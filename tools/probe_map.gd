extends SceneTree

## tools/probe_map.gd -- MEASURE BEFORE CHOOSING A CONSTANT.
## What the map would actually have to draw, in view pixels, off the real roster.

const MAP_W := 520.0
const MAP_H := 780.0
const ORIGIN := Vector2(-1525.71, -8160.0)
const SIZE := Vector2(7200.0, 10800.0)

func _px(w: Vector2) -> Vector2:
	return (w - ORIGIN) / SIZE * Vector2(MAP_W, MAP_H)

func _init() -> void:
	var c := Chronicle.new()
	get_root().add_child(c)
	c.boot(true)
	var roster: Array = Chronicle.REGION_ROSTER
	var centres: Dictionary = {}
	var radii: Dictionary = {}
	for r in roster:
		var rd := r as Dictionary
		centres[String(rd["name"])] = rd["pos"] as Vector2
		radii[String(rd["name"])] = float(rd["r"])

	print("=== SCALE ===")
	var mpp := SIZE.x / MAP_W
	print("  m per px x=%.2f  z=%.2f" % [SIZE.x / MAP_W, SIZE.y / MAP_H])
	print("  region radii in px: min %.1f  max %.1f" % [
		295.3 / mpp, 965.9 / mpp])

	var adj: Dictionary = c._fadj
	print("=== ADJACENCY GEOMETRY (px at zoom 1) ===")
	var _seen := {}
	var gaps: Array[float] = []
	var overlaps := 0
	var pairs := 0
	for a in adj.keys():
		for b in (adj[a] as Array):
			var an := String(a); var bn := String(b)
			if bn <= an: continue
			if not centres.has(an) or not centres.has(bn): continue
			pairs += 1
			var ca: Vector2 = centres[an]; var cb: Vector2 = centres[bn]
			var pa := _px(ca); var pb := _px(cb)
			var dpx := pa.distance_to(pb)
			var rapx := float(radii[an]) / mpp
			var rbpx := float(radii[bn]) / mpp
			var gap := dpx - rapx - rbpx
			gaps.append(gap)
			if gap < 0.0: overlaps += 1
			print("  %-22s %-22s  centres %6.1f px   ra %5.1f  rb %5.1f   GAP %7.1f   minr %5.1f" % [
				an, bn, dpx, rapx, rbpx, gap, minf(rapx, rbpx)])
	gaps.sort()
	@warning_ignore("integer_division")
	print("  pairs=%d  overlapping=%d  gap median=%.1f px  min=%.1f  max=%.1f" % [
		pairs, overlaps, gaps[gaps.size() / 2], gaps[0], gaps[-1]])

	print("=== MARGIN DISTRIBUTION over a simulated year ===")
	var samples: Array[float] = []
	var front_counts: Array[int] = []
	var _contested_days := 0
	var holders := {}
	for dayi in range(96):
		c.advance(24.0, 4000)
		var f: Array = Factions.frontier(c.factions, adj)
		front_counts.append(f.size())
		for n in (c.factions.keys() as Array):
			var rn := String(n)
			samples.append(Factions.margin_of(c.factions, rn))
			var h := Factions.holder_of(c.factions, rn)
			holders[h] = int(holders.get(h, 0)) + 1
			if h == Factions.CONTESTED: _contested_days += 1
	samples.sort()
	var n2 := samples.size()
	@warning_ignore("integer_division")
	print("  margin samples=%d  p05=%.4f p25=%.4f p50=%.4f p75=%.4f p95=%.4f max=%.4f" % [
		n2, samples[int(n2*0.05)], samples[int(n2*0.25)], samples[n2/2],
		samples[int(n2*0.75)], samples[int(n2*0.95)], samples[-1]])
	var lo := front_counts[0]; var hi := front_counts[0]; var tot := 0
	for v in front_counts:
		lo = mini(lo, v); hi = maxi(hi, v); tot += v
	print("  frontier pairs over the year: min %d  max %d  mean %.1f" % [lo, hi, float(tot) / float(front_counts.size())])
	print("  holder tally over 96 days x 17 regions: %s" % str(holders))
	print("  HOLD_MARGIN=%.3f  CLAIMED=%.3f" % [Factions.HOLD_MARGIN, Factions.CLAIMED])

	print("=== what fraction of regions sit at each margin band ===")
	for t: float in [0.02, 0.04, 0.06, 0.10, 0.15, 0.20, 0.30]:
		var below := 0
		for s in samples:
			if s < t: below += 1
		print("  margin < %.2f : %5.1f%%" % [t, 100.0 * float(below) / float(n2)])
	quit()
