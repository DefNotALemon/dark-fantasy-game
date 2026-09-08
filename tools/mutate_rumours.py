#!/usr/bin/env python3
"""tools/mutate_rumours.py -- prove RumourFeedTests can actually fail. [rumours]

A green suite is evidence about the suite, not only about the source. This
reintroduces, one at a time, each defect the feed is written to avoid, and
asserts the suite goes RED for it. A mutation that survives is either an
assertion that cannot fail or -- more usefully -- the name of a test nobody
wrote (2026-09-08: a mutation that would not die against the firepit turned out
to be a missing case, not a weak mutation).

    python3 tools/mutate_rumours.py

The source file is restored from an in-memory copy after every run and its md5
is checked at the end; a crash mid-run leaves scripts/RumourFeed.gd.mutbak
next to it.
"""

import hashlib
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "scripts", "RumourFeed.gd")
BAK = SRC + ".mutbak"
GODOT = "/Applications/Godot.app/Contents/MacOS/Godot"
SUITE = "res://tests/RumourFeedTests.gd"

# (name, what it breaks, old, new)
MUTATIONS = [
    ("earshot_is_spread",
     "overhearing at a day's walk instead of at the village",
     "const EARSHOT := 260.0",
     "const EARSHOT := 1400.0"),
    ("leave_keeps_queue",
     "talk follows you out into the woods",
     "\t_here = \"\"\n\t_queue.clear()",
     "\t_here = \"\"\n\t#_queue.clear()"),
    ("never_marks_heard",
     "the same rumour is told forever",
     "\tmark_heard(_here, text)",
     "\tpass"),
    ("mute_does_not_freeze",
     "a rumour is spent, and marked heard, behind an open map",
     "\tif _muted:\n\t\t## FROZEN",
     "\tif _muted and said < 0:\n\t\t## FROZEN"),
    ("heard_set_unbounded",
     "the save grows a rumour tail forever",
     "\twhile _heard_order.size() > HEARD_KEEP:\n\t\tvar old := String(_heard_order.pop_front())\n\t\t_heard.erase(old)\n\n\nfunc has_heard",
     "\twhile _heard_order.size() > 999999:\n\t\tvar old := String(_heard_order.pop_front())\n\t\t_heard.erase(old)\n\n\nfunc has_heard"),
    ("wildlife_beats_alarm",
     "wolves at the fold read as a nature documentary",
     "\t[\"raid\", Color(0.92, 0.34, 0.30)],",
     "\t[\"wolves\", Color(0.64, 0.76, 0.94)],\n\t[\"raid\", Color(0.92, 0.34, 0.30)],"),
    ("age_band_inclusive",
     "the age bands are off by their own edge",
     "\t\tif age_days < float(row[0]):",
     "\t\tif age_days <= float(row[0]):"),
    ("live_ignores_place",
     "you are told the news of a village you are not in",
     "\tif _here == \"\" or String(ev.get(\"place\", \"\")) != _here:",
     "\tif _here == \"\":"),
    ("no_stack_cap",
     "a wall of text instead of a glance",
     "\tif not _queue.is_empty() and _lines.size() < MAX_SHOWN and _gap_t <= 0.0:",
     "\tif not _queue.is_empty() and _gap_t <= 0.0:"),
    ("dwell_unclamped",
     "a three-word line flashes past and a long one parks",
     "\treturn clampf(float(text.length()) / READ_CPS + READ_LEAD, DWELL_MIN, DWELL_MAX)",
     "\treturn float(text.length()) / READ_CPS + READ_LEAD"),
    ("queue_allows_dupes",
     "the same word twice is two lines",
     "func _queued(k: String) -> bool:",
     "func _queued(k: String) -> bool:\n\tif said >= 0:\n\t\treturn false"),
    ("load_accepts_future",
     "a save from a newer build is half-read instead of refused",
     "\tif d.is_empty() or int(d.get(\"v\", 1)) > 1:\n\t\treturn",
     "\tif d.is_empty():\n\t\treturn"),
    ("key_drops_place",
     "hearing it at Bangor silences it at Ellsworth",
     "\treturn \"%s|%s\" % [place, text]",
     "\treturn text"),
    ("wrap_unbounded",
     "a 150-character rumour runs off the right-hand edge of the screen",
     "\treturn minf(clampf(vp_x * WRAP_FRAC, WRAP_MIN, WRAP_MAX), maxf(vp_x - MARGIN_X * 2.0, 80.0))",
     "\treturn vp_x * 4.0"),
    ("no_gap",
     "three days of gossip arrive in one frame",
     "\t\t_gap_t = GAP",
     "\t\t_gap_t = 0.0"),
]


def run_suite() -> int:
    p = subprocess.run([GODOT, "--headless", "--path", ROOT, "--script", SUITE],
                       capture_output=True, text=True, timeout=300)
    return p.returncode


def main() -> int:
    if not os.path.exists(GODOT):
        print("no Godot at %s" % GODOT)
        return 2
    with open(SRC, "r", encoding="utf-8") as fh:
        original = fh.read()
    md5 = hashlib.md5(original.encode("utf-8")).hexdigest()
    with open(BAK, "w", encoding="utf-8") as fh:
        fh.write(original)

    print("baseline: ", end="", flush=True)
    rc = run_suite()
    print("exit %d %s" % (rc, "(green)" if rc == 0 else "(RED -- fix the suite first)"))
    if rc != 0:
        return 1

    caught, survived = 0, []
    for name, why, old, new in MUTATIONS:
        n = original.count(old)
        if n != 1:
            survived.append("%s [anchor matched %d times]" % (name, n))
            print("  %-22s ANCHOR MISS (%d)" % (name, n))
            continue
        with open(SRC, "w", encoding="utf-8") as fh:
            fh.write(original.replace(old, new, 1))
        rc = run_suite()
        with open(SRC, "w", encoding="utf-8") as fh:
            fh.write(original)
        if rc != 0:
            caught += 1
            print("  %-22s caught   -- %s" % (name, why))
        else:
            survived.append(name)
            print("  %-22s SURVIVED -- %s" % (name, why))

    with open(SRC, "r", encoding="utf-8") as fh:
        back = hashlib.md5(fh.read().encode("utf-8")).hexdigest()
    print("\n%d/%d mutations caught; source restored (md5 %s, %s)"
          % (caught, len(MUTATIONS), back, "OK" if back == md5 else "MISMATCH!"))
    if survived:
        print("SURVIVED: %s" % ", ".join(survived))
        print("A mutation that will not die may be naming the test you never wrote.")
    if back == md5:
        os.remove(BAK)
    return 0 if (caught == len(MUTATIONS) and back == md5) else 1


if __name__ == "__main__":
    raise SystemExit(main())
