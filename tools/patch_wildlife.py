#!/usr/bin/env python3
"""
Wire the wildlife system into World.gd.

    python3 tools/patch_wildlife.py            # patch
    python3 tools/patch_wildlife.py --check    # report only, change nothing
    python3 tools/patch_wildlife.py --revert   # put the .bak back

Re-runnable: guarded by a marker, so running it twice is a no-op rather than a
mess. Same contract as tools/patch_repo.py — the original is kept as
World.gd.bak_wildlife before anything is written.

Five edits, all in scripts/World.gd:

  1. member vars for the three wildlife nodes
  2. _ready()      -> build them after the enemies spawn
  3. _process()    -> push the clock (hour + day) to the director
  4. save_state()  -> write the live wildlife
  5. apply_state() -> put it back
  6. _build_wildlife() appended

Deliberately small. The calendar this needs already exists: DayNight owns
`day`, increments it at the midnight rollover, and calls Wind.publish_season()
itself. Wildlife reads that clock rather than keeping its own — two counters
that can disagree about what season it is would be worse than none.

If an anchor is reported missing, World.gd has moved; the block it wanted is
printed so it can be pasted by hand.
"""

import argparse
import pathlib
import re
import sys

MARK = "## --- wildlife ---"

EDITS = [
    (
        "member vars",
        r"^var _wind: Wind\n",
        """var _wind: Wind
%s
var _wildlife: WildlifeDirector      ## who is out there, and when
var _telegraph: Telegraph            ## the forest's alarm bus
var _critter_audio: CritterAudio     ## calls, and the ambience bed
""" % MARK,
    ),
    (
        "_ready hook",
        r"^\t_spawn_enemies\(\)\n",
        "\t_spawn_enemies()\n\t_build_wildlife()  %s\n" % MARK,
    ),
    (
        "_process clock",
        r"^\t## Random events: now and then, the sky lets something go\.\n",
        """\t%s  The wildlife runs on DayNight's calendar, never its own.
\tif _wildlife != null and _daynight != null:
\t\t_wildlife.set_clock(_daynight.hour, _daynight.day)

\t## Random events: now and then, the sky lets something go.
""" % MARK,
    ),
    (
        "save_state",
        r'^\tif _region != null:\n\t\tout\["cave"\] = _region\.save_state\(\)\n',
        """\tif _wildlife != null:
\t\tout["wildlife"] = _wildlife.save_state()  %s
\tif _region != null:
\t\tout["cave"] = _region.save_state()
""" % MARK,
    ),
    (
        "apply_state",
        r'^\tif _weather and d\.has\("weather"\):\n\t\t_weather\.from_dict\(d\["weather"\] as Dictionary\)\n',
        """\tif _weather and d.has("weather"):
\t\t_weather.from_dict(d["weather"] as Dictionary)
\tif _wildlife != null:
\t\t_wildlife.apply_state(d.get("wildlife", {}) as Dictionary)  %s
""" % MARK,
    ),
]

BUILDER = '''

## ============================== Wildlife ===================================
%s
## Three nodes, in this order, because each finds the last one:
##   Telegraph         the alarm bus every animal rings and listens to
##   CritterAudio      the calls and the ambience bed (half the feature)
##   WildlifeDirector  who spawns, where, and when
##
## See docs/WILDLIFE.md. Set USE_WILDLIFE = false to turn the whole thing off
## in one line if it ever misbehaves — same escape hatch as USE_TREES_V2.


const USE_WILDLIFE := true


func _build_wildlife() -> void:
	if not USE_WILDLIFE:
		return
	_telegraph = Telegraph.new()
	add_child(_telegraph)
	_critter_audio = CritterAudio.new()
	add_child(_critter_audio)
	_wildlife = WildlifeDirector.new()
	_wildlife.player = _player
	_wildlife.world_radius = WORLD_RADIUS
	add_child(_wildlife)
	if _daynight != null:
		_wildlife.set_clock(_daynight.hour, _daynight.day)
	## The hand-placed pass: a chickadee flock by the camp, a squirrel in the
	## near timber, and one deer out at the tree line — so the first three
	## things a player meets are the one that lands on your hand, the one that
	## tells the forest you are here, and the one that runs.
	_wildlife.seed_world()


func wildlife_census() -> Dictionary:
	## For the debug menu and the test suite.
	return _wildlife.census() if _wildlife != null else {}
''' % MARK


def patch(root: pathlib.Path, check: bool) -> int:
    path = root / "scripts" / "World.gd"
    if not path.exists():
        print("!! not found: %s" % path)
        return 1
    src = path.read_text()
    original = src

    if MARK in src:
        print("== already patched (marker present) — nothing to do")
        return 0

    applied, missed = [], []
    for name, anchor, repl in EDITS:
        pat = re.compile(anchor, re.MULTILINE)
        if not pat.search(src):
            missed.append((name, repl))
            continue
        src = pat.sub(lambda _m: repl, src, count=1)
        applied.append(name)

    src = src.rstrip("\n") + "\n" + BUILDER

    for name in applied:
        print("   + %s" % name)
    for name, repl in missed:
        print("   !! ANCHOR NOT FOUND: %s — World.gd has moved. Paste this by hand:" % name)
        for line in repl.rstrip("\n").split("\n"):
            print("      | %s" % line)

    if check:
        print("== --check: nothing written")
        return 0 if not missed else 2
    if src == original:
        print("== no changes")
        return 0

    bak = path.with_suffix(".gd.bak_wildlife")
    if not bak.exists():
        bak.write_text(original)
        print("   kept original at %s" % bak.name)
    path.write_text(src)
    print("== patched %s" % path)
    return 0 if not missed else 2


def revert(root: pathlib.Path) -> int:
    path = root / "scripts" / "World.gd"
    bak = path.with_suffix(".gd.bak_wildlife")
    if not bak.exists():
        print("!! no backup at %s" % bak.name)
        return 1
    path.write_text(bak.read_text())
    print("== reverted %s from %s" % (path.name, bak.name))
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".", help="repo root (default: cwd)")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--revert", action="store_true")
    a = ap.parse_args()
    r = pathlib.Path(a.root).resolve()
    sys.exit(revert(r) if a.revert else patch(r, a.check))
