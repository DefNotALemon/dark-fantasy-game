extends SceneTree

## tools/probe_map2.gd -- the border is FOUND, not drawn. What does marching the
## sim's own partition actually cost, and how coarse can the grid be?

const ORIGIN := Vector2(-1199.79, -8800.08)
const SIZE := Vector2(7200.0, 10800.0)

func _part(roster: Array, nx: int, nz: int) -> PackedInt32Array:
	var out := PackedInt32Array(); out.resize(nx * nz)
	var cx := SIZE.x / float(nx); var cz := SIZE.y / float(nz)
	for j in range(nz):
		var wz := ORIGIN.y + (float(j) + 0.5) * cz
		for i in range(nx):
			var wx := ORIGIN.x + (float(i) + 0.5) * cx
			var here := Vector2(wx, wz)
			var best := -1; var bd := INF
			var near := -1; var nd := INF
			for k in range(roster.size()):
				var rd := roster[k] as Dictionary
				var c: Vector2 = rd["pos"]
				var d := c.distance_to(here)
				if d < nd: nd = d; near = k
				if d < float(rd["r"]) and d < bd: bd = d; best = k
			out[j * nx + i] = best if best >= 0 else near
	return out

func _edges(part: PackedInt32Array, nx: int, nz: int, side: PackedInt32Array) -> int:
	var n := 0
	for j in range(nz):
		for i in range(nx):
			var a := side[part[j * nx + i]]
			if i + 1 < nx and side[part[j * nx + i + 1]] != a: n += 1
			if j + 1 < nz and side[part[(j + 1) * nx + i]] != a: n += 1
	return n

func _init() -> void:
	var c := Chronicle.new()
	get_root().add_child(c)
	c.boot(true)
	var roster: Array = Chronicle.REGION_ROSTER
	print("=== PARTITION COST (pure geometry, cached forever) ===")
	for nx: int in [64, 96, 130, 192, 260]:
		var nz := int(round(float(nx) * SIZE.y / SIZE.x))
		var t0 := Time.get_ticks_usec()
		var _p := _part(roster, nx, nz)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		print("  %dx%d = %6d cells  %7.1f ms   world cell %5.1f m   view px at zoom1 %.2f" % [
			nx, nz, nx * nz, ms, SIZE.x / float(nx), 520.0 / float(nx)])

	# how many border edges at each resolution, with the REAL holders
	for i in range(40): c.advance(24.0, 4000)
	var side := PackedInt32Array(); side.resize(roster.size())
	var names: Array[String] = []
	for k in range(roster.size()):
		var rn := String((roster[k] as Dictionary)["name"])
		names.append(rn)
		var h := Factions.holder_of(c.factions, rn)
		if not c.factions.has(rn): h = "sea"
		side[k] = ["men", "goblins", "wolves", "wild", "contested", "sea"].find(h)
	print("=== holders after 40 days ===")
	for k in range(roster.size()):
		print("  %-22s side=%d  margin=%.3f" % [names[k], side[k],
			Factions.margin_of(c.factions, names[k])])
	print("=== BORDER EDGE COUNT vs resolution ===")
	for nx: int in [64, 96, 130, 192]:
		var nz := int(round(float(nx) * SIZE.y / SIZE.x))
		var p := _part(roster, nx, nz)
		var t0 := Time.get_ticks_usec()
		var e := _edges(p, nx, nz, side)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		print("  %dx%d -> %5d border edges   march %6.2f ms" % [nx, nz, e, ms])

	print("=== ROADS ===")
	var rn2 := RoadNet.new()
	get_root().add_child(rn2)
	rn2.height_fn = func(p: Vector2) -> float: return 120.0 + 40.0 * sin(p.x * 0.001) * cos(p.y * 0.0009)
	rn2.water_fn = func(_p: Vector2) -> float: return RoadNet.NO_WATER
	var rows: Array = []
	for pl in Chronicle.PLACE_ROSTER:
		var pd := pl as Dictionary
		rows.append({"name": pd["name"], "pos": pd["pos"], "rank": pd.get("rank", 0)})
	var t1 := Time.get_ticks_usec()
	rn2.build(rows)
	print("  build %.0f ms  nodes=%d edges=%d" % [float(Time.get_ticks_usec() - t1) / 1000.0,
		rn2.nodes.size(), rn2.edges.size()])
	var pts := 0
	for e2 in rn2.edges:
		pts += (e2["poly"] as PackedVector2Array).size()
	print("  total polyline points across every road: %d" % pts)
	quit()
