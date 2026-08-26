"""Wire trees v2 into the live game. Run from the repo root.

Surgical: three anchored replacements plus one appended block. Every edit is
verified before it is written, and a .bak is left beside each patched file.
"""
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
if os.path.basename(ROOT) == "tools":
    ROOT = os.path.dirname(ROOT)


def patch(path, pairs, append=""):
    p = os.path.join(ROOT, path)
    src = open(p, encoding="utf-8").read()
    orig = src
    for old, new in pairs:
        if new in src:
            print("  = already patched:", path)
            continue
        if old not in src:
            print("  ! ANCHOR NOT FOUND in %s -- skipped:\n    %s" % (path, old.splitlines()[0]))
            continue
        src = src.replace(old, new, 1)
        print("  + patched", path)
    if append and append.strip().splitlines()[0] not in src:
        src = src.rstrip() + "\n\n" + append
        print("  + appended to", path)
    if src != orig:
        shutil.copyfile(p, p + ".bak")
        open(p, "w", encoding="utf-8").write(src)


# ---------------------------------------------------------------- World.gd

WORLD_OLD = '''func _make_tree(pos: Vector3) -> StaticBody3D:
	## Trees are real objects now (ChopTree.gd): the axe eats a wedge out of
	## the trunk, the trunk breaks at that wedge, the canopy comes apart on
	## impact and the trunk splits into logs. All of that lives with the tree.
	var tree := ChopTree.make(_rng)
	tree.position = pos
	tree.rotation.y = _rng.randf() * TAU
	return tree'''

WORLD_NEW = '''func _make_tree(pos: Vector3) -> StaticBody3D:
	## Trees v2 (docs/TREES_v2_SPEC.md): five New England species, five life
	## stages, real limbs. The axe takes the BRANCHES off first — the trunk
	## refuses a bite until the tree is bare — then the trunk goes over as a
	## physics body, and the fallen trunk bucks into logs.
	##
	## Set USE_TREES_V2 = false to fall back to the old cone trees (ChopTree.gd)
	## if something in the new pipeline misbehaves.
	if USE_TREES_V2:
		var t := TreeV2.make(_rng)
		t.position = pos
		t.rotation.y = _rng.randf() * TAU
		return t
	var tree := ChopTree.make(_rng)
	tree.position = pos
	tree.rotation.y = _rng.randf() * TAU
	return tree'''

WORLD_WIND_OLD = '''	_daynight.title_cb = _on_sky_title
	add_child(_daynight)'''

WORLD_WIND_NEW = '''	_daynight.title_cb = _on_sky_title
	add_child(_daynight)

	## One wind for the whole world: leaves, bark, and later grass and cloth all
	## read the same global shader parameters. See scripts/Wind.gd, spec §7.
	_wind = Wind.new()
	_wind.player = get_tree().get_first_node_in_group("player")
	add_child(_wind)
	Wind.publish_season(0.0)'''

patch("scripts/World.gd", [
    (WORLD_OLD, WORLD_NEW),
    (WORLD_WIND_OLD, WORLD_WIND_NEW),
    ("var _daynight: DayNight", "var _daynight: DayNight\nvar _wind: Wind\n\n## Trees v2 master switch — see _make_tree().\nconst USE_TREES_V2 := true"),
])


# --------------------------------------------------------------- Player.gd

CHOP_OLD = '''	var ct := tree as ChopTree
	if ct == null:
		return
	if ct.chop_hit(toward):
		_add_log_msg("Timber!", Color(0.85, 0.75, 0.5))'''

CHOP_NEW = '''	## Trees v2 and the old ChopTree both answer chop_hit(); v2 also wants to
	## know WHERE you were aiming, so it can pick the limb you were looking at
	## rather than an arbitrary one. See docs/TREES_v2_SPEC.md §8.
	var aim := global_position + (-camera.global_transform.basis.z) * 2.6 + Vector3.UP * 1.2
	var t2 := tree as TreeV2
	if t2 != null:
		if t2.trunk_blocked():
			## Line the swing up with the limb instead of hacking across it.
			var limb := t2.nearest_branch(global_position, aim)
			if limb != null:
				axe_swing_axis = limb.dir()
		else:
			axe_swing_axis = Vector3.ZERO
		if t2.chop_hit(toward, aim):
			_add_log_msg("Timber!", Color(0.85, 0.75, 0.5))
		elif t2.trunk_blocked() and t2.branches_left() <= 3:
			_add_log_msg("%d limbs left" % t2.branches_left(), Color(0.62, 0.66, 0.58))
		return
	if tree.has_method("chop_hit") and not (tree is ChopTree):
		## fallen trunks (bucking) and stumps (clearing) answer the same call
		tree.call("chop_hit", toward, aim)
		return
	var ct := tree as ChopTree
	if ct == null:
		return
	if ct.chop_hit(toward):
		_add_log_msg("Timber!", Color(0.85, 0.75, 0.5))'''

FKEY_OLD = '''			KEY_F:
				if menu_open == "":
					_try_interact()'''

FKEY_NEW = '''			KEY_F:
				## Pinned under a fallen trunk, F is the way out (spec §8b):
				## after ten seconds stuck it reloads your last save. Being
				## trapped under a log forever is a bug, not a story beat.
				if pinned_by != null:
					_pin_reload()
				elif menu_open == "":
					_try_interact()'''

PLAYER_APPEND = '''## ===================== Trees v2: limbing, pinning, rescue ===================
## docs/TREES_v2_SPEC.md §8. Added by tools/patch_repo.py — self-contained on
## purpose: nothing here needs a call from _process or _physics_process, so the
## main loops stay exactly as they were.

const PIN_STUCK_PROMPT := 10.0     ## seconds pinned before F offers a reload

## Set by _chop_tree so the axe animation can swing ALONG a limb instead of
## across it. Zero means "no limb in particular" — swing normally.
## TODO(anim): read this in the axe swing to rotate the arc onto the limb axis.
var axe_swing_axis := Vector3.ZERO

var pinned_by: Node3D = null
var pin_t := 0.0
var _pin_watch: Node
var _pin_label: Label


func armor_tier() -> int:
	## How much plate is between you and a falling tree. A trunk knocks an
	## armoured body down; it PINS an unarmoured one.
	## TODO(equipment): return the worn chest piece's material tier here — one
	## line once the equipment slot exposes its material id.
	return 0


func pin_under(what: Node3D, _seconds := 7.0) -> void:
	if pinned_by != null:
		return
	pinned_by = what
	pin_t = 0.0
	_start_knockdown(what.global_position if is_instance_valid(what) else global_position)
	kd_phase = "pinned"          ## stays down until the trunk moves off
	_add_log_msg("Pinned!", Color(0.85, 0.35, 0.25))

	## A tiny watcher node runs the timer, so Player's main loops are untouched.
	_pin_watch = Node.new()
	_pin_watch.set_script(preload("res://scripts/PinWatcher.gd"))
	_pin_watch.set("target", self)
	add_child(_pin_watch)


func release_pin() -> void:
	if pinned_by == null:
		return
	pinned_by = null
	pin_t = 0.0
	kd_phase = "rise"
	kd_t = 0.0
	_hide_pin_prompt()
	if _pin_watch != null and is_instance_valid(_pin_watch):
		_pin_watch.queue_free()
		_pin_watch = null


func pin_tick(delta: float) -> void:
	## Called by PinWatcher.
	if pinned_by == null or not is_instance_valid(pinned_by):
		release_pin()
		return
	pin_t += delta
	if pin_t >= PIN_STUCK_PROMPT:
		_show_pin_prompt()


func _show_pin_prompt() -> void:
	if _pin_label != null:
		return
	_pin_label = Label.new()
	_pin_label.text = "[F]  reload last save"
	_pin_label.add_theme_font_size_override("font_size", 19)
	_pin_label.modulate = Color(0.88, 0.84, 0.72, 0.92)
	_pin_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_pin_label.offset_top = -140.0
	_pin_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if hud_layer != null:
		hud_layer.add_child(_pin_label)


func _hide_pin_prompt() -> void:
	if _pin_label != null and is_instance_valid(_pin_label):
		_pin_label.queue_free()
	_pin_label = null


func _pin_reload() -> void:
	if pin_t < PIN_STUCK_PROMPT:
		return               ## no bailing out of the first ten seconds
	_hide_pin_prompt()
	SaveGame.load_game(self)
'''

patch("scripts/Player.gd", [(CHOP_OLD, CHOP_NEW), (FKEY_OLD, FKEY_NEW)], append=PLAYER_APPEND)

print("done. .bak files left beside anything that changed.")
