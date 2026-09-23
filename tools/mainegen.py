"""
Myrkfell — bake the game terrain from the recovered Maine geography.

    python3 tools/mainegen.py            # ~30 s

Reads assets/terrain/macro/ (20 m macro grids + places, see maine_map.py) and
writes the game-resolution maps into assets/terrain/:

    maine_height.r16   1800 x 2700 uint16, row 0 = NORTH, range in meta
    maine_water.r16    same grid; 0 = dry, else the water SURFACE height
    maine_color.png    1800 x 2700 RGB8 ground tint (shader + scatter read it)
    maine_meta.json    sizes, spacing, origin, sea level, every named place
    maine_preview.png  the N-key map art

The macro grids carry the real geography at 20 m. This adds the fine detail a
4 m bake needs -- ridged fractal spurs and gullies gated to high, steep, dry
ground, exactly the way the 2026-08-22 blockout generator did it -- then pins
Katahdin to 600 m over a -22.5 sea level and flattens the spawn valley.
"""

import json, os, sys
import numpy as np
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import maine_map as M

OUT = os.path.join(M.REPO, "assets", "terrain")
RNG = np.random.default_rng(20260827)      # the build date: stable output

# The recovered macro map is Katahdin-dominant: Katahdin stands at 1022 blend-z
# while Old Speck -- 79% of Katahdin in the real world -- came out of the 08-27
# generator at 186, i.e. 18%. That leaves the "western wall" of the blockout
# plan as a line of foothills. PIN_PEAKS grows each named summit back toward
# its true share of Katahdin, as a smooth bump combined by max, so nothing is
# ever carved down and the recovered geography elsewhere is untouched.
# Set False to bake the macro exactly as the Blender map had it.
PIN_PEAKS = False      # world v2 (tools/myrkgen.py) designs its own peaks
KATAHDIN_REAL_M = 1606.0
KATAHDIN_MACRO_Z = 1022.22
PEAK_SIGMA_BASE = 190.0      # metres of map, at 0 m of real height
PEAK_SIGMA_GAIN = 360.0      # ...plus this much at Katahdin's height (~550 m)
PEAK_FALLOFF    = 1.5        # exp(-(d/sigma)^p): under 2 = a sharper crown
PEAK_ALONG      = 1.85       # stretch the footprint along the range...
PEAK_ACROSS     = 0.70       # ...and pinch it across, so peaks make ridges
PEAK_WARP       = 0.55       # lobe the outline with noise (0 = a circle)
PEAK_CREST      = 0.42       # how much ridged crest rides on the new mass
PEAK_CHAIN_R    = 3000.0     # a peak orients on its neighbour within this

# Towns want buildable ground. Each city site is levelled to its own local
# median and eased back out, so "paint the meadows, then build" starts from a
# flat pad instead of a hillside.
DETAIL_M = 38.0         # spurs on the ranges; the 08-30 bake used 120 (v2 is stylized)
FLATTEN_TOWNS = True
TOWN_R = {0: 55.0, 1: 85.0, 2: 120.0, 3: 200.0}  # village / town / city / metro
TOWN_EASE = 90.0
METRO_FLOOR = 10.0       # game y; Portland/Brunswick pads must stay visibly above the sea
# Extra flatten discs (map metres), matching tools/myrkgen.METRO_PADS.
METRO_PADS = [
    (-2020.0, -3980.0, 190.0),   # Portland south-east toward Casco
    (-1774.0, -3264.0, 170.0),   # Brunswick–Freeport span
]


def town_rank(dim0):
    if dim0 >= 320:
        return 3
    if dim0 >= 220:
        return 2
    if dim0 >= 170:
        return 1
    return 0


# ------------------------------------------------------------------- noise ---
def value_noise(shape, cells, rng):
    """Smooth value noise: a coarse random lattice, bicubically inflated."""
    gy = max(2, int(round(shape[0] / cells)))
    gx = max(2, int(round(shape[1] / cells)))
    g = rng.random((gy + 2, gx + 2)).astype(np.float32)
    z = ndimage.zoom(g, (shape[0] / g.shape[0], shape[1] / g.shape[1]), order=3)
    return z[:shape[0], :shape[1]]


def ridged_fbm(shape, rng, octaves=5, cells=180.0, gain=0.5, lacunarity=2.0):
    """Ridged multifractal -- sharp crests, smooth valleys. Returns 0..1."""
    out = np.zeros(shape, dtype=np.float32)
    amp, c, norm = 1.0, cells, 0.0
    for _ in range(octaves):
        n = value_noise(shape, c, rng)
        n = 1.0 - np.abs(n * 2.0 - 1.0)          # ridge
        out += (n * n) * amp
        norm += amp
        amp *= gain
        c /= lacunarity
    return out / max(norm, 1e-6)


# -------------------------------------------------------------------- bake ---
def main():
    os.makedirs(OUT, exist_ok=True)
    H0, W0, C0, xs, ys = M.macro()

    # row 0 = north. The macro arrays come out of Blender with +y ascending.
    H0 = H0[::-1].copy(); W0 = W0[::-1].copy(); C0 = C0[::-1].copy()

    ny, nx = M.BAKE_NY, M.BAKE_NX
    zy, zx = ny / H0.shape[0], nx / H0.shape[1]
    print(f"macro {H0.shape} @ {M.MACRO_STEP:g} m  ->  bake ({ny}, {nx}) @ {M.BAKE_STEP:g} m")

    H = ndimage.zoom(H0, (zy, zx), order=3).astype(np.float32)[:ny, :nx]
    # water class must not be smeared by interpolation: nearest, then flatten
    Wn = ndimage.zoom(W0, (zy, zx), order=0).astype(np.float32)[:ny, :nx]
    C = np.stack([ndimage.zoom(C0[..., k], (zy, zx), order=1)[:ny, :nx] for k in range(3)], -1)
    C = np.clip(C, 0.0, 1.0).astype(np.float32)

    dry   = Wn <= -199.0
    ocean = np.abs(Wn) < 1e-4
    lake  = ~dry & ~ocean
    print(f"  dry {dry.sum()/dry.size:.1%}   ocean {ocean.sum()/dry.size:.1%}   lake {lake.sum()/dry.size:.1%}")

    # --- pin the named summits back to their real relative height ------------
    if PIN_PEAKS:
        base = ndimage.gaussian_filter(H, 26.0)      # ~100 m of smoothed ground
        mxg = M.X_MIN + np.arange(nx) * M.BAKE_STEP
        myg = M.Y_MAX - np.arange(ny) * M.BAKE_STEP
        # Two noise fields shared by every summit: one lobes the footprint so
        # the outline is not a circle, one puts crests and gullies on the new
        # mass so it reads as rock rather than a dome.
        warp = value_noise((ny, nx), 150.0, RNG).astype(np.float32)
        crest = ridged_fbm((ny, nx), RNG, octaves=4, cells=70.0).astype(np.float32)
        crest = (crest - float(crest.mean())) / max(float(crest.std()), 1e-6)

        # Orient each summit on its nearest neighbour, so a chain of peaks
        # raises a ridgeline instead of a row of muffins.
        pxy = [M.lonlat_to_map(lon, lat) for _, lon, lat, _ in M.PEAKS]
        lifted = 0
        for i, (name, lon, lat, real_m) in enumerate(M.PEAKS):
            px, py = pxy[i]
            tz = (real_m / KATAHDIN_REAL_M) * KATAHDIN_MACRO_Z
            sig = PEAK_SIGMA_BASE + PEAK_SIGMA_GAIN * (real_m / KATAHDIN_REAL_M)

            best, bd = None, PEAK_CHAIN_R ** 2
            for j, (qx, qy) in enumerate(pxy):
                if j == i:
                    continue
                dd = (qx - px) ** 2 + (qy - py) ** 2
                if dd < bd:
                    bd, best = dd, j
            if best is None:
                ux, uy = 1.0, 0.0
            else:
                vx, vy = pxy[best][0] - px, pxy[best][1] - py
                n = max((vx * vx + vy * vy) ** 0.5, 1e-6)
                ux, uy = vx / n, vy / n

            rad = sig * PEAK_ALONG * 3.0
            x0 = max(0, int((px - rad - M.X_MIN) / M.BAKE_STEP))
            x1 = min(nx, int((px + rad - M.X_MIN) / M.BAKE_STEP) + 1)
            y0 = max(0, int((M.Y_MAX - (py + rad)) / M.BAKE_STEP))
            y1 = min(ny, int((M.Y_MAX - (py - rad)) / M.BAKE_STEP) + 1)
            if x1 <= x0 or y1 <= y0:
                continue
            dx = (mxg[x0:x1] - px)[None, :]
            dy = (myg[y0:y1] - py)[:, None]
            along = dx * ux + dy * uy
            across = -dx * uy + dy * ux
            d = np.hypot(along / PEAK_ALONG, across / PEAK_ACROSS)
            d = d * (1.0 + PEAK_WARP * (warp[y0:y1, x0:x1] - 0.5) * 2.0)

            g = np.exp(-np.power(np.maximum(d, 0.0) / sig, PEAK_FALLOFF))
            edge = float(np.exp(-(3.0 ** PEAK_FALLOFF)))
            g = np.clip((g - edge) / (1.0 - edge), 0.0, 1.0)   # 0 at the rim
            g *= 1.0 + PEAK_CREST * crest[y0:y1, x0:x1] * (1.0 - g) * 2.0
            g = np.clip(g, 0.0, 1.0)

            b = base[y0:y1, x0:x1]
            want = b + (tz - b) * g
            # A pin may raise a headland out of the sea -- that is how Acadia's
            # granite and the Camden Hills get to be land at 20 m of macro. It
            # must never raise a lake bed: an inland lake keeps its surface
            # while the range grows around it.
            want = np.where(lake[y0:y1, x0:x1], -1e9, want)
            sx_ = int(np.clip((px - M.X_MIN) / M.BAKE_STEP, 0, nx - 1))
            sy_ = int(np.clip((M.Y_MAX - py) / M.BAKE_STEP, 0, ny - 1))
            was = float(H[sy_, sx_])
            H[y0:y1, x0:x1] = np.maximum(H[y0:y1, x0:x1], want)
            if float(H[sy_, sx_]) > was + 1.0:
                lifted += 1
        print(f"  peaks pinned: {lifted}/{len(M.PEAKS)} summits raised toward their real share")

    # --- fine detail, gated to high steep dry ground -------------------------
    gy, gx = np.gradient(H, M.BAKE_STEP)
    slope = np.hypot(gy, gx)
    elev = np.clip(H / max(1.0, H0.max()), 0.0, 1.0)
    gate = np.clip(elev / 0.55, 0.0, 1.0) ** 1.2 * np.clip(slope / 0.18, 0.20, 1.0)
    gate[~dry] = 0.0
    gate = ndimage.gaussian_filter(gate, 2.0)

    ridge = ridged_fbm((ny, nx), RNG, octaves=3, cells=220.0)
    ridge -= float(ridge.mean())
    detail = ridge * gate * DETAIL_M                     # spurs and gullies on the ranges
    # a whisper of roll on the lowlands so flat farmland is not a table
    roll = (value_noise((ny, nx), 70.0, RNG) - 0.5) * 4.0
    detail += roll * dry * (1.0 - np.clip(elev * 3.0, 0, 1))
    H = H + detail
    print(f"  detail  mean |d| {np.abs(detail).mean():.2f} m   max {np.abs(detail).max():.1f} m (blend z)")

    # --- water: flatten each lake surface, sink its bed -----------------------
    # PIN_PEAKS and the detail pass can lift ground the macro had classed as
    # water (Acadia's granite is a coastal cell; Cadillac's summit landed under
    # the ocean clamp and came out at -22.7 m). Anything that now stands proud
    # of its own water surface stops being water.
    risen_sea = ocean & (H > 0.35)
    risen_lake = lake & (H > Wn + 0.2)
    if risen_sea.any() or risen_lake.any():
        print(f"  reclassified to land: {int(risen_sea.sum())} sea + {int(risen_lake.sum())} lake cells"
              f"  ({(risen_sea.sum()+risen_lake.sum())*M.BAKE_STEP**2/1e6:.2f} km2)")
        ocean = ocean & ~risen_sea
        lake = lake & ~risen_lake
        dry = dry | risen_sea | risen_lake
        Wn = np.where(risen_sea | risen_lake, -200.0, Wn)

    Hs = H.copy()
    if lake.any():
        lab, n = ndimage.label(lake)
        for i in range(1, n + 1):
            m = lab == i
            s = float(np.median(Wn[m]))
            Wn[m] = s
            Hs[m] = np.minimum(Hs[m], s - 1.6)        # a bed under the surface
        print(f"  lakes flattened: {n} bodies")
    Hs[ocean] = np.minimum(Hs[ocean], -0.35)
    Wn[ocean] = 0.0
    H = Hs

    # --- vertical: Katahdin 600 m over a -22.5 sea ---------------------------
    # Pin from the POST-detail maximum, so the ridged pass can never push the
    # roof past the height locked with Lemon in the 2026-08-22 blockout.
    z_top = float(H.max())
    vs = (M.KATAHDIN_GAME_Y - M.SEA_LEVEL) / z_top
    print(f"  vertical: blend z_top {z_top:.1f} -> y {M.KATAHDIN_GAME_Y:g}  (scale {vs:.5f})")
    Hg = (H * vs + M.SEA_LEVEL).astype(np.float32)
    Wg = np.where(dry, 0.0, Wn * vs + M.SEA_LEVEL).astype(np.float32)

    # --- level a pad under every town ---------------------------------------
    if FLATTEN_TOWNS:
        pads = 0
        flatten_sites = [(cx, cy, r, "") for cx, cy, r in METRO_PADS]
        flatten_sites.extend((c["x"], c["y"], TOWN_R[town_rank(c["dim"][0])], c["name"])
                             for c in M.places()["cities"])
        for cx_m, cy_m, r, name in flatten_sites:
            rad = r + TOWN_EASE
            cx = (cx_m - M.X_MIN) / M.BAKE_STEP
            cy = (M.Y_MAX - cy_m) / M.BAKE_STEP
            x0, x1 = max(0, int(cx - rad / M.BAKE_STEP) - 1), min(nx, int(cx + rad / M.BAKE_STEP) + 2)
            y0, y1 = max(0, int(cy - rad / M.BAKE_STEP) - 1), min(ny, int(cy + rad / M.BAKE_STEP) + 2)
            if x1 <= x0 or y1 <= y0:
                continue
            ddx = (np.arange(x0, x1) - cx) * M.BAKE_STEP
            ddy = (np.arange(y0, y1) - cy) * M.BAKE_STEP
            dd = np.hypot(ddx[None, :], ddy[:, None])
            win = Hg[y0:y1, x0:x1]
            inner = dd <= r
            if not inner.any():
                continue
            lvl = float(np.median(win[inner]))
            # A harbour town sits ON the shore; an inland town must not inherit
            # the sea-floor height merely because its compressed border cell
            # touched the exterior mask.
            floor = M.SEA_LEVEL + (3.5 if name in M.COASTAL_PLACES else 25.0)
            # extra metro discs (empty name) and rank-3 pads share the city floor
            if name == "" or r >= TOWN_R[3]:
                floor = max(floor, METRO_FLOOR)
            lvl = max(lvl, floor)
            tt = np.clip((dd - r) / TOWN_EASE, 0.0, 1.0)
            tt = tt * tt * (3.0 - 2.0 * tt)
            # never raise the exterior sea floor into a metro pad
            lifted = win * tt + lvl * (1.0 - tt)
            if name == "":
                # extra discs only fill toward the water; they must not shave
                # an already-flattened city pad (Portland 2026-09-18: 10 m -> 5.6)
                lifted = np.maximum(win, lifted)
            Hg[y0:y1, x0:x1] = np.where(win >= M.SEA_LEVEL, lifted, win)
            pads += 1
        print(f"  town pads levelled: {pads}")

    # --- the spawn valley: flat disc at y = 0, eased to the real hills --------
    wx = np.arange(nx) * M.BAKE_STEP + M.X_MIN - M.ORIGIN[0]
    wz = -((M.Y_MAX - np.arange(ny) * M.BAKE_STEP) - M.ORIGIN[1])
    d = np.hypot(wx[None, :], wz[:, None])
    t = np.clip((d - M.VALLEY_FLAT_R) / (M.VALLEY_EASE_R - M.VALLEY_FLAT_R), 0.0, 1.0)
    t = t * t * (3.0 - 2.0 * t)                        # smoothstep
    Hg = Hg * t + 0.0 * (1.0 - t)
    inval = d < M.VALLEY_EASE_R
    Wg[d < M.VALLEY_EASE_R] = 0.0                      # no ponds in the clearing
    print(f"  valley disc: {int(inval.sum())} cells eased to y=0 at world origin")

    # --- encode ---------------------------------------------------------------
    h_min, h_max = float(Hg.min()), float(Hg.max())
    hq = np.clip((Hg - h_min) / (h_max - h_min), 0, 1)
    (hq * 65535.0 + 0.5).astype("<u2").tofile(os.path.join(OUT, "maine_height.r16"))

    wet = Wg != 0.0
    w_min = float(Wg[wet].min()) if wet.any() else 0.0
    w_max = float(Wg[wet].max()) if wet.any() else 0.0
    wq = np.zeros((ny, nx), dtype="<u2")
    if wet.any():
        wq[wet] = (1 + (Wg[wet] - w_min) / max(w_max - w_min, 1e-6) * 65534.0).astype("<u2")
    wq.tofile(os.path.join(OUT, "maine_water.r16"))

    from PIL import Image
    Image.fromarray((C * 255 + 0.5).astype(np.uint8), "RGB").save(os.path.join(OUT, "maine_color.png"))

    # --- meta -----------------------------------------------------------------
    def ground_at(mx, my):
        """Bilinear, exactly as Terrain.sample_height() does it at runtime."""
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
    meta = {
        "generated": "tools/mainegen.py",
        "size": [M.X_MAX - M.X_MIN, M.Y_MAX - M.Y_MIN],
        "samples": [nx, ny], "spacing": M.BAKE_STEP,
        "row0": "north", "origin_map": list(M.ORIGIN),
        "sea_level": M.SEA_LEVEL,
        "height_range": [h_min, h_max],
        "water_range": [w_min, w_max], "water_dry": 0,
        "valley": {"flat_r": M.VALLEY_FLAT_R, "ease_r": M.VALLEY_EASE_R},
        "bounds_world": {
            "x": [M.X_MIN - M.ORIGIN[0], M.X_MAX - M.ORIGIN[0]],
            "z": [-(M.Y_MAX - M.ORIGIN[1]), -(M.Y_MIN - M.ORIGIN[1])]},
        "playable_area_sq_mi": round((M.X_MAX - M.X_MIN) * (M.Y_MAX - M.Y_MIN) / 2589988.11, 2),
        "land_area_sq_mi": round(float(dry.sum()) * M.BAKE_STEP ** 2 / 2589988.11, 2),
        "places": [], "lakes": [], "regions": [], "peaks": [], "story_route": [],
    }
    for c in pl["cities"]:
        x, z = M.map_to_world(c["x"], c["y"])
        meta["places"].append({"name": c["name"], "pos": [round(x, 1), round(z, 1)],
                               "y": round(ground_at(c["x"], c["y"]), 2),
                               "rank": town_rank(c["dim"][0])})
    for l in pl["lakes"]:
        x, z = M.map_to_world(l["x"], l["y"])
        meta["lakes"].append({"name": l["name"], "pos": [round(x, 1), round(z, 1)],
                              "y": round(ground_at(l["x"], l["y"]), 2)})
    for r in pl["regions"]:
        x, z = M.map_to_world(r["x"], r["y"])
        meta["regions"].append({"name": r["name"], "pos": [round(x, 1), round(z, 1)],
                                "r": round(r["dim"][0] / 2.0, 1)})
    # summits: real lon/lat, then snapped to the local max the bake produced
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
        smx = M.X_MIN + px * M.BAKE_STEP
        smy = M.Y_MAX - py * M.BAKE_STEP
        x, z = M.map_to_world(smx, smy)
        meta["peaks"].append({"name": name, "pos": [round(x, 1), round(z, 1)],
                              "y": round(float(Hg[py, px]), 1), "real_m": real_m})
    # 47x horizontal compression puts whole ranges on top of each other -- Hamlin
    # lands on Katahdin. Traveler is a separate horn (~285 m) and must keep a cairn.
    meta["peaks"].sort(key=lambda p: -p["real_m"])
    kept = []
    for p in meta["peaks"]:
        far = M.PEAK_MERGE_R
        if p["name"] in M.PEAK_KEEP:
            far = 90.0
        if all((p["pos"][0] - q["pos"][0]) ** 2 + (p["pos"][1] - q["pos"][1]) ** 2 > far ** 2
               for q in kept):
            kept.append(p)
    dropped = [p["name"] for p in meta["peaks"] if p not in kept]
    if dropped:
        print(f"  summits merged by compression ({len(dropped)}): {', '.join(dropped)}")
    meta["peaks"] = sorted(kept, key=lambda p: -p["y"])

    # The authored journey is resolved only after towns and summits have their
    # final baked positions. Consumers never need to know lon/lat, punctuation
    # aliases or whether an anchor is a settlement or a landmark.
    anchors = {p["name"]: (p["pos"], "place") for p in meta["places"]}
    anchors.update({p["name"]: (p["pos"], "peak") for p in meta["peaks"]})
    for act in M.STORY_ROUTE:
        points = []
        for name in act["places"]:
            if name not in anchors:
                raise RuntimeError(f"story route anchor did not bake: {name}")
            pos, kind = anchors[name]
            points.append({"name": name, "kind": kind, "pos": pos})
        meta["story_route"].append({
            "act": act["act"], "name": act["name"], "levels": act["levels"],
            "promise": act["promise"], "points": points,
        })
    json.dump(meta, open(os.path.join(OUT, "maine_meta.json"), "w"), indent=1)

    # --- water sanity: the town pads above run AFTER the lake levelling and
    # ignore water, so a pad can drop the ground 16 m under a lake surface
    # (Portland, 2026-08-31). water_relevel re-levels every inland body against
    # the baked heights, in place, and is idempotent.
    # terrain_relax first: PIN_PEAKS exempts lake cells from the raise, which
    # leaves every mountain lake at the bottom of a 300 m shaft and turned one
    # ex-lake on Katahdin into a dry pit (2026-08-31, second survey). It lifts
    # the lakes to their spill points, floods the pits into tarns and cuts the
    # walls to 72 degrees; water_relevel then tidies what is left.
    import terrain_relax
    terrain_relax.main(False)
    import water_relevel
    water_relevel.main(False)

    # --- preview art (from the files, which the two passes just rewrote) ------
    terrain_relax.write_preview()

    print(f"\n  height  {h_min:8.2f} .. {h_max:8.2f} m")
    print(f"  water   {w_min:8.2f} .. {w_max:8.2f} m   (sea {M.SEA_LEVEL})")
    print(f"  tallest {meta['peaks'][0]['name']} at y {meta['peaks'][0]['y']}")
    for f in ("maine_height.r16", "maine_water.r16", "maine_color.png",
              "maine_meta.json", "maine_preview.png"):
        p = os.path.join(OUT, f)
        print(f"    {f:20} {os.path.getsize(p)/1048576:7.2f} MB")


def preview(Hg, Wg, C, meta, w=900):
    """The N-key map: shaded relief over the ground colour, water on top."""
    from PIL import Image
    ny, nx = Hg.shape
    h = int(w * ny / nx)
    sy, sx = ny / h, nx / w
    idx_y = (np.arange(h) * sy).astype(int)
    idx_x = (np.arange(w) * sx).astype(int)
    Hs = Hg[np.ix_(idx_y, idx_x)]
    Ws = Wg[np.ix_(idx_y, idx_x)]
    Cs = C[np.ix_(idx_y, idx_x)]

    gy, gx = np.gradient(ndimage.gaussian_filter(Hs, 1.4))
    # world v2 is cliffs and plateaus: a softer light, so the map reads as
    # a map and not as a relief carving
    shade = np.clip(0.78 + (gx * 0.75 - gy * 0.75) / 24.0, 0.45, 1.25)
    hi = np.clip((Hs - meta["sea_level"]) / 500.0, 0.0, 1.0)[..., None]
    img = np.clip(Cs * shade[..., None] * (1.0 - 0.15 * hi) + 0.10 * hi, 0, 1)

    wet = Ws != 0.0
    depth = np.clip((Ws - Hs) / 26.0, 0.06, 1.0)[..., None]
    water_col = np.array([0.18, 0.33, 0.46]) * (1.0 - depth * 0.55) + np.array([0.05, 0.10, 0.22]) * depth
    img[wet] = water_col[wet]
    Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGB").save(
        os.path.join(OUT, "maine_preview.png"))


if __name__ == "__main__":
    main()
