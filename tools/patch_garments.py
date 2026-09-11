#!/usr/bin/env python3
"""tools/patch_garments.py -- wires Garments into Player.gd.

`scripts/Garments.gd`, `scripts/Exposure.gd` and `tests/GarmentTests.gd` are
committed; the three hunks below land in `scripts/Player.gd`, which carries
thousands of lines of uncommitted work and is never committed by a gauntlet
round. This file is how those hunks are re-applied after a checkout, and how
anybody can read exactly what was added to that file.

    python3 tools/patch_garments.py

IDEMPOTENT. Every hunk is guarded on what it DEFINES -- `func worn_metals`,
not `worn_metals()` -- because a guard that matches the CALL as well as the
definition makes a second run skip the body and leave a file that calls a
function which is not there. That bug cost a round on 2026-09-05. Running
this twice is a no-op and says so.
"""

import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLAYER = os.path.join(ROOT, "scripts", "Player.gd")

NL = "\n"

ENV_ANCHOR = '\t\t"asleep": false,\n\t\t"swimming": swimming,\n'
ENV_GUARD = '"worn": worn_metals(),'
ENV_HUNK = NL.join([
    '\t\t## WHAT IS ON YOUR BACK. `Garments` prices the five armour slots',
    '\t\t## in degrees; `equipment` also carries a sword and an offhand,',
    '\t\t## which `worn_metals()` leaves out rather than relying on the',
    '\t\t## other file to ignore them.',
    '\t\t"worn": worn_metals(),',
    '\t\t## AND WHERE YOU ARE STANDING. `Seasons.base_c_at()` is the',
    "\t\t## season's contribution to the air HERE, on this place's own",
    '\t\t## calendar, and it has had no caller since it shipped. With it,',
    '\t\t## a winter night in Aroostook is genuinely colder than the same',
    '\t\t## night on Casco Bay -- twelve degrees apart on day 66, when the',
    '\t\t## north is in winter and the south has not finished autumn.',
    '\t\t"base_c": Seasons.base_c_at(day, global_position),',
    '',
])

FUNCS_ANCHOR = "func _armor_mult() -> float:"
FUNCS_GUARD = "func worn_metals"
FUNCS_HUNK = NL.join([
    'func worn_metals() -> Dictionary:',
    '\t## The five armour slots as `Garments` wants them: slot -> material id.',
    '\t## Empty slots are left OUT rather than carried as "", so `cover()` and',
    '\t## `pieces()` agree with what is actually on the body.',
    '\tvar w: Dictionary = {}',
    '\tfor slot: String in Materials.ARMOR_SLOTS:',
    '\t\tvar it: Dictionary = equipment.get(slot, {})',
    '\t\tvar m := String(it.get("material", ""))',
    '\t\tif m != "":',
    '\t\t\tw[slot] = m',
    '\treturn w',
    '',
    '',
    'func _garment_note() -> void:',
    '\t## What the set you have just put on is worth TONIGHT, said at the one',
    "\t## moment the choice is in front of you. Every number is `Garments`';",
    '\t## this reads and prints.',
    '\tvar worn := worn_metals()',
    '\tif worn.is_empty():',
    '\t\treturn',
    '\tvar e := _exposure_env()',
    '\tvar g := Exposure.garment_c(e, exposure.wet)',
    '\tvar v := Garments.verdict(worn, Exposure.still_air_c(e), exposure.wet,',
    '\t\tclampf(float(e.get("wind", 0.0)), 0.0, 1.0))',
    '\t_add_log_msg("%s out here: %+.1f C - %s" % [Garments.describe(worn), g, v],',
    '\t\tColor(0.72, 0.84, 1.0) if g >= 0.0 else Color(1.0, 0.76, 0.55))',
    '',
    '',
    '',
])

NOTE_ANCHOR = "\t_refresh_inventory_ui()"
NOTE_GUARD = "\t_garment_note()\n\t_refresh_inventory_ui()"
NOTE_HUNK = "\t_garment_note()\n\t_refresh_inventory_ui()"


def main():
    with io.open(PLAYER, encoding="utf-8") as f:
        src = f.read()
    before = src
    done = []
    skipped = []

    # 1. the two new env keys
    if ENV_GUARD in src:
        skipped.append("env keys")
    elif src.count(ENV_ANCHOR) == 1:
        src = src.replace(ENV_ANCHOR, ENV_ANCHOR + ENV_HUNK)
        done.append("env keys")
    else:
        print("ANCHOR MISS: the exposure env block (%d matches)" % src.count(ENV_ANCHOR))
        return 2

    # 2. the two new functions, guarded on what they DEFINE
    if FUNCS_GUARD in src:
        skipped.append("worn_metals / _garment_note")
    elif src.count(FUNCS_ANCHOR) == 1:
        src = src.replace(FUNCS_ANCHOR, FUNCS_HUNK + FUNCS_ANCHOR)
        done.append("worn_metals / _garment_note")
    else:
        print("ANCHOR MISS: _armor_mult (%d matches)" % src.count(FUNCS_ANCHOR))
        return 2

    # 3. the call, after the "set equipped" line. That line carries an em dash,
    #    so it is never retyped here: the anchor is the FIRST
    #    `_refresh_inventory_ui()` that follows it.
    if NOTE_GUARD in src:
        skipped.append("_garment_note call")
    else:
        marker = "set equipped"
        at = src.find(marker)
        if at < 0:
            print("ANCHOR MISS: the set-equipped log line")
            return 2
        nxt = src.find(NOTE_ANCHOR, at)
        if nxt < 0:
            print("ANCHOR MISS: no _refresh_inventory_ui() after the log line")
            return 2
        src = src[:nxt] + NOTE_HUNK + src[nxt + len(NOTE_ANCHOR):]
        done.append("_garment_note call")

    if src == before:
        print("nothing to do -- all three hunks are already in place")
        return 0

    with io.open(PLAYER, "w", encoding="utf-8") as f:
        f.write(src)
    print("applied: %s" % ", ".join(done) if done else "applied: nothing")
    if skipped:
        print("already present: %s" % ", ".join(skipped))
    print("Player.gd %d -> %d bytes" % (len(before), len(src)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
