#!/usr/bin/env python3
"""Carcass bodies: the animal's own ragdoll skin, and bones you can pick up.

Every edit is an exact-anchor replacement that must match ONCE; a miss is a
hard error, never a silent skip. Run it again and it is a clean no-op.
"""
import os, sys

ROOT = os.environ.get("REPO", os.path.expanduser("~/mnt/dark-fantasy-game"))


def patch(path, edits):
    p = os.path.join(ROOT, path)
    src = open(p, encoding="utf-8").read()
    orig = src
    for anchor, new, guard in edits:
        if guard and guard in src:
            continue  # already applied
        n = src.count(anchor)
        if n != 1:
            sys.exit("%s: anchor matched %d times:\n%s" % (path, n, anchor[:200]))
        src = src.replace(anchor, new)
    if src != orig:
        open(p, "w", encoding="utf-8").write(src)
        print("patched", path)
    else:
        print("no-op  ", path)


# ---------------------------------------------------------------- CreatureSkin
patch("scripts/CreatureSkin.gd", [
    (
        "func pelvis_global() -> Transform3D:\n\treturn bone_global(_pelvis_bone)\n",
        '''func pelvis_global() -> Transform3D:
	return bone_global(_pelvis_bone)


## ================================================================ poses ====
## A carcass wears the pose its death left it in (CarcassBody). These are the
## doors it uses: read a settled skeleton, write one back, and hold it.

func bone_of(n: Node) -> int:
	## The bone a pivot drives, or 0 for a node that carries no flesh.
	return int(_bone_of.get(n, 0))


func bone_aabb(id: int) -> AABB:
	## Bone-space box around everything the bone wears -- what the ragdoll
	## shape is cut from, and what a bone item is sized from.
	return _bone_geo.get(id, AABB())


func rest_global(id: int) -> Transform3D:
	return _rest_global[id] if id >= 0 and id < _rest_global.size() else Transform3D.IDENTITY


func parent_of(id: int) -> int:
	return int(_parent[id]) if id >= 0 and id < _parent.size() else -1


func bone_pose(id: int) -> Transform3D:
	## Owner-space pose of a bone right now (skeleton space == owner space:
	## the skin and its skeleton both sit at identity under the owner).
	## Works OFF the tree, which `bone_global` cannot.
	if skeleton == null or id < 0 or id >= skeleton.get_bone_count():
		return Transform3D.IDENTITY
	return skeleton.get_bone_global_pose(id)


func pose_globals() -> Array:
	## Every bone's owner-space pose, index = bone id, [0] identity. A frozen
	## corpse answers with the pose the ragdoll left it in.
	var out: Array = []
	if skeleton == null:
		return out
	for i in skeleton.get_bone_count():
		out.append(Transform3D.IDENTITY if i == 0 else skeleton.get_bone_global_pose(i))
	return out


func pose_apply(globals: Array) -> void:
	## Write a pose straight onto the bones and HOLD it: no pivots, no
	## physics, no clocks. After this call nothing in here moves a bone
	## again -- `frozen` short-circuits the sync, and the corpse clocks never
	## start because `_linger_t` stays at zero. The segment mirror keeps
	## running, so colour and `visible` on the proxies still land.
	if skeleton == null or globals.size() != bone_nodes.size():
		return
	if ragdoll and _sim != null:
		_sim.physical_bones_stop_simulation()
	ragdoll = false
	_blend_t = 0.0
	_fade_t = -1.0
	_linger_t = 0.0
	_g = globals.duplicate()
	_g[0] = Transform3D.IDENTITY
	_apply_globals()
	frozen = true
	permanent = true
''',
        "func pose_apply(globals: Array) -> void:",
    ),
])

# ---------------------------------------------------------------- Carcasses
patch("scripts/Carcasses.gd", [
    # state: the pending ragdolls
    (
        "var _known: Dictionary = {}      ## instance_id of a dying body -> record id\n",
        "var _known: Dictionary = {}      ## instance_id of a dying body -> record id\n"
        "var _pending: Dictionary = {}    ## instance_id of a dying body -> record id, its ragdoll not yet settled\n",
        "var _pending: Dictionary = {}",
    ),
    # harvest: watch the corpse for its pose
    (
        "\t\tvar rec := _make_from(e)\n"
        "\t\t_known[iid] = int(rec.get(\"id\", 0)) if not rec.is_empty() else 0\n"
        "\t\tif not rec.is_empty():\n"
        "\t\t\tmade += 1\n"
        "\treturn made\n",
        "\t\tvar rec := _make_from(e)\n"
        "\t\t_known[iid] = int(rec.get(\"id\", 0)) if not rec.is_empty() else 0\n"
        "\t\tif not rec.is_empty():\n"
        "\t\t\tmade += 1\n"
        "\t\t\t_watch_pose(e, rec)\n"
        "\t_capture_pending()\n"
        "\treturn made\n"
        "\n"
        "\n"
        "func _watch_pose(e: Node3D, rec: Dictionary) -> void:\n"
        "\t## THE POSE IS THE DEATH'S. A wild animal that dies through `Enemy._die()`\n"
        "\t## hands its body to the CreatureSkin ragdoll, which settles for five\n"
        "\t## seconds and freezes. Until it has, the corpse IS the picture and this\n"
        "\t## bus stages nothing over it; once it has, the skeleton is read once,\n"
        "\t## written on the record, and the body this bus builds wears it -- in\n"
        "\t## the same frame the corpse is hidden, so nothing on screen changes. It\n"
        "\t## just stops being the animal's and starts being the ledger's.\n"
        "\tvar skin := CreatureSkin.of(e)\n"
        "\tif skin == null or skin.bone_count() <= 1:\n"
        "\t\treturn\n"
        "\t_pending[e.get_instance_id()] = int(rec.get(\"id\", 0))\n"
        "\t## and the grass goes down now, not five seconds from now\n"
        "\tvar prof: Dictionary = CritterDex.get_profile(String(rec.get(\"species\", \"\")))\n"
        "\t_mow(rec[\"at\"] as Vector3, mow_radius(float(prof.get(\"len\", 1.0))))\n"
        "\n"
        "\n"
        "func _capture_pending() -> void:\n"
        "\tfor k in _pending.keys():\n"
        "\t\tvar id := int(_pending[k])\n"
        "\t\tvar rec: Dictionary = _by_id.get(id, {})\n"
        "\t\tvar o := instance_from_id(int(k))\n"
        "\t\tif rec.is_empty() or o == null or not is_instance_valid(o):\n"
        "\t\t\t_pending.erase(k)     ## gone before it settled: the fallback pose, then\n"
        "\t\t\tcontinue\n"
        "\t\tvar skin := CreatureSkin.of(o as Node)\n"
        "\t\tif skin == null or skin.bone_count() <= 1:\n"
        "\t\t\t_pending.erase(k)\n"
        "\t\t\tcontinue\n"
        "\t\tif skin.ragdoll or not skin.frozen:\n"
        "\t\t\tcontinue              ## still falling\n"
        "\t\t## Settled. The record moves to where the body actually lies -- a\n"
        "\t\t## ragdoll slides -- and the pose is written relative to that point.\n"
        "\t\tvar pel := skin.pelvis_global().origin\n"
        "\t\tvar at0: Vector3 = rec[\"at\"]\n"
        "\t\tvar at := Vector3(pel.x, at0.y, pel.z)\n"
        "\t\tat.y = _ground_y(at)\n"
        "\t\trec[\"at\"] = at\n"
        "\t\trec[\"pose\"] = _body_script().pose_of(skin, at)\n"
        "\t\t_pending.erase(k)\n"
        "\t\t_restage()\n"
        "\t\tif _staged.has(id):\n"
        "\t\t\tskin.visible = false\n",
        "func _capture_pending() -> void:",
    ),
    # restage: a record whose corpse is still settling stays a corpse
    (
        "\tfor row in near(here, STAGE_RADIUS):\n"
        "\t\tif _staged.size() >= MAX_STAGED:\n"
        "\t\t\tbreak\n"
        "\t\tvar rec2: Dictionary = (row as Dictionary)[\"rec\"]\n"
        "\t\tvar id2 := int(rec2[\"id\"])\n"
        "\t\tif _staged.has(id2):\n"
        "\t\t\tcontinue\n",
        "\t## A record whose corpse is still settling is not staged: the corpse is\n"
        "\t## the picture until `_capture_pending` has read its pose.\n"
        "\tvar held: Dictionary = {}\n"
        "\tfor v in _pending.values():\n"
        "\t\theld[int(v)] = true\n"
        "\tfor row in near(here, STAGE_RADIUS):\n"
        "\t\tif _staged.size() >= MAX_STAGED:\n"
        "\t\t\tbreak\n"
        "\t\tvar rec2: Dictionary = (row as Dictionary)[\"rec\"]\n"
        "\t\tvar id2 := int(rec2[\"id\"])\n"
        "\t\tif _staged.has(id2) or held.has(id2):\n"
        "\t\t\tcontinue\n",
        "if _staged.has(id2) or held.has(id2):",
    ),
    # the body: CarcassBody owns it now
    (
        '''func _build_body(rec: Dictionary) -> Node3D:
	## PSX flat-shaded: four boxes that read as a dead thing IS the correct
	## answer here, and the stage is the whole of what changes.
	var root := Node3D.new()
	root.name = "Carcass%d" % int(rec["id"])
	var at: Vector3 = rec["at"]
	root.position = Vector3(at.x, _ground_y(at), at.z)
	root.add_to_group("carcass_bodies")
	_dress(root, rec)
	return root


func _dress(root: Node3D, rec: Dictionary) -> void:
	for c in root.get_children():
		c.queue_free()
	var st := stage_of(rec)
	var id := int(rec["id"])
	var length := 1.0
	var prof: Dictionary = CritterDex.get_profile(String(rec.get("species", "")))
	if not prof.is_empty():
		length = float(prof.get("len", 1.0))
	var yaw := _unit(_hash(world_seed ^ id, 0, SALT_BODY), 7) * TAU
	root.rotation.y = yaw
	## THE GROUND UNDER IT IS WHAT YOU SEE FIRST, and the first live look at
	## this feature is the reason this slab exists. A flat-shaded box lying
	## in stubble is a dark lump at ten metres and invisible at twenty; a
	## patch of trodden, stained earth the size of the animal reads from
	## across a field -- and it is the honest thing to draw, because this is
	## where something bled and where five kinds of animal have been standing
	## on it for three days. It goes down at EVERY stage, including the last:
	## the bare ground is the longest-lived part of a carcass.
	var soil := Color(0.17, 0.12, 0.09)
	if st >= STAGE_PICKED:
		soil = Color(0.24, 0.20, 0.15)
	_slab(root, length * GROUND_SCALE, soil)
	## The hide is the LIVE animal's colour, barely touched. The first draft
	## darkened it 35 %, which is exactly how the croft's walls vanished into
	## a summer hillside at 196/0 green.
	var hide := Color(0.40, 0.32, 0.24)
	if not prof.is_empty() and prof.get("col") is Color:
		hide = (prof["col"] as Color).lightened(0.10)
	var bone := Color(0.88, 0.85, 0.76)
	var meat := Color(0.44, 0.14, 0.13)
	var lift := length * 0.05
	match st:
		STAGE_WHOLE:
			_box(root, Vector3(length * 0.86, length * 0.32, length * 0.34),
					Vector3(0.0, lift + length * 0.16, 0.0), hide)
			_box(root, Vector3(length * 0.30, length * 0.22, length * 0.22),
					Vector3(length * 0.55, lift + length * 0.11, 0.0), hide)
			_legs(root, length, lift, hide, 4)
		STAGE_OPENED:
			_box(root, Vector3(length * 0.80, length * 0.26, length * 0.32),
					Vector3(0.0, lift + length * 0.13, 0.0), hide)
			_box(root, Vector3(length * 0.34, length * 0.12, length * 0.26),
					Vector3(-length * 0.10, lift + length * 0.25, 0.0), meat)
			_legs(root, length, lift, hide, 3)
		STAGE_PICKED:
			_box(root, Vector3(length * 0.62, length * 0.16, length * 0.26),
					Vector3(0.0, lift + length * 0.08, 0.0), meat)
			_legs(root, length, lift, bone, 1)
			for i in 5:
				var u := _unit(_hash(world_seed ^ id, i + 11, SALT_JIT), 2)
				_box(root, Vector3(length * 0.05, length * 0.20, length * 0.05),
						Vector3(length * (u - 0.5) * 0.7, lift + length * 0.17,
								length * (0.11 if i % 2 == 0 else -0.11)), bone)
		STAGE_BONES, STAGE_GONE:
			for i in 7:
				var h := _hash(world_seed ^ id, i + 21, SALT_JIT)
				_box(root, Vector3(length * 0.07, length * 0.06, length * 0.28),
						Vector3(length * (_unit(h, 2) - 0.5) * 0.9, lift * 0.5,
								length * (_unit(h, 4) - 0.5) * 0.6), bone)
	root.set_meta("stage", st)


func _slab(root: Node3D, radius: float, col: Color) -> void:
	## The trodden ground. Deliberately not a decal and not a shader: a flat
	## box two centimetres proud of the terrain is what every other prop in
	## this project is made of, and it takes the same flat shading.
	_box(root, Vector3(radius * 1.9, 0.04, radius * 1.5), Vector3(0.0, 0.02, 0.0), col)


func _legs(root: Node3D, length: float, lift: float, col: Color, n: int) -> void:
	## Stiff legs are the whole silhouette. A box on its own in long grass
	## reads as a rock; four thin spars sticking out of it reads, at any
	## distance, as a dead animal -- and losing them one at a time is how
	## the stages tell each other apart from far enough away to matter.
	for i in n:
		var pivot := Node3D.new()
		var fore := 1.0 if i < 2 else -1.0
		var side := 1.0 if i % 2 == 0 else -1.0
		pivot.position = Vector3(length * 0.30 * fore, lift + length * 0.14,
				length * 0.13 * side)
		pivot.rotation.z = side * 0.95
		root.add_child(pivot)
		_box(pivot, Vector3(length * 0.07, length * 0.44, length * 0.07),
				Vector3(0.0, length * 0.20, 0.0), col)


func _box(root: Node3D, size: Vector3, at: Vector3, col: Color) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.95
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.material_override = mat
	root.add_child(m)


func _drive_bodies() -> void:
	## A body is a picture of the record and nothing else, so the only thing
	## driving it is the stage changing under it.
	for k in _staged.keys():
		var id := int(k)
		var rec: Dictionary = _by_id.get(id, {})
		var n: Variant = _staged.get(id, null)
		if rec.is_empty() or not (n is Node3D) or not is_instance_valid(n as Node3D):
			continue
		var body := n as Node3D
		var want := stage_of(rec)
		if int(body.get_meta("stage", -1)) != want:
			_dress(body, rec)
''',
        '''static var _body_gd: GDScript = null


static func _body_script() -> GDScript:
	## Loaded by path rather than named: this file must parse on a machine
	## whose class cache has not met CarcassBody yet (a fresh clone, a
	## headless run before the editor has scanned).
	if _body_gd == null:
		_body_gd = load("res://scripts/CarcassBody.gd")
	return _body_gd


func _build_body(rec: Dictionary) -> Node3D:
	## The picture of the record: the species' OWN rounded skin, lying in
	## the pose its death left it in, with the stained ground under it. Until
	## 2026-09-14 this was four flat boxes and some spars -- "some cube
	## that's stuck". CarcassBody owns every box, colour and bone of it now;
	## this bus only says which record and where the ground is.
	var at: Vector3 = rec["at"]
	return _body_script().build(rec, world_seed, _ground_y(at), Callable(self, "_ground_y")) as Node3D


func _dress(root: Node3D, rec: Dictionary) -> void:
	if root != null and is_instance_valid(root) and root.has_method("dress"):
		root.call("dress", rec)


func _drive_bodies() -> void:
	## A body is a picture of the record and nothing else, so the only thing
	## driving it is the stage changing under it -- and, at the bones stage,
	## the one thing the picture can tell the record: that a bone which was
	## lying there has been picked up. A bone never expires and nothing else
	## frees one, so a bone node that is gone IS a bone that was taken.
	for k in _staged.keys():
		var id := int(k)
		var rec: Dictionary = _by_id.get(id, {})
		var n: Variant = _staged.get(id, null)
		if rec.is_empty() or not (n is Node3D) or not is_instance_valid(n as Node3D):
			continue
		var body := n as Node3D
		var want := stage_of(rec)
		if int(body.get_meta("stage", -1)) != want:
			_dress(body, rec)
		if body.has_method("sweep_taken"):
			for bk in body.call("sweep_taken"):
				var taken: Dictionary = rec.get("bones", {})
				taken[String(bk)] = true
				rec["bones"] = taken
''',
        "static func _body_script() -> GDScript:",
    ),
    # the save
    (
        '''			"place": String(rec.get("place", "")),
			"told": (rec.get("told", {}) as Dictionary).duplicate(),
		})
	return {"v": 1, "hours": _hours, "steps": _steps, "next": _next_id, "rows": rows}
''',
        '''			"place": String(rec.get("place", "")),
			"told": (rec.get("told", {}) as Dictionary).duplicate(),
			"pose": _pose_packed(rec.get("pose", null)),
			"bones": (rec.get("bones", {}) as Dictionary).duplicate(),
		})
	return {"v": 1, "hours": _hours, "steps": _steps, "next": _next_id, "rows": rows}


static func _pose_packed(v: Variant) -> PackedFloat32Array:
	## A pose is twelve floats a bone. Anything else -- an old row with none,
	## a JSON detour that turned it into an Array -- comes back as a pose or
	## as nothing, never as a type the body has to reason about.
	if v is PackedFloat32Array:
		return v
	if v is Array:
		return PackedFloat32Array(v as Array)
	return PackedFloat32Array()
''',
        "static func _pose_packed(v: Variant) -> PackedFloat32Array:",
    ),
    (
        '''	records.clear()
	_by_id.clear()
	_known.clear()
	_asked.clear()
''',
        '''	records.clear()
	_by_id.clear()
	_known.clear()
	_pending.clear()
	_asked.clear()
''',
        "\t_pending.clear()\n\t_asked.clear()",
    ),
    (
        '''			"place": String(r.get("place", "")),
			"told": (r.get("told", {}) as Dictionary).duplicate(),
		}
		records.append(rec)
''',
        '''			"place": String(r.get("place", "")),
			"told": (r.get("told", {}) as Dictionary).duplicate(),
			"pose": _pose_packed(r.get("pose", null)),
			"bones": (r.get("bones", {}) as Dictionary).duplicate(),
		}
		records.append(rec)
''',
        '"pose": _pose_packed(r.get("pose", null)),',
    ),
])

# ---------------------------------------------------------------- DroppedItem
patch("scripts/DroppedItem.gd", [
    (
        '''			elif nm == "Old Rucksack":
				_build_rucksack()
			else:
''',
        '''			elif nm == "Old Rucksack":
				_build_rucksack()
			elif item.has("bone"):
				_build_bone(String(item["bone"]))
			else:
''',
        'elif item.has("bone"):',
    ),
    (
        '''func _build_billet() -> void:
''',
        '''func _build_bone(kind: String) -> void:
	## What is left of an animal when the woods are done with it. The carcass
	## bus lays these where each bone settled (CarcassBody._make_bone) and
	## they come back out of the pack the size they went in -- a moose femur
	## is not a hare's. Everything lies along +X, so the keep_yaw settle lays
	## it flat along its own length like a log. Never expires: "keep" is set.
	var L := float(item.get("bone_len", 0.30))
	var r := float(item.get("bone_r", 0.03))
	var w := float(item.get("bone_w", r * 4.0))
	var bone := Color(0.88, 0.85, 0.76)
	var old := Color(0.78, 0.74, 0.63)
	var dark := Color(0.10, 0.09, 0.08)
	match kind:
		"skull":
			## braincase, muzzle, two sockets and a row of teeth
			_add_box(Vector3(L * 0.52, w * 0.72, w * 0.82), bone, Vector3(-L * 0.20, w * 0.36, 0))
			_add_box(Vector3(L * 0.50, w * 0.42, w * 0.50), bone, Vector3(L * 0.24, w * 0.22, 0))
			_add_box(Vector3(L * 0.14, w * 0.20, w * 0.20), dark, Vector3(L * 0.03, w * 0.48, w * 0.30))
			_add_box(Vector3(L * 0.14, w * 0.20, w * 0.20), dark, Vector3(L * 0.03, w * 0.48, -w * 0.30))
			_add_box(Vector3(L * 0.44, w * 0.07, w * 0.46), old, Vector3(L * 0.26, w * 0.03, 0))
		"ribs":
			## a spine along +X and the ribs hanging off it either side
			_add_box(Vector3(L, r * 1.6, r * 1.6), bone, Vector3(0, r * 0.8, 0))
			var n := clampi(int(round(L / 0.16)), 3, 9)
			for i in n:
				var x := (float(i) + 0.5) / float(n) * L - L * 0.5
				for s in [-1.0, 1.0]:
					_add_box(Vector3(r * 1.2, r * 1.2, w * 0.46), old,
						Vector3(x, r * 0.6, s * w * 0.24), Vector3(s * 26.0, 0, 0))
		_:
			## a long bone: the shaft and a knob at each end
			_add_box(Vector3(L * 0.82, r * 1.4, r * 1.4), bone, Vector3(0, r * 0.7, 0))
			_add_box(Vector3(L * 0.16, r * 2.2, r * 2.4), old, Vector3(L * 0.42, r * 1.0, 0), Vector3(0, 0, 12))
			_add_box(Vector3(L * 0.16, r * 2.2, r * 2.4), old, Vector3(-L * 0.42, r * 1.0, 0), Vector3(0, 0, -12))


func _build_billet() -> void:
''',
        "func _build_bone(kind: String) -> void:",
    ),
])

# ---------------------------------------------------------------- World
patch("scripts/World.gd", [
    (
        '''	for d in get_tree().get_nodes_in_group("dropped_items"):
		var di := d as DroppedItem
		if di != null:
			dropped.append({"item": di.item.duplicate(true), "pos": di.global_position})
''',
        '''	for d in get_tree().get_nodes_in_group("dropped_items"):
		var di := d as DroppedItem
		## [carcasses] a bone still lying on its carcass is the CARCASS record's
		## to remember (CarcassBody lays it back down from the ledger); saving
		## it here too would put a second skull on the ground after a reload.
		if di != null and not di.has_meta("carcass_bone"):
			dropped.append({"item": di.item.duplicate(true), "pos": di.global_position})
''',
        'not di.has_meta("carcass_bone")',
    ),
])

# ---------------------------------------------------------------- Butchery
patch("scripts/Butchery.gd", [
    (
        '''	if Carcasses.stage_of(rec) >= Carcasses.STAGE_BONES:
		return "Bones. There is nothing on it to take"
''',
        '''	if Carcasses.stage_of(rec) >= Carcasses.STAGE_BONES:
		return "Bones. Nothing left to cut -- take them if you want them"
''',
        "take them if you want them",
    ),
])
patch("tools/mutate_butchery.py", [
    (
        '''     '\\tif Carcasses.stage_of(rec) >= Carcasses.STAGE_BONES:\\n\\t\\treturn "Bones. There is nothing on it to take"\\n', "\\n"),''',
        '''     '\\tif Carcasses.stage_of(rec) >= Carcasses.STAGE_BONES:\\n\\t\\treturn "Bones. Nothing left to cut -- take them if you want them"\\n', "\\n"),''',
        "take them if you want them",
    ),
])

print("done")
