extends SceneTree

## tools/probe_map4.gd -- FIRM_MARGIN was measured on the wrong population.
## Firmness is the MIN of a PAIR, which is systematically lower than any one
## region's margin, so a threshold taken from the per-region median called
## almost every border uneasy. Measure the thing the constant is actually asked.

const ORIGIN := Vector2(-1199.79, -8800.08)
const SIZE := Vector2(7200.0, 10800.0)

func _init() -> void:
	var c := Chronicle.new()
	get_root().add_child(c)
	c.boot(true)
	var roster: Array = Chronicle.REGION_ROSTER
	var part := MapLayers.partition(roster, MapLayers.GRID_NX, MapLayers.GRID_NZ, ORIGIN, SIZE)
	var mins: Array[float] = []
	var held_pairs := 0
	var contested_pairs := 0
	var sea_lines := 0
	var chain_hist := {}
	for step in range(200):
		c.advance(24.0, 4000)
		var b := MapLayers.border(roster, c.factions, part, MapLayers.GRID_NX,
			MapLayers.GRID_NZ, ORIGIN, SIZE)
		var seen := {}
		for e in b:
			var ed := e as Dictionary
			if String(ed["held_a"]) == "" or String(ed["held_b"]) == "":
				sea_lines += 1
			var key := "%s|%s" % [ed["a"], ed["b"]]
			if seen.has(key):
				continue
			seen[key] = true
			var ha := Factions.holder_of(c.factions, String(ed["a"]))
			var hb := Factions.holder_of(c.factions, String(ed["b"]))
			if ha == Factions.CONTESTED or hb == Factions.CONTESTED:
				contested_pairs += 1
				continue
			held_pairs += 1
			mins.append(minf(Factions.margin_of(c.factions, String(ed["a"])),
				Factions.margin_of(c.factions, String(ed["b"]))))
		chain_hist[b.size()] = int(chain_hist.get(b.size(), 0)) + 1
	print("SEA LINES STILL DRAWN: %d   (must be 0)" % sea_lines)
	mins.sort()
	var n := mins.size()
	print("pair-min margin over %d HELD border pairs across 200 days:" % n)
	print("  p05=%.4f p25=%.4f p50=%.4f p75=%.4f p95=%.4f  max=%.4f" % [
		mins[int(n*0.05)], mins[int(n*0.25)], mins[n/2], mins[int(n*0.75)],
		mins[int(n*0.95)], mins[-1]])
	print("  held pairs=%d  contested pairs=%d  (%.0f%% of borders are frayed)" % [
		held_pairs, contested_pairs,
		100.0 * float(contested_pairs) / float(held_pairs + contested_pairs)])
	print("  a threshold at the pair-min MEDIAN %.4f splits the held half in two:" % mins[n/2])
	for t: float in [0.02, 0.04, 0.06, 0.08, 0.10, 0.1229, 0.15, 0.2062]:
		var below := 0
		for m in mins:
			if m < t: below += 1
		var pc_all := 100.0 * float(below) / float(held_pairs + contested_pairs)
		print("    t=%.4f -> uneasy %5.1f%% of held   |  of ALL borders: settled %4.1f%% uneasy %4.1f%% frayed %4.1f%%" % [
			t, 100.0 * float(below) / float(n),
			100.0 - pc_all - 100.0 * float(contested_pairs) / float(held_pairs + contested_pairs),
			pc_all, 100.0 * float(contested_pairs) / float(held_pairs + contested_pairs)])
	var ks: Array = chain_hist.keys(); ks.sort()
	print("  chains per frame: min %d max %d" % [ks[0], ks[-1]])
	quit()
