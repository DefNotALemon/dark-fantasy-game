class_name Crofts
extends Node

## ===========================================================================
## THE CROFTS — somebody lives out here, and you can read it from the road.
##
## Fifty-one places, fifty-eight roads and twenty people walking them, and the
## whole hundred kilometres between the villages was still empty ground. The
## Chronicle simulates settlements as NUMBERS; the Incident Director stages
## things that HAPPENED. Neither of them puts an ordinary household in front
## of you doing an ordinary Tuesday.
##
## This is that. A croft is a smallholding seated off a road, out of sight of
## the village it belongs to, and everything it does is a QUERY rather than a
## script: the hearth is lit because the household is awake, the beasts are in
## because it is raining, the washing is on the line because the sky was clear
## at eight and it is soaked on it because the sky was not clear at noon.
##
## FIVE RULES this file will not break:
##
##   1. **The day is a pure function.** `routine_at(croft, day, sky, season,
##      state)` reads nothing but its arguments — no node, no clock, no RNG,
##      no `self`. Every observable beat comes out of it. That is what makes
##      "a gale at ten in the morning bars the shutters" a fixture in the
##      suite rather than something you stand in a field and wait for, and it
##      is why the visual half can be a dumb reader of a dictionary.
##   2. **It is deterministic and order-independent.** Seats are cut from the
##      road net in name-sorted edge order and hashed off `world_seed`, so a
##      fort founded at runtime cannot reshuffle who lives where — the same
##      rule the Road Net keeps and for the same reason.
##   3. **Only what genuinely persists is state.** The woodpile, what is on
##      the washing line, and how long the household is barred in. Those
##      three are saved. Everything else is derived and is NOT saved, because
##      a second copy of a derived thing is a second thing that can go stale.
##   4. **Weather and season are the same table for everyone.** Sky levels are
##      `Weather.Level` (CLEAR 0 · OVERCAST 1 · DRIZZLE 2 · RAIN 3 · STORM 4)
##      and the sky is the one the CHRONICLE believes in, never the live
##      `_rng`-driven `Weather` — the Wayfarers' rule, and breaking it would
##      put a number in the save's future that the save cannot reproduce.
##   5. **Nothing is a scene node until you are close.** A croft two valleys
##      away is a dictionary and a float. Bodies are built on the scan and
##      driven from the sim every frame, so walking away and back cannot
##      desynchronise one, and a croft you never staged is doing exactly what
##      it would have been doing if you had.
##
## THE CONSEQUENCE THAT PERSISTS. The woodpile is the point of the whole
## economy. A hearth burns stores every hour it is lit and a quarter of that
## banked overnight, and winter burns it near twice as fast as spring. The
## only way stores go UP is a household hour spent at the woodpile, and autumn
## is the season whose work table is full of them. So an autumn the household
## spent barred indoors — because the Chronicle said there were wolves about,
## or men — is a winter with no smoke over that chimney. You will not be told
## this. You will walk past in February and the roof will be cold.
##
## Wired up by World.gd (tools/patch_crofts.py), AFTER the Road Net and the
## Chronicle, because `bind_world` reaches for both and a collaborator that
## does not exist yet binds as null and stays null all session:
##     _crofts = Crofts.new(); add_child(_crofts); _crofts.bind_world(self)
## Read it with:  World.crofts().near(player.global_position, 600.0)
##
## A node added to `root` from SceneTree._init() never gets `_ready()`, which
## is how StepAudio was caught out on 2026-09-05 — so `boot()` is an explicit,
## idempotent setup call the headless suite can make for itself.
##
## This file contains no key handling of any kind and adds no dev binding.
## That claim is asserted against this source in CroftTests, not in a ledger
## line, because a shadowed dev binding is round-blocking in this project.
## ===========================================================================

## Fired the first time a household bars itself in for a scare it has just
## heard about. `reason` carries the pressure that did it.
signal croft_shut(croft: Dictionary, reason: String)
## Fired the first time a hearth goes cold for want of fuel, and again only
## after it has been warm in between. The interesting one.
signal croft_cold(croft: Dictionary)


# =============================== the world =================================

## Weather.Level, mirrored rather than imported: this file has to parse in a
## project with no Weather.gd in it at all. Same rule Firepit keeps.
const SKY_CLEAR := 0
const SKY_OVERCAST := 1
const SKY_DRIZZLE := 2
const SKY_RAIN := 3
const SKY_STORM := 4

## Chronicle.DAYS_PER_SEASON, mirrored for the same reason.
const DAYS_PER_SEASON := 24.0

const STEP_HOURS := 0.5
const CATCHUP_STEPS := 240
## How much history a fresh world walks before you first see it, so the very
## first croft you meet already has a woodpile rather than an empty yard.
const PRIME_DAYS := 3.0

# ------------------------------------------------------------------ seating
## MEASURED against the real net, not guessed: 57 roads, median 615 m, longest
## 1 592 m. A first pass at 1 750 m per croft seated exactly nothing and the
## probe said so before a single assertion was written, which is the only
## reason these are the numbers they are.
## A road shorter than MIN_ROAD_M has no room for a yard clear of both ends;
## one longer than SPACING_M has room for a second household.
const MIN_ROAD_M := 500.0
const SPACING_M := 1000.0
const MAX_PER_EDGE := 2
const MAX_CROFTS := 44
## Nobody builds in the village and nobody builds in the middle of nowhere
## either: a seat must be this far from both ends of its road.
const CLEAR_OF_PLACE := 190.0
const T_MIN := 0.14
const T_MAX := 0.86
## How far off the road the yard sits. Close enough to read at a glance,
## far enough that the road does not run through the plot.
const OFF_MIN := 26.0
const OFF_MAX := 52.0
## How much higher the far side of the road has to be before the household
## builds there instead. Probed at the yard's OWN offset, not at some token
## step: a first pass sampled nine metres either way, which on a one-in-twenty
## slope is under a metre of difference, so the check never fired once and the
## suite said so.
const SIDE_MARGIN := 1.0

# ------------------------------------------------------------- the household
const RISE_BEFORE_DAWN := 0.55
const RISE_SPREAD := 0.80
const BED_AFTER_DUSK := 1.45
const BED_SPREAD := 0.70
const BANK_BEFORE_BED := 0.35
const FIRST_CHORE := 0.90
const LAST_CHORE := 0.85
const MEAL_FROM := 12.2
const MEAL_TO := 13.0
const LAMP_MARGIN := 0.15

## Beasts out: any sky up to and including drizzle, and not in the dark.
const FIELD_MAX_SKY := SKY_DRIZZLE
const STOCK_OUT_AFTER := 1.10
const STOCK_IN_BEFORE := 0.90
## Winter turns them out for a few hours at midday and only on a clear one.
const WINTER_OUT_FROM := 10.0
const WINTER_OUT_TO := 14.5

## Washing goes out on a clear or merely grey morning, never worse.
const WASH_MAX_SKY := SKY_OVERCAST
const WASH_HANG_AFTER := 1.60
const WASH_IN_BEFORE := 1.20
## The sky that actually soaks a line of washing before they get to it.
## Fetching it in takes one sim step -- half a game hour -- which is the whole
## window a shower has to catch them in.
const SOAK_SKY := SKY_RAIN
## Drying hours a soaked line needs before they will hang a fresh one.
const DRY_HOURS := 9.0

## Outdoor work is driven under cover at rain and indoors at a storm.
const WORK_IN_SKY := SKY_RAIN
const OUTDOOR: Array = ["plot", "wood", "well"]

# ------------------------------------------------------------ the woodpile
const STORE_MAX := 320.0
const STORE_START := 150.0
const BURN_LIT := 1.00
const BURN_BANKED := 0.25
## Spring · summer · autumn · winter. TUNED AGAINST A SIMULATED YEAR, not
## chosen: the first pass left fifteen of twenty-six hearths cold by the last
## day of winter, which makes a cold roof the default rather than the thing
## that tells you something happened to that household. The shape these buy
## is: spring gains a little, summer is flat, AUTUMN IS THE YEAR — it fills a
## bare pile to the cap in about fifteen working days — and winter spends a
## little over two hundred. A household that keeps its autumn ends winter
## with a quarter of its pile. One that loses nine or ten autumn days to a
## scare does not, and goes cold in the last fortnight of winter.
const SEASON_BURN: Array = [1.00, 0.55, 1.15, 1.60]
const GATHER_BASE := 5.4
const SEASON_GATHER: Array = [1.65, 0.75, 1.55, 0.85]
const WOOD_MAX := 9

# --------------------------------------------------------------- the alarm
const ALARM_TAGS: Array = ["raid", "beast", "wolf", "war"]
const SHUT_PRESSURE := 0.55
const SHUT_DAYS := 1.6

# --------------------------------------------------------------- the yard
const STAGE_RADIUS := 300.0
const STRIKE_RADIUS := 420.0
const MAX_STAGED := 4
const SCAN_SECONDS := 1.1
const GROUND_PROBE := 600.0
## Close enough that you would notice the state of the place in passing.
const NOTICE_M := 165.0
## How much of the meadow a household keeps down. Wide enough to reach the
## plot, the woodpile and the beasts' corner, all of which stood invisible in
## waist-high grass on this feature's first screenshot.
const YARD_MOW_M := 17.0

# --------------------------------------------------------------- the hash
const SALT_SEAT := 0x9E3779B1
const SALT_SIDE := 0x85EBCA6B
const SALT_NAME := 0xC2B2AE35
const SALT_KIND := 0x27D4EB2F
const SALT_JIT := 0x165667B1
const SALT_BODY := 0x2545F491

## What the household grows and what it keeps. `stock` is how many beasts
## stand in the field, `plot` whether there is a crop at all.
const KINDS: Dictionary = {
	"croft":    {"stock": 2, "plot": true,  "byre": true,  "wall": 5.2},
	"steading": {"stock": 4, "plot": true,  "byre": true,  "wall": 6.4},
	"shieling": {"stock": 3, "plot": false, "byre": false, "wall": 4.2},
}

## The work of the year. One station per waking hour, cycled — so a household
## moves through its day instead of standing at one spot until dusk.
const WORK_TABLE: Array = [
	["plot", "byre", "plot", "well", "plot", "wood"],   ## spring — ploughing
	["plot", "plot", "well", "byre", "plot", "wood"],   ## summer — hay
	["plot", "wood", "plot", "wood", "byre", "well"],   ## autumn — harvest, stocking
	["wood", "byre", "wood", "in",   "byre", "well"],   ## winter — splitting
]
const SHIELING_TABLE: Array = [
	["byre", "well", "wood", "byre", "well", "wood"],
	["byre", "byre", "well", "wood", "byre", "well"],
	["wood", "byre", "wood", "well", "wood", "byre"],
	["wood", "byre", "in",   "wood", "byre", "well"],
]

## Surnames off the same coast the places are named for. Deliberately this
## file's own list rather than a reach into Wayfarers: two systems sharing a
## private table is two systems that break together.
const SURNAMES: Array = [
	"Alder", "Bagley", "Coffin", "Crowell", "Dorr", "Eldridge", "Files",
	"Gott", "Hallett", "Hersey", "Ingalls", "Joy", "Knowlton", "Leavitt",
	"Merrow", "Norwood", "Osgood", "Pillsbury", "Quimby", "Rand", "Sawtelle",
	"Thurlow", "Urann", "Varney", "Wescott", "Yeaton",
]


## The live instance, found the way Chronicle and the Road Net find
## themselves — never assumed to exist, because a headless test builds
## without one.
static var inst: Crofts = null

var enabled := true
var world_seed := 20260910

var crofts: Array = []            ## of croft Dictionaries, see _seat()
var state: Dictionary = {}        ## croft id -> {stores, wash, dry_h, shut_until, ...}

var days := 0.0

var net: Object = null            ## RoadNet, duck-typed
var chron: Object = null          ## Chronicle, duck-typed
var feed: Object = null           ## RumourFeed, duck-typed
var player: Node3D = null
var clock: Node = null            ## DayNight

var _ground: Object = null
var _booted := false
var _net_print := 0
var _by_id: Dictionary = {}
var _staged: Dictionary = {}      ## id -> Node3D
var _hours := 0.0
var _steps := 0
var _ran := 0
var _last_clock := -1.0
var _scan_t := 0.0
var _said: Dictionary = {}        ## "id|summary" -> true
var _mown: Dictionary = {}        ## yard key -> true, so a yard is cut once
var _build_ms := 0.0


# ============================== lifecycle ==================================

static func get_crofts(from: Node) -> Crofts:
	if inst != null and is_instance_valid(inst):
		return inst
	if from != null and from.is_inside_tree():
		var n := from.get_tree().get_first_node_in_group("crofts")
		if n is Crofts:
			inst = n as Crofts
			return inst
	return null


func _ready() -> void:
	boot()


func _exit_tree() -> void:
	if inst == self:
		inst = null


func boot(force := false) -> void:
	## Idempotent by contract: World calls it, `_ready` calls it, and the
	## suite calls it three times in a row.
	if inst == null or not is_instance_valid(inst):
		inst = self
	if is_inside_tree() and not is_in_group("crofts"):
		add_to_group("crofts")
	if _booted and not force:
		## A net that arrived after the first boot — or was rebuilt when the
		## fort appeared — invalidates every seat cut against the old one.
		## Silent otherwise, which is the dangerous kind.
		if _net_ready() and _fingerprint() != _net_print:
			_rebuild()
		return
	_booted = true
	_rebuild()


func bind_world(w: Node) -> void:
	## Duck-typed on every hook, for the same reason the Road Net and the
	## Wayfarers are: this class must come up inside the full game and inside
	## a stripped test project with three scripts in it.
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
	## a half-answering net seats crofts in lakes rather than seating none.
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
	if chron != null and not chron.has_method("pressure_at"):
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
	return o.has_method("point_on_edge") and o.has_method("edge") \
			and o.has_method("place_pos") and o.has_method("fingerprint")


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
	return _booted and not crofts.is_empty()


# ============================== the seating ================================

func _rebuild() -> void:
	var t0 := Time.get_ticks_usec()
	crofts.clear()
	_by_id.clear()
	_clear_bodies()
	_net_print = _fingerprint()
	if _net_ready():
		var ranks := _ranks()
		var rows := _edge_rows()
		for row in rows:
			if crofts.size() >= MAX_CROFTS:
				break
			var e := int((row as Dictionary)["e"])
			var ed: Dictionary = net.call("edge", e)
			if ed.is_empty():
				continue
			var length := float(ed.get("len", 0.0))
			var a := String(ed.get("from", ""))
			var b := String(ed.get("to", ""))
			var rank_sum := int(ranks.get(a, 0)) + int(ranks.get(b, 0))
			var n := _seats_on(a, b, rank_sum, length)
			for k in n:
				if crofts.size() >= MAX_CROFTS:
					break
				var c := _seat(e, k, n, a, b, length)
				if c.is_empty():
					continue
				crofts.append(c)
				_by_id[String(c["id"])] = c
		_name_pass()
	## State outlives a rebuild for any croft that survived it, and is dropped
	## for any that did not — the same contract `from_dict` keeps.
	for id in state.keys():
		if not _by_id.has(String(id)):
			state.erase(id)
	for c in crofts:
		_ensure_state(String((c as Dictionary)["id"]))
	_build_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	if _hours <= 0.0:
		_hours = PRIME_DAYS * 24.0
		days = PRIME_DAYS
		_steps = 0
		_run_steps(int(PRIME_DAYS * 24.0 / STEP_HOURS) + 4)


func _edge_rows() -> Array:
	## Edges in a NAME-SORTED order, never in net index order. A fort founded
	## at runtime appends a place, the net renumbers, and a seating that had
	## walked the edges by index would move every household on the map.
	var rows: Array = []
	var count := 0
	var arr: Variant = net.get("edges")
	if arr is Array:
		count = (arr as Array).size()
	for e in count:
		var ed: Dictionary = net.call("edge", e)
		if ed.is_empty():
			continue
		var a := String(ed.get("from", ""))
		var b := String(ed.get("to", ""))
		var key := a + " " + b
		if b < a:
			key = b + " " + a
		rows.append({"e": e, "key": key})
	rows.sort_custom(func(x, y): return String(x["key"]) < String(y["key"]))
	return rows


func _ranks() -> Dictionary:
	var out: Dictionary = {}
	var arr: Variant = net.get("nodes")
	if arr is Array:
		for n in (arr as Array):
			if n is Dictionary:
				out[String((n as Dictionary).get("name", ""))] = int((n as Dictionary).get("rank", 0))
	return out


func _seats_on(a: String, b: String, rank_sum: int, length: float) -> int:
	## How many households this road carries. Length sets the ceiling; the
	## rank of the two ends sets how likely each of them is to be taken, so
	## the trunk between two towns is lived along and a track between two
	## hamlets in the County usually is not.
	## Only a long enough road has room for a yard clear of both villages.
	if length < MIN_ROAD_M:
		return 0
	var cap := clampi(2 if length >= SPACING_M else 1, 0, MAX_PER_EDGE)
	var lean := 0.38 + 0.13 * float(clampi(rank_sum, 0, 4))
	var key := (a + "|" + b).hash()
	var n := 0
	for k in cap:
		if _unit(_hash(world_seed, key, SALT_SEAT + k), k + 1) < lean:
			n += 1
	return n


func _seat(e: int, k: int, of_n: int, a: String, b: String, length: float) -> Dictionary:
	var id := "c%d#%d" % [e, k]
	var h := _hash(world_seed, (a + "|" + b + "|" + str(k)).hash(), SALT_SEAT)
	## Spread the seats along the usable middle of the road rather than
	## letting two land on top of each other.
	var lo := T_MIN
	var hi := T_MAX
	if length > 0.0:
		lo = maxf(T_MIN, CLEAR_OF_PLACE / length)
		hi = minf(T_MAX, 1.0 - CLEAR_OF_PLACE / length)
	if hi - lo < 0.04:
		return {}
	var band := (hi - lo) / float(maxi(of_n, 1))
	var t := lo + band * (float(k) + 0.18 + 0.64 * _unit(h, 1))
	t = clampf(t, lo, hi)
	var road: Vector2 = net.call("point_on_edge", e, t)
	var dir := _dir_at(e, t)
	var nrm := Vector2(-dir.y, dir.x)
	var off := OFF_MIN + (OFF_MAX - OFF_MIN) * _unit(h, 2)
	var side := 1 if _unit(_hash(world_seed, id.hash(), SALT_SIDE), 3) < 0.5 else -1
	side = _drier_side(road, nrm, off, side)
	var pos := road + nrm * (float(side) * off)
	var kind := _kind_for(h, off)
	return {
		"id": id,
		## Provisional. `_name_pass` resolves it against the whole roster, so
		## that two households cannot end up with the same surname.
		"name": "%s's %s" % [_name_for(h), "croft" if kind != "shieling" else "shieling"],
		"name_i": int(_unit(h, 7) * float(SURNAMES.size())) % SURNAMES.size(),
		"kind": kind,
		"edge": e,
		"t": t,
		"side": side,
		"off": off,
		"pos": pos,
		"road": road,
		"face": -nrm * float(side),
		"from": a,
		"to": b,
		"jit": _unit(h, 4),
		"hour_key": 7.0 + 9.0 * _unit(h, 5),
	}


func _dir_at(e: int, t: float) -> Vector2:
	## The road's heading at `t`, by finite difference on arclength, so the
	## yard sits square to the track it fronts rather than square to the
	## straight line between two villages.
	var eps := 0.012
	var p0: Vector2 = net.call("point_on_edge", e, maxf(t - eps, 0.0))
	var p1: Vector2 = net.call("point_on_edge", e, minf(t + eps, 1.0))
	var d := p1 - p0
	if d.length() < 0.0001:
		return Vector2(1.0, 0.0)
	return d.normalized()


func _drier_side(road: Vector2, nrm: Vector2, off: float, want: int) -> int:
	## Nobody builds in the marsh. Probed at the two places the yard would
	## ACTUALLY stand, which is the only comparison that means anything: a
	## token nine-metre step either way is under a metre of height on any
	## slope a road can be carved along, so it never moved a single croft.
	## With no ground probe — the headless suite — the hashed side stands,
	## which is the honest answer for a flat plane.
	if _ground == null or not is_instance_valid(_ground):
		return want
	var a := _ground_y(road + nrm * (off * float(want)))
	var b := _ground_y(road - nrm * (off * float(want)))
	if b > a + SIDE_MARGIN:
		return -want
	return want


func _name_pass() -> void:
	## Two households on the same map called Quimby is a bug you only see by
	## LOOKING at the roster, and the first probe had exactly that: 26 seats
	## drawn from 26 surnames, so collisions were near certain. Names are
	## therefore assigned in seat order — which is deterministic — with each
	## croft walking forward from its own hashed index to the first surname
	## nobody has taken. Falling off the end of the list is the only case that
	## needs the road to disambiguate, and it says so out loud rather than
	## quietly repeating a name.
	var used: Dictionary = {}
	for c in crofts:
		var cd := c as Dictionary
		var kindword := "shieling" if String(cd["kind"]) == "shieling" else "croft"
		var start := int(cd.get("name_i", 0)) % SURNAMES.size()
		var pick := ""
		for step in SURNAMES.size():
			var cand := String(SURNAMES[(start + step) % SURNAMES.size()])
			if not used.has(cand):
				pick = cand
				used[cand] = true
				break
		if pick.is_empty():
			pick = String(SURNAMES[start])
			cd["name"] = "%s's %s below %s" % [pick, kindword, String(cd["from"])]
			continue
		cd["name"] = "%s's %s" % [pick, kindword]


func _kind_for(h: int, _off: float) -> String:
	var u := _unit(h, 6)
	if u < 0.18:
		return "steading"
	if u > 0.86:
		return "shieling"
	return "croft"


func _name_for(h: int) -> String:
	return String(SURNAMES[int(_unit(h, 7) * float(SURNAMES.size())) % SURNAMES.size()])


func _ensure_state(id: String) -> void:
	if state.has(id):
		return
	state[id] = {
		"stores": STORE_START,
		"wash": "none",
		"dry_h": 0.0,
		"shut_until": -1.0,
		"cold_h": 0.0,
		"was_cold": false,
		"alarm_day": -1.0,
	}


# ========================== THE DAY — a pure function ======================

static func daylight(season: int) -> Vector2:
	## Dawn and dusk, per season. `x` is dawn, `y` is dusk.
	match clampi(season, 0, 3):
		0:
			return Vector2(5.80, 19.40)
		1:
			return Vector2(4.90, 20.60)
		2:
			return Vector2(6.30, 18.40)
	return Vector2(7.20, 16.60)


static func rise_at(c: Dictionary, season: int) -> float:
	var dl := daylight(season)
	return dl.x - RISE_BEFORE_DAWN + clampf(float(c.get("jit", 0.5)), 0.0, 1.0) * RISE_SPREAD


static func bed_at(c: Dictionary, season: int) -> float:
	var dl := daylight(season)
	var j := clampf(float(c.get("jit", 0.5)), 0.0, 1.0)
	return minf(dl.y + BED_AFTER_DUSK - j * BED_SPREAD, 23.60)


static func station_for(c: Dictionary, season: int, hour_i: int) -> String:
	var se := clampi(season, 0, 3)
	var tbl: Array = SHIELING_TABLE[se] if String(c.get("kind", "croft")) == "shieling" \
			else WORK_TABLE[se]
	var j := int(round(clampf(float(c.get("jit", 0.5)), 0.0, 1.0) * 5.0))
	return String(tbl[posmod(hour_i + j, tbl.size())])


static func crop_at(day: float, season: int, kind: String) -> float:
	## What is standing in the plot, 0 bare to 1 full. Read from the road,
	## this is the cheapest season cue in the game: the same field is brown
	## in April, green in July, gold in September and stubble by October.
	if kind == "shieling":
		return 0.0
	var within := fposmod(day, DAYS_PER_SEASON) / DAYS_PER_SEASON
	var se := clampi(season, 0, 3)
	if se == 0:
		return 0.10 + 0.45 * within
	if se == 1:
		return 0.55 + 0.45 * within
	if se == 2:
		if within < 0.62:
			return 1.0
		return maxf(0.0, 1.0 - (within - 0.62) / 0.38) * 0.90
	return 0.0


static func burn_per_hour(hearth: String, season: int) -> float:
	if hearth == "out":
		return 0.0
	var m := float(SEASON_BURN[clampi(season, 0, 3)])
	return (BURN_LIT if hearth == "lit" else BURN_BANKED) * m


static func gather_per_hour(work: String, season: int) -> float:
	if work != "wood":
		return 0.0
	return GATHER_BASE * float(SEASON_GATHER[clampi(season, 0, 3)])


static func routine_at(c: Dictionary, day: float, sky: int, season: int, st: Dictionary) -> Dictionary:
	## EVERY observable beat of a croft's day, and the only place any of them
	## is decided. Pure: no `self`, no node, no clock, no RNG. The sim reads
	## it to move the woodpile; the staged bodies read it to know what to
	## show; the suite reads it at any hour of any season under any sky.
	var hour := fposmod(day * 24.0, 24.0)
	var lv := clampi(sky, 0, 4)
	var se := clampi(season, 0, 3)
	var dl := daylight(se)
	var rise := rise_at(c, se)
	var bed := bed_at(c, se)
	var awake := hour >= rise and hour < bed
	var stores := maxf(float(st.get("stores", 0.0)), 0.0)
	var shut := day < float(st.get("shut_until", -1.0))
	var wet := String(st.get("wash", "none")) == "wet"
	var kind := String(c.get("kind", "croft"))

	## --- the hearth. Never truly out while there is anything to burn: a
	## household banks its fire overnight, it does not let it die.
	var hearth := "out"
	if stores > 0.0:
		hearth = "lit" if (awake and hour < bed - BANK_BEFORE_BED) else "banked"

	## --- the beasts.
	var stock := "byre"
	if not shut:
		if se == 3:
			if lv == SKY_CLEAR and hour >= WINTER_OUT_FROM and hour < WINTER_OUT_TO:
				stock = "field"
		elif lv <= FIELD_MAX_SKY and hour >= rise + STOCK_OUT_AFTER and hour < dl.y - STOCK_IN_BEFORE:
			stock = "field"

	## --- the line. Two values, and the split matters: `wash_intent` is what
	## the household WANTS given the hour and the sky right now, and `washing`
	## is what is actually on the line, which only the sim may change.
	##
	## They are separate because a soaking is a thing that happens to washing
	## that is ALREADY OUT. Deriving "out" from the current sky alone would
	## mean the line is only ever out while the weather is fine, so it could
	## never be caught by a turn in it — the feature would be unreachable and
	## every assertion aimed at it would pass for the wrong reason.
	var washing := String(st.get("wash", "none"))
	var wash_intent := "none"
	if se != 3 and not shut and not wet:
		var hang := rise + WASH_HANG_AFTER
		var fetch := dl.y - WASH_IN_BEFORE
		if hour >= hang and hour < fetch and lv <= WASH_MAX_SKY:
			wash_intent = "hang"
		else:
			wash_intent = "fetch"
	else:
		wash_intent = "fetch"

	var shutters := "shut" if (not awake or lv >= SKY_STORM or shut) else "open"
	var lamp := awake and (hour < dl.x - LAMP_MARGIN or hour > dl.y - LAMP_MARGIN)

	## --- where the crofter actually is.
	var work := "abed"
	if awake:
		if shut:
			work = "door" if (hour >= rise + 1.0 and hour < rise + 1.4) else "in"
		elif hour < rise + FIRST_CHORE or hour >= bed - LAST_CHORE:
			work = "hearth"
		elif hour >= MEAL_FROM and hour < MEAL_TO:
			work = "in"
		else:
			work = station_for(c, se, int(hour))
		## An empty woodpile is the only thing that outranks the day's work.
		if stores <= 0.0 and not shut:
			work = "wood"
		if OUTDOOR.has(work):
			if lv >= SKY_STORM:
				work = "in"
			elif lv >= WORK_IN_SKY:
				work = "byre"

	return {
		"hour": hour,
		"rise": rise,
		"bed": bed,
		"awake": awake,
		"shut_in": shut,
		"hearth": hearth,
		"stock": stock,
		"beasts": int(KINDS.get(kind, KINDS["croft"])["stock"]) if stock == "field" else 0,
		"washing": washing,
		"wash_intent": wash_intent,
		"shutters": shutters,
		"lamp": lamp,
		"work": work,
		"smoke": hearth != "out",
		"smoke_lean": clampf(float(lv) / 4.0, 0.0, 1.0),
		"crop": crop_at(day, se, kind),
		"wood_n": clampi(int(round(stores / STORE_MAX * float(WOOD_MAX))), 0, WOOD_MAX),
		"stores": stores,
	}


static func summary(r: Dictionary) -> String:
	## The one-word read a passer-by gets, and the key `sense()` de-dupes on.
	if not bool(r.get("smoke", false)):
		return "cold"
	if bool(r.get("shut_in", false)):
		return "barred"
	if String(r.get("washing", "")) == "out":
		return "washing"
	if String(r.get("stock", "")) == "field":
		return "beasts"
	if bool(r.get("lamp", false)):
		return "lamp"
	return "smoke"


static func legible(c: Dictionary, r: Dictionary) -> String:
	## What you would say about the place, walking past it.
	var nm := String(c.get("name", "the croft"))
	match summary(r):
		"cold":
			return "No smoke at %s. Woodpile's bare." % nm
		"barred":
			return "%s is barred up in broad daylight." % nm
		"washing":
			return "Washing out at %s, so somebody trusts the sky." % nm
		"beasts":
			return "%s has the beasts out." % nm
		"lamp":
			return "A lamp still burning at %s." % nm
	return "Smoke up at %s." % nm


# ================================ the sim ==================================

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
	## that passed, not the two real seconds it took. The same shape as
	## `Chronicle._process` and `Wayfarers._tick_clock`, deliberately: three
	## sims reading the same sky must reach the same day.
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
		_hours += minf(d, 30.0) * 24.0
		days = _hours / 24.0
	_run_steps(CATCHUP_STEPS)


func _adopt(now: float) -> void:
	## DayNight boots at day 30, hour 19.7 while a fresh sim sits at day 3.
	## Left alone, every dawn gate would be judged against a clock the sky has
	## never heard of and the hearths would be lit at midnight.
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
	var season := season_at(t)
	var sky := sky_at(t)
	for c in crofts:
		_step_croft(c as Dictionary, t, sky, season_here(t, c as Dictionary))


func season_here(t: float, c: Dictionary) -> int:
	## [seasons] The season AT THIS CROFT, which is not always the season on
	## the calendar. `season_at` still answers for the world — the Chronicle
	## runs on it and a save header records it — but a household's YEAR is
	## warped by where it stands, so the northern crofts sow late and are
	## snowed on early, and the coastal ones get the long mild end of it.
	##
	## This is what makes the woodpile a question about GEOGRAPHY. A croft in
	## the north burns `SEASON_BURN`'s winter rate for a longer winter and
	## gathers over a shorter autumn, off the same two tables, so the same
	## household habits leave a different pile in December depending only on
	## which road it was seated beside. See scripts/Seasons.gd.
	##
	## No altitude term: a croft's `pos` is a Vector2 seated off a road and
	## the sim never learns its height, so latitude and the sea decide it and
	## `Seasons.alt_u` reads 0. Crofts sit in valleys; that is close enough to
	## true and it is honest about what is known.
	## ⚠ Through `season_at`, NEVER through `Seasons.local_index` directly:
	## `season_at` is the door that delegates to the Chronicle, and the
	## Chronicle owns the calendar. Geography moves the DAY this croft is
	## living in; it does not get to decide what a day means.
	var p: Vector2 = c.get("pos", Vector2.ZERO)
	return season_at(t + Seasons.warp_days(t, Vector3(p.x, 0.0, p.y)))


func sky_at(t: float) -> int:
	## The sky the CHRONICLE believes in, never the live `Weather`. The live
	## one is `_rng`-driven and only answers for the step that is actually
	## now; a consumer that reached for it would put a number in the save's
	## future that the save cannot reproduce. The Wayfarers' rule.
	if chron != null and is_instance_valid(chron) and chron.has_method("sky_at"):
		return clampi(int(chron.call("sky_at", t)), 0, 4)
	return SKY_CLEAR


func season_at(t: float) -> int:
	if chron != null and is_instance_valid(chron) and chron.has_method("season_at"):
		return clampi(int(chron.call("season_at", t)), 0, 3)
	return int(fposmod(t, DAYS_PER_SEASON * 4.0) / DAYS_PER_SEASON) % 4


func _step_croft(c: Dictionary, t: float, sky: int, season: int) -> void:
	var id := String(c["id"])
	_ensure_state(id)
	var st: Dictionary = state[id]
	_maybe_alarm(c, st, t)
	var r := routine_at(c, t, sky, season, st)
	var hearth := String(r["hearth"])
	var work := String(r["work"])

	## --- the woodpile. The only economy in here, and the whole point of it.
	var s := float(st["stores"])
	s -= burn_per_hour(hearth, season) * STEP_HOURS
	s += gather_per_hour(work, season) * STEP_HOURS
	st["stores"] = clampf(s, 0.0, STORE_MAX)

	## --- the line. ORDER IS THE WHOLE THING HERE: a line that is out when
	## the rain arrives is soaked BEFORE anyone gets to fetch it in. Reverse
	## these two and washing is never caught out by anything, ever.
	var on_line := String(st.get("wash", "none"))
	if on_line == "out" and sky >= SOAK_SKY:
		on_line = "wet"
		st["dry_h"] = 0.0
	elif on_line == "out" and String(r["wash_intent"]) == "fetch":
		on_line = "none"
	elif on_line == "none" and String(r["wash_intent"]) == "hang":
		on_line = "out"
	if on_line == "wet":
		if sky <= WASH_MAX_SKY:
			st["dry_h"] = float(st.get("dry_h", 0.0)) + STEP_HOURS
			if float(st["dry_h"]) >= DRY_HOURS:
				on_line = "none"
				st["dry_h"] = 0.0
		else:
			st["dry_h"] = 0.0
	st["wash"] = on_line

	## --- a cold roof is worth a signal exactly once per cold spell.
	if hearth == "out":
		st["cold_h"] = float(st.get("cold_h", 0.0)) + STEP_HOURS
		if not bool(st.get("was_cold", false)):
			st["was_cold"] = true
			croft_cold.emit(c)
	else:
		st["was_cold"] = false


func _maybe_alarm(c: Dictionary, st: Dictionary, t: float) -> void:
	## Once a game day per croft, at that household's own hour, so forty
	## crofts do not all walk the Chronicle's resolved ring on the same step.
	var d := floorf(t)
	if d <= float(st.get("alarm_day", -1.0)):
		return
	if fposmod(t * 24.0, 24.0) < float(c.get("hour_key", 9.0)):
		return
	st["alarm_day"] = d
	if chron == null or not is_instance_valid(chron) or not chron.has_method("pressure_at"):
		return
	var p2: Vector2 = c["pos"]
	var at := Vector3(p2.x, 0.0, p2.y)
	var worst := 0.0
	var which := ""
	for tag in ALARM_TAGS:
		var v := float(chron.call("pressure_at", at, String(tag)))
		if v > worst:
			worst = v
			which = String(tag)
	if worst < SHUT_PRESSURE:
		return
	var until := t + SHUT_DAYS
	if until > float(st.get("shut_until", -1.0)):
		st["shut_until"] = until
		croft_shut.emit(c, "%s %.2f" % [which, worst])


# =============================== reading it ================================

func state_of(id: String) -> Dictionary:
	_ensure_state(id)
	return state[id] as Dictionary


func croft_by_id(id: String) -> Dictionary:
	return _by_id.get(id, {}) as Dictionary


func routine_of(id: String) -> Dictionary:
	var c := croft_by_id(id)
	if c.is_empty():
		return {}
	return routine_at(c, days, sky_at(days), season_at(days), state_of(id))


func near(pos: Vector3, radius: float) -> Array:
	## Every croft within `radius`, nearest first. The map, the sense pass and
	## the stager all read this and nothing else.
	var here := Vector2(pos.x, pos.z)
	var out: Array = []
	for c in crofts:
		var cd := c as Dictionary
		var d: float = (cd["pos"] as Vector2).distance_to(here)
		if d <= radius:
			out.append({"croft": cd, "dist": d})
	out.sort_custom(func(a, b):
		if not is_equal_approx(float(a["dist"]), float(b["dist"])):
			return float(a["dist"]) < float(b["dist"])
		return String((a["croft"] as Dictionary)["id"]) < String((b["croft"] as Dictionary)["id"]))
	return out


func report() -> Dictionary:
	var rows: Array = []
	var lit := 0
	var cold := 0
	var barred := 0
	var store_sum := 0.0
	for c in crofts:
		var cd := c as Dictionary
		var st := state_of(String(cd["id"]))
		var r := routine_at(cd, days, sky_at(days), season_at(days), st)
		if String(r["hearth"]) == "out":
			cold += 1
		else:
			lit += 1
		if bool(r["shut_in"]):
			barred += 1
		store_sum += float(st["stores"])
		rows.append("%s|%s|%s|%s|%s|%.0f" % [String(cd["id"]), String(cd["name"]),
			String(cd["kind"]), String(r["hearth"]), String(r["work"]), float(st["stores"])])
	rows.sort()
	return {
		"crofts": crofts.size(),
		"day": days,
		"season": season_at(days),
		"sky": sky_at(days),
		"lit": lit,
		"cold": cold,
		"barred": barred,
		"stores_avg": (store_sum / float(crofts.size())) if not crofts.is_empty() else 0.0,
		"staged": _staged.size(),
		"steps": _ran,
		"build_ms": _build_ms,
		"rows": rows,
	}


func sense() -> void:
	## Walk close enough to a croft and you notice what it is doing. Offered
	## to the feed keyed to the PLACE as speaker, once per state — so a croft
	## you pass every day is not narrating itself at you, but a croft whose
	## smoke has gone out since last time says so.
	if feed == null or not is_instance_valid(feed) or not feed.has_method("offer"):
		return
	if player == null or not is_instance_valid(player):
		return
	var rows := near(player.global_position, NOTICE_M)
	if rows.is_empty():
		return
	var c: Dictionary = (rows[0] as Dictionary)["croft"]
	var id := String(c["id"])
	var r := routine_at(c, days, sky_at(days), season_at(days), state_of(id))
	var key := id + "|" + summary(r)
	if _said.has(key):
		return
	if bool(feed.call("offer", legible(c, r), String(c["name"]), "croft", days)):
		_said[key] = true


# ================================ the yard =================================

func _restage(pos: Vector3) -> void:
	## Stage what is close, strike what is not, and never both in one pass for
	## one croft — the Director's hysteresis, so a player walking the boundary
	## does not rebuild a farmyard every scan.
	if not is_inside_tree():
		return
	var here := Vector2(pos.x, pos.z)
	for id in _staged.keys():
		var c: Dictionary = _by_id.get(String(id), {})
		if c.is_empty() or (c["pos"] as Vector2).distance_to(here) > STRIKE_RADIUS:
			_strike(String(id))
	for row in near(pos, STAGE_RADIUS):
		if _staged.size() >= MAX_STAGED:
			break
		var c2 := (row as Dictionary)["croft"] as Dictionary
		var id2 := String(c2["id"])
		if _staged.has(id2):
			continue
		var body := _build_body(c2)
		if body == null:
			continue
		add_child(body)
		_staged[id2] = body


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
	## Bodies follow the SIM, they do not have one of their own — the same
	## contract the Wayfarers keep. A staged croft is a read of `routine_at`
	## every frame and nothing else, which is why walking away and back cannot
	## desynchronise it.
	if player != null and is_instance_valid(player):
		_restage(player.global_position)
	if _staged.is_empty():
		return
	var sky := sky_at(days)
	var season := season_at(days)
	for id in _staged.keys():
		var body: Variant = _staged.get(id, null)
		if not (body is Node3D) or not is_instance_valid(body as Node3D):
			_staged.erase(id)
			continue
		var c: Dictionary = _by_id.get(String(id), {})
		if c.is_empty():
			_strike(String(id))
			continue
		_apply(body as Node3D, c, routine_at(c, days, sky, season, state_of(String(id))))


func _apply(body: Node3D, c: Dictionary, r: Dictionary) -> void:
	## One reader, one dictionary. Everything the yard shows is here, and
	## nothing here decides anything.
	var lamp := body.get_node_or_null("Lamp") as OmniLight3D
	if lamp != null:
		lamp.visible = bool(r["lamp"])
	var smoke := body.get_node_or_null("Smoke") as Node3D
	if smoke != null:
		var on := bool(r["smoke"])
		smoke.visible = on
		if on:
			## A storm flattens a smoke column. The weather-swap table's
			## third customer, after the firepit and the roads.
			smoke.rotation.z = clampf(float(r["smoke_lean"]), 0.0, 1.0) * 1.15
			var thin := 0.55 if String(r["hearth"]) == "banked" else 1.0
			for ch in smoke.get_children():
				var pf := ch as Node3D
				if pf != null:
					pf.scale.x = thin
	for nm in ["ShutterL", "ShutterR"]:
		var sh := body.get_node_or_null(nm) as Node3D
		if sh != null:
			var s_dir := 1.0 if nm == "ShutterL" else -1.0
			sh.rotation.y = (1.25 * s_dir) if String(r["shutters"]) == "open" else 0.0
	var line := body.get_node_or_null("Washing") as Node3D
	if line != null:
		var w := String(r["washing"])
		line.visible = w != "none"
		for ch2 in line.get_children():
			var cl := ch2 as Node3D
			if cl != null and String(cl.name).begins_with("Cloth"):
				cl.scale.y = 1.0 if w == "out" else 1.22
	var crop := body.get_node_or_null("Crop") as Node3D
	if crop != null:
		var g := clampf(float(r["crop"]), 0.0, 1.0)
		crop.visible = g > 0.02
		crop.scale = Vector3(1.0, maxf(g, 0.02), 1.0)
	var pile := body.get_node_or_null("Woodpile") as Node3D
	if pile != null:
		var n := int(r["wood_n"])
		var i := 0
		for ch3 in pile.get_children():
			var lg := ch3 as Node3D
			if lg != null:
				lg.visible = i < n
				i += 1
	var herd := body.get_node_or_null("Beasts") as Node3D
	if herd != null:
		var b := int(r["beasts"])
		var j := 0
		for ch4 in herd.get_children():
			var bs := ch4 as Node3D
			if bs != null:
				bs.visible = j < b
				j += 1
	var who := body.get_node_or_null("Crofter") as Node3D
	if who != null:
		var stn := String(r["work"])
		who.visible = stn != "abed" and stn != "in"
		var at: Variant = body.get_meta("stations", {})
		if at is Dictionary and (at as Dictionary).has(stn):
			var p: Vector3 = (at as Dictionary)[stn]
			who.position = who.position.lerp(p, 0.12)
			who.rotation.y = atan2(-p.x, -p.z)
	var fire: Variant = body.get_meta("fire", null)
	if fire is Node and is_instance_valid(fire as Node):
		_drive_hearth(fire as Node, String(r["hearth"]))


func _drive_hearth(fire: Node, want: String) -> void:
	## The hearth is a REAL Firepit, in the "fires" group, so a croft warms
	## anyone standing at it through `Firepit.heat_from` and the midge swarm
	## keeps away from it through the "campfires" group it already reads. The
	## household feeds it; the player does not have to.
	if want == "out":
		if fire.has_method("douse"):
			fire.call("douse")
		return
	if not fire.has_method("light") or not fire.has_method("feed"):
		return
	var fuel := float(fire.get("fuel")) if "fuel" in fire else 0.0
	if fuel < 300.0:
		if bool(fire.call("burning")):
			fire.call("feed", 600.0)
		else:
			fire.call("light", 900.0)


func _ground_y(flat: Vector2) -> float:
	## Duck-typed, and null is the normal case: the headless suite has no
	## terrain and every croft in it stands honestly at y = 0.
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


# ============================== building it ================================

func _build_body(c: Dictionary) -> Node3D:
	var kind := String(c.get("kind", "croft"))
	var k: Dictionary = KINDS.get(kind, KINDS["croft"])
	var h := _hash(world_seed, String(c["id"]).hash(), SALT_BODY)
	var root := Node3D.new()
	root.name = "Croft_%s" % String(c["id"]).replace("#", "_")
	var p: Vector2 = c["pos"]
	root.position = Vector3(p.x, _ground_y(p), p.y)
	var face: Vector2 = c.get("face", Vector2(0.0, 1.0))
	root.rotation.y = atan2(face.x, face.y)

	var wall := float(k["wall"])
	var stations: Dictionary = {}
	_build_house(root, wall, h)
	stations["hearth"] = Vector3(0.0, 0.0, -wall * 0.25)
	stations["door"] = Vector3(0.0, 0.0, wall * 0.62)
	stations["in"] = Vector3(0.0, 0.0, 0.0)

	if bool(k["byre"]):
		_build_byre(root, wall, h)
		stations["byre"] = Vector3(-wall * 1.25, 0.0, -1.2)
	else:
		stations["byre"] = Vector3(-wall * 0.9, 0.0, -1.2)
	stations["well"] = _build_well(root, wall)
	stations["wood"] = _build_woodpile(root, wall)
	stations["plot"] = _build_plot(root, wall, bool(k["plot"]), h)
	_build_washing(root, wall)
	_build_beasts(root, wall, int(k["stock"]), h)
	_build_crofter(root, h)
	root.set_meta("stations", stations)
	_mow_yard(root.position)
	return root


func _mow_yard(at: Vector3) -> void:
	## A farmyard is not a hayfield, and the first screenshot of this feature
	## made the case better than any argument could: the house and the byre
	## stood clear while the woodpile, the beasts, the plot and the crofter
	## were all under a metre of standing grass. Nothing below waist height
	## was legible from the road at all.
	##
	## `GrassSystem.cut_at` is the sword's own mower -- it fells the TALL
	## tufts inside a radius, leaves stubble where they stood, and records the
	## cut in `_cut_cells`, which the grass already saves and re-reads when a
	## chunk streams back. So a yard mown once stays mown, across a reload,
	## without this file storing a thing.
	##
	## Once per croft per session, duck-typed, and a silent no-op with no
	## grass bound at all -- which is the headless case and is asserted.
	if _mown.has(_yard_key(at)):
		return
	_mown[_yard_key(at)] = true
	if not is_inside_tree():
		return
	var g := get_tree().get_first_node_in_group("grass_system")
	if g == null or not is_instance_valid(g) or not g.has_method("cut_at"):
		return
	g.call("cut_at", at, YARD_MOW_M)


func _yard_key(at: Vector3) -> String:
	return "%d_%d" % [int(round(at.x)), int(round(at.z))]


func _build_house(root: Node3D, wall: float, h: int) -> void:
	var w := wall
	var d := wall * 0.72
	## Daub over a dark frame, not slate. The first version lerped earth to
	## stone and came out a cold blue-grey that vanished into a summer
	## hillside at thirty metres -- which is the opposite of the one thing
	## this feature is for.
	var wallc: Color = IncidentKit.PALETTE["earth"].lerp(Color(0.74, 0.71, 0.62), 0.55 + 0.25 * _unit(h, 1))
	var mw := IncidentKit._mat(wallc)
	var mr := IncidentKit._mat(IncidentKit.PALETTE["sack"].darkened(0.14))
	IncidentKit._add(root, IncidentKit._box(w, 2.35, d), mw, Vector3(0.0, 1.17, 0.0))
	## Two leaning boards for a roof — cheaper and reads better at distance
	## than a prism nobody will ever stand close enough to fault.
	for s in [-1.0, 1.0]:
		var slab := MeshInstance3D.new()
		slab.mesh = IncidentKit._box(w * 0.62, 0.16, d * 1.16)
		slab.material_override = mr
		slab.position = Vector3(s * w * 0.26, 2.78, 0.0)
		slab.rotation.z = -s * 0.72
		root.add_child(slab)
	## Door and shutters, on pivots the reader turns.
	IncidentKit._add(root, IncidentKit._box(0.92, 1.75, 0.10),
			IncidentKit._mat(IncidentKit.PALETTE["wood"]), Vector3(0.0, 0.88, d * 0.5 + 0.06))
	for nm in ["ShutterL", "ShutterR"]:
		var piv := Node3D.new()
		piv.name = nm
		var s2 := -1.0 if nm == "ShutterL" else 1.0
		piv.position = Vector3(s2 * w * 0.30, 1.45, d * 0.5 + 0.05)
		root.add_child(piv)
		IncidentKit._add(piv, IncidentKit._box(0.46, 0.62, 0.06),
				IncidentKit._mat(IncidentKit.PALETTE["wood"].darkened(0.15)),
				Vector3(s2 * 0.23, 0.0, 0.0))
	## Chimney, the hearth inside it, and the column you actually read.
	IncidentKit._add(root, IncidentKit._box(0.62, 1.5, 0.62),
			IncidentKit._mat(IncidentKit.PALETTE["stone"]), Vector3(-w * 0.5 + 0.2, 2.9, 0.0))
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.position = Vector3(0.0, 1.5, d * 0.5 - 0.15)
	lamp.light_color = Color(1.0, 0.73, 0.40)
	lamp.light_energy = 1.6
	lamp.omni_range = 9.0
	lamp.shadow_enabled = false
	lamp.visible = false
	root.add_child(lamp)
	## The column, and the first thing anyone sees of a croft from a mile off.
	## LOOKED AT before it was believed in: six equal boxes at one alpha, in a
	## dead straight line, read as a translucent chimney extension rather than
	## as smoke. Seven now, each with its OWN material so the plume thins as
	## it climbs, widening and spacing out as it goes, turned off-square and
	## leaning a little further with every rung.
	var smoke := Node3D.new()
	smoke.name = "Smoke"
	smoke.position = Vector3(-w * 0.5 + 0.2, 3.55, 0.0)
	root.add_child(smoke)
	var rise := 0.0
	for i in 7:
		var f := float(i) / 6.0
		var puff := MeshInstance3D.new()
		var sz := 0.46 + 1.55 * f * f
		puff.mesh = IncidentKit._box(sz, 0.44 + 0.5 * f, sz)
		var pm := IncidentKit._mat(Color(0.68, 0.66, 0.63, 0.24 - 0.185 * f), true)
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		puff.material_override = pm
		rise += 0.42 + 0.34 * f
		puff.position = Vector3(0.22 * f * f, rise, 0.15 * f)
		puff.rotation.y = _unit(h, 50 + i) * TAU
		smoke.add_child(puff)
	var fire := Firepit.make()
	fire.position = Vector3(-wall * 0.5 + 0.45, 0.15, 0.0)
	root.add_child(fire)
	fire.boot()
	root.set_meta("fire", fire)


func _build_byre(root: Node3D, wall: float, _h: int) -> void:
	## Weathered board, not pitch. At `wood.darkened(0.1)` with a
	## `sack.darkened(0.35)` roof the byre read as a black hole beside the
	## house in every screenshot -- the second largest mass in the yard and
	## the only one you could not tell anything about.
	var mb := IncidentKit._mat(IncidentKit.PALETTE["wood_pale"].lerp(IncidentKit.PALETTE["wood"], 0.45))
	var byre := Node3D.new()
	byre.name = "Byre"
	byre.position = Vector3(-wall * 1.35, 0.0, -1.2)
	root.add_child(byre)
	IncidentKit._add(byre, IncidentKit._box(3.4, 1.9, 2.6), mb, Vector3(0.0, 0.95, 0.0))
	IncidentKit._add(byre, IncidentKit._box(3.9, 0.14, 3.1),
			IncidentKit._mat(IncidentKit.PALETTE["sack"].darkened(0.14)), Vector3(0.0, 2.0, 0.0))


func _build_well(root: Node3D, wall: float) -> Vector3:
	var at := Vector3(wall * 0.95, 0.0, wall * 0.55)
	var well := Node3D.new()
	well.name = "Well"
	well.position = at
	root.add_child(well)
	IncidentKit._add(well, IncidentKit._cyl(0.55, 0.7, 8),
			IncidentKit._mat(IncidentKit.PALETTE["stone"]), Vector3(0.0, 0.35, 0.0))
	IncidentKit._add(well, IncidentKit._box(0.1, 1.2, 0.1),
			IncidentKit._mat(IncidentKit.PALETTE["wood"]), Vector3(0.0, 1.25, 0.0))
	return at + Vector3(0.0, 0.0, 0.9)


func _build_woodpile(root: Node3D, wall: float) -> Vector3:
	var at := Vector3(wall * 0.72, 0.0, -wall * 0.62)
	var pile := Node3D.new()
	pile.name = "Woodpile"
	pile.position = at
	root.add_child(pile)
	for i in WOOD_MAX:
		var row := i / 3
		var col := i % 3
		var log_node: Node3D = IncidentKit.build_prop({"kind": "log", "arg": "wood"}, i, float(i) / float(WOOD_MAX))
		if log_node == null:
			continue
		log_node.rotation = Vector3(0.0, PI * 0.5, 0.0)
		log_node.position = Vector3(0.0, 0.22 + 0.34 * float(row), -0.55 + 0.55 * float(col))
		log_node.scale = Vector3.ONE * 0.6
		log_node.visible = false
		pile.add_child(log_node)
	return at + Vector3(0.0, 0.0, 1.1)


func _build_plot(root: Node3D, wall: float, has_plot: bool, h: int) -> Vector3:
	var at := Vector3(0.0, 0.0, -wall * 1.7)
	if not has_plot:
		return at
	var plot := Node3D.new()
	plot.name = "Plot"
	plot.position = at
	root.add_child(plot)
	## A fence of the Director's own hurdles, so a croft's boundary and a
	## raided sheepfold's boundary are visibly the same carpentry.
	var span := wall * 1.25
	for i in 8:
		var side := i / 2
		var k := i % 2
		var hu: Node3D = IncidentKit.build_prop({"kind": "hurdle", "arg": ""}, i, _unit(h, 10 + i))
		if hu == null:
			continue
		var x := 0.0
		var z := 0.0
		var yaw := 0.0
		if side == 0:
			x = -span
			z = -span * 0.5 + span * float(k)
			yaw = PI * 0.5
		elif side == 1:
			x = span
			z = -span * 0.5 + span * float(k)
			yaw = PI * 0.5
		elif side == 2:
			x = -span * 0.5 + span * float(k)
			z = -span * 0.6
		else:
			x = -span * 0.5 + span * float(k)
			z = span * 0.6
		hu.position = Vector3(x, 0.0, z)
		hu.rotation.y = yaw
		plot.add_child(hu)
	var crop := Node3D.new()
	crop.name = "Crop"
	root.add_child(crop)
	crop.position = at
	var mc := IncidentKit._mat(Color(0.42, 0.47, 0.20))
	for i in 18:
		var rr := i / 6
		var cc := i % 6
		IncidentKit._add(crop, IncidentKit._box(0.9, 0.85, 0.22), mc,
				Vector3(-span * 0.6 + span * 0.24 * float(cc), 0.42, -0.9 + 0.9 * float(rr)))
	return at + Vector3(0.0, 0.0, span * 0.75)


func _build_washing(root: Node3D, wall: float) -> void:
	var line := Node3D.new()
	line.name = "Washing"
	line.position = Vector3(wall * 0.85, 0.0, 1.6)
	line.visible = false
	root.add_child(line)
	var mp := IncidentKit._mat(IncidentKit.PALETTE["wood"])
	for s in [-1.0, 1.0]:
		IncidentKit._add(line, IncidentKit._box(0.09, 1.9, 0.09), mp, Vector3(0.0, 0.95, s * 1.9))
	IncidentKit._add(line, IncidentKit._box(0.03, 0.03, 3.8),
			IncidentKit._mat(IncidentKit.PALETTE["rope"]), Vector3(0.0, 1.85, 0.0))
	for i in 4:
		var cl := Node3D.new()
		cl.name = "Cloth%d" % i
		cl.position = Vector3(0.0, 1.35, -1.35 + 0.9 * float(i))
		line.add_child(cl)
		IncidentKit._add(cl, IncidentKit._box(0.04, 0.86, 0.55),
				IncidentKit._mat(IncidentKit.PALETTE["linen"], true), Vector3.ZERO)


func _build_beasts(root: Node3D, wall: float, n: int, h: int) -> void:
	var herd := Node3D.new()
	herd.name = "Beasts"
	herd.position = Vector3(-wall * 0.4, 0.0, -wall * 2.5)
	root.add_child(herd)
	var mb := IncidentKit._mat(IncidentKit.PALETTE["fleece"].darkened(0.12))
	for i in n:
		var b := Node3D.new()
		b.name = "Beast%d" % i
		b.position = Vector3(-3.0 + 2.2 * float(i) + 1.4 * _unit(h, 20 + i),
				0.0, -2.0 + 3.4 * _unit(h, 30 + i))
		b.rotation.y = _unit(h, 40 + i) * TAU
		b.visible = false
		herd.add_child(b)
		IncidentKit._add(b, IncidentKit._box(0.52, 0.46, 0.95), mb, Vector3(0.0, 0.62, 0.0))
		IncidentKit._add(b, IncidentKit._box(0.28, 0.26, 0.30), mb, Vector3(0.0, 0.66, 0.60))
		for lx in [-0.17, 0.17]:
			for lz in [-0.32, 0.32]:
				IncidentKit._add(b, IncidentKit._box(0.10, 0.40, 0.10),
						IncidentKit._mat(IncidentKit.PALETTE["earth"]), Vector3(lx, 0.20, lz))


func _build_crofter(root: Node3D, h: int) -> void:
	var who := Node3D.new()
	who.name = "Crofter"
	root.add_child(who)
	var cloth: Color = IncidentKit.PALETTE["sack"].lerp(IncidentKit.PALETTE["earth"], _unit(h, 8))
	var mc := IncidentKit._mat(cloth)
	var ms := IncidentKit._mat(Color(0.62, 0.48, 0.38))
	IncidentKit._add(who, IncidentKit._box(0.44, 0.66, 0.26), mc, Vector3(0, 1.06, 0))
	IncidentKit._add(who, IncidentKit._box(0.30, 0.26, 0.28), mc, Vector3(0, 1.50, -0.02))
	IncidentKit._add(who, IncidentKit._box(0.20, 0.18, 0.18), ms, Vector3(0, 1.44, 0.08))
	IncidentKit._add(who, IncidentKit._box(0.12, 0.52, 0.14), mc, Vector3(-0.28, 1.02, 0))
	IncidentKit._add(who, IncidentKit._box(0.12, 0.52, 0.14), mc, Vector3(0.28, 1.02, 0))
	IncidentKit._add(who, IncidentKit._box(0.34, 0.72, 0.30),
			IncidentKit._mat(cloth.darkened(0.22)), Vector3(0.0, 0.36, 0.0))


# =============================== save =====================================

func to_dict() -> Dictionary:
	## Only what cannot be rebuilt. Seats, names, kinds and circuits are a
	## pure function of the net and the seed, both of which a save restores,
	## so storing them would only be a second copy that can go stale.
	var st: Dictionary = {}
	for id in state.keys():
		var row: Dictionary = state[id]
		st[id] = {
			"stores": float(row.get("stores", STORE_START)),
			"wash": String(row.get("wash", "none")),
			"dry_h": float(row.get("dry_h", 0.0)),
			"shut_until": float(row.get("shut_until", -1.0)),
			"cold_h": float(row.get("cold_h", 0.0)),
			"was_cold": bool(row.get("was_cold", false)),
			"alarm_day": float(row.get("alarm_day", -1.0)),
		}
	return {
		"seed": world_seed,
		"hours": _hours,
		"steps": _steps,
		"print": _net_print,
		"state": st,
	}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	world_seed = int(d.get("seed", world_seed))
	_hours = float(d.get("hours", _hours))
	days = _hours / 24.0
	_steps = int(d.get("steps", _steps))
	_last_clock = -1.0
	## The seats are cut from the net, so they must be cut again before any
	## saved state can be matched to one.
	boot(true)
	var st: Variant = d.get("state", {})
	if st is Dictionary:
		for id in (st as Dictionary).keys():
			## A croft the restored net has never heard of is dropped rather
			## than resurrected — the Wayfarers' rule, and the reason a net
			## fingerprint is worth saving at all.
			if not _by_id.has(String(id)):
				continue
			var row: Dictionary = (st as Dictionary)[id]
			state[String(id)] = {
				"stores": clampf(float(row.get("stores", STORE_START)), 0.0, STORE_MAX),
				"wash": String(row.get("wash", "none")),
				"dry_h": maxf(float(row.get("dry_h", 0.0)), 0.0),
				"shut_until": float(row.get("shut_until", -1.0)),
				"cold_h": maxf(float(row.get("cold_h", 0.0)), 0.0),
				"was_cold": bool(row.get("was_cold", false)),
				"alarm_day": float(row.get("alarm_day", -1.0)),
			}
	_said.clear()


# =============================== the hash ==================================

static func _hash(a: int, b: int, salt: int) -> int:
	## Deterministic, seed-driven, and the only source of variation in this
	## file. No engine roll of any kind appears anywhere in it, and the suite
	## asserts that against this source.
	var x := (a * 0x9E3779B1) ^ (b * 0x85EBCA6B) ^ salt
	x = (x ^ (x >> 15)) * 0x2545F491
	x = (x ^ (x >> 13)) * 0x27D4EB2F
	return absi(x ^ (x >> 16))


static func _unit(h: int, k: int) -> float:
	var x := _hash(h, k * 2654435761, 0x165667B1)
	return float(x % 1000003) / 1000003.0
