extends Node3D
class_name GrassSystem
## GRASS v2 — a real ground layer.
##
##   Architecture (unchanged, it was right): chunked MultiMesh instancing of
##   real low-poly GEOMETRY placed by sampling the voxel surface, faded out in
##   a ring so the world reads lush while the count stays honest.
##
##   What changed (v2):
##     • BLADES ARE CURVED. A blade is a tapered multi-segment strip that arcs
##       over under its own weight, not a flat isoceles triangle. It carries
##       ROUNDED NORMALS — the face normal is rotated outward at each edge, so
##       a flat strip lights like a cylinder. That one trick is most of the
##       difference between "grass" and "green confetti".
##     • ONE WIND. The hand-rolled sine is gone; the shader reads the same
##       global wind_dir / wind_strength / wind_time / player_push that the
##       leaves and bark read (Wind.gd), so the meadow and the canopy lean the
##       same way in the same gust. Weather drives it, so a storm flattens it.
##     • A GROUND LAYER, not just grass: clover, fern, wildflower, sedge and
##       moss, sited by moisture and lushness noise instead of sprinkled.
##     • SEASONS. Same four-stop hold-and-turn ramp as foliage.gdshader, so the
##       meadow browns off in autumn and takes snow in winter without a rebuild.
##     • SLOPE. Tufts tilt with the ground they grow out of instead of standing
##       dead vertical on a hillside.
##     • LOD. Three meshes per kind; each chunk swaps which one its MultiMesh
##       points at as you walk. Same instances, same transforms — one property
##       assignment. The near meadow is 35 triangles a tuft, the far one is 3.
##
## Chunks rebuild when digging (or a new mouth) changes the surface under
## them — same dirty-area pattern as the rock chunks.

const CHUNK_CELLS := 16          ## grass chunk = one rock chunk footprint (12.8 m)
const TUFTS_PER_CHUNK := 3400    ## placement attempts per chunk. History: 650 at
								 ## v2, ×2.6 at v2.1 ("much denser"), doubled again
								 ## at v2.2 for the SHORT grass specifically —
								 ## the tall-patch keep below halves twice to hold
								 ## the hiding grass at half its v2.1 density.
								 ## The LOD ladder is what makes this affordable:
								 ## the extra tufts are mostly 3-triangle far-field.
const FULL_COVER := true         ## v2.6: every dry cell is full meadow — no
								 ## treeline, sand, canopy, tideline or slope
								 ## thinning. Flip false for the graded world.
								 ## Snow, packed tracks and the road net still
								 ## refuse it; those are not a dry meadow.
const SNOW_LINE := 440.0         ## match terrain_psx.gdshader snow_line — Katahdin's
								 ## shoulders. Blades stop where the ground turns white.
const ROAD_W := 5.4              ## country-road kerb, m. City streets bring their
								 ## own width through pave(); this is the cart track.
const GPU_FESCUE := false        ## v3 would hand RED FESCUE outside the valley to a
								 ## particle process shader (scripts/GrassGPU.gd) — 66%
								 ## of the meadow off the CPU. OFF, and not because of
								 ## cost: measured live 2026-09-13, that file sets its
								 ## emitters up cleanly and DRAWS NOT ONE BLADE (see the
								 ## note at the top of it). Turning this on therefore
								 ## does not move the fescue, it DELETES it. The valley
								 ## is CPU-placed either way, because you can dig it.
const SHORT_KEEP := 0.94         ## short grass keeps nearly all of its draw

## Distance bands. LOD keeps the near meadow expensive and the far one nearly
## free, so the ring can be much wider than v1's 38 m without costing frames.
const LOD_HI := 9.0              ## curved 4-segment blades. 15 → 12 → 9 at v2.4.
								 ## The near ring IS the bill: its area goes as the
								 ## square of this, so 12→9 sheds 44% of the
								 ## expensive tufts without moving a visible edge —
								 ## at 9 m a 0.18 m fescue is already a few pixels.
const LOD_MID := 16.0            ## 2-segment blades (27→22→21, →16 at v2.4). The
								 ## mid ring loses 41% of its area with it.
## v2.5 — THE RING IS THE WHOLE COST NOW. Grass no longer lives in a 208 m
## valley you can seed once and forget: it streams across 78 km² of Maine, so
## the only thing that decides what grass costs is how far it draws. That is
## why draw distance is a SETTING (Esc → Draw Distance) rather than a constant,
## and why everything below is a FRACTION of it — move the one number and the
## whole ladder moves honestly, instead of four constants drifting apart.
##
## Area goes as the square: 60 → 90 m is 2.25× the tufts on screen. The
## defaults here are "Medium".
const CULL_END := 110.0          ## DEFAULT draw distance, m — horseback meadow
const DRAW_MIN := 30.0           ## Esc → Draw Distance: Low
const DRAW_MAX := 180.0          ## ...to Ultra. Past this the streamer thrashes.
const FADE_START_F := 0.58       ## blades start sinking + taking the ground's colour
const FADE_END_F := 0.78         ## by here they ARE the ground
## v3.1. The CPU chunks end at the draw ring and fade into it; the GPU horizon
## bands run hundreds of metres further and must NOT, or the world past 70 m
## goes back to being the bare ground this whole change exists to cover. So
## there are two fades in the one shared material and the blade picks which,
## off the flag the placer puts in COLOR.a (1.0 near, 0.5 horizon).
const FADE_FAR_START_F := 0.72   ## x GrassGPU.horizon_dist()
const FADE_FAR_END_F := 0.97
const DETAIL_CULL_F := 0.33      ## flowers/clover/moss are small — cull them early
const FADE_START := CULL_END * FADE_START_F
const FADE_END := CULL_END * FADE_END_F
const DETAIL_CULL := CULL_END * DETAIL_CULL_F

## One grass chunk in metres. The chunk grid is WORLD-space at v2.5 (it used to
## be indexed off CaveField cells, which only existed inside the valley), so a
## key is just floor(world / CHUNK_M) and there is no bound on it.
const CHUNK_M := float(CHUNK_CELLS) * CaveField.VOX

## --- streaming ---------------------------------------------------------------
## 7.2 × 10.8 km at 12.8 m is 474,000 chunks. You cannot seed that; you carry a
## ring of it with you. At 90 m that ring is ~190 chunks — about what the old
## fixed valley grid drew at 60 m, for a world 1,500× the area.
const STREAM_TICK := 0.30        ## seconds between re-evaluating the ring
const STREAM_BATCH := 8          ## chunks per worker batch (one batch in flight)
const STREAM_KEEP := 1.12        ## free a chunk once it is this far past the ring.
								 ## Hysteresis: a chunk on the boundary must not
								 ## be freed and rebuilt every time you step back
								 ## and forth across one metre. One chunk of slack
								 ## is enough — measured at 1.30 the resident set
								 ## was 224 chunks for a ring that wanted 178, and
								 ## a resident chunk still holds its instance
								 ## buffer even though nothing draws it.
const APPLY_PER_FRAME := 3       ## MultiMesh fills per frame — the main-thread half

## --- what actually pays for a 90 m ring --------------------------------------
## Measured the moment the ring went to 90 m: 180 chunks live, **429,116 tufts
## standing**, 7 fps. The old 60 m valley drew ~165k. Area squares, and the LOD
## ladder does not help here — it swaps a tuft's MESH, never whether it is drawn
## at all, so 417,000 far tufts were still 417,000 instances of vertex work.
##
## So past the fade line the meadow THINS. `MultiMesh.visible_instance_count`
## draws the first N instances and costs nothing to change — no rebuild, no
## reupload, one integer — and placement order inside a chunk is rng order, so
## taking the first third is a clean uniform thinning rather than a pattern.
##
## It starts exactly where the blades already begin sinking into the ground
## colour (FADE_START_F), so the density step lands underneath the fade that
## was going to hide it anyway. At 90 m that is 52 m out, and it takes the
## standing count from ~429k back to ~250k for fifty percent more reach.
const FAR_KEEP := 0.35           ## fraction of a faded chunk's tufts still drawn

const WITHER_R := 11.0           ## grass sickens this close to a cave mouth
const TALL_T := 0.34             ## tall-noise above this = a HIDING patch
const CUT_CELL := 0.6            ## resolution of the mown-grass record (m)
const LITTER_CAP := 1800         ## resting cut blades / fallen leaves held at once
const GUST_EVERY_MIN := 16.0     ## seconds between wind gusts through the litter
const GUST_EVERY_MAX := 38.0
const GUST_RANGE := 34.0         ## only lift leaves someone can see lift
const LOD_TICK := 0.22           ## seconds between LOD re-bands

## Every ground-cover kind. "std"/"tall"/"stub" keep their v1 names so saves,
## the mower and the stealth check all still mean the same thing.
##
## v2.3 — THE GRASS IS MAINE GRASS NOW (per Lemon: "a couple different Maine
## types, whatever's common"). Three real species join the layer:
##   std      = RED FESCUE. The fine, dense field grass — Maine's default
##              ground cover, and the baseline short kind here.
##   timothy  = TIMOTHY. THE Maine hayfield grass: a near-vertical stem with
##              the dense cylindrical seed-head spike on top — reads like a
##              slim cattail and identifies a field at fifty metres.
##   bluestem = LITTLE BLUESTEM. Native bunchgrass of dry, thin, sandy ground.
##              Upright and knee-high, blue-green in summer — and it CURES
##              COPPER-RED in autumn and stands all winter, which is the
##              single best colour event a Maine field has.
##   (tall = the generic hiding bunchgrass, sedge = the wet-ground grass —
##    both already read as bluejoint / sedge meadow and stay as they are.)
const KINDS: Array[String] = ["std", "tall", "stub", "clover", "fern", "flower", "sedge", "moss", "timothy", "bluestem"]
const DETAIL_KINDS := {"clover": true, "flower": true, "moss": true}

## Placement runs on the worker pool, and inside a worker thread the kinds are
## INTEGERS, never these strings.
##
## Why: _place_chunk is a group task, so eight threads run it at once. Using
## `KINDS[i]` as a Dictionary key in there has every thread hashing and
## refcounting the SAME shared String objects concurrently, and Godot's String
## refcount is not safe against that. It does not fail cleanly — it corrupts the
## keys (a lookup comes back as invalid unicode) and then double-frees. It also
## only shows up when the chunks take long enough to genuinely overlap, which a
## small test field never does. Names are attached on the main thread, in
## _apply_chunk, where there is exactly one of us.
const K_STD := 0
const K_TALL := 1
const K_STUB := 2
const K_CLOVER := 3
const K_FERN := 4
const K_FLOWER := 5
const K_SEDGE := 6
const K_MOSS := 7
const K_TIMOTHY := 8
const K_BLUESTEM := 9

## Material ids handed to the shader in UV2.x: 0 living foliage, 1 petal,
## 2 dried straw, 3 moss, 4 seed head (timothy's spike — straw-tan all year),
## 5 bluestem (its own season story: blue-green summer, copper autumn, and it
## STAYS copper through the winter). Everything else about a kind is geometry.
const MAT_LEAF := 0.0
const MAT_PETAL := 1.0
const MAT_DRY := 2.0
const MAT_MOSS := 3.0
const MAT_SEEDHEAD := 4.0
const MAT_BLUESTEM := 5.0

var field: CaveField
var base_seed := 0
var _mat: ShaderMaterial
var _mesh := {}                  ## kind -> [hi, mid, lo] ArrayMesh
var _cut_cells := {}             ## Vector2i cut-grid cell -> true (persists digs + shifts)
var _chunks := {}                ## Vector2i -> {kind: MultiMeshInstance3D}
var _chunk_lod := {}             ## Vector2i -> 0/1/2, so a re-band is one assignment
var _litter := {}                ## kind -> ring buffer of what CAME OFF the world
var _density := FastNoiseLite.new()
var _tall := FastNoiseLite.new() ## slow noise carves the tall meadows — the SAME
								 ## noise answers "am I hidden here?"
var _clump := FastNoiseLite.new()  ## 2 m scale: tufts grow in clumps, with dirt between
var _moist := FastNoiseLite.new()  ## wet ground -> sedge, moss, fern, deeper green
var _lush := FastNoiseLite.new()   ## rich vs thin ground -> height and colour
var _gust_t := 0.0               ## the leaf-litter gust clock (Tsushima drift)
var _gust_next := 22.0
var _lod_t := 0.0
var _weather: Node = null
var _ncx := 0                    ## CaveField chunk span — the VALLEY's footprint
var _ncz := 0                    ## only; the world grid beyond it is unbounded
var _bkeys: Array[Vector2i] = [] ## threaded build: the keys of the batch in flight
var _bresults := []

## --- v2.5: the streamed world -----------------------------------------------
var draw_dist := CULL_END        ## live draw distance, m (Esc → Draw Distance)
var detail_dist := DETAIL_CULL   ## flowers/clover/moss, scaled off draw_dist
var _ow: Overworld = null        ## the heightfield outside the valley; may be null
var _sea := -22.5                ## cached Overworld.sea_level
var _stream_t := 0.0
var _focus := Vector3.ZERO       ## the position the ring is centred on
var _queue: Array[Vector2i] = [] ## chunks wanted but not yet placed, nearest first
var _pending: Dictionary = {}    ## Vector2i -> true while queued or in flight
var _job_gid := -1               ## the WorkerThreadPool group task in flight, or -1
var _apply_q: Array = []         ## [key, placed] waiting for a main-thread fill

## --- v3: the GPU fescue field ------------------------------------------------
var _gpu: GrassGPU = null        ## null when GPU_FESCUE is off or there is no bake
## THE TOWNS. A city's ground is not a meadow: it is paved street, trodden
## yard and dirt market square, and only the CPU placer knows where those are
## (`_paved`, `_cut_cells`). So a staged city hands its rect over, the GPU
## field steps out of it exactly as it steps out of the valley, and the chunks
## inside place their own fescue again.
##
## Both of these are read from WORKER THREADS. They are only ever REPLACED
## wholesale on the main thread (never appended to in place) so a worker sees
## either the old table or the new one, never a half-built one.
var _towns: Array = []           ## Rect2, world XZ
var _paved: Dictionary = {}      ## chunk key -> Array of [ax, az, bx, bz, half_w]
var _gpu_on := false             ## read from WORKER THREADS in _place_chunk, so it
								 ## is a plain bool set once on the main thread and never
								 ## touched again — do not make this a property lookup
## GRASS PAINT (2026-09-14, scripts/GrassPaint.gd). WHERE the grass grows, as
## a map Lemon paints in god mode: 0 = the rule below decides, 1 = bare,
## 2..255 = grass at that density, whatever the rule says. Read per tuft from
## the worker threads (an Image that is only written in place); a stroke lands
## its chunks in `_regrow`, which the streamer re-places off-thread when its
## queue is empty, so a brushful of meadow never hitches the frame.
var _paint: GrassPaint = null
var _gp: Object = null           ## GroundPaint, duck-typed on worn_id_at. Worker threads
								 ## read it; the handle is set once on the main thread.
var _roads_bound := false        ## the RoadNet has been stamped into _paved
var _regrow: Dictionary = {}     ## chunk key -> true: standing, and the paint under it changed
var _empty: Dictionary = {}      ## chunk key -> true: placed and found NOTHING (sea, a bare
								 ## paint) — _restream stops asking until a regrow says otherwise


## --- GRASS LAB (F3) -----------------------------------------------------------
## Every number the look of the meadow hangs on, in ONE dictionary, so the F3
## lab (scripts/GrassLab.gd) can drag it around live and a chosen style can be
## SHIPPED as design/grass_style.json. Three groups by what a change costs:
##   shader    -> a uniform, instant
##   geometry  -> _build_meshes() + repoint every chunk's MultiMesh, ~ms
##   placement -> re-place the whole ring (reseed()), the expensive one
## The defaults ARE the v2.7 numbers, so a style with nothing in it is the game
## exactly as it was. Colours are "#rrggbb" strings (sRGB, like the shader's
## source_color defaults). The schema string is what the browser bench exports.
const STYLE_SCHEMA := "myrkfell.grass_style/1"
const STYLE_FILE := "res://design/grass_style.json"       ## the SHIPPED style
const STYLE_DIR := "res://design/grass_styles"           ## the presets
const STYLE_DEFAULTS := {
	## placement
	"density": 1.0,        ## x TUFTS_PER_CHUNK attempts (0..3)
	"tall_keep": 0.235,    ## the tall-patch keep roll
	"short_keep": 0.94,    ## SHORT_KEEP
	"clump_cut": -0.62,    ## clump-noise trough below which nothing grows
	"tall_shift": 0.0,     ## added to TALL_T: + = fewer hiding patches, - = more
	"size_var": 1.0,       ## spread of the per-tuft scale rolls (0 = all the same)
	"vigour": 1.0,         ## x the lush/moist height term
	"tint_dry": 0.55,      ## thin-ground burn strength
	"tint_moist": 0.45,    ## damp-ground depth strength
	"w_fescue": 1.0, "w_sedge": 1.0, "w_timothy": 1.0, "w_bluestem": 1.0,
	"w_flower": 1.0, "w_clover": 1.0, "w_fern": 1.0, "w_moss": 1.0,
	## geometry (the fescue tuft and the hiding grass)
	"height": 0.18, "width": 0.030, "blades": 4, "segs": 4, "lean": 0.35, "droop": 0.55,
	"spread": 1.0,         ## x the blades' root radius: 1 = a spike, 3 = a clump a hand wide
	"tall_height": 1.35, "tall_width": 0.068,
	## shader
	"col_spring": "#598730", "col_summer": "#406626", "col_autumn": "#877330", "col_winter": "#665c3d",
	"col_dry": "#8f7a40", "col_moss": "#305424", "col_snow": "#ccd6e6", "col_seedhead": "#b39966",
	"col_bluestem_summer": "#577557", "col_bluestem_cured": "#9e5433",
	"pixel_on": 1.0, "cells": 8.0, "side_cells": 3.0, "palette": 5.0, "jitter": 0.14,
	"hue_var": 0.12, "val_var": 0.38, "root_dark": 0.62, "tip_light": 0.40,
	"bands": 4.0, "backlight": 1.0, "normal_up": 0.48, "snow": 1.0, "posterize_gamma": 1.0,
}
const PLACEMENT_KEYS := ["density", "tall_keep", "short_keep", "clump_cut", "tall_shift", "size_var",
	"vigour", "tint_dry", "tint_moist", "w_fescue", "w_sedge", "w_timothy", "w_bluestem", "w_flower",
	"w_clover", "w_fern", "w_moss"]
const GEOMETRY_KEYS := ["height", "width", "blades", "segs", "lean", "droop", "spread", "tall_height", "tall_width"]
## shader key -> uniform name (a colour key lands as a Color)
const SHADER_UNIFORMS := {
	"col_spring": "col_spring", "col_summer": "col_summer", "col_autumn": "col_autumn",
	"col_winter": "col_winter", "col_dry": "col_dry", "col_moss": "col_moss", "col_snow": "col_snow",
	"col_seedhead": "col_seedhead", "col_bluestem_summer": "col_bluestem_summer",
	"col_bluestem_cured": "col_bluestem_cured",
	"pixel_on": "pixel_on", "cells": "pixel_cells", "side_cells": "pixel_side_cells",
	"palette": "palette_steps", "jitter": "cell_jitter", "hue_var": "hue_var", "val_var": "val_var",
	"root_dark": "root_dark", "tip_light": "tip_light", "bands": "light_bands", "backlight": "backlight",
	"normal_up": "normal_up", "snow": "snow_amount", "posterize_gamma": "posterize_gamma",
}
var style: Dictionary = STYLE_DEFAULTS.duplicate(true)
## The placer runs on WORKER THREADS and must not read a Dictionary the main
## thread is editing, so the placement knobs are mirrored into plain members
## by _sync_placement_style() -- written on the main thread only, before the
## reseed that makes them visible. Same rule as _gpu_on.
var _s_attempts := TUFTS_PER_CHUNK
var _s_tall_keep := 0.235
var _s_short_keep := SHORT_KEEP
var _s_clump_cut := -0.62
var _s_tall_shift := 0.0
var _s_size_var := 1.0
var _s_vigour := 1.0
var _s_tint_dry := 0.55
var _s_tint_moist := 0.45
var _s_w_fescue := 1.0
var _s_w_sedge := 1.0
var _s_w_timothy := 1.0
var _s_w_bluestem := 1.0
var _s_w_flower := 1.0
var _s_w_clover := 1.0
var _s_w_fern := 1.0
var _s_w_moss := 1.0


func apply_style(d: Dictionary, rebuild := true) -> Dictionary:
	## Merge `d` into the live style and do the CHEAPEST thing that makes it
	## visible. Unknown keys are ignored (a bench export carries wind and sun
	## knobs the game drives itself). Returns which groups changed.
	var changed := {"shader": false, "meshes": false, "placement": false}
	for k in d.keys():
		var key := String(k)
		if not STYLE_DEFAULTS.has(key):
			continue
		var v: Variant = d[k]
		var cur: Variant = style.get(key)
		if cur is String:
			v = String(v)
		elif v is bool:
			v = 1.0 if v else 0.0
		elif cur is int:
			v = int(v)
		else:
			v = float(v)
		if typeof(cur) == typeof(v) and cur == v:
			continue
		style[key] = v
		if GEOMETRY_KEYS.has(key):
			changed["meshes"] = true
		elif PLACEMENT_KEYS.has(key):
			changed["placement"] = true
		else:
			changed["shader"] = true
	_push_style_uniforms()
	_sync_placement_style()
	if rebuild and _mat != null:
		if bool(changed["meshes"]):
			rebuild_meshes()
		if bool(changed["placement"]):
			reseed()
	return changed


func _push_style_uniforms() -> void:
	if _mat == null:
		return
	for key: String in SHADER_UNIFORMS:
		var v: Variant = style[key]
		if v is String:
			_mat.set_shader_parameter(String(SHADER_UNIFORMS[key]), Color.html(String(v)))
		else:
			_mat.set_shader_parameter(String(SHADER_UNIFORMS[key]), float(v))


func _sync_placement_style() -> void:
	_s_attempts = int(clampf(float(style["density"]), 0.0, 3.0) * TUFTS_PER_CHUNK)
	_s_tall_keep = float(style["tall_keep"])
	_s_short_keep = float(style["short_keep"])
	_s_clump_cut = float(style["clump_cut"])
	_s_tall_shift = float(style["tall_shift"])
	_s_size_var = float(style["size_var"])
	_s_vigour = float(style["vigour"])
	_s_tint_dry = float(style["tint_dry"])
	_s_tint_moist = float(style["tint_moist"])
	_s_w_fescue = float(style["w_fescue"])
	_s_w_sedge = float(style["w_sedge"])
	_s_w_timothy = float(style["w_timothy"])
	_s_w_bluestem = float(style["w_bluestem"])
	_s_w_flower = float(style["w_flower"])
	_s_w_clover = float(style["w_clover"])
	_s_w_fern = float(style["w_fern"])
	_s_w_moss = float(style["w_moss"])


func rebuild_meshes() -> void:
	## New geometry, same instances: every chunk's MultiMesh is repointed at
	## the mesh its LOD band already names. No re-placement, no reupload.
	_build_meshes()
	for key: Vector2i in _chunks:
		var lod := int(_chunk_lod.get(key, 6))
		for kind: String in _chunks[key]:
			var mmi := _chunks[key][kind] as MultiMeshInstance3D
			if mmi.multimesh != null:
				mmi.multimesh.mesh = (_mesh[kind] as Array)[lod & 3]


func reseed() -> void:
	## Throw the whole ring away and place it again with the current knobs.
	## The expensive one (it is warm(), synchronous) -- the lab debounces it.
	if _job_gid >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_job_gid)
		_job_gid = -1
	_pending.clear()
	_queue.clear()
	_apply_q.clear()
	_bkeys.clear()
	_bresults.clear()
	for key: Vector2i in _chunks.keys():
		for kind: String in _chunks[key]:
			(_chunks[key][kind] as Node).queue_free()
	_chunks.clear()
	_chunk_lod.clear()
	if field != null:
		warm(_focus)


static func style_from_json(text: String) -> Dictionary:
	## A bench export ({schema, name, params}) or a bare dictionary of keys.
	var j := JSON.new()
	if j.parse(text) != OK or not (j.data is Dictionary):
		return {}   ## (JSON.new().parse, not parse_string: garbage must not push an engine error)
	var d := j.data as Dictionary
	if d.has("params") and d["params"] is Dictionary:
		return (d["params"] as Dictionary).duplicate()
	return d


static func load_style_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	return style_from_json(FileAccess.get_file_as_string(path))


func style_to_json(name_v: String, based_on := "") -> String:
	var out := {"schema": STYLE_SCHEMA, "name": name_v, "based_on": based_on,
		"exported": Time.get_datetime_string_from_system(), "params": style.duplicate(true)}
	return JSON.stringify(out, "\t")


func save_style_file(path: String, name_v: String, based_on := "") -> bool:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(style_to_json(name_v, based_on))
	f.close()
	return true


static func preset_files() -> Array:
	## [{name, path}] for every design/grass_styles/*.json, name-sorted.
	var out: Array = []
	if not DirAccess.dir_exists_absolute(STYLE_DIR):
		return out
	for fn in DirAccess.get_files_at(STYLE_DIR):
		var f := String(fn)
		if not f.ends_with(".json"):
			continue
		var path := STYLE_DIR + "/" + f
		var nm := f.get_basename()
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and (parsed as Dictionary).has("name"):
			nm = String((parsed as Dictionary)["name"])
		out.append({"name": nm, "path": path, "file": f.get_basename()})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["name"]) < String(b["name"]))
	return out


func _ready() -> void:
	add_to_group("grass_system")  ## the sword asks for cuts through here


func _exit_tree() -> void:
	## A placement batch still on the pool when this node goes reads `field`,
	## the noises and `_bkeys` off a freed object — a segfault on the way out
	## of the game. Wait for it; it is at most one batch.
	if _job_gid >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_job_gid)
		_job_gid = -1
	if _paint != null and _paint.changed.is_connected(regrow_rect):
		_paint.changed.disconnect(regrow_rect)


func setup(f: CaveField, seed_v: int) -> void:
	field = f
	base_seed = seed_v
	_density.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_density.frequency = 0.035
	_density.seed = seed_v * 7 + 3
	_tall.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_tall.frequency = 0.016
	_tall.seed = seed_v * 13 + 11
	## The near-scale one. Real grass grows in clumps with bare dirt showing
	## between them; an even sprinkle is the single most artificial thing a
	## grass system can do.
	_clump.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_clump.frequency = 0.42
	_clump.seed = seed_v * 17 + 5
	_moist.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_moist.frequency = 0.011
	_moist.seed = seed_v * 23 + 9
	_lush.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_lush.frequency = 0.045
	_lush.seed = seed_v * 31 + 19
	_build_material()
	## GRASS LAB (F3): the shipped style, if one was saved, is the game's look --
	## applied before the first mesh is built so it is not a dev-only overlay.
	var shipped := load_style_file(STYLE_FILE)
	if not shipped.is_empty():
		apply_style(shipped, false)
	else:
		_push_style_uniforms()
		_sync_placement_style()
	_build_meshes()
	_ncx = int(ceil(float(CaveField.CELLS_X) / CHUNK_CELLS))
	_ncz = int(ceil(float(CaveField.CELLS_Z) / CHUNK_CELLS))
	_ow = Overworld.inst
	if _ow != null:
		_sea = _ow.sea_level
		_gp = _ow.ground_paint
	if _gp == null and GroundPaint.inst != null:
		_gp = GroundPaint.inst
	if GrassPaint.inst != null:
		set_paint(GrassPaint.inst)
	## v3. The GPU field owns the fescue everywhere the baked heightfield is the
	## ground; this system keeps the valley (voxel, diggable) and the other eight
	## kinds. It has to exist BEFORE warm(), because _place_chunk asks it whether
	## to skip `std` and _tall_noise_at reads its baked tile.
	if GPU_FESCUE and _ow != null:
		var g := GrassGPU.new()
		g.name = "GrassGPU"
		add_child(g)
		## The rect the voxel field answers for — the same bounds _place_chunk's
		## `on_field` test uses, so the two grounds meet exactly at the rim and
		## neither leaves a bald metre for the other to have covered.
		var fmin := Vector2(field.origin.x + 2.0 * CaveField.VOX,
			field.origin.z + 2.0 * CaveField.VOX)
		var fmax := Vector2(field.origin.x + float(CaveField.SX - 3) * CaveField.VOX,
			field.origin.z + float(CaveField.SZ - 3) * CaveField.VOX)
		if g.setup(_mat, _mesh["std"] as Array, seed_v, fmin, fmax):
			_gpu = g
			_gpu_on = true
		else:
			g.queue_free()
	set_draw_distance(draw_dist)
	warm(Vector3.ZERO)
	print("GrassSystem: %s — %d chunks up around spawn, draw %.0f m"
		% ["streaming the whole map" if _ow != null else "valley only (no Overworld)",
			_chunks.size(), draw_dist])


## --------------------------------------------------------------- streaming ---
## v2.5. THERE IS NO "ALL THE CHUNKS" ANY MORE.
##
## Until now the meadow was 289 chunks over a 208 m valley, seeded once at boot
## and never touched again. The world is 7.2 × 10.8 km — 474,000 chunks. You do
## not seed that; you carry a ring of it with you, exactly as Overworld carries
## its ground tiles.
##
## What makes freeing a chunk safe is that placement is DETERMINISTIC in the
## world key (see _place_chunk's rng seed): walk away from a meadow, walk back,
## and the same tufts stand in the same spots — including the flat stubble
## wherever you mowed, because _cut_cells is a sparse world-space record that
## outlives the chunk that drew it.
##
## Two halves, both metered:
##   worker    _place_chunk over a batch of keys (pure reads, eight threads)
##   main      _apply_chunk fills the MultiMeshes — ~2 ms a chunk, so a whole
##             batch landing on one frame is a visible hitch. A few per frame.


func warm(at: Vector3) -> void:
	## Build the entire ring around `at` synchronously — boot and teleports call
	## this so there is grass before the frame is shown, the same contract
	## Overworld.warm() gives the ground under your feet.
	## Threaded, not a serial loop. At 90 m the ring is ~190 chunks and the
	## valley ones still walk voxel columns — placing them one at a time on the
	## main thread was a twenty-second boot. This is the old _reseed_all shape:
	## fan the whole ring across the pool, wait once, fill on the main thread.
	if _job_gid >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_job_gid)
		_job_gid = -1
		_pending.clear()
	_focus = at
	_restream()
	_apply_q.clear()
	if _queue.is_empty():
		_update_lod(at)
		return
	_bkeys.clear()
	for key: Vector2i in _queue:
		_bkeys.append(key)
	_queue.clear()
	_bresults.resize(_bkeys.size())
	var gid := WorkerThreadPool.add_group_task(_build_task, _bkeys.size(), -1, true, "Grass")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	for n in range(_bkeys.size()):
		if _bresults[n] is Dictionary:
			_apply_chunk(_bkeys[n], _bresults[n] as Dictionary)
	_bkeys.clear()
	_bresults.clear()
	_update_lod(at)


func set_draw_distance(m: float) -> void:
	## Esc → Draw Distance. One number moves the whole ladder: the cull ring,
	## the detail ring, and the shader's fade. The fade HAS to move with it —
	## left at 34→46 m against a 150 m ring, the far blades would pop in at
	## full colour instead of rising out of the ground.
	draw_dist = clampf(m, DRAW_MIN, DRAW_MAX)
	detail_dist = draw_dist * DETAIL_CULL_F
	if _gpu != null:
		_gpu.set_draw_distance(draw_dist)
	if _mat != null:
		_mat.set_shader_parameter("fade_start", draw_dist * FADE_START_F)
		_mat.set_shader_parameter("fade_end", draw_dist * FADE_END_F)
		var horizon := _gpu.horizon_dist() if _gpu != null else draw_dist
		_mat.set_shader_parameter("fade_start_far", horizon * FADE_FAR_START_F)
		_mat.set_shader_parameter("fade_end_far", horizon * FADE_FAR_END_F)
	for key: Vector2i in _chunks:
		for kind: String in _chunks[key]:
			(_chunks[key][kind] as MultiMeshInstance3D).visibility_range_end = \
				detail_dist if DETAIL_KINDS.has(kind) else draw_dist
	_restream()


func _chunk_dist(key: Vector2i) -> float:
	## Distance to the chunk's nearest EDGE, not its centre. A 12.8 m chunk you
	## are standing in the corner of is 0 m away, and banding it by its centre
	## would swap the ground under your feet to a coarser mesh.
	var c := _chunk_center(key)
	return maxf(Vector2(c.x - _focus.x, c.z - _focus.z).length() - CHUNK_M * 0.5, 0.0)


func _restream() -> void:
	## Rebuild the wanted set from scratch, nearest first, and free what fell
	## behind. Cheap enough to do on a tick: at 90 m that is a 19 × 19 scan.
	##
	## Freeing uses a slacker radius than wanting (STREAM_KEEP) so a chunk right
	## on the boundary does not get freed and rebuilt every time you step back
	## and forth across one metre.
	var r := int(ceil(draw_dist / CHUNK_M)) + 1
	var c0 := _chunk_key_at(_focus.x, _focus.z)
	var keep := draw_dist * STREAM_KEEP
	var want := {}
	_queue.clear()
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var key := Vector2i(c0.x + dx, c0.y + dz)
			if _chunk_dist(key) > draw_dist:
				continue
			want[key] = true
			## _pending is IN FLIGHT ONLY, never "queued": the queue is rebuilt
			## from scratch here, so a key you walked away from before it was
			## placed simply drops out, and walking back re-queues it.
			if not _chunks.has(key) and not _pending.has(key) and not _empty.has(key):
				_queue.append(key)
	_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chunk_dist(a) < _chunk_dist(b))
	for key: Vector2i in _chunks.keys():
		if want.has(key) or _chunk_dist(key) <= keep:
			continue
		for kind: String in _chunks[key]:
			(_chunks[key][kind] as Node).queue_free()
		_chunks.erase(key)
		_chunk_lod.erase(key)
	## The empty memo is only for the ring you are in; let the rest go so a
	## long walk along the coast does not grow it without bound.
	for key: Vector2i in _empty.keys():
		if _chunk_dist(key) > keep:
			_empty.erase(key)


func _stream_step() -> void:
	## One batch in flight at a time, POLLED rather than waited on:
	## wait_for_group_task_completion() blocks the main thread for the whole
	## batch, which is exactly the hitch this is here to avoid.
	if _job_gid >= 0:
		if not WorkerThreadPool.is_group_task_completed(_job_gid):
			return
		WorkerThreadPool.wait_for_group_task_completion(_job_gid)   ## returns at once
		_job_gid = -1
		for n in range(_bkeys.size()):
			if _bresults[n] is Dictionary:
				_apply_q.append([_bkeys[n], _bresults[n]])
			else:
				_pending.erase(_bkeys[n])
		_bkeys.clear()
		_bresults.clear()
		return
	if _queue.is_empty() and not _regrow.is_empty():
		## The brush's chunks: standing, but the paint under them changed. New
		## ground first (a bald patch you can walk into beats a stale one you
		## are looking at), then these, a batch at a time off-thread.
		for key: Vector2i in _regrow.keys():
			if _pending.has(key):
				continue      ## in flight, and it may have read the OLD paint:
							  ## stays marked, goes again once that batch lands
			if _chunk_dist(key) <= draw_dist:
				_queue.append(key)
			_regrow.erase(key)
			if _queue.size() >= STREAM_BATCH:
				break
	if _queue.is_empty():
		return
	_bkeys.clear()
	for _i in range(mini(STREAM_BATCH, _queue.size())):
		var key: Vector2i = _queue.pop_front()
		_bkeys.append(key)
		_pending[key] = true
	_bresults.resize(_bkeys.size())
	_job_gid = WorkerThreadPool.add_group_task(_build_task, _bkeys.size(), -1, true, "Grass")


func _drain_applies() -> void:
	var n := 0
	while not _apply_q.is_empty() and n < APPLY_PER_FRAME:
		var e: Array = _apply_q.pop_front()
		var key: Vector2i = e[0]
		_pending.erase(key)
		_apply_chunk(key, e[1] as Dictionary)
		n += 1


func _build_task(n: int) -> void:
	_bresults[n] = _place_chunk(_bkeys[n])


func _process(delta: float) -> void:
	## v1 pushed wind_t and player_pos into this shader by hand. Both are now
	## global shader parameters published once by Wind.gd for every foliage
	## shader in the game, so the meadow gusts with the canopy instead of
	## keeping its own private weather. Nothing to push per frame but the wet.
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p != null:
		## The stealth question, answered by the same noise that grew the
		## patches: standing in tall grass on the surface = concealed.
		##
		## v2.5: "on the surface" used to mean `y > -1.1`, which was true when
		## the only surface in the game was a valley floor at y = 0. Katahdin's
		## summit is at y 597 and the seabed at −27, so the test is now RELATIVE
		## to the ground you are actually standing on.
		p.set("grass_hidden", absf(p.global_position.y - _ground_y(p.global_position)) < 2.5
			and is_tall_at(p.global_position.x, p.global_position.z))

	## Rain darkens the meadow and makes it shine; the ground stays wet a while
	## after the rain stops, which is what Weather.wetness already tracks.
	if _weather == null or not is_instance_valid(_weather):
		var w := get_tree().get_first_node_in_group("world")
		if w != null and w.has_method("weather"):
			_weather = w.call("weather")
	if _weather != null and is_instance_valid(_weather):
		_mat.set_shader_parameter("wetness", float(_weather.get("wetness")))

	## LOD: which mesh each chunk's MultiMeshes point at. Cheap enough to do
	## on a tick rather than a frame — a chunk is 12.8 m and you can't cross a
	## band boundary in a fifth of a second.
	_lod_t += delta
	if _lod_t >= LOD_TICK:
		_lod_t = 0.0
		if p != null:
			_update_lod(p.global_position)
			## Fade the far blades into the ground THEY are standing on, not a
			## fixed dark green. Out in the world the terrain's own tint is
			## whatever the colour map says — sand at the shore, dark canopy
			## inland — and a ring of grass dissolving into the wrong colour is
			## exactly what makes a draw distance visible.
			if _ow != null:
				var gc := _ow.sample_color(p.global_position.x, p.global_position.z)
				_mat.set_shader_parameter("ground_tint",
					Color(gc.r * 0.62, gc.g * 0.62, gc.b * 0.62))

	## The ring follows you. _restream picks WHAT to build on a tick (a 19 × 19
	## scan is not free); _stream_step and _drain_applies run every frame because
	## they are already metered and stalling either one shows up as a bald patch
	## you can walk into.
	_stream_t += delta
	if _stream_t >= STREAM_TICK:
		_stream_t = 0.0
		if p != null:
			## On foot the ring sits on you. In the saddle it sits AHEAD, so a
			## gallop does not run onto a bald disc the streamer has not built.
			var next := p.global_position
			if p.get("mount") != null:
				var cam := get_viewport().get_camera_3d()
				if cam != null:
					var fwd := -cam.global_transform.basis.z
					fwd.y = 0.0
					if fwd.length_squared() > 0.0001:
						next += fwd.normalized() * 90.0
			if next.distance_to(_focus) > CHUNK_M * 0.5:
				_focus = next
				_restream()
	_bind_roads()
	_stream_step()
	_drain_applies()

	## Now and then the wind gets under the leaf fall and takes a FEW of them
	## somewhere else. The carpet stays; a handful of it moves.
	_gust_t += delta
	if _gust_t >= _gust_next:
		_gust_t = 0.0
		_gust_next = randf_range(GUST_EVERY_MIN, GUST_EVERY_MAX)
		_gust_leaves(p)


## ---------------------------------------------------------------- LOD ------


func _lod_for(d: float) -> int:
	if d < LOD_HI:
		return 0
	if d < LOD_MID:
		return 1
	return 2


func _chunk_center(key: Vector2i) -> Vector3:
	## WORLD-space at v2.5. The grid used to hang off field.origin and be
	## clamped to the CaveField's 17 × 17 chunks, because that was the only
	## ground there was. Now a key is just floor(world / 12.8) with no bound,
	## so the same maths addresses a chunk on Katahdin and one in the valley.
	return Vector3(float(key.x) * CHUNK_M + CHUNK_M * 0.5, 0.0,
		float(key.y) * CHUNK_M + CHUNK_M * 0.5)


func _ground_y(pos: Vector3) -> float:
	## The surface under a world position. Overworld.ground_y() already returns
	## 0.0 inside the spawn clearing (the CaveRegion's own grass top IS the
	## ground there) and 0.0 with no terrain loaded at all, so this is one
	## answer for both worlds and safe before the Overworld exists.
	return Overworld.ground_y(pos) if _ow != null else 0.0


func _update_lod(at: Vector3) -> void:
	## One property assignment per changed chunk. MultiMesh.mesh can be swapped
	## without touching the instance buffer, so a whole hillside changes detail
	## for the cost of a pointer — no rebuild, no reupload, no hitch.
	var half := CHUNK_CELLS * CaveField.VOX * 0.5
	for key: Vector2i in _chunks:
		var c := _chunk_center(key)
		var d := maxf(Vector2(c.x - at.x, c.z - at.z).length() - half, 0.0)
		var want := _lod_for(d)
		## Band 3: not a mesh, a COUNT. Past the fade line the chunk keeps its
		## LOD-2 mesh but draws only FAR_KEEP of its instances. Encoded into the
		## same cached band value so a re-band is still one comparison — 0/1/2
		## pick the mesh, +4 means "and thinned".
		if d >= draw_dist * FADE_START_F:
			want += 4
		if int(_chunk_lod.get(key, -1)) == want:
			continue
		_chunk_lod[key] = want
		var per_kind: Dictionary = _chunks[key]
		for kind: String in per_kind:
			var mmi := per_kind[kind] as MultiMeshInstance3D
			if mmi.multimesh != null:
				mmi.multimesh.mesh = (_mesh[kind] as Array)[want & 3]
				_band_count(mmi.multimesh, want >= 4)


func _band_count(mm: MultiMesh, thin: bool) -> void:
	## visible_instance_count draws the first N instances and leaves the buffer
	## alone — changing it is one integer, not a reupload. -1 means all of them.
	mm.visible_instance_count = maxi(int(float(mm.instance_count) * FAR_KEEP), 1) \
		if thin else -1


## ------------------------------------------------------- the stealth read ---


func is_tall_at(wx: float, wz: float) -> bool:
	## A patch only hides you while it's STANDING — mown stubble conceals no one.
	return _tall_noise_at(wx, wz) and not _cut_cells.has(_cut_cell(wx, wz))


func _tall_noise_at(wx: float, wz: float) -> bool:
	## v3: when the GPU field is up, BOTH sides read the SAME baked tile.
	## FastNoiseLite here and a hand-rolled simplex in GLSL would agree to about
	## three decimals and then disagree at the edge of every patch — and a
	## disagreement here is a BALD RING: no fescue, because the shader thinks the
	## patch is tall, and no bunchgrass, because this thinks it is not.
	if _gpu != null:
		return _gpu.tall_noise(wx, wz)
	return _tall.get_noise_2d(wx, wz) > TALL_T + _s_tall_shift   ## GRASS LAB (F3)


func _cut_cell(wx: float, wz: float) -> Vector2i:
	return Vector2i(int(floor(wx / CUT_CELL)), int(floor(wz / CUT_CELL)))


func _chunk_key_at(wx: float, wz: float) -> Vector2i:
	## floor(), not int() — int() truncates toward zero, so every chunk west or
	## north of the origin would land on its eastern/southern neighbour and the
	## mower would rebuild the wrong chunk for half the map.
	return Vector2i(int(floor(wx / CHUNK_M)), int(floor(wz / CHUNK_M)))


func _cover_at(gy: float, fw: float) -> float:
	## HOW MUCH GRASS THIS GROUND WANTS, 0 .. 1. Outside the valley the terrain
	## already carries the answer — the colour map's forest weight is the same
	## signal the tree scatter reads, so grass and woods agree about where the
	## meadow ends without a second painted mask.
	##
	## Measured off the live bake (5,400 samples across the map):
	##
	##   tideline / seabed     fw 0.00    pale (0.47, 0.53, 0.39)
	##   low coast             fw 0.14
	##   coastal plain / farm  fw 0.33    (0.37, 0.51, 0.23)
	##   inland forest         fw 0.62    (0.22, 0.37, 0.16)
	##   summits 300-600 m     fw 0.59    -- the map does NOT thin out up high
	##
	## That last row is the one worth knowing: the colour map has no rock or
	## alpine swatch, so Katahdin reads as forest to it.
	##
	## v2.6 (2026-09-03, Lemon: "make the entire land covered in short grass"):
	## EVERY DRY CELL IS FULL MEADOW. The old graded answer — a twentieth on
	## sand, ~45% under a closed canopy, 15% above the treeline, wrack at the
	## tideline — is kept below behind `FULL_COVER` so it can come back with one
	## flag flip. Water, snow, packed tracks and the road net still say no in
	## `_place_chunk`; the species MIX still reads `fw` (wood floors grow fern
	## and moss, fields grow clover and timothy), so the forest still changes
	## what grows, just not whether it grows.
	if FULL_COVER:
		return 1.0
	if fw < 0.06:
		return 0.05                                    ## sand, shingle, bare rock
	var c := 1.0 - smoothstep(0.35, 0.85, fw) * 0.55   ## a closed canopy shades its floor
	c *= 1.0 - smoothstep(320.0, 520.0, gy) * 0.85     ## the treeline
	c *= smoothstep(_sea + 0.5, _sea + 4.0, gy)        ## the tideline is wrack, not meadow
	return c


func cut_at(center: Vector3, radius: float) -> bool:
	## THE SWORD MOWS (Player._do_melee_hit): fell every standing TALL tuft
	## inside the swing circle. Short grass is spared, and because chunk seeds
	## are deterministic the felled tufts turn into flat dried STUBBLE in the
	## exact spots they stood — while the patch stops hiding anyone.
	## v2.5: this used to be `center.y < -1.6 or > 7.0`, which meant "near the
	## valley floor" back when the valley floor was the only surface. Measured
	## against the local ground it means the same thing everywhere on the map.
	if field == null or absf(center.y - _ground_y(center)) > 3.0:
		return false  ## no meadow down the throat or over the deeps
	var any_new := false
	var cut_count := 0
	var touched := {}
	var c := Vector2(center.x, center.z)
	var c0 := _cut_cell(center.x, center.z)
	var r_cells := int(ceil(radius / CUT_CELL)) + 1
	for dx in range(-r_cells, r_cells + 1):
		for dz in range(-r_cells, r_cells + 1):
			var cell := Vector2i(c0.x + dx, c0.y + dz)
			var cw := Vector2((float(cell.x) + 0.5) * CUT_CELL, (float(cell.y) + 0.5) * CUT_CELL)
			if cw.distance_to(c) > radius or _cut_cells.has(cell):
				continue
			if not _tall_noise_at(cw.x, cw.y):
				continue  ## only the hiding grass falls
			_cut_cells[cell] = true
			any_new = true
			cut_count += 1
			touched[_chunk_key_at(cw.x, cw.y)] = true
	if any_new:
		for k: Vector2i in touched:
			## Only chunks that are actually STANDING need re-placing. One that
			## has streamed out will read _cut_cells when it streams back and
			## grow its stubble then — that record outlives the chunk on purpose.
			if _chunks.has(k):
				_apply_chunk(k, _place_chunk(k))
		_burst_clippings(center, cut_count)
	return any_new


## A city has been staged (Cities.stage): nothing in this rect is meadow any
## more, the GPU hands it back to the chunks, and the chunks standing in it are
## re-placed so the change shows without walking away and back.
func set_towns(rects: Array) -> void:
	_towns = rects.duplicate()
	if _gpu != null:
		_gpu.set_town_rects(_towns)
	_replace_standing(func(key: Vector2i) -> bool: return _town_chunk(key))


## The streets of that city, as centre-line segments. A tuft inside one is not
## placed at all — the street boxes sit 0.02 m over the ground, so grass left
## under one grows straight through the cobbles.
##
## `segs` is an Array of {a: Vector2, b: Vector2, w: float}. Cumulative: a
## second city adds to the record rather than replacing it.
func pave(segs: Array) -> void:
	var next := _paved.duplicate(true)
	var touched := {}
	for sv in segs:
		var seg := sv as Dictionary
		var a := seg["a"] as Vector2
		var b := seg["b"] as Vector2
		var half := float(seg.get("w", 6.0)) * 0.5
		var row := [a.x, a.y, b.x, b.y, half]
		## Every chunk the segment's fattened box touches, so a tuft is only
		## ever tested against streets that could plausibly reach it.
		var lo := _chunk_key_at(minf(a.x, b.x) - half, minf(a.y, b.y) - half)
		var hi := _chunk_key_at(maxf(a.x, b.x) + half, maxf(a.y, b.y) + half)
		for cx in range(lo.x, hi.x + 1):
			for cz in range(lo.y, hi.y + 1):
				var key := Vector2i(cx, cz)
				if not next.has(key):
					next[key] = []
				(next[key] as Array).append(row)
				touched[key] = true
	_paved = next
	_replace_standing(func(key: Vector2i) -> bool: return touched.has(key))


## The country roads, as the RoadNet carved them. City streets already arrive
## through pave() from Cities; this is the 41 km of cart track BETWEEN the
## places, stamped the same way so a tuft never stands in the metalled line.
## Idempotent: the net is a pure function of the roster, so binding twice
## would double every segment in `_paved`.
func bind_roads(net: Object) -> void:
	if _roads_bound:
		return
	if net == null:
		return
	_roads_bound = true
	pave_roads(net)


func pave_roads(net: Object, width: float = ROAD_W) -> void:
	if net == null:
		return
	var eds: Variant = net.get("edges")
	if typeof(eds) != TYPE_ARRAY:
		return
	var segs: Array = []
	for e in eds:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var ed := e as Dictionary
		if not ed.has("poly"):
			continue
		var poly: PackedVector2Array = ed["poly"]
		for k in range(poly.size() - 1):
			segs.append({"a": poly[k], "b": poly[k + 1], "w": width})
	if not segs.is_empty():
		pave(segs)


func _bind_roads() -> void:
	if _roads_bound:
		return
	if RoadNet.inst == null or not is_instance_valid(RoadNet.inst):
		return
	if RoadNet.inst.has_method("ready") and not RoadNet.inst.ready():
		return
	bind_roads(RoadNet.inst)


## Snow, packed dirt and a wet track are not meadow. The snow line matches the
## terrain shader so Katahdin's white shoulders stay bare; dirt and mud are
## paint-only columns (a road you laid, a yard), and the bake's own snow class
## is column K. Water still has its own veto in `_place_chunk`.
func _surface_blocks_grass(wx: float, wz: float, gy: float) -> bool:
	if gy >= SNOW_LINE:
		return true
	if _gp == null or not _gp.has_method("worn_id_at"):
		return false
	return not GroundPaint.grass_on_tile(int(_gp.call("worn_id_at", wx, wz)))


## GRASS PAINT. Hand over the map (Overworld builds it after the terrain, so
## it usually arrives AFTER setup has warmed the ring) and re-place whatever
## is standing on painted ground. Every later stroke comes in through
## regrow_rect via the map's `changed` signal.
func set_paint(p: GrassPaint) -> void:
	if p == _paint:
		return
	if _paint != null and _paint.changed.is_connected(regrow_rect):
		_paint.changed.disconnect(regrow_rect)
	_paint = p
	if _paint == null:
		return
	if not _paint.changed.is_connected(regrow_rect):
		_paint.changed.connect(regrow_rect)
	if _paint.painted_cells > 0:
		regrow_rect(_paint.world_rect())


## The paint under this world XZ rect changed: every chunk it touches that is
## standing (or was found empty) goes back through the placer — off-thread,
## through the streamer, a batch a frame. Nothing is freed here, so the old
## meadow stays up until the new one lands.
func regrow_rect(r: Rect2) -> void:
	var lo := _chunk_key_at(r.position.x, r.position.y)
	var hi := _chunk_key_at(r.end.x, r.end.y)
	var span := (hi.x - lo.x + 1) * (hi.y - lo.y + 1)
	if span <= _chunks.size() + _empty.size() + 8:
		## A brush: walk the rect.
		for cx in range(lo.x, hi.x + 1):
			for cz in range(lo.y, hi.y + 1):
				var key := Vector2i(cx, cz)
				if _empty.has(key):
					_empty.erase(key)      ## _restream asks again next tick
				if _chunks.has(key) or _pending.has(key):
					_regrow[key] = true
		return
	## The whole map (fill / clear / a map handed over at boot): 474,000 keys
	## is not a rect to walk — ask the standing chunks instead.
	for key: Vector2i in _empty.keys():
		if key.x >= lo.x and key.x <= hi.x and key.y >= lo.y and key.y <= hi.y:
			_empty.erase(key)
	for key: Vector2i in _chunks.keys():
		if key.x >= lo.x and key.x <= hi.x and key.y >= lo.y and key.y <= hi.y:
			_regrow[key] = true
	for key: Vector2i in _pending.keys():
		if key.x >= lo.x and key.x <= hi.x and key.y >= lo.y and key.y <= hi.y:
			_regrow[key] = true


func regrow_pending() -> int:
	return _regrow.size()


func _replace_standing(want: Callable) -> void:
	for key: Vector2i in _chunks.keys():
		if want.call(key):
			_apply_chunk(key, _place_chunk(key))


func _town_chunk(key: Vector2i) -> bool:
	## Chunk-level, not tuft-level: a chunk is either a town's or the world's.
	## The rect is grown by a chunk so the boundary chunk belongs to the town
	## and the GPU's rect test (which IS per tuft) never lands inside a chunk
	## the CPU has already skipped fescue in.
	if _towns.is_empty():
		return false
	var c := _chunk_center(key)
	for t in _towns:
		if (t as Rect2).grow(CHUNK_M).has_point(Vector2(c.x, c.z)):
			return true
	return false


static func _on_segment(rows: Array, wx: float, wz: float) -> bool:
	for r in rows:
		var row := r as Array
		var ax := float(row[0])
		var az := float(row[1])
		var dx := float(row[2]) - ax
		var dz := float(row[3]) - az
		var L2 := dx * dx + dz * dz
		var t := 0.0 if L2 < 0.000001 else clampf(((wx - ax) * dx + (wz - az) * dz) / L2, 0.0, 1.0)
		var px := ax + dx * t - wx
		var pz := az + dz * t - wz
		if px * px + pz * pz <= float(row[4]) * float(row[4]):
			return true
	return false


func rebuild_area(lo: Vector3i, hi: Vector3i) -> void:
	## The ground changed (dig / new mouth) — reseed the grass chunks over it.
	if hi.y < CaveField.SY - 10:
		return
	## lo/hi arrive as VOXEL cell indices (CaveRegion speaks in cells). The
	## chunk grid is world-space now, so go through world metres rather than
	## dividing cell indices by CHUNK_CELLS — those two grids no longer line up.
	var k0 := _chunk_key_at(field.origin.x + float(lo.x) * CaveField.VOX,
		field.origin.z + float(lo.z) * CaveField.VOX)
	var k1 := _chunk_key_at(field.origin.x + float(hi.x) * CaveField.VOX,
		field.origin.z + float(hi.z) * CaveField.VOX)
	for cx in range(mini(k0.x, k1.x), maxi(k0.x, k1.x) + 1):
		for cz in range(mini(k0.y, k1.y), maxi(k0.y, k1.y) + 1):
			var key := Vector2i(cx, cz)
			if _chunks.has(key):
				_apply_chunk(key, _place_chunk(key))


## --------------------------------------------------------------- placing ---


func _ground_basis(p: Vector3, px: Vector3, pz: Vector3, yaw: float, lean: float) -> Basis:
	## Grass is gravitropic — it grows mostly UP even on a slope — but not
	## perfectly, and a meadow of dead-vertical tufts on a hillside is one of
	## the tells that reads as "instanced". Tilt part of the way to the ground
	## normal and leave the rest to gravity.
	var up := Vector3.UP
	if px != Vector3.INF and pz != Vector3.INF:
		var n := (pz - p).cross(px - p)
		if n.length_squared() > 0.000001:
			n = n.normalized()
			if n.y < 0.0:
				n = -n
			up = n.lerp(Vector3.UP, lean).normalized()
	var fwd := Vector3(cos(yaw), 0.0, sin(yaw))
	var right := fwd.cross(up)
	if right.length_squared() < 0.000001:
		right = Vector3.RIGHT
	right = right.normalized()
	return Basis(right, up, up.cross(right).normalized())


func _pick_kind(rng: RandomNumberGenerator, in_tall: bool, cut: bool,
		moist: float, lush: float) -> int:
	## Which ground cover grows on this square metre. Moisture and richness
	## decide, not a flat dice roll — so ferns come in drifts in the damp
	## hollows and the flowers come up where the ground is worth flowering on.
	## Returns an INDEX, not a name — see the note by K_STD.
	## GRASS LAB (F3): each gate's probability is scaled by that species'
	## weight, so every weight at 1.0 is this function exactly as it was, a
	## weight of 0 removes the species, and -1 means "nothing grows here".
	if in_tall:
		if cut:
			return K_STUB
		return K_SEDGE if moist > 0.30 and _s_w_sedge > 0.0 else K_TALL
	var r := rng.randf()
	if moist > 0.50 and r < 0.14 * _s_w_moss:
		return K_MOSS
	if moist > 0.32 and r < 0.30 * _s_w_fern:
		return K_FERN
	if lush > 0.22 and r < 0.24 * _s_w_clover:
		return K_CLOVER
	if lush > 0.06 and r < 0.055 * _s_w_flower:
		return K_FLOWER
	## Little bluestem owns the DRY, thin, sandy ground — where fescue thins
	## out, bluestem takes over in drifts, exactly as it does on a Maine
	## roadside bank. Timothy scatters through the open richer field the way
	## an old hayfield gone wild does: everywhere, but never wall-to-wall.
	if lush < -0.10 and moist < 0.25 and r < 0.55 * _s_w_bluestem:
		return K_BLUESTEM
	if lush > -0.05 and r < 0.085 * _s_w_timothy:
		return K_TIMOTHY
	if _s_w_fescue < 1.0 and rng.randf() >= _s_w_fescue:
		return -1
	return K_STD


func _place_chunk(key: Vector2i) -> Dictionary:
	## Sample the voxel surface for standable spots. Deterministic per chunk
	## (seeded rng) so rebuilds don't reshuffle the whole meadow.
	var rng := RandomNumberGenerator.new()
	rng.seed = base_seed + key.x * 73856093 + key.y * 19349663
	## Accumulate into plain Arrays, NOT PackedColorArrays. Godot's Packed*
	## types are VALUE types: `dict[k]["col"].append(c)` appends to a temporary
	## copy and throws it away, so every tuft would have come out colourless.
	## (Same trap the litter ring buffer already carries a warning about.)
	##
	## Indexed by kind INDEX, not name — this function runs on eight threads at
	## once and must not touch the shared KINDS strings. See K_STD.
	var n_kinds := KINDS.size()
	var xf_by: Array = []
	var col_by: Array = []
	for _k in range(n_kinds):
		xf_by.append([] as Array[Transform3D])
		col_by.append([] as Array[Color])
	## floor_point walks a voxel column top-down in interpreted GDScript, and
	## at v2.2 density each cell gets ~13 tuft attempts × 3 lookups (self + two
	## neighbours). Uncached, that walk was ~85% of the whole seed time
	## (measured: 10.3 s of a 12 s seed). The floor of a CELL never changes
	## within one placement pass, so memoise it per chunk — local Dictionary,
	## thread-safe because nothing shares it. Only the VALLEY pays this; the
	## heightfield outside is a bilinear read off a byte array and needs no memo.
	var floors := {}
	## Both looked up ONCE per chunk, not once per tuft: whether this chunk is
	## a town's (the GPU has stepped out of it, so we place fescue again) and
	## which street segments run through it.
	var in_town := _town_chunk(key)
	var paved: Array = _paved.get(key, [])
	var ox := float(key.x) * CHUNK_M
	var oz := float(key.y) * CHUNK_M
	var ylo := 1.0e20
	var yhi := -1.0e20
	for _i in range(_s_attempts):   ## GRASS LAB (F3): TUFTS_PER_CHUNK x style density
		var wx := ox + rng.randf() * CHUNK_M
		var wz := oz + rng.randf() * CHUNK_M
		if not paved.is_empty() and _on_segment(paved, wx, wz):
			continue      ## a street. Nothing grows through the cobbles.
		## GRASS PAINT. The map says bare, and that is the end of it; the map
		## says grass, and `painted` is how much of a meadow to grow here
		## instead of asking the world's rule below.
		var painted := -1.0
		if _paint != null:
			var pv := _paint.value_at(wx, wz)
			if pv == GrassPaint.BARE:
				continue
			if pv > GrassPaint.BARE:
				painted = GrassPaint.density_of(pv)
		## WHICH GROUND ANSWERS HERE. Inside the CaveField footprint it is the
		## voxel surface, so digging still uproots the grass over it; everywhere
		## else it is the baked heightfield. The two never overlap and the seam
		## is the field's own rim, which is inside the terrain's valley hole.
		var i := int((wx - field.origin.x) / CaveField.VOX)
		var k := int((wz - field.origin.z) / CaveField.VOX)
		var on_field := i >= 2 and k >= 2 and i <= CaveField.SX - 3 and k <= CaveField.SZ - 3
		var cover := 1.0
		var gc := Color(1.0, 1.0, 1.0)
		var fw := 0.0
		var gy := 0.0
		if not on_field:
			if _ow == null:
				continue      ## no heightfield loaded: the valley IS the world
			gy = _ow.sample_height(wx, wz)
			var wy := _ow.sample_water(wx, wz)
			if wy != Overworld.NO_WATER and wy > gy - 0.15:
				continue      ## nothing grows in the lake, the river or the sea
			if _surface_blocks_grass(wx, wz, gy):
				continue      ## snow, packed dirt, a wet track — not meadow
			gc = _ow.sample_color(wx, wz)
			fw = _ow._forest_weight(gc)
			cover = _cover_at(gy, fw) if painted < 0.0 else painted
			if cover <= 0.02:
				continue
		elif _surface_blocks_grass(wx, wz, 0.0):
			continue          ## a painted snowfield or track over the valley
		elif painted >= 0.0:
			cover = painted
			if cover <= 0.02:
				continue
		var in_tall := _tall_noise_at(wx, wz)
		## SHORT GRASS EVERYWHERE (the baseline is lush on purpose — the player
		## asked for no visible gaps); the noise only breathes variation into it.
		## `cover` is the world's veto on top: full in an open field, about half
		## under a closed canopy, a twentieth on sand, near nothing above the
		## treeline. Inside the valley it is 1.0 and this reads as it always did.
		if in_tall:
			if rng.randf() > _s_tall_keep * cover:   ## GRASS LAB (F3): 0.235 by default
				continue      ## HALF the v2.1 tall density (per Lemon), against
							  ## a doubled draw: 3400 × 0.235 ≈ 1700 × 0.47.
							  ## Chest-high blades overlap so much that half the
							  ## tufts still reads as full cover, and wading
							  ## through costs half the overdraw
		elif rng.randf() > (0.88 + _density.get_noise_2d(wx, wz) * 0.10) * _s_short_keep * cover:
			continue
		## ...but at the near scale it still CLUMPS — the gaps just tightened
		## from "bare patches" to "seams". A meadow with zero structure reads as
		## carpet, so the cutoff stays, moved out to reject only the deepest
		## troughs of the noise.
		if not in_tall and _clump.get_noise_2d(wx, wz) < _s_clump_cut:
			continue
		var p := Vector3.INF
		var px := Vector3.INF
		var pz := Vector3.INF
		if on_field:
			p = _floor_cached(floors, i, k)
			if p == Vector3.INF or p.y < -1.1 or p.y > 6.5:
				continue  ## no grass down the throat or floating over caves
			## Skip cliff faces: the neighbour column shouldn't drop far.
			px = _floor_cached(floors, mini(i + 1, CaveField.SX - 3), k)
			if px == Vector3.INF or absf(px.y - p.y) > 0.6:
				continue
			pz = _floor_cached(floors, i, mini(k + 1, CaveField.SZ - 3))
		else:
			p = Vector3(wx, gy, wz)
			px = Vector3(wx + CaveField.VOX, _ow.sample_height(wx + CaveField.VOX, wz), wz)
			pz = Vector3(wx, _ow.sample_height(wx, wz + CaveField.VOX), wz + CaveField.VOX)
			## SLOPE, and NOT the valley's rule. The voxel path rejects a
			## neighbour more than 0.6 m away over 0.8 m, which on a blocky
			## voxel surface means a genuine cliff FACE. On a smooth heightfield
			## the same number is 37° — an ordinary Maine hillside. Measured on
			## the deepwood slope at (1800, −2600): that rule threw away
			## **332 of 400 tufts** and left a whole wooded hill bald.
			##
			## So grade it properly. Grass holds until the soil does not: full
			## cover to 45°, thinning through the steeps, gone by 65° where
			## there is nothing but rock and scree to hold on to.
			##
			## The ceiling is 65° and not 58° because of what the map actually
			## is. Measured over 4,553 dry samples map-wide: 68.8% of the land
			## is under 20°, but **10.5% is steeper than 58°** — the bake's 4 m
			## heightfield plus PIN_PEAKS' crests and gullies make a lot of sharp
			## micro-relief. `Overworld._plantable()` has NO slope test at all,
			## so trees grow happily on those faces; cutting grass off at 58°
			## put whole wooded hillsides on bare dirt under standing timber.
			##
			## v2.6: with FULL_COVER the slope veto is off too — Lemon wants
			## every dry face green, cliffs included. The tuft's own tilt
			## (below) still lays it partway onto steep ground so a wall reads
			## as a mossy wall rather than a hedge of horizontal blades.
			if not FULL_COVER:
				var grade := Vector2(px.y - p.y, pz.y - p.y).length() / CaveField.VOX
				if grade > 2.145:                              ## tan 65°: rock and scree
					continue
				if grade > 1.0 and rng.randf() > (2.145 - grade) / 1.145:
					continue                                   ## tan 45°, faded out
		ylo = minf(ylo, p.y)
		yhi = maxf(yhi, p.y)

		var moist := _moist.get_noise_2d(wx, wz)
		var lush := _lush.get_noise_2d(wx, wz)
		## THE FOREST CHANGES THE MIX, not only the density. Under a closed
		## canopy the floor is shadier and damper, and _pick_kind already routes
		## damp-and-poor ground to moss, fern and sedge — so nudging the two
		## noises it reads is enough to make a wood floor grow like a wood floor
		## while the hayfield keeps its clover and timothy. No second system,
		## and the drifts still come from the noise rather than a dice roll.
		if not on_field:
			moist += fw * 0.22
			lush -= fw * 0.16
		var kind := _pick_kind(rng, in_tall, _cut_cells.has(_cut_cell(wx, wz)), moist, lush)
		if kind < 0:
			continue      ## GRASS LAB (F3): the fescue weight said no
		## v3. Off the voxel field, RED FESCUE belongs to the GPU — it is placed by
		## the particle shader from the same heightfield, the same noise tiles and
		## the same draw roll, so dropping it here removes the instances and not the
		## grass. Everything else on this square metre is still ours.
		if _gpu_on and not on_field and kind == K_STD and not in_town:
			continue

		## Rich ground grows taller. One noise doing two jobs keeps the height
		## variation and the colour variation agreeing with each other, which is
		## what makes a meadow read as ground rather than as scatter.
		var vigour := (1.0 + lush * 0.34 + moist * 0.12) * _s_vigour
		var sxz := 1.0 + (rng.randf_range(0.82, 1.28) - 1.0) * _s_size_var
		var sy := (1.0 + (rng.randf_range(0.72, 1.36) - 1.0) * _s_size_var) * vigour
		var lean := 0.55 if kind == K_MOSS else 0.42   ## moss hugs the slope
		var b := _ground_basis(p, px, pz, rng.randf() * TAU, lean)
		var t := Transform3D(Basis(b.x * sxz, b.y * sy, b.z * sxz), Vector3(wx, p.y - 0.02, wz))

		## The instance colour is now a TINT, not the albedo — the shader owns
		## the season. What the placer knows and the shader can't is local: how
		## rich this ground is, and how close it is to a mouth that is killing it.
		var tint := Color(1.0, 1.0, 1.0)
		var dry := clampf(-lush, 0.0, 1.0)
		tint = tint.lerp(Color(1.18, 1.06, 0.72), dry * _s_tint_dry)          ## thin ground burns off
		tint = tint.lerp(Color(0.82, 1.02, 0.80), clampf(moist, 0.0, 1.0) * _s_tint_moist)  ## damp ground is deeper
		var md := 999.0
		for m in field.mouths:
			md = minf(md, Vector2(wx - m.x, wz - m.z).length())
		tint = tint.lerp(Color(1.05, 0.86, 0.62), clampf(1.0 - md / WITHER_R, 0.0, 1.0) * 0.85)
		tint = tint * rng.randf_range(0.90, 1.10)
		if kind == K_TALL or kind == K_SEDGE:
			tint = tint * 0.88     ## the deep patches are shadier inside
		if not on_field:
			## GROW THE MEADOW OUT OF THE GROUND IT STANDS ON. Take the terrain
			## colour's HUE but not its value — divide out its own mean — so a
			## tuft on the shore goes warm and one under the canopy goes deep
			## green without the whole meadow getting darker with the map. A
			## grass ring that does not share the hue of the hillside beneath it
			## reads as a green disc laid on top, which is precisely what a draw
			## distance looks like when you can see it.
			var gm := maxf((gc.r + gc.g + gc.b) / 3.0, 0.05)
			tint = tint * Color(gc.r / gm, gc.g / gm, gc.b / gm).lerp(Color(1.0, 1.0, 1.0), 0.62)
		(xf_by[kind] as Array[Transform3D]).append(t)
		(col_by[kind] as Array[Color]).append(tint.srgb_to_linear())
	var cols: Array = []
	for k in range(n_kinds):
		var pc := PackedColorArray()
		for c: Color in col_by[k]:
			pc.append(c)
		cols.append(pc)
	## Parallel arrays indexed by kind. The main thread puts the names back on
	## in _apply_chunk.
	##
	## (Measured while chasing v2.2's seed time: the main-thread fill is only
	## ~0.3 s even at 614k instances — do NOT be tempted to pre-bake raw
	## MultiMesh buffers here. The actual cost was floor_point, cached below.)
	## The Y RANGE rides home with the placement so _apply_chunk can hand the
	## renderer an honest AABB. A fixed −3 .. +9 m box was fine when every chunk
	## sat on a flat valley floor; on a mountainside one chunk can span thirty
	## metres, and a box that lies about that culls the meadow out from under
	## you the moment you look down the slope.
	if ylo > yhi:
		ylo = 0.0
		yhi = 0.0
	return {"xf": xf_by, "col": cols, "y0": ylo, "y1": yhi}


func _floor_cached(floors: Dictionary, i: int, k: int) -> Vector3:
	var fk := i * 100000 + k
	var hit: Variant = floors.get(fk)
	if hit != null:
		return hit as Vector3
	var p := field.floor_point(Vector3i(i, CaveField.SY - 2, k))
	floors[fk] = p
	return p


func _apply_chunk(key: Vector2i, placed: Dictionary) -> void:
	## Main thread only. This is where the kind INDEXES the worker threads
	## produced get their names back (see K_STD).
	var xf_by: Array = placed["xf"]
	var col_by: Array = placed["col"]
	var any := false
	for ki in range(KINDS.size()):
		if not (xf_by[ki] as Array).is_empty():
			any = true
			break
	if not any:
		if _chunks.has(key):
			for kind: String in _chunks[key]:
				(_chunks[key][kind] as Node).queue_free()
			_chunks.erase(key)
			_chunk_lod.erase(key)
		_empty[key] = true
		return
	_empty.erase(key)
	if not _chunks.has(key):
		_chunks[key] = {}
	var per_kind: Dictionary = _chunks[key]
	## A chunk that has just streamed in arrived at the RING EDGE, so the honest
	## first guess is "far, and thinned" (2 | 4 — see _update_lod). The next LOD
	## tick corrects it either way; guessing near would flash a full-density
	## high-poly meadow on the horizon for a fifth of a second.
	var lod := int(_chunk_lod.get(key, 6))
	var ox := float(key.x) * CHUNK_M
	var oz := float(key.y) * CHUNK_M
	## The real span the placer measured, plus a metre and a half of headroom
	## for the tallest bunchgrass and half a metre of root below.
	var y0 := float(placed.get("y0", 0.0)) - 0.5
	var y1 := float(placed.get("y1", 0.0)) + 1.8
	var aabb := AABB(Vector3(ox, y0, oz), Vector3(CHUNK_M, maxf(y1 - y0, 1.0), CHUNK_M))
	for ki in range(KINDS.size()):
		var kind: String = KINDS[ki]
		var xfs: Array[Transform3D] = xf_by[ki]
		if xfs.is_empty():
			if per_kind.has(kind):
				(per_kind[kind] as Node).queue_free()
				per_kind.erase(kind)
			continue
		## An MMI is only born when its kind actually grows here. Creating all
		## eight in all 289 chunks would be 2,312 nodes for a world that mostly
		## wants three of them.
		if not per_kind.has(kind):
			var mmi := MultiMeshInstance3D.new()
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = detail_dist if DETAIL_KINDS.has(kind) else draw_dist
			mmi.material_override = _mat
			add_child(mmi)
			per_kind[kind] = mmi
		_fill_mm(per_kind[kind] as MultiMeshInstance3D, (_mesh[kind] as Array)[lod & 3],
			xfs, col_by[ki], aabb, lod >= 4)


func _fill_mm(mmi: MultiMeshInstance3D, mesh: ArrayMesh, transforms: Array[Transform3D],
		colors: PackedColorArray, aabb: AABB, thin := false) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for n in range(transforms.size()):
		mm.set_instance_transform(n, transforms[n])
		mm.set_instance_color(n, colors[n])
	## Instances live in world space around an identity node — hand the
	## renderer an honest AABB or distant chunks cull wrong.
	mm.custom_aabb = aabb
	_band_count(mm, thin)
	mmi.multimesh = mm


## --------------------------------------------------------------- geometry ---
## Everything below builds meshes ONCE at setup. Three LODs per kind; a chunk
## points its MultiMesh at whichever one matches its distance.


func _build_meshes() -> void:
	## segs, blades: the LOD ladder. A 4-segment blade genuinely arcs; a
	## 1-segment blade is v1's flat triangle, which is all a tuft 40 m away
	## has ever needed to be.
	## Field grass — RED FESCUE, and at v2.4 it is MOWN-SHORT: 0.44 → 0.18 m
	## standing, ~0.14 m across. Per Lemon: shorter short grass, and cheaper.
	##
	## Height is the fill-rate knob nothing else touches. Fescue is ~78% of
	## every tuft in the world, and a blade half as tall covers half as many
	## pixels; the near meadow was a wall of overlapping fragments and now it
	## is a floor. The blades narrow with it (0.050 → 0.030 half-width) — a
	## 0.10 m wide blade on a 0.18 m plant reads as a paddle, not grass.
	##
	## Blade count drops 5 → 4 at hi and mid as well. That is 28 triangles a
	## near tuft instead of 35, on the kind there are 477,000 of.
	## GRASS LAB (F3): the fescue reads its shape off `style`; the defaults
	## are the v2.7 numbers above, so an empty style is this exact ladder.
	var sh := float(style["height"])
	var sw := float(style["width"])
	var sb := maxi(1, int(style["blades"]))
	var ss := maxi(1, int(style["segs"]))
	var sl := float(style["lean"])
	var sd := float(style["droop"])
	var sp := float(style["spread"])
	_mesh["std"] = [
		_tuft(sh, sw, sb, ss, sl, sd, MAT_LEAF, sp),
		_tuft(sh, sw, sb, mini(ss, 2), sl, sd, MAT_LEAF, sp),
		_tuft(sh, sw * 1.2, maxi(1, mini(sb, 3)), 1, sl, sd, MAT_LEAF, sp),
	]
	## The hiding grass: a bunchgrass stand about 1.5 m standing and 1 m across,
	## straight for its bottom half and flopping over above that. This is the
	## one you wade through, so its silhouette has to read at a glance.
	var th := float(style["tall_height"])
	var tw := float(style["tall_width"])
	_mesh["tall"] = [
		_tuft(th, tw, 6, 4, 0.30, 0.80),
		_tuft(th, tw, 5, 2, 0.30, 0.80),
		_tuft(th, tw * 1.12, 3, 1, 0.30, 0.80),
	]
	## Sedge: wetland grass. Narrower blades that arc right over the top and
	## fall back toward the water — the giveaway silhouette at a pond edge.
	_mesh["sedge"] = [
		_tuft(1.15, 0.034, 7, 4, 0.45, 2.10),
		_tuft(1.15, 0.034, 5, 2, 0.45, 2.10),
		_tuft(1.15, 0.042, 3, 1, 0.45, 2.10),
	]
	## Mown stubble comes down with the fescue. At v2.3 it was 0.17 m against
	## 0.44 m of standing grass — an obvious shear line. Against 0.18 m of
	## standing grass 0.17 m is invisible, and "I cut this" stops reading at
	## all. The stumps drop to 0.07 m, which holds the SAME 39% of standing
	## height the shear line has always had — the contrast is what reads, not
	## the number.
	var stub_hi := _stub(0.07, 0.032, 5)
	_mesh["stub"] = [stub_hi, stub_hi, _stub(0.07, 0.037, 3)]
	_mesh["clover"] = [_clover(3, 4), _clover(2, 3), _clover(1, 3)]
	_mesh["fern"] = [_fern(3, 5), _fern(3, 0), _fern(2, 0)]
	_mesh["flower"] = [_flower(5), _flower(4), _flower(0)]
	var moss_hi := _moss(6)
	_mesh["moss"] = [moss_hi, _moss(4), _moss(3)]
	## Timothy: the seed head IS the identity, so every LOD keeps it — the far
	## mesh is one stem and one spike, which is exactly what timothy looks like
	## at range anyway.
	_mesh["timothy"] = [_timothy(3, 4, 3), _timothy(2, 2, 2), _timothy(1, 2, 0)]
	## Little bluestem: an upright, narrow, knee-high bunch — stiffer than
	## fescue (bunchgrass barely nods), tagged MAT_BLUESTEM for its own
	## season colours.
	_mesh["bluestem"] = [
		_tuft(0.62, 0.038, 6, 4, 0.18, 0.30, MAT_BLUESTEM),
		_tuft(0.62, 0.038, 5, 2, 0.18, 0.30, MAT_BLUESTEM),
		_tuft(0.62, 0.046, 3, 1, 0.18, 0.30, MAT_BLUESTEM),
	]


func _strip(st: SurfaceTool, base: Vector3, out_dir: Vector3, height: float,
		width: float, lean: float, droop: float, segs: int, round_amt: float,
		matid: float, twist := 0.0) -> void:
	## ONE BLADE. The whole realism argument lives in this function.
	##
	## The centre-line is integrated, not lerped: at each step the blade's
	## direction is tilted `(lean + droop*u) * u²` radians off vertical and we
	## walk that way, so the thing genuinely arcs and a long enough blade tips
	## past horizontal and points back at the ground. A straight triangle
	## cannot do that at any vertex count.
	##
	## The u² is not a fudge — a uniformly loaded cantilever deflects as the
	## square of its length, and a blade of grass is exactly that. It puts the
	## bend where a real blade puts it: the bottom half stands up straight and
	## the top third flops. A linear profile splays the whole clump outward
	## instead, and a metre-tall tuft ends up two metres wide.
	##
	## The width tapers as pow(1-u, 0.55) — a spear, not a rectangle.
	##
	## And the normals: the face normal is rotated OUTWARD about the blade's
	## own tangent, by +round_amt on one edge and -round_amt on the other. The
	## rasteriser interpolates between them, so a flat two-triangle strip
	## shades exactly like a curved one. This costs nothing and it is the
	## single biggest difference between grass and green paper.
	var seg_len := height / float(segs)
	var pts: Array[Vector3] = [base]
	var tans: Array[Vector3] = []
	var p := base
	for s in range(segs):
		var u := (float(s) + 0.5) / float(segs)
		var a := (lean + droop * u) * u * u
		var d := (Vector3.UP * cos(a) + out_dir * sin(a)).normalized()
		tans.append(d)
		p += d * seg_len
		pts.append(p)
	for s in range(segs):
		var u0 := float(s) / float(segs)
		var u1 := float(s + 1) / float(segs)
		var w0 := width * pow(maxf(1.0 - u0, 0.0), 0.55)
		var w1 := width * pow(maxf(1.0 - u1, 0.0), 0.55)
		var t0 := tans[s]
		var t1 := tans[mini(s + 1, segs - 1)]
		var side0 := out_dir.cross(t0).normalized().rotated(t0, twist * u0)
		var side1 := out_dir.cross(t1).normalized().rotated(t1, twist * u1)
		var n0 := side0.cross(t0).normalized()
		var n1 := side1.cross(t1).normalized()
		var a0 := pts[s] - side0 * w0
		var b0 := pts[s] + side0 * w0
		var a1 := pts[s + 1] - side1 * w1
		var b1 := pts[s + 1] + side1 * w1
		## rounded normals: lean each edge's normal away from the centre
		var na0 := n0.rotated(t0, -round_amt)
		var nb0 := n0.rotated(t0, round_amt)
		var na1 := n1.rotated(t1, -round_amt)
		var nb1 := n1.rotated(t1, round_amt)
		if s == segs - 1:
			## the last ring collapses to a point — a blade ends in a tip
			var tip := pts[segs]
			_v(st, a0, na0, 0.0, u0, matid)
			_v(st, tip, n1, 0.5, 1.0, matid)
			_v(st, b0, nb0, 1.0, u0, matid)
		else:
			_v(st, a0, na0, 0.0, u0, matid)
			_v(st, a1, na1, 0.0, u1, matid)
			_v(st, b0, nb0, 1.0, u0, matid)
			_v(st, b0, nb0, 1.0, u0, matid)
			_v(st, a1, na1, 0.0, u1, matid)
			_v(st, b1, nb1, 1.0, u1, matid)


func _v(st: SurfaceTool, pos: Vector3, n: Vector3, side: float, u: float, matid: float) -> void:
	## UV carries the blade's own coordinates — side across, height along — so
	## the shader can bend, shade and tint by position along the blade without
	## a texture. UV2.x is which MATERIAL this vertex is (leaf / petal / dry /
	## moss), which is how one shader covers eight kinds of ground cover.
	st.set_normal(n)
	st.set_uv(Vector2(side, u))
	st.set_uv2(Vector2(matid, 0.0))
	st.add_vertex(pos)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3,
		ua: float, ub: float, uc: float, matid: float) -> void:
	_v(st, a, n, 0.0, ua, matid)
	_v(st, b, n, 0.5, ub, matid)
	_v(st, c, n, 1.0, uc, matid)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		n: Vector3, u0: float, u1: float, matid: float) -> void:
	_v(st, a, n, 0.0, u0, matid)
	_v(st, d, n, 0.0, u1, matid)
	_v(st, b, n, 1.0, u0, matid)
	_v(st, b, n, 1.0, u0, matid)
	_v(st, d, n, 0.0, u1, matid)
	_v(st, c, n, 1.0, u1, matid)


func _tuft(height: float, width: float, blades: int, segs: int,
		lean: float, droop: float, matid := MAT_LEAF, spread := 1.0) -> ArrayMesh:
	## A tuft is a fan of blades around one root, each with its own height,
	## its own lean and its own twist. Identical blades read as a fan; varied
	## ones read as a plant.
	## `spread` (GRASS LAB, v2.8) scales the root radius: at 1 the blades rise
	## from within 4 cm of one point and the tuft is a spike; at 3 they come
	## up across a hand's width and the tuft is a CLUMP whose blades cross its
	## neighbours' -- the difference between scattered spikes and turf, at the
	## same instance count.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in range(blades):
		var ang := TAU * float(b) / float(blades) + 0.35 + float(b % 3) * 0.21
		var out := Vector3(cos(ang), 0.0, sin(ang))
		var vary := 0.78 + 0.44 * float((b * 7) % 5) / 4.0
		_strip(st, out * (0.018 + 0.020 * float(b % 2)) * spread, out,
			height * vary, width * (0.85 + 0.3 * float(b % 2)),
			lean * (0.72 + 0.5 * float((b * 3) % 4) / 3.0), droop * vary,
			segs, 0.58, matid, 0.5 - float(b % 2))
	return st.commit()


func _timothy(stems: int, segs: int, basal: int) -> ArrayMesh:
	## TIMOTHY. A hayfield in one silhouette: a thin, nearly straight stem
	## (lean 0.10, droop 0.14 — hay stands, it does not flop) carrying the
	## dense cylindrical seed-head spike, plus a few ordinary blades at the
	## boot. The spike is a 4-sided prism tagged MAT_SEEDHEAD so the shader
	## keeps it straw-tan whatever the season is doing to the leaves.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in range(stems):
		var ang := TAU * float(s) / float(maxi(stems, 1)) + 0.8
		var out := Vector3(cos(ang), 0.0, sin(ang))
		var h := 0.82 * (0.88 + 0.24 * float(s % 2))
		var lean := 0.10 * (0.7 + 0.6 * float((s * 3) % 3) / 2.0)
		var droop := 0.14
		var base := out * 0.014
		_strip(st, base, out, h, 0.013, lean, droop, segs, 0.5, MAT_LEAF)
		## Walk the same arc _strip walks to find the true stem tip, then set
		## the spike on it, aligned with the stem's final direction.
		var seg_len := h / float(segs)
		var p := base
		var d := Vector3.UP
		for q in range(segs):
			var u := (float(q) + 0.5) / float(segs)
			var a := (lean + droop * u) * u * u
			d = (Vector3.UP * cos(a) + out * sin(a)).normalized()
			p += d * seg_len
		var head_h := 0.085 * (0.9 + 0.3 * float(s % 2))
		var r := 0.016
		var side_a := out.cross(d).normalized()
		var side_b := d.cross(side_a).normalized()
		## four quads around the spike, normals facing out — a tiny prism
		for f in range(4):
			var n0 := (side_a if f % 2 == 0 else side_b) * (1.0 if f < 2 else -1.0)
			var t0 := (side_b if f % 2 == 0 else side_a) * (1.0 if f < 2 else -1.0)
			var c0 := p + n0 * r
			_quad(st, c0 - t0 * r, c0 + t0 * r,
				c0 + t0 * r * 0.7 + d * head_h, c0 - t0 * r * 0.7 + d * head_h,
				n0, 0.9, 1.0, MAT_SEEDHEAD)
	for b in range(basal):
		var ang2 := TAU * float(b) / float(maxi(basal, 1)) + 0.25
		var out2 := Vector3(cos(ang2), 0.0, sin(ang2))
		_strip(st, out2 * 0.02, out2, 0.30, 0.030, 0.45, 0.6, 2, 0.58, MAT_LEAF)
	return st.commit()


func _stub(height: float, width: float, blades: int) -> ArrayMesh:
	## CUT grass. The same fan, TRUNCATED — flat-topped little stumps, sheared
	## where the sword went through. The flat cut is what reads "mown", so this
	## one stays square-ended on purpose while everything else got a tip.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in range(blades):
		var ang := TAU * float(b) / float(blades) + 0.35
		var out := Vector3(cos(ang), 0.0, sin(ang))
		var side := Vector3(-sin(ang), 0.0, cos(ang))
		var base := out * 0.08
		var h := height * (0.8 + 0.4 * float(b % 2))
		var top := base + out * 0.05 + Vector3.UP * h
		var n := side.cross(Vector3.UP).normalized()
		_quad(st, base - side * width, base + side * width,
			top + side * width * 0.7, top - side * width * 0.7, n, 0.0, 1.0, MAT_DRY)
	return st.commit()


func _clover(segs: int, leaflets: int) -> ArrayMesh:
	## Broadleaf ground cover — the low round leaves that carpet good soil
	## between the grass. Nearly horizontal, normals nearly up, so a patch of
	## it reads as a soft green FLOOR that the blades come up through.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in range(leaflets):
		var ang := TAU * float(b) / float(leaflets) + 0.6
		var out := Vector3(cos(ang), 0.0, sin(ang))
		var side := Vector3(-sin(ang), 0.0, cos(ang))
		var lift := 0.055 + 0.03 * float(b % 2)
		var stem := out * 0.03 + Vector3.UP * lift
		var reach := 0.085 + 0.03 * float(b % 3)
		var tipv := stem + out * reach + Vector3.UP * 0.012
		var w := 0.052
		var n := (Vector3.UP * 3.0 + out).normalized()
		if segs <= 1:
			_tri(st, stem - side * w * 0.5, tipv, stem + side * w * 0.5, n, 0.0, 1.0, 0.0, MAT_LEAF)
			continue
		var mid := stem.lerp(tipv, 0.55) + Vector3.UP * 0.008
		_quad(st, stem - side * w * 0.45, stem + side * w * 0.45,
			mid + side * w, mid - side * w, n, 0.0, 0.55, MAT_LEAF)
		_tri(st, mid - side * w, tipv, mid + side * w, n, 0.55, 1.0, 0.55, MAT_LEAF)
	return st.commit()


func _fern(fronds: int, pinnae: int) -> ArrayMesh:
	## The shade plant. A frond is one hard-arcing rachis with leaflets down
	## both sides — at range the leaflets are invisible, which is exactly why
	## the far LOD drops them and keeps the arc.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in range(fronds):
		var ang := TAU * float(f) / float(fronds) + 0.9
		var out := Vector3(cos(ang), 0.0, sin(ang))
		var side := Vector3(-sin(ang), 0.0, cos(ang))
		var h := 0.42 + 0.10 * float(f % 2)
		_strip(st, out * 0.02, out, h, 0.030, 0.62, 1.05, 3, 0.42, MAT_LEAF)
		for s in range(pinnae):
			## leaflets ride the arc, shrinking toward the tip
			var u := 0.30 + 0.62 * float(s) / float(maxi(pinnae - 1, 1))
			var a := (0.62 + 1.05 * u) * u * u   ## same arc the rachis walks
			var alongd := (Vector3.UP * cos(a) + out * sin(a)).normalized()
			var at := out * 0.02 + alongd * (h * u)
			var lw := 0.062 * (1.0 - u * 0.7)
			var sgn := 1.0 if s % 2 == 0 else -1.0
			var tipv := at + side * sgn * lw * 2.1 + alongd * lw * 0.7
			var n := (side * sgn * 0.35 + Vector3.UP).normalized()
			_tri(st, at - alongd * lw * 0.5, tipv, at + alongd * lw * 0.5,
				n, 0.4, 0.9, 0.4, MAT_LEAF)
	return st.commit()


func _flower(petals: int) -> ArrayMesh:
	## A stem and a head. The head's vertices are tagged MAT_PETAL, so the
	## shader colours them off the per-tuft hash instead of off the season
	## ramp — which is how one instanced mesh becomes daisies, buttercups,
	## asters and paintbrush in the same meadow.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 0.30
	for b in range(2):
		var ang := 1.1 + PI * float(b)
		var out := Vector3(cos(ang), 0.0, sin(ang))
		_strip(st, out * 0.012, out, h * (0.86 + 0.2 * float(b)), 0.016,
			0.20, 0.28, 2, 0.5, MAT_LEAF)
	if petals <= 0:
		return st.commit()
	var head := Vector3(cos(1.1), 0.0, sin(1.1)) * 0.045 + Vector3.UP * h * 0.97
	for pt in range(petals):
		var a := TAU * float(pt) / float(petals)
		var out2 := Vector3(cos(a), 0.22, sin(a)).normalized()
		var side2 := Vector3(-sin(a), 0.0, cos(a))
		var tipv := head + out2 * 0.042
		var n := (Vector3.UP * 2.2 + out2).normalized()
		_tri(st, head - side2 * 0.014, tipv, head + side2 * 0.014, n, 0.3, 1.0, 0.3, MAT_PETAL)
	return st.commit()


func _moss(facets: int) -> ArrayMesh:
	## A cushion, not a plant. Overlapping near-flat facets domed slightly up,
	## so a damp hollow gets a soft dark-green skin the blades stand out of.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := 0.13
	for f in range(facets):
		var a0 := TAU * float(f) / float(facets)
		var a1 := TAU * float(f + 1) / float(facets)
		var lift := 0.022 + 0.010 * float(f % 3)
		var v0 := Vector3(cos(a0) * r, 0.004, sin(a0) * r)
		var v1 := Vector3(cos(a1) * r, 0.004, sin(a1) * r)
		var c := Vector3(0.0, lift, 0.0)
		var n := ((v0 - c).cross(v1 - c)).normalized()
		if n.y < 0.0:
			n = -n
		_tri(st, v0, c, v1, n, 0.0, 1.0, 0.0, MAT_MOSS)
	return st.commit()


## ------------------------------------------------------------- clippings ---


func _gust_leaves(p: Node3D) -> void:
	if p == null or not _litter.has("leaf"):
		return
	var pool: Dictionary = _litter["leaf"]
	if int(pool["count"]) <= 0:
		return
	var on: Array = pool["on"]
	var xf: Array = pool["xf"]
	var cols: Array = pool["col"]
	var ga := randf() * TAU
	var gust := Vector3(cos(ga), 0.0, sin(ga))   ## one bearing — one gust
	var want := randi_range(2, 6)
	var taken := 0
	var start := randi() % LITTER_CAP
	for s in range(LITTER_CAP):
		if taken >= want:
			break
		var i: int = (start + s) % LITTER_CAP
		if not on[i]:
			continue
		var t: Transform3D = xf[i]
		if p.global_position.distance_to(t.origin) > GUST_RANGE:
			continue  ## only lift what someone is there to see lift
		var fl := FallingLitter.make("leaf", t.origin + Vector3.UP * 0.06,
			Vector3(randf_range(-0.3, 0.3), randf_range(0.5, 1.5), randf_range(-0.3, 0.3)),
			cols[i] as Color, t.basis.get_scale().x)
		add_child(fl)
		fl.carry(gust + Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3)),
			randf_range(2.0, 12.0), randf_range(0.8, 2.2))
		remove_litter("leaf", i)
		taken += 1


func _burst_clippings(center: Vector3, cells: int) -> void:
	## THE CUT BLADES THEMSELVES. A severed blade PLANES down like a leaf and
	## comes to rest on the dirt — where it STAYS. Mowing leaves a floor of
	## cuttings behind you, not a puff of particles.
	var n := clampi(cells, 6, 18)
	for _i in range(n):
		var a := randf() * TAU
		var rr := sqrt(randf()) * 0.75
		var at := center + Vector3(cos(a) * rr, randf_range(-0.15, 0.45), sin(a) * rr)
		var v := Vector3(cos(a), 0.0, sin(a)) * randf_range(0.5, 1.7) \
			+ Vector3.UP * randf_range(0.5, 1.9)
		var col := Color(0.24, 0.36, 0.15).lerp(Color(0.45, 0.44, 0.21), randf())
		add_child(FallingLitter.make("blade", at, v, col, randf_range(0.85, 1.4)))


## ------------------------- Litter: what lies there ------------------------
## Everything that has come OFF the world and settled — mown blades, leaves
## shaken out of a falling canopy. One MultiMesh per kind, written as a ring
## buffer: the oldest blade quietly gives up its slot when the meadow has been
## worked hard enough, so this never becomes a budget you have to think about.


func _litter_pool(kind: String) -> Dictionary:
	if _litter.has(kind):
		return _litter[kind]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = FallingLitter.mesh_for(kind)
	mm.instance_count = LITTER_CAP
	var gone := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for i in range(LITTER_CAP):
		mm.set_instance_transform(i, gone)
		mm.set_instance_color(i, Color.WHITE)
	## Instances live in world space around an identity node — a world-sized
	## AABB keeps distant litter from culling out from under itself.
	mm.custom_aabb = AABB(Vector3(-130, -50, -130), Vector3(260, 80, 260))
	var mmi := MultiMeshInstance3D.new()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mmi.material_override = mat
	mmi.multimesh = mm
	add_child(mmi)
	## A CPU-side mirror of the buffer: the save reads from THIS, never back
	## out of the renderer. Plain Arrays on purpose — Godot's Packed*Arrays are
	## value types, so `dict["col"][i] = c` would quietly write to a copy.
	var xf: Array = []
	xf.resize(LITTER_CAP)
	var cs: Array = []
	cs.resize(LITTER_CAP)
	var on: Array = []
	on.resize(LITTER_CAP)
	var pool := {"mmi": mmi, "mm": mm, "next": 0, "count": 0, "xf": xf, "col": cs, "on": on}
	_litter[kind] = pool
	return pool


func add_litter(kind: String, xf: Transform3D, col: Color) -> void:
	var pool := _litter_pool(kind)
	var mm: MultiMesh = pool["mm"]
	var i: int = pool["next"]
	mm.set_instance_transform(i, xf)
	mm.set_instance_color(i, col.srgb_to_linear())
	(pool["xf"] as Array)[i] = xf
	(pool["col"] as Array)[i] = col
	(pool["on"] as Array)[i] = true
	pool["next"] = (i + 1) % LITTER_CAP
	pool["count"] = mini(int(pool["count"]) + 1, LITTER_CAP)


func remove_litter(kind: String, i: int) -> void:
	## One piece leaves the floor again (the wind took it).
	if not _litter.has(kind):
		return
	var pool: Dictionary = _litter[kind]
	(pool["mm"] as MultiMesh).set_instance_transform(i,
		Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
	(pool["on"] as Array)[i] = false
	pool["count"] = maxi(int(pool["count"]) - 1, 0)


func clear_litter() -> void:
	var gone := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for kind: String in _litter:
		var pool: Dictionary = _litter[kind]
		var mm: MultiMesh = pool["mm"]
		var on: Array = pool["on"]
		for i in range(LITTER_CAP):
			mm.set_instance_transform(i, gone)
			on[i] = false
		pool["next"] = 0
		pool["count"] = 0


## ------------------------------ Save / load -------------------------------


func save_state() -> Dictionary:
	var cells: Array[Vector2i] = []
	for c: Vector2i in _cut_cells:
		cells.append(c)
	var lit := {}
	for kind: String in _litter:
		var pool: Dictionary = _litter[kind]
		var src: Array = pool["xf"]
		var scol: Array = pool["col"]
		var on: Array = pool["on"]
		var xf: Array[Transform3D] = []
		var cs := PackedColorArray()
		for i in range(LITTER_CAP):
			if not on[i]:
				continue  ## an empty slot
			xf.append(src[i] as Transform3D)
			cs.append(scol[i] as Color)
		lit[kind] = {"xf": xf, "col": cs}
	return {"cut": cells, "litter": lit}


func apply_state(d: Dictionary) -> void:
	_cut_cells.clear()
	for c in d.get("cut", []):
		_cut_cells[c as Vector2i] = true
	clear_litter()
	var lit: Dictionary = d.get("litter", {})
	for kind in lit:
		var pool := _litter_pool(String(kind))
		var mm: MultiMesh = pool["mm"]
		var dst: Array = pool["xf"]
		var dcol: Array = pool["col"]
		var on: Array = pool["on"]
		var xf: Array = (lit[kind] as Dictionary).get("xf", [])
		var cs: PackedColorArray = (lit[kind] as Dictionary).get("col", PackedColorArray())
		var n := mini(xf.size(), LITTER_CAP)
		for i in range(n):
			var t := xf[i] as Transform3D
			var c: Color = cs[i] if i < cs.size() else Color.WHITE
			mm.set_instance_transform(i, t)
			mm.set_instance_color(i, c.srgb_to_linear())
			dst[i] = t
			dcol[i] = c
			on[i] = true
		pool["next"] = n % LITTER_CAP
		pool["count"] = n
	## Every LIVE chunk reseeds so the stubble matches the restored cut record.
	## Only the ring exists at v2.5, and that is enough: _cut_cells is a sparse
	## world-space record, so a chunk streamed in later reads it and grows its
	## stubble then. Re-placing 474,000 chunks to honour a save would be absurd.
	var live: Array = _chunks.keys()
	for key: Vector2i in live:
		_apply_chunk(key, _place_chunk(key))


## ------------------------------- Diagnostics -------------------------------


func stats() -> Dictionary:
	## For the debug menu and the geometry harness: how much meadow is actually
	## standing, and what it costs.
	var by_kind := {}
	var total := 0
	for key: Vector2i in _chunks:
		for kind: String in _chunks[key]:
			var mmi := _chunks[key][kind] as MultiMeshInstance3D
			var n := 0 if mmi.multimesh == null else mmi.multimesh.instance_count
			by_kind[kind] = int(by_kind.get(kind, 0)) + n
			total += n
	return {"chunks": _chunks.size(), "tufts": total, "by_kind": by_kind,
		"cut_cells": _cut_cells.size(),
		## v2.5: what the ring is doing right now. "chunks" is no longer the
		## world — it is what is standing within draw_dist of you.
		"draw_dist": draw_dist, "queued": _queue.size(),
		"in_flight": _pending.size(), "awaiting_fill": _apply_q.size(),
		"streaming": _ow != null,
		## v3: the tufts this system no longer carries. `tufts` above is the
		## MultiMesh half only — add these for what is actually standing.
		"gpu": {} if _gpu == null else _gpu.stats()}


func _build_material() -> void:
	var sh := Shader.new()
	sh.code = GRASS_SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh


const GRASS_SHADER := """
shader_type spatial;
// ===========================================================================
// GRASS v2 — Myrkfell
//
// One shader for eight kinds of ground cover. What varies per kind is
// geometry plus a material id in UV2.x; what varies per SEASON is a single
// global float; what varies per TUFT is a hash of its root position.
//
// UV.x  = across the blade, 0 .. 1   (the rounded-normal axis)
// UV.y  = along the blade,  0 root .. 1 tip
// UV2.x = 0 living foliage | 1 petal | 2 dried straw | 3 moss
// COLOR = the placer's local TINT (rich / thin / damp ground, wither near a
//         cave mouth). Not the albedo — the season owns the albedo now.
// ===========================================================================
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// --- the one wind. Wind.gd publishes these for every foliage shader --------
global uniform vec3 wind_dir;
global uniform float wind_strength;
global uniform float wind_time;
global uniform float season_phase;
global uniform vec3 player_pos;
global uniform float player_push;

// Draw distance is a SETTING now (Esc -> Draw Distance): set_draw_distance()
// pushes both of these every time it moves. These defaults are the Medium
// 90 m ring, so the shader is sane on the frame before the first push.
uniform float fade_start = 52.2;
uniform float fade_end = 70.2;
// v3.1: the horizon pair. A blade whose COLOR.a is below 0.75 was placed by
// one of GrassGPU's far bands and fades on THIS pair instead — it has hundreds
// of metres to go before it is allowed to become the ground.
uniform float fade_start_far = 331.0;
uniform float fade_end_far = 446.0;
// v2.7 — the trample is a set of DIALS now (Lemon: "far less dramatic"). It was
// a 1.35 m radius with a 0.30 m sideways shove that applied even while you stood
// still, so a 2.7 m ring of grass lay flat and slid around with you wherever you
// went. Now: knee-wide, a soft edge, and it only really shows when you move.
uniform float trample_radius = 0.80;
uniform float trample_idle : hint_range(0.0, 0.6) = 0.045;
uniform float trample_move : hint_range(0.0, 1.0) = 0.20;
uniform float trample_flatten : hint_range(0.0, 1.0) = 0.30;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float snow_amount : hint_range(0.0, 1.0) = 1.0;
uniform vec3 ground_tint : source_color = vec3(0.15, 0.16, 0.12);

uniform vec3 col_spring : source_color = vec3(0.35, 0.53, 0.19);
uniform vec3 col_summer : source_color = vec3(0.25, 0.40, 0.15);
uniform vec3 col_autumn : source_color = vec3(0.53, 0.45, 0.19);
uniform vec3 col_winter : source_color = vec3(0.40, 0.36, 0.24);
uniform vec3 col_dry    : source_color = vec3(0.56, 0.48, 0.25);
uniform vec3 col_moss   : source_color = vec3(0.19, 0.33, 0.14);
uniform vec3 col_snow   : source_color = vec3(0.80, 0.84, 0.90);
uniform vec3 col_seedhead : source_color = vec3(0.70, 0.60, 0.40);
uniform vec3 col_bluestem_summer : source_color = vec3(0.34, 0.46, 0.34);
uniform vec3 col_bluestem_cured  : source_color = vec3(0.62, 0.33, 0.20);

// --- REALISTIC-PIXELED (the new style, per Lemon) ------------------------
// Real species, real silhouettes — shaded like pixel art. Three moves:
//   1. every blade is carved into TEXEL CELLS (pixel_cells along its length,
//      a couple across) and each cell gets one flat value — no gradients
//      inside a cell, a hard step between cells;
//   2. the final colour is POSTERIZED to palette_steps levels per channel,
//      so the whole meadow shares one limited palette like a sprite sheet;
//   3. lighting is BANDED in light() — lit / mid / shade / dark, four flat
//      tones, no smooth falloff and no specular smear.
// v2.4 — CHUNKIER. 13 cells down to 8 and 7 palette steps down to 5: on a
// 0.18 m fescue that is a texel about 2 cm tall, so a blade reads as a short
// stack of fat pixels instead of a smooth gradient with a grid on it.
uniform float pixel_cells : hint_range(4.0, 32.0) = 8.0;
uniform float pixel_side_cells : hint_range(1.0, 6.0) = 3.0;
uniform float palette_steps : hint_range(2.0, 16.0) = 5.0;
uniform float cell_jitter : hint_range(0.0, 0.5) = 0.14;
// --- GRASS LAB (F3): the knobs that used to be literals ---------------------
uniform float pixel_on : hint_range(0.0, 1.0) = 1.0;        // 0 = smooth blades, no cells, no posterize
uniform float hue_var : hint_range(0.0, 0.5) = 0.12;        // per-plant hue rotate
uniform float val_var : hint_range(0.0, 1.0) = 0.38;        // per-plant value spread
uniform float root_dark : hint_range(0.0, 1.0) = 0.62;      // how much darker the root cells are
uniform float tip_light : hint_range(0.0, 1.0) = 0.40;      // the yellowing of the tip cells
uniform float light_bands : hint_range(1.0, 6.0) = 4.0;     // 1 = smooth Lambert, 4 = the hand-picked game bands
uniform float backlight : hint_range(0.0, 1.0) = 1.0;       // sun through a thin blade lights the tip
uniform float normal_up : hint_range(0.0, 1.0) = 0.48;      // how far the root's normal is bent toward up
uniform float posterize_gamma : hint_range(0.0, 1.0) = 1.0; // posterize in gamma space (1) or linear (0)

varying float v_u;
varying float v_side;
varying float v_hash;
varying float v_matid;
varying vec3 v_wnormal;
varying float v_fade;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	v_u = UV.y;
	v_side = UV.x;
	v_matid = UV2.x;

	// MODEL_MATRIX carries the instance transform, so its translation IS this
	// tuft's world position — one stable hash per plant, free.
	vec3 root = MODEL_MATRIX[3].xyz;
	v_hash = hash13(root);

	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = distance(root, INV_VIEW_MATRIX[3].xyz);
	float fs = (COLOR.a < 0.75) ? fade_start_far : fade_start;
	float fe = (COLOR.a < 0.75) ? fade_end_far : fade_end;
	v_fade = 1.0 - clamp((dist - fs) / max(fe - fs, 0.01), 0.0, 1.0);
	// Sink into the sod over the last stretch instead of popping out. It never
	// reaches zero — by then it is the ground's colour anyway (see fragment).
	VERTEX.y *= mix(0.34, 1.0, v_fade);

	float bend = v_u * v_u;   // the root is planted; only the tip swings

	// --- gust: two detuned waves so it never reads as a loop, plus flutter --
	float ph = wind_time * 1.15 + v_hash * 6.283 + root.x * 0.085 + root.z * 0.065;
	float gust = sin(ph) * 0.62 + sin(ph * 2.37 + 1.7) * 0.38;
	float flutter = sin(ph * 6.1 + v_hash * 3.0) * 0.20 * wind_strength;
	vec3 off = wind_dir * ((0.10 + gust * 0.26 + flutter) * wind_strength) * bend;

	// --- you, wading through: the grass PARTS at your shins. It does not lie
	// down in a two-metre ring that follows you around (v2.7). The falloff is
	// smoothstepped so there is no hard rim where the effect stops, and the
	// idle term is small enough that standing still barely registers.
	vec2 away = world.xz - player_pos.xz;
	float d = length(away);
	if (d < trample_radius) {
		float k = 1.0 - smoothstep(0.35, 1.0, d / trample_radius);
		vec2 dirn = (d > 0.0001) ? away / d : vec2(1.0, 0.0);
		float shove = k * (trample_idle + trample_move * player_push);
		off.xz += dirn * shove;
		off.y -= shove * trample_flatten * bend;
	}

	// A blade that has bent over is SHORTER standing up — it did not stretch,
	// it leaned. Without this the whole meadow visibly grows in a gust.
	off.y -= dot(off.xz, off.xz) * 0.55 * bend;

	// Model-space offset without a 4x4 inverse: transpose the normalised basis
	// and divide out the scale. Same result, a fraction of the cost, and this
	// runs on every vertex of every blade in the world.
	mat3 M = mat3(MODEL_MATRIX[0].xyz, MODEL_MATRIX[1].xyz, MODEL_MATRIX[2].xyz);
	vec3 sc = vec3(length(M[0]), length(M[1]), length(M[2]));
	mat3 Rt = transpose(mat3(M[0] / max(sc.x, 0.0001), M[1] / max(sc.y, 0.0001),
		M[2] / max(sc.z, 0.0001)));
	VERTEX += (Rt * off) / max(sc, vec3(0.0001));

	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// season_phase 0..1 -> four stops, held then turned (same curve as the leaves,
// so the meadow and the canopy change colour on the same week)
vec3 season_colour(float p) {
	float t = fract(p) * 4.0;
	int i = int(floor(t));
	float f = smoothstep(0.55, 1.0, fract(t));
	vec3 a = col_spring;
	vec3 b = col_summer;
	if (i == 1) { a = col_summer; b = col_autumn; }
	else if (i == 2) { a = col_autumn; b = col_winter; }
	else if (i == 3) { a = col_winter; b = col_spring; }
	return mix(a, b, f);
}

// One instanced flower mesh, four species — the hash picks which.
vec3 petal_colour(float h) {
	if (h < 0.34) return vec3(0.92, 0.90, 0.84);   // oxeye daisy
	if (h < 0.62) return vec3(0.95, 0.80, 0.20);   // buttercup
	if (h < 0.86) return vec3(0.55, 0.46, 0.78);   // aster
	return vec3(0.83, 0.28, 0.22);                 // paintbrush
}

void fragment() {
	vec3 col;
	if (v_matid > 4.5) {
		// LITTLE BLUESTEM has its own year: blue-green through summer, cures
		// copper in early autumn, and STANDS copper all winter — the cure only
		// releases when the spring flush comes in.
		float p = fract(season_phase);
		float cure = smoothstep(0.50, 0.70, p);
		cure = max(cure, 1.0 - smoothstep(0.06, 0.20, p));
		col = mix(col_bluestem_summer, col_bluestem_cured, cure);
		col *= 0.85 + 0.3 * v_hash;
	}
	else if (v_matid > 3.5) col = col_seedhead * (0.82 + 0.36 * v_hash); // timothy spike
	else if (v_matid > 2.5) col = col_moss;
	else if (v_matid > 1.5) col = col_dry;
	else if (v_matid > 0.5) col = petal_colour(fract(v_hash * 7.13));
	else col = season_colour(season_phase);

	if (v_matid < 0.5) {
		// no two plants the same green: value spread, then a small hue rotate
		col *= (1.0 - val_var * 0.5) + val_var * v_hash;
		col = mix(col, col.gbr, (v_hash - 0.5) * hue_var);
	}
	col *= COLOR.rgb;   // the placer's local tint

	// ---- REALISTIC-PIXELED: carve the blade into texel cells ----
	// Everything below shades by the CELL's coordinate, never the fragment's,
	// so each cell comes out one flat colour with a hard step to the next —
	// the blade reads as a little column of pixels.
	bool px = pixel_on > 0.5;
	float cu = px ? (floor(v_u * pixel_cells) + 0.5) / pixel_cells : v_u;
	float cs = px ? floor(v_side * pixel_side_cells) : v_side;
	// one stable random per cell per plant — sprite-noise, not film grain
	float cj = fract(sin(cu * 127.1 + cs * 311.7 + v_hash * 74.7) * 43758.5453);
	if (px) col *= 1.0 - cell_jitter * 0.5 + cell_jitter * cj;

	// Depth in the mass, per-cell: shaded root cells, lit yellowing tip cells.
	col *= mix(1.0 - root_dark, 1.0, smoothstep(0.0, 0.55, cu));
	col = mix(col, col * vec3(1.22, 1.15, 0.76), smoothstep(0.5, 1.0, cu) * tip_light);

	// rain: darker, and it stays that way a while after
	col *= mix(1.0, 0.60, wetness);

	// winter: snow settles cell by cell — tip cells whiten first, and the
	// per-cell jitter decides stragglers, so the line between snow and blade
	// is ragged pixels, not a smooth ramp
	float winter = smoothstep(0.74, 0.90, fract(season_phase))
		* (1.0 - smoothstep(0.97, 1.0, fract(season_phase)));
	float up = clamp(v_wnormal.y, 0.0, 1.0);
	float snow_cell = step(1.0 - winter * snow_amount * up * (0.20 + 0.80 * cu), cj);
	col = mix(col, col_snow, snow_cell);

	// far edge: still becomes the ground it grows out of
	col = mix(ground_tint, col, 0.30 + 0.70 * v_fade);

	// ---- and POSTERIZE: the whole meadow shares one limited palette ----
	// In GAMMA space by default (GRASS LAB, 2026-09-12): the steps then land
	// where the eye sees them. Posterizing the LINEAR value crushed every dark
	// tint into the bottom step -- a shaded tuft came out black, and the
	// warmed winter blade rounded into the red cell (the bright-red winter
	// meadow). 16 steps is "no posterize".
	if (px && palette_steps < 15.5) {
		if (posterize_gamma > 0.5) {
			col = pow(max(col, vec3(0.0)), vec3(1.0 / 2.2));
			col = floor(col * palette_steps + 0.5) / palette_steps;
			col = pow(col, vec3(2.2));
		} else {
			col = floor(col * palette_steps + 0.5) / palette_steps;
		}
	}

	ALBEDO = col;

	// ROUNDED NORMALS, then blended toward world-up at the base. The tips stay
	// round so they read as blades; the roots read as ground. Without the
	// blend a meadow sparkles like tinsel at every camera move.
	vec3 n = normalize(mix(v_wnormal, vec3(0.0, 1.0, 0.0), mix(normal_up, 0.06, v_u)));
	if (!FRONT_FACING) n = -n;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	// Pixel style: no specular smear — a sprite doesn't glint. Wet grass gets
	// its darkening above and one extra light band below instead of gloss.
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	// BANDED LIGHT — four flat tones, hard edges. This is the half of the
	// pixel look that is not the texels: smooth Lambert falloff across a
	// curved blade reads as 3D render; three steps read as sprite shading.
	float nl = dot(NORMAL, LIGHT);
	float band;
	if (light_bands > 3.5 && light_bands < 4.5) {
		// the game's own four, hand-picked
		if (nl > 0.55) band = 1.0;
		else if (nl > 0.18) band = 0.72;
		else if (nl > -0.12) band = 0.45;
		else band = 0.26;
	} else if (light_bands < 1.5) {
		band = 0.26 + 0.74 * clamp(nl * 0.5 + 0.5, 0.0, 1.0);   // smooth Lambert
	} else {
		float nb = floor(light_bands + 0.5);
		float q = floor(clamp(nl * 0.5 + 0.5, 0.0, 0.999) * nb) / (nb - 1.0);
		band = 0.26 + 0.74 * q;
	}
	// wet meadow: the lit band brightens a step instead of glinting
	band *= 1.0 + wetness * 0.18 * step(0.9, band);
	DIFFUSE_LIGHT += LIGHT_COLOR * ALBEDO * band * ATTENUATION / PI;
	// backlight, banded too: sun behind a thin blade lights the tip cells —
	// two flat steps, strongest at the tip, none at the root
	float back = max(-nl, 0.0);
	float bband = (back > 0.6 ? 0.42 : (back > 0.25 ? 0.20 : 0.0)) * backlight;
	DIFFUSE_LIGHT += LIGHT_COLOR * ALBEDO * bband * v_u * (1.0 - wetness * 0.45) * ATTENUATION / PI;
}
"""
