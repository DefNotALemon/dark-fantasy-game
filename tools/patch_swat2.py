#!/usr/bin/env python3
"""
Move the swat geometry out of Player.gd.

    python3 tools/patch_swat2.py            # patch
    python3 tools/patch_swat2.py --check    # report only
    python3 tools/patch_swat2.py --revert   # restore the .bak

Follow-up to tools/patch_swat.py. That version computed the swing volume
inside Player._swat_bugs — a metre in FRONT of the player, in a 0.25 cone.
Blackflies orbit your head, so most of the cloud sat behind the swing origin
and a swing killed 6 of 60. The suite missed it because it called
CritterSwarm.swat() with a hand-picked point instead of the real geometry.

The geometry now lives in CritterSwarm.swat_from(), where the tests can reach
it. This rewrites _swat_bugs to call that and do nothing else.

Requires patch_swat.py to have been run first (it looks for its marker).
"""

import argparse
import pathlib
import re
import sys

MARK = "## --- swat2 ---"
NEEDS = "## --- swat ---"

NEW = '''func _swat_bugs(forward: Vector3, reach: float) -> void:
	%(mark)s
	## A swing kills blackflies. Two clears a cloud — the sweep takes the
	## nearest 60%% of it, so the first swing leaves 40%% and the second
	## finishes them. It still does not SOLVE blackflies: they come back on
	## their own clocks and smoke is the real answer. It is just enormously
	## satisfying, which is the whole point.
	##
	## Fired from the damage frame of each weapon, not the button press, so the
	## flies die where the blade actually is. All of the geometry lives in
	## CritterSwarm.swat_from() — it used to live here, where no test could
	## reach it, and a swing killed six flies out of sixty for a week.
	var n := CritterSwarm.swat_from(self, forward, reach)
	if n <= 0:
		return
	cam_shake = maxf(cam_shake, 0.02)
	_add_log_msg("Swatted %%d." %% n, Color(0.72, 0.70, 0.62))
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
    if NEEDS not in src:
        print("!! tools/patch_swat.py has not been run — run it first")
        return 1

    pat = re.compile(
        r"^func _swat_bugs\(forward: Vector3, reach: float\) -> void:\n.*?(?=^func |\Z)",
        re.MULTILINE | re.DOTALL,
    )
    m = pat.search(src)
    if not m:
        print("!! ANCHOR NOT FOUND: _swat_bugs — replace its body by hand with:")
        for line in NEW.rstrip("\n").split("\n"):
            print("   | %s" % line)
        return 2
    src = src[: m.start()] + NEW + "\n\n" + src[m.end():]
    print("   + _swat_bugs now defers to CritterSwarm.swat_from()")

    if check:
        print("== --check: nothing written")
        return 0
    if src == original:
        print("== no changes")
        return 0

    bak = path.with_suffix(".gd.bak_swat2")
    if not bak.exists():
        bak.write_text(original)
        print("   kept original at %s" % bak.name)
    path.write_text(src)
    print("== patched %s" % path)
    return 0


def revert(root: pathlib.Path) -> int:
    path = root / "scripts" / "Player.gd"
    bak = path.with_suffix(".gd.bak_swat2")
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
