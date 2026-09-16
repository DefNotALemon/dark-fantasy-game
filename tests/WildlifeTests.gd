extends SceneTree

## ===========================================================================
## WILDLIFE TEST SUITE
##
##   godot --headless --path . --script res://tests/WildlifeTests.gd
##
## Same discipline as tests/TreeTests.gd: everything in here was written
## because something actually broke, or because it is the kind of thing that
## breaks silently and eats a save. Assertions are specific — "the moose
## exists" proves nothing, "the moose's collision box is taller than the
## chickadee's" proves the dex is wired to the rig.
## ===========================================================================

## Roughly how big this suite is (3,312 at time of writing). A run that comes
## in well under it did not get easier — a section returned early. The floor
## sits ~1% below the real count: tight enough that losing a whole section
## (the miss that prompted this was 293 assertions) trips it, loose enough that
## editing a few assertions does not. Raise it when the suite grows.
const MIN_ASSERTIONS := 3370

var pass_n := 0
var fail_n := 0
var fails: Array[String] = []
var _world: Node3D
var _player: Node3D


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
	print("=== Myrkfell wildlife tests ===")
	_world = Node3D.new()
	root.add_child(_world)
	_world.add_to_group("world")
	_player = LabPlayer.new()
	_world.add_child(_player)

	await process_frame

	t_dex()
	t_rigs()
	await t_spawn()
	await t_behaviour()
	await t_telegraph()
	t_seasons()
	t_audio()
	t_spawn_menu()
	await t_director()
	await t_saveload()
	## MUST be awaited. The moment a section gains an `await` inside it, it
	## becomes a coroutine, and calling it bare returns at the first yield with
	## the rest of the section silently unrun — 293 assertions disappeared here
	## once and the suite still printed green.
	await t_specials()
	await t_buzz()

	## Guard against exactly the failure above ever recurring quietly: the
	## suite knows roughly how big it is, and a sudden drop is a bug in the
	## suite, not good news.
	if pass_n + fail_n < MIN_ASSERTIONS:
		var ran := pass_n + fail_n
		fail_n += 1
		fails.append("the suite ran only %d assertions (expected at least %d) — a section probably returned early; check for an un-awaited coroutine" % [ran, MIN_ASSERTIONS])

	print("")
	print("=== %d passed, %d failed ===" % [pass_n, fail_n])
	if fail_n > 0:
		print("failures:")
		for f in fails:
			print("  - ", f)
	quit(1 if fail_n > 0 else 0)


## ================================== dex ===================================


func t_dex() -> void:
	print("-- dex --")
	ok(CritterDex.count() >= 60, "the roster is the whole roster (%d species)" % CritterDex.count())

	var rigs_seen: Dictionary = {}
	var archs_seen: Dictionary = {}
	for k in CritterDex.keys():
		var p := CritterDex.get_profile(k)
		ok(p.has("nm") and String(p["nm"]) != "", "%s has a display name" % k)
		ok(float(p.get("len", 0.0)) > 0.0, "%s has a body length" % k)
		ok(float(p.get("hgt", 0.0)) > 0.0, "%s has a height" % k)
		ok(float(p.get("hp", 0.0)) > 0.0, "%s has health" % k)
		var spd: Array = p.get("spd", [])
		ok(spd.size() == 2 and float(spd[1]) >= float(spd[0]),
			"%s runs at least as fast as it ambles" % k)
		ok(CritterRig.FAMILIES.has(String(p.get("rig", ""))), "%s has a known rig family" % k)
		ok(Critter.ARCH_IDS.has(String(p.get("arch", ""))), "%s has a known archetype" % k)
		ok(not (p.get("sig", []) as Array).is_empty(), "%s has at least one signature animation" % k)
		ok(not (p.get("zone", {}) as Dictionary).is_empty(), "%s lives somewhere" % k)
		rigs_seen[String(p["rig"])] = true
		archs_seen[String(p["arch"])] = true

	## Every rig family and every archetype must actually be USED — an unused
	## family is dead code pretending to be coverage.
	for f in CritterRig.FAMILIES:
		ok(rigs_seen.has(f), "rig family %s is used by at least one species" % f)
	for a in Critter.ARCH_IDS.keys():
		ok(archs_seen.has(a), "archetype %s is used by at least one species" % a)

	## Legends are placed by hand and must never be reachable from a zone roll.
	var legends := CritterDex.legends()
	ok(legends.size() >= 5, "there are legends (%d)" % legends.size())
	for z in CritterDex.ZONES:
		for e in CritterDex.species_for_zone(z):
			ok(not legends.has(String(e["key"])),
				"legend %s never appears in the %s spawn table" % [String(e["key"]), z])

	## Sanity on the natural history, because getting this wrong is the whole
	## difference between "Maine wildlife" and "generic forest animals".
	ok(CritterDex.flag("black_bear", "den", false), "bears den in winter")
	ok(not CritterDex.is_awake("black_bear", 12.0, 0.80), "a denned bear is not out in winter")
	ok(CritterDex.is_awake("black_bear", 12.0, 0.30), "the bear is out in summer")
	ok(CritterDex.flag("hare", "coat_swap", false), "the snowshoe hare changes coat")
	ok(CritterDex.flag("ermine", "coat_swap", false), "the ermine changes coat")
	ok(not CritterDex.is_awake("snowy_owl", 2.0, 0.30), "snowy owls are not here in summer")
	ok(CritterDex.is_awake("snowy_owl", 2.0, 0.80), "snowy owls come down in winter")
	ok(not CritterDex.is_awake("loon", 12.0, 0.90), "the loon has left the iced lake")
	ok(CritterDex.is_awake("loon", 12.0, 0.40), "the loon is back for summer")
	ok(CritterDex.in_zone("moose", "moosehead") > 0.0, "moose live in Moosehead country")
	ok(CritterDex.in_zone("puffin", "gulf") > 0.0, "puffins are offshore")
	ok(CritterDex.in_zone("puffin", "deep_woods") == 0.0, "puffins are NOT in the deep woods")
	ok(CritterDex.in_zone("opossum", "county") == 0.0,
		"the opossum has not reached the County (it is a new arrival to Maine)")
	ok(CritterDex.flag("garter_snake", "nofight", false),
		"Maine has no venomous snakes and the garter never bites first")
	ok(float(CritterDex.get_profile("moose")["len"]) > float(CritterDex.get_profile("whitetail")["len"]),
		"a moose is bigger than a deer")
	ok(float(CritterDex.get_profile("lynx").get("hp", 0.0)) > float(CritterDex.get_profile("hare").get("hp", 0.0)),
		"a lynx outweighs a hare")

	## Nothing harmless may carry damage, and nothing gentle may be a bluffer.
	for k in CritterDex.keys():
		if CritterDex.flag(k, "nofight", false):
			pass  ## Critter zeroes dmg at _ready; asserted live in t_spawn


## ================================== rigs ==================================


func t_rigs() -> void:
	print("-- rigs --")
	for k in CritterDex.keys():
		var holder := Node3D.new()
		_world.add_child(holder)
		var rig := CritterRig.build(holder, k)
		ok(rig.has("root") and rig["root"] != null, "%s built a rig root" % k)
		ok(rig["body_mat"] != null, "%s has a body material for the hit flash" % k)
		ok((rig["mats"] as Array).size() > 0, "%s registered materials for coat swaps" % k)
		var fam := String(rig["family"])
		if fam in ["CERVID", "URSID", "CANID", "FELID", "MUSTELID", "RODENT_S"]:
			eq((rig["legs"] as Array).size(), 4, "%s is a quadruped with four legs" % k)
			eq((rig["knees"] as Array).size(), 4, "%s has a knee per leg" % k)
		if fam.begins_with("BIRD"):
			eq((rig["wings"] as Array).size(), 2, "%s has two wings" % k)
			eq((rig["legs"] as Array).size(), 2, "%s stands on two legs" % k)
		if fam != "SWARM" and fam != "FISH":
			ok(rig["head"] != null, "%s has a head" % k)
		## Nothing may build a body of nothing. A swarm member IS one box (plus
		## wings if it has them) — that is the point of a swarm, so it gets the
		## lower bar rather than an exemption.
		var meshes := _count_meshes(rig["root"] as Node)
		if fam == "SWARM":
			ok(meshes >= 1, "%s has a body to instance into the swarm" % k)
		else:
			ok(meshes >= 3, "%s is made of more than a box (%d parts)" % [k, meshes])
		holder.queue_free()

	## Species-specific tells that prove the feature flags reach the geometry.
	var moose := _rig_of("moose")
	var deer := _rig_of("whitetail")
	ok(moose["antler"] != null, "the moose has antlers")
	ok(moose.has("dewlap") and moose["dewlap"] != null, "the moose has its bell")
	ok(deer["antler"] != null, "the buck has antlers")
	ok(not deer.has("dewlap") or deer.get("dewlap") == null, "the deer has no bell")
	ok(_rig_of("porcupine")["quills"] != null, "the porcupine has a quill set to raise")
	ok(_rig_of("turkey")["fan"] != null, "the turkey has a tail fan to spread")
	ok(_rig_of("blue_jay")["crest"] != null, "the jay has a crest to raise")
	ok(_rig_of("garter_snake").has("segments"), "the snake is a chain of segments")
	ok((_rig_of("garter_snake")["segments"] as Array).size() >= 6, "the snake has enough segments to slither")
	ok(_rig_of("snapper").has("shell"), "the snapper has a carapace")
	## A lynx must not be a bobcat: the ear tufts and the snowshoe paws are the
	## whole difference, and they come from the dex.
	ok(float(CritterDex.feat("lynx", "tuft", 0.0)) > float(CritterDex.feat("bobcat", "tuft", 0.0)),
		"the lynx has bigger ear tufts than the bobcat")
	ok(float(CritterDex.feat("lynx", "bigpaw", 1.0)) > float(CritterDex.feat("bobcat", "bigpaw", 1.0)),
		"the lynx has the snowshoe feet")


func _rig_of(k: String) -> Dictionary:
	var holder := Node3D.new()
	_world.add_child(holder)
	return CritterRig.build(holder, k)


func _count_meshes(n: Node) -> int:
	var c := 0
	if n is MeshInstance3D:
		c += 1
	for ch in n.get_children():
		c += _count_meshes(ch)
	return c


## ================================= spawn ==================================


func t_spawn() -> void:
	print("-- spawn --")
	var made: Array[Critter] = []
	for k in CritterDex.keys():
		var c := Critter.make(k)
		_world.add_child(c)
		c.global_position = Vector3(randf_range(-200.0, 200.0), 1.0, randf_range(-200.0, 200.0))
		made.append(c)
	await process_frame
	await physics_frame

	for c in made:
		var k := c.species
		ok(c.is_inside_tree(), "%s entered the tree" % k)
		ok(not c.rig.is_empty(), "%s built its rig on _ready" % k)
		ok(c.loco_root != null, "%s wired loco_root for the footfall bob" % k)
		ok(c.health == c.max_health, "%s spawned at full health" % k)
		ok(c.is_in_group("critters"), "%s is on the critter bus" % k)
		eq(c.display_name, String(CritterDex.get_profile(k)["nm"]), "%s carries its name" % k)
		if CritterDex.flag(k, "nofight", false):
			near(c.attack_damage, 0.0, 0.001, "%s can never hurt anything" % k)
		## HitFX must resolve every animal as flesh — that is what makes the
		## blood toggle, the bestiary and the weapon tables work on day one.
		eq(HitFX.kind_of(c), "flesh", "%s bleeds through the existing HitFX path" % k)
		## The territory anchor is where the spawner PUT it, not the world
		## origin it was standing on during _ready(). Every spawner in the
		## game positions AFTER add_child — 2026-09-14: all of Myrkfell's
		## wildlife was walking home to (0, 0, 0) and piling up on the first
		## wall in the way.
		var off := c._home.distance_to(c.global_position)
		ok(off < 1.0, "%s calls the place it was put home (%.1f m off)" % [k, off])

	## Bigger animals get bigger collision. This is the cheapest proof the dex
	## numbers are actually reaching the body.
	var moose := _find(made, "moose")
	var chick := _find(made, "chickadee")
	ok(moose != null and chick != null, "found the moose and the chickadee")
	if moose != null and chick != null:
		ok(_col_h(moose) > _col_h(chick) * 4.0,
			"the moose's collision dwarfs the chickadee's (%.2f vs %.2f)" % [_col_h(moose), _col_h(chick)])

	for c in made:
		c.queue_free()
	await process_frame


func _find(arr: Array[Critter], k: String) -> Critter:
	for c in arr:
		if c.species == k:
			return c
	return null


func _col_h(c: Critter) -> float:
	for ch in c.get_children():
		if ch is CollisionShape3D:
			var s := (ch as CollisionShape3D).shape
			if s is BoxShape3D:
				return (s as BoxShape3D).size.y
	return 0.0


## =============================== behaviour ================================


func t_behaviour() -> void:
	print("-- behaviour --")

	## A SKITTER runs. Put a hare next to the player and it must not be there
	## a second later.
	_player.global_position = Vector3.ZERO
	var hare := Critter.make("hare")
	_world.add_child(hare)
	hare.global_position = Vector3(0, 1, 4)
	await physics_frame
	var d0 := hare.global_position.distance_to(_player.global_position)
	for _i in range(90):
		await physics_frame
	var d1 := hare.global_position.distance_to(_player.global_position)
	ok(d1 > d0, "the hare fled the player (%.1f m -> %.1f m)" % [d0, d1])
	ok(hare.mood == Critter.Mood.FLEE or d1 > d0 + 2.0, "the hare is in flight")
	hare.queue_free()

	## A BLUFFER does NOT run — it warns, and it holds the ground it warned on.
	## The MOOSE is the honest bluffer now (two rungs on the ladder); the bear
	## has its own, much shorter one, asserted below.
	var bull := Critter.make("moose")
	_world.add_child(bull)
	bull.global_position = Vector3(0, 1, 6)
	await physics_frame
	for _i in range(30):
		await physics_frame
	ok(bull.mood == Critter.Mood.WARN or bull.mood == Critter.Mood.ALERT,
		"the moose stood its ground and warned (mood %d)" % bull.mood)
	ok(bull.mood != Critter.Mood.CHARGE, "the moose did not charge on the first warning")
	ok(bull.global_position.distance_to(_player.global_position) < 16.0, "the moose did not bolt")
	bull.queue_free()

	## Hurting a bluffer ends the bluffing.
	var bear2 := Critter.make("black_bear")
	_world.add_child(bear2)
	bear2.global_position = Vector3(0, 1, 6)
	await physics_frame
	bear2.take_damage(20.0, _player.global_position, false, null, _player)
	await physics_frame
	ok(bear2._bluff_count >= bear2.bold or bear2.mood == Critter.Mood.CHARGE,
		"a hurt bear stops bluffing")
	bear2.queue_free()

	## THE BEAR DOES NOT BACK DOWN. One warning, then it commits — and it stays
	## committed: it does not drop back to huffing after it lands a hit, it
	## cannot be spooked, it never routs, and it follows.
	var b3 := Critter.make("black_bear")
	_world.add_child(b3)
	_player.global_position = Vector3(700, 1, 700)
	b3.global_position = Vector3(700, 1, 706)
	await physics_frame
	eq(b3.bold, 1, "the bear gives exactly one warning")
	ok(b3.relentless, "the bear is relentless")
	near(b3.nerve, 0.0, 0.001, "the bear has no breaking point")
	ok(b3.chase_speed > 8.0, "the bear (%.1f) outruns a sprinting player (8.0)" % b3.chase_speed)
	ok(b3.leash_radius >= 50.0, "the bear follows a long way (%.0f m)" % b3.leash_radius)

	## One warning, then the charge — no second huff required.
	for _i in range(70):
		await physics_frame
		if b3.mood == Critter.Mood.CHARGE:
			break
	eq(b3.mood, Critter.Mood.CHARGE, "the bear charged after ONE warning")

	## Landing a hit must not send it back to warning.
	b3._bluff_count = 3
	b3._set_mood(Critter.Mood.CHARGE, 3.0)
	b3.global_position = _player.global_position + Vector3(0, 0, 1.2)
	b3.attack_cd = 0.0
	var hp_before: float = _player.damage_taken
	for _i in range(6):
		await physics_frame
	ok(_player.damage_taken > hp_before, "the bear landed a hit (%.0f dmg)" % (_player.damage_taken - hp_before))
	ok(b3.mood == Critter.Mood.CHARGE, "and it is STILL charging, not backing off")

	## Nothing spooks it.
	b3._spook(_player.global_position, Telegraph.Threat.PANIC)
	ok(b3.mood != Critter.Mood.FLEE, "a panic alarm does not put the bear to flight")
	b3.hear_alarm(_player.global_position, Telegraph.Threat.PANIC, "Test")
	ok(b3.mood != Critter.Mood.FLEE, "and neither does the rest of the forest bolting")

	## Hurting it does not break it.
	b3.take_damage(200.0, _player.global_position, false, null, _player)
	await physics_frame
	ok(not b3.dying, "the bear survived the hit")
	ok(not b3.routing, "a bear at %.0f/%.0f health has NOT broken" % [b3.health, b3.max_health])
	ok(b3.mood == Critter.Mood.CHARGE, "being hurt put it back on you")

	## But there is an honest way out: get far enough away. (Long enough to
	## outlast the flinch from that 200-damage hit — a flinching animal is not
	## running its brain at all, which cost a red herring the first time.)
	_player.global_position = b3.global_position + Vector3(0, 0, b3.leash_radius + 25.0)
	for _i in range(90):
		await physics_frame
	ok(b3.mood == Critter.Mood.EASY, "past its leash the bear gives up — the way out is distance")
	b3.queue_free()

	## The moose still bluffs properly. If the bear change had leaked into the
	## archetype rather than the dex, this is what would catch it.
	var mo := Critter.make("moose")
	_world.add_child(mo)
	await physics_frame
	eq(mo.bold, 2, "the moose still gives two warnings")
	ok(not mo.relentless, "the moose is not relentless — it is a bluffer, like a real one")
	ok(mo.nerve > 0.0, "and a moose can still be driven off")
	mo.queue_free()

	## A STALKER hunts wildlife, not you.
	var lynx := Critter.make("lynx")
	var prey := Critter.make("hare")
	_world.add_child(lynx)
	_world.add_child(prey)
	lynx.global_position = Vector3(60, 1, 60)
	prey.global_position = Vector3(66, 1, 60)
	await physics_frame
	var found := lynx._find_prey()
	ok(found != null, "the lynx found something to hunt")
	ok(found == prey, "the lynx marked the hare")
	## ...and it will not mark something bigger than itself.
	var big := Critter.make("moose")
	_world.add_child(big)
	big.global_position = Vector3(62, 1, 62)
	await physics_frame
	ok(lynx._find_prey() != big, "the lynx is not stalking a moose")
	lynx.queue_free()
	prey.queue_free()
	big.queue_free()
	await process_frame


## =============================== telegraph ================================


func t_telegraph() -> void:
	print("-- telegraph --")
	var tele := Telegraph.new()
	_world.add_child(tele)
	await process_frame
	ok(Telegraph.get_bus(_world) == tele, "the telegraph bus is reachable")

	## One deer blows and the whole hillside knows.
	var herd: Array[Critter] = []
	for i in range(5):
		var d := Critter.make("whitetail")
		_world.add_child(d)
		d.global_position = Vector3(300 + i * 5.0, 1, 300)
		herd.append(d)
	await physics_frame
	for d in herd:
		eq(d.mood, Critter.Mood.EASY, "the herd started calm")

	Telegraph.ring(_world, Vector3(300, 1, 300), 40.0, Telegraph.Threat.ALARM, "Test")
	await physics_frame
	var spooked := 0
	for d in herd:
		if d.mood != Critter.Mood.EASY:
			spooked += 1
	ok(spooked >= 4, "the alarm reached the herd (%d of 5)" % spooked)

	## The player can read it back — that is the counter-intelligence.
	var line := tele.read_the_woods(Vector3(305, 1, 300))
	ok(line != "", "the woods told the player something: '%s'" % line)
	ok(tele.read_the_woods(Vector3(9000, 1, 9000)) == "", "and said nothing from a mile away")
	ok(tele.alarm_level_at(Vector3(302, 1, 300)) >= Telegraph.Threat.ALARM,
		"the patch is flagged as wound up")
	ok(tele.alarm_level_at(Vector3(900, 1, 900)) < 0, "elsewhere is calm")

	## A predator hears opportunity, not danger.
	var coy := Critter.make("coyote")
	_world.add_child(coy)
	coy.global_position = Vector3(310, 1, 300)
	await physics_frame
	coy.hear_alarm(Vector3(300, 1, 300), Telegraph.Threat.ALARM, "Test")
	ok(coy.mood != Critter.Mood.FLEE, "the coyote did not flee its own dinner bell")

	## Alarms expire.
	for _i in range(6):
		await process_frame
	ok(tele.recent.size() > 0, "the alarm is still warm a moment later")

	for d in herd:
		d.queue_free()
	coy.queue_free()
	tele.queue_free()
	await process_frame


## ================================ seasons =================================


func t_seasons() -> void:
	print("-- seasons --")
	eq(CritterDex.season_of(0.10), CritterDex.SPRING, "0.10 is spring")
	eq(CritterDex.season_of(0.35), CritterDex.SUMMER, "0.35 is summer")
	eq(CritterDex.season_of(0.60), CritterDex.AUTUMN, "0.60 is autumn")
	eq(CritterDex.season_of(0.90), CritterDex.WINTER, "0.90 is winter")

	## The coat swap: brown in summer, white in deep winter, and CAUGHT OUT in
	## between — which is the real behaviour and the best thing in the system.
	var hare := Critter.make("hare")
	_world.add_child(hare)
	hare.set_clock(12.0, 0.35)
	near(hare._coat, 0.0, 0.01, "the hare is brown in summer")
	hare.set_clock(12.0, 0.90)
	near(hare._coat, 1.0, 0.01, "the hare is white in deep winter")
	hare.set_clock(12.0, 0.72)
	ok(hare._coat > 0.1 and hare._coat < 0.9,
		"the hare is halfway white in late autumn (%.2f) — caught out on bare ground" % hare._coat)
	hare.queue_free()

	## Night eyes.
	var coy := Critter.make("coyote")
	_world.add_child(coy)
	coy.set_clock(23.0, 0.35)
	ok(coy._night, "the coyote knows it is night")
	coy.set_clock(12.0, 0.35)
	ok(not coy._night, "and knows when it is not")
	coy.queue_free()

	## Wind's own season maths is what everything reads.
	near(Wind.phase_for_day(0.0), 0.0, 0.001, "day zero is phase zero")
	near(Wind.phase_for_day(96.0), 0.0, 0.001, "a year is 96 days and wraps")
	eq(Wind.season_name(0.0), "Spring", "the year starts in spring")
	eq(Wind.season_name(80.0), "Winter", "day 80 is winter")


## ================================= audio ==================================


func t_audio() -> void:
	print("-- audio --")
	var au := CritterAudio.new()
	_world.add_child(au)
	var rep := au.report()
	print("   audio: %d in manifest, %d referenced, %d found" %
		[int(rep["manifest"]), int(rep["referenced"]), int(rep["found"])])
	ok(int(rep["manifest"]) > 0, "the wildlife audio manifest loaded")
	eq(rep["missing"], [], "every call a species asks for exists as a file")
	ok(int(rep["found"]) == int(rep["referenced"]), "no species is mute by accident")

	## The bed picks the right ambience for the hour and the season.
	eq(au.bed_for("bog", 22.0, 0.05), "peepers", "spring night on a bog is peepers")
	eq(au.bed_for("bog", 22.0, 0.40), "crickets", "summer night is crickets")
	eq(au.bed_for("field", 12.0, 0.40), "", "midday in a field has no bed")
	eq(au.bed_for("deep_woods", 22.0, 0.90), "", "a winter night is silent")
	ok(au.bed_for("bog", 12.0, 0.10) == "blackflies", "late spring bogs have blackflies")

	## The loon must carry further than the chipmunk.
	ok(float(CritterAudio.CARRY.get("loon_wail", 0.0)) > CritterAudio.CARRY_DEFAULT * 3.0,
		"a loon carries across the lake")
	ok(float(CritterAudio.CARRY.get("deer_snort", 0.0)) < float(CritterAudio.CARRY.get("coyote_chorus", 0.0)),
		"a coyote chorus carries further than a deer's snort")
	au.queue_free()


## ============================== spawn menu ================================


func t_spawn_menu() -> void:
	## The M menu builds its wildlife rows out of the dex at runtime, so the
	## thing to assert is COVERAGE: every species reachable, nothing listed
	## twice, and legends kept in their own bucket. Player.gd is 6,600 lines
	## and needs a real scene to instance, so this checks the grouping logic
	## the menu consumes rather than the buttons themselves.
	print("-- spawn menu --")
	var buckets := {
		"BIG GAME": ["CERVID", "URSID"],
		"PREDATORS": ["CANID", "FELID", "MUSTELID"],
		"CRITTERS": ["CHUNK", "RODENT_S"],
		"BIRDS": ["BIRD_GROUND", "BIRD_RAPTOR", "BIRD_PERCH", "BIRD_WATER"],
		"WATER & COLD BLOOD": ["HERP", "FISH"],
		"SWARMS & BUGS": ["SWARM"],
	}
	## Every rig family must land in exactly one bucket, or a species silently
	## vanishes from the menu the day someone adds a new family.
	var covered: Dictionary = {}
	for g in buckets.keys():
		for fam in (buckets[g] as Array):
			ok(not covered.has(fam), "rig family %s is in exactly one menu bucket" % fam)
			covered[fam] = g
	for fam in CritterRig.FAMILIES:
		ok(covered.has(fam), "rig family %s has a home in the spawn menu" % fam)

	var seen: Dictionary = {}
	var listed := 0
	for k in CritterDex.keys():
		var fam := CritterDex.rig_of(k)
		if CritterDex.flag(k, "legend", false):
			continue
		ok(covered.has(fam), "%s (%s) reaches the menu" % [k, fam])
		ok(not seen.has(k), "%s is listed only once" % k)
		seen[k] = true
		listed += 1
	var legend_n := CritterDex.legends().size()
	ok(listed + legend_n == CritterDex.count(),
		"the menu covers the whole roster (%d + %d legends = %d)" % [listed, legend_n, CritterDex.count()])
	print("   menu: %d species across %d groups, %d legends" % [listed, buckets.size(), legend_n])

	## Every button needs a display name short enough to be worth clipping to,
	## and a species key the spawner can actually resolve.
	for k in CritterDex.keys():
		var nm := String(CritterDex.get_profile(k).get("nm", ""))
		ok(nm != "", "%s has a button label" % k)
		ok(nm.length() <= 30, "%s's label fits a button ('%s', %d chars)" % [k, nm, nm.length()])
		ok(CritterDex.has(k), "%s resolves for the spawner" % k)


## ================================ director ================================


func t_director() -> void:
	print("-- director --")
	## Back inside the world. Earlier tests park the player hundreds of metres
	## out to keep their animals from colliding, and the director correctly
	## refuses to spawn outside the world radius — which reads as "the spawner
	## is broken" if you forget to walk back.
	_player.global_position = Vector3(0, 1, 0)
	var tele := Telegraph.new()
	_world.add_child(tele)
	var dir := WildlifeDirector.new()
	dir.player = _player
	dir.world_radius = 80.0
	_world.add_child(dir)
	await process_frame
	dir.set_clock(19.0, 30.0)

	## It must never scatter a legend.
	for _i in range(200):
		var k := dir._roll_species("deep_woods")
		ok(k == "" or not CritterDex.flag(k, "legend", false), "the roller never returns a legend")
		ok(k == "" or CritterDex.rig_of(k) != "SWARM", "the roller never returns a swarm as a critter")
		if fail_n > 0:
			break

	## Nocturnal things at noon, and denned bears in winter, must not be rolled.
	dir.set_clock(12.0, 30.0)
	var noon_rolls: Dictionary = {}
	for _i in range(400):
		var k := dir._roll_species("deep_woods")
		if k != "":
			noon_rolls[k] = true
	ok(not noon_rolls.has("barred_owl"), "no owls rolled at noon")
	ok(not noon_rolls.has("bat"), "no bats rolled at noon")
	dir.set_clock(12.0, 80.0)   ## deep winter
	var winter_rolls: Dictionary = {}
	for _i in range(400):
		var k := dir._roll_species("deep_woods")
		if k != "":
			winter_rolls[k] = true
	ok(not winter_rolls.has("black_bear"), "no bears rolled in winter — they are denned")

	## The budget is a real ceiling.
	dir.set_clock(19.0, 30.0)
	for _i in range(240):
		dir._spawn_t = 0.0
		await physics_frame
	ok(dir.live.size() <= WildlifeDirector.BUDGET,
		"the spawn budget held (%d <= %d)" % [dir.live.size(), WildlifeDirector.BUDGET])
	ok(dir.live.size() > 0, "the director actually spawned something (%d)" % dir.live.size())
	var census := dir.census()
	print("   census: %d live, %d swarms, zone %s, %s" %
		[int(census["live"]), int(census["swarms"]), String(census["zone"]), String(census["season"])])

	## Nothing spawned on the player's face.
	for c in dir.live:
		if is_instance_valid(c):
			ok(c.global_position.distance_to(_player.global_position) >= WildlifeDirector.SPAWN_RING.x - 8.0,
				"%s did not spawn in the player's lap" % c.species)
			if fail_n > 0:
				break

	## The zone map is total — every point resolves to a real zone.
	for r in [0.0, 0.1, 0.3, 0.5, 0.7, 0.9, 1.0]:
		var z := dir._zone_at(Vector3(80.0 * r, 0, 0))
		ok(CritterDex.ZONES.has(z), "radius %.1f resolves to a real zone (%s)" % [r, z])

	dir.queue_free()
	tele.queue_free()
	await process_frame


## =============================== save/load ================================


func t_saveload() -> void:
	print("-- save/load --")
	var dir := WildlifeDirector.new()
	dir.player = _player
	_world.add_child(dir)
	await process_frame
	dir.set_clock(19.0, 30.0)

	## Inside the streaming radius, or the director's own cull will (correctly)
	## delete them before the save is taken.
	_player.global_position = Vector3(120, 1, 110)
	var a := dir.spawn_one("moose", Vector3(120, 1, 120))
	var b := dir.spawn_one("red_fox", Vector3(126, 1, 120))
	await physics_frame
	ok(a != null and b != null, "hand-placed two animals")
	ok(is_instance_valid(a) and is_instance_valid(b), "and the cull did not eat them")
	a.health = 91.0
	var state := dir.save_state()
	eq((state["critters"] as Array).size(), 2, "both were written to the save")

	dir.apply_state(state)
	await physics_frame
	await process_frame
	eq(dir.live.size(), 2, "both came back")
	var species_back: Array = []
	var hp_back := 0.0
	for c in dir.live:
		if is_instance_valid(c):
			species_back.append(c.species)
			if c.species == "moose":
				hp_back = c.health
	ok(species_back.has("moose") and species_back.has("red_fox"), "the right two came back")
	near(hp_back, 91.0, 0.01, "the wounded moose came back wounded")

	## A round trip must not multiply the forest.
	dir.apply_state(dir.save_state())
	await physics_frame
	eq(dir.live.size(), 2, "a second round trip did not duplicate anything")

	## The M menu's spawns are adopted, so they save with the world too — and
	## adopting twice must not double-count.
	var hand := Critter.make("porcupine")
	_world.add_child(hand)
	hand.global_position = Vector3(122, 1, 112)
	await physics_frame
	var before := dir.live.size()
	dir.adopt(hand)
	dir.adopt(hand)
	eq(dir.live.size(), before + 1, "a menu-spawned critter is adopted exactly once")
	ok((dir.save_state()["critters"] as Array).size() == before + 1,
		"and it is written to the save")
	## An adopted legend must not be handed to the legend gate, or spawning one
	## at the wrong time of day gets it silently deleted a moment later.
	var lg := Critter.make("white_raven")
	_world.add_child(lg)
	lg.global_position = Vector3(124, 1, 112)
	await physics_frame
	dir.adopt(lg)
	ok(not dir.legends_placed.has("white_raven"),
		"a hand-spawned legend is not registered with the gate that would retire it")
	dir._legend_t = 0.0
	dir._legend_check()
	await physics_frame
	ok(is_instance_valid(lg), "so it survives the next legend check")

	dir.queue_free()
	await process_frame


## =============================== specials =================================


func t_specials() -> void:
	print("-- specials --")

	## Quills: reach into a porcupine and it costs you.
	var porc := Critter.make("porcupine")
	_world.add_child(porc)
	porc.global_position = Vector3(500, 1, 500)
	_player.global_position = Vector3(500, 1, 500.6)
	_player.damage_taken = 0.0
	_player.quills = 0
	porc.take_damage(5.0, _player.global_position, false, null, _player)
	ok(_player.damage_taken > 0.0, "swinging at a porcupine hurt (%.1f)" % _player.damage_taken)
	eq(_player.quills, 3, "and left quills in you")
	porc.queue_free()

	## The skunk's answer is social, not lethal.
	var skunk := Critter.make("skunk")
	_world.add_child(skunk)
	skunk.global_position = Vector3(520, 1, 520)
	_player.global_position = Vector3(520, 1, 522)
	_player.stink_t = 0.0
	skunk._bluff_count = 2
	skunk._do_spray(_player)
	ok(_player.stink_t > 0.0, "the skunk sprayed you (%.0f s)" % _player.stink_t)
	ok(skunk._spray_cool > 0.0, "and cannot immediately do it again")
	skunk.queue_free()

	## The snapper does not let go.
	var snap := Critter.make("snapper")
	_world.add_child(snap)
	snap.global_position = Vector3(540, 1, 540)
	_player.global_position = Vector3(540, 1, 541)
	snap.try_latch(_player)
	ok(snap._latched == _player, "the snapper latched on")
	ok(snap._latch_t > 0.0, "and is holding")
	snap.queue_free()

	## The opossum's answer to being caught is not running.
	var poss := Critter.make("opossum")
	_world.add_child(poss)
	poss.global_position = Vector3(560, 1, 560)
	var played := false
	for _i in range(40):
		poss._playing_dead = false
		poss._spook(Vector3(560, 1, 562), Telegraph.Threat.ALARM)
		if poss._playing_dead:
			played = true
			break
	ok(played, "the opossum played dead")
	eq(poss._sig, "play_dead", "and is holding the pose")
	poss.queue_free()

	## THE REAR-UP. Four separate promises, each asserted on its own.
	print("   (bear rear-up)")
	var br := Critter.make("black_bear")
	_world.add_child(br)
	br.global_position = Vector3(800, 1, 800)
	_player.global_position = Vector3(800, 1, 806)
	await physics_frame

	## 1. IT NEEDS TWO THIRDS OF ITS HEALTH.
	ok(br.can_play("bear_stand"), "a healthy bear can rear up")
	br.health = br.max_health * 0.70
	ok(br.can_play("bear_stand"), "at 70%% health it still can")
	br.health = br.max_health * 0.66
	ok(not br.can_play("bear_stand"), "at 66%% health it cannot — the gate is two thirds")
	br.health = br.max_health * 0.20
	ok(not br.can_play("bear_stand"), "and a badly hurt bear certainly cannot")
	ok(br._payoff_sig() == "", "so it has no payoff move to open with")
	br.health = br.max_health
	eq(br._payoff_sig(), "bear_stand", "restored, the rear-up is its opener again")
	## The gate must actually stop the animation, not just the picker.
	br.health = br.max_health * 0.3
	br._play_sig("bear_stand")
	ok(br._sig != "bear_stand", "_play_sig refuses a gated move outright")
	br.health = br.max_health

	## 2. IT STOPS IN PLACE.
	br._play_sig("bear_stand")
	eq(br._sig, "bear_stand", "the bear reared up")
	ok(br.is_rooted(), "and it is rooted while it does")
	br.velocity = Vector3(6.0, 0.0, 6.0)
	var where := br.global_position
	for _i in range(30):
		await physics_frame
	## HORIZONTAL only. The lab world has no ground collider, so an unrooted
	## body free-falls — and 30 frames of gravity is 1.2 m, which reads as
	## "it slid" on a 3D distance check and sent me looking for a bug in the
	## root that was not there.
	var moved := Vector2(br.global_position.x - where.x, br.global_position.z - where.z).length()
	ok(moved < 0.05, "it stayed exactly put (%.3f m) with velocity thrown at it" % moved)
	ok(br._sig == "bear_stand", "and it is still standing")

	## 3. THE FRONT LEGS LEAVE THE GROUND WITH THE BODY.
	## Measured off the real rig: the world height of a front paw at the top of
	## the rear-up versus at rest. Before this pass the hips were parented to
	## `root`, so the chest rose and all four feet stayed nailed to the dirt.
	## NOTE: no `await` between posing and measuring. Node3D transforms update
	## the moment they are set, but a physics frame runs _animate, which lays
	## the idle overlay back over the pose — awaiting here measured the idle
	## pose and reported a lift of exactly zero for a working animation.
	br._sig = ""
	CritterAnim.neutral(br.rig)
	var fl: Node3D = (br.rig["knees"] as Array)[0]
	var hl: Node3D = (br.rig["knees"] as Array)[2]
	var front_rest := fl.global_position.y - br.global_position.y
	var hind_rest := hl.global_position.y - br.global_position.y
	CritterAnim.play(br.rig, "bear_stand", 0.60, 0.016, br)
	var front_up := fl.global_position.y - br.global_position.y
	var hind_up := hl.global_position.y - br.global_position.y
	var lift := front_up - front_rest
	ok(lift > 0.35, "the front paws come off the ground (+%.2f m at the top of the rear)" % lift)
	ok(lift > (hind_up - hind_rest) * 3.0,
		"and they rise far more than the hind feet do (%.2f m vs %.2f m) — it is standing ON the hind legs"
			% [lift, hind_up - hind_rest])
	## The body must go up too, or the legs are just detaching.
	var body_n: Node3D = br.rig["body"] as Node3D
	CritterAnim.neutral(br.rig)
	var body_rest := body_n.global_position.y
	CritterAnim.play(br.rig, "bear_stand", 0.60, 0.016, br)
	ok(body_n.global_position.y - body_rest > 0.1,
		"the body rises with them (+%.2f m)" % (body_n.global_position.y - body_rest))
	CritterAnim.neutral(br.rig)

	## 4. COMING ALL THE WAY DOWN PAYS OUT.
	near(br.buff_atk, 1.0, 0.001, "no buff while it is still up there")
	near(br.buff_def, 1.0, 0.001, "and no defensive buff either")
	var base_atk := br.attack_power()
	br._sig = "bear_stand"
	br._sig_t = 0.999
	br._sig_len = 1.0
	br._animate(0.5)          ## push it past the end — the full return to ground
	ok(br.buff_t > 0.0, "finishing the move granted a buff (%.0f s)" % br.buff_t)
	ok(br.buff_atk > 1.0, "attack is up (x%.2f)" % br.buff_atk)
	ok(br.buff_def < 1.0, "and it takes less damage (x%.2f)" % br.buff_def)
	ok(br.attack_power() > base_atk,
		"so it hits harder (%.0f -> %.0f)" % [base_atk, br.attack_power()])
	## The defensive half must actually reach take_damage.
	var hp0 := br.health
	br.flinch_timer = 0.0
	br.take_damage(100.0, _player.global_position, false, null, null)
	var took := hp0 - br.health
	ok(took < 99.0, "a 100-point hit landed for %.0f — the guard is real" % took)
	near(took, 100.0 * br.buff_def, 0.5, "and it is exactly the buff multiplier")

	## It cannot chain: no second rear-up while the first is still paying.
	br.health = br.max_health
	ok(not br.can_play("bear_stand"), "it cannot rear up again while buffed")

	## And cutting the move short pays nothing.
	var br2 := Critter.make("black_bear")
	_world.add_child(br2)
	br2.global_position = Vector3(820, 1, 820)
	await physics_frame
	br2._play_sig("bear_stand")
	eq(br2._sig, "bear_stand", "the second bear reared up")
	br2._sig_t = 0.5
	br2._end_sig()            ## interrupted — a hit, a flinch, anything
	near(br2.buff_atk, 1.0, 0.001, "a rear-up cut short pays nothing")
	near(br2.buff_t, 0.0, 0.001, "and grants no time")
	br.queue_free()
	br2.queue_free()
	await process_frame

	## SWATTING. A swing kills blackflies and only blackflies.
	var flies := CritterSwarm.make("blackfly", Vector3(600, 1, 600))
	_world.add_child(flies)
	await process_frame
	var n0 := flies.alive_count()
	eq(n0, flies.count, "the cloud starts whole (%d)" % n0)

	## A swing behind you kills nothing — the arc is an arc.
	var behind := flies.swat(Vector3(600, 1.4, 604), 3.0, Vector3(0, 0, 1))
	eq(behind, 0, "a swing pointing away from the cloud kills nothing")
	eq(flies.alive_count(), n0, "and the cloud is untouched")

	## A swing into it kills a real number of them.
	var killed := flies.swat(Vector3(600, 1.5, 600), 3.0, Vector3(0, 0, -1))
	ok(killed > 0, "the swing killed blackflies (%d)" % killed)
	eq(flies.alive_count(), n0 - killed, "the dead are actually gone from the cloud")


	## They come back — a swing is relief, not a solution.
	for _i in range(4):
		await process_frame
	ok(flies.alive_count() == n0 - killed, "they stay dead for a while")
	var soonest := 999.0
	for i in range(flies._dead.size()):
		if flies._dead[i] > 0.0:
			soonest = minf(soonest, flies._dead[i])
	ok(soonest >= CritterSwarm.RESPAWN.x - 1.0,
		"and the first one back is at least %.0f s away (%.1f)" % [CritterSwarm.RESPAWN.x, soonest])

	## Killing them all stops the biting; nothing bites from an empty cloud.
	for i in range(flies.count):
		flies._dead[i] = 10.0
	eq(flies.alive_count(), 0, "the whole cloud can be cleared")
	_player.bites = 0.0
	_player.global_position = flies.global_position
	flies._harass(_player, 1.0)
	near(_player.bites, 0.0, 0.0001, "an empty cloud does not bite")
	## Half a cloud bites half as hard.
	for i in range(flies.count):
		flies._dead[i] = 10.0 if i % 2 == 0 else 0.0
	_player.bites = 0.0
	flies._harass(_player, 1.0)
	ok(_player.bites > 0.0 and _player.bites < CritterSwarm.HARASS_DPS,
		"a half-swatted cloud bites at half strength (%.3f)" % _player.bites)
	flies.queue_free()

	## THE REAL GEOMETRY — through swat_from(), exactly the way the game calls
	## it. THIS IS THE ASSERTION THAT WAS MISSING, and its absence is why this
	## shipped broken: the old test hand-picked a swat point at the middle of
	## the cloud and passed, while the game anchored the sweep a metre in FRONT
	## of the player. Blackflies orbit your head, so most of the cloud sat
	## behind the swing origin and a real swing killed 6 of 60.
	##
	## Rule taken from it: anything the player's swing depends on is tested
	## through the player's own call path, not through a convenient inner one.
	## Its own swarm, so nothing above depends on the state this leaves.
	var f2 := CritterSwarm.make("blackfly", Vector3(640, 1, 640))
	_world.add_child(f2)
	_player.global_position = f2.global_position   ## standing in the cloud
	await process_frame
	eq(f2.alive_count(), f2.count, "a fresh cloud is whole (%d)" % f2.count)
	var swing1 := CritterSwarm.swat_from(_player, Vector3(0, 0, -1), 2.6)
	ok(swing1 >= int(f2.count * 0.5),
		"one real swing kills at least half the cloud (%d of %d)" % [swing1, f2.count])
	ok(f2.alive_count() > 0, "but not all of it — the first leaves some (%d)" % f2.alive_count())
	var swing2 := CritterSwarm.swat_from(_player, Vector3(0, 0, -1), 2.6)
	ok(swing2 > 0, "the second swing catches the rest (%d)" % swing2)
	eq(f2.alive_count(), 0, "TWO HITS CLEARS THE CLOUD")

	## And a swing from well outside, pointed away, still misses.
	for i in range(f2.count):
		f2._dead[i] = 0.0
	_player.global_position = f2.global_position + Vector3(0, 0, -12.0)
	await process_frame
	eq(CritterSwarm.swat_from(_player, Vector3(0, 0, -1), 2.6), 0,
		"swinging away from a cloud twelve metres off kills nothing")
	eq(f2.alive_count(), f2.count, "the cloud is untouched")
	f2.queue_free()
	await process_frame

	## Fireflies are NOT killable. Swinging near them scatters them and they
	## all live — an axe that murders the prettiest thing in the game for
	## walking past is a punishment, not a mechanic.
	var ff := CritterSwarm.make("firefly", Vector3(620, 1, 620))
	_world.add_child(ff)
	await process_frame
	var f0 := ff.alive_count()
	var f_killed := ff.swat(Vector3(620, 1.5, 620), 4.0, Vector3(0, 0, -1))
	eq(f_killed, 0, "a swing kills no fireflies")
	eq(ff.alive_count(), f0, "every firefly survived")
	ok(ff._scatter_t > 0.0, "but the cloud blew apart — the swing moved air")
	ff.queue_free()

	for k in CritterDex.keys():
		if CritterDex.rig_of(k) != "SWARM":
			ok(not CritterDex.flag(k, "swattable", false),
				"%s is not a swarm and cannot be swatted" % k)
		elif k != "blackfly":
			ok(not CritterDex.flag(k, "swattable", false),
				"%s is not killable by a stray swing" % k)
	ok(CritterDex.flag("blackfly", "swattable", false), "blackflies are")

	## Every signature the dex names must exist in the animation library, or an
	## animal silently does nothing at the moment it matters most.
	var missing: Array = []
	for k in CritterDex.keys():
		for s in (CritterDex.get_profile(k).get("sig", []) as Array):
			if CritterAnim.duration(String(s)) <= 0.0 and not missing.has(String(s)):
				missing.append(String(s))
	eq(missing, [], "every signature animation in the dex is implemented")

	## And the fallback pickers must always find something real.
	for k in CritterDex.keys():
		var c := Critter.make(k)
		_world.add_child(c)
		for picker in [c._alert_sig(), c._warn_sig(), c._flee_sig(), c._pounce_sig()]:
			ok(String(picker) != "", "%s can always pick a signature" % k)
			if fail_n > 0:
				break
		c.queue_free()
		if fail_n > 0:
			break


## ================================== buzz ==================================


func _head_h(rig: Dictionary) -> float:
	var head := rig["head"] as Node3D
	var rt := rig["root"] as Node3D
	return head.global_position.y - rt.global_position.y


func t_buzz() -> void:
	print("-- buzz --")
	## The generic idle library: every clip has a length, every family gets a
	## non-empty (or, for swarms, deliberately empty) list, and every name on
	## those lists actually plays on every rig without the fallback fidget.
	const CLIPS := ["graze", "sniff_ground", "paw_ground", "huff_toss", "wet_shake",
		"stretch", "look_about", "scratch", "sit_rest", "tail_swish", "peck_ground",
		"preen", "ruffle", "wing_stretch", "sun_bask"]
	for c in CLIPS:
		ok(CritterAnim.DUR.has(c) and float(CritterAnim.DUR[c]) > 0.0,
			"buzz clip %s has a duration" % c)
	const FAMS := {"moose": "CERVID", "black_bear": "URSID", "coyote": "CANID",
		"lynx": "FELID", "fisher": "MUSTELID", "porcupine": "CHUNK",
		"red_squirrel": "RODENT_S", "turkey": "BIRD_GROUND", "bald_eagle": "BIRD_RAPTOR",
		"blue_jay": "BIRD_PERCH", "loon": "BIRD_WATER", "snapper": "HERP", "trout": "FISH"}
	eq(CritterAnim.buzz_for("SWARM"), [], "swarms have no buzz")
	CritterAnim.last_unhandled = ""
	for sp: String in FAMS.keys():
		var fam0 := String(FAMS[sp])
		var rig := _rig_of(sp)
		eq(String(rig["family"]), fam0, "%s builds a %s rig" % [sp, fam0])
		var cands0 := CritterAnim.buzz_for(fam0)
		ok(not cands0.is_empty(), "%s has buzz candidates" % fam0)
		for c in cands0:
			ok(CLIPS.has(String(c)), "%s buzz list only names buzz clips (%s)" % [fam0, c])
		for c in CLIPS:
			CritterAnim.play(rig, String(c), 0.5, 1.0 / 60.0)
			CritterAnim.neutral(rig)
		eq(CritterAnim.last_unhandled, "", "every buzz clip has a play() branch on %s" % fam0)

	## Poses, measured on a whitetail.
	var deer := _rig_of("whitetail")
	var head := deer["head"] as Node3D
	var rest_h := _head_h(deer)
	ok(rest_h > 0.5, "a whitetail carries its head high at rest (%.2f)" % rest_h)
	CritterAnim.play(deer, "graze", 0.45, 1.0 / 60.0)
	var graze_h := _head_h(deer)
	ok(graze_h < rest_h - 0.35 * rest_h,
		"graze puts the head down at least 35%% of its height (%.2f -> %.2f)" % [rest_h, graze_h])
	CritterAnim.neutral(deer)
	near(_head_h(deer), rest_h, 0.001, "neutral() lifts the head back")

	var fl := (deer["legs"] as Array)[0] as Node3D
	var fl_rest := fl.rotation.x
	var max_paw := 0.0
	for i in range(41):
		CritterAnim.play(deer, "paw_ground", float(i) / 40.0, 1.0 / 60.0)
		max_paw = maxf(max_paw, absf(fl.rotation.x - fl_rest))
	CritterAnim.neutral(deer)
	ok(max_paw > 0.2, "paw_ground swings the front-left leg (%.2f rad)" % max_paw)
	var neck := deer["neck"] as Node3D
	var neck_rest := neck.rotation
	var head_rest := head.rotation
	var max_toss := 0.0
	for i in range(41):
		CritterAnim.play(deer, "huff_toss", float(i) / 40.0, 1.0 / 60.0)
		max_toss = maxf(max_toss, (neck.rotation.x - neck_rest.x) + (head.rotation.x - head_rest.x))
	CritterAnim.neutral(deer)
	ok(max_toss > 0.25, "huff_toss throws the head up (%.2f rad)" % max_toss)
	var body := deer["body"] as Node3D
	var body_rest := body.rotation
	CritterAnim.play(deer, "wet_shake", 0.3, 1.0 / 60.0)
	ok(absf(body.rotation.z - body_rest.z) > 0.02, "wet_shake rolls the body mid-clip")
	CritterAnim.play(deer, "wet_shake", 1.0, 1.0 / 60.0)
	near(body.rotation.z, body_rest.z, 0.01, "wet_shake ends on rest (before neutral)")
	CritterAnim.neutral(deer)
	near(body.rotation.z, body_rest.z, 0.01, "wet_shake ends on rest (after neutral)")
	var yaw_min := 0.0
	var yaw_max := 0.0
	for i in range(61):
		CritterAnim.play(deer, "look_about", float(i) / 60.0, 1.0 / 60.0)
		yaw_min = minf(yaw_min, neck.rotation.y - neck_rest.y)
		yaw_max = maxf(yaw_max, neck.rotation.y - neck_rest.y)
	CritterAnim.neutral(deer)
	ok(yaw_min < -0.1 and yaw_max > 0.1, "look_about yaws the neck both ways (%.2f..%.2f)" % [yaw_min, yaw_max])

	## The behaviour: a calm deer with the player in sight but outside its
	## notice radius (30 m) buzzes; an alarmed one does not.
	_player.global_position = Vector3(800, 1, 800)
	var d := Critter.make("whitetail")
	_world.add_child(d)
	d.global_position = Vector3(800, 1, 845)
	await physics_frame
	var fam := String(d.rig.get("family", ""))
	eq(fam, "CERVID", "the deer is a cervid")
	var cands := CritterAnim.buzz_for(fam)
	d._sig_cool = 30.0      ## keep the species tells out of the way
	d._call_cool = 60.0
	d._buzz_cool = 0.0
	var got := ""
	for _i in range(12):
		await physics_frame
		if d._sig != "" and got == "":
			got = d._sig
	eq(d.mood, Critter.Mood.EASY, "the deer stayed calm at 45 m")
	ok(cands.has(got), "a calm standing deer played a buzz clip (%s)" % got)
	ok(d.is_buzzing(), "is_buzzing() recognises it")
	ok(d._buzz_cool > 0.0, "the buzz cooldown was reset")
	ok(d._sig_cool >= 29.0, "a buzz clip does not spend the species-signature cooldown")

	## Alarm cuts it: the mood change ends the sig and nothing buzzes while
	## the animal is fleeing.
	_player.global_position = Vector3(800, 1, 843)
	d._buzz_cool = 0.0
	for _i in range(8):
		await physics_frame
		d._buzz_cool = 0.0
	ok(d.mood != Critter.Mood.EASY, "the deer noticed the player at 2 m (mood %d)" % d.mood)
	ok(not cands.has(d._sig), "no buzz clip while alert or fleeing (sig '%s')" % d._sig)
	d._sig_cool = 30.0
	d._end_sig()
	for _i in range(8):
		d._buzz_cool = 0.0
		await physics_frame
	ok(not cands.has(d._sig), "still no buzz while it is not calm (sig '%s')" % d._sig)
	d.queue_free()
	_player.global_position = Vector3.ZERO
