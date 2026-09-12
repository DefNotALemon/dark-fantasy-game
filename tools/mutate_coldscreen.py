#!/usr/bin/env python3
"""mutate_coldscreen.py -- prove ColdScreenTests can actually fail.

A green suite is evidence about the SUITE, not only about the source. Each
mutation reintroduces a defect the round either fixed or claims to prevent;
the suite must go red for every one. A survivor is never "fine" -- it is a
missing assertion, a redundancy worth naming, or dead code worth deleting.

Ten of these live in Exposure.gd rather than ColdScreen.gd. That is the point
of the `exposure` section: ColdScreen adds no public method to Exposure and
leans on six of its, plus both its warmth rungs, so half of what this suite
MEANS can be changed by somebody else tomorrow without touching a line of
ColdScreen.

Three of them are the defects the LIVE PASS found -- a world-space exhale, a
one-metre quad, and frost drawn from the wrong Worley distance. None was
visible from any pure function, and all three are now held by source
assertions so they cannot come back quietly.

    python3 tools/mutate_coldscreen.py
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
GODOT = "/Applications/Godot.app/Contents/MacOS/Godot"
SUITE = "res://tests/ColdScreenTests.gd"

C = "scripts/ColdScreen.gd"
E = "scripts/Exposure.gd"

# (name, file, old, new)
MUTATIONS = [
    # ---- breath is the AIR: the central claim
    ("breath-reads-felt", C, "\treturn Exposure.ambient_c(e)",
     "\treturn Exposure.felt_c(e, 0.0)"),
    ("breath-threshold-cold", C, "const BREATH_C := 7.0", "const BREATH_C := 2.0"),
    ("breath-threshold-warm", C, "const BREATH_C := 7.0", "const BREATH_C := 13.0"),
    ("breath-span-narrow", C, "const BREATH_SPAN_C := 9.0", "const BREATH_SPAN_C := 3.0"),
    ("breath-span-wide", C, "const BREATH_SPAN_C := 9.0", "const BREATH_SPAN_C := 24.0"),
    ("breath-no-floor", C, "\treturn 0.0 if a < BREATH_MIN else a", "\treturn a"),
    ("breath-floor-high", C, "const BREATH_MIN := 0.12", "const BREATH_MIN := 0.40"),
    ("breath-no-cap", C,
     "\tvar a := clampf((BREATH_C - amb) / BREATH_SPAN_C, 0.0, 1.0)",
     "\tvar a := maxf(0.0, (BREATH_C - amb) / BREATH_SPAN_C)"),

    # ---- breath is an EVENT
    ("breath-no-reset", C, "\t\tbreath_t = 0.0\n\telse:", "\t\tpass\n\telse:"),
    ("breath-underwater", C,
     "\tvar amount := 0.0 if bool(e.get(\"swimming\", false)) else breath_amount(amb)",
     "\tvar amount := breath_amount(amb)"),
    ("breath-fixed-rate", C,
     "\treturn lerpf(BREATH_CALM_S, BREATH_HARD_S, clampf(exertion, 0.0, 1.0))",
     "\treturn BREATH_CALM_S"),
    ("breath-calm-rate", C, "const BREATH_CALM_S := 4.2", "const BREATH_CALM_S := 2.0"),
    ("breath-hard-rate", C, "const BREATH_HARD_S := 1.5", "const BREATH_HARD_S := 3.6"),
    ("breath-size-flat", C,
     "\treturn breath_amount(amb) * (1.0 + BREATH_WORK_SIZE * clampf(exertion, 0.0, 1.0))",
     "\treturn breath_amount(amb)"),
    ("exertion-ignores-stamina", C,
     "\treturn clampf(1.0 - clampf(stamina01, 0.0, 1.0), 0.0, 1.0)", "\treturn 0.0"),
    ("exertion-ignores-sprint", C, "\tif sprinting:\n\t\treturn 1.0", "\tif false:\n\t\treturn 1.0"),

    # ---- the rungs are borrowed, not invented
    ("rung-own-low", C, "\tif warmth < Exposure.WARMTH_LOW:\n\t\treturn 1",
     "\tif warmth < 45.0:\n\t\treturn 1"),
    ("rung-own-numb", C, "\tif warmth < Exposure.WARMTH_NUMB:\n\t\treturn 2",
     "\tif warmth < 3.0:\n\t\treturn 2"),
    ("rung-two-only", C, "\tif warmth < Exposure.WARMTH_NUMB:\n\t\treturn 2",
     "\tif warmth < Exposure.WARMTH_NUMB:\n\t\treturn 1"),

    # ---- the bout: the only state in the file
    ("bout-is-a-query", C, "\tif bout_t > 0.0:\n\t\tbout_t = maxf(0.0, bout_t - d)",
     "\tif bout_t > 0.0 and grade > 0:\n\t\tbout_t = maxf(0.0, bout_t - d)"),
    ("bout-restrengthens", C, "\trep[\"shake\"] = bout_shake if bout_t > 0.0 else 0.0",
     "\trep[\"shake\"] = shake_for(warmth) if bout_t > 0.0 else 0.0"),
    ("bout-never-ends", C, "\t\tif bout_t <= 0.0:\n\t\t\tgap_t = bout_gap(warmth)\n\t\t\tbout_shake = 0.0",
     "\t\tif false:\n\t\t\tgap_t = bout_gap(warmth)\n\t\t\tbout_shake = 0.0"),
    ("bout-warm-man-shakes", C, "\telif grade > 0:", "\telif grade >= 0:"),
    ("bout-gap-constant", C, "\treturn lerpf(BOUT_GAP_LOW, BOUT_GAP_NUMB, shiver_t(warmth))",
     "\treturn BOUT_GAP_LOW"),
    ("bout-gap-numb-nonzero", C, "const BOUT_GAP_NUMB := 0.0", "const BOUT_GAP_NUMB := 4.0"),
    ("bout-len-constant", C, "\treturn lerpf(BOUT_LEN_LOW, BOUT_LEN_NUMB, shiver_t(warmth))",
     "\treturn BOUT_LEN_LOW"),
    ("shake-constant", C, "\treturn lerpf(SHAKE_LOW, SHAKE_NUMB, shiver_t(warmth))",
     "\treturn SHAKE_LOW"),
    ("shiver-t-inverted", C,
     "\treturn clampf((Exposure.WARMTH_LOW - warmth) / span, 0.0, 1.0)",
     "\treturn clampf((warmth - Exposure.WARMTH_NUMB) / span, 0.0, 1.0)"),
    ("reset-keeps-bout", C, "\tbout_t = 0.0\n\tgap_t = 0.0\n\tbreath_t = 0.0",
     "\tgap_t = 0.0\n\tbreath_t = 0.0"),

    # ---- the grade
    ("grade-opens-early", C,
     "\treturn clampf((Exposure.WARMTH_LOW - warmth) / Exposure.WARMTH_LOW, 0.0, 1.0)",
     "\treturn clampf((Exposure.WARMTH_MAX - warmth) / Exposure.WARMTH_MAX, 0.0, 1.0)"),
    ("grade-full-grey", C, "const GRADE_SAT := 0.55", "const GRADE_SAT := 1.0"),
    ("grade-no-sat", C, "const GRADE_SAT := 0.55", "const GRADE_SAT := 0.0"),
    ("grade-no-vignette", C, "const GRADE_VIGNETTE := 0.50", "const GRADE_VIGNETTE := 0.0"),
    ("grade-no-blue", C, "const GRADE_BLUE := 0.35", "const GRADE_BLUE := 0.0"),
    ("frost-at-shiver-line", C,
     "\treturn clampf((Exposure.WARMTH_NUMB - warmth) / Exposure.WARMTH_NUMB, 0.0, 1.0)",
     "\treturn clampf((Exposure.WARMTH_LOW - warmth) / Exposure.WARMTH_LOW, 0.0, 1.0)"),
    ("frost-none", C, "const FROST_MAX := 0.85", "const FROST_MAX := 0.0"),

    # ---- the waking
    ("wake-no-hold", C, "const WAKE_COLD_HOLD_S := 1.1", "const WAKE_COLD_HOLD_S := 0.45"),
    ("wake-cold-same-fade", C, "const WAKE_COLD_FADE_S := 2.9", "const WAKE_COLD_FADE_S := 1.8"),
    ("wake-no-shiver", C, "\t\tbout_t = BOUT_LEN_NUMB\n\t\tbout_shake = SHAKE_NUMB",
     "\t\tbout_t = 0.0\n\t\tbout_shake = 0.0"),
    ("wake-warm-shivers", C, "\twake_t = wake_total\n\tif cold:", "\twake_t = wake_total\n\tif true:"),
    ("wake-never-clears", C, "\twake_t = maxf(0.0, wake_t - d)", "\twake_t = maxf(0.0, wake_t)"),
    ("wake-zero-fade", C, "\tif fade <= 0.0:\n\t\treturn 0.0", "\tif false:\n\t\treturn 0.0"),

    # ---- the three the LIVE PASS found
    ("live-world-space-exhale", C, "\t\t_puff.local_coords = true", "\t\t_puff.local_coords = false"),
    ("live-metre-quad", C, "\t\tqm.size = Vector2(BREATH_QUAD_M, BREATH_QUAD_M)",
     "\t\tqm.size = Vector2(1.0, 1.0)"),
    ("live-quad-too-big", C, "const BREATH_QUAD_M := 0.12", "const BREATH_QUAD_M := 1.0"),
    ("live-bokeh-frost", C, "    return 1.0 - smoothstep(0.0, 0.085, sqrt(b2) - sqrt(best));",
     "    return 1.0 - smoothstep(0.0, 0.22, best);"),
    ("live-hard-square", C, "\t\tsm.albedo_texture = round_tex", "\t\tsm.albedo_color.a = 1.0"),

    # ---- the presenter actually pushes the numbers
    ("present-drops-sat", C,
     "\t\t\t_mat.set_shader_parameter(\"sat_drop\", float(rep.get(\"sat\", 0.0)))",
     "\t\t\tpass"),
    ("present-drops-frost", C,
     "\t\t\t_mat.set_shader_parameter(\"frost\", float(rep.get(\"frost\", 0.0)))",
     "\t\t\tpass"),
    ("overlay-over-the-bars", C, "\t\thud.move_child(_rect, 0)", "\t\tpass"),
    ("no-screen-texture", C, "uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;",
     "uniform sampler2D screen_tex : repeat_disable, filter_linear;"),

    # ---- Exposure's REAL front door: ten mutations in somebody else's file
    ("exp-season-flat", E, "const SEASON_BASE_C: Array[float] = [10.0, 18.0, 8.0, -4.0]",
     "const SEASON_BASE_C: Array[float] = [10.0, 10.0, 10.0, 10.0]"),
    ("exp-season-inverted", E, "const SEASON_BASE_C: Array[float] = [10.0, 18.0, 8.0, -4.0]",
     "const SEASON_BASE_C: Array[float] = [10.0, -4.0, 8.0, 18.0]"),
    ("exp-no-hour-swing", E, "const HOUR_SWING_C := 5.0", "const HOUR_SWING_C := 0.0"),
    ("exp-hour-flipped", E, "const HOUR_COLDEST := 4.0", "const HOUR_COLDEST := 14.0"),
    ("exp-no-lapse", E, "\treturn -LAPSE_PER_M * (y - LAPSE_BASE_Y)", "\treturn 0.0"),
    ("exp-lapse-inverted", E, "\treturn -LAPSE_PER_M * (y - LAPSE_BASE_Y)",
     "\treturn LAPSE_PER_M * (y - LAPSE_BASE_Y)"),
    ("exp-no-weather", E, "const WEATHER_C: Array[float] = [0.0, -1.0, -2.0, -3.5, -6.0]",
     "const WEATHER_C: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]"),
    ("exp-no-wind", E, "\treturn WIND_C * clampf(wind, 0.0, 1.0)", "\treturn 0.0"),
    ("exp-roof-keeps-wind", E, "\tif sheltered:\n\t\treturn 0.0\n\treturn WIND_C * clampf(wind, 0.0, 1.0)",
     "\treturn WIND_C * clampf(wind, 0.0, 1.0)"),
    ("exp-no-snow", E, "const SNOW_C := -1.5", "const SNOW_C := 0.0"),
    ("exp-rungs-collapse", E, "const WARMTH_NUMB := 10.0", "const WARMTH_NUMB := 30.0"),
    ("exp-sway-flat", E, "\tif warmth_v < WARMTH_NUMB:\n\t\treturn NUMB_SWAY",
     "\tif warmth_v < WARMTH_NUMB:\n\t\treturn SHIVER_SWAY"),
    ("exp-env-accepts-typos", E, "\t\tif not DEFAULTS.has(k):\n\t\t\tbad.append(k)",
     "\t\tif false:\n\t\t\tbad.append(k)"),
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
