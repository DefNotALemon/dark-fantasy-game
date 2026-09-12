extends RefCounted

# =============================================================================
# tests/DevInputRegistry.gd -- what every dev key IS, written down once.
# (2026-09-09, HARDEN.)
#
# Loaded by PATH, never by class_name:
#
#     const REG := preload("res://tests/DevInputRegistry.gd")
#
# so nothing here depends on the editor's global class table and a headless
# run needs no filesystem scan to see it.
#
# Two consumers, and they pull in opposite directions on purpose:
#
#   tests/DevInputTests.gd -- headless. Holds Player.gd, GodEditor.gd, Pad.gd
#     and project.godot to account against this table, AND this table to
#     account against them. A key added to the game with no row here is red;
#     a row here with no key in the game is red as well.
#
#   tests/DevInputLive.gd -- inside the running game. Drives every row that
#     says how it can be seen, in ONE pass, and reports what it saw.
#
# The standing round rule is that every dev affordance records its binding.
# THIS FILE is where it is recorded. A ledger line can only ever say that a
# human looked once; this says it every time the suite runs.
#
# The table is deliberately the whole of `Player._input`'s match block and not
# just the interesting half. A binding that nobody thinks of as a dev key --
# the number rows, Tab, Alt -- is exactly the one a new feature will quietly
# take, and the collision is only visible if the boring rows are here too.
#
# This file adds no input handling and registers no InputMap action.
# DevInputTests asserts that against this source.
# =============================================================================

const OWNER := "res://scripts/Player.gd"
const PAD := "res://scripts/Pad.gd"
const GOD := "res://scripts/GodEditor.gd"
const CAM := "res://scripts/EditorCam.gd"
const MENU := "res://scripts/MainMenu.gd"

## Every callback through which a Godot node can take a key.
const INPUT_FUNCS := ["_input", "_unhandled_input", "_unhandled_key_input",
		"_shortcut_input", "_gui_input"]

## How a row can be SEEN from outside, in the running game:
##   "menu"   -- `_toggle_menu`: one press opens it to `expect`, the next shuts
##   "menu1"  -- opens to `expect` but does NOT toggle shut; Escape closes it
##   "stance" -- moves the `expect` flag and comes back on a second press
##   "hold"   -- `expect` is true while the key is held, false again on release
##   "inert"  -- from a clean standing start this key must change NOTHING
##   "none"   -- deliberately not driven live; `why` has to say what stops it
const LIVE_KINDS := ["menu", "menu1", "stance", "hold", "inert", "none"]

## The player fields the live prober is allowed to read. Anything a row names
## as `expect` has to be one of these, so a typo in the table cannot quietly
## become a probe that reads `null` and passes.
const READABLE := ["menu_open", "crouching", "prone", "wheel_open", "god"]


static func bindings() -> Array:
	## `tok` is the token as it appears in the source; `code` is the same thing
	## as an integer, for the live prober. Order is the order of the match
	## block in Player.gd, so a diff of the two reads straight down.
	return [
		{"tok": "KEY_CTRL", "code": KEY_CTRL, "label": "Ctrl",
			"what": "dash -- and descend while god-flying",
			"live": "none", "expect": "",
			"why": "a dash needs floor, no mount and no menu, and leaves no latch behind to read"},
		{"tok": "KEY_F1", "code": KEY_F1, "label": "F1",
			"what": "THE GOD EDITOR -- opens the panel and turns god on",
			"live": "menu", "expect": "god", "why": ""},
		{"tok": "KEY_F2", "code": KEY_F2, "label": "F2",
			"what": "drop in -- the body comes to the spectator camera and you land in it",
			"live": "inert", "expect": "",
			"why": "guarded on the god panel being visible, so with it shut F2 must do nothing"},
		{"tok": "KEY_SPACE", "code": KEY_SPACE, "label": "Space",
			"what": "jump; in god, a double tap toggles flight",
			"live": "none", "expect": "",
			"why": "a jump leaves the floor -- the probe would be judging physics, not a binding"},
		{"tok": "KEY_F", "code": KEY_F, "label": "F",
			"what": "get out from under a fallen trunk; ten seconds pinned and it reloads the save",
			"live": "none", "expect": "",
			"why": "DESTRUCTIVE -- one branch of it reloads the last save"},
		{"tok": "KEY_ALT", "code": KEY_ALT, "label": "Alt",
			"what": "sheathe / draw the sword",
			"live": "none", "expect": "",
			"why": "only legible with a sword as the current weapon"},
		{"tok": "KEY_B", "code": KEY_B, "label": "B",
			"what": "DROP the hovered item at your feet",
			"live": "inert", "expect": "",
			"why": "guarded on the tab menu being open on the inventory page over an item"},
		{"tok": "KEY_Q", "code": KEY_Q, "label": "Q",
			"what": "THE ITEM WHEEL -- hold, drag toward a slot, release to use it",
			"live": "hold", "expect": "wheel_open", "why": ""},
		{"tok": "KEY_E", "code": KEY_E, "label": "E",
			"what": "INTERACT -- grab, pick up, pack a bedroll, gather rock, hoist a log, light and feed a fire, drink",
			"live": "none", "expect": "",
			"why": "needs something in reach; a probe on empty ground proves nothing either way"},
		{"tok": "KEY_M", "code": KEY_M, "label": "M",
			"what": "THE MAP (the mob menu it used to open moved to K)",
			"live": "menu", "expect": "map", "why": ""},
		{"tok": "KEY_K", "code": KEY_K, "label": "K",
			"what": "the spawn menu",
			"live": "menu", "expect": "spawn", "why": ""},
		{"tok": "KEY_G", "code": KEY_G, "label": "G",
			"what": "the creative / build menu",
			"live": "menu", "expect": "creative", "why": ""},
		{"tok": "KEY_V", "code": KEY_V, "label": "V",
			"what": "camera: FP -> TP -> shoulder swap; hold 1.5 s to come back to first person",
			"live": "none", "expect": "",
			"why": "the work is on the RELEASE and it walks the camera round a cycle -- putting it back costs more than the probe proves"},
		{"tok": "KEY_C", "code": KEY_C, "label": "C",
			"what": "CROUCH; from prone it lifts you one stance, to the crouch",
			"live": "stance", "expect": "crouching", "why": ""},
		{"tok": "KEY_X", "code": KEY_X, "label": "X",
			"what": "PRONE; from prone it brings you all the way back to your feet",
			"live": "stance", "expect": "prone", "why": ""},
		{"tok": "KEY_5", "code": KEY_5, "label": "5",
			"what": "quick restart -- reloads the whole world scene",
			"live": "none", "expect": "",
			"why": "DESTRUCTIVE -- it reloads the current scene out from under the probe"},
		{"tok": "KEY_TAB", "code": KEY_TAB, "label": "Tab",
			"what": "the tab menu, on whichever page it was left",
			"live": "menu1", "expect": "tab", "why": ""},
		{"tok": "KEY_I", "code": KEY_I, "label": "I",
			"what": "the tab menu, on the inventory page",
			"live": "menu1", "expect": "tab", "why": ""},
		{"tok": "KEY_1", "code": KEY_1, "label": "1",
			"what": "tab page: inventory",
			"live": "none", "expect": "",
			"why": "only acts while the tab menu is already up"},
		{"tok": "KEY_2", "code": KEY_2, "label": "2",
			"what": "tab page: stats",
			"live": "none", "expect": "",
			"why": "only acts while the tab menu is already up"},
		{"tok": "KEY_3", "code": KEY_3, "label": "3",
			"what": "tab page: progression",
			"live": "none", "expect": "",
			"why": "only acts while the tab menu is already up"},
		{"tok": "KEY_4", "code": KEY_4, "label": "4",
			"what": "tab page: bestiary",
			"live": "none", "expect": "",
			"why": "only acts while the tab menu is already up"},
		{"tok": "KEY_APOSTROPHE", "code": KEY_APOSTROPHE, "label": "'",
			"what": "the SKY menu -- time, season, weather, lightning, aurora",
			"live": "menu", "expect": "sky", "why": ""},
		{"tok": "KEY_ESCAPE", "code": KEY_ESCAPE, "label": "Esc",
			"what": "closes whatever is open; with nothing open, the settings menu",
			"live": "menu", "expect": "settings", "why": ""},
	]


static func releases() -> Array:
	## The two keys whose real work happens when you LET GO. They are separate
	## `elif` arms above the match block, not match cases, so the source check
	## has to look for them separately or it will call them missing.
	return [
		{"tok": "KEY_Q", "what": "closes the wheel and uses the slot, or quick-adds on a tap"},
		{"tok": "KEY_V", "what": "cycles the camera; a 1.5 s hold is consumed in _physics_process instead"},
	]


static func god_eats() -> Array:
	## Keys the GOD PANEL takes off Player while it is up. `GodEditor.eat_input`
	## is the ONE arbitration point in the game, and this is its inventory.
	## `cond` is the guard the swallow is behind -- the conditional ones are the
	## whole subtlety, because an unconditional swallow of Space would ground
	## the spectator camera.
	return [
		{"tok": "KEY_F2", "cond": "", "what": "drop in -- the panel owns it outright"},
		{"tok": "KEY_B", "cond": "k.shift_pressed", "what": "Shift+B brings the body here; plain B falls through to Player's drop"},
		{"tok": "KEY_F", "cond": "", "what": "flips the mouse between looking and being a cursor"},
		{"tok": "KEY_SPACE", "cond": "spectating()", "what": "swallowed only while spectating, so the parked body never banks a jump"},
		{"tok": "KEY_CTRL", "cond": "spectating()", "what": "same, for the dash"},
		{"tok": "KEY_ESCAPE", "cond": "", "what": "closes the panel; while typing it drops focus first and nothing else gets through"},
	]


static func god_only() -> Array:
	## Keys the panel uses that Player never claims. They are listed so that a
	## future Player binding on one of them shows up as a NEW collision rather
	## than as business as usual.
	return ["KEY_ENTER", "KEY_KP_ENTER", "KEY_BACKSPACE", "KEY_DELETE", "KEY_R",
		"KEY_H", "KEY_P", "KEY_BRACKETLEFT", "KEY_BRACKETRIGHT",
		"KEY_PAGEUP", "KEY_PAGEDOWN", "KEY_S"]


static func shared() -> Array:
	## The only scripts other than Player allowed to take a registry key from
	## an `_input`-family callback, and the reason each is allowed to.
	return [
		{"file": "scripts/MainMenu.gd", "toks": ["KEY_F1", "KEY_ESCAPE", "KEY_SPACE"],
			"why": "the front-door card owns the keyboard; Player is input_locked the whole time it is up, and Pad.gd sleeps too, so the three keys it shares with the game can never both fire. Space is the one that is easy to miss -- it activates the highlighted card, and it was not on this list until the suite's own second run named it"},
	]


static func poll_ok() -> Array:
	## Scripts allowed to POLL a registry key with Input.is_key_pressed.
	## Polling is invisible to event consumption, so it is a second, quieter
	## way to claim a key and it needs its own allowlist.
	return [
		{"file": "scripts/EditorCam.gd", "toks": ["KEY_SPACE", "KEY_CTRL", "KEY_SHIFT"],
			"why": "god fly: up, down and boost, read by polling on purpose -- which is exactly why GodEditor swallows the events"},
	]


static func pad_extra() -> Array:
	## Keys Pad.gd posts that are NOT in the registry, with the reason.
	return ["KEY_SHIFT", "KEY_F", "KEY_E"]


# ----------------------------------------------------------------- pure source
# Everything below is a pure function of text. No FileAccess, no tree, no
# engine state -- so the suite can feed them a hand-written string and watch
# them find a planted defect, rather than only ever running them on the truth.

static func func_body(src: String, fname: String) -> String:
	## The body of `func <fname>(` -- every following line that is blank or
	## starts with a tab. Returns "" when the function is not there at all,
	## which callers must treat as a failure and not as an empty body.
	var lines := src.split("\n")
	var head := "func %s(" % fname
	var i := 0
	while i < lines.size() and not lines[i].begins_with(head):
		i += 1
	if i >= lines.size():
		return ""
	var body := PackedStringArray()
	i += 1
	while i < lines.size():
		var ln := lines[i]
		if ln.strip_edges() == "":
			body.append(ln)
			i += 1
			continue
		## Indentation is NOT always a tab. MainMenu.gd is space-indented, and
		## a tab-only rule quietly returned an EMPTY body for it -- which made
		## every cross-script collision check pass by finding nothing at all.
		## Caught by this suite's own first run, which is the shape the header
		## warns about: a scan that comes back empty agrees with everything.
		if not (ln.begins_with("\t") or ln.begins_with(" ")):
			break
		body.append(ln)
		i += 1
	return "\n".join(body)


static func case_toks(body: String) -> Array:
	## KEY_ tokens standing as `match` CASE LABELS: tabs, one or more KEY_
	## names separated by commas, a colon, nothing else but a comment.
	## Duplicates are KEPT -- one key claimed twice in one match block is
	## precisely the thing worth seeing.
	var out: Array = []
	var rx := RegEx.new()
	rx.compile("^[ \\t]+(KEY_[A-Z0-9_]+(?:[ \\t]*,[ \\t]*KEY_[A-Z0-9_]+)*)[ \\t]*:[ \\t]*(##.*)?$")
	for ln in body.split("\n"):
		var m := rx.search(ln)
		if m == null:
			continue
		for tok in m.get_string(1).split(","):
			out.append(tok.strip_edges())
	return out


static func toks_in(text: String) -> Array:
	## Every distinct KEY_ token anywhere in the text, sorted.
	var seen := {}
	var rx := RegEx.new()
	rx.compile("KEY_[A-Z0-9_]+")
	for m in rx.search_all(text):
		seen[m.get_string()] = true
	var out: Array = seen.keys()
	out.sort()
	return out


static func polled_toks(text: String) -> Array:
	## KEY_ tokens read through Input.is_key_pressed(...), sorted.
	var seen := {}
	var rx := RegEx.new()
	rx.compile("is_key_pressed\\([ \\t]*(KEY_[A-Z0-9_]+)")
	for m in rx.search_all(text):
		seen[m.get_string(1)] = true
	var out: Array = seen.keys()
	out.sort()
	return out


static func input_callbacks(src: String) -> Array:
	var out: Array = []
	for f in INPUT_FUNCS:
		if src.contains("func %s(" % f):
			out.append(f)
	return out


static func pad_posts(src: String) -> Array:
	## [{"call": "_mirror"|"_tap", "btn": "JOY_BUTTON_A", "key": "KEY_SPACE"}]
	## -- what the controller actually puts on the input queue.
	var out: Array = []
	var rx := RegEx.new()
	rx.compile("(_mirror|_tap)\\([ \\t]*(JOY_[A-Z0-9_]+)[ \\t]*,[ \\t]*(KEY_[A-Z0-9_]+)[ \\t]*\\)")
	for m in rx.search_all(src):
		out.append({"call": m.get_string(1), "btn": m.get_string(2), "key": m.get_string(3)})
	return out


static func project_actions(cfg: String) -> Array:
	## Custom InputMap action names declared in project.godot's [input]
	## section. The controller pass decided against InputMap actions outright
	## -- "adding them would have created a second, competing definition of
	## every control" -- so the count this is checked against is zero.
	var out: Array = []
	var in_input := false
	for ln in cfg.split("\n"):
		var s := ln.strip_edges()
		if s.begins_with("["):
			in_input = (s == "[input]")
			continue
		if not in_input or s == "" or s.begins_with(";"):
			continue
		var eq := s.find("=")
		if eq > 0:
			out.append(s.substr(0, eq).strip_edges())
	return out


static func escape_code() -> int:
	## The one key the live prober needs to name without having a row in hand:
	## it is how a menu that does not toggle shut gets closed again. Looked up
	## rather than written down, so the prober can stay free of keycodes.
	return int((by_tok()["KEY_ESCAPE"] as Dictionary)["code"])


static func by_tok() -> Dictionary:
	var d := {}
	for b in bindings():
		d[String((b as Dictionary)["tok"])] = b
	return d
