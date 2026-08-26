# ---------------------------------------------------------------------------
# tools/psxgen.py  (docs/TREES_v3_PSX.md §1)
#
#   pip install bpy            # needs python 3.11
#   python3 -S tools/psxgen.py # -S matters: bpy aborts if google-glog was
#                              # already initialised by another module (cv2)
#
# Env: PSX_BLEND (the pack's .blend), PSX_OUT (where the GLBs land).
#
# tools/psxgen.py  --  PSX Nature & Biomes  ->  Myrkfell GLB set
#
# Two things this does that a plain FBX->GLB convert does not:
#
#  1. Splits every mesh into a `Trunk` (opaque wood) and `Foliage` (alpha-cut
#     cards) child, so TreeV2 can carve one and shed the other.
#  2. Ships a SECOND, subdivided trunk per choppable tree (`<name>_chop.glb`).
#     The pack's trunks are 4-8 sided tubes with no rings through the chop
#     band -- there is nothing there to carve a notch out of. Rather than make
#     420 standing trees pay for geometry only the one being chopped needs,
#     the dense trunk is a separate file swapped in on the first axe bite.
# ---------------------------------------------------------------------------
import bpy, bmesh, json, os
from mathutils import Vector

BLEND = os.environ.get("PSX_BLEND",
    os.path.expanduser("~/Downloads/PSX Nature & Biomes/PSX Nature.blend"))
OUT   = os.environ.get("PSX_OUT", "assets/psx_nature/glb")
BAND  = (0.28, 2.20)   # the chop window, once every stage scale is accounted for
CUTS  = 3

CHOPPABLE = {"SM_Tree_01","SM_Tree_02","SM_BareTree_01","SM_BareTree_02",
             "SM_Pine_01","SM_Pine_02","SM_Pine_03","SM_Pine_04","SM_Pine_05","SM_Pine_06",
             "SM_BarePine_01","SM_BarePine_02","SM_GiantPine_01","SM_GiantPine_02"}
SKIP = {"Plano.007"}

def atlas_of(matname):
    for a in ("GiantPine", "Trees", "Props"):
        if f"_{a}" in matname: return a
    return "Props"

def export(objs, path):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True,
                              export_yup=True, export_apply=True, export_materials='EXPORT',
                              export_image_format='NONE', export_vertex_color='ACTIVE',
                              export_extras=False)

def part_object(me, name, idxs, atlas, part):
    bm = bmesh.new(); bm.from_mesh(me)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index not in idxs], context='FACES')
    if not bm.faces:
        bm.free(); return None, 0
    nm = bpy.data.meshes.new(f"{name}_{part}")
    bm.to_mesh(nm); bm.free()
    nm.materials.clear()
    key = f"PSX{part}_{atlas}"
    nm.materials.append(bpy.data.materials.get(key) or bpy.data.materials.new(key))
    for p in nm.polygons: p.material_index = 0
    ob = bpy.data.objects.new(part, nm)
    bpy.context.scene.collection.objects.link(ob)
    return ob, sum(len(p.vertices) - 2 for p in nm.polygons)

bpy.ops.wm.open_mainfile(filepath=BLEND)
os.makedirs(OUT, exist_ok=True)
src_names = sorted(o.name for o in bpy.data.objects if o.type == 'MESH' and o.name not in SKIP)
manifest = {}

for name in src_names:
    bpy.ops.wm.open_mainfile(filepath=BLEND)
    src = bpy.data.objects[name]
    for o in list(bpy.data.objects):
        if o is not src: bpy.data.objects.remove(o, do_unlink=True)
    bpy.context.view_layer.objects.active = src; src.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    me = src.data
    atlas = atlas_of(src.material_slots[0].material.name)
    used = {p.material_index for p in me.polygons}
    wood_idx = {i for i, ms in enumerate(src.material_slots)
                if i in used and ms.material and not ms.material.name.endswith("_Foliage")}
    fol_idx = used - wood_idx

    # ---- sit it on the ground, centred on its own trunk -------------------
    zmin = min(v.co.z for v in me.vertices)
    pick = wood_idx if wood_idx else used
    low = [me.vertices[i].co for p in me.polygons if p.material_index in pick
           for i in p.vertices if me.vertices[i].co.z < zmin + 0.35]
    cx = sum(c.x for c in low) / len(low); cy = sum(c.y for c in low) / len(low)
    for v in me.vertices: v.co -= Vector((cx, cy, zmin))

    height = max(v.co.z for v in me.vertices)
    fz = [me.vertices[i].co.z for p in me.polygons if p.material_index in fol_idx for i in p.vertices]

    if not me.color_attributes:
        me.color_attributes.new(name="Color", type='BYTE_COLOR', domain='CORNER')
        for d in me.color_attributes["Color"].data: d.color = (1.0, 1.0, 1.0, 1.0)

    # ---- the lean model that 420 standing trees actually use --------------
    root = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(root)
    keep = [root]
    tris = {}
    for part, idxs in (("Trunk", wood_idx), ("Foliage", fol_idx)):
        ob, t = part_object(me, name, idxs, atlas, part)
        if ob: ob.parent = root; keep.append(ob); tris[part] = t
    bpy.data.objects.remove(src, do_unlink=True)
    export(keep, f"{OUT}/{name}.glb")

    # ---- the dense trunk, swapped in on the first bite --------------------
    chop_tris = 0; radius = 0.0; profile = []
    if name in CHOPPABLE and wood_idx:
        base = [me.vertices[i].co for p in me.polygons if p.material_index in wood_idx
                for i in p.vertices if me.vertices[i].co.z < 0.30]
        reach = max((c.xy.length for c in base), default=0.5) * 1.6 + 0.15
        bm = bmesh.new(); bm.from_mesh(me); bm.faces.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index not in wood_idx],
                         context='FACES')
        want = [f for f in bm.faces
                if max(v.co.z for v in f.verts) > BAND[0] and min(v.co.z for v in f.verts) < BAND[1]
                and sum(v.co.xy.length for v in f.verts) / len(f.verts) < reach]
        if want:
            bmesh.ops.subdivide_edges(bm, edges=list({e for f in want for e in f.edges}),
                                      cuts=CUTS, use_grid_fill=True, use_only_quads=False)
        dm = bpy.data.meshes.new(f"{name}_ChopTrunk")
        bm.to_mesh(dm); bm.free()
        dm.materials.clear()
        dm.materials.append(bpy.data.materials.get(f"PSXTrunk_{atlas}"))
        for p in dm.polygons: p.material_index = 0
        chop_tris = sum(len(p.vertices) - 2 for p in dm.polygons)
        droot = bpy.data.objects.new(name + "_chop", None)
        dob = bpy.data.objects.new("Trunk", dm)
        for o in (droot, dob): bpy.context.scene.collection.objects.link(o)
        dob.parent = droot
        for o in keep: bpy.data.objects.remove(o, do_unlink=True)
        export([droot, dob], f"{OUT}/{name}_chop.glb")

        # radius every 25 cm: the notch must know how fat the trunk is where the
        # chopper's hands actually land, not at one hard-coded height.
        for k in range(13):
            zc = k * 0.25
            near = [v.co for v in dm.vertices if abs(v.co.z - zc) < 0.22 and v.co.xy.length < reach]
            profile.append(round(sum(c.xy.length for c in near) / len(near), 4) if near else 0.0)
        radius = profile[4] or profile[3] or profile[2]

    manifest[name] = dict(atlas=atlas, height=round(height, 3), radius=round(radius, 4),
                          profile=profile, wood=tris.get("Trunk", 0), foliage=tris.get("Foliage", 0),
                          chop_tris=chop_tris, choppable=name in CHOPPABLE,
                          canopy_lo=round(min(fz), 3) if fz else 0.0,
                          canopy_hi=round(max(fz), 3) if fz else 0.0)
    m = manifest[name]
    print(f"{name:<22} h={m['height']:<7} r={m['radius']:<7} lean={m['wood']+m['foliage']:<5} chop={chop_tris}")

json.dump(manifest, open(f"{OUT}/manifest.json", "w"), indent=1, sort_keys=True)
print("LEAN total tris:", sum(m['wood'] + m['foliage'] for m in manifest.values()), "assets:", len(manifest))
