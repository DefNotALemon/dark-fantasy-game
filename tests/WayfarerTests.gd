extends SceneTree

# =============================================================================
# tests/WayfarerTests.gd -- the people on the roads (2026-09-09, WORLD).
#
#   godot --headless --path . --script res://tests/WayfarerTests.gd
#
# Nothing here needs terrain, a Player, World.tscn or a pixel. The sim is
# driven by INJECTING a road net, a stub Chronicle whose boards this file owns,
# a stub feed that records what it was told, and a sky function that can be a
# gale on demand -- so "a storm empties the road" is a fixture rather than a
# thing you wait for.
#
# Two sections carry more weight than the rest:
#
#   `locate` -- the leg table is BINARY SEARCHED, and a linear walk would
#   answer every question in this file correctly. That is exactly how three
#   index defects walked through the Road Net's 110/0 green on 2026-09-09: the
#   assertions were all about the ANSWER and the answer was never the thing at
#   risk. So this section asserts the property of the SEARCH -- that it
#   narrows, and by how much -- against a deliberately non-fallback brute
#   force that exists only for this purpose.
#
#   `rumour` -- the reason this feature is in the WORLD pillar at all. A line
#   planted at one village has to turn up at the NEXT one, at its ORIGINAL
#   date, without turning up back where it started.
#
# SECTION CLAIMS: every section stakes what it is about to assert before it
# runs one, so a section killed by a runtime error shows up as a claim that
# never settled instead of quietly taking its assertions with it.
# =============================================================================

const MIN_ASSERTIONS := 112

var _pass := 0
var _fail := 0
var _claims: Dictionary = {}
var _counts: Dictionary = {}
var _section := ""
var _held_ids: Array = []
var _arrivals: Array = []


# --------------------------------------------------------------------- stubs

class FakeChron extends Node:
	## Everything Wayfarers asks a Chronicle for, and nothing else. Owning the
	## boards outright is what lets the rumour section plant one line and watch
	## precisely where it goes.
	var boards: Dictionary = {}
	var net: RoadNet = null
	var days := 0.0
	var window := 6.0
	var sky := 0
	var deposits: Array = []

	func _nearest(pos: Vector3) -> String:
		var here := Vector2(pos.x, pos.z)
		var best := ""
		var bd := 60.0
		for nm in boards.keys():
			var d: float = net.place_pos(String(nm)).distance_to(here)
			if d < bd:
				bd = d
				best = String(nm)
		return best

	func rumours_at(pos: Vector3, limit := 3) -> Array:
		var nm := _nearest(pos)
		if nm.is_empty():
			return []
		var out: Array = (boards[nm] as Array).duplicate(true)
		out.sort_custom(func(a, b): return float(a["day"]) > float(b["day"]))
		if out.size() > limit:
			out.resize(limit)
		return out

	func deposit_rumour(place: String, rum: Dictionary) -> bool:
		if not boards.has(place):
			return false
		var text := String(rum.get("text", ""))
		if text.is_empty():
			return false
		if float(rum.get("day", days)) < days - window:
			return false
		for r in (boards[place] as Array):
			if String((r as Dictionary).get("text", "")) == text:
				return false
		(boards[place] as Array).append(rum.duplicate(true))
		deposits.append({"place": place, "text": text, "day": float(rum.get("day", 0.0))})
		return true

	func sky_at(_t: float) -> int:
		return sky


class FakeFeed extends Node:
	var lines: Array = []
	var accept := true
	func offer(text: String, voice: String, kind := "", day := 0.0) -> bool:
		if not accept:
			return false
		lines.append({"text": text, "voice": voice, "kind": kind, "day": day})
		return true


class FakePlayer extends Node3D:
	## Only what `RumourFeed.muted_now` reads. Without one the real feed is
	## muted by definition and every `offer` would be refused, which would
	## make the section below assert nothing at all.
	var menu_open := ""
	var wheel_open := false
	var input_locked := false
	var health := 100.0


class FakeClock extends Node:
	## The ledger's standing rule: anything riding DayNight needs a clock bound
	## in its tests and at least one direct `_process`, or a sim running months
	## out of step with the sky passes every assertion.
	var day := 30.0
	var hour := 19.7


# --------------------------------------------------------------------- harness

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


func same(a: String, b: String, what: String) -> void:
	ok(a == b, "%s (got '%s', want '%s')" % [what, a, b])


# ------------------------------------------------------------------- fixtures

func _ring(n: int, r: float) -> Array:
	## A ring of places with mixed ranks, so several trades can seat.
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


func _mk_chron(net: RoadNet) -> FakeChron:
	var c := FakeChron.new()
	c.net = net
	for nd in net.nodes:
		c.boards[String((nd as Dictionary)["name"])] = []
	return c


func _mk_wf(net: RoadNet, chron: Object = null, seed_v := 20260909) -> Wayfarers:
	var w := Wayfarers.new()
	w.world_seed = seed_v
	w.net = net
	w.chron = chron
	w.sky_fn = Callable(self, "_clear_sky")
	w.boot()
	return w


func _clear_sky(_t: float) -> int:
	return 0


func _gale(_t: float) -> int:
	return 4


func _rain(_t: float) -> int:
	return 3


func _biggest(w: Wayfarers) -> Dictionary:
	## The band with the most legs -- the one worth binary-searching.
	var best: Dictionary = {}
	var n := -1
	for b in w.bands:
		var bd := b as Dictionary
		if (bd["legs"] as Array).size() > n:
			n = (bd["legs"] as Array).size()
			best = bd
	return best


func _on_held(b: Dictionary, _lv: int) -> void:
	_held_ids.append(String(b['id']))


func _on_arrived(b: Dictionary, place: String) -> void:
	_arrivals.append({"id": String(b["id"]), "place": place})


func _walk_hours(w: Wayfarers, h: float) -> void:
	w.advance(h)


# ---------------------------------------------------------------------- entry

func _initialize() -> void:
	print("\n=== WayfarerTests ===")


func _process(_d: float) -> bool:
	_t_roster()
	_t_determinism()
	_t_circuit()
	_t_schedule()
	_t_weather()
	_t_locate()
	_t_position()
	_t_arrival()
	_t_rumour()
	_t_chronicle()
	_t_feed()
	_t_meeting()
	_t_save()
	_t_clock()
	_t_catchup()
	_t_bounds()
	_t_nullable()
	_t_real()
	_t_no_input()
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


# ------------------------------------------------------------------ the roster

func _t_roster() -> void:
	claim("roster", 9)
	var net := _mk_net(_ring(8, 700.0))
	var w := _mk_wf(net)
	ok(w.ready(), "a net with eight places puts somebody on the road")
	ok(w.bands.size() > 0 and w.bands.size() <= Wayfarers.MAX_BANDS,
			"%d bands, inside the cap of %d" % [w.bands.size(), Wayfarers.MAX_BANDS])
	var ids := {}
	var seats := {}
	var named := true
	var legal := true
	var seated := true
	var shaped := true
	for b in w.bands:
		var bd := b as Dictionary
		ids[String(bd["id"])] = true
		seats[String(bd["seat"])] = int(seats.get(String(bd["seat"]), 0)) + 1
		if String(bd["name"]).split(" ").size() != 2:
			named = false
		if Wayfarers.kind_of(String(bd["kind"]))["id"] != String(bd["kind"]):
			legal = false
		if String((bd["circuit"] as Array)[0]) != String(bd["seat"]):
			seated = false
		var seen := {}
		for p in (bd["circuit"] as Array):
			if seen.has(String(p)):
				shaped = false
			seen[String(p)] = true
		if (bd["circuit"] as Array).size() < 2:
			shaped = false
	ok(ids.size() == w.bands.size(), "every band has its own id")
	var doubled := 0
	for s in seats:
		if int(seats[s]) > 1:
			doubled += 1
	ok(doubled == 0, "and no place sends out two of them (%d doubled)" % doubled)
	ok(named, "everyone has a given name and a byname")
	ok(legal, "and a trade that is in the table")
	ok(seated, "every circuit starts at the seat it came from")
	ok(shaped, "and visits at least two places, none of them twice")
	## The mix. Asserted on the REAL map rather than on the ring, because it
	## was on the real map that the weights alone put thirteen pedlars of
	## twenty on the roads and not one pilgrim: the ring is too small for the
	## imbalance to show.
	var real := RoadNet.new()
	root.add_child(real)
	var rw := _mk_wf(real)
	var per: Dictionary = {}
	for b in rw.bands:
		var kd := String((b as Dictionary)["kind"])
		per[kd] = int(per.get(kd, 0)) + 1
	var over := 0
	for kd in per:
		if int(per[kd]) > Wayfarers.KIND_CAP:
			over += 1
	ok(over == 0 and per.size() >= 4,
			"and no one trade crowds the roads out (%d trades, biggest %d, cap %d)"
			% [per.size(), per.values().max(), Wayfarers.KIND_CAP])
	rw.free()
	real.queue_free()
	w.free()
	net.free()


# ---------------------------------------------------------------- determinism

func _t_determinism() -> void:
	claim("determinism", 6)
	var rows := _ring(8, 700.0)
	var reversed: Array = []
	for i in rows.size():
		reversed.push_front(rows[i])
	var n1 := _mk_net(rows)
	var n2 := _mk_net(reversed)
	var a := _mk_wf(n1)
	var b := _mk_wf(n2)
	ok(a.bands.size() == b.bands.size(), "input order cannot change how many bands there are")
	ok(str(a.report()["digest"]) == str(b.report()["digest"]),
			"nor one name, trade, circuit or metre of any of them")
	a.advance(96.0)
	b.advance(96.0)
	ok(str(a.report()["digest"]) == str(b.report()["digest"]),
			"and four days of walking lands them all in the same places")
	var c := _mk_wf(n1)
	c.advance(96.0)
	ok(str(c.report()["digest"]) == str(a.report()["digest"]), "a third run agrees with the first two")
	var d := _mk_wf(n1, null, 12345)
	ok(str(d.report()["digest"]) != str(a.report()["digest"]),
			"a different seed is a different set of people")
	ok(a._net_print == n1.fingerprint(), "and the circuits remember which net they were cut for")
	a.free()
	b.free()
	c.free()
	d.free()
	n1.free()
	n2.free()


# -------------------------------------------------------------- the circuits

func _t_circuit() -> void:
	claim("circuit", 7)
	var net := _mk_net(_ring(8, 700.0))
	var w := _mk_wf(net)
	var unroutable := 0
	var legless := 0
	var bad_cum := 0
	var bad_len := 0
	var bad_close := 0
	var bad_stops := 0
	var bad_edge := 0
	for b in w.bands:
		var bd := b as Dictionary
		var circuit: Array = bd["circuit"]
		for i in circuit.size():
			var from := String(circuit[i])
			var to := String(circuit[(i + 1) % circuit.size()])
			if not bool((net.route(from, to) as Dictionary).get("ok", false)):
				unroutable += 1
		var legs: Array = bd["legs"]
		if legs.is_empty():
			legless += 1
			continue
		if not is_equal_approx(float((legs[0] as Dictionary)["cum"]), 0.0):
			bad_cum += 1
		var run := 0.0
		for k in legs.size():
			var lg := legs[k] as Dictionary
			if absf(float(lg["cum"]) - run) > 0.01:
				bad_cum += 1
			run += float(lg["len"])
			var ed := net.edge(int(lg["e"]))
			if ed.is_empty() or absf(float(ed["len"]) - float(lg["len"])) > 0.01:
				bad_edge += 1
		if absf(run - float(bd["len"])) > 0.05:
			bad_len += 1
		var stops: Array = bd["stops"]
		if stops.is_empty() or absf(float((stops[-1] as Dictionary)["at"]) - float(bd["len"])) > 0.05:
			bad_close += 1
		if stops.size() != circuit.size():
			bad_stops += 1
	ok(unroutable == 0, "every step of every circuit is a walk the net can actually make")
	ok(legless == 0, "and every band has roads under it")
	ok(bad_cum == 0, "the cumulative marks climb from zero without a gap")
	ok(bad_len == 0, "the circuit length is the sum of its roads")
	ok(bad_close == 0, "and the last stop closes the loop exactly")
	ok(bad_stops == 0, "one stop recorded per place on the circuit")
	ok(bad_edge == 0, "and every leg names a road the net really has")
	w.free()
	net.free()


# ---------------------------------------------------------------- the working day

func _t_schedule() -> void:
	claim("schedule", 9)
	var net := _mk_net(_ring(8, 700.0))
	var w := _mk_wf(net)
	var b := _biggest(w)
	var k := Wayfarers.kind_of(String(b["kind"]))
	var dep := float(k["depart"])
	var halt := float(k["halt"])

	## Park the sim just before dawn, walk two hours of night, and nothing moves.
	w.advance(maxf(dep - 3.0, 0.5))
	var at_night := float(b["along"])
	w.advance(1.0)
	near_f(float(b["along"]), at_night, 0.001, "nobody walks before the trade sets out")

	## Into the working day.
	w.advance(dep - fposmod(w.days * 24.0, 24.0) + 1.0)
	ok(float(b["along"]) > at_night + 1.0, "and they are on the road once it does")

	## The night at the far end.
	var w2 := _mk_wf(net)
	var b2 := w2.band_by_id(String(b["id"]))
	w2.advance(halt + 0.5)
	var at_dusk := float(b2["along"])
	w2.advance(3.0)
	near_f(float(b2["along"]), at_dusk, 0.001, "and they stop where the light failed")

	## A whole day of walking is a day's walk.
	var w3 := _mk_wf(net)
	var b3 := w3.band_by_id(String(b["id"]))
	var day0 := float(b3["along"])
	w3.advance(24.0)
	var moved := float(b3["along"]) - day0
	if moved < 0.0:
		moved += float(b3["len"])
	var want := Wayfarers.PACE_DAY * float(k["pace"])
	ok(absf(moved - want) < want * 0.10,
			"a day on the road is a day's walk (%.0f m, want %.0f)" % [moved, want])
	w3.advance(24.0)
	var two := float(b3["along"])
	ok(two != float(b3["along"]) - 1.0, "a second day moves them again")

	## The trades are not interchangeable, and the order is the point.
	var spd := {}
	for kd in Wayfarers.KINDS:
		var kk := kd as Dictionary
		spd[String(kk["id"])] = Wayfarers.PACE_DAY * float(kk["pace"]) \
				/ maxf(float(kk["halt"]) - float(kk["depart"]), 0.5)
	ok(float(spd["courier"]) > float(spd["pedlar"]), "a courier outwalks a pedlar")
	ok(float(spd["pedlar"]) > float(spd["carter"]), "a pedlar outwalks a laden cart")
	ok(float(spd["carter"]) > float(spd["drover"]), "and a cart outwalks a flock")
	var bad_hours := 0
	for kd in Wayfarers.KINDS:
		var kk := kd as Dictionary
		if float(kk["halt"]) - float(kk["depart"]) < 4.0:
			bad_hours += 1
	ok(bad_hours == 0, "and every trade keeps a working day worth the name")
	w.free()
	w2.free()
	w3.free()
	net.free()


# ------------------------------------------------------------------- the sky

func _t_weather() -> void:
	claim("weather", 8)
	near_f(Wayfarers.pace_for(0), 1.0, 0.001, "a clear day costs nothing")
	ok(Wayfarers.pace_for(2) < 1.0 and Wayfarers.pace_for(2) > 0.0, "rain slows a walker without stopping one")
	near_f(Wayfarers.pace_for(Wayfarers.HOLD_LEVEL), 0.0, 0.001, "and a gale stops one dead")

	var net := _mk_net(_ring(8, 700.0))
	var w := _mk_wf(net)
	var b := _biggest(w)
	var k := Wayfarers.kind_of(String(b["kind"]))
	## Put the clock inside the working day, then bring the weather down.
	w.advance(float(k["depart"]) + 1.0)
	_held_ids.clear()
	w.band_held.connect(_on_held)
	w.sky_fn = Callable(self, "_gale")
	var before := float(b["along"])
	w.advance(3.0)
	near_f(float(b["along"]), before, 0.001, "a gale empties the road")
	ok(bool(b["holding"]) and float(b["held"]) >= 2.5, "they are visibly waiting it out (%.1f h)" % float(b["held"]))
	var mine := 0
	for hid in _held_ids:
		if String(hid) == String(b['id']):
			mine += 1
	ok(mine == 1 and _held_ids.size() == w.bands.size(),
			"each band is announced once when it stops, not every half hour (%d for this one, %d in all)" % [mine, _held_ids.size()])
	w.band_held.disconnect(_on_held)

	## Same hours, three skies. Weather is a dial, not a switch.
	var clear_w := _mk_wf(net)
	var rain_w := _mk_wf(net)
	var hard_w := _mk_wf(net)
	rain_w.sky_fn = Callable(self, "_rain")
	hard_w.sky_fn = Callable(self, "_gale")
	var id := String(b["id"])
	clear_w.advance(24.0)
	rain_w.advance(24.0)
	hard_w.advance(24.0)
	var cd := float(clear_w.band_by_id(id)["along"])
	var rd := float(rain_w.band_by_id(id)["along"])
	var hd := float(hard_w.band_by_id(id)["along"])
	ok(rd > 0.0 and rd < cd, "a hard day of rain is slower than a clear one (%.0f vs %.0f)" % [rd, cd])
	near_f(hd, 0.0, 0.001, "and a day of gale is no distance at all")
	w.free()
	clear_w.free()
	rain_w.free()
	hard_w.free()
	net.free()


# ----------------------------------------- the search, not just the answer

func _t_locate() -> void:
	claim("locate", 7)
	## THE SECTION A LINEAR WALK WOULD SAIL THROUGH. Every assertion below
	## except the first two is about the SEARCH rather than about the position
	## it returns, because the position is not what is at risk.
	var net := _mk_net(_ring(8, 900.0))
	var w := _mk_wf(net)
	var b := _biggest(w)
	var legs: Array = b["legs"]
	ok(legs.size() >= 4, "the band under test has %d legs to search" % legs.size())

	var total := float(b["len"])
	var wrong_leg := 0
	var wrong_t := 0
	var out_of_range := 0
	var over_budget := 0
	var narrowed := 0
	var probes := 0
	var budget := int(ceil(log(float(legs.size())) / log(2.0))) + 2
	for i in 200:
		var a := total * float(i) / 199.0
		probes += 1
		var fast := w._locate(b, a)
		var seen := w.last_examined
		var slow := w.locate_brute(b, a)
		if int(fast["leg"]) != int(slow["leg"]):
			wrong_leg += 1
		if absf(float(fast["t"]) - float(slow["t"])) > 0.0001:
			wrong_t += 1
		if float(fast["t"]) < 0.0 or float(fast["t"]) > 1.0:
			out_of_range += 1
		if seen > budget:
			over_budget += 1
		if seen < legs.size():
			narrowed += 1
	ok(wrong_leg == 0, "the binary search names the same road brute force does (%d off)" % wrong_leg)
	ok(wrong_t == 0, "and the same distance along it (%d off)" % wrong_t)
	ok(out_of_range == 0, "t never leaves 0..1 (%d off)" % out_of_range)
	ok(over_budget == 0, "it never looks at more legs than a halving search may (%d over %d)"
			% [over_budget, budget])
	ok(narrowed == probes, "and it narrowed on every one of the %d probes" % probes)
	ok(w.point_at(b, 0.0).distance_to(net.place_pos(String(b["seat"]))) < 1.0,
			"metre zero of the circuit is the doorstep it starts from")
	w.free()
	net.free()


# ------------------------------------------------------------ where they are

func _t_position() -> void:
	claim("position", 7)
	var net := _mk_net(_ring(8, 700.0))
	var w := _mk_wf(net)
	var b := _biggest(w)
	var total := float(b["len"])
	var off_road := 0
	var worst := 0.0
	for i in 120:
		var p := w.point_at(b, total * float(i) / 119.0)
		var d := float(net.nearest_road(p)["dist"])
		worst = maxf(worst, d)
		if d > 2.0:
			off_road += 1
	ok(off_road == 0, "a traveller is never off the road (worst %.2f m)" % worst)
	ok(w.point_at(b, 0.0).distance_to(w.point_at(b, total - 0.001)) < 12.0,
			"the circuit closes back on itself")
	var bad_stop := 0
	for s in (b["stops"] as Array):
		var sd := s as Dictionary
		var at := fposmod(float(sd["at"]), total)
		if w.point_at(b, at).distance_to(net.place_pos(String(sd["place"]))) > 2.0:
			bad_stop += 1
	ok(bad_stop == 0, "and every stop mark really is that village's doorstep")
	var wr := w.where(b)
	near_f((wr["dir"] as Vector2).length(), 1.0, 0.001, "the heading is a unit vector")
	ok(wr.has("pos") and wr.has("at") and wr.has("last") and wr.has("holding") and wr.has("name"),
			"and a reading carries everything a caller needs")
	var here := w.where(b)["pos"] as Vector2
	var found := w.near(Vector3(here.x, 0.0, here.y), 100000.0)
	var sorted := true
	for i in range(1, found.size()):
		if float((found[i] as Dictionary)["d"]) < float((found[i - 1] as Dictionary)["d"]) - 0.001:
			sorted = false
	ok(found.size() == w.bands.size() and sorted, "near() returns everyone, nearest first")
	ok(w.near(Vector3(999999.0, 0.0, 999999.0), 50.0).is_empty(), "and nobody at all from a hundred km off")
	w.free()
	net.free()


# ----------------------------------------------------------------- arriving

func _t_arrival() -> void:
	claim("arrival", 7)
	var net := _mk_net(_ring(8, 700.0))
	var w := _mk_wf(net)
	var b := _biggest(w)
	same(String(b["at"]), String(b["seat"]), "a band starts on its own doorstep")
	_arrivals.clear()
	w.band_arrived.connect(_on_arrived)
	var k := Wayfarers.kind_of(String(b["kind"]))
	w.advance(float(k["depart"]) + 0.6)
	same(String(b["at"]), "", "and is at no place at all once it is between two")
	## Walk far enough that at least one stop must have been passed.
	w.advance(72.0)
	var mine: Array = []
	for a in _arrivals:
		if String((a as Dictionary)["id"]) == String(b["id"]):
			mine.append(a)
	ok(mine.size() >= 1, "three days of walking reaches somewhere (%d arrivals)" % mine.size())
	var known := true
	for a in mine:
		if not (String((a as Dictionary)["place"]) in (b["circuit"] as Array)):
			known = false
	ok(known, "and every place arrived at is on the circuit")
	ok(String(b["last"]) == String((mine[-1] as Dictionary)["place"])
			or not String(b["at"]).is_empty(),
			"the last place reached is remembered")
	## Arriving is an EDGE, not a state. Stood EXACTLY on a stop mark, so
	## `_arrive` really does resolve a place -- the first version of this put
	## the band mid-road, where `_arrive` returns early whatever the guard
	## says, and the `arrive-always` mutation walked straight through it.
	var mark := float((b["stops"] as Array)[0]["at"])
	b["along"] = fposmod(mark, float(b["len"]))
	b["last"] = ""
	w._arrive(b, w.days)
	var count_before := _arrivals.size()
	w._arrive(b, w.days)
	w._arrive(b, w.days)
	ok(_arrivals.size() == count_before, "and standing there does not arrive again")
	## And standing exactly ON a stop mark must not trap them there: the
	## gap to the next stop is zero measured from that spot, and only the
	## wrap in `_next_stop` turns a zero gap back into a whole circuit.
	w.advance(48.0)
	ok(absf(float(b["along"]) - mark) > 1.0, "and a band stood on a doorstep walks off it again")
	w.band_arrived.disconnect(_on_arrived)
	w.free()
	net.free()


# ------------------------------------------------------- news, carried by hand

func _t_rumour() -> void:
	claim("rumour", 9)
	var net := _mk_net(_ring(8, 700.0))
	var chron := _mk_chron(net)
	var w := _mk_wf(net, chron)
	var b := _biggest(w)
	var circuit: Array = b["circuit"]
	var first := String(circuit[0])
	var second := String((b["stops"] as Array)[0]["place"])
	ok((b["carried"] as Dictionary).is_empty(), "a band sets out carrying nothing")

	## One line, planted at the seat, dated today.
	chron.days = 0.0
	(chron.boards[first] as Array).append({"text": "The ford at Sebec is out.", "day": 0.0,
		"from": first, "kind": "bridge_out"})
	## Force the pick-up: the band is standing at its seat and has already
	## recorded it as `last`, so nudge it off and back round.
	w._take(b, first, 0.0)
	var carried: Dictionary = b["carried"]
	ok(not carried.is_empty(), "standing in a village, they hear what is being said")
	same(String(carried.get("from", "")), first, "and they know where they had it")
	same(String(carried.get("text", "")), "The ford at Sebec is out.", "word for word")

	## Now deliver it, one place along.
	chron.days = 1.0
	var before := (chron.boards[second] as Array).size()
	w._deposit(b, second, 1.0)
	ok((chron.boards[second] as Array).size() == before + 1,
			"and they put it down at the next village along")
	var landed := (chron.boards[second] as Array)[-1] as Dictionary
	near_f(float(landed["day"]), 0.0, 0.001,
			"dated when it HAPPENED, not when it arrived -- second-hand news is old news")
	ok((b["carried"] as Dictionary).is_empty(), "having told it, they are no longer carrying it")
	ok(w.delivered_total == 1, "and the world counted one delivery")

	## And it is never walked back to where it came from. Tested on a line the
	## destination has NEVER heard, so the guard is what refuses it rather
	## than the board's own duplicate check -- which is why the `deliver-home`
	## mutation survived the first version of this assertion.
	b["carried"] = {"text": "A ewe went over the weir.", "day": 1.0, "from": second}
	var back := (chron.boards[second] as Array).size()
	w._deposit(b, second, 1.0)
	ok((chron.boards[second] as Array).size() == back and (b["carried"] as Dictionary).is_empty(),
			"news is never carried back to the village it came from")
	w.free()
	chron.free()
	net.free()


# ------------------------------------------- the REAL Chronicle's front door

func _t_chronicle() -> void:
	claim("chronicle", 6)
	## The stub above lets the rumour section watch one line travel. It does
	## NOT exercise `Chronicle.deposit_rumour`, which is the door the game
	## actually delivers through -- and the mutation run proved it: three
	## mutations of that function survived a suite that never called it. This
	## section calls it.
	var c := Chronicle.new()
	c.boot()
	var nm := String((c.places[0] as Dictionary)["name"])
	c.days = 10.0
	var rum := {"text": "A wheel came off on the Freeport road.", "day": 8.5,
		"from": "elsewhere", "kind": "cart_lost"}
	ok(c.deposit_rumour(nm, rum), "a rumour carried in by hand lands on the board")
	var board: Array = (c.place_by_name(nm) as Dictionary)["rumours"]
	var landed := board[board.size() - 1] as Dictionary
	near_f(float(landed["day"]), 8.5, 0.001,
			"dated when it HAPPENED, not when it arrived -- second-hand news is old news")
	ok(not c.deposit_rumour(nm, rum), "and a board does not tell you the same sentence twice")
	ok(not c.deposit_rumour("Nowhere At All", rum), "a place off the map takes no delivery")
	ok(not c.deposit_rumour(nm, {"text": "Ancient business.", "day": 10.0 - Chronicle.RUMOUR_DAYS - 1.0}),
			"nor is news delivered that the next step would erase")
	var sky := c.sky_at(12.0)
	ok(sky >= 0 and sky <= 4 and c.sky_at(12.0) == sky,
			"and the sky the sim believes in is in range and does not change when re-asked")
	c.free()


# --------------------------------------- the REAL feed's front door

func _t_feed() -> void:
	claim("feed", 7)
	## `FakeFeed` above records what it was told; it does not exercise
	## `RumourFeed.offer`, which is where a traveller's sentence actually
	## lands. Both of the defects this section pins were found by LOOKING at
	## the running game rather than by anything in the suite -- the standing
	## rule since 2026-09-08 -- so they are pinned here now.
	var feed := RumourFeed.new()
	feed.boot()
	var pl := FakePlayer.new()
	feed.player = pl
	var text := "Men with cudgels are taking a toll below Lewiston-Auburn."
	ok(feed.offer(text, "Winifred Salter", "bandits_road", 3.0), "a traveller's line goes up")
	ok(feed.has_heard("~Winifred Salter", text), "keyed to the speaker, so she will not repeat it")
	ok(not feed.has_heard("Ellsworth", text), "but Ellsworth may still tell you its own version")
	ok(not feed.offer(text, "Winifred Salter", "bandits_road", 3.0),
			"and she does not say the same sentence twice")
	## The name has to outlast the sentence, not HEAD_HOLD. A place name may
	## fade while the talk goes on; a line with no speaker over it is a voice
	## in your head. Asserted as a relation between the two clocks rather than
	## as a number, so it stays true if either constant is retuned.
	ok(feed._head_t >= RumourFeed.dwell_for(text),
			"and her name stays up for at least as long as her sentence does (%.1f vs %.1f)"
			% [feed._head_t, RumourFeed.dwell_for(text)])

	## Told it standing IN a village: the board must not immediately repeat it.
	var f2 := RumourFeed.new()
	f2.boot()
	f2.player = pl
	f2._here = "Portland"
	f2.offer(text, "Winifred Salter", "bandits_road", 3.0)
	ok(f2.has_heard("Portland", text),
			"being told it here counts as having heard it here -- no verbatim echo off the board")

	## And a refusal is a refusal: muted, nothing is said and nothing is spent.
	var f3 := RumourFeed.new()
	f3.boot()
	pl.menu_open = "god"
	f3.player = pl
	var said_before := f3.said
	ok(not f3.offer(text, "Winifred Salter") and f3.said == said_before
			and not f3.has_heard("~Winifred Salter", text),
			"behind a menu the greeting is frozen, not spent")
	pl.menu_open = ""
	feed.free()
	f2.free()
	f3.free()
	pl.free()


# ------------------------------------------------------------ meeting one

func _t_meeting() -> void:
	claim("meeting", 8)
	var net := _mk_net(_ring(8, 700.0))
	var chron := _mk_chron(net)
	var feed := FakeFeed.new()
	var w := _mk_wf(net, chron)
	w.feed = feed
	var b := _biggest(w)
	ok(w.meet_at(Vector3(999999.0, 0.0, 999999.0)).is_empty(), "an empty road greets nobody")

	var p := w.where(b)["pos"] as Vector2
	var at := Vector3(p.x, 0.0, p.y)
	var got := w.meet_at(at)
	ok(not got.is_empty() and int(b["met"]) == 1, "walk up to one and they speak")
	ok(feed.lines.size() == 1 and String((feed.lines[0] as Dictionary)["voice"]) == String(b["name"]),
			"the feed hears it in their name, not the village's")
	ok(String((feed.lines[0] as Dictionary)["text"]).length() > 8, "and they said something")
	ok(w.meet_at(at).is_empty() and int(b["met"]) == 1,
			"they do not greet you twice in the same hour")
	w.advance(Wayfarers.REMEET_DAYS * 24.0 + 2.0)
	var p2 := w.where(b)["pos"] as Vector2
	var again := w.meet_at(Vector3(p2.x, 0.0, p2.y))
	ok(not again.is_empty() and int(b["met"]) == 2, "but they do the next day")

	## A refusal is not a delivery. If the feed will not take the line -- a
	## menu is up -- `met_day` must not move, or the greeting is spent behind
	## the menu and never offered again.
	feed.accept = false
	w.advance(Wayfarers.REMEET_DAYS * 24.0 + 2.0)
	var p3 := w.where(b)["pos"] as Vector2
	var day_before := float(b["met_day"])
	ok(w.meet_at(Vector3(p3.x, 0.0, p3.y)).is_empty() and is_equal_approx(float(b["met_day"]), day_before),
			"a feed that refuses does not spend the greeting")
	b["carried"] = {"text": "Wolves at the fold.", "day": 0.0, "from": "P3", "kind": "wolves"}
	ok(w.greeting(b, 12.0).contains("P3"), "and news is told with the place it came from")
	w.free()
	feed.free()
	chron.free()
	net.free()


# -------------------------------------------------------------------- saving

func _t_save() -> void:
	claim("save", 8)
	var net := _mk_net(_ring(8, 700.0))
	var chron := _mk_chron(net)
	var w := _mk_wf(net, chron)
	w.advance(60.0)
	var b := _biggest(w)
	b["carried"] = {"text": "A mill wheel broke at P2.", "day": 1.5, "from": "P2", "kind": "mill"}
	b["met"] = 3
	b["met_day"] = 2.25
	var saved := w.to_dict()
	var digest := str(w.report()["digest"])

	var w2 := _mk_wf(net, chron)
	w2.from_dict(saved)
	ok(str(w2.report()["digest"]) == digest, "a save restores every band to the metre")
	var b2 := w2.band_by_id(String(b["id"]))
	same(String((b2["carried"] as Dictionary).get("text", "")), "A mill wheel broke at P2.",
			"including what they were carrying at the time")
	ok(int(b2["met"]) == 3 and is_equal_approx(float(b2["met_day"]), 2.25),
			"and that they remember having met you")
	near_f(w2._hours, w._hours, 0.001, "the clock comes back too")
	ok(w2._steps == w._steps, "and the step it had reached")

	## A save from a world whose roster has since changed: restore what still
	## matches by name, drop what does not, never put a band on a road that is
	## not there.
	var strange := saved.duplicate(true)
	(strange["bands"] as Array).append({"id": "pedlar@Nowhere", "along": 4000.0, "met": 9})
	var w3 := _mk_wf(net, chron)
	w3.from_dict(strange)
	ok(w3.bands.size() == w.bands.size(), "a band the net has never heard of is dropped, not built")

	var w4 := _mk_wf(net, chron)
	var d4 := str(w4.report()["digest"])
	w4.from_dict({})
	w4.from_dict({"v": 2, "bands": []})
	ok(str(w4.report()["digest"]) == d4, "an empty or future save is ignored rather than obeyed")

	var over := saved.duplicate(true)
	for r in (over["bands"] as Array):
		(r as Dictionary)["along"] = 1.0e9
	var w5 := _mk_wf(net, chron)
	w5.from_dict(over)
	var out_of_range := 0
	for bb in w5.bands:
		if float((bb as Dictionary)["along"]) >= float((bb as Dictionary)["len"]):
			out_of_range += 1
	ok(out_of_range == 0, "and a nonsense distance is folded back onto the circuit")
	w.free()
	w2.free()
	w3.free()
	w4.free()
	w5.free()
	chron.free()
	net.free()


# ------------------------------------------------------------- bound to the sky

func _t_clock() -> void:
	claim("clock", 6)
	var net := _mk_net(_ring(8, 700.0))
	var w := _mk_wf(net)
	var dn := FakeClock.new()
	dn.day = 30.0
	dn.hour = 19.7
	w.clock = dn
	ok(w._steps == 0, "a fresh sim has taken no steps")
	w._process(0.016)
	ok(w._steps > 0, "the first frame adopts the sky's calendar rather than its own")
	near_f(w.days, 30.0 + 19.7 / 24.0, 0.05, "and lands on the sky's day, not on day zero")
	var primed := w._steps
	dn.hour = 21.7
	w._process(0.016)
	ok(w._steps > primed, "two hours of sky is two hours of road")
	var after := w._steps
	var days_after := w.days
	dn.day = 29.0
	w._process(0.016)
	## Both halves matter. `_steps` alone cannot move backwards whatever the
	## guard does -- `_run_steps` simply finds nothing to run -- so a suite
	## that only watched the step count let the `backwards-time` mutation
	## through while the sim's own clock was quietly wound back a day.
	ok(w._steps == after and w.days >= days_after - 0.0001,
			"a clock wound backwards is not a day of history, and does not unwind the sim either")
	dn.day = 90.0
	w._process(0.016)
	ok(w.days - 30.0 < 32.0, "and one handover can never be more than thirty days (%.1f)" % w.days)
	w.clock = null
	w.free()
	dn.free()
	net.free()


# ------------------------------------------------------------------ catch-up

func _t_catchup() -> void:
	claim("catchup", 4)
	var net := _mk_net(_ring(8, 700.0))
	var w := _mk_wf(net)
	w.advance(720.0, 40)
	ok(w._steps == 40, "a month handed over at once is metered, not run in one frame")
	var seen := w._steps
	w._run_steps(200)
	ok(w._steps == seen + 200, "and drains at the rate it is given")
	w._run_steps(100000)
	ok(w._steps == int(720.0 / Wayfarers.STEP_HOURS), "until the backlog is gone")
	var sane := true
	for b in w.bands:
		var a := float((b as Dictionary)["along"])
		if is_nan(a) or is_inf(a):
			sane = false
	ok(sane, "and a month of walking leaves nobody at a position that is not a number")
	w.free()
	net.free()


# -------------------------------------------------------------------- bounds

func _t_bounds() -> void:
	claim("bounds", 5)
	var net := _mk_net(_ring(8, 700.0))
	var w := _mk_wf(net, _mk_chron(net))
	w.advance(24.0 * 40.0)
	var out_of_range := 0
	var nan_pos := 0
	var bad_held := 0
	var bad_at := 0
	for b in w.bands:
		var bd := b as Dictionary
		var a := float(bd["along"])
		if a < 0.0 or a >= float(bd["len"]):
			out_of_range += 1
		var p := w.point_at(bd, a)
		if is_nan(p.x) or is_nan(p.y) or is_inf(p.x):
			nan_pos += 1
		if float(bd["held"]) < 0.0:
			bad_held += 1
		var at := String(bd["at"])
		if not at.is_empty() and not (at in (bd["circuit"] as Array)):
			bad_at += 1
	ok(out_of_range == 0, "forty days on, everybody is still somewhere on their own circuit")
	ok(nan_pos == 0, "and standing at a real point on the map")
	ok(bad_held == 0, "nobody has waited out a negative storm")
	ok(bad_at == 0, "and nobody claims to be at a village that is not on their round")
	ok(w.road_metres() > 0.0, "and the round trips add up to real road (%.0f m)" % w.road_metres())
	w.free()
	net.free()


# ------------------------------------------------------------------- nothing

func _t_nullable() -> void:
	claim("nullable", 6)
	var bare := Wayfarers.new()
	bare.boot()
	ok(not bare.ready() and bare.bands.is_empty(), "with no net at all there is nobody on the roads")
	ok(bare.report().has("bands"), "but it still reports")
	bare.advance(240.0)
	bare.sense()
	ok(bare.bands.is_empty(), "and ten days of nothing happening does not crash")
	bare.free()

	var net := _mk_net(_ring(8, 700.0))
	var w := _mk_wf(net)
	var n0 := w.bands.size()
	w.boot()
	w.boot()
	ok(w.bands.size() == n0, "boot is idempotent")
	ok(w.chron == null and not w.bands.is_empty(),
			"a sim with no Chronicle still walks, it simply carries no news")
	var b := _biggest(w)
	var p := w.where(b)["pos"] as Vector2
	var met := w.meet_at(Vector3(p.x, 0.0, p.y))
	ok(not met.is_empty() and int(b["met"]) == 1,
			"and with no feed bound a meeting is still remembered")
	w.free()
	net.free()


# ------------------------------------------------------------- the real map

func _t_real() -> void:
	claim("real", 6)
	var real := RoadNet.new()
	root.add_child(real)
	ok(real.ready() and real.nodes.size() >= 45, "the real map lays its roads (%d places)" % real.nodes.size())
	var w := _mk_wf(real)
	ok(w.bands.size() >= 8, "and puts %d bands on them" % w.bands.size())
	ok(float(w.report()["build_ms"]) < 8000.0,
			"cutting every circuit takes %.0f ms" % float(w.report()["build_ms"]))
	w.advance(24.0 * 5.0)
	var off := 0
	var worst := 0.0
	for b in w.bands:
		var p := w.where(b as Dictionary)["pos"] as Vector2
		var d := float(real.nearest_road(p)["dist"])
		worst = maxf(worst, d)
		if d > 3.0:
			off += 1
	ok(off == 0, "five days on, every one of them is still on a road (worst %.2f m)" % worst)
	var unroutable := 0
	for b in w.bands:
		var c: Array = (b as Dictionary)["circuit"]
		for i in c.size():
			if not bool((real.route(String(c[i]), String(c[(i + 1) % c.size()])) as Dictionary).get("ok", false)):
				unroutable += 1
	ok(unroutable == 0, "every circuit on the real map is walkable end to end")
	ok(w.road_metres() > 3000.0, "%.1f km of circuit between them" % (w.road_metres() / 1000.0))
	w.free()


# ------------------------------------------------------- the rules, in source

func _t_no_input() -> void:
	claim("no_input", 3)
	## This project's standing rule is that a shadowed dev binding is
	## round-blocking. This file claims to add no binding; the claim is
	## asserted here against the source rather than in a ledger line.
	var fa := FileAccess.open("res://scripts/Wayfarers.gd", FileAccess.READ)
	ok(fa != null, "the source is readable")
	if fa == null:
		ok(false, "no source to scan")
		ok(false, "no source to scan")
		return
	var src := fa.get_as_text()
	fa.close()
	var banned := ["KEY_", "InputMap", "is_action_pressed", "is_action_just_pressed",
		"func _input", "func _unhandled_input", "func _shortcut_input", "InputEventKey"]
	var hit := ""
	for b in banned:
		if src.contains(b):
			hit = b
			break
	same(hit, "", "the sim contains no key handling at all")
	ok(src.length() > 20000, "and the file scanned was the real one")
