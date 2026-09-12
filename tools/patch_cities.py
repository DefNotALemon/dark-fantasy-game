#!/usr/bin/env python3
"""patch_cities.py — wire Cities.gd into World.gd. Idempotent, marker-guarded.

    python3 tools/patch_cities.py [--world scripts/World.gd] [--dry-run]

Three hunks, each guarded by the literal marker `[cities]` so a second run
adds nothing (and says so):

  1. `var _cities: Node3D = null` after `var _daynight` — the handle.
  2. `_cities = Cities.boot(self)` as the LAST line of `begin_world()` if
     the world has one, else of `_ready()` — after the roster, the road
     net, the crofts: everything the cities read.
  3. `func cities() -> Node3D` at the end of the file — the accessor the
     map, the feed and a test will ask for.

Nothing is removed. Every anchor must match exactly once or the hunk is
refused with the count, and the file is left untouched.
"""
import argparse
import re
import sys

MARK = "[cities]"


def find_func_end(lines, start):
    """Index of the first line after the body of the func starting at `start`."""
    i = start + 1
    last_body = start
    while i < len(lines):
        l = lines[i]
        if l.strip() == "" or l.startswith("\t") or l.startswith("#"):
            if l.startswith("\t"):
                last_body = i
            i += 1
            continue
        break
    return last_body + 1


def patch(src):
    if MARK in src:
        already = src.count(MARK)
    else:
        already = 0
    lines = src.split("\n")
    edits = 0
    notes = []

    # --- hunk 1: the handle -------------------------------------------------
    if not any(re.match(r"^var _cities\b", l) for l in lines):
        anchors = [i for i, l in enumerate(lines) if re.match(r"^var _daynight\b", l)]
        if len(anchors) != 1:
            return None, "hunk 1: anchor `var _daynight` matched %d times" % len(anchors)
        lines.insert(anchors[0] + 1, "var _cities: Node3D = null    ## %s the big six, scripts/Cities.gd" % MARK)
        edits += 1
        notes.append("hunk 1 (handle) added")
    else:
        notes.append("hunk 1 (handle) already patched")

    # --- hunk 2: the boot call ------------------------------------------------
    if not any(re.search(r"\bCities\.boot\(", l) for l in lines):
        target = None
        for name in ("begin_world", "_ready"):
            hits = [i for i, l in enumerate(lines) if re.match(r"^func %s\(" % re.escape(name), l)]
            if len(hits) == 1:
                target = (name, hits[0])
                break
            if len(hits) > 1:
                return None, "hunk 2: `func %s(` matched %d times" % (name, len(hits))
        if target is None:
            return None, "hunk 2: neither begin_world() nor _ready() found"
        end = find_func_end(lines, target[1])
        # the marker rides the CALL line, not a comment above it: a guard that
        # looks for marker + call on one line must find them on one line
        lines.insert(end, "\t_cities = Cities.boot(self)    ## %s the big six stand up last, after the roster, the net and the crofts" % MARK)
        edits += 1
        notes.append("hunk 2 (boot) added at the end of %s()" % target[0])
    else:
        notes.append("hunk 2 (boot) already patched")

    # --- hunk 3: the accessor -------------------------------------------------
    if not any(re.match(r"^func cities\(", l) for l in lines):
        while lines and lines[-1].strip() == "":
            lines.pop()
        lines += ["", "",
                  "func cities() -> Node3D:    ## %s the built cities, or null before begin_world" % MARK,
                  "\treturn _cities",
                  ""]
        edits += 1
        notes.append("hunk 3 (accessor) added")
    else:
        notes.append("hunk 3 (accessor) already patched")

    return "\n".join(lines), "%d edits (%d markers were already present): %s" % (edits, already, "; ".join(notes))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--world", default="scripts/World.gd")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    src = open(a.world, encoding="utf-8").read()
    out, msg = patch(src)
    if out is None:
        print("REFUSED:", msg)
        sys.exit(1)
    print(msg)
    if out != src and not a.dry_run:
        open(a.world, "w", encoding="utf-8").write(out)
        print("wrote", a.world, "(+%d lines)" % (out.count("\n") - src.count("\n")))
    elif out == src:
        print("no change")
    sys.exit(0)


if __name__ == "__main__":
    main()
