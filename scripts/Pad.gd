extends Node
## =============================================================================
## PAD -- the controller. PlayStation layout (Xbox names in brackets).
##
##   Left stick        move          L3 push in   sprint toggle
##   Right stick       look          R3 push in   camera (V): FP / TP / shoulder
##   R2 [RT]           left click -- swing, chop, mine, draw the bow
##   L2 [LT]           right click -- guard, and eases a drawn bow back down
##   L1 [LB]           item wheel (hold, aim with the right stick, release)
##   R1 [RB]           dash
##   X  [A]            jump   (swim up, god-fly up)
##   O  [B]            crouch (swim down)
##   Square [X]        interact -- take, hoist, drink, fill, free yourself
##   Triangle [Y]      inventory
##   D-pad up          drink a health potion
##   D-pad down        prone
##   D-pad left        sheathe / draw
##   D-pad right       god editor + build menu (F1)
##   Options [Menu]    escape / pause
##   Touchpad [View]   map
##
## HOW IT WORKS: this node does NOT reimplement anything. It turns pad input
## into the very same key and mouse events the game already listens for and
## feeds them back through Input.parse_input_event, so every guard, cooldown
## and menu rule in Player.gd applies to the pad for free and there is only
## ever ONE definition of what a button does. The two exceptions are the
## analog ones -- the sticks -- which have no keyboard equivalent to borrow:
## the left stick is added to move_input by Player._pad_move(), and the right
## stick drives the look, the item wheel, and the menu cursor from here.
## =============================================================================

const DEAD_MOVE := 0.18          ## radial dead zone, left stick
const DEAD_LOOK := 0.14          ## radial dead zone, right stick
const LOOK_SPEED := 3.1          ## rad/s at full deflection (x the sensitivity setting)
const LOOK_CURVE := 2.0          ## >1 = fine aim near the centre, fast at the rim
const TRIG_ON := 0.50            ## trigger pull that counts as a click...
const TRIG_OFF := 0.35           ## ...and the lower edge it has to fall back through
const CURSOR_SPEED := 950.0      ## px/s for the right-stick cursor in menus
const WHEEL_REACH := 60.0        ## stick deflection -> pixels, for the item wheel

const ALL_BUTTONS := [
	JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y,
	JOY_BUTTON_BACK, JOY_BUTTON_START,
	JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK,
	JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER,
	JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN,
	JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT,
	JOY_BUTTON_TOUCHPAD,
]

var player: Node = null
var device := -1                 ## -1 = no pad plugged in

var _btn := {}                   ## JoyButton -> was it down last frame
var _held := {}                  ## keycode -> are WE holding it down
var _mouse := {}                 ## mouse button -> are WE holding it down
var _trig_l := false
var _trig_r := false
var _sprint := false             ## L3 latch


func _ready() -> void:
	_refresh_device()
	Input.joy_connection_changed.connect(_on_joy_changed)


func _on_joy_changed(_dev: int, _connected: bool) -> void:
	var had := device
	_refresh_device()
	if device >= 0 and had < 0:
		_say("Gamepad connected — %s" % Input.get_joy_name(device), Color(0.62, 0.92, 1.0))
	elif device < 0 and had >= 0:
		_release_all()
		_say("Gamepad disconnected", Color(0.9, 0.75, 0.4))


func _refresh_device() -> void:
	var pads := Input.get_connected_joypads()
	device = int(pads[0]) if pads.size() > 0 else -1


func connected() -> bool:
	return device >= 0


## --- what Player asks us for --------------------------------------------- ##

func move_vec() -> Vector3:
	## The left stick in the same shape Player writes WASD into: -z forward,
	## +x right, length 0..1 so a nudge can be a saunter.
	if device < 0 or player == null:
		return Vector3.ZERO
	if player.godmode != null and player.godmode.typing:
		return Vector3.ZERO
	var v := _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, DEAD_MOVE)
	return Vector3(v.x, 0.0, v.y)


## --- the frame ------------------------------------------------------------ ##

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if device < 0:
		return
	if player.input_locked:
		_release_all()
		_sync_buttons()
		return
	if player.godmode != null and player.godmode.typing:
		## The editor's text fields own the keyboard; don't post keys into them.
		_release_all()
		_sync_buttons()
		return
	_buttons()
	_triggers()
	_sticks(delta)


func _buttons() -> void:
	## Held, because something polls them: jump/up, crouch/down, dash/descend,
	## the wheel's hold-and-release, and the camera's hold-to-return-to-first.
	_mirror(JOY_BUTTON_A, KEY_SPACE)                ## X -- jump, swim up, fly up
	_mirror(JOY_BUTTON_B, KEY_C)                    ## O -- crouch, swim down
	_mirror(JOY_BUTTON_LEFT_SHOULDER, KEY_Q)        ## L1 -- item wheel
	_mirror(JOY_BUTTON_RIGHT_SHOULDER, KEY_CTRL)    ## R1 -- dash, fly down
	_mirror(JOY_BUTTON_RIGHT_STICK, KEY_V)          ## R3 -- camera

	## Tapped, because one press is the whole story.
	_tap(JOY_BUTTON_Y, KEY_I)                       ## Triangle -- inventory
	_tap(JOY_BUTTON_START, KEY_ESCAPE)              ## Options -- pause / back
	_tap(JOY_BUTTON_BACK, KEY_M)                    ## View -- map (Xbox)
	_tap(JOY_BUTTON_TOUCHPAD, KEY_M)                ## touchpad click -- map (PS)
	_tap(JOY_BUTTON_DPAD_DOWN, KEY_X)               ## prone
	_tap(JOY_BUTTON_DPAD_LEFT, KEY_ALT)             ## sheathe / draw
	_tap(JOY_BUTTON_DPAD_RIGHT, KEY_F1)             ## god editor + build menu

	if _edge(JOY_BUTTON_X) == 1:
		_interact()                                 ## Square
	if _edge(JOY_BUTTON_DPAD_UP) == 1:
		_potion()
	if _edge(JOY_BUTTON_LEFT_STICK) == 1:
		## L3 LATCHES the sprint instead of asking you to hold a stick down
		## with your thumb. Letting the stick go drops it again (see _sticks).
		_sprint = not _sprint


func _triggers() -> void:
	## The triggers ARE the mouse buttons, with a little hysteresis so a thumb
	## resting on the edge of the pull doesn't machine-gun the swing.
	var r := Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT)
	if r >= TRIG_ON and not _trig_r:
		_trig_r = true
		_hold_mouse(MOUSE_BUTTON_LEFT, true)
	elif r <= TRIG_OFF and _trig_r:
		_trig_r = false
		_hold_mouse(MOUSE_BUTTON_LEFT, false)
	var l := Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT)
	if l >= TRIG_ON and not _trig_l:
		_trig_l = true
		_hold_mouse(MOUSE_BUTTON_RIGHT, true)
	elif l <= TRIG_OFF and _trig_l:
		_trig_l = false
		_hold_mouse(MOUSE_BUTTON_RIGHT, false)


func _sticks(delta: float) -> void:
	## Sprint drops the moment you stop pushing -- a latch you can't turn off
	## is a latch you fight.
	if _sprint and _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, DEAD_MOVE) == Vector2.ZERO:
		_sprint = false
	_hold_key(KEY_SHIFT, _sprint)

	var lk := _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, DEAD_LOOK, LOOK_CURVE)

	## THE ITEM WHEEL owns the right stick while it is up. The mouse version
	## accumulates a drag; a stick already points somewhere, so we hand the
	## wheel an absolute direction and the same dead radius it uses.
	if player.wheel_open or player.wheel_place_open:
		player._wheel_vec = lk * WHEEL_REACH
		player._wheel_highlight_from(player._wheel_vec, 26.0)
		return

	## A MENU is up and the cursor is loose: the right stick drives it and R2
	## is the click, so the pad can reach the inventory, the map and settings.
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		if lk != Vector2.ZERO:
			var vp := get_viewport()
			var p := vp.get_mouse_position() + lk * CURSOR_SPEED * delta
			var sz := vp.get_visible_rect().size
			Input.warp_mouse(Vector2(clampf(p.x, 0.0, sz.x - 1.0), clampf(p.y, 0.0, sz.y - 1.0)))
		return

	if lk == Vector2.ZERO:
		return
	var sens := LOOK_SPEED * float(player.set_sens) * delta
	player.rotate_y(-lk.x * sens)
	player.pitch = clampf(player.pitch - lk.y * sens, -1.4, 1.4)
	player.head.rotation.x = player.pitch
	player._update_head_offset()


## --- the two buttons that don't map to one key ----------------------------- ##

func _interact() -> void:
	## Square is THE use button. On the keyboard that job is split -- E takes
	## what is on the ground, F works the world and is the way out from under
	## a trunk -- so pick whichever one this moment actually wants.
	var take: bool = player._drop_target != null or player._bed_target != null \
		or player._debris_target != null or player._log_target != null \
		or player._water_target != Vector3.INF
	var code := KEY_E if (take and player.pinned_by == null) else KEY_F
	_key(code, true)
	_key(code, false)


func _potion() -> void:
	var idx: int = player._find_item_index("Health Potion")
	if idx < 0:
		_say("No draught in the pack", Color(0.9, 0.75, 0.4))
		return
	player._drink_potion(idx)


## --- posting events -------------------------------------------------------- ##

func _key(code: int, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	e.echo = false
	Input.parse_input_event(e)


func _hold_key(code: int, down: bool) -> void:
	if bool(_held.get(code, false)) == down:
		return
	_held[code] = down
	_key(code, down)


func _hold_mouse(btn: int, down: bool) -> void:
	if bool(_mouse.get(btn, false)) == down:
		return
	_mouse[btn] = down
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = down
	var mp := get_viewport().get_mouse_position()
	e.position = mp
	e.global_position = mp
	Input.parse_input_event(e)


func _mirror(btn: int, code: int) -> void:
	var d := _edge(btn)
	if d == 1:
		_hold_key(code, true)
	elif d == -1:
		_hold_key(code, false)


func _tap(btn: int, code: int) -> void:
	if _edge(btn) == 1:
		_key(code, true)
		_key(code, false)


func _release_all() -> void:
	for code in _held.keys():
		if bool(_held[code]):
			_held[code] = false
			_key(int(code), false)
	for btn in _mouse.keys():
		if bool(_mouse[btn]):
			_mouse[btn] = false
			var e := InputEventMouseButton.new()
			e.button_index = int(btn)
			e.pressed = false
			Input.parse_input_event(e)
	_trig_l = false
	_trig_r = false
	_sprint = false


## --- plumbing -------------------------------------------------------------- ##

func _edge(btn: int) -> int:
	## 1 the frame it goes down, -1 the frame it comes up, 0 otherwise.
	var now := device >= 0 and Input.is_joy_button_pressed(device, btn)
	var was := bool(_btn.get(btn, false))
	_btn[btn] = now
	if now == was:
		return 0
	return 1 if now else -1


func _sync_buttons() -> void:
	## Swallow a frame of edges (used while input is locked) so nothing fires
	## the instant control comes back.
	for b in ALL_BUTTONS:
		_edge(int(b))


func _stick(ax: int, ay: int, dead: float, curve: float = 1.0) -> Vector2:
	var v := Vector2(Input.get_joy_axis(device, ax), Input.get_joy_axis(device, ay))
	var m := v.length()
	if m <= dead:
		return Vector2.ZERO
	var n := clampf((m - dead) / (1.0 - dead), 0.0, 1.0)
	if not is_equal_approx(curve, 1.0):
		n = pow(n, curve)
	return v.normalized() * n


func _say(msg: String, col: Color) -> void:
	if player != null and player.has_method("_add_log_msg"):
		player._add_log_msg(msg, col)
