class_name Wayfarers
extends Node

## ============================ THINGS THAT WALK ============================
##
## The Road Net (`b5ee3f3`) laid 58 roads over 51 places and nothing has ever
## used one. This puts people on them.
##
## A BAND is a named traveller — a pedlar, a carter, a courier, a drover, a
## pilgrim, a charcoal-burner, a tithe-man — making a fixed CIRCUIT of three to
## five places over and over, for the rest of the game. It has a seat it came
## from, a pace its trade can manage, an hour it sets out and an hour it stops,
## and a position on the net measured in metres travelled since the start of
## the circuit.
##
## Three properties are the whole point, and each of them is a test:
##
## 1. **It happens whether or not you are there.** The sim is coarse — half a
##    game hour a step, the Chronicle's own cadence — and holds nothing but a
##    float per band. Nothing is a scene node until you are within 190 m of it.
##    A band you met at Bangor on Tuesday is genuinely most of the way to
##    Bucksport on Wednesday because it walked there, not because it was
##    re-rolled when you looked.
##
## 2. **News rides with them.** Arriving at a place, a band takes the freshest
##    thing being said there and carries it; arriving at the NEXT place, it
##    puts it down. That is the first thing in Myrkfell that moves a rumour
##    further than `Chronicle.RUMOUR_SPREAD`, and it moves it along a real
##    road at a real walking pace. A hamlet four days out finally hears.
##
## 3. **The weather empties the roads.** Pace is multiplied by the sky the
##    Chronicle believes in — the same deterministic reading its own event
##    weights use, never the live `_rng` — and a level-4 gale stops a band
##    where it stands. WORLD queue #3's first customer on the road.
##
## Deterministic, like everything downstream of the Chronicle: no
## RandomNumberGenerator, no `randf`, no clock in the build. Every roll is a
## hash of (seed, salt, index). The roster comes from the NET's nodes, which
## `RoadNet.build` already sorted by name for exactly this reason — a band
## whose circuit reshuffled when the fort was founded would be a different
## person wearing the same name.
##
## Adds NO input binding of any kind. `WayfarerTests._t_no_input` asserts that
## against this file's own source rather than against this sentence.


static var inst: Wayfarers = null

signal band_arrived(band: Dictionary, place: String)
signal band_met(band: Dictionary)
signal band_held(band: Dictionary, level: int)


## ============================== The numbers ==============================

## The sim's step. Half a game hour, matching Chronicle.STEP_HOURS, so a
## catch-up after a sleep meters out at the same rate the world's events do.
const STEP_HOURS := 0.5
## Steps drained per frame. A month of sleep is 1 440 steps and doing them all
## on one frame is a visible hitch.
const CATCHUP_STEPS := 24
## How much history a fresh sim runs before you see it, so the roads are not
## uniformly empty at dawn on day one with every band standing on its own
## doorstep.
const PRIME_DAYS := 1.5

## How far a plain walker gets in one full day of walking. NOT a real-world
## figure: Myrkfell's places are ~700 m apart and `Chronicle.RUMOUR_SPREAD` —
## the distance the Chronicle calls a day's walk — is 1 400 m. Matching that
## constant is what makes "he left Bangor at breakfast and is at Bucksport by
## dusk" true in the same world the rumour radius is true in.
const PACE_DAY := 1400.0

## Bands on the map. Twenty over fifty-one places is roughly one every two and
## a half villages, which reads as a travelled country without turning the
## roads into a procession.
const MAX_BANDS := 20
## Candidates weighed at each step of building a circuit.
const CIRCUIT_LOOK := 5

## And no more than this many of any one trade. Without it the weights alone
## put THIRTEEN pedlars of the twenty on the map and not one pilgrim, charcoal
## burner or tithe-man -- because the pedlar is the only trade that seats at
## every rank and it simply out-scores the rest everywhere. Twenty pedlars is
## a spawn table; four pedlars, three drovers and a tithe-man is a country.
const KIND_CAP := 4

## Meeting. 55 m is close enough that you have plainly seen each other and far
## enough that it fires before you walk through them.
const MEET_RADIUS := 55.0
## And they do not greet you twice in one morning.
const REMEET_DAYS := 0.75

## Manifestation, mirroring the Incident Director's hysteresis: staged inside
## the near radius, struck outside the far one, and never on the same frame.
const STAGE_RADIUS := 190.0
const STRIKE_RADIUS := 260.0
const MAX_STAGED := 4
const SCAN_SECONDS := 1.3
const GROUND_PROBE := 400.0

## The sky level at which a band stops walking altogether.
const HOLD_LEVEL := 4

## How far ahead the heading is sampled, in metres of road.
const LOOK_AHEAD := 3.0

const SALT_SEAT := 7331
const SALT_KIND := 8677
const SALT_NAME := 9137
const SALT_CIRCUIT := 4211
const SALT_BODY := 5527


## The trades. `pace` multiplies PACE_DAY; `depart`/`halt` are the hours
## between which this trade is on the road; `stops` is how many places its
## circuit visits; `wants` is the rank it steers its circuit toward; `seats`
## are the ranks it can come from; `party` is how many figures walk with it.
const KINDS: Array = [
	{"id": "pedlar", "pace": 1.00, "depart": 7.5, "halt": 19.5, "stops": 4,
		"wants": 1, "seats": [0, 1, 2], "party": 1, "prop": "basket", "weight": 1.00},
	{"id": "carter", "pace": 0.72, "depart": 6.5, "halt": 18.5, "stops": 3,
		"wants": 2, "seats": [1, 2], "party": 2, "prop": "cart", "weight": 0.85},
	{"id": "courier", "pace": 1.55, "depart": 5.0, "halt": 21.0, "stops": 4,
		"wants": 2, "seats": [2], "party": 1, "prop": "", "weight": 0.90},
	{"id": "drover", "pace": 0.55, "depart": 7.0, "halt": 18.0, "stops": 3,
		"wants": 0, "seats": [0, 1], "party": 2, "prop": "fleece", "weight": 0.70},
	{"id": "pilgrim", "pace": 0.85, "depart": 6.0, "halt": 19.0, "stops": 5,
		"wants": 1, "seats": [0, 1, 2], "party": 1, "prop": "cloth", "weight": 0.55},
	{"id": "charcoal-burner", "pace": 0.80, "depart": 8.0, "halt": 17.5, "stops": 3,
		"wants": 0, "seats": [0], "party": 1, "prop": "crate", "weight": 0.60},
	{"id": "tithe-man", "pace": 0.95, "depart": 8.5, "halt": 17.0, "stops": 4,
		"wants": 0, "seats": [2], "party": 2, "prop": "", "weight": 0.50},
]

## Names. Deliberately plain and of the place — a pedlar called Aldous Rye is a
## man; a pedlar called Aeltharion is a fantasy novel.
const GIVEN: Array = [
	"Aldous", "Bertram", "Cuthbert", "Dunstan", "Edric", "Fulke", "Godwin",
	"Hamo", "Ivo", "Jocelyn", "Kenric", "Leofric", "Martel", "Nicholas",
	"Osbert", "Peirs", "Randal", "Simon", "Thurstan", "Ulric", "Wulfric",
	"Agnes", "Beatrix", "Cecily", "Edith", "Gunnora", "Hawise", "Isolde",
	"Joan", "Maud", "Petronilla", "Rohese", "Sybil", "Winifred",
]
const BYNAME: Array = [
	"Rye", "Ashdown", "Barrow", "Coombe", "Drewe", "Elmer", "Fenn", "Garth",
	"Hollis", "Kern", "Lound", "Mears", "Nye", "Orme", "Pike", "Quarles",
	"Rowe", "Salter", "Thorne", "Vance", "Weald", "Yare",
]


## ================================ State ==================================

var world_seed := 20260909
var enabled := true

## Collaborators. Every one of them nullable, and the sim runs with none of
## them — the suite builds a net, hands it over and never makes a tree.
var net: Object = null          ## a RoadNet, duck-typed on five method names
var chron: Object = null        ## a Chronicle, duck-typed on three
var feed: Object = null         ## a RumourFeed, duck-typed on `offer`
var player: Node3D = null
var clock: Node = null          ## a DayNight: `day` + `hour`
var sky_fn: Callable = Callable()   ## test hook: (day) -> int, 0..4

var bands: Array = []           ## of band Dictionaries, see `_make_band`

var days := 0.0                 ## the sim's own clock, float game days
var _hours := 0.0
var _steps := 0
var _ran := 0                   ## steps actually executed, for profiling
var _booted := false
var _last_clock := -1.0
var _net_print := 0             ## the net fingerprint these circuits were cut for
var _by_id: Dictionary = {}
var _scan_t := 0.0
var _ground: Object = null
var _staged: Dictionary = {}    ## id -> Node3D
var _build_ms := 0.0

## For the suite's index section. `_locate` binary-searches the leg table; a
## linear walk would answer every question correctly and prove nothing, which
## is the trap the Road Net's cell grid fell into (2026-09-09 00:00). This
## counts legs actually examined so the suite can assert the search NARROWS
## rather than merely that the answer is right.
var last_examined := 0

var met_total := 0
var carried_total := 0          ## rumours picked up
var delivered_total := 0        ## rumours put down somewhere new


## =============================== Lifecycle ===============================


func _ready() -> void:
	boot()


func _exit_tree() -> void:
	if inst == self:
		inst = null


func boot(force := false) -> void:
	## Idempotent by contract: World calls it, `_ready` calls it, and the suite
	## calls it three times in a row.
	if inst == null or not is_instance_valid(inst):
		inst = self
	if is_inside_tree() and not is_in_group("wayfarers"):
		add_to_group("wayfarers")
	if _booted and not force:
		## A net that arrived after the first boot — or was rebuilt when the
		## fort appeared — invalidates every circuit cut against the old one.
		## Silent otherwise, which is the dangerous kind.
		if _net_ready() and _fingerprint() != _net_print:
			_rebuild()
		return
	_booted = true
	_rebuild()


func bind_world(w: Node) -> void:
	## Duck-typed on every hook, for the same reason the Incident Director and
	## the Road Net are: this class must come up inside the full game and
	## inside a stripped project with three scripts in it.
	if w == null or not is_instance_valid(w):
		return
	if w.has_method("roadnet"):
		var rn: Variant = w.call("roadnet")
		if rn is Object and is_instance_valid(rn as Object):
			net = rn as Object
	if net == null and is_inside_tree():
		var g := get_tree().get_first_node_in_group("roads")
		if g != null and is_instance_valid(g):
			net = g
	## A collaborator that is the wrong kind of object is worse than none —
	## the Director's rule, and for the same reason: a half-answering net
	## produces bands that walk through lakes rather than no bands at all.
	if net != null and not _net_ok(net):
		net = null

	if w.has_method("chronicle"):
		var c: Variant = w.call("chronicle")
		if c is Object and is_instance_valid(c as Object):
			chron = c as Object
	if chron == null and is_inside_tree():
		var cg := get_tree().get_first_node_in_group("chronicle")
		if cg != null and is_instance_valid(cg):
			chron = cg
	if chron != null and not chron.has_method("rumours_at"):
		chron = null

	if w.has_method("rumours"):
		var rf: Variant = w.call("rumours")
		if rf is Object and is_instance_valid(rf as Object):
			feed = rf as Object
	if feed == null and is_inside_tree():
		var fg := get_tree().get_first_node_in_group("rumours")
		if fg != null and is_instance_valid(fg):
			feed = fg
	if feed != null and not feed.has_method("offer"):
		feed = null

	var p: Variant = w.get("_player")
	if p is Node3D:
		player = p as Node3D
	var dn: Variant = w.get("_daynight")
	if dn is Node:
		clock = dn as Node
	if w.has_method("_surface_y") or w.has_method("surface_y"):
		_ground = w
	boot()


func _net_ok(o: Object) -> bool:
	return o.has_method("point_on_edge") and o.has_method("route") \
			and o.has_method("edge") and o.has_method("place_pos") \
			and o.has_method("fingerprint")


func _net_ready() -> bool:
	if net == null or not is_instance_valid(net):
		return false
	if net.has_method("ready") and not bool(net.call("ready")):
		return false
	return true


func _fingerprint() -> int:
	if not _net_ready():
		return 0
	return int(net.call("fingerprint"))


func ready() -> bool:
	return _booted and not bands.is_empty()


## ============================ Cutting the round ==========================


func _rebuild() -> void:
	var t0 := Time.get_ticks_usec()
	bands.clear()
	_by_id.clear()
	_clear_bodies()
	_net_print = _fingerprint()
	if not _net_ready():
		_build_ms = 0.0
		return
	var rows := _places()
	if rows.size() < 2:
		_build_ms = 0.0
		return
	for b in _seats(rows):
		var band := _make_band(b["place"] as Dictionary, String(b["kind"]), int(b["n"]), rows)
		if band.is_empty():
			continue
		bands.append(band)
		_by_id[String(band["id"])] = band
	_build_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func _places() -> Array:
	## The net's own node list — already sorted by name by `RoadNet.build`,
	## which is the only reason a circuit is stable across a save.
	var out: Array = []
	var ns: Variant = net.get("nodes")
	if not (ns is Array):
		return out
	for n in (ns as Array):
		if n is Dictionary:
			out.append(n as Dictionary)
	return out


func _seats(rows: Array) -> Array:
	## Which places send someone out, and of what trade.
	##
	## Every (place, trade) pair that is legal at all is SCORED and the top
	## MAX_BANDS taken, rather than walking the roster and stopping when full:
	## the roster is alphabetical, so a first-come rule would put every band in
	## Maine between Ashland and Camden and leave the whole east empty.
	var cand: Array = []
	for i in rows.size():
		var p := rows[i] as Dictionary
		var rank := int(p.get("rank", 0))
		var nm := String(p.get("name", ""))
		for ki in KINDS.size():
			var k := KINDS[ki] as Dictionary
			if not (rank in (k["seats"] as Array)):
				continue
			var h := _hash(world_seed, i * 31 + ki, SALT_SEAT)
			## Weighted by the trade and by how big the place is: a market town
			## puts more people on the road than a hamlet, which is most of what
			## makes the traffic read as a map rather than as a sprinkle.
			var score := _unit(h, 1) * float(k["weight"]) * (0.62 + 0.24 * float(rank))
			cand.append({"score": score, "place": p, "kind": String(k["id"]), "name": nm, "n": ki})
	cand.sort_custom(func(a, b):
		if not is_equal_approx(float(a["score"]), float(b["score"])):
			return float(a["score"]) > float(b["score"])
		## Tiebroken to a TOTAL order on (name, kind): two candidates can score
		## identically and "whatever sort_custom did with the tie" is not a
		## thing a save may depend on.
		if String(a["name"]) != String(b["name"]):
			return String(a["name"]) < String(b["name"])
		return String(a["kind"]) < String(b["kind"]))
	var out: Array = []
	var seen: Dictionary = {}
	var per_kind: Dictionary = {}
	for c in cand:
		if out.size() >= MAX_BANDS:
			break
		## One band per place. Two men setting out from the same hamlet on the
		## same morning is a caravan, and this is not that feature.
		var nm := String(c["name"])
		if seen.has(nm):
			continue
		## And no more than KIND_CAP of any trade, so the roads carry a mix
		## rather than whichever trade happens to score best everywhere.
		var kd := String(c["kind"])
		if int(per_kind.get(kd, 0)) >= KIND_CAP:
			continue
		seen[nm] = true
		per_kind[kd] = int(per_kind.get(kd, 0)) + 1
		out.append(c)
	return out


func _make_band(seat: Dictionary, kind_id: String, ki: int, rows: Array) -> Dictionary:
	var k := kind_of(kind_id)
	var seat_name := String(seat.get("name", ""))
	var circuit := _circuit(seat_name, k, rows, ki)
	if circuit.size() < 2:
		## A place the net could not route out of. Rule 2 of the Road Net says
		## that should be impossible, but a band is not the place to find out.
		return {}
	var b := {
		"id": "%s@%s" % [kind_id, seat_name],
		"name": _name_for(seat_name, ki),
		"kind": kind_id,
		"seat": seat_name,
		"circuit": circuit,
		"along": 0.0,
		"len": 0.0,
		"legs": [],
		"stops": [],
		"at": seat_name,
		"last": seat_name,
		"carried": {},
		"holding": false,
		"held": 0.0,
		"met": 0,
		"met_day": -1000.0,
	}
	_lay_legs(b)
	if float(b["len"]) <= 1.0:
		return {}
	return b


func _circuit(seat: String, k: Dictionary, rows: Array, ki: int) -> Array:
	## Grown outward from the seat one place at a time: of the CIRCUIT_LOOK
	## nearest unused places BY ROUTE LENGTH — not by straight distance, because
	## a village across a lake is not close — take the one whose rank is nearest
	## what this trade wants, tiebroken by a hash so two carters out of
	## neighbouring towns do not walk the same four places.
	var want := int(k.get("wants", 0))
	var stops := clampi(int(k.get("stops", 3)), 2, 6)
	var circuit: Array = [seat]
	var used: Dictionary = {seat: true}
	var cur := seat
	for step in range(stops - 1):
		## Straight-line shortlist FIRST, routes second. `route` is a Dijkstra
		## over the whole graph; asking it about all fifty places for every
		## step of every band's circuit is four thousand of them at world
		## start, and the Road Net's own build is only 900 ms. The straight
		## line is a lower bound on the road, so the true nearest is always
		## inside a shortlist twice as long as the one we keep.
		var here: Vector2 = net.call("place_pos", cur)
		var shortlist: Array = []
		for r in rows:
			var rd := r as Dictionary
			var nm := String(rd.get("name", ""))
			if used.has(nm) or nm.is_empty():
				continue
			shortlist.append({"name": nm, "s": here.distance_to(rd.get("pos", Vector2.ZERO) as Vector2),
				"rank": int(rd.get("rank", 0))})
		shortlist.sort_custom(func(a, b):
			if not is_equal_approx(float(a["s"]), float(b["s"])):
				return float(a["s"]) < float(b["s"])
			return String(a["name"]) < String(b["name"]))
		if shortlist.size() > CIRCUIT_LOOK * 2:
			shortlist.resize(CIRCUIT_LOOK * 2)
		var near: Array = []
		for c0 in shortlist:
			var nm := String((c0 as Dictionary)["name"])
			var rt: Dictionary = net.call("route", cur, nm)
			if not bool(rt.get("ok", false)):
				continue
			near.append({"name": nm, "d": float(rt.get("length", 0.0)),
				"rank": int((c0 as Dictionary)["rank"])})
		if near.is_empty():
			break
		near.sort_custom(func(a, b):
			if not is_equal_approx(float(a["d"]), float(b["d"])):
				return float(a["d"]) < float(b["d"])
			return String(a["name"]) < String(b["name"]))
		if near.size() > CIRCUIT_LOOK:
			near.resize(CIRCUIT_LOOK)
		var best := ""
		var bs := -1.0
		for j in near.size():
			var c := near[j] as Dictionary
			var fit := 1.0 - 0.30 * float(absi(int(c["rank"]) - want))
			var jitter := 0.35 * _unit(_hash(world_seed, ki * 97 + step * 13 + j, SALT_CIRCUIT), 3)
			var s := fit + jitter
			if s > bs:
				bs = s
				best = String(c["name"])
		if best.is_empty():
			break
		circuit.append(best)
		used[best] = true
		cur = best
	return circuit


func _lay_legs(b: Dictionary) -> void:
	## The circuit expanded into a flat list of ROADS in travel order, closed
	## back to the seat, with the cumulative metres before each one and the
	## metre-mark of every place along the way.
	var circuit: Array = b["circuit"]
	var legs: Array = []
	var stops: Array = []
	var run := 0.0
	var n := circuit.size()
	for i in n:
		var from := String(circuit[i])
		var to := String(circuit[(i + 1) % n])
		var rt: Dictionary = net.call("route", from, to)
		if not bool(rt.get("ok", false)):
			continue
		var names: Array = rt.get("places", [])
		var eids: Array = rt.get("edges", [])
		for j in eids.size():
			var e := int(eids[j])
			var ed: Dictionary = net.call("edge", e)
			if ed.is_empty():
				continue
			var fwd := String(ed.get("from", "")) == String(names[j])
			var ln := float(ed.get("len", 0.0))
			legs.append({"e": e, "fwd": fwd, "len": ln, "cum": run})
			run += ln
		## The metre-mark of the place this leg ARRIVES at. Recorded after the
		## roads, so the last entry is the whole circuit and wraps to zero.
		stops.append({"place": to, "at": run})
	b["legs"] = legs
	b["stops"] = stops
	b["len"] = run


func _name_for(seat: String, ki: int) -> String:
	var h := _hash(world_seed, seat.hash(), SALT_NAME + ki)
	var g := String(GIVEN[int(_unit(h, 1) * GIVEN.size()) % GIVEN.size()])
	var s := String(BYNAME[int(_unit(h, 2) * BYNAME.size()) % BYNAME.size()])
	return "%s %s" % [g, s]


static func kind_of(id: String) -> Dictionary:
	for k in KINDS:
		if String((k as Dictionary)["id"]) == id:
			return k as Dictionary
	return KINDS[0] as Dictionary


## ================================ The clock ==============================


func _process(delta: float) -> void:
	if not enabled:
		return
	_tick_clock()
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = SCAN_SECONDS
		sense()
	_drive_bodies()


func _tick_clock() -> void:
	## The game's clock, never the frame delta — a sleep must walk the week
	## that passed, not the two real seconds it took. Same shape as
	## `Chronicle._process`, deliberately: two sims reading the same sky must
	## reach the same day or a band arrives with news from next Tuesday.
	if clock == null or not is_instance_valid(clock):
		return
	if not ("day" in clock and "hour" in clock):
		return
	var now := float(clock.day) + float(clock.hour) / 24.0
	if _last_clock < 0.0:
		_last_clock = now
		_adopt(now)
		return
	var d := now - _last_clock
	_last_clock = now
	if d > 0.0:
		## Backwards time is not a season of history. Thirty days is the
		## ceiling on one handover.
		_hours += minf(d, 30.0) * 24.0
		days = _hours / 24.0
	_run_steps(CATCHUP_STEPS)


func _adopt(now: float) -> void:
	## DayNight boots at day 30, hour 19.7 while a fresh sim sits at day 0. Left
	## alone, every `depart`/`halt` gate would be judged against a clock the sky
	## has never heard of and the roads would be busy at midnight.
	var drift := now * 24.0 - _hours
	if absf(drift) <= 24.0:
		return
	_hours = now * 24.0
	days = _hours / 24.0
	var want := int(floor(_hours / STEP_HOURS + 1e-9))
	_steps = maxi(want - int(PRIME_DAYS * 24.0 / STEP_HOURS), 0)
	_run_steps(20000)


func advance(hours: float, budget := 20000) -> void:
	## The pure simulation step, and the only way time passes in here.
	if hours <= 0.0:
		return
	_hours += hours
	days = _hours / 24.0
	_run_steps(budget)


func _run_steps(budget: int) -> void:
	var want := int(floor(_hours / STEP_HOURS + 1e-9))
	var left := budget
	while _steps < want and left > 0:
		_step(_steps)
		_steps += 1
		_ran += 1
		left -= 1


func _step(n: int) -> void:
	var t := float(n) * STEP_HOURS / 24.0
	var hour := fposmod(t * 24.0, 24.0)
	var level := sky_at(t)
	for b in bands:
		_step_band(b as Dictionary, t, hour, level)


func sky_at(t: float) -> int:
	## The sky the CHRONICLE believes in, not the live one. The Chronicle's own
	## `_weather_level` refuses the live `Weather` for any step that is not
	## right now, for exactly this reason: a replayed month must not be painted
	## with this afternoon's rain, and a `_rng`-driven reading is a number in
	## the save's future the save cannot reproduce.
	if sky_fn.is_valid():
		return clampi(int(sky_fn.call(t)), 0, 4)
	if chron != null and is_instance_valid(chron) and chron.has_method("sky_at"):
		return clampi(int(chron.call("sky_at", t)), 0, 4)
	return 0


static func pace_for(level: int) -> float:
	## What the weather does to a day on the road. A shower is an inconvenience;
	## a gale is a barn door and a wait.
	match clampi(level, 0, 4):
		0, 1:
			return 1.0
		2:
			return 0.82
		3:
			return 0.55
	return 0.0


func _step_band(b: Dictionary, t: float, hour: float, level: int) -> void:
	var k := kind_of(String(b["kind"]))
	var dep := float(k["depart"])
	var halt := float(k["halt"])
	var was_holding := bool(b.get("holding", false))
	if hour < dep or hour >= halt:
		## Night. Standing where the light failed — at an inn if the day's walk
		## reached one, in a hedge if it did not, and either way exactly where
		## you will find them at dawn.
		b["holding"] = false
		return
	var mult := pace_for(level)
	if mult <= 0.0:
		b["holding"] = true
		b["held"] = float(b.get("held", 0.0)) + STEP_HOURS
		if not was_holding:
			band_held.emit(b, level)
		return
	b["holding"] = false
	var speed := PACE_DAY * float(k["pace"]) / maxf(halt - dep, 0.5)
	_advance_band(b, speed * STEP_HOURS * mult, t)


func _advance_band(b: Dictionary, d: float, t: float) -> void:
	var total := float(b["len"])
	if total <= 1.0 or d <= 0.0:
		return
	var guard := 0
	while d > 0.0 and guard < 128:
		guard += 1
		var nxt := _next_stop(b)
		## `_next_stop` answers with a mark STRICTLY ahead, or with the whole
		## circuit when there is none, and `along` is always folded below the
		## circuit -- so the gap here is always positive and there is nothing
		## to wrap. The defensive branch that used to sit here could not be
		## reached, so it could not be tested, so it was a lie about where the
		## safety lives. It lives in `_next_stop`, and the mutation that proves
		## it is `stop-not-strictly-ahead`.
		var gap := nxt - float(b["along"])
		if d < gap:
			b["along"] = fposmod(float(b["along"]) + d, total)
			b["at"] = ""
			return
		b["along"] = fposmod(nxt, total)
		d -= gap
		_arrive(b, t)


func _next_stop(b: Dictionary) -> float:
	## The metre-mark of the next place ahead, strictly ahead, wrapping.
	var total := float(b["len"])
	var along := float(b["along"])
	var best := total
	for s in (b["stops"] as Array):
		var at := float((s as Dictionary)["at"])
		if at > along + 0.001 and at < best:
			best = at
	return best


func stop_at(b: Dictionary, along: float) -> String:
	for s in (b["stops"] as Array):
		if absf(float((s as Dictionary)["at"]) - along) <= 0.01:
			return String((s as Dictionary)["place"])
	## The wrap: the last stop's mark is the whole circuit, and zero is the
	## same place seen from the other side.
	if along <= 0.01 and not (b["stops"] as Array).is_empty():
		return String(((b["stops"] as Array)[-1] as Dictionary)["place"])
	return ""


func _arrive(b: Dictionary, t: float) -> void:
	var place := stop_at(b, float(b["along"]))
	if place.is_empty():
		return
	b["at"] = place
	if String(b.get("last", "")) == place:
		return
	## Put down what you were carrying BEFORE picking anything up, or a band
	## would arrive, take the local news and immediately deliver it back to the
	## place it came from.
	_deposit(b, place, t)
	_take(b, place, t)
	b["last"] = place
	band_arrived.emit(b, place)


## ============================ Carrying the news ==========================


func _deposit(b: Dictionary, place: String, t: float) -> void:
	var c: Dictionary = b.get("carried", {})
	if c.is_empty() or String(c.get("text", "")).is_empty():
		return
	if String(c.get("from", "")) == place:
		b["carried"] = {}
		return
	if chron != null and is_instance_valid(chron) and chron.has_method("deposit_rumour"):
		## The rumour keeps its ORIGINAL day, never today's. "Two days back at
		## Bangor" is what a carried rumour is; re-dating it on arrival would
		## make every second-hand story sound like it happened this morning,
		## and the age words are the one place the sim's calendar is legible.
		if bool(chron.call("deposit_rumour", place, c)):
			delivered_total += 1
	b["carried"] = {}


func _take(b: Dictionary, place: String, _t: float) -> void:
	if chron == null or not is_instance_valid(chron):
		return
	var pos := _place_pos3(place)
	var rum: Array = chron.call("rumours_at", pos, 1)
	if rum.is_empty() or not (rum[0] is Dictionary):
		return
	var r := (rum[0] as Dictionary).duplicate(true)
	r["from"] = place
	b["carried"] = r
	carried_total += 1


func _place_pos3(place: String) -> Vector3:
	if not _net_ready():
		return Vector3.ZERO
	var p: Vector2 = net.call("place_pos", place)
	return Vector3(p.x, 0.0, p.y)


## ============================== Where they are ===========================


func live_along(b: Dictionary) -> float:
	## The band's position between two sim steps. The step is half a game hour
	## and DayNight runs a game hour in fifty real seconds, so without this a
	## staged traveller would teleport twenty-five seconds' worth of road every
	## twenty-five seconds. The fraction is derived from the clock, not
	## accumulated from frames, so it is the same number on a machine running
	## at 8 FPS as on one running at 200.
	var total := float(b["len"])
	if total <= 1.0:
		return 0.0
	var frac := clampf((_hours - float(_steps) * STEP_HOURS) / STEP_HOURS, 0.0, 1.0)
	if frac <= 0.0:
		return float(b["along"])
	var k := kind_of(String(b["kind"]))
	var hour := fposmod(days * 24.0, 24.0)
	if hour < float(k["depart"]) or hour >= float(k["halt"]) or bool(b.get("holding", false)):
		return float(b["along"])
	var speed := PACE_DAY * float(k["pace"]) / maxf(float(k["halt"]) - float(k["depart"]), 0.5)
	var mult := pace_for(sky_at(days))
	return fposmod(float(b["along"]) + speed * STEP_HOURS * mult * frac, total)


func _locate(b: Dictionary, along: float) -> Dictionary:
	## Which road, and how far along it. Binary search over the leg table's
	## cumulative marks.
	##
	## A LINEAR walk would answer every question here correctly and prove
	## nothing about the table — the exact trap `RoadNet.nearest_road`'s brute
	## fallback set on 2026-09-09, where a cell grid that was never populated
	## returned right answers to a green suite. `last_examined` is what lets
	## the suite assert the search NARROWS instead of only that it is right.
	var legs: Array = b["legs"]
	last_examined = 0
	if legs.is_empty():
		return {}
	var want := clampf(along, 0.0, maxf(float(b["len"]) - 0.001, 0.0))
	var lo := 0
	var hi := legs.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		last_examined += 1
		if float((legs[mid] as Dictionary)["cum"]) <= want:
			lo = mid
		else:
			hi = mid - 1
	last_examined += 1
	var leg := legs[lo] as Dictionary
	var ln := maxf(float(leg["len"]), 0.001)
	var u := clampf((want - float(leg["cum"])) / ln, 0.0, 1.0)
	return {"leg": lo, "e": int(leg["e"]), "fwd": bool(leg["fwd"]), "t": u}


func locate_brute(b: Dictionary, along: float) -> Dictionary:
	## The slow answer, for the suite to hold the fast one to account. Not used
	## by anything in the game — deliberately NOT a fallback inside `_locate`,
	## because a fallback is exactly what hid three index defects last time.
	var legs: Array = b["legs"]
	if legs.is_empty():
		return {}
	var want := clampf(along, 0.0, maxf(float(b["len"]) - 0.001, 0.0))
	var pick := 0
	for i in legs.size():
		if float((legs[i] as Dictionary)["cum"]) <= want:
			pick = i
	var leg := legs[pick] as Dictionary
	var ln := maxf(float(leg["len"]), 0.001)
	return {"leg": pick, "e": int(leg["e"]), "fwd": bool(leg["fwd"]),
		"t": clampf((want - float(leg["cum"])) / ln, 0.0, 1.0)}


func point_at(b: Dictionary, along: float) -> Vector2:
	if not _net_ready():
		return Vector2.ZERO
	var loc := _locate(b, along)
	if loc.is_empty():
		return Vector2.ZERO
	var t := float(loc["t"])
	## `point_on_edge` runs from the edge's own `from` to its `to`. Half the
	## legs are walked the other way.
	if not bool(loc["fwd"]):
		t = 1.0 - t
	return net.call("point_on_edge", int(loc["e"]), t)


func where_is(id: String) -> Dictionary:
	var b: Dictionary = _by_id.get(id, {})
	if b.is_empty():
		return {}
	return where(b)


func where(b: Dictionary) -> Dictionary:
	var a := live_along(b)
	var p := point_at(b, a)
	var ahead := point_at(b, fposmod(a + LOOK_AHEAD, maxf(float(b["len"]), 1.0)))
	var dir := ahead - p
	if dir.length() < 0.001:
		dir = Vector2(0.0, 1.0)
	return {
		"id": String(b["id"]),
		"name": String(b["name"]),
		"kind": String(b["kind"]),
		"pos": p,
		"dir": dir.normalized(),
		"along": a,
		"at": String(b.get("at", "")),
		"last": String(b.get("last", "")),
		"holding": bool(b.get("holding", false)),
	}


func near(pos: Vector3, radius: float) -> Array:
	## Every band within reach, nearest first.
	var here := Vector2(pos.x, pos.z)
	var out: Array = []
	for b in bands:
		var bd := b as Dictionary
		var d := point_at(bd, live_along(bd)).distance_to(here)
		if d <= radius:
			out.append({"band": bd, "d": d})
	out.sort_custom(func(a, c):
		if not is_equal_approx(float(a["d"]), float(c["d"])):
			return float(a["d"]) < float(c["d"])
		return String((a["band"] as Dictionary)["id"]) < String((c["band"] as Dictionary)["id"]))
	return out


## ============================== Meeting one ==============================


func sense() -> void:
	## Everything the player's proximity does. Split out from `_process` so the
	## suite can drive it with no tree, no frame and no delta.
	if player == null or not is_instance_valid(player):
		if is_inside_tree():
			var p := get_tree().get_first_node_in_group("player")
			if p is Node3D:
				player = p as Node3D
		if player == null:
			return
	meet_at(player.global_position)
	_restage(player.global_position)


func meet_at(pos: Vector3) -> Dictionary:
	## The nearest band inside MEET_RADIUS says its piece — once, and then not
	## again for REMEET_DAYS, because a pedlar who greets you every one and a
	## third seconds is not a person.
	var found := near(pos, MEET_RADIUS)
	if found.is_empty():
		return {}
	var b := (found[0] as Dictionary)["band"] as Dictionary
	if days - float(b.get("met_day", -1000.0)) < REMEET_DAYS:
		return {}
	var line := greeting(b, days)
	var took := true
	if feed != null and is_instance_valid(feed):
		## `offer` refuses while a menu is up rather than spending the line
		## behind it — the freeze-don't-drop rule the feed was built on. A
		## refusal leaves `met_day` alone so the next scan tries again.
		took = bool(feed.call("offer", line, String(b["name"]), _carried_kind(b), _carried_day(b)))
	if not took:
		return {}
	b["met"] = int(b.get("met", 0)) + 1
	b["met_day"] = days
	met_total += 1
	band_met.emit(b)
	return b


func _carried_kind(b: Dictionary) -> String:
	var c: Dictionary = b.get("carried", {})
	return String(c.get("kind", ""))


func _carried_day(b: Dictionary) -> float:
	var c: Dictionary = b.get("carried", {})
	return float(c.get("day", days))


func greeting(b: Dictionary, now: float) -> String:
	## What they actually say. If they are carrying news, they lead with it and
	## say where they had it — that attribution is the whole reason a carried
	## rumour is different from one you overheard in a village. If not, they say
	## where they are going, which is a fact the schedule actually knows.
	var c: Dictionary = b.get("carried", {})
	var text := String(c.get("text", ""))
	if not text.is_empty():
		var from := String(c.get("from", ""))
		if from.is_empty():
			return text
		if int(b.get("met", 0)) > 0:
			return "Still on the road, then. %s — I had it at %s." % [text, from]
		return "%s I had it at %s." % [text, from]
	var going := _bound_for(b)
	var known := int(b.get("met", 0)) > 0
	if bool(b.get("holding", false)):
		return "No walking in this. I'll sit it out and go on to %s after." % going
	var hour := fposmod(now * 24.0, 24.0)
	if known:
		return "You again. %s before dark, if the road allows." % going
	if hour < 10.0:
		return "Early start — %s by noon, God willing." % going
	if hour > 17.0:
		return "Light's going. I'll not make %s tonight." % going
	return "Bound for %s, if you're asking." % going


func _bound_for(b: Dictionary) -> String:
	## The next place on the circuit ahead of where they stand.
	var nxt := _next_stop(b)
	var nm := stop_at(b, nxt)
	if nm.is_empty() and not (b["stops"] as Array).is_empty():
		nm = String(((b["stops"] as Array)[0] as Dictionary)["place"])
	return nm if not nm.is_empty() else String(b["seat"])


## ============================== On the road ==============================


func _restage(pos: Vector3) -> void:
	## Stage what is close, strike what is not, and never both in one pass for
	## one band — the Director's hysteresis, and for the same reason: a band
	## walking the boundary would otherwise rebuild itself every scan.
	if not is_inside_tree():
		return
	var here := Vector2(pos.x, pos.z)
	for id in _staged.keys():
		var b: Dictionary = _by_id.get(String(id), {})
		if b.is_empty() or point_at(b, live_along(b)).distance_to(here) > STRIKE_RADIUS:
			_strike(String(id))
	for row in near(pos, STAGE_RADIUS):
		if _staged.size() >= MAX_STAGED:
			break
		var b := (row as Dictionary)["band"] as Dictionary
		var id := String(b["id"])
		if _staged.has(id):
			continue
		var body := _build_body(b)
		if body == null:
			continue
		add_child(body)
		_staged[id] = body


func _strike(id: String) -> void:
	var n: Variant = _staged.get(id, null)
	if n is Node and is_instance_valid(n as Node):
		(n as Node).queue_free()
	_staged.erase(id)


func _clear_bodies() -> void:
	for id in _staged.keys():
		_strike(String(id))
	_staged.clear()


func staged_ids() -> Array:
	var out: Array = _staged.keys()
	out.sort()
	return out


func _drive_bodies() -> void:
	## Bodies follow the SIM, they do not have one of their own. A staged
	## traveller is a read of `live_along` every frame and nothing else — which
	## is why walking away and back cannot desynchronise it, and why a band you
	## never staged is in exactly the place it would have been if you had.
	for id in _staged.keys():
		var body: Variant = _staged.get(id, null)
		if not (body is Node3D) or not is_instance_valid(body as Node3D):
			_staged.erase(id)
			continue
		var b: Dictionary = _by_id.get(String(id), {})
		if b.is_empty():
			_strike(String(id))
			continue
		var w := where(b)
		var p: Vector2 = w["pos"]
		var n3 := body as Node3D
		n3.global_position = Vector3(p.x, _ground_y(p), p.y)
		var dir: Vector2 = w["dir"]
		n3.rotation.y = atan2(dir.x, dir.y)
		## The walk. Keyed on DISTANCE COVERED, not on wall time, so a band held
		## by a gale stands still instead of marching on the spot — and so the
		## legs cannot drift out of step with the ground they are crossing.
		var swing := 0.0
		if not bool(w["holding"]) and String(w["at"]).is_empty():
			swing = sin(float(w["along"]) * 2.6) * 0.42
		for c in n3.get_children():
			if c is Node3D and String((c as Node3D).name).begins_with("Walk"):
				(c as Node3D).rotation.x = swing * (1.0 if String((c as Node3D).name).ends_with("L") else -1.0)
		var lamp := n3.get_node_or_null("Lamp")
		if lamp is OmniLight3D:
			(lamp as OmniLight3D).visible = _is_dark()


func _is_dark() -> bool:
	var hour := fposmod(days * 24.0, 24.0)
	return hour < 6.2 or hour > 19.4


func _ground_y(flat: Vector2) -> float:
	## Duck-typed, and null is the normal case: the headless suite has no
	## terrain and every band in it walks honestly at y = 0.
	if _ground == null or not is_instance_valid(_ground):
		return 0.0
	var probe := Vector3(flat.x, GROUND_PROBE, flat.y)
	var y := 0.0
	if _ground.has_method("_surface_y"):
		y = float(_ground.call("_surface_y", probe))
	elif _ground.has_method("surface_y"):
		y = float(_ground.call("surface_y", probe))
	if is_nan(y) or is_inf(y):
		return 0.0
	return y


func _build_body(b: Dictionary) -> Node3D:
	var k := kind_of(String(b["kind"]))
	var root := Node3D.new()
	root.name = "Band_%s" % String(b["id"]).replace("@", "_").replace(" ", "_")
	var h := _hash(world_seed, String(b["id"]).hash(), SALT_BODY)
	var party := clampi(int(k.get("party", 1)), 1, 3)
	for i in party:
		var off := Vector3(-0.6 + 1.2 * float(i), 0.0, -0.9 * float(i))
		_figure(root, off, _unit(h, i + 1), i)
	var prop := String(k.get("prop", ""))
	if not prop.is_empty():
		var spec := {"kind": prop, "arg": "" if prop != "cloth" else "pilgrim"}
		var node: Node3D = IncidentKit.build_prop(spec, 0, _unit(h, 9))
		if node != null:
			## `build_prop` gives everything a random yaw, which is right for
			## wreckage on a field and wrong for a handcart being pushed.
			node.rotation.y = 0.0
			node.position = Vector3(0.0, 0.0, -1.35)
			if prop == "basket" or prop == "crate" or prop == "fleece":
				node.position = Vector3(0.32, 0.95, -0.45)
				node.scale = Vector3.ONE * 0.72
			root.add_child(node)
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.position = Vector3(0.34, 1.15, 0.28)
	lamp.light_color = Color(1.0, 0.76, 0.44)
	lamp.light_energy = 1.35
	lamp.omni_range = 7.5
	lamp.shadow_enabled = false
	lamp.visible = _is_dark()
	root.add_child(lamp)
	return root


func _figure(root: Node3D, at: Vector3, u: float, idx: int) -> void:
	## A person, in seven boxes. Per-vertex shaded through IncidentKit's own
	## material helper so a traveller and the crate on their back are lit the
	## same way as everything else on the ground.
	var cloth: Color = IncidentKit.PALETTE["sack"]
	if idx == 1:
		cloth = IncidentKit.PALETTE["earth"]
	cloth = cloth.lerp(Color(0.30, 0.28, 0.24), 0.25 * u)
	var skin := Color(0.62, 0.48, 0.38)
	var mc := IncidentKit._mat(cloth)
	var ms := IncidentKit._mat(skin)
	var body := Node3D.new()
	body.name = "Fig%d" % idx
	body.position = at
	root.add_child(body)
	## Torso, hood, head.
	IncidentKit._add(body, IncidentKit._box(0.44, 0.66, 0.26), mc, Vector3(0, 1.06, 0))
	IncidentKit._add(body, IncidentKit._box(0.30, 0.26, 0.28), mc, Vector3(0, 1.50, -0.02))
	IncidentKit._add(body, IncidentKit._box(0.20, 0.18, 0.18), ms, Vector3(0, 1.44, 0.08))
	## Arms.
	IncidentKit._add(body, IncidentKit._box(0.12, 0.52, 0.14), mc, Vector3(-0.28, 1.02, 0))
	IncidentKit._add(body, IncidentKit._box(0.12, 0.52, 0.14), mc, Vector3(0.28, 1.02, 0))
	## Legs, hung off pivots the walk cycle turns.
	for side in ["L", "R"]:
		var hip := Node3D.new()
		hip.name = "Walk%d%s" % [idx, side]
		hip.position = at + Vector3(-0.13 if side == "L" else 0.13, 0.72, 0.0)
		root.add_child(hip)
		IncidentKit._add(hip, IncidentKit._box(0.15, 0.72, 0.16),
				IncidentKit._mat(cloth.darkened(0.22)), Vector3(0, -0.36, 0))


## ================================ Reading ================================


func report() -> Dictionary:
	var rows: Array = []
	for b in bands:
		var bd := b as Dictionary
		rows.append("%s|%s|%s|%.1f|%s|%d" % [String(bd["id"]), String(bd["name"]),
			String(bd["kind"]), float(bd["along"]), String(bd.get("last", "")),
			int(bd.get("met", 0))])
	return {
		"bands": bands.size(),
		"days": days,
		"steps": _steps,
		"ran": _ran,
		"staged": _staged.size(),
		"met": met_total,
		"carried": carried_total,
		"delivered": delivered_total,
		"build_ms": _build_ms,
		"print": _net_print,
		"digest": rows,
	}


func band_by_id(id: String) -> Dictionary:
	return _by_id.get(id, {})


func road_metres() -> float:
	var t := 0.0
	for b in bands:
		t += float((b as Dictionary)["len"])
	return t


## ================================= Saving ================================


func to_dict() -> Dictionary:
	## Only what cannot be worked out again. The circuits, the legs and the
	## names are a pure function of the net and the seed, so they are rebuilt
	## rather than stored — and `print` is what tells a load whether the net it
	## is being restored into is the net those circuits were cut for.
	var rows: Array = []
	for b in bands:
		var bd := b as Dictionary
		rows.append({
			"id": String(bd["id"]),
			"along": float(bd["along"]),
			"at": String(bd.get("at", "")),
			"last": String(bd.get("last", "")),
			"carried": (bd.get("carried", {}) as Dictionary).duplicate(true),
			"met": int(bd.get("met", 0)),
			"met_day": float(bd.get("met_day", -1000.0)),
			"held": float(bd.get("held", 0.0)),
		})
	return {
		"v": 1, "seed": world_seed, "print": _net_print,
		"hours": _hours, "steps": _steps,
		"met": met_total, "carried": carried_total, "delivered": delivered_total,
		"bands": rows,
	}


func from_dict(d: Dictionary) -> void:
	if d.is_empty() or int(d.get("v", 1)) > 1:
		return
	world_seed = int(d.get("seed", world_seed))
	_hours = float(d.get("hours", 0.0))
	_steps = int(d.get("steps", 0))
	days = _hours / 24.0
	_last_clock = -1.0
	met_total = int(d.get("met", 0))
	carried_total = int(d.get("carried", 0))
	delivered_total = int(d.get("delivered", 0))
	## Cut the circuits fresh, then pour the saved state into them by id. A
	## save made against a different net — the fort was founded, the roster
	## grew — restores what still matches by name and quietly drops what does
	## not, rather than putting a band on a road that is not there.
	_rebuild()
	for r in (d.get("bands", []) as Array):
		if not (r is Dictionary):
			continue
		var rd := r as Dictionary
		var b: Dictionary = _by_id.get(String(rd.get("id", "")), {})
		if b.is_empty():
			continue
		b["along"] = fposmod(float(rd.get("along", 0.0)), maxf(float(b["len"]), 1.0))
		b["at"] = String(rd.get("at", ""))
		b["last"] = String(rd.get("last", b["seat"]))
		var c: Variant = rd.get("carried", {})
		b["carried"] = (c as Dictionary).duplicate(true) if c is Dictionary else {}
		b["met"] = int(rd.get("met", 0))
		b["met_day"] = float(rd.get("met_day", -1000.0))
		b["held"] = float(rd.get("held", 0.0))
	_booted = true


## ================================= Hashing ===============================


static func _hash(a: int, b: int, c: int) -> int:
	var h := a * 374761393 + b * 668265263 + c * 1274126177
	h = (h ^ (h >> 13)) * 1103515245
	h = h ^ (h >> 16)
	h = h * 2246822519
	h = h ^ (h >> 15)
	return h


static func _unit(h: int, k: int) -> float:
	var x := (h + k * 2654435761) * 1103515245
	x = x ^ (x >> 15)
	x = x * 668265263
	x = x ^ (x >> 17)
	return float(x & 0x3FFFFFFF) / 1073741824.0
