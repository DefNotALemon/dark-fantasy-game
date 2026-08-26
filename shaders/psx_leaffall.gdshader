shader_type spatial;
// ============================================================================
// Leaves coming off a tree that is going over.   (docs/TREES_v3_PSX.md §5)
//
// The cards are lifted straight out of the tree's own canopy mesh, so they
// carry the pack's real leaf UVs and recolour with the season like everything
// else. Each card knows its own centre (CUSTOM0.xyz) and its own seed
// (CUSTOM0.w); the whole burst is one mesh, one draw call, and every leaf
// falls, drifts and spins entirely in the vertex shader off a single float.
// ============================================================================
render_mode depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D atlas_spring : source_color, filter_nearest_mipmap, hint_default_white;
uniform sampler2D atlas_summer : source_color, filter_nearest_mipmap, hint_default_white;
uniform sampler2D atlas_autumn : source_color, filter_nearest_mipmap, hint_default_white;
uniform sampler2D atlas_winter : source_color, filter_nearest_mipmap, hint_default_white;

uniform float fall_t : hint_range(0.0, 1.0) = 0.0;   // 0 = still on the tree
uniform float fall_dist = 9.0;                        // how far they get to drop
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.45;
uniform vec3 tint : source_color = vec3(1.0);

global uniform vec3 wind_dir;
global uniform float wind_strength;
global uniform float season_phase;

varying float v_fade;

void vertex() {
	vec3 centre = CUSTOM0.xyz;
	float seed = CUSTOM0.w;

	// Leaves let go at slightly different moments, so the canopy empties over
	// the fall rather than detaching in one sheet.
	float t = clamp((fall_t - seed * 0.35) / 0.65, 0.0, 1.0);
	float e = t * t;                       // gravity, near enough

	// Down, plus the sideways wander a leaf does on the way, plus the wind
	// carrying the whole lot downrange.
	float sway = sin(seed * 31.7 + t * 11.0) * 0.9 * t;
	vec3 drift = vec3(cos(seed * 17.3), 0.0, sin(seed * 17.3)) * (sway + t * 1.2);
	drift += wind_dir * (wind_strength * t * 3.4);
	vec3 move = vec3(0.0, -fall_dist * e, 0.0) + drift;

	// Tumble about its own centre.
	float a = t * (5.0 + seed * 7.0);
	float ca = cos(a); float sa = sin(a);
	vec3 rel = VERTEX - centre;
	rel = vec3(rel.x * ca - rel.z * sa, rel.y * ca + rel.x * sa * 0.4, rel.z * ca + rel.x * sa);

	VERTEX = centre + rel + move;
	v_fade = 1.0 - smoothstep(0.72, 1.0, t);
}

vec4 season_atlas(vec2 uv) {
	float s = fract(season_phase) * 4.0;
	int i = int(floor(s));
	float f = smoothstep(0.55, 1.0, fract(s));
	vec4 a = texture(atlas_spring, uv);
	vec4 b = texture(atlas_summer, uv);
	if (i == 1) { a = texture(atlas_summer, uv); b = texture(atlas_autumn, uv); }
	else if (i == 2) { a = texture(atlas_autumn, uv); b = texture(atlas_winter, uv); }
	else if (i == 3) { a = texture(atlas_winter, uv); b = texture(atlas_spring, uv); }
	return mix(a, b, f);
}

void fragment() {
	vec4 tex = season_atlas(UV);
	if (tex.a < alpha_cut || v_fade < 0.02) discard;
	ALBEDO = tex.rgb * tint;
	ROUGHNESS = 0.92;
	SPECULAR = 0.03;
	BACKLIGHT = vec3(0.25);
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
}
