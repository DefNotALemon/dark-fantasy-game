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
const FALLBACK_ORIGIN := Vector2(-1525.71, -8160.0)
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

# =============================================================================
# THE LIVING LAYERS  (2026-09-12)
# =============================================================================
## Everything above this line draws MAINE. Everything below it draws MYRKFELL:
## who holds the ground, the roads somebody cut, the households on them, who is
## walking them today and what died beside them. See `scripts/MapLayers.gd` for
## the one idea -- the border is not drawn, it is FOUND, by marching the sim's
## own `region_at` rule over a grid and emitting a wall wherever two cells come
## back in different hands.

const L_FRONTIER := "frontier"
const L_JOURNEY := "journey"
const L_ROADS := "roads"
const L_CROFTS := "crofts"
const L_BANDS := "travellers"
const L_KILLS := "kills"

## All five start ON. The small ones respect the panel's own existing rule --
## villages and lake names only appear past LABEL_ZOOM -- so the unzoomed map
## stays a map of the state and leaning in is what fills it with people.
const LAYERS: Array[String] = [L_JOURNEY, L_FRONTIER, L_ROADS, L_CROFTS, L_BANDS, L_KILLS]

var _on := {L_JOURNEY: true, L_FRONTIER: true, L_ROADS: true, L_CROFTS: true,
	L_BANDS: true, L_KILLS: true}

var _chips: HBoxContainer = null
var _part := PackedInt32Array()      ## cell -> roster index. Built ONCE, kept.
var _tint: ImageTexture = null       ## the territory, as one texture
var _border: Array = []              ## of MapLayers.border() rows, world coords
var _pol_key := ""                   ## the holder signature these were cut for
var _pol_t := 0.0                    ## seconds since the last politics check


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
	## ⚠ THE TERRITORY WASH IS A 130x195 TEXTURE STRETCHED OVER A 520x780 VIEW,
	## and the project's canvas default is NEAREST because Myrkfell is a pixel-art
	## game. Left alone, the political map came out as a grid of hard thirteen-
	## pixel blocks at 3x zoom -- which is not pixel art, it is a low-resolution
	## texture showing its seams. The map is the one surface in the game that is
	## NOT pixel art: it has anti-aliased strokes and a smooth font already.
	## Linear here makes the tint a wash, and it softens the bake at deep zoom
	## into the bargain.
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
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

	## THE LAYER CHIPS. Deliberately MOUSE ONLY: the map is already a
	## mouse-driven panel (wheel zooms, right-drag pans, left click travels),
	## and `tests/DevInputRegistry.gd` holds twenty-four keys Player._input
	## already claims. A layer toggle on a number key would shadow one of them,
	## and a shadowed dev input is round-blocking. This round adds NO BINDING.
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 6)
	vb.add_child(_chips)
	for id: String in LAYERS:
		var b := Button.new()
		b.text = id
		b.toggle_mode = true
		b.button_pressed = true
		b.focus_mode = Control.FOCUS_NONE
		b.flat = true
		b.add_theme_font_size_override("font_size", 12)
		b.toggled.connect(_on_chip.bind(id, b))
		_chips.add_child(b)
		_paint_chip(b, id)
	## One-line key, no new bind — DevInputRegistry is full. Sits on the
	## chips row so the control hint stays the close / zoom / pan line.
	var fort_key := Label.new()
	fort_key.text = "granite star = fort"
	fort_key.add_theme_font_size_override("font_size", 12)
	fort_key.modulate = Color(C_FORT, 0.85)
	_chips.add_child(fort_key)


## Called by Player when M opens the panel: start looking at the whole state
## with the player roughly centred if they are zoomed in from last time.
func opened() -> void:
	_hover = Vector2(-INF, -INF)
	_ensure_part()
	_refresh_politics(true)
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
	if not visible or _view == null:
		return
	## The frontier moves on the Chronicle's step, which is hours of game time
	## apart. Re-marching it every frame would cost 6 ms a frame for an answer
	## that changes about once an in-game day, so it is checked on a timer and
	## re-cut only when the holder signature actually differs.
	_pol_t += _delta
	if _pol_t > 0.75:
		_pol_t = 0.0
		_refresh_politics(false)
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
	## WHOSE ground, and what season it is HERE. `Factions.margin_of` has said
	## how firm a grip is since `42a74e1` and nothing had ever shown it to a
	## player; `Seasons.local_index` has disagreed with itself across the map on
	## 30 of the year's 96 days since `bc142ff` and nowhere could you read it
	## off a place. Both are one hover away now.
	var ch := _bus("chronicle")
	if ch != null and bool(_on[L_FRONTIER]):
		var rn := Factions.region_at(Vector3(w.x, 0.0, w.y), Chronicle.REGION_ROSTER)
		var hl := MapLayers.hold_line(ch.get("factions") as Dictionary, rn)
		if not hl.is_empty():
			line += "  •  %s" % hl
		var here := Vector3(w.x, 0.0, w.y)
		var si := Seasons.local_index(float(ch.get("days")), here)
		line += "  •  %s" % Seasons.name_of(si)
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
const C_FORT := Color(0.58, 0.56, 0.52)   ## granite — not cream, not the peak orange
const C_PEAK := Color(0.98, 0.80, 0.45)
const C_LAKE := Color(0.60, 0.82, 0.95)
const C_REGION := Color(1.0, 1.0, 1.0, 0.32)
const C_YOU := Color(0.35, 0.95, 1.0)

const MARK_FORT := "fort"
const MARK_CITY := "city"
const MARK_TOWN := "town"
const MARK_HAMLET := "hamlet"

## Exact names only. "Fort Kent" is a rank-0 hamlet on the bake; a prefix
## match would steal its mark. World appends Knox and Gorges as rank-1
## places with no `kind` this slice — the names are the fort list.
const FORT_PLACE_NAMES := ["Fort Knox", "Fort Gorges"]


## Pure. Off-tree. `kind == "fort"` wins if a later row carries it; otherwise
## only the two authored fort names. Never `begins_with("Fort")`.
static func is_fort_place(pl: Dictionary) -> bool:
	if String(pl.get("kind", "")) == "fort":
		return true
	return String(pl.get("name", "")) in FORT_PLACE_NAMES


## Settlement glyph: fort | city | town | hamlet. Rank sizes the cream
## circles (Portland bake rank 3 is the largest city mark); forts ignore
## that ladder and take the granite star.
static func place_mark(pl: Dictionary) -> String:
	if is_fort_place(pl):
		return MARK_FORT
	var rank := int(pl.get("rank", 0))
	if rank >= 3:
		return MARK_CITY
	if rank >= 1:
		return MARK_TOWN
	return MARK_HAMLET


## Forts always show, like rank >= 1, even if someone later files them
## rank 0. Hamlets stay zoom-gated at LABEL_ZOOM.
static func place_visible(pl: Dictionary, zoom: float) -> bool:
	if is_fort_place(pl):
		return true
	if int(pl.get("rank", 0)) >= 1:
		return true
	return zoom >= LABEL_ZOOM


## Cream-circle radius. Rank 3 is the largest city mark.
static func place_dot_radius(pl: Dictionary) -> float:
	return 2.0 + float(int(pl.get("rank", 0)))


## Four-pointed granite star (8 verts). Not a cream circle, not the 3-vert
## peak caret.
static func fort_star(p: Vector2, s: float = 5.5) -> PackedVector2Array:
	var inner := s * 0.38
	return PackedVector2Array([
		p + Vector2(0.0, -s),
		p + Vector2(inner, -inner),
		p + Vector2(s, 0.0),
		p + Vector2(inner, inner),
		p + Vector2(0.0, s),
		p + Vector2(-inner, inner),
		p + Vector2(-s, 0.0),
		p + Vector2(-inner, -inner),
	])


## The orange summit caret `_draw_peaks` already used. Kept as a function so
## the fort star can be proved a different polygon, not a second peak.
static func peak_caret(p: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		p + Vector2(0.0, -5.0),
		p + Vector2(-4.5, 3.0),
		p + Vector2(4.5, 3.0),
	])


func _draw_map() -> void:
	var vs := _view_size()
	_view.draw_rect(Rect2(Vector2.ZERO, vs), C_SEA)
	if _tex != null:
		_view.draw_texture_rect(_tex, Rect2(_origin, _span()), false)
	else:
		_view.draw_string(_font, Vector2(14, 24), "maine_preview.png did not load",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.6, 0.6))

	## Ground, then politics, then the works of men, then the labels, then the
	## living. The bake is the paper; the tint is a wash over it and never a
	## replacement for it.
	if bool(_on[L_FRONTIER]):
		_draw_territory()
	if bool(_on[L_ROADS]):
		_draw_roads(vs)
	if bool(_on[L_FRONTIER]):
		_draw_border(vs)

	var ow := Overworld.inst
	if ow != null and ow._loaded:
		if bool(_on[L_JOURNEY]):
			_draw_journey(ow, vs)
		_draw_regions(ow, vs)
		_draw_lakes(ow, vs)
		_draw_peaks(ow, vs)
		_draw_places(ow, vs)

	if bool(_on[L_CROFTS]):
		_draw_crofts(vs)
	if bool(_on[L_KILLS]):
		_draw_kills(vs)
	if bool(_on[L_BANDS]):
		_draw_bands(vs)
	_draw_you(vs)
	if bool(_on[L_FRONTIER]):
		_draw_key(vs)

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
		## A caption in the holder's colour is the cheapest reading of the
		## political map there is: you can tell whose country you are looking
		## at without a legend and without hovering anything.
		var col := C_REGION
		if bool(_on[L_FRONTIER]):
			var h := _holder_of(t)
			if not h.is_empty():
				col = MapLayers.colour_of(h)
				col.a = 0.82
		_view.draw_string(_font, p - Vector2(w * 0.5, 0.0), t,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


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
		## A little caret for a summit — not the fort star.
		_view.draw_colored_polygon(peak_caret(p), C_PEAK)
		if _zoom >= LABEL_ZOOM:
			_view.draw_string(_font, p + Vector2(7, 4),
				"%s  %d m" % [String(pk["name"]), int(float(pk.get("y", 0.0)))],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(C_PEAK, 0.9))


func _draw_places(ow: Overworld, vs: Vector2) -> void:
	for pl: Dictionary in ow.places():
		if not place_visible(pl, _zoom):
			continue
		var q: Array = pl["pos"]
		var p := _to_view(float(q[0]), float(q[1]))
		if not _on_screen(p, vs):
			continue
		var mark := place_mark(pl)
		if mark == MARK_FORT:
			_view.draw_colored_polygon(fort_star(p, 6.6), Color(0.04, 0.04, 0.05, 0.72))
			_view.draw_colored_polygon(fort_star(p), C_FORT)
			_view.draw_string(_font, p + Vector2(8.0, 4.0), String(pl["name"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_FORT)
			continue
		var rank := int(pl.get("rank", 0))
		var r := place_dot_radius(pl)
		_view.draw_circle(p, r + 1.2, Color(0, 0, 0, 0.55))
		_view.draw_circle(p, r, C_PLACE)
		_view.draw_string(_font, p + Vector2(r + 4.0, 4.0), String(pl["name"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11 + rank, C_PLACE)


func _draw_journey(ow: Overworld, vs: Vector2) -> void:
	## The gold thread is the main story's intended travel rhythm: Lewiston
	## south-east to tidewater, north along the coast, then inland into the
	## high-level country. It is deliberately broader than a road because it
	## describes a chapter, not one compulsory footpath.
	var acts: Array = ow.story_route()
	for act: Dictionary in acts:
		var points: Array = act.get("points", [])
		if points.size() < 2:
			continue
		var line := PackedVector2Array()
		var any := false
		for point: Dictionary in points:
			var q: Array = point.get("pos", [])
			if q.size() < 2:
				continue
			var p := _to_view(float(q[0]), float(q[1]))
			line.append(p)
			any = any or _on_screen(p, vs, 80.0)
		if not any or line.size() < 2:
			continue
		var act_i := clampi(int(act.get("act", 1)), 1, 5)
		var col := Color(0.94, 0.72, 0.28, 0.68).lerp(
			Color(0.72, 0.86, 1.0, 0.78), float(act_i - 1) / 4.0)
		_view.draw_polyline(line, Color(0.05, 0.04, 0.03, 0.72), 5.2, true)
		_view.draw_polyline(line, col, 2.4, true)
		var start := line[0]
		_view.draw_circle(start, 7.0, Color(0.04, 0.04, 0.05, 0.88))
		_view.draw_circle(start, 5.5, col)
		_view.draw_string(_font, start + Vector2(-3.2, 3.7), str(act_i),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.05, 0.05, 0.06))


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


# =============================================================================
# THE LIVING LAYERS -- plumbing
# =============================================================================
## Every bus is found by GROUP and used DUCK-TYPED. `World.gd` loads this panel
## by path rather than by class_name precisely to avoid a name-level cycle, and
## reaching back into World by type here would rebuild the cycle from the other
## end. Groups cost nothing and cannot create one.
func _bus(group: String) -> Node:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(group)


func _bus_ready(n: Node) -> bool:
	## ⚠ `ready` IS A SIGNAL ON EVERY Node, and `RoadNet`, `Crofts` and
	## `Wayfarers` each declare a `ready()` METHOD that shadows it. `call("ready")`
	## does resolve to the method -- methods and signals are different tables --
	## but a bus that has not declared one would take the signal's name and fail
	## at runtime inside a draw call, which is the worst place in the frame to
	## find out. Asked properly: does this object actually have the method?
	return n != null and n.has_method("ready") and bool(n.call("ready"))


func _ensure_part() -> void:
	## The partition is a pure function of `Chronicle.REGION_ROSTER`, which is a
	## const. It is therefore the SAME ANSWER for the life of the process and is
	## built once, lazily, the first time the map opens: 30 ms measured, on a
	## panel that is already opening, against 6 ms a frame forever if it were
	## not kept.
	if not _part.is_empty():
		return
	_part = MapLayers.partition(Chronicle.REGION_ROSTER, MapLayers.GRID_NX,
		MapLayers.GRID_NZ, _map_origin(), _map_size())


func _state() -> Dictionary:
	var ch := _bus("chronicle")
	if ch == null:
		return {}
	var st: Variant = ch.get("factions")
	return st as Dictionary if st is Dictionary else {}


func _holder_of(region: String) -> String:
	var st := _state()
	if st.is_empty() or not st.has(region):
		return ""
	return Factions.holder_of(st, region)


func _refresh_politics(force: bool) -> void:
	## Re-cut the border and repaint the tint ONLY when a region has actually
	## changed hands. The signature is the holder list itself, so a margin that
	## drifts without crossing a threshold costs nothing and a province falling
	## redraws the map on the next quarter second.
	var st := _state()
	if st.is_empty() or _part.is_empty():
		return
	var sides := MapLayers.sides(Chronicle.REGION_ROSTER, st)
	var key := "|".join(sides)
	if key == _pol_key and not force and _tint != null:
		return
	_pol_key = key
	_border = MapLayers.border(Chronicle.REGION_ROSTER, st, _part,
		MapLayers.GRID_NX, MapLayers.GRID_NZ, _map_origin(), _map_size())
	var img := MapLayers.tint_image(_part, MapLayers.GRID_NX, MapLayers.GRID_NZ, sides)
	_tint = ImageTexture.create_from_image(img)


func _on_chip(pressed: bool, id: String, b: Button) -> void:
	_on[id] = pressed
	_paint_chip(b, id)
	if _view != null:
		_view.queue_redraw()


func _paint_chip(b: Button, id: String) -> void:
	## A chip that is on wears its layer's colour; one that is off is grey. No
	## second legend to keep in step with the map.
	var col := CHIP_TINT.get(id, Color(0.85, 0.85, 0.85)) as Color
	b.modulate = col if bool(_on[id]) else Color(0.45, 0.45, 0.45, 0.7)


const CHIP_TINT := {
	L_JOURNEY: Color(0.96, 0.74, 0.32),
	L_FRONTIER: Color(0.90, 0.55, 0.45),
	L_ROADS: Color(0.86, 0.78, 0.60),
	L_CROFTS: Color(1.00, 0.84, 0.52),
	L_BANDS: Color(0.62, 0.88, 0.98),
	L_KILLS: Color(0.86, 0.44, 0.40),
}


# =============================================================================
# THE LIVING LAYERS -- drawing
# =============================================================================
const C_ROAD := Color(0.28, 0.22, 0.16, 0.85)
const C_ROAD_HI := Color(0.92, 0.84, 0.66, 0.55)
const C_CROFT := Color(1.00, 0.84, 0.52)
const C_CROFT_COLD := Color(0.62, 0.66, 0.72)
const C_BAND := Color(0.62, 0.88, 0.98)
const C_BAND_HELD := Color(0.70, 0.70, 0.74)
const C_KILL := Color(0.86, 0.44, 0.40)


func _draw_territory() -> void:
	if _tint == null:
		return
	## ONE texture, not 25 350 rectangles. Stretched over the bake with the
	## viewport's own filtering it reads as a wash of colour over the ground
	## rather than as a grid of cells, and it costs a single draw call at any
	## zoom the panel allows.
	_view.draw_texture_rect(_tint, Rect2(_origin, _span()), false)


func _draw_border(vs: Vector2) -> void:
	for row in _border:
		var rd := row as Dictionary
		var firm := clampi(int(rd.get("firm", 2)), 0, 2)
		var pts: PackedVector2Array = rd["pts"]
		if pts.size() < 2:
			continue
		var view := PackedVector2Array()
		var any := false
		for wp: Vector2 in pts:
			var v := _to_view(wp.x, wp.y)
			view.append(v)
			if not any and _on_screen(v, vs, 40.0):
				any = true
		if not any:
			continue
		## A settled border is one confident line. An uneasy one is thinner and
		## broken. A contested one is barely a line at all -- because that is
		## what the word means, and `Factions` is the thing that said it.
		var wsz := MapLayers.FIRM_WIDTH[firm]
		var dash := MapLayers.FIRM_DASH[firm]
		var gap := MapLayers.FIRM_GAP[firm]
		if dash <= 0.0:
			_view.draw_polyline(view, MapLayers.C_BORDER_BED, wsz + MapLayers.BED_EXTRA, true)
			_view.draw_polyline(view, MapLayers.C_BORDER, wsz, true)
		else:
			_dashed(view, MapLayers.C_BORDER_BED, wsz + MapLayers.BED_EXTRA, dash, gap)
			_dashed(view, MapLayers.C_BORDER, wsz, dash, gap)


func _dashed(pts: PackedVector2Array, col: Color, wsz: float, dash: float,
		gap: float) -> void:
	## Walk the polyline in view pixels, so the dash reads the same at every
	## zoom instead of stretching into a solid line when you lean in.
	var on := true
	var left := dash
	var i := 0
	var cur := pts[0]
	while i < pts.size() - 1:
		var nxt := pts[i + 1]
		var seg := cur.distance_to(nxt)
		if seg <= 0.0001:
			i += 1
			cur = nxt
			continue
		if seg <= left:
			if on:
				_view.draw_line(cur, nxt, col, wsz, true)
			left -= seg
			i += 1
			cur = nxt
		else:
			var hit := cur.lerp(nxt, left / seg)
			if on:
				_view.draw_line(cur, hit, col, wsz, true)
			cur = hit
			on = not on
			left = dash if on else gap


func _draw_roads(vs: Vector2) -> void:
	## 41.7 km of road that 58 edges of coordinate descent cut through real
	## terrain on 2026-09-09, and until today nobody could see one metre of it.
	## 399 polyline points across the whole net -- it is free to draw.
	var net := _bus("roads")
	if not _bus_ready(net):
		return
	var edges: Array = net.get("edges")
	for e in edges:
		var ed := e as Dictionary
		var poly: PackedVector2Array = ed["poly"]
		if poly.size() < 2:
			continue
		var view := PackedVector2Array()
		var any := false
		for wp: Vector2 in poly:
			var v := _to_view(wp.x, wp.y)
			view.append(v)
			if not any and _on_screen(v, vs, 40.0):
				any = true
		if not any:
			continue
		## Two strokes: a dark bed and a pale metalled line over it, so a road
		## reads against both the dark forest and the bright shore of the bake.
		_view.draw_polyline(view, C_ROAD, 2.6, true)
		_view.draw_polyline(view, C_ROAD_HI, 1.1, true)


func _draw_crofts(vs: Vector2) -> void:
	## The panel's own rule: small things only appear once you lean in.
	if _zoom < LABEL_ZOOM:
		return
	var cr := _bus("crofts")
	if not _bus_ready(cr):
		return
	var rows: Array = cr.get("crofts")
	var st: Dictionary = cr.get("state")
	for c in rows:
		var cd := c as Dictionary
		var wp: Vector2 = cd.get("pos", Vector2.ZERO)
		var v := _to_view(wp.x, wp.y)
		if not _on_screen(v, vs):
			continue
		## A COLD HEARTH IS THE ONE THING THE CROFTS SIM SAYS THAT NOBODY COULD
		## EVER SEE. `3a24658` measured a whole simulated year to prove that an
		## autumn spent barred indoors is a winter with no smoke over that
		## chimney four months later -- and the only evidence was a test. A
		## croft with a cold hearth is drawn hollow.
		var sd: Dictionary = st.get(String(cd.get("id", "")), {})
		var cold := float(sd.get("cold_h", 0.0)) > 0.0 or bool(sd.get("was_cold", false))
		var col := C_CROFT_COLD if cold else C_CROFT
		var r := 2.4
		_view.draw_circle(v, r + 1.1, Color(0, 0, 0, 0.6))
		if cold:
			_view.draw_arc(v, r, 0.0, TAU, 10, col, 1.2, true)
		else:
			_view.draw_circle(v, r, col)
		if _zoom >= LABEL_ZOOM * 2.0:
			_view.draw_string(_font, v + Vector2(r + 3.0, 3.5),
				String(cd.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
				Color(col, 0.85))


func _draw_bands(vs: Vector2) -> void:
	## Twenty named travellers, each making a fixed circuit for the rest of the
	## game whether or not you are there to see it (`f0e07ce`). A band the
	## weather has HELD somewhere is drawn as a dot rather than a chevron --
	## which is the storm emptying the roads, made visible.
	var wf := _bus("wayfarers")
	if not _bus_ready(wf):
		return
	var bands: Array = wf.get("bands")
	for b in bands:
		var w: Dictionary = wf.call("where", b as Dictionary)
		if w.is_empty():
			continue
		var wp: Vector2 = w["pos"]
		var v := _to_view(wp.x, wp.y)
		if not _on_screen(v, vs):
			continue
		if bool(w.get("holding", false)):
			_view.draw_circle(v, 3.6, Color(0, 0, 0, 0.6))
			_view.draw_circle(v, 2.4, C_BAND_HELD)
			continue
		var d: Vector2 = w.get("dir", Vector2(0, 1))
		var ang := atan2(d.y, d.x)
		var tri := PackedVector2Array([
			Vector2(5.5, 0).rotated(ang), Vector2(-3.5, 3.2).rotated(ang),
			Vector2(-3.5, -3.2).rotated(ang)])
		for i in range(tri.size()):
			tri[i] = tri[i] + v
		_view.draw_colored_polygon(tri, C_BAND)
		if _zoom >= LABEL_ZOOM:
			_view.draw_string(_font, v + Vector2(7, 3.5), String(w.get("name", "")),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(C_BAND, 0.8))


func _draw_kills(vs: Vector2) -> void:
	if _zoom < LABEL_ZOOM:
		return
	var ca := _bus("carcasses")
	if ca == null:
		return
	var recs: Array = ca.get("records")
	for rec in recs:
		var rd := rec as Dictionary
		var at: Vector3 = rd.get("at", Vector3.ZERO)
		var v := _to_view(at.x, at.z)
		if not _on_screen(v, vs):
			continue
		## A CARCASS IS A LEDGER ENTRY WITH KILOGRAMS ON IT (`a23a20e`), and the
		## mark is the fraction left: a fresh kill is a filled dot, a picked-over
		## one a ring, bones a hairline. The same number the crows, the fox, the
		## pack, the bear and -- since `868c60d` -- you are all billing against.
		var mass := maxf(float(rd.get("mass", 1.0)), 0.001)
		var f := clampf(float(rd.get("left", 0.0)) / mass, 0.0, 1.0)
		var r := 1.6 + 2.6 * f
		_view.draw_circle(v, r + 1.0, Color(0, 0, 0, 0.55))
		if f > Carcasses.BONES_AT:
			_view.draw_circle(v, r, Color(C_KILL, 0.45 + 0.5 * f))
		else:
			_view.draw_arc(v, r, 0.0, TAU, 9, Color(C_KILL, 0.55), 1.0, true)


func _draw_key(vs: Vector2) -> void:
	## ONLY the claimants actually holding something right now. Measured over 96
	## simulated days x 17 regions, the holder tally is {men 792, goblins 493,
	## contested 347} and WOLVES AND WILD NEVER HOLD ANYTHING AT ALL -- so a
	## fixed four-colour key would spend two of its rows on answers a player will
	## never see, and would go on lying if that ever changed.
	var st := _state()
	if st.is_empty():
		return
	var seen: Array[String] = []
	for r in Chronicle.REGION_ROSTER:
		var nm := String((r as Dictionary).get("name", ""))
		if not st.has(nm):
			continue
		var h := Factions.holder_of(st, nm)
		if not seen.has(h):
			seen.append(h)
	var y := vs.y - 10.0 - float(seen.size()) * 14.0
	for h2: String in seen:
		var col := MapLayers.colour_of(h2)
		col.a = 0.95
		_view.draw_rect(Rect2(Vector2(10.0, y - 8.0), Vector2(10.0, 10.0)), col)
		_view.draw_string(_font, Vector2(25.0, y), MapLayers._who(h2),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.8))
		y += 14.0
