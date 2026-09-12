extends Node3D
class_name GrassGPU
## GRASS v3 — THE FIELD IS PLACED ON THE GPU.
##
## v2.7's meadow is correct and it is CPU-bound. Measured live at spawn, 90 m
## ring, 429,116 tufts:
##
##     fps 37-46 | process 14.4 ms | physics 11.4 ms | cpu_render 1.7 ms
##     draw calls 3058 | primitives 2.05 M
##
## ~26 ms of CPU against a ~22 ms frame. The renderer is not the wall. The wall
## is `_fill_mm`: an interpreted loop calling `set_instance_transform` and
## `set_instance_color` once per tuft, three chunks a frame while you walk —
## about 14,000 GDScript calls per frame — plus 180 chunks x 9 kinds of
## MultiMeshInstance, which is most of those 3,058 draw calls.
##
## So v3 deletes the placement instead of optimising it. Every blade of RED
## FESCUE outside the spawn valley is now positioned by a `shader_type
## particles` process shader that reads the baked terrain straight out of a
## texture. No worker pool, no apply queue, no per-chunk buffers, no streaming:
## four GPUParticles3D emitters and four draw calls for the whole horizon.
##
## WHY ONLY FESCUE (v3.0). `std` is 284,653 of the 429,116 tufts — 66% of the
## meadow and effectively all of the fill cost. The other eight kinds are 58k
## instances, most of them inside the 30 m detail ring, and each one is a
## different mesh; a GPUParticles3D draws ONE mesh for every particle it owns,
## so a kind costs an emitter. Fescue first, measure, then decide whether
## bluestem and the hiding grass are worth two more.
##
## WHY NOT THE VALLEY. Inside the CaveField footprint the ground is the VOXEL
## surface — you can dig it, and a cave roof is not a heightfield sample. The
## GPU has the baked heightfield and nothing else, so it rejects everything
## inside the field rect and `GrassSystem` keeps the valley exactly as it was,
## digging and all. The seam is the field's own rim, which is inside the
## terrain's valley hole — the same seam `_place_chunk` already draws.
##
## -------------------------------------------------------------------------
## HOW A BLADE FINDS ITS SPOT
##
## Each particle owns one cell of a world-anchored square grid, forever. Its
## INDEX picks a cell SLOT; the slot is mapped to a WORLD cell by wrapping it
## into the window around the player:
##
##     world_cx = cx + S * round((centre_cx - cx) / S)
##
## That is the whole trick, and getting it wrong is the obvious bug: address a
## slot as `centre - S/2 + cx` and every blade in the world slides one cell
## sideways each time you cross a cell boundary — the meadow crawls with you.
## Wrapped, a particle keeps one residue class mod S, so it stands still while
## you walk and only ever teleports by a full window width — from behind you to
## in front of you, past the far fade, once.
##
## Position inside the cell is a hash of the WORLD cell, so it is stable across
## the teleport, across a reload, and across a change of draw distance.
##
## BANDS ARE THE LOD. A GPUParticles3D cannot choose a mesh per particle, so
## the distance ladder is four emitters over four annuli, each drawing the mesh
## its band deserves. Each grid is a HOLLOW square (outer S, inner Si) so the
## far band does not allocate the 16 m disc it will never draw:
##
##     band  radii      mesh  cells/m^2  particles
##     0     0 - 9      hi    9.65       ~3.1k
##     1     9 - 16     mid   9.65       ~6.9k
##     2     16 - 52    lo    9.65       ~95k
##     3     52 - 90    lo    3.38       ~73k      (v2.7's FAR_KEEP, baked in)
##
## ~178k particles where v2.7 held 284,653 instances, and the far band's
## thinning is a coarser CELL rather than `visible_instance_count`, so the
## particles it does not draw are never allocated.
##
## NOISE. `_tall` and `_clump` decide where fescue is allowed; the CPU reads
## them from FastNoiseLite and the GPU cannot. Reimplementing FastNoiseLite's
## simplex in GLSL would agree to about three decimal places and then disagree
## about `is_tall_at()`, which is the STEALTH CHECK — you would be concealed on
## bare ground. So the noises are baked ONCE into seamless tiles and BOTH sides
## read the same image. They agree because they are the same numbers.

const BAND_R := [0.0, 9.0, 16.0, 52.0, 90.0]   ## band n spans BAND_R[n] .. [n+1]
const BAND_MESH := [0, 1, 2, 2]                ## index into the std mesh ladder
const BAND_KEEP := [1.0, 1.0, 1.0, 0.35]       ## v2.7's FAR_KEEP past the fade
const BASE_DENSITY := 9.65                     ## tufts/m^2 — measured off v2.7:
											   ## 284,653 std over a 29,491 m^2 ring
const TALL_T := 0.34                           ## must match GrassSystem.TALL_T
const CLUMP_CUT := -0.62                       ## ...and its clump cutoff

## Seamless noise tiles. A tile repeats across the map; the period is chosen so
## the repeat is longer than anything you can see at once (2 km) for the slow
## noises and shorter than a glance (64 m) for the clump, where a repeat reads
## as texture rather than as pattern.
const COARSE_TILE_M := 2048.0
const COARSE_PX := 1024
const FINE_TILE_M := 64.0
const FINE_PX := 256

var draw_dist := 90.0
var base_seed := 0

var _emit: Array[GPUParticles3D] = []
var _pmat: Array[ShaderMaterial] = []
var _mat: ShaderMaterial = null          ## the SHARED grass spatial material
var _noise := {}                         ## name -> the seamless Image both sides read
var _tall_img: Image = null              ## ...and the one the STEALTH check reads
var _ow: Overworld = null
var _ready_ok := false


# =============================================================================
# SETUP
# =============================================================================

func setup(spatial_mat: ShaderMaterial, meshes: Array, seed_v: int,
		field_min: Vector2, field_max: Vector2) -> bool:
	## `meshes` is GrassSystem's std ladder [hi, mid, lo] — the SAME ArrayMeshes,
	## not copies. `spatial_mat` is its ShaderMaterial, so wetness, the season,
	## the trample dials and the fade keep being pushed to one place and the GPU
	## field and the valley meadow never drift apart.
	_mat = spatial_mat
	base_seed = seed_v
	_ow = Overworld.inst
	if _ow == null:
		push_warning("GrassGPU: no Overworld — the valley IS the world, nothing to do")
		return false

	var hm := _height_texture()
	var wm := _water_texture()
	var cm := _colour_texture()
	if hm == null:
		push_error("GrassGPU: could not build the height texture")
		return false
	_bake_noise()
	var ntex := {}
	for k: String in _noise:
		ntex[k] = ImageTexture.create_from_image(_noise[k] as Image)

	var sh := Shader.new()
	sh.code = PLACE_SHADER

	for b in range(4):
		var g := _make_band(b, sh, meshes)
		g.process_material.set_shader_parameter("hmap", hm)
		g.process_material.set_shader_parameter("wmap", wm)
		if cm != null:
			g.process_material.set_shader_parameter("cmap", cm)
			g.process_material.set_shader_parameter("cmap_size",
				Vector2(cm.get_width(), cm.get_height()))
		g.process_material.set_shader_parameter("ndens", ntex["dens"])
		g.process_material.set_shader_parameter("ntall", ntex["tall"])
		g.process_material.set_shader_parameter("nmoist", ntex["moist"])
		g.process_material.set_shader_parameter("nlush", ntex["lush"])
		g.process_material.set_shader_parameter("nclump", ntex["clump"])
		g.process_material.set_shader_parameter("map_size", Vector2(_ow.nx, _ow.nz))
		g.process_material.set_shader_parameter("map_step", _ow.step)
		g.process_material.set_shader_parameter("map_origin", Vector2(_ow.x0, _ow.z0))
		g.process_material.set_shader_parameter("h_range", Vector2(_ow.h_min, _ow.h_max))
		g.process_material.set_shader_parameter("w_range", Vector2(_ow.w_min, _ow.w_max))
		g.process_material.set_shader_parameter("coarse_tile", COARSE_TILE_M)
		g.process_material.set_shader_parameter("fine_tile", FINE_TILE_M)
		g.process_material.set_shader_parameter("field_min", field_min)
		g.process_material.set_shader_parameter("field_max", field_max)
		g.process_material.set_shader_parameter("tall_t", TALL_T)
		g.process_material.set_shader_parameter("clump_cut", CLUMP_CUT)
	_ready_ok = true
	print("GrassGPU: %d emitters, %d particles, %d draw calls for the whole horizon"
		% [_emit.size(), total_particles(), _emit.size()])
	return true


func _make_band(b: int, sh: Shader, meshes: Array) -> GPUParticles3D:
	var r0 := float(BAND_R[b])
	var r1 := float(BAND_R[b + 1])
	var cell := sqrt(1.0 / (BASE_DENSITY * float(BAND_KEEP[b])))
	## Outer and inner side in cells. Both are forced EVEN so the hollow ring
	## (S - Si) splits into two equal strips — the addressing below assumes it.
	var s := int(ceil(2.0 * r1 / cell))
	var si := int(floor(2.0 * r0 / cell))
	s += s & 1
	si -= si & 1
	if si >= s:
		si = s - 2
	var t := (s - si) / 2
	var count := s * s - si * si

	var pm := ShaderMaterial.new()
	pm.shader = sh
	pm.set_shader_parameter("grid_S", s)
	pm.set_shader_parameter("grid_Si", si)
	pm.set_shader_parameter("grid_t", t)
	pm.set_shader_parameter("cell_m", cell)
	pm.set_shader_parameter("r0", r0)
	pm.set_shader_parameter("r1", r1)
	pm.set_shader_parameter("centre", Vector3.ZERO)

	var g := GPUParticles3D.new()
	g.name = "GrassBand%d" % b
	g.process_material = pm
	g.draw_pass_1 = meshes[BAND_MESH[b]] as Mesh
	g.material_override = _mat
	g.amount = count
	g.lifetime = 8.0             ## nothing really dies — process() rewrites the
								 ## transform every step — but the cycle has to be
								 ## short enough that a particle lost to a hiccup
								 ## comes back inside a second or two
	g.one_shot = false
	g.explosiveness = 1.0        ## THE WHOLE FIELD AT ONCE. At 0.0 the emitter
								 ## spreads `amount` emissions evenly across the
								 ## lifetime — 179,716 blades over an hour is 50 a
								 ## second, which looks exactly like "the shader is
								 ## broken" for the first ten minutes
	g.randomness = 0.0
	g.preprocess = 0.0
	## fixed_fps 0 / interpolate ON. Both of these were the other way round first
	## — 12 fps because a static field only has to keep up with walking, and no
	## interpolation because a blade that teleports across the ring must not be
	## seen SLIDING there. Measured: with `interpolate = false` the emitter runs,
	## reports every particle alive, and draws nothing at all. It is not worth a
	## second day of bisecting; the process shader is a handful of texture
	## fetches and running it per frame costs less than finding out why.
	##
	## The teleport is invisible anyway: a blade only ever jumps a full window
	## width, which lands it past the far fade where it is already the ground's
	## colour.
	g.fixed_fps = 0
	g.interpolate = true
	g.local_coords = false       ## TRANSFORM is written in world space
	g.draw_order = GPUParticles3D.DRAW_ORDER_INDEX   ## never sort 95k particles
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	## The node stays at the origin (see start() in the shader), so the box has
	## to be the WORLD, not the ring. That means the emitter is never frustum
	## culled — which costs nothing, because a ring centred on the player is on
	## screen by definition. Shadows are off, so no shadow pass pays for it.
	g.visibility_aabb = AABB(Vector3(-20000.0, -4000.0, -20000.0),
		Vector3(40000.0, 8000.0, 40000.0))
	g.emitting = true
	add_child(g)
	_emit.append(g)
	_pmat.append(pm)
	return g


# =============================================================================
# TERRAIN, HANDED TO THE GPU AS-IS
# =============================================================================

func _height_texture() -> ImageTexture:
	## `maine_height.r16` is already exactly the bytes an RG8 image wants: one
	## u16 per sample, little-endian, so r = the low byte and g = the high one.
	## No conversion, no float image, no 20 MB of GDScript. The shader puts the
	## pair back together and texelFetches it, because BILINEAR filtering an
	## RG8 pair would blend the low byte across a carry and produce cliffs.
	if _ow._h.size() < _ow.nx * _ow.nz * 2:
		return null
	var img := Image.create_from_data(_ow.nx, _ow.nz, false, Image.FORMAT_RG8, _ow._h)
	return ImageTexture.create_from_image(img)


func _water_texture() -> ImageTexture:
	if _ow._w.size() < _ow.nx * _ow.nz * 2:
		## No water map: hand it a 1x1 "dry" tile rather than branching in the
		## shader for a case that never happens in a real bake.
		var one := Image.create(1, 1, false, Image.FORMAT_RG8)
		one.set_pixel(0, 0, Color(0, 0, 0, 1))
		return ImageTexture.create_from_image(one)
	var img := Image.create_from_data(_ow.nx, _ow.nz, false, Image.FORMAT_RG8, _ow._w)
	return ImageTexture.create_from_image(img)


func _colour_texture() -> Texture2D:
	## The colour map is ALREADY a Texture2D on the GPU — Overworld loaded it to
	## get its Image. Load it again (the resource cache hands back the same one)
	## rather than re-uploading the Image we already have a copy of.
	return load(Overworld.DATA_DIR + "maine_color.png") as Texture2D


func _bake_noise() -> void:
	## ONE set of numbers, read by both sides. See the header: the stealth check
	## and the grass have to agree about where a tall patch is, and two
	## implementations of simplex noise never will.
	##
	## get_seamless_image() generates over the noise's own domain at one unit
	## per pixel, so a feature is 1/frequency PIXELS across. We want it to be
	## 1/frequency METRES across, and a pixel is tile_m/px metres — hence
	## f_img = f_world * tile_m / px.
	var cs := COARSE_TILE_M / float(COARSE_PX)
	_noise["dens"] = _layer(0.035 * cs, base_seed * 7 + 3, COARSE_PX)
	_noise["tall"] = _layer(0.016 * cs, base_seed * 13 + 11, COARSE_PX)
	_noise["moist"] = _layer(0.011 * cs, base_seed * 23 + 9, COARSE_PX)
	_noise["lush"] = _layer(0.045 * cs, base_seed * 31 + 19, COARSE_PX)
	var fs := FINE_TILE_M / float(FINE_PX)
	_noise["clump"] = _layer(0.42 * fs, base_seed * 17 + 5, FINE_PX)
	_tall_img = _noise["tall"]


func _layer(freq: float, seed_v: int, px: int) -> Image:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = freq
	n.seed = seed_v
	return n.get_seamless_image(px, px)


# =============================================================================
# THE ONE THING THIS DOES PER FRAME
# =============================================================================

func _process(_delta: float) -> void:
	if not _ready_ok:
		return
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return
	## The node NEVER moves — EMISSION_TRANSFORM has to stay the identity. The
	## ring follows you through this one uniform instead, four sets a frame.
	var c := p.global_position
	for pm in _pmat:
		pm.set_shader_parameter("centre", c)


## The tall-patch mask, answered off the SAME baked tile the process shader
## reads, so "the grass here is tall" means one thing in this game and not two.
## GrassSystem._tall_noise_at calls straight through to this — the CPU places
## the hiding bunchgrass, the GPU refuses to put fescue in it, and they draw
## the same line. Read-only, so the worker threads may call it.
func tall_noise(wx: float, wz: float) -> bool:
	if _tall_img == null:
		return false
	return _tile(_tall_img, COARSE_TILE_M, COARSE_PX, wx, wz).r * 2.0 - 1.0 > TALL_T


func _tile(img: Image, tile_m: float, px: int, wx: float, wz: float) -> Color:
	var u := int(floor(fposmod(wx / tile_m, 1.0) * float(px))) % px
	var v := int(floor(fposmod(wz / tile_m, 1.0) * float(px))) % px
	return img.get_pixel(u, v)


func set_draw_distance(m: float) -> void:
	## The outer band is the only one whose radius moves; the near ladder is
	## about how big a blade is on screen, not about how far you can see.
	draw_dist = clampf(m, 30.0, 180.0)
	if _emit.size() < 4:
		return
	var r1 := maxf(draw_dist, float(BAND_R[3]) + 4.0)
	_pmat[3].set_shader_parameter("r1", r1)
	var cell := sqrt(1.0 / (BASE_DENSITY * float(BAND_KEEP[3])))
	var s := int(ceil(2.0 * r1 / cell))
	s += s & 1
	var si := int(_pmat[3].get_shader_parameter("grid_Si"))
	_pmat[3].set_shader_parameter("grid_S", s)
	_pmat[3].set_shader_parameter("grid_t", (s - si) / 2)
	_emit[3].amount = s * s - si * si


func total_particles() -> int:
	var n := 0
	for g in _emit:
		n += g.amount
	return n


func stats() -> Dictionary:
	var bands := []
	for i in range(_emit.size()):
		bands.append({"r": [BAND_R[i], BAND_R[i + 1]], "amount": _emit[i].amount})
	return {"gpu_particles": total_particles(), "emitters": _emit.size(),
		"draw_dist": draw_dist, "bands": bands}


# =============================================================================
# THE PROCESS SHADER
# =============================================================================

const PLACE_SHADER := """
shader_type particles;
// NO render_mode. See the note on start(): this shader mirrors the shape of
// Godot's own default particle process shader as closely as it can, because
// deviating from it is how you get an emitter that runs, reports 179,716 live
// particles, and draws absolutely nothing.

// --- the world-anchored grid -----------------------------------------------
uniform int grid_S;          // outer side, cells (even)
uniform int grid_Si;         // inner hole side, cells (even, 0 on band 0)
uniform int grid_t;          // (S - Si) / 2, the strip width
uniform float cell_m;
uniform float r0;
uniform float r1;
uniform vec3 centre;

// --- the bake ---------------------------------------------------------------
uniform sampler2D hmap : filter_nearest, repeat_disable;
uniform sampler2D wmap : filter_nearest, repeat_disable;
uniform sampler2D cmap : filter_linear, repeat_disable;
uniform vec2 map_size;
uniform vec2 cmap_size = vec2(1.0, 1.0);
uniform float map_step;
uniform vec2 map_origin;
uniform vec2 h_range;
uniform vec2 w_range;

// --- the shared noise tiles -------------------------------------------------
// Five single-channel tiles, not one packed RGBA. Packing would mean four
// million get_pixel/set_pixel calls in GDScript at boot to interleave them,
// which is seconds of hitch to save three texture fetches nobody can measure.
uniform sampler2D ndens : filter_linear, repeat_enable;
uniform sampler2D ntall : filter_linear, repeat_enable;
uniform sampler2D nmoist : filter_linear, repeat_enable;
uniform sampler2D nlush : filter_linear, repeat_enable;
uniform sampler2D nclump : filter_linear, repeat_enable;
uniform float coarse_tile;
uniform float fine_tile;

// --- the valley, which belongs to the voxel field ---------------------------
uniform vec2 field_min;
uniform vec2 field_max;

uniform float tall_t;
uniform float clump_cut;

const float SKY_WATER_MAX = 30.0;
const float NO_WATER = -100000.0;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	return fract((p + p) * p);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// The r16 pair, put back together. texelFetch, never texture() — bilinear on
// an RG8 pair blends the LOW byte across a carry and invents cliffs.
float h_texel(ivec2 p) {
	p = clamp(p, ivec2(0), ivec2(map_size) - ivec2(1));
	vec2 rg = texelFetch(hmap, p, 0).rg;
	float v = (floor(rg.r * 255.0 + 0.5) + floor(rg.g * 255.0 + 0.5) * 256.0) / 65535.0;
	return h_range.x + v * (h_range.y - h_range.x);
}

float sample_h(vec2 w) {
	vec2 f = (w - map_origin) / map_step;
	ivec2 i = ivec2(floor(f));
	vec2 t = f - vec2(i);
	float a = h_texel(i);
	float b = h_texel(i + ivec2(1, 0));
	float c = h_texel(i + ivec2(0, 1));
	float d = h_texel(i + ivec2(1, 1));
	return mix(mix(a, b, t.x), mix(c, d, t.x), t.y);
}

// Overworld.sample_water: nearest sample, 0 means dry, and a surface more than
// SKY_WATER_MAX above its own bed is a bake glitch, not a lake.
float sample_w(vec2 w) {
	ivec2 i = clamp(ivec2(round((w - map_origin) / map_step)),
		ivec2(0), ivec2(map_size) - ivec2(1));
	vec2 rg = texelFetch(wmap, i, 0).rg;
	float raw = floor(rg.r * 255.0 + 0.5) + floor(rg.g * 255.0 + 0.5) * 256.0;
	if (raw < 0.5) { return NO_WATER; }
	float s = w_range.x + ((raw - 1.0) / 65534.0) * (w_range.y - w_range.x);
	if (s - h_texel(i) > SKY_WATER_MAX) { return NO_WATER; }
	return s;
}

vec3 sample_c(vec2 w) {
	vec2 i = clamp(round((w - map_origin) / map_step), vec2(0.0), cmap_size - vec2(1.0));
	return texture(cmap, (i + 0.5) / cmap_size).rgb;
}

float nz_at(sampler2D t, vec2 w, float tile) { return texture(t, w / tile).r * 2.0 - 1.0; }

// Overworld._forest_weight, straight across — the SAME weight the F1 paint
// tool drives, so painting Meadow thins the woods and the grass agrees.
float forest_weight(vec3 c) {
	return clamp((c.g - c.r * 0.9 - c.b * 0.6) * 8.0, 0.0, 1.0);
}

void grass_place(uint idx, out mat4 xf, out vec4 col) {
	col = vec4(1.0);
	// ---- slot -> cell in the hollow square -------------------------------
	int n = int(idx);
	int S = grid_S;
	int Si = grid_Si;
	int t = grid_t;
	int row; int cc;
	int top = t * S;
	int mid = Si * 2 * t;
	if (n < top) {
		row = n / S; cc = n - row * S;
	} else if (n < top + mid) {
		int m = n - top;
		int rr = m / (2 * t);
		int k = m - rr * (2 * t);
		row = t + rr;
		cc = (k < t) ? k : (S - 2 * t + k);
	} else {
		int m = n - top - mid;
		int rr = m / S;
		row = t + Si + rr;
		cc = m - rr * S;
	}

	// ---- cell slot -> WORLD cell, wrapped ---------------------------------
	// The whole point. Wrapping keeps a particle in one residue class mod S,
	// so it stands still while you walk instead of sliding a cell at a time.
	vec2 ctr = floor(centre.xz / cell_m);
	vec2 slot = vec2(float(cc), float(row));
	vec2 wc = slot + float(S) * round((ctr - slot) / float(S));

	vec2 j = hash22(wc + vec2(17.3, 91.7));
	vec2 w = (wc + j) * cell_m;

	// ---- the annulus, and everything that says no -------------------------
	float d = length(w - centre.xz);
	bool live = (d >= r0 && d < r1);

	// the valley belongs to the voxel field
	if (w.x > field_min.x && w.x < field_max.x && w.y > field_min.y && w.y < field_max.y) {
		live = false;
	}
	if (w.x < map_origin.x || w.y < map_origin.y
			|| w.x > map_origin.x + map_size.x * map_step
			|| w.y > map_origin.y + map_size.y * map_step) {
		live = false;
	}

	float gy = sample_h(w);
	float wy = sample_w(w);
	if (wy != NO_WATER && wy > gy - 0.15) { live = false; }   // nothing grows in the lake

	float dens = nz_at(ndens, w, coarse_tile);
	float tall = nz_at(ntall, w, coarse_tile);
	float moist = nz_at(nmoist, w, coarse_tile);
	float lush = nz_at(nlush, w, coarse_tile);
	vec3 gc = sample_c(w);
	float fw = forest_weight(gc);
	moist += fw * 0.22;
	lush -= fw * 0.16;

	// This emitter IS red fescue. The hiding grass is a different mesh and
	// therefore a different emitter, so a tall patch is simply not ours.
	if (tall > tall_t) { live = false; }
	// v2.7's short-grass draw roll, as a hash instead of an rng — same shape,
	// same 0.88 +/- 0.10 * SHORT_KEEP(0.94).
	if (hash21(w * 3.1 + vec2(5.0, 9.0)) > (0.88 + dens * 0.10) * 0.94) { live = false; }
	// ...and it still CLUMPS at the near scale. Only the deepest troughs.
	if (nz_at(nclump, w, fine_tile) < clump_cut) { live = false; }

	if (!live) {
		// Degenerate, not deleted: a particle that is not drawn still has to be
		// somewhere, and a zero basis is the cheapest triangle there is.
		xf = mat4(vec4(0.0), vec4(0.0), vec4(0.0), vec4(w.x, -9000.0, w.y, 1.0));
		return;
	}

	// ---- the ground it grows out of ---------------------------------------
	float gx = sample_h(w + vec2(0.8, 0.0));
	float gz = sample_h(w + vec2(0.0, 0.8));
	vec3 p = vec3(w.x, gy, w.y);
	vec3 nrm = normalize(cross(vec3(0.0, gz - gy, 0.8), vec3(0.8, gx - gy, 0.0)));
	if (nrm.y < 0.0) { nrm = -nrm; }
	// gravitropic: part of the way to the ground normal, the rest to gravity
	vec3 up = normalize(mix(nrm, vec3(0.0, 1.0, 0.0), 0.42));
	float yaw = hash21(wc + vec2(3.7, 8.1)) * 6.2831853;
	vec3 fwd = vec3(cos(yaw), 0.0, sin(yaw));
	vec3 rgt = cross(fwd, up);
	if (dot(rgt, rgt) < 1e-6) { rgt = vec3(1.0, 0.0, 0.0); }
	rgt = normalize(rgt);
	vec3 bwd = normalize(cross(up, rgt));

	float vigour = 1.0 + lush * 0.34 + moist * 0.12;
	float h1 = hash11(float(idx) * 0.7 + wc.x * 0.013 + wc.y * 0.029);
	float h2 = hash21(wc * 1.7 + vec2(41.0, 13.0));
	float sxz = mix(0.82, 1.28, h1);
	float sy = mix(0.72, 1.36, h2) * vigour;

	xf = mat4(vec4(rgt * sxz, 0.0), vec4(up * sy, 0.0), vec4(bwd * sxz, 0.0),
		vec4(p.x, p.y - 0.02, p.z, 1.0));

	// ---- the tint (NOT the albedo — the shader owns the season) -----------
	vec3 tint = vec3(1.0);
	float dry = clamp(-lush, 0.0, 1.0);
	tint = mix(tint, vec3(1.18, 1.06, 0.72), dry * 0.55);
	tint = mix(tint, vec3(0.82, 1.02, 0.80), clamp(moist, 0.0, 1.0) * 0.45);
	tint *= mix(0.90, 1.10, hash21(wc + vec2(77.0, 31.0)));
	// grow the meadow out of the ground it stands on: take the map's HUE, not
	// its value, or the whole field darkens with the terrain and the draw
	// distance becomes a visible green disc laid on the hillside.
	float gm = max((gc.r + gc.g + gc.b) / 3.0, 0.05);
	tint *= mix(gc / gm, vec3(1.0), 0.62);
	// COLOR reaches the spatial shader in LINEAR space, same as the CPU path's
	// srgb_to_linear() on the instance colour.
	col = vec4(pow(tint, vec3(2.2)), 1.0);
}

// THE ONE NON-OBVIOUS LINE IN THIS FILE is `EMISSION_TRANSFORM * x` below.
//
// A custom particles shader that writes an absolute world TRANSFORM in start()
// and skips that multiply emits nothing at all — no error, no warning, the
// emitter reports every particle alive and the screen stays empty. Godot's own
// generated process shader ends start() with `TRANSFORM = EMISSION_TRANSFORM *
// TRANSFORM`, and the activation path depends on it. Verified the hard way:
// same shader, same mesh, same emitter — without the multiply, nothing; with
// it, 300 spheres.
//
// GrassGPU therefore keeps its node at the ORIGIN with an identity transform,
// so EMISSION_TRANSFORM is the identity and the multiply is free. Do not
// "optimise" by moving this node onto the player to tighten the AABB: it would
// silently double-transform the whole meadow 600 m into the sea.
void start() {
	mat4 x; vec4 c;
	grass_place(INDEX, x, c);
	TRANSFORM = EMISSION_TRANSFORM * x;
	VELOCITY = vec3(0.0);
	COLOR = c;
}

void process() {
	// TRANSFORM is world space by now, so no multiply here.
	mat4 x; vec4 c;
	grass_place(INDEX, x, c);
	TRANSFORM = x;
	VELOCITY = vec3(0.0);
	COLOR = c;
}
"""
