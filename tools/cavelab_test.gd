extends SceneTree
## The cave lab: do all four rival generators build, hollow out, floor
## smoothly, dig, and replace each other?

var _t := 0.0
var _step := 0
var _w: Node
var _p: Node
var _fails: Array[String] = []

func _ok(c: bool, what: String) -> void:
	print(("  PASS  " if c else "  FAIL  ") + what)
	if not c:
		_fails.append(what)

func _initialize() -> void:
	_w = (load("res://scenes/World.tscn") as PackedScene).instantiate()
	root.add_child(_w)

func _interior_air(lab: TestCave) -> int:
	## Count air samples in the massif's core band — proof it's hollow.
	var air := 0
	for i in range(10, TestCave.SX - 10, 3):
		for j in range(4, TestCave.SY - 8, 2):
			for k in range(10, TestCave.SZ - 10, 3):
				if lab.field[(i * TestCave.SY + j) * TestCave.SZ + k] < 0.0:
					air += 1
	return air

func _floor_heights(lab: TestCave, xz: Vector2, r: float) -> Array[float]:
	## Scan columns near a point: local floor heights (first rock->air top).
	var out: Array[float] = []
	for dx in range(-int(r), int(r) + 1, 1):
		for dz in range(-int(r), int(r) + 1, 1):
			var i := int(xz.x / TestCave.VOX) + dx
			var k := int(xz.y / TestCave.VOX) + dz
			if i < 1 or k < 1 or i >= TestCave.SX - 1 or k >= TestCave.SZ - 1:
				continue
			for j in range(1, TestCave.SY - 2):
				var below: float = lab.field[(i * TestCave.SY + j) * TestCave.SZ + k]
				var above: float = lab.field[(i * TestCave.SY + j + 1) * TestCave.SZ + k]
				if below >= 0.0 and above < 0.0:
					out.append(float(j) * TestCave.VOX)
					break
	return out

func _spawn(v: int) -> TestCave:
	_p._spawn_test_cave(v)
	return root.get_tree().get_first_node_in_group("test_cave") as TestCave

func _process(d: float) -> bool:
	_t += d
	if _t < 1.5:
		return false
	match _step:
		0:
			_p = root.get_tree().get_first_node_in_group("player")
			set_meta("v", 1)
			set_meta("next_at", _t)
			_step = 10
		10:
			## --- Each variant in its own frame-batch, with a breather ---
			if _t < float(get_meta("next_at")):
				return false
			var v: int = get_meta("v")
			var lab := _spawn(v)
			if v == 4:
				set_meta("cathedral_champs", 0)
			_ok(lab != null and lab.variant == v, "New Cave %d spawns" % v)
			_ok(lab._chunks.size() > 10, "  ...meshed (%d chunks)" % lab._chunks.size())
			var air := _interior_air(lab)
			_ok(air > 120, "  ...genuinely hollow (%d core air samples)" % air)
			var cl := 0
			for ch in lab.get_children():
				if ch is CrystalCluster:
					cl += 1
			_ok(cl >= 2, "  ...lit inside (%d crystal clusters)" % cl)
			## --- Normal spawns: dwellers live here, INSIDE the rock ---
			var mobs: Array[Node] = []
			var kinds := {}
			var inside := 0
			for ch in lab.get_children():
				if ch is Enemy:
					mobs.append(ch)
					kinds[(ch as Enemy).display_name] = true
					var lp: Vector3 = (ch as Node3D).position
					if lp.x > 4.0 and lp.x < 61.0 and lp.z > 4.0 and lp.z < 61.0 \
							and lp.y > 1.0 and lp.y < 22.0:
						inside += 1
			_ok(mobs.size() >= 7, "  ...peopled like a real cave (%d dwellers)" % mobs.size())
			_ok(kinds.size() >= 3, "  ...a proper roster (%s)" % ", ".join(kinds.keys()))
			_ok(inside == mobs.size(), "  ...every one of them INSIDE the massif (%d/%d)" % [inside, mobs.size()])
			var calm_normal := true
			for m in mobs:
				if (m as Enemy).confused:
					calm_normal = false
			_ok(calm_normal, "  ...and none are menu-confused (real dwellers)")
			## --- The dressed entrance ---
			var spots_l := 0
			var mouth_crystal := false
			for ch in lab.get_children():
				if ch is SpotLight3D:
					spots_l += 1
				elif ch is CrystalCluster and (ch as Node3D).position.z < 14.0:
					mouth_crystal = true
			_ok(spots_l == 1, "  ...daylight shaft down the throat")
			_ok(mouth_crystal, "  ...night-marker crystal just inside the door")
			if v < 4:
				set_meta("v", v + 1)
				set_meta("next_at", _t + 1.0)
				return false
			_ok(root.get_tree().get_nodes_in_group("test_cave").size() == 1,
				"one lab stands at a time (the rest were cleared)")
			set_meta("next_at", _t + 1.0)
			_step = 1
		1:
			if _t < float(get_meta("next_at")):
				return false
			## --- Halls: the arena floor is walkably FLAT ---
			var lab := _spawn(2)
			var e: Array = lab._ellipsoids[0]
			var c: Vector3 = e[0]
			var hs := _floor_heights(lab, Vector2(c.x, c.z), 3.0)
			_ok(hs.size() > 10, "hall floor scanned (%d columns)" % hs.size())
			var lo := 999.0
			var hi := -999.0
			for h in hs:
				lo = minf(lo, h)
				hi = maxf(hi, h)
			_ok(hi - lo < 1.3, "chamber floor is walkably flat (spread %.2f m over ~6 m)" % (hi - lo))
			_step = 2
		2:
			if _t < 5.0:
				return false
			## --- The pickaxe digs the lab like real rock ---
			var lab := root.get_tree().get_first_node_in_group("test_cave") as TestCave
			var wall_local := Vector3(8.0, 5.0, 30.0)  ## solid flank of the massif
			var before: float = lab.field[(10 * TestCave.SY + 6) * TestCave.SZ + 37]
			var carved: bool = lab.carve_bite(lab.to_global(wall_local))
			_ok(carved, "carve_bite bites the massif")
			_ok(before >= 0.0, "  (it was rock before)")
			var after_air := false
			for j in range(4, 9):
				if lab.field[(10 * TestCave.SY + j) * TestCave.SZ + 37] < 0.0:
					after_air = true
			_ok(after_air, "  ...and left a hole in the field")
			_step = 3
		3:
			## --- The dig cast is duck-typed (lab isn't a CaveRegion) ---
			var lab := root.get_tree().get_first_node_in_group("test_cave")
			_ok(not (lab is CaveRegion), "the lab is NOT a CaveRegion")
			_ok(lab.has_method("carve_bite"), "yet the pickaxe path accepts it (duck-typed)")
			print("")
			print("ALL CHECKS PASSED" if _fails.is_empty() else "FAILURES: " + ", ".join(_fails))
			quit(0 if _fails.is_empty() else 1)
	return false
