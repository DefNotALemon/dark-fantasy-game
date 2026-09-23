extends SceneTree
## ===========================================================================
## MAP PANEL — settlement marks. Forts are a granite star; towns stay cream
## circles sized by rank. Headless, off-tree, no World.tscn.
##
##   godot --headless --path . --script res://tests/MapPanelTests.gd
##
## The load-bearing claims:
##   1. Fort Gorges and Fort Knox take the fort mark by exact name.
##   2. Fort Kent is a rank-0 hamlet on the bake, not a fort — the prefix
##      "Fort " is not a classifier.
##   3. `kind == "fort"` is enough if a later row carries it.
##   4. Rank-0 hamlets stay hidden below LABEL_ZOOM; forts always show,
##      even if filed rank 0.
##   5. Rank 3 is still the largest city mark (cream circle).
##   6. The fort glyph is not the orange peak caret.
## ===========================================================================

const MP := preload("res://scripts/MapPanel.gd")
const MIN_ASSERTIONS := 55

var _pass := 0
var _fail := 0
var _fails: Array = []


func ok(c: bool, what: String) -> void:
	if c:
		_pass += 1
	else:
		_fail += 1
		_fails.append(what)
		print("  FAIL: ", what)


func eq(a, b, what: String) -> void:
	ok(a == b, "%s (got %s, want %s)" % [what, str(a), str(b)])


func section(n: String) -> void:
	print("--- ", n)


func read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


func _code_only(src: String) -> String:
	var out: PackedStringArray = []
	for line in src.split("\n"):
		var s := String(line)
		var t := s.strip_edges()
		if t.begins_with("#"):
			continue
		var h := s.find("#")
		if h >= 0 and not s.substr(0, h).contains("\""):
			s = s.substr(0, h)
		out.append(s)
	return "\n".join(out)


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	print("=== Myrkfell Map Panel tests ===")
	_t_classifier()
	_t_prefix()
	_t_kind()
	_t_visible()
	_t_radius()
	_t_glyph()
	_t_bake()
	_t_source()
	await _t_panel()
	print("=== %d passed, %d failed ===" % [_pass, _fail])
	if _pass + _fail < MIN_ASSERTIONS:
		print("  FAIL: only %d assertions ran (want >= %d)" % [_pass + _fail, MIN_ASSERTIONS])
		_fail += 1
	for f in _fails:
		print("  x ", f)
	quit(1 if _fail > 0 else 0)


func pl(name: String, rank: int, kind := "") -> Dictionary:
	var d := {"name": name, "rank": rank, "pos": [0.0, 0.0], "y": 0.0}
	if not kind.is_empty():
		d["kind"] = kind
	return d


# ---------------------------------------------------------------- classifier

func _t_classifier() -> void:
	section("place_mark, the two forts and the hamlet")
	eq(MP.place_mark(pl("Fort Gorges", 1)), MP.MARK_FORT, "Fort Gorges is a fort mark")
	eq(MP.place_mark(pl("Fort Knox", 1)), MP.MARK_FORT, "Fort Knox is a fort mark")
	ok(MP.is_fort_place(pl("Fort Gorges", 1)), "Gorges is_fort_place")
	ok(MP.is_fort_place(pl("Fort Knox", 1)), "Knox is_fort_place")
	eq(MP.place_mark(pl("Fort Kent", 0)), MP.MARK_HAMLET, "Fort Kent is a hamlet, not a fort")
	ok(not MP.is_fort_place(pl("Fort Kent", 0)), "Fort Kent is_fort_place is false")
	eq(MP.place_mark(pl("Portland", 3)), MP.MARK_CITY, "Portland rank 3 is a city mark")
	eq(MP.place_mark(pl("Lewiston–Auburn", 2)), MP.MARK_TOWN, "rank 2 is still a town mark (circle sized by rank)")
	eq(MP.place_mark(pl("Bath", 1)), MP.MARK_TOWN, "rank 1 is a town mark")
	eq(MP.place_mark(pl("Ashland", 0)), MP.MARK_HAMLET, "rank 0 is a hamlet")
	eq(MP.place_mark({}), MP.MARK_HAMLET, "an empty row is a hamlet, not a fort")
	eq(MP.place_mark(pl("Fort Gorges", 0)), MP.MARK_FORT, "Gorges stays a fort even at rank 0")
	eq(MP.place_mark(pl("Fort Knox", 3)), MP.MARK_FORT, "Knox is a fort even if filed as a city rank")


func _t_prefix() -> void:
	section("the prefix Fort is not a fort")
	for nm: String in ["Fort Kent", "Fort Fairfield", "Fort Worth", "Fort",
			"fort knox", "FORT KNOX", "Fort Knoxx", "Fort Gorges "]:
		ok(not MP.is_fort_place(pl(nm, 0)), "'%s' is not a fort by prefix or near-miss" % nm)
		eq(MP.place_mark(pl(nm, 0)), MP.MARK_HAMLET, "'%s' at rank 0 is a hamlet" % nm)
	ok(not MP.place_mark(pl("Fort Kent", 0)).begins_with("fort") or MP.place_mark(pl("Fort Kent", 0)) == MP.MARK_HAMLET,
		"Kent's mark string is hamlet")
	## The classifier itself must not prefix-match: a planted near-name that
	## starts with Fort and is not on the list stays a hamlet.
	ok("Fort Kent".begins_with("Fort "), "sanity: Kent does begin with Fort ")
	ok(not MP.is_fort_place(pl("Fort Kent", 1)), "raising Kent to rank 1 still does not make it a fort")
	eq(MP.place_mark(pl("Fort Kent", 1)), MP.MARK_TOWN, "rank-1 Kent would be a town, still not a fort")


func _t_kind() -> void:
	section("kind == fort, if a row already has it")
	eq(MP.place_mark(pl("Harbor Battery", 0, "fort")), MP.MARK_FORT,
		"kind fort is enough even with a civilian name")
	ok(MP.is_fort_place(pl("Fort Kent", 0, "fort")), "kind fort wins over the Kent name")
	eq(MP.place_mark(pl("Fort Kent", 0, "fort")), MP.MARK_FORT, "so a typed Kent would be a fort")
	ok(MP.is_fort_place(pl("Fort Knox", 1, "town")), "kind town does not cancel the Knox name")
	eq(MP.place_mark(pl("Fort Knox", 1, "town")), MP.MARK_FORT, "the name still makes Knox a fort")
	ok(not MP.is_fort_place(pl("Old Port", 1, "Fort")), "kind Fort (capital F) is not the token")
	ok(not MP.is_fort_place(pl("Old Port", 1, "forts")), "kind forts is not the token")
	ok(MP.place_visible(pl("No Name", 0, "fort"), 1.0), "a kind-fort at rank 0 is visible unzoomed")


# ---------------------------------------------------------------- visibility

func _t_visible() -> void:
	section("zoom gate and forts-always")
	var z0 := 1.0
	var z_in := MP.LABEL_ZOOM
	ok(z_in > z0, "LABEL_ZOOM is above the unzoomed map")
	ok(not MP.place_visible(pl("Fort Kent", 0), z0), "rank 0 is hidden below LABEL_ZOOM")
	ok(not MP.place_visible(pl("Fort Kent", 0), z_in - 0.01), "still hidden a hair under the gate")
	ok(MP.place_visible(pl("Fort Kent", 0), z_in), "rank 0 appears at LABEL_ZOOM")
	ok(MP.place_visible(pl("Fort Kent", 0), z_in + 1.0), "and stays on past it")
	ok(MP.place_visible(pl("Bath", 1), z0), "rank 1 is always on")
	ok(MP.place_visible(pl("Portland", 3), z0), "rank 3 is always on")
	ok(MP.place_visible(pl("Fort Gorges", 1), z0), "Gorges is on the unzoomed map")
	ok(MP.place_visible(pl("Fort Knox", 1), z0), "Knox is on the unzoomed map")
	ok(MP.place_visible(pl("Fort Gorges", 0), z0), "Gorges at rank 0 is STILL visible")
	ok(MP.place_visible(pl("Fort Knox", 0), z0), "Knox at rank 0 is STILL visible")
	ok(not MP.place_visible(pl("Ashland", 0), z0), "an ordinary hamlet is not")


# ---------------------------------------------------------------- radius

func _t_radius() -> void:
	section("rank still sizes the cream circles")
	var r0 := MP.place_dot_radius(pl("hamlet", 0))
	var r1 := MP.place_dot_radius(pl("town", 1))
	var r2 := MP.place_dot_radius(pl("city2", 2))
	var r3 := MP.place_dot_radius(pl("Portland", 3))
	ok(r3 > r2, "rank 3 is larger than rank 2")
	ok(r2 > r1, "rank 2 is larger than rank 1")
	ok(r1 > r0, "rank 1 is larger than rank 0")
	eq(r3, 5.0, "Portland's city mark is 2 + rank 3")
	eq(r0, 2.0, "a hamlet is 2 + 0")
	ok(r3 > MP.place_dot_radius(pl("anywhere", 0)), "rank 3 is the largest city mark")
	ok(MP.place_dot_radius(pl("Portland", 3)) >= MP.place_dot_radius(pl("x", 3)),
		"nothing outranks a rank-3 circle")
	ok(MP.place_mark(pl("Portland", 3)) != MP.MARK_FORT, "Portland is not drawn as a fort")


# ---------------------------------------------------------------- glyph

func _t_glyph() -> void:
	section("granite star is not a peak caret")
	var o := Vector2.ZERO
	var star: PackedVector2Array = MP.fort_star(o)
	var caret: PackedVector2Array = MP.peak_caret(o)
	eq(star.size(), 8, "the fort mark is an 8-vert star")
	eq(caret.size(), 3, "the peak mark is a 3-vert caret")
	ok(star.size() != caret.size(), "so they cannot be the same polygon")
	ok(star[0] != caret[0] or star.size() != caret.size(), "first verts do not make them the same shape")
	var same := star.size() == caret.size()
	if same:
		for i in range(star.size()):
			if star[i] != caret[i]:
				same = false
				break
	ok(not same, "fort_star is not peak_caret")
	ok(MP.C_FORT != MP.C_PLACE, "granite is not the cream town colour")
	ok(MP.C_FORT != MP.C_PEAK, "granite is not the orange peak colour")
	ok(MP.C_PLACE != MP.C_PEAK, "towns and peaks stay distinct from each other too")
	eq(MP.C_PLACE, Color(0.94, 0.90, 0.80), "C_PLACE is still the cream circle")
	## A diamond/star has opposing tips; a caret has a wide base.
	ok(star.size() >= 4, "four tips at least — a star or diamond, not a triangle")
	var tips := 0
	for v: Vector2 in star:
		if is_equal_approx(v.x, 0.0) or is_equal_approx(v.y, 0.0):
			tips += 1
	ok(tips >= 4, "the star has axis-aligned tips (got %d)" % tips)


# ---------------------------------------------------------------- bake

func _t_bake() -> void:
	section("the bake itself — Kent is a hamlet, Knox/Gorges are not on it")
	var raw: Variant = JSON.parse_string(read("res://assets/terrain/maine_meta.json"))
	ok(raw is Dictionary, "maine_meta.json parsed")
	if not raw is Dictionary:
		return
	var places: Array = (raw as Dictionary).get("places", [])
	ok(places.size() >= 40, "the bake has a place list (%d)" % places.size())
	var kent: Dictionary = {}
	var portland: Dictionary = {}
	var bangor: Dictionary = {}
	var names: PackedStringArray = []
	for row in places:
		var d: Dictionary = row
		var nm := String(d.get("name", ""))
		names.append(nm)
		if nm == "Fort Kent":
			kent = d
		elif nm == "Portland":
			portland = d
		elif nm == "Bangor":
			bangor = d
	ok(not kent.is_empty(), "Fort Kent is on the bake")
	eq(int(kent.get("rank", -1)), 0, "and it is rank 0")
	eq(MP.place_mark(kent), MP.MARK_HAMLET, "so the classifier calls it a hamlet")
	ok(not MP.is_fort_place(kent), "and not a fort")
	ok(not MP.place_visible(kent, 1.0), "Kent stays off the unzoomed map")
	ok(not names.has("Fort Knox"), "Fort Knox is not a bake place — World appends it")
	ok(not names.has("Fort Gorges"), "Fort Gorges is not a bake place — World appends it")
	ok(not portland.is_empty(), "Portland is on the bake")
	eq(int(portland.get("rank", -1)), 3, "Portland bake rank is 3")
	eq(MP.place_mark(portland), MP.MARK_CITY, "so it is a city mark")
	ok(MP.place_dot_radius(portland) >= MP.place_dot_radius(bangor) if not bangor.is_empty() else true,
		"Portland's circle is at least as large as Bangor's")
	ok(MP.place_dot_radius(portland) > MP.place_dot_radius(kent),
		"and larger than Kent's hamlet mark")
	## Every bake place whose name starts with Fort is NOT a fort mark.
	var fort_prefix := 0
	for nm2: String in names:
		if nm2.begins_with("Fort "):
			fort_prefix += 1
			eq(MP.place_mark({"name": nm2, "rank": 0}), MP.MARK_HAMLET,
				"bake name '%s' is not a fort" % nm2)
	ok(fort_prefix >= 1, "the bake really does contain a Fort-prefixed hamlet")


# ---------------------------------------------------------------- source

func _t_source() -> void:
	section("MapPanel.gd and the World append, in source")
	var src := read("res://scripts/MapPanel.gd")
	var code := _code_only(src)
	ok(src.length() > 4000, "MapPanel.gd was read (%d bytes)" % src.length())
	ok(code.contains("static func is_fort_place("), "is_fort_place is a static func")
	ok(code.contains("static func place_mark("), "place_mark is a static func")
	ok(code.contains("static func place_visible("), "place_visible is a static func")
	ok(code.contains("static func fort_star("), "fort_star is a static func")
	ok(code.contains("static func peak_caret("), "peak_caret is a static func")
	var a := code.find("func _draw_places(")
	var b := code.find("\nfunc ", a + 1)
	ok(a >= 0, "_draw_places exists")
	var body := code.substr(a, (b if b > a else code.length()) - a)
	ok(body.contains("place_visible(pl"), "_draw_places asks place_visible")
	ok(body.contains("place_mark(pl"), "_draw_places asks place_mark")
	ok(body.contains("fort_star("), "_draw_places draws the granite star")
	ok(body.contains("C_FORT"), "in granite, not cream")
	ok(body.contains("C_PLACE"), "and towns still take C_PLACE")
	ok(not body.contains("begins_with(\"Fort"), "_draw_places does not prefix-match Fort")
	ok(not code.contains("begins_with(\"Fort"), "nor does the rest of the panel")
	ok(code.contains("peak_caret(p)"), "_draw_peaks still uses the caret")
	ok(code.contains("granite star = fort"), "the chips row carries the one-line legend")
	ok(not code.contains("InputEventKey"), "no new keybind — the panel presses no keys")
	ok(not code.contains("KEY_"), "and names none")

	var world := _code_only(read("res://scripts/World.gd"))
	ok(world.length() > 1000, "World.gd was read (this suite does not edit it)")
	var wa := world.find("func _append_fort_place(")
	var wb := world.find("\nfunc ", wa + 1)
	ok(wa >= 0, "World still appends forts as places")
	var wbody := world.substr(wa, (wb if wb > wa else world.length()) - wa)
	ok(wbody.contains("\"rank\": 1"), "appended forts are rank 1")
	ok(not wbody.contains("\"kind\""), "and World does not file kind this slice")
	ok(world.contains("\"Fort Knox\"") and world.contains("\"Fort Gorges\""),
		"the two names this classifier keys off are the ones World appends")

	ok(not code.contains("res://scenes/World.tscn"), "this panel does not boot World.tscn")


# ---------------------------------------------------------------- panel

func _t_panel() -> void:
	section("the real panel, headless, no World")
	var pan: PanelContainer = MP.new()
	root.add_child(pan)
	await process_frame
	ok(is_instance_valid(pan), "MapPanel builds without World.tscn")
	var chips: HBoxContainer = pan.get("_chips")
	ok(chips != null, "the chips row exists")
	var found := false
	var chip_buttons := 0
	if chips != null:
		for c in chips.get_children():
			if c is Button:
				chip_buttons += 1
			if c is Label and String(c.text).contains("fort"):
				found = true
				eq(String(c.text), "granite star = fort", "legend wording")
	ok(found, "the chips row holds the fort legend")
	ok(chip_buttons == 6, "the six layer chips are still there (got %d)" % chip_buttons)
	ok(not pan.visible, "the map starts closed")
	pan.queue_free()
	await process_frame
