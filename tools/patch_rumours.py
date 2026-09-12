#!/usr/bin/env python3
"""tools/patch_rumours.py -- wire the RumourFeed into World.gd.  [rumours]

Five purely additive edits to scripts/World.gd:

  1. a member,           next to _chronicle / _incidents
  2. a build block,      at the end of _build_wildlife(), after the Director
  3. a save line,        next to out["incidents"]
  4. a load block,       next to _incidents.from_dict
  5. an accessor,        World.rumours(), before weather()

It REMOVES NOTHING.  World.gd carries ~2500 lines of Lemon's own uncommitted
work; run `cp scripts/World.gd /tmp/World.gd.orig` first and `diff` after --
the expected diff is +N / -0, and a single removed line is a stop-everything.

Idempotent.  Every edit is guarded on a marker that ONLY that edit writes, and
the accessor is guarded on `func rumours(` rather than on the bare name, because
a guard that also matches a CALL is not a guard: the patcher that inserts both
a function and a call to it will skip the body it just promised (the bug found
2026-09-05 09:00, and the reason patch_steps.py still prints a hand-step note).

It refuses to write unless scripts/RumourFeed.gd is on disk, since World.gd
would otherwise reference a class_name that does not exist and stop parsing.

    python3 tools/patch_rumours.py            # patch
    python3 tools/patch_rumours.py --dry-run  # report only, write nothing
"""

import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORLD = os.path.join(ROOT, "scripts", "World.gd")
NEEDS = [os.path.join(ROOT, "scripts", "RumourFeed.gd")]

EDITS = [
    # (name, guard, anchor, text, where)  where = "after" | "before"
    (
        "member",
        "var _rumours: RumourFeed",
        "var _incidents: IncidentDirector     ## [incidents] and what of it you can walk into\n",
        "var _rumours: RumourFeed             ## [rumours] and what they are saying about it\n",
        "after",
    ),
    (
        "build",
        "_rumours = RumourFeed.new()",
        "\t_incidents.bind_world(self)\n",
        "\t## [rumours] The Chronicle talks to itself and the Director makes it\n"
        "\t## physical. This is the half that makes it AUDIBLE: walk into a\n"
        "\t## village and you start catching what the village is saying. It\n"
        "\t## finds the player and the Chronicle for itself, so it can be built\n"
        "\t## before either of them and survive both being replaced.\n"
        "\t_rumours = RumourFeed.new()\n"
        "\t_rumours.name = \"RumourFeed\"\n"
        "\tadd_child(_rumours)\n"
        "\t_rumours.boot()\n",
        "after",
    ),
    (
        "save",
        'out["rumours"]',
        '\tout["incidents"] = _incidents.to_dict() if _incidents else {}  ## [incidents]\n',
        '\tout["rumours"] = _rumours.to_dict() if _rumours else {}        ## [rumours]\n',
        "after",
    ),
    (
        "load",
        "_rumours.from_dict",
        '\t\t_incidents.from_dict(d.get("incidents", {}) as Dictionary)\n',
        "\tif _rumours:  ## [rumours]\n"
        '\t\t_rumours.from_dict(d.get("rumours", {}) as Dictionary)\n',
        "after",
    ),
    (
        "accessor",
        "func rumours(",
        "func weather() -> Weather:\n",
        "func rumours() -> RumourFeed:\n"
        "\t## [rumours] The ear on the Chronicle, for the console and the tests:\n"
        "\t## World.rumours().report(). Null until _build_wildlife() has run, or\n"
        "\t## forever if USE_WILDLIFE is off -- every caller must tolerate that.\n"
        "\treturn _rumours\n"
        "\n"
        "\n",
        "before",
    ),
]


def main() -> int:
    dry = "--dry-run" in sys.argv
    for need in NEEDS:
        if not os.path.exists(need):
            print("REFUSING: %s is not on disk -- World.gd would reference a "
                  "class_name that does not exist and stop parsing." % need)
            return 2
    if not os.path.exists(WORLD):
        print("REFUSING: %s not found" % WORLD)
        return 2

    with open(WORLD, "r", encoding="utf-8") as fh:
        src = fh.read()
    before_lines = src.count("\n")
    before_md5 = hashlib.md5(src.encode("utf-8")).hexdigest()

    applied, skipped, missing = [], [], []
    for name, guard, anchor, text, where in EDITS:
        if guard in src:
            skipped.append(name)
            continue
        n = src.count(anchor)
        if n != 1:
            missing.append("%s (anchor matched %d times, want 1)" % (name, n))
            continue
        src = src.replace(anchor, anchor + text if where == "after" else text + anchor, 1)
        applied.append(name)

    after_lines = src.count("\n")
    print("World.gd: %d lines -> %d lines  (+%d / -0)"
          % (before_lines, after_lines, after_lines - before_lines))
    print("  applied: %s" % (", ".join(applied) if applied else "(none)"))
    print("  already patched: %s" % (", ".join(skipped) if skipped else "(none)"))
    if missing:
        print("  ANCHOR PROBLEM: %s" % "; ".join(missing))
        print("REFUSING to write a half-patched World.gd.")
        return 1
    if not applied:
        print("Nothing to do.")
        return 0
    if dry:
        print("--dry-run: nothing written (md5 still %s)" % before_md5)
        return 0
    with open(WORLD, "w", encoding="utf-8") as fh:
        fh.write(src)
    print("written. Run filesystem_manage(op=\"scan\") before launching.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
