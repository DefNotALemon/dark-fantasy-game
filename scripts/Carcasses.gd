class_name Carcasses
extends Node

## ===========================================================================
## THE CARCASS ECONOMY — a kill is a deposit, and the woods come to collect.
##
## Myrkfell had a death animation and nothing downstream of it. A moose you
## dropped fell over, lay there for twenty-two seconds while `CreatureSkin`
## ran its ragdoll clock, dithered out, and the world was exactly as it had
## been. Two hundred and forty kilograms of meat in a county full of hungry
## things, and not one of them noticed.
##
## This is what notices. A carcass is a LEDGER ENTRY with a number of
## kilograms on it, and five claimants bill against that number over the next
## several days: the crows, the foxes, a coyote pack, a bear, and the ground
## itself. The order they arrive in is not a script — it is what the sky, the
## season, the hour and the size of the animal make of them.
##
## FIVE RULES this file will not break:
##
##   1. **The record is the carcass; the body is a picture of it.** Nothing
##      here is a scene node until you are within `STAGE_RADIUS`. Walk two
##      valleys away for a day and come back and the crows have been and gone
##      and the ribs are showing, because the ledger kept billing while the
##      chunk was unloaded. That is the whole reason this is a bus and not a
##      prop with a timer on it.
##   2. **Two accumulators are state; everything else is derived.** `left`
##      (kilograms remaining) and `prog` (how far each guild has got toward
##      FINDING it) are the only things that change, plus the day each guild
##      arrived. Stage, presence, legibility and the rumour text are all pure
##      functions of those. A derived state is not a second thing that can go
##      stale — but see rule 3, which is the other half of that coin.
##   3. **ARRIVAL IS A STATE, NOT A QUERY**, and this is the non-obvious half.
##      `Crofts` learned it on its washing line: derive the thing that
##      HAPPENS and you make it unreachable. If "the crows are on it" were a
##      query on the current sky, a gale would un-find a carcass the crows had
##      already found, the eviction below could never fire, and every
##      assertion aimed at either would pass for the wrong reason. So `seen`
##      is written down.
##   4. **Deterministic, and it counts the CLAIM, not the critter.** No
##      random-number generator anywhere: every jitter is a hash of
##      (`world_seed`, record id, salt). `WildlifeDirector.spawn_one` is free
##      to refuse, and `_cull` frees animals on its own budget, so the number
##      of crows actually standing there is NOT in `report()` — the
##      Incident Director leaked exactly that into its digest and had to take
##      it back out.
##   5. **The sky is the one the CHRONICLE believes in.** Never the live
##      `_rng`-driven `Weather`, for the Wayfarers' reason: a consumer that
##      reached for it would put a number in the save's future that the save
##      cannot reproduce.
##
## THE ECONOMY IS THE POINT, AND IT HAS TEETH. Every guild has a `MIN_LEFT`:
## a share of the original mass below which it will not trouble to come at
## all. A coyote pack wants 18 % of a carcass still on it. So the loop the
## player is actually in is this: **butcher it, or fund the predators.** Take
## the deer down past a fifth and the pack that would have come to your camp
## at midnight never comes. Leave it where it fell and you have baited forty
## kilos of the dark to a spot fifty metres from where you sleep.
##
## And the season is the other dial. Rot is nearly four times as quick in a
## Maine August as it is in spring, and in February it all but stops — so the
## same kill is bones on the third day in summer and still a carcass a
## fortnight later in winter. Scent carries the same way, which is why the
## woods find a summer kill fast and a winter kill slowly. Nothing else in
## the project makes a season mean that yet.
##
## Wired up by World.gd (tools/patch_carcasses.py), AFTER the Chronicle and
## the WildlifeDirector, because `bind_world` reaches for both:
##     _carcasses = Carcasses.new(); add_child(_carcasses)
##     _carcasses.bind_world(self)
## Read it with:  World.carcasses().near(player.global_position, 400.0)
## ===========================================================================

signal carcass_found(rec: Dictionary, guild: String)
signal carcass_stripped(rec: Dictionary)


# ============================== the clock =================================

const STEP_HOURS := 0.5
const CATCHUP_STEPS := 480
const DAYS_PER_SEASON := 24.0

const SKY_CLEAR := 0
const SKY_OVERCAST := 1
const SKY_DRIZZLE := 2
const SKY_RAIN := 3
const SKY_STORM := 4

const SPRING := 0
const SUMMER := 1
const AUTUMN := 2
const WINTER := 3


# ============================== the deposit ===============================

## Usable flesh in kilograms, from the dex's body length. Mass goes as the
## cube of length for anything built roughly the same way, and the constant
## is set so a whitetail (1.70 m) is a realistic 49 kg of workable animal.
## Cross-checked against the dex's own `harv.meat` ordinals: moose 6,
## whitetail 3, coyote 1, hare 1 — same order, so the two agree.
const MASS_K := 10.0
const MIN_MASS := 0.6           ## below this there is no record at all: a hare
                                ## (0.74 kg) leaves one, a red squirrel (0.18)
                                ## does not, and a ledger with every dragonfly
                                ## in it is a ledger nobody reads.
const DRAW_MASS := 49.0         ## one deer — the unit the search rate is in


# ============================= the claimants ==============================
#
# Five rows and one table. Everything a guild IS lives here; nothing about a
# guild is written anywhere else in the file.
#
#   find   hours of ITS OWN WORKING TIME to find one deer in clear spring air
#   rate   kilograms an hour it takes off once it is there
#   stay   days it works a carcass before it has had enough and moves on
#   floor  share of the ORIGINAL mass below which it will not come at all
#   from   hour it starts (inclusive), to   hour it stops; -1 means "daylight"
#   cap    highest sky level it will work in (STORM = 4 means never grounded)
#   n      how many bodies to ask the WildlifeDirector for
#   kinds  the dex species that play this part — all real, all already in it

const GUILDS: Array = [
	{
		"id": "corvid", "nm": "crows",
		"find": 1.2, "rate": 0.30, "stay": 1.6, "floor": 0.02,
		"from": -1.0, "to": -1.0, "cap": SKY_RAIN, "n": 4,
		"kinds": ["crow", "raven", "vulture"], "threat": 0,
	},
	{
		"id": "fox", "nm": "a fox",
		"find": 4.5, "rate": 0.35, "stay": 1.1, "floor": 0.06,
		"from": 17.0, "to": 7.0, "cap": SKY_STORM, "n": 1,
		"kinds": ["red_fox", "gray_fox", "fisher", "marten"], "threat": 1,
	},
	{
		"id": "pack", "nm": "coyotes",
		"find": 9.0, "rate": 3.5, "stay": 0.8, "floor": 0.18,
		"from": 20.0, "to": 5.0, "cap": SKY_STORM, "n": 3,
		"kinds": ["coyote"], "threat": 3,
	},
	{
		"id": "bear", "nm": "a bear",
		"find": 34.0, "rate": 9.5, "stay": 0.55, "floor": 0.30,
		"from": 6.0, "to": 21.0, "cap": SKY_RAIN, "n": 1,
		"kinds": ["black_bear"], "threat": 4,
	},
]

const G_CORVID := 0
const G_FOX := 1
const G_PACK := 2
const G_BEAR := 3

## Black bears den from about the first hard frost to the thaw. A bear is the
## one claimant a winter carcass never has to worry about, which is part of
## why a winter carcass lasts.
const BEAR_DENNED: Array = [false, false, false, true]

## The bear does not queue. It arrives and everything else leaves, and they
## do not come back — this is the one interaction between two guilds and it
## is the reason `seen` has to be written down rather than asked for.
const BEAR_EVICTS := true


# ================================ the ground ==============================

## Share of the ORIGINAL mass the ground takes per day, before the season.
const ROT_PER_DAY := 0.115
## Spring · Summer · Autumn · Winter. August is nearly four times February.
const SEASON_ROT: Array = [1.00, 1.85, 0.80, 0.22]
## How far the smell gets. Warm air carries it; frozen meat barely smells;
## rain beats it into the ground. Both tables multiply the search rate.
const SEASON_SCENT: Array = [1.00, 1.25, 1.00, 0.55]
const SKY_SCENT: Array = [1.00, 0.94, 0.80, 0.62, 0.44]


# ================================= stages =================================

const STAGE_WHOLE := 0
const STAGE_OPENED := 1
const STAGE_PICKED := 2
const STAGE_BONES := 3
const STAGE_GONE := 4

const OPENED_AT := 0.86         ## share of mass left at each boundary
const PICKED_AT := 0.55
const BONES_AT := 0.22
const GONE_AT := 0.02

## Bones linger from the day the MEAT ran out, never from the day of the
## kill. Measured from the kill, a carcass the pack stripped in six hours and
## one the winter kept for a fortnight would both vanish on the same
## afternoon, and nobody would ever walk up to the second one's ribs.
const BONE_DAYS := 5.0
const FORGET_HARD := 40.0       ## and nothing is immortal, whatever the sky


# ================================ the world ===============================

const MAX_RECORDS := 64         ## oldest bones are forgotten first
const TELL_M := 900.0           ## tell a place about a kill this close to it
const TELL_MIN_MASS := 12.0     ## and only about something worth the telling --
                                ## a dead hare is not news at the tavern
const NOTICE_M := 120.0         ## and tell the PLAYER when he is this close
const RING_M := 70.0            ## how far the arrival is heard on the alarm bus
const KILL_NEAR_M := 60.0       ## a kill this close to the player is "his"

const STAGE_RADIUS := 260.0
const STRIKE_RADIUS := 380.0
const MAX_STAGED := 5
const SCAN_SECONDS := 0.9
const HARVEST_SECONDS := 0.45   ## how often we look for something newly dead
## A body mats the grass it is lying in, and the radius is the ANIMAL'S, not
## a constant. The first live look at this feature had a whole moose standing
## four metres away in a hayfield and INVISIBLE: at a flat 2.6 m the mown
## circle was smaller than the two-and-a-half-metre body inside it, so the
## tufts in front of it hid it completely at eye height. The croft yard
## learned the same lesson at 196/0 green and answered it with seventeen
## metres. A carcass wants about two lengths of clearance.
const MOW_PER_M := 2.4
const MOW_MIN := 1.6            ## a hare flattens a patch, not a clearing
const MOW_MAX := 7.0            ## and nothing flattens more than a moose does
const GROUND_SCALE := 1.15      ## the stained patch, in body lengths

const SALT_JIT := 0x9E3779B1
const SALT_KIND := 0x85EBCA6B
const SALT_BODY := 0xC2B2AE35


# ================================== state =================================

var enabled := true
var days := 0.0
var world_seed := 0

var records: Array = []
var player: Node3D = null
var clock: Node = null
var chron: Object = null
var feed: Object = null
var wild: Object = null
var _ground: Object = null

var _by_id: Dictionary = {}
var _known: Dictionary = {}      ## instance_id of a dying body -> record id
var _staged: Dictionary = {}
var _mown: Dictionary = {}
var _told_player: Dictionary = {}
var _asked: Dictionary = {}      ## "recid|guild" -> true, bodies already asked for
var _next_id := 1

var _hours := 0.0
var _steps := 0
var _last_clock := -1.0
var _scan_t := 0.0
var _harvest_t := 0.0
var _booted := false
var _ran := 0


# ============================== the plumbing ==============================

static func get_bus(from: Node) -> Carcasses:
	if from == null or not from.is_inside_tree():
		return null
	var n := from.get_tree().get_first_node_in_group("carcasses")
	return n as Carcasses


func _ready() -> void:
	add_to_group("carcasses")
	boot()


func _exit_tree() -> void:
	remove_from_group("carcasses")


func boot(force := false) -> void:
	## A node added to `root` from `SceneTree._init()` never gets `_ready()`,
	## so every bus in this project boots idempotently and by hand.
	if _booted and not force:
		return
	_booted = true
	if not is_in_group("carcasses"):
		add_to_group("carcasses")


func bind_world(w: Node) -> void:
	## Duck-typed on every hook, like the Road Net, the Wayfarers and the
	## Crofts: this class must come up inside the full game AND inside a
	## stripped test project with three scripts in it.
	if w == null or not is_instance_valid(w):
		return
	if w.has_method("chronicle"):
		var c: Variant = w.call("chronicle")
		if c is Object and is_instance_valid(c as Object):
			chron = c as Object
	if chron == null and is_inside_tree():
		var cg := get_tree().get_first_node_in_group("chronicle")
		if cg != null and is_instance_valid(cg):
			chron = cg
	## A collaborator that is the wrong kind of object is worse than none.
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

	var wd: Variant = w.get("_wildlife")
	if wd is Object and is_instance_valid(wd as Object):
		wild = wd as Object
	if wild != null and not wild.has_method("spawn_one"):
		wild = null

	var p: Variant = w.get("_player")
	if p is Node3D:
		player = p as Node3D
	var dn: Variant = w.get("_daynight")
	if dn is Node:
		clock = dn as Node
	var ws: Variant = w.get("world_seed")
	if ws != null and typeof(ws) == TYPE_INT:
		world_seed = int(ws)
	if w.has_method("_surface_y") or w.has_method("surface_y"):
		_ground = w
	boot()


func ready() -> bool:
	return _booted


# =========================== THE PURE MODEL ===============================
#
# Everything below this line and above "the simulation" reads nothing but its
# arguments. No node, no clock, no RNG, no `self`. That is what makes "a gale
# at four in the morning in February" a call with four arguments rather than
# something you stand in a field and wait for.

static func mass_of(species: String, length_m: float) -> float:
	## The dex's `len` is the only size number every one of the sixty-five
	## animals actually has, so it is the one this is built on. `species` is
	## carried for the two hand-set exceptions below and for legibility.
	if species == "":
		return 0.0
	return MASS_K * length_m * length_m * length_m


static func stage_of(rec: Dictionary) -> int:
	var mass := float(rec.get("mass", 0.0))
	if mass <= 0.0:
		return STAGE_GONE
	var f := float(rec.get("left", 0.0)) / mass
	if f > OPENED_AT:
		return STAGE_WHOLE
	if f > PICKED_AT:
		return STAGE_OPENED
	if f > BONES_AT:
		return STAGE_PICKED
	if f > GONE_AT:
		return STAGE_BONES
	return STAGE_GONE


static func stage_name(s: int) -> String:
	match s:
		STAGE_WHOLE: return "whole"
		STAGE_OPENED: return "opened"
		STAGE_PICKED: return "picked"
		STAGE_BONES: return "bones"
	return "gone"


static func daylight(season: int) -> Vector2:
	## One definition of dawn in the project. `Crofts.daylight` owns it and
	## has a suite holding it; a second copy here would be a second thing to
	## keep in step, and the hour a crow starts work is the same hour a
	## crofter does.
	return Crofts.daylight(clampi(season, 0, 3))


static func works_now(g: int, hour: float, sky: int, season: int) -> bool:
	## Is this guild working at all, this hour, under this sky?
	if g < 0 or g >= GUILDS.size():
		return false
	var row: Dictionary = GUILDS[g]
	if g == G_BEAR and bool(BEAR_DENNED[clampi(season, 0, 3)]):
		return false
	if sky > int(row["cap"]):
		return false          ## a gale grounds the crows outright
	var a := float(row["from"])
	var b := float(row["to"])
	if a < 0.0:
		var dl := daylight(season)
		a = dl.x
		b = dl.y
	var h := fposmod(hour, 24.0)
	if a <= b:
		return h >= a and h < b
	return h >= a or h < b     ## a window that crosses midnight


static func scent(sky: int, season: int) -> float:
	## Warm air carries it, rain beats it down, and a frozen carcass barely
	## smells at all. This multiplies the SEARCH, never the eating: a fox
	## that has already found the thing does not lose it in the rain.
	return float(SEASON_SCENT[clampi(season, 0, 3)]) * float(SKY_SCENT[clampi(sky, 0, 4)])


static func draw_of(mass: float) -> float:
	## A moose is found sooner than a hare, and not by a little. Bounded at
	## both ends so a whale does not summon every crow in the county on the
	## first half hour and a squirrel is still findable.
	return clampf(mass / DRAW_MASS, 0.35, 2.1)


static func find_gain(g: int, mass: float, hour: float, sky: int, season: int) -> float:
	## How much closer this guild gets to finding the carcass, over one
	## STEP_HOURS. Zero when it is not working. 1.0 total means found.
	if not works_now(g, hour, sky, season):
		return 0.0
	var row: Dictionary = GUILDS[g]
	var base := float(row["find"])
	if base <= 0.0:
		return 1.0
	return (STEP_HOURS / base) * scent(sky, season) * draw_of(mass)


static func rot_per_step(mass: float, season: int) -> float:
	## Kilograms the ground takes in one step, and the single biggest reason
	## a season means something here.
	return mass * ROT_PER_DAY * float(SEASON_ROT[clampi(season, 0, 3)]) * (STEP_HOURS / 24.0)


static func wants_it(g: int, rec: Dictionary) -> bool:
	## THE TEETH OF THE ECONOMY. Every guild has a share of the original mass
	## below which it will not come, and will not stay. Strip a deer past a
	## fifth and the pack that would have walked into your camp at midnight
	## never walks into your camp.
	if g < 0 or g >= GUILDS.size():
		return false
	var mass := float(rec.get("mass", 0.0))
	if mass <= 0.0:
		return false
	return float(rec.get("left", 0.0)) / mass > float((GUILDS[g] as Dictionary)["floor"])


static func present(rec: Dictionary, g: int, t: float) -> bool:
	## Is this guild ON it right now? Derived — but derived from `seen`,
	## which is written down, which is the whole of rule 3. A guild is on it
	## from the day it arrived until its stay runs out, unless a bear turned
	## up, or unless there is no longer enough on the bones to hold it.
	var seen: Dictionary = rec.get("seen", {})
	var key := String((GUILDS[g] as Dictionary)["id"])
	if not seen.has(key):
		return false
	var came := float(seen[key])
	if t < came:
		return false
	if t > came + float((GUILDS[g] as Dictionary)["stay"]):
		return false
	if BEAR_EVICTS and g != G_BEAR:
		var bkey := String((GUILDS[G_BEAR] as Dictionary)["id"])
		if seen.has(bkey) and float(seen[bkey]) <= t:
			return false
	return wants_it(g, rec)


static func attendance(rec: Dictionary, t: float) -> Array:
	var out: Array = []
	for g in GUILDS.size():
		if present(rec, g, t):
			out.append(String((GUILDS[g] as Dictionary)["id"]))
	return out


static func legible(rec: Dictionary, t: float) -> String:
	## What a sentence about this carcass reads like from ten metres away.
	var nm := String(rec.get("nm", "something"))
	var here := attendance(rec, t)
	var st := stage_of(rec)
	if st == STAGE_GONE:
		return "Bones, and the grass already coming back through them."
	if not here.is_empty():
		var gi := _guild_index(String(here[0]))
		var who := "something" if gi < 0 else String((GUILDS[gi] as Dictionary)["nm"])
		if st <= STAGE_OPENED:
			return "A dead %s, and %s at it." % [nm, who]
		return "What is left of a %s, and %s still at it." % [nm, who]
	match st:
		STAGE_WHOLE:
			return "A dead %s, not long down and not yet found." % nm
		STAGE_OPENED:
			return "A dead %s, opened up. Something has been here." % nm
		STAGE_PICKED:
			return "A %s picked most of the way down. Tracks all round it." % nm
	return "The ribs of a %s, and not much else." % nm


static func rumour_for(rec: Dictionary, guild_id: String) -> String:
	## News dated to the DAY OF THE KILL, never the day of the telling — the
	## Wayfarers' rule for anything carried. A story three days old has to
	## read as three days old whoever is passing it on.
	var nm := String(rec.get("nm", "something"))
	match guild_id:
		"pack":
			return "Coyotes were singing over a dead %s out that way." % nm
		"bear":
			return "A bear has a dead %s out that way. Give that ground a wide berth." % nm
		"corvid":
			return "Crows are down on something dead out that way — a %s, by the size of it." % nm
	return "There is a dead %s lying out that way." % nm


static func _guild_index(id: String) -> int:
	for g in GUILDS.size():
		if String((GUILDS[g] as Dictionary)["id"]) == id:
			return g
	return -1


static func guild_index(id: String) -> int:
	return _guild_index(id)


# ============================= the simulation =============================

func _process(delta: float) -> void:
	if not enabled:
		return
	_tick_clock()
	_harvest_t -= delta
	if _harvest_t <= 0.0:
		_harvest_t = HARVEST_SECONDS
		harvest()
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = SCAN_SECONDS
		sense()
		_restage()
	_drive_bodies()


func _tick_clock() -> void:
	## The game's clock, never the frame delta — a sleep must walk the week
	## that passed, not the two real seconds it took. The same shape as
	## `Chronicle._process`, `Wayfarers._tick_clock` and `Crofts._tick_clock`,
	## deliberately: four sims reading the same sky must reach the same day.
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
	## DayNight boots at day 30, hour 19.7 while a fresh bus sits at zero.
	## Left alone, every dawn gate would be judged against a clock the sky
	## has never heard of and the crows would clock on at midnight.
	_hours = now * 24.0
	days = _hours / 24.0
	_steps = int(floorf(_hours / STEP_HOURS + 1e-9))


func advance(hours: float, budget := 20000) -> void:
	## The only way time passes in here. GAME HOURS, not days — the
	## Chronicle's own trap, and the same signature for the same reason.
	if hours <= 0.0:
		return
	_hours += hours
	days = _hours / 24.0
	_run_steps(budget)


func _run_steps(budget: int) -> void:
	var want := int(floorf(_hours / STEP_HOURS + 1e-9))
	var left := budget
	while _steps < want and left > 0:
		_step(_steps)
		_steps += 1
		_ran += 1
		left -= 1


func _step(n: int) -> void:
	var t := float(n) * STEP_HOURS / 24.0
	var hour := fposmod(float(n) * STEP_HOURS, 24.0)
	var season := season_at(t)
	var sky := sky_at(t)
	var dead: Array = []
	for r in records:
		var rec := r as Dictionary
		if rec.is_empty():
			continue
		if _step_rec(rec, t, hour, sky, season_here(t, rec)):
			dead.append(rec)
	for r2 in dead:
		_forget(r2 as Dictionary)


func sky_at(t: float) -> int:
	## The sky the CHRONICLE believes in, never the live `Weather` — rule 5.
	if chron != null and is_instance_valid(chron) and chron.has_method("sky_at"):
		return clampi(int(chron.call("sky_at", t)), 0, 4)
	return SKY_CLEAR


func season_at(t: float) -> int:
	if chron != null and is_instance_valid(chron) and chron.has_method("season_at"):
		return clampi(int(chron.call("season_at", t)), 0, 3)
	return int(fposmod(t, DAYS_PER_SEASON * 4.0) / DAYS_PER_SEASON) % 4


func season_here(t: float, rec: Dictionary) -> int:
	## [seasons] The season WHERE THE BODY LIES. `season_at` is still the
	## calendar and still what the Chronicle runs on; rot and scent are local.
	##
	## This is the difference between a larder and a loss. `SEASON_ROT` says
	## August takes meat eight times faster than February, and until now the
	## whole map shared one August — so a kill in the far north spoiled at the
	## same rate as one on the warm south coast. It does not any more: on 30
	## of the year's 96 days two carcasses on this map are rotting in
	## different seasons, and in the shoulder weeks a body up on Katahdin is
	## already keeping while the same animal Down East is still going off.
	##
	## Unlike a croft, a carcass knows its own height — `rec["at"]` is a
	## Vector3 — so altitude counts here, and the mountain gets its full share
	## of the warp. See scripts/Seasons.gd.
	## ⚠ Through `season_at`, NEVER through `Seasons.local_index` directly —
	## see the same note in `Crofts.season_here`. The Chronicle owns the
	## calendar; geography only moves which day this body is lying in.
	var at: Vector3 = rec.get("at", Vector3.ZERO)
	return season_at(t + Seasons.warp_days(t, at))


func _step_rec(rec: Dictionary, t: float, hour: float, sky: int, season: int) -> bool:
	## One half hour in the life of one carcass. Returns true when the record
	## should be forgotten. This is the only function that mutates a record.
	if t < float(rec.get("born", 0.0)):
		return false
	var mass := float(rec.get("mass", 0.0))
	var before := float(rec.get("left", 0.0))
	var seen: Dictionary = rec.get("seen", {})
	var prog: Dictionary = rec.get("prog", {})
	var took: Dictionary = rec.get("took", {})

	## 1 · SEARCH. Anyone who has not found it yet, and still wants it, gets
	## closer to finding it — but only during their own working hours, and
	## only as fast as the air will carry the smell.
	for g in GUILDS.size():
		var key := String((GUILDS[g] as Dictionary)["id"])
		if seen.has(key):
			continue
		if not wants_it(g, rec):
			continue
		if BEAR_EVICTS and g != G_BEAR and seen.has(String((GUILDS[G_BEAR] as Dictionary)["id"])):
			continue
		var p := float(prog.get(key, 0.0)) + find_gain(g, mass, hour, sky, season)
		prog[key] = p
		if p >= 1.0:
			seen[key] = t
			carcass_found.emit(rec, key)

	## 2 · THE TABLE. Everyone present bills against what is left.
	for g2 in GUILDS.size():
		if not present(rec, g2, t):
			continue
		if not works_now(g2, hour, sky, season):
			continue
		var key2 := String((GUILDS[g2] as Dictionary)["id"])
		var want := float((GUILDS[g2] as Dictionary)["rate"]) * STEP_HOURS
		var got := minf(want, maxf(float(rec["left"]), 0.0))
		rec["left"] = float(rec["left"]) - got
		took[key2] = float(took.get(key2, 0.0)) + got

	## 3 · THE GROUND. It never stops and it never has to find anything.
	rec["left"] = maxf(float(rec["left"]) - rot_per_step(mass, season), 0.0)

	rec["seen"] = seen
	rec["prog"] = prog
	rec["took"] = took

	## 4 · THE ENDING, and it is dated from when the MEAT ran out.
	if mass > 0.0:
		var was_meat := before / mass > BONES_AT
		var now_bone := float(rec["left"]) / mass <= BONES_AT
		if was_meat and now_bone:
			rec["stripped"] = t
			carcass_stripped.emit(rec)
	var stripped := float(rec.get("stripped", -1.0))
	if stripped >= 0.0 and t > stripped + BONE_DAYS:
		return true
	return t > float(rec.get("born", 0.0)) + FORGET_HARD


func _forget(rec: Dictionary) -> void:
	var id := int(rec.get("id", 0))
	_by_id.erase(id)
	records.erase(rec)
	_strike(id)
	for k in _known.keys():
		if int(_known[k]) == id:
			_known.erase(k)


# =============================== the ingest ===============================

func harvest() -> int:
	## THE ONLY WAY A CARCASS IS EVER CREATED IN THE GAME, and it deliberately
	## patches nobody's file to do it. `Enemy._die()` sets `dying` and every
	## death in the project — sword, arrow, pickaxe, a fall, another animal —
	## goes through it, so a sweep of the group catches all of them and
	## catches them within half a second of the blow. `Enemy.gd` is 58 KB of
	## somebody else's uncommitted work; a hook in it would be a hunk that
	## could never land under a real diff.
	if not is_inside_tree():
		return 0
	_prune_known()
	var made := 0
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Node3D
		if e == null or not is_instance_valid(e):
			continue
		if not ("dying" in e) or not bool(e.get("dying")):
			continue
		var iid := e.get_instance_id()
		if _known.has(iid):
			continue
		var rec := _make_from(e)
		_known[iid] = int(rec.get("id", 0)) if not rec.is_empty() else 0
		if not rec.is_empty():
			made += 1
	return made


func _prune_known() -> void:
	## A body frees itself twenty-two seconds after it falls (CreatureSkin
	## owns that clock), so the instance ids we have already seen go stale
	## fast. Left alone this dictionary is the one thing in here that grows
	## without bound over a long session.
	for k in _known.keys():
		var o := instance_from_id(int(k))
		if o == null or not is_instance_valid(o):
			_known.erase(k)


func _make_from(e: Node3D) -> Dictionary:
	## `species` is a Critter field. A dead goblin is an Enemy with no
	## species and gets no record, deliberately: this is the WILDLIFE
	## economy, and what happens to a goblin's body is `Enemy._spawn_pickups`
	## and a different argument.
	var species := ""
	if "species" in e:
		species = String(e.get("species"))
	if species == "":
		return {}
	var length := 1.0
	var nm := species
	var prof: Dictionary = CritterDex.get_profile(species)
	if not prof.is_empty():
		length = float(prof.get("len", 1.0))
		nm = String(prof.get("nm", species)).to_lower()
	var mass := mass_of(species, length)
	if mass < MIN_MASS:
		return {}
	return add(species, nm, e.global_position, mass)


func add(species: String, nm: String, at: Vector3, mass: float) -> Dictionary:
	## Public so the tests, the debug console and a future butcher's block can
	## put one on the ledger without killing anything.
	if mass < MIN_MASS:
		return {}
	var id := _next_id
	_next_id += 1
	var near_player := false
	if player != null and is_instance_valid(player):
		near_player = player.global_position.distance_to(at) <= KILL_NEAR_M
	var rec := {
		"id": id,
		"species": species,
		"nm": nm,
		"at": at,
		"born": days,
		"mass": mass,
		"left": mass,
		"seen": {},
		"prog": {},
		"took": {},
		"stripped": -1.0,
		"near_player": near_player,
		"place": _place_name(at),
		"told": {},
	}
	records.append(rec)
	_by_id[id] = rec
	while records.size() > MAX_RECORDS:
		_forget(records[0] as Dictionary)
	return rec


func _place_name(at: Vector3) -> String:
	if chron == null or not is_instance_valid(chron) or not chron.has_method("nearest_place"):
		return ""
	var p: Dictionary = chron.call("nearest_place", at, TELL_M)
	if p.is_empty():
		return ""
	return String(p.get("name", ""))


# =============================== the player ===============================

func harvest_at(pos: Vector3, radius: float, kg: float) -> float:
	## Butchery. Takes up to `kg` off the nearest carcass inside `radius` and
	## returns what it actually got. THIS is the loop: what you take is what
	## the woods do not get, and a carcass stripped past a guild's floor is
	## one that guild will never walk to.
	var best: Dictionary = {}
	var bd := radius
	for r in records:
		var rec := r as Dictionary
		var d := (rec["at"] as Vector3).distance_to(pos)
		if d <= bd:
			bd = d
			best = rec
	if best.is_empty():
		return 0.0
	var got := minf(maxf(kg, 0.0), float(best.get("left", 0.0)))
	best["left"] = float(best["left"]) - got
	best["took"] = best.get("took", {})
	(best["took"] as Dictionary)["player"] = float((best["took"] as Dictionary).get("player", 0.0)) + got
	return got


# =============================== the queries ==============================

func near(pos: Vector3, radius: float) -> Array:
	var out: Array = []
	for r in records:
		var rec := r as Dictionary
		var d := (rec["at"] as Vector3).distance_to(pos)
		if d <= radius:
			out.append({"rec": rec, "d": d})
	out.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]))
	return out


func record_by_id(id: int) -> Dictionary:
	return _by_id.get(id, {})


func report() -> Dictionary:
	## A stable digest. Counts the CLAIM, never the critter: what the
	## WildlifeDirector did or did not manage to spawn is its business and
	## its budget, and putting it in here is how the Incident Director leaked
	## non-determinism into a number two Directors had to agree on.
	var by_stage := [0, 0, 0, 0, 0]
	var claims := {}
	var kg_left := 0.0
	var kg_taken := 0.0
	for g in GUILDS.size():
		claims[String((GUILDS[g] as Dictionary)["id"])] = 0
	for r in records:
		var rec := r as Dictionary
		by_stage[stage_of(rec)] += 1
		kg_left += float(rec.get("left", 0.0))
		var took: Dictionary = rec.get("took", {})
		for k in took:
			kg_taken += float(took[k])
		var seen: Dictionary = rec.get("seen", {})
		for k2 in seen:
			if claims.has(k2):
				claims[k2] = int(claims[k2]) + 1
	return {
		"records": records.size(),
		"days": days,
		"steps": _steps,
		"by_stage": by_stage,
		"claims": claims,
		"kg_left": kg_left,
		"kg_taken": kg_taken,
		"staged": _staged.size(),
	}


# ============================== the telling ===============================

func sense() -> void:
	## Two mouths, and they say different things. The RUMOUR goes to the
	## nearest place's board and keeps the date of the KILL, so a story that
	## reaches a village three days later reads as three days old. The FEED
	## line is what you hear yourself when you walk up to one.
	for r in records:
		var rec := r as Dictionary
		_maybe_tell_place(rec)
	for k in _staged.keys():
		var sr: Dictionary = _by_id.get(int(k), {})
		if not sr.is_empty():
			_ask_for_bodies(sr)
	if player == null or not is_instance_valid(player):
		return
	if feed == null or not is_instance_valid(feed) or not feed.has_method("offer"):
		return
	var rows := near(player.global_position, NOTICE_M)
	if rows.is_empty():
		return
	var rec2: Dictionary = (rows[0] as Dictionary)["rec"]
	var key := "%d|%s|%s" % [int(rec2["id"]), stage_name(stage_of(rec2)), ",".join(attendance(rec2, days))]
	if _told_player.has(key):
		return
	if bool(feed.call("offer", legible(rec2, days), String(rec2.get("nm", "")), "carcass", days)):
		_told_player[key] = true


func _maybe_tell_place(rec: Dictionary) -> void:
	if chron == null or not is_instance_valid(chron) or not chron.has_method("deposit_rumour"):
		return
	var place := String(rec.get("place", ""))
	if place == "":
		return
	if float(rec.get("mass", 0.0)) < TELL_MIN_MASS:
		return
	var told: Dictionary = rec.get("told", {})
	for g in [G_PACK, G_BEAR, G_CORVID]:
		var key := String((GUILDS[g] as Dictionary)["id"])
		if told.has(key):
			continue
		if not (rec.get("seen", {}) as Dictionary).has(key):
			continue
		told[key] = true
		rec["told"] = told
		chron.call("deposit_rumour", place, {
			"text": rumour_for(rec, key),
			"day": float(rec.get("born", days)),
			"from": "",
			"kind": "carcass",
		})
		return


# =============================== the bodies ===============================

func _restage() -> void:
	if not is_inside_tree() or player == null or not is_instance_valid(player):
		return
	var here := player.global_position
	for k in _staged.keys():
		var id := int(k)
		var rec: Dictionary = _by_id.get(id, {})
		if rec.is_empty() or (rec["at"] as Vector3).distance_to(here) > STRIKE_RADIUS:
			_strike(id)
	for row in near(here, STAGE_RADIUS):
		if _staged.size() >= MAX_STAGED:
			break
		var rec2: Dictionary = (row as Dictionary)["rec"]
		var id2 := int(rec2["id"])
		if _staged.has(id2):
			continue
		var body := _build_body(rec2)
		if body == null:
			continue
		add_child(body)
		_staged[id2] = body
		var prof2: Dictionary = CritterDex.get_profile(String(rec2.get("species", "")))
		_mow(rec2["at"] as Vector3, mow_radius(float(prof2.get("len", 1.0))))


func _strike(id: int) -> void:
	var n: Variant = _staged.get(id, null)
	if n is Node and is_instance_valid(n as Node):
		(n as Node).queue_free()
	_staged.erase(id)


func staged_ids() -> Array:
	var out: Array = _staged.keys()
	out.sort()
	return out


static func mow_radius(length_m: float) -> float:
	return clampf(length_m * MOW_PER_M, MOW_MIN, MOW_MAX)


func _mow(at: Vector3, radius: float) -> void:
	## Anything lying on open ground has to say what happens to the meadow
	## under it — the lesson of the croft yard that stood invisible in
	## standing grass at 196/0 green. A body mats the grass it fell in, and
	## `GrassSystem.cut_at` already persists its cuts across a chunk reload.
	var key := "%d_%d" % [int(round(at.x)), int(round(at.z))]
	if _mown.has(key):
		return
	_mown[key] = true
	if not is_inside_tree():
		return
	var g := get_tree().get_first_node_in_group("grass_system")
	if g == null or not is_instance_valid(g) or not g.has_method("cut_at"):
		return
	g.call("cut_at", at, radius)


func _ask_for_bodies(rec: Dictionary) -> void:
	## ASK, never assume. The director is free to refuse — its budget is 26
	## animals and a dev spawn must never be blocked by a crow — so nothing
	## about what comes back is written into the record. The claim happened
	## on the ledger whether or not there was room in the woods for a body.
	if wild == null or not is_instance_valid(wild) or not wild.has_method("spawn_one"):
		return
	var id := int(rec["id"])
	for g in GUILDS.size():
		if not present(rec, g, days):
			continue
		var row: Dictionary = GUILDS[g]
		var key := "%d|%s" % [id, String(row["id"])]
		if _asked.has(key):
			continue
		_asked[key] = true
		var kinds: Array = row["kinds"]
		if kinds.is_empty():
			continue
		var at: Vector3 = rec["at"]
		var n := int(row["n"])
		for i in n:
			var h := _hash(world_seed ^ id, i, SALT_KIND)
			var species := String(kinds[h % kinds.size()])
			var a := _unit(h, 3) * TAU
			var rr := 3.0 + _unit(h, 5) * 5.0
			wild.call("spawn_one", species,
					at + Vector3(cos(a) * rr, 0.0, sin(a) * rr))
		_ring(at, int(row["threat"]), String(row["nm"]))


func _ring(at: Vector3, threat: int, who: String) -> void:
	if threat <= 0 or not is_inside_tree():
		return
	Telegraph.ring(self, at, RING_M, threat, who, 0)


func _build_body(rec: Dictionary) -> Node3D:
	## PSX flat-shaded: four boxes that read as a dead thing IS the correct
	## answer here, and the stage is the whole of what changes.
	var root := Node3D.new()
	root.name = "Carcass%d" % int(rec["id"])
	var at: Vector3 = rec["at"]
	root.position = Vector3(at.x, _ground_y(at), at.z)
	root.add_to_group("carcass_bodies")
	_dress(root, rec)
	return root


func _dress(root: Node3D, rec: Dictionary) -> void:
	for c in root.get_children():
		c.queue_free()
	var st := stage_of(rec)
	var id := int(rec["id"])
	var length := 1.0
	var prof: Dictionary = CritterDex.get_profile(String(rec.get("species", "")))
	if not prof.is_empty():
		length = float(prof.get("len", 1.0))
	var yaw := _unit(_hash(world_seed ^ id, 0, SALT_BODY), 7) * TAU
	root.rotation.y = yaw
	## THE GROUND UNDER IT IS WHAT YOU SEE FIRST, and the first live look at
	## this feature is the reason this slab exists. A flat-shaded box lying
	## in stubble is a dark lump at ten metres and invisible at twenty; a
	## patch of trodden, stained earth the size of the animal reads from
	## across a field -- and it is the honest thing to draw, because this is
	## where something bled and where five kinds of animal have been standing
	## on it for three days. It goes down at EVERY stage, including the last:
	## the bare ground is the longest-lived part of a carcass.
	var soil := Color(0.17, 0.12, 0.09)
	if st >= STAGE_PICKED:
		soil = Color(0.24, 0.20, 0.15)
	_slab(root, length * GROUND_SCALE, soil)
	## The hide is the LIVE animal's colour, barely touched. The first draft
	## darkened it 35 %, which is exactly how the croft's walls vanished into
	## a summer hillside at 196/0 green.
	var hide := Color(0.40, 0.32, 0.24)
	if not prof.is_empty() and prof.get("col") is Color:
		hide = (prof["col"] as Color).lightened(0.10)
	var bone := Color(0.88, 0.85, 0.76)
	var meat := Color(0.44, 0.14, 0.13)
	var lift := length * 0.05
	match st:
		STAGE_WHOLE:
			_box(root, Vector3(length * 0.86, length * 0.32, length * 0.34),
					Vector3(0.0, lift + length * 0.16, 0.0), hide)
			_box(root, Vector3(length * 0.30, length * 0.22, length * 0.22),
					Vector3(length * 0.55, lift + length * 0.11, 0.0), hide)
			_legs(root, length, lift, hide, 4)
		STAGE_OPENED:
			_box(root, Vector3(length * 0.80, length * 0.26, length * 0.32),
					Vector3(0.0, lift + length * 0.13, 0.0), hide)
			_box(root, Vector3(length * 0.34, length * 0.12, length * 0.26),
					Vector3(-length * 0.10, lift + length * 0.25, 0.0), meat)
			_legs(root, length, lift, hide, 3)
		STAGE_PICKED:
			_box(root, Vector3(length * 0.62, length * 0.16, length * 0.26),
					Vector3(0.0, lift + length * 0.08, 0.0), meat)
			_legs(root, length, lift, bone, 1)
			for i in 5:
				var u := _unit(_hash(world_seed ^ id, i + 11, SALT_JIT), 2)
				_box(root, Vector3(length * 0.05, length * 0.20, length * 0.05),
						Vector3(length * (u - 0.5) * 0.7, lift + length * 0.17,
								length * (0.11 if i % 2 == 0 else -0.11)), bone)
		STAGE_BONES, STAGE_GONE:
			for i in 7:
				var h := _hash(world_seed ^ id, i + 21, SALT_JIT)
				_box(root, Vector3(length * 0.07, length * 0.06, length * 0.28),
						Vector3(length * (_unit(h, 2) - 0.5) * 0.9, lift * 0.5,
								length * (_unit(h, 4) - 0.5) * 0.6), bone)
	root.set_meta("stage", st)


func _slab(root: Node3D, radius: float, col: Color) -> void:
	## The trodden ground. Deliberately not a decal and not a shader: a flat
	## box two centimetres proud of the terrain is what every other prop in
	## this project is made of, and it takes the same flat shading.
	_box(root, Vector3(radius * 1.9, 0.04, radius * 1.5), Vector3(0.0, 0.02, 0.0), col)


func _legs(root: Node3D, length: float, lift: float, col: Color, n: int) -> void:
	## Stiff legs are the whole silhouette. A box on its own in long grass
	## reads as a rock; four thin spars sticking out of it reads, at any
	## distance, as a dead animal -- and losing them one at a time is how
	## the stages tell each other apart from far enough away to matter.
	for i in n:
		var pivot := Node3D.new()
		var fore := 1.0 if i < 2 else -1.0
		var side := 1.0 if i % 2 == 0 else -1.0
		pivot.position = Vector3(length * 0.30 * fore, lift + length * 0.14,
				length * 0.13 * side)
		pivot.rotation.z = side * 0.95
		root.add_child(pivot)
		_box(pivot, Vector3(length * 0.07, length * 0.44, length * 0.07),
				Vector3(0.0, length * 0.20, 0.0), col)


func _box(root: Node3D, size: Vector3, at: Vector3, col: Color) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.95
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.material_override = mat
	root.add_child(m)


func _drive_bodies() -> void:
	## A body is a picture of the record and nothing else, so the only thing
	## driving it is the stage changing under it.
	for k in _staged.keys():
		var id := int(k)
		var rec: Dictionary = _by_id.get(id, {})
		var n: Variant = _staged.get(id, null)
		if rec.is_empty() or not (n is Node3D) or not is_instance_valid(n as Node3D):
			continue
		var body := n as Node3D
		var want := stage_of(rec)
		if int(body.get_meta("stage", -1)) != want:
			_dress(body, rec)


func _ground_y(at: Vector3) -> float:
	if _ground != null and is_instance_valid(_ground):
		if _ground.has_method("_surface_y"):
			return float(_ground.call("_surface_y", at))
		if _ground.has_method("surface_y"):
			return float(_ground.call("surface_y", at))
	return at.y


# ================================= the save ===============================

func to_dict() -> Dictionary:
	var rows: Array = []
	for r in records:
		var rec := r as Dictionary
		var at: Vector3 = rec["at"]
		rows.append({
			"id": int(rec["id"]),
			"species": String(rec["species"]),
			"nm": String(rec["nm"]),
			"x": at.x, "y": at.y, "z": at.z,
			"born": float(rec["born"]),
			"mass": float(rec["mass"]),
			"left": float(rec["left"]),
			"seen": (rec["seen"] as Dictionary).duplicate(),
			"prog": (rec["prog"] as Dictionary).duplicate(),
			"took": (rec["took"] as Dictionary).duplicate(),
			"stripped": float(rec.get("stripped", -1.0)),
			"near_player": bool(rec.get("near_player", false)),
			"place": String(rec.get("place", "")),
			"told": (rec.get("told", {}) as Dictionary).duplicate(),
		})
	return {"v": 1, "hours": _hours, "steps": _steps, "next": _next_id, "rows": rows}


func from_dict(d: Dictionary) -> void:
	records.clear()
	_by_id.clear()
	_known.clear()
	_asked.clear()
	for k in _staged.keys():
		_strike(int(k))
	_hours = float(d.get("hours", 0.0))
	days = _hours / 24.0
	_steps = int(d.get("steps", 0))
	_next_id = int(d.get("next", 1))
	var rows: Array = d.get("rows", [])
	for row in rows:
		var r := row as Dictionary
		if r == null or r.is_empty():
			continue
		var rec := {
			"id": int(r.get("id", 0)),
			"species": String(r.get("species", "")),
			"nm": String(r.get("nm", "")),
			"at": Vector3(float(r.get("x", 0.0)), float(r.get("y", 0.0)), float(r.get("z", 0.0))),
			"born": float(r.get("born", 0.0)),
			"mass": float(r.get("mass", 0.0)),
			"left": float(r.get("left", 0.0)),
			"seen": (r.get("seen", {}) as Dictionary).duplicate(),
			"prog": (r.get("prog", {}) as Dictionary).duplicate(),
			"took": (r.get("took", {}) as Dictionary).duplicate(),
			"stripped": float(r.get("stripped", -1.0)),
			"near_player": bool(r.get("near_player", false)),
			"place": String(r.get("place", "")),
			"told": (r.get("told", {}) as Dictionary).duplicate(),
		}
		records.append(rec)
		_by_id[int(rec["id"])] = rec
		_next_id = maxi(_next_id, int(rec["id"]) + 1)


# ================================= hashing ================================

static func _hash(a: int, b: int, salt: int) -> int:
	var h := (a * 0x27D4EB2F) ^ (b * 0x165667B1) ^ (salt * 0x2545F491)
	h = (h ^ (h >> 15)) * 0x85EBCA6B
	h = (h ^ (h >> 13)) * 0xC2B2AE35
	return absi(h ^ (h >> 16))


static func _unit(h: int, k: int) -> float:
	return float(absi((h >> (k % 11)) % 10007)) / 10007.0
