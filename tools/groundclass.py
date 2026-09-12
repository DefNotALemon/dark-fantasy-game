#!/usr/bin/env python3
"""
groundclass.py -- the DEFAULT ground under the painted textures.

Reads the baked colour map (assets/terrain/maine_color.png, written by mainegen.py
from myrkgen.colour()) and classifies every 4 m cell back to the bake class it came
from by nearest palette colour, then maps each class to a COLUMN of the ground
texture sheet (tools/groundsheet.py):

    bake class            column   ground
    forest, pine      ->  F   6    forest floor
    meadow            ->  A   1    lush meadow
    farm, shelf gold  ->  B   2    dry grass / Shelf
    barrens           ->  G   7    barrens / heath
    rock              ->  H   8    gravel / scree
    sand              ->  I   9    sand / beach
    snow              ->  K  11    snow-dusted grass
    seabed / lakes    ->      0    none (bake colour shows; water covers it anyway)

Output: assets/terrain/maine_ground.dat -- PNG bytes of an L8 image, one byte per
bake cell (1800 x 2700), row 0 = north, value = column (1..11) or 0.  Stored with a
.dat extension on purpose: Godot must NOT import it as a texture (a lossy or
re-formatted import would corrupt the ids). GroundPaint.gd reads it with
Image.load_png_from_buffer(), same as it reads design/ground_paint.dat.

The shader picks the actual tile as  id = world_style_row * 11 + column, so the whole
world can be re-styled by changing one uniform -- this file only says WHAT ground is
where, never which art style it is drawn in.

    python3 tools/groundclass.py            (from the repo root; ~2 s)
"""
import os, sys, io
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "terrain", "maine_color.png")
OUT = os.path.join(ROOT, "assets", "terrain", "maine_ground.dat")

# myrkgen.colour()'s palette, verbatim, and the column each class dresses as
PALETTE = [
    ("forest",  (0.16, 0.32, 0.14), 6),
    ("pine",    (0.10, 0.24, 0.14), 6),
    ("meadow",  (0.45, 0.60, 0.25), 1),
    ("farm",    (0.70, 0.65, 0.45), 2),
    ("gold",    (0.66, 0.58, 0.30), 2),
    ("sand",    (0.78, 0.72, 0.52), 9),
    ("rock",    (0.34, 0.32, 0.29), 8),
    ("snow",    (0.86, 0.88, 0.92), 11),
    ("seabed",  (0.25, 0.35, 0.40), 0),
    ("barrens", (0.58, 0.50, 0.34), 7),
]


def classify(rgb):
    """rgb: HxWx3 float 0..1 -> HxW uint8 column ids."""
    cols = np.array([p[1] for p in PALETTE], dtype=np.float32)          # K x 3
    # the bake multiplies every class by (1 +- 8 %) noise, so compare on
    # chromaticity + brightness rather than raw distance: normalise both to
    # unit length, then add a small brightness term so rock vs pine still split.
    def feat(a):
        l = np.linalg.norm(a, axis=-1, keepdims=True) + 1e-6
        return np.concatenate([a / l, 0.35 * l], axis=-1)
    fp = feat(cols)                                                      # K x 4
    fi = feat(rgb.reshape(-1, 3))                                        # N x 4
    # chunked argmin so the 4.9 M-cell map stays under a few hundred MB
    out = np.empty(fi.shape[0], dtype=np.uint8)
    step = 400_000
    ids = np.array([p[2] for p in PALETTE], dtype=np.uint8)
    for s in range(0, fi.shape[0], step):
        d = ((fi[s:s + step, None, :] - fp[None, :, :]) ** 2).sum(-1)   # n x K
        out[s:s + step] = ids[np.argmin(d, axis=1)]
    return out.reshape(rgb.shape[:2])


def main():
    im = Image.open(SRC).convert("RGB")
    rgb = np.asarray(im, dtype=np.float32) / 255.0
    ids = classify(rgb)
    names = {0: "none/water", 1: "A lush meadow", 2: "B dry grass", 6: "F forest floor",
             7: "G barrens", 8: "H gravel", 9: "I sand", 11: "K snow"}
    tot = ids.size
    for v in sorted(names):
        n = int((ids == v).sum())
        print("  %-16s %8d cells  %5.1f %%" % (names[v], n, 100.0 * n / tot))
    buf = io.BytesIO()
    Image.fromarray(ids, "L").save(buf, "PNG", optimize=True)
    with open(OUT, "wb") as f:
        f.write(buf.getvalue())
    print("wrote", os.path.relpath(OUT, ROOT), "%d bytes (%d x %d L8 as PNG)"
          % (len(buf.getvalue()), ids.shape[1], ids.shape[0]))
    # a viewable copy beside it is NOT written on purpose -- Godot would import it.


if __name__ == "__main__":
    main()
