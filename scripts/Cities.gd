extends Node3D
class_name Cities
## Cities — the big six, BUILT.
##
## Fifty-one places sit on the roster as dots; the crofts put households on the
## roads between them; nothing has ever put a TOWN at one. This file does, for
## the six Lemon named: Portland (the hub), Bangor, Lewiston-Auburn, Augusta,
## Brunswick and Presque Isle.
##
## The rules it will not break — the same house architecture as Crofts:
##
##   1. THE LAYOUT IS A PURE FUNCTION.  `layout(name, tier, centre, road_dirs,
##      seed, ground, water)` reads nothing but its arguments — no node, no
##      clock, no `self`, no roll — and returns a Dictionary. The visual half
##      (`_stage`) is a dumb reader of that Dictionary and decides nothing.
##   2. DETERMINISTIC AND ORDER-INDEPENDENT.  Every choice is hashed off
##      `world_seed` and the city's NAME; the roster is sorted by name before
##      anything is built, so a row list handed over in a different order —
##      or a roster that grew a fort — builds the same six cities.
##   3. NOTHING IS A SCENE NODE UNTIL YOU ARE WITHIN `STAGE_RADIUS`.  A city is
##      a Dictionary until you walk up to it, and it is struck again when you
##      leave, so walking away and back cannot desynchronise one.
##   4. NOT SERIALISED.  A city is a function of the roster, the road net and
##      the heightfield, all of which a save already restores. `fingerprint()`
##      is the honest substitute for anyone who cached an answer.
##   5. THE ROSTER IS THE WORLD'S, NOT THIS FILE'S.  `BUILTIN_ROSTER` is an
##      ESTIMATE of where the six sit on the 7.2 × 10.8 km Maine bake, mapped
##      from real latitude/longitude. It is the fallback for a world that has
##      no roster bound. The moment `bind_world` finds the real `places` rows,
##      those positions win BY NAME and the estimate is never consulted —
##      `roster_source` says which one you are looking at.
##
## Collaborators are all duck-typed (`Object`), for the reason Crofts and the
## Incident Director give: this file has to parse inside a stripped test
## project with no RoadNet.gd, no GrassSystem, no DayNight in it. Null is the
## normal case for every one of them and the file degrades honestly:
##   - no road net    → gates at the compass points instead of on the roads
##   - no heightfield → a flat city at y = 0 (and every lot passes the slope test)
##   - no water map   → nothing is wet
##   - no grass       → nothing is mown
##   - no sky         → lamps stay unlit
##
## No key handling. `CityTests._t_no_input` reads this source and asserts it.

## ----------------------------------------------------------- the roster ---

## Tier decides everything about size. 3 = the hub, 2 = a market city,
## 1 = a walled town. Only names in this table become cities; the other
## forty-five places stay as they are.
const CITY_TIERS := {
	"Portland": 3,
	"Bangor": 2,
	"Lewiston-Auburn": 2,
	"Augusta": 2,
	"Brunswick": 1,
	"Presque Isle": 1,
}

## Real Maine place names + fantasy epithets, per the 2026-08-21 map spec.
const EPITHETS := {
	"Portland": "the Beacon Coast",
	"Bangor": "Gate of the North",
	"Lewiston-Auburn": "the Twin Mills",
	"Augusta": "the Seat",
	"Brunswick": "the Falls Market",
	"Presque Isle": "the Shelf Town",
}

## A roster may carry the twin cities under either half of the name.
const ALIASES := {
	"Lewiston": "Lewiston-Auburn",
	"Auburn": "Lewiston-Auburn",
	"Lewiston Auburn": "Lewiston-Auburn",
	"Lewiston/Auburn": "Lewiston-Auburn",
	"Presque-Isle": "Presque Isle",
}

## World extent of the Maine bake (metres). x runs east, z runs SOUTH
## (Godot's −z is north).
##
## The bake's origin is Lewiston-Auburn, not the centre of the map.
## maine_meta.json puts its bounds at x −1525.71…5674.29,
## z −8160…2640. The first estimate assumed a centred box and every city came
## out ~4.2 km from the place it was named after.
const WORLD_W := 7200.0
const WORLD_H := 10800.0
const WORLD_X0 := -1525.71      ## west edge of the bake
const WORLD_Z0 := -8160.0       ## north edge of the bake

## ESTIMATED positions — see rule 5. Real lat/lon of each city mapped
## linearly into Maine's bounding box (lon −71.08…−66.95, lat 43.06…47.46)
## and then into the bake's real bounds above. Within ~115 m of the bake's own
## rows; overridden by name the moment a roster is bound.
const BUILTIN_ROSTER := {
	"Portland": Vector2(-85.7, 1056.0),
	"Lewiston-Auburn": Vector2.ZERO,
	"Bangor": Vector2(2468.6, -1680.0),
	"Augusta": Vector2(754.3, -504.0),
	"Brunswick": Vector2(411.4, 432.0),
	"Presque Isle": Vector2(3754.3, -6192.0),
}

## ---------------------------------------------------------- the numbers ---

## Indexed by tier (index 0 unused).
const CORE_R := [0.0, 85.0, 130.0, 190.0]        ## wall radius, nominal
const HOUSE_CAP := [0, 44, 120, 260]              ## most houses a tier gets
const HOUSE_MIN := [0, 20, 55, 120]               ## fewer than this is a defect
const SQUARE_R := [0.0, 14.0, 20.0, 28.0]         ## the market square
const WALL_KIND := ["", "palisade", "stone", "stone"]
## Name-keyed dialect. Default is the walled medieval ring-town; Portland is
## the 19th-century waterfront (RDR2 Saint Denis, not a curtain-wall hub).
const STYLE := {
	"Portland": "old_port",
}
const STALLS := [0, 4, 6, 8]
const QUAY_H := 2.1                               ## granite seawall, not a 7.5 m curtain
const QUAY_T := 2.4

const WALL_VERTS_BASE := 10                       ## + 2 per tier
const WALL_JITTER := 0.28                         ## radial ±, fraction of R
const WALL_H := [0.0, 3.6, 6.0, 7.5]
const WALL_T := [0.0, 0.45, 2.2, 2.6]
const GATE_W := 7.0
const TOWER_W := 4.0
const STREET_W := 6.0
## Ring streets follow the wall's own shape, scaled: one per fraction here.
const RINGS := [[], [0.5], [0.36, 0.7], [0.28, 0.52, 0.76]]
const MAX_BLOCK := 62.0                           ## a longer outer-ring arc gets a minor radial
const LOT_GAP := 1.5                              ## between footprints
const LOT_PITCH_GAP := 2.0                        ## walk: previous width + this
const LOT_SETBACK := 0.8                          ## from the kerb
const SLOPE_MAX := 3.0                            ## metres across a footprint
const LAMP_STEP := 30.0
const LAMP_CAP := 28
const MIN_GATES := 2
const GATE_MERGE_DEG := 30.0

const STAGE_RADIUS := 700.0                       ## build when the player is this close
const STRIKE_RADIUS := 850.0                      ## strike when this far (hysteresis)
const TICK := 0.5                                 ## seconds between distance checks
const MOW_PAD := 8.0                              ## mown ring past the wall

## --- the site's own heightfield (2026-09-13) -------------------------------
## `layout()` samples the ground ONCE, over the city's own square, and keeps
## the answers in the layout. Staging stays a dumb reader (rule 1): a builder
## asks `local_y()` rather than holding a ground probe of its own, so a staged
## city can never disagree with the layout it came from.
const SITE_STEP := 8.0                            ## metres between site samples
const SITE_PAD := 24.0                            ## sampled past the wall's widest vertex
const CONFORM_SPAN := 8.0                         ## longest wall/street piece laid at one height

## Lamps burn from a little before nightfall to a little after dawn —
## DayNight's DAWN_HOUR is 6.0 and NIGHTFALL_HOUR 20.6.
const LAMP_ON_HOUR := 19.5
const LAMP_OFF_HOUR := 6.5

## ---------------------------------------------------------------- state ---

var world_seed: int = 0
var roster_source := "none"          ## "world" | "builtin" | "none"
var cities: Dictionary = {}          ## name → layout Dictionary
var _rows: Dictionary = {}           ## name → Vector2 (world x, z) from the roster
var _road_dirs: Dictionary = {}      ## name → Array[Vector2] injected or read off the net
var _raw_names: Dictionary = {}      ## canonical name → the spelling the roster used
var _net_names: Dictionary = {}      ## canonical name → the spelling the ROAD NET answers to
var _staged: Dictionary = {}         ## name → Node3D
var _town_rects: Array = []          ## Rect2 per staged city, world XZ — see _claim_ground
var _lit := false
var _acc := 0.0
var hour_override := -1.0            ## ≥ 0 pins the lamp clock (tests, the sky menu); < 0 reads the sky

var _net: Object = null
var _ground_fn := Callable()
var _water_fn := Callable()
var _grass: Object = null
var _sky: Object = null

static var _mats: Dictionary = {}    ## one material per kind, shared by every city


## ============================================================ binding ===

## Boot from World: idempotent, returns the live Cities node.
static func boot(world: Node) -> Cities:
	var existing := world.get_node_or_null("Cities")
	if existing != null and existing is Cities:
		return existing as Cities
	var c := Cities.new()
	c.name = "Cities"
	world.add_child(c)
	c.bind_world(world)
	c.build()
	return c


## Read every collaborator off the world, duck-typed. Anything missing is
## left null and the file degrades as the header says.
func bind_world(world: Object) -> void:
	if world == null:
		return
	if world.get("world_seed") != null:
		world_seed = int(world.get("world_seed"))
	# --- the road net (World.roadnet(), else the "roads" group) ---
	var net: Object = null
	if world.has_method("roadnet"):
		net = world.call("roadnet")
	if net == null and world is Node and (world as Node).is_inside_tree():
		var tree := (world as Node).get_tree()
		if tree != null:
			var roads := tree.get_nodes_in_group("roads")
			if roads.size() > 0:
				net = roads[0]
	set_roadnet(net)
	# --- the roster: World.places(), World.places, or the Chronicle's ---
	var rows: Variant = null
	if world.has_method("places"):
		rows = world.call("places")
	if rows == null:
		rows = world.get("places")
	if rows == null and world.has_method("chronicle"):
		var ch: Object = world.call("chronicle")
		if ch != null:
			rows = ch.get("places")
	if rows == null:
		## World keeps the bake under a private `_terrain` and never re-exports
		## `places()` itself — before 2026-09-13 that dropped every city onto
		## the builtin estimate, 4.2 km from the place it was named after.
		var terr_r: Object = _terrain_of(world)
		if terr_r != null and terr_r.has_method("places"):
			rows = terr_r.call("places")
	if rows is Array and (rows as Array).size() > 0:
		set_roster(rows as Array)
	elif rows is Dictionary and (rows as Dictionary).size() > 0:
		set_roster((rows as Dictionary).values())
	else:
		set_roster([])
	# --- the heightfield and the water map ---
	##
	## 2026-09-13 — THE UNDERGROUND TOWNS. None of the four (x, z) names below
	## exist on World: it spells its probe `_surface_y(Vector3)` and hands the
	## heightfield itself out to nobody. So `_ground_fn` stayed invalid, every
	## city was laid out flat at y = 0, and the six stood buried under their
	## own benches — Presque Isle by 108 m. Both Vector3 spellings and the
	## terrain node's own samplers are tried now, in that order.
	_ground_fn = Callable()
	_water_fn = Callable()
	var terr: Object = _terrain_of(world)
	for m in ["ground_height", "height_at", "terrain_height", "ground_y"]:
		if world.has_method(m):
			_ground_fn = Callable(world, m)
			break
	if not _ground_fn.is_valid():
		for m in ["_surface_y", "surface_y"]:
			if world.has_method(m):
				var w: Object = world
				var mm: String = m
				_ground_fn = func(x: float, z: float) -> float:
					return float(w.call(mm, Vector3(x, 0.0, z)))
				break
	if not _ground_fn.is_valid() and terr != null and terr.has_method("sample_height"):
		var th: Object = terr
		_ground_fn = func(x: float, z: float) -> float:
			return float(th.call("sample_height", x, z))
	for m in ["is_water", "water_at", "in_water"]:
		if world.has_method(m):
			_water_fn = Callable(world, m)
			break
	if not _water_fn.is_valid() and terr != null and terr.has_method("is_water_at"):
		## NOT the raw water map: the bake keeps sea cells BURIED under
		## Portland's and Freeport's town pads, and `is_water_at` is the
		## facade that only calls it water where the surface stands over
		## the bed. Sampling the raw map drowns a third of the hub.
		var tw: Object = terr
		_water_fn = func(x: float, z: float) -> bool:
			return bool(tw.call("is_water_at", Vector3(x, 0.0, z)))
	# --- grass, for the mow ---
	if world.has_method("grass"):
		_grass = world.call("grass")
	if _grass == null:
		_grass = world.get("_grass")
	if _grass != null and not _grass.has_method("cut_at"):
		_grass = null
	# --- the sky, for the lamps ---
	if world.has_method("daynight"):
		_sky = world.call("daynight")
	if _sky == null:
		_sky = world.get("_daynight")
	if _sky != null and _sky.get("hour") == null:
		_sky = null


## The ground node, by whichever name the world keeps it under. A world that
## answers none of these is a flat, dry world, which is the normal case in the
## headless suite.
static func _terrain_of(world: Object) -> Object:
	if world == null:
		return null
	for m in ["terrain", "overworld", "ground_node"]:
		if world.has_method(m):
			var t: Variant = world.call(m)
			if t is Object and t != null:
				return t as Object
	for prop in ["_terrain", "terrain", "_overworld"]:
		var v: Variant = world.get(prop)
		if v is Object and v != null:
			return v as Object
	return null


## Rows are the bake's `places` records: {name, pos:[x,z], y, rank}. A Vector2
## or Vector3 `pos` is accepted too. Only names in CITY_TIERS (after ALIASES)
## become cities; everything else is ignored. An empty roster falls back to
## the builtin estimate.
func set_roster(rows: Array) -> void:
	_rows.clear()
	_raw_names.clear()
	_net_names.clear()
	for r in rows:
		if not (r is Dictionary):
			continue
		var row := r as Dictionary
		var nm := canonical_name(str(row.get("name", "")))
		if nm == "":
			continue
		var p: Variant = _pos_of(row.get("pos"))
		if p == null:
			continue
		_rows[nm] = p
		_raw_names[nm] = str(row.get("name", nm))
	if _rows.size() > 0:
		roster_source = "world"
	else:
		for k in BUILTIN_ROSTER.keys():
			_rows[k] = BUILTIN_ROSTER[k]
		roster_source = "builtin"


## The roster may say "Lewiston"; the tier table says "Lewiston-Auburn".
static func canonical_name(raw: String) -> String:
	## The bake writes "Lewiston–Auburn" with an EN DASH; the tier table says
	## "Lewiston-Auburn". Every dash is a hyphen here (2026-09-12: the sixth
	## city was missing from the live world for exactly this).
	var s := raw.strip_edges().replace("–", "-").replace("—", "-").replace("‐", "-")
	if ALIASES.has(s):
		s = ALIASES[s]
	if CITY_TIERS.has(s):
		return s
	# case-insensitive last chance
	var low := s.to_lower()
	for k in CITY_TIERS.keys():
		if (k as String).to_lower() == low:
			return k
	for k in ALIASES.keys():
		if (k as String).to_lower() == low:
			return ALIASES[k]
	return ""


static func _pos_of(v: Variant) -> Variant:
	if v is Vector2:
		return v
	if v is Vector3:
		return Vector2((v as Vector3).x, (v as Vector3).z)
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float((v as Array)[0]), float((v as Array)[1]))
	return null


## A road net is kept only if it answers the two questions this file asks;
## a collaborator that is the wrong kind of object is worse than none.
func set_roadnet(net: Object) -> void:
	_net = null
	if net == null:
		return
	if net.has_method("edges_from") and net.has_method("place_pos"):
		_net = net


## The name the ROAD NET knows this city by. The tier table says
## "Lewiston-Auburn"; the bake writes "Lewiston–Auburn" with an EN DASH, and
## the net is built from the bake, so asking it under the canonical spelling
## got an empty edge list and the Twin Mills stood with two default gates
## facing nothing (2026-09-13, the same en-dash trap as the missing sixth
## city). Tries the canonical name, the roster's own spelling, then the dash
## variants, and keeps whichever the net answers to.
func net_name_for(city: String) -> String:
	if _net_names.has(city):
		return _net_names[city]
	var found := city
	if _net != null:
		var tries: Array = [city]
		if _raw_names.has(city) and not tries.has(_raw_names[city]):
			tries.append(_raw_names[city])
		for dash in ["–", "—"]:
			var alt := city.replace("-", dash)
			if not tries.has(alt):
				tries.append(alt)
		for t in tries:
			var e: Variant = _net.call("edges_from", t)
			var n := 0
			if e is PackedInt32Array:
				n = (e as PackedInt32Array).size()
			elif e is Array:
				n = (e as Array).size()
			if n > 0:
				found = t
				break
	_net_names[city] = found
	return found


## Direct injection, for tests and for a world with no net: unit Vector2s
## (x, z) pointing OUT of the city along each road.
func set_road_dirs(city: String, dirs: Array) -> void:
	var out: Array = []
	for d in dirs:
		if d is Vector2 and (d as Vector2).length() > 0.001:
			out.append((d as Vector2).normalized())
	_road_dirs[city] = out


func set_ground(height_fn: Callable, water_fn: Callable) -> void:
	_ground_fn = height_fn
	_water_fn = water_fn


func set_grass(grass: Object) -> void:
	_grass = grass if (grass != null and grass.has_method("cut_at")) else null


func set_sky(sky: Object) -> void:
	_sky = sky if (sky != null and sky.get("hour") != null) else null


## ============================================================= building ===

## Lay out every city on the roster. Pure per city; sorted by name so the
## result cannot depend on roster order.
func build() -> void:
	cities.clear()
	var names: Array = _rows.keys()
	names.sort()
	for nm in names:
		var tier: int = CITY_TIERS[nm]
		var centre: Vector2 = _rows[nm]
		var dirs := road_dirs_for(nm)
		cities[nm] = layout(nm, tier, centre, dirs, world_seed, _ground_fn, _water_fn)
	# a rebuild must not leave stale geometry standing
	for nm in _staged.keys().duplicate():
		strike(nm)


## Rebuild for a roster that changed under us (a fort founded, a net rebuilt).
func rebuild() -> void:
	build()


## Where the roads leave this city: injected dirs win, then the net, then
## nothing (and `layout` puts gates at the compass points).
func road_dirs_for(city: String) -> Array:
	if _road_dirs.has(city):
		return _road_dirs[city]
	var out: Array = []
	if _net == null or not _rows.has(city):
		return out
	var here: Vector2 = _rows[city]
	var key := net_name_for(city)
	var edges: Variant = _net.call("edges_from", key)
	## RoadNet.edges_from answers a PackedInt32Array of EDGE IDS, resolved
	## through RoadNet.edge(id); a net that hands the records straight back is
	## accepted too. (2026-09-12: the id form is the real one, and it used to
	## fall through this `is Array` test and leave every city with the two
	## default gates.)
	var recs: Array = []
	if edges is PackedInt32Array:
		for id in edges:
			recs.append(int(id))
	elif edges is Array:
		recs = edges as Array
	else:
		return out
	for e0 in recs:
		var e: Variant = e0
		if (e is int) and _net.has_method("edge"):
			e = _net.call("edge", int(e))
		var far: Variant = _edge_far_end(e, key, here)
		if far == null:
			continue
		var d: Vector2 = (far as Vector2) - here
		if d.length() > 1.0:
			out.append(d.normalized())
	return out


## The net's edge record shape is not this file's to know. Try the honest
## candidates: a Dictionary or Object with two place names (a/b, from/to),
## or a polyline (pts/points/polyline) whose far end is the one away from us.
func _edge_far_end(e: Variant, city: String, here: Vector2) -> Variant:
	var other := ""
	var pts: Variant = null
	if e is Dictionary:
		var d := e as Dictionary
		## Names first: RoadNet's record carries `from`/`to` as place names and
		## `a`/`b` as NODE INDICES, and an index is not a name.
		for pair in [["from", "to"], ["a", "b"], ["u", "v"]]:
			if d.has(pair[0]) and d.has(pair[1]) and (d[pair[0]] is String) and (d[pair[1]] is String):
				other = str(d[pair[1]]) if str(d[pair[0]]) == city else str(d[pair[0]])
				break
		for k in ["pts", "points", "polyline", "path", "poly"]:
			if d.has(k):
				pts = d[k]
				break
	elif e is Object:
		var o := e as Object
		for pair in [["from", "to"], ["a", "b"], ["u", "v"]]:
			var pa: Variant = o.get(pair[0])
			var pb: Variant = o.get(pair[1])
			if pa is String and pb is String:
				other = str(pb) if str(pa) == city else str(pa)
				break
		for k in ["pts", "points", "polyline", "path", "poly"]:
			var v: Variant = o.get(k)
			if v != null:
				pts = v
				break
	if other != "" and other != city:
		var p: Variant = _net.call("place_pos", other)
		var pv: Variant = _pos_of(p)
		# a net answers an unknown name with SOMETHING (often the origin);
		# a far end on top of us is not a far end, so fall through to the polyline
		if pv != null and (pv as Vector2).distance_to(here) > 1.0:
			return pv
	if pts != null and pts is Array and (pts as Array).size() >= 2:
		var a: Variant = _pos_of((pts as Array)[0])
		var b: Variant = _pos_of((pts as Array)[(pts as Array).size() - 1])
		if a != null and b != null:
			return b if (a as Vector2).distance_to(here) < (b as Vector2).distance_to(here) else a
	if pts != null and pts is PackedVector2Array and (pts as PackedVector2Array).size() >= 2:
		var pa2 := (pts as PackedVector2Array)[0]
		var pb2 := (pts as PackedVector2Array)[(pts as PackedVector2Array).size() - 1]
		return pb2 if pa2.distance_to(here) < pb2.distance_to(here) else pa2
	return null


## ------------------------------------------------------------- hashing ---

## One deterministic number in [0, 1) per (seed, name, key). No RNG anywhere
## in this file — `CityTests._t_no_input` scans for one.
static func _h(wseed: int, city: String, k: int) -> float:
	# String.hash() is djb2 and clusters on sequential keys; finish it the
	# murmur way so consecutive k spread across the range.
	var v: int = hash("%d|%s|%d" % [wseed, city, k])
	v = (v ^ (v >> 33)) * -49064778989728563
	v = (v ^ (v >> 33)) * -4265267296055464877
	v = v ^ (v >> 33)
	return float(absi(v) % 100003) / 100003.0


## ============================================================== layout ===

static func style_of(city: String) -> String:
	return str(STYLE.get(city, "walled"))


## THE PURE FUNCTION. Everything observable about a city comes out of here.
##
##   name      canonical city name (a CITY_TIERS key)
##   tier      1..3
##   centre    world (x, z) of the place
##   road_dirs unit Vector2s pointing out of the city along its roads
##   seed      world seed
##   ground    Callable(x, z) → y, or an invalid Callable for a flat world
##   water     Callable(x, z) → bool, or an invalid Callable for a dry one
##
## Returns a Dictionary; every position inside it is LOCAL to `centre`
## except `centre` itself and each lot's `y`, which is world height.


static func layout(city: String, tier: int, centre: Vector2, road_dirs: Array, wseed: int,
		ground: Callable, water: Callable) -> Dictionary:
	tier = clampi(tier, 1, 3)
	var R: float = CORE_R[tier]
	var style := style_of(city)
	var wall: PackedVector2Array
	var wall_kind: String
	var gates: Array
	var streets: Array
	var rings: Array
	var minor: Array
	var piers: Array = []
	if style == "old_port":
		wall = _harbor_polygon(city, tier, wseed)
		wall_kind = "seawall"
		gates = _gates(wall, road_dirs, city, wseed)
		streets = _harbor_streets(gates)
		rings = _harbor_runs(wall, city, wseed, tier, false)
		minor = _harbor_runs(wall, city, wseed, tier, true)
		piers = _harbor_piers(wall, city, wseed)
	else:
		wall = _wall_polygon(city, tier, wseed)
		wall_kind = WALL_KIND[tier]
		gates = _gates(wall, road_dirs, city, wseed)
		streets = _streets(wall, gates, tier, city, wseed)
		rings = _rings(wall, tier)
		minor = _minor_radials(wall, gates, tier, city, wseed)
	# every polyline a lot can front onto. Walled towns: gate streets, then
	# brick lanes, then rings. Old Port: gate streets, then cobble grid, then
	# brick lanes — so townhouses fill the thoroughfares first.
	var roads: Array = []
	roads.append_array(streets)
	if style == "old_port":
		roads.append_array(rings)
		roads.append_array(minor)
	else:
		roads.append_array(minor)
		roads.append_array(rings)
	var lots_and_rejects := _lots(city, tier, wseed, centre, wall, roads, streets.size(), ground, water)
	var lots: Array = lots_and_rejects[0]
	var rejected: Dictionary = lots_and_rejects[1]
	var lamps := _lamps(gates, streets, tier)
	var stalls := _stalls(city, tier, wseed)
	var cy := _y_at(ground, centre.x, centre.y)
	return {
		"name": city,
		"tier": tier,
		"style": style,
		"epithet": EPITHETS.get(city, ""),
		"centre": Vector3(centre.x, cy, centre.y),
		"site": _site_heights(centre, R, ground, cy),
		"core_r": R,
		"wall": wall,
		"wall_kind": wall_kind,
		"gates": gates,
		"streets": streets,
		"minor": minor,
		"rings": rings,
		"roads": roads,
		"piers": piers,
		"square_r": SQUARE_R[tier],
		"lots": lots,
		"stalls": stalls,
		"lamps": lamps,
		"rejected": rejected,
	}


## A square of LOCAL ground heights (world y minus the centre's), SITE_STEP
## apart, reaching SITE_PAD past the wall's widest possible vertex. Local, so
## a flat world is all zeroes and a staged city's node positions can use the
## numbers as they stand.
static func _site_heights(centre: Vector2, R: float, ground: Callable, cy: float) -> Dictionary:
	var reach: float = R * (1.0 + WALL_JITTER * 0.5) + SITE_PAD
	var n: int = int(ceil(reach * 2.0 / SITE_STEP)) + 1
	var h := PackedFloat32Array()
	h.resize(n * n)
	if ground.is_valid():
		for iz in range(n):
			var lz: float = -reach + float(iz) * SITE_STEP
			for ix in range(n):
				var lx: float = -reach + float(ix) * SITE_STEP
				h[iz * n + ix] = _y_at(ground, centre.x + lx, centre.y + lz) - cy
	return {"n": n, "step": SITE_STEP, "reach": reach, "h": h}


## Ground height LOCAL to the city centre at a local (x, z) — bilinear off the
## site grid, clamped at its edge, 0.0 for a flat world or an old layout with
## no grid in it. THE one question every builder asks about the ground.
static func local_y(c: Dictionary, lx: float, lz: float) -> float:
	var site: Dictionary = c.get("site", {})
	if site.is_empty():
		return 0.0
	var n: int = int(site.get("n", 0))
	if n < 2:
		return 0.0
	var step: float = float(site["step"])
	var reach: float = float(site["reach"])
	var h: PackedFloat32Array = site["h"]
	if h.size() < n * n:
		return 0.0
	var fx: float = clampf((lx + reach) / step, 0.0, float(n - 1))
	var fz: float = clampf((lz + reach) / step, 0.0, float(n - 1))
	var ix: int = mini(int(floor(fx)), n - 2)
	var iz: int = mini(int(floor(fz)), n - 2)
	var tx: float = fx - float(ix)
	var tz: float = fz - float(iz)
	var a: float = h[iz * n + ix]
	var b: float = h[iz * n + ix + 1]
	var d0: float = h[(iz + 1) * n + ix]
	var d1: float = h[(iz + 1) * n + ix + 1]
	return lerpf(lerpf(a, b, tx), lerpf(d0, d1, tx), tz)


static func _y_at(ground: Callable, x: float, z: float) -> float:
	if not ground.is_valid():
		return 0.0
	var v: Variant = ground.call(x, z)
	return float(v) if (v is float or v is int) else 0.0


static func _wet_at(water: Callable, x: float, z: float) -> bool:
	if not water.is_valid():
		return false
	var v: Variant = water.call(x, z)
	return bool(v)


## An irregular closed polygon, star-shaped about the origin: n vertices at
## roughly even angles, each pushed in or out by a hashed fraction of R.
static func _wall_polygon(city: String, tier: int, wseed: int) -> PackedVector2Array:
	var R: float = CORE_R[tier]
	var n := WALL_VERTS_BASE + 2 * tier
	var out := PackedVector2Array()
	var step := TAU / float(n)
	for i in range(n):
		var ang := step * float(i) + (_h(wseed, city, 100 + i) - 0.5) * step * 0.5
		var r := R * (1.0 - WALL_JITTER * 0.5 + WALL_JITTER * _h(wseed, city, 200 + i))
		out.append(Vector2(cos(ang), sin(ang)) * r)
	return out


## Orthogonal-ish city pad: a hashed rectangle in polar form, flattened on
## the east/SE (Casco) face so the quay reads as a run of granite, not a
## curtain. Vertices stay inside CORE_R so the town pad is never overflowed.
static func _harbor_polygon(city: String, tier: int, wseed: int) -> PackedVector2Array:
	var R: float = CORE_R[tier]
	var n := WALL_VERTS_BASE + 2 * tier
	var wx := R * (0.78 + 0.10 * _h(wseed, city, 80))
	var wz := R * (0.74 + 0.12 * _h(wseed, city, 81))
	var out := PackedVector2Array()
	var step := TAU / float(n)
	for i in range(n):
		var ang := step * float(i)
		var c := cos(ang)
		var s := sin(ang)
		var r_rect: float
		if absf(c) < 0.0001:
			r_rect = wz
		elif absf(s) < 0.0001:
			r_rect = wx
		else:
			r_rect = minf(wx / absf(c), wz / absf(s))
		var jitter := 0.08 * (_h(wseed, city, 200 + i) - 0.5)
		if c > 0.35:
			jitter *= 0.2
		var r := minf(r_rect * (1.0 + jitter), R * 0.98)
		out.append(Vector2(c, s) * r)
	return out


## Gate streets on an Old Port grid: an orthogonal dogleg into the square,
## not a hashed radial bend.
static func _harbor_streets(gates: Array) -> Array:
	var out: Array = []
	for g in gates:
		var gp: Vector2 = g["pos"]
		var mid: Vector2
		if absf(gp.x) < 10.0 or absf(gp.y) < 10.0:
			mid = gp * 0.5
		elif absf(gp.x) >= absf(gp.y):
			mid = Vector2(0.0, gp.y)
		else:
			mid = Vector2(gp.x, 0.0)
		out.append(PackedVector2Array([gp, mid, Vector2.ZERO]))
	return out


## Axis-aligned runs clipped to the harbor polygon. Thoroughfares (`lane` =
## false) sit on the cobble grid; lanes fill the half-offsets as brick.
static func _harbor_runs(wall: PackedVector2Array, city: String, wseed: int, tier: int, lane: bool) -> Array:
	var out: Array = []
	var sq: float = SQUARE_R[tier]
	var skip := sq + STREET_W + 6.0
	var pitch := 48.0 + 10.0 * _h(wseed, city, 811 if lane else 810)
	var reach := 0.0
	for v in wall:
		reach = maxf(reach, maxf(absf(v.x), absf(v.y)))
	reach += 8.0
	var offsets: Array = []
	var max_k := maxi(1, int(floorf(reach / pitch)))
	if lane:
		for k in range(0, max_k + 1):
			var o := (float(k) + 0.5) * pitch
			if o < skip or o >= reach:
				continue
			offsets.append(o)
			offsets.append(-o)
	else:
		for k in range(1, max_k + 1):
			var o := float(k) * pitch
			if o < skip or o >= reach:
				continue
			offsets.append(o)
			offsets.append(-o)
	for off in offsets:
		var o := float(off)
		for along_x in [true, false]:
			var a := Vector2(-reach, o) if along_x else Vector2(o, -reach)
			var b := Vector2(reach, o) if along_x else Vector2(o, reach)
			var clipped: Array = Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a, b]), wall)
			for bit in clipped:
				if not (bit is PackedVector2Array):
					continue
				var pl: PackedVector2Array = bit
				if pl.size() >= 2 and pl[0].distance_to(pl[pl.size() - 1]) > 24.0:
					out.append(pl)
	return out


## A few wharves on the Casco face, extending east of the quay. House lots
## still reject water; these boxes are allowed to overhang wet cells.
static func _harbor_piers(wall: PackedVector2Array, city: String, wseed: int) -> Array:
	var east: Array = []
	for v in wall:
		if v.x > 0.0:
			east.append(v)
	if east.size() < 2:
		return []
	east.sort_custom(func(a, b): return (a as Vector2).y < (b as Vector2).y)
	var n := 3 + int(_h(wseed, city, 900) * 2.0)
	n = clampi(n, 3, mini(5, east.size()))
	var out: Array = []
	for i in range(n):
		var t := (float(i) + 0.55) / float(n + 1)
		var idx := clampi(int(t * float(east.size() - 1)), 0, east.size() - 1)
		var root_p: Vector2 = east[idx]
		var length := 16.0 + 14.0 * _h(wseed, city, 910 + i)
		var width := 5.0 + 3.5 * _h(wseed, city, 930 + i)
		out.append({
			"root": root_p,
			"pos": root_p + Vector2(length * 0.5, 0.0),
			"length": length,
			"width": width,
		})
	return out


## Where a ray from the origin at `dir` leaves the polygon.
static func poly_hit(poly: PackedVector2Array, dir: Vector2) -> Vector2:
	var far := dir.normalized() * 100000.0
	var best := far
	var best_d := INF
	var n := poly.size()
	for i in range(n):
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var hit: Variant = Geometry2D.segment_intersects_segment(Vector2.ZERO, far, a, b)
		if hit != null:
			var d := (hit as Vector2).length()
			if d < best_d:
				best_d = d
				best = hit
	return best


static func dist_to_poly(poly: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	var n := poly.size()
	for i in range(n):
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % n])
		best = minf(best, q.distance_to(p))
	return best


static func dist_to_polyline(pl: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	for i in range(pl.size() - 1):
		var q := Geometry2D.get_closest_point_to_segment(p, pl[i], pl[i + 1])
		best = minf(best, q.distance_to(p))
	return best


## One gate per road, on the wall where the road's bearing crosses it; roads
## closer than GATE_MERGE_DEG share one. Fewer than MIN_GATES roads → the
## missing gates go opposite the ones there are (or at north and south).
static func _gates(wall: PackedVector2Array, road_dirs: Array, city: String, wseed: int) -> Array:
	var dirs: Array = []
	for d in road_dirs:
		if not (d is Vector2):
			continue
		var v := (d as Vector2).normalized()
		var dup := false
		for e in dirs:
			if absf(rad_to_deg((e as Vector2).angle_to(v))) < GATE_MERGE_DEG:
				dup = true
				break
		if not dup:
			dirs.append(v)
	if dirs.size() == 0:
		var a := (_h(wseed, city, 300) - 0.5) * 0.6
		dirs.append(Vector2(sin(a), -cos(a)))           # roughly north
	while dirs.size() < MIN_GATES:
		var base: Vector2 = dirs[0]
		var opp := -base
		var ok := true
		for e in dirs:
			if absf(rad_to_deg((e as Vector2).angle_to(opp))) < GATE_MERGE_DEG:
				ok = false
		if not ok:
			opp = base.rotated(PI * 0.5)
		dirs.append(opp.normalized())
	var out: Array = []
	for d in dirs:
		out.append({"pos": poly_hit(wall, d), "dir": d})
	return out


## Radial streets from every gate to the square, one hashed bend each so
## nothing is razor-straight.
static func _streets(_wall: PackedVector2Array, gates: Array, tier: int, city: String, wseed: int) -> Array:
	var out: Array = []
	var R: float = CORE_R[tier]
	var i := 0
	for g in gates:
		var gp: Vector2 = g["pos"]
		var mid := gp * 0.5
		var nrm := Vector2(-gp.y, gp.x).normalized()
		mid += nrm * (_h(wseed, city, 400 + i) - 0.5) * R * 0.12
		var pl := PackedVector2Array([gp, mid, Vector2.ZERO])
		out.append(pl)
		i += 1
	return out


## Ring streets: the wall polygon scaled in, one per RINGS fraction, closed
## (last point == first). Scaling the wall rather than drawing circles keeps
## every ring the same distance in from the wall all the way round.
static func _rings(wall: PackedVector2Array, tier: int) -> Array:
	var out: Array = []
	for f in RINGS[tier]:
		var ring := PackedVector2Array()
		for v in wall:
			ring.append(v * float(f))
		ring.append(wall[0] * float(f))
		out.append(ring)
	return out


## Where two neighbouring gate streets leave a long arc of outer ring
## between them, cut it with a minor radial from the outer ring to the
## innermost one — never to the square, so the spokes do not pile up
## there. Tier 1 has one ring and gets none.
static func _minor_radials(wall: PackedVector2Array, gates: Array, tier: int, city: String, wseed: int) -> Array:
	var out: Array = []
	var fr: Array = RINGS[tier]
	if fr.size() < 2:
		return out
	var f_out := float(fr[fr.size() - 1])
	var f_in := float(fr[0])
	var angs: Array = []
	for g in gates:
		angs.append(fposmod((g["pos"] as Vector2).angle(), TAU))
	angs.sort()
	var k := 0
	for i in range(angs.size()):
		var a0 := float(angs[i])
		var a1 := float(angs[(i + 1) % angs.size()])
		if i == angs.size() - 1:
			a1 += TAU
		var span := a1 - a0
		# arc length of the outer ring across this span, roughly
		var r_out := poly_hit(wall, Vector2(cos(a0 + span * 0.5), sin(a0 + span * 0.5))).length() * f_out
		var arc := r_out * span
		var n := int(floorf(arc / MAX_BLOCK))
		for m in range(1, n + 1):
			var a := a0 + span * float(m) / float(n + 1)
			a += (_h(wseed, city, 700 + k) - 0.5) * span * 0.15 / float(n + 1)
			var dir := Vector2(cos(a), sin(a))
			var p_out := poly_hit(wall, dir) * f_out
			var p_in := poly_hit(wall, dir) * f_in
			out.append(PackedVector2Array([p_out, p_in]))
			k += 1
	return out


## Walk every street on both sides and drop a footprint wherever one fits.
## Returns [lots, rejected]. A lot is rejected — and COUNTED — for being
## outside the wall, in the square, over a street, on another lot, on
## water, or across a slope; the counts are what the suite reads.
static func _lots(city: String, tier: int, wseed: int, centre: Vector2, wall: PackedVector2Array,
		polylines: Array, _n_gate_streets: int, ground: Callable, water: Callable) -> Array:
	var lots: Array = []
	var rejected := {"outside": 0, "square": 0, "street": 0, "overlap": 0, "water": 0, "slope": 0, "cap": 0}
	var cap: int = HOUSE_CAP[tier]
	var sq: float = SQUARE_R[tier]
	var k := 0
	for si in range(polylines.size()):
		var pl: PackedVector2Array = polylines[si]
		var total := 0.0
		for i in range(pl.size() - 1):
			total += pl[i].distance_to(pl[i + 1])
		var s := 4.0 + _h(wseed, city, 500 + si) * 6.0
		while s < total - 4.0:
			var pt := _along(pl, s)
			var p: Vector2 = pt[0]
			var t: Vector2 = pt[1]
			var nrm := Vector2(-t.y, t.x)
			var widest := 0.0
			var old_port := style_of(city) == "old_port"
			for side: float in [-1.0, 1.0]:
				k += 1
				var w: float
				var d: float
				var storeys: int
				var h: float
				if old_port:
					w = 5.4 + 2.6 * _h(wseed, city, 1000 + k)
					d = 8.2 + 3.2 * _h(wseed, city, 2000 + k)
					storeys = 2 + (1 if _h(wseed, city, 3000 + k) < 0.52 else 0)
					h = 3.3 + 2.7 * float(storeys - 1) + 0.5 * _h(wseed, city, 4000 + k)
				else:
					w = 6.0 + 3.0 * _h(wseed, city, 1000 + k)
					d = 7.0 + 4.0 * _h(wseed, city, 2000 + k)
					storeys = 1 + (1 if (tier >= 2 and _h(wseed, city, 3000 + k) < 0.45) else 0)
					h = 3.2 + 1.3 * _h(wseed, city, 4000 + k) + 2.6 * float(storeys - 1)
				widest = maxf(widest, w)
				var half := 0.5 * maxf(w, d)
				var to_street: Vector2 = -nrm * side
				var c := p + nrm * side * (STREET_W * 0.5 + LOT_SETBACK + d * 0.5)
				if lots.size() >= cap:
					rejected["cap"] += 1
					continue
				if not Geometry2D.is_point_in_polygon(c, wall) or dist_to_poly(wall, c) < half + 2.5:
					rejected["outside"] += 1
					continue
				if c.length() < sq + half + 2.0:
					rejected["square"] += 1
					continue
				var over_street := false
				for sj in range(polylines.size()):
					if sj == si:
						# our own street can still cut in at a polygon corner
						if dist_to_polyline(pl, c) < STREET_W * 0.5 + LOT_SETBACK + d * 0.5 - 0.3:
							over_street = true
							break
						continue
					if dist_to_polyline(polylines[sj], c) < STREET_W * 0.5 + half:
						over_street = true
						break
				if over_street:
					rejected["street"] += 1
					continue
				var overlaps := false
				for o in lots:
					var oc: Vector2 = o["pos"]
					var os: Vector3 = o["size"]
					if oc.distance_to(c) < half + 0.5 * maxf(os.x, os.z) + LOT_GAP:
						overlaps = true
						break
				if overlaps:
					rejected["overlap"] += 1
					continue
				var wx := centre.x + c.x
				var wz := centre.y + c.y
				if _wet_at(water, wx, wz) or _wet_at(water, wx + half, wz) or _wet_at(water, wx - half, wz) \
						or _wet_at(water, wx, wz + half) or _wet_at(water, wx, wz - half):
					rejected["water"] += 1
					continue
				var ys := [_y_at(ground, wx + half, wz), _y_at(ground, wx - half, wz),
						_y_at(ground, wx, wz + half), _y_at(ground, wx, wz - half)]
				var ymin := float(ys.min())
				var ymax := float(ys.max())
				if ymax - ymin > SLOPE_MAX:
					rejected["slope"] += 1
					continue
				lots.append({
					"pos": c,
					"yaw": atan2(to_street.x, to_street.y),
					"size": Vector3(w, h, d),
					"storeys": storeys,
					"kind": "house",
					"y": _y_at(ground, wx, wz),
					"street": si,
				})
			s += widest + LOT_PITCH_GAP
	_assign_kinds(lots, tier, city, wseed)
	return [lots, rejected]


## Point and unit tangent at arclength s along a polyline.
static func _along(pl: PackedVector2Array, s: float) -> Array:
	var acc := 0.0
	for i in range(pl.size() - 1):
		var seg := pl[i + 1] - pl[i]
		var L := seg.length()
		if L <= 0.0001:
			continue
		if acc + L >= s:
			var t := (s - acc) / L
			return [pl[i] + seg * t, seg / L]
		acc += L
	var last := pl.size() - 1
	var seg2 := pl[last] - pl[maxi(last - 1, 0)]
	return [pl[last], seg2.normalized() if seg2.length() > 0.0001 else Vector2.RIGHT]


## The inn is the first lot inside the main gate. Walled towns: hall (tier
## ≥ 2) nearest the square, chapel (tier 3) the next nearest on another
## street. Old Port remaps those to a custom-house and a brick church, and
## parks warehouses on the Casco side. Kinds are labels the stage reads.
static func _assign_kinds(lots: Array, tier: int, city: String, wseed: int) -> void:
	if lots.size() == 0:
		return
	# inn: on street 0 (the main gate's), farthest from the centre
	var inn := -1
	var best := -1.0
	for i in range(lots.size()):
		if int(lots[i]["street"]) == 0 and (lots[i]["pos"] as Vector2).length() > best:
			best = (lots[i]["pos"] as Vector2).length()
			inn = i
	if inn < 0:
		inn = 0
	lots[inn]["kind"] = "inn"
	var old_port := style_of(city) == "old_port"
	if tier >= 2:
		var hall := -1
		var near := INF
		for i in range(lots.size()):
			if i == inn:
				continue
			var L := (lots[i]["pos"] as Vector2).length()
			if L < near:
				near = L
				hall = i
		if hall >= 0:
			lots[hall]["kind"] = "custom_house" if old_port else "hall"
			if tier >= 3:
				var chapel := -1
				var near2 := INF
				var hs := int(lots[hall]["street"])
				for i in range(lots.size()):
					if i == inn or i == hall or int(lots[i]["street"]) == hs:
						continue
					var L2 := (lots[i]["pos"] as Vector2).length()
					if L2 < near2:
						near2 = L2
						chapel = i
				if chapel >= 0:
					lots[chapel]["kind"] = "church" if old_port else "chapel"
	if old_port:
		var idxs: Array = []
		for i in range(lots.size()):
			if str(lots[i]["kind"]) == "house":
				idxs.append(i)
		idxs.sort_custom(func(a, b): return (lots[a]["pos"] as Vector2).x > (lots[b]["pos"] as Vector2).x)
		var n_wh := mini(4, idxs.size())
		for j in range(n_wh):
			if (lots[idxs[j]]["pos"] as Vector2).x > 16.0:
				lots[idxs[j]]["kind"] = "warehouse"
				var s: Vector3 = lots[idxs[j]]["size"]
				lots[idxs[j]]["size"] = Vector3(s.x * 1.35, s.y * 0.88, s.z * 1.55)
	_assign_look(lots, city, tier, wseed)


## Wall and roof materials live on the lot so `_stage` is a dumb reader.
static func _assign_look(lots: Array, city: String, tier: int, wseed: int) -> void:
	var old_port := style_of(city) == "old_port"
	for i in range(lots.size()):
		var kind := str(lots[i]["kind"])
		if old_port:
			match kind:
				"inn":
					lots[i]["wall_mat"] = "brick"
					lots[i]["roof_mat"] = "slate"
				"custom_house":
					lots[i]["wall_mat"] = "stone"
					lots[i]["roof_mat"] = "slate"
				"church":
					lots[i]["wall_mat"] = "brick"
					lots[i]["roof_mat"] = "slate"
				"warehouse":
					lots[i]["wall_mat"] = "brick" if _h(wseed, city, 5000 + i) < 0.6 else "stone"
					lots[i]["roof_mat"] = "cornice"
				_:
					lots[i]["wall_mat"] = "brick" if _h(wseed, city, 5000 + i) < 0.72 else "stone"
					lots[i]["roof_mat"] = "slate" if _h(wseed, city, 6000 + i) < 0.58 else "cornice"
		else:
			match kind:
				"inn":
					lots[i]["wall_mat"] = "daub"
					lots[i]["roof_mat"] = "thatch" if tier < 3 else "slate"
				"hall", "chapel":
					lots[i]["wall_mat"] = "stone"
					lots[i]["roof_mat"] = "slate"
				_:
					lots[i]["wall_mat"] = "daub" if _h(wseed, city, 5000 + i) < 0.7 else "board"
					lots[i]["roof_mat"] = "thatch" if tier < 3 or _h(wseed, city, 6000 + i) < 0.5 else "slate"


## A lamp just inside every gate, one every LAMP_STEP along each street,
## and four round the square; capped.
static func _lamps(gates: Array, streets: Array, tier: int) -> Array:
	var out: Array = []
	for g in gates:
		var gp: Vector2 = g["pos"]
		out.append(gp - (g["dir"] as Vector2) * (TOWER_W + 2.0) + Vector2(-(g["dir"] as Vector2).y, (g["dir"] as Vector2).x) * (GATE_W * 0.5 + 0.8))
	for pl in streets:
		var total := 0.0
		var p2: PackedVector2Array = pl
		for i in range(p2.size() - 1):
			total += p2[i].distance_to(p2[i + 1])
		var s := LAMP_STEP
		var flip := 1.0
		while s < total - 6.0:
			var pt := _along(p2, s)
			var p: Vector2 = pt[0]
			var t: Vector2 = pt[1]
			out.append(p + Vector2(-t.y, t.x) * flip * (STREET_W * 0.5 + 0.4))
			flip = -flip
			s += LAMP_STEP
	var sq: float = SQUARE_R[tier]
	for i in range(4):
		var a := TAU * (float(i) + 0.5) / 4.0
		out.append(Vector2(cos(a), sin(a)) * (sq * 0.8))
	if out.size() > LAMP_CAP:
		out.resize(LAMP_CAP)
	return out


## Market stalls round the square, each with its own hashed canopy colour.
static func _stalls(city: String, tier: int, wseed: int) -> Array:
	var out: Array = []
	var n: int = STALLS[tier]
	var sq: float = SQUARE_R[tier]
	for i in range(n):
		var a := TAU * float(i) / float(n) + 0.3
		var r := sq * 0.55
		out.append({
			"pos": Vector2(cos(a), sin(a)) * r,
			"yaw": -a,
			"tint": _h(wseed, city, 600 + i),
		})
	return out


## ============================================================= runtime ===

func _process(delta: float) -> void:
	_acc += delta
	if _acc < TICK:
		return
	_acc = 0.0
	_tick(_player_pos())


func _player_pos() -> Variant:
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null:
		return null
	var ps := tree.get_nodes_in_group("player")
	if ps.size() == 0:
		return null
	var p: Node = ps[0]
	if p is Node3D:
		return (p as Node3D).global_position
	return null


## One distance check per city plus the lamp state. `pos` null = nobody
## about, which strikes nothing and stages nothing.
func _tick(pos: Variant) -> void:
	if pos is Vector3:
		var pp := pos as Vector3
		for nm in cities.keys():
			var c: Vector3 = cities[nm]["centre"]
			var d := Vector2(pp.x - c.x, pp.z - c.z).length()
			if d < STAGE_RADIUS and not _staged.has(nm):
				stage(nm)
			elif d > STRIKE_RADIUS and _staged.has(nm):
				strike(nm)
	var lit := lamps_lit(hour_now())
	if lit != _lit:
		_lit = lit
		for nm in _staged.keys():
			_apply_lamps(_staged[nm], lit)


func hour_now() -> float:
	if hour_override >= 0.0:
		return hour_override
	if _sky == null:
		return 12.0
	var h: Variant = _sky.get("hour")
	return float(h) if (h is float or h is int) else 12.0


static func lamps_lit(hour: float) -> bool:
	var h := fmod(hour, 24.0)
	if h < 0.0:
		h += 24.0
	return h >= LAMP_ON_HOUR or h < LAMP_OFF_HOUR


## Pin the lamp clock (tests, the sky menu). Sticks until `clear_hour()`,
## so the next tick cannot quietly undo it — which is exactly what the
## first night render showed: a lamp lit by set_hour and put out half a
## second later by a tick that read "no sky → noon".
func set_hour(hour: float) -> void:
	hour_override = hour
	var lit := lamps_lit(hour)
	_lit = lit
	for nm in _staged.keys():
		_apply_lamps(_staged[nm], lit)


func clear_hour() -> void:
	hour_override = -1.0


func is_staged(city: String) -> bool:
	return _staged.has(city)


func staged_node(city: String) -> Node3D:
	return _staged.get(city, null)


## Nearest city to a world position: {name, dist, layout} or {} with none.
func nearest_city(pos: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for nm in cities.keys():
		var c: Vector3 = cities[nm]["centre"]
		var d := Vector2(pos.x - c.x, pos.z - c.z).length()
		if d < best_d:
			best_d = d
			best = {"name": nm, "dist": d, "layout": cities[nm]}
	return best


## One integer that changes whenever the cities do.
func fingerprint() -> int:
	var names: Array = cities.keys()
	names.sort()
	var parts: Array = []
	for nm in names:
		var c: Dictionary = cities[nm]
		parts.append("%s|%d|%s|%d|%d|%s" % [nm, int(c["tier"]), var_to_str(c["centre"]),
				(c["lots"] as Array).size(), (c["gates"] as Array).size(), var_to_str(c["wall"])])
	return hash("%d\n%s" % [world_seed, "\n".join(PackedStringArray(parts))])


func report() -> String:
	var lines: Array = []
	lines.append("Cities: %d (roster %s, seed %d)" % [cities.size(), roster_source, world_seed])
	var names: Array = cities.keys()
	names.sort()
	for nm in names:
		var c: Dictionary = cities[nm]
		var cen: Vector3 = c["centre"]
		var rj: Dictionary = c["rejected"]
		lines.append("  %-16s t%d  (%6.0f, %6.0f)  %s wall %2d verts  gates %d  streets %d  lots %2d  lamps %2d  rejected w%d s%d o%d" % [
			nm, int(c["tier"]), cen.x, cen.z, str(c["wall_kind"]), (c["wall"] as PackedVector2Array).size(),
			(c["gates"] as Array).size(), (c["streets"] as Array).size(), (c["lots"] as Array).size(),
			(c["lamps"] as Array).size(), int(rj["water"]), int(rj["slope"]), int(rj["overlap"])])
	return "\n".join(PackedStringArray(lines))


## ============================================================= staging ===

## Turn a layout into nodes. Idempotent: a city already standing is left
## alone. Everything hangs off one Node3D at the city's centre so a strike
## is a single `queue_free`.
func stage(city: String) -> Node3D:
	if _staged.has(city):
		return _staged[city]
	if not cities.has(city):
		return null
	var c: Dictionary = cities[city]
	var root := Node3D.new()
	root.name = "City_" + city.replace(" ", "_").replace("-", "_")
	root.position = c["centre"]
	add_child(root)
	_staged[city] = root
	_build_ground_pad(root, c)
	_build_wall(root, c)
	_build_wharf(root, c)
	_build_streets(root, c)
	_build_lots(root, c)
	_build_square(root, c)
	_build_lamps(root, c)
	_apply_lamps(root, _lit)
	_mow(c)
	_claim_ground(c)
	return root


func strike(city: String) -> void:
	if not _staged.has(city):
		return
	var n: Node3D = _staged[city]
	_staged.erase(city)
	if is_instance_valid(n):
		n.queue_free()


func strike_all() -> void:
	for nm in _staged.keys().duplicate():
		strike(nm)


## A town is not a hayfield. One cut over the whole core, past the wall;
## the grass records it in its own cut ledger and re-reads it on stream-in,
## so this costs nothing on a reload. Silent no-op with no grass bound.
## THE TOWN IS NOT A MEADOW. A staged city hands its footprint to the grass:
## the chunks inside it belong to the CPU placer, which is the only thing that
## knows about paved streets and mown yards (GrassSystem.set_towns, and the
## GPU field steps out of the rect the way it steps out of the valley).
func _claim_ground(c: Dictionary) -> void:
	if _grass == null or not _grass.has_method("set_towns"):
		return
	var cen: Vector3 = c["centre"]
	var r: float = float(c["core_r"]) * (1.0 + WALL_JITTER * 0.5) + MOW_PAD
	_town_rects.append(Rect2(cen.x - r, cen.z - r, r * 2.0, r * 2.0))
	_grass.call("set_towns", _town_rects)


func _mow(c: Dictionary) -> void:
	if _grass == null:
		return
	var r: float = float(c["core_r"]) * (1.0 + WALL_JITTER * 0.5) + MOW_PAD
	_grass.call("cut_at", c["centre"], r)


## --- materials: one per kind, shared by every city (Enemy._box's lesson) ---

static func mat(kind: String) -> StandardMaterial3D:
	if _mats.has(kind):
		return _mats[kind]
	var m := StandardMaterial3D.new()
	m.roughness = 1.0
	match kind:
		"daub":      m.albedo_color = Color(0.80, 0.72, 0.56)
		"frame":     m.albedo_color = Color(0.22, 0.15, 0.09)
		"board":     m.albedo_color = Color(0.42, 0.33, 0.22)
		"thatch":    m.albedo_color = Color(0.55, 0.45, 0.22)
		"slate":     m.albedo_color = Color(0.26, 0.28, 0.33)
		"stone":     m.albedo_color = Color(0.46, 0.45, 0.42)
		"stone_dk":  m.albedo_color = Color(0.32, 0.31, 0.29)
		"palisade":  m.albedo_color = Color(0.36, 0.27, 0.16)
		"dirt":      m.albedo_color = Color(0.36, 0.28, 0.19)
		## A city is paved and the country is not — that contrast is the whole
		## point of walking through a gate. Cobble for the thoroughfares and
		## the ring roads, brick for the lanes between them.
		"cobble":    m.albedo_color = Color(0.44, 0.43, 0.40)
		"brick":     m.albedo_color = Color(0.44, 0.26, 0.20)
		"door":      m.albedo_color = Color(0.14, 0.09, 0.05)
		"canvas_r":  m.albedo_color = Color(0.62, 0.22, 0.18)
		"canvas_b":  m.albedo_color = Color(0.20, 0.30, 0.50)
		"canvas_y":  m.albedo_color = Color(0.68, 0.58, 0.22)
		"iron":
			m.albedo_color = Color(0.18, 0.18, 0.20)
			m.roughness = 0.6
			m.metallic = 0.4
		"lamp_off":
			m.albedo_color = Color(0.55, 0.50, 0.38)
		"lamp_on":
			m.albedo_color = Color(1.0, 0.85, 0.55)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.72, 0.36)
			m.emission_energy_multiplier = 2.4
		_:
			m.albedo_color = Color(0.5, 0.5, 0.5)
	_mats[kind] = m
	return m


static func _box_in(parent: Node, size: Vector3, m: Material, pos: Vector3, yaw := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.rotation.y = yaw
	parent.add_child(mi)
	return mi


## A box laid ALONG a slope: yaw about +y, then pitch about its own +x, so
## its long axis (local z) runs up the hill instead of cutting into it.
static func _slab_in(parent: Node, size: Vector3, m: Material, pos: Vector3, yaw: float, pitch: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	parent.add_child(mi)
	return mi


## A pitched roof: PrismMesh's ridge runs along its local Z, so a house
## whose depth is along Z gets a gable facing the street.
static func _roof_in(parent: Node, size: Vector3, m: Material, pos: Vector3, yaw := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = size
	pm.left_to_right = 0.5
	mi.mesh = pm
	mi.material_override = m
	mi.position = pos
	mi.rotation.y = yaw
	parent.add_child(mi)
	return mi


static func _collider(size: Vector3, pos: Vector3, yaw := 0.0) -> StaticBody3D:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	sb.position = pos
	sb.rotation.y = yaw
	return sb


## --- the pieces ---

func _build_ground_pad(root: Node3D, c: Dictionary) -> void:
	var pad := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = float(c["square_r"])
	cm.bottom_radius = float(c["square_r"])
	cm.height = 0.12
	cm.radial_segments = 24
	pad.mesh = cm
	## Tier 1 keeps its dirt square — a market at a crossroads is trodden
	## earth. The two bigger tiers are proper cities and lay stone.
	pad.material_override = mat("dirt" if int(c["tier"]) < 2 else "cobble")
	pad.name = "SquarePad"
	pad.position = Vector3(0.0, local_y(c, 0.0, 0.0) + 0.03, 0.0)
	root.add_child(pad)


## Wall segments between polygon vertices; a segment carrying a gate is
## split around a GATE_W gap with a tower either side.
func _build_wall(root: Node3D, c: Dictionary) -> void:
	var wall: PackedVector2Array = c["wall"]
	var tier: int = c["tier"]
	var kind: String = c["wall_kind"]
	if kind == "seawall" or kind == "quay":
		_build_seawall(root, c)
		return
	var h: float = WALL_H[tier]
	var t: float = WALL_T[tier]
	var m: Material = mat("palisade") if kind == "palisade" else mat("stone")
	var holder := Node3D.new()
	holder.name = "Wall"
	root.add_child(holder)
	var n := wall.size()
	var gates: Array = c["gates"]
	for i in range(n):
		var a := wall[i]
		var b := wall[(i + 1) % n]
		# does a gate sit on this segment?
		var gate_t := -1.0
		var gate_dir := Vector2.ZERO
		for g in gates:
			var gp: Vector2 = g["pos"]
			var q := Geometry2D.get_closest_point_to_segment(gp, a, b)
			if q.distance_to(gp) < 0.05:
				gate_t = (q - a).length() / maxf(a.distance_to(b), 0.001)
				gate_dir = g["dir"]
				break
		if gate_t < 0.0:
			_wall_piece(holder, c, a, b, h, t, m, "Seg%d" % i)
		else:
			var L := a.distance_to(b)
			var u := (b - a) / maxf(L, 0.001)
			var gc := a + u * (gate_t * L)
			var half := GATE_W * 0.5 + TOWER_W * 0.5
			var left := gc - u * half
			var right := gc + u * half
			if (left - a).length() > 1.0:
				_wall_piece(holder, c, a, left, h, t, m, "Seg%dL" % i)
			if (b - right).length() > 1.0:
				_wall_piece(holder, c, right, b, h, t, m, "Seg%dR" % i)
			_tower(holder, c, left, h, m, "TowerL%d" % i)
			_tower(holder, c, right, h, m, "TowerR%d" % i)
			# a threshold of dirt through the gap, so the gate reads from a distance
			var yaw := atan2(gate_dir.x, gate_dir.y)
			var gy := local_y(c, gc.x, gc.y)
			_box_in(holder, Vector3(GATE_W, 0.5, t + 4.0), mat("dirt"),
					Vector3(gc.x, gy - 0.22, gc.y), yaw).name = "Gate%d" % i
			if kind == "stone":
				var lintel := _box_in(holder, Vector3(GATE_W + TOWER_W, 1.2, t), mat("stone_dk"),
						Vector3(gc.x, gy + h - 0.6, gc.y), yaw)
				lintel.name = "Lintel%d" % i


## Low granite quay on the Casco (east / SE) face; landward sides stay open.
## Gates get iron-topped posts, not curtain towers. Each gate is assigned to
## exactly one segment so a vertex-hit (common on a rectangular pad) cannot
## stamp two thresholds.
func _build_seawall(root: Node3D, c: Dictionary) -> void:
	var wall: PackedVector2Array = c["wall"]
	var m: Material = mat("stone_dk")
	var holder := Node3D.new()
	holder.name = "Wall"
	root.add_child(holder)
	var n := wall.size()
	var gates: Array = c["gates"]
	var gate_seg: Dictionary = {}
	for gi in range(gates.size()):
		var gp: Vector2 = gates[gi]["pos"]
		var best_i := -1
		var best_d := 0.08
		for i in range(n):
			var q := Geometry2D.get_closest_point_to_segment(gp, wall[i], wall[(i + 1) % n])
			var d := q.distance_to(gp)
			if d < best_d:
				best_d = d
				best_i = i
		if best_i >= 0:
			gate_seg[best_i] = gi
	for i in range(n):
		var a := wall[i]
		var b := wall[(i + 1) % n]
		var d := b - a
		if d.length() < 0.05:
			continue
		var outward := Vector2(d.y, -d.x)
		var harbor := outward.x > 0.0 and absf(outward.x) >= absf(outward.y) * 0.35
		var gi: int = int(gate_seg.get(i, -1))
		var gate_t := -1.0
		var gate_dir := Vector2.ZERO
		if gi >= 0:
			var gp: Vector2 = gates[gi]["pos"]
			var q := Geometry2D.get_closest_point_to_segment(gp, a, b)
			gate_t = (q - a).length() / maxf(a.distance_to(b), 0.001)
			gate_dir = gates[gi]["dir"]
		if harbor:
			if gate_t < 0.0:
				_wall_piece(holder, c, a, b, QUAY_H, QUAY_T, m, "Seg%d" % i)
			else:
				var L := a.distance_to(b)
				var u := (b - a) / maxf(L, 0.001)
				var gc := a + u * (gate_t * L)
				var half := GATE_W * 0.5 + 0.45
				var left := gc - u * half
				var right := gc + u * half
				if (left - a).length() > 1.0:
					_wall_piece(holder, c, a, left, QUAY_H, QUAY_T, m, "Seg%dL" % i)
				if (b - right).length() > 1.0:
					_wall_piece(holder, c, right, b, QUAY_H, QUAY_T, m, "Seg%dR" % i)
		if gi >= 0:
			_harbor_gate(holder, c, a, b, gate_t, gate_dir, gi)


func _harbor_gate(holder: Node3D, c: Dictionary, a: Vector2, b: Vector2, gate_t: float, gate_dir: Vector2, gi: int) -> void:
	var L := a.distance_to(b)
	var u := (b - a) / maxf(L, 0.001)
	var gc := a + u * (gate_t * L)
	var yaw := atan2(gate_dir.x, gate_dir.y)
	var gy := local_y(c, gc.x, gc.y)
	var half := GATE_W * 0.5
	var left := gc - u * half
	var right := gc + u * half
	for pair in [[left, "L"], [right, "R"]]:
		var at: Vector2 = pair[0]
		var py := local_y(c, at.x, at.y)
		var sb := _collider(Vector3(0.7, 3.4, 0.7), Vector3(at.x, py + 1.5, at.y))
		sb.name = "Post%s%d" % [str(pair[1]), gi]
		holder.add_child(sb)
		_box_in(sb, Vector3(0.7, 3.4, 0.7), mat("stone_dk"), Vector3.ZERO)
		_box_in(sb, Vector3(0.14, 1.6, 0.14), mat("iron"), Vector3(0.0, 2.4, 0.0))
	_box_in(holder, Vector3(GATE_W, 0.45, 4.5), mat("cobble"),
			Vector3(gc.x, gy - 0.18, gc.y), yaw).name = "Gate%d" % gi


func _build_wharf(root: Node3D, c: Dictionary) -> void:
	var piers: Array = c.get("piers", [])
	if piers.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "Wharf"
	root.add_child(holder)
	var i := 0
	for pr in piers:
		var root_p: Vector2 = pr["root"]
		var length: float = float(pr["length"])
		var width: float = float(pr["width"])
		var mid: Vector2 = root_p + Vector2(length * 0.5, 0.0)
		var gy := local_y(c, root_p.x, root_p.y)
		var sb := _collider(Vector3(length, 0.7, width), Vector3(mid.x, gy + 0.12, mid.y))
		sb.name = "Pier%d" % i
		holder.add_child(sb)
		_box_in(sb, Vector3(length, 0.55, width), mat("stone_dk"), Vector3.ZERO)
		for sx: float in [-0.38, 0.38]:
			for sz: float in [-0.38, 0.38]:
				_box_in(sb, Vector3(0.32, 2.8, 0.32), mat("frame"),
						Vector3(sx * (length * 0.5 - 0.45), -1.15, sz * (width * 0.5 - 0.28)))
		i += 1


## A wall run, cut into CONFORM_SPAN pieces so it FOLLOWS the ground instead
## of hanging off the centre's height. A 75 m segment of Portland's wall used
## to span a 20 m drop into the harbour in one box.
func _wall_piece(holder: Node3D, c: Dictionary, a: Vector2, b: Vector2, h: float, t: float, m: Material, nm: String) -> void:
	var L := a.distance_to(b)
	if L < 0.05:
		return
	var steps := maxi(1, int(ceil(L / CONFORM_SPAN)))
	for s in range(steps):
		var p0 := a.lerp(b, float(s) / float(steps))
		var p1 := a.lerp(b, float(s + 1) / float(steps))
		_wall_span(holder, c, p0, p1, h, t, m, nm if steps == 1 else "%s_%d" % [nm, s])


## One box: top flush with the HIGHER end, foot 2 m under the lower one, so a
## sloped span shows neither a gap nor a step.
func _wall_span(holder: Node3D, c: Dictionary, a: Vector2, b: Vector2, h: float, t: float, m: Material, nm: String) -> void:
	var L := a.distance_to(b)
	var mid := (a + b) * 0.5
	var y0 := local_y(c, a.x, a.y)
	var y1 := local_y(c, b.x, b.y)
	var top := maxf(y0, y1) + h
	var bot := minf(y0, y1) - 2.0
	var hh := top - bot
	var mid_y := (top + bot) * 0.5
	var d := b - a
	var yaw := atan2(d.x, d.y)                     # local +z runs a→b
	var sb := _collider(Vector3(t, hh, L), Vector3(mid.x, mid_y, mid.y), yaw)
	sb.name = nm
	holder.add_child(sb)
	_box_in(sb, Vector3(t, hh, L), m, Vector3.ZERO)
	if t >= 1.0:
		# a walkway lip along the top
		_box_in(sb, Vector3(t + 0.6, 0.5, L), mat("stone_dk"), Vector3(0.0, top - 0.25 - mid_y, 0.0))


func _tower(holder: Node3D, c: Dictionary, at: Vector2, h: float, m: Material, nm: String) -> void:
	var th := h + 2.5
	var gy := local_y(c, at.x, at.y)
	var sb := _collider(Vector3(TOWER_W, th + 2.0, TOWER_W), Vector3(at.x, gy + th * 0.5 - 1.0, at.y))
	sb.name = nm
	holder.add_child(sb)
	_box_in(sb, Vector3(TOWER_W, th + 2.0, TOWER_W), m, Vector3.ZERO)
	_roof_in(sb, Vector3(TOWER_W + 0.6, 2.2, TOWER_W + 0.6), mat("slate"), Vector3(0.0, th * 0.5 + 2.1, 0.0))


## Streets are dirt strips laid flat on the ground; GroundPaint along the
## net is the proper answer (POLISH #3) and this is the stand-in until then.
func _build_streets(root: Node3D, c: Dictionary) -> void:
	var holder := Node3D.new()
	holder.name = "Streets"
	root.add_child(holder)
	## Thoroughfares and rings are COBBLE, the lanes between them BRICK.
	## Old Port stores cobble grid in `rings` and brick lanes in `minor`,
	## and `roads` is streets + rings + minor so lots fill the cobbles first.
	var n_gate: int = (c["streets"] as Array).size()
	var n_minor: int = (c["minor"] as Array).size()
	var n_rings: int = (c["rings"] as Array).size()
	var old_port := str(c.get("style", "walled")) == "old_port"
	var cen: Vector3 = c["centre"]
	var paved: Array = []
	var ri := -1
	var k := 0
	for pl in c["roads"]:
		ri += 1
		var surface: String
		if old_port:
			surface = "brick" if ri >= n_gate + n_rings else "cobble"
		else:
			surface = "brick" if (ri >= n_gate and ri < n_gate + n_minor) else "cobble"
		var p2: PackedVector2Array = pl
		for i in range(p2.size() - 1):
			var a := p2[i]
			var b := p2[i + 1]
			var seg := b - a
			var SL := seg.length()
			if SL < 0.5:
				continue
			## Cut into CONFORM_SPAN pieces and sit each on its own ground. A
			## ring street is one 60 m chord between wall vertices; laid flat
			## it either floats over the slope or vanishes into it.
			var steps := maxi(1, int(ceil(SL / CONFORM_SPAN)))
			for s in range(steps):
				var q0 := a.lerp(b, float(s) / float(steps))
				var q1 := a.lerp(b, float(s + 1) / float(steps))
				var d := q1 - q0
				var L := d.length()
				if L < 0.05:
					continue
				var mid := (q0 + q1) * 0.5
				var y0 := local_y(c, q0.x, q0.y)
				var y1 := local_y(c, q1.x, q1.y)
				var gy := (y0 + y1) * 0.5
				## A street LIES ON the slope, it does not step down it. The
				## first conforming pass laid every piece level and Portland's
				## gate street came down the harbour bank as a dashed line of
				## floating plates. 0.6 m thick, top at the ground: a thin
				## strip opens a seam at every joint the moment it tilts.
				var pitch := atan2(y1 - y0, L)
				var run := sqrt(L * L + (y1 - y0) * (y1 - y0))
				_slab_in(holder, Vector3(STREET_W, 0.6, run + STREET_W * 0.5), mat(surface),
						Vector3(mid.x, gy - 0.28, mid.y), atan2(d.x, d.y), -pitch).name = "S%d" % k
				k += 1
				## ...and the meadow stops at the kerb. The slab's top sits AT
				## the ground, so grass left standing under one grows straight
				## up through the cobbles. WORLD coordinates: the polylines are
				## local to the city centre, GrassSystem is not.
				paved.append({"a": Vector2(cen.x + q0.x, cen.z + q0.y),
					"b": Vector2(cen.x + q1.x, cen.z + q1.y), "w": STREET_W + 0.6})
	if _grass != null and _grass.has_method("pave"):
		_grass.call("pave", paved)


func _build_lots(root: Node3D, c: Dictionary) -> void:
	var holder := Node3D.new()
	holder.name = "Lots"
	root.add_child(holder)
	var cy: float = (c["centre"] as Vector3).y
	var old_port := str(c.get("style", "walled")) == "old_port"
	var i := 0
	for lot in c["lots"]:
		var p: Vector2 = lot["pos"]
		var s: Vector3 = lot["size"]
		var yaw: float = lot["yaw"]
		var y: float = float(lot["y"]) - cy
		var kind: String = lot["kind"]
		var wall_mat := str(lot.get("wall_mat", "daub"))
		var roof_mat := str(lot.get("roof_mat", "thatch"))
		var house := Node3D.new()
		house.name = "%s%d" % [kind.capitalize(), i]
		house.position = Vector3(p.x, y, p.y)
		house.rotation.y = yaw
		holder.add_child(house)
		match kind:
			"hall":
				_house_body(house, Vector3(s.x * 1.5, s.y * 1.3, s.z * 1.4), wall_mat, roof_mat, true)
			"chapel":
				_house_body(house, Vector3(s.x * 1.1, s.y * 1.6, s.z * 1.6), wall_mat, roof_mat, true)
				var spire := _box_in(house, Vector3(1.6, s.y * 1.6, 1.6), mat("stone_dk"),
						Vector3(0.0, s.y * 1.6 + s.y * 0.8, -s.z * 0.5))
				spire.name = "Spire"
				_roof_in(spire, Vector3(2.0, 3.0, 2.0), mat("slate"), Vector3(0.0, s.y * 0.8 + 1.5, 0.0))
			"custom_house":
				_house_body(house, Vector3(s.x * 1.55, s.y * 1.35, s.z * 1.5), wall_mat, roof_mat, true, true)
				var cup := _box_in(house, Vector3(2.2, s.y * 0.55, 2.2), mat("stone"),
						Vector3(0.0, s.y * 1.35 + 0.9, 0.0))
				cup.name = "Cupola"
				_roof_in(cup, Vector3(2.6, 1.4, 2.6), mat("slate"), Vector3(0.0, s.y * 0.35 + 0.8, 0.0))
			"church":
				_house_body(house, Vector3(s.x * 1.15, s.y * 1.55, s.z * 1.7), wall_mat, roof_mat, true, true)
				var cspire := _box_in(house, Vector3(1.7, s.y * 1.5, 1.7), mat("brick"),
						Vector3(0.0, s.y * 1.55 + s.y * 0.75, -s.z * 0.45))
				cspire.name = "Spire"
				_roof_in(cspire, Vector3(2.1, 2.6, 2.1), mat("slate"), Vector3(0.0, s.y * 0.75 + 1.3, 0.0))
			"warehouse":
				_house_body(house, s, wall_mat, roof_mat, false)
			"inn":
				_house_body(house, Vector3(s.x * 1.3, s.y * 1.25, s.z * 1.3), wall_mat, roof_mat, true, old_port)
				var sign_mi := _box_in(house, Vector3(1.2, 0.8, 0.12), mat("board"),
						Vector3(s.x * 0.65 + 0.7, s.y * 0.9, s.z * 0.65 - 0.2))
				sign_mi.name = "Sign"
			_:
				_house_body(house, s, wall_mat, roof_mat, false, old_port)
				if old_port:
					_box_in(house, Vector3(s.x * 0.62, 0.08, 0.85), mat("iron"),
							Vector3(0.0, s.y * 0.52, s.z * 0.5 + 0.48))
					_box_in(house, Vector3(s.x * 0.62, 0.7, 0.06), mat("iron"),
							Vector3(0.0, s.y * 0.52 + 0.35, s.z * 0.5 + 0.88))
		i += 1


## Body + plinth + roof + door + collider. `size` is (w, h, d); the door is
## on the +z face, which `layout` turned toward the street.
func _house_body(house: Node3D, s: Vector3, wall_kind: String, roof_kind: String, grand: bool, shallow := false) -> void:
	var sb := _collider(Vector3(s.x, s.y + 1.5, s.z), Vector3(0.0, s.y * 0.5 - 0.75, 0.0))
	sb.name = "Body"
	house.add_child(sb)
	# plinth: 1.5 m of dark stone below grade so a sloped lot shows no gap
	_box_in(sb, Vector3(s.x + 0.2, 1.5 + 0.5, s.z + 0.2), mat("stone_dk"), Vector3(0.0, -s.y * 0.5 + 0.25, 0.0))
	_box_in(sb, s, mat(wall_kind), Vector3(0.0, 0.75, 0.0))
	if wall_kind == "daub":
		# the dark frame: four corner posts and a sill, so daub reads as daub
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				_box_in(sb, Vector3(0.3, s.y, 0.3), mat("frame"), Vector3(sx * (s.x * 0.5 - 0.05), 0.75, sz * (s.z * 0.5 - 0.05)))
		_box_in(sb, Vector3(s.x + 0.1, 0.25, s.z + 0.1), mat("frame"), Vector3(0.0, 0.75 - s.y * 0.5 + 1.2, 0.0))
	if roof_kind == "cornice":
		_box_in(house, Vector3(s.x + 0.7, 0.14, s.z + 0.7), mat("stone_dk"), Vector3(0.0, s.y - 0.02, 0.0))
		_box_in(house, Vector3(s.x + 0.5, 0.36, s.z + 0.5), mat("slate"), Vector3(0.0, s.y + 0.16, 0.0))
	else:
		var roof_h := 2.2 if not grand else 3.0
		if shallow:
			roof_h = 1.05 if not grand else 1.45
		_roof_in(house, Vector3(s.x + 0.8, roof_h, s.z + 0.6), mat(roof_kind), Vector3(0.0, s.y + roof_h * 0.5 - 0.05, 0.0))
	_box_in(house, Vector3(1.0, 2.0, 0.12), mat("door"), Vector3(0.0, 1.0, s.z * 0.5 + 0.04)).name = "Door"


func _build_square(root: Node3D, c: Dictionary) -> void:
	var holder := Node3D.new()
	holder.name = "Square"
	root.add_child(holder)
	# the well
	var well := _collider(Vector3(2.2, 1.0, 2.2), Vector3(0.0, 0.5, 0.0))
	well.name = "Well"
	holder.add_child(well)
	_box_in(well, Vector3(2.2, 1.0, 2.2), mat("stone"), Vector3.ZERO)
	_box_in(well, Vector3(0.2, 2.4, 0.2), mat("frame"), Vector3(-0.9, 1.2, 0.0))
	_box_in(well, Vector3(0.2, 2.4, 0.2), mat("frame"), Vector3(0.9, 1.2, 0.0))
	_roof_in(well, Vector3(2.8, 0.9, 1.4), mat("board"), Vector3(0.0, 2.6, 0.0))
	# the stalls
	var canvases := ["canvas_r", "canvas_b", "canvas_y"]
	var i := 0
	for st in c["stalls"]:
		var p: Vector2 = st["pos"]
		var stall := Node3D.new()
		stall.name = "Stall%d" % i
		stall.position = Vector3(p.x, local_y(c, p.x, p.y), p.y)
		stall.rotation.y = float(st["yaw"])
		holder.add_child(stall)
		_box_in(stall, Vector3(3.0, 0.9, 1.2), mat("board"), Vector3(0.0, 0.45, 0.0))
		for sx: float in [-1.3, 1.3]:
			_box_in(stall, Vector3(0.15, 2.4, 0.15), mat("frame"), Vector3(sx, 1.2, -0.5))
			_box_in(stall, Vector3(0.15, 2.4, 0.15), mat("frame"), Vector3(sx, 1.2, 0.5))
		var canvas: String = canvases[int(floorf(float(st["tint"]) * 3.0)) % 3]
		_roof_in(stall, Vector3(3.4, 0.9, 1.8), mat(canvas), Vector3(0.0, 2.75, 0.0))
		i += 1


func _build_lamps(root: Node3D, c: Dictionary) -> void:
	var holder := Node3D.new()
	holder.name = "Lamps"
	root.add_child(holder)
	var i := 0
	for lp in c["lamps"]:
		var p: Vector2 = lp
		var lamp := Node3D.new()
		lamp.name = "Lamp%d" % i
		lamp.position = Vector3(p.x, local_y(c, p.x, p.y), p.y)
		holder.add_child(lamp)
		_box_in(lamp, Vector3(0.18, 3.2, 0.18), mat("iron"), Vector3(0.0, 1.6, 0.0))
		var head := _box_in(lamp, Vector3(0.42, 0.42, 0.42), mat("lamp_off"), Vector3(0.0, 3.35, 0.0))
		head.name = "Head"
		var light := OmniLight3D.new()
		light.name = "Light"
		light.position = Vector3(0.0, 3.35, 0.0)
		light.omni_range = 18.0
		light.light_energy = 2.6
		light.light_color = Color(1.0, 0.78, 0.5)
		light.shadow_enabled = false
		light.visible = false
		lamp.add_child(light)
		i += 1


## The one runtime beat: every staged lamp follows the clock.
func _apply_lamps(root: Node3D, lit: bool) -> void:
	var holder := root.get_node_or_null("Lamps")
	if holder == null:
		return
	for lamp in holder.get_children():
		var head := lamp.get_node_or_null("Head")
		if head != null and head is MeshInstance3D:
			(head as MeshInstance3D).material_override = mat("lamp_on") if lit else mat("lamp_off")
		var light := lamp.get_node_or_null("Light")
		if light != null and light is OmniLight3D:
			(light as OmniLight3D).visible = lit
