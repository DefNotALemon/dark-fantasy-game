class_name GroundPaint
extends Node

## ===========================================================================
## GROUND TEXTURES — scripts/GroundPaint.gd                       (2026-09-03)
##
## The ground sheet (tools/groundsheet.py: 11 art-style ROWS x 11 ground
## COLUMNS of seamless 256 px tiles) in the game, and the god editor's brush
## for it. Owns everything the terrain shader needs and nothing else:
##
##   the ATLAS   assets/terrain/ground_atlas.png -> a Texture2DArray, one layer
##               per tile, layer = id - 1, id = row * 11 + column (1..121).
##   the BASE    assets/terrain/maine_ground.dat  (tools/groundclass.py): the
##               bake's own ground class per 4 m cell as a sheet COLUMN 1..11,
##               0 = water. Never edited in game.
##   the PAINT   design/ground_paint.dat: what you painted, a tile id per cell,
##               0 = nothing. THIS is the file the brush writes.
##   the STYLE   design/ground.json: {"row": 6, "tile_m": 2.0}. `row` is the
##               WORLD STYLE -- an unpainted cell wears row * 11 + its base
##               column, so the whole map re-styles from one number. -1 = off:
##               only painted cells are textured, the rest is the bake tint.
##
## Both maps are L8 images on the bake grid (Overworld: nx x nz cells, `step`
## metres, cell (i, j) CENTRED at (x0 + i*step, z0 + j*step), row 0 = north),
## stored as PNG BYTES under a .dat name so Godot never imports them -- an
## import could re-format or compress the ids. Read with load_png_from_buffer.
##
## Painting is cheap and immediate: paint_disc() writes cells into the paint
## Image, the texture re-uploads at most every UPLOAD_EVERY seconds, and the
## file is written SAVE_AFTER seconds after the last stroke (and on save_now).
##
## Names no other class on purpose (Overworld and GodEditor name THIS one);
## the terrain hands in its material and grid through setup().
## ===========================================================================

const N_ROWS := 11
const N_COLS := 11
const TILE_PX := 256
const THUMB_PX := 32            ## the palette's view of a tile
const ATLAS_FILE := "res://assets/terrain/ground_atlas.dat"   
const BASE_FILE := "res://assets/terrain/maine_ground.dat"
const PAINT_FILE := "ground_paint.dat"
const SETTINGS_FILE := "ground.json"
const DEFAULT_ROW := 6          ## realistic-pixeled -- the house style
const DEFAULT_TILE_M := 2.0
const UPLOAD_EVERY := 0.08      ## seconds between texture re-uploads while painting
const SAVE_AFTER := 2.5         ## seconds after the last stroke

## The sheet's axes, in id order. Row i, column j  ->  id = i * 11 + j + 1.
const STYLES := [
	["botw",      "Breath of the Wild",       "flat painterly, saturated"],
	["arceus",    "Legends: Arceus",          "painted, visible strokes"],
	["tsushima",  "Ghost of Tsushima",        "lush, warm, wind-combed"],
	["skyrim",    "Skyrim",                   "gritty, cool realism"],
	["rdr2",      "Red Dead 2",               "photoreal grain"],
	["psx",       "PSX / PS1",                "64 px, dithered"],
	["pixeled",   "Realistic-pixeled",        "the house style (grass v2.3)"],
	["minecraft", "Minecraft",                "16 px, no lighting"],
	["stardew",   "Stardew Valley",           "32 px, 8 colours"],
	["valheim",   "Valheim",                  "128 px, moody"],
	["withering", "The Withering",            "DESIGN.md slate + ember"],
]
const GROUNDS := [
	["lush_meadow",  "Lush meadow"],
	["dry_grass",    "Dry grass / Shelf"],
	["patchy",       "Patchy grass-dirt"],
	["dirt",         "Packed dirt"],
	["mud",          "Mud / wet track"],
	["forest_floor", "Forest floor"],
	["barrens",      "Barrens / heath"],
	["gravel",       "Gravel / scree"],
	["sand",         "Sand / beach"],
	["moss_bog",     "Moss / bog"],
	["snow_dusted",  "Snow-dusted grass"],
]

static var inst: GroundPaint = null

## --- the grid (from Overworld) ------------------------------------------------
var nx := 0
var nz := 0
var step := 4.0
var x0 := 0.0
var z0 := 0.0
var ready_ok := false           ## atlas + base loaded, material bound

## --- the data -------------------------------------------------------------------
var base: Image = null          ## L8, column ids
var paint: Image = null         ## L8, tile ids
var base_tex: ImageTexture = null
var paint_tex: ImageTexture = null
var tiles: Texture2DArray = null
var atlas: Image = null         ## the full sheet, only while slicing
var atlas_tex: ImageTexture = null   ## a small copy of it, for the palette
var layers := 0

var style_row := DEFAULT_ROW    ## -1 = off
var tile_m := DEFAULT_TILE_M
var painted_cells := 0

var _mat: ShaderMaterial = null
var _dir := ""
var _tex_dirty := false
var _upload_t := 0.0
var _save_dirty := false
var _save_t := 0.0


# ===========================================================================
#  Boot
# ===========================================================================

func _ready() -> void:
	inst = self
	set_process(true)


## Overworld calls this once its material exists. `origin` is the world x/z of
## cell (0, 0)'s centre -- Overworld's (x0, z0) -- and `cells` its (nx, nz).
func setup(mat: Material, origin: Vector2, cells: Vector2i, cell_m: float) -> bool:
	nx = cells.x
	nz = cells.y
	step = cell_m
	x0 = origin.x
	z0 = origin.y
	_mat = mat as ShaderMaterial
	_dir = design_dir()
	_load_settings()
	if not _load_atlas():
		push_warning("GroundPaint: no atlas at %s -- ground textures off." % ATLAS_FILE)
		return false
	_load_base()
	_load_paint()
	_bind()
	ready_ok = _mat != null
	print("GroundPaint: %d tiles, %d x %d cells @ %.0f m, style row %d, %d painted"
		% [layers, nx, nz, step, style_row, painted_cells])
	return ready_ok


## Where design files live: res://design/ when it is writable (running from
## the Godot editor), user://design/ otherwise. The same probe WorldPlan.dir()
## makes, repeated here so this script names no other class.
static func design_dir() -> String:
	if DirAccess.make_dir_recursive_absolute("res://design") == OK:
		var probe := FileAccess.open("res://design/.writable_ground", FileAccess.WRITE)
		if probe != null:
			probe.close()
			DirAccess.remove_absolute("res://design/.writable_ground")
			return "res://design/"
	DirAccess.make_dir_recursive_absolute("user://design")
	return "user://design/"


static func _png_bytes(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img


func _load_atlas() -> bool:
	atlas = _png_bytes(ATLAS_FILE)
	if atlas == null:
		return false
	if atlas.get_width() < TILE_PX * N_COLS or atlas.get_height() < TILE_PX * N_ROWS:
		push_warning("GroundPaint: atlas is %d x %d, expected %d x %d" % [atlas.get_width(),
			atlas.get_height(), TILE_PX * N_COLS, TILE_PX * N_ROWS])
		return false
	atlas.convert(Image.FORMAT_RGB8)
	var imgs: Array[Image] = []
	for r in range(N_ROWS):
		for c in range(N_COLS):
			var s := atlas.get_region(Rect2i(c * TILE_PX, r * TILE_PX, TILE_PX, TILE_PX))
			s.generate_mipmaps()
			imgs.append(s)
	tiles = Texture2DArray.new()
	if tiles.create_from_images(imgs) != OK:
		push_warning("GroundPaint: Texture2DArray.create_from_images failed")
		tiles = null
		return false
	layers = imgs.size()
	## The palette does not need 24 MB of atlas on the GPU: a 352 px copy.
	var small := atlas.duplicate() as Image
	small.resize(N_COLS * THUMB_PX, N_ROWS * THUMB_PX, Image.INTERPOLATE_LANCZOS)
	atlas_tex = ImageTexture.create_from_image(small)
	atlas = null
	return true


func _blank_map() -> Image:
	var img := Image.create(maxi(nx, 1), maxi(nz, 1), false, Image.FORMAT_L8)
	img.fill(Color(0, 0, 0, 1))
	return img


func _load_base() -> void:
	base = _png_bytes(BASE_FILE)
	if base == null or base.get_width() != nx or base.get_height() != nz:
		if base != null:
			push_warning("GroundPaint: %s is %d x %d, the bake is %d x %d -- ignoring it"
				% [BASE_FILE, base.get_width(), base.get_height(), nx, nz])
		base = _blank_map()
	base.convert(Image.FORMAT_L8)
	base_tex = ImageTexture.create_from_image(base)


func paint_path() -> String:
	return _dir + PAINT_FILE


func settings_path() -> String:
	return _dir + SETTINGS_FILE


func _load_paint() -> void:
	paint = _png_bytes(paint_path())
	if paint == null or paint.get_width() != nx or paint.get_height() != nz:
		if paint != null:
			push_warning("GroundPaint: %s does not match the bake grid -- starting blank"
				% paint_path())
		paint = _blank_map()
	paint.convert(Image.FORMAT_L8)
	painted_cells = _count_painted()
	paint_tex = ImageTexture.create_from_image(paint)


func _count_painted() -> int:
	## PackedByteArray.count is native -- a GDScript loop over 4.9 M cells at
	## boot was a full second.
	var d := paint.get_data()
	return d.size() - d.count(0)


func _load_settings() -> void:
	style_row = DEFAULT_ROW
	tile_m = DEFAULT_TILE_M
	if not FileAccess.file_exists(settings_path()):
		return
	var f := FileAccess.open(settings_path(), FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	style_row = clampi(int(d.get("row", DEFAULT_ROW)), -1, N_ROWS - 1)
	tile_m = clampf(float(d.get("tile_m", DEFAULT_TILE_M)), 0.25, 32.0)


func _bind() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("ground_tiles", tiles)
	_mat.set_shader_parameter("ground_base", base_tex)
	_mat.set_shader_parameter("ground_paint", paint_tex)
	_mat.set_shader_parameter("ground_origin", Vector2(x0, z0))
	_mat.set_shader_parameter("ground_step", step)
	_mat.set_shader_parameter("ground_cells", Vector2i(nx, nz))
	_mat.set_shader_parameter("ground_layers", layers)
	_mat.set_shader_parameter("ground_row", style_row)
	_mat.set_shader_parameter("tile_m", tile_m)


# ===========================================================================
#  The sheet
# ===========================================================================

static func tile_id(row: int, col: int) -> int:
	## row 0..10 (style), col 0..10 (ground)  ->  1..121
	return row * N_COLS + col + 1


static func row_of(id: int) -> int:
	@warning_ignore("integer_division")
	return (id - 1) / N_COLS


static func col_of(id: int) -> int:
	return (id - 1) % N_COLS


static func grid_ref(id: int) -> String:
	## "7-B" -- the sheet's own labels, so a doc and the panel agree
	if id <= 0:
		return "—"
	return "%d-%s" % [row_of(id) + 1, char(65 + col_of(id))]


static func tile_name(id: int) -> String:
	if id <= 0:
		return "nothing"
	return "%s · %s" % [STYLES[row_of(id)][1], GROUNDS[col_of(id)][1]]


func thumb(id: int) -> Texture2D:
	## A cheap view into the atlas for the palette -- no copies.
	if atlas_tex == null or id <= 0:
		return null
	var t := AtlasTexture.new()
	t.atlas = atlas_tex
	t.region = Rect2(col_of(id) * THUMB_PX, row_of(id) * THUMB_PX, THUMB_PX, THUMB_PX)
	return t


# ===========================================================================
#  Cells
# ===========================================================================

func cell_of(wx: float, wz: float) -> Vector2i:
	## The bake cell under a world point (cells are CENTRED on the grid, so
	## this rounds -- the same convention as Overworld.sample_color).
	return Vector2i(int(round((wx - x0) / step)), int(round((wz - z0) / step)))


func in_grid(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < nx and c.y < nz


func paint_id_at(wx: float, wz: float) -> int:
	if paint == null:
		return 0
	var c := cell_of(wx, wz)
	if not in_grid(c):
		return 0
	return int(round(paint.get_pixel(c.x, c.y).r * 255.0))


func base_col_at(wx: float, wz: float) -> int:
	if base == null:
		return 0
	var c := cell_of(wx, wz)
	if not in_grid(c):
		return 0
	return int(round(base.get_pixel(c.x, c.y).r * 255.0))


func worn_id_at(wx: float, wz: float) -> int:
	## What the shader shows there: paint, else the world style's tile.
	var p := paint_id_at(wx, wz)
	if p > 0:
		return p
	if style_row < 0:
		return 0
	var b := base_col_at(wx, wz)
	return 0 if b == 0 else style_row * N_COLS + b


## THE BRUSH. Sets every cell whose centre lies within `radius_m` of the world
## point to `id` (0 erases). Returns how many cells changed.
func paint_disc(at: Vector3, radius_m: float, id: int) -> int:
	if paint == null:
		return 0
	id = clampi(id, 0, layers)
	var v := Color(float(id) / 255.0, 0, 0, 1)
	var cc := cell_of(at.x, at.z)
	var r := maxf(radius_m, step * 0.5) / step
	var ri := int(ceil(r))
	var changed := 0
	for dz in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			if float(dx * dx + dz * dz) > r * r:
				continue
			var c := Vector2i(cc.x + dx, cc.y + dz)
			if not in_grid(c):
				continue
			var old := int(round(paint.get_pixel(c.x, c.y).r * 255.0))
			if old == id:
				continue
			paint.set_pixel(c.x, c.y, v)
			changed += 1
			if old == 0:
				painted_cells += 1
			elif id == 0:
				painted_cells -= 1
	if changed > 0:
		_tex_dirty = true
		_save_dirty = true
		_save_t = 0.0
	return changed


func fill_all(id: int) -> void:
	## Every cell that is not water. Destructive -- the panel confirms first.
	if paint == null or base == null:
		return
	id = clampi(id, 0, layers)
	var bd := base.get_data()
	var pd := paint.get_data()
	painted_cells = 0
	for i in range(pd.size()):
		if bd[i] == 0:
			pd[i] = 0
		else:
			pd[i] = id
			if id != 0:
				painted_cells += 1
	paint.set_data(nx, nz, false, Image.FORMAT_L8, pd)
	_tex_dirty = true
	_save_dirty = true
	_save_t = 0.0


func clear_all() -> void:
	if paint == null:
		return
	paint.fill(Color(0, 0, 0, 1))
	painted_cells = 0
	_tex_dirty = true
	_save_dirty = true
	_save_t = 0.0


func set_style_row(row: int) -> void:
	style_row = clampi(row, -1, N_ROWS - 1)
	if _mat != null:
		_mat.set_shader_parameter("ground_row", style_row)
	_save_dirty = true
	_save_t = 0.0


func set_tile_m(m: float) -> void:
	tile_m = clampf(m, 0.25, 32.0)
	if _mat != null:
		_mat.set_shader_parameter("tile_m", tile_m)
	_save_dirty = true
	_save_t = 0.0


# ===========================================================================
#  Frame: throttled upload, debounced save
# ===========================================================================

func _process(delta: float) -> void:
	_upload_t += delta
	if _tex_dirty and _upload_t >= UPLOAD_EVERY:
		flush_texture()
	if _save_dirty:
		_save_t += delta
		if _save_t >= SAVE_AFTER:
			save_now()


func flush_texture() -> void:
	if paint_tex != null and paint != null:
		paint_tex.update(paint)
	_tex_dirty = false
	_upload_t = 0.0


func save_now() -> void:
	_save_dirty = false
	_save_t = 0.0
	if paint == null or _dir == "":
		return
	var f := FileAccess.open(paint_path(), FileAccess.WRITE)
	if f == null:
		push_warning("GroundPaint: could not write %s" % paint_path())
		return
	f.store_buffer(paint.save_png_to_buffer())
	f.close()
	var s := FileAccess.open(settings_path(), FileAccess.WRITE)
	if s != null:
		s.store_string(JSON.stringify({"format": 1, "row": style_row, "tile_m": tile_m,
			"painted": painted_cells}, "  "))
		s.close()


func _exit_tree() -> void:
	if _save_dirty:
		save_now()
	if inst == self:
		inst = null
