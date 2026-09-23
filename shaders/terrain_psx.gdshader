shader_type spatial;
// ============================================================================
// The overworld ground — Myrkfell / The Withering  (scripts/Overworld.gd)
//
// The heightfield carries ONE colour per vertex, sampled from the painted
// ground map (assets/terrain/maine_color.png). This shader turns that flat
// tint into ground in the game's "realistic pixeled" language — the same
// three moves grass v2.3, the bark and the leaves make, so the floor sits in
// the same picture as everything standing on it:
//   * world-space texel CELLS: a hash per 0.5 m cell jitters the tone, so a
//     meadow is a field of flat pixels rather than a smooth gradient;
//   * the palette is posterized on VALUE (never per channel — that turns a
//     dull green into confetti);
//   * light() is four flat diffuse tones, no specular.
// Plus what a heightfield can tell about itself: steep faces turn to rock,
// the metre above the waterline is sand.
//
// COLOR arrives as the PNG's sRGB bytes. Rendered raw it is pastel — a dark
// forest green read as mint in the first live build — so it is linearised
// here, exactly as StandardMaterial3D.vertex_color_is_srgb would.
//
// GROUND TEXTURES (2026-09-03, scripts/GroundPaint.gd) ----------------------
// On top of the tint, real tileable textures from the ground sheet
// (assets/terrain/ground_atlas.dat, PNG bytes: 11 art-style ROWS x 11 ground COLUMNS,
// bound here as a Texture2DArray, layer = id - 1). Which tile a 4 m bake cell
// wears comes from two L8 maps on the bake grid:
//   ground_paint  what the god editor PAINTED: a tile id 1..121, 0 = nothing
//   ground_base   the bake's own ground class as a sheet COLUMN 1..11, 0 = water
// and one integer: ground_row, the WORLD STYLE. An unpainted cell wears
//   id = ground_row * 11 + column
// so re-styling the whole map is one uniform. ground_row < 0 turns the base
// layer off and only painted cells are textured; everything else is the tint.
//
// The four cell centres around the fragment are blended bilinearly, so a
// painted edge is a 4 m gradient and a lone cell is a soft blob, never a hard
// square. Where the four ids agree (almost everywhere) it is one fetch.
// Texture LOD is taken with textureGrad so the divergent branches below can
// never pick a wrong mip at a tile edge.
// ============================================================================
render_mode diffuse_burley, specular_disabled, cull_back;

uniform float cell = 0.5;                  // metres per ground texel
uniform float detail : hint_range(0.0, 0.4) = 0.11;   // per-cell tone jitter
uniform float macro : hint_range(0.0, 0.4) = 0.05;    // per-8 m patch jitter
uniform float detail_fade_far = 220.0;     // cells fade out past this (no shimmer)
uniform float posterize : hint_range(2.0, 32.0) = 7.0;
uniform float bands : hint_range(2.0, 8.0) = 4.0;
uniform float band_floor : hint_range(0.0, 0.6) = 0.36;

uniform vec3 rock_col : source_color = vec3(0.33, 0.32, 0.30);
uniform float rock_slope : hint_range(0.2, 1.0) = 0.60;   // 1 - normal.y
uniform vec3 sand_col : source_color = vec3(0.60, 0.55, 0.40);
uniform float sea_level = -22.5;
uniform float beach_band = 1.8;
uniform vec3 snow_col : source_color = vec3(0.86, 0.88, 0.92);
uniform float snow_line = 440.0;           // Katahdin's shoulders whiten

// --- THE MEADOW, v3.1 -------------------------------------------------------
// "Make the grass cover the whole world outside the towns." Blades are placed
// out to the draw ring (GrassSystem, 90 m by default) and the world past that
// used to be flat terrain colour — which from any hilltop is exactly the bare
// ground this is meant to fix. Real tufts cannot go that far (474,000 chunks
// to the map edge), so past the ring the GROUND ITSELF becomes the meadow:
// the same four season stops the grass shader uses, laid over the terrain
// colour so the map's own woods, fields and shore still read through it.
//
// The blend RAMPS IN over the stretch where the blades are fading out, so
// there is no line where one takes over from the other — stand anywhere and
// the meadow you are in and the meadow on the far ridge are the same green.
//
// Rock faces, snow, the beach, packed tracks and the water keep their own
// surfaces: this is grass, and grass does not grow on a cliff, a snowfield,
// a road or below the tide.
global uniform float season_phase;
uniform vec3 meadow_spring : source_color = vec3(0.35, 0.53, 0.19);
uniform vec3 meadow_summer : source_color = vec3(0.25, 0.40, 0.15);
uniform vec3 meadow_autumn : source_color = vec3(0.53, 0.45, 0.19);
uniform vec3 meadow_winter : source_color = vec3(0.40, 0.36, 0.24);
uniform float meadow_amount : hint_range(0.0, 1.0) = 1.0;   // 0 = the old bare map
uniform float meadow_bias : hint_range(0.0, 1.0) = 0.80;    // how far toward the grass
uniform float meadow_near = 35.0;          // the blades still carry it this close
uniform float meadow_far = 120.0;          // ...and by here the ground is on its own
uniform float meadow_clump = 11.0;         // metres per patch of the far grain
uniform float meadow_grain : hint_range(0.0, 0.5) = 0.18;

// --- ground textures (all set by GroundPaint.gd; defaults = feature off) ----
uniform sampler2DArray ground_tiles : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_base : filter_nearest, repeat_disable;
uniform sampler2D ground_paint : filter_nearest, repeat_disable;
uniform vec2 ground_origin = vec2(0.0, 0.0);   // world x/z of cell (0, 0)'s CENTRE
uniform float ground_step = 4.0;               // metres per cell
uniform ivec2 ground_cells = ivec2(1, 1);      // cells across / down
uniform int ground_layers = 0;                 // tiles in the array; 0 = no textures bound
uniform int ground_row = -1;                   // world style row 0..10; -1 = tint only
uniform float tile_m = 2.0;                    // metres of ground per texture repeat
uniform float tile_rock : hint_range(0.0, 1.0) = 1.0;   // steep faces still turn to rock over a tile

// --- GRASS PAINT (2026-09-14, scripts/GrassPaint.gd) -------------------------
// Where the grass grows, painted in god mode, on the same 4 m grid as the
// ground textures: 0 = the rule above decides, 1 = BARE, 2..255 = grass at a
// density of (v - 1) / 254 whatever the rule says. The far meadow reads it so
// a bare patch is bare to the map edge and a painted meadow is green from the
// ridge, exactly where the blades (GrassSystem._place_chunk) will and won't
// stand when you walk over. Four cells blended, like the tiles, so an edge is
// a 4 m gradient. grass_paint_on = 0 (the default) is the rule alone.
uniform sampler2D grass_paint : filter_nearest, repeat_disable;
uniform int grass_paint_on = 0;

varying vec3 v_world;
varying vec3 v_wnormal;
varying vec3 v_tint;

float hash21(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

// What the grass paint says about a bake cell: -1 = ask the rule, else the
// fraction of a full meadow (0 = bare).
float grass_cell(ivec2 c) {
	c = clamp(c, ivec2(0), ground_cells - ivec2(1));
	int v = int(texelFetch(grass_paint, c, 0).r * 255.0 + 0.5);
	if (v == 0) {
		return -1.0;
	}
	return float(v - 1) / 254.0;
}

// The tile id a bake cell wears: what was painted, else the world style's
// tile for the bake's ground class, else nothing.
int ground_id(ivec2 c) {
	c = clamp(c, ivec2(0), ground_cells - ivec2(1));
	int p = int(texelFetch(ground_paint, c, 0).r * 255.0 + 0.5);
	if (p > 0) {
		return p;
	}
	if (ground_row < 0) {
		return 0;
	}
	int b = int(texelFetch(ground_base, c, 0).r * 255.0 + 0.5);
	if (b == 0) {
		return 0;
	}
	return ground_row * 11 + b;
}

vec3 tile_col(int id, vec2 uv, vec2 ddx, vec2 ddy) {
	float layer = float(clamp(id, 1, ground_layers) - 1);
	return textureGrad(ground_tiles, vec3(uv, layer), ddx, ddy).rgb;
}

// Packed dirt (col 3), mud/track (col 4) and snow (col 10) are not meadow.
// Column index is (id - 1) % 11, matching GroundPaint.col_of / grass_on_tile.
float tile_allows_grass(int id) {
	if (id <= 0) {
		return 1.0;
	}
	int col = (id - 1) % 11;
	if (col == 3 || col == 4 || col == 10) {
		return 0.0;
	}
	return 1.0;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_tint = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));   // sRGB -> linear
}

void fragment() {
	// how far from the eye, for the cell fade
	float dist = length(VERTEX);
	float cells_on = 1.0 - smoothstep(detail_fade_far * 0.5, detail_fade_far, dist);

	vec2 c = floor(v_world.xz / cell);
	float h = hash21(c);
	float hm = hash21(floor(v_world.xz / (cell * 16.0)) + 7.0);

	// --- the ground textures: a bilinear blend of the four nearest cells -----
	float tw = 0.0;            // how much of this fragment is textured (0..1)
	vec3 tcol = vec3(0.0);     // the weighted texture colour (already x tw)
	float tile_grass = 1.0;    // 0 on snow / packed dirt / a wet track
	if (ground_layers > 0) {
		vec2 g = (v_world.xz - ground_origin) / ground_step;
		vec2 fl = floor(g);
		vec2 f = g - fl;
		ivec2 i0 = ivec2(fl);
		int i00 = ground_id(i0);
		int i10 = ground_id(i0 + ivec2(1, 0));
		int i01 = ground_id(i0 + ivec2(0, 1));
		int i11 = ground_id(i0 + ivec2(1, 1));
		vec2 uv = v_world.xz / tile_m;
		vec2 ddx = dFdx(uv);
		vec2 ddy = dFdy(uv);
		if (i00 == i10 && i00 == i01 && i00 == i11) {
			if (i00 > 0) {
				tcol = tile_col(i00, uv, ddx, ddy);
				tw = 1.0;
			}
			tile_grass = tile_allows_grass(i00);
		} else {
			float w00 = (1.0 - f.x) * (1.0 - f.y);
			float w10 = f.x * (1.0 - f.y);
			float w01 = (1.0 - f.x) * f.y;
			float w11 = f.x * f.y;
			if (i00 > 0) { tcol += w00 * tile_col(i00, uv, ddx, ddy); tw += w00; }
			if (i10 > 0) { tcol += w10 * tile_col(i10, uv, ddx, ddy); tw += w10; }
			if (i01 > 0) { tcol += w01 * tile_col(i01, uv, ddx, ddy); tw += w01; }
			if (i11 > 0) { tcol += w11 * tile_col(i11, uv, ddx, ddy); tw += w11; }
			tile_grass = w00 * tile_allows_grass(i00)
				+ w10 * tile_allows_grass(i10)
				+ w01 * tile_allows_grass(i01)
				+ w11 * tile_allows_grass(i11);
		}
	}

	// the tint where nothing is textured, the texture where it is
	vec3 col = v_tint * (1.0 - tw) + tcol;

	// steep ground is rock; the hash roughens the edge so it is not a contour
	float slope = 1.0 - clamp(v_wnormal.y, 0.0, 1.0);
	float rock = smoothstep(rock_slope - 0.14, rock_slope + 0.10, slope + (h - 0.5) * 0.10);
	rock *= mix(1.0, tile_rock, tw);
	col = mix(col, rock_col, rock);

	// the metre above the waterline is sand, on gentle ground only
	float beach = 1.0 - smoothstep(sea_level + 0.15, sea_level + beach_band, v_world.y);
	col = mix(col, sand_col, beach * (1.0 - rock));

	// THE MEADOW. Everything the map says is ground, from the fade ring out to
	// the horizon, goes most of the way to the colour of the grass standing on
	// it — with a patch grain coarse enough (11 m) not to shimmer at 2 km.
	// the RULE: dry ground that is not a cliff, the beach, snow, or a track
	float snow = smoothstep(snow_line, snow_line + 90.0, v_world.y + (h - 0.5) * 30.0)
		* (1.0 - rock * 0.7);
	float rule = (1.0 - rock)
		* smoothstep(sea_level + 0.2, sea_level + 2.6, v_world.y)
		* (1.0 - beach)
		* (1.0 - snow)
		* tile_grass;
	float grass = rule;
	if (grass_paint_on > 0) {
		// the paint, where there is any: a cell says bare, grass, or "ask"
		vec2 g = (v_world.xz - ground_origin) / ground_step;
		vec2 fl = floor(g);
		vec2 f = g - fl;
		ivec2 i0 = ivec2(fl);
		float p00 = grass_cell(i0);
		float p10 = grass_cell(i0 + ivec2(1, 0));
		float p01 = grass_cell(i0 + ivec2(0, 1));
		float p11 = grass_cell(i0 + ivec2(1, 1));
		// painted grass still will not stand in the water, the snow, or a track
		float wet = smoothstep(sea_level + 0.2, sea_level + 0.6, v_world.y);
		float allow = wet * (1.0 - snow) * tile_grass;
		p00 = p00 < 0.0 ? rule : p00 * allow;
		p10 = p10 < 0.0 ? rule : p10 * allow;
		p01 = p01 < 0.0 ? rule : p01 * allow;
		p11 = p11 < 0.0 ? rule : p11 * allow;
		grass = mix(mix(p00, p10, f.x), mix(p01, p11, f.x), f.y);
	}
	float meadow = meadow_amount
		* smoothstep(meadow_near, meadow_far, dist)
		* grass;
	if (meadow > 0.002) {
		float t = fract(season_phase) * 4.0;
		int si = int(floor(t));
		float sf = smoothstep(0.55, 1.0, fract(t));
		vec3 sa = meadow_spring;
		vec3 sb = meadow_summer;
		if (si == 1) { sa = meadow_summer; sb = meadow_autumn; }
		else if (si == 2) { sa = meadow_autumn; sb = meadow_winter; }
		else if (si == 3) { sa = meadow_winter; sb = meadow_spring; }
		vec3 mcol = mix(sa, sb, sf);
		// two patch scales, so the far field drifts the way a real one does
		float g1 = hash21(floor(v_world.xz / meadow_clump) + 19.0);
		float g2 = hash21(floor(v_world.xz / (meadow_clump * 3.7)) + 53.0);
		mcol *= 1.0 + ((g1 - 0.5) * 1.2 + (g2 - 0.5) * 0.8) * meadow_grain;
		col = mix(col, mix(col, mcol, meadow_bias), meadow);
	}

	// the high tops hold snow where it can lie (amount already computed above
	// so the meadow steps off it; this is the colour)
	col = mix(col, snow_col, snow);

	// Posterize the BASE on VALUE, so the painted map lands on one palette...
	// (the textures carry their own palette from the sheet, so they skip it)
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	vec3 q = col * ((max(floor(lum * posterize + 0.5), 1.0) / posterize) / max(lum, 0.0008));
	col = mix(q, col, tw);

	// ...then lay the texel cells over it, un-quantised. Quantising AFTER the
	// jitter collapsed a +-10% wobble into two flat tones -- a checkerboard on
	// every meadow -- and erased it entirely on the mid greens. The textures
	// get a quarter of the cell jitter: they have their own texels.
	col *= 1.0 + (h - 0.5) * 2.0 * detail * cells_on * mix(1.0, 0.25, tw);
	col *= 1.0 + (hm - 0.5) * 2.0 * macro;

	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

// Four flat diffuse tones, no specular — the banded light() every other
// surface in the game uses. NOTE: `return` is illegal in here.
void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	float b = floor(clamp(ndl, 0.0, 1.0) * bands) / max(bands - 1.0, 1.0);
	b = mix(band_floor, 1.0, clamp(b, 0.0, 1.0));
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * b;
}
