class_name CritterRig
extends RefCounted

## ===========================================================================
## RIG FAMILIES — one skeleton per body plan.            docs/WILDLIFE.md §1
##
## Fourteen builders, sixty-five animals. A family owns a body PLAN and a set
## of named pivots; the dex owns the numbers. That split is the whole reason
## adding a species costs one dex entry: a marten is a fisher at 0.73 scale
## with a bib, and neither of them needed new code.
##
## Everything is boxes, in the game's existing no-texture language (see
## Boar.gd, Enemy._box_in). Bodies face -Z, same as every other creature —
## break that convention and every animation in CritterAnim points backwards.
##
## build() returns a Dictionary of pivots. The keys are a CONTRACT: CritterAnim
## addresses limbs by name and must never reach into the mesh tree itself.
##
##   root    the whole visible rig (Critter points loco_root here)
##   body    torso — lean, roll, crouch
##   neck    neck base pivot            head   head pivot (child of neck)
##   jaw     lower jaw                  legs   Array of hip pivots
##   knees   Array of lower-leg pivots, index-matched to legs
##   tail    tail base                  tail2  tail mid/tip
##   ears    Array                      wings  Array (2, or empty)
##   antler  antler/horn node           crest  raisable crest
##   quills  the bristle set (scaled on threat)
##   fan     spreadable tail fan (turkey, grouse)
##   mats    every material that should change on a coat swap
##   body_mat  the one Enemy's hit-flash drives
##
## Anything a family does not have is simply absent — CritterAnim checks.
## ===========================================================================

const FAMILIES := ["CERVID", "URSID", "CANID", "FELID", "MUSTELID", "CHUNK",
	"RODENT_S", "BIRD_GROUND", "BIRD_RAPTOR", "BIRD_PERCH", "BIRD_WATER",
	"HERP", "FISH", "SWARM"]


## --------------------------------------------------------- box plumbing ---

static func box(parent: Node, size: Vector3, col: Color, pos: Vector3,
		rot := Vector3.ZERO, rig := {}) -> MeshInstance3D:
	## One box. Matches Enemy._box_in's look exactly (flat shaded, no specular)
	## so wildlife sits in the same world as the goblins without a second
	## art pass. Every material made here is registered for coat swaps.
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.95
	mat.metallic = 0.0
	m.material_override = mat
	m.position = pos
	if rot != Vector3.ZERO:
		m.rotation_degrees = rot
	parent.add_child(m)
	if not rig.is_empty():
		(rig["mats"] as Array).append(mat)
	return m


static func pivot(parent: Node, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	parent.add_child(n)
	n.position = pos
	return n


static func glow(m: MeshInstance3D, col: Color, energy := 1.2) -> void:
	var mat := m.material_override as StandardMaterial3D
	if mat:
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = energy


static func eye(parent: Node, pos: Vector3, s: float, rig: Dictionary,
		col := Color(0.04, 0.04, 0.05)) -> void:
	## Eyes get their own list so night-shine can light them without touching
	## the coat.
	var m := box(parent, Vector3(s, s, s * 0.8), col, pos)
	var mat := m.material_override as StandardMaterial3D
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.52, 0.38)
	mat.emission_energy_multiplier = 0.0   ## Critter raises this at night
	(rig["eye_mats"] as Array).append(mat)


static func _new_rig(owner_node: Node3D) -> Dictionary:
	var root := Node3D.new()
	owner_node.add_child(root)
	return {
		"root": root, "body": null, "neck": null, "head": null, "jaw": null,
		"legs": [] as Array, "knees": [] as Array, "tail": null, "tail2": null,
		"ears": [] as Array, "wings": [] as Array, "antler": null,
		"crest": null, "quills": null, "fan": null,
		"mats": [] as Array, "eye_mats": [] as Array, "body_mat": null,
		"family": "", "ground_y": 0.0,
	}


## ================================ ENTRY ===================================

static func build(owner_node: Node3D, key: String) -> Dictionary:
	var p := CritterDex.get_profile(key)
	if p.is_empty():
		p = CritterDex.get_profile("hare")
	var rig := _new_rig(owner_node)
	rig["family"] = String(p.get("rig", "CHUNK"))
	match rig["family"]:
		"CERVID": _cervid(rig, p)
		"URSID": _ursid(rig, p)
		"CANID": _canid(rig, p)
		"FELID": _felid(rig, p)
		"MUSTELID": _mustelid(rig, p)
		"CHUNK": _chunk(rig, p)
		"RODENT_S": _rodent(rig, p)
		"BIRD_GROUND": _bird_ground(rig, p)
		"BIRD_RAPTOR": _bird_raptor(rig, p)
		"BIRD_PERCH": _bird_perch(rig, p)
		"BIRD_WATER": _bird_water(rig, p)
		"HERP": _herp(rig, p)
		"FISH": _fish(rig, p)
		"SWARM": _swarm(rig, p)
		_: _chunk(rig, p)
	return rig


## ============================== QUADRUPEDS ================================
## Four families share a skeleton and differ in proportion and detail:
## CERVID  long legs, long neck, small head, high shoulder
## URSID   massive, low head, no neck, plantigrade
## CANID   deep chest, long muzzle, level back, brush tail
## FELID   short muzzle, crouched, long tail, silent


static func _quad_legs(rig: Dictionary, hips: Array, leg_len: float, thick: float,
		col: Color, knee_frac := 0.5) -> void:
	## Four hip pivots with a knee each. Order is FL, FR, BL, BR — CritterAnim
	## and Enemy._update_locomotion both assume it.
	for hp: Vector3 in hips:
		var hip := pivot(rig["root"], hp)
		var upper := leg_len * knee_frac
		box(hip, Vector3(thick, upper, thick), col, Vector3(0, -upper * 0.5, 0), Vector3.ZERO, rig)
		var knee := pivot(hip, Vector3(0, -upper, 0))
		var lower := leg_len - upper
		box(knee, Vector3(thick * 0.78, lower, thick * 0.78), col, Vector3(0, -lower * 0.5, 0), Vector3.ZERO, rig)
		box(knee, Vector3(thick * 1.1, thick * 0.5, thick * 1.5), col * 0.75,
			Vector3(0, -lower + thick * 0.2, -thick * 0.3), Vector3.ZERO, rig)  ## hoof/paw
		(rig["legs"] as Array).append(hip)
		(rig["knees"] as Array).append(knee)


static func _cervid(rig: Dictionary, p: Dictionary) -> void:
	var L := float(p["len"])
	var H := float(p["hgt"])
	var col: Color = p["col"]
	var col2: Color = p["col2"]
	var col3: Color = p["col3"]
	var f: Dictionary = p.get("feat", {})
	var root: Node3D = rig["root"]

	var body_h := H * 0.34
	var back_y := H - body_h * 0.5
	var w := L * 0.30

	var body := pivot(root, Vector3(0, back_y, 0))
	rig["body"] = body
	var trunk := box(body, Vector3(w, body_h, L * 0.62), col, Vector3(0, 0, L * 0.04), Vector3.ZERO, rig)
	rig["body_mat"] = trunk.material_override as StandardMaterial3D
	## Shoulder hump — a moose is a wedge, a deer barely is.
	var hump := float(f.get("hump", 0.0))
	if hump > 0.0:
		box(body, Vector3(w * 0.86, body_h * hump * 2.0, L * 0.24), col,
			Vector3(0, body_h * 0.45, -L * 0.16), Vector3.ZERO, rig)
	box(body, Vector3(w * 0.94, body_h * 0.5, L * 0.30), col2,
		Vector3(0, -body_h * 0.38, L * 0.04), Vector3.ZERO, rig)  ## pale belly

	## Neck rakes up and forward from the shoulder.
	var neck := pivot(body, Vector3(0, body_h * 0.30, -L * 0.30))
	rig["neck"] = neck
	var nl := H * 0.34
	box(neck, Vector3(w * 0.46, nl, w * 0.44), col,
		Vector3(0, nl * 0.34, -nl * 0.24), Vector3(24, 0, 0), rig)

	var head := pivot(neck, Vector3(0, nl * 0.72, -nl * 0.50))
	rig["head"] = head
	var hs := L * 0.16
	box(head, Vector3(hs * 0.86, hs * 0.92, hs * 1.25), col, Vector3(0, 0, 0), Vector3.ZERO, rig)
	var muz := float(f.get("muzzle", 1.0))
	box(head, Vector3(hs * 0.62, hs * 0.58, hs * 0.95 * muz), col * 0.86,
		Vector3(0, -hs * 0.16, -hs * 0.95 * muz * 0.6), Vector3.ZERO, rig)
	var jaw := pivot(head, Vector3(0, -hs * 0.30, -hs * 0.30))
	rig["jaw"] = jaw
	box(jaw, Vector3(hs * 0.50, hs * 0.20, hs * 0.80 * muz), col * 0.72,
		Vector3(0, 0, -hs * 0.40 * muz), Vector3.ZERO, rig)
	if bool(f.get("dewlap", false)):
		## The bell — a moose's swinging throat flap, and the fastest way to
		## tell a moose from a very large deer at fifty metres.
		var bell := pivot(head, Vector3(0, -hs * 0.5, -hs * 0.1))
		rig["dewlap"] = bell
		box(bell, Vector3(hs * 0.26, hs * 1.5, hs * 0.30), col * 0.8,
			Vector3(0, -hs * 0.75, 0), Vector3.ZERO, rig)

	## Ears — big, and they pin flat when it means it.
	for sx in [-1.0, 1.0]:
		var ear := pivot(head, Vector3(sx * hs * 0.48, hs * 0.42, hs * 0.18))
		box(ear, Vector3(hs * 0.14, hs * 0.62, hs * 0.30), col * 0.9,
			Vector3(sx * hs * 0.1, hs * 0.3, 0), Vector3(0, 0, sx * -22), rig)
		(rig["ears"] as Array).append(ear)
	eye(head, Vector3(-hs * 0.42, hs * 0.14, -hs * 0.34), hs * 0.20, rig)
	eye(head, Vector3(hs * 0.42, hs * 0.14, -hs * 0.34), hs * 0.20, rig)

	## Antlers. Palmate slabs for moose, tined branches for deer.
	var ant := float(f.get("antler", 0.0))
	if ant > 0.0:
		var an := pivot(head, Vector3(0, hs * 0.55, hs * 0.05))
		rig["antler"] = an
		var span := L * 0.22 * ant
		if ant >= 1.2 or bool(f.get("palmate", false)):
			for sx in [-1.0, 1.0]:
				box(an, Vector3(span * 0.9, span * 0.14, span * 0.75), col3,
					Vector3(sx * span * 0.62, span * 0.22, 0), Vector3(0, 0, sx * 16), rig)
				for t in range(4):
					box(an, Vector3(span * 0.10, span * 0.34, span * 0.10), col3,
						Vector3(sx * (span * 0.30 + t * span * 0.24), span * 0.42, -span * 0.28 + t * span * 0.18),
						Vector3(0, 0, sx * 18), rig)
		else:
			for sx in [-1.0, 1.0]:
				box(an, Vector3(span * 0.10, span * 0.9, span * 0.10), col3,
					Vector3(sx * span * 0.3, span * 0.45, 0), Vector3(-14, 0, sx * 26), rig)
				for t in range(3):
					box(an, Vector3(span * 0.07, span * 0.42, span * 0.07), col3,
						Vector3(sx * (span * 0.42 + t * span * 0.10), span * 0.62 + t * span * 0.16, span * 0.10 * t),
						Vector3(-30, 0, sx * 18), rig)

	_quad_legs(rig, [
		Vector3(-w * 0.36, back_y - body_h * 0.4, -L * 0.24),
		Vector3(w * 0.36, back_y - body_h * 0.4, -L * 0.24),
		Vector3(-w * 0.36, back_y - body_h * 0.4, L * 0.26),
		Vector3(w * 0.36, back_y - body_h * 0.4, L * 0.26),
	], back_y - body_h * 0.4, w * 0.17, col * 0.82, 0.52)

	var tail := pivot(body, Vector3(0, body_h * 0.2, L * 0.32))
	rig["tail"] = tail
	var tl := L * (0.20 if bool(f.get("whitetail", false)) else 0.07)
	box(tail, Vector3(w * 0.24, tl, w * 0.16), col, Vector3(0, -tl * 0.4, tl * 0.2), Vector3(30, 0, 0), rig)
	if bool(f.get("whitetail", false)):
		## The flag: white underside, only seen when it goes up. That's the tell.
		box(tail, Vector3(w * 0.28, tl * 0.9, w * 0.06), col2,
			Vector3(0, -tl * 0.4, tl * 0.2 + w * 0.10), Vector3(30, 0, 0), rig)
	rig["ground_y"] = 0.0


static func _ursid(rig: Dictionary, p: Dictionary) -> void:
	var L := float(p["len"])
	var H := float(p["hgt"])
	var col: Color = p["col"]
	var col2: Color = p["col2"]
	var col3: Color = p["col3"]
	var f: Dictionary = p.get("feat", {})
	var root: Node3D = rig["root"]
	var body_h := H * 0.52
	var back_y := H - body_h * 0.42
	var w := L * 0.46

	var body := pivot(root, Vector3(0, back_y, 0))
	rig["body"] = body
	var trunk := box(body, Vector3(w, body_h, L * 0.78), col, Vector3.ZERO, Vector3.ZERO, rig)
	rig["body_mat"] = trunk.material_override as StandardMaterial3D
	var hump := float(f.get("hump", 0.2))
	box(body, Vector3(w * 0.9, body_h * hump, L * 0.34), col2,
		Vector3(0, body_h * 0.48, -L * 0.14), Vector3.ZERO, rig)
	box(body, Vector3(w * 0.72, body_h * 0.44, L * 0.44), col * 1.2,
		Vector3(0, -body_h * 0.34, L * 0.02), Vector3.ZERO, rig)

	## Barely any neck — a bear's head grows straight out of its shoulders.
	var neck := pivot(body, Vector3(0, body_h * 0.16, -L * 0.40))
	rig["neck"] = neck
	box(neck, Vector3(w * 0.62, body_h * 0.48, L * 0.14), col, Vector3(0, 0, -L * 0.05), Vector3.ZERO, rig)
	var head := pivot(neck, Vector3(0, body_h * 0.10, -L * 0.15))
	rig["head"] = head
	var hs := L * 0.24
	box(head, Vector3(hs * 0.94, hs * 0.86, hs * 1.0), col, Vector3.ZERO, Vector3.ZERO, rig)
	var muz := float(f.get("muzzle", 1.2))
	box(head, Vector3(hs * 0.54, hs * 0.48, hs * 0.66 * muz), col3,
		Vector3(0, -hs * 0.14, -hs * 0.60 * muz), Vector3.ZERO, rig)
	box(head, Vector3(hs * 0.20, hs * 0.16, hs * 0.14), Color(0.04, 0.04, 0.04),
		Vector3(0, -hs * 0.10, -hs * 1.02 * muz), Vector3.ZERO, rig)  ## nose
	var jaw := pivot(head, Vector3(0, -hs * 0.34, -hs * 0.24))
	rig["jaw"] = jaw
	box(jaw, Vector3(hs * 0.46, hs * 0.18, hs * 0.60 * muz), col3 * 0.8,
		Vector3(0, 0, -hs * 0.30 * muz), Vector3.ZERO, rig)
	for sx in [-1.0, 1.0]:
		var ear := pivot(head, Vector3(sx * hs * 0.42, hs * 0.46, hs * 0.18))
		box(ear, Vector3(hs * 0.30, hs * 0.30, hs * 0.14), col * 0.8, Vector3(0, hs * 0.12, 0), Vector3.ZERO, rig)
		(rig["ears"] as Array).append(ear)
	eye(head, Vector3(-hs * 0.30, hs * 0.14, -hs * 0.46), hs * 0.13, rig)
	eye(head, Vector3(hs * 0.30, hs * 0.14, -hs * 0.46), hs * 0.13, rig)

	## Short, thick, plantigrade legs — and real paws, because a bear stands
	## on them and swipes with them.
	var leg := back_y - body_h * 0.42
	for hp: Vector3 in [
			Vector3(-w * 0.40, leg, -L * 0.26), Vector3(w * 0.40, leg, -L * 0.26),
			Vector3(-w * 0.42, leg, L * 0.28), Vector3(w * 0.42, leg, L * 0.28)]:
		var hip := pivot(root, hp)
		box(hip, Vector3(w * 0.30, leg * 0.55, w * 0.32), col, Vector3(0, -leg * 0.28, 0), Vector3.ZERO, rig)
		var knee := pivot(hip, Vector3(0, -leg * 0.55, 0))
		box(knee, Vector3(w * 0.26, leg * 0.45, w * 0.28), col, Vector3(0, -leg * 0.22, 0), Vector3.ZERO, rig)
		var paw := box(knee, Vector3(w * 0.30, leg * 0.14, w * 0.46), col * 0.8,
			Vector3(0, -leg * 0.45 + leg * 0.06, -w * 0.08), Vector3.ZERO, rig)
		if bool(f.get("claw", false)):
			for c in range(3):
				box(knee, Vector3(w * 0.05, leg * 0.05, w * 0.12), col3 * 1.2,
					Vector3((c - 1) * w * 0.09, -leg * 0.44, -w * 0.28), Vector3.ZERO, rig)
		paw.name = "Paw"
		(rig["legs"] as Array).append(hip)
		(rig["knees"] as Array).append(knee)
	var tail := pivot(body, Vector3(0, 0, L * 0.40))
	rig["tail"] = tail
	box(tail, Vector3(w * 0.16, w * 0.16, L * 0.07), col, Vector3(0, 0, L * 0.03), Vector3.ZERO, rig)
	rig["ground_y"] = 0.0


static func _canid(rig: Dictionary, p: Dictionary) -> void:
	var L := float(p["len"])
	var H := float(p["hgt"])
	var col: Color = p["col"]
	var col2: Color = p["col2"]
	var col3: Color = p["col3"]
	var f: Dictionary = p.get("feat", {})
	var root: Node3D = rig["root"]
	var body_h := H * 0.36
	var back_y := H - body_h * 0.45
	var w := L * 0.26

	var body := pivot(root, Vector3(0, back_y, 0))
	rig["body"] = body
	var trunk := box(body, Vector3(w, body_h, L * 0.64), col, Vector3.ZERO, Vector3.ZERO, rig)
	rig["body_mat"] = trunk.material_override as StandardMaterial3D
	box(body, Vector3(w * 1.05, body_h * 1.06, L * 0.24), col,
		Vector3(0, 0, -L * 0.18), Vector3.ZERO, rig)                       ## deep chest
	box(body, Vector3(w * 0.86, body_h * 0.42, L * 0.46), col2,
		Vector3(0, -body_h * 0.36, L * 0.02), Vector3.ZERO, rig)           ## pale belly
	var ruff := float(f.get("ruff", 0.0))
	if ruff > 0.0:
		box(body, Vector3(w * 1.24, body_h * 1.1, L * 0.12), col * 0.92,
			Vector3(0, body_h * 0.05, -L * 0.28), Vector3.ZERO, rig)

	var neck := pivot(body, Vector3(0, body_h * 0.26, -L * 0.30))
	rig["neck"] = neck
	box(neck, Vector3(w * 0.62, body_h * 0.66, L * 0.16), col, Vector3(0, body_h * 0.12, -L * 0.06), Vector3(18, 0, 0), rig)
	var head := pivot(neck, Vector3(0, body_h * 0.32, -L * 0.15))
	rig["head"] = head
	var hs := L * 0.20
	box(head, Vector3(hs * 0.74, hs * 0.70, hs * 0.86), col, Vector3.ZERO, Vector3.ZERO, rig)
	var muz := float(f.get("muzzle", 1.2))
	box(head, Vector3(hs * 0.34, hs * 0.32, hs * 0.72 * muz), col * 0.9,
		Vector3(0, -hs * 0.14, -hs * 0.68 * muz), Vector3.ZERO, rig)
	box(head, Vector3(hs * 0.15, hs * 0.13, hs * 0.12), Color(0.05, 0.04, 0.04),
		Vector3(0, -hs * 0.10, -hs * 1.06 * muz), Vector3.ZERO, rig)
	var jaw := pivot(head, Vector3(0, -hs * 0.26, -hs * 0.22))
	rig["jaw"] = jaw
	box(jaw, Vector3(hs * 0.30, hs * 0.14, hs * 0.66 * muz), col3,
		Vector3(0, 0, -hs * 0.34 * muz), Vector3.ZERO, rig)
	## Big triangular ears that swivel — a fox's whole face is the ears.
	for sx in [-1.0, 1.0]:
		var ear := pivot(head, Vector3(sx * hs * 0.34, hs * 0.36, hs * 0.14))
		box(ear, Vector3(hs * 0.10, hs * 0.52, hs * 0.34), col3,
			Vector3(0, hs * 0.26, 0), Vector3(-6, 0, sx * -10), rig)
		(rig["ears"] as Array).append(ear)
	eye(head, Vector3(-hs * 0.28, hs * 0.10, -hs * 0.36), hs * 0.13, rig)
	eye(head, Vector3(hs * 0.28, hs * 0.10, -hs * 0.36), hs * 0.13, rig)

	var leg := back_y - body_h * 0.45
	_quad_legs(rig, [
		Vector3(-w * 0.42, leg, -L * 0.20), Vector3(w * 0.42, leg, -L * 0.20),
		Vector3(-w * 0.44, leg, L * 0.24), Vector3(w * 0.44, leg, L * 0.24),
	], leg, w * 0.24, col * 0.88 if not bool(f.get("socks", false)) else col, 0.55)
	if bool(f.get("socks", false)):
		## Black stockings — the red fox's giveaway.
		for kn in (rig["knees"] as Array):
			box(kn, Vector3(w * 0.22, leg * 0.4, w * 0.22), col3, Vector3(0, -leg * 0.24, 0), Vector3.ZERO, rig)

	var tail := pivot(body, Vector3(0, body_h * 0.10, L * 0.34))
	rig["tail"] = tail
	var tl := L * (0.52 if bool(f.get("brush_tail", false)) else 0.34)
	var tw := w * (1.05 if bool(f.get("brush_tail", false)) else 0.5)
	box(tail, Vector3(tw, tw * 0.9, tl), col, Vector3(0, -tl * 0.12, tl * 0.48), Vector3(14, 0, 0), rig)
	var tail2 := pivot(tail, Vector3(0, -tl * 0.24, tl * 0.9))
	rig["tail2"] = tail2
	if bool(f.get("tailtip", false)):
		box(tail2, Vector3(tw * 0.9, tw * 0.8, tl * 0.22), col2, Vector3(0, 0, tl * 0.1), Vector3.ZERO, rig)
	if bool(f.get("tailstripe", false)):
		box(tail, Vector3(tw * 0.3, tw * 1.0, tl * 0.9), col3, Vector3(0, -tl * 0.06, tl * 0.48), Vector3(14, 0, 0), rig)
	rig["ground_y"] = 0.0


static func _felid(rig: Dictionary, p: Dictionary) -> void:
	var L := float(p["len"])
	var H := float(p["hgt"])
	var col: Color = p["col"]
	var col2: Color = p["col2"]
	var col3: Color = p["col3"]
	var f: Dictionary = p.get("feat", {})
	var root: Node3D = rig["root"]
	var body_h := H * 0.34
	var back_y := H - body_h * 0.46
	var w := L * 0.28

	var body := pivot(root, Vector3(0, back_y, 0))
	rig["body"] = body
	var trunk := box(body, Vector3(w, body_h, L * 0.66), col, Vector3.ZERO, Vector3.ZERO, rig)
	rig["body_mat"] = trunk.material_override as StandardMaterial3D
	box(body, Vector3(w * 0.88, body_h * 0.46, L * 0.5), col2, Vector3(0, -body_h * 0.34, 0), Vector3.ZERO, rig)
	## Shoulder blades that ride high — the crouched cat silhouette.
	box(body, Vector3(w * 1.02, body_h * 0.34, L * 0.20), col,
		Vector3(0, body_h * 0.40, -L * 0.16), Vector3.ZERO, rig)
	if bool(f.get("spots", false)):
		for i in range(7):
			var a := float(i) * 2.399
			box(body, Vector3(w * 0.12, body_h * 0.10, L * 0.08), col3 * 1.4,
				Vector3(cos(a) * w * 0.44, sin(a) * body_h * 0.28, sin(a * 1.7) * L * 0.24), Vector3.ZERO, rig)

	var neck := pivot(body, Vector3(0, body_h * 0.18, -L * 0.32))
	rig["neck"] = neck
	box(neck, Vector3(w * 0.60, body_h * 0.56, L * 0.14), col, Vector3(0, 0, -L * 0.05), Vector3.ZERO, rig)
	var head := pivot(neck, Vector3(0, body_h * 0.14, -L * 0.13))
	rig["head"] = head
	var hs := L * 0.21
	box(head, Vector3(hs * 0.86, hs * 0.76, hs * 0.78), col, Vector3.ZERO, Vector3.ZERO, rig)
	box(head, Vector3(hs * 0.42, hs * 0.32, hs * 0.30), col2,
		Vector3(0, -hs * 0.20, -hs * 0.46), Vector3.ZERO, rig)   ## short blunt muzzle
	box(head, Vector3(hs * 0.13, hs * 0.10, hs * 0.09), Color(0.24, 0.14, 0.14),
		Vector3(0, -hs * 0.12, -hs * 0.60), Vector3.ZERO, rig)
	var jaw := pivot(head, Vector3(0, -hs * 0.28, -hs * 0.24))
	rig["jaw"] = jaw
	box(jaw, Vector3(hs * 0.36, hs * 0.14, hs * 0.34), col2 * 0.9, Vector3(0, 0, -hs * 0.16), Vector3.ZERO, rig)
	## Cheek ruff — the lynx's mutton chops, the whole reason it reads as a lynx.
	var ruff := float(f.get("ruff", 0.0))
	if ruff > 0.0:
		for sx in [-1.0, 1.0]:
			box(head, Vector3(hs * 0.18, hs * ruff * 3.0, hs * 0.34), col2,
				Vector3(sx * hs * 0.48, -hs * 0.20, -hs * 0.06), Vector3(0, 0, sx * 16), rig)
	for sx in [-1.0, 1.0]:
		var ear := pivot(head, Vector3(sx * hs * 0.34, hs * 0.38, hs * 0.06))
		box(ear, Vector3(hs * 0.09, hs * 0.40, hs * 0.28), col, Vector3(0, hs * 0.20, 0), Vector3(0, 0, sx * -12), rig)
		var tuft := float(f.get("tuft", 0.0))
		if tuft > 0.0:
			## Ear tufts. Nothing else says LYNX this cheaply.
			box(ear, Vector3(hs * 0.035, tuft * 6.0 * hs, hs * 0.035), col3,
				Vector3(0, hs * 0.40 + tuft * 3.0 * hs, 0), Vector3(0, 0, sx * -14), rig)
		(rig["ears"] as Array).append(ear)
	eye(head, Vector3(-hs * 0.28, hs * 0.10, -hs * 0.36), hs * 0.16, rig, Color(0.30, 0.42, 0.16))
	eye(head, Vector3(hs * 0.28, hs * 0.10, -hs * 0.36), hs * 0.16, rig, Color(0.30, 0.42, 0.16))

	var leg := back_y - body_h * 0.46
	var paw := float(f.get("bigpaw", 1.0))
	_quad_legs(rig, [
		Vector3(-w * 0.38, leg, -L * 0.20), Vector3(w * 0.38, leg, -L * 0.20),
		Vector3(-w * 0.40, leg, L * 0.24), Vector3(w * 0.40, leg, L * 0.24),
	], leg, w * 0.26, col * 0.94, 0.5)
	if paw > 1.05:
		## Snowshoe feet: the lynx walks ON the crust you post through.
		for kn in (rig["knees"] as Array):
			box(kn, Vector3(w * 0.30 * paw, leg * 0.07, w * 0.42 * paw), col2,
				Vector3(0, -leg * 0.48, -w * 0.06), Vector3.ZERO, rig)

	var tail := pivot(body, Vector3(0, body_h * 0.16, L * 0.34))
	rig["tail"] = tail
	var tl := L * float(f.get("longtail", f.get("bobtail", 0.14)))
	box(tail, Vector3(w * 0.28, w * 0.28, tl), col, Vector3(0, 0, tl * 0.5), Vector3(-10, 0, 0), rig)
	var tail2 := pivot(tail, Vector3(0, 0, tl))
	rig["tail2"] = tail2
	box(tail2, Vector3(w * 0.30, w * 0.30, tl * 0.24), col3, Vector3(0, 0, tl * 0.12), Vector3.ZERO, rig)
	rig["ground_y"] = 0.0


static func _mustelid(rig: Dictionary, p: Dictionary) -> void:
	## The long ones. Low, tubular, absurdly flexible — the body is built in
	## three linked segments so it can arch and bound like a slinky.
	var L := float(p["len"])
	var H := float(p["hgt"])
	var col: Color = p["col"]
	var col2: Color = p["col2"]
	var col3: Color = p["col3"]
	var f: Dictionary = p.get("feat", {})
	var root: Node3D = rig["root"]
	var body_h := H * 0.62
	var back_y := H - body_h * 0.4
	var w := L * 0.17

	var body := pivot(root, Vector3(0, back_y, 0))
	rig["body"] = body
	var trunk := box(body, Vector3(w, body_h, L * 0.40), col, Vector3(0, 0, L * 0.10), Vector3.ZERO, rig)
	rig["body_mat"] = trunk.material_override as StandardMaterial3D
	var mid := pivot(body, Vector3(0, 0, -L * 0.14))
	rig["spine"] = mid
	box(mid, Vector3(w * 0.98, body_h * 0.96, L * 0.30), col, Vector3(0, 0, -L * 0.12), Vector3.ZERO, rig)
	if bool(f.get("bib", false)):
		box(mid, Vector3(w * 0.7, body_h * 0.4, L * 0.16), col2, Vector3(0, -body_h * 0.34, -L * 0.16), Vector3.ZERO, rig)
	if bool(f.get("chinspot", false)):
		box(mid, Vector3(w * 0.4, body_h * 0.22, L * 0.06), col2, Vector3(0, -body_h * 0.38, -L * 0.24), Vector3.ZERO, rig)

	var neck := pivot(mid, Vector3(0, body_h * 0.10, -L * 0.26))
	rig["neck"] = neck
	box(neck, Vector3(w * 0.86, body_h * 0.74, L * 0.14), col, Vector3(0, 0, -L * 0.05), Vector3.ZERO, rig)
	var head := pivot(neck, Vector3(0, body_h * 0.06, -L * 0.12))
	rig["head"] = head
	var hs := L * 0.15
	box(head, Vector3(hs * 0.80, hs * 0.68, hs * 0.92), col, Vector3.ZERO, Vector3.ZERO, rig)
	box(head, Vector3(hs * 0.40, hs * 0.34, hs * 0.44), col * 0.9, Vector3(0, -hs * 0.12, -hs * 0.60), Vector3.ZERO, rig)
	box(head, Vector3(hs * 0.14, hs * 0.11, hs * 0.10), Color(0.14, 0.09, 0.09),
		Vector3(0, -hs * 0.10, -hs * 0.82), Vector3.ZERO, rig)
	var jaw := pivot(head, Vector3(0, -hs * 0.24, -hs * 0.24))
	rig["jaw"] = jaw
	box(jaw, Vector3(hs * 0.34, hs * 0.13, hs * 0.44), col2 * 0.7, Vector3(0, 0, -hs * 0.22), Vector3.ZERO, rig)
	for sx in [-1.0, 1.0]:
		var ear := pivot(head, Vector3(sx * hs * 0.32, hs * 0.28, hs * 0.16))
		box(ear, Vector3(hs * 0.22, hs * 0.20, hs * 0.09), col2, Vector3(0, hs * 0.06, 0), Vector3.ZERO, rig)
		(rig["ears"] as Array).append(ear)
	eye(head, Vector3(-hs * 0.26, hs * 0.10, -hs * 0.34), hs * 0.13, rig)
	eye(head, Vector3(hs * 0.26, hs * 0.10, -hs * 0.34), hs * 0.13, rig)

	## Stubby legs, tucked well under — they barely show at speed.
	var leg := back_y - body_h * 0.4
	_quad_legs(rig, [
		Vector3(-w * 0.5, leg, -L * 0.22), Vector3(w * 0.5, leg, -L * 0.22),
		Vector3(-w * 0.5, leg, L * 0.18), Vector3(w * 0.5, leg, L * 0.18),
	], leg, w * 0.42, col * 0.8, 0.5)

	var tail := pivot(body, Vector3(0, body_h * 0.06, L * 0.28))
	rig["tail"] = tail
	var bushy := float(f.get("bushy", 0.5))
	var thick := float(f.get("thicktail", 0.0))
	var tl := L * (0.42 if bushy > 0.6 else 0.30)
	var tw := w * (1.5 * bushy + 0.5 + (0.9 if thick > 0.0 else 0.0))
	box(tail, Vector3(tw, tw * 0.9, tl), col, Vector3(0, 0, tl * 0.5), Vector3(-8, 0, 0), rig)
	var tail2 := pivot(tail, Vector3(0, 0, tl * 0.95))
	rig["tail2"] = tail2
	box(tail2, Vector3(tw * 0.86, tw * 0.8, tl * 0.4), col if not bool(f.get("tailtip", false)) else col3,
		Vector3(0, 0, tl * 0.2), Vector3.ZERO, rig)
	rig["ground_y"] = 0.0


static func _chunk(rig: Dictionary, p: Dictionary) -> void:
	## The low waddlers, plus the seals (a flippered chunk is still a chunk).
	var L := float(p["len"])
	var H := float(p["hgt"])
	var col: Color = p["col"]
	var col2: Color = p["col2"]
	var col3: Color = p["col3"]
	var f: Dictionary = p.get("feat", {})
	var root: Node3D = rig["root"]
	var flipper := bool(f.get("flipper", false))
	var body_h := H * (0.86 if flipper else 0.62)
	var back_y := H - body_h * 0.45
	var w := L * (0.30 if flipper else 0.40)

	var body := pivot(root, Vector3(0, back_y, 0))
	rig["body"] = body
	var trunk := box(body, Vector3(w, body_h, L * 0.66), col, Vector3.ZERO, Vector3.ZERO, rig)
	rig["body_mat"] = trunk.material_override as StandardMaterial3D
	if bool(f.get("humped", false)):
		box(body, Vector3(w * 0.9, body_h * 0.5, L * 0.4), col,
			Vector3(0, body_h * 0.42, L * 0.06), Vector3.ZERO, rig)
	box(body, Vector3(w * 0.82, body_h * 0.42, L * 0.5), col2, Vector3(0, -body_h * 0.36, 0), Vector3.ZERO, rig)
	if bool(f.get("stripe", false)):
		## The skunk's two white racing stripes. Readable at night, which is
		## exactly when you need to read them.
		for sx in [-1.0, 1.0]:
			box(body, Vector3(w * 0.16, body_h * 0.28, L * 0.72), col2,
				Vector3(sx * w * 0.24, body_h * 0.36, 0), Vector3.ZERO, rig)
	if bool(f.get("spots", false)):
		for i in range(9):
			var a := float(i) * 2.399
			box(body, Vector3(w * 0.10, body_h * 0.08, L * 0.09), col3,
				Vector3(cos(a) * w * 0.42, sin(a * 1.3) * body_h * 0.3, sin(a) * L * 0.26), Vector3.ZERO, rig)

	var neck := pivot(body, Vector3(0, body_h * 0.10, -L * 0.32))
	rig["neck"] = neck
	box(neck, Vector3(w * 0.68, body_h * 0.6, L * 0.10), col, Vector3.ZERO, Vector3.ZERO, rig)
	var head := pivot(neck, Vector3(0, 0, -L * 0.11))
	rig["head"] = head
	var hs := L * 0.24
	box(head, Vector3(hs * 0.82, hs * 0.72, hs * 0.86), col, Vector3.ZERO, Vector3.ZERO, rig)
	var pointy := bool(f.get("pointface", false)) or bool(f.get("horseface", false))
	var muz := float(f.get("muzzle", 1.4 if pointy else 0.9))
	box(head, Vector3(hs * 0.40, hs * 0.34, hs * 0.44 * muz), col2 if pointy else col * 0.88,
		Vector3(0, -hs * 0.14, -hs * 0.50 * muz), Vector3.ZERO, rig)
	box(head, Vector3(hs * 0.13, hs * 0.11, hs * 0.10), Color(0.10, 0.08, 0.08),
		Vector3(0, -hs * 0.12, -hs * 0.74 * muz), Vector3.ZERO, rig)
	var jaw := pivot(head, Vector3(0, -hs * 0.26, -hs * 0.20))
	rig["jaw"] = jaw
	box(jaw, Vector3(hs * 0.34, hs * 0.13, hs * 0.44 * muz), col * 0.7, Vector3(0, 0, -hs * 0.22 * muz), Vector3.ZERO, rig)
	if bool(f.get("incisor", false)):
		## Beaver teeth: orange, oversized, permanently visible.
		box(head, Vector3(hs * 0.20, hs * 0.16, hs * 0.08), Color(0.86, 0.54, 0.10),
			Vector3(0, -hs * 0.28, -hs * 0.70), Vector3.ZERO, rig)
	if bool(f.get("mask", false)):
		## The raccoon's bandit mask, in three boxes.
		box(head, Vector3(hs * 0.86, hs * 0.20, hs * 0.10), col3,
			Vector3(0, hs * 0.06, -hs * 0.44), Vector3.ZERO, rig)
		box(head, Vector3(hs * 0.86, hs * 0.14, hs * 0.34), col2,
			Vector3(0, hs * 0.26, -hs * 0.30), Vector3.ZERO, rig)
	for sx in [-1.0, 1.0]:
		var ear := pivot(head, Vector3(sx * hs * 0.34, hs * 0.34, hs * 0.10))
		var esz := 0.30 if not flipper else 0.0
		if esz > 0.0:
			box(ear, Vector3(hs * esz * 0.8, hs * esz, hs * 0.10), col * 0.85, Vector3(0, hs * 0.10, 0), Vector3.ZERO, rig)
		(rig["ears"] as Array).append(ear)
	eye(head, Vector3(-hs * 0.26, hs * 0.10, -hs * 0.36), hs * (0.20 if flipper else 0.13), rig)
	eye(head, Vector3(hs * 0.26, hs * 0.10, -hs * 0.36), hs * (0.20 if flipper else 0.13), rig)

	var leg := back_y - body_h * 0.45
	if flipper:
		## Seals: fore-flippers at the shoulder, hind flippers trailing. They
		## do not walk — CritterAnim humps them along instead.
		for sx in [-1.0, 1.0]:
			var fl := pivot(body, Vector3(sx * w * 0.5, -body_h * 0.28, -L * 0.16))
			box(fl, Vector3(w * 0.10, body_h * 0.16, L * 0.20), col * 0.85,
				Vector3(sx * w * 0.10, 0, L * 0.06), Vector3(0, sx * 20, 0), rig)
			(rig["legs"] as Array).append(fl)
		var hind := pivot(body, Vector3(0, -body_h * 0.24, L * 0.36))
		rig["tail"] = hind
		for sx in [-1.0, 1.0]:
			box(hind, Vector3(w * 0.14, body_h * 0.34, L * 0.22), col * 0.8,
				Vector3(sx * w * 0.16, 0, L * 0.10), Vector3(0, sx * -22, 0), rig)
	else:
		_quad_legs(rig, [
			Vector3(-w * 0.42, leg, -L * 0.22), Vector3(w * 0.42, leg, -L * 0.22),
			Vector3(-w * 0.44, leg, L * 0.24), Vector3(w * 0.44, leg, L * 0.24),
		], leg, w * 0.30, col * 0.8, 0.5)

		var tail := pivot(body, Vector3(0, 0, L * 0.34))
		rig["tail"] = tail
		if bool(f.get("paddle", false)):
			## The beaver's paddle. Flat, wide, and the loudest thing in the bog.
			box(tail, Vector3(w * 0.86, L * 0.035, L * 0.40), col3,
				Vector3(0, -body_h * 0.22, L * 0.22), Vector3(6, 0, 0), rig)
		elif bool(f.get("ratrail", false)):
			box(tail, Vector3(w * 0.10, w * 0.10, L * 0.60), col2 * 0.9,
				Vector3(0, -body_h * 0.06, L * 0.30), Vector3(8, 0, 0), rig)
		elif bool(f.get("shorttail", false)):
			box(tail, Vector3(w * 0.24, w * 0.20, L * 0.12), col, Vector3(0, 0, L * 0.06), Vector3.ZERO, rig)
		else:
			var bushy := float(f.get("bushy", 0.8))
			var tl := L * 0.46 * bushy
			box(tail, Vector3(w * 0.7 * bushy, w * 0.66 * bushy, tl), col,
				Vector3(0, tl * 0.16, tl * 0.44), Vector3(-26, 0, 0), rig)
			var t2 := pivot(tail, Vector3(0, tl * 0.3, tl * 0.86))
			rig["tail2"] = t2
			var rings := int(f.get("ringtail", 0))
			for r in range(rings):
				box(tail, Vector3(w * 0.74 * bushy, w * 0.70 * bushy, tl * 0.12),
					col3 if r % 2 == 0 else col2,
					Vector3(0, tl * 0.06 * r, tl * 0.12 + r * tl * 0.17), Vector3(-26, 0, 0), rig)

	## Quills. One node, scaled up when the animal means it — the silhouette
	## doubling IS the warning, so it has to be one transform, not 200 boxes
	## animating individually.
	if bool(f.get("quill", false)) or float(f.get("quill", 0.0)) > 0.0:
		var q := pivot(body, Vector3(0, body_h * 0.34, L * 0.04))
		rig["quills"] = q
		var ql := float(f.get("quill", 0.2)) * L
		for i in range(26):
			var a := float(i) * 2.399
			var rx := cos(a) * w * 0.42
			var rz := sin(a * 0.7) * L * 0.30
			box(q, Vector3(L * 0.012, ql, L * 0.012), col3,
				Vector3(rx, ql * 0.4, rz),
				Vector3(rad_to_deg(atan2(rz, ql)) * 0.4, 0, rad_to_deg(atan2(rx, ql)) * -0.5), rig)
	rig["ground_y"] = 0.0


static func _rodent(rig: Dictionary, p: Dictionary) -> void:
	## Squirrels, chipmunks and the hare. Small, upright-capable, big tail or
	## big ears, and they sit up on their haunches — which is most of their
	## personality.
	var L := float(p["len"])
	var H := float(p["hgt"])
	var col: Color = p["col"]
	var col2: Color = p["col2"]
	var col3: Color = p["col3"]
	var f: Dictionary = p.get("feat", {})
	var root: Node3D = rig["root"]
	var body_h := H * 0.52
	var back_y := H - body_h * 0.45
	var w := L * 0.40

	var body := pivot(root, Vector3(0, back_y, 0))
	rig["body"] = body
	var trunk := box(body, Vector3(w, body_h, L * 0.66), col, Vector3.ZERO, Vector3.ZERO, rig)
	rig["body_mat"] = trunk.material_override as StandardMaterial3D
	box(body, Vector3(w * 0.8, body_h * 0.42, L * 0.5), col2, Vector3(0, -body_h * 0.34, 0), Vector3.ZERO, rig)
	if bool(f.get("stripe", false)):
		## Chipmunk racing stripes.
		for sx in [-1.0, 0.0, 1.0]:
			box(body, Vector3(w * 0.09, body_h * 0.16, L * 0.62), col3,
				Vector3(sx * w * 0.26, body_h * 0.40, 0), Vector3.ZERO, rig)
			if sx != 0.0:
				box(body, Vector3(w * 0.07, body_h * 0.14, L * 0.6), col2,
					Vector3(sx * w * 0.38, body_h * 0.30, 0), Vector3.ZERO, rig)

	var neck := pivot(body, Vector3(0, body_h * 0.20, -L * 0.30))
	rig["neck"] = neck
	box(neck, Vector3(w * 0.66, body_h * 0.5, L * 0.09), col, Vector3.ZERO, Vector3.ZERO, rig)
	var head := pivot(neck, Vector3(0, body_h * 0.06, -L * 0.10))
	rig["head"] = head
	var hs := L * 0.28
	box(head, Vector3(hs * 0.74, hs * 0.68, hs * 0.78), col, Vector3.ZERO, Vector3.ZERO, rig)
	box(head, Vector3(hs * 0.36, hs * 0.30, hs * 0.32), col * 0.9, Vector3(0, -hs * 0.14, -hs * 0.48), Vector3.ZERO, rig)
	box(head, Vector3(hs * 0.11, hs * 0.09, hs * 0.08), Color(0.28, 0.16, 0.16),
		Vector3(0, -hs * 0.12, -hs * 0.64), Vector3.ZERO, rig)
	var jaw := pivot(head, Vector3(0, -hs * 0.24, -hs * 0.18))
	rig["jaw"] = jaw
	box(jaw, Vector3(hs * 0.30, hs * 0.12, hs * 0.34), col2 * 0.8, Vector3(0, 0, -hs * 0.17), Vector3.ZERO, rig)
	## Ears: a hare's are the whole animal, a chipmunk's are two little coins.
	var elen := float(f.get("longear", 0.0))
	for sx in [-1.0, 1.0]:
		var ear := pivot(head, Vector3(sx * hs * 0.30, hs * 0.36, hs * 0.06))
		if elen > 0.0:
			box(ear, Vector3(hs * 0.16, elen * 4.0 * hs, hs * 0.08), col,
				Vector3(0, elen * 2.0 * hs, 0), Vector3(-8, 0, sx * -7), rig)
			box(ear, Vector3(hs * 0.10, elen * 3.4 * hs, hs * 0.03), col3,
				Vector3(0, elen * 2.0 * hs, -hs * 0.045), Vector3(-8, 0, sx * -7), rig)
		else:
			box(ear, Vector3(hs * 0.20, hs * 0.26, hs * 0.07), col * 0.85, Vector3(0, hs * 0.11, 0), Vector3.ZERO, rig)
		(rig["ears"] as Array).append(ear)
	if bool(f.get("eyering", false)):
		box(head, Vector3(hs * 0.26, hs * 0.22, hs * 0.04), col2,
			Vector3(-hs * 0.26, hs * 0.10, -hs * 0.38), Vector3.ZERO, rig)
		box(head, Vector3(hs * 0.26, hs * 0.22, hs * 0.04), col2,
			Vector3(hs * 0.26, hs * 0.10, -hs * 0.38), Vector3.ZERO, rig)
	eye(head, Vector3(-hs * 0.28, hs * 0.10, -hs * 0.36), hs * 0.15, rig)
	eye(head, Vector3(hs * 0.28, hs * 0.10, -hs * 0.36), hs * 0.15, rig)

	var leg := back_y - body_h * 0.45
	## Hind legs longer than fore — that's what makes a hop read as a hop.
	var big := bool(f.get("bigfoot", false))
	for i in range(4):
		var front := i < 2
		var sx := -1.0 if i % 2 == 0 else 1.0
		var hp := Vector3(sx * w * 0.40, leg, -L * 0.20 if front else L * 0.22)
		var hip := pivot(root, hp)
		var ll := leg * (0.72 if front else 1.0)
		box(hip, Vector3(w * 0.20, ll * 0.5, w * 0.20), col * 0.9, Vector3(0, -ll * 0.25, 0), Vector3.ZERO, rig)
		var knee := pivot(hip, Vector3(0, -ll * 0.5, 0))
		box(knee, Vector3(w * 0.17, ll * 0.5, w * 0.17), col * 0.9, Vector3(0, -ll * 0.25, 0), Vector3.ZERO, rig)
		var fl := L * (0.24 if (big and not front) else 0.10)
		box(knee, Vector3(w * 0.20, ll * 0.10, fl), col2 * 0.9,
			Vector3(0, -ll * 0.5, -fl * 0.28), Vector3.ZERO, rig)
		(rig["legs"] as Array).append(hip)
		(rig["knees"] as Array).append(knee)

	var tail := pivot(body, Vector3(0, body_h * 0.24, L * 0.32))
	rig["tail"] = tail
	if bool(f.get("puff_tail", false)):
		box(tail, Vector3(w * 0.5, w * 0.5, L * 0.12), col2, Vector3(0, 0, L * 0.06), Vector3.ZERO, rig)
	else:
		var plume := float(f.get("plumetail", 1.0))
		var tl := L * 0.8 * plume
		box(tail, Vector3(w * 0.34, w * 0.62 * plume, tl), col,
			Vector3(0, tl * 0.34, tl * 0.34), Vector3(-52, 0, 0), rig)
		var t2 := pivot(tail, Vector3(0, tl * 0.66, tl * 0.5))
		rig["tail2"] = t2
		box(t2, Vector3(w * 0.30, w * 0.56 * plume, tl * 0.44), col,
			Vector3(0, tl * 0.16, -tl * 0.06), Vector3(-16, 0, 0), rig)
	rig["ground_y"] = 0.0


## ================================= BIRDS ==================================
## All four bird families share a plan: an egg body, a neck, two folding
## wings, a tail fan, and two backward-kneed legs. They differ in leg length,
## bill, and how much of their life happens in the air.


static func _bird_common(rig: Dictionary, p: Dictionary, leg_frac: float,
		neck_frac: float, upright: float) -> Dictionary:
	var L := float(p["len"])
	var H := float(p["hgt"])
	var col: Color = p["col"]
	var col2: Color = p["col2"]
	var col3: Color = p["col3"]
	var f: Dictionary = p.get("feat", {})
	var root: Node3D = rig["root"]
	var leg_len := H * leg_frac
	var body_h := L * 0.42
	var back_y := leg_len + body_h * 0.5
	var w := L * 0.36

	var body := pivot(root, Vector3(0, back_y, 0))
	rig["body"] = body
	body.rotation_degrees.x = -upright
	var trunk := box(body, Vector3(w, body_h, L * 0.62), col, Vector3.ZERO, Vector3.ZERO, rig)
	rig["body_mat"] = trunk.material_override as StandardMaterial3D
	box(body, Vector3(w * 0.84, body_h * 0.5, L * 0.48), col2, Vector3(0, -body_h * 0.32, -L * 0.04), Vector3.ZERO, rig)
	if bool(f.get("fluffy", false)):
		box(body, Vector3(w * 1.14, body_h * 1.06, L * 0.5), col, Vector3(0, 0, L * 0.02), Vector3.ZERO, rig)
	if bool(f.get("barring", false)):
		for i in range(4):
			box(body, Vector3(w * 1.02, body_h * 0.06, L * 0.5), col2 * 0.8,
				Vector3(0, body_h * (0.26 - i * 0.16), -L * 0.02), Vector3.ZERO, rig)
	if bool(f.get("checker", false)):
		## The loon's white piano-key back. Unmistakable, four boxes.
		for i in range(6):
			@warning_ignore("integer_division")
			box(body, Vector3(w * 0.14, body_h * 0.08, L * 0.07), col2,
				Vector3((-1.0 if i % 2 == 0 else 1.0) * w * 0.24, body_h * 0.44,
					-L * 0.18 + float(i / 2) * L * 0.15), Vector3.ZERO, rig)

	## Neck. A heron's is half its height; a grouse barely has one.
	var neck := pivot(body, Vector3(0, body_h * 0.24, -L * 0.28))
	rig["neck"] = neck
	var nl := L * neck_frac
	if bool(f.get("longneck", false)) or float(f.get("longneck", 0.0)) > 0.0:
		nl = L * float(f.get("longneck", neck_frac))
	box(neck, Vector3(w * 0.36, nl, w * 0.34), col, Vector3(0, nl * 0.42, -nl * 0.10), Vector3(10, 0, 0), rig)
	if bool(f.get("necklace", false)):
		box(neck, Vector3(w * 0.42, nl * 0.20, w * 0.40), col2, Vector3(0, nl * 0.34, -nl * 0.08), Vector3(10, 0, 0), rig)
	if bool(f.get("chinstrap", false)):
		box(neck, Vector3(w * 0.42, nl * 0.30, w * 0.20), col2, Vector3(0, nl * 0.72, -nl * 0.20), Vector3(10, 0, 0), rig)

	var head := pivot(neck, Vector3(0, nl * 0.88, -nl * 0.20))
	rig["head"] = head
	var hs := L * 0.20
	box(head, Vector3(hs * 0.78, hs * 0.72, hs * 0.82), col, Vector3.ZERO, Vector3.ZERO, rig)
	if bool(f.get("whitehead", false)):
		box(head, Vector3(hs * 0.82, hs * 0.76, hs * 0.86), col2, Vector3(0, 0, 0), Vector3.ZERO, rig)
	if bool(f.get("cap", false)):
		box(head, Vector3(hs * 0.82, hs * 0.30, hs * 0.86), col3, Vector3(0, hs * 0.30, 0), Vector3.ZERO, rig)
	if bool(f.get("bib", false)):
		box(head, Vector3(hs * 0.44, hs * 0.30, hs * 0.30), col3, Vector3(0, -hs * 0.30, -hs * 0.28), Vector3.ZERO, rig)
	if bool(f.get("facedisc", false)):
		## The owl's face is a dish, and it's why an owl reads as an owl even
		## as a box: flat front plane, eyes forward, no muzzle.
		box(head, Vector3(hs * 0.96, hs * 0.94, hs * 0.14), col2,
			Vector3(0, hs * 0.04, -hs * 0.44), Vector3.ZERO, rig)
	if bool(f.get("eyestripe", false)):
		box(head, Vector3(hs * 0.86, hs * 0.14, hs * 0.30), col * 0.5, Vector3(0, hs * 0.06, -hs * 0.30), Vector3.ZERO, rig)
	if bool(f.get("malar", false)):
		for sx in [-1.0, 1.0]:
			box(head, Vector3(hs * 0.12, hs * 0.36, hs * 0.20), col * 0.4,
				Vector3(sx * hs * 0.32, -hs * 0.10, -hs * 0.32), Vector3.ZERO, rig)
	if bool(f.get("robbermask", false)):
		box(head, Vector3(hs * 0.9, hs * 0.18, hs * 0.16), col3, Vector3(0, 0, -hs * 0.34), Vector3.ZERO, rig)
	if bool(f.get("eartuft", false)) or float(f.get("eartuft", 0.0)) > 0.0:
		for sx in [-1.0, 1.0]:
			box(head, Vector3(hs * 0.10, float(f.get("eartuft", 0.1)) * 6.0 * hs, hs * 0.10), col,
				Vector3(sx * hs * 0.26, hs * 0.52, 0), Vector3(0, 0, sx * -14), rig)
	if bool(f.get("eyecomb", false)):
		for sx in [-1.0, 1.0]:
			box(head, Vector3(hs * 0.14, hs * 0.10, hs * 0.10), col3,
				Vector3(sx * hs * 0.30, hs * 0.22, -hs * 0.26), Vector3.ZERO, rig)

	## Crest — raisable, so it gets a pivot of its own.
	if bool(f.get("crest", false)):
		var cr := pivot(head, Vector3(0, hs * 0.34, hs * 0.06))
		rig["crest"] = cr
		box(cr, Vector3(hs * 0.14, hs * 0.46, hs * 0.34), col3 if bool(f.get("chisel", false)) else col,
			Vector3(0, hs * 0.22, hs * 0.04), Vector3(16, 0, 0), rig)

	## Bill. Five shapes cover every bird on the list.
	var jaw := pivot(head, Vector3(0, -hs * 0.06, -hs * 0.40))
	rig["jaw"] = jaw
	var bill_col := col3
	if bool(f.get("daggerbill", false)):
		box(jaw, Vector3(hs * 0.16, hs * 0.16, hs * 1.5), bill_col, Vector3(0, 0, -hs * 0.75), Vector3.ZERO, rig)
	elif bool(f.get("hookbill", false)):
		box(jaw, Vector3(hs * 0.24, hs * 0.24, hs * 0.34), bill_col, Vector3(0, 0, -hs * 0.17), Vector3.ZERO, rig)
		box(jaw, Vector3(hs * 0.16, hs * 0.22, hs * 0.16), bill_col * 0.7, Vector3(0, -hs * 0.12, -hs * 0.36), Vector3(28, 0, 0), rig)
	elif bool(f.get("flatbill", false)):
		box(jaw, Vector3(hs * 0.34, hs * 0.10, hs * 0.56), bill_col, Vector3(0, 0, -hs * 0.28), Vector3.ZERO, rig)
	elif bool(f.get("clownbill", false)):
		## The puffin. Deep, laterally flat, three colours.
		box(jaw, Vector3(hs * 0.10, hs * 0.52, hs * 0.44), Color(0.92, 0.44, 0.10), Vector3(0, -hs * 0.08, -hs * 0.24), Vector3.ZERO, rig)
		box(jaw, Vector3(hs * 0.11, hs * 0.46, hs * 0.16), Color(0.55, 0.58, 0.60), Vector3(0, -hs * 0.08, -hs * 0.06), Vector3.ZERO, rig)
	elif bool(f.get("chisel", false)):
		box(jaw, Vector3(hs * 0.14, hs * 0.16, hs * 0.60), Color(0.20, 0.20, 0.22), Vector3(0, 0, -hs * 0.30), Vector3.ZERO, rig)
	elif bool(f.get("longbill", false)) or float(f.get("longbill", 0.0)) > 0.0:
		var bl := float(f.get("longbill", 0.06)) / maxf(L, 0.01) * hs * 12.0
		box(jaw, Vector3(hs * 0.10, hs * 0.10, bl), bill_col * 0.8, Vector3(0, 0, -bl * 0.5), Vector3.ZERO, rig)
	elif bool(f.get("heavybill", false)):
		box(jaw, Vector3(hs * 0.22, hs * 0.22, hs * 0.52), bill_col, Vector3(0, 0, -hs * 0.26), Vector3.ZERO, rig)
	else:
		box(jaw, Vector3(hs * 0.14, hs * 0.13, hs * 0.34), bill_col, Vector3(0, 0, -hs * 0.17), Vector3.ZERO, rig)
	if bool(f.get("wattle", false)):
		box(head, Vector3(hs * 0.14, hs * 0.34, hs * 0.10), col3, Vector3(0, -hs * 0.36, -hs * 0.30), Vector3.ZERO, rig)
		box(head, Vector3(hs * 0.16, hs * 0.24, hs * 0.14), col3 * 1.1, Vector3(0, hs * 0.20, -hs * 0.46), Vector3(20, 0, 0), rig)
	if bool(f.get("bareneck", false)):
		box(neck, Vector3(w * 0.30, nl * 0.5, w * 0.28), col3, Vector3(0, nl * 0.7, -nl * 0.16), Vector3(10, 0, 0), rig)

	var eyesz := hs * (0.24 if bool(f.get("bigeye", false)) or bool(f.get("facedisc", false)) else 0.15)
	var eye_col := Color(0.90, 0.72, 0.10) if bool(f.get("facedisc", false)) or bool(f.get("hookbill", false)) else Color(0.05, 0.05, 0.06)
	eye(head, Vector3(-hs * 0.28, hs * 0.12, -hs * 0.36), eyesz, rig, eye_col)
	eye(head, Vector3(hs * 0.28, hs * 0.12, -hs * 0.36), eyesz, rig, eye_col)

	## Wings — one pivot each at the shoulder, folded along the body at rest.
	var wing := float(f.get("wing", 0.5))
	for sx in [-1.0, 1.0]:
		var wg := pivot(body, Vector3(sx * w * 0.46, body_h * 0.20, -L * 0.10))
		var wl := L * maxf(wing, 0.2) * 1.5
		box(wg, Vector3(wl * 0.9, L * 0.030, L * 0.30), col,
			Vector3(sx * wl * 0.42, 0, L * 0.06), Vector3(0, 0, sx * -6), rig)
		if bool(f.get("wingtip", false)):
			box(wg, Vector3(wl * 0.24, L * 0.032, L * 0.24), col3 * 0.3,
				Vector3(sx * wl * 0.78, 0, L * 0.10), Vector3(0, 0, sx * -6), rig)
		if bool(f.get("pointedwing", false)):
			box(wg, Vector3(wl * 0.4, L * 0.026, L * 0.14), col,
				Vector3(sx * wl * 0.78, 0, L * 0.14), Vector3(0, 0, sx * -10), rig)
		(rig["wings"] as Array).append(wg)

	## Tail fan — a pivot so turkeys and grouse can spread it.
	var tail := pivot(body, Vector3(0, body_h * 0.10, L * 0.30))
	rig["tail"] = tail
	rig["fan"] = tail
	var tl := L * (0.55 if bool(f.get("fan", false)) else 0.38)
	if bool(f.get("wedgetail", false)):
		box(tail, Vector3(w * 0.5, L * 0.028, tl), col, Vector3(0, 0, tl * 0.5), Vector3(-6, 0, 0), rig)
		box(tail, Vector3(w * 0.22, L * 0.028, tl * 0.4), col, Vector3(0, 0, tl * 1.1), Vector3(-6, 0, 0), rig)
	elif bool(f.get("stifftail", false)):
		box(tail, Vector3(w * 0.4, L * 0.04, tl), col, Vector3(0, -tl * 0.1, tl * 0.5), Vector3(12, 0, 0), rig)
	elif bool(f.get("fan", false)):
		for i in range(5):
			var a := (float(i) - 2.0) * 13.0
			box(tail, Vector3(w * 0.30, L * 0.024, tl), col if i % 2 == 0 else col2,
				Vector3(0, 0, tl * 0.5), Vector3(-8, a, 0), rig)
	else:
		box(tail, Vector3(w * 0.62, L * 0.028, tl), col, Vector3(0, 0, tl * 0.5), Vector3(-6, 0, 0), rig)

	## Two legs, knees backwards, feet forward.
	var toe_col := col3 if not bool(f.get("longleg", false)) else col3 * 0.8
	for sx in [-1.0, 1.0]:
		var hip := pivot(root, Vector3(sx * w * 0.24, leg_len, L * 0.02))
		box(hip, Vector3(L * 0.05, leg_len * 0.5, L * 0.05), col * 0.7, Vector3(0, -leg_len * 0.25, 0), Vector3.ZERO, rig)
		var knee := pivot(hip, Vector3(0, -leg_len * 0.5, 0))
		box(knee, Vector3(L * 0.042, leg_len * 0.5, L * 0.042), toe_col, Vector3(0, -leg_len * 0.25, 0), Vector3.ZERO, rig)
		box(knee, Vector3(L * 0.10, L * 0.020, L * 0.16), toe_col,
			Vector3(0, -leg_len * 0.5, -L * 0.05), Vector3.ZERO, rig)
		(rig["legs"] as Array).append(hip)
		(rig["knees"] as Array).append(knee)
	rig["ground_y"] = 0.0
	return rig


static func _bird_ground(rig: Dictionary, p: Dictionary) -> void:
	_bird_common(rig, p, 0.42, 0.16, 8.0)


static func _bird_raptor(rig: Dictionary, p: Dictionary) -> void:
	_bird_common(rig, p, 0.30, 0.12, 16.0)


static func _bird_perch(rig: Dictionary, p: Dictionary) -> void:
	_bird_common(rig, p, 0.26, 0.14, 14.0)


static func _bird_water(rig: Dictionary, p: Dictionary) -> void:
	var f: Dictionary = p.get("feat", {})
	var leg := 0.52 if bool(f.get("longleg", false)) else 0.18
	var up := 4.0 if bool(f.get("upright", false)) else 2.0
	_bird_common(rig, p, leg, 0.22, up)


## ============================ HERPS & FISH ================================


static func _herp(rig: Dictionary, p: Dictionary) -> void:
	var L := float(p["len"])
	var H := float(p["hgt"])
	var col: Color = p["col"]
	var col2: Color = p["col2"]
	var col3: Color = p["col3"]
	var f: Dictionary = p.get("feat", {})
	var root: Node3D = rig["root"]
	var body_h := H * 0.62
	var back_y := H - body_h * 0.5
	var w := L * (0.72 if bool(f.get("shell", false)) else (0.10 if bool(f.get("noleg", false)) else 0.44))

	var body := pivot(root, Vector3(0, back_y, 0))
	rig["body"] = body

	if bool(f.get("noleg", false)):
		## Snake: a chain of segments the anim slithers as a travelling wave.
		var segs: Array = []
		var n := 9
		var prev: Node3D = body
		for i in range(n):
			var sg := pivot(prev, Vector3(0, 0, L / float(n)) if i > 0 else Vector3.ZERO)
			var t := float(i) / float(n - 1)
			var sw := w * (1.0 - 0.55 * t)
			var m := box(sg, Vector3(sw, sw * 0.72, L / float(n) * 1.05), col if i % 2 == 0 else col * 0.88,
				Vector3.ZERO, Vector3.ZERO, rig)
			if i == 0:
				rig["body_mat"] = m.material_override as StandardMaterial3D
			if bool(f.get("stripes", false)):
				box(sg, Vector3(sw * 0.22, sw * 0.76, L / float(n) * 1.06), col2, Vector3.ZERO, Vector3.ZERO, rig)
			segs.append(sg)
			prev = sg
		rig["segments"] = segs
		var hd := pivot(body, Vector3(0, 0, -L * 0.06))
		rig["head"] = hd
		box(hd, Vector3(w * 1.1, w * 0.7, L * 0.09), col, Vector3(0, 0, -L * 0.04), Vector3.ZERO, rig)
		eye(hd, Vector3(-w * 0.4, w * 0.2, -L * 0.07), L * 0.018, rig)
		eye(hd, Vector3(w * 0.4, w * 0.2, -L * 0.07), L * 0.018, rig)
		rig["ground_y"] = 0.0
		return

	var trunk := box(body, Vector3(w, body_h * (0.5 if bool(f.get("shell", false)) else 0.8), L * 0.62),
		col, Vector3.ZERO, Vector3.ZERO, rig)
	rig["body_mat"] = trunk.material_override as StandardMaterial3D
	if bool(f.get("shell", false)):
		## The carapace: a dome of plates. Ridged for the snapper, smooth and
		## painted for the basker.
		var dome := pivot(body, Vector3(0, body_h * 0.22, 0))
		rig["shell"] = dome
		box(dome, Vector3(w * 1.02, body_h * 0.44, L * 0.72), col2 * 0.7, Vector3.ZERO, Vector3.ZERO, rig)
		if bool(f.get("ridged", false)):
			for k in range(3):
				box(dome, Vector3(w * 0.16, body_h * 0.24, L * 0.68), col3,
					Vector3((k - 1) * w * 0.28, body_h * 0.22, 0), Vector3.ZERO, rig)
		if bool(f.get("moss", false)):
			for i in range(8):
				var a := float(i) * 2.399
				box(dome, Vector3(w * 0.18, body_h * 0.10, L * 0.14), Color(0.20, 0.34, 0.16),
					Vector3(cos(a) * w * 0.34, body_h * 0.36, sin(a) * L * 0.26), Vector3.ZERO, rig)
		if bool(f.get("smoothshell", false)):
			box(dome, Vector3(w * 1.05, body_h * 0.20, L * 0.74), col, Vector3(0, body_h * 0.14, 0), Vector3.ZERO, rig)
		if bool(f.get("stripes", false)):
			for i in range(4):
				box(dome, Vector3(w * 1.06, body_h * 0.06, L * 0.06), col2,
					Vector3(0, body_h * 0.10, -L * 0.24 + i * L * 0.16), Vector3.ZERO, rig)

	var neck := pivot(body, Vector3(0, body_h * 0.06, -L * 0.30))
	rig["neck"] = neck
	box(neck, Vector3(w * 0.34, body_h * 0.34, L * 0.16), col, Vector3(0, 0, -L * 0.06), Vector3.ZERO, rig)
	var head := pivot(neck, Vector3(0, 0, -L * 0.14))
	rig["head"] = head
	var hs := L * (0.22 if bool(f.get("frog", false)) else 0.24)
	box(head, Vector3(hs * 0.90, hs * 0.60, hs * 0.90), col, Vector3.ZERO, Vector3.ZERO, rig)
	var jaw := pivot(head, Vector3(0, -hs * 0.24, -hs * 0.10))
	rig["jaw"] = jaw
	if bool(f.get("hookjaw", false)):
		## The beak that takes fingers off.
		box(head, Vector3(hs * 0.34, hs * 0.28, hs * 0.34), col3 * 0.8, Vector3(0, -hs * 0.06, -hs * 0.52), Vector3.ZERO, rig)
		box(jaw, Vector3(hs * 0.30, hs * 0.18, hs * 0.40), col2 * 0.6, Vector3(0, 0, -hs * 0.42), Vector3.ZERO, rig)
	else:
		box(jaw, Vector3(hs * 0.70, hs * 0.16, hs * 0.60), col2 * 0.7, Vector3(0, 0, -hs * 0.28), Vector3.ZERO, rig)
	if bool(f.get("robbermask", false)):
		box(head, Vector3(hs * 0.94, hs * 0.16, hs * 0.20), col3, Vector3(0, hs * 0.02, -hs * 0.30), Vector3.ZERO, rig)
	if bool(f.get("eardrum", false)):
		for sx in [-1.0, 1.0]:
			box(head, Vector3(hs * 0.06, hs * 0.26, hs * 0.26), col3, Vector3(sx * hs * 0.46, 0, -hs * 0.02), Vector3.ZERO, rig)
	var esz := hs * (0.30 if bool(f.get("frog", false)) else 0.16)
	eye(head, Vector3(-hs * 0.30, hs * 0.28, -hs * 0.24), esz, rig)
	eye(head, Vector3(hs * 0.30, hs * 0.28, -hs * 0.24), esz, rig)

	## Legs splay OUT to the side — that's what makes a reptile crawl instead
	## of walk.
	var leg := back_y - body_h * 0.5
	for i in range(4):
		var sx := -1.0 if i % 2 == 0 else 1.0
		var front := i < 2
		var hip := pivot(root, Vector3(sx * w * 0.44, back_y - body_h * 0.16, -L * 0.20 if front else L * 0.22))
		box(hip, Vector3(w * 0.34, leg * 0.34, w * 0.18), col * 0.85,
			Vector3(sx * w * 0.16, -leg * 0.16, 0), Vector3(0, 0, sx * 40), rig)
		var knee := pivot(hip, Vector3(sx * w * 0.30, -leg * 0.34, 0))
		box(knee, Vector3(w * 0.14, leg * 0.46, w * 0.14), col * 0.85, Vector3(0, -leg * 0.23, 0), Vector3.ZERO, rig)
		box(knee, Vector3(w * 0.24, leg * 0.10, w * 0.30), col2 * 0.8, Vector3(0, -leg * 0.46, -w * 0.06), Vector3.ZERO, rig)
		(rig["legs"] as Array).append(hip)
		(rig["knees"] as Array).append(knee)

	var tail := pivot(body, Vector3(0, body_h * 0.04, L * 0.32))
	rig["tail"] = tail
	if bool(f.get("sawtail", false)):
		var tl := L * 0.5
		box(tail, Vector3(w * 0.22, body_h * 0.22, tl), col, Vector3(0, 0, tl * 0.5), Vector3(-4, 0, 0), rig)
		for k in range(5):
			box(tail, Vector3(w * 0.06, body_h * 0.20, tl * 0.06), col3,
				Vector3(0, body_h * 0.18, tl * 0.12 + k * tl * 0.18), Vector3.ZERO, rig)
	elif not bool(f.get("frog", false)):
		var tl2 := L * 0.24
		box(tail, Vector3(w * 0.20, body_h * 0.16, tl2), col, Vector3(0, 0, tl2 * 0.5), Vector3.ZERO, rig)
	rig["ground_y"] = 0.0


static func _fish(rig: Dictionary, p: Dictionary) -> void:
	## Fish and cetaceans. Two body segments plus a tail that beats — sideways
	## for a fish, up-and-down for a porpoise (CritterAnim picks).
	var L := float(p["len"])
	var H := float(p["hgt"])
	var col: Color = p["col"]
	var col2: Color = p["col2"]
	var col3: Color = p["col3"]
	var f: Dictionary = p.get("feat", {})
	var root: Node3D = rig["root"]
	var w := H * 0.55

	var body := pivot(root, Vector3(0, 0, 0))
	rig["body"] = body
	var trunk := box(body, Vector3(w, H * 0.9, L * 0.52), col, Vector3(0, 0, -L * 0.10), Vector3.ZERO, rig)
	rig["body_mat"] = trunk.material_override as StandardMaterial3D
	box(body, Vector3(w * 0.9, H * 0.42, L * 0.46), col2, Vector3(0, -H * 0.30, -L * 0.10), Vector3.ZERO, rig)
	if bool(f.get("pleats", false)):
		for i in range(5):
			box(body, Vector3(w * 0.10, H * 0.34, L * 0.40), col2 * 0.8,
				Vector3((i - 2) * w * 0.16, -H * 0.34, -L * 0.18), Vector3.ZERO, rig)
	if bool(f.get("spots", false)):
		for i in range(8):
			var a := float(i) * 2.399
			box(body, Vector3(w * 0.10, H * 0.10, L * 0.06), col3,
				Vector3(cos(a) * w * 0.46, sin(a * 1.7) * H * 0.24, sin(a) * L * 0.18), Vector3.ZERO, rig)

	var head := pivot(body, Vector3(0, 0, -L * 0.34))
	rig["head"] = head
	box(head, Vector3(w * 0.82, H * 0.72, L * 0.24), col, Vector3(0, 0, -L * 0.10), Vector3.ZERO, rig)
	var jaw := pivot(head, Vector3(0, -H * 0.16, -L * 0.16))
	rig["jaw"] = jaw
	box(jaw, Vector3(w * 0.62, H * 0.14, L * 0.14), col2 * 0.8, Vector3(0, 0, -L * 0.06), Vector3.ZERO, rig)
	eye(head, Vector3(-w * 0.40, H * 0.16, -L * 0.16), H * 0.12, rig)
	eye(head, Vector3(w * 0.40, H * 0.16, -L * 0.16), H * 0.12, rig)

	if bool(f.get("dorsal", false)):
		box(body, Vector3(w * 0.10, H * 0.36, L * 0.20), col * 0.8, Vector3(0, H * 0.56, -L * 0.06), Vector3.ZERO, rig)
	if bool(f.get("flipper", false)):
		for sx in [-1.0, 1.0]:
			var fl := pivot(body, Vector3(sx * w * 0.44, -H * 0.18, -L * 0.16))
			box(fl, Vector3(w * 0.10, H * 0.10, L * 0.20), col * 0.85,
				Vector3(sx * w * 0.14, 0, L * 0.06), Vector3(0, sx * 22, 0), rig)
			(rig["legs"] as Array).append(fl)

	var tail := pivot(body, Vector3(0, 0, L * 0.22))
	rig["tail"] = tail
	box(tail, Vector3(w * 0.5, H * 0.5, L * 0.22), col, Vector3(0, 0, L * 0.11), Vector3.ZERO, rig)
	var tail2 := pivot(tail, Vector3(0, 0, L * 0.22))
	rig["tail2"] = tail2
	if bool(f.get("fluke", false)):
		box(tail2, Vector3(w * 2.2, H * 0.06, L * 0.14), col, Vector3(0, 0, L * 0.07), Vector3.ZERO, rig)
	elif bool(f.get("forkedtail", false)):
		box(tail2, Vector3(w * 0.10, H * 1.1, L * 0.16), col, Vector3(0, 0, L * 0.08), Vector3.ZERO, rig)
		box(tail2, Vector3(w * 0.10, H * 0.5, L * 0.10), col, Vector3(0, H * 0.44, L * 0.16), Vector3.ZERO, rig)
		box(tail2, Vector3(w * 0.10, H * 0.5, L * 0.10), col, Vector3(0, -H * 0.44, L * 0.16), Vector3.ZERO, rig)
	else:
		box(tail2, Vector3(w * 0.10, H * 0.9, L * 0.18), col, Vector3(0, 0, L * 0.09), Vector3.ZERO, rig)
	rig["ground_y"] = 0.0


static func _swarm(rig: Dictionary, p: Dictionary) -> void:
	## A single swarm member. The MultiMesh in CritterSwarm draws the crowd —
	## this one exists so a lone luna moth or a single dragonfly still has a
	## body, and so the swarm has a mesh to instance.
	var L := float(p["len"])
	var col: Color = p["col"]
	var col2: Color = p["col2"]
	var f: Dictionary = p.get("feat", {})
	var root: Node3D = rig["root"]
	var body := pivot(root, Vector3.ZERO)
	rig["body"] = body
	var trunk := box(body, Vector3(L * 0.34, L * 0.30, L), col, Vector3.ZERO, Vector3.ZERO, rig)
	rig["body_mat"] = trunk.material_override as StandardMaterial3D
	var wing := float(f.get("wing", 0.0))
	if wing > 0.0:
		for sx in [-1.0, 1.0]:
			var wg := pivot(body, Vector3(sx * L * 0.16, L * 0.10, 0))
			box(wg, Vector3(wing * 8.0 * L, L * 0.02, wing * 5.0 * L), col2,
				Vector3(sx * wing * 4.0 * L, 0, 0), Vector3.ZERO, rig)
			(rig["wings"] as Array).append(wg)
		if bool(f.get("tails", false)):
			## The luna moth's streamers — the reason it stops people.
			for sx in [-1.0, 1.0]:
				box(body, Vector3(L * 0.06, L * 0.02, L * 0.9), col2,
					Vector3(sx * L * 0.16, 0, L * 0.55), Vector3(0, sx * -10, 0), rig)
	if bool(CritterDex.flag(String(p.get("key", "")), "glows", false)):
		glow(trunk, col, 2.4)
	rig["ground_y"] = 0.0


## ============================== Utilities =================================


static func set_coat(rig: Dictionary, from_col: Color, to_col: Color, t: float) -> void:
	## The hare and the ermine turning white. One lerp over every registered
	## material — no mesh rebuild, same trick the leaf shader uses for autumn.
	var c := from_col.lerp(to_col, clampf(t, 0.0, 1.0))
	for m in (rig["mats"] as Array):
		var mat := m as StandardMaterial3D
		if mat:
			mat.albedo_color = mat.albedo_color.lerp(c, 0.0)  ## placeholder-safe
	## Real work: Critter caches originals and re-tints. See Critter._coat_tick.


static func eyeshine(rig: Dictionary, amount: float) -> void:
	## Night eyes. A coyote at the edge of your torchlight should be two
	## points of light before it is a coyote.
	for m in (rig["eye_mats"] as Array):
		var mat := m as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = amount


static func tint_all(rig: Dictionary, mul: Color) -> void:
	for m in (rig["mats"] as Array):
		var mat := m as StandardMaterial3D
		if mat:
			mat.albedo_color = mat.albedo_color * mul


static func spectral(rig: Dictionary, col: Color, energy := 1.6, alpha := 0.55) -> void:
	## The legends: the Specter Moose, the Aurora Herd, the White Raven. Same
	## body, lit from inside and half there.
	for m in (rig["mats"] as Array):
		var mat := m as StandardMaterial3D
		if mat == null:
			continue
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = energy
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var a := mat.albedo_color
		a.a = alpha
		mat.albedo_color = a
