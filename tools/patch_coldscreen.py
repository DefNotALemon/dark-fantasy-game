#!/usr/bin/env python3
"""patch_coldscreen.py -- wire ColdScreen into Player.gd (2026-09-11 06:00, POLISH).

Five hunks, every one PURELY ADDITIVE, every anchor required to match exactly
once, and every hunk guarded on what it DEFINES rather than on a call to it --
a guard that matches the call as well as the definition is not a guard, and
that bug once wrote a World.gd calling a function that was never inserted
(2026-09-05 09:00).

Idempotent: a second run is a clean no-op.

The backup goes to the gauntlet backup directory, NOT beside the source: a
.bak_ file next to Player.gd is clutter in somebody else's working tree.

    python3 tools/patch_coldscreen.py
"""
import pathlib
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BACKUP = pathlib.Path.home() / "myrkfell-gauntlet-backup-20260911-0600"
PLAYER = ROOT / "scripts" / "Player.gd"

# (name, guard, anchor, replacement)
HUNKS = [
    (
        "declare",
        "var cold := ColdScreen.new()",
        "var exposure := Exposure.new()\n",
        "var exposure := Exposure.new()\n"
        "\n"
        "## [coldscreen] What the cold LOOKS like. Exposure has handed out a `felt`\n"
        "## in degrees and a `sway_extra()` every frame since 4ac02b1 and nothing\n"
        "## read either. Breath is the AIR (ambient, so a man at a hearth still\n"
        "## sees it); the shiver and the grade are the BODY (warmth, from the\n"
        "## shiver line down). Owns one overlay and one particle node and takes no\n"
        "## decision: `step()` returns a report and `present()` draws it.\n"
        "var cold := ColdScreen.new()\n",
    ),
    (
        "tick-body",
        "func _cold_tick",
        "## Stamina regen multiplier from thirst: half when parched, 1.5 while\n",
        "func _cold_tick(delta: float) -> void:\n"
        "\t## [coldscreen] Attached lazily: the HUD layer and the head are built by\n"
        "\t## different passes of _ready, and `attach()` is idempotent.\n"
        "\t##\n"
        "\t## Deliberately called OUTSIDE `_exposure_tick`'s god-mode early return.\n"
        "\t## God mode pins warmth at the maximum, so the shiver and the grade turn\n"
        "\t## themselves off with no branch here -- and an afternoon spent building\n"
        "\t## in a winter sky still has your breath in front of you, which is the\n"
        "\t## correct answer and falls out of the model for free.\n"
        "\tcold.attach(head, hud_layer)\n"
        "\tvar ex := ColdScreen.exertion_of(sprinting, stamina / maxf(1.0, max_stamina))\n"
        "\tvar rep: Dictionary = cold.step(_exposure_env(), exposure.warmth, ex, delta)\n"
        "\tcold.present(rep)\n"
        "\tvar sh := float(rep[\"shake\"])\n"
        "\tif sh > 0.0:\n"
        "\t\t## Fed into the EXISTING shake path rather than writing camera.position:\n"
        "\t\t## that line already decays, already composes with the walk-cycle bob,\n"
        "\t\t## and already loses to a real impact -- which is the right priority.\n"
        "\t\tcam_shake = maxf(cam_shake, sh)\n"
        "\n"
        "\n"
        "## Stamina regen multiplier from thirst: half when parched, 1.5 while\n",
    ),
    (
        "tick-call",
        "\t_cold_tick(delta)\n",
        "\t_exposure_tick(delta)\n",
        "\t_exposure_tick(delta)\n\t_cold_tick(delta)\n",
    ),
    (
        "wake",
        "cold.wake(",
        "\t_apply_slept()\n\t_sleep_rise()\n",
        "\t## [coldscreen] Read BEFORE _apply_slept(), which clears `_slept`. A\n"
        "\t## night that ended at four in the morning because the fire went out\n"
        "\t## should not open the same way as one that ran to dawn: it holds the\n"
        "\t## dark longer, comes up slower, and opens on a hard shiver. Until\n"
        "\t## this, the whole difference was one line of log text.\n"
        "\tvar woke_cold := String(_slept.get(\"woke\", Slumber.WOKE_DAWN)) == Slumber.WOKE_COLD\n"
        "\t_apply_slept()\n"
        "\tcold.wake(woke_cold)\n"
        "\t_sleep_rise()\n",
    ),
    (
        "respawn",
        "cold.reset()",
        "\texposure.on_respawn()",
        "\tcold.reset()                        ## [coldscreen] a new body is not still shaking\n"
        "\texposure.on_respawn()",
    ),
]


def main():
    BACKUP.mkdir(parents=True, exist_ok=True)
    src = PLAYER.read_text(encoding="utf-8")
    before_lines = len(src.split("\n"))
    if not (BACKUP / "Player.gd").exists():
        shutil.copy2(PLAYER, BACKUP / "Player.gd")

    applied, skipped, bad = [], [], []
    for name, guard, anchor, repl in HUNKS:
        if guard in src:
            skipped.append(name)
            continue
        n = src.count(anchor)
        if n != 1:
            bad.append("%s (anchor x%d)" % (name, n))
            continue
        src = src.replace(anchor, repl, 1)
        applied.append(name)

    if bad:
        print("REFUSING TO WRITE -- bad anchors: %s" % ", ".join(bad))
        return 1
    if applied:
        PLAYER.write_text(src, encoding="utf-8")
    after_lines = len(src.split("\n"))
    print("applied: %s" % (", ".join(applied) or "(none)"))
    print("skipped (already present): %s" % (", ".join(skipped) or "(none)"))
    print("Player.gd %d -> %d lines" % (before_lines, after_lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
