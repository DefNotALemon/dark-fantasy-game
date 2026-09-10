#!/usr/bin/env python3
"""tools/mutate_crofts.py -- prove CroftTests can actually go red.

    python3 tools/mutate_crofts.py            # the whole sweep
    python3 tools/mutate_crofts.py <name> ... # just these

A green suite is evidence about the SUITE, not only about the source. Each
mutation below reintroduces one specific defect into scripts/Crofts.gd, runs
the suite, and expects it to FAIL. A mutation that survives is a finding: it
names a test that does not exist, a redundancy worth writing down, or dead
code worth deleting -- and on this project all three have happened.

The file is restored from a byte copy after every mutation and the restore is
sha-verified, because a sweep that leaves the source mutated is worse than no
sweep at all.
"""

import hashlib
import pathlib
import shutil
import subprocess
import sys
import tempfile

GODOT = "/Applications/Godot.app/Contents/MacOS/Godot"
SRC = pathlib.Path("scripts/Crofts.gd")
SUITE = "res://tests/CroftTests.gd"

# name, old, new
MUTATIONS = [
    ("seat-any-road",
     "\tif length < MIN_ROAD_M:\n\t\treturn 0",
     "\tif length < 0.0:\n\t\treturn 0"),
    ("seat-unsorted",
     '\trows.sort_custom(func(x, y): return String(x["key"]) < String(y["key"]))',
     '\trows.sort_custom(func(x, y): return int(x["e"]) > int(y["e"]))'),
    ("seat-into-village",
     "\t\tlo = maxf(T_MIN, CLEAR_OF_PLACE / length)",
     "\t\tlo = maxf(T_MIN, 0.0 / length)"),
    ("yard-on-the-road",
     "\tvar off := OFF_MIN + (OFF_MAX - OFF_MIN) * _unit(h, 2)",
     "\tvar off := OFF_MIN * 0.05"),
    ("side-never-moves",
     "\tif b > a + SIDE_MARGIN:",
     "\tif b > a + 100000.0:"),
    ("names-collide",
     "\t\t\tif not used.has(cand):",
     "\t\t\tif true:"),
    ("hearth-never-out",
     '\tvar hearth := "out"\n\tif stores > 0.0:',
     '\tvar hearth := "out"\n\tif stores >= 0.0:'),
    ("never-banks",
     '\t\thearth = "lit" if (awake and hour < bed - BANK_BEFORE_BED) else "banked"',
     '\t\thearth = "lit" if awake else "banked"'),
    ("storm-leaves-shutters",
     '\tvar shutters := "shut" if (not awake or lv >= SKY_STORM or shut) else "open"',
     '\tvar shutters := "shut" if (not awake or shut) else "open"'),
    ("beasts-out-in-rain",
     "\t\telif lv <= FIELD_MAX_SKY and hour >= rise + STOCK_OUT_AFTER",
     "\t\telif lv <= 4 and hour >= rise + STOCK_OUT_AFTER"),
    ("winter-beasts-any-sky",
     "\t\t\tif lv == SKY_CLEAR and hour >= WINTER_OUT_FROM and hour < WINTER_OUT_TO:",
     "\t\t\tif hour >= WINTER_OUT_FROM and hour < WINTER_OUT_TO:"),
    ("storm-only-under-cover",
     '\t\t\tif lv >= SKY_STORM:\n\t\t\t\twork = "in"',
     '\t\t\tif lv >= SKY_STORM:\n\t\t\t\twork = "byre"'),
    ("rain-does-not-drive-in",
     "\t\t\telif lv >= WORK_IN_SKY:",
     "\t\t\telif lv >= 99:"),
    ("empty-pile-ignored",
     "\t\tif stores <= 0.0 and not shut:",
     "\t\tif false and not shut:"),
    ("wash-fetch-beats-soak",
     '\tif on_line == "out" and sky >= SOAK_SKY:\n\t\ton_line = "wet"\n\t\tst["dry_h"] = 0.0\n\telif on_line == "out" and String(r["wash_intent"]) == "fetch":\n\t\ton_line = "none"',
     '\tif on_line == "out" and String(r["wash_intent"]) == "fetch":\n\t\ton_line = "none"\n\telif on_line == "out" and sky >= SOAK_SKY:\n\t\ton_line = "wet"\n\t\tst["dry_h"] = 0.0'),
    ("washing-in-winter",
     "\tif se != 3 and not shut and not wet:",
     "\tif not shut and not wet:"),
    ("wet-line-reused",
     "\tif se != 3 and not shut and not wet:",
     "\tif se != 3 and not shut:"),
    ("rain-dries-washing",
     '\t\tif sky <= WASH_MAX_SKY:\n\t\t\tst["dry_h"] = float(st.get("dry_h", 0.0)) + STEP_HOURS',
     '\t\tif sky <= 4:\n\t\t\tst["dry_h"] = float(st.get("dry_h", 0.0)) + STEP_HOURS'),
    ("flat-season-burn",
     "const SEASON_BURN: Array = [1.00, 0.55, 1.15, 1.60]",
     "const SEASON_BURN: Array = [1.00, 1.00, 1.00, 1.00]"),
    ("flat-season-gather",
     "const SEASON_GATHER: Array = [1.65, 0.75, 1.55, 0.85]",
     "const SEASON_GATHER: Array = [1.00, 1.00, 1.00, 1.00]"),
    ("pile-unbounded",
     '\tst["stores"] = clampf(s, 0.0, STORE_MAX)',
     '\tst["stores"] = s'),
    ("cold-signal-spams",
     '\t\tif not bool(st.get("was_cold", false)):',
     "\t\tif true:"),
    ("alarm-every-step",
     '\tvar d := floorf(t)\n\tif d <= float(st.get("alarm_day", -1.0)):\n\t\treturn',
     '\tvar d := floorf(t)\n\tif false:\n\t\treturn'),
    ("alarm-never-fires",
     "\tif worst < SHUT_PRESSURE:\n\t\treturn",
     "\tif worst < 100.0:\n\t\treturn"),
    ("save-keeps-strangers",
     '\t\t\tif not _by_id.has(String(id)):\n\t\t\t\tcontinue',
     '\t\t\tif false:\n\t\t\t\tcontinue'),
    ("save-mints-firewood",
     '\t\t\t\t"stores": clampf(float(row.get("stores", STORE_START)), 0.0, STORE_MAX),',
     '\t\t\t\t"stores": float(row.get("stores", STORE_START)),'),
    ("croft-narrates-itself",
     "\tif _said.has(key):\n\t\treturn",
     "\tif false:\n\t\treturn"),
    ("heard-from-a-mile-off",
     "\tvar rows := near(player.global_position, NOTICE_M)",
     "\tvar rows := near(player.global_position, 1000000.0)"),
    ("never-strikes",
     '\t\tif c.is_empty() or (c["pos"] as Vector2).distance_to(here) > STRIKE_RADIUS:',
     '\t\tif c.is_empty() or (c["pos"] as Vector2).distance_to(here) > 1000000.0:'),
    ("stage-uncapped",
     "\tfor row in near(pos, STAGE_RADIUS):\n\t\tif _staged.size() >= MAX_STAGED:",
     "\tfor row in near(pos, STAGE_RADIUS):\n\t\tif false:"),
    ("shieling-grows-corn",
     '\tif kind == "shieling":\n\t\treturn 0.0\n\tvar within := fposmod(day, DAYS_PER_SEASON) / DAYS_PER_SEASON',
     '\tvar within := fposmod(day, DAYS_PER_SEASON) / DAYS_PER_SEASON'),
    ("no-harvest",
     "\t\tif within < 0.62:\n\t\t\treturn 1.0",
     "\t\tif within < 99.0:\n\t\t\treturn 1.0"),
]


def sha(p: pathlib.Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def run_suite() -> bool:
    """True when the suite is GREEN."""
    r = subprocess.run([GODOT, "--headless", "--path", ".", "--script", SUITE],
                       capture_output=True, text=True)
    return r.returncode == 0


def main() -> int:
    if not SRC.exists():
        print("mutate_crofts: %s not found (run me from the project root)" % SRC)
        return 2
    wanted = [a for a in sys.argv[1:] if not a.startswith("-")]
    rows = [m for m in MUTATIONS if not wanted or m[0] in wanted]

    baseline_sha = sha(SRC)
    backup = pathlib.Path(tempfile.gettempdir()) / "Crofts.gd.mutbak"
    shutil.copy2(SRC, backup)

    print("mutate_crofts: baseline suite must be GREEN before anything else...")
    if not run_suite():
        print("mutate_crofts: BASELINE IS RED. Fix that first; a sweep against a red")
        print("               suite proves nothing at all.")
        return 2
    print("mutate_crofts: baseline green. %d mutations.\n" % len(rows))

    caught, survived, unapplied = [], [], []
    original = SRC.read_text()
    for name, old, new in rows:
        n = original.count(old)
        if n != 1:
            unapplied.append("%s (anchor matched %d times)" % (name, n))
            print("  ????  %-24s anchor matched %d times" % (name, n))
            continue
        SRC.write_text(original.replace(old, new, 1))
        green = run_suite()
        SRC.write_text(original)
        if sha(SRC) != baseline_sha:
            print("mutate_crofts: RESTORE FAILED after %s -- stopping" % name)
            shutil.copy2(backup, SRC)
            return 2
        if green:
            survived.append(name)
            print("  SURVIVED  %-24s <-- the suite did not notice" % name)
        else:
            caught.append(name)
            print("  caught    %s" % name)

    print("\nmutate_crofts: %d caught, %d survived, %d unapplied of %d"
          % (len(caught), len(survived), len(unapplied), len(rows)))
    if survived:
        print("SURVIVORS: %s" % ", ".join(survived))
    if unapplied:
        print("UNAPPLIED: %s" % ", ".join(unapplied))
    print("source sha %s (unchanged: %s)" % (sha(SRC)[:12], sha(SRC) == baseline_sha))
    return 0 if not survived and not unapplied else 1


if __name__ == "__main__":
    raise SystemExit(main())
