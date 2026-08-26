shader_type spatial;
// ============================================================================
// Bark — The Withering / Myrkfell trees v2  (docs/TREES_v2_SPEC.md §3, §17)
//
// Stylised albedo (plates readable at ten metres) + a detailed normal map, AND
// parallax occlusion mapping so the fissures have real DEPTH when you walk up
// to a trunk — crevices that occlude each other and slide correctly as you move
// past, not a flat picture of bark.
//
// POM is the expensive bit, so it fades out with distance: full stepping under
// `pom_near` metres, tapering to nothing by `pom_far`, where the normal map
// alone is doing a fine job anyway. A forest of 250 trees pays for parallax on
// the two or three you are standing next to.
//
// Textures come from tools/barkgen.py and tile in both axes; trunk UVs run
// u = around the trunk, v = up it.
// ============================================================================
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D bark_albedo : source_color, filter_linear_mipmap;
uniform sampler2D bark_normal : hint_normal, filter_linear_mipmap;
uniform sampler2D bark_rough : hint_default_white, filter_linear_mipmap;
uniform sampler2D bark_height : hint_default_black, filter_linear_mipmap;

uniform vec2 tiling = vec2(2.0, 1.0);
uniform float normal_scale : hint_range(0.0, 3.0) = 1.05;
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);

// --- parallax occlusion -----------------------------------------------------
uniform float pom_depth : hint_range(0.0, 0.14) = 0.035;  // metres of apparent relief
uniform int pom_min_steps : hint_range(4, 32) = 8;
uniform int pom_max_steps : hint_range(8, 64) = 28;
uniform float pom_near = 3.0;    // full-strength stepping closer than this
uniform float pom_far = 14.0;    // no parallax at all past this
uniform bool pom_shadow = true;  // crevices shade themselves from the key light

// winter frosting on the up-facing side of limbs
uniform vec3 col_snow : source_color = vec3(0.78, 0.82, 0.88);
uniform float snow_amount : hint_range(0.0, 1.0) = 0.6;

// moss on the north side, because a forest without it looks sterile
uniform vec3 col_moss : source_color = vec3(0.16, 0.24, 0.13);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.25;

// Fresh-cut heartwood. TreeV2._carve_notch() writes COLOR.r on every vertex the
// axe moved, so the inside of a notch shows pale wood instead of bark.
uniform vec3 col_heart : source_color = vec3(0.62, 0.47, 0.27);
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
	// INVERTED ON PURPOSE: a mesh with no vertex-colour array gives COLOR = white,
	// so "1 = cut" painted every branch in the forest pale yellow. White now
	// means untouched bark, and the carve writes values BELOW 1.
	v_cut = 1.0 - COLOR.r;
}

// Steep parallax + occlusion: march the view ray through the height field until
// it goes under the surface, then interpolate the crossing. `strength` fades the
// whole effect with distance.
vec2 parallax(vec2 uv, vec3 view_ts, float strength, out float depth_out) {
	depth_out = 0.0;
	if (strength <= 0.001) {
		return uv;
	}
	float steps = mix(float(pom_min_steps), float(pom_max_steps),
			clamp(1.0 - abs(view_ts.z), 0.0, 1.0));
	steps = max(steps * strength, 4.0);
	float layer = 1.0 / steps;
	// grazing angles need the ray to travel further per layer
	vec2 shift = view_ts.xy / max(abs(view_ts.z), 0.35) * pom_depth * strength;
	vec2 duv = shift * layer;

	float cur_layer = 0.0;
	vec2 cur_uv = uv;
	float cur_h = 1.0 - texture(bark_height, cur_uv).r;
	for (int i = 0; i < 64; i++) {
		if (cur_layer >= cur_h || float(i) >= steps) {
			break;
		}
		cur_uv -= duv;
		cur_h = 1.0 - texture(bark_height, cur_uv).r;
		cur_layer += layer;
	}
	// one bisection step back for a clean crossing instead of a stair edge
	vec2 prev_uv = cur_uv + duv;
	float after = cur_h - cur_layer;
	float before = (1.0 - texture(bark_height, prev_uv).r) - (cur_layer - layer);
	float w = after / max(after - before, 0.0001);
	depth_out = cur_layer;
	return mix(cur_uv, prev_uv, w);
}

void fragment() {
	// view direction in tangent space — TANGENT/BINORMAL/NORMAL and VIEW are
	// all view-space here, so the dots give a correct tangent-space ray
	vec3 view_ts = normalize(vec3(dot(VIEW, TANGENT), dot(VIEW, BINORMAL), dot(VIEW, NORMAL)));

	float dist = length(VERTEX);              // view-space position = distance to camera
	float strength = (1.0 - smoothstep(pom_near, pom_far, dist)) * (1.0 - smoothstep(0.02, 0.5, v_cut));

	float depth_hit;
	vec2 uv = parallax(UV * tiling, view_ts, strength, depth_hit);

	vec3 col = texture(bark_albedo, uv).rgb * tint;

	// crevice self-shadowing: the deeper the hit, the less key light reaches it
	if (pom_shadow) {
		col *= mix(1.0, clamp(1.0 - depth_hit * 1.15, 0.35, 1.0), strength);
	}

	// ---- the axe cut: pale wood, no bark, and no parallax in the wound ----
	if (v_cut > 0.01) {
		vec3 grain = texture(bark_albedo, UV * tiling * vec2(0.35, 2.2)).rgb;
		vec3 heart = col_heart * (0.72 + 0.55 * dot(grain, vec3(0.333)));
		float k = smoothstep(0.02, 0.55, v_cut);
		col = mix(col, heart, k);
	}

	// moss: north-facing (−Z), low on the trunk
	float north = clamp(-v_world_normal.z, 0.0, 1.0);
	float low = 1.0 - clamp(UV.y * 1.6, 0.0, 1.0);
	col = mix(col, col_moss, north * low * moss_amount);

	float winter = smoothstep(0.72, 0.94, fract(season_phase));
	col = mix(col, col_snow, winter * v_up * snow_amount);

	ALBEDO = col;
	NORMAL_MAP = texture(bark_normal, uv).rgb;
	NORMAL_MAP_DEPTH = normal_scale;
	ROUGHNESS = mix(texture(bark_rough, uv).r, heart_rough, smoothstep(0.02, 0.55, v_cut));
	SPECULAR = 0.15;
}
