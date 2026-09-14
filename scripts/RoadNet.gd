class_name RoadNet
extends Node

## ===========================================================================
## THE ROAD NET — the fifty places joined up, and the ground in between.
##
## Until now the terrain bake had `places` and nothing else. Fifty settlements
## sat on a heightfield with no thread between them: the map drew dots, the
## Chronicle simulated dots, and the Incident Director staged its caravans on
## `_road_point` — an honest stand-in that drew a STRAIGHT LINE from a place to
## its nearest neighbour and said so in a comment. A caravan ambush landed in
## a lake as readily as on a track.
##
## This is the thread. A travel graph over the places, every edge carved into a
## polyline that walks around hills and out of water, plus the three queries
## everything downstream actually wants:
##
##     nearest_road(pos)        where is the road from here, and which road
##     point_on_edge(e, t)      a point a fraction of the way along one
##     route(from, to)          how you would actually walk between two places
##
## FOUR RULES this file will not break:
##
##   1. **It is deterministic.** No RandomNumberGenerator, no `randf`, no time
##      anywhere in the build. The same roster and the same heightfield give
##      the same net to the last centimetre, which is what lets the Incident
##      Director hang a saved anchor off it. Even the INPUT ORDER cannot move
##      it: the roster is sorted by name before anything is built, because
##      `Chronicle.from_dict` and the fort builder both append places and a net
##      that reshuffled when a village was founded would relocate every
##      incident on the map.
##   2. **The graph is connected, always.** The spine is a Euclidean minimum
##      spanning tree, so every place can be walked to from every other place
##      before a single shortcut is considered. Shortcuts are then added only
##      where the tree makes a genuinely absurd detour between two towns that
##      would obviously have a road — which is how the Kennebec towns end up
##      with a trunk road instead of a chain through the hills.
##   3. **Carving is an optimisation, not a search.** Each edge is a fixed
##      straight baseline with a lateral offset per sample point; the offsets
##      are relaxed by coordinate descent against a cost that charges for
##      gradient, for water, for bending and for straying. A road is therefore
##      always a FUNCTION over its baseline: it cannot loop, cannot cross
##      itself, and its deviation is bounded by construction, so nothing
##      downstream has to defend against a pathological polyline.
##   4. **It works with nothing bound.** No terrain, no tree, no World: the
##      height and water probes fall back to a flat dry plane and the net is
##      built out of straight roads. That is what makes the whole thing
##      testable headless, and it is the same contract Chronicle and the
##      Incident Director already keep.
##
## Wired up by World.gd (tools/patch_roadnet.py):
##     _roads = RoadNet.new(); add_child(_roads)
##     _roads.bind_world(self); _roads.boot()
## Read it with:  World.roadnet().nearest_road(Vector2(p.x, p.z))
##
## The net is NOT saved. It is a pure function of the roster and the
## heightfield, both of which a save restores, so `to_dict` would only be a
## second copy of something that can be rebuilt in a few milliseconds — and a
## second copy is a second thing that can go stale. `fingerprint()` is the
## honest substitute: a consumer that cached an answer can tell in one integer
## whether the net it cached against is the net it is looking at.
##
## A node added to `root` from SceneTree._init() never gets `_ready()`, which
## is how StepAudio was caught out on 2026-09-05 — so `boot()` is an explicit,
## idempotent setup call the headless suite can make for itself.
##
## This file contains no key handling of any kind and adds no dev binding.
## That claim is asserted against this source in RoadNetTests, not in a ledger
## line, because a shadowed dev binding is round-blocking in this project.
## ===========================================================================

signal net_built(edge_count: int)

## Overworld's dry-ground sentinel, mirrored rather than imported: this file
## has to parse in a project with no Overworld.gd in it at all.
const NO_WATER := -100000.0
const PROBE_Y := 600.0

## --- carving -------------------------------------------------------------
## Sample spacing along an edge. 130 m is about a minute's walk: fine enough
## that a road bends around a knoll, coarse enough that the longest edge on
## the map is still under forty samples.
const SEG_M := 130.0
const MIN_SEGS := 3
const MAX_SEGS := 40
## Coordinate descent over the lateral offsets. Four passes is where the
## measured cost stops moving on the real bake; the fifth changed nothing.
const REFINE_PASSES := 4
## The furthest one pass will push a sample sideways, and how many candidate
## offsets it tries either way. The total deviation is therefore bounded by
## REFINE_PASSES * LATERAL_M, which is asserted rather than assumed.
const LATERAL_M := 96.0
const LATERAL_STEPS := 3
## The hard leash on a carve, and the reason `_max_offset` is a claim a suite
## can settle rather than a hope. A road may bow a third of the way out from
## the line between its ends and no further: past that it is not a detour, it
## is a different road, and the graph already had the chance to build one.
const MAX_OFFSET_FRAC := 0.35
const MAX_OFFSET_M := 900.0
## What a road is charged for. Gradient dominates: a 1-in-4 slope costs the
## same as six and a half times the distance on the flat, which is roughly the
## trade a cart makes. Water is charged an order above that — a road will ford
## a stream if the alternative is a two-kilometre detour, and will not
## otherwise.
const GRADE_W := 26.0
const WATER_W := 30.0
## Bending and straying, in metres of penalty per metre of offset. Small, but
## the reason a road is a curve rather than a staircase of local minima.
const BEND_W := 0.9
const STRAY_W := 0.12

## --- graph ---------------------------------------------------------------
## A shortcut is added when the spanning tree's walk between two places is
## this many times the straight distance. 2.4 is the elbow on the real roster:
## below it the map grows roads nobody would build, above it Bangor still
## reaches Augusta the long way round.
const SHORTCUT_RATIO := 2.4
const SHORTCUT_MAX := 2800.0
## Small places only get a shortcut to a genuine neighbour; market towns
## (rank >= 1) get them out to SHORTCUT_MAX.
const NEIGHBOUR_MAX := 1000.0

## --- lookup --------------------------------------------------------------
const GRID_M := 512.0
## How finely a polyline is stamped into the lookup grid. This is the slack
## `nearest_road` must allow for before it can stop expanding rings, so it is
## a correctness constant, not a tuning one.
const STAMP_M := 100.0
## Height and water probes are memoised on a 4 m lattice. The carve asks for
## the same neighbourhood seven times per pass per point; without this the
## real roster costs about 400 000 heightfield samples.
const CACHE_M := 4.0
const MAX_RINGS := 64


## The live instance, found the way Telegraph and Chronicle find themselves —
## never assumed to exist, because a headless test builds without one.
static var inst: RoadNet = null

## Injectable probes, and the reason the carve is testable at all: a suite can
## hand this a synthetic ridge or a synthetic lake and assert that the road
## went round it. Vector2 -> float, and Vector2 -> bool.
var height_fn: Callable = Callable()
var water_fn: Callable = Callable()

var nodes: Array = []           ## of {name: String, pos: Vector2, rank: int}
var edges: Array = []           ## of edge Dictionaries, see _edge()

var _by_name: Dictionary = {}   ## name -> node index
var _at_node: Dictionary = {}   ## node index -> PackedInt32Array of edge ids
var _grid: Dictionary = {}      ## Vector2i cell -> PackedInt32Array of edge ids
var _ground: Object = null      ## anything with ground_y / _surface_y / surface_y
var _h_cache: Dictionary = {}
var _w_cache: Dictionary = {}
var _built := false
var _build_ms := 0.0
## How many roads the last `nearest_road` actually looked at. Exported for the
## suite, which otherwise cannot tell a working spatial index from a grid that
## is never populated at all: with no cells the ring search finds nothing, the
## brute-force fallback answers correctly, and every assertion about the ANSWER
## stays green while the index does nothing. Three mutations survived on
## exactly that before this counter existed (2026-09-09).
var last_examined := 0


# ============================== lifecycle ==================================

static func get_net(from: Node) -> RoadNet:
	## Same contract as Chronicle.get_bus: never assume, never crash, null is a
	## legal answer.
	if inst != null and is_instance_valid(inst):
		return inst
	if from != null and from.is_inside_tree():
		var n := from.get_tree().get_first_node_in_group("roads")
		if n is RoadNet:
			inst = n as RoadNet
			return inst
	return null


func _ready() -> void:
	boot()


func boot() -> void:
	## Idempotent by contract: World calls it, _ready calls it, and the suite
	## calls it twice on purpose.
	if inst == null or not is_instance_valid(inst):
		inst = self
	if not is_in_group("roads"):
		add_to_group("roads")
	if _built:
		## A net built before the terrain node existed is a net laid over a
		## flat dry plane -- every road straight, every ford imaginary. That is
		## the correct answer for a headless suite and the WRONG one for the
		## game, and the difference is silent, which is the dangerous part. So
		## a boot that finds ground where there was none lays the roads again.
		if _ground == null or not is_instance_valid(_ground):
			_find_ground()
			if _ground != null and is_instance_valid(_ground):
				_built = false
		if _built:
			return
	_find_ground()
	build(_roster())


func bind_world(w: Node) -> void:
	## Duck-typed on every hook, for the same reason the Incident Director is:
	## this class has to come up inside the full game and inside a stripped
	## test project with three scripts in it.
	_find_ground()
	if _ground == null and w != null and is_instance_valid(w):
		if w.has_method("_surface_y") or w.has_method("surface_y"):
			_ground = w


func rebuild() -> void:
	## For a roster that changed under us — the fort builder appends a place at
	## runtime. Everything downstream should re-ask, which is what fingerprint()
	## is for.
	_built = false
	_h_cache.clear()
	_w_cache.clear()
	boot()


func ready() -> bool:
	return _built and not edges.is_empty()


func report() -> Dictionary:
	var total := 0.0
	for e in edges:
		total += float((e as Dictionary)["len"])
	return {
		"built": _built,
		"places": nodes.size(),
		"roads": edges.size(),
		"length_m": total,
		"build_ms": _build_ms,
		"ground": _ground != null and is_instance_valid(_ground),
		"cells": _grid.size(),
	}


func fingerprint() -> int:
	## One integer that changes whenever the net changes. Cheap enough to check
	## every frame and honest enough to cache against.
	var h := 2166136261
	for nd in nodes:
		var d := nd as Dictionary
		var p: Vector2 = d["pos"]
		h = _mix(h, String(d["name"]).hash())
		h = _mix(h, int(round(p.x * 10.0)))
		h = _mix(h, int(round(p.y * 10.0)))
	for e in edges:
		var ed := e as Dictionary
		h = _mix(h, int(ed["a"]) * 1021 + int(ed["b"]))
		h = _mix(h, int(round(float(ed["len"]) * 10.0)))
	return h


static func _mix(h: int, v: int) -> int:
	var x := (h ^ v) * 16777619
	x = x ^ (x >> 15)
	x = x * 2246822519
	x = x ^ (x >> 13)
	return x & 0x3FFFFFFFFFFFFFF


# ================================ build ====================================

func build(rows: Array) -> void:
	var t0 := Time.get_ticks_usec()
	nodes.clear()
	edges.clear()
	_by_name.clear()
	_at_node.clear()
	_grid.clear()

	## The roster is normalised and SORTED BY NAME before anything is built.
	## That is rule 1: two callers handing the same fifty places in different
	## orders must get the same fifty roads, because one of those callers is a
	## save file and the other is the bake.
	var seen := {}
	var tidy: Array = []
	for row in rows:
		if not (row is Dictionary):
			continue
		var r := row as Dictionary
		var nm := String(r.get("name", "")).strip_edges()
		if nm == "" or seen.has(nm):
			continue
		var pv: Variant = _as_flat(r.get("pos", null))
		if not (pv is Vector2):
			continue
		seen[nm] = true
		tidy.append({
			"name": nm,
			"pos": pv as Vector2,
			"rank": clampi(int(r.get("rank", 0)), 0, 2),
		})
	tidy.sort_custom(func(a, b): return String(a["name"]) < String(b["name"]))
	nodes = tidy
	for i in nodes.size():
		_by_name[String((nodes[i] as Dictionary)["name"])] = i
		_at_node[i] = PackedInt32Array()

	if nodes.size() >= 2:
		var pairs := _shortcuts(_mst())
		for pr in pairs:
			edges.append(_edge(int((pr as Array)[0]), int((pr as Array)[1])))
		_index()

	_built = true
	_build_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	net_built.emit(edges.size())


func _as_flat(v: Variant) -> Variant:
	## The roster arrives from three places with three shapes: Chronicle's
	## PLACE_ROSTER holds Vector2, a save holds an Array, and anything reading
	## world space holds a Vector3 whose Y is not the map's Y.
	if v is Vector2:
		return v as Vector2
	if v is Vector3:
		var v3 := v as Vector3
		return Vector2(v3.x, v3.z)
	if v is Array and (v as Array).size() >= 2:
		var a := v as Array
		return Vector2(float(a[0]), float(a[1]))
	return null


func _pos(i: int) -> Vector2:
	return (nodes[i] as Dictionary)["pos"]


func _rank(i: int) -> int:
	return int((nodes[i] as Dictionary)["rank"])


func _mst() -> Array:
	## Prim, O(n^2), which at fifty-one places is nothing and needs no priority
	## queue to reason about. Ties go to the lower index, so the tree is a pure
	## function of the sorted roster.
	var n := nodes.size()
	var used := PackedByteArray()
	used.resize(n)
	var best := PackedFloat32Array()
	best.resize(n)
	var via := PackedInt32Array()
	via.resize(n)
	for i in n:
		used[i] = 0
		best[i] = INF
		via[i] = -1
	best[0] = 0.0
	var out: Array = []
	for _step in n:
		var pick := -1
		for i in n:
			if used[i] == 1:
				continue
			if pick < 0 or float(best[i]) < float(best[pick]) - 0.0001:
				pick = i
		if pick < 0:
			break
		used[pick] = 1
		if via[pick] >= 0:
			out.append([mini(via[pick], pick), maxi(via[pick], pick)])
		var pp := _pos(pick)
		for j in n:
			if used[j] == 1:
				continue
			var d := pp.distance_to(_pos(j))
			if d < float(best[j]) - 0.0001:
				best[j] = d
				via[j] = pick
	out.sort_custom(func(a, b): return int(a[0]) * 100000 + int(a[1]) < int(b[0]) * 100000 + int(b[1]))
	return out


func _shortcuts(pairs: Array) -> Array:
	## The tree guarantees you can get anywhere. It does not guarantee the walk
	## is sane: a spanning tree happily sends you from one bank of a river to
	## the other by way of the next county. A shortcut is added where the tree's
	## own walk is SHORTCUT_RATIO times the straight distance — measured against
	## the graph as it stands, so each shortcut that lands makes the next one
	## less likely and the net does not fill in with parallel roads.
	var n := nodes.size()
	var adj: Dictionary = {}
	for i in n:
		adj[i] = {}
	for pr in pairs:
		var i0 := int((pr as Array)[0])
		var j0 := int((pr as Array)[1])
		var d0 := _pos(i0).distance_to(_pos(j0))
		(adj[i0] as Dictionary)[j0] = d0
		(adj[j0] as Dictionary)[i0] = d0

	var cand: Array = []
	for i in n:
		for j in range(i + 1, n):
			if (adj[i] as Dictionary).has(j):
				continue
			var d := _pos(i).distance_to(_pos(j))
			if d > SHORTCUT_MAX or d <= 0.001:
				continue
			var trunk := _rank(i) >= 1 and _rank(j) >= 1
			if not trunk and d > NEIGHBOUR_MAX:
				continue
			## Sorted on integer millimetres, then on the pair, so the order is
			## exact rather than float-comparison-dependent.
			cand.append([int(round(d * 1000.0)) * 1000000 + i * 1000 + j, i, j, d])
	cand.sort_custom(func(a, b): return int(a[0]) < int(b[0]))

	var out := pairs.duplicate()
	for c in cand:
		var ca := c as Array
		var i := int(ca[1])
		var j := int(ca[2])
		var d := float(ca[3])
		var sp := _graph_dist(adj, i, j)
		if is_inf(sp) or sp / d >= SHORTCUT_RATIO:
			(adj[i] as Dictionary)[j] = d
			(adj[j] as Dictionary)[i] = d
			out.append([i, j])
	return out


func _graph_dist(adj: Dictionary, src: int, dst: int) -> float:
	var n := nodes.size()
	var dist := PackedFloat32Array()
	dist.resize(n)
	var done := PackedByteArray()
	done.resize(n)
	for i in n:
		dist[i] = INF
		done[i] = 0
	dist[src] = 0.0
	for _s in n:
		var pick := -1
		for i in n:
			if done[i] == 1 or is_inf(float(dist[i])):
				continue
			if pick < 0 or float(dist[i]) < float(dist[pick]):
				pick = i
		if pick < 0:
			break
		done[pick] = 1
		if pick == dst:
			return float(dist[dst])
		for k in (adj[pick] as Dictionary):
			var j := int(k)
			var nd := float(dist[pick]) + float((adj[pick] as Dictionary)[k])
			if nd < float(dist[j]):
				dist[j] = nd
	return float(dist[dst])


func _edge(i: int, j: int) -> Dictionary:
	var poly := _carve(_pos(i), _pos(j))
	var cum := PackedFloat32Array()
	cum.resize(poly.size())
	cum[0] = 0.0
	for k in range(1, poly.size()):
		cum[k] = float(cum[k - 1]) + poly[k - 1].distance_to(poly[k])
	return {
		"a": i,
		"b": j,
		"from": String((nodes[i] as Dictionary)["name"]),
		"to": String((nodes[j] as Dictionary)["name"]),
		"poly": poly,
		"cum": cum,
		"len": float(cum[cum.size() - 1]),
		"straight": _pos(i).distance_to(_pos(j)),
	}


func _carve(a: Vector2, b: Vector2) -> PackedVector2Array:
	## Coordinate descent over one lateral offset per interior sample. The
	## baseline and the normal are FIXED, so whatever the offsets end up as the
	## road is still a single-valued function along the line from a to b: it
	## cannot double back, cannot self-intersect, and its deviation is bounded
	## by REFINE_PASSES * LATERAL_M. Every consumer downstream gets to assume
	## that instead of defending against the alternative.
	var poly := PackedVector2Array()
	var d := a.distance_to(b)
	if d <= 0.001:
		poly.append(a)
		poly.append(b)
		return poly
	var segs := clampi(int(ceil(d / SEG_M)), MIN_SEGS, MAX_SEGS)
	var dir := (b - a) / d
	var nrm := Vector2(-dir.y, dir.x)
	var off := PackedFloat32Array()
	off.resize(segs + 1)
	for k in off.size():
		off[k] = 0.0
	var lim := minf(MAX_OFFSET_FRAC * d, MAX_OFFSET_M)
	var step := LATERAL_M / float(LATERAL_STEPS)
	## MULTIGRID, and it is not a speed trick -- it is the difference between a
	## road that goes round the lake and one that walks straight into it.
	##
	## Relaxing every sample against its immediate neighbours is a coordinate
	## descent with a lake-shaped local minimum in it. Lifting ONE point out of
	## the water leaves both of its segments still half submerged, so it buys
	## half a saving and pays for the whole detour: measured on the test lake,
	## moving the middle sample 288 m clear cost 10 048 against 7 750 for
	## staying under. Every point independently refuses to move and the road
	## drowns, with a perfectly green cost curve on the way down.
	##
	## So the MIDDLE of the road is relaxed first -- one control point standing
	## for the entire span, which sees the real trade and bows the whole road
	## out at once -- then the offsets between control points are filled in and
	## the next finer level tidies the shape the coarse one chose.
	@warning_ignore("integer_division")
	var st := maxi(1, segs / 2)
	while true:
		## How far ONE level may push, and the second half of why a lake is
		## avoidable at all. A level that controls 1500 m of road but may only
		## nudge it 96 m sideways cannot leave a 250 m lake in one move, and
		## every offset in between is still under water -- so the greedy step
		## is never taken and the road drowns exactly as it did before the
		## multigrid was added. Measured: 96 m out cost 14 300 against 14 250
		## for staying put; 300 m out cost 3 140. The reach therefore scales
		## with the span the level controls, three quarters of it, cut off by
		## the leash.
		var reach := clampf(0.75 * float(st) * d / float(segs), minf(LATERAL_M, lim), lim)
		step = reach / float(LATERAL_STEPS)
		for _p in REFINE_PASSES:
			var i := st
			while i < segs:
				var lo := i - st
				var hi := mini(i + st, segs)
				var cur := float(off[i])
				var best_o := cur
				var best_c := _ctrl_cost(a, dir, nrm, d, segs, off, lo, i, hi, cur, st)
				for k in range(-LATERAL_STEPS, LATERAL_STEPS + 1):
					if k == 0:
						continue
					var cnd := clampf(cur + float(k) * step, -lim, lim)
					var c := _ctrl_cost(a, dir, nrm, d, segs, off, lo, i, hi, cnd, st)
					## Strictly better wins; an exact tie goes to the offset
					## nearer the baseline, so a flat dry world produces a
					## straight road rather than whichever candidate was tried
					## first.
					if c < best_c - 0.0001 or (absf(c - best_c) <= 0.0001 and absf(cnd) < absf(best_o) - 0.0001):
						best_c = c
						best_o = cnd
				off[i] = best_o
				i += st
		if st == 1:
			break
		off = _fill_between(off, st, segs)
		@warning_ignore("integer_division")
		st = maxi(1, st / 2)
	for i in range(segs + 1):
		poly.append(_pt(a, dir, nrm, d, segs, float(off[i]), i))
	## The ends are written EXACTLY rather than reconstructed. `a + dir * d` is
	## b to within a rounding error, and a rounding error is enough to make a
	## drawn route finish somewhere that is not the place you were walking to.
	poly[0] = a
	poly[segs] = b
	return poly


func _fill_between(off: PackedFloat32Array, st: int, segs: int) -> PackedFloat32Array:
	## Packed arrays are value types in GDScript, so this RETURNS the filled
	## copy rather than mutating the caller's. Getting that wrong is silent:
	## the coarse level's decision would simply never reach the fine one.
	var a := 0
	while a < segs:
		var b := mini(a + st, segs)
		if b > a + 1:
			for k in range(a + 1, b):
				off[k] = lerpf(float(off[a]), float(off[b]), float(k - a) / float(b - a))
		a = b
	return off


func _pt(a: Vector2, dir: Vector2, nrm: Vector2, d: float, segs: int, o: float, i: int) -> Vector2:
	return a + dir * (d * float(i) / float(segs)) + nrm * o


func _ctrl_cost(a: Vector2, dir: Vector2, nrm: Vector2, d: float, segs: int,
		off: PackedFloat32Array, lo: int, i: int, hi: int, o: float, st: int) -> float:
	var prev := _pt(a, dir, nrm, d, segs, float(off[lo]), lo)
	var here := _pt(a, dir, nrm, d, segs, o, i)
	var next := _pt(a, dir, nrm, d, segs, float(off[hi]), hi)
	var c := _seg_cost(prev, here) + _seg_cost(here, next)
	## The bend is measured across the whole control span, so at a coarse level
	## the same number of metres of curvature is spread over many more metres
	## of road. Charging it undivided would make the coarse levels -- the ones
	## that actually see the lake -- too timid to move.
	c += BEND_W * absf(float(off[lo]) - 2.0 * o + float(off[hi])) / float(st)
	c += STRAY_W * absf(o)
	return c


func _seg_cost(p: Vector2, q: Vector2) -> float:
	## The whole opinion of this file about what a road is: length, plus what
	## the length costs you uphill, plus what it costs you wet. Public so a
	## suite can hold the carve to account against it rather than against a
	## screenshot.
	##
	## SUB-SAMPLED at SEG_M, because the coarse multigrid levels ask about
	## spans over a kilometre long and a kilometre charged by its two endpoints
	## alone would step over a lake without noticing it. At a fine level the
	## span is already under SEG_M and this is exactly one interval, so the
	## levels agree about what a road costs instead of each having an opinion.
	var l := p.distance_to(q)
	if l <= 0.001:
		return 0.0
	var n := clampi(int(ceil(l / SEG_M)), 1, 24)
	var total := 0.0
	for k in n:
		var s0 := p.lerp(q, float(k) / float(n))
		var s1 := p.lerp(q, float(k + 1) / float(n))
		var sl := s0.distance_to(s1)
		var grade := absf(_h(s1) - _h(s0)) / maxf(sl, 0.001)
		var wet := 0.0
		if _wet(s0):
			wet += 0.5
		if _wet(s1):
			wet += 0.5
		total += sl * (1.0 + GRADE_W * grade + WATER_W * wet)
	return total


func path_cost(poly: PackedVector2Array) -> float:
	## What `_seg_cost` says a whole polyline costs. The suite uses it to prove
	## a carved road is cheaper than the straight line it started as, which is
	## the only claim the carve actually makes.
	var t := 0.0
	for k in range(poly.size() - 1):
		t += _seg_cost(poly[k], poly[k + 1])
	return t


# ============================== the ground =================================

func _find_ground() -> void:
	if _ground != null and is_instance_valid(_ground):
		return
	if not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group("terrain"):
		if n.has_method("ground_y") or n.has_method("_surface_y") or n.has_method("surface_y"):
			_ground = n
			return


func _h(p: Vector2) -> float:
	var key := Vector2i(int(floor(p.x / CACHE_M)), int(floor(p.y / CACHE_M)))
	var c: Variant = _h_cache.get(key, null)
	if c != null:
		return float(c)
	var y := 0.0
	if height_fn.is_valid():
		y = float(height_fn.call(p))
	elif _ground != null and is_instance_valid(_ground):
		var probe := Vector3(p.x, PROBE_Y, p.y)
		if _ground.has_method("_surface_y"):
			y = float(_ground.call("_surface_y", probe))
		elif _ground.has_method("surface_y"):
			y = float(_ground.call("surface_y", probe))
		elif _ground.has_method("ground_y"):
			y = float(_ground.call("ground_y", probe))
	if is_nan(y) or is_inf(y):
		y = 0.0
	_h_cache[key] = y
	return y


func _wet(p: Vector2) -> bool:
	var key := Vector2i(int(floor(p.x / CACHE_M)), int(floor(p.y / CACHE_M)))
	var c: Variant = _w_cache.get(key, null)
	if c != null:
		return bool(c)
	var wet := false
	if water_fn.is_valid():
		wet = bool(water_fn.call(p))
	elif _ground != null and is_instance_valid(_ground) and _ground.has_method("water_y"):
		var wy := float(_ground.call("water_y", Vector3(p.x, PROBE_Y, p.y)))
		wet = wy > NO_WATER + 1.0 and wy > _h(p) + 0.05
	_w_cache[key] = wet
	return wet


# =============================== the queries ===============================

func _index() -> void:
	for e in edges.size():
		var ed := edges[e] as Dictionary
		var ai := int(ed["a"])
		var bi := int(ed["b"])
		var pa: PackedInt32Array = _at_node[ai]
		pa.append(e)
		_at_node[ai] = pa
		var pb: PackedInt32Array = _at_node[bi]
		pb.append(e)
		_at_node[bi] = pb
		var poly: PackedVector2Array = ed["poly"]
		for k in range(poly.size() - 1):
			var p := poly[k]
			var q := poly[k + 1]
			var n := maxi(1, int(ceil(p.distance_to(q) / STAMP_M)))
			for s in range(n + 1):
				_stamp(p.lerp(q, float(s) / float(n)), e)


func _stamp(p: Vector2, e: int) -> void:
	var key := Vector2i(int(floor(p.x / GRID_M)), int(floor(p.y / GRID_M)))
	var arr: PackedInt32Array = _grid.get(key, PackedInt32Array())
	if arr.size() > 0 and arr[arr.size() - 1] == e:
		return
	if arr.has(e):
		return
	arr.append(e)
	_grid[key] = arr


func nearest_road(pos: Vector2) -> Dictionary:
	## The query this whole file exists for. Rings out from the query cell and
	## stops only once the best answer so far is closer than the ring it has
	## already searched — with STAMP_M of slack, because a polyline is stamped
	## at intervals and its nearest POINT can sit that far outside the nearest
	## stamped cell. Without that slack the grid would be a fast wrong answer,
	## which is worse than a slow right one; the suite checks it against brute
	## force over four hundred query points for exactly this reason.
	var miss := {"ok": false, "point": pos, "dist": INF, "edge": -1, "t": 0.0, "from": "", "to": ""}
	last_examined = 0
	if edges.is_empty():
		return miss
	var cx := int(floor(pos.x / GRID_M))
	var cy := int(floor(pos.y / GRID_M))
	var seen := {}
	var best := miss
	var ring := 0
	while ring <= MAX_RINGS:
		for gx in range(cx - ring, cx + ring + 1):
			for gy in range(cy - ring, cy + ring + 1):
				if ring > 0 and absi(gx - cx) != ring and absi(gy - cy) != ring:
					continue
				var arr: PackedInt32Array = _grid.get(Vector2i(gx, gy), PackedInt32Array())
				for e in arr:
					if seen.has(e):
						continue
					seen[e] = true
					var hit := _project(int(e), pos)
					if float(hit["dist"]) < float(best["dist"]):
						best = hit
		last_examined = seen.size()
		if seen.size() >= edges.size():
			return best
		if bool(best["ok"]) and float(best["dist"]) + STAMP_M <= float(ring) * GRID_M:
			return best
		ring += 1
	return best if bool(best["ok"]) else nearest_road_brute(pos)


func nearest_road_brute(pos: Vector2) -> Dictionary:
	## The definition the grid is checked against. Never called in the game.
	var best := {"ok": false, "point": pos, "dist": INF, "edge": -1, "t": 0.0, "from": "", "to": ""}
	last_examined = edges.size()
	for e in edges.size():
		var hit := _project(e, pos)
		if float(hit["dist"]) < float(best["dist"]):
			best = hit
	return best


func _project(e: int, pos: Vector2) -> Dictionary:
	var ed := edges[e] as Dictionary
	var poly: PackedVector2Array = ed["poly"]
	var cum: PackedFloat32Array = ed["cum"]
	var bd := INF
	var bp := poly[0]
	var bs := 0.0
	for k in range(poly.size() - 1):
		var p := poly[k]
		var seg := poly[k + 1] - p
		var ll := seg.length_squared()
		var t := 0.0
		if ll > 0.000001:
			t = clampf((pos - p).dot(seg) / ll, 0.0, 1.0)
		var pt := p + seg * t
		var dd := pt.distance_to(pos)
		if dd < bd:
			bd = dd
			bp = pt
			bs = float(cum[k]) + seg.length() * t
	var total := float(ed["len"])
	return {
		"ok": true,
		"point": bp,
		"dist": bd,
		"edge": e,
		## Clamped, and not out of superstition: `cum` is float32 and `bs` is
		## accumulated in float64, so a projection that lands exactly on the
		## far endpoint computes a fraction one ulp past 1.0. Anything that
		## feeds t straight back into point_on_edge survives that; anything
		## that range-checks it does not.
		"t": clampf(bs / total, 0.0, 1.0) if total > 0.001 else 0.0,
		"from": String(ed["from"]),
		"to": String(ed["to"]),
	}


func point_on_edge(e: int, t: float) -> Vector2:
	## Parameterised by ARCLENGTH, not by sample index. The samples are evenly
	## spaced along the baseline, not along the road, so t = 0.5 by index is not
	## the middle of anything a traveller would recognise.
	if e < 0 or e >= edges.size():
		return Vector2.ZERO
	var ed := edges[e] as Dictionary
	var poly: PackedVector2Array = ed["poly"]
	var cum: PackedFloat32Array = ed["cum"]
	var total := float(ed["len"])
	if total <= 0.001:
		return poly[0]
	var want := clampf(t, 0.0, 1.0) * total
	for k in range(poly.size() - 1):
		var c0 := float(cum[k])
		var c1 := float(cum[k + 1])
		if want <= c1 or k == poly.size() - 2:
			var span := c1 - c0
			var f := 0.0
			if span > 0.0001:
				f = clampf((want - c0) / span, 0.0, 1.0)
			return poly[k].lerp(poly[k + 1], f)
	return poly[poly.size() - 1]


func edges_from(nm: String) -> PackedInt32Array:
	if not _by_name.has(nm):
		return PackedInt32Array()
	return _at_node[int(_by_name[nm])]


func has_place(nm: String) -> bool:
	return _by_name.has(nm)


func place_pos(nm: String) -> Vector2:
	if not _by_name.has(nm):
		return Vector2.ZERO
	return _pos(int(_by_name[nm]))


func edge(e: int) -> Dictionary:
	if e < 0 or e >= edges.size():
		return {}
	return edges[e] as Dictionary


func route(from_name: String, to_name: String) -> Dictionary:
	## Dijkstra over CARVED lengths, not straight ones: a road that went round
	## a lake is longer than the line between its ends, and a traveller who
	## planned on the line would be late.
	var miss := {"ok": false, "places": [], "edges": [], "length": 0.0}
	if not _by_name.has(from_name) or not _by_name.has(to_name):
		return miss
	var s := int(_by_name[from_name])
	var g := int(_by_name[to_name])
	if s == g:
		return {"ok": true, "places": [from_name], "edges": [], "length": 0.0}
	var n := nodes.size()
	var dist := PackedFloat32Array()
	dist.resize(n)
	var prev := PackedInt32Array()
	prev.resize(n)
	var pedge := PackedInt32Array()
	pedge.resize(n)
	var done := PackedByteArray()
	done.resize(n)
	for i in n:
		dist[i] = INF
		prev[i] = -1
		pedge[i] = -1
		done[i] = 0
	dist[s] = 0.0
	while true:
		var pick := -1
		for i in n:
			if done[i] == 1 or is_inf(float(dist[i])):
				continue
			if pick < 0 or float(dist[i]) < float(dist[pick]):
				pick = i
		if pick < 0:
			break
		done[pick] = 1
		if pick == g:
			break
		for e in (_at_node[pick] as PackedInt32Array):
			var ed := edges[e] as Dictionary
			var other := int(ed["b"])
			if int(ed["a"]) != pick:
				other = int(ed["a"])
			if done[other] == 1:
				continue
			var nd := float(dist[pick]) + float(ed["len"])
			if nd < float(dist[other]):
				dist[other] = nd
				prev[other] = pick
				pedge[other] = int(e)
	if is_inf(float(dist[g])):
		return miss
	var chain: Array = []
	var echain: Array = []
	var cur := g
	while cur != -1:
		chain.push_front(String((nodes[cur] as Dictionary)["name"]))
		if pedge[cur] >= 0:
			echain.push_front(int(pedge[cur]))
		cur = int(prev[cur])
	return {"ok": true, "places": chain, "edges": echain, "length": float(dist[g])}


func route_polyline(r: Dictionary) -> PackedVector2Array:
	## The route's roads end to end, each laid down in the direction of travel,
	## with the shared endpoint written once.
	var out := PackedVector2Array()
	if not bool(r.get("ok", false)):
		return out
	var names: Array = r.get("places", [])
	var eids: Array = r.get("edges", [])
	for k in eids.size():
		var ed := edges[int(eids[k])] as Dictionary
		var poly: PackedVector2Array = ed["poly"]
		var fwd := String(ed["from"]) == String(names[k])
		var cnt := poly.size()
		for s in cnt:
			var p := poly[s] if fwd else poly[cnt - 1 - s]
			if s == 0 and out.size() > 0:
				continue
			out.append(p)
	return out


func _roster() -> Array:
	## The live bake if the Overworld is up, the shipped roster if it is not —
	## the same two-source rule Chronicle._roster keeps, and for the same
	## reason: a headless suite must lay roads over the real map rather than
	## over a stand-in.
	if is_inside_tree():
		for n in get_tree().get_nodes_in_group("terrain"):
			if n.has_method("places"):
				var live: Variant = n.call("places")
				if live is Array and not (live as Array).is_empty():
					return live as Array
	return Chronicle.PLACE_ROSTER
