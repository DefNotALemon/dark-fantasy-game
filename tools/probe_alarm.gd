extends SceneTree
## tools/probe_alarm.gd -- has a croft EVER barred its door?
##   godot --headless --path . --script res://tools/probe_alarm.gd
const SEED := 0x4D59524B
const CUR: Array = ["raid", "beast", "wolf", "war"]
const FIX: Array = ["goblins", "wolves", "bandits", "unrest"]

func _init() -> void:
	var c := Chronicle.new()
	c.world_seed = SEED
	c.boot(true)
	var vals: Array = []
	var hits_cur := 0
	var hits_fix := 0
	var samples := 0
	var best_cur := 0.0
	var best_fix := 0.0
	for d in range(96):
		c.advance(24.0, 400)
		for p in c.places:
			var pd := p as Dictionary
			var p2: Vector2 = pd["pos"]
			var at := Vector3(p2.x, 0.0, p2.y)
			samples += 1
			var wc := 0.0
			for tg in CUR:
				wc = maxf(wc, c.pressure_at(at, String(tg)))
			var wf := 0.0
			for tg in FIX:
				wf = maxf(wf, c.pressure_at(at, String(tg)))
			best_cur = maxf(best_cur, wc)
			best_fix = maxf(best_fix, wf)
			if wc >= 0.55:
				hits_cur += 1
			vals.append(wf)
			if wf >= 0.55:
				hits_fix += 1
	print("samples=%d  CURRENT tags: %d over 0.55 (best %.3f)  |  REAL tags: %d over 0.55 (best %.3f)" % [samples, hits_cur, best_cur, hits_fix, best_fix])
	var seen: Dictionary = {}
	for tg in CUR:
		seen[tg] = c.bias.has(String(tg))
	for tg in FIX:
		seen[tg] = c.bias.has(String(tg))
	print("tag present in the live bias pool after a year: %s" % str(seen))
	vals.sort()
	var qs: Array = []
	for pct in [50, 75, 85, 90, 92, 95, 97, 99]:
		var idx := int(float(pct) / 100.0 * float(vals.size() - 1))
		qs.append("p%d=%.2f" % [pct, float(vals[idx])])
	print("REAL-tag worst-pressure quantiles over %d croft-days: %s" % [vals.size(), ", ".join(qs)])
	for thr in [0.55, 0.80, 1.00, 1.20, 1.50]:
		var n := 0
		for v in vals:
			if float(v) >= thr:
				n += 1
		print("  threshold %.2f -> %5.1f%% of croft-days barred" % [thr, 100.0 * float(n) / float(vals.size())])
	quit(0)
