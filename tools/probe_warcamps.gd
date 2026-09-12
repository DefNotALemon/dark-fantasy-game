extends SceneTree
## tools/probe_warcamps.gd -- pass two. Probe one found that ALLAGASH, the most
## goblin ground on the map (384 of 384 days) and the largest region on it,
## has EXACTLY ZERO METRES OF ROAD. A camp seated on the road net the way a
## croft is would put no goblin at all in the goblin homeland. So the sites are
## seated on the region's own GROUND, and the road is what they come out to.
##
## This pass fits: the scatter (spacing, clearance), the quota density, and the
## number that decides whether the feature is a world or a warzone -- how many
## occupied camps you pass per kilometre walked, in the south and in the north.

const SEED := 0x4D59524B
const NEUTRAL := 0.25


func _init() -> void:
	var c := Chronicle.new()
	c.world_seed = SEED
	c.boot(true)
	var seats := Factions.seats_from(c.places)
	var land := Factions.land_regions(Chronicle.REGION_ROSTER, seats)
	var centres := Factions.centres_of(Chronicle.REGION_ROSTER)
	var adj := Factions.adjacency(land, centres)
	var anch := Factions.anchors(land, seats, Factions.reach(land, seats, adj))

	var net := RoadNet.new()
	var rows: Array = []
	for p in c.places:
		var pd := p as Dictionary
		rows.append({"name": String(pd.get("name", "")), "pos": pd.get("pos", Vector2.ZERO),
			"rank": int(pd.get("rank", 0))})
	net.build(rows)

	## Run the real field to a year-4 steady state, then measure against THAT.
	var state := Factions.blank(anch)
	var pushes := Factions.blank_push(land)
	c.event_resolved.connect(func(ev: Dictionary) -> void:
		var kind := ChronicleEvents.by_id(String(ev.get("kind", "")))
		for o in (kind.get("outcomes", []) as Array):
			var od := o as Dictionary
			if String(od.get("id", "")) == String(ev.get("outcome", "")):
				var p3: Vector2 = ev.get("pos", Vector2.ZERO)
				Factions.note(pushes, Factions.region_at(Vector3(p3.x, 0.0, p3.y),
					Chronicle.REGION_ROSTER), od.get("bias", {})))
	for d in range(96 * 4):
		c.advance(24.0, 400)
		Factions.step(state, pushes, anch, adj, seats, 1.0)

	var places: Array = []
	for p in c.places:
		var pd2 := p as Dictionary
		places.append(pd2.get("pos", Vector2.ZERO))

	print("=== THE SCATTER: spacing x clearance ===")
	for spacing: float in [500.0, 700.0, 900.0]:
		for clear: float in [190.0, 300.0]:
			var sites := _scatter(land, spacing, clear, places, net)
			var nn := _nn_stats(sites)
			print("  spacing %4.0f clear %3.0f -> %3d sites   nn min %.0f p50 %.0f   road dist p50 %.0f max %.0f" % [
				spacing, clear, sites.size(), nn.x, nn.y, _road_p(sites, net, 0.5), _road_p(sites, net, 1.0)])
	print("")

	var SPACING := 700.0
	var CLEAR := 190.0
	var sites := _scatter(land, SPACING, CLEAR, places, net)
	var by_region := {}
	for s in sites:
		var sd := s as Dictionary
		var rn := String(sd["region"])
		by_region[rn] = int(by_region.get(rn, 0)) + 1
	print("=== SITES PER REGION at spacing %.0f, and what each quota rule OCCUPIES ===" % SPACING)
	print("  %-22s %5s %6s %6s %6s %6s %6s" % ["region", "sites", "gobShr", "D=2.0", "D=3.0", "D=4.0", "D=6.0"])
	var tot := {2.0: 0, 3.0: 0, 4.0: 0, 6.0: 0}
	for a in land:
		var an := String(a)
		var h := Factions.hold_of(state, an)
		var shr := float(h.get(Factions.GOBLINS, 0.0))
		var n := int(by_region.get(an, 0))
		var line := "  %-22s %5d %6.3f" % [an, n, shr]
		for D: float in [2.0, 3.0, 4.0, 6.0]:
			var want := mini(n, int(round(maxf(0.0, shr - NEUTRAL) * D * float(n))))
			tot[D] = int(tot[D]) + want
			line += " %6d" % want
		print(line)
	print("  %-22s %5d %6s %6d %6d %6d %6d" % ["TOTAL", sites.size(), "",
		int(tot[2.0]), int(tot[3.0]), int(tot[4.0]), int(tot[6.0])])
	print("")

	print("=== HOW OFTEN YOU MEET ONE: camps within 220 m per km walked ===")
	for D: float in [2.0, 3.0, 4.0, 6.0]:
		var occ := _occupy(sites, land, state, D)
		var south := _walk_hits(occ, net, state, [Factions.MEN], 220.0)
		var north := _walk_hits(occ, net, state, [Factions.GOBLINS, Factions.CONTESTED], 220.0)
		print("  D=%.1f  occupied %3d   men's roads: %.2f camps/km over %.1f km   goblin+contested roads: %.2f camps/km over %.1f km" % [
			D, occ.size(), south.x, south.y, north.x, north.y])
	print("")

	print("=== THE DEEP: a straight walk north up the map, D=3 ===")
	var occ3 := _occupy(sites, land, state, 3.0)
	var hits := 0
	var steps := 0
	var last := ""
	for i in range(0, 9000, 40):
		var p := Vector2(2200.0, 1000.0 - float(i))
		var rn2 := Factions.region_at(Vector3(p.x, 0.0, p.y), Chronicle.REGION_ROSTER)
		steps += 1
		var near := ""
		for s in occ3:
			var sd2 := s as Dictionary
			if (sd2["pos"] as Vector2).distance_to(p) < 220.0:
				near = String(sd2["id"])
				break
		if not near.is_empty() and near != last:
			hits += 1
			print("    at z %6.0f  %-22s (%s)  camp %s" % [p.y, rn2,
				Factions.holder_of(state, rn2), near])
		last = near
	print("  %d camps met over %.1f km of walking due north" % [hits, float(steps) * 40.0 / 1000.0])
	quit(0)


func _scatter(land: Array, spacing: float, clear: float, places: Array, net: RoadNet) -> Array:
	## Candidate sites: a deterministic hashed scatter inside each region circle,
	## rejected for spacing, for sitting on a town, and for open water.
	var out: Array = []
	for r in Chronicle.REGION_ROSTER:
		var rd := r as Dictionary
		var nm := String(rd.get("name", ""))
		if not land.has(nm):
			continue
		var ctr: Vector2 = rd.get("pos", Vector2.ZERO)
		var rad := float(rd.get("r", 500.0))
		var kept: Array = []
		for k in range(140):
			var h := _hash(nm.hash(), k, 0x9E3779B1)
			var u := _unit(h, 1)
			var v := _unit(h, 2)
			var ang := u * TAU
			var rr := sqrt(v) * rad * 0.92
			var p := ctr + Vector2(cos(ang), sin(ang)) * rr
			if Seasons.coast_u(Vector3(p.x, 0.0, p.y)) >= 0.999:
				continue
			if Factions.region_at(Vector3(p.x, 0.0, p.y), Chronicle.REGION_ROSTER) != nm:
				continue
			var bad := false
			for q: Vector2 in places:
				if q.distance_to(p) < clear:
					bad = true
					break
			if bad:
				continue
			for q2 in kept:
				if (q2 as Vector2).distance_to(p) < spacing:
					bad = true
					break
			if bad:
				continue
			kept.append(p)
			out.append({"id": "%s#%d" % [nm, k], "region": nm, "pos": p, "k": k})
	return out


func _nn_stats(sites: Array) -> Vector2:
	var ds: Array[float] = []
	for i in range(sites.size()):
		var a: Vector2 = (sites[i] as Dictionary)["pos"]
		var best := INF
		for j in range(sites.size()):
			if i == j:
				continue
			var b: Vector2 = (sites[j] as Dictionary)["pos"]
			best = minf(best, a.distance_to(b))
		ds.append(best)
	ds.sort()
	if ds.is_empty():
		return Vector2.ZERO
	return Vector2(ds[0], ds[ds.size() / 2])


func _road_p(sites: Array, net: RoadNet, q: float) -> float:
	var ds: Array[float] = []
	for s in sites:
		var p: Vector2 = (s as Dictionary)["pos"]
		var nr := net.nearest_road(p)
		ds.append(float(nr.get("dist", 99999.0)) if not nr.is_empty() else 99999.0)
	ds.sort()
	if ds.is_empty():
		return 0.0
	return ds[mini(ds.size() - 1, int(q * float(ds.size() - 1)))]


func _occupy(sites: Array, land: Array, state: Dictionary, D: float) -> Array:
	var by := {}
	for s in sites:
		var sd := s as Dictionary
		var rn := String(sd["region"])
		if not by.has(rn):
			by[rn] = []
		(by[rn] as Array).append(sd)
	var out: Array = []
	for a in land:
		var an := String(a)
		var rows: Array = by.get(an, [])
		var shr := float(Factions.hold_of(state, an).get(Factions.GOBLINS, 0.0))
		var want := mini(rows.size(), int(round(maxf(0.0, shr - NEUTRAL) * D * float(rows.size()))))
		for i in range(want):
			out.append(rows[i])
	return out


func _walk_hits(occ: Array, net: RoadNet, state: Dictionary, who: Array, radius: float) -> Vector2:
	## Walk every road polyline in 40 m steps through ground held by `who`,
	## and count DISTINCT camps that come inside `radius`.
	var km := 0.0
	var seen := {}
	for e in range(net.edges.size()):
		var ed: Dictionary = net.edges[e]
		var poly: PackedVector2Array = ed.get("poly", PackedVector2Array())
		for i in range(1, poly.size()):
			var a := poly[i - 1]
			var b := poly[i]
			var seg := a.distance_to(b)
			var n := maxi(1, int(seg / 40.0))
			for t in range(n):
				var p := a.lerp(b, float(t) / float(n))
				var rn := Factions.region_at(Vector3(p.x, 0.0, p.y), Chronicle.REGION_ROSTER)
				if not who.has(Factions.holder_of(state, rn)):
					continue
				km += seg / float(n) / 1000.0
				for s in occ:
					var sd := s as Dictionary
					if (sd["pos"] as Vector2).distance_to(p) < radius:
						seen[String(sd["id"])] = true
	return Vector2(float(seen.size()) / maxf(km, 0.001), km)


static func _hash(a: int, b: int, salt: int) -> int:
	var h := (a * 0x27D4EB2F) ^ (b * 0x165667B1) ^ salt
	h = (h ^ (h >> 15)) * 0x2545F491
	h = (h ^ (h >> 13)) * 0x85EBCA6B
	return absi(h ^ (h >> 16))


static func _unit(h: int, k: int) -> float:
	return float(_hash(h, k, 0xC2B2AE35) % 100000) / 100000.0
