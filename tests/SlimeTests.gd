extends SceneTree

## ===========================================================================
## SLIME TEST SUITE — the bouncing jellies (scripts/Slime.gd, Afflictions.gd,
## SlimeDirector.gd, and the wiring in Player / HitFX / CaveRegion / World)
##
##   godot --headless --path . --script res://tests/SlimeTests.gd
##
## The contract under test is Lemon's rule (2026-09-13): a slime that sees
## you hops closer, COILS (the tell), LEAPS on an arc at you, and the contact
## is the hit — then it bounces straight back OFF you and sits spent for a
## couple of seconds before it comes again. Every colour obeys it; the
## colours differ in how they hop, what the touch leaves on you, and who
## runs. So the suite drives REAL physics frames over a real floor with the
## LabPlayer standing in for you, and reads the phases as they happen:
## detect -> coil -> leap -> bounce (damage, velocity pointing away) ->
## recoup (a window that holds) -> leap again. The abilities are unit-tested
## through Afflictions against a recording stub.
##
## NOTE the await rule (docs/WILDLIFE.md): a section that awaits must be
## awaited by the caller, or the rest of it silently never runs.
## ===========================================================================

const MIN_ASSERTIONS := 150
const MAX_FRAMES := 900   ## 15 s of physics — nothing here should need it

var pass_n := 0
var fail_n := 0
var fails: Array[String] = []
var _world: Node3D
var _player: LabPlayer


class LabFloor:
	extends StaticBody3D
	func _ready() -> void:
		collision_layer = 1
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(600.0, 1.0, 600.0)
		cs.shape = box
		cs.position.y = -0.5
		add_child(cs)


class Warmth:
	extends RefCounted
	var warmth := 100.0
	var wet := 0.0


class Mark:
	extends CharacterBody3D
	## A recording stand-in with the whole surface Afflictions and a slime's
	## bounce probe for: damage with its flags, the slows, the cold model,
	## stamina, stun, swimming, and the log.
	var damage := 0.0
	var hits := 0
	var last_strong := false
	var last_throw = null
	var last_attacker: Node = null
	var status_speed_mult := 1.0
	var exposure := Warmth.new()
	var stamina := 100.0
	var stamina_delay := 0.0
	var hitstun_timer := 0.0
	var swimming := false
	var log_lines: Array = []
	func take_damage(amount: float, _from = null, strong = false, throw = null, attacker: Node = null) -> void:
		damage += amount
		hits += 1
		last_strong = bool(strong)
		last_throw = throw
		last_attacker = attacker
	func _add_log_msg(text: String, _col: Color) -> void:
		log_lines.append(text)


func ok(cond: bool, what: String) -> void:
	if cond:
		pass_n += 1
	else:
		fail_n += 1
		fails.append(what)
		print("  FAIL: ", what)


func eq(a, b, what: String) -> void:
	ok(a == b, "%s (got %s, want %s)" % [what, str(a), str(b)])


func near(a: float, b: float, tol: float, what: String) -> void:
	ok(absf(a - b) <= tol, "%s (got %.4f, want %.4f +-%.4f)" % [what, a, b, tol])


func until(cond: Callable, max_frames := MAX_FRAMES) -> int:
	## Tick physics until cond() holds. Returns frames used, or -1.
	for i in range(max_frames):
		if cond.call():
			return i
		await physics_frame
	return -1


func frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func clear_slimes() -> void:
	for s in get_nodes_in_group("slimes"):
		(s as Node).queue_free()
	await physics_frame
	await physics_frame


func _init() -> void:
	print("=== Myrkfell slime tests ===")
	GameMode.set_mode(GameMode.Mode.NORMAL)
	_world = Node3D.new()
	root.add_child(_world)
	_world.add_to_group("world")
	_world.add_child(LabFloor.new())
	_player = LabPlayer.new()
	_world.add_child(_player)
	_player.position = Vector3(0, 0.05, 0)
	await process_frame
	await physics_frame

	t_sheet()
	t_zone_roll()
	await t_body()
	await t_hop()
	await t_the_bounce()
	await t_zigzag()
	await t_recoup_window()
	t_afflictions()
	await t_abilities_on_contact()
	await t_split()
	await t_gold_runs()
	await t_tar()
	await t_parry_and_death()
	await t_hitfx()
	await t_director()
	t_wiring()

	if pass_n + fail_n < MIN_ASSERTIONS:
		fail_n += 1
		fails.append("suite ran only %d assertions (floor is %d) — a section returned early"
			% [pass_n + fail_n, MIN_ASSERTIONS])
	print("---")
	if fails.is_empty():
		print("ALL GREEN — %d assertions" % pass_n)
	else:
		print("%d/%d FAILED:" % [fail_n, pass_n + fail_n])
		for f in fails:
			print("  - ", f)
	quit(0 if fails.is_empty() else 1)


## =============================== The sheet =================================


func t_sheet() -> void:
	print(" [sheet: nine colours, one script]")
	eq(Slime.KINDS.size(), 9, "nine colours")
	eq(Slime.ORDER.size(), 9, "ORDER lists them all")
	for id in Slime.ORDER:
		ok(Slime.KINDS.has(id), "ORDER entry %s is a KINDS row" % id)
	var classes := {
		"green": SlimeGreen, "blue": SlimeBlue, "red": SlimeRed, "yellow": SlimeYellow,
		"purple": SlimePurple, "black": SlimeBlack, "white": SlimeWhite, "gold": SlimeGold,
		"pink": SlimePink,
	}
	var names := {}
	for id in classes:
		var s: Slime = (classes[id] as GDScript).new()
		eq(s.kind, id, "%s class carries its colour" % id)
		eq(s.display_name, String(Slime.KINDS[id]["name"]), "%s display name from the row" % id)
		near(s.max_health, float(Slime.KINDS[id]["hp"]), 0.001, "%s hp from the row" % id)
		ok("slime" in s.families, "%s is family 'slime'" % id)
		ok(s.monster, "%s is a monster (hunts you because that is what it is)" % id)
		ok(not s.can_climb, "%s cannot climb — it has no hands" % id)
		ok(not names.has(s.display_name), "%s has a name no other colour uses" % id)
		names[s.display_name] = true
		if id == "gold":
			eq(s.attack_damage, 0.0, "gilt never hurts anyone")
			ok(bool(Slime.KINDS[id]["flee"]), "gilt flees")
		else:
			ok(s.attack_damage > 0.0, "%s hurts on the bounce" % id)
			ok(float(Slime.KINDS[id]["recoup"]) >= 1.0, "%s recoups for at least a second after a hit" % id)
			ok(float(Slime.KINDS[id]["recoup_miss"]) < float(Slime.KINDS[id]["recoup"]),
				"%s: a miss costs less than a hit" % id)
			ok(float(Slime.KINDS[id]["leap_max"]) > float(Slime.KINDS[id]["leap_min"]), "%s has a leap band" % id)
		s.free()
	## the personalities the ask named
	ok(float(Slime.KINDS["yellow"]["zig"]) > 30.0, "the jolt skitters side to side")
	ok(float(Slime.KINDS["yellow"]["hop_rest"]) < float(Slime.KINDS["green"]["hop_rest"]) * 0.5, "and hops much faster than the green")
	eq(String(Slime.KINDS["red"]["ability"]), "burn", "the ember burns")
	ok(float(Slime.KINDS["red"]["aggro"]) > float(Slime.KINDS["green"]["aggro"]), "the ember is the more aggressive: it notices you from farther")
	ok(float(Slime.KINDS["purple"]["coil"]) > float(Slime.KINDS["green"]["coil"]), "the venom has the longest tell")
	ok(float(Slime.KINDS["purple"]["leap_max"]) > float(Slime.KINDS["green"]["leap_max"]), "and leaps from farthest out")
	ok(bool(Slime.KINDS["black"]["strong"]), "the tar breaks guard")
	ok(float(Slime.KINDS["black"]["throw"]) > 0.0, "and throws you")
	ok(float(Slime.KINDS["black"]["mass"]) > 100.0, "and is heavy")
	eq(Slime.flavor_of("Ember Slime"), String(Slime.KINDS["red"]["flavor"]), "bestiary flavour by display name")
	eq(Slime.flavor_of("Boar"), "", "and nothing for a boar")
	eq(Slime.kind_of_name("Tar Slime"), "black", "kind by display name")
	var m := Slime.make("purple")
	eq(m.kind, "purple", "make() picks a colour")
	m.free()
	var bad := Slime.make("plaid")
	eq(bad.kind, "green", "an unknown colour is a green one")
	bad.free()


func t_zone_roll() -> void:
	print(" [who lives where]")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var counts := {}
	for _i in range(300):
		var id := Slime.kind_for_zone("lake", false, rng)
		if _i == 0:
			ok(Slime.KINDS.has(id), "lake roll is a real colour")
		counts[id] = int(counts.get(id, 0)) + 1
	ok(int(counts.get("blue", 0)) > int(counts.get("green", 0)), "lakes are the blue one's")
	ok(int(counts.get("black", 0)) == 0 and int(counts.get("purple", 0)) == 0, "no tar or venom by day on a lake")
	counts.clear()
	for _i in range(300):
		var id := Slime.kind_for_zone("county", true, rng)
		counts[id] = int(counts.get(id, 0)) + 1
	ok(int(counts.get("white", 0)) > int(counts.get("green", 0)), "the County is the rime one's")
	ok(int(counts.get("purple", 0)) + int(counts.get("black", 0)) > 0, "night lets the venom and the tar out")
	ok(int(counts.get("gold", 0)) > 0 and int(counts.get("gold", 0)) < 60, "gilt is rare but real (%d/300)" % int(counts.get("gold", 0)))
	counts.clear()
	for _i in range(300):
		var id := Slime.kind_for_zone("nowhere", false, rng)
		counts[id] = int(counts.get(id, 0)) + 1
	ok(int(counts.get("green", 0)) > 100, "everywhere else is mostly green")


## ================================ The body =================================


func t_body() -> void:
	print(" [body]")
	var s := SlimeGreen.new()
	_world.add_child(s)
	s.global_position = Vector3(30, 0.1, 0)   ## far enough not to notice you
	s.wander_dir = Vector3.ZERO   ## sit still for the body checks
	s.wander_timer = 30.0
	await physics_frame
	ok(s.rig != null, "has a rig")
	ok(s.body_mat != null, "has a body material")
	eq(s.body_mat.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA, "the jelly is translucent (dithered by the skin)")
	near(s.body_mat.albedo_color.a, float(Slime.KINDS["green"]["alpha"]), 0.01, "at the colour's alpha")
	eq(s.eye_mats.size(), 2, "two eyes")
	ok(s.core != null and s._core_mat != null and s._core_mat.emission_enabled, "a glowing core")
	ok(s.skin != null, "skinned")
	ok(s.is_in_group("slimes") and s.is_in_group("enemies"), "in both groups")
	eq(s.goo_color, Slime.KINDS["green"]["col"], "bleeds its own colour")
	var col_n := 0
	for c in s.get_children():
		if c is CollisionShape3D:
			col_n += 1
	eq(col_n, 1, "one collision box")
	## scale rides the wobble, never collapses
	await frames(30)
	ok(s.rig.scale.y > 0.5 and s.rig.scale.y < 1.6, "idle scale sane (%.2f)" % s.rig.scale.y)
	ok(s.is_on_floor(), "standing on the floor (y=%.3f vel=%s phase=%s hops=%d)" % [s.global_position.y, str(s.velocity), s.phase, s.hops])
	eq(s.state, Enemy.State.CALM, "30 m away: calm")
	s.queue_free()
	await physics_frame


func t_hop() -> void:
	print(" [the hop]")
	var s := SlimeGreen.new()
	_world.add_child(s)
	s.global_position = Vector3(30, 0.1, 0)
	await frames(3)
	var x0 := s.global_position.x
	s.wander_dir = Vector3(1, 0, 0)
	s.wander_timer = 30.0
	s.hop_cd = 0.0
	var n: int = await until(func() -> bool: return s.hops >= 1)
	ok(n >= 0, "a calm jelly hops off on its wander (%d frames)" % n)
	eq(s.phase, "air", "a hop is a phase")
	await physics_frame
	await physics_frame
	ok(not s.is_on_floor(), "and it leaves the ground")
	ok(s.rig.scale.y > 1.0, "stretched in flight (%.2f)" % s.rig.scale.y)
	n = await until(func() -> bool: return s.is_on_floor() and s.phase == "rest")
	ok(n >= 0, "it lands and rests (%d frames)" % n)
	await physics_frame
	ok(s.global_position.x > x0 + 0.4, "and it went somewhere (+%.2f m)" % (s.global_position.x - x0))
	ok(s._land_t < 0.5, "the landing clock just reset")
	ok(s.rig.scale.y < 1.0, "splatted flat on landing (%.2f)" % s.rig.scale.y)
	ok(s.hop_cd > 0.3, "and it waits before the next one")
	s.queue_free()
	await physics_frame


## ============================== THE BOUNCE =================================


func t_the_bounce() -> void:
	print(" [the bounce: detect -> coil -> leap -> hit -> recoil -> recoup -> again]")
	_player.global_position = Vector3(0, 0.05, 0)
	_player.damage_taken = 0.0
	var s := SlimeGreen.new()
	_world.add_child(s)
	s.global_position = Vector3(0, 0.1, 4.0)   ## inside its 7 m notice, inside the leap band
	var n: int = await until(func() -> bool: return s.state == Enemy.State.AGITATED)
	ok(n >= 0, "DETECT: it sees you (%d frames)" % n)
	ok(s._alert_t > 0.0 or n > 2, "and startles (the alert stretch)")
	n = await until(func() -> bool: return s.phase == "coil")
	ok(n >= 0, "COIL: it winds up in the leap band (%d frames)" % n)
	ok(s.body_mat.emission_enabled, "the coil glows — the tell")
	eq(s.leaps, 0, "not launched yet")
	await frames(10)
	ok(s.rig.scale.y < 0.90, "flattening while it coils (%.2f)" % s.rig.scale.y)
	ok(Vector2(s.velocity.x, s.velocity.z).length() < 0.5, "rooted while it coils")
	n = await until(func() -> bool: return s.phase == "leap")
	ok(n >= 0, "LEAP: it launches (%d frames)" % n)
	eq(s.leaps, 1, "one leap counted")
	ok(s.velocity.y > 2.0 or s._leap_t > 0.1, "up, on an arc")
	var to := (_player.global_position - s.global_position)
	to.y = 0.0
	ok(Vector2(s.velocity.x, s.velocity.z).normalized().dot(Vector2(to.x, to.z).normalized()) > 0.9, "aimed at you")
	ok(not s.body_mat.emission_enabled, "the glow goes out on launch")
	n = await until(func() -> bool: return s.bounces >= 1)
	ok(n >= 0, "HIT: the arc finds you (%d frames)" % n)
	ok(_player.damage_taken >= float(Slime.KINDS["green"]["dmg"]) - 0.01, "the contact is the damage (%.1f)" % _player.damage_taken)
	eq(s.phase, "recoil", "RECOIL: and it is flying back off you")
	var away := s.global_position - _player.global_position
	away.y = 0.0
	ok(Vector2(s.velocity.x, s.velocity.z).dot(Vector2(away.x, away.z)) > 0.0, "velocity points AWAY from you")
	ok(s.velocity.y > 0.0, "and up")
	var dmg_after_hit := _player.damage_taken
	n = await until(func() -> bool: return s.phase == "recoup")
	ok(n >= 0, "RECOUP: it lands spent (%d frames)" % n)
	near(s._recoup_t, float(Slime.KINDS["green"]["recoup"]), 0.1, "for the colour's full recoup")
	var d0 := s.global_position.distance_to(_player.global_position)
	ok(d0 > 1.0, "having backed off you (%.1f m)" % d0)
	await frames(60)   ## a second into the window
	eq(s.phase, "recoup", "still recouping a second later — the window holds")
	eq(s.leaps, 1, "no second leap inside the window")
	eq(_player.damage_taken, dmg_after_hit, "and no damage inside it")
	ok(Vector2(s.velocity.x, s.velocity.z).length() < 0.3, "sitting still")
	n = await until(func() -> bool: return s.leaps >= 2, 600)
	ok(n >= 0, "AGAIN: it comes a second time after the window (%d frames)" % n)
	ok(s.bounces >= 1, "bounces counted: %d" % s.bounces)
	s.queue_free()
	await physics_frame


func t_zigzag() -> void:
	print(" [the jolt skitters]")
	_player.global_position = Vector3(0, 0.05, 0)
	_player.damage_taken = 0.0
	var s := SlimeYellow.new()
	_world.add_child(s)
	s.global_position = Vector3(0, 0.1, 9.0)   ## inside its 13 m notice, outside its 4.5 m leap
	var dirs: Array = []
	var seen := 0
	var f := 0
	while f < MAX_FRAMES and s.leaps == 0 and dirs.size() < 4:
		if s.hops > seen:
			seen = s.hops
			dirs.append(s._hop_dir)
		await physics_frame
		f += 1
	ok(dirs.size() >= 3, "several approach hops before the leap (%d)" % dirs.size())
	var toward := Vector3(0, 0, -1)   ## from z=9 to the player at 0
	var alternated := true
	var progressing := true
	for i in range(dirs.size()):
		var d: Vector3 = dirs[i]
		if d.dot(toward) < 0.2:
			progressing = false
		if i > 0:
			var a: float = (dirs[i - 1] as Vector3).cross(toward).y
			var b: float = d.cross(toward).y
			if signf(a) == signf(b):
				alternated = false
	ok(progressing, "every hop still closes on you")
	ok(alternated, "and they alternate left / right — the skitter")
	var off := 0.0
	for d in dirs:
		off = maxf(off, absf((d as Vector3).x))
	ok(off > 0.6, "well off the line (max side component %.2f)" % off)
	var n: int = await until(func() -> bool: return s.leaps >= 1, 600)
	ok(n >= 0, "then it leaps (%d frames)" % n)
	s.queue_free()
	await physics_frame


func t_recoup_window() -> void:
	print(" [the window is real]")
	var s := SlimeBlue.new()
	_world.add_child(s)
	s.global_position = Vector3(0, 0.1, 3.0)
	await until(func() -> bool: return s.phase == "recoup", 600)
	eq(s.phase, "recoup", "a blue lands in recoup after its first leap")
	var hp := s.health
	s.take_damage(5.0)
	ok(s.health < hp, "a hit lands while it is spent")
	eq(s.phase, "recoup", "and it stays spent")
	ok(s._recoup_t >= 0.6, "for at least a beat more")
	## a hit mid-coil cancels the leap
	var c := SlimeGreen.new()
	_world.add_child(c)
	c.global_position = Vector3(0, 0.1, -3.0)
	var n: int = await until(func() -> bool: return c.phase == "coil", 600)
	ok(n >= 0, "a second green coils")
	c.take_damage(3.0)
	eq(c.phase, "rest", "a hit in the coil cancels the leap")
	ok(not c.body_mat.emission_enabled, "and the glow")
	eq(c.leaps, 0, "no leap came of it")
	s.queue_free()
	c.queue_free()
	await physics_frame


## ============================== Afflictions ================================


func t_afflictions() -> void:
	print(" [afflictions]")
	var m := Mark.new()
	_world.add_child(m)
	m.global_position = Vector3(50, 0.1, 50)
	## burn: ticks, then ends
	Afflictions.apply(m, "burn", Slime.BURN_SECONDS, Slime.BURN_DPS)
	var a := Afflictions.on(m)
	ok(a != null and a.get_parent() == m, "the node attaches to the player")
	ok(a.has("burn"), "burning")
	eq(m.log_lines.size(), 1, "one log line for it")
	for _i in range(int(Slime.BURN_SECONDS / 0.05) + 2):
		a.step(0.05)
	ok(not a.has("burn"), "the burn ends on its clock")
	near(m.damage, Slime.BURN_SECONDS * Slime.BURN_DPS, Slime.BURN_DPS * Afflictions.TICK + 0.01,
		"and dealt about dps x seconds (%.1f)" % m.damage)
	ok(m.last_attacker == null, "burn damage is the world's (no attacker: full price in every mode)")
	## refresh keeps the longer clock and the hotter rate
	a.add("burn", 2.0, 1.0)
	a.add("burn", 5.0, 3.0)
	a.add("burn", 1.0, 2.0)
	near(float(a.active["burn"]["t"]), 5.0, 0.001, "refresh keeps the longer clock")
	near(float(a.active["burn"]["power"]), 3.0, 0.001, "and the stronger power")
	eq(m.log_lines.size(), 2, "a refresh does not log again")
	## water puts it out
	m.swimming = true
	a.step(0.01)
	ok(not a.has("burn"), "swimming puts the fire out")
	m.swimming = false
	## slows
	a.add("gummed", Slime.GUMMED_SECONDS, Slime.GUMMED_MULT)
	near(m.status_speed_mult, Slime.GUMMED_MULT, 0.001, "gummed halves the walk")
	a.add("chill", Slime.CHILL_SECONDS, Slime.CHILL_MULT)
	near(m.status_speed_mult, Slime.GUMMED_MULT * Slime.CHILL_MULT, 0.001, "gummed AND chilled multiply")
	for _i in range(int(Slime.CHILL_SECONDS / 0.05) + 2):
		a.step(0.05)
	near(m.status_speed_mult, Slime.GUMMED_MULT, 0.001, "chill wears off first")
	for _i in range(40):
		a.step(0.05)
	near(m.status_speed_mult, 1.0, 0.001, "then the gum — full speed again")
	ok(a.active.is_empty(), "nothing left on you")
	## poison
	var dmg0 := m.damage
	a.add("poison", 2.0, 2.0)
	for _i in range(41):
		a.step(0.05)
	near(m.damage - dmg0, 4.0, 2.0 * Afflictions.TICK + 0.01, "poison ticks its dps too")
	## shock: instant
	m.stamina = 50.0
	Afflictions.shock(m, Slime.SHOCK_STUN, Slime.SHOCK_STAMINA)
	near(m.hitstun_timer, Slime.SHOCK_STUN, 0.001, "shock locks the legs")
	near(m.stamina, 50.0 - Slime.SHOCK_STAMINA, 0.001, "and takes the wind out of you")
	m.stamina = 5.0
	Afflictions.shock(m, 0.1, Slime.SHOCK_STAMINA)
	eq(m.stamina, 0.0, "stamina floors at zero")
	## soak: wet, and it douses
	a.add("burn", 4.0, 3.0)
	Afflictions.soak(m, Slime.SOAK_WET)
	near(m.exposure.wet, Slime.SOAK_WET, 0.001, "soak wets you (Exposure counts it)")
	ok(not a.has("burn"), "and puts a burn out")
	Afflictions.soak(m, 0.9)
	near(m.exposure.wet, 1.0, 0.001, "wet caps at 1")
	## chill drains warmth
	Afflictions.drain_warmth(m, Slime.CHILL_WARMTH)
	near(m.exposure.warmth, 100.0 - Slime.CHILL_WARMTH, 0.001, "the rime pulls warmth out")
	Afflictions.drain_warmth(m, 500.0)
	eq(m.exposure.warmth, 0.0, "warmth floors at zero")
	## unknown kinds are ignored, a bare player is safe
	a.add("hiccups", 3.0, 1.0)
	ok(not a.has("hiccups"), "unknown afflictions are refused")
	var bare := Node.new()
	_world.add_child(bare)
	Afflictions.shock(bare, 1.0, 1.0)
	Afflictions.soak(bare, 1.0)
	Afflictions.drain_warmth(bare, 1.0)
	Afflictions.apply(bare, "burn", 1.0, 1.0)
	ok(Afflictions.on(bare) != null, "a player with none of the fields still takes the node without error")
	bare.queue_free()
	m.queue_free()


func t_abilities_on_contact() -> void:
	print(" [what the touch leaves]")
	var m := Mark.new()
	_world.add_child(m)
	m.global_position = Vector3(60, 0.1, 60)
	await physics_frame
	var table := {
		"red": "burn", "purple": "poison", "black": "gummed", "white": "chill",
	}
	for id in table:
		var s := Slime.make(id)
		_world.add_child(s)
		s.global_position = m.global_position + Vector3(0, 0.1, 1.0)
		await physics_frame
		var before := m.hits
		var warm0 := m.exposure.warmth
		s._bounce(m, Vector3(0, 0, -1))
		eq(m.hits, before + 1, "%s: the bounce hits once" % id)
		eq(m.last_attacker, s, "%s: the slime owns the hit" % id)
		ok(Afflictions.on(m).has(String(table[id])), "%s leaves %s" % [id, table[id]])
		eq(s.phase, "recoil", "%s recoils" % id)
		eq(s.bounces, 1, "%s counted the bounce" % id)
		if id == "black":
			ok(m.last_strong, "tar breaks guard")
			ok(m.last_throw is Vector3 and (m.last_throw as Vector3).length() > 5.0, "and throws you")
		else:
			ok(not m.last_strong, "%s does not break guard" % id)
		if id == "white":
			near(m.exposure.warmth, warm0 - Slime.CHILL_WARMTH, 0.001, "rime drains warmth on the touch")
		Afflictions.on(m).clear_all()
		s.queue_free()
		await physics_frame
	## shock, soak, leech
	var y := Slime.make("yellow")
	_world.add_child(y)
	y.global_position = m.global_position + Vector3(0, 0.1, 1.0)
	await physics_frame
	m.stamina = 100.0
	y._bounce(m, Vector3(0, 0, -1))
	near(m.hitstun_timer, Slime.SHOCK_STUN, 0.001, "jolt shocks: legs locked")
	near(m.stamina, 100.0 - Slime.SHOCK_STAMINA, 0.001, "and stamina gone")
	y.queue_free()
	var b := Slime.make("blue")
	_world.add_child(b)
	b.global_position = m.global_position + Vector3(0, 0.1, 1.0)
	await physics_frame
	m.exposure.wet = 0.0
	Afflictions.apply(m, "burn", 4.0, 3.0)
	b._bounce(m, Vector3(0, 0, -1))
	near(m.exposure.wet, Slime.SOAK_WET, 0.001, "blue soaks you")
	ok(not Afflictions.on(m).has("burn"), "and the fire is out")
	b.queue_free()
	var p := Slime.make("pink")
	_world.add_child(p)
	p.global_position = m.global_position + Vector3(0, 0.1, 1.0)
	await physics_frame
	p.health = 10.0
	p._bounce(m, Vector3(0, 0, -1))
	near(p.health, 10.0 + p.attack_damage * Slime.LEECH_MULT, 0.001, "the leech drinks the hit back")
	p.health = p.max_health - 1.0
	p._bounce(m, Vector3(0, 0, -1))
	near(p.health, p.max_health, 0.001, "but never past full")
	p.queue_free()
	m.queue_free()
	await physics_frame


## ============================= Personalities ===============================


func t_split() -> void:
	print(" [the green splits]")
	await clear_slimes()
	var s := SlimeGreen.new()
	_world.add_child(s)
	s.global_position = Vector3(40, 0.1, 0)
	await physics_frame
	var before := get_nodes_in_group("slimes").size()
	s.take_damage(1000.0)
	ok(s.dying, "dead")
	await physics_frame
	var now := get_nodes_in_group("slimes")
	eq(now.size(), before + 2, "two out of one")
	var kids: Array = []
	for n in now:
		if n != s and n is Slime and (n as Slime).size_k < 0.9:
			kids.append(n)
	eq(kids.size(), 2, "both are the small kind")
	for kid in kids:
		var ks := kid as Slime
		eq(ks.kind, "green", "still green")
		near(ks.size_k, Slime.SPLIT_SIZE, 0.001, "at the split size")
		near(ks.max_health, float(Slime.KINDS["green"]["hp"]) * Slime.SPLIT_HP, 0.01, "with the split health")
		ok(ks.provoked, "and already angry")
	## the small ones do not split again
	var n2 := now.size()
	(kids[0] as Slime).take_damage(1000.0)
	await physics_frame
	eq(get_nodes_in_group("slimes").size(), n2, "a half does not halve again")
	## a blue does not split at all
	var b := SlimeBlue.new()
	_world.add_child(b)
	b.global_position = Vector3(44, 0.1, 0)
	await physics_frame
	var n3 := get_nodes_in_group("slimes").size()
	b.take_damage(1000.0)
	await physics_frame
	eq(get_nodes_in_group("slimes").size(), n3, "only the green splits")
	await clear_slimes()


func t_gold_runs() -> void:
	print(" [the gilt runs]")
	_player.global_position = Vector3(0, 0.05, 0)
	var g := SlimeGold.new()
	_world.add_child(g)
	g.global_position = Vector3(0, 0.1, 5.0)
	var n: int = await until(func() -> bool: return g.state == Enemy.State.AGITATED)
	ok(n >= 0, "it notices you")
	var d0 := g.global_position.distance_to(_player.global_position)
	await frames(120)
	var d1 := g.global_position.distance_to(_player.global_position)
	ok(d1 > d0 + 3.0, "and it is LEAVING (%.1f -> %.1f m)" % [d0, d1])
	eq(g.leaps, 0, "it never leaps at you")
	ok(g.hops >= 2, "in bounds (%d)" % g.hops)
	ok(g._drops_coins(), "it carries a purse")
	var gr := SlimeGreen.new()
	ok(not gr._drops_coins(), "a green carries nothing")
	gr.free()
	g.queue_free()
	await physics_frame


func t_tar() -> void:
	print(" [the tar does not go over]")
	var t := SlimeBlack.new()
	_world.add_child(t)
	t.global_position = Vector3(50, 0.1, 0)
	await frames(3)
	var ph := t.phase
	t.knockdown(Vector3(5, 0, 0), 2.0)
	eq(t.phase, ph, "a trample does nothing to it")
	ok(not t.knocked, "and it is not down")
	ok(t.velocity.y < 1.0, "and it did not fly")
	var gr := SlimeGreen.new()
	_world.add_child(gr)
	gr.global_position = Vector3(52, 0.1, 0)
	await frames(3)
	gr.knockdown(Vector3(5, 0, 0), 2.0)
	ok(gr.velocity.y > 2.0, "a green gets flung instead of ragdolled")
	eq(gr.phase, "air", "into the air")
	ok(not gr.knocked, "it has no bones to lie on")
	t.queue_free()
	gr.queue_free()
	await physics_frame


func t_parry_and_death() -> void:
	print(" [parried, and the splat]")
	_player.global_position = Vector3(0, 0.05, 0)
	var s := SlimePink.new()
	_world.add_child(s)
	s.global_position = Vector3(0, 0.1, 3.0)
	var n: int = await until(func() -> bool: return s.phase == "leap", 600)
	ok(n >= 0, "a leech leaps")
	s.on_parried()
	eq(s.phase, "recoil", "the parry bounces it off the shield")
	ok(s.leap_hit, "and that leap is spent")
	var away := s.global_position - _player.global_position
	away.y = 0.0
	ok(Vector2(s.velocity.x, s.velocity.z).dot(Vector2(away.x, away.z)) > 0.0, "flying away")
	## death: a splat, then gone
	var before := _world.get_child_count()
	s.take_damage(1000.0)
	ok(s.dying, "dead")
	ok(not s.skin.visible, "the jelly is gone from view")
	ok(_world.get_child_count() > before, "and a burst of goo took its place")
	await frames(75)
	ok(not is_instance_valid(s), "the node frees itself after the splat")


func t_hitfx() -> void:
	print(" [it bleeds goo]")
	var s := SlimeRed.new()
	_world.add_child(s)
	s.global_position = Vector3(70, 0.1, 0)
	await physics_frame
	var kind := HitFX.kind_of(s)
	ok(kind.begins_with("slime:"), "a slime is its own kind of hit (%s)" % kind)
	var col := Color.html(kind.substr(6))
	var want: Color = Slime.KINDS["red"]["col"]
	ok(absf(col.r - want.r) < 0.01 and absf(col.g - want.g) < 0.01 and absf(col.b - want.b) < 0.01, "in its own colour")
	var fx := HitFX.for_creature(kind, Vector3.ZERO, Vector3.UP, 1.0)
	ok(fx != null, "for_creature pours goo")
	var parts := 0
	for c in fx.get_children():
		if c is CPUParticles3D:
			parts += 1
	eq(parts, 2, "two bursts: gobbets and spray")
	fx.free()
	var gob := Goblin.new()
	eq(HitFX.kind_of(gob), "flesh", "a goblin still bleeds")
	gob.free()
	s.queue_free()
	await physics_frame


func t_director() -> void:
	print(" [the director]")
	await clear_slimes()
	_player.global_position = Vector3(0, 0.05, 0)
	var d := SlimeDirector.new()
	_world.add_child(d)
	d.player = _player
	d._t = 9999.0   ## no rolls of its own during the test
	eq(d.zone_at(Vector3.ZERO), "deep_woods", "no map: the woods")
	ok(not d.is_night(), "no clock: noon")
	var made: Array = d.spawn_pocket(Vector3(20, 0, 0), "green")
	ok(made.size() >= SlimeDirector.POCKET.x and made.size() <= SlimeDirector.POCKET.y, "a pocket is %d..%d (%d)" % [SlimeDirector.POCKET.x, SlimeDirector.POCKET.y, made.size()])
	eq(d.live.size(), made.size(), "tracked")
	await physics_frame
	for s in made:
		eq((s as Slime).kind, "green", "the asked-for colour")
		ok((s as Slime).is_on_floor() or (s as Slime).global_position.y < 1.0, "on the ground")
	var c := d.census()
	eq(int(c["live"]), made.size(), "census counts them")
	eq(int(c["by_kind"]["green"]), made.size(), "by colour")
	var gold: Array = d.spawn_pocket(Vector3(24, 0, 0), "gold")
	eq(gold.size(), 1, "gilt is always alone")
	var full: Array = d.spawn_pocket(Vector3(26, 0, 0), "blue")
	ok(d.live.size() <= SlimeDirector.BUDGET, "the budget holds (%d)" % d.live.size())
	ok(full.size() <= SlimeDirector.BUDGET - made.size() - 1, "the last pocket was trimmed to it")
	## culling
	_player.global_position = Vector3(400, 0.05, 0)
	d._cull()
	eq(d.live.size(), 0, "far behind you, they are culled")
	await physics_frame
	await physics_frame
	eq(get_nodes_in_group("slimes").size(), 0, "and gone")
	_player.global_position = Vector3(0, 0.05, 0)
	## a rolled pocket is a real colour
	var rolled: Array = d.spawn_pocket(Vector3(30, 0, 0))
	ok(rolled.size() >= 1, "a rolled pocket spawns")
	ok(Slime.KINDS.has((rolled[0] as Slime).kind), "of a real colour (%s)" % (rolled[0] as Slime).kind)
	d.queue_free()
	await clear_slimes()


func t_wiring() -> void:
	print(" [wiring]")
	var player_src := FileAccess.get_file_as_string("res://scripts/Player.gd")
	ok(player_src.contains("func _slime_types() -> Array:"), "Player: the slime list")
	ok(player_src.contains('_menu_head(vb, "SLIMES")'), "Player: the M menu has a SLIMES heading")
	ok(player_src.contains("] + _slime_types()"), "Player: the bestiary knows them")
	ok(player_src.contains("Slime.flavor_of(nm)"), "Player: the bestiary reads the colour's flavour")
	ok(player_src.contains("var status_speed_mult := 1.0"), "Player: the slow variable")
	ok(player_src.contains("speed *= status_speed_mult"), "Player: and the walk reads it")
	for cls in ["SlimeGreen", "SlimeBlue", "SlimeRed", "SlimeYellow", "SlimePurple", "SlimeBlack", "SlimeWhite", "SlimeGold", "SlimePink"]:
		ok(player_src.contains(cls), "Player: menu row for %s" % cls)
	var cave_src := FileAccess.get_file_as_string("res://scripts/CaveRegion.gd")
	ok(cave_src.contains("_spawn_pack(c, SlimeGreen"), "CaveRegion: green pockets in the shallows")
	ok(cave_src.contains("_spawn_pack(c, SlimePurple"), "CaveRegion: venom in the middle")
	ok(cave_src.contains("_spawn_pack(c, SlimeRed"), "CaveRegion: ember in the deeps")
	ok(cave_src.contains("_spawn_pack(c, SlimeBlack, 1)"), "CaveRegion: one tar in the dark")
	var world_src := FileAccess.get_file_as_string("res://scripts/World.gd")
	ok(world_src.contains("_slimes = SlimeDirector.new()"), "World: the director is built")
	ok(world_src.contains("_slimes.bind_world(self)"), "World: and bound")
	ok(world_src.contains("func slimes() -> SlimeDirector:"), "World: and reachable")
	var fx_src := FileAccess.get_file_as_string("res://scripts/HitFX.gd")
	ok(fx_src.contains("static func goo("), "HitFX: goo exists")
	ok(fx_src.contains('"slime:" + gc.to_html(false)'), "HitFX: kind_of carries the colour")
