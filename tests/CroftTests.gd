extends SceneTree

# =============================================================================
# tests/CroftTests.gd -- somebody lives out here (2026-09-10, WORLD).
#
#   godot --headless --path . --script res://tests/CroftTests.gd
#
# Nothing here needs terrain, a Player, World.tscn or a pixel. The croft's day
# is a PURE FUNCTION -- `Crofts.routine_at(croft, day, sky, season, state)` --
# so "a gale at ten in the morning bars the shutters" is a call with five
# arguments rather than a thing you stand in a field and wait for.
#
# Four sections carry more weight than the rest:
#
#   `washing` -- the one beat in this file that is a STATE and not a query,
#   and the reason for the split. If "out" were derived from the current sky
#   the line would only ever be out while the weather was fine, so nothing
#   could ever be caught by a turn in it: the soak would be unreachable and
#   every assertion aimed at it would pass for the wrong reason. This section
#   drives the whole cycle -- hung, fetched, SOAKED, dried -- and asserts the
#   ORDER of the two branches that decide it.
#
#   `year` -- the woodpile is the only economy in here and the whole point of
#   it, so it is checked the way the feature is actually experienced: a full
#   ninety-six-day year, one croft, and the shape of the curve. Autumn fills
#   it; winter spends two-thirds of it; a household that loses its autumn does
#   not see the far side of winter.
#
#   `chronicle` and `feed` -- the REAL front doors of the two collaborators
#   this file calls into. Three mutations of `Chronicle.deposit_rumour`
#   survived the Wayfarers' 128/0 green because the only suite that used it
#   used a stub instead (2026-09-09). Crofts calls `Chronicle.pressure_at`,
#   `Chronicle.sky_at`, `Chronicle.season_at` and `RumourFeed.offer`, so each
#   of those gets exercised against the real class here.
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
var _cold: Array = []
var _shut: Array = []


# --------------------------------------------------------------------- stubs

class FakeSky extends Node:
	## Everything Crofts asks a Chronicle for on the hot path, and nothing
	## else. The REAL Chronicle gets its own section below -- this exists so
	## that "a gale on day nine" is a fixture rather than a wait.
	var sky := 0
	var season := 0
	var press: Dictionary = {}

	func sky_at(_t: float) -> int:
		return sky

	func season_at(_t: float) -> int:
		return season

	func pressure_at(_at: Vector3, tag: String) -> float:
		return float(press.get(tag, 0.0))


class FakeGround extends Node:
	## A ridge running along +x: ground rises with z. Bound as the ground
	## probe, it makes "the yard went to the drier side" a measurable claim
	## rather than a hope.
	func _surface_y(p: Vector3) -> float:
		return p.z * 0.05


class CountFeed extends Node:
	## Used for exactly ONE assertion, and it earns its place. `sense()`'s own
	## de-dup and the real feed's `_heard` memory are two independent doors on
	## the same result, so a mutation that deleted the first walked through
	## the second and the suite never noticed. This one always accepts, which
	## leaves `sense()`'s memory as the only thing that can refuse.
	var n := 0

	func offer(_text: String, _voice: String, _kind := "", _day := 0.0) -> bool:
		n += 1
		return true


class FakePlayer extends Node3D:
	## Only what `RumourFeed.muted_now` reads. Without one the real feed is
	## muted by definition and every `offer` would be refused, which would
	## make the feed section assert nothing at all.
	var menu_open := ""
	var wheel_open := false
	var input_locked := false
	var health := 100.0


# ------------------------------------------------------------------ harness

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

func _ring(n: int, r: float) -> Array:
	var ranks := [2, 0, 1, 0, 2, 1, 0, 1]
	var out: Array = []
	for i in n:
		var a := TAU * float(i) / float(n)
		out.append({"name": "P%d" % i, "pos": Vector2(cos(a) * r, sin(a) * r),
			"rank": int(ranks[i % ranks.size()])})
	return out


func _mk_net(rows: Array) -> RoadNet:
	var n := RoadNet.new()
	n.build(rows)
	return n


func _mk_cr(net: RoadNet, chron: Object = null, seed_v := 20260910) -> Crofts:
	var c := Crofts.new()
	c.world_seed = seed_v
	c.net = net
	c.chron = chron
	c.boot(true)
	return c


func _croft(jit := 0.5, kind := "croft") -> Dictionary:
	## A hand-built croft for the pure-function sections. `routine_at` reads
	## only `jit` and `kind` off it, and this file asserts that too.
	return {"id": "t0", "name": "Test's croft", "kind": kind, "jit": jit,
		"pos": Vector2.ZERO, "from": "P0", "to": "P1"}


func _st(stores := 150.0, wash := "none", shut_until := -1.0) -> Dictionary:
	return {"stores": stores, "wash": wash, "dry_h": 0.0,
		"shut_until": shut_until, "cold_h": 0.0, "was_cold": false,
		"alarm_day": -1.0}


func _day(d: int, hour: float) -> float:
	return float(d) + hour / 24.0


func _set_clock(cr: Crofts, d: float) -> void:
	## Park the sim at a given day WITHOUT replaying the history in between.
	## `days` has to move with `_hours` or every read before the first
	## `advance` is taken against a clock the sim has already left.
	cr._hours = d * 24.0
	cr.days = d
	cr._steps = int(cr._hours / Crofts.STEP_HOURS)


# --------------------------------------------------------------------- entry

func _initialize() -> void:
	print("\n=== CroftTests ===")


func _process(_d: float) -> bool:
	_t_roster()
	_t_siting()
	_t_determinism()
	_t_day()
	_t_weather()
	_t_season()
	_t_washing()
	_t_woodpile()
	_t_year()
	_t_alarm()
	_t_chronicle()
	_t_feed()
	_t_save()
	_t_staging()
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


# ------------------------------------------------------------------- roster

func _t_roster() -> void:
	claim("roster", 13)
	var net := _mk_net(_ring(8, 1200.0))
	ok(net.ready(), "the test net built")
	var cr := _mk_cr(net)
	ok(cr.ready(), "a ring of eight roads is lived along")
	ok(cr.crofts.size() <= Crofts.MAX_CROFTS,
			"%d crofts, inside the cap of %d" % [cr.crofts.size(), Crofts.MAX_CROFTS])
	var ids := {}
	var names := {}
	var kinds_legal := true
	var per_edge := {}
	for c in cr.crofts:
		var cd := c as Dictionary
		ids[String(cd["id"])] = true
		names[String(cd["name"])] = true
		if not Crofts.KINDS.has(String(cd["kind"])):
			kinds_legal = false
		var e := int(cd["edge"])
		per_edge[e] = int(per_edge.get(e, 0)) + 1
	ok(ids.size() == cr.crofts.size(), "every croft has its own id")
	ok(names.size() == cr.crofts.size(),
			"every household has its own name (%d names, %d crofts)" % [names.size(), cr.crofts.size()])
	ok(kinds_legal, "every kind is one KINDS knows")
	var over := false
	for e in per_edge:
		if int(per_edge[e]) > Crofts.MAX_PER_EDGE:
			over = true
	ok(not over, "no road carries more than MAX_PER_EDGE households")
	## Every croft has state the moment it exists -- a croft with no woodpile
	## row would read as a cold hearth on its very first frame.
	var stated := true
	for c in cr.crofts:
		var s := cr.state_of(String((c as Dictionary)["id"]))
		if not s.has("stores") or not s.has("wash"):
			stated = false
	ok(stated, "every croft is seated with a state row")
	ok(cr.state.size() == cr.crofts.size(), "no orphan state rows")
	## A short road has nowhere to put a yard clear of both villages.
	var tiny := _mk_net([
		{"name": "A", "pos": Vector2(0, 0), "rank": 0},
		{"name": "B", "pos": Vector2(240, 0), "rank": 0}])
	var cr2 := _mk_cr(tiny)
	ok(cr2.crofts.is_empty(), "a 240 m road seats nobody")
	## And a road that IS long enough for the clearance arithmetic but still
	## too short to live along is refused by MIN_ROAD_M rather than by luck.
	## 450 m clears 190 m at both ends with room to spare, so `_seat` would
	## happily take it: without this case, deleting MIN_ROAD_M survived the
	## whole sweep because the 240 m road above is refused twice over.
	var shortish := _mk_net([
		{"name": "A", "pos": Vector2(0, 0), "rank": 2},
		{"name": "B", "pos": Vector2(450, 0), "rank": 2}])
	var cr2b := _mk_cr(shortish)
	ok(cr2b.crofts.is_empty(), "a 450 m road does not either, and only MIN_ROAD_M says so")
	shortish.free()
	cr2b.free()
	## No net at all is a legal world, not a crash.
	var cr3 := Crofts.new()
	cr3.boot(true)
	ok(cr3.crofts.is_empty() and not cr3.ready(), "no road net means no crofts and no crash")
	cr3.advance(48.0)
	ok(cr3.days >= 2.0 and int(cr3.report()["crofts"]) == 0,
			"and a sim with nothing in it still steps its clock")
	net.free()
	cr.free()
	tiny.free()
	cr2.free()
	cr3.free()


# ------------------------------------------------------------------- siting

func _t_siting() -> void:
	claim("siting", 14)
	var net := _mk_net(_ring(8, 1200.0))
	var cr := _mk_cr(net)
	ok(not cr.crofts.is_empty(), "there is something to site")
	var clear_ok := true
	var off_ok := true
	var road_ok := true
	var t_ok := true
	var worst_clear := 1e9
	for c in cr.crofts:
		var cd := c as Dictionary
		var ed: Dictionary = net.edge(int(cd["edge"]))
		var length := float(ed["len"])
		var t := float(cd["t"])
		var from_a := t * length
		var from_b := (1.0 - t) * length
		worst_clear = minf(worst_clear, minf(from_a, from_b))
		if minf(from_a, from_b) < Crofts.CLEAR_OF_PLACE - 1.0:
			clear_ok = false
		if t < 0.0 or t > 1.0:
			t_ok = false
		var d: float = (cd["pos"] as Vector2).distance_to(cd["road"] as Vector2)
		if d < Crofts.OFF_MIN - 0.5 or d > Crofts.OFF_MAX + 0.5:
			off_ok = false
		## `road` must actually be ON the road, not merely near it.
		var hit := net.nearest_road(cd["road"] as Vector2)
		if not bool(hit["ok"]) or float(hit["dist"]) > 1.0:
			road_ok = false
	ok(t_ok, "every seat is a legal fraction of its road")
	ok(clear_ok, "no yard is inside %.0f m of a village (worst %.0f m)"
			% [Crofts.CLEAR_OF_PLACE, worst_clear])
	ok(off_ok, "every yard is between OFF_MIN and OFF_MAX off the road")
	ok(road_ok, "every yard's road point is on a road")
	## The yard faces the road it fronts.
	var facing := true
	for c in cr.crofts:
		var cd := c as Dictionary
		var to_road: Vector2 = ((cd["road"] as Vector2) - (cd["pos"] as Vector2)).normalized()
		if to_road.dot(cd["face"] as Vector2) < 0.98:
			facing = false
	ok(facing, "every croft faces its own road")
	## The drier side. With a ridge bound, the yard must not sit on the low
	## side of the road when the high side is a metre better.
	var cr_dry := Crofts.new()
	cr_dry.world_seed = 20260910
	cr_dry.net = net
	var g := FakeGround.new()
	root.add_child(g)
	cr_dry._ground = g
	cr_dry.boot(true)
	var moved := 0
	var wrong := 0
	var flat_cr := _mk_cr(net)
	for c in cr_dry.crofts:
		var cd := c as Dictionary
		var here: Vector2 = cd["pos"]
		var road: Vector2 = cd["road"]
		var mirror := road - (here - road)
		if g._surface_y(Vector3(mirror.x, 0.0, mirror.y)) > g._surface_y(Vector3(here.x, 0.0, here.y)) + Crofts.SIDE_MARGIN:
			wrong += 1
		var flat := flat_cr.croft_by_id(String(cd["id"]))
		if not flat.is_empty() and int(flat["side"]) != int(cd["side"]):
			moved += 1
	flat_cr.free()
	ok(wrong == 0, "no yard sits on the wetter side when the drier one is clear (%d wrong)" % wrong)
	ok(moved > 0, "the ground probe actually moved %d of them" % moved)
	## And with no probe bound the hashed side stands -- the headless answer.
	var a1 := _mk_cr(net)
	var a2 := _mk_cr(net)
	var same := true
	for i in a1.crofts.size():
		if int((a1.crofts[i] as Dictionary)["side"]) != int((a2.crofts[i] as Dictionary)["side"]):
			same = false
	ok(same, "with no ground probe the side is the hashed one, twice running")
	ok(a1.crofts.size() == cr.crofts.size(), "and the roster is the same size either way")
	## A ring wide enough that some roads carry TWO households, because that
	## is the only case where the clearance arithmetic is load-bearing: with
	## a single seat the band's own 0.18 offset keeps it clear by accident,
	## and a mutation that zeroed the clearance survived on exactly that.
	var wide := _mk_net(_ring(8, 1700.0))
	var cr_w := _mk_cr(wide)
	var per: Dictionary = {}
	for c in cr_w.crofts:
		var e := int((c as Dictionary)["edge"])
		per[e] = int(per.get(e, 0)) + 1
	var pairs := 0
	for e in per:
		if int(per[e]) >= 2:
			pairs += 1
	ok(pairs > 0, "a wide ring puts two households on some roads (%d roads)" % pairs)
	var wide_clear := true
	var worst_w := 1e9
	for c in cr_w.crofts:
		var cd := c as Dictionary
		var length := float((wide.edge(int(cd["edge"])) as Dictionary)["len"])
		var m := minf(float(cd["t"]) * length, (1.0 - float(cd["t"])) * length)
		worst_w = minf(worst_w, m)
		if m < Crofts.CLEAR_OF_PLACE - 1.0:
			wide_clear = false
	ok(wide_clear, "and neither of a pair is inside the clearance (worst %.0f m)" % worst_w)
	wide.free()
	cr_w.free()
	## And a ring of SHORT roads, which is where `lo` is actually the thing
	## keeping a yard out of the village. On a 600 m road the band's own
	## offset alone would seat a household 146 m from the green; on the 900 m
	## and 1 300 m rings above it happens to clear 190 m without any help,
	## which is exactly why a mutation that zeroed the clearance survived two
	## sweeps before this case existed.
	var tight := _mk_net(_ring(8, 800.0))
	var cr_t := _mk_cr(tight)
	ok(cr_t.crofts.size() > 0, "a ring of ~600 m roads is still lived along (%d)" % cr_t.crofts.size())
	var tight_clear := true
	var worst_t := 1e9
	for c in cr_t.crofts:
		var cd := c as Dictionary
		var length := float((tight.edge(int(cd["edge"])) as Dictionary)["len"])
		var m := minf(float(cd["t"]) * length, (1.0 - float(cd["t"])) * length)
		worst_t = minf(worst_t, m)
		if m < Crofts.CLEAR_OF_PLACE - 1.0:
			tight_clear = false
	ok(tight_clear, "and no yard on a short road is inside the clearance (worst %.0f m)" % worst_t)
	tight.free()
	cr_t.free()
	g.free()
	cr_dry.free()
	a1.free()
	a2.free()
	cr.free()
	net.free()


# -------------------------------------------------------------- determinism

func _t_determinism() -> void:
	claim("determinism", 7)
	var rows := _ring(8, 1200.0)
	var n1 := _mk_net(rows)
	var c1 := _mk_cr(n1)
	var n2 := _mk_net(rows)
	var c2 := _mk_cr(n2)
	ok(c1.crofts.size() == c2.crofts.size(), "two builds seat the same number")
	var identical := true
	for i in c1.crofts.size():
		var a := c1.crofts[i] as Dictionary
		var b := c2.crofts[i] as Dictionary
		if String(a["id"]) != String(b["id"]) or String(a["name"]) != String(b["name"]) \
				or String(a["kind"]) != String(b["kind"]) \
				or (a["pos"] as Vector2).distance_to(b["pos"] as Vector2) > 0.001:
			identical = false
	ok(identical, "and the same households in the same places")
	## The ROSTER ORDER must not matter. `_edge_rows` sorts by place name, so
	## a fort appended at runtime cannot renumber the edges under a household.
	var shuffled := rows.duplicate()
	shuffled.reverse()
	var n3 := _mk_net(shuffled)
	var c3 := _mk_cr(n3)
	var by_name1: Dictionary = {}
	for c in c1.crofts:
		by_name1[String((c as Dictionary)["name"])] = (c as Dictionary)["pos"]
	var order_free := c3.crofts.size() == c1.crofts.size()
	for c in c3.crofts:
		var cd := c as Dictionary
		if not by_name1.has(String(cd["name"])):
			order_free = false
			continue
		if (by_name1[String(cd["name"])] as Vector2).distance_to(cd["pos"] as Vector2) > 0.001:
			order_free = false
	ok(order_free, "a reversed roster gives the same households in the same yards")
	## A different seed gives a different country.
	var c4 := _mk_cr(n1, null, 777)
	var diff := false
	for i in mini(c1.crofts.size(), c4.crofts.size()):
		if String((c1.crofts[i] as Dictionary)["name"]) != String((c4.crofts[i] as Dictionary)["name"]):
			diff = true
	ok(diff, "a different seed puts different people in the yards")
	## No RandomNumberGenerator anywhere in the source.
	var fa := FileAccess.open("res://scripts/Crofts.gd", FileAccess.READ)
	ok(fa != null, "the source is readable")
	var src := fa.get_as_text() if fa != null else ""
	if fa != null:
		fa.close()
	ok(src.length() > 20000, "and the scan came back with %d characters" % src.length())
	ok(not src.contains("RandomNumberGenerator") and not src.contains("randf")
			and not src.contains("randi"), "no RNG anywhere in Crofts.gd")
	n1.free()
	n2.free()
	n3.free()
	c1.free()
	c2.free()
	c3.free()
	c4.free()


# ---------------------------------------------------------------- the day

func _t_day() -> void:
	claim("day", 16)
	var c := _croft(0.5)
	var st := _st()
	var dawn := Crofts.daylight(0).x
	var dusk := Crofts.daylight(0).y
	var rise := Crofts.rise_at(c, 0)
	var bed := Crofts.bed_at(c, 0)
	ok(rise < dawn, "the household is up before it is light")
	ok(bed > dusk, "and still up after dark")
	ok(bed - rise > 12.0 and bed - rise < 17.0, "a spring day is %.1f waking hours" % (bed - rise))
	var at_night := Crofts.routine_at(c, _day(4, 2.0), 0, 0, st)
	var at_noon := Crofts.routine_at(c, _day(4, 12.0), 0, 0, st)
	ok(not bool(at_night["awake"]), "nobody is up at two in the morning")
	ok(bool(at_noon["awake"]), "everybody is up at noon")
	ok(String(at_night["hearth"]) == "banked", "the fire is banked overnight, not out")
	ok(String(at_noon["hearth"]) == "lit", "and lit through the day")
	ok(bool(at_night["smoke"]) and bool(at_noon["smoke"]), "there is smoke either way")
	ok(String(at_night["shutters"]) == "shut", "shutters are barred at night")
	ok(String(at_noon["shutters"]) == "open", "and open at noon")
	ok(String(at_night["work"]) == "abed", "the crofter is abed at two")
	ok(not bool(at_night["lamp"]), "and burns no lamp while asleep")
	var at_dark := Crofts.routine_at(c, _day(4, dusk + 0.9), 0, 0, st)
	ok(bool(at_dark["awake"]) and bool(at_dark["lamp"]), "the lamp is lit in the hour after dusk")
	ok(not bool(at_noon["lamp"]), "and never at noon")
	## The bank happens before bed, not at it.
	var late := Crofts.routine_at(c, _day(4, bed - 0.2), 0, 0, st)
	ok(String(late["hearth"]) == "banked", "the fire is banked before they turn in")
	## An empty woodpile is the only thing that puts a hearth out.
	var cold := Crofts.routine_at(c, _day(4, 12.0), 0, 0, _st(0.0))
	ok(String(cold["hearth"]) == "out" and not bool(cold["smoke"]),
			"an empty woodpile is a cold roof")


# ------------------------------------------------------------------ weather

func _t_weather() -> void:
	claim("weather", 15)
	var c := _croft(0.5)
	var st := _st()
	var noon := _day(4, 12.5)
	var clear := Crofts.routine_at(c, noon, Crofts.SKY_CLEAR, 0, st)
	var drizzle := Crofts.routine_at(c, noon, Crofts.SKY_DRIZZLE, 0, st)
	var rain := Crofts.routine_at(c, noon, Crofts.SKY_RAIN, 0, st)
	var storm := Crofts.routine_at(c, noon, Crofts.SKY_STORM, 0, st)
	ok(String(clear["stock"]) == "field", "the beasts are out on a clear noon")
	ok(String(drizzle["stock"]) == "field", "a drizzle does not bring them in")
	ok(String(rain["stock"]) == "byre", "rain does")
	ok(String(storm["stock"]) == "byre", "and a storm certainly does")
	ok(int(clear["beasts"]) > 0 and int(rain["beasts"]) == 0,
			"the yard shows beasts only when they are out")
	ok(String(clear["shutters"]) == "open" and String(rain["shutters"]) == "open",
			"rain alone does not bar the shutters")
	ok(String(storm["shutters"]) == "shut", "a storm bars them in broad daylight")
	## Outdoor work is driven under cover, then indoors.
	var out_clear := 0
	var out_rain := 0
	var out_storm := 0
	for h in range(8, 18):
		var hh := float(h) + 0.5
		if Crofts.OUTDOOR.has(String(Crofts.routine_at(c, _day(4, hh), 0, 0, st)["work"])):
			out_clear += 1
		if Crofts.OUTDOOR.has(String(Crofts.routine_at(c, _day(4, hh), Crofts.SKY_RAIN, 0, st)["work"])):
			out_rain += 1
		if Crofts.OUTDOOR.has(String(Crofts.routine_at(c, _day(4, hh), Crofts.SKY_STORM, 0, st)["work"])):
			out_storm += 1
	ok(out_clear > 0, "there is outdoor work on a clear day (%d hours)" % out_clear)
	ok(out_rain == 0, "and none of it in the rain")
	ok(out_storm == 0, "and none in a storm either")
	## Pick an hour whose CLEAR-sky station is genuinely outdoor work. The
	## work table moves through the day, so a fixed hour proves nothing --
	## the first pass here asked at half past ten, found the household in the
	## byre anyway, and compared two identical answers.
	var out_hour := -1.0
	for h in range(8, 18):
		if Crofts.OUTDOOR.has(String(Crofts.routine_at(c, _day(4, float(h) + 0.5), 0, 0, st)["work"])):
			out_hour = float(h) + 0.5
			break
	ok(out_hour > 0.0, "there is an hour of outdoor work to drive indoors (%.1f)" % out_hour)
	var storm_work := String(Crofts.routine_at(c, _day(4, out_hour), Crofts.SKY_STORM, 0, st)["work"])
	var rain_work := String(Crofts.routine_at(c, _day(4, out_hour), Crofts.SKY_RAIN, 0, st)["work"])
	ok(storm_work == "in", "a storm puts the crofter indoors, not merely under cover")
	ok(rain_work == "byre", "rain puts them under cover instead (%s)" % rain_work)
	ok(storm_work != rain_work, "a gale and a shower are not the same instruction")
	## The smoke column is flattened by the sky, not by a switch.
	ok(float(storm["smoke_lean"]) > float(rain["smoke_lean"])
			and float(rain["smoke_lean"]) > float(clear["smoke_lean"]),
			"the smoke leans further the worse the sky gets")


# ------------------------------------------------------------------- season

func _t_season() -> void:
	claim("season", 14)
	var c := _croft(0.5)
	var st := _st()
	var lens: Array = []
	for s in 4:
		var dl := Crofts.daylight(s)
		lens.append(dl.y - dl.x)
	ok(float(lens[1]) > float(lens[0]), "summer days are longer than spring ones")
	ok(float(lens[0]) > float(lens[2]), "spring days are longer than autumn ones")
	ok(float(lens[2]) > float(lens[3]), "autumn days are longer than winter ones")
	ok(float(lens[3]) < 10.0, "a winter day is under ten hours of light")
	## Winter keeps the stock in except for a few clear hours at midday.
	var w_dawn := Crofts.routine_at(c, _day(76, 8.5), 0, 3, st)
	var w_noon := Crofts.routine_at(c, _day(76, 12.0), 0, 3, st)
	var w_grey := Crofts.routine_at(c, _day(76, 12.0), Crofts.SKY_OVERCAST, 3, st)
	ok(String(w_dawn["stock"]) == "byre", "winter keeps them in at half past eight")
	ok(String(w_noon["stock"]) == "field", "and turns them out at noon on a clear day")
	ok(String(w_grey["stock"]) == "byre", "but not on a grey one")
	var s_noon := Crofts.routine_at(c, _day(4, 12.0), Crofts.SKY_OVERCAST, 0, st)
	ok(String(s_noon["stock"]) == "field", "spring is not so fussy")
	## The crop.
	ok(Crofts.crop_at(_day(2, 0.0), 0, "croft") < 0.3, "the plot is nearly bare in early spring")
	ok(Crofts.crop_at(_day(46, 0.0), 1, "croft") > 0.9, "and full by late summer")
	var harvested := Crofts.crop_at(_day(70, 0.0), 2, "croft")
	ok(harvested < 0.3, "and cut by the end of autumn (%.2f)" % harvested)
	ok(is_equal_approx(Crofts.crop_at(_day(80, 0.0), 3, "croft"), 0.0),
			"winter has nothing standing")
	ok(is_equal_approx(Crofts.crop_at(_day(46, 0.0), 1, "shieling"), 0.0),
			"a shieling has no plot in any season")
	## The work of the year differs by season -- otherwise the table is decoration.
	var seen: Dictionary = {}
	for s in 4:
		var bag: Array = []
		for h in range(8, 17):
			bag.append(Crofts.station_for(c, s, h))
		bag.sort()
		seen["|".join(PackedStringArray(bag))] = true
	ok(seen.size() >= 3, "at least three seasons of work look different (%d)" % seen.size())


# ------------------------------------------------------------------ washing

func _t_washing() -> void:
	claim("washing", 16)
	var c := _croft(0.5)
	var dl := Crofts.daylight(0)
	var rise := Crofts.rise_at(c, 0)
	var hang := rise + Crofts.WASH_HANG_AFTER
	var st := _st()
	## Intent first: it is a query, and it is the only half that is.
	ok(String(Crofts.routine_at(c, _day(4, hang + 0.5), 0, 0, st)["wash_intent"]) == "hang",
			"a clear morning is a morning to hang washing")
	ok(String(Crofts.routine_at(c, _day(4, hang - 1.0), 0, 0, st)["wash_intent"]) == "fetch",
			"before the hour, no")
	ok(String(Crofts.routine_at(c, _day(4, hang + 0.5), Crofts.SKY_DRIZZLE, 0, st)["wash_intent"]) == "fetch",
			"a drizzle is not a morning to hang washing")
	ok(String(Crofts.routine_at(c, _day(4, dl.y - 0.5), 0, 0, st)["wash_intent"]) == "fetch",
			"and it comes in before dusk")
	## Asked at the WINTER hanging hour, not the spring one. `hang` above is
	## derived from the spring rise, which in winter falls before the
	## household is even up -- so this assertion used to come back "fetch"
	## whether or not the season gate existed at all, and a mutation that
	## deleted the gate walked straight through it.
	var w_hang := Crofts.rise_at(c, 3) + Crofts.WASH_HANG_AFTER + 0.5
	ok(String(Crofts.routine_at(c, _day(76, w_hang), 0, 3, st)["wash_intent"]) == "fetch",
			"nobody hangs washing in winter (asked at %.2f)" % w_hang)
	ok(String(Crofts.routine_at(c, _day(4, hang + 0.5), 0, 0, _st(150.0, "none", 99.0))["wash_intent"]) == "fetch",
			"nor while the house is barred")
	ok(String(Crofts.routine_at(c, _day(4, hang + 0.5), 0, 0, _st(150.0, "wet"))["wash_intent"]) == "fetch",
			"nor while yesterday's is still soaked on the line")
	## Then the state, driven through the sim. This is the part a pure query
	## could not express.
	var net := _mk_net(_ring(8, 1200.0))
	var sky := FakeSky.new()
	root.add_child(sky)
	var cr := _mk_cr(net, sky)
	ok(not cr.crofts.is_empty(), "there is a croft to hang anything on")
	var id := String((cr.crofts[0] as Dictionary)["id"])
	var cc := cr.croft_by_id(id)
	var cst := cr.state_of(id)
	var chang := Crofts.rise_at(cc, 0) + Crofts.WASH_HANG_AFTER
	sky.season = 0
	sky.sky = 0
	cst["wash"] = "none"
	_set_clock(cr, _day(8, chang + 0.75))
	cr.advance(Crofts.STEP_HOURS)
	ok(String(cst["wash"]) == "out", "the line goes out on a clear morning")
	## The sky greys: it comes in, undamaged.
	sky.sky = Crofts.SKY_DRIZZLE
	cr.advance(Crofts.STEP_HOURS)
	ok(String(cst["wash"]) == "none", "a drizzle and they fetch it in")
	## Hang it again, then let it RAIN while it is out. This is the branch a
	## sky-derived "out" could never reach.
	sky.sky = 0
	cr.advance(Crofts.STEP_HOURS)
	ok(String(cst["wash"]) == "out", "back out when the sky clears")
	sky.sky = Crofts.SKY_RAIN
	cr.advance(Crofts.STEP_HOURS)
	ok(String(cst["wash"]) == "wet", "and SOAKED when the rain beats them to it")
	## Order: the soak must be decided before the fetch, or nothing is ever
	## caught out. Rain is a "fetch" intent too, so if fetch ran first the
	## line would have come in dry.
	ok(String(Crofts.routine_at(cc, cr.days, Crofts.SKY_RAIN, 0, cst)["wash_intent"]) == "fetch",
			"rain is a fetch instruction, so the soak had to win the race")
	## Nothing fresh goes out while it is wet, and it dries in decent weather.
	sky.sky = 0
	cr.advance(Crofts.DRY_HOURS - Crofts.STEP_HOURS)
	ok(String(cst["wash"]) == "wet", "still drying after %.1f hours" % (Crofts.DRY_HOURS - 0.5))
	cr.advance(Crofts.STEP_HOURS * 2.0)
	ok(String(cst["wash"]) != "wet", "and dry after %.1f" % Crofts.DRY_HOURS)
	## Rain resets the drying clock rather than counting toward it.
	cst["wash"] = "wet"
	cst["dry_h"] = 0.0
	sky.sky = Crofts.SKY_RAIN
	cr.advance(Crofts.DRY_HOURS * 2.0)
	ok(String(cst["wash"]) == "wet" and float(cst["dry_h"]) <= 0.001,
			"a week of rain dries nothing")
	sky.free()
	cr.free()
	net.free()


# ----------------------------------------------------------------- woodpile

func _t_woodpile() -> void:
	claim("woodpile", 17)
	ok(is_equal_approx(Crofts.burn_per_hour("out", 0), 0.0), "a cold hearth burns nothing")
	ok(Crofts.burn_per_hour("lit", 0) > Crofts.burn_per_hour("banked", 0),
			"a lit fire burns more than a banked one")
	ok(Crofts.burn_per_hour("lit", 3) > Crofts.burn_per_hour("lit", 0),
			"and winter burns more than spring")
	ok(Crofts.burn_per_hour("lit", 1) < Crofts.burn_per_hour("lit", 0),
			"and summer less")
	ok(is_equal_approx(Crofts.gather_per_hour("plot", 2), 0.0),
			"an hour at the plot brings no firewood in")
	ok(Crofts.gather_per_hour("wood", 2) > Crofts.gather_per_hour("wood", 3),
			"autumn is the season for stocking up")
	## Through the sim: a household with an empty pile drops everything.
	var net := _mk_net(_ring(8, 1200.0))
	var sky := FakeSky.new()
	root.add_child(sky)
	var cr := _mk_cr(net, sky)
	cr.croft_cold.connect(func(c): _cold.append(String((c as Dictionary)["id"])))
	var id := String((cr.crofts[0] as Dictionary)["id"])
	var cc := cr.croft_by_id(id)
	var cst := cr.state_of(id)
	sky.season = 0
	sky.sky = 0
	cst["stores"] = 0.0
	cst["was_cold"] = false
	_cold.clear()
	_set_clock(cr, _day(9, 10.0))
	var r0 := Crofts.routine_at(cc, cr.days, 0, 0, cst)
	ok(String(r0["work"]) == "wood", "an empty pile outranks the day's work")
	ok(String(r0["hearth"]) == "out", "and the roof is cold until it is filled")
	cr.advance(Crofts.STEP_HOURS)
	ok(_cold.has(id), "a cold roof fires croft_cold")
	var n_first := _cold.size()
	## Keep the pile empty AND the household indoors for the next step. Left
	## alone they go straight to the woodpile, the roof stops being cold, and
	## this assertion passes because there was nothing left to signal rather
	## than because the signal is edge-triggered -- which is how a mutation
	## that made it fire every step survived.
	cst["stores"] = 0.0
	cst["shut_until"] = cr.days + 5.0
	cr.advance(Crofts.STEP_HOURS)
	ok(String(Crofts.routine_at(cc, cr.days, 0, 0, cst)["hearth"]) == "out",
			"the roof is still cold on the step after")
	ok(_cold.size() == n_first, "and croft_cold fires once per cold spell, not once a step")
	cst["shut_until"] = -1.0
	cr.advance(4.0)
	ok(float(cst["stores"]) > 0.0, "the household gets the fire going again (%.0f)" % float(cst["stores"]))
	ok(String(Crofts.routine_at(cc, cr.days, 0, 0, cst)["hearth"]) != "out",
			"and the roof is warm again")
	## Bounded at both ends, always.
	cst["stores"] = Crofts.STORE_MAX * 4.0
	cr.advance(2.0)
	ok(float(cst["stores"]) <= Crofts.STORE_MAX + 0.001,
			"the pile is capped at STORE_MAX (%.0f)" % float(cst["stores"]))
	var floored := true
	sky.season = 3
	cst["stores"] = 0.4
	for i in 200:
		cr.advance(Crofts.STEP_HOURS)
		if float(cst["stores"]) < 0.0:
			floored = false
	ok(floored, "and never goes negative")
	ok(int(Crofts.routine_at(cc, cr.days, 0, 3, _st(0.0))["wood_n"]) == 0,
			"an empty pile shows no logs")
	ok(int(Crofts.routine_at(cc, cr.days, 0, 3, _st(Crofts.STORE_MAX))["wood_n"]) == Crofts.WOOD_MAX,
			"a full one shows all of them")
	sky.free()
	cr.free()
	net.free()


# --------------------------------------------------------------------- year

func _t_year() -> void:
	claim("year", 9)
	## The woodpile is the only economy in here, so it is checked the way it
	## is actually experienced: a whole year, and the SHAPE of the curve.
	var net := _mk_net(_ring(8, 1200.0))
	var sky := FakeSky.new()
	root.add_child(sky)
	var cr := _mk_cr(net, sky)
	var id := String((cr.crofts[0] as Dictionary)["id"])
	var cst := cr.state_of(id)
	cst["stores"] = Crofts.STORE_START
	_set_clock(cr, 0.0)
	sky.sky = 0
	var at_season: Array = [0.0, 0.0, 0.0, 0.0]
	var lowest := 1e9
	var went_cold := false
	for d in 96:
		@warning_ignore("integer_division")
		sky.season = int(d / 24) % 4
		cr.advance(24.0)
		var s := float(cst["stores"])
		lowest = minf(lowest, s)
		if s <= 0.0:
			went_cold = true
		@warning_ignore("integer_division")
		at_season[int(d / 24) % 4] = s
	ok(not went_cold, "a household that keeps its autumn sees the far side of winter")
	ok(lowest > 10.0, "and never runs the pile down to nothing (lowest %.0f)" % lowest)
	ok(float(at_season[2]) > float(at_season[1]), "autumn ends richer than summer")
	near_f(float(at_season[2]), Crofts.STORE_MAX, 60.0, "autumn fills the pile to about the cap")
	ok(float(at_season[3]) < float(at_season[2]) * 0.55,
			"winter spends most of it (%.0f of %.0f left)" % [float(at_season[3]), float(at_season[2])])
	ok(float(at_season[3]) > 0.0, "but not all of it")
	## And now the consequence that persists: bar the same household through
	## most of autumn and it does NOT see the far side of winter.
	cst["stores"] = Crofts.STORE_START
	_set_clock(cr, 0.0)
	var cold_days := 0
	for d in 96:
		@warning_ignore("integer_division")
		sky.season = int(d / 24) % 4
		## Twelve autumn days barred indoors -- a scare that lasted a fortnight.
		if d >= 48 and d < 60:
			cst["shut_until"] = cr.days + 2.0
		cr.advance(24.0)
		if float(cst["stores"]) <= 0.0:
			cold_days += 1
	ok(cold_days > 0, "an autumn spent barred indoors is a winter with no smoke (%d cold days)" % cold_days)
	ok(cold_days < 60, "and it is a hard winter, not a dead household (%d days)" % cold_days)
	ok(float(cst["stores"]) >= 0.0, "the pile is still a legal number afterwards")
	sky.free()
	cr.free()
	net.free()


# -------------------------------------------------------------------- alarm

func _t_alarm() -> void:
	claim("alarm", 13)
	var net := _mk_net(_ring(8, 1200.0))
	var sky := FakeSky.new()
	root.add_child(sky)
	var cr := _mk_cr(net, sky)
	cr.croft_shut.connect(func(c, why): _shut.append("%s %s" % [String((c as Dictionary)["id"]), why]))
	var id := String((cr.crofts[0] as Dictionary)["id"])
	var cc := cr.croft_by_id(id)
	var cst := cr.state_of(id)
	_shut.clear()
	_set_clock(cr, _day(12, 0.0))
	cr.advance(48.0)
	ok(_shut.is_empty(), "a quiet country bars nobody in")
	ok(not bool(Crofts.routine_at(cc, cr.days, 0, 0, cst)["shut_in"]), "and the door stands open")
	sky.press["goblins"] = Crofts.SHUT_PRESSURE + 0.2
	cr.advance(48.0)
	ok(not _shut.is_empty(), "a raid nearby bars the door")
	ok(String(_shut[0]).contains("goblins"), "and says which scare did it (%s)" % String(_shut[0]))
	var shut_r := Crofts.routine_at(cc, cr.days, 0, 0, cst)
	ok(bool(shut_r["shut_in"]), "the household is barred in")
	ok(String(shut_r["shutters"]) == "shut", "the shutters are shut at noon")
	ok(String(shut_r["stock"]) == "byre", "the beasts stay in")
	ok(String(shut_r["work"]) == "in" or String(shut_r["work"]) == "door"
			or String(shut_r["work"]) == "abed",
			"and nobody is out at the plot (%s)" % String(shut_r["work"]))
	## It lifts. A scare is not a permanent state of the world.
	sky.press.clear()
	cr.advance(24.0 * (Crofts.SHUT_DAYS + 1.0))
	ok(not bool(Crofts.routine_at(cc, cr.days, 0, 0, cst)["shut_in"]),
			"and it lifts once the country is quiet again")
	## The check is once a day per household, not once a step.
	var before := _shut.size()
	sky.press["bandits"] = 0.99
	cr.advance(6.0)
	ok(_shut.size() - before <= 1, "the alarm is checked once a day, not twelve times")
	## EVERY ALARM TAG MUST BE ONE THE CATALOGUE CAN ACTUALLY EMIT. This file
	## shipped with `["raid", "beast", "wolf", "war"]` and not one of the four
	## exists anywhere in ChronicleEvents, so `pressure_at` answered a flat
	## zero for all of them and no croft in Myrkfell ever barred its door.
	## Measured over a simulated year before this was fixed: 4 800 croft-days,
	## best pressure ever seen 0.250, doors barred ZERO. A tag list is exactly
	## as dead as a method nobody calls, and it is just as invisible.
	var emitted := {}
	for kid in ChronicleEvents.ids():
		var kd := ChronicleEvents.by_id(String(kid))
		for o in (kd.get("outcomes", []) as Array):
			for tg in ((o as Dictionary).get("bias", {}) as Dictionary):
				emitted[String(tg)] = true
	ok(emitted.size() >= 10, "the catalogue emits a real spread of bias tags (%d)" % emitted.size())
	var dead: Array = []
	for tg in Crofts.ALARM_TAGS:
		if not emitted.has(String(tg)):
			dead.append(String(tg))
	ok(dead.is_empty(), "and every ALARM_TAG is one of them (dead: %s)" % str(dead))
	ok(not Crofts.ALARM_TAGS.is_empty(), "and there is at least one to be alarmed by")
	sky.free()
	cr.free()
	net.free()


# ---------------------------------------------------------------- chronicle

func _t_chronicle() -> void:
	claim("chronicle", 11)
	## A STUB IS NOT THE COLLABORATOR. Everything above drives a FakeSky;
	## this section drives the real Chronicle's real front door, because
	## three mutations of a real Chronicle method survived a green suite on
	## 2026-09-09 for exactly the want of a section like this one.
	var chron := Chronicle.new()
	root.add_child(chron)
	chron.boot()
	ok(chron.has_method("pressure_at"), "Chronicle still has pressure_at")
	ok(chron.has_method("sky_at"), "and sky_at")
	ok(chron.has_method("season_at"), "and season_at")
	var quiet := chron.pressure_at(Vector3(1e6, 0.0, 1e6), "goblins")
	ok(quiet < Crofts.SHUT_PRESSURE, "an empty corner of the map is not an alarm (%.2f)" % quiet)
	## [factions] and the SAME tag, at the same instant, now reads differently
	## depending on where you are standing — which is the whole of the faction
	## field, seen from the one door Crofts actually uses.
	var deep := chron.pressure_at(Vector3(2485.9, 0.0, -5560.1), "goblins")   ## Baxter
	var town := chron.pressure_at(Vector3(600.2, 0.0, 559.9), "goblins")      ## Casco Bay
	ok(deep > town + 0.30, "deep country reads hotter for goblins than the coast does (%.2f vs %.2f)"
			% [deep, town])
	chron.bias["goblins"] = 1.5
	var loud := chron.pressure_at(Vector3(1e6, 0.0, 1e6), "goblins")
	ok(loud >= Crofts.SHUT_PRESSURE, "a loaded bias is (%.2f)" % loud)
	ok(loud > quiet, "and the real pressure_at moved when the bias did")
	ok(absf(chron.pressure_at(Vector3(2485.9, 0.0, -5560.1), "bandits")
			- chron.pressure_at(Vector3(600.2, 0.0, 559.9), "bandits")) < 0.001,
			"but a tag that speaks for nobody is exactly as loud everywhere")
	var lvl := chron.sky_at(3.0)
	ok(lvl >= 0 and lvl <= 4, "the real sky_at answers a legal Weather.Level (%d)" % lvl)
	## Crofts' own season fallback must agree with the Chronicle's, or two
	## sims on the same calendar disagree about what month it is.
	var agree := true
	for d in [0.0, 13.5, 25.0, 49.9, 71.2, 95.5, 120.0]:
		var mine := int(fposmod(float(d), Crofts.DAYS_PER_SEASON * 4.0) / Crofts.DAYS_PER_SEASON) % 4
		if Chronicle.season_at(float(d)) != mine:
			agree = false
	ok(agree, "Crofts' season fallback agrees with Chronicle.season_at on every sample")
	## Bound for real, the croft reads the Chronicle rather than its fallback.
	var net := _mk_net(_ring(8, 1200.0))
	var cr := _mk_cr(net, chron)
	_set_clock(cr, _day(6, 9.5))
	cr.advance(30.0)
	var barred := 0
	for c in cr.crofts:
		if bool(cr.routine_of(String((c as Dictionary)["id"]))["shut_in"]):
			barred += 1
	ok(barred > 0, "a Chronicle screaming raid bars real households (%d of %d)"
			% [barred, cr.crofts.size()])
	cr.free()
	net.free()
	chron.free()


# --------------------------------------------------------------------- feed

func _t_feed() -> void:
	claim("feed", 15)
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
	var net := _mk_net(_ring(8, 1200.0))
	var sky := FakeSky.new()
	root.add_child(sky)
	var cr := _mk_cr(net, sky)
	root.add_child(cr)
	cr.feed = feed
	cr.player = pl
	var cd := cr.crofts[0] as Dictionary
	var id := String(cd["id"])
	var at: Vector2 = cd["pos"]
	pl.global_position = Vector3(at.x, 0.0, at.y)
	## The line itself.
	ok(Crofts.summary(Crofts.routine_at(cd, _day(4, 12.0), 0, 0, _st())) != "",
			"a croft always reads as something")
	ok(Crofts.summary(Crofts.routine_at(cd, _day(4, 12.0), 0, 0, _st(0.0))) == "cold",
			"a cold roof reads as cold before anything else")
	ok(Crofts.summary(Crofts.routine_at(cd, _day(4, 12.0), 0, 0, _st(150.0, "none", 99.0))) == "barred",
			"a barred house reads as barred before its beasts")
	var line := Crofts.legible(cd, Crofts.routine_at(cd, _day(4, 12.0), 0, 0, _st(0.0)))
	ok(line.contains(String(cd["name"])), "and the line names the household")
	ok(line.length() < 90, "and is short enough to read in passing (%d chars)" % line.length())
	## Through sense(), against the real feed.
	cr.state_of(id)["stores"] = 0.0
	cr.sense()
	ok(cr._said.size() == 1, "walking past a croft says one thing about it")
	## The de-dup, put to a feed that would ACCEPT a repeat -- so the only
	## thing left that can refuse it is sense()'s own memory.
	var counter := CountFeed.new()
	root.add_child(counter)
	var real_feed := cr.feed
	cr.feed = counter
	cr.sense()
	ok(counter.n == 0, "and does not say it again, even to a feed that would take it")
	ok(cr._said.size() == 1, "and remembers nothing new as said")
	cr.feed = real_feed
	counter.free()
	## A CHANGED state is worth saying. Note the state must change the
	## SUMMARY, not merely the numbers.
	cr.state_of(id)["stores"] = Crofts.STORE_MAX
	cr.sense()
	ok(cr._said.size() == 2, "but a roof that has gone from cold to smoking is")
	## Out of earshot, nothing -- and the state is changed to one that has
	## NEVER been said, so this cannot pass through the de-dup door instead
	## of the door it is aimed at.
	pl.global_position = Vector3(at.x + Crofts.NOTICE_M * 4.0, 0.0, at.y)
	var was := cr._said.size()
	cr.state_of(id)["shut_until"] = cr.days + 5.0
	ok(Crofts.summary(cr.routine_of(id)) == "barred", "the croft now reads as something new")
	cr.sense()
	ok(cr._said.size() == was, "and a croft a kilometre off still says nothing at all")
	## Muted: refused rather than spent, so the caller comes back for it. The
	## line is still the fresh one, for the same reason.
	pl.global_position = Vector3(at.x, 0.0, at.y)
	pl.menu_open = "god"
	cr.sense()
	ok(cr._said.size() == was, "a line offered behind a menu is refused, not spent")
	pl.menu_open = ""
	cr.sense()
	ok(cr._said.size() > was, "and is said once the menu closes")
	cr.free()
	sky.free()
	feed.free()
	pl.free()
	net.free()


# --------------------------------------------------------------------- save

func _t_save() -> void:
	claim("save", 10)
	var net := _mk_net(_ring(8, 1200.0))
	var cr := _mk_cr(net)
	var id := String((cr.crofts[0] as Dictionary)["id"])
	cr.state_of(id)["stores"] = 77.0
	cr.state_of(id)["wash"] = "wet"
	cr.state_of(id)["shut_until"] = 41.5
	cr.advance(1.0)
	var d := cr.to_dict()
	ok(d.has("seed") and d.has("hours") and d.has("state"), "the save carries seed, clock and state")
	ok(not d.has("crofts") and not d.has("names"),
			"and does NOT carry the seats, which are a pure function of the net")
	var cr2 := _mk_cr(net)
	cr2.from_dict(d)
	ok(cr2.crofts.size() == cr.crofts.size(), "a restore seats the same households")
	near_f(float(cr2.state_of(id)["stores"]), float(cr.state_of(id)["stores"]), 0.001,
			"and their woodpiles came back")
	ok(String(cr2.state_of(id)["wash"]) == String(cr.state_of(id)["wash"]),
			"and what was on the line")
	near_f(float(cr2.state_of(id)["shut_until"]), 41.5, 0.001, "and how long they are barred in")
	near_f(cr2.days, cr.days, 0.001, "and the clock")
	## A croft the restored net has never heard of is dropped, not resurrected.
	var d2 := d.duplicate(true)
	(d2["state"] as Dictionary)["c9999#7"] = {"stores": 12.0}
	var cr3 := _mk_cr(net)
	cr3.from_dict(d2)
	ok(not cr3.state.has("c9999#7"), "a household the net has never heard of is dropped")
	## A restored pile is clamped: a save edited by hand cannot mint firewood.
	var d3 := d.duplicate(true)
	((d3["state"] as Dictionary)[id] as Dictionary)["stores"] = 1e9
	var cr4 := _mk_cr(net)
	cr4.from_dict(d3)
	ok(float(cr4.state_of(id)["stores"]) <= Crofts.STORE_MAX + 0.001,
			"and a restored pile is clamped to STORE_MAX")
	## An empty dict is a no-op, not a wipe.
	var n_before := cr.crofts.size()
	cr.from_dict({})
	ok(cr.crofts.size() == n_before, "an empty save changes nothing")
	cr.free()
	cr2.free()
	cr3.free()
	cr4.free()
	net.free()


# ------------------------------------------------------------------ staging

func _t_staging() -> void:
	claim("staging", 15)
	var net := _mk_net(_ring(8, 1200.0))
	var sky := FakeSky.new()
	root.add_child(sky)
	var cr := _mk_cr(net, sky)
	root.add_child(cr)
	var cd := cr.crofts[0] as Dictionary
	var at: Vector2 = cd["pos"]
	var here := Vector3(at.x, 0.0, at.y)
	ok(cr.staged_ids().is_empty(), "nothing is a scene node until somebody is near")
	ok(cr.near(here, Crofts.NOTICE_M).size() >= 1, "near() finds the croft you are standing at")
	ok(cr.near(Vector3(1e6, 0.0, 1e6), 100.0).is_empty(), "and nothing in an empty quarter")
	var rows := cr.near(here, 4000.0)
	var sorted := true
	for i in range(1, rows.size()):
		if float((rows[i] as Dictionary)["dist"]) < float((rows[i - 1] as Dictionary)["dist"]) - 0.001:
			sorted = false
	ok(sorted, "near() answers nearest first")
	cr._restage(here)
	ok(cr.staged_ids().size() >= 1, "walking up to one builds it")
	ok(cr.staged_ids().size() <= Crofts.MAX_STAGED,
			"and never more than MAX_STAGED at once (%d)" % cr.staged_ids().size())
	ok(cr.staged_ids().has(String(cd["id"])), "and the one you are standing at is among them")
	## Building a yard mows it. With no GrassSystem in the tree at all -- the
	## headless case -- that has to be a silent no-op rather than a crash,
	## and it still has to remember it did it so it does not try again.
	ok(cr._mown.size() >= 1, "and the yard was mown once, harmlessly, with no grass bound")
	var body := cr._staged[String(cd["id"])] as Node3D
	ok(body.get_node_or_null("Smoke") != null and body.get_node_or_null("Lamp") != null,
			"the yard has a chimney and a window")
	var fire: Variant = body.get_meta("fire", null)
	ok(fire is Firepit and (fire as Firepit).is_in_group("fires"),
			"and a REAL hearth in the fires group, so it warms whoever stands at it")
	## The body follows the sim rather than having one of its own.
	var st := cr.state_of(String(cd["id"]))
	st["stores"] = 0.0
	cr._apply(body, cd, Crofts.routine_at(cd, _day(4, 12.0), 0, 0, st))
	var smoke := body.get_node_or_null("Smoke") as Node3D
	ok(not smoke.visible, "an empty woodpile shows no smoke")
	st["stores"] = Crofts.STORE_MAX
	cr._apply(body, cd, Crofts.routine_at(cd, _day(4, 12.0), 0, 0, st))
	ok(smoke.visible, "and a full one does")
	## Hysteresis: walking out past STRIKE_RADIUS strikes it.
	cr._restage(Vector3(at.x + Crofts.STRIKE_RADIUS * 3.0, 0.0, at.y))
	ok(not cr.staged_ids().has(String(cd["id"])), "and walking away strikes the yard again")
	## The CAP. The ring's households are further apart than STAGE_RADIUS, so
	## `MAX_STAGED` is never the thing that stops the loop there and deleting
	## it survived the whole sweep. Crowd the roster on purpose.
	cr._clear_bodies()
	for k in 6:
		var extra := cd.duplicate(true)
		extra["id"] = "crowd%d" % k
		extra["pos"] = at + Vector2(6.0 * float(k), 4.0 * float(k))
		cr.crofts.append(extra)
		cr._by_id[String(extra["id"])] = extra
	var in_reach := cr.near(here, Crofts.STAGE_RADIUS).size()
	ok(in_reach > Crofts.MAX_STAGED,
			"more households in reach than MAX_STAGED (%d in reach)" % in_reach)
	cr._restage(here)
	ok(cr.staged_ids().size() == Crofts.MAX_STAGED,
			"and exactly MAX_STAGED yards get built (%d)" % cr.staged_ids().size())
	cr.free()
	sky.free()
	net.free()


# ------------------------------------------------------------------- purity

func _t_purity() -> void:
	claim("purity", 8)
	## `routine_at` is the whole feature. If it ever reaches for a node, a
	## clock or a roll, none of the sections above mean anything.
	var c := _croft(0.37, "steading")
	var st := _st(211.0, "out", 3.0)
	var a := Crofts.routine_at(c, _day(5, 14.25), 2, 1, st)
	var b := Crofts.routine_at(c, _day(5, 14.25), 2, 1, st)
	var same := true
	for k in a.keys():
		if str(a[k]) != str(b[k]):
			same = false
	ok(same, "the same arguments give the same day, twice")
	ok(a.size() == b.size() and a.size() >= 15, "and a full dictionary of beats (%d)" % a.size())
	## It must not have read the state's stores through a side channel.
	var poorer := Crofts.routine_at(c, _day(5, 14.25), 2, 1, _st(0.0, "out", 3.0))
	ok(String(poorer["hearth"]) != String(a["hearth"]),
			"a different woodpile gives a different hearth")
	var later := Crofts.routine_at(c, _day(5, 3.0), 2, 1, st)
	ok(String(later["work"]) != String(a["work"]), "a different hour gives a different day")
	var wilder := Crofts.routine_at(c, _day(5, 14.25), 4, 1, st)
	ok(String(wilder["shutters"]) != String(a["shutters"]), "a different sky gives a different house")
	var colder := Crofts.routine_at(c, _day(5, 14.25), 2, 3, st)
	ok(not is_equal_approx(float(colder["crop"]), float(a["crop"])),
			"a different season gives a different field")
	## And the source of the pure block reaches for nothing it should not.
	var fa := FileAccess.open("res://scripts/Crofts.gd", FileAccess.READ)
	var src := fa.get_as_text() if fa != null else ""
	if fa != null:
		fa.close()
	var body := _func_body(src, "routine_at")
	ok(body.length() > 400, "routine_at's body scanned back %d characters" % body.length())
	ok(not body.contains("get_tree") and not body.contains("get_node")
			and not body.contains("Time.") and not body.contains("self.")
			and not body.contains("randf"),
			"and reads no tree, no node, no clock and no roll")


func _func_body(src: String, fname: String) -> String:
	## Deliberately tolerant of BOTH tab and space indentation. The Dev-Input
	## suite's own body reader walked only while lines began with a tab, and
	## MainMenu.gd is space-indented, so it returned an empty body and every
	## check built on it passed on a scan that had found nothing (2026-09-09).
	## A scan that comes back empty agrees with everything, so this one is
	## proved against planted text before it is trusted on the truth.
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


# --------------------------------------------------------------- no bindings

func _t_no_bindings() -> void:
	claim("no_bindings", 8)
	## This project's standing rule is that a shadowed dev binding is
	## round-blocking. This file claims to add no binding; the claim is
	## asserted here against the source rather than in a ledger line.
	##
	## First the READER is proved on planted text carrying the defect, then
	## it is trusted on the truth -- because a scanner that returns nothing
	## agrees with everything (2026-09-09 18:00). The planted text is built
	## by CONCATENATION so that none of the tokens this section scans for
	## exist as literals in this file: a fixture that trips the scan it is
	## proving is a fixture that makes the real check unreadable.
	var fn := "func " + "_input"
	var planted := fn + "(event) -> void:\n\tif event is Input" + "EventKey:\n\t\tpass\n\nfunc other() -> void:\n\tpass\n"
	var planted_body := _func_body(planted, "_input")
	ok(planted_body.contains("EventKey"),
			"the body reader finds a planted input body before it is trusted")
	ok(not planted_body.contains("func other"), "and stops at the next function")
	var spaced := fn + "(event):\n    var x = K" + "EY_F1\n\nfunc z():\n    pass\n"
	ok(_func_body(spaced, "_input").contains("EY_F1"),
			"and reads a SPACE-indented body too, which is the bug that hid a whole scan")
	var reg := load("res://tests/DevInputRegistry.gd")
	ok(reg != null, "the dev-input registry is loadable")
	for path in ["res://scripts/Crofts.gd", "res://tests/CroftTests.gd"]:
		var fa := FileAccess.open(path, FileAccess.READ)
		var src := fa.get_as_text() if fa != null else ""
		if fa != null:
			fa.close()
		ok(src.length() > 500, "%s scanned back %d characters" % [path, src.length()])
		var cbs: Array = reg.input_callbacks(src)
		var keys := src.contains("K" + "EY_") or src.contains("Input" + "EventKey") \
				or src.contains("Input" + "Map") or src.contains("is_action" + "_pressed")
		ok(cbs.is_empty() and not keys,
				"%s declares no input callback and claims no key (%d callbacks)" % [path, cbs.size()])
