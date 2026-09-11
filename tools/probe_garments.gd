extends SceneTree

## tools/probe_garments.gd -- THE MEASUREMENT THAT CHOSE EVERY CONSTANT IN
## scripts/Garments.gd, kept in the tree so the literal margins in
## tests/GarmentTests.gd can be re-derived rather than trusted.
##
##   godot --headless --path . --script res://tools/probe_garments.gd
##
## It was run BEFORE a line of Garments.gd existed, against three candidate
## parameter sets, and the winner is the one in the file: a steel harness
## costs about an hour of a winter night and cold iron costs two and a half,
## which is worth roughly half of what the fire is worth and never replaces
## it.

func full(m: String) -> Dictionary:
	var d := {}
	for s in Materials.ARMOR_SLOTS:
		d[s] = m
	return d

func night(sc: Array, worn: Dictionary) -> Array:
	var e := Exposure.env({"season": int(sc[1]), "hour": float(sc[2]), "wind": float(sc[3]),
		"sheltered": bool(sc[5]), "worn": worn})
	var r: Dictionary = Slumber.night(e, Exposure.WARMTH_MAX, float(sc[4]), 10.0,
		float(sc[6]), float(sc[7]))
	return [e, r]

func _init() -> void:
	print("table problems: ", Garments.table_problems())
	var scen := [
		["winter 21:00 open", 3, 21.0, 0.2, 0.0, false, 0.0, 0.0],
		["winter 21:00 gale", 3, 21.0, 1.0, 0.0, false, 0.0, 0.0],
		["winter 21:00 SOAKED", 3, 21.0, 0.2, 1.0, false, 0.0, 0.0],
		["winter roof, no fire", 3, 21.0, 0.2, 0.0, true, 0.0, 0.0],
		["autumn 21:00 open", 2, 21.0, 0.2, 0.0, false, 0.0, 0.0],
	]
	var sets := [["naked", {}], ["steel", full("steel")], ["cold_iron", full("cold_iron")],
		["meteoric", full("meteoric")], ["dragonsteel", full("dragonsteel")],
		["mithril", full("mithril")], ["adamant", full("adamant")],
		["steel chest", {"chest": "steel"}], ["steel boots", {"shoes": "steel"}]]
	for sc in scen:
		print("")
		for st in sets:
			var pair := night(sc, st[1])
			var e: Dictionary = pair[0]
			var r: Dictionary = pair[1]
			print("%-21s %-12s garment %+5.2f felt %7.2f slept %5.2f of %.2f  woke %-5s at %5.2f  coldest %6.2f" % [
				String(sc[0]), String(st[0]), Exposure.garment_c(e, float(sc[4])),
				Exposure.felt_c(e, float(sc[4])), float(r["hours_slept"]), float(r["hours_planned"]),
				String(r["woke"]), float(r["hour"]), float(r["coldest"])])
	print("")
	var order := [{}, {"chest": "steel"}, {"chest": "steel", "pants": "steel"},
		{"chest": "steel", "pants": "steel", "arms": "steel"},
		{"chest": "steel", "pants": "steel", "arms": "steel", "helmet": "steel"},
		full("steel")]
	for w in order:
		print("%d pc cover %.2f  winter open %+5.2f  gale %+5.2f  summer %+5.2f" % [
			Garments.pieces(w), Garments.cover(w),
			Garments.garment_c(w, -4.0, 0.0, 0.2), Garments.garment_c(w, -4.0, 0.0, 1.0),
			Garments.garment_c(w, 18.0, 0.0, 0.2)])
	print("")
	var pack := []
	for s in Materials.ARMOR_SLOTS:
		for m in ["steel", "cold_iron"]:
			pack.append({"slot": s, "material": m})
	for air in [-9.6, -4.0, 4.0, 11.9, 18.0]:
		var d := Garments.dress(pack, float(air), 0.0, 0.2)
		print("dress(steel|cold iron) at %6.2f C -> %-16s protect %.3f  net %+.2f" % [air,
			Garments.describe(d), Garments.protect(d), Garments.garment_c(d, float(air), 0.0, 0.2)])
	print("")
	var places := {"CASCO BAY": Vector3(600.2, 8.0, 559.9), "AROOSTOOK": Vector3(3600.2, 210.0, -7000.1)}
	for nm in places:
		var pos: Vector3 = places[nm]
		for day in [18.0, 66.0, 90.0]:
			var bc := Seasons.base_c_at(float(day), pos)
			var sea := Exposure.season_for_day(float(day))
			var e2 := Exposure.env({"season": sea, "hour": 4.0, "y": pos.y, "base_c": bc})
			var e3 := Exposure.env({"season": sea, "hour": 4.0, "y": pos.y})
			print("%-12s day %5.1f base_c %6.2f  ambient local %6.2f  shared %6.2f" % [
				String(nm), day, bc, Exposure.ambient_c(e2), Exposure.ambient_c(e3)])
	print("")
	var ew := Exposure.env({"season": 3, "hour": 21.0, "worn": full("steel"), "fire_c": 14.0})
	var en := Exposure.env({"season": 3, "hour": 21.0, "fire_c": 14.0})
	print("dry rate at a fire: bare %.5f  full plate %.5f  mult %.3f" % [
		Exposure.wet_rate(en, 0.8), Exposure.wet_rate(ew, 0.8), Garments.dry_mult(full("steel"))])
	quit()