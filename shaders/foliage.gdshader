shader_type spatial;
// ============================================================================
// Leaf cards — The Withering / Myrkfell trees v2  (docs/TREES_v2_SPEC.md §6-§7)
//
// One shader for every species. What varies per species lives in the four
// season colours and the atlas; what varies per SEASON is a single global
// float. No mesh is ever rebuilt to change the time of year.
//
// The atlas is authored GRAYSCALE (tools/leafgen.py) — colour comes from the
// ramp below, which is why one texture covers all four seasons.
//
// TWO MATERIAL VARIANTS ride this one shader (TreeV2.materials_for):
//   animated = 1  — the canopy's outer shell: full Ghost-of-Tsushima wind.
//   animated = 0  — the inner filler pads: NO per-vertex wind at all, they
//                   ride their branch rigidly. That skip is what pays for the
//                   dense canopy (Lemon 2026-08-29: outer layers animated,
//                   inner layers sway with the branch, so it runs better).
//   shade < 1     — inner pads sit in their own shadow.
// ============================================================================
// Cutout by discard, not by alpha blending: leaves stay in the OPAQUE pass,
// so they sort correctly, cast real shadows, and cost nothing to sort.
render_mode depth_draw_opaque, cull_disabled, diffuse_burley, specular_disabled;

uniform sampler2D leaf_atlas : source_color, filter_linear_mipmap, hint_default_white;
uniform sampler2D leaf_normal : hint_normal, filter_linear_mipmap;

// --- seasonal colour: spring / summer / autumn / winter ---------------------
uniform vec3 col_spring : source_color = vec3(0.44, 0.56, 0.26);
uniform vec3 col_summer : source_color = vec3(0.24, 0.36, 0.18);
uniform vec3 col_autumn : source_color = vec3(0.86, 0.34, 0.09);
uniform vec3 col_winter : source_color = vec3(0.40, 0.22, 0.14);
uniform vec3 col_snow   : source_color = vec3(0.78, 0.82, 0.88);

uniform bool deciduous = true;
// A dead tree: bare but for a scatter of brown leaves that never fell.
uniform bool dead = false;
uniform vec3 col_dead : source_color = vec3(0.31, 0.23, 0.14);
uniform float dead_cling : hint_range(0.0, 1.0) = 0.09;
// share of dead leaves that cling all winter — oak marcescence, spec §3
uniform float marcescence : hint_range(0.0, 1.0) = 0.0;
uniform float autumn_hue_jitter : hint_range(0.0, 1.0) = 0.35;
uniform float snow_amount : hint_range(0.0, 1.0) = 1.0;

uniform float alpha_cut : hint_range(0.0, 1.0) = 0.42;
uniform float translucency : hint_range(0.0, 1.0) = 0.25;
uniform float roughness_v : hint_range(0.0, 1.0) = 0.78;

// --- the canopy-layer switches (see header) ---------------------------------
uniform float animated : hint_range(0.0, 1.0) = 1.0;
uniform float shade : hint_range(0.0, 1.5) = 1.0;

// --- wind (Wind.gd publishes these for every foliage shader) ----------------
global uniform vec3 wind_dir;        // normalised, world space
global uniform float wind_strength;  // 0 calm .. 1 gale
global uniform float wind_time;      // seconds, monotonic
global uniform float season_phase;   // 0..1 = one full year, 0 = start of spring
global uniform vec3 player_pos;
global uniform float player_push;    // 0 when still, up to 1 when moving/swinging

uniform float sway = 1.0;            // per-species multiplier
uniform float push_radius = 1.6;

// --- realistic-pixeled (trees v4, 2026-08-30) -------------------------------
// The same three moves as grass v2.3 and shaders/bark.gdshader, so the canopy,
// the trunk, the blades and the creatures all sit in ONE picture:
//   * the atlas UV is snapped to a texel grid — atlas_texels is a multiple of
//     4, so the snap never crosses a 0.25 cell boundary and one leaf cell can
//     never bleed into its neighbour
//   * the palette is posterized
//   * light() is four flat diffuse tones with no specular
// --- per-TREE, set by TreeV2._seed_bark_look() ------------------------------
// One canopy is not the next one's colour. x = lightness, y = 0 cool .. 1 warm.
// An instance uniform is patched per draw call, so this costs no extra material
// and no extra draw call — 420 trees still share one leaf material per species.
instance uniform vec2 leaf_var = vec2(1.0, 0.5);

uniform float atlas_texels : hint_range(32.0, 512.0) = 192.0;
// posterize 7 was the FIRST-PASS value, from before Lemon's "less pixelated,
// more bark-like" note; bark.gdshader was moved to 16 that day and the canopy
// was missed. At 7 the whole thing collapses: a fir leaf texel is grey
// 0.45-0.62, the summer ramp is luma 0.21, so every texel on every fir lands
// in luma bucket 1 and gets normalised to exactly 1/7 -- one flat colour
// across the entire crown. 16 gives the canopy its tones back.
uniform float posterize : hint_range(2.0, 32.0) = 16.0;
// five light bands with a lower floor, matching bark.gdshader, so the crown
// has some depth in it instead of two shades of green
uniform float bands : hint_range(2.0, 8.0) = 5.0;
uniform float band_floor : hint_range(0.0, 0.6) = 0.32;
uniform float cell_fade_far = 34.0;

varying float v_season;
varying float v_hash;
varying vec3 v_world_normal;

// cheap per-instance-ish hash from object space so neighbouring cards differ
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	v_hash = hash13(floor(VERTEX * 7.0) + 0.5);
	v_season = season_phase;

	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Stiffness: leaves at the outside of the crown move, the trunk does not.
	float stiff = clamp(length(VERTEX.xz) * 0.22 + VERTEX.y * 0.10, 0.0, 1.0);

	vec3 offset = vec3(0.0);

	// ---- Ghost-of-Tsushima wind (outer shell only — animated = 1) ----------
	// Coherent waves TRAVEL downwind through the whole forest (phase from the
	// downwind coordinate), so a gust visibly rolls across the canopy from
	// tree to tree and never stops moving. Per-card randomness is kept small
	// in the wave and lives in the fast flutter instead. Pace HALVED
	// 2026-08-29 ("make the tsushima leaves slower") — same travel, same
	// amplitude, lazier tempo.
	if (animated > 0.5) {
		vec3 wdir = normalize(wind_dir + vec3(0.001, 0.0, 0.0));
		float w = clamp(wind_strength, 0.0, 1.2);

		float along = dot(world, wdir);
		float phase = along * 0.42 - wind_time * 1.7 + v_hash * 1.1;
		float wave = sin(phase) * 0.55
			+ sin(phase * 0.47 + 1.7) * 0.30
			+ sin(phase * 2.31 + v_hash * 2.0) * 0.15;

		// the crown holds a bow away from the wind, and streams harder in gusts
		float lean = 0.08 + 0.22 * w;
		float amp = 0.08 + 0.34 * w;

		// slow per-leaf flutter — always alive, even in the lull between gusts
		float fl = sin(wind_time * (4.6 + v_hash * 3.2) + v_hash * 37.0 + along * 1.3)
			* (0.05 + 0.16 * w);

		vec3 side = vec3(-wdir.z, 0.0, wdir.x);
		offset = wdir * (lean + wave * amp) * stiff * sway;
		offset += side * (wave * 0.35 + fl) * amp * stiff * sway;
		offset.y -= (abs(wave) * 0.22 + max(wave, 0.0) * 0.14) * amp * stiff; // gusts press the canopy down
		offset.y += fl * 0.45 * stiff * sway;                                  // and the leaves kick
	}

	// the player shoving through: branches part around you (both layers —
	// stealth and walking through a bush must read on the inner leaves too)
	vec3 to_player = world - player_pos;
	to_player.y *= 0.5;
	float d = length(to_player);
	if (d < push_radius) {
		float k = (1.0 - d / push_radius);
		offset += normalize(to_player + vec3(0.001)) * k * k * player_push * 0.55 * stiff;
	}

	VERTEX += (inverse(MODEL_MATRIX) * vec4(offset, 0.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// season_phase 0..1 -> the four stops, wrapping through winter back to spring
vec3 season_colour(float p, float jitter) {
	// Hold each season, then turn. Straight lerping between the four stops
	// means "summer" exists for one instant of the year and everything else is
	// a crossfade — the canopy read half-autumn in July.
	float t = fract(p) * 4.0;
	int i = int(floor(t));
	float f = smoothstep(0.55, 1.0, fract(t));
	vec3 a = col_spring;
	vec3 b = col_summer;
	if (i == 1) { a = col_summer; b = col_autumn; }
	else if (i == 2) { a = col_autumn; b = col_winter; }
	else if (i == 3) { a = col_winter; b = col_spring; }
	vec3 c = mix(a, b, f);
	// a real maple is orange AND red AND still-green at once
	if (i == 1 || i == 2) {
		c = mix(c, c.bgr * vec3(1.15, 0.75, 0.6), jitter * autumn_hue_jitter);
	}
	return c;
}

void fragment() {
	// snap into the atlas texel grid — chunky leaf edges are the point, and
	// the cut below then reads as pixel-art alpha rather than a soft matte
	float cells_on = 1.0 - smoothstep(cell_fade_far * 0.6, cell_fade_far, length(VERTEX));
	vec2 suv = mix(UV, (floor(UV * atlas_texels) + 0.5) / atlas_texels, cells_on);
	vec4 tex = texture(leaf_atlas, suv);

	// ---- defoliation: raise the cut per card, scattered, late in the year ----
	// This is the whole trick from spec §7 — leaves leave by threshold, not by
	// rebuilding a mesh, so autumn costs exactly nothing.
	float cut = alpha_cut;
	if (dead) {
		// nothing regrows on a snag; only what is still stuck to it stays
		cut = mix(alpha_cut, 1.02, step(dead_cling, v_hash));
	} else if (deciduous) {
		float fall = smoothstep(0.62, 0.86, fract(v_season));   // late autumn -> winter
		float regrow = 1.0 - smoothstep(0.02, 0.16, fract(v_season)); // spring flush
		float bare = max(fall, regrow);
		float clings = step(1.0 - marcescence, v_hash);          // this card holds on
		cut = mix(alpha_cut, 1.02, bare * (1.0 - clings));
	}
	if (tex.a < cut) discard;

	vec3 col = (dead ? col_dead * (0.75 + 0.5 * v_hash) : season_colour(v_season, v_hash)) * tex.rgb;
	col *= shade;   // inner filler pads sit in their own shadow
	// and this tree's own canopy tone
	col *= leaf_var.x * mix(vec3(0.94, 1.00, 1.06), vec3(1.08, 1.02, 0.90),
		clamp(leaf_var.y, 0.0, 1.0));

	// ---- snow: winter, and only on faces looking at the sky ----
	float winter = smoothstep(0.72, 0.92, fract(v_season)) * (1.0 - smoothstep(0.96, 1.0, fract(v_season)));
	float up = clamp(v_world_normal.y, 0.0, 1.0);
	col = mix(col, col_snow, winter * up * snow_amount * 0.7);

	// Posterize last, so ramp, jitter, shade and snow all land on one palette —
	// and posterize on VALUE, never per channel: quantising r, g and b apart
	// pulls a dark green leaf onto a different hue entirely.
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col *= (max(floor(lum * posterize + 0.5), 1.0) / posterize) / max(lum, 0.0008);

	ALBEDO = col;
	NORMAL_MAP = texture(leaf_normal, suv).rgb;
	ROUGHNESS = roughness_v;
}

// Four flat diffuse tones, no specular — the same banded light() the bark and
// the grass use. The sun-through-the-leaf term is folded in by hand here:
// BACKLIGHT is a built-in-lighting feature and a custom light() never sees it.
// NOTE: `return` is illegal in here — one branch only (trees-v3 §3).
void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	// A leaf is THIN: it lights from both sides. The far side comes through
	// dimmer, which is the sun-through-the-canopy read, and it is why this is
	// not just a clamped lambert. (BACKLIGHT is a built-in-lighting feature; a
	// custom light() never sees it, so the term is folded in here by hand.)
	float lam = max(ndl, 0.0) + max(-ndl, 0.0) * (0.30 + translucency);
	float b = floor(clamp(lam, 0.0, 1.0) * bands) / max(bands - 1.0, 1.0);
	b = mix(band_floor, 1.0, clamp(b, 0.0, 1.0));
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * b;
}
