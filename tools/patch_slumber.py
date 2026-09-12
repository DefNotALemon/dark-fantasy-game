#!/usr/bin/env python3
"""patch_slumber.py -- wire Slumber into World.gd and Player.gd.

2026-09-11 03:00 ET, SYSTEMS DEPTH. Six hunks, every one guarded on what it
DEFINES (never on a call it also writes -- the 2026-09-05 bug), idempotent, and
a no-op on a second run. Purely additive except the two lines it must replace:
`World.sleep_at_bed`'s backwards clock and `_sleep_poll`'s unconditional heal.

    python3 tools/patch_slumber.py [--dry]

Back up scripts/Player.gd and scripts/World.gd before running this and diff
afterwards. Expect +n / -3. Any other removed line is a stop-everything.
"""
import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
DRY = "--dry" in sys.argv


def load(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def save(rel, text):
    if DRY:
        return
    (ROOT / rel).write_text(text, encoding="utf-8")


report = []


def hunk(name, src, guard, anchor, new, count=1):
    """Guard on what the hunk DEFINES. Anchor must match exactly `count` times."""
    if guard in src:
        report.append("  skip  %-22s (already present)" % name)
        return src, 0
    n = src.count(anchor)
    if n != count:
        raise SystemExit("ANCHOR %s matched %d times, wanted %d" % (name, n, count))
    report.append("  ok    %-22s (anchor x%d)" % (name, n))
    return src.replace(anchor, new, count), 1


# =========================================================== World.gd

W = "scripts/World.gd"
w = load(W)
before_w = len(w.splitlines())

W_OLD = '''func sleep_at_bed() -> bool:
	## Sleep until dawn — and the earth USES the night: the whole underground
	## reseeds and re-carves (except the permanent caves around each mouth).
	## False if the previous build/shift is still running.
	if _region == null or not _region.reset_underground():
		return false
	if _daynight:
		_daynight.hour = 6.0  ## dawn
'''

W_NEW = '''func sleep_at_bed(hours: float = 8.0) -> bool:
	## Sleep until dawn — and the earth USES the night: the whole underground
	## reseeds and re-carves (except the permanent caves around each mouth).
	## False if the previous build/shift is still running.
	##
	## `hours` is how much of the night the sleeper actually GOT. The cold can
	## cut it short (see `Slumber`), and a man woken at four in the morning
	## wakes the world at four in the morning, not at dawn.
	if _region == null or not _region.reset_underground():
		return false
	if _daynight:
		## FORWARD, ALWAYS. This line used to read `hour = 6.0` with no day
		## increment, which from any evening walks the sky BACKWARDS — fifteen
		## hours, from nine at night. Chronicle, Crofts, Carcasses, Wayfarers
		## and GrowthClock every one bank FORWARD time only (`d > 0.0` in their
		## `_tick_clock`), so every one of them correctly ignored the single
		## action a player uses to skip time; `IncidentDirector._now_days()`
		## carries a `maxf` floor whose comment names this bug by name.
		## Turning the hand the right way is the entire fix: all five catch up
		## on their own, off their own clock reading, with no new plumbing.
		var slept := maxf(0.0, hours)
		var from_h := fposmod(float(_daynight.hour), 24.0)
		_daynight.day = _daynight.day + Slumber.days_crossed(from_h, slept)
		_daynight.hour = Slumber.hour_after(from_h, slept)
'''

w, _ = hunk("world.clock", w, "Slumber.hour_after(from_h, slept)", W_OLD, W_NEW)
save(W, w)


# ========================================================== Player.gd

P = "scripts/Player.gd"
p = load(P)
before_p = len(p.splitlines())

# --- 1. SYSTEMS #2: the out-of-combat regen outruns thirst, exactly as it
#        outran the cold until 4ac02b1. One line.
T_OLD = '''	if thirst <= 0.0 and invuln_timer <= 0.0 and health > 0.0:
		health = maxf(0.0, health - THIRST_DAMAGE_PER_S * delta)
		health_show = 1.0
'''
T_NEW = '''	if thirst <= 0.0 and invuln_timer <= 0.0 and health > 0.0:
		health = maxf(0.0, health - THIRST_DAMAGE_PER_S * delta)
		health_show = 1.0
		## THIRST IS A WOUND, NOT A STATUS — the same bug the cold had, in the
		## same shape, and it has been sitting here since the meter was
		## written. `_process`'s out-of-combat regen waits only on
		## `combat_timer`, and dying of thirst is not a combat action, so a man
		## at zero water healed faster than he bled and sat at full health for
		## ever. Fixed for warmth by 4ac02b1; this is the other half of it.
		combat_timer = 0.0
'''
p, _ = hunk("player.thirst_regen", p, "THIRST IS A WOUND", T_OLD, T_NEW)

# --- 2. the night the player is currently in the middle of
M_OLD = "var combat_timer := 99.0      ## time since last combat action\n"
M_NEW = ("var combat_timer := 99.0      ## time since last combat action\n"
         "## What the last `Slumber.night()` returned, held between the blackout\n"
         "## starting and the player getting up. Empty when nobody is asleep.\n"
         "var _slept: Dictionary = {}\n")
p, _ = hunk("player.slept_member", p, "var _slept: Dictionary", M_OLD, M_NEW)

# --- 3. the two new functions, in front of _sleep
F_ANCHOR = "func _sleep(_bed: Node3D) -> void:\n"
F_NEW = '''func _night_ahead() -> Dictionary:
	## Everything `Slumber` needs, read off the world at the moment the player
	## lies down. The sky is NOT forecast — you are walked against the weather
	## you went to bed in, because a forecast would be a lie you cannot see
	## into. The one thing that does change over the night is the FIRE, which
	## is the one thing you had a choice about, so its fuel comes along with
	## its heat.
	var e := _exposure_env()
	var season := int(e.get("season", 0))
	var hour := float(e.get("hour", 21.0))
	var planned := Slumber.hours_until(hour, Slumber.wake_hour(season))
	if god or not warmth_survival():
		## God mode pins the meter and Light mode has no meter to pin. The
		## night still PASSES — that is the bug being fixed — it just cannot
		## wake anybody.
		return {
			"warmth": exposure.warmth, "wet": exposure.wet,
			"hours_slept": planned, "hours_planned": planned,
			"woke": Slumber.WOKE_DAWN, "hour": Slumber.hour_after(hour, planned),
			"days": Slumber.days_crossed(hour, planned), "rest": 1.0,
			"coldest": 0.0, "fire_out_h": -1.0, "steps": 0,
		}
	var fire0 := float(e.get("fire_c", 0.0))
	var fuel := 0.0
	for f in get_tree().get_nodes_in_group("fires"):
		var pit := f as Node3D
		if pit == null or not ("fuel" in pit):
			continue
		if pit.global_position.distance_to(global_position) > Firepit.FIRE_RANGE:
			continue
		fuel = maxf(fuel, float(pit.get("fuel")))
	return Slumber.night(e, exposure.warmth, exposure.wet, planned, fire0, fuel)


func _apply_slept() -> void:
	## What the night was worth. A whole one closes the whole wound, exactly as
	## sleeping always did — taking that away would be a nerf nobody asked for
	## — and a night broken at four in the morning closes the fraction of it
	## you actually got. The reward for a warm camp is an UNINTERRUPTED night,
	## not a stronger one.
	var r: Dictionary = _slept
	var rest := clampf(float(r.get("rest", 1.0)), 0.0, 1.0)
	health = Slumber.heal_to(health, max_health, rest)
	stamina = Slumber.heal_to(stamina, max_stamina, rest)
	health_show = 2.0
	if not r.is_empty():
		exposure.warmth = clampf(float(r.get("warmth", exposure.warmth)),
				0.0, Exposure.WARMTH_MAX)
		exposure.wet = clampf(float(r.get("wet", exposure.wet)), 0.0, 1.0)
		warmth_show = 3.0
		if thirst_survival():
			thirst = Slumber.thirst_after(thirst, thirst_rate_per_sec(),
					float(r.get("hours_slept", 0.0)))
			thirst_show = 3.0
	var line: Array = Slumber.wake_line(r)
	_add_log_msg(String(line[0]), line[1] as Color)
	_slept = {}


'''
p, _ = hunk("player.night_funcs", p, "func _night_ahead", F_ANCHOR, F_NEW + F_ANCHOR)

# --- 4. the blackout walks the night before the clock moves
B_OLD = '''	var w := get_tree().get_first_node_in_group("world")
	if w == null or not bool(w.call("sleep_at_bed")):
'''
B_NEW = '''	var w := get_tree().get_first_node_in_group("world")
	if w == null:
		_sleep_rise()
		return
	## Walk the night BEFORE the clock moves, because how much of it you
	## actually get is what the clock is then moved BY. A man the cold wakes at
	## four in the morning wakes the world at four in the morning.
	_slept = _night_ahead()
	if not bool(w.call("sleep_at_bed", float(_slept.get("hours_slept", 0.0)))):
'''
p, _ = hunk("player.blackout", p, "_slept = _night_ahead()", B_OLD, B_NEW)

# the restless branch must forget the night it just walked
R_OLD = '''		_add_log_msg("Restless — the earth is still settling. Try again shortly.", Color(0.8, 0.8, 0.8))
		_sleep_rise()
'''
R_NEW = '''		_add_log_msg("Restless — the earth is still settling. Try again shortly.", Color(0.8, 0.8, 0.8))
		_slept = {}
		_sleep_rise()
'''
p, _ = hunk("player.restless", p, "_slept = {}\n\t\t_sleep_rise()", R_OLD, R_NEW)

# --- 5. waking up: the heal is the night's, and so is the line
POLL = re.compile(
    r'\thealth = max_health\n'
    r'\tstamina = max_stamina\n'
    r'\thealth_show = 2\.0\n'
    r'\t_add_log_msg\("You sleep\.[^\n]*\n'
    r'\t_sleep_rise\(\)')
if "\t_apply_slept()\n\t_sleep_rise()" in p:
    report.append("  skip  %-22s (already present)" % "player.wake")
else:
    found = POLL.findall(p)
    if len(found) != 1:
        raise SystemExit("ANCHOR player.wake matched %d times, wanted 1" % len(found))
    p = POLL.sub("\t_apply_slept()\n\t_sleep_rise()", p)
    report.append("  ok    %-22s (anchor x1)" % "player.wake")

save(P, p)

print("\n".join(report))
print("  World.gd  %d -> %d lines" % (before_w, len(w.splitlines())))
print("  Player.gd %d -> %d lines" % (before_p, len(p.splitlines())))
print("DRY RUN, nothing written" if DRY else "written")
