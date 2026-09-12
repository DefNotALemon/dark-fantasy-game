#!/usr/bin/env python3
"""Wire the god editor into Player.gd and World.gd.

Re-runnable: every hunk checks for its own marker first and skips if present.
Anchors are exact strings lifted from the live files.
"""
import sys, pathlib

SRC = pathlib.Path(__file__).resolve().parent.parent / "scripts"
OUT = SRC   ## in the repo this patches the real files in place
OUT.mkdir(parents=True, exist_ok=True)

changes = []

def patch(text, anchor, addition, marker, where="after", name=""):
    if marker in text:
        changes.append(f"  = {name}: already present")
        return text
    if text.count(anchor) != 1:
        raise SystemExit(f"ANCHOR {'MISSING' if anchor not in text else 'AMBIGUOUS'} for {name}:\n{anchor[:120]}")
    if where == "after":
        new = text.replace(anchor, anchor + addition)
    elif where == "before":
        new = text.replace(anchor, addition + anchor)
    else:  # replace
        new = text.replace(anchor, addition)
    changes.append(f"  + {name}")
    return new


def append(text, block, marker, name=""):
    """Append a block at EOF, once. Same idempotence contract as patch()."""
    if marker in text:
        changes.append(f"  = {name}: already present")
        return text
    changes.append(f"  + {name}")
    return text + block


# =========================================================================
#  Player.gd
# =========================================================================
p = (SRC / "Player.gd").read_text()

# --- A. state ------------------------------------------------------------
p = patch(p, "const SHEATH_TIME := 0.40\n", """
## --- GOD MODE (scripts/GodEditor.gd -- F1) ---------------------------------
## The map-authoring mode. `god` pins health/stamina/thirst/breath and refuses
## every source of damage; `flying` is Minecraft flight (double-tap Space) with
## collision parked; `god_speed` is the scroll wheel, and it multiplies walking
## AND flying, so wheel-up is faster wherever you are and wheel-down comes back
## down to 1.0 = the ordinary walk.
const GOD_FLY_SPEED := 12.0    ## m/s at god_speed 1.0
const GOD_FLY_BOOST := 3.2     ## Shift, while flying
const GOD_SPEED_MIN := 0.35
const GOD_SPEED_MAX := 24.0
const GOD_DOUBLE_TAP_MS := 320
var god := false
var flying := false
var god_speed := 1.0
var godmode: GodEditor = null
var _space_tap_ms := 0
var _god_mask_saved := -1      ## collision_mask parked while noclipping
""", "var godmode: GodEditor", name="Player: god state")

# --- A2. spectator state (own marker: the block above may already be in) --
p = patch(p, "var _god_mask_saved := -1      ## collision_mask parked while noclipping\n",
"""
## --- SPECTATOR MODE (scripts/EditorCam.gd) ---------------------------------
## `editing` means the camera has LEFT THE BODY. The character stands where you
## stepped out of them, collision_layer parked at 0 and EditorMode.active true,
## so nothing in the world can see, reach or hunt them; the editor camera flies
## on its own. Closing the editor puts you back in their head.
## `god_sticky` is the panel's GOD toggle: it decides whether the body you go
## BACK to is invulnerable. Spectating is invulnerable either way.
var editing := false
var god_sticky := false
var _editor_cam_mode := ""     ## the view you were using before you stepped out
var _god_layer_saved := -1     ## collision_layer parked while the body is out
""", "var editing := false", name="Player: spectator state")

# --- B. build the panel --------------------------------------------------
p = patch(p, "\tsky_panel = SkyMenu.new()\n\thud_layer.add_child(sky_panel)\n",
"""	## The god editor builds itself too (scripts/GodEditor.gd) -- F1 opens it.
	godmode = GodEditor.new()
	hud_layer.add_child(godmode)
""", "godmode = GodEditor.new()", name="Player: build GodEditor")

# --- C. _input: hand everything to the editor first ----------------------
p = patch(p, """func _input(event: InputEvent) -> void:
	if input_locked:
		return  ## nothing gets through a blackout
""", """	## GOD MODE gets first refusal on every event while its panel is up, so
	## the editor and the game can never both act on one click or one key.
	## GodEditor.eat_input returns true when it has taken the event.
	if godmode != null and godmode.eat_input(event):
		return
	if god and event is InputEventMouseButton and (godmode == null or not godmode.visible):
		## The wheel is the speed dial even with the panel closed.
		var gmb := event as InputEventMouseButton
		if gmb.pressed and gmb.button_index == MOUSE_BUTTON_WHEEL_UP:
			god_speed = clampf(god_speed * 1.22, GOD_SPEED_MIN, GOD_SPEED_MAX)
			return
		if gmb.pressed and gmb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			god_speed = clampf(god_speed / 1.22, GOD_SPEED_MIN, GOD_SPEED_MAX)
			if absf(god_speed - 1.0) < 0.06:
				god_speed = 1.0
			return
""", "godmode.eat_input(event)", name="Player: _input handoff")

# --- D. F1 + double-tap space -------------------------------------------
p = patch(p, """			KEY_SPACE:
				if menu_open == "" and kd_phase == "" and not climbing:
""", """			KEY_F1:
				## F1 IS GOD MODE. Opens the editor panel and turns god on.
				_toggle_menu("god")
			KEY_SPACE:
				## GOD: double-tap Space toggles flight, Minecraft-style. While
				## flying, Space is "up" and never a jump.
				if god:
					var tap := Time.get_ticks_msec()
					if tap - _space_tap_ms < GOD_DOUBLE_TAP_MS:
						flying = not flying
						if not flying:
							velocity = Vector3.ZERO
						_space_tap_ms = 0
						if godmode != null:
							godmode._flag("fly", flying)
						_add_log_msg("Flight %s" % ("on" if flying else "off"),
							Color(0.62, 0.92, 1.0))
					else:
						_space_tap_ms = tap
					if flying:
						return
				if menu_open == "" and kd_phase == "" and not climbing:
""", "KEY_F1:", where="replace", name="Player: F1 + flight tap")

# --- E. _physics_process: restore mask, then the fly branch --------------
p = patch(p, """func _physics_process(delta: float) -> void:
	since_last_attack += delta
""", """	## Leaving flight (or god) puts the collision mask back exactly as found.
	if _god_mask_saved >= 0 and not (god and flying):
		collision_mask = _god_mask_saved
		_god_mask_saved = -1
""", "_god_mask_saved >= 0 and not (god and flying)", name="Player: mask restore")

p = patch(p, """	since_last_attack += delta
""", """	## SPECTATOR: the camera is out. The body is parked and owns nothing --
	## checked FIRST, above the knockdown and grab branches, because none of
	## those may run on a body the world is not allowed to touch.
	if editing:
		_editor_freeze(delta)
		return

""", "if editing:\n\t\t_editor_freeze(delta)", name="Player: editor freeze branch")

p = patch(p, """	## Blackout / bed animation: the body stands (or lies) quietly — gravity
""", """	## GOD FLIGHT owns the frame: noclip, no gravity, no gait, no stamina.
	if god and flying:
		_god_fly(delta)
		return

""", "if god and flying:\n\t\t_god_fly(delta)", where="before", name="Player: fly branch")

# --- F. the flight itself ------------------------------------------------
p = patch(p, "\ndef __never__", "", "___unused___", name="noop") if False else p
p = append(p, '''

## ========================== GOD FLIGHT (F1 mode) ===========================

func _god_fly(delta: float) -> void:
	## Minecraft rules. You hang where you let go. WASD flies along the LOOK
	## (nose down and W dives), Space climbs, Ctrl drops, Shift is the boost,
	## and the scroll wheel's god_speed multiplies the lot. Collision is parked
	## for the duration and restored the instant flight ends.
	if _god_mask_saved < 0:
		_god_mask_saved = collision_mask
		collision_mask = 0
	var typing := godmode != null and godmode.typing
	var iv := Vector3.ZERO
	if not typing:
		if Input.is_key_pressed(KEY_W): iv.z -= 1.0
		if Input.is_key_pressed(KEY_S): iv.z += 1.0
		if Input.is_key_pressed(KEY_A): iv.x -= 1.0
		if Input.is_key_pressed(KEY_D): iv.x += 1.0
	var dir := head.global_transform.basis * iv
	if not typing:
		if Input.is_key_pressed(KEY_SPACE):
			dir.y += 1.0
		if Input.is_key_pressed(KEY_CTRL):
			dir.y -= 1.0
	if dir.length_squared() > 0.000001:
		dir = dir.normalized()
	else:
		dir = Vector3.ZERO
	var spd := GOD_FLY_SPEED * god_speed
	if not typing and Input.is_key_pressed(KEY_SHIFT):
		spd *= GOD_FLY_BOOST
	## Snappy but not instant -- a 60 m/s stop on one key-up reads as a bug.
	velocity = velocity.move_toward(dir * spd, maxf(60.0, spd * 6.0) * delta)
	move_and_slide()
	## Keep the streamer looking at us so there is ground under the landing.
	crouching = false
	prone = false
	sprinting = false
	_frame_fx_and_regen(delta)
	_update_body_arms(delta)
	_update_hud(delta)
	_update_log(delta)


func god_teleport(to: Vector3) -> void:
	## Used by the editor's teleport buttons: build the near ring FIRST so the
	## body does not fall through a tile that has not arrived yet.
	if Overworld.inst != null:
		Overworld.inst.warm(to)
	global_position = to
	velocity = Vector3.ZERO
''', "func _god_fly(", name="Player: _god_fly + god_teleport")

p = append(p, '''

func set_editing(on: bool) -> void:
	## STEP OUT OF THE BODY, and step back in. The one place `editing`,
	## EditorMode.active and the parked collision layer are allowed to change,
	## so the flag and the body can never disagree.
	if editing == on:
		return
	editing = on
	god = editing or god_sticky
	EditorMode.active = editing
	if on:
		flying = false
		jump_queued = false
		drawing = false
		attacking = false
		blocking = false
		## Third person while you are out, so you can SEE the body you left --
		## and so the first-person hands are not hanging in the air where your
		## head used to be. cam_mode is set directly, not through
		## _set_cam_mode, because this is temporary and must not be saved as
		## your camera preference.
		_editor_cam_mode = cam_mode
		cam_mode = "tp"
		cam_snap = 1.0
		sheathed = true
		if _god_layer_saved < 0:
			_god_layer_saved = collision_layer
		## THE UNTOUCHABLE HALF: with no layer, nothing's sensor, ray, hitbox
		## or falling trunk can find the body at all. EditorMode covers the
		## half that finds you by group instead.
		collision_layer = 0
	else:
		if _editor_cam_mode != "":
			cam_mode = _editor_cam_mode
			_editor_cam_mode = ""
		cam_snap = 1.0
		if _god_layer_saved >= 0:
			collision_layer = _god_layer_saved
			_god_layer_saved = -1
		velocity = Vector3.ZERO
		if camera != null:
			camera.current = true
		_update_head_offset()


func _editor_freeze(delta: float) -> void:
	## The parked body. It keeps its weight -- step out mid-jump and it lands
	## and stands there -- but it has no will: no input, no gait, no attack,
	## no interaction. Everything that only DRAWS still runs, so the character
	## you are looking at from the camera breathes and holds its gear properly.
	if not is_on_floor():
		velocity.y -= gravity * delta
	velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)
	move_and_slide()
	_frame_fx_and_regen(delta)
	_update_camera_arm(delta)
	_update_body_arms(delta)
	_update_tp_gear(delta)
	_update_hud(delta)
	_update_log(delta)
''', "func set_editing(", name="Player: set_editing + _editor_freeze")

# --- F2. mouse motion goes to the spectator camera ------------------------
p = patch(p, """func _unhandled_input(event: InputEvent) -> void:
	if input_locked:
		return  ## blackout / bed animation — even the eyes stay still
""", """	## SPECTATOR: mouse motion turns the CAMERA, not the parked body. Returning
	## here matters -- without it your character spins on the spot while you fly.
	if godmode != null and godmode.take_motion(event):
		return
""", "godmode.take_motion(event)", name="Player: motion to the spectator cam")

# --- G0. RMB is "look" while the editor is up, not "block" ----------------
p = patch(p, """	blocking = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and block_broken_timer <= 0.0 \\
		and current_weapon == "sword"  ## both hands are busy with the bow
""", """	blocking = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and block_broken_timer <= 0.0 \\
		and current_weapon == "sword" \\
		and (godmode == null or not godmode.visible)  ## RMB is look-drag in god mode
""", "RMB is look-drag in god mode", where="replace", name="Player: no guard while editing")

# --- G. damage + upkeep --------------------------------------------------
p = patch(p, """func take_damage(amount: float, from_pos := Vector3.INF, strong := false, lunge_throw := Vector3.INF, attacker: Node = null) -> void:
""", """	if god:
		return  ## GOD MODE: nothing in the world gets to touch you.
""", "return  ## GOD MODE: nothing in the world", name="Player: damage immunity")

p = patch(p, """func _frame_fx_and_regen(delta: float) -> void:
""", """	if god:
		## GOD MODE pins the four bars every frame, so nothing drains while
		## you are laying out a town. Done here because every stance -- on
		## foot, flying, mounted, face-down -- comes through this one function.
		health = max_health
		stamina = max_stamina
		stamina_delay = 0.0
		thirst = THIRST_MAX
		breath = 100.0
""", "GOD MODE pins the four bars", name="Player: pin bars")

# --- G2. FALL DAMAGE IS OFF ----------------------------------------------
# Per Lemon 2026-09-02: "get rid of fall damage". Made a real Settings switch
# rather than deleted, because the numbers were tuned and a survival game may
# want them back -- but it is OFF by default, so out of the box the ground
# cannot hurt you and a hard landing never folds your legs.
p = patch(p, "var set_blood := true            ## Blood: off swaps red for a neutral impact puff\n",
"""var set_fall_dmg := false        ## Fall damage: OFF by default (Lemon, 2026-09-02).
                                 ## Gates the hard-landing knockdown too -- that
                                 ## was the half god mode did not already cover.
""", "var set_fall_dmg", name="Player: fall damage setting")

p = patch(p, """func _apply_fall_damage(spd: float) -> void:
	## Called once at touchdown with the impact speed. Bypasses blocking and
	## i-frames — the ground doesn't care how good your guard is.
	if spd <= FALL_SAFE_SPEED or kd_phase != "" or mount != null or climbing:
		return
""", """func _apply_fall_damage(spd: float) -> void:
	## Called once at touchdown with the impact speed. Bypasses blocking and
	## i-frames — the ground doesn't care how good your guard is.
	##
	## ...unless it is switched off, which it is by default (Settings -> Fall
	## Damage). This ONE early return kills the health hit, the death, and the
	## hard-landing knockdown together: leaving the knockdown behind would read
	## as "fall damage is still on" even with the number at zero. The camera
	## dip and the landing sound are not damage and stay.
	if not set_fall_dmg or god:
		return
	if spd <= FALL_SAFE_SPEED or kd_phase != "" or mount != null or climbing:
		return
""", "if not set_fall_dmg or god:", where="replace", name="Player: gate fall damage")

FALL_ROW = (
	'\t_settings_option_row(vb, "Fall Damage", "falldmg",\n'
	'\t\t[["Off", false], ["On", true]])\n'
	'\tvar fall_note := Label.new()\n'
	'\tfall_note.text = "Off: the ground cannot hurt you and a hard landing never knocks you down.'
	'\\nOn: over 11 m/s at touchdown costs health, and over 17.5 m/s puts you flat.'
	'\\nSwitches live, any time."\n'
	'\tfall_note.add_theme_font_size_override("font_size", 13)\n'
	'\tfall_note.modulate = Color(1, 1, 1, 0.55)\n'
	'\tvb.add_child(fall_note)\n\n')
BLOOD_ROW = '\t_settings_option_row(vb, "Blood", "blood",\n\t\t[["Off", false], ["On", true]])\n'
p = patch(p, BLOOD_ROW, FALL_ROW + BLOOD_ROW, "var fall_note := Label.new()",
	where="replace", name="Player: fall damage row")

p = patch(p, '\t\t"blood": set_blood = bool(value)\n',
	'\t\t"falldmg": set_fall_dmg = bool(value)\n\t\t"blood": set_blood = bool(value)\n',
	'"falldmg": set_fall_dmg = bool(value)', where="replace", name="Player: fall damage pick")

p = patch(p, '\t\t\t\t"blood": cur = set_blood\n',
	'\t\t\t\t"falldmg": cur = set_fall_dmg\n\t\t\t\t"blood": cur = set_blood\n',
	'"falldmg": cur = set_fall_dmg', where="replace", name="Player: fall damage refresh")

p = patch(p, '\tcf.set_value("game", "blood", set_blood)\n',
	'\tcf.set_value("game", "blood", set_blood)\n\tcf.set_value("game", "fall_dmg", set_fall_dmg)\n',
	'cf.set_value("game", "fall_dmg"', where="replace", name="Player: fall damage save")

p = patch(p, '\tset_blood = bool(cf.get_value("game", "blood", true))\n',
	'\tset_blood = bool(cf.get_value("game", "blood", true))\n'
	'\tset_fall_dmg = bool(cf.get_value("game", "fall_dmg", false))\n',
	'set_fall_dmg = bool(cf.get_value', where="replace", name="Player: fall damage load")

# --- G3. nothing may manhandle a god / a parked body ----------------------
# take_damage already returns early on `god`. These four are the paths that do
# not go through it: they move you, pin you or put you in a mouth. The parked
# body is also on collision_layer 0, so in practice none of them can even find
# it -- these are the belt to that pair of braces.
p = patch(p, """func _start_knockdown(_from_pos: Vector3, fling := Vector3.ZERO) -> void:
	## Down you go. Cancels everything in your hands; protects NOTHING.
""", """func _start_knockdown(_from_pos: Vector3, fling := Vector3.ZERO) -> void:
	## Down you go. Cancels everything in your hands; protects NOTHING.
	if god:
		return  ## ...except god mode. Every knockdown path funnels through here.
""", "return  ## ...except god mode. Every knockdown path", where="replace",
name="Player: no knockdown in god")

p = patch(p, """	if grabbed_by != null or pressed_by != null or mount != null or kd_phase != "" \\
			or input_locked or climbing or attacker == null:
		return "no"
""", """	if god or grabbed_by != null or pressed_by != null or mount != null or kd_phase != "" \\
			or input_locked or climbing or attacker == null:
		return "no"
""", 'if god or grabbed_by != null or pressed_by != null', where="replace",
name="Player: no grab in god")

p = patch(p, """	if pressed_by != null or grabbed_by != null or mount != null or kd_phase != "" \\
			or input_locked or climbing or attacker == null:
		return false
""", """	if god or pressed_by != null or grabbed_by != null or mount != null or kd_phase != "" \\
			or input_locked or climbing or attacker == null:
		return false
""", 'if god or pressed_by != null or grabbed_by != null', where="replace",
name="Player: no press in god")

p = patch(p, """func pin_under(what: Node3D, _seconds := 7.0) -> void:
	if pinned_by != null:
		return
""", """func pin_under(what: Node3D, _seconds := 7.0) -> void:
	if pinned_by != null or god:
		return
""", "if pinned_by != null or god:", where="replace", name="Player: no pin in god")

# --- H. menu plumbing ----------------------------------------------------
p = patch(p, """	if which == "sky" and sky_panel:
		sky_panel.refresh()
""", """	if godmode != null:
		if which == "god":
			godmode.opened()
		elif godmode.visible:
			godmode.closed()
""", 'if which == "god":\n\t\t\tgodmode.opened()', name="Player: _toggle_menu god")

p = patch(p, """func _close_menu() -> void:
	menu_open = ""
""", """	if godmode != null and godmode.visible:
		godmode.closed()
""", "if godmode != null and godmode.visible:\n\t\tgodmode.closed()", name="Player: _close_menu god")

(OUT / "Player.gd").write_text(p)

# =========================================================================
#  World.gd
# =========================================================================
w = (SRC / "World.gd").read_text()

w = patch(w, """	if _out_of_world(_player.global_position):  ## [terrain] bounds net
		_player.global_position = _world_home()
		_player.velocity = Vector3.ZERO
""", """	if _out_of_world(_player.global_position) and not _player.god:  ## [terrain] bounds net
		_player.global_position = _world_home()
		_player.velocity = Vector3.ZERO
""", "_out_of_world(_player.global_position) and not _player.god",
where="replace", name="World: bounds net respects god")

w = patch(w, """	if _region != null and _region.is_fully_loaded() and _player.global_position.y < 0.0 \\
			and _region.in_footprint(_player.global_position) \\""",
"""	if _region != null and _region.is_fully_loaded() and _player.global_position.y < 0.0 \\
			and not _player.god \\
			and _region.in_footprint(_player.global_position) \\""",
"and not _player.god \\", where="replace", name="World: rock net respects god")

w = patch(w, """			if (t as Node).has_meta("streamed"):
				continue
""", """			if (t as Node).has_meta("streamed"):
				continue
			## ...and neither are the ones the god editor planted: those live
			## in design/build_placements.json and are restored by the
			## "builder" group, so they survive a new run, not just a load.
			if (t as Node).has_meta("built"):
				continue
""", 'if (t as Node).has_meta("built"):\n\t\t\t\tcontinue',
where="replace", name="World: skip editor trees in saves")

w = patch(w, """			_loading = true
			set_blackout(true, "Remembering the world...")
			if _player:
				_player.input_locked = true
""", """	## A load just swept every tree and prop in the world, the god editor's
	## included. Put the built world back (GodEditor.restore_all).
	get_tree().call_group("builder", "restore_all")
""", 'call_group("builder", "restore_all")', name="World: restore built after load")

w = patch(w, """func _drowned_tick(delta: float, uw: float) -> void:
""", """	if _player != null and _player.god:
		return   ## god / spectator: the lake has no claim on a body it cannot see
""", "the lake has no claim", name="World: drowned respects god")

(OUT / "World.gd").write_text(w)

# =========================================================================
#  Enemy.gd  --  the ONE choke point for every hunter in the game
# =========================================================================
e = (SRC / "Enemy.gd").read_text()

e = patch(e, """func _get_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
""", """func _get_player() -> Node3D:
	## SPECTATOR MODE (scripts/EditorMode.gd): while the map editor's camera is
	## out, the body is parked and the world is not allowed to see it. This one
	## return covers all nine mobs AND all 73 wildlife species, because Critter
	## extends Enemy and every hunt, flee, charge and grudge reads through here.
	if EditorMode.active:
		return null
	var players := get_tree().get_nodes_in_group("player")
""", "if EditorMode.active:", where="replace", name="Enemy: blind while editing")

(OUT / "Enemy.gd").write_text(e)

# =========================================================================
#  CritterSwarm.gd  --  the blackflies find you by group, not by _get_player
# =========================================================================
c = (SRC / "CritterSwarm.gd").read_text()

c = patch(c, """	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl != null:
""", """	var pl := get_tree().get_first_node_in_group("player") as Node3D
	## Swarms find you by group rather than through Enemy._get_player, so the
	## spectator gate has to be repeated here. Blackflies do not get to orbit a
	## parked body while you are two kilometres away laying out a town.
	if EditorMode.active:
		pl = null
	if pl != null:
""", "if EditorMode.active:\n\t\tpl = null", where="replace",
name="CritterSwarm: blind while editing")

(OUT / "CritterSwarm.gd").write_text(c)

print("\n".join(changes))
print("\nOK")
