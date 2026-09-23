class_name GrassPaint
extends Node

## ===========================================================================
## GRASS PAINT — scripts/GrassPaint.gd                             (2026-09-14)
##
## WHERE THE GRASS GROWS, as a map you can paint. Lemon: "apply the grass to
## the whole lands that need grass" and "make it paintable in dev mode".
##
## One L8 image on the bake grid (the same 4 m cells GroundPaint uses, cell
## (i, j) CENTRED at (x0 + i*step, z0 + j*step), row 0 = north), one byte per
## cell, stored as PNG bytes under design/grass_paint.dat:
##
##   0          AUTO   the world's own rule decides (GrassSystem._cover_at:
##                     every dry cell is meadow; water, snow, streets say no)
##   1          BARE   no grass here, whatever the rule says
##   2 .. 255   GRASS  grass here, whatever the rule says, at a DENSITY of
##                     (v - 1) / 254 -- 255 is a full meadow, 128 is half,
##                     2 is the odd tuft. Painted grass grows on rock, on the
##                     beach; snow, roads and water still refuse it.
##
## TWO READERS, one map:
##   the BLADES   GrassSystem._place_chunk reads value_at() per tuft (from its
##                worker threads -- Image.get_pixel on a buffer that is only
##                ever written in place, the same bargain Overworld's
##                heightfield reads already make) and a stroke re-places the
##                standing chunks it touched (GrassSystem.regrow_rect).
##   the HORIZON  the terrain shader's far meadow (terrain_psx.gdshader,
##                `grass_paint` sampler) blends the same cells, so a bare
##                patch is bare to the map edge and a painted meadow is green
##                from the ridge.
##
## Painting is cheap and immediate: paint_disc() writes cells into the Image,
## the texture re-uploads at most every UPLOAD_EVERY seconds, and the file is
## written SAVE_AFTER seconds after the last stroke (and on save_now). The
## `changed` signal carries the world rect of every stroke.
##
## Names GroundPaint only to borrow its water mask for fill_all(); Overworld
## builds this the same way it builds GroundPaint, and GodEditor holds the
## brush.
## ===========================================================================

signal changed(rect: Rect2)     ## world XZ rect the last stroke touched

const PAINT_FILE := "grass_paint.dat"
const AUTO := 0
const BARE := 1
const FULL := 255
const UPLOAD_EVERY := 0.08      ## seconds between texture re-uploads while painting
const SAVE_AFTER := 2.5         ## seconds after the last stroke

static var inst: GrassPaint = null

## --- the grid (from Overworld) ------------------------------------------------
var nx := 0
var nz := 0
var step := 4.0
var x0 := 0.0
var z0 := 0.0
var ready_ok := false

## --- the data -------------------------------------------------------------------
var paint: Image = null         ## L8, the values above
var paint_tex: ImageTexture = null
var painted_cells := 0          ## cells that are not AUTO
var bare_cells := 0             ## ...of which BARE

var _mat: ShaderMaterial = null
var _dir := ""
var _tex_dirty := false
var _upload_t := 0.0
var _save_dirty := false
var _save_t := 0.0
var _stroke := Rect2()          ## world rect accumulated since the last emit
var _stroke_any := false


# ===========================================================================
#  Boot
# ===========================================================================

func _ready() -> void:
	inst = self
	set_process(true)


## Overworld calls this once its ground material exists (GodEditor's tests
## call it with no material at all). `origin` is the world x/z of cell
## (0, 0)'s centre and `cells` its (nx, nz).
func setup(mat: Material, origin: Vector2, cells: Vector2i, cell_m: float) -> bool:
	nx = maxi(cells.x, 1)
	nz = maxi(cells.y, 1)
	step = cell_m
	x0 = origin.x
	z0 = origin.y
	_mat = mat as ShaderMaterial
	if _dir == "":
		_dir = GroundPaint.design_dir()
	_load_paint()
	_bind()
	ready_ok = true
	print("GrassPaint: %d x %d cells @ %.0f m, %d painted (%d bare)"
		% [nx, nz, step, painted_cells, bare_cells])
	## The blades may already be up (GrassSystem.setup ran before the terrain
	## finished): hand them the map now rather than waiting for a stroke.
	if is_inside_tree():
		for g in get_tree().get_nodes_in_group("grass_system"):
			if g.has_method("set_paint"):
				g.call("set_paint", self)
	return true


func paint_path() -> String:
	return _dir + PAINT_FILE


func _blank_map() -> Image:
	var img := Image.create(nx, nz, false, Image.FORMAT_L8)
	img.fill(Color(0, 0, 0, 1))
	return img


func _load_paint() -> void:
	paint = GroundPaint._png_bytes(paint_path())
	if paint == null or paint.get_width() != nx or paint.get_height() != nz:
		if paint != null:
			push_warning("GrassPaint: %s does not match the bake grid -- starting blank"
				% paint_path())
		paint = _blank_map()
	paint.convert(Image.FORMAT_L8)
	_recount()
	paint_tex = ImageTexture.create_from_image(paint)


func _recount() -> void:
	## PackedByteArray.count is native -- a GDScript loop over 4.9 M cells at
	## boot was a full second (GroundPaint learned this first).
	var d := paint.get_data()
	painted_cells = d.size() - d.count(0)
	bare_cells = d.count(1)


func _bind() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("grass_paint", paint_tex)
	_mat.set_shader_parameter("grass_paint_on", 1)
	## The same grid GroundPaint binds -- set here too so the horizon reads the
	## right cells even with no ground atlas on disk.
	_mat.set_shader_parameter("ground_origin", Vector2(x0, z0))
	_mat.set_shader_parameter("ground_step", step)
	_mat.set_shader_parameter("ground_cells", Vector2i(nx, nz))


# ===========================================================================
#  Cells
# ===========================================================================

func cell_of(wx: float, wz: float) -> Vector2i:
	## Cells are CENTRED on the grid, so this rounds -- Overworld.sample_color's
	## convention, and GroundPaint's.
	return Vector2i(int(round((wx - x0) / step)), int(round((wz - z0) / step)))


func in_grid(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < nx and c.y < nz


func value_at(wx: float, wz: float) -> int:
	## The byte under a world point; AUTO off the grid. Read from the grass
	## worker threads -- see the header.
	if paint == null:
		return AUTO
	var c := cell_of(wx, wz)
	if not in_grid(c):
		return AUTO
	return int(round(paint.get_pixel(c.x, c.y).r * 255.0))


static func density_of(v: int) -> float:
	## What a byte MEANS to a placer: -1 = ask the world's rule, else the
	## fraction of a full meadow to grow.
	if v <= AUTO:
		return -1.0
	if v == BARE:
		return 0.0
	return float(v - 1) / 254.0


static func value_of_density(d: float) -> int:
	## The inverse, for a brush: 0.0 is BARE, 1.0 is FULL.
	if d <= 0.0:
		return BARE
	return clampi(int(round(1.0 + clampf(d, 0.0, 1.0) * 254.0)), 2, FULL)


static func describe(v: int) -> String:
	if v <= AUTO:
		return "auto (world rule)"
	if v == BARE:
		return "bare"
	return "grass %d%%" % int(round(density_of(v) * 100.0))


## THE BRUSH. Sets every cell whose centre lies within `radius_m` of the world
## point to `value` (AUTO erases the paint). Returns how many cells changed.
func paint_disc(at: Vector3, radius_m: float, value: int) -> int:
	if paint == null:
		return 0
	value = clampi(value, AUTO, FULL)
	var v := Color(float(value) / 255.0, 0, 0, 1)
	var cc := cell_of(at.x, at.z)
	var r := maxf(radius_m, step * 0.5) / step
	var ri := int(ceil(r))
	var n_changed := 0
	for dz in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			if float(dx * dx + dz * dz) > r * r:
				continue
			var c := Vector2i(cc.x + dx, cc.y + dz)
			if not in_grid(c):
				continue
			var old := int(round(paint.get_pixel(c.x, c.y).r * 255.0))
			if old == value:
				continue
			paint.set_pixel(c.x, c.y, v)
			n_changed += 1
			if old == AUTO:
				painted_cells += 1
			elif value == AUTO:
				painted_cells -= 1
			if old == BARE:
				bare_cells -= 1
			if value == BARE:
				bare_cells += 1
	if n_changed > 0:
		_touch(Rect2(at.x - radius_m - step, at.z - radius_m - step,
			(radius_m + step) * 2.0, (radius_m + step) * 2.0))
	return n_changed


func fill_all(value: int) -> void:
	## Every cell that is not water (GroundPaint's base map knows which; with
	## no base every cell). Destructive -- the panel confirms first.
	if paint == null:
		return
	value = clampi(value, AUTO, FULL)
	var pd := paint.get_data()
	var bd := PackedByteArray()
	var gp := GroundPaint.inst
	if gp != null and gp.base != null and gp.base.get_width() == nx and gp.base.get_height() == nz:
		bd = gp.base.get_data()
	var masked := bd.size() == pd.size()
	for i in range(pd.size()):
		pd[i] = AUTO if (masked and bd[i] == 0) else value
	paint.set_data(nx, nz, false, Image.FORMAT_L8, pd)
	_recount()
	_touch(world_rect())


func clear_all() -> void:
	fill_all(AUTO)


func world_rect() -> Rect2:
	return Rect2(x0 - step * 0.5, z0 - step * 0.5, float(nx) * step, float(nz) * step)


func _touch(r: Rect2) -> void:
	_tex_dirty = true
	_save_dirty = true
	_save_t = 0.0
	_stroke = r if not _stroke_any else _stroke.merge(r)
	_stroke_any = true


# ===========================================================================
#  Frame: throttled upload, debounced save, one `changed` per upload
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
	if _stroke_any:
		_stroke_any = false
		changed.emit(_stroke)


func save_now() -> void:
	_save_dirty = false
	_save_t = 0.0
	if paint == null or _dir == "":
		return
	var f := FileAccess.open(paint_path(), FileAccess.WRITE)
	if f == null:
		push_warning("GrassPaint: could not write %s" % paint_path())
		return
	f.store_buffer(paint.save_png_to_buffer())
	f.close()


func _exit_tree() -> void:
	if _save_dirty:
		save_now()
	if inst == self:
		inst = null
