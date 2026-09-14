extends CanvasLayer
## =============================================================================
## THE CURSOR -- one pointer for every menu, drawn by the game.
##
## Lemon, 2026-09-14: "make the mouse a cursor in all menus that's always
## active, that way when a controller is being used you don't have to select
## each item in your inventory."
##
## Whenever the mouse is loose (Input.mouse_mode is VISIBLE: the inventory and
## the rest of the Tab menu, the map, settings, spawn, creative, the sky menu,
## the grass lab, the Claude chat, a talk, the god editor in CURSOR mode, and
## the front-door card) this layer draws a pointer and moves it. The mouse
## moves it, and so does the pad's right stick, with R2 as the click
## (Pad._triggers -- unchanged, it just clicks at `pos` now). Nothing opts in:
## a menu that lets the mouse go has the cursor, and a menu that does not
## exist yet will have it too.
##
## HOW.  The OS pointer is made invisible -- a transparent cursor image on
## every shape, so a text box's I-beam cannot leak through beside ours -- and
## the sprite in this layer is the pointer you see. It sits where Godot says
## the mouse is (Viewport.get_mouse_position), so a real mouse drives it
## exactly as before. The stick moves it directly, and every stick move is
## (a) warped into the OS pointer, so a real click still lands where the
## sprite is, and (b) posted as the very same InputEventMouseMotion the mouse
## would have produced (Input.parse_input_event), so buttons hover,
## mouse_entered / mouse_exited fire (the inventory's hovered-item readout),
## MainMenu's row highlight and parallax follow, the god editor aims at the
## sprite, and Input.get_mouse_position() agrees with what you see.
##
## WHY NOT Input.warp_mouse ALONE (the 2026-09-04 pad cursor).  A warp moves
## the OS pointer, but on macOS no motion event comes back for it, so Godot's
## idea of where the mouse was never moved: every frame the stick added one
## step to the SAME stale position, the pointer twitched in place, nothing
## hovered and R2 clicked where the mouse had been. Now the OS pointer is not
## the cursor at all -- it is only kept in step with the sprite.
##
## THIS FILE TAKES NO KEY and declares no input callback (DevInputTests: only
## MainMenu and Player may). The mouse is read by polling the viewport once a
## frame; the stick comes from Pad.look_stick(). Preloaded BY PATH from Pad.gd,
## never by class_name (a new class_name is invisible to headless runs until
## the editor rebuilds its cache).
## =============================================================================

const LAYER := 120               ## over the card (90), the lifted HUD (85), the curtain (80)
const SPEED := 1150.0            ## px/s at full deflection of the right stick
const BONE := Color(0.878, 0.843, 0.749)   ## the front door's lettering
const INK := Color(0.024, 0.027, 0.039, 1.0)

## The classic arrow, 11 x 18: `#` is the ink outline, `o` the bone fill.
## The hotspot is the tip, (0, 0).
const ARROW := [
	"#..........",
	"##.........",
	"#o#........",
	"#oo#.......",
	"#ooo#......",
	"#oooo#.....",
	"#ooooo#....",
	"#oooooo#...",
	"#ooooooo#..",
	"#oooooooo#.",
	"#ooooo#####",
	"#oo#oo#....",
	"#o#.#oo#...",
	"##...#oo#..",
	"#....#oo#..",
	"......#oo#.",
	"......#oo#.",
	".......##..",
]

var pad: Node = null             ## scripts/Pad.gd -- the right stick comes from it
var pos := Vector2.ZERO          ## where the pointer is, in viewport pixels
var active := false              ## the mouse is loose and the sprite is up
var outside := false             ## the OS pointer has left the window (sprite hidden)
var moved := 0                   ## stick moves posted so far (the tests read it)
var mode_override := -1          ## tests: -1 reads Input.mouse_mode, else pretend it is this
var stick_override := Vector2.INF   ## tests: a right stick to pretend; INF = ask the pad

var _sprite: Sprite2D = null
var _scale := 0
var _art: Dictionary = {}        ## scale -> ImageTexture
var _headless := false


func _ready() -> void:
	layer = LAYER
	_headless = DisplayServer.get_name() == "headless"
	_sprite = Sprite2D.new()
	_sprite.name = "Pointer"
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.visible = false
	add_child(_sprite)
	_rescale()
	get_viewport().size_changed.connect(_rescale)
	_hide_os_pointer(true)


func _exit_tree() -> void:
	_hide_os_pointer(false)


## --- the frame ------------------------------------------------------------ ##

func _process(delta: float) -> void:
	var want := loose()
	if want != active:
		_set_active(want)
	if not active:
		return
	var vp := get_viewport()
	var sz := vp.get_visible_rect().size
	## 1. THE MOUSE. The viewport's position is the truth -- on a desktop it
	##    IS the OS pointer (4.7 reads it back from the OS every time), so a
	##    real mouse move, or our own warp, both show up here. Follow it.
	var m := vp.get_mouse_position()
	if m != pos:
		pos = _clamp(m, sz)
	## Out of the window (a windowed game, the game embedded in the editor):
	## the OS arrow is back over the desktop, so ours steps aside rather than
	## sitting on the edge pretending. A stick push warps it straight back.
	outside = m.x < 0.0 or m.y < 0.0 or m.x >= sz.x or m.y >= sz.y
	## 2. THE STICK moves it, and tells the world.
	var lk := _stick()
	if lk != Vector2.ZERO:
		var np := _clamp(pos + lk * SPEED * delta, sz)
		if np != pos or outside:
			_move_to(np, delta)
			outside = false
	_sprite.visible = not outside
	_sprite.position = pos.floor()


func loose() -> bool:
	## "A menu has the mouse loose" -- the one test for whether the cursor is
	## up. Every menu in the game says so the same way: Input.MOUSE_MODE_VISIBLE.
	var mode := mode_override if mode_override >= 0 else int(Input.mouse_mode)
	return mode == Input.MOUSE_MODE_VISIBLE


func _set_active(on: bool) -> void:
	active = on
	_sprite.visible = on
	if on:
		var vp := get_viewport()
		pos = _clamp(vp.get_mouse_position(), vp.get_visible_rect().size)
		_sprite.position = pos.floor()


func _move_to(np: Vector2, delta: float) -> void:
	var rel := np - pos
	pos = np
	## (a) the OS pointer comes along, so a real click lands where the sprite is
	if not _headless:
		Input.warp_mouse(pos)
	## (b) and the GUI hears a mouse move -- hover, enter/exit, drags, the aim
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	e.velocity = rel / maxf(delta, 0.0001)
	e.button_mask = Input.get_mouse_button_mask()
	Input.parse_input_event(e)
	moved += 1


func _stick() -> Vector2:
	if stick_override != Vector2.INF:
		return stick_override
	if pad == null or not pad.has_method("look_stick"):
		return Vector2.ZERO
	return pad.look_stick()


static func _clamp(p: Vector2, sz: Vector2) -> Vector2:
	return Vector2(clampf(p.x, 0.0, maxf(0.0, sz.x - 1.0)), clampf(p.y, 0.0, maxf(0.0, sz.y - 1.0)))


## --- the look ------------------------------------------------------------- ##

func _rescale() -> void:
	## Bigger with the window, gently -- the menus themselves do not scale, so
	## the arrow must not outgrow an inventory cell on a big screen. Never
	## below 2: a 1x arrow is a speck. 720p -> 2, 1440p -> 3, a 4K-class
	## window -> 4 (22 / 33 / 44 px wide).
	var vs := get_viewport().get_visible_rect().size
	var s := clampi(int(round(vs.y / 540.0)), 2, 4)
	if s == _scale:
		return
	_scale = s
	_sprite.texture = arrow(s)


func arrow(sc: int) -> ImageTexture:
	if _art.has(sc):
		return _art[sc]
	var tex := ImageTexture.create_from_image(arrow_image(sc))
	_art[sc] = tex
	return tex


static func arrow_image(sc: int) -> Image:
	sc = maxi(1, sc)
	var w: int = (ARROW[0] as String).length()
	var h: int = ARROW.size()
	var img := Image.create(w * sc, h * sc, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(h):
		var line: String = ARROW[y]
		for x in range(w):
			var ch := line[x]
			if ch == ".":
				continue
			img.fill_rect(Rect2i(x * sc, y * sc, sc, sc), INK if ch == "#" else BONE)
	return img


func _hide_os_pointer(on: bool) -> void:
	## Every shape, not just the arrow: a LineEdit asks for the I-beam, a link
	## for the hand, and any shape left alone would show the OS pointer beside
	## ours the moment the cursor crossed it. Headless has no pointer to hide.
	if _headless:
		return
	var blank: ImageTexture = null
	if on:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		blank = ImageTexture.create_from_image(img)
	for shape in range(Input.CURSOR_ARROW, Input.CURSOR_HELP + 1):
		Input.set_custom_mouse_cursor(blank, shape, Vector2.ZERO)
