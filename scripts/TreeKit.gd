class_name TreeKit
extends RefCounted

## ===========================================================================
## THE TREE KIT — trees v4.  Hand-authored parts, assembled by natural ratios.
##
## Lemon 2026-08-30: "redo the trees so they're not procedurally generated, but
## instead have a nice detailed bark, and a large number of geometric shapes and
## positions to fit into that look natural and use natural ratios to spawn in."
##
## So there is no branch generator in here. There is a LIBRARY of authored
## shapes — every number in PARTS below was written down on purpose — and an
## assembler whose only job is to decide, by real botanical ratios, how thick
## and how long each authored shape gets to be and which socket it fits into.
##
##   PARTS   — 71 authored profile chunks: root flares, bole sections, crown
##             tops, boughs, arms, twig sprays and the damage details (burls,
##             snapped stubs, splintered tops). Each carries its own path, its
##             own radius profile, and its own named SOCKETS: the positions a
##             child shape is allowed to fit into.
##   RECIPES — 6 authored builds per species: the flare, the stack of boles,
##             the top, and the ORDER the boughs go on in. Nothing in here
##             rolls a die for a shape.
##   RATIOS  — the assembler's whole vocabulary, and all of it is measured:
##             * da Vinci / pipe model — the wood entering a fork equals the
##               wood leaving it, sum(r_child^d) = r_parent^d, with d = 2.3
##               hardwood / 2.0 conifer. This is what makes a limb the right
##               thickness for the trunk it comes off, at every order, without
##               a single hand-picked number.
##             * Golden angle 137.5077 deg between successive boughs on a
##               hardwood; Fibonacci whorls (5 pine, 8 fir) on a conifer.
##             * Internodes shorten up the stem by a constant ratio, which is
##               what a slowing leader actually does.
##             * Child length = parent x 0.618 (phi inverse) — the middle of
##               the measured 0.55-0.72 apical dominance band.
##             * Stem taper r(y) = R0 * (1 - y/H)^p, Kozak-style, p per species.
##
## BARK IS REAL GEOMETRY. Every ring vertex on a trunk is pushed in or out by a
## per-species bark field (_bark_offset), so plates and fissures BREAK THE
## SILHOUETTE instead of being a picture of bark painted on a smooth cylinder.
## The field is sampled in angular CELLS, never in arc length, so it closes
## exactly around the trunk with no seam, and its amplitude fades out on thin
## wood, because a twig does not have fissures.
##
## Everything downstream is untouched. This builds the same node structure the
## GLBs did — a `Trunk` mesh plus one `Branch_NN_rXXX` mesh per limb, surface 0
## wood / surface 1 leaf cards, bark UVs in metres — so TreeV2's notch carving,
## TreeBranch, FallenTrunk, the canopy densifier and save/load all still work.
## ===========================================================================

const GOLDEN_ANGLE := 2.3999632297286535   ## 137.50776 deg
const PHI_INV := 0.6180339887498949        ## apical dominance, mid-band

## Rings this far apart through the chop zone, so TreeV2._carve_notch has
## vertices to push. Above it the trunk goes back to cheap wide rings.
const CHOP_ZONE := 2.6
const CHOP_RING := 0.12
const WIDE_RING := 0.34
const MAX_ORDER := 3
## Wood thinner than this is a twig, and a twig is a leaf card's problem,
## not a tube's. Gating on radius is what keeps a fir out of the six figures.
const MIN_WOOD_R := 0.011


# ===========================================================================
# 1.  SPECIES — the measured numbers.  Shape is not in here; shape is in PARTS.
# ===========================================================================

const SP := {
	"maple": {
		"mode": "GOLDEN", "delta": 2.30, "taper": 0.44, "crown": 0.60,
		"heights": [1.1, 3.6, 8.2, 11.0, 8.0],
		"radii": [0.030, 0.105, 0.31, 0.47, 0.31],
		"elev": 50.0, "blen": 0.44, "n_bough": [0, 5, 12, 16, 11],
		"bark": "plate", "bark_amp": 0.052, "bark_v": 1.9,
		"leaf": "maple", "leaf_mult": 1.50, "leaf_size": [0.20, 0.29], "leaf_droop": 0.36,
		"cluster": [2, 3], "cross": false, "sides": [20, 8, 5, 3],
	},
	"birch": {
		"mode": "GOLDEN", "delta": 2.20, "taper": 0.36, "crown": 0.52,
		"heights": [1.0, 4.2, 10.0, 13.5, 9.5],
		"radii": [0.022, 0.075, 0.20, 0.29, 0.20],
		"elev": 34.0, "blen": 0.30, "n_bough": [0, 6, 14, 18, 12],
		"bark": "paper", "bark_amp": 0.020, "bark_v": 4.0,
		"leaf": "birch", "leaf_mult": 1.90, "leaf_size": [0.15, 0.22], "leaf_droop": 0.60,
		"cluster": [2, 4], "cross": false, "sides": [18, 8, 5, 3],
	},
	"oak": {
		"mode": "GOLDEN", "delta": 2.40, "taper": 0.52, "crown": 0.68,
		"heights": [1.0, 3.2, 7.6, 10.5, 7.6],
		"radii": [0.032, 0.125, 0.39, 0.58, 0.39],
		"elev": 70.0, "blen": 0.50, "n_bough": [0, 5, 11, 14, 10],
		"bark": "fissure", "bark_amp": 0.068, "bark_v": 1.5,
		"leaf": "oak", "leaf_mult": 0.85, "leaf_size": [0.21, 0.30], "leaf_droop": 0.32,
		"cluster": [2, 3], "cross": false, "sides": [18, 8, 5, 3],
	},
	"pine": {
		"mode": "WHORL", "delta": 2.00, "taper": 0.40, "crown": 0.55,
		"heights": [1.3, 5.0, 14.0, 20.0, 13.0],
		"radii": [0.022, 0.085, 0.27, 0.43, 0.27],
		"elev": 84.0, "blen": 0.30, "n_bough": [0, 10, 25, 30, 20],
		"per_whorl": 5, "whorl_gap": 0.92,
		"bark": "jigsaw", "bark_amp": 0.058, "bark_v": 1.1,
		"leaf": "pine", "leaf_mult": 2.20, "leaf_size": [0.26, 0.36], "leaf_droop": 0.08,
		"cluster": [2, 3], "cross": false, "sides": [20, 7, 4, 3],
	},
	"fir": {
		"mode": "WHORL", "delta": 2.00, "taper": 0.34, "crown": 0.92,
		"heights": [1.0, 3.8, 10.5, 15.0, 10.0],
		"radii": [0.020, 0.070, 0.21, 0.31, 0.21],
		"elev": 78.0, "blen": 0.36, "n_bough": [0, 16, 32, 40, 24],
		"per_whorl": 8, "whorl_gap": 0.94,
		"bark": "smooth", "bark_amp": 0.018, "bark_v": 2.2,
		"leaf": "fir", "leaf_mult": 2.60, "leaf_size": [0.19, 0.27], "leaf_droop": 0.24,
		"cluster": [2, 3], "cross": false, "sides": [16, 7, 4, 3],
	},
}

## Deadwood: a snag stops looking like an oak or a maple within a season, so
## every species shares one relief — silvered, split wide open, bark gone in
## patches. Same reasoning as the shared deadwood bark set in trees-v2 §24.
## CHUNKIER (Lemon 2026-09-14): relief ~1.7x deeper and plates taller
## (bark_v lower) across every species; the clamp in _tube still caps it.
const DEAD_BARK := {"bark": "split", "bark_amp": 0.075, "bark_v": 1.3}


# ===========================================================================
# 2.  PARTS — the authored library.  71 shapes.
#
#     Each chunk lives in a local frame that runs 0 -> 1 along +Y, with +Z as
#     the UP SIDE of the piece (so a positive dz rises and a negative dz
#     droops, whichever way the limb itself is pointing).
#       "len"   relative share of the run it is stacked into
#       "path"  [t, dx, dz] lateral offset as a fraction of the chunk's length
#       "rad"   [t, k] radius multiplier on top of the assembler's taper
#       "lobe"  [n, amp, fade] angular lobes: buttress swells, jigsaw ribs
#       "sock"  [t, elev_deg, az_deg, weight, kind] — the positions to fit into
#       "cards" leaf clusters carried along the outer half of the piece
#     kinds: "bough" order-1 limb, "arm" order-2, "spray" leaf twig,
#            "detail" a stub, a burl or a splinter
# ===========================================================================

const PARTS := {

# --- root flares -------------------------------------------------- 8 shapes
"FLARE_EVEN":     {"len": 0.15, "path": [], "rad": [[0.0, 1.38], [0.30, 1.14], [0.70, 1.03], [1.0, 1.0]]},
"FLARE_SWELL":    {"len": 0.18, "path": [], "rad": [[0.0, 1.62], [0.22, 1.26], [0.62, 1.06], [1.0, 1.0]]},
"FLARE_BUT3":     {"len": 0.20, "path": [], "rad": [[0.0, 1.52], [0.28, 1.20], [0.70, 1.04], [1.0, 1.0]], "lobe": [3, 0.34, 2.2]},
"FLARE_BUT5":     {"len": 0.22, "path": [], "rad": [[0.0, 1.58], [0.26, 1.22], [0.68, 1.05], [1.0, 1.0]], "lobe": [5, 0.26, 2.6]},
"FLARE_LEAN":     {"len": 0.16, "path": [[0.0, 0.05, -0.02], [1.0, 0.0, 0.0]], "rad": [[0.0, 1.44], [0.34, 1.16], [1.0, 1.0]], "lobe": [2, 0.22, 1.8]},
"FLARE_SHALLOW":  {"len": 0.10, "path": [], "rad": [[0.0, 1.18], [0.45, 1.06], [1.0, 1.0]]},
"FLARE_STONE":    {"len": 0.20, "path": [[0.0, 0.03, 0.03], [0.5, 0.01, 0.0], [1.0, 0.0, 0.0]], "rad": [[0.0, 1.66], [0.18, 1.34], [0.55, 1.08], [1.0, 1.0]], "lobe": [4, 0.38, 3.0]},
"FLARE_NONE":     {"len": 0.05, "path": [], "rad": [[0.0, 1.05], [1.0, 1.0]]},

# --- bole sections ----------------------------------------------- 14 shapes
"BOLE_STRAIGHT":  {"len": 1.00, "path": [[0.0, 0.0, 0.0], [0.5, 0.012, -0.008], [1.0, 0.0, 0.0]], "rad": []},
"BOLE_TRUE":      {"len": 1.00, "path": [], "rad": []},
"BOLE_LEAN":      {"len": 1.00, "path": [[0.0, 0.0, 0.0], [1.0, 0.10, 0.03]], "rad": []},
"BOLE_LEAN_BACK": {"len": 1.00, "path": [[0.0, 0.0, 0.0], [0.6, 0.07, 0.0], [1.0, 0.04, -0.02]], "rad": []},
"BOLE_S":         {"len": 1.00, "path": [[0.0, 0.0, 0.0], [0.33, 0.07, 0.02], [0.66, -0.04, 0.03], [1.0, 0.0, 0.0]], "rad": []},
"BOLE_SWEEP":     {"len": 1.00, "path": [[0.0, 0.0, 0.0], [0.4, 0.05, 0.0], [1.0, 0.16, 0.02]], "rad": []},
"BOLE_KINK":      {"len": 1.00, "path": [[0.0, 0.0, 0.0], [0.42, 0.02, 0.0], [0.52, 0.09, 0.01], [1.0, 0.11, 0.0]], "rad": [[0.42, 1.0], [0.50, 1.16], [0.60, 1.0]], "sock": [[0.50, 62, 0, 1.35, "bough"]]},
"BOLE_BURL":      {"len": 1.00, "path": [[0.0, 0.0, 0.0], [1.0, 0.03, 0.01]], "rad": [[0.24, 1.0], [0.34, 1.42], [0.46, 1.0]], "lobe": [3, 0.12, 1.4]},
"BOLE_TWIST":     {"len": 1.00, "path": [[0.0, 0.0, 0.0], [0.25, 0.04, 0.03], [0.5, 0.0, 0.06], [0.75, -0.04, 0.03], [1.0, 0.0, 0.0]], "rad": [], "lobe": [2, 0.10, 1.0]},
"BOLE_BUTTRESSED":{"len": 1.00, "path": [], "rad": [[0.0, 1.10], [0.35, 1.0]], "lobe": [4, 0.16, 2.4]},
"BOLE_SCARRED":   {"len": 1.00, "path": [[0.0, 0.0, 0.0], [1.0, 0.02, -0.03]], "rad": [[0.30, 1.0], [0.40, 0.90], [0.55, 0.93], [0.66, 1.0]], "sock": [[0.44, 100, 180, 0.30, "detail"]]},
"BOLE_FORKED":    {"len": 1.00, "path": [[0.0, 0.0, 0.0], [0.7, 0.02, 0.0], [1.0, 0.06, 0.0]], "rad": [[0.72, 1.0], [0.88, 1.22], [1.0, 1.0]], "sock": [[0.86, 34, 180, 1.85, "bough"]]},
"BOLE_SLENDER":   {"len": 1.00, "path": [[0.0, 0.0, 0.0], [0.5, 0.02, 0.02], [1.0, 0.01, 0.0]], "rad": [[0.0, 0.94], [1.0, 0.92]]},
"BOLE_STOUT":     {"len": 1.00, "path": [], "rad": [[0.0, 1.12], [1.0, 1.06]]},

# --- crown tops ---------------------------------------------------- 8 shapes
"TOP_LEADER":     {"len": 0.30, "path": [[0.0, 0.0, 0.0], [1.0, 0.03, 0.02]], "rad": [[0.0, 1.0], [1.0, 0.10]]},
"TOP_SPIRE":      {"len": 0.34, "path": [], "rad": [[0.0, 1.0], [0.6, 0.34], [1.0, 0.04]]},
"TOP_CANDELABRA": {"len": 0.22, "path": [[0.0, 0.0, 0.0], [1.0, -0.05, 0.03]], "rad": [[0.0, 1.0], [1.0, 0.30]], "sock": [[0.55, 26, 0, 1.10, "bough"], [0.80, 30, 144, 0.95, "bough"]]},
"TOP_BROKEN":     {"len": 0.10, "path": [], "rad": [[0.0, 1.0], [0.55, 0.86], [0.80, 0.74], [1.0, 0.70]], "sock": [[0.35, 58, 210, 0.80, "bough"]]},
"TOP_DEADSPIKE":  {"len": 0.26, "path": [[0.0, 0.0, 0.0], [1.0, 0.06, -0.03]], "rad": [[0.0, 1.0], [0.5, 0.40], [1.0, 0.02]]},
"TOP_BENT":       {"len": 0.24, "path": [[0.0, 0.0, 0.0], [0.5, 0.08, 0.0], [1.0, 0.22, 0.05]], "rad": [[0.0, 1.0], [1.0, 0.12]]},
"TOP_ROUND":      {"len": 0.18, "path": [], "rad": [[0.0, 1.0], [0.4, 0.62], [1.0, 0.22]], "sock": [[0.30, 44, 0, 1.0, "bough"], [0.62, 40, 137, 0.9, "bough"], [0.85, 36, 275, 0.8, "bough"]]},
"TOP_STAG":       {"len": 0.16, "path": [], "rad": [[0.0, 1.0], [1.0, 0.55]], "sock": [[0.4, 70, 60, 0.5, "detail"], [0.9, 78, 240, 0.45, "detail"]]},

# --- boughs (order-1 limbs) --------------------------------------- 18 shapes
"BOUGH_RISE_ARC": {"len": 1.0, "path": [[0.0, 0.0, 0.0], [0.4, 0.0, 0.10], [1.0, 0.0, 0.30]],
	"sock": [[0.34, 40, 90, 0.9, "arm"], [0.55, 36, 250, 0.8, "arm"], [0.78, 30, 30, 0.7, "arm"], [0.62, 0, 0, 0, "spray"], [0.86, 0, 0, 0, "spray"], [1.0, 0, 0, 0, "spray"]]},
"BOUGH_LEVEL":    {"len": 1.0, "path": [[0.0, 0.0, 0.0], [0.5, 0.0, 0.03], [1.0, 0.0, 0.02]],
	"sock": [[0.40, 44, 70, 0.9, "arm"], [0.66, 40, 215, 0.8, "arm"], [0.88, 34, 340, 0.6, "arm"], [0.70, 0, 0, 0, "spray"], [0.92, 0, 0, 0, "spray"], [1.0, 0, 0, 0, "spray"]]},
"BOUGH_DROOP":    {"len": 1.0, "path": [[0.0, 0.0, 0.0], [0.45, 0.0, -0.08], [1.0, 0.0, -0.26]],
	"sock": [[0.36, 38, 110, 0.85, "arm"], [0.62, 34, 260, 0.75, "arm"], [0.84, 28, 20, 0.6, "arm"], [0.58, 0, 0, 0, "spray"], [0.80, 0, 0, 0, "spray"], [1.0, 0, 0, 0, "spray"]]},
"BOUGH_DIP_RISE": {"len": 1.0, "path": [[0.0, 0.0, 0.0], [0.35, 0.0, -0.10], [0.7, 0.0, -0.06], [1.0, 0.0, 0.12]],
	"sock": [[0.42, 42, 95, 0.9, "arm"], [0.70, 36, 240, 0.8, "arm"], [0.90, 30, 15, 0.6, "arm"], [0.66, 0, 0, 0, "spray"], [0.88, 0, 0, 0, "spray"], [1.0, 0, 0, 0, "spray"]]},
"BOUGH_ELBOW":    {"len": 1.0, "path": [[0.0, 0.0, 0.0], [0.30, 0.02, 0.02], [0.42, 0.10, 0.08], [1.0, 0.26, 0.16]], "rad": [[0.36, 1.0], [0.44, 1.14], [0.54, 1.0]],
	"sock": [[0.44, 52, 180, 1.05, "arm"], [0.72, 38, 40, 0.8, "arm"], [0.94, 30, 250, 0.6, "arm"], [0.74, 0, 0, 0, "spray"], [1.0, 0, 0, 0, "spray"]]},
"BOUGH_ZIG":      {"len": 1.0, "path": [[0.0, 0.0, 0.0], [0.28, 0.06, 0.03], [0.55, -0.02, 0.08], [0.80, 0.05, 0.14], [1.0, 0.0, 0.20]],
	"sock": [[0.30, 46, 130, 0.85, "arm"], [0.58, 42, 300, 0.8, "arm"], [0.83, 34, 70, 0.65, "arm"], [0.64, 0, 0, 0, "spray"], [0.88, 0, 0, 0, "spray"], [1.0, 0, 0, 0, "spray"]]},
"BOUGH_FORKED":   {"len": 1.0, "path": [[0.0, 0.0, 0.0], [0.5, 0.0, 0.06], [1.0, -0.08, 0.16]],
	"sock": [[0.52, 40, 40, 1.30, "arm"], [0.52, 44, 220, 1.15, "arm"], [0.80, 32, 130, 0.7, "arm"], [0.78, 0, 0, 0, "spray"], [1.0, 0, 0, 0, "spray"]]},
"BOUGH_WHIP":     {"len": 1.0, "path": [[0.0, 0.0, 0.0], [0.6, 0.0, 0.02], [1.0, 0.0, -0.14]], "rad": [[0.0, 1.0], [0.55, 0.80], [1.0, 0.30]],
	"sock": [[0.50, 34, 150, 0.55, "arm"], [0.72, 0, 0, 0, "spray"], [0.88, 0, 0, 0, "spray"], [1.0, 0, 0, 0, "spray"]]},
"BOUGH_LOW_REACH":{"len": 1.0, "path": [[0.0, 0.0, 0.0], [0.35, 0.0, -0.04], [1.0, 0.0, -0.02]],
	"sock": [[0.38, 48, 80, 0.95, "arm"], [0.64, 44, 235, 0.85, "arm"], [0.86, 36, 350, 0.7, "arm"], [0.68, 0, 0, 0, "spray"], [0.90, 0, 0, 0, "spray"], [1.0, 0, 0, 0, "spray"]]},
"BOUGH_CROOK":    {"len": 1.0, "path": [[0.0, 0.0, 0.0], [0.22, 0.0, 0.10], [0.40, 0.04, 0.06], [1.0, 0.14, 0.18]],
	"sock": [[0.40, 56, 200, 1.0, "arm"], [0.68, 40, 20, 0.8, "arm"], [0.90, 32, 160, 0.6, "arm"], [0.72, 0, 0, 0, "spray"], [1.0, 0, 0, 0, "spray"]]},
"BOUGH_STUB":     {"len": 0.30, "path": [[0.0, 0.0, 0.0], [1.0, 0.0, -0.05]], "rad": [[0.0, 1.0], [0.7, 0.72], [1.0, 0.55]], "sock": []},
"BOUGH_DEAD":     {"len": 0.62, "path": [[0.0, 0.0, 0.0], [0.5, 0.02, -0.04], [1.0, 0.06, -0.16]], "rad": [[0.0, 1.0], [0.6, 0.55], [1.0, 0.16]],
	"sock": [[0.55, 40, 120, 0.4, "arm"]]},
"BOUGH_FLAT_TIER":{"len": 1.0, "path": [[0.0, 0.0, 0.0], [0.5, 0.0, -0.01], [1.0, 0.0, 0.01]],
	"sock": [[0.30, 30, 90, 0.8, "arm"], [0.50, 28, 270, 0.8, "arm"], [0.70, 26, 90, 0.7, "arm"], [0.88, 24, 270, 0.6, "arm"], [0.55, 0, 0, 0, "spray"], [0.78, 0, 0, 0, "spray"], [1.0, 0, 0, 0, "spray"]]},
"BOUGH_SWEEP_DN": {"len": 1.0, "path": [[0.0, 0.0, 0.0], [0.3, 0.0, -0.05], [0.7, 0.0, -0.17], [1.0, 0.0, -0.32]],
	"sock": [[0.34, 26, 100, 0.8, "arm"], [0.56, 24, 260, 0.75, "arm"], [0.78, 22, 40, 0.6, "arm"], [0.60, 0, 0, 0, "spray"], [0.82, 0, 0, 0, "spray"], [1.0, 0, 0, 0, "spray"]]},
"BOUGH_UPSWEPT":  {"len": 1.0, "path": [[0.0, 0.0, 0.0], [0.35, 0.0, 0.14], [1.0, 0.0, 0.42]],
	"sock": [[0.38, 34, 60, 0.85, "arm"], [0.64, 30, 230, 0.75, "arm"], [0.88, 26, 340, 0.6, "arm"], [0.66, 0, 0, 0, "spray"], [0.90, 0, 0, 0, "spray"], [1.0, 0, 0, 0, "spray"]]},
"BOUGH_GNARL":    {"len": 1.0, "path": [[0.0, 0.0, 0.0], [0.20, 0.05, 0.04], [0.38, 0.02, 0.10], [0.58, 0.09, 0.06], [0.80, 0.06, 0.14], [1.0, 0.12, 0.10]],
	"rad": [[0.30, 1.0], [0.38, 1.18], [0.48, 1.0], [0.66, 1.0], [0.74, 1.12], [0.82, 1.0]],
	"sock": [[0.38, 62, 170, 1.0, "arm"], [0.60, 52, 320, 0.85, "arm"], [0.82, 40, 100, 0.7, "arm"], [0.70, 0, 0, 0, "spray"], [0.92, 0, 0, 0, "spray"], [1.0, 0, 0, 0, "spray"]]},
"BOUGH_WEEP":     {"len": 1.0, "path": [[0.0, 0.0, 0.0], [0.25, 0.0, 0.06], [0.55, 0.0, 0.02], [1.0, 0.0, -0.34]], "rad": [[0.0, 1.0], [0.6, 0.72], [1.0, 0.22]],
	"sock": [[0.44, 30, 140, 0.6, "arm"], [0.68, 26, 300, 0.5, "arm"], [0.70, 0, 0, 0, "spray"], [0.86, 0, 0, 0, "spray"], [1.0, 0, 0, 0, "spray"]]},
"BOUGH_SHELF":    {"len": 1.0, "path": [[0.0, 0.0, 0.0], [0.18, 0.0, 0.05], [0.5, 0.0, 0.03], [1.0, 0.0, 0.0]],
	"sock": [[0.32, 36, 80, 0.9, "arm"], [0.52, 34, 250, 0.85, "arm"], [0.74, 30, 120, 0.7, "arm"], [0.92, 26, 290, 0.55, "arm"], [0.62, 0, 0, 0, "spray"], [0.84, 0, 0, 0, "spray"], [1.0, 0, 0, 0, "spray"]]},

# --- arms (order-2) ----------------------------------------------- 12 shapes
"ARM_STRAIGHT":   {"len": 1.0, "path": [[0.0, 0.0, 0.0], [1.0, 0.0, 0.04]], "sock": [[0.55, 0, 0, 0, "spray"], [0.80, 0, 0, 0, "spray"], [1.0, 0, 0, 0, "spray"]]},
"ARM_RISE":       {"len": 1.0, "path": [[0.0, 0.0, 0.0], [0.5, 0.0, 0.10], [1.0, 0.0, 0.26]], "sock": [[0.52, 0, 0, 0, "spray"], [0.78, 0, 0, 0, "spray"], [1.0, 0, 0, 0, "spray"]]},
"ARM_DROOP":      {"len": 1.0, "path": [[0.0, 0.0, 0.0], [0.5, 0.0, -0.09], [1.0, 0.0, -0.28]], "sock": [[0.50, 0, 0, 0, "spray"], [0.76, 0, 0, 0, "spray"], [1.0, 0, 0, 0, "spray"]]},
"ARM_FORK":       {"len": 1.0, "path": [[0.0, 0.0, 0.0], [0.5, 0.0, 0.05], [1.0, 0.06, 0.12]], "sock": [[0.48, 44, 200, 0.9, "arm"], [0.66, 0, 0, 0, "spray"], [0.88, 0, 0, 0, "spray"], [1.0, 0, 0, 0, "spray"]]},
"ARM_ZIG":        {"len": 1.0, "path": [[0.0, 0.0, 0.0], [0.35, 0.05, 0.03], [0.7, -0.02, 0.08], [1.0, 0.04, 0.12]], "sock": [[0.58, 0, 0, 0, "spray"], [0.82, 0, 0, 0, "spray"], [1.0, 0, 0, 0, "spray"]]},
"ARM_ELBOW":      {"len": 1.0, "path": [[0.0, 0.0, 0.0], [0.4, 0.02, 0.03], [0.5, 0.09, 0.05], [1.0, 0.22, 0.10]], "sock": [[0.62, 0, 0, 0, "spray"], [0.86, 0, 0, 0, "spray"], [1.0, 0, 0, 0, "spray"]]},
"ARM_WHIP":       {"len": 1.0, "path": [[0.0, 0.0, 0.0], [0.6, 0.0, 0.03], [1.0, 0.0, -0.16]], "rad": [[0.0, 1.0], [0.6, 0.72], [1.0, 0.22]], "sock": [[0.66, 0, 0, 0, "spray"], [0.88, 0, 0, 0, "spray"], [1.0, 0, 0, 0, "spray"]]},
"ARM_FLAT":       {"len": 1.0, "path": [[0.0, 0.0, 0.0], [0.5, 0.0, 0.0], [1.0, 0.0, -0.02]], "sock": [[0.40, 0, 0, 0, "spray"], [0.62, 0, 0, 0, "spray"], [0.84, 0, 0, 0, "spray"], [1.0, 0, 0, 0, "spray"]]},
"ARM_TWIN":       {"len": 1.0, "path": [[0.0, 0.0, 0.0], [0.4, 0.0, 0.04], [1.0, -0.05, 0.10]], "sock": [[0.40, 50, 30, 1.0, "arm"], [0.72, 0, 0, 0, "spray"], [1.0, 0, 0, 0, "spray"]]},
"ARM_CURL":       {"len": 1.0, "path": [[0.0, 0.0, 0.0], [0.3, 0.0, 0.08], [0.65, 0.05, 0.10], [1.0, 0.13, 0.04]], "sock": [[0.60, 0, 0, 0, "spray"], [0.84, 0, 0, 0, "spray"], [1.0, 0, 0, 0, "spray"]]},
"ARM_STUB":       {"len": 0.34, "path": [[0.0, 0.0, 0.0], [1.0, 0.0, -0.03]], "rad": [[0.0, 1.0], [1.0, 0.5]], "sock": []},
"ARM_SPRAY_FAN":  {"len": 0.86, "path": [[0.0, 0.0, 0.0], [1.0, 0.0, 0.02]], "sock": [[0.34, 0, 0, 0, "spray"], [0.52, 0, 0, 0, "spray"], [0.70, 0, 0, 0, "spray"], [0.86, 0, 0, 0, "spray"], [1.0, 0, 0, 0, "spray"]]},

# --- twig sprays (leaf carriers, order-3) ---------------------------- 5 shapes
"SPRAY_OUT":      {"len": 1.0, "path": [[0.0, 0.0, 0.0], [1.0, 0.0, 0.03]], "rad": [[0.0, 1.0], [1.0, 0.30]], "cards": 3},
"SPRAY_DROOP":    {"len": 1.0, "path": [[0.0, 0.0, 0.0], [0.6, 0.0, -0.06], [1.0, 0.0, -0.20]], "rad": [[0.0, 1.0], [1.0, 0.26]], "cards": 3},
"SPRAY_UP":       {"len": 1.0, "path": [[0.0, 0.0, 0.0], [1.0, 0.0, 0.16]], "rad": [[0.0, 1.0], [1.0, 0.28]], "cards": 3},
"SPRAY_FLAT":     {"len": 1.0, "path": [], "rad": [[0.0, 1.0], [1.0, 0.24]], "cards": 4},
"SPRAY_TUFT":     {"len": 0.55, "path": [], "rad": [[0.0, 1.0], [1.0, 0.34]], "cards": 3},

# --- damage details -------------------------------------------------- 6 shapes
"DET_STUB":       {"len": 0.16, "path": [], "rad": [[0.0, 1.0], [1.0, 0.55]]},
"DET_BURL":       {"len": 0.12, "path": [], "rad": [[0.0, 1.0], [0.5, 1.5], [1.0, 0.6]]},
"DET_SPROUT":     {"len": 0.55, "path": [[0.0, 0.0, 0.0], [1.0, 0.0, 0.22]], "rad": [[0.0, 1.0], [1.0, 0.22]], "cards": 2},
"DET_SNAG":       {"len": 0.26, "path": [[0.0, 0.0, 0.0], [1.0, 0.04, -0.08]], "rad": [[0.0, 1.0], [1.0, 0.18]]},
"DET_KNOT":       {"len": 0.07, "path": [], "rad": [[0.0, 1.0], [1.0, 0.8]]},
"DET_SPLINTER":   {"len": 0.34, "path": [[0.0, 0.0, 0.0], [1.0, 0.10, 0.06]], "rad": [[0.0, 1.0], [1.0, 0.10]]},
}


# ===========================================================================
# 3.  RECIPES — 6 authored builds per species.  This is where the shapes and
#     the positions are CHOSEN.  "boughs" is an ordered pool: the assembler
#     walks it in order, wrapping, and drops each shape at the next natural
#     position up the stem.
# ===========================================================================

const RECIPES := {
"maple": [
	{"flare": "FLARE_EVEN",    "bole": ["BOLE_STRAIGHT", "BOLE_S"],           "top": "TOP_ROUND",
	 "boughs": ["BOUGH_RISE_ARC", "BOUGH_LEVEL", "BOUGH_DIP_RISE", "BOUGH_ELBOW", "BOUGH_UPSWEPT", "BOUGH_FORKED"],
	 "arms": ["ARM_RISE", "ARM_STRAIGHT", "ARM_FORK", "ARM_ZIG"], "spray": "SPRAY_OUT"},
	{"flare": "FLARE_BUT3",    "bole": ["BOLE_TRUE", "BOLE_KINK"],            "top": "TOP_CANDELABRA",
	 "boughs": ["BOUGH_ELBOW", "BOUGH_CROOK", "BOUGH_RISE_ARC", "BOUGH_LEVEL", "BOUGH_ZIG", "BOUGH_DIP_RISE"],
	 "arms": ["ARM_ELBOW", "ARM_RISE", "ARM_CURL", "ARM_STRAIGHT"], "spray": "SPRAY_OUT"},
	{"flare": "FLARE_SWELL",   "bole": ["BOLE_LEAN", "BOLE_STRAIGHT"],        "top": "TOP_BENT",
	 "boughs": ["BOUGH_UPSWEPT", "BOUGH_DIP_RISE", "BOUGH_LEVEL", "BOUGH_RISE_ARC", "BOUGH_SHELF", "BOUGH_WHIP"],
	 "arms": ["ARM_RISE", "ARM_TWIN", "ARM_STRAIGHT", "ARM_FLAT"], "spray": "SPRAY_FLAT"},
	{"flare": "FLARE_LEAN",    "bole": ["BOLE_SWEEP", "BOLE_TRUE"],           "top": "TOP_LEADER",
	 "boughs": ["BOUGH_LEVEL", "BOUGH_SHELF", "BOUGH_RISE_ARC", "BOUGH_DROOP", "BOUGH_FORKED", "BOUGH_ELBOW"],
	 "arms": ["ARM_FLAT", "ARM_STRAIGHT", "ARM_DROOP", "ARM_FORK"], "spray": "SPRAY_OUT"},
	{"flare": "FLARE_BUT5",    "bole": ["BOLE_STOUT", "BOLE_BURL"],           "top": "TOP_ROUND",
	 "boughs": ["BOUGH_GNARL", "BOUGH_ELBOW", "BOUGH_LOW_REACH", "BOUGH_RISE_ARC", "BOUGH_CROOK", "BOUGH_LEVEL"],
	 "arms": ["ARM_ELBOW", "ARM_ZIG", "ARM_RISE", "ARM_FORK"], "spray": "SPRAY_OUT"},
	{"flare": "FLARE_STONE",   "bole": ["BOLE_TWIST", "BOLE_FORKED"],         "top": "TOP_CANDELABRA",
	 "boughs": ["BOUGH_ZIG", "BOUGH_RISE_ARC", "BOUGH_CROOK", "BOUGH_UPSWEPT", "BOUGH_LEVEL", "BOUGH_DIP_RISE"],
	 "arms": ["ARM_CURL", "ARM_RISE", "ARM_STRAIGHT", "ARM_TWIN"], "spray": "SPRAY_OUT"},
],
"birch": [
	{"flare": "FLARE_SHALLOW", "bole": ["BOLE_SLENDER", "BOLE_STRAIGHT"],     "top": "TOP_LEADER",
	 "boughs": ["BOUGH_WEEP", "BOUGH_WHIP", "BOUGH_UPSWEPT", "BOUGH_DROOP", "BOUGH_LEVEL", "BOUGH_RISE_ARC"],
	 "arms": ["ARM_WHIP", "ARM_DROOP", "ARM_RISE", "ARM_STRAIGHT"], "spray": "SPRAY_DROOP"},
	{"flare": "FLARE_NONE",    "bole": ["BOLE_S", "BOLE_SLENDER"],            "top": "TOP_BENT",
	 "boughs": ["BOUGH_WHIP", "BOUGH_WEEP", "BOUGH_DIP_RISE", "BOUGH_UPSWEPT", "BOUGH_DROOP", "BOUGH_LEVEL"],
	 "arms": ["ARM_WHIP", "ARM_ZIG", "ARM_DROOP", "ARM_STRAIGHT"], "spray": "SPRAY_DROOP"},
	{"flare": "FLARE_EVEN",    "bole": ["BOLE_TRUE", "BOLE_SLENDER"],         "top": "TOP_SPIRE",
	 "boughs": ["BOUGH_UPSWEPT", "BOUGH_WEEP", "BOUGH_WHIP", "BOUGH_RISE_ARC", "BOUGH_DROOP", "BOUGH_DIP_RISE"],
	 "arms": ["ARM_RISE", "ARM_WHIP", "ARM_DROOP", "ARM_FORK"], "spray": "SPRAY_DROOP"},
	{"flare": "FLARE_SHALLOW", "bole": ["BOLE_LEAN", "BOLE_LEAN_BACK"],       "top": "TOP_BENT",
	 "boughs": ["BOUGH_WEEP", "BOUGH_DROOP", "BOUGH_WHIP", "BOUGH_LEVEL", "BOUGH_UPSWEPT", "BOUGH_WHIP"],
	 "arms": ["ARM_DROOP", "ARM_WHIP", "ARM_STRAIGHT", "ARM_ZIG"], "spray": "SPRAY_DROOP"},
	{"flare": "FLARE_NONE",    "bole": ["BOLE_SLENDER", "BOLE_TWIST"],        "top": "TOP_LEADER",
	 "boughs": ["BOUGH_WHIP", "BOUGH_UPSWEPT", "BOUGH_WEEP", "BOUGH_DIP_RISE", "BOUGH_WHIP", "BOUGH_DROOP"],
	 "arms": ["ARM_WHIP", "ARM_RISE", "ARM_CURL", "ARM_DROOP"], "spray": "SPRAY_DROOP"},
	{"flare": "FLARE_EVEN",    "bole": ["BOLE_STRAIGHT", "BOLE_SCARRED"],     "top": "TOP_BROKEN",
	 "boughs": ["BOUGH_DROOP", "BOUGH_WEEP", "BOUGH_WHIP", "BOUGH_LEVEL", "BOUGH_STUB", "BOUGH_UPSWEPT"],
	 "arms": ["ARM_DROOP", "ARM_WHIP", "ARM_STUB", "ARM_STRAIGHT"], "spray": "SPRAY_DROOP"},
],
"oak": [
	{"flare": "FLARE_BUT5",    "bole": ["BOLE_STOUT", "BOLE_KINK"],           "top": "TOP_CANDELABRA",
	 "boughs": ["BOUGH_GNARL", "BOUGH_ELBOW", "BOUGH_LOW_REACH", "BOUGH_CROOK", "BOUGH_LEVEL", "BOUGH_ZIG"],
	 "arms": ["ARM_ELBOW", "ARM_ZIG", "ARM_FORK", "ARM_CURL"], "spray": "SPRAY_OUT"},
	{"flare": "FLARE_STONE",   "bole": ["BOLE_BUTTRESSED", "BOLE_FORKED"],    "top": "TOP_ROUND",
	 "boughs": ["BOUGH_ELBOW", "BOUGH_GNARL", "BOUGH_FORKED", "BOUGH_LOW_REACH", "BOUGH_CROOK", "BOUGH_LEVEL"],
	 "arms": ["ARM_ELBOW", "ARM_TWIN", "ARM_ZIG", "ARM_STRAIGHT"], "spray": "SPRAY_OUT"},
	{"flare": "FLARE_BUT3",    "bole": ["BOLE_TWIST", "BOLE_BURL"],           "top": "TOP_STAG",
	 "boughs": ["BOUGH_GNARL", "BOUGH_CROOK", "BOUGH_ELBOW", "BOUGH_DEAD", "BOUGH_LOW_REACH", "BOUGH_ZIG"],
	 "arms": ["ARM_ZIG", "ARM_ELBOW", "ARM_STUB", "ARM_CURL"], "spray": "SPRAY_OUT"},
	{"flare": "FLARE_SWELL",   "bole": ["BOLE_STRAIGHT", "BOLE_KINK"],        "top": "TOP_ROUND",
	 "boughs": ["BOUGH_LOW_REACH", "BOUGH_LEVEL", "BOUGH_ELBOW", "BOUGH_SHELF", "BOUGH_GNARL", "BOUGH_CROOK"],
	 "arms": ["ARM_FLAT", "ARM_ELBOW", "ARM_FORK", "ARM_ZIG"], "spray": "SPRAY_OUT"},
	{"flare": "FLARE_BUT5",    "bole": ["BOLE_LEAN", "BOLE_STOUT"],           "top": "TOP_BENT",
	 "boughs": ["BOUGH_CROOK", "BOUGH_GNARL", "BOUGH_LEVEL", "BOUGH_ELBOW", "BOUGH_UPSWEPT", "BOUGH_LOW_REACH"],
	 "arms": ["ARM_CURL", "ARM_ELBOW", "ARM_TWIN", "ARM_ZIG"], "spray": "SPRAY_OUT"},
	{"flare": "FLARE_STONE",   "bole": ["BOLE_SCARRED", "BOLE_BUTTRESSED"],   "top": "TOP_BROKEN",
	 "boughs": ["BOUGH_ELBOW", "BOUGH_DEAD", "BOUGH_GNARL", "BOUGH_LOW_REACH", "BOUGH_STUB", "BOUGH_CROOK"],
	 "arms": ["ARM_ELBOW", "ARM_STUB", "ARM_ZIG", "ARM_FORK"], "spray": "SPRAY_OUT"},
],
"pine": [
	{"flare": "FLARE_EVEN",    "bole": ["BOLE_TRUE", "BOLE_STRAIGHT"],        "top": "TOP_SPIRE",
	 "boughs": ["BOUGH_FLAT_TIER", "BOUGH_LEVEL", "BOUGH_SHELF", "BOUGH_UPSWEPT", "BOUGH_FLAT_TIER"],
	 "arms": ["ARM_FLAT", "ARM_SPRAY_FAN", "ARM_STRAIGHT"], "spray": "SPRAY_FLAT"},
	{"flare": "FLARE_SWELL",   "bole": ["BOLE_STRAIGHT", "BOLE_TRUE"],        "top": "TOP_LEADER",
	 "boughs": ["BOUGH_SHELF", "BOUGH_FLAT_TIER", "BOUGH_LEVEL", "BOUGH_FLAT_TIER", "BOUGH_UPSWEPT"],
	 "arms": ["ARM_SPRAY_FAN", "ARM_FLAT", "ARM_RISE"], "spray": "SPRAY_FLAT"},
	{"flare": "FLARE_BUT3",    "bole": ["BOLE_SLENDER", "BOLE_S"],            "top": "TOP_SPIRE",
	 "boughs": ["BOUGH_FLAT_TIER", "BOUGH_SWEEP_DN", "BOUGH_SHELF", "BOUGH_LEVEL", "BOUGH_FLAT_TIER"],
	 "arms": ["ARM_FLAT", "ARM_DROOP", "ARM_SPRAY_FAN"], "spray": "SPRAY_FLAT"},
	{"flare": "FLARE_EVEN",    "bole": ["BOLE_LEAN", "BOLE_TRUE"],            "top": "TOP_BENT",
	 "boughs": ["BOUGH_LEVEL", "BOUGH_FLAT_TIER", "BOUGH_UPSWEPT", "BOUGH_SHELF", "BOUGH_LEVEL"],
	 "arms": ["ARM_SPRAY_FAN", "ARM_RISE", "ARM_FLAT"], "spray": "SPRAY_UP"},
	{"flare": "FLARE_BUT5",    "bole": ["BOLE_STOUT", "BOLE_TRUE"],           "top": "TOP_SPIRE",
	 "boughs": ["BOUGH_SHELF", "BOUGH_FLAT_TIER", "BOUGH_LEVEL", "BOUGH_SWEEP_DN", "BOUGH_SHELF"],
	 "arms": ["ARM_FLAT", "ARM_SPRAY_FAN", "ARM_STRAIGHT"], "spray": "SPRAY_FLAT"},
	{"flare": "FLARE_SHALLOW", "bole": ["BOLE_SCARRED", "BOLE_STRAIGHT"],     "top": "TOP_DEADSPIKE",
	 "boughs": ["BOUGH_FLAT_TIER", "BOUGH_STUB", "BOUGH_SHELF", "BOUGH_DEAD", "BOUGH_LEVEL"],
	 "arms": ["ARM_FLAT", "ARM_STUB", "ARM_SPRAY_FAN"], "spray": "SPRAY_FLAT"},
],
"fir": [
	{"flare": "FLARE_SHALLOW", "bole": ["BOLE_TRUE", "BOLE_SLENDER"],         "top": "TOP_SPIRE",
	 "boughs": ["BOUGH_SWEEP_DN", "BOUGH_FLAT_TIER", "BOUGH_DROOP", "BOUGH_SHELF"],
	 "arms": ["ARM_FLAT", "ARM_DROOP", "ARM_SPRAY_FAN"], "spray": "SPRAY_FLAT"},
	{"flare": "FLARE_NONE",    "bole": ["BOLE_SLENDER", "BOLE_TRUE"],         "top": "TOP_SPIRE",
	 "boughs": ["BOUGH_DROOP", "BOUGH_SWEEP_DN", "BOUGH_FLAT_TIER", "BOUGH_LEVEL"],
	 "arms": ["ARM_DROOP", "ARM_FLAT", "ARM_SPRAY_FAN"], "spray": "SPRAY_DROOP"},
	{"flare": "FLARE_EVEN",    "bole": ["BOLE_STRAIGHT", "BOLE_TRUE"],        "top": "TOP_LEADER",
	 "boughs": ["BOUGH_FLAT_TIER", "BOUGH_SWEEP_DN", "BOUGH_SHELF", "BOUGH_DROOP"],
	 "arms": ["ARM_SPRAY_FAN", "ARM_FLAT", "ARM_DROOP"], "spray": "SPRAY_FLAT"},
	{"flare": "FLARE_SHALLOW", "bole": ["BOLE_S", "BOLE_SLENDER"],            "top": "TOP_SPIRE",
	 "boughs": ["BOUGH_SWEEP_DN", "BOUGH_DROOP", "BOUGH_FLAT_TIER", "BOUGH_SWEEP_DN"],
	 "arms": ["ARM_DROOP", "ARM_SPRAY_FAN", "ARM_FLAT"], "spray": "SPRAY_DROOP"},
	{"flare": "FLARE_BUT3",    "bole": ["BOLE_TRUE", "BOLE_STOUT"],           "top": "TOP_SPIRE",
	 "boughs": ["BOUGH_SHELF", "BOUGH_FLAT_TIER", "BOUGH_SWEEP_DN", "BOUGH_LEVEL"],
	 "arms": ["ARM_FLAT", "ARM_SPRAY_FAN", "ARM_RISE"], "spray": "SPRAY_FLAT"},
	{"flare": "FLARE_NONE",    "bole": ["BOLE_SCARRED", "BOLE_SLENDER"],      "top": "TOP_DEADSPIKE",
	 "boughs": ["BOUGH_DROOP", "BOUGH_STUB", "BOUGH_SWEEP_DN", "BOUGH_DEAD"],
	 "arms": ["ARM_DROOP", "ARM_STUB", "ARM_FLAT"], "spray": "SPRAY_FLAT"},
],
}


# ===========================================================================
# 4.  PUBLIC API
# ===========================================================================

static var _cache := {}         ## "species#stage#variant#dead" -> built meshes
static var build_ms := 0.0      ## cost of the last real build, for the tests


static func variants(species: String) -> int:
	return (RECIPES.get(species, RECIPES["maple"]) as Array).size()


static func height_of(species: String, stage: int) -> float:
	var s: Dictionary = SP.get(species, SP["maple"])
	return float((s["heights"] as Array)[clampi(stage, 0, 4)])


static func base_radius(species: String, stage: int) -> float:
	var s: Dictionary = SP.get(species, SP["maple"])
	return float((s["radii"] as Array)[clampi(stage, 0, 4)])


## The real radius of the wood at height y, straight off the taper curve the
## mesh was built from. TreeV2 carves its notch against THIS, not a table, so
## the wedge is always the right share of the tree actually standing there.
static func radius_at(species: String, stage: int, y: float) -> float:
	var s: Dictionary = SP.get(species, SP["maple"])
	var h := height_of(species, stage)
	var r0 := base_radius(species, stage)
	return maxf(_taper(r0, y, h, float(s["taper"])), r0 * 0.10)


## Build one tree. Returns a Node3D shaped exactly like the old GLB scene:
##   Trunk_vN            surface 0 wood, surface 1 leaf cards
##   Branch_NN_vV_rRRR   one per order-1 limb, verts about its own base
static func build(species: String, stage: int, variant: int, is_dead := false) -> Node3D:
	if not SP.has(species):
		species = "maple"
	stage = clampi(stage, 0, 4)
	variant = posmod(variant, variants(species))
	var key := "%s#%d#%d#%d" % [species, stage, variant, int(is_dead)]
	var built: Dictionary = _cache.get(key, {})
	if built.is_empty():
		var t0 := Time.get_ticks_usec()
		built = _assemble(species, stage, variant, is_dead)
		build_ms = float(Time.get_ticks_usec() - t0) / 1000.0
		_cache[key] = built

	var root := Node3D.new()
	root.name = "Tree_%s_%d_v%d" % [species, stage, variant]
	var trunk := MeshInstance3D.new()
	trunk.name = "Trunk_v%d" % variant
	trunk.mesh = built["trunk"]
	root.add_child(trunk)
	for b in (built["branches"] as Array):
		var mi := MeshInstance3D.new()
		mi.name = String(b["name"])
		mi.mesh = b["mesh"]
		mi.position = b["pos"]
		root.add_child(mi)
	return root


static func clear_cache() -> void:
	_cache.clear()


# ===========================================================================
# 5.  THE ASSEMBLER — natural ratios only.
# ===========================================================================

## Kozak-style stem taper: r(y) = R0 * (1 - y/H)^p. That is the shape a real
## bole holds — fat and slow at the butt, giving up quickly near the tip.
static func _taper(r0: float, y: float, h: float, p: float) -> float:
	var f: float = clampf(1.0 - y / maxf(h, 0.01), 0.0, 1.0)
	return r0 * pow(f, p)


## da Vinci / pipe model: the wood entering a fork equals the wood leaving it,
## sum(r_child^delta) = r_parent^delta. Give the leader its share first, then
## split what is left by the sockets' authored weights. This one function is
## why a limb is never too fat for the wood it grows out of.
static func _pipe_split(r_parent: float, delta: float, leader_share: float,
		weights: Array) -> Array:
	var budget := pow(maxf(r_parent, 0.001), delta) * (1.0 - leader_share)
	var total := 0.0
	for w in weights:
		total += maxf(float(w), 0.0)
	var out: Array = []
	for w in weights:
		var share := (maxf(float(w), 0.0) / maxf(total, 0.0001)) * budget
		out.append(pow(maxf(share, 1e-9), 1.0 / delta))
	return out


## Positions along the crown. Internodes shorten toward the top by a constant
## ratio — geometric, because that is how a leader's annual growth falls off —
## so limbs crowd near the top and stand apart down low.
static func _geom_place(i: int, n: int, ratio: float) -> float:
	if n <= 1:
		return 0.35
	var acc := 0.0
	var step := 1.0
	var at := 0.0
	for k in range(n - 1):
		if k == i:
			at = acc
		acc += step
		step *= ratio
	if i >= n - 1:
		at = acc
	elif i == 0:
		at = 0.0
	return clampf(at / maxf(acc, 0.0001), 0.0, 1.0)


## A frame whose +Y runs along `d` and whose +Z is the piece's UP SIDE. Every
## part in the library is authored against that convention, so a positive dz
## rises and a negative dz droops no matter which way the limb points.
static func _frame(d: Vector3, up_ref: Vector3) -> Basis:
	var y := d.normalized()
	var z := up_ref - y * up_ref.dot(y)
	if z.length() < 1e-5:
		z = Vector3.FORWARD - y * Vector3.FORWARD.dot(y)
	if z.length() < 1e-5:
		z = Vector3.RIGHT - y * Vector3.RIGHT.dot(y)
	z = z.normalized()
	return Basis(y.cross(z).normalized(), y, z)


static func _dir_from(elev: float, az: float) -> Vector3:
	return Vector3(sin(elev) * cos(az), cos(elev), sin(elev) * sin(az))


static func _assemble(species: String, stage: int, variant: int, is_dead: bool) -> Dictionary:
	var s: Dictionary = SP[species]
	var recs: Array = RECIPES[species]
	var rec: Dictionary = recs[posmod(variant, recs.size())]

	var h := height_of(species, stage)
	var r0 := base_radius(species, stage)
	var delta := float(s["delta"])
	var taper_p := float(s["taper"])
	var conifer: bool = String(s["mode"]) == "WHORL"
	var relief := _relief_of(species, is_dead)
	## One bark seed per authored recipe: recipe 0's oak and recipe 3's oak do
	## not share a single fissure. TreeV2 then varies the SHADING per tree on
	## top of this, which is what makes 420 trees read as 420 trees.
	relief["seed"] = posmod(hash(species + "#" + str(variant) + ("#d" if is_dead else "")), 4096)

	# ---- the trunk: flare + boles + top concatenated into ONE run -----------
	# One continuous tube, never stacked tubes. Two rings built from different
	# segment directions cannot be welded, which is the bug that opened the old
	# trunk into floating bands (trees-v2 spec §22, bug 7).
	var chunks: Array = [String(rec["flare"])]
	chunks.append_array(rec["bole"] as Array)
	chunks.append(String(rec["top"]))
	var run := _run(chunks, h, r0, h, taper_p, true)
	var spine: PackedVector3Array = run["v"]
	var radii: PackedFloat32Array = run["r"]
	var lobes: Array = run["lobe"]
	var trunk_socks: Array = run["sock"]

	# ---- the crown ----------------------------------------------------------
	var y_lo := h * (1.0 - float(s["crown"]))
	var y_hi := h * 0.955
	var n: int = int((s["n_bough"] as Array)[stage])
	var pool: Array = rec["boughs"] as Array
	var arms: Array = rec["arms"] as Array
	var spray_part := String(rec["spray"])
	var branches: Array = []
	var cards_trunk: Array = []

	var leader_share := 0.62 if conifer else 0.44
	var weights: Array = []
	for i in range(n):
		weights.append(1.0)
	var r_crown := _taper(r0, y_lo, h, taper_p)
	var shares: Array = _pipe_split(r_crown, delta, leader_share, weights)

	for i in range(n):
		var t := 0.0
		var az := 0.0
		if conifer:
			# Fibonacci whorls: rings of `per_whorl` limbs at one height, the
			# rings spaced by internodes that shorten as the leader slows.
			var per: int = int(s.get("per_whorl", 5))
			var rings: int = maxi(int(ceil(float(n) / float(per))), 1)
			t = _geom_place(i / per, rings, float(s.get("whorl_gap", 0.92)))
			az = TAU * float(i % per) / float(per) + float(i / per) * 0.62
		else:
			# Golden angle. 137.5077 deg between successive limbs is the single
			# rule that makes a stem read as grown rather than decorated.
			t = _geom_place(i, n, 0.955)
			az = GOLDEN_ANGLE * float(i)

		var y := lerpf(y_lo, y_hi, t)
		var r_here := _taper(r0, y, h, taper_p)
		var rb: float = minf(float(shares[i]) * (r_here / maxf(r_crown, 0.001)),
			r_here * 0.72)
		rb = maxf(rb, 0.006)
		var blen := h * float(s["blen"]) * lerpf(1.05, 0.42, t)
		var elev := deg_to_rad(float(s["elev"])) * lerpf(1.06, 0.74, t)
		var base := _at_height(spine, y)
		var basis := _frame(_dir_from(elev, az), Vector3.UP)

		var limb := _limb(String(pool[i % pool.size()]), blen, rb, delta, s,
			arms, spray_part, relief, 1, stage, is_dead, i * 7 + stage)
		if (limb["chains"] as Array).is_empty():
			continue
		_xform(limb, basis)
		var mesh := _mesh_of(species, limb, s, int((s["sides"] as Array)[1]), relief, false)
		if mesh == null:
			continue
		branches.append({
			"name": "Branch_%02d_v%d_r%03d" % [branches.size(), variant, int(round(rb * 1000.0))],
			"mesh": mesh, "pos": base, "r": rb,
		})

	# limbs that an authored TRUNK socket asked for (a kink's low arm, a
	# candelabra's crown limbs) get built the same way, off the same ratios
	for sk in trunk_socks:
		if String(sk["kind"]) != "bough" or stage < 2 or n == 0:
			continue
		var ty: float = float(sk["t"]) * h
		var r_at: float = _taper(r0, ty, h, taper_p)
		var rb2: float = minf(_pipe_split(r_at, delta, 0.55, [float(sk["w"])])[0], r_at * 0.7)
		var basis2 := _frame(_dir_from(deg_to_rad(float(sk["el"])),
			deg_to_rad(float(sk["az"])) + GOLDEN_ANGLE * float(branches.size())), Vector3.UP)
		var limb2 := _limb(String(pool[branches.size() % pool.size()]),
			h * float(s["blen"]) * 0.8, maxf(rb2, 0.006), delta, s, arms,
			spray_part, relief, 1, stage, is_dead, branches.size() * 5 + 3)
		if (limb2["chains"] as Array).is_empty():
			continue
		_xform(limb2, basis2)
		var m2 := _mesh_of(species, limb2, s, int((s["sides"] as Array)[1]), relief, false)
		if m2 == null:
			continue
		branches.append({
			"name": "Branch_%02d_v%d_r%03d" % [branches.size(), variant, int(round(rb2 * 1000.0))],
			"mesh": m2, "pos": _at_height(spine, ty), "r": rb2,
		})

	# ---- the trunk's own foliage: the leader, and the sapling stem ----------
	if not is_dead and stage > 0 and (conifer or String(rec["top"]) in ["TOP_ROUND", "TOP_CANDELABRA"]):
		for k in range(3):
			var ty2 := lerpf(h * 0.90, h * 0.995, float(k) / 2.0)
			var d := Vector3(cos(GOLDEN_ANGLE * k), 0.55, sin(GOLDEN_ANGLE * k)).normalized()
			_cards(cards_trunk, _at_height(spine, ty2), d, s, h * 0.05 + 0.12, k * 17 + stage)
	if not is_dead and stage == 0:
		for k in range(4):
			var ty3 := lerpf(h * 0.40, h * 0.98, float(k) / 3.0)
			var d3 := Vector3(cos(GOLDEN_ANGLE * k), 0.72, sin(GOLDEN_ANGLE * k)).normalized()
			_cards(cards_trunk, _at_height(spine, ty3), d3, s, 0.12, k * 5 + 1)

	var t_sides := clampi(int(round(float((s["sides"] as Array)[0])
		* clampf(r0 / 0.24, 0.34, 1.10))), 6, 26)
	var trunk_pack := {"chains": [{"v": spine, "r": radii, "ruv": run["ruv"],
		"lobe": lobes}], "cards": cards_trunk}
	var trunk_mesh := _mesh_of(species, trunk_pack, s, t_sides, relief, true)
	return {"trunk": trunk_mesh, "branches": branches, "height": h, "radius": r0}


## One limb and everything it carries, in ITS OWN frame (+Y along the limb).
## Sub-limbs are folded into the same arrays: only order-1 boughs are gameplay
## objects, so an arm and its twigs ride in the same surface and draw call.
static func _limb(part: String, length: float, rbase: float, delta: float,
		s: Dictionary, arms: Array, spray_part: String, relief: Dictionary,
		order: int, stage: int, is_dead: bool, salt: int) -> Dictionary:
	var pd: Dictionary = PARTS.get(part, PARTS["ARM_STRAIGHT"])
	var run := _run([part], length, rbase, length * 1.08, 0.72, false)
	var chains: Array = [{"v": run["v"], "r": run["r"], "ruv": run["ruv"], "lobe": run["lobe"]}]
	var cards: Array = []
	var socks: Array = run["sock"]
	var arc := _arc_len(run["v"])

	var arm_socks: Array = []
	var spray_socks: Array = []
	for sk in socks:
		match String(sk["kind"]):
			"arm": arm_socks.append(sk)
			"spray": spray_socks.append(sk)

	# ---- order-2 / 3 wood, thickness again by the pipe model ----------------
	if order < MAX_ORDER and stage >= (1 if order == 1 else 2) and not arm_socks.is_empty():
		var ws: Array = []
		for sk in arm_socks:
			ws.append(float(sk["w"]))
		var rs: Array = _pipe_split(rbase, delta, 0.46, ws)
		for i in range(arm_socks.size()):
			var sk2: Dictionary = arm_socks[i]
			var t := float(sk2["t"])
			var at := _at_arc(run["v"], t * arc)
			var b := _frame(_dir_from(deg_to_rad(float(sk2["el"])),
				deg_to_rad(float(sk2["az"]))), Vector3.BACK)
			# child length = parent x phi inverse: the middle of the measured
			# 0.55-0.72 apical dominance band
			var clen := length * PHI_INV * lerpf(1.0, 0.72, t)
			var cr: float = minf(float(rs[i]), _rad_on(run["r"], t) * 0.78)
			if cr < MIN_WOOD_R:
				## too thin to be worth a tube -- hang leaves there instead,
				## unless this is a snag, which has none to hang
				if not is_dead and stage > 0:
					_cards(cards, at, _dir_at(run["v"], t * arc), s, length * 0.22,
						salt * 29 + i)
				continue
			var sub := _limb(String(arms[(i + salt) % arms.size()]), clen,
				maxf(cr, 0.004), delta, s, arms, spray_part, relief,
				order + 1, stage, is_dead, salt + i * 3 + 1)
			_xform(sub, b)
			_offset(sub, at)
			chains.append_array(sub["chains"] as Array)
			cards.append_array(sub["cards"] as Array)

	# ---- twig sprays: real wood, with the leaf cards hung off them ----------
	if not is_dead and stage > 0 and not spray_socks.is_empty():
		var want_wood: bool = order == 2 and stage >= 2 \
			and _rad_on(run["r"], 0.6) > MIN_WOOD_R * 1.5
		## Only the OUTERMOST sockets get real twigs. An oak's arms are thick
		## enough that every socket cleared the gate, and a mature oak came out
		## at 13.7k triangles of wood against 3.8k for a fir -- three times the
		## budget, spent on twigs the densified canopy covers anyway.
		var wood_from: int = maxi(spray_socks.size() - 2, 0)
		for i in range(spray_socks.size()):
			var sk3: Dictionary = spray_socks[i]
			var t3 := float(sk3["t"])
			var at3 := _at_arc(run["v"], t3 * arc)
			var d3 := _dir_at(run["v"], t3 * arc)
			if want_wood and i >= wood_from:
				var sb := _frame(_dir_from(deg_to_rad(38.0),
					GOLDEN_ANGLE * float(salt + i)), Vector3.BACK)
				var twig := _limb(spray_part, length * 0.26,
					maxf(_rad_on(run["r"], t3) * 0.42, 0.004), delta, s, arms,
					spray_part, relief, MAX_ORDER, stage, is_dead, salt * 3 + i)
				_xform(twig, sb)
				_offset(twig, at3)
				chains.append_array(twig["chains"] as Array)
				cards.append_array(twig["cards"] as Array)
			else:
				_cards(cards, at3, d3, s, length * 0.22, salt * 13 + i)

	# a limb thin enough to be twig-like carries leaves along ITS OWN length,
	# not just at the sockets — without this a crown is bare inside and leafy
	# only at the very tips, which reads as a bunch of pom-poms on sticks
	if not is_dead and stage > 0 and order >= 1 and rbase < 0.055:
		for k in range(3):
			var tf := lerpf(0.42, 0.96, float(k) / 2.0)
			_cards(cards, _at_arc(run["v"], tf * arc), _dir_at(run["v"], tf * arc),
				s, length * 0.20, salt * 41 + k)

	# a part that declares "cards" carries them along its own outer half
	var nc: int = int(pd.get("cards", 0))
	if nc > 0 and not is_dead and stage > 0:
		for k in range(nc):
			var tk := lerpf(0.35, 1.0, float(k) / float(maxi(nc - 1, 1)))
			_cards(cards, _at_arc(run["v"], tk * arc), _dir_at(run["v"], tk * arc),
				s, length * 0.9, salt * 23 + k)

	return {"chains": chains, "cards": cards}


static func _xform(pack: Dictionary, b: Basis) -> void:
	for ch in (pack["chains"] as Array):
		var v: PackedVector3Array = ch["v"]
		for i in range(v.size()):
			v[i] = b * v[i]
		ch["v"] = v
	for c in (pack["cards"] as Array):
		c["p"] = b * (c["p"] as Vector3)
		c["d"] = (b * (c["d"] as Vector3)).normalized()
		c["up"] = (b * (c["up"] as Vector3)).normalized()


static func _offset(pack: Dictionary, at: Vector3) -> void:
	for ch in (pack["chains"] as Array):
		var v: PackedVector3Array = ch["v"]
		for i in range(v.size()):
			v[i] = v[i] + at
		ch["v"] = v
	for c in (pack["cards"] as Array):
		c["p"] = (c["p"] as Vector3) + at


## Walk a chunk list into ONE continuous spine + radius run, collecting the
## sockets each chunk declares.
static func _run(chunks: Array, length: float, r0: float, taper_h: float,
		taper_p: float, is_trunk: bool) -> Dictionary:
	var spine := PackedVector3Array()
	var radii := PackedFloat32Array()
	## The radius the UVs are measured against: the bare taper, with no part
	## multiplier and no lobe on it. Wrapping u around the REAL radius sheared
	## the texture diagonally wherever the wood changed thickness quickly — a
	## root flare or a burl smeared into streaks.
	var ruv := PackedFloat32Array()
	var lobes: Array = []
	var socks: Array = []
	var wsum := 0.0
	for c in chunks:
		wsum += float((PARTS.get(String(c), PARTS["BOLE_TRUE"]) as Dictionary).get("len", 1.0))
	var y := 0.0
	var lat := Vector3.ZERO
	for ci in range(chunks.size()):
		var pd: Dictionary = PARTS.get(String(chunks[ci]), PARTS["BOLE_TRUE"])
		var seg := length * float(pd.get("len", 1.0)) / maxf(wsum, 0.001)
		var lobe: Array = pd.get("lobe", [])
		var start := lat
		# Ring spacing is decided PER RING: dense only where the axe actually
		# swings. Deciding it once per chunk packed 12 cm rings all the way up
		# a 3 m bole, which was most of the trunk's triangles for nothing.
		var ts := PackedFloat32Array()
		var t := 0.0
		while t < 1.0:
			ts.append(t)
			var yy0 := y + seg * t
			var st: float = (CHOP_RING if yy0 < CHOP_ZONE else WIDE_RING) if is_trunk \
				else maxf(seg / 5.0, 0.07)
			t += maxf(st / maxf(seg, 0.001), 0.02)
		ts.append(1.0)
		if ts.size() < 3:
			ts = PackedFloat32Array([0.0, 0.5, 1.0])
		for k in range(ts.size()):
			if ci > 0 and k == 0:
				continue                       # the joint ring already exists
			var tt: float = ts[k]
			var yy := y + seg * tt
			var off := _path_at(pd, tt) * seg
			var rt := _taper(r0, yy, taper_h, taper_p)
			spine.append(Vector3(start.x + off.x, yy, start.z + off.z))
			radii.append(maxf(rt * _rad_at(pd, tt), 0.003))
			ruv.append(maxf(rt, 0.003))
			lobes.append(lobe)
		lat = start + _path_at(pd, 1.0) * seg
		for sk in (pd.get("sock", []) as Array):
			var a: Array = sk
			socks.append({"t": (y + seg * float(a[0])) / maxf(length, 0.001),
				"el": float(a[1]), "az": float(a[2]), "w": float(a[3]),
				"kind": String(a[4])})
		y += seg
	return {"v": spine, "r": radii, "ruv": ruv, "lobe": lobes, "sock": socks}


static func _path_at(pd: Dictionary, t: float) -> Vector3:
	var path: Array = pd.get("path", [])
	if path.is_empty():
		return Vector3.ZERO
	var prev: Array = path[0]
	if t <= float(prev[0]):
		return Vector3(float(prev[1]), 0.0, float(prev[2]))
	for i in range(1, path.size()):
		var cur: Array = path[i]
		if t <= float(cur[0]):
			var f := (t - float(prev[0])) / maxf(float(cur[0]) - float(prev[0]), 0.0001)
			f = f * f * (3.0 - 2.0 * f)     # smoothstep, so joins have no corner
			return Vector3(lerpf(float(prev[1]), float(cur[1]), f), 0.0,
				lerpf(float(prev[2]), float(cur[2]), f))
		prev = cur
	return Vector3(float(prev[1]), 0.0, float(prev[2]))


static func _rad_at(pd: Dictionary, t: float) -> float:
	var rad: Array = pd.get("rad", [])
	if rad.is_empty():
		return 1.0
	var prev: Array = rad[0]
	if t <= float(prev[0]):
		return float(prev[1])
	for i in range(1, rad.size()):
		var cur: Array = rad[i]
		if t <= float(cur[0]):
			var f := (t - float(prev[0])) / maxf(float(cur[0]) - float(prev[0]), 0.0001)
			return lerpf(float(prev[1]), float(cur[1]), f * f * (3.0 - 2.0 * f))
		prev = cur
	return float(prev[1])


static func _arc_len(v: PackedVector3Array) -> float:
	var a := 0.0
	for i in range(1, v.size()):
		a += v[i].distance_to(v[i - 1])
	return maxf(a, 0.001)


static func _at_arc(v: PackedVector3Array, arc: float) -> Vector3:
	if v.is_empty():
		return Vector3.ZERO
	var a := 0.0
	for i in range(1, v.size()):
		var d := v[i].distance_to(v[i - 1])
		if a + d >= arc:
			return v[i - 1].lerp(v[i], clampf((arc - a) / maxf(d, 0.0001), 0.0, 1.0))
		a += d
	return v[v.size() - 1]


static func _dir_at(v: PackedVector3Array, arc: float) -> Vector3:
	if v.size() < 2:
		return Vector3.UP
	var a := 0.0
	for i in range(1, v.size()):
		var d := v[i].distance_to(v[i - 1])
		if a + d >= arc:
			var dd := v[i] - v[i - 1]
			return dd.normalized() if dd.length() > 1e-5 else Vector3.UP
		a += d
	var e := v[v.size() - 1] - v[v.size() - 2]
	return e.normalized() if e.length() > 1e-5 else Vector3.UP


## The trunk WANDERS: (0, y, 0) is not the centre. Read the real axis at y.
static func _at_height(spine: PackedVector3Array, y: float) -> Vector3:
	if spine.is_empty():
		return Vector3(0, y, 0)
	for i in range(1, spine.size()):
		if spine[i].y >= y:
			var a := spine[i - 1]
			var b := spine[i]
			return a.lerp(b, clampf((y - a.y) / maxf(b.y - a.y, 0.0001), 0.0, 1.0))
	return spine[spine.size() - 1]


static func _rad_on(r: PackedFloat32Array, t: float) -> float:
	if r.is_empty():
		return 0.02
	return r[clampi(int(t * float(r.size() - 1)), 0, r.size() - 1)]


# ===========================================================================
# 6.  BARK AS GEOMETRY
#
#     Every ring vertex is pushed in or out by a per-species field, so plates
#     and fissures break the SILHOUETTE. Sampled in angular CELLS, never in
#     arc length, so the pattern closes exactly around the trunk with no seam,
#     and faded out on thin wood, because a twig has no bark relief.
# ===========================================================================

static func _relief_of(species: String, is_dead: bool) -> Dictionary:
	if is_dead:
		return {"kind": String(DEAD_BARK["bark"]), "amp": float(DEAD_BARK["bark_amp"]),
			"vk": float(DEAD_BARK["bark_v"])}
	var s: Dictionary = SP.get(species, SP["maple"])
	return {"kind": String(s["bark"]), "amp": float(s["bark_amp"]), "vk": float(s["bark_v"])}


## Every octave carries the tree's own BARK SEED. Without it a stand of maples
## all wear the same fissures in the same places, which is the one thing a
## shared mesh gives you for free and you do not want.
## The seed offsets x by a whole number of CELLS, so the field still closes
## exactly around the trunk (see _oct), and y by anything at all.
static func _hash2(x: int, y: int) -> float:
	var n: int = (x * 374761393 + y * 668265263) & 0x7FFFFFFF
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7FFFFFFF
	return float((n ^ (n >> 16)) & 0xFFFFF) / 1048575.0


## Value noise that WRAPS in x at `wrap` cells. The wrap is the whole point:
## sample bark by arc length instead and the trunk shows a seam up one side.
static func _vnoise(x: float, y: float, wrap: int) -> float:
	var x0 := int(floor(x))
	var y0 := int(floor(y))
	var fx := x - float(x0)
	var fy := y - float(y0)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var xa := posmod(x0, wrap)
	var xb := posmod(x0 + 1, wrap)
	var a := lerpf(_hash2(xa, y0), _hash2(xb, y0), fx)
	var b := lerpf(_hash2(xa, y0 + 1), _hash2(xb, y0 + 1), fx)
	return lerpf(a, b, fy)


## One octave of the bark field. `sub` is how many cells this octave uses around
## the trunk, and it MUST be an integer: the octave is sampled at
## ai * sub / cells, so at ai = cells it lands exactly on sub and the pattern
## closes. Scaling ai by anything else (ai * 0.85 for wider plates, say) puts a
## visible seam up one side of every trunk in the forest, which is exactly the
## bug that sampling by arc length would have caused.
static func _oct(ai: float, cells: int, sub: int, v: float, seed: int) -> float:
	sub = maxi(sub, 2)
	return _vnoise(ai * float(sub) / float(cells) + float(posmod(seed, sub)),
		v + float(posmod(seed * 37, 719)), sub)


## Metres of radial displacement at (angular cell ai, height v metres).
static func _bark_offset(kind: String, ai: float, v: float, cells: int,
		vk: float, amp: float, seed := 0) -> float:
	if amp <= 0.0001:
		return 0.0
	match kind:
		"fissure":
			# oak: long deep vertical grooves, with a finer set inside them
			var a := _oct(ai, cells, cells, v * vk, seed)
			var ridge: float = 1.0 - absf(a * 2.0 - 1.0)
			var fine := _oct(ai, cells, cells * 2, v * vk * 2.6, seed)
			return -amp * (pow(ridge, 2.2) * 0.85 + fine * 0.15)
		"plate":
			# maple: shaggy plates lifting off, recessed gaps between them
			var p := _oct(ai, cells, maxi(cells * 3 / 4, 3), v * vk, seed)
			return amp * (smoothstep(0.42, 0.62, p) * 0.9 - smoothstep(0.40, 0.24, p))
		"paper":
			# birch: nearly smooth, horizontal lenticel dashes, the odd peel curl
			var d := _oct(ai, cells, cells * 2, v * vk, seed)
			var curl := _oct(ai + 11.0, cells, maxi(cells / 2, 3), v * vk * 0.35, seed)
			return amp * (smoothstep(0.62, 0.80, d) * 0.35
				+ smoothstep(0.88, 0.99, curl) * 1.6 - 0.12)
		"jigsaw":
			# pine: big irregular plates with narrow deep seams
			var j := _oct(ai, cells, maxi(cells / 2, 3), v * vk, seed)
			var seam: float = 1.0 - absf(j * 2.0 - 1.0)
			return amp * (0.55 - pow(seam, 3.0) * 1.5)
		"smooth":
			# fir: near-smooth grey with sparse resin blisters
			var bl := _oct(ai, cells, cells * 2, v * vk, seed)
			return amp * (smoothstep(0.66, 0.93, bl) * 1.9 - 0.14)
		"split":
			# deadwood: silvered, split wide open, bark gone in patches
			var sp := _oct(ai, cells, maxi(cells * 2 / 3, 3), v * vk, seed)
			var sr: float = 1.0 - absf(sp * 2.0 - 1.0)
			var peel := _oct(ai + 7.0, cells, maxi(cells / 3, 3), v * vk * 0.4, seed)
			return amp * (smoothstep(0.55, 0.85, peel) * 0.35 - pow(sr, 3.0) * 1.4)
	return 0.0


# ===========================================================================
# 7.  MESH
# ===========================================================================

## Bridge every chain into its own watertight tube with rotation-minimising
## frames, so consecutive rings never twist relative to each other. UVs are
## baked in METRES — u around the circumference, v along the wood — which is
## what keeps texel density identical on a fat trunk and a thin twig.
static func _tube(chain: Dictionary, sides: int, relief: Dictionary,
		is_trunk: bool, v_out: PackedVector3Array, n_out: PackedVector3Array,
		t_out: PackedFloat32Array, uv_out: PackedVector2Array,
		i_out: PackedInt32Array) -> void:
	var spine: PackedVector3Array = chain["v"]
	var radii: PackedFloat32Array = chain["r"]
	var ruv: PackedFloat32Array = chain.get("ruv", radii)
	var lobes: Array = chain.get("lobe", [])
	var rings := spine.size()
	if rings < 2:
		return
	sides = clampi(sides, 3, 32)
	# angular cells: half the ring count, so every plate is sampled by at least
	# two vertices and the relief never aliases into noise
	var cells := clampi(sides / 2, 3, 16)
	var amp: float = float(relief["amp"]) if (is_trunk or radii[0] > 0.05) else 0.0
	var kind := String(relief["kind"])
	var vk := float(relief["vk"])
	var bseed := int(relief.get("seed", 0))
	var base := v_out.size()

	var dirs := PackedVector3Array()
	for i in range(rings - 1):
		var d := spine[i + 1] - spine[i]
		dirs.append(d.normalized() if d.length() > 1e-6 else Vector3.UP)

	var u: Vector3 = Vector3.RIGHT
	if absf(dirs[0].dot(u)) > 0.9:
		u = Vector3.FORWARD
	u = (u - dirs[0] * u.dot(dirs[0])).normalized()

	# ---- ring grid, sides wide (the UV seam column is added on the way out) --
	var grid := PackedVector3Array()
	grid.resize(rings * sides)
	var vlens := PackedFloat32Array()
	vlens.resize(rings)
	var circs := PackedFloat32Array()
	circs.resize(rings)
	var vlen := 0.0
	for i in range(rings):
		var d: Vector3 = dirs[mini(i, dirs.size() - 1)]
		if i > 0:
			vlen += spine[i].distance_to(spine[i - 1])
			var dp: Vector3 = dirs[mini(i - 1, dirs.size() - 1)]
			var axis := dp.cross(d)
			if axis.length() > 1e-6:
				u = u.rotated(axis.normalized(), dp.angle_to(d))
			u = (u - d * u.dot(d)).normalized()
		var w := d.cross(u).normalized()
		var r: float = radii[i]
		var fade: float = clampf(r / 0.09, 0.0, 1.0)
		var lobe: Array = lobes[i] if i < lobes.size() else []
		vlens[i] = vlen
		circs[i] = TAU * (ruv[i] if i < ruv.size() else r)
		for k in range(sides):
			var a := TAU * float(k) / float(sides)
			var rr := r
			if amp > 0.0:
				rr += clampf(_bark_offset(kind, float(k) * float(cells) / float(sides),
					vlen, cells, vk, amp * fade), -r * 0.30, r * 0.42)
			if lobe.size() == 3:
				# buttress / rib swell: authored lobes fading up the chunk
				rr += r * float(lobe[1]) * maxf(cos(a * float(lobe[0])), 0.0) \
					* exp(-vlen * float(lobe[2]))
			grid[i * sides + k] = spine[i] + (u * cos(a) + w * sin(a)) * maxf(rr, r * 0.34)

	# ---- normals and tangents straight off the grid --------------------------
	# Central differences around and along the tube. du x dv points OUTWARD by
	# construction (u, w, d is right-handed), and du is exactly the +U texcoord
	# direction, so the tangent is free. Doing this here rather than through
	# SurfaceTool is most of the build's speed.
	var per := sides + 1
	for i in range(rings):
		var ip := maxi(i - 1, 0)
		var inx := mini(i + 1, rings - 1)
		for k in range(per):
			var kk := k % sides
			var du: Vector3 = grid[i * sides + (kk + 1) % sides] - grid[i * sides + posmod(kk - 1, sides)]
			var dv: Vector3 = grid[inx * sides + kk] - grid[ip * sides + kk]
			var nn := du.cross(dv)
			nn = nn.normalized() if nn.length() > 1e-9 else Vector3.UP
			var tg := du.normalized() if du.length() > 1e-9 else Vector3.RIGHT
			v_out.append(grid[i * sides + kk])
			n_out.append(nn)
			t_out.append_array(PackedFloat32Array([tg.x, tg.y, tg.z, 1.0]))
			uv_out.append(Vector2(circs[i] * float(k) / float(sides), vlens[i]))

	for i in range(rings - 1):
		for k in range(sides):
			var a0 := base + i * per + k
			var b0 := base + (i + 1) * per + k
			i_out.append_array(PackedInt32Array([a0, b0, b0 + 1, a0, b0 + 1, a0 + 1]))


## Leaf cards. A spray GROWS OUT OF ITS TWIG: the card's long axis is the
## twig's own direction plus the species' gravity droop, and the base of the
## spray sits at the wood — the atlas cells are drawn stem-at-the-bottom, so
## -v is the attachment point. (Get this wrong and every spray stands bolt
## upright like grass — trees-v2 §22, bug 9.)
static func _cards(out: Array, p: Vector3, d: Vector3, s: Dictionary,
		scale: float, salt: int) -> void:
	var lo: float = float((s["leaf_size"] as Array)[0])
	var hi: float = float((s["leaf_size"] as Array)[1])
	var cl: Array = s["cluster"] as Array
	var span := maxi(int(cl[1]) - int(cl[0]) + 1, 1)
	## leaf_mult is the one dial that trades canopy fill against frame rate.
	## Every card here becomes PAD_OUTER_N + PAD_INNER_N alpha-DISCARD quads in
	## TreeV2._densify_canopy, and a discard quad kills early-Z: it costs a full
	## fragment in the colour pass and again in every shadow split. Fill rate,
	## not triangles, is the wall (measured by the GPU pass, 2026-08-30) -- so
	## these numbers are set so the kit lands UNDER the seed count of the GLBs
	## it replaces, per species, not over it.
	var n: int = maxi(int(round(float(int(cl[0]) + posmod(salt, span))
		* float(s.get("leaf_mult", 1.0)))), 1)
	for k in range(n):
		var f := _hash2(salt * 31 + k, 7)
		var g := _hash2(salt * 17 + k, 13)
		var size: float = lerpf(lo, hi, f) * clampf(scale / 0.30, 0.72, 1.35)
		out.append({
			"p": p + Vector3(f - 0.5, g - 0.5, f * g - 0.25) * size * 0.55,
			"d": d.normalized(), "up": Vector3.UP, "s": size,
			"cell": int(g * 7.999), "droop": float(s["leaf_droop"]),
		})


static func _mesh_of(species: String, pack: Dictionary, s: Dictionary,
		sides: int, relief: Dictionary, is_trunk: bool) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var t := PackedFloat32Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	for ch in (pack["chains"] as Array):
		_tube(ch, sides, relief, is_trunk, v, n, t, uv, idx)
	if v.is_empty():
		return null

	var wood := []
	wood.resize(Mesh.ARRAY_MAX)
	wood[Mesh.ARRAY_VERTEX] = v
	wood[Mesh.ARRAY_NORMAL] = n
	wood[Mesh.ARRAY_TANGENT] = t
	wood[Mesh.ARRAY_TEX_UV] = uv
	wood[Mesh.ARRAY_INDEX] = idx

	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, wood)
	var bm := StandardMaterial3D.new()
	bm.resource_name = "bark_" + species
	am.surface_set_material(0, bm)

	var cards: Array = pack["cards"]
	if not cards.is_empty():
		var leaf := _card_arrays(cards, bool(s.get("cross", true)))
		if not (leaf[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, leaf)
			var lm := StandardMaterial3D.new()
			lm.resource_name = "leaf_" + String(s["leaf"])
			am.surface_set_material(1, lm)
	return am


static func _card_arrays(cards: Array, cross: bool) -> Array:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var tan := PackedFloat32Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	for c in cards:
		var d: Vector3 = (c["d"] as Vector3).normalized()
		var up: Vector3 = (c["up"] as Vector3)
		var grow := (d + up * -float(c["droop"])).normalized()
		var side := grow.cross(up)
		if side.length() < 1e-4:
			side = grow.cross(Vector3.RIGHT)
		if side.length() < 1e-4:
			side = Vector3.RIGHT
		side = side.normalized()
		var size: float = float(c["s"])
		var centre: Vector3 = (c["p"] as Vector3) + grow * size * 0.92
		var cell: int = int(c["cell"]) % 8
		var c0 := float(cell % 4) * 0.25
		var r0 := 1.0 - float(cell / 4 + 1) * 0.25
		for pl in range(2 if cross else 1):
			var uax := side * size if pl == 0 else grow.cross(side).normalized() * size
			var vax := grow * size
			var nn := uax.cross(vax).normalized()
			var base := v.size()
			var corners := [centre - uax - vax, centre + uax - vax,
				centre + uax + vax, centre - uax + vax]
			var cuv := [Vector2(c0, r0), Vector2(c0 + 0.25, r0),
				Vector2(c0 + 0.25, r0 + 0.25), Vector2(c0, r0 + 0.25)]
			var un := uax.normalized()
			for k in range(4):
				v.append(corners[k])
				nrm.append(nn)
				tan.append_array(PackedFloat32Array([un.x, un.y, un.z, 1.0]))
				uv.append(cuv[k])
			idx.append_array(PackedInt32Array([base, base + 1, base + 2,
				base, base + 2, base + 3]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TANGENT] = tan
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	return arr
