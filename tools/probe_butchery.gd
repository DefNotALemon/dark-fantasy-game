extends SceneTree

# tools/probe_butchery.gd -- MEASURE BEFORE CHOOSING A CONSTANT.
#
#   godot --headless --path . --script res://tools/probe_butchery.gd
#
# Run before one assertion of ButcheryTests was written, and it decided the
# shape of the feature four separate times:
#
#   1. `harv` rows WITHOUT MEAT. Sixteen of the dex's rows have none, and the
#      first draft butchered them anyway: a Great Blue Heron is 7.29 kg on the
#      ledger and three feathers in the pack, so butchering one denied the
#      crows a heron for nothing. The Whale, with an empty row, lost 1 200 kg
#      to a 200-cut loop that could never fill a back.
#   2. `Materials.get_mat` FALLS BACK TO IRON, so reading a blade's tier
#      through the front door made every string in the language an edge.
#   3. WHOLE KILOGRAMS ERASE THE SMALL ANIMALS. A woodchuck is 0.97 kg and
#      `floorf` of that is nought cuts.
#   4. And the one the LIVE game had to correct after all of the above: the
#      free back is 55.70 kg and not 40.70, because worn gear counts at HALF.
#      So on a deer the man is stopped by the CARCASS -- `stage_of` calls
#      14.5 % bones -- and not by his back at all.

const START_CARRIED := 34.30
const LIMIT := 90.0


func strip(mass: float, harv: Dictionary, mat: String, keep_parts: bool, start: float) -> Dictionary:
	var left := mass
	var carried := start
	var n := 0
	while n < 400:
		if Carcasses.stage_of({"mass": mass, "left": left}) >= Carcasses.STAGE_BONES:
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


func hours_to_find(g: int, mass: float, left: float, sky: int, season: int) -> float:
	var h := 0.0
	var p := 0.0
	var hr := 0.0
	while p < 1.0 and h < 3000.0:
		p += Carcasses.find_gain(g, mass, left, hr, sky, season)
		h += Carcasses.STEP_HOURS
		hr = fmod(hr + Carcasses.STEP_HOURS, 24.0)
	return h


func _init() -> void:
	print("=== ONE BACK-LOAD, butcherable rows only, iron sword ===")
	var rows: Array = []
	for k in CritterDex.DEX.keys():
		var d: Dictionary = CritterDex.DEX[k]
		if float(d.get("len", 0.0)) <= 0.0:
			continue
		var m := Carcasses.mass_of(String(k), float(d["len"]))
		if m < Carcasses.MIN_MASS:
			continue
		rows.append({"k": k, "nm": String(d.get("nm", k)), "m": m,
			"harv": (d.get("harv", {}) as Dictionary)})
	rows.sort_custom(func(a, b): return float(a["m"]) > float(b["m"]))
	var yes := 0
	var no := 0
	for r in rows:
		if not Butchery.butcherable(r["harv"]):
			no += 1
			continue
		yes += 1
		var res := strip(float(r["m"]), r["harv"], "iron", true, START_CARRIED)
		print("  %-22s %8.2f kg | %2d cuts | left %7.2f (%5.1f%%) | back %6.2f | denies %s"
			% [r["nm"], r["m"], int(res["cuts"]), float(res["left"]),
			   float(res["frac"]) * 100.0, float(res["carried"]),
			   str(Butchery.denied(float(r["m"]), float(res["left"])))])
	print("  butcherable %d, refused %d, of %d over MIN_MASS" % [yes, no, rows.size()])

	print("")
	print("=== THE SAME DEER, TWO BACKS ===")
	var deer := Carcasses.mass_of("whitetail", 1.70)
	var harv: Dictionary = (CritterDex.get_profile("whitetail") as Dictionary)["harv"]
	for start: float in [START_CARRIED, 49.30]:
		var res := strip(deer, harv, "iron", true, start)
		print("  starting at %5.2f kg: %d cuts, left %5.2f (%4.1f%%), back %6.2f, denies %s"
			% [start, int(res["cuts"]), float(res["left"]), float(res["frac"]) * 100.0,
			   float(res["carried"]), str(Butchery.denied(deer, float(res["left"])))])

	print("")
	print("=== EDGE TIERS ===")
	for m2: String in ["iron", "steel", "silver", "mithril", "adamant", "nonsense", ""]:
		print("  %-12s tier %2d  cut %.2f kg" % [m2, Butchery.edge_tier(m2), Butchery.cut_kg(m2)])

	print("")
	print("=== OPEN_SCENT, hours to find one spring deer (49.13 kg) ===")
	for g in Carcasses.GUILDS.size():
		print("  %-10s whole %6.1f   opened %6.1f"
			% [(Carcasses.GUILDS[g] as Dictionary)["nm"],
			   hours_to_find(g, 49.13, 49.13, 0, 0), hours_to_find(g, 49.13, 20.0, 0, 0)])

	print("")
	print("=== THE REAL WALK, no player: who turns up, and when ===")
	for mass: float in [49.13, 243.89]:
		var bus := Carcasses.new()
		var rec := {"id": 1, "species": "x", "nm": "x", "at": Vector3.ZERO, "born": 0.0,
			"mass": mass, "left": mass, "seen": {}, "prog": {}, "took": {},
			"stripped": -1.0, "near_player": false, "place": "", "told": {}}
		var t := 0.0
		var opened := -1.0
		var at: Dictionary = {}
		for i in 8000:
			bus._step_rec(rec, t, fmod(t * 24.0, 24.0), 0, 0)
			t += Carcasses.STEP_HOURS / 24.0
			if opened < 0.0 and Carcasses.open_mult(mass, float(rec["left"])) > 1.0:
				opened = t * 24.0
			for k in (rec["seen"] as Dictionary).keys():
				if not at.has(k):
					at[k] = t * 24.0
			if float(rec["left"]) <= 0.0:
				break
		var line := "  %7.2f kg: opened %5.1f h |" % [mass, opened]
		for g in Carcasses.GUILDS.size():
			var id := String((Carcasses.GUILDS[g] as Dictionary)["id"])
			line += "  %s %s" % [id, ("%.1f h" % float(at[id])) if at.has(id) else "NEVER"]
		print(line)
		bus.free()
	quit()
