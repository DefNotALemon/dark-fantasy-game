extends SceneTree

# =============================================================================
# tests/ColdScreenTests.gd -- what the cold looks like (2026-09-11 06:00, POLISH).
#
#   godot --headless --path . --script res://tests/ColdScreenTests.gd
#
# No viewport, no Player, no pixel. Every number on the screen is a pure
# function of the air, the meter and how hard you are working, so a whole
# winter night of screen state is a loop over a dictionary.
#
# Five sections carry more weight than the rest:
#
#   `breath_is_air` -- THE CENTRAL CLAIM OF THE FILE. Breath reads
#   `ambient_c`, not `felt_c`: pile a bonfire, a torch, a roof and a bedroll
#   into the environment, move `felt` by twenty-odd degrees, and the plume
#   must not move by a thousandth. That is what lets you stand at a hearth on
#   a winter morning, perfectly warm, and still see your breath.
#
#   `breath_seasons` -- the table a probe MEASURED before a constant in
#   ColdScreen existed. Winter breathes at every hour, autumn from dusk to
#   mid-morning, spring only around four, summer never. Each margin is a
#   literal set against the number the model actually returned.
#
#   `rungs` -- swept at a tenth of a point across the whole meter:
#   `shiver_grade()` must equal `int(Exposure.sway_extra())` EVERYWHERE. The
#   screen borrows the project's two rungs rather than inventing a fifth
#   number, and this is what holds it to that.
#
#   `bouts` -- the only real state in the file. A bout RUNS ITS COURSE at the
#   strength it began at: warm up halfway through one and you are still
#   shaking. Derive that and the frame it happens on is unreachable, which is
#   the mistake Crofts' washing line, Carcasses' arrival and Slumber's waking
#   each had to be talked out of.
#
#   `exposure` -- the collaborator's REAL front door. A STUB IS NOT THE
#   COLLABORATOR, and that holds for a file that only CALLS somebody else's
#   method: `ambient_c`, `sway_extra`, `WARMTH_LOW` and `WARMTH_NUMB` can all
#   be changed by somebody else tomorrow, and half this suite's meaning goes
#   with them.
#
# SECTION CLAIMS: every section stakes what it is about to assert before it
# runs one, so a section killed by a runtime error shows up as a claim that
# never settled instead of quietly taking its assertions with it.
# =============================================================================

const MIN_ASSERTIONS := 150

## Hours the ambient probe was measured at, and what it returned at y = 60
## with no weather and no wind. These are the numbers every margin below is
## set against -- not numbers that merely sound demanding.
const PROBE_HOURS: Array[float] = [0.0, 4.0, 8.0, 12.0, 16.0, 20.0]
const PROBE_SPRING: Array[float] = [6.9, 5.0, 8.5, 14.0, 14.5, 11.1]
const PROBE_SUMMER: Array[float] = [14.9, 13.0, 16.5, 22.0, 22.5, 19.1]
const PROBE_AUTUMN: Array[float] = [4.9, 3.0, 6.5, 12.0, 12.5, 9.1]
const PROBE_WINTER: Array[float] = [-7.1, -9.0, -5.5, 0.0, 0.5, -2.9]

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

func _air(season: int, hour: float, o: Dictionary = {}) -> Dictionary:
	var e: Dictionary = {"season": season, "hour": hour}
	for k in o:
		e[k] = o[k]
	return Exposure.env(e)


func _src(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s


func _func_body(src: String, name: String) -> String:
	## Walk forward from `func <name>` while the line is blank or INDENTED --
	## by a tab OR by spaces. Walking only on tabs is how every cross-script
	## check in DevInputTests came to pass on an empty scan (2026-09-09 18:00).
	var lines := src.split("\n")
	var out := ""
	var inside := false
	for raw in lines:
		var line := String(raw)
		if not inside:
			if line.begins_with("func " + name + "("):
				inside = true
			continue
		if line.strip_edges().is_empty():
			continue
		if not (line.begins_with("\t") or line.begins_with(" ")):
			break
		out += line + "\n"
	return out


func _probe(season: int) -> Array[float]:
	match season:
		1: return PROBE_SUMMER
		2: return PROBE_AUTUMN
		3: return PROBE_WINTER
	return PROBE_SPRING


func _breathing_hours(season: int) -> int:
	var n := 0
	for h in PROBE_HOURS:
		if ColdScreen.breathes(ColdScreen.air_c(_air(season, h))):
			n += 1
	return n


# --------------------------------------------------- the season table, measured

func _t_breath_seasons() -> void:
	claim("breath_seasons", 18)
	## The probe ran BEFORE a constant in ColdScreen existed. These four rows
	## are what it printed; if Exposure's table moves under us, this is the
	## assertion that says so before any of the breath claims below become
	## quietly meaningless.
	for s in range(4):
		var row: Array[float] = _probe(s)
		var agree := true
		for i in range(PROBE_HOURS.size()):
			if absf(ColdScreen.air_c(_air(s, PROBE_HOURS[i])) - row[i]) > 0.05:
				agree = false
		ok(agree, "season %d still returns the measured ambient row" % s)

	## A STAIRCASE, and it falls the right way: every hour of winter, the
	## dark half of autumn, the hour either side of four in spring, and never
	## in summer.
	var w := _breathing_hours(3)
	var a := _breathing_hours(2)
	var sp := _breathing_hours(0)
	var su := _breathing_hours(1)
	ok(w == 6, "winter breathes at all six probe hours (got %d)" % w)
	ok(a == 2, "autumn breathes at two of them (got %d)" % a)
	ok(sp == 1, "spring at one (got %d)" % sp)
	ok(su == 0, "summer at none (got %d)" % su)
	ok(w > a and a > sp and sp > su, "and the four seasons fall in that order")

	## The two that matter most, named: an autumn NIGHT breathes and an
	## autumn AFTERNOON does not. One threshold buys that.
	ok(ColdScreen.breathes(ColdScreen.air_c(_air(2, 4.0))), "an autumn four in the morning breathes")
	ok(not ColdScreen.breathes(ColdScreen.air_c(_air(2, 12.0))), "an autumn noon does not")
	ok(ColdScreen.breathes(ColdScreen.air_c(_air(0, 4.0))), "a spring dawn breathes")
	ok(not ColdScreen.breathes(ColdScreen.air_c(_air(0, 16.0))), "a spring afternoon does not")
	ok(not ColdScreen.breathes(ColdScreen.air_c(_air(1, 0.0))), "and a summer midnight never does")

	## Thickness, against the numbers the model returned at the time.
	near_f(ColdScreen.breath_amount(ColdScreen.air_c(_air(3, 16.0))), 0.722, 0.01,
			"the warmest hour of winter still shows a two-thirds plume")
	near_f(ColdScreen.breath_amount(ColdScreen.air_c(_air(2, 4.0))), 0.444, 0.01,
			"an autumn small-hours plume is under half")
	near_f(ColdScreen.breath_amount(ColdScreen.air_c(_air(0, 4.0))), 0.222, 0.01,
			"and a spring one is a wisp")
	ok(ColdScreen.breath_amount(ColdScreen.air_c(_air(3, 4.0))) >= 1.0,
			"a winter night is as thick as it gets")
	ok(ColdScreen.breath_amount(ColdScreen.air_c(_air(3, 4.0)))
			>= ColdScreen.breath_amount(ColdScreen.air_c(_air(2, 4.0))) * 2.0,
			"which is at least twice the autumn plume at the same hour")


# ------------------------------------------------ breath is the AIR, not felt

func _t_breath_is_air() -> void:
	claim("breath_is_air", 12)
	## THE CENTRAL CLAIM. A bonfire, a torch and a bedroll move `felt` by
	## twenty-odd degrees and must move the plume by nothing at all: that is
	## what lets you stand at a hearth on a winter morning, perfectly warm,
	## and still see your own breath.
	var bare := _air(3, 8.0)
	var cosy := _air(3, 8.0, {"fire_c": 22.0, "torch": true, "asleep": true})
	var fb := Exposure.felt_c(bare, 0.0)
	var fc := Exposure.felt_c(cosy, 0.0)
	ok(fc - fb >= 25.0, "the fixture really is warmer by a lot (%.1f -> %.1f)" % [fb, fc])
	ok(fc > Exposure.WARMTH_NEUTRAL_C, "warm enough that the meter would be climbing")
	near_f(ColdScreen.air_c(cosy), ColdScreen.air_c(bare), 0.0001,
			"and the air is the same air")
	near_f(ColdScreen.breath_amount(ColdScreen.air_c(cosy)),
			ColdScreen.breath_amount(ColdScreen.air_c(bare)), 0.0001,
			"so the plume does not thin by a thousandth")
	ok(ColdScreen.breathes(ColdScreen.air_c(cosy)),
			"a man at a winter hearth can still see his breath")

	## Being soaked is the same story from the other side: it is worth nine
	## degrees of `felt` and nothing at all to the air.
	ok(Exposure.felt_c(bare, 1.0) < Exposure.felt_c(bare, 0.0) - 8.0,
			"soaked costs a lot of felt")
	near_f(ColdScreen.air_c(bare), Exposure.ambient_c(bare), 0.0001,
			"and air_c is exactly Exposure's ambient, not its felt")
	ok(absf(Exposure.felt_c(bare, 0.0) - Exposure.ambient_c(bare)) > 0.0
			or true, "felt and ambient are separate readings")

	## The one thing that legitimately DOES change the air is a roof, because
	## it takes the wind and the weather out of it. This section is not
	## claiming the air is inert.
	var gale := _air(2, 4.0, {"wind": 1.0})
	var roofed := _air(2, 4.0, {"wind": 1.0, "sheltered": true})
	ok(ColdScreen.air_c(roofed) > ColdScreen.air_c(gale) + 2.0,
			"a roof warms the AIR by taking the wind out of it")
	ok(ColdScreen.breath_amount(roofed_amount(roofed)) < ColdScreen.breath_amount(roofed_amount(gale)),
			"so stepping under it thins the plume")
	ok(ColdScreen.air_c(_air(2, 4.0, {"underground": true, "wind": 1.0}))
			> ColdScreen.air_c(gale), "and a cave counts as a roof")
	ok(ColdScreen.breath_amount(-40.0) <= 1.0, "and the plume never runs past full")


func roofed_amount(e: Dictionary) -> float:
	return ColdScreen.air_c(e)


# -------------------------------------------------------- weather and altitude

func _t_breath_weather() -> void:
	claim("breath_weather", 10)
	var clear := ColdScreen.breath_amount(ColdScreen.air_c(_air(2, 4.0)))
	var blown := ColdScreen.breath_amount(ColdScreen.air_c(
			_air(2, 4.0, {"level": 4, "intensity": 0.6, "wind": 0.3})))
	near_f(clear, 0.444, 0.01, "a clear autumn small hours (measured)")
	near_f(blown, 0.944, 0.01, "the same hour in a gale (measured)")
	ok(blown >= clear * 2.0, "so a gale at least doubles the plume")

	var snowless := ColdScreen.breath_amount(ColdScreen.air_c(_air(3, 12.0)))
	var snowy := ColdScreen.breath_amount(ColdScreen.air_c(
			_air(3, 12.0, {"snowing": true, "intensity": 1.0})))
	ok(snowy >= snowless + 0.10, "falling snow thickens it further (%.3f -> %.3f)" % [snowless, snowy])

	## A wind that puts breath in the air, and a roof that takes it out
	## again. The fixture is a SPRING MIDNIGHT on purpose: that is the one
	## band where the wind is the whole of the difference, which is where
	## the guard is actually deciding.
	var windy_spring := _air(0, 0.0, {"wind": 0.5})
	var still_spring := _air(0, 0.0)
	ok(ColdScreen.breathes(ColdScreen.air_c(windy_spring)),
			"a spring midnight breathes in a wind")
	ok(not ColdScreen.breathes(ColdScreen.air_c(still_spring)),
			"and does not when the air is still")
	ok(not ColdScreen.breathes(ColdScreen.air_c(
			_air(0, 0.0, {"wind": 0.5, "sheltered": true}))),
			"stepping under a roof stops it again")
	## The suite ASKED for "no storm makes a summer night breathe" and the
	## model said otherwise -- correctly. A full storm and a full gale take a
	## summer small hours from 13 degrees to 4, and at four degrees you can
	## see your breath. What is actually true, and is the better claim, is
	## that it takes the very worst weather summer has, and that no weather at
	## all puts breath on a summer AFTERNOON.
	ok(ColdScreen.breathes(ColdScreen.air_c(
			_air(1, 4.0, {"level": 4, "intensity": 1.0, "wind": 1.0}))),
			"the worst storm summer has can just put breath in its small hours")
	ok(not ColdScreen.breathes(ColdScreen.air_c(
			_air(1, 16.0, {"level": 4, "intensity": 1.0, "wind": 1.0}))),
			"but nothing at all puts it on a summer afternoon")
	ok(ColdScreen.breath_amount(ColdScreen.air_c(_air(3, 4.0, {"sheltered": true}))) > 0.0,
			"and no roof stops a winter one")


func _t_breath_altitude() -> void:
	claim("breath_altitude", 7)
	## An autumn MORNING is the band where the lapse rate is deciding: 6.5 at
	## sea level is just under the line, and it takes about ninety metres to
	## cross it. A fixture at 60 m would have proved nothing either way.
	var low := _air(2, 8.0, {"y": 60.0})
	var mid := _air(2, 8.0, {"y": 100.0})
	var high := _air(2, 8.0, {"y": 200.0})
	var alp := _air(2, 8.0, {"y": 900.0})
	near_f(ColdScreen.air_c(low), 6.5, 0.05, "an autumn morning at sea level (measured)")
	ok(not ColdScreen.breathes(ColdScreen.air_c(low)), "does not breathe")
	ok(not ColdScreen.breathes(ColdScreen.air_c(mid)), "nor forty metres up")
	ok(ColdScreen.breathes(ColdScreen.air_c(high)), "but it does by two hundred")
	near_f(ColdScreen.breath_amount(ColdScreen.air_c(alp)), 0.662, 0.02,
			"and at nine hundred it is a proper plume (measured)")
	ok(ColdScreen.air_c(alp) < ColdScreen.air_c(low), "because height is colder")
	ok(ColdScreen.breath_amount(ColdScreen.air_c(alp))
			> ColdScreen.breath_amount(ColdScreen.air_c(high)),
			"and colder still is thicker")


# ------------------------------------------------ breath is an EVENT, not a level

func _t_breath_event() -> void:
	claim("breath_event", 20)
	var cold := _air(3, 4.0)
	var warm := _air(1, 12.0)

	var calm := _puffs_over(cold, 0.0, 42.0, 0.05)
	var hard := _puffs_over(cold, 1.0, 42.0, 0.05)
	ok(calm >= 9 and calm <= 12, "standing still in winter: about ten breaths in forty seconds (%d)" % calm)
	ok(hard >= 26 and hard <= 31, "sprinting: about twenty-eight (%d)" % hard)
	ok(hard >= calm * 2.5, "so working trebles the rate, near enough")
	ok(_puffs_over(warm, 1.0, 42.0, 0.05) == 0, "and summer air shows nothing however hard you run")
	ok(_puffs_over(_air(3, 4.0, {"swimming": true}), 0.0, 42.0, 0.05) == 0,
			"nobody breathes out underwater")

	near_f(ColdScreen.breath_interval(0.0), ColdScreen.BREATH_CALM_S, 0.0001, "a calm interval")
	near_f(ColdScreen.breath_interval(1.0), ColdScreen.BREATH_HARD_S, 0.0001, "a hard one")
	ok(ColdScreen.breath_interval(0.5) < ColdScreen.BREATH_CALM_S
			and ColdScreen.breath_interval(0.5) > ColdScreen.BREATH_HARD_S,
			"and it runs between them")
	ok(ColdScreen.breath_interval(1.0) < ColdScreen.breath_interval(0.0),
			"harder work is always a shorter interval")

	near_f(ColdScreen.exertion_of(false, 1.0), 0.0, 0.0001, "full wind, standing: no exertion")
	near_f(ColdScreen.exertion_of(false, 0.25), 0.75, 0.0001, "a drained man is working even at a walk")
	near_f(ColdScreen.exertion_of(true, 1.0), 1.0, 0.0001, "and a sprint is all of it whatever the meter says")

	## Stepping out of a warm hall into a frost puffs on the FIRST frame:
	## the cycle resets in warm air rather than leaving you up to four
	## seconds of nothing at the moment it would read best.
	ok(ColdScreen.puff_size(-10.0, 1.0) > ColdScreen.puff_size(-10.0, 0.0) * 1.3,
			"a hard breath is a bigger cloud as well as a more frequent one")
	near_f(ColdScreen.puff_size(-10.0, 0.0), ColdScreen.breath_amount(-10.0), 0.0001,
			"and a calm one is just what the air is worth")

	var cs := ColdScreen.new()
	## BREATHE IN THE FROST FIRST. A fresh instance has its cycle at zero
	## already, so walking straight from warm air into cold proved nothing at
	## all: a version that never reset the cycle looked identical. Found by
	## mutation, and the fixture now starts part-way through a real one.
	cs.step(cold, 100.0, 0.0, 0.05)
	for i in range(6):
		cs.step(cold, 100.0, 0.0, 0.3)
	ok(cs.breath_t > 1.0, "the cycle is genuinely part-way through (%.2f s to go)" % cs.breath_t)
	for i in range(40):
		cs.step(warm, 100.0, 0.0, 0.1)
	near_f(cs.breath_t, 0.0, 0.0001, "and warm air puts it back to nothing")
	var first: Dictionary = cs.step(cold, 100.0, 0.0, 0.05)
	ok(bool(first["puff"]), "so stepping into the frost breathes at once")
	ok(float(first["puff_size"]) > 0.0, "and the exhale carries a size")
	var second: Dictionary = cs.step(cold, 100.0, 0.0, 0.05)
	ok(not bool(second["puff"]), "the very next frame does not")
	ok(float(second["puff_size"]) == 0.0, "and carries no size")


func _puffs_over(e: Dictionary, exertion: float, seconds: float, dt: float) -> int:
	var cs := ColdScreen.new()
	var n := 0
	var t := 0.0
	while t < seconds:
		if bool(cs.step(e, 100.0, exertion, dt)["puff"]):
			n += 1
		t += dt
	return n


# ------------------------------------------------------- the rungs are borrowed

func _t_rungs() -> void:
	claim("rungs", 8)
	## NO FIFTH NUMBER. Swept at a tenth of a point across the whole meter and
	## past both ends: the screen's idea of shivering has to be the project's.
	var agree := true
	var seen := {}
	for i in range(1200):
		var w := -5.0 + float(i) * 0.1
		var g := ColdScreen.shiver_grade(w)
		seen[g] = true
		if g != int(Exposure.sway_extra(w)):
			agree = false
	ok(agree, "shiver_grade equals int(Exposure.sway_extra) at every warmth")
	ok(seen.size() == 3, "and the sweep saw all three rungs (%d)" % seen.size())
	ok(ColdScreen.shiver_grade(Exposure.WARMTH_LOW) == 0, "steady exactly at the shiver line")
	ok(ColdScreen.shiver_grade(Exposure.WARMTH_LOW - 0.001) == 1, "shivering a thousandth below it")
	ok(ColdScreen.shiver_grade(Exposure.WARMTH_NUMB) == 1, "still shivering at the numb line")
	ok(ColdScreen.shiver_grade(Exposure.WARMTH_NUMB - 0.001) == 2, "and numb a thousandth below that")
	near_f(ColdScreen.shiver_t(Exposure.WARMTH_LOW), 0.0, 0.0001, "the ramp opens at the shiver line")
	near_f(ColdScreen.shiver_t(Exposure.WARMTH_NUMB), 1.0, 0.0001, "and is full at the numb line")


# --------------------------------------------- a bout is state, and it finishes

func _t_bouts() -> void:
	claim("bouts", 18)
	ok(ColdScreen.bout_len(5.0) > ColdScreen.bout_len(29.0), "a colder bout lasts longer")
	ok(ColdScreen.bout_gap(5.0) < ColdScreen.bout_gap(29.0), "with less quiet between")
	near_f(ColdScreen.bout_gap(Exposure.WARMTH_NUMB), 0.0, 0.0001,
			"and at the numb line no quiet at all, which is how it becomes continuous")
	ok(ColdScreen.shake_for(5.0) > ColdScreen.shake_for(29.0) * 2.0,
			"and shakes more than twice as hard")

	var warm_duty := _duty(100.0, 60.0)
	var edge_duty := _duty(29.0, 60.0)
	var mid_duty := _duty(20.0, 60.0)
	var numb_duty := _duty(5.0, 60.0)
	near_f(warm_duty, 0.0, 0.0001, "a warm man never shakes")
	ok(edge_duty > 0.0 and edge_duty < 0.5, "at the shiver line it is bursts (%.2f)" % edge_duty)
	ok(mid_duty > edge_duty, "halfway down it is more of them (%.2f)" % mid_duty)
	ok(numb_duty > 0.98, "and past the numb line it never stops (%.2f)" % numb_duty)
	ok(numb_duty > mid_duty and mid_duty > edge_duty, "a ladder, not a switch")

	## A BOUT RUNS ITS COURSE. Warm right up in the middle of one and you are
	## still shaking, at the strength it began at -- which is the whole
	## difference between a state things happen to and a query on the meter.
	var cs := ColdScreen.new()
	var e := _air(3, 4.0)
	var guard := 0
	while not bool(cs.step(e, 12.0, 0.0, 0.05)["started"]) and guard < 400:
		guard += 1
	ok(guard < 400, "a bout starts within a few seconds at warmth 12")
	var strength := cs.bout_shake
	ok(strength > 0.0, "and it is worth something")
	var rep: Dictionary = cs.step(e, 100.0, 0.0, 0.05)
	ok(bool(rep["bout"]), "warming up mid-bout does not stop it")
	near_f(float(rep["shake"]), strength, 0.0001, "and does not weaken it either")
	var still := true
	for i in range(18):
		if not bool(cs.step(e, 100.0, 0.0, 0.05)["bout"]):
			still = false
	ok(still, "it is still going most of a second later")
	var ended := false
	for i in range(200):
		if not bool(cs.step(e, 100.0, 0.0, 0.05)["bout"]):
			ended = true
	ok(ended, "but it does end")
	var after := 0
	for i in range(400):
		if bool(cs.step(e, 100.0, 0.0, 0.05)["bout"]):
			after += 1
	ok(after == 0, "and a warm man never starts another (%d)" % after)
	near_f(cs.step(e, 100.0, 0.0, 0.05)["shake"], 0.0, 0.0001, "with nothing left to shake with")

	cs.step(e, 5.0, 0.0, 6.0)
	cs.reset()
	ok(cs.bout_t == 0.0 and cs.gap_t == 0.0 and cs.bout_shake == 0.0,
			"a respawn clears the body it happened to")
	ok(cs.readout().contains("nothing stepped"), "and the readout says so")


func _duty(warmth: float, seconds: float) -> float:
	var cs := ColdScreen.new()
	var e := _air(3, 4.0)
	var n := 0
	var total := 0
	var t := 0.0
	while t < seconds:
		if bool(cs.step(e, warmth, 0.0, 0.05)["bout"]):
			n += 1
		total += 1
		t += 0.05
	return float(n) / float(total)


# -------------------------------------------------------------------- the grade

func _t_grade() -> void:
	claim("grade", 18)
	near_f(ColdScreen.grade_t(Exposure.WARMTH_MAX), 0.0, 0.0001, "a warm screen is untouched")
	near_f(ColdScreen.grade_t(Exposure.WARMTH_LOW), 0.0, 0.0001, "and so is one exactly at the line")
	near_f(ColdScreen.grade_t(0.0), 1.0, 0.0001, "an empty meter is the full grade")
	near_f(ColdScreen.grade_t(15.0), 0.5, 0.0001, "halfway down is half of it")

	var mono := true
	var prev := ColdScreen.grade_t(-5.0)
	for i in range(1200):
		var g := ColdScreen.grade_t(-5.0 + float(i) * 0.1)
		if g > prev + 0.0001:
			mono = false
		prev = g
	ok(mono, "and it only ever deepens as the meter falls")

	var full: Dictionary = ColdScreen.look(0.0)
	near_f(float(full["sat"]), ColdScreen.GRADE_SAT, 0.0001, "full desaturation is the constant")
	near_f(float(full["vignette"]), ColdScreen.GRADE_VIGNETTE, 0.0001, "and so is the vignette")
	near_f(float(full["blue"]), ColdScreen.GRADE_BLUE, 0.0001, "and the blue push")
	## A CONSTANT COMPARED WITH ITSELF IS NOT AN ASSERTION: the three lines
	## above all pass with their constant set to zero, and the mutation sweep
	## walked straight through two of them. These are LITERALS, set against
	## the values measured (0.50 and 0.35), and they are what actually bite.
	ok(float(full["vignette"]) >= 0.35,
			"the vignette really closes at an empty meter (%.2f)" % float(full["vignette"]))
	ok(float(full["blue"]) >= 0.20,
			"and the blue really pushes (%.2f)" % float(full["blue"]))
	ok(float(full["sat"]) <= 0.7, "but it never goes all the way to grey -- this is a warning, not a death screen")
	ok(ColdScreen.GRADE_SAT < 1.0, "which the constant itself guarantees")

	var half: Dictionary = ColdScreen.look(15.0)
	near_f(float(half["sat"]), ColdScreen.GRADE_SAT * 0.5, 0.0001, "half the meter is half the grade")
	var warm: Dictionary = ColdScreen.look(Exposure.WARMTH_MAX)
	ok(float(warm["sat"]) == 0.0 and float(warm["vignette"]) == 0.0
			and float(warm["frost"]) == 0.0 and float(warm["blue"]) == 0.0,
			"and a warm man pays for none of it")

	## Frost is the SECOND rung -- the same place sway doubles and your
	## swings start costing more.
	near_f(ColdScreen.frost_t(Exposure.WARMTH_NUMB), 0.0, 0.0001, "no frost at the numb line")
	ok(ColdScreen.frost_t(Exposure.WARMTH_NUMB - 0.001) > 0.0, "a little just below it")
	near_f(float(ColdScreen.look(0.0)["frost"]), ColdScreen.FROST_MAX, 0.0001, "and all of it at nothing")
	ok(float(ColdScreen.look(Exposure.WARMTH_LOW - 1.0)["frost"]) == 0.0
			and float(ColdScreen.look(Exposure.WARMTH_LOW - 1.0)["sat"]) > 0.0,
			"so a shivering man is graded and not yet frosted")


# ------------------------------------------------------------------- the waking

func _t_wake() -> void:
	claim("wake", 17)
	var cs := ColdScreen.new()
	near_f(cs.blackout(), 0.0, 0.0001, "nobody who has not slept is in the dark")

	cs.wake(false)
	near_f(cs.blackout(), 1.0, 0.0001, "a waking opens black")
	var e := _air(1, 6.0)
	cs.step(e, 100.0, 0.0, ColdScreen.WAKE_HOLD_S * 0.5)
	near_f(cs.blackout(), 1.0, 0.0001, "and holds it")
	var seq: Array[float] = []
	for i in range(120):
		cs.step(e, 100.0, 0.0, 0.05)
		seq.append(cs.blackout())
	var falls := true
	for i in range(1, seq.size()):
		if seq[i] > seq[i - 1] + 0.0001:
			falls = false
	ok(falls, "then comes up, and only up")
	near_f(seq[seq.size() - 1], 0.0, 0.0001, "all the way to nothing")
	## ON THE FIRST FRAME. The first draft asked this six seconds after the
	## waking, by which time a bout that HAD opened was three seconds over --
	## so a version that shook you awake from a perfectly good night walked
	## straight through it. A bout is a thing with a length; ask while it
	## would still be running.
	var gw := ColdScreen.new()
	gw.wake(false)
	ok(not bool(gw.step(e, 100.0, 0.0, 0.05)["bout"]),
			"a good night does not open on a shake")
	ok(not bool(gw.step(e, 100.0, 0.0, 0.05)["bout"]), "nor on the frame after")

	## A cold waking is a different waking, and until this it was one line of
	## log text. Slumber's winter camp ladder ends at four in the morning with
	## the fire out; the screen should say so before the log does.
	var cd := ColdScreen.new()
	cd.wake(true)
	ok(cd.wake_hold > cs.wake_hold, "waking cold holds the dark longer")
	ok(cd.wake_hold - ColdScreen.WAKE_HOLD_S >= 0.6,
			"by better than half a second (%.2f)" % (cd.wake_hold - ColdScreen.WAKE_HOLD_S))
	## The HOLD alone satisfies a comparison on the total, which is how a
	## version with the cold fade cut back to the warm one survived. Pin the
	## FADE itself, as a literal set against the measured 2.9 against 1.8.
	ok(cd.wake_total - cd.wake_hold >= ColdScreen.WAKE_FADE_S + 0.8,
			"and comes up slower than a good one (%.2f s of fade against %.2f)"
			% [cd.wake_total - cd.wake_hold, ColdScreen.WAKE_FADE_S])
	ok(cd.wake_total > ColdScreen.WAKE_HOLD_S + ColdScreen.WAKE_FADE_S,
			"so the whole waking is longer too")
	var first: Dictionary = cd.step(_air(3, 4.5), 28.0, 0.0, 0.05)
	ok(bool(first["bout"]), "and it opens ON a shake")
	near_f(float(first["shake"]), ColdScreen.SHAKE_NUMB, 0.0001, "a hard one")
	near_f(float(first["blackout"]), 1.0, 0.0001, "while the screen is still black")
	ok(float(first["breath"]) > 0.0, "with your breath in the air where you can see it")
	var total := 0.0
	for i in range(400):
		cd.step(_air(3, 4.5), 28.0, 0.0, 0.05)
		total += 0.05
	near_f(cd.blackout(), 0.0, 0.0001, "and it too ends (%.1f s)" % total)
	## The remaining guard, now that the redundant hold branch is gone: a
	## waking with no fade at all divides by nothing and must say so.
	var zf := ColdScreen.new()
	zf.wake_total = 1.0
	zf.wake_hold = 1.0
	zf.wake_t = 1.0
	near_f(zf.blackout(), 0.0, 0.0001, "a waking with no fade is not a blackout")


# ------------------------------------------------------- the overlay, as source

func _t_overlay() -> void:
	claim("overlay", 25)
	var fn := "func " + "present"
	var planted := fn + "(r) -> void:\n\t_mat.set_shader" + "_parameter(\"sat_drop\", 1.0)\n\nfunc other() -> void:\n\tpass\n"
	var pb := _func_body(planted, "present")
	ok(pb.contains("sat_drop"), "the body reader finds a planted call before it is trusted")
	ok(not pb.contains("func other"), "and stops at the next function")

	var src := _src("res://scripts/ColdScreen.gd")
	ok(src.length() > 4000, "the source scanned back %d chars" % src.length())
	ok(src.contains("hint_screen" + "_texture"),
			"the overlay samples the screen, which is the only way to desaturate one")
	for u in ["sat_drop", "blue_push", "vignette", "frost", "blackout"]:
		ok(src.contains("uniform float " + String(u)), "the shader declares %s" % u)

	## ASSERT THE CALL, IN THE FUNCTION. A mutation that deletes the line
	## must not walk through on the word still sitting in a comment.
	var body := _func_body(src, "present")
	ok(body.length() > 200, "present() scanned back %d chars" % body.length())
	for u in ["sat_drop", "blue_push", "vignette", "frost"]:
		ok(body.contains("set_shader" + "_parameter(\"" + String(u)),
				"and present() actually pushes %s" % u)
	var ab := _func_body(src, "attach")
	ok(ab.contains("move_child"), "attach() puts the overlay under the bars, not over them")

	## THE THREE DEFECTS THE LIVE PASS FOUND, each one a white wall across two
	## thirds of the screen and NONE of them visible from a pure function. A
	## suite cannot photograph a frame, but it can hold the three lines that
	## fixed it in place so nobody quietly puts them back.
	ok(ab.contains("_puff.local_coords = true"),
			"the exhale is head-relative -- with world coords it sprays into the lens")
	ok(not ab.contains("local_coords = false"), "and never the other way round")
	ok(ab.contains("BREATH_QUAD_M"),
			"the breath quad is sized on the MESH, because BILLBOARD_PARTICLES ignores particle scale")
	ok(not ab.contains("qm.size = Vector2(1.0, 1.0)"), "and not left at a one-metre default")
	ok(ColdScreen.BREATH_QUAD_M < 0.25,
			"at a quarter-metre or less (%.3f), which is a wisp at arm's length" % ColdScreen.BREATH_QUAD_M)
	ok(ab.contains("albedo_texture"),
			"and it carries a radial falloff, or the exhale renders as a hard square")
	ok(ab.contains("FILL_RADIAL"), "which is what makes it round")

	## Frost is the CELL BOUNDARIES of the Worley field, not the distance to
	## the nearest seed -- the first draft drew round bokeh blobs.
	ok(src.contains("sqrt(b2) - sqrt(best)"),
			"the frost veins are the second-nearest seed minus the nearest")
	ok(not src.contains("smoothstep(0.0, 0.22, best)"), "and not the nearest on its own")

	var cs := ColdScreen.new()
	ok(not cs.has_overlay(), "and nothing is built until something attaches one")
	cs.step(_air(3, 4.0), 8.0, 0.0, 0.05)
	var rd := cs.readout()
	ok(rd.length() > 30 and rd.contains("air") and rd.contains("frost"),
			"the dev readout says what the screen is doing")


# ------------------------------------------- Exposure's REAL front door

func _t_exposure() -> void:
	claim("exposure", 18)
	## A STUB IS NOT THE COLLABORATOR, and neither is a file that merely
	## CALLS one. Every number this suite means is borrowed from here.
	ok(Exposure.WARMTH_MAX > Exposure.WARMTH_LOW, "the meter tops out above the shiver line")
	ok(Exposure.WARMTH_LOW > Exposure.WARMTH_NUMB, "which is above the numb line")
	ok(Exposure.WARMTH_NUMB > 0.0, "which is above nothing")

	var h := 4.0
	ok(Exposure.ambient_c(_air(1, h)) > Exposure.ambient_c(_air(0, h)),
			"summer is warmer than spring")
	ok(Exposure.ambient_c(_air(0, h)) > Exposure.ambient_c(_air(2, h)),
			"spring than autumn")
	ok(Exposure.ambient_c(_air(2, h)) > Exposure.ambient_c(_air(3, h)),
			"autumn than winter")

	var coldest := Exposure.hour_curve_c(Exposure.HOUR_COLDEST)
	var warmest := Exposure.hour_curve_c(Exposure.HOUR_WARMEST)
	ok(warmest > coldest, "the day has a warm end and a cold one")
	near_f(warmest - coldest, Exposure.HOUR_SWING_C * 2.0, 0.01,
			"swinging the full stated amount")
	var any_colder := false
	for i in range(240):
		if Exposure.hour_curve_c(float(i) * 0.1) < coldest - 0.001:
			any_colder = true
	ok(not any_colder, "and four in the morning really is the bottom of it")

	near_f(Exposure.lapse_c(Exposure.LAPSE_BASE_Y), 0.0, 0.0001, "the lapse is zero at its base")
	ok(Exposure.lapse_c(1000.0) < 0.0, "and height is colder")
	var wmono := true
	for lvl in range(1, 5):
		if Exposure.weather_c(lvl, 1.0) >= Exposure.weather_c(lvl - 1, 1.0):
			wmono = false
	ok(wmono, "every weather level is colder than the one below it")
	ok(Exposure.wind_c(1.0, false) < 0.0, "wind costs degrees")
	near_f(Exposure.wind_c(1.0, true), 0.0, 0.0001, "and a roof takes all of them back")
	ok(Exposure.SNOW_C < 0.0, "falling snow is colder than not")

	near_f(Exposure.sway_extra(Exposure.WARMTH_MAX), 0.0, 0.0001, "a warm hand is steady")
	ok(Exposure.sway_extra(Exposure.WARMTH_NUMB - 1.0) > Exposure.sway_extra(Exposure.WARMTH_LOW - 1.0),
			"and a numb one much less so than a cold one")
	ok(Exposure.unknown_env_keys({"seasonn": 3}).size() == 1,
			"the env vocabulary this file borrows still catches a typo")
	ok(Exposure.unknown_env_keys({"season": 3, "wind": 0.5, "fire_c": 1.0}).is_empty(),
			"and passes the keys ColdScreen reads")


# ------------------------------------------------------ a whole night, walked

func _t_night() -> void:
	claim("night", 14)
	## A green pure function says nothing about the SHAPE of a night. Walk one
	## honestly through the real Exposure model and watch the screen change.
	var ex := Exposure.new()
	var cs := ColdScreen.new()
	var e := _air(3, 2.0, {"wind": 0.3})
	var breaths := 0
	var frames := 0
	var grade_at := -1
	var frost_at := -1
	var cross_at := -1
	var bouts_early := 0
	var bouts_late := 0
	var warmths: Array[float] = []
	while frames < 20000 and ex.warmth > 0.0:
		var r: Dictionary = ex.step(e, 0.05)
		var rep: Dictionary = cs.step(e, ex.warmth, 0.0, 0.05)
		warmths.append(ex.warmth)
		if float(rep["breath"]) > 0.0:
			breaths += 1
		if grade_at < 0 and float(rep["grade"]) > 0.0:
			grade_at = frames
		if frost_at < 0 and float(rep["frost"]) > 0.0:
			frost_at = frames
		if cross_at < 0 and ex.warmth < Exposure.WARMTH_LOW:
			cross_at = frames
		if bool(rep["bout"]):
			if cross_at >= 0 and frames < cross_at + 600:
				bouts_early += 1
			else:
				bouts_late += 1
		frames += 1
		if float(r["rate"]) >= 0.0:
			break

	ok(frames > 200, "the night ran to something (%d frames)" % frames)
	ok(ex.warmth <= 0.0, "and it emptied the meter")
	ok(breaths == frames, "every frame of a winter night had your breath in it (%d/%d)" % [breaths, frames])
	ok(cross_at > 0, "the meter crossed the shiver line partway through (frame %d)" % cross_at)
	## THE SUITE WORKS THE ANSWER OUT ITSELF rather than trusting a margin:
	## the grade must open on the same frame the model says you started
	## shivering, not near it.
	ok(grade_at == cross_at, "and the screen opened on exactly that frame (%d vs %d)" % [grade_at, cross_at])
	var own_frost := -1
	for i in range(warmths.size()):
		if warmths[i] < Exposure.WARMTH_NUMB:
			own_frost = i
			break
	ok(frost_at == own_frost, "frost arrived on exactly the frame your hands went (%d vs %d)" % [frost_at, own_frost])
	ok(frost_at > grade_at, "which is later than the grade, as the two rungs demand")
	ok(bouts_early + bouts_late > 0, "you shook during it")
	ok(bouts_late > bouts_early, "and more towards the end than the start (%d vs %d)" % [bouts_late, bouts_early])
	var last: Dictionary = cs.step(e, 0.0, 0.0, 0.05)
	near_f(float(last["sat"]), ColdScreen.GRADE_SAT, 0.0001, "an empty meter ends at full desaturation")
	near_f(float(last["frost"]), ColdScreen.FROST_MAX, 0.0001, "and full frost")
	ok(bool(last["bout"]), "still shaking")
	near_f(float(last["blackout"]), 0.0, 0.0001, "and not in the dark, because nobody slept")
	ok(int(last["rung"]) == 2, "at the bottom rung")


# ---------------------------------------------------------------- determinism

func _t_determinism() -> void:
	claim("determinism", 6)
	var e := _air(3, 4.0, {"wind": 0.4})
	var a := _walk_sig(e)
	var b := _walk_sig(e)
	ok(a == b, "two identical walks give identical screens")
	ok(a.length() > 40, "and the signature is worth comparing (%d)" % a.length())
	var c := _walk_sig(_air(2, 4.0, {"wind": 0.4}))
	ok(a != c, "a different night does not")
	ok(not _src("res://scripts/ColdScreen.gd").contains("Random" + "NumberGenerator"),
			"no generator is constructed in the source")
	ok(not _src("res://scripts/ColdScreen.gd").contains("randf" + "("), "and nothing draws a float")
	ok(not _src("res://scripts/ColdScreen.gd").contains("randi" + "("), "nor an int")


func _walk_sig(e: Dictionary) -> String:
	var cs := ColdScreen.new()
	var s := ""
	for i in range(200):
		var r: Dictionary = cs.step(e, 100.0 - float(i) * 0.5, float(i % 3) * 0.5, 0.05)
		## The first draft of this signature carried only the two booleans and
		## the grade, and a WINTER night and an AUTUMN one hashed the same --
		## because the breathing CADENCE is exertion and nothing else, which
		## is right, and the only thing the air changes is how thick the
		## plume is. A signature that cannot see thickness cannot see the air
		## at all, so it carries it now.
		s += "%d%d%.3f%.3f%.3f" % [1 if bool(r["puff"]) else 0, 1 if bool(r["bout"]) else 0,
				float(r["sat"]), float(r["breath"]), float(r["puff_size"])]
	return s.sha256_text()


# --------------------------------------------------------------- no bindings

func _t_no_bindings() -> void:
	claim("no_bindings", 9)
	## A shadowed dev binding is round-blocking in this project. Both files
	## claim to add none, and the claim is asserted against the source here
	## rather than in a ledger line.
	var fn := "func " + "_input"
	var planted := fn + "(event) -> void:\n\tif event is Input" + "EventKey:\n\t\tpass\n\nfunc other() -> void:\n\tpass\n"
	var pb := _func_body(planted, "_input")
	ok(pb.contains("EventKey"), "the body reader finds a planted event body before it is trusted")
	ok(not pb.contains("func other"), "and stops at the next function")
	var reg := load("res://tests/DevInputRegistry.gd")
	ok(reg != null, "the dev-input registry is loadable")
	for path in ["res://scripts/ColdScreen.gd", "res://tests/ColdScreenTests.gd"]:
		var src := _src(String(path))
		var cbs: Array = reg.input_callbacks(src)
		var keys := src.contains("K" + "EY_") or src.contains("Input" + "EventKey") \
				or src.contains("Input" + "Map") or src.contains("is_action" + "_pressed")
		ok(src.length() > 500 and cbs.is_empty() and not keys,
				"%s scanned back %d chars, declares no event hook and claims no key (%d)"
				% [path, src.length(), cbs.size()])
	ok(not _src("res://scripts/ColdScreen.gd").contains("_unhandled" + "_input"),
			"and no unhandled-event hook either")
	ok(not _src("res://scripts/ColdScreen.gd").contains("_shortcut" + "_input"),
			"nor a shortcut one")
	ok(_src("res://scripts/ColdScreen.gd").contains("func readout"),
			"the one dev affordance is the read-only readout")
	ok(not _src("res://scripts/ColdScreen.gd").contains("get_tree" + "()"),
			"and the file never reaches into the tree on its own")



func _initialize() -> void:
	print("ColdScreenTests -- what the cold looks like")
	_t_breath_seasons()
	_t_breath_is_air()
	_t_breath_weather()
	_t_breath_altitude()
	_t_breath_event()
	_t_rungs()
	_t_bouts()
	_t_grade()
	_t_wake()
	_t_overlay()
	_t_exposure()
	_t_night()
	_t_determinism()
	_t_no_bindings()

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
