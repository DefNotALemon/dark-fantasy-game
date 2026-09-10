#!/usr/bin/env python3
"""
patch_fireaudio.py -- wire the fire bus into World.gd.

    python3 tools/patch_fireaudio.py [--dry-run]

Two purely ADDITIVE edits, each anchored on a string that must appear exactly
once, and the whole run guarded on `_fire_audio` so a second run is a no-op.
Nothing is removed and nothing is reworded: expect +n / -0 in the diff, and a
removed line is a stop-everything (World.gd has silently lost work to a
concurrent patcher twice).

The bus rides along beside WaterAudio and StepAudio for the same reason they
ride together: all three want the player as a listener and all three want to
exist before the first chunk streams in.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TARGET = os.path.join(HERE, "..", "scripts", "World.gd")
GUARD = "_fire_audio"

EDITS = [
    (
        "member",
        "var _critter_audio: CritterAudio     ## calls, and the ambience bed\n",
        "var _critter_audio: CritterAudio     ## calls, and the ambience bed\n"
        "var _fire_audio: FireAudio = null    ## [fire] beds, crackles, and the one shadow\n",
    ),
    (
        "build",
        """	_step_audio = StepAudio.new()
	_step_audio.name = "StepAudio"
	add_child(_step_audio)
""",
        """	_step_audio = StepAudio.new()
	_step_audio.name = "StepAudio"
	add_child(_step_audio)
	## [fire] the fire bus. Twenty-five croft hearths and every camp you build
	## share three beds between them, ranked by distance four times a second,
	## and that same ranking is what decides which single fire in the world
	## casts shadows. See scripts/FireAudio.gd.
	_fire_audio = FireAudio.new()
	_fire_audio.name = "FireAudio"
	add_child(_fire_audio)
	_fire_audio.listener = _player
""",
    ),
]


def main():
    dry = "--dry-run" in sys.argv
    path = os.path.normpath(TARGET)
    src = open(path).read()
    before = src.count("\n")

    if GUARD in src:
        print("patch_fireaudio: already applied (found '%s') -- nothing to do." % GUARD)
        return 0

    out = src
    for name, old, new in EDITS:
        n = out.count(old)
        if n != 1:
            print("patch_fireaudio: ABORT -- anchor '%s' matched %d times, want exactly 1."
                  % (name, n))
            return 2
        out = out.replace(old, new, 1)
        print("  %-10s ok" % name)

    after = out.count("\n")
    print("patch_fireaudio: %d/%d anchors matched exactly once" % (len(EDITS), len(EDITS)))
    print("  lines %d -> %d  (+%d / -0)" % (before, after, after - before))
    if dry:
        print("  --dry-run: nothing written")
        return 0
    open(path, "w").write(out)
    print("  written: %s" % path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
