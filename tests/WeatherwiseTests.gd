extends SceneTree

# =============================================================================
# tests/WeatherwiseTests.gd -- the sky, and the fact that everything under it
# has an opinion about the sky.
#
#   godot --headless --path . --script res://tests/WeatherwiseTests.gd
#
# `Weatherwise` is pure static arithmetic over the real `CritterDex`, so most
# of this is a loop over the real roster and a faithful rebuild of the pool
# filter `WildlifeDirector._roll_species` uses. Five sections carry the weight:
#
#   `fairweather` -- the claim that costs the most if it is ever wrong: at
#   CLEAR every species in the game keeps EXACTLY its old spawn weight and
#   EXACTLY no urge to hide. This feature is a departure from a day that does
#   not move, and that is asserted to the ten-thousandth, per species.
#
#   `eft` -- the headline. `rain_only` has been a flag on one species since
#   August with nothing in the project reading it. The shares here are the
#   ones `tools/probe_weatherwise.gd` MEASURED off the real pool, stated as
#   literals, because a constant compared with itself is not an assertion.
#
#   `sorts` -- the result nobody put in by hand: out of one table that never
#   mentions terrain, a storm leaves the deep woods with 42% of their spawn
#   weight and an open field with 16%.
#
#   `noise` -- the crossing, SEARCHED for rather than asserted near. The
#   sprint radius belongs to `Telegraph` and the notice radius belongs to
#   `CritterDex`; this file restates neither and asks at which rung one falls
#   under the other.
#
#   `telegraph` / `wiring` -- a method nobody calls is not a feature. Both
#   collaborators get their REAL front door, and every call site is asserted
#   in context through a comment stripper.
# =============================================================================

const MIN_ASSERTIONS := 170

# --------------------------------------------------------------- measured
# All of these came out of tools/probe_weatherwise.gd running against the real
# dex BEFORE scripts/Weatherwise.gd existed. Percentages of pool weight.

const PHASE := 0.45

# [zone, hour, water] -> retained % of clear-weather pool weight, by rung
const KEEP_WOODS_DAWN := [95.0, 94.0, 89.0, 70.0, 42.0]
const KEEP_WOODS_NOON := [91.0, 85.0, 80.0, 73.0, 47.0]
const KEEP_FIELD_DAWN := [100.0, 95.0, 82.0, 54.0, 29.0]
const KEEP_FIELD_NOON := [100.0, 88.0, 64.0, 34.0, 16.0]
const KEEP_LAKE_NOON := [95.0, 87.0, 80.0, 72.0, 52.0]

# share of the pool that is a Red Eft
const EFT_WOODS_DAWN := [0.0, 0.0, 8.8, 16.9, 21.3]
const EFT_WOODS_NOON := [0.0, 0.0, 18.7, 30.5, 35.8]
const EFT_LAKE_NOON := [0.0, 0.0, 10.4, 17.3, 18.0]

# share of the pool that soars
const SOAR_FIELD_DAWN := [5.7, 2.7, 0.8, 0.0, 0.0]
const SOAR_FIELD_NOON := [10.7, 5.5, 2.0, 0.0, 0.0]

# the roster, counted by guild off the real dex
const GUILD_COUNTS := {
	"SOARING": 4, "SHELTERING": 18, "FLATTENED": 7, "DRAWN": 2,
	"UNBOTHERED": 19, "HUNTING": 8, "BEDDING": 8, "VOICE": 2, "LEGEND": 5,
}
const ROSTER_SIZE := 73

var _pass := 0
var _fail := 0
var _claims: Dictionary = {}
var _counts: Dictionary = {}
var _section := ""


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

func read_src(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s


func _code_only(src: String) -> String:
	# Copied verbatim from tests/SeasonsTests.gd, which is where it was written
	# to retire a trap that had fired four rounds running: a negative source
	# scan going red on the comment explaining why the file never does the
	# thing. Two passes -- a whole comment line goes, and a trailing comment is
	# cut off any line with no quote in it. The second pass is the one that
	# matters: without it, a call switched off as `pass  # thing()` still
	# satisfies a scan for `thing()`.
	var out: PackedStringArray = []
	for line in src.split("\n"):
		var s := String(line)
		var t := s.strip_edges()
		if t.begins_with("#"):
			continue
		var h := s.find("#")
		if h >= 0 and not s.substr(0, h).contains("\""):
			s = s.substr(0, h)
		out.append(s)
	return "\n".join(out)


func at_rung(r: float) -> Dictionary:
	# A settled sky at rung r: nowhere to go, so no front.
	var i := int(round(r))
	return Weatherwise.env(i, i, 1.0, 12.0)


func arriving(from_l: int, to_l: int, blend: float) -> Dictionary:
	return Weatherwise.env(to_l, from_l, blend, 12.0)


func fine(r: float) -> Dictionary:
	# ⚠ `at_rung` QUANTISES. It builds a settled sky, and a settled sky sits on
	# an integer rung, so a sweep written against it samples five points and
	# calls that a search. The first version of this file searched for the rung
	# at which the sky empties of eagles that way and got 2.50 -- which is not
	# a property of the table at all, it is `round()`.
	#
	# `fine()` is the continuous sky: genuinely partway between two rungs.
	# It necessarily carries a FRONT (a fractional rung means a blend that has
	# not finished), so it is used only where the front cannot reach the
	# answer -- SOARING, the two masks, and the fog band. `_t_front` asserts
	# that those guilds are not the ones a barometer stirs.
	var lo := int(floorf(r))
	var hi := mini(lo + 1, 4)
	if hi == lo:
		return Weatherwise.env(lo, lo, 1.0, 12.0)
	return Weatherwise.env(hi, lo, r - float(lo), 12.0)


# The pool filter WildlifeDirector._roll_species builds, rebuilt here without
# the roll. If this ever drifts from that function the numbers below are
# worthless, so `_t_wiring` asserts the real function still has every clause.
func pool(zone: String, hour: float, water: bool) -> Array:
	var outp: Array = []
	for e in CritterDex.species_for_zone(zone):
		var k := String(e["key"])
		if CritterDex.rig_of(k) == "SWARM":
			continue
		if not CritterDex.is_awake(k, hour, PHASE):
			continue
		if bool(CritterDex.flag(k, "audio_only", false)):
			continue
		if bool(CritterDex.flag(k, "water", false)) and not water:
			continue
		if bool(CritterDex.flag(k, "cliff", false)) or bool(CritterDex.flag(k, "island_only", false)) \
				or bool(CritterDex.flag(k, "far_only", false)) or bool(CritterDex.flag(k, "marine", false)):
			continue
		var w := float(e["w"])
		var rare = CritterDex.flag(k, "rare", 1.0)
		w *= float(rare) if rare is float else 1.0
		if bool(CritterDex.flag(k, "dusk", false)):
			var dusk := (hour >= 18.6 and hour < 21.2) or (hour >= 4.6 and hour < 7.4)
			w *= 1.8 if dusk else 0.45
		outp.append({"key": k, "w": w})
	return outp


# Returns {keep, eft, soar} as percentages, for one zone/hour at one rung.
func shares(zone: String, hour: float, water: bool, r: float) -> Dictionary:
	var base := pool(zone, hour, water)
	var e := at_rung(r)
	var tot := 0.0
	var raw := 0.0
	var eft := 0.0
	var soar := 0.0
	for row in base:
		var k := String(row["key"])
		var w0 := float(row["w"])
		raw += w0
		var w := w0 * Weatherwise.out_mult(k, e)
		tot += w
		if k == "red_eft":
			eft += w
		if Weatherwise.guild_of(k) == Weatherwise.Guild.SOARING:
			soar += w
	return {
		"keep": 100.0 * tot / raw if raw > 0.0 else 0.0,
		"eft": 100.0 * eft / tot if tot > 0.0 else 0.0,
		"soar": 100.0 * soar / tot if tot > 0.0 else 0.0,
		"n": base.size(),
	}


# ============================== 1. the tables ===============================

func _t_tables() -> void:
	claim("tables", 24)
	var bad := Weatherwise.table_problems()
	ok(bad.is_empty(), "the shipped tables validate: " + ", ".join(PackedStringArray(bad)))

	# A guard that can only ever see a correct table is a guard no mutation can
	# reach. So hand it tables that ARE wrong and demand the right complaint.
	var good_out: Dictionary = {}
	var good_cov: Dictionary = {}
	for g in Weatherwise.OUT.keys():
		good_out[g] = (Weatherwise.OUT[g] as Array).duplicate()
	for g in Weatherwise.COVER.keys():
		good_cov[g] = (Weatherwise.COVER[g] as Array).duplicate()
	var good_noise: Array = Weatherwise.NOISE_MASK.duplicate()
	var good_relay: Array = Weatherwise.RELAY_MASK.duplicate()
	ok(Weatherwise.problems_in(good_out, good_cov, good_noise, good_relay).is_empty(),
			"the copies validate too")

	var t1: Dictionary = good_out.duplicate(true)
	(t1[Weatherwise.Guild.HUNTING] as Array)[0] = 1.4
	ok(_says(Weatherwise.problems_in(t1, good_cov, good_noise, good_relay), "fair weather"),
			"an OUT row that moves a clear day is caught")

	var t2: Dictionary = good_cov.duplicate(true)
	(t2[Weatherwise.Guild.BEDDING] as Array)[0] = 0.3
	ok(_says(Weatherwise.problems_in(good_out, t2, good_noise, good_relay), "fair weather"),
			"a COVER row that wants shelter on a clear day is caught")

	var t3: Dictionary = good_out.duplicate(true)
	(t3[Weatherwise.Guild.SOARING] as Array)[3] = 0.3
	ok(_says(Weatherwise.problems_in(t3, good_cov, good_noise, good_relay), "soaring birds"),
			"a sky that keeps its eagles in the rain is caught")

	var t4: Dictionary = good_out.duplicate(true)
	(t4[Weatherwise.Guild.FLATTENED] as Array)[4] = 0.2
	ok(_says(Weatherwise.problems_in(t4, good_cov, good_noise, good_relay), "insects"),
			"insects still flying in a storm is caught")

	var t5: Dictionary = good_out.duplicate(true)
	(t5[Weatherwise.Guild.DRAWN] as Array)[3] = 1.0
	ok(_says(Weatherwise.problems_in(t5, good_cov, good_noise, good_relay), "invitation"),
			"rain that invites nobody out is caught")

	var t6: Dictionary = good_out.duplicate(true)
	(t6[Weatherwise.Guild.SHELTERING] as Array)[2] = -0.5
	ok(_says(Weatherwise.problems_in(t6, good_cov, good_noise, good_relay), "out of range"),
			"a negative weight is caught")

	var t7: Dictionary = good_cov.duplicate(true)
	(t7[Weatherwise.Guild.SHELTERING] as Array)[4] = 1.8
	ok(_says(Weatherwise.problems_in(good_out, t7, good_noise, good_relay), "0..1 urge"),
			"an urge over one is caught")

	var t8: Dictionary = good_out.duplicate(true)
	t8.erase(Weatherwise.Guild.BEDDING)
	ok(_says(Weatherwise.problems_in(t8, good_cov, good_noise, good_relay), "no row for BEDDING"),
			"a missing guild row is caught, by name")

	var t9: Dictionary = good_out.duplicate(true)
	(t9[Weatherwise.Guild.HUNTING] as Array).resize(4)
	ok(_says(Weatherwise.problems_in(t9, good_cov, good_noise, good_relay), "five rungs"),
			"a short row is caught")

	var n1: Array = good_noise.duplicate()
	n1[3] = 0.99
	ok(_says(Weatherwise.problems_in(good_out, good_cov, n1, good_relay), "noise mask is not monotone"),
			"a noise mask that gets LOUDER in the rain is caught")

	var n2: Array = good_noise.duplicate()
	n2[4] = 0.8
	ok(_says(Weatherwise.problems_in(good_out, good_cov, n2, good_relay), "running man"),
			"a storm that hides nobody is caught")

	var n3: Array = good_noise.duplicate()
	n3[0] = 0.9
	ok(_says(Weatherwise.problems_in(good_out, good_cov, n3, good_relay), "mask moves fair weather"),
			"a mask that bites on a clear day is caught")

	var r1: Array = good_relay.duplicate()
	r1[2] = 1.4
	ok(_says(Weatherwise.problems_in(good_out, good_cov, good_noise, r1), "relay mask is not monotone"),
			"a relay mask that lengthens in the rain is caught")

	var r2: Array = good_relay.duplicate()
	r2.resize(3)
	ok(_says(Weatherwise.problems_in(good_out, good_cov, good_noise, r2), "five rungs"),
			"a short mask is caught")

	# and the tables are still what they were after all that poking
	ok(Weatherwise.table_problems().is_empty(), "the shipped tables are unharmed")
	ok(Weatherwise.OUT.size() == Weatherwise.GUILD_NAMES.size(), "every guild has an OUT row")
	ok(Weatherwise.COVER.size() == Weatherwise.GUILD_NAMES.size(), "every guild has a COVER row")
	ok(Weatherwise.NOISE_MASK.size() == 5, "the noise mask has five rungs")
	ok(Weatherwise.RELAY_MASK.size() == 5, "the relay mask has five rungs")
	ok(float(Weatherwise.NOISE_MASK[0]) == 1.0, "a clear day masks nothing")
	ok(float(Weatherwise.RELAY_MASK[0]) == 1.0, "a clear day shortens nothing")
	ok(float(Weatherwise.NOISE_MASK[4]) <= 0.45, "a storm hides a running man")
	ok(Weatherwise.FRONT_STIR > 0.0, "a falling barometer does something")


func _says(bad: Array, needle: String) -> bool:
	for b in bad:
		if String(b).contains(needle):
			return true
	return false


# ============================== 2. the guilds ===============================

func _t_guilds() -> void:
	claim("guilds", 26)
	var counts: Dictionary = {}
	var n := 0
	for k in CritterDex.DEX.keys():
		n += 1
		var g := Weatherwise.guild_of(String(k))
		ok(g >= 0 and g < Weatherwise.GUILD_NAMES.size(), String(k) + " lands in a guild")
		var nm := Weatherwise.guild_name(g)
		counts[nm] = int(counts.get(nm, 0)) + 1
	ok(n == ROSTER_SIZE, "the roster is still %d species (got %d)" % [ROSTER_SIZE, n])
	for nm in GUILD_COUNTS.keys():
		ok(int(counts.get(nm, 0)) == int(GUILD_COUNTS[nm]),
				"%s holds %d species (got %d)" % [nm, int(GUILD_COUNTS[nm]), int(counts.get(nm, 0))])

	# The ORDER of the classifier is the whole of it, and these are the five
	# places where two clauses both want the same animal.
	ok(Weatherwise.guild_of("moose") == Weatherwise.Guild.BEDDING,
			"a moose is a CERVID before it is a thing flagged water")
	ok(bool(CritterDex.flag("moose", "water", false)),
			"...and it really is flagged water, or that proves nothing")
	ok(Weatherwise.guild_of("mink") == Weatherwise.Guild.UNBOTHERED,
			"a mink IS a thing flagged water, and hunts wet")
	ok(Weatherwise.guild_of("garter_snake") == Weatherwise.Guild.SHELTERING,
			"a snake basks, so rain sends it under")
	ok(bool(CritterDex.flag("garter_snake", "basks", false)),
			"...off the dex's own basks flag")
	ok(Weatherwise.guild_of("red_eft") == Weatherwise.Guild.DRAWN,
			"a newt does not bask, and the rain is its weather")
	ok(Weatherwise.guild_of("vulture") == Weatherwise.Guild.SOARING,
			"a vulture soars before it is a bird")
	ok(Weatherwise.guild_of("specter_moose") == Weatherwise.Guild.LEGEND,
			"a legend is a legend before it is a CERVID")
	ok(Weatherwise.guild_of("peeper") == Weatherwise.Guild.VOICE,
			"a voice is a voice before it is a swarm")
	ok(Weatherwise.guild_of("snowy_owl") == Weatherwise.Guild.SHELTERING,
			"an owl glides but does not soar")

	# DERIVED, NOT RESTATED. Every SOARING member must carry the dex's own
	# `soars` flag and vice versa -- give a new species that flag and it is
	# priced with no edit in Weatherwise.gd.
	for k in CritterDex.DEX.keys():
		var key := String(k)
		if bool(CritterDex.flag(key, "legend", false)):
			continue
		var soars := bool(CritterDex.flag(key, "soars", false))
		var is_s := Weatherwise.guild_of(key) == Weatherwise.Guild.SOARING
		if soars != is_s:
			ok(false, key + ": soars flag and SOARING guild disagree")
	ok(true, "soars and SOARING agree across the whole roster")
	ok(Weatherwise.guild_name(-1) == "?", "an impossible guild names itself honestly")
	ok(Weatherwise.guild_name(99) == "?", "...at both ends")


# ============================== 3. the rungs ================================

func _t_rungs() -> void:
	claim("rungs", 22)
	for i in range(5):
		near_f(Weatherwise.rung(at_rung(float(i))), float(i), 0.0001,
				"a settled sky sits exactly on its rung")
	# continuous between two rungs, and exact at each end
	near_f(Weatherwise.rung(arriving(1, 3, 0.0)), 1.0, 0.0001, "a front starts where it was")
	near_f(Weatherwise.rung(arriving(1, 3, 1.0)), 3.0, 0.0001, "...and lands where it is going")
	near_f(Weatherwise.rung(arriving(1, 3, 0.5)), 2.0, 0.0001, "...and is halfway in between")
	near_f(Weatherwise.rung(arriving(4, 0, 0.25)), 3.0, 0.0001, "a clearing sky runs the other way")
	var last := -1.0
	var mono := true
	for s in range(41):
		var r := Weatherwise.rung(arriving(0, 4, float(s) / 40.0))
		if r < last - 0.0001:
			mono = false
		last = r
	ok(mono, "the rung never goes backwards as a front arrives")
	ok(Weatherwise.rung(Weatherwise.env(9, 9, 1.0)) <= 4.0, "a nonsense level is clamped")
	ok(Weatherwise.rung(Weatherwise.env(-3, -3, 1.0)) >= 0.0, "...at both ends")

	# the barometer
	near_f(Weatherwise.front(at_rung(4.0)), 0.0, 0.0001,
			"a storm that has ARRIVED is not a storm that is COMING")
	ok(Weatherwise.front(arriving(0, 3, 0.2)) > 0.0, "a falling barometer reads positive")
	ok(Weatherwise.front(arriving(4, 0, 0.2)) < 0.0, "a rising one reads negative")
	near_f(Weatherwise.front(arriving(0, 4, 0.0)), 1.0, 0.0001, "a two-rung jump saturates it")
	near_f(Weatherwise.front(arriving(4, 0, 0.0)), -1.0, 0.0001, "...both ways")
	ok(Weatherwise.front(arriving(0, 1, 0.0)) < Weatherwise.front(arriving(0, 3, 0.0)),
			"a bigger front reads harder than a smaller one")
	ok(Weatherwise.front(arriving(0, 3, 0.9)) < Weatherwise.front(arriving(0, 3, 0.1)),
			"...and it fades as the front lands")
	# ⚠ AND THE TABLES ARE READ CONTINUOUSLY, NOT STEPPED. A `_row` that
	# returns the rung it is standing on instead of interpolating between two
	# is INVISIBLE at every integer rung — which is where almost every other
	# assertion in this file asks its question. The mutation sweep found
	# exactly that hole, so these three ask between the rungs instead.
	near_f(Weatherwise.out_mult("blue_jay", fine(2.5)), 0.375, 0.0005,
			"a jay halfway between drizzle and rain is halfway between the two rows")
	near_f(Weatherwise.noise_mult(fine(2.5)), 0.68, 0.0005, "and so is the noise mask")
	near_f(Weatherwise.relay_mult(fine(3.5)), 0.55, 0.0005, "and the relay mask")
	ok(Weatherwise.level_name(at_rung(0.0)) == "clear", "rung 0 is a clear sky")
	ok(Weatherwise.level_name(at_rung(4.0)) == "storm", "rung 4 is a storm")
	ok(Weatherwise.level_name(arriving(2, 3, 0.4)) == "drizzle", "a rain not yet half-arrived is still a drizzle")
	ok(Weatherwise.level_name(arriving(2, 3, 0.5)) == "rain",
			"and one exactly halfway rounds UP -- the readout names the sky you are getting")


# =========================== 4. fair weather ================================

func _t_fairweather() -> void:
	claim("fairweather", 20)
	# THE CLAIM THAT COSTS THE MOST IF IT IS WRONG. Per species, to the
	# ten-thousandth: a clear day is the game Myrkfell already had.
	var clear := at_rung(0.0)
	var moved: Array = []
	var urged: Array = []
	for k in CritterDex.DEX.keys():
		var key := String(k)
		var m := Weatherwise.out_mult(key, clear)
		var want := 0.0 if bool(CritterDex.flag(key, "rain_only", false)) else 1.0
		if absf(m - want) > 0.0001:
			moved.append(key)
		if absf(Weatherwise.cover_urge(key, clear)) > 0.0001:
			urged.append(key)
	ok(moved.is_empty(), "a clear day moves nobody's weight: " + ", ".join(PackedStringArray(moved)))
	ok(urged.is_empty(), "a clear day gives nobody an urge: " + ", ".join(PackedStringArray(urged)))
	near_f(Weatherwise.noise_mult(clear), 1.0, 0.0001, "a clear day masks no footstep")
	near_f(Weatherwise.relay_mult(clear), 1.0, 0.0001, "a clear day shortens no alarm")

	# ...and the ONE deliberate exception, which is the point of the round.
	near_f(Weatherwise.out_mult("red_eft", clear), 0.0, 0.0001,
			"the one species a clear day DOES move is the rain_only one")
	near_f(Weatherwise.out_mult("red_eft", at_rung(1.0)), 0.0, 0.0001,
			"an overcast sky is still not rain")
	ok(Weatherwise.out_mult("red_eft", at_rung(2.0)) > 0.0, "drizzle is")
	var rain_only := 0
	for k in CritterDex.DEX.keys():
		if bool(CritterDex.flag(String(k), "rain_only", false)):
			rain_only += 1
	ok(rain_only == 1, "exactly one species in the game is rain_only (got %d)" % rain_only)

	# a settled clear sky has no front, so the stir cannot leak into it
	near_f(Weatherwise.out_mult("whitetail", clear), 1.0, 0.0001,
			"a settled clear day does not stir the deer")
	ok(Weatherwise.out_mult("whitetail", arriving(0, 2, 0.0)) > 1.0,
			"...but a drizzle on the way does")

	# the neutral guilds stay neutral at every rung: the weather must never
	# touch a legend, because legends are PLACED and not rolled
	for r in range(5):
		var e := at_rung(float(r))
		near_f(Weatherwise.out_mult("ghost_cat", e), 1.0, 0.0001, "no weather weights a legend")
		near_f(Weatherwise.cover_urge("white_raven", e), 0.0, 0.0001, "no weather hides a legend")
	near_f(Weatherwise.out_mult("cricket", at_rung(4.0)), 1.0, 0.0001,
			"a voice is never spawned, so it is never weighted")


# ============================ 5. the sky empties ============================

func _t_sky() -> void:
	claim("sky", 22)
	var soarers: Array = []
	for k in CritterDex.DEX.keys():
		if Weatherwise.guild_of(String(k)) == Weatherwise.Guild.SOARING:
			soarers.append(String(k))
	ok(soarers.size() == 4, "four birds in this game need a thermal (got %d)" % soarers.size())
	for key in soarers:
		var k := String(key)
		near_f(Weatherwise.out_mult(k, at_rung(3.0)), 0.0, 0.0001, k + " is out of the sky by RAIN")
		near_f(Weatherwise.out_mult(k, at_rung(4.0)), 0.0, 0.0001, k + " is out of it in a storm")
		ok(Weatherwise.out_mult(k, at_rung(1.0)) < 0.6, k + " is already thinning under cloud")
		ok(Weatherwise.out_mult(k, at_rung(2.0)) > 0.0, k + " has not gone before the drizzle")

	# SEARCHED, not asserted near: the rung at which the sky is EMPTY of
	# soaring birds, found by walking it at a fiftieth of a rung.
	var gone := -1.0
	var r := 0.0
	while r <= 4.0001:
		if Weatherwise.out_mult("bald_eagle", fine(r)) <= 0.0001:
			gone = r
			break
		r += 0.02
	ok(gone >= 0.0, "the sky does empty at some point")
	near_f(gone, 3.0, 0.05, "the sky empties exactly at RAIN, not before and not at the storm")
	ok(gone < 4.0, "the eagles are gone BEFORE the worst of it, which is the whole tell")
	ok(not Weatherwise.FRONT_GUILDS.has(Weatherwise.Guild.SOARING),
			"and a barometer cannot be what is answering, because SOARING is not stirred by one")

	# and the falling half is monotone -- a thermal does not come back
	var last := 2.0
	var mono := true
	var rr := 0.0
	while rr <= 3.0001:
		var m := Weatherwise.out_mult("osprey", fine(rr))
		if m > last + 0.0001:
			mono = false
		last = m
		rr += 0.05
	ok(mono, "a thermal never comes back as the sky closes")
	ok(Weatherwise.cover_urge("bald_eagle", at_rung(4.0)) >= 0.9,
			"a grounded eagle wants to be somewhere else entirely")


# =============================== 6. the eft =================================

func _t_eft() -> void:
	claim("eft", 24)
	# The headline, measured off the real pool. `rain_only` has been a flag on
	# one species since August and NOTHING in this project has ever read it.
	for i in range(5):
		var s := shares("deep_woods", 6.0, false, float(i))
		near_f(float(s["eft"]), EFT_WOODS_DAWN[i], 0.15,
				"deep woods at dawn, rung %d: the eft's share" % i)
		var s2 := shares("deep_woods", 13.0, false, float(i))
		near_f(float(s2["eft"]), EFT_WOODS_NOON[i], 0.15,
				"deep woods at midday, rung %d: the eft's share" % i)
		var s3 := shares("moosehead", 13.0, true, float(i))
		near_f(float(s3["eft"]), EFT_LAKE_NOON[i], 0.15,
				"moosehead at midday, rung %d: the eft's share" % i)

	# stated as the sentence rather than as the number
	var dry := shares("deep_woods", 6.0, false, 0.0)
	var wet := shares("deep_woods", 6.0, false, 3.0)
	near_f(float(dry["eft"]), 0.0, 0.0001, "in fair weather it is not there at all")
	ok(float(wet["eft"]) >= 15.0,
			"in real rain one animal in six on a wet dawn is a species nobody has met")
	ok(float(wet["eft"]) <= 25.0, "...and the woods are not a documentary about newts")
	ok(int(dry["n"]) > 20, "the dawn pool is a real pool, not two animals")

	# a threshold needs a fixture on each side of it: the wood frog is DRAWN
	# and NOT rain_only, so it is out in every weather and merely likes rain
	ok(Weatherwise.guild_of("wood_frog") == Weatherwise.Guild.DRAWN, "the wood frog is DRAWN too")
	ok(not bool(CritterDex.flag("wood_frog", "rain_only", false)), "...but it is not rain_only")
	near_f(Weatherwise.out_mult("wood_frog", at_rung(0.0)), 1.0, 0.0001,
			"so a clear day leaves it exactly where it was")
	ok(Weatherwise.out_mult("wood_frog", at_rung(3.0)) > 2.0, "and rain brings it out in numbers")
	ok(Weatherwise.out_mult("wood_frog", at_rung(4.0))
			< Weatherwise.out_mult("wood_frog", at_rung(3.0)),
			"even a newt does not want to be hammered")
	ok(Weatherwise.cover_urge("red_eft", at_rung(3.0)) <= 0.05,
			"and nothing that came out FOR the rain wants to hide from it")


# ======================= 7. it sorts, it does not empty =====================

func _t_sorts() -> void:
	claim("sorts", 26)
	for i in range(5):
		near_f(float(shares("deep_woods", 6.0, false, float(i))["keep"]), KEEP_WOODS_DAWN[i], 0.6,
				"deep woods at dawn keeps its weight, rung %d" % i)
		near_f(float(shares("deep_woods", 13.0, false, float(i))["keep"]), KEEP_WOODS_NOON[i], 0.6,
				"deep woods at midday, rung %d" % i)
		near_f(float(shares("field", 6.0, false, float(i))["keep"]), KEEP_FIELD_DAWN[i], 0.6,
				"the open field at dawn, rung %d" % i)
		near_f(float(shares("field", 13.0, false, float(i))["keep"]), KEEP_FIELD_NOON[i], 0.6,
				"the open field at midday, rung %d" % i)
		near_f(float(shares("moosehead", 13.0, true, float(i))["keep"]), KEEP_LAKE_NOON[i], 0.6,
				"the lake at midday, rung %d" % i)

	# THE RESULT NOBODY PUT IN BY HAND. There is no mention of terrain
	# anywhere in Weatherwise.gd, and yet:
	var woods := float(shares("deep_woods", 13.0, false, 4.0)["keep"])
	var field := float(shares("field", 13.0, false, 4.0)["keep"])
	ok(woods >= 40.0, "a storm leaves the deep woods with most of a forest in them")
	ok(field <= 20.0, "...and an open field with almost nothing")
	ok(woods - field >= 25.0,
			"the woods shelter you and the field does not, by at least 25 points (got %.1f)"
			% (woods - field))
	# and it is not a one-rung fluke
	ok(float(shares("deep_woods", 13.0, false, 3.0)["keep"])
			- float(shares("field", 13.0, false, 3.0)["keep"]) >= 25.0,
			"...and the same is true in plain rain")

	# the field's CLEAR retention is exactly 100%, which is the proof that the
	# missing 5% in the woods is the eft's hard gate and nothing else
	near_f(float(shares("field", 13.0, false, 0.0)["keep"]), 100.0, 0.0001,
			"a field with no newt in it keeps every gram of its clear-weather weight")
	ok(float(shares("deep_woods", 13.0, false, 0.0)["keep"]) < 100.0,
			"and the woods lose exactly the newt")

	# the storm is a sorting, so who is LEFT has changed, not just how many
	var hunters_clear := _guild_share("deep_woods", 13.0, false, 0.0, Weatherwise.Guild.HUNTING)
	var hunters_storm := _guild_share("deep_woods", 13.0, false, 4.0, Weatherwise.Guild.HUNTING)
	ok(hunters_storm > hunters_clear,
			"a fox's share of the woods goes UP in a storm (%.1f -> %.1f)"
			% [hunters_clear, hunters_storm])
	var birds_clear := _guild_share("deep_woods", 13.0, false, 0.0, Weatherwise.Guild.SHELTERING)
	var birds_storm := _guild_share("deep_woods", 13.0, false, 4.0, Weatherwise.Guild.SHELTERING)
	ok(birds_storm < birds_clear * 0.6,
			"and the birds' share falls by nearly half again (%.1f -> %.1f)"
			% [birds_clear, birds_storm])


func _guild_share(zone: String, hour: float, water: bool, r: float, g: int) -> float:
	var base := pool(zone, hour, water)
	var e := at_rung(r)
	var tot := 0.0
	var mine := 0.0
	for row in base:
		var k := String(row["key"])
		var w := float(row["w"]) * Weatherwise.out_mult(k, e)
		tot += w
		if Weatherwise.guild_of(k) == g:
			mine += w
	return 100.0 * mine / tot if tot > 0.0 else 0.0


# ============================== 8. the front ================================

func _t_front() -> void:
	claim("front", 15)
	# The hour before the sky breaks is the best hunting in Myrkfell, and it is
	# over the moment the rain lands. Same rung, two skies.
	var settled := at_rung(2.0)
	var coming := arriving(0, 4, 0.5)
	near_f(Weatherwise.rung(coming), 2.0, 0.0001, "both skies are at the same rung")
	ok(Weatherwise.out_mult("whitetail", coming) > Weatherwise.out_mult("whitetail", settled),
			"a deer is out in greater numbers under a falling barometer")
	ok(Weatherwise.out_mult("red_fox", coming) > Weatherwise.out_mult("red_fox", settled),
			"and so is a fox")
	near_f(Weatherwise.out_mult("blue_jay", coming), Weatherwise.out_mult("blue_jay", settled),
			0.0001, "but a jay cannot read a barometer")
	near_f(Weatherwise.out_mult("trout", coming), Weatherwise.out_mult("trout", settled),
			0.0001, "and neither can a trout")

	# the stir has a LITERAL size, set against what FRONT_STIR was measured to
	# be worth: a full front is a third again, and no more
	# GDScript has no implicit line continuation outside brackets, so this
	# division is parenthesised rather than split across a bare assignment.
	var ratio := (Weatherwise.out_mult("whitetail", arriving(0, 4, 0.0))
			/ Weatherwise.out_mult("whitetail", at_rung(0.0)))
	ok(ratio >= 1.3, "a full front is worth at least a third again (got %.3f)" % ratio)
	ok(ratio <= 1.4, "...and not more than that")

	# it is a front, so it is over when the front lands
	near_f(Weatherwise.out_mult("whitetail", arriving(0, 3, 1.0)),
			Weatherwise.out_mult("whitetail", at_rung(3.0)), 0.0001,
			"an arrived storm is just a storm")
	# and a CLEARING sky does not stir anything -- only a falling glass does
	near_f(Weatherwise.out_mult("whitetail", arriving(4, 0, 0.5)),
			Weatherwise.out_mult("whitetail", at_rung(2.0)), 0.0001,
			"a lifting sky stirs nobody")

	# SEARCHED: where is a deer at its most numerous over a whole storm cycle?
	var best := -1.0
	var best_at := ""
	var s := 0.0
	while s <= 1.0001:
		var m := Weatherwise.out_mult("whitetail", arriving(0, 4, s))
		if m > best:
			best = m
			best_at = "blend %.2f rung %.2f" % [s, Weatherwise.rung(arriving(0, 4, s))]
		s += 0.01
	ok(best_at != "", "the sweep found a peak")
	var peak_rung := 0.0
	var s2 := 0.0
	while s2 <= 1.0001:
		if absf(Weatherwise.out_mult("whitetail", arriving(0, 4, s2)) - best) < 0.000001:
			peak_rung = Weatherwise.rung(arriving(0, 4, s2))
			break
		s2 += 0.01
	ok(peak_rung > 0.5 and peak_rung < 2.6,
			"the deer are thickest on the ground BEFORE the rain, at rung %.2f" % peak_rung)
	ok(Weatherwise.out_mult("whitetail", at_rung(3.0))
			< Weatherwise.out_mult("whitetail", at_rung(0.0)) * 0.7,
			"and once it is really raining they are lying up")
	ok(Weatherwise.cover_urge("whitetail", at_rung(3.0)) >= 0.5,
			"...which is the same animal saying the same thing twice")
	ok(Weatherwise.cover_urge("whitetail", at_rung(0.0)) == 0.0, "and not on a clear day")
	ok(Weatherwise.out_mult("black_bear", arriving(0, 3, 0.3))
			> Weatherwise.out_mult("black_bear", at_rung(1.2)),
			"a bear feeds ahead of weather too")


# ======================= 9. rain is stealth (the crossing) ==================

func _t_noise() -> void:
	claim("noise", 19)
	# NEITHER NUMBER IN THIS SECTION BELONGS TO Weatherwise.gd. The sprint
	# radius is Telegraph's and the notice radius is the dex's, and the
	# question is at which rung one falls under the other. Searched at a
	# hundredth of a rung rather than asserted near a guess.
	var far: float = Telegraph.NOISE_FAR
	var near: float = Telegraph.NOISE_NEAR
	var see := (CritterDex.DEX["whitetail"] as Dictionary).get("see", [0.0, 0.0]) as Array
	var notice := float(see[0])
	var panic := float(see[1])
	ok(far > notice, "a sprint on a clear day DOES reach a deer that has not seen you")
	ok(near < notice, "and a careful walk never did")
	ok(notice > panic, "the dex's notice radius is outside its panic radius")

	var crossed := -1.0
	var r := 0.0
	while r <= 4.0001:
		if far * Weatherwise.noise_mult(fine(r)) < notice:
			crossed = r
			break
		r += 0.01
	ok(crossed >= 0.0, "there is a rung at which a sprint stops carrying to a deer")
	ok(crossed > 1.0, "an overcast sky does not hide you")
	ok(crossed <= 2.0, "a drizzle does (crossed at rung %.2f)" % crossed)
	near_f(crossed, 1.27, 0.02,
			"and it happens a quarter of the way from the cloud into the drizzle")
	near_f(far * Weatherwise.noise_mult(at_rung(1.0)), 31.28, 0.05,
			"under cloud a sprint still rings past a deer's notice")
	near_f(far * Weatherwise.noise_mult(at_rung(3.0)), 19.72, 0.05,
			"in rain it rings well inside it")
	near_f(far * Weatherwise.noise_mult(at_rung(4.0)), 13.60, 0.05,
			"in a storm it barely rings at all")
	ok(far * Weatherwise.noise_mult(at_rung(3.0)) > panic,
			"but even a downpour never lets you walk INTO a deer unheard")
	ok(far * Weatherwise.noise_mult(at_rung(4.0)) < panic,
			"...except in the worst of a storm, which is the reward")

	# monotone, and exact at the rungs
	var last := 2.0
	var mono := true
	var rr := 0.0
	while rr <= 4.0001:
		var m := Weatherwise.noise_mult(fine(rr))
		if m > last + 0.0001:
			mono = false
		last = m
		rr += 0.05
	ok(mono, "the wetter it gets the less you are heard, without exception")
	for i in range(5):
		near_f(Weatherwise.noise_mult(at_rung(float(i))), float(Weatherwise.NOISE_MASK[i]),
				0.0001, "the mask reads its own rung exactly")
	ok(Weatherwise.noise_mult({}) == 1.0, "an empty environment is a perfect no-op")


# ========================= 10. and it costs you the woods ===================

func _t_relay() -> void:
	claim("relay", 16)
	# The price, counted against Telegraph's OWN two constants rather than
	# against anything restated here.
	var fall: float = Telegraph.RELAY_FALLOFF
	var floor_r: float = Telegraph.RELAY_MIN_RADIUS
	var far: float = Telegraph.NOISE_FAR
	ok(fall > 0.0 and fall < 1.0, "a relay hop loses radius")
	ok(floor_r > 0.0, "and the word stops somewhere")

	var clear_hops := Weatherwise.hops_left(far, fall, floor_r, at_rung(0.0))
	var storm_hops := Weatherwise.hops_left(far, fall, floor_r, at_rung(4.0))
	ok(clear_hops == 4, "on a clear day a 34 m alarm carries four hops (got %d)" % clear_hops)
	ok(storm_hops == 2, "in a storm it carries two (got %d)" % storm_hops)
	ok(clear_hops - storm_hops >= 2, "a storm halves the forest's network")
	# ...and four is not a coincidence: a clear-day alarm dies at exactly the
	# hop count Telegraph already refuses to go past, so the geometry and the
	# cap were always agreeing and a storm is the first thing to break the tie.
	ok(clear_hops == int(Telegraph.MAX_HOPS),
			"a clear-day alarm uses exactly the hops Telegraph allows and no more")
	ok(storm_hops < int(Telegraph.MAX_HOPS), "and a storm stops it well short of the cap")
	# monotone in rung, and never worse than nothing
	var last := 99
	var mono := true
	for i in range(5):
		var h := Weatherwise.hops_left(far, fall, floor_r, at_rung(float(i)))
		if h > last:
			mono = false
		last = h
		ok(h >= 0, "a hop count is never negative")
	ok(mono, "the word never travels further in worse weather")
	ok(Weatherwise.hops_left(floor_r - 1.0, fall, floor_r, at_rung(0.0)) == 0,
			"an alarm born under the floor never travels at all")
	ok(Weatherwise.hops_left(far, fall, floor_r, {}) == clear_hops,
			"an empty environment relays exactly as the game does today")
	near_f(Weatherwise.relay_mult({}), 1.0, 0.0001, "...because it masks nothing")
	ok(Weatherwise.relay_mult(at_rung(1.0)) == 1.0,
			"an overcast sky is not loud enough to break the chain")
	ok(Weatherwise.relay_mult(at_rung(4.0)) <= 0.5, "a storm is")


# ============================ 11. the other dead flag =======================

func _t_fog() -> void:
	claim("fog", 14)
	# `fog_only` is the project's second never-read weather flag: one species,
	# the Specter Moose, and it wants the soft grey band.
	var foggy: Array = []
	for k in CritterDex.DEX.keys():
		if bool(CritterDex.flag(String(k), "fog_only", false)):
			foggy.append(String(k))
	ok(foggy.size() == 1, "exactly one thing in the game is fog_only (got %d)" % foggy.size())
	ok(foggy.has("specter_moose"), "and it is the Specter Moose")
	ok(not Weatherwise.legend_allows("specter_moose", at_rung(0.0)),
			"a clear night has no specter in it")
	ok(Weatherwise.legend_allows("specter_moose", at_rung(1.0)), "an overcast one does")
	ok(Weatherwise.legend_allows("specter_moose", at_rung(2.0)), "and a drizzle")
	ok(Weatherwise.legend_allows("specter_moose", at_rung(3.0)), "and plain rain")
	ok(not Weatherwise.legend_allows("specter_moose", at_rung(4.0)),
			"but nothing haunts the inside of a thunderstorm")
	# SEARCHED: the band's edges, rather than asserted at its constants
	var first := -1.0
	var r := 0.0
	while r <= 4.0001:
		if Weatherwise.legend_allows("specter_moose", fine(r)):
			first = r
			break
		r += 0.01
	ok(first > 0.0 and first < 1.0, "the band opens between clear and overcast (%.2f)" % first)
	near_f(first, 0.80, 0.02, "four fifths of the way from a clear sky to a closed one")
	for k in ["ghost_cat", "aurora_herd", "king_snapper", "white_raven"]:
		var all_ok := true
		for i in range(5):
			if not Weatherwise.legend_allows(String(k), at_rung(float(i))):
				all_ok = false
		ok(all_ok, String(k) + " is allowed in every weather, as it always was")
	ok(Weatherwise.legend_allows("whitetail", at_rung(4.0)),
			"and a thing that is not fog_only is never refused by this door")
	ok(Weatherwise.legend_allows("specter_moose", {}) == false,
			"an empty environment is a clear sky, and clear has no specter")


# ====================== 12. the collaborator's front door ===================

func _t_telegraph() -> void:
	claim("telegraph", 18)
	# A STUB IS NOT THE COLLABORATOR. Weatherwise's noise and relay arithmetic
	# is worth nothing if Telegraph stops calling it, and Telegraph's four
	# constants can be changed by somebody else tomorrow. So: the real file.
	var src := _code_only(read_src("res://scripts/Telegraph.gd"))
	ok(src.length() > 500, "Telegraph.gd was read (%d chars of code)" % src.length())
	ok(src.contains("class_name Telegraph"), "...and it is the right file")

	ok(Telegraph.NOISE_FAR > Telegraph.NOISE_NEAR, "a sprint is louder than a walk")
	ok(Telegraph.NOISE_FAR == 34.0, "and a sprint still rings at 34 m")
	ok(Telegraph.NOISE_NEAR == 10.0, "and a walk at 10")
	ok(Telegraph.RELAY_FALLOFF == 0.62, "a relay hop still keeps 62% of its radius")
	ok(Telegraph.RELAY_MIN_RADIUS == 8.0, "and still dies under 8 m")
	ok(Telegraph.MAX_HOPS >= 4, "and four hops are still allowed")

	# ASSERT THE CALL SITE, NOT THE METHOD -- and assert it IN CONTEXT, because
	# a scan for a bare name is satisfied by the name's own definition line.
	ok(src.contains("Weatherwise.noise_mult(weather)"),
			"player_noise consults the mask")
	ok(src.contains("Weatherwise.relay_mult(weather)"),
			"the relay consults it too")
	ok(src.contains("lerpf(NOISE_NEAR, NOISE_FAR"),
			"the ring is built from the two named constants, not from literals")
	ok(src.contains("var weather: Dictionary"), "the bus carries an environment")
	var noise_fn := _func_body(src, "func player_noise")
	ok(noise_fn.length() > 60, "player_noise has a body (%d chars)" % noise_fn.length())
	ok(noise_fn.contains("Weatherwise.noise_mult"),
			"and the mask is applied INSIDE player_noise, not merely mentioned in the file")
	var ring_fn := _func_body(src, "func _ring")
	ok(ring_fn.length() > 200, "_ring has a body (%d chars)" % ring_fn.length())
	ok(ring_fn.contains("Weatherwise.relay_mult"),
			"and the relay mask is applied INSIDE _ring")

	# planted-defect fixture, built by concatenation so it cannot trip the
	# very scan it is proving
	var planted := "func " + "player_noise" + "(pos, loudness):\n\tpass\n"
	ok(_func_body(planted, "func " + "player_noise").contains("pass"),
			"the body reader works on planted text with a known answer")
	ok(_func_body(src, "func " + "no_such_function_here") == "",
			"and returns nothing for a function that is not there")


func _func_body(src: String, header: String) -> String:
	# Walks forward from a header while lines are blank or indented by tab OR
	# space -- MainMenu.gd is space-indented and a tab-only reader silently
	# scanned nothing at all (2026-09-09 18:00).
	var lines := src.split("\n")
	var out: PackedStringArray = []
	var inside := false
	for line in lines:
		var s := String(line)
		if not inside:
			if s.begins_with(header):
				inside = true
			continue
		if s.strip_edges() == "":
			out.append(s)
			continue
		if s.begins_with("\t") or s.begins_with(" "):
			out.append(s)
			continue
		break
	return "\n".join(out)


# ============================== 13. the wiring ==============================

func _t_wiring() -> void:
	claim("wiring", 20)
	# A METHOD NOBODY CALLS IS NOT A FEATURE. Every assertion above this point
	# calls Weatherwise by hand, so every assertion above this point would
	# survive the Director never having heard of it.
	var wd := _code_only(read_src("res://scripts/WildlifeDirector.gd"))
	ok(wd.length() > 2000, "WildlifeDirector.gd was read (%d chars)" % wd.length())

	var roll := _func_body(wd, "func _roll_species")
	ok(roll.length() > 200, "_roll_species has a body")
	ok(roll.contains("Weatherwise.out_mult"), "the spawn weight is multiplied by the weather")
	ok(roll.contains("CritterDex.is_awake"), "and the hour gate is still there")
	ok(roll.contains("audio_only"), "and the audio_only gate")
	ok(roll.contains("dusk"), "and the dusk term this one sits beside")

	var swarm := _func_body(wd, "func _try_swarm")
	ok(swarm.length() > 150, "_try_swarm has a body")
	ok(swarm.contains("Weatherwise.out_mult"),
			"the swarms come through their OWN door and it is wired too")

	var leg := _func_body(wd, "func _legend_gate")
	ok(leg.length() > 100, "_legend_gate has a body")
	ok(leg.contains("Weatherwise.legend_allows"), "and fog_only finally decides something")

	var proc := _func_body(wd, "func _process")
	ok(proc.length() > 200, "_process has a body")
	ok(proc.contains("weather ="), "the bus is handed the sky every tick")
	ok(proc.contains("player_noise"), "and the player's noise still goes on the wire")

	var clock := _func_body(wd, "func set_clock")
	ok(clock.length() > 150, "set_clock has a body")
	ok(clock.contains("Weatherwise.cover_urge"), "and every live animal is told to take cover")

	ok(wd.contains("func _wx"), "the Director has one place it asks the sky")
	var wx := _func_body(wd, "func _wx")
	ok(wx.contains("Weatherwise.env"), "and it builds a real environment there")
	ok(wx.contains("weather"), "off World's own weather accessor")
	# ⚠ A SCAN FOR A CALL IS SATISFIED BY A GUTTED CALL. `Weatherwise.env(0, 0,`
	# still contains "Weatherwise.env", and a Director hardcoded to report a
	# clear sky walked through the three assertions above. So: the three
	# fields it has to read out of the real Weather node, by name.
	ok(wx.contains("wx.level"), "...out of the sky's own target level")
	ok(wx.contains("_from"), "...where that sky came from")
	ok(wx.contains("_blend"), "...and how far through the change it is")

	var cr := _code_only(read_src("res://scripts/Critter.gd"))
	# ⚠ ...and a scan for a declaration is satisfied by a RENAMED declaration:
	# `var weather_cover_unused` contains "var weather_cover". Pin the value.
	ok(cr.contains("var weather_cover := 0.0"), "a Critter carries how badly it wants cover")
	ok(cr.contains("const COVER_HOLD"), "and knows when that is enough to stop working")
	var graze := _func_body(cr, "func _graze")
	# ⚠ ...and a scan for a term is satisfied by a term still mentioned further
	# down the same function. Assert the BRANCH, not the word.
	ok(graze.contains("weather_cover >= COVER_HOLD"),
			"and a grazing animal in a downpour does not wander across a hillside")
	var patrol := _func_body(cr, "func _patrol")
	ok(patrol.contains("weather_cover >= COVER_HOLD"),
			"...and neither does a ranging one, at the sky that finally reaches it")


# ============================== 14. the sources =============================

func _t_sources() -> void:
	claim("sources", 18)
	var src := _code_only(read_src("res://scripts/Weatherwise.gd"))
	ok(src.length() > 4000, "Weatherwise.gd was read (%d chars of code)" % src.length())
	ok(src.contains("class_name Weatherwise"), "...and it is the right file")

	# pure static arithmetic: the same five negatives Seasons, Slumber and
	# Garments each assert about themselves
	ok(not src.contains("RandomNumberGenerator"), "no RNG anywhere in it")
	ok(not src.contains("randf"), "and nothing rolls")
	ok(not src.contains("get_tree"), "it never reaches into the scene")
	ok(not src.contains("await"), "and it never waits for a frame")
	ok(not src.contains("extends Node"), "it is not a node")
	ok(not src.contains("func _process"), "and nothing here runs per frame")
	ok(not src.contains("Time."), "it never asks what time it is")

	# NO NEW BINDING. This is the round's dev-input assertion, made the same
	# way the last five rounds made theirs.
	ok(not src.contains("_input"), "it declares no input callback")
	ok(not src.contains("_unhandled_input"), "nor an unhandled one")
	ok(not src.contains("KEY_"), "and it claims no key")
	ok(not src.contains("InputEvent"), "and never sees an event")
	var planted := "func _" + "input(event):\n\tif event is InputEvent" + "Key:\n\t\tpass\n"
	ok(planted.contains("_" + "input"),
			"the planted fixture really does contain what the scan forbids")
	ok(_code_only(planted).contains("KEY" + "_") == false,
			"...and the stripper is not what is answering")

	# it restates nobody else's constants
	ok(not src.contains("34.0"), "the sprint radius belongs to Telegraph, not here")
	ok(not src.contains("0.62"), "and so does the relay falloff")
	ok(not src.contains("30.0"), "and a deer's notice radius belongs to the dex")


# ============================ 15. determinism ===============================

func _t_determinism() -> void:
	claim("determinism", 11)
	# A SIGNATURE THAT CANNOT SEE THE VARIABLE CANNOT SEE THE BUG. This one
	# carries the multiplier AND the urge, per species, at nine decimals and
	# at a twentieth of a rung, so any edit to any cell of either table moves
	# it and no two skies can hash alike.
	var sigs: Array = []
	for pass_i in range(2):
		var acc := ""
		var keys := CritterDex.DEX.keys()
		keys.sort()
		for k in keys:
			var key := String(k)
			var r := 0.0
			while r <= 4.0001:
				var e := at_rung(r)
				acc += "%.9f/%.9f|" % [Weatherwise.out_mult(key, e), Weatherwise.cover_urge(key, e)]
				r += 0.05
		sigs.append(acc.md5_text())
	ok(sigs[0] == sigs[1], "the same sky twice is the same answer twice")
	ok(String(sigs[0]).length() == 32, "the signature is a real digest")

	# and two different skies are two different answers
	var a := _sky_sig(at_rung(2.0))
	var b := _sky_sig(at_rung(3.0))
	var c := _sky_sig(arriving(0, 4, 0.5))
	ok(a != b, "drizzle and rain do not hash alike")
	ok(a != c, "a settled drizzle and an arriving storm at the same rung do not either")
	ok(_sky_sig(at_rung(0.0)) != _sky_sig(at_rung(1.0)), "nor clear and overcast")
	ok(_sky_sig(at_rung(3.0)) != _sky_sig(at_rung(4.0)), "nor rain and a storm")
	# a rung and its own neighbour a twentieth away differ, i.e. it is smooth
	# rather than stepped -- a stepped read would hash identically here
	ok(_sky_sig(at_rung(2.0)) != _sky_sig(Weatherwise.env(3, 2, 0.05)),
			"a sky a twentieth of a rung along is already a different world")
	ok(Weatherwise.rung(Weatherwise.env(3, 2, 0.05)) > 2.0, "...and really is at a higher rung")
	near_f(Weatherwise.rung(Weatherwise.env(3, 2, 0.05)), 2.05, 0.0001, "...by exactly a twentieth")
	ok(Weatherwise.table_problems().is_empty(), "and after all of that the tables still validate")
	ok(_sky_sig({}) == _sky_sig(at_rung(0.0)), "an empty environment is exactly a clear day")


func _sky_sig(e: Dictionary) -> String:
	var acc := ""
	var keys := CritterDex.DEX.keys()
	keys.sort()
	for k in keys:
		acc += "%.9f/%.9f|" % [Weatherwise.out_mult(String(k), e), Weatherwise.cover_urge(String(k), e)]
	acc += "%.9f/%.9f" % [Weatherwise.noise_mult(e), Weatherwise.relay_mult(e)]
	return acc.md5_text()


# ================================== run =====================================

func _init() -> void:
	print("=== WeatherwiseTests ===")
	_t_tables()
	_t_guilds()
	_t_rungs()
	_t_fairweather()
	_t_sky()
	_t_eft()
	_t_sorts()
	_t_front()
	_t_noise()
	_t_relay()
	_t_fog()
	_t_telegraph()
	_t_wiring()
	_t_sources()
	_t_determinism()

	# Every section stakes a claim about how many assertions it will make, so
	# a section deleted by a runtime error cannot hide behind the total.
	var short_sections: Array = []
	for s in _claims.keys():
		if int(_counts.get(s, 0)) < int(_claims[s]):
			short_sections.append("%s %d/%d" % [s, int(_counts.get(s, 0)), int(_claims[s])])
	if not short_sections.is_empty():
		print("  FAIL  sections short of their claim: " + ", ".join(PackedStringArray(short_sections)))
		_fail += short_sections.size()
	var total := _pass + _fail
	if total < MIN_ASSERTIONS:
		print("  FAIL  only %d assertions, floor is %d" % [total, MIN_ASSERTIONS])
		_fail += 1
	if _fail == 0:
		print("ALL GREEN — %d assertions" % total)
	else:
		print("RED — %d passed, %d FAILED (of %d)" % [_pass, _fail, total])
	quit()
