extends Node3D
class_name Overworld

# !! DO NOT rename this back to `Terrain`. !!
# The TerraBrush GDExtension in addons/ registers a NATIVE class called
# `Terrain` (Node3D, non-instantiable). Native ClassDB names win over a
# script's class_name, so `class_name Terrain` silently resolves to TerraBrush's
# class everywhere and `Terrain.new()` returns null:
#     Class 'Terrain' isn't exposed.
#     Class type: 'Terrain' is not instantiable.
#     Invalid assignment of property 'name' ... on a base object of type 'Nil'.
# Verified against Godot 4.7.2 with the addon loaded: ClassDB.class_exists
# ("Terrain") == true, can_instantiate == false. Nothing warns you at parse time.

# =============================================================================
# Myrkfell -- the overworld ground.
#
# The 208 m spawn valley is Lewiston-Auburn, inside a 7.2 x 10.8 km heightfield
# shaped as Maine. The authored journey leaves south-east for Bath, follows
# the coast north, then turns inland for Katahdin's high-level country.
#
# This node is TWO things, deliberately separated:
#
#   1. THE FACADE -- ground_y / water_y / in_bounds / region_for /
#      place_name_at / warm. Every other system in the game (Player, the
#      wildlife director, CaveRegion, the build menu, the map) talks to the
#      world ONLY through these. They are static, they are safe to call when
#      the terrain is switched off, and they never change signature.
#
#   2. A GROUND PROVIDER -- whatever actually puts a mesh and a collider under
#      your feet. Two exist:
#          "builtin"   the three-ring streamer in this file, no dependencies
#          "terrain3d" the Terrain3D GDExtension, if it is installed
#      The facade reads its heights from the baked data either way, so the
#      provider can be swapped without one line changing anywhere else.
#
# Data comes from assets/terrain/, baked by tools/mainegen.py out of the
# geography in tools/maine_map.py. See docs/TERRAIN.md.
#
# EXPORT NOTE: *.r16 are not Godot resources. Add "*.r16" to
# Project -> Export -> Resources -> "Filters to export non-resource files"
# or an exported build boots the old walled valley. (The 2026-08-27 build hit
# exactly this with its *.f32 files.)
#
# 2026-08-31 -- THE MAP SURVEY. Walked the live build end to end and found:
#   * the clearing hole was a 150 m CIRCLE around a 208 m SQUARE of cave rock,
#     so a 46 m moat of nothing ran round the valley with grass floating on it;
#   * the near tiles' heightmap collision covered the whole square at y = 0 --
#     an invisible floor across BOTH cave mouths (the caves were sealed);
#   * the streamer's first focus was (0,0,0), so nothing built until you had
#     walked 24 m, and real trees only ever grew within 130 m of wherever a
#     tile happened to be BORN -- past spawn every tree was a walk-through
#     impostor;
#   * the far/tiny canopy cards spanned the whole leaf atlas (mostly clear
#     texels) and went black in the mipmaps -- the distant woods read as dead
#     white sticks;
#   * ground colours were sRGB samples rendered as linear -> pastel; lakes were
#     one square plane per NAMED marker, so merged bodies were dry pans and one
#     surface floated 130 m over its bed.
# All of that is fixed below; tests/TerrainTests.gd guards each one.
# =============================================================================

const DATA_DIR := "res://assets/terrain/"
const NO_WATER := -100000.0

# --- provider ---------------------------------------------------------------
enum Provider { BUILTIN, TERRAIN3D }
## Leave as AUTO to use Terrain3D when the addon is installed and fall back to
## the builtin streamer when it is not.
@export_enum("auto", "builtin", "terrain3d") var provider_choice: String = "auto"
var provider: Provider = Provider.BUILTIN

# --- streaming budget -------------------------------------------------------
# Three rings of ground, each 4x the last, all built from the same heightfield:
#
#   near  128 m tiles @  4 m   collision + real choppable TreeV2s + impostors
#   mid   512 m tiles @ 16 m   impostor forest only
#   far  2048 m blocks @ 64 m  the ranges on the horizon, forest-TINTED
#
# A far block hides once all 16 of its mid tiles exist; a mid tile hides once
# all 16 of its near tiles exist. No overlap, so no z-fighting.
const TILE_QUADS := 32        # quads per tile edge, every ring
const NEAR_SPAN := 128.0
const MID_SPAN := 512.0
const FAR_SPAN := 2048.0
const NEAR_RANGE := 420.0
const MID_RANGE := 2400.0
const BUILD_BUDGET_MS := 6.0  # per-frame mesh build budget, nearest first
const REFOCUS_DIST := 16.0    # move this far and the rings re-evaluate

# --- chunked streaming, threaded (2026-09-02) --------------------------------
# One tile is ~6,100 verts of SurfaceTool work over 1,089 heightfield samples
# and (before this) 4,096 colour-map reads. That ran on the MAIN THREAD inside
# a budget that was only checked AFTER a whole tile had been built, so one
# tile was one hitch no matter what BUILD_BUDGET_MS said.
#
# Now the ARITHMETIC runs on WorkerThreadPool -- pure reads of _h / _w / _col,
# no node touched, no resource allocated -- and the main thread only assembles
# finished arrays into an ArrayMesh. Several tiles are in the air at once, so
# the threads are never sitting idle waiting for the next frame to feed them.
const BUILD_JOBS := 6         ## tiles meshed on worker threads at once
const APPLY_PER_FRAME := 3    ## finished tiles installed per frame
const APPLY_BUDGET_MS := 4.0  ## ...and never more than this much of a frame
## Queue ORDER is sorted against a point this far ahead of the look, so the
## ground you are walking into is built before the ground behind you.
const PREFETCH_M := 110.0
## Gallop is 11 m/s; 110 m is ten seconds of empty tiles ahead. Push the
## queue farther when someone is mounted so the wood arrives before the horse.
const PREFETCH_RIDE := 240.0
## Slots in a job payload. Integer indices on purpose: a Dictionary with
## String keys shared across threads is the grass-v2 refcount trap.
const JOB_KEY := 0
const JOB_RING := 1
const JOB_TASK := 2
const JOB_VERT := 3
const JOB_COLOR := 4
const JOB_NORMAL := 5
const JOB_HEIGHT := 6

# --- the spawn clearing -----------------------------------------------------
## The CaveRegion is a SQUARE block of voxel rock, CaveField.CELLS_X * VOX on a
## side (208 m), centred on the origin, and its grass-skinned top IS the ground
## in there. The heightfield leaves that square as a hole and meets it flush at
## y = 0 (the bake flattens everything inside valley_flat to zero). Measured
## before this was a square: no ground meshed from |x| = 104 to r = 147.
const HOLE_HALF := 104.0
## Inside the hole the near tiles' HEIGHTMAP COLLISION is sunk to this depth --
## below the cave field's floor at -36 -- so the collider never puts an
## invisible plane across a cave mouth or a hole you dug. The boundary samples
## keep their real height, so the collider still meets the rock edge flush.
const HOLE_SINK := -80.0

# --- the singleton ----------------------------------------------------------
static var inst: Overworld = null

## [fort] extra holes — rects punched out of the heightfield at runtime, on
## top of the spawn square. A hole removes the ground MESH and sinks the
## COLLIDER, so whatever registered one has to put its own floor back; that is
## what FortKnox's raft and apron are for. Each entry is {rect: Rect2, sink}.
static var _extra_holes: Array = []
static var _extra_bounds := Rect2()
static var _has_extra := false


## Cut `rect` (world XZ) out of the terrain, collider sunk to `sink`. Tiles
## already standing keep the ground they were built with, so this rebuilds
## them — at boot there are none yet and the rebuild costs nothing.
static func punch_hole(rect: Rect2, sink: float) -> void:
	for h in _extra_holes:
		if ((h as Dictionary)["rect"] as Rect2).is_equal_approx(rect):
			return
	_extra_holes.append({"rect": rect, "sink": sink})
	_extra_bounds = rect if not _has_extra else _extra_bounds.merge(rect)
	_has_extra = true
	if inst != null and inst._loaded:
		inst.rebuild_all()


## Forget every runtime hole. Only tests need this.
static func clear_holes() -> void:
	_extra_holes.clear()
	_extra_bounds = Rect2()
	_has_extra = false


# --- baked data -------------------------------------------------------------
var meta: Dictionary = {}
var nx := 0
var nz := 0
var step := 4.0
var h_min := 0.0
var h_max := 0.0
var w_min := 0.0
var w_max := 0.0
var sea_level := -22.5
var x0 := 0.0                 # world x of column 0
var z0 := 0.0                 # world z of row 0 (row 0 = north)
var valley_flat := 150.0
var valley_ease := 340.0

var _h := PackedByteArray()   # uint16 little-endian, nx * nz
var _w := PackedByteArray()   # uint16; 0 = dry
var _col: Image = null        # ground tint, same grid
var _loaded := false

var _places: Array = []
var _peaks: Array = []
var _lakes: Array = []
var _regions: Array = []
var _story_route: Array = []

# --- runtime ----------------------------------------------------------------
var _near: Dictionary = {}    # Vector2i -> Node3D
var _mid: Dictionary = {}
var _far: Dictionary = {}
## Shoots and owns the distant forest's impostor textures (TreeImpostor.gd).
var _impostors: TreeImpostor = null
var _queue: Array[Vector3i] = []   # (kx, kz, ring): 0 near, 1 mid
var _jobs: Array = []              # tiles being meshed on worker threads
var _aim := Vector3.ZERO           # the focus, pushed forward along the look
## INF, not ZERO: the first _process compares the camera against this and the
## camera starts at the origin. With ZERO nothing built until you had walked
## REFOCUS_DIST from spawn -- 24 m of a valley with no world around it.
var _focus := Vector3(INF, INF, INF)
var _ground_root: Node3D = null
var _water_root: Node3D = null
var _t3d: Node = null         # a Terrain3D node when that provider is live

signal terrain_ready


# =============================================================================
# BOOT
# =============================================================================
func _ready() -> void:
	inst = self
	add_to_group("terrain")
	_loaded = _load_data()
	if not _loaded:
		push_warning("Overworld: no baked data in %s -- the world stays a valley." % DATA_DIR)
		return
	_ground_root = Node3D.new()
	_ground_root.name = "Ground"
	add_child(_ground_root)
	_water_root = Node3D.new()
	_water_root.name = "Water"
	add_child(_water_root)
	## The distant forest is a PHOTOGRAPH of the real tree now, not a faceted
	## blob, and the photograph takes a few frames to shoot (five species
	## through a SubViewport). Start it here; the far tiers draw nothing until
	## it lands, and `impostors_ready` puts them in.
	## SCATTER off = nothing distant to draw, so do not pay for the bake.
	if SCATTER:
		_impostors = TreeImpostor.new()
		_impostors.name = "TreeImpostors"
		add_child(_impostors)
		_impostors.impostors_ready.connect(_on_impostors_ready)

	_pick_provider()
	if provider == Provider.TERRAIN3D:
		_t3d_setup()
	else:
		_build_builtin()
	_build_ground_paint()
	terrain_ready.emit()


## GROUND TEXTURES (2026-09-03). scripts/GroundPaint.gd owns the ground sheet
## atlas, the two id maps and the god editor's brush; all it needs from here is
## the shared ground material and the bake grid. Built AFTER the far ring so
## the material exists, and it is the same ShaderMaterial every tile shares,
## so binding the textures once textures the whole world at once.
var ground_paint: GroundPaint = null
## GRASS PAINT (2026-09-14). Where the grass grows, on the same grid — the
## god editor's Grass brush (scripts/GrassPaint.gd). Built beside the ground
## textures, and even without them: the atlas is 8 MB of art that may not be
## on disk, the grass map is a byte a cell and always is.
var grass_paint: GrassPaint = null


func _build_ground_paint() -> void:
	if provider != Provider.BUILTIN:
		return
	var mat := _ground_material()
	if not (mat is ShaderMaterial):
		return
	ground_paint = GroundPaint.new()
	ground_paint.name = "GroundPaint"
	add_child(ground_paint)
	ground_paint.setup(mat, Vector2(x0, z0), Vector2i(nx, nz), step)
	grass_paint = GrassPaint.new()
	grass_paint.name = "GrassPaint"
	add_child(grass_paint)
	grass_paint.setup(mat, Vector2(x0, z0), Vector2i(nx, nz), step)


## The impostor textures exist. Every ring scattered before them is standing
## empty, so put the trees in: near and mid come back through rebuild_all(),
## and the far blocks are re-scattered where they stand (rebuild_all leaves
## `_far` alone on purpose -- those blocks are 2 km of ground apiece).
func _on_impostors_ready() -> void:
	for k in _far.keys():
		var blk: Node3D = _far[k]
		for c in blk.get_children():
			if c is MultiMeshInstance3D and String(c.name).begins_with("Forest_"):
				blk.remove_child(c)
				c.queue_free()
		_scatter_impostors(blk, k, FAR_SPAN, 2, "tiny")
	rebuild_all()
	var st: Dictionary = forest_stats()
	print("Overworld: impostors baked -- %d distant trees, %d tris"
		% [st["trees"], st["tris"]])


func _pick_provider() -> void:
	var want := provider_choice
	if want == "auto":
		want = "terrain3d" if _t3d_available() else "builtin"
	if want == "terrain3d" and not _t3d_available():
		push_warning("Overworld: Terrain3D requested but the addon is not installed; using the builtin streamer.")
		want = "builtin"
	provider = Provider.TERRAIN3D if want == "terrain3d" else Provider.BUILTIN
	print("Overworld: provider = %s" % ("Terrain3D" if provider == Provider.TERRAIN3D else "builtin streamer"))


## class_exists() first: can_instantiate() on a name ClassDB has never heard of
## pushes "Cannot get class 'X'" into the log every boot. And class_exists()
## alone is not enough either -- TerraBrush's `Terrain` exists and cannot be
## instantiated, which is the whole reason this file is not called Terrain.gd.
func _t3d_available() -> bool:
	return ClassDB.class_exists("Terrain3D") and ClassDB.can_instantiate("Terrain3D")


func _load_data() -> bool:
	var mf := FileAccess.open(DATA_DIR + "maine_meta.json", FileAccess.READ)
	if mf == null:
		return false
	var parsed: Variant = JSON.parse_string(mf.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Overworld: maine_meta.json is not an object")
		return false
	meta = parsed

	var samples: Array = meta.get("samples", [0, 0])
	nx = int(samples[0])
	nz = int(samples[1])
	step = float(meta.get("spacing", 4.0))
	sea_level = float(meta.get("sea_level", -22.5))
	var hr: Array = meta.get("height_range", [0.0, 1.0])
	h_min = float(hr[0])
	h_max = float(hr[1])
	var wr: Array = meta.get("water_range", [0.0, 1.0])
	w_min = float(wr[0])
	w_max = float(wr[1])
	var b: Dictionary = meta.get("bounds_world", {})
	x0 = float((b.get("x", [0.0, 0.0]) as Array)[0])
	z0 = float((b.get("z", [0.0, 0.0]) as Array)[0])
	var v: Dictionary = meta.get("valley", {})
	valley_flat = float(v.get("flat_r", 150.0))
	valley_ease = float(v.get("ease_r", 340.0))

	_places = meta.get("places", [])
	_peaks = meta.get("peaks", [])
	_lakes = meta.get("lakes", [])
	_regions = meta.get("regions", [])
	_story_route = meta.get("story_route", [])

	_h = _read_raw("maine_height.r16")
	_w = _read_raw("maine_water.r16")
	if _h.size() < nx * nz * 2:
		push_error("Overworld: maine_height.r16 is %d bytes, expected %d -- is *.r16 in the export filter?"
			% [_h.size(), nx * nz * 2])
		return false
	# The colour map goes through load() rather than Image.load(): source PNGs
	# do not exist in an exported build, so Image.load("res://...") fails there.
	var tex: Texture2D = load(DATA_DIR + "maine_color.png") as Texture2D
	if tex != null:
		_col = tex.get_image()
		if _col != null and _col.is_compressed():
			_col.decompress()
	print("Overworld: %d x %d @ %.1f m  (%.1f x %.1f km)  y %.1f..%.1f  sea %.1f"
		% [nx, nz, step, nx * step / 1000.0, nz * step / 1000.0, h_min, h_max, sea_level])
	return true


func _read_raw(fname: String) -> PackedByteArray:
	var f := FileAccess.open(DATA_DIR + fname, FileAccess.READ)
	if f == null:
		push_error("Overworld: missing %s%s" % [DATA_DIR, fname])
		return PackedByteArray()
	return f.get_buffer(f.get_length())


# =============================================================================
# THE FACADE -- static, and safe with no terrain at all
# =============================================================================

## Surface height at a world position. Returns 0.0 inside the spawn valley (the
## CaveRegion's own grass top is the ground there) and when terrain is off.
static func ground_y(pos: Vector3) -> float:
	if inst == null or not inst._loaded:
		return 0.0
	return inst.sample_height(pos.x, pos.z)


## Water SURFACE height, or NO_WATER on dry ground.
static func water_y(pos: Vector3) -> float:
	if inst == null or not inst._loaded:
		return NO_WATER
	return inst.sample_water(pos.x, pos.z)


static func in_bounds(pos: Vector3) -> bool:
	if inst == null or not inst._loaded:
		return true
	return inst.pos_in_bounds(pos)


## True while the position is inside the flattened spawn clearing.
static func in_valley(pos: Vector3) -> bool:
	if inst == null or not inst._loaded:
		return true
	return Vector2(pos.x, pos.z).length() < inst.valley_flat


## True inside the CaveRegion's square footprint -- the hole in the heightfield
## where the voxel rock is the ground. Static and terrain-independent, because
## the square exists whether or not the overworld loaded.
static func in_hole(pos: Vector3) -> bool:
	if absf(pos.x) < HOLE_HALF and absf(pos.z) < HOLE_HALF:
		return true
	## [fort] punched rects — cheap out on the merged bounds first: this runs
	## once per quad of every tile, on the worker threads.
	if not _has_extra:
		return false
	var p := Vector2(pos.x, pos.z)
	if not _extra_bounds.has_point(p):
		return false
	for h in _extra_holes:
		if ((h as Dictionary)["rect"] as Rect2).has_point(p):
			return true
	return false


## How far a position is BELOW the local surface. Positive = underground (or
## under water). World and Player used to compare raw y against constants
## tuned for a flat valley at y = 0, which turned every beach on the map into
## "The Hollow Depths" with cave fog and an auto-drawn torch.
static func depth_below_surface(pos: Vector3) -> float:
	return ground_y(pos) - pos.y


## The world gets harder along the authored journey even when the player
## arrives early: Lewiston and the southern river are tier 0, the coast rises
## eastward, and the far north / high summits are endgame ground. Player level
## may raise a spawn above this floor, but can never make Katahdin harmless.
static func danger_tier_at(pos: Vector3) -> int:
	var y := ground_y(pos)
	if y > 400.0 or pos.z < -5200.0:
		return 4
	if y > 240.0 or pos.z < -2800.0 or pos.x > 4300.0:
		return 3
	if y > 120.0 or pos.z < -1200.0 or pos.x > 2800.0:
		return 2
	if y > 55.0 or pos.z < -500.0 or pos.x > 1100.0:
		return 1
	return 0


## --- water queries (WaterAudio, WildlifeDirector, the Drowned, drinking) ---
## The bake keeps sea-level water cells BURIED under Portland's and Freeport's
## town pads (the macro's coast under the levelled ground), so "wet" is never
## enough: water is water only where its surface stands over the bed.
static func is_water_at(pos: Vector3) -> bool:
	var wy := water_y(pos)
	return wy != NO_WATER and wy > ground_y(pos) + 0.05


static func water_is_sea(pos: Vector3) -> bool:
	if inst == null or not inst._loaded:
		return false
	var wy := water_y(pos)
	return wy != NO_WATER and absf(wy - inst.sea_level) < 0.4


## Water depth under a position (surface minus bed), 0 on dry ground.
static func water_depth_at(pos: Vector3) -> float:
	var wy := water_y(pos)
	if wy == NO_WATER:
		return 0.0
	return maxf(0.0, wy - ground_y(pos))


const _NEAR_RADII: PackedFloat32Array = [1.5, 3.0, 5.0, 8.0, 12.0, 17.0, 24.0, 33.0, 45.0, 60.0]
const _NEAR_DIRS := 12

## The nearest visible water within max_r: {"dist", "pos", "sea", "depth"},
## or {"dist": INF} when there is none. 120 samples at most, so it is cheap
## enough to ask four times a second. `pos` itself counts as distance 0.
static func nearest_water(pos: Vector3, max_r := 60.0) -> Dictionary:
	if inst == null or not inst._loaded:
		return {"dist": INF}
	if is_water_at(pos):
		return {"dist": 0.0, "pos": Vector3(pos.x, water_y(pos), pos.z), "sea": water_is_sea(pos),
			"depth": water_depth_at(pos)}
	for r in _NEAR_RADII:
		if r > max_r:
			break
		for k in range(_NEAR_DIRS):
			var a := TAU * float(k) / float(_NEAR_DIRS) + r * 0.37
			var p := Vector3(pos.x + cos(a) * r, 0.0, pos.z + sin(a) * r)
			if is_water_at(p):
				return {"dist": r, "pos": Vector3(p.x, water_y(p), p.z), "sea": water_is_sea(p),
					"depth": water_depth_at(p)}
	return {"dist": INF}


## The nearest DRY ground within max_r -- how far a swimmer is from a shore.
static func nearest_dry(pos: Vector3, max_r := 60.0) -> Dictionary:
	if inst == null or not inst._loaded:
		return {"dist": 0.0, "pos": pos}
	if not is_water_at(pos):
		return {"dist": 0.0, "pos": pos}
	for r in _NEAR_RADII:
		if r > max_r:
			break
		for k in range(_NEAR_DIRS):
			var a := TAU * float(k) / float(_NEAR_DIRS) + r * 0.37
			var p := Vector3(pos.x + cos(a) * r, 0.0, pos.z + sin(a) * r)
			if not is_water_at(p):
				return {"dist": r, "pos": Vector3(p.x, ground_y(p), p.z)}
	return {"dist": INF}


## Which way the bed drops away -- where a snapping turtle drags you.
static func deeper_dir(pos: Vector3, r := 6.0) -> Vector3:
	var best := Vector3.ZERO
	var best_d := water_depth_at(pos)
	for k in range(8):
		var a := TAU * float(k) / 8.0
		var d := Vector3(cos(a), 0.0, sin(a))
		var dep := water_depth_at(pos + d * r)
		if dep > best_d + 0.05:
			best_d = dep
			best = d
	return best


# =============================================================================
# SAMPLING
# =============================================================================
func _col_of(wx: float) -> float:
	return (wx - x0) / step


func _row_of(wz: float) -> float:
	return (wz - z0) / step


func _h_at(ix: int, iz: int) -> float:
	ix = clampi(ix, 0, nx - 1)
	iz = clampi(iz, 0, nz - 1)
	var v := _h.decode_u16((iz * nx + ix) * 2)
	return h_min + (float(v) / 65535.0) * (h_max - h_min)


func sample_height(wx: float, wz: float) -> float:
	var fx := _col_of(wx)
	var fz := _row_of(wz)
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var a := _h_at(ix, iz)
	var b := _h_at(ix + 1, iz)
	var c := _h_at(ix, iz + 1)
	var d := _h_at(ix + 1, iz + 1)
	return lerp(lerp(a, b, tx), lerp(c, d, tx), tz)


## A lake surface further above its bed than this is a bake glitch, not a lake
## (one body came out 130 m over its valley). Treated as dry everywhere: the
## water mesh, the swim check and the tree scatter all agree.
const SKY_WATER_MAX := 30.0


func _w_raw(ix: int, iz: int) -> float:
	## The water map's own value at a sample, or NO_WATER. No sanity checks.
	var v := _w.decode_u16((iz * nx + ix) * 2)
	if v == 0:
		return NO_WATER
	return w_min + (float(v - 1) / 65534.0) * (w_max - w_min)


func sample_water(wx: float, wz: float) -> float:
	if _w.size() < nx * nz * 2:
		return NO_WATER
	var ix := clampi(int(round(_col_of(wx))), 0, nx - 1)
	var iz := clampi(int(round(_row_of(wz))), 0, nz - 1)
	var s := _w_raw(ix, iz)
	if s == NO_WATER:
		return NO_WATER
	if s - _h_at(ix, iz) > SKY_WATER_MAX:
		return NO_WATER
	return s


func sample_color(wx: float, wz: float) -> Color:
	if _col == null:
		return Color(0.24, 0.34, 0.18)
	var ix := clampi(int(round(_col_of(wx))), 0, _col.get_width() - 1)
	var iz := clampi(int(round(_row_of(wz))), 0, _col.get_height() - 1)
	return _col.get_pixel(ix, iz)


func pos_in_bounds(pos: Vector3) -> bool:
	return pos.x >= x0 and pos.x <= x0 + float(nx) * step \
		and pos.z >= z0 and pos.z <= z0 + float(nz) * step


## "temperate" / "deepwood" / "highland" -- what the wildlife director and the
## weather ask for. Driven by elevation and distance north, not a painted mask.
func region_for(wx: float, wz: float) -> String:
	var y := sample_height(wx, wz)
	if y > 210.0:
		return "highland"
	var north := (z0 + float(nz) * step - wz) / (float(nz) * step)
	if y > 95.0 or north > 0.55:
		return "deepwood"
	return "temperate"


## The nearest named place within `within` metres, or "".
func place_name_at(pos: Vector3, within: float = 900.0) -> String:
	var best := ""
	var bd := within * within
	for p in _places:
		var q: Array = p["pos"]
		var dx: float = pos.x - float(q[0])
		var dz: float = pos.z - float(q[1])
		var d := dx * dx + dz * dz
		if d < bd:
			bd = d
			best = String(p["name"])
	return best


func places() -> Array:
	return _places


func peaks() -> Array:
	return _peaks


func lakes() -> Array:
	return _lakes


func regions() -> Array:
	return _regions


func story_route() -> Array:
	## Five authored acts from Lewiston to Katahdin. Kept in the terrain bake
	## so the map, quest layer and world tests can never disagree on the route.
	return _story_route


func region_name_at(pos: Vector3) -> String:
	var best := ""
	var bd := INF
	for r in _regions:
		var q: Array = r["pos"]
		var dx: float = pos.x - float(q[0])
		var dz: float = pos.z - float(q[1])
		var d := sqrt(dx * dx + dz * dz)
		if d < float(r.get("r", 500.0)) and d < bd:
			bd = d
			best = String(r["name"])
	return best


# =============================================================================
# GROUND PROVIDER -- Terrain3D
# =============================================================================
## Terrain3D owns the mesh, the LOD and the collider when the addon is present.
## The facade above still answers from the baked r16, so ground_y() is identical
## under either provider and nothing else in the game can tell them apart.
func _t3d_setup() -> void:
	# class_exists() is NOT enough -- TerraBrush's `Terrain` exists and is not
	# instantiable, which is the exact trap that cost us this file's name.
	var t: Object = null
	if ClassDB.can_instantiate("Terrain3D"):
		t = ClassDB.instantiate("Terrain3D")
	if t == null or not (t is Node):
		push_warning("Overworld: could not instantiate Terrain3D; falling back.")
		provider = Provider.BUILTIN
		_build_builtin()
		return
	_t3d = t as Node
	_t3d.name = "Terrain3D"
	_ground_root.add_child(_t3d)
	if _t3d.has_method("set_vertex_spacing"):
		_t3d.set("vertex_spacing", step)
	if _t3d.has_method("set_data_directory") or "data_directory" in _t3d:
		_t3d.set("data_directory", DATA_DIR + "t3d")
	# Region data that has already been imported wins; a first run imports the
	# bake. tools/TerrainImport.gd does the import in the editor, because
	# Terrain3D writes its regions to disk and that is an editor-only job.
	print("Overworld: Terrain3D node up, vertex spacing %.1f m" % step)
	_build_water_all()




# =============================================================================
# GROUND PROVIDER -- the builtin three-ring streamer
# =============================================================================
func _build_builtin() -> void:
	_build_far()
	_build_water_all()


func _process(_delta: float) -> void:
	if not _loaded or provider != Provider.BUILTIN:
		return
	var f := _focus_pos()
	_aim = f + _look_lead()
	if f.distance_to(_focus) > REFOCUS_DIST:
		_focus = f
		_requeue()
	_drain_queue()


## Where the camera is pointing, flattened, times PREFETCH_M. Only the queue
## ORDER is sorted against this -- the want-set still uses the real focus, so
## turning round never evicts the ground you are standing on.
func _look_lead() -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return Vector3.ZERO
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		return Vector3.ZERO
	var lead := PREFETCH_M
	var ps := get_tree().get_nodes_in_group("player")
	if ps.size() > 0 and ps[0].get("mount") != null:
		lead = PREFETCH_RIDE
	return fwd.normalized() * lead


func _focus_pos() -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		return cam.global_position
	var ps := get_tree().get_nodes_in_group("player")
	if ps.size() > 0 and ps[0] is Node3D:
		return (ps[0] as Node3D).global_position
	return Vector3.ZERO


## Build the near ring around `pos` synchronously -- ground, and the real trees
## around it. Teleports call this so there is a world under the body before it
## is dropped.
func warm(pos: Vector3) -> void:
	if provider != Provider.BUILTIN or not _loaded:
		return
	_focus = pos
	_aim = pos
	_flush_jobs(false)
	_requeue()
	while not _queue.is_empty():
		_build_one(_queue.pop_front())
	while not _cell_queue.is_empty():
		_promote_cell(_cell_queue.pop_front())
	_update_ring_visibility()


func rebuild_all() -> void:
	_flush_jobs(false)
	for d in [_near, _mid]:
		for k in d.keys():
			(d[k] as Node).queue_free()
		d.clear()
	_plans.clear()
	_queue.clear()
	_cell_queue.clear()
	_requeue()


func _span_of(ring: int) -> float:
	return NEAR_SPAN if ring == 0 else MID_SPAN


func _requeue() -> void:
	# Start the queue over. It used to only APPEND, so after a long move the
	# tiles wanted at the OLD focus were still built afterwards, out of range,
	# and never freed until the next refocus (measured: 27 of 62 near tiles
	# standing beyond NEAR_RANGE after one teleport).
	_queue.clear()
	for ring in [0, 1]:
		var span := _span_of(ring)
		var rng_m := NEAR_RANGE if ring == 0 else MID_RANGE
		var live: Dictionary = _near if ring == 0 else _mid
		var want: Dictionary = {}
		var r := int(ceil(rng_m / span))
		var cx := int(floor(_focus.x / span))
		var cz := int(floor(_focus.z / span))
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var k := Vector2i(cx + dx, cz + dz)
				if _tile_dist(k, span) > rng_m:
					continue
				want[k] = true
				if not live.has(k):
					_queue.append(Vector3i(k.x, k.y, ring))
		for k in live.keys():
			if not want.has(k):
				(live[k] as Node).queue_free()
				live.erase(k)
				if ring == 0:
					_plans.erase(k)
	# nearest first, and the near ring always beats the mid ring -- "nearest"
	# measured from _aim, ahead of the look, so you build into your travel.
	var aim := Vector2(_aim.x, _aim.z)
	_queue.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.z != b.z:
			return a.z < b.z
		return _tile_dist_to(Vector2i(a.x, a.y), _span_of(a.z), aim) \
			< _tile_dist_to(Vector2i(b.x, b.y), _span_of(b.z), aim))
	_refresh_cells()
	_update_ring_visibility()


func _tile_dist(k: Vector2i, span: float) -> float:
	return _tile_dist_to(k, span, Vector2(_focus.x, _focus.z))


## Tile centre to an arbitrary point. The want-set measures from the focus,
## the build ORDER measures from _aim -- same maths, two questions.
func _tile_dist_to(k: Vector2i, span: float, p: Vector2) -> float:
	var c := Vector2((float(k.x) + 0.5) * span, (float(k.y) + 0.5) * span)
	return c.distance_to(p)


func _drain_queue() -> void:
	var t0 := Time.get_ticks_usec()
	var built := false
	# 1. INSTALL what the workers finished. This is the only part that costs
	#    the main thread anything, and it is metered twice: a hard count and a
	#    millisecond budget checked BEFORE each install rather than after (the
	#    old budget let one whole tile through however long it took).
	var done := 0
	var i := 0
	while i < _jobs.size():
		var job: Array = _jobs[i]
		if not WorkerThreadPool.is_task_completed(int(job[JOB_TASK])):
			i += 1
			continue
		if done >= APPLY_PER_FRAME:
			break
		if done > 0 and float(Time.get_ticks_usec() - t0) / 1000.0 > APPLY_BUDGET_MS:
			break
		_jobs.remove_at(i)
		if _install_job(job):
			built = true
		done += 1
	# 2. TOP THE POOL UP so the threads are never idle waiting for a frame.
	while _jobs.size() < BUILD_JOBS and not _queue.is_empty():
		_dispatch(_queue.pop_front())
	# One cell of real trees a frame, whatever the ground cost. They are the
	# interactive world around the player; the mid ring two kilometres out can
	# wait a frame. (Waiting for the tile queue to drain first meant no real
	# tree for ten seconds after a long move.)
	if not _cell_queue.is_empty():
		_promote_cell(_cell_queue.pop_front())
	if built:
		_update_ring_visibility()


## What the streamer is doing right now -- for the F3 overlay and for anyone
## chasing a hitch. `in_flight` sitting at BUILD_JOBS with a long `queued`
## means the threads are the bottleneck, not the frame.
func stream_stats() -> Dictionary:
	return {
		"near": _near.size(), "mid": _mid.size(), "far": _far.size(),
		"queued": _queue.size(), "in_flight": _jobs.size(),
		"cells_queued": _cell_queue.size(),
	}


func _build_one(e: Vector3i) -> void:
	var k := Vector2i(e.x, e.y)
	var ring := e.z
	var live: Dictionary = _near if ring == 0 else _mid
	if live.has(k):
		return
	var span := _span_of(ring)
	var tile := _make_tile(k, span, TILE_QUADS, ring == 0)
	if tile == null:
		return
	add_child_to_ground(tile)
	live[k] = tile
	# The near ring's forest is a PLAN of slots (see THE FOREST): real,
	# choppable TreeV2s in the cells around the player, the same trees baked
	# into MultiMeshes everywhere else on the tile. Streamed nodes carry meta
	# "streamed": World.save_state skips them and a load calls rebuild_all().
	if ring == 0:
		_plan_tile(k)
		_refresh_tile_cells(k)
	else:
		_scatter_impostors(tile, k, span, ring)


## Hand one tile to the thread pool. The payload Array is created HERE, on the
## main thread, and the worker only writes into slots that already exist.
func _dispatch(e: Vector3i) -> void:
	var k := Vector2i(e.x, e.y)
	var ring := e.z
	var live: Dictionary = _near if ring == 0 else _mid
	if live.has(k):
		return
	for j in _jobs:
		if (j[JOB_KEY] as Vector2i) == k and int(j[JOB_RING]) == ring:
			return
	var job := _new_job(k, ring)
	job[JOB_TASK] = WorkerThreadPool.add_task(
		_tile_arrays.bind(k, _span_of(ring), TILE_QUADS, false, job),
		false, "overworld tile %d,%d" % [k.x, k.y])
	_jobs.append(job)


func _new_job(k: Vector2i, ring: int) -> Array:
	var job: Array = []
	job.resize(JOB_HEIGHT + 1)
	job[JOB_KEY] = k
	job[JOB_RING] = ring
	job[JOB_TASK] = -1
	job[JOB_VERT] = PackedVector3Array()
	job[JOB_COLOR] = PackedColorArray()
	job[JOB_NORMAL] = PackedVector3Array()
	job[JOB_HEIGHT] = PackedFloat32Array()
	return job


## Wait a job's worker out, once. Waiting twice on one task id is an error, so
## the id is spent as it is joined.
func _join(job: Array) -> void:
	if int(job[JOB_TASK]) != -1:
		WorkerThreadPool.wait_for_task_completion(int(job[JOB_TASK]))
		job[JOB_TASK] = -1


## Install a finished job. Returns true if a tile actually landed. A job whose
## tile the last _requeue no longer wants is DROPPED here rather than cancelled
## in flight -- the arithmetic is already paid for, and cancelling a running
## task is not something WorkerThreadPool offers.
func _install_job(job: Array) -> bool:
	_join(job)
	var k: Vector2i = job[JOB_KEY]
	var ring: int = int(job[JOB_RING])
	var live: Dictionary = _near if ring == 0 else _mid
	if live.has(k):
		return false
	var span := _span_of(ring)
	var rng_m := NEAR_RANGE if ring == 0 else MID_RANGE
	if _tile_dist(k, span) > rng_m + span:
		return false
	var tile := _assemble_tile(k, span, TILE_QUADS, ring == 0, job)
	if tile == null:
		return false
	add_child_to_ground(tile)
	live[k] = tile
	# The near ring's forest is a PLAN of slots (see THE FOREST): real,
	# choppable TreeV2s in the cells around the player, the same trees baked
	# into MultiMeshes everywhere else on the tile. Streamed nodes carry meta
	# "streamed": World.save_state skips them and a load calls rebuild_all().
	if ring == 0:
		_plan_tile(k)
		_refresh_tile_cells(k)
	else:
		_scatter_impostors(tile, k, span, ring)
	return true


## Wait every worker out and either install or bin what they made. Called
## before anything that rebuilds or tears the rings down, and on the way out.
func _flush_jobs(install: bool) -> void:
	for job in _jobs:
		_join(job)
		if install:
			_install_job(job)
	_jobs.clear()


func _exit_tree() -> void:
	_flush_jobs(false)


func add_child_to_ground(n: Node) -> void:
	_ground_root.add_child(n)


## A coarse ring is only drawn where the finer ring has not arrived yet. 16
## children exactly cover one parent (512/128 and 2048/512), so "all present"
## is a clean test -- no overlap, no z-fighting, no depth-offset hacks.
func _update_ring_visibility() -> void:
	for k in _mid.keys():
		(_mid[k] as Node3D).visible = not _children_complete(k, _mid_to_near(k), _near)
	for k in _far.keys():
		(_far[k] as Node3D).visible = not _children_complete(k, _far_to_mid(k), _mid)


func _mid_to_near(_k: Vector2i) -> int:
	return int(MID_SPAN / NEAR_SPAN)


func _far_to_mid(_k: Vector2i) -> int:
	return int(FAR_SPAN / MID_SPAN)


func _children_complete(k: Vector2i, n: int, child: Dictionary) -> bool:
	for j in range(n):
		for i in range(n):
			if not child.has(Vector2i(k.x * n + i, k.y * n + j)):
				return false
	return true


func _build_far() -> void:
	var bx := int(ceil(float(nx) * step / FAR_SPAN))
	var bz := int(ceil(float(nz) * step / FAR_SPAN))
	var k0x := int(floor(x0 / FAR_SPAN))
	var k0z := int(floor(z0 / FAR_SPAN))
	var made := 0
	for j in range(bz + 1):
		for i in range(bx + 1):
			var k := Vector2i(k0x + i, k0z + j)
			var blk := _make_tile(k, FAR_SPAN, TILE_QUADS, false, true)
			if blk == null:
				continue
			blk.name = "Far_%d_%d" % [k.x, k.y]
			_ground_root.add_child(blk)
			_scatter_impostors(blk, k, FAR_SPAN, 2, "tiny")
			_far[k] = blk
			made += 1
	var st: Dictionary = forest_stats()
	print("Overworld: far ring = %d blocks of %.0f m, %d distant trees standing"
		% [made, FAR_SPAN, st["trees"]])


# --- meshing -----------------------------------------------------------------
## Wind every ground triangle with +Y as the FRONT face. Godot flips NORMAL on
## back faces even under cull_disabled, so a backwards heightfield lights pitch
## black and every debug variant of the shader looks "broken". Viewed from
## above (+X right, +Z down the screen) the front-facing order is clockwise:
## a -> b -> d then a -> d -> c. tests/TerrainTests.gd asserts the generated
## normal of a flat tile is +Y, so a regression here fails loudly.
func _make_tile(k: Vector2i, span: float, quads: int, with_collision: bool,
		forest_tint: bool = false) -> Node3D:
	var out := _new_job(k, 0)
	_tile_arrays(k, span, quads, forest_tint, out)
	return _assemble_tile(k, span, quads, with_collision, out)


## THE WORKER HALF. Pure arithmetic over the baked heightfield and colour map:
## it touches no node, allocates no resource, calls nothing that is not a read,
## and is therefore safe on a WorkerThreadPool thread. Fills out[JOB_VERT] /
## [JOB_COLOR] / [JOB_NORMAL] / [JOB_HEIGHT] in place.
func _tile_arrays(k: Vector2i, span: float, quads: int, forest_tint: bool,
		out: Array) -> void:
	var ox := float(k.x) * span
	var oz := float(k.y) * span
	var qs := span / float(quads)
	var w := quads + 1

	var heights := PackedFloat32Array()
	heights.resize(w * w)
	## Corner colours ONCE, not four times a quad. Every quad already read the
	## same colour for a shared corner, so this is the identical mesh off a
	## quarter of the sampling: 4,096 get_pixel calls a tile become 1,089.
	var tints := PackedColorArray()
	tints.resize(w * w)
	for j in range(w):
		for i in range(w):
			var sx := ox + float(i) * qs
			var sz := oz + float(j) * qs
			heights[j * w + i] = sample_height(sx, sz)
			tints[j * w + i] = _ground_tint(sx, sz, forest_tint)
	out[JOB_HEIGHT] = heights

	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	for j in range(quads):
		for i in range(quads):
			var wx := ox + (float(i) + 0.5) * qs
			var wz := oz + (float(j) + 0.5) * qs
			# the spawn clearing is a hole: the CaveRegion's grass top is the
			# ground in there, and two surfaces would z-fight. The hole is the
			# region's SQUARE, not a circle -- see HOLE_HALF.
			if in_hole(Vector3(wx, 0.0, wz)):
				continue
			if not pos_in_bounds(Vector3(wx, 0.0, wz)):
				continue
			var ax := ox + float(i) * qs
			var az := oz + float(j) * qs
			var ia := j * w + i
			var ib := ia + 1
			var ic := (j + 1) * w + i
			var id := ic + 1
			var a := Vector3(ax, heights[ia], az)
			var b := Vector3(ax + qs, heights[ib], az)
			var c := Vector3(ax, heights[ic], az + qs)
			var d := Vector3(ax + qs, heights[id], az + qs)
			## Flat normals, computed exactly the way
			## SurfaceTool.generate_normals() computes them on UNINDEXED
			## geometry -- Plane(v0, v1, v2).normal, i.e. (v0 - v2) x (v0 - v1)
			## -- so the mesh is byte-for-byte the one this used to commit.
			## Wound so it comes out +Y: Godot flips NORMAL on back faces even
			## under cull_disabled, and a backwards heightfield lights black.
			var n1 := (a - d).cross(a - b).normalized()
			var n2 := (a - c).cross(a - d).normalized()
			verts.append(a); cols.append(tints[ia]); norms.append(n1)
			verts.append(b); cols.append(tints[ib]); norms.append(n1)
			verts.append(d); cols.append(tints[id]); norms.append(n1)
			verts.append(a); cols.append(tints[ia]); norms.append(n2)
			verts.append(d); cols.append(tints[id]); norms.append(n2)
			verts.append(c); cols.append(tints[ic]); norms.append(n2)

	out[JOB_VERT] = verts
	out[JOB_COLOR] = cols
	out[JOB_NORMAL] = norms


## THE MAIN-THREAD HALF. Turns a finished payload into the node: one ArrayMesh
## surface (no SurfaceTool, no normal generation -- the worker did both) plus
## the heightmap collider. Nothing here samples anything.
func _assemble_tile(k: Vector2i, span: float, quads: int, with_collision: bool,
		out: Array) -> Node3D:
	var verts: PackedVector3Array = out[JOB_VERT]
	if verts.is_empty():
		return null
	var ox := float(k.x) * span
	var oz := float(k.y) * span
	var qs := span / float(quads)
	var heights: PackedFloat32Array = out[JOB_HEIGHT]

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = out[JOB_NORMAL]
	arrays[Mesh.ARRAY_COLOR] = out[JOB_COLOR]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var root := StaticBody3D.new()
	root.name = "T%d_%d_%d" % [int(span), k.x, k.y]
	root.collision_layer = 1
	root.collision_mask = 0
	root.set_meta("streamed", true)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _ground_material()
	if not with_collision:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

	if with_collision:
		var shape := HeightMapShape3D.new()
		shape.map_width = quads + 1
		shape.map_depth = quads + 1
		shape.map_data = _collision_heights(heights, ox, oz, qs, quads)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		# HeightMapShape3D is one unit per sample and centred on its origin.
		# Scaling X and Z (never Y -- that would scale the heights too) puts it
		# on the real grid.
		cs.scale = Vector3(qs, 1.0, qs)
		cs.position = Vector3(ox + span * 0.5, 0.0, oz + span * 0.5)
		root.add_child(cs)
	return root


## The collider's copy of the heights: every sample strictly INSIDE the spawn
## square is sunk to HOLE_SINK. The mesh already leaves the square empty; the
## heightmap shape cannot have holes, so before this it laid an invisible
## floor at y = 0 across the whole CaveRegion -- straight over the two cave
## mouths (their ramps dive to -9 m) and over any hole you dug. Boundary
## samples keep their real height so the collider still meets the rock flush.
func _collision_heights(heights: PackedFloat32Array, ox: float, oz: float,
		qs: float, quads: int) -> PackedFloat32Array:
	var out := heights.duplicate()
	var inner := HOLE_HALF - 0.01
	for j in range(quads + 1):
		var sz := oz + float(j) * qs
		if absf(sz) >= inner:
			continue
		for i in range(quads + 1):
			var sx := ox + float(i) * qs
			if absf(sx) < inner:
				out[j * (quads + 1) + i] = HOLE_SINK
	## [fort] punched collider — same treatment for runtime holes, each with
	## its own sink. Boundary samples keep their real height (Rect2.grow(-0.01))
	## so the collider still meets the surrounding ground flush.
	if _has_extra:
		for j2 in range(quads + 1):
			var sz2 := oz + float(j2) * qs
			for i2 in range(quads + 1):
				var p := Vector2(ox + float(i2) * qs, sz2)
				if not _extra_bounds.has_point(p):
					continue
				for h in _extra_holes:
					var hd: Dictionary = h
					if ((hd["rect"] as Rect2).grow(-0.01)).has_point(p):
						out[j2 * (quads + 1) + i2] = float(hd["sink"])
						break
	return out


## Beyond the impostors the horizon is bare ground colour, and Maine reads as
## farmland to the skyline. Pushing the ground toward canopy green by forest
## weight makes the far ranges look wooded for free -- no geometry at all.
const CANOPY_TINT := Color(0.10, 0.20, 0.11)
const CANOPY_STRENGTH := 0.72


func _ground_tint(wx: float, wz: float, forest_tint: bool) -> Color:
	var c := sample_color(wx, wz)
	if not forest_tint:
		return c
	return c.lerp(CANOPY_TINT, _forest_weight(c) * CANOPY_STRENGTH)


var _ground_mat: Material = null


func _ground_material() -> Material:
	if _ground_mat != null:
		return _ground_mat
	# ResourceLoader.exists() first -- a plain load() of a missing path pushes
	# two errors per boot even when the fallback below handles it fine.
	var sh: Resource = null
	if ResourceLoader.exists("res://shaders/terrain_psx.gdshader"):
		sh = load("res://shaders/terrain_psx.gdshader")
	if sh != null and sh is Shader:
		var sm := ShaderMaterial.new()
		sm.shader = sh
		sm.set_shader_parameter("sea_level", sea_level)
		_ground_mat = sm
	else:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		# The tints are sRGB pixels straight out of maine_color.png. Rendered
		# as linear they come out pastel -- a dark forest green read as mint.
		m.vertex_color_is_srgb = true
		m.roughness = 1.0
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		_ground_mat = m
	return _ground_mat


# =============================================================================
# WATER
# =============================================================================
## The sea is one plane at sea level clipped to the map. Every INLAND body is
## meshed straight off the water map at WATER_QUAD metres, one flat quad per
## wet cell at that cell's own surface -- so a merged body, an unnamed pond and
## a lake whose marker landed on dry ground all get water. (It used to be one
## square plane per NAMED lake, sized by marching out from the marker: Sebago,
## 280 m from spawn, was a dry sand pan, and the six lakes the bake merged into
## one 1.3 km2 body had water under three of their names.)
const WATER_QUAD := 8.0
var _water_mat: Material = null      ## the lakes (tannin water)
var _sea_mat: Material = null        ## the Gulf (colder, greener, murkier)
var _water_refract := true
var _inland_water_quads := 0


## Two materials on one shader: a Maine lake is tea-coloured over a pale bed
## and goes black-green a few metres down; the Gulf is slate over grey-green
## and takes longer to close over. Depth, foam and refraction live in the
## shader (shaders/terrain_water.gdshader, v2).
func _water_material(sea := false) -> Material:
	if sea and _sea_mat != null:
		return _sea_mat
	if not sea and _water_mat != null:
		return _water_mat
	var wsh: Resource = null
	if ResourceLoader.exists("res://shaders/terrain_water.gdshader"):
		wsh = load("res://shaders/terrain_water.gdshader")
	var mat: Material
	if wsh != null and wsh is Shader:
		var sm := ShaderMaterial.new()
		sm.shader = wsh
		if sea:
			sm.set_shader_parameter("shallow_col", Color(0.20, 0.30, 0.30))
			sm.set_shader_parameter("deep_col", Color(0.05, 0.11, 0.15))
			sm.set_shader_parameter("murk_depth", 9.0)
			sm.set_shader_parameter("foam_depth", 0.16)
			sm.set_shader_parameter("ripple", 0.16)
		else:
			sm.set_shader_parameter("shallow_col", Color(0.30, 0.30, 0.16))
			sm.set_shader_parameter("deep_col", Color(0.06, 0.10, 0.07))
			sm.set_shader_parameter("murk_depth", 5.5)
			sm.set_shader_parameter("foam_depth", 0.10)
			sm.set_shader_parameter("ripple", 0.12)
		sm.set_shader_parameter("refract_on", _water_refract)
		mat = sm
	else:
		var st := StandardMaterial3D.new()
		st.albedo_color = Color(0.16, 0.28, 0.36, 0.72)
		st.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		st.roughness = 0.12
		st.metallic = 0.25
		st.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat = st
	if sea:
		_sea_mat = mat
	else:
		_water_mat = mat
	return mat


## Settings -> Water Refraction. The one screen read the water does.
func set_refraction(on: bool) -> void:
	_water_refract = on
	for m in [_water_mat, _sea_mat]:
		if m is ShaderMaterial:
			(m as ShaderMaterial).set_shader_parameter("refract_on", on)


## The sky the water reflects at grazing angles -- World feeds it the
## day/night sky tint so a sunset lies on the lake.
func set_water_sky(c: Color) -> void:
	for m in [_water_mat, _sea_mat]:
		if m is ShaderMaterial:
			(m as ShaderMaterial).set_shader_parameter("sky_col", c)


func _build_water_all() -> void:
	if _w.size() < nx * nz * 2:
		return
	var wmat := _water_material(false)

	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(float(nx) * step, float(nz) * step)
	sea.mesh = pm
	sea.material_override = _water_material(true)
	sea.position = Vector3(x0 + float(nx) * step * 0.5, sea_level,
		z0 + float(nz) * step * 0.5)
	sea.name = "Sea"
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_water_root.add_child(sea)

	var t0 := Time.get_ticks_msec()
	var lake_mesh := _build_inland_water()
	if lake_mesh != null:
		lake_mesh.material_override = wmat
		lake_mesh.name = "Lakes"
		lake_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_water_root.add_child(lake_mesh)
	print("Overworld: inland water = %d quads of %.0f m in %d ms"
		% [_inland_water_quads, WATER_QUAD, Time.get_ticks_msec() - t0])


## One quad per wet cell (at WATER_QUAD stride) whose surface is not the sea's
## and sits a sane height over its bed. Built straight into packed arrays: the
## map is 1.2 M samples and SurfaceTool per vertex would be a two-second boot.
func _build_inland_water() -> MeshInstance3D:
	var stride := maxi(1, int(round(WATER_QUAD / step)))
	var q := float(stride) * step
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var n := 0
	var iz := 0
	while iz < nz:
		var wz := z0 + float(iz) * step
		var ix := 0
		while ix < nx:
			var s := _w_raw(ix, iz)
			if s != NO_WATER and absf(s - sea_level) >= 0.4 and s - _h_at(ix, iz) <= SKY_WATER_MAX:
				var wx := x0 + float(ix) * step
				var b := verts.size()
				verts.append(Vector3(wx, s, wz))
				verts.append(Vector3(wx + q, s, wz))
				verts.append(Vector3(wx + q, s, wz + q))
				verts.append(Vector3(wx, s, wz + q))
				# +Y front face: clockwise seen from above (same rule as the ground)
				idx.append(b); idx.append(b + 1); idx.append(b + 2)
				idx.append(b); idx.append(b + 2); idx.append(b + 3)
				n += 1
			ix += stride
		iz += stride
	_inland_water_quads = n
	if n == 0:
		return null
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	norms.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	return mi


# =============================================================================
# THE FOREST
# =============================================================================
# One forest, three costs. Around the player the trees are real TreeV2s --
# choppable, fellable, the whole tree system. Everywhere else they are the SAME
# trees baked into MultiMeshes: a trunk with its biggest branches close in,
# a trunk with a faceted crown further out, a stick with a crown on the
# horizon. That is the only way 78 square kilometres of Maine can be forested;
# 40,000 procedural trees is not a tuning problem, it is a different engine.
#
# THE NEAR RING IS A PLAN, NOT A SCATTER. Each near tile rolls its slots once
# (position, species, scale, seed -- deterministic in the tile key) and groups
# them into CELL m cells. A cell within REAL_R of the focus is PROMOTED: its
# slots become real trees. Walk away and it is DEMOTED back into the tile's
# MultiMesh. So the real, interactive woods travel WITH you instead of staying
# wherever a tile happened to be built -- which is what they used to do, and
# why every tree past the first ring was a walk-through impostor.
#
# A tree you fell is remembered by slot in _felled (saved with the world), so
# neither the impostor nor a fresh tree ever grows back in a stump's place.
#
# FPS DIALS, in the order worth touching:
#   REAL_R            how far the real, interactive trees reach
#   TREE_VIS_END      how far ANY real tree draws (they still exist, unseen)
#   REAL_CAP          slots per near tile (real or baked, same number)
#   LOD_DENSITY       density of the fake forest on the mid ring
## MASTER SWITCH for the whole procedural forest -- the near ring's real
## TreeV2s, the mid/far impostor MultiMeshes, all of it. Off 2026-09-02
## (Lemon: "remove all trees for now... I want to hand place them"). On
## again 2026-09-17: walking and riding are the game, and 78 km² cannot
## be hand-planted. Camp still stays bald (FOREST_INNER_R); F1 placements
## keep working. Deterministic in the tile key, so the same wood returns.
const SCATTER := true
const REAL_R := 155.0             ## real TreeV2s; extra metres for an 11 m/s gallop
const REAL_R_HYST := 28.0         ## ...and they stay real this much further out
const REAL_DENSITY := 0.019       ## trees per m^2 at full forest weight
const TREE_MIN_GAP := 2.1         ## matches World.TREE_MIN_GAP
const REAL_CAP := 90              ## per near tile, whatever the noise says
const TREE_VIS_END := 210.0       ## keep real trees on-screen through a gallop
const TREE_VIS_FADE := 36.0
const CELL := 32.0                ## a near tile is 4 x 4 cells

const LOD_SCALE_MIN := 0.72
const LOD_SCALE_MAX := 1.45
const LOD_ELDER_CHANCE := 0.04     ## matches TreeV2.make()
const LOD_ELDER_SCALE := 1.7

var _plans: Dictionary = {}        ## Vector2i near key -> plan Dictionary
var _cell_queue: Array[Vector3i] = []   ## (kx, kz, cell) waiting to become real
var _felled: Dictionary = {}       ## "kx,kz,slot" -> true, forever


func _forest_weight(c: Color) -> float:
	# The colour map's forest is a dark green, its meadow a yellow-green, its
	# sand and seabed neither. This is the same weight the terrain editor's
	# paint tool drives: paint Meadow to clear a field, Forest to thicken.
	return clampf((c.g - c.r * 0.9 - c.b * 0.6) * 8.0, 0.0, 1.0)


## Camp clearing: hand-placed / god-editor trees only. Streamed woods start
## just past World.WORLD_RADIUS so a gallop out of camp hits a real stand
## instead of a 100 m bald ring.
const FOREST_INNER_R := 82.0


func _plantable(wx: float, wz: float) -> float:
	## 0 where nothing grows -- water, the camp clearing, off-map -- else the
	## forest weight of the ground colour.
	if Vector2(wx, wz).length() < FOREST_INNER_R:
		return 0.0        # the camp keeps its own hand-placed forest
	if not pos_in_bounds(Vector3(wx, 0.0, wz)):
		return 0.0
	var gy := sample_height(wx, wz)
	var wy := sample_water(wx, wz)
	if wy != NO_WATER and wy > gy - 0.2:
		return 0.0        # no trees in the lake
	return _forest_weight(sample_color(wx, wz))


# --- the plan ----------------------------------------------------------------
func _cells_per_tile() -> int:
	return int(NEAR_SPAN / CELL)


func _cell_index(wx: float, wz: float, k: Vector2i) -> int:
	var n := _cells_per_tile()
	var ci := clampi(int(floor((wx - float(k.x) * NEAR_SPAN) / CELL)), 0, n - 1)
	var cj := clampi(int(floor((wz - float(k.y) * NEAR_SPAN) / CELL)), 0, n - 1)
	return cj * n + ci


func _cell_centre(k: Vector2i, cell: int) -> Vector2:
	var n := _cells_per_tile()
	var ci := cell % n
	@warning_ignore("integer_division")
	var cj := cell / n
	return Vector2(float(k.x) * NEAR_SPAN + (float(ci) + 0.5) * CELL,
		float(k.y) * NEAR_SPAN + (float(cj) + 0.5) * CELL)


func _slot_key(k: Vector2i, slot: int) -> String:
	return "%d,%d,%d" % [k.x, k.y, slot]


## Roll a near tile's slots. Deterministic in the tile key: walk away, walk
## back, the same trees stand in the same places.
func _plan_tile(k: Vector2i) -> Dictionary:
	if _plans.has(k):
		return _plans[k]
	var plan := {
		"pos": PackedVector3Array(), "species": PackedStringArray(),
		"scale": PackedFloat32Array(), "seed": PackedInt32Array(),
		"cell": PackedInt32Array(),
		"state": PackedInt32Array(),      ## per cell: 0 baked, 1 real
		"lod": PackedStringArray(),       ## per cell: which bake it wears
		"nodes": [],                      ## per cell: Array of the real nodes
		"dirty": true,
	}
	var ncell := _cells_per_tile() * _cells_per_tile()
	var st := PackedInt32Array()
	st.resize(ncell)
	st.fill(0)
	plan["state"] = st
	var lods := PackedStringArray()
	lods.resize(ncell)
	lods.fill("")
	plan["lod"] = lods
	var nodes: Array = []
	nodes.resize(ncell)
	for i in range(ncell):
		nodes[i] = []
	plan["nodes"] = nodes
	_plans[k] = plan
	if not SCATTER:
		return plan
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(k.x, k.y)) ^ 0x5EED
	var ox := float(k.x) * NEAR_SPAN
	var oz := float(k.y) * NEAR_SPAN
	var tries := int(NEAR_SPAN * NEAR_SPAN * REAL_DENSITY)
	var placed: Array[Vector2] = []
	# Packed arrays are VALUE types: `plan["pos"].append()` appends to a copy
	# and the plan stays empty (the grass v2 trap, met again here). Build
	# locals and assign them in at the end.
	var pos := PackedVector3Array()
	var species := PackedStringArray()
	var scales := PackedFloat32Array()
	var seeds := PackedInt32Array()
	var cells := PackedInt32Array()
	for _i in range(tries):
		if placed.size() >= REAL_CAP:
			break
		var wx := ox + rng.randf() * NEAR_SPAN
		var wz := oz + rng.randf() * NEAR_SPAN
		var w := _plantable(wx, wz)
		if w <= 0.0 or rng.randf() > w:
			continue
		var here := Vector2(wx, wz)
		var clear := true
		for q in placed:
			if q.distance_to(here) < TREE_MIN_GAP:
				clear = false
				break
		if not clear:
			continue
		placed.append(here)
		pos.append(Vector3(wx, sample_height(wx, wz), wz))
		species.append(_species_for(wx, wz, rng))
		var sc := rng.randf_range(LOD_SCALE_MIN, LOD_SCALE_MAX)
		if rng.randf() < LOD_ELDER_CHANCE:
			sc *= LOD_ELDER_SCALE
		scales.append(sc)
		seeds.append(rng.randi())
		cells.append(_cell_index(wx, wz, k))
	plan["pos"] = pos
	plan["species"] = species
	plan["scale"] = scales
	plan["seed"] = seeds
	plan["cell"] = cells
	return plan


## Decide, for every near tile, which cells are real and which bake the rest
## wear. Called whenever the focus has moved REFOCUS_DIST.
func _refresh_cells() -> void:
	for k in _near.keys():
		if _plans.has(k):
			_refresh_tile_cells(k)


func _refresh_tile_cells(k: Vector2i) -> void:
	var plan: Dictionary = _plans[k]
	var state: PackedInt32Array = plan["state"]
	var lods: PackedStringArray = plan["lod"]
	var f := Vector2(_focus.x, _focus.z)
	var dirty: bool = plan["dirty"]
	for c in range(state.size()):
		var d := _cell_centre(k, c).distance_to(f)
		if state[c] == 1:
			if d > REAL_R + REAL_R_HYST:
				_demote_cell(k, c)
				dirty = true
		else:
			if d <= REAL_R:
				var e := Vector3i(k.x, k.y, c)
				if not _cell_queue.has(e):
					_cell_queue.append(e)
			var want := _lod_for(d)
			if want == "tiny":
				want = "far"          ## the near ring never wears sticks
			if lods[c] != want:
				lods[c] = want
				dirty = true
	plan["lod"] = lods
	if dirty:
		_rebuild_impostors(k)
	plan["dirty"] = false
	# nearest cell first
	_cell_queue.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return _cell_centre(Vector2i(a.x, a.y), a.z).distance_to(f) \
			< _cell_centre(Vector2i(b.x, b.y), b.z).distance_to(f))


## Make one cell's slots real trees. The impostor MultiMesh drops them in the
## same call, so a slot is never drawn twice.
func _promote_cell(e: Vector3i) -> void:
	var k := Vector2i(e.x, e.y)
	if not _near.has(k) or not _plans.has(k):
		return
	var tile: Node3D = _near[k]
	var plan: Dictionary = _plans[k]
	var state: PackedInt32Array = plan["state"]
	if state[e.z] == 1:
		return
	var tree_script := load("res://scripts/TreeV2.gd")
	if tree_script == null:
		return
	var pos: PackedVector3Array = plan["pos"]
	var species: PackedStringArray = plan["species"]
	var seeds: PackedInt32Array = plan["seed"]
	var cells: PackedInt32Array = plan["cell"]
	var made: Array = []
	for i in range(pos.size()):
		if cells[i] != e.z or _felled.has(_slot_key(k, i)):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = seeds[i]
		var t: Node3D = tree_script.make(rng, species[i], -1, region_for(pos[i].x, pos[i].z))
		if t == null:
			continue
		t.position = pos[i]
		t.rotation.y = rng.randf() * TAU
		t.set_meta("streamed", true)
		t.set_meta("slot", i)
		tile.add_child(t)
		_range_limit(t)
		made.append(t)
	state[e.z] = 1
	plan["state"] = state
	(plan["nodes"] as Array)[e.z] = made
	_rebuild_impostors(k)


## Take a cell's real trees down and let the bake draw them again. A slot
## whose tree is gone -- felled, blasted over by a meteor -- goes into the
## ledger first, so nothing grows back in its place.
func _demote_cell(k: Vector2i, cell: int) -> void:
	var plan: Dictionary = _plans[k]
	var state: PackedInt32Array = plan["state"]
	if state[cell] != 1:
		return
	var nodes: Array = (plan["nodes"] as Array)[cell]
	# felled = every slot in the cell that no longer has a standing tree
	var cells: PackedInt32Array = plan["cell"]
	var standing: Dictionary = {}
	for n in nodes:
		var t := n as Node
		if t != null and is_instance_valid(t) and not bool(t.get("felled")):
			standing[int(t.get_meta("slot", -1))] = true
	for i in range(cells.size()):
		if cells[i] == cell and not standing.has(i):
			_felled[_slot_key(k, i)] = true
	for n in nodes:
		var t := n as Node
		if t != null and is_instance_valid(t):
			t.queue_free()
	(plan["nodes"] as Array)[cell] = []
	state[cell] = 0
	plan["state"] = state


## How many slots are real right now, over all near tiles.
func real_tree_count() -> int:
	var n := 0
	for k in _plans.keys():
		for cell_nodes in (_plans[k]["nodes"] as Array):
			for t in (cell_nodes as Array):
				if t != null and is_instance_valid(t):
					n += 1
	return n


func felled_count() -> int:
	return _felled.size()


## What the world remembers about the streamed forest: which slots have been
## cut. World.save_state stores this; apply_state hands it back before the
## rebuild, so a load never regrows a tree over its own stump.
func save_state() -> Dictionary:
	return {"felled": _felled.keys()}


func apply_state(d: Dictionary) -> void:
	_felled.clear()
	for key in d.get("felled", []):
		_felled[String(key)] = true


## The trees have never had a visibility range -- 420 of them all drew at once,
## which is why the valley was already heavy. Every MeshInstance under a
## streamed tree now fades out past TREE_VIS_END and hands off to the impostor
## forest, which is drawing the same woods for a fraction of the cost.
func _range_limit(n: Node) -> void:
	var gi := n as GeometryInstance3D
	if gi != null:
		gi.visibility_range_end = TREE_VIS_END
		gi.visibility_range_end_margin = TREE_VIS_FADE
		gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	for c in n.get_children():
		_range_limit(c)


## Rebuild a near tile's MultiMeshes from every slot that is not real and not
## felled, grouped by species and by the bake its cell wears.
func _rebuild_impostors(k: Vector2i) -> void:
	if not _near.has(k) or not _plans.has(k):
		return
	var tile: Node3D = _near[k]
	for c in tile.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("Forest_"):
			tile.remove_child(c)
			c.queue_free()
	if not SCATTER:
		return
	var plan: Dictionary = _plans[k]
	var pos: PackedVector3Array = plan["pos"]
	var species: PackedStringArray = plan["species"]
	var scales: PackedFloat32Array = plan["scale"]
	var seeds: PackedInt32Array = plan["seed"]
	var cells: PackedInt32Array = plan["cell"]
	var state: PackedInt32Array = plan["state"]
	var lods: PackedStringArray = plan["lod"]
	var groups: Dictionary = {}          ## "species|lod" -> Array[Transform3D]
	for i in range(pos.size()):
		var cell := cells[i]
		if state[cell] == 1 or _felled.has(_slot_key(k, i)):
			continue
		var lod := lods[cell] if lods[cell] != "" else "far"
		var key := species[i] + "|" + lod
		var sc := scales[i]
		var t := Transform3D(Basis.IDENTITY, pos[i])
		t.basis = t.basis.rotated(Vector3.UP, float(seeds[i] % 6283) * 0.001).scaled(Vector3(sc, sc, sc))
		if not groups.has(key):
			groups[key] = ([] as Array[Transform3D])
		(groups[key] as Array).append(t)
	for key in groups.keys():
		var parts: PackedStringArray = String(key).split("|")
		_add_forest_multimesh(tile, parts[0], parts[1], groups[key])


## How many patches a mid tile or a far block is split into per axis before its
## trees become MultiMeshes. See the note in _scatter_impostors: a MultiMesh is
## frustum-culled as one object, so an unsplit 2 km block is never culled.
const SUB_SPLIT := 4


func _add_forest_multimesh(tile: Node3D, sp: String, lod: String, xf: Array,
		tag: String = "") -> void:
	var mesh := _bake_species(sp, lod)
	if mesh == null or xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in range(xf.size()):
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Forest_%s_%s%s" % [sp, lod, ("_" + tag) if tag != "" else ""]
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if lod != "mid":
		## An impostor is a quad that SPINS to face you, so the space it can
		## occupy is a cylinder — but the MultiMesh's bounds come from the
		## mesh's flat vertex rect (ArrayMesh.custom_aabb is set and get_aabb()
		## ignores it, verified live). Without a margin a patch pops out at the
		## screen edge the moment its quads turn edge-on. Half the widest tree,
		## times the biggest scale the scatter rolls.
		mmi.extra_cull_margin = 12.0
	tile.add_child(mmi)


# --- the distant forest: the REAL trees, baked down and frozen ---------------
# Past REAL_R you are still looking at Myrkfell's own trees. Same GLB models,
# same bark textures, same leaf atlas, same season ramp -- baked into a
# MultiMesh instead of a node each, and drawn with TreeV2's NO-WIND leaf
# material (materials_for()[2], `animated = 0.0`). The far woods stand
# perfectly still while the close ones move in the gusts, which is both what a
# forest looks like from half a mile off and most of why this runs at all.
#
# Measured on the real models (mature stage, tris per tree):
#
#            trunk only    +25% branches    every branch
#   maple          121            1279             4944
#   oak            121            1284             4455
#   birch          125            2128             6815
#   pine           125             958             3414
#   fir            125            2092             7690
#
# The trunk is ~123 triangles; the branches are ALL of the cost. So the ladder
# spends its budget on branches only where you can see them:
#
#   mid    real trunk + the biggest 25% of branches      ~1,500 tris
#   far    one billboard wearing a photo of the tree           2 tris
#   tiny   the same billboard                                  2 tris
#
# SUPERSEDED 2026-09-01 — the note below is why the blob existed, kept because
# it is also why the OBVIOUS fix (leaf cards at distance) does not work. The
# `far` and `tiny` tiers are now one billboard wearing a rendered PHOTOGRAPH of
# the real tree: scripts/TreeImpostor.gd, shaders/impostor.gdshader. That has
# the constant-alpha property the blob was reaching for -- an impostor's
# silhouette is one tree-shaped mass, not a scatter of cutouts, so the mips
# cannot erase it -- while actually looking like a tree, and it waves.
#
# THE CROWN IS A BLOB, NOT A CARD. The first version hung two crossed quads
# UV'd across the whole leaf atlas -- an atlas that is 66% clear texels with
# a black background under them. Up close the cut kept a sparse sprinkle of
# leaves; at distance the mipmaps averaged alpha under the cut and the cards
# vanished, leaving bare trunks: the distant woods read as dead white sticks.
# A crown is now a few faceted bipyramids with EVERY vertex pinned to one
# solid texel of the species' atlas (BLOB_UV). Constant UV means the GPU
# samples mip 0 at any distance, the alpha is 1, and the season ramp, snow
# and autumn colour still come from the same shader as the real leaves.
const LOD_STAGE := 2               ## mature: the tree a wood is actually made of
const LOD_MID_KEEP := 0.25         ## fraction of branches kept in the mid bake
## 2026-09-01: the geometry tier reaches FURTHER than it did (260 -> 330 m),
## because the tier past it went from 195 triangles a tree to 2. Killing the
## blob bake paid for the extension several times over — a far block used to
## carry ~292k triangles of faceted crowns and now carries ~3k of billboards.
const LOD_MID_DIST := 330.0        ## tile distance: real branchy bake within this
## Past LOD_MID_DIST every tier is the same thing — one billboard wearing a
## photo of the real tree (TreeImpostor). `far` and `tiny` are kept as separate
## names only because the scatter's density and caps are keyed on them.
const LOD_FAR_DIST := 900.0
const LOD_DENSITY := {"mid": 0.004, "far": 0.005, "tiny": 0.007}
const LOD_CAP := {"mid": 220, "far": 1500, "tiny": 2200}
## The far ring covers the WHOLE map, so it gets trees too -- thin, and always
## at the cheapest tier. Without this the forest simply stopped at MID_RANGE
## and the last four kilometres were tinted ground pretending to be woods.
const FAR_BLOCK_DENSITY := 0.0015
const FAR_BLOCK_CAP := 3000
const LOD_SPECIES := {
	"temperate": ["maple", "oak", "birch", "maple", "birch"],
	"deepwood": ["pine", "fir", "birch", "pine", "pine"],
	"highland": ["fir", "pine", "fir", "pine", "fir"],
}
## A texel inside each species' leaf atlas with alpha 1 for at least 9 x 9
## texels around it (measured off the PNGs). Pinned onto the crown blobs.
const BLOB_UV := {
	"maple": Vector2(0.299, 0.198), "birch": Vector2(0.179, 0.272),
	"oak": Vector2(0.295, 0.212), "pine": Vector2(0.168, 0.216),
	"fir": Vector2(0.133, 0.962),
}
## Crown blobs per far tree: offset (fraction of crown size), radius scale.
const CROWN_LOBES := [
	[Vector3(0.0, 0.0, 0.0), 1.0],
	[Vector3(0.38, 0.22, 0.10), 0.62],
	[Vector3(-0.30, 0.34, -0.26), 0.58],
]

var _baked: Dictionary = {}        ## "species|lod" -> ArrayMesh


func _lod_for(d: float) -> String:
	if d <= LOD_MID_DIST:
		return "mid"
	return "far" if d <= LOD_FAR_DIST else "tiny"


## Bake one species at one detail level into a two-surface mesh: wood, then
## leaf. Cached forever -- this instantiates a glTF scene and is far too
## expensive to do per tile.
func _bake_species(species: String, lod: String) -> ArrayMesh:
	## `far` and `tiny` are not baked geometry any more — they are one
	## billboard wearing a photograph of the real tree (scripts/TreeImpostor.gd
	## and shaders/impostor.gdshader). Deliberately NOT cached in `_baked`:
	## TreeImpostor hands back null until its first render lands, and caching
	## that null would leave the distant forest empty for the whole session.
	## `impostors_ready` fires once and _rebuild_all_impostors() picks it up.
	if lod != "mid":
		return TreeImpostor.mesh_for(species)
	var key := species + "|" + lod
	if _baked.has(key):
		return _baked[key]
	_baked[key] = null                      ## remember failures too, and shut up
	var path := "res://assets/trees/glb/%s_%d_%s.glb" % [species, LOD_STAGE, "mature"]
	if not ResourceLoader.exists(path):
		push_warning("Overworld: no model at %s -- the far forest loses %s." % [path, species])
		return null
	var packed = load(path)
	if packed == null:
		return null
	var model: Node3D = packed.instantiate()
	var parts: Node = model
	if model.get_child_count() == 1 and model.get_child(0).get_child_count() > 0:
		parts = model.get_child(0)          ## Godot wraps the glTF scene in a root

	var trunks: Array[MeshInstance3D] = []
	var limbs: Array[MeshInstance3D] = []
	var box := AABB()
	var first := true
	for c in parts.get_children():
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var b := mi.transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
		if mi.name.begins_with("Trunk"):
			trunks.append(mi)
		else:
			limbs.append(mi)
	if first:
		model.queue_free()
		return null
	# biggest limbs first, so a cheap bake keeps the branches that read
	limbs.sort_custom(func(a: MeshInstance3D, b: MeshInstance3D) -> bool:
		return a.mesh.get_aabb().get_volume() > b.mesh.get_aabb().get_volume())

	var wood := SurfaceTool.new()
	var leaf := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	leaf.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nw := 0
	var nl := 0

	if lod == "mid":
		var keep := maxi(1, int(ceil(float(limbs.size()) * LOD_MID_KEEP)))
		for mi in (trunks + limbs.slice(0, keep)):
			for i in range(mi.mesh.get_surface_count()):
				# leaf or wood is decided by the glTF material NAME, exactly as
				# TreeV2._apply_materials does it -- surface indices do not line
				# up between a bare trunk and a leafy branch.
				var src: Material = mi.mesh.surface_get_material(i)
				var nm := str(src.resource_name) if src != null else ""
				if nm.findn("leaf") >= 0 or nm.findn("foliage") >= 0:
					leaf.append_from(mi.mesh, i, mi.transform)
					nl += 1
				else:
					wood.append_from(mi.mesh, i, mi.transform)
					nw += 1
	else:
		## RETIRED 2026-09-01 (Lemon: "completely remove the blob trees").
		## `far` and `tiny` used to bake a crown out of three faceted
		## bipyramids with every vertex pinned to one opaque texel of the leaf
		## atlas (_crown / CROWN_LOBES / BLOB_UV). It was 195 triangles and it
		## read as a green gem on a stick from every distance you could see it.
		## Both tiers are now a single billboard wearing a PHOTOGRAPH of the
		## real tree — scripts/TreeImpostor.gd, two triangles, and it waves.
		## _crown(), _stick() and BLOB_UV are kept below, unused, so the old
		## bake is one line away if the impostor ever has to come out.
		model.queue_free()
		return null

	model.queue_free()
	if nw == 0 and nl == 0:
		return null

	var mats: Array = load("res://scripts/TreeV2.gd").materials_for(species, false)
	var am := ArrayMesh.new()
	if nw > 0:
		wood.generate_normals()
		wood.commit(am)
		am.surface_set_material(am.get_surface_count() - 1, mats[0])
	if nl > 0:
		leaf.generate_normals()
		leaf.commit(am)
		# mats[2] is the inner-canopy variant: same species, same season ramp,
		# a shade darker, and `animated = 0.0`. The distant forest is still.
		am.surface_set_material(am.get_surface_count() - 1,
			mats[2] if mats.size() > 2 else mats[1])
	_baked[key] = am
	return am


func _stick(st: SurfaceTool, box: AABB) -> void:
	var h := box.size.y
	var r := maxf(box.size.x, box.size.z) * 0.030
	for i in range(4):
		var a0 := TAU * float(i) / 4.0
		var a1 := TAU * float(i + 1) / 4.0
		var b0 := Vector3(cos(a0) * r, box.position.y, sin(a0) * r)
		var b1 := Vector3(cos(a1) * r, box.position.y, sin(a1) * r)
		var t0 := Vector3(cos(a0) * r * 0.4, box.position.y + h, sin(a0) * r * 0.4)
		var t1 := Vector3(cos(a1) * r * 0.4, box.position.y + h, sin(a1) * r * 0.4)
		st.set_uv(Vector2(0, 0)); st.add_vertex(b0)
		st.set_uv(Vector2(0, 1)); st.add_vertex(t0)
		st.set_uv(Vector2(1, 1)); st.add_vertex(t1)
		st.set_uv(Vector2(0, 0)); st.add_vertex(b0)
		st.set_uv(Vector2(1, 1)); st.add_vertex(t1)
		st.set_uv(Vector2(1, 0)); st.add_vertex(b1)


## The crown: `lobes` faceted lumps filling the real crown's box, every vertex
## on the one solid atlas texel `uv`. Each lump is an apex, two six-point rings
## and a base -- 24 triangles -- rounder on top than a plain bipyramid so a
## maple reads as a canopy and not a gem. A conifer gets its wide ring low and
## its narrow ring high: a spire, not a ball.
func _crown(st: SurfaceTool, box: AABB, uv: Vector2, conifer: bool, lobes: int) -> void:
	var cx := box.position.x + box.size.x * 0.5
	var cz := box.position.z + box.size.z * 0.5
	var crown_r := maxf(box.size.x, box.size.z) * 0.46
	var y0 := box.position.y + box.size.y * (0.14 if conifer else 0.30)
	var y1 := box.position.y + box.size.y
	var ch := y1 - y0
	# ring heights (fraction of the lobe) and radii (fraction of the lobe's r)
	var lo_h := 0.12 if conifer else 0.30
	var lo_r := 1.00 if conifer else 0.78
	var hi_h := 0.48 if conifer else 0.72
	var hi_r := 0.55 if conifer else 1.00
	for li in range(lobes):
		var lobe: Array = CROWN_LOBES[li]
		var off: Vector3 = lobe[0]
		var rs: float = lobe[1]
		var c := Vector3(cx + off.x * crown_r, y0 + off.y * ch, cz + off.z * crown_r)
		var r := crown_r * rs
		var h := ch * rs
		var top := c + Vector3(0.0, h, 0.0)
		var bot := c
		var ring_lo: Array[Vector3] = []
		var ring_hi: Array[Vector3] = []
		for i in range(6):
			var a := TAU * float(i) / 6.0 + float(li) * 0.5
			# a little radial wobble so six lobes are not six identical gems
			var wob := 0.86 + 0.28 * fposmod(float(i * 7 + li * 3) * 0.61803, 1.0)
			var wob2 := 0.88 + 0.24 * fposmod(float(i * 5 + li * 11) * 0.61803, 1.0)
			ring_lo.append(c + Vector3(cos(a) * r * lo_r * wob, h * lo_h, sin(a) * r * lo_r * wob))
			ring_hi.append(c + Vector3(cos(a + 0.3) * r * hi_r * wob2, h * hi_h, sin(a + 0.3) * r * hi_r * wob2))
		for i in range(6):
			var j := (i + 1) % 6
			# Same winding rule as the ground (see _make_tile): increasing polar
			# angle about the axis = a face whose normal points UP and out. The
			# apex fan and the band run i -> j, the base fan j -> i (down and
			# out). tests/TerrainTests.gd checks the crown's normals.
			st.set_uv(uv); st.add_vertex(top)
			st.set_uv(uv); st.add_vertex(ring_hi[i])
			st.set_uv(uv); st.add_vertex(ring_hi[j])
			# the band between the rings, two triangles
			st.set_uv(uv); st.add_vertex(ring_hi[i])
			st.set_uv(uv); st.add_vertex(ring_lo[i])
			st.set_uv(uv); st.add_vertex(ring_lo[j])
			st.set_uv(uv); st.add_vertex(ring_hi[i])
			st.set_uv(uv); st.add_vertex(ring_lo[j])
			st.set_uv(uv); st.add_vertex(ring_hi[j])
			# the base fan
			st.set_uv(uv); st.add_vertex(bot)
			st.set_uv(uv); st.add_vertex(ring_lo[j])
			st.set_uv(uv); st.add_vertex(ring_lo[i])


## Two crossed quads filling the real crown's box, UV'd across the whole leaf
## atlas. Retired from the bakes (see the crown note above); kept for the leaf
## burst and anything else that wants a card.
func _cards(st: SurfaceTool, box: AABB) -> void:
	var hw := maxf(box.size.x, box.size.z) * 0.42
	var y0 := box.position.y + box.size.y * 0.28
	var y1 := box.position.y + box.size.y * 1.0
	var cx := box.position.x + box.size.x * 0.5
	var cz := box.position.z + box.size.z * 0.5
	for pass_i in range(2):
		var ux := hw if pass_i == 0 else 0.0
		var uz := 0.0 if pass_i == 0 else hw
		var p0 := Vector3(cx - ux, y0, cz - uz)
		var p1 := Vector3(cx + ux, y0, cz + uz)
		var p2 := Vector3(cx + ux, y1, cz + uz)
		var p3 := Vector3(cx - ux, y1, cz - uz)
		st.set_uv(Vector2(0, 1)); st.add_vertex(p0)
		st.set_uv(Vector2(1, 1)); st.add_vertex(p1)
		st.set_uv(Vector2(1, 0)); st.add_vertex(p2)
		st.set_uv(Vector2(0, 1)); st.add_vertex(p0)
		st.set_uv(Vector2(1, 0)); st.add_vertex(p2)
		st.set_uv(Vector2(0, 0)); st.add_vertex(p3)


func _species_for(wx: float, wz: float, rng: RandomNumberGenerator) -> String:
	var list: Array = LOD_SPECIES.get(region_for(wx, wz), LOD_SPECIES["temperate"])
	return String(list[rng.randi() % list.size()])


## Fill a MID tile or a FAR block with the distant forest. (Near tiles are
## planned instead -- see _plan_tile.) Both vanish automatically when a finer
## ring arrives, because the MultiMeshes are children of the tile.
func _scatter_impostors(tile: Node3D, k: Vector2i, span: float, ring: int,
		force_lod: String = "") -> void:
	if not SCATTER:
		return
	var lod := force_lod if force_lod != "" else _lod_for(_tile_dist(k, span))
	var dens: float = FAR_BLOCK_DENSITY if force_lod != "" else float(LOD_DENSITY[lod])
	var cap: int = FAR_BLOCK_CAP if force_lod != "" else int(LOD_CAP[lod])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(k.x, k.y, ring)) ^ 0x51A7
	var ox := float(k.x) * span
	var oz := float(k.y) * span
	var tries := int(span * span * dens)

	## Grouped by species AND by a SUB_SPLIT x SUB_SPLIT patch of the tile, not
	## by species alone. Lemon 2026-09-01: "whatever's not being rendered isn't
	## being rendered." A MultiMesh is culled as ONE object against its whole
	## bounding box, so a far block used to be a single 2 km-wide draw covering
	## 3,000 trees — always in frustum, wherever you looked. Sixteen patches of
	## 512 m each get frustum-culled properly: standing in the open with a 70°
	## FOV, most of them are behind you.
	var by_species: Dictionary = {}         ## "species|patch" -> Array[Transform3D]
	var n := 0
	for _i in range(tries):
		if n >= cap:
			break
		var wx := ox + rng.randf() * span
		var wz := oz + rng.randf() * span
		if ring == 0 and Vector2(wx - _focus.x, wz - _focus.z).length() <= REAL_R:
			continue                        # the real trees own this ground
		var w := _plantable(wx, wz)
		if w <= 0.0 or rng.randf() > w:
			continue
		var sp := _species_for(wx, wz, rng)
		var sc := rng.randf_range(LOD_SCALE_MIN, LOD_SCALE_MAX)
		if rng.randf() < LOD_ELDER_CHANCE:
			sc *= LOD_ELDER_SCALE           ## the tree you notice, same as make()
		var t := Transform3D(Basis.IDENTITY, Vector3(wx, sample_height(wx, wz), wz))
		t.basis = t.basis.rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc))
		var px := clampi(int((wx - ox) / span * float(SUB_SPLIT)), 0, SUB_SPLIT - 1)
		var pz := clampi(int((wz - oz) / span * float(SUB_SPLIT)), 0, SUB_SPLIT - 1)
		var gk := "%s|%d" % [sp, pz * SUB_SPLIT + px]
		if not by_species.has(gk):
			by_species[gk] = ([] as Array[Transform3D])
		(by_species[gk] as Array).append(t)
		n += 1
	if n == 0:
		return

	for gk in by_species.keys():
		var parts: PackedStringArray = String(gk).split("|")
		_add_forest_multimesh(tile, parts[0], lod, by_species[gk], parts[1])


## How many distant trees are standing right now, and what they cost -- the
## numbers to look at when the framerate goes wrong.
func forest_stats() -> Dictionary:
	var trees := 0
	var tris := 0
	for d in [_near, _mid, _far]:
		for k in d.keys():
			for c in (d[k] as Node).get_children():
				var mmi := c as MultiMeshInstance3D
				if mmi == null or mmi.multimesh == null:
					continue
				if not String(mmi.name).begins_with("Forest_"):
					continue
				var cnt := mmi.multimesh.instance_count
				trees += cnt
				var m := mmi.multimesh.mesh as ArrayMesh
				if m != null:
					var t := 0
					for i in range(m.get_surface_count()):
						t += m.surface_get_arrays(i)[Mesh.ARRAY_VERTEX].size() / 3
					tris += cnt * t
	return {"trees": trees, "tris": tris, "real": real_tree_count(),
		"near_tiles": _near.size(), "mid_tiles": _mid.size(), "far_blocks": _far.size()}


func impostor_count() -> int:
	return int(forest_stats()["trees"])
