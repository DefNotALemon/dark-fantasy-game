shader_type spatial;
// ============================================================================
// PSX Nature & Biomes — trunks, limbs, logs, stumps, rocks, twigs
//                                            (docs/TREES_v3_PSX.md §3)
//
// Same four-atlas season crossfade as psx_foliage, minus the wind and the
// defoliation, plus the axe wound.
//
// THE CUT FLAG IS INVERTED, ON PURPOSE.  A mesh with no vertex-colour array
// reports COLOR = white, so "1 = cut" painted every trunk in the forest bright
// heartwood the first time this was written.  White means untouched bark and
// the carve writes values BELOW 1.  If you add a mesh here, that convention is
// load-bearing.
// ============================================================================
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D atlas_spring : source_color, filter_nearest_mipmap, hint_default_white;
uniform sampler2D atlas_summer : source_color, filter_nearest_mipmap, hint_default_white;
uniform sampler2D atlas_autumn : source_color, filter_nearest_mipmap, hint_default_white;
uniform sampler2D atlas_winter : source_color, filter_nearest_mipmap, hint_default_white;

uniform vec3 tint : source_color = vec3(1.0);
uniform float roughness_v : hint_range(0.0, 1.0) = 0.95;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.35;

uniform bool flat_light = true;
uniform int light_bands : hint_range(2, 8) = 4;
uniform float band_gain : hint_range(0.5, 2.0) = 1.12;
uniform float wrap_light : hint_range(0.0, 1.0) = 0.18;

// --- the wound ---------------------------------------------------------------
uniform vec3 col_heart : source_color = vec3(0.62, 0.47, 0.28);
uniform float heart_rough : hint_range(0.0, 1.0) = 0.72;

// --- dead wood ---------------------------------------------------------------
uniform bool dead = false;
uniform vec3 col_dead : source_color = vec3(0.52, 0.50, 0.46);

uniform vec3 col_snow : source_color = vec3(0.80, 0.84, 0.90);
uniform float snow_amount : hint_range(0.0, 1.0) = 0.45;

global uniform float season_phase;

varying vec3 v_wnormal;
varying float v_cut;

void vertex() {
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_cut = 1.0 - clamp(COLOR.r, 0.0, 1.0);   // see the header: white = untouched
}

vec4 season_atlas(vec2 uv) {
	float t = fract(season_phase) * 4.0;
	int i = int(floor(t));
	float f = smoothstep(0.55, 1.0, fract(t));
	vec4 a = texture(atlas_spring, uv);
	vec4 b = texture(atlas_summer, uv);
	if (i == 1) { a = texture(atlas_summer, uv); b = texture(atlas_autumn, uv); }
	else if (i == 2) { a = texture(atlas_autumn, uv); b = texture(atlas_winter, uv); }
	else if (i == 3) { a = texture(atlas_winter, uv); b = texture(atlas_spring, uv); }
	return mix(a, b, f);
}

void fragment() {
	vec4 tex = season_atlas(UV);
	if (tex.a < alpha_cut) discard;

	vec3 col = tex.rgb * tint;
	if (dead) col = mix(col, col_dead * (0.62 + 0.5 * tex.r), 0.62);

	// Bark stops at the cut: a saw face is pale, flat and rougher.
	float cut = smoothstep(0.15, 0.55, v_cut);
	col = mix(col, col_heart, cut);

	float winter = smoothstep(0.74, 0.93, fract(season_phase))
	             * (1.0 - smoothstep(0.97, 1.0, fract(season_phase)));
	col = mix(col, col_snow, winter * clamp(v_wnormal.y, 0.0, 1.0) * snow_amount * (1.0 - cut));

	ALBEDO = col;
	ROUGHNESS = mix(roughness_v, heart_rough, cut);
	SPECULAR = 0.04;
}

void light() {
	// NOTE: `return` is illegal inside light() in Godot -- the whole body has to
	// be one branch, not an early bail.
	float ndl = dot(normalize(NORMAL), LIGHT);
	float lit = max(ndl, 0.0);
	if (flat_light) {
		// Four flat tones and no specular -- the banded read the ground cover
		// uses, so wood, leaf and floor all sit in one picture.
		float w = clamp((ndl + wrap_light) / (1.0 + wrap_light), 0.0, 1.0);
		float n = float(light_bands);
		lit = clamp(floor(w * n) / max(n - 1.0, 1.0), 0.0, 1.0) * band_gain;
	}
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * lit;
}
