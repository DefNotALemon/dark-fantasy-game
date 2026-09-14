#!/usr/bin/env python3
"""
tools/mutate_carcasses.py -- is CarcassTests actually holding the carcass
economy to account, or is it 190 assertions that agree with anything?

    python3 tools/mutate_carcasses.py            # the whole sweep
    python3 tools/mutate_carcasses.py --list     # just name them

A GREEN SUITE IS EVIDENCE ABOUT THE SUITE. Each mutation below reintroduces
one defect the round was written to prevent, reruns CarcassTests headless,
and expects it to go RED. A mutation that SURVIVES is a hole in the suite --
or, three times now in this project, a test nobody had written yet.

Rules this file keeps, all learned the hard way in earlier rounds:
  * every mutation must match its source text EXACTLY ONCE, or the sweep
    reports it as MISSED rather than quietly skipping it;
  * the sources are restored from an in-memory copy in a `finally`, so an
    interrupted sweep cannot leave Lemon's tree mutated;
  * a baseline run has to be GREEN before any mutation is applied, because a
    sweep against an already-red suite catches everything and means nothing.
"""

import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = "/Applications/Godot.app/Contents/MacOS/Godot"
SUITE = "res://tests/CarcassTests.gd"

C = "scripts/Carcasses.gd"

# (name, file, old, new)
MUTATIONS = [
    # ---- the working-hours table: who is awake, and when -----------------
    ("gale no longer grounds the crows", C,
     '"from": -1.0, "to": -1.0, "cap": SKY_RAIN, "n": 4,',
     '"from": -1.0, "to": -1.0, "cap": SKY_STORM, "n": 4,'),
    ("crows keep a fixed window instead of following the daylight", C,
     '"from": -1.0, "to": -1.0, "cap": SKY_RAIN, "n": 4,',
     '"from": 0.0, "to": 24.0, "cap": SKY_RAIN, "n": 4,'),
    ("the bear never dens", C,
     "const BEAR_DENNED: Array = [false, false, false, true]",
     "const BEAR_DENNED: Array = [false, false, false, false]"),
    ("the pack works days", C,
     '"from": 20.0, "to": 5.0, "cap": SKY_STORM, "n": 3,',
     '"from": 6.0, "to": 19.0, "cap": SKY_STORM, "n": 3,'),
    ("the fox works days", C,
     '"from": 17.0, "to": 7.0, "cap": SKY_STORM, "n": 1,',
     '"from": 7.0, "to": 17.0, "cap": SKY_STORM, "n": 1,'),
    ("the sky cap is never consulted", C,
     '\tif sky > int(row["cap"]):\n\t\treturn false          ## a gale grounds the crows outright',
     '\tif false:\n\t\treturn false          ## a gale grounds the crows outright'),
    ("a window that crosses midnight is read as one that does not", C,
     '\treturn h >= a or h < b     ## a window that crosses midnight',
     '\treturn h >= a and h < b     ## a window that crosses midnight'),
    ("everybody works every hour", C,
     "static func works_now(g: int, hour: float, sky: int, season: int) -> bool:\n\t## Is this guild working at all, this hour, under this sky?",
     "static func works_now(g: int, hour: float, sky: int, season: int) -> bool:\n\treturn true\n\t## Is this guild working at all, this hour, under this sky?"),

    # ---- scent: the season and the sky reach the SEARCH -------------------
    ("scent forgets the season", C,
     '\treturn float(SEASON_SCENT[clampi(season, 0, 3)]) * float(SKY_SCENT[clampi(sky, 0, 4)])',
     '\treturn float(SKY_SCENT[clampi(sky, 0, 4)])'),
    ("scent forgets the sky", C,
     '\treturn float(SEASON_SCENT[clampi(season, 0, 3)]) * float(SKY_SCENT[clampi(sky, 0, 4)])',
     '\treturn float(SEASON_SCENT[clampi(season, 0, 3)])'),
    ("a frozen carcass smells like a summer one", C,
     "const SEASON_SCENT: Array = [1.00, 1.25, 1.00, 0.55]",
     "const SEASON_SCENT: Array = [1.00, 1.25, 1.00, 1.25]"),
    ("a gale carries scent as well as clear air", C,
     "const SKY_SCENT: Array = [1.00, 0.94, 0.80, 0.62, 0.44]",
     "const SKY_SCENT: Array = [1.00, 0.94, 0.80, 0.62, 1.00]"),
    ("rain carries scent better than drizzle", C,
     "const SKY_SCENT: Array = [1.00, 0.94, 0.80, 0.62, 0.44]",
     "const SKY_SCENT: Array = [1.00, 0.94, 0.80, 0.90, 0.44]"),
    ("the size of the animal does not draw anybody", C,
     '\treturn (STEP_HOURS / base) * scent(sky, season) * draw_of(mass)',
     '\treturn (STEP_HOURS / base) * scent(sky, season)'),
    ("the draw is unbounded at the top", C,
     "\treturn clampf(mass / DRAW_MASS, 0.35, 2.1)",
     "\treturn maxf(mass / DRAW_MASS, 0.35)"),
    ("and at the bottom", C,
     "\treturn clampf(mass / DRAW_MASS, 0.35, 2.1)",
     "\treturn minf(mass / DRAW_MASS, 2.1)"),

    # ---- the ground -------------------------------------------------------
    ("nothing ever rots", C,
     "const ROT_PER_DAY := 0.115",
     "const ROT_PER_DAY := 0.0"),
    ("August rots like spring", C,
     "const SEASON_ROT: Array = [1.00, 1.85, 0.80, 0.22]",
     "const SEASON_ROT: Array = [1.00, 1.00, 0.80, 0.22]"),
    ("February rots like August", C,
     "const SEASON_ROT: Array = [1.00, 1.85, 0.80, 0.22]",
     "const SEASON_ROT: Array = [1.00, 1.85, 0.80, 1.85]"),
    ("rot forgets the season", C,
     '\treturn mass * ROT_PER_DAY * float(SEASON_ROT[clampi(season, 0, 3)]) * (STEP_HOURS / 24.0)',
     '\treturn mass * ROT_PER_DAY * (STEP_HOURS / 24.0)'),

    # ---- the deposit ------------------------------------------------------
    ("mass goes as the square rather than the cube", C,
     "\treturn MASS_K * length_m * length_m * length_m",
     "\treturn MASS_K * length_m * length_m"),
    ("a deer is a different weight of animal", C,
     "const MASS_K := 10.0",
     "const MASS_K := 13.0"),
    ("a hare is too small to leave a carcass", C,
     "const MIN_MASS := 0.6 ",
     "const MIN_MASS := 2.0 "),
    ("and a squirrel is not", C,
     "const MIN_MASS := 0.6 ",
     "const MIN_MASS := 0.05 "),

    # ---- the stages -------------------------------------------------------
    ("a carcass reads as whole for longer than it is", C,
     "const OPENED_AT := 0.86",
     "const OPENED_AT := 0.50"),
    ("and as opened for longer", C,
     "const PICKED_AT := 0.55",
     "const PICKED_AT := 0.30"),
    ("bones start earlier", C,
     "const BONES_AT := 0.22",
     "const BONES_AT := 0.45"),
    ("nothing is ever gone", C,
     "\tif f > GONE_AT:\n\t\treturn STAGE_BONES",
     "\tif f >= 0.0:\n\t\treturn STAGE_BONES"),
    ("an unrecognised stage has no name", C,
     '\t\tSTAGE_BONES: return "bones"\n\treturn "gone"',
     '\t\tSTAGE_BONES: return "bones"\n\treturn ""'),

    # ---- THE FLOORS, which are the teeth ----------------------------------
    ("everybody wants any carcass at all", C,
     '\treturn float(rec.get("left", 0.0)) / mass > float((GUILDS[g] as Dictionary)["floor"])',
     '\treturn float(rec.get("left", 0.0)) > 0.0'),
    ("a coyote pack will walk to a picked-over carcass", C,
     '"find": 9.0, "rate": 3.5, "stay": 0.8, "floor": 0.18,',
     '"find": 9.0, "rate": 3.5, "stay": 0.8, "floor": 0.0,'),
    ("and so will a bear", C,
     '"find": 34.0, "rate": 9.5, "stay": 0.55, "floor": 0.30,',
     '"find": 34.0, "rate": 9.5, "stay": 0.55, "floor": 0.0,'),
    ("a bear wants no more of one than a coyote does", C,
     '"find": 34.0, "rate": 9.5, "stay": 0.55, "floor": 0.30,',
     '"find": 34.0, "rate": 9.5, "stay": 0.55, "floor": 0.10,'),
    ("butchery takes nothing off the ledger", C,
     '\tbest["left"] = float(best["left"]) - got',
     '\tbest["left"] = float(best["left"])'),
    ("butchery takes from the first carcass rather than the nearest", C,
     '\t\tif d <= bd:\n\t\t\tbd = d\n\t\t\tbest = rec\n\tif best.is_empty():',
     '\t\tif d <= radius and best.is_empty():\n\t\t\tbd = d\n\t\t\tbest = rec\n\tif best.is_empty():'),
    ("you can butcher more off a carcass than is on it", C,
     '\tvar got := minf(maxf(kg, 0.0), float(best.get("left", 0.0)))',
     '\tvar got := maxf(kg, 0.0)'),

    # ---- arrival is a STATE, and the bear evicts --------------------------
    ("the bear does not clear the table", C,
     "const BEAR_EVICTS := true",
     "const BEAR_EVICTS := false"),
    ("a guild that arrived never leaves", C,
     '\tif t > came + float((GUILDS[g] as Dictionary)["stay"]):\n\t\treturn false',
     '\tif false:\n\t\treturn false'),
    ("a guild is present before it arrives", C,
     "\tif t < came:\n\t\treturn false",
     "\tif false:\n\t\treturn false"),
    ("a guild stays at a carcass there is nothing left on", C,
     "\t\tif seen.has(bkey) and float(seen[bkey]) <= t:\n\t\t\treturn false\n\treturn wants_it(g, rec)",
     "\t\tif seen.has(bkey) and float(seen[bkey]) <= t:\n\t\t\treturn false\n\treturn true"),
    ("arrival is re-dated every step, so nobody ever arrived long ago", C,
     "\t\tif seen.has(key):\n\t\t\tcontinue\n\t\tif not wants_it(g, rec):",
     "\t\tif false:\n\t\t\tcontinue\n\t\tif not wants_it(g, rec):"),
    ("everybody eats around the clock", C,
     "\t\tif not works_now(g2, hour, sky, season):\n\t\t\tcontinue",
     "\t\tif false:\n\t\t\tcontinue"),

    # ---- the linger is dated from the ENDING ------------------------------
    ("bones are dated from the kill rather than from the stripping", C,
     '\t\t\trec["stripped"] = t',
     '\t\t\trec["stripped"] = float(rec.get("born", 0.0))'),
    ("bones do not linger", C,
     "const BONE_DAYS := 5.0",
     "const BONE_DAYS := 0.5"),
    ("a record is forgotten on a hard timer instead", C,
     "\tif stripped >= 0.0 and t > stripped + BONE_DAYS:\n\t\treturn true",
     '\tif t > float(rec.get("born", 0.0)) + BONE_DAYS:\n\t\treturn true'),

    # ---- the ingest -------------------------------------------------------
    ("a live animal leaves a carcass", C,
     '\t\tif not ("dying" in e) or not bool(e.get("dying")):\n\t\t\tcontinue',
     '\t\tif false:\n\t\t\tcontinue'),
    ("the same body is harvested twice", C,
     "\t\tif _known.has(iid):\n\t\t\tcontinue",
     "\t\tif false:\n\t\t\tcontinue"),
    ("anything that dies is wildlife", C,
     '\tif species == "":\n\t\treturn {}\n\tvar length := 1.0',
     '\tif species == "":\n\t\tspecies = "whitetail"\n\tvar length := 1.0'),
    ("the floor is not applied on the way in", C,
     "\tif mass < MIN_MASS:\n\t\treturn {}\n\tvar id := _next_id",
     "\tif false:\n\t\treturn {}\n\tvar id := _next_id"),

    # ---- the telling ------------------------------------------------------
    ("a carried rumour is re-dated to the day it was told", C,
     '\t\t\t"day": float(rec.get("born", days)),',
     '\t\t\t"day": days,'),
    ("nothing is worth telling a village about", C,
     "const TELL_MIN_MASS := 12.0",
     "const TELL_MIN_MASS := 100000.0"),
    ("a dead hare is news at the tavern", C,
     "const TELL_MIN_MASS := 12.0",
     "const TELL_MIN_MASS := 0.0"),
    ("a bear and a pack are the same news", C,
     '\t\t"bear":\n\t\t\treturn "A bear has a dead %s out that way. Give that ground a wide berth." % nm',
     '\t\t"bear":\n\t\t\treturn "Coyotes were singing over a dead %s out that way." % nm'),
    ("a carcass is offered to the feed with no speaker over it", C,
     '\tif bool(feed.call("offer", legible(rec2, days), String(rec2.get("nm", "")), "carcass", days)):',
     '\tif bool(feed.call("offer", legible(rec2, days), "", "carcass", days)):'),
    ("every carcass reads the same however far down it is", C,
     '\tmatch st:\n\t\tSTAGE_WHOLE:\n\t\t\treturn "A dead %s, not long down and not yet found." % nm',
     '\tmatch st:\n\t\tSTAGE_WHOLE:\n\t\t\treturn "A dead %s, opened up. Something has been here." % nm'),

    # ---- the save ---------------------------------------------------------
    ("the search accumulators are not saved", C,
     '\t\t\t"prog": (rec["prog"] as Dictionary).duplicate(),',
     '\t\t\t"prog": {},'),
    ("who has already been is not saved", C,
     '\t\t\t"seen": (rec["seen"] as Dictionary).duplicate(),\n\t\t\t"prog": (rec["prog"] as Dictionary).duplicate(),\n\t\t\t"took": (rec["took"] as Dictionary).duplicate(),\n\t\t\t"stripped": float(rec.get("stripped", -1.0)),',
     '\t\t\t"seen": {},\n\t\t\t"prog": (rec["prog"] as Dictionary).duplicate(),\n\t\t\t"took": (rec["took"] as Dictionary).duplicate(),\n\t\t\t"stripped": float(rec.get("stripped", -1.0)),'),
    ("a reload puts the clock back to zero", C,
     '\t_hours = float(d.get("hours", 0.0))\n\tdays = _hours / 24.0\n\t_steps = int(d.get("steps", 0))',
     '\t_hours = float(d.get("hours", 0.0))\n\tdays = _hours / 24.0\n\t_steps = 0'),

    # ---- the bodies -------------------------------------------------------
    ("everything in the county is staged at once", C,
     "const STAGE_RADIUS := 260.0",
     "const STAGE_RADIUS := 1000000.0"),
    ("nothing is ever staged", C,
     "const STAGE_RADIUS := 260.0",
     "const STAGE_RADIUS := 0.0"),
    ("the grass under a body is mown again on every scan", C,
     "\tif _mown.has(key):\n\t\treturn\n\t_mown[key] = true",
     "\tif false:\n\t\treturn"),
    ("the mown circle is a constant instead of the animal's own size", C,
     "\treturn clampf(length_m * MOW_PER_M, MOW_MIN, MOW_MAX)",
     "\treturn MOW_MIN"),
    ("a hare flattens as much meadow as a moose", C,
     "const MOW_MIN := 1.6 ",
     "const MOW_MIN := 6.9 "),
    ("a body is built twice for the same carcass", C,
     "\t\tif _staged.has(id2) or held.has(id2):\n\t\t\tcontinue",
     "\t\tif held.has(id2):\n\t\t\tcontinue"),
    ("a body is staged over a corpse that is still settling", C,
     "\t\tif _staged.has(id2) or held.has(id2):\n\t\t\tcontinue",
     "\t\tif _staged.has(id2):\n\t\t\tcontinue"),
    ("a settled corpse is never read", C,
     "\t\tif skin.ragdoll or not skin.frozen:\n\t\t\tcontinue              ## still falling",
     "\t\tif true:\n\t\t\tcontinue              ## still falling"),
    ("a taken bone is not written on the record", C,
     "\t\t\t\ttaken[String(bk)] = true",
     "\t\t\t\tpass"),
    ("the save drops the pose", C,
     "\t\t\t\"pose\": _pose_packed(rec.get(\"pose\", null)),",
     "\t\t\t\"pose\": PackedFloat32Array(),"),
    ("the save drops the taken bones", C,
     "\t\t\t\"bones\": (rec.get(\"bones\", {}) as Dictionary).duplicate(),\n\t\t})",
     "\t\t\t\"bones\": {},\n\t\t})"),
]


def run_suite(timeout=300):
    r = subprocess.run(
        [GODOT, "--headless", "--path", ROOT, "--script", SUITE],
        capture_output=True, text=True, timeout=timeout)
    return r.returncode, r.stdout


def main():
    if "--list" in sys.argv:
        for i, (nm, f, _o, _n) in enumerate(MUTATIONS, 1):
            print("%2d. [%s] %s" % (i, f, nm))
        print("\n%d mutations" % len(MUTATIONS))
        return 0

    files = sorted({m[1] for m in MUTATIONS})
    originals = {}
    for f in files:
        with open(os.path.join(ROOT, f)) as fh:
            originals[f] = fh.read()

    print("=== baseline ===", flush=True)
    rc, out = run_suite()
    tail = [l for l in out.splitlines() if "passed" in l]
    print((tail[-1] if tail else out.strip()[-200:]), flush=True)
    if rc != 0:
        print("BASELINE IS RED -- a sweep against a red suite catches everything "
              "and means nothing. Fix the suite first.", flush=True)
        return 2

    caught, survived, missed = 0, [], []
    try:
        for i, (name, rel, old, new) in enumerate(MUTATIONS, 1):
            src = originals[rel]
            n = src.count(old)
            if n != 1:
                missed.append((i, name, n))
                print("%2d. MISSED (%d matches) %s" % (i, n, name), flush=True)
                continue
            with open(os.path.join(ROOT, rel), "w") as fh:
                fh.write(src.replace(old, new))
            try:
                rc, out = run_suite()
            finally:
                with open(os.path.join(ROOT, rel), "w") as fh:
                    fh.write(originals[rel])
            if rc != 0:
                caught += 1
                print("%2d. caught   %s" % (i, name), flush=True)
            else:
                survived.append((i, name))
                print("%2d. SURVIVED %s" % (i, name), flush=True)
    finally:
        for f in files:
            with open(os.path.join(ROOT, f), "w") as fh:
                fh.write(originals[f])

    print("\n=== %d/%d caught ===" % (caught, len(MUTATIONS)), flush=True)
    for i, nm in survived:
        print("  SURVIVED %2d. %s" % (i, nm), flush=True)
    for i, nm, n in missed:
        print("  MISSED   %2d. %s (%d matches)" % (i, nm, n), flush=True)

    print("\n=== restored, verifying baseline again ===", flush=True)
    rc, out = run_suite()
    tail = [l for l in out.splitlines() if "passed" in l]
    print((tail[-1] if tail else out.strip()[-200:]), flush=True)
    return 0 if (not survived and not missed and rc == 0) else 1


if __name__ == "__main__":
    sys.exit(main())
