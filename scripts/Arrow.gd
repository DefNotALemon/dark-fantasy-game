extends Node3D
class_name Arrow
## An arrow in flight. Flies flat with a shallow drop, sticks into whatever it
## hits: enemies take the damage (arrow buried in the wound), terrain keeps the
## arrow as a retrievable pickup — walk near and it flies back to your quiver.

var velocity := Vector3.ZERO
var damage := 30.0
var life := 12.0
var stuck := false
var _magnet := false
var _accel := 0.0


func _ready() -> void:
	## Shaft, steel head, pale fletching — pointing down -Z like the sword blade.
	_box(Vector3(0.015, 0.015, 0.55), Color(0.45, 0.33, 0.18), Vector3(0, 0, 0))
	var head := _box(Vector3(0.03, 0.03, 0.06), Color(0.75, 0.78, 0.82), Vector3(0, 0, -0.29))
	var hmat := head.material_override as StandardMaterial3D
	hmat.metallic = 0.7
	hmat.roughness = 0.35
	_box(Vector3(0.05, 0.012, 0.09), Color(0.90, 0.88, 0.80), Vector3(0, 0, 0.25))
	_box(Vector3(0.012, 0.05, 0.09), Color(0.90, 0.88, 0.80), Vector3(0, 0, 0.25))


func _box(size: Vector3, color: Color, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	m.material_override = mat
	m.position = pos
	add_child(m)
	return m


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return

	## Stuck: rest where we landed and wait to be picked back up.
	if stuck:
		var pl := get_tree().get_first_node_in_group("player")
		if pl == null or not (pl is Node3D):
			return
		var p3 := pl as Node3D
		if not _magnet and p3.global_position.distance_to(global_position) <= 1.8:
			_magnet = true
		if _magnet:
			var target: Vector3 = p3.global_position
			if pl.has_method("get_waist_point"):
				target = pl.get_waist_point()
			var to := target - global_position
			if to.length() < 0.35:
				if pl.has_method("collect_pickup"):
					pl.collect_pickup("arrow", 1)
				queue_free()
				return
			_accel += delta * 18.0
			global_position += to.normalized() * (8.0 + _accel) * delta
		return

	## Flight: shallow gravity so aim feels honest but not fussy.
	velocity.y -= 3.2 * delta
	var from := global_position
	var to_pos := from + velocity * delta
	var dir := velocity.normalized()
	if absf(dir.y) < 0.98:  ## keep the shaft aligned with its path
		look_at(from + dir, Vector3.UP)

	## Did this frame's path pass through anything?
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to_pos)
	var pl := get_tree().get_first_node_in_group("player")
	if pl and pl is CharacterBody3D:
		q.exclude = [(pl as CharacterBody3D).get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		global_position = to_pos
		return
	if hit.collider is Enemy:
		(hit.collider as Enemy).take_damage(damage)
		queue_free()  ## buried in the wound
		return
	## Terrain: stick with the head buried a touch, then wait for retrieval.
	global_position = hit.position - dir * 0.14
	stuck = true
	life = 120.0
