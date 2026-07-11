extends CharacterBody3D
class_name Enemy
## Base creature AI shared by every mob (Boar, Skeleton, Goblin, Kobold).
## Wanders while CALM; chases and melees while AGITATED; and has one telegraphed
## "strong attack" (windup glow -> lunge / smash) that the player can dodge or
## block — but if it lands on a raised guard, it BREAKS the block.
## Withers to dust on death. Built in code so mobs spawn with e.g. Boar.new().
##
## Subclasses override _build_body() and set stats in _init().

@export var display_name := "Creature"
@export var max_health := 70.0
@export var wander_speed := 1.4
@export var chase_speed := 4.2
@export var attack_range := 2.0
@export var attack_damage := 12.0
@export var attack_cooldown := 1.2
@export var aggro_radius := 7.0    ## get this close and it wakes up
@export var leash_radius := 18.0   ## get this far and it calms back down
@export var armored := false       ## armored creatures don't flinch (none yet)
@export var xp_tier := 0           ## loot/strength tier: drop tables, orb COUNT
@export var orb_tier := 0          ## essence tier: orb color + XP value (0 green ..
								   ## 3 purple). Every current mob stays 0 — richer
								   ## essence waits for genuinely elite creatures
@export var families: Array = []   ## creature-family tags for weapon-material
								   ## matchups (see Materials.gd): "beast",
								   ## "humanoid", "undead", "cursed", "armored"...

## Strong attack (telegraphed). Guard-breaks the player if it hits their block.
@export var strong_damage := 22.0
@export var strong_speed := 12.0        ## movement during it (0 = attacks in place)
@export var strong_windup_time := 0.5   ## telegraph: whole-body glow, then go
@export var strong_duration := 0.55
@export var strong_cooldown := 2.6
@export var strong_min_range := 3.0     ## won't start it closer than this
@export var strong_max_range := 7.0     ## won't start it farther than this
@export var strong_hit_range := 2.0     ## must be this close to land the hit
@export var strong_from_melee := false   ## may also use it while at melee range
@export var strong_breaks_guard := true  ## smashes through a raised block
@export var strong_multi_hits := 1       ## flurries hit more than once
@export var strong_hit_interval := 0.22  ## delay between flurry hits
@export var strong_throws := false       ## lunge flings the player aside, mob runs past
@export var strong_throw_mode := "side"  ## "side" = shove aside + run past; "away" = hurl back (a throw)
@export var strong_throw_power := 7.0    ## how hard the toss is (boar shove < ogre hurl)
@export var strong_runpast := 0.30       ## side-throw: how long it keeps barreling past after the hit
@export var always_moving := false       ## chargers never plant their feet: they keep running
										 ## through windups and never stop for a standing bite
@export var duelist := false             ## smart mobs: hold near the player, then dart in
@export var duel_range := 6.0            ## band where a duelist paces instead of rushing
@export var duel_hold_min := 0.7         ## how long it paces between strikes (low = relentless)
@export var duel_hold_max := 1.5
@export var duel_lean := 0.45            ## how far it rotates toward its movement while circling
@export var telegraph_color := Color(0.95, 0.10, 0.05)

enum State { CALM, AGITATED }

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var health := 70.0
var state: int = State.CALM
var dying := false
var confused := false   ## menu-spawned mobs: wander in lost circles, never
						## aggro on proximity — snaps out of it when hit

## Wander
var wander_dir := Vector3.ZERO
var wander_timer := 0.0

## Combat
var attack_cd := 0.0
var strong_cd := 0.0
var strong_windup := 0.0
var strong_time := 0.0
var strong_active := false
var strong_dir := Vector3.ZERO
var strong_mode := "primary"   ## which special was chosen (subclasses set this)
var strong_hits_done := 0
var strong_rehit := 0.0
var was_in_melee := false
var _throw_side := 1.0    ## which way a lunge flings the player (left/right)
var _duel_hold := 0.0     ## duelist: pacing timer before darting in
var _duel_side := 1.0     ## duelist: strafe direction while pacing
var _shuffle_side := 1.0  ## which way it sidesteps around the player up close

## --- Locomotion: shared walk animation + natural, imperfect movement ---
var walk_t := 0.0             ## gait phase, driven by real ground speed
var _loco_amount := 0.0       ## eased 0..1 — how much we're actually moving
var _sway_t := randf() * TAU  ## per-mob drift clock (desyncs the whole pack)
var loco_bob_y := 0.0         ## current footfall bob height (rigs compose it)
var loco_root: Node3D = null  ## subclasses point this at their rig for the bob
## Gait character — every mob WALKS, each in its own way (tuned per mob):
var walk_legs: Array[Node3D] = []  ## hip pivots; even = left, odd = right phase
var walk_arms: Array[Node3D] = []  ## loose arms that counter-swing the stride
var stride_deg := 26.0             ## leg swing amplitude at full speed
var waddle_deg := 0.0              ## side-to-side body roll (the ogre's whole deal)
var gait_rate := 1.0               ## cadence: ogres plod (<1), kobolds skitter (>1)
var bob_h := 0.055                 ## footfall bob height

## Melee swing: a short animation plays and the damage lands partway through,
## so the player gets a beat to react.
const MELEE_ANIM_TIME := 0.35
const MELEE_HIT_AT := 0.22   ## damage lands at the WHIP impact of the cut (p=0.62)
var melee_anim := 0.0
var melee_hit_pending := false

var body_mat: StandardMaterial3D
var base_body_color := Color(0.5, 0.5, 0.5)  ## restored after the hit flash
var eye_mats: Array[StandardMaterial3D] = []
var hit_flash := 0.0
var flinch_timer := 0.0
var retreat_timer := 0.0   ## after being caught mid-strong-attack: back off a moment
var parry_open := 0.0      ## parried: staggered AND vulnerable (flinch immunity waived)


func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	_build_body()
	_pick_wander()


func _box_in(parent: Node, size: Vector3, color: Color, pos: Vector3, rot := Vector3.ZERO, metal := false) -> MeshInstance3D:
	## Box mesh under an arbitrary parent (e.g. an animatable arm pivot).
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.35 if metal else 1.0
	if metal:
		mat.metallic = 0.7
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot
	parent.add_child(m)
	return m


func _box(size: Vector3, color: Color, pos: Vector3, rot := Vector3.ZERO, metal := false) -> MeshInstance3D:
	return _box_in(self, size, color, pos, rot, metal)


func _add_eye(pos: Vector3, size := Vector3(0.06, 0.06, 0.05), parent: Node = null) -> void:
	## Eyes tint red (or the telegraph color) when agitated.
	var eye := MeshInstance3D.new()
	var em := BoxMesh.new()
	em.size = size
	eye.mesh = em
	eye.position = pos
	var emat := StandardMaterial3D.new()
	emat.albedo_color = Color(0.05, 0.03, 0.03)
	eye.material_override = emat
	(parent if parent != null else self).add_child(eye)
	eye_mats.append(emat)


func _add_collision(size: Vector3, pos: Vector3) -> void:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	col.position = pos
	add_child(col)


func _build_body() -> void:
	## Fallback body (subclasses override this entirely).
	_add_collision(Vector3(0.8, 1.2, 0.8), Vector3(0, 0.6, 0))
	base_body_color = Color(0.5, 0.5, 0.5)
	var body := _box(Vector3(0.7, 1.1, 0.7), base_body_color, Vector3(0, 0.6, 0))
	body_mat = body.material_override as StandardMaterial3D
	_add_eye(Vector3(-0.15, 0.9, -0.36))
	_add_eye(Vector3(0.15, 0.9, -0.36))


func _pick_wander() -> void:
	## Confused mobs change their mind constantly; calm ones amble and graze.
	wander_timer = randf_range(1.0, 2.5) if confused else randf_range(2.0, 5.0)
	if randf() < 0.4:
		wander_dir = Vector3.ZERO  ## pause and idle
	else:
		var a := randf() * TAU
		wander_dir = Vector3(cos(a), 0, sin(a))


func _physics_process(delta: float) -> void:
	if dying:
		move_and_slide()
		return

	## Sleep far-off idle mobs (caves spawn dozens) to save CPU — they wake as
	## soon as the player gets within range.
	if state == State.CALM and flinch_timer <= 0.0 and retreat_timer <= 0.0 and melee_anim <= 0.0:
		var pw := _get_player()
		if pw and global_position.distance_to(pw.global_position) > 45.0:
			if not is_on_floor():
				velocity.y -= gravity * delta
			move_and_slide()
			return

	if not is_on_floor():
		velocity.y -= gravity * delta

	if hit_flash > 0.0:
		hit_flash -= delta
		if body_mat:
			body_mat.albedo_color = Color(0.9, 0.6, 0.55) if hit_flash > 0.0 else base_body_color
	if parry_open > 0.0:
		parry_open -= delta

	## Resolve an in-flight melee swing (damage lands partway through the swing).
	if melee_anim > 0.0:
		melee_anim -= delta
		if melee_hit_pending and MELEE_ANIM_TIME - melee_anim >= MELEE_HIT_AT:
			melee_hit_pending = false
			var mp := _get_player()
			if mp:
				var mto := mp.global_position - global_position
				mto.y = 0.0
				if mto.length() <= attack_range + 0.4 and mp.has_method("take_damage") and _can_hit(mp):
					mp.take_damage(attack_damage, global_position, false, Vector3.INF, self)

	_update_locomotion(delta)
	_animate(delta)  ## subclasses pose their limbs (attack animations)

	## Flinch: staggered for a moment after a hit (can't act, slides from knockback).
	if flinch_timer > 0.0:
		flinch_timer -= delta
		velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
		move_and_slide()
		return

	## Stunned-retreat: caught mid-attack, so it turns tail and walks away,
	## giving the player a chance to escape before it re-engages.
	if retreat_timer > 0.0:
		retreat_timer -= delta
		var fleer := _get_player()
		if fleer:
			var away := global_position - fleer.global_position
			away.y = 0.0
			if away.length() > 0.01:
				var fdir := away.normalized()
				_steer(fdir * (wander_speed * 1.8), delta, 8.0)
				_face(fdir, delta, 7.0)
		move_and_slide()
		return

	var player := _get_player()
	var dist := 9999.0
	var to_p := Vector3.ZERO
	if player:
		to_p = player.global_position - global_position
		to_p.y = 0.0
		dist = to_p.length()

	## --- State transitions ---
	## Waking needs line of sight too — a mob in the next chamber shouldn't
	## start hunting you through the wall (it would just pace against the rock).
	if state == State.CALM and player and dist < aggro_radius and not confused and _can_see(player):
		_set_agitated(true)
	elif state == State.AGITATED and (player == null or dist > leash_radius):
		_set_agitated(false)

	if state == State.CALM:
		_do_wander(delta)
	else:
		_do_combat(delta, player, to_p, dist)

	move_and_slide()


func _set_agitated(on: bool) -> void:
	state = State.AGITATED if on else State.CALM
	var col := Color(0.95, 0.15, 0.10) if on else Color(0.05, 0.03, 0.03)
	for em in eye_mats:
		em.albedo_color = col
		em.emission_enabled = on
		if on:
			em.emission = Color(0.95, 0.15, 0.10)
			em.emission_energy_multiplier = 2.5
	if not on:
		strong_active = false
		strong_windup = 0.0
		was_in_melee = false
		_set_telegraph_glow(false)
		_pick_wander()


static func _swing_arc(p: float, chamber: float, through: float) -> float:
	## One realistic cut on a single rotation channel: ease BACK into the
	## chamber, whip through accelerating into the impact (p=0.62, where the
	## damage lands), then settle off the follow-through with a little recoil.
	if p < 0.30:
		var u := p / 0.30
		return chamber * (1.0 - (1.0 - u) * (1.0 - u))
	elif p < 0.62:
		var u := (p - 0.30) / 0.32
		return lerpf(chamber, through, u * u)
	var u := (p - 0.62) / 0.38
	return lerpf(through, through * 0.82, 1.0 - pow(1.0 - u, 3.0))


static func _cut_arc(p: float, carry: float, chamber: float, through: float) -> float:
	## One honest sword cut on a single rotation channel, starting and ending at
	## the CARRY pose (blade at the side, tip low) instead of snapping out of
	## nowhere: lift out of the carry into the chamber, drive through the target
	## (impact at p=0.62, where the damage lands), then ride the follow-through
	## down and begin recovering to the carry.
	if p < 0.34:
		var u := p / 0.34
		return lerpf(carry, chamber, u * u * (3.0 - 2.0 * u))
	elif p < 0.62:
		var u := (p - 0.34) / 0.28
		return lerpf(chamber, through, u * u)
	var u := (p - 0.62) / 0.38
	return lerpf(through, lerpf(through, carry, 0.55), u * u * (3.0 - 2.0 * u))


func _set_telegraph_glow(on: bool) -> void:
	## Whole-body shine telegraphing the strong attack.
	if body_mat:
		body_mat.emission_enabled = on
		if on:
			body_mat.emission = telegraph_color
			body_mat.emission_energy_multiplier = 1.8


func _update_locomotion(delta: float) -> void:
	## A body that moves should look like it's WALKING, not sliding. One gait
	## phase per mob, advanced by real ground speed, with its amplitude eased
	## in and out — feeds the footfall bob here and leg/roll animation in
	## subclasses (see Boar). _sway_t is the drift clock behind the imperfect,
	## surging prowl in _do_combat.
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var target := clampf(hspeed / maxf(chase_speed, 0.1), 0.0, 1.0) if is_on_floor() else 0.0
	_loco_amount = lerpf(_loco_amount, target, clampf(delta * 7.0, 0.0, 1.0))
	if is_on_floor():
		walk_t += delta * (2.0 + minf(hspeed, 9.0) * 2.4) * gait_rate
	_sway_t += delta
	loco_bob_y = absf(sin(walk_t)) * bob_h * _loco_amount
	if loco_root:
		loco_root.position.y = loco_bob_y
		if waddle_deg > 0.0:
			## The waddle: hips roll side to side with each step.
			loco_root.rotation_degrees.z = sin(walk_t) * waddle_deg * _loco_amount
	## Registered hip pivots stride, left and right alternating. (The boar
	## runs its own diagonal-pair trot instead — see Boar._animate.)
	for i in range(walk_legs.size()):
		var ph := 0.0 if i % 2 == 0 else PI
		walk_legs[i].rotation.x = sin(walk_t + ph) * deg_to_rad(stride_deg) * _loco_amount
	## Loose arms counter-swing the legs (weapon arms sway in each _animate's
	## rest pose instead, so attack poses always win).
	for i in range(walk_arms.size()):
		var ph := PI if i % 2 == 0 else 0.0
		walk_arms[i].rotation.x = sin(walk_t + ph) * deg_to_rad(stride_deg * 0.7) * _loco_amount


func _steer(target: Vector3, delta: float, accel := 14.0) -> void:
	## Ease horizontal velocity toward a target instead of snapping to it —
	## mobs lean into starts, stops, and turns like they have weight.
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)


func _face(dir: Vector3, delta: float, rate := 10.0) -> void:
	## Turn toward a heading over time (yaw only) — no more snap-facing.
	if dir.length_squared() < 0.0001:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), clampf(delta * rate, 0.0, 1.0))
	rotation.x = 0.0
	rotation.z = 0.0


func _do_wander(delta: float) -> void:
	wander_timer -= delta
	if wander_timer <= 0.0:
		_pick_wander()
	if confused and wander_dir != Vector3.ZERO:
		wander_dir = wander_dir.rotated(Vector3.UP, delta * 1.6)  ## drifts in lost circles
	elif wander_dir != Vector3.ZERO:
		## Even a calm amble drifts — nobody grazes in a straight line.
		wander_dir = wander_dir.rotated(Vector3.UP, sin(_sway_t * 0.5) * 0.3 * delta)
	if wander_dir != Vector3.ZERO:
		_steer(wander_dir * wander_speed, delta, 5.0)  ## amble, don't lurch
		_face(wander_dir, delta, 5.0)
	else:
		_steer(Vector3.ZERO, delta, 4.0)


func _start_strong(dist: float) -> void:
	_choose_strong(dist)  ## subclasses with several specials pick + configure one
	strong_windup = strong_windup_time
	strong_hits_done = 0
	strong_rehit = 0.0
	_throw_side = 1.0 if randf() < 0.5 else -1.0
	_set_telegraph_glow(true)
	if not always_moving:
		velocity.x = 0.0
		velocity.z = 0.0


func _choose_strong(_dist: float) -> void:
	## Virtual: subclasses with more than one special attack set strong_mode and
	## the strong_* parameters for whichever they picked.
	pass


func _animate(_delta: float) -> void:
	## Virtual: subclasses pose their limbs here every frame.
	pass


func _do_combat(delta: float, player: Node3D, to_p: Vector3, dist: float) -> void:
	strong_cd = maxf(0.0, strong_cd - delta)
	attack_cd = maxf(0.0, attack_cd - delta)
	if player == null:
		return

	var dir := to_p.normalized()
	if not strong_active:
		_face(dir, delta, 12.0)  ## track the player quickly, but turn — not teleport

	## Windup before the strong attack (telegraph — dodge or brace now).
	if strong_windup > 0.0:
		strong_windup -= delta
		if always_moving:
			## Chargers keep bearing down on the player while the glow builds.
			_steer(dir * chase_speed, delta, 20.0)
		else:
			_steer(Vector3.ZERO, delta, 10.0)  ## plant the feet for the windup
		if strong_windup <= 0.0:
			strong_active = true
			strong_time = strong_duration
			strong_dir = dir
		return

	## Active strong attack (charge, pounce, smash, flurry... depending on the mob).
	if strong_active:
		strong_time -= delta
		strong_rehit = maxf(0.0, strong_rehit - delta)
		velocity.x = strong_dir.x * strong_speed
		velocity.z = strong_dir.z * strong_speed
		if dist <= strong_hit_range and strong_hits_done < strong_multi_hits and strong_rehit <= 0.0 and _can_hit(player):
			strong_hits_done += 1
			strong_rehit = strong_hit_interval
			if player.has_method("take_damage"):
				var throw := Vector3.INF
				if strong_throws:
					## The throw vector's LENGTH carries this mob's power — a
					## boar's shove and an ogre's hurl should land very differently.
					if strong_throw_mode == "away":
						throw = strong_dir * strong_throw_power  ## hurled back — a real throw
					else:
						## Shoved to the side; the mob keeps its momentum and barrels PAST.
						throw = Vector3(-strong_dir.z, 0.0, strong_dir.x) * _throw_side * strong_throw_power
						strong_time = maxf(strong_time, strong_runpast)  ## keep running past after the hit
				player.take_damage(strong_damage, global_position, strong_breaks_guard, throw, self)
		if strong_time <= 0.0:
			strong_active = false
			strong_cd = strong_cooldown
			_set_telegraph_glow(false)
			if duelist:
				## Swing wide and settle back into circling before the next pass.
				_duel_hold = randf_range(duel_hold_min, duel_hold_max)
				_duel_side = 1.0 if randf() < 0.5 else -1.0
		return

	## Decide: strong attack from its preferred range, otherwise close in and melee.
	## Chargers (always_moving) never take the standing-bite branch — the charge
	## IS their strike, and between passes they just keep circling.
	if dist > attack_range or always_moving:
		was_in_melee = false
		if strong_cd <= 0.0 and dist >= strong_min_range and dist <= strong_max_range:
			_start_strong(dist)
		elif duelist and dist <= duel_range:
			## Duel: CIRCLE the player (orbit at a steady radius), leaning slightly
			## into the direction of travel, then dart in for a strike.
			if always_moving and _duel_hold <= 0.0:
				## Chargers don't dart in for a bite — keep circling until the
				## next charge is ready.
				_duel_hold = randf_range(duel_hold_min, duel_hold_max)
				_duel_side = 1.0 if randf() < 0.5 else -1.0
			if _duel_hold > 0.0:
				_duel_hold -= delta
				var strafe := Vector3(-dir.z, 0.0, dir.x) * _duel_side
				## Natural prowl, not a compass circle: the orbit radius BREATHES
				## (each mob on its own drift clock), the pace surges and
				## hesitates, and now and then it feints back the other way.
				var wob := sin(_sway_t * 0.7) * 0.9 + sin(_sway_t * 1.6 + 1.7) * 0.5
				var ideal := (attack_range + duel_range) * 0.5 + wob
				var radial := 0.0
				if dist > ideal + 0.6:
					radial = 1.0
				elif dist < ideal - 0.6:
					radial = -1.0
				## Weave a little in/out even inside the band, so the line meanders.
				radial += sin(_sway_t * 1.1 + 0.8) * 0.3
				var move := strafe + dir * radial * 0.5
				if move.length() > 0.01:
					move = move.normalized()
				var pace := 0.45 + 0.35 * (0.5 + 0.5 * sin(_sway_t * 1.3 + 0.5))
				_steer(move * chase_speed * pace, delta, 12.0)
				if randf() < delta * 0.12:
					_duel_side = -_duel_side  ## a sudden feint the other way
				## Face mostly the player, but rotate slightly toward the way we move.
				_face(dir + strafe * duel_lean, delta, 9.0)
			else:
				_steer(dir * chase_speed * 1.5, delta, 22.0)  ## the dart-in stays snappy
		else:
			_steer(dir * chase_speed, delta, 14.0)
	else:
		if strong_from_melee and strong_cd <= 0.0:
			_start_strong(dist)
			return
		if not was_in_melee:
			was_in_melee = true
			attack_cd = 1.0  ## pause a beat after walking up before the first swing
		## Up close and between swings, a real fighter never stands stock-still —
		## it shuffles, sidestepping around the player and jockeying for spacing.
		## During the actual swing it plants more so the blow lands true.
		if melee_anim <= 0.0:
			_shuffle_around(delta, dir, dist)
		else:
			_steer(Vector3.ZERO, delta, 18.0)
		if attack_cd <= 0.0 and melee_anim <= 0.0:
			attack_cd = attack_cooldown
			melee_anim = MELEE_ANIM_TIME  ## start the swing; damage lands mid-animation
			melee_hit_pending = true
			if duelist:
				## After a strike, back off and pace before the next dart-in.
				_duel_hold = randf_range(duel_hold_min, duel_hold_max)
				_duel_side = 1.0 if randf() < 0.5 else -1.0


func _shuffle_around(delta: float, dir: Vector3, dist: float) -> void:
	## The close-quarters strafe: never plant the feet — always circle the player
	## at melee distance. Movement is mostly TANGENTIAL (a steady orbit), with a
	## small radial correction folded in only to hold spacing, so a mob waiting
	## out its cooldown keeps sidestepping around you instead of freezing.
	var strafe := Vector3(-dir.z, 0.0, dir.x) * _shuffle_side
	## Hold just inside striking range, the ideal breathing on this mob's clock.
	var ideal := attack_range - 0.2 + sin(_sway_t * 0.8) * 0.25
	var radial := 0.0
	if dist > ideal + 0.3:
		radial = 0.45          ## drifted out — sidle back in
	elif dist < ideal - 0.3:
		radial = -0.45         ## too close — give a little ground
	## Strafe stays dominant so the net motion always carries it AROUND the
	## player; the radial term only nudges the orbit tighter or wider.
	var move := (strafe + dir * radial * 0.4).normalized()
	## Always moving: a firm floor on pace, just surging and easing a touch.
	var pace := chase_speed * (0.5 + 0.14 * sin(_sway_t * 1.5))
	_steer(move * pace, delta, 12.0)
	## Commit to a direction — only occasionally reverse the orbit, so it reads
	## as circling rather than jittering on the spot.
	if randf() < delta * 0.12:
		_shuffle_side = -_shuffle_side
	_face(dir, delta, 10.0)  ## keep squared up on the player while sidestepping


func _get_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0] is Node3D:
		return players[0]
	return null


func _can_see(target: Node3D) -> bool:
	## Line of sight: nothing solid between us and the target. Packmates don't
	## block the view; walls, floors, and hills do.
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.7, target.global_position + Vector3.UP * 1.2)
	q.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty() or hit.collider == target:
		return true
	return hit.collider is Enemy


func _can_hit(target: Node3D) -> bool:
	## Ghost-hit guard. Range checks flatten Y, so without this a mob in the
	## cave chamber under your feet counted as "2m away" and its bite landed
	## straight through the rock. An attack only connects if the target is on
	## roughly our level AND we can actually see them.
	if absf(target.global_position.y - global_position.y) > 1.8:
		return false
	return _can_see(target)


func take_damage(amount: float) -> void:
	if dying:
		return
	if flinch_timer > 0.0 and parry_open <= 0.0:
		return  ## still flinching from the last hit — can't be hit again yet
	parry_open = 0.0  ## the counter-hit landed; normal flinch rules resume
	var was_strong := strong_active or strong_windup > 0.0
	confused = false  ## getting hit snaps it out of confusion — now it fights
	health -= amount
	hit_flash = 0.12
	if not armored:
		## Thrown out of whatever it was doing — interrupts a strong attack or swing.
		strong_active = false
		strong_windup = 0.0
		was_in_melee = false
		melee_anim = 0.0
		melee_hit_pending = false
		_set_telegraph_glow(false)
		var pl := _get_player()
		if pl:
			var away := global_position - pl.global_position
			away.y = 0.0
			if away.length() > 0.01:
				away = away.normalized()
				velocity.x = away.x * 4.0
				velocity.z = away.z * 4.0
		if was_strong:
			## Caught mid-attack: hard stun, then turn tail and back off a moment.
			flinch_timer = 1.2
			retreat_timer = 3.0
			_set_agitated(false)  ## disengage (eyes calm); retreat drives the walk-away
		else:
			flinch_timer = 1.0
			_set_agitated(true)  ## a normal hit just angers it
	else:
		_set_agitated(true)
	if health <= 0.0:
		_die()


func on_parried() -> void:
	## The player's perfect guard turned this attack aside: whatever we were
	## doing stops dead and we stagger open for a counter. parry_open waives the
	## usual flinch immunity so the counter-hit actually lands.
	if dying:
		return
	strong_active = false
	strong_windup = 0.0
	melee_anim = 0.0
	melee_hit_pending = false
	_set_telegraph_glow(false)
	flinch_timer = 1.4
	parry_open = 1.4
	hit_flash = 0.12
	var pl := _get_player()
	if pl:
		var away := global_position - pl.global_position
		away.y = 0.0
		if away.length() > 0.01:
			away = away.normalized()
			velocity.x = away.x * 3.5
			velocity.z = away.z * 3.5


func _die() -> void:
	dying = true
	velocity = Vector3.ZERO
	## Tell the player's ledger — bestiary kill counts + the Slayer tree both
	## hang off this, so EVERY death source counts (sword, arrow, pickaxe...).
	var slayer := _get_player()
	if slayer and slayer.has_method("on_mob_slain"):
		slayer.on_mob_slain(self)
	for c in get_children():
		if c is CollisionShape3D:
			c.set_deferred("disabled", true)
	_apply_white()  ## step 1: turn fully white
	## Step 2: after a second, burst into pieces, then vanish (no sinking).
	var t := create_tween()
	t.tween_interval(1.0)
	t.tween_callback(_spawn_shards)
	t.tween_interval(0.6)
	t.tween_callback(queue_free)


func _apply_white() -> void:
	## Recursive: meshes may sit under animatable pivots, not just the root.
	for c in find_children("*", "MeshInstance3D", true, false):
		var m := (c as MeshInstance3D).material_override
		if m is StandardMaterial3D:
			var sm := m as StandardMaterial3D
			sm.albedo_color = Color(1, 1, 1)
			sm.emission_enabled = true
			sm.emission = Color(1, 1, 1)
			sm.emission_energy_multiplier = 5.0


func _triangle_mesh(s: float) -> ArrayMesh:
	## A single flat triangle of "radius" s, double-sided.
	var verts := PackedVector3Array([
		Vector3(0.0, s, 0.0),
		Vector3(-s * 0.866, -s * 0.5, 0.0),
		Vector3(s * 0.866, -s * 0.5, 0.0),
	])
	var normals := PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


func _xp_orb_value() -> int:
	## XP per orb — scales SLOWLY with essence tier (green 2, yellow 3, blue 4,
	## purple 5). Subclasses may override (boars feed young hunters, Boar.gd).
	return 2 + orb_tier


func _xp_color() -> Color:
	## Essence color rides orb_tier, NOT xp_tier: the whole current roster
	## bleeds green — richer colors are saved for genuinely elite creatures.
	match orb_tier:
		1: return Color(1.0, 0.90, 0.25)   ## yellow
		2: return Color(0.35, 0.60, 1.0)   ## blue
		3: return Color(0.70, 0.30, 1.0)   ## purple
		_: return Color(0.25, 1.0, 0.35)   ## green (default / low level)


func _rand_burst() -> Vector3:
	var d := Vector3(randf() - 0.5, randf() * 0.6 + 0.3, randf() - 0.5)
	if d.length() < 0.01:
		d = Vector3.UP
	return d.normalized() * randf_range(2.0, 3.5)


func _spawn_pickups() -> void:
	## XP orbs (color = tier) and a few gold coins, added to the world so they
	## persist after the corpse frees. They scatter, fall, and wait on the ground.
	var parent := get_parent()
	if parent == null:
		return
	var origin := global_position + Vector3(0, 0.6, 0)
	var col := _xp_color()

	## Stronger kinds don't drop richer orbs (yet) — they drop MORE of them:
	## 3 / 5 / 7 / 9 greens by tier.
	for _i in range(3 + xp_tier * 2):
		var orb := PickupOrb.new()
		var sm := SphereMesh.new()
		sm.radius = 0.08
		sm.height = 0.16
		orb.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 3.0
		orb.material_override = mat
		orb.kind = "xp"
		orb.value = _xp_orb_value()
		parent.add_child(orb)
		orb.global_position = origin
		orb.burst_dir = _rand_burst()

	if _drops_coins():
		for _i in range(randi_range(1, 4)):
			var coin := PickupOrb.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.07
			cm.bottom_radius = 0.07
			cm.height = 0.02
			cm.radial_segments = 10
			coin.mesh = cm
			coin.rotation = Vector3(PI * 0.5, 0, 0)
			var gmat := StandardMaterial3D.new()
			gmat.albedo_color = Color(1.0, 0.84, 0.25)
			gmat.metallic = 1.0
			gmat.roughness = 0.3
			gmat.emission_enabled = true
			gmat.emission = Color(0.8, 0.6, 0.1)
			gmat.emission_energy_multiplier = 0.6
			coin.material_override = gmat
			coin.kind = "coin"
			coin.value = randi_range(1, 5)
			parent.add_child(coin)
			coin.global_position = origin
			coin.burst_dir = _rand_burst()

	## Rare sword drop — v1 slice materials only (iron/steel/silver/meteoric),
	## chance + weighting climb with the mob's tier. See docs/MATERIALS.md.
	## Beasts carry no weapons — they drop nothing but essence.
	if not ("beast" in families):
		var mat_id := Materials.roll_sword_drop(xp_tier)
		if mat_id != "":
			var sw := PickupOrb.make_sword(mat_id)
			parent.add_child(sw)
			sw.global_position = origin
			sw.burst_dir = _rand_burst()


func _drops_coins() -> bool:
	## Beasts have no purse, and the undead lost theirs to rot long ago. The
	## exception: zombies (fresh corpses, pockets intact) — when they're added,
	## tag them ["undead", "zombie"] and the coins come back.
	if "zombie" in families:
		return true
	return not ("beast" in families or "undead" in families)


func _spawn_shards() -> void:
	## Hide the body and explode a big burst of triangle shards outward.
	_spawn_pickups()
	for c in find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).visible = false
	var center := Vector3(0, 0.6, 0)
	for _i in range(48):
		var shard := MeshInstance3D.new()
		shard.mesh = _triangle_mesh(randf_range(0.18, 0.34))
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.80, 0.78, 0.74)  ## pale, fresh from the white flash
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED  ## visible from both sides
		shard.material_override = mat
		shard.position = center
		shard.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		add_child(shard)
		var dir := Vector3(randf() - 0.5, randf() - 0.15, randf() - 0.5)
		if dir.length() < 0.01:
			dir = Vector3.UP
		dir = dir.normalized()
		var dist := randf_range(1.0, 1.7)
		var st := create_tween()
		st.set_parallel(true)
		st.tween_property(shard, "position", center + dir * dist, 0.32)
		st.tween_property(shard, "scale", Vector3(0.15, 0.15, 0.15), 0.55)
