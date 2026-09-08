#!/usr/bin/env python3
"""
patch_steps.py -- wire StepAudio into Player.gd and World.gd.

    python3 tools/patch_steps.py            # apply
    python3 tools/patch_steps.py --check    # report only, change nothing

Idempotent and marker-guarded, same shape as tools/patch_ground.py: every
insertion carries a `## [steps]` marker and the patcher refuses to add one
twice. Player.gd and World.gd have silently lost work to concurrent patchers
before -- this touches THREE anchors in Player.gd and TWO in World.gd, all of
them additive, and it prints exactly what it changed.

What it wires:
  Player.gd   _step_idx member; a footfall at every gait bob peak; a landing
              sound at touchdown.
  World.gd    _step_audio member; the bus built next to WaterAudio; the
              wetness feed from Weather.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
CHECK = "--check" in sys.argv

EDITS = [
    # ---------------------------------------------------------- Player.gd --
    ("scripts/Player.gd", "player-member",
     "var head_bob := Vector2.ZERO ## smoothed camera offset (x sway, y footfall dip)\n",
     "var head_bob := Vector2.ZERO ## smoothed camera offset (x sway, y footfall dip)\n"
     "var _step_idx := -9999       ## [steps] which half-stride we are in; a change is a foot down\n"),

    ("scripts/Player.gd", "player-footfall",
     "\tif is_on_floor():\n"
     "\t\tgait_phase += delta * (4.5 + hspeed * 1.35)\n",
     "\tif is_on_floor():\n"
     "\t\tgait_phase += delta * (4.5 + hspeed * 1.35)\n"
     "\t## [steps] FOOTFALL. The bob already dips the camera at every\n"
     "\t## |sin(gait_phase)| peak -- twice a stride, once per foot. The sound\n"
     "\t## lands on that same beat, so what you hear is exactly what you see at\n"
     "\t## any speed, with no second clock to drift. (If it ever reads too fast,\n"
     "\t## the one-line halving is PI -> TAU on the line below.)\n"
     "\tvar _si := int(floor((gait_phase - PI * 0.5) / PI))\n"
     "\tif _si != _step_idx:\n"
     "\t\tvar _first := _step_idx == -9999\n"
     "\t\t_step_idx = _si\n"
     "\t\tif not _first and is_on_floor() and gait_amount > 0.12 \\\n"
     "\t\t\t\tand not swimming and kd_phase == \"\" and mount == null \\\n"
     "\t\t\t\tand not climbing:\n"
     "\t\t\tStepAudio.footfall(self, global_position, gait_amount,\n"
     "\t\t\t\tcrouching, prone)\n"),

    ("scripts/Player.gd", "player-landing",
     "\t\tland_dip = maxf(land_dip, clampf(_fall_speed * 0.014, 0.0, 0.16))\n"
     "\t\t_apply_fall_damage(_fall_speed)\n",
     "\t\tland_dip = maxf(land_dip, clampf(_fall_speed * 0.014, 0.0, 0.16))\n"
     "\t\tStepAudio.landing(self, global_position, _fall_speed)  ## [steps]\n"
     "\t\t_apply_fall_damage(_fall_speed)\n"),

    # ----------------------------------------------------------- World.gd --
    ("scripts/World.gd", "world-member",
     "var _water_audio: WaterAudio = null  ## [water] shores, strokes, the muffle under\n",
     "var _water_audio: WaterAudio = null  ## [water] shores, strokes, the muffle under\n"
     "var _step_audio: StepAudio = null    ## [steps] the ground under your feet\n"),

    ("scripts/World.gd", "world-build",
     "\t_water_audio = WaterAudio.new()\n"
     "\t_water_audio.name = \"WaterAudio\"\n"
     "\tadd_child(_water_audio)\n"
     "\t_water_audio.listener = _player\n",
     "\t_water_audio = WaterAudio.new()\n"
     "\t_water_audio.name = \"WaterAudio\"\n"
     "\tadd_child(_water_audio)\n"
     "\t_water_audio.listener = _player\n"
     "\t## [steps] the footstep bus rides along -- it needs no listener, the\n"
     "\t## Player hands it the position of every foot it puts down.\n"
     "\t_step_audio = StepAudio.new()\n"
     "\t_step_audio.name = \"StepAudio\"\n"
     "\tadd_child(_step_audio)\n"),
]

# The wetness feed goes into World._process. Anchored separately because the
# function head is the only stable landmark.
WET_ANCHOR = "func weather() -> Weather:\n"
WET_BLOCK = """## [steps] Weather.wetness has been published since the sky pass and read by
## nothing. The footsteps are its first consumer: soaked soil squelches, and
## gravel and sand do not.
func _feed_step_wetness() -> void:
	if _step_audio == null or not is_instance_valid(_step_audio):
		return
	if _weather == null or not is_instance_valid(_weather):
		return
	var w = _weather.get("wetness")
	_step_audio.wetness = clampf(float(w), 0.0, 1.0) if w != null else 0.0


"""


def main():
    changed, skipped, missing = [], [], []
    files = {}
    for rel, tag, old, new in EDITS:
        path = os.path.join(ROOT, rel)
        if rel not in files:
            files[rel] = open(path, encoding="utf-8").read()
        src = files[rel]
        if new in src:
            skipped.append("%s [%s] already patched" % (rel, tag))
            continue
        if src.count(old) != 1:
            missing.append("%s [%s] anchor found %d times (want 1)"
                           % (rel, tag, src.count(old)))
            continue
        files[rel] = src.replace(old, new, 1)
        changed.append("%s [%s]" % (rel, tag))

    rel = "scripts/World.gd"
    if rel not in files:
        files[rel] = open(os.path.join(ROOT, rel), encoding="utf-8").read()
    if "_feed_step_wetness" in files[rel]:
        skipped.append("%s [world-wetness] already patched" % rel)
    elif files[rel].count(WET_ANCHOR) == 1:
        files[rel] = files[rel].replace(WET_ANCHOR, WET_BLOCK + WET_ANCHOR, 1)
        changed.append("%s [world-wetness]" % rel)
    else:
        missing.append("%s [world-wetness] anchor not unique" % rel)

    for line in changed:
        print("  +", line)
    for line in skipped:
        print("  =", line)
    for line in missing:
        print("  !", line)
    if missing:
        print("REFUSING to write: %d anchor(s) did not match." % len(missing))
        return 1
    if CHECK:
        print("--check: %d edit(s) would apply." % len(changed))
        return 0
    for rel, src in files.items():
        open(os.path.join(ROOT, rel), "w", encoding="utf-8").write(src)
    print("patched %d file(s), %d edit(s)." % (len(files), len(changed)))
    print("NOTE: _feed_step_wetness() must be called from World._process --")
    print("      one line, by hand, next to the other per-frame feeds.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
