class_name Warbands
extends Node

## ===========================================================================
## WARBANDS -- the goblins hold a third of the political map, and until now
## there was not one goblin standing on it.
##
## `42a74e1` gave Myrkfell a frontier: eighteen regions, four claimants, a
## border that moves because a bad season moved it. `d2fe8a6` drew that border
## on the map, in the holder's colour, with the contested ground dashed. Both
## of them are TRUE of a world in which the goblins are a number. Walk into the
## Allagash -- 6.8 km2, no road anywhere in it, goblin-held on 384 of 384
## simulated days -- and it is an empty wood. The only goblin in Myrkfell lives
## in a cave, and the only other way to meet one is the spawn menu.
##
## THE ONE IDEA
##
##   A WARBAND DOES NOT SPAWN. IT CAMPS -- AND THE CAMP IS ALWAYS THERE.
##   WHO IS IN IT IS WHAT THE FRONTIER DECIDES.
##
## The 115 camp sites are a pure function of the map: march a lattice over the
## roster's bounds and keep the cells that are land, off the political sea,
## clear of every town, and DEEP -- no road within 220 m. That roster never
## changes. What changes is how many of them are OCCUPIED, which is the goblin
## SHARE of that region's ground, read straight out of the Chronicle's faction
## field. So a border that moves is not an abstraction any more: it is a fire
## that was not burning in that clearing last month, and you can walk to it.
##
## THE SECOND IDEA
##
##   THE CAMP IS WHERE THEY SLEEP. THE ROAD IS WHAT THEY COME OUT TO.
##
## A camp in the deep threatens nothing while its band is in it: measured over
## the whole net, the occupied camps put 0.00 bands per kilometre within 220 m
## of a road on men's ground, on contested ground and on goblin ground alike,
## because the median camp is 661 m off the nearest road. What makes the north
## dangerous is the PROWL. At dusk the band walks out toward the nearest road
## it can reach, stands on it at the dead of night, and is home before dawn --
## and that single term turns a flat map into a gradient:
##
##   on men's roads        0.19 bands per km
##   on CONTESTED roads    0.32
##   on goblin roads       0.56
##
## Three times as dangerous in the north as in the settled south, with the
## frontier sitting exactly where it should, in between. The same ground is
## empty at noon.
##
## THE THIRD IDEA -- and it is the first time a player can move the border
##
##   CLEAR A CAMP AND THE GOBLINS' GRIP LOOSENS. WHAT COMES INTO THE GAP IS
##   NOT UP TO YOU.
##
## Kill a staged band to the last goblin and the camp notes a negative goblin
## push against its region, in the one currency `Factions` speaks, and decays
## on the Chronicle's own fortnight half-life like every other thing that has
## happened. It does not hand the ground to men. `Factions.step`'s frontier
## rule gives vacated ground to whoever presses on it from next door, and in
## the north that is as likely to be the wolves -- which is the file's own
## stated idea (*nobody takes ground; ground is lost*) finally being true of
## the player as well as of the world.
##
## FOUR RULES THIS FILE WILL NOT BREAK
##
##   1. **The site roster is derived, never restated.** Not one camp position
##      is written down in here. The bounds come from `Chronicle.REGION_ROSTER`,
##      the region of a cell from `Factions.region_at`, the sea from
##      `Seasons.coast_u`, the towns from the Chronicle's own place list and
##      the roads from the `RoadNet`. Found a new fort and the camps move.
##   2. **It is deterministic.** No `RandomNumberGenerator`, no `randf`, no
##      `randi`, anywhere. Every bearing, jitter, name and band size is a hash
##      of (seed, id, salt), so the camp above Sebec is the same camp with the
##      same five goblins in it across a save, a reload and a rebuild.
##   3. **Step size cannot change the story.** The occupancy is a pure read of
##      the current share, so one step of half an hour and forty-eight of them
##      reach the same answer; only the `cleared_until` clock accumulates.
##   4. **It declares no `ready()`.** `RoadNet`, `Crofts` and `Wayfarers` each
##      declare a `ready()` METHOD, which shadows the `ready` SIGNAL every Node
##      already has -- an eval that called one parked the whole game at a
##      debugger break on 2026-09-12. This file says `built()` instead. There
##      are three of those traps in the project and this is not the fourth.
##
## WHAT WAS MEASURED, BEFORE ANY CONSTANT WAS CHOSEN
##
## `tools/probe_warbands.gd` and `tools/probe_warcamps*.gd`, five passes, and
## the first three of them killed a design each:
##
##   * **A camp cannot be seated on the road net.** The obvious rule -- a croft
##     is seated off a road, so seat a camp the same way -- puts NO camps in
##     ALLAGASH, which has 6.8 km2 and 0 m of road, and which is goblin ground
##     on every day of four simulated years. 42.9 % of the net's 40.2 km lies
##     in goblin or contested ground, so there is road to work; there is just
##     none at all where the goblins actually live.
##   * **A quota cannot be a fraction of the site count.** Seated per region by
##     rejection sampling at a 700 m spacing, fourteen of the seventeen land
##     regions get exactly ONE candidate site, so a quota expressed as a share
##     of them quantises to all-or-nothing. Marched instead, the same ground
##     yields 115 sites with a per-region spread of 0 to 21, and the quota is
##     fitted against AREA.
##   * **The clearing push was an order of magnitude too big, and the probe
##     that said otherwise was measuring nothing.** Pass three ran `step()`
##     against an EMPTY push bag and reported pushes of 0.15, 0.30 and 0.60
##     producing the bit-identical answer 0.380 -> 0.001: the anchors relaxing,
##     with no Chronicle attached at all. Re-run as a control against a
##     treatment on the same seed, a push of 0.2 every eight days took the
##     Allagash from a 0.614 goblin hold to 0.002 inside a game year and handed
##     it to the WOLVES.
##   * **And the constant had to be fitted at the sensitive end.** `PUSH_GAIN`
##     is divided by `1 + seats / SEAT_HALF`, and ALLAGASH HAS NO SEATS: its
##     gain is 0.0400 against Casco Bay's 0.0094, so a push in the roadless
##     north is worth 4.3x one at the city -- and the north is where the camps
##     are. `CLEAR_PUSH = 0.05` is the smallest value at which ONE cleared camp
##     is still visible against the noise of the Chronicle's own year (at 0.02
##     a single clearing measured +0.005 four weeks later, the wrong sign,
##     swamped by events), and the largest at which clearing a camp every
##     eight days for a year leaves the goblins still holding the Allagash
##     (-0.092 of 0.614).
##
## Adds NO input binding of any kind, and `WarbandTests._t_no_input` asserts
## that against this file's own source rather than against this sentence.
##
## Wired up by World.gd:
##     _warbands = Warbands.new()
##     add_child(_warbands); _warbands.bind_world(self)
## ===========================================================================


static var inst: Warbands = null

## A camp that was empty last step and is occupied now: the border moved, and
## this is where. `camp_abandoned` is its matched pair.
signal camp_raised(camp: Dictionary)
signal camp_abandoned(camp: Dictionary)
## Every goblin in a staged band is dead. Deliberately NOT `camp_abandoned`:
## abandoning is the frontier's doing and reversible on the next step, while
## clearing is the player's and holds the site empty for a fortnight.
signal camp_cleared(camp: Dictionary)


## ============================== the sky ===================================
## Mirrored rather than imported, exactly as Crofts mirrors them: this class
## must come up in a stripped test project with no Weather.gd in it.

const SKY_CLEAR := 0
const SKY_OVERCAST := 1
const SKY_DRIZZLE := 2
const SKY_RAIN := 3
const SKY_STORM := 4


## ============================== the clock =================================

## Half a game hour, matching `Chronicle.STEP_HOURS`, `Crofts.STEP_HOURS` and
## `Wayfarers.STEP_HOURS` -- four sims reading the same sky must reach the same
## day.
const STEP_HOURS := 0.5
const CATCHUP_STEPS := 240
const PRIME_DAYS := 2.0


## ============================ the site roster =============================

## The lattice pitch. Measured: 420 m gives 225 sites (too many to be places
## you remember), 700 m gives 66 and leaves two regions with none at all, and
## 560 m gives 115 with a per-region spread of 0 to 21 and only ACADIA empty --
## which is honest, because there is nowhere in Acadia a warband could sit
## unseen.
const PITCH := 560.0

## How far a site may be shoved off its lattice point, as a fraction of the
## pitch. Enough that a camp never reads as a grid; small enough that the
## spacing guarantee survives.
const JITTER := 0.70

## THE DEEP. No camp within this of a road: a warband that pitched on the
## highway would be a bandit, not a frontier. Measured against the net, this
## drops 10 of 125 candidate cells and leaves the median camp 661 m out.
const DEEP_M := 220.0

## Clear of every town by the same margin a croft keeps.
const CLEAR_OF_PLACE := 190.0

## `Seasons.coast_u` reads 1.0 on salt water. Factions' own number, for the
## same reason: the sea is not ground.
const SEA_U := 0.999

## A guard, not a design: the march over the roster's bounds at PITCH cannot
## reach it (115 at 560 m, 225 at 420 m).
const MAX_CAMPS := 400


## ============================== occupancy =================================

## Camps per square kilometre, per unit of goblin share ABOVE an even split.
## The floor is `Factions.NEUTRAL_SHARE` itself, read from there and never
## restated: ordinary country adds nothing, exactly as it adds nothing to every
## other offset in that file. Measured at the year-4 steady state, 2.5 puts 24
## camps on the map -- against 25 crofts and 20 travelling bands, which is the
## density of thing a player is meant to remember.
const CAMPS_PER_KM2 := 2.5

## A band is two to five. Measured: the occupied camps sit a median 525 m
## apart and the CLOSEST pair is 242 m, which is inside the strike radius, so
## two camps can be staged at once and the worst case is ten live goblins. The
## wildlife budget is twenty-six.
const SIZE_MIN := 2
const SIZE_MAX := 5

## A cleared camp stays empty for exactly as long as the world remembers what
## happened there -- `Factions.PUSH_HALFLIFE_DAYS`, read from there. When the
## push has decayed to half, the site is available again.
const CLEAR_PUSH := 0.05


## =============================== the night ================================

## Out after dusk, home before dawn, off `Crofts.daylight` so that two systems
## cannot disagree about when dark is. The winter working night runs 17.4 to
## 6.6 -- 13.2 hours -- against summer's 21.4 to 4.3, which is 6.9. A goblin's
## year is mostly decided by that one fact.
const OUT_AFTER_DUSK := 0.80
const IN_BEFORE_DAWN := 0.60

## A storm keeps them in. Rain does not: `fc10574` established that rain buys
## stealth in this world, and a raiding party is not a crofter's washing.
const HOLD_SKY := SKY_STORM

## How far a band will walk from its camp, before the season. Measured against
## the real camp-to-road distribution (p25 403 m, p50 661, p75 1112): at 450 m
## only 3 of 24 occupied camps can reach a road and CONTESTED ground reads
## 0.00 bands/km -- the frontier would be exactly as safe as the capital. At
## 900 m, 10 of 24 work a road and the gradient comes out 0.19 / 0.32 / 0.56
## across men's, contested and goblin roads. At 1200 the contested reading
## stops improving while men's roads get worse.
const PROWL_M := 900.0

## A camp with no road inside its reach still works its own ground rather than
## sitting in the dark being a prop.
const PROWL_NEAR := 220.0

## Winter walks further and summer barely leaves the trees. The same 900 m
## becomes 1170 in winter and 765 in summer, which moves camps across the
## threshold: the clearing 950 m off the Sebec road never touches it between
## May and September and is on it every night in January.
const SEASON_REACH: Array[float] = [1.00, 0.85, 1.05, 1.30]


## ============================== staging ===================================

const STAGE_RADIUS := 240.0
const STRIKE_RADIUS := 330.0
const MAX_STAGED := 2
const SCAN_SECONDS := 1.2
const GROUND_PROBE := 600.0

## A camp is a fire ring, two lean-tos and a meat pole, and every one of them
## is below waist height. `a23a20e` found a whole moose invisible at four
## metres in standing grass and `3a24658` found the same of a farmyard, so the
## clearing is mown the same way both of those were.
const CAMP_MOW_M := 14.0

## Close enough to notice what the camp is doing, for the rumour feed.
const NOTICE_M := 165.0


## =============================== the hash =================================

const SALT_SITE := 0x9E3779B1
const SALT_NAME := 0x85EBCA6B
const SALT_SIZE := 0xC2B2AE35
const SALT_BEAR := 0x27D4EB2F
const SALT_RANK := 0x165667B1
const SALT_BODY := 0x2545F491

## Goblin bands are named for the thing they did or the place they sit. Two
## words, hashed, and they read as something a crofter would call them.
const BAND_FIRST: Array[String] = [
	"Crookback", "Sourwater", "Blackpine", "Nine Teeth", "Ratchet",
	"Grimhollow", "Coldspoil", "Thistle", "Ash Heap", "Longclaw",
	"Bogmyrtle", "Tarpit", "Hookjaw", "Stonecrop", "Windgall",
]
const BAND_SECOND: Array[String] = [
	"camp", "fires", "hollow", "sty", "warren", "roost", "midden",
]


## =============================== the state ================================

var enabled := true
var world_seed := 20260912

## The site roster: pure function of the map, rebuilt when the net changes.
var camps: Array = []
## id -> {held, strength, raised, cleared_until, seen}
var state: Dictionary = {}

var days := 0.0

var net: Object = null            ## a RoadNet, duck-typed on four methods
var chron: Object = null          ## a Chronicle, duck-typed on three
var feed: Object = null           ## a RumourFeed, duck-typed on `offer`
var player: Node3D = null
var clock: Node = null            ## a DayNight: `day` + `hour`

var _ground: Object = null
var _booted := false
var _net_print := 0
var _by_id: Dictionary = {}
var _regions: Array = []          ## land region names, sorted
var _areas: Dictionary = {}       ## region -> km2, marched
var _sites_in: Dictionary = {}    ## region -> Array of camp dictionaries, ranked
var _staged: Dictionary = {}      ## id -> Node3D holder
var _bodies: Dictionary = {}      ## id -> Array[Enemy]
var _counted: Dictionary = {}     ## id -> Dictionary of body index -> true
var _hours := 0.0
var _steps := 0
var _ran := 0
var _last_clock := -1.0
var _scan_t := 0.0
var _said: Dictionary = {}
var _mown: Dictionary = {}
var _build_ms := 0.0
## Rumours are suppressed for the steps the sim walks to CATCH UP with the sky.
## `_adopt` runs two primed days in one frame; without this the board at every
## place in Myrkfell would carry two dozen "there are fires in the..." lines on
## the first frame of a new game, all of them dated today.
var _quiet_until := 0.0

## Counters, for the report and for the suite.
var raised_total := 0
var abandoned_total := 0
var cleared_total := 0
var killed_total := 0
var last_examined := 0


# ============================ THE RULES, STATIC =============================
# Everything a test can ask without a node, a clock or a pixel.


static func bounds() -> Vector4:
	## The map's own extent, from the region roster and nothing else. x,y is
	## the minimum corner and z,w the maximum, in world metres.
	var minx := INF
	var maxx := -INF
	var minz := INF
	var maxz := -INF
	for r in Chronicle.REGION_ROSTER:
		var rd := r as Dictionary
		var c: Vector2 = rd.get("pos", Vector2.ZERO)
		var rad := float(rd.get("r", 500.0))
		minx = minf(minx, c.x - rad)
		maxx = maxf(maxx, c.x + rad)
		minz = minf(minz, c.y - rad)
		maxz = maxf(maxz, c.y + rad)
	return Vector4(minx, minz, maxx, maxz)


static func lattice(pitch: float, seed_i: int) -> Array:
	## The candidate cells, jittered off a regular grid so that nothing in the
	## finished world reads as a lattice. Deterministic in (seed, cell).
	var out: Array = []
	if pitch <= 0.0:
		return out
	var b := bounds()
	var nx := int((b.z - b.x) / pitch)
	var nz := int((b.w - b.y) / pitch)
	for ix in range(nx):
		for iz in range(nz):
			var h := _hash(seed_i, ix * 1000 + iz, SALT_SITE)
			var jx := (_unit(h, 1) - 0.5) * pitch * JITTER
			var jz := (_unit(h, 2) - 0.5) * pitch * JITTER
			out.append(Vector2(b.x + (float(ix) + 0.5) * pitch + jx,
					b.y + (float(iz) + 0.5) * pitch + jz))
	return out


static func on_sea(p: Vector2) -> bool:
	return Seasons.coast_u(Vector3(p.x, 0.0, p.y)) >= SEA_U


static func clear_of_places(p: Vector2, places: Array, margin: float) -> bool:
	## True when nothing on the place list is within `margin`.
	for q in places:
		if not (q is Vector2):
			continue
		if (q as Vector2).distance_to(p) < margin:
			return false
	return true


static func is_deep(road_dist: float, deep: float) -> bool:
	## A road further away than `deep` -- or no road at all, which is what a
	## negative distance means and which is the whole of the Allagash.
	if road_dist < 0.0:
		return true
	return road_dist >= deep


static func quota(share: float, km2: float, sites: int) -> int:
	## How many camps a region's ground supports. The excess over an even
	## split is the driver, read from `Factions.NEUTRAL_SHARE` rather than
	## written down again here, so ordinary country carries nothing.
	if sites <= 0 or km2 <= 0.0:
		return 0
	var excess := maxf(0.0, share - Factions.NEUTRAL_SHARE)
	return mini(sites, int(round(excess * CAMPS_PER_KM2 * km2)))


static func size_for(share: float, h: int) -> int:
	## Two to five, leaning on how hard the goblins hold the ground. A band on
	## the frontier is a handful; a band in the Allagash is a war party.
	var t := clampf((share - Factions.NEUTRAL_SHARE) / (1.0 - Factions.NEUTRAL_SHARE), 0.0, 1.0)
	var base := float(SIZE_MIN) + t * float(SIZE_MAX - SIZE_MIN)
	## ⚠ The wobble spans 1.5, not 1.0. At a share of 0.5 the base is exactly
	## 3.0, and a half-wide wobble rounds to three EVERY TIME -- every band in
	## the region the same size, with a term in the file that could not move
	## anything. `WarbandTests._t_size` caught it by asking whether the hash
	## changed the answer at all, and it did not.
	var wobble := (_unit(h, 5) - 0.5) * 1.5
	return clampi(int(round(base + wobble)), SIZE_MIN, SIZE_MAX)


static func night(season: int) -> Vector2:
	## When a band is out. `x` is the hour it leaves, `y` the hour it is home,
	## and `x > y` because a night wraps midnight. Off `Crofts.daylight`, so
	## the goblins and the crofters cannot disagree about when dark is.
	var dl := Crofts.daylight(season)
	return Vector2(minf(dl.y + OUT_AFTER_DUSK, 23.90),
			maxf(dl.x - IN_BEFORE_DAWN, 0.10))


static func night_hours(season: int) -> float:
	var w := night(season)
	return fposmod(w.y - w.x, 24.0)


static func is_night(hour: float, win: Vector2) -> bool:
	var h := fposmod(hour, 24.0)
	if win.x > win.y:
		return h >= win.x or h < win.y
	return h >= win.x and h < win.y


static func reach_for(season: int) -> float:
	return PROWL_M * SEASON_REACH[clampi(season, 0, 3)]


static func prowl_u(hour: float, win: Vector2) -> float:
	## How far along its night the band is, as a fraction of the way OUT: 0 at
	## the camp, 1 at the far point in the dead of the night, 0 again by the
	## time it is home. A triangle, so the band is somewhere real at every hour
	## rather than teleporting between two states.
	var len_h := fposmod(win.y - win.x, 24.0)
	if len_h <= 0.0:
		return 0.0
	if not is_night(hour, win):
		return 0.0
	var t := fposmod(fposmod(hour, 24.0) - win.x, 24.0) / len_h
	return clampf(1.0 - absf(2.0 * t - 1.0), 0.0, 1.0)


static func far_point(camp: Dictionary, season: int) -> Vector2:
	## Where this band's night is aimed. The nearest road if the season's
	## reach can get there, otherwise a hashed bearing across its own ground.
	var pos: Vector2 = camp.get("pos", Vector2.ZERO)
	var rd := float(camp.get("road_d", -1.0))
	if rd >= 0.0 and rd <= reach_for(season):
		return camp.get("road", pos)
	var ang := float(camp.get("bearing", 0.0))
	return pos + Vector2(cos(ang), sin(ang)) * PROWL_NEAR


static func works_road(camp: Dictionary, season: int) -> bool:
	var rd := float(camp.get("road_d", -1.0))
	return rd >= 0.0 and rd <= reach_for(season)


static func routine_at(camp: Dictionary, hour: float, sky: int, season: int) -> Dictionary:
	## THE WHOLE OF WHAT A WARBAND DOES, as a pure function of the hour, the
	## sky and the season. `station` is "camp" or "prowl"; `at` is where the
	## band is on the flat; `reason` says which branch decided it.
	var win := night(season)
	var dark := is_night(hour, win)
	if sky >= HOLD_SKY:
		return {"station": "camp", "at": camp.get("pos", Vector2.ZERO), "u": 0.0,
				"reason": "storm" if dark else "day"}
	if not dark:
		return {"station": "camp", "at": camp.get("pos", Vector2.ZERO), "u": 0.0,
				"reason": "day"}
	var u := prowl_u(hour, win)
	var far := far_point(camp, season)
	var pos: Vector2 = camp.get("pos", Vector2.ZERO)
	var at := pos.lerp(far, u)
	var why := "road" if works_road(camp, season) else "ground"
	return {"station": "prowl" if u > 0.02 else "camp", "at": at, "u": u,
			"reason": why if u > 0.02 else "dusk"}


static func legible(camp: Dictionary, r: Dictionary, strength: int) -> String:
	## What you can tell by looking, in a sentence a rumour board would print.
	var where := Factions.pretty(String(camp.get("region", "")))
	if strength <= 0:
		return "The %s above %s stands cold and empty." % [
			String(camp.get("kind", "camp")), where]
	var many := "a lone goblin" if strength <= 1 else "%d of them" % strength
	if String(r.get("station", "camp")) == "prowl":
		if String(r.get("reason", "")) == "road":
			return "%s is out on the road tonight, %s." % [String(camp.get("name", "A band")), many]
		return "%s is abroad in the %s, %s." % [String(camp.get("name", "A band")), where, many]
	return "%s keeps a fire in the %s, %s." % [String(camp.get("name", "A band")), where, many]


# ============================== the lifecycle ==============================


func _ready() -> void:
	boot()


func _exit_tree() -> void:
	if inst == self:
		inst = null


func boot(force := false) -> void:
	## Idempotent by contract, the same as Crofts: World calls it, `_ready`
	## calls it, and the suite calls it three times in a row.
	if inst == null or not is_instance_valid(inst):
		inst = self
	if is_inside_tree() and not is_in_group("warbands"):
		add_to_group("warbands")
	if _booted and not force:
		if _net_ready() and _fingerprint() != _net_print:
			_rebuild()
		return
	_booted = true
	_rebuild()


func bind_world(w: Node) -> void:
	## Duck-typed on every hook, for the reason the Road Net, the Wayfarers and
	## the Crofts are: this class must come up inside the full game and inside
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
	if chron != null and not chron.has_method("sky_at"):
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
	return o.has_method("nearest_road") and o.has_method("fingerprint")


func _net_ready() -> bool:
	## ⚠ `has_method("ready")` first, ALWAYS. `ready` is a signal on every
	## Node and RoadNet shadows it with a method; asking the wrong object
	## parks the game at a debugger break.
	if net == null or not is_instance_valid(net):
		return false
	if net.has_method("ready") and not bool(net.call("ready")):
		return false
	return true


func _fingerprint() -> int:
	if not _net_ready():
		return 0
	return int(net.call("fingerprint"))


func built() -> bool:
	## NOT called `ready()`. See rule 4 in the header.
	return _booted and not camps.is_empty()


# ============================== the seating ================================


func _rebuild() -> void:
	var t0 := Time.get_ticks_usec()
	camps.clear()
	_by_id.clear()
	_sites_in.clear()
	_clear_bodies()
	_net_print = _fingerprint()

	var seats := Factions.seats_from(_places_rows())
	_regions = Factions.land_regions(Chronicle.REGION_ROSTER, seats)
	_areas = _march_areas()
	var places := _place_points()

	var cells := lattice(PITCH, world_seed)
	for i in range(cells.size()):
		if camps.size() >= MAX_CAMPS:
			break
		var p: Vector2 = cells[i]
		var region := Factions.region_at(Vector3(p.x, 0.0, p.y), Chronicle.REGION_ROSTER)
		if not _regions.has(region):
			continue
		if on_sea(p):
			continue
		if not clear_of_places(p, places, CLEAR_OF_PLACE):
			continue
		var rp := _road_at(p)
		if not is_deep(float(rp.get("dist", -1.0)), DEEP_M):
			continue
		var h := _hash(world_seed, i, SALT_SITE)
		var camp := {
			"id": "%s#%d" % [region, i],
			"cell": i,
			"region": region,
			"pos": p,
			"road": rp.get("point", p),
			"road_d": float(rp.get("dist", -1.0)),
			"bearing": _unit(h, 3) * TAU,
			"jit": _unit(h, 4),
			"rank": _hash(world_seed, i, SALT_RANK),
			"name": _name_for(i),
			"kind": "camp",
		}
		camps.append(camp)
		_by_id[String(camp["id"])] = camp

	for c in camps:
		var cd := c as Dictionary
		var rn := String(cd["region"])
		if not _sites_in.has(rn):
			_sites_in[rn] = []
		(_sites_in[rn] as Array).append(cd)
	## Ranked once, by the hash and then by id, so the SAME sites are the
	## occupied ones every time a quota of three is asked for.
	for rn in _sites_in.keys():
		var rows: Array = _sites_in[rn]
		rows.sort_custom(func(a, b):
			var ai := int((a as Dictionary)["rank"])
			var bi := int((b as Dictionary)["rank"])
			if ai != bi:
				return ai < bi
			return String((a as Dictionary)["id"]) < String((b as Dictionary)["id"]))
	for c2 in camps:
		_ensure_state(String((c2 as Dictionary)["id"]))
	_build_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func _places_rows() -> Array:
	## The Chronicle's own place list, in the shape `Factions.seats_from` wants.
	if chron == null or not is_instance_valid(chron):
		return []
	var pv: Variant = chron.get("places")
	if not (pv is Array):
		return []
	return pv as Array


func _place_points() -> Array:
	var out: Array = []
	for p in _places_rows():
		if not (p is Dictionary):
			continue
		var pd := p as Dictionary
		var v: Variant = pd.get("pos", null)
		if v is Vector2:
			out.append(v as Vector2)
	return out


func _march_areas() -> Dictionary:
	## Region areas, by marching `Factions.region_at` over the same 130 x 195
	## grid the map's frontier layer uses. Derived, so a roster edit moves the
	## quotas with it.
	var b := bounds()
	var cw := (b.z - b.x) / 130.0
	var chh := (b.w - b.y) / 195.0
	var out := {}
	for ix in range(130):
		for iz in range(195):
			var rn := Factions.region_at(Vector3(b.x + (float(ix) + 0.5) * cw, 0.0,
					b.y + (float(iz) + 0.5) * chh), Chronicle.REGION_ROSTER)
			out[rn] = float(out.get(rn, 0.0)) + cw * chh / 1.0e6
	return out


func _road_at(p: Vector2) -> Dictionary:
	## Distance to the nearest road, and the point on it. A missing or unready
	## net answers -1, which `is_deep` reads as "no road at all" -- the
	## Allagash's real answer, and the headless suite's.
	if not _net_ready() or not net.has_method("nearest_road"):
		return {"dist": -1.0, "point": p}
	var r: Variant = net.call("nearest_road", p)
	if not (r is Dictionary) or (r as Dictionary).is_empty():
		return {"dist": -1.0, "point": p}
	var rd := r as Dictionary
	return {"dist": float(rd.get("dist", -1.0)), "point": rd.get("point", p)}


func _name_for(i: int) -> String:
	var h := _hash(world_seed, i, SALT_NAME)
	var a := String(BAND_FIRST[h % BAND_FIRST.size()])
	var b := String(BAND_SECOND[_hash(h, i, SALT_NAME) % BAND_SECOND.size()])
	return "%s %s" % [a, b]


func _ensure_state(id: String) -> Dictionary:
	if not state.has(id):
		state[id] = {
			"held": false,
			"strength": 0,
			"raised": -1.0,
			"cleared_until": -1.0,
			"seen": false,
		}
	return state[id]


# ============================== the simulation =============================


func _process(delta: float) -> void:
	if not enabled:
		return
	_tick_clock()
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = SCAN_SECONDS
		sense()
		_reap()
	_drive_bodies()


func _tick_clock() -> void:
	## The game's clock, never the frame delta -- a sleep must walk the week
	## that passed. The same shape as `Chronicle._process`, `Crofts._tick_clock`
	## and `Wayfarers._tick_clock`, deliberately.
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
	## DayNight boots at day 30 while a fresh sim sits at zero. Left alone,
	## every dusk gate would be judged against a clock the sky has never heard
	## of and the bands would be out at noon.
	var drift := now * 24.0 - _hours
	if absf(drift) <= 24.0:
		return
	_hours = now * 24.0
	days = _hours / 24.0
	_quiet_until = days
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
	for rn in _regions:
		_step_region(String(rn), t)


func _step_region(region: String, t: float) -> void:
	## WHO IS IN THE CAMPS, and it is a pure read of the frontier. The quota
	## comes off the goblin share of this region's ground; the sites that fill
	## it are the first `want` by rank, skipping any the player has cleared
	## inside the fortnight.
	var rows: Array = _sites_in.get(region, [])
	if rows.is_empty():
		return
	var share := share_of(region)
	var want := quota(share, float(_areas.get(region, 0.0)), rows.size())
	var filled := 0
	for r in rows:
		var c := r as Dictionary
		var id := String(c["id"])
		var st := _ensure_state(id)
		var barred := float(st["cleared_until"]) > t
		var wants_this := filled < want and not barred
		if wants_this:
			filled += 1
		var was := bool(st["held"])
		if wants_this == was:
			continue
		st["held"] = wants_this
		if wants_this:
			st["strength"] = size_for(share, _hash(world_seed, int(c["cell"]), SALT_SIZE))
			st["raised"] = t
			st["seen"] = false
			raised_total += 1
			if t >= _quiet_until:
				_rumour(c, "There are fires in the %s again -- %s, by the look of it." % [
						Factions.pretty(region), String(c["name"])])
			camp_raised.emit(c)
		else:
			st["strength"] = 0
			abandoned_total += 1
			if t >= _quiet_until:
				_rumour(c, "%s has moved on; the %s in the %s stands cold." % [
						String(c["name"]), String(c["kind"]), Factions.pretty(region)])
			camp_abandoned.emit(c)


func share_of(region: String) -> float:
	## The goblin share of this region's ground, out of the Chronicle's own
	## faction field. No field bound at all -- the headless case -- reads as an
	## even split, which `quota` turns into no camps rather than into a default
	## number of them.
	if chron == null or not is_instance_valid(chron):
		return Factions.NEUTRAL_SHARE
	var fv: Variant = chron.get("factions")
	if not (fv is Dictionary) or (fv as Dictionary).is_empty():
		return Factions.NEUTRAL_SHARE
	return float(Factions.hold_of(fv as Dictionary, region).get(Factions.GOBLINS,
			Factions.NEUTRAL_SHARE))


static func clear_days() -> float:
	## Exactly as long as the world remembers what happened there. Read from
	## `Factions`, so the two cannot drift apart.
	return Factions.PUSH_HALFLIFE_DAYS


func sky_at(t: float) -> int:
	## The sky the CHRONICLE believes in, never the live `Weather`: the live
	## one is `_rng`-driven and only answers for now, and a consumer that
	## reached for it would put a number in the save's future that the save
	## cannot reproduce. The Wayfarers' rule, and the Crofts'.
	if chron != null and is_instance_valid(chron) and chron.has_method("sky_at"):
		return clampi(int(chron.call("sky_at", t)), 0, 4)
	return SKY_CLEAR


func season_at(t: float) -> int:
	if chron != null and is_instance_valid(chron) and chron.has_method("season_at"):
		return clampi(int(chron.call("season_at", t)), 0, 3)
	return int(fposmod(t, 96.0) / 24.0) % 4


func season_here(t: float, c: Dictionary) -> int:
	## [seasons] The season AT THIS CAMP. A band in the north gets the long
	## winter -- and the long winter is the one that puts it on the road --
	## through `season_at`, never through `Seasons.local_index` directly,
	## because the Chronicle owns the calendar and geography only moves which
	## day this camp is living in. The Crofts' rule.
	var p: Vector2 = c.get("pos", Vector2.ZERO)
	return season_at(t + Seasons.warp_days(t, Vector3(p.x, 0.0, p.y)))


func hour_now() -> float:
	return fposmod(days * 24.0, 24.0)


func routine_of(id: String) -> Dictionary:
	var c: Dictionary = _by_id.get(id, {})
	if c.is_empty():
		return {}
	return routine_at(c, hour_now(), sky_at(days), season_here(days, c))


func state_of(id: String) -> Dictionary:
	return _ensure_state(id)


func camp_by_id(id: String) -> Dictionary:
	return _by_id.get(id, {})


func strength_of(id: String) -> int:
	return int(_ensure_state(id)["strength"])


func occupied(id: String) -> bool:
	return bool(_ensure_state(id)["held"]) and strength_of(id) > 0


func held_ids() -> Array:
	var out: Array = []
	for c in camps:
		var id := String((c as Dictionary)["id"])
		if occupied(id):
			out.append(id)
	out.sort()
	return out


func near(pos: Vector3, radius: float) -> Array:
	## Every camp within `radius` of a point, nearest first, measured at the
	## BAND's position rather than the camp's -- a band out on the road at
	## midnight is where the band is, not where its bedrolls are.
	var here := Vector2(pos.x, pos.z)
	var out: Array = []
	var sky := sky_at(days)
	var hr := hour_now()
	for c in camps:
		var cd := c as Dictionary
		var r := routine_at(cd, hr, sky, season_here(days, cd))
		var at: Vector2 = r.get("at", cd["pos"])
		var d := at.distance_to(here)
		if d <= radius:
			out.append({"camp": cd, "dist": d, "at": at, "routine": r})
	out.sort_custom(func(a, b):
		if not is_equal_approx(float(a["dist"]), float(b["dist"])):
			return float(a["dist"]) < float(b["dist"])
		return String((a["camp"] as Dictionary)["id"]) < String((b["camp"] as Dictionary)["id"]))
	return out


# ============================= the consequence =============================


func clear_camp(id: String) -> bool:
	## THE PLAYER'S HAND ON THE FRONTIER. Every goblin in the band is dead, so
	## the site is barred for a fortnight and the region carries a negative
	## goblin push -- which does NOT hand the ground to men. `Factions.step`
	## gives vacated ground to whoever presses on it from next door, and in the
	## north that is as often the wolves. Nobody takes ground.
	var c: Dictionary = _by_id.get(id, {})
	if c.is_empty():
		return false
	var st := _ensure_state(id)
	if float(st["cleared_until"]) > days:
		return false
	st["held"] = false
	st["strength"] = 0
	st["cleared_until"] = days + clear_days()
	cleared_total += 1
	var landed := push_clear(String(c["region"]))
	_rumour(c, "%s is burnt out. Whatever was keeping the %s in the %s, it is not there now." % [
			String(c["name"]), String(c["kind"]), Factions.pretty(String(c["region"]))])
	camp_cleared.emit(c)
	return landed


func push_clear(region: String) -> bool:
	## The push, and it returns WHETHER IT LANDED. That is not decoration:
	## `Factions.note` refuses a region its bag has never heard of -- the Gulf
	## of Maine is a real case -- and without the return there is nothing for a
	## test to assert, because Godot swallows the missing-key read and the
	## write lands in a discarded temporary.
	##
	## ⚠ The tag is "goblins" because that is the string `Factions.TAG_CLAIM`
	## maps to GOBLINS. `Crofts.ALARM_TAGS` named four tags the Chronicle has
	## never emitted and no croft barred its door for two weeks; the suite
	## asserts this one against that table rather than against this comment.
	if chron == null or not is_instance_valid(chron):
		return false
	var fp: Variant = chron.get("fpush")
	if not (fp is Dictionary):
		return false
	return Factions.note(fp as Dictionary, region, {"goblins": -CLEAR_PUSH})


func _rumour(c: Dictionary, text: String) -> bool:
	## Word gets to the nearest place that has anybody in it. Through
	## `Chronicle.deposit_rumour`, which is the real front door and keeps the
	## rumour's own day -- three mutations of it survived the Wayfarers' green
	## because the only suite using it used a stub.
	if chron == null or not is_instance_valid(chron):
		return false
	if not chron.has_method("nearest_place") or not chron.has_method("deposit_rumour"):
		return false
	var p: Vector2 = c.get("pos", Vector2.ZERO)
	var place: Variant = chron.call("nearest_place", Vector3(p.x, 0.0, p.y), 4000.0)
	if not (place is Dictionary) or (place as Dictionary).is_empty():
		return false
	var nm := String((place as Dictionary).get("name", ""))
	if nm.is_empty():
		return false
	return bool(chron.call("deposit_rumour", nm, {
		"text": text, "kind": "goblins", "day": days}))


func sense() -> void:
	## Walk close enough to a camp and you notice what it is doing, once per
	## state -- so a camp you pass every day is not narrating itself at you,
	## but one whose fire has gone out since last time says so.
	if feed == null or not is_instance_valid(feed) or not feed.has_method("offer"):
		return
	if player == null or not is_instance_valid(player):
		return
	var rows := near(player.global_position, NOTICE_M)
	if rows.is_empty():
		return
	var row := rows[0] as Dictionary
	var c := row["camp"] as Dictionary
	var id := String(c["id"])
	var st := _ensure_state(id)
	var r := row["routine"] as Dictionary
	var key := "%s|%s|%s|%d" % [id, String(r["station"]), String(r["reason"]),
			int(st["strength"])]
	if _said.has(key):
		return
	if bool(feed.call("offer", legible(c, r, int(st["strength"])),
			String(c["name"]), "warband", days)):
		_said[key] = true


# ================================ the camp =================================


func _restage(pos: Vector3) -> void:
	## Stage what is close, strike what is not, and never both in one pass for
	## one camp -- the Director's hysteresis, so a player walking the boundary
	## does not rebuild a camp every scan. Only OCCUPIED camps stage: an empty
	## site is not a prop, it is nothing, which is the point of the feature.
	if not is_inside_tree():
		return
	var here := Vector2(pos.x, pos.z)
	for id in _staged.keys():
		var sid := String(id)
		var c: Dictionary = _by_id.get(sid, {})
		## Distance ALONE strikes a staged camp. Occupancy is a condition on
		## staging something NEW, never on keeping what is already there: a
		## camp struck the instant its last goblin died would take the corpses,
		## the fire and the lean-tos with it while the player watched.
		var keep := not c.is_empty()
		if keep:
			var at: Vector2 = c.get("pos", Vector2.ZERO)
			if at.distance_to(here) > STRIKE_RADIUS:
				keep = false
		if not keep:
			_strike(sid)
	for row in near(pos, STAGE_RADIUS):
		if _staged.size() >= MAX_STAGED:
			break
		var c2 := (row as Dictionary)["camp"] as Dictionary
		var id2 := String(c2["id"])
		if _staged.has(id2) or not occupied(id2):
			continue
		var body := _build_camp(c2)
		if body == null:
			continue
		add_child(body)
		_staged[id2] = body
		_counted[id2] = {}
		_spawn_band(id2, c2, (row as Dictionary)["at"] as Vector2)


func _strike(id: String) -> void:
	## Nodes torn down, record kept -- the Incident Director's rule. Striking a
	## camp is a rendering decision and must never be read as a kill, which is
	## why `_counted` is dropped with the bodies.
	var n: Variant = _staged.get(id, null)
	if n is Node and is_instance_valid(n as Node):
		(n as Node).queue_free()
	_staged.erase(id)
	var bs: Array = _bodies.get(id, [])
	for b in bs:
		if b is Node and is_instance_valid(b as Node):
			(b as Node).queue_free()
	_bodies.erase(id)
	_counted.erase(id)


func _clear_bodies() -> void:
	for id in _staged.keys():
		_strike(String(id))
	_staged.clear()
	_bodies.clear()
	_counted.clear()


func staged_ids() -> Array:
	var out: Array = _staged.keys()
	out.sort()
	return out


func live_goblins() -> int:
	var n := 0
	for id in _bodies.keys():
		for b in (_bodies[id] as Array):
			if b is Node3D and is_instance_valid(b as Node3D) and not bool((b as Node).get("dying")):
				n += 1
	return n


func _drive_bodies() -> void:
	if player != null and is_instance_valid(player):
		_restage(player.global_position)
	for id in _staged.keys():
		var body: Variant = _staged.get(String(id), null)
		if not (body is Node3D) or not is_instance_valid(body as Node3D):
			_staged.erase(String(id))
			continue
		var fire := (body as Node3D).get_node_or_null("Fire")
		if fire != null and is_instance_valid(fire):
			_drive_fire(fire, sky_at(days) < HOLD_SKY)


func _drive_fire(fire: Node, want: bool) -> void:
	## A real Firepit, in the "fires" group, so a goblin camp warms whatever
	## stands at it through `Firepit.heat_from` exactly as a croft's hearth
	## does -- including the player, who is welcome to it once the band is
	## dead. Left burning while the band is out: they banked it and went.
	if not want:
		if fire.has_method("douse"):
			fire.call("douse")
		return
	if not fire.has_method("light") or not fire.has_method("feed"):
		return
	var fuel := float(fire.get("fuel")) if "fuel" in fire else 0.0
	if fuel < 300.0:
		if fire.has_method("burning") and bool(fire.call("burning")):
			fire.call("feed", 600.0)
		else:
			fire.call("light", 900.0)


func _spawn_band(id: String, c: Dictionary, at: Vector2) -> void:
	## Real `Goblin`s with the real `Enemy` AI, standing where the SIM says the
	## band is -- which at midnight is out on the road and at noon is at the
	## fire. Nothing here drives them afterwards: a staged band is a fight, and
	## a fight is Enemy.gd's business.
	var st := _ensure_state(id)
	var n := int(st["strength"])
	if n <= 0:
		return
	var out: Array = []
	var holder: Variant = _staged.get(id, null)
	if not (holder is Node3D) or not is_instance_valid(holder as Node3D):
		return
	var base := Vector3(at.x, _ground_y(at), at.y)
	for i in range(n):
		var g := Goblin.new()
		var h := _hash(world_seed, int(c["cell"]) * 31 + i, SALT_BODY)
		var ang := _unit(h, 1) * TAU
		var rad := 1.2 + _unit(h, 2) * 2.6
		(holder as Node3D).add_child(g)
		g.global_position = base + Vector3(cos(ang) * rad, 0.9, sin(ang) * rad)
		out.append(g)
	_bodies[id] = out


func _reap() -> void:
	## KILL ACCOUNTING. A body that has gone `dying` is counted once, and a
	## body that merely VANISHED is not counted at all -- `_strike` frees whole
	## bands when the player walks away, and reading that as a victory would
	## clear every camp in the north by ignoring it.
	for id in _bodies.keys():
		var sid := String(id)
		var bs: Array = _bodies.get(sid, [])
		var seen: Dictionary = _counted.get(sid, {})
		var st := _ensure_state(sid)
		for i in range(bs.size()):
			if seen.has(i):
				continue
			var b: Variant = bs[i]
			if not (b is Node) or not is_instance_valid(b as Node):
				continue
			if not bool((b as Node).get("dying")):
				continue
			seen[i] = true
			killed_total += 1
			st["strength"] = maxi(0, int(st["strength"]) - 1)
		_counted[sid] = seen
		if int(st["strength"]) <= 0 and bool(st["held"]):
			clear_camp(sid)


func _ground_y(flat: Vector2) -> float:
	## Duck-typed, and null is the normal case: the headless suite has no
	## terrain and every camp in it stands honestly at y = 0.
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


func _build_camp(c: Dictionary) -> Node3D:
	## The camp itself always stands at the CAMP, never at the band's prowl
	## point: the fire ring does not walk to the road. `at` only decides where
	## the goblins are.
	var p: Vector2 = c.get("pos", Vector2.ZERO)
	var root := Node3D.new()
	root.name = "Warcamp_%s" % String(c["id"]).replace("#", "_")
	root.position = Vector3(p.x, _ground_y(p), p.y)
	root.rotation.y = float(c.get("bearing", 0.0))

	var fire := Firepit.make()
	fire.name = "Fire"
	root.add_child(fire)

	_build_stones(root)
	var h := _hash(world_seed, int(c["cell"]), SALT_BODY)
	_build_lean_to(root, Vector3(-2.1, 0.0, -0.6), 0.6, h)
	_build_lean_to(root, Vector3(1.4, 0.0, 1.9), -2.3, h + 7)
	_build_pole(root, Vector3(2.4, 0.0, -1.6))
	_build_stakes(root, h)
	_mow_camp(root.position)
	return root


func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	return m


func _box(root: Node3D, size: Vector3, at: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(col)
	mi.position = at
	root.add_child(mi)
	return mi


func _build_stones(root: Node3D) -> void:
	## Seven stones round the fire. The ring is what reads as a CAMP from
	## twenty metres off, once the grass is down.
	for i in range(7):
		var a := TAU * float(i) / 7.0
		var s := _box(root, Vector3(0.42, 0.26, 0.42),
				Vector3(cos(a) * 1.05, 0.13, sin(a) * 1.05), Color(0.34, 0.33, 0.31))
		s.rotation.y = a


func _build_lean_to(root: Node3D, at: Vector3, yaw: float, h: int) -> void:
	var n := Node3D.new()
	n.name = "LeanTo"
	n.position = at
	n.rotation.y = yaw
	root.add_child(n)
	_box(n, Vector3(0.12, 1.05, 0.12), Vector3(-0.7, 0.52, 0.0), Color(0.24, 0.19, 0.14))
	_box(n, Vector3(0.12, 1.05, 0.12), Vector3(0.7, 0.52, 0.0), Color(0.24, 0.19, 0.14))
	var hide := _box(n, Vector3(1.7, 0.08, 1.5), Vector3(0.0, 0.85, -0.45),
			Color(0.33, 0.27, 0.20))
	hide.rotation.x = -0.55 - _unit(h, 6) * 0.15
	_box(n, Vector3(1.3, 0.10, 0.75), Vector3(0.0, 0.06, 0.30), Color(0.28, 0.25, 0.18))


func _build_pole(root: Node3D, at: Vector3) -> void:
	## The meat pole. Whatever is hanging on it is nobody's business.
	var n := Node3D.new()
	n.name = "Pole"
	n.position = at
	root.add_child(n)
	_box(n, Vector3(0.10, 1.80, 0.10), Vector3(-0.55, 0.90, 0.0), Color(0.22, 0.18, 0.13))
	_box(n, Vector3(0.10, 1.80, 0.10), Vector3(0.55, 0.90, 0.0), Color(0.22, 0.18, 0.13))
	_box(n, Vector3(1.30, 0.09, 0.09), Vector3(0.0, 1.76, 0.0), Color(0.22, 0.18, 0.13))
	_box(n, Vector3(0.30, 0.55, 0.26), Vector3(0.10, 1.42, 0.0), Color(0.36, 0.16, 0.14))


func _build_stakes(root: Node3D, h: int) -> void:
	for i in range(4):
		var a := float(i) * 1.4 + _unit(h, 7 + i) * 0.7
		var s := _box(root, Vector3(0.09, 1.25, 0.09),
				Vector3(cos(a) * 3.4, 0.60, sin(a) * 3.4), Color(0.21, 0.17, 0.12))
		s.rotation.z = 0.12 + _unit(h, 11 + i) * 0.18


func _mow_camp(at: Vector3) -> void:
	## A fire ring, four stakes and two lean-tos are all below waist height,
	## and `a23a20e` found a whole MOOSE invisible at four metres in midsummer
	## grass. `GrassSystem.cut_at` fells the tall tufts and records the cut in
	## `_cut_cells`, which the grass already saves and re-reads when a chunk
	## streams back, so a clearing mown once stays mown across a reload without
	## this file storing anything. Once per camp per session, duck-typed, and a
	## silent no-op with no grass bound at all -- the headless case.
	var key := "%d_%d" % [int(round(at.x)), int(round(at.z))]
	if _mown.has(key):
		return
	_mown[key] = true
	if not is_inside_tree():
		return
	var g := get_tree().get_first_node_in_group("grass_system")
	if g == null or not is_instance_valid(g) or not g.has_method("cut_at"):
		return
	g.call("cut_at", at, CAMP_MOW_M)


# ================================ reading it ===============================


func report() -> Dictionary:
	var held := 0
	var out_now := 0
	var barred := 0
	var strength := 0
	var road_now := 0
	var rows: Array = []
	var sky := sky_at(days)
	var hr := hour_now()
	for c in camps:
		var cd := c as Dictionary
		var id := String(cd["id"])
		var st := _ensure_state(id)
		if float(st["cleared_until"]) > days:
			barred += 1
		if not occupied(id):
			continue
		held += 1
		strength += int(st["strength"])
		var se := season_here(days, cd)
		var r := routine_at(cd, hr, sky, se)
		if String(r["station"]) == "prowl":
			out_now += 1
			if String(r["reason"]) == "road":
				road_now += 1
		rows.append("%s|%s|%s|%s|%d|%.0f" % [id, String(cd["name"]), String(r["station"]),
				String(r["reason"]), int(st["strength"]), float(cd["road_d"])])
	rows.sort()
	return {
		"sites": camps.size(),
		"held": held,
		"out": out_now,
		"on_road": road_now,
		"barred": barred,
		"goblins_modelled": strength,
		"goblins_live": live_goblins(),
		"day": days,
		"hour": hr,
		"sky": sky,
		"season": season_at(days),
		"staged": _staged.size(),
		"raised": raised_total,
		"abandoned": abandoned_total,
		"cleared": cleared_total,
		"killed": killed_total,
		"steps": _ran,
		"build_ms": _build_ms,
		"rows": rows,
	}


func region_table() -> Array:
	## What the frontier is buying, region by region. Used by the probe and by
	## the suite's own independent rebuild.
	var out: Array = []
	for rn in _regions:
		var region := String(rn)
		var rows: Array = _sites_in.get(region, [])
		var share := share_of(region)
		out.append({
			"region": region,
			"sites": rows.size(),
			"km2": float(_areas.get(region, 0.0)),
			"share": share,
			"quota": quota(share, float(_areas.get(region, 0.0)), rows.size()),
		})
	return out


# =============================== save / load ===============================


func to_dict() -> Dictionary:
	## Only what cannot be rebuilt. The sites, their names, their bearings and
	## their road points are a pure function of the net and the seed, both of
	## which a save restores, so storing them would be a second copy that can
	## go stale.
	var st: Dictionary = {}
	for id in state.keys():
		var row: Dictionary = state[id]
		if not bool(row.get("held", false)) and float(row.get("cleared_until", -1.0)) <= days:
			continue
		st[id] = {
			"held": bool(row.get("held", false)),
			"strength": int(row.get("strength", 0)),
			"raised": float(row.get("raised", -1.0)),
			"cleared_until": float(row.get("cleared_until", -1.0)),
		}
	return {
		"seed": world_seed,
		"hours": _hours,
		"steps": _steps,
		"print": _net_print,
		"raised": raised_total,
		"cleared": cleared_total,
		"killed": killed_total,
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
	raised_total = int(d.get("raised", raised_total))
	cleared_total = int(d.get("cleared", cleared_total))
	killed_total = int(d.get("killed", killed_total))
	## The sites are marched off the net, so they must be marched again before
	## any saved state can be matched to one.
	boot(true)
	var st: Variant = d.get("state", {})
	if st is Dictionary:
		for id in (st as Dictionary).keys():
			## A camp the restored net has never heard of is dropped rather
			## than resurrected -- the Wayfarers' rule, and the reason a net
			## fingerprint is worth saving at all.
			if not _by_id.has(String(id)):
				continue
			var row: Dictionary = (st as Dictionary)[id]
			state[String(id)] = {
				"held": bool(row.get("held", false)),
				"strength": clampi(int(row.get("strength", 0)), 0, SIZE_MAX),
				"raised": float(row.get("raised", -1.0)),
				"cleared_until": float(row.get("cleared_until", -1.0)),
				"seen": false,
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
