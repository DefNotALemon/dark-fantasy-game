#!/usr/bin/env python3
"""tools/patch_crofts.py -- wire scripts/Crofts.gd into World.gd.

Five hunks, all PURELY ADDITIVE, and idempotent by contract: run it twice and
the second run reports every hunk as already present and writes nothing.

    python3 tools/patch_crofts.py            # apply
    python3 tools/patch_crofts.py --dry-run  # report only, touch nothing

EACH HUNK IS GUARDED ON WHAT IT *DEFINES*, never on a word it merely uses.
That is the 2026-09-05 bug, written down: a patcher that inserted a function
and a call to it guarded the pair on the bare name, the call it had just
written satisfied the guard, and the function body was silently skipped --
leaving a World.gd that called something that did not exist. So the accessor
is guarded on `func crofts()`, the field on `var _crofts`, and so on.

World.gd carries a great deal of Lemon's own uncommitted work and has twice
lost lines to a concurrent patcher. This script therefore refuses to remove
anything: it only ever splices text in after (or before) an anchor it found
exactly once, and it prints the before/after line counts so the caller can
check for `+n / -0` without trusting it.
"""

import pathlib
import sys

WORLD = pathlib.Path("scripts/World.gd")

VAR_ANCHOR = "var _wayfarers: Wayfarers            ## [wayfarers] and who is out walking them\n"
VAR_ADD = "var _crofts: Crofts                   ## [crofts] and who lives out between them\n"

ACCESSOR_ANCHOR = "func rumours() -> RumourFeed:\n"
ACCESSOR_ADD = (
    "func crofts() -> Crofts:\n"
    "\t## [crofts] The smallholdings off the roads, for the console, the map\n"
    "\t## and the tests: World.crofts().report(). Null until _build_wildlife()\n"
    "\t## has run, or forever if USE_WILDLIFE is off -- every caller must\n"
    "\t## tolerate that.\n"
    "\treturn _crofts\n"
    "\n"
    "\n"
)

BUILD_ANCHOR = "\t_wayfarers.bind_world(self)\n"
BUILD_ADD = (
    "\t## [crofts] Fifty-eight roads with somebody on them, and still nobody\n"
    "\t## LIVING beside one. A croft is a smallholding seated off a road, out\n"
    "\t## of sight of its village, whose whole day is a query rather than a\n"
    "\t## script: hearth lit at rise and banked at dusk, beasts out unless it\n"
    "\t## is raining, washing on the line because the sky was clear at eight\n"
    "\t## and soaked on it because it was not clear at noon -- and a woodpile\n"
    "\t## that an autumn spent barred indoors will not see the far side of.\n"
    "\t## Built LAST, because bind_world reaches for roadnet(), chronicle()\n"
    "\t## and rumours(), and a collaborator that does not exist yet binds as\n"
    "\t## null and stays null for the session.\n"
    "\t_crofts = Crofts.new()\n"
    "\t_crofts.name = \"Crofts\"\n"
    "\tadd_child(_crofts)\n"
    "\t_crofts.bind_world(self)\n"
)

SAVE_ANCHOR = '\tout["wayfarers"] = _wayfarers.to_dict() if _wayfarers else {}    ## [wayfarers]\n'
SAVE_ADD = '\tout["crofts"] = _crofts.to_dict() if _crofts else {}          ## [crofts]\n'

LOAD_ANCHOR = (
    "\tif _wayfarers:  ## [wayfarers]\n"
    '\t\t_wayfarers.from_dict(d.get("wayfarers", {}) as Dictionary)\n'
)
LOAD_ADD = (
    "\tif _crofts:  ## [crofts]\n"
    '\t\t_crofts.from_dict(d.get("crofts", {}) as Dictionary)\n'
)

# name, guard (what this hunk DEFINES), anchor, text, placement
HUNKS = [
    ("field", "var _crofts:", VAR_ANCHOR, VAR_ADD, "after"),
    ("accessor", "func crofts()", ACCESSOR_ANCHOR, ACCESSOR_ADD, "before"),
    ("build", "_crofts = Crofts.new()", BUILD_ANCHOR, BUILD_ADD, "after"),
    ("save", 'out["crofts"]', SAVE_ANCHOR, SAVE_ADD, "after"),
    ("load", "_crofts.from_dict(", LOAD_ANCHOR, LOAD_ADD, "after"),
]


def main() -> int:
    dry = "--dry-run" in sys.argv
    if not WORLD.exists():
        print("patch_crofts: %s not found (run me from the project root)" % WORLD)
        return 2
    src = WORLD.read_text()
    before = src.count("\n")
    applied, skipped, missing = [], [], []

    for name, guard, anchor, add, where in HUNKS:
        if guard in src:
            skipped.append(name)
            continue
        n = src.count(anchor)
        if n != 1:
            missing.append("%s (anchor matched %d times)" % (name, n))
            continue
        if where == "after":
            src = src.replace(anchor, anchor + add, 1)
        else:
            src = src.replace(anchor, add + anchor, 1)
        applied.append(name)

    after = src.count("\n")
    print("patch_crofts: applied=%s skipped=%s missing=%s" % (applied, skipped, missing))
    print("patch_crofts: %d lines -> %d lines (+%d / -0)" % (before, after, after - before))
    if missing:
        print("patch_crofts: REFUSING to write -- an anchor did not match exactly once")
        return 1
    if applied and not dry:
        WORLD.write_text(src)
        print("patch_crofts: wrote %s" % WORLD)
    elif dry:
        print("patch_crofts: dry run, nothing written")
    else:
        print("patch_crofts: nothing to do")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
