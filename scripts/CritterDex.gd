class_name CritterDex
extends RefCounted

## ===========================================================================
## THE DEX — every wild thing in Myrkfell, as data.        docs/WILDLIFE.md §2
##
## Adding species #66 costs ONE entry here and ZERO code, exactly like
## TreeProfile did for the forest. Nothing in this file knows how to draw or
## think — CritterRig builds the body from these numbers, CritterAnim poses it,
## and Critter runs the archetype. This is the only place a species is
## DESCRIBED.
##
## Every field is a stated default, not a guess to re-derive. Change one with a
## reason and log it.
##
## FIELDS
##   nm    display name
##   rig   rig family — CritterRig knows these: CERVID URSID CANID FELID
##         MUSTELID CHUNK RODENT_S BIRD_GROUND BIRD_RAPTOR BIRD_PERCH
##         BIRD_WATER HERP FISH SWARM
##   arch  AI archetype — Critter knows these: SKITTER SENTINEL BLUFFER
##         STALKER RAIDER ENGINEER SCAVENGER AMBIENT
##   len   body length nose-to-rump, metres (drives the whole rig)
##   hgt   shoulder/standing height, metres
##   hp    max health
##   spd   [amble, flat-out] metres/sec
##   see   [notice radius, panic radius] — SKITTER flees inside panic
##   col   primary coat/plumage        col2  belly/marking     col3  accent
##   sig   signature animation keys (CritterAnim owns these)
##   call  {idle, alarm} keys into the wildlife audio manifest
##   zone  spawn weights per map-v1 zone (see ZONES); absent = never there
##   flags per-species switches, all optional:
##         night      active after nightfall, scarce by day
##         dusk       crepuscular — dawn and dusk peaks
##         herd       spawns as a group of N
##         water      needs a pond/river/lake; swims
##         cliff      needs high ground
##         den        gone all winter (bears)
##         coat_swap  brown <-> white on season_phase (hare, ermine)
##         migrate    [leaves_phase, returns_phase] — gone between them
##         rut        autumn aggression spike
##         bold       BLUFFER only: warnings it gives before it commits.
##                    Default 2 (warn, warn harder, then mean it). 1 = one
##                    warning. 0 = no warning at all.
##         relentless never routs, never disengages after landing a hit, and
##                    charges from the full warn radius instead of waiting
##                    for you to close. The bear.
##         leash      how far it will follow before it gives up (metres).
##                    Absent = twice the notice radius.
##         swattable  SWARM only: a weapon swing kills members of this cloud.
##                    Everything else just scatters when a blade goes past.
##         quills     melee attackers take contact damage + stuck quills
##         spray      the skunk special
##         latch      bite that holds (snapper)
##         climbs     can go up a trunk
##         glide      flies; ignores ground
##         legend     hand-placed only, never scatter-spawned
##         nofight    literally cannot be made hostile
##   dmg   attack damage (0 = harmless)
##   harv  harvest yields — {item: count}; the hunting loop reads this when it
##         exists, and nothing breaks while it doesn't
## ===========================================================================

## Map v1's ten zones plus the wet/edge habitats that cut across them.
const ZONES := [
	"beacon_coast", "freeport_road", "mill_reaches", "kennebec_seat",
	"western_peaks", "moosehead", "bangor_gate", "katahdin",
	"dawnwatch", "county",
	"river", "lake", "bog", "field", "deep_woods", "gulf",
]

## Seasons, as season_phase bands. Wind.phase_for_day() feeds this.
const SPRING := 0
const SUMMER := 1
const AUTUMN := 2
const WINTER := 3


static func season_of(phase: float) -> int:
	return int(fposmod(phase, 1.0) * 4.0) % 4


## ============================== THE ROSTER ================================

const DEX := {

## ---------------------------------------------------- TIER 1: megafauna ---

"moose": {
	"nm": "Moose", "rig": "CERVID", "arch": "BLUFFER",
	"len": 2.9, "hgt": 2.1, "hp": 260.0, "dmg": 34.0,
	"spd": [1.3, 8.2], "see": [22.0, 9.0],
	"col": Color(0.20, 0.15, 0.11), "col2": Color(0.30, 0.24, 0.18), "col3": Color(0.52, 0.46, 0.34),
	"sig": ["moose_dunk", "antler_thrash", "rut_spar", "hackles"],
	"call": {"idle": "moose_bellow", "alarm": "moose_cow_call"},
	"zone": {"moosehead": 1.0, "county": 0.7, "bog": 1.0, "katahdin": 0.4, "bangor_gate": 0.4, "western_peaks": 0.3},
	"flags": {"herd": 1, "water": true, "rut": true, "dusk": true},
	"feat": {"antler": 1.5, "dewlap": true, "hump": 0.34, "muzzle": 1.5},
	"harv": {"meat": 6, "hide": 2, "antler": 1, "sinew": 3},
},
"black_bear": {
	## THE BEAR DOES NOT BACK DOWN (Lemon, 2026-08-23). It notices you from
	## further out, gives exactly ONE warning instead of two, commits from the
	## full warn radius rather than waiting until you are half-way in, and
	## never routs — `relentless` zeroes its nerve and keeps it in the charge
	## between hits instead of dropping back to a huff. At 10.2 m/s it is
	## faster than a sprinting player (8.0), on purpose: you do not outrun a
	## bear, you fight it, climb something, or get far enough away that it
	## loses interest — `leash_radius` is the honest out.
	"nm": "Black Bear", "rig": "URSID", "arch": "BLUFFER",
	"len": 1.7, "hgt": 1.0, "hp": 240.0, "dmg": 38.0,
	"spd": [1.2, 10.2], "see": [30.0, 15.0],
	"col": Color(0.07, 0.06, 0.06), "col2": Color(0.13, 0.11, 0.10), "col3": Color(0.42, 0.33, 0.24),
	"sig": ["bear_stand", "bear_huff", "log_rip", "berry_gorge", "tree_climb"],
	"call": {"idle": "bear_growl", "alarm": "bear_huff"},
	"zone": {"deep_woods": 1.0, "moosehead": 1.0, "western_peaks": 0.9, "katahdin": 0.7,
		"bangor_gate": 0.6, "county": 0.6, "dawnwatch": 0.4, "freeport_road": 0.2},
	"flags": {"den": true, "climbs": true, "dusk": true, "raids": true,
		"bold": 1, "relentless": true, "leash": 58.0,
		## Contact specials (Critter._pick_move): the jaw grab-and-toss and
		## the rear-up press. Any species can carry these flags — the moves
		## ride the URSID clips, so give them to something with a jaw pivot.
		"grab": true, "press": true},
	"feat": {"hump": 0.22, "muzzle": 1.2, "claw": true},
	"harv": {"meat": 5, "hide": 1, "fat": 3, "claw": 4},
},
"whitetail": {
	"nm": "White-tailed Deer", "rig": "CERVID", "arch": "SENTINEL",
	"len": 1.7, "hgt": 1.1, "hp": 70.0, "dmg": 6.0,
	"spd": [1.4, 11.0], "see": [30.0, 17.0],
	"col": Color(0.44, 0.31, 0.20), "col2": Color(0.88, 0.86, 0.80), "col3": Color(0.55, 0.48, 0.36),
	"sig": ["tail_flag", "hoof_stomp", "snort_wheeze", "pogo_bound", "velvet_rub"],
	"call": {"idle": "", "alarm": "deer_snort"},
	"zone": {"freeport_road": 1.0, "mill_reaches": 0.8, "kennebec_seat": 0.9, "beacon_coast": 0.7,
		"river": 0.9, "field": 1.0, "deep_woods": 0.6, "bangor_gate": 0.6, "dawnwatch": 0.5},
	"flags": {"herd": 3, "rut": true, "dusk": true},
	"feat": {"antler": 0.55, "muzzle": 1.0, "whitetail": true},
	"harv": {"meat": 3, "hide": 1, "sinew": 2, "antler": 1},
},
"coyote": {
	"nm": "Eastern Coyote", "rig": "CANID", "arch": "STALKER",
	"len": 1.1, "hgt": 0.62, "hp": 85.0, "dmg": 14.0,
	"spd": [1.6, 10.5], "see": [26.0, 0.0],
	"col": Color(0.40, 0.34, 0.25), "col2": Color(0.62, 0.57, 0.47), "col3": Color(0.24, 0.19, 0.14),
	"sig": ["howl", "mouse_pounce", "skulk", "pack_pincer"],
	"call": {"idle": "coyote_howl", "alarm": "coyote_chorus"},
	"zone": {"freeport_road": 1.0, "mill_reaches": 1.0, "kennebec_seat": 0.9, "field": 1.0,
		"deep_woods": 0.8, "bangor_gate": 0.8, "moosehead": 0.6, "county": 0.6, "beacon_coast": 0.6},
	"flags": {"herd": 3, "night": true, "scav": true},
	"feat": {"muzzle": 1.2, "brush_tail": true, "ruff": 0.2},
	"harv": {"meat": 1, "pelt": 1},
},
"lynx": {
	"nm": "Canada Lynx", "rig": "FELID", "arch": "STALKER",
	"len": 0.95, "hgt": 0.58, "hp": 95.0, "dmg": 18.0,
	"spd": [1.5, 10.0], "see": [24.0, 0.0],
	"col": Color(0.55, 0.52, 0.47), "col2": Color(0.74, 0.72, 0.68), "col3": Color(0.12, 0.11, 0.10),
	"sig": ["snow_float", "hare_ambush", "caterwaul", "silent_stalk"],
	"call": {"idle": "lynx_caterwaul", "alarm": "lynx_caterwaul"},
	"zone": {"county": 1.0, "katahdin": 0.8, "moosehead": 0.6, "deep_woods": 0.35},
	"flags": {"night": true, "rare": 0.25, "snowwalk": true},
	"feat": {"tuft": 0.14, "bobtail": 0.12, "ruff": 0.26, "bigpaw": 1.7},
	"harv": {"meat": 1, "pelt": 2},
},
"bobcat": {
	"nm": "Bobcat", "rig": "FELID", "arch": "STALKER",
	"len": 0.82, "hgt": 0.48, "hp": 80.0, "dmg": 15.0,
	"spd": [1.5, 10.6], "see": [22.0, 0.0],
	"col": Color(0.52, 0.40, 0.27), "col2": Color(0.80, 0.76, 0.68), "col3": Color(0.16, 0.13, 0.10),
	"sig": ["hare_ambush", "silent_stalk", "caterwaul"],
	"call": {"idle": "lynx_caterwaul", "alarm": "lynx_caterwaul"},
	"zone": {"western_peaks": 0.9, "kennebec_seat": 0.8, "mill_reaches": 0.7, "freeport_road": 0.6,
		"deep_woods": 0.7, "dawnwatch": 0.5},
	"flags": {"night": true, "rare": 0.4, "spots": true},
	"feat": {"tuft": 0.07, "bobtail": 0.16, "ruff": 0.18, "bigpaw": 1.0},
	"harv": {"meat": 1, "pelt": 1},
},
"fisher": {
	"nm": "Fisher", "rig": "MUSTELID", "arch": "STALKER",
	"len": 0.68, "hgt": 0.26, "hp": 60.0, "dmg": 13.0,
	"spd": [1.7, 9.0], "see": [18.0, 0.0],
	"col": Color(0.15, 0.12, 0.10), "col2": Color(0.28, 0.23, 0.19), "col3": Color(0.40, 0.35, 0.29),
	"sig": ["deadfall_run", "tree_spiral", "porc_flip", "scream"],
	"call": {"idle": "fisher_scream", "alarm": "fisher_scream"},
	"zone": {"deep_woods": 1.0, "moosehead": 0.9, "western_peaks": 0.7, "county": 0.6, "katahdin": 0.4},
	"flags": {"night": true, "climbs": true, "rare": 0.5},
	"feat": {"bushy": 0.9, "lowslung": true},
	"harv": {"pelt": 2},
},

## -------------------------------------- TIER 2: furbearers & charisma ---

"red_fox": {
	"nm": "Red Fox", "rig": "CANID", "arch": "STALKER",
	"len": 0.72, "hgt": 0.40, "hp": 45.0, "dmg": 9.0,
	"spd": [1.5, 9.8], "see": [22.0, 12.0],
	"col": Color(0.66, 0.28, 0.09), "col2": Color(0.92, 0.90, 0.86), "col3": Color(0.10, 0.09, 0.08),
	"sig": ["mouse_dive", "fox_curl", "scream", "skulk"],
	"call": {"idle": "fox_scream", "alarm": "fox_scream"},
	"zone": {"field": 1.0, "freeport_road": 0.9, "kennebec_seat": 0.8, "beacon_coast": 0.7,
		"mill_reaches": 0.7, "county": 0.7, "dawnwatch": 0.6, "deep_woods": 0.4},
	"flags": {"dusk": true, "night": true},
	"feat": {"muzzle": 1.35, "brush_tail": true, "tailtip": true, "socks": true},
	"harv": {"pelt": 1},
},
"gray_fox": {
	"nm": "Gray Fox", "rig": "CANID", "arch": "STALKER",
	"len": 0.68, "hgt": 0.36, "hp": 42.0, "dmg": 8.0,
	"spd": [1.5, 9.0], "see": [20.0, 12.0],
	"col": Color(0.42, 0.41, 0.38), "col2": Color(0.72, 0.60, 0.40), "col3": Color(0.14, 0.12, 0.11),
	"sig": ["trunk_scramble", "skulk"],
	"call": {"idle": "fox_scream", "alarm": "fox_scream"},
	"zone": {"freeport_road": 0.7, "kennebec_seat": 0.6, "mill_reaches": 0.5, "deep_woods": 0.5},
	"flags": {"night": true, "climbs": true, "rare": 0.5},
	"feat": {"muzzle": 1.25, "brush_tail": true, "tailstripe": true},
	"harv": {"pelt": 1},
},
"porcupine": {
	"nm": "Porcupine", "rig": "CHUNK", "arch": "BLUFFER",
	"len": 0.72, "hgt": 0.32, "hp": 65.0, "dmg": 8.0,
	"spd": [0.5, 1.9], "see": [9.0, 3.5],
	"col": Color(0.16, 0.14, 0.12), "col2": Color(0.30, 0.27, 0.22), "col3": Color(0.86, 0.82, 0.62),
	"sig": ["quill_bristle", "tail_swat", "limb_nap", "waddle"],
	"call": {"idle": "porcupine_moan", "alarm": "porcupine_moan"},
	"zone": {"deep_woods": 1.0, "moosehead": 0.8, "western_peaks": 0.8, "county": 0.7, "katahdin": 0.5},
	"flags": {"quills": true, "night": true, "climbs": true, "slow": true},
	"feat": {"quill": 0.22, "humped": true},
	"harv": {"meat": 1, "quill": 12},
},
"skunk": {
	"nm": "Striped Skunk", "rig": "CHUNK", "arch": "BLUFFER",
	"len": 0.48, "hgt": 0.22, "hp": 35.0, "dmg": 4.0,
	"spd": [0.7, 2.6], "see": [10.0, 4.0],
	"col": Color(0.06, 0.06, 0.06), "col2": Color(0.95, 0.95, 0.93), "col3": Color(0.90, 0.88, 0.60),
	"sig": ["foot_stamp", "tail_up", "u_pose", "spray"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"freeport_road": 0.9, "field": 0.9, "kennebec_seat": 0.8, "mill_reaches": 0.8,
		"beacon_coast": 0.6, "deep_woods": 0.5},
	"flags": {"spray": true, "night": true, "raids": true},
	"feat": {"stripe": true, "bushy": 1.1},
	"harv": {"pelt": 1},
},
"raccoon": {
	"nm": "Raccoon", "rig": "CHUNK", "arch": "RAIDER",
	"len": 0.58, "hgt": 0.30, "hp": 45.0, "dmg": 7.0,
	"spd": [0.9, 5.6], "see": [14.0, 6.0],
	"col": Color(0.38, 0.36, 0.33), "col2": Color(0.60, 0.58, 0.54), "col3": Color(0.09, 0.08, 0.08),
	"sig": ["camp_case", "unlatch", "rummage", "food_wash", "mask_stare"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"river": 1.0, "freeport_road": 0.9, "bangor_gate": 0.8, "mill_reaches": 0.8,
		"kennebec_seat": 0.7, "beacon_coast": 0.7, "deep_woods": 0.5},
	"flags": {"night": true, "climbs": true, "raids": true},
	"feat": {"mask": true, "ringtail": 5, "muzzle": 1.1},
	"harv": {"meat": 1, "pelt": 1},
},
"beaver": {
	"nm": "Beaver", "rig": "CHUNK", "arch": "ENGINEER",
	"len": 0.85, "hgt": 0.32, "hp": 70.0, "dmg": 10.0,
	"spd": [0.7, 3.0], "see": [16.0, 7.0],
	"col": Color(0.30, 0.20, 0.13), "col2": Color(0.40, 0.29, 0.20), "col3": Color(0.16, 0.13, 0.11),
	"sig": ["tail_slap", "gnaw_ring", "log_drag", "lodge_dive", "swim_wake"],
	"call": {"idle": "", "alarm": "beaver_slap"},
	"zone": {"river": 1.0, "lake": 0.8, "moosehead": 0.9, "county": 0.8, "western_peaks": 0.7, "bog": 0.7},
	"flags": {"water": true, "dusk": true, "engineer": true},
	"feat": {"paddle": true, "incisor": true, "humped": true},
	"harv": {"meat": 2, "pelt": 2, "castor": 1},
},
"otter": {
	"nm": "River Otter", "rig": "MUSTELID", "arch": "SKITTER",
	"len": 0.80, "hgt": 0.26, "hp": 50.0, "dmg": 8.0,
	"spd": [1.2, 6.0], "see": [16.0, 8.0],
	"col": Color(0.24, 0.18, 0.13), "col2": Color(0.50, 0.45, 0.38), "col3": Color(0.14, 0.11, 0.09),
	"sig": ["bank_slide", "porpoise", "fish_toss", "otter_row"],
	"call": {"idle": "otter_chirp", "alarm": "otter_chirp"},
	"zone": {"river": 1.0, "lake": 1.0, "moosehead": 0.8, "bog": 0.5},
	"flags": {"water": true, "herd": 3, "nofight": true},
	"feat": {"thicktail": true, "lowslung": true},
	"harv": {"pelt": 2},
},
"hare": {
	"nm": "Snowshoe Hare", "rig": "RODENT_S", "arch": "SKITTER",
	"len": 0.42, "hgt": 0.26, "hp": 22.0, "dmg": 0.0,
	"spd": [0.8, 9.6], "see": [16.0, 10.0],
	"col": Color(0.36, 0.28, 0.20), "col2": Color(0.94, 0.94, 0.96), "col3": Color(0.10, 0.09, 0.08),
	"sig": ["zigzag", "freeze_crouch", "sit_scan", "hop"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"deep_woods": 1.0, "county": 1.0, "moosehead": 0.9, "katahdin": 0.7, "western_peaks": 0.7},
	"flags": {"coat_swap": true, "hop": true, "dusk": true, "prey": true},
	"feat": {"longear": 0.16, "bigfoot": true, "puff_tail": true},
	"harv": {"meat": 1, "pelt": 1},
},
"ermine": {
	"nm": "Ermine", "rig": "MUSTELID", "arch": "STALKER",
	"len": 0.26, "hgt": 0.10, "hp": 16.0, "dmg": 5.0,
	"spd": [1.4, 7.0], "see": [12.0, 0.0],
	"col": Color(0.40, 0.28, 0.17), "col2": Color(0.96, 0.96, 0.94), "col3": Color(0.06, 0.05, 0.05),
	"sig": ["war_dance", "snow_pop", "noodle_bound"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"deep_woods": 0.8, "county": 1.0, "field": 0.7, "moosehead": 0.7, "katahdin": 0.5},
	"flags": {"coat_swap": true, "blacktip": true, "rare": 0.6},
	"feat": {"lowslung": true, "tailtip": true},
	"harv": {"pelt": 1},
},
"marten": {
	"nm": "American Marten", "rig": "MUSTELID", "arch": "STALKER",
	"len": 0.50, "hgt": 0.18, "hp": 34.0, "dmg": 8.0,
	"spd": [1.4, 7.6], "see": [15.0, 0.0],
	"col": Color(0.32, 0.20, 0.12), "col2": Color(0.78, 0.60, 0.28), "col3": Color(0.18, 0.14, 0.11),
	"sig": ["tree_spiral", "deadfall_run"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"moosehead": 1.0, "deep_woods": 0.8, "katahdin": 0.6, "county": 0.7},
	"flags": {"climbs": true, "arboreal": true, "rare": 0.5},
	"feat": {"bushy": 0.8, "bib": true},
	"harv": {"pelt": 2},
},
"mink": {
	"nm": "Mink", "rig": "MUSTELID", "arch": "STALKER",
	"len": 0.42, "hgt": 0.14, "hp": 26.0, "dmg": 6.0,
	"spd": [1.3, 6.8], "see": [13.0, 0.0],
	"col": Color(0.17, 0.12, 0.10), "col2": Color(0.90, 0.88, 0.84), "col3": Color(0.10, 0.08, 0.07),
	"sig": ["noodle_bound", "oil_slip"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"river": 1.0, "lake": 0.7, "bog": 0.6, "beacon_coast": 0.4},
	"flags": {"water": true, "rare": 0.5},
	"feat": {"lowslung": true, "chinspot": true},
	"harv": {"pelt": 2},
},
"opossum": {
	"nm": "Virginia Opossum", "rig": "CHUNK", "arch": "SKITTER",
	"len": 0.52, "hgt": 0.22, "hp": 30.0, "dmg": 4.0,
	"spd": [0.6, 3.4], "see": [11.0, 5.0],
	"col": Color(0.62, 0.60, 0.56), "col2": Color(0.90, 0.88, 0.84), "col3": Color(0.72, 0.55, 0.50),
	"sig": ["play_dead", "waddle", "hiss_gape"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"freeport_road": 0.8, "beacon_coast": 0.7, "kennebec_seat": 0.6, "mill_reaches": 0.6},
	"flags": {"night": true, "south_only": true, "playdead": true, "climbs": true},
	"feat": {"ratrail": true, "pointface": true},
	"harv": {"meat": 1, "pelt": 1},
},
"woodchuck": {
	"nm": "Woodchuck", "rig": "CHUNK", "arch": "SENTINEL",
	"len": 0.46, "hgt": 0.22, "hp": 30.0, "dmg": 4.0,
	"spd": [0.7, 4.4], "see": [16.0, 9.0],
	"col": Color(0.36, 0.28, 0.18), "col2": Color(0.52, 0.42, 0.28), "col3": Color(0.14, 0.12, 0.10),
	"sig": ["periscope", "whistle", "burrow_dive"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"field": 1.0, "freeport_road": 0.9, "kennebec_seat": 0.7, "mill_reaches": 0.6},
	"flags": {"den": true, "burrow": true},
	"feat": {"humped": true, "shorttail": true},
	"harv": {"meat": 1, "pelt": 1},
},
"muskrat": {
	"nm": "Muskrat", "rig": "CHUNK", "arch": "SKITTER",
	"len": 0.34, "hgt": 0.15, "hp": 20.0, "dmg": 3.0,
	"spd": [0.7, 3.6], "see": [12.0, 6.0],
	"col": Color(0.29, 0.21, 0.14), "col2": Color(0.44, 0.35, 0.24), "col3": Color(0.13, 0.11, 0.09),
	"sig": ["swim_wake", "cattail_feed"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"bog": 1.0, "river": 0.8, "lake": 0.7},
	"flags": {"water": true},
	"feat": {"ratrail": true},
	"harv": {"pelt": 1},
},
"red_squirrel": {
	"nm": "Red Squirrel", "rig": "RODENT_S", "arch": "SENTINEL",
	"len": 0.20, "hgt": 0.11, "hp": 10.0, "dmg": 0.0,
	"spd": [1.2, 6.0], "see": [15.0, 7.0],
	"col": Color(0.60, 0.30, 0.13), "col2": Color(0.94, 0.92, 0.88), "col3": Color(0.14, 0.12, 0.10),
	"sig": ["trunk_spiral", "scold", "midden"],
	"call": {"idle": "red_squirrel_scold", "alarm": "red_squirrel_scold"},
	"zone": {"deep_woods": 1.0, "moosehead": 0.9, "western_peaks": 0.9, "county": 0.8,
		"katahdin": 0.7, "freeport_road": 0.5},
	"flags": {"climbs": true, "arboreal": true, "narc": true},
	"feat": {"plumetail": 1.1, "eyering": true},
	"harv": {},
},
"gray_squirrel": {
	"nm": "Gray Squirrel", "rig": "RODENT_S", "arch": "SKITTER",
	"len": 0.26, "hgt": 0.13, "hp": 12.0, "dmg": 0.0,
	"spd": [1.1, 6.4], "see": [14.0, 7.0],
	"col": Color(0.46, 0.46, 0.45), "col2": Color(0.92, 0.91, 0.88), "col3": Color(0.60, 0.50, 0.36),
	"sig": ["trunk_spiral", "cache_run", "tail_flick"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"freeport_road": 1.0, "kennebec_seat": 0.9, "mill_reaches": 0.8, "beacon_coast": 0.7,
		"deep_woods": 0.6, "dawnwatch": 0.6},
	"flags": {"climbs": true, "arboreal": true},
	"feat": {"plumetail": 1.35},
	"harv": {"meat": 1},
},
"chipmunk": {
	"nm": "Eastern Chipmunk", "rig": "RODENT_S", "arch": "SKITTER",
	"len": 0.14, "hgt": 0.07, "hp": 7.0, "dmg": 0.0,
	"spd": [1.3, 5.4], "see": [11.0, 6.0],
	"col": Color(0.55, 0.38, 0.22), "col2": Color(0.92, 0.90, 0.84), "col3": Color(0.15, 0.12, 0.10),
	"sig": ["cheek_stuff", "wall_dash", "cache_run"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"freeport_road": 1.0, "field": 0.8, "kennebec_seat": 0.8, "deep_woods": 0.7,
		"mill_reaches": 0.6, "dawnwatch": 0.6},
	"flags": {"stripes": true},
	"feat": {"plumetail": 0.8, "stripe": true},
	"harv": {},
},
"bat": {
	"nm": "Little Brown Bat", "rig": "SWARM", "arch": "AMBIENT",
	"len": 0.09, "hgt": 0.05, "hp": 4.0, "dmg": 0.0,
	"spd": [4.0, 8.0], "see": [0.0, 0.0],
	"col": Color(0.16, 0.13, 0.11), "col2": Color(0.24, 0.20, 0.17), "col3": Color(0.10, 0.09, 0.08),
	"sig": ["bat_ribbon"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"mill_reaches": 1.0, "river": 0.8, "lake": 0.8, "bangor_gate": 0.6, "deep_woods": 0.5},
	"flags": {"night": true, "glide": true, "swarm": 14},
	"feat": {"wing": 0.16},
	"harv": {},
},

## ------------------------------------------------------- TIER 3: birds ---

"loon": {
	"nm": "Common Loon", "rig": "BIRD_WATER", "arch": "SENTINEL",
	"len": 0.78, "hgt": 0.30, "hp": 40.0, "dmg": 6.0,
	"spd": [0.8, 5.0], "see": [26.0, 14.0],
	"col": Color(0.05, 0.05, 0.07), "col2": Color(0.96, 0.96, 0.96), "col3": Color(0.08, 0.07, 0.09),
	"sig": ["loon_wail", "torpedo_dive", "water_run", "chick_ride", "penguin_dance"],
	"call": {"idle": "loon_wail", "alarm": "loon_tremolo"},
	"zone": {"lake": 1.0, "moosehead": 1.0, "county": 0.6, "western_peaks": 0.5},
	"flags": {"water": true, "migrate": [0.80, 0.15], "dusk": true, "nofight": true},
	"feat": {"checker": true, "daggerbill": true, "necklace": true},
	"harv": {},
},
"bald_eagle": {
	"nm": "Bald Eagle", "rig": "BIRD_RAPTOR", "arch": "STALKER",
	"len": 0.85, "hgt": 0.55, "hp": 60.0, "dmg": 14.0,
	"spd": [6.0, 16.0], "see": [40.0, 0.0],
	"col": Color(0.22, 0.16, 0.11), "col2": Color(0.97, 0.97, 0.95), "col3": Color(0.95, 0.78, 0.10),
	"sig": ["fish_snatch", "osprey_mug", "snag_sentinel", "soar"],
	"call": {"idle": "eagle_cry", "alarm": "eagle_cry"},
	"zone": {"lake": 1.0, "river": 0.9, "beacon_coast": 0.9, "moosehead": 0.9, "dawnwatch": 0.8, "gulf": 0.6},
	"flags": {"glide": true, "rare": 0.5, "soars": true},
	"feat": {"wing": 1.05, "hookbill": true, "whitehead": true},
	"harv": {"feather": 3},
},
"osprey": {
	"nm": "Osprey", "rig": "BIRD_RAPTOR", "arch": "STALKER",
	"len": 0.60, "hgt": 0.42, "hp": 42.0, "dmg": 10.0,
	"spd": [6.0, 14.0], "see": [36.0, 0.0],
	"col": Color(0.28, 0.24, 0.20), "col2": Color(0.95, 0.94, 0.92), "col3": Color(0.80, 0.72, 0.30),
	"sig": ["hover_plunge", "shake_off", "fish_carry", "soar"],
	"call": {"idle": "osprey_whistle", "alarm": "osprey_whistle"},
	"zone": {"lake": 1.0, "river": 0.8, "beacon_coast": 0.8, "moosehead": 0.7, "dawnwatch": 0.7},
	"flags": {"glide": true, "migrate": [0.72, 0.10], "soars": true},
	"feat": {"wing": 0.86, "hookbill": true, "eyestripe": true},
	"harv": {"feather": 2},
},
"barred_owl": {
	"nm": "Barred Owl", "rig": "BIRD_RAPTOR", "arch": "STALKER",
	"len": 0.48, "hgt": 0.42, "hp": 34.0, "dmg": 9.0,
	"spd": [4.0, 11.0], "see": [26.0, 0.0],
	"col": Color(0.42, 0.36, 0.30), "col2": Color(0.86, 0.83, 0.77), "col3": Color(0.14, 0.12, 0.14),
	"sig": ["silent_glide", "head_track", "hoot"],
	"call": {"idle": "barred_owl", "alarm": "barred_owl"},
	"zone": {"deep_woods": 1.0, "moosehead": 0.9, "freeport_road": 0.7, "western_peaks": 0.8,
		"bangor_gate": 0.7, "kennebec_seat": 0.6, "dawnwatch": 0.6},
	"flags": {"night": true, "glide": true, "perches": true},
	"feat": {"wing": 0.62, "facedisc": true, "hookbill": true, "barring": true},
	"harv": {"feather": 2},
},
"great_horned_owl": {
	"nm": "Great Horned Owl", "rig": "BIRD_RAPTOR", "arch": "STALKER",
	"len": 0.55, "hgt": 0.48, "hp": 46.0, "dmg": 13.0,
	"spd": [4.5, 12.0], "see": [30.0, 0.0],
	"col": Color(0.34, 0.27, 0.20), "col2": Color(0.78, 0.72, 0.62), "col3": Color(0.90, 0.72, 0.12),
	"sig": ["silent_glide", "head_track", "hoot", "skunk_take"],
	"call": {"idle": "great_horned_owl", "alarm": "great_horned_owl"},
	"zone": {"deep_woods": 0.9, "field": 0.7, "western_peaks": 0.7, "county": 0.6, "bangor_gate": 0.6},
	"flags": {"night": true, "glide": true, "perches": true, "skunkproof": true, "rare": 0.5},
	"feat": {"wing": 0.72, "facedisc": true, "hookbill": true, "eartuft": 0.10},
	"harv": {"feather": 2},
},
"turkey": {
	"nm": "Wild Turkey", "rig": "BIRD_GROUND", "arch": "SENTINEL",
	"len": 0.72, "hgt": 0.72, "hp": 45.0, "dmg": 5.0,
	"spd": [0.9, 7.4], "see": [24.0, 13.0],
	"col": Color(0.17, 0.14, 0.11), "col2": Color(0.42, 0.30, 0.15), "col3": Color(0.72, 0.18, 0.16),
	"sig": ["strut_drum", "scratch_line", "dust_bathe", "roost_flap", "gobble_back"],
	"call": {"idle": "turkey_gobble", "alarm": "turkey_gobble"},
	"zone": {"freeport_road": 1.0, "kennebec_seat": 0.9, "field": 0.9, "mill_reaches": 0.7,
		"beacon_coast": 0.6, "dawnwatch": 0.5},
	"flags": {"herd": 5, "roosts": true},
	"feat": {"fan": true, "wattle": true, "beard": true},
	"harv": {"meat": 2, "feather": 4},
},
"grouse": {
	"nm": "Ruffed Grouse", "rig": "BIRD_GROUND", "arch": "SKITTER",
	"len": 0.34, "hgt": 0.28, "hp": 18.0, "dmg": 0.0,
	"spd": [0.7, 8.6], "see": [9.0, 4.0],
	"col": Color(0.46, 0.36, 0.24), "col2": Color(0.80, 0.74, 0.62), "col3": Color(0.20, 0.16, 0.12),
	"sig": ["log_drum", "flush", "snow_dive", "ruff_up"],
	"call": {"idle": "grouse_drum", "alarm": ""},
	"zone": {"deep_woods": 1.0, "moosehead": 0.9, "western_peaks": 0.9, "county": 0.8,
		"katahdin": 0.6, "bangor_gate": 0.6, "freeport_road": 0.5},
	"flags": {"flush": true, "snowroost": true},
	"feat": {"crest": true, "fan": true, "ruff": 0.1},
	"harv": {"meat": 1, "feather": 2},
},
"spruce_grouse": {
	"nm": "Spruce Grouse", "rig": "BIRD_GROUND", "arch": "SKITTER",
	"len": 0.32, "hgt": 0.26, "hp": 16.0, "dmg": 0.0,
	"spd": [0.5, 5.0], "see": [5.0, 2.0],
	"col": Color(0.20, 0.19, 0.18), "col2": Color(0.88, 0.87, 0.84), "col3": Color(0.78, 0.14, 0.12),
	"sig": ["fool_hen", "ruff_up"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"county": 1.0, "katahdin": 0.8, "moosehead": 0.6},
	"flags": {"tame": true, "rare": 0.5},
	"feat": {"fan": true, "eyecomb": true},
	"harv": {"meat": 1, "feather": 2},
},
"woodcock": {
	"nm": "American Woodcock", "rig": "BIRD_GROUND", "arch": "SKITTER",
	"len": 0.26, "hgt": 0.16, "hp": 12.0, "dmg": 0.0,
	"spd": [0.5, 5.6], "see": [7.0, 3.0],
	"col": Color(0.48, 0.36, 0.22), "col2": Color(0.66, 0.52, 0.34), "col3": Color(0.24, 0.19, 0.14),
	"sig": ["bob_walk", "sky_dance", "peent"],
	"call": {"idle": "woodcock_peent", "alarm": "woodcock_twitter"},
	"zone": {"field": 0.9, "bog": 0.8, "freeport_road": 0.7, "river": 0.6},
	"flags": {"dusk": true, "spring_display": true, "migrate": [0.78, 0.06]},
	"feat": {"longbill": 0.09, "bigeye": true},
	"harv": {"meat": 1},
},
"raven": {
	"nm": "Common Raven", "rig": "BIRD_PERCH", "arch": "SCAVENGER",
	"len": 0.44, "hgt": 0.32, "hp": 28.0, "dmg": 5.0,
	"spd": [4.0, 13.0], "see": [44.0, 0.0],
	"col": Color(0.05, 0.05, 0.07), "col2": Color(0.12, 0.12, 0.16), "col3": Color(0.04, 0.04, 0.05),
	"sig": ["barrel_roll", "kraa", "corpse_circle", "lead_wolves"],
	"call": {"idle": "raven_kraa", "alarm": "raven_kraa"},
	"zone": {"katahdin": 1.0, "county": 0.9, "moosehead": 0.9, "western_peaks": 0.9,
		"deep_woods": 0.7, "bangor_gate": 0.6, "dawnwatch": 0.6},
	"flags": {"glide": true, "perches": true, "scav": true, "smart": true},
	"feat": {"wing": 0.60, "wedgetail": true, "shaggy": true, "heavybill": true},
	"harv": {"feather": 2},
},
"crow": {
	"nm": "American Crow", "rig": "BIRD_PERCH", "arch": "SENTINEL",
	"len": 0.34, "hgt": 0.26, "hp": 20.0, "dmg": 4.0,
	"spd": [4.0, 12.0], "see": [34.0, 0.0],
	"col": Color(0.07, 0.07, 0.08), "col2": Color(0.14, 0.14, 0.16), "col3": Color(0.05, 0.05, 0.06),
	"sig": ["mob", "sentry_post", "caw"],
	"call": {"idle": "crow_caw", "alarm": "crow_caw"},
	"zone": {"freeport_road": 1.0, "mill_reaches": 1.0, "kennebec_seat": 0.9, "beacon_coast": 0.9,
		"field": 0.9, "bangor_gate": 0.8},
	"flags": {"glide": true, "perches": true, "herd": 5, "mobs": true, "scav": true},
	"feat": {"wing": 0.48, "fantail": true},
	"harv": {"feather": 1},
},
"chickadee": {
	"nm": "Black-capped Chickadee", "rig": "BIRD_PERCH", "arch": "SENTINEL",
	"len": 0.13, "hgt": 0.09, "hp": 5.0, "dmg": 0.0,
	"spd": [3.0, 8.0], "see": [12.0, 0.0],
	"col": Color(0.56, 0.55, 0.52), "col2": Color(0.96, 0.95, 0.92), "col3": Color(0.08, 0.08, 0.09),
	"sig": ["hand_land", "dee_count", "flit", "seed_hammer"],
	"call": {"idle": "chickadee_song", "alarm": "chickadee_dee"},
	"zone": {"deep_woods": 1.0, "freeport_road": 1.0, "moosehead": 0.9, "western_peaks": 0.9,
		"county": 0.9, "kennebec_seat": 0.9, "mill_reaches": 0.8, "beacon_coast": 0.8,
		"bangor_gate": 0.8, "dawnwatch": 0.8, "katahdin": 0.7, "field": 0.8},
	"flags": {"glide": true, "perches": true, "herd": 4, "tame": true, "handfeed": true, "allyear": true},
	"feat": {"wing": 0.18, "cap": true, "bib": true},
	"harv": {},
},
"blue_jay": {
	"nm": "Blue Jay", "rig": "BIRD_PERCH", "arch": "SENTINEL",
	"len": 0.27, "hgt": 0.18, "hp": 12.0, "dmg": 2.0,
	"spd": [3.5, 10.0], "see": [22.0, 0.0],
	"col": Color(0.20, 0.36, 0.70), "col2": Color(0.94, 0.94, 0.96), "col3": Color(0.08, 0.08, 0.10),
	"sig": ["screech", "fake_hawk", "crest_raise", "flit"],
	"call": {"idle": "blue_jay_scream", "alarm": "blue_jay_scream"},
	"zone": {"freeport_road": 1.0, "kennebec_seat": 0.9, "deep_woods": 0.8, "mill_reaches": 0.8,
		"beacon_coast": 0.7, "bangor_gate": 0.7, "dawnwatch": 0.6},
	"flags": {"glide": true, "perches": true, "liar": true},
	"feat": {"wing": 0.34, "crest": true, "necklace": true, "barring": true},
	"harv": {"feather": 1},
},
"pileated": {
	"nm": "Pileated Woodpecker", "rig": "BIRD_PERCH", "arch": "SKITTER",
	"len": 0.44, "hgt": 0.30, "hp": 20.0, "dmg": 4.0,
	"spd": [3.5, 10.0], "see": [20.0, 11.0],
	"col": Color(0.09, 0.09, 0.10), "col2": Color(0.96, 0.95, 0.92), "col3": Color(0.82, 0.10, 0.08),
	"sig": ["cling", "excavate", "drum_roll", "laugh"],
	"call": {"idle": "pileated_call", "alarm": "pileated_drum"},
	"zone": {"deep_woods": 1.0, "moosehead": 0.8, "freeport_road": 0.6, "western_peaks": 0.7,
		"bangor_gate": 0.6, "dawnwatch": 0.5},
	"flags": {"glide": true, "clings": true, "excavates": true},
	"feat": {"wing": 0.42, "crest": true, "chisel": true, "stifftail": true},
	"harv": {"feather": 2},
},
"canada_jay": {
	"nm": "Canada Jay", "rig": "BIRD_PERCH", "arch": "RAIDER",
	"len": 0.26, "hgt": 0.17, "hp": 10.0, "dmg": 1.0,
	"spd": [3.0, 8.5], "see": [22.0, 0.0],
	"col": Color(0.56, 0.58, 0.60), "col2": Color(0.94, 0.94, 0.94), "col3": Color(0.22, 0.22, 0.24),
	"sig": ["camp_rob", "glide_in", "hand_land"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"county": 1.0, "katahdin": 0.9, "moosehead": 0.8},
	"flags": {"glide": true, "perches": true, "tame": true, "raids": true, "handfeed": true, "allyear": true},
	"feat": {"wing": 0.32, "cap": true, "fluffy": true},
	"harv": {"feather": 1},
},
"heron": {
	"nm": "Great Blue Heron", "rig": "BIRD_WATER", "arch": "SKITTER",
	"len": 0.90, "hgt": 1.10, "hp": 35.0, "dmg": 8.0,
	"spd": [0.6, 9.0], "see": [30.0, 16.0],
	"col": Color(0.44, 0.48, 0.54), "col2": Color(0.90, 0.90, 0.92), "col3": Color(0.86, 0.74, 0.24),
	"sig": ["statue_stalk", "spear_strike", "fish_gulp", "ptero_takeoff"],
	"call": {"idle": "heron_croak", "alarm": "heron_croak"},
	"zone": {"bog": 1.0, "river": 0.9, "lake": 0.8, "beacon_coast": 0.6},
	"flags": {"water": true, "wader": true, "migrate": [0.76, 0.12], "glide": true},
	"feat": {"longleg": 0.62, "longneck": 0.5, "daggerbill": true, "plume": true},
	"harv": {"feather": 3},
},
"goose": {
	"nm": "Canada Goose", "rig": "BIRD_WATER", "arch": "BLUFFER",
	"len": 0.75, "hgt": 0.62, "hp": 38.0, "dmg": 7.0,
	"spd": [0.8, 7.0], "see": [24.0, 10.0],
	"col": Color(0.35, 0.30, 0.22), "col2": Color(0.92, 0.91, 0.87), "col3": Color(0.06, 0.06, 0.07),
	"sig": ["hiss_charge", "skein", "honk", "grazing_line"],
	"call": {"idle": "goose_honk", "alarm": "goose_honk"},
	"zone": {"lake": 1.0, "river": 0.8, "field": 0.9, "bog": 0.7, "beacon_coast": 0.7, "kennebec_seat": 0.6},
	"flags": {"water": true, "herd": 6, "migrate": [0.86, 0.08], "skein": true},
	"feat": {"longneck": 0.36, "chinstrap": true, "flatbill": true},
	"harv": {"meat": 2, "feather": 3},
},
"wood_duck": {
	"nm": "Wood Duck", "rig": "BIRD_WATER", "arch": "SKITTER",
	"len": 0.42, "hgt": 0.28, "hp": 18.0, "dmg": 0.0,
	"spd": [0.9, 8.0], "see": [20.0, 11.0],
	"col": Color(0.10, 0.34, 0.30), "col2": Color(0.78, 0.52, 0.24), "col3": Color(0.92, 0.92, 0.90),
	"sig": ["duckling_leap", "paddle", "crest_slick"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"bog": 1.0, "river": 0.8, "lake": 0.7},
	"flags": {"water": true, "herd": 4, "beaverpond": true, "migrate": [0.80, 0.10]},
	"feat": {"crest": true, "flatbill": true, "iridescent": true},
	"harv": {"meat": 1, "feather": 2},
},
"gull": {
	"nm": "Herring Gull", "rig": "BIRD_WATER", "arch": "RAIDER",
	"len": 0.52, "hgt": 0.36, "hp": 20.0, "dmg": 4.0,
	"spd": [4.0, 12.0], "see": [30.0, 0.0],
	"col": Color(0.92, 0.92, 0.93), "col2": Color(0.56, 0.60, 0.64), "col3": Color(0.92, 0.78, 0.12),
	"sig": ["hand_steal", "piling_perch", "boat_wheel"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"beacon_coast": 1.0, "dawnwatch": 1.0, "gulf": 0.8, "mill_reaches": 0.3},
	"flags": {"glide": true, "herd": 6, "raids": true, "allyear": true},
	"feat": {"wing": 0.62, "flatbill": true, "wingtip": true},
	"harv": {"feather": 1},
},
"puffin": {
	"nm": "Atlantic Puffin", "rig": "BIRD_WATER", "arch": "SKITTER",
	"len": 0.28, "hgt": 0.22, "hp": 14.0, "dmg": 0.0,
	"spd": [1.0, 13.0], "see": [16.0, 9.0],
	"col": Color(0.07, 0.07, 0.09), "col2": Color(0.96, 0.96, 0.94), "col3": Color(0.92, 0.44, 0.10),
	"sig": ["whir_flight", "fish_mustache", "ledge_shuffle"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"gulf": 1.0},
	"flags": {"water": true, "colony": true, "island_only": true, "migrate": [0.72, 0.16], "herd": 8},
	"feat": {"clownbill": true, "shortwing": true, "upright": true},
	"harv": {"feather": 1},
},
"peregrine": {
	"nm": "Peregrine Falcon", "rig": "BIRD_RAPTOR", "arch": "STALKER",
	"len": 0.46, "hgt": 0.34, "hp": 34.0, "dmg": 12.0,
	"spd": [8.0, 26.0], "see": [50.0, 0.0],
	"col": Color(0.28, 0.30, 0.38), "col2": Color(0.90, 0.88, 0.84), "col3": Color(0.90, 0.74, 0.16),
	"sig": ["stoop", "cliff_ledge", "soar"],
	"call": {"idle": "eagle_cry", "alarm": "eagle_cry"},
	"zone": {"katahdin": 1.0, "dawnwatch": 0.8, "western_peaks": 0.5},
	"flags": {"glide": true, "cliff": true, "rare": 0.4, "soars": true},
	"feat": {"wing": 0.55, "hookbill": true, "malar": true, "pointedwing": true},
	"harv": {"feather": 2},
},
"snowy_owl": {
	"nm": "Snowy Owl", "rig": "BIRD_RAPTOR", "arch": "STALKER",
	"len": 0.58, "hgt": 0.50, "hp": 44.0, "dmg": 12.0,
	"spd": [4.0, 12.0], "see": [34.0, 0.0],
	"col": Color(0.95, 0.95, 0.96), "col2": Color(0.86, 0.86, 0.90), "col3": Color(0.92, 0.76, 0.14),
	"sig": ["ground_sit", "head_track", "silent_glide"],
	"call": {"idle": "snowy_owl_hoot", "alarm": "snowy_owl_hoot"},
	"zone": {"county": 1.0, "beacon_coast": 0.4, "field": 0.3},
	"flags": {"glide": true, "winter_only": true, "irruption": true, "rare": 0.35, "perches": true},
	"feat": {"wing": 0.78, "facedisc": true, "hookbill": true, "barring": true},
	"harv": {"feather": 3},
},
"vulture": {
	"nm": "Turkey Vulture", "rig": "BIRD_RAPTOR", "arch": "SCAVENGER",
	"len": 0.70, "hgt": 0.48, "hp": 30.0, "dmg": 3.0,
	"spd": [5.0, 11.0], "see": [56.0, 0.0],
	"col": Color(0.10, 0.09, 0.09), "col2": Color(0.24, 0.22, 0.21), "col3": Color(0.72, 0.24, 0.20),
	"sig": ["teeter_soar", "corpse_circle", "wing_dry"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"kennebec_seat": 0.9, "freeport_road": 0.8, "mill_reaches": 0.8, "field": 0.8, "western_peaks": 0.5},
	"flags": {"glide": true, "scav": true, "soars": true, "migrate": [0.84, 0.10]},
	"feat": {"wing": 0.98, "bareneck": true, "dihedral": true},
	"harv": {"feather": 2},
},

## ---------------------------------------------- TIER 4: water & coast ---

"harbor_seal": {
	"nm": "Harbor Seal", "rig": "CHUNK", "arch": "SKITTER",
	"len": 1.5, "hgt": 0.40, "hp": 80.0, "dmg": 6.0,
	"spd": [0.5, 6.0], "see": [20.0, 10.0],
	"col": Color(0.42, 0.42, 0.44), "col2": Color(0.72, 0.72, 0.70), "col3": Color(0.10, 0.10, 0.11),
	"sig": ["banana_pose", "spy_hop", "haul_out", "seal_follow"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"beacon_coast": 1.0, "dawnwatch": 1.0, "gulf": 0.7},
	"flags": {"water": true, "herd": 4, "nofight": true, "marine": true},
	"feat": {"flipper": true, "blubber": true, "spots": true},
	"harv": {"meat": 3, "hide": 2, "fat": 3},
},
"gray_seal": {
	"nm": "Gray Seal", "rig": "CHUNK", "arch": "SKITTER",
	"len": 2.1, "hgt": 0.50, "hp": 120.0, "dmg": 9.0,
	"spd": [0.5, 6.5], "see": [20.0, 10.0],
	"col": Color(0.34, 0.33, 0.32), "col2": Color(0.60, 0.60, 0.58), "col3": Color(0.12, 0.11, 0.11),
	"sig": ["banana_pose", "haul_out", "spy_hop"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"beacon_coast": 0.7, "dawnwatch": 0.9, "gulf": 0.8},
	"flags": {"water": true, "herd": 3, "nofight": true, "marine": true, "winter_bold": true},
	"feat": {"flipper": true, "blubber": true, "horseface": true},
	"harv": {"meat": 4, "hide": 2, "fat": 4},
},
"porpoise": {
	"nm": "Harbor Porpoise", "rig": "FISH", "arch": "AMBIENT",
	"len": 1.6, "hgt": 0.45, "hp": 70.0, "dmg": 0.0,
	"spd": [2.0, 8.0], "see": [0.0, 0.0],
	"col": Color(0.24, 0.26, 0.30), "col2": Color(0.88, 0.88, 0.88), "col3": Color(0.14, 0.15, 0.18),
	"sig": ["roll_arc"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"gulf": 1.0, "beacon_coast": 0.5, "dawnwatch": 0.6},
	"flags": {"water": true, "marine": true, "herd": 3, "nofight": true},
	"feat": {"dorsal": true, "fluke": true},
	"harv": {},
},
"whale": {
	"nm": "Whale", "rig": "FISH", "arch": "AMBIENT",
	"len": 11.0, "hgt": 2.4, "hp": 900.0, "dmg": 0.0,
	"spd": [1.5, 5.0], "see": [0.0, 0.0],
	"col": Color(0.16, 0.17, 0.20), "col2": Color(0.72, 0.73, 0.72), "col3": Color(0.10, 0.11, 0.13),
	"sig": ["blow_spout", "breach", "fluke_dive"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"gulf": 1.0},
	"flags": {"water": true, "marine": true, "far_only": true, "nofight": true, "rare": 0.3},
	"feat": {"fluke": true, "pleats": true, "flipper": true},
	"harv": {},
},
"snapper": {
	"nm": "Snapping Turtle", "rig": "HERP", "arch": "BLUFFER",
	"len": 0.50, "hgt": 0.24, "hp": 90.0, "dmg": 16.0,
	"spd": [0.35, 1.5], "see": [8.0, 3.0],
	"col": Color(0.20, 0.20, 0.16), "col2": Color(0.38, 0.36, 0.28), "col3": Color(0.30, 0.34, 0.22),
	"sig": ["silt_ambush", "lunge_latch", "road_hiss", "shell_tuck"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"bog": 1.0, "river": 0.7, "lake": 0.7},
	"flags": {"water": true, "latch": true, "slow": true, "ambush": true},
	"feat": {"shell": true, "ridged": true, "sawtail": true, "hookjaw": true},
	"harv": {"meat": 2, "shell": 1},
},
"painted_turtle": {
	"nm": "Painted Turtle", "rig": "HERP", "arch": "SKITTER",
	"len": 0.18, "hgt": 0.09, "hp": 20.0, "dmg": 0.0,
	"spd": [0.25, 1.1], "see": [10.0, 6.0],
	"col": Color(0.12, 0.16, 0.13), "col2": Color(0.86, 0.42, 0.10), "col3": Color(0.90, 0.70, 0.14),
	"sig": ["bask", "log_plop"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"bog": 1.0, "lake": 0.8, "river": 0.7},
	"flags": {"water": true, "herd": 5, "basks": true, "nofight": true},
	"feat": {"shell": true, "smoothshell": true, "stripes": true},
	"harv": {},
},
"trout": {
	"nm": "Brook Trout", "rig": "FISH", "arch": "AMBIENT",
	"len": 0.28, "hgt": 0.10, "hp": 8.0, "dmg": 0.0,
	"spd": [1.0, 6.0], "see": [0.0, 0.0],
	"col": Color(0.22, 0.30, 0.24), "col2": Color(0.86, 0.52, 0.24), "col3": Color(0.90, 0.30, 0.18),
	"sig": ["rise_ring", "falls_leap", "hold_current"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"river": 1.0, "lake": 0.7, "western_peaks": 0.8, "moosehead": 0.7},
	"flags": {"water": true, "herd": 4, "nofight": true},
	"feat": {"dorsal": true, "spots": true, "forkedtail": false},
	"harv": {"fish": 1},
},
"salmon": {
	"nm": "Landlocked Salmon", "rig": "FISH", "arch": "AMBIENT",
	"len": 0.52, "hgt": 0.16, "hp": 14.0, "dmg": 0.0,
	"spd": [1.2, 8.0], "see": [0.0, 0.0],
	"col": Color(0.52, 0.56, 0.60), "col2": Color(0.92, 0.92, 0.90), "col3": Color(0.20, 0.22, 0.26),
	"sig": ["falls_leap", "hold_current", "rise_ring"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"lake": 1.0, "moosehead": 0.9, "river": 0.7},
	"flags": {"water": true, "herd": 3, "nofight": true},
	"feat": {"dorsal": true, "forkedtail": true, "spots": true},
	"harv": {"fish": 2},
},
"tidepool": {
	"nm": "Tidepool Life", "rig": "SWARM", "arch": "AMBIENT",
	"len": 0.12, "hgt": 0.05, "hp": 3.0, "dmg": 0.0,
	"spd": [0.2, 0.6], "see": [0.0, 0.0],
	"col": Color(0.30, 0.44, 0.26), "col2": Color(0.78, 0.34, 0.22), "col3": Color(0.42, 0.30, 0.44),
	"sig": ["scuttle", "cling"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"beacon_coast": 1.0, "dawnwatch": 1.0},
	"flags": {"tide_only": true, "swarm": 9, "forage": true, "nofight": true},
	"feat": {"shelled": true},
	"harv": {"crab": 1, "urchin": 1},
},

## -------------------------------------- TIER 5: herps, bugs, ambience ---

"garter_snake": {
	"nm": "Garter Snake", "rig": "HERP", "arch": "SKITTER",
	"len": 0.55, "hgt": 0.05, "hp": 8.0, "dmg": 0.0,
	"spd": [0.6, 3.2], "see": [8.0, 4.0],
	"col": Color(0.18, 0.22, 0.14), "col2": Color(0.80, 0.82, 0.44), "col3": Color(0.10, 0.11, 0.09),
	"sig": ["ribbon_flee", "sun_coil"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"field": 1.0, "freeport_road": 0.8, "kennebec_seat": 0.7, "mill_reaches": 0.6, "dawnwatch": 0.5},
	"flags": {"serpent": true, "nofight": true, "basks": true},
	"feat": {"stripes": true, "noleg": true},
	"harv": {},
},
"peeper": {
	"nm": "Spring Peeper", "rig": "SWARM", "arch": "AMBIENT",
	"len": 0.03, "hgt": 0.02, "hp": 1.0, "dmg": 0.0,
	"spd": [0.3, 1.4], "see": [0.0, 0.0],
	"col": Color(0.62, 0.52, 0.34), "col2": Color(0.78, 0.70, 0.50), "col3": Color(0.30, 0.26, 0.18),
	"sig": ["chorus_hole"],
	"call": {"idle": "peepers", "alarm": ""},
	"zone": {"bog": 1.0, "river": 0.8, "field": 0.6, "lake": 0.7},
	"flags": {"spring_only": true, "audio_only": true, "chorus": true, "night": true},
	"feat": {},
	"harv": {},
},
"bullfrog": {
	"nm": "Bullfrog", "rig": "HERP", "arch": "SKITTER",
	"len": 0.16, "hgt": 0.09, "hp": 8.0, "dmg": 0.0,
	"spd": [0.4, 3.0], "see": [7.0, 3.5],
	"col": Color(0.26, 0.36, 0.20), "col2": Color(0.84, 0.86, 0.70), "col3": Color(0.16, 0.20, 0.14),
	"sig": ["jug_o_rum", "leap_splash"],
	"call": {"idle": "bullfrog", "alarm": ""},
	"zone": {"bog": 1.0, "lake": 0.8, "river": 0.7},
	"flags": {"water": true, "hop": true, "nofight": true},
	"feat": {"eardrum": true, "frog": true},
	"harv": {},
},
"wood_frog": {
	"nm": "Wood Frog", "rig": "HERP", "arch": "SKITTER",
	"len": 0.06, "hgt": 0.03, "hp": 3.0, "dmg": 0.0,
	"spd": [0.4, 2.6], "see": [5.0, 2.5],
	"col": Color(0.50, 0.34, 0.22), "col2": Color(0.80, 0.72, 0.58), "col3": Color(0.14, 0.11, 0.09),
	"sig": ["leap_splash", "freeze_solid"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"deep_woods": 0.9, "bog": 1.0, "moosehead": 0.7, "county": 0.6},
	"flags": {"hop": true, "nofight": true, "freezes": true, "spring_peak": true},
	"feat": {"frog": true, "robbermask": true},
	"harv": {},
},
"red_eft": {
	"nm": "Red Eft", "rig": "HERP", "arch": "SKITTER",
	"len": 0.08, "hgt": 0.02, "hp": 2.0, "dmg": 0.0,
	"spd": [0.2, 0.7], "see": [4.0, 2.0],
	"col": Color(0.92, 0.36, 0.08), "col2": Color(0.98, 0.60, 0.22), "col3": Color(0.60, 0.10, 0.06),
	"sig": ["amble"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"deep_woods": 1.0, "moosehead": 0.7, "western_peaks": 0.7},
	"flags": {"rain_only": true, "nofight": true, "slow": true},
	"feat": {"noleg": false, "salamander": true},
	"harv": {},
},
"firefly": {
	"nm": "Firefly", "rig": "SWARM", "arch": "AMBIENT",
	"len": 0.015, "hgt": 0.01, "hp": 1.0, "dmg": 0.0,
	"spd": [0.6, 1.6], "see": [0.0, 0.0],
	"col": Color(0.90, 1.00, 0.42), "col2": Color(0.60, 0.80, 0.24), "col3": Color(0.20, 0.24, 0.10),
	"sig": ["twinkle_drift"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"field": 1.0, "freeport_road": 0.8, "bog": 0.7, "river": 0.6, "kennebec_seat": 0.6},
	"flags": {"night": true, "summer_only": true, "swarm": 40, "glows": true, "glide": true},
	"feat": {},
	"harv": {},
},
"dragonfly": {
	"nm": "Dragonfly", "rig": "SWARM", "arch": "AMBIENT",
	"len": 0.07, "hgt": 0.02, "hp": 1.0, "dmg": 0.0,
	"spd": [2.0, 7.0], "see": [0.0, 0.0],
	"col": Color(0.16, 0.52, 0.60), "col2": Color(0.70, 0.86, 0.88), "col3": Color(0.10, 0.20, 0.24),
	"sig": ["hover_dart"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"bog": 1.0, "lake": 0.8, "river": 0.8, "field": 0.5},
	"flags": {"summer_only": true, "swarm": 8, "glide": true},
	"feat": {"wing": 0.05},
	"harv": {},
},
"monarch": {
	"nm": "Monarch", "rig": "SWARM", "arch": "AMBIENT",
	"len": 0.05, "hgt": 0.02, "hp": 1.0, "dmg": 0.0,
	"spd": [0.8, 3.0], "see": [0.0, 0.0],
	"col": Color(0.92, 0.46, 0.06), "col2": Color(0.10, 0.09, 0.08), "col3": Color(0.98, 0.98, 0.94),
	"sig": ["south_drift"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"field": 1.0, "freeport_road": 0.7, "kennebec_seat": 0.6, "beacon_coast": 0.6},
	"flags": {"swarm": 6, "glide": true, "migrate_drift": true, "autumn_only": true},
	"feat": {"wing": 0.05},
	"harv": {},
},
"blackfly": {
	"nm": "Blackflies", "rig": "SWARM", "arch": "AMBIENT",
	"len": 0.008, "hgt": 0.006, "hp": 1.0, "dmg": 0.4,
	"spd": [1.0, 3.0], "see": [0.0, 0.0],
	"col": Color(0.10, 0.10, 0.11), "col2": Color(0.18, 0.18, 0.20), "col3": Color(0.06, 0.06, 0.07),
	"sig": ["harass_cloud"],
	"call": {"idle": "blackflies", "alarm": ""},
	"zone": {"bog": 1.0, "moosehead": 0.9, "county": 0.9, "river": 0.7, "deep_woods": 0.6},
	## `swattable` is the only one. A swing kills blackflies; it scatters
	## fireflies and moths and leaves them alive, because an axe that murders
	## the prettiest thing in the game for walking near it is a punishment, not
	## a mechanic.
	"flags": {"swarm": 60, "glide": true, "late_spring": true, "harasses": true,
		"smoke_repels": true, "swattable": true},
	"feat": {},
	"harv": {},
},
"luna_moth": {
	"nm": "Luna Moth", "rig": "SWARM", "arch": "AMBIENT",
	"len": 0.11, "hgt": 0.03, "hp": 1.0, "dmg": 0.0,
	"spd": [0.5, 2.2], "see": [0.0, 0.0],
	"col": Color(0.62, 0.92, 0.58), "col2": Color(0.86, 0.98, 0.80), "col3": Color(0.50, 0.30, 0.16),
	"sig": ["lantern_arrive"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"deep_woods": 1.0, "freeport_road": 0.6, "moosehead": 0.6},
	"flags": {"night": true, "summer_only": true, "swarm": 1, "lightseek": true, "glide": true},
	"feat": {"wing": 0.10, "tails": true},
	"harv": {},
},
"cricket": {
	"nm": "Crickets", "rig": "SWARM", "arch": "AMBIENT",
	"len": 0.02, "hgt": 0.01, "hp": 1.0, "dmg": 0.0,
	"spd": [0.2, 1.0], "see": [0.0, 0.0],
	"col": Color(0.18, 0.16, 0.12), "col2": Color(0.28, 0.25, 0.19), "col3": Color(0.10, 0.09, 0.07),
	"sig": ["chorus_hole"],
	"call": {"idle": "crickets", "alarm": ""},
	"zone": {"field": 1.0, "freeport_road": 0.8, "kennebec_seat": 0.7, "mill_reaches": 0.6},
	"flags": {"night": true, "audio_only": true, "chorus": true, "summer_only": true},
	"feat": {},
	"harv": {},
},

## ------------------------------------------------------------ LEGENDS ---
## Hand-placed only. Never rolled from a spawn table — WildlifeDirector
## refuses to scatter anything flagged `legend`.

"specter_moose": {
	"nm": "The Specter Moose", "rig": "CERVID", "arch": "BLUFFER",
	"len": 4.2, "hgt": 3.1, "hp": 1200.0, "dmg": 60.0,
	"spd": [1.0, 9.0], "see": [40.0, 14.0],
	"col": Color(0.86, 0.87, 0.90), "col2": Color(0.94, 0.95, 0.97), "col3": Color(0.70, 0.74, 0.82),
	"sig": ["moose_dunk", "antler_thrash", "specter_fade", "hackles"],
	"call": {"idle": "moose_bellow", "alarm": "moose_bellow"},
	"zone": {"moosehead": 1.0},
	"flags": {"legend": true, "fog_only": true, "glows": true, "dusk": true},
	"feat": {"antler": 2.4, "dewlap": true, "hump": 0.40, "muzzle": 1.6},
	"harv": {"meat": 12, "hide": 4, "antler": 2, "relic": 1},
},
"ghost_cat": {
	"nm": "The Ghost Cat", "rig": "FELID", "arch": "STALKER",
	"len": 1.5, "hgt": 0.80, "hp": 400.0, "dmg": 0.0,
	"spd": [1.6, 13.0], "see": [60.0, 0.0],
	"col": Color(0.62, 0.54, 0.42), "col2": Color(0.86, 0.82, 0.74), "col3": Color(0.14, 0.12, 0.10),
	"sig": ["silent_stalk", "corner_of_eye", "one_scream", "track_leave"],
	"call": {"idle": "lynx_caterwaul", "alarm": "lynx_caterwaul"},
	"zone": {"western_peaks": 0.6, "moosehead": 0.6, "county": 0.5, "katahdin": 0.5},
	"flags": {"legend": true, "nofight": true, "never_seen": true, "night": true, "stalks_player": true},
	"feat": {"longtail": 1.0, "bigpaw": 1.3, "ruff": 0.0},
	"harv": {},
},
"aurora_herd": {
	"nm": "The Aurora Herd", "rig": "CERVID", "arch": "AMBIENT",
	"len": 1.9, "hgt": 1.3, "hp": 1.0, "dmg": 0.0,
	"spd": [2.2, 6.0], "see": [0.0, 0.0],
	"col": Color(0.42, 0.86, 0.78), "col2": Color(0.70, 0.96, 0.92), "col3": Color(0.30, 0.70, 0.90),
	"sig": ["spectral_cross", "specter_fade"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"county": 1.0},
	"flags": {"legend": true, "aurora_only": true, "glows": true, "noclip": true, "nofight": true, "herd": 9},
	"feat": {"antler": 1.1, "muzzle": 1.1, "palmate": true, "hump": 0.1},
	"harv": {},
},
"king_snapper": {
	"nm": "The King Snapper", "rig": "HERP", "arch": "BLUFFER",
	"len": 1.3, "hgt": 0.60, "hp": 700.0, "dmg": 42.0,
	"spd": [0.3, 2.2], "see": [14.0, 5.0],
	"col": Color(0.14, 0.17, 0.12), "col2": Color(0.30, 0.34, 0.22), "col3": Color(0.24, 0.32, 0.18),
	"sig": ["silt_ambush", "lunge_latch", "shell_tuck", "road_hiss"],
	"call": {"idle": "", "alarm": ""},
	"zone": {"bog": 1.0},
	"flags": {"legend": true, "water": true, "latch": true, "ambush": true, "mossy": true},
	"feat": {"shell": true, "ridged": true, "sawtail": true, "hookjaw": true, "moss": true},
	"harv": {"meat": 8, "shell": 1, "relic": 1},
},
"white_raven": {
	"nm": "The White Raven", "rig": "BIRD_PERCH", "arch": "SCAVENGER",
	"len": 0.46, "hgt": 0.34, "hp": 100.0, "dmg": 0.0,
	"spd": [4.5, 14.0], "see": [70.0, 0.0],
	"col": Color(0.97, 0.97, 0.98), "col2": Color(0.88, 0.90, 0.94), "col3": Color(0.80, 0.82, 0.88),
	"sig": ["barrel_roll", "kraa", "omen_perch", "corpse_circle"],
	"call": {"idle": "raven_kraa", "alarm": "raven_kraa"},
	"zone": {"katahdin": 1.0},
	"flags": {"legend": true, "glide": true, "perches": true, "nofight": true, "omen": true, "glows": true},
	"feat": {"wing": 0.62, "wedgetail": true, "shaggy": true, "heavybill": true},
	"harv": {},
},
}


## ============================== Lookups ===================================


static func get_profile(key: String) -> Dictionary:
	return DEX.get(key, {}) as Dictionary


static func has(key: String) -> bool:
	return DEX.has(key)


static func keys() -> Array:
	return DEX.keys()


static func flag(key: String, f: String, dflt = false):
	var p := get_profile(key)
	if p.is_empty():
		return dflt
	return (p.get("flags", {}) as Dictionary).get(f, dflt)


static func feat(key: String, f: String, dflt = false):
	var p := get_profile(key)
	if p.is_empty():
		return dflt
	return (p.get("feat", {}) as Dictionary).get(f, dflt)


static func in_zone(key: String, zone: String) -> float:
	var p := get_profile(key)
	if p.is_empty():
		return 0.0
	return float((p.get("zone", {}) as Dictionary).get(zone, 0.0))


static func species_for_zone(zone: String) -> Array:
	## Every species that can appear here, with its weight, heaviest first.
	## WildlifeDirector rolls against this; legends are excluded on purpose —
	## they are placed by hand, never scattered.
	var out: Array = []
	for k in DEX.keys():
		if flag(k, "legend", false):
			continue
		var w := in_zone(k, zone)
		if w > 0.0:
			out.append({"key": k, "w": w})
	out.sort_custom(func(a, b): return float(a["w"]) > float(b["w"]))
	return out


static func legends() -> Array:
	var out: Array = []
	for k in DEX.keys():
		if flag(k, "legend", false):
			out.append(k)
	return out


static func rig_of(key: String) -> String:
	return String(get_profile(key).get("rig", "CHUNK"))


static func arch_of(key: String) -> String:
	return String(get_profile(key).get("arch", "SKITTER"))


static func is_awake(key: String, hour: float, phase: float) -> bool:
	## Time-of-day and season gate, in one place so the spawner and the
	## already-spawned critters can never disagree about whether a thing
	## should be out right now.
	var night := hour >= 20.6 or hour < 6.0
	var dusk := (hour >= 18.6 and hour < 21.2) or (hour >= 4.6 and hour < 7.4)
	if flag(key, "night", false) and not (night or dusk):
		return false
	if flag(key, "dusk", false) and not (dusk or night):
		## Crepuscular things still exist by day, just quieter — they are awake
		## but they will not be *spawned* fresh. Handled by the director.
		pass
	var season := season_of(phase)
	if flag(key, "den", false) and season == WINTER:
		return false
	if flag(key, "winter_only", false) and season != WINTER:
		return false
	if flag(key, "summer_only", false) and season != SUMMER:
		return false
	if flag(key, "spring_only", false) and season != SPRING:
		return false
	if flag(key, "autumn_only", false) and season != AUTUMN:
		return false
	var mig = flag(key, "migrate", null)
	if mig != null and mig is Array and (mig as Array).size() == 2:
		var leave := float(mig[0])
		var back := float(mig[1])
		var p := fposmod(phase, 1.0)
		## The window wraps midwinter: gone from `leave` until `back`.
		if leave > back:
			if p >= leave or p < back:
				return false
		elif p >= leave and p < back:
			return false
	return true


static func count() -> int:
	return DEX.size()
