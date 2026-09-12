shader_type spatial;
// ===========================================================================
// GROWTH — what creeps over a trunk, a boulder, a cave mouth (GrowthPatch.gd)
//
// One patch is ONE mesh of little cards in two LAYERS:
//   layer 0, the BASE   — flush films/cushions hugging the surface (moss sheet,
//                         mycelium web, ivy film, lichen crust)
//   layer 1, the ACCENT — chunkier things standing proud of it (bracket fungi,
//                         toadstools, hanging vine strands, beard lichen)
// Every card carries its own BIRTH threshold (0..1). The patch's `growth`
// instance uniform sweeps 0 -> 1 over game time and each card fades and swells
// in as the front passes it, so the patch spreads outward from its heart and
// the accents arrive once the base is established. Nothing is rebuilt: growth
// is one float patched per draw call.
//
// Vertex contract (GrowthPatch._card):
//   CUSTOM0.xyz = the card's pivot (patch-local)   CUSTOM0.w = birth
//   UV          = atlas tile                        UV2.x = hang (0 top .. 1 tip)
//   UV2.y       = layer (0 base / 1 accent)          COLOR.rgb = per-card shade
//
// Rendering matches bark/foliage: banded diffuse, no specular, posterize on
// VALUE (never per channel — that is the confetti bug from trees v4).
// ===========================================================================
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap, hint_default_white;
uniform float bands : hint_range(2.0, 8.0) = 5.0;
uniform float band_floor : hint_range(0.0, 0.6) = 0.42;
uniform float posterize : hint_range(2.0, 32.0) = 16.0;
uniform float sway = 0.035;

// per PATCH, patched per draw call — one material serves every patch
instance uniform float growth : hint_range(0.0, 1.0) = 1.0;
instance uniform vec3 tint_base : source_color = vec3(1.0);
instance uniform vec3 tint_accent : source_color = vec3(1.0);
// how see-through each layer is at full growth ("slightly transparent")
instance uniform vec2 opacity = vec2(0.82, 0.92);
instance uniform float wet = 0.0;     // rain darkens and glosses it a touch

varying float v_reveal;
varying float v_layer;

void vertex() {
	float birth = CUSTOM0.w;
	float layer = UV2.y;
	// a base card fades in over a wider window than an accent (a film creeps,
	// a mushroom pops)
	float win = mix(0.22, 0.10, layer);
	float reveal = smoothstep(birth, birth + win, growth);
	v_reveal = reveal;
	v_layer = layer;
	// swell in around the pivot: a new card starts as a speck
	vec3 pivot = CUSTOM0.xyz;
	float sc = mix(0.30, 1.0, reveal);
	VERTEX = pivot + (VERTEX - pivot) * sc;
	// hanging strands (vines, beard lichen) drift in the air. hang is 0 at the
	// root, 1 at the tip, so the root stays put and the tip wanders.
	float hang = UV2.x;
	if (hang > 0.001) {
		float ph = pivot.x * 3.1 + pivot.y * 1.7 + pivot.z * 2.3;
		float h2 = hang * hang * sc;
		VERTEX.x += sin(TIME * 1.30 + ph) * sway * h2;
		VERTEX.z += cos(TIME * 1.05 + ph * 1.3) * sway * 0.7 * h2;
	}
}

void fragment() {
	vec4 t = texture(atlas, UV);
	vec3 tint = mix(tint_base, tint_accent, v_layer);
	vec3 col = t.rgb * tint * COLOR.rgb;
	// rain: darker, a touch bluer, like everything wet
	col *= mix(1.0, 0.72, wet * 0.8);
	// posterize on VALUE, carrying the hue through
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col *= (max(floor(lum * posterize + 0.5), 1.0) / posterize) / max(lum, 0.0008);
	float op = mix(opacity.x, opacity.y, v_layer);
	float a = t.a * v_reveal * op;
	if (a < 0.02) {
		discard;
	}
	ALBEDO = col;
	ALPHA = a;
	ROUGHNESS = mix(1.0, 0.55, wet);
}

// Flat banded tones, matching bark.gdshader — one branch only, no `return`.
void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	// moss is a soft mat: wrap the lambert so its shadow side keeps some form
	float w = clamp((ndl + 0.42) / 1.42, 0.0, 1.0);
	float b = floor(w * bands) / max(bands - 1.0, 1.0);
	b = mix(band_floor, 1.0, clamp(b, 0.0, 1.0));
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * b;
}
