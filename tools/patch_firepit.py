#!/usr/bin/env python3
"""
patch_firepit.py -- wire the burning firepit into Player.gd and open two
public accessors on Weather.gd.  2026-09-08, SYSTEMS DEPTH.

Additive only.  Idempotent.  Every insertion is guarded on a marker that can
only appear in the thing being inserted -- a function guard is `func <name>`,
never a bare name, because a guard that also matches the CALL you just wrote
makes the next run skip the definition and leave the file referencing a
function that does not exist (2026-09-05 09:00, and again 2026-09-08 00:00).

    python3 tools/patch_firepit.py            # patch
    python3 tools/patch_firepit.py --dry-run  # report only, write nothing

Player.gd carries thousands of lines of Lemon's own uncommitted work.  This
script never removes a line, never reorders one, and refuses to write at all
unless every anchor matches EXACTLY ONCE.
"""

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLAYER = os.path.join(ROOT, "scripts", "Player.gd")
WEATHER = os.path.join(ROOT, "scripts", "Weather.gd")
FIREPIT = os.path.join(ROOT, "scripts", "Firepit.gd")

DRY = "--dry-run" in sys.argv

T = "\t"

# --------------------------------------------------------------------- pieces

VAR_DECL = (
    'var _fire_target: Firepit = null        '
    '## a fire pit under the gaze (E = light / feed)\n'
)

KEY_E_BRANCH = (
    '\t\t\t\telif menu_open == "" and kd_phase == "" and _fire_target != null \\\n'
    '\t\t\t\t\t\tand is_instance_valid(_fire_target):\n'
    '\t\t\t\t\t_use_firepit(_fire_target)   ## [fire]\n'
)

TARGET_RESET = '\t_fire_target = null\n'

FIRE_SCAN = '''
\tif _log_target != null:
\t\treturn
\t## And a fire pit. E lights it, feeds it, or tells you what it wants. The
\t## cone is a touch wider than the others because a firepit is a two-metre
\t## ring of stones and you are usually standing right in it.
\tvar fbest := 0.84
\tfor n in get_tree().get_nodes_in_group("fires"):
\t\tvar fp := n as Firepit
\t\tif fp == null:
\t\t\tcontinue
\t\tvar to := fp.here() + Vector3.UP * 0.3 - _aim_origin()
\t\tvar dist := to.length()
\t\tif dist > 3.4 or dist < 0.05:
\t\t\tcontinue
\t\tvar d := fwd.dot(to.normalized())
\t\tif d > fbest:
\t\t\tfbest = d
\t\t\t_fire_target = fp
'''

PROMPT_VISIBLE_OLD = (
    '\t\tpickup_prompt.visible = _drop_target != null or _bed_target != null \\\n'
    '\t\t\tor _debris_target != null or _log_target != null or _water_target != Vector3.INF\n'
)
PROMPT_VISIBLE_ADD = (
    '\t\tpickup_prompt.visible = pickup_prompt.visible or _fire_target != null   ## [fire]\n'
)

PROMPT_TEXT = '''\t\telif _fire_target != null:
\t\t\tif _fire_target.burning():
\t\t\t\tpickup_prompt.text = "[E]  Feed the fire   ·   %s, %d min" \\
\t\t\t\t\t% [_fire_target.state_name(), int(_fire_target.minutes_left())]
\t\t\telif not _fire_target.can_light():
\t\t\t\tpickup_prompt.text = "Too wild a wind to strike a light"
\t\t\telse:
\t\t\t\tpickup_prompt.text = "[E]  Light the fire"
'''

USE_FIREPIT = '''func _use_firepit(f: Firepit) -> void:
\t## E on a fire pit. ONE VERB, and what it does is decided by what is burning
\t## and what you are carrying:
\t##
\t##   burning          -> feed it, if you have wood
\t##   embers + wood    -> back up to a flame; embers never need a torch
\t##   cold + lit torch -> strike it, and put your first log straight in
\t##   nothing to give  -> it says what it wants
\t##
\t## No new binding: E is already the interact verb that drinks, packs the
\t## bedroll, gathers rock and hoists a log.
\tif f == null or not is_instance_valid(f):
\t\treturn
\tvar idx := -1
\tvar fuel_name := ""
\tfor nm in Firepit.FUEL_ITEMS.keys():
\t\tvar i := _find_item_index(str(nm))
\t\tif i >= 0:
\t\t\tidx = i
\t\t\tfuel_name = str(nm)
\t\t\tbreak
\tvar torch: bool = offhand_shown.contains("Torch") or offhand_shown2.contains("Torch")

\tif f.burning() and f.state == Firepit.State.LIT:
\t\tif idx < 0:
\t\t\t_add_log_msg("Burning -- about %d min left. It wants wood."
\t\t\t\t% int(f.minutes_left()), Color(1.0, 0.78, 0.45))
\t\t\treturn
\t\tif not _spend_fuel_item(idx):
\t\t\treturn
\t\tf.feed(Firepit.fuel_value(fuel_name))
\t\t_add_log_msg("%s on the fire -- about %d min of burning"
\t\t\t% [fuel_name, int(f.minutes_left())], Color(1.0, 0.72, 0.36))
\t\treturn

\tif f.state == Firepit.State.EMBERS and idx >= 0:
\t\tif not _spend_fuel_item(idx):
\t\t\treturn
\t\tf.feed(Firepit.fuel_value(fuel_name))
\t\t_add_log_msg("The embers take the %s and come back up" % fuel_name.to_lower(),
\t\t\tColor(1.0, 0.72, 0.36))
\t\treturn

\tif not f.can_light():
\t\t_add_log_msg("The wind takes every spark -- it needs a roof over it",
\t\t\tColor(0.72, 0.80, 0.92))
\t\treturn
\tif not torch:
\t\tif f.state == Firepit.State.EMBERS:
\t\t\t_add_log_msg("Embers, still warm -- feed them before they go",
\t\t\t\tColor(1.0, 0.78, 0.45))
\t\telse:
\t\t\t_add_log_msg("Nothing to light it with -- a lit torch would do it",
\t\t\t\tColor(0.80, 0.80, 0.80))
\t\treturn
\tif not f.light():
\t\treturn
\tif idx >= 0 and _spend_fuel_item(idx):
\t\tf.feed(Firepit.fuel_value(fuel_name))
\t_add_log_msg("The fire takes -- about %d min of burning" % int(f.minutes_left()),
\t\tColor(1.0, 0.72, 0.36))


func _spend_fuel_item(idx: int) -> bool:
\t## One off the stack, the same shape _place_bedroll spends its bedroll.
\tif idx < 0 or idx >= inventory.size():
\t\treturn false
\tvar it: Dictionary = inventory[idx]
\tit.count = int(it.count) - 1
\tif int(it.count) <= 0:
\t\t_remove_inventory_index(idx)
\t_refresh_inventory_ui()
\treturn true


'''

WEATHER_ACCESSORS = '''func season() -> int:
\t## Public face of _season(): 0 spring, 1 summer, 2 autumn, 3 winter.
\t## Exposure and the seasonal pass both want this and neither should have to
\t## reach through the underscore to get it.
\treturn _season()


func is_snowing() -> bool:
\t## Whether the precipitation currently falling is snow rather than rain.
\treturn _snowing


'''

# --------------------------------------------------------------------- engine

EDITS = [
    # (file, kind, guard, anchor, payload)
    (PLAYER, "after",
     "var _fire_target",
     'var _debris_target: RockDebris = null   ## a landed rock under the gaze (E = gather)\n',
     VAR_DECL),

    (PLAYER, "before",
     "_use_firepit(_fire_target)",
     '\t\t\t\telif menu_open == "" and kd_phase == "" and _water_target != Vector3.INF:\n'
     '\t\t\t\t\t_drink_water()   ## [water]\n',
     KEY_E_BRANCH),

    (PLAYER, "before",
     "\t_fire_target = null\n",
     '\t_log_target = null\n'
     '\tif menu_open != "" or kd_phase != "" or reach_phase != "":\n',
     TARGET_RESET),

    (PLAYER, "after",
     "get_nodes_in_group(\"fires\")",
     '\t\tif d > lbest:\n\t\t\tlbest = d\n\t\t\t_log_target = cl\n',
     FIRE_SCAN),

    (PLAYER, "after",
     "pickup_prompt.visible = pickup_prompt.visible or _fire_target",
     PROMPT_VISIBLE_OLD,
     PROMPT_VISIBLE_ADD),

    (PLAYER, "after",
     "pickup_prompt.text = \"[E]  Light the fire\"",
     '\t\telif _log_target != null:\n'
     '\t\t\tpickup_prompt.text = "[E] / [LMB]  Take the log"\n',
     PROMPT_TEXT),

    (PLAYER, "before",
     "func _use_firepit",
     'func _pack_bedroll(bed: Node3D) -> void:\n',
     USE_FIREPIT),

    (WEATHER, "before",
     "func season() -> int:",
     'func _season() -> int:\n',
     WEATHER_ACCESSORS),
]


def main() -> int:
    if not os.path.exists(FIREPIT):
        print("REFUSED: scripts/Firepit.gd is not on disk. Player.gd would "
              "reference a class that does not exist and stop parsing.")
        return 2

    files = {}
    for path, _k, _g, _a, _p in EDITS:
        if path not in files:
            if not os.path.exists(path):
                print("REFUSED: missing %s" % path)
                return 2
            with open(path, "r", encoding="utf-8") as fh:
                files[path] = fh.read()

    original = dict(files)
    applied, skipped, problems = [], [], []

    for path, kind, guard, anchor, payload in EDITS:
        name = os.path.basename(path)
        src = files[path]
        if guard in src:
            skipped.append("%s: %s (already patched)" % (name, guard.strip()[:52]))
            continue
        n = src.count(anchor)
        if n != 1:
            problems.append("%s: anchor matched %d times (want 1): %r"
                            % (name, n, anchor[:64]))
            continue
        if kind == "after":
            files[path] = src.replace(anchor, anchor + payload, 1)
        elif kind == "before":
            files[path] = src.replace(anchor, payload + anchor, 1)
        else:
            problems.append("%s: unknown edit kind %s" % (name, kind))
            continue
        applied.append("%s: %s" % (name, guard.strip()[:52]))

    if problems:
        print("REFUSED -- nothing written:")
        for p in problems:
            print("  " + p)
        return 1

    for path in files:
        before = original[path].splitlines()
        after = files[path].splitlines()
        ## Every edit here is additive, so every original line must still be
        ## present and in order. One lost line is a stop-everything.
        i = 0
        lost = 0
        for line in before:
            found = False
            while i < len(after):
                if after[i] == line:
                    i += 1
                    found = True
                    break
                i += 1
            if not found:
                lost += 1
        if lost:
            print("REFUSED -- %s would lose %d line(s). Nothing written."
                  % (os.path.basename(path), lost))
            return 1
        print("%-14s +%d / -0" % (os.path.basename(path), len(after) - len(before)))

    for a in applied:
        print("  applied  " + a)
    for s in skipped:
        print("  skipped  " + s)

    if DRY:
        print("\n--dry-run: nothing written.")
        return 0

    for path, text in files.items():
        if text != original[path]:
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(text)
    print("\nWritten. Run filesystem_manage(op=\"scan\") before the next launch.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
