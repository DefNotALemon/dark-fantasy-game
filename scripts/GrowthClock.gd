class_name GrowthClock
extends Node

## ===========================================================================
## The one clock every GrowthPatch grows by.  World adds one of these.
##
## Lemon (2026-09-03): growth is driven by BOTH game-time age AND the weather.
## So a patch advances by GAME HOURS elapsed (DayNight's day + hour, which also
## means sleeping through a week grows a week of moss), scaled by how wet the
## world is (Weather.wetness lags behind the rain, so the ground stays damp
## after a storm and so does the moss), by how shaded the patch is, and by the
## season -- nothing much grows in winter.
##
## Patches are ticked here, in one place, every TICK seconds, instead of each
## running its own _process: a hundred patches is one loop, not a hundred.
##
## Statics so a patch restored from a save can ask "what day is it" without
## a node reference -- World.apply_state sets the day and restores the trees in
## the same frame, so this reads the LIVE DayNight, never a cached number.
## ===========================================================================

const TICK := 1.5                 ## real seconds between growth ticks
## Game days for a moss patch in average conditions (half shade, dry) to go
## from nothing to fully grown. Rain and shade shorten it; see rate_for.
const DAYS_TO_FULL := 40.0
const WET_BOOST := 2.0            ## rate multiplier at full wetness = 1 + WET_BOOST * wet
const WINTER_RATE := 0.15         ## growth in winter, as a share
const AUTUMN_RATE := 0.65
## What a patch that has no weather history assumes it lived through while
## the save was closed -- a load catches the patch up on the days it missed.
const NOMINAL_WET := 0.30

## The dials. SPEED is the one to turn to watch it happen.
static var SPEED := 1.0

static var _daynight: Node = null
static var _weather: Node = null
static var _instance: GrowthClock = null

var _acc := 0.0
var _last_days := -1.0


static func bind(daynight: Node, weather: Node) -> void:
	_daynight = daynight
	_weather = weather


static func now_days() -> float:
	## Game time as a float day count -- day + hour/24. -1 if there is no clock
	## (a headless test with no World), in which case patches simply never
	## catch up on load.
	if _daynight != null and is_instance_valid(_daynight) and "day" in _daynight and "hour" in _daynight:
		return float(_daynight.day) + float(_daynight.hour) / 24.0
	return -1.0


static func wetness() -> float:
	if _weather != null and is_instance_valid(_weather) and "wetness" in _weather:
		return clampf(float(_weather.wetness), 0.0, 1.0)
	return 0.0


static func season_rate(days: float) -> float:
	## 0 spring, 1 summer, 2 autumn, 3 winter -- Wind owns the season maths
	if days < 0.0:
		return 1.0
	var s := int(Wind.phase_for_day(days) * 4.0) % 4
	match s:
		3:
			return WINTER_RATE
		2:
			return AUTUMN_RATE
	return 1.0


## Growth per game hour for a patch. `fam` is the GrowthTypes family, `shade`
## is 0 (full sun) .. 1 (deep shade), `damp` is a host's own dampness (a cave
## mouth drips; a rock does not) added to the weather's.
static func rate_for(fam: Dictionary, shade: float, damp: float, wet: float, days: float) -> float:
	var per_hour := 1.0 / (DAYS_TO_FULL * 24.0)
	var w := clampf(wet + damp, 0.0, 1.0)
	var sun_penalty: float = float(fam.get("shade", 1.0)) * (1.0 - clampf(shade, 0.0, 1.0)) * 0.5
	var rate := per_hour * float(fam.get("speed", 1.0)) \
		* (1.0 - sun_penalty) \
		* (1.0 + WET_BOOST * float(fam.get("wet", 1.0)) * w) \
		* season_rate(days) * SPEED
	return maxf(rate, 0.0)


func _ready() -> void:
	_instance = self
	add_to_group("growth_clock")


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _process(delta: float) -> void:
	_acc += delta
	if _acc < TICK:
		return
	_acc = 0.0
	tick()


func tick() -> void:
	## Advance every patch by the game hours since the last tick.
	var days := now_days()
	if days < 0.0:
		return
	if _last_days < 0.0:
		_last_days = days
		return
	var hours := (days - _last_days) * 24.0
	_last_days = days
	if hours <= 0.0:
		return
	## a clock that ran backwards (sky menu, a load) is not a season of growth
	hours = minf(hours, 24.0 * 400.0)
	var wet := wetness()
	for p in get_tree().get_nodes_in_group("growth_patches"):
		if p.has_method("advance"):
			p.advance(hours, wet, days)
