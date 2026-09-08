extends SceneTree

# =============================================================================
# tests/RumourFeedTests.gd -- the ear on the Chronicle (2026-09-08, POLISH).
#
#   godot --headless --path . --script res://tests/RumourFeedTests.gd
#
# Everything here runs without a Player, without World.tscn and without a
# single pixel being looked at. The prose helpers are pure functions and are
# tested as arithmetic; the state machine is driven a frame at a time by
# calling sense() and advance() directly, because a feed tested only through
# _process is a feed tested at whatever frame rate the machine felt like.
#
# The one section that is not about the feed's behaviour is `no_input`, and it
# is the most load-bearing in the file: this project's standing rule is that a
# shadowed dev binding is round-blocking, so the claim "this file adds no
# binding and can shadow none" is asserted against the SOURCE rather than
# asserted in a ledger line.
#
# SECTION CLAIMS: every section stakes what it is about to assert before it
# runs one, so a section killed by a runtime error shows up as a claim that
# never settled instead of quietly taking its assertions with it.
# =============================================================================

const MIN_ASSERTIONS := 84

var _pass := 0
var _fail := 0
var _claims: Dictionary = {}
var _counts: Dictionary = {}
var _section := ""


class FakeBody extends Node3D:
	## Everything RumourFeed.muted_now() looks for, and nothing else.
	var menu_open := ""
	var wheel_open := false
	var input_locked := false
	var health := 100.0


# --------------------------------------------------------------------- harness

func claim(section: String, n: int) -> void:
	_section = section
	_claims[section] = n
	_counts[section] = 0


func ok(cond: bool, what: String) -> void:
	_counts[_section] = int(_counts.get(_section, 0)) + 1
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL  [%s] %s" % [_section, what])


func near(a: float, b: float, tol: float, what: String) -> void:
	ok(absf(a - b) <= tol, "%s (got %.4f, want %.4f +/- %.4f)" % [what, a, b, tol])


func same(a: String, b: String, what: String) -> void:
	ok(a == b, "%s (got '%s', want '%s')" % [what, a, b])


func _accent_named(tag: String) -> Color:
	for row in RumourFeed.ACCENTS:
		if String(row[0]) == tag:
			return row[1] as Color
	return Color(0, 0, 0, 0)


func _mk_feed() -> RumourFeed:
	var f := RumourFeed.new()
	f.boot()
	root.add_child(f)
	return f


func _mk_chron(days: float) -> Chronicle:
	## advance() takes GAME HOURS, not days -- advance(30.0) is a day and a
	## quarter, which is a world with nothing in it yet. Thirty days is what
	## it takes for the boards to fill.
	var c := Chronicle.new()
	c.boot()
	root.add_child(c)
	c.advance(days * 24.0)
	return c


func _place_with_rumours(c: Chronicle) -> Dictionary:
	## The busiest board on the map, so the sections that need something to
	## say are not at the mercy of which village had a quiet fortnight.
	var best: Dictionary = {}
	var bn := 0
	for p in c.places:
		var pd := p as Dictionary
		var n := (pd.get("rumours", []) as Array).size()
		if n > bn:
			bn = n
			best = pd
	return best


func _initialize() -> void:
	print("\n=== RumourFeedTests ===")


func _process(_d: float) -> bool:
	_t_age()
	_t_dwell()
	_t_accent()
	_t_heard()
	_t_pick()
	_t_save()
	_t_earshot()
	_t_speaking()
	_t_mute()
	_t_live()
	_t_layout()
	_t_no_input()
	_t_nullable()
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


# ------------------------------------------------------------------ the prose

func _t_age() -> void:
	claim("age", 12)
	## A clock wound backwards -- the sky menu, a load -- must read as words,
	## not as a negative number of days.
	same(RumourFeed.age_words(-4.0), "just now", "news from the future is just now")
	same(RumourFeed.age_words(0.0), "just now", "this instant")
	same(RumourFeed.age_words(0.34), "just now", "under the first band")
	same(RumourFeed.age_words(0.35), "today", "the first band's edge")
	same(RumourFeed.age_words(0.99), "today", "still today")
	same(RumourFeed.age_words(1.0), "yesterday", "a day old")
	same(RumourFeed.age_words(1.99), "yesterday", "still yesterday")
	same(RumourFeed.age_words(2.0), "two days back", "two")
	same(RumourFeed.age_words(3.5), "three days back", "three")
	same(RumourFeed.age_words(5.9), "a few days back", "nearly out of the window")
	## RUMOUR_DAYS is 6, so anything the feed can ever be handed is inside the
	## bands above -- but a save from a build with a longer window must still
	## produce a sentence rather than an empty string.
	same(RumourFeed.age_words(6.0), "last week", "the far edge")
	same(RumourFeed.age_words(400.0), "last week", "and a year out")


func _t_dwell() -> void:
	claim("dwell", 6)
	near(RumourFeed.dwell_for(""), RumourFeed.DWELL_MIN, 0.001, "an empty line still holds")
	near(RumourFeed.dwell_for("short"), RumourFeed.DWELL_MIN, 0.001, "a short line is floored")
	near(RumourFeed.dwell_for("x".repeat(60)), 60.0 / RumourFeed.READ_CPS + RumourFeed.READ_LEAD,
		0.001, "a middling line is read at READ_CPS")
	near(RumourFeed.dwell_for("x".repeat(400)), RumourFeed.DWELL_MAX, 0.001, "a long line is capped")
	var mono := true
	var last := -1.0
	for n in range(0, 300, 7):
		var d := RumourFeed.dwell_for("x".repeat(n))
		if d < last - 0.0001:
			mono = false
		last = d
	ok(mono, "dwell never decreases as a line gets longer")
	## The catalogue's own longest outcome line has to fit inside the cap, or
	## the cap is cutting a sentence off mid-read for someone.
	var longest := 0
	for k in ChronicleEvents.KINDS:
		for o in ((k as Dictionary).get("outcomes", []) as Array):
			longest = maxi(longest, String((o as Dictionary).get("line", "")).length())
	ok(longest > 20 and RumourFeed.dwell_for("x".repeat(longest)) <= RumourFeed.DWELL_MAX + 0.001,
		"the longest line in the catalogue (%d chars) fits the cap" % longest)


func _t_accent() -> void:
	claim("accent", 9)
	## The ORDER of ACCENTS is the design. wolves_at_fold carries
	## ["wolves", "livestock", "night", "alarm"] and has to read as a threat,
	## not as a nature documentary.
	ok(RumourFeed.accent_for("wolves_at_fold") == _accent_named("alarm"),
		"wolves at the fold reads as alarm")
	ok(RumourFeed.accent_for("wolves_at_fold") != _accent_named("wolves"),
		"and not as wildlife")
	ok(RumourFeed.accent_for("wolf_hunt") == _accent_named("wolves"),
		"the hunt afterwards is wolves, not alarm")
	ok(RumourFeed.accent_for("goblin_raid") == _accent_named("raid"), "a raid is a raid")
	ok(RumourFeed.accent_for("storm_damage") == _accent_named("storm"), "storm before weather")
	ok(RumourFeed.accent_for("aurora") == _accent_named("omen"), "an aurora is an omen, not sky")
	ok(RumourFeed.accent_for("no_such_kind_at_all") == RumourFeed.ACCENT_DEFAULT,
		"a kind renamed out from under a save reads in parchment")
	ok(RumourFeed.accent_for("") == RumourFeed.ACCENT_DEFAULT, "and so does nothing at all")
	var coloured := 0
	var opaque := true
	for id in ChronicleEvents.ids():
		var c := RumourFeed.accent_for(String(id))
		if c.a < 0.99:
			opaque = false
		if c != RumourFeed.ACCENT_DEFAULT:
			coloured += 1
	ok(opaque and coloured >= 25,
		"every one of the %d kinds resolves to an opaque colour, %d of them not the default"
			% [ChronicleEvents.ids().size(), coloured])


# ----------------------------------------------------------- what you've heard

func _t_heard() -> void:
	claim("heard", 8)
	var f := _mk_feed()
	ok(not f.has_heard("Bangor", "A thing happened."), "nothing heard yet")
	f.mark_heard("Bangor", "A thing happened.")
	ok(f.has_heard("Bangor", "A thing happened."), "and now it has been")
	ok(f.heard_count() == 1, "one line remembered")
	f.mark_heard("Bangor", "A thing happened.")
	ok(f.heard_count() == 1, "marking it twice remembers it once")
	## The place is in the key on purpose: outcome lines are shared prose, and
	## being told a thing at Bangor must not silence it at Ellsworth.
	ok(not f.has_heard("Ellsworth", "A thing happened."), "the same line elsewhere is new")
	ok(RumourFeed.key_for("A", "b") != RumourFeed.key_for("B", "b"), "keys are place-scoped")
	for i in range(RumourFeed.HEARD_KEEP + 40):
		f.mark_heard("P", "line %d" % i)
	ok(f.heard_count() == RumourFeed.HEARD_KEEP, "the heard set is capped at HEARD_KEEP")
	ok(not f.has_heard("P", "line 0") and f.has_heard("P", "line %d" % (RumourFeed.HEARD_KEEP + 39)),
		"and it forgets the oldest, not the newest")
	f.free()


func _t_pick() -> void:
	claim("pick", 6)
	var a := {"text": "one", "day": 3.0}
	var b := {"text": "two", "day": 2.0}
	ok(RumourFeed.pick_next([], {}, "P").is_empty(), "nothing to say from an empty board")
	ok(String(RumourFeed.pick_next([a, b], {}, "P").get("text", "")) == "one",
		"the freshest unheard line is taken first")
	var heard := {RumourFeed.key_for("P", "one"): true}
	ok(String(RumourFeed.pick_next([a, b], heard, "P").get("text", "")) == "two",
		"and the next one once it has been said")
	heard[RumourFeed.key_for("P", "two")] = true
	ok(RumourFeed.pick_next([a, b], heard, "P").is_empty(), "a board you have heard out is quiet")
	ok(String(RumourFeed.pick_next([a, b], heard, "Q").get("text", "")) == "one",
		"but the same board at another place is not")
	ok(String(RumourFeed.pick_next([null, 7, a], {}, "P").get("text", "")) == "one",
		"junk in the array is skipped, not crashed on")


func _t_save() -> void:
	claim("save", 6)
	var f := _mk_feed()
	f.mark_heard("Bangor", "Wolves.")
	f.mark_heard("Bath", "Boats.")
	var d := f.to_dict()
	ok(int(d.get("v", 0)) == 1 and (d.get("heard", []) as Array).size() == 2,
		"the save carries the version and both lines")
	var g := _mk_feed()
	g.from_dict(d)
	ok(g.heard_count() == 2, "a fresh feed loads them")
	ok(g.has_heard("Bangor", "Wolves.") and g.has_heard("Bath", "Boats."),
		"and will not repeat either")
	ok(str(g.to_dict()) == str(d), "the round trip is a fixed point")
	## Every save on disk that predates this file has no "rumours" key at all,
	## and World hands us {} for it. That must leave the feed standing.
	var before := g.heard_count()
	g.from_dict({})
	ok(g.heard_count() == before, "a save from before the feed existed changes nothing")
	g.from_dict({"v": 2, "heard": ["x|y"]})
	ok(g.heard_count() == before, "and a save from a newer build is refused, not half-read")
	f.free()
	g.free()


# ------------------------------------------------------------------- earshot

func _t_earshot() -> void:
	claim("earshot", 8)
	var c := _mk_chron(30.0)
	var place := _place_with_rumours(c)
	ok(not place.is_empty() and (place.get("rumours", []) as Array).size() >= 1,
		"thirty days of Chronicle leaves a place with a board on it")
	var p2: Vector2 = place.get("pos", Vector2.ZERO)
	var body := FakeBody.new()
	body.position = Vector3(p2.x, 0.0, p2.y)
	root.add_child(body)
	body.add_to_group("player")

	var f := _mk_feed()
	f.player = body
	f.chron = c
	f.sense()
	same(f._here, String(place.get("name", "")), "standing in a place puts you in its earshot")
	ok(f.arrivals == 1, "arriving is counted once")
	ok(not f._queue.is_empty(), "and there is something to say")
	f.sense()
	ok(f.arrivals == 1, "standing still does not arrive again")

	## The point of EARSHOT. Chronicle.rumours_at answers from RUMOUR_SPREAD
	## away, because that is how far news TRAVELS; overhearing it is a much
	## smaller radius, and if this ever collapses back to rumours_at's own
	## radius you get told the gossip of a village you cannot see.
	var away := Vector3.ZERO
	var found := false
	for i in range(16):
		var ang := TAU * float(i) / 16.0
		var q := Vector3(p2.x + cos(ang) * 1000.0, 0.0, p2.y + sin(ang) * 1000.0)
		if c.nearest_place(q, RumourFeed.EARSHOT).is_empty() and not c.rumours_at(q, 8).is_empty():
			away = q
			found = true
			break
	ok(found, "there is a spot a kilometre out that is out of earshot but inside the spread")
	body.position = away
	f.sense()
	same(f._here, "", "a kilometre out you hear nothing")
	ok(f._queue.is_empty(), "and the queue is dropped rather than carried into the woods")

	f.free()
	body.free()
	c.free()


# ------------------------------------------------------------------ speaking

func _rig(place: String, texts: Array) -> RumourFeed:
	## A feed with a board and no Chronicle, so the pacing can be driven a
	## fraction of a second at a time without the sim moving underneath it.
	var f := _mk_feed()
	f._here = place
	for t in texts:
		f._queue.append({"text": String(t), "day": 0.0, "from": place, "kind": "wolf_hunt"})
	return f


func _t_speaking() -> void:
	claim("speaking", 9)
	## Long lines, so nothing expires while the pacing is being measured:
	## 120 characters is 9.4 s of dwell, capped to DWELL_MAX.
	var texts := ["A".repeat(120), "B".repeat(120), "C".repeat(120), "D".repeat(120)]
	var f := _rig("Bangor", texts)
	f.advance(0.02)
	ok(f.said == 1 and f._lines.size() == 1, "the first line goes up at once")
	ok(f.has_heard("Bangor", String(texts[0])), "and is marked heard the moment it is shown")
	f.advance(0.4)
	ok(f.said == 1, "the next one waits out the gap")
	f.advance(RumourFeed.GAP)
	ok(f.said == 2 and f._lines.size() == 2, "then arrives")
	f.advance(RumourFeed.GAP + 0.05)
	ok(f.said == 3 and f._lines.size() == 3, "and a third")
	f.advance(RumourFeed.GAP + 0.05)
	ok(f._lines.size() <= RumourFeed.MAX_SHOWN,
		"a fourth never makes it up while three are standing")
	ok(f.said == 3 and f._queue.size() == 1, "it is held, not spent")
	## Everything falls off eventually, and the labels go with it.
	f.advance(RumourFeed.DWELL_MAX + 1.0)
	ok(f.said == 4 and f._queue.is_empty(), "the held line is spoken once the stack clears")
	ok(f.lines_on_screen().size() == 1 and String(f.lines_on_screen()[0]) == String(texts[3]),
		"and it is the fourth line, not a repeat of a read one")
	f.free()


func _t_mute() -> void:
	claim("mute", 7)
	var c := _mk_chron(30.0)
	var place := _place_with_rumours(c)
	var p2: Vector2 = place.get("pos", Vector2.ZERO)
	var body := FakeBody.new()
	body.position = Vector3(p2.x, 0.0, p2.y)
	root.add_child(body)
	var f := _mk_feed()
	f.player = body
	f.chron = c
	f.sense()
	f.advance(0.02)
	ok(f.said == 1 and f._lines.size() == 1, "a line is up before the menu opens")
	var life: float = float((f._lines[0] as Dictionary)["life"])

	body.menu_open = "map"
	f.sense()
	ok(f.muted_now(), "an open panel mutes the feed")
	f.advance(5.0)
	## FROZEN, not dropped. If the mute merely hid the line while its life ran
	## out, opening the map would silently spend whatever you were reading --
	## and it is marked heard, so you would never be told it again.
	ok(f.said == 1, "five seconds behind a menu spends no rumour")
	ok(f._lines.size() == 1, "and drops none")
	near(float((f._lines[0] as Dictionary)["life"]), life, 0.001,
		"the standing line keeps every second of its life")

	body.menu_open = ""
	f.sense()
	f.advance(0.02)
	ok(not f.muted_now(), "closing it unmutes")
	near(float((f._lines[0] as Dictionary)["life"]), life - 0.02, 0.001,
		"and hands the sentence back where it was")
	f.free()
	body.free()
	c.free()


func _t_live() -> void:
	claim("live", 6)
	var c := _mk_chron(30.0)
	var place := _place_with_rumours(c)
	var nm := String(place.get("name", ""))
	var p2: Vector2 = place.get("pos", Vector2.ZERO)
	var body := FakeBody.new()
	body.position = Vector3(p2.x, 0.0, p2.y)
	root.add_child(body)
	var f := _mk_feed()
	f.player = body
	f.chron = c
	f.sense()
	var was := f._queue.size()
	f._gap_t = 99.0

	## Word arriving while you are standing in the place it is about goes to
	## the front rather than queuing behind three days of gossip.
	c.event_resolved.emit({"place": nm, "line": "The bell went at midnight.",
		"kind": "goblin_raid", "born": c.days})
	ok(f._queue.size() == was + 1, "it is queued")
	same(String((f._queue[0] as Dictionary).get("text", "")), "The bell went at midnight.",
		"at the front")
	near(f._gap_t, 0.0, 0.001, "and it does not wait out the gap")
	c.event_resolved.emit({"place": nm, "line": "The bell went at midnight.",
		"kind": "goblin_raid", "born": c.days})
	ok(f._queue.size() == was + 1, "the same word twice is one line")
	c.event_resolved.emit({"place": "Somewhere Else", "line": "Not your business.",
		"kind": "goblin_raid", "born": c.days})
	ok(f._queue.size() == was + 1, "and news of a place you are not in is not yours")
	f.advance(0.02)
	ok(f.said == 1 and String(f.lines_on_screen()[0]) == "The bell went at midnight.",
		"so the live line is the one you are shown")
	f.free()
	body.free()
	c.free()


func _t_layout() -> void:
	claim("layout", 5)
	## The catalogue's longest outcome line is 150-odd characters, which at
	## 17px is wider than a 1280 window. Caught live on 2026-09-08 with a line
	## running off the right-hand edge of the screen; the fix is a measure, and
	## this is the measure held to account.
	near(RumourFeed.wrap_width(1280.0), 1280.0 * RumourFeed.WRAP_FRAC, 0.001,
		"a normal window gets its proportional column")
	near(RumourFeed.wrap_width(600.0), RumourFeed.WRAP_MIN, 0.001,
		"a narrow one is floored, not shrunk to a ransom note")
	near(RumourFeed.wrap_width(4000.0), RumourFeed.WRAP_MAX, 0.001,
		"an ultrawide one is capped, not turned into a banner")
	ok(RumourFeed.wrap_width(300.0) <= 300.0 - RumourFeed.MARGIN_X * 2.0 + 0.001,
		"and a window narrower than the floor gives up the floor, not the margin")
	var fits := true
	var x := 320.0
	while x <= 3840.0:
		if RumourFeed.wrap_width(x) > x - RumourFeed.MARGIN_X * 2.0 + 0.001:
			fits = false
		x += 17.0
	ok(fits, "at no width from 320 to 3840 does the column run off the screen")


# ------------------------------------------------------- the rules, in source

func _t_no_input() -> void:
	claim("no_input", 3)
	## This project's standing rule is that a shadowed dev binding is
	## round-blocking. The feed claims to add no binding; that claim is
	## asserted here against the file rather than in a ledger line.
	var fa := FileAccess.open("res://scripts/RumourFeed.gd", FileAccess.READ)
	ok(fa != null, "the source is readable")
	if fa == null:
		ok(false, "no source to scan")
		ok(false, "no source to scan")
		return
	var src := fa.get_as_text()
	fa.close()
	var banned := ["KEY_", "InputMap", "is_action_pressed", "is_action_just_pressed",
		"func _input", "func _unhandled_input", "func _shortcut_input", "InputEventKey"]
	var hit := ""
	for b in banned:
		if src.contains(b):
			hit = b
			break
	same(hit, "", "the feed contains no input handling at all")
	ok(src.length() > 4000, "and the file scanned was the real one")


func _t_nullable() -> void:
	claim("nullable", 5)
	## No player, no Chronicle, no world: it sits there quietly. This is what
	## lets it be built before the player exists and survive a load.
	var f := _mk_feed()
	ok(f.muted_now(), "with no body there is nobody to talk to")
	f.sense()
	f.advance(0.5)
	same(f._here, "", "and nowhere to be")
	ok(f.said == 0, "nothing is said into the void")
	var kids := f.get_child_count()
	f.boot()
	f.boot()
	ok(f.get_child_count() == kids, "boot is idempotent")
	ok(f.report().has("here") and f.report().has("heard"), "and it can still report")
	f.free()
