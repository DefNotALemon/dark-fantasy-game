extends SceneTree

func _init() -> void:
	var c := Chronicle.new()
	c.world_seed = 20260906
	root.add_child(c)
	c.boot()
	print("places: %d  sample: %s" % [c.places.size(), c.places[2]])
	c.advance(24.0 * 30.0)
	var r: Dictionary = c.report()
	print("after 30 days: day=%.2f active=%d resolved=%d" % [r["day"], r["active"], r["resolved"]])
	print("events fired total: %d  -> %.2f/day" % [c._uid - 1, float(c._uid - 1) / 30.0])
	print("bias: %s" % [r["bias"]])
	print("--- the last eight things that happened ---")
	var from := maxi(c.resolved.size() - 8, 0)
	for i in range(from, c.resolved.size()):
		var e: Dictionary = c.resolved[i]
		print("  d%6.2f  %-18s %s" % [e["born"], e["kind"], e["line"]])
	print("--- what they are saying at Bangor ---")
	var b: Dictionary = c.place_by_name("Bangor")
	for x in c.rumours_at(Vector3(b["pos"].x, 0.0, b["pos"].y), 4):
		print("  (d%.2f from %s) %s" % [x["day"], x["from"], x["text"]])
	var lo := 1.0
	var hi := 0.0
	for p in c.places:
		lo = minf(lo, p["mood"])
		hi = maxf(hi, p["mood"])
	print("mood spread %.3f .. %.3f" % [lo, hi])
	var kinds := {}
	for e in c.resolved:
		kinds[e["kind"]] = int(kinds.get(e["kind"], 0)) + 1
	print("distinct kinds in the ring: %d of %d" % [kinds.size(), ChronicleEvents.KINDS.size()])
	quit(0)
