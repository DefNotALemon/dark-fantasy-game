extends SceneTree
## ===========================================================================
## THE MENU CURSOR -- the regression net for scripts/MenuCursor.gd and the
## pad's side of it in scripts/Pad.gd.
##
##   godot --headless --path . --script res://tests/MenuCursorTests.gd
##
## Lemon, 2026-09-14: "make the mouse a cursor in all menus that's always
## active, that way when a controller is being used you don't have to select
## each item in your inventory."
##
## Two halves. SOURCE holds the two files to the rules that keep the input
## story singular (DevInputTests owns the keys; this owns the pointer): the
## cursor takes no key and no input callback, is preloaded by path, sits above
## every other layer, and the pad no longer warps the OS pointer itself.
## BEHAVIOUR runs the real cursor in a real tree, headless, with a fake pad and
## a Button under it: a stick push posts a genuine mouse move, the Button
## hovers (mouse_entered) and un-hovers, a click at the arrow presses it, the
## viewport's mouse position agrees with the arrow, the arrow clamps to the
## window, it follows the mouse when the mouse moves, and it sleeps the moment
## the mouse is captured. The real Pad.gd is then stood up around the cursor
## and its R2 path (_hold_mouse) is shown to click where the arrow is.
##
## Headless facts this leans on (probed on 4.7.2): Input.mouse_mode always
## reads VISIBLE, so the cursor's `mode_override` is what flips it; the root
## window is 64 x 64 until told otherwise; Input.parse_input_event delivers
## mouse motion and buttons to the GUI exactly as the OS would.
## ===========================================================================

const CURSOR := preload("res://scripts/MenuCursor.gd")
const PAD := preload("res://scripts/Pad.gd")
const REG := preload("res://tests/DevInputRegistry.gd")

const MIN_ASSERTIONS := 60

var _pass := 0
var _fail := 0
var _fails: Array = []

## the fixture
var _btn: Button = null
var _entered := 0
var _exited := 0
var _pressed := 0


class FakePad extends Node:
	var vec := Vector2.ZERO
	func look_stick() -> Vector2:
		return vec


func ok(c: bool, what: String) -> void:
	if c:
		_pass += 1
	else:
		_fail += 1
		_fails.append(what)
		print("  FAIL: ", what)


func eq(a, b, what: String) -> void:
	ok(a == b, "%s (got %s, want %s)" % [what, str(a), str(b)])


func section(n: String) -> void:
	print("--- ", n)


func read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	print("=== Myrkfell Menu Cursor tests ===")
	_t_source_cursor()
	_t_source_pad()
	_t_art()
	await _t_behaviour()
	await _t_pad()
	print("=== %d passed, %d failed ===" % [_pass, _fail])
	if _pass + _fail < MIN_ASSERTIONS:
		print("  FAIL: only %d assertions ran (want >= %d)" % [_pass + _fail, MIN_ASSERTIONS])
		_fail += 1
	for f in _fails:
		print("  x ", f)
	quit(1 if _fail > 0 else 0)


# ------------------------------------------------------------------- source

func _t_source_cursor() -> void:
	section("MenuCursor.gd, in source")
	var src := read("res://scripts/MenuCursor.gd")
	ok(src.length() > 3000, "MenuCursor.gd was read (%d bytes)" % src.length())
	ok(src.begins_with("extends CanvasLayer"), "it is a CanvasLayer -- its own layer, over every menu")
	## The standing rule from DevInputTests: only MainMenu and Player declare
	## an input callback. The cursor POLLS the viewport and posts events.
	eq(", ".join(PackedStringArray(REG.input_callbacks(src))), "",
			"it declares no input callback")
	eq(", ".join(PackedStringArray(REG.toks_in(src))), "", "and names no key at all")
	ok(not src.contains("is_key_pressed("), "and polls none")
	var cn := RegEx.new()
	cn.compile("(?m)^class_name\\s")
	ok(cn.search(src) == null, "no class_name -- preloaded by path, like the front door's parts")
	ok(not src.contains("InputMap"), "and no InputMap action")
	## What it must do, said in its own source.
	ok(src.contains("InputEventMouseMotion.new()") and src.contains("Input.parse_input_event("),
			"a stick move is posted as a real mouse motion, so the GUI hovers")
	ok(src.contains("Input.warp_mouse("), "and warped into the OS pointer, so a real click lands there too")
	ok(src.contains("Input.set_custom_mouse_cursor(") and src.contains("Input.CURSOR_HELP + 1"),
			"the OS pointer is blanked on every shape, not just the arrow")
	ok(src.contains("func _exit_tree(") and src.contains("_hide_os_pointer(false)"),
			"and given back when the cursor leaves the tree")
	ok(src.contains("MOUSE_MODE_VISIBLE"), "'a menu has the mouse loose' is the one activation rule")
	var rx := RegEx.new()
	rx.compile("const LAYER := (\\d+)")
	var m := rx.search(src)
	ok(m != null and int(m.get_string(1)) > 90,
			"its layer is above the front-door card's 90 (got %s)" % (m.get_string(1) if m else "none"))
	ok(src.contains("get_viewport().size_changed.connect("), "it rescales with the window")
	ok(src.contains("DisplayServer.get_name() == \"headless\""),
			"and knows a headless run has no pointer to blank or warp")


func _t_source_pad() -> void:
	section("Pad.gd, in source")
	var src := read("res://scripts/Pad.gd")
	ok(src.length() > 4000, "Pad.gd was read (%d bytes)" % src.length())
	ok(src.contains("preload(\"res://scripts/MenuCursor.gd\")"), "the pad preloads the cursor by path")
	ok(src.contains("cursor = CursorScript.new()") and src.contains("cursor.pad = self"),
			"and stands it up under itself with a way back to the stick")
	ok(not src.contains("warp_mouse"), "the pad no longer warps the OS pointer itself -- the cursor owns the pointer")
	ok(src.contains("func look_stick(") , "the right stick is offered as look_stick()")
	var hold := REG.func_body(src, "_hold_mouse")
	ok(hold != "" and hold.contains("cursor.pos"), "a pad click lands at the ARROW when a menu is up")
	var proc := REG.func_body(src, "_process")
	ok(proc.contains("input_locked") and proc.contains("cursor_up()") and proc.contains("_triggers()"),
			"asleep behind the front door, the triggers still click while the arrow is up")
	ok(proc.contains("_release_keys()") and proc.contains("_release_mouse()"),
			"and keys and mouse buttons are let go separately, so a click does not machine-gun")
	var sticks := REG.func_body(src, "_sticks")
	ok(sticks.contains("cursor_up()") and not sticks.contains("MOUSE_MODE_VISIBLE"),
			"_sticks hands the stick to the cursor by the cursor's own say-so")
	ok(sticks.contains("wheel_open"), "and the item wheel still owns the stick first")
	## DevInputTests' contract with the pad is untouched by this pass.
	eq(REG.input_callbacks(src).size(), 0, "the pad still declares no input callback")
	ok(REG.pad_posts(src).size() >= 10, "and still posts its buttons' keys (%d)" % REG.pad_posts(src).size())


# ---------------------------------------------------------------------- art

func _t_art() -> void:
	section("the arrow")
	var img: Image = CURSOR.arrow_image(2)
	eq(img.get_width(), 22, "11 columns at scale 2")
	eq(img.get_height(), 36, "18 rows at scale 2")
	ok(img.get_pixel(0, 0).a > 0.99 and img.get_pixel(0, 0).r < 0.1, "the tip (the hotspot) is ink")
	## RGBA8 quantises, so compare within a step of 1/255, not exactly.
	var body: Color = img.get_pixel(4, 10)
	ok(absf(body.r - CURSOR.BONE.r) < 0.01 and absf(body.g - CURSOR.BONE.g) < 0.01
			and absf(body.b - CURSOR.BONE.b) < 0.01 and body.a > 0.99, "the body is bone (%s)" % str(body))
	eq(img.get_pixel(20, 0).a, 0.0, "the top-right is empty")
	eq(img.get_pixel(1, 1).a, 1.0, "scale 2 paints 2 x 2 blocks")
	var one: Image = CURSOR.arrow_image(1)
	eq(one.get_width(), 11, "scale 1 is the raw art")
	## Every row of the art is the same width, or the arrow would have holes
	## the outline loop cannot see.
	var same_w := true
	for row in CURSOR.ARROW:
		if (row as String).length() != 11:
			same_w = false
	ok(same_w, "every row of the art is 11 wide")
	eq(CURSOR.ARROW.size(), 18, "and there are 18 of them")


# ---------------------------------------------------------------- behaviour

func _fixture() -> void:
	root.size = Vector2i(1280, 720)
	var panel := Control.new()
	panel.name = "Menu"
	panel.size = Vector2(1280, 720)
	root.add_child(panel)
	_btn = Button.new()
	_btn.text = "Iron Sword"
	_btn.position = Vector2(300, 200)
	_btn.size = Vector2(120, 60)
	_btn.focus_mode = Control.FOCUS_NONE
	_btn.mouse_entered.connect(func() -> void: _entered += 1)
	_btn.mouse_exited.connect(func() -> void: _exited += 1)
	_btn.pressed.connect(func() -> void: _pressed += 1)
	panel.add_child(_btn)


func _settle(n: int = 2) -> void:
	for i in range(n):
		await process_frame


func _drive(cursor: CanvasLayer, fake: FakePad, dir: Vector2, until: Callable, cap: int = 900) -> int:
	## Push the stick until `until` says stop (or `cap` frames), then let go.
	## Headless frames are ~7 ms, so a corner-to-corner run is ~200 of them.
	fake.vec = dir
	var frames := 0
	while frames < cap and not until.call():
		await process_frame
		frames += 1
	fake.vec = Vector2.ZERO
	await _settle()
	return frames


func _click_at(p: Vector2) -> void:
	for down in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = down
		mb.position = p
		mb.global_position = p
		Input.parse_input_event(mb)


func _t_behaviour() -> void:
	section("the cursor, live in a headless tree")
	_fixture()
	var fake := FakePad.new()
	root.add_child(fake)
	var cursor: CanvasLayer = CURSOR.new()
	cursor.pad = fake
	cursor.mode_override = Input.MOUSE_MODE_VISIBLE
	root.add_child(cursor)
	await _settle()
	eq(cursor.layer, CURSOR.LAYER, "the layer is set")
	ok(cursor.active, "with the mouse loose the cursor is active")
	var sprite: Sprite2D = cursor.get_node("Pointer")
	ok(sprite != null and sprite.visible, "and the arrow is on screen")
	ok(sprite.texture != null and sprite.texture.get_width() == 22,
			"drawn at scale 2 for a 720-high window (%s)" % (str(sprite.texture.get_width()) if sprite.texture else "no texture"))
	ok(not sprite.centered, "with the tip, not the middle, on the point")
	var start: Vector2 = cursor.pos
	ok(start.x >= 0.0 and start.y >= 0.0, "it starts where the mouse was (%s)" % str(start))

	## THE POINT. A stick push moves the arrow, and the GUI hears it.
	var frames: int = await _drive(cursor, fake, Vector2(1, 0), func() -> bool: return cursor.pos.x >= 360.0)
	ok(cursor.pos.x >= 360.0, "the right stick carried the arrow across (x=%.0f in %d frames)" % [cursor.pos.x, frames])
	ok(cursor.moved > 0, "and posted %d mouse moves doing it" % cursor.moved)
	frames = await _drive(cursor, fake, Vector2(0, 1), func() -> bool: return cursor.pos.y >= 230.0)
	ok(cursor.pos.y >= 230.0, "and down onto the button (y=%.0f)" % cursor.pos.y)
	ok(_btn.get_global_rect().has_point(cursor.pos), "the arrow is over the button")
	ok(_entered >= 1, "the button saw mouse_entered -- it hovers")
	ok(_btn.is_hovered(), "and is hovered right now")
	ok(root.get_mouse_position().is_equal_approx(cursor.pos),
			"the viewport's mouse position IS the arrow (%s vs %s)" % [str(root.get_mouse_position()), str(cursor.pos)])
	eq(sprite.position, cursor.pos.floor(), "the sprite is drawn on the point")

	## A click where the arrow is presses the button (this is the R2 path's
	## event shape; the real Pad is stood up in _t_pad).
	_click_at(cursor.pos)
	await _settle()
	eq(_pressed, 1, "a click at the arrow presses the button")

	## Off the button: mouse_exited.
	frames = await _drive(cursor, fake, Vector2(0, -1), func() -> bool: return cursor.pos.y < 150.0)
	ok(_exited >= 1, "moving the arrow off fires mouse_exited")
	ok(not _btn.is_hovered(), "and the button is no longer hovered")

	## Nothing moves without a stick.
	var before: Vector2 = cursor.pos
	var moved_before: int = cursor.moved
	await _settle(4)
	eq(cursor.pos, before, "a still stick leaves the arrow where it is")
	eq(cursor.moved, moved_before, "and posts nothing")

	## The window's edge is a wall.
	frames = await _drive(cursor, fake, Vector2(-1, -1).normalized(), func() -> bool: return cursor.pos == Vector2.ZERO)
	eq(cursor.pos, Vector2.ZERO, "pushing into the top-left corner stops at (0, 0)")
	frames = await _drive(cursor, fake, Vector2(1, 1).normalized(), func() -> bool: return cursor.pos.x >= 1279.0 and cursor.pos.y >= 719.0)
	eq(cursor.pos, Vector2(1279, 719), "and the bottom-right at the last pixel")

	## The mouse moves it too -- an OS-shaped motion event, and the arrow is there.
	var e := InputEventMouseMotion.new()
	e.position = Vector2(640, 360)
	e.global_position = e.position
	e.relative = Vector2(-639, -359)
	Input.parse_input_event(e)
	await _settle()
	eq(cursor.pos, Vector2(640, 360), "a real mouse move puts the arrow under the mouse")
	eq(sprite.position, Vector2(640, 360), "and the sprite follows")

	## The pointer leaves the window (a windowed game): the arrow steps aside
	## rather than sitting on the edge, and a stick push brings it back.
	e = InputEventMouseMotion.new()
	e.position = Vector2(-20, 100)
	e.global_position = e.position
	e.relative = Vector2(-660, -260)
	Input.parse_input_event(e)
	await _settle()
	ok(cursor.outside, "with the OS pointer off the window the cursor knows it is outside")
	ok(not sprite.visible, "and hides the arrow")
	eq(cursor.pos, Vector2(0, 100), "while keeping its place at the edge it left by")
	moved_before = cursor.moved
	fake.vec = Vector2(1, 0)
	await _settle(3)
	fake.vec = Vector2.ZERO
	await _settle()
	ok(not cursor.outside and sprite.visible, "a stick push brings it back inside")
	ok(cursor.moved > moved_before and cursor.pos.x > 0.0, "with a real move posted (x=%.0f)" % cursor.pos.x)

	## Captured = asleep. No sprite, no moves, no posts.
	cursor.mode_override = Input.MOUSE_MODE_CAPTURED
	await _settle()
	ok(not cursor.active, "capturing the mouse puts the cursor to sleep")
	ok(not sprite.visible, "and hides the arrow")
	before = cursor.pos
	moved_before = cursor.moved
	fake.vec = Vector2(1, 0)
	await _settle(6)
	fake.vec = Vector2.ZERO
	eq(cursor.pos, before, "the stick moves nothing while asleep")
	eq(cursor.moved, moved_before, "and posts nothing -- the stick is the look again")

	## Loose again = awake, where the mouse is.
	cursor.mode_override = Input.MOUSE_MODE_VISIBLE
	await _settle()
	ok(cursor.active and sprite.visible, "letting the mouse go wakes it")
	eq(cursor.pos, root.get_mouse_position(), "at the mouse")

	cursor.queue_free()
	fake.queue_free()
	await _settle()


func _t_pad() -> void:
	section("the real Pad.gd around the cursor")
	var pad: Node = PAD.new()
	root.add_child(pad)
	await _settle()
	ok(pad.cursor != null, "the pad stands the cursor up in _ready")
	ok(pad.cursor.pad == pad, "and the cursor knows its pad")
	ok(pad.cursor.get_parent() == pad, "as its own child")
	eq(pad.look_stick(), Vector2.ZERO, "no pad plugged in: look_stick() is zero")
	ok(pad.cursor_up(), "headless reads the mouse as loose, so the arrow is up")
	## R2's path: _hold_mouse posts the click at the ARROW, wherever the
	## viewport last thought the mouse was.
	var e := InputEventMouseMotion.new()
	e.position = Vector2(350, 230)
	e.global_position = e.position
	e.relative = Vector2(10, 10)
	Input.parse_input_event(e)
	await _settle()
	eq(pad.cursor.pos, Vector2(350, 230), "the arrow is on the button again")
	var was := _pressed
	pad._hold_mouse(MOUSE_BUTTON_LEFT, true)
	pad._hold_mouse(MOUSE_BUTTON_LEFT, false)
	await _settle()
	eq(_pressed, was + 1, "the pad's R2 click presses the button under the arrow")
	## The event carried the arrow's position, not a stale one: move the arrow
	## off by hand (the sprite's own field) and click again -- nothing.
	pad.cursor.pos = Vector2(20, 20)
	pad._hold_mouse(MOUSE_BUTTON_LEFT, true)
	pad._hold_mouse(MOUSE_BUTTON_LEFT, false)
	await _settle()
	eq(_pressed, was + 1, "a click with the arrow elsewhere misses it -- the click goes where the ARROW is")
	pad.queue_free()
	await _settle()
