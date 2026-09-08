class_name ChronicleEvents
extends RefCounted

## ===========================================================================
## THE CHRONICLE'S CATALOGUE — every rumour the world can tell about itself.
##
## Chronicle.gd runs the clock; this file is the BOOK it reads from. A kind is
## a thing that can happen to a place, a road, or the wild between them —
## wolves at the fold, the ford up, a stranger who paid in old silver — and
## each kind resolves into one of several outcomes, at least one of them bad,
## because a world where every rumour ends well is a world nobody listens to.
##
## Everything in here is PURE. Const data, static functions, no tree, no
## randomness of its own: Chronicle hands in the roll and the context and gets
## a number or a Dictionary back. That is what lets the tests hand-compute
## weights and what lets two Chronicles with the same seed agree to the last
## resolved event — the book never changes between readings.
##
## The map is Maine renamed. The region strings below are the EXACT names in
## assets/terrain/maine_meta.json `regions`, upper case, because a kind that
## "prefers" a region it has misspelt prefers nowhere and nobody notices.
##
## Ids are forever: saves key active events on them. Rename the title, retune
## the weights, rewrite the prose — never the id.
## ===========================================================================

## Season indices, so the catalogue reads as words rather than magic numbers.
## Wind owns the season maths (24 days each); these only name the slots.
const SPRING := 0
const SUMMER := 1
const AUTUMN := 2
const WINTER := 3

## Weather.Level, copied by value rather than referenced, because this file
## must load in a headless test with no Weather node and no scene at all.
const W_CLEAR := 0
const W_OVERCAST := 1
const W_DRIZZLE := 2
const W_RAIN := 3
const W_STORM := 4

## "Any hour". hour_in_band is continuous and inclusive at both ends, so the
## whole day is 0..24: written 0..23 it would quietly drop the last hour, and
## a kind tuned for "any time" would fire 4% less often than the tuning says.
const ALL_DAY := Vector2(0, 24)

## The three tags weight_for treats specially. A kind tagged "alarm" gets
## likelier as the place's alarm climbs; "hunger" as its stores empty;
## "unrest" as its mood sours. Those three are the feedback loops that make
## the Chronicle a simulation and not a random rumour generator: a hungry
## village hears about its mill, its tithes and its harvest, and a frightened
## one hears drums.
const TAG_ALARM := "alarm"
const TAG_HUNGER := "hunger"
const TAG_UNREST := "unrest"

## The map's two halves, by region name, for the kinds that are ONLY one or the
## other. A kind can name regions as a mere preference (the usual case: wolves
## are a Katahdin story but a coastal fold can still lose a ewe) or set
## "gate_regions": true and make them a hard requirement. The second is for
## kinds whose prose is a lie anywhere else — "wreckage on the beach east of
## Farmington" is not a rumour, it is a bug, and Farmington is eighty miles
## inland.
const COAST := ["CASCO BAY", "MIDCOAST", "PENOBSCOT BAY", "DOWN EAST", "ACADIA", "GULF OF MAINE"]
const INLAND := ["MOOSEHEAD", "RANGELEY LAKES", "ALLAGASH", "KENNEBEC R.", "PENOBSCOT R.",
	"ANDROSCOGGIN R.", "AROOSTOOK", "KATAHDIN", "BAXTER STATE PARK", "100-MILE WILDERNESS",
	"BIGELOW RANGE", "MAHOOSUCS"]

## The multipliers, named so the tests and the tuning notes can quote them.
const REGION_HOME := 2.0      ## a kind fired in a region it prefers
const REGION_AWAY := 0.35     ## a kind fired somewhere it doesn't
const BIAS_FLOOR := 0.05      ## bias can starve a kind, never kill it outright
const ALARM_GAIN := 0.6
const HUNGER_GAIN := 0.8
const UNREST_GAIN := 0.5


## ============================== The catalogue ==============================
##
## Each `line` is what someone actually says across a table, with exactly one
## "%s" for the place. Prose rules that kept the voice honest:
##   - report first, feeling second, and the feeling is usually implied
##   - no two lines share a shape; hearsay ("They're saying..."), complaint,
##     flat report, and the sentence that trails off are all in here on purpose
##   - the bad outcome is never the loudest one. The worst news is quiet.
##
## `place` deltas are small: a place is 0..1 on every axis and a single rumour
## should nudge it, not swing it. -0.3 is a catastrophe. `bias` is the world
## remembering: wolves that took ewes make the next wolf kind likelier, and
## that decays in Chronicle over BIAS_HALFLIFE_DAYS.

const KINDS: Array = [

	## ------------------------------------------------------- wolves ---
	{
		"id": "wolves_at_fold",
		"title": "Wolves at the fold",
		"scope": "place",
		"tags": ["wolves", "livestock", "night", "alarm"],
		"hours": Vector2(21, 4),
		"seasons": [AUTUMN, WINTER],
		"weather": [],
		"regions": ["MOOSEHEAD", "100-MILE WILDERNESS", "ALLAGASH", "KATAHDIN"],
		"min_rank": 0,
		"base": 1.4,
		"active": Vector2(6, 18),
		"outcomes": [
			{
				"id": "held",
				"weight": 3.0,
				"line": "Dogs at %s kept the wolves off the fold last night. Nobody slept, but nothing was lost.",
				"place": {"alarm": 0.1},
				"bias": {"wolves": 0.2},
				"spawn": "",
			},
			{
				"id": "ewes_lost",
				"weight": 3.0,
				"line": "Wolves got into the fold at %s. Three ewes torn open and the rest scattered up the hill.",
				"place": {"stores": -0.15, "alarm": 0.3, "mood": -0.1},
				"bias": {"wolves": 0.5, "livestock": 0.2},
				"spawn": "wolf_hunt",
			},
			{
				"id": "shepherd_bitten",
				"weight": 1.0,
				"line": "The shepherd's boy at %s went out with a stick to see about the wolves. He's alive, but he'll not use that hand for a while.",
				"place": {"alarm": 0.4, "mood": -0.2},
				"bias": {"wolves": 0.6},
				"spawn": "wolf_hunt",
			},
		],
	},
	{
		"id": "wolf_hunt",
		"title": "The hunt goes out",
		"scope": "wild",
		"tags": ["wolves", "hunt", "watch"],
		"hours": Vector2(5, 17),
		"seasons": [],
		"weather": [W_CLEAR, W_OVERCAST],
		"regions": [],
		"min_rank": 0,
		"base": 0.4,
		"active": Vector2(12, 36),
		"outcomes": [
			{
				"id": "pelt",
				"weight": 3.0,
				"line": "They brought a wolf back to %s slung on a pole. Big grey dog-wolf. The pelt's nailed to the tithe barn door.",
				"place": {"mood": 0.15, "alarm": -0.3},
				"bias": {"wolves": -0.5},
				"spawn": "",
			},
			{
				"id": "empty",
				"weight": 3.0,
				"line": "Half the men of %s tramped the hills two days after those wolves and never saw so much as a track.",
				"place": {"alarm": -0.1, "mood": -0.05},
				"bias": {"wolves": 0.1},
				"spawn": "",
			},
			{
				"id": "hound_lost",
				"weight": 2.0,
				"line": "The hunt out of %s lost a good hound to the pack. Went in after them and didn't come out.",
				"place": {"alarm": 0.15, "mood": -0.1},
				"bias": {"wolves": 0.3},
				"spawn": "",
			},
		],
	},
	{
		"id": "deer_yard",
		"title": "The deer come down",
		"scope": "wild",
		"tags": ["deer", "wildlife", "hunt", "hunger"],
		"hours": Vector2(6, 18),
		"seasons": [WINTER],
		"weather": [],
		"regions": ["100-MILE WILDERNESS", "MOOSEHEAD", "BIGELOW RANGE", "MAHOOSUCS"],
		"min_rank": -1,
		"base": 1.0,
		"active": Vector2(24, 96),
		"outcomes": [
			{
				"id": "yarded",
				"weight": 3.0,
				"line": "The deer have yarded up in the cedar swamp below %s, thick as sheep. A man with a bow could feed a village.",
				"place": {"stores": 0.05},
				"bias": {"hunger": -0.15, "poaching": 0.2},
				"spawn": "",
			},
			{
				"id": "starving",
				"weight": 2.0,
				"line": "Deer are coming right into the yards at %s to eat the hay off the racks. Ribs like a hurdle. Bad winter up top.",
				"place": {"stores": -0.05},
				"bias": {"wolves": 0.3, "hunger": 0.1},
				"spawn": "",
			},
			{
				"id": "wolves_follow",
				"weight": 2.0,
				"line": "Where the deer come down, the wolves come after. They've been howling round the %s yards three nights running.",
				"place": {"alarm": 0.25},
				"bias": {"wolves": 0.5},
				"spawn": "wolves_at_fold",
			},
		],
	},

	## ---------------------------------------------------- livestock ---
	{
		"id": "fold_breached",
		"title": "Stock through the hedge",
		"scope": "place",
		"tags": ["livestock", "fold"],
		"hours": Vector2(6, 20),
		"seasons": [SPRING, SUMMER, AUTUMN],
		"weather": [],
		"regions": [],
		"min_rank": 0,
		"base": 1.0,
		"active": Vector2(6, 24),
		"outcomes": [
			{
				"id": "found",
				"weight": 4.0,
				"line": "Somebody's heifers were loose on the road below %s all morning. Found them in the beans, fat and pleased with themselves.",
				"place": {"mood": 0.05},
				"bias": {},
				"spawn": "",
			},
			{
				"id": "bogged",
				"weight": 2.0,
				"line": "Two of the %s cows went through the hedge and one's stuck to the belly in the bog. They're fetching ropes.",
				"place": {"stores": -0.05, "mood": -0.05},
				"bias": {},
				"spawn": "",
			},
			{
				"id": "gone",
				"weight": 1.0,
				"line": "A whole flock walked off from %s in the fog and they've had no sight of them since. That's a family's winter.",
				"place": {"stores": -0.2, "mood": -0.15},
				"bias": {"livestock": 0.3},
				"spawn": "",
			},
		],
	},
	{
		"id": "murrain",
		"title": "Murrain in the byres",
		"scope": "place",
		"tags": ["livestock", "sickness", "murrain", "hunger"],
		"hours": ALL_DAY,
		"seasons": [],
		"weather": [],
		"regions": [],
		"min_rank": 0,
		"base": 0.5,
		"active": Vector2(48, 168),
		"outcomes": [
			{
				## The catalogue's only cattle-sickness kind was three shades of
				## bad, and the hunger loop PULLS a hungry village toward it —
				## so a bad year could only ever get worse. One outcome where it
				## comes to nothing is what makes the other three frightening.
				"id": "passed",
				"weight": 3.0,
				"line": "The scour at %s passed off with one cow lost and the rest back at the trough. The old man says it was the water, and he has said that for forty years.",
				"place": {"mood": 0.1, "alarm": -0.15},
				"bias": {"murrain": -0.3},
				"spawn": "",
			},
			{
				"id": "one_cow",
				"weight": 4.0,
				"line": "One cow at %s down with the scour and off its feed. They've got it in a shed by itself and they're watching the rest and not saying the word.",
				"place": {"alarm": 0.1},
				"bias": {"murrain": 0.2},
				"spawn": "",
			},
			{
				"id": "herd",
				"weight": 2.0,
				"line": "The murrain's through the whole %s herd. Eyes running, tongues swollen. They're digging a pit at the end of the low field.",
				"place": {"stores": -0.25, "mood": -0.25, "alarm": 0.2},
				"bias": {"murrain": 0.5, "hunger": 0.3},
				"spawn": "",
			},
			{
				"id": "blamed",
				"weight": 2.0,
				"line": "They say the cattle sickness at %s came in with those traders. Now every steading on the road is barring its gate to strangers.",
				"place": {"mood": -0.15, "alarm": 0.15},
				"bias": {"murrain": 0.4, "trade": -0.3},
				"spawn": "stranger_passing",
			},
		],
	},
	{
		"id": "moose_turnips",
		"title": "A moose in the turnips",
		"scope": "place",
		"tags": ["moose", "wildlife", "harvest", "stores"],
		"hours": Vector2(17, 7),
		"seasons": [SUMMER, AUTUMN],
		"weather": [],
		"regions": ["MOOSEHEAD", "ALLAGASH", "AROOSTOOK", "100-MILE WILDERNESS", "KATAHDIN"],
		"min_rank": 0,
		"base": 1.2,
		"active": Vector2(3, 12),
		"outcomes": [
			{
				"id": "chased",
				"weight": 3.0,
				"line": "Bull moose in the turnips at %s again. Three men and a dog got him out. The dog's not right since.",
				"place": {"stores": -0.03, "mood": 0.05},
				"bias": {},
				"spawn": "",
			},
			{
				"id": "shot",
				"weight": 2.0,
				"line": "They shot the moose in the %s turnips and they're hanging him in the smithy. A good bit of meat for a bad bit of field.",
				"place": {"stores": 0.12, "mood": 0.1},
				"bias": {"hunger": -0.2},
				"spawn": "",
			},
			{
				"id": "trampled",
				"weight": 2.0,
				"line": "That moose at %s went through the turnips, the beans, and the fence, and then stood in the road and dared anyone.",
				"place": {"stores": -0.1, "mood": -0.05},
				"bias": {"wildlife": 0.2},
				"spawn": "",
			},
			{
				"id": "gored",
				"weight": 1.0,
				"line": "The %s moose put its antlers through a man's hip when he tried to shoo it. He'll live. He'll not chase moose again.",
				"place": {"mood": -0.1, "alarm": 0.1},
				"bias": {"wildlife": 0.3},
				"spawn": "",
			},
		],
	},

	## -------------------------------------------------------- trade ---
	{
		"id": "caravan_in",
		"title": "A caravan comes in",
		"scope": "road",
		"tags": ["trade", "caravan", "road"],
		"hours": Vector2(8, 19),
		"seasons": [SPRING, SUMMER, AUTUMN],
		"weather": [W_CLEAR, W_OVERCAST, W_DRIZZLE],
		"regions": ["KENNEBEC R.", "PENOBSCOT R.", "CASCO BAY", "MIDCOAST"],
		"min_rank": 1,
		"base": 1.2,
		"active": Vector2(12, 48),
		"outcomes": [
			{
				"id": "good_trade",
				"weight": 4.0,
				"line": "Wagons in at %s from the south, salt and iron and a man selling needles. The market was thick as a fair.",
				"place": {"stores": 0.15, "mood": 0.15},
				"bias": {"trade": 0.3},
				"spawn": "",
			},
			{
				"id": "prices",
				"weight": 3.0,
				"line": "That caravan at %s wanted a silver piece for a pound of salt. A silver piece. They'll be back when we're hungrier.",
				"place": {"mood": -0.1},
				"bias": {"trade": 0.1},
				"spawn": "",
			},
			{
				"id": "sick_ox",
				"weight": 1.0,
				"line": "The caravan's lead ox dropped dead in the square at %s. Nobody wants to say what of, but the butcher wouldn't take it.",
				"place": {"alarm": 0.1, "mood": -0.05},
				"bias": {"murrain": 0.3},
				"spawn": "murrain",
			},
		],
	},
	{
		"id": "caravan_overdue",
		"title": "Caravan overdue",
		"scope": "road",
		"tags": ["trade", "caravan", "road", "alarm"],
		"hours": Vector2(6, 22),
		"seasons": [],
		"weather": [],
		"regions": ["100-MILE WILDERNESS", "ALLAGASH", "AROOSTOOK"],
		"min_rank": 1,
		"base": 0.7,
		"active": Vector2(24, 72),
		"outcomes": [
			{
				## Same reason as murrain's "passed": an overdue caravan that is
				## never once simply late makes the road feel scripted rather
				## than dangerous.
				"id": "turned_up",
				"weight": 3.0,
				"line": "The overdue wagons walked into %s at dusk, mud to the axles. Ford was up, the drivers say, and nobody asked why they smelled of ale.",
				"place": {"stores": 0.1, "mood": 0.1, "alarm": -0.1},
				"bias": {"trade": 0.15},
				"spawn": "",
			},
			{
				"id": "late",
				"weight": 4.0,
				"line": "The salt wagons were due at %s four days ago. Nothing on the road but rain. Reckon the ford's up.",
				"place": {"stores": -0.05, "alarm": 0.1},
				"bias": {},
				"spawn": "",
			},
			{
				"id": "robbed",
				"weight": 2.0,
				"line": "They found the %s caravan on the road with its traces cut and every bale gone. Drivers alive, sat in the ditch counting themselves.",
				"place": {"stores": -0.1, "alarm": 0.3, "mood": -0.1},
				"bias": {"bandits": 0.6, "trade": -0.2},
				"spawn": "watch_patrol",
			},
			{
				"id": "goblins",
				"weight": 1.0,
				"line": "It wasn't bandits took the wagons bound for %s. Little tracks all round the wreck, and the oxen butchered where they stood.",
				"place": {"alarm": 0.4, "mood": -0.15},
				"bias": {"goblins": 0.8},
				"spawn": "goblin_sign",
			},
		],
	},
	{
		"id": "bandits_road",
		"title": "Robbers on the road",
		"scope": "road",
		"tags": ["bandits", "road", "trade", "alarm"],
		"hours": Vector2(5, 23),
		"seasons": [],
		"weather": [],
		"regions": [],
		"min_rank": -1,
		"base": 0.6,
		"active": Vector2(12, 48),
		"outcomes": [
			{
				"id": "toll",
				"weight": 3.0,
				"line": "Men with cudgels are taking a toll on the road below %s. A penny a head and don't argue. The watch says it's not their stretch.",
				"place": {"mood": -0.1, "alarm": 0.15},
				"bias": {"bandits": 0.3},
				"spawn": "watch_patrol",
			},
			{
				"id": "beaten",
				"weight": 2.0,
				"line": "A tinker was beaten and stripped on the road to %s. He crawled in at dark. Says there were four and one of them was a woman.",
				"place": {"alarm": 0.2, "mood": -0.1},
				"bias": {"bandits": 0.4},
				"spawn": "",
			},
			{
				"id": "run_off",
				"weight": 2.0,
				"line": "The carters ganged up on the road-robbers at %s and thrashed them into the wood. Two of the carters are limping and all of them are drinking on it.",
				"place": {"alarm": -0.1, "mood": 0.1},
				"bias": {"bandits": -0.3},
				"spawn": "",
			},
		],
	},

	## ------------------------------------------------------ goblins ---
	{
		"id": "goblin_sign",
		"title": "Sign in the deepwood",
		"scope": "wild",
		"tags": ["goblins", "deepwood", "alarm"],
		"hours": ALL_DAY,
		"seasons": [],
		"weather": [],
		"regions": ["100-MILE WILDERNESS", "ALLAGASH", "BAXTER STATE PARK", "KATAHDIN"],
		"min_rank": -1,
		"base": 0.9,
		"active": Vector2(12, 48),
		"outcomes": [
			{
				"id": "old",
				"weight": 3.0,
				"line": "A woodcutter out of %s found a goblin fire-ring in the deepwood. Cold, he says. Cold for a week. He still came home early.",
				"place": {"alarm": 0.1},
				"bias": {"goblins": 0.2},
				"spawn": "",
			},
			{
				"id": "fresh",
				"weight": 2.0,
				"line": "Fresh goblin sign on the ridge above %s. Hacked saplings and a deer hung up with its belly opened. That's a camp, not a passing.",
				"place": {"alarm": 0.3, "watch": 0.1},
				"bias": {"goblins": 0.5},
				"spawn": "goblin_raid",
			},
			{
				"id": "drums",
				"weight": 1.0,
				"line": "There were drums up the valley from %s last night. Drums. The far steadings have brought the children in and are sitting up with the door barred till the moon's back.",
				"place": {"alarm": 0.4, "mood": -0.1},
				"bias": {"goblins": 0.7},
				"spawn": "goblin_raid",
			},
		],
	},
	{
		"id": "goblin_raid",
		"title": "Goblins at the field's edge",
		"scope": "place",
		"tags": ["goblins", "raid", "night", "alarm", "unrest"],
		"hours": Vector2(22, 4),
		"seasons": [],
		"weather": [W_CLEAR, W_OVERCAST],
		"regions": ["100-MILE WILDERNESS", "ALLAGASH", "BAXTER STATE PARK", "KATAHDIN"],
		"min_rank": 0,
		"base": 0.5,
		"active": Vector2(3, 12),
		"outcomes": [
			{
				"id": "driven_off",
				"weight": 3.0,
				"line": "Goblins came down on the outlying steadings at %s in the night. The watch drove them off with torches and lost nobody, which surprised the watch.",
				"place": {"alarm": 0.2, "watch": 0.15, "mood": 0.05},
				"bias": {"goblins": -0.2},
				"spawn": "",
			},
			{
				"id": "byre_burned",
				"weight": 2.0,
				"line": "Goblins fired a byre at %s before dawn. The stock got out. The hay didn't.",
				"place": {"stores": -0.2, "alarm": 0.35, "mood": -0.15},
				"bias": {"goblins": 0.4, "fire": 0.2},
				"spawn": "watch_patrol",
			},
			{
				"id": "taken",
				"weight": 1.0,
				"line": "The %s raid took two goats and a ploughboy. The goats came back.",
				"place": {"alarm": 0.5, "mood": -0.3, "watch": 0.2},
				"bias": {"goblins": 0.8},
				"spawn": "watch_patrol",
			},
		],
	},

	## ------------------------------------------------------ weather ---
	{
		"id": "storm_damage",
		"title": "The storm's bill",
		"scope": "place",
		"tags": ["weather", "storm", "damage"],
		"hours": ALL_DAY,
		"seasons": [],
		"weather": [W_RAIN, W_STORM],
		"regions": [],
		"min_rank": 0,
		"base": 1.3,
		"active": Vector2(6, 24),
		"outcomes": [
			{
				"id": "roofs",
				"weight": 4.0,
				"line": "That blow took the thatch off half of %s. They're up the ladders now, soaked to the skin and cursing.",
				"place": {"mood": -0.1},
				"bias": {},
				"spawn": "",
			},
			{
				"id": "trees_down",
				"weight": 3.0,
				"line": "Big spruce came down across the road out of %s in the storm. Two days to cut through, they reckon, and the wheelwright already out measuring it for spokes.",
				"place": {"stores": -0.05, "mood": -0.05},
				"bias": {"road": 0.2},
				"spawn": "",
			},
			{
				"id": "bridge",
				"weight": 1.5,
				"line": "The river came up under the %s bridge in the night and took the middle span. The two ends are still there, pointing at each other.",
				"place": {"stores": -0.1, "alarm": 0.15},
				"bias": {"road": 0.4},
				"spawn": "bridge_out",
			},
			{
				"id": "barn_lost",
				"weight": 1.0,
				"line": "Wind laid the tithe barn at %s flat with the grain still in it. What the rain didn't spoil the rats will.",
				"place": {"stores": -0.3, "mood": -0.2},
				"bias": {"hunger": 0.4},
				"spawn": "",
			},
		],
	},
	{
		"id": "ford_drowned",
		"title": "The ford's up",
		"scope": "road",
		"tags": ["road", "river", "weather", "ford"],
		"hours": ALL_DAY,
		"seasons": [SPRING, WINTER],
		"weather": [W_DRIZZLE, W_RAIN, W_STORM],
		"regions": ["KENNEBEC R.", "PENOBSCOT R.", "ANDROSCOGGIN R.", "ALLAGASH"],
		"min_rank": -1,
		"base": 1.0,
		"active": Vector2(12, 48),
		"outcomes": [
			{
				"id": "waited",
				"weight": 4.0,
				"line": "Ford below %s is brown and roaring. Half a dozen carts sat on the bank all day waiting for it to drop, and the inn doing very well out of them.",
				"place": {"stores": -0.03},
				"bias": {"road": 0.2},
				"spawn": "",
			},
			{
				"id": "cart_lost",
				"weight": 2.0,
				"line": "A cart tried the ford at %s while it was up. The ox swam. The cart and the flour didn't.",
				"place": {"stores": -0.1, "mood": -0.1},
				"bias": {"road": 0.3, "hunger": 0.1},
				"spawn": "",
			},
			{
				"id": "drowned_man",
				"weight": 1.0,
				"line": "They pulled a pedlar out of the river a mile below the %s ford. Still had his pack on. That's what drowned him, they reckon.",
				"place": {"mood": -0.15, "alarm": 0.1},
				"bias": {"road": 0.4},
				"spawn": "",
			},
		],
	},
	{
		"id": "ice_out",
		"title": "Ice-out",
		"scope": "place",
		"tags": ["ice", "river", "spring", "weather"],
		"hours": Vector2(6, 20),
		"seasons": [SPRING],
		"weather": [],
		"regions": INLAND,
		"gate_regions": true,
		"min_rank": -1,
		"base": 1.5,
		"active": Vector2(12, 72),
		"outcomes": [
			{
				"id": "clean",
				"weight": 4.0,
				"line": "Ice went out at %s in one night, clean as a bill paid. Boats in the water by noon.",
				"place": {"mood": 0.15},
				"bias": {"trade": 0.2},
				"spawn": "",
			},
			{
				"id": "jam",
				"weight": 2.0,
				"line": "The ice jammed below %s and the river's backed up over the low road. Cellars full, and it's not done yet.",
				"place": {"stores": -0.1, "mood": -0.1, "alarm": 0.15},
				"bias": {"road": 0.3},
				"spawn": "ford_drowned",
			},
			{
				"id": "man_through",
				"weight": 1.0,
				"line": "Fool went out on the %s ice the day before it went, after a lost net. They heard it go. They didn't hear him.",
				"place": {"mood": -0.2},
				"bias": {},
				"spawn": "",
			},
			{
				"id": "boats_crushed",
				"weight": 1.0,
				"line": "The ice going out at %s took every boat on the shore with it. Splinters to the far bank.",
				"place": {"stores": -0.1, "mood": -0.15},
				"bias": {"trade": -0.2},
				"spawn": "boat_overdue",
			},
		],
	},
	{
		"id": "aurora",
		"title": "Lights in the north",
		"scope": "wild",
		"tags": ["aurora", "omen", "night", "sky"],
		"hours": Vector2(21, 3),
		"seasons": [AUTUMN, WINTER],
		"weather": [W_CLEAR],
		"regions": ["ALLAGASH", "AROOSTOOK", "KATAHDIN", "BAXTER STATE PARK", "MOOSEHEAD"],
		"min_rank": -1,
		"base": 0.7,
		"active": Vector2(2, 6),
		"outcomes": [
			{
				"id": "wonder",
				"weight": 4.0,
				"line": "Whole sky over %s went green and red last night and stood there swaying. Folk came out in blankets and just looked.",
				"place": {"mood": 0.1},
				"bias": {"omen": 0.1},
				"spawn": "",
			},
			{
				"id": "priest",
				"weight": 2.0,
				"line": "The priest at %s says the lights were a sign. He's not said of what. He's charging to find out.",
				"place": {"mood": -0.05},
				"bias": {"omen": 0.3},
				"spawn": "",
			},
			{
				"id": "fear",
				"weight": 1.0,
				"line": "They're saying the lights over %s were the colour of blood and the dogs howled the whole time. Two families are talking about leaving.",
				"place": {"mood": -0.15, "alarm": 0.15},
				"bias": {"omen": 0.4, "unrest": 0.2},
				"spawn": "",
			},
		],
	},

	## ----------------------------------------------- harvest & stores ---
	{
		"id": "harvest_in",
		"title": "Harvest home",
		"scope": "place",
		"tags": ["harvest", "stores", "hunger"],
		"hours": Vector2(7, 19),
		"seasons": [AUTUMN],
		"weather": [W_CLEAR, W_OVERCAST],
		"regions": [],
		"min_rank": 0,
		"base": 1.6,
		"active": Vector2(24, 72),
		"outcomes": [
			{
				"id": "full",
				"weight": 4.0,
				"line": "Barley's in at %s and the barns are full to the beams. There'll be a dance.",
				"place": {"stores": 0.3, "mood": 0.25},
				"bias": {"hunger": -0.4, "fair": 0.3},
				"spawn": "",
			},
			{
				"id": "thin",
				"weight": 3.0,
				"line": "Thin harvest at %s this year. The heads were half empty. They're saying it'll be a long winter and a lot of turnip.",
				"place": {"stores": 0.05, "mood": -0.1},
				"bias": {"hunger": 0.3},
				"spawn": "",
			},
			{
				"id": "rotted",
				"weight": 1.0,
				"line": "The rain caught the %s oats in the stook and they've gone black. That's the seed corn and the winter both.",
				"place": {"stores": -0.2, "mood": -0.25},
				"bias": {"hunger": 0.6, "unrest": 0.2},
				"spawn": "tithe_due",
			},
		],
	},
	{
		"id": "tithe_due",
		"title": "The tithe",
		"scope": "place",
		"tags": ["tithes", "unrest", "hunger", "stores"],
		"hours": Vector2(8, 17),
		"seasons": [AUTUMN, WINTER],
		"weather": [],
		"regions": [],
		"min_rank": 0,
		"base": 0.9,
		"active": Vector2(24, 72),
		"outcomes": [
			{
				"id": "paid",
				"weight": 4.0,
				"line": "The reeve came for the tithe at %s and got it, near enough. Nobody sang, but nobody threw anything.",
				"place": {"stores": -0.1},
				"bias": {},
				"spawn": "",
			},
			{
				"id": "short",
				"weight": 2.0,
				"line": "They came up short on the tithe at %s and the reeve took a cow instead. Took the good one, naturally.",
				"place": {"stores": -0.15, "mood": -0.15},
				"bias": {"unrest": 0.3},
				"spawn": "",
			},
			{
				"id": "refused",
				"weight": 1.0,
				"line": "The %s folk barred the barn against the tithe-men. There's a cart of reeve's men on the road now and nobody thinks it ends well.",
				"place": {"mood": -0.2, "alarm": 0.3, "watch": 0.1},
				"bias": {"unrest": 0.6},
				"spawn": "watch_patrol",
			},
		],
	},
	{
		"id": "mill_broken",
		"title": "The mill wheel",
		"scope": "place",
		"tags": ["mill", "stores", "hunger", "trade"],
		"hours": Vector2(6, 19),
		"seasons": [],
		"weather": [],
		"regions": [],
		"min_rank": 1,
		"base": 0.6,
		"active": Vector2(48, 168),
		"outcomes": [
			{
				"id": "mended",
				"weight": 3.0,
				"line": "The millwright's done with the %s wheel. First flour in a fortnight and the whole town smells of baking.",
				"place": {"stores": 0.1, "mood": 0.15},
				"bias": {"hunger": -0.2},
				"spawn": "",
			},
			{
				"id": "shaft",
				"weight": 3.0,
				"line": "The %s mill wheel threw its shaft. Nothing's ground till a new one's hewn, and there's grain sat in every barn going soft.",
				"place": {"stores": -0.15, "mood": -0.1},
				"bias": {"hunger": 0.3},
				"spawn": "",
			},
			{
				"id": "miller_hurt",
				"weight": 1.0,
				"line": "The miller at %s put his arm in the gearing. He'll grind again, left-handed. The wheel's still broken.",
				"place": {"stores": -0.1, "mood": -0.15},
				"bias": {"hunger": 0.3},
				"spawn": "",
			},
		],
	},
	{
		"id": "bees",
		"title": "The bees",
		"scope": "place",
		"tags": ["bees", "honey", "stores"],
		"hours": Vector2(9, 17),
		"seasons": [SPRING, SUMMER],
		"weather": [W_CLEAR],
		"regions": [],
		"min_rank": 0,
		"base": 0.9,
		"active": Vector2(6, 24),
		"outcomes": [
			{
				"id": "swarm_caught",
				"weight": 3.0,
				"line": "A swarm settled in the churchyard yew at %s and the old woman talked it into a skep. Honey for the winter, and she'll not say what she told them.",
				"place": {"stores": 0.08, "mood": 0.1},
				"bias": {"hunger": -0.1},
				"spawn": "",
			},
			{
				"id": "swarm_lost",
				"weight": 2.0,
				"line": "The %s bees swarmed and went off over the wood. Old man ran after them with a pan and a spoon till he couldn't breathe.",
				"place": {"mood": -0.05},
				"bias": {},
				"spawn": "",
			},
			{
				"id": "bear",
				"weight": 1.0,
				"line": "Bear got the skeps at %s. Splinters and wax across the orchard, and the bees in a killing temper.",
				"place": {"stores": -0.08, "alarm": 0.15},
				"bias": {"bears": 0.4},
				"spawn": "",
			},
		],
	},

	## --------------------------------------------------------- fire ---
	{
		"id": "fire",
		"title": "Fire in the night",
		"scope": "place",
		"tags": ["fire", "night", "alarm"],
		"hours": Vector2(20, 5),
		"seasons": [],
		"weather": [W_CLEAR, W_OVERCAST],
		"regions": [],
		"min_rank": 0,
		"base": 0.6,
		"active": Vector2(2, 8),
		"outcomes": [
			{
				"id": "chimney",
				"weight": 4.0,
				"line": "Chimney fire at the inn in %s. Buckets and shouting, then nothing. The thatch is scorched and the innkeeper's sober for once.",
				"place": {"alarm": 0.1},
				"bias": {},
				"spawn": "",
			},
			{
				"id": "row_lost",
				"weight": 1.5,
				"line": "Three houses went in %s last night. The wind carried it roof to roof before the bell was even rung.",
				"place": {"mood": -0.3, "stores": -0.1, "alarm": 0.3},
				"bias": {"fire": 0.3, "unrest": 0.2},
				"spawn": "",
			},
			{
				"id": "set",
				"weight": 1.0,
				"line": "That fire at %s didn't start itself. Somebody stacked brush against the granary wall. The watch is asking who's been quarrelling.",
				"place": {"alarm": 0.3, "watch": 0.1, "mood": -0.15},
				"bias": {"unrest": 0.4},
				"spawn": "watch_patrol",
			},
		],
	},
	{
		"id": "charcoal",
		"title": "The burners",
		"scope": "wild",
		"tags": ["charcoal", "fire", "deepwood", "trade"],
		"hours": ALL_DAY,
		"seasons": [SUMMER, AUTUMN],
		"weather": [W_CLEAR, W_OVERCAST],
		"regions": ["100-MILE WILDERNESS", "ALLAGASH", "BAXTER STATE PARK"],
		"min_rank": -1,
		"base": 0.7,
		"active": Vector2(48, 120),
		"outcomes": [
			{
				"id": "good_burn",
				"weight": 4.0,
				"line": "The charcoal burners above %s broke their clamp and it came out sweet. The smith paid without being asked twice.",
				"place": {"stores": 0.05, "mood": 0.05},
				"bias": {"trade": 0.1},
				"spawn": "",
			},
			{
				"id": "clamp_ran",
				"weight": 2.0,
				"line": "The %s burners let the clamp run away in the night. Whole hillside of ash and one man with no eyebrows.",
				"place": {"mood": -0.05, "alarm": 0.1},
				"bias": {"fire": 0.3},
				"spawn": "",
			},
			{
				"id": "burners_gone",
				"weight": 1.0,
				"line": "The burners' camp above %s is empty. Fire still going in the clamp, tools laid out, and not a soul. The smith won't go up to look.",
				"place": {"alarm": 0.3},
				"bias": {"goblins": 0.4},
				"spawn": "goblin_sign",
			},
		],
	},

	## -------------------------------------------- the road & bridges ---
	{
		"id": "bridge_out",
		"title": "Bridge out",
		"scope": "road",
		"tags": ["road", "bridge", "trade"],
		"hours": ALL_DAY,
		"seasons": [],
		"weather": [],
		"regions": [],
		"min_rank": 0,
		"base": 0.4,
		"active": Vector2(72, 240),
		"outcomes": [
			{
				"id": "mended",
				"weight": 3.0,
				"line": "They've got planks back across the %s bridge. It'll bear a man and a barrow. Don't take a cart on it yet.",
				"place": {"mood": 0.05},
				"bias": {"road": -0.3},
				"spawn": "",
			},
			{
				"id": "long_way",
				"weight": 3.0,
				"line": "With the %s bridge down every cart's going round by the ford, and the ford's no friend to anybody.",
				"place": {"stores": -0.08, "mood": -0.05},
				"bias": {"road": 0.3},
				"spawn": "ford_drowned",
			},
			{
				"id": "fell",
				"weight": 1.0,
				"line": "A carter tried the broken bridge at %s with a full load. Horse, cart and carter, all in the river. The horse came out.",
				"place": {"stores": -0.05, "mood": -0.15, "alarm": 0.1},
				"bias": {"road": 0.3},
				"spawn": "",
			},
		],
	},
	{
		"id": "watch_patrol",
		"title": "The watch rides out",
		"scope": "road",
		"tags": ["watch", "patrol", "road"],
		"hours": Vector2(6, 18),
		"seasons": [],
		"weather": [W_CLEAR, W_OVERCAST, W_DRIZZLE],
		"regions": [],
		"min_rank": 1,
		"base": 0.8,
		"active": Vector2(12, 48),
		"outcomes": [
			{
				"id": "quiet",
				"weight": 4.0,
				"line": "The watch rode the road from %s to the crossing and back and saw nothing worse than a fox. They're calling it a good day.",
				"place": {"alarm": -0.15, "watch": 0.1},
				"bias": {"bandits": -0.2},
				"spawn": "",
			},
			{
				"id": "bandits",
				"weight": 2.0,
				"line": "The %s watch came up on a bandit camp in the cut and took two of them alive. The third ran. He'll be back with friends.",
				"place": {"alarm": 0.1, "watch": 0.15, "mood": 0.1},
				"bias": {"bandits": -0.3},
				"spawn": "",
			},
			{
				"id": "rider_lost",
				"weight": 1.0,
				"line": "One of the %s watch didn't come back from patrol. Horse came home on its own with the saddle turned.",
				"place": {"alarm": 0.3, "watch": -0.2, "mood": -0.15},
				"bias": {"bandits": 0.3, "goblins": 0.2},
				"spawn": "",
			},
		],
	},
	{
		"id": "pilgrims",
		"title": "Pilgrims on the road",
		"scope": "road",
		"tags": ["pilgrims", "road", "faith"],
		"hours": Vector2(7, 19),
		"seasons": [SPRING, SUMMER, AUTUMN],
		"weather": [W_CLEAR, W_OVERCAST, W_DRIZZLE],
		"regions": ["KATAHDIN", "ACADIA", "BAXTER STATE PARK"],
		"min_rank": 0,
		"base": 0.9,
		"active": Vector2(12, 36),
		"outcomes": [
			{
				"id": "passed",
				"weight": 3.0,
				"line": "Forty pilgrims through %s today bound for the mountain, singing the whole way. They bought every loaf in the place.",
				"place": {"stores": -0.05, "mood": 0.1},
				"bias": {"trade": 0.1},
				"spawn": "",
			},
			{
				"id": "mended_pots",
				"weight": 2.0,
				"line": "The pilgrims that stopped at %s had a woman with them who mended every pot in the village for a bed and a bowl. Wish they'd all stay.",
				"place": {"mood": 0.15},
				"bias": {},
				"spawn": "",
			},
			{
				"id": "left_behind",
				"weight": 2.0,
				"line": "A pilgrim party left one of their own at %s, too footsore to go on. Now he eats and doesn't work and the village is starting to say so.",
				"place": {"stores": -0.05, "mood": -0.1},
				"bias": {"unrest": 0.1},
				"spawn": "",
			},
			{
				"id": "robbed",
				"weight": 1.0,
				"line": "Pilgrims came into %s stripped to their shirts. Met men on the road who took their offerings and their boots and left them the hymns.",
				"place": {"alarm": 0.2, "mood": -0.1},
				"bias": {"bandits": 0.5},
				"spawn": "watch_patrol",
			},
		],
	},
	{
		"id": "stranger_passing",
		"title": "A stranger passing",
		"scope": "place",
		"tags": ["stranger", "road", "rumour"],
		"hours": Vector2(16, 23),
		"seasons": [],
		"weather": [],
		"regions": [],
		"min_rank": 0,
		"base": 1.1,
		"active": Vector2(6, 24),
		"outcomes": [
			{
				"id": "old_silver",
				"weight": 3.0,
				"line": "Stranger came through %s with a hood up and paid in old silver for a bed he never slept in. Gone before the cock.",
				"place": {"mood": 0.05},
				"bias": {"ruins": 0.2},
				"spawn": "",
			},
			{
				"id": "asked",
				"weight": 3.0,
				"line": "A stranger at %s was asking after the old road up the mountain. Nobody told him. Somebody will have.",
				"place": {"alarm": 0.1},
				"bias": {"ruins": 0.2},
				"spawn": "",
			},
			{
				"id": "stole",
				"weight": 2.0,
				"line": "That stranger who stopped at %s left in the night with the widow's mule and her son's boots. Should have known by the way he sat.",
				"place": {"stores": -0.05, "mood": -0.1, "alarm": 0.1},
				"bias": {"bandits": 0.2},
				"spawn": "",
			},
			{
				"id": "horse_leech",
				"weight": 1.0,
				"line": "The stranger at %s turned out to be a horse-leech and put the miller's mare right in an evening. Wouldn't take coin. Took the foal, though.",
				"place": {"mood": 0.1},
				"bias": {"murrain": -0.2},
				"spawn": "",
			},
		],
	},

	## ------------------------------------------------- the deep wild ---
	{
		"id": "poaching",
		"title": "Poachers in the lord's wood",
		"scope": "wild",
		"tags": ["poaching", "deer", "watch", "hunger"],
		"hours": Vector2(18, 6),
		"seasons": [],
		"weather": [],
		"regions": [],
		"min_rank": 0,
		"base": 0.7,
		"active": Vector2(12, 36),
		"outcomes": [
			{
				"id": "snares",
				"weight": 4.0,
				"line": "The warden found a line of snares in the wood above %s. Pulled them all and left a note. He can't write, so it was a drawing.",
				"place": {"watch": 0.05},
				"bias": {"poaching": 0.2},
				"spawn": "",
			},
			{
				"id": "caught",
				"weight": 2.0,
				"line": "The warden took a man from %s with a hind over his shoulder. He'll lose a hand for it if the lord's in a bad mood, and the lord is always in a bad mood.",
				"place": {"mood": -0.15, "alarm": 0.1},
				"bias": {"unrest": 0.3, "poaching": -0.2},
				"spawn": "",
			},
			{
				"id": "warden_shot",
				"weight": 1.0,
				"line": "Somebody put an arrow in the warden's leg up past %s. Nobody saw anything. Nobody ever does.",
				"place": {"alarm": 0.25, "watch": -0.15, "mood": -0.05},
				"bias": {"poaching": 0.4, "unrest": 0.3},
				"spawn": "watch_patrol",
			},
		],
	},
	{
		"id": "hunters_find",
		"title": "A hunter's find",
		"scope": "wild",
		"tags": ["hunt", "deepwood", "find"],
		"hours": Vector2(6, 18),
		"seasons": [],
		"weather": [W_CLEAR, W_OVERCAST],
		"regions": ["100-MILE WILDERNESS", "BIGELOW RANGE", "MAHOOSUCS", "RANGELEY LAKES"],
		"min_rank": -1,
		"base": 0.8,
		"active": Vector2(6, 24),
		"outcomes": [
			{
				"id": "stag",
				"weight": 3.0,
				"line": "A hunter out of %s dropped a stag with a rack you couldn't lift alone. Meat for every house on the row.",
				"place": {"stores": 0.1, "mood": 0.1},
				"bias": {"hunger": -0.2},
				"spawn": "",
			},
			{
				"id": "old_hut",
				"weight": 2.0,
				"line": "Fellow hunting above %s found a stone hut in the woods nobody's got a name for. Full of bones, he says. Big ones.",
				"place": {"alarm": 0.1},
				"bias": {"ruins": 0.3},
				"spawn": "",
			},
			{
				"id": "body",
				"weight": 1.5,
				"line": "One of the %s hunters came on a dead man in a thicket, been there since the snow went. Purse still on him. That's what's odd.",
				"place": {"alarm": 0.2, "mood": -0.1},
				"bias": {"goblins": 0.2, "ruins": 0.1},
				"spawn": "",
			},
			{
				"id": "bear_maul",
				"weight": 1.0,
				"line": "The bear got the better of a hunter above %s. They carried him down on a hurdle with his coat over his face. He was talking under it, so that's something.",
				"place": {"alarm": 0.2, "mood": -0.05},
				"bias": {"bears": 0.4},
				"spawn": "",
			},
		],
	},
	{
		"id": "ravens_field",
		"title": "Ravens on the old field",
		"scope": "wild",
		"tags": ["ravens", "battlefield", "ruins", "omen"],
		"hours": Vector2(6, 18),
		"seasons": [],
		"weather": [W_CLEAR, W_OVERCAST],
		"regions": ["KATAHDIN", "PENOBSCOT R.", "AROOSTOOK", "100-MILE WILDERNESS"],
		"min_rank": -1,
		"base": 0.6,
		"active": Vector2(12, 48),
		"outcomes": [
			{
				"id": "gathered",
				"weight": 3.0,
				"line": "Ravens over the old battlefield past %s, hundreds of them, gone by dusk. What they were after, no one went up to find out.",
				"place": {"alarm": 0.05},
				"bias": {"omen": 0.2},
				"spawn": "",
			},
			{
				"id": "fresh_dead",
				"weight": 2.0,
				"line": "The ravens past %s were on something fresh. A dozen goblins and two men, laid out in a row. Somebody's fighting somebody up there.",
				"place": {"alarm": 0.3},
				"bias": {"goblins": 0.4, "bandits": 0.2},
				"spawn": "goblin_sign",
			},
			{
				"id": "digging",
				"weight": 1.0,
				"line": "There's been digging on the old field past %s. Barrows opened. Ravens sat on the spoil-heaps like they're waiting to be paid.",
				"place": {"alarm": 0.2, "mood": -0.1},
				"bias": {"ruins": 0.5, "omen": 0.3},
				"spawn": "",
			},
		],
	},

	## --------------------------------------------------- the coast ---
	{
		"id": "boat_overdue",
		"title": "Boat overdue",
		"scope": "place",
		"tags": ["boat", "sea", "alarm", "trade"],
		"hours": ALL_DAY,
		"seasons": [],
		"weather": [],
		"regions": COAST,
		"gate_regions": true,
		"min_rank": 0,
		"base": 1.0,
		"active": Vector2(24, 96),
		"outcomes": [
			{
				"id": "came_in",
				"weight": 4.0,
				"line": "The %s boat came in three days late with a torn sail and a hold of cod, and the whole quay laughing with relief.",
				"place": {"stores": 0.1, "mood": 0.2},
				"bias": {"trade": 0.1},
				"spawn": "",
			},
			{
				"id": "wreck",
				"weight": 2.0,
				"line": "Wreckage on the beach east of %s. A mast, a chest, a boot. They know whose boat. They're not saying yet.",
				"place": {"mood": -0.3, "stores": -0.05},
				"bias": {"omen": 0.2},
				"spawn": "",
			},
			{
				"id": "empty",
				"weight": 1.0,
				"line": "They found the %s boat off the point, sound as a bell, and nobody in her. Oars shipped. Lines set. Nobody.",
				"place": {"mood": -0.2, "alarm": 0.3},
				"bias": {"omen": 0.4},
				"spawn": "",
			},
		],
	},

	## ------------------------------------------------------- the coast ---
	## Twenty of the fifty places sit in a coastal region and until these two
	## they shared exactly one kind of their own between them, so Down East
	## heard nothing but weather, harvest and strangers. Both are gated: a
	## herring glut at Fort Kent would be a joke at the file's expense.
	{
		"id": "wreck_ashore",
		"title": "Something came ashore",
		"scope": "place",
		"tags": ["sea", "salvage", "trade", "omen"],
		"hours": Vector2(5, 20),
		"seasons": [],
		"weather": [],
		"regions": COAST,
		"gate_regions": true,
		"min_rank": 0,
		"base": 0.9,
		"active": Vector2(8, 30),
		"outcomes": [
			{
				"id": "timber",
				"weight": 4.0,
				"line": "Half a deck's worth of good oak came ashore below %s on the night tide. It was in three barns before the reeve had his boots on.",
				"place": {"mood": 0.15, "stores": 0.05},
				"bias": {"salvage": 0.3},
				"spawn": "",
			},
			{
				"id": "cargo",
				"weight": 2.0,
				"line": "Barrels on the shingle at %s, wax-sealed, and nobody's name burned on them. The headman has them under his own roof, which nobody likes and nobody says.",
				"place": {"mood": -0.05, "stores": 0.15},
				"bias": {"salvage": 0.4, "unrest": 0.2},
				"spawn": "stranger_passing",
			},
			{
				"id": "drowned",
				"weight": 2.0,
				"line": "A man came in with the weed at %s, face down and a week in the water. No boat missing from here. They buried him above the tide line without a name.",
				"place": {"mood": -0.2, "alarm": 0.15},
				"bias": {"omen": 0.4},
				"spawn": "",
			},
			{
				"id": "beast",
				"weight": 1.0,
				"line": "Something rotted onto the flats at %s that the fishermen will not put a name to. Ribs like a boat's. They burned it where it lay and the smoke was wrong.",
				"place": {"mood": -0.15, "alarm": 0.25},
				"bias": {"omen": 0.6},
				"spawn": "",
			},
		],
	},
	{
		"id": "herring_run",
		"title": "The run comes in",
		"scope": "place",
		"tags": ["sea", "fish", "harvest", "hunger"],
		"hours": Vector2(4, 12),
		"seasons": [SPRING, SUMMER, AUTUMN],
		"weather": [W_CLEAR, W_OVERCAST, W_DRIZZLE],
		"regions": COAST,
		"gate_regions": true,
		"min_rank": 0,
		"base": 1.2,
		"active": Vector2(10, 40),
		"outcomes": [
			{
				"id": "glut",
				"weight": 4.0,
				"line": "The run came in thick at %s and they were carting fish up the beach by lantern. Everything smells of it and nobody is complaining yet.",
				"place": {"stores": 0.25, "mood": 0.2},
				"bias": {"trade": 0.2},
				"spawn": "",
			},
			{
				"id": "thin",
				"weight": 3.0,
				"line": "The run went by wide of %s this year. The nets came up with weed and two dogfish, and the salt bought for it is still in the barrel.",
				"place": {"stores": -0.1, "mood": -0.15},
				"bias": {"hunger": 0.3},
				"spawn": "",
			},
			{
				"id": "boat_lost",
				"weight": 1.5,
				"line": "Two boats went out of %s after the run and one came back. The other's oars turned up at the point, which is how they know not to keep looking.",
				"place": {"mood": -0.3, "alarm": 0.2},
				"bias": {"omen": 0.3},
				"spawn": "boat_overdue",
			},
		],
	},

	## ---------------------------------------------------- the town ---
	{
		"id": "lost_child",
		"title": "A child lost",
		"scope": "place",
		"tags": ["child", "search", "alarm"],
		"hours": Vector2(15, 23),
		"seasons": [SPRING, SUMMER, AUTUMN],
		"weather": [],
		"regions": [],
		"min_rank": 0,
		"base": 0.5,
		"active": Vector2(4, 16),
		"outcomes": [
			{
				"id": "hay_rick",
				"weight": 3.0,
				"line": "The %s child that was lost turned up asleep in a hay-rick a hundred yards from her own door, with the village out on the hill calling her name.",
				"place": {"mood": 0.15, "alarm": -0.1},
				"bias": {},
				"spawn": "",
			},
			{
				"id": "dog_brought",
				"weight": 3.0,
				"line": "The %s boy walked into the wood after a fox and the dog brought him home, both of them soaked. The dog got the supper.",
				"place": {"mood": 0.1},
				"bias": {},
				"spawn": "",
			},
			{
				"id": "found_cold",
				"weight": 2.0,
				"line": "They found the %s girl at first light under a spruce, blue with cold. Breathing. Her mother hasn't let go of her since.",
				"place": {"mood": 0.05, "alarm": 0.05},
				"bias": {},
				"spawn": "",
			},
			{
				"id": "not_found",
				"weight": 1.0,
				"line": "Three days searching the woods below %s and no sign of that child. They've stopped calling. Nobody says why.",
				"place": {"mood": -0.35, "alarm": 0.3},
				"bias": {"goblins": 0.3, "wolves": 0.2},
				"spawn": "",
			},
		],
	},
	{
		"id": "bell_wrong",
		"title": "The bell rung wrong",
		"scope": "place",
		"tags": ["bell", "alarm", "watch"],
		"hours": ALL_DAY,
		"seasons": [],
		"weather": [],
		"regions": [],
		"min_rank": 1,
		"base": 0.5,
		"active": Vector2(1, 6),
		"outcomes": [
			{
				"id": "sexton",
				"weight": 3.0,
				"line": "Somebody rang the alarm bell in %s at midnight and the town came out in its shirt. It was the sexton, drunk.",
				"place": {"mood": -0.05, "alarm": -0.05},
				"bias": {},
				"spawn": "",
			},
			{
				"id": "wrong_peal",
				"weight": 2.0,
				"line": "The %s bell rang the wrong peal in the night, three and a pause and three, and nobody's admitting they know what that means.",
				"place": {"alarm": 0.2},
				"bias": {"unrest": 0.1},
				"spawn": "",
			},
			{
				"id": "real",
				"weight": 1.0,
				"line": "The bell at %s rang the alarm and it was no mistake. Torches on the ridge road. Whatever it was, it saw the town come out and thought better.",
				"place": {"alarm": 0.35, "watch": 0.1},
				"bias": {"goblins": 0.3, "bandits": 0.2},
				"spawn": "watch_patrol",
			},
		],
	},
	{
		"id": "fair",
		"title": "Fair day",
		"scope": "place",
		"tags": ["fair", "trade", "unrest"],
		"hours": Vector2(8, 22),
		"seasons": [SUMMER, AUTUMN],
		"weather": [W_CLEAR, W_OVERCAST],
		"regions": [],
		"min_rank": 1,
		"base": 1.0,
		"active": Vector2(12, 48),
		"outcomes": [
			{
				"id": "good",
				"weight": 4.0,
				"line": "Fair at %s was the best in years. A bear that danced, a man who ate fire, and the ale held out past dark.",
				"place": {"mood": 0.25, "stores": 0.05},
				"bias": {"trade": 0.3},
				"spawn": "",
			},
			{
				"id": "brawl",
				"weight": 2.0,
				"line": "Fair at %s ended with two villages in the horse pond and the reeve's teeth in the mud. Same as last year, only wetter.",
				"place": {"mood": 0.05, "alarm": 0.1, "watch": -0.05},
				"bias": {"unrest": 0.2},
				"spawn": "",
			},
			{
				"id": "cutpurses",
				"weight": 1.0,
				"line": "Cutpurses worked the %s fair like a field of barley. Half the town's home with empty pockets and a headache.",
				"place": {"mood": -0.15, "stores": -0.05},
				"bias": {"bandits": 0.3, "unrest": 0.1},
				"spawn": "watch_patrol",
			},
		],
	},
]


## =============================== Lookup ==================================


static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for k in KINDS:
		out.append(String((k as Dictionary).get("id", "")))
	return out


static func by_id(id: String) -> Dictionary:
	## A linear scan. Thirty-odd entries, called a few times a game hour: an
	## index would be a static var, and this file promised to hold no state.
	for k in KINDS:
		var kd := k as Dictionary
		if String(kd.get("id", "")) == id:
			return kd
	return {}


## ============================== Weighting ================================


static func hour_in_band(hour: float, band: Vector2) -> bool:
	## Continuous, inclusive at both ends, and it wraps: Vector2(21, 4) is
	## "from nine at night until four in the morning", which holds 23:00 and
	## 02:00 and rejects 04:30. Not floored to whole hours — Chronicle steps by
	## the half hour, so 20:30 must be outside a band that starts at 21:00 or a
	## kind fires half an hour before its own window. The cost is that a band
	## meaning "all day" has to be written 0..24, not 0..23, which is what
	## ALL_DAY is for.
	var h := fposmod(hour, 24.0)
	var lo := band.x
	var hi := band.y
	if lo <= hi:
		return h >= lo and h <= hi
	return h >= lo or h <= hi


static func weight_for(kind: Dictionary, ctx: Dictionary) -> float:
	## Four hard gates, then the multipliers, in exactly this order — the tests
	## hand-compute against it, and so should anyone tuning a kind. Gates
	## return 0 rather than a small number because a kind that "can't quite"
	## fire in winter is a kind that fires in winter once every long enough.
	if not hour_in_band(float(ctx.get("hour", 12.0)), kind.get("hours", ALL_DAY) as Vector2):
		return 0.0
	var seasons: Array = kind.get("seasons", [])
	if not seasons.is_empty() and not seasons.has(int(ctx.get("season", 0))):
		return 0.0
	var weather: Array = kind.get("weather", [])
	if not weather.is_empty() and not weather.has(int(ctx.get("weather", 0))):
		return 0.0
	var min_rank := int(kind.get("min_rank", -1))
	if min_rank >= 0 and int(ctx.get("rank", 0)) < min_rank:
		return 0.0
	## The fifth gate, and the only optional one: a kind that declares
	## "gate_regions" cannot happen outside the regions it names at all. Kinds
	## without the flag are unaffected, which is why the hand-computed weight
	## arithmetic in the suite still holds.
	if bool(kind.get("gate_regions", false)) \
			and not (kind.get("regions", []) as Array).has(String(ctx.get("region", ""))):
		return 0.0

	var w := float(kind.get("base", 1.0))

	## Region is a preference, not a gate: wolves are a KATAHDIN story but a
	## Casco Bay village can still lose a ewe. Away from home it is rare, not
	## impossible, and that is what keeps the coast from feeling like a
	## different game.
	var regions: Array = kind.get("regions", [])
	if not regions.is_empty():
		w *= REGION_HOME if regions.has(String(ctx.get("region", ""))) else REGION_AWAY

	## The world remembering. Summed over the kind's tags, so a kind tagged
	## both "wolves" and "livestock" hears both echoes. Floored, never zeroed:
	## a run of good wolf hunts should quiet the wolves, not abolish them.
	var tags: Array = kind.get("tags", [])
	var bias: Dictionary = ctx.get("bias", {})
	var b := 0.0
	for t in tags:
		b += float(bias.get(t, 0.0))
	w *= maxf(1.0 + b, BIAS_FLOOR)

	## The three feedback loops. Each reads the PLACE's own state, so they are
	## local: a frightened Bangor does not make Portland hear drums.
	if tags.has(TAG_ALARM):
		w *= 1.0 + ALARM_GAIN * float(ctx.get("alarm", 0.0))
	if tags.has(TAG_HUNGER):
		w *= 1.0 + HUNGER_GAIN * (1.0 - float(ctx.get("stores", 1.0)))
	if tags.has(TAG_UNREST):
		w *= 1.0 + UNREST_GAIN * (1.0 - float(ctx.get("mood", 1.0)))

	return maxf(w, 0.0)


static func pick_outcome(kind: Dictionary, roll: float) -> Dictionary:
	## A weighted walk on a 0..1 roll. Chronicle owns the RNG; this only
	## turns its number into an outcome, so the same seed always tells the
	## same story. Roll 0 is the first outcome, roll just under 1 is the last,
	## and a roll of exactly 1 (or anything past it) also lands on the last —
	## it must never fall off the end and hand back nothing.
	var outs: Array = kind.get("outcomes", [])
	if outs.is_empty():
		return {}
	var total := 0.0
	for o in outs:
		total += maxf(float((o as Dictionary).get("weight", 0.0)), 0.0)
	if total <= 0.0:
		return outs[0] as Dictionary
	var target := clampf(roll, 0.0, 1.0) * total
	var acc := 0.0
	for o in outs:
		acc += maxf(float((o as Dictionary).get("weight", 0.0)), 0.0)
		if target < acc:
			return o as Dictionary
	return outs[outs.size() - 1] as Dictionary


## =============================== Checking ================================


static func problems() -> PackedStringArray:
	## Every rule the catalogue promises, as a list of the ones it breaks.
	## Empty means clean. Chronicle can assert on this at boot and the tests
	## can print it, which is far kinder than a "%s" that turned out to be two
	## of them at the moment a rumour is formatted in a tavern.
	var out := PackedStringArray()
	var seen := {}
	var all_ids := ids()
	for k in KINDS:
		var kd := k as Dictionary
		var id := String(kd.get("id", ""))
		var where := "kind '%s'" % id
		if id.is_empty():
			out.append("a kind has no id")
		elif seen.has(id):
			out.append("%s: duplicate id" % where)
		seen[id] = true
		for key in ["title", "scope", "tags", "hours", "seasons", "weather", "regions", "min_rank", "base", "active", "outcomes"]:
			if not kd.has(key):
				out.append("%s: missing '%s'" % [where, key])
		var hours: Vector2 = kd.get("hours", Vector2(-1, -1))
		if hours.x < 0.0 or hours.x > 24.0 or hours.y < 0.0 or hours.y > 24.0:
			out.append("%s: hours band %s outside 0..24" % [where, hours])
		var active: Vector2 = kd.get("active", Vector2(-1, -1))
		if active.x <= 0.0 or active.y < active.x:
			out.append("%s: active band %s is not min<=max, >0" % [where, active])
		if not ["place", "road", "wild"].has(String(kd.get("scope", ""))):
			out.append("%s: scope must be place|road|wild" % where)
		if bool(kd.get("gate_regions", false)) and (kd.get("regions", []) as Array).is_empty():
			out.append("%s: gate_regions with no regions can never fire" % where)
		var outs: Array = kd.get("outcomes", [])
		if outs.size() < 2:
			out.append("%s: fewer than 2 outcomes" % where)
		var oseen := {}
		for o in outs:
			var od := o as Dictionary
			var oid := String(od.get("id", ""))
			if oseen.has(oid):
				out.append("%s: duplicate outcome id '%s'" % [where, oid])
			oseen[oid] = true
			if float(od.get("weight", 0.0)) <= 0.0:
				out.append("%s/%s: weight must be > 0" % [where, oid])
			var line := String(od.get("line", ""))
			if line.count("%s") != 1 or line.count("%") != 1:
				out.append("%s/%s: line must hold exactly one %%s" % [where, oid])
			var spawn := String(od.get("spawn", ""))
			if not spawn.is_empty() and not all_ids.has(spawn):
				out.append("%s/%s: spawn '%s' is not a kind" % [where, oid, spawn])
			var place: Dictionary = od.get("place", {})
			for pk in place.keys():
				if not ["mood", "stores", "alarm", "watch"].has(String(pk)):
					out.append("%s/%s: place delta '%s' is not a place axis" % [where, oid, pk])
	return out
