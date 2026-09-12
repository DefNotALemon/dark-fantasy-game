class_name GrassLab
extends PanelContainer
## ===========================================================================
## THE GRASS LAB -- F3. Every knob the meadow has, live, in a panel.
##
## Lemon (2026-09-11): "we gotta fix the grass, show me a bunch of different
## styles, and colors, and shapes, and patterns with density, size, and other
## sliders in the dev menu for me to edit." The browser bench (the Cowork
## artifact "Myrkfell Grass Lab") was the first half; this is the in-game
## half, driving the REAL GrassSystem through GrassSystem.apply_style().
##
## What it does:
##   * a PRESET row -- design/grass_styles/*.json (the bench's thirteen styles
##     plus whatever you save), applied whole;
##   * one slider per knob, grouped by what a change COSTS: shader knobs and
##     colours land the same frame, geometry rebuilds the tuft meshes (ms),
##     placement re-places the whole ring -- so placement changes are
##     DEBOUNCED and applied RESEED_DELAY after the last drag;
##   * SHIP writes design/grass_style.json, which GrassSystem.setup() reads
##     before the first blade is built -- the chosen style is the game's style,
##     not a dev overlay; SAVE PRESET adds a named file to the preset row.
##
## Player owns the key: F3 -> Player._toggle_menu("grass") shows and hides
## this panel like every other menu (map, spawn, creative), so the cursor,
## Esc and the god panel's arbitration all behave. THIS FILE TAKES NO KEY and
## registers no action -- GrassLabTests scans the source for that.
## ===========================================================================

const RESEED_DELAY := 0.7      ## s after the last placement drag before the ring re-places
const PANEL_W := 470.0

## [key, label, min, max, step, group]  group: "place" | "geom" | "shader"
const KNOBS := [
	["density", "Density", 0.0, 3.0, 0.05, "place"],
	["tall_keep", "Tall patch fill", 0.0, 1.0, 0.01, "place"],
	["short_keep", "Short grass fill", 0.0, 1.0, 0.01, "place"],
	["clump_cut", "Clump gaps", -1.0, 0.2, 0.01, "place"],
	["tall_shift", "Tall patches (- more)", -0.5, 1.0, 0.01, "place"],
	["size_var", "Size variation", 0.0, 2.5, 0.05, "place"],
	["vigour", "Vigour", 0.3, 2.5, 0.05, "place"],
	["tint_dry", "Dry tint", 0.0, 1.0, 0.01, "place"],
	["tint_moist", "Damp tint", 0.0, 1.0, 0.01, "place"],
	["w_fescue", "Fescue", 0.0, 1.0, 0.05, "place"],
	["w_sedge", "Sedge", 0.0, 3.0, 0.1, "place"],
	["w_timothy", "Timothy", 0.0, 4.0, 0.1, "place"],
	["w_bluestem", "Bluestem", 0.0, 3.0, 0.1, "place"],
	["w_flower", "Flowers", 0.0, 3.0, 0.1, "place"],
	["w_clover", "Clover", 0.0, 3.0, 0.1, "place"],
	["w_fern", "Fern", 0.0, 3.0, 0.1, "place"],
	["w_moss", "Moss", 0.0, 3.0, 0.1, "place"],
	["height", "Blade height (m)", 0.05, 1.2, 0.01, "geom"],
	["width", "Blade width (m)", 0.01, 0.2, 0.002, "geom"],
	["blades", "Blades per tuft", 1, 8, 1, "geom"],
	["segs", "Segments", 1, 6, 1, "geom"],
	["lean", "Lean", 0.0, 1.0, 0.01, "geom"],
	["droop", "Droop", 0.0, 2.0, 0.01, "geom"],
	["tall_height", "Tall height (m)", 0.4, 2.5, 0.02, "geom"],
	["tall_width", "Tall width (m)", 0.02, 0.2, 0.002, "geom"],
	["pixel_on", "Pixel cells (0/1)", 0.0, 1.0, 1.0, "shader"],
	["cells", "Cells along", 4.0, 32.0, 1.0, "shader"],
	["side_cells", "Cells across", 1.0, 6.0, 1.0, "shader"],
	["palette", "Palette steps (16=off)", 2.0, 16.0, 1.0, "shader"],
	["jitter", "Cell jitter", 0.0, 0.5, 0.01, "shader"],
	["posterize_gamma", "Posterize in gamma (0/1)", 0.0, 1.0, 1.0, "shader"],
	["hue_var", "Hue variation", 0.0, 0.5, 0.01, "shader"],
	["val_var", "Value variation", 0.0, 1.0, 0.01, "shader"],
	["root_dark", "Root darkness", 0.0, 1.0, 0.01, "shader"],
	["tip_light", "Tip light", 0.0, 1.0, 0.01, "shader"],
	["bands", "Light bands (1=smooth)", 1.0, 6.0, 1.0, "shader"],
	["backlight", "Backlight", 0.0, 1.0, 0.01, "shader"],
	["normal_up", "Root normal to up", 0.0, 1.0, 0.01, "shader"],
	["snow", "Snow settle", 0.0, 1.0, 0.01, "shader"],
]
const COLOURS := [
	["col_spring", "Spring"], ["col_summer", "Summer"], ["col_autumn", "Autumn"], ["col_winter", "Winter"],
	["col_dry", "Dry / cured"], ["col_moss", "Moss"], ["col_snow", "Snow"], ["col_seedhead", "Timothy head"],
	["col_bluestem_summer", "Bluestem summer"], ["col_bluestem_cured", "Bluestem cured"],
]
const GROUP_TITLES := {"place": "PLACEMENT  (re-places the ring, %.1f s after you stop)",
	"geom": "SHAPE  (rebuilds the tufts)", "shader": "LOOK  (instant)"}

var grass: Node = null            ## the GrassSystem, found on open
var preset_btn: OptionButton
var status: Label
var name_edit: LineEdit
var _sliders: Dictionary = {}     ## key -> HSlider
var _vals: Dictionary = {}        ## key -> Label
var _pickers: Dictionary = {}     ## key -> ColorPickerButton
var _presets: Array = []          ## [{name, path, file}]
var _pending: Dictionary = {}     ## placement changes waiting on the debounce
var _reseed_t := -1.0
var _syncing := false             ## true while the widgets are being set from the style
var _based_on := ""


func _ready() -> void:
	name = "GrassLab"
	visible = false
	_build()
	visibility_changed.connect(_on_visibility)


## ------------------------------------------------------------- the panel --

func _build() -> void:
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	margin.add_child(vb)

	var title := Label.new()
	title.text = "GRASS LAB   [F3]"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.86, 0.78, 0.52))
	vb.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	vb.add_child(row)
	preset_btn = OptionButton.new()
	preset_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_btn.focus_mode = Control.FOCUS_NONE
	preset_btn.item_selected.connect(_on_preset)
	row.add_child(preset_btn)
	row.add_child(_button("Reseed", _reseed_now, "Re-place the ring with the current numbers"))
	row.add_child(_button("Reset", _reset, "Back to the v2.7 numbers"))

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	vb.add_child(row2)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "preset name"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(name_edit)
	row2.add_child(_button("Save preset", _save_preset, "design/grass_styles/<name>.json"))
	row2.add_child(_button("SHIP", _ship, "Write design/grass_style.json -- the game boots with it"))

	status = Label.new()
	status.add_theme_font_size_override("font_size", 13)
	status.add_theme_color_override("font_color", Color(0.72, 0.70, 0.62))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 3)
	scroll.add_child(body)

	for group in ["shader", "geom", "place"]:
		var head := Label.new()
		var t := String(GROUP_TITLES[group])
		head.text = t % RESEED_DELAY if t.contains("%") else t
		head.add_theme_font_size_override("font_size", 13)
		head.add_theme_color_override("font_color", Color(0.86, 0.78, 0.52))
		body.add_child(head)
		if group == "shader":
			for c in COLOURS:
				body.add_child(_colour_row(String(c[0]), String(c[1])))
		for k in KNOBS:
			if String(k[5]) != group:
				continue
			body.add_child(_slider_row(String(k[0]), String(k[1]), float(k[2]), float(k[3]), float(k[4])))


func _button(text: String, fn: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(fn)
	return b


func _slider_row(key: String, label: String, lo: float, hi: float, step: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(178, 0)
	l.add_theme_font_size_override("font_size", 13)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(_on_slider.bind(key))
	row.add_child(s)
	var v := Label.new()
	v.custom_minimum_size = Vector2(52, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_theme_font_size_override("font_size", 12)
	row.add_child(v)
	_sliders[key] = s
	_vals[key] = v
	return row


func _colour_row(key: String, label: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(178, 0)
	l.add_theme_font_size_override("font_size", 13)
	row.add_child(l)
	var p := ColorPickerButton.new()
	p.custom_minimum_size = Vector2(120, 22)
	p.focus_mode = Control.FOCUS_NONE
	p.edit_alpha = false
	p.color_changed.connect(_on_colour.bind(key))
	row.add_child(p)
	_pickers[key] = p
	return row


## ------------------------------------------------------------- open/close -

func _on_visibility() -> void:
	if visible:
		open()


func open() -> void:
	grass = _find_grass()
	_load_presets()
	sync_from_style()
	if grass == null:
		_say("No meadow yet -- the lab needs a world with grass in it.")
	else:
		_say("Drag anything. LOOK is instant, SHAPE rebuilds the tufts, PLACEMENT re-places the ring.")


func _find_grass() -> Node:
	var t := get_tree()
	if t == null:
		return null
	var g := t.get_first_node_in_group("grass_system")
	if g != null and g.has_method("apply_style") and g.get("style") is Dictionary:
		return g
	return null


func _load_presets() -> void:
	_presets = [{"name": "Myrkfell now (v2.7 defaults)", "path": "", "file": ""}]
	if grass != null:
		for p in grass.call("preset_files"):
			_presets.append(p)
	preset_btn.clear()
	for p in _presets:
		preset_btn.add_item(String((p as Dictionary)["name"]))


func sync_from_style() -> void:
	## Widgets follow the style, never the other way round while this runs.
	_syncing = true
	var st: Dictionary = grass.get("style") if grass != null else _defaults()
	for key: String in _sliders:
		var s := _sliders[key] as HSlider
		var v := float(st.get(key, s.min_value))
		s.value = v
		_show_val(key, v)
	for key: String in _pickers:
		(_pickers[key] as ColorPickerButton).color = Color.html(String(st.get(key, "#ffffff")))
	_syncing = false


const INT_KEYS := ["blades", "segs", "cells", "side_cells", "palette", "bands", "pixel_on", "posterize_gamma"]


static func _defaults() -> Dictionary:
	return GrassSystem.STYLE_DEFAULTS.duplicate(true)


func _show_val(key: String, v: float) -> void:
	var l := _vals[key] as Label
	if INT_KEYS.has(key):
		l.text = "%d" % int(roundf(v))
	elif absf(v) < 0.1:
		l.text = "%.3f" % v
	else:
		l.text = "%.2f" % v


## ------------------------------------------------------------- changes ----

func _on_slider(v: float, key: String) -> void:
	_show_val(key, v)
	if _syncing or grass == null:
		return
	var group := _group_of(key)
	if group == "place":
		## the expensive one: coalesce a drag into one reseed
		_pending[key] = v
		_reseed_t = RESEED_DELAY
		_say("placement change queued: %s = %.2f (re-places in %.1f s)" % [key, v, RESEED_DELAY])
		return
	grass.call("apply_style", {key: v}, true)


func _on_colour(c: Color, key: String) -> void:
	if _syncing or grass == null:
		return
	grass.call("apply_style", {key: "#" + c.to_html(false)}, true)


static func _group_of(key: String) -> String:
	for k in KNOBS:
		if String(k[0]) == key:
			return String(k[5])
	return "shader"


func _process(delta: float) -> void:
	if not visible:
		return
	## sit at the left edge, full height, under nothing
	var vp := get_viewport().get_visible_rect().size
	custom_minimum_size = Vector2(PANEL_W, vp.y - 32.0)
	position = Vector2(16.0, 16.0)
	if _reseed_t >= 0.0:
		_reseed_t -= delta
		if _reseed_t < 0.0:
			_flush_pending()


func _flush_pending() -> void:
	_reseed_t = -1.0
	if grass == null or _pending.is_empty():
		_pending.clear()
		return
	var t0 := Time.get_ticks_msec()
	var d := _pending.duplicate()
	_pending.clear()
	grass.call("apply_style", d, true)
	_say("re-placed the ring in %d ms" % (Time.get_ticks_msec() - t0))


func _reseed_now() -> void:
	if grass == null:
		return
	_pending.clear()
	_reseed_t = -1.0
	var t0 := Time.get_ticks_msec()
	grass.call("reseed")
	_say("re-placed the ring in %d ms" % (Time.get_ticks_msec() - t0))


func _reset() -> void:
	if grass == null:
		return
	_apply_whole(_defaults(), "Myrkfell now")
	_based_on = ""


func _on_preset(idx: int) -> void:
	if grass == null or idx < 0 or idx >= _presets.size():
		return
	var p: Dictionary = _presets[idx]
	if String(p["path"]) == "":
		_reset()
		return
	var d: Dictionary = grass.call("load_style_file", String(p["path"]))
	if d.is_empty():
		_say("could not read %s" % String(p["path"]))
		return
	## a preset lists only what it changes: start from the defaults
	var whole := _defaults()
	for k in d.keys():
		whole[k] = d[k]
	_based_on = String(p["file"])
	_apply_whole(whole, String(p["name"]))


func _apply_whole(d: Dictionary, label: String) -> void:
	_pending.clear()
	_reseed_t = -1.0
	var t0 := Time.get_ticks_msec()
	var ch: Dictionary = grass.call("apply_style", d, true)
	sync_from_style()
	_say("%s applied in %d ms (shader %s, meshes %s, placement %s)" % [label, Time.get_ticks_msec() - t0,
		str(ch.get("shader", false)), str(ch.get("meshes", false)), str(ch.get("placement", false))])


func _save_preset() -> void:
	if grass == null:
		return
	var nm := name_edit.text.strip_edges()
	if nm == "":
		_say("give the preset a name first")
		return
	var file := nm.to_lower().replace(" ", "_").validate_filename()
	var path := String(grass.get("STYLE_DIR")) + "/" + file + ".json"
	if bool(grass.call("save_style_file", path, nm, _based_on)):
		_say("saved %s" % path)
		_load_presets()
		for i in range(_presets.size()):
			if String((_presets[i] as Dictionary)["path"]) == path:
				preset_btn.select(i)
	else:
		_say("could not write %s" % path)


func _ship() -> void:
	if grass == null:
		return
	var path := String(grass.get("STYLE_FILE"))
	if bool(grass.call("save_style_file", path, "shipped", _based_on)):
		_say("SHIPPED: %s -- the game boots with this style now" % path)
	else:
		_say("could not write %s" % path)


func _say(t: String) -> void:
	if status != null:
		status.text = t


func report() -> Dictionary:
	return {"grass": grass != null, "presets": _presets.size(), "sliders": _sliders.size(),
		"pickers": _pickers.size(), "pending": _pending.size(), "status": status.text if status else ""}
