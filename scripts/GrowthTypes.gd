class_name GrowthTypes
extends RefCounted

## ===========================================================================
## THE CATALOGUE of what grows on things, and the one atlas it all draws from.
##
## Lemon (2026-09-03): "different types of patches, such as different mosses
## and fungi, or vines, then in each of those is a variety of different bases
## and accents."
##
## So: a TYPE (moss / fungi / vine / lichen) is a family. Each family has a set
## of BASES (layer 1 -- the film that hugs the surface) and a set of ACCENTS
## (layer 2 -- what stands proud of that film once it is established). A patch
## is one type + one base + one accent, and GrowthPatch builds it. Add a row
## to a table here and it exists in the world; no other file has to know.
##
## Every entry:
##   tile     which atlas tile the cards wear (see TILES)
##   style    card geometry -- "flush" (in the surface), "shelf" (bracket
##            sticking out level), "cross" (two crossed cards standing off the
##            surface), "hang" (a strip hanging down, swaying)
##   size     [min, max] card size in metres
##   n        cards per square metre of patch at full growth
##   tint     colour multiplier for the tile (bases are painted grey-green in
##            the atlas and take their whole colour from here; accents carry
##            their own paint and take a light tint)
##   off      how far off the surface the card sits, metres
##
## Each family also has:
##   speed    growth rate multiplier (lichen is slow, fungi are quick)
##   wet      how much rain speeds it (1.0 = trebles at full wetness)
##   shade    how much it minds the sun (1.0 = full sun halves it)
##   opacity  [base, accent] alpha at full growth -- "slightly transparent"
##
## The atlas is PROCEDURAL: painted once per run with FastNoiseLite into a
## 512x384 image, twelve 128 px tiles, and cached. No texture files to ship or
## lose, and every tile is documented in code by what it is supposed to be.
## ===========================================================================

const TILE := 128
const COLS := 4
const ROWS := 3

## Tile index -> what it is. Kept as named constants so a table row reads.
const T_CUSHION := 0     ## a round moss cushion, soft-edged
const T_SHEET := 1       ## a ragged film with holes in it
const T_CRUST := 2       ## a lichen crust: lobed, dark-rimmed
const T_WEB := 3         ## mycelium threads / thin tendrils
const T_BRACKET := 4     ## a shelf fungus, banded (turkey tail)
const T_TOAD_RED := 5    ## red-capped toadstool with pale spots, on a stem
const T_STRAND := 6      ## a leafy hanging strand (ivy / vine)
const T_WISP := 7        ## thin pale threads hanging (beard lichen, sporophytes)
const T_TOAD_BROWN := 8  ## brown-capped mushroom cluster
const T_HOOF := 9        ## a hoof / conk fungus, thick and grey-brown
const T_LEAF_FILM := 10  ## small ivy leaves overlapping as a sheet
const T_SPOTS := 11      ## a scatter of small dots (cup lichen, tiny blooms)

const TYPES := {
	"moss": {
		"speed": 1.0, "wet": 1.2, "shade": 1.0, "opacity": [0.80, 0.90],
		"bases": {
			"cushion": {"tile": T_CUSHION, "style": "flush", "size": [0.10, 0.22], "n": 95.0,
				"tint": Color(0.44, 0.62, 0.24), "off": 0.012},
			"sheet": {"tile": T_SHEET, "style": "flush", "size": [0.18, 0.34], "n": 55.0,
				"tint": Color(0.36, 0.54, 0.26), "off": 0.010},
			"feather": {"tile": T_CUSHION, "style": "flush", "size": [0.07, 0.14], "n": 170.0,
				"tint": Color(0.56, 0.68, 0.26), "off": 0.014},
			"peat": {"tile": T_SHEET, "style": "flush", "size": [0.14, 0.26], "n": 70.0,
				"tint": Color(0.40, 0.44, 0.18), "off": 0.010},
		},
		"accents": {
			"sporophytes": {"tile": T_WISP, "style": "cross", "size": [0.05, 0.09], "n": 22.0,
				"tint": Color(0.80, 0.52, 0.34), "off": 0.02},
			"buttons": {"tile": T_TOAD_BROWN, "style": "cross", "size": [0.05, 0.09], "n": 10.0,
				"tint": Color(1.0, 0.95, 0.85), "off": 0.02},
			"lichen_spots": {"tile": T_SPOTS, "style": "flush", "size": [0.08, 0.16], "n": 18.0,
				"tint": Color(0.82, 0.86, 0.70), "off": 0.02},
		},
	},
	"fungi": {
		"speed": 1.35, "wet": 1.6, "shade": 1.2, "opacity": [0.72, 0.95],
		"bases": {
			"mycelium": {"tile": T_WEB, "style": "flush", "size": [0.16, 0.30], "n": 60.0,
				"tint": Color(0.86, 0.84, 0.72), "off": 0.010},
			"rot": {"tile": T_SHEET, "style": "flush", "size": [0.20, 0.36], "n": 45.0,
				"tint": Color(0.36, 0.28, 0.18), "off": 0.008},
			"mould": {"tile": T_CUSHION, "style": "flush", "size": [0.08, 0.16], "n": 120.0,
				"tint": Color(0.52, 0.56, 0.40), "off": 0.010},
		},
		"accents": {
			"brackets": {"tile": T_BRACKET, "style": "shelf", "size": [0.10, 0.22], "n": 14.0,
				"tint": Color(1.0, 0.96, 0.90), "off": 0.0},
			"toadstools": {"tile": T_TOAD_RED, "style": "cross", "size": [0.08, 0.15], "n": 9.0,
				"tint": Color(1.0, 1.0, 1.0), "off": 0.02},
			"conks": {"tile": T_HOOF, "style": "shelf", "size": [0.12, 0.24], "n": 7.0,
				"tint": Color(0.95, 0.90, 0.82), "off": 0.0},
			"teeth": {"tile": T_WISP, "style": "hang", "size": [0.06, 0.12], "n": 26.0,
				"tint": Color(0.96, 0.94, 0.86), "off": 0.02},
		},
	},
	"vine": {
		"speed": 0.75, "wet": 0.8, "shade": 0.5, "opacity": [0.86, 0.94],
		"bases": {
			"ivy": {"tile": T_LEAF_FILM, "style": "flush", "size": [0.16, 0.28], "n": 70.0,
				"tint": Color(0.32, 0.54, 0.22), "off": 0.016},
			"tendrils": {"tile": T_WEB, "style": "flush", "size": [0.18, 0.32], "n": 55.0,
				"tint": Color(0.46, 0.50, 0.22), "off": 0.012},
			"creeper": {"tile": T_LEAF_FILM, "style": "flush", "size": [0.10, 0.18], "n": 110.0,
				"tint": Color(0.50, 0.58, 0.18), "off": 0.016},
		},
		"accents": {
			"strands": {"tile": T_STRAND, "style": "hang", "size": [0.22, 0.50], "n": 18.0,
				"tint": Color(0.90, 1.0, 0.86), "off": 0.03},
			"curls": {"tile": T_WISP, "style": "hang", "size": [0.10, 0.20], "n": 24.0,
				"tint": Color(0.70, 0.80, 0.40), "off": 0.03},
			"blooms": {"tile": T_SPOTS, "style": "flush", "size": [0.06, 0.12], "n": 30.0,
				"tint": Color(0.95, 0.70, 0.85), "off": 0.02},
		},
	},
	"lichen": {
		"speed": 0.45, "wet": 0.5, "shade": 0.2, "opacity": [0.84, 0.90],
		"bases": {
			"crust_grey": {"tile": T_CRUST, "style": "flush", "size": [0.10, 0.20], "n": 80.0,
				"tint": Color(0.62, 0.66, 0.56), "off": 0.008},
			"crust_orange": {"tile": T_CRUST, "style": "flush", "size": [0.08, 0.16], "n": 90.0,
				"tint": Color(0.86, 0.56, 0.20), "off": 0.008},
			"crust_mint": {"tile": T_CRUST, "style": "flush", "size": [0.10, 0.20], "n": 75.0,
				"tint": Color(0.60, 0.74, 0.58), "off": 0.008},
		},
		"accents": {
			"beard": {"tile": T_WISP, "style": "hang", "size": [0.10, 0.24], "n": 20.0,
				"tint": Color(0.78, 0.84, 0.70), "off": 0.03},
			"cups": {"tile": T_SPOTS, "style": "flush", "size": [0.06, 0.12], "n": 26.0,
				"tint": Color(0.72, 0.78, 0.60), "off": 0.02},
			"shields": {"tile": T_CRUST, "style": "flush", "size": [0.06, 0.12], "n": 30.0,
				"tint": Color(0.80, 0.80, 0.72), "off": 0.018},
		},
	},
}


static func family(type_id: String) -> Dictionary:
	return TYPES.get(type_id, TYPES["moss"])


static func base_of(type_id: String, base_id: String) -> Dictionary:
	var f := family(type_id)
	var b: Dictionary = f["bases"]
	return b.get(base_id, b[b.keys()[0]])


static func accent_of(type_id: String, accent_id: String) -> Dictionary:
	var f := family(type_id)
	var a: Dictionary = f["accents"]
	return a.get(accent_id, a[a.keys()[0]])


static func type_ids() -> Array:
	return TYPES.keys()


static func pick_base(type_id: String, rng: RandomNumberGenerator) -> String:
	var keys: Array = family(type_id)["bases"].keys()
	return String(keys[rng.randi() % keys.size()])


static func pick_accent(type_id: String, rng: RandomNumberGenerator) -> String:
	var keys: Array = family(type_id)["accents"].keys()
	return String(keys[rng.randi() % keys.size()])


static func tile_rect(tile: int) -> Rect2:
	## UV rect of a tile, inset half a texel so filtering never bleeds a
	## neighbour's edge in
	var cx := tile % COLS
	var cy := tile / COLS
	var inset := 0.5 / float(TILE)
	var w := 1.0 / float(COLS)
	var h := 1.0 / float(ROWS)
	return Rect2(cx * w + inset * w, cy * h + inset * h, w - 2.0 * inset * w, h - 2.0 * inset * h)


## ------------------------------------------------------------- the atlas ---

static var _atlas: ImageTexture = null
static var _material: ShaderMaterial = null

const SHADER := "res://shaders/growth.gdshader"


static func material() -> ShaderMaterial:
	## ONE material for every patch in the world. Growth, tint and wetness are
	## instance uniforms, so a hundred patches are still one material and never
	## add to the material count the optimisation audit flagged.
	if _material != null:
		return _material
	_material = ShaderMaterial.new()
	var sh := load(SHADER)
	if sh != null:
		_material.shader = sh
	_material.set_shader_parameter("atlas", atlas())
	return _material


static func atlas() -> ImageTexture:
	if _atlas != null:
		return _atlas
	var img := Image.create(COLS * TILE, ROWS * TILE, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for t in range(COLS * ROWS):
		_paint_tile(img, t)
	img.generate_mipmaps()
	_atlas = ImageTexture.create_from_image(img)
	return _atlas


static func _noise(seed_v: int, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = 3
	return n


static func _paint_tile(img: Image, tile: int) -> void:
	var ox := (tile % COLS) * TILE
	var oy := (tile / COLS) * TILE
	var na := _noise(100 + tile, 4.0 / float(TILE))
	var nb := _noise(200 + tile, 11.0 / float(TILE))
	var nc := _noise(300 + tile, 27.0 / float(TILE))
	for py in range(TILE):
		for px in range(TILE):
			var u := (float(px) + 0.5) / float(TILE)
			var v := (float(py) + 0.5) / float(TILE)
			var a := na.get_noise_2d(px, py)          ## -1..1, slow
			var b := nb.get_noise_2d(px, py)          ## medium
			var c := nc.get_noise_2d(px, py)          ## fine grain
			img.set_pixel(ox + px, oy + py, _texel(tile, u, v, a, b, c))


## One texel of one tile. u, v in 0..1; a/b/c three octaves of noise in -1..1.
## Bases are painted in a neutral grey-green and take their colour from the
## row's tint; accents are painted in their own colours.
static func _texel(tile: int, u: float, v: float, a: float, b: float, c: float) -> Color:
	var du := u - 0.5
	var dv := v - 0.5
	var r := sqrt(du * du + dv * dv) * 2.0     ## 0 centre .. 1 tile edge
	var grain := 0.82 + 0.18 * c + 0.10 * b
	var px := _texel_raw(tile, u, v, du, dv, r, grain, a, b, c)
	## every ROUND tile fades out before the tile's edge, or the card's square
	## cut shows as a hard line through the moss
	if tile in [T_CUSHION, T_SHEET, T_CRUST, T_WEB, T_LEAF_FILM, T_SPOTS]:
		px.a *= smoothstep(0.99, 0.84, r)
	return px


static func _texel_raw(tile: int, u: float, v: float, du: float, dv: float, r: float,
		grain: float, a: float, b: float, c: float) -> Color:
	match tile:
		T_CUSHION:
			## a round cushion whose edge is lumpy; lighter in the middle
			var edge := 0.78 + a * 0.16 + b * 0.08
			var al := smoothstep(edge, edge - 0.30, r)
			var val := (0.70 + 0.30 * (1.0 - r)) * grain
			return Color(val, val * 1.02, val * 0.92, al)
		T_SHEET:
			## a ragged film full of holes
			var edge := 0.90 + a * 0.20
			var al := smoothstep(edge, edge - 0.35, r)
			if b > 0.42:
				al *= 0.25                              ## a hole
			var val := (0.62 + 0.25 * (1.0 - r * 0.5)) * grain
			return Color(val, val * 1.03, val * 0.94, al)
		T_CRUST:
			## lobed crust with a dark rim, like a lichen thallus
			var edge := 0.74 + a * 0.22 + b * 0.10
			var al := smoothstep(edge + 0.06, edge - 0.10, r)
			var rim := smoothstep(edge - 0.22, edge - 0.02, r)
			var val := lerpf(0.86, 0.42, rim) * grain
			if c > 0.55:
				val *= 0.80                             ## pits
			return Color(val, val, val * 0.96, al)
		T_WEB:
			## ridged noise: thin bright filaments on nothing
			var ridge := 1.0 - absf(b) * 2.0
			var ridge2 := 1.0 - absf(c) * 2.0
			var f := maxf(smoothstep(0.62, 0.92, ridge), smoothstep(0.78, 0.98, ridge2) * 0.7)
			var fall := smoothstep(1.0, 0.45, r)
			var val := 0.90 * grain
			return Color(val, val, val * 0.95, f * fall)
		T_BRACKET:
			## a half-disc growing out of the bottom edge, concentric bands
			var bu := du
			var bv := v - 1.0                          ## 0 at the root edge, -1 at the top
			var rr := sqrt(bu * bu + bv * bv) * 2.0
			var edge := 0.94 + a * 0.10
			var al := smoothstep(edge, edge - 0.10, rr) * float(v > 0.02)
			var band := 0.5 + 0.5 * sin(rr * 26.0 + a * 3.0)
			var base_col := Color(0.55, 0.42, 0.28)
			var light_col := Color(0.86, 0.74, 0.52)
			var col := base_col.lerp(light_col, band * 0.8)
			col = col.lerp(Color(0.30, 0.22, 0.14), smoothstep(0.55, 1.0, rr) * 0.5)   ## darker outer band
			col = col.lerp(Color(0.95, 0.92, 0.80), smoothstep(0.92, 0.99, rr) * 0.9) ## pale lip
			return Color(col.r * grain, col.g * grain, col.b * grain, al)
		T_TOAD_RED, T_TOAD_BROWN:
			return _toadstool(tile == T_TOAD_RED, u, v, a, b, grain)
		T_STRAND:
			## a stem down the middle with leaves lobed off either side, tapering
			var sway := a * 0.10
			var cx := 0.5 + sway * v
			var stem_w := 0.020 * (1.0 - v * 0.5)
			var leaf := 0.0
			for k in range(5):
				var ly := 0.12 + float(k) * 0.19
				var side := 1.0 if (k % 2 == 0) else -1.0
				var lx := cx + side * 0.16
				var ex := (u - lx) / 0.15
				var ey := (v - ly) / 0.10
				leaf = maxf(leaf, 1.0 - (ex * ex + ey * ey))
			var stem := smoothstep(stem_w + 0.01, stem_w, absf(u - cx))
			var al := maxf(smoothstep(0.0, 0.25, leaf), stem * 0.9)
			var col := Color(0.30, 0.48, 0.20).lerp(Color(0.50, 0.62, 0.24), clampf(leaf, 0.0, 1.0))
			if stem > leaf:
				col = Color(0.40, 0.32, 0.18)
			return Color(col.r * grain, col.g * grain, col.b * grain, al)
		T_WISP:
			## a handful of thin threads hanging from the top edge, thinning out
			var al := 0.0
			for k in range(6):
				var x0 := 0.12 + float(k) * 0.15 + a * 0.05
				var wob := sin(v * 9.0 + float(k) * 1.7) * 0.03 * v
				var w := 0.010 + 0.014 * (1.0 - v)
				var d := absf(u - (x0 + wob))
				al = maxf(al, smoothstep(w + 0.008, w, d))
			al *= smoothstep(1.0, 0.55, v) * 0.95 + 0.05
			var val := 0.92 * grain
			return Color(val, val, val * 0.94, al)
		T_HOOF:
			## a thick conk: a hoof-shaped mass out of the bottom edge, ridged
			var bu := du * 1.15
			var bv := (v - 1.0) * 1.35
			var rr := sqrt(bu * bu + bv * bv) * 2.0
			var edge := 0.96 + a * 0.06
			var al := smoothstep(edge, edge - 0.08, rr) * float(v > 0.02)
			var ridge := 0.5 + 0.5 * sin(rr * 14.0)
			var col := Color(0.44, 0.38, 0.30).lerp(Color(0.62, 0.56, 0.44), ridge)
			col = col.lerp(Color(0.86, 0.80, 0.62), smoothstep(0.90, 0.98, rr))   ## pale growing lip
			return Color(col.r * grain, col.g * grain, col.b * grain, al)
		T_LEAF_FILM:
			## small overlapping ivy leaves as a sheet, soft edged as a whole
			var leaf := 0.0
			var shade := 0.0
			for k in range(8):
				var ang := float(k) * 0.9 + a * 2.0
				var rad := 0.0 if k == 0 else 0.10 + 0.18 * fposmod(float(k) * 0.61, 1.0)
				var lx := 0.5 + cos(ang) * rad
				var ly := 0.5 + sin(ang) * rad
				var ex := (u - lx) / 0.17
				var ey := (v - ly) / 0.14
				var q := 1.0 - (ex * ex + ey * ey)
				if q > leaf:
					leaf = q
					shade = float(k) / 8.0
			var al := smoothstep(0.0, 0.2, leaf) * smoothstep(1.05, 0.7, r)
			var val := (0.70 + 0.30 * shade) * grain
			return Color(val * 0.92, val, val * 0.84, al)
		T_SPOTS:
			## a scatter of dots
			var al := 0.0
			var val := 0.9
			for k in range(9):
				var sx := 0.18 + fposmod(float(k) * 0.37 + a * 0.3, 0.64)
				var sy := 0.18 + fposmod(float(k) * 0.59 + b * 0.2, 0.64)
				var rad := 0.045 + 0.03 * fposmod(float(k) * 0.71, 1.0)
				var d := sqrt((u - sx) * (u - sx) + (v - sy) * (v - sy))
				var q := smoothstep(rad, rad - 0.02, d)
				if q > al:
					al = q
					val = 0.75 + 0.25 * fposmod(float(k) * 0.43, 1.0)
			return Color(val * grain, val * grain, val * 0.9 * grain, al)
	return Color(1, 1, 1, 0)


static func _toadstool(red: bool, u: float, v: float, a: float, b: float, grain: float) -> Color:
	## A cross-card mushroom: cap on top, stem below, transparent around.
	var cx := 0.5 + a * 0.03
	## cap: an ellipse with a domed top, sitting at v ~ 0.38
	var ex := (u - cx) / 0.40
	var ey := (v - 0.40) / 0.24
	var cap := 1.0 - (ex * ex + ey * ey)
	if v < 0.40:
		cap = 1.0 - (ex * ex + ((v - 0.40) / 0.30) * ((v - 0.40) / 0.30))
	var stem_w := 0.09 * (1.0 + (v - 0.5) * 0.4)
	var stem := float(v > 0.42 and v < 0.97 and absf(u - cx) < stem_w)
	var al := maxf(smoothstep(0.0, 0.12, cap), stem)
	var col: Color
	if cap > 0.0:
		if red:
			col = Color(0.78, 0.16, 0.10)
			## pale warts
			var spot := 0.0
			for k in range(5):
				var sx := cx - 0.26 + float(k) * 0.13 + b * 0.04
				var sy := 0.30 + fposmod(float(k) * 0.37, 1.0) * 0.16
				var d := sqrt((u - sx) * (u - sx) + (v - sy) * (v - sy))
				spot = maxf(spot, smoothstep(0.045, 0.03, d))
			col = col.lerp(Color(0.96, 0.92, 0.82), spot)
		else:
			col = Color(0.56, 0.40, 0.24).lerp(Color(0.72, 0.56, 0.34), clampf(cap, 0.0, 1.0))
		## the cap's underside is darker
		col = col.lerp(Color(0.32, 0.22, 0.14), smoothstep(0.50, 0.62, v) * 0.7)
	else:
		col = Color(0.90, 0.86, 0.76) if red else Color(0.82, 0.74, 0.60)
		col = col.lerp(Color(0.55, 0.48, 0.38), absf(u - cx) / maxf(stem_w, 0.01) * 0.6)
	return Color(col.r * grain, col.g * grain, col.b * grain, al)
