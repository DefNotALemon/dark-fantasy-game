extends SceneTree
## ===========================================================================
## tests/ClaudeChatLive.gd -- F4 pressed for real, on the real World.
##
##   godot --headless --path . --script res://tests/ClaudeChatLive.gd
##
## The half ClaudeChatTests cannot reach: Player's own _input, with the god
## editor's first refusal, the menu table and the cursor all in the loop.
## Boots World.tscn the way PLAY does (CityLive's pattern), waits for the body,
## then posts real InputEventKeys the way Pad.gd does:
##
##   F4        -> menu_open == "claude", the card visible, the cursor free
##   M, G, K   -> typing: menu_open STAYS "claude" (the leak this exists for --
##                a typed M used to be the map)
##   Esc       -> closed, cursor captured again
##   F4, F4    -> open, then toggled shut
##
## No network. The card is never asked to send.
## ===========================================================================

const SETTLE := 6
var _world: Node
var _t := 0.0
var _pass := 0
var _fail := 0
var _phase := 0
var _player: Node = null


func ok(c: bool, what: String) -> void:
	if c:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: ", what)


func _initialize() -> void:
	print("=== Claude Chat LIVE ===")
	_world = (load("res://scenes/World.tscn") as PackedScene).instantiate()
	root.add_child(_world)


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _tap(code: Key) -> void:
	_key(code, true)
	for i in range(2):
		await process_frame
	_key(code, false)
	for i in range(SETTLE):
		await process_frame


func _process(d: float) -> bool:
	_t += d
	if _phase == 0:
		if _t < 3.0:
			return false
		_phase = 1
		if _world.has_method("front_door_done"):
			_world.call("front_door_done", false)
		return false
	if _phase == 1:
		_player = get_first_node_in_group("player")
		if _player == null or _player.get("claude_chat") == null or bool(_player.get("input_locked")):
			if _t < 240.0:
				return false
			ok(false, "no player with a claude card in 240 s")
			_finish()
			return true
		_phase = 2
		_drive()
		return false
	return false


func _drive() -> void:
	ok(true, "the body is up with a card (%.0f s)" % _t)
	## let the world settle a beat so the first press is not eaten by a
	## blackout edge (Pad.gd swallows a frame coming out of input_locked)
	for i in range(30):
		await process_frame
	var card: Node = _player.get("claude_chat")
	ok(card != null and not bool(card.get("visible")), "card starts hidden")
	ok(String(_player.get("menu_open")) == "", "no menu open to begin with (%s)" % String(_player.get("menu_open")))

	await _tap(KEY_F4)
	ok(String(_player.get("menu_open")) == "claude", "F4 opens the claude menu (%s)" % String(_player.get("menu_open")))
	ok(bool(card.get("visible")), "the card is visible")
	if DisplayServer.get_name() != "headless":   ## the headless server has no cursor to free
		ok(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "the cursor is free while it is up")

	## THE LEAK. Typing into the card must not reach Player's match block.
	for k in [KEY_M, KEY_G, KEY_K, KEY_C, KEY_TAB]:
		await _tap(k)
	ok(String(_player.get("menu_open")) == "claude", "M, G, K, C, Tab while typing leave the claude menu up (%s)" % String(_player.get("menu_open")))
	ok(not bool(_player.get("crouching")), "and C did not crouch the body")

	await _tap(KEY_ESCAPE)
	ok(String(_player.get("menu_open")) == "", "Esc closes it (%s)" % String(_player.get("menu_open")))
	ok(not bool(card.get("visible")), "card hidden again")
	if DisplayServer.get_name() != "headless":
		ok(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "cursor captured again")

	await _tap(KEY_F4)
	ok(String(_player.get("menu_open")) == "claude", "F4 opens it again")
	await _tap(KEY_F4)
	ok(String(_player.get("menu_open")) == "", "a second F4 toggles it shut (%s)" % String(_player.get("menu_open")))

	## the snapshot on the real world has the real fields
	var snap: Dictionary = card.call("snapshot")
	ok(snap.has("pos") and snap.has("health"), "snapshot reads the body: %s" % JSON.stringify(snap).left(160))
	ok(snap.has("hour") and snap.has("weather"), "and the sky: hour=%s weather=%s" % [str(snap.get("hour", "?")), str(snap.get("weather", "?"))])
	## the card with no key refuses to send rather than erroring
	card.set("backend", "anthropic")
	card.set("api_key", "")
	card.call("send", "hello?")
	ok(card.get("_chat") == null, "with no key it says so instead of sending")
	_finish()


func _finish() -> void:
	print("=== CLAUDE CHAT LIVE: %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
