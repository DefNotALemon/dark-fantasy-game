extends SceneTree

# =============================================================================
# tests/DevInputTests.gd -- the dev bindings, held to account by machine.
# (2026-09-09, HARDEN. Queue item HARDEN #3.)
#
#   godot --headless --path . --script res://tests/DevInputTests.gd
#
# WHY THIS EXISTS. "A broken or shadowed dev input is round-blocking" is the
# oldest standing rule in this project, and until now the only way to honour it
# was to launch the world and press twelve keys by hand -- about twelve tool
# round trips a round, at the 6-8 FPS the game runs while terrain streams. That
# manual pass can only ever answer "the keys I remembered to try still work
# today". It cannot answer the question that actually bites: has anything
# QUIETLY TAKEN one of them.
#
# So this suite does not press keys. It reads the source and holds four files
# to one table:
#
#   Player.gd     -- the twenty-five keys the game claims, exactly
#   GodEditor.gd  -- the one arbitration point, and what it is allowed to eat
#   Pad.gd        -- the controller, which POSTS keys and so breaks silently
#                    the moment a binding moves
#   project.godot -- InputMap actions, of which the design says there are none
#
# WHAT WOULD MAKE THIS SUITE A LIE. Every check here is of the shape "scan the
# source, compare the set". A parser that quietly returns nothing would make
# every one of them pass -- the same fallback-shaped hole that hid three index
# defects behind the Road Net's 110/0 green on 2026-09-09. Two answers to that,
# both load-bearing:
#
#   * `parser` runs the pure functions over HAND-WRITTEN text with defects
#     planted in it -- a duplicate case, a KEY_ inside a comment, a KEY_ in a
#     string, a missing function -- and asserts they are found. The parser is
#     under test before it is trusted.
#   * every section that scans a real file asserts the scan CAME BACK WITH
#     SOMETHING, and how much, before asserting anything about what it found.
#
# SECTION CLAIMS: every section stakes its count before it runs an assertion,
# so a section killed by a runtime error surfaces as an unsettled claim rather
# than quietly taking its assertions out of the total with it.
# =============================================================================

const REG := preload("res://tests/DevInputRegistry.gd")

const MIN_ASSERTIONS := 108

var _pass := 0
var _fail := 0
var _claims: Dictionary = {}
var _counts: Dictionary = {}
var _section := ""


func claim(section: String, n: int) -> void:
	_section = section
	_claims[section] = n


func ok(cond: bool, what: String) -> void:
	_counts[_section] = int(_counts.get(_section, 0)) + 1
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL  [%s] %s" % [_section, what])


func same(a: String, b: String, what: String) -> void:
	ok(a == b, "%s (got '%s', want '%s')" % [what, a, b])


func read(path: String) -> String:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return ""
	var s := fa.get_as_text()
	fa.close()
	return s


func sorted_join(a: Array) -> String:
	var c := a.duplicate()
	c.sort()
	return ", ".join(PackedStringArray(c))


func _initialize() -> void:
	print("\n=== DevInputTests ===")


func _process(_d: float) -> bool:
	_t_table()
	_t_parser()
	_t_player()
	_t_god()
	_t_pad()
	_t_others()
	_t_inputmap()
	_t_live_spec()
	_t_no_input()
	_report()
	return true


func _report() -> void:
	for s in _claims:
		var want := int(_claims[s])
		var got := int(_counts.get(s, 0))
		if want != got:
			_fail += 1
			print("  FAIL  [claims] section '%s' claimed %d assertions, ran %d" % [s, want, got])
	print("\n--- %d passed, %d failed (floor %d) ---" % [_pass, _fail, MIN_ASSERTIONS])
	if _pass + _fail < MIN_ASSERTIONS:
		print("FAIL: only %d assertions ran" % (_pass + _fail))
		quit(1)
		return
	quit(1 if _fail > 0 else 0)


# ------------------------------------------------------------------- the table

func _t_table() -> void:
	claim("table", 14)
	var b := REG.bindings()
	ok(b.size() == 25, "twenty-five rows, one per match case in Player._input (got %d)" % b.size())
	var toks := {}
	var codes := {}
	var labels := {}
	var fielded := true
	var kinded := true
	var whyed := true
	var readable := true
	var described := true
	for r in b:
		var d := r as Dictionary
		for f in ["tok", "code", "label", "what", "live", "expect", "why"]:
			if not d.has(f):
				fielded = false
		if not REG.LIVE_KINDS.has(String(d.get("live", ""))):
			kinded = false
		## An unprobed row has to say what stops it -- otherwise "none" becomes
		## the place bindings go to stop being checked.
		if String(d.get("live", "")) == "none" and String(d.get("why", "")).length() < 20:
			whyed = false
		## `expect` means two different things and both have to be checked.
		## For a stance or a hold it is a PLAYER FIELD, and a probe that read a
		## field nobody declared would read null and pass. For a menu it is the
		## NAME the menu opens to. For anything else it must be empty, or a row
		## is carrying an expectation nothing will ever look at.
		var ex := String(d.get("expect", ""))
		var kd := String(d.get("live", ""))
		if kd in ["stance", "hold"] and not REG.READABLE.has(ex):
			readable = false
		if kd in ["menu", "menu1"] and ex == "":
			readable = false
		if kd in ["none", "inert"] and ex != "":
			readable = false
		if String(d.get("what", "")).length() < 12:
			described = false
		toks[String(d.get("tok", ""))] = true
		codes[int(d.get("code", -1))] = true
		labels[String(d.get("label", ""))] = true
	ok(fielded, "every row carries all seven fields")
	ok(kinded, "every row's live kind is one of %s" % [REG.LIVE_KINDS])
	ok(whyed, "every unprobed row says in a sentence what stops it being probed")
	ok(readable, "every expectation is a readable field, or a menu name, or absent")
	ok(described, "every row says what the key does")
	ok(toks.size() == b.size(), "no token appears twice (%d distinct of %d)" % [toks.size(), b.size()])
	ok(codes.size() == b.size(), "no keycode appears twice (%d distinct of %d)" % [codes.size(), b.size()])
	ok(labels.size() == b.size(), "no label appears twice")
	## The token and the integer have to agree, or the headless half and the
	## live half are checking two different keyboards.
	var agree := true
	var spot := {"KEY_F1": KEY_F1, "KEY_M": KEY_M, "KEY_K": KEY_K, "KEY_G": KEY_G,
		"KEY_APOSTROPHE": KEY_APOSTROPHE, "KEY_C": KEY_C, "KEY_X": KEY_X,
		"KEY_Q": KEY_Q, "KEY_ESCAPE": KEY_ESCAPE, "KEY_TAB": KEY_TAB}
	for t in spot:
		var row := REG.by_tok().get(t, {}) as Dictionary
		if row.is_empty() or int(row["code"]) != int(spot[t]):
			agree = false
	ok(agree, "the tokens and the keycodes are the same ten keys")
	## The brief this project is run from still says T is terrain and N is the
	## map. Neither key exists. The table is the source of truth; assert the
	## stale pair stays out of it so nobody re-adds them from the brief.
	ok(not REG.by_tok().has("KEY_T"), "no KEY_T in the table -- the task brief is stale about it")
	ok(not REG.by_tok().has("KEY_N"), "no KEY_N in the table -- likewise")
	var rel := REG.releases()
	ok(rel.size() == 2, "two keys do their real work on release")
	same(sorted_join([String((rel[0] as Dictionary)["tok"]), String((rel[1] as Dictionary)["tok"])]),
			"KEY_Q, KEY_V", "and they are the wheel and the camera")


# ------------------------------------------------------------------ the parser

func _t_parser() -> void:
	claim("parser", 18)
	## Planted text. Every trap in it is one this parser would otherwise fall
	## into on a real file: a KEY_ in a comment, a KEY_ in a string, a case
	## label that is really an expression, and a duplicated case.
	var fake := "\n".join([
		"extends Node",
		"",
		"func _input(event: InputEvent) -> void:",
		"\tif event is InputEventKey and event.pressed:",
		"\t\tmatch event.keycode:",
		"\t\t\tKEY_A:",
		"\t\t\t\tpass  ## KEY_ZZZ is only mentioned here",
		"\t\t\tKEY_B, KEY_C:",
		"\t\t\t\tprint(\"KEY_YYY\")",
		"\t\t\tKEY_A:",
		"\t\t\t\tpass",
		"\tif Input.is_key_pressed(KEY_D):",
		"\t\tpass",
		"",
		"func something_else() -> void:",
		"\tvar x := KEY_E",
	])
	var body := REG.func_body(fake, "_input")
	ok(body != "", "the body of a function that exists comes back")
	ok(body.contains("KEY_A"), "and it contains the match block")
	ok(not body.contains("KEY_E"), "and stops at the next top-level func")
	same(REG.func_body(fake, "_nope"), "", "a function that is not there comes back empty")
	var cases := REG.case_toks(body)
	same(sorted_join(cases), "KEY_A, KEY_A, KEY_B, KEY_C",
			"four case labels, the duplicate kept")
	ok(cases.size() == 4, "a doubled case is not deduped away (%d)" % cases.size())
	ok(not sorted_join(cases).contains("KEY_ZZZ"), "a KEY_ in a trailing comment is not a case")
	ok(not sorted_join(cases).contains("KEY_YYY"), "a KEY_ inside a string is not a case")
	ok(not sorted_join(cases).contains("KEY_D"), "a polled KEY_ is not a case")
	same(sorted_join(REG.polled_toks(fake)), "KEY_D", "polling is found, and only polling")
	same(sorted_join(REG.input_callbacks(fake)), "_input", "the callback is found by name")
	same(sorted_join(REG.input_callbacks("func _ready() -> void:\n\tpass")), "",
			"and a file with no callback reports none")
	var padfake := "\n".join([
		"\t_mirror(JOY_BUTTON_A, KEY_SPACE)   ## jump",
		"\t_tap(JOY_BUTTON_Y, KEY_I)",
		"\t_hold_key(KEY_SHIFT, _sprint)",
		"\t## _tap(JOY_BUTTON_Z, KEY_Z) -- commented out",
	])
	var posts := REG.pad_posts(padfake)
	ok(posts.size() == 3, "three posted buttons, the commented one included (%d)" % posts.size())
	same(String((posts[0] as Dictionary)["key"]), "KEY_SPACE", "the first is the jump mirror")
	same(String((posts[1] as Dictionary)["call"]), "_tap", "and the second is a tap")
	## project.godot's [input] section, and only that section.
	var cfg := "\n".join(["[application]", "config/name=\"x\"", "",
		"[input]", "jump={\"deadzone\":0.5}", "", "[rendering]", "aa=2"])
	same(sorted_join(REG.project_actions(cfg)), "jump", "one action, read from [input] alone")
	same(sorted_join(REG.project_actions("[application]\nconfig/name=\"x\"")), "",
			"and a project with no [input] section has no actions")
	ok(REG.toks_in(fake).size() >= 5, "the blunt token scan sees everything, comments and all")


# ------------------------------------------------------------------- Player.gd

func _t_player() -> void:
	claim("player", 16)
	var src := read(REG.OWNER)
	ok(src.length() > 100000, "Player.gd was read and is the real one (%d bytes)" % src.length())
	var body := REG.func_body(src, "_input")
	ok(body.length() > 4000, "its _input body was found (%d bytes)" % body.length())
	var cases := REG.case_toks(body)
	ok(cases.size() >= 20, "the match block has %d case labels" % cases.size())
	var want := {}
	for r in REG.bindings():
		want[String((r as Dictionary)["tok"])] = true
	var got := {}
	var doubled: Array = []
	for c in cases:
		if got.has(c):
			doubled.append(c)
		got[c] = true
	same(sorted_join(doubled), "", "no key is claimed twice in the match block")
	var missing: Array = []
	for t in want:
		if not got.has(t):
			missing.append(t)
	var extra: Array = []
	for t in got:
		if not want.has(t):
			extra.append(t)
	## These two are the whole point of the suite.
	same(sorted_join(missing), "",
			"every key in the table is still handled in Player._input")
	same(sorted_join(extra), "",
			"and Player._input handles no key the table has not been told about")
	ok(got.size() == want.size(), "%d handled, %d recorded" % [got.size(), want.size()])
	## The two release arms live above the match block, so they are found by a
	## different shape and would otherwise read as missing.
	var rels_ok := true
	for r in REG.releases():
		var t := String((r as Dictionary)["tok"])
		if not body.contains("not event.pressed and (event as InputEventKey).keycode == %s" % t):
			rels_ok = false
	ok(rels_ok, "both release arms are still there, in their own elif")
	## Player's OTHER input callback must stay out of the keyboard, or there
	## are two places to look and the table only covers one.
	var un := REG.func_body(src, "_unhandled_input")
	ok(un != "", "_unhandled_input exists")
	same(sorted_join(REG.toks_in(un)), "", "and takes no key at all")
	## The keys Player reaches for outside _input: WASD for movement (polled or
	## read elsewhere) is fine; a second match block is not.
	var outside := REG.toks_in(src.replace(body, "").replace(un, ""))
	var unexpected: Array = []
	for t in outside:
		if not want.has(t) and not ["KEY_W", "KEY_A", "KEY_S", "KEY_D", "KEY_SHIFT"].has(t):
			unexpected.append(t)
	same(sorted_join(unexpected), "",
			"and mentions no key outside _input beyond the movement set")
	same(sorted_join(REG.input_callbacks(src)), "_input, _unhandled_input",
			"Player has exactly two input callbacks")
	## First refusal. If this line goes, the editor and the game both act on
	## the same key and nothing in the table can tell you.
	##
	## This was one assertion, `src.contains("eat_input")`, and a mutation that
	## replaced the actual CALL with `godmode.map_over()` walked straight
	## through it -- because the words "eat_input" still sat in two comments
	## further down. An assertion that can pass through a door other than the
	## one it is aimed at is not an assertion. So: the exact call, inside
	## _input, and BEFORE the match block, because arbitration that happens
	## after the game has already acted is not arbitration.
	var refusal := body.find("if godmode != null and godmode.eat_input(event):")
	var matched := body.find("match event.keycode:")
	ok(refusal >= 0, "the god editor is still called for first refusal on every event")
	ok(refusal >= 0 and matched > refusal,
			"and it is called before the match block, not after (%d vs %d)" % [refusal, matched])
	ok(body.contains("if input_locked:"), "with the blackout guard still at the top")
	ok(body.contains("and event.pressed and not event.echo"),
			"and the match block still refuses key repeats")


# --------------------------------------------------------- the one arbitration

func _t_god() -> void:
	claim("god", 13)
	var src := read(REG.GOD)
	ok(src.length() > 10000, "GodEditor.gd was read (%d bytes)" % src.length())
	var body := REG.func_body(src, "eat_input")
	ok(body.length() > 800, "eat_input was found (%d bytes)" % body.length())
	var cases := REG.case_toks(body)
	ok(cases.size() >= 12, "the panel's match block has %d case labels" % cases.size())
	var reg := REG.by_tok()
	var eats := {}
	for e in REG.god_eats():
		eats[String((e as Dictionary)["tok"])] = e
	var only := {}
	for t in REG.god_only():
		only[t] = true
	var unlisted: Array = []
	for c in cases:
		if not eats.has(c) and not only.has(c):
			unlisted.append(c)
	same(sorted_join(unlisted), "",
			"every key the panel takes is either a recorded swallow or a panel-only key")
	var vanished: Array = []
	for t in eats:
		if not cases.has(t):
			vanished.append(t)
	same(sorted_join(vanished), "", "and every recorded swallow is still in the match")
	## A swallow of a registry key is a deliberate shadow. Assert the set is
	## exactly what it was, so widening it is a decision and not a diff.
	var overlap: Array = []
	for t in eats:
		if reg.has(t):
			overlap.append(t)
	same(sorted_join(overlap), "KEY_B, KEY_CTRL, KEY_ESCAPE, KEY_F, KEY_F2, KEY_SPACE",
			"six of Player's keys are shadowed while the panel is up, and only six")
	## The conditional ones are the subtlety: an unconditional swallow of Space
	## would ground the spectator camera, which polls it.
	var conds_ok := true
	for t in eats:
		var c := String((eats[t] as Dictionary)["cond"])
		if c != "" and not body.contains(c):
			conds_ok = false
	ok(conds_ok, "the conditional swallows still carry their guards")
	ok(body.contains("return spectating()"),
			"Space and Ctrl are swallowed only while spectating")
	ok(body.contains("if k.shift_pressed:"), "and B only with Shift held")
	## F1 must fall THROUGH, or the panel can never be opened again.
	ok(src.contains("KEY_F1") and src.contains("return false   ## Player's own KEY_F1 case opens the panel"),
			"F1 is explicitly handed back to Player")
	ok(body.contains("if map_over():"), "the map over the panel takes precedence over both")
	same(sorted_join(REG.input_callbacks(src)), "",
			"and the panel declares no input callback of its own -- Player feeds it")
	ok(not reg.has("KEY_S") and cases.has("KEY_S"),
			"Ctrl+S saves the plan and is the panel's alone")


# ----------------------------------------------------------------- the pad

func _t_pad() -> void:
	claim("pad", 12)
	var src := read(REG.PAD)
	ok(src.length() > 4000, "Pad.gd was read (%d bytes)" % src.length())
	var posts := REG.pad_posts(src)
	ok(posts.size() >= 10, "the controller posts %d buttons' worth of keys" % posts.size())
	var reg := REG.by_tok()
	var extra := REG.pad_extra()
	## THE POINT OF THIS SECTION. Pad.gd does not handle keys, it MANUFACTURES
	## them -- it posts the very same InputEventKey the keyboard produces. So
	## the day a dev binding moves, the controller keeps posting the old key
	## into a match block that no longer has a case for it, and NOTHING fails:
	## the button just quietly stops doing anything. There is no other check in
	## the project that would catch that.
	var orphan: Array = []
	for p in posts:
		var k := String((p as Dictionary)["key"])
		if not reg.has(k) and not extra.has(k):
			orphan.append(k)
	same(sorted_join(orphan), "",
			"every key the controller posts is a key Player still handles")
	var btns := {}
	var twice: Array = []
	for p in posts:
		var b := String((p as Dictionary)["btn"])
		if btns.has(b):
			twice.append(b)
		btns[b] = true
	same(sorted_join(twice), "", "and no button is mapped twice")
	## Two buttons on one key is fine and deliberate (View and the touchpad
	## both open the map), so it is asserted rather than merely tolerated.
	var per := {}
	for p in posts:
		var k := String((p as Dictionary)["key"])
		per[k] = int(per.get(k, 0)) + 1
	ok(int(per.get("KEY_M", 0)) == 2, "the map is on two buttons, for Xbox and for PlayStation")
	## Held vs tapped is not cosmetic: the wheel, the dash and the camera are
	## POLLED or read on release, and a tap would never be seen.
	var held := {}
	for p in posts:
		if String((p as Dictionary)["call"]) == "_mirror":
			held[String((p as Dictionary)["key"])] = true
	ok(held.has("KEY_Q"), "the item wheel is HELD, not tapped -- it is read on release")
	ok(held.has("KEY_V"), "so is the camera")
	ok(held.has("KEY_SPACE") and held.has("KEY_CTRL"), "so are jump and dash, which are polled")
	ok(held.has("KEY_C"), "and crouch, which swimming polls")
	var tapped := {}
	for p in posts:
		if String((p as Dictionary)["call"]) == "_tap":
			tapped[String((p as Dictionary)["key"])] = true
	ok(tapped.has("KEY_F1"), "the god editor is a tap")
	ok(tapped.has("KEY_ESCAPE") and tapped.has("KEY_I"), "as are pause and inventory")
	same(sorted_join(REG.input_callbacks(src)), "",
			"and the pad declares no input callback either -- it only posts")


# -------------------------------------------------------------- everyone else

func _t_others() -> void:
	claim("others", 15)
	var reg := REG.by_tok()
	var allowed := {}
	for s in REG.shared():
		allowed[String((s as Dictionary)["file"])] = (s as Dictionary)["toks"]
	var polls := {}
	for s in REG.poll_ok():
		polls[String((s as Dictionary)["file"])] = (s as Dictionary)["toks"]
	var dir := DirAccess.open("res://scripts")
	ok(dir != null, "res://scripts is readable")
	if dir == null:
		for i in range(13):
			ok(false, "no scripts directory to scan")
		return
	var names := dir.get_files()
	ok(names.size() > 20, "%d scripts to scan" % names.size())
	var scanned := 0
	var claimers: Array = []
	var pollers: Array = []
	var cb_files: Array = []
	for n in names:
		if not n.ends_with(".gd"):
			continue
		var rel := "scripts/%s" % n
		var src := read("res://%s" % rel)
		if src == "":
			continue
		scanned += 1
		var cbs := REG.input_callbacks(src)
		if not cbs.is_empty():
			cb_files.append(rel)
		if rel == "scripts/Player.gd":
			continue
		## A registry key taken from an _input-family callback by anyone but
		## Player is a shadow unless it is on the list with a reason.
		for cb in cbs:
			for t in REG.case_toks(REG.func_body(src, cb)) + REG.toks_in(REG.func_body(src, cb)):
				if reg.has(t) and not (allowed.get(rel, []) as Array).has(t):
					if not claimers.has("%s:%s" % [rel, t]):
						claimers.append("%s:%s" % [rel, t])
		## Polling is invisible to event consumption -- a quieter second claim.
		for t in REG.polled_toks(src):
			if reg.has(t) and not (polls.get(rel, []) as Array).has(t):
				if not pollers.has("%s:%s" % [rel, t]):
					pollers.append("%s:%s" % [rel, t])
	ok(scanned > 20, "%d scripts actually opened -- the scan is not empty" % scanned)
	same(sorted_join(claimers), "",
			"no script outside the allowlist takes a dev key from an input callback")
	same(sorted_join(pollers), "",
			"and none polls one either")
	## The allowlist has to still be true, or it is just a hole.
	var menu := read(REG.MENU)
	ok(menu.length() > 2000, "MainMenu.gd was read")
	var mbody := REG.func_body(menu, "_input")
	ok(mbody != "", "and it does have an _input")
	var mtoks := REG.toks_in(mbody)
	ok(mtoks.has("KEY_F1"), "the front door really does claim F1")
	ok(mtoks.has("KEY_ESCAPE"), "and Escape")
	ok(mtoks.has("KEY_SPACE"), "and Space, which activates the highlighted card")
	## Derived from the allowlist rather than written out again here: two
	## copies of the same list is how the third key stayed off one of them.
	var shared_extra: Array = []
	for t in mtoks:
		if reg.has(t) and not (allowed.get("scripts/MainMenu.gd", []) as Array).has(t):
			shared_extra.append(t)
	same(sorted_join(shared_extra), "", "and nothing else of Player's")
	ok(menu.contains("input_locked"), "and Player is locked out the whole time it is up")
	var cam := read(REG.CAM)
	same(sorted_join(REG.polled_toks(cam)),
			"KEY_A, KEY_CTRL, KEY_D, KEY_S, KEY_SHIFT, KEY_SPACE, KEY_W",
			"the spectator camera polls exactly the fly set")
	ok(cb_files.size() == 2, "only two files in scripts/ declare an input callback at all (%d)"
			% cb_files.size())
	same(sorted_join(cb_files), "scripts/MainMenu.gd, scripts/Player.gd",
			"and they are the front door and the player")


# --------------------------------------------------------------- project.godot

func _t_inputmap() -> void:
	claim("inputmap", 5)
	var cfg := read("res://project.godot")
	ok(cfg.length() > 200, "project.godot was read (%d bytes)" % cfg.length())
	ok(cfg.contains("config_version"), "and it is the real project file")
	var actions := REG.project_actions(cfg)
	## The controller pass decided against InputMap actions outright: they
	## would be a second, competing definition of every control, and an action
	## bound to F1 is a shadow no source scan of Player.gd could ever see.
	same(sorted_join(actions), "", "the project declares no InputMap actions (%d)" % actions.size())
	ok(not cfg.contains("[input]") or actions.is_empty(),
			"so nothing can be bound behind the table's back")
	ok(not cfg.contains("physical_keycode"), "and no keycode is bound in the project file")


# ------------------------------------------------------------- the live prober

func _t_live_spec() -> void:
	claim("live", 17)
	var b := REG.bindings()
	var kinds := {}
	for r in b:
		var k := String((r as Dictionary)["live"])
		kinds[k] = int(kinds.get(k, 0)) + 1
	ok(int(kinds.get("menu", 0)) == 7, "seven keys toggle a menu open and shut (%d)" % kinds.get("menu", 0))
	ok(int(kinds.get("menu1", 0)) == 2, "two open one without toggling it shut")
	ok(int(kinds.get("stance", 0)) == 2, "two move the stance")
	ok(int(kinds.get("hold", 0)) == 1, "one is a hold")
	ok(int(kinds.get("inert", 0)) == 2, "two must do nothing at all from a clean start")
	ok(int(kinds.get("none", 0)) == 11, "and eleven are off the live pass with a reason")
	var probeable := 0
	for r in b:
		if String((r as Dictionary)["live"]) != "none":
			probeable += 1
	ok(probeable == 14, "fourteen rows can be driven live (%d)" % probeable)
	## More than the twelve-key manual pass covered, which is the trade this
	## whole item was taken for.
	ok(probeable >= 12, "which is at least what the hand pass used to cover")
	var menus := {}
	for r in b:
		var d := r as Dictionary
		if String(d["live"]) in ["menu", "menu1"]:
			menus[String(d["expect"])] = int(menus.get(String(d["expect"]), 0)) + 1
	same(sorted_join(menus.keys()), "creative, god, grass, map, settings, sky, spawn, tab",
			"the eight menu names the prober will look for")
	ok(int(menus.get("tab", 0)) == 2, "Tab and I both land on the tab menu")
	var live := read("res://tests/DevInputLive.gd")
	ok(live.length() > 2000, "the prober was read (%d bytes)" % live.length())
	## THE ASSERTION THAT KEEPS THE TABLE SINGULAR. If the prober carried its
	## own keycodes it could drift from the registry silently, and then the
	## live pass and the headless pass would be checking two different
	## keyboards -- which is the failure this whole file exists to prevent.
	same(sorted_join(REG.toks_in(live)), "",
			"and it names no key of its own -- it can only press what the table lists")
	ok(live.contains("DevInputRegistry.gd"), "because it loads the table by path")
	ok(live.contains("Input.parse_input_event"), "and presses real key events")
	ok(live.contains("restore"), "and puts the player back where it found him")
	## The first synthetic press of a pass can be swallowed -- Pad.gd eats a
	## frame of edges coming out of input_locked -- so the prober has to watch
	## a key go in and something come out before it judges any binding. Without
	## it, whichever row is first gets a false red, or, if it is an inert row,
	## a false GREEN.
	ok(live.contains("func _warm(") and live.contains("WARM-UP FAILED"),
			"and refuses to judge anything until it has seen a key get through")
	## `Player._input` returns on its first line while `input_locked` is true.
	## A press into a blackout is not a press that failed; it is a press that
	## never happened. The prober has to know that, or a death on spawn reads
	## as a broken binding -- and on an inert row, as a working one.
	ok(live.contains("input_locked") and live.contains("func _settle("),
			"and waits out a blackout rather than judging a key it never delivered")


# ------------------------------------------------------- the rules, in source

func _t_no_input() -> void:
	claim("no_input", 8)
	## The standing rule: a file that claims to add no binding says so here,
	## against its own source, rather than in a ledger line nobody can re-run.
	## This suite itself is deliberately NOT in the set: it is a SceneTree that
	## never joins the game's tree, and it has to quote the very needles below
	## in order to look for them, so scanning itself would always find them.
	var files := {
		"res://tests/DevInputRegistry.gd": true,
		"res://tests/DevInputLive.gd": true,
	}
	for path in files:
		var src := read(path)
		ok(src.length() > 1000, "%s was read (%d bytes)" % [path.get_file(), src.length()])
		var banned := ["func _input(", "func _unhandled_input(", "func _shortcut_input(",
			"func _unhandled_key_input(", "func _gui_input(", "InputMap.add_action"]
		var hit := ""
		for t in banned:
			if src.contains(t):
				hit = t
				break
		same(hit, "", "%s declares no input callback and registers no action" % path.get_file())
		## And nothing here is a Node that could be added to a tree and start
		## receiving input by accident.
		ok(not src.contains("extends Node\n") and not src.contains("extends Control"),
				"%s is not a Node" % path.get_file())
		ok(not src.contains("set_process_input(true)"),
				"%s turns no input processing on" % path.get_file())
