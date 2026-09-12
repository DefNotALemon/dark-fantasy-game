#!/usr/bin/env python3
"""
groundsheet.py — tileable ground textures for Myrkfell, as a labeled contact sheet.

Two axes:
  rows    = ART STYLE   (one per game on the inspiration list + the two house styles)
  columns = GROUND TYPE (the Maine ground the world base actually needs)

Every tile is a seamless 256x256 texture built from PERIODIC noise, so any cell on the
sheet can be dropped straight onto the terrain as a repeating albedo.  The same material
(a "ground type") is rendered once per style: the style only changes resolution, palette,
lighting model and post-processing — so a column reads as one ground across the sheet.

    python3 groundsheet.py            -> out/ground_sheet.png + out/tiles/*.png + out/tiles.zip
    python3 groundsheet.py --size 128 -> smaller tiles (faster)

Pure numpy + Pillow + scipy.ndimage.  No assets, no downloads.
"""
import os, sys, zipfile, json, argparse
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import uniform_filter, gaussian_filter

# ----------------------------------------------------------------------------- noise ---

def _fade(t):
    return t * t * t * (t * (t * 6 - 15) + 10)

def pnoise(size, px, py, rng):
    """Periodic gradient (Perlin) noise. px / py = integer cells across the tile on each axis.
    Because the gradient lattice wraps, the result tiles exactly. Range ~[-0.7, 0.7]."""
    px, py = max(1, int(px)), max(1, int(py))
    g = rng.normal(size=(py, px, 2))
    g /= np.linalg.norm(g, axis=-1, keepdims=True) + 1e-9
    xs = np.linspace(0, px, size, endpoint=False)
    ys = np.linspace(0, py, size, endpoint=False)
    x, y = np.meshgrid(xs, ys)
    xi, yi = np.floor(x).astype(int), np.floor(y).astype(int)
    xf, yf = x - xi, y - yi

    def dot(ix, iy, dx, dy):
        gg = g[iy % py, ix % px]
        return gg[..., 0] * dx + gg[..., 1] * dy

    n00 = dot(xi, yi, xf, yf)
    n10 = dot(xi + 1, yi, xf - 1, yf)
    n01 = dot(xi, yi + 1, xf, yf - 1)
    n11 = dot(xi + 1, yi + 1, xf - 1, yf - 1)
    u, v = _fade(xf), _fade(yf)
    return (n00 * (1 - u) + n10 * u) * (1 - v) + (n01 * (1 - u) + n11 * u) * v

def fbm(size, px, py, rng, octaves=4, gain=0.5, lac=2.0):
    """Periodic fractal noise, normalised to roughly [-1, 1]."""
    out, amp, tot = np.zeros((size, size)), 1.0, 0.0
    for _ in range(octaves):
        out += amp * pnoise(size, px, py, rng)
        tot += amp * 0.7
        amp *= gain
        px, py = px * lac, py * lac
    return out / tot

def ridged(size, px, py, rng, octaves=3):
    """1 - |noise| stacked: sharp creases (cracks, root lines, ripples)."""
    out, amp, tot = np.zeros((size, size)), 1.0, 0.0
    for _ in range(octaves):
        out += amp * (1 - np.abs(pnoise(size, px, py, rng)) / 0.7)
        tot += amp
        amp *= 0.5
        px, py = px * 2, py * 2
    return out / tot

def worley(size, n, rng, jitter=1.0):
    """Periodic cellular noise. Returns (d1, d2, cell_id): distance to the nearest and
    second-nearest of n wrapped feature points (in tile units, tile = 1.0) and the id of
    the nearest one, so every cell can get its own colour."""
    pts = rng.random((n, 2)) * jitter + (1 - jitter) * 0.5
    ys, xs = np.mgrid[0:size, 0:size] / size
    d1 = np.full((size, size), 9.0)
    d2 = np.full((size, size), 9.0)
    idx = np.zeros((size, size), dtype=int)
    for i, (cx, cy) in enumerate(pts):
        for ox in (-1, 0, 1):
            for oy in (-1, 0, 1):
                d = np.hypot(xs - (cx + ox), ys - (cy + oy))
                closer = d < d1
                d2 = np.where(closer, d1, np.minimum(d2, d))
                idx = np.where(closer, i, idx)
                d1 = np.where(closer, d, d1)
    return d1, d2, idx

def clamp01(a):
    return np.clip(a, 0.0, 1.0)

def col(r, g, b):
    return np.array([r, g, b], dtype=float)

def blend(a, b, t):
    """lerp two HxWx3 images (or colour + image) by an HxW mask."""
    t = t[..., None] if t.ndim == 2 else t
    return a * (1 - t) + b * t

def shade_from_height(h, strength, light=(-0.6, -0.8)):
    """Cheap directional lighting off a height field (wrapped gradients, so it tiles)."""
    dx = np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)
    dy = np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)
    s = 1.0 + strength * (dx * light[0] + dy * light[1]) * 14.0
    return np.clip(s, 0.45, 1.6)

# ------------------------------------------------------------------------- materials ---
# Each material returns a dict:
#   base   HxWx3  the colour without fine grain        (macro + mid frequencies)
#   fine   HxW    signed fine detail (blades, grain)    style multiplies this in
#   height HxW    height field for the lighting model
#   accent HxW    0..1 mask of "accent" pixels (flowers, lichen, pebbles, ember leaves)
#   accent_rgb    the natural colour of those accents (house styles may recolour them)

def grass_layers(size, rng, green, var_amt=0.12, blade_amt=1.0, clump=1.0):
    macro = fbm(size, 2, 2, rng, 3)
    mid = fbm(size, 7, 7, rng, 3)
    d1, _, cid = worley(size, 60, rng)
    cell_var = rng.random(60)[cid] - 0.5                 # each tuft its own tone
    tuft = clamp01(1 - d1 / 0.11)                        # bright tuft centres
    base = green[None, None, :] * (1 + var_amt * macro[..., None] * 1.6
                                   + 0.08 * mid[..., None]
                                   + clump * (0.07 * cell_var + 0.06 * tuft)[..., None])
    # yellow-green sun tips vs blue-green shade
    warm = col(0.10, 0.06, -0.06)
    base = base + warm[None, None, :] * (macro * 0.5 + tuft * 0.6 * clump)[..., None] * 0.25
    # blades: strongly anisotropic noise (tall thin), two layers of thickness
    blades = (fbm(size, 40, 8, rng, 2) * 0.7 + fbm(size, 80, 14, rng, 2) * 0.5) * blade_amt
    height = macro * 0.3 + tuft * 0.5 * clump + blades * 0.25
    return base, blades, height, tuft

def dirt_layers(size, rng, brown, pebbles=40, grain=1.0, crack=0.0):
    macro = fbm(size, 3, 3, rng, 3)
    mid = fbm(size, 9, 9, rng, 3)
    base = brown[None, None, :] * (1 + 0.16 * macro[..., None] + 0.07 * mid[..., None])
    # damp patches go darker + slightly redder
    damp = clamp01(fbm(size, 4, 4, rng, 2) * 1.2 + 0.1)
    base = base * (1 - 0.18 * damp[..., None]) + col(0.02, 0.0, -0.01)[None, None, :] * damp[..., None]
    d1, _, cid = worley(size, pebbles, rng)
    pr = 0.012 + 0.02 * rng.random(pebbles)[cid]
    peb = clamp01((pr - d1) / 0.006)                      # small hard stones
    peb_col = (0.55 + 0.3 * rng.random(pebbles)[cid])[..., None] * col(0.52, 0.50, 0.46)[None, None, :]
    base = blend(base, peb_col, peb * 0.85)
    grainn = (fbm(size, 48, 48, rng, 2) * 0.8 + fbm(size, 96, 96, rng, 1) * 0.4) * grain
    height = macro * 0.25 + peb * 0.9 + grainn * 0.15
    if crack > 0:
        cr = clamp01((ridged(size, 3, 3, rng, 2) - 0.78) / 0.06)
        base = base * (1 - 0.35 * crack * cr[..., None])
        height = height - 0.6 * crack * cr
    return base, grainn, height, peb

def mat_lush(size, rng):
    base, blades, h, tuft = grass_layers(size, rng, col(0.30, 0.52, 0.17), 0.12, 1.0, 1.0)
    # clover-ish darker rounds + a few wildflowers
    d1, _, cid = worley(size, 24, rng)
    clover = clamp01(1 - d1 / 0.05) * (rng.random(24)[cid] > 0.6)
    base = blend(base, col(0.22, 0.42, 0.14)[None, None, :] * np.ones_like(base), clover * 0.7)
    d1f, _, cidf = worley(size, 70, rng)
    fl = clamp01((0.006 - d1f) / 0.003) * (rng.random(70)[cidf] > 0.72)
    return dict(base=base, fine=blades, height=h, accent=fl, accent_rgb=col(0.95, 0.92, 0.55))

def mat_dry(size, rng):
    base, blades, h, tuft = grass_layers(size, rng, col(0.66, 0.58, 0.30), 0.10, 1.3, 0.8)
    # olive dips between the straw, seed heads as pale specks
    dip = clamp01(fbm(size, 5, 5, rng, 2) * 1.5)
    base = blend(base, col(0.48, 0.47, 0.24)[None, None, :] * np.ones_like(base), dip * 0.55)
    d1, _, cid = worley(size, 90, rng)
    heads = clamp01((0.007 - d1) / 0.003) * (rng.random(90)[cid] > 0.5)
    return dict(base=base, fine=blades, height=h, accent=heads, accent_rgb=col(0.88, 0.80, 0.55))

def mat_patchy(size, rng):
    g, gb, gh, tuft = grass_layers(size, rng, col(0.36, 0.50, 0.18), 0.10, 1.0, 1.0)
    d, dg, dh, peb = dirt_layers(size, rng, col(0.44, 0.34, 0.22), 30, 1.0)
    cover = clamp01((fbm(size, 3, 3, rng, 3) * 1.3 + 0.05) / 0.35 + 0.5)   # soft threshold
    cover = clamp01(cover + tuft * 0.15 - 0.05)
    base = blend(d, g, cover)
    fine = gb * cover + dg * (1 - cover)
    h = gh * cover + dh * (1 - cover) - 0.3 * (1 - cover)
    # worn edge: dirt just under the grass lip is a shade darker
    lip = clamp01(1 - np.abs(cover - 0.5) / 0.12)
    base = base * (1 - 0.15 * lip[..., None])
    return dict(base=base, fine=fine, height=h, accent=peb * (1 - cover), accent_rgb=col(0.6, 0.58, 0.54))

def mat_dirt(size, rng):
    base, grain, h, peb = dirt_layers(size, rng, col(0.45, 0.34, 0.22), 45, 1.0, 0.35)
    # boot / hoof compaction: broad smooth lows
    return dict(base=base, fine=grain, height=h, accent=peb, accent_rgb=col(0.62, 0.60, 0.56))

def mat_mud(size, rng):
    base, grain, h, peb = dirt_layers(size, rng, col(0.27, 0.20, 0.14), 12, 0.6)
    ruts = fbm(size, 2, 11, rng, 3)                      # long horizontal ruts
    h = h * 0.4 + ruts * 0.35
    base = base * (1 + 0.06 * ruts[..., None])
    # standing water in the lows: darker, bluer, and it will catch the light
    pud = clamp01((-ruts - 0.25) / 0.2) * clamp01(fbm(size, 3, 3, rng, 2) * 2 + 0.6)
    water = col(0.20, 0.20, 0.20)
    base = blend(base, water[None, None, :] * np.ones_like(base), pud * 0.7)
    h = h - pud * 0.5
    return dict(base=base, fine=grain * 0.5 + ruts * 0.3, height=h, accent=pud, accent_rgb=col(0.42, 0.47, 0.52), gloss=pud)

def mat_forest_floor(size, rng):
    base, grain, h, _ = dirt_layers(size, rng, col(0.34, 0.24, 0.14), 8, 0.7)
    # needle drifts at two angles (rotate by sampling anisotropic noise on rotated coords)
    n1 = fbm(size, 36, 6, rng, 2)
    n2 = fbm(size, 6, 36, rng, 2)
    needles = np.maximum(n1, n2 * 0.9)
    base = base * (1 + 0.22 * needles[..., None]) + col(0.10, 0.05, 0.0)[None, None, :] * clamp01(needles)[..., None] * 0.5
    # leaf litter: flat rounded blobs in ochre / russet
    d1, _, cid = worley(size, 40, rng)
    lr = 0.025 + 0.02 * rng.random(40)[cid]
    leaf = clamp01((lr - d1) / 0.004) * (rng.random(40)[cid] > 0.35)
    tone = rng.random(40)[cid]
    leaf_col = (col(0.50, 0.34, 0.14)[None, None, :] * (1 - tone[..., None])
                + col(0.52, 0.26, 0.12)[None, None, :] * tone[..., None])
    base = blend(base, leaf_col, leaf * 0.75)
    # roots
    root = clamp01((ridged(size, 2, 2, rng, 2) - 0.87) / 0.05)
    base = blend(base, col(0.28, 0.20, 0.12)[None, None, :] * np.ones_like(base), root * 0.8)
    h = h * 0.4 + needles * 0.25 + leaf * 0.3 + root * 0.45
    ember = leaf * (tone > 0.72)                          # only the freshest-fallen leaves glow
    return dict(base=base, fine=grain * 0.5 + needles * 0.6, height=h, accent=ember, accent_rgb=col(0.64, 0.34, 0.12))

def mat_barrens(size, rng):
    # Downeast blueberry barrens: low red-green shrub mat, lichen, granite showing through
    base, grain, h, _ = dirt_layers(size, rng, col(0.36, 0.26, 0.18), 10, 0.6)
    shrub = clamp01(fbm(size, 5, 5, rng, 3) * 1.4 + 0.3)
    d1, _, cid = worley(size, 50, rng)
    knots = clamp01(1 - d1 / 0.07) * shrub
    shrub_col = col(0.30, 0.36, 0.14)[None, None, :] * (1 + 0.3 * (rng.random(50)[cid] - 0.5))[..., None]
    red = col(0.50, 0.20, 0.14)[None, None, :]
    shrub_rgb = blend(shrub_col, red * np.ones_like(base), clamp01((fbm(size, 4, 4, rng, 2) - 0.1) * 1.6))
    base = blend(base, shrub_rgb, clamp01(shrub * 0.8 + knots * 0.4))
    # granite
    rock = clamp01((fbm(size, 2, 2, rng, 2) - 0.35) / 0.12)
    rock_rgb = col(0.58, 0.56, 0.54)[None, None, :] * (1 + 0.15 * fbm(size, 24, 24, rng, 2))[..., None]
    base = blend(base, rock_rgb, rock)
    # lichen specks on rock and shrub edge
    d1l, _, cidl = worley(size, 120, rng)
    lich = clamp01((0.009 - d1l) / 0.003) * (rng.random(120)[cidl] > 0.45)
    h = h * 0.3 + knots * 0.6 + rock * 0.5 + shrub * 0.2
    return dict(base=base, fine=grain * 0.6 + fbm(size, 40, 40, rng, 2) * 0.4, height=h,
                accent=lich, accent_rgb=col(0.80, 0.84, 0.70))

def mat_gravel(size, rng):
    n = 150
    d1, d2, cid = worley(size, n, rng)
    tone = rng.random(n)[cid]
    R = (0.05 + 0.03 * rng.random(n))[cid]                # each stone its own radius
    edge = clamp01((d2 - d1) / 0.03)                      # 0 on the joins between stones
    dome = clamp01(np.minimum(edge, 1 - d1 / R))          # a round cap clipped by its neighbours
    grey = col(0.47, 0.45, 0.42)[None, None, :] * (0.65 + 0.4 * tone)[..., None]
    pink = col(0.60, 0.48, 0.44)[None, None, :]           # Maine granite has feldspar in it
    stone = blend(grey, pink * np.ones_like(grey), (rng.random(n)[cid] > 0.8) * 0.6)
    gap = col(0.26, 0.23, 0.20)[None, None, :] * np.ones_like(grey)
    base = blend(gap, stone, clamp01(dome * 3))
    spec = fbm(size, 60, 60, rng, 2)
    h = np.sqrt(dome) * 0.35 + spec * 0.05
    return dict(base=base, fine=spec * 0.7, height=h, accent=(tone > 0.9) * clamp01(dome * 3), accent_rgb=col(0.68, 0.66, 0.62))

def mat_sand(size, rng):
    macro = fbm(size, 2, 2, rng, 2)
    ripple = np.sin((np.linspace(0, 1, size, endpoint=False)[:, None] * 7
                     + fbm(size, 2, 2, rng, 2) * 0.6) * 2 * np.pi)             # wind ripples
    ripple = ripple * clamp01(fbm(size, 2, 2, rng, 2) * 1.5 + 0.7)
    base = col(0.80, 0.71, 0.52)[None, None, :] * (1 + 0.07 * macro[..., None] + 0.025 * ripple[..., None])
    wet = clamp01(fbm(size, 2, 2, rng, 2) * 1.4 - 0.15)
    base = base * (1 - 0.25 * wet[..., None])
    grain = fbm(size, 64, 64, rng, 2) * 0.8 + fbm(size, 128, 128, rng, 1) * 0.5
    d1, _, cid = worley(size, 40, rng)
    shell = clamp01((0.008 - d1) / 0.003) * (rng.random(40)[cid] > 0.6)
    h = ripple * 0.10 + macro * 0.15 + grain * 0.05 + shell * 0.4
    return dict(base=base, fine=grain, height=h, accent=shell, accent_rgb=col(0.35, 0.30, 0.26))

def mat_moss(size, rng):
    d1, d2, cid = worley(size, 45, rng)
    n = 45
    dome = clamp01(1 - d1 / 0.11) ** 0.6                   # sphagnum cushions
    tone = rng.random(n)[cid]
    green = col(0.30, 0.42, 0.14)[None, None, :] * (0.8 + 0.4 * tone)[..., None]
    yellow = col(0.58, 0.55, 0.18)[None, None, :]
    moss = blend(green, yellow * np.ones_like(green), (tone > 0.7)[..., None] * 0.5 * dome[..., None])
    peat = col(0.16, 0.12, 0.08)[None, None, :] * np.ones_like(green)
    base = blend(peat, moss, clamp01(dome * 1.4))
    fuzz = fbm(size, 50, 50, rng, 2)
    h = dome * 0.45 + fuzz * 0.12
    # dead bleached sprigs
    d1s, _, cids = worley(size, 80, rng)
    sprig = clamp01((0.006 - d1s) / 0.003) * (rng.random(80)[cids] > 0.6) * dome
    return dict(base=base, fine=fuzz * 0.9, height=h, accent=sprig, accent_rgb=col(0.80, 0.78, 0.60))

def mat_snow(size, rng):
    base, blades, h, tuft = grass_layers(size, rng, col(0.50, 0.46, 0.26), 0.10, 1.0, 0.8)
    cover = clamp01((fbm(size, 3, 3, rng, 3) * 1.3 + 0.35) / 0.3 + 0.4)
    cover = clamp01(cover - tuft * 0.5)                   # tufts poke through
    snow = col(0.88, 0.90, 0.95)[None, None, :] * (1 + 0.04 * fbm(size, 6, 6, rng, 2))[..., None]
    snow = snow - col(0.0, 0.02, 0.06)[None, None, :] * clamp01(-fbm(size, 4, 4, rng, 2))[..., None]   # blue in the hollows
    base = blend(base, snow, cover)
    sparkle = fbm(size, 64, 64, rng, 1)
    fine = blades * (1 - cover) + sparkle * 0.4 * cover
    h = h * (1 - cover) * 0.5 + cover * 0.25 + cover * 0.12 * fbm(size, 5, 5, rng, 2)
    d1, _, cid = worley(size, 60, rng)
    glint = clamp01((0.004 - d1) / 0.002) * (rng.random(60)[cid] > 0.5) * cover
    return dict(base=base, fine=fine, height=h, accent=glint, accent_rgb=col(1.0, 1.0, 1.0))

GROUNDS = [
    ("lush_meadow",  "Lush meadow",        "spring green, clover, wildflowers",     mat_lush),
    ("dry_grass",    "Dry grass / Shelf",  "straw + olive, Aroostook gold",         mat_dry),
    ("patchy",       "Patchy grass-dirt",  "the transition tile",                   mat_patchy),
    ("dirt",         "Packed dirt",        "trodden earth, pebbles, cracks",        mat_dirt),
    ("mud",          "Mud / wet track",    "ruts + puddles",                        mat_mud),
    ("forest_floor", "Forest floor",       "needles, leaf litter, roots",           mat_forest_floor),
    ("barrens",      "Barrens / heath",    "Downeast blueberry mat + lichen",       mat_barrens),
    ("gravel",       "Gravel / scree",     "granite chips, Katahdin talus",         mat_gravel),
    ("sand",         "Sand / beach",       "Casco Bay, wind ripples",               mat_sand),
    ("moss_bog",     "Moss / bog",         "sphagnum cushions over peat",           mat_moss),
    ("snow_dusted",  "Snow-dusted grass",  "the snow line, tufts poking through",   mat_snow),
]

# ---------------------------------------------------------------------------- styles ---

def kuwahara(img, r):
    """Painterly edge-preserving smoothing (wrapped, so it tiles). img HxWx3 float."""
    k = r + 1
    half = (r + 1) // 2
    lum = img.mean(axis=-1)
    m = uniform_filter(lum, size=k, mode="wrap")
    m2 = uniform_filter(lum * lum, size=k, mode="wrap")
    var = m2 - m * m
    means = np.stack([uniform_filter(img[..., c], size=k, mode="wrap") for c in range(3)], axis=-1)
    out = np.zeros_like(img)
    best = np.full(lum.shape, np.inf)
    # four quadrant windows, each centred `half` pixels diagonally off the pixel
    for oy in (-half, half):
        for ox in (-half, half):
            v = np.roll(var, (-oy, -ox), axis=(0, 1))
            mrgb = np.roll(means, (-oy, -ox), axis=(0, 1))
            take = v < best
            best = np.where(take, v, best)
            out = np.where(take[..., None], mrgb, out)
    return out

def bayer(size, n=4):
    m = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0
    reps = size // 4 + 1
    return np.tile(m, (reps, reps))[:size, :size]

def block_down(img, res):
    """Average-pool HxWx3 to res×res, return the small image."""
    H = img.shape[0]
    f = H // res
    return img[:res * f, :res * f].reshape(res, f, res, f, 3).mean(axis=(1, 3))

def block_up(small, size):
    f = size // small.shape[0]
    return np.repeat(np.repeat(small, f, axis=0), f, axis=1)

def saturate(img, s):
    lum = img @ np.array([0.299, 0.587, 0.114])
    return lum[..., None] + (img - lum[..., None]) * s

def contrast(img, c, pivot=0.5):
    return (img - pivot) * c + pivot

def posterize(img, levels):
    return np.round(img * (levels - 1)) / (levels - 1)

def posterize_luma(img, levels, chroma_steps=24):
    """Flat steps in brightness, hue kept: quantise luminance to `levels` and the colour
    offset to a finer grid — dark browns stay brown instead of snapping to maroon."""
    lum = img @ np.array([0.299, 0.587, 0.114])
    chroma = img - lum[..., None]
    lq = np.round(lum * (levels - 1)) / (levels - 1)
    cq = np.round(chroma * chroma_steps) / chroma_steps
    return clamp01(lq[..., None] + cq)

def band_light(shade, tones=4):
    """Flat banded lighting: the psx_ground / grass v2.3 look."""
    lo, hi = 0.55, 1.35
    t = clamp01((shade - lo) / (hi - lo))
    return lo + (np.floor(t * tones) / (tones - 1)).clip(0, 1) * (hi - lo)

def style_render(mat, style, size, rng):
    """Turn a material into a styled RGB tile. `style` is a dict of knobs."""
    base = mat["base"].copy()
    fine = mat["fine"]
    h = mat["height"]
    acc, acc_rgb = mat["accent"], mat["accent_rgb"]

    # --- lighting model -------------------------------------------------------------
    sh_h = gaussian_filter(h, style.get("height_blur", 0.0), mode="wrap") if style.get("height_blur", 0) else h
    shade = shade_from_height(sh_h, style.get("shade", 0.7))
    if style.get("banded"):
        shade = band_light(shade, style.get("bands", 4))
    if style.get("gloss") and "gloss" in mat:            # wet mud catches a highlight
        shade = shade + mat["gloss"] * clamp01(shade - 1.0) * 1.5
    img = base * (1 + style.get("fine", 1.0) * 0.16 * fine[..., None])
    img = img * shade[..., None]

    # --- accents ----------------------------------------------------------------
    a_rgb = style.get("accent_override", None)
    a_rgb = a_rgb if a_rgb is not None else acc_rgb
    img = blend(img, a_rgb[None, None, :] * np.ones_like(img), acc * style.get("accent", 1.0))

    # --- paint pass -------------------------------------------------------------
    if style.get("kuwahara"):
        img = kuwahara(img, style["kuwahara"])
    if style.get("stroke"):
        st = fbm(size, 24, 3, rng, 2)                     # visible brush direction
        img = img * (1 + style["stroke"] * 0.10 * st[..., None])
    if style.get("grain"):
        gr = rng.normal(size=(size, size)) * style["grain"]
        img = img * (1 + gr[..., None])

    # --- palette ----------------------------------------------------------------
    if style.get("tint") is not None:
        t_rgb, t_amt = style["tint"]
        img = img * (1 - t_amt) + t_rgb[None, None, :] * img.mean(axis=-1, keepdims=True) * t_amt * 2.0
    img = saturate(img, style.get("sat", 1.0))
    img = contrast(img, style.get("contrast", 1.0))
    img = img * style.get("bright", 1.0) + style.get("lift", 0.0)
    img = clamp01(img)

    # --- resolution / pixel model ---------------------------------------------------
    res = style.get("res")
    if res and res < size:
        small = block_down(img, res)
        if style.get("pixel_jitter"):
            small = small * (1 + rng.normal(size=small.shape[:2])[..., None] * style["pixel_jitter"])
        if style.get("dither"):
            small = small + (bayer(res) - 0.5)[..., None] * style["dither"]
        if style.get("levels"):
            small = (posterize_luma if style.get("luma") else posterize)(clamp01(small), style["levels"])
        if style.get("palette"):
            small = palette_reduce(clamp01(small), style["palette"], outline=style.get("outline", 0.0))
        img = block_up(clamp01(small), size)
    elif style.get("levels"):
        if style.get("dither"):
            img = img + (bayer(size) - 0.5)[..., None] * style["dither"]
        img = posterize(clamp01(img), style["levels"])
    return clamp01(img)

def palette_reduce(small, n, outline=0.0):
    """Reduce to n colours (median cut via Pillow) and optionally draw a dark 1px edge
    where the colour index changes — the Stardew read."""
    im = Image.fromarray((small * 255).astype(np.uint8), "RGB")
    q = im.quantize(colors=n, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    idx = np.array(q)
    out = np.array(q.convert("RGB")).astype(float) / 255.0
    if outline > 0:
        edge = (idx != np.roll(idx, 1, axis=0)) | (idx != np.roll(idx, 1, axis=1))
        out = out * (1 - outline * edge[..., None])
    return out

# The rows. Each: key, display name, the source on the inspiration list, knobs.
STYLES = [
    ("botw", "Breath of the Wild", "flat painterly, big soft shapes, saturated",
     dict(fine=0.15, shade=0.35, height_blur=2.0, kuwahara=6, sat=1.30, contrast=0.92, bright=1.10, accent=1.0)),
    ("arceus", "Legends: Arceus", "painted, visible strokes, pastel-soft",
     dict(fine=0.35, shade=0.45, height_blur=1.5, kuwahara=4, stroke=1.0, sat=0.92, contrast=0.90, bright=1.06, lift=0.02)),
    ("tsushima", "Ghost of Tsushima", "lush, warm, wind-combed detail",
     dict(fine=1.35, shade=0.75, sat=1.15, contrast=1.08, tint=(col(1.0, 0.92, 0.75), 0.10), bright=1.02)),
    ("skyrim", "Skyrim", "gritty, cool, desaturated realism",
     dict(fine=1.0, shade=0.95, grain=0.035, sat=0.68, contrast=1.15, tint=(col(0.80, 0.88, 1.0), 0.10), bright=0.96)),
    ("rdr2", "Red Dead 2", "photoreal grain, natural colour drift",
     dict(fine=1.15, shade=1.0, grain=0.02, sat=0.88, contrast=1.05, bright=0.98)),
    ("psx", "PSX / PS1", "64 px, 16 levels, ordered dither",
     dict(fine=0.6, shade=0.6, res=64, dither=0.14, levels=16, sat=1.05, contrast=1.05)),
    ("pixeled", "Realistic-pixeled (house)", "grass v2.3 rule: 64 cells, 7 steps, 4 light bands",
     dict(fine=0.8, shade=0.7, banded=True, bands=4, res=64, levels=7, luma=True, pixel_jitter=0.03, sat=1.0, contrast=1.02)),
    ("minecraft", "Minecraft", "16 px, per-pixel noise, no lighting",
     dict(fine=1.0, shade=0.15, res=16, pixel_jitter=0.06, levels=16, sat=1.0, contrast=1.05)),
    ("stardew", "Stardew Valley", "32 px, 8-colour palette, cheerful outlines",
     dict(fine=0.15, shade=0.4, height_blur=1.5, kuwahara=3, res=32, palette=8, outline=0.30, sat=1.25, contrast=1.10, bright=1.04)),
    ("valheim", "Valheim", "128 px, high contrast, moody",
     dict(fine=1.0, shade=1.05, res=128, grain=0.03, sat=0.78, contrast=1.30, bright=0.88, tint=(col(0.85, 0.90, 1.0), 0.12))),
    ("withering", "The Withering (house)", "DESIGN.md: slate/indigo base, ember + frost accents",
     dict(fine=0.7, shade=0.8, banded=True, bands=5, sat=0.55, contrast=1.10, bright=0.90,
          tint=(col(0.30, 0.32, 0.42), 0.28), accent=1.0, accent_override=col(0.88, 0.45, 0.12))),
]
# The Withering row swaps accents to ember-orange, except cold grounds which go frost-blue.
WITHERING_FROST = {"snow_dusted", "mud", "gravel", "sand"}

# ----------------------------------------------------------------------------- sheet ---

def wrap_px(draw, text, fnt, width):
    words, lines, cur = text.split(), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if draw.textlength(t, font=fnt) > width and cur:
            lines.append(cur); cur = w
        else:
            cur = t
    lines.append(cur)
    return lines

def font(sz, bold=True):
    p = "/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf" % ("-Bold" if bold else "")
    try:
        return ImageFont.truetype(p, sz)
    except Exception:
        return ImageFont.load_default()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", type=int, default=256)
    ap.add_argument("--out", default="out")
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()
    S = args.size
    os.makedirs(os.path.join(args.out, "tiles"), exist_ok=True)

    # materials once, seeded per ground so a column is the SAME ground in every style
    mats = {}
    for gi, (gk, gname, gdesc, fn) in enumerate(GROUNDS):
        mats[gk] = fn(S, np.random.default_rng(args.seed * 100 + gi))
        print("material", gk)

    LW, TH, PAD, GAP = 300, 120, 24, 6
    W = LW + PAD + len(GROUNDS) * (S + GAP) + PAD
    H = TH + PAD + len(STYLES) * (S + GAP) + PAD + 40
    sheet = Image.new("RGB", (W, H), (24, 24, 28))
    draw = ImageDraw.Draw(sheet)
    f_title, f_head, f_sub, f_small = font(30), font(19), font(14, False), font(13, False)

    draw.text((PAD, 18), "MYRKFELL  —  ground textures for the world base", font=f_title, fill=(235, 232, 220))
    draw.text((PAD, 58), "rows = art style (from the inspiration list)   ·   columns = ground type   ·   every tile is a seamless %dpx repeat" % S,
              font=f_sub, fill=(170, 170, 165))

    # column headers
    for gi, (gk, gname, gdesc, fn) in enumerate(GROUNDS):
        x = LW + PAD + gi * (S + GAP)
        draw.text((x, TH - 46), gname, font=f_head, fill=(235, 232, 220))
        for li, ln in enumerate(wrap_px(draw, gdesc, f_small, S - 6)[:2]):
            draw.text((x, TH - 22 + li * 15), ln, font=f_small, fill=(160, 160, 155))
        draw.text((x + S - 8, TH - 56), chr(ord("A") + gi), font=f_head, fill=(120, 120, 115), anchor="ra")

    legend = {"tile_px": S, "rows": [], "cols": []}
    tiles_dir = os.path.join(args.out, "tiles")
    for si, (sk, sname, sdesc, knobs) in enumerate(STYLES):
        y = TH + PAD + si * (S + GAP)
        draw.text((PAD, y + 4), "%d" % (si + 1), font=f_head, fill=(120, 120, 115))
        nx = PAD + int(draw.textlength("%d" % (si + 1), font=f_head)) + 10
        draw.text((nx, y + 4), sname, font=f_head, fill=(235, 232, 220))
        # wrap the description at ~34 chars
        words, lines, cur = sdesc.split(), [], ""
        for w in words:
            if len(cur) + len(w) + 1 > 34:
                lines.append(cur); cur = w
            else:
                cur = (cur + " " + w).strip()
        lines.append(cur)
        for li, ln in enumerate(lines):
            draw.text((PAD + 26, y + 32 + li * 18), ln, font=f_small, fill=(160, 160, 155))
        legend["rows"].append(dict(n=si + 1, key=sk, name=sname, note=sdesc))
        for gi, (gk, gname, gdesc, fn) in enumerate(GROUNDS):
            st = dict(knobs)
            if sk == "withering" and gk in WITHERING_FROST:
                st["accent_override"] = col(0.55, 0.72, 0.88)
            rng = np.random.default_rng(args.seed * 1000 + si * 37 + gi)
            img = style_render(mats[gk], st, S, rng)
            im = Image.fromarray((img * 255 + 0.5).astype(np.uint8), "RGB")
            fname = "%02d%s_%s__%s.png" % (si + 1, chr(ord("A") + gi), sk, gk)
            im.save(os.path.join(tiles_dir, fname))
            x = LW + PAD + gi * (S + GAP)
            sheet.paste(im, (x, y))
            if si == 0:
                legend["cols"].append(dict(letter=chr(ord("A") + gi), key=gk, name=gname, note=gdesc))
        print("row", sk)

    draw.text((PAD, H - 30), "Pick by grid ref (e.g. 7-B = realistic-pixeled dry grass). tiles/ holds every cell as its own PNG; groundsheet.py regenerates all of it.",
              font=f_small, fill=(140, 140, 135))
    sheet.save(os.path.join(args.out, "ground_sheet.png"), optimize=True)
    with open(os.path.join(args.out, "legend.json"), "w") as f:
        json.dump(legend, f, indent=2)
    with zipfile.ZipFile(os.path.join(args.out, "tiles.zip"), "w", zipfile.ZIP_DEFLATED) as z:
        for fn in sorted(os.listdir(tiles_dir)):
            z.write(os.path.join(tiles_dir, fn), "tiles/" + fn)
        z.write(os.path.join(args.out, "legend.json"), "legend.json")
    print("sheet", W, "x", H)

if __name__ == "__main__":
    main()
