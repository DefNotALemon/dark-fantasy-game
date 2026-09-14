extends SceneTree
## Boot the real World.tscn headless and walk the NPC base through the REAL
## Player: the M-menu spawn path, the [E] prompt, E through Player._input,
## Esc through Player._close_menu, RMB focus, F, and the save round trip.
##   godot --headless --path . --script res://tests/NPCLive.gd

var _t := 0.0
var _world: Node = null
var _phase := 0
var _pass := 0
var _fail := 0
var _npc: NPC = null
var _pl: Node = null
var _f: NPCFocus = null


func ok(c: bool, what: String) -> void:
	if c:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: ", what)


func _initialize() -> void:
	_world = (load("res://scenes/World.tscn") as PackedScene).instantiate()
	root.add_child(_world)


func key(code: int, pressed := true) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code as Key
	ev.physical_keycode = code as Key
	ev.pressed = pressed
	root.push_input(ev)


func _process(d: float) -> bool:
	_t += d
	match _phase:
		0:
			if _t < 5.0:
				return false
			_phase = 1
			_pl = root.get_tree().get_first_node_in_group("player")
			ok(_pl != null, "player exists")
			var dir := root.get_tree().get_first_node_in_group("npc_director") as NPCDirector
			ok(dir != null, "director booted from World._ready")
			ok(dir != null and dir.records.size() == 3, "three camp records")
			ok(dir != null and dir.bodies.size() == 3, "three bodies staged at the camp")
			_f = NPCFocus.of(_pl)
			ok(_f != null, "focus attached to the real player")
			ok(_f != null and _f.prompt != null and _f.panel != null, "prompt + talk panel built on the real HUD")
			for b in dir.bodies.values():
				var n := b as NPC
				print("  %s the %s %s: %s at %s  home=%s work=%s" % [n.npc_name, n.personality, n.job, n.mode_name(), str(n.global_position.round()), str(n.home.round()), str(n.work.round())])
				if n.npc_name == "Hannah Tibbetts":
					_npc = n
			ok(_npc != null, "Hannah is here")
			## hold her still for the probe: an all-day idle slot, no ambles
			_npc.schedule = [{"from": 0.0, "to": 24.0, "do": "idle", "at": "anchor"}]
			_npc.anchor = _npc.global_position
			_npc.slot_key = ""
			_npc.goto_target = Vector3.INF
			_npc._enter(NPC.Mode.IDLE)
			_npc._idle_next = 999.0
			## stand 2.5 m in front of her, facing her, first person
			_pl.set("input_locked", false)
			_pl.set("cam_mode", "fp")
			_pl.set("pitch", 0.0)
			## the hunch draws the sword whenever anything out there is
			## agitated (a wolf on a deer counts); pin the sword OUT for now
			_pl.set("set_hunch", false)
			_pl.set("sheathed", false)
			_pl.set("sheath_t", 0.0)
			var pl3 := _pl as Node3D
			var stand: Vector3 = _npc.global_position + (-_npc.global_transform.basis.z) * 2.5
			pl3.global_position = stand + Vector3.UP * 0.1
			var to: Vector3 = _npc.global_position - pl3.global_position
			pl3.rotation = Vector3(0.0, atan2(-to.x, -to.z), 0.0)
			var hd = _pl.get("head")
			if hd is Node3D:
				(hd as Node3D).rotation.x = 0.0
			_t = 0.0
		1:
			_npc._idle_next = 999.0
			if _t < 1.0:
				return false
			_phase = 2
			ok(_f.hover == _npc, "the real camera's gaze finds her (hover=%s)" % (_f.hover.npc_name if _f.hover else "none"))
			ok(_f.prompt.visible and _f.prompt.text.begins_with("[E] Talk to Hannah"), "prompt: %s" % _f.prompt.text)
			## E through Player._input
			key(KEY_E)
			key(KEY_E, false)
			_t = 0.0
		2:
			if _t < 0.3:
				return false
			_phase = 3
			ok(_f.talking == _npc, "E through Player._input opened the talk")
			ok(String(_pl.get("menu_open")) == "talk", "menu_open == talk (%s)" % String(_pl.get("menu_open")))
			ok(_f.panel.visible, "the talk panel is showing")
			ok(_f.text_lbl.text != "", "a line: %s" % _f.text_lbl.text)
			ok(_f.name_lbl.text == "Hannah Tibbetts", "spoken by her")
			## the real player spawns with the sword OUT: she wants it away first
			ok(_f.node_id == "steel", "sword out: the talk opens at 'steel' (%s)" % _f.node_id)
			ok(_f.choices_box.get_child_count() == 2, "%d choices" % _f.choices_box.get_child_count())
			ok(_npc.mode == NPC.Mode.TALK, "she is talking (%s)" % _npc.mode_name())
			ok(not _f.prompt.visible, "no prompt while talking")
			## Esc through the player's own close
			key(KEY_ESCAPE)
			key(KEY_ESCAPE, false)
			_t = 0.0
		3:
			if _t < 0.3:
				return false
			_phase = 4
			ok(_f.talking == null, "Esc ended the talk")
			ok(String(_pl.get("menu_open")) == "", "menu closed")
			## sheathe: RMB stops being the guard
			_pl.set("sheathed", true)
			_pl.set("sheath_t", 1.0)
			## RMB focus: the real Input, if it takes the event headless
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_RIGHT
			mb.pressed = true
			Input.parse_input_event(mb)
			Input.flush_buffered_events()
			if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
				print("  (headless Input does not hold the mouse button; forcing RMB)")
				_f.rmb_override = 1
			_t = 0.0
		4:
			if _t < 0.5:
				return false
			_phase = 5
			ok(_f.focused == _npc, "RMB focused her")
			ok(_npc.mode == NPC.Mode.ATTEND, "she attends (%s)" % _npc.mode_name())
			ok(_f.prompt.text.contains("[E] Greet") or _f.prompt.text.contains("[E] Talk"), "focus prompt: %s" % _f.prompt.text)
			var d0 := _npc.disposition
			key(KEY_F)
			key(KEY_F, false)
			_t = 0.0
			set_meta("d0", d0)
		5:
			if _t < 0.3:
				return false
			_phase = 6
			ok(_npc.disposition < float(get_meta("d0")), "F through Player._input antagonized her (%.0f -> %.0f)" % [float(get_meta("d0")), _npc.disposition])
			ok(_npc.bark_text != "", "she answered: %s" % _npc.bark_text)
			ok(_npc.name_label.visible, "...over her head")
			## E now: sheathed, focused -> greet (or talk if she already said hello)
			key(KEY_E)
			key(KEY_E, false)
			_phase = 51
			_t = 0.0
			return false
		51:
			if _t < 0.3:
				return false
			_phase = 6
			ok(_f.talking == _npc or _f.greeted, "E while focused: greeted or talking (talking=%s greeted=%s)" % [str(_f.talking != null), str(_f.greeted)])
			if _f.talking == null:
				key(KEY_E)
				key(KEY_E, false)
				_phase = 52
				_t = 0.0
				return false
			_phase = 52
			_t = 0.0
			return false
		52:
			if _t < 0.3:
				return false
			_phase = 6
			ok(_f.talking == _npc, "...and talks")
			ok(_f.node_id != "steel", "sheathed: no steel node (%s)" % _f.node_id)
			ok(_f.choices_box.get_child_count() >= 5, "%d choices at the hub" % _f.choices_box.get_child_count())
			_f._end_talk()
			## release
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_RIGHT
			mb.pressed = false
			Input.parse_input_event(mb)
			Input.flush_buffered_events()
			_f.rmb_override = -1
			## the M-menu path: _spawn_mob(NPC)
			var before := root.get_tree().get_nodes_in_group("npcs").size()
			if _pl.has_method("_spawn_mob"):
				_pl.call("_spawn_mob", NPC)
			set_meta("before", before)
			_t = 0.0
		6:
			if _t < 0.6:
				return false
			_phase = 7
			var dir := root.get_tree().get_first_node_in_group("npc_director") as NPCDirector
			ok(root.get_tree().get_nodes_in_group("npcs").size() == int(get_meta("before")) + 1, "the menu spawned a person")
			ok(dir.records.size() == 4, "...adopted into a fourth record")
			var newest: NPC = null
			for b in dir.bodies.values():
				if (b as NPC).record_id == "npc_004":
					newest = b
			ok(newest != null and newest.npc_name != "" and not newest.confused, "named %s, not confused" % (newest.npc_name if newest else "?"))
			## save / load through the real World
			var st: Dictionary = _world.call("save_state")
			ok(st.has("npcs") and (st["npcs"] as Dictionary).has("records"), "World.save_state carries the people")
			var hannah_id := _npc.record_id
			_npc.disposition = 77.0
			var st2: Dictionary = _world.call("save_state")
			ok(is_equal_approx(float((((st2["npcs"] as Dictionary)["records"] as Dictionary)[hannah_id] as Dictionary)["disposition"]), 77.0), "a live change is in the save")
			_world.call("apply_state", st)
			_t = 0.0
		7:
			if _t < 1.0:
				return false
			var dir := root.get_tree().get_first_node_in_group("npc_director") as NPCDirector
			ok(dir.records.size() == 4, "apply_state restored four records")
			var h: NPC = null
			for b in dir.bodies.values():
				if (b as NPC).npc_name == "Hannah Tibbetts":
					h = b
			ok(h != null and h.disposition < 77.0, "...and Hannah's disposition is the saved one (%s)" % (str(h.disposition) if h else "gone"))
			print(dir.report())
			print("=== NPC LIVE: %d passed, %d failed ===" % [_pass, _fail])
			quit(0 if _fail == 0 else 1)
			return true
	return false
