extends SceneTree

## ===========================================================================
## GAME MODE TEST SUITE — Peaceful / Normal / Hardcore
##
##   godot --headless --path . --script res://tests/GameModeTests.gd
##
## Same discipline as the wildlife and tree suites: every assertion is here
## because it is the kind of thing that breaks silently. "Peaceful is quiet"
## proves nothing — "a boar three metres away, ticked for two seconds, is
## still CALM, and the same boar after one hit is AGITATED" proves the gate.
##
## 2026-08-29 v2: the cave rule and the surface amnesty (Lemon). On Peaceful
## a monster is exempt ONLY while underground (GameMode.mob_in_cave), and the
## switch itself pardons everything outside a cave on the spot. Plus the
## bear's contact specials (grab / press) — picked, gated, and posed.
##
## NOTE the await rule (docs/WILDLIFE.md): the moment a section contains an
## `await` it is a coroutine, and calling it bare runs it up to the first
## yield and silently drops the rest. Every section below that awaits is
## awaited by the caller.
## ===========================================================================

const MIN_ASSERTIONS := 110

var pass_n := 0
var fail_n := 0
var fails: Array[String] = []
var _world: Node3D
var _player: LabPlayer


class FakeCave:
	extends Node3D
	## A 40 m shaft of "underground" below this node — answers the same
	## contains_point contract CaveRegion does, through the same group.
	func _ready() -> void:
		add_to_group("cave_regions")
	func contains_point(p: Vector3) -> bool:
		if p.y >= -2.0:
			return false
		return Vector2(p.x - global_position.x, p.z - global_position.z).length() < 40.0


class GrabMark:
	extends CharacterBody3D
	## The full manhandle surface the bear probes for, recording every call.
	var grabbed := 0
	var released := 0
	var pressed := 0
	var press_ended := 0
	var damage := 0.0
	var kd_phase := ""
	var mount = null
	func creature_grab(_a: Node3D, dmg: float) -> String:
		grabbed += 1
		damage += dmg
		return "grabbed"
	func grab_release(_v: Vector3) -> void:
		released += 1
	func creature_press(_a: Node3D) -> bool:
		pressed += 1
		return true
	func creature_press_end(_v: Vector3) -> void:
		press_ended += 1
	func take_damage(amount: float, _f = null, _s = false, _t = null, _at: Node = null) -> void:
		damage += amount


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


func _init() -> void:
	print("=== Myrkfell game-mode tests ===")
	_world = Node3D.new()
	root.add_child(_world)
	_world.add_to_group("world")
	_player = LabPlayer.new()
	_world.add_child(_player)
	_player.global_position = Vector3.ZERO

	await process_frame

	t_switch()
	t_who_is_a_monster()
	t_numbers()
	await t_the_gate()
	await t_surface_amnesty()
	await t_the_bear()
	await t_bear_moves()
	t_the_seal()

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
	GameMode.set_mode(GameMode.Mode.NORMAL)
	quit(0 if fails.is_empty() else 1)


## ============================== The switch =================================


func t_switch() -> void:
	print(" [switch]")
	eq(GameMode.KEYS.size(), 3, "three modes, no more")
	eq(GameMode.NAMES.size(), 3, "three names to match")
	eq(GameMode.Mode.NORMAL, 1, "Normal is the middle one (settings.cfg stores the KEY, but the UI stores the int)")

	GameMode.set_mode(GameMode.Mode.PEACEFUL)
	ok(GameMode.is_peaceful(), "peaceful is peaceful")
	ok(not GameMode.is_hardcore(), "and is not hardcore")
	eq(GameMode.key(), "peaceful", "key() round-trips")
	eq(GameMode.mode_name(), "Peaceful", "and it has a display name")

	GameMode.set_mode(GameMode.Mode.HARDCORE)
	ok(GameMode.is_hardcore(), "hardcore is hardcore")
	ok(not GameMode.is_peaceful(), "and is not peaceful")

	GameMode.set_mode(GameMode.Mode.NORMAL)
	ok(not GameMode.is_peaceful() and not GameMode.is_hardcore(), "normal is neither")

	for k: String in GameMode.KEYS:
		GameMode.set_mode(GameMode.from_key(k))
		eq(GameMode.key(), k, "from_key/key round-trip for '%s'" % k)
	eq(GameMode.from_key("nonsense"), GameMode.Mode.NORMAL, "an unreadable settings file lands on Normal")
	eq(GameMode.from_key(""), GameMode.Mode.NORMAL, "so does an empty one")

	GameMode.set_mode(99)
	eq(GameMode.mode, GameMode.Mode.HARDCORE, "set_mode clamps up")
	GameMode.set_mode(-5)
	eq(GameMode.mode, GameMode.Mode.PEACEFUL, "and clamps down")

	## Leaving hardcore lifts the SESSION seal (the file's tombstone does not).
	GameMode.set_mode(GameMode.Mode.HARDCORE)
	GameMode.run_lost = true
	GameMode.set_mode(GameMode.Mode.NORMAL)
	ok(not GameMode.run_lost, "switching out of Hardcore lifts the session seal")
	GameMode.set_mode(GameMode.Mode.NORMAL)


## =========================== Monster or animal =============================


func t_who_is_a_monster() -> void:
	print(" [monster or animal]")
	var monsters := {"Goblin": Goblin, "Kobold": Kobold, "Orc": Orc,
		"Ogre": Ogre, "Skeleton": Skeleton, "DarkKnight": DarkKnight}
	for nm: String in monsters:
		var m: Enemy = (monsters[nm] as GDScript).new()
		ok(m.monster, "%s is a monster — the caves stay dangerous" % nm)
		ok(GameMode.is_monster(m), "and GameMode agrees about the %s" % nm)
		ok(GameMode.is_creature(m), "and it is alive")
		ok(not m.provoked, "a fresh %s has no grudge yet" % nm)
		m.free()

	var boar := Boar.new()
	ok(not boar.monster, "a boar is an ANIMAL — Peaceful leaves it alone")
	ok(GameMode.is_creature(boar), "but it is still alive")
	ok(not GameMode.is_monster(boar), "and GameMode does not call it a monster")
	boar.free()

	var horse := Horse.new()
	ok(not horse.monster, "a horse is an animal")
	horse.free()

	var bear := Critter.make("black_bear")
	ok(not bear.monster, "and so is the bear, however it behaves")
	ok(GameMode.is_creature(bear), "the whole dex is alive")
	bear.free()

	## The duck-typing that makes the whole file work: no attacker at all is
	## the world, and the world is not a creature.
	ok(not GameMode.is_creature(null), "null is not a creature (falls, fire, a trunk on your back)")
	var plain := Node3D.new()
	ok(not GameMode.is_creature(plain), "a plain node is not a creature either")
	plain.free()
	ok(not GameMode.is_monster(null), "and null is certainly not a monster")
	ok(not GameMode.mob_in_cave(null), "null is nowhere, let alone in a cave")


## =============================== The dials =================================


func t_numbers() -> void:
	print(" [numbers]")
	var gob := Goblin.new()

	GameMode.set_mode(GameMode.Mode.NORMAL)
	near(GameMode.creature_damage_mult(gob), 1.0, 0.001, "Normal touches nothing")
	near(GameMode.heal_rate_mult(), 1.0, 0.001, "Normal heals at the tuned rate")
	near(GameMode.heal_delay_mult(), 1.0, 0.001, "and waits the tuned delay")
	near(GameMode.swarm_damage_mult(), 1.0, 0.001, "and the blackflies bite")
	near(GameMode.aggro_mult(gob), 1.0, 0.001, "and the goblin's eyes are its own")
	eq(GameMode.pack_count(6), 6, "and a pack of six is six")

	GameMode.set_mode(GameMode.Mode.PEACEFUL)
	near(GameMode.creature_damage_mult(gob), GameMode.PEACE_CREATURE_DAMAGE, 0.001,
		"Peaceful softens a creature's blow")
	near(GameMode.creature_damage_mult(null), 1.0, 0.001,
		"but NOT the ground at the end of a fall — no attacker, full price")
	ok(GameMode.heal_rate_mult() > 1.0, "Peaceful closes wounds faster")
	ok(GameMode.heal_delay_mult() < 1.0, "and starts sooner")
	near(GameMode.swarm_damage_mult(), 0.0, 0.001, "and the blackflies stop taking blood")
	near(GameMode.aggro_mult(gob), GameMode.PEACE_MONSTER_AGGRO, 0.001,
		"a cave dweller notices you late")
	eq(GameMode.pack_count(6), 3, "half a pack of six")
	eq(GameMode.pack_count(2), 1, "half a pack of two")
	eq(GameMode.pack_count(1), 1, "a lone dark knight is still a dark knight")
	eq(GameMode.pack_count(0), 0, "and nothing stays nothing")

	GameMode.set_mode(GameMode.Mode.HARDCORE)
	ok(GameMode.creature_damage_mult(gob) > 1.0, "Hardcore leans on you")
	near(GameMode.creature_damage_mult(null), 1.0, 0.001, "the world is the world in every mode")
	ok(GameMode.heal_rate_mult() < 1.0, "Hardcore closes wounds slower")
	ok(GameMode.heal_delay_mult() > 1.0, "and makes you wait for it")
	eq(GameMode.pack_count(6), 6, "Hardcore does not thin the packs")

	gob.free()
	GameMode.set_mode(GameMode.Mode.NORMAL)


## ================================ The gate =================================


func t_the_gate() -> void:
	print(" [the gate: who may start it]")

	## ------------------------------- the animal ---------------------------
	var boar := Boar.new()
	_world.add_child(boar)
	boar.global_position = Vector3(0, 0, 3.0)   ## well inside its 8 m notice
	_player.global_position = Vector3.ZERO
	GameMode.set_mode(GameMode.Mode.NORMAL, self)
	for _i in range(14):
		await physics_frame
	eq(boar.state, Enemy.State.AGITATED, "NORMAL: the boar wakes up on its own")

	GameMode.set_mode(GameMode.Mode.PEACEFUL, self)
	eq(boar.state, Enemy.State.CALM, "the switch SETTLES the boar that was already coming")
	for _i in range(20):
		await physics_frame
	eq(boar.state, Enemy.State.CALM, "PEACEFUL: 20 frames nose-to-nose and it never starts it")
	ok(not GameMode.may_engage(boar, _player), "may_engage refuses it")
	ok(not boar.provoked, "because you have never touched it")

	## Hit it, and it is an animal again — for the rest of THIS peace.
	boar.take_damage(1.0)   ## a bare call is exactly how the player's sword arrives
	ok(boar.provoked, "one swing provokes it")
	ok(GameMode.may_engage(boar, _player), "and a provoked animal may fight back")
	for _i in range(14):
		await physics_frame
	eq(boar.state, Enemy.State.AGITATED, "PEACEFUL: the boar you hit IS a fight")
	boar._set_agitated(false)
	for _i in range(8):
		await physics_frame
	ok(boar.provoked, "and the grudge holds while the mode holds")

	## ------------------------- a second, untouched one --------------------
	var boar2 := Boar.new()
	_world.add_child(boar2)
	boar2.global_position = Vector3(0, 0, 6.0)
	await physics_frame
	ok(not GameMode.may_engage(boar2, _player), "PEACEFUL: the second boar will not start it either")
	for _i in range(14):
		await physics_frame
	eq(boar2.state, Enemy.State.CALM, "and fourteen frames prove it")

	GameMode.set_mode(GameMode.Mode.HARDCORE, self)
	ok(GameMode.may_engage(boar2, _player), "HARDCORE: the gate is open again")
	for _i in range(16):
		await physics_frame
	eq(boar2.state, Enemy.State.AGITATED, "HARDCORE: the unprovoked boar comes anyway")
	GameMode.set_mode(GameMode.Mode.PEACEFUL, self)
	eq(boar2.state, Enemy.State.CALM, "and Peaceful calls it straight back off")

	## --------------- infighting is never counted against you --------------
	boar2.take_damage(1.0, null, false, null, boar)
	ok(not boar2.provoked, "another creature's swing is that creature's problem, not yours")
	ok(not GameMode.may_engage(boar2, _player), "so it still will not start on you")
	ok(GameMode.may_engage(boar2, boar), "but nothing about Peaceful stops the two of THEM")

	boar.queue_free()
	boar2.queue_free()
	await physics_frame

	## ------------------------------ the monster ---------------------------
	## THE CAVE RULE (Lemon, 2026-08-29): on Peaceful a monster is exempt
	## only while it is actually underground. In daylight it is off the clock.
	var gob := Goblin.new()
	_world.add_child(gob)
	gob.global_position = Vector3(300, 0, 303.0)
	_player.global_position = Vector3(300, 0, 300)
	for _i in range(18):
		await physics_frame
	eq(gob.state, Enemy.State.CALM,
		"PEACEFUL: a goblin in DAYLIGHT never starts it — the exemption lives underground")
	ok(not GameMode.may_engage(gob, _player), "may_engage refuses the surfaced monster")
	ok(not GameMode.mob_in_cave(gob), "because it is not in any cave")
	near(GameMode.aggro_mult(gob), GameMode.PEACE_MONSTER_AGGRO, 0.001,
		"its eyesight is still dimmed, for whenever it goes back down")

	## Underground, the same monster is the same old problem.
	var cave := FakeCave.new()
	_world.add_child(cave)
	cave.global_position = Vector3(600, 0, 600)
	var gob2 := Goblin.new()
	_world.add_child(gob2)
	gob2.global_position = Vector3(600, -8, 603.0)
	_player.global_position = Vector3(600, -8, 600)
	await physics_frame
	ok(GameMode.mob_in_cave(gob2), "the deep goblin reads as in-cave")
	ok(GameMode.may_engage(gob2, _player), "and may_engage lets it straight through")
	for _i in range(18):
		await physics_frame
	eq(gob2.state, Enemy.State.AGITATED,
		"PEACEFUL: down in the dark it hunts you anyway — a cave that cannot hurt you is just a room")
	gob.queue_free()
	gob2.queue_free()
	cave.queue_free()

	GameMode.set_mode(GameMode.Mode.NORMAL, self)
	_player.global_position = Vector3.ZERO
	await physics_frame


## ========================= The surface amnesty =============================


func t_surface_amnesty() -> void:
	print(" [the switch: surface amnesty]")
	GameMode.set_mode(GameMode.Mode.NORMAL, self)
	var boar := Boar.new()
	_world.add_child(boar)
	boar.global_position = Vector3(1200, 0, 1203)
	_player.global_position = Vector3(1200, 0, 1200)
	await physics_frame
	boar.take_damage(1.0)   ## the player's signature
	ok(boar.provoked, "provoked in Normal")

	GameMode.set_mode(GameMode.Mode.PEACEFUL, self)
	ok(not boar.provoked, "the switch pardons the surface ON THE SPOT — grudge wiped")
	eq(boar.state, Enemy.State.CALM, "and it stands down the same frame")
	ok(not GameMode.may_engage(boar, _player), "the gate is shut again")
	boar.take_damage(1.0)
	ok(boar.provoked, "hit it AGAIN on Peaceful and it is a real animal again — the amnesty is the switch, not a shield")

	## A provoked thing in a CAVE keeps its grudge straight through the switch.
	GameMode.set_mode(GameMode.Mode.NORMAL, self)
	var cave := FakeCave.new()
	_world.add_child(cave)
	cave.global_position = Vector3(1500, 0, 1500)
	var kob := Kobold.new()
	_world.add_child(kob)
	kob.global_position = Vector3(1500, -8, 1503)
	await physics_frame
	kob.take_damage(1.0)
	ok(kob.provoked, "a struck kobold holds a grudge")
	GameMode.set_mode(GameMode.Mode.PEACEFUL, self)
	ok(kob.provoked, "and the caves keep their grudges — no amnesty underground")

	boar.queue_free()
	kob.queue_free()
	cave.queue_free()
	GameMode.set_mode(GameMode.Mode.NORMAL, self)
	_player.global_position = Vector3.ZERO
	await physics_frame


## ============================== The bear ===================================


func t_the_bear() -> void:
	print(" [the bear: warnings without a charge]")
	var br := Critter.make("black_bear")
	_world.add_child(br)
	br.global_position = Vector3(800, 0, 800)
	_player.global_position = Vector3(800, 0, 806)
	_player.damage_taken = 0.0   ## the goblin upstairs may have got a hit in
	await physics_frame

	## The bear is the one animal that attacks unprovoked on Normal. On
	## Peaceful it must still DO all of it — notice, rear up, huff, hold the
	## ground — and never reach the charge.
	GameMode.set_mode(GameMode.Mode.PEACEFUL, self)
	br.provoked = false
	br._bluff_count = 0
	br._set_mood(Critter.Mood.EASY, 0.0)
	var warned := false
	for _i in range(140):
		await physics_frame
		if br.mood == Critter.Mood.WARN:
			warned = true
		if br.mood == Critter.Mood.CHARGE:
			break
	ok(warned, "PEACEFUL: the bear still warns you")
	ok(br.mood != Critter.Mood.CHARGE, "but it never charges (mood %d)" % br.mood)
	near(_player.damage_taken, 0.0, 0.001, "and it never lands a blow")
	ok(br._bluff_count >= 1, "it climbed the ladder — it simply has no top rung")

	## Hit it and the whole ladder is available again.
	br.take_damage(1.0)
	ok(br.provoked, "one arrow provokes the bear")
	eq(br.mood, Critter.Mood.CHARGE, "and a provoked bear charges on Peaceful too")
	ok(GameMode.may_engage(br, _player), "the gate opens for it")

	## Normal: unprovoked is enough.
	var br2 := Critter.make("black_bear")
	_world.add_child(br2)
	br2.global_position = Vector3(900, 0, 900)
	_player.global_position = Vector3(900, 0, 905)
	GameMode.set_mode(GameMode.Mode.NORMAL, self)
	await physics_frame
	var charged := false
	for _i in range(200):
		await physics_frame
		if br2.mood == Critter.Mood.CHARGE:
			charged = true
			break
	ok(charged, "NORMAL: the same bear, unprovoked, comes for you")
	ok(not br2.provoked, "without you ever having touched it")

	## And the switch lands on the fight you are already in.
	GameMode.set_mode(GameMode.Mode.PEACEFUL, self)
	ok(br2.mood != Critter.Mood.CHARGE, "flipping to Peaceful calls the charge off mid-stride")

	br.queue_free()
	br2.queue_free()
	GameMode.set_mode(GameMode.Mode.NORMAL, self)
	_player.global_position = Vector3.ZERO
	_player.damage_taken = 0.0
	await physics_frame


## ==================== The bear's hands: grab + press =======================


func t_bear_moves() -> void:
	print(" [the bear's hands: grab + press]")
	ok(CritterDex.flag("black_bear", "grab", false), "the bear carries the grab flag")
	ok(CritterDex.flag("black_bear", "press", false), "and the press flag")
	ok(CritterAnim.duration("bear_grab") > 1.0, "bear_grab is a real clip")
	ok(CritterAnim.duration("bear_press") > 2.0, "bear_press is a real clip")

	var br := Critter.make("black_bear")
	_world.add_child(br)
	br.global_position = Vector3(2000, 0, 2000)
	await physics_frame

	## LabPlayer has no grab/press surface, so the bear NEVER picks a move on
	## it — the whole feature is has_method-guarded and the plain swipe stays
	## the fallback. This is what keeps every older suite green.
	var never := true
	for _i in range(60):
		if br._pick_move(_player, 1.0) != "":
			never = false
	ok(never, "no creature_grab on the target = no move ever picked (swipe fallback)")

	## A target with the full surface gets manhandled sooner or later.
	var mark := GrabMark.new()
	_world.add_child(mark)
	mark.global_position = Vector3(2001, 0, 2000)
	mark.add_to_group("player")
	var rolled := {}
	for _i in range(200):
		var mv := br._pick_move(mark, 1.0)
		if mv != "":
			rolled[mv] = true
	ok(rolled.has("grab"), "the grab comes up")
	ok(rolled.has("press"), "the press comes up")

	## Cooldowns gate them off; a downed body is never picked at all.
	br._grab_cd = 99.0
	br._press_cd = 99.0
	var gated := true
	for _i in range(40):
		if br._pick_move(mark, 1.0) != "":
			gated = false
	ok(gated, "on cooldown neither is picked")
	br._grab_cd = 0.0
	br._press_cd = 0.0
	ok(not br._target_down(mark), "a standing mark is not down")
	mark.kd_phase = "down"
	ok(br._target_down(mark), "kd_phase = down reads as down")
	var merciful := true
	for _i in range(40):
		if br._pick_move(mark, 1.0) != "":
			merciful = false
	ok(merciful, "MERCY: a body on the ground is never picked for a move")
	mark.kd_phase = "rise"
	ok(br._target_down(mark), "the rise still counts as down — no instant re-hit")
	mark.kd_phase = ""

	## Starting a move rides the matching clip; aborting drops everything.
	br._start_move("grab")
	eq(br._move, "grab", "grab started")
	eq(br._sig, "bear_grab", "and the clip is the clock")
	br._move_abort()
	eq(br._move, "", "abort clears the move")
	ok(br._sig != "bear_grab", "and the clip")
	ok(br._grab_cd > 0.0, "an aborted grab pays a cooldown")

	## The pose math. The press rears the FRONT HIPS off the ground (the
	## bear_stand lesson: hips are parented to root, so the arc is written
	## onto the pivots), and the grab gapes the jaw for the clamp.
	CritterAnim.neutral(br.rig)
	var hip := (br.rig["legs"] as Array)[0] as Node3D
	var rest_y := hip.position.y
	CritterAnim.play(br.rig, "bear_press", 0.30, 0.016, br)
	ok(hip.position.y > rest_y + 0.2,
		"press t=0.30: front hip pivot is off the ground (+%.2f m)" % (hip.position.y - rest_y))
	CritterAnim.neutral(br.rig)
	near(hip.position.y, rest_y, 0.001, "neutral() restores the hip exactly")

	var jaw := br.rig["jaw"] as Node3D
	var jrest := jaw.rotation.x
	CritterAnim.play(br.rig, "bear_grab", 0.10, 0.016, br)
	ok(jaw.rotation.x < jrest - 0.4, "grab lunge: the jaw gapes for the clamp")
	CritterAnim.play(br.rig, "bear_grab", 0.78, 0.016, br)
	var head := br.rig["head"] as Node3D
	ok(absf(head.rotation.y) > 0.4, "the throw whips the head to the side (%.2f rad)" % head.rotation.y)
	CritterAnim.neutral(br.rig)

	## grab_anchor answers with a hang point under the mouth, live per frame.
	var a: Dictionary = br.grab_anchor()
	ok(a.has("pos"), "grab_anchor answers with a position")

	mark.remove_from_group("player")
	mark.queue_free()
	br.queue_free()
	await physics_frame


## =============================== The seal ==================================


func t_the_seal() -> void:
	print(" [hardcore: the seal]")
	## Whatever state this machine is really in, put it back at the end — a
	## test run must never resurrect somebody's dead Hardcore save.
	var was_sealed := SaveGame.is_sealed()

	SaveGame.unseal()
	ok(not SaveGame.is_sealed(), "an unsealed slot reads as unsealed")

	SaveGame.seal("GameModeTests")
	ok(SaveGame.is_sealed(), "seal() lays the tombstone")
	ok(FileAccess.file_exists(SaveGame.SEAL_PATH),
		"and it is a FILE, so the death outlives the process")

	if SaveGame.has_save():
		var refusal := SaveGame.load_game(_player)
		ok(refusal != "" and not refusal.begins_with("Nothing"),
			"Load refuses the sealed slot: '%s'" % refusal)
	else:
		## There is no slot on this machine to be refused, and writing a fake
		## one would clobber a real save. Assert the predicate Load reads.
		ok(SaveGame.is_sealed(), "no save file here — Load's guard asserted through is_sealed()")

	SaveGame.unseal()
	ok(not SaveGame.is_sealed(), "New Run breaks the seal")
	ok(not FileAccess.file_exists(SaveGame.SEAL_PATH), "the tombstone is gone from disk")
	SaveGame.unseal()
	ok(not SaveGame.is_sealed(), "and unseal() is idempotent — twice over is fine")

	if was_sealed:
		SaveGame.seal("restored by GameModeTests")
	ok(SaveGame.is_sealed() == was_sealed, "the machine is left exactly as it was found")
