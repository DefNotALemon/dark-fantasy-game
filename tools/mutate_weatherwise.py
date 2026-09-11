#!/usr/bin/env python3
"""A green suite is evidence about the SUITE. Apply each mutation to the real
source, run tests/WeatherwiseTests.gd, demand RED. A SURVIVOR names a test
that does not exist -- or a redundancy, or dead code.

Fourteen of these live in files Weatherwise does not own, because a suite that
only mutates its own source proves nothing about whether its callers call it.

    python3 tools/mutate_weatherwise.py [--only N]
"""
import subprocess, sys, os, shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = "/Applications/Godot.app/Contents/MacOS/Godot"
SUITE = "res://tests/WeatherwiseTests.gd"
WW, TG, WD, CR = "scripts/Weatherwise.gd", "scripts/Telegraph.gd", "scripts/WildlifeDirector.gd", "scripts/Critter.gd"

M = [
(WW, "Guild.SOARING:    [1.0, 0.45, 0.12, 0.00, 0.00],", "Guild.SOARING:    [1.0, 0.45, 0.12, 0.20, 0.00],", "eagles still up in the rain"),
(WW, "Guild.SOARING:    [1.0, 0.45, 0.12, 0.00, 0.00],", "Guild.SOARING:    [1.0, 0.95, 0.12, 0.00, 0.00],", "cloud does not thin the soarers"),
(WW, "Guild.SHELTERING: [1.0, 0.85, 0.50, 0.25, 0.10],", "Guild.SHELTERING: [1.0, 0.85, 0.50, 0.60, 0.10],", "birds ignore real rain"),
(WW, "Guild.SHELTERING: [1.0, 0.85, 0.50, 0.25, 0.10],", "Guild.SHELTERING: [1.0, 0.85, 0.50, 0.25, 0.45],", "birds ignore a storm"),
(WW, "Guild.SHELTERING: [1.0, 0.85, 0.50, 0.25, 0.10],", "Guild.SHELTERING: [1.0, 1.00, 0.50, 0.25, 0.10],", "cloud does not quiet the birds"),
(WW, "Guild.FLATTENED:  [1.0, 0.85, 0.40, 0.12, 0.00],", "Guild.FLATTENED:  [1.0, 0.85, 0.40, 0.12, 0.15],", "insects fly in a storm"),
(WW, "Guild.DRAWN:      [1.0, 1.40, 1.60, 2.40, 1.80],", "Guild.DRAWN:      [1.0, 1.40, 1.60, 1.20, 1.80],", "rain does not draw the newts"),
(WW, "Guild.DRAWN:      [1.0, 1.40, 1.60, 2.40, 1.80],", "Guild.DRAWN:      [1.0, 1.40, 1.60, 2.40, 2.90],", "a newt likes being hammered"),
(WW, "Guild.DRAWN:      [1.0, 1.40, 1.60, 2.40, 1.80],", "Guild.DRAWN:      [1.0, 1.40, 1.00, 2.40, 1.80],", "drizzle draws nobody"),
(WW, "Guild.UNBOTHERED: [1.0, 1.00, 1.00, 1.00, 0.90],", "Guild.UNBOTHERED: [1.0, 1.00, 1.00, 1.00, 1.00],", "even a storm is nothing to a duck"),
(WW, "Guild.HUNTING:    [1.0, 1.05, 1.15, 1.20, 0.80],", "Guild.HUNTING:    [1.0, 1.05, 1.15, 0.80, 0.80],", "rain is not a fox's weather"),
(WW, "Guild.HUNTING:    [1.0, 1.05, 1.15, 1.20, 0.80],", "Guild.HUNTING:    [1.0, 1.05, 1.00, 1.20, 0.80],", "drizzle does nothing for a fox"),
(WW, "Guild.BEDDING:    [1.0, 1.15, 1.25, 0.60, 0.25],", "Guild.BEDDING:    [1.0, 1.15, 0.80, 0.60, 0.25],", "no surge before the front"),
(WW, "Guild.BEDDING:    [1.0, 1.15, 1.25, 0.60, 0.25],", "Guild.BEDDING:    [1.0, 1.15, 1.25, 1.00, 0.25],", "deer do not lie up in rain"),
(WW, "Guild.BEDDING:    [1.0, 1.15, 1.25, 0.60, 0.25],", "Guild.BEDDING:    [1.0, 1.00, 1.25, 0.60, 0.25],", "cloud does not stir them"),
(WW, "Guild.SOARING:    [0.0, 0.20, 0.55, 0.85, 1.00],", "Guild.SOARING:    [0.0, 0.20, 0.55, 0.85, 0.50],", "a grounded eagle is content"),
(WW, "Guild.BEDDING:    [0.0, 0.05, 0.15, 0.60, 0.90],", "Guild.BEDDING:    [0.0, 0.05, 0.15, 0.20, 0.90],", "a deer in rain wants no cover"),
(WW, "Guild.DRAWN:      [0.0, 0.00, 0.00, 0.00, 0.10],", "Guild.DRAWN:      [0.0, 0.00, 0.00, 0.80, 0.10],", "a newt hides from its own rain"),
(WW, "const NOISE_MASK := [1.00, 0.92, 0.78, 0.58, 0.40]", "const NOISE_MASK := [1.00, 0.92, 0.78, 0.90, 0.40]", "rain does not hide you"),
(WW, "const NOISE_MASK := [1.00, 0.92, 0.78, 0.58, 0.40]", "const NOISE_MASK := [1.00, 0.92, 0.78, 0.58, 0.56]", "a storm does not hide you"),
(WW, "const NOISE_MASK := [1.00, 0.92, 0.78, 0.58, 0.40]", "const NOISE_MASK := [1.00, 0.70, 0.78, 0.58, 0.40]", "cloud alone hides you"),
(WW, "const RELAY_MASK := [1.00, 1.00, 0.85, 0.65, 0.45]", "const RELAY_MASK := [1.00, 1.00, 0.85, 0.65, 0.80]", "a storm does not break the chain"),
(WW, "const RELAY_MASK := [1.00, 1.00, 0.85, 0.65, 0.45]", "const RELAY_MASK := [1.00, 0.50, 0.85, 0.65, 0.45]", "cloud breaks the chain"),
(WW, "const FRONT_STIR := 0.35", "const FRONT_STIR := 0.0", "the barometer does nothing"),
(WW, "const FRONT_STIR := 0.35", "const FRONT_STIR := 0.75", "the barometer does far too much"),
(WW, "const RAIN_ONLY_RUNG := 2.0", "const RAIN_ONLY_RUNG := 1.0", "overcast counts as rain"),
(WW, "const RAIN_ONLY_RUNG := 2.0", "const RAIN_ONLY_RUNG := 0.0", "the rain_only gate is off"),
(WW, "const FOG_BAND := Vector2(0.8, 3.0)", "const FOG_BAND := Vector2(0.0, 3.0)", "a specter on a clear night"),
(WW, "const FOG_BAND := Vector2(0.8, 3.0)", "const FOG_BAND := Vector2(0.8, 4.0)", "a specter inside a thunderstorm"),
(WW, "\tif bool(CritterDex.flag(key, \"legend\", false)):\n\t\treturn Guild.LEGEND", "\tif false:\n\t\treturn Guild.LEGEND", "legends are classified like animals"),
(WW, "\tif bool(CritterDex.flag(key, \"soars\", false)):\n\t\treturn Guild.SOARING", "\tif bool(CritterDex.flag(key, \"glide\", false)):\n\t\treturn Guild.SOARING", "gliding counts as soaring"),
(WW, "\t\tif bool(CritterDex.flag(key, \"basks\", false)):\n\t\t\treturn Guild.SHELTERING", "\t\tif false:\n\t\t\treturn Guild.SHELTERING", "a basking snake loves rain"),
(WW, "\tif rig == \"FISH\" or rig == \"BIRD_WATER\":", "\tif bool(CritterDex.flag(key, \"water\", false)):", "a moose is a water animal"),
(WW, "\tif rig == \"RODENT_S\":\n\t\treturn Guild.SHELTERING", "\tif false:\n\t\treturn Guild.SHELTERING", "squirrels bed down like deer"),
(WW, "\tif bool(CritterDex.flag(key, \"audio_only\", false)):\n\t\treturn Guild.VOICE", "\tif false:\n\t\treturn Guild.VOICE", "a voice is weighted like a body"),
(WW, "\tvar row := tbl[g] as Array\n\tvar lo := clampi(int(floorf(r)), 0, 4)", "\tvar row := tbl[g] as Array\n\tvar lo := clampi(int(round(r)), 0, 4)", "the table reads the nearest rung"),
(WW, "\treturn lerpf(float(row[lo]), float(row[hi]), clampf(f, 0.0, 1.0))", "\treturn float(row[lo])", "the table is stepped, not smooth"),
(WW, "\treturn clampf(lerpf(a, b, t), 0.0, 4.0)", "\treturn clampf(b, 0.0, 4.0)", "a front lands the instant it starts"),
(WW, "\tvar left := 1.0 - clampf(float(e.get(\"blend\", 1.0)), 0.0, 1.0)", "\tvar left := clampf(float(e.get(\"blend\", 1.0)), 0.0, 1.0)", "the barometer runs backwards"),
(WW, "\treturn clampf(d * left * 0.5, -1.0, 1.0)", "\treturn clampf(d * left, -1.0, 1.0)", "every front saturates the glass"),
(WW, "\tif FRONT_GUILDS.has(g):\n\t\tm *= 1.0 + FRONT_STIR * maxf(front(e), 0.0)", "\tif false:\n\t\tm *= 1.0 + FRONT_STIR * maxf(front(e), 0.0)", "nothing reads the barometer"),
(WW, "\tif bool(CritterDex.flag(key, \"rain_only\", false)) and r < RAIN_ONLY_RUNG:\n\t\treturn 0.0", "\tif false:\n\t\treturn 0.0", "rain_only means nothing again"),
(WW, "\tif not bool(CritterDex.flag(key, \"fog_only\", false)):\n\t\treturn true", "\tif true:\n\t\treturn true", "fog_only means nothing again"),
(WW, "\t\trr = rr * falloff * m", "\t\trr = rr * falloff", "the relay ignores the weather"),
(WW, "\treturn clampf(_row(COVER, guild_of(key), rung(e)), 0.0, 1.0)", "\treturn 0.0", "nothing ever wants cover"),
(TG, "\tring *= Weatherwise.noise_mult(weather)", "\tring *= 1.0", "player_noise ignores the rain"),
(TG, "const NOISE_FAR := 34.0", "const NOISE_FAR := 30.0", "a sprint carries less than it did"),
(TG, "const RELAY_FALLOFF := 0.62", "const RELAY_FALLOFF := 0.45", "a relay hop loses more than it did"),
(TG, "\t\tvar next_r := radius * RELAY_FALLOFF * Weatherwise.relay_mult(weather)", "\t\tvar next_r := radius * RELAY_FALLOFF", "_ring ignores the rain"),
(TG, "\tvar ring := lerpf(NOISE_NEAR, NOISE_FAR, clampf(loudness, 0.0, 1.0))", "\tvar ring := lerpf(10.0, 34.0, clampf(loudness, 0.0, 1.0))", "the ring is back to bare literals"),
(WD, "\t\tw *= Weatherwise.out_mult(k, wx)", "\t\tw *= 1.0", "the spawn roll ignores the sky"),
(WD, "\t\tif _rng.randf() > Weatherwise.out_mult(k, wx):\n\t\t\tcontinue", "\t\tif false:\n\t\t\tcontinue", "the swarm door ignores the sky"),
(WD, "\tcondition = condition and Weatherwise.legend_allows(key, _wx())", "\tcondition = condition", "the legend gate ignores the sky"),
(WD, "\t\t_tele.weather = _wx()", "\t\tpass", "the bus is never told the sky"),
(WD, "\t\t\tc.weather_cover = Weatherwise.cover_urge(c.species, wx)", "\t\t\tpass", "no animal is told to take cover"),
(WD, "\treturn Weatherwise.env(int(wx.level), int(wx.get(\"_from\")),", "\treturn Weatherwise.env(0, 0,", "the Director always reports clear"),
(CR, "\tif weather_cover >= COVER_HOLD:\n\t\t_steer(Vector3.ZERO, delta, 6.0)\n\t\t_call_cool = maxf(_call_cool, CALL_COOLDOWN.x * weather_cover)\n\t\treturn\n\tvar pull := _home - global_position\n\tpull.y = 0.0\n\tif pull.length() > home_radius:", "\tif false:\n\t\t_steer(Vector3.ZERO, delta, 6.0)\n\t\t_call_cool = maxf(_call_cool, CALL_COOLDOWN.x * weather_cover)\n\t\treturn\n\tvar pull := _home - global_position\n\tpull.y = 0.0\n\tif pull.length() > home_radius:", "a grazing animal never takes cover"),
(CR, "var weather_cover := 0.0", "var weather_cover_unused := 0.0", "a Critter has no cover term"),
]


def run_suite():
    p = subprocess.run([GODOT, "--headless", "--path", ROOT, "--script", SUITE],
                       capture_output=True, text=True, timeout=180)
    out = p.stdout + p.stderr
    return ("ALL GREEN" in out), out


def main():
    only = None
    if "--only" in sys.argv:
        only = int(sys.argv[sys.argv.index("--only") + 1])

    green, out = run_suite()
    if not green:
        print("BASELINE IS NOT GREEN -- fix that first")
        print(out[-3000:])
        return 1
    print("baseline green")

    files = sorted(set(m[0] for m in M))
    orig = {}
    for f in files:
        with open(os.path.join(ROOT, f), "rb") as fh:
            orig[f] = fh.read()

    bad_anchor, survived, caught = [], [], 0
    try:
        for i, (path, old, new, label) in enumerate(M):
            if only is not None and i != only:
                continue
            full = os.path.join(ROOT, path)
            src = orig[path].decode("utf-8")
            n = src.count(old)
            if n != 1:
                bad_anchor.append("%3d  %-34s anchor matches %d times" % (i, label, n))
                continue
            with open(full, "w") as fh:
                fh.write(src.replace(old, new, 1))
            ok, _ = run_suite()
            with open(full, "wb") as fh:
                fh.write(orig[path])
            if ok:
                survived.append("%3d  %-18s %s" % (i, os.path.basename(path), label))
                print("  SURVIVED  %3d  %s" % (i, label))
            else:
                caught += 1
                print("  caught    %3d  %s" % (i, label))
    finally:
        for f in files:
            with open(os.path.join(ROOT, f), "wb") as fh:
                fh.write(orig[f])

    print("\n=== %d caught, %d survived, %d bad anchors ===" % (caught, len(survived), len(bad_anchor)))
    for s in survived:
        print("  SURVIVOR " + s)
    for b in bad_anchor:
        print("  ANCHOR   " + b)
    green2, _ = run_suite()
    print("restored baseline green: %s" % green2)
    return 0 if (not survived and not bad_anchor and green2) else 1


if __name__ == "__main__":
    sys.exit(main())
