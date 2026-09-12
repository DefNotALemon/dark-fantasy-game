extends SceneTree
func _init() -> void:
	var c := Chronicle.new()
	c.world_seed = 0x4D59524B
	c.boot(true)
	var st := c.factions
	var bax: Dictionary = st.get("BAXTER STATE PARK", {})
	var cas: Dictionary = st.get("CASCO BAY", {})
	var all: Dictionary = st.get("ALLAGASH", {})
	var bands := {}
	for k in CritterDex.keys():
		var b := Factions.band_name(Factions.band_of(String(k)))
		bands[b] = int(bands.get(b, 0)) + 1
	print("band counts: %s   roster %d" % [str(bands), CritterDex.keys().size()])
	var reps := {"HUNTER": "", "SCAV": "", "QUIET": ""}
	for k in CritterDex.keys():
		var b := Factions.band_name(Factions.band_of(String(k)))
		if String(reps[b]).is_empty():
			reps[b] = String(k)
	for b in ["HUNTER", "SCAV", "QUIET"]:
		var k := String(reps[b])
		var mb := Factions.spawn_mult(k, bax)
		var mc := Factions.spawn_mult(k, cas)
		var ma := Factions.spawn_mult(k, all)
		print("%-7s %-16s baxter %.4f  casco %.4f  allagash %.4f   ratio bax/casco %.3f" % [b, k, mb, mc, ma, mb / mc])
	var neutral := {"men": 0.25, "goblins": 0.25, "wolves": 0.25, "wild": 0.25}
	var worst := 0.0
	for k in CritterDex.keys():
		worst = maxf(worst, absf(Factions.spawn_mult(String(k), neutral) - 1.0))
	print("worst departure from 1.0 on neutral ground, over the whole roster: %.9f" % worst)
	var allmen := {"men": 1.0, "goblins": 0.0, "wolves": 0.0, "wild": 0.0}
	for b in ["HUNTER", "SCAV", "QUIET"]:
		print("  all-men ground, %s -> %.4f" % [b, Factions.spawn_mult(String(reps[b]), allmen)])
	print("baxter %s  casco %s" % [str(bax), str(cas)])
	quit(0)
