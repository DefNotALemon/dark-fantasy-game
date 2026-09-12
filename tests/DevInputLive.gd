extends RefCounted

# =============================================================================
# tests/DevInputLive.gd -- the dev bindings, pressed for real, in two calls.
# (2026-09-09, HARDEN. The other half of queue item HARDEN #3.)
#
# Driven from a running game:
#
#     const L = preload("res://tests/DevInputLive.gd")
#     L.start(player)          # returns at once; the pass runs in the game
#     ... a few seconds later ...
#     L.report()               # what every key did
#
# WHY IT IS SHAPED LIKE THIS. The game runs at 6-8 FPS while terrain streams,
# and `await tree.process_frame` is charged at that rate, so the honest six
# frames between a press and a read is nearly a second per key. Driving twelve
# keys inside one `game_eval` blows the ~8 s budget every time -- which is why
# the manual pass had become one key per call and about twelve round trips a
# round. So the pass does not run inside an eval at all: `start` kicks off a
# coroutine, hands the eval straight back, and the game gets on with it in its
# own time. `report` collects it afterwards. Two calls, whatever the frame rate.
#
# It carries NO KEYCODES OF ITS OWN. Every key it presses comes out of
# tests/DevInputRegistry.gd, and DevInputTests asserts against this source that
# there is not a single key token in it. If the prober had its own table it
# could drift from the registry silently, and then the live pass and the
# headless pass would be checking two different keyboards -- which is the exact
# failure the pair of them exists to prevent.
#
# It declares no input callback. It manufactures InputEventKeys and posts them
# the same way Pad.gd does, so every guard, cooldown and stance rule in
# Player._input applies to the probe for free.
# =============================================================================

const REG := preload("res://tests/DevInputRegistry.gd")
const SELF := "res://tests/DevInputLive.gd"

## Frames between a press and the read that judges it. Input.parse_input_event
## is buffered while use_accumulated_input is on, so an event lands on the NEXT
## frame at the earliest; menus then need a frame or two to settle.
const SETTLE := 5

## The longest a row will wait for a clear moment before giving up on it.
## A death blackout out of a bad spawn is the case this exists for, and one
## is over well inside sixty frames even at the streaming frame rate.
const SETTLE_MAX := 60

static var _rows: Array = []
static var _state := "idle"
static var _note := ""
static var _runner: RefCounted = null


static func start(player: Node) -> Dictionary:
	## Returns immediately. Poll `report()` until it says "done".
	if _state == "running":
		return {"state": _state, "note": "a pass is already running"}
	if player == null or not is_instance_valid(player):
		return {"state": "idle", "note": "no player"}
	_rows = []
	_note = ""
	_state = "running"
	_runner = (load(SELF) as GDScript).new()
	_runner._drive(player)      ## deliberately not awaited: the eval must return
	return {"state": "running", "probes": _probeable().size()}


static func report() -> Dictionary:
	var bad: Array = []
	for r in _rows:
		if not bool((r as Dictionary)["ok"]):
			bad.append((r as Dictionary)["label"])
	return {
		"state": _state,
		"warm": not _note.begins_with("WARM-UP FAILED"),
		"note": _note,
		"ran": _rows.size(),
		"want": _probeable().size(),
		"failed": bad,
		"rows": _rows,
	}


static func restore(player: Node) -> Dictionary:
	## Put the player back the way he was found: nothing open, on his feet,
	## no key still held. Safe to call at any time, including after a crash
	## mid-pass -- which is the only reason it is public.
	if player == null or not is_instance_valid(player):
		return {"ok": false}
	for b in REG.bindings():
		var d := b as Dictionary
		_post(int(d["code"]), false)
	if String(player.menu_open) != "":
		_post(REG.escape_code(), true)
		_post(REG.escape_code(), false)
	return {"ok": true, "menu_open": player.menu_open,
		"crouching": player.crouching, "prone": player.prone}


# ------------------------------------------------------------------ internals

static func _probeable() -> Array:
	var out: Array = []
	for b in REG.bindings():
		if String((b as Dictionary)["live"]) != "none":
			out.append(b)
	return out


static func _post(code: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = down
	ev.echo = false
	Input.parse_input_event(ev)


static func _snap(p: Node) -> Dictionary:
	return {"menu_open": String(p.menu_open), "crouching": bool(p.crouching),
		"prone": bool(p.prone), "wheel_open": bool(p.wheel_open), "god": bool(p.god),
		"locked": bool(p.input_locked)}


static func _clean(s: Dictionary) -> bool:
	## `locked` belongs in here and not in a separate check. `Player._input`'s
	## very first line is `if input_locked: return`, so a press sent into a
	## blackout is not a press that failed -- it is a press that never
	## happened, and a moment when this prober has nothing to say.
	return String(s["menu_open"]) == "" and not bool(s["crouching"]) \
		and not bool(s["prone"]) and not bool(s["wheel_open"]) \
		and not bool(s["locked"])


func _wait(tree: SceneTree, frames: int) -> void:
	for i in range(frames):
		await tree.process_frame


func _settle(tree: SceneTree, player: Node) -> Dictionary:
	## Wait, bounded, for a moment when a key would actually be read: nothing
	## open, standing, and not in a blackout. Returns the snapshot it settled
	## on, or the last one it saw if it never settled.
	var s := _snap(player)
	var waited := 0
	while not _clean(s) and waited < SETTLE_MAX:
		if not bool(s["locked"]):
			restore(player)
		await _wait(tree, 3)
		waited += 3
		s = _snap(player)
	return s


func _tap(tree: SceneTree, code: int) -> void:
	_post(code, true)
	await _wait(tree, SETTLE)
	_post(code, false)
	await _wait(tree, 2)


func _warm(tree: SceneTree, player: Node, esc: int) -> bool:
	## THE FIRST PRESS OF A PASS CAN BE EATEN, and this cost the round that
	## wrote this file a false red. On a world that had just come up through
	## `front_door_done`, F1 -- the first row in the table -- did nothing at
	## all, while the same key pressed by hand a minute later worked fine. The
	## controller pass documents the mechanism: Pad.gd "swallows a frame of
	## edges on the way out so nothing fires the instant control returns", and
	## a synthetic press landing in that frame is spent on nothing.
	##
	## A false red is the harmless half. Had an INERT row been first instead,
	## the eaten press would have looked exactly like correct inertness and the
	## pass would have gone green for the wrong reason.
	##
	## So: spend the swallowed edge on Escape, which opens the settings menu
	## and closes it again, and refuse to judge a single binding until we have
	## watched a key go in and something come out.
	for i in range(4):
		await _tap(tree, esc)
		if String(player.menu_open) == "settings":
			await _tap(tree, esc)
			return String(player.menu_open) == ""
	return false


func _drive(player: Node) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		_state = "done"
		_note = "no scene tree"
		return
	## Whatever happens below, the player is put back before anyone sees him.
	var opening := _snap(player)
	if not _clean(opening):
		restore(player)
		await _wait(tree, SETTLE)
	var esc := REG.escape_code()
	var warm: bool = await _warm(tree, player, esc)
	if not warm:
		restore(player)
		await _wait(tree, SETTLE)
		_note = "WARM-UP FAILED: no key reached the player, so nothing below is evidence"
		_state = "done"
		return
	## ONE RETRY PER ROW. A blackout can open and shut between the settle and
	## the press, and a false red on a dev binding is exactly the alarm people
	## learn to ignore. A row that fails twice is a finding.
	var queue: Array = _probeable()
	var tries: Dictionary = {}
	var i := 0
	while i < queue.size():
		var b = queue[i]
		var d := b as Dictionary
		var row := {"label": String(d["label"]), "what": String(d["what"]),
			"kind": String(d["live"]), "ok": false, "saw": "", "why": ""}
		## WAIT FOR THE WORLD TO LET GO OF THE KEYBOARD before judging
		## anything. On the cold run that found this, the player DIED on spawn
		## -- a fatal drop out of `front_door_done(false)` -- and F1, first in
		## the table, was pressed into the death blackout and reported broken.
		## It was not broken. Every press in that window is dropped by
		## `Player._input`'s first line, in silence, and on an INERT row that
		## silence would have read as a pass.
		var before := await _settle(tree, player)
		if not _clean(before):
			row["why"] = "never got a clear moment to press it: %s" % [before]
			_rows.append(row)
			i += 1
			restore(player)
			await _wait(tree, SETTLE)
			continue
		var code := int(d["code"])
		var want := String(d["expect"])
		match String(d["live"]):
			"menu":
				await _tap(tree, code)
				var opened := _snap(player)
				await _tap(tree, code)
				var shut := _snap(player)
				row["saw"] = "%s -> %s" % [opened["menu_open"], shut["menu_open"]]
				row["ok"] = String(opened["menu_open"]) == want and String(shut["menu_open"]) == ""
				## F1 is the one that also flips god on and off with the panel.
				if want == "god":
					row["saw"] += " (god %s -> %s)" % [opened["god"], shut["god"]]
					row["ok"] = row["ok"] and bool(opened["god"]) and not bool(shut["god"])
			"menu1":
				await _tap(tree, code)
				var up := _snap(player)
				await _tap(tree, esc)
				var down := _snap(player)
				row["saw"] = "%s -> %s" % [up["menu_open"], down["menu_open"]]
				row["ok"] = String(up["menu_open"]) == want and String(down["menu_open"]) == ""
			"stance":
				await _tap(tree, code)
				var into := _snap(player)
				await _tap(tree, code)
				var out_of := _snap(player)
				row["saw"] = "%s %s -> %s (crouching %s -> %s)" % [want, into[want],
					out_of[want], into["crouching"], out_of["crouching"]]
				## Prone keeps `crouching` true on the way in -- stealth reads
				## it -- and both have to clear on the way back to standing.
				row["ok"] = bool(into[want]) and not bool(out_of[want]) \
					and not bool(out_of["crouching"]) and not bool(out_of["prone"])
			"hold":
				_post(code, true)
				await _wait(tree, SETTLE)
				var held := _snap(player)
				_post(code, false)
				await _wait(tree, SETTLE)
				var let_go := _snap(player)
				row["saw"] = "%s %s -> %s" % [want, held[want], let_go[want]]
				row["ok"] = bool(held[want]) and not bool(let_go[want])
			"inert":
				await _tap(tree, code)
				var after := _snap(player)
				row["saw"] = String(after["menu_open"])
				row["ok"] = _clean(after) and String(after["menu_open"]) == ""
		var after_all := _snap(player)
		if not bool(row["ok"]) or not _clean(after_all):
			restore(player)
			await _wait(tree, SETTLE)
		if not bool(row["ok"]):
			var n := int(tries.get(String(d["label"]), 0)) + 1
			tries[String(d["label"])] = n
			if bool(after_all["locked"]):
				row["why"] = "a blackout took this one"
			if n < 2:
				continue      ## same row, once more, after a fresh settle
			row["why"] = "%s (failed twice)" % row["why"]
		_rows.append(row)
		i += 1
	restore(player)
	await _wait(tree, SETTLE)
	var closing := _snap(player)
	_note = "left him at %s" % [closing]
	if not _clean(closing):
		_note = "DID NOT LEAVE HIM CLEAN: %s" % [closing]
	_state = "done"
