#!/usr/bin/env python3
"""Mutation sweep for Seasons (2026-09-11 09:00 ET, WORLD & LIFE).

    python3 tools/mutate_seasons.py

A green suite is evidence about the SUITE, not about the source. This
reintroduces, one at a time, each bug `Seasons` could plausibly have, and
demands that SeasonsTests goes red for every one. A mutation that SURVIVES is
naming an assertion that does not exist -- or, three times in this project's
history, naming dead code that should simply be deleted.

⚠ A third of these deliberately live in OTHER PEOPLE'S FILES. `Seasons` is
read by `Crofts`, `Carcasses` and `World`, and a suite that only mutates its
own source proves nothing about whether those three still call it correctly.
The first draft of this round shipped `season_here` calling
`Seasons.local_index` directly, which cut the Chronicle out of the calendar;
mutations 24 and 27 are the standing guard against that coming back.
"""

import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = "/Applications/Godot.app/Contents/MacOS/Godot"
SUITE = "res://tests/SeasonsTests.gd"

S = "scripts/Seasons.gd"
C = "scripts/Crofts.gd"
A = "scripts/Carcasses.gd"
W = "scripts/World.gd"
G = "scripts/Grass.gd"

# (label, file, old, new)  -- each `old` must occur EXACTLY ONCE.
MUTATIONS = [
    # ---- the warp's three geographic terms, each removed on its own
    ("lat term removed", S, "const LAT_WARP := 0.060", "const LAT_WARP := 0.000"),
    ("alt term removed", S, "const ALT_WARP := 0.035", "const ALT_WARP := 0.000"),
    ("sea mildness removed", S, "const SEA_WARP := 0.030", "const SEA_WARP := 0.000"),
    ("sea lag removed", S, "const SEA_LAG := 0.022", "const SEA_LAG := 0.000"),
    ("lat term halved", S, "const LAT_WARP := 0.060", "const LAT_WARP := 0.030"),
    ("alt term doubled", S, "const ALT_WARP := 0.035", "const ALT_WARP := 0.070"),

    # ---- the warp's shape
    ("warp sign flipped", S,
     "return lagged + warp_at(pos) * sin(TAU * (q - MIDSUMMER_PHASE)) * DAYS_PER_YEAR",
     "return lagged - warp_at(pos) * sin(TAU * (q - MIDSUMMER_PHASE)) * DAYS_PER_YEAR"),
    ("fixed point moved to the equinox", S,
     "const MIDSUMMER_PHASE := 0.375", "const MIDSUMMER_PHASE := 0.250"),
    ("warp is a plain offset, not a warp", S,
     "return lagged + warp_at(pos) * sin(TAU * (q - MIDSUMMER_PHASE)) * DAYS_PER_YEAR",
     "return lagged + warp_at(pos) * DAYS_PER_YEAR"),
    ("warp uses cos, so the fixed points move", S,
     "sin(TAU * (q - MIDSUMMER_PHASE))", "cos(TAU * (q - MIDSUMMER_PHASE))"),
    ("lag applied forwards", S,
     "var lagged := day - lag_at(pos) * DAYS_PER_YEAR",
     "var lagged := day + lag_at(pos) * DAYS_PER_YEAR"),
    ("warp_days answers zero", S,
     "return local_day(day, pos) - day", "return 0.0"),
    ("monotonicity clamp opened past the limit", S,
     "const WARP_LIMIT := 0.140", "const WARP_LIMIT := 0.400"),

    # ---- geography
    ("latitude runs the wrong way", S,
     "return clampf((SOUTH_Z - pos.z) / (SOUTH_Z - NORTH_Z), 0.0, 1.0)",
     "return clampf((pos.z - SOUTH_Z) / (SOUTH_Z - NORTH_Z), 0.0, 1.0)"),
    ("altitude never reaches 1", S,
     "const ALT_FULL_Y := 900.0", "const ALT_FULL_Y := 90000.0"),
    ("negative altitude counts", S,
     "return clampf(pos.y / ALT_FULL_Y, 0.0, 1.0)",
     "return clampf(pos.y / ALT_FULL_Y, -1.0, 1.0)"),
    ("the open sea reads as inland", S, "\tif seaward:\n\t\treturn 1.0",
     "\tif seaward and false:\n\t\treturn 1.0"),
    ("the coast band is a hairline", S,
     "const COAST_REACH_M := 1100.0", "const COAST_REACH_M := 10.0"),
    ("the coast band reaches the whole map", S,
     "const COAST_REACH_M := 1100.0", "const COAST_REACH_M := 9000.0"),

    # ---- the continuous table
    ("the turn starts at once (no hold)", S,
     "const TURN_START := 0.55", "const TURN_START := 0.00"),
    ("the season never turns at all", S,
     "\treturn lerpf(a, b, turn_f(p))", "\treturn a"),
    ("the colour never turns", S,
     "\treturn a.lerp(b, turn_f(p))", "\treturn a"),
    ("sample reads the NEXT anchor", S,
     "\tvar a := float(anchors[i % 4])", "\tvar a := float(anchors[(i + 1) % 4])"),

    # ---- the anchors themselves (must disagree with their source file)
    ("rot anchor drifts from Carcasses", S,
     "const ROT: Array[float] = [1.00, 1.85, 0.80, 0.22]",
     "const ROT: Array[float] = [1.00, 1.50, 0.80, 0.22]"),
    ("scent anchor drifts from Carcasses", S,
     "const SCENT: Array[float] = [1.00, 1.25, 1.00, 0.55]",
     "const SCENT: Array[float] = [1.00, 1.25, 1.00, 0.75]"),
    ("burn anchor drifts from Crofts", S,
     "const BURN: Array[float] = [1.00, 0.55, 1.15, 1.60]",
     "const BURN: Array[float] = [1.00, 0.55, 1.15, 1.20]"),
    ("gather anchor drifts from Crofts", S,
     "const GATHER: Array[float] = [1.65, 0.75, 1.55, 0.85]",
     "const GATHER: Array[float] = [1.65, 0.75, 1.55, 1.05]"),
    ("base_c anchor drifts from Exposure", S,
     "const BASE_C: Array[float] = [10.0, 18.0, 8.0, -4.0]",
     "const BASE_C: Array[float] = [10.0, 18.0, 8.0, -2.0]"),
    ("meadow winter drifts from Grass", S,
     "\tColor(0.40, 0.36, 0.24),", "\tColor(0.44, 0.36, 0.24),"),

    # ---- snow
    ("snow opens too early", S, "const SNOW_IN := 0.74", "const SNOW_IN := 0.30"),
    ("snow never closes", S,
     "\treturn smoothstep(SNOW_IN, 0.90, p) * (1.0 - smoothstep(SNOW_OUT, 1.0, p))",
     "\treturn smoothstep(SNOW_IN, 0.90, p)"),

    # ---- the calendar
    ("a season is 20 days", S, "const DAYS_PER_SEASON := 24.0",
     "const DAYS_PER_SEASON := 20.0"),
    ("phase breaks on negative days", S,
     "\treturn fposmod(day, DAYS_PER_YEAR) / DAYS_PER_YEAR",
     "\treturn fmod(day, DAYS_PER_YEAR) / DAYS_PER_YEAR"),
    ("the year has three seasons", S,
     "\treturn int(fposmod(p, 1.0) * 4.0) % 4", "\treturn int(fposmod(p, 1.0) * 3.0) % 4"),

    # ---- THE COLLABORATORS. A stub is not the collaborator, and a file that
    #      only CALLS somebody else's method still depends on the call site.
    ("Crofts stops asking where it is", C,
     "\treturn season_at(t + Seasons.warp_days(t, Vector3(p.x, 0.0, p.y)))",
     "\treturn season_at(t)"),
    ("Crofts cuts the Chronicle out of the calendar", C,
     "\treturn season_at(t + Seasons.warp_days(t, Vector3(p.x, 0.0, p.y)))",
     "\treturn Seasons.local_index(t, Vector3(p.x, 0.0, p.y))"),
    ("every croft stands at the origin", C,
     "\tvar p: Vector2 = c.get(\"pos\", Vector2.ZERO)",
     "\tvar p: Vector2 = Vector2.ZERO"),
    ("crofts all share one season again", C,
     "\t\t_step_croft(c as Dictionary, t, sky, season_here(t, c as Dictionary))",
     "\t\t_step_croft(c as Dictionary, t, sky, season)"),
    ("Carcasses stops asking where the body is", A,
     "\treturn season_at(t + Seasons.warp_days(t, at))", "\treturn season_at(t)"),
    ("Carcasses cuts the Chronicle out of the calendar", A,
     "\treturn season_at(t + Seasons.warp_days(t, at))",
     "\treturn Seasons.local_index(t, at)"),
    ("every carcass lies at the origin", A,
     "\tvar at: Vector3 = rec.get(\"at\", Vector3.ZERO)",
     "\tvar at: Vector3 = Vector3.ZERO"),
    ("carcasses all share one season again", A,
     "\t\tif _step_rec(rec, t, hour, sky, season_here(t, rec)):",
     "\t\tif _step_rec(rec, t, hour, sky, season):"),

    # ---- the wiring
    ("World publishes the calendar phase again", W,
     "\tvar p := Seasons.local_phase(_daynight.day, _player.global_position)",
     "\tvar p := Seasons.phase(_daynight.day)"),
    ("World stops feeding the season per frame", W,
     "\t_feed_local_season()\n", "\tpass  # _feed_local_season()\n"),
    ("World stops updating Wind.phase", W, "\tWind.phase = p\n", "\n"),
    ("World stops publishing to the shaders", W,
     "\tRenderingServer.global_shader_parameter_set(\"season_phase\", p)", "\tpass"),
]


def run_suite():
    r = subprocess.run([GODOT, "--headless", "--path", ROOT, "--script", SUITE],
                       capture_output=True, text=True, timeout=180)
    out = (r.stdout or "") + (r.stderr or "")
    return ("ALL GREEN" in out), out


def main():
    if not os.path.exists(GODOT):
        print("no Godot at " + GODOT)
        return 2

    print("baseline ...")
    green, out = run_suite()
    if not green:
        print("BASELINE IS NOT GREEN -- fix that first")
        print(out[-2500:])
        return 2
    n = re.search(r"ALL GREEN -- (\d+)", out)
    print("baseline green, %s assertions\n" % (n.group(1) if n else "?"))

    caught, survived, bad = 0, [], []
    for i, (label, rel, old, new) in enumerate(MUTATIONS, 1):
        path = os.path.join(ROOT, rel)
        src = open(path, encoding="utf-8").read()
        hits = src.count(old)
        if hits != 1:
            # ⚠ A BAD ANCHOR IS NOT A CAUGHT MUTATION. A pattern that matches
            # zero times mutates nothing and the suite stays green, which
            # reads exactly like a survivor; one that matches twice mutates
            # more than intended. Both are reported apart from the result.
            bad.append("%2d %-52s anchor matched %d times in %s" % (i, label, hits, rel))
            print("%2d/%d  ANCHOR  %s" % (i, len(MUTATIONS), label))
            continue
        shutil.copy2(path, path + ".mutbak")
        try:
            open(path, "w", encoding="utf-8").write(src.replace(old, new, 1))
            green, _ = run_suite()
            if green:
                survived.append("%2d %s  [%s]" % (i, label, rel))
                print("%2d/%d  SURVIVED  %s" % (i, len(MUTATIONS), label))
            else:
                caught += 1
                print("%2d/%d  caught    %s" % (i, len(MUTATIONS), label))
        finally:
            shutil.move(path + ".mutbak", path)

    print("\n%d caught, %d survived, %d bad anchors, of %d"
          % (caught, len(survived), len(bad), len(MUTATIONS)))
    for s in survived:
        print("  SURVIVED  " + s)
    for b in bad:
        print("  BAD ANCHOR  " + b)

    green, out = run_suite()
    print("\nrestored baseline green: %s" % green)
    return 0 if (not survived and not bad and green) else 1


if __name__ == "__main__":
    sys.exit(main())
