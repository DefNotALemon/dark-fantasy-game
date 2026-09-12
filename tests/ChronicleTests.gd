extends SceneTree
## ===========================================================================
## ChronicleTests.gd -- the Chronicle (scripts/Chronicle.gd, ChronicleEvents.gd)
##
##   godot --headless --path . --script res://tests/ChronicleTests.gd
##
## Runs without a renderer, a clock or a sky: the Chronicle keeps its own
## float-day clock and is never bound to DayNight or Weather here, so every
## number below is the sim's own arithmetic. Nothing is written to disk.
##
## Every section is its own function. A runtime error inside one aborts that
## function and returns here, so one broken section cannot take the rest of
## the run with it -- the summary still prints and quit(1) still fires.
## ===========================================================================

var _pass := 0
var _fail := 0
var _sig_fired := 0
var _sig_resolved := 0
const MIN_ASSERTIONS := 70

## the seed every section uses unless it says otherwise
const SEED := 0x4D59524B          ## "MYRK"
const REQUIRED_KIND_KEYS := ["id", "title", "scope", "tags", "hours", "seasons",
	"weather", "regions", "min_rank", "base", "active", "outcomes"]
const REQUIRED_OUTCOME_KEYS := ["id", "weight", "line", "place", "bias", "spawn"]
const PLACE_VALUE_KEYS := ["mood", "stores", "alarm", "watch"]
const EVENT_KEYS := ["uid", "kind", "place", "pos", "born", "ends", "state", "outcome", "line"]
const RUMOUR_KEYS := ["text", "day", "from", "kind"]
## a tag no catalogue outcome may touch, so its decay is measured clean
const CLEAN_TAG := "zz_test_only"


func ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: %s" % what)


func eq(a, b, what: String) -> void:
	ok(a == b, "%s  (got %s, want %s)" % [what, str(a), str(b)])


func near(a: float, b: float, tol: float, what: String) -> void:
	ok(absf(a - b) <= tol, "%s  (got %s, want %s +/- %s)" % [what, str(a), str(b), str(tol)])


func _init() -> void:
	print("ChronicleTests")

	_test_catalogue()
	_test_hour_band()
	_test_weight_gates()
	_test_weight_multipliers()
	_test_catalogue_reachable()
	_test_pick_outcome()
	_test_boot()
	_test_lookups()
	_test_determinism()
	_test_events_age()
	_test_rumours()
	_test_bias()
	_test_save_round_trip()
	_test_long_run()
	_test_clock_binding()
	_test_region_gate()

	_finish()


## ---------------------------------------------------------------------------
##  helpers
## ---------------------------------------------------------------------------

## A booted Chronicle under `root`. A node added to `root` from
## SceneTree._init() gets no _ready() before the first frame, and this suite
## quits inside _init(); boot() is the explicit setup call for exactly that.
func _make(seed_: int = SEED) -> Chronicle:
	var c := Chronicle.new()
	c.world_seed = seed_
	root.add_child(c)
	c.boot()
	return c


func _ctx(hour: float, season: int, weather: int, region: String, rank: int,
		alarm := 0.0, mood := 1.0, stores := 1.0, bias: Dictionary = {}) -> Dictionary:
	return {"hour": hour, "season": season, "weather": weather, "region": region,
		"rank": rank, "alarm": alarm, "mood": mood, "stores": stores, "bias": bias}


## A synthetic kind whose arithmetic is known by hand. Not from the catalogue,
## so the numbers below are the contract's and nobody else's.
func _synth_kind() -> Dictionary:
	return {
		"id": "synth_test", "title": "Synthetic", "scope": "place",
		"tags": ["wolves", "alarm", "hunger", "unrest"],
		"hours": Vector2(6.0, 18.0), "seasons": [1], "weather": [0, 1],
		"regions": ["BANGOR"], "min_rank": 1, "base": 1.0, "active": Vector2(2.0, 6.0),
		"outcomes": [
			{"id": "a", "weight": 1.0, "line": "%s a", "place": {}, "bias": {}, "spawn": ""},
			{"id": "b", "weight": 2.0, "line": "%s b", "place": {}, "bias": {}, "spawn": ""},
			{"id": "c", "weight": 7.0, "line": "%s c", "place": {}, "bias": {}, "spawn": ""},
		],
	}


func _digest(v) -> String:
	return var_to_str(v).sha256_text().substr(0, 16)


func _resolved_seq(c: Chronicle) -> String:
	var parts: PackedStringArray = []
	for ev in c.resolved:
		if ev is Dictionary:
			parts.append("%s:%s" % [str(ev.get("kind", "?")), str(ev.get("outcome", "?"))])
	return ",".join(parts)


func _uid_seq(arr: Array) -> String:
	var parts: PackedStringArray = []
	for ev in arr:
		if ev is Dictionary:
			parts.append(str(ev.get("uid", -1)))
	return ",".join(parts)


func _place_pos(p: Dictionary) -> Vector3:
	var xz: Vector2 = p.get("pos", Vector2.ZERO)
	return Vector3(xz.x, float(p.get("y", 0.0)), xz.y)


## true when every mood/stores/alarm/watch of every place sits in 0..1
func _places_in_range(c: Chronicle) -> bool:
	for p in c.places:
		if not (p is Dictionary):
			return false
		for k in PLACE_VALUE_KEYS:
			var v: float = float(p.get(k, -1.0))
			if v < 0.0 or v > 1.0 or is_nan(v):
				return false
	return true


func _count_sub(s: String, sub: String) -> int:
	var n := 0
	var at := s.find(sub)
	while at >= 0:
		n += 1
		at = s.find(sub, at + sub.length())
	return n


func _fired(_ev: Dictionary) -> void:
	_sig_fired += 1


func _resolved_sig(_ev: Dictionary) -> void:
	_sig_resolved += 1


## ---------------------------------------------------------------------------
##  the catalogue
## ---------------------------------------------------------------------------
func _test_catalogue() -> void:
	var kinds: Array = ChronicleEvents.KINDS
	var ids: PackedStringArray = ChronicleEvents.ids()
	ok(kinds.size() >= 26, "at least 26 kinds (%d)" % kinds.size())
	eq(ids.size(), kinds.size(), "ids() lists every kind")

	var id_set := {}
	var unique := true
	var all_keys := true
	var all_types := true
	var scopes_ok := true
	var bands_ok := true
	var seasons_ok := true
	var weather_ok := true
	var rank_ok := true
	var base_ok := true
	var active_ok := true
	var two_outcomes := true
	var outcome_keys := true
	var weights_pos := true
	var one_pct_s := true
	var spawns_real := true
	var outcome_ids_unique := true
	var deltas_ok := true
	var bias_ok := true
	var bad_each := true
	var snake := true
	var spawn_count := 0
	var clean_tag_untouched := true

	for k in kinds:
		if not (k is Dictionary):
			all_types = false
			continue
		var kind: Dictionary = k
		for key in REQUIRED_KIND_KEYS:
			if not kind.has(key):
				all_keys = false
				print("    kind %s missing %s" % [str(kind.get("id", "?")), key])
		var id: String = str(kind.get("id", ""))
		if id_set.has(id):
			unique = false
			print("    duplicate id %s" % id)
		id_set[id] = true
		if id != id.to_lower() or id.contains(" ") or id.is_empty():
			snake = false
		if not (kind.get("tags") is Array and kind.get("hours") is Vector2
				and kind.get("seasons") is Array and kind.get("weather") is Array
				and kind.get("regions") is Array and kind.get("min_rank") is int
				and kind.get("base") is float and kind.get("active") is Vector2
				and kind.get("outcomes") is Array and kind.get("title") is String):
			all_types = false
			print("    kind %s has a mistyped field" % id)
			continue
		if not ["place", "road", "wild"].has(kind["scope"]):
			scopes_ok = false
		var band: Vector2 = kind["hours"]
		if band.x < 0.0 or band.x > 24.0 or band.y < 0.0 or band.y > 24.0:
			bands_ok = false
			print("    kind %s hours %s" % [id, str(band)])
		for s in kind["seasons"]:
			if not (s is int) or s < 0 or s > 3:
				seasons_ok = false
		for w in kind["weather"]:
			if not (w is int) or w < 0 or w > 4:
				weather_ok = false
		var mr: int = kind["min_rank"]
		if mr < -1 or mr > 2:
			rank_ok = false
		if float(kind["base"]) <= 0.0:
			base_ok = false
		var act: Vector2 = kind["active"]
		if act.x <= 0.0 or act.y < act.x:
			active_ok = false
			print("    kind %s active %s" % [id, str(act)])
		var outs: Array = kind["outcomes"]
		if outs.size() < 2:
			two_outcomes = false
			print("    kind %s has %d outcomes" % [id, outs.size()])
		var oids := {}
		var has_bad := false
		for o in outs:
			if not (o is Dictionary):
				outcome_keys = false
				continue
			var out: Dictionary = o
			for key in REQUIRED_OUTCOME_KEYS:
				if not out.has(key):
					outcome_keys = false
					print("    %s/%s missing %s" % [id, str(out.get("id", "?")), key])
			var oid: String = str(out.get("id", ""))
			if oids.has(oid):
				outcome_ids_unique = false
			oids[oid] = true
			if float(out.get("weight", 0.0)) <= 0.0:
				weights_pos = false
			var line: String = str(out.get("line", ""))
			if _count_sub(line, "%s") != 1:
				one_pct_s = false
				print("    %s/%s line has %d %%s: %s" % [id, oid, _count_sub(line, "%s"), line])
			var sp: String = str(out.get("spawn", ""))
			if not sp.is_empty():
				spawn_count += 1
				if ChronicleEvents.by_id(sp).is_empty():
					spawns_real = false
					print("    %s/%s spawns unknown %s" % [id, oid, sp])
			var pd: Variant = out.get("place", {})
			if pd is Dictionary:
				for dk in pd:
					var dv: float = float(pd[dk])
					if not PLACE_VALUE_KEYS.has(dk) or dv < -1.0 or dv > 1.0:
						deltas_ok = false
						print("    %s/%s place delta %s=%s" % [id, oid, str(dk), str(dv)])
					if (dk == "mood" and dv < 0.0) or (dk == "stores" and dv < 0.0) \
							or (dk == "alarm" and dv > 0.0) or (dk == "watch" and dv < 0.0):
						has_bad = true
			else:
				deltas_ok = false
			var bd: Variant = out.get("bias", {})
			if bd is Dictionary:
				for bk in bd:
					if not (bk is String) or not (bd[bk] is float or bd[bk] is int):
						bias_ok = false
					if bk == CLEAN_TAG:
						clean_tag_untouched = false
			else:
				bias_ok = false
		if not has_bad:
			bad_each = false
			print("    kind %s has no bad outcome" % id)

	ok(all_keys, "every kind carries every required key")
	ok(all_types, "every kind field has the declared type")
	ok(unique, "kind ids are unique")
	ok(snake, "kind ids are lowercase_snake")
	ok(scopes_ok, "every scope is place|road|wild")
	ok(bands_ok, "every hours band sits in 0..24")
	ok(seasons_ok, "every season is 0..3")
	ok(weather_ok, "every weather level is 0..4")
	ok(rank_ok, "every min_rank is -1..2")
	ok(base_ok, "every base weight is positive")
	ok(active_ok, "every active band is 0 < min <= max")
	ok(two_outcomes, "every kind has at least two outcomes")
	ok(outcome_keys, "every outcome carries every required key")
	ok(outcome_ids_unique, "outcome ids are unique within their kind")
	ok(weights_pos, "every outcome weight is > 0")
	ok(one_pct_s, "every outcome line has exactly one %s")
	ok(spawns_real, "every spawn names a real kind id")
	ok(spawn_count >= 4, "at least 4 kinds chain through spawn (%d)" % spawn_count)
	ok(deltas_ok, "place deltas are a subset of mood/stores/alarm/watch in -1..1")
	ok(bias_ok, "bias pools are tag -> number")
	ok(bad_each, "every kind has at least one bad outcome")
	ok(clean_tag_untouched, "no outcome touches the suite's clean tag")

	## by_id
	ok(ChronicleEvents.by_id("no_such_kind_9").is_empty(), "by_id of an unknown id is {}")
	if ids.size() > 0:
		var first: Dictionary = ChronicleEvents.by_id(ids[0])
		eq(str(first.get("id", "")), ids[0], "by_id finds the first id")
		var last: Dictionary = ChronicleEvents.by_id(ids[ids.size() - 1])
		eq(str(last.get("id", "")), ids[ids.size() - 1], "by_id finds the last id")
	## every listed id resolves
	var all_resolve := true
	for id in ids:
		if ChronicleEvents.by_id(id).is_empty():
			all_resolve = false
	ok(all_resolve, "every id from ids() resolves through by_id")


## ---------------------------------------------------------------------------
##  hour_in_band, across midnight
## ---------------------------------------------------------------------------
func _test_hour_band() -> void:
	var night := Vector2(21.0, 4.0)
	ok(ChronicleEvents.hour_in_band(23.0, night), "night band holds 23")
	ok(ChronicleEvents.hour_in_band(2.0, night), "night band holds 2")
	ok(ChronicleEvents.hour_in_band(21.0, night), "night band holds its start")
	ok(ChronicleEvents.hour_in_band(4.0, night), "night band holds its end")
	ok(ChronicleEvents.hour_in_band(0.0, night), "night band holds midnight")
	ok(not ChronicleEvents.hour_in_band(12.0, night), "night band rejects noon")
	ok(not ChronicleEvents.hour_in_band(20.5, night), "night band rejects 20:30")
	ok(not ChronicleEvents.hour_in_band(4.5, night), "night band rejects 04:30")
	var day := Vector2(6.0, 18.0)
	ok(ChronicleEvents.hour_in_band(12.0, day), "day band holds noon")
	ok(ChronicleEvents.hour_in_band(6.0, day), "day band holds its start")
	ok(ChronicleEvents.hour_in_band(18.0, day), "day band holds its end")
	ok(not ChronicleEvents.hour_in_band(3.0, day), "day band rejects 3")
	ok(not ChronicleEvents.hour_in_band(20.0, day), "day band rejects 20")
	ok(ChronicleEvents.hour_in_band(13.37, Vector2(0.0, 24.0)), "0..24 holds everything")


## ---------------------------------------------------------------------------
##  weight_for -- the four hard gates
## ---------------------------------------------------------------------------
func _test_weight_gates() -> void:
	var kind := _synth_kind()
	var open := _ctx(12.0, 1, 0, "BANGOR", 1)
	ok(ChronicleEvents.weight_for(kind, open) > 0.0, "the open context passes every gate")
	eq(ChronicleEvents.weight_for(kind, _ctx(22.0, 1, 0, "BANGOR", 1)), 0.0,
		"gate: hour outside the band")
	eq(ChronicleEvents.weight_for(kind, _ctx(12.0, 3, 0, "BANGOR", 1)), 0.0,
		"gate: season not listed")
	eq(ChronicleEvents.weight_for(kind, _ctx(12.0, 1, 4, "BANGOR", 1)), 0.0,
		"gate: weather not listed")
	eq(ChronicleEvents.weight_for(kind, _ctx(12.0, 1, 0, "BANGOR", 0)), 0.0,
		"gate: rank under min_rank")
	## the gates open when the lists are empty / rank is -1
	var loose := _synth_kind()
	loose["seasons"] = []
	loose["weather"] = []
	loose["min_rank"] = -1
	loose["regions"] = []
	ok(ChronicleEvents.weight_for(loose, _ctx(12.0, 3, 4, "", 0)) > 0.0,
		"empty lists and min_rank -1 gate nothing")
	near(ChronicleEvents.weight_for(loose, _ctx(12.0, 3, 4, "", 0)), 1.0, 1e-6,
		"an unconstrained kind in a neutral context is exactly its base")
	ok(ChronicleEvents.weight_for(loose, _ctx(12.0, 3, 4, "", 0, 0.0, 1.0, 1.0,
		{"wolves": -10.0})) >= 0.0, "weight is never negative")


## ---------------------------------------------------------------------------
##  weight_for -- each multiplier, against a hand-computed number
## ---------------------------------------------------------------------------
func _test_weight_multipliers() -> void:
	var kind := _synth_kind()
	## base 1.0, home region -> x2.0, everything else neutral
	near(ChronicleEvents.weight_for(kind, _ctx(12.0, 1, 0, "BANGOR", 1)), 2.0, 1e-6,
		"home region doubles: 1.0 * 2.0")
	near(ChronicleEvents.weight_for(kind, _ctx(12.0, 1, 0, "PORTLAND", 1)), 0.35, 1e-6,
		"wrong region: 1.0 * 0.35")
	var anywhere := _synth_kind()
	anywhere["regions"] = []
	near(ChronicleEvents.weight_for(anywhere, _ctx(12.0, 1, 0, "PORTLAND", 1)), 1.0, 1e-6,
		"no region preference: 1.0 * 1.0")
	## bias: x(1 + sum over the kind's tags)
	near(ChronicleEvents.weight_for(kind, _ctx(12.0, 1, 0, "BANGOR", 1, 0.0, 1.0, 1.0,
		{"wolves": 0.5})), 3.0, 1e-6, "bias wolves +0.5: 2.0 * 1.5")
	near(ChronicleEvents.weight_for(kind, _ctx(12.0, 1, 0, "BANGOR", 1, 0.0, 1.0, 1.0,
		{"wolves": 0.25, "hunger": 0.25})), 3.0, 1e-6, "bias sums across tags: 2.0 * 1.5")
	near(ChronicleEvents.weight_for(kind, _ctx(12.0, 1, 0, "BANGOR", 1, 0.0, 1.0, 1.0,
		{"goblins": 5.0})), 2.0, 1e-6, "bias on a tag the kind lacks does nothing")
	near(ChronicleEvents.weight_for(kind, _ctx(12.0, 1, 0, "BANGOR", 1, 0.0, 1.0, 1.0,
		{"wolves": -2.0})), 0.1, 1e-6, "bias floor: 2.0 * clamp(1 - 2, 0.05)")
	## alarm: x(1 + 0.6 * alarm)
	near(ChronicleEvents.weight_for(kind, _ctx(12.0, 1, 0, "BANGOR", 1, 0.5)), 2.6, 1e-6,
		"alarm 0.5: 2.0 * 1.3")
	## hunger: x(1 + 0.8 * (1 - stores))
	near(ChronicleEvents.weight_for(kind, _ctx(12.0, 1, 0, "BANGOR", 1, 0.0, 1.0, 0.5)), 2.8, 1e-6,
		"stores 0.5: 2.0 * 1.4")
	## unrest: x(1 + 0.5 * (1 - mood))
	near(ChronicleEvents.weight_for(kind, _ctx(12.0, 1, 0, "BANGOR", 1, 0.0, 0.5, 1.0)), 2.5, 1e-6,
		"mood 0.5: 2.0 * 1.25")
	## all together: 2.0 * 1.5 * 1.3 * 1.4 * 1.25
	near(ChronicleEvents.weight_for(kind, _ctx(12.0, 1, 0, "BANGOR", 1, 0.5, 0.5, 0.5,
		{"wolves": 0.5})), 6.825, 1e-5, "every multiplier at once: 6.825")
	## the pressure multipliers only bite on their tag
	var quiet := _synth_kind()
	quiet["tags"] = ["wolves"]
	near(ChronicleEvents.weight_for(quiet, _ctx(12.0, 1, 0, "BANGOR", 1, 1.0, 0.0, 0.0)), 2.0, 1e-6,
		"alarm/hunger/unrest do nothing to a kind without those tags")
	## full stores and full mood are the neutral point
	near(ChronicleEvents.weight_for(kind, _ctx(12.0, 1, 0, "BANGOR", 1, 0.0, 1.0, 1.0)), 2.0, 1e-6,
		"stores 1 and mood 1 multiply by exactly 1")
	## a different base scales everything
	var heavy := _synth_kind()
	heavy["base"] = 2.5
	near(ChronicleEvents.weight_for(heavy, _ctx(12.0, 1, 0, "BANGOR", 1, 0.5)), 6.5, 1e-6,
		"base 2.5, alarm 0.5: 2.5 * 2.0 * 1.3")


## every catalogue kind can actually fire somewhere
func _test_catalogue_reachable() -> void:
	var dead := 0
	var kinds: Array = ChronicleEvents.KINDS
	for k in kinds:
		if not (k is Dictionary):
			dead += 1
			continue
		var kind: Dictionary = k
		var hours: Vector2 = kind.get("hours", Vector2(0.0, 24.0))
		var seasons: Array = kind.get("seasons", [])
		var weather: Array = kind.get("weather", [])
		var regions: Array = kind.get("regions", [])
		var ctx := _ctx(hours.x, int(seasons[0]) if seasons.size() > 0 else 0,
			int(weather[0]) if weather.size() > 0 else 0,
			str(regions[0]) if regions.size() > 0 else "",
			maxi(int(kind.get("min_rank", -1)), 0))
		if ChronicleEvents.weight_for(kind, ctx) <= 0.0:
			dead += 1
			print("    kind %s has no context it can fire in" % str(kind.get("id", "?")))
	eq(dead, 0, "every kind has a context where its weight is positive")


## ---------------------------------------------------------------------------
##  pick_outcome -- a weighted walk
## ---------------------------------------------------------------------------
func _test_pick_outcome() -> void:
	var kind := _synth_kind()          ## weights 1 : 2 : 7
	eq(str(ChronicleEvents.pick_outcome(kind, 0.0).get("id", "")), "a", "roll 0.0 is the first")
	eq(str(ChronicleEvents.pick_outcome(kind, 0.999).get("id", "")), "c", "roll 0.999 is the last")
	eq(str(ChronicleEvents.pick_outcome(kind, 0.05).get("id", "")), "a", "roll 0.05 is still the first")
	eq(str(ChronicleEvents.pick_outcome(kind, 0.15).get("id", "")), "b", "roll 0.15 is the second")
	eq(str(ChronicleEvents.pick_outcome(kind, 0.5).get("id", "")), "c", "roll 0.5 is the third")
	var empty := _synth_kind()
	empty["outcomes"] = []
	ok(ChronicleEvents.pick_outcome(empty, 0.5).is_empty(), "no outcomes gives {}")
	## 1000 evenly spaced rolls land within 5% of the declared weights
	var counts := {"a": 0, "b": 0, "c": 0}
	var strays := 0
	for i in range(1000):
		var roll := (float(i) + 0.5) / 1000.0
		var got: String = str(ChronicleEvents.pick_outcome(kind, roll).get("id", ""))
		if counts.has(got):
			counts[got] += 1
		else:
			strays += 1
	eq(strays, 0, "every roll lands on a real outcome")
	near(float(counts["a"]) / 1000.0, 0.1, 0.05, "outcome a lands near 10%")
	near(float(counts["b"]) / 1000.0, 0.2, 0.05, "outcome b lands near 20%")
	near(float(counts["c"]) / 1000.0, 0.7, 0.05, "outcome c lands near 70%")
	## every catalogue kind resolves at both ends of the roll
	var whole := true
	for k in ChronicleEvents.KINDS:
		if not (k is Dictionary):
			continue
		var lo: Dictionary = ChronicleEvents.pick_outcome(k, 0.0)
		var hi: Dictionary = ChronicleEvents.pick_outcome(k, 0.999)
		if lo.is_empty() or hi.is_empty() or not lo.has("id") or not hi.has("id"):
			whole = false
	ok(whole, "every catalogue kind picks an outcome at roll 0 and 0.999")


## ---------------------------------------------------------------------------
##  boot()
## ---------------------------------------------------------------------------
func _test_boot() -> void:
	var c := _make()
	var n := c.places.size()
	ok(n > 0, "boot() populates places (%d)" % n)
	c.boot()
	c.boot()
	eq(c.places.size(), n, "boot() x3 leaves the place count alone")
	var names := {}
	var dupes := false
	var shaped := true
	for p in c.places:
		if not (p is Dictionary):
			shaped = false
			continue
		var nm: String = str(p.get("name", ""))
		if names.has(nm) or nm.is_empty():
			dupes = true
		names[nm] = true
		for k in ["name", "pos", "y", "rank", "region", "mood", "stores", "alarm", "watch", "rumours"]:
			if not p.has(k):
				shaped = false
				print("    place %s missing %s" % [nm, k])
		if not (p.get("pos") is Vector2 and p.get("rumours") is Array):
			shaped = false
		var rk: int = int(p.get("rank", -1))
		if rk < 0 or rk > 2:
			shaped = false
	ok(not dupes, "no duplicate place names after three boots")
	ok(shaped, "every place has the declared shape")
	ok(_places_in_range(c), "every place value sits in 0..1 after boot")
	eq(c.active.size(), 0, "nothing is active before the first advance")
	eq(c.resolved.size(), 0, "nothing is resolved before the first advance")
	near(c.days, 0.0, 1e-9, "the clock starts at day 0")
	ok(c.world_seed == SEED, "boot() keeps the world seed")
	## force=true rebuilds, and the rebuild is the same world
	c.boot(true)
	eq(c.places.size(), n, "boot(force) rebuilds the same number of places")
	## constants are the shape the design says
	ok(Chronicle.STEP_HOURS > 0.0 and Chronicle.STEP_HOURS <= 1.0, "the step is a fraction of an hour")
	ok(Chronicle.MAX_ACTIVE > 0, "MAX_ACTIVE is positive")
	ok(Chronicle.RUMOUR_DAYS > 0.0, "rumours live a positive number of days")
	ok(Chronicle.BIAS_HALFLIFE_DAYS > 0.0, "bias has a positive half-life")
	ok(Chronicle.RESOLVED_KEEP > 0, "the resolved ring holds something")
	c.queue_free()


## ---------------------------------------------------------------------------
##  place lookups
## ---------------------------------------------------------------------------
func _test_lookups() -> void:
	var c := _make()
	if c.places.is_empty():
		ok(false, "lookups: no places to look up")
		return
	var p0: Dictionary = c.places[0]
	var nm: String = str(p0.get("name", ""))
	eq(str(c.place_by_name(nm).get("name", "")), nm, "place_by_name finds a place")
	ok(c.place_by_name("no_such_place_9").is_empty(), "place_by_name of nothing is {}")
	var at := _place_pos(p0)
	eq(str(c.nearest_place(at).get("name", "")), nm, "nearest_place on top of a place is that place")
	eq(str(c.nearest_place(at + Vector3(30.0, 0.0, -30.0)).get("name", "")), nm,
		"nearest_place a stone's throw away is still that place")
	ok(c.nearest_place(Vector3(9.0e6, 0.0, 9.0e6), 1200.0).is_empty(),
		"nearest_place with nothing within reach is {}")
	## the farthest place from p0 is not p0's nearest
	var far: Dictionary = p0
	var far_d := 0.0
	for p in c.places:
		var d: float = (p.get("pos", Vector2.ZERO) as Vector2).distance_to(p0.get("pos", Vector2.ZERO))
		if d > far_d:
			far_d = d
			far = p
	if far_d > 0.0:
		eq(str(c.nearest_place(_place_pos(far)).get("name", "")), str(far.get("name", "")),
			"nearest_place at the far end of the map is the far place")
	ok(c.events_near(at, 1.0e7) is Array, "events_near returns an Array")
	eq(c.events_near(at, 1.0e7).size(), 0, "events_near is empty before anything fires")
	ok(c.rumours_at(at, 3) is Array, "rumours_at returns an Array")
	ok(c.pressure_at(at, "wolves") is float, "pressure_at returns a float")
	c.queue_free()


## ---------------------------------------------------------------------------
##  determinism -- step size must not change the story
## ---------------------------------------------------------------------------
func _test_determinism() -> void:
	var a := _make()
	var b := _make()
	var c := _make()
	a.advance(240.0)
	for i in range(240):
		b.advance(1.0)
	for i in range(960):
		c.advance(0.25)
	near(a.days, 10.0, 1e-6, "advance(240) is ten days")
	near(b.days, a.days, 1e-6, "240 x advance(1) reaches the same day")
	near(c.days, a.days, 1e-6, "960 x advance(0.25) reaches the same day")
	ok(a.resolved.size() > 0, "ten days resolve something (%d)" % a.resolved.size())
	var sa := _resolved_seq(a)
	var sb := _resolved_seq(b)
	var sc := _resolved_seq(c)
	ok(sa == sb, "one big step and 240 hour steps resolve the same sequence\n    A: %s\n    B: %s" % [sa, sb])
	ok(sa == sc, "quarter-hour steps resolve the same sequence too\n    A: %s\n    C: %s" % [sa, sc])
	eq(_uid_seq(a.resolved), _uid_seq(b.resolved), "resolved uids match across step sizes")
	eq(_uid_seq(a.active), _uid_seq(b.active), "active uids match across step sizes")
	eq(_uid_seq(a.active), _uid_seq(c.active), "active uids match at quarter-hour steps too")
	## the float clock may carry epsilon noise between step sizes, so the bias
	## pool is compared by which tags it holds, not by digest
	var ta: Array = a.bias.keys()
	var tb: Array = b.bias.keys()
	ta.sort()
	tb.sort()
	eq(",".join(PackedStringArray(ta)), ",".join(PackedStringArray(tb)),
		"the same tags sit in the bias pool across step sizes")
	eq(a.places.size(), b.places.size(), "the same places across step sizes")
	## and a different seed is a different world
	var d := _make(SEED + 1)
	d.advance(240.0)
	ok(_resolved_seq(d) != sa or _digest(d.to_dict()) != _digest(a.to_dict()),
		"a different seed tells a different story")
	for x in [a, b, c, d]:
		x.queue_free()


## ---------------------------------------------------------------------------
##  events age out of active and into resolved
## ---------------------------------------------------------------------------
func _test_events_age() -> void:
	var c := _make()
	var guard := 0
	while c.active.is_empty() and guard < 400:
		c.advance(6.0)
		guard += 1
	ok(not c.active.is_empty(), "something fires inside a hundred days")
	if c.active.is_empty():
		c.queue_free()
		return
	var ev: Dictionary = c.active[0]
	var shaped := true
	for k in EVENT_KEYS:
		if not ev.has(k):
			shaped = false
			print("    live event missing %s" % k)
	ok(shaped, "a live event has the declared shape")
	eq(str(ev.get("state", "")), "active", "a live event is active")
	eq(str(ev.get("outcome", "x")), "", "a live event has no outcome yet")
	eq(str(ev.get("line", "x")), "", "a live event has no line yet")
	ok(not ChronicleEvents.by_id(str(ev.get("kind", ""))).is_empty(), "a live event names a real kind")
	var born: float = float(ev.get("born", 0.0))
	var ends: float = float(ev.get("ends", 0.0))
	ok(ends > born, "an event ends after it is born")
	ok(born <= c.days and c.days <= ends, "the clock sits inside the event's life")
	var uid: int = int(ev.get("uid", -1))
	## the event is visible near its spot and absent far away
	var pos: Vector2 = ev.get("pos", Vector2.ZERO)
	var here := Vector3(pos.x, 0.0, pos.y)
	var seen := false
	for e in c.events_near(here, 50.0):
		if e is Dictionary and int(e.get("uid", -2)) == uid:
			seen = true
	ok(seen, "events_near finds the event at its own position")
	var seen_far := false
	for e in c.events_near(here + Vector3(5.0e6, 0.0, 0.0), 50.0):
		if e is Dictionary and int(e.get("uid", -2)) == uid:
			seen_far = true
	ok(not seen_far, "events_near does not find it half a world away")
	## step past `ends`
	c.advance(maxf((ends - c.days) * 24.0, 0.0) + Chronicle.STEP_HOURS * 2.0)
	var still_active := false
	for e in c.active:
		if e is Dictionary and int(e.get("uid", -2)) == uid:
			still_active = true
	ok(not still_active, "past its end the event has left active")
	var done: Dictionary = {}
	for e in c.resolved:
		if e is Dictionary and int(e.get("uid", -2)) == uid:
			done = e
	ok(not done.is_empty(), "past its end the event sits in resolved")
	eq(str(done.get("state", "")), "resolved", "a resolved event says so")
	ok(not str(done.get("outcome", "")).is_empty(), "a resolved event has an outcome")
	ok(not str(done.get("line", "")).is_empty(), "a resolved event has a line")
	ok(not str(done.get("line", "")).contains("%s"), "the line has had its place name filled in")
	## the outcome is one the kind declares
	var kind: Dictionary = ChronicleEvents.by_id(str(done.get("kind", "")))
	var declared := false
	for o in kind.get("outcomes", []):
		if o is Dictionary and str(o.get("id", "")) == str(done.get("outcome", "")):
			declared = true
	ok(declared, "the outcome is one the kind declares")
	c.queue_free()


## ---------------------------------------------------------------------------
##  rumours decay, and rumours_at reads the nearest place newest-first
## ---------------------------------------------------------------------------
func _test_rumours() -> void:
	var c := _make()
	c.advance(24.0)
	if c.places.is_empty():
		ok(false, "rumours: no places")
		return
	var p0: Dictionary = c.places[0]
	var here := _place_pos(p0)
	var rum: Array = p0["rumours"]
	var stale := "ZZ_STALE_RUMOUR"
	var fresh := "ZZ_FRESH_RUMOUR"
	rum.append({"text": stale, "day": c.days - Chronicle.RUMOUR_DAYS - 1.0, "from": "test", "kind": "test"})
	rum.append({"text": fresh, "day": c.days, "from": "test", "kind": "test"})
	c.advance(1.0)
	var has_stale := false
	var has_fresh := false
	for r in c.places[0]["rumours"]:
		if r is Dictionary:
			if str(r.get("text", "")) == stale:
				has_stale = true
			if str(r.get("text", "")) == fresh:
				has_fresh = true
	ok(not has_stale, "a rumour older than RUMOUR_DAYS is gone")
	ok(has_fresh, "a fresh rumour is still there")
	## a rumour that is just inside the window survives; one just past it does not
	rum = c.places[0]["rumours"]
	var edge_in := "ZZ_EDGE_IN"
	var edge_out := "ZZ_EDGE_OUT"
	rum.append({"text": edge_in, "day": c.days - Chronicle.RUMOUR_DAYS + 0.5, "from": "test", "kind": "test"})
	rum.append({"text": edge_out, "day": c.days - Chronicle.RUMOUR_DAYS - 0.5, "from": "test", "kind": "test"})
	c.advance(Chronicle.STEP_HOURS)
	var in_ok := false
	var out_ok := true
	for r in c.places[0]["rumours"]:
		if r is Dictionary:
			if str(r.get("text", "")) == edge_in:
				in_ok = true
			if str(r.get("text", "")) == edge_out:
				out_ok = false
	ok(in_ok, "a rumour half a day inside the window survives")
	ok(out_ok, "a rumour half a day past the window is pruned")
	## rumours_at: newest first, capped, and from the nearest place
	rum = c.places[0]["rumours"]
	for i in range(5):
		rum.append({"text": "ZZ_STACK_%d" % i, "day": c.days - 0.05 * float(i + 1), "from": "test", "kind": "test"})
	var got: Array = c.rumours_at(here, 3)
	ok(got.size() <= 3, "rumours_at never returns more than limit (%d)" % got.size())
	ok(got.size() > 0, "rumours_at returns something where rumours are")
	eq(c.rumours_at(here, 1).size(), 1, "rumours_at limit 1 returns one")
	var ordered := true
	var all_here := true
	var last_day := INF
	for r in got:
		if not (r is Dictionary):
			ordered = false
			continue
		var d: float = float(r.get("day", 0.0))
		if d > last_day + 1e-9:
			ordered = false
		last_day = d
		var found := false
		for mine in c.places[0]["rumours"]:
			if mine is Dictionary and str(mine.get("text", "")) == str(r.get("text", "")):
				found = true
		if not found:
			all_here = false
	ok(ordered, "rumours_at returns newest first")
	ok(all_here, "rumours_at reads the nearest place's own rumours")
	## the top of the pile is the freshest one we planted (or something at least as new)
	if got.size() > 0 and got[0] is Dictionary:
		ok(float(got[0].get("day", -1.0)) >= c.days - 0.05 - 1e-9,
			"the first rumour back is at least as fresh as the freshest planted")
	## a far place does not hear p0's rumours
	var far: Dictionary = p0
	var far_d := 0.0
	for p in c.places:
		var d: float = (p.get("pos", Vector2.ZERO) as Vector2).distance_to(p0.get("pos", Vector2.ZERO))
		if d > far_d:
			far_d = d
			far = p
	if far_d > 0.0:
		var leaked := false
		for r in c.rumours_at(_place_pos(far), 10):
			if r is Dictionary and str(r.get("text", "")).begins_with("ZZ_STACK_"):
				leaked = true
		ok(not leaked, "rumours_at at the far place does not hand back the near place's rumours")
	## every rumour anywhere has the declared shape and a sane day
	c.advance(24.0 * 20.0)
	var shaped := true
	var any := 0
	for p in c.places:
		for r in p.get("rumours", []):
			any += 1
			if not (r is Dictionary):
				shaped = false
				continue
			for k in RUMOUR_KEYS:
				if not r.has(k):
					shaped = false
			var d: float = float(r.get("day", -1.0))
			if d > c.days + 1e-6 or d < c.days - Chronicle.RUMOUR_DAYS - 1.0:
				shaped = false
	ok(shaped, "every rumour has text/day/from/kind and a day inside the window")
	ok(any > 0, "twenty days in, the places have rumours (%d)" % any)
	c.queue_free()


## ---------------------------------------------------------------------------
##  consequence bias -- it biases, and it decays
## ---------------------------------------------------------------------------
func _test_bias() -> void:
	## a wolves-tagged kind from the real catalogue
	var wolf: Dictionary = {}
	for k in ChronicleEvents.KINDS:
		if k is Dictionary and (k.get("tags", []) as Array).has("wolves"):
			wolf = k
			break
	ok(not wolf.is_empty(), "the catalogue has a wolves-tagged kind")
	if wolf.is_empty():
		return
	var hours: Vector2 = wolf.get("hours", Vector2(0.0, 24.0))
	var seasons: Array = wolf.get("seasons", [])
	var weather: Array = wolf.get("weather", [])
	var regions: Array = wolf.get("regions", [])
	var base_ctx := _ctx(hours.x, int(seasons[0]) if seasons.size() > 0 else 0,
		int(weather[0]) if weather.size() > 0 else 0,
		str(regions[0]) if regions.size() > 0 else "",
		maxi(int(wolf.get("min_rank", -1)), 0))
	var w0: float = ChronicleEvents.weight_for(wolf, base_ctx)
	ok(w0 > 0.0, "the wolves kind can fire in its own context")

	var c := _make()
	## the outcome's consequence, forced: bias {"wolves": +1.0}, plus a clean
	## tag nothing in the catalogue can top up, so its decay is measured alone
	c.bias["wolves"] = c.bias.get("wolves", 0.0) + 1.0
	c.bias[CLEAN_TAG] = 1.0
	var biased_ctx := base_ctx.duplicate()
	biased_ctx["bias"] = c.bias
	var w1: float = ChronicleEvents.weight_for(wolf, biased_ctx)
	ok(w1 > w0, "wolves bias +1 raises the wolves kind's weight (%.3f -> %.3f)" % [w0, w1])
	near(w1 / maxf(w0, 1e-9), 2.0, 1e-6, "and by exactly (1 + 1.0): twice")
	## one half-life
	c.advance(Chronicle.BIAS_HALFLIFE_DAYS * 24.0)
	var half: float = float(c.bias.get(CLEAN_TAG, 0.0))
	near(half, 0.5, 0.1, "after one half-life the clean tag is about half")
	ok(half < 1.0, "the clean tag has decayed at all")
	## four half-lives
	c.advance(Chronicle.BIAS_HALFLIFE_DAYS * 24.0 * 3.0)
	var late: float = float(c.bias.get(CLEAN_TAG, 0.0))
	ok(late < half, "and keeps decaying")
	ok(late < 0.1, "after four half-lives the clean tag is under 0.1 (%.4f)" % late)
	ok(late >= 0.0, "decay never crosses zero")
	var wolves_late: float = float(c.bias.get("wolves", 0.0))
	ok(wolves_late < 1.0, "the forced wolves bias has decayed toward 0 (%.4f)" % wolves_late)
	## no bias value anywhere is NaN
	var finite := true
	for t in c.bias:
		if not is_finite(float(c.bias[t])):
			finite = false
	ok(finite, "every bias value is finite")
	c.queue_free()


## ---------------------------------------------------------------------------
##  save round-trip
## ---------------------------------------------------------------------------
func _test_save_round_trip() -> void:
	var a := _make()
	a.advance(24.0 * 30.0)
	var d: Dictionary = a.to_dict()
	ok(not d.is_empty(), "to_dict() carries something")
	var b := _make()
	b.from_dict(d)
	near(b.days, a.days, 1e-9, "from_dict restores the clock")
	eq(b.places.size(), a.places.size(), "from_dict restores the place count")
	eq(_uid_seq(b.active), _uid_seq(a.active), "from_dict restores the active uids")
	eq(_uid_seq(b.resolved), _uid_seq(a.resolved), "from_dict restores the resolved ring")
	eq(_digest(b.report()), _digest(a.report()), "report() digests match right after the load")
	a.advance(24.0 * 10.0)
	b.advance(24.0 * 10.0)
	eq(_digest(a.report()), _digest(b.report()),
		"ten days on, report() digests still match\n    A: %s\n    B: %s" % [
			_resolved_seq(a), _resolved_seq(b)])
	eq(_resolved_seq(a), _resolved_seq(b), "ten days on, the resolved sequences match")
	eq(_digest(a.to_dict()), _digest(b.to_dict()), "ten days on, to_dict() digests match")
	## a save must survive a from_dict of its own to_dict without drifting
	var again := _make()
	again.from_dict(a.to_dict())
	eq(_digest(again.to_dict()), _digest(a.to_dict()), "to_dict -> from_dict -> to_dict is a fixed point")
	## from_dict of garbage does not wreck a booted Chronicle
	var g := _make()
	g.from_dict({})
	ok(g.places.size() > 0, "from_dict({}) leaves a booted world standing")
	ok(_places_in_range(g), "and its values in range")
	for x in [a, b, again, g]:
		x.queue_free()


## ---------------------------------------------------------------------------
##  200 days -- the caps hold and nothing leaks out of range
## ---------------------------------------------------------------------------
func _test_long_run() -> void:
	var c := _make()
	_sig_fired = 0
	_sig_resolved = 0
	c.event_fired.connect(_fired)
	c.event_resolved.connect(_resolved_sig)
	var max_active := 0
	var max_resolved := 0
	var in_range := true
	var states_ok := true
	var uids_unique := true
	var total_seen := {}
	for step in range(800):            ## 200 days in six-hour bites
		c.advance(6.0)
		max_active = maxi(max_active, c.active.size())
		max_resolved = maxi(max_resolved, c.resolved.size())
		if not _places_in_range(c):
			in_range = false
		var seen := {}
		for e in c.active:
			if not (e is Dictionary):
				states_ok = false
				continue
			if str(e.get("state", "")) != "active" or float(e.get("ends", 0.0)) < c.days - Chronicle.STEP_HOURS / 24.0 - 1e-6:
				states_ok = false
			var u: int = int(e.get("uid", -1))
			if seen.has(u):
				uids_unique = false
			seen[u] = true
			total_seen[u] = true
		for e in c.resolved:
			if e is Dictionary:
				if str(e.get("state", "")) != "resolved":
					states_ok = false
				var u: int = int(e.get("uid", -1))
				if seen.has(u):
					uids_unique = false
				seen[u] = true
	near(c.days, 200.0, 1e-6, "the run covers 200 days")
	ok(max_active <= Chronicle.MAX_ACTIVE, "active never exceeds MAX_ACTIVE (peak %d)" % max_active)
	ok(max_resolved <= Chronicle.RESOLVED_KEEP, "resolved never exceeds RESOLVED_KEEP (peak %d)" % max_resolved)
	ok(in_range, "no place value ever leaves 0..1")
	ok(states_ok, "active events are active and unexpired; resolved events say resolved")
	ok(uids_unique, "no uid is ever in two lists or twice in one")
	ok(total_seen.size() > 10, "two hundred days fire a real number of events (%d)" % total_seen.size())
	ok(_sig_fired > 0, "event_fired is emitted (%d)" % _sig_fired)
	ok(_sig_resolved > 0, "event_resolved is emitted (%d)" % _sig_resolved)
	ok(_sig_fired >= _sig_resolved, "nothing resolves that never fired")
	ok(_sig_resolved >= c.resolved.size(), "the resolved ring never holds more than was resolved")
	## the world is not frozen: some place has moved off its boot values
	var fresh := _make()
	var moved := false
	for i in range(mini(c.places.size(), fresh.places.size())):
		for k in PLACE_VALUE_KEYS:
			if absf(float(c.places[i].get(k, 0.0)) - float(fresh.places[i].get(k, 0.0))) > 1e-6:
				moved = true
	ok(moved, "two hundred days move at least one place value")
	## every resolved event's line is filled and its kind is real
	var lines_ok := true
	for e in c.resolved:
		if not (e is Dictionary):
			lines_ok = false
			continue
		if str(e.get("line", "")).is_empty() or str(e.get("line", "")).contains("%s") \
				or str(e.get("outcome", "")).is_empty() \
				or ChronicleEvents.by_id(str(e.get("kind", ""))).is_empty():
			lines_ok = false
	ok(lines_ok, "every resolved event has a real kind, an outcome and a filled line")
	## report() is a Dictionary and stable when nothing advances
	var rep: Dictionary = c.report()
	ok(not rep.is_empty(), "report() carries something")
	eq(_digest(c.report()), _digest(rep), "report() is stable between advances")
	## pressure is a finite number everywhere
	var press_ok := true
	for p in c.places:
		var v: float = c.pressure_at(_place_pos(p), "wolves")
		if not is_finite(v):
			press_ok = false
	ok(press_ok, "pressure_at is finite at every place")
	c.queue_free()
	fresh.queue_free()



## ---------------------------------------------------------------------------
##  bound to a real clock -- the sim's calendar must be the SKY's calendar
##
##  Added 2026-09-06 after the round's critic found that nothing in this suite
##  ever bound a DayNight or called _process, so a Chronicle running a whole
##  season out of step with the sky passed all 182 assertions.
## ---------------------------------------------------------------------------
class FakeClock extends Node:
	var day := 0.0
	var hour := 0.0


func _test_clock_binding() -> void:
	## DayNight's own boot values: day 30, hour 19.7 -- mid-summer, dusk.
	var clock := FakeClock.new()
	clock.day = 30.0
	clock.hour = 19.7
	root.add_child(clock)
	Chronicle.bind(clock, null)

	var c := _make()
	eq(c.resolved.size(), 0, "clock: a booted Chronicle has no history yet")
	c._process(0.016)                       ## the first frame: adopt the sky
	var now := clock.day + clock.hour / 24.0
	near(c.days, now, Chronicle.STEP_HOURS / 24.0 + 1e-6,
		"clock: the first frame adopts the sky's calendar (%.4f vs %.4f)" % [c.days, now])
	near(fposmod(c.days * 24.0, 24.0), clock.hour, Chronicle.STEP_HOURS + 1e-6,
		"clock: the sim's hour is the game's hour")
	eq(Chronicle.season_at(c.days), int(fposmod(now, 96.0) / 24.0) % 4,
		"clock: the sim's season is the game's season")
	ok(c.resolved.size() > 0, "clock: adopting primes a week of history (%d resolved)" % c.resolved.size())
	ok(c.days - float(c.resolved[0].get("born", 0.0)) <= Chronicle.PRIME_DAYS + 1.0,
		"clock: the primed history is a week deep, not a month")
	## every primed event fired inside its own hour band, by the GAME clock
	var bands_ok := true
	for e in c.resolved:
		var kind: Dictionary = ChronicleEvents.by_id(str(e.get("kind", "")))
		if kind.is_empty():
			continue
		if not ChronicleEvents.hour_in_band(fposmod(float(e.get("born", 0.0)) * 24.0, 24.0),
				kind.get("hours", Vector2(0.0, 24.0))):
			bands_ok = false
			print("    %s fired at hour %.2f, band %s" % [
				str(e.get("kind", "")), fposmod(float(e.get("born", 0.0)) * 24.0, 24.0),
				str(kind.get("hours", Vector2.ZERO))])
	ok(bands_ok, "clock: every primed event fired inside its own hour band")
	## a second frame with the clock unmoved is a no-op
	var before := c.days
	var steps_before: int = c._steps
	c._process(0.016)
	near(c.days, before, 1e-9, "clock: a frame with a still clock changes nothing")
	eq(c._steps, steps_before, "clock: and runs no steps")
	## the clock moves on: the sim follows
	clock.hour = 21.7
	c._process(0.016)
	ok(c.days > before, "clock: two game hours later the sim has moved")
	near(c.days, clock.day + clock.hour / 24.0, Chronicle.STEP_HOURS / 24.0 + 1e-6,
		"clock: and it lands where the sky says")
	## the sky menu winds time BACKWARDS: not a season of history
	var mark := c.days
	var smark: int = c._steps
	clock.hour = 6.0
	c._process(0.016)
	near(c.days, mark, 1e-9, "clock: a clock wound backwards adds no history")
	eq(c._steps, smark, "clock: and runs no steps")
	c.queue_free()

	## a save that predates the Chronicle: apply_state hands us {} and then
	## moves the clock a long way. That must prime a week, never invent a month.
	var g := _make()
	g._process(0.016)
	var primed: int = g._ran
	g.from_dict({})
	ok(g.places.size() > 0, "clock: a legacy load leaves the world standing")
	clock.day = 200.0
	clock.hour = 12.0
	g._process(0.016)
	var jumped: int = g._ran - primed
	ok(jumped <= int(Chronicle.PRIME_DAYS * 24.0 / Chronicle.STEP_HOURS) + 4,
		"clock: a legacy load re-anchors and primes a week, not a month (%d steps)" % jumped)
	near(g.days, clock.day + clock.hour / 24.0, Chronicle.STEP_HOURS / 24.0 + 1e-6,
		"clock: and lands on the saved clock")
	g.queue_free()

	## catching up is throttled: a month handed over in one frame does not run
	## a month of steps in that frame
	var h := _make()
	h._process(0.016)
	var base: int = h._ran
	clock.day = 230.0
	clock.hour = 12.0
	h._last_clock = 200.5              ## pretend we were watching all along
	h._process(0.016)
	ok(h._ran - base <= Chronicle.CATCHUP_STEPS,
		"clock: one frame of catch-up runs at most CATCHUP_STEPS (%d)" % (h._ran - base))
	## and the rest arrives over the following frames
	for i in range(200):
		h._process(0.016)
	ok(h._ran - base > Chronicle.CATCHUP_STEPS, "clock: the backlog does drain over later frames")
	h.queue_free()

	Chronicle.bind(null, null)
	clock.queue_free()



## ---------------------------------------------------------------------------
##  the optional fifth gate -- a kind whose prose is a lie outside its regions
##
##  Added 2026-09-06: the sim was cheerfully reporting "wreckage on the beach
##  east of Farmington", which is eighty miles inland.
## ---------------------------------------------------------------------------
func _test_region_gate() -> void:
	ok(ChronicleEvents.problems().is_empty(),
		"catalogue: problems() is clean (%s)" % ",".join(ChronicleEvents.problems()))
	var gated := 0
	var gated_ok := true
	for k in ChronicleEvents.KINDS:
		var kd := k as Dictionary
		if not bool(kd.get("gate_regions", false)):
			continue
		gated += 1
		var regions: Array = kd.get("regions", [])
		if regions.is_empty():
			gated_ok = false
			continue
		## inside one of its own regions it can happen; outside, never
		var home := _ctx(float((kd.get("hours", Vector2(0.0, 24.0)) as Vector2).x),
			int((kd.get("seasons", []) as Array)[0]) if not (kd.get("seasons", []) as Array).is_empty() else 0,
			int((kd.get("weather", []) as Array)[0]) if not (kd.get("weather", []) as Array).is_empty() else 0,
			String(regions[0]), maxi(int(kd.get("min_rank", -1)), 0))
		var away := home.duplicate()
		away["region"] = "NOWHERE AT ALL"
		if ChronicleEvents.weight_for(kd, home) <= 0.0:
			gated_ok = false
			print("    gated kind %s cannot fire at home" % str(kd.get("id", "")))
		if ChronicleEvents.weight_for(kd, away) != 0.0:
			gated_ok = false
			print("    gated kind %s fired outside its regions" % str(kd.get("id", "")))
	ok(gated >= 3, "at least three kinds are region-gated (%d)" % gated)
	ok(gated_ok, "every gated kind fires at home and nowhere else")
	## the sea kinds in particular, because those are the ones that read as a bug
	for id in ["boat_overdue", "wreck_ashore", "herring_run"]:
		var kd: Dictionary = ChronicleEvents.by_id(id)
		ok(not kd.is_empty(), "the catalogue has %s" % id)
		ok(bool(kd.get("gate_regions", false)), "%s is region-gated" % id)
		var inland := _ctx(float((kd.get("hours", Vector2(0.0, 24.0)) as Vector2).x),
			int((kd.get("seasons", []) as Array)[0]) if not (kd.get("seasons", []) as Array).is_empty() else 0,
			int((kd.get("weather", []) as Array)[0]) if not (kd.get("weather", []) as Array).is_empty() else 0,
			"AROOSTOOK", 2)
		near(ChronicleEvents.weight_for(kd, inland), 0.0, 1e-9, "%s cannot happen at Aroostook" % id)
	## and an UNgated kind with a region preference still reaches the rest of
	## the map -- the gate must be opt-in, not the new default
	var soft: Dictionary = {}
	for k in ChronicleEvents.KINDS:
		var kd := k as Dictionary
		if not bool(kd.get("gate_regions", false)) and not (kd.get("regions", []) as Array).is_empty():
			soft = kd
			break
	ok(not soft.is_empty(), "the catalogue still has a soft region preference")
	if not soft.is_empty():
		var away := _ctx(float((soft.get("hours", Vector2(0.0, 24.0)) as Vector2).x),
			int((soft.get("seasons", []) as Array)[0]) if not (soft.get("seasons", []) as Array).is_empty() else 0,
			int((soft.get("weather", []) as Array)[0]) if not (soft.get("weather", []) as Array).is_empty() else 0,
			"NOWHERE AT ALL", maxi(int(soft.get("min_rank", -1)), 0))
		ok(ChronicleEvents.weight_for(soft, away) > 0.0,
			"a soft-preference kind still fires away from home")
	## the whole 200-day world never tells a coastal story inland
	var c := _make()
	c.advance(24.0 * 120.0)
	var lies := 0
	for e in c.resolved:
		var ev := e as Dictionary
		var kd: Dictionary = ChronicleEvents.by_id(String(ev.get("kind", "")))
		if kd.is_empty() or not bool(kd.get("gate_regions", false)):
			continue
		var pl: Dictionary = c.place_by_name(String(ev.get("place", "")))
		if pl.is_empty():
			continue
		if not (kd.get("regions", []) as Array).has(String(pl.get("region", ""))):
			lies += 1
			print("    %s at %s (%s)" % [str(ev.get("kind", "")), str(ev.get("place", "")), str(pl.get("region", ""))])
	eq(lies, 0, "a hundred and twenty days tells no gated story in the wrong region")
	c.queue_free()


func _finish() -> void:
	print("ChronicleTests: %d passed, %d failed (%d assertions)" % [_pass, _fail, _pass + _fail])
	if _pass + _fail < MIN_ASSERTIONS:
		print("  LOST A SECTION: only %d assertions ran (floor %d)" % [_pass + _fail, MIN_ASSERTIONS])
		_fail += 1
	quit(1 if _fail > 0 else 0)
