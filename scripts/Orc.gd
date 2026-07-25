extends Enemy
class_name Orc
## Fast, strong sword-wielding raider — hits harder than a skeleton and barely
## lets up. Duels aggressively. Attacks vary: "charge" (shared shoulder-rush that
## shoves you aside and barrels past), "thrust" (a hard lunging stab), and a
## rapid three-hit "slash" combo.

var rig: Node3D
var arm: Node3D    ## shoulder pivot (upper arm)
var hand: Node3D   ## elbow/wrist pivot — the sword hangs off this


func _init() -> void:
	display_name = "Orc"
	max_health = 120.0       ## takes several hits and keeps coming
	wander_speed = 1.8
	chase_speed = 5.6          ## faster than the others
	attack_range = 2.0
	attack_damage = 15.0
	attack_cooldown = 0.7      ## relentless — swings often
	aggro_radius = 13.0
	leash_radius = 28.0
	xp_tier = 2
	families = ["humanoid"]
	duelist = true
	duel_range = 6.0
	duel_hold_min = 0.15       ## barely pauses; always pressing in
	duel_hold_max = 0.45
	strong_from_melee = true
	strong_min_range = 2.5
	strong_max_range = 7.0
	telegraph_color = Color(0.95, 0.25, 0.05)
	climb_speed = 2.7   ## muscles a wall the way it muscles everything else
	## Gait: hard, eager strides.
	gait_rate = 1.0
	stride_deg = 30.0
	waddle_deg = 2.2


func _choose_strong(dist: float) -> void:
	if dist > strong_min_range and dist <= strong_max_range and randf() < 0.6:
		strong_mode = "charge"    ## shared shoulder-rush — shoves aside, runs past
		strong_throws = true
		strong_throw_mode = "side"
		strong_throw_power = 7.0  ## tosses you a couple feet — if you're not blocking
		strong_damage = 18.0
		strong_speed = 12.0
		strong_windup_time = 0.40
		strong_duration = 0.45
		strong_cooldown = 3.0
		strong_hit_range = 2.1
		strong_breaks_guard = true
		strong_multi_hits = 1
	elif randf() < 0.5:
		strong_mode = "thrust"    ## hard lunging stab (guard-break)
		strong_throws = false
		strong_damage = 19.0
		strong_speed = 7.0
		strong_windup_time = 0.35
		strong_duration = 0.30
		strong_cooldown = 3.2
		strong_hit_range = 2.5
		strong_breaks_guard = true
		strong_multi_hits = 1
	else:
		strong_mode = "slash"     ## rapid three-hit sword combo (blockable)
		strong_throws = false
		strong_damage = 9.0
		strong_speed = 2.0
		strong_windup_time = 0.30
		strong_duration = 0.75
		strong_cooldown = 3.2
		strong_hit_range = 2.3
		strong_breaks_guard = false
		strong_multi_hits = 3
		strong_hit_interval = 0.20


## The resting carry: shoulder hanging, elbow angling the blade down and just
## behind the leg so the tip clears the dirt. Exactly how a man walks with a
## drawn sword. Every attack lifts out of this pose and recovers back into it.
const CARRY_ARM := Vector3(-4.0, 0.0, 8.0)
const CARRY_HAND := Vector3(-40.0, 0.0, 6.0)


func _animate(delta: float) -> void:
	if arm == null:
		return
	if strong_windup > 0.0:
		var p := 1.0 - strong_windup / strong_windup_time
		if strong_mode == "thrust":
			## Draw the elbow back and level the point at you.
			arm.rotation_degrees = arm.rotation_degrees.lerp(Vector3(lerpf(CARRY_ARM.x, -30.0, p), 0, lerpf(CARRY_ARM.z, 4.0, p)), delta * 16.0)
			hand.rotation_degrees = hand.rotation_degrees.lerp(Vector3(lerpf(CARRY_HAND.x, 66.0, p), 0, 0), delta * 16.0)
		elif strong_mode == "charge":
			rig.rotation_degrees = rig.rotation_degrees.lerp(Vector3(-14.0 * p, 0, 0), delta * 14.0)
			_lerp_carry(delta * 8.0)
		else:
			## Chamber the blade up over the shoulder — elbow stays at his side.
			arm.rotation_degrees = arm.rotation_degrees.lerp(Vector3(lerpf(CARRY_ARM.x, -42.0, p), -12.0 * p, lerpf(CARRY_ARM.z, 10.0, p)), delta * 16.0)
			hand.rotation_degrees = hand.rotation_degrees.lerp(Vector3(lerpf(CARRY_HAND.x, -82.0, p), 0, 0), delta * 16.0)
		return
	if strong_active:
		var p := 1.0 - strong_time / strong_duration
		if strong_mode == "thrust":
			## The stab RAMS forward: the shoulder drives, the point stays level.
			var c := minf(p * 2.5, 1.0)
			arm.rotation_degrees = Vector3(lerpf(-30.0, 20.0, c * c), 0, 4.0)
			hand.rotation_degrees = Vector3(lerpf(66.0, 72.0, c), 0, 0)
		elif strong_mode == "charge":
			var c := minf(p * 2.0, 1.0)
			rig.rotation_degrees = Vector3(lerpf(-14.0, 16.0, c * c), 0, 0)
			_lerp_carry(delta * 8.0)
		else:
			## Three sloppy-confident cuts crossing the body side to side —
			## whip down fast off the shoulder, re-chamber lazily.
			var q := fmod(p * 3.0, 1.0)
			var sh: float
			var wr: float
			if q < 0.5:
				var u := q / 0.5
				sh = lerpf(-42.0, 34.0, u * u)
				wr = lerpf(-82.0, 24.0, u * u)
			else:
				var u := (q - 0.5) / 0.5
				var e := u * u * (3.0 - 2.0 * u)
				sh = lerpf(34.0, -42.0, e)
				wr = lerpf(24.0, -82.0, e)
			arm.rotation_degrees = Vector3(sh, sin(p * PI * 3.0) * 22.0, 10.0)
			hand.rotation_degrees = Vector3(wr, 0, 0)
		return
	if melee_anim > 0.0:
		## The raider's cleave: lift from the carry, chamber over the shoulder,
		## and haul it through on a loose diagonal — then let it fall back.
		var p := 1.0 - melee_anim / MELEE_ANIM_TIME
		arm.rotation_degrees = Vector3(
			_cut_arc(p, CARRY_ARM.x, -46.0, 40.0),
			_cut_arc(p, CARRY_ARM.y, -14.0, 22.0),
			_cut_arc(p, CARRY_ARM.z, 12.0, -6.0))
		hand.rotation_degrees = Vector3(
			_cut_arc(p, CARRY_HAND.x, -100.0, 26.0), 0, _cut_arc(p, CARRY_HAND.z, 8.0, -4.0))
		rig.rotation_degrees = Vector3(_swing_arc(p, -6.0, 9.0), _swing_arc(p, -8.0, 10.0), 0)
		return
	rig.rotation_degrees = rig.rotation_degrees.lerp(Vector3.ZERO, delta * 8.0)
	_lerp_carry(delta * 7.0, sin(walk_t) * 6.0 * _loco_amount)


func _lerp_carry(k: float, sway := 0.0) -> void:
	arm.rotation_degrees = arm.rotation_degrees.lerp(CARRY_ARM + Vector3(sway, 0, 0), k)
	hand.rotation_degrees = hand.rotation_degrees.lerp(CARRY_HAND + Vector3(sway * 0.4, 0, 0), k)


func _build_body() -> void:
	_add_collision(Vector3(0.8, 1.7, 0.7), Vector3(0, 0.9, 0))

	## Palette swapped with the Ogre: the raider is now the grey-tan brute-hide,
	## while the ogre wears the deep green.
	var skin := Color(0.46, 0.42, 0.30)
	var skin_dark := Color(0.34, 0.31, 0.22)
	var leather := Color(0.24, 0.16, 0.10)
	var steel := Color(0.58, 0.60, 0.66)
	base_body_color = skin

	rig = Node3D.new()
	add_child(rig)
	loco_root = rig  ## footfall bob while it walks

	## Broad torso + slight hunch.
	var body := _box_in(rig, Vector3(0.66, 0.70, 0.40), leather, Vector3(0, 1.05, 0), Vector3(6, 0, 0))
	body_mat = body.material_override as StandardMaterial3D
	_box_in(rig, Vector3(0.72, 0.20, 0.44), skin_dark, Vector3(0, 1.42, 0.02))   ## shoulders
	## Head with a heavy jaw + tusks.
	_box_in(rig, Vector3(0.30, 0.30, 0.30), skin, Vector3(0, 1.66, -0.02))
	_box_in(rig, Vector3(0.05, 0.08, 0.05), Color(0.85, 0.82, 0.7), Vector3(-0.08, 1.55, -0.17), Vector3(-14, 0, 0))
	_box_in(rig, Vector3(0.05, 0.08, 0.05), Color(0.85, 0.82, 0.7), Vector3(0.08, 1.55, -0.17), Vector3(-14, 0, 0))
	## Left arm — shoulder pivot, swings with the stride.
	var larm := Node3D.new()
	rig.add_child(larm)
	larm.position = Vector3(-0.40, 1.41, 0)
	_box_in(larm, Vector3(0.16, 0.62, 0.16), skin, Vector3(0, -0.31, 0))
	walk_arms.append(larm)
	## Right arm: a SHOULDER pivot carrying the upper arm, and an elbow pivot
	## (`hand`) carrying the sword. Two joints, so he can hold the blade down at
	## his side like a person and still chamber it over the shoulder to cut.
	arm = Node3D.new()
	rig.add_child(arm)
	arm.position = Vector3(0.40, 1.38, 0)
	_box_in(arm, Vector3(0.17, 0.60, 0.17), skin, Vector3(0, -0.28, 0))
	hand = Node3D.new()
	arm.add_child(hand)
	hand.position = Vector3(0, -0.56, 0)
	_box_in(hand, Vector3(0.19, 0.19, 0.19), skin_dark, Vector3(0, -0.04, 0))                      ## fist
	_box_in(hand, Vector3(0.07, 0.07, 0.07), Color(0.30, 0.22, 0.12), Vector3(0, 0.06, 0))         ## pommel
	_box_in(hand, Vector3(0.28, 0.06, 0.08), Color(0.30, 0.22, 0.12), Vector3(0, -0.15, 0))        ## crossguard
	_box_in(hand, Vector3(0.09, 0.80, 0.06), steel, Vector3(0, -0.57, 0), Vector3.ZERO, true)      ## blade
	arm.rotation_degrees = CARRY_ARM
	hand.rotation_degrees = CARRY_HAND
	## Legs: hip pivots that actually stride.
	for lx: float in [-0.16, 0.16]:
		var leg := Node3D.new()
		rig.add_child(leg)
		leg.position = Vector3(lx, 0.66, 0)
		_box_in(leg, Vector3(0.22, 0.62, 0.22), skin_dark, Vector3(0, -0.31, 0))
		walk_legs.append(leg)

	_add_eye(Vector3(-0.08, 1.70, -0.17), Vector3(0.05, 0.04, 0.04), rig)
	_add_eye(Vector3(0.08, 1.70, -0.17), Vector3(0.05, 0.04, 0.04), rig)
