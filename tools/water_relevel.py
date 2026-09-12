#!/usr/bin/env python3
"""
water_relevel.py -- sanity pass over assets/terrain/maine_water.r16.

Why this exists (map survey, 2026-08-31): mainegen.py levels every lake to the
median of its macro surface and sinks its bed 1.6 m under that -- and THEN
levels a flat pad under every town, ignoring water. Portland's pad dropped the
ground to -17.7 m while two water bodies over it kept their -1.0 m surface: a
sixteen-metre-deep lake standing on top of the town. Rangeley-Kennebago came
out 130 m above its valley the same way (a peak pin under a lake).

The heights are fine; only the water surfaces are wrong. So this re-levels the
water map in place, body by body, against the baked heights:

  * a cell whose bed is at or above its surface is not water   -> dry
  * a body deeper than MAX_DEPTH over its median bed is a bake glitch, not a
    lake: its surface drops to median bed + RELEVEL_DEPTH, and any cell whose
    bed now stands above that new surface goes dry too
  * a single cell more than MAX_CELL_DEPTH under an otherwise flat lake is a
    hole the bake punched in the bed, not water                  -> dry
  * a body whose bed lies within TIDAL_BED of sea level is tidal water the
    macro classed as a lake (Casco Bay over Portland's pad)      -> sea level

The sea (cells at sea level) is never touched. Run from the repo root:

    python3 tools/water_relevel.py            # rewrites maine_water.r16
    python3 tools/water_relevel.py --dry-run  # just report

Deterministic and idempotent: a second run changes nothing. The encoding
(w_min / w_max in maine_meta.json) is kept, so nothing else needs re-baking.
scripts/Overworld.gd keeps a runtime guard (SKY_WATER_MAX) as the belt to
this pass's braces.
"""
import json
import os
import sys

import numpy as np
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "terrain")

MAX_DEPTH = 15.0        # a lake deeper than this over its median bed is a glitch
RELEVEL_DEPTH = 4.0     # ...and becomes this deep instead
BED_MARGIN = 0.3        # surface must clear the bed by this to count as water
MAX_CELL_DEPTH = 30.0   # one cell this deep under a flat lake is a bake artifact
                        # (matches Overworld.SKY_WATER_MAX, the runtime guard)
TIDAL_BED = 6.0         # an inland body whose bed lies this close to sea level is
                        # tidal water (Casco Bay, Back Cove): it takes the sea's
                        # own level, so the town pad above it is dry land


def main(dry_run: bool) -> int:
    meta = json.load(open(os.path.join(OUT, "maine_meta.json")))
    nx, nz = meta["samples"]
    h_min, h_max = meta["height_range"]
    w_min, w_max = meta["water_range"]
    sea = float(meta["sea_level"])

    hq = np.fromfile(os.path.join(OUT, "maine_height.r16"), dtype="<u2").reshape(nz, nx)
    wq = np.fromfile(os.path.join(OUT, "maine_water.r16"), dtype="<u2").reshape(nz, nx)
    H = h_min + hq.astype(np.float64) / 65535.0 * (h_max - h_min)
    wet0 = wq > 0
    W0 = np.where(wet0, w_min + (wq.astype(np.float64) - 1) / 65534.0 * (w_max - w_min), np.nan)

    # Drying cells splits merged bodies, and a split part can have its own
    # median bed -- so iterate to a fixed point. Converges in two or three
    # passes; that is what makes ONE run of this script idempotent.
    W = W0
    total_changed = 0
    for _pass in range(8):
        W_next, changed = _pass_once(W, H, sea)
        total_changed += changed
        W = W_next
        if changed == 0:
            break
    new_wet = ~np.isnan(W)
    print(f"  total: {total_changed} cell changes over the passes")
    # nothing may leave the encoding range the meta declares
    lo = float(np.nanmin(W)) if new_wet.any() else w_min
    hi = float(np.nanmax(W)) if new_wet.any() else w_max
    assert lo >= w_min - 1e-3 and hi <= w_max + 1e-3, (lo, hi, w_min, w_max)
    if dry_run or total_changed == 0:
        print("  (no write)" if dry_run else "  already clean")
        return 0
    out = np.zeros((nz, nx), dtype="<u2")
    out[new_wet] = (1 + (W[new_wet] - w_min) / max(w_max - w_min, 1e-6) * 65534.0 + 0.5).astype("<u2")
    out[new_wet] = np.maximum(out[new_wet], 1)
    out.tofile(os.path.join(OUT, "maine_water.r16"))
    print(f"  wrote {os.path.join(OUT, 'maine_water.r16')}")
    return 0


def _pass_once(W: np.ndarray, H: np.ndarray, sea: float):
    wet = ~np.isnan(W)
    ocean = wet & (np.abs(W - sea) < 0.4)
    inland = wet & ~ocean
    lab, n = ndimage.label(inland)
    print(f"water: {int(wet.sum())} wet cells, {int(ocean.sum())} sea, {int(inland.sum())} inland in {n} bodies")

    new_W = W.copy()
    dried = 0
    relevelled = 0
    for i in range(1, n + 1):
        m = lab == i
        lvl = float(np.nanmedian(W[m]))
        bed = H[m]
        # 1) cells whose bed is above the surface were never water, and a
        #    single cell 30 m under a flat lake is a bake artifact, not a lake
        above = (bed > lvl - BED_MARGIN) | (lvl - bed > MAX_CELL_DEPTH)
        if above.all():
            new_W[m] = np.nan
            dried += int(m.sum())
            continue
        med_bed = float(np.median(bed[~above]))
        if med_bed < sea + TIDAL_BED and lvl > sea + 0.4:
            # coastal lowland water that the macro classed as a lake -- the
            # bodies over Portland's pad were exactly this. At sea level the
            # sea plane draws them where the ground is under the sea and the
            # pad stays dry. (The cells become "sea" and are never revisited.)
            relevelled += 1
            print(f"  body {i}: {int(m.sum())} cells, surface {lvl:.1f}, bed {med_bed:.1f} near the sea"
                  f" -> tidal, set to sea level {sea:.1f}")
            lvl = sea
            idx = np.where(m)
            new_W[idx[0], idx[1]] = lvl
            continue
        if lvl - med_bed > MAX_DEPTH:
            new_lvl = med_bed + RELEVEL_DEPTH
            relevelled += 1
            print(f"  body {i}: {int(m.sum())} cells, surface {lvl:.1f} over median bed {med_bed:.1f}"
                  f" -> re-levelled to {new_lvl:.1f}")
            lvl = new_lvl
            above = (bed > lvl - BED_MARGIN) | (lvl - bed > MAX_CELL_DEPTH)
        idx = np.where(m)
        keep = ~above
        new_W[idx[0][keep], idx[1][keep]] = lvl
        new_W[idx[0][above], idx[1][above]] = np.nan
        dried += int(above.sum())

    new_wet = ~np.isnan(new_W)
    changed = int((new_wet != wet).sum() + (new_wet & wet & (np.abs(np.nan_to_num(new_W) - np.nan_to_num(W)) > 0.01)).sum())
    print(f"  pass: dried {dried} cells, re-levelled {relevelled} bodies, {changed} cells changed")
    return new_W, changed


if __name__ == "__main__":
    sys.exit(main("--dry-run" in sys.argv))
