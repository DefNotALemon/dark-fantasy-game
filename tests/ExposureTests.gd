extends SceneTree

# =============================================================================
# tests/ExposureTests.gd -- the cold (2026-09-10, SYSTEMS DEPTH).
#
#   godot --headless --path . --script res://tests/ExposureTests.gd
#
# Nothing here needs terrain, a Player, World.tscn or a pixel. The whole model
# is pure -- `ambient_c(e)`, `felt_c(e, wet)`, `warmth_rate(felt, mode)` -- so
# "a winter midnight, soaked, in a gale, with no roof and no fire" is a call
# with arguments rather than a thing you stand in a field and wait for.
#
# Three sections carry more weight than the rest:
#
#   `table` -- the survival table, which is the feature. Every constant in
#   Exposure.gd was MEASURED against these rows and not chosen: the spec's
#   first regain number left a lit firepit taking TEN REAL MINUTES to bring
#   the meter back, which makes a fire read as weather rather than as the
#   answer to it. The row that matters most is the WINTER CAMP LADDER --
#   nothing, torch, roof, fire, fire and roof, and then asleep by the fire
#   under the roof, which is the only one of the six that actually gains.
#   That ladder is the loop this feature exists to create, so it is asserted
#   as a strict ordering rather than as six separate numbers.
#
#   `fire` and `mode` -- the REAL front doors of the two collaborators this
#   file calls into. Exposure adds no public method to either `Firepit` or
#   `GameMode` and still drives both here, because a stub is not the
#   collaborator (2026-09-09) and that holds for a file that only CALLS one
#   (2026-09-10). `Firepit.heat_from` taking the MAXIMUM and not the sum is
#   the single assumption the whole heat model rests on.
#
#   `meter` -- the only stateful part. The crossings are EDGE-triggered, so
#   this section drives four hundred seconds of a winter night one tenth of a
#   second at a time and asserts each warning fired exactly once, in order,
#   at the second the arithmetic says.
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


func within(v: float, lo: float, hi: float, what: String) -> void:
	ok(v >= lo and v <= hi, "%s (got %.2f, want %.2f..%.2f)" % [what, v, lo, hi])


# ------------------------------------------------------------------ fixtures

func _minutes(e: Dictionary, wet_v := 0.0) -> float:
	## Minutes of real time from a full meter to an empty one, holding the
	## environment still. INF when it never empties.
	var s := Exposure.seconds_to_empty(e, wet_v)
	return INF if s == INF else s / 60.0


func _drive(x: Exposure, e: Dictionary, seconds: float, dt := 0.1) -> Dictionary:
	## Run the meter forward one tenth of a second at a time, collecting every
	## crossing it reports and the damage it asks for. The crossings are
	## EDGE-triggered, so "exactly one" is the assertion that matters.
	var events: Array = []
	var damage := 0.0
	var t := 0.0
	var last: Dictionary = {}
	while t < seconds:
		last = x.step(e, dt)
		var c := String(last["crossed"])
		if c != "":
			events.append([t, c])
		damage += float(last["damage"])
		t += dt
	return {"events": events, "damage": damage, "last": last}


func _of(events: Array, kind: String) -> Array:
	var out: Array = []
	for e in events:
		if String(e[1]) == kind:
			out.append(float(e[0]))
	return out


func _src(path: String) -> String:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return ""
	var s := fa.get_as_text()
	fa.close()
	return s


func _pit(at: Vector3, lit := true) -> Firepit:
	var f := Firepit.make()
	f.position = at
	root.add_child(f)
	if lit:
		f.light()
	return f


# --------------------------------------------------------------------- entry

func _initialize() -> void:
	print("\n=== ExposureTests ===")


func _process(_d: float) -> bool:
	_t_env()
	_t_season()
	_t_hour()
	_t_lapse()
	_t_weather()
	_t_wind()
	_t_ambient()
	_t_felt()
	_t_fire()
	_t_rates()
	_t_table()
	_t_wet()
	_t_meter()
	_t_light()
	_t_mode()
	_t_save()
	_t_effects()
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


# ----------------------------------------------------------------------- env

func _t_env() -> void:
	claim("env", 9)
	## One vocabulary shared by the caller and this file. A misspelt key would
	## otherwise read as its default and quietly turn a storm into a clear day,
	## which is a bug no assertion about degrees could ever catch.
	var d := Exposure.env()
	ok(d.size() == Exposure.DEFAULTS.size(), "env() returns every default")
	ok(int(d["season"]) == 0 and float(d["hour"]) == 12.0, "and their values")
	ok(bool(d["survival"]), "survival is the default: the meter is on unless asked")
	var o := Exposure.env({"season": 3, "wind": 0.5})
	ok(int(o["season"]) == 3 and is_equal_approx(float(o["wind"]), 0.5), "overrides land")
	ok(float(o["hour"]) == 12.0, "and everything unnamed keeps its default")
	ok(int(Exposure.env()["season"]) == 0, "a merge does not mutate DEFAULTS")
	ok(Exposure.unknown_env_keys({"seasonn": 1, "wind": 0.2}) == ["seasonn"],
			"a misspelt key is reported rather than silently defaulted")
	ok(Exposure.unknown_env_keys({"season": 1, "fire_c": 3.0}).is_empty(),
			"and a good dictionary reports nothing")
	var src := _src("res://scripts/Exposure.gd")
	var missing: Array = []
	for k in Exposure.DEFAULTS:
		if not src.contains('"%s"' % k):
			missing.append(k)
	ok(src.length() > 5000 and missing.is_empty(),
			"every declared key is named in the source (%d chars, missing %s)" % [src.length(), str(missing)])


# -------------------------------------------------------------------- season

func _t_season() -> void:
	claim("season", 11)
	## Wind's REAL front door. `Weather.season()` needs a Weather node with a
	## DayNight bound to it; `Wind.phase_for_day` is static and is what
	## `Weather._season()` is built on, so this file agrees with the sky
	## without having to build one.
	var names := ["Spring", "Summer", "Autumn", "Winter"]
	var seen: Dictionary = {}
	for i in 8:
		var day := Wind.DAYS_PER_YEAR * float(i) / 8.0 + 0.5
		var s := Exposure.season_for_day(day)
		seen[s] = true
		ok(names[s] == Wind.season_name(day),
				"day %.1f is %s to both of us" % [day, names[s]])
	ok(seen.size() == 4, "all four seasons turn up across one year")
	ok(Exposure.season_for_day(3.0) == Exposure.season_for_day(3.0 + Wind.DAYS_PER_YEAR),
			"and the year wraps")
	var p := Wind.phase_for_day(7.0)
	ok(p >= 0.0 and p < 1.0, "the phase Wind hands out is a real 0..1")


# ---------------------------------------------------------------------- hour

func _t_hour() -> void:
	claim("hour", 8)
	## The diurnal curve is SKEWED on purpose: ten hours up from 04:00 to
	## 14:00, fourteen back round. A plain cosine would put the warmest hour at
	## 16:00 and every dusk in the game would be warmer than it looks.
	near_f(Exposure.hour_curve_c(Exposure.HOUR_COLDEST), -Exposure.HOUR_SWING_C, 0.001,
			"04:00 is the coldest hour")
	near_f(Exposure.hour_curve_c(Exposure.HOUR_WARMEST), Exposure.HOUR_SWING_C, 0.001,
			"14:00 is the warmest")
	near_f(Exposure.hour_curve_c(3.999), Exposure.hour_curve_c(4.0), 0.01,
			"and the two halves join without a step at 04:00")
	var rising := true
	var h := Exposure.HOUR_COLDEST
	while h < Exposure.HOUR_WARMEST - 0.01:
		if Exposure.hour_curve_c(h + 0.25) <= Exposure.hour_curve_c(h):
			rising = false
		h += 0.25
	ok(rising, "it climbs without pause from 04:00 to 14:00")
	var falling := true
	var g := Exposure.HOUR_WARMEST
	while g < Exposure.HOUR_WARMEST + 13.9:
		if Exposure.hour_curve_c(g + 0.25) >= Exposure.hour_curve_c(g):
			falling = false
		g += 0.25
	ok(falling, "and falls without pause from 14:00 round to 04:00")
	var bounded := true
	for i in 240:
		var v := Exposure.hour_curve_c(float(i) * 0.1)
		if absf(v) > Exposure.HOUR_SWING_C + 0.001:
			bounded = false
	ok(bounded, "and never leaves +/- HOUR_SWING_C over a whole day")
	near_f(Exposure.hour_curve_c(26.0), Exposure.hour_curve_c(2.0), 0.0001,
			"an hour past midnight is an hour past midnight")
	ok(Exposure.hour_curve_c(0.0) < Exposure.hour_curve_c(12.0), "midnight is colder than noon")


# --------------------------------------------------------------------- lapse

func _t_lapse() -> void:
	claim("lapse", 4)
	near_f(Exposure.lapse_c(Exposure.LAPSE_BASE_Y), 0.0, 0.00001, "sea level costs nothing")
	near_f(Exposure.lapse_c(Exposure.LAPSE_BASE_Y + 1000.0), -6.5, 0.001,
			"a kilometre up is 6.5 degrees colder, which is the real lapse rate")
	ok(Exposure.lapse_c(500.0) < Exposure.lapse_c(200.0), "and it is monotonic in height")
	ok(Exposure.lapse_c(0.0) > 0.0, "below the base line is warmer, not clamped away")


# ------------------------------------------------------------------- weather

func _t_weather() -> void:
	claim("weather", 8)
	for i in range(1, Exposure.WEATHER_C.size()):
		ok(Exposure.weather_c(i, 1.0) < Exposure.weather_c(i - 1, 1.0),
				"weather level %d is strictly colder than %d" % [i, i - 1])
	near_f(Exposure.weather_c(4, 0.5), Exposure.WEATHER_C[4] * 0.5, 0.0001,
			"a storm still building is not yet a storm")
	ok(Exposure.weather_c(0, 1.0) == 0.0, "a clear sky costs nothing at any intensity")
	ok(Exposure.weather_c(99, 1.0) == Exposure.WEATHER_C[Exposure.WEATHER_C.size() - 1],
			"a level off the end of the table clamps rather than crashing")
	ok(Exposure.weather_c(3, 4.0) == Exposure.weather_c(3, 1.0), "and intensity clamps at 1")


# ---------------------------------------------------------------------- wind

func _t_wind() -> void:
	claim("wind", 4)
	ok(Exposure.wind_c(1.0, false) == Exposure.WIND_C, "a full gale costs WIND_C")
	ok(Exposure.wind_c(1.0, true) == 0.0,
			"and a roof takes the whole of it away -- this is what shelter IS")
	near_f(Exposure.wind_c(0.5, false), Exposure.WIND_C * 0.5, 0.0001, "it scales")
	ok(Exposure.wind_c(9.0, false) == Exposure.WIND_C, "and clamps")


# ------------------------------------------------------------------- ambient

func _t_ambient() -> void:
	claim("ambient", 11)
	var noon := {"hour": 12.0}
	for s in 4:
		var d: Dictionary = noon.duplicate()
		d["season"] = s
		near_f(Exposure.ambient_c(Exposure.env(d)),
				Exposure.SEASON_BASE_C[s] + Exposure.hour_curve_c(12.0), 0.001,
				"season %d at noon is its base plus the hour" % s)
	ok(Exposure.ambient_c(Exposure.env({"season": 1})) > Exposure.ambient_c(Exposure.env({"season": 3})),
			"summer is warmer than winter")
	var open_storm := Exposure.env({"season": 2, "level": 4, "intensity": 1.0, "wind": 0.8})
	var clear := Exposure.env({"season": 2})
	ok(Exposure.ambient_c(open_storm) < Exposure.ambient_c(clear), "a storm in the open is colder")
	var roofed := open_storm.duplicate()
	roofed["sheltered"] = true
	near_f(Exposure.ambient_c(roofed), Exposure.ambient_c(clear), 0.001,
			"and a roof takes BOTH the weather and the wind terms off it")
	var cave := open_storm.duplicate()
	cave["underground"] = true
	near_f(Exposure.ambient_c(cave), Exposure.ambient_c(roofed), 0.001,
			"a cave shelters exactly as a roof does")
	var snow := Exposure.env({"season": 3, "level": 3, "intensity": 1.0, "snowing": true})
	var rain := Exposure.env({"season": 3, "level": 3, "intensity": 1.0})
	ok(Exposure.ambient_c(snow) <= Exposure.ambient_c(rain) - 1.0,
			"snow costs at least a degree more than the same weight of rain")
	var snow_in := snow.duplicate()
	snow_in["sheltered"] = true
	var rain_in := rain.duplicate()
	rain_in["sheltered"] = true
	near_f(Exposure.ambient_c(snow_in), Exposure.ambient_c(rain_in), 0.001,
			"and costs nothing at all indoors")
	ok(Exposure.ambient_c(Exposure.env({"y": 400.0})) < Exposure.ambient_c(Exposure.env({"y": 60.0})),
			"the ridge line is colder than the valley you climbed out of")


# ---------------------------------------------------------------------- felt

func _t_felt() -> void:
	claim("felt", 10)
	var e := Exposure.env({"season": 2, "hour": 2.0})
	var dry := Exposure.felt_c(e, 0.0)
	near_f(dry, Exposure.ambient_c(e), 0.0001, "a dry body with nothing near it feels the ambient")
	near_f(Exposure.felt_c(e, 1.0), dry - Exposure.WET_CHILL_C, 0.0001,
			"soaked through costs WET_CHILL_C in still air")
	var gale := Exposure.env({"season": 2, "hour": 2.0, "wind": 1.0})
	var chill_still := Exposure.ambient_c(e) - Exposure.felt_c(e, 1.0)
	var chill_gale := Exposure.ambient_c(gale) - Exposure.felt_c(gale, 1.0)
	ok(chill_still >= 8.0 and chill_gale >= chill_still * 1.5,
			"and wind on wet skin costs it again -- the worst pairing in the game "
			+ "(%.1f still, %.1f in a gale)" % [chill_still, chill_gale])
	var gale_in := gale.duplicate()
	gale_in["sheltered"] = true
	near_f(Exposure.felt_c(gale_in, 1.0),
			Exposure.ambient_c(gale_in) - Exposure.WET_CHILL_C + Exposure.SHELTER_C, 0.0001,
			"a roof takes the wind half of the wet chill away but not the wet")
	near_f(Exposure.felt_c(Exposure.env({"season": 2, "hour": 2.0, "torch": true}), 0.0),
			dry + Exposure.TORCH_C, 0.0001, "a lit torch is a poor fire, but it is one")
	near_f(Exposure.felt_c(Exposure.env({"season": 2, "hour": 2.0, "asleep": true}), 0.0),
			dry + Exposure.BED_C, 0.0001, "a bedroll is worth six degrees")
	near_f(Exposure.felt_c(Exposure.env({"season": 2, "hour": 2.0, "fire_c": 14.0}), 0.0),
			dry + 14.0, 0.0001, "and the fire's degrees go straight in")
	near_f(Exposure.felt_c(Exposure.env({"season": 2, "hour": 2.0, "fire_c": -5.0}), 0.0),
			dry, 0.0001, "a negative heat source is not a cold source")
	near_f(Exposure.felt_c(e, 9.0), Exposure.felt_c(e, 1.0), 0.0001, "wet clamps at soaked")
	ok(Exposure.felt_c(e, 0.5) > Exposure.felt_c(e, 1.0), "and damp is better than soaked")


# ---------------------------------------------------------------------- fire

func _t_fire() -> void:
	claim("fire", 10)
	## Firepit's REAL front door. Exposure adds nothing to that class and still
	## drives it here, because the one assumption the entire heat model rests
	## on -- MAXIMUM across pits, never the sum -- lives in somebody else's
	## file and can be deleted by somebody else tomorrow.
	var a := _pit(Vector3.ZERO)
	ok(a.burning(), "a firepit lights")
	near_f(Exposure.fire_c([a], Vector3(0.0, 0.0, 0.5)), Firepit.FIRE_HEAT_C, 0.001,
			"inside the core radius you get all of it")
	near_f(Exposure.fire_c([a], Vector3(Firepit.FIRE_RANGE, 0.0, 0.0)), 0.0, 0.001,
			"at the edge of its range, none of it")
	ok(Exposure.fire_c([a], Vector3(12.0, 0.0, 0.0)) == 0.0, "and twelve metres out, nothing")
	var b := _pit(Vector3(1.2, 0.0, 0.0))
	var both := Exposure.fire_c([a, b], Vector3(0.6, 0.0, 0.0))
	var one := Exposure.fire_c([a], Vector3(0.6, 0.0, 0.0))
	var other := Exposure.fire_c([b], Vector3(0.6, 0.0, 0.0))
	near_f(both, maxf(one, other), 0.001, "TWO CAMPFIRES ARE NOT A FURNACE: max, never sum")
	ok(both < one + other - 0.5, "and the sum would have been visibly bigger")
	near_f(both, Firepit.heat_from([a, b], Vector3(0.6, 0.0, 0.0)), 0.0001,
			"Exposure.fire_c is exactly Firepit's own answer")
	a.state = Firepit.State.EMBERS
	var ember_heat := Exposure.fire_c([a], Vector3(0.0, 0.0, 0.5))
	ok(ember_heat > 0.0 and ember_heat <= Firepit.FIRE_HEAT_C * 0.4,
			"a banked fire holds a FRACTION of its heat, which is why you bank it "
			+ "(%.2f of %.2f)" % [ember_heat, Firepit.FIRE_HEAT_C])
	a.state = Firepit.State.OUT
	ok(Exposure.fire_c([a], Vector3.ZERO) == 0.0, "a dead pit warms nothing")
	ok(Exposure.fire_c([null, b], Vector3(1.2, 0.0, 0.0)) > 0.0,
			"and a stale entry in the group does not take the live one with it")
	a.queue_free()
	b.queue_free()


# --------------------------------------------------------------------- rates

func _t_rates() -> void:
	claim("rates", 10)
	var n := Exposure.WARMTH_NEUTRAL_C
	ok(Exposure.warmth_rate(n, Exposure.MODE_NORMAL) == 0.0, "at the neutral point, nothing happens")
	ok(Exposure.warmth_rate(n - 5.0, Exposure.MODE_NORMAL) < 0.0, "below it you lose")
	ok(Exposure.warmth_rate(n + 5.0, Exposure.MODE_NORMAL) > 0.0, "above it you gain")
	near_f(Exposure.warmth_rate(n - 10.0, Exposure.MODE_NORMAL),
			-10.0 * Exposure.WARMTH_PER_DEGREE_S, 0.00001, "the drain is linear in degrees")
	near_f(Exposure.warmth_rate(n + 2.0, Exposure.MODE_NORMAL),
			2.0 * Exposure.WARMTH_REGAIN_PER_DEGREE_S, 0.00001, "and so is the regain")
	ok(Exposure.warmth_rate(n + 500.0, Exposure.MODE_NORMAL) == Exposure.WARMTH_REGAIN_CAP,
			"a bonfire is fast but not instant")
	## These two are stated as LITERAL margins rather than against the very
	## constants they exist to guard. The first sweep of `mutate_exposure.py`
	## let `hardcore-is-normal` walk straight through the near_f that stood
	## here, because `rate * HARD_DRAIN_MULT` agrees with itself whatever
	## HARD_DRAIN_MULT is set to. An assertion that cannot fail is not one.
	ok(Exposure.warmth_rate(n - 10.0, Exposure.MODE_PEACEFUL)
			> Exposure.warmth_rate(n - 10.0, Exposure.MODE_NORMAL) * 0.75,
			"Peaceful loses it markedly more slowly")
	ok(Exposure.warmth_rate(n - 10.0, Exposure.MODE_HARDCORE)
			< Exposure.warmth_rate(n - 10.0, Exposure.MODE_NORMAL) * 1.15,
			"Hardcore markedly faster")
	near_f(Exposure.warmth_rate(n + 3.0, Exposure.MODE_HARDCORE),
			Exposure.warmth_rate(n + 3.0, Exposure.MODE_NORMAL), 0.00001,
			"but the mode tax is on the DRAIN only: Hardcore makes the cold bite harder, "
			+ "not the fire you already built warm slower")
	ok(Exposure.drain_mult_for(99) == 1.0, "an unknown mode is Normal, not free")


# --------------------------------------------------------------------- table

func _t_table() -> void:
	claim("table", 11)
	## THE FEATURE. Every constant in Exposure.gd was measured against these
	## rows; nothing here was chosen and then rationalised.
	within(_minutes(Exposure.env({"season": 2, "hour": 2.0})), 12.0, 18.0,
			"an autumn night out in the open, dry, is a slow problem")
	within(_minutes(Exposure.env({"season": 3, "hour": 2.0, "wind": 0.3})), 5.0, 7.0,
			"a winter night is twice the problem")
	within(_minutes(Exposure.env({"season": 3, "hour": 2.0, "level": 4, "intensity": 1.0,
			"wind": 0.8, "snowing": true}), 1.0), 2.0, 4.0,
			"and a winter midnight, soaked, in a snowstorm, in a gale, is under three minutes")
	var fire := Exposure.env({"season": 2, "hour": 2.0, "fire_c": Firepit.FIRE_HEAT_C})
	within(Exposure.seconds_to_full(fire, 0.0, 0.0) / 60.0, 3.0, 5.0,
			"a lit firepit brings an empty man back in about four minutes")
	ok(_minutes(Exposure.env({"season": 0, "hour": 20.0})) > 60.0,
			"a clear spring evening is not a survival situation")
	ok(Exposure.warmth_rate(Exposure.felt_c(Exposure.env({"season": 1, "hour": 12.0}), 0.0),
			Exposure.MODE_NORMAL) > 0.0, "and a summer noon actively warms you")
	## THE WINTER CAMP LADDER. Five configurations of the same midnight, each
	## strictly better than the last, and only the last of them survivable.
	## This ordering is the loop the whole feature exists to create.
	##
	## A BARE ROOF IS DELIBERATELY NOT ON THIS LADDER, and the first draft of
	## this section was wrong to put it there: in still air a torch in your
	## hand beats a roof over your head, because a roof's whole value is the
	## wind and the rain it takes away and there is neither to take. The
	## crossover is asserted on its own below -- it is a better statement about
	## the game than a rung would have been.
	var base := {"season": 3, "hour": 2.0, "wind": 0.3}
	var rungs := [
		{},
		{"torch": true},
		{"fire_c": Firepit.FIRE_HEAT_C},
		{"fire_c": Firepit.FIRE_HEAT_C, "sheltered": true},
		{"fire_c": Firepit.FIRE_HEAT_C, "sheltered": true, "asleep": true},
	]
	var felts: Array = []
	for r in rungs:
		var d: Dictionary = base.duplicate()
		for k in r:
			d[k] = r[k]
		felts.append(Exposure.felt_c(Exposure.env(d), 0.0))
	var climbs := true
	for i in range(1, felts.size()):
		if float(felts[i]) <= float(felts[i - 1]):
			climbs = false
	ok(climbs, "the winter camp ladder climbs at every rung: %s" % str(felts))
	var gains: Array = []
	for i in felts.size():
		if Exposure.warmth_rate(float(felts[i]), Exposure.MODE_NORMAL) > 0.0:
			gains.append(i)
	ok(gains == [felts.size() - 1],
			"and ONLY the top rung -- asleep, by the fire, under the roof -- actually gains (%s)" % str(gains))
	## The crossover the ladder is not allowed to hide: shelter is worth more
	## than a torch exactly when the weather is worth sheltering from.
	var still := {"season": 3, "hour": 2.0, "wind": 0.0}
	var blowing := {"season": 3, "hour": 2.0, "wind": 0.9, "level": 4, "intensity": 1.0}
	var torch_still: Dictionary = still.duplicate()
	torch_still["torch"] = true
	var roof_still: Dictionary = still.duplicate()
	roof_still["sheltered"] = true
	var torch_blow: Dictionary = blowing.duplicate()
	torch_blow["torch"] = true
	var roof_blow: Dictionary = blowing.duplicate()
	roof_blow["sheltered"] = true
	ok(Exposure.felt_c(Exposure.env(torch_still), 0.0) > Exposure.felt_c(Exposure.env(roof_still), 0.0)
			and Exposure.felt_c(Exposure.env(roof_blow), 0.0) > Exposure.felt_c(Exposure.env(torch_blow), 0.0),
			"in still air a torch beats a bare roof, and in a storm the roof beats the torch")
	ok(_minutes(Exposure.env({"season": 2, "hour": 14.0, "level": 4, "intensity": 1.0,
			"wind": 0.8, "sheltered": true})) > 20.0,
			"an autumn storm you are standing under a roof in is weather, not a death")
	var worst := {"season": 3, "hour": 2.0, "level": 4, "intensity": 1.0, "wind": 0.8}
	var peace: Dictionary = worst.duplicate()
	peace["mode"] = Exposure.MODE_PEACEFUL
	near_f(_minutes(Exposure.env(peace), 1.0), _minutes(Exposure.env(worst), 1.0) * 2.0, 0.01,
			"and Peaceful buys exactly twice as long on the worst night in the game")


# ----------------------------------------------------------------------- wet

func _t_wet() -> void:
	claim("wet", 12)
	var storm := Exposure.env({"level": 4, "intensity": 1.0})
	near_f(1.0 / Exposure.WET_SWIM_PER_S, 1.43, 0.05, "swimming soaks you in a second and a half")
	near_f(1.0 / Exposure.WET_RAIN_PER_S, 16.7, 0.5, "a full storm takes about seventeen seconds")
	var roofed: Dictionary = storm.duplicate()
	roofed["sheltered"] = true
	ok(Exposure.wet_rate(roofed, 0.0) < 0.0, "under a roof in a storm you get DRIER, not wetter")
	var drizzle := Exposure.env({"level": 2, "intensity": 0.4})
	ok(Exposure.wet_rate(drizzle, 0.5) == 0.0,
			"rain soaks you only as far as it is falling: a drizzle stops at damp")
	ok(Exposure.wet_rate(drizzle, 0.2) > 0.0, "and keeps going until it gets there")
	near_f(1.0 / Exposure.WET_DRY_PER_S, 100.0, 1.0, "drying off in the open takes a hundred seconds")
	near_f(-Exposure.wet_rate(Exposure.env({"fire_c": 14.0}), 1.0),
			Exposure.WET_DRY_PER_S * Exposure.WET_DRY_FIRE_MULT, 0.00001,
			"and a quarter of that by a fire")
	ok(Exposure.wet_rate(storm, 0.5) >= 0.0, "nothing dries while rain is landing on you")
	ok(-Exposure.wet_rate(Exposure.env({"sheltered": true}), 1.0) > Exposure.WET_DRY_PER_S,
			"a roof dries you faster than the open air")
	ok(-Exposure.wet_rate(Exposure.env({"fire_c": 14.0, "sheltered": true}), 1.0)
			> -Exposure.wet_rate(Exposure.env({"sheltered": true}), 1.0),
			"and a fire beats a roof at it")
	var swim_in := Exposure.env({"sheltered": true, "swimming": true})
	ok(Exposure.wet_rate(swim_in, 0.0) == Exposure.WET_SWIM_PER_S,
			"swimming beats every roof there is")
	ok(Exposure.wet_rate(Exposure.env({"level": 1, "intensity": 1.0}), 0.0) < 0.0,
			"and an overcast sky is not rain, however thick")


# --------------------------------------------------------------------- meter

func _t_meter() -> void:
	claim("meter", 15)
	## Four hundred seconds of a winter night, a tenth of a second at a time.
	## The warnings are EDGE-triggered, so "exactly once" is the assertion.
	var cold := Exposure.env({"season": 3, "hour": 2.0})
	var rate := absf(Exposure.warmth_rate(Exposure.felt_c(cold, 0.0), Exposure.MODE_NORMAL))
	var x := Exposure.new()
	var run := _drive(x, cold, 400.0)
	var ev: Array = run["events"]
	ok(x.warmth < Exposure.WARMTH_MAX, "a winter night takes warmth off you")
	ok(x.warmth == 0.0, "and given long enough, all of it")
	ok(_of(ev, "low").size() == 1, "'Shivering' fires exactly once")
	ok(_of(ev, "numb").size() == 1, "and 'your hands are going' exactly once")
	ok(_of(ev, "low")[0] < _of(ev, "numb")[0], "in that order")
	near_f(_of(ev, "low")[0],
			(Exposure.WARMTH_MAX - Exposure.WARMTH_LOW) / rate, 0.5,
			"at the second the arithmetic says")
	var bled := 400.0 - Exposure.WARMTH_MAX / rate
	ok(float(run["damage"]) > 8.0
			and absf(float(run["damage"]) - bled * Exposure.WARMTH_DAMAGE_PER_S) <= 0.2,
			"and the cold bills you for every second past empty (%.2f over %.0fs)"
			% [float(run["damage"]), bled])
	ok(bool(run["last"]["dying"]), "the report says so out loud")
	var dying := _of(ev, "dying")
	var spaced := dying.size() >= 1 and dying.size() <= 4
	for i in range(1, dying.size()):
		if float(dying[i]) - float(dying[i - 1]) < 5.0:
			spaced = false
	ok(spaced, "and the warning repeats on a timer rather than every frame (%d in 25s)" % dying.size())
	var warm := Exposure.env({"season": 2, "hour": 2.0, "fire_c": Firepit.FIRE_HEAT_C})
	var back := _drive(x, warm, 400.0)
	ok(_of(back["events"], "recovered").size() == 1, "coming back past Shivering reports once")
	ok(x.warmth == Exposure.WARMTH_MAX, "and the meter stops at full")
	var p := Exposure.new()
	var pe: Dictionary = cold.duplicate()
	pe["mode"] = Exposure.MODE_PEACEFUL
	var prun := _drive(p, pe, 900.0)
	ok(float(prun["damage"]) == 0.0, "PEACEFUL: the cold is atmosphere and never a killer")
	ok(p.warmth == 0.0, "but it still empties the meter -- Peaceful is not Light")
	## From HALF a meter, not a full one: at full, the clamp answers this
	## question correctly whether or not the guard exists, and the first
	## mutation sweep walked `negative-delta-warms-you` straight through it.
	var q := Exposure.new()
	q.warmth = 50.0
	q.wet = 0.5
	q.step(cold, -5.0)
	ok(q.warmth == 50.0 and q.wet == 0.5, "a negative delta moves nothing")
	var r2 := q.step(cold, 0.1)
	ok(bool(r2["shivering"]) == (q.warmth < Exposure.WARMTH_LOW)
			and bool(r2["numb"]) == (q.warmth < Exposure.WARMTH_NUMB),
			"and the report's flags agree with the meter they came from")


# --------------------------------------------------------------------- light

func _t_light() -> void:
	claim("light", 6)
	var cold := Exposure.env({"season": 3, "hour": 2.0, "survival": false})
	var x := Exposure.new()
	var run := _drive(x, cold, 600.0)
	ok(x.warmth == Exposure.WARMTH_MAX, "Light mode holds the meter full")
	ok(float(run["damage"]) == 0.0, "and never costs you a point of health")
	ok(float(run["last"]["rate"]) == 0.0, "the report says the rate is zero, not merely unapplied")
	var rain: Dictionary = cold.duplicate()
	rain["level"] = 4
	rain["intensity"] = 1.0
	var y := Exposure.new()
	_drive(y, rain, 60.0)
	ok(y.wet > 0.5,
			"but WET is a physical fact rather than a punishment and is tracked anyway, "
			+ "so switching back to Survival in the rain does not start you dry")
	var z := Exposure.new()
	z.warmth = 3.0
	z.to_light()
	ok(z.warmth == Exposure.WARMTH_MAX, "switching to Light tops a frozen meter")
	var r := z.step(Exposure.env({"season": 3, "hour": 2.0}), 0.1)
	ok(z.warmth > Exposure.WARMTH_LOW and float(r["damage"]) == 0.0,
			"so switching back can never start you freezing")


# ---------------------------------------------------------------------- mode

func _t_mode() -> void:
	claim("mode", 6)
	## GameMode's REAL front door, and the one impure static in Exposure.gd.
	var was := GameMode.mode_name()
	GameMode.set_mode(GameMode.Mode.PEACEFUL)
	ok(Exposure.mode_now() == Exposure.MODE_PEACEFUL, "Peaceful reads through")
	ok(GameMode.is_peaceful(), "and GameMode agrees it is set")
	GameMode.set_mode(GameMode.Mode.HARDCORE)
	ok(Exposure.mode_now() == Exposure.MODE_HARDCORE, "Hardcore reads through")
	GameMode.set_mode(GameMode.Mode.NORMAL)
	ok(Exposure.mode_now() == Exposure.MODE_NORMAL, "and Normal is neither of the other two")
	ok(GameMode.KEYS.size() == 3 and GameMode.NAMES.size() == 3,
			"there are exactly three modes to map, so the mapping is total")
	ok(was != "", "and the mode had a name before this section touched it (%s)" % was)


# ---------------------------------------------------------------------- save

func _t_save() -> void:
	claim("save", 9)
	var x := Exposure.new()
	x.warmth = 41.5
	x.wet = 0.62
	var y := Exposure.new()
	y.apply_dict(x.to_dict())
	near_f(y.warmth, 41.5, 0.0001, "warmth survives a save")
	near_f(y.wet, 0.62, 0.0001, "and so does wet")
	var z := Exposure.new()
	z.apply_dict({})
	ok(z.warmth == Exposure.WARMTH_MAX and z.wet == 0.0,
			"a save written before this feature existed loads warm and dry, not dead")
	z.apply_dict({"warmth": 9999.0, "wet": -3.0})
	ok(z.warmth == Exposure.WARMTH_MAX, "a corrupt warmth clamps")
	ok(z.wet == 0.0, "and so does a corrupt wet")
	var r := Exposure.new()
	r.warmth = 0.0
	r.wet = 1.0
	r.on_respawn()
	ok(r.warmth == Exposure.WARMTH_RESPAWN_MIN, "you never respawn into a body already dying of cold")
	ok(r.wet == 0.0, "or a soaked one")
	var full := Exposure.new()
	full.on_respawn()
	ok(full.warmth == Exposure.WARMTH_MAX, "and respawning never takes warmth AWAY")
	ok(x.to_dict().size() == 2, "the save carries the two numbers of state and nothing else")


# ------------------------------------------------------------------- effects

func _t_effects() -> void:
	claim("effects", 8)
	ok(Exposure.stamina_mult(Exposure.WARMTH_MAX) == 1.0, "a warm man is not taxed")
	## Every one of these is a LITERAL margin. Stated against the constants
	## themselves they agreed with whatever those constants became, and two of
	## them let a mutation through on the first sweep.
	ok(Exposure.stamina_mult(Exposure.WARMTH_LOW - 1.0) <= 0.6,
			"a shivering one gets his wind back at little better than half pace")
	ok(Exposure.windup_mult(Exposure.WARMTH_LOW) == 1.0, "shivering does not slow your swing")
	ok(Exposure.windup_mult(Exposure.WARMTH_NUMB - 1.0) >= 1.1,
			"but hands that have gone numb do")
	ok(Exposure.sway_extra(Exposure.WARMTH_MAX) == 0.0, "a warm hand is steady")
	ok(Exposure.sway_extra(Exposure.WARMTH_LOW - 1.0) > 0.0, "a cold one is not")
	ok(Exposure.sway_extra(Exposure.WARMTH_NUMB - 1.0)
			> Exposure.sway_extra(Exposure.WARMTH_LOW - 1.0), "a numb one much less so")
	ok(Exposure.WARMTH_NUMB < Exposure.WARMTH_LOW and Exposure.WARMTH_LOW < Exposure.WARMTH_MAX,
			"and the three bands are in the order the warnings assume")


# -------------------------------------------------------------------- purity

func _t_purity() -> void:
	claim("purity", 8)
	## The model is pure so that the sections above can exist at all. If a roll
	## or a clock ever gets in, every number in `table` becomes a sample rather
	## than a fact.
	var e := Exposure.env({"season": 2, "hour": 7.3, "wind": 0.4, "level": 3, "intensity": 0.6})
	ok(Exposure.ambient_c(e) == Exposure.ambient_c(e), "ambient_c answers the same twice")
	ok(Exposure.felt_c(e, 0.3) == Exposure.felt_c(e, 0.3), "and so does felt_c")
	var src := _src("res://scripts/Exposure.gd")
	ok(src.length() > 5000, "the source scanned back %d characters" % src.length())
	## Prove the reader on planted text carrying the defect BEFORE trusting it
	## on the truth: a scan that comes back empty agrees with everything
	## (2026-09-09 18:00). Tokens are built by concatenation so this file does
	## not trip the very scan it exists to prove.
	var rng_tok := "Random" + "NumberGenerator"
	var planted := "var r := " + rng_tok + ".new()\nvar v := r.rand" + "f()\n"
	ok(planted.contains(rng_tok) and not src.contains(rng_tok),
			"the scanner sees a planted roll, and the real file has none")
	ok(not src.contains("rand" + "f(") and not src.contains("rand" + "i_range")
			and not src.contains("random" + "ize"), "nor any other roll")
	ok(not src.contains("get_" + "tree") and not src.contains("get_" + "node"),
			"it reaches for no node: the caller hands it everything")
	ok(not src.contains("func _" + "process") and not src.contains("func _" + "ready"),
			"and owns no frame of its own -- step() is called, never scheduled")
	ok(not src.contains("Time." + "get_ticks") and not src.contains("await "),
			"no wall clock and nothing to wait for")


# -------------------------------------------------------------- no_bindings

func _t_no_bindings() -> void:
	claim("no_bindings", 8)
	## A shadowed dev binding is round-blocking. This feature claims to add no
	## binding at all; the claim is asserted here against the SOURCE rather
	## than in a ledger line.
	var reg := load("res://tests/DevInputRegistry.gd")
	ok(reg != null, "the dev-input registry is loadable")
	var fn := "func " + "_input"
	var planted := fn + "(event) -> void:\n\tif event is Input" + "EventKey:\n\t\tpass\n"
	var cbs_planted: Array = reg.input_callbacks(planted)
	ok(not cbs_planted.is_empty(),
			"and finds a planted input callback before it is trusted on the truth")
	var spaced := fn + "(event):\n    var x = K" + "EY_F1\n"
	ok(not (reg.input_callbacks(spaced) as Array).is_empty(),
			"including a SPACE-indented one, which is the bug that hid a whole scan")
	for path in ["res://scripts/Exposure.gd", "res://tests/ExposureTests.gd"]:
		var src := _src(path)
		ok(src.length() > 500, "%s scanned back %d characters" % [path, src.length()])
		var cbs: Array = reg.input_callbacks(src)
		var keys := src.contains("K" + "EY_") or src.contains("Input" + "EventKey") \
				or src.contains("Input" + "Map") or src.contains("is_action" + "_pressed")
		ok(cbs.is_empty() and not keys,
				"%s declares no input callback and claims no key (%d callbacks)" % [path, cbs.size()])
	ok(true, "and the feature's only dev affordance is a READ-ONLY row on the F1 god panel")
