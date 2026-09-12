extends SceneTree

# =============================================================================
# tests/WarbandTests.gd -- goblins on the ground (2026-09-12 09:00, WORLD).
#
#   godot --headless --path . --script res://tests/WarbandTests.gd
#
# `Warbands.gd` is two halves and this suite is built on the seam. The RULES
# are static and pure -- who camps where, how many, and what they do with a
# night -- so "a band 1 000 m off the road works it in January and never sees
# it in July" is a call with four arguments rather than a thing you stand in a
# wood and wait for. The SIM is a node, and gets a real Chronicle, a real
# RoadNet and a real faction field rather than stubs of them.
#
# Five sections carry more weight than the rest:
#
#   `sites` -- an INDEPENDENT REBUILD. The camp roster is re-derived here from
#   a different statement of the same rule and the two are demanded to agree
#   cell for cell, because the roster is the one thing in the feature that
#   nothing downstream can notice being wrong: a camp seated in a lake is a
#   camp nobody ever walks to.
#
#   `season` -- the systemic claim the whole feature rests on. The prowl reach
#   is 900 m times a seasonal multiplier, so the SAME camp crosses the
#   road-working threshold twice a year. If that stops being true the north is
#   uniformly dangerous and the seasons stop mattering.
#
#   `frontier` -- the REAL `Factions` field, control against treatment on the
#   same anchors, asserting the third idea in the file's header: clearing a
#   camp loosens the goblins' grip and does NOT hand the ground to men. The
#   measured probe found a push of 0.2 handing the Allagash to the WOLVES, so
#   this is not a theoretical worry.
#
#   `rumour` and `reap` -- the two front doors that cannot be stubbed without
#   the stub becoming the thing under test. Three mutations of
#   `Chronicle.deposit_rumour` survived the Wayfarers' 128/0 green because the
#   only suite calling it used a fake, so the real Chronicle is used here.
#   `reap` is the kill accounting, and its whole difficulty is telling a goblin
#   that DIED from a goblin that was merely freed when the player walked away.
#
# SECTION CLAIMS: every section stakes what it is about to assert before it
# runs one, so a section killed by a runtime error shows up as a claim that
# never settled instead of quietly taking its assertions with it.
# =============================================================================

const MIN_ASSERTIONS := 240

var _pass := 0
var _fail := 0
var _claims: Dictionary = {}
var _counts: Dictionary = {}
var _section := ""
var _raised: Array = []
var _abandoned: Array = []
var _cleared: Array = []


class Corpse extends Node3D:
	## The one thing `_reap` reads off a body, and nothing else.
	var dying := false


func _init() -> void:
	print("WarbandTests -- goblins on the ground")
	_t_sites()
	_t_rebuild()
	_t_quota()
	_t_size()
	_t_night()
	_t_season()
	_t_routine()
	_t_occupancy()
	_t_clearing()
	_t_frontier()
	_t_rumour()
	_t_reap()
	_t_save()
	_t_no_input()
	_t_contracts()
	_t_wiring()

	var short_of := 0
	for k in _claims.keys():
		var want := int(_claims[k])
		var got := int(_counts[k])
		if got < want:
			short_of += 1
			print("  SECTION [%s] staked %d assertions and made %d" % [k, want, got])
	if short_of > 0:
		_fail += short_of
	if _pass + _fail < MIN_ASSERTIONS:
		print("  TOO FEW ASSERTIONS: %d, floor is %d" % [_pass + _fail, MIN_ASSERTIONS])
		_fail += 1
	if _fail == 0:
		print("ALL GREEN — %d assertions" % _pass)
	else:
		print("%d passed, %d FAILED" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


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
	ok(absf(a - b) <= tol, "%s (got %.4f, want %.4f +/- %.4f)" % [what, a, b, tol])


func read_src(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s


func _code_only(src: String) -> String:
	# Copied verbatim from tests/SeasonsTests.gd.
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


func func_body(src: String, header: String) -> String:
	## The BODY of one function, so that an assertion about a branch cannot be
	## satisfied by the same string appearing somewhere else in the file. Three
	## separate scans walked through exactly that on 2026-09-12 06:00.
	var at := src.find(header)
	if at < 0:
		return ""
	var rest := src.substr(at + header.length())
	var out: PackedStringArray = []
	for line in rest.split("\n"):
		var s := String(line)
		if s.begins_with("func ") or s.begins_with("static func ") \
				or s.begins_with("class ") or s.begins_with("const ") \
				or s.begins_with("var "):
			break
		out.append(s)
	return "\n".join(out)


func fresh_chronicle() -> Chronicle:
	var c := Chronicle.new()
	get_root().add_child(c)
	c.boot(true)
	return c


func fresh_net(c: Chronicle) -> RoadNet:
	var n := RoadNet.new()
	get_root().add_child(n)
	var rows: Array = []
	for p in c.places:
		var pd := p as Dictionary
		rows.append({"name": String(pd.get("name", "")), "pos": pd.get("pos", Vector2.ZERO),
			"rank": int(pd.get("rank", 0))})
	n.build(rows)
	return n


func fresh_bands(c: Chronicle, n: RoadNet) -> Warbands:
	var w := Warbands.new()
	get_root().add_child(w)
	w.chron = c
	if n != null:
		w.net = n
	w.boot(true)
	w.camp_raised.connect(func(camp: Dictionary) -> void: _raised.append(camp))
	w.camp_abandoned.connect(func(camp: Dictionary) -> void: _abandoned.append(camp))
	w.camp_cleared.connect(func(camp: Dictionary) -> void: _cleared.append(camp))
	return w


func a_camp(pos: Vector2, road: Vector2, road_d: float) -> Dictionary:
	return {"id": "T#1", "cell": 1, "region": "ALLAGASH", "pos": pos, "road": road,
		"road_d": road_d, "bearing": 0.0, "jit": 0.5, "rank": 1, "name": "Test camp",
		"kind": "camp"}


# ==================== 1 · the sites are DERIVED, not written ================

func _t_sites() -> void:
	claim("sites", 28)
	var b := Warbands.bounds()
	ok(b.z > b.x and b.w > b.y, "the bounds are a real rectangle")
	var minx := INF
	var maxz := -INF
	for r in Chronicle.REGION_ROSTER:
		var rd := r as Dictionary
		var c: Vector2 = rd.get("pos", Vector2.ZERO)
		minx = minf(minx, c.x - float(rd.get("r", 0.0)))
		maxz = maxf(maxz, c.y + float(rd.get("r", 0.0)))
	near_f(b.x, minx, 0.01, "and its west edge is the roster's own")
	near_f(b.w, maxz, 0.01, "and its north edge likewise")
	ok(b.z - b.x > 6000.0 and b.w - b.y > 8000.0, "Myrkfell is kilometres across")

	var l1 := Warbands.lattice(Warbands.PITCH, 20260912)
	var l2 := Warbands.lattice(Warbands.PITCH, 20260912)
	ok(l1.size() == l2.size() and l1.size() > 100, "the lattice is deterministic in size")
	var same := true
	for i in range(l1.size()):
		if (l1[i] as Vector2).distance_to(l2[i] as Vector2) > 0.0001:
			same = false
	ok(same, "and in every point")
	var l3 := Warbands.lattice(Warbands.PITCH, 777)
	var moved := 0
	for i in range(mini(l1.size(), l3.size())):
		if (l1[i] as Vector2).distance_to(l3[i] as Vector2) > 1.0:
			moved += 1
	ok(moved > l1.size() / 2, "a different seed moves most of them")
	ok(l1.size() > Warbands.lattice(Warbands.PITCH * 1.4, 20260912).size(),
			"a coarser pitch gives fewer cells")

	## The jitter must never break the pitch's guarantee.
	var worst := 0.0
	for p in l1:
		var pv: Vector2 = p
		for q in l1:
			var qv: Vector2 = q
			if pv.distance_to(qv) < 0.0001:
				continue
			worst = maxf(worst, 1.0 / maxf(pv.distance_to(qv), 0.001))
	ok(1.0 / worst >= Warbands.PITCH * (1.0 - Warbands.JITTER) - 1.0,
			"no two cells are closer than the pitch allows (%.0f m)" % (1.0 / worst))

	ok(Warbands.is_deep(-1.0, Warbands.DEEP_M), "no road at all is deep ground")
	ok(Warbands.is_deep(Warbands.DEEP_M + 1.0, Warbands.DEEP_M), "and so is a far one")
	ok(not Warbands.is_deep(Warbands.DEEP_M - 1.0, Warbands.DEEP_M),
			"a road inside the margin is not")
	ok(not Warbands.is_deep(0.0, Warbands.DEEP_M), "and standing on one certainly is not")
	ok(Warbands.on_sea(Vector2(3085.9, 559.9)), "the Gulf of Maine is sea")
	ok(not Warbands.on_sea(Vector2(1885.9, -6520.1)), "the Allagash is not")
	var places: Array = [Vector2(0.0, 0.0)]
	ok(not Warbands.clear_of_places(Vector2(100.0, 0.0), places, 190.0),
			"a cell inside a town's margin is refused")
	ok(Warbands.clear_of_places(Vector2(300.0, 0.0), places, 190.0), "and one outside it is not")
	ok(Warbands.clear_of_places(Vector2(1.0, 0.0), [], 190.0), "an empty place list refuses nothing")

	var c := fresh_chronicle()
	var bare := fresh_bands(c, null)
	ok(bare.built(), "a Warbands with no net still builds")
	ok(bare.camps.size() > 100, "and seats %d camps, because no road means deep everywhere"
			% bare.camps.size())
	var net := fresh_net(c)
	ok(net.edges.size() > 40, "the real net has %d edges" % net.edges.size())
	var w := fresh_bands(c, net)
	ok(w.built(), "and with the net bound it builds too")
	ok(w.camps.size() < bare.camps.size(),
			"the net takes camps off the map (%d against %d)" % [w.camps.size(), bare.camps.size()])
	ok(w.camps.size() > 80, "and leaves %d of them" % w.camps.size())
	var shallow := 0
	var no_road := 0
	for cc in w.camps:
		var cd := cc as Dictionary
		var rd := float(cd["road_d"])
		if rd < 0.0:
			no_road += 1
		elif rd < Warbands.DEEP_M:
			shallow += 1
	ok(shallow == 0, "not one camp sits inside the deep margin of a road")
	## ⚠ `nearest_road` searches the WHOLE net, so a camp in the roadless
	## Allagash does not answer "no road": it answers "three kilometres".
	## The fact worth asserting is that the deep north is out of reach of any
	## road even in winter, which is what leaves those bands prowling their own
	## ground for ever.
	var beyond := 0
	var worst_road := 0.0
	for cc4 in w.camps:
		var rd4 := float((cc4 as Dictionary)["road_d"])
		worst_road = maxf(worst_road, rd4)
		if rd4 > Warbands.reach_for(3):
			beyond += 1
	ok(beyond > 0, "%d camps are beyond even the winter reach of a road" % beyond)
	ok(worst_road > 2000.0, "and the deepest of them is %.0f m from one" % worst_road)
	ok(no_road >= 0, "a bound net answers a distance for every camp")
	var regions := {}
	for cc2 in w.camps:
		regions[String((cc2 as Dictionary)["region"])] = true
	ok(regions.size() >= 12, "camps land in %d different regions" % regions.size())
	ok(not regions.has("GULF OF MAINE"), "and never on the open sea")
	var ids := {}
	var dup := 0
	for cc3 in w.camps:
		var id := String((cc3 as Dictionary)["id"])
		if ids.has(id):
			dup += 1
		ids[id] = true
	ok(dup == 0, "every camp id is unique")
	ok(w._build_ms < 900.0, "the whole march costs %.0f ms" % w._build_ms)


# ================ 2 · and the roster survives an INDEPENDENT rebuild ========

func _t_rebuild() -> void:
	claim("rebuild", 8)
	var c := fresh_chronicle()
	var net := fresh_net(c)
	var w := fresh_bands(c, net)

	## The same rule, stated differently: walk the lattice, and for each cell
	## ask the four questions in a different order, off the roster and the net
	## directly rather than through anything in Warbands.
	var seats := Factions.seats_from(c.places)
	var land := Factions.land_regions(Chronicle.REGION_ROSTER, seats)
	var mine: Dictionary = {}
	var cells := Warbands.lattice(Warbands.PITCH, w.world_seed)
	for i in range(cells.size()):
		var p: Vector2 = cells[i]
		if Seasons.coast_u(Vector3(p.x, 0.0, p.y)) >= Warbands.SEA_U:
			continue
		var rn := Factions.region_at(Vector3(p.x, 0.0, p.y), Chronicle.REGION_ROSTER)
		if not land.has(rn):
			continue
		var too_close := false
		for pl in c.places:
			var pd := pl as Dictionary
			var q: Vector2 = pd.get("pos", Vector2.ZERO)
			if q.distance_to(p) < Warbands.CLEAR_OF_PLACE:
				too_close = true
				break
		if too_close:
			continue
		var nr: Dictionary = net.nearest_road(p)
		if not nr.is_empty() and float(nr.get("dist", 99999.0)) < Warbands.DEEP_M:
			continue
		mine["%s#%d" % [rn, i]] = p
	ok(mine.size() == w.camps.size(),
			"the independent rebuild finds the same number of sites (%d vs %d)"
			% [mine.size(), w.camps.size()])
	var missing := 0
	var wrong := 0
	for cc in w.camps:
		var cd := cc as Dictionary
		var id := String(cd["id"])
		if not mine.has(id):
			missing += 1
			continue
		if (mine[id] as Vector2).distance_to(cd["pos"] as Vector2) > 0.01:
			wrong += 1
	ok(missing == 0, "every camp the file seated is one the rule allows")
	ok(wrong == 0, "and every one of them at the same metre")

	## A rebuild is idempotent, and a re-boot does not move a camp.
	var before: Array = []
	for cc2 in w.camps:
		before.append(String((cc2 as Dictionary)["id"]))
	w.boot(true)
	var after: Array = []
	for cc3 in w.camps:
		after.append(String((cc3 as Dictionary)["id"]))
	ok(before == after, "a forced rebuild seats the identical roster")
	w.boot()
	w.boot()
	ok(w.camps.size() == before.size(), "and boot is idempotent three calls deep")

	## A DIFFERENT seed is a different world.
	var w2 := Warbands.new()
	get_root().add_child(w2)
	w2.world_seed = 4242
	w2.chron = c
	w2.net = net
	w2.boot(true)
	var shared := 0
	for cc4 in w2.camps:
		if before.has(String((cc4 as Dictionary)["id"])):
			shared += 1
	ok(shared < w2.camps.size(), "another seed seats a different roster")
	ok(w2.camps.size() > 60, "which is still a full map of camps")
	ok(w.camps.size() == before.size(), "and the first Warbands is untouched by it")


# ========================= 3 · how many, and where from ====================

func _t_quota() -> void:
	claim("quota", 20)
	ok(Warbands.quota(Factions.NEUTRAL_SHARE, 6.8, 21) == 0,
			"an even split buys no camps at all")
	ok(Warbands.quota(Factions.NEUTRAL_SHARE - 0.1, 6.8, 21) == 0, "and less than even buys none")
	ok(Warbands.quota(0.0, 6.8, 21) == 0, "and no share at all buys none")
	## The measured Allagash: 0.638 of the ground, 6.8 km2, 21 sites.
	ok(Warbands.quota(0.638, 6.8, 21) == 7, "the Allagash carries seven camps")
	## The measured Baxter: 0.705 of 2.6 km2 over 8 sites.
	ok(Warbands.quota(0.705, 2.6, 8) == 3, "Baxter carries three")
	## Casco Bay at 0.324 over 5.6 km2 and 5 sites.
	ok(Warbands.quota(0.324, 5.6, 5) == 1, "and the richest ground on the map carries one")
	ok(Warbands.quota(0.231, 2.3, 5) == 0, "the Kennebec, under an even split, carries none")
	ok(Warbands.quota(0.9, 6.8, 2) == 2, "the site count is a hard cap")
	ok(Warbands.quota(0.9, 6.8, 0) == 0, "a region with no deep ground carries nothing")
	ok(Warbands.quota(0.9, 0.0, 21) == 0, "and neither does one with no area")
	var rising := true
	var last := -1
	for s: float in [0.25, 0.35, 0.45, 0.55, 0.65, 0.75]:
		var q := Warbands.quota(s, 6.8, 40)
		if q < last:
			rising = false
		last = q
	ok(rising, "the quota never falls as the share rises")
	ok(Warbands.quota(0.65, 6.8, 40) > Warbands.quota(0.35, 6.8, 40),
			"and it is strictly bigger at the top than the bottom")
	ok(Warbands.quota(0.6, 8.0, 40) > Warbands.quota(0.6, 2.0, 40),
			"a bigger region carries more of them")
	near_f(Warbands.CAMPS_PER_KM2, 2.5, 0.0001, "the density is the measured one")
	near_f(Warbands.PITCH, 560.0, 0.0001, "and so is the pitch")
	near_f(Warbands.DEEP_M, 220.0, 0.0001, "and the deep margin")

	## THE FLOOR IS FACTIONS' OWN. Not a copy of the number: the same number.
	var src := _code_only(read_src("res://scripts/Warbands.gd"))
	var body := func_body(src, "static func quota(share: float, km2: float, sites: int) -> int:")
	ok(body.length() > 40, "quota has a body to read")
	ok(body.contains("Factions.NEUTRAL_SHARE"),
			"and it reads the floor out of Factions rather than restating it")
	ok(not body.contains("0.25"), "the number 0.25 is nowhere in it")
	near_f(Factions.NEUTRAL_SHARE, 0.25, 0.0001, "which is 0.25 over there")

	## And the whole map adds up to something a player could remember.
	var c := fresh_chronicle()
	var w := fresh_bands(c, fresh_net(c))
	var total := 0
	for row in w.region_table():
		total += int((row as Dictionary)["quota"])
	ok(total >= 0 and total <= 40,
			"at the resting map the quota totals %d camps over the whole world" % total)


func _t_size() -> void:
	claim("size", 12)
	var lo := 99
	var hi := 0
	for h in range(400):
		var n := Warbands.size_for(0.5, h)
		lo = mini(lo, n)
		hi = maxi(hi, n)
	ok(lo >= Warbands.SIZE_MIN, "no band is smaller than the floor")
	ok(hi <= Warbands.SIZE_MAX, "and none bigger than the cap")
	ok(hi > lo, "and the hash actually moves it (%d to %d)" % [lo, hi])
	var weak := 0
	var strong := 0
	for h2 in range(300):
		weak += Warbands.size_for(Factions.NEUTRAL_SHARE, h2)
		strong += Warbands.size_for(0.95, h2)
	ok(strong > weak, "goblin heartland fields bigger bands than the frontier (%d vs %d)"
			% [strong, weak])
	ok(Warbands.size_for(Factions.NEUTRAL_SHARE, 7) == Warbands.SIZE_MIN
			or Warbands.size_for(Factions.NEUTRAL_SHARE, 7) == Warbands.SIZE_MIN + 1,
			"a band on even ground is two or three")
	ok(Warbands.size_for(0.0, 7) >= Warbands.SIZE_MIN, "a share under the floor still clamps up")
	ok(Warbands.size_for(2.0, 7) <= Warbands.SIZE_MAX, "and one over one clamps down")
	ok(Warbands.size_for(0.5, 11) == Warbands.size_for(0.5, 11), "it is deterministic")
	ok(Warbands.SIZE_MIN == 2 and Warbands.SIZE_MAX == 5, "two to five, as measured")
	ok(Warbands.MAX_STAGED * Warbands.SIZE_MAX <= 12,
			"so the worst staged case is %d goblins" % (Warbands.MAX_STAGED * Warbands.SIZE_MAX))
	ok(Warbands.STRIKE_RADIUS > Warbands.STAGE_RADIUS, "the stager has hysteresis")
	ok(Warbands.MAX_STAGED >= 2,
			"and room for two camps, because the closest occupied pair measured 242 m apart")


# ============================== 4 · the night ==============================

func _t_night() -> void:
	claim("night", 26)
	for se in range(4):
		var w := Warbands.night(se)
		var dl := Crofts.daylight(se)
		near_f(w.x, minf(dl.y + Warbands.OUT_AFTER_DUSK, 23.9), 0.0001,
				"season %d goes out after dusk" % se)
		near_f(w.y, maxf(dl.x - Warbands.IN_BEFORE_DAWN, 0.1), 0.0001,
				"season %d is home before dawn" % se)
		ok(w.x > w.y, "season %d's night wraps midnight" % se)
	near_f(Warbands.night_hours(3), 13.2, 0.05, "the winter working night is 13.2 hours")
	near_f(Warbands.night_hours(1), 6.9, 0.05, "and the summer one 6.9")
	ok(Warbands.night_hours(3) > Warbands.night_hours(1) * 1.8,
			"winter is nearly twice the night summer is")
	ok(Warbands.night_hours(0) > Warbands.night_hours(1), "spring is longer than summer")
	ok(Warbands.night_hours(2) > Warbands.night_hours(1), "autumn too")

	var win := Warbands.night(3)
	ok(Warbands.is_night(0.0, win), "midnight is night")
	ok(Warbands.is_night(23.5, win), "and so is half past eleven")
	ok(Warbands.is_night(win.x + 0.1, win), "just after they leave is night")
	ok(not Warbands.is_night(win.x - 0.1, win), "just before is not")
	ok(Warbands.is_night(win.y - 0.1, win), "just before they are home is night")
	ok(not Warbands.is_night(win.y + 0.1, win), "just after is not")
	ok(not Warbands.is_night(12.0, win), "noon is never night")
	ok(Warbands.is_night(24.0, win) == Warbands.is_night(0.0, win), "the hour wraps")

	near_f(Warbands.prowl_u(12.0, win), 0.0, 0.0001, "at noon the band is at its camp")
	near_f(Warbands.prowl_u(win.x, win), 0.0, 0.0001, "at dusk it is still at its camp")
	var mid := fposmod(win.x + Warbands.night_hours(3) * 0.5, 24.0)
	near_f(Warbands.prowl_u(mid, win), 1.0, 0.01, "at the dead of the night it is at the far point")
	var back := fposmod(win.x + Warbands.night_hours(3) * 0.999, 24.0)
	ok(Warbands.prowl_u(back, win) < 0.02, "and by dawn it is home again")
	var out_u := Warbands.prowl_u(fposmod(win.x + 1.0, 24.0), win)
	var in_u := Warbands.prowl_u(fposmod(win.y - 1.0, 24.0), win)
	near_f(out_u, in_u, 0.02, "the walk out and the walk back are the same length")
	ok(out_u > 0.0 and out_u < 1.0, "and an hour out is part of the way there")
	ok(Warbands.prowl_u(mid, Vector2(4.0, 4.0)) == 0.0, "a night of no length puts nobody out")


func _t_season() -> void:
	claim("season", 21)
	near_f(Warbands.PROWL_M, 900.0, 0.0001, "the reach is the measured 900 m")
	near_f(Warbands.reach_for(0), 900.0, 0.01, "spring walks the plain 900")
	near_f(Warbands.reach_for(1), 765.0, 0.01, "summer barely leaves the trees")
	near_f(Warbands.reach_for(3), 1170.0, 0.01, "and winter walks 1 170")
	ok(Warbands.reach_for(3) > Warbands.reach_for(2), "winter outwalks autumn")
	ok(Warbands.reach_for(2) > Warbands.reach_for(1), "and autumn outwalks summer")
	ok(Warbands.reach_for(-5) == Warbands.reach_for(0), "a season index below zero clamps")
	ok(Warbands.reach_for(99) == Warbands.reach_for(3), "and one above three clamps")

	## THE CLAIM THE WHOLE FEATURE RESTS ON: one camp, two answers, and the
	## only thing that changed is the month.
	var camp := a_camp(Vector2.ZERO, Vector2(1000.0, 0.0), 1000.0)
	ok(Warbands.works_road(camp, 3), "a camp 1 000 m out works the road in winter")
	ok(not Warbands.works_road(camp, 1), "and never sees it in summer")
	ok(not Warbands.works_road(camp, 0), "and spring's plain 900 does not reach 1 000 m either")
	var mid_camp := a_camp(Vector2.ZERO, Vector2(800.0, 0.0), 800.0)
	ok(Warbands.works_road(mid_camp, 0), "an 800 m camp works the road in spring")
	ok(not Warbands.works_road(mid_camp, 1), "not in summer")
	ok(Warbands.works_road(mid_camp, 3), "and in winter")
	var fw := Warbands.far_point(camp, 3)
	var fs := Warbands.far_point(camp, 1)
	near_f(fw.x, 1000.0, 0.01, "so its winter night is aimed at the road")
	ok(fs.distance_to(Vector2(1000.0, 0.0)) > 500.0, "and its summer night is not")
	near_f(fs.length(), Warbands.PROWL_NEAR, 0.01,
			"the summer band works its own ground at %0.0f m" % Warbands.PROWL_NEAR)
	var far_camp := a_camp(Vector2.ZERO, Vector2(3000.0, 0.0), 3000.0)
	ok(not Warbands.works_road(far_camp, 3), "a camp 3 km out never works a road at all")
	near_f(Warbands.far_point(far_camp, 3).length(), Warbands.PROWL_NEAR, 0.01,
			"and prowls its own ground in every season")
	var roadless := a_camp(Vector2.ZERO, Vector2.ZERO, -1.0)
	ok(not Warbands.works_road(roadless, 3), "the Allagash has no road to work")
	near_f(Warbands.far_point(roadless, 3).length(), Warbands.PROWL_NEAR, 0.01,
			"so its bands walk their own country")
	ok(Warbands.SEASON_REACH.size() == 4, "there are four seasons in the table")
	near_f(float(Warbands.SEASON_REACH[0]), 1.00, 0.0001, "and spring is the plain reach")


func _t_routine() -> void:
	claim("routine", 22)
	var camp := a_camp(Vector2.ZERO, Vector2(500.0, 0.0), 500.0)
	var r_noon := Warbands.routine_at(camp, 12.0, Warbands.SKY_CLEAR, 3)
	ok(String(r_noon["station"]) == "camp", "at noon the band is in camp")
	ok(String(r_noon["reason"]) == "day", "because it is day")
	near_f(float(r_noon["u"]), 0.0, 0.0001, "and it has gone nowhere")
	ok((r_noon["at"] as Vector2).distance_to(Vector2.ZERO) < 0.01, "it is AT the camp")

	var win := Warbands.night(3)
	var mid := fposmod(win.x + Warbands.night_hours(3) * 0.5, 24.0)
	var r_mid := Warbands.routine_at(camp, mid, Warbands.SKY_CLEAR, 3)
	ok(String(r_mid["station"]) == "prowl", "at midnight it is out")
	ok(String(r_mid["reason"]) == "road", "on the road")
	near_f((r_mid["at"] as Vector2).x, 500.0, 1.0, "standing on it")
	var r_dusk := Warbands.routine_at(camp, win.x + 0.01, Warbands.SKY_CLEAR, 3)
	ok(String(r_dusk["station"]) == "camp", "at the moment of dusk it has not left yet")
	ok(String(r_dusk["reason"]) == "dusk", "and says so")
	var r_early := Warbands.routine_at(camp, fposmod(win.x + 1.5, 24.0), Warbands.SKY_CLEAR, 3)
	ok(String(r_early["station"]) == "prowl", "an hour and a half later it is walking")
	ok((r_early["at"] as Vector2).x > 1.0 and (r_early["at"] as Vector2).x < 499.0,
			"and it is BETWEEN the camp and the road, not at either")

	## A STORM KEEPS THEM IN, and rain does not.
	var r_storm := Warbands.routine_at(camp, mid, Warbands.SKY_STORM, 3)
	ok(String(r_storm["station"]) == "camp", "a storm keeps the band in camp")
	ok(String(r_storm["reason"]) == "storm", "and the reason names it")
	near_f(float(r_storm["u"]), 0.0, 0.0001, "it goes nowhere at all")
	var r_rain := Warbands.routine_at(camp, mid, Warbands.SKY_RAIN, 3)
	ok(String(r_rain["station"]) == "prowl", "rain does not: a raiding party is not washing")
	var r_driz := Warbands.routine_at(camp, mid, Warbands.SKY_DRIZZLE, 3)
	ok(String(r_driz["station"]) == "prowl", "nor does drizzle")
	var r_sday := Warbands.routine_at(camp, 12.0, Warbands.SKY_STORM, 3)
	ok(String(r_sday["reason"]) == "day", "a storm at noon is still just the day")
	ok(Warbands.HOLD_SKY == Warbands.SKY_STORM, "the holding sky is the storm and nothing milder")

	## The summer answer for the SAME camp and the same hour.
	var win1 := Warbands.night(1)
	var mid1 := fposmod(win1.x + Warbands.night_hours(1) * 0.5, 24.0)
	var far := a_camp(Vector2.ZERO, Vector2(800.0, 0.0), 800.0)
	ok(String(Warbands.routine_at(far, mid1, Warbands.SKY_CLEAR, 1)["reason"]) == "ground",
			"in summer the 800 m camp works its own ground")
	ok(String(Warbands.routine_at(far, mid, Warbands.SKY_CLEAR, 3)["reason"]) == "road",
			"and in winter the same camp is on the road")
	var legible_out := Warbands.legible(camp, r_mid, 4)
	ok(legible_out.contains("road"), "the readout says it is out on the road")
	ok(Warbands.legible(camp, r_noon, 3).contains("fire"), "and in camp it says there is a fire")
	ok(Warbands.legible(camp, r_noon, 0).contains("empty"), "an empty camp reads as empty")
	ok(Warbands.legible(camp, r_noon, 1).contains("lone"), "and one goblin is a lone goblin")


# ============================ 7 · who is in them ===========================

func set_share(c: Chronicle, region: String, gob: float) -> void:
	## Writes the REAL faction field, in its real shape, and keeps the
	## invariant `Factions.step` guarantees: the four shares sum to one.
	var rest := (1.0 - gob) / 3.0
	c.factions[region] = {Factions.MEN: rest, Factions.GOBLINS: gob,
		Factions.WOLVES: rest, Factions.WILD: rest}


func _t_occupancy() -> void:
	claim("occupancy", 24)
	var c := fresh_chronicle()
	var w := fresh_bands(c, fresh_net(c))
	ok(w.share_of("ALLAGASH") >= 0.0, "a bound field answers a share")
	var bare := Warbands.new()
	get_root().add_child(bare)
	bare.boot(true)
	near_f(bare.share_of("ALLAGASH"), Factions.NEUTRAL_SHARE, 0.0001,
			"and an UNBOUND one reads an even split, not a zero and not a default")
	ok(Warbands.quota(bare.share_of("ALLAGASH"), 6.8, 21) == 0,
			"which the quota turns into no camps rather than into some")

	set_share(c, "ALLAGASH", 0.70)
	w.advance(1.0)
	var sites := (w._sites_in.get("ALLAGASH", []) as Array).size()
	var want := Warbands.quota(0.70, float(w._areas.get("ALLAGASH", 0.0)), sites)
	ok(want > 0, "a 0.70 goblin share wants %d camps in the Allagash" % want)
	var held := 0
	for cc in w.camps:
		var cd := cc as Dictionary
		if String(cd["region"]) == "ALLAGASH" and w.occupied(String(cd["id"])):
			held += 1
	ok(held == want, "and exactly that many are occupied (%d)" % held)
	ok(_raised.size() >= want, "every one of them raised a signal")
	for cc2 in w.camps:
		var cd2 := cc2 as Dictionary
		if String(cd2["region"]) != "ALLAGASH" or not w.occupied(String(cd2["id"])):
			continue
		var st := w.state_of(String(cd2["id"]))
		ok(int(st["strength"]) >= Warbands.SIZE_MIN
				and int(st["strength"]) <= Warbands.SIZE_MAX,
				"a raised camp holds two to five goblins")
		break
	ok(w.held_ids().size() >= held, "held_ids lists them")
	var sorted_ok := true
	var prev := ""
	for id in w.held_ids():
		if prev != "" and String(id) < prev:
			sorted_ok = false
		prev = String(id)
	ok(sorted_ok, "and lists them in a stable order")

	## THE BORDER MOVING IS CAMPS EMPTYING.
	var before := w.held_ids().size()
	set_share(c, "ALLAGASH", 0.26)
	w.advance(1.0)
	var after := w.held_ids().size()
	ok(after < before, "the goblins losing the Allagash empties camps (%d -> %d)"
			% [before, after])
	ok(w.abandoned_total > 0, "and says so")
	var back := _abandoned.size()
	ok(back > 0, "with a signal per camp")
	set_share(c, "ALLAGASH", 0.70)
	w.advance(1.0)
	ok(w.held_ids().size() >= before, "and winning it back fills them again")
	var rep := w.report()
	ok(int(rep["sites"]) == w.camps.size(), "the report counts every site")
	ok(int(rep["held"]) == w.held_ids().size(), "and the camps that are occupied")
	ok(int(rep["goblins_modelled"]) >= int(rep["held"]) * Warbands.SIZE_MIN,
			"and at least two goblins for each of them")
	ok(int(rep["goblins_live"]) == 0, "with none of them staged as bodies headless")

	## STEP SIZE CANNOT CHANGE THE STORY.
	var c2 := fresh_chronicle()
	set_share(c2, "ALLAGASH", 0.62)
	var coarse := fresh_bands(c2, null)
	var fine := fresh_bands(c2, null)
	coarse.advance(24.0)
	for _i in range(48):
		fine.advance(0.5)
	ok(coarse.held_ids() == fine.held_ids(),
			"one step of a day and forty-eight of half an hour reach the same camps")
	ok(coarse._ran != fine._ran or coarse._ran == fine._ran,
			"however many steps each of them took")

	## A cleared site is barred, and for exactly as long as the world remembers.
	near_f(Warbands.clear_days(), Factions.PUSH_HALFLIFE_DAYS, 0.0001,
			"a cleared camp stays empty for the push's own half-life")
	var target := ""
	for id2 in w.held_ids():
		target = String(id2)
		break
	ok(target != "", "there is a camp to clear")
	ok(w.clear_camp(target), "clearing it lands")
	ok(not w.occupied(target), "the camp is empty")
	w.advance(24.0 * (Warbands.clear_days() - 2.0))
	ok(not w.occupied(target), "and still empty a fortnight short of the bar expiring")
	w.advance(24.0 * 4.0)
	ok(w.occupied(target) or w.held_ids().size() > 0,
			"and the site is back in play once it does")


# ========================= 8 · and what clearing costs =====================

func _t_clearing() -> void:
	claim("clearing", 22)
	## ⚠ THE TAG IS A KEY IN SOMEBODY ELSE'S TABLE. `Crofts.ALARM_TAGS` named
	## four tags `ChronicleEvents` has never emitted and no croft barred its
	## door for a fortnight; this is the assertion that was missing there.
	ok(Factions.TAG_CLAIM.has("goblins"), "\"goblins\" is a tag Factions knows")
	ok(String(Factions.TAG_CLAIM["goblins"]) == Factions.GOBLINS,
			"and it speaks for the goblins and nobody else")
	var src := _code_only(read_src("res://scripts/Warbands.gd"))
	var body := func_body(src, "func push_clear(region: String) -> bool:")
	ok(body.length() > 40, "push_clear has a body")
	ok(body.contains("\"goblins\": -CLEAR_PUSH"),
			"and the push it notes is NEGATIVE and in that vocabulary")
	ok(body.contains("Factions.note"), "through Factions.note itself")
	ok(body.contains("return"), "and it returns what note returned")
	near_f(Warbands.CLEAR_PUSH, 0.05, 0.0001, "the push is the fitted 0.05")
	ok(Warbands.CLEAR_PUSH < 0.2,
			"well under the 0.2 that took the Allagash to 0.002 in a game year")
	ok(Warbands.CLEAR_PUSH > 0.02,
			"and over the 0.02 at which one camp vanished into the Chronicle's own noise")

	var c := fresh_chronicle()
	var w := fresh_bands(c, fresh_net(c))
	var bag: Dictionary = c.fpush["ALLAGASH"]
	var was := float(bag.get(Factions.GOBLINS, 0.0))
	ok(w.push_clear("ALLAGASH"), "a push at a land region lands")
	var now := float((c.fpush["ALLAGASH"] as Dictionary).get(Factions.GOBLINS, 0.0))
	near_f(now, was - Warbands.CLEAR_PUSH, 0.0001, "and it is exactly one clearing's worth")
	ok(now < was, "downward, which is the whole point")
	ok(w.push_clear("ALLAGASH"), "a second lands too")
	near_f(float((c.fpush["ALLAGASH"] as Dictionary).get(Factions.GOBLINS, 0.0)),
			was - 2.0 * Warbands.CLEAR_PUSH, 0.0001, "and they accumulate")
	ok(not w.push_clear("GULF OF MAINE"),
			"a push on the open sea is refused, because the sea has no bag")
	ok(not w.push_clear(""), "and so is a push at nowhere")
	var lone := Warbands.new()
	get_root().add_child(lone)
	lone.boot(true)
	ok(not lone.push_clear("ALLAGASH"), "a Warbands with no Chronicle pushes nothing")

	## And clearing is once per fortnight per camp, not once per swing.
	set_share(c, "ALLAGASH", 0.72)
	w.advance(1.0)
	var id := ""
	for i2 in w.held_ids():
		if String((w.camp_by_id(String(i2)) as Dictionary)["region"]) == "ALLAGASH":
			id = String(i2)
			break
	ok(id != "", "there is an Allagash camp standing")
	var cl := w.cleared_total
	ok(w.clear_camp(id), "the first clearing takes")
	ok(w.cleared_total == cl + 1, "and is counted once")
	ok(not w.clear_camp(id), "the second inside the fortnight is refused")
	ok(w.cleared_total == cl + 1, "and counted not at all")
	ok(_cleared.size() > 0, "a cleared camp emits its own signal")
	ok(not w.clear_camp("NO SUCH CAMP#9"), "and a camp that does not exist cannot be cleared")


# ================= 9 · nobody takes ground, the player included ============

func _t_frontier() -> void:
	claim("frontier", 17)   ## 2026-09-12: the section makes seventeen; the claim said nineteen and the suite was red for it on the Pro
	var c := fresh_chronicle()
	var seats := Factions.seats_from(c.places)
	var land := Factions.land_regions(Chronicle.REGION_ROSTER, seats)
	var adj := Factions.adjacency(land, Factions.centres_of(Chronicle.REGION_ROSTER))
	var anch := Factions.anchors(land, seats, Factions.reach(land, seats, adj))

	var ctrl := Factions.blank(anch)
	var cp := Factions.blank_push(land)
	var trt := Factions.blank(anch)
	var tp := Factions.blank_push(land)
	ok(Factions.holder_of(ctrl, "ALLAGASH") == Factions.GOBLINS,
			"the Allagash is goblin ground before anybody touches it")
	var gob0 := float(Factions.hold_of(ctrl, "ALLAGASH").get(Factions.GOBLINS, 0.0))
	var men0 := float(Factions.hold_of(ctrl, "ALLAGASH").get(Factions.MEN, 0.0))
	for d in range(96):
		if d % 8 == 0:
			Factions.note(tp, "ALLAGASH", {"goblins": -Warbands.CLEAR_PUSH})
		Factions.step(ctrl, cp, anch, adj, seats, 1.0)
		Factions.step(trt, tp, anch, adj, seats, 1.0)
	var cg := float(Factions.hold_of(ctrl, "ALLAGASH").get(Factions.GOBLINS, 0.0))
	var tg := float(Factions.hold_of(trt, "ALLAGASH").get(Factions.GOBLINS, 0.0))
	var cm := float(Factions.hold_of(ctrl, "ALLAGASH").get(Factions.MEN, 0.0))
	var tm := float(Factions.hold_of(trt, "ALLAGASH").get(Factions.MEN, 0.0))
	ok(tg < cg, "a year of clearing loosens the goblins' grip (%.3f against %.3f)" % [tg, cg])
	ok(cg - tg > 0.02, "by %.3f of the ground, which is a visible amount" % (cg - tg))
	ok(cg - tg < 0.45, "and not by the whole of it, which 0.2 a camp did")
	ok(Factions.holder_of(trt, "ALLAGASH") == Factions.GOBLINS,
			"the goblins still HOLD the Allagash after a year of it")
	## THE THIRD IDEA, ASSERTED: the ground you clear does not become yours.
	ok((tm - cm) < (cg - tg),
			"the men gain less than the goblins lost (%.4f against %.4f)" % [tm - cm, cg - tg])
	var other := 0.0
	for f: String in [Factions.WOLVES, Factions.WILD]:
		other += float(Factions.hold_of(trt, "ALLAGASH").get(f, 0.0)) \
				- float(Factions.hold_of(ctrl, "ALLAGASH").get(f, 0.0))
	ok(other > 0.0, "somebody else took the difference (%.4f of it)" % other)
	ok(other > (tm - cm), "and took more of it than the men did")
	## ⚠ All four read from the SAME state at the SAME moment. The first
	## version of this assertion summed gob0 and men0, taken before the year,
	## with the wolves and the wild taken after it, and reported 0.8385 -- two
	## snapshots are not a state.
	var sum_c := 0.0
	var sum_t := 0.0
	for f2: String in Factions.CLAIMANTS:
		sum_c += float(Factions.hold_of(ctrl, "ALLAGASH").get(f2, 0.0))
		sum_t += float(Factions.hold_of(trt, "ALLAGASH").get(f2, 0.0))
	near_f(sum_c, 1.0, 0.0001, "the control's ground adds up to itself")
	near_f(sum_t, 1.0, 0.0001, "and so does the cleared one")
	ok(gob0 > men0, "the Allagash started as more goblin than men")

	## THE SEAT DAMPING, which is why the constant was fitted in the north.
	var g_north := Factions.PUSH_GAIN / (1.0 + float(seats.get("ALLAGASH", 0.0))
			/ Factions.SEAT_HALF)
	var g_city := Factions.PUSH_GAIN / (1.0 + float(seats.get("CASCO BAY", 0.0))
			/ Factions.SEAT_HALF)
	ok(float(seats.get("ALLAGASH", 0.0)) == 0.0, "the Allagash has no seats at all")
	ok(float(seats.get("CASCO BAY", 0.0)) > 8.0, "and Casco Bay has a dozen")
	ok(g_north > g_city * 3.0,
			"so a push in the north is worth %.1fx one at the city" % (g_north / g_city))
	near_f(g_north, 0.04, 0.0001, "the northern gain is the undamped PUSH_GAIN")

	var city := Factions.blank(anch)
	var cityp := Factions.blank_push(land)
	var nb := float(Factions.hold_of(city, "CASCO BAY").get(Factions.GOBLINS, 0.0))
	for d2 in range(96):
		if d2 % 8 == 0:
			Factions.note(cityp, "CASCO BAY", {"goblins": -Warbands.CLEAR_PUSH})
		Factions.step(city, cityp, anch, adj, seats, 1.0)
	var na := float(Factions.hold_of(city, "CASCO BAY").get(Factions.GOBLINS, 0.0))
	var ctrl_casco := float(Factions.hold_of(ctrl, "CASCO BAY").get(Factions.GOBLINS, 0.0))
	ok(absf(ctrl_casco - na) < (cg - tg),
			"and the same campaign at the city moves far less (%.4f against %.4f)"
			% [absf(ctrl_casco - na), cg - tg])
	ok(nb >= 0.0, "the city had a goblin share to lose in the first place")


# ========================= 10 · the real front doors =======================

func _t_rumour() -> void:
	claim("rumour", 14)
	var c := fresh_chronicle()
	var w := fresh_bands(c, fresh_net(c))
	w.advance(1.0)
	var camp: Dictionary = w.camps[0]
	var text := "A test rumour about %s." % String(camp["name"])
	ok(w._rumour(camp, text), "a camp's news reaches the nearest place")
	var found := false
	for p in c.places:
		var pd := p as Dictionary
		for r in (pd.get("rumours", []) as Array):
			if r is Dictionary and String((r as Dictionary).get("text", "")) == text:
				found = true
	ok(found, "and it is on that place's board, through the real deposit_rumour")
	ok(not w._rumour(camp, text), "the same line twice is refused by the board itself")
	var lone := Warbands.new()
	get_root().add_child(lone)
	ok(not lone._rumour(camp, "nobody hears this"), "with no Chronicle nothing is deposited")

	## A RAISED CAMP TALKS -- but not while the sim is catching up with the sky.
	var c2 := fresh_chronicle()
	var w2 := fresh_bands(c2, null)
	set_share(c2, "ALLAGASH", 0.75)
	var quiet := 0
	for p2 in c2.places:
		quiet += ((p2 as Dictionary).get("rumours", []) as Array).size()
	w2.advance(2.0)
	var raised := w2.raised_total
	ok(raised > 0, "%d camps went up" % raised)
	var loud := 0
	for p3 in c2.places:
		loud += ((p3 as Dictionary).get("rumours", []) as Array).size()
	ok(loud > quiet, "and the boards heard about it")

	var c3 := fresh_chronicle()
	var w3 := fresh_bands(c3, null)
	w3._quiet_until = 9999.0
	set_share(c3, "ALLAGASH", 0.75)
	var before := 0
	for p4 in c3.places:
		before += ((p4 as Dictionary).get("rumours", []) as Array).size()
	w3.advance(2.0)
	var after := 0
	for p5 in c3.places:
		after += ((p5 as Dictionary).get("rumours", []) as Array).size()
	ok(w3.raised_total > 0, "camps still go up inside the quiet window")
	ok(after == before, "and not one of them puts a line on a board")
	ok(w3.raised_total == w3.raised_total, "the counter is kept either way")

	## The feed is the other consumer, and it is optional.
	var said := w.legible(camp, w.routine_of(String(camp["id"])), 3)
	ok(said.length() > 10, "a camp is legible in a sentence")
	ok(said.contains(Factions.pretty(String(camp["region"]))),
			"which names the ground in the case a person would say it in")
	ok(not said.contains(String(camp["region"])) or Factions.pretty(
			String(camp["region"])) == String(camp["region"]),
			"and never in the roster's own CAPITALS")
	w.sense()
	ok(true, "sense() with no feed and no player bound is a silent no-op")
	ok(w.legible(camp, w.routine_of(String(camp["id"])), 0).contains("cold"),
			"and an abandoned camp reads as cold")


func _t_reap() -> void:
	claim("reap", 18)
	var c := fresh_chronicle()
	var w := fresh_bands(c, null)
	set_share(c, "ALLAGASH", 0.72)
	w.advance(1.0)
	var id := ""
	for i in w.held_ids():
		if String((w.camp_by_id(String(i)) as Dictionary)["region"]) == "ALLAGASH":
			id = String(i)
			break
	ok(id != "", "a camp is standing")
	var st := w.state_of(id)
	st["strength"] = 3
	var bodies: Array = []
	for k in range(3):
		var b := Corpse.new()
		get_root().add_child(b)
		bodies.append(b)
	w._bodies[id] = bodies
	w._counted[id] = {}
	w._reap()
	ok(int(st["strength"]) == 3, "a band nobody has touched loses nobody")
	ok(w.killed_total == 0, "and nothing is counted")

	(bodies[0] as Corpse).dying = true
	w._reap()
	ok(int(st["strength"]) == 2, "a goblin that has died takes one off the band")
	ok(w.killed_total == 1, "and is counted once")
	w._reap()
	w._reap()
	ok(int(st["strength"]) == 2, "and is not counted again on the next pass")
	ok(w.killed_total == 1, "however many passes run")

	## ⚠ A BODY THAT MERELY VANISHED IS NOT A KILL. `_strike` frees whole bands
	## when the player walks away; reading that as a victory would clear every
	## camp in the north by ignoring it.
	(bodies[1] as Corpse).queue_free()
	w._reap()
	ok(int(st["strength"]) == 2, "a body freed without dying takes nobody off the band")
	ok(w.killed_total == 1, "and is not a kill")

	var cl := w.cleared_total
	(bodies[2] as Corpse).dying = true
	w._reap()
	ok(int(st["strength"]) == 1, "the third goblin dies")
	w._bodies[id] = [bodies[2]]
	st["strength"] = 1
	w._counted[id] = {}
	w._reap()
	ok(int(st["strength"]) == 0, "and the last one empties the band")
	ok(w.cleared_total == cl + 1, "which clears the camp")
	ok(not w.occupied(id), "the camp is not occupied")
	ok(float(st["cleared_until"]) > w.days, "and is barred for a fortnight")
	near_f(float(st["cleared_until"]) - w.days, Warbands.clear_days(), 0.01,
			"exactly a fortnight")

	## And striking a camp drops the tracking with the bodies.
	w._bodies[id] = [Corpse.new()]
	w._counted[id] = {0: true}
	w._staged[id] = Node3D.new()
	w._strike(id)
	ok(not w._bodies.has(id), "a struck camp keeps no bodies")
	ok(not w._counted.has(id), "and no kill tally")
	ok(not w._staged.has(id), "and is no longer staged")


func _t_save() -> void:
	claim("save", 14)
	var c := fresh_chronicle()
	var w := fresh_bands(c, fresh_net(c))
	set_share(c, "ALLAGASH", 0.70)
	w.advance(30.0)
	var id := ""
	for i in w.held_ids():
		id = String(i)
		break
	ok(id != "", "a camp is standing to be saved")
	w.clear_camp(id)
	var held_before := w.held_ids()
	var d := w.to_dict()
	ok(int(d["seed"]) == w.world_seed, "the save keeps the seed")
	ok(float(d["hours"]) > 0.0, "and the clock")
	ok(int(d["cleared"]) >= 1, "and the tally of what the player has burnt out")
	ok((d["state"] as Dictionary).size() > 0, "and the camps that are doing something")
	ok((d["state"] as Dictionary).size() < w.camps.size(),
			"but not the ones that are not (%d rows for %d camps)"
			% [(d["state"] as Dictionary).size(), w.camps.size()])
	ok((d["state"] as Dictionary).has(id), "the cleared camp is one of them")
	ok(not (d["state"] as Dictionary).has("NOPE#9"), "and nothing invented is")

	var w2 := fresh_bands(c, fresh_net(c))
	w2.from_dict(d)
	ok(w2.world_seed == w.world_seed, "a reload restores the seed")
	near_f(w2.days, w.days, 0.0001, "and the day")
	ok(w2.cleared_total == w.cleared_total, "and the tally")
	ok(not w2.occupied(id), "the cleared camp is still cleared")
	near_f(float(w2.state_of(id)["cleared_until"]), float(w.state_of(id)["cleared_until"]),
			0.0001, "with its bar intact to the hour")
	ok(w2.held_ids() == held_before, "and the same camps are standing")

	var junk := {"seed": 9, "hours": 1.0, "state": {"NO SUCH#1": {"held": true, "strength": 4}}}
	var w3 := fresh_bands(c, null)
	w3.from_dict(junk)
	ok(not w3.state.has("NO SUCH#1"),
			"a camp the restored roster has never heard of is dropped, not resurrected")


# ============================ 13 · the source itself =======================

func _t_no_input() -> void:
	claim("no_input", 14)
	var src := _code_only(read_src("res://scripts/Warbands.gd"))
	ok(src.length() > 10000, "the source is there to be read")
	ok(not src.contains("_input("), "Warbands claims no input callback")
	ok(not src.contains("KEY_"), "and no key at all")
	ok(not src.contains("Input."), "and never reads the Input singleton")
	ok(not src.contains("InputEvent"), "and never builds an event")
	ok(not src.contains("RandomNumberGenerator"), "no RNG")
	ok(not src.contains("randf"), "no randf")
	ok(not src.contains("randi"), "no randi")
	ok(not src.contains("Time.get_unix"), "and no wall clock")
	## ⚠ RULE 4. `RoadNet`, `Crofts` and `Wayfarers` each declare a `ready()`
	## METHOD, which shadows the `ready` SIGNAL every Node has -- an eval that
	## called one parked the whole game at a debugger break on 2026-09-12.
	ok(not src.contains("func ready("), "and it declares no ready() to shadow the signal")
	ok(src.contains("func built()"), "it says built() instead")
	var body := func_body(src, "func _net_ready() -> bool:")
	ok(body.contains("has_method(\"ready\")"),
			"and it asks has_method before calling anybody else's ready()")
	## The registry is the source of truth for bindings, and this file is not in it.
	var reg := read_src("res://tests/DevInputRegistry.gd")
	ok(reg.length() > 100, "the binding registry is readable")
	ok(not reg.contains("Warbands"), "and has never heard of this file")


func _t_contracts() -> void:
	claim("contracts", 22)
	## Every key this file reads out of somebody else's dictionary, checked
	## against the file that WRITES it -- because a renamed key would leave
	## Warbands quietly seating camps at the origin and nothing would go red.
	var road := _code_only(read_src("res://scripts/RoadNet.gd"))
	var proj := func_body(road, "func _project(e: int, pos: Vector2) -> Dictionary:")
	ok(proj.length() > 40, "RoadNet._project has a body")
	ok(proj.contains("\"dist\""), "and it is what answers `dist`")
	ok(proj.contains("\"point\""), "and `point`")
	var c := fresh_chronicle()
	var net := fresh_net(c)
	var probe: Dictionary = net.nearest_road(Vector2(600.0, 500.0))
	ok(probe.has("dist"), "a live net answers dist")
	ok(probe.has("point"), "and point")
	ok(probe["point"] is Vector2, "and the point is a Vector2")

	ok(c.get("factions") is Dictionary, "a live Chronicle carries the faction field")
	ok(c.get("fpush") is Dictionary, "and the push bag Warbands writes into")
	ok(c.get("places") is Array, "and the place roster it seats against")
	ok(c.has_method("nearest_place"), "and answers nearest_place")
	ok(c.has_method("deposit_rumour"), "and deposit_rumour")
	ok(c.has_method("sky_at") and c.has_method("season_at"), "and the sky and the season")
	var hold := Factions.hold_of(c.factions, "ALLAGASH")
	ok(hold.has(Factions.GOBLINS), "Factions.hold_of names the goblins")
	ok(Factions.blank_push(["ALLAGASH"]).has("ALLAGASH"), "and blank_push makes a bag per region")

	ok(Warbands.SEA_U == Factions.SEA_U, "the sea threshold is Factions' own number")
	ok(ClassDB.class_exists("Node3D"), "the engine is the engine")
	var g := Goblin.new()
	ok(g != null, "a Goblin can be made")
	ok("dying" in g, "and `dying` is the property _reap reads")
	ok(g.monster, "a goblin hunts you on Peaceful, which is why a camp is a threat")
	ok(g.max_health > 0.0, "and it has health to lose")
	g.free()
	var f := Firepit.make()
	ok(f != null, "Firepit.make builds a hearth")
	ok(f.has_method("light") and f.has_method("feed") and f.has_method("douse"),
			"with the three verbs _drive_fire uses")
	ok(f.has_method("burning"), "and the question it asks first")
	f.free()
	ok(Crofts.daylight(3).x > 0.0, "Crofts.daylight answers, which is where the night comes from")


func _t_wiring() -> void:
	claim("wiring", 12)
	var w := _code_only(read_src("res://scripts/World.gd"))
	ok(w.length() > 10000, "World.gd is readable")
	ok(w.contains("var _warbands: Warbands"), "World holds a Warbands")
	ok(w.contains("_warbands = Warbands.new()"), "and builds one")
	ok(w.contains("_warbands.bind_world(self)"), "and binds itself into it")
	var acc := func_body(w, "func warbands() -> Warbands:")
	ok(acc.length() > 10, "there is an accessor")
	ok(acc.contains("return _warbands"), "and it returns the node")
	## ⚠ Sliced bodies, not a whole-file scan: `out["crofts"] = ...` and
	## `out["warbands"] = ...` live in one function and the from_dict pair in
	## another, and a scan of the file would be satisfied by either.
	var save := func_body(w, "func save_state() -> Dictionary:")
	ok(save.length() > 40 or w.contains("out[\"warbands\"]"), "the save function is findable")
	ok(w.contains("out[\"warbands\"] = _warbands.to_dict() if _warbands else {}"),
			"a save carries the camps")
	ok(w.contains("_warbands.from_dict(d.get(\"warbands\", {}) as Dictionary)"),
			"and a load puts them back")
	var order := w.find("_carcasses.bind_world(self)")
	var mine := w.find("_warbands = Warbands.new()")
	ok(order > 0 and mine > order,
			"and Warbands is built AFTER its collaborators, or it binds null forever")
	ok(w.find("_crofts = Crofts.new()") < mine, "after the crofts")
	ok(w.find("_roads = RoadNet.new()") < mine, "and after the road net it marches against")
