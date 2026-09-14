class_name PsxTex
extends RefCounted
## The creature texture atlas. ONE 256x256 image, a 4x4 grid of 64x64 tiles,
## every tile a seamless GRAYSCALE-ish surface pattern; colour comes from the
## segment palette (the original box colours), so a fox and a lynx share the
## same fur tile and differ only in the numbers CritterDex already holds.
##
## Nothing is painted or downloaded — same philosophy as leafgen/barkgen: every
## texel is a function of (x, y, tile). Built once, cached for the run.
##
## Tiles (index = column + row * 4):
##   0 flat        4 hide         8 cloth       12 bone
##   1 fur         5 feather      9 leather     13 stone
##   2 fur_striped 6 scale       10 wood        14 fur_long
##   3 fur_spotted 7 skin        11 metal       15 chitin

const SIZE := 256
const TILE := 64
const TILES := {
	"flat": 0, "fur": 1, "fur_striped": 2, "fur_spotted": 3,
	"hide": 4, "feather": 5, "scale": 6, "skin": 7,
	"cloth": 8, "leather": 9, "wood": 10, "metal": 11,
	"bone": 12, "stone": 13, "fur_long": 14, "chitin": 15,
}

static var _tex: ImageTexture = null
static var _img: Image = null


static func tile_index(name: String) -> int:
	return int(TILES.get(name, 0))


static func atlas() -> ImageTexture:
	if _tex == null:
		_tex = ImageTexture.create_from_image(image())
	return _tex


static func image() -> Image:
	if _img != null:
		return _img
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for t in 16:
		var ox := (t % 4) * TILE
		@warning_ignore("integer_division")
		var oy := (t / 4) * TILE
		for y in TILE:
			for x in TILE:
				var u := float(x) / TILE
				var v := float(y) / TILE
				img.set_pixel(ox + x, oy + y, _texel(t, u, v, x, y))
	_img = img
	return img


## ------------------------------------------------------------ noise ------

static func _fr(x: float) -> float:
	return x - floor(x)


static func _hash(i: int, j: int, sd: int) -> float:
	var n := i * 374761393 + j * 668265263 + sd * 1274126177
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0xFFFFFF) / float(0xFFFFFF)


static func _vnoise(u: float, v: float, cells: int, sd: int) -> float:
	## Value noise that TILES at u,v = 1 (lattice wraps at `cells`).
	var fx := u * cells
	var fy := v * cells
	var ix := int(floor(fx))
	var iy := int(floor(fy))
	var tx := fx - ix
	var ty := fy - iy
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var a := _hash(ix % cells, iy % cells, sd)
	var b := _hash((ix + 1) % cells, iy % cells, sd)
	var c := _hash(ix % cells, (iy + 1) % cells, sd)
	var d := _hash((ix + 1) % cells, (iy + 1) % cells, sd)
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)


static func _fbm(u: float, v: float, cells: int, sd: int, oct := 3) -> float:
	var s := 0.0
	var amp := 0.5
	var tot := 0.0
	var c := cells
	for i in oct:
		s += _vnoise(u, v, c, sd + i * 7) * amp
		tot += amp
		amp *= 0.5
		c *= 2
	return s / tot


## ------------------------------------------------------------ tiles ------

static func _texel(t: int, u: float, v: float, x: int, y: int) -> Color:
	var g := 1.0
	var tint := Vector3(1, 1, 1)
	match t:
		0:  ## flat — a whisper of grain so it is not a vector fill
			g = 0.97 + 0.06 * _vnoise(u, v, 8, 1)
		1:  ## fur — short streaks running along v
			g = 0.86 + 0.26 * _fbm(u * 3.0, v, 16, 11, 2)
			g *= 0.94 + 0.12 * _vnoise(u * 7.0, v * 0.8, 32, 12)
		2:  ## striped fur — dark bands across u with ragged edges
			g = 0.86 + 0.26 * _fbm(u * 3.0, v, 16, 21, 2)
			var band := sin((v + 0.08 * _vnoise(u, v, 8, 22)) * TAU * 3.0)
			if band > 0.35:
				g *= 0.58
		3:  ## spotted fur — blobs
			g = 0.86 + 0.26 * _fbm(u * 3.0, v, 16, 31, 2)
			if _vnoise(u, v, 6, 33) > 0.66:
				g *= 0.55
		4:  ## hide — coarse mottle, short nap
			g = 0.90 + 0.18 * _fbm(u, v, 6, 41, 3)
		5:  ## feather — overlapping scallop rows
			var row := floorf(v * 8.0)
			var uu := u * 6.0 + (0.5 if int(row) % 2 == 1 else 0.0)
			var fu := _fr(uu) - 0.5
			var fv := _fr(v * 8.0)
			var edge := fv - (0.35 - fu * fu * 1.4)
			g = 0.92 + 0.14 * _vnoise(u, v, 16, 51)
			if edge < 0.0 and edge > -0.12:
				g *= 0.72
			g *= 0.94 + 0.12 * fv
		6:  ## scale — hex-ish plates with dark seams
			var row2 := floorf(v * 8.0)
			var uu2 := u * 8.0 + (0.5 if int(row2) % 2 == 1 else 0.0)
			var cu := absf(_fr(uu2) - 0.5)
			var cv := absf(_fr(v * 8.0) - 0.5)
			var r := maxf(cu * 1.15, cv)
			g = 0.90 + 0.16 * _vnoise(u, v, 8, 61)
			if r > 0.42:
				g *= 0.62
			else:
				g *= 1.0 + (0.42 - r) * 0.25
		7:  ## skin — warty: bright bumps, dark pits
			g = 0.92 + 0.14 * _fbm(u, v, 8, 71, 3)
			var w := _vnoise(u, v, 16, 72)
			if w > 0.78:
				g *= 1.12
			elif w < 0.18:
				g *= 0.80
		8:  ## cloth — weave
			g = 0.94 + 0.08 * _vnoise(u, v, 16, 81)
			if (x % 4 == 0) != (y % 4 == 0):
				g *= 0.93
			tint = Vector3(1.0, 0.99, 0.97)
		9:  ## leather — fine grain plus a few scratches
			g = 0.90 + 0.16 * _fbm(u, v, 12, 91, 3)
			if _vnoise(u * 9.0, v, 24, 92) > 0.86:
				g *= 0.78
		10:  ## wood — grain along v, with knots
			var gr := sin((u * 9.0 + 0.6 * _fbm(u, v, 4, 101, 2)) * TAU)
			g = 0.86 + 0.18 * (gr * 0.5 + 0.5)
			if _vnoise(u, v, 4, 103) > 0.82:
				g *= 0.72
			tint = Vector3(1.0, 0.94, 0.85)
		11:  ## metal — brushed lines, cool cast
			g = 0.92 + 0.12 * _vnoise(u * 20.0, v * 0.5, 32, 111)
			g += 0.06 * _vnoise(u, v, 4, 112)
			tint = Vector3(0.94, 0.97, 1.05)
		12:  ## bone — pale, porous
			g = 0.96 + 0.08 * _fbm(u, v, 8, 121, 3)
			if _vnoise(u, v, 24, 122) > 0.84:
				g *= 0.82
			tint = Vector3(1.02, 1.0, 0.94)
		13:  ## stone — mottle
			g = 0.88 + 0.22 * _fbm(u, v, 6, 131, 4)
		14:  ## long fur — deep streaks
			g = 0.78 + 0.38 * _fbm(u * 5.0, v * 0.7, 16, 141, 3)
		15:  ## chitin — plates with rims
			var pv := _fr(v * 5.0)
			g = 0.90 + 0.16 * _vnoise(u, v, 8, 151)
			if pv < 0.10:
				g *= 0.62
			elif pv < 0.22:
				g *= 1.10
	g = clampf(g, 0.45, 1.25)
	## quantize the detail itself — a PS1 texture had 16 or 256 colours, not a float
	g = floor(g * 14.0 + 0.5) / 14.0
	return Color(clampf(g * tint.x, 0.0, 1.0), clampf(g * tint.y, 0.0, 1.0), clampf(g * tint.z, 0.0, 1.0))
