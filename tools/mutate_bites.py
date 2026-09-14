#!/usr/bin/env python3
"""
mutate_bites.py -- every axe bite strips bark where it lands, and every
slanted face is inner wood (2026-09-14).

    python3 tools/mutate_bites.py [repo-root]

Lemon: "when you hit the trees with your axe every hit splits the bark off
wherever you hit, every time you hit, and every bit of the tree that slants
after being hit should be inner tree."

  * TreeV2.bites: every bite the axe lands is recorded (height, angle round
    the trunk, mesh space) and saved. The first one is still the felling
    notch; EVERY one of them dents the bark where it hit and strips it.
  * _carve_notch UNWELDS the cut: any triangle with a moved vertex is a
    slanted face and is drawn entirely as inner wood -- its still-bark
    corners are duplicated as bare copies with the cut face's normal -- and
    any triangle with no moved vertex is drawn entirely as bark. No triangle
    is half and half; the bark shader's step never has to decide.
Each replace_once asserts a single match: a second run fails loudly.
"""
import os
import re
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


def replace_func(src, name, new_text):
    i = src.find("\nfunc " + name + "(")
    if i < 0:
        raise SystemExit("no func %s" % name)
    i += 1
    m = re.compile(r"\n\n\n(?=(func |static func |## =|## -|const |var |class_name ))").search(src, i)
    j = m.start() if m else len(src)
    return src[:i] + new_text.rstrip("\n") + src[j:]


P = os.path.join(root, "scripts/TreeV2.gd")
s = read(P)

# ---- state --------------------------------------------------------------------
s = replace_once(s, "const BREAK_AT := 1.02       ## wedge depth / trunk radius that drops the tree\n",
"""const BREAK_AT := 1.02       ## wedge depth / trunk radius that drops the tree
## EVERY BITE MARKS THE TREE (Lemon 2026-09-14: "every hit splits the bark off
## wherever you hit, every time you hit"). An axe head's worth of bark comes
## off around each strike, dished into the wood, whether or not it landed in
## the felling notch. Sizes are WORLD metres, divided by the model scale when
## carved (with a floor so a great tree's mark still catches a ring or two).
const BITE_H := 0.22         ## half-height of a bite mark
const BITE_W := 0.17         ## half-width across the bark
const BITE_DENT := 0.10      ## its depth, as a fraction of the radius there
""", "bite consts")

s = replace_once(s, "var _branches: Array = []     ## of TreeBranch\n",
"""var _branches: Array = []     ## of TreeBranch
## Where every axe bite landed, mesh space: Vector3(height, angle, 0). The
## first is the felling notch's line; all of them strip bark. Saved.
var bites: Array = []
""", "bites var")

# ---- recording the bite ---------------------------------------------------------
s = replace_once(s, """	if notch_y <= 0.0:
		notch_y = y
		notch_ang = ang
	## ...and that is the last time it moves. Later bites land in the SAME cut
	## and only make it bigger — see _carve_notch, where the wedge opens up as
	## it deepens. Returning true either way keeps the caller off its
	## side-you're-standing-on fallback.
	return true
""", """	if notch_y <= 0.0:
		notch_y = y
		notch_ang = ang
	## ...and that is the last time it moves. Later bites land in the SAME cut
	## and only make it bigger — see _carve_notch, where the wedge opens up as
	## it deepens. Returning true either way keeps the caller off its
	## side-you're-standing-on fallback. Every bite is remembered where it
	## landed, though: each one strips its own patch of bark.
	bites.append(Vector3(y, ang, 0.0))
	return true
""", "record bite")

s = replace_once(s, """	if not _aim_to_notch(aim):
		var local := (global_transform.basis.inverse() * toward_chopper).normalized()
		notch_ang = atan2(local.z, local.x)
		if notch_y <= 0.0:
			notch_y = notch_line()
""", """	if not _aim_to_notch(aim):
		var local := (global_transform.basis.inverse() * toward_chopper).normalized()
		notch_ang = atan2(local.z, local.x)
		if notch_y <= 0.0:
			notch_y = notch_line()
		bites.append(Vector3(notch_y, notch_ang, 0.0))   ## a blind bite lands on the line
""", "blind bite")

# ---- save / restore ----------------------------------------------------------------
s = replace_once(s, """		"notch_ang": notch_ang,
		"notch_y": notch_y,
		"branches": _branch_state(),
""", """		"notch_ang": notch_ang,
		"notch_y": notch_y,
		"bites": _bite_state(),
		"branches": _branch_state(),
""", "save bites")
s = replace_once(s, """func _branch_state() -> Array:
""", """func _bite_state() -> Array:
	var out: Array = []
	for b in bites:
		out.append([float((b as Vector3).x), float((b as Vector3).y)])
	return out


func _branch_state() -> Array:
""", "bite state")
s = replace_once(s, """	notch_y = float(d.get("notch_y", 0.0))
""", """	notch_y = float(d.get("notch_y", 0.0))
	bites = []
	for b in (d.get("bites", []) as Array):
		if b is Array and (b as Array).size() >= 2:
			bites.append(Vector3(float(b[0]), float(b[1]), 0.0))
""", "restore bites")
s = replace_once(s, """	if notch_depth > 0.0:
		_carve_notch()      ## a half-chopped tree comes back half-chopped
""", """	if notch_depth > 0.0 or not bites.is_empty():
		_carve_notch()      ## a half-chopped tree comes back half-chopped
""", "restore carve")

# ---- the carve ---------------------------------------------------------------------
s = replace_func(s, "_carve_notch", '''func _carve_notch() -> void:
	## Push the trunk's own vertices inward inside the wedge -- and dish a
	## patch of bark off around EVERY bite that has landed. Always rebuilt
	## from the pristine arrays, so depth is absolute and never compounds.
	##
	## THEN THE CUT IS UNWELDED (Lemon 2026-09-14: "every bit of the tree that
	## slants after being hit should be inner tree"). A vertex that moved is
	## bare wood. A triangle with any moved corner is a SLANTED FACE and is
	## drawn entirely as wood: its still-bark corners are duplicated as bare
	## copies that carry the cut face's normal. A triangle with no moved
	## corner is drawn entirely as bark, with its round-trunk normal. No
	## triangle is half and half, so nothing blends -- bark stops on a line.
	_cache_trunk()
	if _trunk == null or _trunk_arrays.is_empty():
		return
	var src: PackedVector3Array = _trunk_arrays[Mesh.ARRAY_VERTEX]
	var verts := PackedVector3Array(src)
	## The wedge is authored in world metres but carved in the trunk mesh's own
	## space, so both the height and the half-height divide by the model scale.
	## WHERE, and HOW BIG. The line is wherever the blade went in; the wedge
	## around it OPENS UP as the cut deepens, so the triangle you are watching
	## gets taller and wraps further round the trunk with every bite instead of
	## just getting a little deeper in a fixed-size slot.
	var ny := notch_line()
	var shape := notch_shape()
	var nh: float = shape[0]
	var nang: float = shape[1]
	var y_lo := ny - nh
	var y_hi := ny + nh
	var ms := maxf(scale_class, 0.001)
	## a bite mark is an axe head's worth of bark, in world metres, with a
	## floor in mesh space so it always spans a ring or two of vertices
	var bh := maxf(BITE_H / ms, 0.18)
	var bw := maxf(BITE_W / ms, 0.15)

	var moved := PackedByteArray()
	moved.resize(verts.size())
	moved.fill(0)

	for i in range(verts.size()):
		var v := verts[i]
		var c := _ring_centre(v.y)
		var rel := Vector3(v.x - c.x, 0.0, v.z - c.z)
		var r := rel.length()
		if r < 0.001:
			continue
		var a := atan2(rel.z, rel.x)
		var cut := 0.0
		## ---- the felling wedge, on its line ----------------------------------
		if notch_depth > 0.0 and v.y >= y_lo and v.y <= y_hi:
			var da: float = absf(wrapf(a - notch_ang, -PI, PI))
			if da <= nang:
				## A SHARP TRIANGLE, not a gouge. Down the trunk the depth falls off
				## LINEARLY from the strike line to nothing at the top and bottom
				## of the wedge -- a clean V with its point buried in the wood.
				var fy: float = 1.0 - absf(v.y - ny) / nh
				## ACROSS the trunk it stays a FACE: full depth over the middle of
				## the arc, tapering only out at the corners where the wedge runs
				## out of wood. A V in both axes at once would be a cone.
				var fa: float = clampf((1.0 - da / nang) / 0.35, 0.0, 1.0)
				if fy > 0.0:
					cut = notch_depth * fy * fa
		## ---- every bite, where it landed ---------------------------------------
		for b in bites:
			var bv := b as Vector3
			var dy := absf(v.y - bv.x)
			if dy > bh:
				continue
			var dx: float = absf(wrapf(a - bv.y, -PI, PI)) * r    ## arc metres across
			if dx > bw:
				continue
			## a shallow dish: full depth under the edge, nothing at the rim
			var f := 1.0 - maxf(dy / bh, dx / bw)
			cut = maxf(cut, r * BITE_DENT * f)
		if cut <= 0.0005:
			continue
		var nr: float = maxf(r - cut, 0.012)
		verts[i] = Vector3(c.x + rel.x / r * nr, v.y, c.z + rel.z / r * nr)
		moved[i] = 1

	## ---- unweld: slanted faces are wood, flat faces are bark -------------------
	var idx: PackedInt32Array = _trunk_arrays[Mesh.ARRAY_INDEX]
	var has_n: bool = _trunk_arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array \\
		and (_trunk_arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).size() == src.size()
	var has_t: bool = _trunk_arrays[Mesh.ARRAY_TANGENT] is PackedFloat32Array \\
		and (_trunk_arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array).size() == src.size() * 4
	var has_uv: bool = _trunk_arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array \\
		and (_trunk_arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() == src.size()
	var out_v: Array = Array(verts)
	var out_n: Array = Array(_trunk_arrays[Mesh.ARRAY_NORMAL]) if has_n else []
	var out_t: Array = Array(_trunk_arrays[Mesh.ARRAY_TANGENT]) if has_t else []
	var out_uv: Array = Array(_trunk_arrays[Mesh.ARRAY_TEX_UV]) if has_uv else []
	## White = untouched bark. The bark shader reads (1 - COLOR.r), so anything
	## without a colour array (every branch mesh) correctly reads as no cut.
	var out_c: Array = []
	out_c.resize(verts.size())
	for i in range(verts.size()):
		out_c[i] = Color(0, 0, 0, 1) if moved[i] == 1 else Color(1, 1, 1, 1)
	var dup := {}                       ## bark vertex -> its bare copy on a cut face
	var acc: Array = []                 ## cut-face normals, summed per output vertex
	acc.resize(verts.size())
	for i in range(verts.size()):
		acc[i] = Vector3.ZERO
	var new_idx := PackedInt32Array()
	var t := 0
	while t + 2 < idx.size():
		var ia := idx[t]
		var ib := idx[t + 1]
		var ic := idx[t + 2]
		t += 3
		if moved[ia] == 0 and moved[ib] == 0 and moved[ic] == 0:
			new_idx.append_array(PackedInt32Array([ia, ib, ic]))
			continue
		## Godot's front faces are clockwise: the face normal is -(b-a)x(c-a)
		var fn := -(verts[ib] - verts[ia]).cross(verts[ic] - verts[ia])
		var tri := [ia, ib, ic]
		for k in range(3):
			var i: int = tri[k]
			var j: int = i
			if moved[i] == 0:
				if dup.has(i):
					j = int(dup[i])
				else:
					j = out_v.size()
					dup[i] = j
					out_v.append(verts[i])
					out_c.append(Color(0, 0, 0, 1))
					if has_n:
						out_n.append(out_n[i])
					if has_t:
						out_t.append_array(out_t.slice(i * 4, i * 4 + 4))
					if has_uv:
						out_uv.append(out_uv[i])
					acc.append(Vector3.ZERO)
			acc[j] = acc[j] + fn
			tri[k] = j
		new_idx.append_array(PackedInt32Array([tri[0], tri[1], tri[2]]))
	## every vertex on a cut face is lit by the cut, never by the round trunk
	if has_n:
		for i in range(out_v.size()):
			var is_cut: bool = (i < moved.size() and moved[i] == 1) or i >= moved.size()
			if is_cut and (acc[i] as Vector3).length_squared() > 1e-12:
				out_n[i] = (acc[i] as Vector3).normalized()

	var arrays := _trunk_arrays.duplicate()
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(out_v)
	arrays[Mesh.ARRAY_INDEX] = new_idx
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray(out_c)
	if has_n:
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(out_n)
	if has_t:
		arrays[Mesh.ARRAY_TANGENT] = PackedFloat32Array(out_t)
	if has_uv:
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(out_uv)
	## any other per-vertex array the kit did not fill stays absent; one it did
	## fill at the old count would now be short, so drop it rather than lie
	for extra in [Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1,
			Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
		if arrays[extra] != null:
			arrays[extra] = null
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	## keep every other surface (sapling twigs) exactly as it was
	for s in range(1, _trunk.mesh.get_surface_count()):
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _trunk.mesh.surface_get_arrays(s))
	_trunk.mesh = am
	_seed_bark_look(_trunk)   ## a carve rebuilds the mesh; keep this tree's bark
	var mats: Array = PSXNature.materials(String(_psx["atlas"]), region, dead) \\
		if (USE_PSX and not _psx.is_empty()) else materials_for(species, dead)
	_trunk.set_surface_override_material(0, mats[0])
	var lroles: Array = _trunk.get_meta("leaf_roles") if _trunk.has_meta("leaf_roles") else []
	for s in range(1, am.get_surface_count()):
		var role := String(lroles[s]) if s < lroles.size() else "outer"
		_trunk.set_surface_override_material(s,
			mats[2] if role == "inner" and mats.size() > 2 else mats[1])
''')
write(P, s)
print("patched TreeV2.gd", len(s))
