extends SceneTree
## CityTests — the big six, checked.
##
##   godot --headless --path . --script res://tests/CityTests.gd
##
## Nothing here needs terrain, a Player, World.tscn or a pixel: the layout is
## a pure function, so it is driven with an INJECTED heightfield and water
## map, and every claim about a city is a claim about the Dictionary it
## returns. The staging half is driven in a bare SceneTree with a Node3D in
## the "player" group standing in for Lemon.
##
## Every section stakes a `claim()`; MIN_ASSERTIONS is the floor.

const MIN_ASSERTIONS := 150
const SRC := "res://scripts/Cities.gd"

var _pass := 0
var _fail := 0
var _section := ""


func ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL  [%s] %s" % [_section, msg])


func claim(text: String) -> void:
	_section = text
	print("-- ", text)


func note(msg: String) -> void:
	print("        ", msg)


## ------------------------------------------------------------- fixtures ---

## Ground callables. Each is `(x, z) -> y`.
func _flat(_x: float, _z: float) -> float:
	return 0.0


func _dome(x: float, z: float) -> float:
	## a 40 m hill centred on Portland's builtin position
	var c: Vector2 = Cities.BUILTIN_ROSTER["Portland"]
	var d := Vector2(x, z).distance_to(c)
	return maxf(0.0, 40.0 - d * 0.25)


func _cliff(x: float, _z: float) -> float:
	## a 30 m step 40 m east of Portland's centre
	var c: Vector2 = Cities.BUILTIN_ROSTER["Portland"]
	return 30.0 if x > c.x + 40.0 else 0.0


func _dry(_x: float, _z: float) -> bool:
	return false


func _sea_east(x: float, _z: float) -> bool:
	## everything east of Portland's centre is under water — a coast
	var c: Vector2 = Cities.BUILTIN_ROSTER["Portland"]
	return x > c.x


func _drowned(_x: float, _z: float) -> bool:
	return true


class GrassStub extends RefCounted:
	var calls: Array = []
	func cut_at(center: Vector3, radius: float) -> bool:
		calls.append([center, radius])
		return true


class SkyStub extends RefCounted:
	var hour := 12.0


class NetStub extends RefCounted:
	## edges as {a, b} dictionaries, places as {name: Vector2}
	var places: Dictionary = {}
	var edges: Array = []
	func edges_from(nm: String) -> Array:
		var out: Array = []
		for e in edges:
			if e.get("a", "") == nm or e.get("b", "") == nm:
				out.append(e)
		return out
	func place_pos(nm: String) -> Vector2:
		return places.get(nm, Vector2.ZERO)


class BadNet extends RefCounted:
	func edges_from(_nm: String) -> Array:
		return []


class WorldStub extends Node3D:
	## the shape bind_world reads: roadnet(), places, daynight(), grass()
	var world_seed := 77
	var places: Array = []
	var _net: Object = null
	var _sky: Object = null
	var _grass: Object = null
	func roadnet() -> Object:
		return _net
	func daynight() -> Object:
		return _sky
	func grass() -> Object:
		return _grass
	func ground_height(_x: float, _z: float) -> float:
		return 5.0
	func is_water(_x: float, _z: float) -> bool:
		return false


func _portland(wseed := 1, dirs: Array = [], ground := Callable(self, "_flat"), water := Callable(self, "_dry")) -> Dictionary:
	return Cities.layout("Portland", 3, Cities.BUILTIN_ROSTER["Portland"], dirs, wseed, ground, water)


func _lot_half(lot: Dictionary) -> float:
	var s: Vector3 = lot["size"]
	return 0.5 * maxf(s.x, s.z)


## --------------------------------------------------------------- driver ---

## Runs in the first frame rather than _init/_initialize: the root Window is
## only inside the tree once the loop is up, and the staging half needs
## get_tree() / groups to work. No await anywhere — a coroutine _process
## reads as "true" and quits on frame one (docs/TREES_v3_PSX.md).
var _ran := false


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run_all()
	return true


func _run_all() -> void:
	_t_roster()
	_t_determinism()
	_t_wall()
	_t_gates()
	_t_streets()
	_t_lots()
	_t_kinds()
	_t_water()
	_t_slope()
	_t_lamps_clock()
	_t_staging()
	_t_proximity()
	_t_lamps_live()
	_t_grass()
	_t_roadnet()
	_t_bind_world()
	_t_report()
	_t_no_input()
	print("")
	print("CityTests: %d passed / %d failed (floor %d)" % [_pass, _fail, MIN_ASSERTIONS])
	if _pass < MIN_ASSERTIONS:
		print("  FAIL  assertion floor not met")
		_fail += 1
	quit(1 if _fail > 0 else 0)


## ------------------------------------------------------------- sections ---

func _t_roster() -> void:
	claim("the roster: six cities, the world's rows win by name, aliases resolve")
	var c := Cities.new()
	c.set_roster([])
	ok(c.roster_source == "builtin", "empty roster falls back to the builtin estimate")
	c.build()
	ok(c.cities.size() == 6, "builtin roster builds six cities (got %d)" % c.cities.size())
	for nm in Cities.CITY_TIERS.keys():
		ok(c.cities.has(nm), "builtin has " + str(nm))
	# tiers monotone by design: the hub is the biggest
	ok(int(c.cities["Portland"]["tier"]) == 3, "Portland is tier 3")
	ok(int(c.cities["Brunswick"]["tier"]) == 1, "Brunswick is tier 1")
	ok(float(c.cities["Portland"]["core_r"]) > float(c.cities["Bangor"]["core_r"]), "hub core larger than a market city")
	ok(float(c.cities["Bangor"]["core_r"]) > float(c.cities["Brunswick"]["core_r"]), "market city larger than a town")
	# the world's rows, in the bake's record shape
	var rows := [
		{"name": "Portland", "pos": [100.0, 200.0], "y": 3.0, "rank": 2},
		{"name": "Lewiston", "pos": [300.0, 400.0], "y": 3.0, "rank": 1},
		{"name": "Fort Kent", "pos": [1.0, 1.0], "y": 0.0, "rank": 0},
		{"name": "Bangor", "pos": Vector2(500.0, 600.0)},
		{"name": "augusta", "pos": Vector3(700.0, 9.0, 800.0)},
	]
	c.set_roster(rows)
	c.build()
	ok(c.roster_source == "world", "a real roster is marked as the world's")
	ok(c.cities.size() == 4, "only the named cities are built from a roster of five rows (got %d)" % c.cities.size())
	ok(not c.cities.has("Fort Kent"), "an ordinary place is not a city")
	ok((c.cities["Portland"]["centre"] as Vector3).x == 100.0 and (c.cities["Portland"]["centre"] as Vector3).z == 200.0, "Portland sits where the roster put it, not the estimate")
	ok(c.cities.has("Lewiston-Auburn"), "'Lewiston' resolves to Lewiston-Auburn")
	ok((c.cities["Lewiston-Auburn"]["centre"] as Vector3).x == 300.0, "…at the roster's position")
	ok((c.cities["Bangor"]["centre"] as Vector3).z == 600.0, "a Vector2 pos is accepted")
	ok(c.cities.has("Augusta") and (c.cities["Augusta"]["centre"] as Vector3).z == 800.0, "a Vector3 pos is accepted, case-insensitively named")
	ok(not c.cities.has("Brunswick"), "a city absent from the world's roster is not invented")
	ok(Cities.canonical_name("Presque-Isle") == "Presque Isle", "hyphenated alias")
	ok(Cities.canonical_name("Nowhere") == "", "unknown name is empty")
	c.free()


func _t_determinism() -> void:
	claim("determinism: same inputs → identical layout; seed changes it; roster order does not")
	var a := _portland(5)
	var b := _portland(5)
	ok(var_to_str(a) == var_to_str(b), "two layouts from the same inputs are byte-identical")
	var d := _portland(6)
	ok(var_to_str(a["wall"]) != var_to_str(d["wall"]), "a different seed moves the wall")
	ok((a["lots"] as Array).size() != (d["lots"] as Array).size() or var_to_str(a["lots"]) != var_to_str(d["lots"]), "a different seed changes the lots")
	var rows := [
		{"name": "Portland", "pos": [0.0, 0.0]},
		{"name": "Bangor", "pos": [2000.0, 0.0]},
		{"name": "Augusta", "pos": [0.0, 2000.0]},
	]
	var c1 := Cities.new()
	c1.world_seed = 9
	c1.set_roster(rows)
	c1.build()
	var rev := rows.duplicate()
	rev.reverse()
	var c2 := Cities.new()
	c2.world_seed = 9
	c2.set_roster(rev)
	c2.build()
	ok(c1.fingerprint() == c2.fingerprint(), "reversed roster order gives the same fingerprint")
	ok(var_to_str(c1.cities) == var_to_str(c2.cities), "…and byte-identical cities")
	var k1: Array = c1.cities.keys()
	var k2: Array = c2.cities.keys()
	var sorted_k: Array = k1.duplicate()
	sorted_k.sort()
	ok(k1 == k2 and k1 == sorted_k, "…built in NAME order whichever way the rows came (%s)" % str(k1))
	var c3 := Cities.new()
	c3.world_seed = 10
	c3.set_roster(rows)
	c3.build()
	ok(c1.fingerprint() != c3.fingerprint(), "a different world seed changes the fingerprint")
	ok(Cities._h(1, "Portland", 3) == Cities._h(1, "Portland", 3), "hash is stable")
	ok(Cities._h(1, "Portland", 3) != Cities._h(1, "Bangor", 3), "hash differs by name")
	ok(Cities._h(1, "Portland", 3) != Cities._h(1, "Portland", 4), "hash differs by key")
	var lo := 1.0
	var hi := 0.0
	for k in range(200):
		var h := Cities._h(3, "x", k)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	ok(lo >= 0.0 and hi < 1.0, "hash stays in [0, 1)")
	ok(hi - lo > 0.8, "hash spreads across the range (%.2f…%.2f)" % [lo, hi])
	c1.free()
	c2.free()
	c3.free()


func _t_wall() -> void:
	claim("the wall: a closed irregular polygon within the jitter band, star-shaped about the square")
	for tier in [1, 2, 3]:
		var L := Cities.layout("Bangor", tier, Vector2.ZERO, [], 4, Callable(), Callable())
		var wall: PackedVector2Array = L["wall"]
		var R := float(L["core_r"])
		ok(wall.size() == Cities.WALL_VERTS_BASE + 2 * tier, "tier %d wall has %d verts" % [tier, wall.size()])
		var band_ok := true
		var prev_ang := -INF
		var monotone := true
		for i in range(wall.size()):
			var r := wall[i].length()
			if r < R * (1.0 - Cities.WALL_JITTER * 0.5) - 0.01 or r > R * (1.0 + Cities.WALL_JITTER * 0.5) + 0.01:
				band_ok = false
			var ang := fposmod(wall[i].angle(), TAU)
			if i > 0 and ang < prev_ang:
				monotone = false
			prev_ang = ang
		ok(band_ok, "tier %d every vertex within the jitter band of R" % tier)
		ok(monotone, "tier %d vertices go round in angular order (star-shaped, no self-crossing)" % tier)
		ok(Geometry2D.is_point_in_polygon(Vector2.ZERO, wall), "tier %d the square is inside the wall" % tier)
		ok(str(L["wall_kind"]) == Cities.WALL_KIND[tier], "tier %d wall kind is %s" % [tier, str(L["wall_kind"])])
	var p := _portland()
	var hit := Cities.poly_hit(p["wall"], Vector2.RIGHT)
	ok(Cities.dist_to_poly(p["wall"], hit) < 0.01, "poly_hit lands on the wall")
	ok(hit.x > 0.0 and absf(hit.y) < 0.01, "poly_hit follows the ray")


func _t_gates() -> void:
	claim("gates: one per road, on the wall, facing the road; never fewer than two; near-parallel roads merge")
	var dirs := [Vector2(1, 0), Vector2(0, -1), Vector2(-0.7, 0.7).normalized()]
	var L := _portland(2, dirs)
	var gates: Array = L["gates"]
	ok(gates.size() == 3, "three roads → three gates (got %d)" % gates.size())
	for i in range(gates.size()):
		var g: Dictionary = gates[i]
		ok(Cities.dist_to_poly(L["wall"], g["pos"]) < 0.05, "gate %d sits on the wall" % i)
		var want: Vector2 = dirs[i]
		ok(absf(rad_to_deg((g["dir"] as Vector2).angle_to(want))) < 0.5, "gate %d faces its road" % i)
		ok(absf(rad_to_deg((g["pos"] as Vector2).angle_to(want))) < 12.0, "gate %d lies along its road's bearing" % i)
	var none := _portland(2, [])
	ok((none["gates"] as Array).size() == Cities.MIN_GATES, "no roads → MIN_GATES gates at the compass")
	var g0: Vector2 = (none["gates"] as Array)[0]["dir"]
	var g1: Vector2 = (none["gates"] as Array)[1]["dir"]
	ok(absf(rad_to_deg(g0.angle_to(-g1))) < 1.0, "…opposite each other")
	var one := _portland(2, [Vector2(0, 1)])
	ok((one["gates"] as Array).size() == 2, "one road → a second gate is added")
	ok(((one["gates"] as Array)[1]["dir"] as Vector2).distance_to(Vector2(0, -1)) < 0.01, "…opposite the road")
	var merged := _portland(2, [Vector2(1, 0), Vector2(1, 0).rotated(deg_to_rad(10.0)), Vector2(0, 1)])
	ok((merged["gates"] as Array).size() == 2, "two roads 10° apart share a gate (got %d)" % (merged["gates"] as Array).size())
	var lamps: Array = L["lamps"]
	ok(lamps.size() >= gates.size() + 4, "a lamp inside every gate plus four round the square")
	for i in range(gates.size()):
		var g: Dictionary = gates[i]
		var lp: Vector2 = lamps[i]
		ok(Geometry2D.is_point_in_polygon(lp, L["wall"]), "gate %d's lamp is inside the wall" % i)
		ok(lp.distance_to(g["pos"]) < Cities.TOWER_W + Cities.GATE_W, "gate %d's lamp is at the gate" % i)


func _t_streets() -> void:
	claim("streets: one from every gate to the square, entirely inside the wall; a ring for tier ≥ 2")
	var L := _portland(3, [Vector2(1, 0), Vector2(-1, 0.3).normalized()])
	var streets: Array = L["streets"]
	var gates: Array = L["gates"]
	ok(streets.size() == gates.size(), "one street per gate")
	for i in range(streets.size()):
		var pl: PackedVector2Array = streets[i]
		ok(pl[0].distance_to(gates[i]["pos"]) < 0.01, "street %d starts at its gate" % i)
		ok(pl[pl.size() - 1].length() < 0.01, "street %d ends at the square" % i)
		var inside := true
		for k in range(1, pl.size()):
			if not Geometry2D.is_point_in_polygon(pl[k] * 0.999, L["wall"]):
				inside = false
		ok(inside, "street %d stays inside the wall" % i)
		ok(pl.size() == 3, "street %d has one bend" % i)
	var rings: Array = L["rings"]
	ok(rings.size() == 3, "tier 3 has three rings")
	var wall: PackedVector2Array = L["wall"]
	for k in range(rings.size()):
		var ring: PackedVector2Array = rings[k]
		ok(ring.size() == wall.size() + 1 and ring[0] == ring[ring.size() - 1], "ring %d is closed with the wall's vertex count" % k)
		var f := float(Cities.RINGS[3][k])
		var shaped := true
		for v in range(wall.size()):
			if ring[v].distance_to(wall[v] * f) > 0.001:
				shaped = false
		ok(shaped, "ring %d is the wall scaled by %.2f" % [k, f])
	var minor: Array = L["minor"]
	ok(minor.size() >= 3, "the hub's long outer arcs are cut by minor radials (%d)" % minor.size())
	var span_ok := true
	for pl in minor:
		var p2: PackedVector2Array = pl
		if p2.size() != 2 or p2[0].length() < p2[1].length():
			span_ok = false
		if not Geometry2D.is_point_in_polygon(p2[0], wall):
			span_ok = false
	ok(span_ok, "every minor radial runs from the outer ring inward, inside the wall")
	var roads: Array = L["roads"]
	ok(roads.size() == streets.size() + minor.size() + rings.size(), "roads = gate streets + minor radials + rings, in that order")
	ok(roads[0] == streets[0], "…gate streets first")
	var t1 := Cities.layout("Brunswick", 1, Vector2.ZERO, [], 1, Callable(), Callable())
	ok((t1["rings"] as Array).size() == 1 and (t1["minor"] as Array).size() == 0, "tier 1 has one ring and no minor radials")


func _t_lots() -> void:
	claim("lots: inside the wall, clear of the square, the streets and each other; counts follow tier")
	var counts := {}
	for nm in ["Portland", "Bangor", "Brunswick"]:
		var tier: int = Cities.CITY_TIERS[nm]
		var L := Cities.layout(nm, tier, Cities.BUILTIN_ROSTER[nm], [Vector2(1, 0), Vector2(0, 1)], 3, Callable(self, "_flat"), Callable(self, "_dry"))
		var lots: Array = L["lots"]
		var wall: PackedVector2Array = L["wall"]
		counts[nm] = lots.size()
		ok(lots.size() >= Cities.HOUSE_MIN[tier], "%s has at least HOUSE_MIN lots (%d ≥ %d)" % [nm, lots.size(), Cities.HOUSE_MIN[tier]])
		ok(lots.size() <= Cities.HOUSE_CAP[tier], "%s has at most HOUSE_CAP lots (%d ≤ %d)" % [nm, lots.size(), Cities.HOUSE_CAP[tier]])
		var inside := true
		var clear_sq := true
		var clear_st := true
		var no_overlap := true
		var polylines: Array = L["roads"]
		for i in range(lots.size()):
			var lot: Dictionary = lots[i]
			var p: Vector2 = lot["pos"]
			var half := _lot_half(lot)
			if not Geometry2D.is_point_in_polygon(p, wall) or Cities.dist_to_poly(wall, p) < half:
				inside = false
			if p.length() < float(L["square_r"]) + half:
				clear_sq = false
			for pl in polylines:
				if Cities.dist_to_polyline(pl, p) < Cities.STREET_W * 0.5 + half * 0.7:
					clear_st = false
			for j in range(i + 1, lots.size()):
				var q: Vector2 = lots[j]["pos"]
				if q.distance_to(p) < half + _lot_half(lots[j]):
					no_overlap = false
		ok(inside, "%s every lot is inside the wall with its footprint clear of it" % nm)
		ok(clear_sq, "%s no lot sits on the square" % nm)
		ok(clear_st, "%s no lot sits on a street" % nm)
		ok(no_overlap, "%s no two footprints overlap" % nm)
		var rj: Dictionary = L["rejected"]
		ok(int(rj["water"]) == 0 and int(rj["slope"]) == 0, "%s a flat dry world rejects nothing for water or slope" % nm)
		ok(int(rj["overlap"]) + int(rj["street"]) + int(rj["outside"]) + int(rj["square"]) > 0, "%s the placer actually refused something (the filters bind)" % nm)
		note("%s: %d lots, rejected %s" % [nm, lots.size(), str(rj)])
	ok(int(counts["Portland"]) > int(counts["Bangor"]), "the hub has more houses than a market city")
	ok(int(counts["Bangor"]) > int(counts["Brunswick"]), "a market city has more houses than a town")
	# yaw faces the street: the door (+z local) must point back toward the street the lot was cut from
	var L2 := _portland(3, [Vector2(1, 0)])
	var faces := 0
	var total := 0
	var polylines2: Array = L2["roads"]
	for lot in L2["lots"]:
		var p: Vector2 = lot["pos"]
		var yaw: float = lot["yaw"]
		var fwd := Vector2(sin(yaw), cos(yaw))
		var pl: PackedVector2Array = polylines2[int(lot["street"])]
		var d_here := Cities.dist_to_polyline(pl, p)
		var d_step := Cities.dist_to_polyline(pl, p + fwd * 2.0)
		total += 1
		if d_step < d_here:
			faces += 1
	ok(faces == total, "every door faces its own street (%d of %d)" % [faces, total])


func _t_kinds() -> void:
	claim("kinds: exactly one inn by the main gate; a hall for tier ≥ 2; a chapel only at the hub")
	for nm in ["Portland", "Bangor", "Brunswick"]:
		var tier: int = Cities.CITY_TIERS[nm]
		var L := Cities.layout(nm, tier, Vector2.ZERO, [Vector2(0, -1), Vector2(1, 0)], 2, Callable(), Callable())
		var kinds := {"inn": 0, "hall": 0, "chapel": 0, "house": 0}
		var inn_lot := {}
		for lot in L["lots"]:
			kinds[str(lot["kind"])] += 1
			if str(lot["kind"]) == "inn":
				inn_lot = lot
		ok(int(kinds["inn"]) == 1, "%s has exactly one inn" % nm)
		ok(int(kinds["hall"]) == (1 if tier >= 2 else 0), "%s hall count matches tier" % nm)
		ok(int(kinds["chapel"]) == (1 if tier >= 3 else 0), "%s chapel count matches tier" % nm)
		ok(int(kinds["house"]) >= Cities.HOUSE_MIN[tier] - 3, "%s the rest are houses (%d)" % [nm, int(kinds["house"])])
		ok(int(inn_lot["street"]) == 0, "%s the inn is on the main gate's street" % nm)
		# the inn is the OUTERMOST lot on that street — first thing through the gate
		var outer := 0.0
		for lot in L["lots"]:
			if int(lot["street"]) == 0:
				outer = maxf(outer, (lot["pos"] as Vector2).length())
		ok(absf((inn_lot["pos"] as Vector2).length() - outer) < 0.01, "%s the inn is the first lot inside the gate" % nm)
	var stalls: Array = _portland()["stalls"]
	ok(stalls.size() == Cities.STALLS[3], "hub square has %d stalls" % Cities.STALLS[3])
	var inside := true
	for st in stalls:
		if (st["pos"] as Vector2).length() > Cities.SQUARE_R[3]:
			inside = false
	ok(inside, "every stall is on the square")


func _t_water() -> void:
	claim("water: a coastal city keeps its wall and loses its wet lots — and COUNTS them")
	var dry := _portland(3, [Vector2(1, 0), Vector2(0, 1)])
	var wet := _portland(3, [Vector2(1, 0), Vector2(0, 1)], Callable(self, "_flat"), Callable(self, "_sea_east"))
	var c: Vector2 = Cities.BUILTIN_ROSTER["Portland"]
	var on_water := 0
	for lot in wet["lots"]:
		var p: Vector2 = lot["pos"]
		if c.x + p.x > c.x:
			on_water += 1
	ok(on_water == 0, "no lot east of the shoreline (got %d)" % on_water)
	ok(int(wet["rejected"]["water"]) > 0, "wet lots were rejected and counted (%d)" % int(wet["rejected"]["water"]))
	ok((wet["lots"] as Array).size() < (dry["lots"] as Array).size(), "the coast costs houses (%d < %d)" % [(wet["lots"] as Array).size(), (dry["lots"] as Array).size()])
	ok(var_to_str(wet["wall"]) == var_to_str(dry["wall"]), "the wall does not move for water — a coastal city is coastal")
	ok((wet["gates"] as Array).size() == (dry["gates"] as Array).size(), "…and keeps its gates")
	var drowned := _portland(3, [], Callable(self, "_flat"), Callable(self, "_drowned"))
	ok((drowned["lots"] as Array).size() == 0, "a city entirely under water has no lots at all")
	ok((drowned["wall"] as PackedVector2Array).size() > 0, "…but still returns a wall (rule 2 of the road net: a place is a place)")


func _t_slope() -> void:
	claim("slope: a footprint across a step is refused; a gentle dome is fine; lot y follows the ground")
	var flat := _portland(3, [Vector2(1, 0), Vector2(0, 1)])
	var cliff := _portland(3, [Vector2(1, 0), Vector2(0, 1)], Callable(self, "_cliff"), Callable(self, "_dry"))
	ok(int(cliff["rejected"]["slope"]) > 0, "lots across the cliff were rejected (%d)" % int(cliff["rejected"]["slope"]))
	ok((cliff["lots"] as Array).size() <= (flat["lots"] as Array).size(), "the cliff never adds houses")
	ok(var_to_str(cliff["lots"]) != var_to_str(flat["lots"]), "…and the lots differ from the flat world's")
	var c: Vector2 = Cities.BUILTIN_ROSTER["Portland"]
	var straddles := 0
	for lot in cliff["lots"]:
		var p: Vector2 = lot["pos"]
		var half := _lot_half(lot)
		var wx := c.x + p.x
		if wx - half <= c.x + 40.0 and wx + half >= c.x + 40.0:
			straddles += 1
	ok(straddles == 0, "no surviving footprint straddles the step (got %d)" % straddles)
	var dome := _portland(3, [Vector2(1, 0), Vector2(0, 1)], Callable(self, "_dome"), Callable(self, "_dry"))
	ok(int(dome["rejected"]["slope"]) == 0, "a 1-in-4 dome rejects nothing (footprints are < 12 m)")
	ok((dome["centre"] as Vector3).y == 40.0, "centre y is the ground's (40)")
	var y_ok := true
	for lot in dome["lots"]:
		var p: Vector2 = lot["pos"]
		var want := _dome(c.x + p.x, c.y + p.y)
		if absf(float(lot["y"]) - want) > 0.001:
			y_ok = false
	ok(y_ok, "every lot carries the ground height at its own position")
	ok((flat["centre"] as Vector3).y == 0.0, "a flat world puts the centre at y 0")


func _t_lamps_clock() -> void:
	claim("lamps: lit from LAMP_ON_HOUR to LAMP_OFF_HOUR, wrapping midnight")
	ok(Cities.lamps_lit(23.0), "23:00 lit")
	ok(Cities.lamps_lit(0.5), "00:30 lit")
	ok(Cities.lamps_lit(6.4), "06:24 still lit")
	ok(not Cities.lamps_lit(6.6), "06:36 out")
	ok(not Cities.lamps_lit(12.0), "noon out")
	ok(not Cities.lamps_lit(19.4), "19:24 out")
	ok(Cities.lamps_lit(19.6), "19:36 lit")
	ok(Cities.lamps_lit(24.0 + 23.0), "hour past 24 wraps")
	ok(not Cities.lamps_lit(-12.0), "negative hour wraps")


func _t_staging() -> void:
	claim("staging: a layout becomes nodes, one per lot with a collider; strike removes them; idempotent")
	var c := Cities.new()
	root.add_child(c)
	c.world_seed = 1
	c.set_roster([])
	c.set_road_dirs("Portland", [Vector2(1, 0), Vector2(0, 1)])
	c.set_ground(Callable(self, "_flat"), Callable(self, "_dry"))
	c.build()
	ok(not c.is_staged("Portland"), "nothing is staged after build")
	ok(c.get_child_count() == 0, "…and the node has no children")
	var n := c.stage("Portland")
	ok(n != null and c.is_staged("Portland"), "stage() returns the city node")
	ok(c.staged_node("Portland") == n, "staged_node finds it")
	ok(n.position == c.cities["Portland"]["centre"], "the city node sits at the centre")
	var lots: Array = c.cities["Portland"]["lots"]
	var lots_node := n.get_node("Lots")
	ok(lots_node.get_child_count() == lots.size(), "one node per lot (%d)" % lots_node.get_child_count())
	var with_body := 0
	var with_door := 0
	var facing := 0
	for i in range(lots_node.get_child_count()):
		var h: Node3D = lots_node.get_child(i)
		var body := h.get_node_or_null("Body")
		if body != null and body is StaticBody3D and body.get_child_count() > 0 and body.get_child(0) is CollisionShape3D:
			with_body += 1
		if h.get_node_or_null("Door") != null:
			with_door += 1
		if absf(h.rotation.y - float(lots[i]["yaw"])) < 0.0001:
			facing += 1
	ok(with_body == lots.size(), "every house has a StaticBody3D with a CollisionShape3D")
	ok(with_door == lots.size(), "every house has a door")
	ok(facing == lots.size(), "every house is turned to its yaw")
	var wall_node := n.get_node("Wall")
	var wall: PackedVector2Array = c.cities["Portland"]["wall"]
	var gates: Array = c.cities["Portland"]["gates"]
	var towers := 0
	var segs := 0
	var gate_marks := 0
	for ch in wall_node.get_children():
		var nm := str(ch.name)
		if nm.begins_with("Tower"):
			towers += 1
		elif nm.begins_with("Seg"):
			segs += 1
		elif nm.begins_with("Gate"):
			gate_marks += 1
	ok(towers == gates.size() * 2, "two towers per gate (%d)" % towers)
	ok(gate_marks == gates.size(), "one threshold per gate")
	ok(segs >= wall.size() - gates.size() and segs <= wall.size() + gates.size(), "wall segments: %d for %d verts and %d gates" % [segs, wall.size(), gates.size()])
	var seg_colliders := true
	for ch in wall_node.get_children():
		if str(ch.name).begins_with("Seg") and not (ch is StaticBody3D):
			seg_colliders = false
	ok(seg_colliders, "every wall segment is solid")
	var lamps_node := n.get_node("Lamps")
	ok(lamps_node.get_child_count() == (c.cities["Portland"]["lamps"] as Array).size(), "one node per lamp")
	ok(n.get_node("Square").get_node_or_null("Well") != null, "the square has a well")
	ok(n.get_node("Square").get_child_count() == 1 + Cities.STALLS[3], "well plus the stalls")
	# materials are SHARED — Enemy._box's lesson: not one per box
	var mats := {}
	var boxes := 0
	var stack: Array = [n]
	while stack.size() > 0:
		var x: Node = stack.pop_back()
		if x is MeshInstance3D:
			boxes += 1
			var m := (x as MeshInstance3D).material_override
			if m != null:
				mats[m.get_instance_id()] = true
		for ch in x.get_children():
			stack.append(ch)
	ok(boxes > 800, "a staged hub is a lot of geometry (%d meshes)" % boxes)
	ok(mats.size() <= 20, "…on at most twenty materials (%d)" % mats.size())
	# idempotent
	var again := c.stage("Portland")
	ok(again == n, "staging a staged city returns the same node")
	ok(c.get_child_count() == 1, "…and adds nothing")
	c.strike("Portland")
	ok(not c.is_staged("Portland"), "strike clears the staged flag")
	ok(n.is_queued_for_deletion(), "…and frees the node")
	c.strike("Portland")
	ok(true, "striking twice is harmless")
	c.strike("Nowhere")
	ok(c.stage("Nowhere") == null, "staging an unknown city returns null")
	# a rebuild strikes what is standing
	var m2 := c.stage("Bangor")
	c.rebuild()
	ok(not c.is_staged("Bangor") and m2.is_queued_for_deletion(), "rebuild strikes standing cities")
	root.remove_child(c)
	c.free()


func _t_proximity() -> void:
	claim("proximity: within STAGE_RADIUS of the player a city stands; past STRIKE_RADIUS it is struck")
	var c := Cities.new()
	root.add_child(c)
	c.set_roster([])
	c.set_ground(Callable(self, "_flat"), Callable(self, "_dry"))
	c.build()
	var player := Node3D.new()
	player.add_to_group("player")
	root.add_child(player)
	var pc: Vector3 = c.cities["Portland"]["centre"]
	c._tick(null)
	ok(not c.is_staged("Portland"), "nobody about → nothing staged")
	player.position = pc + Vector3(Cities.STAGE_RADIUS - 10.0, 0.0, 0.0)
	c._tick(c._player_pos())
	ok(c.is_staged("Portland"), "player just inside STAGE_RADIUS stages Portland")
	ok(not c.is_staged("Bangor"), "…and not Bangor, 3 km away")
	player.position = pc + Vector3(Cities.STAGE_RADIUS + 50.0, 0.0, 0.0)
	c._tick(c._player_pos())
	ok(c.is_staged("Portland"), "between the radii the city stays up (hysteresis)")
	player.position = pc + Vector3(Cities.STRIKE_RADIUS + 10.0, 0.0, 0.0)
	c._tick(c._player_pos())
	ok(not c.is_staged("Portland"), "past STRIKE_RADIUS it is struck")
	player.position = pc + Vector3(Cities.STAGE_RADIUS - 10.0, 900.0, 0.0)
	c._tick(c._player_pos())
	ok(c.is_staged("Portland"), "distance is measured on the ground plane — 900 m up (1.1 km away in 3D) is still here")
	player.position = pc + Vector3(Cities.STAGE_RADIUS - 1.0, 0.0, 0.0)
	var b: Vector3 = c.cities["Bangor"]["centre"]
	player.position = b
	c._tick(c._player_pos())
	ok(c.is_staged("Bangor"), "walk to Bangor and it stands")
	ok(not c.is_staged("Portland"), "…and Portland is struck behind you")
	root.remove_child(player)
	player.free()
	c._tick(c._player_pos())
	ok(c.is_staged("Bangor"), "no player node → nothing changes")
	root.remove_child(c)
	c.free()


func _t_lamps_live() -> void:
	claim("lamps, live: a staged city's lights follow the sky's hour")
	var c := Cities.new()
	root.add_child(c)
	c.set_roster([])
	c.build()
	var sky := SkyStub.new()
	sky.hour = 12.0
	c.set_sky(sky)
	var n := c.stage("Brunswick")
	var lamps := n.get_node("Lamps")
	var lit_count := func() -> int:
		var k := 0
		for lamp in lamps.get_children():
			if (lamp.get_node("Light") as OmniLight3D).visible:
				k += 1
		return k
	var on_mat := func() -> int:
		var k := 0
		for lamp in lamps.get_children():
			if (lamp.get_node("Head") as MeshInstance3D).material_override == Cities.mat("lamp_on"):
				k += 1
		return k
	ok(lit_count.call() == 0, "staged at noon: no light on")
	ok(on_mat.call() == 0, "…and every head wears the unlit material")
	sky.hour = 22.0
	c._tick(null)
	ok(lit_count.call() == lamps.get_child_count(), "at 22:00 every lamp is lit (%d)" % lamps.get_child_count())
	ok(on_mat.call() == lamps.get_child_count(), "…and every head glows")
	sky.hour = 8.0
	c._tick(null)
	ok(lit_count.call() == 0, "at 08:00 they are out again")
	# a city staged AT NIGHT comes up lit
	var n2 := c.stage("Augusta")
	sky.hour = 23.0
	c._tick(null)
	var lit2 := 0
	for lamp in n2.get_node("Lamps").get_children():
		if (lamp.get_node("Light") as OmniLight3D).visible:
			lit2 += 1
	ok(lit2 == n2.get_node("Lamps").get_child_count(), "a second city follows the same clock")
	c.strike_all()
	var n3 := c.stage("Bangor")
	var lit3 := 0
	for lamp in n3.get_node("Lamps").get_children():
		if (lamp.get_node("Light") as OmniLight3D).visible:
			lit3 += 1
	ok(lit3 == n3.get_node("Lamps").get_child_count(), "a city staged at night is lit on arrival")
	ok(c.hour_now() == 23.0, "hour_now reads the sky")
	c.set_sky(null)
	ok(c.hour_now() == 12.0, "no sky → noon, lamps out")
	c.set_hour(21.0)
	var lit4 := 0
	for lamp in n3.get_node("Lamps").get_children():
		if (lamp.get_node("Light") as OmniLight3D).visible:
			lit4 += 1
	ok(lit4 == n3.get_node("Lamps").get_child_count(), "set_hour forces the clock")
	c._tick(null)
	var lit5 := 0
	for lamp in n3.get_node("Lamps").get_children():
		if (lamp.get_node("Light") as OmniLight3D).visible:
			lit5 += 1
	ok(lit5 == lit4, "…and a tick with no sky does NOT put them out again (the first night render's bug)")
	c.clear_hour()
	c._tick(null)
	var lit6 := 0
	for lamp in n3.get_node("Lamps").get_children():
		if (lamp.get_node("Light") as OmniLight3D).visible:
			lit6 += 1
	ok(lit6 == 0, "clear_hour hands the clock back to the sky (none → noon → out)")
	var shadows := 0
	for lamp in n3.get_node("Lamps").get_children():
		if (lamp.get_node("Light") as OmniLight3D).shadow_enabled:
			shadows += 1
	ok(shadows == 0, "no lamp casts shadows (cost)")
	root.remove_child(c)
	c.free()


func _t_grass() -> void:
	claim("grass: staging mows the core once, past the wall; no grass bound is a silent no-op")
	var c := Cities.new()
	root.add_child(c)
	c.set_roster([])
	c.build()
	var g := GrassStub.new()
	c.set_grass(g)
	c.stage("Portland")
	ok(g.calls.size() == 1, "one cut per staging (got %d)" % g.calls.size())
	var call: Array = g.calls[0]
	ok(call[0] == c.cities["Portland"]["centre"], "cut at the centre")
	var R := float(c.cities["Portland"]["core_r"])
	ok(float(call[1]) > R * (1.0 + Cities.WALL_JITTER * 0.5), "cut radius reaches past the outermost wall vertex")
	c.stage("Portland")
	ok(g.calls.size() == 1, "re-staging a staged city does not mow again")
	c.strike("Portland")
	c.stage("Portland")
	ok(g.calls.size() == 2, "a fresh staging mows again (the grass de-dups its own ledger)")
	c.set_grass(RefCounted.new())
	c.strike("Portland")
	c.stage("Portland")
	ok(g.calls.size() == 2, "an object without cut_at is refused as grass")
	c.set_grass(null)
	c.strike("Portland")
	ok(c.stage("Portland") != null, "no grass → staging still works")
	root.remove_child(c)
	c.free()


func _t_roadnet() -> void:
	claim("the road net, duck-typed: directions come off edges_from + place_pos; a wrong-shaped net is dropped")
	var net := NetStub.new()
	net.places = {"Portland": Vector2(0, 0), "Brunswick": Vector2(1000, 0), "Augusta": Vector2(0, -1000), "Nowhere": Vector2(-500, -500)}
	net.edges = [{"a": "Portland", "b": "Brunswick"}, {"a": "Augusta", "b": "Portland"}, {"a": "Augusta", "b": "Nowhere"}]
	var c := Cities.new()
	c.set_roster([{"name": "Portland", "pos": [0.0, 0.0]}, {"name": "Brunswick", "pos": [1000.0, 0.0]}, {"name": "Augusta", "pos": [0.0, -1000.0]}])
	c.set_roadnet(net)
	var dirs := c.road_dirs_for("Portland")
	ok(dirs.size() == 2, "Portland has two roads (got %d)" % dirs.size())
	ok(dirs.size() == 2 and (dirs[0] as Vector2).distance_to(Vector2(1, 0)) < 0.001, "…one east to Brunswick")
	ok(dirs.size() == 2 and (dirs[1] as Vector2).distance_to(Vector2(0, -1)) < 0.001, "…one north to Augusta (b→a order handled)")
	var adirs := c.road_dirs_for("Augusta")
	ok(adirs.size() == 2, "Augusta has two roads, one to a non-city place")
	c.build()
	ok((c.cities["Portland"]["gates"] as Array).size() == 2, "the net's roads become Portland's gates")
	ok(absf(rad_to_deg(((c.cities["Portland"]["gates"] as Array)[0]["dir"] as Vector2).angle_to(Vector2(1, 0)))) < 0.5, "the first gate faces Brunswick")
	# polyline-shaped edges
	var net2 := NetStub.new()
	net2.places = net.places
	net2.edges = [{"x": 1, "pts": [Vector2(0, 0), Vector2(300, 100), Vector2(1000, 0)]}]
	c.set_roadnet(net2)
	ok(c.road_dirs_for("Portland").size() == 0, "an edge with no names and no membership is not Portland's")
	net2.edges = [{"a": "Portland", "b": "?", "pts": [Vector2(0, 0), Vector2(300, 100), Vector2(1000, 0)]}]
	var pd := c.road_dirs_for("Portland")
	ok(pd.size() == 1 and (pd[0] as Vector2).distance_to(Vector2(1, 0)) < 0.001, "an unknown far name falls back to the polyline's far end")
	# injection wins over the net
	c.set_road_dirs("Portland", [Vector2(0, 1)])
	ok(c.road_dirs_for("Portland").size() == 1 and (c.road_dirs_for("Portland")[0] as Vector2) == Vector2(0, 1), "injected dirs win")
	# a net missing place_pos is refused
	c.set_roadnet(BadNet.new())
	ok(c._net == null, "a net without place_pos is dropped")
	c.set_roadnet(null)
	ok(c._net == null, "null net is fine")
	c.set_road_dirs("Portland", [Vector2.ZERO, "junk", Vector2(3, 4)])
	var inj := c.road_dirs_for("Portland")
	ok(inj.size() == 1 and (inj[0] as Vector2).is_equal_approx(Vector2(0.6, 0.8)), "injection normalises and drops junk")
	c.free()


func _t_bind_world() -> void:
	claim("bind_world: reads the world's roster, net, sky, grass and heightfield duck-typed; boot is idempotent")
	var w := WorldStub.new()
	root.add_child(w)
	w.places = [{"name": "Portland", "pos": [10.0, 20.0], "y": 5.0, "rank": 2}, {"name": "Bangor", "pos": [900.0, 20.0]}]
	var net := NetStub.new()
	net.places = {"Portland": Vector2(10, 20), "Bangor": Vector2(900, 20)}
	net.edges = [{"a": "Portland", "b": "Bangor"}]
	w._net = net
	var sky := SkyStub.new()
	sky.hour = 22.0
	w._sky = sky
	var g := GrassStub.new()
	w._grass = g
	var c := Cities.boot(w)
	ok(c != null and c.get_parent() == w, "boot adds a Cities child to the world")
	ok(c.name == "Cities", "…named Cities")
	ok(Cities.boot(w) == c, "boot twice returns the same node")
	ok(w.get_child_count() == 1, "…and adds nothing")
	ok(c.world_seed == 77, "world_seed read off the world")
	ok(c.roster_source == "world", "roster read off the world")
	ok(c.cities.size() == 2, "two cities from the world's two named rows")
	ok((c.cities["Portland"]["centre"] as Vector3).y == 5.0, "ground_height() found and used (centre y 5)")
	ok((c.cities["Portland"]["gates"] as Array).size() == 2, "net found: one road east + one added opposite")
	ok(absf(rad_to_deg(((c.cities["Portland"]["gates"] as Array)[0]["dir"] as Vector2).angle_to(Vector2(1, 0)))) < 0.5, "…the road gate faces Bangor")
	ok(c.hour_now() == 22.0, "sky found through daynight()")
	c.stage("Bangor")
	ok(g.calls.size() == 1, "grass found through grass() and mown")
	var lamps := c.staged_node("Bangor").get_node("Lamps")
	ok((lamps.get_child(0).get_node("Light") as OmniLight3D).visible == false, "lamps follow _lit, which the first tick sets")
	c._tick(null)
	ok((lamps.get_child(0).get_node("Light") as OmniLight3D).visible == true, "…lit after the first tick at 22:00")
	# a bare world with none of it
	var bare := Node3D.new()
	root.add_child(bare)
	var c2 := Cities.boot(bare)
	ok(c2.roster_source == "builtin", "a world with no roster gets the builtin six")
	ok(c2.cities.size() == 6, "…all six")
	ok(c2._net == null and c2._sky == null and c2._grass == null, "nothing else bound")
	ok(c2.stage("Portland") != null, "…and it still stages")
	root.remove_child(w)
	w.free()
	root.remove_child(bare)
	bare.free()


func _t_report() -> void:
	claim("report and fingerprint")
	var c := Cities.new()
	c.set_roster([])
	c.build()
	var r := c.report()
	ok(r.begins_with("Cities: 6"), "report opens with the count")
	ok(r.find("Portland") >= 0 and r.find("Presque Isle") >= 0, "report names the cities")
	ok(r.split("\n").size() == 7, "one line per city plus the header")
	var f1 := c.fingerprint()
	c.set_roster([{"name": "Portland", "pos": [1.0, 2.0]}])
	c.build()
	ok(c.fingerprint() != f1, "fingerprint changes with the roster")
	var near := c.nearest_city(Vector3(100.0, 0.0, 100.0))
	ok(str(near["name"]) == "Portland" and absf(float(near["dist"]) - Vector2(99.0, 98.0).length()) < 0.01, "nearest_city measures on the ground plane")
	c.set_roster([])
	c.build()
	ok(str(c.nearest_city(Vector3(1735.0, 0.0, -3400.0))["name"]) == "Presque Isle", "nearest_city finds the Shelf town")
	ok(str(c.cities["Bangor"]["epithet"]) == "Gate of the North", "epithets ride the layout")
	c.free()


## Source-level: Cities.gd claims no key, handles no input, rolls no dice.
func _t_no_input() -> void:
	claim("no input, no RNG: the source claims no key and rolls nothing")
	var f := FileAccess.open(SRC, FileAccess.READ)
	ok(f != null, "source readable")
	if f == null:
		return
	var code := _code_only(f.get_as_text())
	for bad in ["KEY_", "InputMap", "is_action_pressed", "is_action_just_pressed", "func _input", "func _unhandled_input",
			"func _shortcut_input", "InputEventKey", "InputEventMouse", "RandomNumberGenerator", "randf", "randi",
			"randomize", "Time.get_", "get_ticks"]:
		ok(code.find(bad) < 0, "source has no '%s'" % bad)
	ok(code.find("static func layout(") >= 0, "layout is static (pure by construction)")
	ok(code.find("func _process(") >= 0, "the tick exists")
	ok(code.find("queue_free") >= 0, "strike frees")


## Strip comments and string literals so a word in a doc comment cannot
## satisfy — or fail — a scan (SeasonsTests._code_only, adopted).
static func _code_only(src: String) -> String:
	var out := PackedStringArray()
	for line in src.split("\n"):
		var s := ""
		var in_str := false
		var q := ""
		var i := 0
		while i < line.length():
			var ch := line[i]
			if in_str:
				if ch == "\\":
					i += 2
					continue
				if ch == q:
					in_str = false
				i += 1
				continue
			if ch == "\"" or ch == "'":
				in_str = true
				q = ch
				i += 1
				continue
			if ch == "#":
				break
			s += ch
			i += 1
		out.append(s)
	return "\n".join(out)
