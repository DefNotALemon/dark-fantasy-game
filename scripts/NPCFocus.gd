class_name NPCFocus
extends Node
## ===========================================================================
## The player's side of meeting a person — RDR2's focus, on Myrkfell's keys.
##
## Lives as a child of the Player (NPCDirector attaches it; `attach()` is
## idempotent). Every physics frame it finds the NPC under the crosshair
## (HOVER: the same gaze-cone rule the [E] pickup prompt uses — origin at the
## head, direction from the camera), and:
##
##   hold RMB on a person (weapon sheathed)  -> FOCUS. They stop, turn to you,
##                                              and look you in the eye; the
##                                              prompt offers the options.
##   E while focused                          -> GREET (a wave or a nod back),
##                                              then TALK (the dialogue box).
##   F while focused                          -> ANTAGONIZE. They answer by
##                                              temperament; push it and the
##                                              brave square up, the rest run.
##   E on a person, no focus                  -> TALK straight away (Skyrim).
##
## TALK opens a cursor-driven panel (the game's menus are all cursor-driven;
## the pad's right stick is a cursor): the line, the speaker, and the choices
## as buttons. E takes the first choice — a keyboard can skim a talk without
## touching the mouse — and Esc leaves, through Player._close_menu like every
## other menu, because the panel is `menu_open == "talk"`.
##
## THIS FILE TAKES NO KEY. Player._input hands E and F here through
## `take_e` / `take_f` (two one-line hunks); RMB is polled the way the guard
## polls it. DevInputTests' registry stays exactly as it was.
## ===========================================================================

const HOVER_R := 5.5           ## m — a person this close under the crosshair
const HOVER_COS := 0.90        ## the pickup prompt's own cone
const FOCUS_R := 7.0           ## focus breaks past this
const TALK_R := 4.5            ## a talk closes if you walk off
const TALK_OPEN_R := 4.0       ## E-to-talk needs this
const TWIN_LOCK := 0.30        ## s — the pad posts E and F together; the second is swallowed
const TURN_RATE := 4.0         ## how fast focus turns the player toward the person
const PROMPT_Y := 0.655        ## fraction of the viewport, under the pickup prompt (0.60)

var player: Node3D = null
var hover: NPC = null
var focused: NPC = null
var talking: NPC = null
var greeted := false           ## a hello was exchanged in this focus
var focus_t := 0.0
var _twin_lock := 0.0
var _tagged: NPC = null
var rmb_override := -1         ## tests: -1 reads the mouse, 0 / 1 force it

## UI
var prompt: Label = null
var panel: PanelContainer = null
var name_lbl: Label = null
var text_lbl: Label = null
var choices_box: VBoxContainer = null
var _ui_layer: CanvasLayer = null

## the talk
var tree: Dictionary = {}
var ctx: Dictionary = {}
var node_id := ""
var node_end := false
var lines_spoken := 0
var _rng := RandomNumberGenerator.new()


static func of(pl: Node) -> NPCFocus:
	if pl == null:
		return null
	for c in pl.get_children():
		if c is NPCFocus:
			return c
	return null


static func attach(pl: Node) -> NPCFocus:
	var f := of(pl)
	if f != null:
		return f
	f = NPCFocus.new()
	f.name = "NPCFocus"
	pl.add_child(f)
	return f


static func take_e(pl: Node) -> bool:
	## Player._input, KEY_E: "if NPCFocus.take_e(self): pass  elif <the old chain>".
	var f := of(pl)
	return f != null and f.on_e()


static func take_f(pl: Node) -> bool:
	var f := of(pl)
	return f != null and f.on_f()


static func claims_rmb(pl: Node) -> bool:
	## Player._physics_process: `blocking = RMB and ... and not NPCFocus.claims_rmb(self)`.
	## "Raising a guard pulls the steel" — so with the sword sheathed and a
	## person under the crosshair, RMB must be the focus and NOT the guard, or
	## the guard would draw the sword and the focus would break itself. With
	## steel already out RMB stays the guard (aiming it at someone is its own
	## message: they get wary).
	var f := of(pl)
	return f != null and f.rmb_claimed()


func rmb_claimed() -> bool:
	if player == null or _rmb_is_guard():
		return false
	if talking != null or focused != null:
		return true
	return hover != null and is_instance_valid(hover) and hover.can_be_greeted()


func _ready() -> void:
	player = get_parent() as Node3D
	_rng.randomize()
	_build_ui()


## ------------------------------------------------------------- the loop ---

func _physics_process(delta: float) -> void:
	_twin_lock = maxf(0.0, _twin_lock - delta)
	if player == null or not is_instance_valid(player):
		return
	if _ui_layer == null:
		_build_ui()
	var menu := _menu()
	var free := menu == "" and _kd() == ""

	if talking != null:
		if not is_instance_valid(talking) or talking.dying or talking.hostile or talking.indoors \
				or menu != "talk" or _dist(talking) > TALK_R:
			_end_talk()
		else:
			talking.attend(player)
		_set_hover(null)
		_update_prompt()
		return

	var h := _find_hover() if free else null
	_set_hover(h)

	var rmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) if rmb_override < 0 else rmb_override > 0
	var can_focus := free and not _rmb_is_guard()
	if focused != null:
		if not rmb or not can_focus or not is_instance_valid(focused) or focused.dying \
				or focused.hostile or _dist(focused) > FOCUS_R or not focused.can_be_greeted():
			_unfocus()
		else:
			focus_t += delta
			focused.attend(player)
			_soft_turn(delta)
	elif rmb and can_focus and h != null and h.can_be_greeted():
		focused = h
		## a hello is once a day: if it has been said (in passing, or before
		## a talk), E goes straight to Talk
		greeted = h.greeted_day == h.day_now()
		focus_t = 0.0
		h.attend(player)
	_update_prompt()


func _find_hover() -> NPC:
	## The person under the crosshair: nearest to the gaze inside HOVER_R.
	## Distance from the HEAD, direction from the CAMERA — in third person the
	## camera hangs metres behind the body (Player._aim_origin's rule).
	var origin := _aim_origin()
	var fwd := _aim_dir()
	var best := HOVER_COS
	var pick: NPC = null
	for n in get_tree().get_nodes_in_group("npcs"):
		var p := n as NPC
		if p == null or p.dying or p.indoors or not p.visible:
			continue
		var to := (p.global_position + Vector3.UP * 1.0) - origin
		var dist := to.length()
		if dist > HOVER_R or dist < 0.05:
			continue
		var d := fwd.dot(to.normalized())
		if d > best:
			best = d
			pick = p
	return pick


func _set_hover(h: NPC) -> void:
	hover = h
	var want: NPC = focused if focused != null else h
	if _tagged != want:
		if _tagged != null and is_instance_valid(_tagged):
			_tagged.show_tag = false
		_tagged = want
		if _tagged != null:
			_tagged.show_tag = true


func _unfocus() -> void:
	focused = null
	greeted = false
	focus_t = 0.0


func _soft_turn(delta: float) -> void:
	## RDR2 pulls the camera onto the person; here the body eases round so
	## the mouse still owns the view.
	if focused == null:
		return
	var d := focused.global_position - player.global_position
	d.y = 0.0
	if d.length() < 0.2:
		return
	var want := atan2(-d.x, -d.z)
	player.rotation.y = lerp_angle(player.rotation.y, want, clampf(delta * TURN_RATE, 0.0, 1.0))


## ------------------------------------------------------------- keys -------

func on_e() -> bool:
	## E: continue a talk (first choice), greet then talk while focused, or
	## talk to whoever is under the crosshair. Returns true when it was ours.
	if talking != null:
		_take_e_choice()
		_twin_lock = TWIN_LOCK
		return true
	if _kd() != "" or _menu() != "":
		return false
	if focused != null and is_instance_valid(focused) and focused.can_be_greeted():
		_twin_lock = TWIN_LOCK
		if not greeted:
			greeted = true
			focused.greet(player)
		else:
			_start_talk(focused)
		return true
	if hover != null and is_instance_valid(hover) and hover.can_be_greeted() and _dist(hover) <= TALK_OPEN_R:
		_twin_lock = TWIN_LOCK
		_start_talk(hover)
		return true
	return false


func on_f() -> bool:
	## F: antagonize the focused person (or the one you are talking to).
	if _twin_lock > 0.0:
		return true   ## the pad's Square posted E and F together: E already answered
	if talking != null and is_instance_valid(talking):
		var t := talking
		_end_talk()
		t.antagonize(player)
		return true
	if _menu() != "" or _kd() != "":
		return false
	if focused != null and is_instance_valid(focused):
		focused.antagonize(player)
		_twin_lock = TWIN_LOCK
		return true
	return false


## ------------------------------------------------------------- the talk ---

func _start_talk(npc: NPC) -> void:
	if npc == null or not is_instance_valid(npc):
		return
	ctx = NPCDialogue.context_for(npc, player, npc.sky_level(), _place_name())
	tree = NPCDialogue.tree_for(npc)
	if not npc.begin_talk(player):
		return
	talking = npc
	greeted = true   ## talking IS the hello; the focus (if RMB is still held) resumes afterwards
	lines_spoken = 0
	_set_menu("talk")
	if panel != null:
		panel.visible = true
	node_id = NPCDialogue.first_node(tree, ctx)
	_show_node(node_id)


func _show_node(id: String) -> void:
	var node: Dictionary = tree.get(id, {})
	if node.is_empty() or talking == null:
		_end_talk()
		return
	node_id = id
	if node.has("do"):
		_apply(NPCDialogue.parse_actions(String(node["do"])))
		if talking == null:
			return
	node_end = bool(node.get("end", false))
	lines_spoken += 1
	if name_lbl != null:
		name_lbl.text = talking.npc_name if talking.npc_name != "" else talking.display_name
	if text_lbl != null:
		text_lbl.text = NPCDialogue.text_of(node, ctx, _rng.randi())
	talking.on_line_spoken()
	_rebuild_choices(node)


func _rebuild_choices(node: Dictionary) -> void:
	if choices_box == null:
		return
	for c in choices_box.get_children():
		c.queue_free()
	var choices := NPCDialogue.choices_for(node, ctx)
	if node_end or choices.is_empty():
		var b := _choice_button("[E]  Leave")
		b.pressed.connect(_end_talk)
		return
	## E takes the LAST choice — the "I see." / "Farewell." of every node —
	## so a keyboard can always continue or leave, and never loops a topic.
	var i := 0
	for ch in choices:
		i += 1
		var b := _choice_button("%s%s" % ["[E]  " if i == choices.size() else "      ", String((ch as Dictionary).get("text", "..."))])
		b.pressed.connect(_pick.bind(ch))


func _choice_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 17)
	choices_box.add_child(b)
	return b


func _take_e_choice() -> void:
	## E = continue: the last choice of the node (see _rebuild_choices).
	if talking == null:
		return
	var node: Dictionary = tree.get(node_id, {})
	var choices := NPCDialogue.choices_for(node, ctx)
	if node_end or choices.is_empty():
		_end_talk()
		return
	_pick(choices[choices.size() - 1])


func _pick(choice: Dictionary) -> void:
	if talking == null:
		return
	if choice.has("do"):
		_apply(NPCDialogue.parse_actions(String(choice["do"])))
		if talking == null:
			return
	var to := String(choice.get("to", ""))
	if to == "" or not tree.has(to):
		_end_talk()
		return
	_show_node(to)


func _apply(fx: Dictionary) -> void:
	## The vocabulary's side effects land on the person and the player.
	if talking == null:
		return
	var npc := talking
	npc.disposition = clampf(npc.disposition + float(fx.get("disp", 0.0)), -100.0, 100.0)
	for f in fx.get("flags_set", []):
		npc.flags[String(f)] = true
	for f in fx.get("flags_clear", []):
		npc.flags.erase(String(f))
	var gold := int(fx.get("gold", 0))
	if gold != 0 and "gold" in player:
		player.set("gold", maxi(0, int(player.get("gold")) + gold))
	for item in fx.get("give", []):
		if player.has_method("_give_item"):
			player.call("_give_item", String(item), 1, 0.5)
		if player.has_method("_push_gain"):
			player.call("_push_gain", String(item), 1)
	var act := String(fx.get("act", ""))
	if act != "":
		npc.act(act)
	## keep the context honest for the next condition
	ctx["disp"] = npc.disposition
	ctx["flags"] = npc.flags
	if "gold" in player:
		ctx["gold"] = int(player.get("gold"))
	if bool(fx.get("hostile", false)):
		_end_talk()
		npc.make_hostile()
		return
	if bool(fx.get("end", false)):
		_end_talk()


func _end_talk() -> void:
	var t := talking
	talking = null
	if t != null and is_instance_valid(t):
		t.end_talk()
	if panel != null:
		panel.visible = false
	if choices_box != null:
		for c in choices_box.get_children():
			c.queue_free()
	if _menu() == "talk":
		if player.has_method("_close_menu"):
			player.call("_close_menu")
		else:
			_set_menu("")
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## ------------------------------------------------------------- player bits

func _menu() -> String:
	return String(player.get("menu_open")) if "menu_open" in player else ""


func _set_menu(which: String) -> void:
	if "menu_open" in player:
		player.set("menu_open", which)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if which != "" else Input.MOUSE_MODE_CAPTURED


func _kd() -> String:
	return String(player.get("kd_phase")) if "kd_phase" in player else ""


func _rmb_is_guard() -> bool:
	## RMB is the guard with a sword out and the draw-cancel with a bow out;
	## with those in hand it is not a focus.
	var st: float = float(player.get("sheath_t")) if "sheath_t" in player else 1.0
	var w: String = String(player.get("current_weapon")) if "current_weapon" in player else ""
	return st < 0.5 and (w == "sword" or w == "bow")


func _aim_origin() -> Vector3:
	var h = player.get("head") if "head" in player else null
	if h is Node3D:
		return (h as Node3D).global_position
	return player.global_position + Vector3.UP * 1.6


func _aim_dir() -> Vector3:
	var c = player.get("camera") if "camera" in player else null
	if c is Node3D:
		return -(c as Node3D).global_transform.basis.z
	return -player.global_transform.basis.z


func _dist(npc: NPC) -> float:
	if npc == null or not is_instance_valid(npc):
		return 9999.0
	return _aim_origin().distance_to(npc.global_position + Vector3.UP * 1.0)


func _place_name() -> String:
	var w := get_tree().get_first_node_in_group("world")
	if w != null and w.has_method("place_name_at"):
		return String(w.call("place_name_at", player.global_position))
	return "Myrkfell"


## ------------------------------------------------------------- UI ---------

func _build_ui() -> void:
	var hl = player.get("hud_layer") if "hud_layer" in player else null
	if not (hl is CanvasLayer):
		return   ## no HUD (a headless suite, a stub player): try again later
	_ui_layer = hl as CanvasLayer
	prompt = Label.new()
	prompt.name = "NPCPrompt"
	prompt.add_theme_font_size_override("font_size", 17)
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.visible = false
	_ui_layer.add_child(prompt)

	panel = PanelContainer.new()
	panel.name = "TalkPanel"
	panel.visible = false
	_ui_layer.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	margin.add_child(vb)
	name_lbl = Label.new()
	name_lbl.add_theme_font_size_override("font_size", 19)
	name_lbl.add_theme_color_override("font_color", Color(0.94, 0.86, 0.66))
	vb.add_child(name_lbl)
	text_lbl = Label.new()
	text_lbl.add_theme_font_size_override("font_size", 18)
	text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_lbl.custom_minimum_size = Vector2(640, 0)
	vb.add_child(text_lbl)
	vb.add_child(HSeparator.new())
	choices_box = VBoxContainer.new()
	choices_box.add_theme_constant_override("separation", 4)
	vb.add_child(choices_box)


func _process(_delta: float) -> void:
	if _ui_layer == null or player == null:
		return
	var vp := get_viewport().get_visible_rect().size
	if prompt != null and prompt.visible:
		prompt.position = Vector2((vp.x - prompt.size.x) * 0.5, vp.y * PROMPT_Y)
	if panel != null and panel.visible:
		var sc := clampf(vp.x / 1280.0, 1.0, 1.35)
		panel.scale = Vector2(sc, sc)
		panel.position = Vector2((vp.x - panel.size.x * sc) * 0.5, vp.y - panel.size.y * sc - 36.0).floor()


func _update_prompt() -> void:
	if prompt == null:
		return
	if talking != null:
		prompt.visible = false
		return
	if focused != null and is_instance_valid(focused):
		var who := focused.npc_name if focused.npc_name != "" else focused.display_name
		prompt.text = "%s   ·   [E] %s   ·   [F] Antagonize" % [who, "Talk" if greeted else "Greet"]
		prompt.visible = true
		return
	if hover != null and is_instance_valid(hover) and hover.can_be_greeted():
		var who := hover.npc_name if hover.npc_name != "" else hover.display_name
		if _rmb_is_guard():
			prompt.text = "[E] Talk to %s   ·   sheathe to focus" % who
		else:
			prompt.text = "[E] Talk to %s   ·   hold [RMB] to focus" % who
		prompt.visible = true
		return
	prompt.visible = false


func report() -> Dictionary:
	return {
		"hover": hover.npc_name if hover != null and is_instance_valid(hover) else "",
		"focused": focused.npc_name if focused != null and is_instance_valid(focused) else "",
		"talking": talking.npc_name if talking != null and is_instance_valid(talking) else "",
		"node": node_id, "greeted": greeted, "lines": lines_spoken,
	}
