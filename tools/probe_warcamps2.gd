extends SceneTree
## tools/probe_warcamps2.gd -- pass three, and the last before a constant is
## chosen. Pass two killed the per-region rejection scatter: at a 700 m spacing
## fourteen of the seventeen land regions get exactly ONE candidate site, so a
## quota expressed as a fraction of the site count quantises to all-or-nothing.
## This pass seats the sites the way the map draws a border -- by MARCHING a
## rule over a global grid -- and fits the quota against AREA instead.
##
## It also fits the two numbers the feature lives or dies by: how far a band
## has to prowl to reach a road (pass two measured the p50 camp-to-road at
## 401 m), and what clearing a camp is worth on the political map.

const SEED := 0x4D59524B
const NEUTRAL := 0.25


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

	print("=== MARCHED SITES: pitch x deep ===")
	for pitch: float in [420.0, 560.0, 700.0]:
		for deep: float in [120.0, 220.0, 320.0]:
			var s := _march(pitch, deep, places, net, land)
			var regs := {}
			for r in s:
				regs[String((r as Dictionary)["region"])] = int(regs.get(String((r as Dictionary)["region"]), 0)) + 1
			var lo := 999
			var hi := 0
			var zero := 0
			for a in land:
				var n := int(regs.get(String(a), 0))
				lo = mini(lo, n)
				hi = maxi(hi, n)
				if n == 0:
					zero += 1
			print("  pitch %4.0f deep %3.0f -> %4d sites   per-region min %d max %d   regions with none: %d" % [
				pitch, deep, s.size(), lo, hi, zero])
	print("")

	var PITCH := 560.0
	var DEEP := 220.0
	var sites := _march(PITCH, DEEP, places, net, land)
	var by := {}
	for s in sites:
		var sd := s as Dictionary
		var rn := String(sd["region"])
		if not by.has(rn):
			by[rn] = []
		(by[rn] as Array).append(sd)
	var areas := _areas(land)

	print("=== QUOTA BY AREA at pitch %.0f deep %.0f ===" % [PITCH, DEEP])
	print("  %-22s %5s %6s %6s   %5s %5s %5s %5s" % ["region", "sites", "km2", "gobShr", "D=1.5", "D=2.5", "D=3.5", "D=5.0"])
	var tot := {1.5: 0, 2.5: 0, 3.5: 0, 5.0: 0}
	for a in land:
		var an := String(a)
		var shr := float(Factions.hold_of(state, an).get(Factions.GOBLINS, 0.0))
		var n := (by.get(an, []) as Array).size()
		var km2 := float(areas.get(an, 0.0))
		var line := "  %-22s %5d %6.1f %6.3f  " % [an, n, km2, shr]
		for D: float in [1.5, 2.5, 3.5, 5.0]:
			var want := mini(n, int(round(maxf(0.0, shr - NEUTRAL) * D * km2)))
			tot[D] = int(tot[D]) + want
			line += " %5d" % want
		print(line)
	print("  %-22s %5d %6.1f %6s   %5d %5d %5d %5d" % ["TOTAL", sites.size(), _sum(areas), "",
		int(tot[1.5]), int(tot[2.5]), int(tot[3.5]), int(tot[5.0])])
	print("")

	print("=== THE PROWL: can a band reach a road? ===")
	var ds: Array[float] = []
	for s in sites:
		var nr := net.nearest_road((s as Dictionary)["pos"])
		ds.append(float(nr.get("dist", 99999.0)) if not nr.is_empty() else 99999.0)
	ds.sort()
	print("  camp-to-road over all %d sites: p05 %.0f p25 %.0f p50 %.0f p75 %.0f p95 %.0f max %.0f" % [
		ds.size(), _p(ds, 0.05), _p(ds, 0.25), _p(ds, 0.50), _p(ds, 0.75), _p(ds, 0.95), ds[ds.size() - 1]])
	for pm: float in [300.0, 450.0, 600.0, 900.0]:
		var reach := 0
		for d in ds:
			if d <= pm:
				reach += 1
		print("  PROWL_M %4.0f -> %d of %d sites (%.0f%%) work a road; the rest prowl their own ground" % [
			pm, reach, ds.size(), 100.0 * float(reach) / float(ds.size())])
	print("")

	print("=== THE DANGER GRADIENT: occupied camps on the road, D=2.5, PROWL 450 ===")
	var occ := _occupy(by, land, state, areas, 2.5)
	for radius: float in [220.0]:
		for who in [[Factions.MEN], [Factions.CONTESTED], [Factions.GOBLINS]]:
			var camp_hit := _hits(occ, net, state, who, radius, false)
			var prowl_hit := _hits(occ, net, state, who, radius, true)
			print("  on %-24s roads: %.2f camps/km asleep in camp, %.2f bands/km once they are OUT  (%.1f km)" % [
				str(who), camp_hit.x, prowl_hit.x, prowl_hit.y])
	print("  occupied camps map-wide: %d" % occ.size())
	print("")

	print("=== WHAT IS A CLEARED CAMP WORTH? a season of clearing, per region ===")
	for push: float in [0.15, 0.30, 0.60]:
		for every: float in [4.0]:
			var st2 := _copy(state)
			var pu2 := Factions.blank_push(land)
			var target := "AROOSTOOK"
			var t0 := float(Factions.hold_of(st2, target).get(Factions.GOBLINS, 0.0))
			var who0 := Factions.holder_of(st2, target)
			var flipped := -1
			for d in range(96):
				if fmod(float(d), every) == 0.0:
					Factions.note(pu2, target, {"goblins": -push})
				Factions.step(st2, pu2, anch, adj, seats, 1.0)
				if flipped < 0 and Factions.holder_of(st2, target) == Factions.MEN and who0 != Factions.MEN:
					flipped = d
			print("  clear-push %.2f every %.0f days at %s: gob %.3f -> %.3f  holder %s -> %s  men by day %s" % [
				push, every, target, t0, float(Factions.hold_of(st2, target).get(Factions.GOBLINS, 0.0)),
				who0, Factions.holder_of(st2, target), str(flipped)])
	quit(0)


func _march(pitch: float, deep: float, places: Array, net: RoadNet, land: Array) -> Array:
	## Walk a jittered lattice over the roster's bounds and keep the cells that
	## are land, off the political sea, clear of every town, and DEEP -- that is,
	## no road within `deep`. Allagash has no road at all, so all of it is deep.
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
	var out: Array = []
	var nx := int((maxx - minx) / pitch)
	var nz := int((maxz - minz) / pitch)
	for ix in range(nx):
		for iz in range(nz):
			var h := _hash(ix, iz, 0x9E3779B1)
			var jx := (_unit(h, 1) - 0.5) * pitch * 0.7
			var jz := (_unit(h, 2) - 0.5) * pitch * 0.7
			var p := Vector2(minx + (float(ix) + 0.5) * pitch + jx,
				minz + (float(iz) + 0.5) * pitch + jz)
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


func _areas(_land: Array) -> Dictionary:
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
	var NX := 130
	var NZ := 195
	var cw := (maxx - minx) / float(NX)
	var ch := (maxz - minz) / float(NZ)
	var out := {}
	for ix in range(NX):
		for iz in range(NZ):
			var p := Vector3(minx + (float(ix) + 0.5) * cw, 0.0, minz + (float(iz) + 0.5) * ch)
			var rn := Factions.region_at(p, Chronicle.REGION_ROSTER)
			out[rn] = float(out.get(rn, 0.0)) + cw * ch / 1.0e6
	return out


func _sum(d: Dictionary) -> float:
	var s := 0.0
	for k in d:
		s += float(d[k])
	return s


func _p(a: Array[float], q: float) -> float:
	if a.is_empty():
		return 0.0
	return a[mini(a.size() - 1, int(q * float(a.size() - 1)))]


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
		prowl: bool) -> Vector2:
	var pts: Array = []
	for s in occ:
		var sd := s as Dictionary
		var p: Vector2 = sd["pos"]
		if prowl:
			var nr := net.nearest_road(p)
			if not nr.is_empty() and float(nr.get("dist", 99999.0)) <= 450.0:
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
			var n := maxi(1, int(seg / 40.0))
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


func _copy(state: Dictionary) -> Dictionary:
	var out := {}
	for k in state:
		out[String(k)] = (state[k] as Dictionary).duplicate()
	return out


static func _hash(a: int, b: int, salt: int) -> int:
	var h := (a * 0x27D4EB2F) ^ (b * 0x165667B1) ^ salt
	h = (h ^ (h >> 15)) * 0x2545F491
	h = (h ^ (h >> 13)) * 0x85EBCA6B
	return absi(h ^ (h >> 16))


static func _unit(h: int, k: int) -> float:
	return float(_hash(h, k, 0xC2B2AE35) % 100000) / 100000.0
