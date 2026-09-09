#!/usr/bin/env python3
"""Wire the Road Net into World.gd.  (2026-09-09, WORLD)

    python3 tools/patch_roadnet.py [--dry-run]

THREE additive edits, no line ever removed:

  1. a `_roads` member beside `_chronicle` / `_incidents` / `_rumours`
  2. a build block immediately BEFORE the Incident Director is built, because
     `IncidentDirector.bind_world()` reaches for `World.roadnet()` and a net
     that does not exist yet binds as null and stays null for the session
  3. a `roadnet()` accessor beside `incidents()`

There is deliberately NO save/load edit.  The net is a pure function of the
place roster and the heightfield, both of which a save already restores, so
serialising it would only be a second copy of something that rebuilds in a few
milliseconds -- and a second copy is a second thing that can go stale.

Every insertion is guarded on a marker that can only match the thing it is
guarding, never a call to it: the 2026-09-05 bug was a guard that tested for a
bare name, which the freshly-written CALL satisfied, so the patcher skipped the
definition and wrote a file that called a function that did not exist.  Here
the function guard is `func roadnet` and the member guard is `var _roads`.

Idempotent: a second run reports every marker already patched and writes
nothing.  Purely additive: the script refuses to write if the output has fewer
lines than the input.
"""

import sys
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORLD = os.path.join(ROOT, "scripts", "World.gd")
NET = os.path.join(ROOT, "scripts", "RoadNet.gd")

MEMBER_ANCHOR = "var _rumours: RumourFeed"
MEMBER_GUARD = "var _roads: RoadNet"
MEMBER_TEXT = (
    "var _roads: RoadNet                  ## [roadnet] and the roads between the places\n"
)

BUILD_ANCHOR = "\t_incidents = IncidentDirector.new()"
BUILD_GUARD = "_roads = RoadNet.new()"
BUILD_TEXT = (
    "\t## [roadnet] the travel graph over the fifty places. Built BEFORE the\n"
    "\t## Incident Director, because bind_world() reaches for roadnet() and a\n"
    "\t## net that does not exist yet binds as null and stays null all session.\n"
    "\t_roads = RoadNet.new()\n"
    "\t_roads.name = \"RoadNet\"\n"
    "\tadd_child(_roads)\n"
    "\t_roads.bind_world(self)\n"
    "\t_roads.boot()\n"
    "\n"
)

ACCESSOR_ANCHOR = "func incidents() -> IncidentDirector:"
ACCESSOR_GUARD = "func roadnet"
ACCESSOR_TEXT = (
    "func roadnet() -> RoadNet:\n"
    "\t## [roadnet] The road net, or null before begin_world has run. The\n"
    "\t## Incident Director and the map both read it; neither may assume it.\n"
    "\treturn _roads\n"
    "\n"
    "\n"
)

EDITS = [
    ("member", MEMBER_GUARD, MEMBER_ANCHOR, MEMBER_TEXT, "after"),
    ("build", BUILD_GUARD, BUILD_ANCHOR, BUILD_TEXT, "before"),
    ("accessor", ACCESSOR_GUARD, ACCESSOR_ANCHOR, ACCESSOR_TEXT, "before"),
]


def main():
    dry = "--dry-run" in sys.argv

    if not os.path.exists(NET):
        print("REFUSING: scripts/RoadNet.gd is not on disk.")
        print("World.gd would reference a class_name that does not exist and")
        print("stop parsing, which takes the whole game down at boot.")
        return 2
    if not os.path.exists(WORLD):
        print("REFUSING: scripts/World.gd not found at %s" % WORLD)
        return 2

    with open(WORLD, "r", encoding="utf-8") as fh:
        src = fh.read()
    before_lines = src.count("\n")

    out = src
    applied = 0
    for name, guard, anchor, text, where in EDITS:
        if guard in out:
            print("  %-9s already patched" % name)
            continue
        hits = out.count(anchor)
        if hits != 1:
            print("  %-9s ANCHOR MATCHED %d TIMES -- refusing to guess" % (name, hits))
            print("             anchor: %r" % anchor)
            return 3
        idx = out.index(anchor)
        if where == "after":
            eol = out.index("\n", idx) + 1
            out = out[:eol] + text + out[eol:]
        else:
            bol = out.rfind("\n", 0, idx) + 1
            out = out[:bol] + text + out[bol:]
        applied += 1
        print("  %-9s inserted %s its anchor" % (name, where))

    after_lines = out.count("\n")
    if after_lines < before_lines:
        print("REFUSING: the patch would REMOVE lines (%d -> %d)." % (before_lines, after_lines))
        return 4

    print("\n  World.gd  %d -> %d lines  (+%d / -0), %d edit(s)"
          % (before_lines, after_lines, after_lines - before_lines, applied))

    if applied == 0:
        print("  nothing to do.")
        return 0
    if dry:
        print("  --dry-run: nothing written.")
        return 0

    with open(WORLD, "w", encoding="utf-8") as fh:
        fh.write(out)
    print("  written.")
    print("\n  NEXT: run filesystem_manage(op=\"scan\") before launching, or the")
    print("  global class table will not know RoadNet and the boot will fail on")
    print("  an unresolved class.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
