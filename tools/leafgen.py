"""Procedural leaf-card atlas generator — The Withering / Myrkfell trees v2.

Builds one RGBA atlas per leaf SHAPE (docs/TREES_v2_SPEC.md §6). Atlases are authored
as GRAYSCALE LUMINANCE + ALPHA, never as coloured leaves: the season shader multiplies
the luminance by a per-species seasonal colour ramp, so one atlas covers spring /
summer / autumn / winter with no extra texture memory and no mesh rebuild.

Layout: 1024 x 1024, 4 x 4 cells of 256 px.
  rows 0-1 (cells 0-7)  = leaf SPRAYS   — what the canopy MultiMesh instances
  rows 2-3 (cells 8-15) = SINGLE leaves — close LOD detail + falling-leaf particles

Outputs per species:
  <name>_leaf_atlas.png   RGBA — luminance in RGB, silhouette in A
  <name>_leaf_normal.png  tangent-space normal from leaf curvature + veins

Run:  python3 tools/leafgen.py --out assets/trees/leaves
"""

import argparse
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

# ---------------------------------------------------------------- constants

CELL = 256          # px per atlas cell (final)
COLS, ROWS = 4, 4
SS = 4              # supersample while drawing
SPRAY_CELLS = 8     # cells 0..7 sprays, 8..15 single leaves

LUMA_BODY = 205     # base leaf luminance — leaves get tinted, so leave headroom
LUMA_VEIN = 224
LUMA_EDGE = 0.72    # rim darkening
LUMA_STEM = 92      # conifer twig / fascicle sheath: stays dark under any tint


# ------------------------------------------------------------ leaf outlines
# Builders return (polys, veins) in unit space: petiole at (0,0), leaf runs up
# +Y to y≈1, half-width ≈0.5. polys is a list so a leaf can carry its stalk.

def _petiole(length=0.16, w=0.011):
    return [(-w, 0.03), (w, 0.03), (w * 0.6, -length), (-w * 0.6, -length)]


def leaf_maple(rng):
    """Sugar maple — 5 palmate lobes, U-sinuses, coarse teeth, cordate base."""
    spread = 68.0
    tips = np.radians(np.linspace(-spread, spread, 5))
    lens = np.array([0.60, 0.90, 1.00, 0.90, 0.60]) * rng.uniform(0.95, 1.05)
    half = np.radians(spread * 0.5 * 0.62)

    th = np.radians(np.linspace(-spread - 24, spread + 24, 520))
    r = np.full_like(th, 0.30)
    for t0, ln in zip(tips, lens):
        d = np.clip(np.abs(th - t0) / half, 0.0, 1.0)
        r = np.maximum(r, ln * np.cos(d * math.pi / 2) ** 0.58)
    r *= 1.0 + 0.028 * np.sin(th * 9.0) ** 2
    edge = np.clip((np.abs(th) - np.radians(spread + 2)) / np.radians(22), 0, 1)
    r *= np.clip(1.0 - edge ** 1.15, 0.0, 1.0)

    pts = [(float(rr * math.sin(t)), float(rr * math.cos(t))) for t, rr in zip(th, r)]
    veins = [[(0.0, 0.05), (float(l * math.sin(t) * 0.86), float(l * math.cos(t) * 0.86))]
             for t, l in zip(tips, lens)]
    return [pts, _petiole(0.20)], veins


def leaf_oak(rng):
    """Northern red oak — long blade, four deep narrow sinuses per side."""
    t = np.linspace(0.015, 1.0, 340)
    env = np.sin(np.pi * t ** 0.80) ** 0.70
    off = rng.uniform(-0.02, 0.02)

    def side(shift):
        cut = np.zeros_like(t)
        for s in (0.20, 0.40, 0.60, 0.785):
            cut += 0.66 * np.exp(-((t - (s + shift)) / 0.038) ** 2)
        return env * (1.0 - np.clip(cut, 0, 0.84)) * 0.5 * rng.uniform(0.95, 1.05)

    wr, wl = side(off), side(-off)
    rake = 0.13  # lobes sweep forward toward the tip, like a real red oak
    right = [(float(w), float(ti + rake * w)) for w, ti in zip(wr, t)]
    left = [(float(-w), float(ti + rake * w)) for w, ti in zip(wl, t)][::-1]
    pts = right + [(0.0, 1.0)] + left

    veins = [[(0.0, 0.0), (0.0, 0.97)]]
    for s in (0.30, 0.50, 0.70, 0.87):
        i = int(s * len(t))
        for sgn, w in ((1, wr), (-1, wl)):
            veins.append([(0.0, float(t[i] - 0.06)), (sgn * float(w[i]) * 0.82, float(t[i]))])
    return [pts, _petiole(0.14)], veins


def leaf_birch(rng):
    """Paper birch — small ovate, doubly serrate, acuminate tip."""
    t = np.linspace(0.015, 1.0, 340)
    w = (t ** 0.50) * ((1.0 - t) ** 1.05)
    w = w / w.max() * 0.5 * rng.uniform(0.94, 1.06)
    serr = 1.0 + 0.038 * np.sign(np.sin(26 * math.pi * t)) * np.clip(4 * t * (1 - t), 0, 1)
    w = w * serr

    right = [(float(wi), float(ti)) for wi, ti in zip(w, t)]
    left = [(float(-wi), float(ti)) for wi, ti in zip(w, t)][::-1]
    pts = right + [(0.0, 1.02)] + left

    veins = [[(0.0, 0.0), (0.0, 0.98)]]
    for s in np.linspace(0.16, 0.80, 6):
        i = int(s * len(t))
        for sgn in (1, -1):
            veins.append([(0.0, float(t[i]) - 0.05),
                          (sgn * float(w[i]) * 0.88, float(t[i]) + 0.05)])
    return [pts, _petiole(0.10)], veins


def needle_pine(rng, length=1.0):
    """One eastern-white-pine needle: long, fine, gently bowed."""
    t = np.linspace(0, 1, 34)
    bow = rng.uniform(-0.09, 0.09)
    x, y = bow * t ** 2, t * length
    w = 0.028 * (1 - 0.7 * t ** 3)
    right = [(float(xi + wi), float(yi)) for xi, yi, wi in zip(x, y, w)]
    left = [(float(xi - wi), float(yi)) for xi, yi, wi in zip(x, y, w)][::-1]
    return [right + left], []


def needle_fir(rng, length=1.0):
    """One balsam-fir needle: short, flat, blunt-tipped."""
    t = np.linspace(0, 1, 12)
    y = t * length
    w = 0.026 * (1 - 0.30 * t ** 2)
    right = [(float(wi), float(yi)) for yi, wi in zip(y, w)]
    left = [(float(-wi), float(yi)) for yi, wi in zip(y, w)][::-1]
    return [right + left], []


# ------------------------------------------------------------- compositing

def _xf(pts, cx, cy, scale, rot):
    c, s = math.cos(rot), math.sin(rot)
    return [(cx + (x * c - y * s) * scale, cy - (x * s + y * c) * scale) for x, y in pts]


def _stamp(cell, polys, veins, cx, cy, scale, rot, luma):
    """Paint one leaf, with its veins clipped to its own silhouette."""
    mask = Image.new("L", cell.size, 0)
    md = ImageDraw.Draw(mask)
    for p in polys:
        md.polygon(_xf(p, cx, cy, scale, rot), fill=255)
    lay = Image.new("L", cell.size, luma)
    if veins:
        ld = ImageDraw.Draw(lay)
        vw = max(1, int(scale * 0.008))
        for v in veins:
            ld.line(_xf(v, cx, cy, scale, rot), fill=LUMA_VEIN, width=vw)
    cell.alpha_composite(Image.merge("RGBA", (lay, lay, lay, mask)))


# ----------------------------------------------------------------- sprays

def _fit(polys, bx, by, sc, rot, cx, cy, limit):
    """Shrink a leaf until its whole silhouette sits inside the cell.

    A leaf clipped by the atlas edge reads in-game as a straight razor cut
    across the canopy, so this is not optional.
    """
    c, s_ = math.cos(rot), math.sin(rot)
    xs, ys = [], []
    for poly in polys:
        for x, y in poly:
            xs.append(x * c - y * s_)
            ys.append(-(x * s_ + y * c))
    reach = max(max(abs(bx + v * sc - cx) for v in xs),
                max(abs(by + v * sc - cy) for v in ys))
    return sc * (limit / reach) if reach > limit else sc


def _spray_hardwood(cell, builder, rng, box, count, leaf_scale=1.0):
    """Leaves alternating off an implied twig — fanned, with sky-gaps between."""
    cx, cy = box / 2, box / 2
    limit = box * 0.47
    x0, y0 = cx + rng.uniform(-0.05, 0.05) * box, cy + 0.26 * box
    x1, y1 = cx + rng.uniform(-0.14, 0.14) * box, cy - 0.24 * box
    side = rng.choice((-1, 1))

    stamps = []
    for i in range(count):
        f = i / max(count - 1, 1)
        bx = x0 + (x1 - x0) * f
        by = y0 + (y1 - y0) * f
        ang = side * math.radians(rng.uniform(38, 78)) * (1.0 - 0.40 * f)
        ang += math.radians(rng.uniform(-9, 9))
        sc = box * leaf_scale * rng.uniform(0.80, 1.05) * (1.0 - 0.10 * f)
        polys, veins = builder(rng)
        sc = _fit(polys, bx, by, sc, ang, cx, cy, limit)
        stamps.append((bx, by, sc, ang, int(LUMA_BODY * rng.uniform(0.78, 1.0)), polys, veins))
        side = -side
    stamps.sort(key=lambda s: -s[1])
    for bx, by, sc, ang, lu, polys, veins in stamps:
        _stamp(cell, polys, veins, bx, by, sc, ang, lu)


def _spray_pine(cell, rng, box, fascicles=3, scale=0.74):
    """Bundles of five needles — the white-pine tell."""
    cx, cy = box / 2, box / 2
    for f in range(fascicles):
        t = f / max(fascicles - 1, 1)
        bx = cx + rng.uniform(-0.17, 0.17) * box
        by = cy + box * (0.44 - t * 0.30)
        base = math.radians(rng.uniform(-17, 17))
        d = ImageDraw.Draw(cell)
        d.line([(bx, by), (bx + math.sin(base) * box * 0.09, by - math.cos(base) * box * 0.09)],
               fill=(LUMA_STEM,) * 3 + (255,), width=max(2, int(box * 0.016)))
        for n in range(5):
            ang = base + math.radians((n - 2) * rng.uniform(5, 9))
            polys, _ = needle_pine(rng, rng.uniform(0.86, 1.0))
            _stamp(cell, polys, [], bx, by, box * scale * rng.uniform(0.92, 1.0), ang,
                   int(LUMA_BODY * rng.uniform(0.76, 1.0)))


def _spray_fir(cell, rng, box, scale=0.26, pairs=34):
    """A flat sprig: short needles combed forward off both sides of a twig."""
    cx, cy = box / 2, box / 2
    ax = math.radians(rng.uniform(-10, 10))
    x0, y0 = cx + rng.uniform(-0.08, 0.08) * box, cy + box * 0.46
    ln = box * rng.uniform(0.80, 0.92)
    x1, y1 = x0 + math.sin(ax) * ln, y0 - math.cos(ax) * ln
    ImageDraw.Draw(cell).line([(x0, y0), (x1, y1)], fill=(LUMA_STEM,) * 3 + (255,),
                              width=max(2, int(box * 0.010)))
    for i in range(pairs):
        t = 0.04 + 0.94 * i / (pairs - 1)
        px, py = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
        taper = 1.0 - 0.42 * t
        for s in (-1, 1):
            ang = ax + s * math.radians(rng.uniform(52, 72))
            polys, _ = needle_fir(rng)
            _stamp(cell, polys, [], px, py, box * scale * taper * rng.uniform(0.85, 1.1),
                   ang, int(LUMA_BODY * rng.uniform(0.72, 1.0)))


# ------------------------------------------------------------------ atlas

SPECIES = {
    "maple": dict(kind="hardwood", builder=leaf_maple, count=(9, 13), single=0.62, lscale=0.42),
    "birch": dict(kind="hardwood", builder=leaf_birch, count=(13, 17), single=0.60, lscale=0.38),
    "oak":   dict(kind="hardwood", builder=leaf_oak,   count=(8, 11), single=0.70, lscale=0.46),
    "pine":  dict(kind="pine",     builder=None,       count=(1, 1), single=0.90),
    "fir":   dict(kind="fir",      builder=None,       count=(1, 1), single=0.86),
}


def build_atlas(name, cfg, seed):
    rng = random.Random(seed)
    box = CELL * SS
    atlas = Image.new("RGBA", (CELL * COLS * SS, CELL * ROWS * SS), (0, 0, 0, 0))

    for c in range(COLS * ROWS):
        cell = Image.new("RGBA", (box, box), (0, 0, 0, 0))
        if c < SPRAY_CELLS:
            if cfg["kind"] == "hardwood":
                _spray_hardwood(cell, cfg["builder"], rng, box, rng.randint(*cfg["count"]),
                                cfg.get("lscale", 1.0))
            elif cfg["kind"] == "pine":
                _spray_pine(cell, rng, box)
            else:
                _spray_fir(cell, rng, box)
        else:
            if cfg["kind"] == "hardwood":
                polys, veins = cfg["builder"](rng)
                rot = math.radians(rng.uniform(-14, 14))
                sc = _fit(polys, box / 2, box * 0.90, box * cfg["single"], rot,
                          box / 2, box / 2, box * 0.47)
                _stamp(cell, polys, veins, box / 2, box * 0.90, sc, rot,
                       int(LUMA_BODY * rng.uniform(0.86, 1.0)))
            elif cfg["kind"] == "pine":
                _spray_pine(cell, rng, box, fascicles=2, scale=0.86)
            else:
                _spray_fir(cell, rng, box, scale=0.30, pairs=36)
        atlas.paste(cell, ((c % COLS) * box, (c // COLS) * box))

    atlas = atlas.resize((CELL * COLS, CELL * ROWS), Image.LANCZOS)
    return _finish(atlas)


def _finish(img):
    """Rim-darken the silhouette, then derive a matching normal map."""
    a = np.asarray(img).astype(np.float32)
    alpha = a[..., 3] / 255.0

    inner = np.asarray(Image.fromarray((alpha * 255).astype(np.uint8))
                       .filter(ImageFilter.MinFilter(5))).astype(np.float32) / 255.0
    rim = np.clip(alpha - inner, 0, 1)
    lum = a[..., 0] * (1.0 - rim * (1.0 - LUMA_EDGE))

    out = np.zeros_like(a)
    for i in range(3):
        out[..., i] = lum
    out[..., 3] = a[..., 3]
    atlas = Image.fromarray(out.astype(np.uint8), "RGBA")

    soft = np.asarray(Image.fromarray((alpha * 255).astype(np.uint8))
                      .filter(ImageFilter.GaussianBlur(3.0))).astype(np.float32) / 255.0
    height = soft * 0.72 + (lum / 255.0) * alpha * 0.28
    gx = np.gradient(height, axis=1) * 24.0
    gy = np.gradient(height, axis=0) * 24.0
    nz = np.ones_like(gx)
    ln = np.sqrt(gx * gx + gy * gy + nz * nz)
    nrm = np.stack([(-gx / ln * 0.5 + 0.5) * 255,
                    (gy / ln * 0.5 + 0.5) * 255,
                    (nz / ln * 0.5 + 0.5) * 255,
                    alpha * 255], axis=-1)
    return atlas, Image.fromarray(nrm.astype(np.uint8), "RGBA")


# ---------------------------------------------------------------- previews

SEASON_RAMPS = {
    #            spring              summer              autumn              winter
    "maple": [(0.44, 0.56, 0.26), (0.24, 0.36, 0.18), (0.86, 0.34, 0.09), (0.40, 0.22, 0.14)],
    "birch": [(0.56, 0.66, 0.31), (0.31, 0.43, 0.21), (0.87, 0.63, 0.17), (0.44, 0.34, 0.18)],
    "oak":   [(0.36, 0.46, 0.23), (0.19, 0.29, 0.15), (0.56, 0.27, 0.12), (0.34, 0.22, 0.13)],
    "pine":  [(0.20, 0.33, 0.22), (0.16, 0.28, 0.20), (0.16, 0.27, 0.19), (0.21, 0.33, 0.34)],
    "fir":   [(0.17, 0.28, 0.21), (0.13, 0.24, 0.19), (0.13, 0.23, 0.18), (0.19, 0.30, 0.33)],
}
SEASON_NAMES = ["spring", "summer", "autumn", "winter"]
BG = (26, 30, 38)


def _tint(cell, rgb):
    a = np.asarray(cell).astype(np.float32)
    lum = a[..., 0:1] / 255.0
    col = lum * np.array(rgb, dtype=np.float32).reshape(1, 1, 3) * 255.0
    bg = np.array(BG, dtype=np.float32).reshape(1, 1, 3)
    al = a[..., 3:4] / 255.0
    return Image.fromarray((col * al + bg * (1 - al)).astype(np.uint8), "RGB")


def _sheet(atlases, path, cells, season_idx, label, thumb=180):
    names = list(atlases)
    sheet = Image.new("RGB", (thumb * 4 + 40, len(names) * (thumb + 26) + 10), BG)
    d = ImageDraw.Draw(sheet)
    for r, n in enumerate(names):
        y = r * (thumb + 26) + 24
        d.text((8, y - 16), "%s — %s" % (n.upper(), label), fill=(196, 202, 214))
        atlas = atlases[n][0]
        for i, c in enumerate(cells):
            col, row = c % COLS, c // COLS
            cell = atlas.crop((col * CELL, row * CELL, (col + 1) * CELL, (row + 1) * CELL))
            s = season_idx if isinstance(season_idx, int) else season_idx[i]
            sheet.paste(_tint(cell, SEASON_RAMPS[n][s]).resize((thumb, thumb), Image.LANCZOS),
                        (8 + i * (thumb + 8), y))
    sheet.save(path)


# -------------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="assets/trees/leaves")
    ap.add_argument("--previews", default=None)
    ap.add_argument("--seed", type=int, default=7717)
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    prev = args.previews or os.path.join(args.out, "previews")
    os.makedirs(prev, exist_ok=True)

    atlases = {}
    for i, (name, cfg) in enumerate(SPECIES.items()):
        atlas, normal = build_atlas(name, cfg, args.seed + i * 101)
        atlas.save(os.path.join(args.out, "%s_leaf_atlas.png" % name))
        normal.save(os.path.join(args.out, "%s_leaf_normal.png" % name))
        atlases[name] = (atlas, normal)
        print("built %-6s -> %s_leaf_atlas.png" % (name, name))

    _sheet(atlases, os.path.join(prev, "leaf_atlases.png"), [0, 1, 2, 3], 1, "sprays (summer)")
    _sheet(atlases, os.path.join(prev, "leaf_singles.png"), [8, 9, 10, 11], 2, "single leaves (autumn)")
    _sheet(atlases, os.path.join(prev, "leaf_seasons.png"), [0, 0, 0, 0], [0, 1, 2, 3],
           "spring / summer / autumn / winter")
    print("previews ->", prev)


if __name__ == "__main__":
    main()
