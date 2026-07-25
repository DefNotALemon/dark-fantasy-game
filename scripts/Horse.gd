extends Enemy
class_name Horse
## Passive wildlife (step 6, first pass) — the WILD horse. Grazes and roams the
## overworld, bolts if you press in close, and NEVER takes a rider. Hurt one and
## it answers before it flees: it wheels its rump to you and KICKS — a hoof like
## a hammer that puts you flat on the ground (see Player.horse_kick /
## _start_knockdown). Any horse you've hurt is trust-broken for good.
##
## The tame, saddled, rideable kind is SaddledHorse.gd. While ridden, the rider
## drives this body directly (_do_ridden) — camera-relative reins, Shift to
## gallop, Space to jump. Your own swings can never hit the horse under you;
## the buck-off path stays for anything else that hurts a ridden horse (and
## for a horse dying under its rider).

const KICK_WINDUP := 0.30     ## wheeling its rear toward you
const KICK_ACTIVE := 0.34     ## hind legs snapped out
const KICK_HIT_AT := 0.12     ## into the active phase — when the hooves land
const KICK_RANGE := 2.9       ## hind hooves reach
const KICK_TRIGGER := 3.6     ## a blade inside this = wheel and kick, not just flee
const KICK_DAMAGE := 14.0
const RIDE_WALK := 4.6
const RIDE_RUN := 11.0        ## a gallop outruns any sprinting boot
const RIDE_JUMP := 5.4
const BUCK_TIME := 0.5        ## rearing up as it hurls the rider

var rideable := false         ## wild horses never take a rider
var trust_broken := false     ## hurt it once and this is forever
var skittish_radius := 8.0    ## wild horses bolt inside this (0 = calm near people)

## --- The panic bolt: no horse goes willingly underground, and no horse
## shields a rider forever. Ride one down a cave throat (or use up its last
## heart) and it rears, hurls you off, and BOLTS — out of the dark first if
## it must, then 8-13 honest meters past the spot where it found open ground
## before it lets itself settle. Terror, not betrayal — trust survives. ---
const CAVE_PANIC_Y := -2.2    ## this deep with a rider aboard = the ride is over
var _surface_pos := Vector3.ZERO   ## last footing that still felt like daylight
var _panic_t := 0.0                ## safety clock on a bolt (never runs forever)
var _panic_from := Vector3.INF     ## stamped where hooves find open ground; the bolt ends past it
var _panic_range := 10.0           ## 8-13 m, rolled fresh per panic

## --- Riding (rider = the Player while mounted; it feeds the reins each frame) ---
var rider: CharacterBody3D = null
var ride_input := Vector2.ZERO   ## camera-relative reins (x strafe, y forward)
var ride_run := false
var _ride_jump := false

## --- The kick ---
var kicking := false
var kick_timer := 0.0
var kick_cd := 0.0
var _kick_hit_done := false
var _buck_t := 0.0            ## rear-up pose timer (bucking a rider off)

## --- Body ---
var rig: Node3D
var legs_all: Array[Node3D] = []    ## FL, FR, BL, BR hip pivots
var neck_pivot: Node3D
var tail_pivot: Node3D
var coat := Color(0.30, 0.20, 0.12)


func _init() -> void:
	display_name = "Horse"
	max_health = 3.0  ## horses count HITS, not damage: 3 hearts (see hearts below)
	wander_speed = 1.7
	chase_speed = 9.0        ## its "combat" is FLIGHT — and horses are fast
	attack_range = 0.0       ## it never bites
	attack_damage = 0.0
	strong_damage = KICK_DAMAGE   ## the bestiary's "Fury" line = the kick
	aggro_radius = 0.0       ## never hunts anyone
	leash_radius = 26.0      ## how far it runs before settling back to graze
	can_climb = false        ## flight stays on the ground — no wall-scaling horses
	xp_tier = 1
	families = ["beast"]
	gait_rate = 1.15
	stride_deg = 30.0
	bob_h = 0.07


func _ready() -> void:
	super()
	add_to_group("horses")
	_surface_pos = global_position  ## horses spawn under open sky


func request_jump() -> void:
	_ride_jump = true


func saddle_world() -> Vector3:
	## Where the rider sits (world space).
	return to_global(Vector3(0, 1.16, -0.05))


func can_carry() -> bool:
	## Willing AND able: saddled, trusting, hearts to spare, not mid-panic.
	## (Player._try_mount_toggle asks before every mount — a bolting or
	## spent horse needs its breath and its hearts back first.)
	return rideable and not trust_broken and hearts > 0 and _panic_t <= 0.0


## ============================ Behaviour ===================================


func _physics_process(delta: float) -> void:
	if dying:
		move_and_slide()
		return

	kick_cd = maxf(0.0, kick_cd - delta)
	if _buck_t > 0.0:
		_buck_t -= delta

	if rider != null:
		_do_ridden(delta)
		_update_locomotion(delta)
		_animate(delta)
		move_and_slide()
		return

	if kicking:
		_do_kick(delta)
		_update_locomotion(delta)
		_animate(delta)
		move_and_slide()
		return

	if _panic_t > 0.0:
		## Bolting: nothing else matters until it's out and CLEAR.
		_panic_t -= delta
		_do_panic_flee(delta)
		_update_locomotion(delta)
		_animate(delta)
		move_and_slide()
		if _panic_t <= 0.0 or _panic_cleared():
			_panic_t = 0.0
			_set_agitated(false)  ## far enough — settle, breathe, graze
		return

	super(delta)


func _do_ridden(delta: float) -> void:
	## Remember the last open-sky footing — and the moment a cave throat
	## swallows the body, the ride is OVER: rear, throw, bolt for the light.
	if is_on_floor() and global_position.y > -0.8:
		_surface_pos = global_position
	if global_position.y < CAVE_PANIC_Y:
		_cave_panic()
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif _ride_jump:
		velocity.y = RIDE_JUMP
	_ride_jump = false

	var fwd := -transform.basis.z
	var desired := Vector3.ZERO
	var in3 := Vector3(ride_input.x, 0.0, ride_input.y)
	if rider != null and in3.length() > 0.05:
		## Camera-relative reins: the horse turns toward where the rider is
		## steering, and only builds speed as its body comes around — it turns
		## like an animal with a neck, not a strafing capsule.
		desired = rider.transform.basis * in3
		desired.y = 0.0
		if desired.length() > 0.01:
			desired = desired.normalized()

	if desired != Vector3.ZERO:
		_face(desired, delta, 2.6)  ## wide, committed turns
		var align := fwd.dot(desired)
		var speed := (RIDE_RUN if ride_run else RIDE_WALK) * clampf(maxf(align, 0.22), 0.0, 1.0)
		_steer(fwd * speed, delta, 10.0)
	else:
		_steer(Vector3.ZERO, delta, 8.0)


func _do_kick(delta: float) -> void:
	kick_timer += delta
	if not is_on_floor():
		velocity.y -= gravity * delta
	## Plant while the rear wheels around.
	velocity.x = move_toward(velocity.x, 0.0, 16.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 16.0 * delta)
	if hit_flash > 0.0:
		hit_flash -= delta
		if body_mat:
			body_mat.albedo_color = Color(0.9, 0.6, 0.55) if hit_flash > 0.0 else base_body_color

	var pl := _get_player()
	if pl != null and kick_timer < KICK_WINDUP:
		## Wheel the RUMP toward the threat — the kick comes from the hind legs.
		var away := global_position - pl.global_position
		away.y = 0.0
		if away.length() > 0.01:
			_face(away.normalized(), delta, 14.0)

	if not _kick_hit_done and kick_timer >= KICK_WINDUP + KICK_HIT_AT:
		_kick_hit_done = true
		if pl != null:
			var to_p := pl.global_position - global_position
			to_p.y = 0.0
			var behind := to_p.normalized().dot(transform.basis.z) > 0.25
			if to_p.length() <= KICK_RANGE and behind and pl.has_method("horse_kick"):
				pl.horse_kick(KICK_DAMAGE, global_position, self)

	if kick_timer >= KICK_WINDUP + KICK_ACTIVE:
		kicking = false
		kick_cd = 3.0
		_set_agitated(true)  ## now RUN


func _cave_panic() -> void:
	## The dark closed over its ears — no reins can argue with this. The rider
	## leaves the saddle the hard way; the horse takes the throat back up at a
	## blind gallop and keeps running. Trust survives: terror, not betrayal.
	var pl := rider
	_buck_off()
	_start_panic()
	if pl != null and pl.has_method("notify"):
		pl.notify("The horse rears — it will NOT go underground!", Color(1.0, 0.75, 0.35))


func _start_panic() -> void:
	## One bolt, two legs: get OUT (if underground), then get CLEAR — the run
	## ends 8-13 m past wherever hooves found open ground again.
	_panic_t = 14.0
	_panic_range = randf_range(8.0, 13.0)
	_panic_from = global_position if global_position.y > -1.2 else Vector3.INF


func _panic_cleared() -> bool:
	## Clear = above ground AND far enough from the doorstep it surfaced at.
	if global_position.y < -1.2 or _panic_from == Vector3.INF:
		return false
	var flat := global_position - _panic_from
	flat.y = 0.0
	return flat.length() >= _panic_range


func _do_panic_flee(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	if global_position.y < -1.2:
		## Underground: gallop for the last remembered daylight footing.
		var out := _surface_pos - global_position
		out.y = 0.0
		if out.length() > 1.2:
			var d := out.normalized()
			_steer(d * chase_speed, delta, 14.0)
			_face(d, delta, 6.0)
		else:
			## Right under the remembered spot but still deep — charge straight
			## on (the ramp bends; momentum finds it).
			var ahead := -transform.basis.z
			ahead.y = 0.0
			if ahead.length() > 0.01:
				_steer(ahead.normalized() * chase_speed, delta, 10.0)
		return
	## Open ground: stamp the doorstep the first time hooves find it, then put
	## honest meters between horse and hole.
	if _panic_from == Vector3.INF:
		_panic_from = global_position
	var away := global_position - _panic_from
	away.y = 0.0
	if away.length() < 0.5:
		## Fresh out of the hole — bearing is ambiguous, so run from the rider
		## (or just keep charging the way the body already points).
		var pl := _get_player()
		away = (global_position - pl.global_position) if pl != null else -transform.basis.z
		away.y = 0.0
	if away.length() > 0.01:
		away = away.normalized()
		_steer(away * chase_speed, delta, 12.0)
		_face(away, delta, 6.0)


func _do_wander(delta: float) -> void:
	## Skittish: wild (and betrayed) horses bolt when someone presses in close.
	var r := skittish_radius
	if trust_broken:
		r = maxf(r, 7.0)
	if r > 0.0:
		var pl := _get_player()
		if pl != null and global_position.distance_to(pl.global_position) < r and _can_see(pl):
			_set_agitated(true)
			return
	super(delta)


func _do_combat(delta: float, player: Node3D, to_p: Vector3, dist: float) -> void:
	## A horse's AGITATED state is pure flight (the base leash calms it once it
	## has put distance between you). Corner one and it answers with hooves.
	if player == null:
		return
	if dist < 2.4 and kick_cd <= 0.0 and not kicking:
		_start_kick()
		return
	var away := -to_p
	away.y = 0.0
	if away.length() > 0.01:
		away = away.normalized()
		_steer(away * chase_speed, delta, 16.0)
		_face(away, delta, 8.0)


func _set_agitated(on: bool) -> void:
	## Same state machine, but no glowing red predator eyes — a spooked horse
	## just runs. Keep the eyes dark glass.
	super(on)
	for em in eye_mats:
		em.albedo_color = Color(0.06, 0.045, 0.035)
		em.emission_enabled = false


func _start_kick() -> void:
	kicking = true
	kick_timer = 0.0
	_kick_hit_done = false
	strong_active = false
	strong_windup = 0.0


## --- Hearts: a horse takes 3 HITS (any hit = one heart, damage numbers be
## damned). Three unharmed seconds regrow one heart at a time. WHO sees the
## tally depends on who should care: with a RIDER aboard it lives on the
## rider's HUD (Player.mount_hearts — an enemy catching your mount shows up
## right under your own bars); loose horses hurt by the WORLD pop the ♥♥♥
## pips over the head. Your OWN strikes get no sympathy card — you know what
## you did (the trust break message says the rest). ---
var hearts := 3
var _since_hit := 999.0
var _hearts_lbl: Label3D = null
var _hearts_show := 0.0


func _process(delta: float) -> void:
	if dying:
		if _hearts_lbl != null:
			_hearts_lbl.visible = false
		return
	_since_hit += delta
	if hearts < 3 and _since_hit >= 3.0:
		hearts += 1
		health = float(hearts)
		_since_hit = 0.0
		## Show the heart growing back wherever the tally already lives: the
		## rider's HUD reads it by itself; the overhead pips only wake if
		## they were already up (a world-hurt display cycle in progress).
		if rider == null and _hearts_show > 0.0:
			_hearts_show = maxf(_hearts_show, 1.6)
		_update_hearts_ui()
	if rider != null:
		if _hearts_lbl != null:
			_hearts_lbl.visible = false  ## the HUD carries it while ridden
	elif _hearts_show > 0.0:
		_hearts_show -= delta
		if _hearts_lbl != null:
			_hearts_lbl.visible = true
			_hearts_lbl.modulate.a = clampf(_hearts_show / 0.6, 0.0, 1.0)
	elif _hearts_lbl != null:
		_hearts_lbl.visible = false


func _take_heart_hit(from_player := false) -> void:
	hearts -= 1
	health = float(hearts)
	_since_hit = 0.0
	if rider != null:
		## In the saddle the tally rides the rider's HUD — flash it awake.
		if "mount_heart_flash" in rider:
			rider.set("mount_heart_flash", 1.2)
	elif not from_player:
		## Overhead pips: for watching a horse weather the WORLD. Your own
		## blade gets no display — the horse's opinion of you shows other ways.
		_hearts_show = 4.0
		_ensure_hearts_ui()
	_update_hearts_ui()
	hit_flash = 0.12
	if body_mat:
		body_mat.albedo_color = Color(0.9, 0.6, 0.55)


func _ensure_hearts_ui() -> void:
	if _hearts_lbl != null:
		return
	_hearts_lbl = Label3D.new()
	_hearts_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hearts_lbl.no_depth_test = true
	_hearts_lbl.font_size = 64
	_hearts_lbl.pixel_size = 0.01
	_hearts_lbl.outline_size = 18
	_hearts_lbl.modulate = Color(1.0, 0.36, 0.42)
	_hearts_lbl.position = Vector3(0, 2.15, 0)
	add_child(_hearts_lbl)


func _update_hearts_ui() -> void:
	if _hearts_lbl != null:
		## Filled hearts keep the left; the emptied ones stack in from the
		## RIGHT — first hit hollows the rightmost.
		_hearts_lbl.text = "♥".repeat(maxi(hearts, 0)) + "♡".repeat(3 - maxi(hearts, 0))


func rider_shielded_hit() -> void:
	## THE MOUNT IS THE GUARD (Player.take_damage routes here): a blow that
	## lands on the rider costs the horse a HEART instead of rider health.
	## Three of those and it has had ENOUGH — off you go, away it goes. It
	## LIVES: hearts grow back, and shielding you breaks no trust.
	if dying:
		return
	_take_heart_hit(false)
	if hearts <= 0:
		_enough_buck()


func _enough_buck() -> void:
	## The last heart spent under a rider: rear, throw, bolt — alive.
	var pl := rider
	_buck_off()
	_start_panic()
	if pl != null and pl.has_method("notify"):
		pl.notify("The horse has had enough — it throws you and bolts!", Color(1.0, 0.75, 0.35))


func take_damage(_amount: float, _from_pos = null, _strong = false, _throw = null, attacker: Node = null) -> void:
	## Horses don't stagger and trade blows — they retaliate ONCE and then run.
	## Harm from YOUR hand breaks its trust forever (saddled ones included);
	## a goblin's club does NOT — the horse just bolts, and remembers nothing.
	if dying:
		return
	confused = false
	if attacker is Enemy:
		## Predator, not master: pure flight — no trust lost, no kick duel.
		_take_heart_hit(false)
		if hearts <= 0:
			if rider != null:
				## Spent its last heart under you: bucked and gone, not dead.
				_enough_buck()
			else:
				_die()
			return
		if rider == null:
			_set_agitated(true)  ## loose horse: bolt (ridden ones keep the rider's reins)
		return
	var was_trusted := rideable and not trust_broken
	trust_broken = true
	_take_heart_hit(true)

	var pl := _get_player()
	if was_trusted and pl != null and pl.has_method("notify"):
		pl.notify("The horse will never carry you again", Color(0.95, 0.55, 0.45))

	if hearts <= 0:
		if rider != null:
			_buck_off()  ## it dies under you — you go down with it
		_die()
		return

	if rider != null:
		## Steel into your own mount: it rears, hurls you off, and the hooves
		## find you on the ground before it bolts.
		_buck_off()
		kick_cd = 0.0
		_start_kick()
	elif pl != null and global_position.distance_to(pl.global_position) <= KICK_TRIGGER and kick_cd <= 0.0 and not kicking:
		_start_kick()
	else:
		_set_agitated(true)


func _buck_off() -> void:
	var pl := rider
	rider = null
	ride_input = Vector2.ZERO
	_buck_t = BUCK_TIME
	if pl != null and pl.has_method("thrown_from_mount"):
		pl.thrown_from_mount(self)


func _die() -> void:
	if rider != null:
		_buck_off()  ## never strand a ghost rider on a corpse
	super()


## ============================ Body & animation =============================


func _animate(delta: float) -> void:
	if rig == null:
		return
	## Diagonal-pair trot/gallop on the shared gait phase (FL+BR / FR+BL),
	## swinging harder the faster the body actually moves.
	var swing := 0.62 * _loco_amount
	for i in range(legs_all.size()):
		var ph := 0.0 if (i == 0 or i == 3) else PI
		legs_all[i].rotation.x = sin(walk_t + ph) * swing

	## Kick pose: nose dips, rear rises, hind legs snap out behind.
	var body_pitch := 0.0
	if kicking:
		if kick_timer >= KICK_WINDUP:
			var u := clampf((kick_timer - KICK_WINDUP) / KICK_ACTIVE, 0.0, 1.0)
			var snap := sin(minf(u * 1.6, 1.0) * PI)  ## out fast, back down
			legs_all[2].rotation.x = -2.0 * snap
			legs_all[3].rotation.x = -2.0 * snap
			body_pitch = 12.0 * snap  ## nose down, hooves up
	elif _buck_t > 0.0:
		## Rearing: front end hurled skyward as the rider leaves the saddle.
		var u := _buck_t / BUCK_TIME
		body_pitch = -34.0 * sin(u * PI)

	## Gallop lean + neck/tail life.
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var lean := -3.5 * clampf(hspeed / RIDE_RUN, 0.0, 1.0)
	rig.rotation_degrees.x = lerpf(rig.rotation_degrees.x, body_pitch + lean, clampf(delta * 9.0, 0.0, 1.0))
	rig.rotation_degrees.z = sin(walk_t) * 1.6 * _loco_amount
	if neck_pivot:
		neck_pivot.rotation.x = sin(walk_t) * 0.09 * _loco_amount \
			+ (0.14 if (kicking or _buck_t > 0.0) else 0.0)
	if tail_pivot:
		tail_pivot.rotation.x = sin(_sway_t * 1.7) * 0.14 + sin(walk_t) * 0.10 * _loco_amount


func _build_body() -> void:
	_add_collision(Vector3(0.95, 1.5, 2.1), Vector3(0, 0.95, 0))

	rig = Node3D.new()
	add_child(rig)
	loco_root = rig

	## Coat: bay / chestnut / dun / near-black, mane always darker.
	var coats: Array[Color] = [
		Color(0.30, 0.20, 0.12), Color(0.38, 0.22, 0.12),
		Color(0.42, 0.34, 0.22), Color(0.16, 0.12, 0.10),
	]
	coat = coats[randi() % coats.size()]
	var dark := Color(coat.r * 0.45, coat.g * 0.45, coat.b * 0.45)
	var hoof := Color(0.12, 0.10, 0.08)
	base_body_color = coat

	## Barrel (faces -z), chest and rump.
	var body := _box_in(rig, Vector3(0.66, 0.64, 1.75), coat, Vector3(0, 1.18, 0))
	body_mat = body.material_override as StandardMaterial3D
	_box_in(rig, Vector3(0.60, 0.56, 0.46), coat, Vector3(0, 1.12, -0.78))
	_box_in(rig, Vector3(0.62, 0.58, 0.50), coat, Vector3(0, 1.16, 0.72))

	## Neck + head on a pivot so the whole front bobs with the stride.
	neck_pivot = Node3D.new()
	rig.add_child(neck_pivot)
	neck_pivot.position = Vector3(0, 1.34, -0.86)
	_box_in(neck_pivot, Vector3(0.26, 0.74, 0.32), coat, Vector3(0, 0.30, -0.16), Vector3(-38, 0, 0))
	_box_in(neck_pivot, Vector3(0.24, 0.28, 0.50), coat, Vector3(0, 0.64, -0.48))          ## head
	_box_in(neck_pivot, Vector3(0.17, 0.20, 0.24), dark, Vector3(0, 0.58, -0.80))          ## muzzle
	_box_in(neck_pivot, Vector3(0.05, 0.15, 0.05), dark, Vector3(-0.08, 0.83, -0.42))      ## ears
	_box_in(neck_pivot, Vector3(0.05, 0.15, 0.05), dark, Vector3(0.08, 0.83, -0.42))
	## Mane: a ragged crest down the neck's top line.
	_box_in(neck_pivot, Vector3(0.09, 0.55, 0.12), dark, Vector3(0, 0.42, 0.06), Vector3(-38, 0, 0))
	_box_in(neck_pivot, Vector3(0.09, 0.16, 0.10), dark, Vector3(0, 0.76, -0.24))
	_add_eye(Vector3(-0.13, 0.66, -0.62), Vector3(0.05, 0.05, 0.04), neck_pivot)
	_add_eye(Vector3(0.13, 0.66, -0.62), Vector3(0.05, 0.05, 0.04), neck_pivot)

	## Legs: FL, FR, BL, BR hip pivots (diagonal pairs trot in _animate).
	for p: Vector3 in [Vector3(-0.24, 1.0, -0.62), Vector3(0.24, 1.0, -0.62),
			Vector3(-0.24, 1.0, 0.66), Vector3(0.24, 1.0, 0.66)]:
		var leg := Node3D.new()
		rig.add_child(leg)
		leg.position = p
		_box_in(leg, Vector3(0.17, 0.55, 0.19), coat, Vector3(0, -0.26, 0))
		_box_in(leg, Vector3(0.13, 0.50, 0.14), dark, Vector3(0, -0.74, 0.01))
		_box_in(leg, Vector3(0.15, 0.10, 0.17), hoof, Vector3(0, -0.99, 0.02))
		legs_all.append(leg)

	## Tail on its own pivot so it can swish.
	tail_pivot = Node3D.new()
	rig.add_child(tail_pivot)
	tail_pivot.position = Vector3(0, 1.36, 0.96)
	_box_in(tail_pivot, Vector3(0.09, 0.56, 0.10), dark, Vector3(0, -0.24, 0.06), Vector3(14, 0, 0))

	if rideable:
		_build_saddle(dark)


func _build_saddle(strap: Color) -> void:
	## Tack marks the tame kind at a glance: blanket, seat, and stirrups.
	var leather := Color(0.32, 0.19, 0.10)
	var blanket := Color(0.28, 0.11, 0.12)
	_box_in(rig, Vector3(0.72, 0.05, 0.72), blanket, Vector3(0, 1.51, -0.02))
	_box_in(rig, Vector3(0.50, 0.10, 0.60), leather, Vector3(0, 1.58, -0.02))
	_box_in(rig, Vector3(0.42, 0.13, 0.10), leather, Vector3(0, 1.65, 0.24))   ## cantle
	_box_in(rig, Vector3(0.34, 0.11, 0.08), leather, Vector3(0, 1.65, -0.28))  ## pommel
	for sx: float in [-0.36, 0.36]:
		_box_in(rig, Vector3(0.03, 0.44, 0.09), strap, Vector3(sx, 1.30, -0.02))
		_box_in(rig, Vector3(0.10, 0.04, 0.13), Color(0.55, 0.58, 0.62), Vector3(sx, 1.06, -0.02), Vector3.ZERO, true)
