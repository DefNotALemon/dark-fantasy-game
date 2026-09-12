class_name MenuBackdrop
extends RefCounted

## ===========================================================================
## THE TITLE CARD — scripts/MenuBackdrop.gd
##
## A granite coastal fort over the narrows at last light, painted pixel by
## pixel into a 320 x 180 Image and blown up with no filtering, so the menu
## sits on something that looks made rather than rendered.
##
## The fort is Fort Knox on the Penobscot read through this game's eye: a
## squat casemate curtain in cut granite, a demi-bastion on the landward
## shoulder, one tall corner tower, and a tattered banner. The sun has just
## gone down BEHIND it, which is the whole lighting trick — the fort is a
## near-black mass with a warm rim on every edge that faces the glow, the
## water carries the glow back up as a glitter column, and the left third of
## the frame stays cold and dark, which is where the menu's words go.
##
## Deterministic: same seed, same coast, every boot.
## Names no other class (see EditorMode.gd for why).
## ===========================================================================

const BW := 320
const BH := 180

const HORIZON := 106   ## the far waterline
const BLUFF_X := 172   ## where the fort's headland begins
const BLUFF_TOP := 100 ## the rock the fort stands on
const BLUFF_FOOT := 120## where that rock enters the water
const FG_TOP := 150    ## the near shore ledge

const SUN_X := 250.0
const SUN_Y := 109.0

## --- the palette -----------------------------------------------------------
const SKY_HIGH := Color(0.086, 0.098, 0.157)
const SKY_MID := Color(0.196, 0.204, 0.267)
const SKY_LOW := Color(0.427, 0.373, 0.361)
const SKY_HAZE := Color(0.706, 0.549, 0.376)
const GLOW := Color(0.937, 0.749, 0.451)
const CLOUD_DARK := Color(0.145, 0.153, 0.208)
const CLOUD_LIT := Color(0.545, 0.435, 0.361)

const WATER_FAR := Color(0.263, 0.278, 0.318)
const WATER_NEAR := Color(0.063, 0.078, 0.110)
const WATER_GLINT := Color(0.898, 0.729, 0.475)

const ROCK_LIT := Color(0.310, 0.298, 0.286)
const ROCK_MID := Color(0.180, 0.180, 0.184)
const ROCK_DARK := Color(0.086, 0.090, 0.102)
const RIM := Color(0.847, 0.667, 0.408)
const WINDOW := Color(0.941, 0.596, 0.259)
const PINE := Color(0.055, 0.086, 0.082)
const BANNER := Color(0.396, 0.129, 0.137)


static func build(seed_v := 20260904) -> ImageTexture:
    var img := Image.create_empty(BW, BH, false, Image.FORMAT_RGBA8)
    img.fill(Color(0, 0, 0, 1))
    var rng := RandomNumberGenerator.new()
    rng.seed = seed_v

    _sky(img)
    _clouds(img, rng)
    _gulls(img)
    _far_shore(img, rng)
    _water(img, rng)
    _bluff(img, rng)
    _fort(img)
    _reflection(img, rng)
    _foreground(img, rng)
    _vignette(img)
    return ImageTexture.create_from_image(img)


## ---------------------------------------------------------------- utilities

static func _px(img: Image, x: int, y: int, c: Color) -> void:
    if x < 0 or y < 0 or x >= BW or y >= BH:
        return
    if c.a >= 1.0:
        img.set_pixel(x, y, c)
    elif c.a > 0.0:
        img.set_pixel(x, y, img.get_pixel(x, y).lerp(c, c.a))


static func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
    for y in range(maxi(0, y0), mini(BH, y1)):
        for x in range(maxi(0, x0), mini(BW, x1)):
            _px(img, x, y, c)


const BAYER := [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]


static func _dither(c: Color, x: int, y: int, levels: float) -> Color:
    ## Ordered dither, which is what gives the sky its banded, printed look
    ## instead of a smooth 24-bit ramp that reads as "gradient rectangle".
    var b: float = (float(BAYER[y % 4][x % 4]) / 16.0 - 0.5) / levels
    return Color(
        clampf(round((c.r + b) * levels) / levels, 0.0, 1.0),
        clampf(round((c.g + b) * levels) / levels, 0.0, 1.0),
        clampf(round((c.b + b) * levels) / levels, 0.0, 1.0),
        1.0)


static func _glow_at(x: float, y: float, rx: float, ry: float) -> float:
    var dx := (x - SUN_X) / rx
    var dy := (y - SUN_Y) / ry
    var d := sqrt(dx * dx + dy * dy)
    return clampf(1.0 - d, 0.0, 1.0)


## -------------------------------------------------------------------- sky

static func _sky(img: Image) -> void:
    for y in range(0, HORIZON):
        var t := float(y) / float(HORIZON)
        var base: Color
        if t < 0.55:
            base = SKY_HIGH.lerp(SKY_MID, t / 0.55)
        elif t < 0.85:
            base = SKY_MID.lerp(SKY_LOW, (t - 0.55) / 0.30)
        else:
            base = SKY_LOW.lerp(SKY_HAZE, (t - 0.85) / 0.15)
        for x in range(BW):
            var g := _glow_at(float(x), float(y), 110.0, 74.0)
            g = g * g * 0.95
            var c := base.lerp(GLOW, g)
            _px(img, x, y, _dither(c, x, y, 13.0))


static func _clouds(img: Image, rng: RandomNumberGenerator) -> void:
    ## Five ragged bands, each thinner and warmer as it nears the horizon.
    for b in range(5):
        var cy := 26.0 + float(b) * 15.0
        var th := 7.0 - float(b) * 0.9
        var warm := float(b) / 4.0
        for x in range(BW):
            var fx := float(x)
            var wob := sin(fx * 0.041 + float(b) * 2.7) * 3.4 \
                + sin(fx * 0.113 + float(b) * 5.1) * 1.9 \
                + sin(fx * 0.257 + float(b) * 1.3) * 0.9
            var top := cy + wob
            var bot := top + th * (0.55 + 0.55 * sin(fx * 0.033 + float(b) * 3.9))
            if bot <= top:
                continue
            for y in range(int(top), int(bot) + 1):
                if y < 0 or y >= HORIZON:
                    continue
                var g := _glow_at(fx, float(y), 118.0, 82.0)
                var edge := 1.0 if (y > int(top) and y < int(bot)) else 0.55
                var c := CLOUD_DARK.lerp(CLOUD_LIT, warm * 0.7 + g * 0.6)
                c = c.lerp(GLOW, g * g * 0.55)
                var under := img.get_pixel(x, y)
                _px(img, x, y, _dither(under.lerp(c, 0.80 * edge), x, y, 13.0))


static func _gulls(img: Image) -> void:
    ## Three birds, off to the right so they never crowd the lettering.
    var pts := [Vector2i(186, 41), Vector2i(203, 49), Vector2i(172, 56)]
    var c := Color(0.118, 0.125, 0.157)
    for p in pts:
        _px(img, p.x - 2, p.y - 1, c)
        _px(img, p.x - 1, p.y, c)
        _px(img, p.x, p.y, c)
        _px(img, p.x + 1, p.y, c)
        _px(img, p.x + 2, p.y - 1, c)


## ------------------------------------------------------------- the far side

static func _far_shore(img: Image, rng: RandomNumberGenerator) -> void:
    ## The opposite bank of the narrows: a low dark ridge with a fringe of
    ## spruce, sitting right on the horizon.
    for x in range(BW):
        var fx := float(x)
        var ridge := float(HORIZON) - 4.0 \
            - 2.6 * sin(fx * 0.023 + 0.7) \
            - 1.4 * sin(fx * 0.071 + 2.2)
        if x > BLUFF_X - 30:
            ridge += float(x - (BLUFF_X - 30)) * 0.10  ## it dips away behind the fort
        var top := int(ridge)
        var g := _glow_at(fx, float(HORIZON) - 5.0, 130.0, 90.0)
        var col := Color(0.098, 0.110, 0.137).lerp(Color(0.243, 0.216, 0.212), g * 0.7)
        for y in range(top, HORIZON):
            _px(img, x, y, col)
        ## the spruce fringe
        if (x % 3) == 0:
            var h := 2 + int(rng.randf() * 4.0)
            for k in range(h):
                _px(img, x, top - k, col.darkened(0.25))
                if k < h - 1:
                    _px(img, x + 1, top - k, col.darkened(0.15))


## ------------------------------------------------------------------- water

static func _water(img: Image, rng: RandomNumberGenerator) -> void:
    for y in range(HORIZON, FG_TOP + 6):
        var t := float(y - HORIZON) / float(FG_TOP + 6 - HORIZON)
        var base := WATER_FAR.lerp(WATER_NEAR, pow(t, 0.65))
        for x in range(BW):
            var fx := float(x)
            ## the glitter column: wide at the bottom, pinched at the horizon
            var spread := 7.0 + t * 78.0
            var col_u := clampf(1.0 - absf(fx - SUN_X) / spread, 0.0, 1.0)
            col_u = pow(col_u, 1.5) * pow(1.0 - t, 1.1)
            var c := base.lerp(WATER_GLINT, col_u * 0.85)
            _px(img, x, y, _dither(c, x, y, 12.0))

    ## broken chop: short horizontal dashes, denser and longer nearer the eye
    for i in range(340):
        var t := pow(rng.randf(), 0.55)
        var y := HORIZON + 1 + int(t * float(FG_TOP + 4 - HORIZON))
        var x := int(rng.randf() * float(BW))
        var ln := 1 + int(t * 5.0 + rng.randf() * 2.0)
        var col_u := clampf(1.0 - absf(float(x) - SUN_X) / (10.0 + t * 86.0), 0.0, 1.0)
        var c: Color
        if col_u > 0.05 and rng.randf() < 0.55 + col_u * 0.45:
            c = WATER_GLINT.lerp(Color(1, 1, 1), 0.15 * col_u)
            c.a = 0.35 + col_u * 0.55
        else:
            c = Color(0.408, 0.424, 0.463)
            c.a = 0.18 + 0.20 * rng.randf()
        for k in range(ln):
            _px(img, x + k, y, c)


## ------------------------------------------------------------- the headland

static func _bluff_top(x: int) -> int:
    ## The rock line the fort stands on: a sloped shoulder rising out of the
    ## water on the left, then flat under the walls.
    if x < BLUFF_X - 34:
        return 10000
    if x < BLUFF_X:
        var u := float(x - (BLUFF_X - 34)) / 34.0
        return int(lerpf(float(HORIZON) + 8.0, float(BLUFF_TOP), u * u))
    return BLUFF_TOP


static func _bluff(img: Image, rng: RandomNumberGenerator) -> void:
    for x in range(BLUFF_X - 34, BW):
        var top := _bluff_top(x)
        if top > 9000:
            continue
        var foot := BLUFF_FOOT + int(2.0 * sin(float(x) * 0.06))
        for y in range(top, foot):
            var d := float(y - top) / maxf(1.0, float(foot - top))
            var g := _glow_at(float(x), float(y), 120.0, 60.0)
            var c := ROCK_MID.lerp(ROCK_DARK, d * 0.85)
            c = c.lerp(RIM, g * 0.16 * (1.0 - d))
            ## granite is bedded, and the beds are not a spirit level: the
            ## seam wanders with x or the whole headland reads as tarmac.
            if ((y - top + int(3.0 * sin(float(x) * 0.047))) % 5) == 0:
                c = c.lightened(0.10)
            if rng.randf() < 0.10:
                c = c.lightened(0.12)
            _px(img, x, y, c)
        ## A lit crest along the top edge — but only on the open shoulder.
        ## Under the fort the glacis covers it, and running it flat all the
        ## way across drew a ruler-straight bright line that read as a road.
        if x < 170:
            var crest := ROCK_LIT.lerp(RIM, _glow_at(float(x), float(top), 120.0, 60.0) * 0.5)
            _px(img, x, top, crest.darkened(0.25 * rng.randf()))

    ## boulders fallen to the tideline, so the rock does not simply stop
    for i in range(22):
        var rx := BLUFF_X - 40 + int(rng.randf() * float(BW - BLUFF_X + 46))
        var ry := BLUFF_FOOT - 3 + int(rng.randf() * 5.0)
        var rw := 2 + int(rng.randf() * 4.0)
        var rh := 1 + int(rng.randf() * 3.0)
        for yy in range(ry, ry + rh):
            for xx in range(rx, rx + rw):
                _px(img, xx, yy, ROCK_MID.darkened(0.15 + 0.35 * rng.randf()))
        _px(img, rx, ry, ROCK_LIT.lerp(RIM, 0.20))

    ## a small stand of spruce on the shoulder, in front of the wall
    for i in range(9):
        var bx := BLUFF_X - 30 + i * 5 + int(rng.randf() * 3.0)
        var by := _bluff_top(bx)
        if by > 9000:
            continue
        _pine(img, bx, by, 7 + int(rng.randf() * 7.0))


static func _pine(img: Image, bx: int, by: int, h: int) -> void:
    for k in range(h):
        var w := int(round(float(k) / float(h) * 3.4))
        var y := by - h + k
        for dx in range(-w, w + 1):
            _px(img, bx + dx, y, PINE)
    _px(img, bx, by - h - 1, PINE)


## -------------------------------------------------------------------- fort

static func _fort(img: Image) -> void:
    var base := BLUFF_TOP

    ## --- the curtain wall ---------------------------------------------
    var cx0 := 194
    var cx1 := 284
    var cy0 := 70
    _wall(img, cx0, cy0, cx1, base)

    ## battlements along the curtain top
    var x := cx0
    while x < cx1:
        _rect(img, x, cy0 - 5, mini(x + 5, cx1), cy0, ROCK_DARK.lightened(0.06))
        for k in range(mini(5, cx1 - x)):
            _px(img, x + k, cy0 - 5, RIM.darkened(0.15))
        x += 9

    ## casemate arches along the ground floor
    var a := cx0 + 6
    while a + 7 <= cx1 - 6:
        _arch(img, a, base - 15, 7, 15)
        a += 14
    ## the sally port, taller, dead centre
    _arch(img, (cx0 + cx1) / 2 - 5, base - 20, 11, 20)

    ## upper-tier gun embrasures
    var e := cx0 + 9
    while e < cx1 - 8:
        _rect(img, e, cy0 + 6, e + 2, cy0 + 13, Color(0.043, 0.047, 0.055))
        e += 14

    ## --- landward demi-bastion ----------------------------------------
    _wall(img, 172, 82, 196, base)
    var b := 172
    while b < 196:
        _rect(img, b, 78, mini(b + 4, 196), 82, ROCK_DARK)
        for k in range(mini(4, 196 - b)):
            _px(img, b + k, 78, RIM.darkened(0.30))
        b += 8

    ## --- the corner tower ---------------------------------------------
    _wall(img, 282, 54, 304, base, true)  ## the tower alone stands clear of the sky
    var t := 282
    while t < 304:
        _rect(img, t, 49, mini(t + 5, 304), 54, ROCK_DARK.lightened(0.06))
        for k in range(mini(5, 304 - t)):
            _px(img, t + k, 49, RIM)
        t += 9
    ## tower windows — the only lamps lit on this coast
    _rect(img, 288, 62, 291, 67, WINDOW)
    _rect(img, 295, 62, 298, 67, WINDOW.darkened(0.25))
    _rect(img, 291, 76, 294, 82, WINDOW.darkened(0.45))
    _arch(img, 288, base - 13, 8, 13)

    ## --- the banner ----------------------------------------------------
    for y in range(30, 49):
        _px(img, 293, y, Color(0.145, 0.129, 0.118))
    for y in range(32, 43):
        var w := 11 - int(absf(float(y) - 37.0) * 0.6)
        for k in range(1, w):
            var frayed := (y > 39 and k > w - 3 and ((y + k) % 2) == 0)
            if frayed:
                continue
            _px(img, 293 - k, y, BANNER.lerp(Color(0.208, 0.075, 0.086), float(k) / 11.0))

    ## --- the glacis the walls stand on ---------------------------------
    ## Earth banked against the wall foot, not a kerb: the top edge wanders,
    ## the face darkens as it falls, and only the odd stone catches the sky.
    for gx in range(166, BW):
        var h := 5 + int(2.4 * sin(float(gx) * 0.09) + 1.6 * sin(float(gx) * 0.31))
        for gy in range(base, base + h):
            var d := float(gy - base) / maxf(1.0, float(h))
            var c := ROCK_DARK.lerp(ROCK_MID, 0.30 * (1.0 - d))
            if gy == base and ((gx * 7919) % 5) == 0:
                c = c.lerp(RIM, 0.22)
            _px(img, gx, gy, c)


static func _wall(img: Image, x0: int, y0: int, x1: int, y1: int, rim_right := false) -> void:
    ## A block of cut granite lit only by what is left of the sky behind it.
    for y in range(y0, y1):
        for x in range(x0, x1):
            var g := _glow_at(float(x), float(y), 150.0, 130.0)
            var v := float(y - y0) / maxf(1.0, float(y1 - y0))
            var c := Color(0.129, 0.133, 0.149).lerp(Color(0.055, 0.059, 0.071), v)
            c = c.lerp(RIM, g * 0.13)
            ## coursed stone: a seam every four rows, a joint every eight
            if ((y - y0) % 4) == 0:
                c = c.lightened(0.13)
            if ((x - x0 + ((y - y0) / 4) * 4) % 8) == 0:
                c = c.darkened(0.16)
            _px(img, x, y, c)
    ## Only the TOP edge catches the sky. An earlier pass rimmed the left and
    ## right edges too and every wall grew a bright vertical stripe down it —
    ## nine feet of scaffolding pole on a granite fort.
    for x in range(x0, x1):
        _px(img, x, y0, ROCK_LIT.lerp(RIM, 0.45))
    if rim_right:
        for y in range(y0, y1):
            var g := _glow_at(float(x1), float(y), 150.0, 130.0)
            _px(img, x1 - 1, y, ROCK_MID.lerp(RIM, 0.16 + g * 0.24))


static func _arch(img: Image, x: int, y: int, w: int, h: int) -> void:
    ## A casemate mouth: square below, rounded above, black inside, with a
    ## pale voussoir line around the head.
    var r := int(float(w) / 2.0)
    var cx := x + r
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            var inside := true
            if yy < y + r:
                var dx := float(xx - cx) + 0.5
                var dy := float(yy - (y + r)) + 0.5
                if sqrt(dx * dx + dy * dy) > float(r) + 0.4:
                    inside = false
            if inside:
                var d := float(yy - y) / float(h)
                _px(img, xx, yy, Color(0.024, 0.027, 0.035).lerp(Color(0.071, 0.055, 0.043), d * 0.5))
    for k in range(w + 2):
        var xx := x - 1 + k
        var dx := float(xx - cx) + 0.5
        var yy := y + r - int(sqrt(maxf(0.0, float((r + 1) * (r + 1)) - dx * dx)))
        _px(img, xx, yy, ROCK_LIT.lerp(RIM, 0.25))


## -------------------------------------------------------------- reflection

static func _reflection(img: Image, rng: RandomNumberGenerator) -> void:
    ## The headland thrown back at you, smeared sideways and dimmed. Only the
    ## bottom third of the fort makes it into the water — the rest is broken
    ## up by the chop long before it gets there.
    var mirror_y := BLUFF_FOOT
    for y in range(mirror_y, mini(FG_TOP, mirror_y + 26)):
        var d := float(y - mirror_y)
        var src := mirror_y - int(d * 1.35) - 1
        if src < 40:
            continue
        var fade := clampf(1.0 - d / 26.0, 0.0, 1.0)
        var wob := int(round(2.6 * sin(float(y) * 0.55) + 1.4 * sin(float(y) * 1.31)))
        for x in range(BLUFF_X - 34, BW):
            var sc := img.get_pixel(clampi(x + wob, 0, BW - 1), clampi(src, 0, BH - 1))
            var under := img.get_pixel(x, y)
            var c := under.lerp(sc.darkened(0.30), fade * 0.62)
            if rng.randf() < 0.10:
                c = c.lerp(under, 0.7)  ## chop tears holes in it
            _px(img, x, y, c)


## -------------------------------------------------------------- foreground

static func _foreground(img: Image, rng: RandomNumberGenerator) -> void:
    ## The ledge you are standing on. Nearly black, because it is behind you
    ## as far as the light is concerned, and because the menu needs a floor.
    for x in range(BW):
        var fx := float(x)
        var top := float(FG_TOP) \
            - 5.0 * sin(fx * 0.019 + 1.1) \
            - 2.4 * sin(fx * 0.083 + 0.3) \
            - 1.2 * sin(fx * 0.211 + 2.6)
        var ti := int(top)
        ## wet stone catches one line of the last light
        _px(img, x, ti, Color(0.212, 0.204, 0.196).lerp(RIM, _glow_at(fx, top, 150.0, 90.0) * 0.35))
        for y in range(ti + 1, BH):
            var d := float(y - ti) / float(BH - ti)
            var c := Color(0.055, 0.059, 0.067).lerp(Color(0.020, 0.024, 0.031), d)
            if rng.randf() < 0.055:
                c = c.lightened(0.10 + 0.16 * rng.randf())
            _px(img, x, y, c)

    ## two spruce leaning in from the bottom right, for depth
    _pine(img, 296, 176, 34)
    _pine(img, 311, 180, 44)


static func _vignette(img: Image) -> void:
    ## Corners pulled down, and the left third pulled down further still —
    ## that darkness is not decoration, it is the page the title is set on.
    for y in range(BH):
        for x in range(BW):
            var u := (float(x) / float(BW) - 0.5) * 2.0
            var v := (float(y) / float(BH) - 0.5) * 2.0
            var r := sqrt(u * u * 0.85 + v * v)
            var k := clampf((r - 0.55) / 0.85, 0.0, 1.0)
            k = k * k * 0.72
            var left := clampf(1.0 - float(x) / 150.0, 0.0, 1.0)
            k = clampf(k + left * left * 0.34, 0.0, 0.92)
            var c := img.get_pixel(x, y)
            _px(img, x, y, c.lerp(Color(0.016, 0.020, 0.031), k))
