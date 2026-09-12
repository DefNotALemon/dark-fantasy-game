#!/usr/bin/env python3
"""
patch_incidents.py -- wire the Incident Director into World.gd.

    python3 tools/patch_incidents.py                 # apply, repo root = tools/..
    python3 tools/patch_incidents.py --dry-run       # report only, change nothing
    python3 tools/patch_incidents.py /path/to/repo   # apply against another checkout
    python3 tools/patch_incidents.py --check         # alias of --dry-run (house habit)

Idempotent, marker-guarded and PURELY ADDITIVE, same shape as
tools/patch_chronicle.py and tools/patch_steps.py: every insertion carries an
`## [incidents]` marker, the patcher refuses to add one twice, and it never
removes a line -- asserted with a real diff before anything is written.
World.gd has silently lost work to concurrent patchers twice; this touches FIVE
anchors, all additive, and prints exactly what it changed. It never opens
Player.gd.

=============================================================================
ORDER: patch_chronicle.py MUST RUN FIRST.

The Incident Director reads the Chronicle and nothing else, so it is built
immediately after `_chronicle.boot()` -- which is a line patch_chronicle.py
writes. That is deliberate rather than incidental:

  * it makes the dependency mechanical instead of a comment. Run this first
    and the `build` anchor is missing, the patcher refuses to write, and the
    message says which patcher to run;
  * it removes a real ordering hazard. Both patchers would otherwise want to
    anchor on `_wildlife.seed_world()`, and since each inserts directly after
    its anchor, whichever ran SECOND would land its block FIRST -- building an
    Incident Director against a `_chronicle` that is still null.

So: patch_chronicle.py, then this. Both are idempotent; running the pair twice
is a no-op.
=============================================================================

What it wires (scripts/World.gd only):
  member     _incidents: IncidentDirector next to _chronicle
  build      made, bound to the world, added -- right after _chronicle.boot()
  save       out["incidents"] in save_state()
  load       _incidents.from_dict() in apply_state()
  accessor   func incidents() -> IncidentDirector, beside chronicle()

DEV INPUTS: this patcher adds nothing to `_input`, nothing to the input map and
no UI. F1 / T / B / N / ' / M / Q / C / X and god fly-noclip-teleport are
untouched and unshadowed -- there is no key anywhere in either new script.

THE GUARD BUG (2026-09-05): a patcher that inserts both a FUNCTION and a CALL
to it must guard the function on `func <name>`, never on the bare name, or the
call it just wrote satisfies the guard and the next run skips the body. Every
guard below is the most specific string its own insertion writes and nothing
any other insertion writes; _trap_check() proves it mechanically at startup.
"""
import difflib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_ROOT = os.path.normpath(os.path.join(HERE, ".."))
TARGET = "scripts/World.gd"

# Anchors that only exist once patch_chronicle.py has run. Named so the
# refusal message can tell the operator what to do instead of just failing.
NEEDS_CHRONICLE = {"member", "build", "save", "load"}

# The scripts whose class names this patcher writes into World.gd. If they are
# not on disk, the edits below make World.gd reference a `class_name` that does
# not exist -- which is not a subtle failure: World.gd stops parsing and the
# game does not boot at all. Checked before anything is written.
REQUIRES = ["scripts/IncidentDirector.gd", "scripts/IncidentKit.gd"]

EDITS = [
    # 1. the member, next to the Chronicle it reads ------------------------
    ("member",
     "var _incidents: IncidentDirector",
     "var _chronicle: Chronicle            ## [chronicle] what happened while you were away\n",
     "after",
     "var _incidents: IncidentDirector     ## [incidents] and what of it you can walk into\n"),

    # 2. build it directly after the Chronicle boots -----------------------
    # Not after seed_world(): see the ORDER note in the docstring. The
    # Director tolerates a null Chronicle, but there is no reason to build one
    # blind when the dependency can be spelled in the anchor instead.
    ("build",
     "_incidents = IncidentDirector.new()",
     "\t_chronicle.boot()\n",
     "after",
     "\t## [incidents] The Chronicle knows a caravan is on the Freeport road at\n"
     "\t## hour nine and that wolves took a ewe at Sebec last night. It will\n"
     "\t## never put either of them in front of you -- it deals in places, not\n"
     "\t## nodes, on purpose. This is the half that makes them physical: the\n"
     "\t## party you can actually meet, and the torn hurdle with the crows on\n"
     "\t## it that you can stumble into three days later and read.\n"
     "\t_incidents = IncidentDirector.new()\n"
     "\t_incidents.name = \"IncidentDirector\"\n"
     "\tadd_child(_incidents)\n"
     "\t_incidents.bind_world(self)\n"),

    # 3. save ---------------------------------------------------------------
    ("save",
     "out[\"incidents\"]",
     "\tout[\"chronicle\"] = _chronicle.to_dict() if _chronicle else {}  ## [chronicle]\n",
     "after",
     "\tout[\"incidents\"] = _incidents.to_dict() if _incidents else {}  ## [incidents]\n"),

    # 4. load ---------------------------------------------------------------
    # from_dict MERGES, so a save written before this patcher landed carries no
    # "incidents" key, restores nothing, and wipes nothing.
    ("load",
     "_incidents.from_dict(",
     "\tif _chronicle:  ## [chronicle]\n"
     "\t\t_chronicle.from_dict(d.get(\"chronicle\", {}) as Dictionary)\n",
     "after",
     "\tif _incidents:  ## [incidents]\n"
     "\t\t_incidents.from_dict(d.get(\"incidents\", {}) as Dictionary)\n"),

    # 5. the accessor, in front of weather() -------------------------------
    # Guarded on the `func` line. See THE GUARD BUG above: guarding on
    # `incidents` would be satisfied by out["incidents"], d.get("incidents")
    # and the marker comments alike.
    ("accessor",
     "func incidents() -> IncidentDirector:",
     "func weather() -> Weather:\n",
     "before",
     "func incidents() -> IncidentDirector:\n"
     "\t## [incidents] The physical half of the off-screen world, for the\n"
     "\t## console and the tests. Null until _build_wildlife() has run, or\n"
     "\t## forever if USE_WILDLIFE is off -- every caller must tolerate that.\n"
     "\treturn _incidents\n"
     "\n"
     "\n"),
]


def _trap_check():
    """Refuse to run if any guard could be satisfied by another edit's text.

    A guard must be found in its own block and in no other block, and every
    guard must actually be written by its own block -- or a first run would
    never mark itself done."""
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

    absent = [r for r in REQUIRES if not os.path.isfile(os.path.join(root, r))]
    if absent:
        for r in absent:
            print("  ! %s is not on disk" % r)
        print("REFUSING to write: World.gd would reference a class_name that")
        print("  does not exist, and would stop parsing. Land the scripts first.")
        return 1
    before = open(path, encoding="utf-8").read()
    src = before

    changed, skipped, missing = [], [], []
    for tag, guard, anchor, where, block in EDITS:
        # counted against the ORIGINAL, never the file we are building: an
        # earlier edit must not be able to change a later count
        n = before.count(anchor)
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
        if any(tag in NEEDS_CHRONICLE and n == 0 for tag, _a, n in missing):
            print("")
            print("  The missing anchors are lines tools/patch_chronicle.py writes.")
            print("  Run it first:   python3 tools/patch_chronicle.py")
            print("  then run this patcher again. Both are idempotent.")
        print("REFUSING to write: %d anchor(s) did not match exactly once."
              % len(missing))
        return 1

    plus, minus = _delta(before, src)
    # The invariant that makes this safe to run on a file other people are also
    # patching: it only ever ADDS. Deliberately NOT an `assert` -- asserts are
    # stripped by `python3 -O`, and this is the one check standing between a
    # bad anchor and a World.gd that has silently lost work twice already.
    if minus != 0:
        print("  ! patcher would remove %d line(s)" % minus)
        print("REFUSING to write: this patcher is additive-only.")
        return 1
    if plus != sum(c[3] for c in changed):
        print("  ! line accounting drifted: total %d, edits sum to %d"
              % (plus, sum(c[3] for c in changed)))
        print("REFUSING to write.")
        return 1
    print("total delta: +%d/-%d lines" % (plus, minus))

    if not changed:
        print("nothing to do: World.gd already carries every [incidents] edit.")
        return 0
    if dry:
        print("--dry-run: %d edit(s) would apply, nothing written." % len(changed))
        return 0
    open(path, "w", encoding="utf-8").write(src)
    print("patched %s, %d edit(s)." % (TARGET, len(changed)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
