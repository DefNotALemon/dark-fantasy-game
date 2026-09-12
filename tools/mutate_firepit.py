#!/usr/bin/env python3
"""
mutate_firepit.py -- prove tests/FirepitTests.gd can actually fail.

A green suite is evidence about the suite, not only about the source
(gauntlet ledger, 2026-09-07: two live defects sat under a 771/0 green because
the suite had encoded them as intended behaviour). So: reintroduce, one at a
time, each bug the firepit pass was written to prevent, and require the suite
to go RED. A mutation that leaves it green names an assertion that cannot
fail.

    python3 tools/mutate_firepit.py

Restores every file it touches, including on a crash.
"""

import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = "/Applications/Godot.app/Contents/MacOS/Godot"
FIREPIT = os.path.join(ROOT, "scripts", "Firepit.gd")
PIECE = os.path.join(ROOT, "scripts", "BuiltPiece.gd")

## (label, file, find, replace, what it breaks)
MUTATIONS = [
    ("heat sums instead of maxing", FIREPIT,
     "\t\tbest = maxf(best, f.heat_at(at))",
     "\t\tbest = best + f.heat_at(at)",
     "two campfires become a furnace"),

    ("no ember stage", FIREPIT,
     "\t\tstate = State.EMBERS\n\t\tember_t = EMBER_SECONDS",
     "\t\tstate = State.OUT\n\t\tember_t = 0.0",
     "a spent fire dies instead of banking"),

    ("rain ignores the roof", FIREPIT,
     "\tif float(w.intensity) > RAIN_THRESHOLD and not sheltered():",
     "\tif float(w.intensity) > RAIN_THRESHOLD:",
     "a roof stops saving the wood"),

    ("storm ignores the roof", FIREPIT,
     "\tif sheltered():\n\t\treturn false",
     "\tif false:\n\t\treturn false",
     "you cannot light a fire indoors in a gale"),

    ("save does not clamp", FIREPIT,
     "\tfuel = clampf(float(d.get(\"fuel\", 0.0)), 0.0, FUEL_MAX)",
     "\tfuel = float(d.get(\"fuel\", 0.0))",
     "a corrupt save loads infinite wood"),

    ("crash dict stays lit", FIREPIT,
     "\tif state == State.LIT and fuel <= 0.0:",
     "\tif false and fuel <= 0.0:",
     "a fire with no wood loads as burning"),

    ("smoke group never joined", FIREPIT,
     "\tif want and not have:\n\t\tadd_to_group(\"campfires\")",
     "\tif false and not have:\n\t\tadd_to_group(\"campfires\")",
     "CritterSwarm's smoke relief goes back to never firing"),

    ("fuel cap removed", FIREPIT,
     "\tfuel = minf(FUEL_MAX, fuel + seconds)",
     "\tfuel = fuel + seconds",
     "one armful of wood burns for a week"),

    ("piece drops its saved fire", PIECE,
     "\t\tfire.apply_dict(_fire_restore)",
     "\t\tpass",
     "a banked camp loads cold"),

    ("piece attaches a second fire", PIECE,
     "\tif fire != null and is_instance_valid(fire):\n\t\treturn\n"
     "\tfor c in get_children():\n\t\tif c is Firepit:\n"
     "\t\t\tfire = c as Firepit\n\t\t\tbreak",
     "\tif false:\n\t\treturn",
     "every _ready doubles the fire"),
]


def run_suite() -> tuple:
    p = subprocess.run(
        [GODOT, "--headless", "--path", ROOT,
         "--script", "res://tests/FirepitTests.gd"],
        capture_output=True, text=True, timeout=300)
    tail = [l for l in p.stdout.splitlines() if "passed," in l or "FAIL" in l]
    return p.returncode, tail


def main() -> int:
    if not os.path.exists(GODOT):
        print("no Godot at %s" % GODOT)
        return 2
    tmp = tempfile.mkdtemp(prefix="mutfire")
    for f in (FIREPIT, PIECE):
        shutil.copy2(f, os.path.join(tmp, os.path.basename(f)))
    bad = []
    try:
        rc, tail = run_suite()
        print("BASELINE  rc=%d  %s" % (rc, tail[-1] if tail else "?"))
        if rc != 0:
            print("baseline is not green -- fix that before mutating")
            return 1
        for label, path, find, repl, why in MUTATIONS:
            src = open(path, encoding="utf-8").read()
            if src.count(find) != 1:
                print("SKIP      %-32s (pattern matched %d times)"
                      % (label, src.count(find)))
                bad.append(label)
                continue
            open(path, "w", encoding="utf-8").write(src.replace(find, repl, 1))
            rc, tail = run_suite()
            shutil.copy2(os.path.join(tmp, os.path.basename(path)), path)
            fails = [t for t in tail if t.startswith("  FAIL")]
            if rc == 0:
                print("SURVIVED  %-32s -- %s" % (label, why))
                bad.append(label)
            else:
                print("caught    %-32s  %d assertion(s) went red" % (label, len(fails)))
    finally:
        for f in (FIREPIT, PIECE):
            shutil.copy2(os.path.join(tmp, os.path.basename(f)), f)
        shutil.rmtree(tmp, ignore_errors=True)
    print("\n%d/%d mutations caught" % (len(MUTATIONS) - len(bad), len(MUTATIONS)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
