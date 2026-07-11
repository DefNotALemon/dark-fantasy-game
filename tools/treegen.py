"""Tree generator for The Withering — take 2, one species at a time.
Currently: GNARLED OAK, 5 life stages in a line for review.
Low poly, faceted, flat-shaded. Palette per docs/DESIGN.md: desaturated
slate/indigo base, ember-orange + frost-blue accents. Z-up meters in Blender;
GLB export is Y-up, origin at trunk base.
"""
import bpy, bmesh, math, random
from mathutils import Vector, Matrix

STAGES = ["sapling", "young", "mature", "ancient", "withered"]
SPACING = 9.0  # line spacing between stages for review

PAL = {
    "bark_oak":     (0.23, 0.185, 0.165),
    "wood_ash":     (0.36, 0.345, 0.33),
    "leaf_oak":     (0.285, 0.345, 0.205),
    "leaf_fresh":   (0.38, 0.48, 0.24),
    "accent_ember": (0.78, 0.30, 0.10),
    "accent_frost": (0.50, 0.63, 0.68),
}


def _mat(name, rgb, rough=0.9, emit=0.0):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    if emit > 0:
        for k in ("Emission Color", "Emission"):
            if k in bsdf.inputs:
                bsdf.inputs[k].default_value = (*rgb, 1.0)
                break
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = emit
    m.diffuse_color = (*rgb, 1.0)
    return m


def leaf_mat(stage_i):
    t = [0.5, 0.25, 0.0, 0.0][min(stage_i, 3)]
    rgb = tuple(b * (1 - t) + f * t for b, f in zip(PAL["leaf_oak"], PAL["leaf_fresh"]))
    if stage_i == 3:
        rgb = tuple(c * 0.8 for c in rgb)  # ancient: darker, colder
    return _mat("leaf_oak_%d" % stage_i, rgb)


class Build:
    """One mesh, face-by-face, per-face material slots."""

    def __init__(self, name, seed):
        self.bm = bmesh.new()
        self.name = name
        self.rng = random.Random(seed)
        self.slots = []
        self._idx = {}

    def slot(self, mat):
        if mat.name not in self._idx:
            self._idx[mat.name] = len(self.slots)
            self.slots.append(mat)
        return self._idx[mat.name]

    def tube(self, pts, radii, sides, mat, cap=True, twist=0.0):
        """Bridged rings along pts; progressive twist for gnarl."""
        si = self.slot(mat)
        rings = []
        a0 = self.rng.uniform(0, math.pi)
        for j, (p, r) in enumerate(zip(pts, radii)):
            ring = []
            for k in range(sides):
                a = a0 + twist * j + 2 * math.pi * k / sides
                ring.append(self.bm.verts.new(p + Vector((math.cos(a) * r, math.sin(a) * r, 0))))
            rings.append(ring)
        for r0, r1 in zip(rings, rings[1:]):
            for k in range(sides):
                f = self.bm.faces.new((r0[k], r0[(k + 1) % sides], r1[(k + 1) % sides], r1[k]))
                f.material_index = si
        if cap:
            for ring, flip in ((rings[0], True), (rings[-1], False)):
                f = self.bm.faces.new(tuple(reversed(ring)) if flip else tuple(ring))
                f.material_index = si

    def blob(self, center, r, mat, squash=1.0, jitter=0.16):
        si = self.slot(mat)
        M = Matrix.Translation(center) @ Matrix.Diagonal((r, r, r * squash, 1.0))
        try:
            ret = bmesh.ops.create_icosphere(self.bm, subdivisions=1, radius=1.0, matrix=M)
        except TypeError:
            ret = bmesh.ops.create_icosphere(self.bm, subdivisions=1, diameter=1.0, matrix=M)
        for v in ret["verts"]:
            v.co += Vector((self.rng.uniform(-1, 1) * r * jitter,
                            self.rng.uniform(-1, 1) * r * jitter,
                            self.rng.uniform(-1, 1) * r * squash * jitter))
        for v in ret["verts"]:
            for f in v.link_faces:
                f.material_index = si

    def quad_leaf(self, center, size, mat):
        si = self.slot(mat)
        n = Vector((self.rng.uniform(-1, 1), self.rng.uniform(-1, 1), self.rng.uniform(0.2, 1))).normalized()
        u = n.orthogonal().normalized() * size
        w = n.cross(u).normalized() * size
        c = Vector(center)
        f = self.bm.faces.new((self.bm.verts.new(c + u), self.bm.verts.new(c + w),
                               self.bm.verts.new(c - u), self.bm.verts.new(c - w)))
        f.material_index = si

    def paint_random_faces(self, mat_from, mat_to, frac):
        src, dst = self.slot(mat_from), self.slot(mat_to)
        for f in [f for f in self.bm.faces if f.material_index == src]:
            if self.rng.random() < frac:
                f.material_index = dst

    def to_object(self, collection):
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.slots:
            me.materials.append(m)
        for p in me.polygons:
            p.use_smooth = False
        ob = bpy.data.objects.new(self.name, me)
        collection.objects.link(ob)
        return ob


# ------------------------------- OAK --------------------------------------

def _trunk(b, H, R, segs, wander, kink, sides, mat, flare=1.6):
    """Gnarled S-curve trunk with a root flare. Returns spine points."""
    pts = [Vector((0, 0, 0))]
    p = Vector((0, 0, 0))
    kink_at = b.rng.randint(max(1, segs // 3), segs - 1) if kink else -1
    for i in range(segs):
        dz = H / segs
        w = wander * (1.7 if i + 1 == kink_at else 1.0) * (0.35 if i == 0 else 1.0)
        p = p + Vector((b.rng.uniform(-w, w) * dz, b.rng.uniform(-w, w) * dz, dz))
        if i + 1 == kink_at:
            p += Vector((b.rng.choice((-1, 1)) * kink * dz, b.rng.uniform(-1, 1) * kink * dz, 0))
        pts.append(p.copy())
    # root flare: insert a squat ring just above the base
    spine = [pts[0], pts[0] + Vector((0, 0, min(0.28, H * 0.09)))] + pts[1:]
    radii = [R * flare, R] + [R * (1 - 0.68 * (i / segs) ** 0.9) for i in range(1, segs + 1)]
    b.tube(spine, radii, sides, mat, twist=b.rng.uniform(0.12, 0.3))
    return pts


def _branch(b, start, ang, length, r0, mat, lift, segs=3, twigs=0, tips=None):
    """Oak branch: dips out, then curls upward at the tip. Optionally twigs."""
    d = Vector((math.cos(ang), math.sin(ang), 0.0))
    pts, p = [Vector(start)], Vector(start)
    for i in range(segs):
        f = (i + 1) / segs
        step = d * (length / segs)
        step.z = length / segs * (lift * (f - 0.35) * 1.8)  # dip then rise
        p = p + step + Vector((b.rng.uniform(-.1, .1), b.rng.uniform(-.1, .1),
                               b.rng.uniform(-.05, .08))) * (length / segs)
        pts.append(p.copy())
    radii = [r0 * (1 - 0.78 * (i / segs) ** 0.85) for i in range(segs + 1)]
    b.tube(pts, radii, 4, mat, twist=0.3)
    if tips is not None:
        tips.append(pts[-1])
    for _ in range(twigs):
        m = pts[b.rng.randint(1, len(pts) - 1)]
        ta = ang + b.rng.uniform(-1.2, 1.2)
        tp = [m, m + Vector((math.cos(ta) * length * 0.3, math.sin(ta) * length * 0.3,
                             length * b.rng.uniform(0.08, 0.22)))]
        b.tube(tp, [r0 * 0.35, r0 * 0.08], 3, mat)
        if tips is not None:
            tips.append(tp[-1])
    return pts[-1]


def build_oak(b, s):
    """Stage s in 0..4: sapling, young, mature, ancient, withered."""
    alive = s < 4
    bark = _mat("bark_oak", PAL["bark_oak"]) if alive else _mat("wood_ash", PAL["wood_ash"])
    leaf = leaf_mat(s)
    H = [0.8, 3.2, 7.5, 9.5, 7.0][s]
    R = [0.04, 0.15, 0.44, 0.68, 0.42][s]
    segs = [3, 4, 5, 5, 5][s]
    wander = [0.14, 0.24, 0.32, 0.4, 0.5][s]
    kink = [0.0, 0.3, 0.6, 0.9, 1.1][s]
    sides = [5, 6, 7, 8, 7][s]
    pts = _trunk(b, H, R, segs, wander, kink, sides, bark, flare=[1.2, 1.35, 1.6, 1.85, 1.7][s])

    # ancient: forked second trunk
    if s == 3:
        fk = pts[2]
        fpts = [fk]
        fp = fk.copy()
        for i in range(3):
            fp = fp + Vector((b.rng.uniform(0.3, 0.7) * b.rng.choice((-1, 1)),
                              b.rng.uniform(-0.5, 0.5), H * 0.14))
            fpts.append(fp.copy())
        b.tube(fpts, [R * 0.62, R * 0.45, R * 0.28, R * 0.12], 6, bark, twist=0.25)

    # branches
    nb = [0, 3, 5, 6, 6][s]
    lift = 0.55 if alive else 1.35          # withered branches claw upward
    blen = H * [0.0, 0.34, 0.38, 0.4, 0.46][s]
    tips = []
    for i in range(nb):
        hfrac = 0.5 + 0.42 * (i / max(nb - 1, 1)) + b.rng.uniform(-0.04, 0.04)
        start = pts[0].lerp(pts[-1], min(hfrac, 0.97))
        ang = i * 2.4 + b.rng.uniform(-0.5, 0.5)  # golden-angle spread, no clumping
        _branch(b, start, ang, blen * b.rng.uniform(0.8, 1.15), R * 0.4, bark,
                lift, twigs=(2 if s >= 2 else 1), tips=tips)

    # canopy
    if alive:
        crown = pts[-1] + Vector((0, 0, H * 0.05))
        cr = H * [0.4, 0.28, 0.32, 0.34, 0][s]
        b.blob(crown, cr, leaf, squash=b.rng.uniform(0.75, 0.9))
        for t in tips:
            c = t.lerp(crown, 0.45)
            b.blob(c, cr * b.rng.uniform(0.55, 0.78), leaf, squash=b.rng.uniform(0.7, 0.9))
        if s == 0:  # sapling: a couple of tender leaf quads low on the stem
            for _ in range(3):
                q = pts[0].lerp(pts[-1], b.rng.uniform(0.4, 0.85))
                b.quad_leaf(q + Vector((b.rng.uniform(-.1, .1), b.rng.uniform(-.1, .1), 0)),
                            0.09, _mat("leaf_fresh", PAL["leaf_fresh"]))
    if s == 3:
        # one bare dead limb + frost lichen on the old bark
        _branch(b, pts[0].lerp(pts[-1], 0.8), b.rng.uniform(0, math.tau),
                blen * 0.8, R * 0.3, _mat("wood_ash", PAL["wood_ash"]), 1.2, twigs=1)
        b.paint_random_faces(bark, _mat("accent_frost", PAL["accent_frost"]), 0.07)
    if s == 4:
        for t in tips[:6]:
            b.quad_leaf(t, 0.14, _mat("accent_ember", PAL["accent_ember"], emit=1.6))


# ----------------------------- assembly ------------------------------------

def get_collection(name):
    col = bpy.data.collections.get(name)
    if not col:
        col = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(col)
    return col


def build_oak_line(base_seed=421):
    col = get_collection("trees_oak")
    for ob in list(col.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    stats = {}
    for s, stage in enumerate(STAGES):
        name = "tree_oak_%d_%s" % (s, stage)
        old = bpy.data.meshes.get(name)
        if old:
            bpy.data.meshes.remove(old)
        b = Build(name, base_seed + s * 17)
        build_oak(b, s)
        ob = b.to_object(col)
        ob.location.x = (s - 2) * SPACING
        stats[name] = {"tris": sum(len(p.vertices) - 2 for p in ob.data.polygons),
                       "h": round(ob.dimensions.z, 1)}
    return stats


def preview(path, res=(880, 420)):
    sc = bpy.context.scene
    for n in ("Cube", "Light"):  # default objects photobomb the lineup
        ob = bpy.data.objects.get(n)
        if ob:
            ob.hide_render = True
            ob.hide_set(True)
    cam = bpy.data.objects.get("PreviewCam")
    if not cam:
        cam = bpy.data.objects.new("PreviewCam", bpy.data.cameras.new("PreviewCam"))
        sc.collection.objects.link(cam)
    sun = bpy.data.objects.get("PreviewSun")
    if not sun:
        sun = bpy.data.objects.new("PreviewSun", bpy.data.lights.new("PreviewSun", 'SUN'))
        sc.collection.objects.link(sun)
        sun.data.energy = 3.5
        sun.data.color = (1.0, 0.82, 0.62)
        sun.rotation_euler = (math.radians(55), 0, math.radians(35))
    if "PreviewGround" not in bpy.data.objects:
        gm = bpy.data.meshes.new("PreviewGround")
        gm.from_pydata([(-300, -300, 0), (300, -300, 0), (300, 300, 0), (-300, 300, 0)], [], [(0, 1, 2, 3)])
        gm.materials.append(_mat("ground_slate", (0.085, 0.095, 0.115)))
        sc.collection.objects.link(bpy.data.objects.new("PreviewGround", gm))
    w = bpy.data.worlds.get("World") or bpy.data.worlds.new("World")
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.045, 0.055, 0.085, 1)
    bg.inputs[1].default_value = 1.15
    hmax = max((o.dimensions.z for o in bpy.data.collections["trees_oak"].objects), default=8)
    span = SPACING * 4 + hmax * 0.8
    cam.location = (0, -(span * 0.75 + 6), hmax * 0.45)
    cam.rotation_euler = (math.radians(88), 0, 0)
    cam.data.lens = 28
    sc.camera = cam
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 24
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.filepath = path
    sc.render.image_settings.file_format = 'PNG'
    bpy.ops.render.render(write_still=True)
