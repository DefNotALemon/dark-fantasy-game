class_name Butchery
extends RefCounted

## ===========================================================================
## BUTCHERY — the caller `Carcasses.harvest_at` has been waiting for.
##
## `a23a20e` shipped a carcass economy with a hole in the middle of it. The
## file's own docstring says the loop out loud — *"butcher it, or fund the
## predators"* — and `Carcasses.harvest_at` has sat there since, fully
## modelled, fully tested, and called by nothing. `add()`'s comment even
## names the missing thing: *"a future butcher's block"*. This is it.
##
## THE ONE IDEA: **BUTCHERY IS SUBTRACTION, AND YOUR BACK IS THE ONLY LIMIT
## ON IT.** There is no loot table here. Every kilogram you put in your pack
## is a kilogram the woods do not get, and the guilds' floors — already in
## `Carcasses.GUILDS`, already with teeth — decide what that buys you.
##
## THE NUMBER THE PROBE FOUND, and it was nobody's decision:
##
##   BASE_CARRY is 90. The starting kit weighs 49.30 (worn gear counts half),
##   so a fresh character walks around with **40.70 kg of free back**. A
##   white-tailed deer, at `MASS_K` × 1.70³, is **49.13 kg**. And the coyote
##   pack's floor is 18 % — so denying a pack one deer means taking 40.30 kg.
##
##   Forty point three, against forty point seven. FOUR HUNDRED GRAMS.
##
## Three constants written in three files on three different days put the
## largest animal a man can carry away from the wolves exactly at the deer,
## and put the deer exactly on the line. So:
##
##   * a deer or a black bear (49 kg) — one full back strips it to 14.5 %,
##     which **denies the coyotes and the bear** and leaves the crows and the
##     fox their share. This is the animal the loop is about.
##   * anything at 41 kg or under — you carry the whole thing away and NOBODY
##     comes. A hare is not an economy.
##   * a moose (243.9 kg) — one back is 17 % of it. **You cannot deny a moose
##     to anything, at any skill, with any blade.** Five and a half trips, and
##     it rots faster than you can walk them. Killing a moose beside your camp
##     is baiting a bear, and there is no play that avoids it.
##
## THE SECOND TERM: **AN OPENED CARCASS SMELLS.** `Carcasses.find_gain` took
## the sky and the season and the mass and had no idea whether the animal was
## still zipped up. It does now — see `OPEN_SCENT` and the `left` argument
## added to that function. Measured on one spring deer, opening it brings the
## fox in at 3.0 h instead of 4.5 and the bear at 36.5 h instead of 58.5. So
## the first cut is the expensive one: you cannot take your share quietly.
## And because the stage is derived from `left` and not from who did the
## cutting, **the crows are the scouts of the whole system** — the guild that
## opens it accelerates every guild behind it, and nobody wrote that down.
##
## THE THIRD TERM: **A CUT IS WET WORK.** Field-dressing puts your arms
## inside a warm animal. `Exposure` has priced wet since `4ac02b1` and
## nothing but rain and swimming had ever set it. Measured at a winter dusk:
## dry, the warmth bar is 9.9 real minutes deep; bloody to the elbows after a
## whole deer (0.56 wet), it is 6.6. Autumn is the crueller one — 129 minutes
## dry against 16 wet. It sheds in 56 s in the open and 14 s by a fire, which
## is one more rung on the winter-camp ladder `4ac02b1` built.
##
## Pure static. No node, no clock, no RNG, no `get_tree`, no state — the same
## shape as `Slumber`, `Garments`, `Weatherwise` and `Factions`. `Player.gd`
## owns the interaction; this file owns every number and every sentence.
## ===========================================================================


# ================================ the cut =================================

## How much one cut moves. This is a FEEL constant and not a balance one, and
## the probe is why: at 4, 5, 6, 7 or 8 kg a cut, a deer ends at the same
## 8.43 kg because the wall is the back, not the knife. It only decides how
## many times you press.
const CUT_KG := 6.0

## Seconds between cuts. Seven of them strips a deer, so a whole deer is
## about fifteen seconds of standing still in the open with your hands busy —
## which is the point, and is what the wet and the cold are billed against.
const CUT_SECONDS := 2.2
const CUT_STAMINA := 8.0

## Wet added per cut. 0.08 puts a whole deer at 0.56 — see the header.
const CUT_WET := 0.08

## An edge holds. `Materials.MATS` has carried a `tier` on every material
## since it was written and only damage had ever read it: a tier-3 blade
## takes 36 % more off per cut than the iron sword you start with. Nothing
## about the outcome changes — the back is still the wall — you just stand
## there for four cuts instead of seven.
const EDGE_TIER_BONUS := 0.12

## Reach and gaze, matched to the firepit's (a carcass is a big thing on the
## ground and you are usually standing over it).
const REACH := 3.4
const CONE := 0.82

## What a guild's floor is worth once it is crossed, in the guild's own words.
const DENIED_LINES := {
	"corvid": "Even the crows will pass it by now",
	"fox": "Not worth a fox's night any more",
	"pack": "Stripped past what a pack would come for",
	"bear": "No bear will walk this far for what is left",
}


# ============================== the parts =================================
#
# `CritterDex`'s `harv` row has been in the dex since the dex was written and
# has NEVER been read by anything — a vocabulary with no consumer, the exact
# shape `Crofts.ALARM_TAGS` was on the other side (2026-09-12). This is its
# first reader. The ordinal is a COUNT, and you receive them as you work:
# after taking the fraction f of the animal you are owed ceil(ordinal × f) of
# each part, so the hide comes off on the first cut and the porcupine's
# twelfth quill only if you strip the porcupine.

const PART_KG := {
	"hide": 4.0, "pelt": 1.2, "antler": 1.5, "sinew": 0.1, "fat": 0.6,
	"claw": 0.05, "feather": 0.02, "quill": 0.005, "castor": 0.25,
	"shell": 1.8, "relic": 0.5, "fish": 0.8,
}
const PART_KG_DEFAULT := 0.2

const PART_NAMES := {
	"hide": "Hide", "pelt": "Pelt", "antler": "Antler", "sinew": "Sinew",
	"fat": "Fat", "claw": "Claw", "feather": "Feather", "quill": "Quill",
	"castor": "Castor", "shell": "Shell", "relic": "Relic", "fish": "Fillet",
}

## English has a word for exactly one of the sixty-five, and it is worth
## having. Everything else is named off the dex's own `nm` by its last word —
## "Eastern Coyote" is coyote meat, "Snowshoe Hare" is hare meat — which is a
## rule rather than a table, and so cannot go stale when the dex grows.
const MEAT_OVERRIDE := {"whitetail": "Venison"}




# =============================== the edge =================================


static func edge_tier(mat_id: String) -> int:
	## The blade's tier out of `Materials`, or -1 for something that is not a
	## material at all.
	##
	## ⚠ It reads `Materials.MATS` DIRECTLY and not through
	## `Materials.get_mat`, which falls back to iron for an unknown id. Going
	## through the front door made `edge_tier("")` and `edge_tier("nonsense")`
	## both answer 0, so the "you need an edge" gate could never refuse
	## anything and a pickaxe would have field-dressed a moose. A fallback can
	## hide the thing you built; here it hid the guard.
	## (`mat_id == ""` was here as well and the sweep killed it as a
	## redundancy: `MATS.has("")` is already false, and two guards on one path
	## is a guard that cannot be tested.)
	if not Materials.MATS.has(mat_id):
		return -1
	return int((Materials.MATS[mat_id] as Dictionary).get("tier", 0))


static func cut_kg(mat_id: String) -> float:
	## Kilograms one cut takes off, before the carcass and the back have their
	## say. Iron (tier 0) is the baseline you start the game with.
	var t := edge_tier(mat_id)
	if t < 0:
		return 0.0
	return CUT_KG * (1.0 + EDGE_TIER_BONUS * float(t))


static func take_for(left: float, want: float, carried: float, limit: float) -> float:
	## THE WALL, and the one rule that softens it: **you may always finish a
	## cut you were light enough to start.** So the last cut is the one that
	## puts you over the limit, the overburden warning appears at exactly the
	## moment you take the deer's last piece, and a player is never told "no"
	## in the middle of an animal — only at the start of the next one.
	##
	## It answers in WHOLE kilograms so the pack and the ledger cannot drift
	## apart by a rounding error -- except on the very last scrap, where whole
	## kilograms would have erased three animals outright: a woodchuck is 0.97
	## kg, `floorf` of that is zero, and the first draft handed the player
	## nought cuts and left the whole carcass standing at 100 %. The remainder
	## under a kilogram therefore comes off exactly, and `meat_count` rounds
	## it up, which is the only place the two numbers can disagree and is
	## bounded by `Carcasses.MIN_MASS` at under half a kilo per carcass.
	if want <= 0.0 or left <= 0.0:
		return 0.0
	if carried >= limit:
		return 0.0
	var t := minf(want, left)
	var whole := floorf(t)
	return whole if whole >= 1.0 else t


static func meat_count(got: float) -> int:
	## Kilograms in the pack for kilograms off the ledger. Never zero for a
	## cut that actually took something, or the last scrap of a small animal
	## would vanish between the two.
	if got <= 0.0:
		return 0
	return maxi(1, int(roundf(got)))


# ============================== the yield =================================


static func meat_name(species: String, nm: String) -> String:
	if MEAT_OVERRIDE.has(species):
		return String(MEAT_OVERRIDE[species])
	## No article to strip: the rule is the LAST word, so "The Specter Moose"
	## and "Specter Moose" both answer "Moose Meat" and a `begins_with("The ")`
	## branch here was dead code the sweep found for us.
	var parts := nm.strip_edges().split(" ", false)
	if parts.is_empty():
		return "Meat"
	return "%s Meat" % String(parts[parts.size() - 1])


static func part_name(part: String, nm: String) -> String:
	var words := nm.strip_edges().split(" ", false)
	var animal := String(words[words.size() - 1]) if not words.is_empty() else "Beast"
	return "%s %s" % [animal, String(PART_NAMES.get(part, part.capitalize()))]


static func part_weight(part: String) -> float:
	return float(PART_KG.get(part, PART_KG_DEFAULT))


static func parts_owed(harv: Dictionary, mass: float, taken: float) -> Dictionary:
	## Cumulative count of each non-meat part owed at this much taken. The
	## meat is the kilograms and is not in here — it would be counted twice.
	var out: Dictionary = {}
	if mass <= 0.0 or taken <= 0.0:
		return out
	var f := clampf(taken / mass, 0.0, 1.0)
	for k in harv.keys():
		var key := String(k)
		if key == "meat":
			continue
		var ord_n := int(harv[k])
		if ord_n <= 0:
			continue
		## (A `mini(owed, ord_n)` cap stood here and the sweep killed it: with
		## `f` clamped it can never bind, and it was masking the clamp's own
		## mutation. One guard, on the term that expresses the rule.)
		out[key] = int(ceilf(float(ord_n) * f))
	return out


static func parts_due(harv: Dictionary, mass: float, before: float, after: float) -> Dictionary:
	## What THIS cut hands over: the difference between two cumulative counts,
	## so nothing is ever handed over twice and nothing is skipped by a big cut.
	var a := parts_owed(harv, mass, before)
	var b := parts_owed(harv, mass, after)
	var out: Dictionary = {}
	for k in b.keys():
		var d := int(b[k]) - int(a.get(k, 0))
		if d > 0:
			out[k] = d
	return out


# ============================= the verdict ================================


static func butcherable(harv: Dictionary) -> bool:
	## SIXTEEN OF THE DEX'S ROWS HAVE NO MEAT IN THEM, and the first draft of
	## this file let you butcher them anyway. Measured over the whole roster:
	## a Great Blue Heron is 7.29 kg on the ledger and its whole `harv` row is
	## three feathers, so three cuts took seven kilograms off the carcass, put
	## sixty grams in the pack, and DENIED THE CROWS A HERON FOR NOTHING. The
	## Whale was worse -- an empty row, 1 200 kg destroyed over a 200-cut loop
	## that could never fill a back because nothing was ever carried.
	##
	## A carcass is not a bin. If there is no meat on the row there is nothing
	## here a knife is for -- the feathers come off a pluck, which this is not.
	return int(harv.get("meat", 0)) > 0


static func denied(mass: float, left: float) -> Array:
	## Which guilds will no longer come, by `Carcasses`' own floors. Read off
	## the shipped table so there is not a second copy of the economy here.
	var out: Array = []
	if mass <= 0.0:
		return out
	var f := left / mass
	for g in Carcasses.GUILDS.size():
		if f <= float((Carcasses.GUILDS[g] as Dictionary)["floor"]):
			out.append(String((Carcasses.GUILDS[g] as Dictionary)["id"]))
	return out


static func crossed(mass: float, before: float, after: float) -> Array:
	## The guilds this one cut just shut out — the difference of two `denied`
	## calls, which is what earns a line on the message log.
	var was := denied(mass, before)
	var now := denied(mass, after)
	var out: Array = []
	for id in now:
		if not was.has(id):
			out.append(id)
	return out


static func denied_line(guild_id: String) -> String:
	return String(DENIED_LINES.get(guild_id, ""))


static func appetite(mass: float, left: float) -> String:
	## What is still on it, said as who would come for it: the biggest guild
	## whose floor the remainder still clears. This is the sentence that makes
	## the economy legible without a single number.
	if mass <= 0.0 or left <= 0.0:
		return "nothing left"
	var f := left / mass
	var best := -1
	for g in Carcasses.GUILDS.size():
		if f > float((Carcasses.GUILDS[g] as Dictionary)["floor"]):
			best = g
	if best < 0:
		return "nothing worth a crow"
	return "still enough for %s" % String((Carcasses.GUILDS[best] as Dictionary)["nm"])


static func prompt_for(rec: Dictionary, harv: Dictionary, edge: String,
		carried: float, limit: float) -> String:
	## The whole interaction's front door, in one string, so the suite can
	## hold every branch of it without a viewport.
	if rec.is_empty():
		return ""
	var mass := float(rec.get("mass", 0.0))
	var left := float(rec.get("left", 0.0))
	var nm := String(rec.get("nm", "it"))
	if Carcasses.stage_of(rec) >= Carcasses.STAGE_BONES:
		return "Bones. There is nothing on it to take"
	if not butcherable(harv):
		return "There is nothing on a %s a knife is for" % nm.to_lower()
	if edge == "":
		return "Nothing on you will open it -- it wants an edge"
	if carried >= limit:
		return "Your back is full -- %.0f / %.0f" % [carried, limit]
	return "[E]  Butcher the %s   ·   %.0f kg on it   ·   %s" \
		% [nm.to_lower(), left, appetite(mass, left)]
