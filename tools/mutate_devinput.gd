extends SceneTree

# =============================================================================
# tools/mutate_devinput.gd -- is DevInputTests actually load-bearing?
#
#   godot --headless --path . --script res://tools/mutate_devinput.gd
#
# A green suite is evidence about the suite. THIS one is almost entirely of the
# shape "scan the source, compare the set", and that shape fails OPEN: a parser
# that comes back with nothing agrees with everything. It had that exact bug on
# its first run -- MainMenu.gd is space-indented and the body reader wanted a
# tab, so every cross-script collision check was passing on an empty scan.
#
# So every claim the suite makes gets a mutation that ought to break it, and a
# mutation that SURVIVES is a finding: a missing test, a redundancy, or dead
# code. It is written in GDScript rather than as the usual tools/mutate_*.py
# only because it has to drive the same engine binary either way.
#
# Each mutation edits a REAL file in the tree and puts it straight back.
# Player.gd carries thousands of lines of Lemon's uncommitted work, so every
# file is length- and content-checked after restore and the run stops dead if
# one does not come back identical.
# =============================================================================

const SUITE := "res://tests/DevInputTests.gd"
const GODOT := "/Applications/Godot.app/Contents/MacOS/Godot"

const P := "res://scripts/Player.gd"
const G := "res://scripts/GodEditor.gd"
const D := "res://scripts/Pad.gd"
const C := "res://scripts/EditorCam.gd"
const M := "res://scripts/MainMenu.gd"
const R := "res://tests/DevInputRegistry.gd"
const LV := "res://tests/DevInputLive.gd"
const PJ := "res://project.godot"


func muts() -> Array:
	return [
		{"name": "player-key-moved", "file": P,
			"old": "\t\t\tKEY_K:\n", "new": "\t\t\tKEY_J:\n",
			"note": "the spawn menu quietly rebound to J"},
		{"name": "player-key-added", "file": P,
			"old": "\t\t\tKEY_APOSTROPHE:\n",
			"new": "\t\t\tKEY_N:\n\t\t\t\tpass\n\t\t\tKEY_APOSTROPHE:\n",
			"note": "a new binding lands and nobody is told"},
		{"name": "player-key-doubled", "file": P,
			"old": "\t\t\tKEY_G:\n",
			"new": "\t\t\tKEY_G:\n\t\t\t\tpass\n\t\t\tKEY_G:\n",
			"note": "one key claimed twice in the same match block"},
		{"name": "player-release-lost", "file": P,
			"old": "not event.pressed and (event as InputEventKey).keycode == KEY_Q",
			"new": "not event.pressed and (event as InputEventKey).keycode == KEY_Y",
			"note": "the wheel never closes because its release arm moved"},
		{"name": "player-echo-guard-gone", "file": P,
			"old": "and event.pressed and not event.echo",
			"new": "and event.pressed and not event.canceled",
			"note": "key repeat starts re-firing every binding"},
		{"name": "player-first-refusal-gone", "file": P,
			"old": "if godmode != null and godmode.eat_input(event):",
			"new": "if godmode != null and godmode.map_over():",
			"note": "the editor stops getting first refusal"},
		{"name": "god-eats-the-map", "file": G,
			"old": "\t\t\tKEY_H:\n", "new": "\t\t\tKEY_M:\n\t\t\t\treturn true\n\t\t\tKEY_H:\n",
			"note": "the panel starts swallowing the map key"},
		{"name": "god-grounds-the-camera", "file": G,
			"old": "\t\t\t\treturn spectating()", "new": "\t\t\t\treturn true",
			"note": "Space and Ctrl swallowed unconditionally -- god fly dies"},
		{"name": "god-keeps-f1", "file": G,
			"old": "\t\t\treturn false   ## Player's own KEY_F1 case opens the panel",
			"new": "\t\t\treturn true",
			"note": "F1 is eaten before Player can open the panel"},
		{"name": "god-b-unconditional", "file": G,
			"old": "\t\t\t\tif k.shift_pressed:\n\t\t\t\t\tbring_body_here()",
			"new": "\t\t\t\tif true:\n\t\t\t\t\tbring_body_here()",
			"note": "plain B stops falling through to the drop"},
		{"name": "pad-posts-a-dead-key", "file": D,
			"old": "_tap(JOY_BUTTON_BACK, KEY_M)", "new": "_tap(JOY_BUTTON_BACK, KEY_N)",
			"note": "the View button posts a key nothing handles -- silent"},
		{"name": "pad-taps-the-wheel", "file": D,
			"old": "_mirror(JOY_BUTTON_LEFT_SHOULDER, KEY_Q)",
			"new": "_tap(JOY_BUTTON_LEFT_SHOULDER, KEY_Q)",
			"note": "L1 taps instead of holding -- the wheel never opens"},
		{"name": "pad-button-doubled", "file": D,
			"old": "_tap(JOY_BUTTON_DPAD_DOWN, KEY_X)",
			"new": "_tap(JOY_BUTTON_DPAD_DOWN, KEY_X)\n\t_tap(JOY_BUTTON_DPAD_DOWN, KEY_C)",
			"note": "one button mapped to two keys"},
		{"name": "cam-polls-the-map", "file": C,
			"old": "if Input.is_key_pressed(KEY_W): iv.z -= 1.0",
			"new": "if Input.is_key_pressed(KEY_M): iv.z -= 1.0",
			"note": "a dev key claimed by POLLING, which consumes no event"},
		{"name": "menu-takes-the-build-key", "file": M,
			"old": "            KEY_F1:", "new": "            KEY_G, KEY_F1:",
			"note": "the front door grows a claim on G"},
		{"name": "registry-code-drift", "file": R,
			"old": "\"tok\": \"KEY_M\", \"code\": KEY_M", "new": "\"tok\": \"KEY_M\", \"code\": KEY_N",
			"note": "the token and the integer stop agreeing"},
		{"name": "registry-silent-none", "file": R,
			"old": "\"why\": \"only legible with a sword as the current weapon\"",
			"new": "\"why\": \"\"",
			"note": "a row drops off the live pass with no reason given"},
		{"name": "registry-tab-only-again", "file": R,
			"old": "if not (ln.begins_with(\"\\t\") or ln.begins_with(\" \")):",
			"new": "if not ln.begins_with(\"\\t\"):",
			"note": "THE BUG THIS SUITE SHIPPED WITH: space-indented files scan empty"},
		{"name": "live-grows-a-keycode", "file": LV,
			"old": "static func _probeable() -> Array:",
			"new": "const OWN_ESCAPE := KEY_ESCAPE\n\n\nstatic func _probeable() -> Array:",
			"note": "the prober starts keeping its own copy of a key"},
		{"name": "live-loses-its-warmup", "file": LV,
			"old": "func _warm(tree: SceneTree", "new": "func _nowarm(tree: SceneTree",
			"note": "the prober stops proving a key gets through before judging one"},
		{"name": "live-forgets-blackouts", "file": LV,
			"old": "func _settle(tree: SceneTree", "new": "func _nosettle(tree: SceneTree",
			"note": "the prober judges keys it pressed into a blackout"},
		{"name": "project-grows-an-action", "file": PJ,
			"old": "[rendering]", "new": "[input]\n\nopen_god={\"deadzone\":0.5}\n\n[rendering]",
			"note": "an InputMap action, invisible to any scan of Player.gd"},
	]


func _initialize() -> void:
	print("\n=== mutate_devinput ===")


func read(p: String) -> String:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s


func write(p: String, s: String) -> bool:
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(s)
	f.close()
	return true


func suite_red() -> bool:
	## The suite exits 1 on any failure and 0 only when every assertion passed
	## and the floor was cleared.
	var out: Array = []
	var rc := OS.execute(GODOT, ["--headless", "--path",
			ProjectSettings.globalize_path("res://"), "--script", SUITE], out, true)
	return rc != 0


func _process(_d: float) -> bool:
	## Baseline first. A harness that reports every mutation caught because the
	## suite was already red would be worse than no harness at all.
	if suite_red():
		print("  ABORT: the suite is RED before any mutation")
		quit(1)
		return true
	print("  baseline green")
	var caught := 0
	var survived: Array = []
	for m in muts():
		var d := m as Dictionary
		var path := String(d["file"])
		var orig := read(path)
		if orig == "":
			print("  ABORT: cannot read %s" % path)
			quit(1)
			return true
		var hits := orig.count(String(d["old"]))
		if hits != 1:
			print("  ABORT: %s -- anchor matched %d times in %s"
					% [d["name"], hits, path.get_file()])
			quit(1)
			return true
		var bad := orig.replace(String(d["old"]), String(d["new"]))
		if not write(path, bad):
			print("  ABORT: cannot write %s" % path)
			quit(1)
			return true
		var red := suite_red()
		## Put it back BEFORE reporting, so a crash in the print cannot leave a
		## mutated Player.gd on disk.
		write(path, orig)
		var back := read(path)
		if back != orig:
			print("  STOP EVERYTHING: %s did not restore (%d bytes, wanted %d)"
					% [path, back.length(), orig.length()])
			quit(2)
			return true
		if red:
			caught += 1
			print("  caught    %-26s %s" % [d["name"], d["note"]])
		else:
			survived.append(String(d["name"]))
			print("  SURVIVED  %-26s %s" % [d["name"], d["note"]])
	print("\n--- %d of %d caught ---" % [caught, muts().size()])
	if not survived.is_empty():
		print("survivors: %s" % [survived])
	## A survivor is a finding to be understood, not a build to be failed, so
	## the exit code marks it and the round reads the list.
	quit(0 if survived.is_empty() else 1)
	return true
