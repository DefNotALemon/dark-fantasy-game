class_name Chronicle
extends Node

## ===========================================================================
## THE CHRONICLE — the world that keeps happening while you are not there.
##
## Myrkfell's map is roughly a hundred kilometres of Maine renamed, and until
## now every one of the fifty named places on it was a label on a map panel.
## Nothing happened at Bangor. Nothing had ever happened at Bangor. You could
## walk the Allagash for a game year and the world would have no memory of the
## year having passed.
##
## This is the fix, and it is deliberately CHEAP: a coarse simulation of the
## whole map that runs on DayNight's calendar, half a game hour at a step,
## whether or not the player is within a hundred kilometres of the place it is
## simulating. Places carry four numbers — mood, stores, alarm, watch. Events
## are drawn from ChronicleEvents' catalogue, weighted by the hour, the season,
## the sky, the region and the place's own state. An event lives for a handful
## of game hours and then RESOLVES into one of its outcomes, and the outcome
## does three things: it moves the place's numbers, it drops a rumour into that
## place and its neighbours, and it adds to a world-wide bias pool that makes
## the same sort of thing likelier — or rarer — for the next few days.
##
## That last part is the whole design. A bad wolf winter is not a die roll; it
## is one fold lost, which biases wolves up, which loses another fold, which
## sends the hunt out, which biases wolves down. The world argues with itself.
##
## THREE RULES this file will not break:
##
##   1. **It is deterministic.** There is no RandomNumberGenerator anywhere in
##      here. Every roll is a hash of (world_seed, step index, salt), so two
##      Chronicles with the same seed tell the same story to the last comma,
##      and a save that stores the step index restores the future as well as
##      the past. That is what makes `to_dict()` honest.
##   2. **Step size cannot change the story.** `advance()` accumulates hours
##      and only ever executes whole STEP_HOURS steps off a running total, so
##      one call of `advance(240)` and two hundred and forty calls of
##      `advance(1)` run the same 480 steps in the same order. The game feeds
##      it ragged frame deltas; the tests feed it clean days; both agree.
##   3. **It never touches the scene.** The Chronicle knows about places, not
##      nodes. Making an event physical near the player — the torn hurdle, the
##      blood trail, the caravan you can actually meet — is the Incident
##      Director's job (Sunday plan item 2), and it reads this.
##
## Wired up by World.gd (tools/patch_chronicle.py):
##     _chronicle = Chronicle.new(); Chronicle.bind(_daynight, _weather)
##     add_child(_chronicle); _chronicle.boot()
## Read it with:  World.chronicle().rumours_at(pos)
##
## A node added to `root` from SceneTree._init() never gets `_ready()`, which
## is how StepAudio was caught out on 2026-09-05 — so `boot()` is an explicit,
## idempotent setup call the headless suite can make for itself.
## ===========================================================================

signal event_fired(ev: Dictionary)
signal event_resolved(ev: Dictionary)

## How long a rumour is still worth repeating. Six days is two thirds of a
## season-quarter at 24 days a season: long enough that a walk from the coast
## to Katahdin arrives ahead of the news, short enough that a village is never
## reciting last spring.
const RUMOUR_DAYS := 6.0
## The whole map, not one region. Eighteen at once is already a busy world;
## the cap exists so a bad feedback loop cannot run away with the sim.
const MAX_ACTIVE := 18
## The sim's heartbeat. Half a game hour is ~25 real seconds at DayNight's
## 20-minute day: fine enough that "the caravan reaches the ford at nine" is
## meaningful, coarse enough that 200 game days is ten thousand steps.
const STEP_HOURS := 0.5
## How fast the world forgets. Three days to half — so a wolf scare is spent
## inside a week unless something feeds it.
const BIAS_HALFLIFE_DAYS := 3.0
## The ring of what has already happened, for rumours, the tavern board and
## the Incident Director's aftermath lookups.
const RESOLVED_KEEP := 64

## How much history a brand-new world is handed the moment it first sees the
## sky's clock. Walking into a world where nothing has ever happened and the
## tavern board is blank is the exact failure this whole file exists to fix,
## so the Chronicle simulates the week before you arrived and starts you in
## the middle of a story. 336 steps, about a tenth of a second, once.
const PRIME_DAYS := 7.0
## Steps one _process call will run while catching up after a sleep or a load.
## The sim is ~0.2 ms a step, so this is a few milliseconds of frame; the rest
## waits for the next frame. Determinism does not care — the state is a pure
## function of the step index, not of when the steps were executed.
const CATCHUP_STEPS := 16

## How many rumours one place will hold before the oldest falls off. A tavern
## board, not an archive.
const RUMOURS_PER_PLACE := 8
## How far news travels from where it happened, in metres. Roughly a hard
## day's walk on the bake's scale — the next valley hears, the next region
## does not.
const RUMOUR_SPREAD := 1400.0
## Chance-per-step scaling. Tuned so the whole fifty-place map runs at roughly
## three events a game day and holds six to ten at once: busy enough that a
## week of play has a story in it, quiet enough that no single place is a soap
## opera, and far enough under MAX_ACTIVE that the cap is a safety net rather
## than the thing actually setting the pace.
const FIRE_GAIN := 0.006
const FIRE_CEIL := 0.16
## Below this a bias tag is dropped rather than carried as a rounding crumb —
## and dropping it keeps `to_dict()` from growing a tail of dead tags forever.
const BIAS_FLOOR := 0.001
## Seasons, mirroring Wind.DAYS_PER_SEASON. NOT read from Wind: the Chronicle
## must run in a headless suite with no Wind node, no shaders and no tree, and
## a season is arithmetic, not a service.
const DAYS_PER_SEASON := 24.0

const PLACE_ROSTER: Array = [
	{"name": "Ashland", "pos": Vector2(3102.9, -6072.0), "y": 109.35, "rank": 0},
	{"name": "Augusta", "pos": Vector2(754.3, -504.0), "y": 11.59, "rank": 2},
	{"name": "Bangor", "pos": Vector2(2468.6, -1680.0), "y": 12.64, "rank": 2},
	{"name": "Bar Harbor", "pos": Vector2(3445.7, -696.0), "y": -19.0, "rank": 1},
	{"name": "Bath", "pos": Vector2(685.7, 480.0), "y": -19.0, "rank": 1},
	{"name": "Belfast", "pos": Vector2(2091.4, -792.0), "y": -19.0, "rank": 0},
	{"name": "Bethel", "pos": Vector2(-994.3, -720.0), "y": 17.98, "rank": 0},
	{"name": "Biddeford", "pos": Vector2(-411.4, 1464.0), "y": -19.0, "rank": 1},
	{"name": "Bingham", "pos": Vector2(582.9, -2280.0), "y": 16.61, "rank": 0},
	{"name": "Blue Hill", "pos": Vector2(2777.1, -744.0), "y": 2.5, "rank": 0},
	{"name": "Boothbay", "pos": Vector2(994.3, 600.0), "y": -19.0, "rank": 0},
	{"name": "Bridgton", "pos": Vector2(-857.1, 120.0), "y": 18.55, "rank": 0},
	{"name": "Brunswick", "pos": Vector2(411.4, 432.0), "y": 8.25, "rank": 1},
	{"name": "Bucksport", "pos": Vector2(2434.3, -1128.0), "y": 2.5, "rank": 0},
	{"name": "Calais", "pos": Vector2(5022.9, -2616.0), "y": -19.0, "rank": 0},
	{"name": "Camden", "pos": Vector2(1971.4, -264.0), "y": -19.0, "rank": 0},
	{"name": "Caribou", "pos": Vector2(3771.4, -6624.0), "y": 113.47, "rank": 0},
	{"name": "Dover-Foxcroft", "pos": Vector2(1680.0, -2592.0), "y": 18.09, "rank": 0},
	{"name": "Eastport", "pos": Vector2(5417.1, -1920.0), "y": -19.0, "rank": 0},
	{"name": "Ellsworth", "pos": Vector2(3068.6, -1056.0), "y": -19.0, "rank": 0},
	{"name": "Farmington", "pos": Vector2(102.9, -1368.0), "y": 19.19, "rank": 1},
	{"name": "Fort Kent", "pos": Vector2(2777.1, -7584.0), "y": 2.5, "rank": 0},
	{"name": "Freeport", "pos": Vector2(188.6, 576.0), "y": 18.59, "rank": 0},
	{"name": "Fryeburg", "pos": Vector2(-1320.0, 192.0), "y": 27.92, "rank": 0},
	{"name": "Gardiner", "pos": Vector2(737.1, -312.0), "y": 15.28, "rank": 0},
	{"name": "Greenville", "pos": Vector2(1062.9, -3264.0), "y": 30.53, "rank": 1},
	{"name": "Houlton", "pos": Vector2(4062.9, -4872.0), "y": 35.82, "rank": 1},
	{"name": "Jackman", "pos": Vector2(-68.6, -3648.0), "y": 334.75, "rank": 0},
	{"name": "Kingfield", "pos": Vector2(102.9, -2064.0), "y": 22.58, "rank": 0},
	{"name": "Kittery", "pos": Vector2(-925.7, 2424.0), "y": -19.0, "rank": 0},
	{"name": "Lewiston–Auburn", "pos": Vector2(0.0, -0.0), "y": 0.0, "rank": 2},
	{"name": "Lincoln", "pos": Vector2(2931.4, -3024.0), "y": 19.79, "rank": 0},
	{"name": "Livermore Falls", "pos": Vector2(34.3, -888.0), "y": 17.39, "rank": 0},
	{"name": "Machias", "pos": Vector2(4714.3, -1488.0), "y": 20.22, "rank": 0},
	{"name": "Millinocket", "pos": Vector2(2571.4, -3744.0), "y": 29.13, "rank": 1},
	{"name": "Norway", "pos": Vector2(-582.9, -264.0), "y": 17.54, "rank": 0},
	{"name": "Old Town", "pos": Vector2(2674.3, -1992.0), "y": 13.82, "rank": 0},
	{"name": "Patten", "pos": Vector2(3017.1, -4560.0), "y": 28.45, "rank": 0},
	{"name": "Portland", "pos": Vector2(-85.7, 1056.0), "y": 18.37, "rank": 2},
	{"name": "Presque Isle", "pos": Vector2(3754.3, -6192.0), "y": 108.43, "rank": 1},
	{"name": "Rangeley", "pos": Vector2(-737.1, -2064.0), "y": 254.04, "rank": 1},
	{"name": "Rockland", "pos": Vector2(1885.7, -0.0), "y": -19.0, "rank": 1},
	{"name": "Rumford", "pos": Vector2(-582.9, -1080.0), "y": 16.76, "rank": 1},
	{"name": "Sanford", "pos": Vector2(-960.0, 1584.0), "y": 18.92, "rank": 0},
	{"name": "Skowhegan", "pos": Vector2(840.0, -1608.0), "y": 14.61, "rank": 1},
	{"name": "Stonington", "pos": Vector2(2640.0, -144.0), "y": -19.0, "rank": 0},
	{"name": "Sugarloaf", "pos": Vector2(-171.4, -2280.0), "y": 332.82, "rank": 0},
	{"name": "Van Buren", "pos": Vector2(3891.4, -7344.0), "y": 2.5, "rank": 0},
	{"name": "Waterville", "pos": Vector2(994.3, -1080.0), "y": 12.26, "rank": 1},
	{"name": "Wiscasset", "pos": Vector2(942.9, 240.0), "y": 18.43, "rank": 0},
]

const REGION_ROSTER: Array = [
	{"name": "100-MILE WILDERNESS", "pos": Vector2(1645.7, -3600.0), "r": 699.9},
	{"name": "ACADIA", "pos": Vector2(3274.3, -480.0), "r": 300.4},
	{"name": "ALLAGASH", "pos": Vector2(1560.0, -5880.0), "r": 391.4},
	{"name": "ANDROSCOGGIN R.", "pos": Vector2(-240.0, -768.0), "r": 454.2},
	{"name": "AROOSTOOK", "pos": Vector2(3274.3, -6360.0), "r": 565.2},
	{"name": "BAXTER STATE PARK", "pos": Vector2(2160.0, -4920.0), "r": 930.2},
	{"name": "BIGELOW RANGE", "pos": Vector2(-154.3, -2688.0), "r": 425.2},
	{"name": "CASCO BAY", "pos": Vector2(274.3, 1200.0), "r": 342.0},
	{"name": "DOWN EAST", "pos": Vector2(4645.7, -2160.0), "r": 470.6},
	{"name": "GULF OF MAINE", "pos": Vector2(2760.0, 1200.0), "r": 965.9},
	{"name": "KATAHDIN", "pos": Vector2(2211.4, -4320.0), "r": 356.7},
	{"name": "KENNEBEC R.", "pos": Vector2(1011.4, -792.0), "r": 295.3},
	{"name": "MAHOOSUCS", "pos": Vector2(-1320.0, -1248.0), "r": 326.7},
	{"name": "MIDCOAST", "pos": Vector2(1560.0, -480.0), "r": 311.9},
	{"name": "MOOSEHEAD", "pos": Vector2(960.0, -3480.0), "r": 319.2},
	{"name": "PENOBSCOT BAY", "pos": Vector2(2331.4, 120.0), "r": 492.2},
	{"name": "PENOBSCOT R.", "pos": Vector2(3068.6, -2520.0), "r": 334.2},
	{"name": "RANGELEY LAKES", "pos": Vector2(-977.1, -2232.0), "r": 563.5},
]


## The live instance, found the way Telegraph finds itself — never assumed to
## exist, because a headless test and the old world both build without one.
static var inst: Chronicle = null

## The clock and the sky, bound by World the same way GrowthClock binds them.
## Statics, so a place restored from a save can ask what day it is without
## holding a node reference. Both may be null forever: unbound, the Chronicle
## keeps its own clock (whatever `advance()` is fed) and rolls its own weather.
static var _daynight: Node = null
static var _weather: Node = null

## The seed the whole story hangs off. Change it and you get a different world
## with the same map. World leaves it at the default so every fresh run tells
## the same first week, which is what makes a bug reproducible.
var world_seed: int = 20260906

var places: Array = []          ## of place Dictionaries, see the file header
var active: Array = []          ## live events
var resolved: Array = []        ## the last RESOLVED_KEEP, oldest first
var bias: Dictionary = {}       ## tag -> float, canonical (sorted) after each step

## [factions] WHO HOLDS THE GROUND. `bias` above is one pool for the whole
## map, which is why `pressure_at` took a position and threw it away. These
## four are the write side: the political field, the fortnight's memory of
## what has been happening in each region, and the last holder seen, so a
## border that MOVES can say so. The three cached tables beneath them are
## pure functions of the roster and are rebuilt by boot(), never saved.
var factions: Dictionary = {}   ## region -> {men, goblins, wolves, wild}
var fpush: Dictionary = {}      ## region -> {men, goblins, wolves, lawless}
var _fwas: Dictionary = {}      ## region -> the holder at the last step
var _fseats: Dictionary = {}
var _fadj: Dictionary = {}
var _fanch: Dictionary = {}
var _fland: Array = []
var days := 0.0                 ## the sim's own clock, in float game days

var _steps := 0                 ## the step index the sim has reached
var _ran := 0                   ## steps actually EXECUTED, for profiling and tests
var _hours := 0.0               ## total game hours fed to advance()
var _uid := 1
var _booted := false
var _last_clock := -1.0         ## the game clock reading at the last _process


## ============================== Wiring up =================================


static func bind(daynight: Node, weather: Node) -> void:
	_daynight = daynight
	_weather = weather


static func get_bus(from: Node) -> Chronicle:
	## Same contract as Telegraph.get_bus: never assume, never crash.
	if inst != null and is_instance_valid(inst):
		return inst
	if from != null and from.is_inside_tree():
		var n := from.get_tree().get_first_node_in_group("chronicle")
		if n is Chronicle:
			inst = n as Chronicle
			return inst
	return null


func _ready() -> void:
	inst = self
	add_to_group("chronicle")
	boot()


func _exit_tree() -> void:
	if inst == self:
		inst = null


func boot(force := false) -> void:
	## Idempotent by design: World calls it, `_ready` calls it, and the tests
	## call it three times in a row. Only `force` rebuilds — otherwise a second
	## call is a no-op, because rebuilding would throw away a world that a save
	## may already have been loaded into.
	if _booted and not force:
		return
	places.clear()
	active.clear()
	resolved.clear()
	bias.clear()
	days = 0.0
	_steps = 0
	_hours = 0.0
	_uid = 1
	_ran = 0
	_last_clock = -1.0
	for row in _roster():
		var r := row as Dictionary
		var pos: Vector2 = r.get("pos", Vector2.ZERO)
		var rank := clampi(int(r.get("rank", 0)), 0, 2)
		## Opening state is seeded, not uniform: a world where every village
		## starts at exactly 0.5 mood reads as a spreadsheet for its first
		## week. Bigger places keep deeper stores and a real watch; the
		## outposts up the Allagash keep neither.
		var h := _hash(int(pos.x), int(pos.y), 7717)
		places.append({
			"name": String(r.get("name", "")),
			"pos": pos,
			"y": float(r.get("y", 0.0)),
			"rank": rank,
			"region": _region_for(pos),
			"mood": clampf(0.55 + 0.20 * _unit(h, 1) - 0.05 * float(2 - rank), 0.0, 1.0),
			"stores": clampf(0.50 + 0.25 * _unit(h, 2) + 0.10 * float(rank), 0.0, 1.0),
			"alarm": clampf(0.10 * _unit(h, 3), 0.0, 1.0),
			"watch": clampf(0.15 + 0.20 * _unit(h, 4) + 0.20 * float(rank), 0.0, 1.0),
			"rumours": [],
		})
	_rebuild_factions()
	_booted = true


func _rebuild_factions() -> void:
	## The political map is DERIVED from the places that exist right now — add
	## a fort at runtime and the borders redraw themselves. Nothing in here is
	## saved except the field itself and its pressure.
	_fseats = Factions.seats_from(places)
	_fland = Factions.land_regions(REGION_ROSTER, _fseats)
	_fadj = Factions.adjacency(_fland, Factions.centres_of(REGION_ROSTER))
	_fanch = Factions.anchors(_fland, _fseats, Factions.reach(_fland, _fseats, _fadj))
	factions = Factions.blank(_fanch)
	fpush = Factions.blank_push(_fland)
	_fwas = {}
	for r in _fland:
		_fwas[String(r)] = Factions.holder_of(factions, String(r))


func _roster() -> Array:
	## The live bake if the Overworld is up, the shipped roster if it is not.
	## Both are the same fifty places -- PLACE_ROSTER was generated from
	## assets/terrain/maine_meta.json -- so a headless suite simulates the real
	## map rather than a stand-in, and anything the fort builder appends to the
	## live place list (World.gd:731) is chronicled too.
	##
	## Found through the "terrain" group and duck-typed on places(), never by
	## class_name: the headless suite loads this file into a project with no
	## Overworld.gd in it at all, and a hard reference would be a parse error
	## rather than a graceful absence.
	var ow: Node = null
	if is_inside_tree():
		for n in get_tree().get_nodes_in_group("terrain"):
			if n.has_method("places"):
				ow = n
				break
	if ow != null:
		var live: Variant = ow.call("places")
		if live is Array and not (live as Array).is_empty():
			var out: Array = []
			for p in (live as Array):
				if not (p is Dictionary):
					continue
				var pd := p as Dictionary
				var q: Array = pd.get("pos", [0.0, 0.0])
				if q.size() < 2:
					continue
				out.append({
					"name": String(pd.get("name", "")),
					"pos": Vector2(float(q[0]), float(q[1])),
					"y": float(pd.get("y", 0.0)),
					"rank": int(pd.get("rank", 0)),
				})
			## Sorted by name so the simulation order is the same on every
			## machine and in every save -- the bake's own order is whatever
			## the generator happened to emit, and determinism cannot rest on
			## that.
			out.sort_custom(func(a, b): return String(a["name"]) < String(b["name"]))
			if not out.is_empty():
				return out
	return PLACE_ROSTER


func _region_for(pos: Vector2) -> String:
	## Which part of the map a place belongs to, for the catalogue's region
	## preferences.
	##
	## Deliberately NOT the same rule as Overworld.region_name_at, which only
	## answers inside a region's circle and returns "" everywhere else. That is
	## right for a map label — you are not "in" Katahdin standing at Bangor —
	## but it is wrong here: the eighteen circles cover maybe a third of the
	## bake, so under that rule two thirds of the fifty places would have no
	## region at all and every region preference in the catalogue would be
	## dead weight. So: the circle that contains it if there is one, otherwise
	## the nearest circle's centre. Every place belongs somewhere.
	##
	## [factions] The rule itself now lives in `Factions.region_at`, because
	## the faction field has to answer the same question for an arbitrary
	## position and two copies of this would be two maps.
	return Factions.region_at(Vector3(pos.x, 0.0, pos.y), REGION_ROSTER)


## =============================== The clock ================================


func _process(_delta: float) -> void:
	## The game's own clock drives the sim — NOT the frame delta. Sleeping
	## through a week, or winding the sky menu forward, must chronicle the week
	## that passed rather than the two real seconds it took, and DayNight's
	## day+hour is the only honest reading of that.
	if _daynight == null or not is_instance_valid(_daynight):
		return
	if not ("day" in _daynight and "hour" in _daynight):
		return
	var now := float(_daynight.day) + float(_daynight.hour) / 24.0
	if _last_clock < 0.0:
		_last_clock = now
		_adopt(now)
		return
	var d := now - _last_clock
	_last_clock = now
	if d > 0.0:
		## A clock wound BACKWARDS is not a season of history, so only forward
		## time is banked. Thirty days is the ceiling on one handover.
		_hours += minf(d, 30.0) * 24.0
		days = _hours / 24.0
	## Drained EVERY frame, not only on the frames the clock moved. A sleep
	## hands over a month at once and a month in one frame is a visible hitch,
	## so the steps are metered out — and if the drain only ran when the clock
	## moved, a backlog banked on one frame would sit there until the next
	## time-jump, which is to say for the rest of the game.
	_run_steps(CATCHUP_STEPS)


func _adopt(now: float) -> void:
	## The first clock reading this Chronicle has ever seen.
	##
	## DayNight boots at day 30, hour 19.7 — mid-summer, dusk — while a fresh
	## Chronicle sits at its own day 0, hour 0, which is the first day of
	## spring at midnight. Left alone the two clocks stay that far apart
	## forever, and every `hours` band and `seasons` gate in the catalogue is
	## evaluated against a calendar the sky has never heard of: the tavern says
	## "kept the wolves off last night" at three in the afternoon, and an
	## autumn-and-winter kind fires right through the game's summer.
	##
	## So the sim adopts the sky's calendar the moment it first reads it, and
	## then simulates PRIME_DAYS of it, so the world you walk into already has
	## a week of news in it. A save restored before the first frame is within a
	## day of the clock already, which is what the 24-hour guard is for.
	var drift: float = now * 24.0 - _hours
	if absf(drift) <= 24.0:
		return
	_hours = now * 24.0
	days = _hours / 24.0
	var want := int(floor(_hours / STEP_HOURS + 1e-9))
	_steps = maxi(want - int(PRIME_DAYS * 24.0 / STEP_HOURS), 0)
	_run_steps(20000)


func advance(hours: float, budget := 20000) -> void:
	## The pure simulation step, and the only way time passes in here.
	##
	## The total is accumulated and the step count is derived from it, rather
	## than each call consuming its own hours: that is what makes advance(240)
	## and 240 x advance(1) run the identical 480 steps. Do not "optimise" this
	## into a per-call remainder — the remainder is where the drift lives.
	if hours <= 0.0:
		return
	if not _booted:
		boot()
	_hours += hours
	days = _hours / 24.0
	_run_steps(budget)


func _run_steps(budget: int) -> void:
	## The one place a step is ever executed. `budget` is a hard ceiling so that
	## loading a save from a hundred game years ago cannot lock the main thread
	## simulating a century of sheep — anything left over is picked up by the
	## next call, because `_steps` is state, not a local.
	var want := int(floor(_hours / STEP_HOURS + 1e-9))
	while _steps < want and budget > 0:
		_steps += 1
		_ran += 1
		budget -= 1
		_step(_steps)


func _step(n: int) -> void:
	var t := float(n) * STEP_HOURS / 24.0        ## this step's time, in days
	var hour := fposmod(t * 24.0, 24.0)
	var season := season_at(t)
	var sky := _weather_level(t)

	_decay_bias()
	_step_factions(t)
	_drift(t)
	_prune_rumours(t)
	_resolve_due(t)
	_maybe_fire(n, t, hour, season, sky)


func _step_factions(t: float) -> void:
	## [factions] The border moves on the same step everything else does, by
	## exactly one step's worth of days — so a sleep that hands the sim
	## fourteen hours at once moves it fourteen hours, and a save that restores
	## the step count restores the frontier with it.
	if _fland.is_empty():
		return
	Factions.step(factions, fpush, _fanch, _fadj, _fseats, STEP_HOURS / 24.0)
	## and a border that has actually moved is NEWS. It is deposited at the
	## region's chief seat and travels from there like anything else, so you
	## hear that the watch has lost the Allagash from someone in a village
	## rather than from a number on a panel.
	for r in _fland:
		var rn := String(r)
		var was := String(_fwas.get(rn, ""))
		var now := Factions.holder_of(factions, rn)
		if now == was:
			continue
		_fwas[rn] = now
		if was.is_empty():
			continue
		var line := Factions.line_for(factions, rn, was)
		if line.is_empty():
			continue
		var seat := _chief_seat(rn)
		if seat.is_empty():
			continue
		deposit_rumour(seat, {"text": line, "day": t, "from": seat, "kind": "frontier"})


func _chief_seat(region: String) -> String:
	## The best-ranked place in a region, ties broken by name so two Chronicles
	## that told the same story pick the same mouth.
	var best := ""
	var br := -1
	for p in places:
		var pd := p as Dictionary
		if String(pd.get("region", "")) != region:
			continue
		var rank := int(pd.get("rank", 0))
		var nm := String(pd.get("name", ""))
		if rank > br or (rank == br and nm < best):
			br = rank
			best = nm
	return best


static func season_at(day: float) -> int:
	## Mirrors Wind.phase_for_day / season_name, without needing Wind: one
	## season is 24 days, one year 96, and 0 is the first day of spring.
	return int(fposmod(day, DAYS_PER_SEASON * 4.0) / DAYS_PER_SEASON) % 4


func _weather_level(t: float) -> int:
	## The live sky when there is one. Without it — a headless suite, or the
	## editor before Weather is built — the Chronicle rolls its own from the
	## seed and the day, so the catalogue's weather-gated kinds still reach the
	## world instead of quietly never firing.
	## Only for the step that is actually NOW. A catch-up loop replaying a month
	## of sleep must not paint all thirty days with this afternoon's sky — and
	## the live Weather is `_rng`-driven, so letting it into a replayed step
	## would put a number in the save's future that the save cannot reproduce.
	if _weather != null and is_instance_valid(_weather) and "level" in _weather \
			and absf(t - days) <= STEP_HOURS / 24.0 * 1.5:
		return clampi(int(_weather.level), 0, 4)
	var d := int(floor(t))
	var u := _unit(_hash(world_seed, d, 4409), 0)
	var season := season_at(t)
	## Wetter in spring and autumn, hard and clear in winter. Same shape as
	## Weather.TRANSITIONS, coarsened to a day at a time.
	var wet := 0.42 if season == 0 or season == 2 else (0.30 if season == 1 else 0.22)
	if u < 1.0 - wet:
		return 0 if u < (1.0 - wet) * 0.55 else 1
	var v := (u - (1.0 - wet)) / maxf(wet, 1e-6)
	if v < 0.45:
		return 2
	return 3 if v < 0.85 else 4


## ============================== The bias pool =============================


func _decay_bias() -> void:
	## Exponential, on the step, so the half-life is the half-life whatever
	## size the caller's steps are. Rebuilt sorted every time: the dictionary's
	## key ORDER is part of what to_dict() serialises, and two Chronicles that
	## told the same story must serialise identically or the save round-trip
	## test is comparing insertion history instead of state.
	var k := pow(0.5, (STEP_HOURS / 24.0) / BIAS_HALFLIFE_DAYS)
	var keys: Array = bias.keys()
	keys.sort()
	var next := {}
	for tag in keys:
		var v := float(bias[tag]) * k
		if absf(v) >= BIAS_FLOOR:
			next[tag] = v
	bias = next


func pressure_at(pos: Vector3, tag: String) -> float:
	## How loaded this corner of the map is for one tag right now: the world's
	## own bias, plus what the nearest place has actually lived through inside
	## the rumour window. The spawn tables and the Incident Director read this.
	var p := float(bias.get(tag, 0.0))
	var near_place := nearest_place(pos, RUMOUR_SPREAD)
	if near_place.is_empty():
		return p
	var nm := String(near_place.get("name", ""))
	for ev in resolved:
		var e := ev as Dictionary
		if String(e.get("place", "")) != nm:
			continue
		if days - float(e.get("born", 0.0)) > RUMOUR_DAYS:
			continue
		var kind := ChronicleEvents.by_id(String(e.get("kind", "")))
		if (kind.get("tags", []) as Array).has(tag):
			p += 0.25
	## [factions] and finally WHERE YOU ARE STANDING. Until this line the
	## dominant term was map-wide: a bad raid at Freeport raised the goblin
	## pressure at the Allagash by the same amount in the same instant. A tag
	## that speaks for a claimant now reads high on that claimant's ground and
	## low off it, and a tag that speaks for nobody — bandits, unrest — is
	## exactly as loud everywhere, which is the point of them.
	p += Factions.pressure_bonus(factions, Factions.region_at(pos, REGION_ROSTER), tag)
	return p


## ================================ Firing ==================================


func _maybe_fire(n: int, t: float, hour: float, season: int, sky: int) -> void:
	if places.is_empty() or active.size() >= MAX_ACTIVE:
		return
	## ONE candidate place per step, chosen by hash rather than by sweeping all
	## fifty: fifty places x thirty-odd kinds every half hour is seventy
	## thousand weight lookups a game day, and the story is no better for it.
	## Forty-eight draws a day over fifty places touches about thirty of them,
	## so nowhere waits long and nowhere is guaranteed its turn.
	var pi := absi(_hash(world_seed, n, 1301)) % places.size()
	var place: Dictionary = places[pi]
	var ctx := {
		"hour": hour, "season": season, "weather": sky,
		"region": String(place.get("region", "")),
		"rank": int(place.get("rank", 0)),
		"alarm": float(place.get("alarm", 0.0)),
		"mood": float(place.get("mood", 0.5)),
		"stores": float(place.get("stores", 0.5)),
		"bias": bias,
	}
	## A place does not run the same story twice at once — the fold cannot be
	## raided while it is already being raided.
	var busy := {}
	for e in active:
		if String((e as Dictionary).get("place", "")) == String(place.get("name", "")):
			busy[String((e as Dictionary).get("kind", ""))] = true

	var weights: Array = []
	var total := 0.0
	for k in ChronicleEvents.KINDS:
		var kd := k as Dictionary
		if busy.has(String(kd.get("id", ""))):
			weights.append(0.0)
			continue
		var w := ChronicleEvents.weight_for(kd, ctx)
		weights.append(w)
		total += w
	if total <= 0.0:
		return

	## The busier a place's weather, season and mood make it, the likelier
	## something happens there — capped, so a perfect storm of modifiers cannot
	## turn one village into an event every half hour.
	var chance := minf(total * FIRE_GAIN, FIRE_CEIL)
	if _unit(_hash(world_seed, n, 5591), 0) >= chance:
		return

	var target := _unit(_hash(world_seed, n, 6113), 1) * total
	var acc := 0.0
	var chosen := -1
	for i in range(weights.size()):
		acc += float(weights[i])
		if target < acc:
			chosen = i
			break
	if chosen < 0:
		return
	_fire(ChronicleEvents.KINDS[chosen] as Dictionary, place, t, n, 0)


func _fire(kind: Dictionary, place: Dictionary, t: float, n: int, salt: int) -> void:
	if active.size() >= MAX_ACTIVE:
		return
	var band: Vector2 = kind.get("active", Vector2(6.0, 18.0))
	var u := _unit(_hash(world_seed, n, 7727 + salt), 2)
	var life := lerpf(band.x, band.y, u) / 24.0     ## game hours -> days
	var ev := {
		"uid": _uid,
		"kind": String(kind.get("id", "")),
		"place": String(place.get("name", "")),
		"pos": place.get("pos", Vector2.ZERO) as Vector2,
		"born": t,
		"ends": t + maxf(life, STEP_HOURS / 24.0),
		"state": "active",
		"outcome": "",
		"line": "",
	}
	_uid += 1
	active.append(ev)
	event_fired.emit(ev)


func _ctx_for(place: Dictionary, t: float) -> Dictionary:
	## The same context _maybe_fire builds, for anything that needs to ask
	## "could this kind happen here, now?" outside the firing loop.
	return {
		"hour": fposmod(t * 24.0, 24.0),
		"season": season_at(t),
		"weather": _weather_level(t),
		"region": String(place.get("region", "")),
		"rank": int(place.get("rank", 0)),
		"alarm": float(place.get("alarm", 0.0)),
		"mood": float(place.get("mood", 0.5)),
		"stores": float(place.get("stores", 0.5)),
		"bias": bias,
	}


func _busy_with(place: Dictionary, kind_id: String) -> bool:
	var nm := String(place.get("name", ""))
	for e in active:
		var ev := e as Dictionary
		if String(ev.get("place", "")) == nm and String(ev.get("kind", "")) == kind_id:
			return true
	return false


## =============================== Resolving ================================


func _resolve_due(t: float) -> void:
	var i := 0
	while i < active.size():
		var ev := active[i] as Dictionary
		if float(ev.get("ends", 0.0)) > t:
			i += 1
			continue
		active.remove_at(i)
		_resolve(ev, t)


func _resolve(ev: Dictionary, t: float) -> void:
	var kind := ChronicleEvents.by_id(String(ev.get("kind", "")))
	if kind.is_empty():
		return   ## a kind that was renamed out from under an old save: drop it
	var place := place_by_name(String(ev.get("place", "")))
	var roll := _unit(_hash(world_seed, int(ev.get("uid", 0)), 8837), 3)
	var out := ChronicleEvents.pick_outcome(kind, roll)
	if out.is_empty():
		return
	ev["state"] = "resolved"
	ev["outcome"] = String(out.get("id", ""))
	ev["line"] = String(out.get("line", "%s")) % String(ev.get("place", ""))

	## 1. the place's own numbers move
	if not place.is_empty():
		var deltas: Dictionary = out.get("place", {})
		for key in ["mood", "stores", "alarm", "watch"]:
			if deltas.has(key):
				place[key] = clampf(float(place.get(key, 0.0)) + float(deltas[key]), 0.0, 1.0)

	## 2. the world remembers the SHAPE of what happened
	var b: Dictionary = out.get("bias", {})
	for tag in b:
		bias[String(tag)] = float(bias.get(String(tag), 0.0)) + float(b[tag])
	## [factions] ...and WHERE it happened is written down too. The world-wide
	## pool above says what sort of year it is; this says whose ground it is.
	var epos: Vector2 = ev.get("pos", Vector2.ZERO)
	Factions.note(fpush, Factions.region_at(Vector3(epos.x, 0.0, epos.y), REGION_ROSTER), b)

	## 3. the news travels — here first, then as far as a day's walk
	_spread_rumour(ev, t)

	resolved.append(ev)
	while resolved.size() > RESOLVED_KEEP:
		resolved.pop_front()
	event_resolved.emit(ev)

	## 4. and one thing leads to another
	var spawn := String(out.get("spawn", ""))
	if not spawn.is_empty() and not place.is_empty():
		var next := ChronicleEvents.by_id(spawn)
		## A follow-on is a consequence, not an exemption. It still has to be
		## able to happen: the hunt does not go out at midnight in a storm
		## because a fold was lost, it goes out at first light. A spawn whose
		## own gates are shut is dropped — the fold was still lost.
		if not next.is_empty() and ChronicleEvents.weight_for(next, _ctx_for(place, t)) > 0.0 \
				and not _busy_with(place, spawn):
			_fire(next, place, t, int(ev.get("uid", 0)), 991)


func _spread_rumour(ev: Dictionary, t: float) -> void:
	var origin: Vector2 = ev.get("pos", Vector2.ZERO)
	var from := String(ev.get("place", ""))
	for p in places:
		var pd := p as Dictionary
		var d: float = (pd.get("pos", Vector2.ZERO) as Vector2).distance_to(origin)
		if d > RUMOUR_SPREAD:
			continue
		var rum: Array = pd.get("rumours", [])
		## A village does not tell you the same sentence twice. The same kind
		## can fire twice at the same place inside a rumour window and the
		## outcome lines are shared prose, so without this the board reads like
		## a stuck record rather than a week of news.
		var dupe := false
		for r in rum:
			if r is Dictionary and String((r as Dictionary).get("text", "")) == String(ev.get("line", "")):
				dupe = true
				break
		if dupe:
			continue
		rum.append({
			"text": String(ev.get("line", "")),
			"day": t,
			"from": from,
			"kind": String(ev.get("kind", "")),
		})
		while rum.size() > RUMOURS_PER_PLACE:
			rum.pop_front()


func _prune_rumours(t: float) -> void:
	var cutoff := t - RUMOUR_DAYS
	for p in places:
		var rum: Array = (p as Dictionary).get("rumours", [])
		var i := rum.size() - 1
		while i >= 0:
			var r: Variant = rum[i]
			if not (r is Dictionary) or float((r as Dictionary).get("day", -1e9)) < cutoff:
				rum.remove_at(i)
			i -= 1


func _drift(t: float) -> void:
	## The slow background the events push against. Without it a place that has
	## a bad week stays frightened and hungry for the rest of the game, which
	## is not a simulation, it is a scar. Rates are per step, so a season of
	## quiet is what it takes to come all the way back.
	var season := season_at(t)
	var k := STEP_HOURS / 24.0
	for p in places:
		var pd := p as Dictionary
		var watch := float(pd.get("watch", 0.2))
		## alarm cools, and a place with a real watch cools faster
		pd["alarm"] = clampf(lerpf(float(pd.get("alarm", 0.0)), 0.03, k * (0.5 + watch)), 0.0, 1.0)
		## mood drifts back toward workaday, faster when the stores are full
		var settle: float = 0.5 + 0.2 * float(pd.get("stores", 0.5))
		pd["mood"] = clampf(lerpf(float(pd.get("mood", 0.5)), settle, k * 0.35), 0.0, 1.0)
		## stores fill through the summer and empty through the winter — the
		## one place the calendar reaches into the sim on its own
		var store_rate := 0.010 if season == 1 else (0.014 if season == 2 else (-0.016 if season == 3 else 0.002))
		pd["stores"] = clampf(float(pd.get("stores", 0.5)) + store_rate * k, 0.0, 1.0)


## =============================== Reading it ===============================


func place_by_name(n: String) -> Dictionary:
	for p in places:
		if String((p as Dictionary).get("name", "")) == n:
			return p as Dictionary
	return {}


func nearest_place(pos: Vector3, within := 1200.0) -> Dictionary:
	## Flat distance: the map is a hundred kilometres wide and four hundred
	## metres tall, so height is noise here.
	var here := Vector2(pos.x, pos.z)
	var best: Dictionary = {}
	var bd := within
	for p in places:
		var d: float = (p as Dictionary).get("pos", Vector2.ZERO).distance_to(here)
		if d <= bd:
			bd = d
			best = p as Dictionary
	return best


func rumours_at(pos: Vector3, limit := 3) -> Array:
	## What they are saying HERE — the nearest place's own board, freshest
	## first. News does not pool in the empty map between two villages, which
	## is why this reads one place rather than everything within a radius.
	var p := nearest_place(pos, RUMOUR_SPREAD)
	if p.is_empty():
		return []
	var out: Array = []
	for r in p.get("rumours", []):
		if r is Dictionary:
			out.append(r)
	## Tiebroken on the text so the order is total: two rumours can land on the
	## same half-hour step, and "whatever sort_custom did with the tie" is not
	## a thing a save may depend on.
	out.sort_custom(func(a, b):
		if not is_equal_approx(float(a["day"]), float(b["day"])):
			return float(a["day"]) > float(b["day"])
		return String(a["text"]) < String(b["text"]))
	if out.size() > limit:
		out.resize(limit)
	return out


func events_near(pos: Vector3, radius: float) -> Array:
	## Everything still HAPPENING within reach — the Incident Director's whole
	## input. Resolved events are aftermath and live in `resolved`.
	var here := Vector2(pos.x, pos.z)
	var out: Array = []
	for e in active:
		var ev := e as Dictionary
		if (ev.get("pos", Vector2.ZERO) as Vector2).distance_to(here) <= radius:
			out.append(ev)
	return out


func sky_at(t: float) -> int:
	## [wayfarers] The weather the SIM believes in at day `t`, public so that
	## anything else running on this calendar reads the same sky the event
	## weights do. It is deliberately the same call the catch-up loop makes:
	## the live `Weather` is `_rng`-driven and only answers for the step that
	## is actually now, so a consumer that reached for `Weather.level` would
	## put a number in the save's future that the save cannot reproduce.
	return _weather_level(t)


func deposit_rumour(place_name: String, rum: Dictionary) -> bool:
	## [wayfarers] Word carried in by hand rather than spread by radius.
	##
	## `_spread_rumour` drops a line into every place within RUMOUR_SPREAD of
	## where it happened, which is a day's walk and no further. This is the
	## other way news travels: somebody walked it here. So the rumour keeps
	## its ORIGINAL day — it is two days old and must read as two days old,
	## whoever is telling it — and it is refused outright once it is past the
	## window `_prune_rumours` would delete it in, because arriving with news
	## the board would erase on the next step is not delivery.
	var text := String(rum.get("text", ""))
	if text.is_empty():
		return false
	var born := float(rum.get("day", days))
	if born < days - RUMOUR_DAYS:
		return false
	var p := place_by_name(place_name)
	if p.is_empty():
		return false
	var board: Array = p.get("rumours", [])
	for r in board:
		if r is Dictionary and String((r as Dictionary).get("text", "")) == text:
			return false
	board.append({
		"text": text,
		"day": born,
		"from": String(rum.get("from", "")),
		"kind": String(rum.get("kind", "")),
	})
	while board.size() > RUMOURS_PER_PLACE:
		board.pop_front()
	return true


func report() -> Dictionary:
	## A stable digest of the whole world, for the console, the tests and a
	## future tavern board. Everything in here is sorted or already ordered:
	## two Chronicles that told the same story must report the same string.
	var tags: Array = bias.keys()
	tags.sort()
	var pool := {}
	for t in tags:
		pool[t] = snappedf(float(bias[t]), 0.0001)
	var pl: Array = []
	for p in places:
		var pd := p as Dictionary
		pl.append("%s|%.3f|%.3f|%.3f|%.3f|%d" % [
			String(pd.get("name", "")),
			snappedf(float(pd.get("mood", 0.0)), 0.001),
			snappedf(float(pd.get("stores", 0.0)), 0.001),
			snappedf(float(pd.get("alarm", 0.0)), 0.001),
			snappedf(float(pd.get("watch", 0.0)), 0.001),
			(pd.get("rumours", []) as Array).size(),
		])
	var recent: Array = []
	var from := maxi(resolved.size() - 5, 0)
	for i in range(from, resolved.size()):
		recent.append(String((resolved[i] as Dictionary).get("line", "")))
	return {
		"day": snappedf(days, 0.0001),
		"season": int(season_at(days)),
		"steps": _steps,
		"active": active.size(),
		"resolved": resolved.size(),
		"places": places.size(),
		"bias": pool,
		"state": pl,
		"latest": recent,
	}


## ============================== Save / load ===============================


func to_dict() -> Dictionary:
	## Everything the sim cannot work out again for itself. The STEP COUNT is
	## in here on purpose: the rolls are hashes of (seed, step), so restoring
	## the count restores the FUTURE as well as the past — load a save twice
	## and the same caravan is overdue on the same road at the same hour.
	var pl: Array = []
	for p in places:
		var pd := (p as Dictionary).duplicate(true)
		pl.append(pd)
	var act: Array = []
	for e in active:
		act.append((e as Dictionary).duplicate(true))
	var res: Array = []
	for e in resolved:
		res.append((e as Dictionary).duplicate(true))
	var tags: Array = bias.keys()
	tags.sort()
	var pool := {}
	for t in tags:
		pool[t] = float(bias[t])
	return {
		"v": 1,
		"seed": world_seed,
		"hours": _hours,
		"steps": _steps,
		"uid": _uid,
		"bias": pool,
		"places": pl,
		"active": act,
		"resolved": res,
		"factions": _fdup(factions),
		"fpush": _fdup(fpush),
	}


func _fdup(src: Dictionary) -> Dictionary:
	## Sorted, because the key order is part of what a save round-trip compares.
	var names: Array = src.keys()
	names.sort()
	var out := {}
	for n in names:
		out[String(n)] = (src[String(n)] as Dictionary).duplicate()
	return out


func from_dict(d: Dictionary) -> void:
	## A save from another build, or none at all, must leave a booted world
	## standing rather than an empty one — an empty Chronicle is a world with
	## no places in it, and everything downstream would read that as "nowhere".
	if not _booted:
		boot()
	## Reset BEFORE the early return, not after it. World.apply_state moves
	## DayNight to the saved hour in the same frame as this call, so a
	## Chronicle that kept a stale `_last_clock` would read that jump as time
	## having passed and invent a month of history out of a save that predates
	## the Chronicle entirely — which is every save on disk today.
	_last_clock = -1.0
	if d.is_empty() or not d.has("places") or int(d.get("v", 1)) > 1:
		return
	world_seed = int(d.get("seed", world_seed))
	_hours = float(d.get("hours", 0.0))
	_steps = int(d.get("steps", 0))
	_uid = maxi(int(d.get("uid", 1)), 1)
	days = _hours / 24.0
	## OVERLAY, never replace. A save knows the places that existed when it was
	## written; the roster is the places that exist now. Replacing the list
	## outright means a place added to the bake — or one the fort builder
	## appends at runtime — never reaches an existing save, and a save whose
	## place list was empty would load as a world with nowhere in it.
	for p in (d.get("places", []) as Array):
		if not (p is Dictionary):
			continue
		var pd := (p as Dictionary).duplicate(true)
		var live := place_by_name(String(pd.get("name", "")))
		if live.is_empty():
			places.append(pd)
		else:
			live.merge(pd, true)
	## Re-sorted by name: _maybe_fire picks its candidate by index, so the order
	## of this array is part of the determinism contract.
	places.sort_custom(func(a, b): return String(a["name"]) < String(b["name"]))
	active.clear()
	for e in (d.get("active", []) as Array):
		if e is Dictionary:
			active.append((e as Dictionary).duplicate(true))
	resolved.clear()
	for e in (d.get("resolved", []) as Array):
		if e is Dictionary:
			resolved.append((e as Dictionary).duplicate(true))
	## [factions] The field and its pressure are state; the tables under them
	## are not, so they are rebuilt from the roster this build actually has and
	## only the numbers are overlaid. A save from before factions existed
	## leaves the world standing at rest rather than empty.
	_rebuild_factions()
	for rn in (d.get("factions", {}) as Dictionary):
		if factions.has(String(rn)):
			(factions[String(rn)] as Dictionary).merge(
				(d.get("factions", {}) as Dictionary)[rn] as Dictionary, true)
	for rn in (d.get("fpush", {}) as Dictionary):
		if fpush.has(String(rn)):
			(fpush[String(rn)] as Dictionary).merge(
				(d.get("fpush", {}) as Dictionary)[rn] as Dictionary, true)
	for r in _fland:
		_fwas[String(r)] = Factions.holder_of(factions, String(r))
	var pool: Dictionary = d.get("bias", {})
	var tags: Array = pool.keys()
	tags.sort()
	bias = {}
	for t in tags:
		bias[String(t)] = float(pool[t])


## ================================ Rolling =================================
## No RandomNumberGenerator anywhere in this file, on purpose. Every roll is a
## pure hash of (world_seed, step, salt), which is what lets a save restore the
## future and lets the suite run the same ten days three different ways and get
## the same ten days back. If you ever need "one more random number here",
## reach for a new salt, never for a stateful generator.


static func _hash(a: int, b: int, c: int) -> int:
	var h := a * 374761393 + b * 668265263 + c * 1274126177
	h = (h ^ (h >> 13)) * 1103515245
	h = h ^ (h >> 16)
	h = h * 2246822519
	h = h ^ (h >> 15)
	return h


static func _unit(h: int, k: int) -> float:
	## 0..1, masked rather than modulo'd off a signed int so a negative hash
	## cannot fold onto a narrow band of the range.
	var x := (h + k * 2654435761) * 1103515245
	x = x ^ (x >> 15)
	x = x * 668265263
	x = x ^ (x >> 17)
	return float(x & 0x3FFFFFFF) / 1073741824.0
