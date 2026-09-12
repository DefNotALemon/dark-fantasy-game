extends PanelContainer
class_name MapPanel
## THE MAP (M). The baked Maine preview with everything the meta knows drawn
## over it -- towns, peaks, lakes, regions -- plus you, where you are, pointing
## where you look.
##
## Wheel zooms about the cursor, right-drag pans, and in GOD MODE a left click
## anywhere on the map puts you there: the near ring is warmed first
## (Player.god_teleport), so you land on ground that exists instead of falling
## through a tile that has not arrived yet. Out of god mode the click is
## refused -- fast travel is a debug tool, not a mechanic.
##
## Coordinates: the bake's row 0 is NORTH, so map v = 0 is z0 (the most
## negative z) and the image maps linearly onto the world with no flip.

const MAP_W := 520.0            ## 7.2 x 10.8 km at 2:3 -- the whole state, unzoomed
const MAP_H := 780.0
const ZOOM_MIN := 1.0
const ZOOM_MAX := 10.0
const ZOOM_STEP := 1.28
const LABEL_ZOOM := 1.8         ## small places only appear once you lean in

## Fallbacks for when the terrain never loaded, so the panel still opens
## instead of dividing by a zero-sized map.
const FALLBACK_ORIGIN := Vector2(-1199.79, -8800.08)
const FALLBACK_SIZE := Vector2(7200.0, 10800.0)

var player: Node3D = null       ## the Player; set by Player._build_hud()

var _view: Control = null
var _read: Label = null
var _tex: Texture2D = null
var _font: Font = null
var _zoom := 1.0
var _origin := Vector2.ZERO     ## where the map image's top-left sits in view space
var _hover := Vector2(-INF, -INF)
var _panning := false


func _ready() -> void:
	visible = false
	_font = ThemeDB.fallback_font
	_tex = load("res://assets/terrain/maine_preview.png") as Texture2D

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	margin.add_child(vb)

	var title := Label.new()
	title.text = "Map of Maine"
	title.add_theme_font_size_override("font_size", 22)
	vb.add_child(title)

	_view = Control.new()
	_view.custom_minimum_size = Vector2(MAP_W, MAP_H)
	_view.clip_contents = true
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.draw.connect(_draw_map)
	_view.gui_input.connect(_on_view_input)
	vb.add_child(_view)

	_read = Label.new()
	_read.add_theme_font_size_override("font_size", 13)
	_read.modulate = Color(1, 1, 1, 0.75)
	vb.add_child(_read)

	var hint := Label.new()
	hint.text = "M / Esc to close  •  wheel zooms  •  right-drag pans  •  in god mode: click to travel"
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(1, 1, 1, 0.5)
	vb.add_child(hint)


## Called by Player when M opens the panel: start looking at the whole state
## with the player roughly centred if they are zoomed in from last time.
func opened() -> void:
	_hover = Vector2(-INF, -INF)
	if _zoom > 1.0 and player != null and is_instance_valid(player):
		var eye := _eye()
		centre_on(eye.global_position.x, eye.global_position.z)
	_clamp_origin()
	_refresh_readout()
	if _view != null:
		_view.queue_redraw()


func _process(_delta: float) -> void:
	## The arrow has to track the body, so the map redraws while it is up --
	## and does nothing at all while it is not.
	if visible and _view != null:
		_view.queue_redraw()


# =============================================================================
# WORLD <-> MAP <-> VIEW
# =============================================================================
func _map_origin() -> Vector2:
	var ow := Overworld.inst
	if ow == null or not ow._loaded:
		return FALLBACK_ORIGIN
	return Vector2(ow.x0, ow.z0)


func _map_size() -> Vector2:
	var ow := Overworld.inst
	if ow == null or not ow._loaded or ow.nx <= 0 or ow.nz <= 0:
		return FALLBACK_SIZE
	return Vector2(float(ow.nx) * ow.step, float(ow.nz) * ow.step)


func _span() -> Vector2:
	## The map image's size in view pixels at the current zoom.
	return _view_size() * _zoom


func _view_size() -> Vector2:
	if _view == null or _view.size.x < 1.0:
		return Vector2(MAP_W, MAP_H)
	return _view.size


## World (x, z) -> a point in the view.
func _to_view(wx: float, wz: float) -> Vector2:
	var uv := (Vector2(wx, wz) - _map_origin()) / _map_size()
	return _origin + uv * _span()


## A point in the view -> world (x, z).
func _to_world(p: Vector2) -> Vector2:
	var uv := (p - _origin) / _span()
	return _map_origin() + uv * _map_size()


func _clamp_origin() -> void:
	## Never drag the map off its own frame: the image always covers the view.
	var span := _span()
	var vs := _view_size()
	_origin.x = clampf(_origin.x, vs.x - span.x, 0.0)
	_origin.y = clampf(_origin.y, vs.y - span.y, 0.0)


func _zoom_about(p: Vector2, factor: float) -> void:
	var was := _zoom
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(_zoom, was):
		return
	## Keep whatever is under the cursor under the cursor.
	_origin = p - (p - _origin) * (_zoom / was)
	_clamp_origin()


## Put the view on a world position at the current zoom, centred.
func centre_on(wx: float, wz: float) -> void:
	var uv := (Vector2(wx, wz) - _map_origin()) / _map_size()
	_origin = _view_size() * 0.5 - uv * _span()
	_clamp_origin()


# =============================================================================
# INPUT
# =============================================================================
func _on_view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom_about(mb.position, ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom_about(mb.position, 1.0 / ZOOM_STEP)
			MOUSE_BUTTON_RIGHT:
				_panning = mb.pressed
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_travel_to(mb.position)
		_view.queue_redraw()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_hover = mm.position
		if _panning:
			_origin += mm.relative
			_clamp_origin()
		_refresh_readout()
		_view.queue_redraw()


## Left click: fast travel, GOD MODE ONLY.
func _travel_to(p: Vector2) -> void:
	var w := _to_world(p)
	if player == null or not is_instance_valid(player):
		return
	if not bool(player.god):
		_read.text = "Fast travel is god mode only — F1 turns it on."
		return
	var target := Vector3(w.x, 0.0, w.y)
	if not Overworld.in_bounds(target):
		_read.text = "That is off the edge of the world."
		return
	## Stand on the ground, or on the water if there is water over it, with a
	## little clearance so the body settles instead of starting inside a slope.
	var g := Overworld.ground_y(target)
	var wy := Overworld.water_y(target)
	target.y = (maxf(g, wy) if wy != Overworld.NO_WATER else g) + 2.0
	## Spectating in the editor: the camera travels (and the body under it);
	## otherwise the body alone. GodEditor.travel_to does the first.
	var gm = player.get("godmode")     ## null when the player has no editor
	if gm != null and gm.has_method("spectating") and gm.spectating() and gm.has_method("travel_to"):
		gm.travel_to(target)
	elif player.has_method("god_teleport"):
		player.god_teleport(target)
	if player.has_method("_add_log_msg"):
		var nm := _place_label(w.x, w.y)
		player._add_log_msg("Travelled to %s" % nm, Color(0.62, 0.92, 1.0))
	## Land looking at the world, not at a map of it. Over the editor this
	## closes just the map (Player._toggle_menu knows), not the editor.
	if player.has_method("_close_menu"):
		player._close_menu()


func _place_label(wx: float, wz: float) -> String:
	var ow := Overworld.inst
	if ow == null or not ow._loaded:
		return "%d, %d" % [int(wx), int(wz)]
	var here := Vector3(wx, 0.0, wz)
	var nm := ow.place_name_at(here, 1400.0)
	if nm == "":
		nm = ow.region_name_at(here)
	if nm == "":
		nm = "%d, %d" % [int(wx), int(wz)]
	return nm


func _refresh_readout() -> void:
	if _read == null:
		return
	if _hover.x == -INF:
		_read.text = ""
		return
	var w := _to_world(_hover)
	var ow := Overworld.inst
	var line := "%s  —  x %d, z %d" % [_place_label(w.x, w.y), int(w.x), int(w.y)]
	if ow != null and ow._loaded:
		var g := ow.sample_height(w.x, w.y)
		var wy := ow.sample_water(w.x, w.y)
		if wy != Overworld.NO_WATER and wy > g:
			line += "  •  water, %.0f m deep" % (wy - g)
		else:
			line += "  •  %.0f m" % g
	if player != null and is_instance_valid(player) and bool(player.god):
		line += "        [ click to travel here ]"
	else:
		line += "        [ F1 god mode to travel ]"
	_read.text = line


# =============================================================================
# DRAWING
# =============================================================================
const C_SEA := Color(0.06, 0.09, 0.13)
const C_PLACE := Color(0.94, 0.90, 0.80)
const C_PEAK := Color(0.98, 0.80, 0.45)
const C_LAKE := Color(0.60, 0.82, 0.95)
const C_REGION := Color(1.0, 1.0, 1.0, 0.32)
const C_YOU := Color(0.35, 0.95, 1.0)


func _draw_map() -> void:
	var vs := _view_size()
	_view.draw_rect(Rect2(Vector2.ZERO, vs), C_SEA)
	if _tex != null:
		_view.draw_texture_rect(_tex, Rect2(_origin, _span()), false)
	else:
		_view.draw_string(_font, Vector2(14, 24), "maine_preview.png did not load",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.6, 0.6))

	var ow := Overworld.inst
	if ow != null and ow._loaded:
		_draw_regions(ow, vs)
		_draw_lakes(ow, vs)
		_draw_peaks(ow, vs)
		_draw_places(ow, vs)
	_draw_you(vs)

	## A hairline frame, so the map reads as a map and not as the panel.
	_view.draw_rect(Rect2(Vector2.ZERO, vs), Color(1, 1, 1, 0.18), false, 1.0)


func _on_screen(p: Vector2, vs: Vector2, pad := 60.0) -> bool:
	return p.x > -pad and p.y > -pad and p.x < vs.x + pad and p.y < vs.y + pad


func _draw_regions(ow: Overworld, vs: Vector2) -> void:
	if _zoom > 3.0:
		return          ## the big captions only get in the way up close
	for r: Dictionary in ow.regions():
		var q: Array = r["pos"]
		var p := _to_view(float(q[0]), float(q[1]))
		if not _on_screen(p, vs, 120.0):
			continue
		var t := String(r["name"])
		var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		_view.draw_string(_font, p - Vector2(w * 0.5, 0.0), t,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_REGION)


func _draw_lakes(ow: Overworld, vs: Vector2) -> void:
	if _zoom < LABEL_ZOOM:
		return
	for l: Dictionary in ow.lakes():
		var q: Array = l["pos"]
		var p := _to_view(float(q[0]), float(q[1]))
		if not _on_screen(p, vs):
			continue
		_view.draw_string(_font, p + Vector2(4, 4), String(l["name"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(C_LAKE, 0.8))


func _draw_peaks(ow: Overworld, vs: Vector2) -> void:
	for pk: Dictionary in ow.peaks():
		var q: Array = pk["pos"]
		var p := _to_view(float(q[0]), float(q[1]))
		if not _on_screen(p, vs):
			continue
		## A little caret for a summit.
		var tri := PackedVector2Array([p + Vector2(0, -5), p + Vector2(-4.5, 3), p + Vector2(4.5, 3)])
		_view.draw_colored_polygon(tri, C_PEAK)
		if _zoom >= LABEL_ZOOM:
			_view.draw_string(_font, p + Vector2(7, 4),
				"%s  %d m" % [String(pk["name"]), int(float(pk.get("y", 0.0)))],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(C_PEAK, 0.9))


func _draw_places(ow: Overworld, vs: Vector2) -> void:
	for pl: Dictionary in ow.places():
		var rank := int(pl.get("rank", 0))
		## Villages stay off the unzoomed map; cities are always on it.
		if rank == 0 and _zoom < LABEL_ZOOM:
			continue
		var q: Array = pl["pos"]
		var p := _to_view(float(q[0]), float(q[1]))
		if not _on_screen(p, vs):
			continue
		var r := 2.0 + float(rank)
		_view.draw_circle(p, r + 1.2, Color(0, 0, 0, 0.55))
		_view.draw_circle(p, r, C_PLACE)
		_view.draw_string(_font, p + Vector2(r + 4.0, 4.0), String(pl["name"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11 + rank, C_PLACE)


## Whose position the arrow marks: the body, or the spectator camera while
## god mode has you out of it (Player.map_eye decides).
func _eye() -> Node3D:
	if player != null and is_instance_valid(player) and player.has_method("map_eye"):
		var e: Node3D = player.map_eye()
		if e != null and is_instance_valid(e):
			return e
	return player


func _draw_you(vs: Vector2) -> void:
	if player == null or not is_instance_valid(player):
		return
	var eye := _eye()
	var pos: Vector3 = eye.global_position
	var p := _to_view(pos.x, pos.z)
	## Facing: the body's forward is -Z, and the map is a straight scaling of
	## world (x, z), so the screen angle is just atan2 of that vector.
	var fwd: Vector3 = -eye.global_transform.basis.z
	var ang := atan2(fwd.z, fwd.x)
	var arrow := PackedVector2Array([
		Vector2(9, 0).rotated(ang), Vector2(-6, 6).rotated(ang),
		Vector2(-3, 0).rotated(ang), Vector2(-6, -6).rotated(ang)])
	for i in range(arrow.size()):
		arrow[i] = arrow[i] + p
	if not _on_screen(p, vs, 0.0):
		## Off the visible patch: park a marker on the edge pointing home.
		var e := Vector2(clampf(p.x, 8.0, vs.x - 8.0), clampf(p.y, 8.0, vs.y - 8.0))
		_view.draw_circle(e, 5.0, Color(C_YOU, 0.55))
		return
	_view.draw_circle(p, 11.0, Color(C_YOU, 0.16))
	_view.draw_colored_polygon(arrow, C_YOU)
