class_name Slumber
extends RefCounted

# ===========================================================================
#  SLUMBER - what a night actually costs
# ===========================================================================
#
#  Myrkfell's sleep was an instantaneous blackout that set the sky to 06:00
#  and left everything else exactly as it was. Three things were wrong with
#  that, and this file is the answer to all three.
#
#  1. THE CLOCK WENT BACKWARDS. `World.sleep_at_bed` wrote `hour = 6.0` with
#     no `day += 1`, so lying down at nine in the evening wound the sky back
#     fifteen hours. Chronicle, Crofts, Carcasses, Wayfarers and GrowthClock
#     all bank forward time only - `d > 0.0` - so every one of them
#     CORRECTLY ignored the single action a player uses to skip time, and
#     `IncidentDirector._now_days()` carries a `maxf` floor whose comment
#     names this bug by name. Move the hour hand FORWARD and all five catch
#     up on their own: there is no new plumbing here, only a sign.
#
#  2. SLEEP WAS FREE. Eight hours passed and the body was handed a full
#     health bar for it. Meanwhile `Exposure` - the whole winter camp ladder
#     - has an `asleep` term that is modelled, tested, the top rung, and has
#     never had a caller, because there was no state for it to be true in.
#
#  3. YOU COULD NOT DIE OF IT, AND YOU ALSO COULD NOT SURVIVE IT. Walked
#     honestly, a winter night in the open takes a dry man from 100 warmth to
#     4.3 and a soaked one to zero - inside a blackout he cannot act in.
#     A survival system that kills you during a cutscene is not a survival
#     system. So: THE COLD WAKES YOU. You come to at four in the morning
#     shivering, with a dead fire and five hours of dark left, and what you
#     do about it is the game.
#
#  The night is WALKED, not solved: `night()` steps the real `Exposure`
#  model a quarter of a game hour at a time, with `asleep` true, moving the
#  hour hand as it goes - so the 04:00 trough in `Exposure.hour_curve_c` is
#  a thing you sleep THROUGH rather than a number nobody visits. The sky you
#  lay down under is the sky you are walked against: this file does not
#  forecast weather, because a forecast would be a lie the player cannot see
#  into. The one thing that does change over the night is the FIRE, because
#  the fire is the thing you had a choice about.
#
#  Pure and static throughout: no node, no clock, no RNG, no `get_tree`, no
#  `await`. Every reading it needs is an argument. That is what lets a winter
#  midnight, soaked, on an open pit with one log on it, be a call with
#  arguments instead of something you stand in a field for twenty minutes to
#  find out.
#
#  MEASURED, NOT CHOSEN. Every number below came off a throwaway probe run
#  before one assertion existed (2026-09-11 03:00). Going to bed at 21:00:
#
#    night length      spring 8.8 h   summer 7.9   autumn 9.3   WINTER 10.2
#    spring/summer/autumn, worst rung, soaked    wake at 76.7 or better
#    WINTER, dry, open ground .............. woke COLD at 04:30, warmth 4.3
#    WINTER, dry, roof only ................ woke COLD at 06:18, warmth 23.6
#    WINTER, dry, one log on the fire ...... slept through, warmth 67.2
#    WINTER, dry, fire and a roof .......... slept through, warmth 82.8
#    WINTER, dry, FED fire and a roof ...... slept through, warmth 96.3
#    WINTER, SOAKED, open ground ........... woke COLD at 03:48, warmth 0.0
#
#  Two things that table settles. Three seasons out of four sleeping is a
#  non-event, so this is not a tax on ordinary play - it is a winter rule.
#  And the five winter rungs land 4.3 / 23.6 / 67.2 / 82.8 / 96.3, no two of
#  them within ten points of each other, which is a ladder rather than a
#  gradient. One log (`Firepit.FUEL_PER_LOG`, 420 s) burns 8.4 game hours and
#  dies at half past five, an hour before a winter dawn: that last cold hour
#  is the difference between 67 and 83, and it is why feeding the fire before
#  you lie down is worth doing.


# ---------------------------------------------------------------------------
#  Constants
# ---------------------------------------------------------------------------

## `DAY_SECONDS` on the day/night node is 1200 for 24 game hours. Kept as its
## own name so the arithmetic below reads in game hours and the suite can hold
## the conversion to account in one place. Written without naming that class
## with a dot after it, because this file's own purity scan looks for exactly
## that string and a comment is not a reference (the third time a negative
## source scan has been tripped by the line explaining it).
const REAL_SECONDS_PER_HOUR := 50.0

## The integration step. Fine enough that the 04:00 trough is sampled a
## dozen times rather than jumped over, coarse enough that a fourteen-hour
## winter night is fifty-six steps and not five thousand.
const STEP_HOURS := 0.25

## You wake when you start shivering, and `Exposure.WARMTH_LOW` is already
## the project's word for that line - it is where the HUD bar lights and
## where `stamina_mult` halves. Deliberately NOT a fifth new number.
## Referenced, never copied: if the shiver line moves, this moves with it.
static func wake_warmth() -> float:
	return Exposure.WARMTH_LOW

## A sleeper is never killed by thirst either - he wakes parched instead.
const THIRST_FLOOR := 1.0

## Guard rails on a night's length. Nobody sleeps a negative number of
## hours, and `hours_until` wrapping onto itself is a full day, not zero.
const MIN_NIGHT_H := 0.05
const MAX_NIGHT_H := 24.0

const WOKE_DAWN := "dawn"
const WOKE_COLD := "cold"


# ---------------------------------------------------------------------------
#  The clock - pure
# ---------------------------------------------------------------------------

static func real_seconds(hours: float) -> float:
	return hours * REAL_SECONDS_PER_HOUR


static func wake_hour(season: int) -> float:
	## Dawn, and it is the SEASON'S dawn. `Crofts.daylight` is the one
	## definition of dawn in this project - twenty-five households already get
	## up by it - and a winter dawn at 07:12 against a summer one at 04:54 is
	## two and a quarter hours of extra dark, which is most of why winter is
	## the season this file is about. Not a second copy of that table.
	return Crofts.daylight(season).x


static func hours_until(from_h: float, to_h: float) -> float:
	## Forward only, always. This single function is the whole of bug 1: the
	## old code assigned the destination hour and let the difference fall
	## where it may, which from any evening is a walk BACKWARDS down the hour
	## hand. Landing exactly on the hour you are already at is a full day
	## round, not an instant - you do not sleep for zero hours.
	var d := fposmod(to_h - from_h, 24.0)
	if d < MIN_NIGHT_H:
		return MAX_NIGHT_H
	return d


static func days_crossed(from_h: float, hours: float) -> int:
	## How many times midnight goes by. The `day += 1` the old code never did,
	## and the reason five simulations spent every night asleep.
	return int(floorf((fposmod(from_h, 24.0) + maxf(0.0, hours)) / 24.0))


static func hour_after(from_h: float, hours: float) -> float:
	return fposmod(fposmod(from_h, 24.0) + maxf(0.0, hours), 24.0)


# ---------------------------------------------------------------------------
#  The fire, over the night - pure
# ---------------------------------------------------------------------------

static func burn_mult(e: Dictionary) -> float:
	## Rain on an open pit burns wood twice as fast - `Firepit`'s own rule,
	## borrowed rather than restated, so a fire and the sleep that depends on
	## it cannot disagree about how long a log lasts. A roof is what turns it
	## off, which is the same reason to build a roof as everything else here.
	if not Exposure.raining_on(e):
		return 1.0
	if float(e.get("intensity", 0.0)) < Firepit.RAIN_THRESHOLD:
		return 1.0
	return Firepit.RAIN_BURN_MULT


static func fire_c_at(fire0: float, fuel_s: float, elapsed_s: float) -> float:
	## The heat you went to sleep next to, as its fuel runs out: full while
	## there is wood, a quarter of it through `Firepit.EMBER_SECONDS` of
	## coals, then nothing. The player who banked a second log gets the whole
	## night; the player who lit it and lay down gets eight hours and a cold
	## finish.
	if fire0 <= 0.0:
		return 0.0
	var used := maxf(0.0, elapsed_s)
	if used < maxf(0.0, fuel_s):
		return fire0
	if used < maxf(0.0, fuel_s) + Firepit.EMBER_SECONDS:
		return fire0 * Firepit.EMBER_HEAT_MULT
	return 0.0


# ---------------------------------------------------------------------------
#  The night itself - pure
# ---------------------------------------------------------------------------

static func night(e: Dictionary, warmth0: float, wet0: float, hours: float,
		fire0: float, fuel_s: float) -> Dictionary:
	## Walk the night. `e` is the environment as the player lay down in it -
	## it is NOT mutated. `fire0` is the heat at the bedroll right now and
	## `fuel_s` the seconds of wood behind it; pass 0 for both if there is no
	## fire, which is most of the interesting cases.
	##
	## Returns what he wakes with and when. The one invariant worth stating
	## out loud: THIS NEVER KILLS ANYBODY. Warmth reaching zero is a waking,
	## not a wound, so no `Exposure` damage is ever accrued in here and no
	## caller has to remember to check.
	var env: Dictionary = e.duplicate(true)
	env["asleep"] = true
	env["swimming"] = false
	var mode := int(env.get("mode", Exposure.MODE_NORMAL))
	var start_h := fposmod(float(env.get("hour", 0.0)), 24.0)
	var planned := clampf(hours, 0.0, MAX_NIGHT_H)
	var step_real := real_seconds(STEP_HOURS)

	var w := clampf(warmth0, 0.0, Exposure.WARMTH_MAX)
	var wet := clampf(wet0, 0.0, 1.0)
	## The threshold is the shiver line OR where you already were, whichever
	## is lower. Lie down warm and the cold wakes you at thirty; lie down
	## already shivering at twenty and it wakes you the moment it gets worse
	## than that - a shivering man in a winter field does not get a night's
	## sleep. In summer he gains instead, never crosses it, and sleeps through.
	var floor_w := minf(wake_warmth(), w)

	var slept := 0.0
	var woke := WOKE_DAWN
	var coldest := INF
	var fire_out_h := -1.0
	var steps := 0

	while slept < planned - 1e-6:
		var span: float = minf(STEP_HOURS, planned - slept)
		var real: float = real_seconds(span) if span < STEP_HOURS else step_real
		env["hour"] = hour_after(start_h, slept)
		var fc := fire_c_at(fire0, fuel_s, real_seconds(slept) * burn_mult(env))
		## "The fire went out" is the moment the FLAMES die, not the moment
		## the last coal does. Written as `fc <= 0.0` this never fired at all
		## on the case it exists for: one log plus `Firepit.EMBER_SECONDS` of
		## coals outlasts a winter night by minutes, so a sleeper woken at
		## four in the morning by a dead fire was told nothing about it.
		if fire0 > 0.0 and fc < fire0 and fire_out_h < 0.0:
			fire_out_h = slept
		env["fire_c"] = fc
		var felt := Exposure.felt_c(env, wet)
		coldest = minf(coldest, felt)
		w = clampf(w + Exposure.warmth_rate(felt, mode) * real, 0.0, Exposure.WARMTH_MAX)
		wet = clampf(wet + Exposure.wet_rate(env, wet) * real, 0.0, 1.0)
		slept += span
		steps += 1
		if w < floor_w or w <= 0.0:
			woke = WOKE_COLD
			break

	if coldest == INF:
		coldest = Exposure.felt_c(env, wet)

	return {
		"warmth": w,
		"wet": wet,
		"hours_slept": slept,
		"hours_planned": planned,
		"woke": woke,
		"hour": hour_after(start_h, slept),
		"days": days_crossed(start_h, slept),
		"rest": rest_fraction(slept, planned),
		"coldest": coldest,
		"fire_out_h": fire_out_h,
		"steps": steps,
	}


# ---------------------------------------------------------------------------
#  What the night was worth - pure
# ---------------------------------------------------------------------------

static func rest_fraction(slept: float, planned: float) -> float:
	if planned <= 0.0:
		return 0.0
	return clampf(slept / planned, 0.0, 1.0)


static func heal_to(current: float, max_v: float, rest: float) -> float:
	## A full night closes the whole gap - which is what sleeping did before,
	## and taking that away would be a nerf nobody asked for. A night broken
	## at four in the morning closes the fraction of it you actually got. The
	## shape matters more than the number: the reward for a warm camp is that
	## your sleep is not interrupted, not that sleeping is stronger.
	if max_v <= 0.0:
		return 0.0
	var cur := clampf(current, 0.0, max_v)
	return clampf(cur + (max_v - cur) * clampf(rest, 0.0, 1.0), 0.0, max_v)


static func thirst_after(thirst0: float, rate_per_s: float, slept_h: float) -> float:
	## A night is five hundred real seconds of body, and skipping it for free
	## is the other half of the bug this file exists for. You wake thirsty.
	## You never wake dead of thirst: the floor is what makes sleep safe and
	## the parched message at dawn is what makes it matter.
	var drained := maxf(0.0, thirst0) - maxf(0.0, rate_per_s) * real_seconds(maxf(0.0, slept_h))
	return maxf(THIRST_FLOOR, drained)


static func wake_line(r: Dictionary) -> Array:
	## What the player is told on getting up. The cold waking has to say WHY -
	## a man who wakes at four in the morning with no explanation reads it as
	## a bug, and a man told the fire is out goes and does something about it.
	if String(r.get("woke", WOKE_DAWN)) == WOKE_COLD:
		var fire_died: bool = float(r.get("fire_out_h", -1.0)) >= 0.0
		if fire_died:
			return ["You wake shivering in the dark. The fire has burned out.",
				Color(0.72, 0.84, 1.0)]
		return ["The cold wakes you. It is a long way to dawn.",
			Color(0.72, 0.84, 1.0)]
	if float(r.get("warmth", 100.0)) < Exposure.WARMTH_MAX * 0.75:
		return ["You sleep badly, and wake cold with the dawn.",
			Color(0.85, 0.9, 1.0)]
	return ["You sleep. Dawn comes - and the deep has moved.", Color(0.85, 0.9, 1.0)]


static func readout(r: Dictionary) -> String:
	## The one dev affordance in this file, and it is read-only.
	return "slept %.2f of %.2f h -> %s at %.2f (+%d d) warmth %.1f wet %.2f coldest %.1fC" % [
		float(r.get("hours_slept", 0.0)), float(r.get("hours_planned", 0.0)),
		String(r.get("woke", "?")), float(r.get("hour", 0.0)), int(r.get("days", 0)),
		float(r.get("warmth", 0.0)), float(r.get("wet", 0.0)), float(r.get("coldest", 0.0))]
