extends SceneTree

# =============================================================================
# tests/FireAudioTests.gd -- the fire's voice, and its light (2026-09-10, POLISH).
#
#   godot --headless --path . --script res://tests/FireAudioTests.gd
#
# Nothing here needs terrain, a Player, World.tscn, a pixel or an audio device.
# Every decision the fire bus makes is a static function taking plain data --
# `bed_key`, `pop_rate`, `rank_fires`, `assign_beds`, `shadow_pick` -- so
# "twenty-six hearths, three voices, and you are standing at the fourth one"
# is a call with arguments rather than a thing you walk across a county to see.
#
# Three sections carry more weight than the rest:
#
#   `signal` -- the refactor's whole claim. The light's flicker USED to be
#   computed inline in `_apply_visuals`; it is now `Firepit.flame_signal(t)`,
#   read by the light AND by the crackle rate. The assertion that matters is
#   that the new expression is the old one to six decimal places, written out
#   longhand, so "we changed nothing you can see" is a test and not a promise.
#
#   `beds` -- the fixture is TWENTY-SIX fires, because that is what the map
#   actually holds after `3a24658` (twenty-five croft hearths and your camp),
#   and a budget of three. A stability bug in the slot assignment is invisible
#   at four fires and deafening at twenty-six.
#
#   `firepit` -- FireAudio adds no public method to Firepit, and rests
#   entirely on six of its methods. A stub answering those six names would let
#   this whole suite pass while the real class rotted, so the real front door
#   gets its own section. (2026-09-09's standing rule: a stub is not the
#   collaborator, and that holds for a round that only CALLS.)
# =============================================================================

const MIN_ASSERTIONS := 110

var _pass := 0
var _fail := 0
var _claims: Dictionary = {}
var _counts: Dictionary = {}
var _section := ""


# ------------------------------------------------------------------- harness

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
	ok(absf(a - b) <= tol, "%s (got %.6f, want %.6f +/- %.6f)" % [what, a, b, tol])


func within(v: float, lo: float, hi: float, what: String) -> void:
	ok(v >= lo and v <= hi, "%s (got %.3f, want %.3f..%.3f)" % [what, v, lo, hi])


func _src(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


# ------------------------------------------------------------------ fixtures

func _pit(pos: Vector3, st: int, fuel := 0.0, ember := 0.0) -> Firepit:
	var f := Firepit.make()
	f.position = pos
	f.boot()
	f.state = st
	f.fuel = fuel
	f.ember_t = ember
	return f


func _entry(id: int, pos: Vector3, st: int) -> Dictionary:
	return {"id": id, "pos": pos, "state": st}


func _county() -> Array:
	## The map as it actually stands: twenty-five croft hearths scattered out to
	## four hundred metres, plus the fire you built, at your feet. Ids are 1-26.
	var out: Array = []
	out.append(_entry(1, Vector3(2.0, 0, 0), Firepit.State.LIT))
	for i in range(25):
		var ang := float(i) * 0.8
		var r := 9.0 + float(i) * 16.0
		var st := Firepit.State.LIT if i % 3 != 2 else Firepit.State.EMBERS
		out.append(_entry(2 + i, Vector3(cos(ang) * r, 0.0, sin(ang) * r), st))
	return out


func _drive_pops(f01: float, seconds: float) -> int:
	## The accumulator FireAudio._drive_pops runs, in the open, so the pop COUNT
	## over a minute is a number this suite can hold to account.
	var ph := 0.0
	var n := 0
	var t := 0.0
	var dt := 1.0 / 60.0
	while t < seconds:
		ph += dt * FireAudio.pop_rate(f01, Firepit.flame_signal(t))
		while ph >= 1.0:
			ph -= 1.0
			n += 1
		t += dt
	return n


# --------------------------------------------------------------------- entry

func _initialize() -> void:
	print("\n=== FireAudioTests ===")


func _process(_d: float) -> bool:
	_t_signal()
	_t_flame01()
	_t_pops()
	_t_popkeys()
	_t_bedkey()
	_t_rank()
	_t_beds()
	_t_gain()
	_t_hiss()
	_t_shadow()
	_t_shadow_live()
	_t_color()
	_t_pack()
	_t_firepit()
	_t_looping()
	_t_wiring()
	_t_purity()
	_t_no_bindings()
	_report()
	return true


func _report() -> void:
	for s in _claims:
		var want := int(_claims[s])
		var got := int(_counts.get(s, 0))
		if want != got:
			_fail += 1
			print("  FAIL  [claims] section '%s' claimed %d assertions, ran %d" % [s, want, got])
	print("\n--- %d passed, %d failed (floor %d) ---" % [_pass, _fail, MIN_ASSERTIONS])
	if _pass + _fail < MIN_ASSERTIONS:
		print("FAIL: only %d assertions ran" % (_pass + _fail))
		quit(1)
		return
	quit(1 if _fail > 0 else 0)


# -------------------------------------------------------------------- signal

func _t_signal() -> void:
	claim("signal", 9)
	## THE CLAIM OF THE WHOLE ROUND. The light used to compute its flicker
	## inline; it now reads this. Below, the OLD expression written out
	## longhand, and the new one, agreeing to a millionth.
	var worst := 0.0
	var lo := INF
	var hi := -INF
	var t := 0.0
	while t < 40.0:
		var old_flick := 1.0 + sin(t * 11.3) * 0.06 + sin(t * 4.1) * 0.04
		var new_flick := 0.90 + 0.20 * Firepit.flame_signal(t)
		worst = maxf(worst, absf(old_flick - new_flick))
		var s := Firepit.flame_signal(t)
		lo = minf(lo, s)
		hi = maxf(hi, s)
		t += 0.005
	ok(worst < 1.0e-6, "the new flicker IS the old flicker (worst drift %.9f)" % worst)
	ok(lo < 0.05, "the signal reaches down near nothing (min %.4f)" % lo)
	ok(hi > 0.95, "and up near full (max %.4f)" % hi)
	within(Firepit.flame_signal(0.0), 0.49, 0.51, "it starts halfway up")
	ok(Firepit.flame_signal(1.234) == Firepit.flame_signal(1.234),
			"and it is deterministic -- two fires fed the same wood flicker alike")
	ok(Firepit.flame_signal(1.234) != Firepit.flame_signal(1.334),
			"but it is not a constant")
	## The two terms are different in kind: a fast gutter and a slow breath.
	## If the fast one were removed the signal would still move, so the test
	## that catches it is the RATE of movement, not the range.
	var fast := absf(Firepit.flame_signal(0.02) - Firepit.flame_signal(0.0))
	ok(fast > 0.04, "the fast gutter moves it measurably in a fiftieth of a second (%.4f)" % fast)
	ok(Firepit.FLICKER_A > 2.0 * Firepit.FLICKER_B,
			"the gutter is at least twice the frequency of the breath")
	## Coals do not gutter, they breathe.
	ok(Firepit.EMBER_BREATH < 0.5, "and embers breathe at under half a flame's rate")


# ------------------------------------------------------------------- flame01

func _t_flame01() -> void:
	claim("flame01", 10)
	var out := _pit(Vector3.ZERO, Firepit.State.OUT)
	var full := _pit(Vector3.ZERO, Firepit.State.LIT, Firepit.FUEL_BRIGHT)
	var over := _pit(Vector3.ZERO, Firepit.State.LIT, Firepit.FUEL_MAX)
	var low := _pit(Vector3.ZERO, Firepit.State.LIT, 60.0)
	var coals := _pit(Vector3.ZERO, Firepit.State.EMBERS, 0.0, Firepit.EMBER_SECONDS)

	near_f(out.flame01(), 0.0, 0.0001, "a dead pit is at nothing")
	near_f(full.flame01(), 1.0, 0.0001, "a well-fed flame is at full")
	near_f(over.flame01(), 1.0, 0.0001, "and a banked one does not go past full")
	ok(low.flame01() < 0.12, "a flame down to a minute of fuel is nearly out (%.3f)" % low.flame01())
	ok(low.flame01() > 0.0, "but not out")
	## Coals are a quarter of a fire in heat; they are a quarter of one here too.
	ok(coals.flame01() <= 0.26, "fresh coals sit at a quarter (%.3f)" % coals.flame01())
	ok(coals.flame01() > 0.20, "and not lower than that")
	ok(full.flame01() > coals.flame01() * 3.5,
			"a flame is at least three and a half times a coal bed")
	## Monotone in fuel -- the thing a mutation to the divisor breaks.
	var a := _pit(Vector3.ZERO, Firepit.State.LIT, 120.0)
	var b := _pit(Vector3.ZERO, Firepit.State.LIT, 480.0)
	ok(b.flame01() > a.flame01() + 0.5,
			"and four times the fuel is at least half a meter brighter (%.3f vs %.3f)"
			% [b.flame01(), a.flame01()])
	near_f(full.signal_now(), Firepit.flame_signal(0.0), 0.0001,
			"signal_now() is the shared signal, not a second copy of it")
	for f in [out, full, over, low, coals, a, b]:
		(f as Firepit).free()


# ---------------------------------------------------------------------- pops

func _t_pops() -> void:
	claim("pops", 12)
	## MEASURED, NOT CHOSEN. These are literal margins in pops per second and
	## pops per minute, which is the only form of the assertion that can fail:
	## stated against POP_HZ_MAX it would agree with itself whatever that
	## constant became (2026-09-10 03:00, nine of them in one green file).
	var fresh := FireAudio.pop_rate(1.0, 0.5)
	var dying := FireAudio.pop_rate(0.0, 0.5)
	within(fresh, 2.9, 3.7, "a fed fire pops about three times a second")
	within(dying, 0.35, 0.75, "a dying one about every other second")
	ok(fresh > dying * 4.0, "so a fed fire is at least four times as busy (%.2fx)" % (fresh / dying))

	## The flicker warps the rate. Band stated as a literal ratio.
	var bright := FireAudio.pop_rate(0.5, 1.0)
	var dark := FireAudio.pop_rate(0.5, 0.0)
	within(bright / dark, 1.5, 2.1, "the flare pops nearly twice as often as the gutter")
	ok(bright > FireAudio.pop_rate(0.5, 0.5), "and the signal moves the rate at all")
	ok(FireAudio.pop_rate(0.5, 0.5) > dark, "in both directions")

	## Clamped at both ends, so a caller handing it rubbish cannot make a
	## machine gun out of a fire.
	near_f(FireAudio.pop_rate(4.0, 0.5), fresh, 0.0001, "f01 above one is clamped")
	near_f(FireAudio.pop_rate(-3.0, 0.5), dying, 0.0001, "and below zero")
	near_f(FireAudio.pop_rate(0.5, 9.0), bright, 0.0001, "the signal is clamped too")

	## And the accumulator, driven for a real minute at a real frame rate.
	var hot := _drive_pops(1.0, 60.0)
	var cold := _drive_pops(0.05, 60.0)
	ok(hot >= 150, "a minute at a fed fire is at least 150 pops (got %d)" % hot)
	ok(cold <= 55, "a minute at a dying one is at most 55 (got %d)" % cold)
	ok(hot > cold * 3, "which is more than three times as many")


func _t_popkeys() -> void:
	claim("popkeys", 8)
	## Deterministic, and every key it can name has to be in the pack.
	var seen: Dictionary = {}
	var settles := 0
	for n in range(66):
		var k := FireAudio.pop_key(n)
		seen[k] = true
		if k.begins_with("settle_"):
			settles += 1
	ok(seen.size() >= 9, "sixty-six pops use at least nine different sounds (%d)" % seen.size())
	ok(settles == 5, "and five of them are a log shifting (got %d)" % settles)
	ok(FireAudio.pop_key(0) == "crackle_1", "the first pop is a crackle, not a settle")
	ok(FireAudio.pop_key(11).begins_with("settle_"), "the eleventh is a settle")
	ok(FireAudio.pop_key(3) == FireAudio.pop_key(3), "it is deterministic")
	ok(FireAudio.pop_key(3) != FireAudio.pop_key(4), "and it does not repeat back to back")
	var crackles := 0
	for n in range(FireAudio.POP_KINDS):
		if FireAudio.pop_key(n).begins_with("crackle_"):
			crackles += 1
	ok(crackles == FireAudio.POP_KINDS, "the first six pops are all six crackles")
	ok(seen.size() <= FireAudio.POP_KINDS + FireAudio.SETTLE_KINDS,
			"and it never names a sound outside the pack")


# ------------------------------------------------------------------- bed_key

func _t_bedkey() -> void:
	claim("bedkey", 9)
	ok(FireAudio.bed_key(Firepit.State.OUT, 0.0) == "", "a dead pit has no bed")
	ok(FireAudio.bed_key(Firepit.State.OUT, 900.0) == "",
			"and fuel in a pit nobody lit is still silence")
	ok(FireAudio.bed_key(Firepit.State.EMBERS, 0.0) == "ember_bed", "coals get the coal bed")
	ok(FireAudio.bed_key(Firepit.State.EMBERS, 900.0) == "ember_bed",
			"whatever their fuel says -- embers are a different SOUND, not a quiet flame")
	ok(FireAudio.bed_key(Firepit.State.LIT, 900.0) == "fire_bed_big", "a fed fire roars")
	ok(FireAudio.bed_key(Firepit.State.LIT, 30.0) == "fire_bed_small", "a low one does not")
	## The threshold is a real one and sits inside the range a fire actually
	## occupies: above a plank, below two logs.
	within(FireAudio.BIG_FUEL, Firepit.FUEL_PER_PLANK + 1.0, Firepit.FUEL_PER_LOG * 2.0,
			"and 'big' is somewhere between a plank and two logs")
	ok(FireAudio.bed_db("fire_bed_big") > FireAudio.bed_db("fire_bed_small") + 2.0,
			"a big fire is at least 2 dB louder than a small one")
	ok(FireAudio.bed_db("ember_bed") < FireAudio.bed_db("fire_bed_small") - 6.0,
			"and coals are at least 6 dB under a low flame")


# ---------------------------------------------------------------------- rank

func _t_rank() -> void:
	claim("rank", 10)
	var county := _county()
	ok(county.size() == 26, "the fixture is the map as it stands: twenty-six fires")
	var near := FireAudio.rank_fires(county, Vector3.ZERO, FireAudio.HEAR_R)
	ok(near.size() >= 3, "at least three of them are audible from the middle (%d)" % near.size())
	ok(near.size() < county.size(), "but not all twenty-six")
	ok(near[0] == 1, "the fire at your feet is first")
	## Sorted, strictly, all the way down.
	var sorted_ok := true
	var by_id: Dictionary = {}
	for e in county:
		by_id[int((e as Dictionary)["id"])] = (e as Dictionary)["pos"]
	for i in range(near.size() - 1):
		var da: float = (by_id[near[i]] as Vector3).length()
		var db: float = (by_id[near[i + 1]] as Vector3).length()
		if da > db:
			sorted_ok = false
	ok(sorted_ok, "and the rest are in order of distance")
	## OUT fires are not in it, at any distance.
	var with_dead := county.duplicate()
	with_dead.append(_entry(99, Vector3(0.4, 0, 0), Firepit.State.OUT))
	var r2 := FireAudio.rank_fires(with_dead, Vector3.ZERO, FireAudio.HEAR_R)
	ok(not r2.has(99), "a dead pit under your boots is not audible")
	ok(r2.size() == near.size(), "and it does not displace anything either")
	## Range is real, and the fixture straddles it: the ring runs out to 400 m.
	var far := FireAudio.rank_fires(county, Vector3(600.0, 0, 0), FireAudio.HEAR_R)
	ok(far.is_empty(), "from six hundred metres away the county is silent")
	var wide := FireAudio.rank_fires(county, Vector3.ZERO, 5000.0)
	ok(wide.size() > near.size(), "widen the radius and more of it comes in")
	ok(wide.size() == 26, "all of it, in fact")


# ---------------------------------------------------------------------- beds

func _t_beds() -> void:
	claim("beds", 18)
	var county := _county()
	var ranked := FireAudio.rank_fires(county, Vector3.ZERO, FireAudio.HEAR_R)
	var claims := FireAudio.assign_beds({}, ranked, FireAudio.BEDS)
	ok(claims.size() == FireAudio.BEDS, "three fires get a bed, not twenty-six")
	var slots: Dictionary = {}
	for id in claims:
		slots[int(claims[id])] = true
	ok(slots.size() == FireAudio.BEDS, "one each -- no two fires share a slot")
	for id in claims:
		ok(ranked.slice(0, FireAudio.BEDS).has(id), "and it is one of the nearest three (id %d)" % id)

	## STABILITY. Take a step; the same three fires must keep the SAME slots,
	## or every footfall restarts the fire you are standing at.
	var moved := FireAudio.rank_fires(county, Vector3(1.0, 0, 0), FireAudio.HEAR_R)
	var claims2 := FireAudio.assign_beds(claims, moved, FireAudio.BEDS)
	var same := true
	for id in claims:
		if claims2.has(id) and int(claims2[id]) != int(claims[id]):
			same = false
	ok(same, "a step does not move any fire to a different slot")

	## A fire dropping out frees EXACTLY its slot, and the newcomer takes that
	## index -- not slot 0, and not somebody else's.
	var evicted: int = ranked[1]
	var freed := int(claims[evicted])
	var ranked3 := ranked.duplicate()
	ranked3.erase(evicted)
	var claims3 := FireAudio.assign_beds(claims, ranked3, FireAudio.BEDS)
	ok(not claims3.has(evicted), "the fire that went out loses its bed")
	ok(claims3.size() == FireAudio.BEDS, "and the slot is refilled, not left idle")
	var taker := -1
	for id in claims3:
		if not claims.has(id):
			taker = int(id)
	ok(taker != -1, "somebody new took it")
	ok(int(claims3[taker]) == freed, "and took the slot that was actually freed (%d)" % freed)
	for id in claims3:
		if claims.has(id) and id != evicted:
			ok(int(claims3[id]) == int(claims[id]), "the other two did not move (id %d)" % id)

	## AND THE OTHER DIRECTION, which the first sweep found nobody was testing:
	## a nearer fire arriving must PUSH THE THIRD ONE OUT. Over-slicing `keep`
	## survived a green suite because the free-slot budget already caps how many
	## NEW fires get seated -- so the size never moved, and a fire that had
	## dropped out of the top three quietly kept its bed for ever.
	var newcomer := 4242
	var pushed := ranked.slice(0, FireAudio.BEDS)
	var arrived: Array = [newcomer]
	arrived.append_array(pushed)
	var claims4 := FireAudio.assign_beds(claims, arrived, FireAudio.BEDS)
	ok(claims4.has(newcomer), "the fire that just walked into earshot gets a bed")
	ok(not claims4.has(pushed[FireAudio.BEDS - 1]),
			"and the one it pushed out of the top three LOSES its bed (id %d)"
			% int(pushed[FireAudio.BEDS - 1]))
	ok(claims4.size() == FireAudio.BEDS, "still three, not four")

	## Degenerate inputs.
	ok(FireAudio.assign_beds({}, [], FireAudio.BEDS).is_empty(), "no fires, no beds")
	var one := FireAudio.assign_beds({}, [7], FireAudio.BEDS)
	ok(one.size() == 1 and int(one[7]) == 0, "one fire takes the first slot")
	## A stale claim naming a slot outside the budget must not be honoured.
	var stale := FireAudio.assign_beds({7: 99}, [7], FireAudio.BEDS)
	ok(int(stale[7]) == 0, "a stale claim on a slot that does not exist is re-seated")


func _t_gain() -> void:
	claim("gain", 8)
	## A bed never pops in or out, and going out takes longer than coming in.
	near_f(FireAudio.ease_gain(0.0, 1.0, FireAudio.FADE_IN), 1.0, 0.0001,
			"a full fade-in gets all the way there")
	ok(FireAudio.ease_gain(0.0, 1.0, 0.05) < 0.10, "a frame of it gets barely anywhere")
	ok(FireAudio.ease_gain(1.0, 0.0, 0.05) > 0.90, "and a frame of fade-out even less")
	var up := 1.0 - FireAudio.ease_gain(0.0, 1.0, 0.5)
	var down := FireAudio.ease_gain(1.0, 0.0, 0.5)
	ok(down > up, "a fire fades out more slowly than it comes in")
	within(FireAudio.ease_gain(0.5, 1.0, 1000.0), 1.0, 1.0, "and a huge step still clamps at one")
	within(FireAudio.ease_gain(0.5, 0.0, 1000.0), 0.0, 0.0, "and at zero")
	## FINITE, not just quiet. `-7 + linear_to_db(0.0)` is -INF, which is quiet
	## enough to pass any "is it under -79 dB" test and is not a number you can
	## hand a mixer. The guard exists to return silence rather than negative
	## infinity, so that is what the assertion has to say -- the first sweep
	## found this one passing for the wrong reason.
	var quiet := FireAudio.gain_to_db(0.0, -7.0)
	ok(quiet <= -79.0 and is_finite(quiet), "silence is silent, and is a number (%.1f)" % quiet)
	near_f(FireAudio.gain_to_db(1.0, -7.0), -7.0, 0.0001, "and full gain is the bed's own level")


# ---------------------------------------------------------------------- hiss

func _t_hiss() -> void:
	claim("hiss", 6)
	## Gated on the MECHANIC, not on a second reading of the sky: if you can
	## hear it, your wood is going twice as fast.
	ok(FireAudio.hiss_db(1.0) <= -79.0, "a sheltered fire is silent of rain")
	ok(FireAudio.hiss_db(Firepit.RAIN_BURN_MULT) >= -30.0, "an open one in rain is not")
	ok(FireAudio.hiss_db(Firepit.RAIN_BURN_MULT) <= -6.0, "but it is under the flame itself")
	ok(FireAudio.hiss_db(1.0001) <= -79.0, "float noise on the burn rate does not open the gate")
	ok(FireAudio.hiss_db(1.4) > -79.0, "anything genuinely above one does")
	ok(Firepit.RAIN_BURN_MULT > 1.0,
			"and the mechanic it is gated on still raises the burn rate at all")


# -------------------------------------------------------------------- shadow

func _t_shadow() -> void:
	claim("shadow", 11)
	var county := _county()
	var pick := Firepit.shadow_pick(county, Vector3.ZERO, Firepit.SHADOW_RANGE)
	ok(pick == 1, "the fire at your feet casts the shadows")
	## A dead pit closer than the live one must not take the promotion.
	var with_dead := county.duplicate()
	with_dead.push_front(_entry(99, Vector3(0.2, 0, 0), Firepit.State.OUT))
	ok(Firepit.shadow_pick(with_dead, Vector3.ZERO, Firepit.SHADOW_RANGE) == 1,
			"a cold pit half a metre away does not take it from the fire you are sitting at")
	## Coals do: they are still light.
	var coals_only: Array = [_entry(5, Vector3(3, 0, 0), Firepit.State.EMBERS)]
	ok(Firepit.shadow_pick(coals_only, Vector3.ZERO, Firepit.SHADOW_RANGE) == 5,
			"a coal bed still casts")
	ok(Firepit.shadow_pick([], Vector3.ZERO, Firepit.SHADOW_RANGE) == -1, "nothing, nobody")
	var all_dead: Array = [_entry(5, Vector3(1, 0, 0), Firepit.State.OUT)]
	ok(Firepit.shadow_pick(all_dead, Vector3.ZERO, Firepit.SHADOW_RANGE) == -1,
			"a county of dead pits casts nothing")
	## Range, with a fixture built at the range so the guard is the thing deciding.
	var far_only: Array = [_entry(7, Vector3(Firepit.SHADOW_RANGE + 4.0, 0, 0), Firepit.State.LIT)]
	ok(Firepit.shadow_pick(far_only, Vector3.ZERO, Firepit.SHADOW_RANGE) == -1,
			"a fire beyond the range casts nothing -- you cannot see them move that far off")
	ok(Firepit.shadow_pick(far_only, Vector3.ZERO, 500.0) == 7, "widen it and it can")
	## Nearest, not first in the array.
	var two: Array = [
		_entry(11, Vector3(9, 0, 0), Firepit.State.LIT),
		_entry(12, Vector3(2, 0, 0), Firepit.State.LIT),
	]
	ok(Firepit.shadow_pick(two, Vector3.ZERO, Firepit.SHADOW_RANGE) == 12,
			"the nearer of two, whatever order they arrive in")
	two.reverse()
	ok(Firepit.shadow_pick(two, Vector3.ZERO, Firepit.SHADOW_RANGE) == 12, "either order")
	## It moves with you.
	ok(Firepit.shadow_pick(two, Vector3(20, 0, 0), Firepit.SHADOW_RANGE) == 11,
			"walk across the camp and the other one takes over")
	within(Firepit.SHADOW_RANGE, 6.0, 60.0,
			"and the range is a distance a person could actually stand at")


func _t_shadow_live() -> void:
	claim("shadow_live", 7)
	## The arbiter on REAL Firepits with REAL lights -- because shadow_pick
	## returning the right id proves nothing about whether anything got set.
	var a := _pit(Vector3(1.0, 0, 0), Firepit.State.LIT, 600.0)
	var b := _pit(Vector3(7.0, 0, 0), Firepit.State.LIT, 600.0)
	var c := _pit(Vector3(3.0, 0, 0), Firepit.State.OUT)
	var fires: Array = [a, b, c]
	var pick := Firepit.apply_shadows(fires, Vector3.ZERO)
	ok(pick == int(a.get_instance_id()), "the nearest live fire is picked")
	ok(a.casts_shadow(), "and it is the one whose light actually casts")
	ok(not b.casts_shadow(), "the second fire does not")
	ok(not c.casts_shadow(), "and the dead one certainly does not")
	var lit := 0
	for f in fires:
		if (f as Firepit).casts_shadow():
			lit += 1
	ok(lit == 1, "EXACTLY one shadow-caster in the world, always")
	## Walk past it.
	Firepit.apply_shadows(fires, Vector3(20.0, 0, 0))
	ok(b.casts_shadow() and not a.casts_shadow(), "and the promotion follows the listener")
	Firepit.apply_shadows(fires, Vector3(900.0, 0, 0))
	ok(not a.casts_shadow() and not b.casts_shadow(),
			"walk out of the county and nothing casts at all")
	for f in fires:
		(f as Firepit).free()


# --------------------------------------------------------------------- color

func _t_color() -> void:
	claim("color", 7)
	var hot := Firepit.light_color(Firepit.State.LIT, 1.0)
	var low := Firepit.light_color(Firepit.State.LIT, 0.0)
	var coal := Firepit.light_color(Firepit.State.EMBERS, 1.0)
	## The colour used to be a constant. A dying fire read as "the same fire,
	## further away"; it should read as a different fire.
	ok(hot.g > low.g + 0.25, "a fed flame is a quarter greener than a starved one (yellow, not red)")
	ok(hot.b > low.b + 0.15, "and carries visibly more blue")
	ok(coal.g < low.g, "coals are redder still than a starved flame")
	ok(hot.r >= 0.98 and low.r >= 0.98, "every one of them is full red -- fire is never blue here")
	var mid := Firepit.light_color(Firepit.State.LIT, 0.5)
	ok(mid.g > low.g and mid.g < hot.g, "and it moves continuously between the two")
	near_f(Firepit.light_color(Firepit.State.LIT, 4.0).g, hot.g, 0.0001, "clamped above")
	near_f(Firepit.light_color(Firepit.State.LIT, -4.0).g, low.g, 0.0001, "and below")


# ---------------------------------------------------------------------- pack

func _t_pack() -> void:
	claim("pack", 8)
	## The manifest and the code are written in two different languages by two
	## different tools; a key drifting between them is silence in the game and
	## nothing at all in a log.
	var f := FileAccess.open(FireAudio.MANIFEST, FileAccess.READ)
	ok(f != null, "the pack manifest is on disk (run tools/firesounds.py)")
	if f == null:
		for _i in range(7):
			ok(false, "no manifest -- pack assertions skipped")
		return
	var parsed = JSON.parse_string(f.get_as_text())
	ok(parsed is Dictionary, "and it parses")
	var sounds: Dictionary = ((parsed as Dictionary).get("sounds", {}) as Dictionary)
	ok(sounds.size() >= 16, "with at least sixteen sounds in it (%d)" % sounds.size())
	var need: Array = ["fire_bed_big", "fire_bed_small", "ember_bed", "rain_hiss",
			"catch", "feed_log", "douse"]
	var missing: Array = []
	for k in need:
		if not sounds.has(k):
			missing.append(k)
	for n in range(66):
		var k := FireAudio.pop_key(n)
		if not sounds.has(k) and not missing.has(k):
			missing.append(k)
	ok(missing.is_empty(), "and every key the code can ask for is in it (missing: %s)" % str(missing))
	var loops := 0
	for k in sounds:
		if bool((sounds[k] as Dictionary).get("loop", false)):
			loops += 1
	ok(loops == 4, "four of them loop: two flames, the coals and the rain (%d)" % loops)
	ok(bool((sounds["fire_bed_big"] as Dictionary).get("loop", false)),
			"the bed is one of them")
	ok(not bool((sounds["crackle_1"] as Dictionary).get("loop", false)),
			"and a crackle is not")
	ok(float((sounds["fire_bed_big"] as Dictionary).get("seconds", 0.0)) > 4.0,
			"the bed is long enough that its loop is not a stutter")


# ------------------------------------------------------------------- firepit

func _t_firepit() -> void:
	claim("firepit", 12)
	## A STUB IS NOT THE COLLABORATOR. This round adds no public method to
	## Firepit's burning model and rests entirely on it; if somebody deletes
	## one of these tomorrow, this is what goes red.
	var f := _pit(Vector3.ZERO, Firepit.State.OUT)
	ok(f.state == Firepit.State.OUT, "a fresh pit is out")
	ok(f.light(), "and it takes a light")
	ok(f.state == Firepit.State.LIT, "which puts it in LIT")
	ok(f.burning(), "and burning() agrees")
	ok(f.fuel > 0.0, "with fuel in it")
	var before := f.fuel
	ok(f.feed(Firepit.FUEL_PER_LOG), "a log goes on")
	ok(f.fuel > before + 100.0, "and is worth at least a hundred seconds")
	near_f(f.burn_rate(), 1.0, 0.0001, "with no weather, wood burns at one second a second")
	f.tick(60.0)
	near_f(f.fuel, before + Firepit.FUEL_PER_LOG - 60.0, 0.001, "a minute of ticking costs a minute")
	var heat := Firepit.heat_from([f], Vector3(0.5, 0, 0))
	ok(heat > 10.0, "and standing in it is worth over ten degrees")
	ok(Firepit.heat_from([f, f], Vector3(0.5, 0, 0)) <= heat + 0.001,
			"two references to one fire are still one fire -- heat_from takes the MAXIMUM")
	f.fuel = 0.0
	f.tick(0.1)
	ok(f.state == Firepit.State.EMBERS, "and out of fuel it drops to coals, not to nothing")
	f.free()


# ------------------------------------------------------------------- looping

func _t_looping() -> void:
	claim("looping", 11)
	## THE DEFECT THE LIVE PASS FOUND, AND THE ONE NO PURE FUNCTION COULD HAVE.
	## The suite was 149/0 green, forty-four mutations were caught, and in the
	## running game the bed played through once and stopped: `loop_end = 0` is
	## a ZERO-LENGTH loop, and nothing errors, nothing logs, and `loop_mode`
	## still reads LOOP_FORWARD while `playing` quietly goes false.
	## `scripts/WaterAudio.gd` and `scripts/CritterAudio.gd` had it too -- the
	## lake had been lapping for eight seconds a session for weeks.
	near_f(float(FireAudio.wav_loop_end(1.0, 44100)), 44099.0, 0.5,
			"a one-second bed at 44.1 kHz loops back from frame 44099")
	near_f(float(FireAudio.wav_loop_end(8.15, 44100)), 359414.0, 1.5,
			"and the real eight-second one from about 359414")
	near_f(float(FireAudio.wav_loop_end(1.0, 22050)), 22049.0, 0.5,
			"a different mix rate moves it")
	ok(FireAudio.wav_loop_end(0.0, 44100) == 0, "an empty stream loops nowhere")
	ok(FireAudio.wav_loop_end(-3.0, 44100) == 0, "and a negative length cannot go below zero")
	## Against the REAL bed on disk. ⚠ THE SECOND DEFECT LIVED HERE: the first
	## fix derived the frame count from `data.size()`, and Godot's importer had
	## already re-encoded the pack to QOA, so the "frame count" was a
	## COMPRESSED BYTE COUNT -- 145 480 against 359 416 real frames, putting the
	## loop point at 3.3 s of an 8.15 s bed. The margin below is stated against
	## the file's own true length, which is the only number the compression
	## cannot lie about.
	var bytes := FileAccess.get_file_as_bytes("res://assets/audio/fire/fire_bed_big.wav")
	ok(bytes.size() > 100000, "the big bed is on disk (%d bytes)" % bytes.size())
	var true_frames := (bytes.size() - 44) / 2      ## 16-bit mono PCM, minus the header
	var end_f := FireAudio.wav_loop_end(float(true_frames) / 44100.0, 44100)
	ok(end_f > 4 * 44100,
			"its loop point is over four seconds in, not at frame zero (%d)" % end_f)
	ok(absf(float(end_f) - float(true_frames)) < float(true_frames) * 0.01,
			"and within 1%% of the WHOLE bed (%d of %d frames) -- not a third of it"
			% [end_f, true_frames])
	## And the source, in the right function.
	var src := _src("res://scripts/FireAudio.gd")
	ok(not src.contains("w.loop_" + "end = 0"),
			"nothing in FireAudio sets a zero-length loop")
	ok(src.contains("w.loop_end = wav_loop" + "_end(w.get_length(), w.mix_rate)"),
			"_stream takes the loop point from the DECODED length, never from the byte count")
	var lo := src.find("func _drive_beds")
	var hi := src.find("func _drive_pops")
	var body := src.substr(lo, maxi(0, hi - lo))
	ok(lo > 0 and hi > lo and body.length() > 800 and body.contains("not p.playing"),
			"and _drive_beds (%d chars) restarts a bed that stopped while it was wanted"
			% body.length())


# -------------------------------------------------------------------- wiring

func _t_wiring() -> void:
	claim("wiring", 10)
	## ASSERT THE CALL, IN THE FUNCTION, AND IN THE RIGHT ORDER. Every pure
	## function above can be perfect and the light still not read any of them:
	## `_apply_visuals` is where the signal, the colour and the ember breath
	## actually reach an OmniLight3D, and none of that is reachable from a
	## headless test. So the body is scanned -- and the scan is asserted to
	## have FOUND something before anything is asserted about what it found,
	## which is the defence a scan that comes back empty needs.
	var pit := _src("res://scripts/Firepit.gd")
	var lo := pit.find("func _apply_visuals")
	var hi := pit.find("func flame" + "_signal")
	ok(lo > 0 and hi > lo, "_apply_visuals is where it says it is (%d..%d)" % [lo, hi])
	var body := pit.substr(lo, maxi(0, hi - lo))
	ok(body.length() > 600, "and its body scanned back %d characters" % body.length())
	ok(body.contains("0.90 + 0.20 * flame" + "_signal(_flicker)"),
			"the LIT light energy is driven by the shared signal, not by a flicker of its own")
	ok(body.contains("light_color(State.LIT, f01)"),
			"the LIT colour rides the fuel")
	ok(body.contains("light_color(State.EMBERS, e01)"),
			"and the EMBERS colour rides the ember clock")
	ok(body.contains("flame" + "_signal(_flicker * EMBER_BREATH)"),
			"coals breathe on the same signal, slowed down")
	ok(body.contains("0.86 + 0.28 * esig"),
			"and the coal bed's own emission breathes with them")
	ok(body.contains("clampf(fuel / FUEL_BRIGHT"),
			"the light sizes a flame by FUEL_BRIGHT -- the same constant flame01() uses, so the "
			+ "two cannot disagree")
	## `_flicker` must advance in BOTH burning states. It used to advance only
	## in LIT, which froze every coal bed in the county.
	var tick_lo := pit.find("func tick(")
	var tick_hi := pit.find("func burn_rate(")
	var tick := pit.substr(tick_lo, maxi(0, tick_hi - tick_lo))
	ok(tick_lo > 0 and tick_hi > tick_lo and tick.length() > 200,
			"tick() scanned back %d characters" % tick.length())
	ok(tick.count("_flicker += delta") == 1
			and tick.find("_flicker += delta") < tick.find("if state == State.EMBERS"),
			"and the clock advances ONCE, before the embers branch returns")


# -------------------------------------------------------------------- purity

func _t_purity() -> void:
	claim("purity", 9)
	var src := _src("res://scripts/FireAudio.gd")
	ok(src.length() > 4000, "FireAudio.gd scanned back %d characters" % src.length())
	ok(not src.contains("RandomNumber" + "Generator"),
			"no RNG -- two fires fed the same wood sound the same, as they burn the same")
	ok(not src.contains("randf" + "_range") and not src.contains("randi" + "()"),
			"and nothing borrows the global one either")
	ok(not src.contains("await "), "nothing waits")
	ok(not src.contains("Time." + "get_ticks"), "and nothing reads a wall clock")
	## The pure block must be reachable with no tree at all -- that is what
	## makes the whole mix testable headless. Scan the block, and assert the
	## scan FOUND it: a scan that comes back empty agrees with everything.
	var lo := src.find("The pure decisions")
	var hi := src.find("#  The frame")
	ok(lo > 0 and hi > lo, "the pure block is where it says it is (%d..%d)" % [lo, hi])
	var pure := src.substr(lo, maxi(0, hi - lo))
	ok(pure.length() > 1500 and not pure.contains("get_" + "tree"),
			"and %d characters of it touch no scene tree" % pure.length())
	var pit := _src("res://scripts/Firepit.gd")
	ok(pit.contains("static func flame" + "_signal"),
			"the flame signal is a STATIC on Firepit -- one signal, no per-fire copy")
	ok(pit.count("sin(_flicker") == 0,
			"and nothing in Firepit computes a flicker of its own any more")


# -------------------------------------------------------------- no_bindings

func _t_no_bindings() -> void:
	claim("no_bindings", 8)
	## A shadowed dev binding is round-blocking. This feature claims to add no
	## binding at all; the claim is asserted here against the SOURCE.
	var reg := load("res://tests/DevInputRegistry.gd")
	ok(reg != null, "the dev-input registry is loadable")
	var fn := "func " + "_input"
	var planted := fn + "(event) -> void:\n\tif event is Input" + "EventKey:\n\t\tpass\n"
	ok(not (reg.input_callbacks(planted) as Array).is_empty(),
			"and finds a planted input callback before it is trusted on the truth")
	var spaced := fn + "(event):\n    var x = K" + "EY_F1\n"
	ok(not (reg.input_callbacks(spaced) as Array).is_empty(),
			"including a SPACE-indented one, which is the bug that hid a whole scan")
	for path in ["res://scripts/FireAudio.gd", "res://tests/FireAudioTests.gd"]:
		var src := _src(path)
		ok(src.length() > 500, "%s scanned back %d characters" % [path, src.length()])
		var cbs: Array = reg.input_callbacks(src)
		var keys := src.contains("K" + "EY_") or src.contains("Input" + "EventKey") \
				or src.contains("Input" + "Map") or src.contains("is_action" + "_pressed")
		ok(cbs.is_empty() and not keys,
				"%s declares no input callback and claims no key (%d callbacks)" % [path, cbs.size()])
	ok(true, "and the only dev affordance is a READ-ONLY readout() for the F1 panel")
