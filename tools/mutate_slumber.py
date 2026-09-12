#!/usr/bin/env python3
"""mutate_slumber.py -- prove SlumberTests can actually fail.

A green suite is evidence about the SUITE, not only about the source. Each
mutation below reintroduces a defect the round either fixed or claims to
prevent; the suite must go red for every one. A survivor is never "fine" -- it
is either a missing assertion, a redundancy worth naming, or dead code worth
deleting.

Fourteen of the mutations live in somebody else's file (Exposure, Firepit,
Crofts). That is deliberate: Slumber adds no public method to any of them and
calls nine, so their front-door sections exist precisely to notice when one of
those nine changes under it.

    python3 tools/mutate_slumber.py
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
GODOT = "/Applications/Godot.app/Contents/MacOS/Godot"
SUITE = "res://tests/SlumberTests.gd"

S = "scripts/Slumber.gd"
E = "scripts/Exposure.gd"
F = "scripts/Firepit.gd"
C = "scripts/Crofts.gd"

# (name, file, old, new)
MUTATIONS = [
    # ---- the clock: the bug this whole file exists for
    ("clock-backwards", S, "\tvar d := fposmod(to_h - from_h, 24.0)",
     "\tvar d := fposmod(from_h - to_h, 24.0)"),
    ("clock-zero-night", S, "\tif d < MIN_NIGHT_H:\n\t\treturn MAX_NIGHT_H",
     "\tif d < MIN_NIGHT_H:\n\t\treturn 0.0"),
    ("clock-no-day", S,
     "\treturn int(floorf((fposmod(from_h, 24.0) + maxf(0.0, hours)) / 24.0))",
     "\treturn 0"),
    ("clock-no-wrap", S,
     "\treturn fposmod(fposmod(from_h, 24.0) + maxf(0.0, hours), 24.0)",
     "\treturn fposmod(from_h, 24.0) + maxf(0.0, hours)"),
    ("clock-real-seconds", S, "\treturn hours * REAL_SECONDS_PER_HOUR",
     "\treturn hours * 1.0"),
    ("clock-day-length", S, "const REAL_SECONDS_PER_HOUR := 50.0",
     "const REAL_SECONDS_PER_HOUR := 25.0"),

    # ---- dawn
    ("dawn-hardcoded-six", S, "\treturn Crofts.daylight(season).x", "\treturn 6.0"),
    ("dawn-is-dusk", S, "\treturn Crofts.daylight(season).x",
     "\treturn Crofts.daylight(season).y"),

    # ---- the fire over the night
    ("fire-no-embers", S,
     "\tif used < maxf(0.0, fuel_s) + Firepit.EMBER_SECONDS:\n\t\treturn fire0 * Firepit.EMBER_HEAT_MULT",
     "\tif used < maxf(0.0, fuel_s) + Firepit.EMBER_SECONDS:\n\t\treturn 0.0"),
    ("fire-never-dies", S, "\tif used < maxf(0.0, fuel_s):\n\t\treturn fire0",
     "\tif used < maxf(0.0, fuel_s) * 1000.0:\n\t\treturn fire0"),
    ("fire-embers-full-heat", S, "\t\treturn fire0 * Firepit.EMBER_HEAT_MULT",
     "\t\treturn fire0"),
    ("rain-no-penalty", S, "\treturn Firepit.RAIN_BURN_MULT", "\treturn 1.0"),
    ("rain-ignores-roof", S, "\tif not Exposure.raining_on(e):\n\t\treturn 1.0",
     "\tif false:\n\t\treturn 1.0"),
    ("rain-no-threshold", S,
     "\tif float(e.get(\"intensity\", 0.0)) < Firepit.RAIN_THRESHOLD:\n\t\treturn 1.0",
     "\tif false:\n\t\treturn 1.0"),

    # ---- the night itself
    ("night-not-asleep", S, "\tenv[\"asleep\"] = true", "\tenv[\"asleep\"] = false"),
    ("night-never-wakes", S, "\tvar floor_w := minf(wake_warmth(), w)",
     "\tvar floor_w := -1.0"),
    ("night-fixed-threshold", S, "\tvar floor_w := minf(wake_warmth(), w)",
     "\tvar floor_w := wake_warmth()"),
    ("night-sleeps-through-zero", S, "\t\tif w < floor_w or w <= 0.0:",
     "\t\tif w < floor_w:"),
    ("night-hour-frozen", S, "\t\tenv[\"hour\"] = hour_after(start_h, slept)",
     "\t\tenv[\"hour\"] = start_h"),
    ("night-rain-not-applied", S,
     "\t\tvar fc := fire_c_at(fire0, fuel_s, real_seconds(slept) * burn_mult(env))",
     "\t\tvar fc := fire_c_at(fire0, fuel_s, real_seconds(slept))"),
    ("night-never-dries", S,
     "\t\twet = clampf(wet + Exposure.wet_rate(env, wet) * real, 0.0, 1.0)",
     "\t\twet = clampf(wet, 0.0, 1.0)"),
    ("night-coldest-is-last", S, "\t\tcoldest = minf(coldest, felt)", "\t\tcoldest = felt"),
    ("night-mutates-caller", S, "\tvar env: Dictionary = e.duplicate(true)",
     "\tvar env: Dictionary = e"),
    ("night-fire-out-late", S, "\t\tif fire0 > 0.0 and fc < fire0 and fire_out_h < 0.0:",
     "\t\tif fire0 > 0.0 and fc <= 0.0 and fire_out_h < 0.0:"),
    ("night-mode-ignored", S,
     "\t\tw = clampf(w + Exposure.warmth_rate(felt, mode) * real, 0.0, Exposure.WARMTH_MAX)",
     "\t\tw = clampf(w + Exposure.warmth_rate(felt, Exposure.MODE_PEACEFUL) * real, 0.0, Exposure.WARMTH_MAX)"),
    ("night-no-clamp", S,
     "\t\tw = clampf(w + Exposure.warmth_rate(felt, mode) * real, 0.0, Exposure.WARMTH_MAX)",
     "\t\tw = w + Exposure.warmth_rate(felt, mode) * real"),
    ("night-step-too-coarse", S, "const STEP_HOURS := 0.25", "const STEP_HOURS := 4.0"),

    # ---- what the night was worth
    ("rest-always-full", S, "\treturn clampf(slept / planned, 0.0, 1.0)", "\treturn 1.0"),
    ("heal-always-full", S,
     "\treturn clampf(cur + (max_v - cur) * clampf(rest, 0.0, 1.0), 0.0, max_v)",
     "\treturn max_v"),
    ("heal-ignores-rest", S,
     "\treturn clampf(cur + (max_v - cur) * clampf(rest, 0.0, 1.0), 0.0, max_v)",
     "\treturn clampf(cur + (max_v - cur), 0.0, max_v)"),
    ("thirst-free-night", S,
     "\treturn maxf(THIRST_FLOOR, drained)", "\treturn maxf(THIRST_FLOOR, thirst0)"),
    ("thirst-no-floor", S, "\treturn maxf(THIRST_FLOOR, drained)", "\treturn drained"),
    ("thirst-floor-zero", S, "const THIRST_FLOOR := 1.0", "const THIRST_FLOOR := 0.0"),

    # ---- what the player is told
    ("line-no-fire-reason", S,
     "\t\tif fire_died:", "\t\tif false:"),
    ("line-no-cold-dawn", S,
     "\tif float(r.get(\"warmth\", 100.0)) < Exposure.WARMTH_MAX * 0.75:",
     "\tif false:"),

    # ---- the collaborators, whose front doors get their own sections
    ("exp-bed-worthless", E, "const BED_C := 6.0", "const BED_C := 0.0"),
    ("exp-shiver-line-zero", E, "const WARMTH_LOW := 30.0", "const WARMTH_LOW := 0.0"),
    ("exp-no-bed-term", E, "\tif bool(e.get(\"asleep\", false)):\n\t\tf += BED_C",
     "\tif bool(e.get(\"asleep\", false)):\n\t\tf += 0.0"),
    ("exp-no-hardcore-tax", E,
     "\treturn -((WARMTH_NEUTRAL_C - felt) * WARMTH_PER_DEGREE_S * drain_mult_for(mode))",
     "\treturn -((WARMTH_NEUTRAL_C - felt) * WARMTH_PER_DEGREE_S)"),
    ("exp-rain-through-roof", E, "\tif is_sheltered(e):\n\t\treturn false",
     "\tif false:\n\t\treturn false"),
    ("exp-never-dries", E, "\treturn -dry", "\treturn 0.0"),
    ("fire-rain-mult-one", F, "const RAIN_BURN_MULT := 2.0", "const RAIN_BURN_MULT := 1.0"),
    ("fire-ember-mult-one", F, "const EMBER_HEAT_MULT := 0.25", "const EMBER_HEAT_MULT := 0.99"),
    ("fire-no-ember-seconds", F, "const EMBER_SECONDS := 90.0", "const EMBER_SECONDS := 0.0"),
    ("fire-log-lasts-forever", F, "const FUEL_PER_LOG := 420.0", "const FUEL_PER_LOG := 4200.0"),
    ("crofts-winter-is-summer", C, "\treturn Vector2(7.20, 16.60)",
     "\treturn Vector2(4.90, 20.60)"),
]


def run_suite():
    r = subprocess.run([GODOT, "--headless", "--path", str(ROOT), "--script", SUITE],
                       capture_output=True, text=True, timeout=180)
    return r.returncode != 0 or "FAIL" in r.stdout


def main():
    caught, survived, bad = [], [], []
    print("baseline ...", flush=True)
    if run_suite():
        print("BASELINE IS ALREADY RED -- fix that first")
        return 1
    print("baseline green\n", flush=True)
    for name, rel, old, new in MUTATIONS:
        path = ROOT / rel
        src = path.read_text(encoding="utf-8")
        n = src.count(old)
        if n != 1:
            bad.append("%s (anchor x%d in %s)" % (name, n, rel))
            print("  BAD   %s -- anchor matched %d times" % (name, n), flush=True)
            continue
        path.write_text(src.replace(old, new, 1), encoding="utf-8")
        try:
            red = run_suite()
        finally:
            path.write_text(src, encoding="utf-8")
        if red:
            caught.append(name)
            print("  caught    %s" % name, flush=True)
        else:
            survived.append(name)
            print("  SURVIVED  %s  <-- a missing test, a redundancy, or dead code" % name,
                  flush=True)
    print("\n%d/%d caught, %d survived, %d bad anchors"
          % (len(caught), len(MUTATIONS) - len(bad), len(survived), len(bad)))
    for s in survived:
        print("  SURVIVED: %s" % s)
    for b in bad:
        print("  BAD ANCHOR: %s" % b)
    return 0


if __name__ == "__main__":
    sys.exit(main())
