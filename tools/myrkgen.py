"""
Myrkfell — the stylized Maine (world v2, 2026-09-02).

    python3 tools/myrkgen.py            # ~10 s, then run tools/mainegen.py

Loosely inspired by Maine, built like a Breath of the Wild overworld: a few
big clean landforms you can read from the far side of the map, cliffs and
plateaus instead of noise, scenic set-pieces with names.  Writes the 20 m
macro grids that tools/mainegen.py bakes into the game:

    assets/terrain/macro/maine_macro.npz    H / W / C / xs / ys, row 0 = SOUTH
    assets/terrain/macro/places.json        50 cities / 30 lakes / 18 regions
    assets/terrain/macro/myrk_preview.png   quick shaded relief, for a look

The 50 city sites keep their positions from the recovered .blend (the game's
meta, teleport list and the region captions all key off them). Everything
else -- coast, ranges, lakes, rivers -- is redrawn.

Vertical unit is "blend z": Katahdin's horn is 1022, the sea is 0, and
mainegen scales that to y 597 over a -22.5 sea, as before.

Set-pieces (see SETPIECES at the bottom for the whole list):
  * Katahdin       a horn over a flat Tableland, a cirque with a tarn on its
                   east face, the Knife Edge running out to Pamola
  * the Wall       the Longfellows as one continuous ridge along the west,
                   the Boundary wall running up the Quebec edge to the tip
  * the Shelf      Aroostook as a golden plateau standing 200 m over the
                   lowlands behind one escarpment you can see from Bangor
  * the Rift       the Allagash cut into the Shelf as a canyon of pools
  * the Tablelands mesas between Patten and Houlton
  * Moosehead      a lake the size of a county, Kineo a flat-topped stack
                   standing sheer out of it
  * the Steps      the Rangeley lakes as terraces stepping down west
  * the Crater     Grand Lake as a caldera, one gap in the rim to the east
  * Downeast       sea cliffs from Machias to Cutler with stacks off them,
                   Acadia's granite domes, the Camden cliff over the bay
  * Casco Bay      an archipelago, sand from Kittery to Portland
"""

import json, os, sys, math
import numpy as np
from scipy import ndimage
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import maine_map as M

MACRO = M.MACRO
NX, NY = M.MACRO_NX, M.MACRO_NY
STEP = M.MACRO_STEP
XS = M.X_MIN + np.arange(NX) * STEP
YS = M.Y_MIN + np.arange(NY) * STEP            # row 0 = south
GX, GY = np.meshgrid(XS, YS)
RNG = np.random.default_rng(20260902)
DRY = -200.0
KATAHDIN_Z = 1022.22

LL = M.lonlat_to_map


# ------------------------------------------------------------------ helpers ---
def cell(x, y):
    """map metres -> (col, row) float indices."""
    return (x - M.X_MIN) / STEP, (y - M.Y_MIN) / STEP


def poly_mask(pts):
    """Filled polygon (map metres) -> bool grid."""
    im = Image.new("L", (NX, NY), 0)
    ImageDraw.Draw(im).polygon([cell(x, y) for x, y in pts], fill=1)
    return np.asarray(im, dtype=bool)


def blob(cx, cy, rx, ry, rot=0.0, lobes=0.0, seed=0):
    """A lobed ellipse mask -- lakes and islands. lobes 0 = a clean ellipse."""
    ang = np.linspace(0, 2 * math.pi, 48, endpoint=False)
    r = np.random.default_rng(seed)
    k = 1.0 + lobes * (0.5 * np.sin(ang * 3 + r.random() * 6) + 0.35 * np.sin(ang * 5 + r.random() * 6))
    px = np.cos(ang) * rx * k
    py = np.sin(ang) * ry * k
    c, s = math.cos(rot), math.sin(rot)
    pts = [(cx + c * a - s * b, cy + s * a + c * b) for a, b in zip(px, py)]
    return poly_mask(pts)


def dist_to(mask):
    """Metres from every cell to the nearest True cell."""
    if not mask.any():
        return np.full((NY, NX), 1e9, np.float32)
    return (ndimage.distance_transform_edt(~mask) * STEP).astype(np.float32)


def seg_dist(pts):
    """Metres to a polyline (and the parameter 0..1 along it, by arc length)."""
    pts = np.asarray(pts, np.float32)
    L = np.r_[0.0, np.cumsum(np.hypot(*np.diff(pts, axis=0).T))]
    best = np.full((NY, NX), 1e9, np.float32)
    bt = np.zeros((NY, NX), np.float32)
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        ab = b - a
        n2 = max(float(ab @ ab), 1e-6)
        t = np.clip(((GX - a[0]) * ab[0] + (GY - a[1]) * ab[1]) / n2, 0.0, 1.0)
        d = np.hypot(GX - (a[0] + t * ab[0]), GY - (a[1] + t * ab[1]))
        m = d < best
        best[m] = d[m]
        bt[m] = ((L[i] + t * (L[i + 1] - L[i])) / max(L[-1], 1e-6))[m]
    return best, bt


def smooth(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def noise(cells, seed):
    g = np.random.default_rng(seed).random((int(NY / cells) + 3, int(NX / cells) + 3)).astype(np.float32)
    z = ndimage.zoom(g, (NY / g.shape[0] * 1.02, NX / g.shape[1] * 1.02), order=3)
    return z[:NY, :NX] - 0.5


def horn(cx, cy, h, sigma, along=1.0, across=1.0, rot=0.0, sharp=1.2):
    """A peak: a pointed cone, ellipse footprint, zero at 1.0*sigma."""
    c, s = math.cos(rot), math.sin(rot)
    dx, dy = GX - cx, GY - cy
    a = (dx * c + dy * s) / along
    b = (-dx * s + dy * c) / across
    d = np.hypot(a, b) / sigma
    return h * np.clip(1.0 - d, 0.0, 1.0) ** sharp


def plateau(mask, level, edge=60.0):
    """A flat top at `level` with a cliff `edge` metres wide."""
    d = dist_to(mask)
    return level * (1.0 - smooth(d / edge))


def ridge(pts, h, width, crest=0.0, seed=0, sharp=1.3):
    """A ridge along a polyline: height h, half-width `width` metres."""
    d, t = seg_dist(pts)
    prof = np.clip(1.0 - d / width, 0.0, 1.0) ** sharp
    if crest:
        prof *= 1.0 + crest * np.sin(t * 40.0 + seed) * 0.5 + crest * np.sin(t * 17.0 + seed * 2) * 0.5
    return h * prof


# ---------------------------------------------------------------- geography ---
def coast_polygon():
    """The Gulf of Maine, as a polygon in map metres. Bold, few points."""
    pts = [
        (-70.75, 42.95), (-70.70, 43.08), (-70.60, 43.24), (-70.44, 43.44), (-70.33, 43.55),
        (-70.20, 43.63), (-70.07, 43.70), (-69.99, 43.80), (-69.96, 43.90),   # Casco Bay
        (-69.84, 43.86), (-69.78, 43.94), (-69.66, 43.85), (-69.54, 43.96), (-69.40, 43.92),
        (-69.22, 44.02), (-69.10, 44.12), (-69.02, 44.24), (-68.98, 44.44), (-68.84, 44.58),  # Penobscot Bay
        (-68.74, 44.50), (-68.66, 44.36), (-68.56, 44.30), (-68.48, 44.45), (-68.42, 44.56),  # Blue Hill
        (-68.30, 44.52), (-68.18, 44.42), (-68.05, 44.48), (-67.92, 44.42), (-67.74, 44.56),
        (-67.60, 44.55), (-67.47, 44.66), (-67.35, 44.64), (-67.20, 44.76), (-67.05, 44.82),
        (-66.98, 44.90), (-67.06, 45.05), (-67.18, 45.13), (-67.27, 45.18),                  # Eastport, Calais
        (-66.85, 45.22), (-66.85, 42.95),
    ]
    return [LL(*p) for p in pts]


ISLANDS = [   # (lon, lat, rx, ry, rot, lobes, top z, cliff)  -- z 0 = a low island
    (-68.32, 44.34, 300, 210, 0.3, 0.30, 55, 40),      # Mount Desert
    (-68.68, 44.22, 130, 90, 0.4, 0.4, 30, 25),        # Deer Isle
    (-68.83, 44.05, 120, 90, 0.0, 0.5, 40, 30),        # Vinalhaven
    (-68.90, 44.30, 40, 130, 0.1, 0.2, 25, 20),        # Islesboro
    (-69.32, 43.76, 40, 30, 0.0, 0.0, 130, 25),        # Monhegan -- a pillar
    (-68.88, 43.87, 45, 35, 0.0, 0.2, 90, 25),         # Matinicus
    (-70.18, 43.66, 45, 25, 0.5, 0.3, 20, 15),         # Peaks Island
    (-70.14, 43.70, 30, 20, 0.6, 0.3, 18, 15),
    (-70.10, 43.73, 60, 25, 0.7, 0.3, 24, 15),         # Chebeague
    (-70.05, 43.76, 25, 20, 0.2, 0.3, 16, 15),
    (-70.00, 43.74, 40, 18, 0.9, 0.3, 20, 15),
    (-69.95, 43.79, 22, 16, 0.4, 0.3, 14, 15),
    (-70.22, 43.60, 22, 14, 0.3, 0.2, 16, 15),
    (-70.12, 43.64, 18, 18, 0.0, 0.3, 14, 15),
    (-68.20, 44.29, 50, 30, 0.2, 0.3, 30, 25),         # Cranberry
    (-67.32, 44.60, 30, 22, 0.3, 0.2, 60, 30),         # Cross Island -- a stack
    (-67.20, 44.66, 18, 14, 0.0, 0.0, 70, 30),
    (-67.52, 44.58, 16, 12, 0.0, 0.0, 75, 30),
    (-67.62, 44.50, 22, 14, 0.5, 0.0, 65, 30),
]

# Katahdin and the Baxter peaks; the Wall; the coast hills. (lon, lat, z, sigma, along, across, rot)
PEAKS = {
    "Katahdin":            (-68.9214, 45.9044, KATAHDIN_Z, 900, 1.0, 1.0, 0.0),
    "Hamlin Peak":         (-68.9161, 45.9250, 880, 300, 1.0, 0.8, 1.4),
    "North Brother":       (-69.0011, 45.9628, 760, 330, 1.3, 0.8, 0.9),
    "Doubletop Mountain":  (-69.0575, 45.8747, 640, 260, 1.0, 0.7, 1.2),
    "Traveler Mountain":   (-68.8869, 46.0206, 700, 320, 1.0, 1.0, 0.0),
    "White Cap Mountain":  (-69.2586, 45.5647, 700, 360, 1.6, 0.8, 0.5),
    "Elephant Mountain":   (-69.5722, 45.5028, 620, 300, 1.4, 0.8, 0.3),
    "Big Moose Mountain":  (-69.7167, 45.5236, 660, 300, 1.2, 0.9, 0.9),
    "Old Speck":           (-70.9469, 44.5647, 820, 330, 1.2, 0.8, 0.8),
    "Baldpate Mountain":   (-70.8817, 44.5931, 740, 280, 1.2, 0.8, 0.8),
    "Saddleback":          (-70.5147, 44.9450, 800, 320, 1.4, 0.8, 0.6),
    "Mount Abraham":       (-70.3350, 44.9008, 780, 300, 1.3, 0.8, 0.6),
    "Spaulding Mountain":  (-70.3608, 44.9436, 760, 260, 1.2, 0.8, 0.6),
    "Sugarloaf":           (-70.3131, 45.0353, 830, 330, 1.2, 0.9, 0.7),
    "Crocker Mountain":    (-70.3806, 45.0272, 800, 300, 1.3, 0.8, 0.7),
    "Mount Redington":     (-70.4064, 44.9686, 750, 260, 1.2, 0.8, 0.7),
    "Bigelow — West Peak": (-70.3053, 45.1483, 800, 340, 1.8, 0.7, 0.15),
    "Bigelow — Avery":     (-70.2872, 45.1461, 790, 300, 1.8, 0.7, 0.15),
    "Snow Mountain":       (-70.7383, 45.2483, 740, 320, 1.3, 0.8, 0.9),
    "Boundary Bald":       (-70.1919, 45.6142, 700, 330, 1.4, 0.8, 1.0),
    "Coburn Mountain":     (-70.1256, 45.4694, 720, 320, 1.3, 0.8, 1.0),
    "Mount Blue":          (-70.3286, 44.7286, 620, 280, 1.0, 1.0, 0.0),
    "Tumbledown Mountain": (-70.5433, 44.7275, 600, 300, 1.5, 0.7, 0.2),
    "Mount Kineo":         (-69.7333, 45.6800, 330, 0, 0, 0, 0),      # built as a stack, below
    "Mount Battie":        (-69.0603, 44.2247, 300, 190, 1.0, 1.0, 0.0),
    "Cadillac Mountain":   (-68.2247, 44.3528, 430, 220, 1.0, 1.0, 0.0),
}

RIDGES = [   # polylines in lon/lat: (points, z, half-width, crest)
    # the Wall -- the Longfellows as one curtain
    ([(-71.00, 44.45), (-70.95, 44.56), (-70.88, 44.59), (-70.70, 44.75), (-70.51, 44.95),
      (-70.40, 44.97), (-70.34, 44.90), (-70.31, 45.04), (-70.38, 45.03), (-70.30, 45.15),
      (-70.20, 45.16)], 610, 380, 0.3),
    # the Boundary wall -- the world's north-west edge, up to the tip
    ([(-71.08, 45.30), (-70.74, 45.25), (-70.45, 45.45), (-70.19, 45.61), (-70.13, 45.47),
      (-70.05, 45.80), (-69.95, 46.10), (-69.75, 46.45), (-69.50, 46.80), (-69.30, 47.15),
      (-69.20, 47.45)], 500, 400, 0.4),
    # the NH edge, south of Old Speck: a lower curb so Fryeburg still has a horizon
    ([(-71.08, 45.30), (-71.05, 44.60), (-71.00, 44.10), (-70.98, 43.70), (-70.90, 43.30)], 260, 300, 0.3),
    # the Hundred-Mile -- Moosehead to Katahdin
    ([(-69.50, 45.50), (-69.40, 45.55), (-69.26, 45.56), (-69.10, 45.70),
      (-69.00, 45.82)], 420, 330, 0.4),
    # Knife Edge -- Katahdin summit out to Pamola, south-east
    ([(-68.9214, 45.9044), (-68.905, 45.898), (-68.890, 45.892)], 840, 110, 0.0),
    # the Camden line over Penobscot Bay
    ([(-69.10, 44.19), (-69.06, 44.22), (-69.03, 44.27)], 240, 260, 0.2),
]

# Lakes: name -> (cx, cy, rx, ry, rot, lobes, surface z or None = fit to ground)
# Positions are the recovered markers (map metres), shapes are new.
LAKES = {
    "Moosehead Lake":       None,       # drawn from a real-ish outline below
    "Sebago Lake":          (-2674, -3336, 300, 340, 0.3, 0.25, None),
    "Flagstaff Lake":       (-2143, -96, 420, 95, 0.05, 0.3, 300),
    "Rangeley Lake":        (-2920, -600, 200, 110, 0.1, 0.25, 470),
    "Rangeley — Kennebago": (-2880, -360, 240, 90, 0.5, 0.3, 560),
    "Mooselookmeguntic":    (-3086, -840, 300, 170, -0.5, 0.3, 400),
    "Richardson Lakes":     (-3257, -1080, 120, 280, 0.2, 0.3, 330),
    "Aziscohos Lake":       (-3429, -552, 70, 300, 0.1, 0.3, 480),
    "Umbagog Lake":         (-3514, -1248, 150, 200, 0.0, 0.35, 250),
    "Webb Lake":            (-2486, -1368, 130, 170, 0.2, 0.25, None),
    "Kezar Lake":           (-3223, -2520, 80, 220, 0.15, 0.3, None),
    "Thompson Lake":        (-2400, -2880, 70, 240, 0.1, 0.3, None),
    "Cobbossee Lake":       (-1543, -2400, 90, 260, 0.15, 0.3, None),
    "China Lake":           (-943, -1992, 90, 170, 0.3, 0.3, None),
    "Great Pond":           (-1457, -1680, 200, 170, 0.0, 0.35, None),
    "Sebec Lake":           (-377, 120, 260, 70, 0.05, 0.25, None),
    "Schoodic Lake":        (86, 120, 110, 190, 0.0, 0.3, None),
    "Jo-Mary Lakes":        (-86, 552, 220, 120, 0.3, 0.45, None),
    "Pemadumcook Lake":     (34, 888, 300, 150, -0.2, 0.45, None),
    "Millinocket Lake":     (343, 1080, 190, 130, 0.4, 0.3, None),
    "Chesuncook Lake":      (-514, 1848, 110, 380, 0.25, 0.25, None),
    "Chamberlain Lake":     (-429, 2400, 100, 360, 0.3, 0.25, None),
    "Eagle Lake":           (-600, 2712, 80, 250, 0.25, 0.3, None),
    "Munsungan Lake":       (171, 2568, 220, 90, 0.2, 0.3, None),
    "Seboomook Lake":       (-1457, 1440, 330, 80, 0.0, 0.3, None),
    "Baskahegan Lake":      (1800, 480, 190, 130, 0.5, 0.35, None),
    "East Grand Lake":      (2023, 960, 90, 330, 0.05, 0.3, None),
    "Grand Lake":           (1971, -120, 300, 300, 0.0, 0.0, None),   # the Crater
    "Square Lake":          (943, 4440, 200, 150, 0.2, 0.35, None),
    "Long Lake":            (1200, 4608, 90, 210, 0.4, 0.3, None),
}

MOOSEHEAD = [(-69.76, 45.33), (-69.66, 45.36), (-69.58, 45.44), (-69.54, 45.55), (-69.58, 45.68),
             (-69.64, 45.78), (-69.78, 45.86), (-69.86, 45.80), (-69.83, 45.70), (-69.74, 45.62),
             (-69.68, 45.52), (-69.70, 45.44), (-69.76, 45.36)]

# Rivers: polylines in map metres, downstream order. (points, valley half-width, pool width)
RIVERS = [   # (points, valley half-width, pool width, valley depth)
    # Kennebec: Moosehead's outlet to the sea at Bath
    ([(-1290, 330), (-1400, -100), (-1470, -420), (-1290, -900), (-1180, -1110), (-1120, -1420),
      (-1060, -1640), (-1200, -1980), (-1280, -2300), (-1300, -2500), (-1330, -2900), (-1350, -3250),
      (-1300, -3520)], 400, 40, 55),
    # Penobscot: Millinocket to the bay
    ([(400, 1010), (600, 700), (820, 320), (700, -150), (560, -700), (450, -1040), (390, -1250),
      (330, -1620), (340, -1900)], 380, 40, 55),
    # Androscoggin: Umbagog round the Wall to Brunswick
    ([(-3480, -1350), (-3590, -1500), (-3590, -1800), (-3400, -2000), (-3060, -2010), (-2800, -1780), (-2600, -1700), (-2300, -1800),
      (-2060, -1960), (-2000, -2300), (-2050, -2650), (-1950, -2950), (-1720, -3140), (-1600, -3320)], 340, 34, 50),
    # Saco: Fryeburg to Biddeford
    ([(-3400, -2900), (-3150, -3300), (-2900, -3700), (-2600, -4100), (-2450, -4300)], 260, 28, 40),
    # St John: the northern edge, west to east
    ([(-1500, 4300), (-900, 4500), (-300, 4700), (300, 4800), (700, 4900), (1200, 4780),
      (1800, 4660), (2400, 4900), (3000, 5150), (3600, 5300)], 380, 60, 110),
    # the Rift -- Allagash canyon, Chamberlain north to the St John
    ([(-420, 2780), (-560, 3050), (-520, 3400), (-380, 3800), (-300, 4200), (-280, 4650)], 260, 46, 150),
    # Aroostook river across the Shelf
    ([(600, 3200), (1000, 3260), (1400, 3380), (1750, 3400), (2200, 3600), (2800, 3700), (3600, 3750)], 220, 34, 70),
    # Piscataquis / Sebec outlet down to the Penobscot
    ([(-380, 190), (-100, -150), (200, -480), (520, -720)], 200, 22, 35),
    # St Croix -- the eastern border down to Calais
    ([(2060, 1300), (2300, 900), (2600, 500), (2900, 100), (3080, -200), (3300, -500)], 240, 30, 45),
]

MESAS = [   # (x, y, rx, ry, rot, top z) -- the Tablelands
    (1250, 1500, 210, 150, 0.3, 400), (1650, 1750, 160, 120, 0.9, 360), (1400, 2050, 130, 130, 0.0, 440),
    (1000, 2250, 180, 100, 0.5, 380), (1800, 2350, 120, 90, 0.2, 330), (1450, 1150, 110, 110, 0.0, 350),
    (700, 1900, 90, 140, 1.1, 410), (2050, 2000, 100, 80, 0.4, 300), (1150, 2650, 130, 100, 0.7, 340),
]

# the Shelf -- the Aroostook plateau, map metres
SHELF = [(-100, 2900), (300, 2750), (900, 2650), (1500, 2600), (2200, 2700), (2800, 2650), (3600, 2600),
         (3600, 5400), (-1600, 5400), (-1300, 4200), (-700, 3500)]
SHELF_Z = 230.0

# Downeast sea cliffs, Machias to Cutler: land within this polygon is a 90 m table
CLIFF_COAST = [LL(*p) for p in [(-67.55, 44.62), (-67.45, 44.66), (-67.20, 44.78), (-67.02, 44.86),
                                  (-67.00, 44.75), (-67.35, 44.50), (-67.60, 44.50)]]
CLIFF_Z = 90.0

SAND_COAST = [LL(*p) for p in [(-70.80, 42.95), (-70.72, 43.08), (-70.60, 43.24), (-70.44, 43.44),
                                 (-70.30, 43.56), (-70.28, 43.50), (-70.55, 43.15), (-70.70, 42.95)]]

REGIONS_KEEP = True


# ------------------------------------------------------------------ the build ---
def build():
    print("myrkgen: the stylized Maine")
    ocean = poly_mask(coast_polygon())
    land = ~ocean
    # islands
    for lon, lat, rx, ry, rot, lobes, _, _ in ISLANDS:
        cx, cy = LL(lon, lat)
        land |= blob(cx, cy, rx, ry, rot, lobes, seed=int(abs(lon * 100)))
    ocean = ~land
    dsea = dist_to(ocean)           # distance from land cells to the sea
    dland = dist_to(land)

    # --- base: a coastal plain rising inland, one soft regional swell ---------
    shore = smooth(dsea / 420.0)                 # everything fades to the waterline
    H = 1.2 + 80.0 * smooth(dsea / 2600.0)
    H += (45.0 * noise(70, 1) + 18.0 * noise(28, 2)) * shore
    # rolling hills, the BOTW lowland: round, separate, walkable
    hills = np.maximum(noise(11, 21), 0.0) * 2.0
    H += (75.0 * hills ** 1.4 + 22.0 * noise(19, 22)) * shore
    H = np.maximum(H, 1.0)

    for lon, lat, rx, ry, rot, lobes, z, cl in ISLANDS:
        cx, cy = LL(lon, lat)
        m = blob(cx, cy, rx, ry, rot, lobes, seed=int(abs(lon * 100)))
        H = np.maximum(H, plateau(m, z, edge=cl))

    # --- the Shelf: Aroostook as a plateau with one escarpment ----------------
    shelf = poly_mask(SHELF) & land
    H = np.maximum(H, plateau(shelf, SHELF_Z, edge=140.0) + 6.0 * noise(20, 3) * smooth(dist_to(~shelf) / 200.0))
    # the top of the Shelf rolls, gently, and drops toward its north edge (the St John)

    # --- the Steps: Rangeley terraces ------------------------------------------
    steps = [((-2860, -520), 780, 300, 560), ((-3080, -830), 560, 270, 400),
             ((-3250, -1080), 520, 240, 330), ((-3510, -1260), 470, 260, 250)]
    for (x, y), rx, ry, z in steps:
        t = blob(x, y, rx, ry, 0.3, 0.2, seed=int(-x))
        H = np.where(t, np.maximum(np.minimum(H, z + 40.0), z), H)
        H = np.maximum(H, plateau(t, z, edge=90.0))

    # --- ridges and peaks, combined by max so nothing stacks ------------------
    R = np.zeros((NY, NX), np.float32)
    for pts, z, w, crest in RIDGES:
        R = np.maximum(R, ridge([LL(*p) for p in pts], z, w, crest, seed=len(pts)))
    for name, (lon, lat, z, sig, al, ac, rot) in PEAKS.items():
        if sig == 0:
            continue
        cx, cy = LL(lon, lat)
        R = np.maximum(R, horn(cx, cy, z, sig * 1.3, al, ac, rot, sharp=1.7 if name == "Katahdin" else 1.2))
    # teeth along the Boundary wall -- a skyline, not a dyke
    wall = [LL(*p) for p in RIDGES[1][0]]
    wl = np.r_[0.0, np.cumsum([math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(wall, wall[1:])])]
    for i, sdist in enumerate(np.arange(250.0, wl[-1], 520.0)):
        j = int(np.searchsorted(wl, sdist)) - 1
        f = (sdist - wl[j]) / max(wl[j + 1] - wl[j], 1e-6)
        px = wall[j][0] + f * (wall[j + 1][0] - wall[j][0])
        py = wall[j][1] + f * (wall[j + 1][1] - wall[j][1])
        rot = math.atan2(wall[j + 1][1] - wall[j][1], wall[j + 1][0] - wall[j][0])
        R = np.maximum(R, horn(px, py, 600.0 + 90.0 * math.sin(i * 1.7), 230.0, 1.5, 0.8, rot))
    # the ridges sit on the plain: their zero is the local ground
    H = np.maximum(H, R + np.where(R > 0, np.minimum(H, 60.0), 0.0))

    # --- Katahdin: the Tableland, the cirque, the tarn -------------------------
    kx, ky = LL(-68.9214, 45.9044)
    table = blob(kx - 420, ky + 60, 420, 300, 0.2, 0.15, seed=7)
    H = np.maximum(H, plateau(table, 690.0, edge=90.0))
    cirque = blob(kx + 300, ky + 90, 190, 150, 0.4, 0.1, seed=8)
    dc = dist_to(cirque)
    bowl = 260.0 * (1.0 - smooth(dc / 120.0))
    H = np.where(dc < 400, H - bowl * (H > 500), H)
    # cut a plateau under the tarn so it has a shore
    H = np.where(cirque, np.minimum(H, 560.0), H)

    # --- the Tablelands: mesas ------------------------------------------------
    for x, y, rx, ry, rot, z in MESAS:
        H = np.maximum(H, plateau(blob(x, y, rx, ry, rot, 0.2, seed=int(x)), z * 0.8, edge=95.0))

    # --- Downeast cliffs and the Crater rim -------------------------------------
    cliff = poly_mask(CLIFF_COAST) & land
    H = np.where(cliff, np.maximum(H, CLIFF_Z + 12.0 * noise(10, 4)), H)
    # the land behind the cliff table rolls up into the barrens
    cx, cy = 1971, -120
    dr = np.hypot(GX - cx, GY - cy)
    rim = 270.0 * np.clip(1.0 - np.abs(dr - 430.0) / 190.0, 0.0, 1.0) ** 1.2
    gap = smooth((np.arctan2(GY - cy, GX - cx) - 0.0) / 0.35) * (1.0 - smooth((np.arctan2(GY - cy, GX - cx) - 0.35) / 0.35))
    rim *= 1.0 - 0.85 * gap * (GX > cx)        # one breach on the east side
    H = np.maximum(H, rim + 70.0)
    H = np.where(dr < 300, np.minimum(H, 150.0), H)

    # --- coast: beaches low, cliffs sheer, the sea floor ---------------------------
    sandy = poly_mask(SAND_COAST) & land
    H = np.where(sandy, np.minimum(H, 6.0 + 20.0 * smooth(dsea / 500.0)), H)
    # sea floor: shelf then a drop
    H = np.where(ocean, -1.5 - 7.5 * smooth(dland / 400.0) - 14.0 * smooth((dland - 600) / 1200.0), H)

    # --- water --------------------------------------------------------------------
    W = np.full((NY, NX), DRY, np.float32)
    W[ocean] = 0.0

    # rivers: carve a valley, then pools stepping down the floor
    river_cells = np.zeros((NY, NX), bool)
    for pts, vw, pw, vdepth in RIVERS:
        d, t = seg_dist(pts)
        near = d < vw
        # a floor profile that only descends: sample the current ground along the line
        n = 48
        floor = np.zeros(n, np.float32)
        for i in range(n):
            sel = near & (np.abs(t - i / (n - 1)) < 0.6 / n)
            floor[i] = np.percentile(H[sel], 25) if sel.any() else (floor[i - 1] if i else 40.0)
        for i in range(1, n):
            floor[i] = min(floor[i], floor[i - 1] - 0.5)
        floor = np.maximum(floor, 2.0)
        F = np.interp(t, np.linspace(0, 1, n), floor)
        vall = F + (np.clip(d / vw, 0, 1) ** 1.4) * vdepth
        # a valley through the plain; a range keeps its shape and the river cuts a gorge
        H = np.where(near & land & (H > 0), np.minimum(H, np.maximum(vall, R * 0.92)), H)
        # pools: 14-cell chunks along the line, one dry lip between (a falls)
        pool = (d < pw) & land
        pool = ndimage.binary_dilation(pool, iterations=1)
        L = np.cumsum([0] + [math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(pts, pts[1:])])
        seg_len = 300.0
        k = np.floor(t * L[-1] / seg_len)
        lip = (t * L[-1] / seg_len - k) < (STEP * 1.2 / seg_len)
        pool &= ~lip
        lab, nb = ndimage.label(pool)
        for b in range(1, nb + 1):
            m = lab == b
            rim_ = ndimage.binary_dilation(m, iterations=1) & ~m
            s = float(np.min(H[rim_])) - 0.8 if rim_.any() else float(H[m].min())
            W[m] = s
            H[m] = np.minimum(H[m], s - 3.5)
        river_cells |= pool

    # lakes
    lake_out = {}
    for name, spec in LAKES.items():
        if name == "Moosehead Lake":
            m = poly_mask([LL(*p) for p in MOOSEHEAD])
            surf = None
            cx, cy = -1114, 720
        else:
            cx, cy, rx, ry, rot, lobes, surf = spec
            m = blob(cx, cy, rx, ry, rot, lobes, seed=abs(hash(name)) % 1000)
        m &= land
        if name == "Grand Lake":
            m = np.hypot(GX - 1971, GY + 120) < 290
        if surf is None:
            rim_ = ndimage.binary_dilation(m, iterations=2) & ~m
            surf = float(np.percentile(H[rim_], 8)) - 1.0
        surf = max(surf, 3.0)
        # ground around a designed-level lake is lifted to its shore
        shore = ndimage.binary_dilation(m, iterations=3)
        H = np.where(shore & ~m, np.maximum(H, surf + 1.5), H)
        # ...and eased: a lake you can walk down to, not a moat under a cliff
        # (the Crater keeps its rim -- that one is the point)
        if name != "Grand Lake":
            dsh = dist_to(m)
            ease = surf + 1.5 + np.clip(dsh / 140.0, 0.0, 1.0) ** 1.6 * 34.0
            H = np.where((dsh < 140.0) & ~m, np.minimum(H, ease), H)
        H = np.where(m, np.minimum(H, surf - 4.0 - 6.0 * smooth(dist_to(~m) / 120.0)), H)
        W[m] = surf
        lake_out[name] = (cx, cy, surf, m)

    # Kineo: a flat-topped stack standing out of Moosehead
    kx, ky = LL(-69.7333, 45.6800)
    kin = blob(kx, ky, 95, 70, 0.4, 0.15, seed=11)
    H = np.where(kin, 330.0 + 8.0 * noise(8, 5), H)
    W[kin] = DRY
    kin_e = ndimage.binary_dilation(kin, iterations=1) & ~kin
    H = np.where(kin_e, np.maximum(H, 200.0), H)   # a cliff foot, not a slope

    # the tarn in Katahdin's cirque
    kx, ky = LL(-68.9214, 45.9044)
    tarn = blob(kx + 300, ky + 90, 110, 80, 0.4, 0.1, seed=9)
    tarn &= H < 600
    if tarn.any():
        s = float(np.min(H[ndimage.binary_dilation(tarn, iterations=1) & ~tarn])) - 0.5
        W[tarn] = s
        H[tarn] = np.minimum(H[tarn], s - 4.0)

    # --- cities always stand on dry ground -------------------------------------
    for c in M.places()["cities"]:
        d = np.hypot(GX - c["x"], GY - c["y"])
        m = d < 110.0
        wet = m & (W > DRY + 1)
        if wet.any():
            lvl = float(np.max(W[wet])) + 2.0
            H = np.where(m, np.maximum(H, lvl), H)
            W = np.where(m, DRY, W)

    # --- a last touch of shape, then tidy ---------------------------------------
    dry = W <= DRY + 1
    H = ndimage.gaussian_filter(H, 0.7)
    # keep water beds under their surfaces after the blur
    wet = ~dry
    H = np.where(wet, np.minimum(H, W - 2.5), H)
    H = np.where(ocean, np.minimum(H, -1.2), H)
    # the spawn valley: leave it to mainegen (it flattens a disc at ORIGIN) but make
    # sure it is land and low
    d0 = np.hypot(GX - M.ORIGIN[0], GY - M.ORIGIN[1])
    H = np.where(d0 < 420, np.minimum(H, 60.0), H)
    W = np.where(d0 < 420, DRY, W)
    H = np.where(d0 < 420, np.maximum(H, 8.0), H)

    # scale so Katahdin's horn is exactly KATAHDIN_Z
    top = float(H.max())
    if top != KATAHDIN_Z:
        vs = KATAHDIN_Z / top
        H = np.where(H > 0, H * vs, H)
        W = np.where(W > 0, W * vs, W)
    H = H.astype(np.float32)
    W = W.astype(np.float32)

    # --- colour ---------------------------------------------------------------------
    C = colour(H, W, ocean, sandy, shelf, cliff, river_cells, M.places()["cities"])

    # --- places -------------------------------------------------------------------------
    pl = M.places()
    def h_at(x, y):
        cx_, cy_ = cell(x, y)
        return float(H[int(np.clip(round(cy_), 0, NY - 1)), int(np.clip(round(cx_), 0, NX - 1))])
    for c in pl["cities"]:
        c["z"] = round(h_at(c["x"], c["y"]), 2)
    lakes = []
    for name, (cx, cy, surf, m) in lake_out.items():
        ys_, xs_ = np.nonzero(m)
        ex = (xs_.max() - xs_.min() + 1) * STEP if len(xs_) else 100.0
        ey = (ys_.max() - ys_.min() + 1) * STEP if len(ys_) else 100.0
        lakes.append({"name": name, "x": float(cx), "y": float(cy), "z": round(float(surf), 2),
                      "dim": [round(ex, 1), round(ey, 1), 3.0]})
    pl["lakes"] = sorted(lakes, key=lambda l: l["name"])
    for r in pl["regions"]:
        r["z"] = round(h_at(r["x"], r["y"]) + 60.0, 2)

    return H, W, C, pl


def colour(H, W, ocean, sandy, shelf, cliff, river, cities):
    forest = np.array([0.16, 0.32, 0.14]); pine = np.array([0.10, 0.24, 0.14])
    meadow = np.array([0.45, 0.60, 0.25]); farm = np.array([0.70, 0.65, 0.45])
    gold = np.array([0.66, 0.58, 0.30]); sand = np.array([0.78, 0.72, 0.52])
    rock = np.array([0.34, 0.32, 0.29]); snow = np.array([0.86, 0.88, 0.92])
    seabed = np.array([0.25, 0.35, 0.40]); barrens = np.array([0.58, 0.50, 0.34])
    gy, gx = np.gradient(H, STEP)
    slope = np.hypot(gy, gx)
    C = np.broadcast_to(forest, (NY, NX, 3)).copy()
    hi = H > 380
    C[hi] = pine
    # meadows: the lowland flats, in patches
    pat = noise(30, 6) + 0.4 * noise(11, 7)
    low = (H < 140) & (slope < 0.09) & (pat > 0.22)
    C[low] = meadow
    # farmland follows the rivers and rings the towns
    dr = dist_to(river)
    near_town = np.zeros((NY, NX), bool)
    for c in cities:
        near_town |= np.hypot(GX - c["x"], GY - c["y"]) < (330.0 if c["dim"][0] >= 170 else 220.0)
    fm = (H < 160) & (slope < 0.07) & ((dr < 260) | near_town) & (pat > -0.05)
    C[fm] = farm
    C[near_town & (slope < 0.07) & (H < 160)] = np.where(pat[near_town & (slope < 0.07) & (H < 160)][:, None] > 0.1, farm, meadow)
    # the Shelf is golden grassland
    C[shelf & (H > 150) & (slope < 0.12)] = gold
    C[shelf & (H > 150) & (slope < 0.12) & (pat > 0.2)] = farm
    # the barrens behind the Downeast cliffs
    dd = np.hypot(GX - 2750, GY + 950)
    C[(dd < 330) & (slope < 0.1) & (H > 20) & (pat > 0.0)] = barrens
    C[cliff & (slope < 0.12)] = barrens
    # rock by slope and height, snow on the roof
    C[slope > 0.42] = rock
    C[(H > 560) & (slope > 0.22)] = rock
    C[H > 780] = snow
    C[(H > 700) & (slope < 0.25)] = snow
    C[sandy & (H < 12)] = sand
    coast = ndimage.binary_dilation(ocean, iterations=1) & ~ocean & (H < 8) & ~cliff
    C[coast] = sand
    C[ocean] = seabed
    lake = W > 0
    C[lake] = seabed * 0.9 + forest * 0.1
    C[river] = seabed * 0.8 + meadow * 0.2
    # a little tonal variation so flat colour does not read as vinyl
    C = C * (1.0 + 0.08 * noise(6, 8))[..., None]
    return np.clip(C, 0.0, 1.0).astype(np.float32)


def preview(H, W, C, path):
    Hn = H[::-1]; Wn = W[::-1]; Cn = C[::-1]
    gy, gx = np.gradient(ndimage.gaussian_filter(Hn, 0.6))
    shade = np.clip(0.72 + (gx * 0.8 - gy * 0.8) / 90.0, 0.35, 1.35)
    img = np.clip(Cn * shade[..., None], 0, 1)
    wet = Wn > DRY + 1
    depth = np.clip((Wn - Hn) / 30.0, 0.06, 1.0)[..., None]
    wc = np.array([0.20, 0.42, 0.55]) * (1 - depth * 0.5) + np.array([0.05, 0.12, 0.28]) * depth
    img[wet] = wc[wet]
    im = Image.fromarray((img * 255).astype(np.uint8), "RGB").resize((NX * 2, NY * 2), Image.BILINEAR)
    im.save(path)


def main():
    os.makedirs(MACRO, exist_ok=True)
    H, W, C, pl = build()
    np.savez_compressed(os.path.join(MACRO, "maine_macro.npz"), H=H, W=W, C=C,
                        xs=XS.astype(np.float32), ys=YS.astype(np.float32))
    json.dump(pl, open(os.path.join(MACRO, "places.json"), "w"), indent=1, ensure_ascii=False)
    preview(H, W, C, os.path.join(MACRO, "myrk_preview.png"))
    dry = W <= DRY + 1
    print(f"  H {H.min():.1f}..{H.max():.1f}   land {dry.mean():.1%}   ocean {(W == 0).mean():.1%}   "
          f"lakes+rivers {((W > 0)).mean():.1%}")
    for name, (lon, lat, z, *_r) in PEAKS.items():
        cx, cy = cell(*LL(lon, lat))
        print(f"    {name:22s} z {H[int(cy), int(cx)]:6.0f}")


if __name__ == "__main__":
    main()
