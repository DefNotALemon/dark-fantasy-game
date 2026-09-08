#!/usr/bin/env python3
"""
patch_chronicle.py -- wire the Chronicle into World.gd.

    python3 tools/patch_chronicle.py                 # apply, repo root = tools/..
    python3 tools/patch_chronicle.py --dry-run       # report only, change nothing
    python3 tools/patch_chronicle.py /path/to/repo   # apply against another checkout
    python3 tools/patch_chronicle.py --check         # alias of --dry-run (house habit)

Idempotent, marker-guarded and PURELY ADDITIVE, same shape as
tools/patch_steps.py: every insertion carries a `## [chronicle]` marker, the
patcher refuses to add one twice, and it never removes a line -- that is
asserted with a real diff before anything is written. World.gd has silently
lost work to concurrent patchers before; this touches FIVE anchors in
World.gd, all additive, and prints exactly what it changed. It never opens
Player.gd.

What it wires (scripts/World.gd only):
  member     _chronicle: Chronicle next to _wildlife
  build      the node made, bound to the clock and sky, added, booted -- at
             the tail of _build_wildlife(), after the director is seeded
  save       out["chronicle"] in save_state()
  load       _chronicle.from_dict() in apply_state()
  accessor   func chronicle() -> Chronicle, beside weather()

=============================================================================
THE GUARD BUG (2026-09-05). A patcher that inserts both a FUNCTION and a CALL
to that function must guard the function on `func <name>`, never on the bare
name. Otherwise the call it just wrote satisfies the guard, the next run
skips the function body, and the game boots into a parse error calling a
function that does not exist. It cost a round.

So: every guard below is the most specific string its own insertion writes,
and nothing any OTHER insertion writes. The accessor is guarded on
`func chronicle() -> Chronicle:` -- NOT on `chronicle`, which would be matched
by out["chronicle"], d.get("chronicle"), and the marker comments alike.
_trap_check() proves this mechanically at startup: each guard must appear in
exactly one insertion, its own, or the patcher refuses to run at all.
=============================================================================
"""
import difflib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_ROOT = os.path.normpath(os.path.join(HERE, ".."))
TARGET = "scripts/World.gd"

# The whole edit list is against ONE file. Each entry:
#   (tag, guard, anchor, where, block)
#     guard   text whose presence means "already patched" -- see THE GUARD BUG
#     anchor  text that must occur EXACTLY ONCE in World.gd
#     where   "after" -> block goes right after the anchor
#             "before" -> block goes right before the anchor
#     block   the lines added; every one carries `## [chronicle]` or sits in a
#             run that opens with one
EDITS = [
    # 1. the member, next to the wildlife director -------------------------
    ("member",
     "var _chronicle: Chronicle",
     "var _wildlife: WildlifeDirector      ## who is out there, and when\n",
     "after",
     "var _chronicle: Chronicle            ## [chronicle] what happened while you were away\n"),

    # 2. build it at the tail of _build_wildlife() -------------------------
    # After seed_world(): the director is made, added and clocked by then.
    # It shares the wildlife's escape hatch on purpose -- USE_WILDLIFE = false
    # returns before this runs and _chronicle stays null; every other edit
    # below tolerates that.
    ("build",
     "_chronicle = Chronicle.new()",
     "\t_wildlife.seed_world()\n",
     "after",
     "\t## [chronicle] The Chronicle rides behind the wildlife: the off-screen\n"
     "\t## world that talks -- what the wolves did to whose fold, which road the\n"
     "\t## caravan gave up on. It binds to the same clock and sky the animals\n"
     "\t## keep, so a rumour about last night's storm is about the storm you saw.\n"
     "\t_chronicle = Chronicle.new()\n"
     "\t_chronicle.name = \"Chronicle\"\n"
     "\tChronicle.bind(_daynight, _weather)\n"
     "\tadd_child(_chronicle)\n"
     "\t_chronicle.boot()\n"),

    # 3. save ---------------------------------------------------------------
    ("save",
     "out[\"chronicle\"]",
     "\t\tout[\"wildlife\"] = _wildlife.save_state()  ## --- wildlife ---\n",
     "after",
     "\tout[\"chronicle\"] = _chronicle.to_dict() if _chronicle else {}  ## [chronicle]\n"),

    # 4. load ---------------------------------------------------------------
    ("load",
     "_chronicle.from_dict(",
     "\t\t_wildlife.apply_state(d.get(\"wildlife\", {}) as Dictionary)  ## --- wildlife ---\n",
     "after",
     "\tif _chronicle:  ## [chronicle]\n"
     "\t\t_chronicle.from_dict(d.get(\"chronicle\", {}) as Dictionary)\n"),

    # 5. the accessor, in front of weather() -------------------------------
    # Guarded on the `func` line. See THE GUARD BUG above.
    ("accessor",
     "func chronicle() -> Chronicle:",
     "func weather() -> Weather:\n",
     "before",
     "func chronicle() -> Chronicle:\n"
     "\t## [chronicle] The off-screen world, for the console, the tavern board\n"
     "\t## and the tests: World.chronicle().rumours_at(pos). Null until\n"
     "\t## _build_wildlife() has run, or forever if USE_WILDLIFE is off.\n"
     "\treturn _chronicle\n"
     "\n"
     "\n"),
]


def _trap_check():
    """Refuse to run if any guard could be satisfied by another edit's text.

    This is the mechanical form of THE GUARD BUG note in the docstring: a
    guard must be found in its own block and in no other block, and every
    guard must actually be written by its own block (or a first run would
    never mark itself done)."""
    bad = []
    for tag, guard, _anchor, _where, block in EDITS:
        if guard not in block:
            bad.append("[%s] guard %r is not written by its own block" % (tag, guard))
        for other_tag, _g, _a, _w, other_block in EDITS:
            if other_tag != tag and guard in other_block:
                bad.append("[%s] guard %r is also written by [%s] -- THE GUARD BUG"
                           % (tag, guard, other_tag))
    return bad


def _apply(src, anchor, where, block):
    if where == "after":
        return src.replace(anchor, anchor + block, 1)
    return src.replace(anchor, block + anchor, 1)


def _delta(before, after):
    """(+added, -removed) line counts from a real diff, not arithmetic."""
    added = removed = 0
    for line in difflib.ndiff(before.splitlines(True), after.splitlines(True)):
        if line.startswith("+ "):
            added += 1
        elif line.startswith("- "):
            removed += 1
    return added, removed


def _show(text):
    """An anchor, printed so tabs and newlines are visible."""
    return repr(text)


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    flags = [a for a in argv[1:] if a.startswith("--")]
    dry = "--dry-run" in flags or "--check" in flags
    unknown = [f for f in flags if f not in ("--dry-run", "--check")]
    if unknown or len(args) > 1:
        print(__doc__.split("\n\n")[1])
        return 2
    root = os.path.abspath(args[0]) if args else DEFAULT_ROOT
    path = os.path.join(root, TARGET)

    traps = _trap_check()
    if traps:
        for t in traps:
            print("  !", t)
        print("REFUSING to run: the guards would not survive a second pass.")
        return 1

    if not os.path.isfile(path):
        print("  ! %s not found under %s" % (TARGET, root))
        return 1
    before = open(path, encoding="utf-8").read()
    src = before

    changed, skipped, missing = [], [], []
    for tag, guard, anchor, where, block in EDITS:
        n = before.count(anchor)  # counted against the ORIGINAL, never the
        #                            file we are building -- an earlier edit
        #                            must not be able to change a later count
        if guard in src:
            skipped.append((tag, anchor, n))
            continue
        if n != 1:
            missing.append((tag, anchor, n))
            continue
        patched = _apply(src, anchor, where, block)
        plus, minus = _delta(src, patched)
        src = patched
        changed.append((tag, anchor, n, plus, minus))

    # ---- report ----------------------------------------------------------
    for tag, anchor, n, plus, minus in changed:
        print("  + %s [%s]  anchor %s  matches=%d  +%d/-%d"
              % (TARGET, tag, _show(anchor), n, plus, minus))
    for tag, anchor, n in skipped:
        print("  = %s [%s]  anchor %s  matches=%d  already patched"
              % (TARGET, tag, _show(anchor), n))
    for tag, anchor, n in missing:
        print("  ! %s [%s]  anchor %s  found %d times (want 1)"
              % (TARGET, tag, _show(anchor), n))
    if missing:
        print("REFUSING to write: %d anchor(s) did not match exactly once."
              % len(missing))
        return 1

    plus, minus = _delta(before, src)
    # The one invariant that makes this patcher safe to run on a file other
    # people are also patching: it only ever ADDS.
    assert minus == 0, "patcher tried to remove %d line(s) -- refusing" % minus
    assert plus == sum(c[3] for c in changed), "line accounting drifted"
    print("total delta: +%d/-%d lines" % (plus, minus))

    if not changed:
        print("nothing to do: World.gd already carries every [chronicle] edit.")
        return 0
    if dry:
        print("--dry-run: %d edit(s) would apply, nothing written." % len(changed))
        return 0
    open(path, "w", encoding="utf-8").write(src)
    print("patched %s, %d edit(s)." % (TARGET, len(changed)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
