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
	var struck := CreatureSkin.owner_of(hit.collider)   ## a ragdoll bone counts as its creature
	if struck is Enemy:
		var e := struck as Enemy
		e.take_damage(damage)
		## An arrow leaves a mark like anything else that lands: blood off bare
		## flesh, sparks where the head skates off plate, dust off the undead.
		_leave_fx(HitFX.for_creature(HitFX.kind_of(e), hit.position as Vector3,
			(-dir + Vector3.UP * 0.4).normalized(), 0.75))
		queue_free()  ## buried in the wound
		return
	## Terrain: stick with the head buried a touch, then wait for retrieval.
	## Thunking into timber puts a small burst of chips in the air first.
	var body := hit.collider as Node
	var timber := _timber_owner(body)
	if timber != null:
		var sp := ""
		if "species" in timber:
			sp = String(timber.get("species"))
		_leave_fx(HitFX.wood(hit.position as Vector3,
			((hit.normal as Vector3) + Vector3.UP * 0.4).normalized(), sp, 0.45))
		## the thock, and the shaft quivering -- pitched to the trunk
		WoodAudio.strike(self, hit.position as Vector3, "arrow", 0.7, timber)
	global_position = hit.position - dir * 0.14
	stuck = true
	life = 120.0


func _timber_owner(body: Node) -> Node:
	## The tree/trunk/stump behind a collider, if that's what we hit. Colliders
	## are usually a child body of the thing itself, so check one level up too.
	var n := body
	for _i in range(2):
		if n == null:
			return null
		if n.is_in_group("choppable") or n.is_in_group("trees") or n.is_in_group("tree_stumps"):
			return n
		n = n.get_parent()
	return null


func _leave_fx(node: Node3D) -> void:
	## Effects belong to the WORLD — the arrow that made them is about to die.
	if node == null:
		return
	var parent := get_parent()
	if parent != null:
		parent.add_child(node)
