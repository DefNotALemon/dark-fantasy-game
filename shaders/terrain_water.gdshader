shader_type spatial;
// ============================================================================
// Lakes and the sea, v2 — Myrkfell / The Withering  (scripts/Overworld.gd)
//
// Flat water in the game's pixel language, now with real DEPTH:
//   * the depth buffer says how much water the eye's ray passes through
//     before it hits the bed -- the first half metre shows the bed through
//     the ripple cells, and the tone closes to `deep_col` by ~murk_depth
//     (a Maine lake is tea over sand and black-green three metres down; the
//     Gulf is slate and takes longer);
//   * a FOAM line where the depth goes to nothing -- the shore, a rock, a
//     swimmer's chest -- broken up by the same cells so it is not a contour;
//   * Fresnel: at a grazing angle the surface is the SKY (sky_col, fed by
//     World from the day/night clock), straight down it is the water;
//   * REFRACTION: the bed seen through the surface is the screen behind us,
//     nudged per ripple cell, so it swims the way a pebble bed does. That is
//     the one screen read this shader makes; `refract_on` (Settings -> Water
//     Refraction) turns it off and the water falls back to plain blending.
// Still no reflections of geometry, no normal maps, no tessellation: this
// covers a quarter of a 78 km2 map and has to stay nearly free.
//
// From UNDER the surface (FRONT_FACING false) it is a dim mirror with no
// foam; the underwater look itself (fog, tint, muffled sound) is World's and
// the Player's, not the plane's.
// ============================================================================
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_disabled;

uniform vec3 shallow_col : source_color = vec3(0.30, 0.30, 0.16);   // tea over sand
uniform vec3 deep_col : source_color = vec3(0.06, 0.10, 0.07);      // black-green
uniform vec3 sky_col : source_color = vec3(0.55, 0.68, 0.85);
uniform vec3 foam_col : source_color = vec3(0.74, 0.80, 0.80);
uniform float murk_depth = 5.5;            // metres of water until it is opaque
uniform float foam_depth = 0.10;           // metres of water under which it foams
uniform float min_alpha : hint_range(0.0, 1.0) = 0.22;   // over a bed you can just see
uniform float cell = 0.75;                 // metres per ripple texel
uniform float ripple : hint_range(0.0, 0.4) = 0.12;
uniform float refract_px : hint_range(0.0, 0.05) = 0.010;  // screen-space nudge per cell
uniform bool refract_on = true;
uniform float posterize : hint_range(2.0, 32.0) = 6.0;
uniform float bands : hint_range(2.0, 8.0) = 4.0;
uniform float band_floor : hint_range(0.0, 0.8) = 0.55;
uniform float detail_fade_far = 260.0;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

global uniform vec3 wind_dir;
global uniform float wind_time;
global uniform float wind_strength;

varying vec3 v_world;

float hash21(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

// View-space distance to whatever the depth buffer holds under this pixel.
float scene_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv * 2.0 - 1.0, d * 2.0 - 1.0);
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return -v.z / v.w;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dist = length(VERTEX);
	float cells_on = 1.0 - smoothstep(detail_fade_far * 0.5, detail_fade_far, dist);

	// --- ripples: two cell grids sliding downwind at different paces -------
	vec2 w = normalize(wind_dir.xz + vec2(0.001, 0.0));
	float sp = 0.25 + 0.6 * clamp(wind_strength, 0.0, 1.0);
	vec2 p1 = v_world.xz - w * wind_time * sp;
	vec2 p2 = v_world.xz * 0.5 + w * wind_time * sp * 0.4;
	float r1 = hash21(floor(p1 / cell));
	float r2 = hash21(floor(p2 / cell) + 3.0);
	float r = r1 * 0.6 + r2 * 0.4;

	// --- how much water is under this pixel ---------------------------------
	// The depth buffer holds the opaque scene (the bed, a rock, a swimmer);
	// the difference to our own depth is the water the ray crossed. Scaled by
	// the view's tilt it is close to the vertical depth, which is what murk
	// and foam are about.
	float here = -VERTEX.z;
	float behind = scene_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float thick = max(behind - here, 0.0);
	float vdepth = thick * max(abs(VIEW.y), 0.12);
	float murk = 1.0 - exp(-vdepth / max(murk_depth, 0.1));      // 0 at the shore, 1 deep
	float far_deep = smoothstep(20.0, 120.0, dist);              // far off it reads deep anyway
	murk = max(murk, far_deep * 0.85);

	// --- the water's own colour, in the pixel language ----------------------
	vec3 col = mix(shallow_col, deep_col, murk);
	col *= 1.0 + (r - 0.5) * 2.0 * ripple * cells_on;
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col *= (max(floor(lum * posterize + 0.5), 1.0) / posterize) / max(lum, 0.0008);

	// --- Fresnel: the sky lies on the water at a grazing angle -------------
	vec3 n = FRONT_FACING ? NORMAL : -NORMAL;
	float cosv = clamp(dot(normalize(n), normalize(VIEW)), 0.0, 1.0);
	float fres = pow(1.0 - cosv, 4.0);
	fres = floor(fres * 4.0 + 0.5) / 4.0;                          // banded, like everything else
	col = mix(col, sky_col, fres * 0.75);

	// --- foam where the water runs out ------------------------------------
	// A WASH, not a sheet: on a 1:40 beach a depth test alone paints twenty
	// metres of sea white. So the line is thin (foam_depth is centimetres),
	// it breathes in and out with the wind clock, and it is never solid --
	// the cells leave dark water between the streaks.
	float wash = sin(wind_time * 1.3 + v_world.x * 0.21 + v_world.z * 0.17) * 0.35 * foam_depth;
	float foam = 1.0 - smoothstep(0.0, foam_depth, vdepth + (r2 - 0.5) * foam_depth * 0.9 + wash);
	foam *= 0.28 + 0.37 * step(0.45, r1);
	// a few loose streaks a little further out
	float foam2 = (1.0 - smoothstep(foam_depth, foam_depth * 2.5, vdepth)) * step(0.80, r1) * 0.30;
	foam = max(foam, foam2) * float(FRONT_FACING) * cells_on;

	// --- composite -----------------------------------------------------------
	float a = mix(min_alpha, 0.97, murk);
	a = max(a, fres * 0.9);
	if (!FRONT_FACING) {
		// from below: a dark mirror, almost opaque, no foam
		col = mix(deep_col, col, 0.35);
		a = 0.92;
	}
	a = clamp(max(a, foam), 0.0, 1.0);
	if (refract_on && FRONT_FACING) {
		// the bed, seen through the surface: the screen behind us, nudged per
		// cell. The nudge shrinks with depth (deep water shows no bed) and with
		// distance (a far shore must not smear). The bed pixels were lit once
		// already, so they pass through as EMISSION (unlit) while the water's
		// own share of the pixel takes the banded light() like everything else.
		vec2 nudge = (vec2(r1, r2) - 0.5) * refract_px * (1.0 - murk) * cells_on;
		vec3 bed = texture(screen_tex, clamp(SCREEN_UV + nudge, vec2(0.001), vec2(0.999))).rgb;
		ALBEDO = mix(col * a, foam_col, foam);
		EMISSION = bed * (1.0 - a) * (1.0 - foam);
		ALPHA = 1.0;
	} else {
		ALBEDO = mix(col, foam_col, foam);
		ALPHA = a;
	}
	ROUGHNESS = 0.2;
}

void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	float b = floor(clamp(abs(ndl), 0.0, 1.0) * bands) / max(bands - 1.0, 1.0);
	b = mix(band_floor, 1.0, clamp(b, 0.0, 1.0));
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * b;
}
