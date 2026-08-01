extends SceneTree
## The Cathedral is the REAL underground now: do the caverns exist, connect,
## floor smoothly, people themselves, and re-author on a sleep shift?

var _t := 0.0
var _step := 0
var _w: Node
var _region
var _first_center := Vector3.ZERO
var _fails: Array[String] = []

func _ok(c: bool, what: String) -> void:
	print(("  PASS  " if c else "  FAIL  ") + what)
	if not c:
		_fails.append(what)

func _initialize() -> void:
	_w = (load("res://scenes/World.tscn") as PackedScene).instantiate()
	root.add_child(_w)

func _air_at(f, wp: Vector3) -> bool:
	var i := int(round((wp.x - f.origin.x) / CaveField.VOX))
	var j := int(round((wp.y - f.origin.y) / CaveField.VOX))
	var k := int(round((wp.z - f.origin.z) / CaveField.VOX))
	if i < 1 or j < 1 or k < 1 or i >= CaveField.SX - 1 or j >= CaveField.SY - 1 or k >= CaveField.SZ - 1:
		return false
	return f.data[f.idx(i, j, k)] < 0.0

func _process(d: float) -> bool:
	_t += d
	if _t < 2.0:
		return false
	_region = _w.get("_region")
	match _step:
		0:
			if not _region.is_fully_loaded():
				return false
			var f = _region.field
			_ok(f._cath_ell.size() >= 10, "the cathedral system was authored (%d caverns)" % f._cath_ell.size())
			_ok(f._cath_caps.size() >= 20, "joined by tunnels (%d segments)" % f._cath_caps.size())
			_ok(f._cath_cols.size() >= 6, "with columns in the naves (%d)" % f._cath_cols.size())
			## Cavern hearts are genuinely AIR after the deep load.
			var hollow := 0
			for e in f._cath_ell:
				if _air_at(f, (e[0] as Vector3) + Vector3(0, 1.0, 0)):
					hollow += 1
			_ok(hollow >= f._cath_ell.size() * 0.8,
				"cavern hearts are open air (%d/%d)" % [hollow, f._cath_ell.size()])
			_first_center = f._cath_ell[0][0]
			## Connectivity: the BFS from the mouths reaches a big underground.
			var reach: Array = f.reachable_air()
			_ok(reach.size() > 20000, "the network connects to the mouths (%d reachable nodes)" % reach.size())
			## Content moved in.
			var mobs := 0
			for e2 in root.get_tree().get_nodes_in_group("enemies"):
				if (e2 as Node3D).global_position.y < -3.0:
					mobs += 1
			_ok(mobs >= 15, "dwellers took the caverns (%d underground)" % mobs)
			_ok(root.get_tree().get_nodes_in_group("ore_veins").size() >= 10,
				"veins seam the walls (%d)" % root.get_tree().get_nodes_in_group("ore_veins").size())
			## Floors: scan a grand cavern's walking line.
			var big_i := 0
			var big_r := 0.0
			for n in range(f._cath_ell.size()):
				if (f._cath_ell[n][1] as Vector3).x > big_r:
					big_r = (f._cath_ell[n][1] as Vector3).x
					big_i = n
			var c: Vector3 = f._cath_ell[big_i][0]
			var heights: Array[float] = []
			var cols := 0
			for dx in range(-3, 4):
				for dz in range(-3, 4):
					## Start the drop from MID-CAVERN air (starting inside the
					## ceiling rock made floor_point report the ceiling).
					var p: Vector3 = f.floor_point(Vector3i(
						int((c.x - f.origin.x) / CaveField.VOX) + dx,
						int((c.y - f.origin.y) / CaveField.VOX),
						int((c.z - f.origin.z) / CaveField.VOX) + dz))
					if p != Vector3.INF and p.y < -2.0:
						cols += 1
						heights.append(p.y)
			_ok(cols > 20, "nave floor scanned (%d columns)" % cols)
			## The SEDIMENT is the claim — a scan corner may graze a rock
			## column's flared foot (furniture, not rubble). Judge the middle
			## 90% of the walk, not the pillar it brushed.
			heights.sort()
			var cut := maxi(int(heights.size() * 0.05), 1)
			var spread: float = heights[heights.size() - 1 - cut] - heights[cut]
			_ok(spread < 1.5, "and it walks like terrain, not rubble (core spread %.2f m)" % spread)
			_step = 1
		1:
			## --- The sleep shift re-authors the whole system ---
			_ok(_region.reset_underground(), "sleep-shift accepted")
			_step = 2
		2:
			if not _region.is_fully_loaded():
				return false
			var f = _region.field
			var moved: Vector3 = f._cath_ell[0][0]
			_ok(moved.distance_to(_first_center) > 2.0,
				"the shift re-authored the caverns (first nave moved %.0f m)" % moved.distance_to(_first_center))
			_ok(f._cath_caps.size() >= 20, "and re-tunnelled the network (%d segments)" % f._cath_caps.size())
			print("")
			print("ALL CHECKS PASSED" if _fails.is_empty() else "FAILURES: " + ", ".join(_fails))
			quit(0 if _fails.is_empty() else 1)
	return false
