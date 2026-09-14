class_name SkyMenu
extends PanelContainer

## ===========================================================================
## The sky menu — scripts/SkyMenu.gd          bound to  '  (apostrophe)
##
## Scrub the clock, force the weather, throw lightning, turn the northern
## lights on. Everything the sky and weather systems can do, on one panel, so
## you can see a change in a second instead of waiting twenty real minutes for
## dusk or twenty-five in-game days for autumn.
##
## It owns no state. Every control writes straight into DayNight / Weather /
## SkyRig and every readout is read back from them the same frame, so the
## panel can never drift out of sync with the world.
##
## Built and shown by Player.gd like the other menus (settings, creative).
## ===========================================================================

const SEASONS := ["Spring", "Summer", "Autumn", "Winter"]

var _dn: DayNight
var _wx: Weather
var _sky: SkyRig
var _world: Node

var _clock: Label
var _weather_line: Label
var _sky_line: Label
var _hour_slider: HSlider
var _cover_slider: HSlider
var _hour_dragging := false
var _cover_dirty := false     ## true once you've hand-set coverage this session
var _snap := true             ## weather buttons snap instead of easing over 25 s

var _btn_groups := {}         ## id -> [[value, Button], ...] for the lit state


func _ready() -> void:
	visible = false
	_build()


# ===========================================================================
#  Wiring — found lazily, so load order never matters
# ===========================================================================

func _find() -> bool:
	if _world == null or not is_instance_valid(_world):
		_world = get_tree().get_first_node_in_group("world")
	if _world == null:
		return false
	if _wx == null or not is_instance_valid(_wx):
		if _world.has_method("weather"):
			_wx = _world.weather()
	if _sky == null or not is_instance_valid(_sky):
		_sky = _world.get("_sky")
	if _dn == null or not is_instance_valid(_dn):
		_dn = _world.get("_daynight")
	return _dn != null


# ===========================================================================
#  Layout
# ===========================================================================

func _build() -> void:
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	margin.add_child(vb)

	var title := Label.new()
	title.text = "Sky, Time & Weather  (dev)"
	title.add_theme_font_size_override("font_size", 22)
	vb.add_child(title)

	var hint := Label.new()
	hint.text = "'  closes this again."
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(1, 1, 1, 0.5)
	vb.add_child(hint)
	vb.add_child(HSeparator.new())

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	vb.add_child(cols)

	_build_time_column(cols)
	_build_weather_column(cols)


func _build_time_column(parent: Control) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.custom_minimum_size = Vector2(430, 0)
	parent.add_child(col)

	_head(col, "Time")

	_clock = Label.new()
	_clock.text = "--:--"
	_clock.add_theme_font_size_override("font_size", 30)
	col.add_child(_clock)

	## The scrub bar. Dragging it takes the clock wherever you point.
	_hour_slider = HSlider.new()
	_hour_slider.min_value = 0.0
	_hour_slider.max_value = 24.0
	_hour_slider.step = 0.05
	_hour_slider.custom_minimum_size = Vector2(410, 0)
	_hour_slider.focus_mode = Control.FOCUS_NONE
	_hour_slider.value_changed.connect(_on_hour_slider)
	_hour_slider.drag_started.connect(func() -> void: _hour_dragging = true)
	_hour_slider.drag_ended.connect(func(_c: bool) -> void: _hour_dragging = false)
	col.add_child(_hour_slider)

	## The hours worth jumping to. Solar noon is 13:18, not 12:00 — the sun's
	## arc is pinned to DAWN_HOUR..NIGHTFALL_HOUR, so the top of the arc sits
	## halfway between them.
	_row_of_buttons(col, "Jump to", [
		["Dawn", 6.0], ["Morning", 9.0], ["Noon", 13.3],
		["Golden", 19.5], ["Dusk", 20.3], ["Night", 22.5], ["Midnight", 0.0],
	], _set_hour)

	## Frozen is the useful one: park the sun mid-sunset and go look at it.
	_toggle_row(col, "Speed", "speed", [
		["Frozen", 0.0], ["1x", 1.0], ["10x", 10.0], ["60x", 60.0], ["300x", 300.0],
	], _set_speed)

	col.add_child(HSeparator.new())
	_head(col, "Calendar")

	var dayrow := HBoxContainer.new()
	dayrow.add_theme_constant_override("separation", 4)
	col.add_child(dayrow)
	_label(dayrow, "Day", 60)
	_button(dayrow, "-7", func() -> void: _add_days(-7.0))
	_button(dayrow, "-1", func() -> void: _add_days(-1.0))
	_button(dayrow, "+1", func() -> void: _add_days(1.0))
	_button(dayrow, "+7", func() -> void: _add_days(7.0))
	_button(dayrow, "+1 season", func() -> void: _add_days(Wind.DAYS_PER_SEASON))

	_row_of_buttons(col, "Season", [
		["Spring", 0], ["Summer", 1], ["Autumn", 2], ["Winter", 3],
	], _set_season)

	var note := Label.new()
	note.text = "A season is 24 game days. Jumping one moves the leaves, the snow,\nthe seed drop and the wildlife coats together — it is one global uniform."
	note.add_theme_font_size_override("font_size", 12)
	note.modulate = Color(1, 1, 1, 0.5)
	col.add_child(note)


func _build_weather_column(parent: Control) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.custom_minimum_size = Vector2(430, 0)
	parent.add_child(col)

	_head(col, "Weather")

	_weather_line = Label.new()
	_weather_line.text = "--"
	_weather_line.add_theme_font_size_override("font_size", 19)
	col.add_child(_weather_line)

	_toggle_row(col, "Set", "level", [
		["Clear", 0], ["Overcast", 1], ["Drizzle", 2], ["Rain", 3], ["Storm", 4],
	], _set_level)

	_toggle_row(col, "Change", "snap", [
		["Snap", true], ["Ease 25s", false],
	], func(v: Variant) -> void: _snap = bool(v))

	_toggle_row(col, "Clock", "lock", [
		["Auto", false], ["Hold", true],
	], _set_lock)

	var lockn := Label.new()
	lockn.text = "Hold stops the weather rolling itself onward — the same lock the\nstorm crown over Katahdin will use."
	lockn.add_theme_font_size_override("font_size", 12)
	lockn.modulate = Color(1, 1, 1, 0.5)
	col.add_child(lockn)

	var bolt := HBoxContainer.new()
	bolt.add_theme_constant_override("separation", 4)
	col.add_child(bolt)
	_label(bolt, "Lightning", 84)
	_button(bolt, "Overhead", func() -> void: _strike(0.0))
	_button(bolt, "Near", func() -> void: _strike(0.25))
	_button(bolt, "Over the ridge", func() -> void: _strike(0.6))
	_button(bolt, "Far off", func() -> void: _strike(1.0))

	var boltn := Label.new()
	boltn.text = "The gap before the thunder is the distance. Works at any weather\nlevel from here; the storm itself only throws them at Storm."
	boltn.add_theme_font_size_override("font_size", 12)
	boltn.modulate = Color(1, 1, 1, 0.5)
	col.add_child(boltn)

	col.add_child(HSeparator.new())
	_head(col, "Sky")

	_sky_line = Label.new()
	_sky_line.text = "--"
	_sky_line.add_theme_font_size_override("font_size", 15)
	_sky_line.modulate = Color(1, 1, 1, 0.72)
	col.add_child(_sky_line)

	_toggle_row(col, "Clouds", "clouds", [
		["Off", 0], ["Painterly", 1], ["Volumetric", 2],
	], _set_clouds)

	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 4)
	col.add_child(crow)
	_label(crow, "Coverage", 84)
	_cover_slider = HSlider.new()
	_cover_slider.min_value = 0.0
	_cover_slider.max_value = 1.0
	_cover_slider.step = 0.01
	_cover_slider.custom_minimum_size = Vector2(250, 0)
	_cover_slider.focus_mode = Control.FOCUS_NONE
	_cover_slider.value_changed.connect(_on_coverage)
	crow.add_child(_cover_slider)

	_toggle_row(col, "Aurora", "aurora", [
		["Normal", -1.0], ["Off", 0.0], ["Faint", 0.35], ["Full", 0.9],
	], _set_aurora)

	var an := Label.new()
	an.text = "Normal hands it back to the nightly roll (AURORA_CHANCE in Weather.gd).\nThe forced settings ignore the hour and the cloud deck both."
	an.add_theme_font_size_override("font_size", 12)
	an.modulate = Color(1, 1, 1, 0.5)
	col.add_child(an)


# ---------------------------------------------------------- little parts ---

func _head(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 17)
	l.modulate = Color(1, 0.92, 0.75)
	parent.add_child(l)


func _label(parent: Control, text: String, w: float) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(w, 0)
	l.add_theme_font_size_override("font_size", 15)
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _row_of_buttons(parent: Control, name_text: String, opts: Array, cb: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	_label(row, name_text, 84)
	for o: Array in opts:
		_button(row, String(o[0]), cb.bind(o[1]))


## Like _row_of_buttons, but one option stays lit to show what's selected.
func _toggle_row(parent: Control, name_text: String, id: String,
		opts: Array, cb: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	_label(row, name_text, 84)
	var pairs: Array = []
	for o: Array in opts:
		var b := _button(row, String(o[0]), cb.bind(o[1]))
		b.toggle_mode = true
		pairs.append([o[1], b])
	_btn_groups[id] = pairs


func _light(id: String, value: Variant) -> void:
	if not _btn_groups.has(id):
		return
	for pair: Array in _btn_groups[id]:
		(pair[1] as Button).button_pressed = _same(pair[0], value)


static func _same(a: Variant, b: Variant) -> bool:
	if a is float or b is float:
		return absf(float(a) - float(b)) < 0.001
	return a == b


# ===========================================================================
#  Controls
# ===========================================================================

func _on_hour_slider(v: float) -> void:
	if _hour_dragging and _find():
		_dn.hour = fmod(v, 24.0)
		_dn._apply()


func _set_hour(h: float) -> void:
	if not _find():
		return
	_dn.hour = fposmod(h, 24.0)
	_dn._apply()
	refresh()


func _set_speed(sc: float) -> void:
	if _find():
		_dn.time_scale = sc
	_light("speed", sc)


func _add_days(n: float) -> void:
	if not _find():
		return
	_dn.day = maxf(0.0, _dn.day + n)
	Wind.publish_season(_dn.day)
	refresh()


func _set_season(idx: int) -> void:
	if not _find():
		return
	## Keep the year, land on the first day of that season.
	var year := floorf(_dn.day / Wind.DAYS_PER_YEAR) * Wind.DAYS_PER_YEAR
	_dn.day = year + float(idx) * Wind.DAYS_PER_SEASON
	Wind.publish_season(_dn.day)
	refresh()


func _set_level(lv: int) -> void:
	if not _find() or _wx == null:
		return
	_wx.set_weather(lv, _snap)
	refresh()


func _set_lock(on: bool) -> void:
	if not _find() or _wx == null:
		return
	if on:
		_wx.lock_weather(_wx.level, true)
	else:
		_wx.release_weather()
	_light("lock", on)


func _strike(distance: float) -> void:
	if _find() and _wx != null:
		_wx.strike(distance)


func _set_clouds(mode: int) -> void:
	if _find() and _world != null and _world.has_method("set_cloud_mode"):
		_world.set_cloud_mode(mode)
	_light("clouds", mode)
	## Keep the Settings row honest — the two controls are the same setting.
	var p := get_tree().get_first_node_in_group("player")
	if p != null and "set_clouds" in p:
		p.set_clouds = mode
		if p.has_method("_save_settings"):
			p._save_settings()
		if p.has_method("_refresh_settings_ui"):
			p._refresh_settings_ui()


func _on_coverage(v: float) -> void:
	if _find() and _sky != null:
		_sky.cloud_coverage = v
		_cover_dirty = true


func _set_aurora(v: float) -> void:
	if _find() and _wx != null:
		_wx.aurora_override = v
	_light("aurora", v)


# ===========================================================================
#  Readouts
# ===========================================================================

func _process(_delta: float) -> void:
	if visible:
		refresh()


func refresh() -> void:
	if not _find():
		return

	var h := _dn.hour
	## Round to the minute, don't truncate: 19.7 hours is 41.999... minutes in
	## float, and int() would print 19:41 for an hour that is exactly 19:42.
	var total := int(roundf(h * 60.0))
	@warning_ignore("integer_division")
	var hh := (total / 60) % 24
	var mm := total % 60
	var season: String = SEASONS[int(Wind.phase_for_day(_dn.day) * 4.0) % 4]
	_clock.text = "%02d:%02d   ·   Day %d   ·   %s" % [hh, mm, int(_dn.day), season]

	if not _hour_dragging:
		_hour_slider.set_value_no_signal(h)
	_light("speed", _dn.time_scale if "time_scale" in _dn else 1.0)

	if _wx != null and is_instance_valid(_wx):
		var held := " · HELD" if _wx.get("_locked") else ""
		_weather_line.text = "%s%s   ·   rain %.2f   ·   wet %.2f" % [
			_wx.level_name(), held, _wx.intensity, _wx.wetness]
		_light("level", _wx.level)
		_light("lock", bool(_wx.get("_locked")))
		_light("aurora", _wx.aurora_override)
		_light("snap", _snap)

	if _sky != null and is_instance_valid(_sky):
		var sun_y := 0.0
		if _dn.sun != null:
			sun_y = _dn.sun.global_transform.basis.z.normalized().y
		_sky_line.text = "sun %+.2f   ·   coverage %.2f   ·   dark %.2f   ·   gloom %.2f" % [
			sun_y, _sky.cloud_coverage, _sky.cloud_darkness, _sky.storm_gloom]
		_light("clouds", _sky.cloud_mode)
		## The weather owns coverage and will take it back on its next change;
		## don't fight the slider while someone is dragging it.
		if not _cover_slider.has_focus():
			_cover_slider.set_value_no_signal(_sky.cloud_coverage)
