class_name Seasons
extends RefCounted

## THE YEAR — and the fact that it does not arrive everywhere on the same day.
##
## Before this file, nine places in the project each worked out what season it
## was, and every one of them got the same answer, because every one of them
## computed `int(Wind.phase_for_day(day) * 4.0) % 4`. That agreement was the
## problem: a season was a property of the CALENDAR, so all 41.7 km of Myrkfell
## turned on the same midnight. A mountain and a harbour a hundred kilometres
## apart shared a spring.
##
## Here a season is a property of a PLACE. `local_index(day, pos)` is the
## season at a point on the map, and on 30 of the year's 96 days the map does
## not agree with itself about what that is.
##
## ## The warp
##
## A cold place does not have a SHIFTED year, it has a SHORTER summer. Every
## seasonal boundary is a threshold crossing on the year's temperature wave,
## and dropping that wave (a colder place) moves crossings on the warming limb
## LATER and crossings on the cooling limb EARLIER. Both ends of summer close
## in; both ends of winter open out. Spring and autumn keep their length and
## slide.
##
## One term does all four:
##
##     local_phase = phase + s * sin(TAU * (phase - MIDSUMMER_PHASE))
##
## because `sin(TAU * (p - 0.375))` is zero at midsummer and midwinter, −1 at
## mid-spring (the middle of the warming limb) and +1 at mid-autumn (the middle
## of the cooling limb). At s > 0 the four boundaries move, in the four right
## directions, off a single coefficient.
##
##   p = 0.25  spring→summer   −0.707s   summer starts LATE
##   p = 0.50  summer→autumn   +0.707s   summer ends EARLY
##   p = 0.75  autumn→winter   +0.707s   winter starts EARLY
##   p = 1.00  winter→spring   −0.707s   spring starts LATE
##
## ⚠ The warp is only a warp while it is MONOTONE. d(local)/dp is
## `1 + s*TAU*cos(...)`, so s must stay under `1/TAU` = 0.1592 or the year
## runs backwards for part of itself. `WARP_LIMIT` clamps well short of it and
## `SeasonsTests` sweeps the whole map against the real limit.
##
## ## Where s comes from
##
## Three facts about a point, each measured off the map that exists:
##
##   LATITUDE   the roster spans z = +560 (Casco Bay) to −7000 (Aroostook).
##   ALTITUDE   sea level to Katahdin's 900 m.
##   THE SEA    salt water holds its heat. The coast is MILDER (a negative s:
##              a longer summer and a shorter winter) and it also LAGS, which
##              is a plain phase offset and the only part of this that is.
##
## The constants were not chosen, they were fitted. Real Maine's growing season
## runs about 170 days on the south coast and about 100 in Aroostook, a ratio
## near 1.7. These four give Casco Bay 28.6 summer days against Katahdin's 16.4
## — 1.74 — and they do it with 2× headroom on the monotonicity limit.
##
## The result worth pointing at is one nobody put in by hand: DOWN EAST sits at
## latitude 0.444, well north of the Kennebec's 0.264, and still has the longer
## summer, because the ocean cancels its latitude. That is true of the real
## place and it falls out of three lines of arithmetic.
##
## ## The table
##
## Five systems each carried a private four-value array of what a season means
## — rot, scent, hearth burn, wood gathering, base temperature. They are all
## here now, as ANCHORS, and `SeasonsTests` asserts each one still equals the
## array in the file it came from. Edit one of the five and this file's suite
## goes red naming it. That is the reconciliation: no risky five-file refactor,
## and the tables can never drift apart again in silence.
##
## `sample()` reads an anchor set CONTINUOUSLY, on the same hold-and-turn curve
## the grass shader uses for colour — held flat through the first 55 % of a
## season, then turned into the next. So a number and the meadow's colour change
## on the same week, and a value sampled mid-season is EXACTLY the old constant.
##
## Pure statics throughout: no node, no clock, no RNG, no `get_tree`, no
## `await`. Position comes in as an argument; nothing here goes looking for it.

# ===========================================================================
#  The calendar
# ===========================================================================

## One season is 24 game days, a year 96 (trees-v2 spec §7). `Wind.gd` owns
## these numbers; they are mirrored here for the same reason `Crofts` and
## `Chronicle` mirror them — a headless suite must be able to ask what season
## it is without a `Wind` autoload in the tree — and asserted equal to Wind's.
const DAYS_PER_SEASON := 24.0
const DAYS_PER_YEAR := DAYS_PER_SEASON * 4.0

## Phase 0 is the first day of spring. Midsummer is therefore the middle of
## index 1, at 0.375, and midwinter the middle of index 3, at 0.875 — the two
## fixed points of the warp.
const MIDSUMMER_PHASE := 0.375

const SPRING := 0
const SUMMER := 1
const AUTUMN := 2
const WINTER := 3

const NAMES: Array[String] = ["Spring", "Summer", "Autumn", "Winter"]


static func phase(day: float) -> float:
	## The year as 0..1. THE definition — `Wind.phase_for_day` computes the
	## identical thing and the suite holds the two together.
	return fposmod(day, DAYS_PER_YEAR) / DAYS_PER_YEAR


static func index(day: float) -> int:
	## The season on the CALENDAR, ignoring where you are standing. This is
	## what the nine existing readings all return, and it is still correct for
	## anything genuinely global — the Chronicle's world-scale weather, a save
	## header, the title card.
	return int(phase(day) * 4.0) % 4


static func name_of(season: int) -> String:
	return NAMES[clampi(season, 0, 3)]


static func index_of_phase(p: float) -> int:
	return int(fposmod(p, 1.0) * 4.0) % 4


# ===========================================================================
#  The map — latitude, altitude, and the sea
# ===========================================================================

## The north-south span of `Chronicle.REGION_ROSTER`: Casco Bay at z = +560 is
## the south end, Aroostook at z = −7000 the north. z runs NEGATIVE northward.
const SOUTH_Z := 560.0
const NORTH_Z := -7000.0

## Katahdin's summit is the roof of the map at ~900 m, and sea level is 0.
const ALT_FULL_Y := 900.0

## Maine's coastline, as the three bay anchors the region roster already
## names: Casco Bay, Penobscot Bay, Down East. Anything on the seaward side of
## this polyline is open water and takes the sea's full influence.
const COAST: Array = [
	Vector2(600.2, 559.9),
	Vector2(2657.3, -520.1),
	Vector2(4971.6, -2800.1),
]

## How far inland the sea is still felt. Penobscot Bay at 397 m reads 0.64,
## Acadia at 496 m reads 0.55, and the Kennebec seat at 1130 m reads 0.00 —
## which is the right shape: the coast is a band, not a line, and it is thin.
const COAST_REACH_M := 1100.0


static func lat_u(pos: Vector3) -> float:
	## 0 at the south coast, 1 at the northern border.
	return clampf((SOUTH_Z - pos.z) / (SOUTH_Z - NORTH_Z), 0.0, 1.0)


static func alt_u(pos: Vector3) -> float:
	## 0 at sea level, 1 on Katahdin. Below sea level is still 0 — a valley
	## floor is not warmer than the shore for this purpose.
	return clampf(pos.y / ALT_FULL_Y, 0.0, 1.0)


static func coast_u(pos: Vector3) -> float:
	## 1 on salt water and on the shore, falling to 0 by `COAST_REACH_M`
	## inland. The seaward test is a cross product against each segment, so
	## the open Gulf — which is 1.5 km from the polyline and unmistakably at
	## sea — reads 1.0 rather than 0.0 off a bare distance.
	var here := Vector2(pos.x, pos.z)
	var best := INF
	var seaward := false
	for i in range(COAST.size() - 1):
		var a: Vector2 = COAST[i]
		var b: Vector2 = COAST[i + 1]
		var ab := b - a
		var t: float = clampf((here - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		best = minf(best, here.distance_to(a + ab * t))
		if (here - a).cross(ab) < 0.0:
			seaward = true
	if seaward:
		return 1.0
	return clampf(1.0 - best / COAST_REACH_M, 0.0, 1.0)


# ===========================================================================
#  The warp
# ===========================================================================

## Fitted against real Maine's growing-season spread — see the header. Raising
## LAT_WARP alone would give the north a shorter summer without giving the
## mountains one; raising ALT_WARP alone would do the reverse.
const LAT_WARP := 0.060      ## Aroostook is this much colder than Casco Bay
const ALT_WARP := 0.035      ## Katahdin's summit, on top of its latitude
const SEA_WARP := 0.030      ## salt water, subtracted: a MILDER year
const SEA_LAG := 0.022       ## and a later one — the sea is slow both ways

## `1.0 / TAU` = 0.1592 is where the warp stops being monotone. The map's
## worst point (Katahdin) reaches 0.079, so this clamp is a guard against a
## future constant, not against the current ones.
const WARP_LIMIT := 0.140


static func warp_at(pos: Vector3) -> float:
	## How much colder this place is than the reference south coast, in units
	## of the year. Positive shortens summer; the coast goes negative.
	var s := LAT_WARP * lat_u(pos) + ALT_WARP * alt_u(pos) - SEA_WARP * coast_u(pos)
	return clampf(s, -WARP_LIMIT, WARP_LIMIT)


static func lag_at(pos: Vector3) -> float:
	## The sea's slowness, as a plain fraction of a year. Inland is 0.
	return SEA_LAG * coast_u(pos)


static func local_day(day: float, pos: Vector3) -> float:
	## The calendar as this place experiences it, still in days and still
	## MONOTONE in `day`, so anything that reads a position within a season
	## (`Crofts.crop_at`) can be handed this instead of the raw day and keep
	## working. Deliberately not wrapped: it stays within about a tenth of a
	## year of `day`, and `local_phase` does the wrapping.
	var lagged := day - lag_at(pos) * DAYS_PER_YEAR
	var q := phase(lagged)
	return lagged + warp_at(pos) * sin(TAU * (q - MIDSUMMER_PHASE)) * DAYS_PER_YEAR


static func warp_days(day: float, pos: Vector3) -> float:
	## The local year as an OFFSET IN DAYS from the calendar — negative where
	## the season is running behind here, positive where it is ahead.
	##
	## ⚠ THIS, not `local_index`, is what a simulation should use. `Crofts`
	## and `Carcasses` both answer "what season is it" through a `season_at`
	## that DELEGATES TO THE CHRONICLE, because the Chronicle owns the
	## calendar and a save has to reproduce it. A consumer that called
	## `local_index` directly would compute its own season and quietly cut
	## the Chronicle out of the loop — which is precisely what the first
	## draft of this file did, and what `CarcassTests` and `CroftTests`
	## caught within the minute by holding a stub Chronicle that forces a
	## season and watching both sims ignore it.
	##
	## Adding this to the day and asking the SAME front door keeps the
	## Chronicle authoritative over what season it is, and lets geography
	## move only WHEN a place arrives there.
	return local_day(day, pos) - day


static func local_phase(day: float, pos: Vector3) -> float:
	return phase(local_day(day, pos))


static func local_index(day: float, pos: Vector3) -> int:
	## THE headline. The season HERE, on this day.
	return index_of_phase(local_phase(day, pos))


static func agrees(day: float, a: Vector3, b: Vector3) -> bool:
	## Whether two places are in the same season on the same day. False on
	## 30 of the year's 96 days somewhere on this map.
	return local_index(day, a) == local_index(day, b)


# ===========================================================================
#  The anchors — five private tables, reconciled
# ===========================================================================

## Each of these is asserted element-for-element equal to the array in the file
## it came from. They are NOT a second copy to keep in step by hand: the suite
## is what keeps them in step, and it names the file when one drifts.

const ROT: Array[float] = [1.00, 1.85, 0.80, 0.22]        ## Carcasses.SEASON_ROT
const SCENT: Array[float] = [1.00, 1.25, 1.00, 0.55]      ## Carcasses.SEASON_SCENT
const BURN: Array[float] = [1.00, 0.55, 1.15, 1.60]       ## Crofts.SEASON_BURN
const GATHER: Array[float] = [1.65, 0.75, 1.55, 0.85]     ## Crofts.SEASON_GATHER
const BASE_C: Array[float] = [10.0, 18.0, 8.0, -4.0]      ## Exposure.SEASON_BASE_C

## The meadow's four stops, equal to `Grass.gd`'s `col_spring` … `col_winter`
## shader uniform defaults. A sixth private reading of the year is exactly what
## this file exists to stop, so these are held to Grass's numbers by assertion
## the same way the other five are.
const MEADOW: Array[Color] = [
	Color(0.35, 0.53, 0.19),
	Color(0.25, 0.40, 0.15),
	Color(0.53, 0.45, 0.19),
	Color(0.40, 0.36, 0.24),
]

## Where the grass shader's own snow term opens and closes, so anything asking
## "is there snow on the ground here" gets the answer the ground is giving.
const SNOW_IN := 0.74
const SNOW_OUT := 0.97

## The hold-and-turn curve, identical to `season_colour()` in Grass.gd's
## fragment shader: a season holds its value flat for 55 % of its length and
## turns into the next over the remaining 45 %.
const TURN_START := 0.55


static func turn_f(p: float) -> float:
	## Where within the turn this phase sits, 0 held and 1 fully turned.
	var t := fposmod(p, 1.0) * 4.0
	return smoothstep(TURN_START, 1.0, t - floorf(t))


static func sample(p: float, anchors: Array) -> float:
	## An anchor set read continuously. ⚠ Mid-season this returns the anchor
	## EXACTLY, which is what lets the five source files keep their tuned
	## numbers while losing their step discontinuity at the turn.
	var t := fposmod(p, 1.0) * 4.0
	var i := int(floorf(t))
	var a := float(anchors[i % 4])
	var b := float(anchors[(i + 1) % 4])
	return lerpf(a, b, turn_f(p))


static func sample_color(p: float, anchors: Array) -> Color:
	var t := fposmod(p, 1.0) * 4.0
	var i := int(floorf(t))
	var a: Color = anchors[i % 4]
	var b: Color = anchors[(i + 1) % 4]
	return a.lerp(b, turn_f(p))


static func rot_at(day: float, pos: Vector3) -> float:
	return sample(local_phase(day, pos), ROT)


static func scent_at(day: float, pos: Vector3) -> float:
	return sample(local_phase(day, pos), SCENT)


static func burn_at(day: float, pos: Vector3) -> float:
	return sample(local_phase(day, pos), BURN)


static func gather_at(day: float, pos: Vector3) -> float:
	return sample(local_phase(day, pos), GATHER)


static func base_c_at(day: float, pos: Vector3) -> float:
	## The season's contribution to the air temperature HERE — `Exposure`'s
	## own table, read on this place's calendar. Note this is the season term
	## only: `Exposure.lapse_c` still owns what altitude does to the air on
	## the day, and this owns what altitude does to the YEAR.
	return sample(local_phase(day, pos), BASE_C)


static func meadow_at(day: float, pos: Vector3) -> Color:
	return sample_color(local_phase(day, pos), MEADOW)


static func snow_cover(day: float, pos: Vector3) -> float:
	## 0 bare to 1 covered, on the grass shader's own window.
	var p := fposmod(local_phase(day, pos), 1.0)
	return smoothstep(SNOW_IN, 0.90, p) * (1.0 - smoothstep(SNOW_OUT, 1.0, p))


# ===========================================================================
#  Readout
# ===========================================================================

static func readout(day: float, pos: Vector3) -> Dictionary:
	## Everything this file knows about one point on one day. Read-only; no
	## key binding, no event hook, nothing to press.
	var lp := local_phase(day, pos)
	return {
		"day": day,
		"calendar": NAMES[index(day)],
		"local": NAMES[index_of_phase(lp)],
		"phase": phase(day),
		"local_phase": lp,
		"drift_days": local_day(day, pos) - day,
		"lat_u": lat_u(pos),
		"alt_u": alt_u(pos),
		"coast_u": coast_u(pos),
		"warp": warp_at(pos),
		"lag": lag_at(pos),
		"snow": snow_cover(day, pos),
		"rot": rot_at(day, pos),
		"base_c": base_c_at(day, pos),
	}
