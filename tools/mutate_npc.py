#!/usr/bin/env python3
"""Mutation sweep for tests/NPCTests.gd — does the suite actually bite?

    python3 tools/mutate_npc.py [--godot PATH] [--only NAME]

Each mutation edits ONE thing in a real source file, runs the suite, and
expects it RED; the file is restored byte-for-byte (sha-checked) whatever
happens. Baseline must be green first, or every "caught" is a lie.
"""
import argparse
import hashlib
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SUITE = "res://tests/NPCTests.gd"

MUTATIONS = [
    # name, file, old, new
    ("aggro-on-proximity", "scripts/NPC.gd", "\taggro_radius = 0.0            ## NEVER", "\taggro_radius = 7.0            ## NEVER"),
    ("cadence-not-players", "scripts/NPC.gd", "\tgait_rate = (4.5 + h * 1.35) / (2.0 + minf(h, 9.0) * 2.4)", "\tgait_rate = 1.0"),
    ("stride-too-small", "scripts/NPC.gd", "\tvar amp := 0.5 * clampf(0.55 + 0.45 * hspeed / RUN_SPEED, 0.0, 1.0) * _gait_k", "\tvar amp := 0.3 * clampf(0.55 + 0.45 * hspeed / RUN_SPEED, 0.0, 1.0) * _gait_k"),
    ("hello-every-minute", "scripts/NPC.gd", "\t\t\tand greeted_day != day_now() and not weapon_out and mode != Mode.SLEEP:", "\t\t\tand not weapon_out and mode != Mode.SLEEP:"),
    ("everyone-fights", "scripts/NPC.gd", "\tif courage >= 0.55 or job == \"guard\":\n\t\tmake_hostile()", "\tif courage >= 0.0 or job == \"guard\":\n\t\tmake_hostile()"),
    ("never-cowers", "scripts/NPC.gd", "const COWER_R := 2.2", "const COWER_R := 0.0"),
    ("sit-half-way", "scripts/NPC.gd", "\t\t\t\thl = Vector3(1.5, 0.0, 0.05)", "\t\t\t\thl = Vector3(0.5, 0.0, 0.05)"),
    ("sleep-standing", "scripts/NPC.gd", "\t\t\t\trig_rx = PI * 0.5", "\t\t\t\trig_rx = 0.0"),
    ("witnesses-blind", "scripts/NPC.gd", "\t\tif o.global_position.distance_to(global_position) > 25.0:", "\t\tif o.global_position.distance_to(global_position) > 0.0:"),
    ("death-unreported", "scripts/NPC.gd", "\t\tdir.call(\"on_npc_died\", self, _hit_by_player)", "\t\tpass"),
    ("punch-not-snapped", "scripts/NPC.gd", "\t\t\tsp = Vector3(-0.10 + Enemy._cut_arc(p, 0.0, 0.10, -0.22), Enemy._cut_arc(p, 0.0, 0.35, -0.40), 0.0)\n\t\t\tsnap = true", "\t\t\tsp = Vector3(-0.10 + Enemy._cut_arc(p, 0.0, 0.10, -0.22), Enemy._cut_arc(p, 0.0, 0.35, -0.40), 0.0)\n\t\t\tsnap = false"),
    ("null-attacker-not-player", "scripts/NPC.gd", "\tvar by_player := attacker == null or (attacker != null and attacker.is_in_group(\"player\"))", "\tvar by_player := attacker != null and attacker.is_in_group(\"player\")"),
    ("head-no-clamp", "scripts/NPC.gd", "\t\t\t\tclampf(yaw, -LOOK_YAW_MAX, LOOK_YAW_MAX))", "\t\t\t\tyaw)"),
    ("unknown-term-true", "scripts/NPCDialogue.gd", "\t\t\t\t\t\t\treturn is_equal_approx(v, num)\n\treturn false", "\t\t\t\t\t\t\treturn is_equal_approx(v, num)\n\treturn true"),
    ("openers-ignored", "scripts/NPCDialogue.gd", "\tfor o in tree.get(\"openers\", []):\n\t\tif o is Dictionary and eval_cond", "\tfor o in []:\n\t\tif o is Dictionary and eval_cond"),
    ("extra-choice-after-farewell", "scripts/NPCDialogue.gd", "\tout.insert(maxi(0, out.size() - 1), extra)", "\tout.append(extra)"),
    ("e-takes-first", "scripts/NPCFocus.gd", "\t_pick(choices[choices.size() - 1])", "\t_pick(choices[0])"),
    ("guard-never-yields", "scripts/NPCFocus.gd", "\tif player == null or _rmb_is_guard():\n\t\treturn false\n\tif talking != null or focused != null:\n\t\treturn true", "\tif player == null or _rmb_is_guard():\n\t\treturn false\n\tif talking != null or focused != null:\n\t\treturn false"),
    ("twin-not-swallowed", "scripts/NPCFocus.gd", "\tif _twin_lock > 0.0:\n\t\treturn true   ## the pad's Square", "\tif false:\n\t\treturn true   ## the pad's Square"),
    ("focus-with-steel-out", "scripts/NPCFocus.gd", "\treturn st < 0.5 and (w == \"sword\" or w == \"bow\")", "\treturn false"),
    ("restage-where-left", "scripts/NPCDirector.gd", "\tif rec.has(\"unstaged_hour\") and away > RESTAGE_HOURS:", "\tif false and rec.has(\"unstaged_hour\") and away > RESTAGE_HOURS:"),
    ("never-unstages", "scripts/NPCDirector.gd", "const UNSTAGE_R := 160.0", "const UNSTAGE_R := 100000.0"),
    ("dead-restage", "scripts/NPCDirector.gd", "\t\tif bool(rec.get(\"dead\", false)):\n\t\t\tcontinue", "\t\tif false:\n\t\t\tcontinue"),
    ("save-drops-live-bodies", "scripts/NPCDirector.gd", "\treturn {\"records\": records.duplicate(true), \"crimes\": crimes, \"next_id\": _next_id}", "\treturn {\"records\": records, \"crimes\": crimes, \"next_id\": _next_id}"),
]


def sha(b):
    return hashlib.sha256(b).hexdigest()


def run_suite(godot):
    r = subprocess.run([godot, "--headless", "--path", ROOT, "--script", SUITE],
                       capture_output=True, text=True, timeout=900)
    return r.returncode, r.stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    ap.add_argument("--only", default=None)
    a = ap.parse_args()
    rc, out = run_suite(a.godot)
    if rc != 0:
        print("BASELINE IS RED — fix the suite first")
        print(out[-2000:])
        sys.exit(2)
    print("baseline green")
    caught = 0
    total = 0
    for name, rel, old, new in MUTATIONS:
        if a.only and a.only != name:
            continue
        total += 1
        path = os.path.join(ROOT, rel)
        with open(path, "rb") as f:
            orig = f.read()
        text = orig.decode("utf-8")
        if text.count(old) != 1:
            print("  %-28s SKIP: anchor matches %d times" % (name, text.count(old)))
            continue
        try:
            with open(path, "wb") as f:
                f.write(text.replace(old, new, 1).encode("utf-8"))
            rc, out = run_suite(a.godot)
            red = rc != 0
            fails = [l.strip() for l in out.split("\n") if l.strip().startswith("FAIL:")]
            print("  %-28s %s %s" % (name, "caught" if red else "SURVIVED", ("(%s)" % fails[0][:70]) if fails else ""))
            if red:
                caught += 1
        finally:
            with open(path, "wb") as f:
                f.write(orig)
            with open(path, "rb") as f:
                if sha(f.read()) != sha(orig):
                    print("RESTORE FAILED for", rel)
                    sys.exit(3)
    print("%d / %d mutations caught" % (caught, total))
    sys.exit(0 if caught == total else 1)


if __name__ == "__main__":
    main()
