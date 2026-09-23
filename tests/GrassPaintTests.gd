extends SceneTree
## ===========================================================================
## GrassPaintTests.gd -- where the grass grows, as a map (scripts/GrassPaint.gd)
##
##   godot --headless --path . --script res://tests/GrassPaintTests.gd
##
## Runs without a renderer: everything the brush does is Image arithmetic and
## the texture uploads on the dummy driver. Writes only into user://grass_test/.
## The blades' half (GrassSystem reading the map) is GrassTests section 17.
## ===========================================================================

var _pass := 0
var _fail := 0
const MIN_ASSERTIONS := 60
var _last_rect := Rect2()
var _signals := 0


func ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: %s" % what)


func eq(a, b, what: String) -> void:
	ok(a == b, "%s  (got %s, want %s)" % [what, str(a), str(b)])


func _on_changed(r: Rect2) -> void:
	_signals += 1
	_last_rect = r


func _init() -> void:
	## root is not in the tree during _init, so add_child() would not fire
	## _ready() (and GrassPaint.inst / the grass_system group are set there).
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	print("GrassPaintTests")
	DirAccess.make_dir_recursive_absolute("user://grass_test")
	if FileAccess.file_exists("user://grass_test/grass_paint.dat"):
		DirAccess.remove_absolute("user://grass_test/grass_paint.dat")

	## --- the encoding ------------------------------------------------------------
	eq(GrassPaint.AUTO, 0, "0 is auto")
	eq(GrassPaint.BARE, 1, "1 is bare")
	eq(GrassPaint.FULL, 255, "255 is a full meadow")
	ok(GrassPaint.density_of(0) < 0.0, "auto asks the rule (negative)")
	eq(GrassPaint.density_of(1), 0.0, "bare is density 0")
	eq(GrassPaint.density_of(255), 1.0, "255 is density 1")
	ok(absf(GrassPaint.density_of(128) - 0.5) < 0.01, "128 is about half")
	eq(GrassPaint.value_of_density(1.0), 255, "density 1 -> 255")
	eq(GrassPaint.value_of_density(0.0), 1, "density 0 -> bare")
	eq(GrassPaint.value_of_density(0.5), 128, "density 0.5 -> 128")
	var rt := true
	for v in range(2, 256):
		if GrassPaint.value_of_density(GrassPaint.density_of(v)) != v:
			rt = false
	ok(rt, "every grass byte 2..255 round-trips through density")
	ok(GrassPaint.describe(0).begins_with("auto"), "describe auto")
	eq(GrassPaint.describe(1), "bare", "describe bare")
	eq(GrassPaint.describe(255), "grass 100%", "describe full")

	## --- the shader carries the map --------------------------------------------------
	var sh := load("res://shaders/terrain_psx.gdshader") as Shader
	ok(sh != null, "terrain shader loads")
	var src := sh.code
	ok(src.contains("uniform sampler2D grass_paint"), "shader declares grass_paint")
	ok(src.contains("uniform int grass_paint_on"), "...and the switch")
	ok(src.contains("float grass_cell(ivec2 c)"), "...and the cell read")
	ok(src.contains("* grass;") and src.contains("float rule = (1.0 - rock)"),
		"the far meadow is the rule where the paint says ask, the paint elsewhere")
	ok(src.contains("tile_allows_grass"), "snow and packed tracks refuse the far meadow")
	ok(src.contains("float allow = wet * (1.0 - snow) * tile_grass"),
		"painted grass still refuses water, snow and tracks")
	var mat := ShaderMaterial.new()
	mat.shader = sh

	## --- setup on a small grid ---------------------------------------------------------
	## 40 x 30 cells of 4 m with cell (0,0) centred at (-80, -60): the bake's
	## own convention (Overworld x0/z0), just tiny.
	var gp := GrassPaint.new()
	gp._dir = "user://grass_test/"
	root.add_child(gp)
	ok(gp.setup(mat, Vector2(-80.0, -60.0), Vector2i(40, 30), 4.0), "setup succeeds")
	ok(GrassPaint.inst == gp, "the static handle is set")
	eq(gp.paint.get_format(), Image.FORMAT_L8, "paint is L8")
	eq(gp.paint.get_width(), 40, "paint is the grid")
	eq(gp.painted_cells, 0, "nothing painted yet")
	eq(gp.bare_cells, 0, "nothing bare yet")
	ok(mat.get_shader_parameter("grass_paint") == gp.paint_tex, "uniform grass_paint bound")
	eq(mat.get_shader_parameter("grass_paint_on"), 1, "uniform grass_paint_on")
	eq(mat.get_shader_parameter("ground_cells"), Vector2i(40, 30), "the grid reaches the shader")
	eq(mat.get_shader_parameter("ground_origin"), Vector2(-80.0, -60.0), "...and its origin")
	eq(gp.cell_of(-80.0, -60.0), Vector2i(0, 0), "origin is cell (0,0)")
	eq(gp.cell_of(-77.9, -60.0), Vector2i(1, 0), "2.1 m off centre is the next cell")
	eq(gp.value_at(-80.0, -60.0), 0, "an unpainted cell is auto")
	eq(gp.value_at(5000.0, 5000.0), 0, "off the grid is auto")
	var wr := gp.world_rect()
	ok(wr.has_point(Vector2(-80.0, -60.0)) and wr.has_point(Vector2(76.0, 56.0))
		and not wr.has_point(Vector2(90.0, 0.0)), "world_rect spans the cells")

	## --- the brush ------------------------------------------------------------------------
	gp.changed.connect(_on_changed)
	var centre := Vector3(0.0, 0.0, 0.0)
	var n := gp.paint_disc(centre, 10.0, GrassPaint.FULL)
	eq(n, 21, "a 10 m disc on 4 m cells is 21 cells")
	eq(gp.painted_cells, 21, "21 painted")
	eq(gp.value_at(0.0, 0.0), 255, "the centre reads full")
	eq(gp.value_at(0.0, 8.0), 255, "8 m out is inside")
	eq(gp.value_at(0.0, 12.0), 0, "12 m out is not")
	eq(gp.paint_disc(centre, 10.0, GrassPaint.FULL), 0, "painting the same again changes nothing")
	eq(_signals, 0, "no signal until the texture flushes")
	gp.flush_texture()
	eq(_signals, 1, "one `changed` per flush")
	ok(_last_rect.has_point(Vector2(0.0, 0.0)) and _last_rect.size.x >= 20.0,
		"...carrying the stroke's world rect")
	gp.flush_texture()
	eq(_signals, 1, "a flush with no stroke says nothing")
	n = gp.paint_disc(Vector3(0.0, 0.0, 4.0), 4.0, GrassPaint.BARE)
	ok(n > 0, "bare over grass changes cells (%d)" % n)
	eq(gp.value_at(0.0, 4.0), 1, "the centre is bare now")
	eq(gp.bare_cells, n, "bare count follows")
	eq(gp.painted_cells, 21, "bare is still painted")
	gp.paint_disc(Vector3(0.0, 0.0, 4.0), 4.0, GrassPaint.AUTO)
	eq(gp.value_at(0.0, 4.0), 0, "auto erases")
	eq(gp.bare_cells, 0, "...the bare count too")
	eq(gp.painted_cells, 21 - n, "...and the painted count")
	gp.paint_disc(Vector3(-60.0, 0.0, 40.0), 6.0, 128)
	eq(gp.value_at(-60.0, 40.0), 128, "a half-density dab reads 128")
	## an edge dab is clipped, never wrapped
	var before := gp.painted_cells
	gp.paint_disc(Vector3(-80.0, 0.0, -60.0), 6.0, GrassPaint.FULL)
	ok(gp.painted_cells - before < 21 and gp.painted_cells > before, "a corner dab is clipped to the grid")
	eq(gp.value_at(76.0, 56.0), 0, "...and the far corner did not wrap")

	## --- fill / clear, with and without a water mask ------------------------------------
	gp.fill_all(GrassPaint.FULL)
	eq(gp.painted_cells, 40 * 30, "no base map: fill paints every cell")
	gp.clear_all()
	eq(gp.painted_cells, 0, "clear empties the paint")
	eq(gp.bare_cells, 0, "...bare too")
	## a GroundPaint beside it with water in its base: fill skips the water
	var g2 := GroundPaint.new()
	g2._dir = "user://grass_test/"
	root.add_child(g2)
	g2.nx = 40
	g2.nz = 30
	g2.base = Image.create(40, 30, false, Image.FORMAT_L8)
	g2.base.fill(Color(6.0 / 255.0, 0, 0, 1))
	for i in range(10):
		g2.base.set_pixel(i, 0, Color(0, 0, 0, 1))      ## ten cells of sea
	gp.fill_all(GrassPaint.FULL)
	eq(gp.painted_cells, 40 * 30 - 10, "fill leaves the water alone")
	eq(gp.value_at(-80.0, -60.0), 0, "a sea cell stays auto")
	eq(gp.value_at(0.0, 0.0), 255, "a land cell is full")
	gp.fill_all(GrassPaint.BARE)
	eq(gp.bare_cells, 40 * 30 - 10, "fill bare bares the land")
	gp.clear_all()
	g2.queue_free()

	## --- save / load round trip ------------------------------------------------------------
	gp.paint_disc(centre, 10.0, 200)
	gp.paint_disc(Vector3(40.0, 0.0, 20.0), 4.0, GrassPaint.BARE)
	gp.save_now()
	ok(FileAccess.file_exists("user://grass_test/grass_paint.dat"), "paint file written")
	var bytes := FileAccess.get_file_as_bytes("user://grass_test/grass_paint.dat")
	ok(bytes.size() > 8 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47, "paint file is PNG bytes")
	var gp2 := GrassPaint.new()
	gp2._dir = "user://grass_test/"
	root.add_child(gp2)
	var mat2 := ShaderMaterial.new()
	mat2.shader = sh
	ok(gp2.setup(mat2, Vector2(-80.0, -60.0), Vector2i(40, 30), 4.0), "second instance sets up")
	eq(gp2.painted_cells, gp.painted_cells, "reloaded paint has the same count")
	eq(gp2.bare_cells, gp.bare_cells, "...and the same bare count")
	eq(gp2.value_at(0.0, 0.0), 200, "reloaded cell reads 200")
	eq(gp2.value_at(40.0, 20.0), 1, "reloaded bare reads bare")
	## a map that does not match the grid is refused, not stretched
	var gp3 := GrassPaint.new()
	gp3._dir = "user://grass_test/"
	root.add_child(gp3)
	gp3.setup(null, Vector2(0.0, 0.0), Vector2i(20, 20), 4.0)
	eq(gp3.painted_cells, 0, "a mismatched file starts blank")
	eq(gp3.paint.get_width(), 20, "...at the grid's own size")
	ok(gp3.ready_ok, "and setup with no material is still ready (the tests' path)")

	## --- the brush hands the blades their map ----------------------------------------------
	var gs := GrassSystem.new()
	root.add_child(gs)
	ok(gs.is_in_group("grass_system"), "a grass system is in the group the map looks for")
	gs.set_paint(gp2)
	ok(gp2.changed.is_connected(gs.regrow_rect), "set_paint wires the stroke signal to regrow")
	gs.set_paint(null)
	ok(not gp2.changed.is_connected(gs.regrow_rect), "...and unwires it")
	gs.queue_free()

	_finish()


func _finish() -> void:
	print("GrassPaintTests: %d passed, %d failed" % [_pass, _fail])
	if _pass + _fail < MIN_ASSERTIONS:
		print("  LOST A SECTION: only %d assertions ran (floor %d)" % [_pass + _fail, MIN_ASSERTIONS])
		_fail += 1
	quit(1 if _fail > 0 else 0)
