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
		return
	velocity.y -= gravity * delta
	velocity.x = move_toward(velocity.x, 0.0, delta * 0.8)
	velocity.z = move_toward(velocity.z, 0.0, delta * 0.8)
	global_position += velocity * delta
	rotate_y(TOSS_SPIN * delta)
	if velocity.y >= 0.0:
		return
	## Falling: look for the ground under us and settle onto it.
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.3, global_position + Vector3.DOWN * 1.5)
	var hit: Dictionary = space.intersect_ray(q)
	if hit and not (hit.collider is CharacterBody3D) and global_position.y <= float(hit.position.y) + REST_HEIGHT:
		_resting = true
		global_position.y = float(hit.position.y) + REST_HEIGHT
		rotation = Vector3(0.0, randf() * TAU, 0.0)  ## settle flat, any old way


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
			## Plain loot (tusks, bones, pickaxes...): a humble bundle.
			_add_box(Vector3(0.16, 0.14, 0.16), col, Vector3(0, 0.05, 0))
			_add_box(Vector3(0.19, 0.05, 0.05), Color(0.30, 0.24, 0.16), Vector3(0, 0.12, 0), Vector3(0, 25, 0))
