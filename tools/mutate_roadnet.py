#!/usr/bin/env python3
"""Prove RoadNetTests' assertions are load-bearing.  (2026-09-09, WORLD)

    python3 tools/mutate_roadnet.py [--list]

A green suite is evidence about the SUITE, not only about the source. This
reintroduces, one at a time, each defect the round either fixed or deliberately
guarded against, and requires the suite to go red for every one. A mutation the
suite survives is either a missing test or a constant nobody depends on -- and
both of those are findings, which is why the script prints them rather than
quietly passing.

The file is restored from an in-memory copy after every mutation, and again in
a `finally`, so an interrupted run cannot leave a sabotaged RoadNet.gd on disk.
"""

import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "scripts", "RoadNet.gd")
GODOT = "/Applications/Godot.app/Contents/MacOS/Godot"
SUITE = "res://tests/RoadNetTests.gd"

# (name, what it breaks, old, new)
MUTATIONS = [
    # NOTE (2026-09-09): the first version of this mutation dropped only the
    # STAMP_M slack and it SURVIVED -- correctly. Polyline vertices are 130 m
    # apart at most and the slack is 100 m, so the stamping is already dense
    # enough that removing the slack makes no answer wrong. That is a
    # redundancy, not a missing test. This one is a real early-out: it lets
    # the ring search stop on the first ring whatever it happened to find.
    ("grid-early-out",
     "the lookup stops on the first ring whatever it has found",
     'if bool(best["ok"]) and float(best["dist"]) + STAMP_M <= float(ring) * GRID_M:',
     'if bool(best["ok"]) and float(best["dist"]) - 2000.0 <= float(ring) * GRID_M:'),

    ("stamp-ends-only",
     "a road is indexed where it starts and nowhere along its length",
     "\t\t\tfor s in range(n + 1):\n"
     "\t\t\t\t_stamp(p.lerp(q, float(s) / float(n)), e)",
     "\t\t\tfor s in range(n + 1):\n"
     "\t\t\t\tif k == 0 and s == 0:\n"
     "\t\t\t\t\t_stamp(p.lerp(q, float(s) / float(n)), e)"),

    ("never-stamp",
     "the lookup grid is never populated at all",
     "\tarr.append(e)\n\t_grid[key] = arr",
     "\tif arr.size() >= 0:\n\t\treturn\n\tarr.append(e)\n\t_grid[key] = arr"),

    ("no-multigrid",
     "the carve relaxes every sample against its neighbours only -- the lake",
     "\tvar st := maxi(1, segs / 2)",
     "\tvar st := 1"),

    ("fixed-reach",
     "a coarse level may only nudge the road as far as a fine one",
     "\t\tstep = reach / float(LATERAL_STEPS)",
     "\t\tstep = LATERAL_M / float(LATERAL_STEPS)"),

    ("no-subsampling",
     "a kilometre of road is costed by its two endpoints",
     "\tvar n := clampi(int(ceil(l / SEG_M)), 1, 24)",
     "\tvar n := 1"),

    ("water-free",
     "water costs a road nothing",
     "const WATER_W := 30.0",
     "const WATER_W := 0.0"),

    ("flat-earth",
     "gradient costs a road nothing",
     "const GRADE_W := 26.0",
     "const GRADE_W := 0.0"),

    ("short-leash",
     "the offset leash is drawn so tight nothing can bend",
     "const MAX_OFFSET_FRAC := 0.35",
     "const MAX_OFFSET_FRAC := 0.0001"),

    ("unsorted-roster",
     "the roster keeps arrival order, so input order reshapes the map",
     'tidy.sort_custom(func(a, b): return String(a["name"]) < String(b["name"]))',
     'pass'),

    ("keep-duplicates",
     "a place named twice becomes two places",
     'if nm == "" or seen.has(nm):',
     'if nm == "":'),

    ("no-tree",
     "the spanning tree keeps none of its edges",
     "\t\tif via[pick] >= 0:",
     "\t\tif via[pick] >= 0 and pick < 0:"),

    ("no-shortcuts",
     "no detour is ever absurd enough to earn a road",
     "const SHORTCUT_RATIO := 2.4",
     "const SHORTCUT_RATIO := 1000.0"),

    ("rank-blind",
     "two hamlets get the same roads two market towns would",
     "\t\t\tvar trunk := _rank(i) >= 1 and _rank(j) >= 1",
     "\t\t\tvar trunk := true"),

    ("loose-ends",
     "a road ends near its place instead of exactly at it",
     "\tpoly[0] = a\n\tpoly[segs] = b",
     "\tpoly[0] = a"),

    ("unclamped-t",
     "t is allowed out of 0..1 by a float32 rounding error",
     '"t": clampf(bs / total, 0.0, 1.0) if total > 0.001 else 0.0,',
     '"t": (bs / total) if total > 0.001 else 0.0,'),

    ("index-parameterised",
     "a point along a road is found by sample index, not by arclength",
     "\tvar want := clampf(t, 0.0, 1.0) * total",
     "\tvar want := clampf(t, 0.0, 1.0) * total * 0.5"),

    ("no-fill",
     "a coarse level's decision never reaches the finer one",
     "\t\toff = _fill_between(off, st, segs)",
     "\t\toff = off"),
]


def run_suite():
    p = subprocess.run([GODOT, "--headless", "--path", ROOT, "--script", SUITE],
                       capture_output=True, text=True, cwd=ROOT)
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def main():
    if "--list" in sys.argv:
        for name, why, _o, _n in MUTATIONS:
            print("  %-20s %s" % (name, why))
        return 0

    with open(SRC, "r", encoding="utf-8") as fh:
        clean = fh.read()

    print("baseline ...")
    rc, out = run_suite()
    if rc != 0:
        print("BASELINE IS RED -- fix the suite before mutating it.")
        print(out[-2000:])
        return 1
    print("  baseline green.\n")

    caught = 0
    survived = []
    try:
        for name, why, old, new in MUTATIONS:
            if clean.count(old) != 1:
                print("  %-20s SKIPPED -- pattern matched %d times"
                      % (name, clean.count(old)))
                survived.append(name + " (stale pattern)")
                continue
            with open(SRC, "w", encoding="utf-8") as fh:
                fh.write(clean.replace(old, new, 1))
            rc, out = run_suite()
            fails = out.count("  FAIL")
            if rc != 0:
                caught += 1
                print("  %-20s CAUGHT  (%d assertions went red)  -- %s"
                      % (name, fails, why))
            else:
                survived.append(name)
                print("  %-20s SURVIVED -- nothing asserts that %s is wrong"
                      % (name, why))
    finally:
        with open(SRC, "w", encoding="utf-8") as fh:
            fh.write(clean)

    print("\n  %d of %d mutations caught." % (caught, len(MUTATIONS)))
    if survived:
        print("  survived: %s" % ", ".join(survived))
        print("  A mutation that will not die may be naming the test you never")
        print("  wrote. Write it, or delete the constant nothing depends on.")
        return 1
    print("  source restored, suite green.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
