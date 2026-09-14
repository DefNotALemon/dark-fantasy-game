extends SceneTree

# =============================================================================
# tests/CarcassTests.gd -- the carcass economy (2026-09-11, WORLD).
#
#   godot --headless --path . --script res://tests/CarcassTests.gd
#
# Nothing here needs terrain, a Player, World.tscn or a pixel. A carcass is a
# ledger entry billed against by a table of claimants, and every rule about
# who bills when is a pure static function -- so "a gale at four in the
# morning in February" is a call with four arguments rather than something you
# stand in a field and wait for.
#
# Five sections carry more weight than the rest:
#
#   `arrival` -- WHO GETS THERE FIRST, and that it depends on the hour of the
#   kill. Drop a deer at noon and the crows have it inside the hour; drop the
#   same deer at midnight and a fox has been and gone before the crows are
#   even awake. This is the single most visible thing the feature does and it
#   falls straight out of the working-hours table.
#
#   `gale` -- the negative case, and its positive twin in the same section.
#   A scan that comes back empty agrees with everything (2026-09-09 18:00), so
#   "the crows never came" is worthless on its own: the identical fixture in
#   clear air has to show them coming.
#
#   `economy` -- the floors, which are the teeth. Butcher a moose past a
#   quarter and the bear never walks to it; past a fifth and neither does the
#   pack. Stated as LITERAL kilogram margins, because a margin stated against
#   the constant it exists to guard agrees with itself whatever that constant
#   becomes (2026-09-10 03:00, nine of them in one file).
#
#   `linger` -- bones are dated from the ENDING, never the firing. Two
#   carcasses stripped four days apart are forgotten four days apart. Measured
#   from the kill instead, no player would ever walk up to a winter carcass's
#   ribs (the Incident Director's rule, 2026-09-07).
#
#   `chronicle` and `feed` -- the REAL front doors of the two collaborators
#   this file calls into. A STUB IS NOT THE COLLABORATOR: three mutations of
#   `Chronicle.deposit_rumour` survived the Wayfarers' 128/0 green because the
#   only suite that used it used a fake. This file calls `deposit_rumour`,
#   `nearest_place`, `sky_at` and `season_at` on a real Chronicle, `offer` on
#   a real RumourFeed, and `daylight` on the real Crofts.
#
# SECTION CLAIMS: every section stakes what it is about to assert before it
# runs one, so a section killed by a runtime error shows up as a claim that
# never settled instead of quietly taking its assertions with it.
# =============================================================================

const MIN_ASSERTIONS := 150

var _pass := 0
var _fail := 0
var _claims: Dictionary = {}
var _counts: Dictionary = {}
var _section := ""


# --------------------------------------------------------------------- stubs

class FakeSky extends Node:
	## Everything Carcasses asks a Chronicle for on the hot path, and nothing
	## else. The REAL Chronicle gets its own section below -- this exists so
	## that "a gale on day nine in February" is a fixture rather than a wait.
	var sky := 0
	var season := 0

	func sky_at(_t: float) -> int:
		return sky

	func season_at(_t: float) -> int:
		return season


class FakePlayer extends Node3D:
	pass


class FakeDead extends Node3D:
	## A body shaped exactly like the part of a Critter the harvest pass
	## reads, and nothing else: `dying`, `species`, a position, and the
	## `enemies` group. Nothing in this file ever constructs a real Critter,
	## because a real Critter needs a rig, a skin and sixty-five animals of
	## dex to come up.
	var dying := false
	var species := ""


class FakeWild extends Node:
	## Counts what it was ASKED for. The point of this stub is the assertion
	## that the ledger does NOT count what it returns: the director may
	## refuse, and the Incident Director leaked exactly that into a digest
	## two Directors had to agree on.
	var asked: Array = []
	var refuse := false

	func spawn_one(key: String, at: Vector3):
		asked.append({"key": key, "at": at})
		return null if refuse else Node3D.new()


# ------------------------------------------------------------------- harness

func claim(section: String, n: int) -> void:
	_section = section
	_claims[section] = n
	_counts[section] = 0


func ok(cond: bool, what: String) -> void:
	_counts[_section] = int(_counts.get(_section, 0)) + 1
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL  [%s] %s" % [_section, what])


func near_f(a: float, b: float, tol: float, what: String) -> void:
	ok(absf(a - b) <= tol, "%s (got %.4f, want %.4f +/- %.4f)" % [what, a, b, tol])


# ------------------------------------------------------------------ fixtures

const DEER_LEN := 1.70
const MOOSE_LEN := 2.90
const HARE_LEN := 0.42
const START_DAY := 30.0


func _bus(season: int, sky: int, at_hour: float) -> Carcasses:
	var c := Carcasses.new()
	var f := FakeSky.new()
	f.season = season
	f.sky = sky
	c.chron = f
	c.add_child(f)
	c.advance(START_DAY * 24.0 + at_hour)
	return c


func _deer(c: Carcasses) -> Dictionary:
	return c.add("whitetail", "whitetail deer", Vector3.ZERO,
			Carcasses.mass_of("whitetail", DEER_LEN))


func _moose(c: Carcasses) -> Dictionary:
	return c.add("moose", "moose", Vector3.ZERO, Carcasses.mass_of("moose", MOOSE_LEN))


func _run_hours(c: Carcasses, hours: float) -> void:
	var bites := int(hours / 6.0)
	for _i in bites:
		c.advance(6.0)


func _seen_h(rec: Dictionary, guild: String) -> float:
	## Hours after the kill that this guild turned up, or -1 if it never
	## did. Deliberately a READ and not a run, which the first draft got
	## wrong: it ran the clock until somebody turned up and returned then,
	## so asking about a SECOND guild afterwards asked about a world that
	## had only lived six hours. The crows came back as never having come
	## on a fixture that had not yet reached dawn.
	var seen: Dictionary = rec.get("seen", {})
	if not seen.has(guild):
		return -1.0
	return (float(seen[guild]) - float(rec["born"])) * 24.0


func _run_days(c: Carcasses, d: float) -> void:
	var bites := int(d * 4.0)
	for _i in bites:
		c.advance(6.0)


func _func_body(src: String, fname: String) -> String:
	## Deliberately tolerant of BOTH tab and space indentation. The Dev-Input
	## suite's own body reader walked only while lines began with a tab, so
	## it returned an empty body against a space-indented file and every
	## check built on it passed on a scan that had found nothing. A scan that
	## comes back empty agrees with everything, so this one is proved against
	## planted text before it is trusted on the truth.
	var lines := src.split("\n")
	var out: Array = []
	var inside := false
	for ln in lines:
		var s := String(ln)
		if not inside:
			if s.begins_with("static func %s(" % fname) or s.begins_with("func %s(" % fname):
				inside = true
			continue
		if s.strip_edges().is_empty():
			out.append(s)
			continue
		if s.begins_with("\t") or s.begins_with(" "):
			out.append(s)
			continue
		break
	return "\n".join(PackedStringArray(out))


func _src(path: String) -> String:
	var fa := FileAccess.open(path, FileAccess.READ)
	var s := fa.get_as_text() if fa != null else ""
	if fa != null:
		fa.close()
	return s


# --------------------------------------------------------------------- entry

func _initialize() -> void:
	print("\n=== CarcassTests ===")


func _process(_d: float) -> bool:
	_t_mass()
	_t_stages()
	_t_hours()
	_t_search()
	_t_arrival()
	_t_gale()
	_t_economy()
	_t_season()
	_t_eviction()
	_t_linger()
	_t_harvest()
	_t_ingest()
	_t_bodies()
	_t_body_skin()
	_t_pose()
	_t_determinism()
	_t_save()
	_t_chronicle()
	_t_feed()
	_t_purity()
	_t_no_bindings()
	_report()
	return true


func _report() -> void:
	for s in _claims:
		var want := int(_claims[s])
		var got := int(_counts.get(s, 0))
		if want != got:
			_fail += 1
			print("  FAIL  [claims] section '%s' claimed %d assertions, ran %d" % [s, want, got])
	print("\n--- %d passed, %d failed (floor %d) ---" % [_pass, _fail, MIN_ASSERTIONS])
	if _pass + _fail < MIN_ASSERTIONS:
		print("FAIL: only %d assertions ran" % (_pass + _fail))
		quit(1)
		return
	quit(1 if _fail > 0 else 0)


# ---------------------------------------------------------------------- mass

func _t_mass() -> void:
	claim("mass", 11)
	## The deposit. Every number downstream is in kilograms of this, so if
	## the size curve is wrong nothing else in the file means anything.
	var deer := Carcasses.mass_of("whitetail", DEER_LEN)
	var moose := Carcasses.mass_of("moose", MOOSE_LEN)
	var hare := Carcasses.mass_of("hare", HARE_LEN)
	near_f(deer, 49.13, 0.05, "a whitetail is a realistic 49 kg of workable animal")
	ok(moose > deer * 4.0, "and a moose is at least four deer (%.0f kg)" % moose)
	ok(hare < 1.0, "and a hare is under a kilogram (%.2f kg)" % hare)
	ok(Carcasses.mass_of("", 2.0) == 0.0, "nothing with no name has any mass")
	## Cube law, stated as a literal ratio rather than against the constant
	## that produces it -- MASS_K cancels out of any check written that way.
	near_f(Carcasses.mass_of("x", 2.0) / Carcasses.mass_of("x", 1.0), 8.0, 0.001,
			"twice as long is eight times the meat")
	ok(Carcasses.MIN_MASS < hare,
			"a hare is over the floor, so a hare leaves a carcass (%.2f > %.2f)"
			% [hare, Carcasses.MIN_MASS])
	ok(Carcasses.mass_of("red_squirrel", 0.20) < Carcasses.MIN_MASS,
			"a red squirrel is under it, so the ledger is not a list of squirrels")
	## The dex's own harvest ordinals must agree with the size curve, or the
	## two numbers the game has for "how big is this" disagree.
	var order_ok := true
	var prev := -1.0
	for k in ["hare", "whitetail", "moose"]:
		var p: Dictionary = CritterDex.get_profile(k)
		var m := Carcasses.mass_of(k, float(p.get("len", 1.0)))
		if m <= prev:
			order_ok = false
		prev = m
	ok(order_ok, "hare < whitetail < moose, by the dex's own lengths")
	ok(int((CritterDex.get_profile("moose").get("harv", {}) as Dictionary).get("meat", 0))
			> int((CritterDex.get_profile("whitetail").get("harv", {}) as Dictionary).get("meat", 0)),
			"and the dex's harv.meat ordinals put them in the same order")
	## The draw curve is bounded at both ends on purpose.
	near_f(Carcasses.draw_of(1e9), 2.1, 0.0001, "a whale does not summon the whole county")
	near_f(Carcasses.draw_of(0.0), 0.35, 0.0001, "and something tiny is still findable")


# -------------------------------------------------------------------- stages

func _t_stages() -> void:
	claim("stages", 15)
	## Stage is DERIVED from `left`, which is state. That is the correct half
	## of the split -- see `arrival` for the half that is not.
	var m := 100.0
	ok(Carcasses.stage_of({"mass": m, "left": 100.0}) == Carcasses.STAGE_WHOLE, "a fresh kill is whole")
	ok(Carcasses.stage_of({"mass": m, "left": 87.0}) == Carcasses.STAGE_WHOLE, "and still whole at 87 %")
	ok(Carcasses.stage_of({"mass": m, "left": 80.0}) == Carcasses.STAGE_OPENED, "opened at 80 %")
	ok(Carcasses.stage_of({"mass": m, "left": 56.0}) == Carcasses.STAGE_OPENED, "still opened at 56 %")
	ok(Carcasses.stage_of({"mass": m, "left": 40.0}) == Carcasses.STAGE_PICKED, "picked at 40 %")
	ok(Carcasses.stage_of({"mass": m, "left": 10.0}) == Carcasses.STAGE_BONES, "bones at 10 %")
	ok(Carcasses.stage_of({"mass": m, "left": 0.0}) == Carcasses.STAGE_GONE, "gone at nothing")
	ok(Carcasses.stage_of({"mass": 0.0, "left": 0.0}) == Carcasses.STAGE_GONE,
			"and a record with no mass cannot divide by it")
	## Monotone: eating can only ever move the stage forwards.
	var back := false
	var last := -1
	for i in 101:
		var st := Carcasses.stage_of({"mass": m, "left": m - float(i)})
		if st < last:
			back = true
		last = st
	ok(not back, "the stage never runs backwards as the meat goes")
	ok(last == Carcasses.STAGE_GONE, "and ends at gone")
	ok(Carcasses.stage_name(Carcasses.STAGE_WHOLE) == "whole", "whole has a name")
	ok(Carcasses.stage_name(Carcasses.STAGE_BONES) == "bones", "so does bones")
	ok(Carcasses.stage_name(99) == "gone", "and anything unrecognised reads as gone")
	## Legibility must never come back empty -- it is the line the feed says.
	var blank := false
	for st2 in 5:
		var rec := {"mass": m, "left": m * (1.0 - float(st2) * 0.245), "nm": "moose", "seen": {}}
		if Carcasses.legible(rec, 0.0).strip_edges().is_empty():
			blank = true
	ok(not blank, "a carcass always reads as something, at every stage")
	## And they must read DIFFERENTLY, or the stage is invisible to anyone
	## who only ever gets the sentence. The sweep named this: swapping the
	## whole-carcass line for the opened one changed nothing anybody asserted.
	var said := {}
	for st3 in 4:
		var frac: float = [1.0, 0.7, 0.4, 0.1][st3]
		said[Carcasses.legible({"mass": m, "left": m * frac, "nm": "moose", "seen": {}}, 0.0)] = true
	ok(said.size() == 4,
			"and the four unattended stages read as four different sentences (%d)" % said.size())


# --------------------------------------------------------------------- hours

func _t_hours() -> void:
	claim("hours", 16)
	## Who is awake, and when. Everything about arrival order comes out of
	## this table, so it is checked one guild at a time.
	ok(Carcasses.works_now(Carcasses.G_CORVID, 12.0, 0, 1), "crows work at noon in summer")
	ok(not Carcasses.works_now(Carcasses.G_CORVID, 2.0, 0, 1), "and not at two in the morning")
	ok(Carcasses.works_now(Carcasses.G_FOX, 2.0, 0, 1), "a fox does")
	ok(not Carcasses.works_now(Carcasses.G_FOX, 12.0, 0, 1), "and is not out at noon")
	ok(Carcasses.works_now(Carcasses.G_PACK, 23.0, 0, 1), "the pack works at eleven at night")
	ok(Carcasses.works_now(Carcasses.G_PACK, 2.0, 0, 1), "and at two, across midnight")
	ok(not Carcasses.works_now(Carcasses.G_PACK, 12.0, 0, 1), "and not at noon")
	ok(Carcasses.works_now(Carcasses.G_BEAR, 12.0, 0, 2), "a bear works at noon in autumn")
	ok(not Carcasses.works_now(Carcasses.G_BEAR, 12.0, 0, Carcasses.WINTER),
			"and is denned in winter, which is half of why a winter carcass keeps")
	## The gale. A cap of SKY_RAIN means the storm level and nothing below it.
	ok(Carcasses.works_now(Carcasses.G_CORVID, 12.0, Carcasses.SKY_RAIN, 1),
			"crows work in rain")
	ok(not Carcasses.works_now(Carcasses.G_CORVID, 12.0, Carcasses.SKY_STORM, 1),
			"and a gale grounds them outright")
	ok(Carcasses.works_now(Carcasses.G_PACK, 23.0, Carcasses.SKY_STORM, 1),
			"a gale does NOT ground the pack -- wind is the birds' problem")
	## Daylight is the real Crofts table, not a second copy of it.
	var summer := Carcasses.daylight(Carcasses.SUMMER)
	var winter := Carcasses.daylight(Carcasses.WINTER)
	ok(summer.y - summer.x > winter.y - winter.x + 3.0,
			"a summer day is at least three hours longer than a winter one (%.1f vs %.1f)"
			% [summer.y - summer.x, winter.y - winter.x])
	ok(summer == Crofts.daylight(Carcasses.SUMMER),
			"and it IS the Crofts table -- one definition of dawn in the project")
	## The crows' window follows it rather than a fixed pair of hours.
	ok(Carcasses.works_now(Carcasses.G_CORVID, 5.5, 0, Carcasses.SUMMER)
			and not Carcasses.works_now(Carcasses.G_CORVID, 5.5, 0, Carcasses.WINTER),
			"half past five is a working hour for a crow in June and not in January")
	ok(not Carcasses.works_now(-1, 12.0, 0, 0) and not Carcasses.works_now(99, 12.0, 0, 0),
			"and a guild that does not exist never works")


# -------------------------------------------------------------------- search

func _t_search() -> void:
	claim("search", 14)
	var deer := Carcasses.mass_of("whitetail", DEER_LEN)
	var moose := Carcasses.mass_of("moose", MOOSE_LEN)
	ok(Carcasses.find_gain(Carcasses.G_CORVID, deer, deer, 2.0, 0, 1) == 0.0,
			"nobody gets closer to finding anything while they are asleep")
	ok(Carcasses.find_gain(Carcasses.G_CORVID, deer, deer, 12.0, 0, 1) > 0.0,
			"and does while they are awake")
	## Scent. Stated as LITERAL margins, never against the tables that make
	## them -- `scent(summer) > scent(winter) * SEASON_SCENT_RATIO` agrees
	## with itself whatever the ratio becomes.
	ok(Carcasses.scent(0, Carcasses.SUMMER) > Carcasses.scent(0, Carcasses.WINTER) * 2.0,
			"a summer carcass smells at least twice as far as a frozen one (%.2f vs %.2f)"
			% [Carcasses.scent(0, Carcasses.SUMMER), Carcasses.scent(0, Carcasses.WINTER)])
	ok(Carcasses.scent(Carcasses.SKY_CLEAR, 0) > Carcasses.scent(Carcasses.SKY_STORM, 0) + 0.4,
			"and clear air carries it at least 0.4 further than a gale does")
	ok(Carcasses.scent(Carcasses.SKY_RAIN, 0) < Carcasses.scent(Carcasses.SKY_DRIZZLE, 0),
			"rain beats it down harder than drizzle")
	var falling := true
	var prev := 999.0
	for sk in 5:
		var v := Carcasses.scent(sk, 0)
		if v >= prev:
			falling = false
		prev = v
	ok(falling, "and the sky table falls all the way from clear to gale")
	ok(Carcasses.scent(0, 0) > 0.0 and is_finite(Carcasses.scent(4, 3)),
			"scent is finite and positive at both ends -- a threshold satisfied by zero is not a threshold")
	## Size. A moose is found sooner and the margin is stated flat.
	ok(Carcasses.find_gain(Carcasses.G_CORVID, moose, moose, 12.0, 0, 1)
			> Carcasses.find_gain(Carcasses.G_CORVID, deer, deer, 12.0, 0, 1) * 1.5,
			"a moose draws the crows at least half again as fast as a deer does")
	ok(Carcasses.draw_of(moose) <= 2.1 and Carcasses.draw_of(0.5) >= 0.35,
			"and the draw is clamped at both ends")
	## Rot. The season dial, in the same literal form.
	var m := 100.0
	ok(Carcasses.rot_per_step(m, Carcasses.SUMMER) > Carcasses.rot_per_step(m, Carcasses.WINTER) * 6.0,
			"August takes at least six times what February does (%.4f vs %.4f)"
			% [Carcasses.rot_per_step(m, Carcasses.SUMMER),
					Carcasses.rot_per_step(m, Carcasses.WINTER)])
	## And at least half again what a wet SPRING does. The mutation sweep
	## named this one: at a literal margin of four, August could be dialled
	## all the way back to the spring rate and every assertion in the file
	## still agreed, because February is a fifth of spring on its own.
	ok(Carcasses.rot_per_step(m, Carcasses.SUMMER) > Carcasses.rot_per_step(m, Carcasses.SPRING) * 1.5,
			"and at least half again what spring does (%.4f vs %.4f)"
			% [Carcasses.rot_per_step(m, Carcasses.SUMMER),
				Carcasses.rot_per_step(m, Carcasses.SPRING)])
	ok(Carcasses.rot_per_step(m, Carcasses.WINTER) > 0.0,
			"but February is not free -- the ground never stops entirely")
	near_f(Carcasses.rot_per_step(m, Carcasses.SPRING) * 48.0, m * Carcasses.ROT_PER_DAY, 1e-6,
			"and forty-eight steps is a day of it")
	ok(Carcasses.find_gain(Carcasses.G_BEAR, moose, moose, 12.0, 0, Carcasses.WINTER) == 0.0,
			"a denned bear makes no progress toward anything")


# ------------------------------------------------------------------- arrival

func _t_arrival() -> void:
	claim("arrival", 11)
	## THE HOUR OF THE KILL DECIDES WHO GETS THERE FIRST, and it is the most
	## visible thing this feature does. Two identical deer, twelve hours
	## apart, in the same weather and the same season.
	var noon := _bus(Carcasses.AUTUMN, Carcasses.SKY_CLEAR, 12.0)
	var rec_n := _deer(noon)
	_run_hours(noon, 72.0)
	var crow_n := _seen_h(rec_n, "corvid")
	var fox_n := _seen_h(rec_n, "fox")
	ok(crow_n >= 0.0 and crow_n <= 3.0,
			"a deer dropped at noon has crows on it inside three hours (%.1f h)" % crow_n)
	ok(fox_n < 0.0 or crow_n < fox_n,
			"and the crows beat the fox to it (crows %.1f h, fox %.1f h)" % [crow_n, fox_n])

	var midnight := _bus(Carcasses.AUTUMN, Carcasses.SKY_CLEAR, 0.0)
	var rec_m := _deer(midnight)
	_run_hours(midnight, 72.0)
	var fox_m := _seen_h(rec_m, "fox")
	var crow_m := _seen_h(rec_m, "corvid")
	ok(fox_m >= 0.0 and fox_m <= 8.0,
			"the same deer dropped at midnight has a fox on it inside eight hours (%.1f h)" % fox_m)
	ok(crow_m >= 0.0 and fox_m < crow_m,
			"and THE FOX BEATS THE CROWS, because the crows are asleep (fox %.1f h, crows %.1f h)"
			% [fox_m, crow_m])
	ok(crow_m > crow_n + 3.0,
			"the crows are at least three hours later on the midnight kill (%.1f vs %.1f)"
			% [crow_m, crow_n])
	## And the pack is a night animal, so it is never the first to arrive at
	## a daytime kill however big the carcass is.
	var big := _bus(Carcasses.AUTUMN, Carcasses.SKY_CLEAR, 12.0)
	var rec_b := _moose(big)
	_run_hours(big, 96.0)
	var pack_b := _seen_h(rec_b, "pack")
	var crow_b := _seen_h(rec_b, "corvid")
	ok(pack_b > 0.0, "a moose is found by the pack (%.1f h)" % pack_b)
	ok(crow_b >= 0.0 and crow_b < pack_b, "but not before the crows have had it")
	var pack_hour := fposmod(float(rec_b["born"]) * 24.0 + pack_b, 24.0)
	ok(Carcasses.works_now(Carcasses.G_PACK, pack_hour, 0, Carcasses.AUTUMN),
			"and the pack arrived during its own working hours (%.1f o'clock)" % pack_hour)
	## Arrival is a STATE. Once found, a change in the sky cannot un-find it.
	var sky := midnight.chron as FakeSky
	var was: Dictionary = (rec_m["seen"] as Dictionary).duplicate()
	sky.sky = Carcasses.SKY_STORM
	midnight.advance(12.0)
	var still := true
	for k in was:
		if not (rec_m["seen"] as Dictionary).has(k):
			still = false
	ok(still, "a gale does not un-find a carcass that has already been found")
	ok((rec_m["seen"] as Dictionary).size() >= was.size(),
			"and the arrival list only ever grows")
	ok(Carcasses.attendance({"seen": {}, "mass": 10.0, "left": 10.0}, 0.0).is_empty(),
			"nothing is at a carcass nobody has found")
	noon.free()
	midnight.free()
	big.free()


# ---------------------------------------------------------------------- gale

func _t_gale() -> void:
	claim("gale", 7)
	## The negative case AND its positive twin, in one section on purpose.
	## "The crows never came" is worth nothing on its own: a search loop that
	## silently does nothing would pass it, and so would a guild table with
	## no crows in it. The identical fixture in clear air is the other door.
	var stormy := _bus(Carcasses.AUTUMN, Carcasses.SKY_STORM, 12.0)
	var rec_s := _deer(stormy)
	_run_days(stormy, 3.0)
	ok(not (rec_s["seen"] as Dictionary).has("corvid"),
			"three days of gale and the crows have never come")
	ok(float((rec_s["prog"] as Dictionary).get("corvid", 0.0)) == 0.0,
			"and they made no progress at all toward coming")

	var calm := _bus(Carcasses.AUTUMN, Carcasses.SKY_CLEAR, 12.0)
	var rec_c := _deer(calm)
	_run_days(calm, 3.0)
	ok((rec_c["seen"] as Dictionary).has("corvid"),
			"THE SAME THREE DAYS IN CLEAR AIR AND THEY DID -- which is what makes the line above an assertion")
	ok(float((rec_c["took"] as Dictionary).get("corvid", 0.0)) > 1.0,
			"and they took more than a kilogram off it (%.1f kg)"
			% float((rec_c["took"] as Dictionary).get("corvid", 0.0)))
	## The gale is the birds' problem and nobody else's.
	ok((rec_s["seen"] as Dictionary).has("fox"),
			"a fox works right through the same gale")
	ok(float((rec_s["prog"] as Dictionary).get("fox", 0.0)) > 0.0,
			"and got there by searching, not by being handed it")
	## But rain slows the fox down, because the search reads the scent table.
	var wet := _bus(Carcasses.AUTUMN, Carcasses.SKY_STORM, 0.0)
	var dry := _bus(Carcasses.AUTUMN, Carcasses.SKY_CLEAR, 0.0)
	var rw := _deer(wet)
	var rd := _deer(dry)
	_run_hours(wet, 96.0)
	var fw := _seen_h(rw, "fox")
	_run_hours(dry, 96.0)
	var fd := _seen_h(rd, "fox")
	ok(fw > fd + 4.0,
			"and takes at least four hours longer to find one in a gale (%.1f vs %.1f)" % [fw, fd])
	stormy.free()
	calm.free()
	wet.free()
	dry.free()


# ------------------------------------------------------------------- economy

func _t_economy() -> void:
	claim("economy", 16)
	## THE FLOORS ARE THE TEETH: butcher it, or fund the predators. Every
	## margin below is a LITERAL share, never the constant it guards.
	var mass := Carcasses.mass_of("moose", MOOSE_LEN)
	ok(mass > 200.0, "a moose is over two hundred kilograms (%.0f)" % mass)

	var whole := _bus(Carcasses.AUTUMN, Carcasses.SKY_CLEAR, 6.0)
	var rw := _moose(whole)
	_run_days(whole, 4.0)
	ok((rw["seen"] as Dictionary).has("pack"), "left where it fell, the pack comes")
	ok((rw["seen"] as Dictionary).has("bear"), "and so does a bear")

	var butchered := _bus(Carcasses.AUTUMN, Carcasses.SKY_CLEAR, 6.0)
	var rb := _moose(butchered)
	var took := butchered.harvest_at(Vector3.ZERO, 5.0, mass * 0.85)
	near_f(took, mass * 0.85, 0.01, "the butcher takes 85 % of it off the ledger")
	_run_days(butchered, 4.0)
	ok(not (rb["seen"] as Dictionary).has("pack"),
			"AND THE PACK NEVER COMES -- the same moose, the same night, the same weather")
	ok(not (rb["seen"] as Dictionary).has("bear"), "nor the bear")
	ok((rb["seen"] as Dictionary).has("corvid"),
			"the crows still do, because crows are not proud")

	## And the boundary is where the table says it is, not somewhere near it.
	##
	## 2026-09-12: the two assertions that stood here were passing for the
	## WRONG REASON, and `Butchery`'s round is what exposed them. They said
	## "half a moose is not worth a bear's walk" -- but the bear's floor is
	## 30 %, so a bear wants half a moose very much indeed. What was actually
	## keeping him away was that his thirty-four-hour search did not finish
	## inside an arbitrary four-day window. `Carcasses.OPEN_SCENT` shortened
	## that search by a measured 1.6 and the pair went red at once, which is an
	## assertion finally telling the truth about itself. Both are restated as
	## what they MEANT: the floor, said directly through `wants_it`, and
	## BEAR_EVICTS, which is what a bear arriving on half a moose actually does
	## to a coyote pack.
	var half := _bus(Carcasses.AUTUMN, Carcasses.SKY_CLEAR, 6.0)
	var rh := _moose(half)
	half.harvest_at(Vector3.ZERO, 5.0, mass * 0.5)
	ok(Carcasses.wants_it(Carcasses.G_PACK, rh), "half a moose is worth a pack's walk")
	ok(Carcasses.wants_it(Carcasses.G_BEAR, rh),
			"and a bear's too -- fifty per cent clears his thirty-per-cent floor")
	_run_days(half, 4.0)
	ok((rh["seen"] as Dictionary).has("bear"),
			"and once it is OPEN he finds it inside four clear autumn days")
	ok(not (rh["seen"] as Dictionary).has("pack"),
			"AND THE PACK NEVER GETS A LOOK IN -- BEAR_EVICTS, and the bear got there first")
	var lean := _bus(Carcasses.AUTUMN, Carcasses.SKY_CLEAR, 6.0)
	var rl := _moose(lean)
	lean.harvest_at(Vector3.ZERO, 5.0, mass * 0.78)
	ok(Carcasses.wants_it(Carcasses.G_PACK, rl), "at twenty-two per cent left a pack still comes")
	ok(not Carcasses.wants_it(Carcasses.G_BEAR, rl),
			"and a bear does NOT -- THAT is where the two floors part company")
	lean.free()
	ok(float((GUILDS_ROW(Carcasses.G_BEAR))["floor"]) > float((GUILDS_ROW(Carcasses.G_PACK))["floor"]),
			"which is the table saying so")
	## `wants_it` is the one function all of that rests on.
	ok(Carcasses.wants_it(Carcasses.G_PACK, {"mass": 100.0, "left": 30.0}),
			"a pack wants 30 % of a carcass")
	ok(not Carcasses.wants_it(Carcasses.G_PACK, {"mass": 100.0, "left": 10.0}),
			"and not 10 %")
	whole.free()
	butchered.free()
	half.free()


func GUILDS_ROW(i: int) -> Dictionary:
	return Carcasses.GUILDS[i]


# -------------------------------------------------------------------- season

func _t_season() -> void:
	claim("season", 9)
	## THE SEASON IS THE OTHER DIAL, and the way it is actually experienced
	## is the number of DAYS a carcass is still a carcass. Two identical
	## deer, dropped at noon, on the same hour of the same clock.
	var summer := _bus(Carcasses.SUMMER, Carcasses.SKY_CLEAR, 12.0)
	var winter := _bus(Carcasses.WINTER, Carcasses.SKY_CLEAR, 12.0)
	var rs := _deer(summer)
	var rwn := _deer(winter)
	var s_bones := -1.0
	var s_at3 := -1.0
	var w_at3 := -1.0
	var w_bones := -1.0
	for i in 80:
		summer.advance(6.0)
		winter.advance(6.0)
		if s_at3 < 0.0 and summer.days - float(rs["born"]) >= 3.0:
			s_at3 = float(rs["left"])
			w_at3 = float(rwn["left"])
		if s_bones < 0.0 and Carcasses.stage_of(rs) >= Carcasses.STAGE_BONES:
			s_bones = summer.days - float(rs["born"])
		if w_bones < 0.0 and Carcasses.stage_of(rwn) >= Carcasses.STAGE_BONES:
			w_bones = winter.days - float(rwn["born"])
	ok(s_bones > 0.0, "a summer deer is bones (day %.2f)" % s_bones)
	ok(s_bones < 3.0, "and is bones inside three days, which is the whole claim")
	ok(w_bones > 0.0, "a winter deer gets there too, eventually (day %.2f)" % w_bones)
	ok(w_bones > s_bones + 4.0,
			"BUT AT LEAST FOUR DAYS LATER (%.2f vs %.2f)" % [w_bones, s_bones])
	## And the reason is in two places at once, both of which must hold.
	ok(Carcasses.rot_per_step(100.0, Carcasses.SUMMER)
			> Carcasses.rot_per_step(100.0, Carcasses.WINTER) * 6.0,
			"the ground is at least six times as hungry in August")
	ok(Carcasses.scent(0, Carcasses.SUMMER) > Carcasses.scent(0, Carcasses.WINTER) * 2.0,
			"and the air carries it at least twice as far")
	ok(not (rwn["seen"] as Dictionary).has("bear"),
			"and no bear came to the winter one, because a bear is asleep")
	ok(w_at3 > s_at3 + 8.0,
			"and three days in, the winter one still has at least eight kilos more on it (%.1f vs %.1f)"
			% [w_at3, s_at3])
	## A carcass in autumn sits between the two, so the table is a curve and
	## not a switch with a summer flag on it.
	var autumn := _bus(Carcasses.AUTUMN, Carcasses.SKY_CLEAR, 12.0)
	var ra := _deer(autumn)
	var a_bones := -1.0
	for i in 80:
		autumn.advance(6.0)
		if a_bones < 0.0 and Carcasses.stage_of(ra) >= Carcasses.STAGE_BONES:
			a_bones = autumn.days - float(ra["born"])
	ok(a_bones > s_bones and a_bones < w_bones,
			"and autumn lands between the two (%.2f, between %.2f and %.2f)"
			% [a_bones, s_bones, w_bones])
	summer.free()
	winter.free()
	autumn.free()


# ------------------------------------------------------------------ eviction

func _t_eviction() -> void:
	claim("eviction", 8)
	## The one interaction between two guilds, and the reason `seen` is
	## written down rather than asked for: a bear arrives and the table
	## clears. Both doors are closed here -- WITHOUT the bear, at the very
	## same instant, the pack is still there, so the assertion below cannot
	## be passing because the pack had simply gone home.
	var base := {"mass": 200.0, "left": 180.0, "seen": {"pack": 10.0}}
	ok(Carcasses.present(base, Carcasses.G_PACK, 10.2), "the pack is at a fresh carcass")
	var evicted := {"mass": 200.0, "left": 180.0, "seen": {"pack": 10.0, "bear": 10.1}}
	ok(not Carcasses.present(evicted, Carcasses.G_PACK, 10.2),
			"AND IS GONE THE MOMENT A BEAR ARRIVES -- same t, same carcass, one extra row")
	ok(Carcasses.present(evicted, Carcasses.G_BEAR, 10.2), "and the bear is there instead")
	## The bear evicts from its arrival, not from the beginning of time.
	ok(Carcasses.present(evicted, Carcasses.G_PACK, 10.05),
			"the pack was still there in the hour before the bear turned up")
	## Stay windows.
	ok(not Carcasses.present(base, Carcasses.G_PACK, 9.9),
			"nobody is at a carcass before they found it")
	ok(not Carcasses.present(base, Carcasses.G_PACK, 12.0),
			"and a pack does not sit on one for two days")
	## And the floor holds inside `present` too, so a guild that is standing
	## there when the last of it goes leaves rather than eating nothing.
	ok(not Carcasses.present({"mass": 200.0, "left": 4.0, "seen": {"pack": 10.0}},
			Carcasses.G_PACK, 10.2),
			"a pack that arrives at a stripped carcass does not stay at it")
	ok(Carcasses.attendance(evicted, 10.2) == ["bear"],
			"so the attendance at that moment is the bear and nobody else")


# -------------------------------------------------------------------- linger

func _t_linger() -> void:
	claim("linger", 8)
	## AGEING ANYTHING ON A GAME CLOCK: NAME WHICH CLOCK. Bones are worth
	## walking up to for BONE_DAYS after the meat ran out, never after the
	## kill -- measured from the kill, a carcass the pack stripped in six
	## hours and one the winter kept for a fortnight would both vanish on the
	## same afternoon and nobody would ever see the second one's ribs.
	var fast := _bus(Carcasses.SUMMER, Carcasses.SKY_CLEAR, 12.0)
	var slow := _bus(Carcasses.WINTER, Carcasses.SKY_CLEAR, 12.0)
	var rf := _deer(fast)
	var rl := _deer(slow)
	var f_strip := -1.0
	var l_strip := -1.0
	var f_gone := -1.0
	var l_gone := -1.0
	for i in 160:
		fast.advance(6.0)
		slow.advance(6.0)
		if f_strip < 0.0 and float(rf.get("stripped", -1.0)) >= 0.0:
			f_strip = float(rf["stripped"])
		if l_strip < 0.0 and float(rl.get("stripped", -1.0)) >= 0.0:
			l_strip = float(rl["stripped"])
		if f_gone < 0.0 and fast.record_by_id(int(rf["id"])).is_empty():
			f_gone = fast.days
		if l_gone < 0.0 and slow.record_by_id(int(rl["id"])).is_empty():
			l_gone = slow.days
	ok(f_strip > 0.0 and l_strip > 0.0, "both deer were stripped in the end")
	ok(l_strip > f_strip + 3.0,
			"the winter one at least three days after the summer one (%.2f vs %.2f)"
			% [l_strip, f_strip])
	ok(f_gone > 0.0 and l_gone > 0.0, "and both records were eventually forgotten")
	near_f(f_gone - f_strip, Carcasses.BONE_DAYS, 0.5,
			"the summer bones lasted BONE_DAYS from their own ending")
	## ...and said as a LITERAL too. Stated only against the constant, the
	## sweep's "bones do not linger" (BONE_DAYS 5.0 -> 0.5) survived at HEAD
	## on 2026-09-14: a margin stated against the constant it guards agrees
	## with itself whatever that constant becomes.
	ok(f_gone - f_strip >= 3.0,
			"and bones are worth walking up to for at least three days (%.2f)" % (f_gone - f_strip))
	near_f(l_gone - l_strip, Carcasses.BONE_DAYS, 0.5,
			"and so did the winter ones, from theirs")
	ok(l_gone > f_gone + 3.0,
			"SO THE TWO ARE FORGOTTEN AS FAR APART AS THEY WERE STRIPPED (%.2f vs %.2f)"
			% [l_gone, f_gone])
	ok(absf((l_gone - float(rl["born"])) - (f_gone - float(rf["born"]))) > 3.0,
			"which is a different answer from dating the linger off the kill")
	fast.free()
	slow.free()


# ------------------------------------------------------------------- harvest

func _t_harvest() -> void:
	claim("harvest", 10)
	var c := _bus(Carcasses.AUTUMN, Carcasses.SKY_CLEAR, 12.0)
	var rec := _deer(c)
	var mass := float(rec["mass"])
	ok(c.harvest_at(Vector3(1000.0, 0.0, 0.0), 5.0, 10.0) == 0.0,
			"there is nothing to butcher a kilometre away")
	near_f(c.harvest_at(Vector3.ZERO, 5.0, 10.0), 10.0, 1e-6, "ten kilos comes off")
	near_f(float(rec["left"]), mass - 10.0, 1e-6, "and the ledger is ten lighter")
	near_f(float((rec["took"] as Dictionary)["player"]), 10.0, 1e-6,
			"and the player is on the list of claimants")
	var rest := c.harvest_at(Vector3.ZERO, 5.0, 1e6)
	near_f(rest, mass - 10.0, 1e-6, "you cannot take more off it than is on it")
	near_f(float(rec["left"]), 0.0, 1e-6, "and what is left is nothing")
	ok(c.harvest_at(Vector3.ZERO, 5.0, 10.0) == 0.0, "and nothing more comes off an empty one")
	ok(c.harvest_at(Vector3.ZERO, 5.0, -50.0) == 0.0, "a negative cut takes nothing")
	## Nearest wins, and it is the nearest rather than the first.
	var c2 := _bus(Carcasses.AUTUMN, Carcasses.SKY_CLEAR, 12.0)
	var far := c2.add("moose", "moose", Vector3(40.0, 0.0, 0.0), 200.0)
	var close := c2.add("whitetail", "deer", Vector3(2.0, 0.0, 0.0), 49.0)
	c2.harvest_at(Vector3.ZERO, 50.0, 5.0)
	near_f(float(close["left"]), 44.0, 1e-6, "the nearer carcass is the one you butcher")
	near_f(float(far["left"]), 200.0, 1e-6, "and the far one is untouched")
	c.free()
	c2.free()


# -------------------------------------------------------------------- ingest

func _t_ingest() -> void:
	claim("ingest", 12)
	## The only way a carcass is ever made in the game. A sweep of the
	## `enemies` group for `dying`, which every death in the project goes
	## through -- and which patches nobody else's file to do it.
	var c := Carcasses.new()
	var sky := FakeSky.new()
	sky.season = Carcasses.AUTUMN
	c.chron = sky
	root.add_child(c)
	c.advance(START_DAY * 24.0 + 12.0)
	ok(c.harvest() == 0, "an empty wood makes no carcasses")

	var alive := FakeDead.new()
	alive.species = "whitetail"
	alive.add_to_group("enemies")
	root.add_child(alive)
	ok(c.harvest() == 0, "and neither does a LIVE deer")

	var dead := FakeDead.new()
	dead.species = "whitetail"
	dead.dying = true
	dead.add_to_group("enemies")
	root.add_child(dead)
	dead.global_position = Vector3(5.0, 0.0, 5.0)
	ok(c.harvest() == 1, "a dying one makes exactly one")
	ok(c.harvest() == 0, "and the same body does not make a second on the next sweep")
	ok(c.records.size() == 1, "so the ledger has one row")
	var rec := c.records[0] as Dictionary
	ok(String(rec["species"]) == "whitetail", "which knows what it was")
	near_f(float(rec["mass"]), 49.13, 0.05, "and how much of it there is")
	near_f((rec["at"] as Vector3).distance_to(Vector3(5.0, 0.0, 5.0)), 0.0, 1e-4,
			"and where it fell")
	near_f(float(rec["born"]), c.days, 1e-6, "and when")

	var nameless := FakeDead.new()
	nameless.dying = true
	nameless.add_to_group("enemies")
	root.add_child(nameless)
	ok(c.harvest() == 0,
			"a dead goblin has no species and gets no record -- this is the WILDLIFE economy")

	var tiny := FakeDead.new()
	tiny.species = "red_squirrel"
	tiny.dying = true
	tiny.add_to_group("enemies")
	root.add_child(tiny)
	ok(c.harvest() == 0, "and a squirrel is under the floor")

	## The public door has its own floor, and it is a DIFFERENT door: the
	## sweep took the one out of `add` and nothing moved, because
	## `_make_from` refuses a squirrel before `add` ever sees it.
	ok(c.add("red_squirrel", "red squirrel", Vector3.ZERO, 0.1).is_empty(),
			"and `add` refuses one on its own account too")

	alive.free()
	dead.free()
	nameless.free()
	tiny.free()
	sky.free()
	c.free()


# -------------------------------------------------------------------- bodies

func _t_bodies() -> void:
	claim("bodies", 13)
	## Nothing is a scene node until you are close, and the body is a picture
	## of the record rather than a second copy of it.
	var c := _bus(Carcasses.AUTUMN, Carcasses.SKY_CLEAR, 12.0)
	var rec := _moose(c)
	ok(c.staged_ids().is_empty(), "nothing is staged with no player and no tree")
	c._restage()
	ok(c.staged_ids().is_empty(), "and a restage outside the tree is a silent no-op")
	c._mow(Vector3.ZERO, 3.0)
	c._mow(Vector3.ZERO, 3.0)
	ok(c._mown.size() == 1,
			"mowing with no grass bound is a no-op, and mowing the same spot twice is one cut")
	## AND THE CIRCLE IS THE ANIMAL'S, NOT A CONSTANT. The first live look at
	## this feature stood four metres from a whole moose in a hayfield and
	## could not see it: at a flat 2.6 m the mown circle was smaller than the
	## body inside it, and the tufts in front hid it at eye height. Nothing
	## in a pure function could have caught that.
	near_f(Carcasses.mow_radius(MOOSE_LEN), 6.96, 0.01,
			"a moose flattens seven metres of meadow")
	ok(Carcasses.mow_radius(HARE_LEN) < Carcasses.mow_radius(MOOSE_LEN) - 4.0,
			"and a hare at least four metres less than that (%.2f vs %.2f)"
			% [Carcasses.mow_radius(HARE_LEN), Carcasses.mow_radius(MOOSE_LEN)])

	root.add_child(c)
	var pl := FakePlayer.new()
	root.add_child(pl)
	c.player = pl
	pl.global_position = Vector3(1e5, 0.0, 1e5)
	c._restage()
	ok(c.staged_ids().is_empty(), "a carcass a hundred kilometres away is a dictionary")
	pl.global_position = Vector3(12.0, 0.0, 0.0)
	c._restage()
	ok(c.staged_ids().size() == 1, "walk up to within twelve metres and it is a body")
	c._restage()
	ok(c.staged_ids().size() == 1, "and staying there does not build a second one")
	## Counted on the SCENE, not on the dictionary. The sweep named this:
	## with the guard removed a second body was built every scan and the
	## staged dictionary still had exactly one key, because the new node
	## simply overwrote the old one under the same id. Two children here:
	## the FakeSky the fixture parented to the bus, and the one body.
	ok(c.get_child_count() == 2,
			"and there is ONE body node under the bus, not two (%d children)" % c.get_child_count())
	pl.global_position = Vector3(1e5, 0.0, 1e5)
	c._restage()
	ok(c.staged_ids().is_empty(), "walk away and it is a dictionary again")
	## THE LEDGER KEPT BILLING WHILE IT WAS NOT A NODE. That is the whole
	## reason this is a bus.
	var before := float(rec["left"])
	_run_days(c, 2.0)
	ok(float(rec["left"]) < before - 20.0,
			"twenty kilos went off it while nobody was there to watch (%.0f -> %.0f)"
			% [before, float(rec["left"])])
	pl.global_position = Vector3(12.0, 0.0, 0.0)
	c._restage()
	ok(c.staged_ids().size() == 1, "and it is still there when you come back")
	## The director is ASKED, never assumed.
	var wild := FakeWild.new()
	wild.refuse = true
	root.add_child(wild)
	c.wild = wild
	c._ask_for_bodies(rec)
	var claims: Dictionary = c.report()["claims"]
	var total := 0
	for k in claims:
		total += int(claims[k])
	ok(total > 0 and c.report()["records"] == 1,
			"a director that refuses every spawn changes nothing on the ledger")
	pl.free()
	wild.free()
	c.free()


# ----------------------------------------------------------------- body skin

func _t_body_skin() -> void:
	claim("body_skin", 31)
	## THE PICTURE IS THE ANIMAL'S OWN SKIN. Until 2026-09-14 a staged body
	## was four flat boxes and some spars -- "some cube that's stuck", when
	## Lemon found the butchery loop. It is the species' rig baked through
	## CreatureSkin now, lying on its side, and at the bones stage what is
	## left of it is loot. CarcassBody is reached by duck typing on purpose:
	## this file must parse on a machine whose class cache has not met it.
	var c := _bus(Carcasses.AUTUMN, Carcasses.SKY_CLEAR, 12.0)
	c.world_seed = 777
	root.add_child(c)
	var pl := FakePlayer.new()
	root.add_child(pl)
	c.player = pl
	pl.global_position = Vector3(12.0, 0.0, 0.0)
	var mass := Carcasses.mass_of("black_bear", 1.7)
	var rec := c.add("black_bear", "black bear", Vector3(3.0, 0.0, -2.0), mass)
	c._restage()
	ok(c.staged_ids().size() == 1, "a bear is a body at twelve metres")
	var body: Node3D = c._staged[int(rec["id"])]
	ok(body.is_in_group("carcass_bodies"), "in the carcass_bodies group")
	ok(body.has_method("dress") and body.has_method("sweep_taken"), "and it is a CarcassBody")
	var skin: CreatureSkin = body.get("skin")
	ok(skin != null and skin.bone_count() > 8,
			"wearing a real skeleton (%d bones)" % (skin.bone_count() if skin != null else 0))
	ok(skin != null and skin.segment_count() > 20,
			"and a real rounded skin, not four boxes (%d segments)"
			% (skin.segment_count() if skin != null else 0))
	ok(skin != null and skin.frozen and not skin.ragdoll, "held still: frozen, never simulating")
	ok(not bool(body.get("pose_from_death")), "a record with no ragdoll pose gets the fallback")
	ok(body.rotation == Vector3.ZERO, "the root never rotates -- the yaw lives in the pose")
	near_f(body.position.x, 3.0, 1e-6, "and it sits where the record says")
	## The fallback is ON ITS SIDE: the pelvis' up axis is nowhere near up...
	var pel: Transform3D = skin.bone_pose(1)
	ok(absf(pel.basis.y.y) < 0.6, "on its side (pelvis up.y = %.2f)" % pel.basis.y.y)
	## ...and on the ground: the lowest point of the skin rests on the terrain.
	var low := INF
	for bid in range(1, skin.bone_count()):
		var box: AABB = skin.bone_aabb(bid)
		var t: Transform3D = skin.bone_pose(bid)
		for k in 8:
			var corner := box.position + Vector3(
					box.size.x if (k & 1) != 0 else 0.0,
					box.size.y if (k & 2) != 0 else 0.0,
					box.size.z if (k & 4) != 0 else 0.0)
			low = minf(low, (t * corner).y)
	near_f(low, 0.01, 0.02, "the lowest point of it rests on the ground")
	ok((body.get("bones") as Dictionary).is_empty(), "no bones to pick up on a whole animal")
	ok(body.get_node_or_null("Slab") != null, "and the stained ground is under it")
	## THE STAGES ARE THE SKIN'S OWN MIRROR: colour and `visible` on the
	## proxies, which is what `_sync_segments` has always read.
	var trunk: MeshInstance3D = body.get("_trunk")
	var live_col: Color = (trunk.material_override as StandardMaterial3D).albedo_color
	rec["left"] = mass * 0.70    ## opened
	c._drive_bodies()
	ok(int(body.get_meta("stage")) == Carcasses.STAGE_OPENED, "the body follows the ledger to OPENED")
	var opened_col: Color = (trunk.material_override as StandardMaterial3D).albedo_color
	ok(opened_col != live_col and opened_col.r > live_col.r,
			"an opened trunk is bloodied (%s -> %s)" % [live_col, opened_col])
	ok(trunk.visible and skin.visible, "and still all there")
	rec["left"] = mass * 0.40    ## picked
	c._drive_bodies()
	ok(int(body.get_meta("stage")) == Carcasses.STAGE_PICKED, "then PICKED")
	ok(not trunk.visible, "the trunk is gone")
	var core: MeshInstance3D = body.get("_core")
	ok(core != null and core.visible, "a dark core shows in its place")
	var ribs: Array = body.get("_ribs")
	ok(ribs.size() >= 3 and (ribs[0] as MeshInstance3D).visible,
			"with %d rib plates over it" % ribs.size())
	ok((body.get("bones") as Dictionary).is_empty(), "and still nothing to pick up")
	## BONES ARE LOOT.
	rec["left"] = mass * 0.10    ## bones
	c._drive_bodies()
	ok(int(body.get_meta("stage")) == Carcasses.STAGE_BONES, "then BONES")
	ok(not skin.visible, "the skin is gone")
	var bones: Dictionary = body.get("bones")
	ok(bones.size() == 10, "a bear leaves ten bones: skull, ribs, two a leg (%d)" % bones.size())
	var names := {}
	var all_items := true
	for k in bones:
		var di := bones[k] as DroppedItem
		if di == null or not di.is_in_group("dropped_items") or not di.has_meta("carcass_bone"):
			all_items = false
			continue
		names[String(di.item.get("name", ""))] = true
	ok(all_items, "every one a DroppedItem in the loot group, marked as the carcass's")
	ok(names.has("Bear Skull") and names.has("Bear Ribs") and names.has("Bear Bone"),
			"named off the animal: %s" % [names.keys()])
	ok(bool((bones["skull"] as DroppedItem).item.get("keep", false)), "and a bone never expires")
	## TAKING ONE IS WRITTEN ON THE RECORD -- the picture's one word back to
	## the ledger. The player frees the node; nothing else ever does.
	(bones["skull"] as DroppedItem).free()
	c._drive_bodies()
	ok((rec.get("bones", {}) as Dictionary).has("skull"), "pick up the skull and the record knows")
	ok(not (rec.get("bones", {}) as Dictionary).has("ribs"), "and only the skull")
	pl.global_position = Vector3(1e5, 0.0, 1e5)
	c._restage()
	pl.global_position = Vector3(12.0, 0.0, 0.0)
	c._restage()
	var body2: Node3D = c._staged[int(rec["id"])]
	var n2 := (body2.get("bones") as Dictionary).size()
	ok(body2 != body and n2 == 9, "walk away and back and the skull is still gone (%d bones)" % n2)
	## and a save carries it
	var c2 := _bus(Carcasses.AUTUMN, Carcasses.SKY_CLEAR, 12.0)
	c2.from_dict(c.to_dict())
	ok(((c2.records[0] as Dictionary).get("bones", {}) as Dictionary).has("skull"),
			"the taken skull survives a save")
	c2.free()
	pl.free()
	c.free()


# ---------------------------------------------------------------------- pose

func _t_pose() -> void:
	claim("pose", 15)
	## THE POSE IS THE DEATH'S. A real kill hands its body to the ragdoll,
	## which settles and freezes; the bus reads the skeleton once, writes it
	## on the record, and the body it stages wears the same pose -- the
	## corpse is hidden in the same sweep, so nothing on screen changes.
	var c := _bus(Carcasses.AUTUMN, Carcasses.SKY_CLEAR, 12.0)
	root.add_child(c)
	var pl := FakePlayer.new()
	root.add_child(pl)
	c.player = pl
	pl.global_position = Vector3.ZERO
	## a dead bear: the fixture the harvest reads, wearing a real skin
	var dead := FakeDead.new()
	dead.species = "black_bear"
	dead.dying = true
	dead.add_to_group("enemies")
	root.add_child(dead)
	dead.global_position = Vector3(4.0, 0.0, 4.0)
	CritterRig.build(dead, "black_bear")
	var dskin := CreatureSkin.bake(dead, {"tile": "fur_long", "mass": 49.0})
	ok(dskin.bone_count() > 8, "the fixture wears a skeleton (%d bones)" % dskin.bone_count())
	ok(c.harvest() == 1, "it dies and is harvested")
	var rec := c.records[0] as Dictionary
	ok(c._pending.size() == 1, "and watched for its pose")
	ok(not rec.has("pose") or (rec["pose"] as PackedFloat32Array).is_empty(),
			"which is not written yet")
	c._restage()
	ok(c.staged_ids().is_empty(), "nothing is staged over a corpse that is still settling")
	## It settles: put it in a pose and freeze it, the way the ragdoll clock
	## does at the end of CORPSE_SETTLE.
	var tilt := Basis(Vector3.BACK, 1.2)
	var globals: Array = []
	for i in dskin.bone_count():
		var rest: Transform3D = dskin.rest_global(i)
		globals.append(Transform3D(tilt * rest.basis, tilt * rest.origin + Vector3(0.0, 0.3, 0.0)))
	dskin.pose_apply(globals)
	ok(dskin.frozen and not dskin.ragdoll, "the fixture is frozen")
	var before := dskin.pelvis_global().origin
	ok(before.distance_to(Vector3(4.0, 0.0, 4.0)) > 0.2, "with its pelvis off the spawn point (%.2f m)"
			% before.distance_to(Vector3(4.0, 0.0, 4.0)))
	c.harvest()    ## the next sweep reads it
	ok(c._pending.is_empty(), "the settled corpse is read and released")
	var pose: PackedFloat32Array = rec.get("pose", PackedFloat32Array())
	ok(pose.size() == dskin.bone_count() * 12, "twelve floats a bone on the record (%d)" % pose.size())
	near_f((rec["at"] as Vector3).x, before.x, 1e-4, "the record moved to where the pelvis lies")
	ok(c.staged_ids().size() == 1, "and the body is staged in the same sweep")
	ok(not dskin.visible, "the corpse is hidden the moment the body exists")
	var body: Node3D = c._staged[int(rec["id"])]
	ok(bool(body.get("pose_from_death")), "and the body wears the death's pose")
	var bskin: CreatureSkin = body.get("skin")
	var after: Vector3 = body.position + bskin.bone_pose(1).origin
	near_f(after.distance_to(before), 0.0, 1e-3, "pelvis for pelvis, where the corpse's was")
	## the same pose after a save
	var c2 := _bus(Carcasses.AUTUMN, Carcasses.SKY_CLEAR, 12.0)
	c2.from_dict(c.to_dict())
	ok(((c2.records[0] as Dictionary)["pose"] as PackedFloat32Array) == pose, "and it survives a save")
	dead.free()
	pl.free()
	c2.free()
	c.free()


# --------------------------------------------------------------- determinism

func _t_determinism() -> void:
	claim("determinism", 6)
	## Two buses with the same seed that lived the same life must produce
	## identical digests, or a save cannot reproduce the world it saved.
	var a := _bus(Carcasses.AUTUMN, Carcasses.SKY_CLEAR, 7.5)
	var b := _bus(Carcasses.AUTUMN, Carcasses.SKY_CLEAR, 7.5)
	a.world_seed = 4242
	b.world_seed = 4242
	var ra := _moose(a)
	var rb := _moose(b)
	_run_days(a, 6.0)
	_run_days(b, 6.0)
	ok(str(a.report()) == str(b.report()), "the same life gives the same report")
	ok(str(a.to_dict()) == str(b.to_dict()), "and the same save")
	near_f(float(ra["left"]), float(rb["left"]), 1e-9, "down to the last gram")
	## Running it in different sized bites must not change the answer either,
	## because the step is the unit and the bite is not.
	var cc := _bus(Carcasses.AUTUMN, Carcasses.SKY_CLEAR, 7.5)
	cc.world_seed = 4242
	var rc := _moose(cc)
	for _i in 12:
		cc.advance(12.0)
	near_f(float(rc["left"]), float(ra["left"]), 1e-6,
			"twelve twelve-hour bites is the same six days as twenty-four six-hour ones")
	## And no roll anywhere.
	var src := _src("res://scripts/Carcasses.gd")
	ok(src.length() > 20000, "the source scanned back %d characters" % src.length())
	ok(not src.contains("rand" + "f(") and not src.contains("Random" + "NumberGenerator" + ".new(")
			and not src.contains("rand" + "i("),
			"and there is no roll of any kind in it")
	a.free()
	b.free()
	cc.free()


# ---------------------------------------------------------------------- save

func _t_save() -> void:
	claim("save", 12)
	var a := _bus(Carcasses.AUTUMN, Carcasses.SKY_CLEAR, 9.0)
	var rec := _moose(a)
	_run_days(a, 2.5)
	var d := a.to_dict()
	ok(int(d["v"]) == 1, "the save is versioned")
	ok((d["rows"] as Array).size() == 1, "and carries the row")

	var b := _bus(Carcasses.AUTUMN, Carcasses.SKY_CLEAR, 9.0)
	b.from_dict(d)
	ok(b.records.size() == 1, "which comes back")
	var rb := b.records[0] as Dictionary
	near_f(float(rb["left"]), float(rec["left"]), 1e-9, "with the same meat on it")
	near_f(float(rb["born"]), float(rec["born"]), 1e-9, "the same birthday")
	ok((rb["seen"] as Dictionary).size() == (rec["seen"] as Dictionary).size(),
			"and the same claimants already on it")
	near_f(b.days, a.days, 1e-9, "and the bus is on the same day")
	## And it keeps going the same way. A reload that resets an accumulator
	## would re-find everything from scratch and read as a second wave.
	_run_days(a, 3.0)
	_run_days(b, 3.0)
	near_f(float(rb["left"]), float(rec["left"]), 1e-6,
			"three more days apart and the two are still the same carcass")
	ok(str(a.report()) == str(b.report()), "and the two buses still agree")
	## A SECOND ROUND TRIP, EARLY. The one above reloads a carcass that
	## everybody has already found, so the SEARCH accumulators have nothing
	## left to carry and a save that dropped them looked identical. The
	## sweep named it. This one saves at twelve hours, mid-search.
	var e := _bus(Carcasses.AUTUMN, Carcasses.SKY_CLEAR, 9.0)
	var re := _moose(e)
	_run_hours(e, 12.0)
	ok(not (re["seen"] as Dictionary).has("pack"),
			"at twelve hours the pack has not found it yet")
	ok(float((re["prog"] as Dictionary).get("pack", 0.0)) > 0.0,
			"but is part of the way there (%.2f)" % float((re["prog"] as Dictionary).get("pack", 0.0)))
	var f2 := _bus(Carcasses.AUTUMN, Carcasses.SKY_CLEAR, 9.0)
	f2.from_dict(e.to_dict())
	var rf2 := f2.records[0] as Dictionary
	_run_hours(e, 48.0)
	_run_hours(f2, 48.0)
	near_f(float((rf2["seen"] as Dictionary).get("pack", -1.0)),
			float((re["seen"] as Dictionary).get("pack", -2.0)), 1e-9,
			"and after the reload the pack still arrives on the same half hour")
	e.free()
	f2.free()
	a.free()
	b.free()


# ----------------------------------------------------------------- chronicle

func _t_chronicle() -> void:
	claim("chronicle", 14)
	## A STUB IS NOT THE COLLABORATOR. Everything above drives a FakeSky;
	## this drives the real Chronicle's real front door, because three
	## mutations of a real Chronicle method survived a green suite on
	## 2026-09-09 for exactly the want of a section like this one.
	var chron := Chronicle.new()
	root.add_child(chron)
	chron.boot()
	ok(chron.has_method("sky_at"), "Chronicle still has sky_at")
	ok(chron.has_method("season_at"), "and season_at")
	ok(chron.has_method("nearest_place"), "and nearest_place")
	ok(chron.has_method("deposit_rumour"), "and deposit_rumour")
	ok(chron.places.size() > 10, "and a roster of places (%d)" % chron.places.size())

	var c := Carcasses.new()
	c.chron = chron
	root.add_child(c)
	var lvl := c.sky_at(3.0)
	ok(lvl >= 0 and lvl <= 4, "the real sky_at answers a legal Weather.Level (%d)" % lvl)
	var sea := c.season_at(3.0)
	ok(sea >= 0 and sea <= 3, "and the real season_at a legal season (%d)" % sea)
	## Carcasses' own season fallback must agree with the Chronicle's, or two
	## sims on the same calendar disagree about what month it is.
	var agree := true
	for dd in [0.0, 13.5, 25.0, 49.9, 71.2, 95.5, 120.0]:
		var mine := int(fposmod(float(dd), Carcasses.DAYS_PER_SEASON * 4.0)
				/ Carcasses.DAYS_PER_SEASON) % 4
		if Chronicle.season_at(float(dd)) != mine:
			agree = false
	ok(agree, "the fallback agrees with Chronicle.season_at on every sample")

	## A kill beside a real place tells that place, through the real door.
	var p := chron.places[0] as Dictionary
	var pp: Vector2 = p["pos"]
	var at := Vector3(pp.x + 30.0, 0.0, pp.y + 30.0)
	c.advance(chron.days * 24.0 + 6.0)
	var rec := c.add("moose", "moose", at, Carcasses.mass_of("moose", MOOSE_LEN))
	ok(String(rec["place"]) == String(p["name"]),
			"a carcass thirty metres from %s belongs to it" % String(p["name"]))
	var before := (chron.place_by_name(String(p["name"]))["rumours"] as Array).size()
	_run_days(c, 3.0)
	c.sense()
	var after := (chron.place_by_name(String(p["name"]))["rumours"] as Array).size()
	ok(after > before, "and three days later the village is talking about it")
	## The rumour keeps the date of the KILL, not of the telling. A story
	## three days old has to read as three days old whoever passes it on.
	var newest := 0.0
	var found_ours := false
	for r in chron.place_by_name(String(p["name"]))["rumours"]:
		var rr := r as Dictionary
		if String(rr.get("kind", "")) == "carcass":
			found_ours = true
			newest = float(rr.get("day", 0.0))
	ok(found_ours, "the board carries a carcass rumour")
	near_f(newest, float(rec["born"]), 0.01,
			"dated to the day the moose died, not the day the crows told anyone")
	## AND A DEAD HARE IS NOT NEWS. The sweep named this too:
	## TELL_MIN_MASS could be dialled to zero and every assertion above
	## still agreed, because every carcass in this section was a moose.
	var hare := c.add("hare", "hare", at, Carcasses.mass_of("hare", HARE_LEN))
	ok(not hare.is_empty(), "a hare is on the ledger like anything else")
	_run_days(c, 3.0)
	c.sense()
	var hare_told := false
	for r2 in chron.place_by_name(String(p["name"]))["rumours"]:
		if String((r2 as Dictionary).get("text", "")).contains("hare"):
			hare_told = true
	ok(not hare_told, "but the village is never told about it")
	c.free()
	chron.free()


# ---------------------------------------------------------------------- feed

func _t_feed() -> void:
	claim("feed", 8)
	## The other real front door: RumourFeed.offer.
	var pl := FakePlayer.new()
	root.add_child(pl)
	pl.add_to_group("player")
	var feed := RumourFeed.new()
	root.add_child(feed)
	feed.boot()
	## The feed finds the player for itself on its own scan; with nobody
	## bound it is muted BY DEFINITION and refuses every offer, which would
	## make this whole section assert nothing at all.
	feed.player = pl
	ok(feed.has_method("offer"), "RumourFeed still has offer")
	ok(not feed.muted_now(), "and is listening rather than muted by default")

	var c := Carcasses.new()
	var sky := FakeSky.new()
	sky.season = Carcasses.AUTUMN
	c.chron = sky
	c.add_child(sky)
	root.add_child(c)
	c.feed = feed
	c.player = pl
	c.advance(START_DAY * 24.0 + 12.0)
	var rec := c.add("moose", "moose", Vector3.ZERO, Carcasses.mass_of("moose", MOOSE_LEN))
	pl.global_position = Vector3(1e5, 0.0, 1e5)
	c.sense()
	ok(c._told_player.is_empty(), "a carcass a hundred kilometres away says nothing to you")
	pl.global_position = Vector3(4.0, 0.0, 0.0)
	c.sense()
	ok(not c._told_player.is_empty(),
			"and one at your feet is offered to the real feed, which took it")
	## The line itself must say something, and must change as it is eaten.
	var fresh := Carcasses.legible(rec, c.days)
	ok(fresh.contains("moose"), "the line names the animal: %s" % fresh)
	rec["left"] = float(rec["mass"]) * 0.30
	var picked := Carcasses.legible(rec, c.days)
	ok(picked != fresh, "and a picked carcass does not read like a fresh one")
	(rec["seen"] as Dictionary)["pack"] = c.days
	var busy := Carcasses.legible(rec, c.days)
	ok(busy.contains("coyotes"), "and one with coyotes on it says so: %s" % busy)
	ok(Carcasses.rumour_for(rec, "bear") != Carcasses.rumour_for(rec, "pack"),
			"a bear and a pack are different news")
	c.free()
	feed.free()
	pl.free()


# -------------------------------------------------------------------- purity

func _t_purity() -> void:
	claim("purity", 10)
	## The pure block is the whole feature. If any of it reaches for a node,
	## a clock or the live Weather, none of the sections above mean anything.
	var src := _src("res://scripts/Carcasses.gd")
	ok(src.length() > 20000, "the source scanned back %d characters" % src.length())
	var names := ["works_now", "scent", "find_gain", "rot_per_step", "wants_it",
			"present", "stage_of", "legible"]
	var clean := true
	var short_body := ""
	for n in names:
		var body := _func_body(src, String(n))
		if body.strip_edges().is_empty():
			short_body = String(n)
		if body.contains("get_tree(") or body.contains("self.") or body.contains("Weather."):
			clean = false
	ok(short_body == "", "every pure function's body was actually read (%s)" % short_body)
	ok(clean, "and none of them reaches for a tree, a self or the live Weather")
	## Prove the reader on planted text first: a scan that comes back empty
	## agrees with everything. Built by CONCATENATION so the fixture does not
	## trip the very scan it is proving.
	var planted := "static func " + "works_now" + "(a):\n\tvar x = get_" + "tree()\n\nfunc z():\n\tpass\n"
	var pb := _func_body(planted, "works_now")
	ok(pb.contains("get_" + "tree("), "the body reader finds a planted defect before it is trusted")
	ok(not pb.contains("func z"), "and stops at the next function")
	var spaced := "static func " + "scent" + "(a):\n    return Weather" + ".foo\n\nfunc z():\n    pass\n"
	ok(_func_body(spaced, "scent").contains("Weather" + "."),
			"and reads a SPACE-indented body too, which is the bug that hid a whole scan")
	## Same arguments, same answer, twice -- no hidden state anywhere.
	near_f(Carcasses.find_gain(1, 49.0, 49.0, 3.0, 2, 1), Carcasses.find_gain(1, 49.0, 49.0, 3.0, 2, 1),
			0.0, "the same arguments give the same answer")
	ok(Carcasses.find_gain(1, 49.0, 49.0, 3.0, 2, 1) != Carcasses.find_gain(1, 49.0, 49.0, 3.0, 4, 1),
			"a different sky gives a different answer")
	ok(Carcasses.find_gain(1, 49.0, 49.0, 3.0, 2, 1) != Carcasses.find_gain(1, 49.0, 49.0, 3.0, 2, 3),
			"and a different season does")
	ok(Carcasses.find_gain(1, 490.0, 490.0, 3.0, 2, 1) != Carcasses.find_gain(1, 49.0, 49.0, 3.0, 2, 1),
			"and a different animal does")


# --------------------------------------------------------------- no bindings

func _t_no_bindings() -> void:
	claim("no_bindings", 6)
	## A shadowed dev binding is round-blocking in this project. This file
	## claims to add no binding; the claim is asserted here against the
	## source rather than in a ledger line.
	var fn := "func " + "_input"
	var planted := fn + "(event) -> void:\n\tif event is Input" + "EventKey:\n\t\tpass\n\nfunc other() -> void:\n\tpass\n"
	var planted_body := _func_body(planted, "_input")
	ok(planted_body.contains("EventKey"),
			"the body reader finds a planted input body before it is trusted")
	ok(not planted_body.contains("func other"), "and stops at the next function")
	var reg := load("res://tests/DevInputRegistry.gd")
	ok(reg != null, "the dev-input registry is loadable")
	for path in ["res://scripts/Carcasses.gd", "res://tests/CarcassTests.gd"]:
		var src := _src(String(path))
		var cbs: Array = reg.input_callbacks(src)
		var keys := src.contains("K" + "EY_") or src.contains("Input" + "EventKey") \
				or src.contains("Input" + "Map") or src.contains("is_action" + "_pressed")
		ok(src.length() > 500 and cbs.is_empty() and not keys,
				"%s scanned back %d chars, declares no input callback and claims no key (%d)"
				% [path, src.length(), cbs.size()])
	ok(not _src("res://scripts/Carcasses.gd").contains("_unhandled" + "_input"),
			"and no unhandled-input hook either")
