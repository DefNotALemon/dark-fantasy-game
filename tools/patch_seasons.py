#!/usr/bin/env python3
"""Wire the local-season feed into World.gd (2026-09-11 09:00 ET, WORLD & LIFE).

    python3 tools/patch_seasons.py

`scripts/World.gd` carries ~2 700 lines of Lemon's own uncommitted work and is
therefore OUTSIDE this round's commit. These two hunks are the only edits the
round makes to it, and this script is how they come back if his tree is ever
reverted or rebuilt. It is idempotent: run it twice and the second run is a
clean no-op.

The two other edits the round makes -- `Crofts.season_here` and
`Carcasses.season_here` -- are in TRACKED files and went in with the commit,
so they are not repeated here.

⚠ Each hunk is guarded on what it DEFINES, never on a call to it. A guard that
matches the call as well as the definition is not a guard: the patcher writes
the call, then skips the body, and leaves a World.gd calling a function that
does not exist (2026-09-05 09:00).
"""

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORLD = os.path.join(ROOT, "scripts", "World.gd")

CALL_ANCHOR = """\t## [steps] the wetness feed. One line per frame; the bus itself is
\t## built next to WaterAudio and does nothing until it has a surface.
\t_feed_step_wetness()"""

CALL_ADD = """

\t## [seasons] the local-year feed. Same shape as the line above: one call
\t## per frame, and the season the foliage shaders paint becomes the season
\t## at the PLAYER'S FEET rather than the one on the calendar.
\t_feed_local_season()"""

BODY_ANCHOR = "func daynight() -> DayNight:"

BODY_ADD = '''## [seasons] THE YEAR IS A PLACE. `Wind.publish_season(day)` put ONE phase on
## the whole 41.7 km map, and published it only at the midnight rollover and
## on load -- so sleeping (which moves the day by any amount without crossing
## a rollover in `DayNight._process`) left every foliage shader painting
## yesterday's season until the next natural midnight, and setting the day by
## hand never updated them at all.
##
## Both halves are fixed here. The phase published is `Seasons.local_phase` at
## the player's position, so walking north or climbing turns the meadow and
## brings the snow in under your boots; and it is republished whenever it has
## actually moved, which no longer depends on how the day changed.
##
## Cheap by construction: the compare is against the last value PUBLISHED, so
## a standing player costs one float subtraction a frame and no RenderingServer
## traffic at all.
const SEASON_FEED_EPS := 0.0004   ## ~0.04 of a game day -- finer than the eye
var _season_pub := -1.0

func _feed_local_season() -> void:
\tif _daynight == null or _player == null:
\t\treturn
\tvar p := Seasons.local_phase(_daynight.day, _player.global_position)
\t## A year-wrap (0.999 -> 0.001) is a LARGE delta and publishes, which is
\t## what we want; there is no second clause guarding it, because one would
\t## be unreachable under any EPS below a half.
\tif _season_pub >= 0.0 and absf(p - _season_pub) < SEASON_FEED_EPS:
\t\treturn
\t_season_pub = p
\tWind.phase = p
\tRenderingServer.global_shader_parameter_set("season_phase", p)


'''


def main():
    src = open(WORLD, encoding="utf-8").read()
    before = len(src)
    did = []

    # --- hunk 1: the per-frame call. Guarded on the CALL, which is what it
    #     writes; the body has its own guard below.
    if "_feed_local_season()" in src:
        print("skip  call already present")
    elif src.count(CALL_ANCHOR) != 1:
        print("FAIL  wetness-feed anchor matched %d times" % src.count(CALL_ANCHOR))
        return 1
    else:
        src = src.replace(CALL_ANCHOR, CALL_ANCHOR + CALL_ADD, 1)
        did.append("call")

    # --- hunk 2: the function itself. Guarded on `func <name>`, NOT on the
    #     bare name, which the call above would satisfy.
    if "func _feed_local_season" in src:
        print("skip  body already present")
    elif src.count(BODY_ANCHOR) != 1:
        print("FAIL  daynight() anchor matched %d times" % src.count(BODY_ANCHOR))
        return 1
    else:
        src = src.replace(BODY_ANCHOR, BODY_ADD + BODY_ANCHOR, 1)
        did.append("body")

    if not did:
        print("no-op -- World.gd already carries the local-season feed")
        return 0

    open(WORLD, "w", encoding="utf-8").write(src)
    print("patched World.gd (%s): %d -> %d bytes" % ("+".join(did), before, len(src)))
    print("⚠ run filesystem_manage(op=\"scan\") in the editor afterwards.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
