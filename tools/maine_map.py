"""
Myrkfell — the Maine geography.

This module is the SOURCE OF TRUTH for the world's shape. It was recovered on
2026-08-30 from myrkfell_maine.blend (the only survivor of the 2026-08-27
overworld build, whose Godot-side payload was lost with its container).

It holds:
  * the macro heightfield / water surface / ground colour at 20 m per sample,
    exactly as the Blender map was built (assets/terrain/macro/*.npz),
  * every named place — 50 cities, 30 lakes, 18 regions — at its map position,
  * the real-world <-> map-metre transform, fitted from the city placements,
  * the named summits, positioned from their true lon/lat.

tools/mainegen.py consumes this and bakes the game-resolution maps.
Nothing here imports Blender or Godot; it is plain numpy so it can be run
anywhere, and so the geography can never again live only inside a container.
"""

import json, os
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
MACRO = os.path.join(REPO, "assets", "terrain", "macro")

# ---------------------------------------------------------------- the map box
# Blender/map metres. +x east, +y north. The Godot world flips y into +z south
# and re-origins on the spawn valley (see ORIGIN below).
X_MIN, X_MAX = -3600.0, 3600.0      # 7.2 km
Y_MIN, Y_MAX = -5400.0, 5400.0      # 10.8 km
MACRO_STEP = 20.0                   # the Blender mesh's sample spacing
MACRO_NX, MACRO_NY = 361, 541

# ------------------------------------------------------------------- vertical
# The Blender map is built at its own vertical scale (z_max 1022.22 m).
# The game pins Katahdin to 600 m over a sea level of -22.5, per the scale
# locked with Lemon in the 2026-08-22 blockout.
KATAHDIN_GAME_Y = 597.0
SEA_LEVEL       = -22.5
BLEND_Z_MAX     = 1022.22
V_SCALE  = (KATAHDIN_GAME_Y - SEA_LEVEL) / BLEND_Z_MAX     # ~0.6060
V_OFFSET = SEA_LEVEL

def to_game_y(blend_z):
    """Blender map metres -> Godot world y."""
    return blend_z * V_SCALE + V_OFFSET

# --------------------------------------------------------- real world <-> map
# Fitted by least squares against all 50 city placements and their true
# coordinates: mean residual 14 m, median 11 m, max 88 m -- which is the
# placement grid's own 34.3 m snap, not transform error. The cross terms come
# out near zero (the map is an unrotated plate carree), so they are dropped.
# This lets us put real Maine coordinates -- summits, rivers, anything --
# straight onto the map.
X_PER_DEG_LON, X_LON_C = 1707.32, 117675.61
Y_PER_DEG_LAT, Y_LAT_C = 2401.36, -108627.68

def lonlat_to_map(lon, lat):
    return (X_PER_DEG_LON * lon + X_LON_C, Y_PER_DEG_LAT * lat + Y_LAT_C)

def map_to_lonlat(mx, my):
    return ((mx - X_LON_C) / X_PER_DEG_LON, (my - Y_LAT_C) / Y_PER_DEG_LAT)

# ------------------------------------------------------------- the spawn hole
# The world origin is the spawn valley, real-world (-70.33, 43.82) -- the same
# point the 2026-08-27 build used, which puts Portland ~390 m south-east and
# Katahdin ~5 km north-east. The CaveRegion's grass top is the ground here, so
# the bake flattens a disc to y = 0 and eases back to the real hills.
VALLEY_LON, VALLEY_LAT = -70.33, 43.82
ORIGIN = lonlat_to_map(VALLEY_LON, VALLEY_LAT)      # ~(-2283.3, -3429.8)
VALLEY_FLAT_R = 150.0
VALLEY_EASE_R = 340.0

def map_to_world(mx, my):
    """Map metres -> Godot world (x east, z south)."""
    return (mx - ORIGIN[0], -(my - ORIGIN[1]))

def world_to_map(wx, wz):
    return (wx + ORIGIN[0], -wz + ORIGIN[1])

# ------------------------------------------------------------- named  summits
# Real lon/lat, real summit height in metres. Placed through lonlat_to_map and
# then snapped to the local maximum of the baked heightfield, so the marker
# always sits on the actual peak the generator produced.
PEAKS = [
    ("Katahdin",            -68.9214, 45.9044, 1606),
    ("Hamlin Peak",         -68.9161, 45.9250, 1450),
    ("Sugarloaf",           -70.3131, 45.0353, 1291),
    ("Crocker Mountain",    -70.3806, 45.0272, 1268),
    ("Old Speck",           -70.9469, 44.5647, 1274),
    ("Saddleback",          -70.5147, 44.9450, 1255),
    ("Mount Abraham",       -70.3350, 44.9008, 1234),
    ("Bigelow — West Peak", -70.3053, 45.1483, 1245),
    ("Bigelow — Avery",     -70.2872, 45.1461, 1237),
    ("North Brother",       -69.0011, 45.9628, 1200),
    ("Baldpate Mountain",   -70.8817, 44.5931, 1152),
    ("White Cap Mountain",  -69.2586, 45.5647, 1109),
    ("Mount Redington",     -70.4064, 44.9686, 1200),
    ("Spaulding Mountain",  -70.3608, 44.9436, 1224),
    ("Snow Mountain",       -70.7383, 45.2483, 1177),
    ("Boundary Bald",       -70.1919, 45.6142, 1097),
    ("Coburn Mountain",     -70.1256, 45.4694, 1120),
    ("Elephant Mountain",   -69.5722, 45.5028, 1000),
    ("Big Moose Mountain",  -69.7167, 45.5236, 1029),
    ("Mount Kineo",         -69.7333, 45.6800,  520),
    ("Traveler Mountain",   -68.8869, 46.0206, 1017),
    ("Doubletop Mountain",  -69.0575, 45.8747, 976),
    ("Mount Blue",          -70.3286, 44.7286,  945),
    ("Tumbledown Mountain", -70.5433, 44.7275,  921),
    ("Mount Battie",        -69.0603, 44.2247,  240),
    ("Cadillac Mountain",   -68.2247, 44.3528,  466),
]

# ----------------------------------------------------------------- the tables
def places():
    """The named places recovered from the .blend, in map metres."""
    with open(os.path.join(MACRO, "places.json")) as f:
        return json.load(f)

def macro():
    """The 20 m macro grids: heights, water surface, ground colour.

    Returns (H, W, C, xs, ys) with row 0 = SOUTH (+y ascending), matching the
    Blender mesh. mainegen.py flips to north-first when it bakes.
    W is -200 where dry, 0.0 on the ocean, else the lake surface height.
    """
    z = np.load(os.path.join(MACRO, "maine_macro.npz"))
    return z["H"], z["W"], z["C"], z["xs"], z["ys"]

# ------------------------------------------------------------------ bake size
# Terrain3D holds the ground now, so the bake is no longer limited by what a
# GDScript streamer could mesh per frame. 4 m per sample is 1.75x the old
# 7.03 m build -- fine enough that a footpath is a footpath -- and lands the
# whole state in 6 Terrain3D regions.
BAKE_STEP = 4.0
BAKE_NX = int(round((X_MAX - X_MIN) / BAKE_STEP))    # 1800
BAKE_NY = int(round((Y_MAX - Y_MIN) / BAKE_STEP))    # 2700
