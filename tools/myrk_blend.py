"""
Myrkfell — build the world v2 .blend from the macro grids.

    blender -b -P tools/myrk_blend.py               # headless
    (or paste into Blender's console / run through the MCP addon)

Reads assets/terrain/macro/maine_macro.npz + places.json (tools/myrkgen.py)
and builds, in a fresh scene:

    Maine_Terrain      361 x 541 verts at 20 m, `Col` vertex colours = ground tint
    Maine_Water        the sea and every lake / pool as one mesh (wet cells only)
    MYRKFELL_MARKERS/  50 CITY_* empties, 30 LAKE_* circles, 18 REGION_* texts,
                       26 PEAK_* cones -- names on, so the viewport is a map
    CAM_Top / CAM_Hero / Sun

Vertical is blend z (Katahdin 1022, sea 0), exactly the convention the recovered
2026-08-27 file used, so tools/maine_map.py's transform still holds.
Saves to ~/Downloads/myrkfell_maine_v2.blend and renders a hero still beside it.
"""

import bpy, json, os, math
import numpy as np

REPO = os.environ.get("MYRK_REPO", os.path.expanduser("~/dark-fantasy-game"))
MACRO = os.path.join(REPO, "assets", "terrain", "macro")
OUT_BLEND = os.path.expanduser("~/Downloads/myrkfell_maine_v2.blend")
OUT_RENDER = os.path.expanduser("~/Downloads/myrkfell_v2_hero.png")
OUT_TOP = os.path.expanduser("~/Downloads/myrkfell_v2_top.png")

PEAKS = [  # name, lon, lat (tools/maine_map.py)
    ("Katahdin", -68.9214, 45.9044), ("Hamlin Peak", -68.9161, 45.9250), ("Sugarloaf", -70.3131, 45.0353),
    ("Crocker Mountain", -70.3806, 45.0272), ("Old Speck", -70.9469, 44.5647), ("Saddleback", -70.5147, 44.9450),
    ("Mount Abraham", -70.3350, 44.9008), ("Bigelow West", -70.3053, 45.1483), ("Bigelow Avery", -70.2872, 45.1461),
    ("North Brother", -69.0011, 45.9628), ("Baldpate", -70.8817, 44.5931), ("White Cap", -69.2586, 45.5647),
    ("Redington", -70.4064, 44.9686), ("Spaulding", -70.3608, 44.9436), ("Snow Mountain", -70.7383, 45.2483),
    ("Boundary Bald", -70.1919, 45.6142), ("Coburn", -70.1256, 45.4694), ("Elephant", -69.5722, 45.5028),
    ("Big Moose", -69.7167, 45.5236), ("Kineo", -69.7333, 45.6800), ("Traveler", -68.8869, 46.0206),
    ("Doubletop", -69.0575, 45.8747), ("Mount Blue", -70.3286, 44.7286), ("Tumbledown", -70.5433, 44.7275),
    ("Battie", -69.0603, 44.2247), ("Cadillac", -68.2247, 44.3528),
]
X_PER_DEG_LON, X_LON_C = 1707.32, 117675.61
Y_PER_DEG_LAT, Y_LAT_C = 2401.36, -108627.68


def ll(lon, lat):
    return X_PER_DEG_LON * lon + X_LON_C, Y_PER_DEG_LAT * lat + Y_LAT_C


def clear():
    # empty the current scene in place (a read_homefile would drop the MCP addon's server)
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.curves, bpy.data.cameras, bpy.data.lights):
        for d in list(coll):
            if d.users == 0:
                coll.remove(d)


def grid_mesh(name, xs, ys, Z, keep=None):
    ny, nx = Z.shape
    verts = np.stack([np.repeat(xs[None, :], ny, 0), np.repeat(ys[:, None], nx, 1), Z], -1).reshape(-1, 3)
    i = np.arange(ny - 1)[:, None] * nx + np.arange(nx - 1)[None, :]
    faces = np.stack([i, i + 1, i + nx + 1, i + nx], -1).reshape(-1, 4)
    if keep is not None:
        k = keep[:-1, :-1] & keep[1:, :-1] & keep[:-1, 1:] & keep[1:, 1:]
        faces = faces[k.reshape(-1)]
    me = bpy.data.meshes.new(name)
    me.vertices.add(len(verts))
    me.vertices.foreach_set("co", verts.astype(np.float32).reshape(-1))
    me.loops.add(len(faces) * 4)
    me.loops.foreach_set("vertex_index", faces.astype(np.int32).reshape(-1))
    me.polygons.add(len(faces))
    me.polygons.foreach_set("loop_start", (np.arange(len(faces)) * 4).astype(np.int32))
    me.polygons.foreach_set("loop_total", np.full(len(faces), 4, np.int32))
    me.update(calc_edges=True)
    me.validate()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def material(name, rgba, vcol=False, alpha=1.0, rough=0.9):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Roughness"].default_value = rough
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        for attr, val in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
            try:
                setattr(m, attr, val)
                break
            except Exception:
                pass
    if vcol:
        n = nt.nodes.new("ShaderNodeVertexColor")
        n.layer_name = "Col"
        nt.links.new(n.outputs["Color"], bsdf.inputs["Base Color"])
    return m


def build():
    clear()
    scn = bpy.context.scene
    z = np.load(os.path.join(MACRO, "maine_macro.npz"))
    H, W, C, xs, ys = z["H"], z["W"], z["C"], z["xs"], z["ys"]
    places = json.load(open(os.path.join(MACRO, "places.json")))
    ny, nx = H.shape

    # --- terrain -------------------------------------------------------------
    terr = grid_mesh("Maine_Terrain", xs, ys, H)
    me = terr.data
    col = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    rgba = np.concatenate([C.reshape(-1, 3), np.ones((ny * nx, 1), np.float32)], 1)
    col.data.foreach_set("color", rgba.astype(np.float32).reshape(-1))
    me.materials.append(material("Myrk_Ground", (0.4, 0.5, 0.3, 1), vcol=True))
    me.polygons.foreach_set("use_smooth", np.ones(len(me.polygons), bool))

    # --- water: wet cells only, at their surface ------------------------------
    wet = W > -100.0
    water = grid_mesh("Maine_Water", xs, ys, np.where(wet, W, -200.0).astype(np.float32), keep=wet)
    water.data.materials.append(material("Myrk_Water", (0.12, 0.35, 0.55, 1), alpha=0.85, rough=0.15))
    water.data.polygons.foreach_set("use_smooth", np.ones(len(water.data.polygons), bool))

    # --- markers ------------------------------------------------------------------
    coll = bpy.data.collections.new("MYRKFELL_MARKERS")
    scn.collection.children.link(coll)

    def hz(x, y):
        cx = int(np.clip(round((x - xs[0]) / 20.0), 0, nx - 1))
        cy = int(np.clip(round((y - ys[0]) / 20.0), 0, ny - 1))
        return float(max(H[cy, cx], W[cy, cx]))

    def marker(name, x, y, zz, kind, size):
        if kind == "cone":
            bpy.ops.mesh.primitive_cone_add(radius1=size, depth=size * 2.5, location=(x, y, zz + size * 1.2))
            ob = bpy.context.active_object
        elif kind == "circle":
            bpy.ops.mesh.primitive_circle_add(radius=size, location=(x, y, zz + 2))
            ob = bpy.context.active_object
        elif kind == "text":
            cu = bpy.data.curves.new(name, "FONT")
            cu.body = name.split("_", 1)[1].replace("_", " ")
            cu.size = size
            cu.align_x = "CENTER"
            ob = bpy.data.objects.new(name, cu)
            ob.location = (x, y, zz + 40)
            scn.collection.objects.link(ob)
        else:
            ob = bpy.data.objects.new(name, None)
            ob.empty_display_type = "SPHERE"
            ob.empty_display_size = size
            ob.location = (x, y, zz + size)
            scn.collection.objects.link(ob)
        ob.name = name
        ob.show_name = True
        for c in list(ob.users_collection):
            c.objects.unlink(ob)
        coll.objects.link(ob)
        return ob

    for c in places["cities"]:
        marker("CITY_" + c["name"], c["x"], c["y"], hz(c["x"], c["y"]), "empty", c["dim"][0] / 4.0)
    for l in places["lakes"]:
        marker("LAKE_" + l["name"], l["x"], l["y"], l["z"], "circle", max(l["dim"][0], l["dim"][1]) / 2.0)
    for r in places["regions"]:
        marker("REGION_" + r["name"], r["x"], r["y"], hz(r["x"], r["y"]), "text", 140.0)
    for name, lon, lat in PEAKS:
        x, y = ll(lon, lat)
        marker("PEAK_" + name, x, y, hz(x, y), "cone", 45.0)
    for ob in coll.objects:
        ob.hide_render = True

    # --- box, cameras, sun, world ---------------------------------------------------------
    bpy.ops.object.empty_add(type="CUBE", location=(0, 0, 500))
    box = bpy.context.active_object
    box.name = "WORLD_BOUNDS"
    box.scale = (3600, 5400, 500)

    cam = bpy.data.cameras.new("CAM_Top")
    cam.type = "ORTHO"
    cam.ortho_scale = 11000
    cam.clip_end = 20000
    top = bpy.data.objects.new("CAM_Top", cam)
    top.location = (0, 0, 6000)
    scn.collection.objects.link(top)

    cam2 = bpy.data.cameras.new("CAM_Hero")
    cam2.lens = 32
    cam2.clip_end = 40000
    hero = bpy.data.objects.new("CAM_Hero", cam2)
    hero.location = (-2400, -8600, 2600)              # over the Gulf, looking up the state
    hero.rotation_euler = (math.radians(70), 0, math.radians(-12))
    scn.collection.objects.link(hero)
    scn.camera = hero

    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 3.0
    sun.angle = math.radians(3)
    so = bpy.data.objects.new("Sun", sun)
    so.rotation_euler = (math.radians(50), math.radians(15), math.radians(-40))
    scn.collection.objects.link(so)

    scn.world = bpy.data.worlds.new("Sky")
    scn.world.use_nodes = True
    scn.world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.7, 0.9, 1)
    scn.world.node_tree.nodes["Background"].inputs[1].default_value = 0.45

    for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scn.render.engine = eng
            break
        except Exception:
            pass
    scn.render.resolution_x, scn.render.resolution_y = 1920, 1080
    scn.render.film_transparent = False
    try:
        scn.view_settings.view_transform = "AgX"
        scn.view_settings.look = "AgX - Medium High Contrast"
    except Exception:
        pass

    scn.view_settings.exposure = -0.6
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
    return {"blend": OUT_BLEND, "verts": ny * nx, "water_faces": len(water.data.polygons),
            "markers": len(coll.objects), "zmax": float(H.max())}


def render(which="hero"):
    scn = bpy.context.scene
    scn.camera = bpy.data.objects["CAM_Hero" if which == "hero" else "CAM_Top"]
    scn.render.filepath = OUT_RENDER if which == "hero" else OUT_TOP
    if which == "top":
        scn.render.resolution_x, scn.render.resolution_y = 1200, 1800
    bpy.ops.render.render(write_still=True)
    return scn.render.filepath


if __name__ == "__main__" or bpy.app.background:
    info = build()
    print(info)
    render("hero")
    render("top")
