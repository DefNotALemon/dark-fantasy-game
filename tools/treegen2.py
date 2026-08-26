"""Tree generator v2 — The Withering / Myrkfell.  docs/TREES_v2_SPEC.md phases 1-2.

Replaces tools/treegen.py (icosphere blob canopies). Builds five New England species
across five life stages: a real recursive branch skeleton (phyllotaxis / whorls,
apical dominance, gravity droop, light-seeking) with alpha-clipped leaf CARDS taken
from the atlases that tools/leafgen.py generates.

The skeleton half (`build_skeleton`) is deliberately pure Python with no bpy in it —
those are the same numbers the Godot-side generator has to produce, so port that
function, not the mesh code.

Run headless (bpy as a module, no Blender app needed):
    python3 tools/treegen2.py --out assets/trees --leaves assets/trees/leaves

Or inside Blender:
    exec(open('tools/treegen2.py').read())
"""

import argparse
import math
import os
import random

import bpy
import bmesh
from mathutils import Vector, Matrix, Euler

STAGES = ["sapling", "young", "mature", "ancient", "withered"]

## The axe swings low. Rings are packed CHOP_RING apart from the ground up to
## CHOP_ZONE so TreeV2.gd has vertices to carve a notch out of; above that the
## trunk goes back to cheap wide rings. FLARE_H is the root swell.
CHOP_ZONE = 2.6
CHOP_RING = 0.12
FLARE_H = 0.45
GOLDEN = math.radians(137.5)


# ============================================================== profiles
# One dict per species = the TreeProfile resource from spec §2. Everything the
# skeleton needs lives here; nothing is hard-coded in the generator below.

def P(**kw):
    base = dict(
        mode="GOLDEN",          # GOLDEN (hardwood) or WHORL (conifer)
        orders=3,
        heights=[1.1, 3.5, 8.0, 11.0, 8.0],
        radii=[0.030, 0.10, 0.30, 0.46, 0.30],
        wander=0.16,            # trunk lateral drift per metre
        first_branch=0.34,      # fraction of trunk height where branching starts
        top_branch=0.95,
        n_branch=[0, 4, 9, 12, 9],   # order-1 count per stage
        elev=52.0,              # degrees off vertical for order-1
        elev_jit=10.0,
        blen=0.42,              # order-1 length as a fraction of tree height
        dominance=0.62,         # child length = parent * this
        child_n=(3, 4),         # children per branch
        droop=0.30,             # +down
        light=0.42,             # +up at the tip (dip-then-rise when both are on)
        curve=0.55,             # how much of the droop/light plays out along a branch
        whorls=0,               # conifer only
        per_whorl=5,
        leaf_size=(0.26, 0.40),
        leaf_droop=0.35,        # how far a spray sags off its twig axis
        cluster=(2, 3),         # cards per twig
        cross=True,
        bark=(0.150, 0.120, 0.105),
        leaf_atlas="maple",
        season=(0.24, 0.36, 0.18),
    )
    base.update(kw)
    return base


SPECIES = {
    # -------------------------------------------------- hardwoods (GOLDEN)
    "maple": P(
        heights=[1.1, 3.6, 8.2, 11.0, 8.0], radii=[0.030, 0.105, 0.31, 0.47, 0.31],
        elev=50, blen=0.44, droop=0.26, light=0.50, n_branch=[0, 5, 12, 16, 11],
        leaf_atlas="maple", season=(0.24, 0.36, 0.18), bark=(0.145, 0.120, 0.105),
        leaf_size=(0.20, 0.29), cluster=(2, 3), leaf_droop=0.36,
    ),
    "birch": P(
        heights=[1.0, 4.2, 10.0, 13.5, 9.5], radii=[0.022, 0.075, 0.20, 0.29, 0.20],
        wander=0.10, elev=34, blen=0.30, droop=0.55, light=0.18, curve=0.75,
        n_branch=[0, 6, 14, 18, 12], child_n=(3, 4), first_branch=0.42,
        leaf_atlas="birch", season=(0.31, 0.43, 0.21), bark=(0.66, 0.66, 0.62),
        leaf_size=(0.15, 0.22), cluster=(2, 4), leaf_droop=0.60,   # birch weeps
    ),
    "oak": P(
        heights=[1.0, 3.2, 7.6, 10.5, 7.6], radii=[0.032, 0.125, 0.39, 0.58, 0.39],
        wander=0.24, elev=70, elev_jit=14, blen=0.50, droop=0.34, light=0.62,
        curve=0.45, n_branch=[0, 5, 11, 14, 10], child_n=(3, 4), first_branch=0.30,
        leaf_atlas="oak", season=(0.19, 0.29, 0.15), bark=(0.125, 0.105, 0.092),
        leaf_size=(0.21, 0.30), cluster=(2, 3), leaf_droop=0.32,
    ),
    # --------------------------------------------------- conifers (WHORL)
    "pine": P(
        mode="WHORL", orders=2,
        heights=[1.3, 5.0, 14.0, 20.0, 13.0], radii=[0.022, 0.085, 0.27, 0.43, 0.27],
        wander=0.05, first_branch=0.30, top_branch=0.97,
        whorls=[0, 3, 7, 9, 6], per_whorl=5,
        elev=84, elev_jit=6, blen=0.30, droop=0.10, light=0.22, curve=0.6,
        dominance=0.5, child_n=(2, 3),
        leaf_atlas="pine", season=(0.19, 0.31, 0.22), bark=(0.135, 0.105, 0.088),
        leaf_size=(0.26, 0.36), cluster=(2, 3), leaf_droop=0.08,   # needles sweep out, not down
    ),
    "fir": P(
        mode="WHORL", orders=2,
        heights=[1.0, 3.8, 10.5, 15.0, 10.0], radii=[0.020, 0.070, 0.21, 0.31, 0.21],
        wander=0.03, first_branch=0.06, top_branch=0.96,
        whorls=[0, 5, 12, 16, 10], per_whorl=7,
        elev=78, elev_jit=7, blen=0.36, droop=0.42, light=0.10, curve=0.7,
        dominance=0.48, child_n=(2, 3),
        leaf_atlas="fir", season=(0.17, 0.29, 0.22), bark=(0.115, 0.100, 0.092),
        leaf_size=(0.19, 0.27), cluster=(2, 3), leaf_droop=0.24,
    ),
}


# ============================================== skeleton (pure python — port me)

class Seg:
    """One tapered tube section of wood. `tag` = which order-1 branch owns it
    (-1 = the trunk itself). Gameplay limbs the tree by tag, so this has to be
    carried all the way through to the exported object names."""
    __slots__ = ("a", "b", "ra", "rb", "order", "tag")

    def __init__(self, a, b, ra, rb, order, tag=-1):
        self.a, self.b, self.ra, self.rb, self.order = a, b, ra, rb, order
        self.tag = tag


class Twig:
    """Where leaf cards get hung: a point, the direction the twig runs, and the
    order-1 branch that owns it."""
    __slots__ = ("p", "d", "tag")

    def __init__(self, p, d, tag=-1):
        self.p, self.d, self.tag = p, d, tag


def _grow(segs, twigs, prof, rng, start, direction, length, radius, order, stage, tag=-1):
    """One branch: walk it out in steps, bending under gravity and toward light."""
    n = max(2, int(4 - order))
    p = Vector(start)
    d = Vector(direction).normalized()
    step = length / n

    for i in range(n):
        f = (i + 1) / n
        # dip early, lift late — the oak/maple signature. Conifers just sag.
        bend = (-prof["droop"] * (1.0 - f) + prof["light"] * (f - 0.30) * 1.7) * prof["curve"]
        d = (d + Vector((0, 0, bend)) * 0.6
             + Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0)) * 0.10).normalized()
        q = p + d * step
        ra = radius * (1 - 0.80 * (i / n) ** 0.85)
        rb = radius * (1 - 0.80 * ((i + 1) / n) ** 0.85)
        segs.append(Seg(p.copy(), q.copy(), ra, rb, order, tag))
        # leaves hang off the outer reaches of the last two orders, not just the
        # very tip — tip-only placement gives you pom-poms on bare sticks
        if order >= prof["orders"] - 1 and i >= n - 2:
            twigs.append(Twig(q.copy(), d.copy(), tag))
        p = q

    if order >= prof["orders"]:
        twigs.append(Twig(p.copy(), d.copy(), tag))
        return

    # children, spread by the golden angle around the parent axis
    kids = rng.randint(*prof["child_n"])
    axis = d
    ref = Vector((0, 0, 1)).cross(axis)
    if ref.length < 1e-4:
        ref = Vector((1, 0, 0))
    ref.normalize()
    for k in range(kids):
        t = 0.35 + 0.6 * (k + rng.uniform(0, 0.6)) / max(kids, 1)
        base = Vector(start).lerp(p, t)
        roll = GOLDEN * (k + 1) + rng.uniform(-0.4, 0.4)
        side = (ref * math.cos(roll) + axis.cross(ref) * math.sin(roll)).normalized()
        out = math.radians(rng.uniform(34, 58))
        nd = (axis * math.cos(out) + side * math.sin(out)).normalized()
        _grow(segs, twigs, prof, rng, base, nd,
              length * prof["dominance"] * rng.uniform(0.82, 1.10),
              radius * 0.52, order + 1, stage, tag)
    twigs.append(Twig(p.copy(), d.copy(), tag))


def build_skeleton(prof, stage, seed):
    """Trunk + branches for one tree. Returns (segments, twigs, height, branch_bases).\n\n    Every Seg/Twig carries `.tag`: -1 for the trunk, otherwise the index of the\n    order-1 branch it hangs off. That mapping is the whole basis of limbing."""
    rng = random.Random(seed)
    H = prof["heights"][stage]
    R = prof["radii"][stage]
    segs, twigs, bases = [], [], []

    # ---- trunk: a wandering spine with a root flare at the bottom
    taper = 0.86 if prof["mode"] == "WHORL" else 0.74       # conifers keep a leader

    def trunk_r(y):
        """Radius at height y, including the root flare near the ground."""
        base = R * (1 - taper * min(y / H, 1.0) ** 0.9)
        if y < FLARE_H:
            base = base + (R * 0.5) * (1.0 - y / FLARE_H) ** 1.6
        return max(base, R * 0.06)

    # Ring heights: DENSE through the chopping zone, coarse above it. The axe
    # carves the notch by pushing these rings' vertices inward at runtime, so
    # there has to be real geometry down where a chopper swings.
    ys = []
    y = 0.0
    while y < min(CHOP_ZONE, H * 0.72):
        ys.append(y)
        y += CHOP_RING
    while y < H:
        ys.append(y)
        y += max(H / 7.0, CHOP_RING)
    ys.append(H)

    pts = []
    lateral = Vector((0, 0, 0))
    prev_y = 0.0
    for yy in ys:
        dz = yy - prev_y
        w = prof["wander"] * dz * (0.3 if yy < FLARE_H else 1.0)
        lateral = lateral + Vector((rng.uniform(-w, w), rng.uniform(-w, w), 0))
        pts.append(Vector((lateral.x, lateral.y, yy)))
        prev_y = yy
    for i in range(len(pts) - 1):
        segs.append(Seg(pts[i], pts[i + 1], trunk_r(ys[i]), trunk_r(ys[i + 1]), 0))
    n = len(pts) - 1

    def on_trunk(f):
        """Point at fraction f of the trunk's HEIGHT (rings are not uniform)."""
        target = min(max(f, 0.0), 0.999) * H
        for i in range(len(pts) - 1):
            if pts[i + 1].z >= target:
                span = max(pts[i + 1].z - pts[i].z, 1e-5)
                return pts[i].lerp(pts[i + 1], (target - pts[i].z) / span)
        return pts[-1]

    if stage == 0:                      # saplings are a stem and a few leaves
        for _ in range(3):
            twigs.append(Twig(on_trunk(rng.uniform(0.55, 1.0)), Vector((0, 0, 1)), -1))
        return segs, twigs, H, bases

    lo, hi = prof["first_branch"], prof["top_branch"]

    if prof["mode"] == "WHORL":
        # ---- conifer: rings of branches, longest at the bottom -> cone
        rings = prof["whorls"][stage]
        for w in range(rings):
            f = lo + (hi - lo) * (w / max(rings - 1, 1))
            base = on_trunk(f)
            taper = (1.0 - f) ** 0.75
            roll0 = GOLDEN * w
            for k in range(prof["per_whorl"]):
                az = roll0 + 2 * math.pi * k / prof["per_whorl"] + rng.uniform(-0.15, 0.15)
                el = math.radians(prof["elev"] + rng.uniform(-1, 1) * prof["elev_jit"])
                d = Vector((math.cos(az) * math.sin(el), math.sin(az) * math.sin(el),
                            math.cos(el)))
                _grow(segs, twigs, prof, rng, base, d,
                      H * prof["blen"] * taper * rng.uniform(0.85, 1.15),
                      R * 0.30 * taper + 0.008, 1, stage, tag=len(bases))
                bases.append(base.copy())
    else:
        # ---- hardwood: golden-angle spiral, upper branches favoured
        nb = prof["n_branch"][stage]
        for i in range(nb):
            f = lo + (hi - lo) * (i / max(nb - 1, 1)) ** 0.85 + rng.uniform(-0.03, 0.03)
            base = on_trunk(f)
            az = GOLDEN * i + rng.uniform(-0.30, 0.30)
            el = math.radians(prof["elev"] + rng.uniform(-1, 1) * prof["elev_jit"])
            d = Vector((math.cos(az) * math.sin(el), math.sin(az) * math.sin(el),
                        math.cos(el)))
            # apical dominance: the top of the tree gets the budget
            grade = 0.55 + 0.45 * (f - lo) / max(hi - lo, 1e-3)
            _grow(segs, twigs, prof, rng, base, d,
                  H * prof["blen"] * grade * rng.uniform(0.85, 1.12),
                  R * 0.34 * grade, 1, stage, tag=len(bases))
            bases.append(base.copy())

    if stage == 4:                      # withered: a thin scatter of survivors
        keep = max(3, len(twigs) // 9)
        twigs = rng.sample(twigs, keep) if len(twigs) > keep else twigs
    return segs, twigs, H, bases


# ================================================================ meshing

def _mat_bark(name, rgb):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1.0)
    b.inputs["Roughness"].default_value = 0.92
    return m


def _mat_leaf(name, atlas_path, tint):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(atlas_path, check_existing=True)
    tex.interpolation = "Closest" if False else "Linear"
    mix = nt.nodes.new("ShaderNodeMixRGB")
    mix.blend_type = "MULTIPLY"
    mix.inputs[0].default_value = 1.0
    mix.inputs[2].default_value = (*tint, 1.0)
    nt.links.new(tex.outputs["Color"], mix.inputs[1])
    nt.links.new(mix.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    bsdf.inputs["Roughness"].default_value = 0.78
    # thin, backlit leaves
    ## No transmission: it exports as KHR_materials_transmission, which Godot
    ## cannot render and which turned every leaf material into a magenta error.
    ## Backlighting is the foliage shader's job in-engine.
    m.use_backface_culling = False
    try:
        m.blend_method = "CLIP"
        m.alpha_threshold = 0.5
        m.shadow_method = "CLIP"
    except (AttributeError, TypeError):
        pass                      # Blender 4.2+ dropped these; Cycles clips anyway
    return m


def _chains(segs):
    """Split a run of segments into connected chains (a.b == next.a)."""
    out = []
    cur = []
    for sg in segs:
        if cur and (cur[-1].b - sg.a).length > 1e-5:
            out.append(cur)
            cur = []
        cur.append(sg)
    if cur:
        out.append(cur)
    return out


def _tube(bm, uvl, chain, o):
    """Bridge one chain of segments into a single watertight tube."""
    sides = (12, 5, 4, 3)[min(chain[0].order, 3)]
    pts = [chain[0].a] + [sg.b for sg in chain]
    radii = [chain[0].ra] + [sg.rb for sg in chain]
    dirs = []
    for i, sg in enumerate(chain):
        d = sg.b - sg.a
        dirs.append(d.normalized() if d.length > 1e-6 else Vector((0, 0, 1)))
    if not dirs:
        return

    rings = []
    for i, p in enumerate(pts):
        # the ring at a joint faces the AVERAGE of the two segments meeting there
        if i == 0:
            d = dirs[0]
        elif i >= len(dirs):
            d = dirs[-1]
        else:
            d = (dirs[i - 1] + dirs[i]).normalized()
        rings.append(_ring(bm, p - o, d, max(radii[i], 0.004), sides, 0.0))

    for i in range(len(rings) - 1):
        r0, r1 = rings[i], rings[i + 1]
        # bark UVs in METRES: u around the circumference, v along the limb
        va, vb = (pts[i] - o).length, (pts[i + 1] - o).length
        ca = 2 * math.pi * max(radii[i], 0.004)
        cb = 2 * math.pi * max(radii[i + 1], 0.004)
        for k in range(sides):
            try:
                f = bm.faces.new((r0[k], r0[(k + 1) % sides],
                                  r1[(k + 1) % sides], r1[k]))
                f.material_index = 0
                uvs = [(ca * k / sides, va), (ca * (k + 1) / sides, va),
                       (cb * (k + 1) / sides, vb), (cb * k / sides, vb)]
                for loop, uv in zip(f.loops, uvs):
                    loop[uvl].uv = uv
            except ValueError:
                pass


def _ring(bm, c, d, r, sides, roll):
    """A ring of verts around c, facing d.

    The reference axis must be STABLE along a limb. Deriving u from
    UP.cross(d) looks fine until the direction is near-vertical, where the
    cross product collapses and u snaps to whatever the wander happened to be
    that segment — so consecutive rings twist relative to each other and the
    weld pass can't join them. With rings 12 cm apart that turned the trunk
    into a stack of loose bands with gaps you could see the sky through.
    """
    d = Vector(d).normalized()
    ref = Vector((1.0, 0.0, 0.0))
    if abs(d.dot(ref)) > 0.9:
        ref = Vector((0.0, 1.0, 0.0))
    u = (ref - d * ref.dot(d)).normalized()
    v = d.cross(u)
    return [bm.verts.new(c + (u * math.cos(a + roll) + v * math.sin(a + roll)) * r)
            for a in [2 * math.pi * i / sides for i in range(sides)]]


def build_mesh(name, segs, twigs, prof, atlas_dir, rng):
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")

    # ---- wood
    for chain in _chains(segs):
        _tube(bm, uvl, chain, Vector((0, 0, 0)))
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.0009)
    n_wood = len(bm.faces)

    # ---- leaf cards: quads (crossed on the bigger trees) at every twig
    lo, hi = prof["leaf_size"]
    cards = 0
    for t in twigs:
        for _ in range(rng.randint(*prof["cluster"])):
            size = rng.uniform(lo, hi)
            # A leaf spray GROWS OUT OF ITS TWIG. The card's long axis is the
            # twig's own direction plus a little gravity droop, and the base of
            # the spray sits exactly at the twig tip -- the atlas cells are drawn
            # with the stem at the bottom edge, so -v is the attachment point.
            # Before this the card's up-axis was world +Z, so every spray in the
            # canopy stood bolt upright like grass.
            d = Vector(t.d).normalized()
            grow = (d + Vector((rng.uniform(-0.18, 0.18), rng.uniform(-0.18, 0.18),
                                -prof["leaf_droop"] + rng.uniform(-0.10, 0.10)))).normalized()
            side = grow.cross(Vector((0.0, 0.0, 1.0)))
            if side.length < 1e-4:
                side = Vector((1.0, 0.0, 0.0))
            side.normalize()
            roll = rng.uniform(0, math.tau)
            u1 = (side * math.cos(roll) + grow.cross(side) * math.sin(roll)) * size
            v = grow * size
            centre = t.p + grow * size * 0.92 + side * rng.uniform(-0.08, 0.08) * size
            for plane in range(2 if prof["cross"] else 1):
                u = u1 if plane == 0 else grow.cross(u1)
                vs = [bm.verts.new(centre - u - v), bm.verts.new(centre + u - v),
                      bm.verts.new(centre + u + v), bm.verts.new(centre - u + v)]
                f = bm.faces.new(vs)
                f.material_index = 1
                cell = rng.randrange(8)               # spray cells only (rows 0-1)
                c0 = (cell % 4) * 0.25
                r0c = 1.0 - (cell // 4 + 1) * 0.25
                for loop, uv in zip(f.loops, [(c0, r0c), (c0 + 0.25, r0c),
                                              (c0 + 0.25, r0c + 0.25), (c0, r0c + 0.25)]):
                    loop[uvl].uv = uv
                cards += 1

    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    # wood smooth-shaded, leaf cards flat: piecewise-linear tapers under flat
    # shading turn every segment join into a bamboo ring
    for p in me.polygons:
        p.use_smooth = (p.material_index == 0)
    me.materials.append(_mat_bark("bark_" + name.split("_")[1], prof["bark"]))
    me.materials.append(_mat_leaf(
        "leaf_" + prof["leaf_atlas"],
        os.path.join(atlas_dir, "%s_leaf_atlas.png" % prof["leaf_atlas"]),
        prof["season"]))
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    return ob, dict(tris=tris, cards=cards, wood_faces=n_wood)


def make_tree(species, stage, seed, atlas_dir, leafless=False):
    prof = SPECIES[species]
    segs, twigs, H, _bases = build_skeleton(prof, stage, seed)
    if leafless:
        twigs = []
    rng = random.Random(seed ^ 0x5EED)
    name = "tree_%s_%d_%s" % (species, stage, STAGES[stage])
    ob, stats = build_mesh(name, segs, twigs, prof, atlas_dir, rng)
    stats["h"] = round(H, 2)
    return ob, stats



# ---------------------------------------------------- split export (limbing)

def _part_mesh(name, segs, twigs, prof, atlas_dir, rng, origin):
    """One gameplay part — the trunk, or one order-1 branch and everything it
    carries — with its verts relative to `origin` so the object can be rotated
    about its own base when the axe takes it off."""
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    o = Vector(origin)

    for chain in _chains(segs):
        _tube(bm, uvl, chain, o)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.0009)

    lo, hi = prof["leaf_size"]
    cards = 0
    for t in twigs:
        for _ in range(rng.randint(*prof["cluster"])):
            size = rng.uniform(lo, hi)
            # A leaf spray GROWS OUT OF ITS TWIG. The card's long axis is the
            # twig's own direction plus a little gravity droop, and the base of
            # the spray sits exactly at the twig tip -- the atlas cells are drawn
            # with the stem at the bottom edge, so -v is the attachment point.
            # Before this the card's up-axis was world +Z, so every spray in the
            # canopy stood bolt upright like grass.
            d = Vector(t.d).normalized()
            grow = (d + Vector((rng.uniform(-0.18, 0.18), rng.uniform(-0.18, 0.18),
                                -prof["leaf_droop"] + rng.uniform(-0.10, 0.10)))).normalized()
            side = grow.cross(Vector((0.0, 0.0, 1.0)))
            if side.length < 1e-4:
                side = Vector((1.0, 0.0, 0.0))
            side.normalize()
            roll = rng.uniform(0, math.tau)
            u1 = (side * math.cos(roll) + grow.cross(side) * math.sin(roll)) * size
            v = grow * size
            centre = (t.p - o) + grow * size * 0.92 + side * rng.uniform(-0.08, 0.08) * size
            for plane in range(2 if prof["cross"] else 1):
                u = u1 if plane == 0 else grow.cross(u1)
                vs = [bm.verts.new(centre - u - v), bm.verts.new(centre + u - v),
                      bm.verts.new(centre + u + v), bm.verts.new(centre - u + v)]
                f = bm.faces.new(vs)
                f.material_index = 1
                cell = rng.randrange(8)               # spray cells only (rows 0-1)
                c0 = (cell % 4) * 0.25
                r0c = 1.0 - (cell // 4 + 1) * 0.25
                for loop, uv in zip(f.loops, [(c0, r0c), (c0 + 0.25, r0c),
                                              (c0 + 0.25, r0c + 0.25), (c0, r0c + 0.25)]):
                    loop[uvl].uv = uv
                cards += 1

    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for pg in me.polygons:
        pg.use_smooth = (pg.material_index == 0)
    me.materials.append(_mat_bark("bark_" + prof["leaf_atlas"], prof["bark"]))
    me.materials.append(_mat_leaf("leaf_" + prof["leaf_atlas"],
                                  os.path.join(atlas_dir, "%s_leaf_atlas.png" % prof["leaf_atlas"]),
                                  prof["season"]))
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = o
    tris = sum(len(pg.vertices) - 2 for pg in me.polygons)
    return ob, tris, cards


def build_split(species, stage, seed, atlas_dir):
    """A tree as SEPARATE gameplay objects: Trunk + Branch_00..NN, each with its
    own origin. TreeV2.gd walks these names; do not rename them casually."""
    prof = SPECIES[species]
    segs, twigs, H, bases = build_skeleton(prof, stage, seed)
    rng = random.Random(seed ^ 0x5EED)

    root = bpy.data.objects.new("tree_%s_%d_%s" % (species, stage, STAGES[stage]), None)
    bpy.context.scene.collection.objects.link(root)

    parts, tris, cards = [], 0, 0
    groups = {}
    for sg in segs:
        groups.setdefault(sg.tag, ([], []))[0].append(sg)
    for tw in twigs:
        groups.setdefault(tw.tag, ([], []))[1].append(tw)

    for tag in sorted(groups):
        sgs, tws = groups[tag]
        # The gameplay side needs each limb's real thickness to set its HP.
        # Reading it back off the mesh AABB guesses badly (a long branch has a
        # big bounding box), so the true tube radius rides in the NAME:
        #   Branch_03_r085  ->  0.085 m.  TreeBranch.gd parses it.
        if tag == -1:
            name = "Trunk"
        else:
            r0 = max((sg.ra for sg in sgs if sg.order == 1), default=0.05)
            name = "Branch_%02d_r%03d" % (tag, int(round(r0 * 1000)))
        origin = Vector((0, 0, 0)) if tag == -1 else bases[tag]
        ob, t, c = _part_mesh(name, sgs, tws, prof, atlas_dir, rng, origin)
        ob.parent = root
        parts.append(ob)
        tris += t
        cards += c
    return root, parts, dict(tris=tris, cards=cards, h=round(H, 2), branches=len(bases))


# =============================================================== rendering

def scene_reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def setup_world(sun_energy=3.2):
    sc = bpy.context.scene
    w = bpy.data.worlds.new("World")
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.055, 0.070, 0.105, 1)
    bg.inputs[1].default_value = 1.5

    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sc.collection.objects.link(sun)
    sun.data.energy = sun_energy
    sun.data.color = (1.0, 0.86, 0.70)
    sun.data.angle = math.radians(3.0)
    sun.rotation_euler = (math.radians(58), 0, math.radians(38))

    fill = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", "SUN"))
    sc.collection.objects.link(fill)
    fill.data.energy = 0.7
    fill.data.color = (0.55, 0.68, 0.85)
    fill.rotation_euler = (math.radians(115), 0, math.radians(-140))

    gm = bpy.data.meshes.new("Ground")
    gm.from_pydata([(-400, -400, 0), (400, -400, 0), (400, 400, 0), (-400, 400, 0)],
                   [], [(0, 1, 2, 3)])
    gmat = bpy.data.materials.new("ground")
    gmat.use_nodes = True
    gmat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (
        0.055, 0.062, 0.072, 1)
    gmat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
    gm.materials.append(gmat)
    sc.collection.objects.link(bpy.data.objects.new("Ground", gm))


def render(path, width, span, height, samples=20, res=(1400, 720)):
    """Frame the whole lineup: solve the camera distance from the sensor, don't guess."""
    sc = bpy.context.scene
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    lens, sensor = 42.0, 36.0
    cam.data.lens = lens
    aspect = res[1] / res[0]
    half_h_fov = math.atan(sensor / 2 / lens)
    half_v_fov = math.atan(sensor * aspect / 2 / lens)
    margin = 1.12
    need_x = (width * margin / 2) / math.tan(half_h_fov)
    need_y = (height * margin / 2) / math.tan(half_v_fov)
    dist = max(need_x, need_y)
    cam.location = (width * 0.5, -dist, height * 0.50)
    cam.rotation_euler = (math.radians(90), 0, 0)
    sc.camera = cam

    sc.render.engine = "CYCLES"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 4
    sc.cycles.transparent_max_bounces = 12
    sc.render.film_transparent = False
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.filepath = path
    sc.render.image_settings.file_format = "PNG"
    sc.view_settings.look = "AgX - Medium High Contrast" if hasattr(
        sc.view_settings, "look") else "None"
    bpy.ops.render.render(write_still=True)


# =================================================================== main

def stage_line(species, atlas_dir, out_png, leafless=False, seed=991, samples=20):
    """One species, all five stages, left to right."""
    scene_reset()
    setup_world()
    prof = SPECIES[species]
    x, stats, hmax = 0.0, {}, 0.0
    gaps = []
    for s in range(5):
        ob, st = make_tree(species, s, seed + s * 37, atlas_dir, leafless)
        gap = max(2.2, prof["heights"][s] * 0.62)
        x += gap
        ob.location.x = x
        ob.rotation_euler.z = random.Random(seed + s).uniform(0, math.tau)
        gaps.append(x)
        x += gap * 0.55
        hmax = max(hmax, st["h"])
        stats[STAGES[s]] = st
    render(out_png, x, x, hmax * 1.35, samples=samples)
    return stats


def species_lineup(atlas_dir, out_png, stage=2, leafless=False, seed=4242, samples=22):
    """All five species side by side at one stage."""
    scene_reset()
    setup_world()
    x, stats, hmax = 0.0, {}, 0.0
    for i, name in enumerate(SPECIES):
        ob, st = make_tree(name, stage, seed + i * 53, atlas_dir, leafless)
        gap = max(3.0, SPECIES[name]["heights"][stage] * 0.55)
        x += gap
        ob.location.x = x
        ob.rotation_euler.z = random.Random(seed + i).uniform(0, math.tau)
        x += gap * 0.5
        hmax = max(hmax, st["h"])
        stats[name] = st
    render(out_png, x, x, hmax * 1.35, samples=samples)
    return stats


def export_glb(species, stage, atlas_dir, out_dir, seed=991):
    """Exports the SPLIT hierarchy: an empty root with Trunk + Branch_NN children.
    TreeV2.gd walks those child names to build the limbing model — renaming them
    here breaks chopping in-game."""
    scene_reset()
    root, parts, st = build_split(species, stage, seed, atlas_dir)
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for pt in parts:
        pt.select_set(True)
    bpy.context.view_layer.objects.active = root
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "%s_%d_%s.glb" % (species, stage, STAGES[stage]))
    # textures stay out of the GLB: the leaf atlas is one shared file in
    # assets/trees/leaves, not 25 embedded copies of the same PNG
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True,
                              export_format="GLB", export_yup=True,
                              export_image_format="NONE")
    return path, st


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="assets/trees")
    ap.add_argument("--leaves", default="assets/trees/leaves")
    ap.add_argument("--previews", default=None)
    ap.add_argument("--samples", type=int, default=20)
    ap.add_argument("--glb", action="store_true", help="also export GLBs")
    ap.add_argument("--only", default=None, help="one species")
    args = ap.parse_args()

    prev = args.previews or os.path.join(args.out, "previews")
    os.makedirs(prev, exist_ok=True)

    names = [args.only] if args.only else list(SPECIES)

    print("== species lineup (mature) ==")
    st = species_lineup(args.leaves, os.path.join(prev, "trees_species_mature.png"),
                        stage=2, samples=args.samples)
    for k, v in st.items():
        print("  %-6s h=%5.1fm tris=%6d cards=%4d" % (k, v["h"], v["tris"], v["cards"]))

    print("== species lineup (bark only) ==")
    species_lineup(args.leaves, os.path.join(prev, "trees_silhouettes.png"),
                   stage=3, leafless=True, samples=max(8, args.samples // 2))

    for n in names:
        print("== %s stage line ==" % n)
        st = stage_line(n, args.leaves,
                        os.path.join(prev, "trees_%s_line.png" % n), samples=args.samples)
        for k, v in st.items():
            print("  %-8s h=%5.1fm tris=%6d cards=%4d" % (k, v["h"], v["tris"], v["cards"]))

    if args.glb:
        gdir = os.path.join(args.out, "glb")
        for n in names:
            for s in range(5):
                p, v = export_glb(n, s, args.leaves, gdir)
                print("glb %-34s tris=%6d" % (os.path.basename(p), v["tris"]))

    print("previews ->", prev)


if __name__ == "__main__":
    main()
