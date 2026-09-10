#!/usr/bin/env python3
"""mutate_exposure.py -- is ExposureTests actually holding anything?

    python3 tools/mutate_exposure.py [--only NAME] [--list]

A green suite is evidence about the SUITE, not only about the source. This
reintroduces, one at a time, every defect the model could plausibly have and
checks that `tests/ExposureTests.gd` goes red for it. A mutation that SURVIVES
is a finding: either a missing test, a redundancy worth naming, or dead code
worth deleting -- and it is never to be waved away.

Two of these mutate `scripts/Firepit.gd` rather than `scripts/Exposure.gd`.
That is deliberate. Exposure adds no public method to Firepit and the whole
heat model still rests on `heat_from` taking the MAXIMUM and not the sum, so
the suite's `fire` section drives the real class and these two prove it.

Every touched file is sha-verified after restore; the script refuses to run at
all unless the untouched suite is green first.
"""

import hashlib
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = "/Applications/Godot.app/Contents/MacOS/Godot"
SUITE = "res://tests/ExposureTests.gd"

EXPO = "scripts/Exposure.gd"
PIT = "scripts/Firepit.gd"

# (name, relative path, exact text to find, replacement)
MUTATIONS = [
    ("season-flat", EXPO,
     "const SEASON_BASE_C: Array[float] = [10.0, 18.0, 8.0, -4.0]",
     "const SEASON_BASE_C: Array[float] = [10.0, 10.0, 10.0, 10.0]"),
    ("season-map-shift", EXPO,
     "return int(Wind.phase_for_day(day) * 4.0) % 4",
     "return (int(Wind.phase_for_day(day) * 4.0) + 1) % 4"),
    ("hour-symmetric", EXPO,
     "const HOUR_WARMEST := 14.0",
     "const HOUR_WARMEST := 16.0"),
    ("hour-sign", EXPO,
     "return -HOUR_SWING_C * cos(PI * clampf(u, 0.0, 1.0))",
     "return HOUR_SWING_C * cos(PI * clampf(u, 0.0, 1.0))"),
    ("lapse-sign", EXPO,
     "return -LAPSE_PER_M * (y - LAPSE_BASE_Y)",
     "return LAPSE_PER_M * (y - LAPSE_BASE_Y)"),
    ("lapse-zero", EXPO,
     "const LAPSE_PER_M := 0.0065",
     "const LAPSE_PER_M := 0.0"),
    ("weather-order", EXPO,
     "const WEATHER_C: Array[float] = [0.0, -1.0, -2.0, -3.5, -6.0]",
     "const WEATHER_C: Array[float] = [0.0, -1.0, -2.0, -6.0, -3.5]"),
    ("weather-no-intensity", EXPO,
     "return WEATHER_C[i] * clampf(intensity, 0.0, 1.0)",
     "return WEATHER_C[i]"),
    ("wind-ignores-shelter", EXPO,
     "static func wind_c(wind: float, sheltered: bool) -> float:\n\tif sheltered:\n\t\treturn 0.0",
     "static func wind_c(wind: float, sheltered: bool) -> float:\n\tif sheltered and wind < 0.0:\n\t\treturn 0.0"),
    ("shelter-keeps-the-weather", EXPO,
     "\tif not sheltered:\n\t\tc += weather_c(int(e.get(\"level\", 0)), intensity)",
     "\tif true:\n\t\tc += weather_c(int(e.get(\"level\", 0)), intensity)"),
    ("cave-is-not-shelter", EXPO,
     "return bool(e.get(\"sheltered\", false)) or bool(e.get(\"underground\", false))",
     "return bool(e.get(\"sheltered\", false))"),
    ("snow-is-free", EXPO,
     "const SNOW_C := -1.5",
     "const SNOW_C := 0.0"),
    ("wet-is-free", EXPO,
     "const WET_CHILL_C := 9.0",
     "const WET_CHILL_C := 0.0"),
    ("wind-not-on-wet-skin", EXPO,
     "const WET_CHILL_WIND := 1.0",
     "const WET_CHILL_WIND := 0.0"),
    ("negative-fire-cools", EXPO,
     "\tf += maxf(0.0, float(e.get(\"fire_c\", 0.0)))",
     "\tf += float(e.get(\"fire_c\", 0.0))"),
    ("torch-is-free", EXPO, "const TORCH_C := 3.5", "const TORCH_C := 0.0"),
    ("shelter-is-free", EXPO, "const SHELTER_C := 2.0", "const SHELTER_C := 0.0"),
    ("bedroll-is-free", EXPO, "const BED_C := 6.0", "const BED_C := 0.0"),
    ("regain-uncapped", EXPO,
     "const WARMTH_REGAIN_CAP := 0.55",
     "const WARMTH_REGAIN_CAP := 9999.0"),
    ("mode-taxes-the-regain-too", EXPO,
     "\t\treturn minf(WARMTH_REGAIN_CAP, (felt - WARMTH_NEUTRAL_C) * WARMTH_REGAIN_PER_DEGREE_S)",
     "\t\treturn minf(WARMTH_REGAIN_CAP, (felt - WARMTH_NEUTRAL_C) * WARMTH_REGAIN_PER_DEGREE_S / drain_mult_for(mode))"),
    ("peaceful-is-normal", EXPO,
     "const PEACE_DRAIN_MULT := 0.5",
     "const PEACE_DRAIN_MULT := 1.0"),
    ("hardcore-is-normal", EXPO,
     "const HARD_DRAIN_MULT := 1.25",
     "const HARD_DRAIN_MULT := 1.0"),
    ("unknown-mode-is-free", EXPO,
     "\tif mode == MODE_HARDCORE:\n\t\treturn HARD_DRAIN_MULT\n\treturn 1.0",
     "\tif mode == MODE_HARDCORE:\n\t\treturn HARD_DRAIN_MULT\n\treturn 0.0"),
    ("swimming-loses-to-a-roof", EXPO,
     "\tif bool(e.get(\"swimming\", false)):\n\t\treturn WET_SWIM_PER_S",
     "\tif bool(e.get(\"swimming\", false)) and not is_sheltered(e):\n\t\treturn WET_SWIM_PER_S"),
    ("rain-soaks-past-its-weight", EXPO,
     "\t\treturn 0.0 if wet_v >= target else WET_RAIN_PER_S",
     "\t\treturn WET_RAIN_PER_S"),
    ("you-dry-off-in-the-rain", EXPO,
     "\t\treturn 0.0 if wet_v >= target else WET_RAIN_PER_S",
     "\t\treturn -WET_DRY_PER_S if wet_v >= target else WET_RAIN_PER_S"),
    ("rain-comes-through-the-roof", EXPO,
     "static func raining_on(e: Dictionary) -> bool:\n\tif is_sheltered(e):\n\t\treturn false",
     "static func raining_on(e: Dictionary) -> bool:\n\tif false:\n\t\treturn false"),
    ("overcast-soaks-you", EXPO, "const RAIN_LEVEL := 2", "const RAIN_LEVEL := 1"),
    ("fire-does-not-dry", EXPO,
     "const WET_DRY_FIRE_MULT := 4.0",
     "const WET_DRY_FIRE_MULT := 1.0"),
    ("roof-does-not-dry", EXPO,
     "const WET_DRY_SHELTER_MULT := 1.6",
     "const WET_DRY_SHELTER_MULT := 1.0"),
    ("shivering-every-frame", EXPO,
     "\tif before >= WARMTH_LOW and warmth < WARMTH_LOW:",
     "\tif warmth < WARMTH_LOW:"),
    ("numb-never-fires", EXPO,
     "\telif before >= WARMTH_NUMB and warmth < WARMTH_NUMB:",
     "\telif before >= WARMTH_NUMB and warmth < -1.0:"),
    ("cold-does-not-kill", EXPO,
     "const WARMTH_DAMAGE_PER_S := 0.5",
     "const WARMTH_DAMAGE_PER_S := 0.0"),
    ("peaceful-kills-you", EXPO,
     "\tif warmth <= 0.0 and mode != MODE_PEACEFUL:",
     "\tif warmth <= 0.0:"),
    ("dying-warning-spams", EXPO,
     "const WARMTH_MSG_GAP := 12.0",
     "const WARMTH_MSG_GAP := 0.0"),
    ("negative-delta-warms-you", EXPO,
     "\tvar d := maxf(0.0, delta)",
     "\tvar d := delta"),
    ("meter-runs-past-full", EXPO,
     "\twarmth = clampf(warmth + rate * d, 0.0, WARMTH_MAX)",
     "\twarmth = maxf(0.0, warmth + rate * d)"),
    ("light-mode-drains", EXPO,
     "\tif not bool(e.get(\"survival\", true)):",
     "\tif not bool(e.get(\"survivall\", true)):"),
    ("light-mode-forgets-wet", EXPO,
     "\t\twarmth = WARMTH_MAX\n\t\t_dying = false",
     "\t\twarmth = WARMTH_MAX\n\t\twet = 0.0\n\t\t_dying = false"),
    ("save-does-not-clamp", EXPO,
     "\twarmth = clampf(float(d.get(\"warmth\", WARMTH_MAX)), 0.0, WARMTH_MAX)",
     "\twarmth = float(d.get(\"warmth\", WARMTH_MAX))"),
    ("respawn-lowers-a-full-meter", EXPO,
     "\twarmth = maxf(warmth, WARMTH_RESPAWN_MIN)",
     "\twarmth = WARMTH_RESPAWN_MIN"),
    ("respawn-leaves-you-soaked", EXPO,
     "func on_respawn() -> void:\n\twarmth = maxf(warmth, WARMTH_RESPAWN_MIN)\n\twet = 0.0",
     "func on_respawn() -> void:\n\twarmth = maxf(warmth, WARMTH_RESPAWN_MIN)"),
    ("light-does-not-top-the-meter", EXPO,
     "func to_light() -> void:",
     "func to_light(_unused := 0) -> void:\n\tif _unused == 0:\n\t\treturn"),
    ("unknown-keys-pass-silently", EXPO,
     "\t\tif not DEFAULTS.has(k):",
     "\t\tif DEFAULTS.has(k):"),
    ("shivering-costs-nothing", EXPO,
     "const SHIVER_STAMINA_MULT := 0.5",
     "const SHIVER_STAMINA_MULT := 1.0"),
    ("numb-hands-swing-normally", EXPO,
     "const NUMB_WINDUP_MULT := 1.15",
     "const NUMB_WINDUP_MULT := 1.0"),
    # --- the collaborator. Exposure adds nothing to Firepit and rests on it. --
    ("two-campfires-ARE-a-furnace", PIT,
     "\t\tbest = maxf(best, f.heat_at(at))",
     "\t\tbest = best + f.heat_at(at)"),
    ("a-banked-fire-is-a-lit-one", PIT,
     "const EMBER_HEAT_MULT := 0.25",
     "const EMBER_HEAT_MULT := 1.0"),
]


def sha(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def run_suite():
    p = subprocess.run(
        [GODOT, "--headless", "--path", ROOT, "--script", SUITE],
        capture_output=True, text=True, timeout=180)
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def main():
    args = sys.argv[1:]
    if "--list" in args:
        for m in MUTATIONS:
            print(m[0])
        return 0
    only = None
    if "--only" in args:
        only = args[args.index("--only") + 1]

    names = [m[0] for m in MUTATIONS]
    if len(names) != len(set(names)):
        print("FAIL: duplicate mutation names")
        return 2

    print("baseline...")
    rc, out = run_suite()
    if rc != 0:
        print("FAIL: the UNMUTATED suite is already red -- nothing below means anything")
        print(out[-2000:])
        return 2
    print("baseline green\n")

    before = {EXPO: sha(os.path.join(ROOT, EXPO)), PIT: sha(os.path.join(ROOT, PIT))}
    caught, survived, broken = [], [], []

    for name, rel, old, new in MUTATIONS:
        if only and name != only:
            continue
        path = os.path.join(ROOT, rel)
        with open(path, "r") as fh:
            src = fh.read()
        n = src.count(old)
        if n != 1:
            broken.append((name, "anchor matched %d times, not once" % n))
            print("  BROKEN  %-32s anchor matched %d times" % (name, n))
            continue
        try:
            with open(path, "w") as fh:
                fh.write(src.replace(old, new, 1))
            rc, out = run_suite()
        finally:
            with open(path, "w") as fh:
                fh.write(src)
        if rc != 0:
            caught.append(name)
            print("  caught    %s" % name)
        else:
            survived.append(name)
            print("  SURVIVED  %s   <-- a finding, not a shrug" % name)

    for rel, want in before.items():
        got = sha(os.path.join(ROOT, rel))
        if got != want:
            print("\nFAIL: %s was not restored byte-for-byte!" % rel)
            return 2

    total = len(caught) + len(survived)
    print("\n=== %d/%d caught, %d survived, %d broken anchors ==="
          % (len(caught), total, len(survived), len(broken)))
    for n in survived:
        print("  survived: %s" % n)
    for n, why in broken:
        print("  broken:   %s (%s)" % (n, why))
    return 0 if (not survived and not broken) else 1


if __name__ == "__main__":
    sys.exit(main())
