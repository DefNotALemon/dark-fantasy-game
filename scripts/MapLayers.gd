class_name MapLayers
extends RefCounted
## THE MAP STOPS BEING A PICTURE OF THE GROUND.
##
## Myrkfell has spent two weeks growing a meta-simulation -- 57 roads, 25
## crofts, 20 travelling bands, carcasses on the ground, a year that differs by
## place, and since `42a74e1` a frontier between four claimants that moves and
## moves back -- and the map (M) drew none of it. It drew Maine: coastline,
## peaks, lakes, towns. Geography. Nothing that had happened since the world
## booted was on it anywhere.
##
## ---------------------------------------------------------------------------
## THE ONE IDEA: A BORDER IS NOT DRAWN, IT IS FOUND.
## ---------------------------------------------------------------------------
## The obvious way to draw a frontier is to take `Factions.frontier()`'s pairs
## of disagreeing regions and put a line between each pair's two centres. That
## was this round's first design and a probe killed it in one run: the regions
## are CIRCLES, and FIVE of the seventeen adjacent pairs OVERLAP. Katahdin
## (r 356 m) sits wholly inside Baxter State Park (r 930 m) -- their centres are
## 43.5 view pixels apart and Baxter's radius alone is 67.2 -- so "the line goes
## in the gap between the two circles" is not merely inaccurate there, it is
## undefined, and it would have been undefined for a third of the map.
##
## The sim already answers the question properly and has since the Chronicle
## shipped. `Factions.region_at` says: you are in the circle that contains you,
## and if no circle contains you, you belong to the nearest centre. That rule --
## not a polygon, not a Voronoi diagram, not anything anyone drew -- IS the
## political map of Myrkfell. So this file does not invent a boundary. It
## marches that rule over a grid and emits a wall wherever two neighbouring
## cells come back in different hands.
##
## Every line the map draws is the simulation's own answer, read back.
##
## ---------------------------------------------------------------------------
## THE SECOND IDEA: HOW FIRMLY THE LINE IS DRAWN IS THE MARGIN.
## ---------------------------------------------------------------------------
## `Factions.margin_of` has always said how far ahead the leader is, and nothing
## had ever shown it to a player. A border between two regions each held past
## doubt is a settled thing and gets a solid stroke; one where either side is
## within `FIRM_MARGIN` of losing its grip is UNEASY and gets a thinner, broken
## one; and where the sim itself says CONTESTED there is no border at all, only
## a frayed scribble, because that is what the word means.
##
## ---------------------------------------------------------------------------
## COST
## ---------------------------------------------------------------------------
## `partition()` is a pure function of a CONSTANT roster: it is the same answer
## for the life of the game and is built ONCE, lazily, the first time the map
## opens -- 63 ms measured at GRID_NX. Everything downstream is cheap and only
## reruns when a region changes hands: the march is 2.16 ms and the tint image
## is one texture upload of 130x195 pixels. Nothing here runs per frame.
##
## Pure static: no node, no clock, no RNG, no `get_tree`, no state.


# =============================================================================
# CLAIMANTS
# =============================================================================
## `Factions` names four claimants plus CONTESTED. NONE is this file's own: the
## sea, and any region the faction state has never heard of. It is drawn as
## nothing at all rather than as a colour, because "I do not know" is not a
## claim and must not look like one.
const NONE := ""

const SIDE_ORDER: Array[String] = [
	Factions.MEN, Factions.GOBLINS, Factions.WOLVES, Factions.WILD,
	Factions.CONTESTED, NONE,
]

## Measured, 2026-09-12: over 96 simulated days x 17 land regions the holder
## tally came back {men: 792, goblins: 493, contested: 347} and BOTH WOLVES AND
## WILD WERE NEVER ONCE THE HOLDER OF ANYTHING. Myrkfell is a two-power map with
## contested ground between. Their colours are here because `Factions` can
## return them and a map that cannot draw an answer the sim can give is a bug
## waiting; they are simply not what a player will see.
const TINT := {
	Factions.MEN: Color(0.86, 0.71, 0.40),        ## ochre -- tilled, roaded, taxed
	Factions.GOBLINS: Color(0.49, 0.71, 0.36),    ## a sour green
	Factions.WOLVES: Color(0.60, 0.65, 0.79),     ## cold slate
	Factions.WILD: Color(0.42, 0.54, 0.44),       ## moss
	Factions.CONTESTED: Color(0.90, 0.41, 0.33),  ## rust
}

## How much of the tint reaches the paper. The bake underneath is the map; this
## is a wash over it, never a replacement for it.
const FILL_ALPHA := 0.30


static func colour_of(side: String) -> Color:
	## An unknown side is transparent, not a fallback colour. A FALLBACK CAN
	## HIDE THE THING YOU BUILT: if this answered ochre for everything it did
	## not recognise, the sea would join the kingdom of men and nobody would
	## ever see a border move.
	if not TINT.has(side):
		return Color(0, 0, 0, 0)
	return TINT[side] as Color


# =============================================================================
# THE GRID
# =============================================================================
## 130 x 195 is not a round number; it is the coarsest grid whose cell is still
## smaller than a map label's stroke at zoom 1. The map view is 520 x 780 view
## pixels, so a cell is EXACTLY 4.00 px across unzoomed, and 55.4 m on the
## ground. Measured cost at this size: 62.9 ms to build the partition once,
## 2.16 ms to march it, 737 border walls. The next step up (192 x 288) costs
## 138 ms and 1097 walls to buy a stair-step nobody can see.
const GRID_NX := 130
const GRID_NZ := 195

## ⚠ THIS COMMENT USED TO SAY SOMETHING FALSE, AND THE PICTURE PROVED IT. It
## read "three rounds start pulling the line off the cells it came from", chose
## two on that basis, and the map went up with a plainly visible pixel staircase
## along every long border. Two things were wrong with it.
##
## First, Chaikin CONVERGES; it does not wander. Second -- and this is the one
## that decided the number -- the thing a player can SEE is not the turn angle
## and not the distance from the cells. It is the SAGITTA: how far the drawn
## polyline sits from the smooth curve it approximates, in VIEW PIXELS, at the
## deepest zoom the panel allows. Measured on a TRUE 90-degree staircase, which
## is what marching a grid actually produces (the first probe used a diagonal
## ramp and flattered every row):
##
##   passes  points  off-wall   sharpest   facet at 10x   SAGITTA at 10x
##        1      48   0.0000     45.0 deg      20.00 px      4.142 px
##        2      96   0.0625     26.6          10.00         1.180 px   <- shipped, and visible
##        3     192   0.0938     14.0           5.00         0.308 px
##        4     384   0.1094      7.1           2.50         0.078 px   <- here
##        5     768   0.1172      3.6           1.25         0.020 px
##
## Four: the first pass count whose deviation is a small fraction of one pixel
## at 10x zoom, so the staircase is gone at every zoom the panel can reach. It
## is still inside an eighth of a cell of the walls it came from (6.1 m on the
## ground), so the map and `region_at` never disagree about which side of a
## border you are standing on; and five would double the point count to buy a
## deviation four hundredths of a pixel smaller.
const SMOOTH_PASSES := 4

## A wall or two on its own is a diagonal cutting a corner, not a border.
const MIN_CHAIN := 3


static func partition(roster: Array, nx: int, nz: int, origin: Vector2,
		size: Vector2) -> PackedInt32Array:
	## Which region owns each cell, by `Factions.region_at`'s rule and no other:
	## the containing circle if there is one, else the nearest centre. This is
	## a pure function of a constant roster, so it is built once and kept.
	var out := PackedInt32Array()
	if nx <= 0 or nz <= 0 or roster.is_empty():
		return out
	out.resize(nx * nz)
	var cw := size.x / float(nx)
	var ch := size.y / float(nz)
	## Unpacked once rather than read out of the Dictionaries 25 000 times.
	var cxs := PackedFloat32Array()
	var czs := PackedFloat32Array()
	var rr := PackedFloat32Array()
	for r in roster:
		var rd := r as Dictionary
		var c: Vector2 = rd.get("pos", Vector2.ZERO)
		cxs.append(c.x)
		czs.append(c.y)
		rr.append(float(rd.get("r", 500.0)))
	var n := cxs.size()
	for j in range(nz):
		var wz := origin.y + (float(j) + 0.5) * ch
		var row := j * nx
		for i in range(nx):
			var wx := origin.x + (float(i) + 0.5) * cw
			var best := -1
			var bd := INF
			var near := 0
			var nd := INF
			for k in range(n):
				var dx := cxs[k] - wx
				var dz := czs[k] - wz
				var d := sqrt(dx * dx + dz * dz)
				if d < nd:
					nd = d
					near = k
				if d < rr[k] and d < bd:
					bd = d
					best = k
			out[row + i] = best if best >= 0 else near
	return out


static func cell_to_world(i: float, j: float, nx: int, nz: int,
		origin: Vector2, size: Vector2) -> Vector2:
	## CORNER coordinates, not centres: corner (0, 0) is the map's top-left and
	## corner (nx, nz) its bottom-right, so a wall between two cells lands on
	## the line that actually divides them.
	return Vector2(origin.x + i / float(nx) * size.x,
			origin.y + j / float(nz) * size.y)


# =============================================================================
# WHO HOLDS WHAT
# =============================================================================
static func sides(roster: Array, state: Dictionary) -> PackedStringArray:
	## The holder of each roster entry, by index. A region the faction state has
	## never heard of -- the Gulf of Maine, which `Factions.land_regions` drops
	## as open water -- is NONE and not WILD. `Factions.holder_of` answers WILD
	## for anything it does not know, which is the right answer to "who holds
	## the Allagash" and the WRONG answer to "who holds the sea": one is wild
	## country you can walk into and the other is not country at all.
	var out := PackedStringArray()
	for r in roster:
		var rd := r as Dictionary
		var nm := String(rd.get("name", ""))
		if not state.has(nm):
			out.append(NONE)
		else:
			out.append(Factions.holder_of(state, nm))
	return out


static func firmness(state: Dictionary, a: String, b: String) -> int:
	## 0 settled, 1 uneasy, 2 frayed. Asked of the PAIR, because a border is a
	## relationship: a province held past doubt beside one about to fall is not
	## a firm border, it is the firm side of a soft one.
	var ha := Factions.holder_of(state, a)
	var hb := Factions.holder_of(state, b)
	if ha == Factions.CONTESTED or hb == Factions.CONTESTED:
		return 2
	var m := minf(Factions.margin_of(state, a), Factions.margin_of(state, b))
	return 1 if m < FIRM_MARGIN else 0


## ⚠ MEASURED ON THE WRONG POPULATION THE FIRST TIME. The per-REGION margin
## distribution has its median at 0.2062, and the first draft used it -- but
## firmness is asked of a PAIR and takes the MINIMUM of two margins, which is
## systematically lower than either. At 0.2062 the probe called 58% of held
## borders uneasy and left only 18% of the map settled: a scale tuned for one
## population and read against another.
##
## Re-measured against the thing the constant is actually asked, 1 640 held
## border pairs over 200 simulated days: pair-min p05 0.0647, p25 0.1024,
## p50 0.1841, p75 0.2833, p95 0.4468. FIRM_MARGIN is the MEDIAN OF THAT, so it
## splits the held borders exactly in half by construction rather than by
## anyone's taste.
##
## It cannot be confused with `Factions.HOLD_MARGIN` (0.06): a pair with either
## margin below that is CONTESTED and never reaches this test at all, which is
## why the held population BEGINS at 0.0647. Two different claims, two different
## numbers, and the second is provably above the first.
##
## What the map therefore looks like: 57% of its borders are frayed, 22% uneasy,
## 21% settled. Myrkfell's frontier is mostly in flux, and that is the sim's
## answer, not a dial.
const FIRM_MARGIN := 0.1841

const FIRM_NAMES: Array[String] = ["settled", "uneasy", "frayed"]

## Stroke width and dash, per rung.
##
## ⚠ FRAYED MEANS BROKEN, NOT FAINT. The first draft faded the alpha as the
## border got shakier, and on screen that made the contested borders -- the only
## places on the map where anything is HAPPENING -- the hardest lines to see.
## A player should be drawn to them. The dash carries the whole meaning now and
## every rung is drawn at full strength.
const FIRM_WIDTH: Array[float] = [2.4, 2.0, 1.7]
const FIRM_DASH: Array[float] = [0.0, 10.0, 4.0]     ## 0 = unbroken
const FIRM_GAP: Array[float] = [0.0, 6.0, 6.0]

## ⚠ AND A NEAR-BLACK LINE DISAPPEARS INTO A DARK FOREST. The border is drawn
## twice, the way the roads are: a dark bed slightly wider than the line, then
## the line itself in bone. That reads against the pale shore, the dark woods
## and every tint this file can put underneath it.
const C_BORDER_BED := Color(0.05, 0.04, 0.04, 0.75)
const C_BORDER := Color(0.97, 0.94, 0.87, 0.96)
const BED_EXTRA := 1.8


# =============================================================================
# MARCHING
# =============================================================================
static func walls(part: PackedInt32Array, nx: int, nz: int,
		side_ids: PackedStringArray) -> Dictionary:
	## Every cell wall with a different hand on each side, grouped by the PAIR
	## of regions that meet across it.
	##
	## ⚠ A COASTLINE IS NOT A FRONTIER. The first draft of this guard only threw
	## a wall away when BOTH sides were NONE, and the probe came back with three
	## kilometres of "frayed border" between Acadia and the GULF OF MAINE, held
	## on one side by nobody -- frayed only because the sea is not in the faction
	## state at all and the firmness fell through to its last rung. A line there
	## says a province lost ground to the ocean. Either side unheld is no border. Grouping by pair rather than piling every
	## wall into one bag is what lets each chain carry its own two names and its
	## own firmness, and it makes each chain exactly one border between exactly
	## two provinces.
	##
	## Corner indexing: corner (i, j) is j * (nx + 1) + i. The wall between
	## cells (i, j) and (i+1, j) is the VERTICAL segment from corner (i+1, j) to
	## corner (i+1, j+1); the wall between (i, j) and (i, j+1) is the HORIZONTAL
	## segment from (i, j+1) to (i+1, j+1).
	var out := {}
	if nx <= 0 or nz <= 0 or part.size() < nx * nz:
		return out
	var w := nx + 1              ## a grid of nx cells has nx+1 corner columns
	for j in range(nz):
		var row := j * nx
		for i in range(nx):
			var ra := part[row + i]
			var sa := side_ids[ra] if ra < side_ids.size() else NONE
			if i + 1 < nx:
				var rb := part[row + i + 1]
				var sb := side_ids[rb] if rb < side_ids.size() else NONE
				if sa != sb and sa != NONE and sb != NONE:
					_add_wall(out, ra, rb, j * w + (i + 1), (j + 1) * w + (i + 1))
			if j + 1 < nz:
				var rc := part[row + nx + i]
				var sc := side_ids[rc] if rc < side_ids.size() else NONE
				if sa != sc and sa != NONE and sc != NONE:
					_add_wall(out, ra, rc, (j + 1) * w + i, (j + 1) * w + (i + 1))
	return out


static func _add_wall(bag: Dictionary, ra: int, rb: int, c0: int, c1: int) -> void:
	## ⚠ The first draft ordered the two corners with mini/maxi here and a
	## mutation sweep would not kill it, because `walls` ALREADY emits them
	## ascending by construction: a vertical wall runs j*w -> (j+1)*w and a
	## horizontal one runs +i -> +(i+1). Two guards on one path; the weaker one
	## is gone and the invariant is asserted instead, in MapLayerTests' `walls`
	## section, as "every wall is one cell edge long, across or down" -- which
	## can only be true of an ascending pair.
	var key := "%d|%d" % [mini(ra, rb), maxi(ra, rb)]
	var arr: Array = bag.get(key, [])
	arr.append(Vector2i(c0, c1))
	bag[key] = arr


static func chains(segs: Array, nx: int) -> Array:
	## Thread a bag of unordered corner-to-corner segments into polylines by
	## shared endpoints. Open runs are walked from their ends first so a line
	## that crosses the map comes out as ONE chain instead of two halves meeting
	## in the middle; whatever is left over is a closed loop -- an enclave --
	## and is walked from anywhere.
	var w := nx + 1
	var at := {}                      ## corner -> Array of segment indices
	for si in range(segs.size()):
		var s: Vector2i = segs[si]
		for c: int in [s.x, s.y]:
			var a: Array = at.get(c, [])
			a.append(si)
			at[c] = a
	var used := PackedByteArray()
	used.resize(segs.size())
	var out: Array = []
	var starts: Array = []
	for c in at.keys():
		if (at[c] as Array).size() == 1:
			starts.append(int(c))
	starts.sort()
	var seeds: Array = starts.duplicate()
	for si2 in range(segs.size()):
		seeds.append(int((segs[si2] as Vector2i).x))
	for seed in seeds:
		var c0 := int(seed)
		while true:
			var nxt := -1
			for si3 in (at.get(c0, []) as Array):
				if used[int(si3)] == 0:
					nxt = int(si3)
					break
			if nxt < 0:
				break
			var line := PackedVector2Array()
			line.append(_corner(c0, w))
			var cur := c0
			while nxt >= 0:
				used[nxt] = 1
				var s2: Vector2i = segs[nxt]
				cur = s2.y if s2.x == cur else s2.x
				line.append(_corner(cur, w))
				nxt = -1
				for si4 in (at.get(cur, []) as Array):
					if used[int(si4)] == 0:
						nxt = int(si4)
						break
			if line.size() >= MIN_CHAIN:
				out.append(line)
	return out


static func _corner(c: int, w: int) -> Vector2:
	return Vector2(float(c % w), float(c / w))


static func chaikin(pts: PackedVector2Array, passes: int) -> PackedVector2Array:
	## Corner-cutting. The ENDS ARE PINNED, so a border still starts and stops
	## exactly where the cells said it did -- only the staircase between them
	## softens. A closed loop is detected and wrapped, or its seam would grow a
	## spike at the join.
	var cur := pts
	for _p in range(maxi(0, passes)):
		var n := cur.size()
		if n < 3:
			return cur
		var closed := cur[0].is_equal_approx(cur[n - 1])
		var nextp := PackedVector2Array()
		if not closed:
			nextp.append(cur[0])
		for i in range(n - 1):
			var a := cur[i]
			var b := cur[i + 1]
			nextp.append(a.lerp(b, 0.25))
			nextp.append(a.lerp(b, 0.75))
		if not closed:
			nextp.append(cur[n - 1])
		else:
			nextp.append(nextp[0])
		cur = nextp
	return cur


# =============================================================================
# THE WHOLE PIPELINE
# =============================================================================
static func border(roster: Array, state: Dictionary, part: PackedInt32Array,
		nx: int, nz: int, origin: Vector2, size: Vector2) -> Array:
	## Every line on the political map, in WORLD coordinates, each carrying the
	## two provinces it divides and how firmly it is held.
	var side_ids := sides(roster, state)
	var bag := walls(part, nx, nz, side_ids)
	var out: Array = []
	## ⚠ Sorting the BAG's keys sorted "ia|ib" -- roster INDICES rendered as
	## strings, so "10|3" came before "2|5". Deterministic, but an order no
	## reader could predict and one that says nothing. The rows are sorted by
	## REGION NAME at the end instead, which is a property of the const roster
	## and cannot be reshuffled by which corner of the map the march reached
	## first, so a province changing hands never restacks which border is drawn
	## over which.
	var keys: Array = bag.keys()
	for k in keys:
		var bits := String(k).split("|")
		var ia := int(bits[0])
		var ib := int(bits[1])
		if ia >= roster.size() or ib >= roster.size():
			continue
		var na := String((roster[ia] as Dictionary).get("name", ""))
		var nb := String((roster[ib] as Dictionary).get("name", ""))
		## `walls` has already refused every pair with an unheld side, so both
		## names are in the state here. Asserted, not assumed: a default of
		## "frayed" for a region nobody has heard of is the exact fallback that
		## drew the coastline as a war.
		if not (state.has(na) and state.has(nb)):
			continue
		var firm := firmness(state, na, nb)
		for line in chains(bag[k] as Array, nx):
			var sm := chaikin(line as PackedVector2Array, SMOOTH_PASSES)
			var wl := PackedVector2Array()
			for p: Vector2 in sm:
				wl.append(cell_to_world(p.x, p.y, nx, nz, origin, size))
			out.append({
				"pts": wl, "a": na, "b": nb, "firm": firm,
				"held_a": side_ids[ia], "held_b": side_ids[ib],
			})
	out.sort_custom(func(x, y):
		var xa := String((x as Dictionary)["a"])
		var ya := String((y as Dictionary)["a"])
		if xa != ya:
			return xa < ya
		return String((x as Dictionary)["b"]) < String((y as Dictionary)["b"]))
	return out


static func tint_image(part: PackedInt32Array, nx: int, nz: int,
		side_ids: PackedStringArray) -> Image:
	## The territory as ONE texture instead of 25 350 rectangles. Stretched over
	## the bake it reads as a wash of colour rather than a grid, and it costs a
	## single draw call at any zoom.
	var img := Image.create_empty(maxi(nx, 1), maxi(nz, 1), false, Image.FORMAT_RGBA8)
	if part.size() < nx * nz:
		return img
	var cache := {}
	for j in range(nz):
		var row := j * nx
		for i in range(nx):
			var r := part[row + i]
			var s := side_ids[r] if r < side_ids.size() else NONE
			var col: Color = cache.get(s, Color(0, 0, 0, 0))
			if not cache.has(s):
				col = colour_of(s)
				col.a = FILL_ALPHA if col.a > 0.0 else 0.0
				cache[s] = col
			img.set_pixel(i, j, col)
	return img


# =============================================================================
# READOUT
# =============================================================================
static func hold_line(state: Dictionary, region: String) -> String:
	## What the hover line says about whose ground this is. A READOUT THAT
	## PRINTS A SIGN BY HAND BREAKS ON THE FIRST NEGATIVE VALUE, so the margin
	## goes through a plain percentage and the WORD carries the judgement.
	if region.is_empty() or not state.has(region):
		return ""
	var h := Factions.holder_of(state, region)
	var m := Factions.margin_of(state, region)
	if h == Factions.CONTESTED:
		return "%s — contested" % Factions.pretty(region)
	var word := "held"
	if m < FIRM_MARGIN:
		word = "held, barely"
	return "%s — %s by %s (%.0f%%)" % [Factions.pretty(region), word, _who(h), m * 100.0]


static func _who(side: String) -> String:
	## NAMES THE GAME SAYS OUT LOUD ARE NOT DATA: `Factions` stores "goblins"
	## and a sentence wants "the goblins".
	match side:
		Factions.MEN:
			return "men"
		Factions.GOBLINS:
			return "goblins"
		Factions.WOLVES:
			return "wolves"
		Factions.WILD:
			return "nothing that answers"
	return side
