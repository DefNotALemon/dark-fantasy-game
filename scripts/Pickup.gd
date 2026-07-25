extends MeshInstance3D
class_name PickupOrb
## A glowing XP orb or gold coin. Bursts out of the dying creature, falls to the
## ground, and rests there. Walk over it and it flies up to you to be collected.
##
## Coins are simulated like real money: they tumble through the air, BOUNCE off
## the ground a few times, and — if they come down on their rim with some pace —
## roll away on edge before spiralling down to rest with that unmistakable
## rattle. XP essence is magic, so it just floats.

const PICKUP_RADIUS := 1.6   ## walk this close to a resting orb to grab it
const FLY_SPEED := 7.5
const REST_HEIGHT := 0.14    ## hover just above the ground while resting

## --- Coin physics ---
const COIN_RADIUS := 0.07        ## must match the CylinderMesh radius
const COIN_HALF_THICK := 0.011
const COIN_RESTITUTION := 0.42   ## how much of the drop survives each impact
const COIN_FRICTION := 0.72      ## horizontal speed kept per bounce
const COIN_MAX_BOUNCES := 5
const COIN_STOP_SPEED := 0.55    ## downward speed below which it stops bouncing
const RIM_ROLL_CHANCE := 0.34    ## chance it catches its rim and runs
const RIM_MIN_SPEED := 0.9       ## needs some pace to roll rather than flop
const ROLL_DRAG := 1.5           ## roll deceleration (units/sec^2)
const ROLL_STOP := 0.55          ## roll speed at which it starts to spiral down
const SETTLE_TIME := 0.9         ## length of the spiralling-down rattle

var burst_dir := Vector3.ZERO   ## initial outward velocity (units/sec)
var kind := "xp"                ## "xp", "coin", "arrow", "sword" or "ore"
var value := 1
var payload := ""               ## extra data — sword/ore drops carry their material id
var life := 90.0                ## safety: free if never collected


## A mined ore chunk: raw rock with bright faces of its metal showing through.
## Falls like essence, rests, magnets to the player. Payload = material id.
static func make_ore(mat_id: String) -> PickupOrb:
	var p := PickupOrb.new()
	p.kind = "ore"
	p.payload = mat_id
	p.value = 1
	var mat: Dictionary = Materials.get_mat(mat_id)
	var col: Color = mat["color"]
	var elem: Dictionary = mat["element"]
	var glow: Color = col if elem.is_empty() else Color(elem["color"])
	var rock := BoxMesh.new()
	rock.size = Vector3(0.30, 0.24, 0.28)
	p.mesh = rock
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.18, 0.17, 0.19)
	rm.roughness = 1.0
	p.material_override = rm
	## The metal showing through: two bright studs on the chunk's faces.
	for off: Vector3 in [Vector3(0.10, 0.09, 0.05), Vector3(-0.08, -0.02, -0.09)]:
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.14, 0.12, 0.13)
		m.mesh = bm
		var mm := StandardMaterial3D.new()
		mm.albedo_color = col
		mm.metallic = 0.8
		mm.roughness = 0.3
		mm.emission_enabled = true
		mm.emission = glow
		mm.emission_energy_multiplier = 1.4
		m.material_override = mm
		m.position = off
		m.rotation_degrees = Vector3(randf() * 40.0, randf() * 360.0, randf() * 40.0)
		p.add_child(m)
	p.rotation_degrees = Vector3(randf() * 20.0, randf() * 360.0, randf() * 20.0)
	return p

## A dropped material sword: the blade IS the root mesh (colored by material,
## elemental metals glow), with hilt pieces as children. Floats/spins like
## essence once it lands — unmistakably loot.
static func make_sword(mat_id: String) -> PickupOrb:
	var p := PickupOrb.new()
	p.kind = "sword"
	p.payload = mat_id
	p.value = 1
	var mat: Dictionary = Materials.get_mat(mat_id)
	var col: Color = mat["color"]
	var elem: Dictionary = mat["element"]
	var blade := BoxMesh.new()
	blade.size = Vector3(0.05, 0.09, 0.85)
	p.mesh = blade
	var bm := StandardMaterial3D.new()
	bm.albedo_color = col
	bm.metallic = 0.7
	bm.roughness = 0.35
	if not elem.is_empty():
		bm.emission_enabled = true
		bm.emission = elem["color"]
		bm.emission_energy_multiplier = 1.4
	p.material_override = bm
	## Hilt: crossguard + grip + pommel hanging off the blade's +Z end.
	var fittings := [
		[Vector3(0.24, 0.05, 0.05), Color(0.50, 0.42, 0.22), Vector3(0, 0, 0.46)],
		[Vector3(0.04, 0.04, 0.15), Color(0.12, 0.10, 0.09), Vector3(0, 0, 0.56)],
		[Vector3(0.06, 0.06, 0.05), Color(0.50, 0.42, 0.22), Vector3(0, 0, 0.66)],
	]
	for f: Array in fittings:
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = f[0]
		m.mesh = box
		var mm := StandardMaterial3D.new()
		mm.albedo_color = f[1]
		m.material_override = mm
		m.position = f[2]
		p.add_child(m)
	p.rotation_degrees = Vector3(14.0, randf() * 360.0, 0.0)
	return p


var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _vel := Vector3.ZERO
var _started := false
var _resting := false
var _magnet := false
var _accel := 0.0
var _bob := 0.0
var _refoot := randf_range(0.3, 0.6)  ## staggered footing re-checks at rest

## Coin state machine: "fall" -> (optionally "roll") -> "settle" -> "rest".
var _phase := "fall"
var _ground_y := 0.0
var _bounces := 0
var _tumble_axis := Vector3.UP
var _tumble_rate := 0.0
var _roll_dir := Vector3.FORWARD
var _roll_speed := 0.0
var _spin := 0.0        ## rotation about the coin's own axis
var _lay := 0.0         ## 0 = standing on its rim, PI/2 = lying flat
var _lay_start := 0.0
var _precess := 0.0     ## which way the rim's contact point faces
var _settle_t := 0.0


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return

	if not _started:
		_started = true
		_vel = burst_dir + Vector3.UP * 2.2  ## outward burst with a little pop upward
		if kind == "coin":
			## Off-axis tumble, so it flips end over end on the way down.
			_tumble_axis = Vector3(randf() - 0.5, randf() * 0.3, randf() - 0.5).normalized()
			_tumble_rate = randf_range(9.0, 16.0)

	if _magnet:
		_do_magnet(delta)
		return

	if kind == "coin":
		_coin_process(delta)
		return

	## --- XP essence: spin, arc, land, then hover and bob. ---
	rotate_y(delta * 4.0)
	if _resting:
		_bob += delta
		global_position.y += sin(_bob * 3.0) * 0.05 * delta
		_check_magnet()
		_recheck_footing(delta)
		return
	_ballistic(delta)
	var hit := _ground_check()
	if hit.is_empty():
		return
	if hit.collider is CharacterBody3D:
		_glance_off(hit.collider as Node3D)
		return
	_resting = true
	global_position.y = hit.position.y + REST_HEIGHT


## --------------------------------------------------------------------------
## Coins
## --------------------------------------------------------------------------

func _coin_process(delta: float) -> void:
	match _phase:
		"fall":
			## Tumbling through the air, then clattering off the dirt.
			basis = Basis(_tumble_axis, _tumble_rate * delta) * basis
			_ballistic(delta)
			var hit := _ground_check()
			if hit.is_empty():
				return
			if hit.collider is CharacterBody3D:
				_glance_off(hit.collider as Node3D)
				return
			_ground_y = hit.position.y
			_bounce()
		"roll":
			_check_magnet()
			_roll(delta)
		"settle":
			_check_magnet()
			_settle(delta)
		_:
			_check_magnet()
			_recheck_footing(delta)


func _bounce() -> void:
	## Hit the ground. Real coins don't stop dead — they clatter. Each impact
	## keeps a fraction of the drop, sheds sideways speed, and calms the tumble.
	var drop := -_vel.y
	_bounces += 1
	if drop > COIN_STOP_SPEED and _bounces < COIN_MAX_BOUNCES:
		global_position.y = _ground_y + COIN_HALF_THICK + 0.005
		_vel.y = drop * COIN_RESTITUTION
		_vel.x *= COIN_FRICTION
		_vel.z *= COIN_FRICTION
		## A little skitter, so it never bounces perfectly in place.
		_vel.x += randf_range(-0.25, 0.25)
		_vel.z += randf_range(-0.25, 0.25)
		_tumble_rate *= 0.7
		return

	## Final contact: does it land flat, or catch its rim and run?
	var flat := Vector3(_vel.x, 0.0, _vel.z)
	var speed := flat.length()
	if speed > RIM_MIN_SPEED and randf() < RIM_ROLL_CHANCE:
		_roll_dir = flat / speed
		_roll_speed = speed
		_spin = randf() * TAU
		_lay = 0.0
		_precess = atan2(_roll_dir.x, _roll_dir.z)
		_phase = "roll"
		global_position.y = _ground_y + COIN_RADIUS
		return

	## Flopping down: settle from a shallow tilt, so it rattles once before rest.
	_begin_settle(deg_to_rad(randf_range(38.0, 62.0)))
	_roll_speed = 0.0


func _roll(delta: float) -> void:
	## Running along on its edge, bleeding speed to friction.
	_roll_speed = maxf(_roll_speed - ROLL_DRAG * delta, 0.0)
	## A rolling coin never tracks straight — it curves off toward its lean.
	_precess += delta * 0.4 * signf(sin(_spin * 0.11))
	_roll_dir = Vector3(sin(_precess), 0.0, cos(_precess))
	global_position += _roll_dir * _roll_speed * delta
	_spin += (_roll_speed * delta) / COIN_RADIUS

	## Follow the ground under it; if it rolls off a ledge, fall again.
	var q := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.3, global_position + Vector3.DOWN * 1.2)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_phase = "fall"
		_vel = _roll_dir * _roll_speed
		_bounces = COIN_MAX_BOUNCES - 1
		return
	_ground_y = hit.position.y
	global_position.y = _ground_y + COIN_RADIUS
	_apply_coin_basis()

	if _roll_speed <= ROLL_STOP:
		_begin_settle(0.0)


func _begin_settle(from_lay: float) -> void:
	_phase = "settle"
	_settle_t = 0.0
	_lay = from_lay
	_lay_start = from_lay
	if from_lay > 0.0:
		_precess = randf() * TAU


func _settle(delta: float) -> void:
	## The Euler-disk spiral: the coin lies over while its contact point races
	## around the rim faster and faster, then it slaps flat and goes quiet.
	_settle_t += delta
	var u := clampf(_settle_t / SETTLE_TIME, 0.0, 1.0)
	_lay = lerpf(_lay_start, PI * 0.5, 1.0 - pow(1.0 - u, 2.2))
	_precess += delta * (7.0 + 34.0 * u * u)   ## the rattle, accelerating
	_spin += delta * maxf(_roll_speed, 1.0) * (1.0 - u) * 4.0
	global_position.y = _ground_y + COIN_RADIUS * cos(_lay) + COIN_HALF_THICK * sin(_lay)
	_apply_coin_basis()

	if u >= 1.0:
		_phase = "rest"
		_resting = true
		_lay = PI * 0.5
		global_position.y = _ground_y + COIN_HALF_THICK + 0.004
		rotation = Vector3(0.0, randf() * TAU, 0.0)


func _apply_coin_basis() -> void:
	## The coin's own axis (the CylinderMesh's +Y) tilts up from horizontal as it
	## lies over: horizontal = standing on the rim, vertical = flat on the dirt.
	var rim := Vector3(cos(_precess), 0.0, -sin(_precess))
	var axis := (rim * cos(_lay) + Vector3.UP * sin(_lay)).normalized()
	var ref := Vector3.FORWARD if absf(axis.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var x := ref.cross(axis).normalized()
	var z := x.cross(axis)
	basis = Basis(x, axis, z) * Basis(Vector3.UP, _spin)


## --------------------------------------------------------------------------
## Shared
## --------------------------------------------------------------------------

func _ballistic(delta: float) -> void:
	_vel.y -= gravity * delta
	var drag := 1.5 if kind != "coin" else 0.6  ## coins keep their sideways pace
	_vel.x = move_toward(_vel.x, 0.0, delta * drag)
	_vel.z = move_toward(_vel.z, 0.0, delta * drag)
	global_position += _vel * delta


func _ground_check() -> Dictionary:
	if _vel.y >= 0.0:
		return {}
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.3, global_position + Vector3.DOWN * 2.0)
	var hit: Dictionary = space.intersect_ray(q)
	var floor_h: float = REST_HEIGHT if kind != "coin" else COIN_HALF_THICK + 0.02
	if hit and global_position.y <= hit.position.y + floor_h:
		return hit
	return {}


func _glance_off(who: Node3D) -> void:
	## Landed on a creature — glance off sideways and keep falling.
	var away := global_position - who.global_position
	away.y = 0.0
	if away.length() < 0.05:
		away = Vector3(randf() - 0.5, 0.0, randf() - 0.5)
	away = away.normalized()
	_vel = away * randf_range(1.2, 2.2) + Vector3.UP * randf_range(1.5, 2.5)


func _recheck_footing(delta: float) -> void:
	## The floor a pickup rests on can be DUG away (or redrawn by a sleep
	## shift). Re-check now and then; nothing solid below = fall again, all
	## the way down to the true ground.
	_refoot -= delta
	if _refoot > 0.0:
		return
	_refoot = randf_range(0.3, 0.6)
	var q := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.25, global_position + Vector3.DOWN * 0.7)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_resting = false
		_phase = "fall"     ## coins tumble again; essence just drops
		_bounces = 0
		_vel = Vector3.ZERO


func _check_magnet() -> void:
	var pl := get_tree().get_first_node_in_group("player")
	if pl and (pl as Node3D).global_position.distance_to(global_position) <= PICKUP_RADIUS:
		_magnet = true


func _do_magnet(delta: float) -> void:
	## The player walked over it — fly up to their waist and get collected.
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if kind == "xp" or kind == "sword" or kind == "ore":
		rotate_y(delta * 4.0)
	var target: Vector3 = (player as Node3D).global_position
	if player.has_method("get_waist_point"):
		target = player.get_waist_point()
	var to := target - global_position
	if to.length() < 0.3:
		if player.has_method("collect_pickup"):
			player.collect_pickup(kind, value, payload)
		queue_free()
		return
	_accel += delta * 16.0
	global_position += to.normalized() * (FLY_SPEED + _accel) * delta
