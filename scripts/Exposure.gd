class_name Exposure
extends RefCounted

## ===========================================================================
## COLD - scripts/Exposure.gd  (2026-09-10, SYSTEMS DEPTH)
##
## Myrkfell had weather you could look at and, since `c89be45`, a fire that
## actually burns - and nothing anywhere that made either one matter to the
## body standing in it. This is the thing that makes them matter.
##
## DEGREES ARE THE TUNING CURRENCY, NOT THE METER. Every dial in here is one
## number in Celsius, so "an autumn night is about three degrees" and "being
## soaked costs you nine of them" are claims you can argue with. The meter is
## one line of arithmetic downstream of the degrees, and it is the degrees
## that were measured against the four rows of the survival table.
##
## TWO NUMBERS OF STATE, AND ONLY TWO:
##   warmth   0..100. The meter. Falls while `felt` is under WARMTH_NEUTRAL_C
##            and climbs while it is over.
##   wet      0..1. How soaked the BODY is. This is NOT `Weather.wetness`,
##            which is the GROUND and lags the rain by minutes.
##
## Everything else - ambient, felt, the fire's contribution, the drain rate -
## is a PURE FUNCTION of an environment dictionary the caller builds. `step()`
## is the only method that changes anything and the only thing it changes is
## those two floats. That is what makes "a winter midnight, soaked, in a gale,
## with no fire and no roof" a call with arguments rather than something you
## have to stand in a field and wait for.
##
## WET IS THE MULTIPLIER, AND THAT IS THE DESIGN. Weather you can walk through
## is never lethal. Weather plus wet plus no plan is lethal in about the time
## it takes to find wood. Standing under a roof zeroes the wind term AND the
## precipitation term, which is the whole reason to build one before you are
## cold rather than after.
##
## WHAT IT READS FROM OTHER PEOPLE (no node, no clock, no RNG lives in here):
##   Firepit.heat_from(fires, at)   the MAXIMUM across lit pits, never the sum
##   Wind.phase_for_day(day)        which quarter of the year it is, without
##                                  needing a Weather node to ask
##   GameMode                       Peaceful never kills; Hardcore drains 1.25x
##
## Each of those three gets its own section in `tests/ExposureTests.gd`, driven
## against the REAL class and not a stub, because a stub is not the
## collaborator (2026-09-09) and that holds for a file that only CALLS one.
## ===========================================================================


# ===========================================================================
#  The sky - what the air outside is doing
# ===========================================================================

## Spring, summer, autumn, winter. The year Myrkfell is set in is a Maine one:
## a summer afternoon is pleasant, a winter night is not survivable in a shirt.
const SEASON_BASE_C: Array[float] = [10.0, 18.0, 8.0, -4.0]

## The diurnal swing is SKEWED, not a plain cosine: the ten hours from 04:00 to
## 14:00 are the rising half and the fourteen hours back round are the falling
## half, so the coldest hour is just before dawn and the warmest is early
## afternoon. A symmetric cosine would put the warmest hour at 16:00 and every
## dusk in the game would be warmer than it looks.
const HOUR_SWING_C := 5.0
const HOUR_COLDEST := 4.0
const HOUR_WARMEST := 14.0

## 6.5 C per kilometre, which is the real environmental lapse rate. The bake's
## highlands are a few hundred metres up, so this is worth about two degrees -
## small, but it means a ridge line at night is measurably worse than the
## valley you climbed out of.
const LAPSE_PER_M := 0.0065
const LAPSE_BASE_Y := 60.0

## By `Weather.Level`: CLEAR, OVERCAST, DRIZZLE, RAIN, STORM. Scaled by
## `Weather.intensity`, so a storm still building is not yet a storm.
const WEATHER_C: Array[float] = [0.0, -1.0, -2.0, -3.5, -6.0]

## Wind is the term shelter kills outright. Snow costs a little more than the
## same intensity of rain because it comes with the air that made it.
const WIND_C := -3.0
const SNOW_C := -1.5

## `Weather.intensity` above which precipitation is actually landing on you.
const RAIN_ON_YOU := 0.05

## `Weather.Level` at or above which what is falling can soak you. Overcast
## does not; drizzle does.
const RAIN_LEVEL := 2


# ===========================================================================
#  The body - what the air outside costs the man standing in it
# ===========================================================================

## Nine degrees for being soaked through, and up to nine more on top of that in
## a full gale: wind on wet skin is the single most dangerous combination in
## the game and the arithmetic says so out loud.
const WET_CHILL_C := 9.0
const WET_CHILL_WIND := 1.0

const TORCH_C := 3.5      ## a lit torch in hand is a poor fire, but it is one
const SHELTER_C := 2.0    ## a roof over you, on top of killing wind and rain
const BED_C := 6.0        ## asleep on a bedroll, wrapped up


# ===========================================================================
#  The meter
# ===========================================================================

const WARMTH_MAX := 100.0
const WARMTH_NEUTRAL_C := 12.0            ## at or above this, warmth comes back
const WARMTH_PER_DEGREE_S := 0.013        ## lost per degree below neutral, /s
## MEASURED, not chosen. At the spec's 0.030 a lit firepit on an autumn night
## took TEN REAL MINUTES to bring the meter back from empty, which makes the
## fire read as weather rather than as the answer to it. 0.075 puts that row
## at four minutes, which is the shape the whole feature is for: the cold is
## slow and the fire is decisive.
const WARMTH_REGAIN_PER_DEGREE_S := 0.075
const WARMTH_REGAIN_CAP := 0.55           ## /s: a bonfire is fast, not instant
const WARMTH_LOW := 30.0                  ## shivering
const WARMTH_NUMB := 10.0                 ## hands going
const WARMTH_DAMAGE_PER_S := 0.5
const WARMTH_RESPAWN_MIN := 60.0          ## never respawn a body already dying
const WARMTH_MSG_GAP := 12.0              ## seconds between "the cold is..."


# ===========================================================================
#  Wet
# ===========================================================================

const WET_SWIM_PER_S := 0.7        ## soaked in about a second and a half
const WET_RAIN_PER_S := 0.06       ## about seventeen seconds in a full storm
const WET_DRY_PER_S := 0.010       ## about a hundred seconds to dry off
const WET_DRY_FIRE_MULT := 4.0
const WET_DRY_SHELTER_MULT := 1.6
const WET_FIRE_C := 3.0            ## fire heat that counts as "by a fire"


# ===========================================================================
#  Modes and consequences
# ===========================================================================

const MODE_PEACEFUL := 0
const MODE_NORMAL := 1
const MODE_HARDCORE := 2
const PEACE_DRAIN_MULT := 0.5
const HARD_DRAIN_MULT := 1.25

const SHIVER_STAMINA_MULT := 0.5
const NUMB_WINDUP_MULT := 1.15
const SHIVER_SWAY := 1.0
const NUMB_SWAY := 2.0

## What the caller prints when `step()` reports a crossing. Kept here so the
## HUD wiring holds no strings of its own and a reworded warning is a one-line
## diff in a tested file.
const MESSAGES := {
	"low": ["Shivering", Color(0.85, 0.80, 0.55)],
	"numb": ["Your hands are going", Color(1.0, 0.70, 0.40)],
	"dying": ["The cold is killing you", Color(1.0, 0.45, 0.30)],
	"recovered": ["Warm again", Color(0.72, 0.86, 0.74)],
}


# ===========================================================================
#  The environment dictionary
# ===========================================================================

## Every key the model reads, with the value it takes when nobody says. One
## vocabulary shared by the caller and the suite: a misspelt key would
## otherwise read as a default and quietly turn a storm into a clear day.
## `unknown_env_keys()` is how a caller catches that before it ships.
const DEFAULTS := {
	"season": 0,          ## 0 spring 1 summer 2 autumn 3 winter
	"hour": 12.0,         ## DayNight.hour, 0..24
	"y": 60.0,            ## metres; LAPSE_BASE_Y is sea-ish level
	"level": 0,           ## Weather.Level
	"intensity": 0.0,     ## Weather.intensity, 0..1
	"snowing": false,     ## Weather.is_snowing()
	"wind": 0.0,          ## Wind.last_strength, 0..1
	"sheltered": false,   ## a roof within reach overhead
	"underground": false, ## World._underground
	"fire_c": 0.0,        ## Firepit.heat_from(...), degrees
	"torch": false,       ## a LIT torch in hand
	"asleep": false,      ## on a bedroll
	"worn": {},           ## armour slot -> Materials id; see Garments.gd
	"base_c": NAN,        ## Seasons.base_c_at() for HERE; NAN = use the table
	"swimming": false,
	"mode": MODE_NORMAL,
	"survival": true,     ## Settings -> Warmth: Survival, not Light
}


static func env(o: Dictionary = {}) -> Dictionary:
	var e: Dictionary = DEFAULTS.duplicate(true)
	for k in o:
		e[k] = o[k]
	return e


static func unknown_env_keys(o: Dictionary) -> Array:
	var bad: Array = []
	for k in o:
		if not DEFAULTS.has(k):
			bad.append(k)
	bad.sort()
	return bad


# ===========================================================================
#  Ambient - pure, no state, no node
# ===========================================================================

static func season_for_day(day: float) -> int:
	## 0 spring, 1 summer, 2 autumn, 3 winter - the same quarter of the year
	## `Wind.season_name()` prints and `Weather.season()` returns, without
	## needing a Weather node in the tree to ask.
	return int(Wind.phase_for_day(day) * 4.0) % 4


static func hour_curve_c(hour: float) -> float:
	## Coldest at HOUR_COLDEST, warmest at HOUR_WARMEST, continuous at both
	## joins, and NOT symmetric - see the note on HOUR_SWING_C.
	var h := fposmod(hour, 24.0)
	var u := 0.0
	if h >= HOUR_COLDEST and h < HOUR_WARMEST:
		u = (h - HOUR_COLDEST) / (HOUR_WARMEST - HOUR_COLDEST)
	else:
		var d := h - HOUR_WARMEST
		if d < 0.0:
			d += 24.0
		u = 1.0 - d / (24.0 - (HOUR_WARMEST - HOUR_COLDEST))
	return -HOUR_SWING_C * cos(PI * clampf(u, 0.0, 1.0))


static func lapse_c(y: float) -> float:
	return -LAPSE_PER_M * (y - LAPSE_BASE_Y)


static func weather_c(level: int, intensity: float) -> float:
	var i := clampi(level, 0, WEATHER_C.size() - 1)
	return WEATHER_C[i] * clampf(intensity, 0.0, 1.0)


static func wind_c(wind: float, sheltered: bool) -> float:
	if sheltered:
		return 0.0
	return WIND_C * clampf(wind, 0.0, 1.0)


static func is_sheltered(e: Dictionary) -> bool:
	## A roof over your head or a cave around you. Both zero the wind and the
	## rain; the ray that finds the roof lives in the caller, because a
	## physics query is the one thing this file refuses to own.
	return bool(e.get("sheltered", false)) or bool(e.get("underground", false))


static func ambient_c(e: Dictionary) -> float:
	var season := clampi(int(e.get("season", 0)), 0, SEASON_BASE_C.size() - 1)
	var sheltered := is_sheltered(e)
	var intensity := clampf(float(e.get("intensity", 0.0)), 0.0, 1.0)
	var c := SEASON_BASE_C[season]
	var local := float(e.get("base_c", NAN))
	if not is_nan(local):
		## `Seasons.base_c_at()` answers this same question for a PLACE,
		## continuously, on that place's own calendar. When the caller has
		## bothered to ask it, its answer replaces the shared table
		## outright -- everything below here (the hour, the lapse rate,
		## the weather, the wind) still applies on top, because this term
		## is the SEASON's contribution and nothing else's.
		c = local
	c += hour_curve_c(float(e.get("hour", 12.0)))
	c += lapse_c(float(e.get("y", LAPSE_BASE_Y)))
	if not sheltered:
		c += weather_c(int(e.get("level", 0)), intensity)
		if bool(e.get("snowing", false)):
			c += SNOW_C * intensity
	c += wind_c(float(e.get("wind", 0.0)), sheltered)
	return c


static func still_air_c(e: Dictionary) -> float:
	## The air with the wind's own chill taken back OUT of it.
	##
	## This is the temperature a harness has been sitting in, and it is
	## what `Garments` is asked for. Handing it the windy figure instead
	## would charge the metal for conducting away the very draught it is
	## standing in the way of, and a full suit of plate in a gale would
	## then be scored twice for the same three degrees.
	return ambient_c(e) - wind_c(float(e.get("wind", 0.0)), is_sheltered(e))


static func garment_c(e: Dictionary, wet_v: float) -> float:
	## What is on your back, in degrees. `Garments` owns every number in
	## here; this is the door it comes through, and it is the only place
	## in the project that reads the `worn` key.
	var sheltered := is_sheltered(e)
	var wind := 0.0 if sheltered else clampf(float(e.get("wind", 0.0)), 0.0, 1.0)
	var worn: Dictionary = e.get("worn", {})
	return Garments.garment_c(worn, still_air_c(e), clampf(wet_v, 0.0, 1.0), wind)


static func felt_c(e: Dictionary, wet_v: float) -> float:
	## What the body is actually up against: ambient, less what being wet costs
	## in this wind, plus every source of heat within reach.
	var sheltered := is_sheltered(e)
	var wind := 0.0 if sheltered else clampf(float(e.get("wind", 0.0)), 0.0, 1.0)
	var chill := WET_CHILL_C * (1.0 + WET_CHILL_WIND * wind) * clampf(wet_v, 0.0, 1.0)
	var f := ambient_c(e) - chill
	f += garment_c(e, wet_v)
	f += maxf(0.0, float(e.get("fire_c", 0.0)))
	if bool(e.get("torch", false)):
		f += TORCH_C
	if sheltered:
		f += SHELTER_C
	if bool(e.get("asleep", false)):
		f += BED_C
	return f


# ===========================================================================
#  Rates - pure
# ===========================================================================

static func drain_mult_for(mode: int) -> float:
	if mode == MODE_PEACEFUL:
		return PEACE_DRAIN_MULT
	if mode == MODE_HARDCORE:
		return HARD_DRAIN_MULT
	return 1.0


static func warmth_rate(felt: float, mode: int) -> float:
	## Warmth per second: negative losing, positive gaining. The mode tax is on
	## the DRAIN only, deliberately - Hardcore is meant to make the cold bite
	## harder, not to make a fire you have already built warm you slower.
	if felt >= WARMTH_NEUTRAL_C:
		return minf(WARMTH_REGAIN_CAP, (felt - WARMTH_NEUTRAL_C) * WARMTH_REGAIN_PER_DEGREE_S)
	return -((WARMTH_NEUTRAL_C - felt) * WARMTH_PER_DEGREE_S * drain_mult_for(mode))


static func raining_on(e: Dictionary) -> bool:
	if is_sheltered(e):
		return false
	return int(e.get("level", 0)) >= RAIN_LEVEL \
		and float(e.get("intensity", 0.0)) > RAIN_ON_YOU


static func wet_rate(e: Dictionary, wet_v: float) -> float:
	## Per second, signed. Swimming beats everything; rain soaks you only up to
	## how hard it is falling; drying is zero while anything is landing on you.
	if bool(e.get("swimming", false)):
		return WET_SWIM_PER_S
	if raining_on(e):
		var target := clampf(float(e.get("intensity", 0.0)), 0.0, 1.0)
		return 0.0 if wet_v >= target else WET_RAIN_PER_S
	var dry := WET_DRY_PER_S
	if float(e.get("fire_c", 0.0)) >= WET_FIRE_C:
		dry *= WET_DRY_FIRE_MULT
	elif is_sheltered(e):
		dry *= WET_DRY_SHELTER_MULT
	## And metal does not breathe. A man drying himself at a fire in full
	## plate is working against his own harness, which is why getting out
	## of it is an ACTION rather than a number on a sheet.
	dry *= Garments.dry_mult(e.get("worn", {}))
	return -dry


# ===========================================================================
#  Consequences of a low meter - pure
# ===========================================================================

static func stamina_mult(warmth_v: float) -> float:
	return SHIVER_STAMINA_MULT if warmth_v < WARMTH_LOW else 1.0


static func windup_mult(warmth_v: float) -> float:
	return NUMB_WINDUP_MULT if warmth_v < WARMTH_NUMB else 1.0


static func sway_extra(warmth_v: float) -> float:
	if warmth_v < WARMTH_NUMB:
		return NUMB_SWAY
	if warmth_v < WARMTH_LOW:
		return SHIVER_SWAY
	return 0.0


# ===========================================================================
#  The collaborators' real front doors
# ===========================================================================

static func fire_c(fires: Array, at: Vector3) -> float:
	## Firepit's door. MAXIMUM across pits, never the sum: two campfires are
	## not a furnace, and a croft hearth counts exactly like your own.
	return Firepit.heat_from(fires, at)


static func mode_now() -> int:
	## GameMode's door, and the one impure static in the file.
	if GameMode.is_peaceful():
		return MODE_PEACEFUL
	if GameMode.is_hardcore():
		return MODE_HARDCORE
	return MODE_NORMAL


# ===========================================================================
#  The two numbers of state
# ===========================================================================

var warmth := WARMTH_MAX
var wet := 0.0

var _msg_t := 0.0
var _dying := false


func step(e: Dictionary, delta: float) -> Dictionary:
	## The whole feature, once a frame. Returns a REPORT and touches no node,
	## no HUD and no health bar: the caller decides what to do about it.
	var d := maxf(0.0, delta)
	_msg_t = maxf(0.0, _msg_t - d)
	var mode := int(e.get("mode", MODE_NORMAL))

	## Wet is a physical fact rather than a punishment, so it is tracked in
	## Light mode too: switching back to Survival in the rain must not start
	## you dry.
	var wr := wet_rate(e, wet)
	wet = clampf(wet + wr * d, 0.0, 1.0)

	var amb := ambient_c(e)
	var felt := felt_c(e, wet)
	var rate := warmth_rate(felt, mode)

	if not bool(e.get("survival", true)):
		warmth = WARMTH_MAX
		_dying = false
		_msg_t = 0.0
		return _report(amb, felt, 0.0, wr, 0.0, "")

	var before := warmth
	warmth = clampf(warmth + rate * d, 0.0, WARMTH_MAX)

	var crossed := ""
	if before >= WARMTH_LOW and warmth < WARMTH_LOW:
		crossed = "low"
	elif before >= WARMTH_NUMB and warmth < WARMTH_NUMB:
		crossed = "numb"
	elif before < WARMTH_LOW and warmth >= WARMTH_LOW:
		crossed = "recovered"

	var dmg := 0.0
	if warmth <= 0.0 and mode != MODE_PEACEFUL:
		dmg = WARMTH_DAMAGE_PER_S * d
		_dying = true
		if _msg_t <= 0.0:
			_msg_t = WARMTH_MSG_GAP
			crossed = "dying"
	else:
		_dying = false
	return _report(amb, felt, rate, wr, dmg, crossed)


func _report(amb: float, felt: float, rate: float, wr: float,
		damage: float, crossed: String) -> Dictionary:
	return {
		"ambient": amb,
		"felt": felt,
		"rate": rate,
		"wet_rate": wr,
		"damage": damage,
		"crossed": crossed,
		"warmth": warmth,
		"wet": wet,
		"shivering": warmth < WARMTH_LOW,
		"numb": warmth < WARMTH_NUMB,
		"dying": _dying,
	}


# ===========================================================================
#  Save, respawn, settings
# ===========================================================================

func to_dict() -> Dictionary:
	return {"warmth": warmth, "wet": wet}


func apply_dict(d: Dictionary) -> void:
	## A save written before this feature existed has neither key, and loads
	## to a warm dry body rather than to a corpse.
	warmth = clampf(float(d.get("warmth", WARMTH_MAX)), 0.0, WARMTH_MAX)
	wet = clampf(float(d.get("wet", 0.0)), 0.0, 1.0)
	_msg_t = 0.0
	_dying = false


func on_respawn() -> void:
	warmth = maxf(warmth, WARMTH_RESPAWN_MIN)
	wet = 0.0
	_msg_t = 0.0
	_dying = false


func to_light() -> void:
	## Switching Settings -> Warmth to Light tops the meter, so switching back
	## can never start you freezing. The thirst pass established that rule and
	## breaking it here would be a regression in feel.
	warmth = WARMTH_MAX
	_msg_t = 0.0
	_dying = false


# ===========================================================================
#  Readouts - the god panel, and the probe that measured the table
# ===========================================================================

func readout(e: Dictionary) -> String:
	var fire := maxf(0.0, float(e.get("fire_c", 0.0)))
	return "warmth %.0f / wet %.2f / felt %.1fC (amb %.1f, fire +%.1f, wind %.2f%s)" % [
		warmth, wet, felt_c(e, wet), ambient_c(e), fire,
		float(e.get("wind", 0.0)), ", sheltered" if is_sheltered(e) else ""]


static func seconds_to_empty(e: Dictionary, wet_v: float, from_v := WARMTH_MAX) -> float:
	## Hold an environment still and ask how long the meter lasts. INF when it
	## never empties - which is the answer for every day you can walk through.
	var r := warmth_rate(felt_c(e, wet_v), int(e.get("mode", MODE_NORMAL)))
	if r >= 0.0:
		return INF
	return from_v / -r


static func seconds_to_full(e: Dictionary, wet_v: float, from_v := 0.0) -> float:
	var r := warmth_rate(felt_c(e, wet_v), int(e.get("mode", MODE_NORMAL)))
	if r <= 0.0:
		return INF
	return (WARMTH_MAX - from_v) / r
