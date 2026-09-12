#!/usr/bin/env python3
"""patch_exposure.py -- wire scripts/Exposure.gd into the player.

    python3 tools/patch_exposure.py [--dry-run]

Idempotent and PURELY ADDITIVE. `scripts/Player.gd` and `scripts/World.gd`
carry thousands of lines of Lemon's own uncommitted work and have silently
lost some of it to a patcher twice, so this script:

  * refuses to run unless every anchor matches EXACTLY ONCE,
  * guards each hunk on what it DEFINES, never on a call it also writes (a
    marker-guard that matches a call as well as a definition is not a guard --
    2026-09-05 09:00),
  * removes nothing, ever, and prints the line delta so the caller can check
    it is +n / -0.

The model itself lives in scripts/Exposure.gd and is tested headless with no
player at all (tests/ExposureTests.gd, 168 assertions, 48/48 mutations caught).
What lands here is only the wiring: an environment dictionary built once a
frame, a shelter ray throttled to one every second and a half, a HUD bar, the
settings row, the save keys and the respawn clamp.

THREE THINGS IN HERE WERE FOUND BY RUNNING THE GAME, not by the suite, and
each is commented at the line it fixes:
  * the torch test must read `offhand_shown`, not `tp_torch.visible`;
  * cold damage must reset `combat_timer`, or the out-of-combat regen outruns
    it and a man at zero warmth never dies;
  * GDScript has no implicit line continuation outside brackets, so the
    settings note is one string and not three added together.

NO NEW KEY BINDING. This feature adds nothing to `Player._input` and that is
asserted against the source in ExposureTests._t_no_bindings.
"""

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLAYER = os.path.join(ROOT, "scripts", "Player.gd")
WORLD = os.path.join(ROOT, "scripts", "World.gd")


# --- World.gd: the two accessors the spec's step 1 asked for ---------------

WORLD_ACCESSORS = '''func daynight() -> DayNight:
	## [exposure] The clock, for anything that needs the hour or the day.
	## `_daynight` was private and Exposure is the third customer to want it.
	return _daynight


func underground() -> bool:
	## [exposure] Public face of `_underground`: a cave shelters you from the
	## wind and the rain exactly as a roof does.
	return _underground


'''


# --- Player.gd -------------------------------------------------------------

PLAYER_BLOCK = '''

## --- exposure and warmth (2026-09-10, SYSTEMS) -----------------------------
## The model is scripts/Exposure.gd and every degree of it is a pure function.
## What lives here is the wiring: build the environment once a frame, hand it
## to `exposure.step()`, and do as the report says. No decision is taken in
## this file, which is why the whole feature is testable without a Player.
const EXPOSURE_SHELTER_UP := 7.0        ## how far overhead we look for a roof
const EXPOSURE_SHELTER_RECHECK := 1.5   ## seconds between shelter rays

var exposure := Exposure.new()
var set_warmth_mode := 0                ## 0 Survival / 1 Light  (Settings)
var warmth_show := 0.0
var warmth_bar: Control
var warmth_fill: ColorRect
var _exposure_sheltered := false
var _exposure_shelter_t := 0.0


func warmth_survival() -> bool:
	return set_warmth_mode == 0


func _exposure_roof() -> bool:
	## One ray straight up, EXPOSURE_SHELTER_RECHECK seconds apart. A roof
	## takes the wind AND the precipitation off you, which is the whole reason
	## to build one before you are cold rather than after.
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var from := global_position + Vector3(0.0, 1.2, 0.0)
	var q := PhysicsRayQueryParameters3D.create(from,
			from + Vector3(0.0, EXPOSURE_SHELTER_UP, 0.0))
	q.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	return not hit.is_empty()


func _exposure_env() -> Dictionary:
	## Everything Exposure needs, gathered from the four places that hold it.
	## Nothing here decides anything; it reads.
	var w := get_tree().get_first_node_in_group("world")
	var wx: Object = null
	var dn: Object = null
	var under := false
	if w != null:
		if w.has_method("weather"):
			wx = w.call("weather")
		if w.has_method("daynight"):
			dn = w.call("daynight")
		if w.has_method("underground"):
			under = bool(w.call("underground"))
	var hour := 12.0
	var day := 30.0
	if dn != null:
		hour = float(dn.get("hour"))
		day = float(dn.get("day"))
	var level := 0
	var intensity := 0.0
	var snowing := false
	var wind := 0.0
	if wx != null:
		level = int(wx.get("level"))
		intensity = clampf(float(wx.get("intensity")), 0.0, 1.0)
		if wx.has_method("is_snowing"):
			snowing = bool(wx.call("is_snowing"))
		var wnode: Object = wx.get("wind")
		if wnode != null:
			wind = clampf(float(wnode.get("last_strength")), 0.0, 1.0)
	return Exposure.env({
		"season": Exposure.season_for_day(day),
		"hour": hour,
		"y": global_position.y,
		"level": level,
		"intensity": intensity,
		"snowing": snowing,
		"wind": wind,
		"sheltered": _exposure_sheltered,
		"underground": under,
		"fire_c": Exposure.fire_c(get_tree().get_nodes_in_group("fires"), global_position),
		## NOT `tp_torch.visible`: that node exists from boot, and its
		## visibility is also gated on `cam_mode == "tp"`, so reading it gave
		## the player a lit torch's 3.5 C for ever in third person and none of
		## it in first. What is actually in the left hand is `offhand_shown`
		## (found live, 2026-09-10).
		"torch": String(offhand_shown).contains("Torch") \\
			or String(offhand_shown2).contains("Torch"),
		## Myrkfell's sleep is an instantaneous blackout rather than a state, so
		## nothing sets this yet. The term is modelled and tested because it is
		## the top rung of the winter camp ladder; wiring it belongs with the
		## `World.sleep_at_bed` fix (SYSTEMS #2), which has to land first.
		"asleep": false,
		"swimming": swimming,
		"mode": Exposure.mode_now(),
		"survival": warmth_survival(),
	})


func _exposure_tick(delta: float) -> void:
	warmth_show = maxf(0.0, warmth_show - delta)
	if god:
		## The map-authoring mode pins health, stamina and thirst; it pins this
		## too, or an afternoon spent building in a winter sky kills you.
		exposure.warmth = Exposure.WARMTH_MAX
		exposure.wet = 0.0
		return
	_exposure_shelter_t -= delta
	if _exposure_shelter_t <= 0.0:
		_exposure_shelter_t = EXPOSURE_SHELTER_RECHECK
		_exposure_sheltered = _exposure_roof()
	var r: Dictionary = exposure.step(_exposure_env(), delta)
	var crossed := String(r["crossed"])
	if crossed != "" and Exposure.MESSAGES.has(crossed):
		var m: Array = Exposure.MESSAGES[crossed]
		_add_log_msg(String(m[0]), m[1] as Color)
		warmth_show = 3.0
	var dmg := float(r["damage"])
	if dmg > 0.0 and invuln_timer <= 0.0 and health > 0.0:
		health = maxf(0.0, health - dmg)
		health_show = 1.0
		## THE COLD IS A WOUND, NOT A STATUS. Without this the out-of-combat
		## regen a few lines down in `_process` outruns WARMTH_DAMAGE_PER_S
		## and a soaked man at zero warmth in a winter gale sits at a hundred
		## health for ever -- which is what he did, live, before this line.
		combat_timer = 0.0
		if health <= 0.0:
			_die()
'''


HUNKS = [
    # (file, guard-substring, anchor, insertion, where)
    (WORLD, "func underground()", "func is_dark_out() -> bool:", WORLD_ACCESSORS, "before"),

    (PLAYER, "func warmth_survival",
     "func thirst_survival() -> bool:\n\treturn set_thirst_mode == 0\n",
     PLAYER_BLOCK, "after"),

    (PLAYER, "_exposure_tick(delta)", "\t_thirst_tick(delta)\n",
     "\t_exposure_tick(delta)\n", "after"),

    (PLAYER, "warmth_bar = wm[0]", "\tthirst_bar.modulate.a = 0.10\n",
     "\tvar wm := _make_bar(6.0, Color(0.92, 0.62, 0.34))    ## [exposure] warmth (amber)\n"
     "\twarmth_bar = wm[0]\n"
     "\twarmth_fill = wm[1]\n"
     "\twarmth_bar.modulate.a = 0.10\n", "after"),

    (PLAYER, "warmth_bar.modulate.a = lerpf",
     "\t\tthirst_bar.modulate.a = lerpf(thirst_bar.modulate.a, t_target, delta * 6.0)\n",
     "\tif warmth_bar:\n"
     "\t\twarmth_bar.visible = warmth_survival()\n"
     "\t\t## Above breath, which is above thirst, stamina and health.\n"
     "\t\twarmth_bar.position = Vector2(cx, vp.y - 104.0)\n"
     "\t\t(warmth_bar.get_child(0) as ColorRect).size.x = bw\n"
     "\t\twarmth_fill.size.x = bw * clampf(exposure.warmth / Exposure.WARMTH_MAX, 0.0, 1.0)\n"
     "\t\t## amber while you are warm, and the colour of the weather when you are not\n"
     "\t\twarmth_fill.color = Color(0.92, 0.62, 0.34) if exposure.warmth >= Exposure.WARMTH_LOW "
     "else Color(0.55, 0.76, 1.0)\n"
     "\t\tvar w_target := 1.0 if (exposure.warmth < Exposure.WARMTH_LOW or warmth_show > 0.0) else 0.10\n"
     "\t\twarmth_bar.modulate.a = lerpf(warmth_bar.modulate.a, w_target, delta * 6.0)\n", "after"),

    (PLAYER, "\"warmth\": exposure.warmth,", "\t\t\"thirst\": thirst,\n",
     "\t\t\"warmth\": exposure.warmth,\n\t\t\"wet\": exposure.wet,\n", "after"),

    (PLAYER, "exposure.apply_dict(d)",
     "\tthirst = clampf(float(d.get(\"thirst\", THIRST_MAX)), 0.0, THIRST_MAX)\n",
     "\texposure.apply_dict(d)\n", "after"),

    (PLAYER, "exposure.on_respawn()",
     "\tthirst = maxf(thirst, 60.0)         ## [water] never respawn already dying of it\n",
     "\texposure.on_respawn()               ## [exposure] nor already dying of cold\n", "after"),

    # GDScript has NO implicit line continuation outside brackets: written as
    # three strings joined by a leading `+` on the next line, this note was a
    # hard parse error that took Player.gd down with it. One string.
    (PLAYER, "\"Warmth\", \"warmth\"", "\tvb.add_child(th_note)\n",
     "\t_settings_option_row(vb, \"Warmth\", \"warmth\",\n"
     "\t\t[[\"Survival\", 0], [\"Light\", 1]])\n"
     "\tvar wa_note := Label.new()\n"
     "\twa_note.text = \"Survival: the cold is real -- an autumn night is a slow problem and a\\n"
     "winter one is not, being soaked doubles it, and a roof, a torch and a lit fire\\n"
     "are the three answers. Light: no meter, and no cold. Switches live, any time.\"\n"
     "\twa_note.add_theme_font_size_override(\"font_size\", 13)\n"
     "\twa_note.modulate = Color(1, 1, 1, 0.55)\n"
     "\tvb.add_child(wa_note)\n", "after"),

    # One match arm, not a second `if` bolted onto the thirst block: a lone
    # `\tif ...` inserted after a 2-tab line dedents out of the block it lands
    # in and orphans whatever followed.
    (PLAYER, "set_warmth_mode = int(value)",
     "\t\t\"thirst\": set_thirst_mode = int(value)\n",
     "\t\t\"warmth\":\n"
     "\t\t\tset_warmth_mode = int(value)\n"
     "\t\t\t## Switching to Light TOPS the meter, so switching back can never\n"
     "\t\t\t## start you freezing. The thirst pass established that rule.\n"
     "\t\t\tif set_warmth_mode == 1:\n"
     "\t\t\t\texposure.to_light()\n", "after"),

    (PLAYER, "\"warmth\": cur = set_warmth_mode",
     "\t\t\t\t\"thirst\": cur = set_thirst_mode\n",
     "\t\t\t\t\"warmth\": cur = set_warmth_mode\n", "after"),

    (PLAYER, "cf.set_value(\"game\", \"warmth\"",
     "\tcf.set_value(\"game\", \"thirst\", \"survival\" if set_thirst_mode == 0 else \"light\")\n",
     "\tcf.set_value(\"game\", \"warmth\", \"survival\" if set_warmth_mode == 0 else \"light\")\n",
     "after"),

    (PLAYER, "set_warmth_mode = 1 if",
     "\tset_thirst_mode = 1 if String(cf.get_value(\"game\", \"thirst\", \"survival\")) == \"light\" else 0\n",
     "\tset_warmth_mode = 1 if String(cf.get_value(\"game\", \"warmth\", \"survival\")) == \"light\" else 0\n",
     "after"),
]


def main():
    dry = "--dry-run" in sys.argv
    files = {}
    for path in (PLAYER, WORLD):
        with open(path, "r") as fh:
            files[path] = fh.read()
    before = {p: files[p].count("\n") for p in files}

    applied, skipped, failed = [], [], []
    for path, guard, anchor, ins, where in HUNKS:
        src = files[path]
        name = "%s :: %s" % (os.path.basename(path), guard.strip()[:44])
        if guard in src:
            skipped.append(name)
            continue
        n = src.count(anchor)
        if n != 1:
            failed.append((name, "anchor matched %d times, not once" % n))
            continue
        if where == "after":
            files[path] = src.replace(anchor, anchor + ins, 1)
        else:
            files[path] = src.replace(anchor, ins + anchor, 1)
        applied.append(name)

    print("applied %d, already present %d, FAILED %d"
          % (len(applied), len(skipped), len(failed)))
    for n in applied:
        print("  +  %s" % n)
    for n in skipped:
        print("  =  %s" % n)
    for n, why in failed:
        print("  !! %s  (%s)" % (n, why))
    if failed:
        print("\nREFUSING TO WRITE: an anchor moved. Nothing has been changed.")
        return 2

    for path in files:
        after = files[path].count("\n")
        print("%s  %+d lines" % (os.path.basename(path), after - before[path]))
        if after < before[path]:
            print("REFUSING TO WRITE: %s would LOSE lines." % path)
            return 2

    if dry:
        print("\n--dry-run: nothing written.")
        return 0
    for path in files:
        with open(path, "w") as fh:
            fh.write(files[path])
    print("\nwritten.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
