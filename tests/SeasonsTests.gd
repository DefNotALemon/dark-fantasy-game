extends SceneTree

# =============================================================================
# tests/SeasonsTests.gd -- the year, and the fact that it is a PLACE.
#
#   godot --headless --path . --script res://tests/SeasonsTests.gd
#
# `Seasons` is pure static arithmetic, so almost all of this is a loop over
# the real region roster. Six sections carry more weight than the rest:
#
#   `anchors` -- THE RECONCILIATION, and the reason this file exists. Five
#   systems each carried a private four-value array of what a season means.
#   All five are asserted element-for-element against the array in the file
#   they came from, BY NAME, so editing one turns this red and says which.
#
#   `monotone` -- the property that makes the warp a warp. `local_day` must
#   be strictly increasing in `day` at every place on the map, or the year
#   runs backwards for part of itself somewhere. Checked against the real
#   limit (1/TAU), recomputed here, not against the file's own clamp.
#
#   `boundaries` -- all four seasonal boundaries must move in the four right
#   directions in the north: summer late in, early out; winter early in, late
#   out. This is the whole physical claim of the warp and it is the thing a
#   sign error would silently get half right.
#
#   `maritime` -- DOWN EAST sits well north of the Kennebec and still has the
#   longer summer. Nobody wrote that down; it falls out of the sea term. It
#   is asserted on its own because it is the only assertion in the file that
#   fails if the sea term stops doing work INDEPENDENT of latitude.
#
#   `collaborators` -- the REAL front doors of Chronicle, Crofts and
#   Carcasses. A STUB IS NOT THE COLLABORATOR, and this file learned that the
#   expensive way: the first draft had `Crofts` and `Carcasses` call
#   `Seasons.local_index` directly, which computed their season themselves
#   and CUT THE CHRONICLE OUT OF THE CALENDAR. Their own suites caught it
#   inside a minute, because both hold a stub Chronicle that forces a season
#   and both sims had stopped listening to it. The fix was `warp_days`: the
#   warp is an offset applied to the DAY, and the season still comes back
#   through `season_at`.
#
#   `sources` -- negative source scans, THROUGH A COMMENT STRIPPER. Four
#   rounds running, a negative scan has gone red on the prose explaining it
#   -- including once in a round that had already written the warning into
#   its own header. `_code_only()` drops comment lines before any scan, which
#   retires that whole family rather than rewording one more sentence.
#
# SECTION CLAIMS: every section stakes what it is about to assert before it
# runs one, so a section killed by a runtime error shows up as a claim that
# never settled instead of quietly taking its assertions with it.
# =============================================================================

const MIN_ASSERTIONS := 150

## The region roster, as `Chronicle.REGION_ROSTER` positions plus the height
## each place actually stands at. THESE ARE THE FIXTURE. Every margin below
## is a literal set against what the model returned for these fifteen points
## when it was measured, not against a number that merely sounds demanding.
const PLACES: Array = [
	["AROOSTOOK", 3600.2, 210.0, -7000.1],
	["ALLAGASH", 1885.9, 180.0, -6520.1],
	["KATAHDIN", 2537.3, 900.0, -4960.1],
	["BAXTER", 2485.9, 430.0, -5560.1],
	["MOOSEHEAD", 1285.9, 320.0, -4120.1],
	["BIGELOW", 171.6, 760.0, -3328.1],
	["RANGELEY", -651.2, 480.0, -2872.1],
	["MAHOOSUCS", -994.1, 700.0, -1888.1],
	["PENOBSCOT R.", 3394.5, 40.0, -3160.1],
	["DOWN EAST", 4971.6, 20.0, -2800.1],
	["KENNEBEC", 1337.3, 20.0, -1432.1],
	["MIDCOAST", 1885.9, 15.0, -1120.1],
	["ACADIA", 3600.2, 120.0, -1120.1],
	["PENOBSCOT BAY", 2657.3, 10.0, -520.1],
	["CASCO BAY", 600.2, 8.0, 559.9],
]

## Measured summer and winter lengths, in days, for the places the margins
## below are stated against. Casco Bay 28.6 / 20.5 against Katahdin's
## 16.4 / 38.4 is a growing-season ratio of 1.74, which is what real Maine's
## south coast and its mountains actually run.
const MEASURED_SUMMER := {"CASCO BAY": 28.6, "KATAHDIN": 16.4, "AROOSTOOK": 17.1,
	"DOWN EAST": 24.4, "KENNEBEC": 22.0}
const MEASURED_WINTER := {"CASCO BAY": 20.5, "KATAHDIN": 38.4, "AROOSTOOK": 36.1}
const MEASURED_WARP := {"KATAHDIN": 0.079, "AROOSTOOK": 0.068, "CASCO BAY": -0.030,
	"KENNEBEC": 0.017, "DOWN EAST": -0.003}

## Days of the 96 on which the map does NOT agree with itself, measured at a
## twentieth of a day over the fifteen places above.
const MEASURED_SPLIT_DAYS := 30.2

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

func at(name: String) -> Vector3:
	for p in PLACES:
		if String(p[0]) == name:
			return Vector3(float(p[1]), float(p[2]), float(p[3]))
	push_error("no such place: " + name)
	return Vector3.ZERO


func read_src(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s


func _code_only(src: String) -> String:
	## ⚠ THE FIX FOR A TRAP THAT HAS FIRED FOUR ROUNDS RUNNING. A negative
	## source scan -- "this file never does X" -- goes red on the comment
	## explaining why it never does X. Rewording the sentence works once;
	## stripping the comments works for every scan anyone writes after this.
	##
	## Line-based and deliberately crude, in two passes: a line that is ALL
	## comment goes entirely, and a TRAILING comment is cut off the end of a
	## line that has no quote in it.
	##
	## ⚠ The second pass is not decoration. The first version of this helper
	## only dropped whole comment lines, and the mutation sweep walked
	## straight through it within the hour: switching World's feed off as
	## `pass  # _feed_local_season()` left the call's text on a line
	## beginning with `pass`, so the scan still found it and the whole
	## feature could be disabled with the suite none the wiser.
	##
	## The quote test is what keeps it honest -- a line containing a string
	## may legitimately contain a hash -- and it is why the scans below ask
	## about calls, which live at the start of their own statement.
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


## The span of consecutive days a place spends in each season, walked at a
## twentieth of a day over one whole year.
func season_days(pos: Vector3) -> Array:
	var cnt := [0, 0, 0, 0]
	for k in range(1920):
		var d := float(k) * 0.05
		cnt[Seasons.local_index(d, pos)] += 1
	return [float(cnt[0]) * 0.05, float(cnt[1]) * 0.05,
		float(cnt[2]) * 0.05, float(cnt[3]) * 0.05]


## The day a place first enters `want`, scanning forward from `from_day`.
func first_day_in(pos: Vector3, want: int, from_day: float) -> float:
	for k in range(2400):
		var d := from_day + float(k) * 0.05
		if Seasons.local_index(d, pos) == want:
			return d
	return -1.0


# =============================================================================
#  1 - the calendar
# =============================================================================

func _t_calendar() -> void:
	claim("calendar", 16)

	near_f(Seasons.DAYS_PER_SEASON, 24.0, 1e-9, "a season is 24 days")
	near_f(Seasons.DAYS_PER_YEAR, 96.0, 1e-9, "a year is 96")
	ok(Seasons.DAYS_PER_SEASON == Wind.DAYS_PER_SEASON,
		"and it is WIND's 24, not a sixth private copy of it")
	ok(Seasons.DAYS_PER_YEAR == Wind.DAYS_PER_YEAR, "same for the year")

	near_f(Seasons.phase(0.0), 0.0, 1e-9, "day zero is phase zero")
	near_f(Seasons.phase(48.0), 0.5, 1e-9, "half a year is phase a half")
	near_f(Seasons.phase(96.0), 0.0, 1e-9, "a year wraps")
	near_f(Seasons.phase(-24.0), 0.75, 1e-9, "and it wraps BACKWARDS into winter")

	## The one definition, held against the one it replaces.
	for d in [0.0, 7.0, 23.9, 24.0, 37.5, 71.0, 95.9, 300.0]:
		ok(is_equal_approx(Seasons.phase(float(d)), Wind.phase_for_day(float(d))),
			"phase agrees with Wind.phase_for_day at day %s" % d)

	ok(Seasons.index(0.0) == Seasons.SPRING, "day 0 is the first day of spring")
	ok(Seasons.index(30.0) == Seasons.SUMMER, "day 30 is summer")
	ok(Seasons.index(50.0) == Seasons.AUTUMN, "day 50 is autumn")
	ok(Seasons.index(80.0) == Seasons.WINTER, "day 80 is winter")


# =============================================================================
#  2 - THE RECONCILIATION
# =============================================================================

func _t_anchors() -> void:
	claim("anchors", 27)

	## Five private tables, each held to the file it came from. If one of
	## these goes red, somebody edited the source table and this file's copy
	## is now a lie -- the message names which file to look in.
	var pairs := [
		["Carcasses.SEASON_ROT", Seasons.ROT, Carcasses.SEASON_ROT],
		["Carcasses.SEASON_SCENT", Seasons.SCENT, Carcasses.SEASON_SCENT],
		["Crofts.SEASON_BURN", Seasons.BURN, Crofts.SEASON_BURN],
		["Crofts.SEASON_GATHER", Seasons.GATHER, Crofts.SEASON_GATHER],
		["Exposure.SEASON_BASE_C", Seasons.BASE_C, Exposure.SEASON_BASE_C],
	]
	for row in pairs:
		var nm := String(row[0])
		var mine: Array = row[1]
		var theirs: Array = row[2]
		ok(mine.size() == theirs.size(), "%s still has %d entries" % [nm, mine.size()])
		for i in range(mini(mine.size(), theirs.size())):
			near_f(float(mine[i]), float(theirs[i]), 1e-9,
				"%s[%d] matches -- edit one, edit both" % [nm, i])

	## And the meadow's four stops, held to the grass shader's own uniform
	## defaults by scanning the shader source. A sixth private reading of the
	## year is the thing this file exists to stop.
	var g := read_src("res://scripts/Grass.gd")
	ok(g.length() > 2000, "Grass.gd read back (%d bytes) -- an empty scan agrees with everything" % g.length())
	var stops := ["col_spring", "col_summer", "col_autumn", "col_winter"]
	for i in range(4):
		var key: String = stops[i]
		var c: Color = Seasons.MEADOW[i]
		var want := "uniform vec3 %s : source_color = vec3(%.2f, %.2f, %.2f);" % [
			key, c.r, c.g, c.b]
		ok(g.contains(want), "MEADOW[%d] is Grass.gd's own %s" % [i, key])


# =============================================================================
#  3 - the map
# =============================================================================

func _t_geography() -> void:
	claim("geography", 18)

	near_f(Seasons.lat_u(at("CASCO BAY")), 0.0, 0.001, "Casco Bay is the south end")
	near_f(Seasons.lat_u(at("AROOSTOOK")), 1.0, 0.001, "Aroostook is the north end")
	ok(Seasons.lat_u(at("MOOSEHEAD")) > Seasons.lat_u(at("KENNEBEC")),
		"Moosehead is north of the Kennebec")

	## Monotone in z, which is the only thing latitude has to be.
	var prev := -1.0
	for k in range(40):
		var z := 560.0 - float(k) * 200.0
		var u := Seasons.lat_u(Vector3(0.0, 0.0, z))
		ok(u >= prev - 1e-9, "latitude never goes backwards walking north (z=%.0f)" % z)
		prev = u

	near_f(Seasons.alt_u(at("KATAHDIN")), 1.0, 0.001, "Katahdin is the roof")
	near_f(Seasons.alt_u(Vector3(0, 0, 0)), 0.0, 0.001, "sea level is zero")
	near_f(Seasons.alt_u(Vector3(0, -50, 0)), 0.0, 0.001,
		"and below sea level is still zero, not negative")

	near_f(Seasons.coast_u(at("CASCO BAY")), 1.0, 0.001, "Casco Bay is the shore")
	near_f(Seasons.coast_u(at("DOWN EAST")), 1.0, 0.001, "so is Down East")
	near_f(Seasons.coast_u(at("KENNEBEC")), 0.0, 0.06,
		"the Kennebec seat at 1130 m inland is out of the sea's reach")
	ok(Seasons.coast_u(at("PENOBSCOT BAY")) > 0.5,
		"Penobscot Bay at 397 m is well inside it")
	ok(Seasons.coast_u(at("MOOSEHEAD")) < 0.001, "Moosehead is not coastal")

	## ⚠ A CONDITION THAT ONLY BITES AT ONE SCALE NEEDS A FIXTURE AT THAT
	## SCALE. Every coastal place above is either ON the polyline or seaward
	## of it, and both return 1.0 whatever `COAST_REACH_M` is -- so cutting
	## the band from 1100 m to 10 m changed nothing the suite looked at.
	## These two sit in the band's INTERIOR, which is the only place the
	## reach is the thing deciding.
	## ⚠ AND THE FIXTURE HAD TO BE MEASURED, NOT GUESSED. The first draft of
	## this block put Acadia at 0.55 off an earlier two-point sketch of the
	## coast; against the three-point polyline this file actually ships,
	## Acadia is SEAWARD and reads 1.0. Of the fifteen roster places exactly
	## one -- Midcoast -- lies strictly inside the band, so the other two
	## fixtures are synthetic points placed in it on purpose.
	near_f(Seasons.coast_u(at("MIDCOAST")), 0.1911, 0.02,
		"Midcoast is the one roster place inside the band, at its measured value")
	near_f(Seasons.coast_u(Vector3(1885.9, 10.0, -530.1)), 0.666, 0.03,
		"a point 300 m into the band reads two thirds")
	near_f(Seasons.coast_u(Vector3(1885.9, 10.0, -1030.1)), 0.2635, 0.03,
		"and one 800 m in reads a quarter -- the reach is what decides both")
	ok(Seasons.coast_u(Vector3(1885.9, 10.0, -1630.1)) < 0.001,
		"past the reach the sea is not felt at all")

	## ⚠ The open Gulf is 1.5 km from the coast POLYLINE and unmistakably at
	## sea. A bare distance test reads it as inland; the seaward cross
	## product is what gets it right, and this is the assertion that holds
	## that apart from the distance term.
	near_f(Seasons.coast_u(Vector3(3085.9, 0.0, 559.9)), 1.0, 0.001,
		"the open Gulf of Maine is SEA, not inland")


# =============================================================================
#  4 - the warp, and its monotonicity
# =============================================================================

func _t_warp() -> void:
	claim("warp", 12)

	for nm in MEASURED_WARP:
		near_f(Seasons.warp_at(at(String(nm))), float(MEASURED_WARP[nm]), 0.002,
			"%s's warp is the measured one" % nm)

	ok(Seasons.warp_at(at("AROOSTOOK")) > 0.0, "the north runs cold (positive warp)")
	ok(Seasons.warp_at(at("CASCO BAY")) < 0.0, "the south coast runs mild (negative)")
	ok(Seasons.warp_at(at("KATAHDIN")) > Seasons.warp_at(at("BAXTER")),
		"and the summit is colder than the park below it -- altitude is doing work")

	near_f(Seasons.lag_at(at("CASCO BAY")), Seasons.SEA_LAG, 1e-9,
		"the shore takes the full sea lag")
	near_f(Seasons.lag_at(at("MOOSEHEAD")), 0.0, 1e-9, "and inland takes none")

	## ⚠ Stated as a LITERAL against the real limit, recomputed here, rather
	## than against the file's own WARP_LIMIT -- a clamp compared with itself
	## is not an assertion.
	var hard_limit := 1.0 / TAU
	var worst := 0.0
	for p in PLACES:
		worst = maxf(worst, absf(Seasons.warp_at(
			Vector3(float(p[1]), float(p[2]), float(p[3])))))
	ok(worst < hard_limit,
		"no place on the map warps past the monotonicity limit (%.4f < %.4f)" % [worst, hard_limit])
	ok(worst < hard_limit * 0.6,
		"and it keeps real headroom, not a hair's breadth (%.4f)" % worst)

	## ⚠ THE CLAMP ITSELF, which nothing asserted until a mutation opened it
	## to 0.400 and the suite did not notice. The map's worst point is 0.079,
	## so `WARP_LIMIT` never BINDS at the current constants -- which makes it
	## a guard against a future constant, and the only honest way to test a
	## guard like that is to assert the guard's own value is a safe one
	## rather than to wait for a position that reaches it.
	ok(Seasons.WARP_LIMIT < hard_limit,
		"WARP_LIMIT is itself inside the monotonicity limit (%.4f < %.4f)"
		% [Seasons.WARP_LIMIT, hard_limit])
	ok(Seasons.WARP_LIMIT > worst,
		"and it is above anything the real map asks for, so it clamps nothing today")


func _t_monotone() -> void:
	claim("monotone", 15)

	## THE property that makes a warp a warp. If `local_day` ever decreases,
	## the year runs backwards at that place for part of itself -- a croft
	## would un-harvest and a carcass would un-rot.
	for p in PLACES:
		var pos := Vector3(float(p[1]), float(p[2]), float(p[3]))
		var prev := -INF
		var bad := ""
		for k in range(1920):
			var d := float(k) * 0.05
			var ld := Seasons.local_day(d, pos)
			if ld <= prev:
				bad = "day %.2f" % d
				break
			prev = ld
		ok(bad == "", "%s's local year never runs backwards (%s)" % [p[0], bad])


# =============================================================================
#  5 - the four boundaries, each moving the right way
# =============================================================================

func _t_boundaries() -> void:
	claim("boundaries", 8)

	var north := at("KATAHDIN")
	var south := at("CASCO BAY")

	## Summer: LATE in, EARLY out. Winter: EARLY in, LATE out. A sign error
	## in the warp term would get exactly half of these right, which is why
	## all four are here and not just one.
	var n_sum_in := first_day_in(north, Seasons.SUMMER, 12.0)
	var s_sum_in := first_day_in(south, Seasons.SUMMER, 12.0)
	ok(n_sum_in > s_sum_in + 2.0,
		"summer reaches Katahdin at least two days after Casco Bay (%.1f vs %.1f)" % [n_sum_in, s_sum_in])

	var n_aut_in := first_day_in(north, Seasons.AUTUMN, 36.0)
	var s_aut_in := first_day_in(south, Seasons.AUTUMN, 36.0)
	ok(n_aut_in < s_aut_in - 2.0,
		"and summer LEAVES it at least two days early (%.1f vs %.1f)" % [n_aut_in, s_aut_in])

	var n_win_in := first_day_in(north, Seasons.WINTER, 60.0)
	var s_win_in := first_day_in(south, Seasons.WINTER, 60.0)
	ok(n_win_in < s_win_in - 2.0,
		"winter arrives on the mountain at least two days early (%.1f vs %.1f)" % [n_win_in, s_win_in])

	var n_spr_in := first_day_in(north, Seasons.SPRING, 88.0)
	var s_spr_in := first_day_in(south, Seasons.SPRING, 88.0)
	ok(n_spr_in > s_spr_in + 2.0,
		"and it lets go at least two days late (%.1f vs %.1f)" % [n_spr_in, s_spr_in])

	## The warp's two fixed points. ⚠ Asserted only INLAND, and that is not
	## a convenience: `sin` is evaluated at the LAGGED phase, so at a coastal
	## place the lag moves the point the warp is measured from and midsummer
	## is no longer exactly fixed. The clean statement of the property is the
	## one with only one term in it.
	var mid := Seasons.MIDSUMMER_PHASE * Seasons.DAYS_PER_YEAR
	for nm in ["KATAHDIN", "AROOSTOOK", "MOOSEHEAD"]:
		var pos := at(String(nm))
		near_f(Seasons.lag_at(pos), 0.0, 1e-9, "%s is inland, so this is the warp alone" % nm)
		near_f(Seasons.local_day(mid, pos), mid, 0.02,
			"%s's midsummer is a FIXED POINT of the warp" % nm)

	## And a coastal one moves by its lag and essentially nothing else,
	## which is the same property stated where the second term exists.
	var cb := at("CASCO BAY")
	near_f(Seasons.local_day(mid, cb) - mid,
		-Seasons.lag_at(cb) * Seasons.DAYS_PER_YEAR, 0.45,
		"and Casco Bay's midsummer moves by its sea lag, not by its warp")


func _t_lengths() -> void:
	claim("lengths", 11)

	for nm in MEASURED_SUMMER:
		var d := season_days(at(String(nm)))
		near_f(float(d[Seasons.SUMMER]), float(MEASURED_SUMMER[nm]), 0.6,
			"%s gets its measured summer" % nm)
	for nm2 in MEASURED_WINTER:
		var d2 := season_days(at(String(nm2)))
		near_f(float(d2[Seasons.WINTER]), float(MEASURED_WINTER[nm2]), 0.6,
			"%s gets its measured winter" % nm2)

	var casco := season_days(at("CASCO BAY"))
	var kat := season_days(at("KATAHDIN"))

	## ⚠ The margin is set against the number MEASURED (1.74), not against a
	## number that sounds demanding. A literal that merely sounds demanding
	## can be satisfied by the wrong term, which is how "August takes at
	## least four times February" survived August being dialled back.
	var ratio := float(casco[Seasons.SUMMER]) / maxf(float(kat[Seasons.SUMMER]), 1e-6)
	ok(ratio > 1.55 and ratio < 1.95,
		"the growing-season ratio is real Maine's ~1.7 (%.2f)" % ratio)

	ok(float(kat[Seasons.WINTER]) > float(casco[Seasons.WINTER]) + 14.0,
		"and the mountain's winter is a fortnight longer than the harbour's (%.1f vs %.1f)"
		% [kat[Seasons.WINTER], casco[Seasons.WINTER]])

	## ⚠ THE MODEL WAS RIGHT HERE AND THE FIRST VERSION OF THIS ASSERTION
	## WAS WRONG. It claimed the shoulders keep their length exactly, on the
	## reasoning that both of spring's boundaries shift by the same
	## `s*sin(...)`. They do not: a boundary's crossing is the SOLUTION of
	## `p + s*sin(TAU*(p - 0.375)) = edge`, and the warp's slope differs at
	## p = 1.0 and p = 0.25, so the two crossings move by unequal amounts and
	## Katahdin's spring comes out ~2.9 days short of Casco Bay's.
	##
	## What is actually true -- and what the warp was built for -- is that
	## the shoulders move an order less than summer and winter do. Stated as
	## a ratio against the measured numbers, so it bites.
	var d_sum := absf(float(casco[Seasons.SUMMER]) - float(kat[Seasons.SUMMER]))
	var d_win := absf(float(casco[Seasons.WINTER]) - float(kat[Seasons.WINTER]))
	for i in [Seasons.SPRING, Seasons.AUTUMN]:
		var d_sh := absf(float(casco[i]) - float(kat[i]))
		ok(d_sh < d_sum / 3.0 and d_sh < d_win / 3.0,
			"shoulder season %d changes far less than summer or winter (%.1f vs %.1f / %.1f d)"
			% [i, d_sh, d_sum, d_win])
	ok(d_sum > 10.0 and d_win > 14.0,
		"and summer and winter are what actually move (%.1f / %.1f d)" % [d_sum, d_win])

	var total := 0.0
	for v in kat:
		total += float(v)
	near_f(total, 96.0, 0.2, "and a year on Katahdin is still a year long")


func _t_maritime() -> void:
	claim("maritime", 5)

	## THE RESULT NOBODY PUT IN BY HAND. Down East is at latitude 0.444,
	## well north of the Kennebec seat's 0.264, and still has the longer
	## summer -- because the ocean cancels its latitude. This is the only
	## assertion in the file that fails if the sea term stops doing work
	## INDEPENDENTLY of latitude, so it is stated on its own.
	var de := at("DOWN EAST")
	var ke := at("KENNEBEC")
	ok(Seasons.lat_u(de) > Seasons.lat_u(ke) + 0.1,
		"Down East is well north of the Kennebec seat (%.3f vs %.3f)"
		% [Seasons.lat_u(de), Seasons.lat_u(ke)])
	var d_de := season_days(de)
	var d_ke := season_days(ke)
	ok(float(d_de[Seasons.SUMMER]) > float(d_ke[Seasons.SUMMER]) + 1.0,
		"and it STILL gets the longer summer (%.1f vs %.1f) -- the sea, not the sun"
		% [d_de[Seasons.SUMMER], d_ke[Seasons.SUMMER]])
	ok(float(d_de[Seasons.WINTER]) < float(d_ke[Seasons.WINTER]) - 1.0,
		"and the shorter winter with it")

	## The lag is the half of the sea term that is NOT the mildness, and it
	## has to be separable: a coast with its warp zeroed still runs late.
	ok(Seasons.lag_at(de) > 0.0, "Down East carries a sea lag at all")
	var lagged := Seasons.local_day(20.0, de) - 20.0
	ok(lagged < 0.0,
		"and in spring the lag holds it BEHIND the calendar (%.2f d)" % lagged)


# =============================================================================
#  6 - the map disagreeing with itself
# =============================================================================

func _t_split() -> void:
	claim("split", 6)

	var split := 0
	var worst_pair := ""
	for k in range(1920):
		var d := float(k) * 0.05
		var seen := {}
		for p in PLACES:
			seen[Seasons.local_index(d, Vector3(float(p[1]), float(p[2]), float(p[3])))] = true
		if seen.size() > 1:
			split += 1
	var days := float(split) * 0.05
	near_f(days, MEASURED_SPLIT_DAYS, 2.0,
		"the map is not unanimous on the measured number of days")
	ok(days > 20.0, "which is a fifth of the year at the very least (%.1f)" % days)
	ok(days < 55.0, "and not so much that a season means nothing (%.1f)" % days)

	## A named, concrete instance, because a count can be right for the
	## wrong reason.
	ok(Seasons.local_index(66.0, at("KATAHDIN")) == Seasons.WINTER,
		"on day 66 it is winter on Katahdin")
	ok(Seasons.local_index(66.0, at("CASCO BAY")) == Seasons.AUTUMN,
		"and on the same day it is still autumn in Casco Bay")
	ok(not Seasons.agrees(66.0, at("KATAHDIN"), at("CASCO BAY")),
		"and `agrees` says so")


# =============================================================================
#  7 - reading an anchor set continuously
# =============================================================================

func _t_sample() -> void:
	claim("sample", 17)

	## ⚠ THE PROPERTY THAT LETS FIVE TUNED FILES KEEP THEIR NUMBERS: read
	## anywhere in the held part of a season, `sample` returns the season's
	## own anchor EXACTLY. Without this the continuous curve would be a
	## silent retune of rot, burn, gather and the air temperature at once.
	for s in 4:
		for frac in [0.02, 0.25, 0.50, 0.54]:
			var p := (float(s) + float(frac)) / 4.0
			near_f(Seasons.sample(p, Seasons.ROT), float(Seasons.ROT[s]), 1e-9,
				"mid-season %d at %.2f is exactly the old constant" % [s, frac])

	## And the turn is a turn: strictly between, and monotone through it.
	var a := float(Seasons.ROT[1])
	var b := float(Seasons.ROT[2])
	var mid := Seasons.sample((1.0 + 0.8) / 4.0, Seasons.ROT)
	ok((mid - a) * (mid - b) < 0.0, "at the turn the value is strictly between the two anchors")

	var last := Seasons.sample((1.0 + 0.55) / 4.0, Seasons.ROT)
	var fell := true
	for k in range(1, 46):
		var p2 := (1.0 + 0.55 + float(k) * 0.01) / 4.0
		var v := Seasons.sample(p2, Seasons.ROT)
		if v > last + 1e-9:
			fell = false
		last = v
	ok(fell, "and summer's rot falls monotonically into autumn's, never jitters")

	near_f(Seasons.turn_f((1.0 + 0.2) / 4.0), 0.0, 1e-9, "the hold is flat")
	near_f(Seasons.turn_f((1.0 + 0.999) / 4.0), 1.0, 0.01, "and the turn completes")

	## The named readers all agree with `sample` on the same phase -- they
	## are conveniences, not second opinions.
	var pos := at("MOOSEHEAD")
	var lp := Seasons.local_phase(40.0, pos)
	near_f(Seasons.rot_at(40.0, pos), Seasons.sample(lp, Seasons.ROT), 1e-9, "rot_at")
	near_f(Seasons.burn_at(40.0, pos), Seasons.sample(lp, Seasons.BURN), 1e-9, "burn_at")
	near_f(Seasons.gather_at(40.0, pos), Seasons.sample(lp, Seasons.GATHER), 1e-9, "gather_at")
	near_f(Seasons.base_c_at(40.0, pos), Seasons.sample(lp, Seasons.BASE_C), 1e-9, "base_c_at")
	near_f(Seasons.scent_at(40.0, pos), Seasons.sample(lp, Seasons.SCENT), 1e-9, "scent_at")

# =============================================================================
#  8 - snow, and the meadow
# =============================================================================

func _t_ground() -> void:
	claim("ground", 10)

	## The grass shader opens its snow term at phase 0.74. Anything asking
	## "is there snow here" has to answer on the same window, or the number
	## and the ground disagree.
	near_f(Seasons.SNOW_IN, 0.74, 1e-9, "snow opens where Grass.gd opens it")
	near_f(Seasons.SNOW_OUT, 0.97, 1e-9, "and closes where it closes")

	var kat := at("KATAHDIN")
	var casco := at("CASCO BAY")
	near_f(Seasons.snow_cover(71.0, kat), 0.306, 0.02,
		"on day 71 Katahdin is under its measured snow")
	near_f(Seasons.snow_cover(71.0, casco), 0.0, 1e-6,
		"and Casco Bay has none at all -- the same day, the same world")
	ok(Seasons.snow_cover(84.0, casco) > 0.5,
		"the harbour does get its winter, a fortnight later (%.2f)"
		% Seasons.snow_cover(84.0, casco))
	near_f(Seasons.snow_cover(30.0, kat), 0.0, 1e-6, "and nowhere is snowed on in summer")

	## ⚠ THE THAW, which no fixture reached until a mutation deleted the
	## closing term and nothing moved. `SNOW_OUT` is phase 0.97 -- past day
	## 93 -- so every assertion above sits in the OPEN half of the window
	## and says nothing about whether the snow ever goes.
	ok(Seasons.snow_cover(95.5, casco) < 0.35,
		"the snow is going by the end of the year, before the calendar turns (%.2f)"
		% Seasons.snow_cover(95.5, casco))
	ok(Seasons.snow_cover(95.5, casco) < Seasons.snow_cover(88.0, casco),
		"and it is on its way DOWN, not still climbing")
	near_f(Seasons.snow_cover(0.2, casco), 0.0, 0.05,
		"and the first days of spring are bare")

	## The meadow turns on the same curve, so colour and number never drift.
	var green: Color = Seasons.MEADOW[Seasons.SUMMER]
	near_f(Seasons.meadow_at(30.0, casco).g, green.g, 0.02,
		"a summer meadow is the summer green")
	var winter_col: Color = Seasons.MEADOW[Seasons.WINTER]
	near_f(Seasons.meadow_at(84.0, casco).r, winter_col.r, 0.05,
		"and a winter one has turned")
	ok(Seasons.meadow_at(66.0, kat) != Seasons.meadow_at(66.0, casco),
		"on day 66 the mountain and the harbour are not the same colour")

	## ⚠ Asked at a moment when the thing is actually happening: mid-turn,
	## not after it has completed, where both ends would look the same.
	var turning := Seasons.meadow_at(45.0, casco)
	ok(turning != Seasons.MEADOW[Seasons.SUMMER] and turning != Seasons.MEADOW[Seasons.AUTUMN],
		"and mid-turn the meadow is between its two stops, not snapped to one")


# =============================================================================
#  9 - THE REAL FRONT DOORS
# =============================================================================

func _t_collaborators() -> void:
	claim("collaborators", 24)

	## --- Chronicle. A STATIC, and the calendar's actual owner. If this
	## drifts from `Seasons.index`, every warp below is measured off a
	## different year than the story is running on.
	for d in [0.0, 13.0, 24.0, 47.9, 55.0, 71.0, 95.0, 240.0]:
		ok(Chronicle.season_at(float(d)) == Seasons.index(float(d)),
			"Chronicle and Seasons agree on the calendar at day %s" % d)

	## --- Crofts. The REAL method, on a real instance, with no Chronicle
	## bound so `season_at` runs its own fallback -- which is the path a
	## headless world and a fresh save both take.
	var cr := Crofts.new()
	var south_c := {"pos": Vector2(600.2, 559.9)}
	var north_c := {"pos": Vector2(3600.2, -7000.1)}

	## ⚠ THE DEFECT THIS SECTION EXISTS FOR. The first draft called
	## `Seasons.local_index` here and cut the Chronicle out of the calendar.
	## `season_here` must route through `season_at`, so a season the
	## Chronicle forces is the season the croft gets.
	var src_c := _code_only(read_src("res://scripts/Crofts.gd"))
	ok(src_c.length() > 4000, "Crofts.gd read back as code (%d bytes)" % src_c.length())
	ok(src_c.contains("season_at(t + Seasons.warp_days("),
		"Crofts.season_here goes through season_at, NOT straight to local_index")
	ok(not src_c.contains("return Seasons.local_index("),
		"and it never answers with local_index directly")

	## ⚠ A METHOD NOBODY CALLS IS NOT A FEATURE. Every assertion in this
	## section calls `season_here` by hand, so the suite proved the method
	## worked and said nothing about whether the SIM uses it -- a mutation
	## putting the old shared `season` back into the step loop survived the
	## whole first sweep. This is the call site, asserted.
	ok(src_c.contains("_step_croft(c as Dictionary, t, sky, season_here(t, c as Dictionary))"),
		"and the croft step loop asks per croft, not once for the whole map")

	## ⚠ The day is SEARCHED FOR, not hardcoded. A croft's `pos` is a
	## Vector2 and the sim never learns its height, so a croft gets latitude
	## and the sea but no altitude -- which makes day 66 (chosen against
	## Katahdin's 900 m) a day these two still agree on. Finding the day
	## the claim is about is the honest version of the assertion, and it
	## fails loudly if no such day exists.
	var boundary := -1.0
	var s_south := -1
	var s_north := -1
	for k in range(960):
		var d := float(k) * 0.1
		var a := cr.season_here(d, south_c)
		var b := cr.season_here(d, north_c)
		if a != b:
			boundary = d
			s_south = a
			s_north = b
			break
	ok(boundary >= 0.0,
		"there IS a day a northern croft and a southern one disagree (day %.1f)" % boundary)
	ok(s_south != s_north,
		"and on it they are in different seasons (%d vs %d)" % [s_south, s_north])
	ok(s_north > s_south or (s_south == 3 and s_north == 0),
		"with the north the further on of the two (%d vs %d)" % [s_north, s_south])

	## AND THAT IS THE WOODPILE, which Crofts calls the whole point of
	## itself. ⚠ Searched for the SPECIFIC pairing the claim is about --
	## the north already in winter while the south is still in autumn --
	## because "the north burns more" is only true of some season pairs
	## (`SEASON_BURN` runs 1.00 / 0.55 / 1.15 / 1.60, so a northern spring
	## against a southern winter burns LESS, correctly).
	var wday := -1.0
	for k2 in range(960):
		var d2 := float(k2) * 0.1
		if cr.season_here(d2, north_c) == Seasons.WINTER \
				and cr.season_here(d2, south_c) == Seasons.AUTUMN:
			wday = d2
			break
	ok(wday >= 0.0,
		"there is a stretch where the north is in winter and the south still in autumn (day %.1f)" % wday)
	if wday >= 0.0:
		var burn_n := Crofts.burn_per_hour("lit", cr.season_here(wday, north_c))
		var burn_s := Crofts.burn_per_hour("lit", cr.season_here(wday, south_c))
		ok(burn_n > burn_s,
			"so the northern hearth burns the WINTER rate while the southern one does not (%.3f vs %.3f)"
			% [burn_n, burn_s])
		var gath_n := Crofts.gather_per_hour("wood", cr.season_here(wday, north_c))
		var gath_s := Crofts.gather_per_hour("wood", cr.season_here(wday, south_c))
		ok(gath_n < gath_s,
			"and gathers LESS while it does it -- the same habits, a different pile (%.3f vs %.3f)"
			% [gath_n, gath_s])
	else:
		ok(false, "(burn comparison skipped: no such day)")
		ok(false, "(gather comparison skipped: no such day)")

	## Crofts' own real front doors, which somebody can delete tomorrow.
	ok(Crofts.crop_at(30.0, Seasons.SUMMER, "croft") > Crofts.crop_at(30.0, Seasons.WINTER, "croft"),
		"Crofts.crop_at still gives summer more standing crop than winter")
	near_f(Crofts.crop_at(30.0, Seasons.SPRING, "shieling"), 0.0, 1e-9,
		"and a shieling still grows nothing")
	ok(Crofts.daylight(Seasons.WINTER).y - Crofts.daylight(Seasons.WINTER).x
		< Crofts.daylight(Seasons.SUMMER).y - Crofts.daylight(Seasons.SUMMER).x,
		"Crofts.daylight still makes a winter day the short one")
	cr.free()

	## --- Carcasses. Same shape, and this one knows its own height.
	var ca := Carcasses.new()
	var src_a := _code_only(read_src("res://scripts/Carcasses.gd"))
	ok(src_a.contains("season_at(t + Seasons.warp_days("),
		"Carcasses.season_here goes through season_at too")
	ok(src_a.contains("_step_rec(rec, t, hour, sky, season_here(t, rec))"),
		"and its step loop asks per carcass -- the same call site, same hole")

	var hot := {"at": Vector3(600.2, 8.0, 559.9)}
	var cold := {"at": Vector3(2537.3, 900.0, -4960.1)}
	var s_hot := ca.season_here(boundary, hot)
	var s_cold := ca.season_here(boundary, cold)
	ok(s_hot != s_cold,
		"a body on the coast and a body on the mountain rot in different seasons on day 66")
	var rot_hot := Carcasses.rot_per_step(50.0, s_hot)
	var rot_cold := Carcasses.rot_per_step(50.0, s_cold)
	ok(rot_hot > rot_cold,
		"and the mountain one KEEPS while the coastal one goes off (%.4f vs %.4f kg/step)"
		% [rot_hot, rot_cold])

	## ⚠ The altitude term has to be what did that, not the latitude alone.
	## Same latitude, different height: the mountain still wins.
	var v_low := Vector3(2537.3, 0.0, -4960.1)
	var v_high := Vector3(2537.3, 900.0, -4960.1)
	ok(Seasons.warp_at(v_high) > Seasons.warp_at(v_low) + 0.02,
		"altitude alone shortens the year at a fixed latitude (%.3f vs %.3f)"
		% [Seasons.warp_at(v_high), Seasons.warp_at(v_low)])
	ok(Seasons.local_phase(63.5, v_high) > Seasons.local_phase(63.5, v_low),
		"so the valley floor below Katahdin is not living the summit's year")
	## ⚠ No `or` escape hatch here: `season_here` must return EXACTLY what
	## the calendar returns at the warped day, at both heights. An `or`
	## between two clauses either of which can carry the assertion is how a
	## test passes through the door you were not watching.
	for v in [v_low, v_high]:
		var want := Seasons.index(63.5 + Seasons.warp_days(63.5, v))
		ok(ca.season_here(63.5, {"at": v}) == want,
			"Carcasses reads that height through its own front door (y=%.0f)" % v.y)

	ok(Carcasses.scent(0, Seasons.SUMMER) > Carcasses.scent(0, Seasons.WINTER),
		"Carcasses.scent still carries further in summer than in winter")
	ca.free()

	## --- Exposure. The season term is this file's BASE_C, read by the air.
	var e_sum := {"season": Seasons.SUMMER, "hour": 12.0, "y": 60.0}
	var e_win := {"season": Seasons.WINTER, "hour": 12.0, "y": 60.0}
	ok(Exposure.ambient_c(e_sum) > Exposure.ambient_c(e_win) + 15.0,
		"Exposure's noon is at least fifteen degrees warmer in summer than winter (%.1f vs %.1f)"
		% [Exposure.ambient_c(e_sum), Exposure.ambient_c(e_win)])
	near_f(Exposure.SEASON_BASE_C[Seasons.WINTER], -4.0, 1e-9,
		"and its winter base is still the number BASE_C mirrors")


# =============================================================================
#  10 - the wiring in World.gd
# =============================================================================

func _t_wiring() -> void:
	claim("wiring", 9)

	var w := _code_only(read_src("res://scripts/World.gd"))
	ok(w.length() > 20000, "World.gd read back as code (%d bytes)" % w.length())

	ok(w.contains("func _feed_local_season"), "the local-season feed is DEFINED")
	ok(w.contains("_feed_local_season()"), "and CALLED")
	ok(w.contains("Seasons.local_phase(_daynight.day, _player.global_position)"),
		"and what it publishes is the phase at the PLAYER'S position")
	ok(w.contains("global_shader_parameter_set(\"season_phase\""),
		"it reaches the shaders' own global")
	ok(w.contains("Wind.phase = p"),
		"and Wind.phase with it, which is what TreeImpostor reads")

	## ⚠ The bug this replaced: the season was published ONLY at the midnight
	## rollover and on load, so sleeping -- which moves the day without
	## crossing one -- left every foliage shader a day or more behind. The
	## feed is in `_process`, so how the day moved stopped mattering.
	var proc_i := w.find("func _process")
	var feed_i := w.find("_feed_local_season()")
	var next_func := w.find("\nfunc ", proc_i + 1)
	ok(proc_i >= 0 and feed_i > proc_i and (next_func < 0 or feed_i < next_func),
		"the feed is called from inside _process, not from a rollover branch")

	## A planted-defect fixture, built by CONCATENATION so it cannot trip the
	## scan it is proving.
	var planted := "func " + "_feed_local_season" + "() -> void:\n\tpass\n"
	ok(_code_only(planted).contains("func " + "_feed_local_season"),
		"the scanner finds a definition in planted text")
	var commented := "# func " + "_feed_local_season" + "() -> void:\n"
	ok(not _code_only(commented).contains("func " + "_feed_local_season"),
		"and the comment stripper hides one that is only mentioned in prose")


# =============================================================================
#  11 - what this file refuses to be
# =============================================================================

func _t_sources() -> void:
	claim("sources", 14)

	var raw := read_src("res://scripts/Seasons.gd")
	ok(raw.length() > 8000, "Seasons.gd read back (%d bytes)" % raw.length())
	var src := _code_only(raw)
	ok(src.length() > 2000, "and its code alone is %d bytes" % src.length())
	ok(src.length() < raw.length(),
		"the stripper actually removed something (%d -> %d)" % [raw.length(), src.length()])

	## ⚠ EVERY ONE OF THESE IS A NEGATIVE SCAN, and four rounds running a
	## negative scan has gone red on the comment explaining it. They run over
	## `_code_only`, so the prose in this file's header is free to say
	## "no RNG" and "no get_tree" in as many words.
	ok(not src.contains("RandomNumberGenerator"),
		"Seasons is deterministic -- no RNG in the code")
	ok(not src.contains("randf") and not src.contains("randi"),
		"and no loose random call either")
	ok(not src.contains("get_tree"), "it never reaches into the scene tree")
	ok(not src.contains("await"), "it never awaits")
	ok(not src.contains("_process("), "it has no frame hook")
	ok(not src.contains("Time.get_"), "and it never asks the wall clock what time it is")

	## Prove the scanner can SEE a defect before trusting it on the truth.
	var planted_rng := "var r = RandomNumber" + "Generator.new()"
	ok(_code_only(planted_rng).contains("RandomNumberGenerator"),
		"the scanner finds an RNG in planted code")
	var planted_comment := "## this file has no RandomNumber" + "Generator in it"
	ok(not _code_only(planted_comment).contains("RandomNumberGenerator"),
		"and does NOT find one in a comment saying so -- the whole point")

	## No binding, no event hook. The one affordance is read-only.
	ok(not src.contains("func _input") and not src.contains("func _unhandled_input"),
		"Seasons claims no input callback")
	ok(not src.contains("KEY_"), "and no key at all")
	var ro: Dictionary = Seasons.readout(66.0, at("KATAHDIN"))
	ok(String(ro.get("local", "")) == "Winter" and String(ro.get("calendar", "")) == "Autumn",
		"and readout() reports the local season differing from the calendar one")


func _t_determinism() -> void:
	claim("determinism", 6)

	## ⚠ A SIGNATURE THAT CANNOT SEE THE VARIABLE CANNOT SEE THE BUG. This
	## one carries the local phase itself, at full precision, for every
	## place -- so two runs that differ anywhere in the geography differ
	## here, which a season INDEX would have rounded away.
	var sig := ""
	for p in PLACES:
		var pos := Vector3(float(p[1]), float(p[2]), float(p[3]))
		for d in [0.0, 24.0, 48.0, 66.0, 84.0]:
			sig += "%.9f|" % Seasons.local_phase(float(d), pos)
	var sig2 := ""
	for p2 in PLACES:
		var pos2 := Vector3(float(p2[1]), float(p2[2]), float(p2[3]))
		for d2 in [0.0, 24.0, 48.0, 66.0, 84.0]:
			sig2 += "%.9f|" % Seasons.local_phase(float(d2), pos2)
	ok(sig == sig2, "the same question twice gives the same answer, to nine places")
	ok(sig.length() > 600, "and the signature is long enough to carry the whole map")

	## Two places that SHOULD differ must not hash the same -- the check
	## that the signature is sensitive to what it claims to cover.
	var a := "%.9f" % Seasons.local_phase(66.0, at("KATAHDIN"))
	var b := "%.9f" % Seasons.local_phase(66.0, at("CASCO BAY"))
	ok(a != b, "and two different places do not produce the same phase")

	## A year later is the same point in the year.
	for nm in ["KATAHDIN", "DOWN EAST"]:
		near_f(Seasons.local_phase(30.0, at(String(nm))),
			Seasons.local_phase(30.0 + 96.0, at(String(nm))), 1e-9,
			"%s's year repeats exactly" % nm)
	near_f(Seasons.local_phase(30.0, at("KATAHDIN")),
		Seasons.local_phase(30.0 + 960.0, at("KATAHDIN")), 1e-6,
		"and still does ten years on")


# =============================================================================

func _init() -> void:
	_t_calendar()
	_t_anchors()
	_t_geography()
	_t_warp()
	_t_monotone()
	_t_boundaries()
	_t_lengths()
	_t_maritime()
	_t_split()
	_t_sample()
	_t_ground()
	_t_collaborators()
	_t_wiring()
	_t_sources()
	_t_determinism()

	var short: Array = []
	for s in _claims:
		if int(_counts.get(s, 0)) < int(_claims[s]):
			short.append("%s %d/%d" % [s, int(_counts.get(s, 0)), int(_claims[s])])
	if not short.is_empty():
		_fail += 1
		print("  FAIL  [claims] sections that never finished: %s" % ", ".join(PackedStringArray(short)))
	if _pass + _fail < MIN_ASSERTIONS:
		_fail += 1
		print("  FAIL  [floor] only %d assertions ran, floor is %d" % [_pass + _fail, MIN_ASSERTIONS])

	if _fail == 0:
		print("ALL GREEN -- %d assertions" % _pass)
	else:
		print("%d passed, %d FAILED" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
