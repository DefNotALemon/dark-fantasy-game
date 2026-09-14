#!/usr/bin/env python3
"""
mutate_timber.py -- the 2026-09-14 timber pass, applied to the repo in place.

    python3 tools/mutate_timber.py [repo-root]

Trees answer every tool with its own sound (WoodAudio.gd + tools/woodsounds.py);
felled trunks are cut ON the line with end grain on every face (WoodCut.gd);
bucked logs are the actual piece of trunk lying where it was; no branch is
left floating when the wood it grew on is gone; logs stop looking like
mushrooms. Idempotence: NOT -- each replace_once asserts a single match, so a
second run fails loudly instead of doubling anything.
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
    """Replace the whole body of `func name(` (from its header line to the
    blank lines before the next top-level func / section) with new_text."""
    head = ("static func " if static else "func ") + name + "("
    i = src.find("\n" + head)
    if i < 0:
        raise SystemExit("no func %s" % name)
    i += 1
    # next top-level definition after it
    m = re.compile(r"\n\n\n(?=(func |static func |## =|## -|const |var |class_name))").search(src, i)
    j = m.start() if m else len(src)
    return src[:i] + new_text.rstrip("\n") + src[j:]


def replace_once(src, old, new, label=""):
    n = src.count(old)
    if n != 1:
        raise SystemExit("expected 1 match for %s, got %d" % (label or old[:40], n))
    return src.replace(old, new)


def insert_before_func(src, name, text):
    head = "func " + name + "("
    i = src.find("\n" + head)
    if i < 0:
        raise SystemExit("no func %s" % name)
    return src[:i + 1] + text.rstrip("\n") + "\n\n\n" + src[i + 1:]


# ======================================================================
# patch_fallen.py

P = os.path.join(root, "scripts/FallenTrunk.gd")
s = read(P)

# ---- vars -------------------------------------------------------------------
s = replace_once(s, """var _trunk_mats: Array = []
""", """var _trunk_mats: Array = []
## Per pristine surface: "wood" (the bark tube -- split on a cut and capped),
## "card" (leaf cards -- kept whole or dropped, never sliced), "cap" (an end
## grain disc an earlier cut already left on the wood).
var _trunk_kind: Array = []
## EVERY branch mesh on the model, big or small, with where it grows from the
## trunk in MESH space. _limbs only ever held the ones long enough to prop the
## trunk up; the twigs were never in any list, so when the section they grew
## on was bucked away they stayed exactly where they were -- floating in the
## air over the ground (Lemon 2026-09-14). A branch goes with the wood it is
## rooted in, whatever its size.
var _twigs: Array = []             ## [{mesh, base_y}]
var _landed := false               ## the crown has met the ground (sound)
var _prev_spd := 0.0
""", "vars")

# ---- _ready: the creak --------------------------------------------------------
s = replace_once(s, """	call_deferred("_start_topple", dir)

	body_entered.connect(_on_body_entered)
""", """	call_deferred("_start_topple", dir)

	body_entered.connect(_on_body_entered)
	## The hinge goes: one long groan that ends on the snap, about as long as
	## the fall itself. A stump-less blast fell creaks too -- it is wood tearing.
	WoodAudio.creak(self, global_position + Vector3.DOWN * trunk_len * 0.5, trunk_len)
""", "creak")

# ---- _clip_below_cut ------------------------------------------------------------
s = replace_func(s, "_clip_below_cut", '''func _clip_below_cut() -> void:
	## Everything under the break line belongs to the stump, so it comes out of
	## this piece for good -- mesh and limbs both. Done ONCE, into the pristine
	## surfaces themselves, so the bucking clip later starts from a trunk whose
	## bottom already IS the break face and cannot resurrect the stump's wood.
	##
	## And the break face is WOOD. The tube is split exactly on the line, and
	## the loop it leaves is capped with end grain -- before this the butt of a
	## felled tree was an open tube you could see straight into (cull_back
	## draws nothing from inside), which is the "see-through bottom".
	if clip_below <= 0.0 or _model == null:
		return
	_cache_trunk_mesh()
	if _trunk_mi == null:
		return
	var floor_y := clip_below / maxf(_model.scale.y, 0.001)   ## mesh space
	var pr: Array = []
	var mats: Array = []
	var kinds: Array = []
	for si in range(_trunk_pristine.size()):
		var src: Array = _trunk_pristine[si]
		var kind := String(_trunk_kind[si])
		if kind == "card":
			var kept := WoodCut.cards(src, floor_y, INF)
			if not kept.is_empty():
				pr.append(kept)
				mats.append(_trunk_mats[si])
				kinds.append("card")
			continue
		var cut := WoodCut.slab(src, floor_y, INF, kind == "wood", false)
		if not (cut["wood"] as Array).is_empty():
			pr.append(cut["wood"])
			mats.append(_trunk_mats[si])
			kinds.append(kind)
		for cap in (cut["caps"] as Array):
			pr.append(cap)
			mats.append(WoodCut.grain_material(species))
			kinds.append("cap")
	_trunk_pristine = pr
	_trunk_mats = mats
	_trunk_kind = kinds
	_apply_surfaces(pr, mats)
	## A limb growing out of the stump's half stays on the stump.
	_hide_branches(-INF, floor_y, false)
''')

# ---- _build_limb_props: record every branch --------------------------------------
s = replace_once(s, """		var aabb := mi.mesh.get_aabb()
		## The model is a SCALED node (elder 1.7, great 3.5-4.5) and these
		## colliders are children of the BODY, so every length off the mesh has
		## to come across in body metres or a big tree props itself on spheres
		## in the wrong places at the wrong size.
		var ms := maxf(_model.scale.y, 0.001)
		var reach := aabb.size.length() * ms
		if reach < 1.0:
			continue                      ## twigs don't hold a tree up
""", """		var aabb := mi.mesh.get_aabb()
		## The model is a SCALED node (elder 1.7, great 3.5-4.5) and these
		## colliders are children of the BODY, so every length off the mesh has
		## to come across in body metres or a big tree props itself on spheres
		## in the wrong places at the wrong size.
		var ms := maxf(_model.scale.y, 0.001)
		var reach := aabb.size.length() * ms
		## every branch, whatever its size, is rooted somewhere on the trunk --
		## TreeKit puts a Branch mesh's origin at its own base, so mi.position.y
		## IS where it grows from, in mesh space
		_twigs.append({"mesh": mi, "base_y": mi.position.y, "reach": reach})
		if reach < 1.0:
			continue                      ## twigs don't hold a tree up
""", "twigs")

# ---- _physics_process: the crash ---------------------------------------------------
s = replace_once(s, """	if _age < MIN_FALL_TIME:
		return
	if settled:
		return
""", """	if not _landed and not settled and not freeze:
		## THE CROWN MEETING THE GROUND, heard. A falling trunk only ever speeds
		## up until something stops it, so the first hard drop in speed while
		## it is well over is the landing -- and it is one moment, not a
		## contact list, so it cannot fire at the foot's own touch on the stump.
		var spd := linear_velocity.length()
		var over := absf(global_transform.basis.y.dot(Vector3.UP)) < 0.85
		if over and _prev_spd - spd > 1.2 and _prev_spd > 1.5:
			_land_sound()
		_prev_spd = spd
	if _age < MIN_FALL_TIME:
		return
	if settled:
		return
""", "crash detect")

s = replace_once(s, """	if (slow and down) or _age > SETTLE_DEADLINE:
		settled = true
		freeze = true     ## stop simulating a log that has finished falling
""", """	if (slow and down) or _age > SETTLE_DEADLINE:
		settled = true
		freeze = true     ## stop simulating a log that has finished falling
		_land_sound()     ## if nothing else caught the landing, it is down now
""", "settle sound")

s = replace_once(s, """func _on_body_entered(body: Node) -> void:
	if not _crashed:
		_crashed = true
		for p in get_tree().get_nodes_in_group("player"):
			if p.has_method("tree_crash_shake"):
				p.tree_crash_shake(global_position)
		_snap_limbs_underneath()
""", """func _on_body_entered(body: Node) -> void:
	if not _crashed:
		_crashed = true
		for p in get_tree().get_nodes_in_group("player"):
			if p.has_method("tree_crash_shake"):
				p.tree_crash_shake(global_position)
		_snap_limbs_underneath()
	## a new contact once it is well over is the crown coming down
	if absf(global_transform.basis.y.dot(Vector3.UP)) < 0.85:
		_land_sound()
""", "body entered sound")

s = insert_before_func(s, "_set_limb_colliders", '''func _land_sound() -> void:
	## Once, however it was noticed. Sized by the wood: a sapling flops, an
	## ancient oak is felt through the floor.
	if _landed:
		return
	_landed = true
	WoodAudio.crash(self, global_position, trunk_len * trunk_r)''')

# ---- chop_hit / bucking ------------------------------------------------------------
s = replace_func(s, "chop_hit", '''func chop_hit(_toward_chopper: Vector3, _aim := Vector3.INF) -> bool:
	## One bite of the axe on a downed trunk cuts one log free -- and the log
	## is THAT PIECE OF THE TREE, lying where it was, not a token that pops
	## off the end (Lemon 2026-09-14: "separate into logs from where the logs
	## were, as tree lying on the ground"). The last bite takes whatever is
	## left rather than leaving a stub that vanishes.
	if not settled:
		return false
	logs_left -= 1
	var last := logs_left <= 0 or trunk_len - BUCK_LENGTH < BUCK_LENGTH * 0.5
	var cut_len := trunk_len if last else BUCK_LENGTH
	_spawn_log(cut_len)
	trunk_len = maxf(trunk_len - cut_len, 0.0)
	if last:
		_scatter_last()
		queue_free()
		return true
	_resize()
	return false
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
			for i in range(mi.mesh.get_surface_count()):
				_trunk_pristine.append(mi.mesh.surface_get_arrays(i))
				_trunk_mats.append(mi.get_surface_override_material(i))
				## surface 0 is the bark tube; everything after it is leaf
				## cards (TreeKit._mesh_of), which are never sliced
				_trunk_kind.append("wood" if i == 0 else "card")
			return
''')

s = replace_func(s, "_clip_model", '''func _clip_model() -> void:
	## Cut the trunk mesh off at the new length and put away everything beyond
	## it. Always rebuilt from the PRISTINE surfaces, never from the last clip,
	## so the cut is absolute and cannot compound -- the same rule
	## TreeV2._carve_notch follows for the notch.
	if _model == null:
		return
	_cache_trunk_mesh()
	if _trunk_mi == null:
		return
	## Mesh space, where the OLD TREE'S foot is still y = 0 -- so the cut has to
	## carry the wood already left behind on the stump, and come across the
	## model's scale.
	var limit := (trunk_len + clip_below) / maxf(_model.scale.y, 0.001)
	var surfaces: Array = []
	var mats: Array = []
	for si in range(_trunk_pristine.size()):
		var src: Array = _trunk_pristine[si]
		var kind := String(_trunk_kind[si])
		if kind == "card":
			var kept := WoodCut.cards(src, -INF, limit)
			if not kept.is_empty():
				surfaces.append(kept)
				mats.append(_trunk_mats[si])
			continue
		## the tube is split ON the line and the cut end capped with end
		## grain, so what is left is a log with a wooden face, not a pipe
		var cut := WoodCut.slab(src, -INF, limit, false, kind == "wood")
		if not (cut["wood"] as Array).is_empty():
			surfaces.append(cut["wood"])
			mats.append(_trunk_mats[si])
		for cap in (cut["caps"] as Array):
			surfaces.append(cap)
			mats.append(WoodCut.grain_material(species))
	_apply_surfaces(surfaces, mats)
	## branches rooted beyond the cut went with that section -- hidden, and
	## the big ones snap off as sticks the way limbs caught under it do
	_hide_branches(limit, INF, true)
''')

s = insert_before_func(s, "_spawn_log", '''func _apply_surfaces(surfaces: Array, mats: Array) -> void:
	if _trunk_mi == null:
		return
	if surfaces.is_empty():
		_trunk_mi.visible = false
		return
	var am := ArrayMesh.new()
	for arr in surfaces:
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_trunk_mi.mesh = am
	_trunk_mi.visible = true
	for i in range(mats.size()):
		_trunk_mi.set_surface_override_material(i, mats[i])


func _hide_branches(lo: float, hi: float, sticks_too: bool) -> void:
	## Put away every branch ROOTED between lo and hi (mesh-space heights on
	## the old tree's trunk). Rooted, not centred: a limb growing from wood
	## that is still here stays, however far it reaches; one growing from wood
	## that is gone goes with it, however small. Nothing is left in the air.
	var dropped := 0
	for tw in _twigs:
		var by := float(tw["base_y"])
		if by < lo or by > hi:
			continue
		var mi := tw["mesh"] as MeshInstance3D
		if mi == null or not is_instance_valid(mi) or not mi.visible:
			continue
		mi.visible = false
		## and if it was one of the props, its collider goes with it
		for L in _limbs.duplicate():
			if L["mesh"] == mi:
				var cs := L["shape"] as CollisionShape3D
				if is_instance_valid(cs):
					cs.queue_free()
				_limbs.erase(L)
				if sticks_too and dropped < 3 and float(tw["reach"]) >= 1.0:
					dropped += 1
					_stick_at(mi.global_position)


func _stick_at(at: Vector3) -> void:
	var world := get_parent()
	if world == null:
		return
	var s := DroppedItem.make({"name": "Stick", "weight": 0.3, "count": 1, "slot": ""})
	world.add_child(s)
	s.global_position = at + Vector3(randf_range(-0.4, 0.4), 0.25, randf_range(-0.4, 0.4))
	s.velocity = Vector3(randf_range(-1.4, 1.4), randf_range(0.8, 1.8), randf_range(-1.4, 1.4))''')

s = replace_func(s, "_spawn_log", '''func _spawn_log(cut_len: float) -> void:
	## The log is the far `cut_len` metres of what is left, cut off ON the
	## line and lying exactly where that piece of trunk lay -- its own bark,
	## its own notch if the cut ran through one, end grain on both faces. It
	## is an ordinary dropped item: look at it, press E, it is in your pack.
	## (It used to be a CarryLog you hefted onto your shoulder; Lemon
	## 2026-08-30: logs are inventory now.)
	var world := get_parent()
	if world == null:
		return
	var r_here := maxf(trunk_r * 0.9, 0.05)
	var d := DroppedItem.make({"name": "Log", "weight": LOG_WEIGHT, "count": 1,
		"slot": "", "material": "",
		## timber does not rot away on a ten-minute fuse -- see DroppedItem.KEEPS
		"keep": true,
		"species": species, "log_len": cut_len, "log_r": r_here,
		"bark": BARK.get(species, Color(0.28, 0.19, 0.12))})
	world.add_child(d)
	if _model != null and _hand_section(d, cut_len):
		return
	## No model (a plain-cylinder trunk): a built log of the same size, laid
	## along the trunk's axis over the piece it replaces.
	var axis := global_transform.basis.y.normalized()
	var mi := WoodCut.log_instance(species, r_here, cut_len,
		BARK.get(species, Color(0.28, 0.19, 0.12)), hash(str(global_position, trunk_len)))
	d.adopt_log(mi, r_here)
	var centre := global_position + axis * (_base + trunk_len - cut_len * 0.5)
	var gb := (global_transform.basis * Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0),
		Vector3(0, 0, 1))).orthonormalized()
	d.global_transform = Transform3D(gb, centre - gb.y * r_here)


func _hand_section(d: DroppedItem, cut_len: float) -> bool:
	## Slice the section out of the trunk's own pristine tube, lay it down
	## along +X in the item's frame, and place the item so the piece has not
	## moved a millimetre from where it was on the trunk.
	_cache_trunk_mesh()
	if _trunk_mi == null:
		return false
	var ms := maxf(_model.scale.y, 0.001)
	var hi := (trunk_len + clip_below) / ms
	var lo := (trunk_len - cut_len + clip_below) / ms
	## never exactly on the butt's own cap: a hair above it, so the tube is
	## split there and gets its own face rather than inheriting a second,
	## coplanar one
	lo = maxf(lo, clip_below / ms + 0.002)
	if hi - lo < 0.02:
		return false
	var wood: Array = []
	var caps: Array = []
	for si in range(_trunk_pristine.size()):
		if String(_trunk_kind[si]) != "wood":
			continue      ## leaves and old faces stay behind; a log is bark and grain
		var cut := WoodCut.slab(_trunk_pristine[si], lo, hi, true, true)
		if not (cut["wood"] as Array).is_empty():
			wood.append(cut["wood"])
		caps.append_array(cut["caps"] as Array)
	if wood.is_empty():
		return false
	## the section's own centre-line, mesh space
	var v: PackedVector3Array = wood[0][Mesh.ARRAY_VERTEX]
	var cx := 0.0
	var cz := 0.0
	for p in v:
		cx += p.x
		cz += p.z
	cx /= float(v.size())
	cz /= float(v.size())
	var rsum := 0.0
	for p in v:
		rsum += Vector2(p.x - cx, p.z - cz).length()
	var r_here := maxf(rsum / float(v.size()) * ms, 0.05)
	var ymid := (lo + hi) * 0.5

	var mi := MeshInstance3D.new()
	var am := ArrayMesh.new()
	var laid := WoodCut.lay_down(wood[0], cx, ymid, cz, ms, -0.05)
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, laid["arrays"])
	var lift: float = laid["lift"]
	for extra in range(1, wood.size()):
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
			WoodCut.lay_down(wood[extra], cx, ymid, cz, ms, -0.05, lift)["arrays"])
	var n_wood := am.get_surface_count()
	for cap in caps:
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
			WoodCut.lay_down(cap, cx, ymid, cz, ms, -0.05, lift)["arrays"])
	mi.mesh = am
	## the tree's OWN bark (dead bark stays dead), just not swaying any more
	var bark: Material = _trunk_mats[0]
	if bark is ShaderMaterial:
		bark = (bark as ShaderMaterial).duplicate()
		(bark as ShaderMaterial).set_shader_parameter("sway", 0.0)
	else:
		bark = WoodCut.bark_material(species, BARK.get(species, Color(0.28, 0.19, 0.12)))
	for si in range(n_wood):
		mi.set_surface_override_material(si, bark)
	for si in range(n_wood, am.get_surface_count()):
		mi.set_surface_override_material(si, WoodCut.grain_material(species))
	## and this tree's own cut of the bark sheet
	for pname in ["bark_var", "bark_value"]:
		var val = _trunk_mi.get_instance_shader_parameter(pname)
		if val != null:
			mi.set_instance_shader_parameter(pname, val)
	d.adopt_log(mi, r_here)
	d.item["log_r"] = r_here

	## Where it was: the section centre, mesh -> body -> world, and the item's
	## +X along the trunk's +Y. The centre sits `lift` up the item's own Y.
	var xf := global_transform * _model.transform
	var centre := xf * Vector3(cx, ymid, cz)
	var gb := (xf.basis * Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1))).orthonormalized()
	d.global_transform = Transform3D(gb, centre - gb.y * lift)
	return true
''')

s = replace_func(s, "_bark_material", '''func _bark_material(r: float, along: float) -> Material:
	## One shared ShaderMaterial per species would tile wrongly on differently
	## sized logs, so this takes a duplicate and sets the tiling for THIS piece.
	var base: Material = TreeV2.materials_for(species)[0]
	var m: ShaderMaterial = (base as ShaderMaterial).duplicate()
	m.set_shader_parameter("tiling", Vector2(maxf(TAU * r * 1.6, 0.5), maxf(along * 1.6, 0.5)))
	m.set_shader_parameter("sway", 0.0)      ## it is on the ground; it does not sway
	return m
''')

write(P, s)
print("patched", P, len(s))


# ======================================================================
# patch_dropped.py

P = os.path.join(root, "scripts/DroppedItem.gd")
s = read(P)

s = replace_once(s, """var _refoot := randf_range(0.3, 0.6)  ## staggered footing re-checks while resting
""", """var _refoot := randf_range(0.3, 0.6)  ## staggered footing re-checks while resting
## A bucked log is the actual piece of trunk it was cut from (FallenTrunk
## hands it over with adopt_log). It does not tumble like a tossed potion,
## and when it comes to rest it keeps lying along the line of the trunk
## instead of spinning to a random heading.
var keep_yaw := false
var tumble := true
var log_r := 0.0             ## radius of a log, for the thud's pitch; 0 = not a log
""", "vars")

s = replace_once(s, """func display_name() -> String:
	return String(item.get("name", "item"))
""", """func display_name() -> String:
	return String(item.get("name", "item"))


## Wear a piece of real trunk instead of the built billet: FallenTrunk cuts
## the section out of its own mesh and hands it over lying along +X.
func adopt_log(mi: MeshInstance3D, r: float) -> void:
	for c in get_children():
		if c is MeshInstance3D:
			c.queue_free()
	add_child(mi)
	keep_yaw = true
	tumble = false
	log_r = maxf(r, 0.03)
""", "adopt_log")

s = replace_once(s, """	global_position += velocity * delta
	rotate_y(TOSS_SPIN * delta)
	if velocity.y >= 0.0:
		return
""", """	global_position += velocity * delta
	if tumble:
		rotate_y(TOSS_SPIN * delta)
	if velocity.y >= 0.0:
		return
""", "tumble")

s = replace_once(s, """	if global_position.y <= float(hit.position.y) + REST_HEIGHT:
		_resting = true
		global_position.y = float(hit.position.y) + REST_HEIGHT
		rotation = Vector3(0.0, randf() * TAU, 0.0)  ## settle flat, any old way
""", """	if global_position.y <= float(hit.position.y) + REST_HEIGHT:
		_resting = true
		global_position.y = float(hit.position.y) + REST_HEIGHT
		if keep_yaw:
			## flat, but along the line it was lying on: the log's +X is the
			## trunk's axis, so its heading is that axis on the ground
			var ax := global_transform.basis.x
			var yaw := atan2(-ax.z, ax.x) if Vector2(ax.x, ax.z).length() > 0.05 else rotation.y
			var from := global_transform.basis.orthonormalized()
			var to := Basis(Vector3.UP, yaw)
			var tw := create_tween()
			tw.tween_method(func(t: float): basis = from.slerp(to, t), 0.0, 1.0, 0.22)
		else:
			rotation = Vector3(0.0, randf() * TAU, 0.0)  ## settle flat, any old way
		if log_r > 0.0 or String(item.get("name", "")) == "Log":
			WoodAudio.thud(self, global_position,
				log_r if log_r > 0.0 else float(item.get("log_r", 0.22)))
""", "rest")

s = replace_func(s, "_build_billet", '''func _build_billet() -> void:
	## A split of firewood: a round of bark with end grain on both faces,
	## lying on its side. A LOG is the same thing at timber scale -- it came
	## off a trunk you felled, and it has to read as a piece of that trunk
	## from across a clearing. One builder (WoodCut.log_instance), so the
	## bark is the species' own shader and the faces are growth rings.
	##
	## The old one was three CylinderMeshes: a shaft tapered to 55% at one
	## end and two full-radius heart discs -- so the discs stood proud of the
	## thin end like a cap on a stalk. That is the "logs look like mushrooms"
	## report (Lemon 2026-09-14). A log bucked off a trunk carries its size
	## (log_r / log_len) and species in its dict, so it comes back out of the
	## pack the size it went in.
	var log_sized := String(item.get("name", "")) == "Log"
	var species := String(item.get("species", ""))
	var wood: Color = item.get("bark", Color(0.28, 0.19, 0.12).lerp(Color(0.34, 0.23, 0.14), randf()))
	var r := float(item.get("log_r", 0.22 if log_sized else 0.085))
	var length := float(item.get("log_len", 1.05 if log_sized else 0.40))
	var seed_v := hash(str(item.get("name", ""), item.get("bark", ""), randi()))
	add_child(WoodCut.log_instance(species, r, length, wood, seed_v))
	if not log_sized:
		## kindling comes as a pair: a second, thinner split leaning on the first
		var b := WoodCut.log_instance(species, 0.055, 0.30, wood, seed_v + 1)
		b.position = Vector3(0.03, 0.0, 0.12)
		b.rotation_degrees = Vector3(0, 12, 0)
		add_child(b)
''')

write(P, s)
print("patched", P, len(s))


# ======================================================================
# patch_rest.py


# ---- Player.gd ------------------------------------------------------------------
P = os.path.join(root, "scripts/Player.gd")
s = read(P)
s = replace_once(s, """func _wood_impact(wood: Node3D, mat_id := "", power := 1.0) -> Array:
	## Chips out of the cut, tinted to the species, plus real tumbling
	## splinters you can watch land. Returns [point, normal] so the caller can
	## reuse the strike point it just paid a raycast for.
	var pn := _wood_strike_point(wood, AXE_RANGE + 0.6)
	var at: Vector3 = pn[0]
	var normal: Vector3 = pn[1]
	var dir := _fx_dir(normal)
	var species := ""
	if "species" in wood:
		species = String(wood.get("species"))
	_fx(HitFX.wood(at, dir, species, power))
""", """func _wood_impact(wood: Node3D, mat_id := "", power := 1.0, tool := "") -> Array:
	## Chips out of the cut, tinted to the species, plus real tumbling
	## splinters you can watch land. Returns [point, normal] so the caller can
	## reuse the strike point it just paid a raycast for.
	## AND THE SOUND OF IT: every tool that meets wood comes through here, so
	## this is where the trunk answers -- with the tool's own voice (an axe
	## bites, a sword slaps, a pick thuds) pitched to the size of the wood.
	## See WoodAudio.gd. `tool` defaults to what is in your hand.
	var pn := _wood_strike_point(wood, AXE_RANGE + 0.6)
	var at: Vector3 = pn[0]
	var normal: Vector3 = pn[1]
	var dir := _fx_dir(normal)
	var species := ""
	if "species" in wood:
		species = String(wood.get("species"))
	_fx(HitFX.wood(at, dir, species, power))
	WoodAudio.strike(self, at, tool if tool != "" else current_weapon, power, wood)
""", "wood_impact")

s = replace_once(s, """	## No rock — it's a poor weapon, but it IS a heavy spike of iron.
	var fwd_flat := forward
	fwd_flat.y = 0.0
	fwd_flat = fwd_flat.normalized()
	for e in get_tree().get_nodes_in_group("enemies"):
""", """	## No rock — it's a poor weapon, but it IS a heavy spike of iron.
	var fwd_flat := forward
	fwd_flat.y = 0.0
	fwd_flat = fwd_flat.normalized()
	## Timber in the arc: the point goes in with a dull thud, a few chips
	## come out, and not one bit of the felling job gets done. Bring an axe.
	## (Every tool sounds like itself on a trunk -- WoodAudio.gd.)
	var wood_hit := _nearest_wood(fwd_flat, PICK_RANGE)
	if wood_hit != null:
		_wood_impact(wood_hit, "", 0.5, "pickaxe")
		cam_punch = maxf(cam_punch, 0.6)
		if wood_hit.has_method("shiver_from"):
			wood_hit.call("shiver_from", global_position)
		if axe_hint_cd <= 0.0:
			axe_hint_cd = 8.0
			_add_log_msg("The pick thuds in, but this is an axe's work (2)", Color(0.8, 0.8, 0.8))
		return
	for e in get_tree().get_nodes_in_group("enemies"):
""", "pick on wood")
write(P, s)
print("patched Player.gd", len(s))

# ---- Arrow.gd ------------------------------------------------------------------------
P = os.path.join(root, "scripts/Arrow.gd")
s = read(P)
s = replace_once(s, """		_leave_fx(HitFX.wood(hit.position as Vector3,
			((hit.normal as Vector3) + Vector3.UP * 0.4).normalized(), sp, 0.45))
""", """		_leave_fx(HitFX.wood(hit.position as Vector3,
			((hit.normal as Vector3) + Vector3.UP * 0.4).normalized(), sp, 0.45))
		## the thock, and the shaft quivering -- pitched to the trunk
		WoodAudio.strike(self, hit.position as Vector3, "arrow", 0.7, timber)
""", "arrow sound")
write(P, s)
print("patched Arrow.gd", len(s))

# ---- TreeV2.gd -------------------------------------------------------------------------
P = os.path.join(root, "scripts/TreeV2.gd")
s = read(P)
s = replace_once(s, """	var limb := nearest_branch(global_position, aim)
	if limb != null:
		last_result = "limb_off" if limb.take_hit(1) else "limb"
		return false
""", """	var limb := nearest_branch(global_position, aim)
	if limb != null:
		last_result = "limb_off" if limb.take_hit(1) else "limb"
		if last_result == "limb_off":
			WoodAudio.limb(self, aim if aim != Vector3.INF else global_position + Vector3.UP * 2.0)
		return false
""", "limb sound")
write(P, s)
print("patched TreeV2.gd", len(s))

# ---- World.gd ---------------------------------------------------------------------------
P = os.path.join(root, "scripts/World.gd")
s = read(P)
s = replace_once(s, """	_step_audio = StepAudio.new()
	_step_audio.name = "StepAudio"
	add_child(_step_audio)
""", """	_step_audio = StepAudio.new()
	_step_audio.name = "StepAudio"
	add_child(_step_audio)
	## [wood] iron on timber and trees coming down -- see scripts/WoodAudio.gd.
	## Static entry points like StepAudio; nothing else needs a handle on it.
	var wood_audio := WoodAudio.new()
	wood_audio.name = "WoodAudio"
	add_child(wood_audio)
""", "world wood audio")
write(P, s)
print("patched World.gd", len(s))
