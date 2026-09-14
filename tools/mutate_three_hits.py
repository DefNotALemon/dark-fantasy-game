#!/usr/bin/env python3
"""
mutate_three_hits.py -- the axe is a three-swing job, a limb is one (2026-09-14).

    python3 tools/mutate_three_hits.py [repo-root]

Lemon: "it should instantly take out a branch and the axe should too, the full
tree should take 3 hits with the axe ... clearly define the tree so that when
you're hitting it with an axe each part of the tree either is untouched or hit.
I don't want any more gradients between bark and not bark, also make the bark
chunkier."

  * TreeBranch.MAX_HP 3 -> 1: any limb, any tool, one cut.
  * TreeV2.TRUNK_CHOPS: young/mature/ancient/withered all 3 (sapling stays 1).
  * The notch is BINARY: a vertex the axe moved is bare wood (COLOR 0), one it
    did not is bark (COLOR 1) -- no "how much" in between -- and the bark
    shader steps at 0.5 instead of blending over 0.02..0.55. The moved
    vertices also get their normals rebuilt from the carved faces, so the cut
    is lit as a cut instead of wearing the round trunk's outward normals.
  * Chunkier bark: relief amplitude up ~1.7x and plates taller (bark_v down)
    in TreeKit; the shader's texel cells double in size (cell_m 0.015 ->
    0.028), land harder (cell_mix 0.32 -> 0.55), fewer tones (posterize 16 ->
    9), more per-cell jitter.
Each replace_once asserts a single match: a second run fails loudly.
"""
import os
import sys

root = sys.argv[1] if len(sys.argv) > 1 else "."


def read(path):
    return open(path, encoding="utf-8").read()


def write(path, s):
    open(path, "w", encoding="utf-8").write(s)


def replace_once(src, old, new, label=""):
    n = src.count(old)
    if n != 1:
        raise SystemExit("expected 1 match for %s, got %d" % (label or old[:40], n))
    return src.replace(old, new)


# ---- TreeBranch: one cut ----------------------------------------------------
P = os.path.join(root, "scripts/TreeBranch.gd")
s = read(P)
s = replace_once(s, "const MAX_HP := 3        ## was 7, then 4 — see the swing-count note below",
    "## ONE CUT (Lemon 2026-09-14: \"it should instantly take out a branch and the\n"
    "## axe should too\"). Was 7, then 4, then 3 -- a limb is a limb, it comes off.\n"
    "const MAX_HP := 1")
write(P, s)
print("patched TreeBranch.gd")

# ---- TreeV2: three swings, a binary notch, lit as a cut ----------------------------
P = os.path.join(root, "scripts/TreeV2.gd")
s = read(P)
s = replace_once(s, "const TRUNK_CHOPS: Array[int] = [1, 3, 5, 7, 4]",
    "## THREE SWINGS FELL A TREE, whatever its size (Lemon 2026-09-14: \"the full\n"
    "## tree should take 3 hits with the axe\"); a sapling is one. Was [1,3,5,7,4].\n"
    "const TRUNK_CHOPS: Array[int] = [1, 3, 3, 3, 3]")
s = replace_once(s, """		## Anything the axe actually moved is exposed wood. Scale by the bite so
		## the shallow edges of the wedge are half-bark, the middle is bare.
		if cut > 0.004:
			var bare: float = 1.0 - clampf(cut / maxf(notch_depth, 0.001), 0.0, 1.0)
			cols[i] = Color(bare, bare, bare, 1)
""", """		## Anything the axe actually moved is exposed wood -- ALL the way. No
		## "half-bark" at the wedge's edges (Lemon 2026-09-14: "each part of the
		## tree either is untouched or hit ... no more gradients between bark
		## and not bark"); the shader steps on this, it does not blend.
		if cut > 0.004:
			cols[i] = Color(0, 0, 0, 1)
			moved[i] = 1
""", "binary colour")
s = replace_once(s, """	var cols := PackedColorArray()
	cols.resize(verts.size())
""", """	var cols := PackedColorArray()
	cols.resize(verts.size())
	var moved := PackedByteArray()
	moved.resize(verts.size())
	moved.fill(0)
""", "moved array")
s = replace_once(s, """	var arrays := _trunk_arrays.duplicate()
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
""", """	var arrays := _trunk_arrays.duplicate()
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	## The cut is LIT as a cut: every vertex the axe moved gets its normal
	## rebuilt from the faces it now sits on, instead of keeping the round
	## trunk's outward normal and shading the notch as if it were still bark.
	## Godot's front faces are clockwise, so a face's normal is -(b-a)x(c-a).
	if _trunk_arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
		var nrm := PackedVector3Array(_trunk_arrays[Mesh.ARRAY_NORMAL])
		var idx: PackedInt32Array = _trunk_arrays[Mesh.ARRAY_INDEX]
		if nrm.size() == verts.size() and not idx.is_empty():
			var acc := PackedVector3Array()
			acc.resize(verts.size())
			acc.fill(Vector3.ZERO)
			var t := 0
			while t + 2 < idx.size():
				var ia := idx[t]
				var ib := idx[t + 1]
				var ic := idx[t + 2]
				t += 3
				if moved[ia] == 0 and moved[ib] == 0 and moved[ic] == 0:
					continue
				var fn := -(verts[ib] - verts[ia]).cross(verts[ic] - verts[ia])
				acc[ia] = acc[ia] + fn
				acc[ib] = acc[ib] + fn
				acc[ic] = acc[ic] + fn
			for i in range(verts.size()):
				if moved[i] == 1 and acc[i].length_squared() > 1e-12:
					nrm[i] = acc[i].normalized()
			arrays[Mesh.ARRAY_NORMAL] = nrm
""", "normals")
write(P, s)
print("patched TreeV2.gd")

# ---- bark shader: a step, not a blend; chunkier cells ------------------------------
P = os.path.join(root, "shaders/bark.gdshader")
s = read(P)
s = replace_once(s, "uniform float cell_m : hint_range(0.004, 0.08) = 0.015;",
    "uniform float cell_m : hint_range(0.004, 0.08) = 0.028;")
s = replace_once(s, "uniform float cell_mix : hint_range(0.0, 1.0) = 0.32;",
    "uniform float cell_mix : hint_range(0.0, 1.0) = 0.55;")
s = replace_once(s, "uniform float posterize : hint_range(2.0, 32.0) = 16.0;",
    "uniform float posterize : hint_range(2.0, 32.0) = 9.0;")
s = replace_once(s, "uniform float cell_jitter : hint_range(0.0, 0.5) = 0.035;",
    "uniform float cell_jitter : hint_range(0.0, 0.5) = 0.06;")
s = replace_once(s, """	// ---- the axe cut: pale wood, no bark ---------------------------------
	if (v_cut > 0.01) {
		vec3 grain = texture(bark_albedo, suv * vec2(0.35, 2.2)).rgb;
		col = mix(col, col_heart * (0.72 + 0.55 * dot(grain, vec3(0.333))),
			smoothstep(0.02, 0.55, v_cut));
	}
""", """	// ---- the axe cut: pale wood, no bark ---------------------------------
	// A STEP, not a blend (Lemon 2026-09-14: "no more gradients between bark
	// and not bark"). TreeV2._carve_notch writes 0 or 1 per vertex; the
	// interpolated value crosses 0.5 once along an edge, so the line between
	// bark and cut is a line.
	float cut = step(0.5, v_cut);
	if (cut > 0.5) {
		vec3 grain = texture(bark_albedo, suv * vec2(0.35, 2.2)).rgb;
		col = col_heart * (0.72 + 0.55 * dot(grain, vec3(0.333)));
	}
""", "cut step")
s = replace_once(s, """	ROUGHNESS = mix(texture(bark_rough, suv).r, heart_rough,
		smoothstep(0.02, 0.55, v_cut));
""", """	ROUGHNESS = mix(texture(bark_rough, suv).r, heart_rough, cut);
""", "cut roughness")
write(P, s)
print("patched bark.gdshader")

# ---- TreeKit: chunkier relief ----------------------------------------------------------
P = os.path.join(root, "scripts/TreeKit.gd")
s = read(P)
for old, new in [
    ('"bark": "plate", "bark_amp": 0.030, "bark_v": 2.6,', '"bark": "plate", "bark_amp": 0.052, "bark_v": 1.9,'),
    ('"bark": "paper", "bark_amp": 0.012, "bark_v": 5.5,', '"bark": "paper", "bark_amp": 0.020, "bark_v": 4.0,'),
    ('"bark": "fissure", "bark_amp": 0.040, "bark_v": 2.1,', '"bark": "fissure", "bark_amp": 0.068, "bark_v": 1.5,'),
    ('"bark": "jigsaw", "bark_amp": 0.034, "bark_v": 1.5,', '"bark": "jigsaw", "bark_amp": 0.058, "bark_v": 1.1,'),
    ('"bark": "smooth", "bark_amp": 0.010, "bark_v": 3.0,', '"bark": "smooth", "bark_amp": 0.018, "bark_v": 2.2,'),
    ('const DEAD_BARK := {"bark": "split", "bark_amp": 0.046, "bark_v": 1.8}',
     '## CHUNKIER (Lemon 2026-09-14): relief ~1.7x deeper and plates taller\n'
     '## (bark_v lower) across every species; the clamp in _tube still caps it.\n'
     'const DEAD_BARK := {"bark": "split", "bark_amp": 0.075, "bark_v": 1.3}'),
]:
    s = replace_once(s, old, new, old[:30])
write(P, s)
print("patched TreeKit.gd")
