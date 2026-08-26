// =============================================================================
// Myrkfell sky — shaders/sky.gdshader
// Custom sky: day / pink dusk / night gradient, sun disc + scatter glow,
// clouds (toggle: off / painterly layers / volumetric raymarch), stars,
// northern lights, storm gloom, lightning flash.
//
// Driven by scripts/Sky.gd (sun + wind) and scripts/Weather.gd (weather).
// Reads the sun straight from LIGHT0 (the DirectionalLight3D), so dusk
// happens wherever the sun actually is — no script has to tell it.
//
// Godot 4.7, Forward+. Set the Sky resource to PROCESS_MODE_INCREMENTAL
// (Sky.gd does this) so the animated radiance doesn't re-render every frame.
// =============================================================================
shader_type sky;
render_mode use_debanding;

group_uniforms sky_colors;
uniform vec3 day_top : source_color = vec3(0.235, 0.416, 0.700);
uniform vec3 day_horizon : source_color = vec3(0.640, 0.752, 0.870);
uniform vec3 dusk_top : source_color = vec3(0.280, 0.196, 0.420);
uniform vec3 dusk_horizon : source_color = vec3(1.000, 0.480, 0.585); // the pink
uniform vec3 dusk_glow : source_color = vec3(1.000, 0.560, 0.450);    // sun-side bloom
uniform vec3 night_top : source_color = vec3(0.012, 0.018, 0.048);
uniform vec3 night_horizon : source_color = vec3(0.045, 0.058, 0.110);
uniform vec3 ground_color : source_color = vec3(0.120, 0.115, 0.110);
group_uniforms;

group_uniforms sun;
// Direction TOWARD the sun. SkyRig.gd feeds this from the DirectionalLight3D's
// basis.z every frame; left at zero it falls back to LIGHT0 so the sky still
// looks right in the editor with nothing running.
uniform vec3 sun_dir_override = vec3(0.0, 0.0, 0.0);
uniform vec3 sun_color_day : source_color = vec3(1.000, 0.975, 0.930);
uniform vec3 sun_color_dusk : source_color = vec3(1.000, 0.400, 0.300);
uniform float sun_size : hint_range(0.005, 0.1) = 0.024;   // angular radius, radians
uniform float sun_softness : hint_range(0.0, 2.0) = 0.35;
uniform float sun_energy : hint_range(0.0, 32.0) = 9.0;
group_uniforms;

group_uniforms clouds;
// 0 = off, 1 = painterly layers (cheap), 2 = volumetric raymarch (pretty, pricier)
uniform int cloud_mode : hint_enum("Off", "Painterly", "Volumetric") = 1;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.42;
uniform float cloud_softness : hint_range(0.01, 0.5) = 0.16;
uniform float cloud_scale : hint_range(0.2, 6.0) = 1.35;
uniform float cloud_opacity : hint_range(0.0, 1.0) = 1.0;
uniform float cloud_darkness : hint_range(0.0, 1.0) = 0.0; // Weather: storm bottoms
uniform vec2 cloud_wind = vec2(0.008, 0.003);              // Sky.gd feeds Wind.gd into this
group_uniforms;

group_uniforms volumetric_clouds;
uniform float vol_base : hint_range(200.0, 4000.0) = 900.0;    // slab bottom, meters
uniform float vol_thick : hint_range(200.0, 4000.0) = 950.0;   // slab thickness
uniform float vol_density : hint_range(0.1, 4.0) = 1.0;
uniform float vol_freq : hint_range(0.0002, 0.004) = 0.0008;   // cloud size: bigger = smaller puffs
uniform float vol_far : hint_range(4000.0, 40000.0) = 16000.0; // stop marching out here
uniform float vol_brightness : hint_range(0.1, 2.0) = 0.72;
group_uniforms;

group_uniforms night_sky;
uniform float star_density : hint_range(0.0, 0.5) = 0.10;
uniform float star_brightness : hint_range(0.0, 4.0) = 1.1;
uniform vec3 aurora_color_a : source_color = vec3(0.10, 0.95, 0.45); // green
uniform vec3 aurora_color_b : source_color = vec3(0.45, 0.18, 0.90); // violet
uniform float aurora_strength : hint_range(0.0, 1.0) = 0.0; // Weather.gd rolls this nightly
uniform float aurora_speed : hint_range(0.0, 3.0) = 0.7;
group_uniforms;

group_uniforms weather;
uniform float storm_gloom : hint_range(0.0, 1.0) = 0.0; // desaturate + darken everything
uniform float lightning : hint_range(0.0, 1.0) = 0.0;   // Weather.gd pulses this
group_uniforms;

// ---------------------------------------------------------------- noise ------
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
	float n = hash21(p);
	return vec2(n, hash21(p + n + 17.17));
}

float hash31(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y);
}

float fbm2(vec2 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 6; i++) {
		if (i >= octaves) { break; }
		v += a * vnoise2(p);
		p = p * 2.17 + vec2(11.31, 7.77);
		a *= 0.5;
	}
	return v;
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(i);
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, u.x);
	float nx10 = mix(n010, n110, u.x);
	float nx01 = mix(n001, n101, u.x);
	float nx11 = mix(n011, n111, u.x);
	return mix(mix(nx00, nx10, u.y), mix(nx01, nx11, u.y), u.z);
}

// Volumetric cloud density at a world-ish point. drift is in uv units.
// `t` is TIME, passed in: sky shaders only expose TIME inside sky(), and
// touching it from a helper is a compile error, not a warning.
float cloud_density(vec3 p, vec2 drift, float cov, int oct, float t) {
	float h01 = clamp((p.y - vol_base) / max(vol_thick, 1.0), 0.0, 1.0);
	float prof = smoothstep(0.0, 0.22, h01) * (1.0 - smoothstep(0.55, 1.0, h01));
	if (prof <= 0.0) { return 0.0; }
	vec2 uv = p.xz * vol_freq + drift;
	float base = fbm2(uv, oct);
	float detail = vnoise3(vec3(p.x, p.y * 1.7, p.z) * vol_freq * 3.4
		+ vec3(drift.x * 4.0, t * 0.01, drift.y * 4.0));
	// Erode the base shape with the detail rather than adding to it — adding
	// just raises the average and the deck turns into fog.
	float n = base - (1.0 - detail) * 0.22;
	return smoothstep(cov, cov + 0.20, n) * prof * vol_density;
}

// ------------------------------------------------------------------ sky ------
void sky() {
	vec3 dir = EYEDIR;
	vec3 sun_dir = normalize(vec3(0.42, 0.10, 0.35)); // editor default: low sun, pink hour
	if (length(sun_dir_override) > 0.001) {
		sun_dir = normalize(sun_dir_override);
	} else if (LIGHT0_ENABLED) {
		sun_dir = LIGHT0_DIRECTION;
	}
	float sun_h = sun_dir.y;

	// Time-of-day factors, straight from the sun's own elevation.
	float day = smoothstep(-0.03, 0.25, sun_h);
	float dusk = 1.0 - smoothstep(0.10, 0.35, abs(sun_h)); // peaks with the sun on the horizon
	float night = 1.0 - smoothstep(-0.16, -0.01, sun_h);

	// --- base gradient -------------------------------------------------------
	float up = clamp(dir.y, 0.0, 1.0);
	float horizon_t = pow(1.0 - up, 3.0);
	vec3 day_col = mix(day_top, day_horizon, horizon_t);
	vec3 night_col = mix(night_top, night_horizon, horizon_t);
	vec3 col = mix(night_col, day_col, day);

	// The pink hour: wash the sky toward the dusk ramp, strongest low and
	// on the sun's side, plus a warm scatter bloom around the sun itself.
	float sun_dot = clamp(dot(dir, sun_dir), -1.0, 1.0);
	float toward_sun = pow(clamp(sun_dot, 0.0, 1.0), 2.0) * 0.65 + 0.35;
	vec3 dusk_col = mix(dusk_top, dusk_horizon, horizon_t);
	col = mix(col, dusk_col, dusk * (0.25 + 0.75 * horizon_t) * toward_sun);
	col += dusk_glow * pow(clamp(sun_dot, 0.0, 1.0), 5.0) * dusk * 0.8;
	col += vec3(1.0, 0.95, 0.85) * pow(clamp(sun_dot, 0.0, 1.0), 48.0) * day * 0.28;

	// Storm gloom: pull toward a dead slate gray and drop exposure.
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum) * vec3(0.55, 0.62, 0.72), storm_gloom * 0.85);
	col *= 1.0 - storm_gloom * 0.50;

	// --- sun disc ------------------------------------------------------------
	float cs = cos(sun_size);
	float cs_soft = cos(sun_size * (1.0 + sun_softness));
	float disc = smoothstep(cs_soft, cs, sun_dot);
	float sun_vis = smoothstep(-0.06, 0.02, sun_h) * (1.0 - storm_gloom * 0.9);
	vec3 sun_col = mix(sun_color_day, sun_color_dusk, dusk);
	col += sun_col * disc * sun_vis * sun_energy * (AT_CUBEMAP_PASS ? 0.35 : 1.0);

	// --- clouds (computed first so stars/aurora can hide behind them) --------
	float cm = 0.0;             // cloud alpha
	vec3 cloud_col = vec3(0.0); // cloud color
	vec2 drift = cloud_wind * TIME;

	if (cloud_mode == 1 && dir.y > 0.0) {
		// Painterly: two scrolling fbm layers projected on a dome.
		vec2 cuv = dir.xz / (dir.y + 0.18) * cloud_scale;
		int oct = AT_CUBEMAP_PASS ? 3 : 5;
		float n1 = fbm2(cuv + drift, oct);
		float n2 = fbm2(cuv * 2.6 - drift * 1.6 + vec2(37.0, 11.0), max(oct - 1, 2));
		float n = n1 * 0.62 + n2 * 0.38;
		float cov = mix(0.72, 0.18, cloud_coverage);
		cm = smoothstep(cov, cov + cloud_softness, n);
		cm *= smoothstep(0.0, 0.08, dir.y); // fade into the horizon haze
		cm *= cloud_opacity;

		// Cheap directional light: resample shifted toward the sun; where
		// density falls off sunward, that's a lit edge — the silver lining.
		vec2 sun_flat = normalize(sun_dir.xz + vec2(0.0001, 0.0));
		float n_lit = fbm2(cuv + drift - sun_flat * 0.14, oct);
		float rim = clamp((n - n_lit) * 3.0, 0.0, 1.0);
		float thick = smoothstep(cov, cov + 0.35, n);

		vec3 lit = mix(vec3(1.02, 1.00, 0.98), dusk_horizon * 1.15, dusk); // sunset catches the tops
		lit = mix(lit, vec3(0.30, 0.34, 0.45), night * 0.9);
		vec3 shade = mix(vec3(0.62, 0.66, 0.75), vec3(0.15, 0.16, 0.21),
			max(cloud_darkness, night * 0.85));
		shade = mix(shade, dusk_horizon * 0.45, dusk * 0.5 * (1.0 - cloud_darkness));

		cloud_col = mix(lit, shade, thick * (0.55 + 0.45 * cloud_darkness));
		cloud_col += lit * rim * (0.5 + 0.6 * dusk) * (1.0 - cloud_darkness);
		cloud_col *= 0.25 + 0.75 * day + 0.20 * dusk;
		cloud_col += vec3(0.75, 0.82, 1.00) * lightning * (0.18 + 0.35 * thick);
	} else if (cloud_mode == 2 && dir.y > 0.015) {
		// Volumetric-lite: march a slab of noise between vol_base and the top
		// of the deck, gathering light as we go. Near the horizon that slab is
		// enormously long, so the march is clamped at vol_far — past that the
		// deck is a smear anyway and the extra steps buy nothing.
		float t0 = vol_base / max(dir.y, 0.02);
		float t1 = min((vol_base + vol_thick) / max(dir.y, 0.02), vol_far);
		if (t1 > t0) {
			int steps = AT_CUBEMAP_PASS ? 8 : 20;
			int oct = AT_CUBEMAP_PASS ? 2 : 4;
			float dt = (t1 - t0) / float(steps);
			float cov = mix(0.74, 0.20, cloud_coverage);
			// Jitter the first step per pixel. Without this a 20-step march
			// bands into visible slabs — you see the sampling, not the cloud.
			t0 += dt * hash21(SCREEN_UV * 1024.0);

			// Light reaching a cloud: the sun through the deck, plus sky from
			// every other direction. Storm bellies get much less of both.
			vec3 sun_col2 = mix(vec3(1.00, 0.97, 0.90), dusk_horizon * 1.25, dusk);
			sun_col2 = mix(sun_col2, vec3(0.09, 0.11, 0.17), night * 0.92);
			sun_col2 *= mix(1.0, 0.28, cloud_darkness);
			vec3 ambient = mix(day_horizon * 0.55, night_top * 2.2, night);
			ambient = mix(ambient, dusk_horizon * 0.45, dusk * 0.6);
			ambient *= mix(1.0, 0.30, cloud_darkness);

			float trans = 1.0;
			vec3 acc = vec3(0.0);
			for (int i = 0; i < 22; i++) {
				if (i >= steps) { break; }
				vec3 p = dir * (t0 + (float(i) + 0.5) * dt);
				float dns = cloud_density(p, drift, cov, oct, TIME);
				if (dns > 0.001) {
					// Two shadow taps toward the sun. This is the whole reason
					// to march at all — it's what gives a cloud a bright top
					// and a dark underside instead of a flat white blob.
					float shadow =
						cloud_density(p + sun_dir * 180.0, drift, cov, 2, TIME) * 180.0
						+ cloud_density(p + sun_dir * 430.0, drift, cov, 2, TIME) * 250.0;
					float li = exp(-shadow * 0.010);
					// A little forward scatter so the rim facing the sun glows.
					float ph = 0.45 + 0.55 * pow(clamp(dot(dir, sun_dir), 0.0, 1.0), 3.0);
					vec3 c = ambient + sun_col2 * li * ph;
					c += vec3(0.75, 0.82, 1.00) * lightning * (0.3 + 0.4 * dns);
					float a = 1.0 - exp(-dns * dt * 0.0055);
					acc += trans * a * c;
					trans *= 1.0 - a;
					if (trans < 0.02) { break; }
				}
			}
			cm = (1.0 - trans) * smoothstep(0.015, 0.07, dir.y) * cloud_opacity;
			cloud_col = acc / max(1.0 - trans, 0.0001) * vol_brightness;
		}
	}

	// --- stars ---------------------------------------------------------------
	if (!AT_CUBEMAP_PASS && night > 0.001 && dir.y > 0.0) {
		vec2 suv = vec2(atan(dir.x, dir.z), acos(clamp(dir.y, -1.0, 1.0))) * 40.0;
		vec2 cell = floor(suv);
		vec2 cf = fract(suv) - 0.5;
		vec2 off = (hash22(cell) - 0.5) * 0.7;
		float h = hash21(cell + 7.31);
		float star = smoothstep(0.12, 0.02, length(cf - off)) * step(1.0 - star_density, h);
		float tw = 0.6 + 0.4 * sin(TIME * (1.5 + 4.0 * h) + h * 31.4);
		col += vec3(0.90, 0.95, 1.00) * star * star_brightness * tw * night
			* (1.0 - cm) * (1.0 - storm_gloom) * clamp(dir.y * 4.0 + 0.2, 0.0, 1.0);
	}

	// --- northern lights -----------------------------------------------------
	// Weather.gd rolls aurora_strength up on lucky clear nights.
	if (!AT_CUBEMAP_PASS && aurora_strength > 0.001 && night > 0.01 && dir.y > 0.02) {
		vec2 auv = dir.xz / (dir.y + 0.4);
		float t = TIME * aurora_speed;
		float glow = 0.0;
		for (int i = 0; i < 3; i++) {
			float fi = float(i);
			float y = auv.y * (1.6 + fi * 0.7) + fi * 2.3;
			float wave = fbm2(vec2(auv.x * (0.9 + fi * 0.35) + t * (0.05 + 0.04 * fi),
				t * 0.03 + fi * 9.0), 4);
			float d = abs(y - (wave * 2.4 - 1.2));
			glow += smoothstep(0.55, 0.0, d) * (0.5 - fi * 0.12);
		}
		glow *= 0.6 + 0.4 * vnoise2(vec2(auv.x * 14.0, t * 0.7)); // vertical ray shimmer
		float hue = vnoise2(auv * 1.7 + t * 0.05);
		vec3 acol = mix(aurora_color_a, aurora_color_b,
			smoothstep(0.35, 0.75, hue + (1.0 - dir.y) * 0.2));
		float band = smoothstep(0.02, 0.18, dir.y) * (1.0 - smoothstep(0.55, 0.95, dir.y));
		col += acol * glow * aurora_strength * night * band * (1.0 - cm) * 1.4;
	}

	// --- composite -----------------------------------------------------------
	col = mix(col, cloud_col, cm);
	col += vec3(0.55, 0.60, 0.75) * lightning * 0.10; // the whole sky blinks

	// Below the horizon: settle to a sane ground color so the radiance/ambient
	// the sky feeds the scene doesn't glow from underneath.
	float below = smoothstep(0.0, 0.12, -dir.y);
	vec3 ground = ground_color * (0.15 + 0.85 * day + 0.3 * dusk);
	col = mix(col, ground, below);

	COLOR = col;
}
