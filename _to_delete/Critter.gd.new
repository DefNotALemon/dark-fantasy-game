class_name Critter
extends Enemy

## ===========================================================================
## WILDLIFE — one class, sixty-five animals.            docs/WILDLIFE.md §1
##
## A Critter is an Enemy that mostly does not want to fight you. It inherits
## the whole existing creature stack — collision, gravity, locomotion phase,
## damage, flinch, death, HitFX resolution, the infighting grudge — and
## replaces the COMBAT brain with an archetype brain. That reuse is the point:
## a deer bleeds through exactly the same code path as a goblin, so Settings ->
## Blood, the bestiary, the XP ledger and the weapon-material tables all work
## on wildlife the day it ships, with no second implementation to keep in sync.
##
## Everything a species IS lives in CritterDex. Everything it LOOKS like lives
## in CritterRig. Everything it DOES that is unique lives in CritterAnim. This
## file is only the brain and the plumbing between the three.
##
## Spawn one:   var c := Critter.make("moose");  c.position = p;  add_child(c)
## `species` MUST be set before entering the tree — Enemy._ready builds the
## body immediately, and a body with no species is a grey box.
## ===========================================================================

enum Arch { SKITTER, SENTINEL, BLUFFER, STALKER, RAIDER, ENGINEER, SCAVENGER, AMBIENT }

const ARCH_IDS := {
	"SKITTER": Arch.SKITTER, "SENTINEL": Arch.SENTINEL, "BLUFFER": Arch.BLUFFER,
	"STALKER": Arch.STALKER, "RAIDER": Arch.RAIDER, "ENGINEER": Arch.ENGINEER,
	"SCAVENGER": Arch.SCAVENGER, "AMBIENT": Arch.AMBIENT,
}

## Behaviour states. Deliberately NOT Enemy.State — a wild animal's inner life
## is not "calm / aggro", it is "how close is that and do I care yet".
enum Mood { EASY, ALERT, FLEE, WARN, CHARGE, HUNT, WORK, FEED, DOWN }

const ALERT_HOLD := 6.0          ## seconds of staring before it settles again
const FLEE_HOLD := 4.0           ## minimum commitment to a run
const WARN_HOLD := 2.6
const SIG_COOLDOWN := Vector2(4.0, 13.0)   ## idle signature cadence
const CALL_COOLDOWN := Vector2(14.0, 48.0)
## Buzz: the generic idle library (CritterAnim.buzz_for). Rolled far more
## often than a species signature — this is the layer that keeps a calm
## animal doing SOMETHING between its tells.
const BUZZ_COOLDOWN := Vector2(2.5, 8.0)
## ---------------------------------------------------- gated signatures ---
## Some moves are not free. A signature listed here needs at least this much
## of the animal's health before it will play, so a wounded one simply cannot
## do it any more — which is a real mechanic, not a cosmetic one: hurt a bear
## past a third and it can never buff itself again for the rest of the fight.
const SIG_HEALTH_GATE := {
	"bear_stand": 2.0 / 3.0,
}

## Signatures that PLANT the animal. While one of these runs it does not
## steer, chase, or attack — it is committed to the move, and so are you.
const SIG_ROOTS := {
	"bear_stand": true, "play_dead": true, "freeze_solid": true,
	"freeze_crouch": true, "statue_stalk": true, "log_drum": true,
	"strut_drum": true, "banana_pose": true, "quill_bristle": true,
}

## Finishing one of these, all the way back to the ground, pays out.
## {attack multiplier, damage-taken multiplier, seconds}
const SIG_PAYOFF := {
	"bear_stand": {"atk": 1.55, "def": 0.65, "time": 18.0},
}

const QUILL_DAMAGE := 9.0
const SPRAY_RANGE := 6.0
const SPRAY_SECONDS := 22.0
const LATCH_SECONDS := 4.5

## --------------------------------------------------------------- identity ---
var species := "hare"
var profile: Dictionary = {}
var arch: int = Arch.SKITTER
var rig: Dictionary = {}

## ------------------------------------------------------------- behaviour ---
var mood: int = Mood.EASY
var mood_t := 0.0
var _alarm_cool := 0.0           ## Telegraph reads this before choosing a relay
var _sig := ""                   ## signature animation currently playing
var _sig_t := 0.0
var _sig_len := 1.0
var _sig_cool := 3.0
var _buzz_cool := 2.0
var _call_cool := 6.0
var _breathe := 0.0
var _threat_pos := Vector3.ZERO
var _flee_dir := Vector3.ZERO
var _home := Vector3.ZERO        ## territory anchor — nothing wanders forever
var home_radius := 30.0
var _bluff_count := 0            ## how many warnings it has already given you
var bold := 2                    ## warnings a BLUFFER gives before it commits
var relentless := false          ## never routs, never disengages — see the bear
## The payoff for finishing a gated move. Both multipliers, and the clock.
var buff_t := 0.0
var buff_atk := 1.0
var buff_def := 1.0
var _buff_cool := 0.0            ## no chain-buffing between charges
var _prey: Node3D = null         ## STALKER's current mark
var _target_pos := Vector3.ZERO  ## RAIDER / ENGINEER work site
var _work_t := 0.0

## --------------------------------------------------------------- seasons ---
var _coat := 0.0                 ## 0 = summer coat, 1 = winter white
var _base_cols: Array = []       ## every material's original albedo, for swaps
var _season := 0
var _night := false

## --------------------------------------------------------------- specials ---
var _spray_cool := 0.0
var _latched: Node3D = null
var _latch_t := 0.0
var _playing_dead := false

## ------------------------------------------------------------ bookkeeping ---
var _zone := "deep_woods"        ## set by the director; used for calls + save
var legend := false
## Health carried across a load. Enemy._ready sets health = max_health, so a
## wounded animal restored from a save would come back healed — from_dict parks
## the real value here and _ready puts it back after super().
var _restore_hp := -1.0


## =============================== Creation =================================


static func make(key: String) -> Critter:
	## The only correct way to build one. Sets species BEFORE _ready fires.
	var c := Critter.new()
	c.species = key if CritterDex.has(key) else "hare"
	c._configure()
	return c


func _configure() -> void:
	## Pull the dex into Enemy's exported knobs. Runs before the tree, so the
	## body, the collision box and the AI all agree about how big this is.
	profile = CritterDex.get_profile(species)
	if profile.is_empty():
		profile = CritterDex.get_profile("hare")
	arch = int(ARCH_IDS.get(String(profile.get("arch", "SKITTER")), Arch.SKITTER))
	legend = bool(CritterDex.flag(species, "legend", false))

	display_name = String(profile.get("nm", "Creature"))
	max_health = float(profile.get("hp", 30.0))
	health = max_health
	var spd: Array = profile.get("spd", [1.0, 5.0])
	wander_speed = float(spd[0])
	chase_speed = float(spd[1])
	var see: Array = profile.get("see", [14.0, 8.0])
	aggro_radius = float(see[0])
	leash_radius = float(CritterDex.flag(species, "leash", float(see[0]) * 2.0))
	bold = int(CritterDex.flag(species, "bold", 2))
	relentless = bool(CritterDex.flag(species, "relentless", false))
	attack_damage = float(profile.get("dmg", 0.0))
	attack_range = maxf(float(profile.get("len", 0.5)) * 0.9, 1.2)
	attack_cooldown = 1.4
	families = ["beast"]
	if CritterDex.flag(species, "legend", false):
		families = ["beast", "legend"]
	## Wildlife never uses Enemy's duelling/strong-attack machinery — the
	## archetypes drive everything. Leaving these on would let the inherited
	## combat code fight the brain for the steering wheel.
	duelist = false
	always_moving = false
	strong_throws = false
	can_climb = bool(CritterDex.flag(species, "climbs", false))
	climb_speed = 3.4
	## A wild animal's "nerve" is not courage, it is how hurt it gets before
	## it stops arguing and leaves. Almost everything leaves — a relentless
	## one never does, and hurting it only makes the fight worse.
	nerve = 0.999 if arch != Arch.BLUFFER else 0.30
	if relentless:
		nerve = 0.0
	rout_speed = 1.0
	rout_line = "bolts"
	gait_rate = clampf(1.8 / maxf(float(profile.get("len", 1.0)), 0.2), 0.55, 2.4)
	stride_deg = clampf(34.0 - float(profile.get("len", 1.0)) * 5.0, 14.0, 34.0)
	bob_h = clampf(float(profile.get("hgt", 0.5)) * 0.055, 0.01, 0.12)
	home_radius = lerpf(18.0, 60.0, clampf(float(profile.get("len", 1.0)) / 3.0, 0.0, 1.0))


func _ready() -> void:
	if profile.is_empty():
		_configure()
	super()
	if _restore_hp >= 0.0:
		health = minf(_restore_hp, max_health)
		_restore_hp = -1.0
	add_to_group("critters")
	add_to_group("wildlife")
	if arch == Arch.STALKER or arch == Arch.SCAVENGER:
		add_to_group("critter_predators")
	if CritterDex.flag(species, "prey", false) or arch == Arch.SKITTER:
		add_to_group("critter_prey")
	_home = global_position
	_sig_cool = randf_range(SIG_COOLDOWN.x, SIG_COOLDOWN.y)
	_buzz_cool = randf_range(BUZZ_COOLDOWN.x, BUZZ_COOLDOWN.y)
	_call_cool = randf_range(2.0, CALL_COOLDOWN.y)
	_breathe = randf() * TAU
	## Nothing that cannot be provoked should ever be able to hurt anything.
	if CritterDex.flag(species, "nofight", false):
		attack_damage = 0.0


func _skin_opts() -> Dictionary:
	## Texture tile by rig family, mass from the dex (or a body-size estimate:
	## ~60 kg per cubic metre of len x len x hgt, which puts a hare at 3 kg, a
	## deer at 150 and a moose near 500 — close enough for who-shoves-whom).
	var fam := String(profile.get("rig", "CHUNK"))
	var tile := "fur"
	match fam:
		"BIRD_GROUND", "BIRD_RAPTOR", "BIRD_PERCH", "BIRD_WATER": tile = "feather"
		"HERP", "FISH": tile = "scale"
		"URSID": tile = "fur_long"
		"CERVID": tile = "hide"
		"SWARM": tile = "chitin"
	if CritterDex.feat(species, "stripes", false) or CritterDex.feat(species, "stripe", false) \
			or CritterDex.feat(species, "barring", false):
		tile = "fur_striped"
	elif CritterDex.feat(species, "spots", false):
		tile = "fur_spotted"
	elif CritterDex.feat(species, "shaggy", false):
		tile = "fur_long"
	elif CritterDex.feat(species, "shell", false):
		tile = "scale"
	var L := float(profile.get("len", 0.6))
	var H := float(profile.get("hgt", 0.4))
	var m := maxf(float(profile.get("mass", 60.0 * L * L * H)), 0.05)
	mass = m
	return {"tile": tile, "mass": m}


func _build_body() -> void:
	if profile.is_empty():
		_configure()
	var L := float(profile.get("len", 0.6))
	var H := float(profile.get("hgt", 0.4))
	_add_collision(Vector3(maxf(L * 0.45, 0.25), maxf(H, 0.2), maxf(L * 0.9, 0.3)),
		Vector3(0, maxf(H, 0.2) * 0.5, 0))
	rig = CritterRig.build(self, species)
	loco_root = rig["root"] as Node3D
	body_mat = rig["body_mat"] as StandardMaterial3D
	base_body_color = profile.get("col", Color(0.5, 0.5, 0.5))
	eye_mats.clear()
	for m in (rig["eye_mats"] as Array):
		eye_mats.append(m as StandardMaterial3D)
	## Hip pivots go to Enemy's stride driver. Birds get two, quadrupeds four,
	## seals get flippers that _update_locomotion will swing — which is wrong
	## for a seal, so they opt out and CritterAnim humps them along instead.
	if not CritterDex.feat(species, "flipper", false) and rig["family"] != "FISH" \
			and rig["family"] != "SWARM":
		for hp in (rig["legs"] as Array):
			walk_legs.append(hp as Node3D)
	## Cache every albedo so a coat swap can lerp from the real colour rather
	## than compounding tints frame after frame.
	_base_cols.clear()
	for m in (rig["mats"] as Array):
		_base_cols.append((m as StandardMaterial3D).albedo_color)
	if legend and bool(CritterDex.flag(species, "glows", false)):
		CritterRig.spectral(rig, profile.get("col2", Color.WHITE), 1.4, 0.62)


## ============================== The brain =================================


func _physics_process(delta: float) -> void:
	if knocked:
		_knocked_tick(delta)
		return
	if dying:
		if skin == null or not skin.is_down():
			move_and_slide()
		return
	if burn_t > 0.0:
		## Fire is Enemy's business and it ticks whatever the animal is doing.
		super(delta)
		return

	_breathe += delta
	_alarm_cool = maxf(0.0, _alarm_cool - delta)
	_spray_cool = maxf(0.0, _spray_cool - delta)
	mood_t = maxf(0.0, mood_t - delta)
	_sig_cool = maxf(0.0, _sig_cool - delta)
	_buzz_cool = maxf(0.0, _buzz_cool - delta)
	_call_cool = maxf(0.0, _call_cool - delta)

	if hit_flash > 0.0:
		hit_flash -= delta
		if body_mat:
			body_mat.albedo_color = Color(0.9, 0.6, 0.55) if hit_flash > 0.0 else base_body_color

	## Sleep the far-off ones. A forest full of animals is only affordable
	## because most of them are not thinking.
	var pl := _get_player()
	var dist := 9999.0
	if pl != null:
		dist = global_position.distance_to(pl.global_position)
	if dist > 60.0 and mood == Mood.EASY:
		if not is_on_floor() and not _flies():
			velocity.y -= gravity * delta
		move_and_slide()
		return

	if not is_on_floor() and not _flies():
		velocity.y -= gravity * delta
	elif _flies():
		velocity.y = move_toward(velocity.y, 0.0, 2.0 * delta)

	if flinch_timer > 0.0:
		flinch_timer -= delta
		velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
		_update_locomotion(delta)
		_animate(delta)
		move_and_slide()
		return

	_season_tick(delta)
	_latch_tick(delta)
	_buff_tick(delta)

	## ROOTED. A committed move plants the animal: it does not steer, chase or
	## swing while it runs. The archetype is skipped entirely rather than asked
	## to behave, because a brain that is still picking targets while the body
	## cannot move is how you get an animal that slides across the ground in a
	## pose. Its mood is held so the move cannot expire out from under it.
	if is_rooted():
		## Planted, not braking. Bleeding the velocity off over a fifth of a
		## second still slid the bear a metre and a half across the ground
		## while it was supposedly standing still, which is exactly the
		## floating-pose look this is meant to avoid. Gravity still applies —
		## it stands on the ground, it does not hover over it.
		velocity.x = 0.0
		velocity.z = 0.0
		mood_t = maxf(mood_t, 0.25)
		if pl != null:
			var to_p := pl.global_position - global_position
			to_p.y = 0.0
			_face(to_p, delta, 2.2)   ## it can still turn to keep you in front
		_update_locomotion(delta)
		_animate(delta)
		move_and_slide()
		return

	## Perception, then the archetype, then the body.
	if pl != null and not _playing_dead:
		_notice(pl, dist, delta)
	match arch:
		Arch.SKITTER: _do_skitter(delta, pl, dist)
		Arch.SENTINEL: _do_sentinel(delta, pl, dist)
		Arch.BLUFFER: _do_bluffer(delta, pl, dist)
		Arch.STALKER: _do_stalker(delta, pl, dist)
		Arch.RAIDER: _do_raider(delta, pl, dist)
		Arch.ENGINEER: _do_engineer(delta, pl, dist)
		Arch.SCAVENGER: _do_scavenger(delta, pl, dist)
		_: _do_ambient(delta, pl, dist)

	_idle_flavour(delta, dist)
	_update_locomotion(delta)
	_animate(delta)
	move_and_slide()


func _flies() -> bool:
	return bool(CritterDex.flag(species, "glide", false))


func _panic_radius() -> float:
	var see: Array = profile.get("see", [14.0, 8.0])
	return float(see[1])


func _notice(pl: Node3D, dist: float, _delta: float) -> void:
	## The one rule every archetype shares: something big walked into the
	## radius, so at minimum you look at it. What happens next is the
	## archetype's problem.
	if dist > aggro_radius:
		return
	if mood == Mood.EASY:
		_set_mood(Mood.ALERT, ALERT_HOLD)
		_threat_pos = pl.global_position


func _set_mood(m: int, hold: float) -> void:
	if mood != m:
		mood = m
		mood_t = hold
		_end_sig()
	else:
		mood_t = maxf(mood_t, hold)


## ============================== Archetypes ================================


func _do_skitter(delta: float, pl: Node3D, dist: float) -> void:
	## Flee, and keep fleeing until you have put real distance between you and
	## it. Nothing here ever fights.
	match mood:
		Mood.FLEE:
			if mood_t <= 0.0 and dist > _panic_radius() * 1.8:
				_set_mood(Mood.ALERT, 2.5)
				return
			_run_from(_threat_pos, delta)
		Mood.ALERT:
			if pl != null and dist < _panic_radius():
				_spook(pl.global_position, Telegraph.Threat.ALARM)
				return
			_hold_still(delta, pl)
			if mood_t <= 0.0:
				_set_mood(Mood.EASY, 0.0)
		_:
			if pl != null and dist < _panic_radius():
				_spook(pl.global_position, Telegraph.Threat.ALARM)
			else:
				_graze(delta)


func _do_sentinel(delta: float, pl: Node3D, dist: float) -> void:
	## SHOUT first, run second. That call is the whole reason this archetype
	## exists — the animal is a sensor the player can learn to read.
	match mood:
		Mood.FLEE:
			if mood_t <= 0.0 and dist > _panic_radius() * 1.6:
				_set_mood(Mood.ALERT, 3.0)
				return
			_run_from(_threat_pos, delta)
		Mood.ALERT:
			_hold_still(delta, pl)
			if pl != null and dist < _panic_radius():
				_sound_off(pl.global_position)
				_spook(pl.global_position, Telegraph.Threat.ALARM)
			elif _alarm_cool <= 0.0 and pl != null and dist < aggro_radius * 0.8:
				_sound_off(pl.global_position)
			elif mood_t <= 0.0:
				_set_mood(Mood.EASY, 0.0)
		_:
			if pl != null and dist < aggro_radius:
				_set_mood(Mood.ALERT, ALERT_HOLD)
				_threat_pos = pl.global_position
			else:
				_graze(delta)


func _do_bluffer(delta: float, pl: Node3D, dist: float) -> void:
	## The escalation ladder: warn, warn harder, then mean it. How many rungs
	## it has is `bold` — most things want two, a bear wants one — and a
	## `relentless` one never climbs back down it.
	var warn_at := _panic_radius()
	## A relentless animal commits from the whole warn radius. Everything else
	## waits until you are half-way in before it decides you meant it.
	var charge_at := warn_at * (1.0 if relentless else 0.5)
	match mood:
		Mood.CHARGE:
			if pl == null:
				_set_mood(Mood.EASY, 0.0)
				return
			var to := pl.global_position - global_position
			to.y = 0.0
			var dist_p := to.length()
			## Giving up. A normal bluffer stops when the charge times out; a
			## relentless one only stops when you are past its leash, which is
			## the honest way out of a fight you cannot win — get far enough
			## away and it goes back to its patch. It does NOT time out, and it
			## does NOT lose interest because you hid behind a rock.
			if relentless:
				if dist_p > leash_radius:
					_bluff_count = 0
					_set_mood(Mood.EASY, 0.0)
					return
				mood_t = maxf(mood_t, 1.0)
			elif mood_t <= 0.0:
				_set_mood(Mood.WARN, WARN_HOLD)
				return
			_face(to, delta, 6.0)
			_steer(to.normalized() * chase_speed, delta, 16.0)
			if dist_p <= attack_range and attack_cd <= 0.0:
				attack_cd = attack_cooldown
				if pl.has_method("take_damage"):
					pl.take_damage(attack_power(), global_position, true, Vector3.INF, self)
				HitFX.flesh(global_position + Vector3.UP * float(profile.get("hgt", 1.0)) * 0.6,
					to.normalized(), 1.2)
				## A bluffer makes its point and backs off. A relentless one
				## does not: it stays on you and swings again. This one line is
				## the difference between a bear that scares you off and a bear
				## that is a fight.
				if not relentless:
					_set_mood(Mood.WARN, WARN_HOLD)
			attack_cd = maxf(0.0, attack_cd - delta)
		Mood.WARN:
			if pl == null:
				_set_mood(Mood.EASY, 0.0)
				return
			var tw := pl.global_position - global_position
			tw.y = 0.0
			_face(tw, delta, 5.0)
			_steer(Vector3.ZERO, delta, 10.0)
			if _sig == "":
				## The ladder opens with the biggest thing the animal can still
				## do. For a healthy bear that is rearing up — it plants itself,
				## reads the air, and comes down meaner. Below the gate it
				## cannot, and drops straight to the huff, which is exactly the
				## reward for having hurt it: the wounded bear is the weaker
				## bear even though it is angrier.
				var opener := _payoff_sig()
				_play_sig(opener if opener != "" else _warn_sig())
				_bluff_count += 1
				Telegraph.ring(self, global_position, aggro_radius * 1.2,
					Telegraph.Threat.ALARM, display_name)
				_say(String((profile.get("call", {}) as Dictionary).get("alarm", "")))
			## Skunks do not charge. They have a better idea.
			if CritterDex.flag(species, "spray", false) and _bluff_count >= bold \
					and dist < SPRAY_RANGE and _spray_cool <= 0.0:
				_do_spray(pl)
			elif dist < charge_at and _bluff_count >= bold and attack_damage > 0.0:
				_set_mood(Mood.CHARGE, 3.0)
			elif relentless and _bluff_count >= bold and attack_damage > 0.0 and dist < leash_radius:
				## It gave you the warning. It is not going to stand here
				## repeating itself while you walk around it.
				_set_mood(Mood.CHARGE, 3.0)
			elif not relentless and dist > warn_at * 1.6 and mood_t <= 0.0:
				_bluff_count = 0
				_set_mood(Mood.EASY, 0.0)
			elif relentless and dist > leash_radius:
				_bluff_count = 0
				_set_mood(Mood.EASY, 0.0)
		Mood.FLEE:
			## Nothing puts a relentless one to flight — if something managed
			## to set this mood, it turns straight back around.
			if relentless and pl != null and dist < leash_radius:
				_set_mood(Mood.CHARGE, 4.0)
				return
			_run_from(_threat_pos, delta)
			if mood_t <= 0.0:
				_set_mood(Mood.EASY, 0.0)
		_:
			if pl != null and dist < warn_at:
				_threat_pos = pl.global_position
				_set_mood(Mood.WARN, WARN_HOLD)
			else:
				_bluff_count = 0
				_graze(delta)


func _do_stalker(delta: float, pl: Node3D, dist: float) -> void:
	## Hunts other wildlife, not you. It will keep its distance and watch, and
	## a player who stands still long enough gets to see a real kill.
	if _prey == null or not is_instance_valid(_prey) or (_prey as Node3D).global_position.distance_to(global_position) > 45.0:
		_prey = _find_prey()
	match mood:
		Mood.HUNT:
			if _prey == null or not is_instance_valid(_prey):
				_set_mood(Mood.EASY, 0.0)
				return
			var to: Vector3 = (_prey as Node3D).global_position - global_position
			to.y = 0.0
			var d := to.length()
			_face(to, delta, 7.0)
			if d > 6.0:
				## The stalk: low, slow, and it stops when the prey looks up.
				if _sig == "":
					_play_sig("silent_stalk")
				_steer(to.normalized() * wander_speed * 2.2, delta, 8.0)
			else:
				if _sig == "" or _sig == "silent_stalk":
					_play_sig(_pounce_sig())
				_steer(to.normalized() * chase_speed, delta, 20.0)
				if d < attack_range and attack_cd <= 0.0:
					attack_cd = attack_cooldown
					if _prey.has_method("take_damage"):
						(_prey as Node3D).call("take_damage", attack_power() * 2.0,
							global_position, false, Vector3.INF, self)
					HitFX.flesh((_prey as Node3D).global_position + Vector3.UP * 0.4,
						to.normalized(), 1.0)
			attack_cd = maxf(0.0, attack_cd - delta)
			if mood_t <= 0.0:
				_set_mood(Mood.EASY, 0.0)
		Mood.FLEE:
			_run_from(_threat_pos, delta)
			if mood_t <= 0.0:
				_set_mood(Mood.EASY, 0.0)
		Mood.ALERT:
			## Predators do not panic at a person; they withdraw and watch.
			_hold_still(delta, pl)
			if pl != null and dist < _panic_radius() * 0.7:
				_spook(pl.global_position, Telegraph.Threat.WARY)
			elif mood_t <= 0.0:
				_set_mood(Mood.EASY, 0.0)
		_:
			if _prey != null and randf() < 0.4 * delta * 8.0:
				_set_mood(Mood.HUNT, 22.0)
			else:
				_patrol(delta)


func _do_raider(delta: float, pl: Node3D, dist: float) -> void:
	## Goes for the player's stuff, not the player. Backs off when watched,
	## comes right back when not.
	if _target_pos == Vector3.ZERO or randf() < 0.01:
		_target_pos = _find_loot()
	match mood:
		Mood.WORK:
			if _target_pos == Vector3.ZERO:
				_set_mood(Mood.EASY, 0.0)
				return
			var to := _target_pos - global_position
			to.y = 0.0
			if to.length() > 1.4:
				_face(to, delta, 6.0)
				_steer(to.normalized() * wander_speed * 2.6, delta, 9.0)
				if _sig == "":
					_play_sig("camp_case")
			else:
				_steer(Vector3.ZERO, delta, 12.0)
				_work_t += delta
				if _sig == "":
					_play_sig("rummage" if randf() < 0.5 else "unlatch")
				if _work_t > 7.0:
					_work_t = 0.0
					_target_pos = Vector3.ZERO
					_play_sig("food_wash" if species == "raccoon" else "camp_rob")
					_set_mood(Mood.EASY, 0.0)
			## Caught in the act: freeze, stare, then leave with your dinner.
			if pl != null and dist < 5.0:
				_play_sig("mask_stare")
				_set_mood(Mood.FLEE, FLEE_HOLD)
				_threat_pos = pl.global_position
			if mood_t <= 0.0 and mood == Mood.WORK:
				mood_t = 4.0
		Mood.FLEE:
			_run_from(_threat_pos, delta)
			if mood_t <= 0.0:
				_set_mood(Mood.EASY, 0.0)
		_:
			if pl != null and dist < _panic_radius():
				_spook(pl.global_position, Telegraph.Threat.WARY)
			elif _target_pos != Vector3.ZERO and (_night_now() or CritterDex.flag(species, "tame", false)):
				_set_mood(Mood.WORK, 12.0)
			else:
				_patrol(delta)


func _do_engineer(delta: float, pl: Node3D, dist: float) -> void:
	## The beaver. Fells saplings using the REAL tree system, hauls them to a
	## dam site, and the pond it makes changes what else lives there. Every
	## other archetype reacts to the world; this one edits it.
	match mood:
		Mood.WORK:
			var to := _target_pos - global_position
			to.y = 0.0
			if _target_pos == Vector3.ZERO:
				_set_mood(Mood.EASY, 0.0)
			elif to.length() > 1.6:
				_face(to, delta, 5.0)
				_steer(to.normalized() * wander_speed * 2.0, delta, 7.0)
				if _sig == "":
					_play_sig("log_drag")
			else:
				_steer(Vector3.ZERO, delta, 10.0)
				_work_t += delta
				if _sig == "":
					_play_sig("gnaw_ring")
				if _work_t > 9.0:
					_work_t = 0.0
					_gnaw_through()
					_target_pos = Vector3.ZERO
					_set_mood(Mood.EASY, 0.0)
			if mood_t <= 0.0 and mood == Mood.WORK:
				mood_t = 6.0
		Mood.FLEE:
			## The tail slap first, THEN the dive. Loudest ping in the woods.
			_run_from(_threat_pos, delta)
			if mood_t <= 0.0:
				_set_mood(Mood.EASY, 0.0)
		_:
			if pl != null and dist < _panic_radius():
				_play_sig("tail_slap")
				_say("beaver_slap")
				Telegraph.ring(self, global_position, 46.0, Telegraph.Threat.ALARM, display_name)
				_alarm_cool = 6.0
				_spook(pl.global_position, Telegraph.Threat.ALARM)
			elif _sig_cool <= 0.0 and randf() < 0.5:
				_target_pos = _find_sapling()
				if _target_pos != Vector3.ZERO:
					_set_mood(Mood.WORK, 20.0)
				else:
					_graze(delta)
			else:
				_graze(delta)


func _do_scavenger(delta: float, pl: Node3D, dist: float) -> void:
	## Ravens and vultures. They find the dead, they circle it, and the circle
	## is visible from a long way off — which makes them the game's cheapest
	## and best "something happened over there" marker.
	match mood:
		Mood.FEED:
			var to := _target_pos - global_position
			to.y = 0.0
			if to.length() > 2.0:
				_face(to, delta, 4.0)
				_steer(to.normalized() * wander_speed * 3.0, delta, 6.0)
				if _sig == "":
					_play_sig("corpse_circle")
			else:
				_steer(Vector3.ZERO, delta, 8.0)
				if _sig == "":
					_play_sig("kraa" if species != "vulture" else "wing_dry")
			if pl != null and dist < 8.0:
				_spook(pl.global_position, Telegraph.Threat.WARY)
			if mood_t <= 0.0:
				_set_mood(Mood.EASY, 0.0)
		Mood.FLEE:
			_run_from(_threat_pos, delta)
			if mood_t <= 0.0:
				_set_mood(Mood.EASY, 0.0)
		_:
			var corpse := _find_corpse()
			if corpse != Vector3.ZERO:
				_target_pos = corpse
				_set_mood(Mood.FEED, 30.0)
			elif pl != null and dist < _panic_radius() * 0.6:
				_spook(pl.global_position, Telegraph.Threat.WARY)
			else:
				_patrol(delta)


func _do_ambient(delta: float, _pl: Node3D, _dist: float) -> void:
	## Fish, swarms, the aurora herd. No fear, no hunger, no opinions — they
	## drift on their own clock and never interact.
	_steer(wander_dir * wander_speed, delta, 3.0)
	wander_timer -= delta
	if wander_timer <= 0.0:
		_pick_wander()
	if wander_dir != Vector3.ZERO:
		_face(wander_dir, delta, 2.0)
	if _sig == "" and _sig_cool <= 0.0:
		var sigs: Array = profile.get("sig", [])
		if not sigs.is_empty():
			_play_sig(String(sigs[0]))


## ============================ Shared movement =============================


func _graze(delta: float) -> void:
	## Not a straight line, and not far from home — an animal has a patch.
	var pull := _home - global_position
	pull.y = 0.0
	if pull.length() > home_radius:
		_face(pull, delta, 3.0)
		_steer(pull.normalized() * wander_speed, delta, 4.0)
		return
	_do_wander(delta)


func _patrol(delta: float) -> void:
	## Predators and fliers range much wider than a grazer.
	var pull := _home - global_position
	pull.y = 0.0
	if pull.length() > home_radius * 2.4:
		_face(pull, delta, 3.0)
		_steer(pull.normalized() * wander_speed * 1.6, delta, 5.0)
		return
	_do_wander(delta)


func _hold_still(delta: float, pl: Node3D) -> void:
	## The stare. Every prey animal's first move is to stop moving and look
	## right at you, and it is worth animating properly because it is the
	## moment the player realises they have been seen.
	_steer(Vector3.ZERO, delta, 12.0)
	if pl != null:
		var to := pl.global_position - global_position
		to.y = 0.0
		_face(to, delta, 4.0)
	if _sig == "" and _sig_cool <= 0.0:
		_play_sig(_alert_sig())


func _run_from(from: Vector3, delta: float) -> void:
	var away := global_position - from
	away.y = 0.0
	if away.length() < 0.2:
		away = Vector3(randf() - 0.5, 0, randf() - 0.5)
	away = away.normalized()
	## Zigzag: a hare that runs in a straight line is a dead hare, and it also
	## looks like a bug.
	if CritterDex.flag(species, "prey", false) or arch == Arch.SKITTER:
		away = away.rotated(Vector3.UP, sin(_breathe * 4.4) * 0.55)
	_flee_dir = away
	_face(away, delta, 9.0)
	_steer(away * chase_speed, delta, 22.0)


func _spook(from: Vector3, threat: int) -> void:
	if _playing_dead:
		return
	## A relentless animal cannot be spooked. Alarm calls, a hit, another
	## animal bolting past it — none of it makes a bear leave. It turns toward
	## whatever caused it instead.
	if relentless:
		_threat_pos = from
		if attack_damage > 0.0:
			_bluff_count = maxi(_bluff_count, bold)
			_set_mood(Mood.CHARGE, 4.0)
		return
	## The opossum's answer to being caught is not running.
	if CritterDex.flag(species, "playdead", false) and randf() < 0.7:
		_play_dead()
		return
	_threat_pos = from
	_set_mood(Mood.FLEE, FLEE_HOLD)
	if _alarm_cool <= 0.0:
		_alarm_cool = 3.5
		Telegraph.ring(self, global_position, aggro_radius * 1.6, threat, display_name)
	_play_sig(_flee_sig())


## ================================ Alarms ==================================


func is_sentinel() -> bool:
	return arch == Arch.SENTINEL


func relay_alarm(_delay: float) -> void:
	_alarm_cool = 5.0
	_play_sig(_alert_sig())
	_say(String((profile.get("call", {}) as Dictionary).get("alarm", "")))


func hear_alarm(pos: Vector3, threat: int, _src: String) -> void:
	## Somebody else raised the alarm. Prey believes it immediately; predators
	## take it as news, not orders.
	if _playing_dead or dying:
		return
	if arch == Arch.STALKER or arch == Arch.SCAVENGER:
		return
	_threat_pos = pos
	if relentless:
		## Everything else in the woods going up is not a bear's problem.
		return
	if threat >= Telegraph.Threat.ALARM and global_position.distance_to(pos) < aggro_radius * 1.4:
		_set_mood(Mood.FLEE, FLEE_HOLD * 0.7)
	elif mood == Mood.EASY:
		_set_mood(Mood.ALERT, ALERT_HOLD * 0.6)


func hear_prey(pos: Vector3) -> void:
	## A predator hearing the forest go up hears a meal, not a warning.
	if dying or mood == Mood.FLEE:
		return
	if arch != Arch.STALKER and arch != Arch.SCAVENGER:
		return
	_target_pos = pos
	if mood == Mood.EASY:
		_prey = _find_prey()
		if _prey != null:
			_set_mood(Mood.HUNT, 20.0)


func _sound_off(at: Vector3) -> void:
	if _alarm_cool > 0.0:
		return
	_alarm_cool = randf_range(4.0, 9.0)
	_play_sig(_alert_sig())
	_say(String((profile.get("call", {}) as Dictionary).get("alarm", "")))
	Telegraph.ring(self, global_position, aggro_radius * 2.0, Telegraph.Threat.ALARM, display_name)
	_threat_pos = at


## ========================= Signature animations ===========================


func can_play(key: String) -> bool:
	## A gated move needs the health to pay for it. Everything else is free.
	if not SIG_HEALTH_GATE.has(key):
		return true
	var need := float(SIG_HEALTH_GATE[key])
	if health < max_health * need:
		return false
	## And a payoff move will not chain — it has to be earned again.
	return not (SIG_PAYOFF.has(key) and (_buff_cool > 0.0 or buff_t > 0.0))


func is_rooted() -> bool:
	return _sig != "" and bool(SIG_ROOTS.get(_sig, false))


func _play_sig(key: String) -> void:
	if key == "" or _playing_dead:
		return
	if not can_play(key):
		return
	_sig = key
	_sig_t = 0.0
	_sig_len = maxf(CritterAnim.duration(key), 0.05)
	_sig_cool = randf_range(SIG_COOLDOWN.x, SIG_COOLDOWN.y)


func _end_sig() -> void:
	if _sig != "":
		_sig = ""
		CritterAnim.neutral(rig)


func _sigs() -> Array:
	return profile.get("sig", []) as Array


func _has_sig(k: String) -> bool:
	return _sigs().has(k)


func _first_sig(cands: Array) -> String:
	for c in cands:
		if _has_sig(String(c)):
			return String(c)
	var s := _sigs()
	return String(s[0]) if not s.is_empty() else ""


func _alert_sig() -> String:
	return _first_sig(["hoof_stomp", "scold", "screech", "periscope", "sit_scan",
		"dee_count", "sentry_post", "caw", "kraa", "head_track", "mask_stare",
		"freeze_crouch", "hiss_gape", "ruff_up", "peent", "statue_stalk"])


func _payoff_sig() -> String:
	## The best gated move this animal has right now, or "" if it cannot pay
	## for any of them. Only ever returns something the animal actually owns.
	for k in SIG_PAYOFF.keys():
		if _has_sig(String(k)) and can_play(String(k)):
			return String(k)
	return ""


func _warn_sig() -> String:
	return _first_sig(["hackles", "bear_huff", "quill_bristle", "foot_stamp",
		"hiss_charge", "road_hiss", "antler_thrash", "tail_up", "ruff_up"])


func _flee_sig() -> String:
	return _first_sig(["tail_flag", "zigzag", "flush", "burrow_dive", "lodge_dive",
		"snow_dive", "log_plop", "ribbon_flee", "leap_splash", "torpedo_dive",
		"trunk_scramble", "wall_dash", "roost_flap", "shell_tuck", "waddle"])


func _pounce_sig() -> String:
	return _first_sig(["mouse_dive", "mouse_pounce", "hare_ambush", "stoop",
		"hover_plunge", "fish_snatch", "lunge_latch", "spear_strike", "war_dance"])


## =============================== The payoff ===============================


func _award_payoff(key: String) -> void:
	## The bear that reared up, read the air, and came all the way back down
	## has decided about you. It is stronger and harder to hurt for a while,
	## and it looks it — the coat lights from underneath so the player can read
	## "that just got worse" without a health bar or a status icon.
	if not SIG_PAYOFF.has(key):
		return
	var p: Dictionary = SIG_PAYOFF[key]
	buff_atk = float(p.get("atk", 1.0))
	buff_def = float(p.get("def", 1.0))
	buff_t = float(p.get("time", 12.0))
	_buff_cool = buff_t + 14.0
	_say(String((profile.get("call", {}) as Dictionary).get("idle", "")))
	Telegraph.ring(self, global_position, aggro_radius * 1.5,
		Telegraph.Threat.PANIC, display_name)
	_set_buff_glow(true)


func _buff_tick(delta: float) -> void:
	_buff_cool = maxf(0.0, _buff_cool - delta)
	if buff_t <= 0.0:
		return
	buff_t = maxf(0.0, buff_t - delta)
	if buff_t <= 0.0:
		buff_atk = 1.0
		buff_def = 1.0
		_set_buff_glow(false)


func _set_buff_glow(on: bool) -> void:
	## Emission, not albedo — the hit flash and the seasonal coat swap both own
	## albedo, and three systems writing one colour is how you get a bear that
	## flickers.
	if rig.is_empty():
		return
	var col: Color = profile.get("col3", Color(0.9, 0.5, 0.2))
	for m in (rig["mats"] as Array):
		var mat := m as StandardMaterial3D
		if mat == null:
			continue
		mat.emission_enabled = on
		if on:
			mat.emission = col
			mat.emission_energy_multiplier = 0.55


func attack_power() -> float:
	return attack_damage * buff_atk


## ============================== Specials ==================================


func _play_dead() -> void:
	## The opossum is not pretending on purpose — it faints. Either way it
	## works on a coyote, and it works on a player exactly once.
	_playing_dead = true
	_sig = "play_dead"
	_sig_t = 0.0
	_sig_len = CritterAnim.duration("play_dead")
	velocity = Vector3.ZERO
	get_tree().create_timer(_sig_len).timeout.connect(func():
		if is_instance_valid(self):
			_playing_dead = false
			_end_sig()
			_set_mood(Mood.FLEE, FLEE_HOLD))


func _do_spray(pl: Node3D) -> void:
	## The debuff is social, not physical: nothing wants to be near you.
	_spray_cool = 40.0
	_play_sig("spray")
	var dir := (pl.global_position - global_position).normalized()
	var fx := HitFX.flesh(global_position + Vector3.UP * 0.3 + dir * 0.4, dir, 0.7)
	if fx != null and pl.has_method("apply_stink"):
		pl.call("apply_stink", SPRAY_SECONDS)
	elif pl.has_method("take_damage"):
		pl.take_damage(1.0, global_position, false, Vector3.INF, self)
	## Everything with a nose leaves.
	for n in get_tree().get_nodes_in_group("critters"):
		var c := n as Critter
		if c != null and c != self and c.global_position.distance_to(global_position) < 20.0:
			c._spook(global_position, Telegraph.Threat.WARY)
	_set_mood(Mood.FLEE, FLEE_HOLD)
	_threat_pos = pl.global_position


func _latch_tick(delta: float) -> void:
	if _latched == null or not is_instance_valid(_latched):
		_latched = null
		return
	_latch_t -= delta
	global_position = global_position.lerp((_latched as Node3D).global_position, clampf(delta * 6.0, 0.0, 1.0))
	if _latch_t <= 0.0:
		_latched = null
		_end_sig()


func try_latch(who: Node3D) -> void:
	if not CritterDex.flag(species, "latch", false) or _latched != null:
		return
	_latched = who
	_latch_t = LATCH_SECONDS
	_play_sig("lunge_latch")
	if who.has_method("take_damage"):
		who.call("take_damage", attack_power(), global_position, true, Vector3.INF, self)


func _gnaw_through() -> void:
	## The beaver actually takes the tree down, through the real tree system —
	## the whole reason it is worth having an ENGINEER archetype rather than
	## an animal that mimes at a trunk.
	var best: Node = null
	var bd := 3.2
	for t in get_tree().get_nodes_in_group("trees"):
		var n := t as Node3D
		if n == null:
			continue
		var d := n.global_position.distance_to(global_position)
		if d < bd:
			bd = d
			best = t
	if best == null:
		return
	if best.has_method("chop_hit"):
		for _i in range(9):
			best.call("chop_hit", global_position, global_position)
	HitFX.wood(global_position + Vector3.UP * 0.4, Vector3.FORWARD, "birch", 1.0)
	Telegraph.ring(self, global_position, 26.0, Telegraph.Threat.WARY, display_name)


## ============================== Perception ================================


func _find_prey() -> Node3D:
	var best: Node3D = null
	var bd := 40.0
	for n in get_tree().get_nodes_in_group("critter_prey"):
		var c := n as Critter
		if c == null or c == self or c.dying:
			continue
		## A predator eats things smaller than itself. A lynx does not stalk a
		## moose, and a fisher only takes a porcupine because it cheats.
		if float(c.profile.get("len", 1.0)) > float(profile.get("len", 1.0)) * 0.95:
			continue
		var d := c.global_position.distance_to(global_position)
		if d < bd:
			bd = d
			best = c
	return best


func _find_corpse() -> Vector3:
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e != null and e != self and e.dying:
			return e.global_position
	for n in get_tree().get_nodes_in_group("dropped_items"):
		var d := n as Node3D
		if d != null and d.global_position.distance_to(global_position) < 50.0:
			return d.global_position
	return Vector3.ZERO


func _find_loot() -> Vector3:
	for g in ["dropped_items", "beds", "carry_logs"]:
		for n in get_tree().get_nodes_in_group(g):
			var d := n as Node3D
			if d != null and d.global_position.distance_to(global_position) < 40.0:
				return d.global_position
	return Vector3.ZERO


func _find_sapling() -> Vector3:
	var best := Vector3.ZERO
	var bd := 26.0
	for t in get_tree().get_nodes_in_group("trees"):
		var n := t as Node3D
		if n == null:
			continue
		var d := n.global_position.distance_to(global_position)
		if d < bd:
			bd = d
			best = n.global_position
	return best


## =============================== Seasons ==================================


func _night_now() -> bool:
	return _night


func set_clock(hour: float, phase: float) -> void:
	## The director pushes the clock rather than every animal polling for it.
	_night = hour >= 20.6 or hour < 6.0
	_season = CritterDex.season_of(phase)
	if CritterDex.flag(species, "coat_swap", false):
		## Winter white. Ramped over the shoulder seasons so a hare can be
		## caught out — white on bare ground in a late autumn is real, and it
		## is the best argument this whole system makes for itself.
		var p := fposmod(phase, 1.0)
		var want := 0.0
		if p >= 0.68:
			want = clampf((p - 0.68) / 0.14, 0.0, 1.0)
		elif p < 0.16:
			want = 1.0 - clampf(p / 0.14, 0.0, 1.0)
		_coat = want


func _season_tick(delta: float) -> void:
	CritterRig.eyeshine(rig, 0.9 if _night else 0.0)
	if not CritterDex.flag(species, "coat_swap", false):
		return
	var white: Color = profile.get("col2", Color.WHITE)
	var mats: Array = rig["mats"] as Array
	for i in range(mats.size()):
		if i >= _base_cols.size():
			break
		var mat := mats[i] as StandardMaterial3D
		if mat == null or mat == body_mat and hit_flash > 0.0:
			continue
		var want: Color = (_base_cols[i] as Color).lerp(white, _coat)
		mat.albedo_color = mat.albedo_color.lerp(want, clampf(delta * 2.0, 0.0, 1.0))
	if CritterDex.flag(species, "blacktip", false):
		pass  ## the ermine keeps its black tail tip — it is col3 and never swaps


## ============================== Presentation ==============================


func _idle_flavour(_delta: float, dist: float) -> void:
	## The unprompted stuff: a call across the valley, an idle signature, a
	## sit-up-and-scan. This is what makes a forest feel inhabited rather than
	## populated.
	if _sig != "" or _playing_dead:
		return
	if _call_cool <= 0.0:
		_call_cool = randf_range(CALL_COOLDOWN.x, CALL_COOLDOWN.y)
		var idle_call := String((profile.get("call", {}) as Dictionary).get("idle", ""))
		if idle_call != "" and (not CritterDex.flag(species, "night", false) or _night):
			_say(idle_call)
			var voice_sig := _first_sig(["howl", "loon_wail", "hoot", "kraa", "caw",
				"log_drum", "gobble_back", "scold", "jug_o_rum", "peent", "laugh", "screech"])
			if voice_sig != "":
				_play_sig(voice_sig)
			return
	if _sig_cool <= 0.0 and dist < 45.0:
		## Idle flavour never reaches for a payoff move. Rearing up is a
		## decision the animal makes about YOU, not something it does to pass
		## the afternoon — and a buff handed out by a random idle roll with
		## nobody watching is a bug wearing an animation.
		var s: Array = []
		for k in _sigs():
			if not SIG_PAYOFF.has(String(k)):
				s.append(k)
		if not s.is_empty():
			_play_sig(String(s[randi() % s.size()]))
			return
	## BUZZ. A calm animal standing about — eating, scratching, tossing its
	## head — off the generic library, so nothing needs a per-species clip to
	## look alive. Standing only: a buzz clip on a walking body fights the
	## gait. Never a payoff move; none of these keys are in SIG_PAYOFF, and
	## the filter keeps it that way if one ever is.
	if _buzz_cool <= 0.0 and mood == Mood.EASY and _loco_amount < 0.25 and dist < 60.0:
		_buzz_cool = randf_range(BUZZ_COOLDOWN.x, BUZZ_COOLDOWN.y)
		var b: Array = []
		for k in CritterAnim.buzz_for(String(rig.get("family", ""))):
			if not SIG_PAYOFF.has(String(k)):
				b.append(k)
		if not b.is_empty():
			_play_buzz(String(b[randi() % b.size()]))


func _play_buzz(key: String) -> void:
	## Like _play_sig, but a buzz clip does not spend the species-signature
	## cooldown — the tells keep their own cadence on top of this. It is silent
	## by construction: huff_toss is idle flavour, not the alarm call.
	if key == "" or _playing_dead or not can_play(key):
		return
	_sig = key
	_sig_t = 0.0
	_sig_len = maxf(CritterAnim.duration(key), 0.05)


func is_buzzing() -> bool:
	return _sig != "" and CritterAnim.buzz_for(String(rig.get("family", ""))).has(_sig)


func _say(call_key: String) -> void:
	if call_key == "":
		return
	CritterAudio.play_at(self, call_key, global_position)


func _animate(delta: float) -> void:
	if rig.is_empty():
		return
	CritterAnim.idle(rig, String(rig.get("family", "CHUNK")), _loco_amount, walk_t, _breathe)
	if _sig == "":
		return
	_sig_t += delta / _sig_len
	if _sig_t >= 1.0:
		if _playing_dead:
			_sig_t = 1.0
		else:
			## Paid out only on the FULL return to the ground. Cut the move
			## short — flinch, a hit, anything that calls _end_sig early — and
			## the animal gets nothing for it.
			_award_payoff(_sig)
			_end_sig()
			return
	CritterAnim.play(rig, _sig, clampf(_sig_t, 0.0, 1.0), delta, self)


## ================================ Damage ==================================


func take_damage(amount: float, from_pos = null, strong = false, throw = null, attacker: Node = null) -> void:
	if dying:
		return
	var was_easy := mood == Mood.EASY
	## Quills. Reach into a porcupine and you take it home with you — and the
	## coyotes learn this too, because they route through the same call.
	if CritterDex.flag(species, "quills", false) and attacker != null \
			and attacker is Node3D and (attacker as Node3D).global_position.distance_to(global_position) < attack_range + 0.6:
		if attacker.has_method("take_damage"):
			attacker.call("take_damage", QUILL_DAMAGE, global_position, false, Vector3.INF, self)
		if attacker.has_method("stick_quills"):
			attacker.call("stick_quills", 3)
		HitFX.bone(global_position + Vector3.UP * float(profile.get("hgt", 0.4)) * 0.7,
			((attacker as Node3D).global_position - global_position).normalized(), 0.8)
		_play_sig("quill_bristle")
	## The snapper does not let go.
	if CritterDex.flag(species, "latch", false) and attacker is Node3D:
		try_latch(attacker as Node3D)
	## The defensive half of the payoff. A bear that just came down off its
	## hind legs is harder to put down as well as harder to survive.
	super(amount * buff_def, from_pos, strong, throw, attacker)
	if dying:
		## A kill in the woods is loud. Everything hears it, the scavengers
		## come, and the ravens will be over the spot before you finish.
		Telegraph.ring(self, global_position, 60.0, Telegraph.Threat.PANIC, display_name)
		return
	_playing_dead = false
	var src: Vector3 = from_pos if from_pos is Vector3 else global_position - Vector3.FORWARD
	if arch == Arch.BLUFFER and attack_damage > 0.0:
		## Hurt a bluffer and the ladder is over — it does not matter whether it
		## was grazing or already huffing at you. This deliberately ignores the
		## previous mood: an earlier version only escalated a bear that was
		## still CALM, so hitting one that had already started warning did
		## nothing at all, which is the exact moment it must do something.
		_bluff_count = maxi(_bluff_count, 3)
		_threat_pos = src
		_set_mood(Mood.CHARGE, 6.0)
	elif was_easy:
		_spook(src, Telegraph.Threat.PANIC)
	elif mood != Mood.FLEE:
		## Everything else that gets hit runs, however it was feeling before.
		_spook(src, Telegraph.Threat.PANIC)


func _xp_orb_value() -> int:
	## Wildlife is not an XP farm. A hare is a hare.
	return 2 if float(profile.get("len", 0.5)) < 1.0 else 6


func _drops_coins() -> bool:
	return false


## ============================== Save / load ===============================


func save_dict() -> Dictionary:
	return {
		"kind": "critter", "species": species, "pos": global_position,
		"rot_y": rotation.y, "hp": health, "home": _home, "zone": _zone,
	}


static func from_dict(d: Dictionary) -> Critter:
	var c := Critter.make(String(d.get("species", "hare")))
	c._restore_hp = float(d.get("hp", c.max_health))
	c._home = d.get("home", Vector3.ZERO)
	c._zone = String(d.get("zone", "deep_woods"))
	return c
