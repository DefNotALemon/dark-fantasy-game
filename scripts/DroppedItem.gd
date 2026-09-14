class_name DroppedItem
extends Node3D
## An item thrown out of the pack (hover it in the inventory and press Q).
## Tossed with a little arc, tumbles, lands, and then just LIES there — no
## magnet. Picking it back up is deliberate: look at it and press E.
## Built from the same inventory dict it came from, so nothing is lost in
## the round trip (material swords stay material swords).

const REST_HEIGHT := 0.07    ## resting offset above the ground hit
const TOSS_SPIN := 3.2       ## tumble rate while airborne
const LIFE := 600.0          ## safety: fade out after 10 minutes on the floor
## ...except for things you took OUT OF THE WORLD rather than out of your pack.
## Timber is the case that matters: fell a tree, buck it into six logs, carry
## two home and come back for the rest, and a ten-minute fuse means the wood is
## gone. The CarryLogs this replaced never expired, and neither do these.
## Set "keep": true on the item dict (FallenTrunk does it for every log).
const KEEPS := {"Log": true, "Wood": true}

var item := {}               ## {name, weight, count, slot [, material]}
var velocity := Vector3.ZERO
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _resting := false
var _life := LIFE
var _refoot := randf_range(0.3, 0.6)  ## staggered footing re-checks while resting
## A bucked log is the actual piece of trunk it was cut from (FallenTrunk
## hands it over with adopt_log). It does not tumble like a tossed potion,
## and when it comes to rest it keeps lying along the line of the trunk
## instead of spinning to a random heading.
var keep_yaw := false
var tumble := true
var log_r := 0.0             ## radius of a log, for the thud's pitch; 0 = not a log


static func make(d: Dictionary) -> DroppedItem:
	var n := DroppedItem.new()
	n.item = d
	n._build_mesh()
	return n


func _ready() -> void:
	add_to_group("dropped_items")


func display_name() -> String:
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


func _keeps() -> bool:
	return bool(item.get("keep", false)) or KEEPS.has(String(item.get("name", "")))


func _physics_process(delta: float) -> void:
	if not _keeps():
		_life -= delta
		if _life <= 0.0:
			queue_free()
			return
	if _resting:
		## The world keeps moving under still things: floors get DUG out from
		## beneath loot, and sleep-shifts redraw whole caves. Re-check the
		## footing now and then — nothing below means we fall again, all the
		## way to the true ground.
		_refoot -= delta
		if _refoot <= 0.0:
			_refoot = randf_range(0.3, 0.6)
			var rspace := get_world_3d().direct_space_state
			var rq := PhysicsRayQueryParameters3D.create(
				global_position + Vector3.UP * 0.25, global_position + Vector3.DOWN * 0.7)
			if rspace.intersect_ray(rq).is_empty():
				_resting = false
				velocity = Vector3.ZERO
		return
	velocity.y -= gravity * delta
	velocity.x = move_toward(velocity.x, 0.0, delta * 0.8)
	velocity.z = move_toward(velocity.z, 0.0, delta * 0.8)
	global_position += velocity * delta
	if tumble:
		rotate_y(TOSS_SPIN * delta)
	if velocity.y >= 0.0:
		return
	## Falling: look for the ground under us and settle onto it. BODIES are
	## not ground — come down on a head or a boar's back and it glances off,
	## still falling, until actual world holds it.
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.3, global_position + Vector3.DOWN * 1.5)
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return
	if hit.collider is CharacterBody3D:
		if global_position.y <= float(hit.position.y) + 0.4:
			_glance_off(hit.collider as Node3D)
		return
	if global_position.y <= float(hit.position.y) + REST_HEIGHT:
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


func _glance_off(who: Node3D) -> void:
	## Bounced off someone: skitter sideways with a little pop and fall on.
	var away := global_position - who.global_position
	away.y = 0.0
	if away.length() < 0.05:
		away = Vector3(randf() - 0.5, 0.0, randf() - 0.5)
	away = away.normalized()
	velocity = away * randf_range(1.3, 2.2) + Vector3.UP * randf_range(1.2, 2.0)


## ------------------------------ Looks -------------------------------------


func _add_box(size: Vector3, col: Color, pos: Vector3, rot := Vector3.ZERO,
		metal := false, glow := Color(0, 0, 0)) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.35 if metal else 1.0
	if metal:
		mat.metallic = 0.7
	if glow != Color(0, 0, 0):
		mat.emission_enabled = true
		mat.emission = glow
		mat.emission_energy_multiplier = 1.2
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot
	add_child(m)
	return m


func _build_mesh() -> void:
	var slot := String(item.get("slot", ""))
	var mat_id := String(item.get("material", ""))
	var nm := String(item.get("name", ""))
	var col := Color(0.42, 0.32, 0.20)   ## generic loot: worn leather brown
	var metal := false
	var glow := Color(0, 0, 0)
	if mat_id != "":
		var m: Dictionary = Materials.get_mat(mat_id)
		col = m["color"]
		metal = true
		var elem: Dictionary = m["element"]
		if slot == "sword" and not elem.is_empty():
			glow = elem["color"]
	match slot:
		"sword":
			_add_box(Vector3(0.05, 0.08, 0.72), col, Vector3(0, 0, -0.12), Vector3.ZERO, true, glow)  ## blade
			_add_box(Vector3(0.22, 0.045, 0.045), Color(0.50, 0.42, 0.22), Vector3(0, 0, 0.27))       ## crossguard
			_add_box(Vector3(0.035, 0.035, 0.13), Color(0.12, 0.10, 0.09), Vector3(0, 0, 0.36))       ## grip
			_add_box(Vector3(0.05, 0.05, 0.045), Color(0.50, 0.42, 0.22), Vector3(0, 0, 0.44))        ## pommel
		"helmet":
			_add_box(Vector3(0.22, 0.20, 0.24), col, Vector3(0, 0.05, 0), Vector3.ZERO, metal)
			_add_box(Vector3(0.24, 0.045, 0.05), Color(0.08, 0.08, 0.09), Vector3(0, 0.06, -0.11))    ## visor slit
		"chest":
			_add_box(Vector3(0.32, 0.34, 0.16), col, Vector3(0, 0.1, 0), Vector3.ZERO, metal)
			_add_box(Vector3(0.34, 0.08, 0.17), col, Vector3(0, 0.30, 0), Vector3.ZERO, metal)        ## shoulder line
		"arms":
			_add_box(Vector3(0.11, 0.30, 0.11), col, Vector3(-0.09, 0.05, 0), Vector3(0, 0, 8), metal)
			_add_box(Vector3(0.11, 0.30, 0.11), col, Vector3(0.09, 0.05, 0), Vector3(0, 0, -8), metal)
		"pants":
			_add_box(Vector3(0.24, 0.12, 0.15), col, Vector3(0, 0.16, 0), Vector3.ZERO, metal)        ## waist
			_add_box(Vector3(0.10, 0.26, 0.13), col, Vector3(-0.07, -0.02, 0), Vector3.ZERO, metal)
			_add_box(Vector3(0.10, 0.26, 0.13), col, Vector3(0.07, -0.02, 0), Vector3.ZERO, metal)
		"shoes":
			_add_box(Vector3(0.10, 0.09, 0.26), col, Vector3(-0.08, 0.02, 0), Vector3.ZERO, metal)
			_add_box(Vector3(0.10, 0.09, 0.26), col, Vector3(0.08, 0.02, 0), Vector3.ZERO, metal)
		"offhand":
			if nm.contains("Torch"):
				_add_box(Vector3(0.045, 0.40, 0.045), Color(0.35, 0.24, 0.13), Vector3(0, 0.1, 0), Vector3(0, 0, 78))
				_add_box(Vector3(0.075, 0.075, 0.075), Color(1.0, 0.45, 0.10), Vector3(0.24, 0.14, 0),
					Vector3.ZERO, false, Color(1.0, 0.45, 0.10))
			else:  ## shield: boards + rim + boss, lying face-up
				_add_box(Vector3(0.34, 0.045, 0.44), Color(0.38, 0.26, 0.14), Vector3(0, 0.02, 0))
				_add_box(Vector3(0.44, 0.045, 0.30), Color(0.38, 0.26, 0.14), Vector3(0, 0.02, 0))
				_add_box(Vector3(0.10, 0.07, 0.10), Color(0.60, 0.63, 0.68), Vector3(0, 0.05, 0), Vector3.ZERO, true)
		_:
			if nm == "Stick":
				_build_stick()
			elif nm == "Wood" or nm == "Log":
				_build_billet()
			elif nm == "Crystal Shard":
				_build_shard(Color(item.get("glow", Color(0.35, 0.85, 1.0))))
			elif mat_id != "" and nm.ends_with(" Ore"):
				_build_ore(mat_id)
			elif nm == "Health Potion":
				_build_potion()
			elif nm == "Old Rucksack":
				_build_rucksack()
			elif item.has("bone"):
				_build_bone(String(item["bone"]))
			else:
				## Plain loot (tusks, bones, pickaxes...): a humble bundle.
				_add_box(Vector3(0.16, 0.14, 0.16), col, Vector3(0, 0.05, 0))
				_add_box(Vector3(0.19, 0.05, 0.05), Color(0.30, 0.24, 0.16), Vector3(0, 0.12, 0), Vector3(0, 25, 0))


func _build_ore(mat_id: String) -> void:
	## A PIECE OF THE VEIN, not a parcel: the same dark rock lump the standing
	## vein is made of, shot through with the same glowing seam studs, at
	## roughly half the parent's size — big enough to spot across a dark
	## chamber by its own glint, unmistakably a chunk OF the thing you broke.
	var m: Dictionary = Materials.get_mat(mat_id)
	var seam_col: Color = m["color"]
	var elem: Dictionary = m["element"]
	var glow_col: Color = seam_col if elem.is_empty() else Color(elem["color"])
	var rock_col := Color(0.16, 0.15, 0.17)
	## The rock: two tilted lumps, vein-shaped, about half a vein tall.
	_add_box(Vector3(0.62, 0.50, 0.62), rock_col,
		Vector3(0, 0.25, 0), Vector3(randf_range(-9, 9), randf() * 360.0, randf_range(-9, 9)))
	_add_box(Vector3(0.44, 0.36, 0.44), rock_col,
		Vector3(randf_range(-0.12, 0.12), 0.52, randf_range(-0.12, 0.12)),
		Vector3(randf_range(-15, 15), randf() * 360.0, randf_range(-15, 15)))
	## The seams: bright studs punched through the faces, glowing the metal's
	## color (elemental metals burn their element's color, like the vein).
	for _i in range(randi_range(4, 6)):
		var a := randf() * TAU
		var h := randf_range(0.12, 0.55)
		var r := 0.30 if h < 0.44 else 0.21
		_add_box(Vector3.ONE * randf_range(0.09, 0.14), seam_col,
			Vector3(cos(a) * r, h, sin(a) * r),
			Vector3(randf_range(-20, 20), randf() * 360.0, randf_range(-20, 20)),
			true, glow_col)


func _add_branch(len_v: float, rad: float, col: Color, pos: Vector3, rot: Vector3) -> MeshInstance3D:
	## One length of wood: a tapered six-sided shaft, not a cube. Godot's
	## cylinder stands along Y, so the rotation is what lays it down.
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = rad * 0.55
	cm.bottom_radius = rad
	cm.height = len_v
	cm.radial_segments = 6
	m.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 1.0
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot
	add_child(m)
	return m


func _build_stick() -> void:
	## A STICK is a stick: a crooked shaft lying on the ground with two broken
	## side branches and a pale snapped end where it came off the tree.
	var wood := Color(0.31, 0.21, 0.13).lerp(Color(0.24, 0.16, 0.10), randf())
	_add_branch(0.62, 0.026, wood, Vector3(0, 0.028, 0), Vector3(90, 0, 0))
	## A kink partway along — nothing off a tree is straight.
	_add_branch(0.26, 0.021, wood, Vector3(0.05, 0.030, 0.24), Vector3(78, 34, 0))
	## Two snapped-off twigs.
	_add_branch(0.17, 0.013, wood.lightened(0.06), Vector3(-0.06, 0.030, -0.05), Vector3(84, -52, 0))
	_add_branch(0.13, 0.011, wood.lightened(0.06), Vector3(0.05, 0.031, 0.08), Vector3(80, 61, 0))
	## The break: pale heartwood at the butt.
	_add_branch(0.02, 0.026, Color(0.52, 0.39, 0.21), Vector3(0, 0.028, -0.31), Vector3(90, 0, 0))


func _build_shard(glow_col: Color) -> void:
	## A piece of the cave's light, lying in the dirt still burning. It keeps
	## the colour of the cluster it came off — blue, violet, or ember deep down.
	_add_box(Vector3(0.10, 0.26, 0.10), glow_col, Vector3(0, 0.11, 0),
		Vector3(18, 24, -12), false, glow_col)
	_add_box(Vector3(0.07, 0.15, 0.07), glow_col, Vector3(0.08, 0.07, 0.04),
		Vector3(-26, -40, 20), false, glow_col)


func _build_potion() -> void:
	## The red draught: a squat glass flask, liquid glowing faintly through it,
	## corked, lying where it was dropped. Reads across a dark room.
	var red := Color(0.85, 0.12, 0.14)
	_add_box(Vector3(0.13, 0.15, 0.13), red, Vector3(0, 0.075, 0),
		Vector3(0, randf() * 360.0, 0), false, red * 0.5)                       ## the body
	_add_box(Vector3(0.055, 0.07, 0.055), Color(0.65, 0.75, 0.78), Vector3(0, 0.185, 0))  ## the neck
	_add_box(Vector3(0.065, 0.035, 0.065), Color(0.42, 0.30, 0.18), Vector3(0, 0.235, 0)) ## the cork


func _build_rucksack() -> void:
	## The old rucksack, off a back for once: worn leather, rolled flap,
	## front pocket, one strap flopped loose on the ground.
	var leath := Color(0.30, 0.22, 0.14)
	_add_box(Vector3(0.30, 0.34, 0.14), leath, Vector3(0, 0.17, 0), Vector3(-8, randf() * 360.0, 4))
	_add_box(Vector3(0.32, 0.11, 0.15), Color(0.38, 0.33, 0.24), Vector3(0, 0.36, 0), Vector3(-14, 0, 4))
	_add_box(Vector3(0.20, 0.14, 0.05), leath.darkened(0.12), Vector3(0, 0.10, 0.09), Vector3(-8, 0, 4))
	_add_box(Vector3(0.05, 0.03, 0.26), leath.darkened(0.2), Vector3(0.16, 0.02, 0.10), Vector3(0, 30, 0))


func _build_bone(kind: String) -> void:
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