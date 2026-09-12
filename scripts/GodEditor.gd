class_name GodEditor
extends PanelContainer

## ===========================================================================
## GOD MODE — scripts/GodEditor.gd                          bound to  F1
##
## The map authoring tool. F1 lifts you OUT OF YOUR BODY, Minecraft-spectator
## style: a free camera detaches at exactly the view you had, and your
## character stays standing where you left them. F1 again drops you back into
## their head, wherever the camera has wandered to.
##
##   SPECTATOR  the camera has no body. WASD along the look, SPACE up, CTRL
##              down, SHIFT boosts, wheel is the speed dial. Nothing to collide
##              with, nothing to fall off.
##
##   THE BODY   parked. Its collision layer goes to 0 and EditorMode.active
##              goes true, so no mob, no animal, no swarm and no falling trunk
##              can see it, reach it or hunt it while you are out.
##              "Bring body here" moves it to the camera; F1 returns you to it.
##              F2 does both at once and LEAVES: body to the camera, editor
##              shut, survival back on, and the fall down is on the house.
##
##   LOOKING    F FLIPS THE MOUSE. In CURSOR mode (the default) the pointer
##              belongs to the panel and you look by holding RIGHT MOUSE and
##              dragging. Press F and the mouse is captured: you look by moving
##              it, like ordinary play, and the crosshair is what you are
##              aiming with. F again gives the cursor back.
##              Everything else stays live: weather, wildlife, the sun.
##
##   TOOLS      Select · Zone · Path · Note · Trees · Build · Ground · Erase.
##              LEFT MOUSE is always "do the current tool where I am aiming".
##              Ground PAINTS the ground-sheet textures (scripts/GroundPaint.gd):
##              hold LEFT MOUSE to stroke, the palette picks the tile, and the
##              WORLD STYLE dropdown re-dresses every unpainted cell at once.
##
##   THE MAP    M opens the map OVER the editor (it used to close it). The
##              spectator camera is the arrow; clicking travels camera and
##              body both; M or Esc closes just the map and you are back here.
##
## WHAT IT WRITES
##
##   design/world_plan.json  + WORLD_PLAN.md   the PLAN — zones, roads, notes.
##                                            Claude reads the .md.
##   design/build_placements.json              the STUFF — pieces and trees
##                                            you actually put in the world.
##   design/ground_paint.dat + ground.json     the GROUND — painted tiles and
##                                            the world style (GroundPaint.gd).
##
## Both live in res://design/ when the game is run from the Godot editor.
## Neither depends on a save game: start a new run and the town is still there.
##
## LATER (Stardew): every placement here is a {piece, pos, rot, mat} record and
## BuildKit.COST already prices them. A survival build mode is this file's
## Build tab minus god mode, plus a pack check — the catalog, the ghost, the
## snapping and the record format all carry over unchanged.
## ===========================================================================

const PLACEMENT_FILE := "build_placements.json"
const PANEL_W := 356.0
const REACH := 1400.0            ## how far the aim ray looks
const MARCH_MAX := 1400.0
const SPEED_MIN := 0.35
const SPEED_MAX := 24.0
const SPEED_STEP := 1.22         ## one wheel click, multiplicative

## --- wiring ----------------------------------------------------------------
var _player: Player = null
var _world: Node3D = null
var viz: PlanViz = null
var cam: EditorCam = null       ## the spectator eye — see scripts/EditorCam.gd

## --- tool state -------------------------------------------------------------
var tool := "select"
var typing := false              ## a text box has the keyboard — Player, hands off

var zone_kind := "village"
var zone_mode := "poly"          ## "poly" | "circle"
var circle_r := 30.0
var path_kind := "road"
var path_width := 6.0

var note_tag := "todo"
var note_attach := true

var tree_species := "maple"
var tree_stage := 2
var tree_brush := 0.0            ## 0 = single tree; >0 = scatter radius
var tree_density := 0.02         ## trees per m² inside the brush

var build_mode := "piece"        ## "piece" | "prefab"
var build_piece := "wall"
var build_mat := ""
var build_prefab := "cottage"
var build_rot := 0.0
var build_scale := 1.0
var build_y := 0.0               ## manual height nudge off the ground
var grid_snap := true
var erase_plan := false          ## Erase tool: objects, or plan marks

## Ground tool (the ground-sheet textures, scripts/GroundPaint.gd)
var ground_id := 67              ## the tile the brush paints: 7-A, the house style's meadow
var ground_brush := 12.0         ## metres
var ground_erase := false        ## brush erases back to the world style
var _painting := false           ## LMB is held on the ground tool
var _paint_last := Vector3(INF, INF, INF)
var _confirm := ""               ## a destructive button waiting for its second click
var _ground_label: Label = null
var _ground_hover: Label = null

var selected_id := ""

## --- draft ------------------------------------------------------------------
var _draft: PackedVector2Array = PackedVector2Array()

## --- ghost ------------------------------------------------------------------
var _ghost: Node3D = null
var _ghost_key := ""
var _aim_pos := Vector3.ZERO
var _aim_node: Node = null
var _aim_valid := false

## --- placement bookkeeping ---------------------------------------------------
var _pieces: Array = []          ## live BuiltPiece nodes
var _trees: Array = []           ## live TreeV2 nodes we planted
var _rng := RandomNumberGenerator.new()
var _dirty := false
var _save_t := 0.0

## --- the mouse ---------------------------------------------------------------
## F flips between the two. false = CURSOR: the pointer drives the panel and
## RIGHT-MOUSE-DRAG looks. true = LOOK: the mouse is captured and moving it
## turns your head, exactly like playing, and the aim is screen centre.
var mouse_look := false
var _looking := false           ## RMB is down and dragging (cursor mode only)

## --- UI ----------------------------------------------------------------------
var _status: Label
var _hint: Label
var _body: VBoxContainer
var _tool_box: VBoxContainer
var _tool_btns := {}
var _note_title: LineEdit
var _note_body: TextEdit
var _sel_name: LineEdit
var _sel_info: Label
var _flag_btns := {}


# ===========================================================================
#  Boot
# ===========================================================================

func _ready() -> void:
	add_to_group("builder")
	visible = false
	_rng.randomize()
	custom_minimum_size = Vector2(PANEL_W, 0)
	set_anchors_preset(Control.PRESET_LEFT_WIDE)
	offset_left = 12
	offset_right = 12 + PANEL_W
	offset_top = 14
	offset_bottom = -14
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	set_process(true)
	set_process_unhandled_input(true)
	## Everything else in the world is still coming up; find it next frame.
	call_deferred("_late_boot")


func _late_boot() -> void:
	_player = get_tree().get_first_node_in_group("player") as Player
	_world = get_tree().get_first_node_in_group("world") as Node3D
	if _world == null and _player != null:
		_world = _player.get_parent() as Node3D
	if viz == null and _world != null:
		viz = PlanViz.new()
		viz.name = "PlanViz"
		_world.add_child(viz)
	if cam == null and _world != null:
		cam = EditorCam.new()
		cam.name = "EditorCam"
		_world.add_child(cam)
	if not WorldPlan.loaded:
		WorldPlan.load_plan()
	restore_all()
	if viz != null:
		viz.rebuild()
		viz.visible = false
	_refresh_tool_page()


# ===========================================================================
#  Open / close  (Player routes this through _toggle_menu("god"))
# ===========================================================================

func opened() -> void:
	visible = true
	## Step out of the body FIRST (it parks and goes untouchable), then lift the
	## camera out of the head it was in. Order matters: set_editing puts the
	## body in third person, so the eye we copy is the one you were using.
	if _player != null:
		_player.set_editing(true)
	if cam != null and _player != null:
		cam.take_over(_player.camera)
		cam.typing = false
	if viz != null:
		viz.visible = true
	mouse_look = false     ## Player's _toggle_menu frees the cursor right after us
	_flag("mouse", false)
	_refresh_tool_page()
	_note("Spectator. F1 returns you to your body · F2 drops you in HERE "
		+ "· F flips the mouse (cursor / look) · wheel for speed.")


func spectating() -> bool:
	return visible and cam != null and cam.active


func active_cam() -> Camera3D:
	## Whichever eye is live. Everything that aims, ghosts or measures goes
	## through here so the editor never reads a camera that is not rendering.
	if cam != null and cam.active:
		return cam
	return _player.camera if _player != null else null


func return_to_body() -> void:
	if _player != null:
		_player.set_editing(false)
	if cam != null and _player != null:
		cam.release(_player.camera)


func bring_body_here() -> void:
	## The other direction: put the character where you are standing (well,
	## floating). Lands them on the ground under the camera, and warms the
	## terrain first so there IS ground under them.
	if _player == null or cam == null:
		return
	var p := cam.global_position
	var g := Overworld.ground_y(p)
	var to := Vector3(p.x, maxf(g + 1.2, p.y - 1.6), p.z)
	if _player.has_method("god_teleport"):
		_player.god_teleport(to)
	else:
		_player.global_position = to
	_note("Body moved here.")


func drop_in_here() -> void:
	## F2 -- DROP IN. The one-key way out of the editor: your character comes to
	## wherever you are floating and you land in them, PLAYING. Not spectating,
	## not god: survival. Health, stamina and thirst start ticking again and the
	## world can see you the moment the panel shuts.
	##
	## The drop itself is free. Coming down 300 m because you were building up
	## there is not a fall you chose, so Player.fall_grace() spends one landing
	## with no damage, no death and no knockdown -- the NEXT one is judged
	## normally. The grace is armed before the body moves, so a short hop off a
	## rooftop cannot land and spend it before the editor has even closed.
	if _player == null or cam == null:
		return
	if _player.has_method("fall_grace"):
		_player.fall_grace()
	bring_body_here()
	## Survival, whatever the GOD flag was set to. The panel's sticky toggle
	## decides what body you go BACK to; F2 says that body is a mortal one.
	_player.god_sticky = false
	_flag("god", false)
	_player.flying = false
	if map_over():
		_player._map_over_god(false)   ## the map is an overlay -- shut it first
	_player._close_menu()              ## -> closed() -> return_to_body()
	_note("Dropped in. Survival -- the landing is on the house.")


## --- the map over the editor ------------------------------------------------
## Player._toggle_menu("map") while we are up shows the map WITHOUT closing us:
## menu_open becomes "map" and we stay visible and spectating underneath.

func map_over() -> bool:
	return visible and _player != null and _player.menu_open == "map"


func map_opened() -> void:
	_painting = false
	_looking = false
	if mouse_look:
		set_mouse_look(false)      ## the map needs a pointer
	_note("Map. Click to travel · M or Esc back to the editor.")


func map_closed() -> void:
	_looking = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE    ## back to CURSOR mode


func travel_to(target: Vector3) -> void:
	## Fast travel from the map while spectating: the camera goes -- and the
	## body comes along underneath, so F1 still returns you to your character
	## where you are, not 4 km back where you left it.
	if _player == null:
		return
	if _player.has_method("god_teleport"):
		_player.god_teleport(target)
	else:
		_player.global_position = target
	if cam != null and cam.active:
		cam.place(target + Vector3(0.0, 14.0, 22.0), target)
	_paint_last = Vector3(INF, INF, INF)


func closed() -> void:
	visible = false
	typing = false
	mouse_look = false     ## _close_menu recaptures for ordinary play
	return_to_body()
	_clear_ghost()
	_draft = PackedVector2Array()
	if viz != null:
		viz.clear_draft()
		viz.visible = false
	save_now()


func _note(txt: String) -> void:
	if _player != null:
		_player._add_log_msg(txt, Color(0.62, 0.92, 1.0))


# ===========================================================================
#  Input — Player hands us every event first while the panel is up
# ===========================================================================

func eat_input(event: InputEvent) -> bool:
	## Returns true when the editor has taken the event and Player should not
	## also act on it. ONE arbitration point, so the two never fight.
	if not visible:
		## Even closed, F1 has to get through to open us.
		if event is InputEventKey and event.pressed and not event.echo \
				and (event as InputEventKey).keycode == KEY_F1:
			return false   ## Player's own KEY_F1 case opens the panel
		return false

	if map_over():
		## The map is open on top of us: it owns every click, wheel and key
		## (M / Esc close it through Player). We take nothing.
		_painting = false
		return false

	if event is InputEventKey:
		var k := event as InputEventKey
		if typing:
			## Typing owns the keyboard, except the one key that gets you out.
			if k.pressed and k.keycode == KEY_ESCAPE:
				_drop_focus()
				return true
			return true
		if not k.pressed or k.echo:
			return false
		match k.keycode:
			KEY_ENTER, KEY_KP_ENTER:
				_finish_draft()
				return true
			KEY_BACKSPACE:
				if not _draft.is_empty():
					_draft.remove_at(_draft.size() - 1)
					_redraw_draft()
					return true
			KEY_ESCAPE:
				if not _draft.is_empty():
					_draft = PackedVector2Array()
					_redraw_draft()
					_note("Draft cleared.")
					return true
				return false   ## let Esc close the panel through Player
			KEY_DELETE:
				_erase_at_aim()
				return true
			KEY_R:
				build_rot = wrapf(build_rot + (deg_to_rad(-15.0) if k.shift_pressed
					else deg_to_rad(15.0)), -PI, PI)
				_ghost_key = ""
				return true
			KEY_F:
				## F FLIPS THE MOUSE between looking and being a cursor.
				set_mouse_look(not mouse_look)
				return true
			KEY_SPACE, KEY_CTRL:
				## The camera reads these by polling. Swallow the events so the
				## parked body never banks a jump or a dash for later.
				return spectating()
			KEY_F2:
				## Drop in: body comes here, editor closes, survival resumes.
				drop_in_here()
				return true
			KEY_B:
				if k.shift_pressed:
					bring_body_here()
					return true
			KEY_H:
				grid_snap = not grid_snap
				_flag("grid", grid_snap)
				return true
			KEY_P:
				if viz != null:
					viz.visible = not viz.visible
				return true
			KEY_BRACKETLEFT:
				build_scale = maxf(0.25, build_scale - 0.1)
				_ghost_key = ""
				return true
			KEY_BRACKETRIGHT:
				build_scale = minf(6.0, build_scale + 0.1)
				_ghost_key = ""
				return true
			KEY_PAGEUP:
				build_y += 0.25
				return true
			KEY_PAGEDOWN:
				build_y -= 0.25
				return true
			KEY_S:
				if k.ctrl_pressed or k.meta_pressed:
					save_now()
					return true
		return false

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if _over_panel():
			## The GUI still gets this click (we never set_input_as_handled) --
			## we only stop the GAME from also acting on it. Without this, every
			## press of a panel button also swung the sword.
			return true
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_speed_by(SPEED_STEP)
				return true
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_speed_by(1.0 / SPEED_STEP)
				return true
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_click_world()
				else:
					_painting = false     ## the ground stroke ends with the button
				return true
			MOUSE_BUTTON_RIGHT:
				_looking = mb.pressed
				if mb.pressed and not _draft.is_empty() and tool != "select":
					pass   ## RMB is look while drafting; Enter finishes
				return true
		return false

	return false


func take_motion(event: InputEvent) -> bool:
	## Player._unhandled_input hands mouse motion here first. While the
	## spectator camera is out it turns the CAMERA, never the parked body --
	## and it returns true so Player does not also rotate itself, which would
	## leave your character spinning on the spot while you fly.
	if not spectating() or not (event is InputEventMouseMotion):
		return false
	if map_over():
		return true    ## the map has the pointer; nothing turns
	## Captured = look with the mouse. Cursor = look only while RMB is down.
	if not mouse_look and not _looking:
		return true    ## eaten anyway: a free cursor must not turn anything
	var mm := event as InputEventMouseMotion
	var sens := Player.MOUSE_SENS * (_player.set_sens if _player != null else 1.0)
	cam.look(mm.relative, sens)
	return true


func _over_panel() -> bool:
	## With the mouse captured there is no pointer to be "over" anything --
	## every click is a world click down the crosshair.
	if mouse_look:
		return false
	return visible and get_global_rect().has_point(get_viewport().get_mouse_position())


func _speed_by(f: float) -> void:
	if _player == null:
		return
	_player.god_speed = clampf(_player.god_speed * f, SPEED_MIN, SPEED_MAX)
	if absf(_player.god_speed - 1.0) < 0.06:
		_player.god_speed = 1.0    ## snap back to plain walking speed


func set_mouse_look(on: bool) -> void:
	## F. Captured = look with the mouse and aim down the crosshair; released =
	## a cursor for the panel and RMB-drag to look. Typing is dropped either
	## way -- a captured mouse and a focused text box is a trap.
	mouse_look = on
	_looking = false
	_drop_focus()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE
	_flag("mouse", on)
	_note("Mouse: %s" % ("LOOK — F for the cursor" if on else "CURSOR — F to look"))


func _drop_focus() -> void:
	typing = false
	if _note_title != null:
		_note_title.release_focus()
	if _note_body != null:
		_note_body.release_focus()
	if _sel_name != null:
		_sel_name.release_focus()


# ===========================================================================
#  Aiming
# ===========================================================================

func _update_aim() -> void:
	_aim_valid = false
	_aim_node = null
	var eye := active_cam()
	if _player == null or eye == null:
		return
	var vp := get_viewport()
	var mp := vp.get_mouse_position()
	if mouse_look or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or _looking:
		mp = vp.get_visible_rect().size * 0.5
	var from := eye.project_ray_origin(mp)
	var dir := eye.project_ray_normal(mp)

	var best := INF
	var pos := Vector3.ZERO

	## 1. real geometry (placed pieces, trees, boulders, the near-ring collider)
	var space := _player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * REACH)
	q.exclude = [_player.get_rid()]
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		best = from.distance_to(hit["position"])
		pos = hit["position"]
		_aim_node = hit.get("collider", null)

	## 2. the heightfield, marched analytically — the mid and far rings have no
	##    collision at all, and you spend most of god mode looking at them.
	var t := 0.5
	var prev := from.y - Overworld.ground_y(from)
	while t < MARCH_MAX and t < best:
		var p := from + dir * t
		var d := p.y - Overworld.ground_y(p)
		if d <= 0.0 and prev > 0.0:
			var lo := t - _march_step(t)
			var hi := t
			for _i in range(14):
				var mid := (lo + hi) * 0.5
				var pm := from + dir * mid
				if pm.y - Overworld.ground_y(pm) > 0.0:
					lo = mid
				else:
					hi = mid
			var ph := from + dir * hi
			if hi < best:
				best = hi
				pos = Vector3(ph.x, Overworld.ground_y(ph), ph.z)
				_aim_node = null
			break
		prev = d
		t += _march_step(t)

	if best < INF:
		_aim_pos = pos
		_aim_valid = true


static func _march_step(t: float) -> float:
	return clampf(t * 0.035, 0.6, 14.0)


func _snap(p: Vector3) -> Vector3:
	if not grid_snap:
		return p
	var g := BuildKit.MODULE
	return Vector3(roundf(p.x / g) * g, p.y, roundf(p.z / g) * g)


# ===========================================================================
#  The click
# ===========================================================================

func _click_world() -> void:
	_update_aim()
	if not _aim_valid:
		return
	match tool:
		"select":  _select_at_aim()
		"zone":    _zone_click()
		"path":    _path_click()
		"note":    _note_click()
		"tree":    _tree_click()
		"build":   _build_click()
		"ground":  _ground_click()
		"erase":   _erase_at_aim()


## --------------------------------------------------------------- select ---

func _select_at_aim() -> void:
	var z := WorldPlan.zone_at(_aim_pos.x, _aim_pos.z)
	if not z.is_empty():
		selected_id = str(z.get("id", ""))
		_refresh_tool_page()
		_note("Selected %s." % str(z.get("name", "")))
		return
	## nearest path within half its width
	var best := ""
	var best_d := INF
	for p in WorldPlan.paths:
		var pd: Dictionary = p
		var pts := WorldPlan.points_of(pd)
		for i in range(pts.size() - 1):
			var d := _dist_to_seg(Vector2(_aim_pos.x, _aim_pos.z), pts[i], pts[i + 1])
			if d < maxf(float(pd.get("width", 4.0)) * 0.7, 3.0) and d < best_d:
				best_d = d
				best = str(pd.get("id", ""))
	if best != "":
		selected_id = best
		_refresh_tool_page()
		return
	selected_id = ""
	_refresh_tool_page()


static func _dist_to_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## ----------------------------------------------------------------- zone ---

func _zone_click() -> void:
	if zone_mode == "circle":
		var pts := PackedVector2Array()
		var c := Vector2(_aim_pos.x, _aim_pos.z)
		var z := WorldPlan.new_zone(zone_kind, pts, "circle", circle_r)
		z["center"] = [snappedf(c.x, 0.01), snappedf(c.y, 0.01)]
		selected_id = str(z["id"])
		_after_plan_change("Zone: %s (circle, r %.0f m)" % [str(z["name"]), circle_r])
		return
	_draft.append(Vector2(_aim_pos.x, _aim_pos.z))
	_redraw_draft()


## ----------------------------------------------------------------- path ---

func _path_click() -> void:
	_draft.append(Vector2(_aim_pos.x, _aim_pos.z))
	_redraw_draft()


func _finish_draft() -> void:
	if tool == "zone" and _draft.size() >= 3:
		var z := WorldPlan.new_zone(zone_kind, _draft, "poly")
		selected_id = str(z["id"])
		_draft = PackedVector2Array()
		_after_plan_change("Zone: %s (%s)" % [str(z["name"]), WorldPlan.kind_label(z)])
	elif tool == "path" and _draft.size() >= 2:
		var p := WorldPlan.new_path(path_kind, _draft, path_width)
		selected_id = str(p["id"])
		_draft = PackedVector2Array()
		_after_plan_change("%s: %s, %.0f m" % [WorldPlan.kind_label(p), str(p["name"]),
			WorldPlan.length_of(p)])
	elif not _draft.is_empty():
		_note("Need 3 points for a zone, 2 for a path.")


func _redraw_draft() -> void:
	if viz == null:
		return
	if _draft.is_empty():
		viz.clear_draft()
		return
	var col := Color.WHITE
	var w := 0.0
	if tool == "zone":
		col = (WorldPlan.ZONE_KINDS.get(zone_kind, {"color": Color.WHITE}) as Dictionary)["color"]
	elif tool == "path":
		col = (WorldPlan.PATH_KINDS.get(path_kind, {"color": Color.WHITE}) as Dictionary)["color"]
		w = path_width
	viz.set_draft(_draft, tool == "zone", col, w)


## ----------------------------------------------------------------- note ---

func _note_click() -> void:
	_drop_note_at(_aim_pos)


func _drop_note_at(pos: Vector3) -> void:
	var title := _note_title.text.strip_edges() if _note_title != null else ""
	var body := _note_body.text.strip_edges() if _note_body != null else ""
	if title == "" and body == "":
		_note("Write the note first — the box is on the panel.")
		return
	var owner_id := ""
	if note_attach:
		var z := WorldPlan.zone_at(pos.x, pos.z)
		if not z.is_empty():
			owner_id = str(z.get("id", ""))
		elif selected_id != "":
			owner_id = selected_id
	WorldPlan.new_note(pos, title, body, note_tag, owner_id)
	if _note_title != null:
		_note_title.text = ""
	if _note_body != null:
		_note_body.text = ""
	var where := "loose"
	if owner_id != "":
		where = str(WorldPlan.find(owner_id).get("name", owner_id))
	_after_plan_change("Note filed under %s." % where)


## ---------------------------------------------------------------- trees ---

func _tree_click() -> void:
	if tree_brush <= 0.0:
		_plant(_aim_pos, tree_species, tree_stage)
		_mark_dirty()
		return
	## brush: scatter across the disc, no two trunks inside 2 m
	var n := maxi(1, int(PI * tree_brush * tree_brush * tree_density))
	var placed: Array[Vector2] = []
	var made := 0
	for _i in range(n * 3):
		if made >= n:
			break
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * tree_brush
		var p := Vector2(_aim_pos.x + cos(a) * r, _aim_pos.z + sin(a) * r)
		var clash := false
		for q in placed:
			if q.distance_to(p) < 2.1:
				clash = true
				break
		if clash:
			continue
		placed.append(p)
		var g := Overworld.ground_y(Vector3(p.x, 0, p.y))
		var stage := tree_stage
		if tree_stage < 0:
			stage = 1 if _rng.randf() < 0.42 else (2 if _rng.randf() < 0.75 else 3)
		var sp := tree_species
		if sp == "mixed":
			sp = TreeV2.ALL_SPECIES[_rng.randi() % TreeV2.ALL_SPECIES.size()]
		_plant(Vector3(p.x, g, p.y), sp, stage)
		made += 1
	_note("Planted %d." % made)
	_mark_dirty()


func _plant(pos: Vector3, sp: String, stage: int) -> TreeV2:
	if _world == null:
		return null
	var species := sp
	if species == "mixed":
		species = TreeV2.ALL_SPECIES[_rng.randi() % TreeV2.ALL_SPECIES.size()]
	var st := stage
	if st < 0:
		st = 2
	var t := TreeV2.make(_rng, species, st)
	t.position = Vector3(pos.x, Overworld.ground_y(pos), pos.z)
	t.rotation.y = _rng.randf() * TAU
	t.set_meta("built", true)
	_world.add_child(t)
	t.add_to_group("editor_placed")
	_trees.append(t)
	return t


func grow_aimed() -> void:
	## Age the tree you are looking at by one stage. TreeV2 bakes its shape at
	## build time, so growing one is really "replace it with its older self" —
	## same species, same spot, same seed, one stage up.
	_update_aim()
	var t := _find_owner(_aim_node, "trees") as TreeV2
	if t == null:
		_note("Aim at a tree.")
		return
	var next := t.stage + 1
	if next > 3:
		_note("Already ancient. (Stage 4 is withered — set it on the panel.)")
		return
	var pos := t.global_position
	var rot := t.rotation.y
	var sp := t.species
	var sd := t.tree_seed
	if _trees.has(t):
		_trees.erase(t)
	t.queue_free()
	var nt := _plant(pos, sp, next)
	if nt != null:
		nt.rotation.y = rot
		nt.tree_seed = sd
	_note("Grown to %s." % TreeV2.STAGE_NAMES[next])
	_mark_dirty()


## --------------------------------------------------------------- ground ---

func _ground_click() -> void:
	## One dab now, then _process keeps dabbing while the button is held.
	if GroundPaint.inst == null or not GroundPaint.inst.ready_ok:
		_note("Ground textures are not loaded (no atlas?).")
		return
	_painting = true
	_paint_last = Vector3(INF, INF, INF)
	_ground_dab()


func _ground_dab() -> void:
	var gp := GroundPaint.inst
	if gp == null or not _aim_valid:
		return
	## Dab again only once the aim has moved a quarter-brush (or a cell), so a
	## held button on one spot is one write, not sixty a second.
	var min_move := maxf(ground_brush * 0.25, gp.step * 0.5)
	if _paint_last.x != INF and _aim_pos.distance_to(_paint_last) < min_move:
		return
	_paint_last = _aim_pos
	var id := 0 if ground_erase else ground_id
	gp.paint_disc(_aim_pos, ground_brush, id)
	_refresh_ground_label()


func _refresh_ground_label() -> void:
	if _ground_label == null or GroundPaint.inst == null:
		return
	var gp := GroundPaint.inst
	_ground_label.text = "brush: %s  %s
%d cells painted · %s" % [
		("ERASE" if ground_erase else GroundPaint.grid_ref(ground_id)),
		("" if ground_erase else GroundPaint.tile_name(ground_id)),
		gp.painted_cells, gp.paint_path()]


## ---------------------------------------------------------------- build ---

func _build_click() -> void:
	if _world == null:
		return
	var base := _snap(_aim_pos)
	base.y = Overworld.ground_y(base) + build_y
	if build_mode == "prefab":
		var recs := BuildKit.prefab(build_prefab)
		var c := cos(build_rot)
		var s := sin(build_rot)
		for r in recs:
			var rd: Dictionary = r
			var lp: Vector3 = rd["pos"] * build_scale
			var wp := Vector3(lp.x * c - lp.z * s, lp.y, lp.x * s + lp.z * c) + base
			_place_piece(str(rd["piece"]), wp, float(rd["rot"]) + build_rot,
				str(rd["mat"]), build_scale)
		_note("%s stamped (%d pieces)."
			% [str((BuildKit.PREFABS[build_prefab] as Dictionary)["label"]), recs.size()])
	else:
		_place_piece(build_piece, base, build_rot, build_mat, build_scale)
	_mark_dirty()


func _place_piece(piece: String, pos: Vector3, rot: float, m: String, sc: float) -> void:
	var b := BuiltPiece.make(piece, m, sc)
	b.position = pos
	b.rotation.y = rot
	_world.add_child(b)
	_pieces.append(b)


## ---------------------------------------------------------------- erase ---

func _erase_at_aim() -> void:
	_update_aim()
	if not _aim_valid:
		return
	if erase_plan:
		var z := WorldPlan.zone_at(_aim_pos.x, _aim_pos.z)
		if not z.is_empty():
			var nm := str(z.get("name", ""))
			WorldPlan.remove(str(z.get("id", "")))
			if selected_id == str(z.get("id", "")):
				selected_id = ""
			_after_plan_change("Removed zone %s." % nm)
			return
		_note("Nothing planned here.")
		return
	var n := _find_owner(_aim_node, "")
	if n == null:
		_note("Nothing to remove there.")
		return
	if n is BuiltPiece:
		_pieces.erase(n)
	elif n is TreeV2:
		_trees.erase(n)
	n.queue_free()
	_mark_dirty()


func _find_owner(n: Node, group: String) -> Node:
	## Walk up from whatever the ray hit to the thing we own.
	var cur := n
	while cur != null:
		if group != "":
			if cur.is_in_group(group):
				return cur
		elif cur is BuiltPiece or cur is TreeV2:
			return cur
		cur = cur.get_parent()
	return null


# ===========================================================================
#  Ghost
# ===========================================================================

func _clear_ghost() -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	_ghost_key = ""


func _update_ghost() -> void:
	if not visible or _world == null:
		_clear_ghost()
		return
	var want := ""
	if tool == "build":
		want = "%s|%s|%s|%.2f|%.2f" % [build_mode, build_piece, build_prefab,
			build_rot, build_scale] if build_mode == "piece" \
			else "prefab|%s|%.2f|%.2f" % [build_prefab, build_rot, build_scale]
	elif tool == "tree":
		want = "tree|%s|%d|%.1f" % [tree_species, tree_stage, tree_brush]
	elif tool == "ground":
		want = "ground|%.1f|%s" % [ground_brush, "e" if ground_erase else "p"]
	elif tool == "zone" and zone_mode == "circle":
		want = "circle|%.1f|%s" % [circle_r, zone_kind]
	if want == "":
		_clear_ghost()
		return
	if want != _ghost_key:
		_clear_ghost()
		_ghost_key = want
		_ghost = _make_ghost()
		if _ghost != null:
			_world.add_child(_ghost)
	if _ghost == null or not _aim_valid:
		return
	var p := _snap(_aim_pos) if tool == "build" else _aim_pos
	p.y = Overworld.ground_y(p) + (build_y if tool == "build" else 0.0)
	_ghost.global_position = p
	_ghost.rotation.y = build_rot if tool == "build" else 0.0


func _make_ghost() -> Node3D:
	var root := Node3D.new()
	if tool == "build" and build_mode == "piece":
		var b := BuildKit.build(build_piece, build_mat)
		b.collision_layer = 0
		root.add_child(b)
		root.scale = Vector3.ONE * build_scale
	elif tool == "build":
		for r in BuildKit.prefab(build_prefab):
			var rd: Dictionary = r
			var b := BuildKit.build(str(rd["piece"]), str(rd["mat"]))
			b.collision_layer = 0
			b.position = rd["pos"]
			b.rotation.y = float(rd["rot"])
			root.add_child(b)
		root.scale = Vector3.ONE * build_scale
	elif tool == "tree":
		var r := maxf(tree_brush, 1.2)
		root.add_child(_ring(r, Color(0.4, 0.9, 0.5)))
		if tree_brush <= 0.0:
			var post := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.3, 4.0 + tree_stage * 2.0, 0.3)
			post.mesh = bm
			post.position.y = (4.0 + tree_stage * 2.0) * 0.5
			root.add_child(post)
	elif tool == "zone":
		root.add_child(_ring(circle_r,
			(WorldPlan.ZONE_KINDS.get(zone_kind, {"color": Color.WHITE}) as Dictionary)["color"]))
	elif tool == "ground":
		root.add_child(_ring(maxf(ground_brush, 1.0),
			Color(1.0, 0.45, 0.35) if ground_erase else Color(1.0, 0.85, 0.40)))
	_ghostify(root)
	return root


func _ring(r: float, col: Color) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var segs := 40
	for i in range(segs):
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var p0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
		verts.append_array([p0, p1, p1 + Vector3.UP * 1.6,
							p0, p1 + Vector3.UP * 1.6, p0 + Vector3.UP * 1.6])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, 0.30)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	mi.material_override = m
	return mi


func _ghostify(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.material_override == null:
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.55, 0.95, 1.0, 0.36)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			mi.material_override = m
	elif n is CollisionShape3D:
		(n as CollisionShape3D).disabled = true
	for c in n.get_children():
		_ghostify(c)


# ===========================================================================
#  Frame
# ===========================================================================

func _process(delta: float) -> void:
	if not visible:
		return
	if cam != null and _player != null:
		cam.speed_mult = _player.god_speed
		cam.typing = typing or map_over()   ## WASD must not fly you under the map
	_update_aim()
	_update_ghost()
	_refresh_status()
	if _painting and tool == "ground" and not map_over():
		if _over_panel():
			_paint_last = Vector3(INF, INF, INF)   ## lift the brush over the panel
		elif _aim_valid:
			_ground_dab()
	if _dirty:
		_save_t += delta
		if _save_t > 2.5:
			save_now()


func _refresh_status() -> void:
	if _player == null or _status == null:
		return
	var eye := active_cam()
	var p := eye.global_position if eye != null else _player.global_position
	var g := Overworld.ground_y(p)
	var place := ""
	var region := ""
	if Overworld.inst != null:
		place = Overworld.inst.place_name_at(p, 1200.0)
		region = Overworld.inst.region_for(p.x, p.z)
	var zone := WorldPlan.zone_at(p.x, p.z)
	var zname: String = str(zone.get("name", "—")) if not zone.is_empty() else "—"
	var mode := "SPECTATOR" if spectating() else ("FLY" if _player.flying else "WALK")
	var mouse := "LOOK" if mouse_look else "CURSOR"
	var body := ""
	if spectating() and cam != null:
		body = "  ·  body %.0f m" % cam.distance_to_body(_player)
	_status.text = "%s  ×%.2f  ·  mouse %s%s\nx %.0f  y %.0f  z %.0f\nground %.0f · %s%s\nzone: %s" % [
		mode, _player.god_speed, mouse, body, p.x, p.y, p.z, g, region,
		("" if place == "" else " · " + place), zname]
	if _hint != null:
		var aim := "—"
		if _aim_valid:
			aim = "%.0f, %.0f, %.0f" % [_aim_pos.x, _aim_pos.y, _aim_pos.z]
		var extra := ""
		if tool == "zone" and zone_mode == "poly":
			extra = "   points: %d (Enter closes)" % _draft.size()
		elif tool == "path":
			extra = "   points: %d (Enter finishes)" % _draft.size()
		elif tool == "ground" and _aim_valid and GroundPaint.inst != null:
			var worn := GroundPaint.inst.worn_id_at(_aim_pos.x, _aim_pos.z)
			extra = "   ground: %s %s" % [GroundPaint.grid_ref(worn), GroundPaint.tile_name(worn)]
		_hint.text = "aim %s%s" % [aim, extra]


func _mark_dirty() -> void:
	_dirty = true
	_save_t = 0.0


func _after_plan_change(msg: String) -> void:
	if viz != null:
		viz.clear_draft()
		viz.rebuild()
	_refresh_tool_page()
	_note(msg)
	WorldPlan.save_plan()


# ===========================================================================
#  Persistence for the STUFF (pieces + planted trees)
# ===========================================================================

func placement_path() -> String:
	return WorldPlan.dir() + PLACEMENT_FILE


func save_now() -> void:
	_dirty = false
	_save_t = 0.0
	WorldPlan.save_plan()
	if GroundPaint.inst != null:
		GroundPaint.inst.save_now()
	var pieces: Array = []
	for p in _pieces:
		if is_instance_valid(p):
			pieces.append((p as BuiltPiece).save_dict())
	var trees: Array = []
	for t in _trees:
		if is_instance_valid(t):
			trees.append((t as TreeV2).save_dict())
	var f := FileAccess.open(placement_path(), FileAccess.WRITE)
	if f == null:
		push_warning("GodEditor: could not write %s" % placement_path())
		return
	f.store_string(JSON.stringify({"format": 1, "pieces": pieces, "trees": trees}, "  "))
	f.close()


func restore_all() -> void:
	## Called at boot and after a save-game load (World.apply_state calls the
	## "builder" group), because loading a save sweeps every tree in the world.
	for n in get_tree().get_nodes_in_group("editor_placed"):
		(n as Node).queue_free()
	_pieces.clear()
	_trees.clear()
	if _world == null:
		return
	var p := placement_path()
	if not FileAccess.file_exists(p):
		return
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	for rec in d.get("pieces", []):
		var b := BuiltPiece.from_dict(rec as Dictionary)
		_world.add_child(b)
		_pieces.append(b)
	for rec in d.get("trees", []):
		var rd: Dictionary = rec
		var t := TreeV2.from_dict(rd)
		t.set_meta("built", true)
		_world.add_child(t)
		t.add_to_group("editor_placed")
		t.restore(rd)
		_trees.append(t)


# ===========================================================================
#  UI
# ===========================================================================

func _build_ui() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.09, 0.93)
	sb.border_color = Color(0.34, 0.62, 0.72, 0.85)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	add_theme_stylebox_override("panel", sb)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)

	var title := Label.new()
	title.text = "GOD MODE"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.62, 0.92, 1.0))
	outer.add_child(title)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Color(0.80, 0.86, 0.90))
	outer.add_child(_status)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(0.58, 0.64, 0.68))
	outer.add_child(_hint)

	## --- flags row ---------------------------------------------------------
	var flags := HBoxContainer.new()
	flags.add_theme_constant_override("separation", 4)
	outer.add_child(flags)
	_flag_btn(flags, "god", "GOD", func(): _toggle_god_sticky())
	_flag_btn(flags, "mouse", "LOOK", func(): set_mouse_look(not mouse_look))
	_flag_btn(flags, "grid", "GRID", func():
		grid_snap = not grid_snap
		_flag("grid", grid_snap))
	_flag_btn(flags, "plan", "PLAN", func():
		if viz != null:
			viz.visible = not viz.visible
			_flag("plan", viz.visible))
	var save_b := Button.new()
	save_b.text = "SAVE"
	save_b.add_theme_font_size_override("font_size", 12)
	save_b.pressed.connect(func():
		save_now()
		_note("Plan written to %s" % WorldPlan.dir()))
	flags.add_child(save_b)
	_flag("grid", grid_snap)

	## --- the body ----------------------------------------------------------
	var bodyrow := HBoxContainer.new()
	bodyrow.add_theme_constant_override("separation", 4)
	outer.add_child(bodyrow)
	var back_b := Button.new()
	back_b.text = "Return to body (F1)"
	back_b.add_theme_font_size_override("font_size", 12)
	back_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_b.pressed.connect(func():
		if _player != null:
			_player._toggle_menu("god"))
	bodyrow.add_child(back_b)
	var bring_b := Button.new()
	bring_b.text = "Bring body here"
	bring_b.add_theme_font_size_override("font_size", 12)
	bring_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bring_b.pressed.connect(func(): bring_body_here())
	bodyrow.add_child(bring_b)
	var drop_b := Button.new()
	drop_b.text = "Drop in (F2)"
	drop_b.tooltip_text = ("Bring the body here AND land in it -- editor closes, "
		+ "survival resumes. The fall down is free.")
	drop_b.add_theme_font_size_override("font_size", 12)
	drop_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drop_b.pressed.connect(func(): drop_in_here())
	bodyrow.add_child(drop_b)

	outer.add_child(_sep())

	## --- tool row ----------------------------------------------------------
	var tools := GridContainer.new()
	tools.columns = 4
	tools.add_theme_constant_override("h_separation", 4)
	tools.add_theme_constant_override("v_separation", 4)
	outer.add_child(tools)
	for t in [["select", "Select"], ["zone", "Zone"], ["path", "Path"], ["note", "Note"],
			["tree", "Trees"], ["build", "Build"], ["ground", "Ground"], ["erase", "Erase"]]:
		var b := Button.new()
		b.text = t[1]
		b.add_theme_font_size_override("font_size", 13)
		b.custom_minimum_size = Vector2(78, 26)
		var id: String = t[0]
		b.pressed.connect(func(): _set_tool(id))
		tools.add_child(b)
		_tool_btns[id] = b

	outer.add_child(_sep())

	## --- the tool's own controls -------------------------------------------
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 5)
	scroll.add_child(_body)
	_tool_box = _body


func _sep() -> Control:
	var s := ColorRect.new()
	s.color = Color(0.3, 0.4, 0.45, 0.5)
	s.custom_minimum_size = Vector2(0, 1)
	return s


func _flag_btn(parent: Node, id: String, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(cb)
	parent.add_child(b)
	_flag_btns[id] = b


func _flag(id: String, on: bool) -> void:
	if not _flag_btns.has(id):
		return
	var b: Button = _flag_btns[id]
	b.add_theme_color_override("font_color",
		Color(0.45, 1.0, 0.6) if on else Color(0.55, 0.58, 0.60))


func _toggle_god_sticky() -> void:
	## STICKY GOD. Spectator mode is always invulnerable -- there is no body to
	## hit. This is about the body you go back to: on, and your character keeps
	## the invulnerability and the double-tap-Space flight after you close the
	## panel. Off (the default) and closing the editor returns you to an
	## ordinary mortal character.
	if _player == null:
		return
	_player.god_sticky = not _player.god_sticky
	_player.god = _player.editing or _player.god_sticky
	if not _player.god:
		_player.flying = false
	_flag("god", _player.god_sticky)
	_note("Character god mode %s." % ("on" if _player.god_sticky else "off"))


func _set_tool(t: String) -> void:
	tool = t
	_painting = false
	_confirm = ""
	_draft = PackedVector2Array()
	if viz != null:
		viz.clear_draft()
	_clear_ghost()
	_refresh_tool_page()


# --- small builders ---------------------------------------------------------

func _head(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.55, 0.80, 0.90))
	_body.add_child(l)


func _para(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(PANEL_W - 40, 0)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.62, 0.66, 0.70))
	_body.add_child(l)


func _grid(cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 3)
	g.add_theme_constant_override("v_separation", 3)
	_body.add_child(g)
	return g


func _chip(parent: Node, text: String, on: bool, cb: Callable, col := Color.TRANSPARENT) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 12)
	b.custom_minimum_size = Vector2(0, 24)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if on:
		b.add_theme_color_override("font_color", Color(0.45, 1.0, 0.6))
	elif col != Color.TRANSPARENT:
		b.add_theme_color_override("font_color", col.lightened(0.25))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _slider(label_text: String, v: float, lo: float, hi: float, step: float,
		cb: Callable) -> void:
	var l := Label.new()
	l.text = label_text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.70, 0.74, 0.78))
	_body.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = v
	s.custom_minimum_size = Vector2(PANEL_W - 44, 18)
	s.value_changed.connect(func(nv):
		cb.call(nv)
		l.text = label_text.split(":")[0] + ": %.1f" % nv)
	_body.add_child(s)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(cb)
	_body.add_child(b)
	return b


func _track_focus(c: Control) -> void:
	c.focus_entered.connect(func(): typing = true)
	c.focus_exited.connect(func(): typing = false)


# --- the pages --------------------------------------------------------------

func _refresh_tool_page() -> void:
	if _body == null:
		return
	for c in _body.get_children():
		c.queue_free()
	_note_title = null
	_note_body = null
	_sel_name = null
	_ground_label = null
	_ground_hover = null
	for id in _tool_btns:
		(_tool_btns[id] as Button).add_theme_color_override("font_color",
			Color(0.45, 1.0, 0.6) if id == tool else Color(0.78, 0.80, 0.82))
	match tool:
		"select": _page_select()
		"zone":   _page_zone()
		"path":   _page_path()
		"note":   _page_note()
		"tree":   _page_tree()
		"build":  _page_build()
		"ground": _page_ground()
		"erase":  _page_erase()


func _page_select() -> void:
	_para("Click a zone or a road to select it. Everything you change here is "
		+ "written to %s." % WorldPlan.dir())
	var rec := WorldPlan.find(selected_id)
	if rec.is_empty():
		_head("NOTHING SELECTED")
		_head("PLAN CONTENTS")
		_para("%d zones · %d paths · %d notes" % [WorldPlan.zones.size(),
			WorldPlan.paths.size(), WorldPlan.notes.size()])
		var g := _grid(1)
		for z in WorldPlan.zones:
			var zd: Dictionary = z
			var id := str(zd.get("id", ""))
			_chip(g, "%s — %s" % [str(zd.get("name", "")), WorldPlan.kind_label(zd)],
				false, func():
					selected_id = id
					_refresh_tool_page(), WorldPlan.kind_color(zd))
		for p in WorldPlan.paths:
			var pd: Dictionary = p
			var pid := str(pd.get("id", ""))
			_chip(g, "%s — %s" % [str(pd.get("name", "")), WorldPlan.kind_label(pd)],
				false, func():
					selected_id = pid
					_refresh_tool_page(), WorldPlan.kind_color(pd))
		return

	_head(str(rec.get("id", "")).to_upper())
	_sel_name = LineEdit.new()
	_sel_name.text = str(rec.get("name", ""))
	_sel_name.placeholder_text = "name"
	_track_focus(_sel_name)
	_sel_name.text_submitted.connect(func(t):
		rec["name"] = t
		_drop_focus()
		_after_plan_change("Renamed."))
	_body.add_child(_sel_name)

	var c := WorldPlan.center_of(rec)
	var info := "%s · %s\ncentre (%.0f, %.0f)" % [WorldPlan.kind_label(rec),
		str(rec.get("status", "")), c.x, c.y]
	if rec.has("radius") and float(rec.get("radius", 0.0)) > 0.0:
		info += "\nradius %.0f m · area %.0f m²" % [float(rec["radius"]), WorldPlan.area_of(rec)]
	elif WorldPlan.zones.has(rec):
		info += "\narea %.0f m²" % WorldPlan.area_of(rec)
	else:
		info += "\nlength %.0f m · width %.1f m" % [WorldPlan.length_of(rec),
			float(rec.get("width", 4.0))]
	_para(info)

	_head("STATUS")
	var gs := _grid(4)
	for s in WorldPlan.STATUSES:
		var sv: String = s
		_chip(gs, sv, str(rec.get("status", "")) == sv, func():
			rec["status"] = sv
			_after_plan_change("%s → %s" % [str(rec.get("name", "")), sv]))
	_head("PRIORITY")
	var gp := _grid(4)
	for pr in WorldPlan.PRIORITIES:
		var pv: String = pr
		_chip(gp, pv, str(rec.get("priority", "")) == pv, func():
			rec["priority"] = pv
			_after_plan_change("priority %s" % pv))

	if rec.has("radius") and str(rec.get("shape", "")) == "circle":
		_slider("radius: %.1f" % float(rec["radius"]), float(rec["radius"]), 4.0, 400.0, 1.0,
			func(v):
				rec["radius"] = v
				if viz != null:
					viz.rebuild())
	if WorldPlan.paths.has(rec):
		_slider("width: %.1f" % float(rec.get("width", 4.0)), float(rec.get("width", 4.0)),
			0.5, 24.0, 0.5, func(v):
				rec["width"] = v
				if viz != null:
					viz.rebuild())

	var mine := WorldPlan.notes_for(str(rec.get("id", "")))
	_head("NOTES (%d)" % mine.size())
	for n in mine:
		var nd: Dictionary = n
		var l := Label.new()
		l.text = "• [%s] %s" % [str(nd.get("tag", "")), str(nd.get("title", ""))]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(PANEL_W - 40, 0)
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color",
			WorldPlan.NOTE_TAG_COLOR.get(str(nd.get("tag", "todo")), Color.WHITE))
		_body.add_child(l)

	_button("Teleport here", func():
		if _player != null:
			var g := Overworld.ground_y(Vector3(c.x, 0, c.y))
			if Overworld.inst != null:
				Overworld.inst.warm(Vector3(c.x, g, c.y))
			_player.global_position = Vector3(c.x, g + 2.0, c.y))
	_button("Delete", func():
		var nm := str(rec.get("name", ""))
		WorldPlan.remove(str(rec.get("id", "")))
		selected_id = ""
		_after_plan_change("Deleted %s." % nm))


func _page_zone() -> void:
	_para("Polygon: click each corner on the ground, ENTER closes it. "
		+ "BACKSPACE takes back a corner. Circle: one click drops it.")
	var gm := _grid(2)
	_chip(gm, "Polygon", zone_mode == "poly", func():
		zone_mode = "poly"
		_refresh_tool_page())
	_chip(gm, "Circle", zone_mode == "circle", func():
		zone_mode = "circle"
		_refresh_tool_page())
	if zone_mode == "circle":
		_slider("radius: %.0f" % circle_r, circle_r, 4.0, 400.0, 1.0, func(v): circle_r = v)
	var cats := {}
	for k in WorldPlan.ZONE_KINDS:
		var cat := str((WorldPlan.ZONE_KINDS[k] as Dictionary)["cat"])
		if not cats.has(cat):
			cats[cat] = []
		(cats[cat] as Array).append(k)
	for cat in cats:
		_head(str(cat).to_upper())
		var g := _grid(2)
		for k in cats[cat]:
			var kv: String = k
			var d: Dictionary = WorldPlan.ZONE_KINDS[kv]
			_chip(g, str(d["label"]), zone_kind == kv, func():
				zone_kind = kv
				_refresh_tool_page(), d["color"])


func _page_path() -> void:
	_para("Roads and trails. Click along the route, ENTER finishes it. "
		+ "BACKSPACE takes back a point. Follow the valleys — the ribbon "
		+ "drapes onto the ground so you can see the grade you picked.")
	_head("KIND")
	var g := _grid(2)
	for k in WorldPlan.PATH_KINDS:
		var kv: String = k
		var d: Dictionary = WorldPlan.PATH_KINDS[kv]
		_chip(g, str(d["label"]), path_kind == kv, func():
			path_kind = kv
			path_width = float(d["width"])
			_refresh_tool_page(), d["color"])
	_slider("width: %.1f m" % path_width, path_width, 0.5, 24.0, 0.5, func(v):
		path_width = v
		_redraw_draft())


func _page_note() -> void:
	_para("Write it, then click the spot. The pin stands where you clicked and "
		+ "files itself under whatever zone it lands in — that is the sectioning. "
		+ "Claude reads design/WORLD_PLAN.md.")
	_note_title = LineEdit.new()
	_note_title.placeholder_text = "title — one line"
	_track_focus(_note_title)
	_body.add_child(_note_title)
	_note_body = TextEdit.new()
	_note_body.placeholder_text = "what you want done here"
	_note_body.custom_minimum_size = Vector2(PANEL_W - 44, 96)
	_note_body.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_track_focus(_note_body)
	_body.add_child(_note_body)
	_head("TAG")
	var g := _grid(3)
	for t in WorldPlan.NOTE_TAGS:
		var tv: String = t
		_chip(g, tv, note_tag == tv, func():
			note_tag = tv
			_refresh_tool_page(), WorldPlan.NOTE_TAG_COLOR.get(tv, Color.WHITE))
	var ga := _grid(1)
	_chip(ga, "file under the zone it lands in: %s" % ("yes" if note_attach else "no"),
		note_attach, func():
			note_attach = not note_attach
			_refresh_tool_page())
	_button("Pin at my feet", func():
		if _player != null:
			_drop_note_at(_player.global_position))
	_head("OPEN NOTES")
	var open_n := 0
	for n in WorldPlan.notes:
		if str((n as Dictionary).get("tag", "")) != "done":
			open_n += 1
	_para("%d open, %d total. Saved to %s" % [open_n, WorldPlan.notes.size(), WorldPlan.dir()])


func _page_tree() -> void:
	_para("Plant one, or scatter a stand. A tree you plant here is a real "
		+ "TreeV2 — choppable, seasonal, and it survives a new run.")
	_head("SPECIES")
	var g := _grid(3)
	for s in (TreeV2.ALL_SPECIES + ["mixed"]):
		var sv: String = s
		_chip(g, sv, tree_species == sv, func():
			tree_species = sv
			_refresh_tool_page())
	_head("STAGE")
	var g2 := _grid(3)
	for i in range(TreeV2.STAGE_NAMES.size()):
		var iv := i
		_chip(g2, TreeV2.STAGE_NAMES[i], tree_stage == iv, func():
			tree_stage = iv
			_refresh_tool_page())
	_chip(_grid(1), "random age", tree_stage == -1, func():
		tree_stage = -1
		_refresh_tool_page())
	_slider("brush radius: %.0f m (0 = one tree)" % tree_brush, tree_brush, 0.0, 90.0, 1.0,
		func(v): tree_brush = v)
	_slider("density: %.3f /m²" % tree_density, tree_density, 0.002, 0.09, 0.002,
		func(v): tree_density = v)
	_button("Grow the tree I'm aiming at", func(): grow_aimed())
	_button("Clear my planted trees", func():
		for t in _trees:
			if is_instance_valid(t):
				(t as Node).queue_free()
		_trees.clear()
		_mark_dirty()
		_note("Planted trees cleared."))


func _page_build() -> void:
	_para("R rotates 15° (Shift+R back), [ ] scales, PgUp/PgDn nudges height, "
		+ "H toggles grid snap. A prefab is just its pieces — stamp one, then "
		+ "swap a wall for a window.")
	var gm := _grid(2)
	_chip(gm, "Pieces", build_mode == "piece", func():
		build_mode = "piece"
		_refresh_tool_page())
	_chip(gm, "Prefabs", build_mode == "prefab", func():
		build_mode = "prefab"
		_refresh_tool_page())
	_para("rot %.0f° · scale %.2f · y %+.2f · snap %s"
		% [rad_to_deg(build_rot), build_scale, build_y, "on" if grid_snap else "off"])
	if build_mode == "prefab":
		for cat in BuildKit.prefab_categories():
			_head(str(cat).to_upper())
			var g := _grid(2)
			for id in BuildKit.prefabs_in(cat):
				var iv: String = id
				_chip(g, str((BuildKit.PREFABS[iv] as Dictionary)["label"]),
					build_prefab == iv, func():
						build_prefab = iv
						_ghost_key = ""
						_refresh_tool_page())
		return
	_head("MATERIAL")
	var gmat := _grid(3)
	_chip(gmat, "default", build_mat == "", func():
		build_mat = ""
		_ghost_key = ""
		_refresh_tool_page())
	for m in BuildKit.MATS:
		var mv: String = m
		_chip(gmat, str((BuildKit.MATS[mv] as Dictionary)["label"]), build_mat == mv, func():
			build_mat = mv
			_ghost_key = ""
			_refresh_tool_page())
	for cat in BuildKit.categories():
		_head(str(cat).to_upper())
		var g := _grid(2)
		for id in BuildKit.pieces_in(cat):
			var iv: String = id
			_chip(g, BuildKit.label_of(iv), build_piece == iv, func():
				build_piece = iv
				_ghost_key = ""
				_refresh_tool_page())


func _page_ground() -> void:
	var gp := GroundPaint.inst
	if gp == null or not gp.ready_ok:
		_para(("Ground textures are not loaded. The atlas lives at %s and the "
			+ "class map at %s — run tools/groundsheet.py and tools/groundclass.py.") % [
			GroundPaint.ATLAS_FILE, GroundPaint.BASE_FILE])
		return
	_para("Paint the ground. Pick a tile below, hold LEFT MOUSE and drag across "
		+ "the terrain. Cells are 4 m; edges blend. Erase puts a cell back to the "
		+ "world style. Saved to design/ground_paint.dat 2.5 s after you stop.")

	_head("WORLD STYLE — every unpainted cell wears this row")
	var opt := OptionButton.new()
	opt.add_theme_font_size_override("font_size", 12)
	opt.add_item("bake tint only (textures off)", 0)
	for i in range(GroundPaint.STYLES.size()):
		opt.add_item("%d  %s — %s" % [i + 1, GroundPaint.STYLES[i][1], GroundPaint.STYLES[i][2]], i + 1)
	opt.select(gp.style_row + 1)
	opt.item_selected.connect(func(idx: int):
		gp.set_style_row(idx - 1)
		_note("World style: %s" % ("tint only" if idx == 0 else GroundPaint.STYLES[idx - 1][1])))
	_body.add_child(opt)
	_slider("texture scale: %.2f m per repeat" % gp.tile_m, gp.tile_m, 0.5, 12.0, 0.25,
		func(v): gp.set_tile_m(v))

	_head("BRUSH")
	var gm := _grid(2)
	_chip(gm, "Paint", not ground_erase, func():
		ground_erase = false
		_ghost_key = ""
		_refresh_tool_page())
	_chip(gm, "Erase", ground_erase, func():
		ground_erase = true
		_ghost_key = ""
		_refresh_tool_page())
	_slider("radius: %.0f m" % ground_brush, ground_brush, 2.0, 160.0, 1.0, func(v):
		ground_brush = v
		_ghost_key = "")

	_head("TILE — row is the style, column is the ground")
	_ground_hover = Label.new()
	_ground_hover.add_theme_font_size_override("font_size", 11)
	_ground_hover.add_theme_color_override("font_color", Color(0.75, 0.80, 0.84))
	_ground_hover.text = "hover a tile"
	_body.add_child(_ground_hover)
	var pal := GridContainer.new()
	pal.columns = GroundPaint.N_COLS + 1
	pal.add_theme_constant_override("h_separation", 2)
	pal.add_theme_constant_override("v_separation", 2)
	_body.add_child(pal)
	var corner := Label.new()
	corner.custom_minimum_size = Vector2(16, 14)
	pal.add_child(corner)
	for c in range(GroundPaint.N_COLS):
		var l := Label.new()
		l.text = char(65 + c)
		l.add_theme_font_size_override("font_size", 10)
		l.add_theme_color_override("font_color", Color(0.55, 0.62, 0.66))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(24, 14)
		l.tooltip_text = GroundPaint.GROUNDS[c][1]
		pal.add_child(l)
	for r in range(GroundPaint.N_ROWS):
		var rl := Label.new()
		rl.text = str(r + 1)
		rl.add_theme_font_size_override("font_size", 10)
		rl.add_theme_color_override("font_color", Color(0.55, 0.62, 0.66))
		rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rl.custom_minimum_size = Vector2(16, 24)
		rl.tooltip_text = GroundPaint.STYLES[r][1]
		pal.add_child(rl)
		for c in range(GroundPaint.N_COLS):
			var id := GroundPaint.tile_id(r, c)
			var b := TextureButton.new()
			b.texture_normal = gp.thumb(id)
			b.ignore_texture_size = true
			b.stretch_mode = TextureButton.STRETCH_SCALE
			b.custom_minimum_size = Vector2(24, 24)
			b.modulate = Color(1, 1, 1) if id == ground_id else Color(0.62, 0.62, 0.62)
			b.tooltip_text = "%s  %s" % [GroundPaint.grid_ref(id), GroundPaint.tile_name(id)]
			b.mouse_entered.connect(func():
				if _ground_hover != null:
					_ground_hover.text = "%s  %s" % [GroundPaint.grid_ref(id), GroundPaint.tile_name(id)])
			b.pressed.connect(func():
				ground_id = id
				ground_erase = false
				_ghost_key = ""
				_refresh_tool_page())
			pal.add_child(b)

	_ground_label = Label.new()
	_ground_label.add_theme_font_size_override("font_size", 12)
	_ground_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ground_label.custom_minimum_size = Vector2(PANEL_W - 40, 0)
	_ground_label.add_theme_color_override("font_color", Color(0.45, 1.0, 0.6))
	_body.add_child(_ground_label)
	_refresh_ground_label()

	_head("WHOLE WORLD")
	_button("Fill every dry cell with this tile" if _confirm != "fill"
			else "Really fill the whole world? Click again", func():
		if _confirm == "fill":
			_confirm = ""
			gp.fill_all(ground_id)
			_note("World filled with %s." % GroundPaint.grid_ref(ground_id))
		else:
			_confirm = "fill"
		_refresh_tool_page())
	_button("Clear all paint" if _confirm != "clear"
			else "Really clear every painted cell? Click again", func():
		if _confirm == "clear":
			_confirm = ""
			gp.clear_all()
			_note("Ground paint cleared.")
		else:
			_confirm = "clear"
		_refresh_tool_page())
	_button("Save ground now", func():
		gp.save_now()
		_note("Ground written to %s" % gp.paint_path()))


func _page_erase() -> void:
	_para("Click to remove. DELETE does the same thing without moving the mouse.")
	var g := _grid(2)
	_chip(g, "Objects", not erase_plan, func():
		erase_plan = false
		_refresh_tool_page())
	_chip(g, "Plan marks", erase_plan, func():
		erase_plan = true
		_refresh_tool_page())
	if erase_plan:
		_para("Removes the smallest zone under the cursor, and its notes with it.")
	else:
		_para("Removes a built piece or a tree you planted. World trees the "
			+ "terrain scattered are not the editor's to delete — chop those.")
