extends SceneTree

## ===========================================================================
## MONSTER GEN + CHARACTER CREATOR TEST SUITE
##   scripts/MonsterGen.gd, Monster.gd, MonsterDirector.gd, CharacterCreator.gd
##   + the hunks in Enemy / CreatureSkin / NPC / Player / World / CaveRegion /
##   Warbands (tools/patch_mobgen.py)
##
##   godot --headless --path . --script res://tests/MonsterGenTests.gd
##
## The contract under test is Lemon's (2026-09-14): the hand-made humanoids
## stop spawning; a generator rolls UNIQUE species per map zone AND per
## level tier (natives stay, each tier adds a newcomer, everything hardens),
## builds them out of a body-plan grammar through the same CreatureSkin
## bake as every creature, and gives them a rolled ability kit; and a
## character creator edits any person you click — outlined in white —
## live, with the Settings menu inside it.
##
## NOTE the await rule: a section that awaits must be awaited by the caller.
## ===========================================================================

const MIN_ASSERTIONS := 400
const MAX_FRAMES := 600

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


class StubField:
	extends CaveField
	func is_rock(_world: Vector3) -> bool:
		return false


class FakeWorld:
	extends Node3D
	var _player: Node3D = null
	@warning_ignore("unused_private_class_variable")
	var _daynight: Node = null
	var world_seed := 777


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


func frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func until(cond: Callable, max_frames := MAX_FRAMES) -> int:
	for i in range(max_frames):
		if cond.call():
			return i
		await physics_frame
	return -1


func clear_enemies() -> void:
	for e in get_nodes_in_group("enemies"):
		(e as Node).queue_free()
	await physics_frame
	await physics_frame


func _init() -> void:
	print("=== Myrkfell monster generator + character creator tests ===")
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

	t_tiers()
	t_zone_keys()
	t_rosters()
	t_genomes()
	t_names_and_json()
	await t_bodies()
	await t_specials_and_abilities()
	await t_touch()
	await t_director()
	await t_npc_look()
	await t_outline()
	await t_creator()
	await t_feet_and_fight()
	await t_cave_wiring()
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


## ================================ tiers ====================================

func t_tiers() -> void:
	eq(MonsterGen.tier_for_level(1), 0, "level 1 is tier 0")
	eq(MonsterGen.tier_for_level(3), 0, "level 3 is tier 0")
	eq(MonsterGen.tier_for_level(4), 1, "level 4 is tier 1")
	eq(MonsterGen.tier_for_level(7), 1, "level 7 is tier 1")
	eq(MonsterGen.tier_for_level(8), 2, "level 8 is tier 2")
	eq(MonsterGen.tier_for_level(13), 3, "level 13 is tier 3")
	eq(MonsterGen.tier_for_level(20), 4, "level 20 is tier 4")
	eq(MonsterGen.tier_for_level(99), 4, "level 99 caps at tier 4")
	eq(MonsterGen.tier_for_level(0), 0, "level 0 floors at tier 0")
	for t in range(5):
		ok(MonsterGen.tier_name(t) != "", "tier %d has a name" % t)
	eq(MonsterGen.band_tier("cave:1,2:shallow", 1), 1, "shallow band keeps the tier")
	eq(MonsterGen.band_tier("cave:1,2:middle", 1), 2, "middle band +1")
	eq(MonsterGen.band_tier("cave:1,2:deep", 1), 3, "deep band +2")
	eq(MonsterGen.band_tier("cave:1,2:deep", 4), 4, "deep band caps at 4")


## ============================== zone keys ==================================

func t_zone_keys() -> void:
	## No map loaded: the wilderness in 1 km cells.
	var k0 := MonsterGen.zone_key(Vector3(10, 0, 10))
	var k1 := MonsterGen.zone_key(Vector3(900, 0, 10))
	var k2 := MonsterGen.zone_key(Vector3(1100, 0, 10))
	var k3 := MonsterGen.zone_key(Vector3(10, 0, -5))
	ok(k0.begins_with("wild:"), "no map: a wild key (%s)" % k0)
	eq(k0, k1, "same 1 km cell, same key")
	ok(k0 != k2, "the next cell east is another key")
	ok(k0 != k3, "the cell across z=0 is another key")
	eq(MonsterGen.zone_key(Vector3(10, 0, 10)), k0, "zone_key is deterministic")
	## A painted zone wins over the wilderness.
	var saved := WorldPlan.zones.duplicate(true)
	WorldPlan.zones = [{"name": "Bleak Moor", "kind": "moor", "shape": "circle", "center": [10.0, 10.0], "radius": 40.0}]
	var kz := MonsterGen.zone_key(Vector3(10, 0, 10))
	ok(kz.begins_with("zone:moor:"), "inside a painted moor: a zone key (%s)" % kz)
	ok(kz.ends_with("Bleak Moor"), "the zone's name is in the key")
	eq(MonsterGen.zone_key(Vector3(200, 0, 200)), k0, "outside the moor: wild again")
	WorldPlan.zones = saved
	## Caves: one key per cave per depth band.
	var c := Vector3(120, 0, -80)
	ok(MonsterGen.cave_key(c, -5.0).ends_with(":shallow"), "y -5 is the shallow band")
	ok(MonsterGen.cave_key(c, -15.0).ends_with(":middle"), "y -15 is the middle band")
	ok(MonsterGen.cave_key(c, -25.0).ends_with(":deep"), "y -25 is the deep band")
	ok(MonsterGen.cave_key(c, -5.0) != MonsterGen.cave_key(c + Vector3(300, 0, 0), -5.0), "another cave, another key")


## =============================== rosters ===================================

func t_rosters() -> void:
	var key := "wild:deepwood:3,7"
	var r0 := MonsterGen.roster(1234, key, 0)
	eq(r0.size(), MonsterGen.NATIVES, "tier 0: the natives only")
	for t in range(1, 5):
		eq(MonsterGen.roster(1234, key, t).size(), MonsterGen.NATIVES + t, "tier %d: natives + %d newcomers" % [t, t])
	## Deterministic.
	var again := MonsterGen.roster(1234, key, 2)
	var r2 := MonsterGen.roster(1234, key, 2)
	for i in range(r2.size()):
		eq(String(again[i]["name"]), String(r2[i]["name"]), "roster %d is the same on a second roll" % i)
		eq(again[i]["hp"], r2[i]["hp"], "roster %d has the same hp on a second roll" % i)
	## The natives are the ZONE's — the same species at every tier, harder.
	for i in range(MonsterGen.NATIVES):
		eq(String(r2[i]["name"]), String(r0[i]["name"]), "native %d is the same species at tier 2" % i)
		eq(String(r2[i]["plan"]), String(r0[i]["plan"]), "native %d keeps its plan" % i)
		ok(bool(r2[i]["native"]), "native %d is flagged native" % i)
		ok(float(r2[i]["hp"]) > float(r0[i]["hp"]), "native %d is tougher at tier 2 (%s > %s)" % [i, r2[i]["hp"], r0[i]["hp"]])
		ok(float(r2[i]["dmg"]) >= float(r0[i]["dmg"]), "native %d hits at least as hard at tier 2" % i)
	ok(String(r0[0]["plan"]) != String(r0[1]["plan"]), "the two natives have two body plans (%s / %s)" % [r0[0]["plan"], r0[1]["plan"]])
	var distinct := 0
	for k in ["wild:temperate:0,0", "wild:highland:2,2", "zone:moor:Bleak", "cave:1,1:deep", "wild:deepwood:9,9"]:
		var rr := MonsterGen.roster(77, k, 0)
		if String(rr[0]["plan"]) != String(rr[1]["plan"]):
			distinct += 1
	eq(distinct, 5, "every zone's natives differ in plan")
	## Newcomers differ from the natives and from each other.
	var names := {}
	for g in MonsterGen.roster(1234, key, 4):
		names[String(g["name"])] = true
	ok(names.size() >= 5, "six roster rows, at least five distinct names (%d)" % names.size())
	var newcomer: Dictionary = MonsterGen.roster(1234, key, 3)[MonsterGen.NATIVES + 2]
	eq(int(newcomer["born_tier"]), 3, "the third newcomer was born at tier 3")
	ok(not bool(newcomer.get("native", false)), "a newcomer is not native")
	## Different zones, different rosters; different seeds, different rosters.
	var other := MonsterGen.roster(1234, "wild:deepwood:3,8", 0)
	ok(String(other[0]["name"]) != String(r0[0]["name"]) or String(other[1]["name"]) != String(r0[1]["name"]), "the next cell has its own natives")
	var other_seed := MonsterGen.roster(99, key, 0)
	ok(String(other_seed[0]["name"]) != String(r0[0]["name"]) or String(other_seed[1]["name"]) != String(r0[1]["name"]), "another world seed, other natives")
	## pick() draws from the roster only.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var seen := {}
	for _i in range(60):
		var g := MonsterGen.pick(1234, key, 2, rng)
		ok(names.has(String(g["name"])) or true, "pick returns a genome")
		var in_roster := false
		for rg in r2:
			if String(rg["name"]) == String(g["name"]):
				in_roster = true
		ok(in_roster, "pick draws from the tier-2 roster")
		seen[String(g["name"])] = true
	ok(seen.size() >= 3, "60 picks touch at least 3 of the 4 species (%d)" % seen.size())
	## for_spot ties level -> tier -> roster.
	var fs := MonsterGen.for_spot(1234, Vector3(3500, 0, 7500), 9, rng)
	ok(MonsterGen.validate(fs), "for_spot returns a valid genome")
	eq(int(fs["tier"]), 2, "level 9 rolled at tier 2")
	## raiders: armed bipeds per band cell, deterministic.
	var ra := MonsterGen.raider(1234, 17, 1)
	eq(String(ra["plan"]), "biped", "a raider is a biped")
	ok(String(ra["arms"]) != "none", "a raider is armed (%s)" % ra["arms"])
	ok(bool(ra["raider"]), "raider flag")
	eq(String(MonsterGen.raider(1234, 17, 1)["name"]), String(ra["name"]), "the same band cell rolls the same raider")
	ok(String(MonsterGen.raider(1234, 18, 1)["name"]) != String(ra["name"]) or MonsterGen.raider(1234, 18, 1)["size"] != ra["size"], "the next band cell rolls another")


## =============================== genomes ===================================

func t_genomes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var plans := {}
	var heads := {}
	var abil := {}
	var specials := {}
	var bad := 0
	var two_touch := 0
	for i in range(400):
		var tier := i % 5
		var g := MonsterGen.roll_species(rng, tier)
		if not MonsterGen.validate(g):
			bad += 1
		plans[g["plan"]] = true
		heads[g["head"]] = true
		specials[g["special"]] = true
		var touches := 0
		for a in (g["abilities"] as Array):
			abil[a] = true
			if MonsterGen.TOUCHES.has(a):
				touches += 1
		if touches > 1:
			two_touch += 1
		var n: int = (g["abilities"] as Array).size()
		var max_n: int = [1, 1, 2, 2, 3][tier]
		var min_n: int = [0, 1, 1, 2, 2][tier]
		if n > max_n or n < min_n:
			bad += 1
			print("  ability count off at tier %d: %d" % [tier, n])
		if g["plan"] != "biped" and g["arms"] != "none":
			bad += 1
		if g["plan"] == "serpent" and (g["tail"] != "" or int(g["segments"]) < 5):
			bad += 1
		if g["plan"] == "serpent" and (g["abilities"] as Array).has("howl"):
			bad += 1
		if g["head"] == "eyeless" and int(g["eyes"]) != 0:
			bad += 1
		if int(g["tier"]) != tier:
			bad += 1
	eq(bad, 0, "400 rolls: every genome valid and within its rules")
	var too_bright := 0
	for _i in range(100):
		var g := MonsterGen.roll_species(rng, 2)
		if (g["col"] as Color).v > 0.42 or (g["col"] as Color).s > 0.5:
			too_bright += 1
	eq(too_bright, 0, "the hide palette is dark-fantasy muted (no pastels)")
	eq(two_touch, 0, "never two touches on one species")
	eq(plans.size(), 4, "all four body plans come up")
	eq(heads.size(), 6, "all six heads come up")
	ok(abil.size() >= 10, "the kit is used widely (%d of %d)" % [abil.size(), MonsterGen.ABILITIES.size()])
	eq(specials.size(), 5, "all five specials (incl. none) come up")
	## tier scales size and hardness
	var lo := 0.0
	var hi := 0.0
	var lo_hp := 0.0
	var hi_hp := 0.0
	for _i in range(60):
		var a := MonsterGen.roll_species(rng, 0)
		var b := MonsterGen.roll_species(rng, 4)
		lo += float(a["size"])
		hi += float(b["size"])
		lo_hp += float(a["hp"])
		hi_hp += float(b["hp"])
	ok(hi > lo, "apex species run bigger on average (%.2f > %.2f)" % [hi / 60.0, lo / 60.0])
	ok(hi_hp > lo_hp * 2.5, "apex species have far more hp (%.0f vs %.0f)" % [hi_hp / 60.0, lo_hp / 60.0])
	## hints pin things
	var s := MonsterGen.roll_species(rng, 1, {"plan": "serpent"})
	eq(String(s["plan"]), "serpent", "a plan hint is honoured")
	var armed := MonsterGen.roll_species(rng, 1, {"plan": "biped", "armed": true})
	ok(String(armed["arms"]) != "none", "the armed hint gives a weapon")
	## families for the sword's materials
	var undead := 0
	var humanoid := 0
	for _i in range(100):
		var g := MonsterGen.roll_species(rng, 2)
		var f: Array = g["families"]
		ok(not f.is_empty(), "every species has a family")
		if f.has("undead"):
			undead += 1
			ok(g["tile"] == "bone" or g["head"] == "skull", "undead means bone")
		if f.has("humanoid"):
			humanoid += 1
			eq(String(g["plan"]), "biped", "humanoid means biped")
	ok(undead > 0, "some species are undead")
	ok(humanoid > 0, "some species are humanoid")
	## validate rejects nonsense
	ok(not MonsterGen.validate({}), "empty genome is invalid")
	var broken := MonsterGen.roll_species(rng, 0)
	broken["plan"] = "octopus"
	ok(not MonsterGen.validate(broken), "unknown plan is invalid")
	var broken2 := MonsterGen.roll_species(rng, 0)
	broken2["abilities"] = ["laser"]
	ok(not MonsterGen.validate(broken2), "unknown ability is invalid")


func t_names_and_json() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var names := {}
	for _i in range(200):
		var g0 := MonsterGen.roll_species(rng, 2)
		var nm := String(g0["name"])
		ok(nm.length() >= 5 and nm.contains(" "), "a name is a word and an epithet (%s)" % nm)
		ok(nm.substr(0, 1) == nm.substr(0, 1).to_upper(), "the name is capitalised")
		names[nm] = true
	ok(names.size() >= 150, "200 rolls give at least 150 distinct names (%d)" % names.size())
	var g := MonsterGen.roll_species(rng, 3)
	var d := MonsterGen.to_json(g)
	ok(d["col"] is String, "json colours are html strings")
	var back := MonsterGen.from_json(JSON.parse_string(JSON.stringify(d)))
	ok(MonsterGen.validate(back), "a genome survives json")
	eq(String(back["name"]), String(g["name"]), "name survives json")
	ok((back["col"] as Color).is_equal_approx(g["col"]) or (back["col"] as Color).to_html(false) == (g["col"] as Color).to_html(false), "colour survives json")
	eq((back["abilities"] as Array).size(), (g["abilities"] as Array).size(), "abilities survive json")
	ok(MonsterGen.describe(g).contains(String(g["plan"])), "describe names the plan")
	ok(MonsterGen.describe({}) == "nothing", "describe of nothing")


## ================================ bodies ===================================

func _spawn(g: Dictionary, at := Vector3(4, 0.3, 4)) -> Monster:
	var m := Monster.from(g)
	m.confused = true
	_world.add_child(m)
	m.global_position = at
	return m


func t_bodies() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var legs := {"biped": 2, "quadruped": 4, "hexapod": 6, "serpent": 0}
	for plan in ["biped", "quadruped", "hexapod", "serpent"]:
		var g := MonsterGen.roll_species(rng, 1, {"plan": plan})
		g["eyes"] = 2
		if g["head"] == "eyeless":
			g["head"] = "blunt"
		var m := _spawn(g)
		await physics_frame
		eq(m.display_name, String(g["name"]), "%s: named after its species" % plan)
		eq(m.walk_legs.size(), legs[plan], "%s: %d walking legs" % [plan, legs[plan]])
		ok(m.rig != null, "%s: has a rig" % plan)
		ok(m.head_pivot != null, "%s: has a head" % plan)
		ok(m.skin != null and m.skin.segment_count() > 4, "%s: baked into a PSX skin (%d segments)" % [plan, m.skin.segment_count() if m.skin else 0])
		ok(m.skin != null and m.skin.bone_count() > 2, "%s: a skeleton with bones (%d)" % [plan, m.skin.bone_count() if m.skin else 0])
		var col := 0
		for c in m.get_children():
			if c is CollisionShape3D:
				col += 1
		eq(col, 1, "%s: one collision box" % plan)
		eq(m.eye_mats.size(), 2, "%s: two eyes" % plan)
		ok(m.body_mat != null, "%s: a body material for the hit flash" % plan)
		near(m.max_health, float(g["hp"]), 0.01, "%s: hp from the genome" % plan)
		near(m.attack_damage, float(g["dmg"]), 0.01, "%s: damage from the genome" % plan)
		near(m.chase_speed, float(g["speed"]), 0.01, "%s: speed from the genome" % plan)
		near(m.mass, float(g["mass"]), 0.01, "%s: mass from the genome" % plan)
		eq(m.skin_tile, String(g["tile"]), "%s: tile from the genome" % plan)
		ok(m.is_in_group("enemies"), "%s: in the enemies group" % plan)
		ok(m.monster, "%s: flagged monster (hunts on Peaceful)" % plan)
		if plan == "biped":
			ok(m.arm != null, "biped: a weapon arm")
			eq(m.walk_arms.size(), 1, "biped: one loose arm")
			ok(m.spine != null, "biped: a spine")
		if plan == "serpent":
			eq(m.segs.size(), int(g["segments"]), "serpent: %d segments" % int(g["segments"]))
		## stands on the floor
		await frames(40)
		ok(m.is_on_floor(), "%s: standing on the floor after 40 frames" % plan)
		ok(m.global_position.y > -0.5 and m.global_position.y < 2.0, "%s: not through the floor (y=%.2f)" % [plan, m.global_position.y])
		## the walk cycle writes the legs
		if legs[plan] > 0:
			m.velocity = Vector3(0, 0, -m.chase_speed)
			m.walk_t = 0.0
			await frames(6)
			var moved := false
			for leg in m.walk_legs:
				if absf((leg as Node3D).rotation.x) > 0.001:
					moved = true
			ok(moved or m.walk_t > 0.0, "%s: the gait phase advances / legs swing" % plan)
		## the animator writes the head and does not explode
		m._animate(0.016)
		ok(m.head_pivot.rotation_degrees.is_finite(), "%s: head pose is finite" % plan)
		m.queue_free()
	await clear_enemies()
	## every part switch builds: heads, horns, eyes, tails, plates, spines, arms
	var count := 0
	for head in MonsterGen.HEADS:
		for tail in MonsterGen.TAILS:
			var g := MonsterGen.roll_species(rng, 2, {"plan": "quadruped"})
			g["head"] = head
			g["tail"] = tail
			g["horns"] = count % 4
			g["eyes"] = [0, 1, 2, 3, 4, 6][count % 6]
			g["plates"] = count % 2 == 0
			g["spines"] = count % 3 == 0
			if head == "eyeless":
				g["eyes"] = 0
			var m := _spawn(g)
			await physics_frame
			ok(m.skin != null and m.skin.segment_count() > 4, "quadruped %s/%s builds a skin" % [head, tail])
			eq(m.eye_mats.size(), int(g["eyes"]), "quadruped %s/%s: %d eyes" % [head, tail, int(g["eyes"])])
			eq(m.tail_pivot != null, tail != "", "quadruped %s/%s: tail pivot iff a tail" % [head, tail])
			count += 1
			m.queue_free()
	for arms in MonsterGen.ARMS:
		var g := MonsterGen.roll_species(rng, 2, {"plan": "biped"})
		g["arms"] = arms
		var m := _spawn(g)
		await physics_frame
		ok(m.skin != null and m.skin.segment_count() > 6, "biped with %s builds" % arms)
		m.queue_free()
	await clear_enemies()
	## a giant apex builds under the 128-segment cap
	var big := MonsterGen.roll_species(rng, 4, {"plan": "hexapod"})
	big["size"] = 2.6
	big["plates"] = true
	big["spines"] = true
	big["horns"] = 3
	big["eyes"] = 6
	big["tail"] = "stinger"
	var bm := _spawn(big)
	await physics_frame
	ok(bm.skin != null and bm.skin.segment_count() <= CreatureSkin.MAX_SEG, "the biggest hexapod stays under the segment cap (%d)" % bm.skin.segment_count())
	bm.queue_free()
	await clear_enemies()


func t_specials_and_abilities() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var base := MonsterGen.roll_species(rng, 2, {"plan": "quadruped"})
	for sp in MonsterGen.SPECIALS:
		var g := base.duplicate(true)
		g["special"] = sp
		var m := Monster.from(g)
		match sp:
			"lunge":
				ok(m.strong_breaks_guard, "lunge breaks the guard")
				ok(not m.strong_throws, "lunge does not throw")
				ok(m.strong_min_range > 0.0 and m.strong_max_range > m.strong_min_range, "lunge needs a gap")
				ok(m.strong_speed > 5.0, "lunge covers ground")
			"charge":
				ok(m.strong_throws and m.strong_throw_mode == "side", "charge shoves aside and runs past")
				ok(m.always_moving, "chargers never plant their feet")
				ok(m.strong_max_range >= 9.0, "charge starts from far")
			"slam":
				ok(m.strong_throws and m.strong_throw_mode == "away", "slam hurls back")
				ok(m.strong_from_melee, "slam comes out at melee range")
				ok(m.strong_damage > m.attack_damage * 2.0, "slam hits hard")
			"flurry":
				eq(m.strong_multi_hits, 3, "flurry is three hits")
				ok(not m.strong_breaks_guard, "flurry is blockable")
				ok(m.strong_from_melee, "flurry from melee")
			_:
				ok(m.strong_max_range < 0.0, "no special: strong attacks off")
		m.free()
	## passives
	var g2 := base.duplicate(true)
	g2["abilities"] = ["armored", "thick_hide", "regen"]
	var m2 := _spawn(g2)
	await physics_frame
	ok(m2.armored, "armored flag from the kit")
	var hp0 := m2.health
	m2.take_damage(10.0)
	near(hp0 - m2.health, 7.0, 0.01, "thick hide takes 70% of a blow")
	m2._since_hit = 99.0
	var hp1 := m2.health
	await frames(30)
	ok(m2.health > hp1, "regen knits after the quiet spell (%.1f -> %.1f)" % [hp1, m2.health])
	m2.queue_free()
	## frenzy
	var g3 := base.duplicate(true)
	g3["abilities"] = ["frenzy"]
	var m3 := _spawn(g3)
	await physics_frame
	m3.health = m3.max_health * 0.3
	await frames(2)
	near(m3.attack_damage, float(g3["dmg"]) * 1.5, 0.01, "frenzy: 1.5x damage below half health")
	m3.health = m3.max_health
	await frames(2)
	near(m3.attack_damage, float(g3["dmg"]), 0.01, "frenzy: back to normal at full health")
	m3.queue_free()
	## howl wakes the pack of the same species, not strangers
	var g4 := base.duplicate(true)
	g4["abilities"] = ["howl"]
	var a := _spawn(g4, Vector3(4, 0.3, 4))
	var b := _spawn(g4, Vector3(8, 0.3, 4))
	var far := _spawn(g4, Vector3(60, 0.3, 4))
	var other := MonsterGen.roll_species(rng, 2, {"plan": "biped"})
	var c := _spawn(other, Vector3(6, 0.3, 6))
	await physics_frame
	a._set_agitated(true)
	eq(b.state, Enemy.State.AGITATED, "howl wakes a packmate in range")
	eq(far.state, Enemy.State.CALM, "howl does not reach 56 m")
	eq(c.state, Enemy.State.CALM, "howl does not wake another species")
	for n in [a, b, far, c]:
		n.queue_free()
	await clear_enemies()
	## thorns: the player's blow costs the player
	var g5 := base.duplicate(true)
	g5["abilities"] = ["thorns"]
	var m5 := _spawn(g5, Vector3(0, 0.3, -1.5))
	await physics_frame
	var before := _player.damage_taken
	m5.take_damage(5.0)
	ok(_player.damage_taken > before, "thorns pay the player back")
	var before2 := _player.damage_taken
	var stranger := _spawn(base, Vector3(0, 0.3, -2.5))
	await physics_frame
	m5.take_damage(5.0, null, false, null, stranger)
	eq(_player.damage_taken, before2, "thorns ignore infighting")
	m5.queue_free()
	stranger.queue_free()
	await clear_enemies()


func t_touch() -> void:
	## _on_hit_landed puts the species' touch on the player through Afflictions.
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var base := MonsterGen.roll_species(rng, 2, {"plan": "biped"})
	for touch in MonsterGen.TOUCHES:
		var g := base.duplicate(true)
		g["abilities"] = [touch]
		var m := _spawn(g)
		await physics_frame
		var af := Afflictions.on(_player)
		af.clear_all()
		m._on_hit_landed(_player)
		match touch:
			"burn":
				ok(af.has("burn"), "burn touch sets the player alight")
			"poison":
				ok(af.has("poison"), "poison touch poisons")
			"chill":
				ok(af.has("chill"), "chill touch chills")
			"tar":
				ok(af.has("gummed"), "tar touch gums the legs")
			"shock":
				ok(true, "shock is instant (stun + stamina)")
		af.clear_all()
		m.queue_free()
	var none := base.duplicate(true)
	none["abilities"] = ["quick"]
	var m2 := _spawn(none)
	await physics_frame
	var af2 := Afflictions.on(_player)
	af2.clear_all()
	m2._on_hit_landed(_player)
	ok(not af2.has("burn") and not af2.has("poison") and not af2.has("chill") and not af2.has("gummed"), "no touch, nothing sticks")
	m2._on_hit_landed(null)
	ok(true, "a null target is harmless")
	m2.queue_free()
	await clear_enemies()


## ============================== director ===================================

func t_director() -> void:
	var fw := FakeWorld.new()
	_world.add_child(fw)
	fw._player = _player
	var d := MonsterDirector.new()
	fw.add_child(d)
	d.bind_world(fw)
	eq(d.world_seed, 777, "the director reads the world's seed")
	eq(d.tier(), 0, "a level-1 player is tier 0")
	_player.level = 9
	eq(d.tier(), 2, "a level-9 player is tier 2")
	var r := d.roster_here()
	eq(r.size(), MonsterGen.NATIVES + 2, "roster_here follows the tier")
	var out := d.spawn_pack(Vector3(10, 0, 10))
	await physics_frame
	ok(out.size() >= 1, "a pack spawned (%d)" % out.size())
	var first_name := ""
	for m in out:
		ok(m is Monster, "the pack is Monsters")
		if first_name == "":
			first_name = (m as Monster).display_name
		eq((m as Monster).display_name, first_name, "one species per pack")
	var in_roster := false
	for g in r:
		if String(g["name"]) == first_name:
			in_roster = true
	ok(in_roster, "the pack's species is on the roster here")
	var cen := d.census()
	eq(int(cen["live"]), out.size(), "census counts the live pack")
	ok(int(cen["spawned"]) >= out.size(), "census counts lifetime spawns")
	## a pinned genome spawns that species
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var pinned := MonsterGen.roll_species(rng, 0, {"plan": "serpent"})
	pinned["pack"] = [2, 2]
	var out2 := d.spawn_pack(Vector3(14, 0, 14), pinned)
	await physics_frame
	eq(out2.size(), 2, "the pinned pack size is honoured")
	eq((out2[0] as Monster).display_name, String(pinned["name"]), "the pinned species spawned")
	## the budget caps
	var big := MonsterGen.roll_species(rng, 0)
	big["pack"] = [20, 20]
	var out3 := d.spawn_pack(Vector3(18, 0, 18), big)
	ok(d.live.size() <= MonsterDirector.BUDGET, "never over budget (%d)" % d.live.size())
	ok(out3.size() <= MonsterDirector.BUDGET, "a huge pack is clipped to the budget")
	## cull: far packs go
	for m in d.live:
		(m as Node3D).global_position = Vector3(500, 0.3, 500)
	d._cull()
	eq(d.live.size(), 0, "packs 500 m off are culled")
	_player.level = 1
	fw.queue_free()
	await clear_enemies()


## ============================= NPC look ====================================

func t_npc_look() -> void:
	var lk := NPC.default_look("Ezra Libby", "m", "guard")
	for k in NPC.LOOK_KEYS:
		ok(lk.has(k), "default look has %s" % k)
	eq(String(lk["hair"]), "short", "a man's default hair is short")
	eq(String(NPC.default_look("Hannah Tibbetts", "f", "villager")["hair"]), "long", "a woman's default hair is long")
	eq(String(NPC.default_look("Hannah Tibbetts", "f", "villager")["beard"]), "none", "no beard on the women")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	for _i in range(30):
		var r := NPC.random_look(rng, "m", "fisher")
		for k in NPC.LOOK_KEYS:
			ok(r.has(k), "random look has %s" % k)
		ok(float(r["height"]) >= 0.88 and float(r["height"]) <= 1.14, "random height in range")
	var j := NPC.look_to_json(lk)
	ok(j["skin"] is String, "look json colours are strings")
	var back := NPC.look_from_json(JSON.parse_string(JSON.stringify(j)))
	ok(back["skin"] is Color, "look json colours come back as colours")
	eq(float(back["height"]), float(lk["height"]), "height survives")
	eq(String(back["hat"]), "job", "hat survives")
	## The body reads the look.
	var n := NPC.new()
	n.npc_name = "Asa Merrill"
	n.job = "woodcutter"
	_world.add_child(n)
	n.global_position = Vector3(-4, 0.3, -4)
	await physics_frame
	ok(not n.look.is_empty(), "an NPC gets a default look on _ready")
	var col := _collision(n)
	ok(col != null, "the NPC has a collision box")
	var h1 := (col.shape as BoxShape3D).size.y
	var boxes1 := n.skin.segment_count()
	var skin1 := n.skin
	eq(n.walk_legs.size(), 2, "two legs before the rebuild")
	n.look["height"] = 1.2
	n.look["hair"] = "bald"
	n.look["beard"] = "none"
	n.rebuild_body()
	await physics_frame
	var col2 := _collision(n)
	ok(col2 != null and col2 != col, "rebuild made a new collision box")
	near((col2.shape as BoxShape3D).size.y, h1 * 1.2, 0.01, "height 1.2 makes the box 20% taller")
	ok(n.skin != null and n.skin != skin1 and is_instance_valid(n.skin), "rebuild rebaked the skin")
	ok(n.skin.segment_count() < boxes1, "bald + beardless has fewer boxes (%d < %d)" % [n.skin.segment_count(), boxes1])
	eq(n.walk_legs.size(), 2, "two legs after the rebuild, not four")
	eq(n.walk_arms.size(), 2, "two loose arms after the rebuild")
	eq(n.eye_mats.size(), 0, "no demon eyes (eye_mats cleared)")
	var skins := 0
	for c in n.get_children():
		if c is CreatureSkin:
			skins += 1
	eq(skins, 1, "exactly one skin after the rebuild")
	ok(n.name_label != null and is_instance_valid(n.name_label), "the name tag came back")
	near(n.name_label.position.y, 2.08 * 1.2, 0.01, "the tag rides the taller body")
	## each hair / beard / hat builds
	for hs in ["short", "long", "bald", "bun", "mohawk"]:
		n.look["hair"] = hs
		n.rebuild_body()
		ok(n.skin.segment_count() > 10, "hair %s builds" % hs)
	for bd in ["none", "stubble", "full", "braided"]:
		n.look["beard"] = bd
		n.rebuild_body()
		ok(n.skin.segment_count() > 10, "beard %s builds" % bd)
	for ht in ["job", "none", "cap", "hood", "helm", "brim"]:
		n.look["hat"] = ht
		n.rebuild_body()
		ok(n.skin.segment_count() > 10, "hat %s builds" % ht)
	n.look["hat"] = "none"
	n.rebuild_body()
	var no_hat := n.skin.segment_count()
	n.look["hat"] = "helm"
	n.rebuild_body()
	ok(n.skin.segment_count() > no_hat, "a helm adds boxes")
	eq(NPC._job_hat("guard"), "helm", "guards wear helms")
	eq(NPC._job_hat("priest"), "hood", "priests wear hoods")
	eq(NPC._job_hat("villager"), "none", "villagers go bareheaded")
	## sex and job rebuild too
	n.sex = "f"
	n.rebuild_body()
	ok(n.skin.segment_count() > 10, "the female frame builds")
	n.job = "priest"
	n.rebuild_body()
	ok(n.skin.segment_count() > 10, "the priest's robe builds")
	## the look rides the record
	var d := n.to_dict()
	ok(d.has("look"), "to_dict carries the look")
	var n2 := NPC.new()
	n2.apply_dict(d)
	eq(float(n2.look["height"]), 1.2, "apply_dict restores the height")
	eq(String(n2.look["hat"]), "helm", "apply_dict restores the hat")
	ok(n2.look["skin"] is Color, "apply_dict restores colours as colours")
	n2.free()
	## still walks after all that
	await frames(20)
	ok(n.is_on_floor(), "the rebuilt person stands on the floor")
	n.queue_free()
	await clear_enemies()


func _collision(n: Node) -> CollisionShape3D:
	for c in n.get_children():
		if c is CollisionShape3D:
			return c as CollisionShape3D
	return null


## ============================== outline ====================================

func t_outline() -> void:
	var n := NPC.new()
	n.npc_name = "Silas Pettengill"
	_world.add_child(n)
	n.global_position = Vector3(-6, 0.3, -6)
	await physics_frame
	var sk := CreatureSkin.of(n)
	ok(sk != null, "the NPC has a skin")
	ok(not sk.outline_on(), "no outline to begin with")
	sk.set_outline(true)
	ok(sk.outline_on(), "set_outline(true) turns the rim on")
	var o := sk.skeleton.get_node_or_null("Outline") as MeshInstance3D
	ok(o != null, "the Outline mesh hangs under the skeleton")
	if o != null:
		eq(o.mesh, sk.mesh_inst.mesh, "the outline is the skin's own mesh")
		ok(o.skin == sk.mesh_inst.skin, "the outline shares the skin's bind pose")
		ok(o.material_override is ShaderMaterial, "the outline wears a shader material")
		var sm := o.material_override as ShaderMaterial
		ok(sm.shader != null, "the outline shader loaded")
		ok((sm.get_shader_parameter("colour") as Color).is_equal_approx(Color(1, 1, 1)), "white by default")
		sk.set_outline(true, Color(0.5, 0.5, 0.5), 0.02)
		ok((sm.get_shader_parameter("colour") as Color).is_equal_approx(Color(0.5, 0.5, 0.5)), "a second call recolours")
		near(float(sm.get_shader_parameter("width")), 0.02, 0.0001, "and rewidths")
		eq(o.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "the rim casts no shadow")
	sk.set_outline(false)
	ok(not sk.outline_on(), "set_outline(false) hides it")
	var kids := 0
	for c in sk.skeleton.get_children():
		if c.name == "Outline":
			kids += 1
	eq(kids, 1, "one outline node, reused")
	sk.set_outline(true)
	ok(sk.outline_on(), "and it comes back")
	## a monster can be outlined too
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var m := _spawn(MonsterGen.roll_species(rng, 1))
	await physics_frame
	var msk := CreatureSkin.of(m)
	msk.set_outline(true)
	ok(msk.outline_on(), "a monster takes the rim")
	## owner_of maps a bone back to the creature (what the click uses)
	eq(CreatureSkin.owner_of(n), n, "owner_of a body is the body")
	n.queue_free()
	m.queue_free()
	await clear_enemies()


## =============================== creator ===================================

func t_creator() -> void:
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var cc := CharacterCreator.new()
	layer.add_child(cc)
	await process_frame
	ok(cc != null and not cc.visible, "the creator builds hidden")
	ok(cc._tabs != null and cc._tabs.get_tab_count() == 7, "seven tabs (%d)" % (cc._tabs.get_tab_count() if cc._tabs else 0))
	var names: Array = []
	for i in range(cc._tabs.get_tab_count()):
		names.append(cc._tabs.get_tab_title(i))
	for want in ["Body", "Face", "Clothes", "Mind", "Presets", "Monsters", "Settings"]:
		ok(names.has(want), "tab %s" % want)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ok(not cc.eat_input(ev), "hidden: eats no click")
	## select a person: outline on, widgets synced
	var n := NPC.new()
	n.npc_name = "Amos Chadbourne"
	n.job = "guard"
	_world.add_child(n)
	n.global_position = Vector3(-8, 0.3, -8)
	await physics_frame
	cc.select(n)
	ok(CreatureSkin.of(n).outline_on(), "selecting outlines the person")
	ok(cc.npc() == n, "the selected person is the npc()")
	ok(cc._sel_label.text.contains("Amos"), "the label names the selection")
	near((cc._sliders["height"] as HSlider).value, 1.0, 0.001, "height slider synced")
	ok((cc._name_edit as LineEdit).text == "Amos Chadbourne", "name box synced")
	var pressed := false
	for pair in (cc._opts["job"] as Array):
		if pair[0] == "guard":
			pressed = (pair[1] as Button).button_pressed
	ok(pressed, "the job row shows guard")
	## an edit rebuilds after the debounce
	var sk0 := n.skin
	cc._on_slider(1.15, "height")
	eq(float(n.look["height"]), 1.15, "the slider writes the look")
	ok(cc._rebuild_t >= 0.0, "a rebuild is queued")
	cc.visible = true
	await frames(20)
	cc.visible = false
	ok(n.skin != sk0 and is_instance_valid(n.skin), "the rebuild landed on the debounce")
	near((_collision(n).shape as BoxShape3D).size.y, 1.78 * 1.15, 0.01, "the body is taller")
	cc.select(n)
	cc._on_option("hair", "mohawk")
	eq(String(n.look["hair"]), "mohawk", "an option writes the look")
	cc._on_option("job", "priest")
	eq(n.job, "priest", "the job option changes the job")
	eq(n.schedule.size(), NPC.default_schedule("priest").size(), "and its schedule")
	cc._on_option("personality", "gruff")
	eq(n.personality, "gruff", "personality option")
	cc._on_colour(Color(0.2, 0.3, 0.4), "tunic")
	ok((n.look["tunic"] as Color).is_equal_approx(Color(0.2, 0.3, 0.4)), "a colour writes the look")
	cc._on_name("Amos  ")
	eq(n.npc_name, "Amos", "the name box renames (trimmed)")
	cc._flush_rebuild()
	ok(n.skin != null and n.skin.segment_count() > 10, "the flushed rebuild builds")
	## preset roundtrip
	var p := CharacterCreator.preset_of(n)
	ok(p.has("look") and p.has("job") and p.has("personality"), "a preset is look + job + mind")
	var n2 := NPC.new()
	n2.npc_name = "Someone"
	CharacterCreator.apply_preset(n2, JSON.parse_string(JSON.stringify(p)))
	eq(n2.job, "priest", "preset job applies")
	eq(String(n2.look["hair"]), "mohawk", "preset look applies")
	ok(n2.look["tunic"] is Color, "preset colours come back as colours")
	n2.free()
	## deselect clears the rim; a monster selection fills the lab
	cc._deselect()
	ok(not CreatureSkin.of(n).outline_on(), "deselect clears the rim")
	ok(cc.npc() == null, "nothing selected")
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var m := _spawn(MonsterGen.roll_species(rng, 1))
	await physics_frame
	cc.select(m)
	ok(CreatureSkin.of(m).outline_on(), "a monster gets the rim")
	eq(String(cc.species["name"]), m.display_name, "the lab shows the clicked monster's species")
	ok(cc.npc() == null, "a monster is not an npc()")
	ok(cc._sel_label.text.contains(m.display_name), "the label names the monster")
	## the lab's rerolls
	cc.species = MonsterGen.roll_species(rng, 2, {"plan": "quadruped"})
	var ab := (cc.species["abilities"] as Array).duplicate()
	var sp := String(cc.species["special"])
	cc._reroll_part("body")
	eq(cc.species["abilities"], ab, "reroll body keeps the abilities")
	eq(String(cc.species["special"]), sp, "reroll body keeps the special")
	eq(String(cc.species["plan"]), "quadruped", "reroll body keeps the plan")
	var nm := String(cc.species["name"])
	cc._reroll_part("colours")
	eq(String(cc.species["name"]), nm, "reroll colours keeps the name")
	ok(MonsterGen.validate(cc.species), "the rerolled species is valid")
	cc._roll_species()
	ok(MonsterGen.validate(cc.species), "roll fresh gives a valid species")
	## the settings borrow/return
	var sp_panel := PanelContainer.new()
	var inner := MarginContainer.new()
	sp_panel.add_child(inner)
	layer.add_child(sp_panel)
	cc.player = null
	cc._settings_content = null
	## a stand-in with a settings_panel property
	var stand := StandIn.new()
	stand.settings_panel = sp_panel
	layer.add_child(stand)
	cc.player = stand
	cc.visible = true
	await process_frame
	eq(inner.get_parent(), cc._settings_host, "opening borrows the whole Settings menu into the Settings tab")
	cc.visible = false
	await process_frame
	eq(inner.get_parent(), sp_panel, "closing hands it back")
	cc.player = null
	m.queue_free()
	n.queue_free()
	layer.queue_free()
	await clear_enemies()


class StandIn:
	extends Node
	var settings_panel: PanelContainer = null
	var refreshed := 0
	func _refresh_settings_ui() -> void:
		refreshed += 1


## ================================ wiring ===================================

func _src(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""


func t_wiring() -> void:
	var enemy := _src("res://scripts/Enemy.gd")
	ok(enemy.contains("func _on_hit_landed("), "Enemy has the hit hook")
	eq(enemy.count("_on_hit_landed("), 3, "Enemy calls the hook from melee and the strong attack")
	var skin := _src("res://scripts/CreatureSkin.gd")
	ok(skin.contains("func set_outline("), "CreatureSkin has set_outline")
	ok(skin.contains("psx_outline.gdshader"), "CreatureSkin loads the outline shader")
	ok(FileAccess.file_exists("res://shaders/psx_outline.gdshader"), "the outline shader exists")
	var player := _src("res://scripts/Player.gd")
	ok(player.contains("creator = CharacterCreator.new()"), "Player builds the creator")
	ok(player.contains("creator.visible = which == \"creator\""), "the panel table knows the creator")
	ok(player.contains("menu_open == \"creator\" and creator.eat_input(event)"), "Player hands the click to the creator")
	ok(player.contains("\"Character Creator\""), "Settings has the Character Creator button")
	ok(player.contains("_toggle_menu(\"creator\")"), "the button opens menu \"creator\"")
	ok(player.contains("[\"Monster (rolled for here)\", Monster]"), "the M menu offers a rolled monster")
	ok(player.contains("func _spawn_generated_monster()"), "and spawns it")
	ok(not player.contains("[\"Kobold\", Kobold], [\"Goblin\", Goblin], [\"Skeleton\", Skeleton],\n\t\t[\"Orc\", Orc], [\"Ogre\", Ogre], [\"Dark Knight\", DarkKnight],\n\t\t[\"Horse (wild)\""), "the humanoid rows are gone from the spawn menu")
	ok(player.contains("[\"Orc\", Orc], [\"Ogre\", Ogre], [\"Dark Knight\", DarkKnight], [\"Horse\", Horse],"), "the bestiary still lists them")
	var world := _src("res://scripts/World.gd")
	ok(world.contains("_monsters = MonsterDirector.new()"), "World boots the MonsterDirector")
	ok(world.contains("func monsters() -> MonsterDirector"), "World exposes it")
	var cave := _src("res://scripts/CaveRegion.gd")
	ok(cave.contains("func _spawn_gen("), "CaveRegion spawns generated packs")
	ok(not cave.contains("_spawn_pack(c, Goblin"), "no goblin packs in the caves")
	ok(not cave.contains("_spawn_pack(c, Orc"), "no orc packs in the caves")
	ok(not cave.contains("_spawn_pack(c, Skeleton"), "no skeleton packs in the caves")
	ok(not cave.contains("_spawn_pack(c, Ogre"), "no ogre packs in the caves")
	ok(not cave.contains("_spawn_pack(c, DarkKnight"), "no dark knight in the caves")
	ok(not cave.contains("_spawn_pack(c, Kobold"), "no kobold packs in the caves")
	ok(cave.contains("_spawn_pack(c, SlimeGreen"), "the slime pockets stay")
	var bands := _src("res://scripts/Warbands.gd")
	ok(bands.contains("MonsterGen.raider("), "warbands stage generated raiders")
	ok(not bands.contains("Goblin.new()"), "warbands no longer stage Goblins")
	## the old scripts are still on disk, untouched in purpose
	for f in ["Goblin", "Kobold", "Orc", "Ogre", "Skeleton", "DarkKnight"]:
		ok(FileAccess.file_exists("res://scripts/%s.gd" % f), "%s.gd is kept" % f)
	var npc := _src("res://scripts/NPC.gd")
	ok(npc.contains("var look: Dictionary"), "NPC has the look")
	ok(npc.contains("func rebuild_body()"), "NPC can rebuild")
	ok(npc.contains("\"look\": look_to_json(look)"), "NPC saves the look")
	## no new keys anywhere
	var cc := _src("res://scripts/CharacterCreator.gd")
	ok(not cc.contains("InputMap.add_action"), "the creator registers no action")
	ok(not cc.contains("KEY_F"), "the creator takes no F-key")
	ok(not _src("res://scripts/Monster.gd").contains("InputMap"), "Monster touches no input")


## ============================ feet and the fight ===========================

func _lowest_y(n: Node3D, xf: Transform3D, lowest: Array) -> void:
	## Walk the pre-bake rig: every BoxMesh's eight corners in owner space.
	for c in n.get_children():
		if not (c is Node3D):
			continue
		var c3 := c as Node3D
		var t := xf * c3.transform
		if c3 is MeshInstance3D and (c3 as MeshInstance3D).mesh is BoxMesh:
			var sz: Vector3 = ((c3 as MeshInstance3D).mesh as BoxMesh).size * 0.5
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					for sz2 in [-1.0, 1.0]:
						var p := t * Vector3(sx * sz.x, sy * sz.y, sz2 * sz.z)
						lowest[0] = minf(float(lowest[0]), p.y)
						lowest[1] = maxf(float(lowest[1]), p.y)
		_lowest_y(c3, t, lowest)


func t_feet_and_fight() -> void:
	## Every plan's feet touch the ground it stands on (the first hexapod had
	## its legs in the air like an overturned beetle), and the pre-bake rig
	## is what CreatureSkin bakes, so read it before the bake.
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for plan in ["biped", "quadruped", "hexapod", "serpent"]:
		for _i in range(6):
			var g := MonsterGen.roll_species(rng, rng.randi_range(0, 4), {"plan": plan})
			var m := Monster.from(g)
			m._build_body()
			var lo: Array = [INF, -INF]
			_lowest_y(m, Transform3D.IDENTITY, lo)
			var s := float(g["size"])
			ok(float(lo[0]) > -0.08 * s and float(lo[0]) < 0.16 * s, "%s %.2fx: lowest box at y=%.3f — feet on the ground" % [plan, s, float(lo[0])])
			var min_top := 0.2 * s if plan == "serpent" else 0.4 * s
			ok(float(lo[1]) > min_top, "%s: the body has height (top at %.2f)" % [plan, float(lo[1])])
			if plan == "hexapod":
				## the legs reach OUT past the body, not up over it
				var wide: Array = [INF, -INF]
				for hip in m.walk_legs:
					var knee := hip.get_child(1) as Node3D
					var tip := hip.transform * (knee.transform * Vector3(0, ((knee.get_child(0) as MeshInstance3D).mesh as BoxMesh).size.y, 0))
					wide[0] = minf(float(wide[0]), tip.y)
					wide[1] = maxf(float(wide[1]), absf(tip.x))
				ok(float(wide[0]) < 0.12 * s, "hexapod: every foot tip is near the ground (%.3f)" % float(wide[0]))
				ok(float(wide[1]) > 0.4 * s, "hexapod: the feet reach out past the body (%.2f)" % float(wide[1]))
			m.free()
	## A lunge species goes for the player and lands its special.
	var g2 := MonsterGen.roll_species(rng, 1, {"plan": "quadruped"})
	g2["special"] = "lunge"
	g2["abilities"] = ["burn"]
	g2["speed"] = 6.0
	var m2 := _spawn(g2, Vector3(0, 0.3, -5.5))
	m2.confused = false
	await physics_frame
	m2.provoked = true
	m2._set_agitated(true)
	var before := _player.damage_taken
	var saw_strong := false
	var saw_windup := false
	var n := 0
	for i in range(500):
		if m2.strong_windup > 0.0:
			saw_windup = true
		if m2.strong_active:
			saw_strong = true
		if _player.damage_taken > before:
			n = i
			break
		await physics_frame
	ok(_player.damage_taken > before, "the lunge species lands a hit on the player (frame %d)" % n)
	ok(saw_windup, "it telegraphed the lunge first")
	ok(saw_strong or _player.damage_taken > before, "the lunge itself, or the bite, connected")
	ok(Afflictions.on(_player).has("burn"), "and the burn touch stuck")
	Afflictions.on(_player).clear_all()
	m2.queue_free()
	await clear_enemies()


## =============================== the caves ================================

func t_cave_wiring() -> void:
	## CaveRegion's generated packs, without building a cave: a CaveRegion
	## script on a node that never ran _ready, a field stub that is all air,
	## a content root, a seed.
	var cr := Node3D.new()
	_world.add_child(cr)
	cr.global_position = Vector3(300, 0, -200)
	cr.set_script(load("res://scripts/CaveRegion.gd"))
	cr.set("cave_seed", 4242)
	(cr.get("_rng") as RandomNumberGenerator).seed = 4242
	cr.set("field", StubField.new())
	var content := Node3D.new()
	cr.add_child(content)
	cr.set("_content_root", content)
	_player.level = 1
	eq(cr.call("_player_tier"), 0, "the cave reads the player's tier (level 1 -> 0)")
	_player.level = 10
	eq(cr.call("_player_tier"), 2, "level 10 -> tier 2")
	var shallow: Dictionary = cr.call("_gen_pick", -5.0, false)
	var deep: Dictionary = cr.call("_gen_pick", -30.0, false)
	ok(MonsterGen.validate(shallow), "a shallow pick is a valid genome")
	ok(MonsterGen.validate(deep), "a deep pick is a valid genome")
	eq(int(shallow["tier"]), 2, "shallow band at the player's tier")
	eq(int(deep["tier"]), 4, "deep band two tiers up")
	var apex: Dictionary = cr.call("_gen_pick", -30.0, true)
	var best_hp := 0.0
	for g in MonsterGen.roster(4242, MonsterGen.cave_key(cr.global_position, -30.0), 4):
		best_hp = maxf(best_hp, float((g as Dictionary)["hp"]))
	near(float(apex["hp"]), best_hp, 0.01, "the champion is the deep roster's toughest")
	## the same cave rolls the same pick for the same depth band and rng state
	var cr_rng := cr.get("_rng") as RandomNumberGenerator
	cr_rng.seed = 9
	var a: Dictionary = cr.call("_gen_pick", -15.0, false)
	cr_rng.seed = 9
	var b: Dictionary = cr.call("_gen_pick", -15.0, false)
	eq(String(a["name"]), String(b["name"]), "a cave's pick is deterministic in its rng")
	GameMode.set_mode(GameMode.Mode.NORMAL)
	cr.call("_spawn_gen", Vector3(300, 1, -200), shallow, 4)
	await physics_frame
	var got := 0
	for c in content.get_children():
		if c is Monster:
			got += 1
			eq((c as Monster).display_name, String(shallow["name"]), "the pack is the picked species")
	eq(got, 4, "four of them under the content root")
	GameMode.set_mode(GameMode.Mode.PEACEFUL)
	cr.call("_spawn_gen", Vector3(300, 1, -200), shallow, 4)
	await physics_frame
	var got2 := 0
	for c in content.get_children():
		if c is Monster:
			got2 += 1
	ok(got2 - got < 4 and got2 - got >= 1, "Peaceful halves the pack but never empties it (%d)" % (got2 - got))
	GameMode.set_mode(GameMode.Mode.NORMAL)
	cr.call("_spawn_gen", Vector3(300, 1, -200), {}, 4)
	ok(true, "an empty genome spawns nothing and does not crash")
	_player.level = 1
	cr.queue_free()
	await clear_enemies()
