"""Procedural bark atlas generator — The Withering / Myrkfell trees v2 (spec §3, §17).

Five species, each a seamless tiling bark set. Per Lemon's call: STYLIZED ALBEDO —
broad readable plates you can identify from ten metres — with a DETAILED NORMAL MAP
doing the close-up work, so the trunk holds up with your nose against it without
fighting the stylized leaf cards.

Textures tile in both axes. Trunk UVs run u = around the circumference, v = up the
trunk, so every species' noise is anisotropic: fissures are long in v, tight in u.

Outputs per species:
  <name>_bark_albedo.png   RGB, sRGB
  <name>_bark_normal.png   tangent-space normal (OpenGL +Y up)
  <name>_bark_rough.png    roughness (R), packed grayscale
  <name>_bark_height.png   height field (R) — drives parallax occlusion so the
                           crevices have real depth when you walk up to a trunk

Run:  python3 tools/barkgen.py --out assets/trees/bark
"""

import argparse
import math
import os

import numpy as np
from PIL import Image, ImageFilter

SIZE = 1024


# ------------------------------------------------------------------- noise

def _lattice_noise(size, gx, gy, rng):
    """Smoothed value noise on a wrapping lattice — seamless by construction."""
    lat = rng.random((gy, gx))
    ys = np.linspace(0, gy, size, endpoint=False)
    xs = np.linspace(0, gx, size, endpoint=False)
    y0 = np.floor(ys).astype(int) % gy
    x0 = np.floor(xs).astype(int) % gx
    fy = (ys - np.floor(ys))[:, None]
    fx = (xs - np.floor(xs))[None, :]
    fy = fy * fy * (3 - 2 * fy)
    fx = fx * fx * (3 - 2 * fx)
    y1, x1 = (y0 + 1) % gy, (x0 + 1) % gx
    a = lat[np.ix_(y0, x0)]
    b = lat[np.ix_(y0, x1)]
    c = lat[np.ix_(y1, x0)]
    d = lat[np.ix_(y1, x1)]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(size, gx, gy, octaves, rng, gain=0.5, lac=2):
    out = np.zeros((size, size))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        out += amp * _lattice_noise(size, max(2, gx * lac ** o), max(2, gy * lac ** o), rng)
        tot += amp
        amp *= gain
    return out / tot


def ridged(size, gx, gy, octaves, rng):
    """1 - |2n-1| — the ridge lines that make fissured bark read as fissured."""
    return 1.0 - np.abs(2.0 * fbm(size, gx, gy, octaves, rng) - 1.0)


def warp(field, dx, dy, amount):
    """Domain warp: push the field around by another field. Kills grid regularity."""
    size = field.shape[0]
    yy, xx = np.meshgrid(np.arange(size), np.arange(size), indexing="ij")
    sy = (yy + (dy - 0.5) * amount).astype(int) % size
    sx = (xx + (dx - 0.5) * amount).astype(int) % size
    return field[sy, sx]


def norm01(a):
    lo, hi = a.min(), a.max()
    return (a - lo) / max(hi - lo, 1e-6)


# ------------------------------------------------------------- species maps
# Each builder returns (height 0..1, tint 0..1 extra colour break-up, mask dict).

def bark_oak(rng):
    """Northern red oak: deep vertical fissures between hard blocky plates."""
    h = ridged(SIZE, 22, 4, 4, rng)
    h = warp(h, fbm(SIZE, 6, 3, 2, rng), fbm(SIZE, 5, 4, 2, rng), 26)
    h = norm01(h) ** 1.5                       # push the fissures deep
    plate = np.clip((h - 0.40) * 9.0, 0, 1)
    plate = plate * (0.75 + 0.25 * fbm(SIZE, 14, 6, 3, rng))
    h = 0.28 * h + 0.72 * plate
    grain = fbm(SIZE, 40, 6, 3, rng) * 0.10
    return norm01(h + grain), fbm(SIZE, 7, 4, 3, rng), {}


def bark_maple(rng):
    """Sugar maple: irregular plates that lift at their edges — shaggy, not carved."""
    h = fbm(SIZE, 12, 6, 4, rng)
    h = warp(h, fbm(SIZE, 5, 5, 2, rng), fbm(SIZE, 4, 6, 2, rng), 34)
    edge = ridged(SIZE, 16, 7, 3, rng)
    h = norm01(h * 0.7 + edge * 0.45)
    lift = (edge > 0.72).astype(float) * 0.30  # plate lips catching the light
    return norm01(h + lift), fbm(SIZE, 9, 5, 3, rng), {}


def bark_birch(rng):
    """Paper birch: smooth chalk-white paper, dark horizontal lenticel dashes,
    and the odd curl where the paper has started to peel."""
    base = fbm(SIZE, 6, 6, 3, rng) * 0.20 + 0.55
    # lenticels: short dashes, wide in u, thin in v
    dash = _lattice_noise(SIZE, 13, 200, rng)
    dash = np.asarray(Image.fromarray((dash * 255).astype(np.uint8))
                      .filter(ImageFilter.GaussianBlur(1.2))) / 255.0
    marks = np.clip((dash - 0.68) * 6.0, 0, 1)
    marks *= (fbm(SIZE, 5, 5, 2, rng) > 0.42)          # only in bands
    # peel curls: rare, chunky, horizontal
    curl = np.clip((_lattice_noise(SIZE, 6, 30, rng) - 0.865) * 10.0, 0, 1)
    h = norm01(base + curl * 0.40 - marks * 0.22)
    return h, marks, {"marks": marks, "curl": curl}


def bark_pine(rng):
    """Eastern white pine: big jigsaw plates with dark crevices between."""
    cell = fbm(SIZE, 8, 6, 3, rng)
    cell = warp(cell, fbm(SIZE, 4, 3, 2, rng), fbm(SIZE, 3, 4, 2, rng), 40)
    edges = ridged(SIZE, 9, 7, 3, rng)
    plate = np.clip((cell - 0.40) * 7.0, 0, 1) * np.clip((edges - 0.26) * 4.0, 0, 1)
    h = norm01(plate * 0.90 + fbm(SIZE, 26, 12, 3, rng) * 0.16)
    return h, cell, {}


def bark_dead(rng):
    """Standing deadwood: bark long gone in places, deep splits, silvered grain.

    One shared set for every species — a dead trunk stops looking like an oak or
    a maple within a season or two, which is exactly why a snag reads as dead
    from across a clearing."""
    h = ridged(SIZE, 16, 3, 4, rng)                 # long vertical splits
    h = warp(h, fbm(SIZE, 5, 3, 2, rng), fbm(SIZE, 4, 4, 2, rng), 30)
    h = norm01(h) ** 1.8                            # deep, hard-edged cracks
    slab = np.clip((h - 0.46) * 6.0, 0, 1)          # what bark is still hanging on
    bare = fbm(SIZE, 9, 5, 3, rng)
    peeled = (bare > 0.54).astype(float)            # patches stripped to the wood
    h = norm01(h * 0.35 + slab * 0.55 - peeled * 0.22)
    grain = fbm(SIZE, 60, 4, 3, rng) * 0.16         # exposed grain runs with the trunk
    return norm01(h + grain), 1.0 - peeled * 0.6, {}


def bark_fir(rng):
    """Balsam fir: near-smooth grey, faint lenticels, and resin blisters."""
    h = fbm(SIZE, 7, 6, 3, rng) * 0.35 + 0.4
    lent = np.clip((_lattice_noise(SIZE, 22, 120, rng) - 0.72) * 5.0, 0, 1) * 0.12
    blist = _lattice_noise(SIZE, 26, 26, rng)
    blist = np.asarray(Image.fromarray((blist * 255).astype(np.uint8))
                       .filter(ImageFilter.GaussianBlur(2.0))) / 255.0
    blist = np.clip((blist - 0.815) * 13.0, 0, 1)
    blist = np.asarray(Image.fromarray((blist * 255).astype(np.uint8))
                       .filter(ImageFilter.GaussianBlur(2.4))) / 255.0
    h = norm01(h * 0.90 + blist * 0.28 - lent)
    return h, blist, {"blisters": blist}


SPECIES = {
    "oak":   dict(fn=bark_oak,   dark=(0.062, 0.051, 0.043), light=(0.180, 0.153, 0.128),
                  rough=(0.93, 0.99), depth=44, contrast=2.8, pivot=0.36, ao=3.0),
    "maple": dict(fn=bark_maple, dark=(0.070, 0.060, 0.053), light=(0.176, 0.156, 0.136),
                  rough=(0.88, 0.97), depth=34, contrast=2.4, pivot=0.38, ao=2.8),
    "birch": dict(fn=bark_birch, dark=(0.470, 0.462, 0.428), light=(0.885, 0.875, 0.830),
                  rough=(0.62, 0.86), depth=18, contrast=1.8, pivot=0.34, ao=1.6),
    "pine":  dict(fn=bark_pine,  dark=(0.048, 0.030, 0.022), light=(0.170, 0.104, 0.070),
                  rough=(0.90, 0.99), depth=40, contrast=3.2, pivot=0.34, ao=3.2),
    ## Deadwood, shared by every species (see bark_dead).
    "dead":  dict(fn=bark_dead,  dark=(0.052, 0.051, 0.047), light=(0.132, 0.130, 0.121),
                  rough=(0.94, 1.00), depth=52, contrast=2.6, pivot=0.34, ao=3.4),
    "fir":   dict(fn=bark_fir,   dark=(0.100, 0.104, 0.097), light=(0.205, 0.212, 0.196),
                  rough=(0.80, 0.94), depth=16, contrast=1.9, pivot=0.36, ao=1.8),
}


# ------------------------------------------------------------------ output

def to_normal(height, depth):
    """Sobel the height into a tangent normal. Wraps, so the map stays seamless."""
    h = height.astype(np.float32)
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * depth
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * depth
    nz = np.ones_like(gx)
    ln = np.sqrt(gx * gx + gy * gy + nz * nz)
    return np.stack([(-gx / ln * 0.5 + 0.5), (gy / ln * 0.5 + 0.5), (nz / ln * 0.5 + 0.5)], -1)


def build(name, cfg, seed):
    rng = np.random.default_rng(seed)
    h, tint, extra = cfg["fn"](rng)

    # albedo: ramp dark crevice -> light plate, with baked cavity shading so the
    # plates read from ten metres even before a light hits the normal map
    dark = np.array(cfg["dark"], np.float32)
    light = np.array(cfg["light"], np.float32)
    hc = np.clip((h - cfg.get("pivot", 0.34)) * cfg.get("contrast", 2.1) + 0.30, 0, 1)
    hc = hc * hc * (3 - 2 * hc)
    blur = np.asarray(Image.fromarray((h * 255).astype(np.uint8))
                      .filter(ImageFilter.GaussianBlur(7))) / 255.0
    ao = np.clip(1.0 - (blur - h) * cfg.get("ao", 2.4), 0.42, 1.0)
    a = dark + (light - dark) * hc[..., None]
    a *= ao[..., None]
    a *= (0.90 + 0.20 * tint[..., None])

    if name == "birch":
        # the dark lenticel dashes are colour, not just depth — that's the tell
        m = extra["marks"][..., None]
        a = a * (1 - m) + np.array([0.085, 0.080, 0.078], np.float32) * m
        a += extra["curl"][..., None] * np.array([0.06, 0.045, 0.035], np.float32)
    if name == "pine":
        a += (h[..., None] ** 3) * np.array([0.030, 0.011, 0.004], np.float32)  # warm plate faces
    if name == "fir":
        a += extra["blisters"][..., None] * np.array([0.014, 0.015, 0.012], np.float32)

    a = np.clip(a, 0, 1) ** (1 / 2.2)                 # to sRGB for the albedo file
    albedo = Image.fromarray((a * 255).astype(np.uint8), "RGB")

    normal = Image.fromarray((to_normal(h, cfg["depth"]) * 255).astype(np.uint8), "RGB")

    r0, r1 = cfg["rough"]
    rough = r1 - (r1 - r0) * h                        # plate faces polish, crevices don't
    roughness = Image.fromarray((np.clip(rough, 0, 1) * 255).astype(np.uint8), "L")
    # height for parallax occlusion: 1 = plate face, 0 = bottom of the fissure
    height = Image.fromarray((np.clip(h, 0, 1) * 255).astype(np.uint8), "L")
    return albedo, normal, roughness, height


def contact_sheet(sets, path, thumb=250):
    names = list(sets)
    sheet = Image.new("RGB", (thumb * 3 + 40, len(names) * (thumb + 26) + 10), (26, 30, 38))
    from PIL import ImageDraw
    d = ImageDraw.Draw(sheet)
    for r, n in enumerate(names):
        y = r * (thumb + 26) + 24
        d.text((8, y - 16), "%s — albedo / normal / height" % n.upper(),
               fill=(196, 202, 214))
        for c, im in enumerate(sets[n]):
            sheet.paste(im.convert("RGB").resize((thumb, thumb), Image.LANCZOS),
                        (8 + c * (thumb + 8), y))
    sheet.save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="assets/trees/bark")
    ap.add_argument("--seed", type=int, default=3301)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    prev = os.path.join(args.out, "previews")
    os.makedirs(prev, exist_ok=True)

    sets = {}
    for i, (name, cfg) in enumerate(SPECIES.items()):
        al, nr, ro, he = build(name, cfg, args.seed + i * 71)
        al.save(os.path.join(args.out, "%s_bark_albedo.png" % name))
        nr.save(os.path.join(args.out, "%s_bark_normal.png" % name))
        ro.save(os.path.join(args.out, "%s_bark_rough.png" % name))
        he.save(os.path.join(args.out, "%s_bark_height.png" % name))
        sets[name] = (al, nr, he)
        print("built %-6s -> %s_bark_*.png" % (name, name))
    contact_sheet(sets, os.path.join(prev, "bark_sheet.png"))
    print("previews ->", prev)


if __name__ == "__main__":
    main()
