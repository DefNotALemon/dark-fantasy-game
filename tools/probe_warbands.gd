extends SceneTree
## tools/probe_warbands.gd -- MEASURE BEFORE CHOOSING A CONSTANT.
##   godot --headless --path . --script res://tools/probe_warbands.gd
##
## WORLD & LIFE, 2026-09-12 09:00. The goblins hold a third of the political
## map and there is not one goblin standing on it. Before a single constant is
## chosen: where IS goblin ground, how long does it stay goblin, and is there
## any road in it to seat a camp beside?

const SEED := 0x4D59524B


func _init() -> void:
	var c := Chronicle.new()
	c.world_seed = SEED
	c.boot(true)
	var seats := Factions.seats_from(c.places)
	var land := Factions.land_regions(Chronicle.REGION_ROSTER, seats)
	var centres := Factions.centres_of(Chronicle.REGION_ROSTER)
	var adj := Factions.adjacency(land, centres)
	var rch := Factions.reach(land, seats, adj)
	var anch := Factions.anchors(land, seats, rch)

	# ---------------------------------------------------------------- geography
	var net := RoadNet.new()
	var rows: Array = []
	for p in c.places:
		var pd := p as Dictionary
		rows.append({"name": String(pd.get("name", "")), "pos": pd.get("pos", Vector2.ZERO),
			"rank": int(pd.get("rank", 0))})
	net.build(rows)
	print("=== THE NET ===")
	print("  places %d  edges %d" % [net.nodes.size(), net.edges.size()])

	## Road metres inside each region, by walking every edge in 40 m steps and
	## asking region_at -- the same rule the map draws with.
	var road_m := {}
	var total_m := 0.0
	for e in range(net.edges.size()):
		var ed: Dictionary = net.edges[e]
		var poly: PackedVector2Array = ed.get("poly", PackedVector2Array())
		for i in range(1, poly.size()):
			var a := poly[i - 1]
			var b := poly[i]
			var seg := a.distance_to(b)
			total_m += seg
			var mid := (a + b) * 0.5
			var rn := Factions.region_at(Vector3(mid.x, 0.0, mid.y), Chronicle.REGION_ROSTER)
			road_m[rn] = float(road_m.get(rn, 0.0)) + seg
	print("  total road metres %.0f" % total_m)

	var places_in := {}
	for p in c.places:
		var pd2 := p as Dictionary
		var pp: Vector2 = pd2.get("pos", Vector2.ZERO)
		var rn2 := Factions.region_at(Vector3(pp.x, 0.0, pp.y), Chronicle.REGION_ROSTER)
		places_in[rn2] = int(places_in.get(rn2, 0)) + 1

	## Region areas, by the same march the map uses: 130 x 195 cells.
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
	print("  roster bounds x [%.0f %.0f]  z [%.0f %.0f]" % [minx, maxx, minz, maxz])
	var cells := {}
	var NX := 130
	var NZ := 195
	var cw := (maxx - minx) / float(NX)
	var ch := (maxz - minz) / float(NZ)
	for ix in range(NX):
		for iz in range(NZ):
			var px := minx + (float(ix) + 0.5) * cw
			var pz := minz + (float(iz) + 0.5) * ch
			var rn3 := Factions.region_at(Vector3(px, 0.0, pz), Chronicle.REGION_ROSTER)
			cells[rn3] = int(cells.get(rn3, 0)) + 1
	var cell_km2 := cw * ch / 1.0e6
	print("  cell %.1f x %.1f m  (%.3f km2)" % [cw, ch, cell_km2])
	print("")

	# ---------------------------------------------------------------- politics
	print("=== FOUR GAME YEARS OF THE FRONTIER ===")
	var c2 := Chronicle.new()
	c2.world_seed = SEED
	c2.boot(true)
	var state := Factions.blank(anch)
	var pushes := Factions.blank_push(land)
	c2.event_resolved.connect(func(ev: Dictionary) -> void:
		var kind := ChronicleEvents.by_id(String(ev.get("kind", "")))
		for o in (kind.get("outcomes", []) as Array):
			var od := o as Dictionary
			if String(od.get("id", "")) == String(ev.get("outcome", "")):
				var p3: Vector2 = ev.get("pos", Vector2.ZERO)
				var rn4 := Factions.region_at(Vector3(p3.x, 0.0, p3.y), Chronicle.REGION_ROSTER)
				Factions.note(pushes, rn4, od.get("bias", {})))

	var days_held := {}        # region -> claimant -> days
	for a in land:
		days_held[String(a)] = {}
	var gob_count: Array[int] = []
	var con_count: Array[int] = []
	var hold_sum := {}
	var mgn_sum := {}
	var gob_share_days := {}
	for d in range(96 * 4):
		c2.advance(24.0, 400)
		Factions.step(state, pushes, anch, adj, seats, 1.0)
		var ng := 0
		var nc := 0
		for a in land:
			var an := String(a)
			var who := Factions.holder_of(state, an)
			var t: Dictionary = days_held[an]
			t[who] = float(t.get(who, 0.0)) + 1.0
			var h := Factions.hold_of(state, an)
			hold_sum[an] = float(hold_sum.get(an, 0.0)) + float(h.get(Factions.GOBLINS, 0.0))
			mgn_sum[an] = float(mgn_sum.get(an, 0.0)) + Factions.margin_of(state, an)
			if who == Factions.GOBLINS:
				ng += 1
			elif who == Factions.CONTESTED:
				nc += 1
		gob_count.append(ng)
		con_count.append(nc)
	var gmin := 99
	var gmax := 0
	var gsum := 0
	for v in gob_count:
		gmin = mini(gmin, v)
		gmax = maxi(gmax, v)
		gsum += v
	var cmin := 99
	var cmax := 0
	var csum := 0
	for v in con_count:
		cmin = mini(cmin, v)
		cmax = maxi(cmax, v)
		csum += v
	print("  goblin-held regions per day: min %d mean %.2f max %d   (of %d land regions)" % [
		gmin, float(gsum) / float(gob_count.size()), gmax, land.size()])
	print("  contested regions per day:   min %d mean %.2f max %d" % [
		cmin, float(csum) / float(con_count.size()), cmax])
	print("")
	print("  %-22s %8s %6s %6s %5s %7s %7s %8s  %s" % ["region", "km2", "cells", "roadm", "plcs",
		"gobShr", "margin", "gobDays", "holder-days"])
	var tot_days := float(96 * 4)
	for a in land:
		var an := String(a)
		var t2: Dictionary = days_held[an]
		var gd := float(t2.get(Factions.GOBLINS, 0.0))
		var nice: Array = []
		for k in t2.keys():
			nice.append("%s %d" % [String(k), int(t2[k])])
		nice.sort()
		print("  %-22s %8.1f %6d %6.0f %5d %7.3f %7.3f %8.0f  %s" % [
			an, float(cells.get(an, 0)) * cell_km2, int(cells.get(an, 0)),
			float(road_m.get(an, 0.0)), int(places_in.get(an, 0)),
			float(hold_sum.get(an, 0.0)) / tot_days,
			float(mgn_sum.get(an, 0.0)) / tot_days, gd, str(nice)])
	print("")

	# ------------------------------------------------------- where the player is
	var here := Factions.region_at(Vector3.ZERO, Chronicle.REGION_ROSTER)
	print("=== THE WALK NORTH ===")
	print("  region at the origin: %s (holder %s)" % [here, Factions.holder_of(state, here)])
	var best := ""
	var bd := INF
	for r in Chronicle.REGION_ROSTER:
		var rd3 := r as Dictionary
		var nm := String(rd3.get("name", ""))
		if not land.has(nm):
			continue
		if Factions.holder_of(state, nm) != Factions.GOBLINS:
			continue
		var cp: Vector2 = rd3.get("pos", Vector2.ZERO)
		var dd := cp.length() - float(rd3.get("r", 500.0))
		if dd < bd:
			bd = dd
			best = nm
	print("  nearest goblin-held ground to the origin: %s at %.0f m" % [best, bd])
	print("")

	# ------------------------------------------------------ candidate camp seats
	print("=== IS THERE ANY ROAD IN GOBLIN GROUND? ===")
	var gob_regions: Array = []
	for a in land:
		var an2 := String(a)
		var w := Factions.holder_of(state, an2)
		if w == Factions.GOBLINS or w == Factions.CONTESTED:
			gob_regions.append(an2)
	var gob_road := 0.0
	var gob_area := 0.0
	for g in gob_regions:
		gob_road += float(road_m.get(String(g), 0.0))
		gob_area += float(cells.get(String(g), 0)) * cell_km2
	print("  goblin/contested regions at year 4: %s" % str(gob_regions))
	print("  road in them: %.0f m of %.0f m total (%.1f%%)  over %.1f km2 of %.1f km2" % [
		gob_road, total_m, 100.0 * gob_road / total_m, gob_area, _sum_area(cells, land, cell_km2)])
	print("  road density in goblin ground: %.0f m per km2" % (gob_road / maxf(gob_area, 0.001)))
	print("  road density map-wide:         %.0f m per km2" % (total_m / maxf(_sum_area(cells, land, cell_km2), 0.001)))
	quit(0)


func _sum_area(cells: Dictionary, land: Array, k: float) -> float:
	var s := 0.0
	for a in land:
		s += float(cells.get(String(a), 0)) * k
	return s
