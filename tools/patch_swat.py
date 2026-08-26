#!/usr/bin/env python3
"""
Make a weapon swing kill blackflies.

    python3 tools/patch_swat.py            # patch
    python3 tools/patch_swat.py --check    # report only
    python3 tools/patch_swat.py --revert   # restore the .bak

Re-runnable; guarded by a marker. Keeps scripts/Player.gd.bak_swat.

Three edits, all in scripts/Player.gd — the sword, the axe and the pick each
sweep the air at the exact frame their damage lands, so the swat happens at
the visual impact of the cut rather than at the button press.

The sweep itself lives in CritterSwarm.swat_all(); this only points at it.
"""

import argparse
import pathlib
import re
import sys

MARK = "## --- swat ---"

HELPER = '''

func _swat_bugs(forward: Vector3, reach: float) -> void:
	%(mark)s
	## A swing through a blackfly cloud kills what is in the arc. It does not
	## solve blackflies — there are sixty of them and they come back on their
	## own clocks — but it thins the biting while they do, and it is enormously
	## satisfying, which is the entire point. Smoke is still the real answer.
	##
	## Fired from the damage frame of each weapon, not the button press, so the
	## flies die where the blade actually is.
	var at := global_position + Vector3.UP * 1.35 + forward * (reach * 0.45)
	var n := CritterSwarm.swat_all(self, at, reach * 0.9, forward)
	if n <= 0:
		return
	cam_shake = maxf(cam_shake, 0.02)
	_add_log_msg("Swatted %%d." %% n, Color(0.72, 0.70, 0.62))

''' % {"mark": MARK}

EDITS = [
    (
        "sword",
        r"^func _do_melee_hit\(\) -> void:\n"
        r"\tvar mat_id := _sword_material_id\(\)\n"
        r"\tvar forward := -camera\.global_transform\.basis\.z\n"
        r"\tforward\.y = 0\.0\n"
        r"\tforward = forward\.normalized\(\)\n",
        "func _do_melee_hit() -> void:\n"
        "\tvar mat_id := _sword_material_id()\n"
        "\tvar forward := -camera.global_transform.basis.z\n"
        "\tforward.y = 0.0\n"
        "\tforward = forward.normalized()\n"
        "\t_swat_bugs(forward, attack_range)  %s\n" % MARK,
    ),
    (
        "axe",
        r"^\tvar best_tree := _nearest_wood\(forward, AXE_RANGE \+ 0\.5\)\n",
        "\t_swat_bugs(forward, AXE_RANGE)  %s\n"
        "\tvar best_tree := _nearest_wood(forward, AXE_RANGE + 0.5)\n" % MARK,
    ),
]

# The pick is optional — it exists in the current file but is the least likely
# anchor to survive, so a miss on it is reported and shrugged off.
PICK = (
    "pick",
    r"^func _do_pick_hit\(\) -> void:\n",
    "func _do_pick_hit() -> void:\n\t_swat_bugs(_flat_forward(), 2.4)  %s\n" % MARK,
)

FLAT_FWD = '''

func _flat_forward() -> Vector3:
	%(mark)s
	var f := -camera.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else -transform.basis.z

''' % {"mark": MARK}


def patch(root: pathlib.Path, check: bool) -> int:
    path = root / "scripts" / "Player.gd"
    if not path.exists():
        print("!! not found: %s" % path)
        return 1
    src = path.read_text()
    original = src

    if MARK in src:
        print("== already patched (marker present) — nothing to do")
        return 0

    problems = []
    for name, anchor, repl in EDITS:
        pat = re.compile(anchor, re.MULTILINE)
        if not pat.search(src):
            problems.append(name)
            continue
        src = pat.sub(lambda _m: repl, src, count=1)
        print("   + %s swings sweep the air" % name)

    pat = re.compile(PICK[1], re.MULTILINE)
    if pat.search(src):
        src = pat.sub(lambda _m: PICK[2], src, count=1)
        print("   + pick swings sweep the air")
    else:
        print("   . no _do_pick_hit found — skipping the pick (not an error)")

    # helpers, appended
    src = src.rstrip("\n") + "\n" + HELPER + FLAT_FWD

    for name in problems:
        print("   !! ANCHOR NOT FOUND: %s — add `_swat_bugs(forward, <reach>)` "
              "at that weapon's damage frame by hand" % name)

    if check:
        print("== --check: nothing written")
        return 0 if not problems else 2
    if src == original:
        print("== no changes")
        return 0

    bak = path.with_suffix(".gd.bak_swat")
    if not bak.exists():
        bak.write_text(original)
        print("   kept original at %s" % bak.name)
    path.write_text(src)
    print("== patched %s" % path)
    return 0 if not problems else 2


def revert(root: pathlib.Path) -> int:
    path = root / "scripts" / "Player.gd"
    bak = path.with_suffix(".gd.bak_swat")
    if not bak.exists():
        print("!! no backup at %s" % bak.name)
        return 1
    path.write_text(bak.read_text())
    print("== reverted %s" % path.name)
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--revert", action="store_true")
    a = ap.parse_args()
    r = pathlib.Path(a.root).resolve()
    sys.exit(revert(r) if a.revert else patch(r, a.check))
