class_name CarryLog
extends Node3D
## A LOG — one section of a felled trunk, lying where it rolled.
##
## The tree doesn't hand you lumber; it hands you weight. A crashed trunk
## breaks into as many of these as the tree was metres tall, they tumble off
## the fall line, settle on the dirt, and stay there. Look at one and press E
## to swing it onto your shoulder (four is all a back will take) — but a
## shoulder is not a pocket: jump, climb, crouch, go prone, take a hit, or
## reach into your pack and the whole load rolls off behind you.
##
## Like every resting thing in this world, a log re-checks its footing: dig
## the ground out from under it and it falls again (Pickup/DroppedItem rule).

const REST_SINK := 0.88          ## a log settles a little into the dirt

var length := 1.0
var radius := 0.22
var bark := Color(0.24, 0.16, 0.10)

var velocity := Vector3.ZERO
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _resting := false
var _tumble := Vector3.ZERO
var _refoot := randf_range(0.3, 0.6)


static func make(p_len: float, p_r: float, p_bark: Color) -> CarryLog:
	var n := CarryLog.new()
	n.length = maxf(p_len, 0.35)
	n.radius = maxf(p_r, 0.08)
	n.bark = p_bark
	return n


static func from_dict(d: Dictionary) -> CarryLog:
	var n := CarryLog.make(float(d.get("length", 1.0)), float(d.get("radius", 0.22)),
		Color(d.get("bark", Color(0.24, 0.16, 0.10))))
	return n


func save_dict() -> Dictionary:
	return {"length": length, "radius": radius, "bark": bark,
		"pos": global_position, "rot": rotation}


func carry_dict() -> Dictionary:
	## What the shoulder remembers about a log it is carrying.
	return {"length": length, "radius": radius, "bark": bark}


func _ready() -> void:
	add_to_group("carry_logs")
	var m := MeshInstance3D.new()
	m.mesh = build_mesh(length, radius, bark)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	m.material_override = mat
	add_child(m)
	_tumble = Vector3(randf_range(-2.2, 2.2), randf_range(-1.4, 1.4), randf_range(-2.2, 2.2))


static func build_mesh(p_len: float, p_r: float, p_bark: Color) -> ArrayMesh:
	## An eight-sided billet running along local Z, capped at both ends with
	## the pale heartwood the saw exposed — the same cut colour the axe leaves
	## in the notch, so a log reads as a piece of the tree you just dropped.
	const SIDES := 8
	var heart := Color(0.50, 0.37, 0.20)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var hz := p_len * 0.5
	var ring: Array[Vector3] = []
	for s in range(SIDES):
		var a := TAU * float(s) / float(SIDES)
		## A billet is never a perfect cylinder — jitter the profile a little.
		var rr := p_r * (0.92 + 0.16 * fmod(float(s) * 0.37, 1.0))
		ring.append(Vector3(cos(a) * rr, sin(a) * rr, 0.0))
	for s in range(SIDES):
		var p0: Vector3 = ring[s]
		var p1: Vector3 = ring[(s + 1) % SIDES]
		var a0 := p0 + Vector3(0, 0, -hz)
		var a1 := p1 + Vector3(0, 0, -hz)
		var b0 := p0 * 0.97 + Vector3(0, 0, hz)
		var b1 := p1 * 0.97 + Vector3(0, 0, hz)
		for v: Vector3 in [a0, b0, b1, a0, b1, a1]:
			st.set_color(p_bark)
			st.add_vertex(v)
		## End caps: fresh sawn faces.
		for v: Vector3 in [Vector3(0, 0, -hz), a1, a0]:
			st.set_color(heart)
			st.add_vertex(v)
		for v: Vector3 in [Vector3(0, 0, hz), b0, b1]:
			st.set_color(heart)
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


func display_name() -> String:
	return "log"


func _physics_process(delta: float) -> void:
	if _resting:
		_refoot -= delta
		if _refoot <= 0.0:
			_refoot = randf_range(0.4, 0.8)
			var rspace := get_world_3d().direct_space_state
			var rq := PhysicsRayQueryParameters3D.create(
				global_position + Vector3.UP * 0.25, global_position + Vector3.DOWN * 0.8)
			if rspace.intersect_ray(rq).is_empty():
				_resting = false
				velocity = Vector3.ZERO
		return
	velocity.y -= gravity * delta
	velocity.x = move_toward(velocity.x, 0.0, delta * 1.6)
	velocity.z = move_toward(velocity.z, 0.0, delta * 1.6)
	global_position += velocity * delta
	rotate(Vector3.RIGHT, _tumble.x * delta)
	rotate(Vector3.UP, _tumble.y * delta)
	rotate(Vector3.FORWARD, _tumble.z * delta)
	if velocity.y >= 0.0:
		return
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.35, global_position + Vector3.DOWN * 1.2)
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return
	if hit.collider is CharacterBody3D:
		## Bodies are not ground — it rolls off a shoulder and keeps falling.
		var away := global_position - (hit.collider as Node3D).global_position
		away.y = 0.0
		if away.length() < 0.05:
			away = Vector3(randf() - 0.5, 0.0, randf() - 0.5)
		velocity = away.normalized() * randf_range(1.2, 2.0) + Vector3.UP * 1.2
		return
	var gy := float((hit.position as Vector3).y)
	if global_position.y <= gy + radius * REST_SINK:
		_settle(gy)


func _settle(ground_y: float) -> void:
	## A log comes to rest FLAT: it rolls onto its side and stops. Keep the
	## bearing it was travelling on, level the rest, sink it into the dirt.
	_resting = true
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var yaw := rotation.y if flat.length() < 0.25 else atan2(flat.x, flat.z)
	rotation = Vector3(randf_range(-0.05, 0.05), yaw, randf_range(-0.06, 0.06))
	global_position.y = ground_y + radius * REST_SINK
	velocity = Vector3.ZERO
	## The last little roll after it lands.
	var roll := Vector3(cos(yaw), 0.0, -sin(yaw)) * randf_range(-0.22, 0.22)
	var tw := create_tween()
	tw.tween_property(self, "global_position", global_position + roll, 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func toss(v: Vector3) -> void:
	_resting = false
	velocity = v
	_tumble = Vector3(randf_range(-2.6, 2.6), randf_range(-1.6, 1.6), randf_range(-2.6, 2.6))
