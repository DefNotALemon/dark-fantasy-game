#!/usr/bin/env python3

"""
terrain_relax.py -- lift the mountain lakes out of their shafts, fill the pits,
and cut the vertical walls the bake left on the ranges.

Why this exists (map survey, 2026-08-31, second pass): mainegen.py's PIN_PEAKS
grows every named summit toward its real share of Katahdin, and it exempts
lake cells from the raise so "an inland lake keeps its surface while the range
grows around it". At the map's 47x horizontal compression that puts whole
lakes INSIDE the new mountain mass: Chesuncook stayed at 9 m while 500 m of
Katahdin rose around it, so the bake carries 22,000 cells of 84-89 degree
walls -- a 4 m step of 350 m -- around every mountain lake, and a lake the
detail pass lifted above its own surface became a DRY rectangular pit 40 x 75 m
and 330 m deep on Katahdin's flank (x 2294..2330, z -4947..-4875), a trap a
player cannot climb out of.

This is a post-pass over the baked files -- it needs no macro data -- built
from a few physical moves, iterated until nothing changes:

  CUT.    No ground may stand steeper than SLOPE_CAP above any water surface:
          a cone from every visible water cell (its level + SLOPE_CAP per
          metre) caps the land around it, so a wall becomes a 72-degree
          flank instead of one stretched quad. Peaks survive as long as no
          water sits within (peak - water) / SLOPE_CAP of them.
  FILL.   Water finds the spill point of its basin (priority-flood, done as a
          morphological reconstruction, with the sea, the map edge and the
          spawn valley as the drains). A lake whose rim stands above it is
          CARRIED UP with its bed to that rim -- the mountain lake it always
          should have been -- and a DRY closed basin deeper than
          PIT_MIN_DEPTH (a pit, not a hollow) fills into a tarn: the drowned
          floor becomes water over its own bed, capped TARN_DEPTH under the
          surface, so every filled lake has real shallows to wade.
  DRAIN.  A filled body whose rim a later CUT lowers under its surface (two
          new water levels closer than their difference allows) settles down
          to that rim; the cut runs again. Two or three rounds settle it.
  EMBANK. Lakes the bake itself left hanging over their own shore -- a river
          the macro classed as one flat lake, 30 m above its lower reaches --
          keep their level (their beds are the bake's flat fakes; draining
          them would empty them) and get a 72-degree bank instead of a wall
          of water.

The bank can close a low pocket behind it, which the next FILL floods as part
of the lake, so FILL / CUT+DRAIN / EMBANK repeat until a round changes
(almost) nothing -- three rounds on the 2026-08-31 bake. Result on that bake:
the 11,700 steps over 40 m per cell came down to 285 (all of them dry cliffs
the macro itself carries, e.g. the straight coast seam north of Freeport),
23 lake basins rose 1-177 m (Moosehead +44, Munsungan +177), 59 pits became
tarns, water grew by 4.3 km2, and no named summit lost more than 11 m except
Kineo, the cliff over Moosehead (-39). The spawn valley (340 m) is untouched.

Then the meta is re-derived exactly as mainegen does it (places, lakes and
summits re-snapped to the new heights) and the N-key preview is redrawn.
Run from the repo root:

    python3 tools/terrain_relax.py            # rewrites the bake in place
    python3 tools/terrain_relax.py --dry-run  # just report

Deterministic and, to within the r16 quantum and water_relevel's own tidying,
idempotent: a second run touches ~0.03% of the cells by under a metre. The height
encoding (height_range in maine_meta.json) is kept -- nothing here raises
ground above the old maximum or cuts below the old minimum -- and the water
encoding is widened only if a new tarn stands above the old water_range.
mainegen.py calls this right after it writes the meta, and water_relevel.py
runs after it, so a full re-bake produces the same files this pass produces.
"""
from __future__ import annotations

import json
import os
import sys

import numpy as np
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "terrain")
STEP = 4.0

LAKE_MIN_RISE = 1.0     # a lake basin is filled if its spill is this far above the lake
PIT_MIN_DEPTH = 40.0    # a DRY closed basin this deep is a pit, not a hollow: it fills
                        # (the natural hollows the ridged detail leaves are 6-30 m)
FLOOD_MIN = 0.3         # filled ground this far under the spill point is water
                        # (= LIP: everything under the new surface floods, so a
                        # raised lake keeps a natural bed from 0 to TARN_DEPTH
                        # and has shallows to wade, not a 2 m step at its edge)
TARN_DEPTH = 5.0        # a new tarn's bed is at most this far under its surface
                        # (well under water_relevel's 15 m re-level rule)
LIP = 0.3               # water stands this far under its spill rim
SLOPE_CAP = 3.0         # metres of rise per metre allowed above any water (72 deg):
                        # only the bake's 84-89 degree walls are steeper than this,
                        # so the pinned summits themselves are never touched


def main(dry_run: bool) -> int:
    meta = json.load(open(os.path.join(OUT, "maine_meta.json")))
    nx, nz = meta["samples"]
    h_min, h_max = meta["height_range"]
    w_min, w_max = meta["water_range"]
    sea = float(meta["sea_level"])

    hq = np.fromfile(os.path.join(OUT, "maine_height.r16"), dtype="<u2").reshape(nz, nx)
    wq = np.fromfile(os.path.join(OUT, "maine_water.r16"), dtype="<u2").reshape(nz, nx)
    H = h_min + hq.astype(np.float64) / 65535.0 * (h_max - h_min)
    wet = wq > 0
    W = np.where(wet, w_min + (wq.astype(np.float64) - 1) / 65534.0 * (w_max - w_min), np.nan)

    H1, W1, wet1, rep = relax(H, W, wet, sea, valley_mask(meta))
    for line in rep:
        print("  " + line)

    changed_h = int((np.abs(H1 - H) > 0.01).sum())
    changed_w = int((wet1 != wet).sum() + (wet1 & wet & (np.abs(np.nan_to_num(W1) - np.nan_to_num(W)) > 0.01)).sum())
    print(f"  total: {changed_h} height cells and {changed_w} water cells changed")
    if dry_run or (changed_h == 0 and changed_w == 0):
        print("  (no write)" if dry_run else "  already clean")
        return 0

    # --- encode, same height range; widen the water range only if needed ----
    assert float(H1.min()) >= h_min - 1e-3 and float(H1.max()) <= h_max + 1e-3, (H1.min(), H1.max(), h_min, h_max)
    hq1 = (np.clip((H1 - h_min) / (h_max - h_min), 0.0, 1.0) * 65535.0 + 0.5).astype("<u2")
    hq1.tofile(os.path.join(OUT, "maine_height.r16"))
    lo = float(np.nanmin(W1)) if wet1.any() else w_min
    hi = float(np.nanmax(W1)) if wet1.any() else w_max
    if lo < w_min - 1e-3 or hi > w_max + 1e-3:
        w_min, w_max = min(lo, w_min), max(hi, w_max)
        meta["water_range"] = [w_min, w_max]
        print(f"  water_range widened to {w_min:.2f} .. {w_max:.2f}")
    out = np.zeros((nz, nx), dtype="<u2")
    out[wet1] = (1 + (W1[wet1] - w_min) / max(w_max - w_min, 1e-6) * 65534.0 + 0.5).astype("<u2")
    out[wet1] = np.maximum(out[wet1], 1)
    out.tofile(os.path.join(OUT, "maine_water.r16"))

    # --- meta: places, lakes and summits against the new ground ---------------
    Hg = (h_min + hq1.astype(np.float64) / 65535.0 * (h_max - h_min)).astype(np.float32)
    _remeta(meta, Hg)
    json.dump(meta, open(os.path.join(OUT, "maine_meta.json"), "w"), indent=1)
    write_preview()
    print(f"  wrote maine_height.r16, maine_water.r16, maine_meta.json, maine_preview.png")
    return 0


def valley_mask(meta: dict) -> np.ndarray:
    """The spawn valley is the bake's own design (flat disc, no ponds, the
    cave hole under it): nothing in this pass may touch it. Metro pads are
    likewise authored flats — a 72° cone from nearby Casco water must not
    shave Portland back down to the beach."""
    nx, nz = meta["samples"]
    bx = meta["bounds_world"]["x"][0]
    bz = meta["bounds_world"]["z"][0]
    ease_r = float(meta["valley"]["ease_r"])
    gx = bx + np.arange(nx) * STEP
    gz = bz + np.arange(nz) * STEP
    m = np.hypot(gx[None, :], gz[:, None]) < ease_r + STEP
    for p in meta.get("places", []):
        if int(p.get("rank", 0)) < 2:
            continue
        r = 140.0 if int(p["rank"]) >= 3 else 90.0
        dx = gx[None, :] - float(p["pos"][0])
        dz = gz[:, None] - float(p["pos"][1])
        m |= np.hypot(dx, dz) < r
    return m


# ------------------------------------------------------------------ the pass --
def relax(H: np.ndarray, W: np.ndarray, wet: np.ndarray, sea: float, fixed: np.ndarray | None = None):
    """Pure function: (H, W, wet) -> (H', W', wet', report lines).

    `fixed` marks cells that must come out exactly as they went in (the spawn
    valley). Only VISIBLE water -- a surface above its own bed -- counts as
    water here: the bake also carries sea-level cells under Portland's and
    Freeport's town pads (the macro's coast, buried by the pad), and a cone
    or a fill anchored on those would dig the towns out from under themselves.

    Order: CUT, FILL, then rounds of CUT + DRAIN, then EMBANK.
      * The walls are cut first against the bake's own water, so a hollow
        perched on top of a wall spills over the new slope instead of
        becoming a tarn 100 m above the lake next to it.
      * Then the basins fill.
      * A filled body whose rim the next cut lowers under its surface (two
        new water levels closer than their difference allows) DRAINS to that
        rim, and the cut runs again; this settles in two or three rounds.
      * Lakes the bake itself left hanging over their own shore -- a river
        the macro classed as one flat lake, 30 m above its lower reaches --
        keep their level (their beds are the bake's flat fakes; draining
        them would empty them) and get a 72-degree bank instead of a wall
        of water: EMBANK.
    """
    rep = []
    if fixed is None:
        fixed = np.zeros(H.shape, dtype=bool)
    H1, W1, wet1 = H.copy(), W.copy(), wet.copy()
    cut_mask = np.zeros(H.shape, dtype=bool)
    cap = np.full(H.shape, np.inf)          # a drained body never fills past its cut rim again
    H1 = _cut(H1, W1, wet1, fixed, rep, "cut 1", cut_mask)
    # The bank an EMBANK raises can close a low pocket behind it, which the
    # next FILL then floods as part of the lake; two or three rounds settle it.
    for outer in range(1, 4):
        H1, W1, wet1, info, n_fill = _fill(H1, W1, wet1, sea, fixed, cap, rep)
        for k in range(2, 6):
            H1 = _cut(H1, W1, wet1, fixed, rep, f"cut {k}", cut_mask)
            H1, W1, wet1, drained = _drain(H1, W1, wet1, info, cut_mask, cap, rep)
            if drained == 0:
                break
        H1, n_bank = _embank(H1, W1, wet1, fixed, rep)
        rep.append(f"-- round {outer}: {n_fill} cells filled, {n_bank} embanked")
        if n_fill < 50 and n_bank < 50:
            break
    _residuals(H1, W1, wet1, fixed, rep)
    # the valley comes out exactly as it went in
    H1[fixed] = H[fixed]
    W1[fixed] = W[fixed]
    wet1[fixed] = wet[fixed]
    return H1, W1, wet1, rep


def _visible(H, W, wet):
    Wn = np.nan_to_num(W, nan=-1e9)
    return Wn, wet & (Wn > H + 0.05)


def _fill(H, W, wet, sea, fixed, cap, rep):
    from skimage.morphology import reconstruction
    Wn, vis = _visible(H, W, wet)
    Hs = np.where(vis, Wn, H)           # the water surface is the ground the fill sees
    outlets = np.zeros(H.shape, dtype=bool)
    outlets[0, :] = outlets[-1, :] = outlets[:, 0] = outlets[:, -1] = True
    outlets |= vis & (np.abs(Wn - sea) < 0.4)
    outlets |= fixed                    # the valley drains everything that reaches it
    seed = Hs.copy()
    seed[~outlets] = float(Hs.max())
    fill = reconstruction(seed, Hs, method="erosion")
    fill = np.minimum(fill, cap)
    depth = np.maximum(fill - Hs, 0.0)
    depth[fixed] = 0.0
    lab, n = ndimage.label(depth > 1e-3)
    idx = np.arange(1, n + 1)
    maxd = np.asarray(ndimage.maximum(depth, lab, index=idx)) if n else np.zeros(0)
    haswet = (np.asarray(ndimage.maximum(vis.astype(np.uint8), lab, index=idx)) > 0) if n else np.zeros(0, bool)
    keep = np.zeros(n + 1, dtype=bool)
    # a lake whose rim stands above it fills to the rim; a dry hollow fills only
    # when it is far too deep to be a hollow
    keep[1:] = (haswet & (maxd >= LAKE_MIN_RISE)) | (~haswet & (maxd >= PIT_MIN_DEPTH))
    apply = keep[lab]
    rep.append(f"fill: {n} closed basins; filling {int((keep[1:] & haswet).sum())} lake basins and "
               f"{int((keep[1:] & ~haswet).sum())} dry pits deeper than {PIT_MIN_DEPTH:g} m "
               f"({int(apply.sum())} cells, deepest {float(maxd.max()) if n else 0:.0f} m)")

    H1, W1, wet1 = H.copy(), W.copy(), wet.copy()
    m_lake = apply & vis
    m_flood = apply & ~vis & (depth >= FLOOD_MIN)
    m_shore = apply & ~vis & (depth < FLOOD_MIN)
    L = fill - LIP
    # a lake carried up keeps its bed under it
    H1[m_lake] = H[m_lake] + (L[m_lake] - W[m_lake])
    W1[m_lake] = L[m_lake]
    # drowned basin floor becomes water over a shallow bed
    H1[m_flood] = np.maximum(H[m_flood], L[m_flood] - TARN_DEPTH)
    W1[m_flood] = L[m_flood]
    wet1[m_flood] = True
    # cells between the new surface and the spill rim stay exactly as they
    # are: the natural bank (a buried sea cell there is dry now)
    W1[m_shore] = np.nan
    wet1[m_shore] = False
    lifted = np.unique(lab[m_lake]).size
    tarns = ndimage.label(m_flood & ~ndimage.binary_dilation(vis, iterations=1))[1]
    rep.append(f"fill: {lifted} lake basins carried up, {int(m_flood.sum())} cells flooded "
               f"(~{tarns} new tarns), {int(m_shore.sum())} bank cells left as they are")
    if m_lake.any():
        rise = L[m_lake] - W[m_lake]
        rep.append(f"fill: lakes rose {float(rise.min()):.1f} .. {float(rise.max()):.1f} m (mean {float(rise.mean()):.1f})")
    info = {"H_before": H, "W_before": W, "m_lake": m_lake, "m_flood": m_flood, "m_shore": m_shore,
            "basin": np.where(apply, lab, 0)}
    return H1, W1, wet1, info, int(apply.sum())


def _cut(H, W, wet, fixed, rep, tag, cut_mask):
    Wn, vis = _visible(H, W, wet)
    C = _cone(Wn, vis, SLOPE_CAP, top=float(H.max()) + 1.0)
    cut = (H > C + 0.05) & ~vis & ~fixed     # 0.05: the r16 quantum is 0.01
    cut_mask |= cut
    H1 = H.copy()
    if cut.any():
        drop = H[cut] - C[cut]
        rep.append(f"{tag}: {int(cut.sum())} cells lowered under the {SLOPE_CAP:g}:1 cone "
                   f"(mean {float(drop.mean()):.1f} m, max {float(drop.max()):.0f} m)")
        H1[cut] = C[cut]
    else:
        rep.append(f"{tag}: nothing stands over the cone")
    return H1


def _rim_min(H, vis, only=None):
    """Per cell: the lowest DRY 8-neighbour's height (inf where none);
    with `only`, just those neighbours."""
    Hd = np.where(vis, np.inf, H)
    if only is not None:
        Hd = np.where(only, Hd, np.inf)
    out = np.full(H.shape, np.inf)
    for dz in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dz == 0 and dx == 0:
                continue
            out = np.minimum(out, np.roll(np.roll(Hd, dz, axis=0), dx, axis=1))
    return out


def _drain(H, W, wet, info, cut_mask, cap, rep):
    """A body the fill raised or made, whose rim a CUT has since lowered under
    its surface, settles down to that rim (lowest cut neighbour - LIP). A
    shore the bake itself left under the water is not a reason to drain --
    that is the embankment's job."""
    Wn, vis = _visible(H, W, wet)
    touched = info["m_lake"] | info["m_flood"]
    lab, n = ndimage.label(vis, structure=np.ones((3, 3)))
    if n == 0:
        return H, W, wet, 0
    idx = np.arange(1, n + 1)
    rim = _rim_min(H, vis, only=cut_mask)
    rim[~vis] = np.inf
    body_rim = np.asarray(ndimage.minimum(rim, lab, index=idx))
    body_lvl = np.asarray(ndimage.median(Wn, lab, index=idx))
    body_new = np.asarray(ndimage.maximum(touched.astype(np.uint8), lab, index=idx)) > 0
    low = body_new & np.isfinite(body_rim) & (body_rim < body_lvl - 0.05)
    if not low.any():
        rep.append("drain: no filled body stands over its rim")
        return H, W, wet, 0
    H1, W1, wet1 = H.copy(), W.copy(), wet.copy()
    Hb, Wb = info["H_before"], info["W_before"]
    Wbn = np.nan_to_num(Wb, nan=-1e9)
    drained = 0
    biggest = 0.0
    for i in np.where(low)[0]:
        body = lab == i + 1
        new_lvl = float(body_rim[i]) - LIP
        biggest = max(biggest, float(body_lvl[i]) - new_lvl)
        # its whole basin comes with it: the shore ring and the flooded floor
        bid = np.unique(info["basin"][body])
        bid = bid[bid > 0]
        basin = np.isin(info["basin"], bid) if bid.size else body
        area = basin | body
        lk = area & info["m_lake"]
        fl = area & info["m_flood"]
        sh = area & info["m_shore"]
        # original lake cells keep their depth under the new surface
        H1[lk] = Hb[lk] + (new_lvl - Wbn[lk])
        W1[lk] = new_lvl
        # flooded floor: back to dry ground where the old ground clears the new
        # surface, else water over a shallow bed
        dry = fl & (Hb >= new_lvl - 0.05)
        wetf = fl & ~dry
        H1[dry] = Hb[dry]
        W1[dry] = np.nan
        wet1[dry] = False
        H1[wetf] = np.maximum(Hb[wetf], new_lvl - TARN_DEPTH)
        W1[wetf] = new_lvl
        # the raised shore ring goes back to the ground it was
        H1[sh] = Hb[sh]
        cap[area] = np.minimum(cap[area], new_lvl + LIP)
        drained += 1
    rep.append(f"drain: {drained} filled bodies settled to their cut rim (largest drop {biggest:.1f} m)")
    return H1, W1, wet1, drained


def _embank(H, W, wet, fixed, rep):
    """Dry ground under a neighbouring water surface is raised to the water,
    then a 72-degree bank runs down from it: the perched lake keeps its level
    and shows a bank instead of a wall of water."""
    Wn, vis = _visible(H, W, wet)
    Wv = np.where(vis, Wn, -1e9)
    wmax = np.full(H.shape, -1e9)
    for dz in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dz == 0 and dx == 0:
                continue
            wmax = np.maximum(wmax, np.roll(np.roll(Wv, dz, axis=0), dx, axis=1))
    lip = ~vis & ~fixed & (wmax > -1e8) & (H < wmax - 1e-3)
    H1 = H.copy()
    if not lip.any():
        rep.append("embank: no dry ground lies under a neighbouring water surface")
        return H1, 0
    worst = float((wmax - H)[lip].max())
    H1[lip] = wmax[lip] + LIP * 0.5
    # the bank: a rising cone from every lip, applied to dry ground only
    src = np.full(H.shape, -np.inf)
    src[lip] = H1[lip]
    B = -_cone(-src, lip, SLOPE_CAP, top=-float(H.min()) + 1.0)   # max over lips of (lip - slope*d)
    bank = ~vis & ~fixed & ~lip & (H1 < B - 1e-6)
    H1[bank] = B[bank]
    rep.append(f"embank: {int(lip.sum())} shore cells raised to their water (worst {worst:.1f} m under it), "
               f"{int(bank.sum())} bank cells behind them")
    return H1, int(lip.sum() + bank.sum())


def _residuals(H, W, wet, fixed, rep):
    Wn, vis = _visible(H, W, wet)
    dx = np.abs(np.diff(H, axis=1))
    dz = np.abs(np.diff(H, axis=0))
    rep.append(f"left: {int((dx > 40).sum() + (dz > 40).sum())} steps over 40 m, "
               f"{int((dx > 20).sum() + (dz > 20).sum())} over 20 m (per 4 m cell)")


def _cone(W: np.ndarray, wet: np.ndarray, slope: float, max_iter: int = 400, top: float = np.inf) -> np.ndarray:
    """min over wet q of (W(q) + slope * |p - q|), 8-connected chamfer.

    `top`: nothing stands higher than this, so the cone is clamped there --
    the chamfer then converges in ~top/(slope*STEP) sweeps instead of
    crawling to the far corner of the map (2026-09-02: 25 min -> 1 min)."""
    C = np.full(W.shape, np.inf)
    C[wet] = W[wet]
    C = np.minimum(C, top)
    d1 = slope * STEP
    d2 = slope * STEP * np.sqrt(2.0)
    for _ in range(max_iter):
        P = C.copy()
        C[1:, :] = np.minimum(C[1:, :], P[:-1, :] + d1)
        C[:-1, :] = np.minimum(C[:-1, :], P[1:, :] + d1)
        C[:, 1:] = np.minimum(C[:, 1:], P[:, :-1] + d1)
        C[:, :-1] = np.minimum(C[:, :-1], P[:, 1:] + d1)
        C[1:, 1:] = np.minimum(C[1:, 1:], P[:-1, :-1] + d2)
        C[:-1, :-1] = np.minimum(C[:-1, :-1], P[1:, 1:] + d2)
        C[1:, :-1] = np.minimum(C[1:, :-1], P[:-1, 1:] + d2)
        C[:-1, 1:] = np.minimum(C[:-1, 1:], P[1:, :-1] + d2)
        if np.isfinite(top):
            np.minimum(C, top, out=C)
        if np.array_equal(C, P):
            break
    return C


# --------------------------------------------------------------------- meta --
def _remeta(meta: dict, Hg: np.ndarray) -> None:
    """Re-derive the y of every named place and re-snap the summits, the way
    mainegen.py does it, against the relaxed heights."""
    sys.path.insert(0, HERE)
    import maine_map as M
    ny, nx = Hg.shape

    def ground_at(mx, my):
        fx = (mx - M.X_MIN) / M.BAKE_STEP
        fy = (M.Y_MAX - my) / M.BAKE_STEP
        ix, iy = int(np.floor(fx)), int(np.floor(fy))
        tx, ty = fx - ix, fy - iy

        def h(a, b):
            return float(Hg[np.clip(b, 0, ny - 1), np.clip(a, 0, nx - 1)])
        top = h(ix, iy) * (1 - tx) + h(ix + 1, iy) * tx
        bot = h(ix, iy + 1) * (1 - tx) + h(ix + 1, iy + 1) * tx
        return top * (1 - ty) + bot * ty

    pl = M.places()
    by_name = {c["name"]: c for c in pl["cities"]}
    for p in meta["places"]:
        c = by_name.get(p["name"])
        if c is not None:
            p["y"] = round(ground_at(c["x"], c["y"]), 2)
    by_name = {l["name"]: l for l in pl["lakes"]}
    for p in meta["lakes"]:
        l = by_name.get(p["name"])
        if l is not None:
            p["y"] = round(ground_at(l["x"], l["y"]), 2)
    peaks = []
    for name, lon, lat, real_m in M.PEAKS:
        mx, my = M.lonlat_to_map(lon, lat)
        cx = int(np.clip((mx - M.X_MIN) / M.BAKE_STEP, 0, nx - 1))
        cy = int(np.clip((M.Y_MAX - my) / M.BAKE_STEP, 0, ny - 1))
        rr = int(round(M.PEAK_SNAP_R / M.BAKE_STEP))
        y0, y1 = max(0, cy - rr), min(ny, cy + rr)
        x0, x1 = max(0, cx - rr), min(nx, cx + rr)
        win = Hg[y0:y1, x0:x1]
        oy, ox = np.unravel_index(int(np.argmax(win)), win.shape)
        py, px = y0 + oy, x0 + ox
        x, z = M.map_to_world(M.X_MIN + px * M.BAKE_STEP, M.Y_MAX - py * M.BAKE_STEP)
        peaks.append({"name": name, "pos": [round(x, 1), round(z, 1)],
                      "y": round(float(Hg[py, px]), 1), "real_m": real_m})
    peaks.sort(key=lambda p: -p["real_m"])
    kept = []
    for p in peaks:
        far = M.PEAK_MERGE_R
        if p["name"] in M.PEAK_KEEP:
            far = 90.0
        if all((p["pos"][0] - q["pos"][0]) ** 2 + (p["pos"][1] - q["pos"][1]) ** 2 > far ** 2 for q in kept):
            kept.append(p)
    meta["peaks"] = sorted(kept, key=lambda p: -p["y"])
    # The story route is authored by name. A relaxation can move a snapped
    # summit, so refresh every route point from the final canonical records.
    canonical = {p["name"]: p["pos"] for p in meta["places"]}
    canonical.update({p["name"]: p["pos"] for p in meta["peaks"]})
    for act in meta.get("story_route", []):
        for point in act.get("points", []):
            if point["name"] not in canonical:
                raise RuntimeError(f"story route anchor disappeared during relax: {point['name']}")
            point["pos"] = canonical[point["name"]]


def write_preview() -> None:
    """Redraw maine_preview.png from the files on disk (mainegen.preview)."""
    from PIL import Image
    sys.path.insert(0, HERE)
    import mainegen
    meta = json.load(open(os.path.join(OUT, "maine_meta.json")))
    nx, nz = meta["samples"]
    h_min, h_max = meta["height_range"]
    w_min, w_max = meta["water_range"]
    hq = np.fromfile(os.path.join(OUT, "maine_height.r16"), dtype="<u2").reshape(nz, nx)
    wq = np.fromfile(os.path.join(OUT, "maine_water.r16"), dtype="<u2").reshape(nz, nx)
    Hg = (h_min + hq.astype(np.float64) / 65535.0 * (h_max - h_min)).astype(np.float32)
    Wg = np.where(wq > 0, w_min + (wq.astype(np.float64) - 1) / 65534.0 * (w_max - w_min), 0.0).astype(np.float32)
    C = np.asarray(Image.open(os.path.join(OUT, "maine_color.png")).convert("RGB")).astype(np.float32) / 255.0
    mainegen.preview(Hg, Wg, C, meta)


if __name__ == "__main__":
    sys.exit(main("--dry-run" in sys.argv))
