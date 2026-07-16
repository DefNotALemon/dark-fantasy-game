extends Node3D
class_name RockDebris
## A chunk of rock knocked loose by the pickaxe (or, later, by cave-ins):
## tumbles out, falls, thuds onto whatever is below, sits a moment, crumbles.
## The BIG variant is a hazard — mine the ceiling over your own head and the
## slab that comes down will hurt you (10 dmg). Purely visual otherwise: no
## collision body, just a downward ray to find where to land.

const SMALL_DMG := 0.0
const BIG_DMG := 10.0

var vel := Vector3.ZERO
var big := false
var _spin := Vector3.ZERO
var _landed := false
var _life := 0.0
var _fade := 0.0
var _hurt_done := false


static func make(at: Vector3, velocity: Vector3, is_big := false) -> RockDebris:
	var r := RockDebris.new()
	r.position = at
	r.vel = velocity
	r.big = is_big
	return r


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_spin = Vector3(rng.randf_range(-4.0, 4.0), rng.randf_range(-4.0, 4.0), rng.randf_range(-4.0, 4.0))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.24, 0.29) if not big else Color(0.20, 0.20, 0.25)
	mat.roughness = 1.0
	var n := 1 if not big else 2
	for i in range(n):
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var s := rng.randf_range(0.10, 0.22) if not big else rng.randf_range(0.34, 0.5)
		bm.size = Vector3(s, s * rng.randf_range(0.6, 1.1), s * rng.randf_range(0.7, 1.3))
		m.mesh = bm
		m.material_override = mat
		m.position = Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(-0.08, 0.08), rng.randf_range(-0.1, 0.1)) * (1.0 if not big else 2.0)
		m.rotation_degrees = Vector3(rng.randf_range(0, 360), rng.randf_range(0, 360), rng.randf_range(0, 360))
		add_child(m)


func _physics_process(delta: float) -> void:
	if _landed:
		_life += delta
		if _life > (4.0 if not big else 7.0):
			_fade += delta
			scale = Vector3.ONE * maxf(1.0 - _fade / 0.9, 0.001)
			if _fade >= 0.9:
				queue_free()
		return

	vel.y -= 9.8 * delta
	rotation += _spin * delta

	## A falling BIG slab is a hazard to whoever is under it — usually the
	## miner who cut it loose. TODO(design): should it crush enemies too?
	if big and not _hurt_done and vel.y < 0.0:
		var p := get_tree().get_first_node_in_group("player") as Node3D
		if p != null and p.global_position.distance_to(global_position) < 1.15:
			_hurt_done = true
			if p.has_method("take_damage"):
				p.call("take_damage", BIG_DMG, global_position)

	## Land on whatever rock/floor the ray finds under us this frame.
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.05,
		global_position + vel * delta + Vector3.DOWN * 0.12)
	var hit := space.intersect_ray(q)
	if not hit.is_empty() and vel.y <= 0.0:
		global_position = (hit.position as Vector3) + Vector3.UP * 0.06
		_landed = true
		if big:  ## a heavy thud — kick the camera if the player is close
			var p := get_tree().get_first_node_in_group("player")
			if p != null and (p as Node3D).global_position.distance_to(global_position) < 7.0:
				p.set("cam_shake", maxf(float(p.get("cam_shake")), 0.16))
		return
	global_position += vel * delta
	if global_position.y < -60.0:
		queue_free()
