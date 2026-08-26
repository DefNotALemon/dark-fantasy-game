shader_type spatial;
// ============================================================================
// PSX Nature & Biomes — foliage cards        (docs/TREES_v3_PSX.md §3)
//
// The pack ships the SAME atlas painted six ways (Spring / Temperate / Autumn /
// Snowy / Dark / Redwood).  So the season system stops being a colour ramp over
// a grayscale sheet and becomes a crossfade between two hand-painted atlases,
// picked off the one global `season_phase` float.  Still zero mesh rebuilds,
// still zero allocations — one extra texture sample.
//
// A region binds its own four stops: temperate woods run
// Spring->Temperate->Autumn->Snowy, a dark stand runs Dark all year with a
// snowy winter, a redwood stand runs Redwood.  That is the whole biome system.
// ============================================================================
render_mode depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// --- the region's four seasonal atlases -------------------------------------
uniform sampler2D atlas_spring : source_color, filter_nearest_mipmap, hint_default_white;
uniform sampler2D atlas_summer : source_color, filter_nearest_mipmap, hint_default_white;
uniform sampler2D atlas_autumn : source_color, filter_nearest_mipmap, hint_default_white;
uniform sampler2D atlas_winter : source_color, filter_nearest_mipmap, hint_default_white;

uniform vec3 tint : source_color = vec3(1.0);
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.45;
uniform float roughness_v : hint_range(0.0, 1.0) = 0.92;
uniform float translucency : hint_range(0.0, 1.0) = 0.22;

// --- the flat "realistic pixeled" light, same language as the ground cover ---
uniform bool flat_light = true;
uniform int light_bands : hint_range(2, 8) = 4;
uniform float band_gain : hint_range(0.5, 2.0) = 1.12;
uniform float wrap_light : hint_range(0.0, 1.0) = 0.55;  // leaves are thin

// --- dead wood ---------------------------------------------------------------
uniform bool dead = false;
uniform vec3 col_dead : source_color = vec3(0.34, 0.26, 0.17);
uniform float dead_cling : hint_range(0.0, 1.0) = 0.30;

// --- shedding: a felled tree throws its leaves on the way down --------------
// 0 = full canopy, 1 = bare.  TreeV2 ramps this over the fall.
uniform float shed : hint_range(0.0, 1.0) = 0.0;

// --- snow ---------------------------------------------------------------------
uniform vec3 col_snow : source_color = vec3(0.80, 0.84, 0.90);
uniform float snow_amount : hint_range(0.0, 1.0) = 0.55;

// --- PSX wobble (off by default; a whole forest of it reads as a bug) --------
uniform float psx_snap : hint_range(0.0, 400.0) = 0.0;

// --- wind: Wind.gd owns the weather, nothing here invents its own breeze -----
global uniform vec3 wind_dir;
global uniform float wind_strength;
global uniform float wind_time;
global uniform float season_phase;
global uniform vec3 player_pos;
global uniform float player_push;

uniform float sway = 1.0;
uniform float push_radius = 1.7;

varying float v_hash;
varying float v_dist;
varying vec3 v_wnormal;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	v_hash = hash13(floor(VERTEX * 6.0) + 0.5);
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Stiffness: the crown moves, the wood it hangs off does not.
	float stiff = clamp(length(VERTEX.xz) * 0.20 + VERTEX.y * 0.06, 0.0, 1.0);

	float phase = wind_time * 1.1 + v_hash * 6.283 + world.x * 0.12 + world.z * 0.15;
	float gust = sin(phase) * 0.6 + sin(phase * 0.41 + 1.7) * 0.4;
	float flutter = sin(phase * 5.1) * 0.22 * wind_strength;
	vec3 offset = wind_dir * (gust + flutter) * wind_strength * stiff * 0.30 * sway;
	offset.y -= abs(gust) * wind_strength * stiff * 0.05;

	vec3 to_player = world - player_pos;
	to_player.y *= 0.5;
	float d = length(to_player);
	if (d < push_radius) {
		float k = 1.0 - d / push_radius;
		offset += normalize(to_player + vec3(0.0001)) * k * k * player_push * 0.5 * stiff;
	}

	VERTEX += (inverse(MODEL_MATRIX) * vec4(offset, 0.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_dist = length((VIEW_MATRIX * vec4(world, 1.0)).xyz);
}

// Hold each season, then turn over the last stretch.  Straight-lerping four
// stops means "summer" exists for one instant of the year — the canopy read
// half-autumn in July the first time this was written.  Don't go back to it.
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

	// Nearest + mipmaps thins alpha with distance and the canopy goes see-through,
	// so the cut relaxes as the tree recedes.
	float cut = mix(alpha_cut, alpha_cut * 0.42, smoothstep(22.0, 80.0, v_dist));

	// A snag keeps only what never fell off it.
	if (dead) cut = mix(cut, 1.02, step(dead_cling, v_hash));
	// A felled tree loses its canopy on the way down, card by card, not all at once.
	if (shed > 0.0) cut = mix(cut, 1.02, step(1.0 - shed, v_hash));

	if (tex.a < cut) discard;

	// MultiMesh instance tint (Understory: how rich/damp/withered this ground
	// is). COLOR is white on any mesh without an instance colour, so this is a
	// no-op for trees.
	vec3 col = tex.rgb * tint * COLOR.rgb;
	if (dead) col = mix(col, col_dead * (0.7 + 0.6 * v_hash), 0.75);

	// Winter frosting on what faces the sky.  The Snowy atlas already carries
	// most of it; this is the bit that follows the actual surface.
	float winter = smoothstep(0.74, 0.93, fract(season_phase))
	             * (1.0 - smoothstep(0.97, 1.0, fract(season_phase)));
	col = mix(col, col_snow, winter * clamp(v_wnormal.y, 0.0, 1.0) * snow_amount);

	ALBEDO = col;
	ROUGHNESS = roughness_v;
	SPECULAR = 0.03;
	BACKLIGHT = vec3(translucency);
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
