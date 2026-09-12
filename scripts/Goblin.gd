extends Enemy
class_name Goblin
## Fast, twitchy little raider. Hostile on sight, quick club whacks up close.
## Specials: "pounce" — crouches low (sickly green glow) then leaps across the
## gap, guard-breaking. "flurry" — three rapid club whacks at melee range,
## blockable but stamina-draining.

var rig: Node3D    ## whole visible body (crouches / stretches)
var arm: Node3D    ## right shoulder pivot holding the club


func _init() -> void:
	mass = 35.0
	skin_tile = "skin"
	display_name = "Goblin"
	monster = true           ## cave dweller — hunts you on Peaceful too
	max_health = 40.0        ## fragile fodder
	wander_speed = 1.8
	chase_speed = 5.0
	attack_range = 1.6
	attack_damage = 7.0
	attack_cooldown = 0.9
	aggro_radius = 10.0
	leash_radius = 22.0
	xp_tier = 1
	families = ["humanoid"]
	## Fights dirty, which includes knowing when to stop fighting.
	nerve = 0.32
	rout_speed = 0.58
	rout_line = "breaks and scrambles away"
	duelist = true   ## smart enough to pace and pick its moment
	## Pounce triggers from mid-range; the flurry comes out at melee range.
	strong_min_range = 2.5
	strong_max_range = 6.0
	strong_from_melee = true
	telegraph_color = Color(0.55, 0.95, 0.15)
	climb_speed = 3.2   ## a born raider — swarms up walls nearly as fast as a kobold


func _choose_strong(dist: float) -> void:
	if dist <= attack_range + 0.3:
		strong_mode = "flurry"  ## three fast whacks, blockable
		strong_damage = 5.0
		strong_speed = 1.5
		strong_windup_time = 0.30
		strong_duration = 0.75
		strong_cooldown = 5.0
		strong_hit_range = 1.8
		strong_breaks_guard = false
		strong_multi_hits = 3
		strong_hit_interval = 0.22
	else:
		strong_mode = "pounce"  ## the leaping guard-breaker
		strong_damage = 15.0
		strong_speed = 9.0
		strong_windup_time = 0.45
		strong_duration = 0.40
		strong_cooldown = 4.0
		strong_hit_range = 1.6
		strong_breaks_guard = true
		strong_multi_hits = 1


func _animate(delta: float) -> void:
	if arm == null:
		return
	if strong_windup > 0.0:
		var p := 1.0 - strong_windup / strong_windup_time
		if strong_mode == "pounce":
			## Coil down low, club dragged BACK behind it (negative x — the old
			## +40 stuck the club out front like a handshake).
			rig.position.y = lerpf(rig.position.y, -0.16 * p, delta * 14.0)
			rig.rotation_degrees = rig.rotation_degrees.lerp(Vector3(14.0 * p, 0, 0), delta * 14.0)
			arm.rotation_degrees = arm.rotation_degrees.lerp(Vector3(-40.0 * p, 0, 0), delta * 14.0)
		else:
			## Flurry windup: club raised, bouncing on its toes.
			arm.rotation_degrees = arm.rotation_degrees.lerp(Vector3(-80.0 * p, 0, 0), delta * 16.0)
		return
	if strong_active:
		var p := 1.0 - strong_time / strong_duration
		if strong_mode == "pounce":
			## Stretched out mid-leap, the club whipping over from cocked-back
			## to a forward-down smash as it lands on you.
			rig.position.y = lerpf(-0.16, 0.06, minf(p * 2.0, 1.0))
			rig.rotation_degrees = Vector3(lerpf(14.0, -10.0, p), 0, 0)
			arm.rotation_degrees = Vector3(lerpf(-40.0, 45.0, minf(p * 1.8, 1.0)), 0, 0)
		else:
			## Three rapid whacks: the club oscillates fast.
			arm.rotation_degrees = Vector3(-25.0 + sin(p * TAU * 1.5) * -55.0, 0, 0)
			rig.rotation_degrees = Vector3(6.0, sin(p * TAU * 1.5) * 10.0, 0)
		return
	if melee_anim > 0.0:
		## Quick whack: raise behind the head, then whip through so the club is
		## all the way FORWARD right on the damage frame (p≈0.62) — it used to
		## still be up behind the head when the hit landed.
		var p := 1.0 - melee_anim / MELEE_ANIM_TIME
		if p < 0.30:
			arm.rotation_degrees = arm.rotation_degrees.lerp(Vector3(-75, 0, 0), delta * 22.0)
		else:
			arm.rotation_degrees = Vector3(lerpf(-75.0, 35.0, minf((p - 0.30) / 0.32, 1.0)), 0, 0)
		return
	## Ease back to the rest pose — riding the footfall bob while it scampers
	## (the crouch poses above own rig.position.y during specials).
	rig.position.y = lerpf(rig.position.y, loco_bob_y, delta * 10.0)
	rig.rotation_degrees = rig.rotation_degrees.lerp(Vector3(0, 0, sin(walk_t) * 2.0 * _loco_amount), delta * 8.0)
	## Club arm pumps along with the scurry until an attack claims it.
	arm.rotation_degrees = arm.rotation_degrees.lerp(Vector3(sin(walk_t) * 8.0 * _loco_amount, 0, 0), delta * 8.0)


func _build_body() -> void:
	_add_collision(Vector3(0.5, 1.15, 0.45), Vector3(0, 0.6, 0))

	rig = Node3D.new()
	add_child(rig)
	## Gait: quick scampering steps.
	gait_rate = 1.25
	stride_deg = 34.0
	bob_h = 0.05

	var skin := Color(0.30, 0.45, 0.18)
	var rag := Color(0.32, 0.24, 0.16)
	var wood := Color(0.35, 0.24, 0.13)
	base_body_color = skin

	## Torso (ragged tunic).
	var body := _box_in(rig, Vector3(0.36, 0.40, 0.24), skin, Vector3(0, 0.72, 0))
	body_mat = body.material_override as StandardMaterial3D
	_box_in(rig, Vector3(0.38, 0.18, 0.26), rag, Vector3(0, 0.52, 0))
	## Big head with a long nose and huge ears.
	_box_in(rig, Vector3(0.28, 0.24, 0.26), skin, Vector3(0, 1.06, 0))
	_box_in(rig, Vector3(0.07, 0.06, 0.16), skin, Vector3(0, 1.02, -0.20))
	_box_in(rig, Vector3(0.05, 0.18, 0.12), skin, Vector3(-0.19, 1.10, 0.02), Vector3(0, 0, 18))
	_box_in(rig, Vector3(0.05, 0.18, 0.12), skin, Vector3(0.19, 1.10, 0.02), Vector3(0, 0, -18))
	## Left arm hangs loose — pivoted so it pumps with the scurry.
	var larm := Node3D.new()
	rig.add_child(larm)
	larm.position = Vector3(-0.24, 0.87, 0)
	_box_in(larm, Vector3(0.08, 0.38, 0.08), skin, Vector3(0, -0.19, 0))
	walk_arms.append(larm)
	## Right arm: a pivot at the shoulder so the club-arm can swing.
	arm = Node3D.new()
	rig.add_child(arm)
	arm.position = Vector3(0.24, 0.87, 0)
	_box_in(arm, Vector3(0.08, 0.38, 0.08), skin, Vector3(0, -0.19, 0))
	## Crude wooden club in the hand.
	_box_in(arm, Vector3(0.09, 0.09, 0.42), wood, Vector3(0.02, -0.37, -0.14), Vector3(12, 0, 0))
	_box_in(arm, Vector3(0.13, 0.13, 0.16), wood, Vector3(0.02, -0.34, -0.36))
	## Stubby legs: hip pivots that scurry.
	for lx: float in [-0.10, 0.10]:
		var leg := Node3D.new()
		rig.add_child(leg)
		leg.position = Vector3(lx, 0.42, 0)
		_box_in(leg, Vector3(0.11, 0.40, 0.11), rag, Vector3(0, -0.20, 0))
		walk_legs.append(leg)

	## Beady eyes.
	_add_eye(Vector3(-0.08, 1.09, -0.13), Vector3(0.05, 0.05, 0.04), rig)
	_add_eye(Vector3(0.08, 1.09, -0.13), Vector3(0.05, 0.05, 0.04), rig)
