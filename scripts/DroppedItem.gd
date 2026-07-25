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

var item := {}               ## {name, weight, count, slot [, material]}
var velocity := Vector3.ZERO
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _resting := false
var _life := LIFE
var _refoot := randf_range(0.3, 0.6)  ## staggered footing re-checks while resting


static func make(d: Dictionary) -> DroppedItem:
	var n := DroppedItem.new()
	n.item = d
	n._build_mesh()
	return n


func _ready() -> void:
	add_to_group("dropped_items")


func display_name() -> String:
	return String(item.get("name", "item"))


func _physics_process(delta: float) -> void:
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
		rotation = Vector3(0.0, randf() * TAU, 0.0)  ## settle flat, any old way


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
			else:
				## Plain loot (tusks, bones, pickaxes...): a humble bundle.
				_add_box(Vector3(0.16, 0.14, 0.16), col, Vector3(0, 0.05, 0))
				_add_box(Vector3(0.19, 0.05, 0.05), Color(0.30, 0.24, 0.16), Vector3(0, 0.12, 0), Vector3(0, 25, 0))


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


func _build_billet() -> void:
	## A split of firewood: a stubby round with sawn faces, lying on its side.
	var wood := Color(0.28, 0.19, 0.12).lerp(Color(0.34, 0.23, 0.14), randf())
	_add_branch(0.40, 0.085, wood, Vector3(0, 0.085, 0), Vector3(90, 0, 0))
	_add_branch(0.02, 0.085, Color(0.52, 0.39, 0.21), Vector3(0, 0.085, -0.20), Vector3(90, 0, 0))
	_add_branch(0.02, 0.085, Color(0.52, 0.39, 0.21), Vector3(0, 0.085, 0.20), Vector3(90, 0, 0))
	_add_branch(0.30, 0.055, wood, Vector3(0.11, 0.055, 0.03), Vector3(90, 12, 0))
