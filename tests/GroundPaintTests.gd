extends SceneTree
## ===========================================================================
## GroundPaintTests.gd -- the ground-texture layer (scripts/GroundPaint.gd)
##
##   godot --headless --path . --script res://tests/GroundPaintTests.gd
##
## Runs without a renderer: the atlas slices into a Texture2DArray and the id
## maps upload as ImageTextures even on the dummy driver, and everything the
## brush does is Image arithmetic. Writes only into user://ground_test/.
## ===========================================================================

var _pass := 0
var _fail := 0
const MIN_ASSERTIONS := 60


func ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: %s" % what)


func eq(a, b, what: String) -> void:
	ok(a == b, "%s  (got %s, want %s)" % [what, str(a), str(b)])


func _init() -> void:
	print("GroundPaintTests")
	var gp := GroundPaint.new()
	root.add_child(gp)
	## a private design dir so the suite can never scribble on design/
	DirAccess.make_dir_recursive_absolute("user://ground_test")
	for f in ["ground_paint.dat", "ground.json"]:
		if FileAccess.file_exists("user://ground_test/" + f):
			DirAccess.remove_absolute("user://ground_test/" + f)

	var sh := load("res://shaders/terrain_psx.gdshader") as Shader
	ok(sh != null, "terrain shader loads")
	var mat := ShaderMaterial.new()
	mat.shader = sh

	## --- the sheet's arithmetic --------------------------------------------
	eq(GroundPaint.tile_id(0, 0), 1, "1-A is id 1")
	eq(GroundPaint.tile_id(6, 1), 68, "7-B is id 68")
	eq(GroundPaint.tile_id(10, 10), 121, "11-K is id 121")
	eq(GroundPaint.row_of(68), 6, "row of 68")
	eq(GroundPaint.col_of(68), 1, "col of 68")
	eq(GroundPaint.grid_ref(68), "7-B", "grid ref 7-B")
	eq(GroundPaint.grid_ref(1), "1-A", "grid ref 1-A")
	eq(GroundPaint.grid_ref(121), "11-K", "grid ref 11-K")
	eq(GroundPaint.grid_ref(0), "—", "grid ref of nothing")
	ok(GroundPaint.tile_name(68).begins_with("Realistic-pixeled"), "7 is the house style")
	ok(GroundPaint.tile_name(68).ends_with("Dry grass / Shelf"), "B is dry grass")
	eq(GroundPaint.STYLES.size(), 11, "11 styles")
	eq(GroundPaint.GROUNDS.size(), 11, "11 grounds")
	## every id round-trips
	var rt := true
	for r in range(11):
		for c in range(11):
			var id := GroundPaint.tile_id(r, c)
			if GroundPaint.row_of(id) != r or GroundPaint.col_of(id) != c:
				rt = false
	ok(rt, "all 121 ids round-trip through row_of / col_of")

	## --- setup on a small fake grid, real atlas --------------------------------
	## 40 x 30 cells of 4 m with cell (0,0) centred at (-80, -60): the bake's
	## own convention (Overworld x0/z0), just tiny.
	gp._dir = "user://ground_test/"
	var okset := _setup_private_dir(gp, mat, Vector2(-80.0, -60.0), Vector2i(40, 30), 4.0)
	ok(okset, "setup succeeds with the real atlas")
	if not okset:
		_finish()
		return
	eq(gp.layers, 121, "atlas sliced into 121 layers")
	ok(gp.tiles is Texture2DArray, "tiles is a Texture2DArray")
	eq(gp.tiles.get_layers(), 121, "Texture2DArray has 121 layers")
	eq(gp.tiles.get_width(), 256, "layer is 256 wide")
	ok(gp.tiles.has_mipmaps(), "layers carry mipmaps")
	ok(gp.atlas == null, "the full atlas image is released after slicing")
	ok(gp.atlas_tex != null, "a palette copy of the atlas exists")
	eq(gp.atlas_tex.get_width(), 11 * GroundPaint.THUMB_PX, "palette atlas is 11 thumbs wide")
	var th := gp.thumb(68)
	ok(th is AtlasTexture, "thumb is an AtlasTexture view")
	eq((th as AtlasTexture).region.position, Vector2(1 * GroundPaint.THUMB_PX, 6 * GroundPaint.THUMB_PX), "thumb 7-B region")
	ok(gp.thumb(0) == null, "no thumb for nothing")
	## the real base map is 1800 x 2700 -- it must be REJECTED for this grid
	eq(gp.base.get_width(), 40, "mismatched base map ignored -> blank base of grid size")
	eq(gp.base.get_format(), Image.FORMAT_L8, "base is L8")
	eq(gp.paint.get_format(), Image.FORMAT_L8, "paint is L8")
	eq(gp.painted_cells, 0, "nothing painted yet")
	eq(gp.style_row, GroundPaint.DEFAULT_ROW, "default style row")
	eq(mat.get_shader_parameter("ground_layers"), 121, "uniform ground_layers")
	eq(mat.get_shader_parameter("ground_row"), GroundPaint.DEFAULT_ROW, "uniform ground_row")
	eq(mat.get_shader_parameter("ground_cells"), Vector2i(40, 30), "uniform ground_cells")
	eq(mat.get_shader_parameter("ground_origin"), Vector2(-80.0, -60.0), "uniform ground_origin")
	ok(mat.get_shader_parameter("ground_tiles") == gp.tiles, "uniform ground_tiles bound")
	ok(mat.get_shader_parameter("ground_paint") == gp.paint_tex, "uniform ground_paint bound")

	## --- cells ---------------------------------------------------------------
	eq(gp.cell_of(-80.0, -60.0), Vector2i(0, 0), "origin is cell (0,0)")
	eq(gp.cell_of(-76.0, -56.0), Vector2i(1, 1), "one step over is (1,1)")
	eq(gp.cell_of(-78.1, -60.0), Vector2i(0, 0), "1.9 m off centre still (0,0) -- cells are centred")
	eq(gp.cell_of(-77.9, -60.0), Vector2i(1, 0), "2.1 m off centre is the next cell")
	ok(gp.in_grid(Vector2i(39, 29)), "far corner in grid")
	ok(not gp.in_grid(Vector2i(40, 29)), "one past the edge is out")
	ok(not gp.in_grid(Vector2i(-1, 0)), "negative is out")

	## --- the brush ------------------------------------------------------------
	var centre := Vector3(-80.0 + 20 * 4.0, 0.0, -60.0 + 15 * 4.0)   # cell (20, 15)
	var n := gp.paint_disc(centre, 1.0, 68)
	eq(n, 1, "a 1 m brush paints exactly the cell under it")
	eq(gp.paint_id_at(centre.x, centre.z), 68, "that cell reads back 68")
	eq(gp.paint_id_at(centre.x + 4.0, centre.z), 0, "its neighbour is untouched")
	eq(gp.painted_cells, 1, "painted count 1")
	eq(gp.worn_id_at(centre.x, centre.z), 68, "worn id is the paint")
	## the base is blank here, so an unpainted cell wears nothing
	eq(gp.worn_id_at(centre.x + 4.0, centre.z), 0, "unpainted over blank base wears nothing")
	## give the base a class and the world style dresses it
	gp.base.set_pixel(21, 15, Color(2.0 / 255.0, 0, 0, 1))
	eq(gp.base_col_at(centre.x + 4.0, centre.z), 2, "base column set")
	eq(gp.worn_id_at(centre.x + 4.0, centre.z), GroundPaint.DEFAULT_ROW * 11 + 2, "unpainted wears style row x 11 + column")
	gp.set_style_row(2)
	eq(gp.worn_id_at(centre.x + 4.0, centre.z), 2 * 11 + 2, "style row change re-dresses it (3-B)")
	eq(mat.get_shader_parameter("ground_row"), 2, "uniform follows the style row")
	gp.set_style_row(-1)
	eq(gp.worn_id_at(centre.x + 4.0, centre.z), 0, "style off -> bare tint")
	eq(gp.worn_id_at(centre.x, centre.z), 68, "...but paint still shows")
	gp.set_style_row(6)

	## a 10 m brush: cells whose centres lie within 10 m -> radius 2.5 cells
	## -> offsets with dx^2+dz^2 <= 6.25: 21 cells
	n = gp.paint_disc(centre, 10.0, 5)
	eq(n, 21, "10 m brush covers 21 cells (one already painted still changes id)")
	eq(gp.painted_cells, 21, "painted count 21")
	eq(gp.paint_id_at(centre.x, centre.z), 5, "centre re-painted to 5")
	eq(gp.paint_id_at(centre.x + 8.0, centre.z), 5, "2 cells out is inside a 10 m brush")
	eq(gp.paint_id_at(centre.x + 12.0, centre.z), 0, "3 cells out is not")
	eq(gp.paint_id_at(centre.x + 8.0, centre.z + 8.0), 0, "diagonal (2,2) = 11.3 m is outside")
	## painting the same id again changes nothing
	eq(gp.paint_disc(centre, 10.0, 5), 0, "repaint with the same id is a no-op")
	## erase
	n = gp.paint_disc(centre, 1.0, 0)
	eq(n, 1, "erase one cell")
	eq(gp.paint_id_at(centre.x, centre.z), 0, "erased cell reads 0")
	eq(gp.painted_cells, 20, "painted count 20 after erase")
	## out-of-range ids clamp
	gp.paint_disc(centre, 1.0, 999)
	eq(gp.paint_id_at(centre.x, centre.z), 121, "ids clamp to the layer count")
	## the brush off the grid edge paints only what exists
	var edge := gp.paint_disc(Vector3(-80.0, 0.0, -60.0), 6.0, 3)
	eq(edge, 4, "6 m brush at the corner: 4 of the 9 cells exist")

	## --- fill / clear ----------------------------------------------------------
	gp.fill_all(7)
	## base has exactly one non-water cell (21,15)
	eq(gp.painted_cells, 1, "fill paints only non-water base cells")
	eq(gp.paint_id_at(centre.x + 4.0, centre.z), 7, "the one dry cell got 7")
	eq(gp.paint_id_at(centre.x, centre.z), 0, "water cell stays 0")
	gp.clear_all()
	eq(gp.painted_cells, 0, "clear empties the paint")

	## --- save / load round trip ----------------------------------------------------
	gp.paint_disc(centre, 10.0, 44)
	gp.set_style_row(9)
	gp.set_tile_m(3.5)
	gp.save_now()
	ok(FileAccess.file_exists("user://ground_test/ground_paint.dat"), "paint file written")
	ok(FileAccess.file_exists("user://ground_test/ground.json"), "settings written")
	var gp2 := GroundPaint.new()
	root.add_child(gp2)
	var mat2 := ShaderMaterial.new()
	mat2.shader = sh
	ok(_setup_private_dir(gp2, mat2, Vector2(-80.0, -60.0), Vector2i(40, 30), 4.0), "second instance sets up")
	eq(gp2.painted_cells, 21, "reloaded paint has 21 cells")
	eq(gp2.paint_id_at(centre.x, centre.z), 44, "reloaded cell reads 44")
	eq(gp2.style_row, 9, "style row reloaded")
	ok(absf(gp2.tile_m - 3.5) < 0.001, "tile_m reloaded")
	eq(mat2.get_shader_parameter("ground_row"), 9, "reloaded row reaches the uniform")
	## the bytes on disk are a PNG (the .dat is PNG bytes, never a raw dump)
	var bytes := FileAccess.get_file_as_bytes("user://ground_test/ground_paint.dat")
	ok(bytes.size() > 8 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47, "paint file is PNG bytes")
	ok(bytes.size() < 40000, "a nearly-empty 40x30 map compresses small (%d B)" % bytes.size())

	## --- the shipped base map matches the real bake -----------------------------------
	var real := GroundPaint._png_bytes(GroundPaint.BASE_FILE)
	ok(real != null, "maine_ground.dat loads")
	if real != null:
		eq(real.get_width(), 1800, "base map is 1800 wide")
		eq(real.get_height(), 2700, "base map is 2700 tall")
		real.convert(Image.FORMAT_L8)
		var d := real.get_data()
		var hist := {}
		for i in range(0, d.size(), 97):     # a stride sample is plenty
			hist[d[i]] = int(hist.get(d[i], 0)) + 1
		var legal := true
		for k in hist:
			if int(k) > 11:
				legal = false
		ok(legal, "every base value is a column 0..11")
		ok(hist.has(6) and hist.has(1) and hist.has(2) and hist.has(8), "forest, meadow, dry grass and rock all present")
		ok(hist.has(0), "water present")
		ok(not hist.has(3) and not hist.has(4) and not hist.has(5) and not hist.has(10),
			"patchy / dirt / mud / moss are paint-only (the bake has no class for them)")

	_finish()


## setup() with the private dir kept: GroundPaint.setup() resolves the design
## dir itself, so re-point it AFTER setup and reload from the test dir.
func _setup_private_dir(gp: GroundPaint, mat: Material, origin: Vector2, cells: Vector2i, step: float) -> bool:
	var r := gp.setup(mat, origin, cells, step)
	gp._dir = "user://ground_test/"
	gp._load_settings()
	gp._load_paint()
	gp._bind()
	return r


func _finish() -> void:
	print("GroundPaintTests: %d passed, %d failed" % [_pass, _fail])
	if _pass + _fail < MIN_ASSERTIONS:
		print("  LOST A SECTION: only %d assertions ran (floor %d)" % [_pass + _fail, MIN_ASSERTIONS])
		_fail += 1
	quit(1 if _fail > 0 else 0)
