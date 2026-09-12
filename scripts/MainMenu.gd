extends CanvasLayer

## ===========================================================================
## THE FRONT DOOR — scripts/MainMenu.gd
##
## Lemon, 2026-09-04: "add a main menu with the top left corner of the screen,
## big but not too big, then under it is a list of options top to bottom going
## play, dev mode, settings, perish(quit)" — then "don't dim the buttons, let
## it go to the myrkfell loading screen" — then "make it so that you can select
## any of the options when you first boot up, and the settings menu opens on a
## black screen until you actually enter the game or dev mode... main menu
## should be it's own seperate part that loads fully with the setting menu and
## the animated to move with the mouse. all before the actual game."
##
## So this is a front end, not a pause screen. World._ready builds ONLY what
## the menu needs — the curtain, an atmosphere, the parked body that owns the
## settings panel, and this card. The map, the caves, the forest and the
## wildlife are World.begin_world(), and that does not run until PLAY or DEV
## MODE is picked. Every row is live within a fraction of a second of launch.
##
## Two layers, and that is the whole trick:
##   layer 0   THE STAGE — a black rectangle under everything, over the 3D
##             view. It is what SETTINGS opens on: pick it from here and the
##             card hides, the stage does not, and the panel sits on black
##             with the rest of the HUD hidden behind it.
##   layer 90  THE CARD — backdrop and lettering, above Player's HUD at 1.
##
## Both drift against the mouse. The fort moves a full parallax step, the
## lettering about a third of one, so the art sits behind the words instead
## of on the same pane of glass.
##
## What each row does
##   PLAY      World.front_door_done(false) — builds the world, then hands
##             the body back behind the MYRKFELL curtain.
##   DEV MODE  the same with dev = true, which then runs F1's own path
##             (Player._toggle_menu("god")).
##   SETTINGS  the Esc panel that already exists inside Player, on the black
##             stage. Esc (or closing it) brings the card back.
##   PERISH    quit.
##
## The lettering is scripts/PixelFont.gd and the art is scripts/MenuBackdrop.gd,
## both preloaded BY PATH, never by class_name: this file is on the cold-open
## path and a name-level cycle here is a parse error before anything can run
## (see the MapPanel note in Player._build_hud).
## ===========================================================================

const PF := preload("res://scripts/PixelFont.gd")
const Backdrop := preload("res://scripts/MenuBackdrop.gd")

const BONE := Color(0.878, 0.843, 0.749)
const HOT := Color(1.000, 0.812, 0.463)
const DIM := Color(0.494, 0.494, 0.510)
const FAINT := Color(0.612, 0.596, 0.557)
const INK := Color(0.024, 0.027, 0.039, 1.0)
const VOID := Color(0.0, 0.0, 0.0, 1.0)

const TITLE := "THE WITHERING"
const SUBTITLE := "MYRKFELL"
const OPTIONS := [
    {"id": "play", "label": "PLAY", "suffix": ""},
    {"id": "dev", "label": "DEV MODE", "suffix": "F1"},
    {"id": "settings", "label": "SETTINGS", "suffix": ""},
    {"id": "perish", "label": "PERISH", "suffix": "(QUIT)"},
]

## How far the art drifts, as a share of the short screen edge, and how much
## of that the lettering takes.
const DRIFT := 0.020
const PLATE_DRIFT := 0.30
const DRIFT_EASE := 0.0025   ## per-second settle; smaller = snappier

var player: Node = null
var world: Node = null

var _stage: CanvasLayer      ## layer 0: the black the settings panel sits on
var _root: Control
var _backdrop: TextureRect
var _plate: Control          ## everything made of letters, drifting as one
var _title: TextureRect
var _subtitle: TextureRect
var _rule: ColorRect
var _rule2: ColorRect
var _marker: TextureRect
var _rows: Array = []        ## {id, label, suffix, rect, ty}
var _sel := 0
var _state := "menu"         ## "menu" | "settings" | "leaving"
var _s := 3                  ## glyph scale for the option rows
var _pad_down := {}          ## JoyButton -> held last frame (controller nav)
var _pad_stick := 0          ## -1 / 0 / 1, the left stick as a d-pad
var _drift_px := 24.0
var _par := Vector2.ZERO
var _hud_hidden: Array = []
var _hud_layer_was := -999    ## Player's HUD layer before we lifted it


func _ready() -> void:
    layer = 90

    ## The stage, under Player's HUD (layer 1) and over the 3D view.
    _stage = CanvasLayer.new()
    _stage.layer = 0
    add_child(_stage)
    var void_rect := ColorRect.new()
    void_rect.color = VOID
    void_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
    void_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _stage.add_child(void_rect)

    _root = Control.new()
    _root.set_anchors_preset(Control.PRESET_FULL_RECT)
    _root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_root)

    var black := ColorRect.new()
    black.color = Color(0.016, 0.020, 0.031, 1.0)
    black.set_anchors_preset(Control.PRESET_FULL_RECT)
    black.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(black)

    ## The backdrop is deliberately BIGGER than the screen and positioned by
    ## hand — that overscan is the room the parallax moves in, and it is why
    ## no edge of the painting ever comes into view.
    _backdrop = TextureRect.new()
    _backdrop.texture = Backdrop.build()
    _backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    _backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    _backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(_backdrop)

    _plate = Control.new()
    _plate.set_anchors_preset(Control.PRESET_FULL_RECT)
    _plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(_plate)

    _title = _sprite()
    _subtitle = _sprite()
    _rule = ColorRect.new()
    _rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _plate.add_child(_rule)
    _rule2 = ColorRect.new()
    _rule2.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _plate.add_child(_rule2)
    _marker = _sprite()
    for o in OPTIONS:
        _rows.append({
            "id": o["id"],
            "label": _sprite(),
            "suffix": _sprite(),
            "rect": Rect2(),
            "ty": 0,
        })

    _relayout()
    get_viewport().size_changed.connect(_relayout)
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func setup(w: Node, p: Node) -> void:
    world = w
    player = p
    if player != null:
        player.input_locked = true


func _sprite() -> TextureRect:
    var t := TextureRect.new()
    t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    t.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _plate.add_child(t)
    return t


## ------------------------------------------------------------------ layout

func _relayout() -> void:
    var vs := get_viewport().get_visible_rect().size
    _drift_px = maxf(10.0, minf(vs.x, vs.y) * DRIFT)
    _backdrop.size = vs + Vector2(_drift_px, _drift_px) * 2.0
    _backdrop.position = Vector2(-_drift_px, -_drift_px)

    ## "big but not too big": the option rows come out at about a thirtieth of
    ## the screen height, the title two steps up from that, and every size is a
    ## whole number of source pixels so nothing ever blurs.
    _s = clampi(int(round(vs.y / 360.0)), 2, 6)
    var ts := _s + 2
    var ss := maxi(2, _s - 1)

    var x0 := maxi(26, int(vs.x * 0.052))
    var y := maxi(24, int(vs.y * 0.085))

    _paint(_title, TITLE, BONE.lerp(HOT, 0.25), ts, x0, y)
    y += 11 * ts + 3 * ts

    _rule.color = Color(0.545, 0.475, 0.361, 0.75)
    _rule.position = Vector2(x0, y)
    _rule.size = Vector2(PF.text_width(TITLE) * ts, maxi(1, _s / 2))
    y += int(_rule.size.y) + _s * 2
    _rule2.color = Color(0.545, 0.475, 0.361, 0.30)
    _rule2.position = Vector2(x0, y)
    _rule2.size = Vector2(PF.text_width(TITLE) * ts * 0.55, maxi(1, _s / 2))
    y += int(_rule2.size.y) + _s * 3

    _paint(_subtitle, SUBTITLE, FAINT, ss, x0 + _s, y)
    y += 11 * ss + 9 * _s

    var row_h := int(11 * _s * 1.75)
    var text_x := x0 + 11 * _s
    for i in range(_rows.size()):
        var row: Dictionary = _rows[i]
        var o: Dictionary = OPTIONS[i]
        var lab: TextureRect = row["label"]
        _paint(lab, o["label"], BONE, _s, text_x, y)
        var sfx: TextureRect = row["suffix"]
        if String(o["suffix"]) != "":
            _paint(sfx, String(o["suffix"]), DIM, maxi(2, _s - 1),
                text_x + PF.text_width(String(o["label"])) * _s + 6 * _s,
                y + 11 * _s - 11 * maxi(2, _s - 1) - _s)
            sfx.visible = true
        else:
            sfx.visible = false
        row["ty"] = y
        row["rect"] = Rect2(Vector2(x0, y - _s * 3),
            Vector2(maxf(220.0, PF.text_width(String(o["label"])) * _s + 22 * _s),
                11 * _s + _s * 6))
        _rows[i] = row
        y += row_h

    _marker.position = Vector2(x0, 0)
    _refresh_selection()


func _paint(t: TextureRect, text: String, col: Color, scale: int, x: int, y: int) -> void:
    t.texture = PF.render(text, Color(1, 1, 1), INK, scale)
    t.modulate = col
    ## render() carries a 1 px margin for the outline; back it out so the
    ## glyphs land exactly where the layout asked for.
    t.position = Vector2(x - scale, y - scale)
    t.size = t.texture.get_size()


## ------------------------------------------------------------------- state

func _refresh_selection() -> void:
    for i in range(_rows.size()):
        var row: Dictionary = _rows[i]
        var lab: TextureRect = row["label"]
        var sfx: TextureRect = row["suffix"]
        var r: Rect2 = row["rect"]
        if i == _sel:
            lab.modulate = HOT
            sfx.modulate = FAINT
            lab.position.x = r.position.x + 13 * _s - _s
        else:
            lab.modulate = BONE
            sfx.modulate = DIM
            lab.position.x = r.position.x + 11 * _s - _s
    if _sel >= 0 and _sel < _rows.size():
        var sr: Rect2 = _rows[_sel]["rect"]
        var ty: int = int(_rows[_sel]["ty"])
        _marker.texture = PF.marker(Color(1, 1, 1), INK, _s)
        _marker.modulate = HOT
        _marker.size = _marker.texture.get_size()
        _marker.position = Vector2(sr.position.x - _s, ty - _s)
        _marker.visible = true
    else:
        _marker.visible = false


func _process(dt: float) -> void:
    if _state == "settings":
        ## The Esc panel belongs to Player; when it closes, the card returns.
        if player == null or String(player.menu_open) != "settings":
            _leave_settings()
        return
    if _state == "menu" and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    if _state == "menu":
        _pad_nav()
    _drift(dt)


func _drift(dt: float) -> void:
    ## The coast leans away from the cursor, the words follow it a third of
    ## the way. Eased, so a flick of the mouse does not snap the horizon.
    var vs := get_viewport().get_visible_rect().size
    var mp := get_viewport().get_mouse_position()
    var want := Vector2(
        clampf(mp.x / maxf(1.0, vs.x) * 2.0 - 1.0, -1.0, 1.0),
        clampf(mp.y / maxf(1.0, vs.y) * 2.0 - 1.0, -1.0, 1.0))
    _par = _par.lerp(want, 1.0 - pow(DRIFT_EASE, clampf(dt, 0.0, 0.25)))
    _backdrop.position = Vector2(-_drift_px, -_drift_px) - _par * _drift_px
    _plate.position = -_par * (_drift_px * PLATE_DRIFT)


## ------------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
    if _state == "leaving":
        return
    if _state == "settings":
        if event is InputEventKey and event.pressed and not event.echo \
                and (event as InputEventKey).keycode == KEY_ESCAPE:
            if player != null and player.has_method("_close_menu"):
                player._close_menu()
            _leave_settings()
            get_viewport().set_input_as_handled()
        return

    if event is InputEventMouseMotion:
        var mp := (event as InputEventMouseMotion).position - _plate.position
        for i in range(_rows.size()):
            if (_rows[i]["rect"] as Rect2).has_point(mp):
                if _sel != i:
                    _sel = i
                    _refresh_selection()
                break
        return

    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
            var hit := mb.position - _plate.position
            for i in range(_rows.size()):
                if (_rows[i]["rect"] as Rect2).has_point(hit):
                    _sel = i
                    _refresh_selection()
                    _activate()
                    get_viewport().set_input_as_handled()
                    return
        return

    if event is InputEventKey and event.pressed and not event.echo:
        match (event as InputEventKey).keycode:
            KEY_UP, KEY_W:
                _step(-1)
                get_viewport().set_input_as_handled()
            KEY_DOWN, KEY_S:
                _step(1)
                get_viewport().set_input_as_handled()
            KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
                _activate()
                get_viewport().set_input_as_handled()
            KEY_F1:
                _leave(true)
                get_viewport().set_input_as_handled()


func _pad_nav() -> void:
    ## The pad drives the front door directly. Player.input_locked is true
    ## while this card is up (see setup), so scripts/Pad.gd is asleep and the
    ## two can never both act on one press.
    var pads := Input.get_connected_joypads()
    if pads.is_empty():
        return
    var dev := int(pads[0])
    if _pad_edge(dev, JOY_BUTTON_DPAD_UP):
        _step(-1)
    if _pad_edge(dev, JOY_BUTTON_DPAD_DOWN):
        _step(1)
    if _pad_edge(dev, JOY_BUTTON_A) or _pad_edge(dev, JOY_BUTTON_START):
        _activate()
    ## The left stick counts as the d-pad, one step per push past the notch.
    var y := Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y)
    var now := (1 if y > 0.6 else (-1 if y < -0.6 else 0))
    if now != 0 and now != _pad_stick:
        _step(now)
    _pad_stick = now


func _pad_edge(dev: int, btn: int) -> bool:
    var now := Input.is_joy_button_pressed(dev, btn)
    var was := bool(_pad_down.get(btn, false))
    _pad_down[btn] = now
    return now and not was


func _step(d: int) -> void:
    var n := _rows.size()
    _sel = (_sel + d + n) % n
    _refresh_selection()


func _activate() -> void:
    if _sel < 0 or _sel >= _rows.size():
        return
    match String(OPTIONS[_sel]["id"]):
        "play":
            _leave(false)
        "dev":
            _leave(true)
        "settings":
            _open_settings()
        "perish":
            _perish()


## ---------------------------------------------------------------- settings

func _open_settings() -> void:
    if player == null or not player.has_method("_toggle_menu"):
        return
    _state = "settings"
    _root.visible = false          ## the card goes; the black stage stays
    _lift_hud(true)
    player._toggle_menu("settings")
    _hud_dim(true)
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _leave_settings() -> void:
    _hud_dim(false)
    _lift_hud(false)
    _state = "menu"
    _root.visible = true
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _lift_hud(on: bool) -> void:
    ## THE ONE THAT BIT. Player's HUD lives at layer 1 and World's loading
    ## curtain at layer 80 — so hiding the card to show the settings panel
    ## just showed the curtain, and SETTINGS looked like it did nothing.
    ## Lift the HUD over the curtain while the panel is up, and put it back
    ## exactly where it was after, because in-game it belongs under nothing.
    ## The curtain's own MYRKFELL comes down with it, or the word reads
    ## straight through the middle of the settings panel.
    if world != null:
        for part in ["_black_title", "_black_label"]:
            var n: Object = world.get(part)
            if n != null and n is CanvasItem:
                (n as CanvasItem).visible = not on
    if player == null or player.hud_layer == null:
        return
    if on:
        if _hud_layer_was == -999:
            _hud_layer_was = player.hud_layer.layer
        player.hud_layer.layer = 85
    elif _hud_layer_was != -999:
        player.hud_layer.layer = _hud_layer_was
        _hud_layer_was = -999


func _hud_dim(on: bool) -> void:
    ## There is no game behind the settings panel yet — just the stage — so
    ## the bars, the crosshair and the log have no business floating on it.
    ## Only what THIS hid is put back, so nothing that was already closed
    ## comes on when the card returns.
    if player == null or player.hud_layer == null:
        return
    if on:
        _hud_hidden.clear()
        for c in player.hud_layer.get_children():
            if c == player.settings_panel or not (c is CanvasItem):
                continue
            if (c as CanvasItem).visible:
                _hud_hidden.append(c)
                (c as CanvasItem).visible = false
    else:
        for c in _hud_hidden:
            if is_instance_valid(c):
                (c as CanvasItem).visible = true
        _hud_hidden.clear()


## ------------------------------------------------------------------ leaving

func _leave(dev: bool) -> void:
    ## Fade the card off and hand the whole question to World: it builds the
    ## map (phase two), keeps the black MYRKFELL curtain up while it does,
    ## and gives the body back when the deep is real.
    _state = "leaving"
    _hud_dim(false)
    _lift_hud(false)
    var tw := create_tween()
    tw.tween_property(_root, "modulate:a", 0.0, 0.45)
    tw.tween_callback(func() -> void:
        if world != null and world.has_method("front_door_done"):
            world.front_door_done(dev)
        queue_free())


func _perish() -> void:
    _state = "leaving"
    var tw := create_tween()
    tw.tween_property(_root, "modulate:a", 0.0, 0.35)
    tw.tween_callback(func() -> void: get_tree().quit())
