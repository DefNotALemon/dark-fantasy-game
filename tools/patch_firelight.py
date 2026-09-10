#!/usr/bin/env python3
"""
patch_firelight.py -- give Firepit the shared flame signal and the light spill.

    python3 tools/patch_firelight.py [--dry-run] [--target PATH]

Seven edits to scripts/Firepit.gd, all of them exact string replacements that
must match EXACTLY ONCE or the patcher refuses to write anything. Idempotent:
the whole run is guarded on `func flame_signal` -- on what it DEFINES, never
on a call to it, which is the guard bug found on 2026-09-05.

What it does, and why:

  1  new constants: the flicker's two frequencies (lifted out of the inline
     expression in _apply_visuals, unchanged), the ember breath rate, the fuel
     at which a flame is at full size, three light colours and the shadow range.

  2  _apply_visuals' LIT branch reads `flame_signal(_flicker)` instead of
     computing `sin(_flicker * 11.3)` itself, and sets the light's COLOUR from
     the fuel as well as its energy. The energy expression is algebraically the
     same number -- 0.90 + 0.20 * signal IS 1.0 + 0.06 sin a + 0.04 sin b -- and
     FireAudioTests asserts that longhand, to a millionth.

  3  the EMBERS branch gets a slow breath of its own, on the same signal at
     EMBER_BREATH speed, in the light AND in the coal bed's emission.

  4  _flicker advances in EMBERS too. It never did, so a coal bed was frozen.

  5  the new methods: flame_signal / signal_now / flame01 / light_color, and
     the shadow arbiter shadow_pick / apply_shadows / set_shadow / casts_shadow.

  6  the magic 600.0 in _apply_visuals becomes FUEL_BRIGHT, so the light and
     flame01() cannot disagree about how big a flame is.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TARGET = os.path.join(HERE, "..", "scripts", "Firepit.gd")
GUARD = "func flame_signal"

CONSTS = '''const EMBER_HEAT_MULT := 0.25

## --- the flame signal, and the light it drives -------------------------------
## ONE number drives the flicker, and both the light and FireAudio's crackle
## rate are computed from it. That is the whole reason a pop lands on the frame
## the flame flares instead of on a timer of its own.
const FLICKER_A := 11.3           ## the fast gutter
const FLICKER_B := 4.1            ## the slow breath under it
const EMBER_BREATH := 0.22        ## coals do not gutter; they breathe, slowly
const FUEL_BRIGHT := 600.0        ## fuel at which a flame is at its full size
const COLOR_HOT := Color(1.0, 0.68, 0.34)    ## a fed flame: yellow
const COLOR_LOW := Color(1.0, 0.36, 0.11)    ## a starved one: orange-red
const COLOR_EMBER := Color(1.0, 0.24, 0.06)  ## coals: red
const SHADOW_RANGE := 18.0        ## no shadows from a fire you cannot make out
const SHADOW_BIAS := 0.05
'''

NEW_FUNCS = '''# ===========================================================================
#  The flame signal - ONE number, read by the light and by the sound
# ===========================================================================

static func flame_signal(t: float) -> float:
	## 0..1, deterministic, no RNG. The light's energy is computed from this,
	## and `FireAudio.pop_rate` warps the crackle rate with it, so the pop you
	## hear lands on the frame the flame flares. Sound and light cannot drift
	## apart because there is only one of them -- the trick StepAudio used to
	## hang the footstep off `Player.gait_phase`'s bob peaks.
	return clampf(0.5 + 0.30 * sin(t * FLICKER_A) + 0.20 * sin(t * FLICKER_B), 0.0, 1.0)


func signal_now() -> float:
	## This fire's flicker, this instant. Coals breathe at EMBER_BREATH speed,
	## and _apply_visuals reads the same number, not a second copy of it.
	return flame_signal(_flicker if state == State.LIT else _flicker * EMBER_BREATH)


func flame01() -> float:
	## How hard this fire is burning, 0..1. A flame reads its fuel; coals read
	## their ember clock and are capped at the same quarter their HEAT is
	## capped at, because they are a quarter of a fire in every other way too.
	if state == State.LIT:
		return clampf(fuel / FUEL_BRIGHT, 0.0, 1.0)
	if state == State.EMBERS:
		return clampf(ember_t / EMBER_SECONDS, 0.0, 1.0) * EMBER_HEAT_MULT
	return 0.0


static func light_color(st: int, f01: float) -> Color:
	## The colour used to be a constant and only the energy moved, which is why
	## a dying fire read as "the same fire, further away". It should read as a
	## different fire.
	if st == State.EMBERS:
		return COLOR_EMBER
	if st == State.OUT:
		return COLOR_LOW
	return COLOR_LOW.lerp(COLOR_HOT, clampf(f01, 0.0, 1.0))


# ===========================================================================
#  Light spill - exactly ONE fire in the world casts shadows
# ===========================================================================

static func shadow_pick(entries: Array, at: Vector3, range_m: float) -> int:
	## [{"id": int, "pos": Vector3, "state": int}] -> the id of the one fire
	## that gets shadows, or -1. The nearest BURNING one within range: a cold
	## pit half a metre away must not take the promotion from the campfire you
	## are actually sitting at.
	var best := -1
	var best_d := INF
	for e in entries:
		var d: Dictionary = e
		if int(d.get("state", State.OUT)) == State.OUT:
			continue
		var pos: Vector3 = d.get("pos", Vector3.ZERO)
		var dist := pos.distance_to(at)
		if dist > range_m:
			continue
		if dist < best_d:
			best_d = dist
			best = int(d.get("id", -1))
	return best


static func apply_shadows(fires: Array, at: Vector3) -> int:
	## Called once per query by the fire bus, not once per fire per frame.
	## Twenty-six hearths each deciding for themselves is twenty-six distance
	## queries a frame for an answer only one of them can have.
	var entries: Array = []
	var pits: Array = []
	for n in fires:
		var fp := n as Firepit
		if fp == null or not is_instance_valid(fp):
			continue
		pits.append(fp)
		entries.append({"id": int(fp.get_instance_id()), "pos": fp.here(), "state": fp.state})
	var pick := shadow_pick(entries, at, SHADOW_RANGE)
	for p in pits:
		var fp2 := p as Firepit
		fp2.set_shadow(int(fp2.get_instance_id()) == pick)
	return pick


func set_shadow(on: bool) -> void:
	if _light == null:
		return
	if on and not _light.shadow_enabled:
		_light.shadow_bias = SHADOW_BIAS
		_light.shadow_normal_bias = 1.4
	_light.shadow_enabled = on


func casts_shadow() -> bool:
	return _light != null and _light.shadow_enabled


func _set_ember_glow(e: float) -> void:'''

EDITS = [
    (
        "consts",
        "const EMBER_HEAT_MULT := 0.25\n",
        CONSTS,
    ),
    (
        "lit branch",
        """		State.LIT:
			var flick := 1.0 + sin(_flicker * 11.3) * 0.06 + sin(_flicker * 4.1) * 0.04
			_light.light_energy = (1.1 + 1.4 * f01) * flick
			_light.omni_range = 6.5 + 3.5 * f01
""",
        """		State.LIT:
			## 0.90 + 0.20 * signal IS 1.0 + 0.06 sin(11.3t) + 0.04 sin(4.1t).
			## FireAudioTests asserts that longhand, to a millionth.
			_light.light_energy = (1.1 + 1.4 * f01) * (0.90 + 0.20 * flame_signal(_flicker))
			_light.omni_range = 6.5 + 3.5 * f01
			_light.light_color = light_color(State.LIT, f01)
""",
    ),
    (
        "embers branch",
        """			var e01 := clampf(ember_t / EMBER_SECONDS, 0.0, 1.0)
			_light.light_energy = 0.45 * e01
			_light.omni_range = 4.5
""",
        """			var e01 := clampf(ember_t / EMBER_SECONDS, 0.0, 1.0)
			var esig := flame_signal(_flicker * EMBER_BREATH)
			_light.light_energy = 0.45 * e01 * (0.82 + 0.36 * esig)
			_light.omni_range = 4.5
			_light.light_color = light_color(State.EMBERS, e01)
""",
    ),
    (
        "ember glow breath",
        "			_set_ember_glow(0.35 + 0.9 * e01)\n",
        "			_set_ember_glow((0.35 + 0.9 * e01) * (0.86 + 0.28 * esig))\n",
    ),
    (
        "flicker in embers",
        """		_sheltered = _raycast_roof()
	if state == State.EMBERS:
""",
        """		_sheltered = _raycast_roof()
	## Coals were FROZEN before this line moved up here: _flicker only
	## advanced in LIT, so an ember bed never breathed and never popped.
	_flicker += delta
	if state == State.EMBERS:
""",
    ),
    (
        "old flicker bump",
        """	_flicker += delta
	_apply_visuals()
""",
        "	_apply_visuals()\n",
    ),
    (
        "fuel_bright",
        "	var f01 := clampf(fuel / 600.0, 0.0, 1.0)\n",
        "	var f01 := clampf(fuel / FUEL_BRIGHT, 0.0, 1.0)\n",
    ),
    (
        "new funcs",
        "func _set_ember_glow(e: float) -> void:",
        NEW_FUNCS,
    ),
]


def main():
    dry = "--dry-run" in sys.argv
    path = os.path.normpath(TARGET)
    if "--target" in sys.argv:
        path = sys.argv[sys.argv.index("--target") + 1]
    src = open(path).read()
    before_lines = src.count("\n")

    if GUARD in src:
        print("patch_firelight: already applied (found '%s') -- nothing to do." % GUARD)
        return 0

    out = src
    report = []
    for name, old, new in EDITS:
        n = out.count(old)
        if n != 1:
            print("patch_firelight: ABORT -- anchor '%s' matched %d times, want exactly 1."
                  % (name, n))
            return 2
        out = out.replace(old, new, 1)
        report.append("  %-20s ok" % name)

    after_lines = out.count("\n")
    print("patch_firelight: %d/%d anchors matched exactly once" % (len(EDITS), len(EDITS)))
    for r in report:
        print(r)
    print("  lines %d -> %d  (+%d)" % (before_lines, after_lines, after_lines - before_lines))
    if dry:
        print("  --dry-run: nothing written")
        return 0
    open(path, "w").write(out)
    print("  written: %s" % path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
