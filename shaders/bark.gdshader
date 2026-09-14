shader_type spatial;
// ============================================================================
// Bark — The Withering / Myrkfell trees v4  (claude/trees-v4-kit.md)
//
// REWRITTEN 2026-08-30. Two things changed and they are connected:
//
// 1. THE RELIEF IS REAL NOW. TreeKit._bark_offset pushes every ring vertex of
//    a trunk in or out by a per-species bark field, so the plates and fissures
//    break the SILHOUETTE. That is what parallax occlusion mapping was faking
//    here before, badly and at the cost of a 28-step march per fragment on
//    every trunk in view. The POM is GONE. The normal map still fills in the
//    grain between the plates, which is the half of the job it was always
//    better at.
//
// 2. THE READ leans on the "realistic pixeled" language grass v2.3 and the PSX
//    skin pass established — but LIGHTLY. The first pass snapped the albedo
//    hard onto 3 cm cells and posterised to 7 steps, and Lemon's call was
//    immediate: "less pixelated, more bark-like". So the cells are half the
//    size, only half-mixed against the true sample, and the palette has room
//    to breathe. The wood still sits in the same picture as the grass; it just
//    reads as bark first and as a style second.
//      * texel CELLS: measured in METRES, so bark texels are the same size on
//        a sapling and on a great pine and never swim as you walk past —
//        blended at `cell_mix`, not snapped outright.
//      * POSTERIZE on VALUE, at a step count fine enough to keep the plates.
//      * a banded light(): flat diffuse tones, no specular at all.
//
// 3. EVERY TREE WEARS ITS OWN BARK (Lemon, 2026-08-30). 420 trees share a
//    handful of meshes and ONE material per species — that sharing is what
//    makes the forest affordable, and it is also what made every maple wear
//    the same fissures in the same places. Two layers fix it without giving
//    anything back:
//      * the RELIEF is seeded per authored recipe in TreeKit, so recipe 0's
//        oak and recipe 3's oak do not share a single plate;
//      * the SHADING is seeded per TREE through `instance uniform`s, which
//        Godot patches per draw call — no material duplication, no extra
//        draw calls, no cache pressure. TreeV2._seed_bark_look() slides each
//        trunk to its own patch of the tiling sheet, mirrors half of them,
//        and gives each its own tone. A stand reads as individuals.
//    Instance uniforms need Forward+ or Mobile; this project is Forward Plus.
//
// Textures still come from tools/barkgen.py and still tile in both axes; trunk
// UVs still run u = around the trunk, v = up it, in METRES.
//
// TWO TRAPS, both load-bearing:
//   * `return` is ILLEGAL inside light() in Godot. The body has to be one
//     branch. (trees-v3 §3)
//   * THE CUT FLAG IS INVERTED ON PURPOSE. A mesh with no vertex-colour array
//     reports COLOR = white, so "1 = cut" paints every trunk in the forest
//     bright heartwood. White means untouched bark; the carve writes below 1.
// ============================================================================
render_mode cull_back, diffuse_burley, specular_disabled;

uniform sampler2D bark_albedo : source_color, filter_linear_mipmap;
uniform sampler2D bark_normal : hint_normal, filter_linear_mipmap;
uniform sampler2D bark_rough : hint_default_white, filter_linear_mipmap;
// kept so TreeV2.materials_for() can go on setting it; the height field is the
// MESH's job now, not the shader's
uniform sampler2D bark_height : hint_default_black, filter_linear_mipmap;

uniform vec2 tiling = vec2(1.6, 1.6);
uniform float normal_scale : hint_range(0.0, 3.0) = 1.15;
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);

// --- per-TREE, set by TreeV2._seed_bark_look() ------------------------------
//   xy  where on the tiling sheet this trunk's bark is cut from
//   z   >0.5 mirrors the sheet in u, which doubles the variety for free
//   w   0 = cool grey bark .. 1 = warm brown bark
instance uniform vec4 bark_var = vec4(0.0, 0.0, 0.0, 0.5);
//   overall lightness of this particular tree
instance uniform float bark_value = 1.0;
uniform float bark_var_strength : hint_range(0.0, 1.0) = 1.0;

// --- realistic-pixeled ------------------------------------------------------
// POSTERIZE IS ON VALUE, NOT PER CHANNEL. Quantising r, g and b independently
// wrecks the hue of anything low-saturation: a plain brown bark plate lands on
// (3/7, 3/7, 2/7) and reads olive, its neighbour lands on (2/7, 1/7, 1/7) and
// reads red, and a perfectly good bark sheet turns into confetti. Quantise the
// brightness and carry the hue through untouched.
// cell_m is the size of one bark texel IN METRES. UVs are already metres, so
// this is a straight snap and the density never changes with trunk radius.
uniform float cell_m : hint_range(0.004, 0.08) = 0.028;
// How much of the cell grid actually lands. 1.0 is the hard pixel-art snap the
// first pass shipped; 0.45 keeps the chunky read without turning a detailed
// bark sheet into tiles. This is the dial for "more/less pixelated".
uniform float cell_mix : hint_range(0.0, 1.0) = 0.55;
uniform float posterize : hint_range(2.0, 32.0) = 9.0;
uniform float cell_jitter : hint_range(0.0, 0.5) = 0.06;
uniform float bands : hint_range(2.0, 8.0) = 5.0;
uniform float band_floor : hint_range(0.0, 0.6) = 0.32;   // the shaded side is not dead
uniform float cell_fade_far = 26.0;   // past this the cells dissolve into the mip

// winter frosting on the up-facing side of limbs
uniform vec3 col_snow : source_color = vec3(0.78, 0.82, 0.88);
uniform float snow_amount : hint_range(0.0, 1.0) = 0.6;

// moss on the north side, because a forest without it looks sterile
uniform vec3 col_moss : source_color = vec3(0.16, 0.24, 0.13);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.25;

// Fresh-cut heartwood. TreeV2._carve_notch() writes COLOR.r on every vertex the
// axe moved, so the inside of a notch shows pale wood instead of bark.
uniform vec3 col_heart : source_color = vec3(0.70, 0.58, 0.40);
uniform float heart_rough : hint_range(0.0, 1.0) = 0.72;

global uniform vec3 wind_dir;
global uniform float wind_strength;
global uniform float wind_time;
global uniform float season_phase;

uniform float sway = 0.35;        // trunks barely move; branches are given more

varying vec3 v_world_normal;
varying float v_up;
varying float v_cut;

void vertex() {
	// Sway scales with height off the tree's own origin: the base is planted,
	// the top of the leader is not.
	float stiff = clamp(VERTEX.y * 0.09 + length(VERTEX.xz) * 0.12, 0.0, 1.0);
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = wind_time * 0.9 + world.x * 0.10 + world.z * 0.13;
	float gust = sin(phase) * 0.65 + sin(phase * 0.37 + 2.1) * 0.35;
	vec3 offset = wind_dir * gust * wind_strength * stiff * sway * 0.30;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(offset, 0.0)).xyz;

	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_up = clamp(v_world_normal.y, 0.0, 1.0);
	// INVERTED ON PURPOSE — see the header.
	v_cut = 1.0 - COLOR.r;
}

// Quantise BRIGHTNESS and carry the hue through. See the note at the top.
vec3 posterize_value(vec3 c) {
	float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
	// never let a step land on absolute black: the darkest bark values would
	// quantise to zero and punch holes in the trunk
	float q = max(floor(lum * posterize + 0.5), 1.0) / posterize;
	return c * (q / max(lum, 0.0008));
}

float hash21(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

void fragment() {
	// this tree's own cut of the sheet: mirror, then slide
	vec2 tuv = UV;
	tuv.x = mix(tuv.x, -tuv.x, step(0.5, bark_var.z) * bark_var_strength);
	tuv += bark_var.xy * bark_var_strength;

	vec2 uv = tuv * tiling;
	float dist = length(VERTEX);                 // view space = distance to camera

	// ---- texel cells, sized in metres ------------------------------------
	// Snapping the SAMPLE (not the result) keeps the mip chain honest, so the
	// cells fade out with distance instead of shimmering into aliasing.
	float cells_on = cell_mix * (1.0 - smoothstep(cell_fade_far * 0.6, cell_fade_far, dist));
	vec2 grid = tuv / max(cell_m, 0.001);
	vec2 snapped = (floor(grid) + 0.5) * cell_m * tiling;
	vec2 suv = mix(uv, snapped, cells_on);

	// One flat tone per cell, and it has to be the cell's AVERAGE — a point
	// sample out of a 1024 sheet per 3 cm cell is just noise. Four taps inside
	// the cell rather than a mip, because the bark sheets ship with
	// mipmaps/generate=false and textureLod would quietly do nothing.
	vec2 e = cell_m * tiling * 0.29;
	vec3 col = (texture(bark_albedo, suv + vec2(-e.x, -e.y)).rgb
		+ texture(bark_albedo, suv + vec2(e.x, -e.y)).rgb
		+ texture(bark_albedo, suv + vec2(-e.x, e.y)).rgb
		+ texture(bark_albedo, suv + vec2(e.x, e.y)).rgb) * 0.25;
	col = mix(texture(bark_albedo, uv).rgb, col, cells_on) * tint;

	// this tree's own tone: a stand of maples is not one colour, and the
	// cheapest honest way to say so is warmth and lightness per stem
	col *= mix(vec3(1.0), mix(vec3(0.93, 0.96, 1.05), vec3(1.09, 1.02, 0.92),
		clamp(bark_var.w, 0.0, 1.0)) * bark_value, bark_var_strength);

	// per-cell value jitter, the sprite-noise trick from grass v2.3: one flat
	// tone per cell, but neighbouring cells are never quite the same tone
	float j = (hash21(floor(grid)) - 0.5) * 2.0;
	col *= 1.0 + j * cell_jitter * cells_on;

	// ---- the axe cut: pale wood, no bark ---------------------------------
	// A STEP, not a blend (Lemon 2026-09-14: "no more gradients between bark
	// and not bark"). TreeV2._carve_notch writes 0 or 1 per vertex; the
	// interpolated value crosses 0.5 once along an edge, so the line between
	// bark and cut is a line.
	float cut = step(0.5, v_cut);
	if (cut > 0.5) {
		vec3 grain = texture(bark_albedo, suv * vec2(0.35, 2.2)).rgb;
		col = col_heart * (0.72 + 0.55 * dot(grain, vec3(0.333)));
	}

	// moss: north-facing (−Z), low on the trunk
	float north = clamp(-v_world_normal.z, 0.0, 1.0);
	float low = 1.0 - clamp(UV.y * 0.55, 0.0, 1.0);   // UV.y is metres up the wood, unshifted
	col = mix(col, col_moss, north * low * moss_amount);

	float winter = smoothstep(0.72, 0.94, fract(season_phase));
	col = mix(col, col_snow, winter * v_up * snow_amount);

	// ---- posterize last, so everything above lands on the same palette ----
	col = posterize_value(col);

	ALBEDO = col;
	NORMAL_MAP = texture(bark_normal, mix(uv, suv, cells_on * 0.6)).rgb;
	NORMAL_MAP_DEPTH = normal_scale;
	ROUGHNESS = mix(texture(bark_rough, suv).r, heart_rough, cut);
}

// Four flat diffuse tones and nothing else. Matching grass v2.3's banded
// light() is what stops the trunks reading as a different render to the ground
// they stand in. NOTE: `return` is illegal in here — one branch only.
void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	// wrapped lambert: bark is thick, but a trunk's shadow side should still
	// carry its own form rather than going to flat black
	float w = clamp((ndl + 0.28) / 1.28, 0.0, 1.0);
	float b = floor(w * bands) / max(bands - 1.0, 1.0);
	b = mix(band_floor, 1.0, clamp(b, 0.0, 1.0));
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * b;
}
