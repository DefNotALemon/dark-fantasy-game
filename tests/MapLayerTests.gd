extends SceneTree

# =============================================================================
# tests/MapLayerTests.gd -- the map of Myrkfell, not the map of Maine.
#
#   godot --headless --path . --script res://tests/MapLayerTests.gd
#
# `MapLayers` is pure static arithmetic over the Chronicle's own region roster,
# so most of this is a loop over the real map. The sections that carry weight:
#
#   `partition` -- THE STRONGEST FORM OF AN ASSERTION IS AN INDEPENDENT REBUILD.
#   This file does not check the partition against a golden table; it checks it
#   against `Factions.region_at`, cell for cell, over all 25 350 cells. If they
#   ever disagree the map is lying about where you are standing, and the map is
#   how a player decides where to walk.
#
#   `nesting` -- the defect that killed this round's FIRST design, kept as a
#   test so no later round reinvents it. Five of seventeen adjacent region pairs
#   OVERLAP and Katahdin sits WHOLLY INSIDE Baxter State Park. Any rule that
#   puts a border "in the gap between two circles" is undefined for a third of
#   the map. Asserted in both halves: the nesting is real, and the partition
#   gives Katahdin its cells anyway.
#
#   `sea` -- a COASTLINE IS NOT A FRONTIER. The first draft drew three km of
#   frayed border between Acadia and the open sea. The guard is asserted against
#   a planted fixture built by concatenation, so a scan that came back empty
#   could not agree with it.
#
#   `firm` -- FIRM_MARGIN was measured on the wrong population first. Both
#   thresholds are asserted on both sides, and the two populations are asserted
#   to be provably different rather than merely differently named.
#
#   `chronicle` -- a stub is not the collaborator. The real Chronicle is booted
#   and stepped, and the border is asserted to move when ground changes hands
#   and to hold still when it does not.
#
#   `ground` -- the finding: the map you can WALK is a strict SUPERSET of the
#   graph the sim PUSHES on. Asserted in both directions.
#
#   `wiring` -- a method nobody calls is not a feature, and a call-site scan is
#   satisfied by a gutted call. Every site is asserted with its ARGUMENTS and
#   its BRANCH, through a comment stripper, against planted defects.
# =============================================================================

const MIN_ASSERTIONS := 250

const ORIGIN := Vector2(-1199.79, -8800.08)
const SIZE := Vector2(7200.0, 10800.0)

# --------------------------------------------------------------- measured
# Every literal below came out of tools/probe_map*.gd running against the real
# Chronicle roster BEFORE these assertions were written.

const NX := MapLayers.GRID_NX            ## 130
const NZ := MapLayers.GRID_NZ            ## 195
const CELLS := 25350
const CELL_PX := 4.0                     ## 520.0 / 130, exactly
const CELL_M := 55.3846                  ## 7200.0 / 130

const OVERLAPPING_PAIRS := 5             ## of 17 adjacent pairs
const NESTED_INNER := "KATAHDIN"
const NESTED_OUTER := "BAXTER STATE PARK"
const SEA_REGION := "GULF OF MAINE"
const LAND_COUNT := 17

## pair-min margin over 1 640 held border pairs across 200 simulated days
const PAIRMIN_P05 := 0.0647
const PAIRMIN_P50 := 0.1841
const PAIRMIN_P95 := 0.4468

var _pass := 0
var _fail := 0
var _claims: Dictionary = {}
var _counts: Dictionary = {}
var _section := ""
var _part := PackedInt32Array()
var _roster: Array = []


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


func read_src(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s


func _code_only(src: String) -> String:
	# Copied verbatim from tests/SeasonsTests.gd.
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


func fresh_chronicle() -> Chronicle:
	var c := Chronicle.new()
	get_root().add_child(c)
	c.boot(true)
	return c


# ====================== 1 · the partition IS region_at ======================

func _t_partition() -> void:
	claim("partition", 24)
	ok(NX == 130 and NZ == 195, "the grid is the measured one")
	ok(NX * NZ == CELLS, "which is %d cells" % CELLS)
	near_f(520.0 / float(NX), CELL_PX, 0.0001,
		"a cell is exactly four view pixels at zoom 1")
	near_f(SIZE.x / float(NX), CELL_M, 0.01, "and 55.4 m on the ground")
	ok(_part.size() == CELLS, "the partition covers every cell")

	## THE INDEPENDENT REBUILD. Not a golden table: the sim's own rule, asked
	## cell by cell, by the function every other system in the game uses to
	## decide which region a position is in.
	var wrong := 0
	var first_bad := ""
	var cw := SIZE.x / float(NX)
	var ch := SIZE.y / float(NZ)
	for j in range(NZ):
		var wz := ORIGIN.y + (float(j) + 0.5) * ch
		for i in range(NX):
			var wx := ORIGIN.x + (float(i) + 0.5) * cw
			var mine := String((_roster[_part[j * NX + i]] as Dictionary)["name"])
			var theirs := Factions.region_at(Vector3(wx, 0.0, wz), _roster)
			if mine != theirs:
				wrong += 1
				if first_bad.is_empty():
					first_bad = "%d,%d: %s vs %s" % [i, j, mine, theirs]
	ok(wrong == 0, "the partition agrees with Factions.region_at on every one of %d cells (%d wrong, first %s)" % [CELLS, wrong, first_bad])

	## Every region index it emits is a real one, and the map is not all one
	## colour -- a partition that answered 0 everywhere would pass the loop
	## above only if region_at did too, but it would pass a weaker test.
	var seen := {}
	for v in _part:
		seen[v] = int(seen.get(v, 0)) + 1
	var bad_idx := 0
	for v2 in seen.keys():
		if int(v2) < 0 or int(v2) >= _roster.size():
			bad_idx += 1
	ok(bad_idx == 0, "every cell names a roster entry that exists")
	ok(seen.size() == _roster.size(),
		"and every one of the %d regions owns ground (%d did)" % [_roster.size(), seen.size()])
	var biggest := 0
	for v3 in seen.values():
		biggest = maxi(biggest, int(v3))
	ok(biggest < CELLS / 2,
		"no single region owns half the map (biggest holds %d of %d)" % [biggest, CELLS])

	## Corner coordinates, not cell centres: the map's four corners.
	var tl := MapLayers.cell_to_world(0.0, 0.0, NX, NZ, ORIGIN, SIZE)
	var br := MapLayers.cell_to_world(float(NX), float(NZ), NX, NZ, ORIGIN, SIZE)
	near_f(tl.x, ORIGIN.x, 0.001, "corner (0,0) is the map origin, x")
	near_f(tl.y, ORIGIN.y, 0.001, "corner (0,0) is the map origin, z")
	near_f(br.x, ORIGIN.x + SIZE.x, 0.001, "corner (nx,nz) is the far edge, x")
	near_f(br.y, ORIGIN.y + SIZE.y, 0.001, "corner (nx,nz) is the far edge, z")
	var mid := MapLayers.cell_to_world(float(NX) * 0.5, float(NZ) * 0.5, NX, NZ, ORIGIN, SIZE)
	near_f(mid.x, ORIGIN.x + SIZE.x * 0.5, 0.001, "and the middle is the middle")

	## Degenerate inputs answer empty rather than crashing or inventing.
	ok(MapLayers.partition(_roster, 0, 10, ORIGIN, SIZE).is_empty(), "no columns, no partition")
	ok(MapLayers.partition(_roster, 10, 0, ORIGIN, SIZE).is_empty(), "no rows, no partition")
	ok(MapLayers.partition([], NX, NZ, ORIGIN, SIZE).is_empty(), "no roster, no partition")
	ok(MapLayers.walls(PackedInt32Array(), NX, NZ, PackedStringArray()).is_empty(),
		"and no partition, no walls")

	## Determinism: the same roster twice is the same answer, byte for byte.
	var again := MapLayers.partition(_roster, 32, 48, ORIGIN, SIZE)
	var again2 := MapLayers.partition(_roster, 32, 48, ORIGIN, SIZE)
	ok(again == again2, "the partition is a pure function and is safe to cache")
	ok(again.size() == 32 * 48, "at any resolution asked for")

	## THE FRAME IS AN ARGUMENT, NOT A CONSTANT. `MapPanel` falls back to a
	## hard-coded origin and size when the terrain never loaded and uses
	## `Overworld`'s real ones when it did, so the two must not be the same
	## code path. Halve the frame and the partition must follow it.
	var half := MapLayers.partition(_roster, 32, 48, ORIGIN, SIZE * 0.5)
	ok(half != again, "a different frame gives a different partition")
	ok(half.size() == again.size(), "of the same size")
	## And a cell's centre, pushed back out through the corner mapping, lands
	## in the cell it came from.
	var slips := 0
	for j2 in range(0, NZ, 17):
		for i2 in range(0, NX, 11):
			var wc := MapLayers.cell_to_world(float(i2) + 0.5, float(j2) + 0.5,
				NX, NZ, ORIGIN, SIZE)
			var back := Factions.region_at(Vector3(wc.x, 0.0, wc.y), _roster)
			if back != String((_roster[_part[j2 * NX + i2]] as Dictionary)["name"]):
				slips += 1
	ok(slips == 0, "and a cell centre put back through cell_to_world lands in its own cell")
	ok(_part[0] >= 0, "the first cell of the map is owned by somebody")


# ================ 2 · the circles overlap, and one is nested ================

func _t_nesting() -> void:
	claim("nesting", 14)
	## THE DEFECT THAT KILLED THIS ROUND'S FIRST DESIGN, kept so no later round
	## reinvents "put the line in the gap between the two circles".
	var centres := {}
	var radii := {}
	for r in _roster:
		var rd := r as Dictionary
		centres[String(rd["name"])] = rd["pos"] as Vector2
		radii[String(rd["name"])] = float(rd["r"])
	var ci: Vector2 = centres[NESTED_INNER]
	var co: Vector2 = centres[NESTED_OUTER]
	var ri := float(radii[NESTED_INNER])
	var ro := float(radii[NESTED_OUTER])
	var d := ci.distance_to(co)
	## ⚠ READ A RED ASSERTION AS A QUESTION FIRST. This claimed Katahdin lies
	## WHOLLY inside Baxter and went red: 602 + 357 = 959 against Baxter's 930,
	## so it pokes out by 29 m. The model was right and the claim was too
	## strong. What is true, and is what actually kills a gap rule: Katahdin's
	## CENTRE is 328 m inside Baxter's edge, and 92% of its radius is swallowed.
	ok(d < ro,
		"%s's CENTRE is inside %s (centres %.0f m, outer radius %.0f)" % [
			NESTED_INNER, NESTED_OUTER, d, ro])
	near_f(d + ri - ro, 29.3, 1.0,
		"and its circle escapes that one by only 29 m of a %.0f m radius" % ri)
	ok((d + ri - ro) / ri < 0.10,
		"-- under a tenth of itself (%.3f)" % ((d + ri - ro) / ri))
	near_f(d - ri - ro, -685.5, 1.5,
		"so the gap between their edges is NEGATIVE SIX HUNDRED AND EIGHTY-FIVE METRES")
	ok(d - ri - ro < 0.0, "which no 'put the line in the gap' rule can divide by")

	var c := fresh_chronicle()
	var adj: Dictionary = c._fadj
	var overlaps := 0
	var pairs := 0
	for a in adj.keys():
		for b in (adj[a] as Array):
			var an := String(a)
			var bn := String(b)
			if bn <= an:
				continue
			if not centres.has(an) or not centres.has(bn):
				continue
			pairs += 1
			if (centres[an] as Vector2).distance_to(centres[bn] as Vector2) \
					- float(radii[an]) - float(radii[bn]) < 0.0:
				overlaps += 1
	ok(pairs == 17, "there are 17 adjacent pairs (%d)" % pairs)
	ok(overlaps == OVERLAPPING_PAIRS,
		"and %d of them OVERLAP (%d) -- a gap rule is undefined for %.0f%% of the map" % [
			OVERLAPPING_PAIRS, overlaps, 100.0 * float(OVERLAPPING_PAIRS) / float(pairs)])
	ok(overlaps > 0, "which is why the border is found and not drawn")

	## And the partition handles the nesting correctly anyway, because
	## `region_at` prefers the CONTAINING circle over the nearest centre.
	var inner_cells := 0
	var outer_cells := 0
	var ii := -1
	var oi := -1
	for k in range(_roster.size()):
		var nm := String((_roster[k] as Dictionary)["name"])
		if nm == NESTED_INNER:
			ii = k
		if nm == NESTED_OUTER:
			oi = k
	for v in _part:
		if v == ii:
			inner_cells += 1
		elif v == oi:
			outer_cells += 1
	ok(ii >= 0 and oi >= 0, "both regions are on the roster")
	ok(inner_cells > 0,
		"the nested region still owns ground (%d cells) -- the containing circle wins" % inner_cells)
	ok(outer_cells > 0, "and so does the one around it (%d cells)" % outer_cells)
	ok(outer_cells > inner_cells, "the bigger circle keeps the bigger share")
	## The centre of the inner circle belongs to the INNER region, which is the
	## whole point: nearest-centre alone would also say that, but a rule that
	## took the LARGEST containing circle would say Baxter.
	var at_inner := Factions.region_at(Vector3(ci.x, 0.0, ci.y), _roster)
	ok(at_inner == NESTED_INNER, "and standing at its centre you are in it, not in the one around it")
	## A point inside the outer circle but outside the inner belongs to outer.
	var away := co + (ci - co).normalized() * -(ro * 0.5)
	ok(Factions.region_at(Vector3(away.x, 0.0, away.y), _roster) == NESTED_OUTER,
		"and a step the other way puts you back in the outer one")
	c.free()


# ==================== 3 · a coastline is not a frontier ====================

func _t_sea() -> void:
	claim("sea", 18)
	var c := fresh_chronicle()
	ok(not c.factions.has(SEA_REGION),
		"%s is open water and is not in the faction state at all" % SEA_REGION)
	ok(c.factions.size() == LAND_COUNT, "which leaves %d land regions" % LAND_COUNT)

	var sides := MapLayers.sides(_roster, c.factions)
	var sea_i := -1
	for k in range(_roster.size()):
		if String((_roster[k] as Dictionary)["name"]) == SEA_REGION:
			sea_i = k
	ok(sea_i >= 0, "the sea is on the roster")
	ok(sides[sea_i] == MapLayers.NONE, "and its side is NONE, not WILD")
	ok(Factions.holder_of(c.factions, SEA_REGION) == Factions.WILD,
		"even though Factions.holder_of would answer WILD for it")
	ok(MapLayers.NONE != Factions.WILD,
		"-- wild country you can walk into is not the same as no country at all")
	ok(MapLayers.colour_of(MapLayers.NONE).a == 0.0, "NONE is transparent")
	ok(MapLayers.colour_of("nonsense").a == 0.0,
		"and so is anything else this file does not know: NO FALLBACK COLOUR")
	for s: String in [Factions.MEN, Factions.GOBLINS, Factions.WOLVES,
			Factions.WILD, Factions.CONTESTED]:
		ok(MapLayers.colour_of(s).a > 0.0, "but %s has a colour of its own" % s)

	## THE ASSERTION THAT WOULD HAVE CAUGHT IT: no border row anywhere, over
	## many days and many holder configurations, touches an unheld side.
	var sea_rows := 0
	var rows := 0
	for step in range(24):
		c.advance(24.0, 4000)
		var b := MapLayers.border(_roster, c.factions, _part, NX, NZ, ORIGIN, SIZE)
		for e in b:
			rows += 1
			var ed := e as Dictionary
			if String(ed["held_a"]).is_empty() or String(ed["held_b"]).is_empty():
				sea_rows += 1
			if String(ed["a"]) == SEA_REGION or String(ed["b"]) == SEA_REGION:
				sea_rows += 1
	ok(rows > 100, "there are borders to check (%d rows over 24 days)" % rows)
	ok(sea_rows == 0, "and NOT ONE of them has the sea on either side (%d did)" % sea_rows)

	## And the guard bites: hand `walls` a side list where one region is NONE
	## and confirm the walls against it vanish rather than being drawn.
	var forced := PackedStringArray()
	for k2 in range(_roster.size()):
		forced.append(Factions.MEN)
	var all_men := MapLayers.walls(_part, NX, NZ, forced)
	ok(all_men.is_empty(), "one hand over the whole map is no border at all")
	forced[sea_i] = Factions.GOBLINS
	var with_sea := MapLayers.walls(_part, NX, NZ, forced)
	ok(not with_sea.is_empty(),
		"the same map with the sea in another hand DOES produce walls -- the grid is not the thing refusing")
	forced[sea_i] = MapLayers.NONE
	var none_sea := MapLayers.walls(_part, NX, NZ, forced)
	ok(none_sea.is_empty(),
		"and setting that one side to NONE removes every one of them (%d left)" % none_sea.size())
	c.free()


# ========================= 4 · walls and chains =========================

func _t_walls() -> void:
	claim("walls", 22)
	## A tiny hand-built partition, so the counting can be checked by eye.
	##   0 0 1
	##   0 1 1
	var part := PackedInt32Array([0, 0, 1, 0, 1, 1])
	var sides := PackedStringArray([Factions.MEN, Factions.GOBLINS])
	var bag := MapLayers.walls(part, 3, 2, sides)
	ok(bag.size() == 1, "one pair of regions meets (%d)" % bag.size())
	var segs: Array = bag.values()[0]
	ok(segs.size() == 3, "across three cell walls (%d)" % segs.size())
	ok(String(bag.keys()[0]) == "0|1", "keyed low|high regardless of which cell was walked first")

	## THE CORNER INDEXING, BY HAND. Grid is 3 wide, so a corner row is 4 long.
	##   cells      0 0 1        corners  0  1  2  3
	##              0 1 1                 4  5  6  7
	##                                    8  9 10 11
	## The vertical wall between cells (1,0) and (2,0) runs corner 2 -> 6; the
	## vertical wall between (0,1) and (1,1) runs corner 5 -> 9; the horizontal
	## wall between (1,0) and (1,1) runs corner 5 -> 6.
	var got := {}
	for sg in segs:
		got["%d-%d" % [(sg as Vector2i).x, (sg as Vector2i).y]] = true
	ok(got.has("2-6"), "the vertical wall east of cell (1,0) is corner 2 to 6")
	ok(got.has("5-9"), "the vertical wall east of cell (0,1) is corner 5 to 9")
	ok(got.has("5-6"), "and the horizontal wall under cell (1,0) is corner 5 to 6")
	## Every wall spans exactly one cell edge: one step in corner space.
	var wrongspan := 0
	for sg2 in segs:
		var v2 := sg2 as Vector2i
		var d2 := v2.y - v2.x
		if d2 != 1 and d2 != 4:
			wrongspan += 1
	ok(wrongspan == 0, "every wall is one cell edge long, across or down")
	## The same cells with the two regions RENUMBERED give the same walls.
	var swapped := PackedInt32Array([1, 1, 0, 1, 0, 0])
	var bag_s := MapLayers.walls(swapped, 3, 2, PackedStringArray([Factions.GOBLINS, Factions.MEN]))
	ok((bag_s.values()[0] as Array).size() == 3,
		"and which region got which index changes nothing")

	## Same geometry, same hand on both sides: no walls at all.
	var same := PackedStringArray([Factions.MEN, Factions.MEN])
	ok(MapLayers.walls(part, 3, 2, same).is_empty(),
		"two regions in the same hand share no border")

	## Independent recount over the REAL map: a wall exists for exactly those
	## neighbouring cell pairs whose holders differ and neither is NONE.
	var c := fresh_chronicle()
	for _i in range(40):
		c.advance(24.0, 4000)
	var real_sides := MapLayers.sides(_roster, c.factions)
	var bag2 := MapLayers.walls(_part, NX, NZ, real_sides)
	var mine := 0
	for k in bag2.keys():
		mine += (bag2[k] as Array).size()
	var theirs := 0
	for j in range(NZ):
		for i in range(NX):
			var sa := real_sides[_part[j * NX + i]]
			if i + 1 < NX:
				var sb := real_sides[_part[j * NX + i + 1]]
				if sa != sb and not sa.is_empty() and not sb.is_empty():
					theirs += 1
			if j + 1 < NZ:
				var sc := real_sides[_part[(j + 1) * NX + i]]
				if sa != sc and not sa.is_empty() and not sc.is_empty():
					theirs += 1
	ok(theirs > 200, "the real map has walls to count (%d)" % theirs)
	ok(mine == theirs, "and the bag holds exactly that many (%d vs %d)" % [mine, theirs])

	## Chains: every segment used exactly once, and each chain is CONTINUOUS.
	var total_segs := 0
	var total_used := 0
	var breaks := 0
	var short_chains := 0
	for k2 in bag2.keys():
		var arr: Array = bag2[k2]
		total_segs += arr.size()
		for line in MapLayers.chains(arr, NX):
			var pl: PackedVector2Array = line
			total_used += pl.size() - 1
			if pl.size() < MapLayers.MIN_CHAIN:
				short_chains += 1
			for i2 in range(pl.size() - 1):
				## In CORNER coordinates consecutive points are one cell apart.
				if not is_equal_approx(pl[i2].distance_to(pl[i2 + 1]), 1.0):
					breaks += 1
	ok(breaks == 0, "every step of every chain is one cell wall (%d breaks)" % breaks)
	ok(short_chains == 0, "and nothing shorter than MIN_CHAIN survives")
	ok(total_used <= total_segs,
		"no segment is threaded twice (%d used of %d)" % [total_used, total_segs])
	ok(total_used > total_segs / 2,
		"and most of them are threaded, not dropped (%d of %d)" % [total_used, total_segs])
	ok(MapLayers.MIN_CHAIN == 3, "a wall or two on its own is a cut corner, not a border")

	## A straight run comes back as ONE chain, walked from an END.
	var line_segs: Array = [Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3)]
	var straight := MapLayers.chains(line_segs, 100)
	ok(straight.size() == 1, "three segments in a row make one chain (%d)" % straight.size())
	ok((straight[0] as PackedVector2Array).size() == 4, "of four points")
	ok(MapLayers.chains([Vector2i(0, 1)], 100).is_empty(), "a single wall is not a chain")
	ok(MapLayers.chains([], 100).is_empty(), "and no walls is no chains")
	## Order must not matter: the same segments shuffled give the same chain.
	var shuffled: Array = [Vector2i(2, 3), Vector2i(0, 1), Vector2i(1, 2)]
	var sh := MapLayers.chains(shuffled, 100)
	ok(sh.size() == 1, "the threading does not depend on the order they arrived in")
	ok((sh[0] as PackedVector2Array).size() == 4, "and neither does the length")
	c.free()


# ============================ 5 · the smoothing ============================

func _t_smooth() -> void:
	claim("smooth", 28)
	var stair := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1),
		Vector2(2, 1), Vector2(2, 2)])
	var sm := MapLayers.chaikin(stair, MapLayers.SMOOTH_PASSES)
	ok(sm[0].is_equal_approx(stair[0]), "the first point is PINNED")
	ok(sm[sm.size() - 1].is_equal_approx(stair[stair.size() - 1]), "and so is the last")
	ok(sm.size() > stair.size(), "the line gains points (%d from %d)" % [sm.size(), stair.size()])
	ok(MapLayers.SMOOTH_PASSES == 4, "four passes, measured -- see the table in MapLayers")
	## THE NUMBER YOU CAN SEE: the SAGITTA, in view pixels at the deepest zoom
	## the panel allows. A true 90-degree staircase, which is what marching a
	## grid produces -- not a diagonal ramp, which flatters every row.
	var real_stair := PackedVector2Array()
	for i7 in range(12):
		real_stair.append(Vector2(float(i7), float(i7)))
		real_stair.append(Vector2(float(i7) + 1.0, float(i7)))
	var sag := _sagitta_px(real_stair, MapLayers.SMOOTH_PASSES)
	ok(sag < 0.15,
		"the drawn border sits %.3f view pixels from the curve at 10x zoom -- sub-pixel" % sag)
	near_f(sag, 0.078, 0.01, "which is the measured figure for four passes")
	ok(_sagitta_px(real_stair, 2) > 1.0,
		"two passes leave %.3f px, which is the staircase that was photographed" % _sagitta_px(real_stair, 2))
	ok(_sagitta_px(real_stair, 3) > sag,
		"and three is still coarser than four (%.3f px)" % _sagitta_px(real_stair, 3))
	## ⚠ THE CONVERGENCE ITSELF, asserted, because the first draft chose two
	## passes on a comment that claimed the opposite and shipped a visible pixel
	## staircase. Chaikin does NOT wander further with more passes.
	var far_off: Array[float] = []
	for pp: int in [2, 3, 4, 5, 6]:
		var c2 := MapLayers.chaikin(stair, pp)
		var w2 := 0.0
		for q5: Vector2 in c2:
			var b5 := INF
			for i5 in range(stair.size() - 1):
				var a5 := stair[i5]
				var e5 := stair[i5 + 1]
				var t5 := clampf((q5 - a5).dot(e5 - a5) / maxf((e5 - a5).length_squared(), 0.0001), 0.0, 1.0)
				b5 = minf(b5, q5.distance_to(a5.lerp(e5, t5)))
			w2 = maxf(w2, b5)
		far_off.append(w2)
	ok(far_off[far_off.size() - 1] < 0.14,
		"even six passes stay inside an eighth of a cell (%.4f)" % far_off[far_off.size() - 1])
	ok(far_off[4] - far_off[3] < far_off[1] - far_off[0],
		"and the curve CONVERGES: each pass moves it less than the last")
	## And the thing you can actually see: the sharpest facet left in the line.
	var sharp := 0.0
	for i6 in range(1, sm.size() - 1):
		var u := (sm[i6] - sm[i6 - 1]).normalized()
		var v := (sm[i6 + 1] - sm[i6]).normalized()
		sharp = maxf(sharp, rad_to_deg(acos(clampf(u.dot(v), -1.0, 1.0))))
	ok(sharp < 10.0, "no facet of a smoothed border turns more than %.1f degrees" % sharp)

	## THE SMOOTHED LINE MUST NOT WANDER OFF THE CELLS IT CAME FROM, or the map
	## would disagree with `region_at` about which side of the border you are on.
	var worst := 0.0
	for q: Vector2 in sm:
		var best := INF
		for i in range(stair.size() - 1):
			var a := stair[i]
			var b := stair[i + 1]
			var t := clampf((q - a).dot(b - a) / maxf((b - a).length_squared(), 0.0001), 0.0, 1.0)
			best = minf(best, q.distance_to(a.lerp(b, t)))
		worst = maxf(worst, best)
	## ⚠ A LITERAL MARGIN CAN STILL BE TOO SLACK TO BITE, and this one was mine:
	## it read `< 0.5` and the true worst is 0.0625, so cutting the corner to the
	## MIDPOINT instead of the quarter (worst 0.25) sailed straight through a
	## mutation sweep. Set against the measured number now.
	ok(worst < 0.13, "and stays within an eighth of a cell of the walls (worst %.4f)" % worst)
	near_f(worst, 0.1094, 0.003, "which is the quarter-cut's measured reach at four passes")
	## A midpoint cut also DUPLICATES every point, and a border made of doubled
	## points is not a smoothed line, it is a collapsed one.
	var dupes := 0
	var slen := 0.0
	for i3 in range(sm.size() - 1):
		if sm[i3].is_equal_approx(sm[i3 + 1]):
			dupes += 1
		slen += sm[i3].distance_to(sm[i3 + 1])
	ok(dupes == 0, "no two consecutive points of a smoothed border are the same (%d were)" % dupes)
	var raw := 0.0
	for i4 in range(stair.size() - 1):
		raw += stair[i4].distance_to(stair[i4 + 1])
	ok(slen / raw > 0.80 and slen / raw < 0.90,
		"and the corner is CUT, not collapsed: %.4f of the staircase's length" % (slen / raw))
	ok(dupes == 0 and sm.size() > stair.size() * 4,
		"four passes multiply the points (%d from %d)" % [sm.size(), stair.size()])

	## A closed loop wraps rather than growing a spike at the seam.
	var loop := PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(2, 2),
		Vector2(0, 2), Vector2(0, 0)])
	var ls := MapLayers.chaikin(loop, 2)
	ok(ls[0].is_equal_approx(ls[ls.size() - 1]), "a closed loop stays closed")
	## ⚠ AND THAT ALONE CANNOT SEE THE BUG. With the loop unrecognised the ends
	## are PINNED instead of wrapped -- and a loop's two ends are the same point,
	## so it stays "closed" either way and the assertion above passes. What
	## actually differs is the SEAM: wrapped, the corner at the join is cut like
	## every other; pinned, it survives untouched.
	ok(not ls[0].is_equal_approx(loop[0]),
		"and its SEAM corner is cut like the rest, not left sitting at the join")
	var far := 0.0
	for q2: Vector2 in ls:
		far = maxf(far, q2.distance_to(Vector2(1, 1)))
	ok(far <= 1.45, "and no point of it flies off the square (%.3f)" % far)
	ok(ls.size() > loop.size(), "the loop gains points too")
	## A loop's corners are actually cut -- it is not returned untouched.
	var has_corner := false
	for q3: Vector2 in ls:
		if q3.is_equal_approx(Vector2(2, 0)):
			has_corner = true
	ok(not has_corner, "and its corners are CUT, not left where they were")

	ok(MapLayers.chaikin(stair, 0) == stair, "zero passes changes nothing")
	ok(MapLayers.chaikin(stair, -3) == stair, "and neither does a negative count")
	var two := PackedVector2Array([Vector2(0, 0), Vector2(1, 0)])
	ok(MapLayers.chaikin(two, 2) == two, "a two-point line has no corner to cut")
	ok(MapLayers.chaikin(PackedVector2Array(), 2).is_empty(), "and an empty one stays empty")
	var once := MapLayers.chaikin(stair, 1)
	var twice := MapLayers.chaikin(stair, 2)
	ok(twice.size() > once.size(), "each pass adds more (%d then %d)" % [once.size(), twice.size()])
	var w1 := 0.0
	for q4: Vector2 in once:
		var b1 := INF
		for i2 in range(stair.size() - 1):
			var a2 := stair[i2]
			var b2 := stair[i2 + 1]
			var t2 := clampf((q4 - a2).dot(b2 - a2) / maxf((b2 - a2).length_squared(), 0.0001), 0.0, 1.0)
			b1 = minf(b1, q4.distance_to(a2.lerp(b2, t2)))
		w1 = maxf(w1, b1)
	ok(worst >= w1 - 0.0001, "and each pass pulls no further from the walls than the last")
	ok(once.size() < twice.size() and once[0].is_equal_approx(stair[0]),
		"one pass already pins the ends")


# ============================== 6 · firmness ==============================

func _t_firm() -> void:
	claim("firm", 29)
	## THE TWO THRESHOLDS ARE DIFFERENT CLAIMS OVER DIFFERENT POPULATIONS.
	ok(MapLayers.FIRM_MARGIN > Factions.HOLD_MARGIN,
		"FIRM_MARGIN (%.4f) is above HOLD_MARGIN (%.4f)" % [
			MapLayers.FIRM_MARGIN, Factions.HOLD_MARGIN])
	near_f(MapLayers.FIRM_MARGIN, PAIRMIN_P50, 0.0001,
		"and it IS the measured pair-min median, not a number anybody picked")
	ok(PAIRMIN_P05 > Factions.HOLD_MARGIN,
		"the held population BEGINS above HOLD_MARGIN (%.4f) by construction" % PAIRMIN_P05)
	ok(PAIRMIN_P50 < PAIRMIN_P95, "and the measured quantiles are ordered")
	ok(MapLayers.FIRM_NAMES.size() == 3 and MapLayers.FIRM_WIDTH.size() == 3
		and MapLayers.FIRM_DASH.size() == 3 and MapLayers.FIRM_GAP.size() == 3,
		"three rungs, and every style table has three rows")
	ok(MapLayers.FIRM_DASH[0] <= 0.0, "a settled border is UNBROKEN")
	ok(MapLayers.FIRM_DASH[1] > 0.0 and MapLayers.FIRM_DASH[2] > 0.0,
		"and the other two are not")
	ok(MapLayers.FIRM_WIDTH[0] > MapLayers.FIRM_WIDTH[1],
		"a settled border is drawn heavier than an uneasy one")
	ok(MapLayers.FIRM_WIDTH[1] > MapLayers.FIRM_WIDTH[2],
		"and an uneasy one heavier than a frayed one")
	ok(MapLayers.FIRM_DASH[2] < MapLayers.FIRM_DASH[1],
		"and the frayed one's dash is the shorter -- more gap, less line")
	## ⚠ FRAYED MEANS BROKEN, NOT FAINT. The first draft faded the alpha with the
	## firmness and made the contested borders -- the only part of the map where
	## anything is happening -- the hardest lines on it to see.
	ok(MapLayers.C_BORDER.a > 0.9, "every border is drawn at full strength")
	ok(MapLayers.FIRM_WIDTH[2] > 1.5,
		"including the frayed one, which is still a line (%.1f px)" % MapLayers.FIRM_WIDTH[2])
	ok(MapLayers.FIRM_WIDTH[0] - MapLayers.FIRM_WIDTH[2] < 1.0,
		"-- the three rungs differ by dash, not by disappearing")
	## ⚠ AND A NEAR-BLACK LINE DISAPPEARS INTO A DARK FOREST.
	ok(MapLayers.C_BORDER.get_luminance() > 0.8, "the border's line is bone, not black")
	ok(MapLayers.C_BORDER_BED.get_luminance() < 0.15, "and its bed is dark")
	ok(MapLayers.BED_EXTRA > 1.0, "with the bed wider than the line it carries")

	## BOTH SIDES OF BOTH BOUNDARIES, asked on a state built by hand so the
	## margins are exactly what they say.
	var eps := 0.0005
	var wide := MapLayers.FIRM_MARGIN + 0.2
	var st := {
		"SETTLED_A": _hold(wide),
		"SETTLED_B": _hold(wide),
		"EDGE_OVER": _hold(MapLayers.FIRM_MARGIN + eps),
		"EDGE_UNDER": _hold(MapLayers.FIRM_MARGIN - eps),
		"TIED": _hold(0.005),
	}
	near_f(Factions.margin_of(st, "EDGE_OVER"), MapLayers.FIRM_MARGIN + eps, 0.0002,
		"on both sides of the boundary")
	near_f(Factions.margin_of(st, "TIED"), 0.005, 0.0002, "and at the tie")
	near_f(Factions.margin_of(st, "SETTLED_A"), wide, 0.0005, "the fixture's margins are what they claim")
	ok(MapLayers.firmness(st, "SETTLED_A", "SETTLED_B") == 0, "two firm grips make a settled border")
	ok(MapLayers.firmness(st, "SETTLED_A", "EDGE_OVER") == 0,
		"a hair OUTSIDE FIRM_MARGIN is still settled")
	ok(MapLayers.firmness(st, "SETTLED_A", "EDGE_UNDER") == 1,
		"and a hair INSIDE it is uneasy")
	ok(Factions.holder_of(st, "TIED") == Factions.CONTESTED,
		"a five-thousandth lead is contested, by Factions' own rule")
	ok(MapLayers.firmness(st, "SETTLED_A", "TIED") == 2,
		"and a contested side frays the border however firm the other one is")
	ok(MapLayers.firmness(st, "TIED", "SETTLED_A") == 2, "in either order")
	## THE ASYMMETRY IS THE POINT: firmness is a property of the PAIR.
	ok(MapLayers.firmness(st, "SETTLED_A", "EDGE_UNDER")
		!= MapLayers.firmness(st, "SETTLED_A", "SETTLED_B"),
		"a province held past doubt beside one about to fall is NOT a firm border")
	ok(MapLayers.firmness(st, "EDGE_UNDER", "SETTLED_A")
		== MapLayers.firmness(st, "SETTLED_A", "EDGE_UNDER"),
		"and the answer does not depend on which name came first")
	## Both arguments must be able to move the answer on their own.
	ok(MapLayers.firmness(st, "EDGE_UNDER", "EDGE_UNDER") == 1, "two uneasy sides are uneasy")
	ok(MapLayers.firmness(st, "TIED", "TIED") == 2, "two contested sides are frayed")


func _hold(m: float) -> Dictionary:
	## A hold whose margin is EXACTLY `m`. The first draft of this fixture set a
	## leader and a remainder that looked about right and produced 0.5894 where
	## it claimed 0.3841 -- every firmness assertion downstream then went red,
	## and the model was the half that was correct. Solve it instead: the shares
	## sum to one and the other three are equal, so top - (1 - top) / 3 = m
	## gives top = (3m + 1) / 4.
	var top := (3.0 * m + 1.0) / 4.0
	var r := (1.0 - top) / 3.0
	return {Factions.MEN: top, Factions.GOBLINS: r, Factions.WOLVES: r, Factions.WILD: r}


# ============================ 7 · the tint image ============================

func _t_tint() -> void:
	claim("tint", 12)
	var c := fresh_chronicle()
	for _i in range(30):
		c.advance(24.0, 4000)
	var sides := MapLayers.sides(_roster, c.factions)
	var img := MapLayers.tint_image(_part, NX, NZ, sides)
	ok(img.get_width() == NX and img.get_height() == NZ,
		"the tint is one texture the size of the grid")
	ok(img.get_format() == Image.FORMAT_RGBA8, "with an alpha channel")

	## EVERY PIXEL IS ITS CELL'S HOLDER. Not a sample: all of them.
	var wrong := 0
	var clear := 0
	var painted := 0
	for j in range(NZ):
		for i in range(NX):
			var s := sides[_part[j * NX + i]]
			var want := MapLayers.colour_of(s)
			if want.a > 0.0:
				want.a = MapLayers.FILL_ALPHA
				painted += 1
			else:
				clear += 1
			var got := img.get_pixel(i, j)
			if absf(got.r - want.r) > 0.01 or absf(got.g - want.g) > 0.01 \
					or absf(got.b - want.b) > 0.01 or absf(got.a - want.a) > 0.01:
				wrong += 1
	ok(wrong == 0, "every one of %d pixels carries its cell's holder (%d wrong)" % [NX * NZ, wrong])
	ok(painted > 0, "some of the map is held (%d cells)" % painted)
	ok(clear > 0, "and some of it is sea, left CLEAR rather than coloured (%d)" % clear)
	ok(float(clear) / float(NX * NZ) > 0.05,
		"the sea is a real share of the image (%.1f%%)" % (100.0 * float(clear) / float(NX * NZ)))
	ok(MapLayers.FILL_ALPHA < 0.5,
		"the tint is a WASH over the bake, never a replacement for it (%.2f)" % MapLayers.FILL_ALPHA)
	ok(MapLayers.FILL_ALPHA > 0.0, "but it is visible")
	ok(MapLayers.C_BORDER.a > MapLayers.FILL_ALPHA, "and a border is firmer than a wash")
	## A held side and an unheld one never share a colour.
	ok(MapLayers.colour_of(Factions.MEN) != MapLayers.colour_of(MapLayers.NONE),
		"men and nobody are different colours")
	ok(MapLayers.colour_of(Factions.MEN) != MapLayers.colour_of(Factions.GOBLINS),
		"and so are men and goblins")
	ok(MapLayers.tint_image(PackedInt32Array(), NX, NZ, sides).get_width() == NX,
		"an empty partition still returns an image of the right size rather than crashing")
	c.free()


# ======================== 8 · what the hover says ========================

func _t_readout() -> void:
	claim("readout", 16)
	var st := {
		"CASCO BAY": _hold(0.60),
		"RANGELEY LAKES": _hold(0.005),
		"MOOSEHEAD": _hold(MapLayers.FIRM_MARGIN - 0.02),
	}
	var a := MapLayers.hold_line(st, "CASCO BAY")
	ok(a.contains("Casco Bay"), "a place is named the way a person would say it")
	ok(not a.contains("CASCO BAY"), "NOT IN CAPITALS mid-sentence")
	ok(a.contains("held by men"), "and it says who holds it: '%s'" % a)
	ok(not a.contains("held, barely"), "a firm grip is not hedged")
	ok(a.contains("%"), "with the margin as a percentage")
	var b := MapLayers.hold_line(st, "RANGELEY LAKES")
	ok(b.contains("contested"), "a contested region says so: '%s'" % b)
	ok(not b.contains("held"), "and does not also claim somebody holds it")
	ok(not b.contains("%"), "nor put a number on a thing with no leader")
	var d := MapLayers.hold_line(st, "MOOSEHEAD")
	ok(d.contains("held, barely"), "a grip inside FIRM_MARGIN is hedged: '%s'" % d)
	ok(d.contains("Moosehead"), "and still names the place properly")
	ok(MapLayers.hold_line(st, "GULF OF MAINE").is_empty(),
		"the sea says NOTHING rather than 'held by nobody'")
	ok(MapLayers.hold_line({}, "CASCO BAY").is_empty(), "and so does an empty state")
	ok(MapLayers.hold_line(st, "").is_empty(), "and so does no region at all")
	## The claimant names are English, not the sim's keys.
	ok(MapLayers._who(Factions.GOBLINS) == "goblins", "goblins are goblins")
	ok(MapLayers._who(Factions.WILD) != Factions.WILD,
		"but WILD is not a word anyone says: '%s'" % MapLayers._who(Factions.WILD))
	ok(MapLayers._who("weather") == "weather", "and anything unknown comes back unchanged")


# ==================== 9 · the real Chronicle, stepped ====================

func _t_chronicle() -> void:
	claim("chronicle", 18)
	## A STUB IS NOT THE COLLABORATOR.
	var c := fresh_chronicle()
	var first := MapLayers.border(_roster, c.factions, _part, NX, NZ, ORIGIN, SIZE)
	ok(first.size() > 0, "a fresh world already has a frontier (%d chains)" % first.size())
	## ⚠ NOTHING HAD ASSERTED THAT `border` SMOOTHS AT ALL: passing 0 passes
	## survived a whole sweep. A raw chain's steps are one cell apart in world
	## metres; a smoothed one's are a fraction of that.
	var steps: Array[float] = []
	for e0 in first:
		var pl0: PackedVector2Array = (e0 as Dictionary)["pts"]
		for i0 in range(pl0.size() - 1):
			steps.append(pl0[i0].distance_to(pl0[i0 + 1]))
	steps.sort()
	ok(steps.size() > 100, "there are border steps to measure (%d)" % steps.size())
	ok(steps[steps.size() / 2] < CELL_M * 0.75,
		"the border IS smoothed: its median step is %.1f m against a %.1f m cell" % [
			steps[steps.size() / 2], CELL_M])
	ok(steps[steps.size() - 1] <= CELL_M * 1.01,
		"and no step is longer than one cell (%.1f m)" % steps[steps.size() - 1])
	var key0 := "|".join(MapLayers.sides(_roster, c.factions))

	## The border HOLDS STILL while nobody changes hands -- which is what makes
	## caching it on the holder signature legitimate rather than a guess.
	var same := MapLayers.border(_roster, c.factions, _part, NX, NZ, ORIGIN, SIZE)
	ok(same.size() == first.size(), "asked twice of the same state it is the same border")
	ok(_sig(same) == _sig(first), "chain for chain, point for point")

	## And it MOVES when ground does change hands.
	var moved := false
	var grew := false
	var shrank := false
	var seen_firm := {}
	var last := first
	var lastkey := key0
	for step in range(120):
		c.advance(24.0, 4000)
		var k := "|".join(MapLayers.sides(_roster, c.factions))
		var now := MapLayers.border(_roster, c.factions, _part, NX, NZ, ORIGIN, SIZE)
		for e in now:
			seen_firm[int((e as Dictionary)["firm"])] = true
		if k != lastkey:
			if _sig(now) != _sig(last):
				moved = true
			if now.size() > last.size():
				grew = true
			if now.size() < last.size():
				shrank = true
		lastkey = k
		last = now
	ok(moved, "a province changing hands re-cuts the border")
	ok(grew and shrank, "and the frontier both lengthens and shortens over a year")
	ok(seen_firm.has(0), "settled borders occur")
	ok(seen_firm.has(1), "uneasy ones occur")
	ok(seen_firm.has(2), "and frayed ones occur")
	ok(seen_firm.size() == 3, "all three rungs are reachable in one simulated year")

	## Every row is well formed and in WORLD coordinates inside the map.
	var bad := 0
	var outside := 0
	for e2 in last:
		var ed := e2 as Dictionary
		if not (ed.has("pts") and ed.has("a") and ed.has("b") and ed.has("firm")):
			bad += 1
		for q: Vector2 in (ed["pts"] as PackedVector2Array):
			if q.x < ORIGIN.x - 1.0 or q.y < ORIGIN.y - 1.0 \
					or q.x > ORIGIN.x + SIZE.x + 1.0 or q.y > ORIGIN.y + SIZE.y + 1.0:
				outside += 1
	ok(bad == 0, "every row carries its two names and its firmness")
	ok(outside == 0, "and every point is inside the map (%d were not)" % outside)
	## Determinism: the same state gives the same chains in the same ORDER, so
	## the map does not flicker between two equally valid drawings.
	var again := MapLayers.border(_roster, c.factions, _part, NX, NZ, ORIGIN, SIZE)
	ok(_sig(again) == _sig(last), "the border is deterministic, order included")
	## ⚠ AND THAT IS NOT WHAT `keys.sort()` BUYS. Dictionary keys come back in
	## insertion order, which is already deterministic inside one process, so
	## dropping the sort survived a sweep against the assertion above. What the
	## sort actually buys is a draw order fixed by NAME rather than by whichever
	## corner of the map the march happened to reach first -- so a province
	## changing hands cannot reshuffle which border is drawn over which.
	var order: Array[String] = []
	for e3 in last:
		order.append("%s|%s" % [(e3 as Dictionary)["a"], (e3 as Dictionary)["b"]])
	var sorted_order := order.duplicate()
	sorted_order.sort()
	ok(order == sorted_order,
		"the border is drawn in region-name order, not in march order")
	ok(last.size() >= 5 and last.size() <= 40,
		"and there are few enough chains to read (%d)" % last.size())
	ok(key0.length() > 0 and key0.contains("|"),
		"the holder signature the panel caches on is a real string")
	c.free()


func _sagitta_px(pts: PackedVector2Array, passes: int) -> float:
	## How far the drawn polyline sits from the curve it approximates, in view
	## pixels, at ZOOM_MAX. A cell is 4.00 px unzoomed and the panel zooms to 10x.
	var cur := MapLayers.chaikin(pts, passes)
	var longest := 0.0
	for i in range(cur.size() - 1):
		longest = maxf(longest, cur[i].distance_to(cur[i + 1]))
	var sharp := 0.0
	for i2 in range(1, cur.size() - 1):
		var u := (cur[i2] - cur[i2 - 1]).normalized()
		var v := (cur[i2 + 1] - cur[i2]).normalized()
		sharp = maxf(sharp, rad_to_deg(acos(clampf(u.dot(v), -1.0, 1.0))))
	var facet_px := longest * CELL_PX * 10.0
	return facet_px * 0.5 * tan(deg_to_rad(sharp) * 0.5)


func _sig(b: Array) -> String:
	var out: PackedStringArray = []
	for e in b:
		var ed := e as Dictionary
		var pts: PackedVector2Array = ed["pts"]
		out.append("%s|%s|%d|%d|%.2f,%.2f" % [ed["a"], ed["b"], int(ed["firm"]),
			pts.size(), pts[0].x, pts[0].y])
	return "/".join(out)


# ============ 10 · the ground you walk vs the graph it pushes on ============

func _t_ground() -> void:
	claim("ground", 10)
	## THE FINDING. `Factions` spreads influence along a relative-neighbourhood
	## graph of 17 edges. The partition -- the ground a player can actually walk
	## across -- puts many more pairs of regions in contact than that. Measured
	## at every step of a simulated year, the graph's frontier is a STRICT
	## SUBSET of the map's, and never once the other way round.
	var c := fresh_chronicle()
	var only_graph := 0
	var extra_total := 0
	var steps := 0
	var max_extra := 0
	for step in range(60):
		c.advance(24.0, 4000)
		steps += 1
		var b := MapLayers.border(_roster, c.factions, _part, NX, NZ, ORIGIN, SIZE)
		var on_ground := {}
		for e in b:
			var ed := e as Dictionary
			on_ground["%s|%s" % [ed["a"], ed["b"]]] = true
		var extra := 0
		for f in Factions.frontier(c.factions, c._fadj):
			var fd := f as Dictionary
			if not on_ground.has("%s|%s" % [fd["a"], fd["b"]]):
				only_graph += 1
		for k in on_ground.keys():
			var found := false
			for f2 in Factions.frontier(c.factions, c._fadj):
				var f2d := f2 as Dictionary
				if "%s|%s" % [f2d["a"], f2d["b"]] == String(k):
					found = true
			if not found:
				extra += 1
		extra_total += extra
		max_extra = maxi(max_extra, extra)
	ok(steps == 60, "a year of steps")
	ok(only_graph == 0,
		"every pair the GRAPH calls a frontier is a border you can WALK (%d were not)" % only_graph)
	ok(extra_total > 0, "but the ground has more (%d pair-steps the graph never mentions)" % extra_total)
	ok(max_extra >= 8,
		"and at its widest the gap is %d pairs at once" % max_extra)
	## Name one, and check it is real geometry rather than a rounding artefact.
	var adj: Dictionary = c._fadj
	ok(not (adj.get("AROOSTOOK", []) as Array).has("KATAHDIN"),
		"the graph says Aroostook and Katahdin are not neighbours")
	var sides := MapLayers.sides(_roster, c.factions)
	var ai := -1
	var ki := -1
	for k2 in range(_roster.size()):
		var nm := String((_roster[k2] as Dictionary)["name"])
		if nm == "AROOSTOOK":
			ai = k2
		if nm == "KATAHDIN":
			ki = k2
	var touch := 0
	for j in range(NZ):
		for i in range(NX):
			var here := _part[j * NX + i]
			if i + 1 < NX and mini(here, _part[j * NX + i + 1]) == mini(ai, ki) \
					and maxi(here, _part[j * NX + i + 1]) == maxi(ai, ki):
				touch += 1
			if j + 1 < NZ and mini(here, _part[(j + 1) * NX + i]) == mini(ai, ki) \
					and maxi(here, _part[(j + 1) * NX + i]) == maxi(ai, ki):
				touch += 1
	ok(touch > 0, "but on the ground they share %d cell walls" % touch)
	ok(float(touch) * CELL_M > 500.0,
		"-- %.1f km of it, which is a border a player would cross" % (float(touch) * CELL_M / 1000.0))
	ok(adj.size() > 0, "the graph is not empty (so this is not a scan agreeing with everything)")
	var edges := 0
	for a in adj.keys():
		edges += (adj[a] as Array).size()
	ok(edges / 2 == 17, "it holds 17 undirected edges (%d)" % (edges / 2))
	ok(true, "AND THIS IS A QUEUE ITEM, NOT A BUG THIS ROUND FIXES: two provinces can share a walkable border and never spill into each other")
	c.free()


# =========================== 12 · what it costs ===========================

func _t_cost() -> void:
	claim("cost", 15)
	## The docstrings make performance CLAIMS -- built once, marched cheaply,
	## drawn in one texture -- and the whole design rests on them. Ceilings are
	## literals set generously against numbers this round actually measured on
	## Lemon's machine (partition 30 ms, march 6 ms, tint 3.4 ms), so the suite
	## bites on a regression of an order of magnitude and not on a slow morning.
	var t0 := Time.get_ticks_usec()
	var p2 := MapLayers.partition(_roster, NX, NZ, ORIGIN, SIZE)
	var build_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	ok(p2.size() == CELLS, "the partition built")
	ok(build_ms < 300.0, "in %.1f ms, which a panel can afford ONCE (measured 30)" % build_ms)

	var c := fresh_chronicle()
	for _i in range(30):
		c.advance(24.0, 4000)
	var sides := MapLayers.sides(_roster, c.factions)
	var t1 := Time.get_ticks_usec()
	var b := MapLayers.border(_roster, c.factions, p2, NX, NZ, ORIGIN, SIZE)
	var march_ms := float(Time.get_ticks_usec() - t1) / 1000.0
	ok(march_ms < 60.0, "and re-marching it costs %.2f ms (measured 6)" % march_ms)
	ok(march_ms < build_ms,
		"-- cheaper than rebuilding it, which is why the partition is cached and the border is not")
	var t2 := Time.get_ticks_usec()
	var img := MapLayers.tint_image(p2, NX, NZ, sides)
	var tint_ms := float(Time.get_ticks_usec() - t2) / 1000.0
	ok(tint_ms < 60.0, "the tint image takes %.2f ms (measured 3.4)" % tint_ms)
	ok(img.get_width() * img.get_height() == CELLS,
		"and is %d pixels, not %d rectangles" % [CELLS, CELLS])

	## WHAT A FRAME ACTUALLY DRAWS. Over a simulated year: the chain count and
	## the total point count, which are what `_draw_border` walks every frame.
	var lo_chains := 999
	var hi_chains := 0
	var hi_pts := 0
	var hi_one := 0
	for step in range(80):
		c.advance(24.0, 4000)
		var now := MapLayers.border(_roster, c.factions, p2, NX, NZ, ORIGIN, SIZE)
		lo_chains = mini(lo_chains, now.size())
		hi_chains = maxi(hi_chains, now.size())
		var pts := 0
		for e in now:
			var n := ((e as Dictionary)["pts"] as PackedVector2Array).size()
			pts += n
			hi_one = maxi(hi_one, n)
		hi_pts = maxi(hi_pts, pts)
	ok(lo_chains >= 5, "the map never has fewer than %d border chains" % lo_chains)
	ok(hi_chains <= 40, "and never more than %d -- a legible number of lines" % hi_chains)
	ok(hi_pts < 22000, "the whole frontier is %d points at its busiest" % hi_pts)
	ok(hi_one < 3000, "and no single chain exceeds %d of them" % hi_one)
	ok(hi_chains >= lo_chains, "the range is a range")

	## The drawn layers are bounded too, by the systems' own caps.
	ok(Carcasses.MAX_RECORDS <= 128,
		"the kill layer can never draw more than %d marks" % Carcasses.MAX_RECORDS)
	ok(Carcasses.BONES_AT > 0.0 and Carcasses.BONES_AT < 1.0,
		"and the mark's fill threshold is a real fraction (%.2f)" % Carcasses.BONES_AT)
	## THE PARTITION IS THE EXPENSIVE HALF AND IT IS THE HALF THAT NEVER
	## CHANGES. Said as an assertion so a later round cannot quietly move the
	## roster into something the panel would have to rebuild.
	var p3 := MapLayers.partition(_roster, NX, NZ, ORIGIN, SIZE)
	ok(p3 == p2, "and the same roster gives the identical partition, so caching it forever is sound")
	ok(_roster == Chronicle.REGION_ROSTER, "-- the roster being a const is what makes that true")
	c.free()


# ===================== 13 · the keys the layers read =====================

func _t_contracts() -> void:
	claim("contracts", 26)
	## A CALLER WITH NO TERM. The croft, traveller and kill layers cannot be
	## drawn headless -- they need a built road net and a streaming world -- so
	## the thing that WOULD rot silently is a renamed dictionary key: the layer
	## keeps drawing nothing and no suite anywhere notices. Every key those
	## three layers read is checked against the file that writes it.
	var panel := _code_only(read_src("res://scripts/MapPanel.gd"))

	## Carcasses: a REAL record off the real bus, not a literal copied here.
	var ca := Carcasses.new()
	get_root().add_child(ca)
	ca.boot(true)
	var rec := ca.add("whitetail", "White-tailed Deer", Vector3(10.0, 0.0, -20.0), 49.13)
	ok(not rec.is_empty(), "the carcass bus makes a record")
	for k: String in ["at", "mass", "left"]:
		ok(rec.has(k), "and it carries the key the kill layer reads: %s" % k)
		ok(panel.contains('rd.get("%s"' % k), "which the kill layer does read: rd.get(\"%s\")" % k)
	ok(rec["at"] is Vector3, "`at` is a Vector3, which is why the layer uses at.x and at.z")
	ok(panel.contains("_to_view(at.x, at.z)"), "and it does")
	ok(float(rec["mass"]) > 0.0, "mass is positive, so the fraction cannot divide by zero")
	near_f(float(rec["left"]), float(rec["mass"]), 0.001, "a fresh kill is whole")
	ok(panel.contains("f > Carcasses.BONES_AT"),
		"and the mark changes at the same threshold the sim calls bones")
	ca.free()

	## Crofts and Wayfarers: the record literals in their own sources.
	var crofts := _code_only(read_src("res://scripts/Crofts.gd"))
	for k2: String in ["\"pos\":", "\"id\":", "\"name\":"]:
		ok(crofts.contains(k2), "Crofts._seat writes %s" % k2)
	for k3: String in ["\"cold_h\":", "\"was_cold\":"]:
		ok(crofts.contains(k3), "Crofts._ensure_state writes %s" % k3)
	ok(panel.contains('sd.get("cold_h", 0.0)') and panel.contains('sd.get("was_cold", false)'),
		"and the croft layer reads BOTH, so a hearth that went cold once still shows")
	ok(panel.contains('cd.get("pos", Vector2.ZERO)'), "and reads the croft's position")
	ok(panel.contains('cr.get("state")'), "off the state dictionary the sim keeps")

	var way := _code_only(read_src("res://scripts/Wayfarers.gd"))
	for k4: String in ["\"pos\": p", "\"dir\": dir.normalized()", "\"holding\":"]:
		ok(way.contains(k4), "Wayfarers.where returns %s" % k4)
	ok(panel.contains('wf.call("where", b as Dictionary)'),
		"and the traveller layer asks `where` for it, band by band")
	ok(panel.contains('bool(w.get("holding", false))'),
		"-- including whether the weather is HOLDING that band somewhere")

	## The bus lookups are by GROUP, and every group name is one a bus joins.
	var groups := {"chronicle": "res://scripts/Chronicle.gd",
		"roads": "res://scripts/RoadNet.gd", "crofts": "res://scripts/Crofts.gd",
		"carcasses": "res://scripts/Carcasses.gd", "wayfarers": "res://scripts/Wayfarers.gd"}
	for g in groups.keys():
		var gn := String(g)
		ok(panel.contains('_bus("%s")' % gn), "the panel looks up the %s bus" % gn)
		ok(_code_only(read_src(String(groups[g]))).contains('add_to_group("%s")' % gn),
			"and something actually joins that group")
	ok(panel.contains("get_tree().get_first_node_in_group(group)"),
		"by group and never by class_name -- World.gd loads this panel by PATH to avoid the cycle")
	## ⚠ `ready` IS A SIGNAL ON Node. Every bus this panel waits on must be
	## asked whether it HAS the method before the method is called.
	ok(panel.contains('n.has_method("ready") and bool(n.call("ready"))'),
		"and a bus's readiness is asked through has_method, not assumed")
	ok(not panel.contains('.call("ready")\n') or panel.contains("_bus_ready("),
		"no draw call reaches for ready() without that guard")
	for fn2: String in ["_draw_roads", "_draw_crofts", "_draw_bands"]:
		var a2 := panel.find("func %s(" % fn2)
		var b2 := panel.find("\nfunc ", a2 + 1)
		var body2 := panel.substr(a2, (b2 if b2 > a2 else panel.length()) - a2)
		ok(body2.contains("if not _bus_ready("),
			"%s waits for its bus through the guard" % fn2)
	## And the three buses really do declare the method that shadows the signal.
	for src2: String in ["res://scripts/RoadNet.gd", "res://scripts/Crofts.gd",
			"res://scripts/Wayfarers.gd"]:
		ok(_code_only(read_src(src2)).contains("func ready() -> bool:"),
			"%s declares ready() as a method" % src2)


# ======================= 14 · the chips and the key =======================

func _t_panel() -> void:
	claim("panel", 17)
	var panel := _code_only(read_src("res://scripts/MapPanel.gd"))
	## Every layer has a name, a default, a chip and a chip colour, and the
	## four lists agree. A layer with no chip cannot be turned off; a chip with
	## no layer toggles nothing.
	for id: String in ["frontier", "roads", "crofts", "travellers", "kills"]:
		ok(panel.contains('L_%s := "%s"' % [_const_for(id), id]),
			"the %s layer is named" % id)
	ok(panel.contains("const LAYERS: Array[String] = [L_FRONTIER, L_ROADS, L_CROFTS, L_BANDS, L_KILLS]"),
		"all five are in the LAYERS list the chips are built from")
	ok(panel.contains("var _on := {L_FRONTIER: true, L_ROADS: true, L_CROFTS: true,"),
		"and all five start ON")
	ok(panel.contains("for id: String in LAYERS:"), "the chips are built FROM that list")
	ok(panel.contains("_paint_chip(b, id)"), "and painted from it")
	ok(panel.contains("CHIP_TINT.get(id,"), "each chip wears its layer's colour")
	## The table itself, row by row -- and sliced out of the source first, so
	## "L_FRONTIER:" matching somewhere else in the file cannot carry it. The
	## first draft of this loop was `ok(has_the_table or has_the_name)`, which
	## is an ESCAPE HATCH: the left clause is true once and the row could go
	## missing forever without a red line.
	var tstart := panel.find("const CHIP_TINT := {")
	ok(tstart >= 0, "the chip colour table is in the file")
	var tend := panel.find("}", tstart)
	var table := panel.substr(tstart, tend - tstart)
	ok(table.length() > 40, "and it was sliced out (%d chars)" % table.length())
	for cid: String in ["L_FRONTIER:", "L_ROADS:", "L_CROFTS:", "L_BANDS:", "L_KILLS:"]:
		ok(table.contains(cid), "CHIP_TINT has a row for %s" % cid)
	ok(not table.contains("L_NONSENSE:"),
		"-- and the slice is not a scan that agrees with everything")
	ok(panel.contains("_view.queue_redraw()"), "toggling a chip redraws the map")


func _const_for(id: String) -> String:
	if id == "travellers":
		return "BANDS"
	return id.to_upper()


# =============================== 11 · wiring ===============================

func _t_wiring() -> void:
	claim("wiring", 40)
	## A METHOD NOBODY CALLS IS NOT A FEATURE, and a call-site scan is satisfied
	## by a gutted call. Scan for the BRANCH, the ARGUMENTS and the VALUE.
	var panel := _code_only(read_src("res://scripts/MapPanel.gd"))
	var layers := _code_only(read_src("res://scripts/MapLayers.gd"))
	ok(panel.length() > 4000, "MapPanel.gd was read (%d chars of code)" % panel.length())
	ok(layers.length() > 3000, "MapLayers.gd was read (%d chars of code)" % layers.length())
	## PROVE THE SCANNER BITES, against text built by concatenation so no
	## literal in this file can satisfy the scan it is checking.
	var planted := "func x():" + "\n\t" + "MapLayers" + "." + "partition(a, b)"
	ok(_code_only(planted).contains("MapLayers.partition("),
		"the scanner finds a planted call")
	ok(not _code_only("# " + "MapLayers" + "." + "partition(a, b)").contains("MapLayers.partition("),
		"and does NOT find one that is only a comment")
	var mixed := "\tvar z = 1  # " + "MapLayers" + "." + "tint_image(q)"
	ok(not _code_only(mixed).contains("MapLayers.tint_image("),
		"nor one in a trailing comment")

	for sig: String in [
			"MapLayers.partition(Chronicle.REGION_ROSTER, MapLayers.GRID_NX,",
			"MapLayers.sides(Chronicle.REGION_ROSTER, st)",
			"MapLayers.border(Chronicle.REGION_ROSTER, st, _part,",
			"MapLayers.tint_image(_part, MapLayers.GRID_NX, MapLayers.GRID_NZ, sides)",
			"MapLayers.hold_line(ch.get(\"factions\") as Dictionary, rn)",
			"MapLayers.colour_of(h)",
			"MapLayers.FIRM_WIDTH[firm]",
			"MapLayers.FIRM_DASH[firm]",
			"MapLayers.FIRM_GAP[firm]",
			"MapLayers._who(h2)",
			"Seasons.local_index(float(ch.get(\"days\")), here)",
			"Factions.region_at(Vector3(w.x, 0.0, w.y), Chronicle.REGION_ROSTER)",
			"ImageTexture.create_from_image(img)"]:
		ok(panel.contains(sig), "MapPanel actually calls it: %s" % sig)

	## THE BRANCHES. A layer that is drawn unconditionally is not a toggle.
	for br: String in [
			"if bool(_on[L_FRONTIER]):", "if bool(_on[L_ROADS]):",
			"if bool(_on[L_CROFTS]):", "if bool(_on[L_BANDS]):",
			"if bool(_on[L_KILLS]):"]:
		ok(panel.contains(br), "and guards it behind its own chip: %s" % br)

	## NO NEW KEY BINDING. Twenty-four keys are already claimed by Player._input
	## and a shadowed dev input is round-blocking; the chips are mouse only.
	ok(not panel.contains("InputEventKey"), "the map panel presses no keys")
	ok(not panel.contains("KEY_"), "and names none")
	ok(panel.contains("b.toggled.connect(_on_chip.bind(id, b))"),
		"the layers are toggled by a Button, which is mouse and focus only")
	ok(panel.contains("b.focus_mode = Control.FOCUS_NONE"),
		"and the chips never steal focus from the game")
	## The small layers respect the panel's own zoom rule rather than inventing
	## one. ⚠ A SCAN IS SATISFIED BY ANOTHER OCCURRENCE: the first draft of this
	## asked whether "if _zoom < LABEL_ZOOM:" appeared ANYWHERE in the file, and
	## it appears in `_draw_lakes` too -- so gutting the croft layer's guard
	## sailed through a mutation sweep. Ask each function's OWN body.
	for fn: String in ["_draw_crofts", "_draw_kills"]:
		var a := panel.find("func %s(" % fn)
		var b := panel.find("\nfunc ", a + 1)
		ok(a >= 0, "%s exists" % fn)
		var body := panel.substr(a, (b if b > a else panel.length()) - a)
		ok(body.contains("if _zoom < LABEL_ZOOM:"),
			"and %s ITSELF obeys the rule villages already obeyed" % fn)
		ok(not body.contains("func _draw_lakes"),
			"-- and the slice is one function, not the rest of the file")
	## The cache is keyed on the holders, not on a timer alone.
	ok(panel.contains("if key == _pol_key and not force and _tint != null:"),
		"and the border is re-cut only when a region actually changes hands")
	## ⚠ A SCAN IS SATISFIED BY ANOTHER OCCURRENCE -- for the THIRD time this
	## round. Asking whether "MapLayers.C_BORDER_BED, wsz + MapLayers.BED_EXTRA"
	## appears ANYWHERE was answered by the dashed branch's copy of it, so
	## gutting the SOLID branch's bed survived a sweep. Each branch's own full
	## line, or the assertion is about the file and not about the drawing.
	for st2: String in [
			"_view.draw_polyline(view, MapLayers.C_BORDER_BED, wsz + MapLayers.BED_EXTRA, true)",
			"_view.draw_polyline(view, MapLayers.C_BORDER, wsz, true)",
			"_dashed(view, MapLayers.C_BORDER_BED, wsz + MapLayers.BED_EXTRA, dash, gap)",
			"_dashed(view, MapLayers.C_BORDER, wsz, dash, gap)"]:
		ok(panel.contains(st2), "the border is drawn bed-then-line: %s" % st2)
	ok(panel.contains("_dashed(view, MapLayers.C_BORDER_BED, wsz + MapLayers.BED_EXTRA, dash, gap)"),
		"and a dashed border gets the same two strokes, not one")
	## ⚠ A 130x195 TEXTURE STRETCHED OVER 520x780 UNDER THE PROJECT'S PIXEL-ART
	## NEAREST FILTER IS A GRID OF BLOCKS, not a wash -- photographed at 3x zoom.
	ok(panel.contains("_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR"),
		"the map view filters linearly, so the territory reads as a wash")


# ================================== run ==================================

func _init() -> void:
	print("MapLayerTests -- the map of Myrkfell")
	_roster = Chronicle.REGION_ROSTER
	_part = MapLayers.partition(_roster, NX, NZ, ORIGIN, SIZE)
	_t_partition()
	_t_nesting()
	_t_sea()
	_t_walls()
	_t_smooth()
	_t_firm()
	_t_tint()
	_t_readout()
	_t_chronicle()
	_t_ground()
	_t_cost()
	_t_contracts()
	_t_panel()
	_t_wiring()

	var short_of := 0
	for k in _claims.keys():
		var want := int(_claims[k])
		var got := int(_counts[k])
		if got < want:
			short_of += 1
			print("  SECTION [%s] staked %d assertions and made %d" % [k, want, got])
	if short_of > 0:
		_fail += short_of
	if _pass + _fail < MIN_ASSERTIONS:
		print("  TOO FEW ASSERTIONS: %d, floor is %d" % [_pass + _fail, MIN_ASSERTIONS])
		_fail += 1
	if _fail == 0:
		print("ALL GREEN — %d assertions" % _pass)
	else:
		print("%d passed, %d FAILED" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
