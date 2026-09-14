class_name CharacterCreator
extends PanelContainer
## ===========================================================================
## THE CHARACTER CREATOR — the dev toolkit's front door.
##
## Lemon (2026-09-14): "a character creator that we can use to make npc's ...
## full in game screen with the entire setting menu in the menu for the dev
## toolkit and can click on any character which will outline them with white
## for selection".
##
## So: a full-height card docked to the RIGHT of the screen (the world stays
## visible on the left so you can click in it), opened from Settings ->
## Dev Toolkit -> Character Creator (Player._toggle_menu("creator")), with:
##
##   * SELECTION: while the card is up, the cursor is loose and a left click
##     in the world raycasts through the camera; a creature under it (its
##     body, or one of its ragdoll bones) is OUTLINED IN WHITE (an inverted
##     hull on its own PSX skin — shaders/psx_outline.gdshader, through
##     CreatureSkin.set_outline) and becomes the thing the tabs edit. The
##     thing under the cursor shows a fainter rim as you hover.
##   * PERSON tabs — Body / Face / Clothes / Mind: every knob of NPC.look
##     (build sliders, colour pickers, hair, beard, hat, job, name,
##     personality, courage). Edits rebuild the body LIVE (NPC.rebuild_body,
##     debounced) and go into the NPCDirector's record with the next
##     unstage / save. NEW PERSON drops a fresh villager ~3 m ahead and
##     selects it; RANDOM rerolls the look; SAVE PRESET / the preset list
##     write and read design/characters/*.json.
##   * MONSTERS tab — the Monster Lab: the zone key and level tier you stand
##     in, the roster MonsterGen rolls for it, a description of each, ROLL a
##     fresh species, SPAWN one or a pack ahead, SAVE a species to
##     design/monsters/*.json and spawn saved ones. Click a monster in the
##     world and its genome shows here.
##   * SETTINGS tab — the ENTIRE Settings (Esc) menu, reparented into this
##     card while it is open and handed back when it closes, so the dev
##     toolkit is one screen.
##
## Player owns the menu string ("creator") and the click: it hands mouse
## events here through `eat_input` only while menu_open == "creator". THIS
## FILE TAKES NO KEY and registers no action.
## ===========================================================================

const CARD_W := 500.0
const MARGIN := 12.0
const MENU_SCALE := 1.67            ## the other menus render 67% larger (Player.MENU_SCALE)
const MAX_SHARE := 0.62             ## the card never covers more than this of the screen width
const REBUILD_DELAY := 0.12
const PRESET_DIR := "res://design/characters"
const MONSTER_DIR := "res://design/monsters"
const PICK_MASK := 2 | (1 << 7)            ## creatures (2) + ragdoll bones (layer 8)
const OUTLINE_SELECTED := Color(1.0, 1.0, 1.0)
const OUTLINE_HOVER := Color(0.75, 0.75, 0.72)
const HAIR_STYLES := ["short", "long", "bald", "bun", "mohawk"]
const BEARDS := ["none", "stubble", "full", "braided"]
const HATS := ["job", "none", "cap", "hood", "helm", "brim"]
const PERSONALITIES := ["friendly", "gruff", "wary", "cheerful", "dour"]

var player: Node = null
var selected: Node3D = null
var hovered: Node3D = null
var species: Dictionary = {}      ## the Monster Lab's current genome

var _tabs: TabContainer
var _title: Label
var _sel_label: Label
var _status: Label
var _sliders: Dictionary = {}     ## key -> HSlider
var _vals: Dictionary = {}        ## key -> Label
var _pickers: Dictionary = {}     ## key -> ColorPickerButton
var _opts: Dictionary = {}        ## key -> [[value, Button]...]
var _name_edit: LineEdit
var _preset_list: VBoxContainer
var _preset_name: LineEdit
var _roster_box: VBoxContainer
var _species_label: Label
var _zone_label: Label
var _saved_box: VBoxContainer
var _settings_host: VBoxContainer
var _settings_content: Control = null   ## the Settings menu's own margin, borrowed
var _settings_home: Node = null
var _syncing := false
var _rebuild_t := -1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _panel_style())
	_rng.randomize()
	_build()
	visibility_changed.connect(_on_visibility)


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.07, 0.94)
	sb.border_color = Color(0.878, 0.843, 0.749, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(MARGIN)
	return sb


## ================================================================ layout ==

func _build() -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	_title = Label.new()
	_title.text = "Character Creator"
	_title.add_theme_font_size_override("font_size", 22)
	vb.add_child(_title)
	_sel_label = Label.new()
	_sel_label.text = "Click a character in the world to select it."
	_sel_label.add_theme_font_size_override("font_size", 13)
	_sel_label.modulate = Color(1, 1, 1, 0.7)
	_sel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_sel_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	vb.add_child(row)
	row.add_child(_button("New person", _new_person, "Drop a fresh villager ~3 m ahead and select it"))
	row.add_child(_button("Random look", _randomize_look, "Reroll every knob of the selected person"))
	row.add_child(_button("Delete", _delete_selected, "Remove the selected person from the world"))
	row.add_child(_button("Deselect", _deselect))
	vb.add_child(HSeparator.new())

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 13)
	vb.add_child(_tabs)
	_tabs.add_child(_wrap("Body", _build_body_tab()))
	_tabs.add_child(_wrap("Face", _build_face_tab()))
	_tabs.add_child(_wrap("Clothes", _build_clothes_tab()))
	_tabs.add_child(_wrap("Mind", _build_mind_tab()))
	_tabs.add_child(_wrap("Presets", _build_presets_tab()))
	_tabs.add_child(_wrap("Monsters", _build_monsters_tab()))
	_tabs.add_child(_wrap("Settings", _build_settings_tab()))
	_tabs.tab_changed.connect(_on_tab)

	_status = Label.new()
	_status.text = "Esc closes.  Left click in the world selects.  Edits apply live."
	_status.add_theme_font_size_override("font_size", 12)
	_status.modulate = Color(1, 1, 1, 0.55)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_status)


func _wrap(title: String, content: Control) -> Control:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(content)
	return sc


func _column() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	return v


func _note(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.modulate = Color(1, 1, 1, 0.55)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)


func _button(text: String, fn: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(fn)
	return b


func _slider_row(parent: Node, key: String, label: String, lo: float, hi: float, step: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(110, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = 1.0
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(_on_slider.bind(key))
	row.add_child(s)
	var v := Label.new()
	v.text = "1.00"
	v.custom_minimum_size = Vector2(46, 0)
	row.add_child(v)
	_sliders[key] = s
	_vals[key] = v


func _colour_row(parent: Node, key: String, label: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(110, 0)
	row.add_child(l)
	var p := ColorPickerButton.new()
	p.custom_minimum_size = Vector2(120, 26)
	p.edit_alpha = false
	p.focus_mode = Control.FOCUS_NONE
	p.color_changed.connect(_on_colour.bind(key))
	row.add_child(p)
	_pickers[key] = p


func _option_row(parent: Node, key: String, label: String, options: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(110, 0)
	row.add_child(l)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(flow)
	var btns: Array = []
	for o in options:
		var b := Button.new()
		b.text = String(o).capitalize()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(_on_option.bind(key, o))
		flow.add_child(b)
		btns.append([o, b])
	_opts[key] = btns


func _build_body_tab() -> Control:
	var v := _column()
	_note(v, "The build. Height and bulk scale the whole rig; limbs and head are relative.")
	_slider_row(v, "height", "Height", 0.80, 1.25, 0.01)
	_slider_row(v, "bulk", "Bulk", 0.75, 1.35, 0.01)
	_slider_row(v, "limb", "Limb length", 0.85, 1.15, 0.01)
	_slider_row(v, "head", "Head size", 0.85, 1.20, 0.01)
	_option_row(v, "sex", "Frame", ["m", "f"])
	return v


func _build_face_tab() -> Control:
	var v := _column()
	_colour_row(v, "skin", "Skin")
	_colour_row(v, "hair_col", "Hair colour")
	_colour_row(v, "eye_col", "Eyes")
	_option_row(v, "hair", "Hair", HAIR_STYLES)
	_option_row(v, "beard", "Beard", BEARDS)
	return v


func _build_clothes_tab() -> Control:
	var v := _column()
	_colour_row(v, "tunic", "Tunic")
	_colour_row(v, "breeches", "Breeches")
	_option_row(v, "hat", "Hat", HATS)
	_option_row(v, "job", "Job", NPCDirector.JOBS)
	_note(v, "The job picks the default hat and cloth, the tools it works with and its day. \"Job\" hat = whatever the job wears.")
	return v


func _build_mind_tab() -> Control:
	var v := _column()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	var l := Label.new()
	l.text = "Name"
	l.custom_minimum_size = Vector2(110, 0)
	row.add_child(l)
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_submitted.connect(_on_name)
	_name_edit.focus_exited.connect(func() -> void: _on_name(_name_edit.text))
	row.add_child(_name_edit)
	row.add_child(_button("Roll", _roll_name, "A Maine name for the frame"))
	_option_row(v, "personality", "Personality", PERSONALITIES)
	_slider_row(v, "courage", "Courage", 0.0, 1.0, 0.05)
	_note(v, "Courage: 0 runs from a raised voice, 1 fights back. Personality picks the barks and how an insult lands.")
	return v


func _build_presets_tab() -> Control:
	var v := _column()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	_preset_name = LineEdit.new()
	_preset_name.placeholder_text = "preset name"
	_preset_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_preset_name)
	row.add_child(_button("Save preset", _save_preset, "Write the selected person's look + job to design/characters/"))
	_note(v, "Presets are a look, a job and a personality — not a person. Load one onto the selected person, or spawn a new one wearing it.")
	_preset_list = VBoxContainer.new()
	_preset_list.add_theme_constant_override("separation", 4)
	v.add_child(_preset_list)
	return v


func _build_monsters_tab() -> Control:
	var v := _column()
	_zone_label = Label.new()
	_zone_label.add_theme_font_size_override("font_size", 13)
	_zone_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_zone_label)
	_note(v, "The roster: what MonsterGen rolls for the zone you stand in, at your level tier. Natives were here at level 1; each tier adds a newcomer and hardens the lot.")
	_roster_box = VBoxContainer.new()
	_roster_box.add_theme_constant_override("separation", 4)
	v.add_child(_roster_box)
	v.add_child(HSeparator.new())
	_species_label = Label.new()
	_species_label.text = "No species picked."
	_species_label.add_theme_font_size_override("font_size", 13)
	_species_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_species_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	row.add_child(_button("Roll fresh", _roll_species, "A brand-new species at this tier, not on any roster"))
	row.add_child(_button("Spawn one", _spawn_species.bind(false), "~4 m ahead"))
	row.add_child(_button("Spawn pack", _spawn_species.bind(true), "The species' pack size, ~4 m ahead"))
	row.add_child(_button("Save species", _save_species, "Write the genome to design/monsters/"))
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	v.add_child(row2)
	row2.add_child(_button("Reroll body", _reroll_part.bind("body"), "Same abilities, new body"))
	row2.add_child(_button("Reroll abilities", _reroll_part.bind("abilities"), "Same body, new kit"))
	row2.add_child(_button("Reroll colours", _reroll_part.bind("colours")))
	row2.add_child(_button("Refresh roster", _refresh_roster))
	v.add_child(HSeparator.new())
	_note(v, "Saved species (design/monsters/):")
	_saved_box = VBoxContainer.new()
	_saved_box.add_theme_constant_override("separation", 4)
	v.add_child(_saved_box)
	return v


func _build_settings_tab() -> Control:
	_settings_host = _column()
	_note(_settings_host, "The whole Settings menu lives here while the toolkit is open.")
	return _settings_host


## ============================================================ open/close ==

func _on_visibility() -> void:
	if visible:
		opened()
	else:
		closed()


func opened() -> void:
	_syncing = true
	_borrow_settings()
	_refresh_roster()
	_load_presets()
	_load_saved_species()
	_sync_from_selected()
	_syncing = false
	_dock()


func closed() -> void:
	_return_settings()
	_set_hover(null)
	if selected != null and is_instance_valid(selected):
		var sk := CreatureSkin.of(selected)
		if sk != null:
			sk.set_outline(false)
	_flush_rebuild()


func _dock() -> void:
	## Full height, docked right, scaled like every other menu (the game
	## renders at 2x on the Pro, so an unscaled card is a sliver); the world
	## stays on the left for clicking. On the Settings tab the card widens to
	## the Settings menu's own width so nothing is cut off.
	var vp := get_viewport_rect().size
	var want_w := CARD_W
	if _settings_content != null and _tabs != null and _tabs.get_current_tab_control() != null \
			and _tabs.get_current_tab_control().name == "Settings":
		want_w = maxf(CARD_W, _settings_content.get_combined_minimum_size().x + 2.0 * MARGIN + 24.0)
	var s := clampf(minf(MENU_SCALE, vp.x * MAX_SHARE / want_w), 0.5, MENU_SCALE)
	scale = Vector2(s, s)
	custom_minimum_size = Vector2(want_w, (vp.y - 2.0 * MARGIN) / s)
	size = custom_minimum_size
	position = Vector2(vp.x - want_w * s - MARGIN, MARGIN).floor()


func card_rect() -> Rect2:
	## The card's footprint on screen, scale included (get_global_rect does
	## not fold the scale in on every build).
	return Rect2(global_position, size * scale)


func _borrow_settings() -> void:
	if player == null or _settings_content != null:
		return
	if not ("settings_panel" in player):
		return
	var sp: Node = player.get("settings_panel")
	if sp == null or sp.get_child_count() == 0:
		return
	_settings_content = sp.get_child(0) as Control
	_settings_home = sp
	sp.remove_child(_settings_content)
	_settings_host.add_child(_settings_content)
	if player.has_method("_refresh_settings_ui"):
		player.call("_refresh_settings_ui")


func _return_settings() -> void:
	if _settings_content == null:
		return
	if _settings_content.get_parent() == _settings_host:
		_settings_host.remove_child(_settings_content)
	if _settings_home != null and is_instance_valid(_settings_home):
		_settings_home.add_child(_settings_content)
	_settings_content = null
	_settings_home = null


func _on_tab(_i: int) -> void:
	if _tabs.get_current_tab_control() != null and _tabs.get_current_tab_control().name == "Settings":
		if player != null and player.has_method("_refresh_settings_ui"):
			player.call("_refresh_settings_ui")
	elif _tabs.get_current_tab_control() != null and _tabs.get_current_tab_control().name == "Monsters":
		_refresh_roster()


func _process(delta: float) -> void:
	if not visible:
		return
	_dock()
	if _rebuild_t >= 0.0:
		_rebuild_t -= delta
		if _rebuild_t <= 0.0:
			_rebuild_t = 0.0   ## still "queued" so the flush below takes it
			_flush_rebuild()
	if selected != null and not is_instance_valid(selected):
		selected = null
		_sync_from_selected()
	## Hover: a fainter rim on whatever the cursor rests on in the world.
	var m := get_viewport().get_mouse_position()
	if card_rect().has_point(m):
		_set_hover(null)
	else:
		_set_hover(_pick_at(m))


## ============================================================= selection ==

func eat_input(event: InputEvent) -> bool:
	## Player hands mouse events here while the card is up. A left click in
	## the world (not on the card) selects what it hits. Returns true when
	## the event was ours.
	if not visible:
		return false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if card_rect().has_point(mb.position):
				return false
			var hit := _pick_at(mb.position)
			if hit != null:
				select(hit)
			return true
	return false


func _camera() -> Camera3D:
	var cam := get_viewport().get_camera_3d()
	if cam == null and player != null and "camera" in player:
		cam = player.get("camera") as Camera3D
	return cam


func _pick_at(screen: Vector2) -> Node3D:
	var cam := _camera()
	if cam == null or not cam.is_inside_tree():
		return null
	var space := cam.get_world_3d().direct_space_state
	if space == null:
		return null
	var from := cam.project_ray_origin(screen)
	var to := from + cam.project_ray_normal(screen) * 200.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = PICK_MASK
	q.collide_with_areas = false
	if player != null and player is CollisionObject3D:
		q.exclude = [(player as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	var who: Object = CreatureSkin.owner_of(hit["collider"])
	if who is Node3D and (who as Node).has_meta("creature_skin"):
		return who as Node3D
	return null


func _set_hover(n: Node3D) -> void:
	if n == hovered:
		return
	if hovered != null and is_instance_valid(hovered) and hovered != selected:
		var sk := CreatureSkin.of(hovered)
		if sk != null:
			sk.set_outline(false)
	hovered = n
	if hovered != null and hovered != selected:
		var sk2 := CreatureSkin.of(hovered)
		if sk2 != null:
			sk2.set_outline(true, OUTLINE_HOVER, 0.02)


func select(n: Node3D) -> void:
	_flush_rebuild()
	if selected != null and is_instance_valid(selected) and selected != n:
		var old := CreatureSkin.of(selected)
		if old != null:
			old.set_outline(false)
	selected = n
	if selected != null:
		var sk := CreatureSkin.of(selected)
		if sk != null:
			sk.set_outline(true, OUTLINE_SELECTED, 0.035)
		if selected is Monster:
			species = (selected as Monster).genome.duplicate(true)
			_tabs.current_tab = 5
			_show_species()
	_syncing = true
	_sync_from_selected()
	_syncing = false


func _deselect() -> void:
	_flush_rebuild()
	if selected != null and is_instance_valid(selected):
		var sk := CreatureSkin.of(selected)
		if sk != null:
			sk.set_outline(false)
	selected = null
	_syncing = true
	_sync_from_selected()
	_syncing = false


func npc() -> NPC:
	if selected != null and is_instance_valid(selected) and selected is NPC:
		return selected as NPC
	return null


func _sync_from_selected() -> void:
	var n := npc()
	if n == null:
		if selected != null and is_instance_valid(selected):
			var what := String(selected.name)
			if (selected as Node).is_in_group("player"):
				what = "the player"
			elif "display_name" in selected:
				what = String(selected.get("display_name"))
			_sel_label.text = "Selected: %s — not a person; the Monsters tab shows a monster's genome." % what
		else:
			_sel_label.text = "Nothing selected. Click a character in the world, or New person."
		_set_widgets_enabled(false)
		return
	_set_widgets_enabled(true)
	_sel_label.text = "Selected: %s, %s (%s)" % [n.npc_name if n.npc_name != "" else "(unnamed)", String(NPC.JOB_TITLE.get(n.job, n.job)).to_lower(), n.personality]
	var lk := n.look
	for key in ["height", "bulk", "limb", "head"]:
		_set_slider(key, float(lk.get(key, 1.0)))
	_set_slider("courage", n.courage)
	for key in ["skin", "hair_col", "eye_col", "tunic", "breeches"]:
		if _pickers.has(key):
			(_pickers[key] as ColorPickerButton).color = lk.get(key, Color.WHITE)
	_set_option("sex", n.sex)
	_set_option("hair", str(lk.get("hair", "short")))
	_set_option("beard", str(lk.get("beard", "none")))
	_set_option("hat", str(lk.get("hat", "job")))
	_set_option("job", n.job)
	_set_option("personality", n.personality)
	_name_edit.text = n.npc_name


func _set_widgets_enabled(on: bool) -> void:
	for s in _sliders.values():
		(s as HSlider).editable = on
	for p in _pickers.values():
		(p as ColorPickerButton).disabled = not on
	for arr in _opts.values():
		for pair in (arr as Array):
			(pair[1] as Button).disabled = not on
	_name_edit.editable = on


func _set_slider(key: String, v: float) -> void:
	if not _sliders.has(key):
		return
	(_sliders[key] as HSlider).set_value_no_signal(v)
	(_vals[key] as Label).text = "%.2f" % v


func _set_option(key: String, value: Variant) -> void:
	if not _opts.has(key):
		return
	for pair in (_opts[key] as Array):
		(pair[1] as Button).button_pressed = pair[0] == value


## ================================================================= edits ==

func _on_slider(v: float, key: String) -> void:
	(_vals[key] as Label).text = "%.2f" % v
	if _syncing:
		return
	var n := npc()
	if n == null:
		return
	if key == "courage":
		n.courage = v
		return
	n.look[key] = v
	_queue_rebuild()


func _on_colour(c: Color, key: String) -> void:
	if _syncing:
		return
	var n := npc()
	if n == null:
		return
	n.look[key] = c
	_queue_rebuild()


func _on_option(key: String, value: Variant) -> void:
	_set_option(key, value)
	if _syncing:
		return
	var n := npc()
	if n == null:
		return
	match key:
		"sex":
			n.sex = String(value)
		"job":
			n.job = String(value)
			n.schedule = NPC.default_schedule(n.job)
			n.display_name = String(NPC.JOB_TITLE.get(n.job, "Villager"))
			n.courage = NPCDirector.courage_for(n.job, _rng)
			_set_slider("courage", n.courage)
		"personality":
			n.personality = String(value)
		_:
			n.look[key] = value
	if key != "personality":
		_queue_rebuild()
	_sync_label()


func _on_name(text: String) -> void:
	var n := npc()
	if n == null:
		return
	if text.strip_edges() != "":
		n.npc_name = text.strip_edges()
	_sync_label()


func _roll_name() -> void:
	var n := npc()
	if n == null:
		return
	n.npc_name = NPCDirector.random_name(_rng, n.sex)
	_name_edit.text = n.npc_name
	_sync_label()


func _sync_label() -> void:
	var n := npc()
	if n != null:
		_sel_label.text = "Selected: %s, %s (%s)" % [n.npc_name if n.npc_name != "" else "(unnamed)", String(NPC.JOB_TITLE.get(n.job, n.job)).to_lower(), n.personality]


func _queue_rebuild() -> void:
	_rebuild_t = REBUILD_DELAY


func _flush_rebuild() -> void:
	if _rebuild_t < 0.0:
		return
	_rebuild_t = -1.0
	var n := npc()
	if n == null:
		return
	n.rebuild_body()
	var sk := CreatureSkin.of(n)
	if sk != null:
		sk.set_outline(true, OUTLINE_SELECTED, 0.035)
	_file_record(n)


func _file_record(n: NPC) -> void:
	## The director's record should know the new look before any save.
	var d := _director()
	if d != null and n.record_id != "" and d.records.has(n.record_id):
		(d.records[n.record_id] as Dictionary)["look"] = NPC.look_to_json(n.look)
		(d.records[n.record_id] as Dictionary)["name"] = n.npc_name
		(d.records[n.record_id] as Dictionary)["job"] = n.job
		(d.records[n.record_id] as Dictionary)["sex"] = n.sex
		(d.records[n.record_id] as Dictionary)["personality"] = n.personality
		(d.records[n.record_id] as Dictionary)["courage"] = n.courage


func _randomize_look() -> void:
	var n := npc()
	if n == null:
		return
	n.look = NPC.random_look(_rng, n.sex, n.job)
	n.rebuild_body()
	_syncing = true
	_sync_from_selected()
	_syncing = false
	var sk := CreatureSkin.of(n)
	if sk != null:
		sk.set_outline(true, OUTLINE_SELECTED, 0.035)
	_file_record(n)


## ================================================================ people ==

func _world() -> Node:
	if player == null:
		return null
	return player.get_parent()


func _director() -> NPCDirector:
	var w := _world()
	if w == null:
		return null
	var tree := w.get_tree()
	if tree == null:
		return null
	var d := tree.get_first_node_in_group("npc_director")
	return d as NPCDirector


func _ahead(dist: float) -> Vector3:
	if player == null or not (player is Node3D):
		return Vector3.ZERO
	var p := player as Node3D
	var fwd := -p.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3.FORWARD
	return p.global_position + fwd.normalized() * dist


func _new_person() -> void:
	var d := _director()
	var w := _world()
	if w == null:
		return
	var n: NPC
	if d != null:
		n = d.make("villager")
		n.look = NPC.random_look(_rng, n.sex, n.job)
		d.place(n, _ahead(3.0))
	else:
		n = NPC.new()
		n.npc_name = NPCDirector.random_name(_rng, n.sex)
		n.look = NPC.random_look(_rng, n.sex, n.job)
		w.add_child(n)
		n.global_position = _ahead(3.0) + Vector3.UP * 0.5
	n.confused = false
	select(n)
	_tabs.current_tab = 0


func _delete_selected() -> void:
	var n := npc()
	if n == null:
		return
	var d := _director()
	if d != null and n.record_id != "":
		d.records.erase(n.record_id)
		d.bodies.erase(n.record_id)
	selected = null
	n.queue_free()
	_syncing = true
	_sync_from_selected()
	_syncing = false


## =============================================================== presets ==

func _save_preset() -> void:
	var n := npc()
	if n == null:
		return
	var nm := _preset_name.text.strip_edges()
	if nm == "":
		nm = n.npc_name if n.npc_name != "" else "person"
	nm = nm.to_lower().replace(" ", "_")
	DirAccess.make_dir_recursive_absolute(PRESET_DIR)
	var f := FileAccess.open("%s/%s.json" % [PRESET_DIR, nm], FileAccess.WRITE)
	if f == null:
		_status.text = "Could not write the preset."
		return
	f.store_string(JSON.stringify(preset_of(n), "\t"))
	f.close()
	_status.text = "Saved preset %s." % nm
	_load_presets()


static func preset_of(n: NPC) -> Dictionary:
	return {"look": NPC.look_to_json(n.look), "job": n.job, "sex": n.sex, "personality": n.personality, "courage": n.courage}


static func apply_preset(n: NPC, p: Dictionary) -> void:
	if p.has("job"):
		n.job = String(p["job"])
		n.schedule = NPC.default_schedule(n.job)
		n.display_name = String(NPC.JOB_TITLE.get(n.job, "Villager"))
	if p.has("sex"):
		n.sex = String(p["sex"])
	if p.has("personality"):
		n.personality = String(p["personality"])
	if p.has("courage"):
		n.courage = float(p["courage"])
	if p.has("look") and p["look"] is Dictionary:
		n.look = NPC.look_from_json(p["look"])


func _load_presets() -> void:
	for c in _preset_list.get_children():
		_preset_list.remove_child(c)
		c.queue_free()
	var dir := DirAccess.open(PRESET_DIR)
	if dir == null:
		_note(_preset_list, "No presets yet.")
		return
	var names: Array = []
	for f in dir.get_files():
		if String(f).ends_with(".json"):
			names.append(String(f))
	names.sort()
	if names.is_empty():
		_note(_preset_list, "No presets yet.")
	for f in names:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_preset_list.add_child(row)
		var l := Label.new()
		l.text = String(f).trim_suffix(".json")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(_button("Load onto", _load_preset.bind(String(f), false), "Put this preset on the selected person"))
		row.add_child(_button("Spawn", _load_preset.bind(String(f), true), "A new person wearing it, ~3 m ahead"))


func _load_preset(file: String, spawn: bool) -> void:
	var f := FileAccess.open("%s/%s" % [PRESET_DIR, file], FileAccess.READ)
	if f == null:
		return
	var p = JSON.parse_string(f.get_as_text())
	f.close()
	if not (p is Dictionary):
		return
	if spawn:
		_new_person()
	var n := npc()
	if n == null:
		return
	apply_preset(n, p)
	n.rebuild_body()
	var sk := CreatureSkin.of(n)
	if sk != null:
		sk.set_outline(true, OUTLINE_SELECTED, 0.035)
	_file_record(n)
	_syncing = true
	_sync_from_selected()
	_syncing = false


## ============================================================ monster lab ==

func _monsters() -> MonsterDirector:
	var w := _world()
	if w == null:
		return null
	if w.has_method("monsters"):
		return w.call("monsters") as MonsterDirector
	return null


func _world_seed() -> int:
	var md := _monsters()
	return md.world_seed if md != null else MonsterDirector.DEFAULT_SEED


func _tier() -> int:
	var lvl := 1
	if player != null and "level" in player:
		lvl = maxi(int(player.get("level")), 1)
	return MonsterGen.tier_for_level(lvl)


func _refresh_roster() -> void:
	if _roster_box == null:
		return
	for c in _roster_box.get_children():
		_roster_box.remove_child(c)
		c.queue_free()
	var key := "wild:wild:0,0"
	if player != null and player is Node3D:
		key = MonsterGen.zone_key((player as Node3D).global_position)
	var tier := _tier()
	_zone_label.text = "Here: %s   —   tier %d (%s)" % [key, tier, MonsterGen.tier_name(tier)]
	var r := MonsterGen.roster(_world_seed(), key, tier)
	for g in r:
		var gd := g as Dictionary
		var b := _button("%s  —  %s" % [str(gd.get("name", "?")), "native" if bool(gd.get("native", false)) else "newcomer, tier %d" % int(gd.get("born_tier", 0))], _pick_species.bind(gd), MonsterGen.describe(gd))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_roster_box.add_child(b)


func _pick_species(g: Dictionary) -> void:
	species = g.duplicate(true)
	_show_species()


func _show_species() -> void:
	if species.is_empty():
		_species_label.text = "No species picked."
		return
	_species_label.text = "%s\n%s" % [str(species.get("name", "?")), MonsterGen.describe(species)]


func _roll_species() -> void:
	species = MonsterGen.roll_species(_rng, _tier())
	_show_species()


func _reroll_part(which: String) -> void:
	if species.is_empty():
		_roll_species()
		return
	var fresh := MonsterGen.roll_species(_rng, int(species.get("tier", _tier())), {"plan": species.get("plan", "quadruped")})
	match which:
		"body":
			for k in ["size", "bulk", "leg_len", "neck", "head_size", "head", "horns", "eyes", "tail", "plates", "spines", "segments", "arms", "tile", "hp", "dmg", "speed", "mass", "pack", "name", "id"]:
				species[k] = fresh[k]
		"abilities":
			species["abilities"] = fresh["abilities"]
			species["special"] = fresh["special"]
		"colours":
			for k in ["col", "accent", "eye_col"]:
				species[k] = fresh[k]
	_show_species()


func _spawn_species(pack: bool) -> void:
	if species.is_empty():
		_roll_species()
	var w := _world()
	if w == null:
		return
	var at := _ahead(4.0)
	var n := 1
	if pack:
		var pk: Array = species.get("pack", [1, 2])
		n = _rng.randi_range(int(pk[0]), int(pk[1]))
	var first: Monster = null
	for i in range(n):
		var m := Monster.from(species)
		m.confused = true
		w.add_child(m)
		var off := Vector3.ZERO if i == 0 else Vector3(_rng.randf_range(-2.5, 2.5), 0.0, _rng.randf_range(-2.5, 2.5))
		m.global_position = _ground(at + off)
		if first == null:
			first = m
	_status.text = "Spawned %d x %s." % [n, str(species.get("name", "?"))]
	if first != null:
		select(first)


func _ground(pos: Vector3) -> Vector3:
	var cam := _camera()
	if cam == null:
		return pos + Vector3.UP * 0.5
	var space := cam.get_world_3d().direct_space_state
	if space == null:
		return pos + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 4.0, pos + Vector3.DOWN * 30.0)
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return pos + Vector3.UP * 0.5
	return (hit["position"] as Vector3) + Vector3.UP * 0.2


func _save_species() -> void:
	if species.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(MONSTER_DIR)
	var nm := str(species.get("name", "species")).to_lower().replace(" ", "_")
	var f := FileAccess.open("%s/%s.json" % [MONSTER_DIR, nm], FileAccess.WRITE)
	if f == null:
		_status.text = "Could not write the species."
		return
	f.store_string(JSON.stringify(MonsterGen.to_json(species), "\t"))
	f.close()
	_status.text = "Saved species %s." % nm
	_load_saved_species()


func _load_saved_species() -> void:
	if _saved_box == null:
		return
	for c in _saved_box.get_children():
		_saved_box.remove_child(c)
		c.queue_free()
	var dir := DirAccess.open(MONSTER_DIR)
	if dir == null:
		_note(_saved_box, "None saved yet.")
		return
	var names: Array = []
	for f in dir.get_files():
		if String(f).ends_with(".json"):
			names.append(String(f))
	names.sort()
	if names.is_empty():
		_note(_saved_box, "None saved yet.")
	for f in names:
		var b := _button(String(f).trim_suffix(".json"), _pick_saved.bind(String(f)), "Pick this species")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_saved_box.add_child(b)


func _pick_saved(file: String) -> void:
	var f := FileAccess.open("%s/%s" % [MONSTER_DIR, file], FileAccess.READ)
	if f == null:
		return
	var p = JSON.parse_string(f.get_as_text())
	f.close()
	if p is Dictionary:
		species = MonsterGen.from_json(p)
		_show_species()
