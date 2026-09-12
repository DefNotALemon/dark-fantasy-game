extends SceneTree

# =============================================================================
# tests/SlumberTests.gd -- the night (2026-09-11 03:00, SYSTEMS).
#
#   godot --headless --path . --script res://tests/SlumberTests.gd
#
# No terrain, no Player, no World.tscn, no pixel. A night is walked by a pure
# static function over a dictionary, so "winter, soaked, on an open pit with
# one log on it" is a call with six arguments.
#
# Five sections carry more weight than the rest:
#
#   `clock` -- FORWARD, ALWAYS. This is the bug the file exists for:
#   `World.sleep_at_bed` assigned `hour = 6.0` with no `day += 1`, so lying
#   down at nine in the evening wound the sky back fifteen hours and five
#   simulations that bank forward time only spent every night asleep.
#   `hours_until(21, 6) == 9`, stated as a number, is the whole fix.
#
#   `ladder` -- the five winter rungs, each against the value MEASURED by a
#   probe run before one assertion in this file existed. A literal margin set
#   against a number that merely sounds demanding is not an assertion
#   (2026-09-11 00:00): every margin here is set against what the model
#   actually returned, and the neighbouring rung is what pins it.
#
#   `rain` -- the best thing the feature does, and it is not in this file's
#   code at all: `Firepit.RAIN_BURN_MULT` eats the log twice as fast, so the
#   identical fire and the identical night wakes you at a quarter past two in
#   the morning instead of seeing you through to dawn. Five hours of sleep,
#   decided by whether you built a roof.
#
#   `wake` -- the invariant. THIS NEVER KILLS ANYBODY: warmth reaching the
#   shiver line is a waking, not a wound. Asserted from both ends, including
#   an aggregate over every season and rung, because a survival rule that can
#   kill you inside a blackout you cannot act in is not a survival rule.
#
#   `exposure`, `firepit`, `crofts` -- the REAL front doors of the three
#   collaborators. A STUB IS NOT THE COLLABORATOR, and that holds for a file
#   that only CALLS somebody else's method: `Exposure.felt_c`/`warmth_rate`/
#   `wet_rate`/`raining_on`, `Firepit`'s five fuel and rain constants and
#   `Crofts.daylight` can all be deleted by somebody else tomorrow.
#
# SECTION CLAIMS: every section stakes what it is about to assert before it
# runs one, so a section killed by a runtime error shows up as a claim that
# never settled instead of quietly taking its assertions with it.
# =============================================================================

const MIN_ASSERTIONS := 150

const BED_HOUR := 21.0
const LOG_HEAT := 11.4        ## measured live at 2.2 m from a croft hearth
const WIND := 0.3

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

func _e(se: int, hour: float, roof: bool, o: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {"season": se, "hour": hour, "y": 60.0, "wind": WIND,
			"sheltered": roof}
	for k in o:
		d[k] = o[k]
	return Exposure.env(d)


func _planned(se: int) -> float:
	return Slumber.hours_until(BED_HOUR, Slumber.wake_hour(se))


func _rung(se: int, rung: int, wet: float, o: Dictionary = {}) -> Dictionary:
	## 0 open ground, 1 a roof, 2 one log on a fire, 3 fire and a roof,
	## 4 a banked fire and a roof. The winter camp ladder, in order.
	var fire := 0.0
	var fuel := 0.0
	var roof := false
	match rung:
		1:
			roof = true
		2:
			fire = LOG_HEAT
			fuel = Firepit.FUEL_PER_LOG
		3:
			fire = LOG_HEAT
			fuel = Firepit.FUEL_PER_LOG
			roof = true
		4:
			fire = LOG_HEAT
			fuel = Firepit.FUEL_MAX
			roof = true
	return Slumber.night(_e(se, BED_HOUR, roof, o), 100.0, wet, _planned(se), fire, fuel)


func _f(r: Dictionary, k: String) -> float:
	return float(r.get(k, 0.0))


func _woke(r: Dictionary) -> String:
	return String(r.get("woke", "?"))


func _func_body(src: String, fname: String) -> String:
	## Tolerant of BOTH tab and space indentation: the Dev-Input suite's own
	## reader walked only while lines began with a tab, so against a
	## space-indented file it returned nothing and every check built on it
	## passed on a scan that had found nothing (2026-09-09 18:00).
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
	print("\n=== SlumberTests ===")


func _process(_d: float) -> bool:
	_t_clock()
	_t_dawn()
	_t_fire()
	_t_ladder()
	_t_seasons()
	_t_wake()
	_t_rain()
	_t_dry()
	_t_rest()
	_t_thirst()
	_t_purity()
	_t_exposure()
	_t_firepit()
	_t_crofts()
	_t_step()
	_t_messages()
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


# --------------------------------------------------------------------- clock

func _t_clock() -> void:
	claim("clock", 14)
	## THE BUG, as a number. Nine hours forward, not fifteen back.
	near_f(Slumber.hours_until(21.0, 6.0), 9.0, 1e-6,
			"lying down at nine in the evening is NINE hours to a six o'clock dawn")
	ok(Slumber.hours_until(21.0, 6.0) > 0.0,
			"and it is a positive number, which the old assignment never was")
	near_f(Slumber.hours_until(6.0, 21.0), 15.0, 1e-6, "the other way round is fifteen")
	near_f(Slumber.hours_until(23.9, 0.1), 0.2, 1e-6, "and midnight is not a special case")
	near_f(Slumber.hours_until(6.0, 6.0), 24.0, 1e-6,
			"landing on the hour you are already at is a whole day, never zero")
	var all_fwd := true
	var all_day := true
	for i in range(24):
		for j in range(24):
			var h := Slumber.hours_until(float(i), float(j))
			if h <= 0.0:
				all_fwd = false
			if h > 24.0:
				all_day = false
	ok(all_fwd, "every one of 576 hour pairs walks forward")
	ok(all_day, "and none of them walks more than a day")
	ok(Slumber.days_crossed(21.0, 9.0) == 1, "an evening sleep to dawn crosses midnight once")
	ok(Slumber.days_crossed(21.0, 2.0) == 0, "a doze before midnight crosses nothing")
	ok(Slumber.days_crossed(6.0, 9.0) == 0, "and neither does a morning nap")
	ok(Slumber.days_crossed(23.0, 25.0) == 2, "a day and a bit crosses twice")
	near_f(Slumber.hour_after(21.0, 9.0), 6.0, 1e-6, "nine hours after nine at night is six")
	near_f(Slumber.hour_after(21.0, 2.0), 23.0, 1e-6, "two hours after is eleven")
	near_f(Slumber.real_seconds(24.0), 1200.0, 1e-6,
			"and a game day is DayNight's twenty real minutes")


# ---------------------------------------------------------------------- dawn

func _t_dawn() -> void:
	claim("dawn", 8)
	near_f(Slumber.wake_hour(3), Crofts.daylight(3).x, 0.0,
			"dawn IS Crofts' dawn -- one definition of it in the project, not two")
	near_f(Slumber.wake_hour(1), 4.90, 1e-6, "a summer dawn is ten to five")
	near_f(Slumber.wake_hour(3), 7.20, 1e-6, "a winter one is twelve minutes past seven")
	ok(Slumber.wake_hour(3) > Slumber.wake_hour(1), "winter waits longer for the light")
	near_f(_planned(3), 10.20, 0.02, "a winter night from nine is ten and a fifth hours")
	near_f(_planned(1), 7.90, 0.02, "a summer one is seven and nine tenths")
	ok(_planned(3) - _planned(1) >= 2.0,
			"and winter is at least two hours longer -- which is most of why it kills")
	ok(_planned(0) >= _planned(1) + 0.5, "spring is longer than summer too")


# ---------------------------------------------------------------------- fire

func _t_fire() -> void:
	claim("fire", 12)
	var log_s := Firepit.FUEL_PER_LOG
	near_f(Slumber.fire_c_at(LOG_HEAT, log_s, 0.0), LOG_HEAT, 1e-6, "a lit fire is its heat")
	near_f(Slumber.fire_c_at(LOG_HEAT, log_s, log_s - 1.0), LOG_HEAT, 1e-6,
			"and stays it right up to the last second of wood")
	near_f(Slumber.fire_c_at(LOG_HEAT, log_s, log_s + 1.0),
			LOG_HEAT * Firepit.EMBER_HEAT_MULT, 1e-6, "then drops to coals")
	near_f(Slumber.fire_c_at(LOG_HEAT, log_s, log_s + Firepit.EMBER_SECONDS + 1.0), 0.0,
			1e-6, "and the coals go out")
	near_f(Slumber.fire_c_at(0.0, log_s, 0.0), 0.0, 1e-6, "no fire is no fire, fuelled or not")
	ok(Slumber.fire_c_at(LOG_HEAT, log_s, log_s + 1.0) <= LOG_HEAT * 0.5,
			"coals are worth at most half a burning fire")
	near_f(Slumber.burn_mult(_e(3, 21.0, false)), 1.0, 1e-6, "clear air burns wood at its rate")
	near_f(Slumber.burn_mult(_e(3, 21.0, false, {"level": 4, "intensity": 1.0})),
			Firepit.RAIN_BURN_MULT, 1e-6, "a storm on an open pit eats it faster")
	near_f(Slumber.burn_mult(_e(3, 21.0, true, {"level": 4, "intensity": 1.0})), 1.0, 1e-6,
			"and a roof is what turns that off")
	near_f(Slumber.burn_mult(_e(3, 21.0, false, {"level": 4, "intensity": 0.2})), 1.0, 1e-6,
			"a drizzle too light to bite does not")
	ok(Firepit.RAIN_BURN_MULT >= 1.5, "and the rain penalty is a real number, not a one")
	ok(Firepit.EMBER_SECONDS >= 30.0, "coals last long enough to be worth modelling")


# -------------------------------------------------------------------- ladder

func _t_ladder() -> void:
	claim("ladder", 16)
	## WINTER. Every margin below is set against the number a probe returned
	## before this section was written: 04:45 / 06:30 / 70.8 / 86.3 / 96.2.
	var r0 := _rung(3, 0, 0.0)
	var r1 := _rung(3, 1, 0.0)
	var r2 := _rung(3, 2, 0.0)
	var r3 := _rung(3, 3, 0.0)
	var r4 := _rung(3, 4, 0.0)
	ok(_woke(r0) == Slumber.WOKE_COLD, "a winter night on open ground wakes you")
	ok(_f(r0, "hour") <= 5.5, "in the small hours, before five")
	ok(_f(r0, "hours_slept") <= 8.5, "having lost at least an hour and a half of a 10.2 h night")
	ok(_woke(r1) == Slumber.WOKE_COLD, "a roof on its own is NOT enough in winter")
	ok(_f(r1, "hours_slept") >= _f(r0, "hours_slept") + 1.0,
			"though it buys you an hour of it")
	ok(_woke(r2) == Slumber.WOKE_DAWN, "one log on a fire sees you through to dawn")
	ok(_f(r2, "warmth") >= 60.0, "and you wake past sixty")
	ok(_woke(r3) == Slumber.WOKE_DAWN, "so does a fire under a roof")
	ok(_f(r3, "warmth") >= _f(r2, "warmth") + 10.0,
			"and the roof is worth ten points of warmth on top of the fire")
	ok(_woke(r4) == Slumber.WOKE_DAWN, "a banked fire under a roof, likewise")
	ok(_f(r4, "warmth") >= _f(r3, "warmth") + 6.0,
			"and feeding it before bed is worth six more")
	ok(_f(r4, "warmth") >= 90.0, "the top rung wakes you all but full")
	ok(_f(r0, "rest") < _f(r2, "rest"), "a broken night is worth less than a whole one")
	ok(_f(r2, "fire_out_h") >= 0.0, "one log does die before a winter dawn")
	ok(_f(r4, "fire_out_h") < 0.0, "a banked one does not")
	ok(_f(r0, "coldest") <= 0.0, "and the worst of it is below freezing")


# ------------------------------------------------------------------- seasons

func _t_seasons() -> void:
	claim("seasons", 10)
	## Three seasons out of four this is a non-event. That is the point: the
	## feature is a winter rule, not a tax on ordinary play.
	for se in [0, 1, 2]:
		var r := _rung(se, 0, 0.0)
		ok(_woke(r) == Slumber.WOKE_DAWN,
				"season %d sleeps the night through on open ground" % se)
	for se in [0, 1, 2]:
		var r := _rung(se, 0, 0.0)
		ok(_f(r, "warmth") >= 70.0, "and wakes past seventy in season %d" % se)
	var soaked := _rung(2, 0, 1.0)
	ok(_woke(soaked) == Slumber.WOKE_DAWN, "even soaked on the ground in autumn")
	ok(_f(soaked, "warmth") >= 60.0, "and past sixty at that")
	ok(_woke(_rung(3, 0, 0.0)) == Slumber.WOKE_COLD,
			"while the identical night in WINTER wakes you -- which is what makes the rest mean something")
	near_f(_f(_rung(1, 0, 0.0), "warmth"), Exposure.WARMTH_MAX, 0.1,
			"a summer night on bare ground wakes you full")


# ---------------------------------------------------------------------- wake

func _t_wake() -> void:
	claim("wake", 12)
	## THE INVARIANT: this never kills anybody.
	var r0 := _rung(3, 0, 0.0)
	var rs := _rung(3, 0, 1.0)
	ok(_f(r0, "warmth") >= 0.0, "a winter night in the open leaves warmth at or above zero")
	ok(_f(rs, "warmth") > 0.0, "and soaked it is still above it -- nobody freezes in his sleep")
	ok(_f(r0, "hours_slept") <= _f(r0, "hours_planned"), "nobody sleeps past his own dawn")
	var all_bounded := true
	var all_alive := true
	for se in range(4):
		for rung in range(5):
			for wet in [0.0, 1.0]:
				var r := _rung(se, rung, wet)
				if _f(r, "hours_slept") > _f(r, "hours_planned") + 1e-6:
					all_bounded = false
				if _f(r, "warmth") < 0.0:
					all_alive = false
	ok(all_bounded, "across all forty nights, none runs past its planned length")
	ok(all_alive, "and none of them ends below zero warmth")
	ok(_f(r0, "hours_slept") < _f(r0, "hours_planned"),
			"waking cold means the night was actually cut short")
	## A man who lies down already shivering. The threshold is where he was,
	## not where a full man would be -- and it cuts both ways.
	var shiv_w := Slumber.night(_e(3, BED_HOUR, false), 20.0, 0.0, 8.0, 0.0, 0.0)
	var shiv_s := Slumber.night(_e(1, BED_HOUR, false), 20.0, 0.0, 8.0, 0.0, 0.0)
	ok(_woke(shiv_w) == Slumber.WOKE_COLD, "a shivering man in a winter field does not sleep")
	ok(_f(shiv_w, "hours_slept") <= 1.0, "he is up again inside the hour")
	ok(_woke(shiv_s) == Slumber.WOKE_DAWN, "the same man in summer sleeps the night through")
	ok(_f(shiv_s, "warmth") >= 95.0, "and wakes recovered, because there he GAINS")
	var dead := Slumber.night(_e(3, BED_HOUR, false), 0.0, 0.0, 8.0, 0.0, 0.0)
	ok(_f(dead, "hours_slept") <= 0.5, "a man at zero warmth gets no sleep at all")
	near_f(Slumber.wake_warmth(), Exposure.WARMTH_LOW, 0.0,
			"and the line he wakes on IS the shiver line, referenced, never copied")


# ---------------------------------------------------------------------- rain

func _t_rain() -> void:
	claim("rain", 8)
	## The best thing this feature does, and none of it is in this file's own
	## arithmetic: Firepit's rain rule eats the log, the log's heat goes, and
	## the cold does the rest.
	var storm := {"level": 4, "intensity": 1.0}
	var h := _planned(3)
	var rain := Slumber.night(_e(3, BED_HOUR, false, storm), 100.0, 0.0, h,
			LOG_HEAT, Firepit.FUEL_PER_LOG)
	var clear := Slumber.night(_e(3, BED_HOUR, false), 100.0, 0.0, h,
			LOG_HEAT, Firepit.FUEL_PER_LOG)
	var roofed := Slumber.night(_e(3, BED_HOUR, true, storm), 100.0, 0.0, h,
			LOG_HEAT, Firepit.FUEL_PER_LOG)
	ok(_woke(clear) == Slumber.WOKE_DAWN, "one log in clear air sees out a winter night")
	ok(_woke(rain) == Slumber.WOKE_COLD, "the identical fire in a storm does not")
	ok(_f(clear, "hours_slept") - _f(rain, "hours_slept") >= 3.5,
			"the rain costs at least three and a half hours of it")
	ok(_f(rain, "hour") <= 3.5, "and has you up before half past three in the morning")
	ok(_f(rain, "fire_out_h") >= 0.0, "because the fire went out")
	ok(_f(rain, "fire_out_h") < _f(clear, "fire_out_h"), "sooner than it would have")
	ok(_woke(roofed) == Slumber.WOKE_DAWN, "a roof over the same pit gives the night back")
	ok(_f(roofed, "hours_slept") >= _f(rain, "hours_slept") + 3.0, "all three hours of it")


# ----------------------------------------------------------------------- dry

func _t_dry() -> void:
	claim("dry", 6)
	var wet_w := _rung(3, 0, 1.0)
	var dry_w := _rung(3, 0, 0.0)
	ok(_f(wet_w, "wet") <= 0.05, "a night dries you out, whatever you lay down in")
	ok(_f(_rung(0, 0, 1.0), "wet") <= 0.05, "in spring too")
	ok(_f(wet_w, "coldest") < _f(dry_w, "coldest"),
			"but soaked is colder while it lasts")
	ok(_f(wet_w, "hours_slept") < _f(dry_w, "hours_slept"),
			"so being wet wakes you sooner, not later")
	ok(_f(dry_w, "hours_slept") - _f(wet_w, "hours_slept") >= 0.5,
			"by at least half an hour -- the damage is done in the FIRST hours")
	ok(_woke(_rung(0, 0, 1.0)) == Slumber.WOKE_DAWN,
			"and wet alone, in a mild season, is not enough to wake anybody")


# ---------------------------------------------------------------------- rest

func _t_rest() -> void:
	claim("rest", 10)
	near_f(Slumber.rest_fraction(8.0, 8.0), 1.0, 0.0, "a whole night is a whole night")
	near_f(Slumber.rest_fraction(4.0, 8.0), 0.5, 0.0, "half of one is half")
	near_f(Slumber.rest_fraction(0.0, 8.0), 0.0, 0.0, "none of one is none")
	near_f(Slumber.rest_fraction(9.0, 8.0), 1.0, 0.0, "and you cannot bank extra")
	near_f(Slumber.rest_fraction(4.0, 0.0), 0.0, 0.0, "a night of no length divides by nothing")
	near_f(Slumber.heal_to(40.0, 100.0, 1.0), 100.0, 1e-6,
			"a full night closes the whole wound, as sleeping always did")
	near_f(Slumber.heal_to(40.0, 100.0, 0.5), 70.0, 1e-6, "half a night closes half of it")
	near_f(Slumber.heal_to(40.0, 100.0, 0.0), 40.0, 1e-6, "and none of it closes nothing")
	near_f(Slumber.heal_to(100.0, 100.0, 0.0), 100.0, 1e-6, "a whole man stays whole")
	ok(Slumber.heal_to(40.0, 100.0, _f(_rung(3, 0, 0.0), "rest"))
			< Slumber.heal_to(40.0, 100.0, _f(_rung(3, 2, 0.0), "rest")),
			"so the reward for a warm camp is an UNBROKEN night, not a stronger one")


# -------------------------------------------------------------------- thirst

func _t_thirst() -> void:
	claim("thirst", 8)
	var rate := 0.08
	var night := 10.2
	ok(Slumber.thirst_after(100.0, rate, night) < 100.0, "you wake thirstier than you lay down")
	near_f(Slumber.thirst_after(100.0, rate, night), 100.0 - rate * 510.0, 1e-4,
			"by exactly the body's own rate over the real seconds that passed")
	ok(Slumber.thirst_after(100.0, rate, night) >= Slumber.THIRST_FLOOR, "and never below the floor")
	near_f(Slumber.thirst_after(5.0, rate, night), Slumber.THIRST_FLOOR, 1e-6,
			"a man who went to bed parched wakes at the floor")
	ok(Slumber.thirst_after(5.0, rate, night) > 0.0, "alive -- nobody dies of thirst asleep either")
	near_f(Slumber.thirst_after(100.0, 0.0, night), 100.0, 1e-6,
			"Light mode drains nothing, because its rate is nothing")
	near_f(Slumber.thirst_after(100.0, rate, 0.0), 100.0, 1e-6, "and no sleep costs no water")
	ok(Slumber.thirst_after(100.0, rate, night) < Slumber.thirst_after(100.0, rate, 5.0),
			"a longer night costs more of it")


# -------------------------------------------------------------------- purity

func _t_purity() -> void:
	claim("purity", 12)
	var src := _src("res://scripts/Slumber.gd")
	ok(src.length() > 8000, "the source scanned back %d characters" % src.length())
	ok(not src.contains("get_" + "tree("), "no scene tree anywhere in it")
	## Assert the CONSTRUCTOR, not the bare class name: a negative scan for
	## the name alone goes red on the header comment saying there is no RNG
	## here (2026-09-11 00:00).
	ok(not src.contains("RandomNumberGenerator" + ".new("), "and no randomness")
	ok(not src.contains("await "), "and nothing to await")
	ok(not src.contains("Weather" + "."), "it never reaches for the live Weather node")
	ok(not src.contains("DayNight" + "."), "nor for the live clock")
	var planted := "static func " + "burn_mult" + "(e):\n\tvar x = get_" + "tree()\n\nfunc z():\n\tpass\n"
	var pb := _func_body(planted, "burn_mult")
	ok(pb.contains("get_" + "tree("), "the body reader finds a planted defect before it is trusted")
	ok(not pb.contains("func z"), "and stops at the next function")
	var spaced := "static func " + "night" + "(e):\n    return Weather" + ".foo\n\nfunc z():\n    pass\n"
	ok(_func_body(spaced, "night").contains("Weather" + "."),
			"and reads a SPACE-indented body, which is the bug that hid a whole scan")
	var short_body := ""
	for n in ["hours_until", "days_crossed", "fire_c_at", "burn_mult", "night",
			"rest_fraction", "heal_to", "thirst_after"]:
		if _func_body(src, String(n)).strip_edges().is_empty():
			short_body = String(n)
	ok(short_body == "", "every function under test was actually read (%s)" % short_body)
	var a := Slumber.night(_e(3, BED_HOUR, false), 100.0, 0.0, 9.0, 0.0, 0.0)
	var b := Slumber.night(_e(3, BED_HOUR, false), 100.0, 0.0, 9.0, 0.0, 0.0)
	near_f(_f(a, "warmth"), _f(b, "warmth"), 0.0, "the same night twice is the same night")
	var e := _e(3, BED_HOUR, false)
	Slumber.night(e, 100.0, 0.0, 9.0, 0.0, 0.0)
	ok(not bool(e.get("asleep", false)) and absf(float(e.get("hour", 0.0)) - BED_HOUR) < 1e-9,
			"and walking a night does not write on the environment it was handed")


# ------------------------------------------------------------------ exposure

func _t_exposure() -> void:
	claim("exposure", 12)
	## THE REAL FRONT DOOR. This file adds nothing to Exposure and calls four
	## of its methods; any of them can be deleted by somebody else tomorrow.
	ok(Exposure.WARMTH_LOW > 0.0 and Exposure.WARMTH_LOW < Exposure.WARMTH_MAX,
			"the shiver line sits inside the meter")
	var awake := _e(3, 2.0, false)
	var abed: Dictionary = awake.duplicate(true)
	abed["asleep"] = true
	ok(Exposure.felt_c(abed, 0.0) > Exposure.felt_c(awake, 0.0),
			"a bedroll is worth degrees -- the term that had no caller until now")
	near_f(Exposure.felt_c(abed, 0.0) - Exposure.felt_c(awake, 0.0), Exposure.BED_C, 1e-6,
			"exactly BED_C of them")
	ok(Exposure.BED_C >= 3.0, "and at least three")
	ok(Exposure.warmth_rate(-10.0, Exposure.MODE_NORMAL) < 0.0, "cold loses warmth")
	ok(Exposure.warmth_rate(30.0, Exposure.MODE_NORMAL) > 0.0, "warm gains it")
	near_f(Exposure.warmth_rate(Exposure.WARMTH_NEUTRAL_C, Exposure.MODE_NORMAL), 0.0, 1e-6,
			"and neutral is neutral")
	ok(Exposure.warmth_rate(-10.0, Exposure.MODE_HARDCORE)
			< Exposure.warmth_rate(-10.0, Exposure.MODE_NORMAL), "hardcore bites harder")
	ok(Exposure.raining_on(_e(3, 21.0, false, {"level": 4, "intensity": 1.0})),
			"a storm in the open falls on you")
	ok(not Exposure.raining_on(_e(3, 21.0, true, {"level": 4, "intensity": 1.0})),
			"and under a roof it does not")
	ok(Exposure.wet_rate(_e(3, 21.0, false), 0.5) < 0.0, "out of the rain you dry off")
	ok(Exposure.felt_c(_e(3, 2.0, false, {"fire_c": 11.4}), 0.0)
			> Exposure.felt_c(_e(3, 2.0, false), 0.0), "and a fire is heat")


# ------------------------------------------------------------------- firepit

func _t_firepit() -> void:
	claim("firepit", 10)
	## The other real front door: five Firepit constants decide how long the
	## night's fire lasts, and none of them lives in this file.
	ok(Firepit.FUEL_PER_LOG > 0.0, "a log is worth fuel")
	ok(Firepit.FUEL_MAX > Firepit.FUEL_PER_LOG, "and a pit holds more than one")
	ok(Firepit.EMBER_HEAT_MULT > 0.0 and Firepit.EMBER_HEAT_MULT < 1.0,
			"coals are warm, but less warm")
	ok(Firepit.EMBER_SECONDS > 0.0, "and they last a while")
	ok(Firepit.RAIN_BURN_MULT > 1.0, "rain costs wood")
	ok(Firepit.RAIN_THRESHOLD > 0.0 and Firepit.RAIN_THRESHOLD < 1.0,
			"above a threshold that is neither always nor never")
	near_f(Firepit.FUEL_PER_LOG / Slumber.REAL_SECONDS_PER_HOUR, 8.4, 0.05,
			"one log is eight and a half game hours of fire")
	ok(Firepit.FUEL_PER_LOG / Slumber.REAL_SECONDS_PER_HOUR < _planned(3),
			"which is LESS than a winter night -- the last cold hour is the point")
	ok(Firepit.FUEL_MAX / Slumber.REAL_SECONDS_PER_HOUR >= 24.0,
			"while a banked pit sees out any night there is")
	ok(Firepit.FIRE_HEAT_C >= 10.0, "and the stones themselves are worth ten degrees")


# -------------------------------------------------------------------- crofts

func _t_crofts() -> void:
	claim("crofts", 6)
	ok(Crofts.daylight(3).x > Crofts.daylight(1).x, "winter dawn is later than summer's")
	ok(Crofts.daylight(3).y < Crofts.daylight(1).y, "and winter dusk is earlier")
	var ordered := true
	var sane := true
	for se in range(4):
		var dl := Crofts.daylight(se)
		if dl.x >= dl.y:
			ordered = false
		if dl.x < 4.0 or dl.x > 8.0:
			sane = false
	ok(ordered, "every season's dawn comes before its dusk")
	ok(sane, "and every dawn is somewhere between four and eight")
	near_f(Slumber.wake_hour(0), Crofts.daylight(0).x, 0.0, "spring too -- the same table")
	ok((Crofts.daylight(1).y - Crofts.daylight(1).x)
			- (Crofts.daylight(3).y - Crofts.daylight(3).x) >= 3.0,
			"and a summer day is at least three hours longer than a winter one")


# ---------------------------------------------------------------------- step

func _t_step() -> void:
	claim("step", 7)
	## The integration step must not be what decides the answer. Walk the same
	## night by hand five times finer and it has to agree.
	var r3 := _rung(3, 3, 0.0)
	var h := _planned(3)
	var env := _e(3, BED_HOUR, true)
	env["asleep"] = true
	var fine := 0.05
	var w := 100.0
	var wet := 0.0
	var t := 0.0
	var n := 0
	var hand_min := INF
	while t < h - 1e-9:
		env["hour"] = Slumber.hour_after(BED_HOUR, t)
		env["fire_c"] = Slumber.fire_c_at(LOG_HEAT, Firepit.FUEL_PER_LOG,
				Slumber.real_seconds(t))
		var real := Slumber.real_seconds(fine)
		var felt := Exposure.felt_c(env, wet)
		hand_min = minf(hand_min, felt)
		w = clampf(w + Exposure.warmth_rate(felt, Exposure.MODE_NORMAL) * real,
				0.0, Exposure.WARMTH_MAX)
		wet = clampf(wet + Exposure.wet_rate(env, wet) * real, 0.0, 1.0)
		t += fine
		n += 1
	ok(n > 100, "the hand walk took %d steps" % n)
	ok(absf(w - _f(r3, "warmth")) <= 3.0,
			"and a five-times finer step gives the same night (%.1f vs %.1f)" % [w, _f(r3, "warmth")])
	ok(Slumber.STEP_HOURS <= 0.5, "the step is fine enough to sample the four o'clock trough")
	ok(int(r3.get("steps", 0)) >= 30, "a winter night really is walked in thirty-odd steps")
	ok(absf(float(int(r3.get("steps", 0))) - ceilf(h / Slumber.STEP_HOURS)) <= 1.0,
			"as many as its length divided by the step")
	ok(_f(r3, "coldest") < Exposure.felt_c(_e(3, BED_HOUR, true, {"asleep": true,
			"fire_c": LOG_HEAT}), 0.0),
			"and the coldest moment is NOT the hour you lay down -- the night is walked")
	## `coldest` has to be the MINIMUM over the night, not merely the LAST
	## reading, and the difference is not academic: mutating
	## `minf(coldest, felt)` to `felt` survived a 164/0 green twice. The
	## first replacement assertion -- "the worst is behind you by the hour
	## you get up" -- survived it too, because the last step still has the
	## fire's COALS in it and is genuinely warmer than the hour after. So the
	## only honest form is to work the minimum out independently, which this
	## section's hand walk has already done, and demand they agree.
	ok(absf(hand_min - _f(r3, "coldest")) <= 1.0,
			"the coldest reading IS the minimum the night passed through (%.1f vs %.1f)"
			% [hand_min, _f(r3, "coldest")])


# ------------------------------------------------------------------ messages

func _t_messages() -> void:
	claim("messages", 8)
	var cold_fire: Array = Slumber.wake_line({"woke": Slumber.WOKE_COLD, "fire_out_h": 6.0,
			"warmth": 28.0})
	var cold_bare: Array = Slumber.wake_line({"woke": Slumber.WOKE_COLD, "fire_out_h": -1.0,
			"warmth": 28.0})
	var dawn_ok: Array = Slumber.wake_line({"woke": Slumber.WOKE_DAWN, "fire_out_h": -1.0,
			"warmth": 96.0})
	var dawn_cold: Array = Slumber.wake_line({"woke": Slumber.WOKE_DAWN, "fire_out_h": 6.0,
			"warmth": 40.0})
	ok(String(cold_fire[0]).to_lower().contains("fire"),
			"a man woken by a dead fire is TOLD the fire is dead")
	ok(not String(cold_bare[0]).to_lower().contains("fire"),
			"and one who never lit one is not told about a fire he never had")
	ok(String(cold_fire[0]) != String(cold_bare[0]), "so the two readings differ")
	ok(String(dawn_ok[0]).to_lower().contains("dawn"), "a good night mentions the dawn")
	ok(String(dawn_ok[0]) != String(dawn_cold[0]),
			"and waking cold at dawn reads differently from waking well")
	var all_sane := true
	for m in [cold_fire, cold_bare, dawn_ok, dawn_cold]:
		var a: Array = m
		if a.size() != 2 or String(a[0]).is_empty() or String(a[0]).length() > 90:
			all_sane = false
	ok(all_sane, "every line is a non-empty sentence that fits the log")
	var all_coloured := true
	for m in [cold_fire, cold_bare, dawn_ok, dawn_cold]:
		var a: Array = m
		if not (a[1] is Color):
			all_coloured = false
	ok(all_coloured, "and carries a colour the log can use")
	var rd := Slumber.readout(_rung(3, 3, 0.0))
	ok(rd.length() > 20 and rd.contains("warmth"), "and the dev readout says what happened")


# --------------------------------------------------------------- no bindings

func _t_no_bindings() -> void:
	claim("no_bindings", 6)
	## A shadowed dev binding is round-blocking in this project. This file and
	## Slumber.gd claim to add none; the claim is asserted against the source
	## here rather than in a ledger line.
	var fn := "func " + "_input"
	var planted := fn + "(event) -> void:\n\tif event is Input" + "EventKey:\n\t\tpass\n\nfunc other() -> void:\n\tpass\n"
	var pb := _func_body(planted, "_input")
	ok(pb.contains("EventKey"), "the body reader finds a planted input body before it is trusted")
	ok(not pb.contains("func other"), "and stops at the next function")
	var reg := load("res://tests/DevInputRegistry.gd")
	ok(reg != null, "the dev-input registry is loadable")
	for path in ["res://scripts/Slumber.gd", "res://tests/SlumberTests.gd"]:
		var src := _src(String(path))
		var cbs: Array = reg.input_callbacks(src)
		var keys := src.contains("K" + "EY_") or src.contains("Input" + "EventKey") \
				or src.contains("Input" + "Map") or src.contains("is_action" + "_pressed")
		ok(src.length() > 500 and cbs.is_empty() and not keys,
				"%s scanned back %d chars, declares no input callback and claims no key (%d)"
				% [path, src.length(), cbs.size()])
	ok(not _src("res://scripts/Slumber.gd").contains("_unhandled" + "_input"),
			"and no unhandled-input hook either")
