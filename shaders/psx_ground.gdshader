shader_type spatial;
// ============================================================================
// The ground, in the pack's own dirt.        (docs/TREES_v3_PSX.md §7)
//
// The world surface is the top skin of the map-wide CaveRegion, meshed by
// CaveMesher with flat per-face VERTEX COLOURS and no UVs at all. So this
// shader is triplanar: it projects the pack's ForestFloor / Soil / RockGround
// sheets onto that mesh by world position, picks between them by how flat the
// face is and how deep it lies, and keeps the mesher's vertex colour as a HUE
// TINT so the strata still cool to frost and warm to ember down in the deeps.
//
// Two reasons this matters: with the procedural blades gone (Understory.gd)
// the floor has to carry itself, and a textured floor is what makes the ferns
// standing in it read as a forest instead of as props on a green slab.
// ============================================================================
render_mode depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D floor_warm : source_color, filter_nearest_mipmap, hint_default_white;
uniform sampler2D floor_cold : source_color, filter_nearest_mipmap, hint_default_white;
uniform sampler2D soil_tex   : source_color, filter_nearest_mipmap, hint_default_white;
uniform sampler2D rock_tex   : source_color, filter_nearest_mipmap, hint_default_white;

uniform float tiling = 0.42;              // texture repeats per metre
uniform float rock_tiling = 0.30;
uniform float tint_strength : hint_range(0.0, 1.0) = 0.55;
uniform float surface_depth = 1.6;        // below this the floor gives way to soil

uniform bool flat_light = true;
uniform int light_bands : hint_range(2, 8) = 4;
uniform float band_gain : hint_range(0.5, 2.0) = 1.10;
uniform float wrap_light : hint_range(0.0, 1.0) = 0.12;

uniform vec3 col_snow : source_color = vec3(0.82, 0.86, 0.92);
uniform float snow_amount : hint_range(0.0, 1.0) = 0.7;

global uniform float season_phase;

varying vec3 v_world;
varying vec3 v_wnormal;
varying vec3 v_tint;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// CaveMesher writes its palette straight into VERTEX colour, already in
	// LINEAR space (see its srgb_to_linear note). Normalise it to a hue so the
	// texture keeps its own brightness and only picks up the strata's colour.
	float l = max(max(COLOR.r, max(COLOR.g, COLOR.b)), 0.001);
	v_tint = COLOR.rgb / l;
}

vec3 tri(sampler2D t, vec3 p, vec3 n, float sc) {
	vec3 b = abs(n);
	b = b / max(b.x + b.y + b.z, 0.001);
	vec3 x = texture(t, p.zy * sc).rgb;
	vec3 y = texture(t, p.xz * sc).rgb;
	vec3 z = texture(t, p.xy * sc).rgb;
	return x * b.x + y * b.y + z * b.z;
}

void fragment() {
	vec3 n = normalize(v_wnormal);
	float up = clamp(n.y, 0.0, 1.0);

	// Winter swaps the forest floor for the snowy sheet; the pack painted it,
	// so there is nothing to invent here.
	float winter = smoothstep(0.74, 0.93, fract(season_phase))
	             * (1.0 - smoothstep(0.97, 1.0, fract(season_phase)));
	vec3 fl = mix(texture(floor_warm, v_world.xz * tiling).rgb,
	              texture(floor_cold, v_world.xz * tiling).rgb, winter);
	vec3 so = tri(soil_tex, v_world, n, tiling);
	vec3 ro = tri(rock_tex, v_world, n, rock_tiling);

	// Flat and near the surface = forest floor. Tilting = bare soil. Steep or
	// deep = the rock the whole map is carved out of.
	float deep = smoothstep(0.0, surface_depth, -v_world.y);
	float flatness = smoothstep(0.30, 0.72, up);
	vec3 c = mix(ro, so, flatness);
	c = mix(c, fl, flatness * (1.0 - deep));

	c *= mix(vec3(1.0), v_tint, tint_strength);
	c = mix(c, col_snow, winter * up * snow_amount * (1.0 - deep) * 0.55);

	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.02;
}

void light() {
	float ndl = dot(normalize(NORMAL), LIGHT);
	float lit = max(ndl, 0.0);
	if (flat_light) {
		float w = clamp((ndl + wrap_light) / (1.0 + wrap_light), 0.0, 1.0);
		float nb = float(light_bands);
		lit = clamp(floor(w * nb) / max(nb - 1.0, 1.0), 0.0, 1.0) * band_gain;
	}
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * lit;
}
