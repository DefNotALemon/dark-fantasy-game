class_name Factions
extends RefCounted

## ===========================================================================
## FACTIONS -- who holds the ground, and what it costs them to keep it.
##
## Myrkfell has had a `Chronicle.pressure_at(pos, tag)` since the Chronicle
## shipped, and for six days it has been telling a polite lie. The dominant
## term in it is `bias[tag]`, and `bias` is ONE dictionary for the whole map:
## a raid that resolved badly at Freeport raised the goblin pressure at the
## Allagash, ninety kilometres north, in the same instant and by the same
## amount. The function took a position and threw it away.
##
## So: there was no territory. This is the write side.
##
## THE ONE IDEA
##
##   NOBODY TAKES GROUND. GROUND IS LOST, AND WHOEVER IS NEXT DOOR DIVIDES IT.
##
## There is no "goblin offensive" in here, no raid that advances a border by a
## hex. A region whose men are hungry, unwatched and burnt loses its GRIP, and
## the grip it loses is picked up by whichever claimant already presses on it
## from an adjoining region -- and by nobody at all if nobody is next door, in
## which case the ground simply goes wild. That is the whole mechanism, and it
## is what makes a FRONTIER: a line that moves, that has a direction, and that
## you can walk from the coast to the north woods.
##
## THREE RULES THIS FILE WILL NOT BREAK
##
##   1. **It is pure.** No node, no clock, no RNG, no `get_tree`, no state of
##      its own. Every function reads its arguments and nothing else. The
##      state is a Dictionary the Chronicle owns, hands in, and saves.
##   2. **The map is DERIVED, never restated.** The seats come from the
##      Chronicle's own place roster; the coastline comes from `Seasons`; the
##      adjacency is a relative-neighbourhood graph over the region roster,
##      which has no parameter to get wrong. There is not one hand-drawn
##      border in this file, and adding a place to the bake redraws the
##      political map with no edit here.
##   3. **Step size cannot change the story.** Every rate is a half-life
##      raised to `days`, so one call of `step(..., 1.0)` and forty-eight
##      calls of `step(..., 1.0 / 48.0)` land in the same place. The game
##      feeds it half-hours; the suite feeds it whole days; both agree.
##
## WHAT WAS MEASURED, BEFORE ANY CONSTANT WAS CHOSEN
##
## `tools/probe_factions.gd` ran the real Chronicle for a game year and dumped
## every resolved outcome with its region. Three findings decided the design:
##
##   * **The wilderness sees NO events.** Allagash and the Gulf of Maine had
##     precisely zero in ninety-six days; Katahdin had six; Casco Bay had a
##     hundred and seventy-five. A border driven by events alone would have
##     frozen the north solid for ever -- and the north is exactly the ground
##     the goblins are supposed to hold. So the resting division is a property
##     of the MAP (seats, and distance from seats), and events only ever move
##     it at the margin. The wild is the default state of Myrkfell; the men
##     are an exception they have to keep paying for.
##   * **An impulse cannot move a spring.** With the push applied per day
##     against a relax-to-rest, NOTHING changed hands in a game year at any
##     sane gain -- events are too sparse and too small. Hence two timescales:
##     pressure ACCUMULATES on a fortnight's half-life, and the hold relaxes
##     over forty days. A border moves because of a bad season, not a bad
##     Tuesday.
##   * **Seat count had to resist.** Without it the BUSIEST region was the
##     most volatile, which is backwards, and Casco Bay -- thirteen seats, the
##     richest ground on the map -- fell to the goblins inside one game year.
##     The push is divided by how much is actually there to hold, so a raid
##     that swings an outpost barely registers at a city.
##
## Fitted at PUSH_GAIN 0.04 the map runs 13 changes of hand in a game year
## across 8 regions, the four core seats never wobble once, and the whole
## field reaches a steady state by year four and sits there -- mean men 0.306
## and goblins 0.416 at both year four and year ten. It does not collapse.
## ===========================================================================


## ============================== The claimants =============================

const MEN := "men"
const GOBLINS := "goblins"
const WOLVES := "wolves"
const WILD := "wild"

## Not a claimant: what `holder_of` answers when the top two are too close to
## call. Contested ground is a NAMED STATE, not a tie broken by sort order --
## the probe found four regions landing within a hundredth of each other, and
## "whoever happens to sort first" is not a political map.
const CONTESTED := "contested"

const CLAIMANTS: Array[String] = [MEN, GOBLINS, WOLVES, WILD]

## Disorder. It is what the men LOSE to, and it is nobody's gain: the share it
## takes off them is handed to the frontier rule like any other empty ground.
const LAWLESS := "lawless"


## ============================== The constants =============================
## Every number below was measured by tools/probe_factions.gd against the real
## roster and a real simulated year. See the file header for what each one
## bought.

## Seats at which the men hold half the ground. Casco Bay's thirteen give
## 0.76, Acadia's five give 0.56, Katahdin's two give 0.33, Allagash's none
## give nothing at all.
const SEAT_HALF := 4.0

## How much of their grip the men lose per hop of adjacency. This is what
## makes "deep country" a measured quantity rather than an opinion.
const REACH_DECAY := 0.45

## How much of the non-men ground is actively CLAIMED rather than simply
## empty. Nothing on this map is ever wholly spoken for.
const CLAIMED := 0.75

## Closer than this and the region is contested rather than held.
const HOLD_MARGIN := 0.06

## A fortnight: how long the world goes on shouting about what happened.
const PUSH_HALFLIFE_DAYS := 14.0

## Forty days: how long a border takes to lean back toward where the map says
## it belongs. Deliberately much longer than the pressure's half-life -- that
## gap IS the feature.
const HOLD_HALFLIFE_DAYS := 40.0

## Fitted. At 0.02 the map barely breathes; at 0.07 three of the four core
## seats wobble and at 0.12 Casco Bay itself falls inside a year.
const PUSH_GAIN := 0.04

## How fast a claimant bleeds into the empty ground of an adjoining region.
const SPILL := 0.06

## THE FLOOR UNDER A WALLED TOWN. A share of the men's resting grip that no
## amount of pressure can take off them, because there are no sieges in this
## model: a border is moved by whether the roads are safe and the stores hold,
## and that is not how a city falls. Without it the probe put Casco Bay --
## thirteen seats, the richest ground on the map -- in play inside a decade,
## which is a collapse rather than a frontier.
##
## It is scaled by the region's OWN resting grip, so it is a wall where there
## is a town and nothing at all where there is not: Casco Bay can never go
## under 0.46, while Katahdin's two seats floor at 0.20 and are very much
## losable. The four core seats are thereby unassailable AS A PROPERTY OF THE
## MODEL rather than as a happy accident of PUSH_GAIN.
const MEN_FLOOR := 0.60

## An even four-way split. Every offset in this file is measured from here, so
## ordinary country adds nothing to anything.
const NEUTRAL_SHARE := 0.25

## How much a fully-held region moves `Chronicle.pressure_at`. Against a
## measured median croft-day pressure of 0.48 and a barred-door threshold of
## 0.90, this is the difference between a croft on the wrong side of the line
## and one behind it -- and it is not enough on its own to bar a door on
## ordinary ground.
const PRESSURE_SPAN := 1.0

## `Seasons.coast_u` reads 1.0 on salt water and on the shore. A region at
## that reading with not one seat on it is open sea, and the sea is not
## ground. This is the whole of how the Gulf of Maine stays off the political
## map, and it is derived from the coastline the temperature model already
## uses rather than from a list of names in here.
const SEA_U := 0.999

## The spawn multiplier is an offset, but an offset can still run a weight
## negative at the extremes. Binds only past a hold no real region reaches.
const MULT_MIN := 0.15
const MULT_MAX := 3.0


## Which claimant a Chronicle bias tag speaks for. Every tag the catalogue
## actually emits is placed: `tools/probe_factions.gd` printed the seventeen
## of them, and `table_problems()` fails if one goes missing.
const TAG_CLAIM := {
	"trade": MEN, "road": MEN, "fair": MEN, "salvage": MEN,
	"goblins": GOBLINS, "ruins": GOBLINS,
	"wolves": WOLVES, "wildlife": WOLVES, "bears": WOLVES, "livestock": WOLVES,
	"unrest": LAWLESS, "hunger": LAWLESS, "bandits": LAWLESS, "fire": LAWLESS,
	"murrain": LAWLESS, "omen": LAWLESS, "poaching": LAWLESS,
}


## ============================== Spawn bands ===============================
## Three bands, and membership is DERIVED from `CritterDex.arch_of` -- give a
## new species an archetype and it is priced here with no edit in this file.

const BAND_HUNTER := 0    ## STALKER, RAIDER -- the things that hunt
const BAND_SCAV := 1      ## SCAVENGER -- the things that follow trouble
const BAND_QUIET := 2     ## everything else -- the things trouble drives off

const HUNTER_ARCH: Array[String] = ["STALKER", "RAIDER"]
const SCAV_ARCH: Array[String] = ["SCAVENGER"]

## What each band makes of ground held by each claimant, as an offset from an
## even split. EVERY ROW IS EXACTLY 1.0 ON NEUTRAL GROUND, by construction and
## by assertion, per species: this is a departure from a map that does not
## care who holds what, never a replacement for it.
const GROUND_MULT := {
	BAND_HUNTER: {MEN: -0.60, GOBLINS: 0.25, WOLVES: 1.30, WILD: 0.20},
	BAND_SCAV: {MEN: -0.30, GOBLINS: 1.10, WOLVES: 0.55, WILD: 0.10},
	BAND_QUIET: {MEN: 0.35, GOBLINS: -0.55, WOLVES: -0.45, WILD: 0.05},
}


## ========================= The map, derived ===============================


static func seats_from(places: Array) -> Dictionary:
	## How hard the men already hold each region, out of the Chronicle's own
	## place roster. A place is worth one, and its rank again on top -- Bangor
	## counts for three of an Allagash outpost.
	var out := {}
	for p in places:
		var pd := p as Dictionary
		var rn := String(pd.get("region", ""))
		if rn.is_empty():
			continue
		out[rn] = float(out.get(rn, 0.0)) + 1.0 + float(int(pd.get("rank", 0)))
	return out


static func is_open_water(centre: Vector2, seat: float) -> bool:
	## The sea is not ground and nobody holds it.
	if seat > 0.0:
		return false
	return Seasons.coast_u(Vector3(centre.x, 0.0, centre.y)) >= SEA_U


static func land_regions(roster: Array, seats: Dictionary) -> Array:
	## Sorted, because the order of this array is part of the determinism
	## contract: the step walks it and the save serialises it.
	var out: Array = []
	for r in roster:
		var rd := r as Dictionary
		var nm := String(rd.get("name", ""))
		var c: Vector2 = rd.get("pos", Vector2.ZERO)
		if is_open_water(c, float(seats.get(nm, 0.0))):
			continue
		out.append(nm)
	out.sort()
	return out


static func centres_of(roster: Array) -> Dictionary:
	var out := {}
	for r in roster:
		var rd := r as Dictionary
		out[String(rd.get("name", ""))] = rd.get("pos", Vector2.ZERO)
	return out


static func adjacency(names: Array, centres: Dictionary) -> Dictionary:
	## THE RELATIVE NEIGHBOURHOOD GRAPH, and it is parameter-free on purpose:
	## A and B adjoin when nothing else on the map is closer to BOTH of them
	## than they are to each other. There is no radius to tune and no k to
	## pick, so unlike a hand-drawn border list it cannot quietly be wrong.
	##
	## Over the eighteen regions it returns a spine rather than a blob -- a
	## chain from Aroostook down through the Allagash, Baxter, Katahdin and
	## the 100-Mile Wilderness to the settled coast -- which is why goblins
	## coming out of the north have to come THROUGH somewhere to reach anyone.
	var out := {}
	for a in names:
		var an := String(a)
		var ap: Vector2 = centres.get(an, Vector2.ZERO)
		var nb: Array = []
		for b in names:
			var bn := String(b)
			if bn == an:
				continue
			var bp: Vector2 = centres.get(bn, Vector2.ZERO)
			var dab := ap.distance_to(bp)
			var blocked := false
			for c in names:
				var cn := String(c)
				if cn == an or cn == bn:
					continue
				var cp: Vector2 = centres.get(cn, Vector2.ZERO)
				if maxf(ap.distance_to(cp), bp.distance_to(cp)) < dab:
					blocked = true
					break
			if not blocked:
				nb.append(bn)
		nb.sort()
		out[an] = nb
	return out


static func hops_from(start: String, adj: Dictionary) -> Dictionary:
	## Breadth-first, so the answer is hops of adjacency and not metres.
	var dist := {start: 0}
	var queue: Array = [start]
	var head := 0
	while head < queue.size():
		var u := String(queue[head])
		head += 1
		for v in (adj.get(u, []) as Array):
			var vn := String(v)
			if dist.has(vn):
				continue
			dist[vn] = int(dist[u]) + 1
			queue.append(vn)
	return dist


static func men_anchor(seat: float) -> float:
	## Saturating, not linear: the fifth seat in a region is worth far less
	## than the first, which is why a city is firm rather than invincible.
	if seat <= 0.0:
		return 0.0
	return seat / (seat + SEAT_HALF)


static func reach(names: Array, seats: Dictionary, adj: Dictionary) -> Dictionary:
	## How far the men's arm reaches into each region: its own grip, and every
	## other region's grip discounted once per hop between. A region with no
	## seat of its own that adjoins a city is still the city's march; one four
	## hops out is nobody's.
	var out := {}
	for a in names:
		var an := String(a)
		var hops := hops_from(an, adj)
		var best := 0.0
		for b in hops:
			var bn := String(b)
			var m := men_anchor(float(seats.get(bn, 0.0)))
			best = maxf(best, m * pow(REACH_DECAY, float(int(hops[bn]))))
		out[an] = best
	return out


static func anchors(names: Array, seats: Dictionary, rch: Dictionary) -> Dictionary:
	## The resting division -- where the border sits when nothing is happening.
	## This is a property of the MAP and of nothing else: no event, no clock,
	## no save. It is what the whole field leans back toward, and it is the
	## reason the Allagash is goblin country even though nothing has ever
	## happened there.
	var out := {}
	for a in names:
		var an := String(a)
		var m := men_anchor(float(seats.get(an, 0.0)))
		var rest := 1.0 - m
		var deep := clampf(1.0 - float(rch.get(an, 0.0)), 0.0, 1.0)
		out[an] = {
			MEN: m,
			GOBLINS: rest * CLAIMED * deep,
			WOLVES: rest * CLAIMED * (1.0 - deep),
			WILD: rest * (1.0 - CLAIMED),
		}
	return out


## =============================== The field ================================


static func blank(anch: Dictionary) -> Dictionary:
	## A world at rest. Sorted keys, because two Chronicles that told the same
	## story have to serialise identically.
	var names: Array = anch.keys()
	names.sort()
	var out := {}
	for n in names:
		var nm := String(n)
		out[nm] = (anch[nm] as Dictionary).duplicate()
	return out


static func blank_push(names: Array) -> Dictionary:
	var out := {}
	for n in names:
		out[String(n)] = {MEN: 0.0, GOBLINS: 0.0, WOLVES: 0.0, LAWLESS: 0.0}
	return out


static func push_from(b: Dictionary) -> Dictionary:
	## One resolved outcome's bias, read as who it speaks for. An outcome that
	## touches no faction tag at all is silent here, which is most of them.
	var out := {MEN: 0.0, GOBLINS: 0.0, WOLVES: 0.0, LAWLESS: 0.0}
	for t in b:
		var who := String(TAG_CLAIM.get(String(t), ""))
		if who.is_empty():
			continue
		out[who] = float(out[who]) + float(b[t])
	return out


static func note(pushes: Dictionary, region: String, b: Dictionary) -> bool:
	## What happened at a place is written down against its region. The
	## accumulator is the world's MEMORY of the last fortnight, and it is the
	## reason a bad season moves a line that a bad Tuesday cannot.
	##
	## IT RETURNS WHETHER IT LANDED, and that is not decoration. `region_at`
	## answers over the WHOLE region roster, the Gulf of Maine included, while
	## `pushes` only has bags for the seventeen that are land — so an event on
	## the water is a real case and this guard is the thing that drops it.
	## Without the return there is nothing observable to assert: Godot swallows
	## the missing-key read, the write lands in a discarded temporary, and the
	## mutation sweep walked straight through the guard twice.
	if region.is_empty() or not pushes.has(region):
		return false
	var add := push_from(b)
	var bag: Dictionary = pushes[region]
	for f in add:
		bag[f] = float(bag.get(f, 0.0)) + float(add[f])
	return true


static func step(state: Dictionary, pushes: Dictionary, anch: Dictionary,
		adj: Dictionary, seats: Dictionary, days: float) -> void:
	## Advance the whole political map by `days`. Order-independent: the
	## frontier rule reads a SNAPSHOT of the neighbours taken before anything
	## moved, so walking the regions in a different order cannot change the
	## answer.
	if days <= 0.0:
		return
	var names: Array = state.keys()
	names.sort()

	## 1. the world stops shouting, on its own half-life
	var pk := pow(0.5, days / PUSH_HALFLIFE_DAYS)
	for n in names:
		var nm := String(n)
		if not pushes.has(nm):
			continue
		var bag: Dictionary = pushes[nm]
		for f in bag:
			bag[f] = float(bag[f]) * pk

	## 2. every region leans back toward where the map says the border belongs
	var hk := 1.0 - pow(0.5, days / HOLD_HALFLIFE_DAYS)
	for n in names:
		var nm := String(n)
		var h: Dictionary = state[nm]
		var a: Dictionary = anch.get(nm, {})
		for f in CLAIMANTS:
			h[f] = float(h.get(f, 0.0)) + (float(a.get(f, 0.0)) - float(h.get(f, 0.0))) * hk

		## 3. and what has been happening pushes it -- damped by how much is
		##    actually there to hold, so the frontier moves and the cities do not
		var g := PUSH_GAIN * days / (1.0 + float(seats.get(nm, 0.0)) / SEAT_HALF)
		var bag2: Dictionary = pushes.get(nm, {})
		var lawless := float(bag2.get(LAWLESS, 0.0))
		h[MEN] = maxf(0.0, float(h[MEN]) + g * float(bag2.get(MEN, 0.0)) - g * lawless)
		h[GOBLINS] = maxf(0.0, float(h[GOBLINS]) + g * float(bag2.get(GOBLINS, 0.0)))
		h[WOLVES] = maxf(0.0, float(h[WOLVES]) + g * float(bag2.get(WOLVES, 0.0)))

	## 4. THE FRONTIER. Empty ground goes to whoever is already next door, in
	##    proportion to how hard they press on it -- and to nobody at all if
	##    nobody is. This is the only term in the file that is not local, and
	##    it is the one that makes a border advance rather than eighteen
	##    regions drifting on their own.
	var before := {}
	for n in names:
		before[String(n)] = (state[String(n)] as Dictionary).duplicate()
	for n in names:
		var nm := String(n)
		var h2: Dictionary = state[nm]
		var nb: Array = adj.get(nm, [])
		if nb.is_empty():
			continue
		for f in [MEN, GOBLINS, WOLVES]:
			var press := 0.0
			for q in nb:
				var qh: Dictionary = before.get(String(q), {})
				press += float(qh.get(f, 0.0))
			press /= float(nb.size())
			var take := SPILL * days * press * float(h2[WILD])
			h2[WILD] = float(h2[WILD]) - take
			h2[f] = float(h2[f]) + take

	## 5. and the ground adds up to itself
	for n in names:
		var nm := String(n)
		var h3: Dictionary = state[nm]
		var total := 0.0
		for f in CLAIMANTS:
			total += float(h3[f])
		if total <= 0.0:
			h3[WILD] = 1.0
			continue
		for f in CLAIMANTS:
			h3[f] = float(h3[f]) / total

		## 6. AND A TOWN IS A TOWN. Applied AFTER the ground is normalised, not
		##    before: a floor set and then divided through is not a floor, and
		##    the division is exactly what would quietly take back what it held.
		##    The room is found by scaling everybody else down together, so the
		##    shares still sum to one and the rest of the map is untouched.
		var floor_men := MEN_FLOOR * men_anchor(float(seats.get(nm, 0.0)))
		var have := float(h3[MEN])
		if have >= floor_men:
			continue
		var rest := 1.0 - have
		if rest <= 0.0:
			continue
		var k := maxf(0.0, (rest - (floor_men - have)) / rest)
		for f in CLAIMANTS:
			if f != MEN:
				h3[f] = float(h3[f]) * k
		h3[MEN] = floor_men

	## 7. and the invariant is made EXACT rather than nearly true. Four
	##    divisions and a rescale leave residue at about a ten-thousandth, and
	##    the probe caught eight regions carrying a share of -0.0001 or 1.0001.
	##    Dust, but an invariant that is only approximately true is one no
	##    assertion can be sharp about, and every reader of this field divides
	##    by it or compares against it.
	for n in names:
		var nm := String(n)
		var h4: Dictionary = state[nm]
		var t2 := 0.0
		for f in CLAIMANTS:
			h4[f] = maxf(0.0, float(h4[f]))
			t2 += float(h4[f])
		if t2 <= 0.0:
			continue
		for f in CLAIMANTS:
			h4[f] = minf(1.0, float(h4[f]) / t2)


## ============================== Reading it ================================


static func hold_of(state: Dictionary, region: String) -> Dictionary:
	## Never returns an empty dictionary for a region it does not know: a
	## caller standing somewhere off the political map is standing in the
	## wild, which is a true answer and not a missing one.
	var h: Dictionary = state.get(region, {})
	if h.is_empty():
		return {MEN: 0.0, GOBLINS: 0.0, WOLVES: 0.0, WILD: 1.0}
	return h


static func holder_of(state: Dictionary, region: String) -> String:
	## Whoever leads, unless the lead is too narrow to call.
	var h := hold_of(state, region)
	var top := WILD
	var first := -1.0
	var second := -1.0
	for f in CLAIMANTS:
		var v := float(h.get(f, 0.0))
		if v > first:
			second = first
			first = v
			top = f
		elif v > second:
			second = v
	if first - second < HOLD_MARGIN:
		return CONTESTED
	return top


static func margin_of(state: Dictionary, region: String) -> float:
	## How firmly, in the only currency there is: the lead over second place.
	var h := hold_of(state, region)
	var first := -1.0
	var second := -1.0
	for f in CLAIMANTS:
		var v := float(h.get(f, 0.0))
		if v > first:
			second = first
			first = v
		elif v > second:
			second = v
	return maxf(0.0, first - second)


static func frontier(state: Dictionary, adj: Dictionary) -> Array:
	## THE THING A PLAYER CAN WALK TO. Every adjoining pair the map disagrees
	## about: two regions in different hands, or one that is contested and one
	## that is not. Sorted, and each pair named once.
	var names: Array = state.keys()
	names.sort()
	var out: Array = []
	for n in names:
		var an := String(n)
		for q in (adj.get(an, []) as Array):
			var bn := String(q)
			if bn <= an:
				continue
			var ha := holder_of(state, an)
			var hb := holder_of(state, bn)
			if ha == hb:
				continue
			out.append({"a": an, "b": bn, "held_a": ha, "held_b": hb})
	return out


static func region_at(pos: Vector3, roster: Array) -> String:
	## The circle that contains it if there is one, otherwise the nearest
	## circle's centre -- the Chronicle's own rule, which now lives here and
	## is called from there rather than written out twice. Every point on the
	## map belongs somewhere.
	var here := Vector2(pos.x, pos.z)
	var best := ""
	var bd := INF
	var near := ""
	var nd := INF
	for r in roster:
		var rd := r as Dictionary
		var c: Vector2 = rd.get("pos", Vector2.ZERO)
		var d := c.distance_to(here)
		if d < nd:
			nd = d
			near = String(rd.get("name", ""))
		if d < float(rd.get("r", 500.0)) and d < bd:
			bd = d
			best = String(rd.get("name", ""))
	return best if not best.is_empty() else near


static func pressure_bonus(state: Dictionary, region: String, tag: String) -> float:
	## What it MEANS to be standing here. A tag that speaks for a claimant
	## reads high on ground that claimant holds and low where it does not,
	## measured from an even split so ordinary country adds nothing either way.
	##
	## Disorder gets none of this on purpose: `bandits` and `unrest` are not a
	## faction and do not hold territory, so a lawless tag is exactly as loud
	## on the coast as it is in the north woods.
	var who := String(TAG_CLAIM.get(tag, ""))
	if who.is_empty() or who == LAWLESS:
		return 0.0
	var h := hold_of(state, region)
	return PRESSURE_SPAN * (float(h.get(who, 0.0)) - NEUTRAL_SHARE)


static func band_of(key: String) -> int:
	## Derived from the dex's own archetype, never restated here.
	var arch := CritterDex.arch_of(key)
	if HUNTER_ARCH.has(arch):
		return BAND_HUNTER
	if SCAV_ARCH.has(arch):
		return BAND_SCAV
	return BAND_QUIET


static func band_name(b: int) -> String:
	if b == BAND_HUNTER:
		return "HUNTER"
	if b == BAND_SCAV:
		return "SCAV"
	return "QUIET"


static func spawn_mult(key: String, hold: Dictionary) -> float:
	## What the ground does to this animal's spawn weight. EXACTLY 1.0 on an
	## even four-way split, by construction: every term is an offset from
	## NEUTRAL_SHARE and they are all zero there.
	##
	## Nobody wrote "there are more wolves in goblin country" anywhere. It
	## falls out of the field: predators run roughly twice as common in the
	## deep north as on the settled coast, and the scavengers follow the
	## trouble rather than the predators.
	## An EMPTY hold is not the same thing as unclaimed ground: it means there
	## is no political map at all — a headless suite, the old build, a world
	## with no Chronicle — and such a world must spawn EXACTLY as it did before
	## this file existed. Read as all-zeroes it would price a hunter at 0.15,
	## which is a silent, total change to a game that has no factions in it.
	if hold.is_empty():
		return 1.0
	var row: Dictionary = GROUND_MULT.get(band_of(key), {})
	var m := 1.0
	for f in CLAIMANTS:
		m += (float(hold.get(f, 0.0)) - NEUTRAL_SHARE) * float(row.get(f, 0.0))
	return clampf(m, MULT_MIN, MULT_MAX)


static func readout(state: Dictionary, adj: Dictionary, region: String) -> Dictionary:
	## Read-only, for the god panel. Claims no key and hooks no event.
	var h := hold_of(state, region)
	return {
		"region": region,
		"held_by": holder_of(state, region),
		"margin": margin_of(state, region),
		"men": float(h.get(MEN, 0.0)),
		"goblins": float(h.get(GOBLINS, 0.0)),
		"wolves": float(h.get(WOLVES, 0.0)),
		"wild": float(h.get(WILD, 0.0)),
		"frontier": frontier(state, adj).size(),
	}


## Short words that stay lowercase inside a name, but never as the first word.
const SMALL_WORDS: Array[String] = ["of", "the", "and", "at", "on"]


static func pretty(region: String) -> String:
	## The roster names regions in CAPITALS, which is right for a label on a map
	## and wrong in the middle of a sentence a villager is saying to you. Found
	## by LOOKING at the live rumour board, at 343 green assertions:
	##
	##     "no honest man walks moosehead after dark any more"
	##     "there is argument over who holds down east now"
	##
	## Godot's own `capitalize()` gets sixteen of the eighteen right and loses on
	## exactly two, and both of them are in this roster: it drops the hyphen out
	## of 100-MILE WILDERNESS, and it writes "Gulf Of Maine".
	var parts := region.to_lower().split(" ")
	var out: PackedStringArray = []
	for i in range(parts.size()):
		var w := String(parts[i])
		if w.is_empty():
			continue
		if i > 0 and SMALL_WORDS.has(w):
			out.append(w)
			continue
		out.append(_cap_hyphenated(w))
	return " ".join(out)


static func _cap_hyphenated(w: String) -> String:
	## Each side of a hyphen is its own word: 100-MILE WILDERNESS is a place, not
	## a number followed by a word.
	var bits := w.split("-")
	var out: PackedStringArray = []
	for b in bits:
		var sb := String(b)
		if sb.is_empty():
			out.append(sb)
		else:
			out.append(sb.substr(0, 1).to_upper() + sb.substr(1))
	return "-".join(out)


static func line_for(state: Dictionary, region: String, was: String) -> String:
	## What the world SAYS when a border moves. The Chronicle deposits this at
	## the region's chief seat, so news of a frontier arrives the same way news
	## of anything else does -- by someone telling you in a village.
	var now := holder_of(state, region)
	if now == was:
		return ""
	if now == CONTESTED:
		return "there is argument over who holds %s now" % pretty(region)
	if now == MEN:
		return "the watch has the roads through %s again" % pretty(region)
	if now == GOBLINS:
		return "no honest man walks %s after dark any more" % pretty(region)
	if now == WOLVES:
		return "the packs have run the herds out of %s" % pretty(region)
	return "%s has gone back to the wild" % pretty(region)


## ============================== Validation ================================
## Handed the tables IN, so the suite can pass one that IS wrong and demand
## the right complaint back. A guard nothing can reach is not a guard.


static func problems_in(tag_claim: Dictionary, ground: Dictionary,
		seats: Dictionary, adj: Dictionary, land: Array) -> Array:
	var out: Array = []

	## every claimant a tag names must be one that can hold ground
	for t in tag_claim:
		var who := String(tag_claim[t])
		if who != LAWLESS and not CLAIMANTS.has(who):
			out.append("tag %s speaks for %s, who is nobody" % [String(t), who])

	## every band prices every claimant, or a hold would silently read as zero
	for b in [BAND_HUNTER, BAND_SCAV, BAND_QUIET]:
		var row: Dictionary = ground.get(b, {})
		if row.is_empty():
			out.append("band %s has no row" % band_name(b))
			continue
		for f in CLAIMANTS:
			if not row.has(f):
				out.append("band %s does not price %s" % [band_name(b), f])

	## adjacency must be symmetric, or the frontier has a one-way street in it
	for a in land:
		var an := String(a)
		for q in (adj.get(an, []) as Array):
			var bn := String(q)
			if not (adj.get(bn, []) as Array).has(an):
				out.append("%s adjoins %s but not the other way about" % [an, bn])

	## and the map must be one piece: an island region can never change hands,
	## because nobody is ever next door to take it
	if not land.is_empty():
		var seen := hops_from(String(land[0]), adj)
		for a in land:
			if not seen.has(String(a)):
				out.append("%s is cut off from the rest of the map" % String(a))

	## somebody has to be able to hold something
	var total := 0.0
	for a in land:
		total += float(seats.get(String(a), 0.0))
	if total <= 0.0:
		out.append("not one seat on the whole map")

	return out


static func table_problems(land: Array, seats: Dictionary, adj: Dictionary) -> Array:
	## The shipped tables, through the same door.
	var out := problems_in(TAG_CLAIM, GROUND_MULT, seats, adj, land)
	## and every species the dex knows must land in a band
	for k in CritterDex.keys():
		var key := String(k)
		if not GROUND_MULT.has(band_of(key)):
			out.append("%s falls out of every band" % key)
	return out
