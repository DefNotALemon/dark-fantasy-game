extends SceneTree
## ===========================================================================
## GRASS LAB (F3) — the regression net for GrassSystem.apply_style and the
## panel that drives it.
##
##   godot --headless --path . --script res://tests/GrassLabTests.gd
##
## Runs the REAL Grass.gd on the real CaveField (GrassTests' fixture) and the
## real GrassLab panel with no HUD. The load-bearing claims:
##   1. an EMPTY style is the v2.7 game, byte for byte — the defaults are not
##      "close to" the old literals, the placement of a chunk is IDENTICAL;
##   2. each knob group does the thing its cost class says: shader keys land
##      as uniforms and nothing else moves, geometry keys rebuild the meshes
##      AND repoint every live chunk, placement keys re-place the ring;
##   3. the weights bite (a species at 0 is gone, fescue at 0.5 is half);
##   4. the JSON round trip, the presets on disk, the shipped-style load path;
##   5. the shader carries the new uniforms and posterizes in GAMMA space;
##   6. the panel takes no key of its own (F3 is Player's), and its widgets
##      follow the style rather than the other way round.
## ===========================================================================

const MIN_ASSERTIONS := 120

var _pass := 0
var _fail := 0
var _fails: Array = []
var _gs: GrassSystem
var _field: CaveField


func ok(c: bool, what: String) -> void:
	if c:
		_pass += 1
	else:
		_fail += 1
		_fails.append(what)
		print("  FAIL: ", what)


func eq(a, b, what: String) -> void:
	ok(a == b, "%s (got %s, want %s)" % [what, str(a), str(b)])


func near(a: float, b: float, tol: float, what: String) -> void:
	ok(absf(a - b) <= tol, "%s (got %.4f, want %.4f +-%.4f)" % [what, a, b, tol])


func section(n: String) -> void:
	print("--- ", n)


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	print("=== Myrkfell Grass Lab tests ===")
	_field = CaveField.new()
	_field.origin = Vector3(-CaveField.CELLS_X * CaveField.VOX * 0.5, -CaveField.DEPTH,
		-CaveField.CELLS_Z * CaveField.VOX * 0.5)
	_field.mouths = [Vector3(20, 0, -14), Vector3(-30, 0, 26)]
	_field.dirs = [Vector3(0, 0, -1), Vector3(1, 0, 0)]
	_field.generate(true)
	_gs = GrassSystem.new()
	root.add_child(_gs)
	_gs.setup(_field, 4457)
	## No shipped style may leak into the fixture: the suite's whole first
	## claim is about the DEFAULTS.
	_gs.apply_style(GrassSystem.STYLE_DEFAULTS.duplicate(true), true)

	t_defaults_are_the_game()
	t_groups()
	t_weights()
	t_json()
	t_shader()
	await t_panel()
	t_no_input()

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	if _pass + _fail < MIN_ASSERTIONS:
		_fail += 1
		_fails.append("only %d assertions ran (floor %d)" % [_pass + _fail, MIN_ASSERTIONS])
	for f in _fails:
		print("  - ", f)
	quit(0 if _fail == 0 else 1)


func _count(placed: Dictionary) -> int:
	var n := 0
	for a in placed["xf"]:
		n += (a as Array).size()
	return n


func _count_kind(placed: Dictionary, k: int) -> int:
	return ((placed["xf"] as Array)[k] as Array).size()


func _tris(m: ArrayMesh) -> int:
	return int(floor(float((m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3.0))


## ============================================================ 1. defaults =

func t_defaults_are_the_game() -> void:
	section("an empty style is the v2.7 game exactly")
	var key := Vector2i(0, 0)
	var a := _gs._place_chunk(key)
	## the literals the hunks replaced, asserted as the defaults they became
	eq(float(GrassSystem.STYLE_DEFAULTS["tall_keep"]), 0.235, "tall keep default is the old literal")
	eq(float(GrassSystem.STYLE_DEFAULTS["short_keep"]), GrassSystem.SHORT_KEEP, "short keep default is SHORT_KEEP")
	eq(float(GrassSystem.STYLE_DEFAULTS["clump_cut"]), -0.62, "clump cut default is the old literal")
	eq(float(GrassSystem.STYLE_DEFAULTS["height"]), 0.18, "fescue height default is v2.4's 0.18")
	eq(float(GrassSystem.STYLE_DEFAULTS["width"]), 0.030, "fescue width default")
	eq(int(GrassSystem.STYLE_DEFAULTS["blades"]), 4, "blades default")
	eq(float(GrassSystem.STYLE_DEFAULTS["tall_height"]), 1.35, "tall height default")
	eq(float(GrassSystem.STYLE_DEFAULTS["cells"]), 8.0, "cells default is v2.4's 8")
	eq(float(GrassSystem.STYLE_DEFAULTS["palette"]), 5.0, "palette default is v2.4's 5")
	eq(_gs._s_attempts, GrassSystem.TUFTS_PER_CHUNK, "density 1.0 = TUFTS_PER_CHUNK attempts")
	for k in GrassSystem.STYLE_DEFAULTS:
		ok(_gs.style.has(k), "style carries %s" % k)
	## every key is in exactly one group
	for k in GrassSystem.STYLE_DEFAULTS:
		var n := 0
		if GrassSystem.PLACEMENT_KEYS.has(k):
			n += 1
		if GrassSystem.GEOMETRY_KEYS.has(k):
			n += 1
		if GrassSystem.SHADER_UNIFORMS.has(k):
			n += 1
		eq(n, 1, "%s belongs to exactly one cost group" % k)
	## applying the defaults again changes nothing and re-places nothing
	var ch := _gs.apply_style(GrassSystem.STYLE_DEFAULTS.duplicate(true), true)
	ok(not bool(ch["shader"]) and not bool(ch["meshes"]) and not bool(ch["placement"]), "re-applying the defaults is a no-op")
	var b := _gs._place_chunk(key)
	eq(_count(b), _count(a), "the same chunk places the same number of tufts")
	var same := true
	for ki in range(GrassSystem.KINDS.size()):
		var xa: Array = (a["xf"] as Array)[ki]
		var xb: Array = (b["xf"] as Array)[ki]
		if xa.size() != xb.size():
			same = false
			break
		for i in range(xa.size()):
			if not (xa[i] as Transform3D).is_equal_approx(xb[i] as Transform3D):
				same = false
				break
	ok(same, "...at the same transforms, kind for kind")
	ok(_count(a) > 500, "the fixture chunk is a real meadow (%d tufts)" % _count(a))


## ============================================================ 2. groups ===

func t_groups() -> void:
	section("each knob group costs what it says")
	var n_chunks := _gs._chunks.size()
	ok(n_chunks > 4, "%d chunks up around the origin" % n_chunks)
	## shader: uniform lands, nothing rebuilt
	var std0: ArrayMesh = (_gs._mesh["std"] as Array)[0]
	var ch := _gs.apply_style({"palette": 9.0}, true)
	ok(bool(ch["shader"]) and not bool(ch["meshes"]) and not bool(ch["placement"]), "palette is a shader-only change")
	near(float(_gs._mat.get_shader_parameter("palette_steps")), 9.0, 0.001, "...and the uniform landed")
	ok((_gs._mesh["std"] as Array)[0] == std0, "...and the mesh object is untouched")
	ch = _gs.apply_style({"col_summer": "#ff0000"}, true)
	ok(bool(ch["shader"]), "a colour is a shader change")
	var c: Color = _gs._mat.get_shader_parameter("col_summer")
	ok(c.r > 0.99 and c.g < 0.01, "...landed as a Color (%s)" % str(c))
	ok(_gs.style["col_summer"] is String and String(_gs.style["col_summer"]) == "#ff0000", "...and stays a string in the style")
	## a bool from a bench export coerces to the float the shader wants
	ch = _gs.apply_style({"pixel_on": false}, true)
	near(float(_gs.style["pixel_on"]), 0.0, 0.0001, "pixel_on false -> 0.0")
	_gs.apply_style({"pixel_on": true}, true)
	near(float(_gs.style["pixel_on"]), 1.0, 0.0001, "pixel_on true -> 1.0")
	## geometry: meshes rebuilt AND every live chunk repointed
	var tris0 := _tris(std0)
	ch = _gs.apply_style({"height": 0.5, "blades": 6, "segs": 5}, true)
	ok(bool(ch["meshes"]) and not bool(ch["placement"]), "height/blades/segs are a geometry change, not a re-place")
	var std1: ArrayMesh = (_gs._mesh["std"] as Array)[0]
	ok(std1 != std0, "the fescue mesh was rebuilt")
	ok(_tris(std1) > tris0, "six five-segment blades carry more triangles (%d > %d)" % [_tris(std1), tris0])
	var top := 0.0
	for v in (std1.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		top = maxf(top, v.y)
	ok(top > 0.35, "and the tallest vertex is up near the new height (%.2f m)" % top)
	var repointed := true
	var checked := 0
	for key: Vector2i in _gs._chunks:
		var per: Dictionary = _gs._chunks[key]
		if per.has("std"):
			checked += 1
			var mmi := per["std"] as MultiMeshInstance3D
			var lod := int(_gs._chunk_lod.get(key, 6)) & 3
			if mmi.multimesh.mesh != (_gs._mesh["std"] as Array)[lod]:
				repointed = false
	ok(checked > 0 and repointed, "every live chunk's fescue points at the new mesh (%d checked)" % checked)
	eq(_gs._chunks.size(), n_chunks, "a geometry change did not re-place the ring")
	## placement: the ring is re-placed and the knob reached the workers
	var before: int = _gs.stats()["tufts"]
	ch = _gs.apply_style({"density": 0.5}, true)
	ok(bool(ch["placement"]), "density is a placement change")
	eq(_gs._s_attempts, int(GrassSystem.TUFTS_PER_CHUNK * 0.5), "...half the attempts")
	var after: int = _gs.stats()["tufts"]
	ok(after < before * 0.62 and after > before * 0.38, "...and the standing meadow halved (%d -> %d)" % [before, after])
	_gs.apply_style({"density": 1.0}, true)
	var back: int = _gs.stats()["tufts"]
	eq(back, before, "density back to 1.0 re-places the identical meadow")
	## the tall threshold moves the stealth answer too
	var talls := 0
	for i in range(400):
		if _gs.is_tall_at(-60.0 + float(i) * 0.3, 7.0):
			talls += 1
	_gs.apply_style({"tall_shift": 1.0}, false)
	var talls2 := 0
	for i in range(400):
		if _gs.is_tall_at(-60.0 + float(i) * 0.3, 7.0):
			talls2 += 1
	ok(talls > 0 and talls2 == 0, "tall_shift +1 removes every hiding patch on the line (%d -> %d)" % [talls, talls2])
	_gs.apply_style({"tall_shift": 0.0}, false)
	## unknown keys (a bench export's sun and wind) are ignored, not stored
	ch = _gs.apply_style({"sun_el": 40, "wind": 0.7, "pattern": "stripes"}, true)
	ok(not bool(ch["shader"]) and not bool(ch["meshes"]) and not bool(ch["placement"]), "bench-only keys are ignored")
	ok(not _gs.style.has("sun_el"), "...and not stored")
	_gs.apply_style(GrassSystem.STYLE_DEFAULTS.duplicate(true), true)


## ============================================================ 3. weights ==

func t_weights() -> void:
	section("the species weights bite")
	_gs.apply_style(GrassSystem.STYLE_DEFAULTS.duplicate(true), false)
	## the chunk with the most fescue near the origin -- a sparse edge chunk
	## cannot show a halving
	var key := Vector2i(0, 0)
	var best := -1
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			var k := Vector2i(dx, dz)
			var n := _count_kind(_gs._place_chunk(k), GrassSystem.K_STD)
			if n > best:
				best = n
				key = k
	var base := _gs._place_chunk(key)
	var n_std := _count_kind(base, GrassSystem.K_STD)
	var n_tim := _count_kind(base, GrassSystem.K_TIMOTHY)
	ok(n_std > 200, "the chunk has fescue (%d)" % n_std)
	ok(n_tim > 5, "...and some timothy (%d)" % n_tim)
	_gs.apply_style({"w_timothy": 0.0}, false)
	var p := _gs._place_chunk(key)
	eq(_count_kind(p, GrassSystem.K_TIMOTHY), 0, "timothy at 0: no timothy")
	ok(_count(p) >= _count(base) - 2, "...its square metres went to something else, not to nothing (%d vs %d)" % [_count(p), _count(base)])
	_gs.apply_style({"w_timothy": 4.0}, false)
	p = _gs._place_chunk(key)
	ok(_count_kind(p, GrassSystem.K_TIMOTHY) > n_tim * 2, "timothy at 4: a lot more of it (%d > 2x%d)" % [_count_kind(p, GrassSystem.K_TIMOTHY), n_tim])
	_gs.apply_style({"w_timothy": 1.0, "w_fescue": 0.5}, false)
	p = _gs._place_chunk(key)
	var half := _count_kind(p, GrassSystem.K_STD)
	ok(half > n_std * 0.38 and half < n_std * 0.62, "fescue at 0.5: about half the fescue (%d of %d)" % [half, n_std])
	_gs.apply_style({"w_fescue": 0.0}, false)
	p = _gs._place_chunk(key)
	eq(_count_kind(p, GrassSystem.K_STD), 0, "fescue at 0: bare ground between the other kinds")
	_gs.apply_style({"w_fescue": 1.0, "w_moss": 0.0, "w_fern": 0.0, "w_clover": 0.0, "w_flower": 0.0, "w_bluestem": 0.0}, false)
	p = _gs._place_chunk(key)
	for kk in [GrassSystem.K_MOSS, GrassSystem.K_FERN, GrassSystem.K_CLOVER, GrassSystem.K_FLOWER, GrassSystem.K_BLUESTEM]:
		eq(_count_kind(p, kk), 0, "%s at 0 is gone" % GrassSystem.KINDS[kk])
	## size_var 0: every tuft the same scale (vigour still varies it by ground)
	_gs.apply_style(GrassSystem.STYLE_DEFAULTS.duplicate(true), false)
	_gs.apply_style({"size_var": 0.0, "vigour": 1.0}, false)
	p = _gs._place_chunk(key)
	var xs: Array = (p["xf"] as Array)[GrassSystem.K_STD]
	var lo := 99.0
	var hi := 0.0
	for t in xs:
		var s := (t as Transform3D).basis.x.length()
		lo = minf(lo, s)
		hi = maxf(hi, s)
	near(lo, hi, 0.001, "size_var 0: no xz scale spread (%.3f..%.3f)" % [lo, hi])
	_gs.apply_style(GrassSystem.STYLE_DEFAULTS.duplicate(true), false)
	p = _gs._place_chunk(key)
	xs = (p["xf"] as Array)[GrassSystem.K_STD]
	lo = 99.0
	hi = 0.0
	for t in xs:
		var s := (t as Transform3D).basis.x.length()
		lo = minf(lo, s)
		hi = maxf(hi, s)
	ok(hi - lo > 0.3, "size_var 1: the v2.7 spread is back (%.2f..%.2f)" % [lo, hi])


## ============================================================ 4. json =====

func t_json() -> void:
	section("json: the bench's export shape, the presets, the shipped style")
	_gs.apply_style({"height": 0.33, "palette": 7.0, "col_dry": "#123456"}, false)
	var txt := _gs.style_to_json("probe", "bench:probe")
	var d: Dictionary = JSON.parse_string(txt)
	eq(String(d["schema"]), GrassSystem.STYLE_SCHEMA, "schema string")
	eq(String(d["name"]), "probe", "name")
	near(float((d["params"] as Dictionary)["height"]), 0.33, 0.0001, "params carry the live value")
	var back := GrassSystem.style_from_json(txt)
	near(float(back["height"]), 0.33, 0.0001, "style_from_json reads an export")
	eq(String(back["col_dry"]), "#123456", "...colours as strings")
	var bare := GrassSystem.style_from_json("{\"height\": 0.2}")
	near(float(bare["height"]), 0.2, 0.0001, "...and a bare dictionary")
	ok(GrassSystem.style_from_json("not json").is_empty(), "garbage is empty, not a crash")
	## write, then read back through the file path
	var tmp := "user://grass_lab_probe.json"
	ok(_gs.save_style_file(tmp, "probe"), "save_style_file writes")
	var rd := GrassSystem.load_style_file(tmp)
	near(float(rd["palette"]), 7.0, 0.0001, "load_style_file reads it back")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	ok(GrassSystem.load_style_file("res://design/no_such_style.json").is_empty(), "a missing file is an empty style")
	## the presets on disk: the bench's twelve, every one a valid style
	var presets := GrassSystem.preset_files()
	ok(presets.size() >= 12, "%d presets under design/grass_styles" % presets.size())
	var names: Array = []
	for p in presets:
		var st := GrassSystem.load_style_file(String((p as Dictionary)["path"]))
		ok(not st.is_empty(), "%s parses" % String((p as Dictionary)["file"]))
		var known := 0
		for k in st.keys():
			if GrassSystem.STYLE_DEFAULTS.has(k):
				known += 1
		ok(known == st.size(), "%s uses only keys the game knows (%d/%d)" % [String((p as Dictionary)["file"]), known, st.size()])
		names.append(String((p as Dictionary)["name"]))
	ok(names.has("Painterly wild") and names.has("PS1 low-poly") and names.has("Frost winter"), "the bench's names came across")
	var sorted := names.duplicate()
	sorted.sort()
	eq(names, sorted, "presets are name-sorted")
	## the shipped-style path: setup() applies design/grass_style.json before the first mesh
	var g2 := GrassSystem.new()
	root.add_child(g2)
	var shipped := GrassSystem.load_style_file(GrassSystem.STYLE_FILE)
	g2.setup(_field, 4457)
	if shipped.is_empty():
		near(float(g2.style["height"]), 0.18, 0.0001, "no shipped style: a fresh system is the defaults")
	else:
		var hit := 0
		var known := 0
		for k in shipped.keys():
			if not GrassSystem.STYLE_DEFAULTS.has(k):
				continue
			known += 1
			var want: Variant = shipped[k]
			var got: Variant = g2.style[k]
			if got is String:
				if String(got) == String(want):
					hit += 1
			elif absf(float(got) - float(want)) < 0.0005:
				hit += 1
		eq(hit, known, "shipped style applied at setup (%d keys)" % known)
	g2.queue_free()
	_gs.apply_style(GrassSystem.STYLE_DEFAULTS.duplicate(true), true)


## ============================================================ 5. shader ===

func t_shader() -> void:
	section("shader: the new uniforms, and the posterize is in gamma space")
	var src := GrassSystem.GRASS_SHADER
	for u in ["pixel_on", "hue_var", "val_var", "root_dark", "tip_light", "light_bands", "backlight", "normal_up", "posterize_gamma"]:
		ok(src.contains("uniform float %s" % u), "declares %s" % u)
	ok(src.contains("floor(col * palette_steps + 0.5) / palette_steps"), "still posterizes (GrassTests' anchor)")
	var gi := src.find("posterize_gamma > 0.5")
	ok(gi > 0, "the gamma branch exists")
	var after := src.substr(gi, 400)
	ok(after.contains("vec3(1.0 / 2.2)") and after.contains("floor(col * palette_steps") and after.contains("vec3(2.2)"),
		"to gamma, quantise, back to linear -- in that order")
	ok(src.find("vec3(1.0 / 2.2)") < src.find("floor(col * palette_steps", gi), "the encode comes BEFORE the floor")
	ok(src.contains("mix(1.0 - root_dark, 1.0"), "root darkness reads the uniform")
	ok(src.contains("* tip_light)"), "tip light reads the uniform")
	ok(src.contains("(v_hash - 0.5) * hue_var"), "hue variation reads the uniform")
	ok(src.contains("mix(normal_up, 0.06, v_u)"), "normal blend reads the uniform")
	ok(src.contains("* backlight;"), "backlight scales the back band")
	ok(src.contains("light_bands < 1.5"), "one band is smooth Lambert")
	ok(not src.contains("mix(0.38, 1.0, smoothstep"), "the old root literal is gone")
	## the shader compiles: a material carrying it answers its uniforms
	var m := _gs._mat
	ok(m != null and m.shader != null, "material built")
	near(float(m.get_shader_parameter("root_dark")), 0.62, 0.001, "root_dark uniform = default 0.62")
	near(float(m.get_shader_parameter("light_bands")), 4.0, 0.001, "light_bands uniform = 4")
	near(float(m.get_shader_parameter("posterize_gamma")), 1.0, 0.001, "posterize_gamma on by default")


## ============================================================ 6. panel ====

func t_panel() -> void:
	section("the panel: builds without a HUD, lists presets, widgets follow the style")
	var lab := GrassLab.new()
	root.add_child(lab)
	await process_frame
	ok(not lab.visible, "starts hidden")
	var r := lab.report()
	eq(int(r["sliders"]), GrassLab.KNOBS.size(), "one slider per knob (%d)" % GrassLab.KNOBS.size())
	eq(int(r["pickers"]), GrassLab.COLOURS.size(), "one picker per colour")
	## every knob is a style key and every non-colour style key is a knob
	var knob_keys: Array = []
	for k in GrassLab.KNOBS:
		knob_keys.append(String(k[0]))
		ok(GrassSystem.STYLE_DEFAULTS.has(String(k[0])), "knob %s is a style key" % String(k[0]))
		var lo := float(k[2])
		var hi := float(k[3])
		var dv := float(GrassSystem.STYLE_DEFAULTS[String(k[0])])
		ok(dv >= lo and dv <= hi, "%s's default %.3f is inside its slider (%.2f..%.2f)" % [String(k[0]), dv, lo, hi])
	for c in GrassLab.COLOURS:
		ok(GrassSystem.STYLE_DEFAULTS.has(String(c[0])), "colour %s is a style key" % String(c[0]))
	for key in GrassSystem.STYLE_DEFAULTS:
		if GrassSystem.STYLE_DEFAULTS[key] is String:
			continue
		ok(knob_keys.has(key), "style key %s has a slider" % key)
	## open: finds the meadow, lists the presets, sets the widgets
	_gs.apply_style({"height": 0.41, "col_moss": "#0a0b0c"}, false)
	lab.visible = true
	await process_frame
	r = lab.report()
	ok(bool(r["grass"]), "found the GrassSystem through its group")
	ok(int(r["presets"]) >= 13, "%d presets listed (defaults + the files)" % int(r["presets"]))
	near((lab._sliders["height"] as HSlider).value, 0.41, 0.001, "the height slider took the live value")
	var pc: Color = (lab._pickers["col_moss"] as ColorPickerButton).color
	ok(pc.is_equal_approx(Color.html("#0a0b0c")), "the moss picker took the live colour")
	## a slider drag of a LOOK knob lands at once; a PLACEMENT knob waits
	(lab._sliders["palette"] as HSlider).value = 11.0
	near(float(_gs.style["palette"]), 11.0, 0.001, "dragging palette applied at once")
	var tufts: int = _gs.stats()["tufts"]
	(lab._sliders["density"] as HSlider).value = 0.5
	near(float(_gs.style["density"]), 1.0, 0.001, "dragging density did NOT apply yet")
	eq(int(lab.report()["pending"]), 1, "...it is pending")
	eq(_gs.stats()["tufts"], tufts, "...and the ring is untouched")
	lab._reseed_t = 0.0
	lab._process(0.05)
	near(float(_gs.style["density"]), 0.5, 0.001, "after the debounce it applied")
	ok(_gs.stats()["tufts"] < tufts, "...and the ring re-placed (%d -> %d)" % [tufts, _gs.stats()["tufts"]])
	(lab._sliders["vigour"] as HSlider).value = 2.0
	lab._reseed_t = 0.0
	lab._process(0.05)
	near(float(_gs.style["vigour"]), 2.0, 0.001, "a second placement drag (vigour) applied the same way")
	## a preset applies whole, on top of the defaults
	var idx := -1
	for i in range(lab._presets.size()):
		if String((lab._presets[i] as Dictionary)["file"]) == "ps1":
			idx = i
	ok(idx > 0, "PS1 preset is in the list")
	lab._on_preset(idx)
	near(float(_gs.style["pixel_on"]), 1.0, 0.001, "PS1: pixel on")
	near(float(_gs.style["palette"]), 4.0, 0.001, "PS1: four-step palette")
	eq(int(_gs.style["segs"]), 1, "PS1: one-segment blades")
	near(float(_gs.style["density"]), 8.0 / 24.0, 0.001, "PS1 names density (8 of the bench's 24 attempts per square metre)")
	near(float(_gs.style["vigour"]), 1.0, 0.001, "PS1 does not name vigour: back to the default, not the last drag")
	near((lab._sliders["palette"] as HSlider).value, 4.0, 0.001, "the slider followed the preset")
	## reset
	lab._reset()
	near(float(_gs.style["palette"]), 5.0, 0.001, "reset: palette back to 5")
	eq(int(_gs.style["segs"]), 4, "reset: segments back to 4")
	lab.visible = false
	lab.queue_free()
	await process_frame


## ============================================================ 7. no input =

func t_no_input() -> void:
	section("no_input: the lab takes no key -- F3 is Player's")
	var src := FileAccess.get_file_as_string("res://scripts/GrassLab.gd")
	ok(src.length() > 3000, "GrassLab.gd read")
	var code := _code_only(src)
	ok(not code.contains("func _input(") and not code.contains("func _unhandled_input(") and not code.contains("func _unhandled_key_input("), "declares no input callback")
	ok(not code.contains("KEY_"), "names no key")
	ok(not code.contains("is_key_pressed") and not code.contains("InputMap"), "polls no key, registers no action")
	## and Player's F3 is exactly one match case that toggles the "grass" menu
	var praw := FileAccess.get_file_as_string("res://scripts/Player.gd")
	var psrc := _code_only(praw)
	eq(psrc.count("KEY_F3:"), 1, "Player claims F3 once")
	var at := praw.find("KEY_F3:")
	ok(at > 0 and praw.substr(at, 240).contains("_toggle_menu(\"grass\")"), "...and it toggles the grass menu")
	ok(praw.contains("grass_lab.visible = which == \"grass\""), "_toggle_menu shows the lab for \"grass\"")
	## Since 2026-09-12 every panel is hidden through ONE table,
	## _show_menu_panels, which _close_menu calls with "" -- so the lab
	## cannot be left showing.
	ok(praw.contains("grass_lab.visible = which == \"grass\"")
			and praw.contains("_show_menu_panels(\"\")"), "_close_menu hides it")
	ok(psrc.contains("grass_lab = GrassLab.new()"), "Player builds the lab")
	var reg := FileAccess.get_file_as_string("res://tests/DevInputRegistry.gd")
	ok(reg.contains("\"tok\": \"KEY_F3\"") and reg.contains("\"expect\": \"grass\""), "DevInputRegistry has the F3 row, live kind menu -> grass")


static func _code_only(src: String) -> String:
	var out := PackedStringArray()
	for line in src.split("\n"):
		var s := String(line)
		var clean := ""
		var in_str := false
		var q := ""
		var i := 0
		while i < s.length():
			var c := s[i]
			if in_str:
				if c == "\\":
					i += 2
					continue
				if c == q:
					in_str = false
				i += 1
				continue
			if c == "\"" or c == "'":
				in_str = true
				q = c
				i += 1
				continue
			if c == "#":
				break
			clean += c
			i += 1
		out.append(clean)
	return "\n".join(out)
