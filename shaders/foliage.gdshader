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
// ============================================================================
// Cutout by discard, not by alpha blending: leaves stay in the OPAQUE pass,
// so they sort correctly, cast real shadows, and cost nothing to sort.
render_mode depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

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

// --- wind (Wind.gd publishes these for every foliage shader) ----------------
global uniform vec3 wind_dir;        // normalised, world space
global uniform float wind_strength;  // 0 calm .. 1 gale
global uniform float wind_time;      // seconds, monotonic
global uniform float season_phase;   // 0..1 = one full year, 0 = start of spring
global uniform vec3 player_pos;
global uniform float player_push;    // 0 when still, up to 1 when moving/swinging

uniform float sway = 1.0;            // per-species multiplier
uniform float push_radius = 1.6;

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
	// Baking this into COLOR.r is better (spec §6) — until the exporter does,
	// height above the tree origin plus distance out is a good stand-in.
	float stiff = clamp(length(VERTEX.xz) * 0.22 + VERTEX.y * 0.10, 0.0, 1.0);

	// gust: two detuned waves so it never reads as a loop, plus a fast flutter
	float phase = wind_time * 1.1 + v_hash * 6.283 + world.x * 0.12 + world.z * 0.15;
	float gust = sin(phase) * 0.6 + sin(phase * 0.41 + 1.7) * 0.4;
	float flutter = sin(phase * 5.3) * 0.25 * wind_strength;
	vec3 offset = wind_dir * (gust + flutter) * wind_strength * stiff * 0.35 * sway;
	offset.y -= abs(gust) * wind_strength * stiff * 0.06;   // wind presses down too

	// the player shoving through: branches part around you
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
	vec4 tex = texture(leaf_atlas, UV);

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

	// ---- snow: winter, and only on faces looking at the sky ----
	float winter = smoothstep(0.72, 0.92, fract(v_season)) * (1.0 - smoothstep(0.96, 1.0, fract(v_season)));
	float up = clamp(v_world_normal.y, 0.0, 1.0);
	col = mix(col, col_snow, winter * up * snow_amount * 0.7);

	ALBEDO = col;
	NORMAL_MAP = texture(leaf_normal, UV).rgb;
	ROUGHNESS = roughness_v;
	SPECULAR = 0.2;
	BACKLIGHT = vec3(translucency);   // thin leaves glow when the sun is behind
}
