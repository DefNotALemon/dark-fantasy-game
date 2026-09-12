#!/usr/bin/env python3
# =============================================================================
# tools/patch_wayfarers.py -- wire Wayfarers into World.gd. (2026-09-09, WORLD)
#
#   python3 tools/patch_wayfarers.py [--dry]
#
# Five additive edits, each idempotent and guarded on something only that edit
# can produce. The accessor's guard is `func wayfarers(` and NOT `wayfarers(`,
# because the build block this same patcher writes contains calls the looser
# marker would match -- which is the exact bug that shipped a World.gd calling
# an undefined function on 2026-09-05.
#
# World.gd carries ~2 500 lines of Lemon's own uncommitted work. This script
# only ever INSERTS, never rewrites, and prints the line delta so the round can
# assert +n / -0 afterwards.
# =============================================================================

import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORLD = os.path.join(ROOT, "scripts", "World.gd")
NEEDED = [os.path.join(ROOT, "scripts", "Wayfarers.gd")]

T = chr(9)
NL = chr(10)

BUILD = NL.join([
    T + "## [wayfarers] Fifty-eight roads and, until now, nobody on one. A band",
    T + "## is a named traveller walking a fixed circuit of three to five places",
    T + "## for the rest of the game, at a pace its trade can manage, stopping",
    T + "## where the light fails and holding where the weather is worse than",
    T + "## that -- and carrying whatever the last village was talking about to",
    T + "## the next one. Built LAST, because bind_world reaches for roadnet(),",
    T + "## chronicle() and rumours(), and a collaborator that does not exist",
    T + "## yet binds as null and stays null for the session.",
    T + "_wayfarers = Wayfarers.new()",
    T + '_wayfarers.name = "Wayfarers"',
    T + "add_child(_wayfarers)",
    T + "_wayfarers.bind_world(self)",
    "",
])

EDITS = [
    {
        "name": "member",
        "guard": "_wayfarers: Wayfarers",
        "anchor": "var _roads: RoadNet                  ## [roadnet] and the roads between the places" + NL,
        "add": "var _wayfarers: Wayfarers            ## [wayfarers] and who is out walking them" + NL,
    },
    {
        "name": "build",
        "guard": "_wayfarers = Wayfarers.new()",
        "anchor": T + "_rumours.boot()" + NL,
        "add": BUILD,
    },
    {
        "name": "save",
        "guard": 'out["wayfarers"]',
        "anchor": T + 'out["rumours"] = _rumours.to_dict() if _rumours else {}        ## [rumours]' + NL,
        "add": T + 'out["wayfarers"] = _wayfarers.to_dict() if _wayfarers else {}    ## [wayfarers]' + NL,
    },
    {
        "name": "load",
        "guard": "_wayfarers.from_dict",
        "anchor": T + "if _rumours:  ## [rumours]" + NL
                  + T + T + '_rumours.from_dict(d.get("rumours", {}) as Dictionary)' + NL,
        "add": T + "if _wayfarers:  ## [wayfarers]" + NL
               + T + T + '_wayfarers.from_dict(d.get("wayfarers", {}) as Dictionary)' + NL,
    },
    {
        "name": "accessor",
        "guard": "func wayfarers(",
        "anchor": "func rumours() -> RumourFeed:" + NL,
        "add": NL.join([
            "func wayfarers() -> Wayfarers:",
            T + "## [wayfarers] Who is on the roads, for the console, the map and the",
            T + "## tests: World.wayfarers().report(). Null until _build_wildlife()",
            T + "## has run, or forever if USE_WILDLIFE is off -- every caller must",
            T + "## tolerate that, and every caller does.",
            T + "return _wayfarers",
            "",
            "",
            "",
        ]),
        "where": "before",
    },
]


def main():
    dry = "--dry" in sys.argv
    for p in NEEDED:
        if not os.path.exists(p):
            print("REFUSING: %s is not on disk. World.gd would reference a class" % p)
            print("that does not exist and stop parsing at boot.")
            return 2
    src = io.open(WORLD, encoding="utf-8").read()
    before = src.count(NL)
    edits = 0
    for e in EDITS:
        if e["guard"] in src:
            print("  --  %-9s already patched" % e["name"])
            continue
        n = src.count(e["anchor"])
        if n != 1:
            print("  !!  %-9s ANCHOR MATCHED %d TIMES -- refusing" % (e["name"], n))
            return 1
        if e.get("where") == "before":
            src = src.replace(e["anchor"], e["add"] + e["anchor"])
        else:
            src = src.replace(e["anchor"], e["anchor"] + e["add"])
        edits += 1
        print("  ok  %-9s inserted" % e["name"])
    after = src.count(NL)
    print("%d edits, %+d lines" % (edits, after - before))
    if dry:
        print("(dry run -- nothing written)")
        return 0
    if edits:
        io.open(WORLD, "w", encoding="utf-8").write(src)
    return 0


if __name__ == "__main__":
    sys.exit(main())
