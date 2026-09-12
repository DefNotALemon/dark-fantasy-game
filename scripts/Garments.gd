class_name Garments
extends RefCounted

## WHAT YOU ARE WEARING, PRICED IN DEGREES.
##
## Myrkfell has let you wear five pieces of metal since the armour sets
## landed, and nothing in the game has ever asked what metal is LIKE to
## stand around in. `Materials` prices a harness in one currency only --
## how much damage it turns -- so the only question a suit of plate has
## ever answered is how hard its wearer is to kill.
##
## This file asks the other question, and the answer has two halves that
## pull in opposite directions and do not cancel:
##
##   IT BREAKS THE WIND. Plate is the best windbreak in the game, and
##   `Exposure` charges up to `WIND_C` degrees for standing in a gale.
##
##   IT CONDUCTS. Metal on a man is a route the heat takes out of him,
##   and it leaves at a rate proportional to how much colder the air is
##   than he is. That is Newton's, and it is the reason the same steel
##   harness is worth a degree on an autumn evening and costs three on a
##   winter night: the wind term is flat and the metal term is a
##   fraction of a GRADIENT, so the two of them cross somewhere in the
##   autumn and stay crossed until the spring.
##
## Above `Exposure.WARMTH_NEUTRAL_C` the gradient is zero and the
## conduction term vanishes outright, so a summer harness is pure
## windbreak and what it is made of stops mattering. Which is correct,
## and is why nobody has ever noticed.
##
## ## The metal decides which way it goes
##
## `Materials.MATS` has carried an `element` on seven of its ten metals
## since it was written, and it has only ever been read for damage.
## Frost, Ember, Dragonfire, Soulfire: the table already knows which
## metals are cold to the touch and which ones are not. `CONDUCT` prices
## that, `table_problems()` refuses to let the two tables drift apart,
## and the consequence is the whole point of the file --
##
##   COLD IRON IS THE BEST ARMOUR IN THE GAME AGAINST WHAT LIVES IN THE
##   DARK, AND THE WORST THING IN THE GAME TO SLEEP IN.
##
## -- so a set is now a choice between what it turns and what it costs
## you at four in the morning, and those two numbers live on two
## different tables on purpose. `dress()` is the other side of the same
## coin: it hands back the warmest set your pack can make TONIGHT, and
## in summer, when no metal conducts anything, it quietly hands back
## your best armour instead.
##
## ## What this file does not do
##
## Metal does nothing whatever for being WET. `Exposure.WET_CHILL_C` is
## nine degrees and up to nine more in a gale, and not one of them is
## refundable here -- worse, a full harness holds the water against you
## (`dry_mult`), so soaked-and-armoured stays the most dangerous state
## in the game and getting out of it is an action rather than a stat.
##
## And the metal is as cold as the AIR IT HAS BEEN SITTING IN, which is
## why `garment_c` is asked for a still-air temperature rather than a
## felt one: a fire warms the man, not the harness, so the decision of
## what to wear is one you make before you are cold and cannot fix by
## standing closer to the flames.
##
## Pure static. No node, no clock, no RNG, no `get_tree`, no state.


# ===========================================================================
#  Coverage - the five slots are not worth the same
# ===========================================================================

## What fraction of the body's heat each piece stands in front of. The
## trunk is most of it and the feet are very little, which is what gives
## a part-dressed man a DRESSING ORDER: chest, then legs, then arms,
## then head, then boots. Sums to exactly 1.0, so a head-to-toe set is a
## complete garment and nothing can be more than completely covered.
const COVER := {
	"helmet": 0.14,
	"chest": 0.38,
	"arms": 0.16,
	"pants": 0.22,
	"shoes": 0.10,
}
const COVER_TOTAL := 1.0


# ===========================================================================
#  Conduction - per metal, and anchored to Materials
# ===========================================================================

## How readily each metal hands your heat to the night, as a multiple of
## plain steel. The four mundane metals are 1.0 by definition; every
## value away from 1.0 is there because `Materials.MATS` gives that
## metal an element, and `table_problems()` asserts the direction of
## every one of them against `Materials.element_name()` so the two
## tables cannot quietly disagree.
##
## A NEGATIVE value is a metal that gives heat back -- dragonsteel runs
## warm, and it runs warmest on the worst night, because the term it
## scales is the gradient.
const CONDUCT := {
	"bronze": 1.00,
	"iron": 1.00,
	"steel": 1.00,
	"silver": 1.00,
	"cold_iron": 1.70,
	"meteoric": 0.35,
	"mithril": 0.85,
	"adamant": 1.15,
	"dragonsteel": -0.30,
	"voidsteel": -0.10,
}
const CONDUCT_BARE := 1.0

## The elements that make a metal warm to wear and the ones that make it
## cold. Read out of `Materials.element_name()`, never restated here as
## a list of material ids.
const WARM_ELEMENTS: Array[String] = ["Ember", "Dragonfire", "Soulfire"]
const COLD_ELEMENTS: Array[String] = ["Frost"]


# ===========================================================================
#  The four numbers
# ===========================================================================

## Degrees a full harness is worth in still air, just for being in the
## way. Small on purpose: standing behind your own breastplate is not a
## roof (`Exposure.SHELTER_C`) and is not a fire.
const STILL_C := 1.2

## And degrees more at a full gale. STRICTLY LESS than `Exposure.WIND_C`
## takes, so that no amount of plate can ever make a gale better than
## still air -- `table_problems()` refuses the file if that stops being
## true.
const WIND_BREAK_C := 2.2

## The fraction of the air-to-body gradient that a full covering of
## plain metal hands through. Measured: at 0.17 a steel harness costs
## about a degree on a winter evening (ambient -4.6) and about two at
## four in the morning (-9.6), which is worth roughly a third of what
## the fire is worth and never replaces it.
const CONDUCT_FRACTION := 0.17

## Wet metal against skin. The harness is not what is making you wet --
## that is `Exposure.WET_CHILL_C` and it is nine degrees - but it is
## what is holding the water there.
const WET_CONDUCT_MULT := 1.6

## And it does not breathe: a full harness slows drying to this.
const DRY_MULT_FULL := 0.6

## Two metals within this many degrees of each other are the same
## choice, and `dress()` breaks the tie on protection instead.
const TIE_EPS := 0.0005


# ===========================================================================
#  What is on the body
# ===========================================================================

static func cover(worn: Dictionary) -> float:
	## 0 bare to 1 head-to-toe. Slots this file does not know about and
	## empty materials contribute nothing rather than throwing: the
	## caller is `Player.equipment`, which carries a sword in it too.
	##
	## ⚠ This used to end in `clampf(c, 0.0, COVER_TOTAL)` and the mutation
	## sweep proved the clamp could not change an answer: `worn` is a
	## dictionary, so each slot appears once, and `table_problems()` refuses
	## a COVER table whose weights do not sum to COVER_TOTAL. The clamp was
	## guarding a condition another guard already forbids, so it went rather
	## than an assertion being manufactured for it.
	var c := 0.0
	for slot in worn:
		if String(worn[slot]) == "":
			continue
		c += float(COVER.get(slot, 0.0))
	return c


static func pieces(worn: Dictionary) -> int:
	var n := 0
	for slot in worn:
		if COVER.has(slot) and String(worn[slot]) != "":
			n += 1
	return n


static func conduct(worn: Dictionary) -> float:
	## The conduction of the set, weighted by how much of the body each
	## piece is standing in front of. A MEAN, not a sum: three pieces of
	## cold iron and two of dragonsteel is a number between the two, and
	## a man in one dragonsteel boot is not warm.
	var num := 0.0
	var den := 0.0
	for slot in worn:
		var m := String(worn[slot])
		if m == "" or not COVER.has(slot):
			continue
		var w := float(COVER[slot])
		num += w * float(CONDUCT.get(m, CONDUCT_BARE))
		den += w
	if den <= 0.0:
		return 0.0
	return num / den


static func protect(worn: Dictionary) -> float:
	## The other currency, read through `Materials`' own door so that this
	## file never carries a second opinion about what a piece turns.
	var p := 0.0
	for slot in worn:
		var m := String(worn[slot])
		if m == "" or not COVER.has(slot):
			continue
		p += Materials.armor_piece_protect(m)
	return p


# ===========================================================================
#  Degrees
# ===========================================================================

static func gradient_c(still_air_c: float) -> float:
	## How much colder the air is than a body wants to be. Zero above
	## neutral, and `Exposure` owns that number -- there is no second
	## definition of "warm enough" in this file.
	return maxf(0.0, Exposure.WARMTH_NEUTRAL_C - still_air_c)


static func wind_break(worn: Dictionary, wind: float) -> float:
	## The half of a harness that is always a gift. Scales with coverage,
	## because a gale finds a gap.
	return cover(worn) * (STILL_C + WIND_BREAK_C * clampf(wind, 0.0, 1.0))


static func conduct_c(worn: Dictionary, still_air_c: float, wet: float) -> float:
	## The half that is a debt, and the only term in the file that knows
	## what the metal is. Scales with the gradient, with coverage twice
	## over (more of you against it, and more of it against you), and
	## with how wet you are.
	##
	## Can come back NEGATIVE for a warm metal, which is the point.
	var cv := cover(worn)
	if cv <= 0.0:
		return 0.0
	var loss := conduct(worn) * CONDUCT_FRACTION * gradient_c(still_air_c) * cv
	return loss * (1.0 + (WET_CONDUCT_MULT - 1.0) * clampf(wet, 0.0, 1.0))


static func garment_c(worn: Dictionary, still_air_c: float, wet: float, wind: float) -> float:
	## THE DOOR. `Exposure.felt_c` adds this and nothing else.
	##
	## `still_air_c` is the air with the wind's own chill taken back out
	## of it -- see `Exposure.still_air_c()`. Handing the windy number in
	## here would charge the harness for the very draught it is stopping.
	if worn.is_empty():
		return 0.0
	return wind_break(worn, wind) - conduct_c(worn, still_air_c, wet)


static func dry_mult(worn: Dictionary) -> float:
	## Metal does not breathe. Multiplies `Exposure`'s drying rate, so a
	## man in full plate takes two thirds again as long to dry out, and
	## the fire he is standing at is working against his own harness.
	return lerpf(1.0, DRY_MULT_FULL, cover(worn))


# ===========================================================================
#  Choosing
# ===========================================================================

static func dress(pack: Array, still_air_c: float, wet: float, wind: float) -> Dictionary:
	## The warmest set the pack can make TONIGHT, slot by slot.
	##
	## Every piece is scored on its own -- `conduct()` is a weighted mean,
	## so a slot's best metal does not depend on what is in the other
	## four -- and ties go to the tougher metal. In deep winter that
	## returns your warmest armour; in summer the gradient is zero, every
	## metal scores identically, and the tiebreak quietly hands back your
	## BEST armour instead. One function, two answers, and the season
	## decides which.
	##
	## `pack` is a list of item dictionaries as `Player.inventory` holds
	## them: anything with a `slot` this file knows and a `material`.
	var best: Dictionary = {}
	var score: Dictionary = {}
	var prot: Dictionary = {}
	for entry in pack:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var it: Dictionary = entry
		var slot := String(it.get("slot", ""))
		var m := String(it.get("material", ""))
		if m == "" or not COVER.has(slot):
			continue
		var s := garment_c({slot: m}, still_air_c, wet, wind)
		var p := Materials.armor_piece_protect(m)
		var take := false
		if not best.has(slot):
			take = true
		elif s > float(score[slot]) + TIE_EPS:
			take = true
		elif s >= float(score[slot]) - TIE_EPS and p > float(prot[slot]):
			take = true
		if take:
			best[slot] = m
			score[slot] = s
			prot[slot] = p
	return best


# ===========================================================================
#  The tables have to agree with Materials
# ===========================================================================

static func table_problems() -> Array:
	## Everything this file believes about `Materials`, asked out loud.
	## Returns a list of English complaints, empty when all is well; the
	## suite asserts it is empty, so adding a metal or renaming a slot in
	## `Materials.gd` turns this red and says which.
	return problems_in(COVER, CONDUCT, COVER_TOTAL, WIND_BREAK_C, DRY_MULT_FULL)


static func problems_in(cover_tbl: Dictionary, conduct_tbl: Dictionary,
		cover_total: float, wind_break_c: float, dry_mult_full: float) -> Array:
	## The same checks with the tables HANDED IN rather than read off this
	## file's constants.
	##
	## ⚠ This split exists because the mutation sweep found it. With the
	## checks written against the constants directly, three of them could
	## have their thresholds opened to nonsense and nothing moved: the
	## shipped tables are correct, so a guard that cannot fire at the
	## shipped values is a guard no mutation can reach. Handing the tables
	## in lets the suite feed it a table that IS wrong and demand the right
	## complaint back, which is the only form of this function that can be
	## tested at all.
	var bad: Array = []
	for slot in cover_tbl:
		if not Materials.ARMOR_SLOTS.has(slot):
			bad.append("cover weight for a slot Materials has no armour in: %s" % slot)
	for slot in Materials.ARMOR_SLOTS:
		if not cover_tbl.has(slot):
			bad.append("armour slot with no cover weight: %s" % slot)
	var tot := 0.0
	for slot in cover_tbl:
		tot += float(cover_tbl[slot])
	if absf(tot - cover_total) > 1e-6:
		bad.append("cover weights sum to %.4f, not %.4f" % [tot, cover_total])
	for id in conduct_tbl:
		if not Materials.ORDER.has(id):
			bad.append("conduction for a metal Materials does not have: %s" % id)
	for id in Materials.ORDER:
		var mid := String(id)
		if not conduct_tbl.has(mid):
			bad.append("metal with no conduction: %s" % mid)
			continue
		var el := Materials.element_name(mid)
		var c := float(conduct_tbl[mid])
		if WARM_ELEMENTS.has(el) and c >= CONDUCT_BARE:
			bad.append("%s carries %s and does not run cooler than plain metal" % [mid, el])
		if COLD_ELEMENTS.has(el) and c <= CONDUCT_BARE:
			bad.append("%s carries %s and does not run colder than plain metal" % [mid, el])
		if el == "" and absf(c - CONDUCT_BARE) > 1e-6:
			bad.append("%s has no element and is not plain metal: %.3f" % [mid, c])
	if wind_break_c >= absf(Exposure.WIND_C):
		bad.append("a harness hands back more of the gale than the gale takes")
	if dry_mult_full > 1.0:
		bad.append("a harness dries you faster than bare skin")
	return bad


# ===========================================================================
#  Readouts
# ===========================================================================

static func describe(worn: Dictionary) -> String:
	if pieces(worn) == 0:
		return "nothing"
	var tally: Dictionary = {}
	for slot in Materials.ARMOR_SLOTS:
		var m := String(worn.get(slot, ""))
		if m == "":
			continue
		tally[m] = int(tally.get(m, 0)) + 1
	var parts: PackedStringArray = []
	for m in tally:
		parts.append("%s x%d" % [Materials.display_name(String(m)), int(tally[m])])
	return ", ".join(parts)


static func verdict(worn: Dictionary, still_air_c: float, wet: float, wind: float) -> String:
	var g := garment_c(worn, still_air_c, wet, wind)
	if pieces(worn) == 0:
		return "unclothed"
	## ⚠ FOUND BY LOOKING AT IT IN THE GAME. On a summer evening a full
	## harness scores its whole windbreak and nothing else, and this line
	## called that "worth more than the fire" -- of a set that cannot move
	## the meter at all, because above `WARMTH_NEUTRAL_C` warmth comes back
	## whatever you are wearing. There is no gradient, so there is nothing
	## for a garment to be worth, and saying so is the honest answer.
	if gradient_c(still_air_c) <= 0.0:
		return "nothing to keep out"
	if g <= -2.0:
		return "killing you"
	if g < -0.25:
		return "a liability tonight"
	if g < 0.25:
		return "paying for itself"
	if g < 2.0:
		return "worth wearing"
	return "worth more than the fire"


static func readout(worn: Dictionary, still_air_c: float, wet: float, wind: float) -> String:
	## ⚠ The conduction is NEGATED and printed signed, not printed after a
	## hardcoded minus. A warm metal's conduction is negative, so the first
	## version of this line put `metal --0.8` on the screen the first time a
	## dragonsteel harness was looked at in the running game. Signed, the
	## three numbers now read as what they are: a credit, a debit, and their
	## sum.
	return "%s - %d pc, %.0f%% covered, break %+.1f, metal %+.1f, net %+.1f C (%s)" % [
		describe(worn), pieces(worn), cover(worn) * 100.0,
		wind_break(worn, wind), -conduct_c(worn, still_air_c, wet),
		garment_c(worn, still_air_c, wet, wind),
		verdict(worn, still_air_c, wet, wind)]
