#!/usr/bin/env python3
"""
tools/patch_carcasses.py -- wire the carcass economy into World.gd.

    python3 tools/patch_carcasses.py            # apply
    python3 tools/patch_carcasses.py --dry      # say what it would do

Five hunks, all purely additive, each guarded on what it DEFINES rather than
on what it calls -- the 2026-09-05 bug: a patcher that inserts both a
function and a call to it, and guards on the bare name, is satisfied by the
call it just wrote and silently skips the body. Run it twice; the second run
is a no-op and says so.

World.gd carries ~2 500 lines of Lemon's own uncommitted work, so this file
backs it up beside itself before touching it and prints the line delta after.
The expected delta is `+N / -0`. ANY REMOVED LINE IS A STOP-EVERYTHING.
"""

import os
import shutil
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGET = os.path.join(ROOT, "scripts", "World.gd")

DECL_OLD = "var _crofts: Crofts                   ## [crofts] and who lives out between them"
DECL_NEW = (DECL_OLD + "\n"
            "var _carcasses: Carcasses            ## [carcasses] and what the woods do with a kill")

BUILD_OLD = "\t_crofts.bind_world(self)"
BUILD_NEW = BUILD_OLD + """
\t## [carcasses] Sixty-five animals that can die and nothing downstream of
\t## a death but a twenty-two second ragdoll clock. A carcass is a LEDGER
\t## ENTRY with a number of kilograms on it, and five claimants bill
\t## against that number over the days after a kill -- the crows, a fox, a
\t## coyote pack, a bear and the ground itself -- in an order the hour, the
\t## sky and the season decide between them. Drop a deer at noon and the
\t## crows have it inside the hour; drop the same deer at midnight and a
\t## fox has been and gone before the crows are awake. Butcher it past a
\t## fifth and the pack that would have walked into your camp never comes.
\t## Built LAST, because bind_world reaches for chronicle(), rumours() and
\t## _wildlife, and a collaborator that does not exist yet binds as null
\t## and stays null for the session.
\t_carcasses = Carcasses.new()
\t_carcasses.name = "Carcasses"
\tadd_child(_carcasses)
\t_carcasses.bind_world(self)"""

ACC_OLD = "func rumours() -> RumourFeed:"
ACC_NEW = """func carcasses() -> Carcasses:
\t## [carcasses] What the woods are doing with what you killed, for the
\t## console, the map and the tests: World.carcasses().report(). Null until
\t## _build_wildlife() has run, or forever if USE_WILDLIFE is off -- every
\t## caller must tolerate that.
\treturn _carcasses


func rumours() -> RumourFeed:"""

SAVE_OLD = '\tout["crofts"] = _crofts.to_dict() if _crofts else {}          ## [crofts]'
SAVE_NEW = SAVE_OLD + '\n\tout["carcasses"] = _carcasses.to_dict() if _carcasses else {}  ## [carcasses]'

LOAD_OLD = ('\tif _crofts:  ## [crofts]\n'
            '\t\t_crofts.from_dict(d.get("crofts", {}) as Dictionary)')
LOAD_NEW = (LOAD_OLD + '\n'
            '\tif _carcasses:  ## [carcasses]\n'
            '\t\t_carcasses.from_dict(d.get("carcasses", {}) as Dictionary)')

# (label, old, new, guard)
HUNKS = [
    ("the member declaration", DECL_OLD, DECL_NEW, "var _carcasses:"),
    ("the build block in _build_wildlife", BUILD_OLD, BUILD_NEW, "_carcasses = Carcasses.new()"),
    ("the public accessor", ACC_OLD, ACC_NEW, "func carcasses"),
    ("the save hook", SAVE_OLD, SAVE_NEW, 'out["carcasses"]'),
    ("the load hook", LOAD_OLD, LOAD_NEW, "_carcasses.from_dict"),
]


def main():
    dry = "--dry" in sys.argv
    with open(TARGET) as fh:
        src = fh.read()
    before = src.count("\n")

    applied, skipped, missing = [], [], []
    for label, old, new, guard in HUNKS:
        if guard in src:
            skipped.append(label)
            continue
        n = src.count(old)
        if n != 1:
            missing.append((label, n))
            continue
        src = src.replace(old, new)
        applied.append(label)

    for label, n in missing:
        print("ANCHOR NOT FOUND (%d matches): %s" % (n, label))
    for label in skipped:
        print("already there, skipped: %s" % label)
    for label in applied:
        print(("would apply: %s" if dry else "applied: %s") % label)

    if missing:
        print("\nREFUSING TO WRITE -- %d anchor(s) did not match exactly once."
              % len(missing))
        return 2
    if not applied:
        print("\nnothing to do (idempotent no-op).")
        return 0
    after = src.count("\n")
    print("\n%d lines -> %d lines  (+%d / -0)" % (before, after, after - before))
    if dry:
        return 0

    bak = TARGET + ".bak_carcasses_" + time.strftime("%Y%m%d-%H%M%S")
    shutil.copy2(TARGET, bak)
    with open(TARGET, "w") as fh:
        fh.write(src)
    print("backup: %s" % os.path.basename(bak))
    print("diff World.gd against that backup before committing. Expect +N / -0;"
          " any removed line is a stop-everything.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
