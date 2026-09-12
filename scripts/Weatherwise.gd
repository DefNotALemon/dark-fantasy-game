class_name Weatherwise
extends RefCounted

## ===========================================================================
## WEATHERWISE — what the sky does to everything that lives under it.
##
## Myrkfell has had a full weather model since the day the wildlife landed,
## and in all that time not one animal has ever noticed it. `docs/WILDLIFE.md`
## gap 7 says so in as many words: "Rain should quiet the birds and put the
## deer up; a storm should empty the sky of soaring raptors; and `red_eft` is
## flagged `rain_only` but nothing checks for rain."
##
## THE IDEA IS THAT A STORM DOES NOT EMPTY THE WOODS. IT SORTS THEM.
##
## Every animal in the dex has somewhere to be when the sky opens, and the
## whole feature is that *where* differs. An eagle cannot fly without a
## thermal and is gone before the first drop falls. A jay goes under a bough.
## A blackfly is physically knocked out of the air. A fox has never had better
## hunting in its life. And a Red Eft — a species that has been in this game
## since August and that no player has ever been able to meet — walks out onto
## the open forest floor, because rain is the only weather it has.
##
## Measured through the real spawn pool (`tools/probe_weatherwise.gd`), what
## that adds up to is a thing no line in this file says: in a full storm the
## DEEP WOODS keep 42% of their spawn weight and the OPEN FIELD keeps 16%.
## One table, no mention of terrain anywhere in it, and the woods shelter you
## and the field does not.
##
## THE SECOND HALF IS THE OTHER DIRECTION: WHAT THE WEATHER DOES TO *YOU*.
## `Telegraph.player_noise` is the stealth mechanic — crashing through brush
## rings the forest ahead of you. Rain is loud. From DRIZZLE onward a sprint
## no longer reaches a whitetail standing at its own notice radius, so you can
## run in the wet woods without emptying them. The price is exact and it is
## paid in the same coin: the alarm RELAY is cut by the same rain, so the word
## stops travelling. **Rain buys you stealth and takes away your intelligence.**
##
## No node, no clock, no RNG, no `get_tree`, no state. Everything here is a
## pure function of a species key and an environment dictionary, exactly like
## `Seasons`, `Slumber` and `Garments`.
##
## Read by:  WildlifeDirector._roll_species / _try_swarm / _legend_check
##           Telegraph.player_noise / _ring
##           Critter._physics_process  (the cover urge)
## ===========================================================================


## ============================== The guilds ================================
##
## A guild is NOT a taxon. It is an answer to one question: what does foul
## weather do to this animal? Eight of them cover all 73 species, and every
## membership is DERIVED from `CritterDex` — the rig family and the flags the
## dex already carries — never restated here. Give a new species `soars` and
## it is a SOARING animal with no edit in this file; give it a rig this
## classifier has never seen and `table_problems()` goes red and says which.

enum Guild {
	SOARING,      ## needs a thermal. The first thing the sky loses.
	SHELTERING,   ## gets under something: land birds, squirrels, basking herps
	FLATTENED,    ## insects and bats. Rain knocks them out of the air.
	DRAWN,        ## the rain is the INVITATION. Efts and wood frogs.
	UNBOTHERED,   ## already wet: fish, waterfowl, otters, turtles
	HUNTING,      ## foul weather is an advantage. Canids, felids, mustelids.
	BEDDING,      ## stirs before a front, lies up in the worst of it
	VOICE,        ## audio_only — never spawned, so never weighted
	LEGEND,       ## placed, never rolled. The weather must not touch these.
}

const GUILD_NAMES := [
	"SOARING", "SHELTERING", "FLATTENED", "DRAWN",
	"UNBOTHERED", "HUNTING", "BEDDING", "VOICE", "LEGEND",
]


## ============================== The tables ================================
##
## Indexed by Weather.Level: CLEAR OVERCAST DRIZZLE RAIN STORM.
##
## ⚠ EVERY ROW IS EXACTLY 1.0 AT CLEAR, BY CONSTRUCTION AND BY ASSERTION.
## Fair weather is the world Myrkfell already has and this feature is not
## allowed to move it. Everything below is a departure from a day that stays
## exactly as it was.
##
## These four rows were not chosen. `tools/probe_weatherwise.gd` swept three
## candidate sets against the real dex pool before a line of this file
## existed, and the three disagreed in a way that decided the answer:
##
##   * the timid set held the Red Eft at one animal in six on a wet dawn,
##     which is right — but left four soaring birds still in the sky at the
##     height of a storm, which is the one thing the gap list asked for.
##   * the bold set emptied the sky properly and made the eft one animal in
##     four, which is a nature documentary about newts.
##   * the extreme set took a midday field down to 5% of its animals. That is
##     not a storm, that is a ghost town.
##
## So this is the FIT: the bold SOARING row, the timid DRAWN / HUNTING /
## BEDDING / UNBOTHERED rows, and a SHELTERING row split between them.

const OUT := {
	Guild.SOARING:    [1.0, 0.45, 0.12, 0.00, 0.00],
	Guild.SHELTERING: [1.0, 0.85, 0.50, 0.25, 0.10],
	Guild.FLATTENED:  [1.0, 0.85, 0.40, 0.12, 0.00],
	Guild.DRAWN:      [1.0, 1.40, 1.60, 2.40, 1.80],
	Guild.UNBOTHERED: [1.0, 1.00, 1.00, 1.00, 0.90],
	Guild.HUNTING:    [1.0, 1.05, 1.15, 1.20, 0.80],
	Guild.BEDDING:    [1.0, 1.15, 1.25, 0.60, 0.25],
	Guild.VOICE:      [1.0, 1.00, 1.00, 1.00, 1.00],
	Guild.LEGEND:     [1.0, 1.00, 1.00, 1.00, 1.00],
}

## How badly an animal that IS out wants to be under something, 0..1. This is
## the behaviour half: it scales how far a calm animal will wander and how
## often it bothers to call, so a deer in a downpour stands under a tree
## instead of grazing across a hillside.
const COVER := {
	Guild.SOARING:    [0.0, 0.20, 0.55, 0.85, 1.00],
	Guild.SHELTERING: [0.0, 0.15, 0.45, 0.75, 0.95],
	Guild.FLATTENED:  [0.0, 0.10, 0.40, 0.80, 1.00],
	Guild.DRAWN:      [0.0, 0.00, 0.00, 0.00, 0.10],
	Guild.UNBOTHERED: [0.0, 0.00, 0.05, 0.10, 0.25],
	Guild.HUNTING:    [0.0, 0.00, 0.05, 0.15, 0.45],
	Guild.BEDDING:    [0.0, 0.05, 0.15, 0.60, 0.90],
	Guild.VOICE:      [0.0, 0.00, 0.00, 0.00, 0.00],
	Guild.LEGEND:     [0.0, 0.00, 0.00, 0.00, 0.00],
}

## What the rain does to the player's own noise on the Telegraph.
##
## ⚠ THE INTERESTING NUMBER IS NOT IN THIS ARRAY, IT IS THE CROSSING.
## `Telegraph.player_noise` rings a sprint at 34.0 m and a whitetail notices
## at 30.0 m (both numbers belong to other files; neither is restated here).
## The rung at which `34 * mask` first falls under 30 is the rung at which you
## can start running in the woods without emptying them ahead of you — and
## the suite SEARCHES for that rung rather than asserting near it.
const NOISE_MASK := [1.00, 0.92, 0.78, 0.58, 0.40]

## And the price. The forest's alarm network is hearing too: each relay hop
## keeps `Telegraph.RELAY_FALLOFF` of its radius and dies under
## `RELAY_MIN_RADIUS`, so cutting the hop shortens the chain. Measured
## against those two constants, a storm takes the word from four hops to one.
const RELAY_MASK := [1.00, 1.00, 0.85, 0.65, 0.45]

## A falling barometer stirs the big herbivores BEFORE the weather lands —
## the hour in front of a storm is the best hunting in Myrkfell, and it is
## over the moment the rain arrives. Applied only where an animal could
## plausibly read the sky.
const FRONT_STIR := 0.35
const FRONT_GUILDS := [Guild.BEDDING, Guild.HUNTING]

## A `rain_only` species is unreachable when it is dry. This is the flag
## finally meaning something: below this rung the multiplier is not small,
## it is ZERO.
const RAIN_ONLY_RUNG := 2.0      ## DRIZZLE

## `fog_only` is the same shape on the other dead flag: the Specter Moose
## wants the soft grey band, not a clear night and not a downpour.
const FOG_BAND := Vector2(0.8, 3.0)

const LEVEL_NAMES := ["clear", "overcast", "drizzle", "rain", "storm"]


## ============================ The environment =============================


static func env(level: int, from_level: int, blend: float, hour := 12.0) -> Dictionary:
	## The door every caller comes through. `level` is where the sky is HEADED
	## and `from_level` is where it came from — that is Weather.gd's own
	## vocabulary, and the gap between them is the front.
	return {
		"level": level,
		"from": from_level,
		"blend": clampf(blend, 0.0, 1.0),
		"hour": hour,
	}


static func rung(e: Dictionary) -> float:
	## The weather as the animals actually feel it: a continuous 0..4 between
	## where the sky was and where it is going. Continuous on purpose — a
	## stepped answer would make every creature in the world change its mind on
	## the same frame, which is the exact discontinuity `Seasons.sample()` was
	## built to avoid at the turn of a season.
	var a := float(e.get("from", 0))
	var b := float(e.get("level", 0))
	var t := clampf(float(e.get("blend", 1.0)), 0.0, 1.0)
	return clampf(lerpf(a, b, t), 0.0, 4.0)


static func front(e: Dictionary) -> float:
	## The barometer, −1..+1. Positive while the sky is still worsening and the
	## front has not landed; negative while it is clearing. Zero once the blend
	## completes, whatever the weather is — a storm that has ARRIVED is not a
	## storm that is COMING, and only the second one stirs anything.
	var d := float(e.get("level", 0)) - float(e.get("from", 0))
	var left := 1.0 - clampf(float(e.get("blend", 1.0)), 0.0, 1.0)
	return clampf(d * left * 0.5, -1.0, 1.0)


static func level_name(e: Dictionary) -> String:
	var r := rung(e)
	return String(LEVEL_NAMES[clampi(int(round(r)), 0, 4)])


## ============================ The classifier ==============================


static func guild_of(key: String) -> int:
	## Ordered, and the order is the whole of it. Read top to bottom: the first
	## question that gets a yes decides, so `moose` is a CERVID before it is a
	## thing flagged `water`, and a legend is a legend before it is anything.
	if bool(CritterDex.flag(key, "legend", false)):
		return Guild.LEGEND
	if bool(CritterDex.flag(key, "audio_only", false)):
		return Guild.VOICE
	if bool(CritterDex.flag(key, "soars", false)):
		return Guild.SOARING
	var rig := String(CritterDex.rig_of(key))
	if rig == "SWARM":
		return Guild.FLATTENED
	if rig == "FISH" or rig == "BIRD_WATER":
		return Guild.UNBOTHERED
	if rig == "HERP":
		## A turtle on a log and a newt on the leaf litter want opposite skies,
		## and the dex already knows which is which: `basks` is a fair-weather
		## verb.
		if bool(CritterDex.flag(key, "water", false)):
			return Guild.UNBOTHERED
		if bool(CritterDex.flag(key, "basks", false)):
			return Guild.SHELTERING
		return Guild.DRAWN
	if rig.begins_with("BIRD_"):
		return Guild.SHELTERING
	if bool(CritterDex.flag(key, "water", false)) and (rig == "MUSTELID" or rig == "CHUNK"):
		return Guild.UNBOTHERED
	if rig == "CANID" or rig == "FELID" or rig == "MUSTELID":
		return Guild.HUNTING
	if rig == "RODENT_S":
		return Guild.SHELTERING
	return Guild.BEDDING


static func guild_name(g: int) -> String:
	if g < 0 or g >= GUILD_NAMES.size():
		return "?"
	return String(GUILD_NAMES[g])


## ============================== The answers ===============================


static func _row(tbl: Dictionary, g: int, r: float) -> float:
	## Continuous read of a five-rung row. ⚠ Returns the rung's own value
	## EXACTLY at an integer rung, which is what lets the tables above be read
	## as a plain table and still be smooth between rungs.
	if not tbl.has(g):
		return 1.0
	var row := tbl[g] as Array
	var lo := clampi(int(floorf(r)), 0, 4)
	var hi := clampi(lo + 1, 0, 4)
	var f := r - float(lo)
	return lerpf(float(row[lo]), float(row[hi]), clampf(f, 0.0, 1.0))


static func out_mult(key: String, e: Dictionary) -> float:
	## The spawn-weight term, applied as an OFFSET through
	## `WildlifeDirector._roll_species`' existing multiplier chain — the same
	## shape as the `dusk` term already sitting two lines above it. It never
	## replaces the roll and it never decides a species on its own.
	var r := rung(e)
	if bool(CritterDex.flag(key, "rain_only", false)) and r < RAIN_ONLY_RUNG:
		return 0.0
	var g := guild_of(key)
	var m := _row(OUT, g, r)
	if FRONT_GUILDS.has(g):
		m *= 1.0 + FRONT_STIR * maxf(front(e), 0.0)
	return maxf(m, 0.0)


static func cover_urge(key: String, e: Dictionary) -> float:
	## 0..1. What an animal already in the world does about the sky.
	return clampf(_row(COVER, guild_of(key), rung(e)), 0.0, 1.0)


static func noise_mult(e: Dictionary) -> float:
	## Rain is loud. Multiply the radius a careless player rings at.
	var r := rung(e)
	var lo := clampi(int(floorf(r)), 0, 4)
	var hi := clampi(lo + 1, 0, 4)
	return lerpf(float(NOISE_MASK[lo]), float(NOISE_MASK[hi]), clampf(r - float(lo), 0.0, 1.0))


static func relay_mult(e: Dictionary) -> float:
	## ...and so is the forest. The word stops travelling in the same rain.
	var r := rung(e)
	var lo := clampi(int(floorf(r)), 0, 4)
	var hi := clampi(lo + 1, 0, 4)
	return lerpf(float(RELAY_MASK[lo]), float(RELAY_MASK[hi]), clampf(r - float(lo), 0.0, 1.0))


static func legend_allows(key: String, e: Dictionary) -> bool:
	## `fog_only` is the project's other never-read weather flag — one species,
	## the Specter Moose, and it wants the soft grey band rather than a clear
	## night or the inside of a downpour. Everything else is unconditional:
	## legends are PLACED, never rolled, and the weather must not touch them.
	if not bool(CritterDex.flag(key, "fog_only", false)):
		return true
	var r := rung(e)
	return r >= FOG_BAND.x and r <= FOG_BAND.y


static func hops_left(radius: float, falloff: float, min_radius: float, e: Dictionary) -> int:
	## How far the word gets, counted rather than asserted. Takes the
	## Telegraph's own two constants as arguments so that this file states
	## neither of them and the suite can hand in a table that is wrong.
	var m := relay_mult(e)
	var hops := 0
	var rr := radius
	while hops < 64:
		if rr <= min_radius:
			return hops
		rr = rr * falloff * m
		hops += 1
	return hops


## ============================== Validation ================================


static func problems_in(out_tbl: Dictionary, cover_tbl: Dictionary,
		noise: Array, relay: Array) -> Array:
	## ⚠ THE TABLES COME IN AS ARGUMENTS, THEY ARE NOT READ OFF THE CONSTANTS.
	## A guard that can only ever see a correct table is a guard no mutation
	## can reach (2026-09-11 12:00). The suite hands this function tables that
	## ARE wrong and demands the right complaint back.
	var bad: Array = []
	for g in range(GUILD_NAMES.size()):
		var nm := String(GUILD_NAMES[g])
		if not out_tbl.has(g):
			bad.append("OUT has no row for " + nm)
			continue
		if not cover_tbl.has(g):
			bad.append("COVER has no row for " + nm)
			continue
		var o := out_tbl[g] as Array
		var c := cover_tbl[g] as Array
		if o.size() != 5:
			bad.append("OUT row " + nm + " is not five rungs")
		if c.size() != 5:
			bad.append("COVER row " + nm + " is not five rungs")
		if o.size() == 5 and absf(float(o[0]) - 1.0) > 0.0001:
			bad.append("OUT row " + nm + " moves fair weather")
		if c.size() == 5 and absf(float(c[0])) > 0.0001:
			bad.append("COVER row " + nm + " wants cover in fair weather")
		for v in o:
			if float(v) < 0.0 or float(v) > 6.0:
				bad.append("OUT row " + nm + " is out of range")
				break
		for v in c:
			if float(v) < 0.0 or float(v) > 1.0:
				bad.append("COVER row " + nm + " is not a 0..1 urge")
				break
	## The three claims the whole feature is FOR, stated as validation rather
	## than as prose, so that softening any one of them is a red suite.
	if out_tbl.has(Guild.SOARING) and (out_tbl[Guild.SOARING] as Array).size() == 5:
		if float((out_tbl[Guild.SOARING] as Array)[3]) > 0.0001:
			bad.append("the sky still has soaring birds in it at RAIN")
	if out_tbl.has(Guild.FLATTENED) and (out_tbl[Guild.FLATTENED] as Array).size() == 5:
		if float((out_tbl[Guild.FLATTENED] as Array)[4]) > 0.0001:
			bad.append("insects are still flying in a storm")
	if out_tbl.has(Guild.DRAWN) and (out_tbl[Guild.DRAWN] as Array).size() == 5:
		if float((out_tbl[Guild.DRAWN] as Array)[3]) < 1.5:
			bad.append("rain is not an invitation to anything")
	if noise.size() != 5 or relay.size() != 5:
		bad.append("a mask is not five rungs")
	else:
		if absf(float(noise[0]) - 1.0) > 0.0001 or absf(float(relay[0]) - 1.0) > 0.0001:
			bad.append("a mask moves fair weather")
		for i in range(4):
			if float(noise[i + 1]) > float(noise[i]) + 0.0001:
				bad.append("the noise mask is not monotone")
				break
		for i in range(4):
			if float(relay[i + 1]) > float(relay[i]) + 0.0001:
				bad.append("the relay mask is not monotone")
				break
		if float(noise[4]) > 0.5:
			bad.append("a storm does not hide a running man")
	return bad


static func table_problems() -> Array:
	## The shipped tables, plus the one check that can only be made against the
	## real dex: every species in the game lands in a guild that has a row.
	var bad := problems_in(OUT, COVER, NOISE_MASK, RELAY_MASK)
	for k in CritterDex.DEX.keys():
		var key := String(k)
		var g := guild_of(key)
		if g < 0 or g >= GUILD_NAMES.size():
			bad.append(key + " falls out of the classifier")
		elif not OUT.has(g):
			bad.append(key + " is " + guild_name(g) + ", which has no OUT row")
	return bad


## =============================== Readout ==================================


static func readout(key: String, e: Dictionary) -> String:
	## Read-only dev affordance. No key of its own — it hangs off the F1 god
	## panel's existing stat block like every other one this project has added.
	var g := guild_of(key)
	var f := front(e)
	var sky := level_name(e)
	if f > 0.05:
		sky += " coming"
	elif f < -0.05:
		sky += " lifting"
	return "%s [%s] %s: out x%.2f cover %.0f%%" % [
		key, guild_name(g), sky, out_mult(key, e), 100.0 * cover_urge(key, e)]


static func sky_readout(e: Dictionary) -> String:
	return "sky %s r%.2f front %+.2f | noise x%.2f relay x%.2f" % [
		level_name(e), rung(e), front(e), noise_mult(e), relay_mult(e)]
