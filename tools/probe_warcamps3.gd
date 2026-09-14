extends SceneTree
## tools/probe_warcamps3.gd -- pass four. Pass three's clear-push measurement
## was a DEGENERATE FIXTURE: it ran `step()` against an EMPTY push bag with no
## Chronicle attached, so pushes of 0.15, 0.30 and 0.60 all produced the
## bit-identical answer 0.380 -> 0.001 -- the anchors relaxing, not the push.
## Nothing was measured. This pass runs the REAL Chronicle in both arms and
## differences a control against a treatment on the same seed, which is the
## only shape that can answer "what is a cleared camp worth".
##
## It also re-measures the danger gradient at the prowl distances pass three
## showed were needed: at PROWL 450 only 30 % of camps can reach a road and
## CONTESTED ground -- the whole point of the frontier -- had 0.00 bands/km.

const SEED := 0x4D59524B
const NEUTRAL := 0.25
const PITCH := 560.0
const DEEP := 220.0
const DENSITY := 2.5


func _init() -> void:
	var c := Chronicle.new()
	c.world_seed = SEED
	c.boot(true)
	var seats := Factions.seats_from(c.places)
	var land := Factions.land_regions(Chronicle.REGION_ROSTER, seats)
	var adj := Factions.adjacency(land, Factions.centres_of(Chronicle.REGION_ROSTER))
	var anch := Factions.anchors(land, seats, Factions.reach(land, seats, adj))
	var net := RoadNet.new()
	var rows: Array = []
	for p in c.places:
		var pd := p as Dictionary
		rows.append({"name": String(pd.get("name", "")), "pos": pd.get("pos", Vector2.ZERO),
			"rank": int(pd.get("rank", 0))})
	net.build(rows)
	var places: Array = []
	for p in c.places:
		places.append((p as Dictionary).get("pos", Vector2.ZERO))
	var sites := _march(PITCH, DEEP, places, net, land)
	var by := {}
	for s in sites:
		var sd := s as Dictionary
		var rn := String(sd["region"])
		if not by.has(rn):
			by[rn] = []
		(by[rn] as Array).append(sd)
	var areas := _areas(land)

	## a year-4 state to measure geometry against
	var state := Factions.blank(anch)
	var pushes := Factions.blank_push(land)
	_wire(c, pushes)
	for d in range(96 * 4):
		c.advance(24.0, 400)
		Factions.step(state, pushes, anch, adj, seats, 1.0)
	var occ := _occupy(by, land, state, areas, DENSITY)

	print("=== OCCUPIED CAMP SPACING (%d camps) ===" % occ.size())
	var nn: Array[float] = []
	for i in range(occ.size()):
		var a: Vector2 = (occ[i] as Dictionary)["pos"]
		var best := INF
		for j in range(occ.size()):
			if i != j:
				best = minf(best, a.distance_to((occ[j] as Dictionary)["pos"]))
		nn.append(best)
	nn.sort()
	print("  nearest occupied camp: min %.0f p25 %.0f p50 %.0f max %.0f" % [
		nn[0], _p(nn, 0.25), _p(nn, 0.5), nn[nn.size() - 1]])
	print("")

	print("=== DANGER GRADIENT vs PROWL_M ===")
	for pm: float in [450.0, 700.0, 900.0, 1200.0]:
		var line := "  PROWL %4.0f  " % pm
		var reach := 0
		for s in occ:
			var nr := net.nearest_road((s as Dictionary)["pos"])
			if not nr.is_empty() and float(nr.get("dist", 99999.0)) <= pm:
				reach += 1
		for who in [[Factions.MEN], [Factions.CONTESTED], [Factions.GOBLINS]]:
			var h := _hits(occ, net, state, who, 220.0, pm)
			line += "%s %.2f/km  " % [String(who[0]).substr(0, 4), h.x]
		line += "  (%d of %d camps work a road)" % [reach, occ.size()]
		print(line)
	print("")

	print("=== WHAT IS A CLEARED CAMP WORTH? control vs treatment, same seed ===")
	print("  A camp cleared notes a NEGATIVE goblin bias against its region. The")
	print("  Chronicle's own catalogue emits goblin biases of 0.2 to 0.8, so the")
	print("  question is which of those a destroyed camp is worth.")
	for target: String in ["ALLAGASH", "AROOSTOOK", "DOWN EAST"]:
		var base := _arm(target, 0.0, 0.0, seats, land, adj, anch)
		print("  %-16s control: gob %.3f  goblin-days %3d of 96  holder %s" % [
			target, base.x, int(base.y), _holder_name(base.z)])
		for push: float in [0.2, 0.4, 0.8]:
			for every: float in [3.0, 8.0]:
				var t := _arm(target, push, every, seats, land, adj, anch)
				print("      push %.1f every %.0f d: gob %.3f (%+.3f)  goblin-days %3d (%+d)  holder %s" % [
					push, every, t.x, t.x - base.x, int(t.y), int(t.y) - int(base.y),
					_holder_name(t.z)])
	quit(0)


func _wire(c: Chronicle, pushes: Dictionary) -> void:
	c.event_resolved.connect(func(ev: Dictionary) -> void:
		var kind := ChronicleEvents.by_id(String(ev.get("kind", "")))
		for o in (kind.get("outcomes", []) as Array):
			var od := o as Dictionary
			if String(od.get("id", "")) == String(ev.get("outcome", "")):
				var p3: Vector2 = ev.get("pos", Vector2.ZERO)
				Factions.note(pushes, Factions.region_at(Vector3(p3.x, 0.0, p3.y),
					Chronicle.REGION_ROSTER), od.get("bias", {})))


func _arm(target: String, push: float, every: float, seats: Dictionary, land: Array,
		adj: Dictionary, anch: Dictionary) -> Vector3:
	## One full game year of the REAL Chronicle, with or without a player
	## clearing camps in `target`. Returns (final goblin share, goblin-days,
	## final holder as an index into CLAIMANTS+contested).
	var c := Chronicle.new()
	c.world_seed = SEED
	c.boot(true)
	var state := Factions.blank(anch)
	var pushes := Factions.blank_push(land)
	_wire(c, pushes)
	var gdays := 0
	for d in range(96):
		if push > 0.0 and every > 0.0 and fmod(float(d), every) == 0.0:
			Factions.note(pushes, target, {"goblins": -push})
		c.advance(24.0, 400)
		Factions.step(state, pushes, anch, adj, seats, 1.0)
		if Factions.holder_of(state, target) == Factions.GOBLINS:
			gdays += 1
	var who := Factions.holder_of(state, target)
	var idx := 4.0
	for i in range(Factions.CLAIMANTS.size()):
		if String(Factions.CLAIMANTS[i]) == who:
			idx = float(i)
	return Vector3(float(Factions.hold_of(state, target).get(Factions.GOBLINS, 0.0)),
		float(gdays), idx)


func _holder_name(idx: float) -> String:
	var i := int(idx)
	if i >= 0 and i < Factions.CLAIMANTS.size():
		return String(Factions.CLAIMANTS[i])
	return Factions.CONTESTED


func _march(pitch: float, deep: float, places: Array, net: RoadNet, land: Array) -> Array:
	var b := _bounds()
	var out: Array = []
	var nx := int((b.z - b.x) / pitch)
	var nz := int((b.w - b.y) / pitch)
	for ix in range(nx):
		for iz in range(nz):
			var h := _hash(ix, iz, 0x9E3779B1)
			var p := Vector2(b.x + (float(ix) + 0.5) * pitch + (_unit(h, 1) - 0.5) * pitch * 0.7,
				b.y + (float(iz) + 0.5) * pitch + (_unit(h, 2) - 0.5) * pitch * 0.7)
			var rn := Factions.region_at(Vector3(p.x, 0.0, p.y), Chronicle.REGION_ROSTER)
			if not land.has(rn):
				continue
			if Seasons.coast_u(Vector3(p.x, 0.0, p.y)) >= 0.999:
				continue
			var bad := false
			for q: Vector2 in places:
				if q.distance_to(p) < 190.0:
					bad = true
					break
			if bad:
				continue
			var nr := net.nearest_road(p)
			if not nr.is_empty() and float(nr.get("dist", 99999.0)) < deep:
				continue
			out.append({"id": "%d,%d" % [ix, iz], "region": rn, "pos": p})
	return out


func _bounds() -> Vector4:
	var minx := INF
	var maxx := -INF
	var minz := INF
	var maxz := -INF
	for r in Chronicle.REGION_ROSTER:
		var rd := r as Dictionary
		var cc: Vector2 = rd.get("pos", Vector2.ZERO)
		var rr := float(rd.get("r", 500.0))
		minx = minf(minx, cc.x - rr)
		maxx = maxf(maxx, cc.x + rr)
		minz = minf(minz, cc.y - rr)
		maxz = maxf(maxz, cc.y + rr)
	return Vector4(minx, minz, maxx, maxz)


func _areas(_land: Array) -> Dictionary:
	var b := _bounds()
	var cw := (b.z - b.x) / 130.0
	var ch := (b.w - b.y) / 195.0
	var out := {}
	for ix in range(130):
		for iz in range(195):
			var rn := Factions.region_at(Vector3(b.x + (float(ix) + 0.5) * cw, 0.0,
				b.y + (float(iz) + 0.5) * ch), Chronicle.REGION_ROSTER)
			out[rn] = float(out.get(rn, 0.0)) + cw * ch / 1.0e6
	return out


func _occupy(by: Dictionary, land: Array, state: Dictionary, areas: Dictionary, D: float) -> Array:
	var out: Array = []
	for a in land:
		var an := String(a)
		var rows: Array = by.get(an, [])
		var shr := float(Factions.hold_of(state, an).get(Factions.GOBLINS, 0.0))
		var want := mini(rows.size(), int(round(maxf(0.0, shr - NEUTRAL) * D * float(areas.get(an, 0.0)))))
		for i in range(want):
			out.append(rows[i])
	return out


func _hits(occ: Array, net: RoadNet, state: Dictionary, who: Array, radius: float,
		prowl_m: float) -> Vector2:
	var pts: Array = []
	for s in occ:
		var sd := s as Dictionary
		var p: Vector2 = sd["pos"]
		var nr := net.nearest_road(p)
		if not nr.is_empty() and float(nr.get("dist", 99999.0)) <= prowl_m:
			p = nr.get("point", p)
		pts.append(p)
	var km := 0.0
	var seen := {}
	for e in range(net.edges.size()):
		var ed: Dictionary = net.edges[e]
		var poly: PackedVector2Array = ed.get("poly", PackedVector2Array())
		for i in range(1, poly.size()):
			var a := poly[i - 1]
			var b := poly[i]
			var seg := a.distance_to(b)
			var n := maxi(1, int(seg / 50.0))
			for t in range(n):
				var pp := a.lerp(b, float(t) / float(n))
				var rn := Factions.region_at(Vector3(pp.x, 0.0, pp.y), Chronicle.REGION_ROSTER)
				if not who.has(Factions.holder_of(state, rn)):
					continue
				km += seg / float(n) / 1000.0
				for j in range(pts.size()):
					if (pts[j] as Vector2).distance_to(pp) < radius:
						seen[j] = true
	return Vector2(float(seen.size()) / maxf(km, 0.001), km)


func _p(a: Array[float], q: float) -> float:
	if a.is_empty():
		return 0.0
	return a[mini(a.size() - 1, int(q * float(a.size() - 1)))]


static func _hash(a: int, b: int, salt: int) -> int:
	var h := (a * 0x27D4EB2F) ^ (b * 0x165667B1) ^ salt
	h = (h ^ (h >> 15)) * 0x2545F491
	h = (h ^ (h >> 13)) * 0x85EBCA6B
	return absi(h ^ (h >> 16))


static func _unit(h: int, k: int) -> float:
	return float(_hash(h, k, 0xC2B2AE35) % 100000) / 100000.0
