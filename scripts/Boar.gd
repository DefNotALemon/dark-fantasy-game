extends Enemy
class_name Boar
## Territorial passive mob. Ignores the player and grazes until they get close,
## then winds up and CHARGES. Strong attack: the charge (guard-breaks).

var rig: Node3D                 ## whole visible body (bobs, rolls, leans)
var legs: Array[Node3D] = []    ## hip pivots: FL, FR, BL, BR — they trot


func _init() -> void:
	display_name = "Boar"
	max_health = 70.0         ## fodder — goes down fairly quick
	wander_speed = 1.4
	chase_speed = 4.6
	attack_range = 2.0
	attack_damage = 12.0
	attack_cooldown = 1.2
	aggro_radius = 8.0
	leash_radius = 20.0
	xp_tier = 0
	families = ["beast"]
	## Circles the player in a big, sweeping arc, leaning hard into the turn.
	duelist = true
	duel_range = 11.0
	duel_lean = 1.1
	duel_hold_min = 1.6
	duel_hold_max = 3.2
	## Always on the move: keeps running through the windup, never stops to bite.
	## Charge -> hit -> barrel PAST -> swing wide -> back to circling.
	always_moving = true
	gait_rate = 1.1  ## quick little trotters
	strong_runpast = 0.55
	## Strong: the full-tilt charge from mid-range — knocks the player aside,
	## just hard enough to clear them off the tusks' path (no launching).
	strong_throws = true
	strong_throw_power = 5.0
	strong_damage = 22.0
	strong_speed = 12.0
	strong_windup_time = 0.5
	strong_duration = 0.55
	strong_cooldown = 2.6
	strong_min_range = 3.0
	strong_max_range = 7.0
	strong_hit_range = 2.0
	telegraph_color = Color(0.95, 0.10, 0.05)


func _xp_orb_value() -> int:
	## Starter prey: boar essence runs rich for young hunters. Until level 5
	## a boar kill pays 30 XP (3 orbs x 10) instead of 6 — hunt them to find
	## your feet, then the forest stops being generous.
	var pl := _get_player()
	if pl != null and "level" in pl and int(pl.level) < 5:
		return 10
	return super()


func _animate(delta: float) -> void:
	if rig == null:
		return
	## Trot: diagonal leg pairs (FL+BR / FR+BL) swing opposite each other on
	## the shared gait phase — quick feet in a charge, a lazy amble grazing.
	var swing := 0.55 * _loco_amount
	for i in range(legs.size()):
		var ph := 0.0 if (i == 0 or i == 3) else PI
		legs[i].rotation.x = sin(walk_t + ph) * swing
	## The body waddle-rolls a touch and drops its head into the charge.
	rig.rotation_degrees.z = sin(walk_t) * 2.2 * _loco_amount
	var lean := -9.0 if (strong_active or strong_windup > 0.0) else 0.0
	rig.rotation_degrees.x = lerpf(rig.rotation_degrees.x,
		lean + absf(sin(walk_t)) * 1.4 * _loco_amount, clampf(delta * 10.0, 0.0, 1.0))


func _build_body() -> void:
	## Collision (low and long, like a boar).
	_add_collision(Vector3(0.8, 0.9, 1.4), Vector3(0, 0.55, 0))

	rig = Node3D.new()
	add_child(rig)
	loco_root = rig  ## base locomotion bobs the whole body with each footfall

	var hide := Color(0.28, 0.20, 0.14)
	var dark := Color(0.18, 0.13, 0.09)
	var tusk := Color(0.85, 0.82, 0.70)
	base_body_color = hide

	## Main body (faces -z).
	var body := _box_in(rig, Vector3(0.7, 0.6, 1.2), hide, Vector3(0, 0.62, 0))
	body_mat = body.material_override as StandardMaterial3D
	## Shoulder hump.
	_box_in(rig, Vector3(0.6, 0.3, 0.5), dark, Vector3(0, 0.92, 0.2))
	## Head + snout at the front (-z).
	_box_in(rig, Vector3(0.42, 0.40, 0.40), hide, Vector3(0, 0.55, -0.75))
	_box_in(rig, Vector3(0.24, 0.22, 0.22), dark, Vector3(0, 0.48, -0.98))
	## Tusks.
	_box_in(rig, Vector3(0.05, 0.05, 0.18), tusk, Vector3(-0.12, 0.44, -1.02), Vector3(20, 0, 0))
	_box_in(rig, Vector3(0.05, 0.05, 0.18), tusk, Vector3(0.12, 0.44, -1.02), Vector3(20, 0, 0))
	## Ears.
	_box_in(rig, Vector3(0.10, 0.14, 0.05), dark, Vector3(-0.16, 0.78, -0.62))
	_box_in(rig, Vector3(0.10, 0.14, 0.05), dark, Vector3(0.16, 0.78, -0.62))
	## Legs: hip pivots so they can actually trot (FL, FR, BL, BR).
	for p: Vector3 in [Vector3(-0.26, 0.4, -0.42), Vector3(0.26, 0.4, -0.42), Vector3(-0.26, 0.4, 0.42), Vector3(0.26, 0.4, 0.42)]:
		var leg := Node3D.new()
		rig.add_child(leg)
		leg.position = p
		_box_in(leg, Vector3(0.16, 0.4, 0.16), dark, Vector3(0, -0.2, 0))
		legs.append(leg)
	## Tail.
	_box_in(rig, Vector3(0.05, 0.05, 0.22), dark, Vector3(0, 0.7, 0.66))

	## Eyes.
	_add_eye(Vector3(-0.13, 0.62, -0.93), Vector3(0.06, 0.06, 0.05), rig)
	_add_eye(Vector3(0.13, 0.62, -0.93), Vector3(0.06, 0.06, 0.05), rig)
