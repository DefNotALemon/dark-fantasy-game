#!/usr/bin/env python3
"""mutate_cities.py — does CityTests actually bite?

Applies one deliberate defect at a time to a COPY of scripts/Cities.gd,
runs tests/CityTests.gd against it, and expects red. A mutation that
survives names an assertion that does not exist.

    python3 tools/mutate_cities.py [--godot /path/to/godot] [--project .]

Each mutation is (name, old, new): `old` must occur exactly once in the
source or the mutation is reported as MISSING (the anchor moved — fix the
mutator, do not skip it).
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

MUTATIONS = [
    ("build-unsorted", "\tnames.sort()\n\tfor nm in names:\n\t\tvar tier: int", "\tfor nm in names:\n\t\tvar tier: int"),
    ("far-end-on-top-of-us", "if pv != null and (pv as Vector2).distance_to(here) > 1.0:", "if pv != null:"),
    ("lamps-and-not-or", "return h >= LAMP_ON_HOUR or h < LAMP_OFF_HOUR", "return h >= LAMP_ON_HOUR and h < LAMP_OFF_HOUR"),
    ("mow-inside-wall", "var r: float = float(c[\"core_r\"]) * (1.0 + WALL_JITTER * 0.5) + MOW_PAD", "var r: float = float(c[\"core_r\"])"),
    ("gates-never-merge", "if absf(rad_to_deg((e as Vector2).angle_to(v))) < GATE_MERGE_DEG:", "if absf(rad_to_deg((e as Vector2).angle_to(v))) < 0.0:"),
    ("one-gate-is-fine", "while dirs.size() < MIN_GATES:", "while false:"),
    ("build-on-water", "\t\t\t\t\trejected[\"water\"] += 1\n\t\t\t\t\tcontinue", "\t\t\t\t\tpass"),
    ("build-on-cliffs", "if ymax - ymin > SLOPE_MAX:", "if ymax - ymin > INF:"),
    ("lots-overlap", "\t\t\t\tif overlaps:\n\t\t\t\t\trejected[\"overlap\"] += 1\n\t\t\t\t\tcontinue", "\t\t\t\tif false:\n\t\t\t\t\tcontinue"),
    ("own-street-cuts-in", "if dist_to_polyline(pl, c) < STREET_W * 0.5 + LOT_SETBACK + d * 0.5 - 0.3:", "if false:"),
    ("no-hysteresis", "elif d > STRIKE_RADIUS and _staged.has(nm):", "elif d > STAGE_RADIUS and _staged.has(nm):"),
    ("stage-twice", "\tif _staged.has(city):\n\t\treturn _staged[city]\n\tif not cities.has(city):", "\tif not cities.has(city):"),
    ("staged-dark-at-night", "\t_apply_lamps(root, _lit)\n\t_mow(c)", "\t_mow(c)"),
    ("roster-ignored", "\tif _rows.size() > 0:\n\t\troster_source = \"world\"", "\tif false:\n\t\troster_source = \"world\""),
    ("inn-off-main-street", "if int(lots[i][\"street\"]) == 0 and (lots[i][\"pos\"] as Vector2).length() > best:", "if int(lots[i][\"street\"]) == 1 and (lots[i][\"pos\"] as Vector2).length() > best:"),
    ("doors-face-away", "\"yaw\": atan2(to_street.x, to_street.y),", "\"yaw\": atan2(-to_street.x, -to_street.y),"),
    ("hash-ignores-name", "var v: int = hash(\"%d|%s|%d\" % [wseed, city, k])", "var v: int = hash(\"%d|%s|%d\" % [wseed, \"\", k])"),
    ("hash-unfinished", "\tv = (v ^ (v >> 33)) * -49064778989728563\n\tv = (v ^ (v >> 33)) * -4265267296055464877\n\tv = v ^ (v >> 33)\n", ""),
    ("set-hour-forgets", "\thour_override = hour\n\tvar lit := lamps_lit(hour)", "\tvar lit := lamps_lit(hour)"),
    ("tick-ignores-y-plane", "var d := Vector2(pp.x - c.x, pp.z - c.z).length()\n\t\t\tif d < STAGE_RADIUS", "var d := (pp - c).length()\n\t\t\tif d < STAGE_RADIUS"),
    ("bad-net-kept", "if net.has_method(\"edges_from\") and net.has_method(\"place_pos\"):", "if net.has_method(\"edges_from\"):"),
    ("rebuild-leaves-stale", "\tfor nm in _staged.keys().duplicate():\n\t\tstrike(nm)\n\n\n## Rebuild", "\n\n## Rebuild"),
    ("rings-are-circles", "\t\tfor v in wall:\n\t\t\tring.append(v * float(f))", "\t\tfor v in wall:\n\t\t\tring.append(Vector2(1.0, 0.0).rotated(v.angle()) * v.length() * float(f) * 0.9)"),
    ("towers-missing", "\t\t\t_tower(holder, left, h, m, \"TowerL%d\" % i)\n", ""),
]


def run(godot, project, src_override=None):
    with tempfile.TemporaryDirectory() as td:
        dst = os.path.join(td, "p")
        shutil.copytree(project, dst, ignore=shutil.ignore_patterns(".godot", "shots", "*.png", "__pycache__"))
        if src_override is not None:
            with open(os.path.join(dst, "scripts", "Cities.gd"), "w") as f:
                f.write(src_override)
        subprocess.run([godot, "--headless", "--path", dst, "--import"], capture_output=True, timeout=300)
        r = subprocess.run([godot, "--headless", "--path", dst, "--script", "res://tests/CityTests.gd"],
                           capture_output=True, text=True, timeout=300)
        tail = [l for l in r.stdout.splitlines() if l.startswith("CityTests:")]
        return r.returncode, (tail[-1] if tail else r.stdout[-300:] + r.stderr[-300:])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    ap.add_argument("--project", default=".")
    ap.add_argument("--only", default=None)
    a = ap.parse_args()
    src = open(os.path.join(a.project, "scripts", "Cities.gd")).read()
    rc, line = run(a.godot, a.project)
    print("baseline:", "GREEN" if rc == 0 else "RED", "—", line)
    if rc != 0:
        print("baseline is red; fix that first")
        sys.exit(2)
    caught = 0
    survived = []
    missing = []
    for name, old, new in MUTATIONS:
        if a.only and a.only != name:
            continue
        n = src.count(old)
        if n != 1:
            print("  MISSING %-24s anchor occurs %d times" % (name, n))
            missing.append(name)
            continue
        mutated = src.replace(old, new)
        rc, line = run(a.godot, a.project, mutated)
        if rc != 0:
            caught += 1
            print("  caught  %-24s %s" % (name, line))
        else:
            survived.append(name)
            print("  SURVIVED %-23s %s" % (name, line))
    print("")
    print("mutations: %d caught, %d survived, %d missing" % (caught, len(survived), len(missing)))
    for s in survived:
        print("  survivor:", s)
    sys.exit(1 if survived or missing else 0)


if __name__ == "__main__":
    main()
