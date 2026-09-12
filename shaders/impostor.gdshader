shader_type spatial;
// ============================================================================
// Tree impostors — the distant forest, 2026-09-01
//
// Lemon: "let's do lod textures, make tree blobs (like pictures of the real
// trees and leaves) that can wave around in the distance, and whatever's not
// being rendered isn't being rendered."
//
// This replaces Overworld's faceted CROWN_LOBES bake. Every distant tree is
// ONE quad wearing a PHOTOGRAPH of the real tree — scripts/TreeImpostor.gd
// builds an actual TreeV2, densified canopy and all, in a SubViewport and
// grabs the frame. So the far woods are the near woods: same kit geometry,
// same bark, same leaf atlas, same season ramp, two triangles.
//
// Why a photo works where leaf cards did not (Overworld §"THE CROWN IS A
// BLOB"): the old impostor hung crossed quads UV'd across the whole leaf
// atlas, which is ~66% clear texels, so the mipmaps averaged alpha under the
// cut and the trees dissolved into bare sticks. An impostor's alpha is one
// big tree-shaped silhouette. It survives every mip.
//
// It is a Y-BILLBOARD: it turns to face you but never tips over, so it still
// reads as a standing tree from a ridge. Two triangles, no shadow, no shadow
// receive, and the wind moves it — a still forest next to a moving one is the
// thing that gives an impostor away at any distance.
// ============================================================================
render_mode depth_draw_opaque, cull_disabled, diffuse_burley, specular_disabled,
	shadows_disabled;

uniform sampler2D albedo : source_color, filter_linear_mipmap;
// The silhouette is a whole tree, not a leaf, so the cut can sit low without
// the mips eating it. Too high and the crown edge frays as it recedes.
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.30;
// The quad's own height in model metres. The sway is expressed as a fraction
// of it, so a 20 m pine and a 7 m maple lean by the same amount of THEMSELVES.
uniform float quad_h = 10.0;
uniform float sway = 1.0;
uniform float lean = 0.075;      // crown travel, as a fraction of quad_h

// matched to foliage.gdshader so the far woods and the near woods shade alike
uniform float bands : hint_range(2.0, 8.0) = 5.0;
uniform float band_floor : hint_range(0.0, 0.6) = 0.32;

global uniform vec3 wind_dir;
global uniform float wind_strength;
global uniform float wind_time;

varying float v_hash;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	// per-instance scale, recovered from the columns — overriding
	// MODELVIEW_MATRIX below throws the instance basis away, and the scatter
	// puts real size variation in there (LOD_SCALE_MIN..MAX, and elders)
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	v_hash = fract(sin(dot(origin.xz, vec2(12.9898, 78.233))) * 43758.5453);

	// --- Y-billboard: yaw to the camera, stay upright ----------------------
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	right.y = 0.0;
	right = normalize(right + vec3(0.0001, 0.0, 0.0));
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 fwd = cross(right, up);

	// --- the wave ----------------------------------------------------------
	// Same idea as foliage.gdshader's canopy wave, one octave: the phase comes
	// from the DOWNWIND coordinate, so a gust travels across the distant
	// forest instead of every tree bobbing on its own clock. The base is
	// nailed down (k = 0 at the ground) and the crown does the moving.
	vec3 local = VERTEX;
	float k = clamp(local.y / max(quad_h, 0.001), 0.0, 1.0);
	k *= k;
	vec3 wd = normalize(wind_dir + vec3(0.001, 0.0, 0.0));
	float w = clamp(wind_strength, 0.0, 1.2);
	float phase = dot(origin, wd) * 0.055 - wind_time * 0.85 + v_hash * 6.283;
	float amt = sin(phase) * 0.70 + sin(phase * 0.53 + 1.3) * 0.30;
	// the lean lives in the billboard's own horizontal axis, projected off the
	// wind, so a crosswind rocks the tree and a headwind barely does
	local.x += amt * k * sway * dot(wd, right) * quad_h * lean * (0.25 + 0.75 * w);

	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(right * sx, 0.0),
		vec4(up * sy, 0.0),
		vec4(fwd * sx, 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	VERTEX = local;
	// Tilted off the quad's face toward the sky: a flat camera-facing normal
	// makes the whole forest ignore the sun's elevation and stay bright at
	// dusk. This is the one lighting cue an impostor gets, so it should be
	// the right one.
	NORMAL = normalize(vec3(0.0, 0.55, 1.0));
}

void fragment() {
	vec4 t = texture(albedo, UV);
	if (t.a < alpha_cut) discard;
	ALBEDO = t.rgb;
	ROUGHNESS = 1.0;
}

// The same banded light() the bark, the grass and the leaves use, so the far
// woods sit in one picture with the near ones. `return` is illegal in here.
void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	float lam = max(ndl, 0.0) + max(-ndl, 0.0) * 0.35;
	float b = floor(clamp(lam, 0.0, 1.0) * bands) / max(bands - 1.0, 1.0);
	b = mix(band_floor, 1.0, clamp(b, 0.0, 1.0));
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * b;
}
