extends SceneTree

# =============================================================================
# tests/ButcheryTests.gd -- what you take is what the woods do not get.
#
#   godot --headless --path . --script res://tests/ButcheryTests.gd
#
# `Butchery` is pure static arithmetic over three tables that were already in
# the project -- `Carcasses.GUILDS`, `CritterDex.harv` and `Materials.MATS` --
# so most of this is a loop over the real roster. The sections that carry the
# weight:
#
#   `backload` -- the headline, and it is a measurement rather than a design:
#   with the game's own starting kit a man has 40.70 kg of free back, and one
#   full back-load off a 49.13 kg deer leaves 26.7 %, which is under the
#   bear's floor and over the coyotes'. It is re-derived here by a second
#   implementation that never calls `take_for`, and the two must agree to the
#   gram on every butcherable species in the dex.
#
#   `nomeat` -- the defect the probe caught in this file's own first draft. A
#   Great Blue Heron has three feathers and no meat; butchering it took 7.29
#   kg off the ledger, put 60 g in the pack and denied the crows a heron for
#   nothing. Twenty-six of the forty-six rows over MIN_MASS are like that.
#
#   `edge` -- the second defect. `Materials.get_mat` falls back to iron for an
#   unknown id, so reading the tier through the front door made every string
#   in the language an edge, including "". A fallback can hide the thing you
#   built; here it hid the guard.
#
#   `scent` -- `Carcasses.find_gain` gained a `left` argument, required rather
#   than defaulted, because a default is a fallback. The arrival schedule is
#   asserted as measured literals, and the emergent half -- that the guild
#   which opens a carcass is the scout for every guild behind it -- is walked
#   through the REAL `_step_rec` with no player anywhere in it.
#
#   `wiring` -- a method nobody calls is not a feature, and a call-site scan
#   is satisfied by a gutted call. Every site is asserted with its ARGUMENTS
#   and its BRANCH, through a comment stripper, against planted-defect
#   fixtures built by concatenation.
# =============================================================================

const MIN_ASSERTIONS := 1020

# ------------------------------------------------------------------ measured
# Every number below came out of tests/_probe_butchery.gd running against the
# real dex, the real GUILDS table and the real Materials before one assertion
# was written. A constant compared with itself is not an assertion.

## ⚠ READ OFF THE LIVE GAME, not computed by hand. This round's first draft
## worked `_total_weight()` out on paper as 49.30 and hung the whole headline
## on it, and 977 green assertions did not notice; the live pass read 34.30
## off a fresh character in one call, because WORN GEAR COUNTS AT HALF and
## the paper sum had it at full. That is the difference between a man who
## cannot carry a deer and a man who can.
const FRESH_CARRIED := 34.30     ## a fresh character, live: 52 kg of free back
const LADEN_CARRIED := 49.30     ## a man already carrying fifteen kilos of loot
const LIMIT := 90.0              ## PlayerStats.BASE_CARRY at base STR
const FRESH_BACK := 55.70
const LADEN_BACK := 40.70

const DEER_KG := 49.13
## Fresh: seven cuts, and what stops him is the CARCASS -- 7.13 kg is 14.5 %,
## which `stage_of` calls bones, and you do not open bones. Verified live, in
## the running game, cut by cut.
const DEER_CUTS_FRESH := 7
const DEER_LEFT_FRESH := 7.13
const DEER_FRAC_FRESH := 0.1451
## 34.30 + 42 kg of venison + 5.70 of hide, antler and sinew. The live run
## started 3.50 kg heavier (the pickaxe had moved into the grid between two
## reads) and finished at 85.50 -- SEVEN cuts and 7.13 kg left either way,
## because what stops him is the carcass and not the back. Asserted below.
const DEER_BACK_FRESH := 82.00
const DEER_BACK_LIVE := 85.50
## Laden: six cuts, and what stops him is the BACK.
const DEER_CUTS_LADEN := 6
const DEER_LEFT_LADEN := 13.13
const DEER_FRAC_LADEN := 0.267
const DEER_BACK_LADEN := 91.00
const MOOSE_KG := 243.89
const MOOSE_LEFT := 207.89
const SEAL_FRAC := 0.0222             ## harbor seal: over the crows' 2 % floor

const BUTCHERABLE_N := 20
const REFUSED_N := 26

const CUT_IRON := 6.00
const CUT_SILVER := 6.72
const CUT_MITHRIL := 7.44

# hours to find one spring deer, whole against opened
const FIND_WHOLE := [7.5, 4.5, 24.0, 58.0]
const FIND_OPEN := [7.0, 3.0, 21.0, 36.5]

var _pass := 0
var _fail := 0
var _claims: Dictionary = {}
var _counts: Dictionary = {}
var _section := ""


func claim(section: String, n: int) -> void:
	_section = section
	_claims[section] = n
	_counts[section] = 0


func ok(cond: bool, what: String) -> void:
	_counts[_section] = int(_counts.get(_section, 0)) + 1
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL  [%s] %s" % [_section, what])


func near_f(a: float, b: float, tol: float, what: String) -> void:
	ok(absf(a - b) <= tol, "%s (got %.4f, want %.4f +/- %.4f)" % [what, a, b, tol])


# ------------------------------------------------------------------ fixtures

func read_src(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s


func _code_only(src: String) -> String:
	# Copied verbatim from tests/SeasonsTests.gd, where it was written to
	# retire a trap that had fired four rounds running: a negative source scan
	# going red on the comment explaining why the file never does the thing.
	var out: PackedStringArray = []
	for line in src.split("\n"):
		var s := String(line)
		var t := s.strip_edges()
		if t.begins_with("#"):
			continue
		var h := s.find("#")
		if h >= 0 and not s.substr(0, h).contains("\""):
			s = s.substr(0, h)
		out.append(s)
	return "\n".join(out)


func rows() -> Array:
	## Every dex row heavy enough to leave a record, with its real mass.
	var out: Array = []
	for k in CritterDex.DEX.keys():
		var d: Dictionary = CritterDex.DEX[k]
		if float(d.get("len", 0.0)) <= 0.0:
			continue
		var m := Carcasses.mass_of(String(k), float(d["len"]))
		if m < Carcasses.MIN_MASS:
			continue
		out.append({"k": String(k), "nm": String(d.get("nm", k)), "m": m,
			"harv": (d.get("harv", {}) as Dictionary)})
	out.sort_custom(func(a, b): return String(a["k"]) < String(b["k"]))
	return out


func rec_for(mass: float, left: float) -> Dictionary:
	return {"id": 1, "species": "whitetail", "nm": "White-tailed Deer",
		"at": Vector3.ZERO, "born": 0.0, "mass": mass, "left": left,
		"seen": {}, "prog": {}, "took": {}, "stripped": -1.0,
		"near_player": false, "place": "", "told": {}}


# ============================== 1 · the parts ==============================

func _t_parts() -> void:
	claim("parts", 459)
	var seen_parts: Dictionary = {}
	for r in rows():
		var harv: Dictionary = r["harv"]
		for k in harv.keys():
			var key := String(k)
			if key == "meat":
				continue
			seen_parts[key] = true
			ok(Butchery.PART_KG.has(key),
				"%s: the dex part '%s' has a shipped weight, not the default" % [r["nm"], key])
			ok(Butchery.PART_NAMES.has(key),
				"%s: the dex part '%s' has a shipped name" % [r["nm"], key])
			ok(Butchery.part_weight(key) > 0.0, "%s weighs something" % key)
	ok(seen_parts.size() >= 10,
		"the dex actually uses at least ten distinct parts (got %d)" % seen_parts.size())

	# owed is monotone in what you have taken, capped at the ordinal, and the
	# hide comes off on the FIRST cut rather than the last.
	var deer: Dictionary = (CritterDex.get_profile("whitetail") as Dictionary)["harv"]
	var mass := DEER_KG
	var last: Dictionary = {}
	for i in 51:
		var taken := mass * float(i) / 50.0
		var owed := Butchery.parts_owed(deer, mass, taken)
		for k in owed.keys():
			ok(int(owed[k]) >= int(last.get(k, 0)), "owed never goes backwards for %s" % k)
			ok(int(owed[k]) <= int(deer[k]), "owed never exceeds the dex ordinal for %s" % k)
		last = owed
	ok(int(Butchery.parts_owed(deer, mass, 0.0).size()) == 0, "nothing owed before the first cut")
	ok(int(Butchery.parts_owed(deer, mass, 0.001).get("hide", 0)) == 1,
		"THE HIDE COMES OFF FIRST -- one hide owed on the very first sliver")
	ok(int(Butchery.parts_owed(deer, mass, mass).get("sinew", 0)) == 2,
		"and the whole animal owes the whole ordinal (2 sinew)")
	var porc: Dictionary = (CritterDex.get_profile("porcupine") as Dictionary)["harv"]
	ok(int(Butchery.parts_owed(porc, 3.73, 3.73).get("quill", 0)) == 12,
		"twelve quills, but only for the whole porcupine")
	ok(int(Butchery.parts_owed(porc, 3.73, 3.73 * 0.5).get("quill", 0)) == 6,
		"and six for half of one")
	ok(str(Butchery.parts_owed(porc, 3.73, 3.73 * 1.4)) == str(Butchery.parts_owed(porc, 3.73, 3.73)),
		"taking MORE than the animal owes exactly the animal -- the fraction is clamped")
	ok(str(Butchery.parts_owed(deer, mass, mass * 9.0)) == str(Butchery.parts_owed(deer, mass, mass)),
		"however much more")


# ============================= 2 · the ledger ==============================

func _t_ledger() -> void:
	claim("ledger", 119)
	# parts_due telescopes: however you slice the animal, the sum of the dues
	# equals the cumulative owed at the end. Independent of `take_for`.
	for r in rows():
		var harv: Dictionary = r["harv"]
		if harv.is_empty():
			continue
		var mass := float(r["m"])
		for slices in [1, 3, 17]:
			var tally: Dictionary = {}
			for i in slices:
				var a := mass * float(i) / float(slices)
				var b := mass * float(i + 1) / float(slices)
				for k in Butchery.parts_due(harv, mass, a, b).keys():
					tally[k] = int(tally.get(k, 0)) + int(Butchery.parts_due(harv, mass, a, b)[k])
			var owed := Butchery.parts_owed(harv, mass, mass)
			var agree := true
			for k in owed.keys():
				if int(tally.get(k, 0)) != int(owed[k]):
					agree = false
			for k in tally.keys():
				if int(owed.get(k, 0)) != int(tally[k]):
					agree = false
			ok(agree, "%s in %d slices: the dues sum to the whole animal, never twice"
				% [r["nm"], slices])
	ok(Butchery.parts_due({"hide": 1}, 10.0, 5.0, 5.0).is_empty(),
		"a cut that takes nothing owes nothing")
	ok(Butchery.parts_due({}, 10.0, 0.0, 10.0).is_empty(), "an empty row owes nothing")


# ============================== 3 · the edge ===============================

func _t_edge() -> void:
	claim("edge", 31)
	for id in Materials.MATS.keys():
		var t := Butchery.edge_tier(String(id))
		ok(t >= 0, "%s is an edge" % id)
		near_f(Butchery.cut_kg(String(id)),
			Butchery.CUT_KG * (1.0 + Butchery.EDGE_TIER_BONUS * float(t)), 0.0001,
			"%s cuts at its tier" % id)
	# THE FALLBACK GUARD. Materials.get_mat answers iron for anything, so the
	# first draft read every string in the language as a tier-0 edge.
	ok(Butchery.edge_tier("") == -1, "the empty string is NOT an edge")
	ok(Butchery.edge_tier("nonsense") == -1, "an unknown id is NOT an edge")
	ok(Butchery.edge_tier("Iron Pickaxe") == -1, "a pickaxe is NOT an edge")
	ok(Butchery.cut_kg("") == 0.0, "and it cuts nothing")
	ok(Butchery.cut_kg("nonsense") == 0.0, "nor does an unknown id")
	ok(not Materials.get_mat("nonsense").is_empty(),
		"...while Materials.get_mat still answers for it -- which is the trap")
	near_f(Butchery.cut_kg("iron"), CUT_IRON, 0.001, "iron, the sword you start with")
	near_f(Butchery.cut_kg("silver"), CUT_SILVER, 0.001, "silver holds an edge better")
	near_f(Butchery.cut_kg("mithril"), CUT_MITHRIL, 0.001, "mithril better still")
	ok(Butchery.cut_kg("mithril") > Butchery.cut_kg("silver"),
		"and the ordering is strict across tiers")
	ok(Butchery.cut_kg("silver") > Butchery.cut_kg("iron"), "strictly, at every step")


# ============================== 4 · the wall ===============================

func _t_wall() -> void:
	claim("wall", 13)
	ok(Butchery.take_for(40.0, 6.0, LIMIT - 0.01, LIMIT) == 6.0,
		"YOU MAY ALWAYS FINISH A CUT YOU WERE LIGHT ENOUGH TO START")
	ok(Butchery.take_for(40.0, 6.0, LIMIT, LIMIT) == 0.0, "and at the limit, nothing")
	ok(Butchery.take_for(40.0, 6.0, LIMIT + 20.0, LIMIT) == 0.0, "nor over it")
	ok(Butchery.take_for(0.0, 6.0, 0.0, LIMIT) == 0.0, "nothing off an empty carcass")
	ok(Butchery.take_for(-3.0, 6.0, 0.0, LIMIT) == 0.0, "nor off a negative one")
	ok(Butchery.take_for(40.0, 0.0, 0.0, LIMIT) == 0.0, "nor with no edge")
	ok(Butchery.take_for(3.4, 6.0, 0.0, LIMIT) == 3.0,
		"whole kilograms while there is a whole kilogram to take")
	near_f(Butchery.take_for(0.97, 6.0, 0.0, LIMIT), 0.97, 0.0001,
		"THE WOODCHUCK: the sub-kilo remainder comes off exactly, not rounded to zero")
	ok(Butchery.meat_count(0.97) == 1, "and reaches the pack as one kilogram")
	ok(Butchery.meat_count(0.0) == 0, "a cut that took nothing is nothing")
	ok(Butchery.meat_count(0.01) == 1, "but any cut that took something is at least one")
	ok(Butchery.meat_count(6.0) == 6, "and a whole cut is itself")
	ok(Butchery.meat_count(6.7) == 7, "it ROUNDS, it does not floor -- 6.7 kg is seven in the pack")
	ok(Butchery.meat_count(6.4) == 6, "and 6.4 kg is six")
	# The drift between pack and ledger is bounded by MIN_MASS and is under
	# half a kilogram per carcass, once, on the last scrap.
	var worst := 0.0
	for i in 200:
		var lf := Carcasses.MIN_MASS + float(i) * 0.05
		var t := Butchery.take_for(lf, 6.0, 0.0, LIMIT)
		worst = maxf(worst, absf(float(Butchery.meat_count(t)) - t))
	ok(worst < 0.5, "pack and ledger never drift by half a kilo (worst %.3f)" % worst)


# ============================ 5 · the back-load ============================

func back_load(mass: float, harv: Dictionary, mat: String, keep_parts: bool,
		start := FRESH_CARRIED) -> Dictionary:
	## Walks the loop the way `Player._butcher_cut` does -- INCLUDING the bones
	## gate, which the first draft of this function left out and the live game
	## put back: `_butcher_cut` refuses a carcass at STAGE_BONES, so on a deer
	## the man runs out of animal four and a half kilos before he runs out of
	## back. The caller re-derives the same answer in closed form below.
	var left := mass
	var carried := start
	var n := 0
	while n < 400:
		if Carcasses.stage_of(rec_for(mass, left)) >= Carcasses.STAGE_BONES:
			break
		var want := Butchery.take_for(left, Butchery.cut_kg(mat), carried, LIMIT)
		if want <= 0.0:
			break
		var before := left
		left = maxf(left - want, 0.0)
		carried += float(Butchery.meat_count(want))
		if keep_parts:
			var due := Butchery.parts_due(harv, mass, mass - before, mass - left)
			for k in due.keys():
				carried += Butchery.part_weight(String(k)) * float(int(due[k]))
		n += 1
	return {"left": left, "frac": left / mass, "cuts": n, "carried": carried}


func _t_backload() -> void:
	claim("backload", 107)
	near_f(LIMIT - FRESH_CARRIED, FRESH_BACK, 0.001,
		"a fresh character has 55.70 kg of free back -- MEASURED LIVE, not on paper")
	near_f(LIMIT - LADEN_CARRIED, LADEN_BACK, 0.001, "a laden one has 40.70")
	near_f(Carcasses.mass_of("whitetail", 1.70), DEER_KG, 0.01, "a whitetail is 49.13 kg")
	near_f(Carcasses.mass_of("moose", 2.90), MOOSE_KG, 0.01, "a moose is 243.89 kg")
	ok(FRESH_BACK > DEER_KG, "so a fresh back is BIGGER than a whole deer")
	ok(LADEN_BACK < DEER_KG, "and a laden one is not -- which is the whole feature")

	var deer_h: Dictionary = (CritterDex.get_profile("whitetail") as Dictionary)["harv"]

	# FRESH. Stopped by the CARCASS: seven cuts and the deer is bones.
	var f := back_load(DEER_KG, deer_h, "iron", true, FRESH_CARRIED)
	ok(int(f["cuts"]) == DEER_CUTS_FRESH,
		"seven cuts on a deer with an empty back (got %d)" % int(f["cuts"]))
	near_f(float(f["left"]), DEER_LEFT_FRESH, 0.01, "leaving 7.13 kg")
	near_f(float(f["frac"]), DEER_FRAC_FRESH, 0.002, "which is 14.5 %")
	near_f(float(f["carried"]), DEER_BACK_FRESH, 0.01, "with the man at 82.00 of 90")
	var f_live := back_load(DEER_KG, deer_h, "iron", true, FRESH_CARRIED + 3.5)
	near_f(float(f_live["carried"]), DEER_BACK_LIVE, 0.01,
		"and the LIVE run, three and a half kilos heavier, finished at 85.50")
	ok(int(f_live["cuts"]) == int(f["cuts"]),
		"same number of cuts, three and a half kilos heavier")
	near_f(float(f_live["left"]), float(f["left"]), 0.0001,
		"and the same 7.13 kg left -- the outcome is INVARIANT to the load, "
		+ "because the gate is the carcass")
	ok(float(f["carried"]) < LIMIT,
		"UNDER the limit -- THE BACK IS NOT WHAT STOPPED HIM, he had four and a half kilos spare")
	ok(Carcasses.stage_of(rec_for(DEER_KG, float(f["left"]))) >= Carcasses.STAGE_BONES,
		"THE CARCASS IS -- what is left is bones, and you do not open bones")
	var den_fresh := Butchery.denied(DEER_KG, float(f["left"]))
	ok(den_fresh.has("pack"), "and 14.5 % is under the coyotes' floor: THE PACK NEVER COMES")
	ok(den_fresh.has("bear"), "nor the bear")
	ok(not den_fresh.has("fox"), "the fox still does")
	ok(not den_fresh.has("corvid"), "and the crows, who are not proud")

	# LADEN. The same deer, the same blade, fifteen kilos already on his back.
	var d := back_load(DEER_KG, deer_h, "iron", true, LADEN_CARRIED)
	ok(int(d["cuts"]) == DEER_CUTS_LADEN,
		"six cuts on the same deer with a laden back (got %d)" % int(d["cuts"]))
	near_f(float(d["left"]), DEER_LEFT_LADEN, 0.01, "leaving 13.13 kg")
	near_f(float(d["frac"]), DEER_FRAC_LADEN, 0.002, "which is 26.7 %")
	near_f(float(d["carried"]), DEER_BACK_LADEN, 0.01, "with the man at 91.00 of 90")
	ok(float(d["carried"]) > LIMIT, "OVER it -- the last cut is the one that puts you over")
	ok(Carcasses.stage_of(rec_for(DEER_KG, float(d["left"]))) < Carcasses.STAGE_BONES,
		"and there is still meat on it, so it was the BACK that stopped him")
	var den_laden := Butchery.denied(DEER_KG, float(d["left"]))
	ok(den_laden.has("bear"), "26.7 % is under the bear's floor")
	ok(not den_laden.has("pack"), "and OVER the coyotes' -- THE PACK COMES")
	ok(float(d["left"]) > float(f["left"]),
		"THE SAME DEER, THE SAME BLADE, AND WHAT YOU WERE ALREADY CARRYING DECIDES "
		+ "WHETHER A COYOTE PACK WALKS INTO YOUR CAMP TONIGHT")

	# YOU CANNOT DENY A MOOSE TO ANYTHING, at any load, with any blade.
	var moose_h: Dictionary = (CritterDex.get_profile("moose") as Dictionary)["harv"]
	for start: float in [FRESH_CARRIED, LADEN_CARRIED, 0.0]:
		for mat: String in ["iron", "silver", "mithril"]:
			var m := back_load(MOOSE_KG, moose_h, mat, true, start)
			ok(Butchery.denied(MOOSE_KG, float(m["left"])).is_empty(),
				"a moose at start %.0f with a %s edge still denies NOBODY" % [start, mat])
			ok(float(m["frac"]) > 0.60, "and most of it is still lying there")
	ok(MOOSE_KG * (1.0 - float((Carcasses.GUILDS[Carcasses.G_BEAR] as Dictionary)["floor"]))
			> LIMIT, "denying a bear one moose would need more than a whole carry limit of meat")

	# The whole roster, re-derived without `take_for`: cuts of `cut` kg while
	# the man is under the limit AND the carcass is not yet bones.
	var cut := Butchery.cut_kg("iron")
	var bones_kg_of := func(mass: float) -> float:
		return mass * Carcasses.BONES_AT
	for r in rows():
		var harv: Dictionary = r["harv"]
		if not Butchery.butcherable(harv):
			continue
		var mass := float(r["m"])
		var got := back_load(mass, harv, "iron", false, FRESH_CARRIED)
		var k := 0
		var taken := 0.0
		while k < 400:
			if mass - taken <= bones_kg_of.call(mass):
				break
			if FRESH_CARRIED + taken >= LIMIT:
				break
			var step: float = minf(cut, mass - taken)
			if floorf(step) >= 1.0:
				step = floorf(step)
			taken += step
			k += 1
		near_f(float(got["left"]), maxf(mass - taken, 0.0), 0.02,
			"%s: the walk and the closed form agree to the gram" % r["nm"])
		ok(int(got["cuts"]) == k, "%s: and on the number of cuts" % r["nm"])

	# Nothing under a full back can survive its own bones gate: every animal
	# small enough to carry ends AT the gate, never above it.
	for r2 in rows():
		if not Butchery.butcherable(r2["harv"]):
			continue
		var mass2 := float(r2["m"])
		var g2 := back_load(mass2, r2["harv"], "iron", true, FRESH_CARRIED)
		if mass2 <= FRESH_BACK:
			ok(float(g2["frac"]) <= Carcasses.BONES_AT + 0.001,
				"%s fits on one back, so it goes all the way to bones" % r2["nm"])
		else:
			ok(float(g2["frac"]) > Carcasses.BONES_AT,
				"%s does not, so something is always left standing" % r2["nm"])


# ============================== 6 · no meat ================================

func _t_nomeat() -> void:
	claim("nomeat", 10)
	var yes := 0
	var no := 0
	for r in rows():
		if Butchery.butcherable(r["harv"]):
			yes += 1
		else:
			no += 1
	ok(yes == BUTCHERABLE_N, "twenty rows over MIN_MASS are worth a knife (got %d)" % yes)
	ok(no == REFUSED_N, "and twenty-six are not (got %d)" % no)
	ok(not Butchery.butcherable({}),
		"THE WHALE: an empty harv row is not butcherable -- 1 200 kg destroyed for nothing")
	ok(not Butchery.butcherable({"feather": 3}),
		"THE HERON: three feathers and no meat is not butchery, it is a pluck")
	ok(not Butchery.butcherable({"meat": 0}), "nor is a zero ordinal")
	ok(Butchery.butcherable({"meat": 1}), "one is enough")
	var heron: Dictionary = (CritterDex.get_profile("heron") as Dictionary)["harv"]
	ok(not Butchery.butcherable(heron), "and the real heron row agrees")
	var deer_h2: Dictionary = (CritterDex.get_profile("whitetail") as Dictionary)["harv"]
	ok(Butchery.butcherable(deer_h2), "while the real deer row is")
	# A refused row can never reach the prompt's cutting branch.
	var p := Butchery.prompt_for(rec_for(7.29, 7.29), heron, "iron", 0.0, LIMIT)
	ok(not p.contains("[E]"), "a heron offers no cut at all")
	ok(p.contains("knife is for"), "and says why")


# ============================== 7 · the floors =============================

func _t_floors() -> void:
	claim("floors", 67)
	# `denied` must be the exact complement of the shipped `wants_it`, on every
	# species at every fraction. There is not a second copy of the economy here.
	for r in rows():
		var mass := float(r["m"])
		var agree := true
		for i in 41:
			var left := mass * float(i) / 40.0
			var rec := rec_for(mass, left)
			var den := Butchery.denied(mass, left)
			for g in Carcasses.GUILDS.size():
				var id := String((Carcasses.GUILDS[g] as Dictionary)["id"])
				if Carcasses.wants_it(g, rec) == den.has(id):
					agree = false
		ok(agree, "%s: denied() is exactly the complement of Carcasses.wants_it" % r["nm"])
	ok(Butchery.denied(0.0, 0.0).is_empty(), "a massless record denies nobody")
	ok(Butchery.denied(49.0, 0.0).size() == Carcasses.GUILDS.size(),
		"an empty carcass denies everybody")
	ok(Butchery.denied(49.0, 49.0).is_empty(), "a whole one denies nobody")

	# `crossed` fires exactly once per guild over a full strip, in floor order.
	var fired: Dictionary = {}
	var left2 := 49.13
	for i in 100:
		var before := left2
		left2 = maxf(left2 - 0.5, 0.0)
		for id in Butchery.crossed(49.13, before, left2):
			fired[String(id)] = int(fired.get(String(id), 0)) + 1
	for g in Carcasses.GUILDS.size():
		var gid := String((Carcasses.GUILDS[g] as Dictionary)["id"])
		ok(int(fired.get(gid, 0)) == 1, "%s is shut out exactly once over a full strip" % gid)
		ok(Butchery.denied_line(gid) != "", "%s has a line to say when it is" % gid)
	ok(Butchery.crossed(49.0, 40.0, 45.0).is_empty(),
		"putting meat BACK crosses nothing (and cannot un-say a line)")
	ok(Butchery.denied_line("nobody") == "", "an unknown guild says nothing at all")

	# `appetite` names the biggest guild still interested, and shuts up in order.
	ok(Butchery.appetite(49.13, 49.13).contains("bear"), "a whole deer is a bear's")
	ok(Butchery.appetite(49.13, 13.13).contains("coyotes"), "at 26.7 % it is the coyotes'")
	ok(Butchery.appetite(49.13, 7.13).contains("fox"), "at 14.5 % it is a fox's")
	ok(Butchery.appetite(49.13, 1.5).contains("crows"), "at 3 % only the crows")
	ok(Butchery.appetite(49.13, 0.5) == "nothing worth a crow",
		"and at 1 %, under even their two-per-cent floor, not even those")
	ok(Butchery.appetite(49.13, 0.0) == "nothing left", "and at nothing, nothing")
	ok(Butchery.appetite(0.0, 0.0) == "nothing left", "a massless record too")
	var seen_all: Dictionary = {}
	for i in 200:
		seen_all[Butchery.appetite(49.13, 49.13 * float(i) / 199.0)] = true
	ok(seen_all.size() == 6,
		"a full strip passes through six distinct verdicts and no more (got %d)" % seen_all.size())


# ============================== 8 · the scent ==============================

func _t_scent() -> void:
	claim("scent", 50)
	near_f(Carcasses.open_mult(49.13, 49.13), 1.0, 0.0001, "a whole animal smells of nothing extra")
	near_f(Carcasses.open_mult(49.13, 49.13 * Carcasses.OPENED_AT - 0.01),
		Carcasses.OPEN_SCENT, 0.0001, "an opened one smells")
	near_f(Carcasses.open_mult(49.13, 49.13 * Carcasses.OPENED_AT + 0.01), 1.0, 0.0001,
		"and the boundary is stage_of's own OPENED_AT, not a second number")
	near_f(Carcasses.open_mult(0.0, 0.0), 1.0, 0.0001, "a massless record is not opened")
	near_f(Carcasses.open_mult(49.13, 49.13 * Carcasses.OPENED_AT), Carcasses.OPEN_SCENT, 0.0001,
		"EXACTLY at the boundary it is opened -- which is what stage_of says too")
	var disagree := 0
	for i in 401:
		var lf := 49.13 * float(i) / 400.0
		var st := Carcasses.stage_of(rec_for(49.13, lf))
		var smells: bool = Carcasses.open_mult(49.13, lf) > 1.0
		if smells != (st >= Carcasses.STAGE_OPENED):
			disagree += 1
	ok(disagree == 0,
		"and the smell and the stage agree at every one of 401 fractions (%d disagreed)" % disagree)
	ok(Carcasses.OPEN_SCENT > 1.0, "opening it can only ever help the woods, never hinder")

	# find_gain must actually multiply by it, at every guild and every sky.
	for g in Carcasses.GUILDS.size():
		for sky in 5:
			var whole := Carcasses.find_gain(g, 49.13, 49.13, 12.0, sky, 0)
			var open_v := Carcasses.find_gain(g, 49.13, 20.0, 12.0, sky, 0)
			if whole <= 0.0:
				ok(open_v == 0.0, "guild %d grounded at sky %d stays grounded when opened" % [g, sky])
			else:
				near_f(open_v / whole, Carcasses.OPEN_SCENT, 0.0001,
					"guild %d at sky %d gains exactly OPEN_SCENT when opened" % [g, sky])

	# The measured arrival schedule, as literals.
	for g in Carcasses.GUILDS.size():
		near_f(hours_to_find(g, 49.13, 49.13, 0, 0), float(FIND_WHOLE[g]), 0.6,
			"guild %d finds a whole spring deer on schedule" % g)
		near_f(hours_to_find(g, 49.13, 20.0, 0, 0), float(FIND_OPEN[g]), 0.6,
			"guild %d finds an opened one sooner" % g)
		ok(hours_to_find(g, 49.13, 20.0, 0, 0) < hours_to_find(g, 49.13, 49.13, 0, 0),
			"guild %d: strictly sooner, never merely not-later" % g)
	near_f(hours_to_find(Carcasses.G_BEAR, 49.13, 49.13, 0, 0)
			- hours_to_find(Carcasses.G_BEAR, 49.13, 20.0, 0, 0),
		21.5, 1.0, "THE BEAR COMES A DAY EARLIER TO AN OPENED CARCASS")

	# THE EMERGENT HALF, walked through the REAL `_step_rec` with NO PLAYER
	# anywhere in it. The claim this round first wrote down here was that the
	# opening calls the fox; the walk said otherwise and was right, because the
	# fox is the FASTEST finder in the table and arrives at 4.5 h against an
	# opening at 14.5 h. It is the COYOTES the scouts call: 22.5 h against a
	# whole-carcass schedule of 24.0.
	#
	# And the walk turned up the better fact besides. A deer left to the woods
	# is eaten under the bear's thirty-per-cent floor by the small claimants
	# before a bear could ever find one, so THE BEAR NEVER COMES TO A DEER --
	# `wants_it` gates the search as well as the table. A moose is the only
	# thing big enough to still be a bear's when a bear finds it, and a moose
	# is exactly the animal a man cannot carry away. Neither half was designed.
	var deer_walk := walk(49.13)
	var moose_walk := walk(243.89)
	ok(float(deer_walk["opened"]) > 0.0,
		"a carcass nobody touches still gets opened -- by the ground and the guilds")
	near_f(float(deer_walk["opened"]), 14.5, 1.0, "at about fourteen and a half hours")
	near_f(float(deer_walk["corvid"]), 7.5, 0.6, "the crows are there long before that")
	near_f(float(deer_walk["fox"]), 4.5, 0.6, "and the fox before them")
	ok(float(deer_walk["fox"]) < float(deer_walk["opened"]),
		"so the opening cannot be what called the fox -- it is the fastest finder there is")
	near_f(float(deer_walk["pack"]), 22.5, 0.6, "THE SCOUT: the coyotes arrive at 22.5 h")
	ok(float(deer_walk["pack"]) < FIND_WHOLE[Carcasses.G_PACK] - 1.0,
		"...which is over an hour inside their whole-carcass schedule of 24.0")
	ok(float(deer_walk["opened"]) < float(deer_walk["pack"]),
		"and it was open before they got there, which is why")
	ok(float(deer_walk["bear"]) < 0.0,
		"THE BEAR NEVER COMES TO A DEER -- the small claimants eat it under his floor first")
	ok(float(moose_walk["bear"]) > 0.0, "he comes to a MOOSE")
	ok(float(moose_walk["bear"]) < FIND_WHOLE[Carcasses.G_BEAR],
		"and sooner than his whole-carcass schedule, because it is open by then")
	ok(float(moose_walk["opened"]) < float(moose_walk["bear"]),
		"which is the same scout property, on the one animal it decides anything for")


func walk(mass: float) -> Dictionary:
	## The real bus, the real `_step_rec`, spring, clear, no player at all.
	var bus := Carcasses.new()
	var rec := rec_for(mass, mass)
	rec["species"] = "x"
	var t := 0.0
	var out: Dictionary = {"opened": -1.0}
	for g in Carcasses.GUILDS.size():
		out[String((Carcasses.GUILDS[g] as Dictionary)["id"])] = -1.0
	for i in 8000:
		bus._step_rec(rec, t, fmod(t * 24.0, 24.0), 0, 0)
		t += Carcasses.STEP_HOURS / 24.0
		if float(out["opened"]) < 0.0 and Carcasses.open_mult(mass, float(rec["left"])) > 1.0:
			out["opened"] = t * 24.0
		for k in (rec["seen"] as Dictionary).keys():
			if float(out.get(String(k), -1.0)) < 0.0:
				out[String(k)] = t * 24.0
		if float(rec["left"]) <= 0.0:
			break
	bus.free()
	return out


func hours_to_find(g: int, mass: float, left: float, sky: int, season: int) -> float:
	var h := 0.0
	var p := 0.0
	var hr := 0.0
	while p < 1.0 and h < 3000.0:
		p += Carcasses.find_gain(g, mass, left, hr, sky, season)
		h += Carcasses.STEP_HOURS
		hr = fmod(hr + Carcasses.STEP_HOURS, 24.0)
	return h


# ============================== 9 · the prompt =============================

func _t_prompt() -> void:
	claim("prompt", 17)
	var deer_h: Dictionary = (CritterDex.get_profile("whitetail") as Dictionary)["harv"]
	var whole := rec_for(DEER_KG, DEER_KG)
	var bones := rec_for(DEER_KG, DEER_KG * 0.05)
	var lines: Dictionary = {}
	var normal := Butchery.prompt_for(whole, deer_h, "iron", 10.0, LIMIT)
	var no_edge := Butchery.prompt_for(whole, deer_h, "", 10.0, LIMIT)
	var full := Butchery.prompt_for(whole, deer_h, "iron", LIMIT, LIMIT)
	var boned := Butchery.prompt_for(bones, deer_h, "iron", 10.0, LIMIT)
	var no_meat := Butchery.prompt_for(whole, {"feather": 2}, "iron", 10.0, LIMIT)
	for s in [normal, no_edge, full, boned, no_meat]:
		ok(String(s) != "", "every branch says something")
		lines[s] = true
	ok(lines.size() == 5, "and all five branches say something DIFFERENT (got %d)" % lines.size())
	ok(normal.contains("[E]"), "only the cutting branch offers the key")
	ok(not no_edge.contains("[E]"), "no edge, no offer")
	ok(not full.contains("[E]"), "a full back, no offer")
	ok(not boned.contains("[E]"), "bones, no offer")
	ok(not no_meat.contains("[E]"), "no meat, no offer")
	ok(normal.contains("white-tailed deer"),
		"it names the animal in lower case -- this is a thing you are looking at, not a map label")
	ok(normal.contains("49 kg"), "and how much is on it")
	ok(normal.contains("bear"), "and who else would come for it")
	ok(full.contains("90"), "the full-back line shows the limit you are against")
	ok(Butchery.prompt_for({}, deer_h, "iron", 0.0, LIMIT) == "", "an empty record prompts nothing")
	# The prompt must track the ledger, not restate a constant.
	var a := Butchery.prompt_for(rec_for(DEER_KG, 40.0), deer_h, "iron", 10.0, LIMIT)
	var b := Butchery.prompt_for(rec_for(DEER_KG, 20.0), deer_h, "iron", 10.0, LIMIT)
	ok(a != b, "and it changes as the carcass does")


# ============================== 10 · the meat ==============================

func _t_names() -> void:
	claim("names", 69)
	ok(Butchery.meat_name("whitetail", "White-tailed Deer") == "Venison",
		"English has a word for exactly one of them and it is worth having")
	ok(Butchery.meat_name("moose", "Moose") == "Moose Meat", "the rest are named off the dex")
	ok(Butchery.meat_name("coyote", "Eastern Coyote") == "Coyote Meat",
		"by their LAST word, so a modifier never leaks into a pack row")
	ok(Butchery.meat_name("snowshoe_hare", "Snowshoe Hare") == "Hare Meat", "hare, not snowshoe")
	ok(Butchery.meat_name("specter_moose", "The Specter Moose") == "Moose Meat",
		"and a legend's definite article is dropped")
	ok(Butchery.meat_name("x", "") == "Meat", "an unnamed thing still yields meat")
	ok(Butchery.part_name("hide", "White-tailed Deer") == "Deer Hide", "parts the same way")
	ok(Butchery.part_name("quill", "Porcupine") == "Porcupine Quill", "on the real rows too")
	# Every butcherable row produces a distinct, non-empty, capitalised name.
	var names: Dictionary = {}
	for r in rows():
		if not Butchery.butcherable(r["harv"]):
			continue
		var n := Butchery.meat_name(String(r["k"]), String(r["nm"]))
		ok(n != "" and n != "Meat", "%s yields a named meat (%s)" % [r["nm"], n])
		ok(n == n.strip_edges(), "%s: no stray whitespace" % n)
		ok(n.substr(0, 1) == n.substr(0, 1).to_upper(),
			"%s: a pack row is a LABEL and is capitalised" % n)
		names[n] = true
	ok(names.size() >= 17, "and the twenty butcherable rows are near enough all distinct")


# ============================= 11 · the wiring =============================

func _t_wiring() -> void:
	claim("wiring", 33)
	var pl := _code_only(read_src("res://scripts/Player.gd"))
	var bu := _code_only(read_src("res://scripts/Butchery.gd"))
	var ca := _code_only(read_src("res://scripts/Carcasses.gd"))
	ok(pl.length() > 100000, "Player.gd was actually read (a scan that comes back empty agrees with everything)")
	ok(bu.length() > 3000, "Butchery.gd was actually read")
	ok(ca.length() > 20000, "Carcasses.gd was actually read")

	# THE CALL SITE, with its arguments and its branch -- never the bare name.
	ok(pl.contains("carc.harvest_at(rec[\"at\"] as Vector3, 1.0, want)"),
		"harvest_at IS CALLED, with the record's own position and the wall's own answer")
	ok(pl.contains("var want := Butchery.take_for(before, Butchery.cut_kg(edge), carried, limit)"),
		"and `want` is take_for's answer, off the edge, the back and the limit")
	ok(pl.contains("var carried := _total_weight()"), "with the real pack weight")
	ok(pl.contains("var limit := stats.carry_limit()"), "and the real carry limit off the sheet")
	ok(pl.contains("_butcher_cut()"), "E reaches it")
	ok(pl.contains("not _carc_target.is_empty():\n\t\t\t\t\t_butcher_cut()"),
		"...inside the branch that requires a carcass under the gaze")
	ok(pl.contains("KEY_E:"), "and that branch lives under the EXISTING interact key")
	ok(pl.contains("Butchery.butcherable(harv0)"), "the no-meat guard is at the call site")
	ok(pl.contains("if Butchery.edge_tier(m) >= 0:\n\t\t\treturn m"),
		"_edge_mat proves the material IS one before calling it an edge")
	ok(pl.contains("Butchery.meat_count(got)"), "the pack takes meat_count of what the LEDGER gave")
	ok(pl.contains("Butchery.parts_due(harv, carcass_mass, carcass_mass - before, carcass_mass - after)"),
		"and the parts come off the two ledger readings, not off what we asked for")
	ok(pl.contains("exposure.wet = minf(1.0, exposure.wet + Butchery.CUT_WET)"),
		"a cut is wet work")
	ok(pl.contains("if warmth_survival():\n\t\texposure.wet"),
		"...and it is gated on the survival mode, like every other exposure write")
	ok(pl.contains("Butchery.crossed(carcass_mass, before, after)"),
		"the shut-out lines are driven off the two ledger readings")
	ok(pl.contains("Butchery.prompt_for(_carc_target, chv, _edge_mat()"),
		"the HUD reads the prompt off the same file")
	ok(pl.contains("_cut_cd = Butchery.CUT_SECONDS"), "a cut costs time")
	ok(pl.contains("stamina = maxf(0.0, stamina - Butchery.CUT_STAMINA)"), "and strength")

	# `find_gain` must be handed the record's LEFT, not its mass -- the whole
	# open_mult term is invisible if the call site passes the wrong one.
	ok(ca.contains("find_gain(g, mass, float(rec.get(\"left\", 0.0)), hour, sky, season)"),
		"_step_rec hands find_gain the LIVE remainder, not the original mass")
	ok(ca.contains("* open_mult(mass, left)"), "and find_gain multiplies by it")
	ok(not ca.contains("left := -1.0"), "`left` is required, never defaulted -- a default is a fallback")

	# `CritterDex.harv` gets its first reader in the life of the project.
	ok(pl.contains("get(\"harv\", {})"), "the dex's harv row is READ")
	ok(bu.contains("harv.keys()"), "and walked")
	ok(bu.contains("if key == \"meat\":"), "with the meat held out of the part count")

	# NO NEW BINDING.
	ok(not bu.contains("KEY_"), "Butchery.gd claims no key")
	ok(not bu.contains("_input"), "and hooks no input")
	ok(not bu.contains("get_tree"), "no tree")
	ok(not bu.contains("randf"), "no RNG")
	ok(not bu.contains("\nvar "), "no instance state at all -- pure static, like Slumber and Factions")

	# PLANTED DEFECTS, built by concatenation, so the scanner is proved to bite.
	var planted := "pass  " + "# carc.harvest_at(rec[\"at\"] as Vector3, 1.0, want)"
	ok(not _code_only(planted).contains("harvest_at"),
		"a call commented out does NOT satisfy the scan")
	var planted2 := "\tvar want := Butchery.take_for(before, 6.0, carried, limit)"
	ok(not _code_only(planted2).contains("Butchery.cut_kg(edge)"),
		"a gutted call -- the edge replaced by a literal -- does NOT satisfy it")
	var planted3 := "find_gain(g, mass, mass, hour, sky, season)"
	ok(not _code_only(planted3).contains("float(rec.get(\"left\", 0.0))"),
		"and passing the mass where the remainder belongs does NOT satisfy it")


# ============================ 12 · determinism =============================

func _t_determinism() -> void:
	claim("det", 46)
	var deer_h: Dictionary = (CritterDex.get_profile("whitetail") as Dictionary)["harv"]
	for i in 20:
		var lf := DEER_KG * float(i) / 19.0
		ok(Butchery.take_for(lf, 6.0, 0.0, LIMIT) == Butchery.take_for(lf, 6.0, 0.0, LIMIT),
			"take_for is a function of its arguments and nothing else")
		ok(str(Butchery.parts_owed(deer_h, DEER_KG, lf))
			== str(Butchery.parts_owed(deer_h, DEER_KG, lf)), "and so is parts_owed")
	# A signature that cannot see the variable cannot see the bug: every one of
	# take_for's four arguments must be able to change its answer.
	ok(Butchery.take_for(2.0, 6.0, 0.0, LIMIT) != Butchery.take_for(40.0, 6.0, 0.0, LIMIT),
		"`left` moves it")
	ok(Butchery.take_for(40.0, 6.0, 0.0, LIMIT) != Butchery.take_for(40.0, 7.0, 0.0, LIMIT),
		"`want` moves it")
	ok(Butchery.take_for(40.0, 6.0, 0.0, LIMIT) != Butchery.take_for(40.0, 6.0, 95.0, LIMIT),
		"`carried` moves it")
	ok(Butchery.take_for(40.0, 6.0, 50.0, LIMIT) != Butchery.take_for(40.0, 6.0, 50.0, 40.0),
		"`limit` moves it")
	# ...and the same for open_mult.
	ok(Carcasses.open_mult(49.0, 49.0) != Carcasses.open_mult(49.0, 20.0), "`left` moves open_mult")
	ok(Carcasses.open_mult(49.0, 45.0) != Carcasses.open_mult(500.0, 45.0),
		"`mass` moves it too -- 45 kg is most of a deer and a rounding error off a moose")


func _init() -> void:
	print("ButcheryTests")
	_t_parts()
	_t_ledger()
	_t_edge()
	_t_wall()
	_t_backload()
	_t_nomeat()
	_t_floors()
	_t_scent()
	_t_prompt()
	_t_names()
	_t_wiring()
	_t_determinism()

	var short_sections: Array = []
	for s in _claims.keys():
		if int(_counts.get(s, 0)) < int(_claims[s]):
			short_sections.append("%s %d/%d" % [s, int(_counts.get(s, 0)), int(_claims[s])])
	if not short_sections.is_empty():
		print("  FAIL  sections short of their claim: " + ", ".join(PackedStringArray(short_sections)))
		_fail += short_sections.size()
	for s2 in _claims.keys():
		print("  · %-10s %d" % [s2, int(_counts.get(s2, 0))])
	var total := _pass + _fail
	if total < MIN_ASSERTIONS:
		print("  FAIL  only %d assertions, floor is %d" % [total, MIN_ASSERTIONS])
		_fail += 1
	if _fail == 0:
		print("ALL GREEN — %d assertions" % total)
	else:
		print("RED — %d passed, %d FAILED (of %d)" % [_pass, _fail, total])
	quit()
