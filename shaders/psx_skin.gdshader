shader_type spatial;
// ============================================================================
// PSX SKIN — the one material every creature in Myrkfell wears.
//
// A CreatureSkin bakes a creature's box rig into ONE skinned mesh; this shader
// gives that mesh the PlayStation look the rest of the "realistic pixeled"
// art direction (Grass v2.3) already speaks:
//   * vertices SNAP to a coarse screen grid (the PS1 had no sub-pixel
//     precision, which is where the wobble comes from),
//   * textures are mapped AFFINE (no perspective correction — the swim),
//   * light is BANDED into flat tones, no specular smear,
//   * colours are POSTERIZED to a shared palette,
//   * transparency is a SCREEN-DOOR dither, never a blend.
//
// THE PROXIMITY EASE (psx_near / psx_far): every one of those artefacts is a
// look for a creature you are LOOKING AT, not one you are standing under. At
// arm's length the snap grid chews the silhouette into blocks and the affine
// swim drags the coat texture around in wedges — which is what "the horse goes
// pixelated while it's still close" was. So the whole PS1 stack now fades in
// with distance: off inside psx_near metres, full strength past psx_far. Set
// psx_near = psx_far = 0.0 to get the old always-on behaviour back.
//
// Per-segment colour, emission, metal and visibility come from a 128x2 data
// texture the CreatureSkin keeps in sync with the ORIGINAL box materials, so
// every hit flash, coat swap, eyeshine, buff glow and armour tint the game
// already writes keeps working without knowing the boxes are gone.
//   row 0: albedo rgb + alpha (0 = the source box is hidden)
//   row 1: emission rgb (colour x energy) + metallic in .a
// UV2.x = segment index, UV2.y = pattern tile (4x4 atlas in pattern_tex).
// ============================================================================
render_mode cull_back, depth_draw_opaque, diffuse_lambert, specular_disabled;

uniform sampler2D seg_tex : filter_nearest, repeat_disable;
// The same atlas twice: hard texels for the PS1 read, a filtered tap for the
// close-up end of the ease. CreatureSkin binds both to PsxTex.atlas().
uniform sampler2D pattern_tex : source_color, filter_nearest, repeat_enable;
uniform sampler2D pattern_soft : source_color, filter_linear, repeat_enable;
uniform vec2 snap_res = vec2(426.0, 240.0);   // the grid vertices snap to
uniform float snap_amount : hint_range(0.0, 1.0) = 1.0;
uniform float psx_near = 3.0;   // metres: inside this the creature is clean
uniform float psx_far = 11.0;   // metres: past this the full PS1 look
uniform float palette_steps = 12.0;
uniform float tex_strength : hint_range(0.0, 1.0) = 1.0;
uniform float ghost : hint_range(0.0, 1.0) = 1.0;  // whole-creature fade (corpses)
uniform float flash = 0.0;                          // whole-creature white flash

varying vec3 v_uvw;    // affine (UV * w, w)
varying vec2 v_uv;     // the honest, perspective-correct UV
varying vec4 v_col;
varying vec4 v_emis;
varying float v_tile;
varying float v_alpha;
varying float v_psx;   // 0 = up close and clean, 1 = full PlayStation

void vertex() {
	int seg = int(UV2.x + 0.5);
	v_col = texelFetch(seg_tex, ivec2(seg, 0), 0);
	v_emis = texelFetch(seg_tex, ivec2(seg, 1), 0);
	v_tile = UV2.y;
	v_alpha = v_col.a * ghost;

	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float dist = -view.z;                       // metres in front of the camera
	v_psx = (psx_far > psx_near)
		? smoothstep(psx_near, psx_far, dist)
		: 1.0;

	vec4 clip = PROJECTION_MATRIX * view;
	float amt = snap_amount * v_psx;
	if (amt > 0.0 && clip.w > 0.0) {
		vec2 g = snap_res * 0.5;
		vec2 ndc = clip.xy / clip.w;
		vec2 snapped = floor(ndc * g + 0.5) / g;
		clip.xy = mix(ndc, snapped, amt) * clip.w;
	}
	POSITION = clip;
	// UV * w interpolated perspective-correctly and divided by interpolated w
	// comes out SCREEN-linear: that is the affine swim, on purpose. v_uv is the
	// same coordinate WITHOUT the trick, so the fragment can cross-fade out of
	// the swim as the creature comes near.
	v_uvw = vec3(UV * clip.w, clip.w);
	v_uv = UV;
}

float bayer4(vec2 px) {
	// 4x4 ordered dither, 0..1
	int x = int(mod(px.x, 4.0));
	int y = int(mod(px.y, 4.0));
	int idx = x + y * 4;
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[idx]) + 0.5) / 16.0;
}

void fragment() {
	if (v_alpha < 0.999) {
		if (v_alpha < 0.01 || v_alpha < bayer4(floor(FRAGCOORD.xy))) {
			discard;
		}
	}
	float psx = clamp(v_psx, 0.0, 1.0);
	vec2 uv_aff = v_uvw.xy / max(v_uvw.z, 0.0001);
	vec2 uv = mix(v_uv, uv_aff, psx);
	float tile = v_tile;
	vec2 cell = vec2(mod(tile, 4.0), floor(tile / 4.0));
	vec2 f = fract(uv);
	vec2 tuv = (cell + f) * 0.25;
	// The filtered tap is inset half a texel so it cannot bleed across the
	// atlas cell border (64 px tiles in a 256 px atlas).
	vec2 tuv_soft = (cell + clamp(f, vec2(0.5 / 64.0), vec2(1.0 - 0.5 / 64.0))) * 0.25;
	vec3 pat = mix(texture(pattern_soft, tuv_soft).rgb, texture(pattern_tex, tuv).rgb, psx);
	vec3 col = v_col.rgb * mix(vec3(1.0), pat, tex_strength);
	col = mix(col, vec3(1.0), flash);
	col = floor(col * palette_steps + 0.5) / palette_steps;
	ALBEDO = col;
	EMISSION = v_emis.rgb + vec3(flash) * 2.0;
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	// BANDED LIGHT — four flat tones with hard edges, the same steps the grass
	// uses, so a deer standing in the meadow is lit by the same sun.
	float nl = dot(NORMAL, LIGHT);
	float band;
	if (nl > 0.55) band = 1.0;
	else if (nl > 0.18) band = 0.72;
	else if (nl > -0.12) band = 0.45;
	else band = 0.26;
	// metal (armour, blades): one extra glint band where the light is square on
	float metal = v_emis.a;
	band += metal * 0.45 * step(0.80, nl);
	DIFFUSE_LIGHT += LIGHT_COLOR * ALBEDO * band * ATTENUATION / PI;
}
