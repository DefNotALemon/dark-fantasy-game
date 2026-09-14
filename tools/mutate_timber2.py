#!/usr/bin/env python3
"""
mutate_timber2.py -- the second timber pass (2026-09-14, later the same day).

    python3 tools/mutate_timber2.py [repo-root]

Lemon: "the tree midsection/base will still float in the air after falling it
and giving it a couple hits. to fix this I want you to make the fallen tree
split from the side you break it instead of going from the top down every
time. also I like the tree rings, but on the bottom most section where the
tree splits when it falls needs the rings to center the original size of the
tree trunk, currently the rings center on the new shape with the chunk taken
out, which isn't how tree rings work."

  * FallenTrunk.chop_hit cuts WHERE THE AXE LANDED (the aim point projected
    onto the trunk's axis). The piece beyond the cut comes off as a Log item
    when it is short, or as a NEW FallenTrunk when it is long -- still
    buckable, carrying its own branches. What is left drops to the ground
    again (it was frozen in the air, propped by limbs that are gone).
  * WoodCut caps fit a circle to the OUTER rim points, so the growth rings
    centre on the trunk the tree grew, not on whatever shape the notch left.
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


def replace_func(src, name, new_text, static=False):
    head = ("static func " if static else "func ") + name + "("
    i = src.find("\n" + head)
    if i < 0:
        raise SystemExit("no func %s" % name)
    i += 1
    m = re.compile(r"\n\n\n(?=(func |static func |## =|## -|const |var |class_name ))").search(src, i)
    j = m.start() if m else len(src)
    return src[:i] + new_text.rstrip("\n") + src[j:]


def replace_once(src, old, new, label=""):
    n = src.count(old)
    if n != 1:
        raise SystemExit("expected 1 match for %s, got %d" % (label or old[:40], n))
    return src.replace(old, new)


def insert_before_func(src, name, text):
    i = src.find("\nfunc " + name + "(")
    if i < 0:
        i = src.find("\nstatic func " + name + "(")
    if i < 0:
        raise SystemExit("no func %s" % name)
    return src[:i + 1] + text.rstrip("\n") + "\n\n\n" + src[i + 1:]


# =============================================================================
# WoodCut.gd -- rings centred on the tree the trunk grew
P = os.path.join(root, "scripts/WoodCut.gd")
s = read(P)

s = replace_once(s, '''	var c := Vector3.ZERO
	for p in loop:
		c += p
	c /= float(n)
	var rmax := 0.0
	for p in loop:
		rmax = maxf(rmax, Vector2(p.x - c.x, p.z - c.z).length())
	if rmax < 1e-5:
		return []
	var span := rmax * 2.04
	var want := Vector3.UP if up else Vector3.DOWN
''', '''	var c := Vector3.ZERO
	for p in loop:
		c += p
	c /= float(n)
	var rmax := 0.0
	for p in loop:
		rmax = maxf(rmax, Vector2(p.x - c.x, p.z - c.z).length())
	if rmax < 1e-5:
		return []
	## THE RINGS BELONG TO THE TREE, NOT TO THE CUT (Lemon 2026-09-14). Where
	## the break runs through the notch the loop is a D, and a disc centred on
	## the D's centroid puts the pith in the wrong place with rings that follow
	## the axe. Fit a circle to the OUTER rim -- the bark that is still there --
	## and centre the grain on that: the pith sits where it grew, and the
	## rings simply stop where the wood was taken out.
	var fit := fit_circle(loop)
	var ring_c := Vector3(float(fit[0]), c.y, float(fit[1]))
	var ring_r := float(fit[2])
	if ring_r < rmax * 0.5 or ring_r > rmax * 1.6:
		ring_c = c                       ## a fit that ran away: fall back
		ring_r = rmax
	var span := ring_r * 2.04
	var want := Vector3.UP if up else Vector3.DOWN
''', "cap fit")

s = replace_once(s, '''		uvs.append(Vector2(0.5 + (p.x - c.x) / span, 0.5 + (p.z - c.z) / span))
		poly.append(Vector2(p.x, p.z))''', '''		uvs.append(Vector2(0.5 + (p.x - ring_c.x) / span, 0.5 + (p.z - ring_c.z) / span))
		poly.append(Vector2(p.x, p.z))''', "cap uv")

s = insert_before_func(s, "_cap", '''## A least-squares circle through a rim, refitted on its inliers: a plain
## Kasa fit over every point, then the points that sit on or outside that
## circle (within the bark's relief) are kept and the fit repeated. On a whole ring that
## is the ring; on a notched one the bark that is left is the majority and
## agrees with itself, so the wedge the axe took drops out as outliers and
## cannot drag the centre. Returns [cx, cz, r] in the loop's x/z, or the
## centroid and its max radius when the fit is degenerate.
static func fit_circle(loop: PackedVector3Array) -> Array:
	var n := loop.size()
	var c := Vector3.ZERO
	for p in loop:
		c += p
	c /= float(maxi(n, 1))
	var rmax := 0.0
	for p in loop:
		rmax = maxf(rmax, Vector2(p.x - c.x, p.z - c.z).length())
	if n < 4 or rmax < 1e-6:
		return [c.x, c.z, rmax]
	var use := PackedByteArray()
	use.resize(n)
	use.fill(1)
	var best := [c.x, c.z, rmax]
	for _pass in range(6):
		var fit := _kasa(loop, use, c)
		if fit.is_empty():
			break
		best = fit
		## The axe only ever takes wood AWAY, so the points that disagree with
		## the circle all sit INSIDE it. Keep everything on or outside it, and
		## anything inside by no more than the bark's own relief (1.5x the
		## median miss, never under 4% of the radius); the notch drops out.
		var inside := PackedFloat32Array()
		var miss := PackedFloat32Array()
		for i in range(n):
			var di := Vector2(loop[i].x - float(fit[0]), loop[i].z - float(fit[1])).length()
			inside.append(float(fit[2]) - di)
			miss.append(absf(float(fit[2]) - di))
		var sorted := PackedFloat32Array(miss)
		sorted.sort()
		var tol: float = maxf(sorted[n / 2] * 1.5, float(fit[2]) * 0.04)
		var kept := 0
		var changed := false
		for i in range(n):
			var u := 1 if inside[i] <= tol else 0
			if u != use[i]:
				changed = true
			use[i] = u
			kept += u
		if kept < 4 or not changed:
			break
	return best


static func _kasa(loop: PackedVector3Array, use: PackedByteArray, about: Vector3) -> Array:
	## normal equations for x^2 + z^2 + D x + E z + F = 0 over the used points,
	## about `about` so the 3x3 stays well conditioned
	var sxx := 0.0
	var sxz := 0.0
	var szz := 0.0
	var sx := 0.0
	var sz := 0.0
	var m := 0.0
	var bx := 0.0
	var bz := 0.0
	var b1 := 0.0
	for i in range(loop.size()):
		if use[i] == 0:
			continue
		var x := loop[i].x - about.x
		var z := loop[i].z - about.z
		var r2 := x * x + z * z
		sxx += x * x
		sxz += x * z
		szz += z * z
		sx += x
		sz += z
		m += 1.0
		bx += -r2 * x
		bz += -r2 * z
		b1 += -r2
	if m < 3.0:
		return []
	var A := Basis(Vector3(sxx, sxz, sx), Vector3(sxz, szz, sz), Vector3(sx, sz, m))
	if absf(A.determinant()) < 1e-14:
		return []
	var sol := A.inverse() * Vector3(bx, bz, b1)
	var cx := -sol.x * 0.5
	var cz := -sol.y * 0.5
	var rr := cx * cx + cz * cz - sol.z
	if rr <= 0.0 or is_nan(rr):
		return []
	return [about.x + cx, about.z + cz, sqrt(rr)]''')

write(P, s)
print("patched WoodCut.gd", len(s))

# =============================================================================
# FallenTrunk.gd -- split where you strike, and drop back to the ground
P = os.path.join(root, "scripts/FallenTrunk.gd")
s = read(P)

s = replace_once(s, '''var _landed := false               ## the crown has met the ground (sound)
var _prev_spd := 0.0
''', '''var _landed := false               ## the crown has met the ground (sound)
var _prev_spd := 0.0
## A settled trunk is FROZEN where it stopped -- propped on limbs whose
## colliders are gone. Cut those limbs off and the wood that is left hangs
## in the air (Lemon 2026-09-14: "the midsection/base will still float").
## So every bite lets it fall again: unfreeze, wait for it to come to rest on
## whatever is actually under it, freeze. `settled` stays true throughout --
## it is still furniture, still buckable, never crushes anyone.
var _resettle := false
var _resettle_t := 0.0
## A piece cut off a downed trunk (see _split_off): it starts lying down,
## already landed, and never topples or creaks.
var _split := false
''', "vars")

s = replace_once(s, '''	## Stand it up where the tree stood: the body's origin is the MIDDLE of the
	## cylinder, so it has to sit half a trunk above the stump or the log spawns
	## buried to the waist.
	position.y += trunk_len * 0.5
''', '''	_split = bool(get_meta("split", false))
	## Stand it up where the tree stood: the body's origin is the MIDDLE of the
	## cylinder, so it has to sit half a trunk above the stump or the log spawns
	## buried to the waist. (A split-off piece is placed by whoever cut it.)
	if not _split:
		position.y += trunk_len * 0.5
''', "ready position")

s = replace_once(s, '''	var dir: Vector3 = get_meta("fall_dir", Vector3.FORWARD)
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	call_deferred("_start_topple", dir)

	body_entered.connect(_on_body_entered)
	## The hinge goes: one long groan that ends on the snap, about as long as
	## the fall itself. A stump-less blast fell creaks too -- it is wood tearing.
	WoodAudio.creak(self, global_position + Vector3.DOWN * trunk_len * 0.5, trunk_len)
''', '''	body_entered.connect(_on_body_entered)
	if _split:
		## Already down: it was lying on the ground as part of a bigger log a
		## moment ago. It only has to drop onto whatever is under it now.
		_age = MIN_FALL_TIME
		settled = true
		_landed = true
		_crashed = true          ## no crash shake, and its limbs never prop it
		_drop_again()
		return
	var dir: Vector3 = get_meta("fall_dir", Vector3.FORWARD)
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	call_deferred("_start_topple", dir)
	## The hinge goes: one long groan that ends on the snap, about as long as
	## the fall itself. A stump-less blast fell creaks too -- it is wood tearing.
	WoodAudio.creak(self, global_position + Vector3.DOWN * trunk_len * 0.5, trunk_len)
''', "ready split")

s = replace_once(s, '''	if _age < MIN_FALL_TIME:
		return
	if settled:
		return
''', '''	if _resettle:
		## Falling again after a bite. Rest = slow for a beat; a hard cap so a
		## piece wedged against something does not simulate forever.
		_resettle_t += delta
		var still := linear_velocity.length() < 0.25 and angular_velocity.length() < 0.3
		if (_resettle_t > 0.35 and still) or _resettle_t > 4.0:
			_resettle = false
			freeze = true
			if _split:
				WoodAudio.thud(self, global_position, trunk_r)
	if _age < MIN_FALL_TIME:
		return
	if settled:
		return
''', "resettle")

s = replace_func(s, "chop_hit", '''func chop_hit(_toward_chopper: Vector3, aim := Vector3.INF) -> bool:
	## One bite of the axe on a downed trunk cuts it WHERE THE AXE LANDED
	## (Lemon 2026-09-14: "split from the side you break it instead of going
	## from the top down every time"). `aim` is the crosshair strike point the
	## Player already paid a raycast for; projected onto the trunk's axis it is
	## the cut. The piece beyond the cut -- the top side -- comes off: as a Log
	## item when it is short enough to carry, as a NEW trunk lying right there
	## when it is not, still buckable, its own branches on it. What is left is
	## the butt side, and it falls back onto the ground it was floating over.
	## With no aim (a test, a blast) it takes BUCK_LENGTH off the top as before.
	## The last bite takes whatever is left rather than leaving a stub.
	if not settled:
		return false
	logs_left -= 1
	if trunk_len <= BUCK_LENGTH * 1.5:
		_spawn_log(trunk_len)
		trunk_len = 0.0
		_scatter_last()
		queue_free()
		return true
	var keep := trunk_len - BUCK_LENGTH
	if aim != Vector3.INF and aim.is_finite():
		var along := to_local(aim).y - _base          ## metres up the trunk from the butt
		keep = clampf(along, BUCK_LENGTH * 0.75, trunk_len - BUCK_LENGTH * 0.75)
	var off := trunk_len - keep
	if off <= BUCK_LENGTH * 1.5 or not _split_off(off):
		_spawn_log(off)
	trunk_len = keep
	_resize()
	_drop_again()
	return false


func _drop_again() -> void:
	## Let the physics have it back until it is resting on something real.
	freeze = false
	sleeping = false
	_resettle = true
	_resettle_t = 0.0
''')

s = replace_func(s, "_cache_trunk_mesh", '''func _cache_trunk_mesh() -> void:
	## Lazy: a trunk nobody ever chops should not pay to copy its own mesh.
	if _trunk_mi != null or _model == null:
		return
	var parts: Node = _model
	if _model.get_child_count() == 1 and _model.get_child(0).get_child_count() > 0:
		parts = _model.get_child(0)
	for child in parts.get_children():
		var mi := child as MeshInstance3D
		if mi != null and mi.mesh != null and mi.name.begins_with("Trunk"):
			_trunk_mi = mi
			## a split-off piece says what each of its surfaces is; a tree's own
			## trunk is the bark tube on surface 0 and leaf cards after it
			## (TreeKit._mesh_of), which are never sliced
			var kinds: Array = mi.get_meta("wood_kinds", [])
			for i in range(mi.mesh.get_surface_count()):
				_trunk_pristine.append(mi.mesh.surface_get_arrays(i))
				_trunk_mats.append(mi.get_surface_override_material(i))
				if i < kinds.size():
					_trunk_kind.append(String(kinds[i]))
				else:
					_trunk_kind.append("wood" if i == 0 else "card")
			return
''')

s = insert_before_func(s, "_spawn_log", '''func _split_off(off: float) -> bool:
	## The far `off` metres of this trunk become a trunk of their own, lying
	## exactly where they are: the same mesh space (foot at the old tree's
	## origin, the model's scale), the bark tube sliced on the cut with end
	## grain on the new face, the leaf cards and every branch ROOTED in that
	## stretch moved across as the same nodes. Returns false if there is no
	## model to slice (a plain-cylinder trunk), and the caller makes a log.
	var world := get_parent()
	if world == null or _model == null:
		return false
	_cache_trunk_mesh()
	if _trunk_mi == null:
		return false
	var ms := maxf(_model.scale.y, 0.001)
	var hi := (trunk_len + clip_below) / ms
	var lo := (trunk_len - off + clip_below) / ms
	var surfaces: Array = []
	var mats: Array = []
	var kinds: Array = []
	for si in range(_trunk_pristine.size()):
		var src: Array = _trunk_pristine[si]
		var kind := String(_trunk_kind[si])
		if kind == "wood":
			var cut := WoodCut.slab(src, lo, hi, true, false)
			if not (cut["wood"] as Array).is_empty():
				surfaces.append(cut["wood"])
				mats.append(_trunk_mats[si])
				kinds.append("wood")
			for cap in (cut["caps"] as Array):
				surfaces.append(cap)
				mats.append(WoodCut.grain_material(species))
				kinds.append("cap")
		else:
			## leaf cards, and any face an earlier cut left up there
			var kept := WoodCut.cards(src, lo - 0.001, hi + 0.001)
			if not kept.is_empty():
				surfaces.append(kept)
				mats.append(_trunk_mats[si])
				kinds.append(kind)
	if surfaces.is_empty() or kinds[0] != "wood":
		return false
	var v: PackedVector3Array = surfaces[0][Mesh.ARRAY_VERTEX]
	var cx := 0.0
	var cz := 0.0
	for p in v:
		cx += p.x
		cz += p.z
	cx /= float(v.size())
	cz /= float(v.size())
	## the collider's radius is the wood AT THE CUT, not the average of a
	## piece that tapers to the leader's tip -- or the thick end sinks into
	## the ground up to its bark
	var rsum := 0.0
	var rn := 0
	for p in v:
		if p.y <= lo + 0.6 / ms:
			rsum += Vector2(p.x - cx, p.z - cz).length()
			rn += 1
	var r_here := maxf((rsum / float(rn) if rn > 0 else trunk_r * 0.8) * ms, 0.05)

	var am := ArrayMesh.new()
	for arr in surfaces:
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "Trunk_split"
	mi.mesh = am
	for i in range(mats.size()):
		mi.set_surface_override_material(i, mats[i])
	mi.set_meta("wood_kinds", kinds)
	for pname in ["bark_var", "bark_value", "leaf_var"]:
		var val = _trunk_mi.get_instance_shader_parameter(pname)
		if val != null:
			mi.set_instance_shader_parameter(pname, val)
	var model := Node3D.new()
	model.name = "Split_%s" % species
	model.scale = _model.scale
	model.add_child(mi)
	## the branches rooted in that stretch go with it -- the same nodes, the
	## same mesh-space positions, so nothing on them moves
	var parts: Node = _model
	if _model.get_child_count() == 1 and _model.get_child(0).get_child_count() > 0:
		parts = _model.get_child(0)
	for tw in _twigs.duplicate():
		var by := float(tw["base_y"])
		if by < lo or by > hi:
			continue
		var bm := tw["mesh"] as MeshInstance3D
		if bm == null or not is_instance_valid(bm):
			continue
		for L in _limbs.duplicate():
			if L["mesh"] == bm:
				var cs := L["shape"] as CollisionShape3D
				if is_instance_valid(cs):
					cs.queue_free()
				_limbs.erase(L)
		_twigs.erase(tw)
		if bm.get_parent() == parts:
			parts.remove_child(bm)
		model.add_child(bm)

	var piece := FallenTrunk.make(Vector3.ZERO, Vector3.FORWARD, off, r_here, species,
		maxi(logs_left, 1))
	piece.clip_below = clip_below + trunk_len - off
	piece.leaf_mat = leaf_mat
	piece.sticks = 0
	piece.set_meta("split", true)
	piece.adopt(model)
	world.add_child(piece)
	## the body's origin is the middle of its cylinder: put it on this body's
	## axis at the middle of the stretch, with this body's orientation
	piece.global_transform = Transform3D(global_transform.basis,
		to_global(Vector3(0, _base + trunk_len - off * 0.5, 0)))
	return true''')

write(P, s)
print("patched FallenTrunk.gd", len(s))
