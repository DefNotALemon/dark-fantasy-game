extends SceneTree

## tools/probe_map3.gd -- does the thing this round just wrote actually produce
## a map? And does the ground you can WALK agree with the graph the sim PUSHES on?

const ORIGIN := Vector2(-1199.79, -8800.08)
const SIZE := Vector2(7200.0, 10800.0)

func _init() -> void:
	var c := Chronicle.new()
	get_root().add_child(c)
	c.boot(true)
	var roster: Array = Chronicle.REGION_ROSTER
	var t0 := Time.get_ticks_usec()
	var part := MapLayers.partition(roster, MapLayers.GRID_NX, MapLayers.GRID_NZ, ORIGIN, SIZE)
	print("partition %d cells in %.1f ms" % [part.size(), float(Time.get_ticks_usec() - t0) / 1000.0])

	for days: int in [0, 40, 200]:
		while c.days < float(days):
			c.advance(24.0, 4000)
		var t1 := Time.get_ticks_usec()
		var b := MapLayers.border(roster, c.factions, part, MapLayers.GRID_NX,
			MapLayers.GRID_NZ, ORIGIN, SIZE)
		var ms := float(Time.get_ticks_usec() - t1) / 1000.0
		var pairs := {}
		var pts := 0
		var byfirm := [0, 0, 0]
		var total_len := 0.0
		for e in b:
			var ed := e as Dictionary
			pairs["%s|%s" % [ed["a"], ed["b"]]] = true
			var pl: PackedVector2Array = ed["pts"]
			pts += pl.size()
			byfirm[int(ed["firm"])] += 1
			for i in range(pl.size() - 1):
				total_len += pl[i].distance_to(pl[i + 1])
		var fr: Array = Factions.frontier(c.factions, c._fadj)
		var frset := {}
		for f in fr:
			frset["%s|%s" % [(f as Dictionary)["a"], (f as Dictionary)["b"]]] = true
		var only_map := []
		var only_graph := []
		for k in pairs.keys():
			if not frset.has(k): only_map.append(k)
		for k in frset.keys():
			if not pairs.has(k): only_graph.append(k)
		print("--- day %d: %d chains, %d pairs, %d points, %.1f km of border, march %.2f ms" % [
			days, b.size(), pairs.size(), pts, total_len / 1000.0, ms])
		print("    firmness settled=%d uneasy=%d frayed=%d" % byfirm)
		print("    Factions.frontier() pairs=%d" % fr.size())
		print("    ON THE GROUND BUT NOT IN THE GRAPH: %s" % str(only_map))
		print("    IN THE GRAPH BUT NOT ON THE GROUND: %s" % str(only_graph))
		var lens: Array[int] = []
		for e2 in b:
			lens.append(((e2 as Dictionary)["pts"] as PackedVector2Array).size())
		lens.sort()
		@warning_ignore("integer_division")
		print("    chain point counts: min %d median %d max %d" % [lens[0], lens[lens.size()/2], lens[-1]])
		for e3 in b:
			var e3d := e3 as Dictionary
			var p3: PackedVector2Array = e3d["pts"]
			var l3 := 0.0
			for i in range(p3.size() - 1): l3 += p3[i].distance_to(p3[i+1])
			if l3 > 3000.0:
				print("      %-20s | %-20s  %s  %5.1f km  (%s vs %s)" % [e3d["a"], e3d["b"],
					MapLayers.FIRM_NAMES[int(e3d["firm"])], l3 / 1000.0, e3d["held_a"], e3d["held_b"]])
		var si := MapLayers.sides(roster, c.factions)
		var t2 := Time.get_ticks_usec()
		var img := MapLayers.tint_image(part, MapLayers.GRID_NX, MapLayers.GRID_NZ, si)
		print("    tint image %dx%d in %.1f ms" % [img.get_width(), img.get_height(),
			float(Time.get_ticks_usec() - t2) / 1000.0])
		print("    hover readout samples:")
		for nm: String in ["CASCO BAY", "KATAHDIN", "RANGELEY LAKES", "GULF OF MAINE", "ALLAGASH"]:
			print("      %-18s -> '%s'" % [nm, MapLayers.hold_line(c.factions, nm)])
	quit()
