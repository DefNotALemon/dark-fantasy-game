extends SceneTree

# =============================================================================
# tests/RoadNetTests.gd -- the roads between the fifty places (2026-09-09, WORLD).
#
#   godot --headless --path . --script res://tests/RoadNetTests.gd
#
# Nothing here needs terrain, a Player, World.tscn or a pixel. The carve is
# tested by INJECTING a heightfield and a water map -- a hill in a known place,
# a lake in a known place -- and asserting the road went round them and that
# going round was genuinely cheaper by the net's own cost function. A carve
# tested only against the real bake is a carve tested against whatever the bake
# happened to look like.
#
# The load-bearing section is `nearest`: the grid lookup is checked against
# brute force over four hundred query points, because a spatial index that is
# fast and subtly wrong is worse than no index at all, and nothing else in the
# file would ever catch it.
#
# SECTION CLAIMS: every section stakes what it is about to assert before it
# runs one, so a section killed by a runtime error shows up as a claim that
# never settled instead of quietly taking its assertions with it.
# =============================================================================

const MIN_ASSERTIONS := 110

var _pass := 0
var _fail := 0
var _claims: Dictionary = {}
var _counts: Dictionary = {}
var _section := ""
var _real: RoadNet = null


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


func near(a: float, b: float, tol: float, what: String) -> void:
	ok(absf(a - b) <= tol, "%s (got %.4f, want %.4f +/- %.4f)" % [what, a, b, tol])


func same(a: String, b: String, what: String) -> void:
	ok(a == b, "%s (got '%s', want '%s')" % [what, a, b])


# ------------------------------------------------------------ injected ground

func _flat(_p: Vector2) -> float:
	return 0.0


func _dry(_p: Vector2) -> bool:
	return false


func _hill(p: Vector2) -> float:
	## A 500 m dome squatting on the midpoint of the test edge.
	var d := p.distance_to(Vector2(1500.0, 0.0))
	return 500.0 * exp(-(d * d) / (2.0 * 400.0 * 400.0))


func _lake(p: Vector2) -> bool:
	return p.distance_to(Vector2(1500.0, 0.0)) < 250.0


func _lake2(p: Vector2) -> bool:
	## Deliberately NOT under a multigrid control point. The coarse level's
	## control samples sit at the middle and quarters of the road; a lake at
	## x = 750 is stepped straight over unless `_seg_cost` sub-samples the span
	## it is costing. The `no-subsampling` mutation survived the centred lake
	## for exactly this reason, which is what put this fixture here.
	return p.distance_to(Vector2(750.0, 0.0)) < 250.0


func _flood(_p: Vector2) -> bool:
	return true


# ------------------------------------------------------------------- fixtures

func _mk(rows: Array, hf: String, wf: String) -> RoadNet:
	## Deliberately NOT added to the tree: a net with no parent, no terrain and
	## no World is the contract, and building it here proves it every time.
	var n := RoadNet.new()
	n.height_fn = Callable(self, hf)
	n.water_fn = Callable(self, wf)
	n.build(rows)
	return n


func _pair_rows() -> Array:
	return [
		{"name": "AA", "pos": Vector2(0.0, 0.0), "rank": 1},
		{"name": "BB", "pos": Vector2(3000.0, 0.0), "rank": 1},
	]


func _ring_rows(r: float, rank: int) -> Array:
	var out: Array = []
	for i in 8:
		var a := TAU * float(i) / 8.0
		out.append({"name": "R%d" % i, "pos": Vector2(cos(a) * r, sin(a) * r), "rank": rank})
	return out


func _straight_poly(a: Vector2, b: Vector2, segs: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(segs + 1):
		out.append(a.lerp(b, float(i) / float(segs)))
	return out


func _max_offset(n: RoadNet, e: int) -> float:
	## How far the carved road strays from the straight line between its ends.
	var ed := n.edge(e)
	var poly: PackedVector2Array = ed["poly"]
	var a := poly[0]
	var b := poly[poly.size() - 1]
	var d := a.distance_to(b)
	if d <= 0.001:
		return 0.0
	var dir := (b - a) / d
	var nrm := Vector2(-dir.y, dir.x)
	var m := 0.0
	for p in poly:
		m = maxf(m, absf((p - a).dot(nrm)))
	return m


func _wet_count(n: RoadNet, poly: PackedVector2Array) -> int:
	var c := 0
	for p in poly:
		if n._wet(p):
			c += 1
	return c


# ---------------------------------------------------------------------- entry

func _initialize() -> void:
	print("\n=== RoadNetTests ===")


func _process(_d: float) -> bool:
	_real = RoadNet.new()
	root.add_child(_real)
	_t_roster()
	_t_connected()
	_t_determinism()
	_t_shortcuts()
	_t_carve_flat()
	_t_carve_hill()
	_t_carve_water()
	_t_nearest()
	_t_index()
	_t_point_on_edge()
	_t_route()
	_t_edges_from()
	_t_real()
	_t_nullable()
	_t_no_input()
	_t_director()
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
	var n := _mk([
		{"name": "Beta", "pos": Vector2(1000.0, 0.0), "rank": 1},
		{"name": "Alpha", "pos": Vector2(0.0, 0.0), "rank": 0},
		{"name": "Beta", "pos": Vector2(9999.0, 9999.0), "rank": 2},
		{"name": "", "pos": Vector2(5.0, 5.0), "rank": 0},
		{"name": "Gamma", "pos": [2000.0, 0.0], "rank": 9},
		{"name": "Delta", "pos": Vector3(3000.0, 77.0, 0.0), "rank": -3},
		{"name": "Bad"},
	], "_flat", "_dry")
	ok(n.nodes.size() == 4, "four usable places out of seven rows")
	same(String((n.nodes[0] as Dictionary)["name"]), "Alpha", "sorted by name, not by arrival")
	same(String((n.nodes[1] as Dictionary)["name"]), "Beta", "and the second is Beta")
	same(String((n.nodes[3] as Dictionary)["name"]), "Gamma", "and the last is Gamma")
	ok(n.place_pos("Beta") == Vector2(1000.0, 0.0), "a repeated name keeps the FIRST row")
	ok(n.place_pos("Gamma") == Vector2(2000.0, 0.0), "an Array position is read as x,z")
	ok(n.place_pos("Delta") == Vector2(3000.0, 0.0), "a Vector3 position drops its Y")
	ok(int((n.nodes[3] as Dictionary)["rank"]) == 2, "rank 9 clamps to 2")
	ok(int((n.nodes[2] as Dictionary)["rank"]) == 0, "rank -3 clamps to 0")
	n.free()


# --------------------------------------------------------------- connectedness

func _t_connected() -> void:
	claim("connected", 7)
	var n := _real
	ok(n.ready(), "the real roster builds a usable net")
	ok(n.nodes.size() >= 45, "and it has the whole map in it (%d places)" % n.nodes.size())
	ok(n.edges.size() >= n.nodes.size() - 1, "at least a spanning tree of roads")

	## Rule 2: every place walkable from every other. Breadth-first from the
	## first node; anything unreached is a village with no road to it.
	var seen := {0: true}
	var q: Array = [0]
	while not q.is_empty():
		var cur := int(q.pop_back())
		for e in n.edges_from(String((n.nodes[cur] as Dictionary)["name"])):
			var ed := n.edge(int(e))
			var other := int(ed["b"])
			if int(ed["a"]) != cur:
				other = int(ed["a"])
			if not seen.has(other):
				seen[other] = true
				q.append(other)
	ok(seen.size() == n.nodes.size(), "every place is reachable from every other (%d of %d)"
			% [seen.size(), n.nodes.size()])

	var selfish := 0
	var dup := 0
	var pairs := {}
	var lonely := 0
	for e in n.edges.size():
		var ed := n.edge(e)
		var a := int(ed["a"])
		var b := int(ed["b"])
		if a == b:
			selfish += 1
		var key := mini(a, b) * 100000 + maxi(a, b)
		if pairs.has(key):
			dup += 1
		pairs[key] = true
	for i in n.nodes.size():
		if n.edges_from(String((n.nodes[i] as Dictionary)["name"])).is_empty():
			lonely += 1
	ok(selfish == 0, "no road runs from a place to itself")
	ok(dup == 0, "no two roads join the same pair of places")
	ok(lonely == 0, "no place is left without a road")


# ---------------------------------------------------------------- determinism

func _t_determinism() -> void:
	claim("determinism", 6)
	var rows := _ring_rows(700.0, 1)
	var shuffled: Array = []
	for i in rows.size():
		shuffled.push_front(rows[i])
	var a := _mk(rows, "_flat", "_dry")
	var b := _mk(shuffled, "_flat", "_dry")
	ok(a.edges.size() == b.edges.size(), "input order cannot change how many roads there are")
	ok(a.fingerprint() == b.fingerprint(), "nor the fingerprint of the net")
	var exact := true
	for e in a.edges.size():
		var pa: PackedVector2Array = a.edge(e)["poly"]
		var pb: PackedVector2Array = b.edge(e)["poly"]
		if pa.size() != pb.size():
			exact = false
			break
		for k in pa.size():
			if pa[k] != pb[k]:
				exact = false
				break
	ok(exact, "nor one centimetre of one polyline")
	var names := true
	for i in a.nodes.size():
		if String((a.nodes[i] as Dictionary)["name"]) != String((b.nodes[i] as Dictionary)["name"]):
			names = false
	ok(names, "the roster is sorted to the same order both times")

	var c := _mk(rows, "_flat", "_dry")
	ok(c.fingerprint() == a.fingerprint(), "a third build agrees with the first two")
	var moved := rows.duplicate(true)
	(moved[3] as Dictionary)["pos"] = Vector2(4000.0, 4000.0)
	var d := _mk(moved, "_flat", "_dry")
	ok(d.fingerprint() != a.fingerprint(), "and moving one place changes the fingerprint")
	a.free()
	b.free()
	c.free()
	d.free()


# ----------------------------------------------------------------- shortcuts

func _t_shortcuts() -> void:
	claim("shortcuts", 6)
	## Eight market towns on a ring. The spanning tree is the path round it and
	## leaves ONE adjacent pair unjoined -- the walk between them is seven hops
	## for a gap you can see across, which is exactly the absurdity a shortcut
	## is for.
	var n := _mk(_ring_rows(700.0, 1), "_flat", "_dry")
	ok(n.edges.size() == 8, "seven tree roads plus the one that closes the ring (%d)"
			% n.edges.size())
	var closed := false
	for e in n.edges_from("R0"):
		var ed := n.edge(int(e))
		if String(ed["from"]) == "R7" or String(ed["to"]) == "R7":
			closed = true
	ok(closed, "and the road it added is the one the tree left out")
	var longest := 0.0
	for e in n.edges.size():
		longest = maxf(longest, float(n.edge(e)["straight"]))
	ok(longest < 700.0, "no road cuts across the ring (longest %.1f m)" % longest)
	n.free()

	## Rank is the gate. The same ring at 1500 m has 1148 m gaps: too far for a
	## pair of hamlets to have a road between them, not too far for two market
	## towns.
	var small := _mk(_ring_rows(1500.0, 0), "_flat", "_dry")
	ok(small.edges.size() == 7, "hamlets 1148 m apart get no shortcut (%d)" % small.edges.size())
	small.free()
	var big := _mk(_ring_rows(1500.0, 1), "_flat", "_dry")
	ok(big.edges.size() == 8, "market towns at the same distance do (%d)" % big.edges.size())
	big.free()
	var far := _mk(_ring_rows(4000.0, 1), "_flat", "_dry")
	ok(far.edges.size() == 7, "but nothing is joined across 3 km (%d)" % far.edges.size())
	far.free()


# --------------------------------------------------------------- carving: flat

func _t_carve_flat() -> void:
	claim("carve_flat", 7)
	var n := _mk(_pair_rows(), "_flat", "_dry")
	ok(n.edges.size() == 1, "two places, one road")
	var poly: PackedVector2Array = n.edge(0)["poly"]
	ok(poly[0] == Vector2(0.0, 0.0), "the road starts exactly at the first place")
	ok(poly[poly.size() - 1] == Vector2(3000.0, 0.0), "and ends exactly at the second")
	ok(_max_offset(n, 0) < 0.001, "on flat dry ground there is nothing to go round")
	var cum: PackedFloat32Array = n.edge(0)["cum"]
	var mono := true
	for k in range(1, cum.size()):
		if float(cum[k]) <= float(cum[k - 1]):
			mono = false
	ok(mono, "the arclength table climbs")
	near(float(n.edge(0)["len"]), 3000.0, 0.01, "and totals the straight distance")
	ok(poly.size() == 25, "3000 m at 130 m a sample is 24 spans, 25 points (%d)" % poly.size())
	n.free()


# --------------------------------------------------------------- carving: hill

func _t_carve_hill() -> void:
	claim("carve_hill", 8)
	var n := _mk(_pair_rows(), "_hill", "_dry")
	ok(n.edges.size() == 1, "still one road")
	var poly: PackedVector2Array = n.edge(0)["poly"]
	var off := _max_offset(n, 0)
	ok(off > 20.0, "the road leaves the straight line to get round the hill (%.1f m)" % off)
	ok(off <= minf(RoadNet.MAX_OFFSET_FRAC * 3000.0, RoadNet.MAX_OFFSET_M) + 0.001,
			"and cannot stray past the leash (%.1f m)" % off)
	var straight := _straight_poly(Vector2(0.0, 0.0), Vector2(3000.0, 0.0), poly.size() - 1)
	ok(n.path_cost(poly) < n.path_cost(straight),
			"going round is cheaper by the net's own reckoning")
	ok(poly[0] == Vector2(0.0, 0.0), "the ends are still nailed to the places")
	ok(poly[poly.size() - 1] == Vector2(3000.0, 0.0), "both of them")
	ok(float(n.edge(0)["len"]) > 3000.0, "a road that goes round is longer than one that does not")
	ok(float(n.edge(0)["len"]) < 6000.0, "but it is a detour, not a wander")
	n.free()


# -------------------------------------------------------------- carving: water

func _t_carve_water() -> void:
	claim("carve_water", 10)
	var n := _mk(_pair_rows(), "_flat", "_lake")
	ok(n.edges.size() == 1, "one road past the lake")
	var poly: PackedVector2Array = n.edge(0)["poly"]
	var straight := _straight_poly(Vector2(0.0, 0.0), Vector2(3000.0, 0.0), poly.size() - 1)
	ok(_wet_count(n, poly) == 0, "the carved road keeps its feet dry")
	ok(_wet_count(n, straight) > 0, "and the straight line it started as did not")
	ok(n.path_cost(poly) < n.path_cost(straight), "which is cheaper, by the same reckoning")

	## And where there is no way round -- the whole corridor under water -- it
	## still lays a road. A ford is a road. Refusing to build one would leave a
	## place unreachable, which rule 2 does not allow.
	n.free()
	var f := _mk(_pair_rows(), "_flat", "_flood")
	ok(f.edges.size() == 1 and float(f.edge(0)["len"]) > 0.0, "an unavoidable crossing is still a road")
	var fp: PackedVector2Array = f.edge(0)["poly"]
	ok(fp[0] == Vector2(0.0, 0.0) and fp[fp.size() - 1] == Vector2(3000.0, 0.0),
			"with its ends where they belong")
	ok(_max_offset(f, 0) <= minf(RoadNet.MAX_OFFSET_FRAC * 3000.0, RoadNet.MAX_OFFSET_M) + 0.001,
			"and no thrashing about looking for dry land")
	f.free()

	## And a lake the coarse level cannot see by standing on it. Its control
	## samples are the middle and the quarters of the road; this one sits at
	## x = 750, between two of them, so only a cost function that SUB-SAMPLES
	## the span it is charging for will notice the road is in the water.
	var o := _mk(_pair_rows(), "_flat", "_lake2")
	var op: PackedVector2Array = o.edge(0)["poly"]
	ok(_wet_count(o, op) == 0, "a lake between two control points is avoided too")
	ok(o.path_cost(op) < o.path_cost(_straight_poly(Vector2(0.0, 0.0), Vector2(3000.0, 0.0), op.size() - 1)),
			"and going round it is still the cheaper road")

	## What sub-sampling actually buys, stated as the property it is: the cost
	## of a span must not depend on how finely you ask about it. The multigrid
	## asks about kilometre-long spans at its coarse levels and 125 m spans at
	## its fine ones, and if those two answers disagree the levels are
	## optimising different roads. (The `no-subsampling` mutation survived two
	## lake fixtures before this assertion existed: a lake wide enough to
	## matter always has SOME control point inside it, so detection was never
	## the thing sub-sampling was load-bearing for. Costing was.)
	var whole := o._seg_cost(Vector2(0.0, 0.0), Vector2(3000.0, 0.0))
	var parts := 0.0
	for k in 24:
		parts += o._seg_cost(Vector2(125.0 * float(k), 0.0), Vector2(125.0 * float(k + 1), 0.0))
	ok(absf(whole - parts) < maxf(whole, parts) * 0.02,
			"a span costs the same asked whole or asked in pieces (%.0f vs %.0f)" % [whole, parts])
	o.free()


# ------------------------------------------------------- the lookup, vs. truth

func _t_nearest() -> void:
	claim("nearest", 11)
	var n := _real
	var bad_edge := 0
	var bad_dist := 0
	var bad_t := 0
	var bad_pt := 0
	var bad_name := 0
	var bad_round := 0
	var tested := 0
	for ix in 20:
		for iy in 20:
			var q := Vector2(-1000.0 + 7000.0 * float(ix) / 19.0,
					-8500.0 + 10500.0 * float(iy) / 19.0)
			var g := n.nearest_road(q)
			var t := n.nearest_road_brute(q)
			tested += 1
			if absf(float(g["dist"]) - float(t["dist"])) > 0.001:
				bad_dist += 1
			## A different edge id is only wrong if it is a different PLACE on
			## the ground. Query points far off the map project onto a shared
			## endpoint -- the village where three roads meet -- and the two
			## searches walk the edges in different orders, so they disagree
			## about which of three equally-correct roads to name.
			if int(g["edge"]) != int(t["edge"]):
				var gp: Vector2 = g["point"]
				var tp: Vector2 = t["point"]
				if gp.distance_to(tp) > 0.01:
					bad_edge += 1
			if float(g["t"]) < 0.0 or float(g["t"]) > 1.0:
				bad_t += 1
			var p: Vector2 = g["point"]
			if absf(p.distance_to(q) - float(g["dist"])) > 0.01:
				bad_pt += 1
			if String(g["from"]) == "" or String(g["to"]) == "":
				bad_name += 1
			if p.distance_to(n.point_on_edge(int(g["edge"]), float(g["t"]))) > 0.05:
				bad_round += 1
	ok(tested == 400, "four hundred query points swept")
	ok(bad_dist == 0, "the grid finds the same distance as brute force everywhere (%d off)" % bad_dist)
	ok(bad_edge == 0, "and the same road (%d off)" % bad_edge)
	ok(bad_t == 0, "t never leaves 0..1 (%d off)" % bad_t)
	ok(bad_pt == 0, "the point returned really is that far away (%d off)" % bad_pt)
	ok(bad_name == 0, "and it always knows which two places it runs between (%d off)" % bad_name)
	ok(bad_round == 0, "point_on_edge(edge, t) lands back on the same spot (%d off)" % bad_round)

	var at_place := n.nearest_road(n.place_pos("Bangor"))
	ok(float(at_place["dist"]) < 1.0, "standing in Bangor you are standing on a road")
	var miles_out := n.nearest_road(Vector2(100000.0, 100000.0))
	ok(bool(miles_out["ok"]) and float(miles_out["dist"]) > 1000.0,
			"a hundred kilometres off the map still answers, honestly")
	var empty := RoadNet.new()
	empty.build([])
	ok(not bool(empty.nearest_road(Vector2.ZERO)["ok"]), "a net with no roads says so")
	ok(not bool(empty.nearest_road_brute(Vector2.ZERO)["ok"]), "and says so the slow way too")
	empty.free()


# ------------------------------------------- the index, not just the answer

func _t_index() -> void:
	claim("index", 5)
	## THE SECTION THREE MUTATIONS WALKED THROUGH. `nearest_road` falls back to
	## brute force when the grid turns up nothing, so a grid that is never
	## populated at all still returns the right answer to every question the
	## suite asks -- and every assertion about the ANSWER stayed green while
	## the index did nothing whatsoever. What has to be asserted is that the
	## index EXISTS, that it NARROWS, and that it is right where it is hardest:
	## just off the side of a road, where the ring search is deciding whether
	## it has already searched far enough to stop.
	var n := _real
	ok(n._grid.size() > 0, "the lookup grid has cells in it at all (%d)" % n._grid.size())

	var probes := 0
	var wrong := 0
	var narrowed := 0
	for e in n.edges.size():
		for ti in 3:
			var t := 0.25 + 0.25 * float(ti)
			var here := n.point_on_edge(e, t)
			var ahead := n.point_on_edge(e, minf(t + 0.02, 1.0))
			var behind := n.point_on_edge(e, maxf(t - 0.02, 0.0))
			var dir := (ahead - behind)
			if dir.length() < 0.001:
				continue
			var nrm := Vector2(-dir.y, dir.x).normalized()
			for si in 2:
				var side := -1.0 if si == 0 else 1.0
				var q := here + nrm * 250.0 * side
				probes += 1
				var g := n.nearest_road(q)
				var seen_g := n.last_examined
				var b := n.nearest_road_brute(q)
				if absf(float(g["dist"]) - float(b["dist"])) > 0.001:
					wrong += 1
				elif int(g["edge"]) != int(b["edge"]):
					var gp: Vector2 = g["point"]
					var bp: Vector2 = b["point"]
					if gp.distance_to(bp) > 0.01:
						wrong += 1
				if seen_g < n.edges.size():
					narrowed += 1
	ok(probes > 100, "%d probes taken 250 m off the side of every road" % probes)
	ok(wrong == 0, "the grid agrees with brute force on every one of them (%d off)" % wrong)
	@warning_ignore("integer_division")
	ok(narrowed > probes / 2, "and it looked at fewer roads than all of them for most (%d of %d)"
			% [narrowed, probes])
	n.nearest_road_brute(Vector2.ZERO)
	ok(n.last_examined == n.edges.size(), "while brute force always looks at every road")


# ------------------------------------------------------------- along a road

func _t_point_on_edge() -> void:
	claim("point_on_edge", 8)
	var n := _mk(_pair_rows(), "_hill", "_dry")
	var poly: PackedVector2Array = n.edge(0)["poly"]
	var total := float(n.edge(0)["len"])
	ok(n.point_on_edge(0, 0.0) == poly[0], "t = 0 is the first place")
	ok(n.point_on_edge(0, 1.0) == poly[poly.size() - 1], "t = 1 is the second")
	ok(n.point_on_edge(0, -3.0) == poly[0], "t below zero clamps")
	ok(n.point_on_edge(0, 4.0) == poly[poly.size() - 1], "t above one clamps")
	ok(n.point_on_edge(99, 0.5) == Vector2.ZERO, "an edge that does not exist is the origin")

	## t is ARCLENGTH, not sample index: half of t must be half of the walk.
	var walked := 0.0
	var prev := n.point_on_edge(0, 0.0)
	for i in range(1, 201):
		var p := n.point_on_edge(0, 0.5 * float(i) / 200.0)
		walked += prev.distance_to(p)
		prev = p
	ok(absf(walked - total * 0.5) < total * 0.01, "t = 0.5 is halfway along the road, not halfway along the line")

	var mono := true
	var last := -1.0
	for i in 51:
		var d := poly[0].distance_to(n.point_on_edge(0, float(i) / 50.0))
		if d < last - 0.001:
			mono = false
		last = d
	ok(mono, "and it only ever moves forward")
	n.free()

	var s := _mk(_pair_rows(), "_flat", "_dry")
	ok(s.point_on_edge(0, 0.25).distance_to(Vector2(750.0, 0.0)) < 0.01,
			"on a straight road a quarter of the way is a quarter of the way")
	s.free()


# ------------------------------------------------------------------- routing

func _t_route() -> void:
	claim("route", 9)
	var n := _mk(_ring_rows(700.0, 1), "_flat", "_dry")
	var here := n.route("R0", "R0")
	ok(bool(here["ok"]) and (here["places"] as Array).size() == 1 and float(here["length"]) == 0.0,
			"you are already where you are")
	ok(not bool(n.route("R0", "Nowhere")["ok"]), "and there is no road to a place that is not there")
	var r := n.route("R0", "R4")
	ok(bool(r["ok"]), "halfway round the ring is walkable")
	var places: Array = r["places"]
	var eids: Array = r["edges"]
	same(String(places[0]), "R0", "the route starts where you asked")
	same(String(places[places.size() - 1]), "R4", "and ends where you asked")
	ok(eids.size() == places.size() - 1, "one road for every step of the walk")
	var back := n.route("R4", "R0")
	near(float(back["length"]), float(r["length"]), 0.01, "a road is the same length in both directions")
	var line := n.route_polyline(r)
	var gap := 0.0
	for k in range(line.size() - 1):
		gap = maxf(gap, line[k].distance_to(line[k + 1]))
	ok(line.size() > 4 and line[0] == n.place_pos("R0") and gap < RoadNet.SEG_M * 2.0,
			"and the drawn route is one unbroken line from the first place")
	ok(line[line.size() - 1] == n.place_pos("R4"), "that arrives at the last")
	n.free()


# ------------------------------------------------------------- the adjacency

func _t_edges_from() -> void:
	claim("edges_from", 5)
	var n := _real
	ok(n.edges_from("Nowhere At All").is_empty(), "a place off the map has no roads")
	var total := 0
	var wrong := 0
	for i in n.nodes.size():
		var nm := String((n.nodes[i] as Dictionary)["name"])
		var lst := n.edges_from(nm)
		total += lst.size()
		for e in lst:
			var ed := n.edge(int(e))
			if int(ed["a"]) != i and int(ed["b"]) != i:
				wrong += 1
	ok(wrong == 0, "every road on a place's list actually touches it")
	ok(total == n.edges.size() * 2, "and every road is on exactly two lists")
	var ring := _mk(_ring_rows(700.0, 1), "_flat", "_dry")
	ok(ring.edges_from("R0").size() == 2, "a place on a closed ring has two roads out")
	ok(ring.has_place("R3") and not ring.has_place("R9"), "and it knows which places it holds")
	ring.free()


# ------------------------------------------------------------- the real map

func _t_real() -> void:
	claim("real", 10)
	var n := _real
	var rep := n.report()
	ok(float(rep["build_ms"]) < 3000.0, "the whole map lays its roads in %.0f ms" % float(rep["build_ms"]))
	ok(int(rep["places"]) == n.nodes.size(), "the report counts the places it has")
	ok(int(rep["roads"]) == n.edges.size(), "and the roads")
	var total := float(rep["length_m"])
	ok(total > 10000.0 and total < 1000000.0, "%.0f km of road over the whole map" % (total / 1000.0))
	var off_road := 0
	var shrunk := 0
	var broken := 0
	for i in n.nodes.size():
		var nm := String((n.nodes[i] as Dictionary)["name"])
		if float(n.nearest_road(n.place_pos(nm))["dist"]) > 1.0:
			off_road += 1
	for e in n.edges.size():
		var ed := n.edge(e)
		var l := float(ed["len"])
		if is_nan(l) or is_inf(l) or l <= 0.0:
			broken += 1
		if l < float(ed["straight"]) - 0.01:
			shrunk += 1
	ok(off_road == 0, "every one of the %d places sits on its own road" % n.nodes.size())
	ok(broken == 0, "no road has a length that is not a number")
	ok(shrunk == 0, "and no carved road is shorter than the line it was carved from")
	ok(n.fingerprint() == n.fingerprint(), "the fingerprint is stable when nothing changed")
	ok(bool(n.nearest_road(Vector2.ZERO)["ok"]), "the spawn valley can find a road")
	ok(n.has_place("Bangor") and n.has_place("Portland") and bool(n.route("Bangor", "Portland")["ok"]),
			"and you can walk from Bangor to Portland")


# ------------------------------------------------------------------- nothing

func _t_nullable() -> void:
	claim("nullable", 7)
	var n := RoadNet.new()
	n.build([])
	ok(not n.ready(), "an empty roster is not a usable net")
	ok(not bool(n.route("a", "b")["ok"]), "and nothing can be routed on it")
	ok(n.report().has("roads"), "but it can still report")
	n.build([{"name": "Only", "pos": Vector2(1.0, 2.0), "rank": 0}])
	ok(n.edges.is_empty() and n.nodes.size() == 1, "one place is a place, not a road")
	ok(n.place_pos("Only") == Vector2(1.0, 2.0), "and it is still findable")
	n.free()

	## No terrain, no tree, no height function: a flat dry world, and a net.
	var bare := RoadNet.new()
	bare.build(_pair_rows())
	ok(bare.edges.size() == 1 and float(bare.edge(0)["len"]) > 2999.0,
			"with nothing bound at all the ground is flat and dry and the road is straight")
	var before := bare.edges.size()
	bare.boot()
	bare.boot()
	ok(bare.edges.size() == before, "boot is idempotent")
	bare.free()


# ------------------------------------------------------- the rules, in source

func _t_no_input() -> void:
	claim("no_input", 3)
	## This project's standing rule is that a shadowed dev binding is
	## round-blocking. The net claims to add no binding; that claim is asserted
	## here against the file rather than in a ledger line.
	var fa := FileAccess.open("res://scripts/RoadNet.gd", FileAccess.READ)
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
	same(hit, "", "the net contains no key handling at all")
	ok(src.length() > 8000, "and the file scanned was the real one")


# ------------------------------------------------- the Director, on the road

func _t_director() -> void:
	claim("director", 7)
	## The queue item this round exists for: `_road_point` was a straight line
	## between two villages and said so in a comment. With a net bound it is a
	## point ON a road out of the place.
	var c := Chronicle.new()
	c.boot()
	var pos: Vector2 = (c.places[0] as Dictionary)["pos"]

	var plain := IncidentDirector.new()
	plain.chronicle = c
	var p0 := plain._road_point({"pos": pos}, 4242)
	ok(p0 is Vector2, "with no net bound the old stand-in still answers")

	var d := IncidentDirector.new()
	d.chronicle = c
	d.roadnet = _real
	var p1 := d._road_point({"pos": pos}, 4242)
	ok(float(_real.nearest_road(p1)["dist"]) < 4.0, "with a net bound the incident lands ON a road")
	## NOT "p1 != p0": headless there is no terrain, so every carved road IS
	## the straight line and the two answers legitimately coincide. What must
	## be asserted is which BRANCH ran, and the per-uid snapshot each keeps is
	## the honest witness -- the net branch fills `_road_pts`, the stand-in
	## fills `_road_ends` and never touches it.
	ok(plain._road_pts.is_empty() and d._road_pts.has(4242),
			"and it came off the net, not off the stand-in")
	ok(p1 == d._road_point({"pos": pos}, 4242), "and it is snapshotted, so it never moves again")
	ok(d._road_point({"pos": pos}, 9999) != p1, "a different incident gets a different spot")
	ok(pos.distance_to(p1) > 1.0, "and none of them is in the middle of the village square")
	var off_map := d._road_point({"pos": Vector2(99999.0, 99999.0)}, 77)
	ok(off_map is Vector2, "a place the net has never heard of still gets an anchor")
	plain.free()
	d.free()
	c.free()
