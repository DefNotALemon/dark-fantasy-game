shader_type spatial;
// ============================================================================
// PSX OUTLINE — the white selection rim the Character Creator draws around a
// character you clicked (Lemon, 2026-09-14: "click on any character which
// will outline them with white for selection").
//
// An inverted hull: the creature's own skinned mesh drawn a second time,
// front faces culled, every vertex pushed out along its normal by `width`
// metres, unlit, in one flat colour. From outside you see only the rim the
// hull sticks out past the real skin. It reads the same 128x2 segment
// texture the skin does, so a segment the skin hides (a stowed tool, gear
// that is off) leaves no ghost rim behind.
// ============================================================================
render_mode cull_front, unshaded, depth_draw_opaque;

uniform sampler2D seg_tex : filter_nearest, repeat_disable;
uniform vec4 colour : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float width = 0.035;

varying float v_alpha;

void vertex() {
	int seg = int(UV2.x + 0.5);
	v_alpha = texelFetch(seg_tex, ivec2(seg, 0), 0).a;
	VERTEX += NORMAL * width;
}

void fragment() {
	if (v_alpha < 0.5) {
		discard;
	}
	ALBEDO = colour.rgb;
	EMISSION = colour.rgb * 0.6;
}
