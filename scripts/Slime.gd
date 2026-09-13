extends Enemy
class_name Slime
## ============================================================================
## SLIMES — the bouncing jellies. (Lemon, 2026-09-13)
##
## THE RULE, and every colour obeys it: a slime hurts you by BOUNCING INTO
## you. It hops closer, COILS (squashes flat and glows — that is the tell),
## LEAPS on a ballistic arc aimed at your chest, and if the arc finds you the
## contact IS the hit: it recoils straight back off your body and sits there
## for a couple of seconds, jiggling, spent — RECOUPING. That is the window.
## Miss, and it still has to gather itself, just for less time.
##
## Nine colours, nine personalities, ONE script. Everything that differs is a
## row in KINDS — the body, the hop, the leap, the recoup, the ability — so a
## new colour is a row here plus a five-line subclass (scripts/SlimeGreen.gd
## and friends exist only because the M menu and the bestiary spawn by
## class: `cls.new()`). Never branch on colour in the AI below; add a field.
##
##   green   Green Slime   the common one; dopey, lazy hops, SPLITS in two
##   blue    Blue Slime    lobs itself in high arcs; SOAKS you (wet — cold
##                         later — but it also puts you out if you burn)
##   red     Ember Slime   fast skipping hops, sheds embers; sets you ALIGHT
##   yellow  Jolt Slime    THE skitterer: darts side to side at you in quick
##                         hops, then leaps; the touch SHOCKS (stun + stamina)
##   purple  Venom Slime   creeps flat and slow, longest tell, leaps from the
##                         farthest out; POISON that keeps ticking
##   black   Tar Slime     heavy brute: guard-breaking hurl, and you're GUMMED
##                         (slowed) after; nothing knocks it over
##   white   Rime Slime    shivers; the touch drains WARMTH and stiffens you
##   gold    Gilt Slime    never fights — bounds AWAY the moment it sees you;
##                         run it down and it's a purse
##   pink    Leech Slime   adores you: bounces off you and DRINKS the hit
##                         back as health
##
## Movement is HOPS, not steps: a CharacterBody3D that launches itself
## (velocity = dir * pace + UP * lift), flies on the base class's gravity,
## and splats on landing. The rig only ever changes SCALE (squash/stretch)
## and pitch — the skin (CreatureSkin) carries pivot scale into the bones, so
## the PSX mesh jiggles with it. Contact during a leap is a sphere test at
## the player's chest plus the slide collisions, so the bounce is never a
## ghost hit and never a miss through the capsule.
##
## Duck-typed on the player like every other creature: take_damage, and
## Afflictions.gd for the status effects (burn / poison / gummed / chill /
## shock / soak) — the LabPlayer in the tests answers the same surface.
## ============================================================================

## What a colour is. Every number the AI reads lives here.
const KINDS := {
	"green": {
		"name": "Green Slime",
		"flavor": "The common jelly. Hops at you like it has all day, and when it dies it just becomes two of the problem.",
		"col": Color(0.36, 0.86, 0.30), "core": Color(0.10, 0.40, 0.12), "alpha": 0.80,
		"size": 1.0, "hp": 34.0, "dmg": 6.0, "mass": 28.0,
		"aggro": 7.0, "leash": 18.0, "nerve": 0.0, "xp": 0,
		"hop_pace": 2.6, "hop_lift": 3.4, "hop_rest": 0.55, "zig": 0.0,
		"leap_min": 1.6, "leap_max": 5.5, "leap_lift": 4.2, "leap_pace": 9.0, "coil": 0.50,
		"recoup": 2.2, "recoup_miss": 0.9, "recoil": 5.5,
		"ability": "split", "wobble": 0.05, "wobble_rate": 3.2,
		"telegraph": Color(0.65, 1.0, 0.35), "strong": false, "throw": 0.0, "flee": false,
		"rout": "sloshes away",
	},
	"blue": {
		"name": "Blue Slime",
		"flavor": "Lobs itself in high, wet arcs. The splash soaks you through — a cold night will remember that — but it will put a burning coat out.",
		"col": Color(0.30, 0.55, 0.95), "core": Color(0.10, 0.20, 0.55), "alpha": 0.72,
		"size": 1.0, "hp": 38.0, "dmg": 6.0, "mass": 30.0,
		"aggro": 8.0, "leash": 18.0, "nerve": 0.30, "xp": 0,
		"hop_pace": 2.4, "hop_lift": 5.0, "hop_rest": 0.70, "zig": 0.0,
		"leap_min": 1.6, "leap_max": 6.0, "leap_lift": 5.6, "leap_pace": 9.5, "coil": 0.55,
		"recoup": 2.0, "recoup_miss": 0.9, "recoil": 5.0,
		"ability": "soak", "wobble": 0.07, "wobble_rate": 2.4,
		"telegraph": Color(0.55, 0.80, 1.0), "strong": false, "throw": 0.0, "flee": false,
		"rout": "sloshes off, dripping",
	},
	"red": {
		"name": "Ember Slime",
		"flavor": "Skips at you low and fast, spitting sparks. The bounce lights you up — and it keeps burning after the jelly has backed off.",
		"col": Color(0.95, 0.30, 0.12), "core": Color(1.0, 0.72, 0.20), "alpha": 0.84,
		"size": 0.95, "hp": 40.0, "dmg": 8.0, "mass": 30.0,
		"aggro": 12.0, "leash": 22.0, "nerve": 0.0, "xp": 1,
		"hop_pace": 3.4, "hop_lift": 2.6, "hop_rest": 0.22, "zig": 0.0,
		"leap_min": 1.5, "leap_max": 5.0, "leap_lift": 3.8, "leap_pace": 10.0, "coil": 0.38,
		"recoup": 1.4, "recoup_miss": 0.7, "recoil": 6.0,
		"ability": "burn", "wobble": 0.04, "wobble_rate": 7.0,
		"telegraph": Color(1.0, 0.55, 0.15), "strong": false, "throw": 0.0, "flee": false,
		"rout": "gutters and flees",
	},
	"yellow": {
		"name": "Jolt Slime",
		"flavor": "Never comes straight at you. It skitters left, right, left in quick hops — then it's on you, and the touch locks your legs.",
		"col": Color(0.98, 0.88, 0.22), "core": Color(1.0, 1.0, 0.85), "alpha": 0.82,
		"size": 0.85, "hp": 26.0, "dmg": 5.0, "mass": 22.0,
		"aggro": 13.0, "leash": 24.0, "nerve": 0.0, "xp": 1,
		"hop_pace": 3.8, "hop_lift": 2.4, "hop_rest": 0.16, "zig": 62.0,
		"leap_min": 1.5, "leap_max": 4.5, "leap_lift": 3.6, "leap_pace": 11.0, "coil": 0.28,
		"recoup": 1.0, "recoup_miss": 0.5, "recoil": 6.5,
		"ability": "shock", "wobble": 0.03, "wobble_rate": 13.0,
		"telegraph": Color(1.0, 1.0, 0.55), "strong": false, "throw": 0.0, "flee": false,
		"rout": "skitters off",
	},
	"purple": {
		"name": "Venom Slime",
		"flavor": "Creeps flat along the ground, patient as rot. The longest tell in the cave — and the longest leap. What it leaves in you keeps working.",
		"col": Color(0.58, 0.28, 0.85), "core": Color(0.25, 0.05, 0.40), "alpha": 0.80,
		"size": 1.05, "hp": 48.0, "dmg": 7.0, "mass": 34.0,
		"aggro": 11.0, "leash": 20.0, "nerve": 0.0, "xp": 1,
		"hop_pace": 1.6, "hop_lift": 1.8, "hop_rest": 1.10, "zig": 0.0,
		"leap_min": 2.5, "leap_max": 8.0, "leap_lift": 5.0, "leap_pace": 12.0, "coil": 0.85,
		"recoup": 3.0, "recoup_miss": 1.2, "recoil": 5.0,
		"ability": "poison", "wobble": 0.03, "wobble_rate": 1.6,
		"telegraph": Color(0.85, 0.45, 1.0), "strong": false, "throw": 0.0, "flee": false,
		"rout": "oozes away",
	},
	"black": {
		"name": "Tar Slime",
		"flavor": "Pitch with a pulse. Slow, and it does not care about your shield — the hit throws you, and you come up gummed and slow while it gathers itself.",
		"col": Color(0.10, 0.09, 0.11), "core": Color(0.35, 0.12, 0.05), "alpha": 0.94,
		"size": 1.35, "hp": 120.0, "dmg": 14.0, "mass": 110.0,
		"aggro": 8.0, "leash": 14.0, "nerve": 0.0, "xp": 2,
		"hop_pace": 2.0, "hop_lift": 3.8, "hop_rest": 1.20, "zig": 0.0,
		"leap_min": 1.8, "leap_max": 5.0, "leap_lift": 4.4, "leap_pace": 8.0, "coil": 0.75,
		"recoup": 2.8, "recoup_miss": 1.3, "recoil": 3.5,
		"ability": "gummed", "wobble": 0.015, "wobble_rate": 1.1,
		"telegraph": Color(0.95, 0.35, 0.10), "strong": true, "throw": 6.0, "flee": false,
		"rout": "never runs",
	},
	"white": {
		"name": "Rime Slime",
		"flavor": "Shivers even when it's still. The touch pulls the warmth straight out of you, and cold limbs are slow limbs.",
		"col": Color(0.88, 0.95, 1.0), "core": Color(0.55, 0.80, 1.0), "alpha": 0.78,
		"size": 1.0, "hp": 38.0, "dmg": 6.0, "mass": 30.0,
		"aggro": 9.0, "leash": 18.0, "nerve": 0.0, "xp": 1,
		"hop_pace": 2.6, "hop_lift": 3.2, "hop_rest": 0.50, "zig": 0.0,
		"leap_min": 1.6, "leap_max": 5.5, "leap_lift": 4.2, "leap_pace": 9.0, "coil": 0.50,
		"recoup": 2.0, "recoup_miss": 0.9, "recoil": 5.5,
		"ability": "chill", "wobble": 0.02, "wobble_rate": 22.0,
		"telegraph": Color(0.75, 0.92, 1.0), "strong": false, "throw": 0.0, "flee": false,
		"rout": "shivers away",
	},
	"gold": {
		"name": "Gilt Slime",
		"flavor": "It has never hurt anyone. It sees you and bounds for the tree line in great glittering leaps — and if you catch it, it was carrying a purse.",
		"col": Color(1.0, 0.82, 0.25), "core": Color(1.0, 0.95, 0.60), "alpha": 0.88,
		"size": 0.9, "hp": 30.0, "dmg": 0.0, "mass": 26.0,
		"aggro": 12.0, "leash": 34.0, "nerve": 0.0, "xp": 2,
		"hop_pace": 5.2, "hop_lift": 4.4, "hop_rest": 0.30, "zig": 18.0,
		"leap_min": 0.0, "leap_max": 0.0, "leap_lift": 0.0, "leap_pace": 0.0, "coil": 0.0,
		"recoup": 0.0, "recoup_miss": 0.0, "recoil": 0.0,
		"ability": "purse", "wobble": 0.04, "wobble_rate": 5.0,
		"telegraph": Color(1.0, 0.9, 0.4), "strong": false, "throw": 0.0, "flee": true,
		"rout": "bounds away",
	},
	"pink": {
		"name": "Leech Slime",
		"flavor": "Adores you. Bounces off you as eagerly as a dog, and every bounce drinks a little of you back into itself.",
		"col": Color(1.0, 0.50, 0.70), "core": Color(0.85, 0.15, 0.35), "alpha": 0.80,
		"size": 0.95, "hp": 36.0, "dmg": 5.0, "mass": 28.0,
		"aggro": 10.0, "leash": 20.0, "nerve": 0.0, "xp": 0,
		"hop_pace": 3.0, "hop_lift": 3.2, "hop_rest": 0.30, "zig": 0.0,
		"leap_min": 1.4, "leap_max": 4.5, "leap_lift": 3.8, "leap_pace": 9.5, "coil": 0.40,
		"recoup": 1.2, "recoup_miss": 0.6, "recoil": 5.0,
		"ability": "leech", "wobble": 0.06, "wobble_rate": 4.5,
		"telegraph": Color(1.0, 0.65, 0.80), "strong": false, "throw": 0.0, "flee": false,
		"rout": "flops away, heartbroken",
	},
}

## The colours in menu / bestiary order.
const ORDER := ["green", "blue", "red", "yellow", "purple", "black", "white", "gold", "pink"]

## Ability numbers. Named so the tests and the doc can quote them.
const BURN_SECONDS := 4.0
const BURN_DPS := 3.0
const POISON_SECONDS := 8.0
const POISON_DPS := 1.4
const GUMMED_SECONDS := 4.0
const GUMMED_MULT := 0.50
const CHILL_SECONDS := 3.0
const CHILL_MULT := 0.80
const CHILL_WARMTH := 14.0
const SHOCK_STUN := 0.55
const SHOCK_STAMINA := 30.0
const SOAK_WET := 0.55
const LEECH_MULT := 2.0        ## health drunk back per point of damage
const SPLIT_MIN_SIZE := 0.9    ## only a full-grown green splits
const SPLIT_SIZE := 0.58
const SPLIT_HP := 0.45
const PURSE_COINS := Vector2i(12, 20)
const HIT_REACH := 0.55        ## contact sphere = body radius + this
const LAND_SQUASH := 1.0       ## landing splat strength (scaled by fall speed)

var kind := "green"
var k: Dictionary = KINDS["green"]
var size_k := 1.0          ## body scale (splits shrink it)
var goo_color := Color(0.36, 0.86, 0.30)   ## HitFX reads this for the splat

## --- the hop machine ---
## phase: "rest" (on the ground between hops) | "air" (a plain hop in flight)
##        | "coil" (winding up the leap) | "leap" (the attack, in flight)
##        | "recoil" (bounced off you, flying back) | "recoup" (spent)
var phase := "rest"
var hop_cd := 0.0            ## rest left before the next hop
var _coil_t := 0.0
var _leap_t := 0.0           ## how long the leap has been in the air
var leap_hit := false        ## this leap found you
var _recoup_t := 0.0
var _zig := 1.0              ## which way the next zig-zag hop goes
var _hop_dir := Vector3.ZERO
var _was_air := false
var _land_t := 99.0          ## seconds since the last landing (drives the splat)
var _land_k := 0.0           ## how hard it landed
var _alert_t := 0.0          ## the "!" stretch when it first spots you
var _wob_t := randf() * TAU
var _leech_glow := 0.0
var hops := 0                ## plain hops taken (tests count them)
var leaps := 0               ## leaps launched
var bounces := 0             ## leaps that found you
var rig: Node3D
var core: MeshInstance3D
var _core_mat: StandardMaterial3D
var _flee_t := 0.0


## ------------------------------------------------------------- setup -----

func _init() -> void:
	set_kind(kind)


func set_kind(id: String) -> void:
	## Apply a colour's row to the sheet. Subclasses call this from _init so
	## the bestiary (which reads a throwaway `cls.new()`) sees the numbers.
	if not KINDS.has(id):
		id = "green"
	kind = id
	k = KINDS[id]
	display_name = String(k["name"])
	goo_color = k["col"]
	max_health = float(k["hp"]) * size_k
	health = max_health
	attack_damage = float(k["dmg"])
	strong_damage = attack_damage   ## the bestiary shows one number for us
	mass = float(k["mass"]) * size_k
	aggro_radius = float(k["aggro"])
	leash_radius = float(k["leash"])
	nerve = float(k["nerve"])
	rout_speed = 0.7
	rout_line = String(k["rout"])
	xp_tier = int(k["xp"])
	telegraph_color = k["telegraph"]
	families = ["slime"]
	monster = true            ## a jelly hunts you because that is what it is
	can_climb = false         ## it has no hands; it has no anything
	skin_tile = "flat"        ## smooth jelly — no fur, no scales
	wander_speed = 1.0
	chase_speed = float(k["hop_pace"])   ## locomotion amplitude reference
	attack_range = 0.0        ## never a standing bite: the leap IS the attack
	strong_cooldown = 0.0


func _ready() -> void:
	super()
	add_to_group("slimes")


func _build_body() -> void:
	var s := float(k["size"]) * size_k
	_add_collision(Vector3(0.62 * s, 0.56 * s, 0.62 * s), Vector3(0, 0.30 * s, 0))
	rig = Node3D.new()
	add_child(rig)
	rig.position = Vector3(0, 0.02, 0)
	base_body_color = k["col"]
	## The jelly: one soft box the skin rounds into a blob (superellipse
	## rings), dithered translucent so the core shows through it.
	var body := _box_in(rig, Vector3(0.72 * s, 0.58 * s, 0.72 * s), base_body_color, Vector3(0, 0.30 * s, 0))
	body_mat = body.material_override as StandardMaterial3D
	body_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body_mat.albedo_color.a = float(k["alpha"])
	base_body_color.a = float(k["alpha"])
	## A droplet crown so the silhouette reads as a blob, not a cube.
	var crown := _box_in(rig, Vector3(0.42 * s, 0.22 * s, 0.42 * s), base_body_color, Vector3(0, 0.60 * s, 0))
	var cm := crown.material_override as StandardMaterial3D
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.albedo_color.a = float(k["alpha"])
	## The core: what it is made of, glowing faintly through the jelly.
	core = _box_in(rig, Vector3(0.24 * s, 0.22 * s, 0.24 * s), k["core"], Vector3(0, 0.28 * s, 0))
	_core_mat = core.material_override as StandardMaterial3D
	_core_mat.emission_enabled = true
	_core_mat.emission = k["core"]
	_core_mat.emission_energy_multiplier = 0.9
	## Two beady eyes near the front (mobs face -z).
	_add_eye(Vector3(-0.13 * s, 0.40 * s, -0.33 * s), Vector3(0.07 * s, 0.07 * s, 0.05 * s), rig)
	_add_eye(Vector3(0.13 * s, 0.40 * s, -0.33 * s), Vector3(0.07 * s, 0.07 * s, 0.05 * s), rig)
	loco_root = null   ## we own the bob — the hop is the gait


func _skin_opts() -> Dictionary:
	return {"tile": skin_tile, "mass": mass, "tile_world": 0.5}


## -------------------------------------------------------------- brain ----

func _set_agitated(on: bool) -> void:
	var was := state == State.AGITATED
	super(on)
	if on and not was:
		_alert_t = 0.45   ## the startled stretch: it saw you
		hop_cd = minf(hop_cd, 0.25)
	if not on:
		phase = "rest" if is_on_floor() else "air"
		_coil_t = 0.0
		_recoup_t = 0.0


func _pick_wander() -> void:
	## Calm: an idle jelly mostly sits; now and then it hops off somewhere.
	wander_timer = randf_range(1.0, 2.5) if confused else randf_range(2.5, 6.0)
	if randf() < 0.55:
		wander_dir = Vector3.ZERO
	else:
		var a := randf() * TAU
		wander_dir = Vector3(cos(a), 0, sin(a))


func _do_wander(delta: float) -> void:
	wander_timer -= delta
	if wander_timer <= 0.0:
		_pick_wander()
	_ground_tick(delta)
	if not is_on_floor():
		return
	hop_cd -= delta
	if wander_dir != Vector3.ZERO and hop_cd <= 0.0:
		_hop(wander_dir, float(k["hop_pace"]) * 0.55, float(k["hop_lift"]) * 0.8)
		hop_cd = float(k["hop_rest"]) + randf_range(0.6, 1.4)
		_face(wander_dir, delta, 6.0)


func _do_combat(delta: float, player: Node3D, to_p: Vector3, dist: float) -> void:
	## The whole attack loop. No standing melee, no strong-attack machinery —
	## a slime has exactly one move and this is it.
	if player == null:
		return
	var dir := to_p.normalized() if dist > 0.05 else -global_transform.basis.z
	_ground_tick(delta)

	if bool(k["flee"]):
		_do_flee(delta, player, dir, dist)
		return

	match phase:
		"recoup":
			## Spent. Sits where it bounced to, jiggling, and only turns to
			## keep its eyes on you. THIS is when you hit it.
			_recoup_t -= delta
			_settle(delta)
			_face(dir, delta, 4.0)
			if _recoup_t <= 0.0:
				phase = "rest"
				hop_cd = 0.15
		"coil":
			## Winding up: flattening, glowing. Rooted. Dodge now.
			_coil_t -= delta
			_settle(delta, 14.0)
			_face(dir, delta, 10.0)
			if _coil_t <= 0.0:
				if _target_down(player) or not _can_hit(player):
					phase = "rest"   ## they went down (or behind rock) mid-coil: hold
					hop_cd = 0.4
					_set_telegraph_glow(false)
				else:
					_launch_leap(player, dir, dist)
		"leap":
			## In the air, on the line. Contact = the hit + the bounce.
			_leap_t += delta
			if not leap_hit and _touching(player):
				_bounce(player, dir)
			elif _leap_t > 2.5:
				## An arc that never came down (fell off a ledge, got stuck):
				## call it a miss so it can't fly forever.
				phase = "recoup"
				_recoup_t = float(k["recoup_miss"])
		"recoil":
			pass   ## flying back off you; the landing decides what's next
		"air":
			pass   ## a plain hop in flight
		_:
			## "rest": on the ground and ready. Leap if you're in the band,
			## else close the gap one hop at a time.
			if not is_on_floor():
				return
			_settle(delta, 10.0)
			_face(dir, delta, 9.0)
			if hop_cd > 0.0:
				hop_cd -= delta
				return
			if dist >= float(k["leap_min"]) and dist <= float(k["leap_max"]) \
					and _can_hit(player) and not _target_down(player):
				phase = "coil"
				_coil_t = float(k["coil"])
				_set_telegraph_glow(true)
				velocity.x = 0.0
				velocity.z = 0.0
				return
			## Approach hop. Zig-zag colours skitter off the line and back.
			var hd := dir
			var zig := float(k["zig"])
			if zig > 0.0:
				hd = dir.rotated(Vector3.UP, deg_to_rad(zig) * _zig)
				_zig = -_zig
			elif dist < float(k["leap_min"]):
				## Too close to leap (it landed on your boots): a short hop
				## back to a distance it can come at you from.
				hd = -dir
			_hop(hd, float(k["hop_pace"]), float(k["hop_lift"]))
			hop_cd = float(k["hop_rest"])


func _do_flee(delta: float, _player: Node3D, dir: Vector3, dist: float) -> void:
	## The gilt slime's whole personality: it saw you, and it is LEAVING, in
	## bounds, with a little jink so an arrow has to guess.
	_flee_t += delta
	if not is_on_floor():
		return
	_settle(delta, 10.0)
	if hop_cd > 0.0:
		hop_cd -= delta
		return
	var away := -dir.rotated(Vector3.UP, deg_to_rad(float(k["zig"])) * _zig * randf())
	_zig = -_zig
	_face(away, delta, 12.0)
	var pace := float(k["hop_pace"]) * (1.0 if dist < 14.0 else 0.7)
	_hop(away, pace, float(k["hop_lift"]))
	hop_cd = float(k["hop_rest"])


## --------------------------------------------------------- the moves -----

func _hop(dir: Vector3, pace: float, lift: float) -> void:
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = -global_transform.basis.z
	dir = dir.normalized()
	_hop_dir = dir
	velocity = dir * pace + Vector3.UP * lift
	phase = "air"
	hops += 1
	_land_t = 99.0


func _launch_leap(player: Node3D, dir: Vector3, dist: float) -> void:
	## Aim the arc AT them: lift is the colour's, pace is whatever lands the
	## jelly on the player's position (capped at the colour's leap_pace so a
	## far leap arrives fast, not impossibly fast). A ballistic arc under
	## the base class's gravity: air time = 2 * lift / g.
	var lift := float(k["leap_lift"])
	var air := 2.0 * lift / maxf(gravity, 0.1)
	var pace := clampf(dist / maxf(air, 0.05), 2.0, float(k["leap_pace"]))
	## a moving target: lead them a touch by their own velocity
	if "velocity" in player:
		var pv: Vector3 = player.velocity
		pv.y = 0.0
		var lead := pv * air * 0.5
		var aim := (player.global_position + lead) - global_position
		aim.y = 0.0
		if aim.length() > 0.2:
			dir = aim.normalized()
			pace = clampf(aim.length() / maxf(air, 0.05), 2.0, float(k["leap_pace"]))
	velocity = dir * pace + Vector3.UP * lift
	_hop_dir = dir
	phase = "leap"
	_leap_t = 0.0
	leap_hit = false
	leaps += 1
	_land_t = 99.0
	_set_telegraph_glow(false)
	_burst(global_position + Vector3.UP * 0.2, Vector3.UP, 0.5)


func _touching(player: Node3D) -> bool:
	## Contact = our centre inside a sphere on the player's chest, OR the
	## physics already pushed us into them this step.
	var r := float(k["size"]) * size_k * 0.36 + HIT_REACH
	var chest: Vector3 = player.global_position + Vector3.UP * 0.9
	var me := global_position + Vector3.UP * 0.3 * float(k["size"]) * size_k
	if me.distance_to(chest) <= r:
		return true
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_collider() == player:
			return true
	return false


func _bounce(player: Node3D, dir: Vector3) -> void:
	## THE HIT. Damage on contact, then straight back off their body — up and
	## away on the line it came in on — and it lands spent.
	leap_hit = true
	bounces += 1
	var away := global_position - player.global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.05 else -dir
	var throw := Vector3.INF
	if float(k["throw"]) > 0.0:
		throw = -away * float(k["throw"])
	if player.has_method("take_damage") and attack_damage > 0.0:
		player.take_damage(attack_damage, global_position, bool(k["strong"]), throw, self)
	_ability_on_contact(player)
	velocity = away * float(k["recoil"]) + Vector3.UP * (float(k["recoil"]) * 0.55)
	phase = "recoil"
	_burst(global_position + Vector3.UP * 0.4, away, 1.0)


func _ability_on_contact(player: Node3D) -> void:
	match String(k["ability"]):
		"burn":
			Afflictions.apply(player, "burn", BURN_SECONDS, BURN_DPS)
		"poison":
			Afflictions.apply(player, "poison", POISON_SECONDS, POISON_DPS)
		"gummed":
			Afflictions.apply(player, "gummed", GUMMED_SECONDS, GUMMED_MULT)
		"chill":
			Afflictions.apply(player, "chill", CHILL_SECONDS, CHILL_MULT)
			Afflictions.drain_warmth(player, CHILL_WARMTH)
		"shock":
			Afflictions.shock(player, SHOCK_STUN, SHOCK_STAMINA)
		"soak":
			Afflictions.soak(player, SOAK_WET)
		"leech":
			health = minf(max_health, health + attack_damage * LEECH_MULT)
			_leech_glow = 0.6


func _ground_tick(delta: float) -> void:
	## Landings. Runs every combat/wander frame: notices the floor arriving,
	## squashes, and moves the phase machine on.
	var on := is_on_floor()
	_land_t += delta
	if on and _was_air:
		_land_k = clampf(absf(velocity.y) / 6.0 + 0.35, 0.4, 1.4) * LAND_SQUASH
		_land_t = 0.0
		_on_land()
	elif on and (phase == "rest" or phase == "recoup" or phase == "coil"):
		## friction on the ground: a jelly does not slide (a fresh hop is
		## still "on the floor" for the frame it launches — leave it alone)
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
	_was_air = not on


func _on_land() -> void:
	match phase:
		"leap":
			## Came down without finding you: gather, briefly.
			phase = "recoup"
			_recoup_t = float(k["recoup_miss"])
		"recoil":
			## Bounced off you and landed: the long sit.
			phase = "recoup"
			_recoup_t = float(k["recoup"])
		"air":
			phase = "rest"
	velocity.x *= 0.15
	velocity.z *= 0.15
	_land_fx()


func _settle(delta: float, rate := 10.0) -> void:
	velocity.x = move_toward(velocity.x, 0.0, rate * delta)
	velocity.z = move_toward(velocity.z, 0.0, rate * delta)


func _land_fx() -> void:
	match String(k["ability"]):
		"burn":
			_burst(global_position + Vector3.UP * 0.1, Vector3.UP, 0.4)
		"chill":
			_burst(global_position + Vector3.UP * 0.1, Vector3.UP, 0.4)
		"gummed":
			## the thump: a nearby player feels the tar land
			var p := _get_player()
			if p != null and "cam_shake" in p and p.global_position.distance_to(global_position) < 7.0:
				p.set("cam_shake", maxf(float(p.get("cam_shake")), 0.10))


func _burst(at: Vector3, dir: Vector3, power: float) -> void:
	## A few goo cubes in the colour's own light. HitFX does the real splat
	## when a blade lands; this is the little one for landings and launches.
	var parent := get_parent()
	if parent == null or not is_inside_tree():
		return
	var fx := HitFX.goo(at, dir, goo_color, power)
	if fx != null:
		parent.add_child(fx)


## ------------------------------------------------------------ the look ---

func _animate(delta: float) -> void:
	if rig == null:
		return
	var s := float(k["size"]) * size_k
	_wob_t += delta * float(k["wobble_rate"])
	var wob := float(k["wobble"])
	var sx := 1.0
	var sy := 1.0
	var pitch := 0.0
	if not is_on_floor():
		## Stretched along the flight, nose pitched with the arc.
		var vy := velocity.y
		var st := clampf(absf(vy) * 0.06 + Vector2(velocity.x, velocity.z).length() * 0.02, 0.0, 0.42)
		sy = 1.0 + st
		sx = 1.0 - st * 0.45
		pitch = clampf(vy * 5.0, -30.0, 30.0)
		if phase == "leap":
			sy += 0.12
			sx -= 0.05
	elif phase == "coil":
		## Flattening into the ground, ready to go.
		var p := 1.0 - clampf(_coil_t / maxf(float(k["coil"]), 0.01), 0.0, 1.0)
		sy = 1.0 - 0.48 * p + sin(_wob_t * 3.0) * 0.03 * p
		sx = 1.0 + 0.36 * p
	else:
		## Grounded. The landing splat rings down (a damped bounce), the idle
		## wobble rides under it, and a recouping jelly heaves, spent.
		var splat := 0.0
		if _land_t < 0.9:
			splat = exp(-_land_t * 5.5) * cos(_land_t * 15.0) * 0.55 * _land_k
		var idle := sin(_wob_t) * wob
		var heave := 0.0
		if phase == "recoup":
			heave = sin(_wob_t * 0.55) * 0.09 + 0.04
		sy = 1.0 - splat - idle - heave
		sx = 1.0 + splat * 0.7 + idle + heave * 0.6
		if _alert_t > 0.0:
			_alert_t -= delta
			var a := sin(clampf(_alert_t / 0.45, 0.0, 1.0) * PI)
			sy += 0.35 * a
			sx -= 0.14 * a
	rig.scale = Vector3(sx, sy, sx) * s
	rig.rotation_degrees = rig.rotation_degrees.lerp(Vector3(pitch, 0.0, 0.0), clampf(delta * 12.0, 0.0, 1.0))
	## the core breathes; red flickers; pink flushes after a drink
	if _core_mat != null:
		var e := 0.9 + 0.25 * sin(_wob_t * 0.9)
		match String(k["ability"]):
			"burn":
				e = 1.4 + randf() * 0.8
			"shock":
				e = 1.2 + (2.2 if randf() < 0.06 else 0.0)
			"leech":
				if _leech_glow > 0.0:
					_leech_glow -= delta
					e += _leech_glow * 4.0
		if phase == "recoup":
			e *= 0.55
		_core_mat.emission_energy_multiplier = e


## ------------------------------------------------------------- damage ----

func take_damage(amount: float, from_pos = null, strong = false, throw = null, attacker: Node = null) -> void:
	## A blade interrupts the coil and the recoup like anyone else's flinch;
	## a jelly in the air just keeps flying (the base zeroes velocity on a
	## flinch, which would hang it mid-arc).
	var airborne := not is_on_floor()
	var v := velocity
	super(amount, from_pos, strong, throw, attacker)
	if dying:
		return
	if phase == "coil":
		phase = "rest"
		_coil_t = 0.0
		hop_cd = 0.6
		_set_telegraph_glow(false)
	if airborne:
		velocity = v
		flinch_timer = minf(flinch_timer, 0.05)
	elif phase == "recoup":
		_recoup_t = maxf(_recoup_t, 0.6)   ## a hit while spent keeps it down a beat longer


func knockdown(fling: Vector3 = Vector3.ZERO, seconds := 2.4) -> void:
	## Tar does not go over. The others: a jelly has no bones to ragdoll —
	## a trample just flings it.
	if String(k["ability"]) == "gummed":
		return
	velocity = fling * 0.6 + Vector3.UP * 2.5
	phase = "air"
	hop_cd = seconds * 0.4
	_set_telegraph_glow(false)


func on_parried() -> void:
	## Turned aside mid-leap: it bounces off the shield instead of you.
	super()
	if phase == "leap":
		velocity = -_hop_dir * float(k["recoil"]) + Vector3.UP * 3.0
		phase = "recoil"
		leap_hit = true


func _die() -> void:
	## A jelly has no bones to fall over on and no body to leave: it SPLATS
	## — one big burst of its own goo, the essence out of the middle, gone.
	if dying:
		return
	if String(k["ability"]) == "split" and size_k >= SPLIT_MIN_SIZE and get_parent() != null:
		_split()
	dying = true
	velocity = Vector3.ZERO
	var slayer := _get_player()
	if slayer and slayer.has_method("on_mob_slain"):
		slayer.on_mob_slain(self)
	for c in get_children():
		if c is CollisionShape3D:
			c.set_deferred("disabled", true)
	_set_telegraph_glow(false)
	_burst(global_position + Vector3.UP * 0.3, Vector3.UP, 3.0)
	if skin != null:
		skin.visible = false
	for c in find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).visible = false
	var t := create_tween()
	t.tween_interval(0.15)
	t.tween_callback(_spawn_pickups)
	t.tween_interval(0.6)
	t.tween_callback(queue_free)


func _split() -> void:
	## Two half-jellies out of the corpse, already angry.
	for side: float in [-1.0, 1.0]:
		var child := Slime.new()
		child.size_k = SPLIT_SIZE
		child.set_kind(kind)
		child.max_health = float(k["hp"]) * SPLIT_HP
		child.health = child.max_health
		get_parent().add_child(child)
		child.global_position = global_position + Vector3(0.35 * side, 0.2, 0.0)
		child.velocity = Vector3(1.8 * side, 3.4, randf_range(-1.0, 1.0))
		child.phase = "air"
		child.provoked = true
		child._set_agitated(true)


func _spawn_pickups() -> void:
	super()
	if String(k["ability"]) != "purse":
		return
	## The gilt slime's purse: a shower of real coins.
	var parent := get_parent()
	if parent == null:
		return
	var origin := global_position + Vector3(0, 0.6, 0)
	for _i in range(randi_range(PURSE_COINS.x, PURSE_COINS.y)):
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


func _drops_coins() -> bool:
	return String(k["ability"]) == "purse"


## ------------------------------------------------------------- static ----

static func kind_for_zone(zone: String, night: bool, rng: RandomNumberGenerator) -> String:
	## Who lives where (SlimeDirector rolls this per pocket). Lakes are the
	## blue one's; the cold north is the rime one's; night lets the venom
	## and the tar out; gilt is the rare one everywhere.
	var table: Array = []
	match zone:
		"lake", "gulf", "beacon_coast", "dawnwatch":
			table = [["blue", 6], ["green", 3], ["pink", 1], ["yellow", 1]]
		"county", "katahdin", "moosehead":
			table = [["white", 6], ["green", 2], ["purple", 1], ["blue", 1]]
		"western_peaks":
			table = [["white", 3], ["green", 3], ["red", 2], ["yellow", 1]]
		"field", "freeport_road", "kennebec_seat", "bangor_gate":
			table = [["green", 6], ["yellow", 3], ["pink", 2], ["red", 1]]
		_:
			table = [["green", 5], ["purple", 2], ["yellow", 2], ["pink", 1], ["red", 1]]
	if night:
		table.append(["purple", 3])
		table.append(["black", 2])
	table.append(["gold", 1])
	var total := 0
	for row: Array in table:
		total += int(row[1])
	var pick := rng.randi_range(1, total)
	for row: Array in table:
		pick -= int(row[1])
		if pick <= 0:
			return String(row[0])
	return "green"


static func make(id: String) -> Slime:
	var s := Slime.new()
	s.set_kind(id)
	return s


static func flavor_of(display: String) -> String:
	## The bestiary's line for a colour, by display name ("" if not ours).
	for id in KINDS:
		if String(KINDS[id]["name"]) == display:
			return String(KINDS[id]["flavor"])
	return ""


static func kind_of_name(display: String) -> String:
	for id in KINDS:
		if String(KINDS[id]["name"]) == display:
			return String(id)
	return ""
