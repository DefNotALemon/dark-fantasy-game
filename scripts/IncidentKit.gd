class_name IncidentKit
extends RefCounted

## ===========================================================================
## THE INCIDENT KIT — the props cupboard behind the Chronicle.
##
## The Chronicle knows that wolves got into the fold at Sebec at two in the
## morning. It knows it whether or not anyone was within eighty kilometres of
## Sebec, and it will still know it a week later when the rumour reaches the
## coast. What it will not do — deliberately, see its file-top — is put a
## single object on the ground. It has no scene. It never will.
##
## This file is the other half of that bargain. For every one of the thirty-
## four kinds in ChronicleEvents it holds a RECIPE: what is physically there
## while the thing is still happening, what is left behind afterwards for each
## separate way it can end, what it sounds like from a field away, and one
## plain line of prose for the moment the player walks into earshot.
##
## Two things this file is fanatical about.
##
##   1. **The aftermath tells the outcomes apart.** A fold that HELD is churned
##      mud and a great many wolf tracks. A fold that lost ewes is a torn
##      hurdle, blood, fleece caught in the hedge and crows. A fold where the
##      shepherd's boy got bitten adds his dropped stick, a blood trail, and the
##      two parallel scars of a hurdle dragged out with a man on it. Nobody is
##      ever told which happened. A player who has learned to read a fold can
##      stand there and know.
##
##   2. **It is pure.** Const data and static functions: no tree, no timers, no
##      randomness of its own. `build_prop(spec, index, unit)` is a function of
##      its three arguments and nothing else, so the Incident Director can hand
##      it a hash of (world_seed, uid, salt) and get byte-identical geometry
##      back on the tenth visit that it got on the first. That is what makes
##      walking away and coming back honest, and it is why there is not one
##      `randf()` in here.
##
## The props are built from boxes, cylinders, spheres and quads, and they are
## meant to be. Myrkfell is flat-shaded and low-poly by choice; four boxes that
## read as a broken hurdle from fifteen metres in bad light is the correct
## answer, and a modelled hurdle would be the wrong one twice over — slower,
## and less like the rest of the world.
##
## Read by IncidentDirector.gd, which owns the placement, the earshot and the
## record-keeping. This file owns the taste.
## ===========================================================================


## The whole vocabulary. If a recipe names something that is not in here,
## `problems()` says so rather than quietly staging nothing.
##
## Every one of these is built out of boxes, cylinders, spheres and quads by a
## `_b_*` below — except "critter", which is a live animal. The Incident
## Director hands that one to the WildlifeDirector and never asks this file for
## geometry, because the crows that are still ON the field are a different
## thing from the feathers they dropped, and a box bird next to a real one is
## worse than no bird at all.
const PROP_KINDS: Array[String] = [
	"post", "plank", "log", "hurdle", "crate", "barrel", "cart", "cloth", "stone",
	"ash", "char", "blood", "bone", "fleece", "basket", "net", "float",
	"torch", "cairn", "track", "scat", "feather", "critter",
]

## And the arg each one will answer to. Until this table existed `problems()`
## checked the prop KIND and never the arg, and four recipes went a whole
## release staging `track: "wolf"`, `scat: "wolf"`, `scat: "fox"` and
## `feather: "raven"` — none of which had a builder branch, all of which came
## out byte-identical to the default, and the most load-bearing of which was
## the fourteen wolf prints that are the entire aftermath of a fold that held.
## An empty string means "no arg", and every list below carries it unless the
## prop is meaningless without one.
const PROP_ARGS: Dictionary = {
	"post": ["", "burnt", "cut", "snapped"],
	"plank": ["", "split", "charred", "stick"],
	"log": ["", "charred"],
	"hurdle": ["", "broken"],
	"crate": ["", "spilled"],
	"barrel": ["", "sealed", "stove"],
	"cart": ["", "tipped"],
	"cloth": ["", "sack", "linen", "pilgrim", "sail"],
	"stone": ["", "burnt"],
	"ash": [""],
	"char": [""],
	"blood": ["", "trail"],
	"bone": ["", "man", "big", "ox", "deer", "sheep", "wolf", "dog"],
	"fleece": [""],
	"basket": ["", "spilled"],
	"net": ["", "snare", "rope", "torn"],
	"float": [""],
	"torch": ["", "lit", "guttered"],
	"cairn": [""],
	"track": ["", "boot", "small", "bear", "moose", "hoof", "deer", "cow",
		"horse", "dog", "fox", "wolf", "drag", "cart"],
	"scat": ["", "bear", "moose", "cow", "horse", "deer", "small", "wolf", "fox"],
	"feather": ["", "crow", "raven", "goose", "gull"],
	## The WildlifeDirector owns the real species table; this is only the short
	## list this catalogue actually asks for, so a typo still gets caught.
	"critter": ["crow", "deer"],
}

## Everything on the ground is one of about a dozen colours. Keeping them in
## one place is what stops a charred post in a burnt byre being a different
## black from the charred post beside it.
const PALETTE: Dictionary = {
	"wood": Color(0.31, 0.24, 0.16),
	"wood_pale": Color(0.56, 0.46, 0.32),
	"char": Color(0.085, 0.078, 0.075),
	"ash": Color(0.61, 0.59, 0.56),
	"blood": Color(0.235, 0.055, 0.045),
	"blood_old": Color(0.16, 0.07, 0.06),
	"bone": Color(0.82, 0.79, 0.70),
	"fleece": Color(0.87, 0.85, 0.79),
	"sack": Color(0.47, 0.41, 0.30),
	"linen": Color(0.78, 0.76, 0.70),
	"pilgrim": Color(0.30, 0.27, 0.35),
	"sail": Color(0.71, 0.68, 0.59),
	"stone": Color(0.43, 0.43, 0.41),
	"rope": Color(0.50, 0.44, 0.31),
	"iron": Color(0.23, 0.23, 0.25),
	"earth": Color(0.22, 0.175, 0.13),
	"scat": Color(0.17, 0.13, 0.095),
	"flame": Color(0.92, 0.56, 0.18),
	"cork": Color(0.69, 0.55, 0.30),
	"crow": Color(0.065, 0.065, 0.085),
	## A raven is not a big crow. It is bluer, colder and reads darker against
	## wet ground, and on a field where both could be it is the difference.
	"raven": Color(0.045, 0.045, 0.065),
	"gull": Color(0.80, 0.79, 0.76),
	"goose": Color(0.72, 0.68, 0.60),
}

## How high a ground decal floats. Enough to beat z-fighting on the terrain,
## little enough that nothing looks like it is hovering.
const DECAL_Y := 0.02


## ============================== The recipes ===============================
##
## recipe = {
##   "id":     String,     ## exactly a ChronicleEvents kind id
##   "stage":  String,     ## place | road | wild | shore — where the anchor
##                         ## lands. "shore" is a refinement of "place": the
##                         ## Director walks out from the place until it finds
##                         ## water and backs off six metres, so a wreck lands
##                         ## on the waterline instead of in a turnip field.
##   "live":   Array,      ## prop specs staged while the event is ACTIVE
##   "after":  Dictionary, ## outcome_id -> Array of prop specs
##   "hear":   String,     ## Telegraph source name
##   "threat": int,        ## Telegraph.Threat 0..3, or -1 for a silent incident
##   "threat_after": int,  ## OPTIONAL. what the AFTERMATH is worth ringing at.
##                         ## Absent means mini(threat, 1), which is the honest
##                         ## default: a fire is a 3 while it is burning and a
##                         ## patch of cold char three days later, and ringing
##                         ## PANIC over cold char taught players to ignore the
##                         ## Telegraph. Set it only where the aftermath is
##                         ## genuinely still dangerous (a goblin raid, a field
##                         ## the ravens have not left) or genuinely silent.
##   "note":   String,     ## one line at earshot; one "%s" for the place
##   "linger": float,      ## game-days the aftermath is worth staging
## }
## prop spec = {"kind": String, "n": int, "spread": float, "arg": String,
##              "y": float, "layout": String}
##
## `layout` is "" for the default scatter — the Director drops the copies on a
## disc around the anchor — or "line", which lays them along one bearing with
## a single shared yaw. A fold is a fence and a set line of floats is a set
## line of floats; both of them read as a heap on a disc and as themselves on
## a line.
##
## Counts and spreads are the difference between a scene and a heap. A `spread`
## of 3 is one torn gate; a spread of 12 is a hillside. Where an aftermath needs
## to be read at a glance, the telling prop goes in with a small spread so it
## lands where the eye already is.

const RECIPES: Array = [

	## ------------------------------------------------------------ wolves ---
	{
		"id": "wolves_at_fold",
		"stage": "place",
		"hear": "dogs",
		"threat": 2,
		"linger": 2.0,
		"note": "Dogs up at %s and not stopping, the flat hard barking they keep for wolves.",
		"live": [
			{"kind": "hurdle", "n": 3, "spread": 3.2, "layout": "line"},
			{"kind": "post", "n": 2, "spread": 3.5},
			{"kind": "torch", "n": 1, "spread": 4.0, "arg": "lit"},
			{"kind": "track", "n": 6, "spread": 5.0, "arg": "wolf"},
		],
		"after": {
			## Held: nothing lost, and the whole night written into the mud.
			"held": [
				{"kind": "track", "n": 14, "spread": 6.0, "arg": "wolf"},
				{"kind": "hurdle", "n": 3, "spread": 3.2, "layout": "line"},
				{"kind": "scat", "n": 2, "spread": 5.0, "arg": "wolf"},
				{"kind": "torch", "n": 1, "spread": 4.0, "arg": "guttered"},
			],
			## Three ewes torn open: the hurdle is through, and the hedge kept
			## the wool. Crows are the part that carries furthest.
			"ewes_lost": [
				{"kind": "hurdle", "n": 2, "spread": 3.0, "arg": "broken", "layout": "line"},
				{"kind": "plank", "n": 4, "spread": 3.5, "arg": "split"},
				{"kind": "blood", "n": 3, "spread": 3.0},
				{"kind": "fleece", "n": 5, "spread": 5.0, "y": 0.35},
				{"kind": "bone", "n": 2, "spread": 4.0, "arg": "sheep"},
				{"kind": "feather", "n": 6, "spread": 5.0, "arg": "crow"},
				{"kind": "critter", "n": 3, "spread": 7.0, "arg": "crow"},
				{"kind": "track", "n": 8, "spread": 5.0, "arg": "wolf"},
			],
			## A boy went out with a stick. The stick is still there, and so is
			## the pair of grooves they took him out on.
			"shepherd_bitten": [
				{"kind": "hurdle", "n": 2, "spread": 3.0, "arg": "broken", "layout": "line"},
				{"kind": "blood", "n": 4, "spread": 4.0, "arg": "trail"},
				{"kind": "plank", "n": 1, "spread": 1.5, "arg": "stick"},
				{"kind": "track", "n": 2, "spread": 3.0, "arg": "drag"},
				{"kind": "cloth", "n": 1, "spread": 2.5, "arg": "linen"},
				{"kind": "fleece", "n": 2, "spread": 4.0, "y": 0.3},
				{"kind": "track", "n": 6, "spread": 5.0, "arg": "boot"},
			],
		},
	},

	{
		"id": "wolf_hunt",
		"stage": "wild",
		"hear": "horn",
		"threat": 1,
		"linger": 1.5,
		"note": "A horn on the hill above %s, and men calling to each other across the ground.",
		"live": [
			{"kind": "track", "n": 8, "spread": 6.0, "arg": "boot"},
			{"kind": "torch", "n": 1, "spread": 3.0, "arg": "lit"},
			{"kind": "cloth", "n": 1, "spread": 4.0, "arg": "sack"},
		],
		"after": {
			"pelt": [
				{"kind": "ash", "n": 1, "spread": 1.5},
				{"kind": "blood", "n": 2, "spread": 2.0},
				{"kind": "bone", "n": 3, "spread": 2.5, "arg": "wolf"},
				{"kind": "track", "n": 10, "spread": 6.0, "arg": "boot"},
				{"kind": "feather", "n": 4, "spread": 4.0, "arg": "crow"},
			],
			## Two days of walking and nothing to show: boots everywhere, a
			## cold fire, and not one print that is not a man's.
			"empty": [
				{"kind": "track", "n": 12, "spread": 9.0, "arg": "boot"},
				{"kind": "ash", "n": 1, "spread": 2.0},
				{"kind": "cloth", "n": 1, "spread": 4.0, "arg": "sack"},
			],
			"hound_lost": [
				{"kind": "blood", "n": 3, "spread": 5.0, "arg": "trail"},
				{"kind": "bone", "n": 2, "spread": 3.0, "arg": "dog"},
				{"kind": "track", "n": 10, "spread": 6.0, "arg": "wolf"},
				{"kind": "track", "n": 6, "spread": 5.0, "arg": "boot"},
				{"kind": "cairn", "n": 1, "spread": 2.5},
			],
		},
	},

	{
		"id": "deer_yard",
		"stage": "wild",
		"hear": "deer",
		"threat": 0,
		"linger": 1.0,
		"note": "The cedar swamp below %s is packed with deer, standing close and watching.",
		"live": [
			{"kind": "track", "n": 12, "spread": 10.0, "arg": "hoof"},
			{"kind": "scat", "n": 6, "spread": 8.0, "arg": "deer"},
			## The note promises a hundred deer standing there looking back. A
			## farmyard hurdle in the middle of a cedar swamp was never going to
			## be the thing that carried that, and the deer themselves are.
			{"kind": "critter", "n": 6, "spread": 16.0, "arg": "deer"},
		],
		"after": {
			"yarded": [
				{"kind": "track", "n": 16, "spread": 12.0, "arg": "hoof"},
				{"kind": "scat", "n": 8, "spread": 10.0, "arg": "deer"},
				{"kind": "critter", "n": 4, "spread": 18.0, "arg": "deer"},
			],
			## Ribs like a hurdle. They came in for the hay off the racks and
			## some of them did not go back out.
			"starving": [
				{"kind": "track", "n": 14, "spread": 9.0, "arg": "hoof"},
				{"kind": "bone", "n": 3, "spread": 6.0, "arg": "deer"},
				## Cedar browsed off flat at exactly a deer's reach and not one
				## green twig under it. A woodsman reads a starving yard off that
				## line and off nothing else.
				{"kind": "post", "n": 5, "spread": 7.0, "arg": "cut"},
				{"kind": "basket", "n": 1, "spread": 3.0, "arg": "spilled"},
				{"kind": "feather", "n": 4, "spread": 6.0, "arg": "crow"},
			],
			"wolves_follow": [
				{"kind": "track", "n": 10, "spread": 9.0, "arg": "hoof"},
				{"kind": "track", "n": 8, "spread": 10.0, "arg": "wolf"},
				{"kind": "scat", "n": 3, "spread": 8.0, "arg": "wolf"},
				{"kind": "blood", "n": 2, "spread": 8.0},
				{"kind": "bone", "n": 2, "spread": 7.0, "arg": "deer"},
			],
		},
	},

	{
		"id": "fold_breached",
		"stage": "place",
		"hear": "cattle",
		"threat": 0,
		"linger": 1.5,
		"note": "Stock is out somewhere near %s and somebody has been shouting at it a while.",
		"live": [
			{"kind": "hurdle", "n": 2, "spread": 3.0, "arg": "broken", "layout": "line"},
			{"kind": "track", "n": 8, "spread": 6.0, "arg": "hoof"},
			{"kind": "post", "n": 2, "spread": 3.5},
		],
		"after": {
			## Found in the beans, fat and pleased with themselves: the gap is
			## small, the tracks go one way and come back.
			"found": [
				{"kind": "track", "n": 12, "spread": 9.0, "arg": "cow"},
				{"kind": "scat", "n": 5, "spread": 7.0, "arg": "cow"},
				{"kind": "hurdle", "n": 1, "spread": 2.5, "arg": "broken", "layout": "line"},
				{"kind": "basket", "n": 1, "spread": 4.0, "arg": "spilled"},
			],
			## One is in the bog to the belly. Ropes, and planks laid out to
			## stand on.
			## No hurdle in this one on purpose: the fold is half a field away
			## and the whole story is at the bog. Planks laid end to end to stand
			## on, and two coils of rope where they took the strain.
			"bogged": [
				{"kind": "track", "n": 6, "spread": 5.0, "arg": "cow"},
				{"kind": "plank", "n": 4, "spread": 3.0, "layout": "line"},
				{"kind": "net", "n": 2, "spread": 2.5, "arg": "rope"},
				{"kind": "cloth", "n": 1, "spread": 3.0, "arg": "sack"},
			],
			## A family's winter walked off into fog. The tracks lead out and
			## stop, and there is wool on the hedge going the same way.
			"gone": [
				{"kind": "hurdle", "n": 2, "spread": 3.0, "arg": "broken", "layout": "line"},
				{"kind": "track", "n": 6, "spread": 12.0, "arg": "hoof"},
				{"kind": "post", "n": 2, "spread": 3.5},
				{"kind": "fleece", "n": 3, "spread": 6.0, "y": 0.3},
				{"kind": "cloth", "n": 1, "spread": 4.0, "arg": "sack"},
			],
		},
	},

	{
		"id": "murrain",
		"stage": "place",
		## threat -1 means the Director rings nothing, live or after, so this
		## `hear` is a label on the record and never a sound. Do not tune it
		## expecting cattle: give the recipe a threat first, or leave it alone.
		"hear": "cattle",
		"threat": -1,
		"linger": 2.5,
		"note": "The byres at %s are shut in broad daylight, which they never are.",
		"live": [
			{"kind": "post", "n": 2, "spread": 3.0},
			{"kind": "hurdle", "n": 2, "spread": 3.5, "layout": "line"},
			{"kind": "cloth", "n": 2, "spread": 3.0, "arg": "linen"},
			{"kind": "basket", "n": 1, "spread": 2.5},
		],
		"after": {
			## It went through and took nothing. The byres are open again and
			## the stock is back out on the grass, which is the whole of the good
			## news and the only way to tell this from the one that was not.
			"passed": [
				{"kind": "track", "n": 10, "spread": 7.0, "arg": "cow"},
				{"kind": "scat", "n": 4, "spread": 7.0, "arg": "cow"},
				{"kind": "cloth", "n": 2, "spread": 3.0, "arg": "linen"},
				{"kind": "basket", "n": 1, "spread": 2.5},
			],
			## One shed on its own, a fire kept in beside it, and nobody using
			## the word. The light burning by a shut byre in the middle of the day
			## is the tell, and the one ox's bones behind it.
			"one_cow": [
				{"kind": "hurdle", "n": 2, "spread": 3.0, "layout": "line"},
				{"kind": "torch", "n": 1, "spread": 2.5, "arg": "lit"},
				{"kind": "ash", "n": 1, "spread": 2.0},
				{"kind": "bone", "n": 1, "spread": 3.0, "arg": "ox"},
				{"kind": "cloth", "n": 1, "spread": 2.5, "arg": "linen"},
				{"kind": "post", "n": 1, "spread": 2.0},
			],
			## The pit at the end of the low field. This is the one that reads
			## from the far side of the wall.
			"herd": [
				{"kind": "bone", "n": 5, "spread": 4.0, "arg": "ox"},
				{"kind": "ash", "n": 2, "spread": 3.0},
				{"kind": "char", "n": 3, "spread": 3.0},
				{"kind": "stone", "n": 3, "spread": 5.0},
				{"kind": "feather", "n": 6, "spread": 6.0, "arg": "crow"},
				{"kind": "cloth", "n": 2, "spread": 4.0, "arg": "linen"},
			],
			## Every gate on the road barred against strangers.
			"blamed": [
				{"kind": "hurdle", "n": 3, "spread": 5.0, "layout": "line"},
				{"kind": "post", "n": 3, "spread": 5.0},
				{"kind": "torch", "n": 2, "spread": 4.0, "arg": "guttered"},
				{"kind": "cloth", "n": 1, "spread": 3.0, "arg": "sack"},
				{"kind": "track", "n": 8, "spread": 7.0, "arg": "boot"},
			],
		},
	},

	{
		"id": "moose_turnips",
		"stage": "place",
		"hear": "dogs",
		"threat": 2,
		"linger": 2.0,
		"note": "Something heavy is standing in the turnips at %s and it is not moving off.",
		"live": [
			{"kind": "hurdle", "n": 2, "spread": 3.5, "arg": "broken", "layout": "line"},
			{"kind": "track", "n": 5, "spread": 5.0, "arg": "moose"},
			{"kind": "basket", "n": 1, "spread": 3.0, "arg": "spilled"},
		],
		"after": {
			"chased": [
				{"kind": "track", "n": 10, "spread": 8.0, "arg": "moose"},
				{"kind": "hurdle", "n": 1, "spread": 3.0, "arg": "broken", "layout": "line"},
				{"kind": "basket", "n": 1, "spread": 3.0, "arg": "spilled"},
				{"kind": "track", "n": 8, "spread": 6.0, "arg": "boot"},
				## Every account of this has the dog in it. The dog was not on the
				## ground until now, and a dog line running inside the boot line is
				## what says CHASED rather than shot, trampled or gored.
				{"kind": "track", "n": 10, "spread": 7.0, "arg": "dog"},
				{"kind": "scat", "n": 3, "spread": 6.0, "arg": "moose"},
			],
			## Hanging in the smithy now. What is left in the field is the
			## gralloch, the cart that fetched him, and the birds.
			"shot": [
				{"kind": "blood", "n": 4, "spread": 3.0},
				{"kind": "track", "n": 6, "spread": 5.0, "arg": "moose"},
				{"kind": "track", "n": 8, "spread": 6.0, "arg": "boot"},
				{"kind": "bone", "n": 2, "spread": 3.0, "arg": "big"},
				{"kind": "cart", "n": 1, "spread": 4.0},
				{"kind": "feather", "n": 5, "spread": 5.0, "arg": "crow"},
			],
			## Through the turnips, the beans and the fence, and then stood in
			## the road. The line of wreckage is the story.
			"trampled": [
				{"kind": "hurdle", "n": 3, "spread": 6.0, "arg": "broken", "layout": "line"},
				{"kind": "post", "n": 3, "spread": 6.0},
				{"kind": "plank", "n": 4, "spread": 5.0, "arg": "split"},
				{"kind": "track", "n": 12, "spread": 12.0, "arg": "moose"},
				{"kind": "basket", "n": 2, "spread": 5.0, "arg": "spilled"},
			],
			"gored": [
				{"kind": "blood", "n": 3, "spread": 2.5},
				{"kind": "track", "n": 6, "spread": 5.0, "arg": "moose"},
				{"kind": "track", "n": 3, "spread": 3.0, "arg": "drag"},
				{"kind": "cloth", "n": 1, "spread": 2.5, "arg": "linen"},
				{"kind": "hurdle", "n": 1, "spread": 3.0, "arg": "broken", "layout": "line"},
				{"kind": "plank", "n": 1, "spread": 2.0, "arg": "stick"},
			],
		},
	},

	## ------------------------------------------------------------- roads ---
	{
		"id": "caravan_in",
		"stage": "road",
		"hear": "carts",
		"threat": 0,
		"linger": 1.0,
		"note": "Wheels and voices on the road into %s, more of both than that road usually carries.",
		"live": [
			{"kind": "cart", "n": 2, "spread": 6.0},
			{"kind": "crate", "n": 4, "spread": 5.0},
			{"kind": "barrel", "n": 3, "spread": 5.0},
			{"kind": "cloth", "n": 2, "spread": 5.0, "arg": "sail", "y": 0.7},
			{"kind": "torch", "n": 1, "spread": 4.0, "arg": "lit"},
		],
		"after": {
			"good_trade": [
				{"kind": "track", "n": 8, "spread": 10.0, "arg": "cart"},
				{"kind": "crate", "n": 1, "spread": 4.0, "arg": "spilled"},
				{"kind": "cloth", "n": 1, "spread": 4.0, "arg": "sack"},
				{"kind": "ash", "n": 1, "spread": 2.0},
				{"kind": "basket", "n": 2, "spread": 4.0},
			],
			## A silver piece a pound. The salt went out again in the barrels it
			## came in, still sealed, and the crates went home loaded — no fire,
			## no emptied baskets, nobody stayed the night. That is the complaint,
			## standing in a field, and it is the opposite of `good_trade`.
			"prices": [
				{"kind": "barrel", "n": 3, "spread": 4.0, "arg": "sealed"},
				{"kind": "crate", "n": 2, "spread": 4.0},
				{"kind": "track", "n": 6, "spread": 10.0, "arg": "cart"},
			],
			## The butcher would not take it, so they burned it where it fell.
			"sick_ox": [
				{"kind": "bone", "n": 4, "spread": 3.0, "arg": "ox"},
				{"kind": "char", "n": 2, "spread": 2.5},
				{"kind": "ash", "n": 1, "spread": 2.0},
				{"kind": "blood", "n": 2, "spread": 2.5},
				{"kind": "track", "n": 6, "spread": 8.0, "arg": "cart"},
				{"kind": "feather", "n": 8, "spread": 5.0, "arg": "crow"},
			],
		},
	},

	{
		"id": "caravan_overdue",
		"stage": "road",
		## threat -1: silent, so this `hear` never reaches the Telegraph. It is
		## here to name the record, not to be tuned. See `murrain`.
		"hear": "road",
		"threat": -1,
		"linger": 3.0,
		"note": "The road to %s is empty in the wrong way. Old ruts, and nothing laid over them.",
		"live": [
			{"kind": "track", "n": 8, "spread": 12.0, "arg": "cart"},
			{"kind": "cloth", "n": 1, "spread": 5.0, "arg": "sack"},
		],
		"after": {
			## Mud to the axles, and they walked in at dusk. Deep fresh ruts,
			## nothing else disturbed.
			"turned_up": [
				{"kind": "track", "n": 12, "spread": 12.0, "arg": "cart"},
				{"kind": "plank", "n": 3, "spread": 4.0, "layout": "line"},
				{"kind": "crate", "n": 1, "spread": 4.0},
				{"kind": "cloth", "n": 1, "spread": 4.0, "arg": "sack"},
			],
			## Not stuck — just slow, and a night spent on the road rather than
			## in it. A cold fire and horse dung is the difference between a
			## caravan that had to be dug out and one that simply stopped.
			"late": [
				{"kind": "track", "n": 6, "spread": 14.0, "arg": "cart"},
				{"kind": "ash", "n": 1, "spread": 3.0},
				{"kind": "scat", "n": 4, "spread": 8.0, "arg": "horse"},
				{"kind": "stone", "n": 2, "spread": 5.0},
			],
			## Traces cut, every bale gone, drivers alive in the ditch. Men's
			## boots and a coil of cut rope, and no blood worth the name.
			"robbed": [
				{"kind": "cart", "n": 1, "spread": 3.0, "arg": "tipped"},
				{"kind": "crate", "n": 3, "spread": 5.0, "arg": "spilled"},
				{"kind": "net", "n": 1, "spread": 2.5, "arg": "rope"},
				{"kind": "cloth", "n": 2, "spread": 5.0, "arg": "sack"},
				{"kind": "track", "n": 8, "spread": 8.0, "arg": "boot"},
			],
			## Little tracks all round, and the oxen butchered where they
			## stood. The difference from `robbed` is written in the ground.
			"goblins": [
				{"kind": "cart", "n": 1, "spread": 3.0, "arg": "tipped"},
				{"kind": "crate", "n": 2, "spread": 5.0, "arg": "spilled"},
				{"kind": "bone", "n": 5, "spread": 4.0, "arg": "ox"},
				{"kind": "blood", "n": 4, "spread": 4.0},
				{"kind": "track", "n": 12, "spread": 8.0, "arg": "small"},
				{"kind": "ash", "n": 1, "spread": 3.0},
				{"kind": "feather", "n": 8, "spread": 6.0, "arg": "crow"},
			],
		},
	},

	{
		"id": "bandits_road",
		"stage": "road",
		"hear": "men",
		"threat": 2,
		"linger": 2.0,
		"note": "There are men on the road below %s who picked that spot on purpose.",
		"live": [
			{"kind": "plank", "n": 2, "spread": 4.0},
			{"kind": "post", "n": 2, "spread": 4.0},
			{"kind": "ash", "n": 1, "spread": 2.5},
			{"kind": "torch", "n": 1, "spread": 3.0, "arg": "lit"},
		],
		"after": {
			## A penny a head and don't argue. They have been sat here long
			## enough to eat something.
			"toll": [
				{"kind": "ash", "n": 1, "spread": 2.5},
				{"kind": "post", "n": 2, "spread": 4.0},
				{"kind": "plank", "n": 1, "spread": 3.0},
				{"kind": "track", "n": 10, "spread": 6.0, "arg": "boot"},
				{"kind": "bone", "n": 2, "spread": 2.5, "arg": "sheep"},
				{"kind": "cloth", "n": 1, "spread": 4.0, "arg": "sack"},
			],
			"beaten": [
				{"kind": "blood", "n": 3, "spread": 3.0},
				{"kind": "cloth", "n": 3, "spread": 4.0, "arg": "linen"},
				{"kind": "basket", "n": 1, "spread": 3.0, "arg": "spilled"},
				{"kind": "track", "n": 10, "spread": 6.0, "arg": "boot"},
				{"kind": "track", "n": 2, "spread": 4.0, "arg": "drag"},
			],
			## The carters won. Broken cudgels, a great churn of boots, and
			## the fire kicked apart on the way past.
			"run_off": [
				{"kind": "track", "n": 14, "spread": 9.0, "arg": "boot"},
				{"kind": "plank", "n": 3, "spread": 5.0, "arg": "split"},
				{"kind": "blood", "n": 2, "spread": 5.0},
				{"kind": "cloth", "n": 1, "spread": 4.0, "arg": "sack"},
				{"kind": "ash", "n": 1, "spread": 3.5},
			],
		},
	},

	## ----------------------------------------------------------- goblins ---
	{
		"id": "goblin_sign",
		"stage": "wild",
		## A jay is a daylight bird mobbing something it can see. This kind runs
		## ALL_DAY, so a third of it fires in the dark; crows carry at any hour
		## and are what actually sits over a camp in the deepwood.
		"hear": "crows",
		"threat": 1,
		"linger": 3.0,
		"note": "Saplings cut off waist high in the deepwood past %s, and a ring of blackened stones.",
		"live": [
			{"kind": "post", "n": 4, "spread": 5.0, "arg": "cut"},
			{"kind": "ash", "n": 1, "spread": 1.6},
			## Blackened, six of them, and tight enough to sit on the rim of the
			## ash decal rather than scattered across the clearing. The note says
			## a RING of blackened stones and now the ground says it too.
			{"kind": "stone", "n": 6, "spread": 1.1, "arg": "burnt"},
		],
		"after": {
			## Cold for a week, and he still came home early. No ash: a ring
			## that has stood out a week of Maine rain has nothing grey left in
			## it, and the plain weathered cuts beside the fresh ones are how a
			## week reads on a stump. That absence is the whole difference from
			## `fresh`, and without it this was a strict subset of it.
			"old": [
				{"kind": "stone", "n": 6, "spread": 1.1, "arg": "burnt"},
				{"kind": "post", "n": 3, "spread": 5.0, "arg": "cut"},
				{"kind": "post", "n": 2, "spread": 5.5},
				{"kind": "bone", "n": 2, "spread": 3.0, "arg": "deer"},
			],
			## A deer hung up with its belly opened. That is a camp.
			"fresh": [
				{"kind": "stone", "n": 6, "spread": 1.1, "arg": "burnt"},
				{"kind": "ash", "n": 1, "spread": 1.6},
				{"kind": "char", "n": 3, "spread": 2.0},
				{"kind": "post", "n": 4, "spread": 5.0, "arg": "cut"},
				{"kind": "bone", "n": 3, "spread": 2.5, "arg": "deer"},
				{"kind": "blood", "n": 3, "spread": 2.0},
				{"kind": "track", "n": 10, "spread": 6.0, "arg": "small"},
				{"kind": "feather", "n": 4, "spread": 4.0, "arg": "crow"},
			],
			## Drums. Big enough to drum in, and the tracks go everywhere.
			"drums": [
				{"kind": "stone", "n": 6, "spread": 1.1, "arg": "burnt"},
				{"kind": "ash", "n": 2, "spread": 3.5},
				{"kind": "char", "n": 4, "spread": 3.5},
				{"kind": "post", "n": 5, "spread": 7.0, "arg": "cut"},
				{"kind": "track", "n": 16, "spread": 10.0, "arg": "small"},
				{"kind": "bone", "n": 4, "spread": 4.0, "arg": "big"},
				{"kind": "scat", "n": 4, "spread": 6.0, "arg": "small"},
			],
		},
	},

	{
		"id": "goblin_raid",
		"stage": "place",
		"hear": "shouting",
		"threat": 3,
		## The one aftermath in the file that is still dangerous three days on.
		## They know the way in now, and every outcome here ends with them still
		## out there — so this stays ALARM after the fact where a fire drops to
		## nothing.
		"threat_after": 2,
		"linger": 3.0,
		"note": "There is shouting at the field's edge at %s and torches going the wrong way up it.",
		"live": [
			{"kind": "torch", "n": 3, "spread": 6.0, "arg": "lit"},
			{"kind": "hurdle", "n": 2, "spread": 4.0, "arg": "broken", "layout": "line"},
			{"kind": "track", "n": 10, "spread": 8.0, "arg": "small"},
		],
		"after": {
			## Driven off with torches and nobody lost. Two sets of prints, one
			## coming and one going, and no burning.
			"driven_off": [
				{"kind": "torch", "n": 4, "spread": 6.0, "arg": "guttered"},
				{"kind": "track", "n": 12, "spread": 9.0, "arg": "small"},
				{"kind": "track", "n": 10, "spread": 7.0, "arg": "boot"},
				{"kind": "hurdle", "n": 1, "spread": 3.0, "arg": "broken", "layout": "line"},
				{"kind": "plank", "n": 2, "spread": 4.0, "arg": "split"},
				{"kind": "ash", "n": 1, "spread": 3.0},
			],
			## The stock got out. The hay did not.
			"byre_burned": [
				{"kind": "char", "n": 6, "spread": 4.0},
				{"kind": "ash", "n": 2, "spread": 3.5},
				{"kind": "post", "n": 4, "spread": 4.0, "arg": "burnt"},
				{"kind": "plank", "n": 3, "spread": 4.5, "arg": "charred"},
				{"kind": "track", "n": 10, "spread": 8.0, "arg": "small"},
				{"kind": "hurdle", "n": 1, "spread": 3.5, "arg": "broken", "layout": "line"},
			],
			## Two goats and a ploughboy. The goats came back.
			"taken": [
				{"kind": "hurdle", "n": 2, "spread": 3.5, "arg": "broken", "layout": "line"},
				{"kind": "track", "n": 14, "spread": 10.0, "arg": "small"},
				{"kind": "track", "n": 4, "spread": 6.0, "arg": "boot"},
				{"kind": "blood", "n": 3, "spread": 4.0},
				{"kind": "cloth", "n": 2, "spread": 5.0, "arg": "linen"},
				{"kind": "basket", "n": 1, "spread": 3.0, "arg": "spilled"},
				{"kind": "plank", "n": 1, "spread": 2.5, "arg": "stick"},
				{"kind": "feather", "n": 4, "spread": 5.0, "arg": "crow"},
			],
		},
	},

	{
		"id": "storm_damage",
		"stage": "place",
		"hear": "wind",
		"threat": 1,
		"linger": 3.0,
		"note": "Everything at %s that could come down came down in the night, and they are still finding out how much.",
		"live": [
			{"kind": "plank", "n": 5, "spread": 8.0, "arg": "split"},
			{"kind": "cloth", "n": 2, "spread": 6.0, "arg": "sack"},
			{"kind": "post", "n": 2, "spread": 5.0},
		],
		"after": {
			## Thatch off, and it went everywhere. Cloth and straw, no timber.
			"roofs": [
				{"kind": "plank", "n": 6, "spread": 8.0, "arg": "split"},
				{"kind": "cloth", "n": 3, "spread": 7.0, "arg": "sack", "y": 0.05},
				{"kind": "basket", "n": 2, "spread": 5.0},
				{"kind": "track", "n": 8, "spread": 6.0, "arg": "boot"},
			],
			## Big spruce across the road, and the wheelwright already out
			## measuring it for spokes. This was six standing posts, which is a
			## fence at fifteen metres and never a felled tree — a `post` is a
			## vertical cylinder and cannot lie down. Logs can.
			"trees_down": [
				{"kind": "log", "n": 3, "spread": 9.0, "layout": "line"},
				{"kind": "plank", "n": 5, "spread": 7.0, "arg": "split"},
				{"kind": "post", "n": 2, "spread": 8.0, "arg": "snapped"},
				{"kind": "track", "n": 6, "spread": 8.0, "arg": "boot"},
				{"kind": "cart", "n": 1, "spread": 6.0},
			],
			## The middle span gone and the two ends pointing at each other.
			"bridge": [
				{"kind": "plank", "n": 6, "spread": 8.0, "arg": "split"},
				{"kind": "post", "n": 4, "spread": 7.0},
				{"kind": "stone", "n": 5, "spread": 6.0},
				{"kind": "net", "n": 1, "spread": 3.0, "arg": "rope"},
			],
			## Laid flat with the grain still in it: two corner posts left
			## standing over a whole field of boards. Six upright posts read as a
			## fence line; two read as what is left of a building.
			"barn_lost": [
				{"kind": "post", "n": 2, "spread": 9.0},
				{"kind": "plank", "n": 10, "spread": 9.0, "arg": "split"},
				{"kind": "cloth", "n": 2, "spread": 7.0, "arg": "sack"},
				{"kind": "basket", "n": 2, "spread": 6.0, "arg": "spilled"},
				{"kind": "crate", "n": 2, "spread": 6.0, "arg": "spilled"},
				{"kind": "track", "n": 6, "spread": 6.0, "arg": "boot"},
			],
		},
	},

	{
		"id": "ford_drowned",
		"stage": "road",
		"hear": "water",
		"threat": 1,
		"linger": 1.5,
		"note": "Carts drawn up short of the ford below %s with nobody in a hurry to be first.",
		"live": [
			{"kind": "cart", "n": 2, "spread": 8.0},
			{"kind": "barrel", "n": 2, "spread": 6.0},
			{"kind": "track", "n": 8, "spread": 8.0, "arg": "cart"},
			{"kind": "torch", "n": 1, "spread": 4.0, "arg": "lit"},
		],
		"after": {
			## Half a dozen carts sat on the bank all day and the inn doing very
			## well out of them: churned ground, fires, horse dung, no wreckage.
			"waited": [
				{"kind": "track", "n": 12, "spread": 10.0, "arg": "cart"},
				{"kind": "ash", "n": 2, "spread": 5.0},
				{"kind": "scat", "n": 4, "spread": 6.0, "arg": "horse"},
				{"kind": "barrel", "n": 1, "spread": 4.0},
			],
			## The ox swam. The cart and the flour did not.
			"cart_lost": [
				{"kind": "cart", "n": 1, "spread": 3.0, "arg": "tipped"},
				{"kind": "plank", "n": 4, "spread": 6.0, "arg": "split"},
				{"kind": "barrel", "n": 2, "spread": 6.0, "arg": "stove"},
				{"kind": "cloth", "n": 2, "spread": 5.0, "arg": "sack"},
				{"kind": "track", "n": 6, "spread": 7.0, "arg": "cart"},
			],
			## Still had his pack on. That is what drowned him.
			"drowned_man": [
				{"kind": "cloth", "n": 2, "spread": 3.0, "arg": "linen"},
				{"kind": "basket", "n": 1, "spread": 2.5, "arg": "spilled"},
				{"kind": "track", "n": 8, "spread": 5.0, "arg": "boot"},
				{"kind": "cairn", "n": 1, "spread": 2.0},
				{"kind": "stone", "n": 3, "spread": 4.0},
				{"kind": "feather", "n": 4, "spread": 5.0, "arg": "crow"},
			],
		},
	},

	## -------------------------------------------------- water and the sky ---
	{
		"id": "ice_out",
		"stage": "place",
		"hear": "ice",
		"threat": 1,
		"linger": 2.0,
		"note": "The ice at %s is working. Cracks going off across it like axe blows, and never two in the same place.",
		"live": [
			{"kind": "stone", "n": 5, "spread": 8.0},
			{"kind": "net", "n": 2, "spread": 6.0},
			{"kind": "float", "n": 5, "spread": 7.0},
		],
		"after": {
			## Clean as a bill paid. Boats in the water by noon.
			"clean": [
				{"kind": "net", "n": 2, "spread": 5.0},
				{"kind": "float", "n": 6, "spread": 6.0},
				{"kind": "basket", "n": 2, "spread": 4.0},
				{"kind": "track", "n": 6, "spread": 6.0, "arg": "boot"},
			],
			## Backed up over the low road. The wrack line is a field inland of
			## where a wrack line belongs.
			"jam": [
				{"kind": "plank", "n": 4, "spread": 8.0},
				{"kind": "stone", "n": 6, "spread": 8.0},
				{"kind": "net", "n": 1, "spread": 5.0, "arg": "torn"},
				{"kind": "cloth", "n": 1, "spread": 6.0, "arg": "sack"},
				{"kind": "float", "n": 3, "spread": 8.0},
			],
			## They heard it go. They did not hear him.
			"man_through": [
				{"kind": "net", "n": 1, "spread": 3.0, "arg": "torn"},
				{"kind": "float", "n": 3, "spread": 4.0},
				{"kind": "cloth", "n": 1, "spread": 3.0, "arg": "linen"},
				{"kind": "track", "n": 6, "spread": 5.0, "arg": "boot"},
				{"kind": "cairn", "n": 1, "spread": 2.0},
				{"kind": "stone", "n": 2, "spread": 3.0},
			],
			## Splinters to the far bank.
			"boats_crushed": [
				{"kind": "plank", "n": 6, "spread": 10.0, "arg": "split"},
				{"kind": "post", "n": 3, "spread": 8.0},
				{"kind": "net", "n": 2, "spread": 7.0, "arg": "torn"},
				{"kind": "float", "n": 6, "spread": 9.0},
				{"kind": "cloth", "n": 1, "spread": 6.0, "arg": "sail"},
			],
		},
	},

	{
		"id": "aurora",
		"stage": "wild",
		## threat -1: nothing is rung for this, so `hear` is a name and not a
		## sound. The sky does not make a noise. See `murrain`.
		"hear": "sky",
		"threat": -1,
		"linger": 0.5,
		"note": "The sky north of %s is standing up in green curtains and swaying about.",
		"live": [
			{"kind": "torch", "n": 1, "spread": 3.0, "arg": "guttered"},
			{"kind": "cloth", "n": 2, "spread": 4.0, "arg": "sack"},
		],
		"after": {
			## Folk came out in blankets and just looked.
			"wonder": [
				{"kind": "cloth", "n": 3, "spread": 5.0, "arg": "sack"},
				{"kind": "ash", "n": 1, "spread": 2.0},
				{"kind": "track", "n": 8, "spread": 6.0, "arg": "boot"},
			],
			## He is not said of what. He is charging to find out.
			"priest": [
				{"kind": "cairn", "n": 1, "spread": 1.5},
				{"kind": "torch", "n": 2, "spread": 3.0, "arg": "guttered"},
				{"kind": "cloth", "n": 1, "spread": 2.5, "arg": "linen"},
				{"kind": "stone", "n": 3, "spread": 3.0},
			],
			## Two families are talking about leaving, and one of them has begun
			## to load.
			"fear": [
				{"kind": "cart", "n": 1, "spread": 3.0},
				{"kind": "crate", "n": 3, "spread": 4.0},
				{"kind": "basket", "n": 2, "spread": 3.5},
				{"kind": "cloth", "n": 2, "spread": 4.0, "arg": "sack"},
				{"kind": "track", "n": 8, "spread": 8.0, "arg": "cart"},
			],
		},
	},

	## ---------------------------------------------------- the year's work ---
	{
		"id": "harvest_in",
		"stage": "place",
		"hear": "voices",
		"threat": 0,
		"linger": 1.5,
		"note": "Carts going in and out of the barns at %s, and somebody singing badly over it.",
		"live": [
			{"kind": "cart", "n": 1, "spread": 5.0},
			{"kind": "basket", "n": 4, "spread": 5.0},
			{"kind": "crate", "n": 2, "spread": 5.0},
			{"kind": "cloth", "n": 1, "spread": 4.0, "arg": "sack"},
		],
		"after": {
			## Full to the beams, and a fire lit for the dance.
			"full": [
				{"kind": "basket", "n": 5, "spread": 6.0},
				{"kind": "crate", "n": 3, "spread": 5.0},
				{"kind": "cart", "n": 1, "spread": 5.0},
				{"kind": "ash", "n": 1, "spread": 2.5},
				{"kind": "track", "n": 8, "spread": 8.0, "arg": "cart"},
			],
			## The heads were half empty. Two baskets where there should be six.
			"thin": [
				{"kind": "basket", "n": 2, "spread": 6.0},
				{"kind": "cart", "n": 1, "spread": 5.0},
				{"kind": "cloth", "n": 2, "spread": 5.0, "arg": "sack"},
				{"kind": "track", "n": 6, "spread": 8.0, "arg": "cart"},
				{"kind": "stone", "n": 2, "spread": 5.0},
			],
			## Caught in the stook and gone black. Seed corn and winter both.
			"rotted": [
				{"kind": "cloth", "n": 3, "spread": 6.0, "arg": "sack", "y": 0.05},
				{"kind": "basket", "n": 3, "spread": 6.0, "arg": "spilled"},
				{"kind": "ash", "n": 1, "spread": 3.0},
				{"kind": "feather", "n": 6, "spread": 6.0, "arg": "crow"},
				{"kind": "post", "n": 2, "spread": 6.0},
			],
		},
	},

	{
		"id": "tithe_due",
		"stage": "place",
		"hear": "voices",
		"threat": 1,
		"linger": 1.0,
		"note": "Reeve's men at %s, and nobody talking any louder than they have to.",
		"live": [
			{"kind": "cart", "n": 1, "spread": 4.0},
			{"kind": "crate", "n": 3, "spread": 4.0},
			{"kind": "basket", "n": 3, "spread": 4.0},
			{"kind": "track", "n": 6, "spread": 5.0, "arg": "boot"},
		],
		"after": {
			## Got it, near enough. Nobody sang and nobody threw anything.
			"paid": [
				{"kind": "track", "n": 10, "spread": 8.0, "arg": "cart"},
				{"kind": "basket", "n": 2, "spread": 4.0},
				{"kind": "crate", "n": 1, "spread": 4.0},
				{"kind": "ash", "n": 1, "spread": 2.5},
			],
			## He took a cow instead. Took the good one, naturally — and the
			## hoofprints leave beside the cart ruts.
			"short": [
				{"kind": "track", "n": 8, "spread": 8.0, "arg": "cart"},
				{"kind": "track", "n": 6, "spread": 8.0, "arg": "cow"},
				{"kind": "basket", "n": 1, "spread": 3.5, "arg": "spilled"},
				{"kind": "scat", "n": 3, "spread": 6.0, "arg": "cow"},
				{"kind": "cloth", "n": 1, "spread": 4.0, "arg": "sack"},
			],
			## The barn barred, stones brought to hand, and a cart of reeve's
			## men on the road.
			"refused": [
				{"kind": "plank", "n": 4, "spread": 5.0},
				{"kind": "post", "n": 3, "spread": 5.0},
				{"kind": "hurdle", "n": 2, "spread": 5.0, "layout": "line"},
				{"kind": "torch", "n": 2, "spread": 5.0, "arg": "guttered"},
				{"kind": "track", "n": 12, "spread": 8.0, "arg": "boot"},
				{"kind": "stone", "n": 4, "spread": 5.0},
			],
		},
	},

	{
		"id": "mill_broken",
		"stage": "place",
		"hear": "hammer",
		"threat": 0,
		"linger": 2.5,
		"note": "Nothing is turning at %s, and the river going past the wheel sounds far too loud with it stopped.",
		"live": [
			{"kind": "plank", "n": 4, "spread": 5.0},
			{"kind": "post", "n": 2, "spread": 4.0},
			{"kind": "crate", "n": 2, "spread": 4.0},
			{"kind": "basket", "n": 2, "spread": 4.0},
		],
		"after": {
			## First flour in a fortnight. Fresh shavings and empty sacks.
			"mended": [
				{"kind": "plank", "n": 3, "spread": 5.0},
				{"kind": "basket", "n": 3, "spread": 4.0},
				{"kind": "crate", "n": 2, "spread": 4.0},
				{"kind": "ash", "n": 1, "spread": 2.5},
				{"kind": "track", "n": 8, "spread": 6.0, "arg": "boot"},
			],
			## Threw its shaft, and there is grain sat in every barn going soft.
			"shaft": [
				{"kind": "post", "n": 2, "spread": 3.0},
				{"kind": "plank", "n": 5, "spread": 6.0, "arg": "split"},
				{"kind": "crate", "n": 3, "spread": 5.0},
				{"kind": "basket", "n": 3, "spread": 5.0},
				{"kind": "cloth", "n": 2, "spread": 5.0, "arg": "sack"},
			],
			## He will grind again, left-handed.
			"miller_hurt": [
				{"kind": "blood", "n": 3, "spread": 2.0},
				{"kind": "cloth", "n": 2, "spread": 3.0, "arg": "linen"},
				{"kind": "plank", "n": 3, "spread": 4.0, "arg": "split"},
				{"kind": "post", "n": 1, "spread": 2.5},
				{"kind": "basket", "n": 1, "spread": 3.0, "arg": "spilled"},
				{"kind": "track", "n": 6, "spread": 5.0, "arg": "boot"},
			],
		},
	},

	{
		"id": "bees",
		"stage": "place",
		"hear": "bees",
		"threat": 1,
		"linger": 1.5,
		"note": "The orchard at %s is roaring low and steady, and everybody in it is standing further back than usual.",
		"live": [
			{"kind": "basket", "n": 4, "spread": 4.0},
			{"kind": "post", "n": 2, "spread": 3.5},
			{"kind": "cloth", "n": 1, "spread": 3.0, "arg": "linen"},
		],
		"after": {
			## Talked into a skep. She will not say what she told them. One MORE
			## skep than there was, veils hung up, and nobody went anywhere: the
			## boots stay inside four metres.
			"swarm_caught": [
				{"kind": "basket", "n": 6, "spread": 4.0},
				{"kind": "cloth", "n": 3, "spread": 3.0, "arg": "linen"},
				{"kind": "post", "n": 2, "spread": 3.5, "layout": "line"},
				{"kind": "track", "n": 6, "spread": 4.0, "arg": "boot"},
			],
			## One skep over and the boots go off into the wood and keep going.
			## Fourteen metres of them, the skep-pole dropped where they gave up,
			## and the veil left in the grass.
			"swarm_lost": [
				{"kind": "basket", "n": 3, "spread": 4.0, "arg": "spilled"},
				{"kind": "track", "n": 12, "spread": 14.0, "arg": "boot"},
				{"kind": "plank", "n": 1, "spread": 3.0, "arg": "stick"},
				{"kind": "cloth", "n": 1, "spread": 6.0, "arg": "linen"},
			],
			## Splinters and wax across the orchard, and prints the size of a
			## man's two hands.
			"bear": [
				{"kind": "basket", "n": 4, "spread": 6.0, "arg": "spilled"},
				{"kind": "plank", "n": 4, "spread": 5.0, "arg": "split"},
				{"kind": "track", "n": 5, "spread": 6.0, "arg": "bear"},
				{"kind": "scat", "n": 2, "spread": 5.0, "arg": "bear"},
				{"kind": "cloth", "n": 1, "spread": 4.0, "arg": "linen"},
				{"kind": "post", "n": 2, "spread": 4.0},
			],
		},
	},

	{
		"id": "fire",
		"stage": "place",
		"hear": "bell",
		"threat": 3,
		## PANIC while it is burning and nothing at all afterwards. The modal
		## outcome is a chimney fire beaten out with buckets; ringing the bell at
		## three-day-old scorch marks is how a player learns that the Telegraph
		## lies to them, and once they have learned that they stop listening to
		## the wolves too.
		"threat_after": -1,
		"linger": 3.0,
		"note": "Bell going at %s, and the smoke laid flat along the roofs instead of standing up.",
		"live": [
			{"kind": "torch", "n": 4, "spread": 6.0, "arg": "lit"},
			{"kind": "barrel", "n": 3, "spread": 5.0},
			{"kind": "basket", "n": 3, "spread": 5.0},
			{"kind": "char", "n": 2, "spread": 3.0},
		],
		"after": {
			## Buckets and shouting, then nothing. Scorch, and the buckets still
			## out where they were dropped.
			"chimney": [
				{"kind": "char", "n": 3, "spread": 3.0},
				{"kind": "ash", "n": 1, "spread": 2.5},
				{"kind": "barrel", "n": 3, "spread": 4.0},
				{"kind": "basket", "n": 2, "spread": 4.0},
				{"kind": "cloth", "n": 1, "spread": 4.0, "arg": "sack"},
				{"kind": "track", "n": 10, "spread": 6.0, "arg": "boot"},
			],
			## Roof to roof before the bell was rung. Three houses of it.
			"row_lost": [
				{"kind": "char", "n": 6, "spread": 7.0},
				{"kind": "ash", "n": 3, "spread": 6.0},
				{"kind": "post", "n": 5, "spread": 7.0, "arg": "burnt"},
				{"kind": "plank", "n": 5, "spread": 7.0, "arg": "charred"},
				{"kind": "crate", "n": 2, "spread": 6.0},
				{"kind": "cloth", "n": 2, "spread": 6.0, "arg": "sack"},
				{"kind": "barrel", "n": 2, "spread": 6.0, "arg": "stove"},
			],
			## Somebody stacked brush against the granary wall. The brush is
			## still stacked, at the one corner that did not go up.
			"set": [
				{"kind": "char", "n": 4, "spread": 4.0},
				{"kind": "ash", "n": 2, "spread": 3.0},
				{"kind": "post", "n": 2, "spread": 3.5, "arg": "burnt"},
				{"kind": "plank", "n": 4, "spread": 4.0, "arg": "stick"},
				{"kind": "track", "n": 10, "spread": 7.0, "arg": "boot"},
				{"kind": "barrel", "n": 2, "spread": 5.0},
				{"kind": "stone", "n": 3, "spread": 5.0},
			],
		},
	},

	{
		"id": "charcoal",
		"stage": "wild",
		## The clamp is sealed and smoking, which is precisely the week nobody
		## is chopping — a burner sits on it for days and does not touch an axe.
		## What carries down the hill is the fire itself.
		"hear": "fire",
		"threat": 0,
		"linger": 2.5,
		"note": "Smoke standing over the hill above %s, blue and slow, the way a clamp smokes.",
		"live": [
			{"kind": "post", "n": 3, "spread": 4.0},
			{"kind": "ash", "n": 1, "spread": 2.5},
			{"kind": "char", "n": 3, "spread": 3.0},
			## Cordwood cut and stacked ready for the next clamp. A charcoal burn
			## is a woodpile before it is anything else.
			{"kind": "log", "n": 3, "spread": 4.5, "layout": "line"},
			{"kind": "cloth", "n": 1, "spread": 3.0, "arg": "sack"},
			{"kind": "basket", "n": 2, "spread": 3.5},
		],
		"after": {
			## Came out sweet and the smith paid without being asked twice.
			"good_burn": [
				{"kind": "ash", "n": 2, "spread": 3.0},
				{"kind": "char", "n": 3, "spread": 3.0},
				{"kind": "basket", "n": 4, "spread": 4.0},
				{"kind": "crate", "n": 2, "spread": 4.0},
				{"kind": "track", "n": 8, "spread": 6.0, "arg": "boot"},
				{"kind": "cart", "n": 1, "spread": 5.0},
			],
			## Ran away in the night. A whole hillside of it and one man with
			## no eyebrows.
			"clamp_ran": [
				{"kind": "ash", "n": 4, "spread": 8.0},
				{"kind": "char", "n": 8, "spread": 8.0},
				{"kind": "log", "n": 3, "spread": 7.0, "arg": "charred"},
				{"kind": "post", "n": 3, "spread": 6.0, "arg": "burnt"},
				{"kind": "basket", "n": 1, "spread": 4.0, "arg": "spilled"},
				{"kind": "track", "n": 8, "spread": 7.0, "arg": "boot"},
			],
			## Fire still going, tools laid out in a row, and not a soul. The
			## lit torch here is the clamp, still working on its own.
			"burners_gone": [
				{"kind": "ash", "n": 1, "spread": 2.5},
				{"kind": "char", "n": 3, "spread": 3.0},
				{"kind": "torch", "n": 1, "spread": 2.0, "arg": "lit"},
				{"kind": "cloth", "n": 2, "spread": 3.0, "arg": "sack"},
				{"kind": "basket", "n": 2, "spread": 3.0},
				{"kind": "crate", "n": 1, "spread": 3.0},
				{"kind": "plank", "n": 2, "spread": 2.5, "arg": "stick"},
				{"kind": "post", "n": 2, "spread": 4.0},
			],
		},
	},

	{
		"id": "bridge_out",
		"stage": "road",
		"hear": "water",
		"threat": 1,
		"linger": 3.0,
		"note": "There is a rope strung across the road short of the %s bridge, and a path worn round it going down to the water.",
		"live": [
			{"kind": "post", "n": 4, "spread": 6.0},
			{"kind": "plank", "n": 5, "spread": 6.0, "arg": "split"},
			## The stringer that went with the span, lying half in the water.
			{"kind": "log", "n": 1, "spread": 5.0},
			{"kind": "net", "n": 1, "spread": 3.0, "arg": "rope"},
			{"kind": "stone", "n": 5, "spread": 6.0},
		],
		"after": {
			## Planks back across. It will bear a man and a barrow.
			"mended": [
				{"kind": "plank", "n": 5, "spread": 4.0},
				{"kind": "post", "n": 4, "spread": 5.0},
				{"kind": "net", "n": 1, "spread": 3.0, "arg": "rope"},
				{"kind": "track", "n": 8, "spread": 6.0, "arg": "boot"},
				{"kind": "stone", "n": 3, "spread": 5.0},
			],
			## Every cart going round by the ford, and the ruts say so.
			"long_way": [
				{"kind": "post", "n": 4, "spread": 6.0},
				{"kind": "plank", "n": 3, "spread": 6.0, "arg": "split"},
				{"kind": "stone", "n": 4, "spread": 6.0},
				{"kind": "track", "n": 12, "spread": 12.0, "arg": "cart"},
			],
			## Horse, cart and carter, all in. The horse came out.
			"fell": [
				{"kind": "cart", "n": 1, "spread": 4.0, "arg": "tipped"},
				{"kind": "plank", "n": 5, "spread": 7.0, "arg": "split"},
				{"kind": "post", "n": 3, "spread": 6.0},
				{"kind": "net", "n": 1, "spread": 3.0, "arg": "rope"},
				{"kind": "cloth", "n": 1, "spread": 5.0, "arg": "sack"},
				{"kind": "track", "n": 6, "spread": 8.0, "arg": "horse"},
				{"kind": "stone", "n": 3, "spread": 5.0},
			],
		},
	},

	{
		"id": "watch_patrol",
		"stage": "road",
		"hear": "horses",
		"threat": 0,
		"linger": 1.0,
		"note": "Horses on the road out of %s at a walk, four or five of them, in no hurry at all.",
		"live": [
			{"kind": "track", "n": 8, "spread": 8.0, "arg": "horse"},
			{"kind": "torch", "n": 1, "spread": 4.0, "arg": "lit"},
		],
		"after": {
			## Nothing worse than a fox. They are calling it a good day.
			"quiet": [
				{"kind": "track", "n": 10, "spread": 10.0, "arg": "horse"},
				{"kind": "scat", "n": 4, "spread": 8.0, "arg": "horse"},
			],
			## Came up on a camp in the cut and took two alive. The camp is
			## turned over and there is cut cord on the ground.
			"bandits": [
				{"kind": "ash", "n": 1, "spread": 2.5},
				{"kind": "stone", "n": 4, "spread": 2.0},
				{"kind": "cloth", "n": 2, "spread": 4.0, "arg": "sack"},
				{"kind": "net", "n": 1, "spread": 2.5, "arg": "rope"},
				{"kind": "track", "n": 12, "spread": 8.0, "arg": "boot"},
				{"kind": "track", "n": 8, "spread": 8.0, "arg": "horse"},
				{"kind": "blood", "n": 1, "spread": 3.0},
			],
			## The horse came home on its own with the saddle turned. What is
			## on the road is the tack, and the birds found it first.
			"rider_lost": [
				{"kind": "track", "n": 8, "spread": 10.0, "arg": "horse"},
				{"kind": "cloth", "n": 1, "spread": 3.0, "arg": "linen"},
				{"kind": "blood", "n": 2, "spread": 4.0},
				{"kind": "net", "n": 1, "spread": 3.0, "arg": "rope"},
				{"kind": "feather", "n": 4, "spread": 5.0, "arg": "crow"},
				{"kind": "torch", "n": 1, "spread": 4.0, "arg": "guttered"},
			],
		},
	},

	{
		"id": "pilgrims",
		"stage": "road",
		"hear": "singing",
		"threat": 0,
		"linger": 0.5,
		"note": "Singing on the road to %s, forty of them on the one note and none of it good.",
		"live": [
			{"kind": "cloth", "n": 4, "spread": 6.0, "arg": "pilgrim"},
			{"kind": "basket", "n": 3, "spread": 5.0},
			{"kind": "torch", "n": 1, "spread": 4.0, "arg": "lit"},
		],
		"after": {
			## Bought every loaf in the place and went on singing. No fire: they
			## did not stop long enough to light one, and that is exactly what
			## separates this from the one who could not go on. What they leave
			## instead is the stone every pilgrim adds to every waymark they pass,
			## which means WENT BY rather than STAYED.
			"passed": [
				{"kind": "track", "n": 14, "spread": 10.0, "arg": "boot"},
				{"kind": "cairn", "n": 1, "spread": 3.0},
				{"kind": "cloth", "n": 1, "spread": 5.0, "arg": "pilgrim"},
			],
			## A woman with them mended every pot in the village. Her fire and
			## her scrap are still where she sat.
			"mended_pots": [
				{"kind": "ash", "n": 1, "spread": 2.0},
				{"kind": "stone", "n": 4, "spread": 1.8},
				{"kind": "crate", "n": 1, "spread": 3.0, "arg": "spilled"},
				{"kind": "basket", "n": 2, "spread": 3.5},
				{"kind": "char", "n": 2, "spread": 2.5},
				{"kind": "track", "n": 10, "spread": 8.0, "arg": "boot"},
			],
			## Too footsore to go on. One bed, one bowl, and one set of prints
			## that never left.
			"left_behind": [
				{"kind": "cloth", "n": 2, "spread": 3.0, "arg": "pilgrim"},
				{"kind": "basket", "n": 1, "spread": 2.5},
				{"kind": "plank", "n": 1, "spread": 2.0, "arg": "stick"},
				{"kind": "ash", "n": 1, "spread": 2.0},
				{"kind": "track", "n": 10, "spread": 9.0, "arg": "boot"},
			],
			## They took the offerings and the boots and left them the hymns.
			"robbed": [
				{"kind": "cloth", "n": 4, "spread": 6.0, "arg": "pilgrim"},
				{"kind": "basket", "n": 2, "spread": 5.0, "arg": "spilled"},
				{"kind": "crate", "n": 1, "spread": 4.0, "arg": "spilled"},
				{"kind": "track", "n": 12, "spread": 8.0, "arg": "boot"},
				{"kind": "blood", "n": 1, "spread": 4.0},
			],
		},
	},

	{
		"id": "stranger_passing",
		"stage": "place",
		"hear": "dogs",
		"threat": 0,
		"linger": 0.75,
		"note": "There is a man sat in the corner at %s that nobody has a name for, and he has not put his hood down.",
		"live": [
			{"kind": "track", "n": 6, "spread": 6.0, "arg": "boot"},
			{"kind": "cloth", "n": 1, "spread": 3.0, "arg": "linen"},
		],
		"after": {
			## Paid in old silver for a bed he never slept in. Gone before the
			## cock, and the prints only go one way.
			"old_silver": [
				{"kind": "track", "n": 8, "spread": 8.0, "arg": "boot"},
				{"kind": "cloth", "n": 1, "spread": 3.0, "arg": "linen"},
				{"kind": "basket", "n": 1, "spread": 3.0},
			],
			## Asking after the old road up the mountain. Nobody told him, and he
			## went and stood at the waymark at the foot of it anyway. The cairn is
			## the thing he was asking about; the bed he never used is not in this
			## one at all.
			"asked": [
				{"kind": "track", "n": 10, "spread": 10.0, "arg": "boot"},
				{"kind": "cairn", "n": 1, "spread": 5.0},
				{"kind": "stone", "n": 3, "spread": 4.0},
			],
			## The widow's mule and her son's boots. A cut halter and hoofprints
			## leaving in the dark.
			"stole": [
				{"kind": "track", "n": 8, "spread": 8.0, "arg": "boot"},
				{"kind": "track", "n": 6, "spread": 10.0, "arg": "hoof"},
				{"kind": "net", "n": 1, "spread": 2.5, "arg": "rope"},
				{"kind": "cloth", "n": 1, "spread": 4.0, "arg": "sack"},
				{"kind": "basket", "n": 1, "spread": 3.0, "arg": "spilled"},
			],
			## Put the miller's mare right in an evening. Took the foal.
			"horse_leech": [
				{"kind": "basket", "n": 2, "spread": 3.0},
				{"kind": "cloth", "n": 2, "spread": 3.0, "arg": "linen"},
				{"kind": "track", "n": 6, "spread": 6.0, "arg": "hoof"},
				{"kind": "ash", "n": 1, "spread": 2.0},
				{"kind": "crate", "n": 1, "spread": 3.0},
			],
		},
	},

	{
		"id": "poaching",
		"stage": "wild",
		## This kind runs eighteen to six. A jay is asleep for all of it. What is
		## awake and loud over a snare line at two in the morning is the fox
		## working it — which is also the animal in every one of the outcomes.
		"hear": "fox",
		"threat": 0,
		"linger": 2.0,
		"note": "Snare wire in the hazel above %s, set fresh and set by somebody who knows how.",
		"live": [
			{"kind": "net", "n": 2, "spread": 6.0, "arg": "snare"},
			{"kind": "post", "n": 2, "spread": 5.0},
			{"kind": "track", "n": 6, "spread": 6.0, "arg": "boot"},
		],
		"after": {
			## Pulled them all and left a note. He cannot write, so it is a
			## drawing, and it is nailed to a board.
			"snares": [
				{"kind": "net", "n": 3, "spread": 7.0, "arg": "snare"},
				{"kind": "post", "n": 2, "spread": 5.0},
				{"kind": "plank", "n": 1, "spread": 2.0},
				{"kind": "track", "n": 8, "spread": 7.0, "arg": "boot"},
			],
			## Taken with a hind over his shoulder. It went down in the pulling.
			"caught": [
				{"kind": "blood", "n": 2, "spread": 3.0},
				{"kind": "net", "n": 2, "spread": 5.0, "arg": "torn"},
				{"kind": "bone", "n": 2, "spread": 3.0, "arg": "deer"},
				{"kind": "track", "n": 10, "spread": 7.0, "arg": "boot"},
				{"kind": "track", "n": 4, "spread": 5.0, "arg": "drag"},
				{"kind": "feather", "n": 4, "spread": 5.0, "arg": "crow"},
			],
			## An arrow in the warden's leg, and nobody saw anything. What is
			## left is grey goose fletching and a long trail off the ridge.
			"warden_shot": [
				{"kind": "blood", "n": 3, "spread": 6.0, "arg": "trail"},
				{"kind": "feather", "n": 5, "spread": 4.0, "arg": "goose"},
				{"kind": "net", "n": 1, "spread": 4.0, "arg": "snare"},
				{"kind": "track", "n": 8, "spread": 8.0, "arg": "boot"},
				{"kind": "cloth", "n": 1, "spread": 3.0, "arg": "linen"},
			],
		},
	},

	{
		"id": "hunters_find",
		"stage": "wild",
		"hear": "crows",
		"threat": 1,
		"linger": 2.5,
		"note": "There is something in the thicket above %s that the crows got to first.",
		"live": [
			{"kind": "track", "n": 6, "spread": 6.0, "arg": "boot"},
			{"kind": "feather", "n": 4, "spread": 5.0, "arg": "crow"},
			## The crows are the reason anybody found it. Dropped feathers are the
			## aftermath of birds; while this is live the birds are still on it.
			{"kind": "critter", "n": 4, "spread": 8.0, "arg": "crow"},
		],
		"after": {
			## A rack you could not lift alone. The gralloch is what is left.
			"stag": [
				{"kind": "blood", "n": 3, "spread": 3.0},
				{"kind": "bone", "n": 4, "spread": 3.0, "arg": "deer"},
				{"kind": "feather", "n": 8, "spread": 5.0, "arg": "crow"},
				{"kind": "critter", "n": 3, "spread": 6.0, "arg": "crow"},
				{"kind": "track", "n": 8, "spread": 6.0, "arg": "boot"},
				{"kind": "plank", "n": 2, "spread": 3.0, "arg": "stick"},
				{"kind": "scat", "n": 2, "spread": 5.0, "arg": "fox"},
			],
			## A stone hut nobody has a name for, full of bones. Big ones.
			"old_hut": [
				{"kind": "stone", "n": 8, "spread": 4.0},
				{"kind": "bone", "n": 6, "spread": 3.0, "arg": "big"},
				{"kind": "ash", "n": 1, "spread": 2.0},
				{"kind": "char", "n": 2, "spread": 2.5},
				{"kind": "cairn", "n": 1, "spread": 3.0},
				{"kind": "track", "n": 6, "spread": 6.0, "arg": "boot"},
			],
			## Been there since the snow went, purse still on him. That is the
			## odd part, and there is no wound to look at.
			"body": [
				{"kind": "cloth", "n": 3, "spread": 3.0, "arg": "linen"},
				{"kind": "bone", "n": 4, "spread": 2.0, "arg": "man"},
				{"kind": "feather", "n": 5, "spread": 4.0, "arg": "crow"},
				{"kind": "basket", "n": 1, "spread": 2.5},
				{"kind": "track", "n": 8, "spread": 6.0, "arg": "boot"},
				{"kind": "cairn", "n": 1, "spread": 2.5},
			],
			## Carried down on a hurdle with his coat over his face.
			"bear_maul": [
				{"kind": "blood", "n": 4, "spread": 6.0, "arg": "trail"},
				{"kind": "track", "n": 5, "spread": 6.0, "arg": "bear"},
				{"kind": "scat", "n": 2, "spread": 5.0, "arg": "bear"},
				{"kind": "hurdle", "n": 1, "spread": 3.0, "arg": "broken", "layout": "line"},
				{"kind": "cloth", "n": 2, "spread": 3.0, "arg": "linen"},
				{"kind": "track", "n": 4, "spread": 5.0, "arg": "drag"},
				{"kind": "plank", "n": 1, "spread": 2.5, "arg": "stick"},
			],
		},
	},

	{
		"id": "ravens_field",
		"stage": "wild",
		## The kind, the note and every prop in it say ravens. Ringing "crows"
		## put "Crows — alarm calls nearby." on the HUD for the one incident in
		## the file that is specifically not crows.
		"hear": "ravens",
		"threat": 2,
		## Still ALARM afterwards. Whatever the birds are on is still lying in
		## that field, and two of the three outcomes are somebody being killed
		## up there recently enough that the birds have not finished.
		"threat_after": 2,
		"linger": 3.0,
		"note": "Ravens are up over the old field past %s in a sheet, and they are not settling.",
		"live": [
			{"kind": "feather", "n": 10, "spread": 8.0, "arg": "raven"},
			{"kind": "stone", "n": 5, "spread": 8.0},
			## Up in a sheet and not settling. That is the whole event, and until
			## now it was staged as dropped feathers on an empty field.
			{"kind": "critter", "n": 6, "spread": 14.0, "arg": "crow"},
		],
		"after": {
			## Hundreds of them, gone by dusk. NOBODY WENT UP TO FIND OUT, so
			## there is not one boot print in this outcome and there never will be
			## — the absence is the tell. What is up there is old: three barrow
			## cairns nobody has touched, and the birds long gone off them.
			"gathered": [
				{"kind": "feather", "n": 12, "spread": 10.0, "arg": "raven"},
				{"kind": "cairn", "n": 3, "spread": 9.0},
				{"kind": "stone", "n": 6, "spread": 9.0},
				{"kind": "bone", "n": 3, "spread": 8.0, "arg": "man"},
			],
			## A dozen goblins and two men, laid out in a row. Somebody is
			## fighting somebody up there.
			"fresh_dead": [
				{"kind": "bone", "n": 6, "spread": 6.0, "arg": "man"},
				{"kind": "blood", "n": 5, "spread": 6.0},
				{"kind": "cloth", "n": 4, "spread": 6.0, "arg": "sack"},
				{"kind": "feather", "n": 14, "spread": 8.0, "arg": "raven"},
				{"kind": "critter", "n": 5, "spread": 10.0, "arg": "crow"},
				{"kind": "plank", "n": 3, "spread": 6.0, "arg": "stick"},
				{"kind": "stone", "n": 3, "spread": 6.0},
				{"kind": "track", "n": 8, "spread": 8.0, "arg": "small"},
			],
			## Barrows opened, and the ravens sat on the spoil-heaps like they
			## are waiting to be paid.
			## The exact inverse of `gathered`: a barrow that has been OPENED has
			## no cairn left on it, it has ten stones thrown down off it, and it
			## has the boots of whoever threw them all over the spoil.
			"digging": [
				{"kind": "stone", "n": 10, "spread": 8.0},
				{"kind": "track", "n": 8, "spread": 8.0, "arg": "boot"},
				{"kind": "plank", "n": 2, "spread": 5.0},
				{"kind": "bone", "n": 5, "spread": 6.0, "arg": "man"},
				{"kind": "feather", "n": 10, "spread": 8.0, "arg": "raven"},
				{"kind": "critter", "n": 4, "spread": 10.0, "arg": "crow"},
				{"kind": "basket", "n": 1, "spread": 4.0, "arg": "spilled"},
			],
		},
	},

	## ------------------------------------------------------------- coast ---
	{
		"id": "boat_overdue",
		## Everything in this recipe is waterline — floats, nets, a sealed
		## barrel, drag marks up a beach. On "place" the anchor went out on a
		## uniform bearing eighteen to thirty-four metres from the town, which
		## put half of them in a turnip field behind the village.
		"stage": "shore",
		"hear": "gulls",
		"threat": 1,
		"linger": 2.0,
		"note": "Somebody has left a lantern burning on the stones below %s, stood facing out at the water.",
		"live": [
			{"kind": "float", "n": 5, "spread": 8.0},
			{"kind": "net", "n": 2, "spread": 6.0},
			{"kind": "torch", "n": 1, "spread": 4.0, "arg": "lit"},
			{"kind": "stone", "n": 4, "spread": 7.0},
		],
		"after": {
			## Three days late with a torn sail and a hold of cod. The whole
			## village came down to unload her: boots, a cart, baskets and every
			## gull on the coast. Gear OFF the beach and people ON it.
			"came_in": [
				{"kind": "basket", "n": 6, "spread": 5.0},
				{"kind": "crate", "n": 2, "spread": 5.0},
				{"kind": "cart", "n": 1, "spread": 6.0},
				{"kind": "track", "n": 10, "spread": 7.0, "arg": "boot"},
				{"kind": "feather", "n": 6, "spread": 6.0, "arg": "gull"},
			],
			## A mast, a chest, a boot. They know whose boat.
			"wreck": [
				{"kind": "plank", "n": 6, "spread": 9.0, "arg": "split"},
				{"kind": "post", "n": 1, "spread": 5.0},
				{"kind": "crate", "n": 1, "spread": 6.0, "arg": "spilled"},
				{"kind": "cloth", "n": 2, "spread": 7.0, "arg": "sail"},
				{"kind": "float", "n": 4, "spread": 8.0},
				{"kind": "net", "n": 1, "spread": 6.0, "arg": "torn"},
				{"kind": "feather", "n": 6, "spread": 6.0, "arg": "gull"},
			],
			## Sound as a bell. Oars shipped, lines set, nobody. Nothing here is
			## broken, which is the whole horror of it — and NOTHING here is a
			## boot print either. Somebody set that line and did not walk away
			## from it. The nets and floats run out in a line because that is what
			## "lines set" means; the oars are lying beside them.
			"empty": [
				{"kind": "net", "n": 2, "spread": 4.0, "layout": "line"},
				{"kind": "float", "n": 6, "spread": 5.0, "layout": "line"},
				{"kind": "cloth", "n": 1, "spread": 4.0, "arg": "sail"},
				{"kind": "plank", "n": 2, "spread": 3.0, "arg": "stick"},
				{"kind": "basket", "n": 2, "spread": 4.0},
			],
		},
	},

	{
		"id": "wreck_ashore",
		## The sea put it on the tideline. Staging it on a bearing from the
		## village square put a hull in somebody's beans half the time.
		"stage": "shore",
		"hear": "gulls",
		"threat": 1,
		"linger": 3.0,
		"note": "Gulls working the tideline below %s over something the sea put there in the night.",
		"live": [
			{"kind": "plank", "n": 5, "spread": 9.0, "arg": "split"},
			{"kind": "float", "n": 4, "spread": 8.0},
			{"kind": "cloth", "n": 1, "spread": 6.0, "arg": "sail"},
		],
		"after": {
			## In three barns before the reeve had his boots on. The drag marks
			## up the beach are the evidence and everyone knows it.
			"timber": [
				{"kind": "plank", "n": 6, "spread": 9.0},
				{"kind": "post", "n": 2, "spread": 7.0},
				{"kind": "track", "n": 10, "spread": 9.0, "arg": "boot"},
				{"kind": "track", "n": 6, "spread": 10.0, "arg": "drag"},
				{"kind": "float", "n": 3, "spread": 8.0},
			],
			## Wax-sealed, and no name burned on them.
			"cargo": [
				{"kind": "barrel", "n": 5, "spread": 7.0, "arg": "sealed"},
				{"kind": "plank", "n": 3, "spread": 8.0},
				{"kind": "net", "n": 1, "spread": 5.0, "arg": "rope"},
				{"kind": "track", "n": 10, "spread": 8.0, "arg": "boot"},
				{"kind": "float", "n": 3, "spread": 8.0},
				{"kind": "cloth", "n": 1, "spread": 6.0, "arg": "sail"},
			],
			## Buried above the tide line without a name. No boat missing here.
			"drowned": [
				{"kind": "cloth", "n": 3, "spread": 4.0, "arg": "linen"},
				{"kind": "bone", "n": 2, "spread": 3.0, "arg": "man"},
				{"kind": "cairn", "n": 1, "spread": 3.0},
				{"kind": "stone", "n": 5, "spread": 5.0},
				{"kind": "feather", "n": 8, "spread": 6.0, "arg": "gull"},
				{"kind": "net", "n": 1, "spread": 5.0, "arg": "torn"},
			],
			## Ribs like a boat's. They burned it where it lay and the smoke
			## was wrong.
			"beast": [
				{"kind": "bone", "n": 8, "spread": 6.0, "arg": "big"},
				{"kind": "char", "n": 5, "spread": 5.0},
				{"kind": "ash", "n": 3, "spread": 4.0},
				{"kind": "feather", "n": 10, "spread": 8.0, "arg": "gull"},
				{"kind": "stone", "n": 4, "spread": 6.0},
				{"kind": "float", "n": 2, "spread": 7.0},
			],
		},
	},

	{
		"id": "herring_run",
		## Nets, floats, a cart on the shingle and a barrel of salt. All of it
		## belongs on the waterline and none of it belongs on a bearing.
		"stage": "shore",
		"hear": "gulls",
		"threat": 0,
		"linger": 1.5,
		"note": "There are lanterns the whole length of the shore at %s and nobody has been to bed.",
		"live": [
			{"kind": "net", "n": 3, "spread": 7.0, "layout": "line"},
			{"kind": "float", "n": 8, "spread": 8.0, "layout": "line"},
			{"kind": "basket", "n": 5, "spread": 6.0},
			{"kind": "torch", "n": 2, "spread": 6.0, "arg": "lit"},
			{"kind": "cart", "n": 1, "spread": 6.0},
		],
		"after": {
			## Carting fish up the beach by lantern. Nobody complaining yet.
			"glut": [
				{"kind": "basket", "n": 6, "spread": 7.0},
				{"kind": "net", "n": 3, "spread": 7.0},
				{"kind": "float", "n": 8, "spread": 8.0},
				{"kind": "cart", "n": 1, "spread": 6.0},
				{"kind": "crate", "n": 3, "spread": 6.0},
				{"kind": "feather", "n": 10, "spread": 8.0, "arg": "gull"},
				{"kind": "track", "n": 10, "spread": 8.0, "arg": "boot"},
			],
			## Weed and two dogfish. The gear never went in the water and never
			## came out of it — no nets down the shingle, no line of floats, no
			## cart, and three gulls that could not be bothered. What IS on the
			## beach is the salt they bought for a run that did not come: three
			## barrels still sealed, sat on the stones with the empty baskets.
			"thin": [
				{"kind": "barrel", "n": 3, "spread": 5.0, "arg": "sealed"},
				{"kind": "basket", "n": 2, "spread": 5.0},
				{"kind": "stone", "n": 4, "spread": 7.0},
				{"kind": "cloth", "n": 1, "spread": 5.0, "arg": "sack"},
				{"kind": "feather", "n": 3, "spread": 6.0, "arg": "gull"},
			],
			## The other one's oars turned up at the point, which is how they
			## knew not to keep looking.
			## Nothing was landed off this one, so there is not a basket on the
			## beach. Oars, torn gear, a sail, and a stone raised above the tide.
			"boat_lost": [
				{"kind": "plank", "n": 3, "spread": 8.0, "arg": "stick"},
				{"kind": "net", "n": 2, "spread": 7.0, "arg": "torn"},
				{"kind": "float", "n": 5, "spread": 8.0},
				{"kind": "cloth", "n": 1, "spread": 6.0, "arg": "sail"},
				{"kind": "cairn", "n": 1, "spread": 4.0},
				{"kind": "feather", "n": 6, "spread": 6.0, "arg": "gull"},
			],
		},
	},

	## ------------------------------------------------------- the village ---
	{
		"id": "lost_child",
		"stage": "place",
		"hear": "voices",
		"threat": 2,
		## Three of the four outcomes end with the child indoors and asleep, and
		## the modal one has her in a hay-rick a hundred yards from her own door.
		## A cold hillside of guttered torches two days later is a sad thing to
		## walk into and not a thing to ring an alarm over.
		"threat_after": -1,
		"linger": 2.5,
		"note": "People are strung out across the hill above %s calling the one name over and over.",
		"live": [
			{"kind": "torch", "n": 4, "spread": 10.0, "arg": "lit"},
			{"kind": "track", "n": 12, "spread": 12.0, "arg": "boot"},
		],
		"after": {
			## Asleep in a hay-rick a hundred yards from her own door, with the
			## whole village out on the hill.
			"hay_rick": [
				{"kind": "cloth", "n": 3, "spread": 4.0, "arg": "sack"},
				{"kind": "track", "n": 14, "spread": 12.0, "arg": "boot"},
				{"kind": "torch", "n": 3, "spread": 8.0, "arg": "guttered"},
				{"kind": "basket", "n": 1, "spread": 3.0},
			],
			## The dog brought him home, both of them soaked.
			## Tight on the dog, wide on the boots: the dog line runs BESIDE the
			## search line and comes back down it, which is the one thing that
			## tells this from the child found cold under a spruce at dawn.
			"dog_brought": [
				{"kind": "track", "n": 12, "spread": 10.0, "arg": "boot"},
				{"kind": "track", "n": 14, "spread": 6.0, "arg": "dog"},
				{"kind": "torch", "n": 2, "spread": 7.0, "arg": "guttered"},
			],
			## Under a spruce at first light, blue with cold. Breathing.
			"found_cold": [
				{"kind": "cloth", "n": 3, "spread": 4.0, "arg": "linen"},
				{"kind": "track", "n": 14, "spread": 12.0, "arg": "boot"},
				{"kind": "torch", "n": 4, "spread": 8.0, "arg": "guttered"},
				{"kind": "post", "n": 1, "spread": 3.0},
				{"kind": "ash", "n": 1, "spread": 3.0},
			],
			## Three days, and they have stopped calling. Nobody says why.
			"not_found": [
				{"kind": "track", "n": 16, "spread": 14.0, "arg": "boot"},
				{"kind": "torch", "n": 5, "spread": 10.0, "arg": "guttered"},
				{"kind": "cloth", "n": 2, "spread": 8.0, "arg": "linen"},
				{"kind": "cairn", "n": 1, "spread": 5.0},
				{"kind": "feather", "n": 4, "spread": 8.0, "arg": "crow"},
				{"kind": "plank", "n": 1, "spread": 4.0, "arg": "stick"},
			],
		},
	},

	{
		"id": "bell_wrong",
		"stage": "place",
		"hear": "bell",
		"threat": 2,
		## The bell stopped. Whatever it meant, it is not ringing now, and the
		## aftermath of a bell is silence by definition.
		"threat_after": -1,
		"linger": 1.0,
		"note": "The bell at %s is ringing a peal that is not any peal, and it has not stopped.",
		"live": [
			{"kind": "torch", "n": 3, "spread": 8.0, "arg": "lit"},
			{"kind": "track", "n": 10, "spread": 8.0, "arg": "boot"},
		],
		"after": {
			## The town came out in its shirt. It was the sexton, drunk, and
			## there is his cask lying on its side to prove it.
			"sexton": [
				{"kind": "track", "n": 12, "spread": 8.0, "arg": "boot"},
				{"kind": "torch", "n": 2, "spread": 6.0, "arg": "guttered"},
				{"kind": "barrel", "n": 1, "spread": 3.0, "arg": "stove"},
				{"kind": "cloth", "n": 1, "spread": 4.0, "arg": "linen"},
			],
			## Three and a pause and three, and nobody admitting they know what
			## that means.
			"wrong_peal": [
				{"kind": "track", "n": 10, "spread": 8.0, "arg": "boot"},
				{"kind": "torch", "n": 3, "spread": 6.0, "arg": "guttered"},
				{"kind": "cairn", "n": 1, "spread": 3.0},
				{"kind": "stone", "n": 3, "spread": 5.0},
			],
			## No mistake. Torches on the ridge road, and small prints that came
			## a long way down and then turned around.
			"real": [
				{"kind": "track", "n": 12, "spread": 9.0, "arg": "boot"},
				{"kind": "torch", "n": 4, "spread": 8.0, "arg": "guttered"},
				{"kind": "ash", "n": 2, "spread": 8.0},
				{"kind": "plank", "n": 2, "spread": 5.0, "arg": "stick"},
				{"kind": "track", "n": 8, "spread": 12.0, "arg": "small"},
			],
		},
	},

	{
		"id": "fair",
		"stage": "place",
		"hear": "crowd",
		"threat": 0,
		"linger": 1.5,
		"note": "Drums and a fiddle at %s, and a deal more smoke than a village that size makes.",
		"live": [
			{"kind": "cloth", "n": 4, "spread": 8.0, "arg": "sail", "y": 1.2},
			{"kind": "crate", "n": 4, "spread": 7.0},
			{"kind": "barrel", "n": 4, "spread": 7.0},
			{"kind": "torch", "n": 3, "spread": 8.0, "arg": "lit"},
			{"kind": "basket", "n": 4, "spread": 6.0},
		],
		"after": {
			## The best in years, and the ale held out past dark.
			"good": [
				{"kind": "ash", "n": 2, "spread": 6.0},
				{"kind": "barrel", "n": 4, "spread": 7.0, "arg": "stove"},
				{"kind": "crate", "n": 2, "spread": 6.0},
				{"kind": "cloth", "n": 2, "spread": 7.0, "arg": "sail"},
				{"kind": "track", "n": 16, "spread": 12.0, "arg": "boot"},
				{"kind": "basket", "n": 3, "spread": 6.0},
			],
			## Two villages in the horse pond and the reeve's teeth in the mud.
			"brawl": [
				{"kind": "barrel", "n": 3, "spread": 6.0, "arg": "stove"},
				{"kind": "plank", "n": 5, "spread": 7.0, "arg": "split"},
				{"kind": "crate", "n": 2, "spread": 6.0, "arg": "spilled"},
				{"kind": "blood", "n": 2, "spread": 5.0},
				{"kind": "cloth", "n": 3, "spread": 7.0, "arg": "sack"},
				{"kind": "track", "n": 16, "spread": 12.0, "arg": "boot"},
				{"kind": "basket", "n": 2, "spread": 5.0, "arg": "spilled"},
			],
			## Worked it like a field of barley. Half the town home with empty
			## pockets and a headache, and cut purse-strings underfoot.
			"cutpurses": [
				{"kind": "track", "n": 18, "spread": 12.0, "arg": "boot"},
				{"kind": "basket", "n": 3, "spread": 7.0, "arg": "spilled"},
				{"kind": "cloth", "n": 2, "spread": 7.0, "arg": "sack"},
				{"kind": "net", "n": 1, "spread": 5.0, "arg": "rope"},
				{"kind": "barrel", "n": 2, "spread": 6.0},
				{"kind": "crate", "n": 2, "spread": 6.0},
				{"kind": "ash", "n": 1, "spread": 4.0},
			],
		},
	},
]


## ================================ Lookup ==================================


static func recipe_for(kind_id: String) -> Dictionary:
	## A deep copy, not the const. Callers get to write on what they are
	## handed, and nothing a caller does can reach back into the catalogue.
	for r in RECIPES:
		var rd := r as Dictionary
		if String(rd.get("id", "")) == kind_id:
			return rd.duplicate(true)
	return {}


static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for r in RECIPES:
		out.append(String((r as Dictionary).get("id", "")))
	out.sort()
	return out


static func props_for(kind_id: String, outcome_id: String, live: bool) -> Array:
	## The prop specs to stage. `live` picks the event-in-progress dressing;
	## otherwise the outcome's aftermath, and an outcome nobody wrote a scene
	## for is an empty stage rather than a crash — the Chronicle can add
	## outcomes faster than this file can be dressed.
	var rec := recipe_for(kind_id)
	if rec.is_empty():
		return []
	if live:
		return (rec.get("live", []) as Array).duplicate(true)
	var after := rec.get("after", {}) as Dictionary
	if not after.has(outcome_id):
		return []
	return (after[outcome_id] as Array).duplicate(true)


static func note_for(kind_id: String, place: String) -> String:
	## The one line the player gets, once, on walking into earshot. Every note
	## holds at most one "%s"; a note with none is a line about the thing
	## rather than the village, and formatting it anyway would be a runtime
	## error for no gain.
	var rec := recipe_for(kind_id)
	if rec.is_empty():
		return ""
	var note := String(rec.get("note", ""))
	if note.is_empty():
		return ""
	if note.count("%s") == 1:
		return note % place
	return note


static func hear_for(kind_id: String) -> String:
	var rec := recipe_for(kind_id)
	return String(rec.get("hear", "")) if not rec.is_empty() else ""


static func threat_for(kind_id: String) -> int:
	## -1 means the incident makes no noise worth ringing the Telegraph over.
	## A murrain is silent; a fire is not.
	var rec := recipe_for(kind_id)
	return int(rec.get("threat", -1)) if not rec.is_empty() else -1


static func threat_after_for(kind_id: String) -> int:
	## What the AFTERMATH is worth ringing at. Absent means one step below the
	## live threat and never above WARY: the thing has happened, the shouting
	## has stopped, and the only honest reason to ring a 2 over cold ground is
	## that the ground is still dangerous. Kept here rather than in the caller
	## so there is one definition of the default instead of two.
	var rec := recipe_for(kind_id)
	if rec.is_empty():
		return -1
	return int(rec.get("threat_after", mini(int(rec.get("threat", -1)), 1)))


static func linger_for(kind_id: String) -> float:
	var rec := recipe_for(kind_id)
	return float(rec.get("linger", 0.0)) if not rec.is_empty() else 0.0


static func stage_for(kind_id: String) -> String:
	var rec := recipe_for(kind_id)
	return String(rec.get("stage", "place")) if not rec.is_empty() else "place"


## =============================== Self-audit ===============================


static func problems() -> PackedStringArray:
	## Every promise this file makes, listed as the ones it is breaking. Empty
	## means clean, and the Incident Director asserts on it at bind time —
	## which is far kinder than a recipe keyed on an outcome id that was
	## renamed in the catalogue two months ago and stages nothing at all,
	## silently, forever.
	var out := PackedStringArray()
	var kind_ids := ChronicleEvents.ids()
	var seen := {}

	for r in RECIPES:
		var rec := r as Dictionary
		var id := String(rec.get("id", ""))
		var where := "recipe '%s'" % id

		if id.is_empty():
			out.append("a recipe has no id")
			continue
		if seen.has(id):
			out.append("%s: duplicate recipe id" % where)
		seen[id] = true

		for key in ["stage", "live", "after", "hear", "threat", "note", "linger"]:
			if not rec.has(key):
				out.append("%s: missing '%s'" % [where, key])

		var kind := ChronicleEvents.by_id(id)
		if kind.is_empty():
			out.append("%s: not a ChronicleEvents kind id" % where)
			continue

		## The anchor axis has to agree with the catalogue, or a road incident
		## gets staged in the middle of a village and the prose lies.
		var stage := String(rec.get("stage", ""))
		var scope := String(kind.get("scope", ""))
		if not ["place", "road", "wild", "shore"].has(stage):
			out.append("%s: stage '%s' must be place|road|wild|shore" % [where, stage])
		elif stage == "shore":
			## The one exemption to stage == scope. "shore" is a REFINEMENT of
			## "place", not a fourth scope: the Chronicle has no idea where the
			## water is and never will, so the catalogue still calls these place
			## events and the Director walks out to the waterline from there.
			## A shore recipe on a road or wild kind is still an error.
			if scope != "place":
				out.append("%s: stage 'shore' refines 'place', but the catalogue scope is '%s'"
					% [where, scope])
		elif stage != scope:
			out.append("%s: stage '%s' disagrees with catalogue scope '%s'"
				% [where, stage, scope])

		if String(rec.get("hear", "")).is_empty():
			out.append("%s: hear is empty; the player learns of this by ear or not at all" % where)

		var threat := int(rec.get("threat", -99))
		if threat < -1 or threat > 3:
			out.append("%s: threat %d outside -1..3" % [where, threat])

		## Optional, and absent is the common case — but a typo in it would ring
		## the wrong bell for a whole release without anything crashing.
		if rec.has("threat_after"):
			var ta := int(rec.get("threat_after", -99))
			if ta < -1 or ta > 3:
				out.append("%s: threat_after %d outside -1..3" % [where, ta])

		var linger := float(rec.get("linger", -1.0))
		if linger < 0.0 or not is_finite(linger):
			out.append("%s: linger %s must be >= 0" % [where, linger])

		_check_note(out, where, String(rec.get("note", "")))

		var live := rec.get("live", []) as Array
		if live.is_empty():
			out.append("%s: no live props; an active event must be visible" % where)
		for i in live.size():
			_check_spec(out, "%s live[%d]" % [where, i], live[i])

		var after := rec.get("after", {}) as Dictionary
		var outs := kind.get("outcomes", []) as Array
		var real_outcomes := {}
		for o in outs:
			real_outcomes[String((o as Dictionary).get("id", ""))] = true
		for key in after.keys():
			var oid := String(key)
			if not real_outcomes.has(oid):
				out.append("%s: after key '%s' is not an outcome of that kind" % [where, oid])
			var arr = after[key]
			if not (arr is Array):
				out.append("%s/%s: after value is not an Array" % [where, oid])
				continue
			var specs := arr as Array
			if specs.is_empty():
				out.append("%s/%s: aftermath has no props" % [where, oid])
			for i in specs.size():
				_check_spec(out, "%s/%s[%d]" % [where, oid, i], specs[i])
		## An outcome with no aftermath is an outcome the player can never
		## read off the ground, which is the entire point of the file.
		for oid in real_outcomes.keys():
			if not after.has(oid):
				out.append("%s: outcome '%s' has no aftermath" % [where, String(oid)])

	for kid in kind_ids:
		if not seen.has(String(kid)):
			out.append("kind '%s' has no recipe" % String(kid))

	## A prop kind nobody stages is a builder nobody is testing.
	var used := {}
	for r in RECIPES:
		var rec := r as Dictionary
		for spec in (rec.get("live", []) as Array):
			used[String((spec as Dictionary).get("kind", ""))] = true
		for key in (rec.get("after", {}) as Dictionary).keys():
			for spec in ((rec.get("after", {}) as Dictionary)[key] as Array):
				used[String((spec as Dictionary).get("kind", ""))] = true
	for pk in PROP_KINDS:
		if not used.has(pk):
			out.append("prop kind '%s' is in PROP_KINDS but no recipe stages it" % pk)
		## "critter" is the one prop this file cannot build out of boxes. It is
		## a live animal, the WildlifeDirector owns every one of those, and the
		## Incident Director routes the spec straight to `spawn_one` without
		## ever asking `build_prop` for it. Holding it to the geometry sweep
		## would mean either a fake bird in the Kit that nothing ever renders,
		## or a permanent entry in problems(). It is exempt on purpose.
		if pk == "critter":
			continue
		## And a prop kind with no builder would stage an empty node forever.
		var probe := build_prop({"kind": pk}, 0, 0.5)
		if probe == null:
			out.append("prop kind '%s' built nothing" % pk)
		else:
			if probe.get_child_count() == 0:
				out.append("prop kind '%s' has no builder (no geometry)" % pk)
			probe.free()

	## Every arg the table allows has to build something too — that is the
	## half of the check the kind sweep above cannot see, and it is where
	## `track: "wolf"` had been hiding.
	for pk in PROP_ARGS.keys():
		var pks := String(pk)
		if pks == "critter":
			continue
		for a in (PROP_ARGS[pk] as Array):
			var probe2 := build_prop({"kind": pks, "arg": String(a)}, 0, 0.5)
			if probe2 == null or probe2.get_child_count() == 0:
				out.append("prop '%s' arg '%s' builds nothing" % [pks, String(a)])
			if probe2 != null:
				probe2.free()

	return out


static func _check_note(out: PackedStringArray, where: String, note: String) -> void:
	if note.is_empty():
		out.append("%s: note is empty" % where)
		return
	if note.count("%s") > 1:
		out.append("%s: note holds more than one %%s" % where)
	if note.count("%") != note.count("%s"):
		out.append("%s: note holds a stray %% that will not format" % where)
	## House prose rules, enforced rather than hoped for. A line read at two in
	## the morning in a dark wood does not shout and does not address anybody.
	if note.contains("!"):
		out.append("%s: note has an exclamation mark" % where)
	if not note.ends_with("."):
		out.append("%s: note does not end in a full stop" % where)
	for w in note.to_lower().replace(",", " ").replace(".", " ").split(" ", false):
		if String(w) == "you" or String(w) == "your":
			out.append("%s: note addresses the player directly" % where)
			break


static func _check_spec(out: PackedStringArray, where: String, raw: Variant) -> void:
	if not (raw is Dictionary):
		out.append("%s: prop spec is not a Dictionary" % where)
		return
	var spec := raw as Dictionary
	var kind := String(spec.get("kind", ""))
	if not PROP_KINDS.has(kind):
		out.append("%s: prop kind '%s' is not in PROP_KINDS" % [where, kind])
	## The arg, which nothing checked until the 2026-09-07 pass. Four recipes
	## had been naming args with no builder branch behind them, and because an
	## unmatched arg falls through to the default the props still built — just
	## as the wrong animal, silently, for as long as anybody had been looking.
	var arg := String(spec.get("arg", "")) if spec.get("arg", "") is String else ""
	if PROP_ARGS.has(kind):
		var allowed := PROP_ARGS[kind] as Array
		if not allowed.has(arg):
			out.append("%s: prop '%s' arg '%s' is not one of %s"
				% [where, kind, arg, str(allowed)])
	elif PROP_KINDS.has(kind):
		out.append("%s: prop kind '%s' has no PROP_ARGS entry" % [where, kind])
	var layout := String(spec.get("layout", ""))
	if not ["", "line"].has(layout):
		out.append("%s: layout '%s' must be \"\" or \"line\"" % [where, layout])
	if int(spec.get("n", 1)) < 1:
		out.append("%s: n must be >= 1" % where)
	var spread := float(spec.get("spread", 2.0))
	if spread < 0.0 or not is_finite(spread):
		out.append("%s: spread %s must be >= 0" % [where, spread])
	var y := float(spec.get("y", 0.0))
	if not is_finite(y):
		out.append("%s: y is not finite" % where)
	if not (spec.get("arg", "") is String):
		out.append("%s: arg must be a String" % where)
	for key in spec.keys():
		if not ["kind", "n", "spread", "arg", "y", "layout"].has(String(key)):
			out.append("%s: unknown spec key '%s'" % [where, String(key)])


## ============================ Building things =============================
##
## Everything below is a pure function of (spec, index, unit). `unit` is the
## caller's deterministic roll in [0,1) — a hash of (world_seed, uid, salt) —
## and `_wob` spreads that one number into as many uncorrelated-looking ones as
## a prop needs. Nothing in here calls randf(), and nothing in here ever will:
## the whole idempotency promise of the Incident Director rests on a restaged
## incident being geometrically identical to the one that was struck.


static func _wob(unit: float, index: int, salt: int) -> float:
	## One number in, one number out, same answer every time on every machine.
	var x := absf(unit) * 1000003.0 + float(index) * 7919.0 + float(salt) * 104729.0
	var s := sin(x * 12.9898) * 43758.5453
	return s - floor(s)


static func _spanned(unit: float, index: int, salt: int, lo: float, hi: float) -> float:
	return lerpf(lo, hi, _wob(unit, index, salt))


static func _col(key: String, fallback := "stone") -> Color:
	return PALETTE.get(key, PALETTE[fallback])


static func _mat(c: Color, two_sided := false, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	## Per-vertex shading is what the rest of Myrkfell renders with; a prop lit
	## per-pixel next to a per-vertex tree reads as a different game.
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	if two_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m


static func _box(sx: float, sy: float, sz: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(sx, sy, sz)
	return m


static func _cyl(r: float, h: float, sides := 6) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = sides
	m.rings = 1
	return m


static func _tapered(rt: float, rb: float, h: float, sides := 8) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	m.radial_segments = sides
	m.rings = 1
	return m


static func _sph(r: float, sides := 6, rings := 3) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = sides
	m.rings = rings
	return m


static func _quad(w: float, h: float) -> QuadMesh:
	var m := QuadMesh.new()
	m.size = Vector2(w, h)
	return m


static func _add(root: Node3D, mesh: Mesh, mat: StandardMaterial3D, pos: Vector3,
		rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	root.add_child(mi)
	return mi


static func _decal(root: Node3D, w: float, h: float, c: Color, pos: Vector3, yaw: float,
		lift := 0.0) -> MeshInstance3D:
	## A flat patch on the ground: a quad laid down, lifted a hair so it does
	## not fight the terrain for the same depth.
	var p := pos
	p.y += DECAL_Y + lift
	return _add(root, _quad(w, h), _mat(c, true), p, Vector3(-PI * 0.5, yaw, 0.0))


static func build_prop(spec: Dictionary, index: int, unit: float) -> Node3D:
	## The whole prop cupboard behind one door. `spec` is a recipe entry,
	## `index` is which of the `n` copies this is, `unit` is the caller's roll.
	## An unknown kind returns an empty Node3D rather than null — the Director
	## will parent it, see nothing, and carry on — and `problems()` catches the
	## missing builder long before a player does.
	var kind := String(spec.get("kind", ""))
	var arg := String(spec.get("arg", ""))
	var u := clampf(unit, 0.0, 0.999999)
	var root := Node3D.new()
	root.name = "Prop_%s_%d" % [kind if not kind.is_empty() else "none", index]
	match kind:
		"post": _b_post(root, arg, index, u)
		"plank": _b_plank(root, arg, index, u)
		"log": _b_log(root, arg, index, u)
		"hurdle": _b_hurdle(root, arg, index, u)
		"crate": _b_crate(root, arg, index, u)
		"barrel": _b_barrel(root, arg, index, u)
		"cart": _b_cart(root, arg, index, u)
		"cloth": _b_cloth(root, arg, index, u)
		"stone": _b_stone(root, arg, index, u)
		"ash": _b_ash(root, arg, index, u)
		"char": _b_char(root, arg, index, u)
		"blood": _b_blood(root, arg, index, u)
		"bone": _b_bone(root, arg, index, u)
		"fleece": _b_fleece(root, arg, index, u)
		"basket": _b_basket(root, arg, index, u)
		"net": _b_net(root, arg, index, u)
		"float": _b_float(root, arg, index, u)
		"torch": _b_torch(root, arg, index, u)
		"cairn": _b_cairn(root, arg, index, u)
		"track": _b_track(root, arg, index, u)
		"scat": _b_scat(root, arg, index, u)
		"feather": _b_feather(root, arg, index, u)
	root.rotation.y = u * TAU
	root.position.y = float(spec.get("y", 0.0))
	return root


## ---------------------------------------------------------- timber ---


static func _b_post(root: Node3D, arg: String, i: int, u: float) -> void:
	var burnt := arg == "burnt"
	var cut := arg == "cut"
	## Snapped is not cut. A tree taken off in a gale breaks low and leaves a
	## splintered stump with three or four spikes of heartwood standing out of
	## it; a sapling taken off with a hatchet leaves one flat pale face. From
	## fifteen metres the difference is the spikes, so that is what gets built.
	var snapped := arg == "snapped"
	var h := _spanned(u, i, 1, 1.05, 1.55) - (0.45 if burnt else 0.0)
	if snapped:
		h = _spanned(u, i, 21, 0.45, 0.9)
	var lean := deg_to_rad(_spanned(u, i, 2, -16.0, 16.0))
	var mat := _mat(_col("char") if burnt else _col("wood"))
	_add(root, _cyl(0.075, h, 6), mat, Vector3(0.0, h * 0.5, 0.0),
		Vector3(lean, 0.0, lean * 0.55))
	if cut:
		## A sapling taken off at an angle with something blunt: the pale cut
		## face is the only reason anyone notices it at all.
		_add(root, _box(0.17, 0.05, 0.17), _mat(_col("wood_pale")),
			Vector3(sin(lean) * h * 0.5, h, sin(lean * 0.55) * h * 0.5),
			Vector3(0.35, _wob(u, i, 3) * TAU, 0.25))
	if snapped:
		for k in 3:
			var sp := _spanned(u, i, 22 + k, 0.16, 0.38)
			var sa := _wob(u, i, 25 + k) * TAU
			_add(root, _box(0.035, sp, 0.035), _mat(_col("wood_pale")),
				Vector3(cos(sa) * 0.045, h + sp * 0.45, sin(sa) * 0.045),
				Vector3(deg_to_rad(_spanned(u, i, 28 + k, -14.0, 14.0)), sa,
					deg_to_rad(_spanned(u, i, 31 + k, -14.0, 14.0))))
	if burnt:
		_add(root, _cyl(0.055, 0.28, 5), _mat(_col("char")),
			Vector3(_spanned(u, i, 4, -0.35, 0.35), 0.14, _spanned(u, i, 5, -0.35, 0.35)),
			Vector3(1.35, _wob(u, i, 6) * TAU, 0.0))


static func _b_plank(root: Node3D, arg: String, i: int, u: float) -> void:
	if arg == "stick":
		## A shepherd's stick, an oar, a spear shaft. One cylinder, lying where
		## it was dropped, and it does more work in an aftermath than any of
		## the big props.
		var l := _spanned(u, i, 1, 0.9, 1.5)
		_add(root, _cyl(0.032, l, 5), _mat(_col("wood")), Vector3(0.0, 0.05, 0.0),
			Vector3(0.0, _wob(u, i, 2) * TAU, PI * 0.5))
		return
	var c := _col("char") if arg == "charred" else _col("wood")
	var len_a := _spanned(u, i, 3, 1.1, 1.7)
	var tilt := deg_to_rad(_spanned(u, i, 4, -9.0, 9.0))
	if arg == "split":
		## Broken, not sawn: two unequal halves that no longer line up.
		var a := len_a * _spanned(u, i, 5, 0.4, 0.62)
		var b := len_a - a
		_add(root, _box(a, 0.055, 0.19), _mat(c), Vector3(-a * 0.5, 0.06, 0.0),
			Vector3(tilt, 0.0, deg_to_rad(_spanned(u, i, 6, -6.0, 6.0))))
		_add(root, _box(b, 0.055, 0.19), _mat(c),
			Vector3(b * 0.5 + 0.06, 0.055, _spanned(u, i, 7, -0.18, 0.18)),
			Vector3(tilt, deg_to_rad(_spanned(u, i, 8, -28.0, 28.0)), 0.0))
		_add(root, _box(0.1, 0.05, 0.17), _mat(_col("wood_pale")),
			Vector3(0.0, 0.06, 0.0), Vector3(0.0, deg_to_rad(14.0), 0.0))
	else:
		_add(root, _box(len_a, 0.055, 0.2), _mat(c), Vector3(0.0, 0.06, 0.0),
			Vector3(tilt, 0.0, deg_to_rad(_spanned(u, i, 9, -5.0, 5.0))))


static func _b_log(root: Node3D, arg: String, i: int, u: float) -> void:
	## A tree that is DOWN. `post` is a vertical cylinder and no amount of
	## leaning makes it a felled spruce across a road — a storm that took the
	## barn out and left six fence posts standing was the read from fifteen
	## metres, and it was the wrong one. This is one three-to-five metre
	## tapered trunk lying on its side with two limb stubs still on it, which
	## is the shape everybody recognises without being told.
	var l := _spanned(u, i, 1, 3.0, 5.0)
	var rb := _spanned(u, i, 2, 0.19, 0.29)
	var rt := rb * _spanned(u, i, 3, 0.5, 0.72)
	var c := _col("char") if arg == "charred" else _col("wood")
	var mat := _mat(c)
	## Rolled a little off true and lying at a slight angle to its own axis,
	## because a trunk that came down in a gale did not land square.
	var roll := deg_to_rad(_spanned(u, i, 4, -7.0, 7.0))
	_add(root, _tapered(rt, rb, l, 8), mat, Vector3(0.0, rb * 0.92, 0.0),
		Vector3(roll, 0.0, PI * 0.5))
	for k in 2:
		var along := _spanned(u, i, 5 + k, -0.34, 0.34) * l
		var limb := _spanned(u, i, 7 + k, 0.5, 1.0)
		var out_a := _wob(u, i, 9 + k) * TAU
		_add(root, _cyl(rb * 0.3, limb, 5), mat,
			Vector3(along + cos(out_a) * limb * 0.25, rb * 1.3, sin(out_a) * limb * 0.45),
			Vector3(deg_to_rad(_spanned(u, i, 11 + k, 58.0, 104.0)), out_a,
				deg_to_rad(_spanned(u, i, 13 + k, 55.0, 88.0))))
	## The butt end, sawn or torn, pale against everything else on the ground.
	_add(root, _cyl(rb * 0.97, 0.045, 8), _mat(_col("char") if arg == "charred" else _col("wood_pale")),
		Vector3(-l * 0.5 - 0.02, rb * 0.92, 0.0), Vector3(0.0, 0.0, PI * 0.5))


static func _b_hurdle(root: Node3D, arg: String, i: int, u: float) -> void:
	## Four boxes that read as a hurdle. Two uprights, three rails. That is the
	## whole trick, and at fifteen metres in bad light it is enough.
	var broken := arg == "broken"
	var wood := _mat(_col("wood"))
	var span := _spanned(u, i, 1, 1.7, 2.2)
	var h := 1.05
	_add(root, _cyl(0.06, h, 5), wood, Vector3(-span * 0.5, h * 0.5, 0.0))
	if broken:
		## The post that took the weight is over at forty-odd degrees and the
		## middle rail is two stubs. That gap is the story.
		var lean := deg_to_rad(_spanned(u, i, 2, 38.0, 62.0))
		_add(root, _cyl(0.06, h, 5), wood,
			Vector3(span * 0.5, cos(lean) * h * 0.5, sin(lean) * h * 0.5),
			Vector3(lean, 0.0, 0.0))
		for r in 3:
			var ry := 0.3 + float(r) * 0.3
			if r == 1:
				var stub := span * _spanned(u, i, 3 + r, 0.28, 0.42)
				_add(root, _box(stub, 0.05, 0.06), wood,
					Vector3(-span * 0.5 + stub * 0.5, ry, 0.0),
					Vector3(0.0, 0.0, deg_to_rad(-8.0)))
				_add(root, _box(stub * 0.7, 0.05, 0.06), wood,
					Vector3(span * 0.18, ry - 0.22, 0.24),
					Vector3(0.4, deg_to_rad(31.0), deg_to_rad(24.0)))
				_add(root, _box(0.08, 0.05, 0.055), _mat(_col("wood_pale")),
					Vector3(-span * 0.5 + stub, ry, 0.0))
			else:
				_add(root, _box(span * 0.92, 0.05, 0.06), wood,
					Vector3(0.0, ry, sin(lean) * ry * 0.35),
					Vector3(deg_to_rad(_spanned(u, i, 8 + r, -7.0, 7.0)), 0.0, 0.0))
	else:
		_add(root, _cyl(0.06, h, 5), wood, Vector3(span * 0.5, h * 0.5, 0.0))
		for r in 3:
			_add(root, _box(span, 0.05, 0.06), wood,
				Vector3(0.0, 0.3 + float(r) * 0.3, 0.0),
				Vector3(deg_to_rad(_spanned(u, i, 11 + r, -4.0, 4.0)), 0.0, 0.0))


static func _b_crate(root: Node3D, arg: String, i: int, u: float) -> void:
	var body := Node3D.new()
	root.add_child(body)
	var s := _spanned(u, i, 1, 0.44, 0.58)
	var wood := _mat(_col("wood"))
	var pale := _mat(_col("wood_pale"))
	_add(body, _box(s, s, s), wood, Vector3(0.0, s * 0.5, 0.0))
	for b in 2:
		var yy := s * (0.24 + float(b) * 0.52)
		_add(body, _box(s * 1.04, 0.05, s * 1.04), pale, Vector3(0.0, yy, 0.0))
	if arg == "spilled":
		body.rotation = Vector3(0.0, _wob(u, i, 2) * TAU, deg_to_rad(_spanned(u, i, 3, 72.0, 104.0)))
		body.position = Vector3(0.0, s * 0.06, 0.0)
		## Lid off and a handful of whatever was in it, out on the ground.
		_add(root, _box(s * 0.95, 0.04, s * 0.95), pale,
			Vector3(s * 0.9, 0.03, s * 0.2), Vector3(0.0, _wob(u, i, 4) * TAU, deg_to_rad(6.0)))
		for k in 3:
			_add(root, _sph(0.07, 5, 2), _mat(_col("sack")),
				Vector3(_spanned(u, i, 5 + k, 0.3, 1.1), 0.06, _spanned(u, i, 8 + k, -0.5, 0.5)),
				Vector3.ZERO, Vector3(1.0, 0.6, 1.0))


static func _b_barrel(root: Node3D, arg: String, i: int, u: float) -> void:
	var body := Node3D.new()
	root.add_child(body)
	var h := _spanned(u, i, 1, 0.62, 0.8)
	var r := h * 0.38
	var wood := _mat(_col("wood"))
	var iron := _mat(_col("iron"))
	_add(body, _cyl(r, h, 8), wood, Vector3(0.0, h * 0.5, 0.0))
	for b in 2:
		_add(body, _cyl(r * 1.06, 0.055, 8), iron, Vector3(0.0, h * (0.24 + float(b) * 0.52), 0.0))
	match arg:
		"sealed":
			## Wax-sealed and nobody's name burned on it. A pale lid, and that
			## is the entire tell.
			_add(body, _cyl(r * 0.92, 0.05, 8), _mat(_col("linen")), Vector3(0.0, h + 0.02, 0.0))
		"stove":
			## On its side with staves sprung. Drunk, wrecked or emptied.
			body.rotation = Vector3(0.0, _wob(u, i, 2) * TAU, PI * 0.5)
			body.position = Vector3(0.0, r, 0.0)
			for k in 2:
				_add(root, _box(h * 0.6, 0.04, 0.11), wood,
					Vector3(_spanned(u, i, 3 + k, -0.7, 0.7), 0.04, _spanned(u, i, 5 + k, -0.6, 0.6)),
					Vector3(0.0, _wob(u, i, 7 + k) * TAU, 0.0))


static func _b_cart(root: Node3D, arg: String, i: int, u: float) -> void:
	## A two-wheeled cart: a bed, two side boards, two wheels and a pair of
	## shafts. Tipped, it is the same six boxes rolled onto one edge, which is
	## exactly what a cart in a river looks like from the bank.
	##
	## Every number in here used to be a literal, so the only cart that varied
	## with the roll was a tipped one — sixteen recipes stage carts and
	## `caravan_in` puts two of them six metres apart, byte for byte identical,
	## which reads as one object rendered twice. A cart is a hand-built thing;
	## no two are the same length and no two wheels are the same height.
	var body := Node3D.new()
	root.add_child(body)
	var wood := _mat(_col("wood"))
	var iron := _mat(_col("iron"))
	var bed_l := _spanned(u, i, 3, 1.72, 2.18)
	var bed_w := _spanned(u, i, 4, 0.88, 1.08)
	var wheel_r := _spanned(u, i, 5, 0.38, 0.49)
	var side_h := _spanned(u, i, 6, 0.26, 0.42)
	var shaft_lean := deg_to_rad(_spanned(u, i, 7, -12.0, -2.0))
	var bed_y := wheel_r + 0.16
	_add(body, _box(bed_l, 0.16, bed_w), wood, Vector3(0.0, bed_y, 0.0))
	for s in 2:
		var z := bed_w * 0.48 * (1.0 if s == 0 else -1.0)
		_add(body, _box(bed_l, side_h, 0.06), wood, Vector3(0.0, bed_y + side_h * 0.7, z))
	for w in 2:
		var z2 := (bed_w * 0.5 + 0.06) * (1.0 if w == 0 else -1.0)
		_add(body, _cyl(wheel_r, 0.09, 8), wood, Vector3(0.05, wheel_r, z2),
			Vector3(PI * 0.5, 0.0, 0.0))
		_add(body, _cyl(wheel_r * 0.2, 0.11, 6), iron, Vector3(0.05, wheel_r, z2),
			Vector3(PI * 0.5, 0.0, 0.0))
	for s2 in 2:
		var z3 := bed_w * 0.35 * (1.0 if s2 == 0 else -1.0)
		_add(body, _box(bed_l * 0.59, 0.07, 0.07), wood,
			Vector3(bed_l * 0.74, bed_y - 0.12, z3), Vector3(0.0, 0.0, shaft_lean))
	if arg == "tipped":
		body.rotation = Vector3(deg_to_rad(_spanned(u, i, 1, 62.0, 96.0)), 0.0,
			deg_to_rad(_spanned(u, i, 2, -14.0, 14.0)))
		body.position = Vector3(0.0, -0.32, 0.0)


## ---------------------------------------------------------- fabric ---


static func _b_cloth(root: Node3D, arg: String, i: int, u: float) -> void:
	## Sacking, linen, a pilgrim's cloak, a scrap of sail. Two or three quads
	## folded across each other; the fold is what stops it reading as a poster
	## lying in a field.
	var c := _col(arg if PALETTE.has(arg) else "sack")
	var mat := _mat(c, true)
	var w := _spanned(u, i, 1, 0.7, 1.25)
	_add(root, _quad(w, w * 0.8), mat, Vector3(0.0, DECAL_Y + 0.01, 0.0),
		Vector3(-PI * 0.5 + deg_to_rad(_spanned(u, i, 2, -8.0, 8.0)), _wob(u, i, 3) * TAU, 0.0))
	_add(root, _quad(w * 0.62, w * 0.5), mat,
		Vector3(_spanned(u, i, 4, -0.3, 0.3), 0.09, _spanned(u, i, 5, -0.3, 0.3)),
		Vector3(deg_to_rad(-52.0), _wob(u, i, 6) * TAU, deg_to_rad(12.0)))
	if arg == "sail" or arg == "pilgrim":
		_add(root, _quad(w * 0.45, w * 0.45), mat,
			Vector3(_spanned(u, i, 7, -0.4, 0.4), 0.16, _spanned(u, i, 8, -0.4, 0.4)),
			Vector3(deg_to_rad(-24.0), _wob(u, i, 9) * TAU, deg_to_rad(-31.0)))


static func _b_fleece(root: Node3D, arg: String, i: int, u: float) -> void:
	## Wool torn off on a thorn. Spec `y` lifts it into the hedge, which is
	## where a shepherd would actually find it.
	var mat := _mat(_col("fleece"))
	for k in 2:
		_add(root, _sph(_spanned(u, i, 1 + k, 0.06, 0.105), 5, 2), mat,
			Vector3(_spanned(u, i, 3 + k, -0.14, 0.14), _spanned(u, i, 5 + k, 0.0, 0.09),
				_spanned(u, i, 7 + k, -0.14, 0.14)),
			Vector3.ZERO, Vector3(1.0, 0.66, 1.15))
	_add(root, _quad(0.13, 0.09), _mat(_col("fleece"), true),
		Vector3(0.0, 0.11, 0.0), Vector3(deg_to_rad(-38.0), _wob(u, i, 9) * TAU, 0.0))


## ------------------------------------------------------ earth and fire ---


static func _b_stone(root: Node3D, arg: String, i: int, u: float) -> void:
	var c := _col("char") if arg == "burnt" else _col("stone")
	var r := _spanned(u, i, 1, 0.16, 0.3)
	_add(root, _sph(r, 5, 2), _mat(c), Vector3(0.0, r * 0.42, 0.0),
		Vector3(0.0, _wob(u, i, 2) * TAU, deg_to_rad(_spanned(u, i, 3, -12.0, 12.0))),
		Vector3(1.0, 0.55, 0.88))
	_add(root, _sph(r * 0.55, 5, 2), _mat(c),
		Vector3(_spanned(u, i, 4, -0.4, 0.4), r * 0.24, _spanned(u, i, 5, -0.4, 0.4)),
		Vector3.ZERO, Vector3(1.0, 0.6, 0.9))


static func _b_ash(root: Node3D, arg: String, i: int, u: float) -> void:
	## Where a fire was. Grey patch, a few black lumps at the rim, and the
	## single most legible aftermath prop in the kit.
	var w := _spanned(u, i, 1, 1.2, 2.0)
	_decal(root, w, w, _col("ash"), Vector3.ZERO, _wob(u, i, 2) * TAU)
	for k in 3:
		var a := _wob(u, i, 3 + k) * TAU
		var d := w * 0.33
		_add(root, _sph(0.09, 5, 2), _mat(_col("char")),
			Vector3(cos(a) * d, 0.05, sin(a) * d), Vector3.ZERO, Vector3(1.0, 0.5, 1.0))


static func _b_char(root: Node3D, arg: String, i: int, u: float) -> void:
	var mat := _mat(_col("char"))
	for k in 3:
		var l := _spanned(u, i, 1 + k, 0.35, 0.75)
		_add(root, _cyl(0.05, l, 5), mat,
			Vector3(_spanned(u, i, 4 + k, -0.28, 0.28), 0.06, _spanned(u, i, 7 + k, -0.28, 0.28)),
			Vector3(deg_to_rad(_spanned(u, i, 10 + k, 74.0, 100.0)), _wob(u, i, 13 + k) * TAU, 0.0))
	_add(root, _box(0.28, 0.07, 0.22), mat, Vector3(0.0, 0.035, 0.0),
		Vector3(0.0, _wob(u, i, 16) * TAU, 0.0))


static func _b_blood(root: Node3D, arg: String, i: int, u: float) -> void:
	var c := _col("blood_old")
	if arg == "trail":
		## A wounded thing going somewhere. Five patches getting smaller along
		## one bearing — the direction is the information.
		var head := _wob(u, i, 1) * TAU
		for k in 5:
			var t := float(k) / 4.0
			var d := t * _spanned(u, i, 2, 3.0, 5.5)
			_decal(root, lerpf(0.5, 0.16, t), lerpf(0.42, 0.14, t), c,
				Vector3(cos(head) * d + _spanned(u, i, 3 + k, -0.25, 0.25), 0.0,
					sin(head) * d + _spanned(u, i, 8 + k, -0.25, 0.25)),
				head + _spanned(u, i, 13 + k, -0.6, 0.6), float(k) * 0.001)
		return
	_decal(root, _spanned(u, i, 4, 0.55, 0.95), _spanned(u, i, 5, 0.5, 0.85), c,
		Vector3.ZERO, _wob(u, i, 6) * TAU)
	for k in 3:
		var a := _wob(u, i, 7 + k) * TAU
		var dd := _spanned(u, i, 10 + k, 0.35, 0.9)
		_decal(root, 0.16, 0.13, c, Vector3(cos(a) * dd, 0.0, sin(a) * dd), a, 0.002)


static func _b_bone(root: Node3D, arg: String, i: int, u: float) -> void:
	## Scale is the species. A sheep's skull and an ox's are the same three
	## shapes at different sizes, and from ten metres that is all anyone reads.
	var skull := 0.09
	match arg:
		"man": skull = 0.105
		"big": skull = 0.22
		"ox": skull = 0.16
		"deer": skull = 0.10
		"sheep": skull = 0.085
		"wolf": skull = 0.085
		"dog": skull = 0.07
	var mat := _mat(_col("bone"))
	_add(root, _sph(skull, 5, 3), mat, Vector3(0.0, skull * 0.7, 0.0),
		Vector3(deg_to_rad(_spanned(u, i, 1, -20.0, 20.0)), _wob(u, i, 2) * TAU, 0.0),
		Vector3(1.0, 0.82, 1.35))
	for k in 2:
		var l := skull * _spanned(u, i, 3 + k, 3.0, 4.6)
		_add(root, _cyl(skull * 0.2, l, 5), mat,
			Vector3(_spanned(u, i, 5 + k, -0.3, 0.5), skull * 0.22, _spanned(u, i, 7 + k, -0.4, 0.4)),
			Vector3(0.0, _wob(u, i, 9 + k) * TAU, PI * 0.5))
	if arg == "big" or arg == "ox":
		## Ribs like a boat's. Three staves standing out of the ground is all
		## it takes for a fisherman not to want to name it.
		for k in 3:
			_add(root, _box(0.05, skull * 3.4, 0.05), mat,
				Vector3(-0.3 + float(k) * 0.3, skull * 1.5, 0.0),
				Vector3(0.0, 0.0, deg_to_rad(_spanned(u, i, 11 + k, -34.0, 34.0))))


static func _b_scat(root: Node3D, arg: String, i: int, u: float) -> void:
	var r := 0.05
	match arg:
		"bear": r = 0.085
		"moose": r = 0.075
		"cow": r = 0.09
		"horse": r = 0.07
		"deer": r = 0.035
		"small": r = 0.03
		## Both of these were staged by recipes and neither had a branch, so a
		## wolf and a fox were leaving the same droppings as everything else.
		"wolf": r = 0.055
		"fox": r = 0.04
	var mat := _mat(_col("scat"))
	for k in 3:
		_add(root, _sph(r * _spanned(u, i, 1 + k, 0.8, 1.15), 5, 2), mat,
			Vector3(_spanned(u, i, 4 + k, -0.12, 0.12), r * 0.5, _spanned(u, i, 7 + k, -0.12, 0.12)),
			Vector3.ZERO, Vector3(1.0, 0.7, 1.0))


static func _b_cairn(root: Node3D, arg: String, i: int, u: float) -> void:
	## Stones over somebody, or a mark that somebody was here. Four flattened
	## spheres getting smaller, stacked slightly wrong, because they always are.
	var mat := _mat(_col("stone"))
	var y := 0.0
	for k in 4:
		var r := lerpf(0.26, 0.1, float(k) / 3.0)
		_add(root, _sph(r, 5, 2), mat,
			Vector3(_spanned(u, i, 1 + k, -0.05, 0.05), y + r * 0.32,
				_spanned(u, i, 5 + k, -0.05, 0.05)),
			Vector3(0.0, _wob(u, i, 9 + k) * TAU, deg_to_rad(_spanned(u, i, 13 + k, -9.0, 9.0))),
			Vector3(1.0, 0.62, 0.9))
		y += r * 0.66


## ------------------------------------------------------ work and water ---


static func _b_basket(root: Node3D, arg: String, i: int, u: float) -> void:
	var body := Node3D.new()
	root.add_child(body)
	var h := _spanned(u, i, 1, 0.28, 0.4)
	var r := h * 0.72
	var mat := _mat(_col("rope"))
	_add(body, _tapered(r * 1.15, r * 0.8, h, 8), mat, Vector3(0.0, h * 0.5, 0.0))
	_add(body, _cyl(r * 1.2, 0.05, 8), _mat(_col("wood")), Vector3(0.0, h, 0.0))
	if arg == "spilled":
		body.rotation = Vector3(deg_to_rad(_spanned(u, i, 2, 74.0, 104.0)), _wob(u, i, 3) * TAU, 0.0)
		body.position = Vector3(0.0, r * 0.9, 0.0)
		for k in 4:
			_add(root, _sph(0.055, 5, 2), _mat(_col("wood_pale")),
				Vector3(_spanned(u, i, 4 + k, -0.7, 0.7), 0.05, _spanned(u, i, 8 + k, 0.15, 0.85)),
				Vector3.ZERO, Vector3(1.0, 0.7, 1.0))


static func _b_net(root: Node3D, arg: String, i: int, u: float) -> void:
	var rope := _mat(_col("rope"), true)
	match arg:
		"snare":
			## Wire in the hazel: a stake, a peg and a loop stood open. Small,
			## quiet, and the only reason a warden ever comes up the hill.
			_add(root, _cyl(0.03, 0.55, 5), _mat(_col("wood")), Vector3(0.0, 0.27, 0.0))
			_add(root, _cyl(0.09, 0.015, 8), _mat(_col("iron")), Vector3(0.11, 0.3, 0.0),
				Vector3(PI * 0.5, _wob(u, i, 1) * TAU, 0.0))
			_add(root, _cyl(0.012, 0.34, 4), _mat(_col("iron")), Vector3(0.05, 0.3, 0.0),
				Vector3(0.0, 0.0, PI * 0.5))
		"rope":
			## A coil, or a cut trace lying where it was cut.
			for k in 3:
				_add(root, _cyl(_spanned(u, i, 1 + k, 0.14, 0.22), 0.035, 10), rope,
					Vector3(_spanned(u, i, 4 + k, -0.08, 0.08), 0.03 + float(k) * 0.035,
						_spanned(u, i, 7 + k, -0.08, 0.08)))
			_add(root, _cyl(0.02, 0.8, 4), rope, Vector3(0.4, 0.03, 0.2),
				Vector3(0.0, _wob(u, i, 10) * TAU, PI * 0.5))
		_:
			var torn := arg == "torn"
			var w := _spanned(u, i, 1, 0.9, 1.6) * (0.7 if torn else 1.0)
			_add(root, _quad(w, w * 0.75), rope, Vector3(0.0, DECAL_Y + 0.015, 0.0),
				Vector3(-PI * 0.5, _wob(u, i, 2) * TAU, 0.0))
			_add(root, _quad(w * 0.6, w * 0.45), rope,
				Vector3(_spanned(u, i, 3, -0.3, 0.3), 0.12, _spanned(u, i, 4, -0.3, 0.3)),
				Vector3(deg_to_rad(-46.0), _wob(u, i, 5) * TAU, deg_to_rad(14.0)))
			for k in 2:
				_add(root, _cyl(0.018, w * 1.1, 4), rope,
					Vector3(0.0, 0.04 + float(k) * 0.02, _spanned(u, i, 6 + k, -0.4, 0.4)),
					Vector3(0.0, _wob(u, i, 8 + k) * TAU, PI * 0.5))
			if not torn:
				for k in 2:
					_add(root, _cyl(0.055, 0.1, 6), _mat(_col("cork")),
						Vector3(_spanned(u, i, 10 + k, -0.5, 0.5), 0.06,
							_spanned(u, i, 12 + k, -0.5, 0.5)),
						Vector3(PI * 0.5, _wob(u, i, 14 + k) * TAU, 0.0))


static func _b_float(root: Node3D, arg: String, i: int, u: float) -> void:
	## Cork and a glass ball's worth of tarred wood. What a shore is made of
	## when the boats are out, and what is left of one when they are not.
	var cork := _mat(_col("cork"))
	for k in 2:
		_add(root, _cyl(_spanned(u, i, 1 + k, 0.055, 0.085), 0.14, 6), cork,
			Vector3(_spanned(u, i, 3 + k, -0.2, 0.2), 0.06, _spanned(u, i, 5 + k, -0.2, 0.2)),
			Vector3(PI * 0.5, _wob(u, i, 7 + k) * TAU, deg_to_rad(_spanned(u, i, 9 + k, -20.0, 20.0))))
	_add(root, _sph(0.07, 5, 2), _mat(_col("wood")), Vector3(0.16, 0.06, -0.12),
		Vector3.ZERO, Vector3(1.0, 0.85, 1.0))


static func _b_torch(root: Node3D, arg: String, i: int, u: float) -> void:
	var lit := arg == "lit"
	if arg == "guttered":
		## Burnt out and dropped. A search party's worth of these, cold on the
		## hill at dawn, says more than any amount of blood.
		_add(root, _cyl(0.04, 0.85, 5), _mat(_col("wood")), Vector3(0.0, 0.05, 0.0),
			Vector3(0.0, _wob(u, i, 1) * TAU, PI * 0.5))
		_add(root, _sph(0.08, 5, 2), _mat(_col("char")), Vector3(0.42, 0.07, 0.0),
			Vector3.ZERO, Vector3(1.0, 0.8, 1.0))
		return
	var lean := deg_to_rad(_spanned(u, i, 2, -12.0, 12.0))
	var h := _spanned(u, i, 3, 0.85, 1.1)
	_add(root, _cyl(0.04, h, 5), _mat(_col("wood")), Vector3(0.0, h * 0.5, 0.0),
		Vector3(lean, 0.0, lean * 0.6))
	if lit:
		_add(root, _sph(0.1, 5, 2), _mat(_col("flame"), false, 2.4), Vector3(0.0, h + 0.05, 0.0),
			Vector3.ZERO, Vector3(1.0, 1.5, 1.0))
		_add(root, _sph(0.16, 5, 2), _mat(_col("flame"), true, 0.7), Vector3(0.0, h + 0.1, 0.0),
			Vector3.ZERO, Vector3(1.0, 1.2, 1.0))
	else:
		_add(root, _sph(0.09, 5, 2), _mat(_col("char")), Vector3(0.0, h + 0.04, 0.0))


static func _b_track(root: Node3D, arg: String, i: int, u: float) -> void:
	## The most important builder in the file. Everything else says something
	## happened; tracks say WHAT, WHICH WAY and HOW MANY, and a player who has
	## learned wolf from goblin from boot can read an aftermath without being
	## told a word of it.
	var earth := _col("earth")
	var head := _wob(u, i, 1) * TAU
	var fw := Vector3(cos(head), 0.0, sin(head))
	var side := Vector3(-sin(head), 0.0, cos(head))

	if arg == "drag" or arg == "cart":
		## Two parallel scars. A stretcher out of a wood, or a loaded cart
		## going somewhere it should not have gone.
		var length := 2.4 if arg == "drag" else 3.4
		var gap := 0.5 if arg == "drag" else 1.05
		var wide := 0.1 if arg == "drag" else 0.15
		for s in 2:
			var off: Vector3 = side * (gap * 0.5 * (1.0 if s == 0 else -1.0))
			_add(root, _box(length, 0.03, wide), _mat(earth),
				off + Vector3(0.0, DECAL_Y, 0.0), Vector3(0.0, -head, 0.0))
		return

	var w := 0.11
	var l := 0.15
	var stride := 0.75
	var stagger := 0.07
	var paired := false
	match arg:
		"boot":
			w = 0.13
			l = 0.31
			stride = 0.68
			stagger = 0.14
		"small":
			w = 0.09
			l = 0.17
			stride = 0.48
			stagger = 0.1
		"bear":
			w = 0.2
			l = 0.27
			stride = 0.9
			stagger = 0.16
		"moose":
			w = 0.16
			l = 0.23
			stride = 1.3
			stagger = 0.2
			paired = true
		"hoof", "deer":
			w = 0.09
			l = 0.14
			stride = 0.9
			stagger = 0.15
			paired = true
		"cow":
			w = 0.14
			l = 0.16
			stride = 0.85
			stagger = 0.18
			paired = true
		"horse":
			w = 0.16
			l = 0.17
			stride = 1.0
			stagger = 0.12
		"dog":
			w = 0.08
			l = 0.1
			stride = 0.6
			stagger = 0.09
		"wolf":
			## A dog wanders and a wolf goes somewhere. The pad is barely bigger
			## than a large dog's and nobody reads it off the size — what gives a
			## wolf away is a long stride laid down almost dead straight, one
			## print nearly in front of the last. That is the whole difference,
			## and it is the one this file most needed: the aftermath of a fold
			## that held is fourteen of these and nothing else at all.
			w = 0.105
			l = 0.135
			stride = 1.05
			stagger = 0.04
		"fox":
			w = 0.055
			l = 0.085
			stride = 0.45
			stagger = 0.06

	for k in 4:
		var along := float(k) * stride
		var across := stagger * (1.0 if k % 2 == 0 else -1.0)
		var p: Vector3 = fw * along + side * across
		p += fw * _spanned(u, i, 2 + k, -0.05, 0.05)
		if paired:
			## Cloven: two crescents side by side, and the pair is what tells
			## a deer from a dog at a glance.
			for c in 2:
				var q: Vector3 = p + side * (w * 0.34 * (1.0 if c == 0 else -1.0))
				_decal(root, w * 0.45, l, earth, q, -head + _spanned(u, i, 6 + k, -0.1, 0.1),
					float(k) * 0.0005)
		else:
			_decal(root, w, l, earth, p, -head + _spanned(u, i, 10 + k, -0.12, 0.12),
				float(k) * 0.0005)


static func _b_feather(root: Node3D, arg: String, i: int, u: float) -> void:
	## Crows are the loudest thing in an aftermath and the cheapest to draw.
	## Two quads stood on edge in the grass, and the eye supplies the bird.
	var c := _col(arg if PALETTE.has(arg) else "crow")
	var mat := _mat(c, true)
	## A raven's primary is half again a crow's, and on a field where the note
	## says ravens and the birds have gone this quill is the ONLY thing on the
	## ground that says which. Before the palette knew the word, `arg: "raven"`
	## fell through to crow and `ravens_field` was `hunters_find` with more of
	## everything.
	var big := 1.35 if arg == "raven" else 1.0
	for k in 2:
		_add(root, _quad(0.045 * big, _spanned(u, i, 1 + k, 0.16, 0.26) * big), mat,
			Vector3(_spanned(u, i, 3 + k, -0.2, 0.2), 0.09, _spanned(u, i, 5 + k, -0.2, 0.2)),
			Vector3(deg_to_rad(_spanned(u, i, 7 + k, -74.0, -40.0)), _wob(u, i, 9 + k) * TAU, 0.0))
