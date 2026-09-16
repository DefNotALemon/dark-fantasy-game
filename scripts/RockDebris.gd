extends Node3D
class_name RockDebris
## A chunk of rock knocked loose by the pickaxe (or, later, by cave-ins):
## tumbles out, falls, thuds onto whatever is below, sits a moment, crumbles.
## The BIG variant is a hazard — mine the ceiling over your own head and the
## slab that comes down will hurt you (10 dmg). Purely visual otherwise: no
## collision body, just a downward ray to find where to land.

const SMALL_DMG := 0.0
const BIG_DMG := 10.0
const GATHER_FLY := 0.30         ## hold-E sweep: s from the ground to the pack

var vel := Vector3.ZERO
var big := false
var wood := false                ## a wood CHIP off a tree, not a rock
var hazard := false              ## falls with intent — hurts whoever is under it
var _spin := Vector3.ZERO
var landed := false              ## resting on the ground — E can gather rocks
var _rolling := false            ## on the ground but still moving downhill
var _life := 0.0
var _fade := 0.0
var _hurt_done := false
var _refoot := randf_range(0.3, 0.6)  ## staggered footing re-checks once landed
var gather_to: Node3D = null     ## hold-E sweep: non-null means it is leaving
var gather_t := 0.0


static func make(at: Vector3, velocity: Vector3, is_big := false, is_wood := false, is_hazard := false) -> RockDebris:
	var r := RockDebris.new()
	r.position = at
	r.vel = velocity
	r.big = is_big
	r.wood = is_wood
	r.hazard = is_hazard
	return r


func _ready() -> void:
	add_to_group("debris")  ## landed ROCKS are gatherable (look + E)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_spin = Vector3(rng.randf_range(-4.0, 4.0), rng.randf_range(-4.0, 4.0), rng.randf_range(-4.0, 4.0))
	if wood:
		_spin *= 1.8  ## chips tumble livelier than stone
	var mat := StandardMaterial3D.new()
	if wood:
		## Fresh-cut wood: pale heart, sometimes bark-dark.
		mat.albedo_color = Color(0.45, 0.33, 0.18) if rng.randf() < 0.7 else Color(0.26, 0.18, 0.11)
	else:
		mat.albedo_color = Color(0.24, 0.24, 0.29) if not big else Color(0.20, 0.20, 0.25)
	mat.roughness = 1.0
	var n := 1 if not big else 2
	for i in range(n):
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var s := rng.randf_range(0.10, 0.22) if not big else rng.randf_range(0.34, 0.5)
		if wood:
			s = rng.randf_range(0.06, 0.13)  ## splinters, not boulders
		bm.size = Vector3(s, s * rng.randf_range(0.6, 1.1), s * rng.randf_range(0.7, 1.3))
		m.mesh = bm
		m.material_override = mat
		m.position = Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(-0.08, 0.08), rng.randf_range(-0.1, 0.1)) * (1.0 if not big else 2.0)
		m.rotation_degrees = Vector3(rng.randf_range(0, 360), rng.randf_range(0, 360), rng.randf_range(0, 360))
		add_child(m)


func _physics_process(delta: float) -> void:
	if gather_to != null:
		_fly_home(delta)
		return
	if landed:
		_life += delta
		## The ground under a landed rock can be dug away (or a sleep shift
		## redraws it): re-check the footing now and then and fall again.
		_refoot -= delta
		if _refoot <= 0.0:
			_refoot = randf_range(0.3, 0.6)
			var lq := PhysicsRayQueryParameters3D.create(
				global_position + Vector3.UP * 0.25, global_position + Vector3.DOWN * 0.7)
			if get_world_3d().direct_space_state.intersect_ray(lq).is_empty():
				landed = false
				_rolling = false
				vel = Vector3.ZERO
				return
		## Rocks linger long enough to be gathered; wood chips are set dressing.
		if _life > (4.0 if wood else (18.0 if not big else 24.0)):
			_fade += delta
			scale = Vector3.ONE * maxf(1.0 - _fade / 0.9, 0.001)
			if _fade >= 0.9:
				queue_free()
		return

	rotation += _spin * delta * (clampf(vel.length() * 0.6, 0.15, 1.0) if _rolling else 1.0)

	if _rolling:
		## ROLLING: gravity's slope component drives it, friction argues.
		## Gentle ground talks it to a stop; STEEP ground keeps it going;
		## losing the ground under it (a cliff lip) drops it back into a fall.
		var dss := get_world_3d().direct_space_state
		var gq := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.35,
			global_position + Vector3.DOWN * 0.7)
		var ghit := dss.intersect_ray(gq)
		if ghit.is_empty():
			_rolling = false  ## rolled off the edge — falling again
			return
		if ghit.collider is CharacterBody3D:
			## Rolled onto someone's boots: kick off them and fall on — bodies
			## never carry debris.
			_rolling = false
			var baway := global_position - (ghit.collider as Node3D).global_position
			baway.y = 0.0
			if baway.length() < 0.05:
				baway = Vector3(randf() - 0.5, 0.0, randf() - 0.5)
			vel = baway.normalized() * maxf(vel.length() * 0.5, 1.0) + Vector3.UP * 0.6
			return
		var n := ghit.normal as Vector3
		global_position.y = (ghit.position as Vector3).y + 0.07
		vel += (Vector3.DOWN - n * Vector3.DOWN.dot(n)) * 9.8 * delta  ## downhill pull
		vel = vel.slide(n)
		var sp := maxf(0.0, vel.length() - (4.2 if wood else 2.4) * delta)  ## friction
		vel = vel.normalized() * sp if sp > 0.001 else Vector3.ZERO
		## Don't roll through walls: a shoulder-check along the motion.
		if sp > 0.05:
			var wq := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.08,
				global_position + Vector3.UP * 0.08 + vel * delta * 2.0)
			var whit := dss.intersect_ray(wq)
			if not whit.is_empty() and (whit.normal as Vector3).y < 0.45:
				vel = vel.bounce(whit.normal as Vector3) * 0.3
		global_position += vel * delta
		if sp < 0.18 and n.y > 0.75:
			landed = true  ## down for good, on ground flat enough to hold it
			if big:  ## a heavy thud — kick the camera if the player is close
				var p := get_tree().get_first_node_in_group("player")
				if p != null and (p as Node3D).global_position.distance_to(global_position) < 7.0:
					p.set("cam_shake", maxf(float(p.get("cam_shake")), 0.16))
		return

	vel.y -= 9.8 * delta

	## A falling HAZARD slab hurts whoever is under it — usually the miner
	## who cut it loose. TODO(design): should it crush enemies too?
	if hazard and not _hurt_done and vel.y < 0.0:
		var p := get_tree().get_first_node_in_group("player") as Node3D
		if p != null and p.global_position.distance_to(global_position) < 1.15:
			_hurt_done = true
			if p.has_method("take_damage"):
				p.call("take_damage", BIG_DMG, global_position)

	## Fly along the velocity and COLLIDE with the world: glance off walls,
	## and touch down into a ROLL on the first walkable ground.
	var space := get_world_3d().direct_space_state
	var motion := vel * delta
	var q := PhysicsRayQueryParameters3D.create(global_position,
		global_position + motion + Vector3.DOWN * 0.06)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		global_position += motion
	elif hit.collider is CharacterBody3D:
		## Bodies are not ground: clip off a shoulder and keep falling — no
		## rock ever rides a head around.
		var caway := global_position - (hit.collider as Node3D).global_position
		caway.y = 0.0
		if caway.length() < 0.05:
			caway = Vector3(randf() - 0.5, 0.0, randf() - 0.5)
		vel = caway.normalized() * maxf(vel.length() * 0.35, 1.2) + Vector3.UP * 0.8
		global_position += vel * delta
	else:
		var n := hit.normal as Vector3
		global_position = (hit.position as Vector3) + n * 0.05
		if n.y > 0.45 and vel.y <= 0.5:
			## Touchdown: the impact eats most of the energy, the rest ROLLS.
			_rolling = true
			vel = vel.slide(n) * 0.55
			return
		## Wall or ceiling: bounce off, lose most of the energy, keep falling.
		vel = vel.bounce(n) * 0.35
	if global_position.y < -60.0:
		queue_free()


## --------------------- The pile sweep (hold E) ----------------------------
## A pickaxe leaves five or six of these lying together, which is exactly the
## case hold-E is for. The player counts the rock into the pack and then hands
## the chunk itself over to this: out of the "debris" group so the sweep cannot
## take it twice, then up to the waist, shrinking, and gone.


func gather_fly(to: Node3D) -> void:
	remove_from_group("debris")
	gather_to = to
	gather_t = 0.0


func _fly_home(delta: float) -> void:
	if not is_instance_valid(gather_to):
		queue_free()
		return
	gather_t += delta
	var k := clampf(gather_t / GATHER_FLY, 0.0, 1.0)
	var dst: Vector3 = gather_to.global_position + Vector3.UP * 1.0
	global_position = global_position.lerp(dst, clampf(delta * 13.0, 0.0, 1.0))
	global_position.y += (1.0 - k) * 2.4 * delta
	rotation += _spin * delta * 0.6
	scale = Vector3.ONE * maxf(0.05, 1.0 - k * k)
	if k >= 1.0:
		queue_free()
