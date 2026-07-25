extends SceneTree
## Does a dug tunnel survive a save, a full cave reshuffle, and a load?
## That's the 30 m sphere in CaveRegion.save_state / _stamp_sphere.

var _t := 0.0
var _step := 0
var _w: Node
var _p: Node3D
var _region
var _dug: Array[Vector3] = []
var _dens: Array[float] = []
var _fails: Array[String] = []

func _sample(at: Vector3) -> float:
	var f = _region.field
	var i := int(round((at.x - f.origin.x) / CaveField.VOX))
	var j := int(round((at.y - f.origin.y) / CaveField.VOX))
	var k := int(round((at.z - f.origin.z) / CaveField.VOX))
	return f.data[f.idx(clampi(i, 0, CaveField.SX - 1), clampi(j, 0, CaveField.SY - 1),
		clampi(k, 0, CaveField.SZ - 1))]

func _ok(c: bool, what: String) -> void:
	print(("  PASS  " if c else "  FAIL  ") + what)
	if not c:
		_fails.append(what)

func _initialize() -> void:
	_w = (load("res://scenes/World.tscn") as PackedScene).instantiate()
	root.add_child(_w)

func _process(d: float) -> bool:
	_t += d
	if _t < 2.0:
		return false
	_region = _w.get("_region")
	match _step:
		0:
			if not _region.is_fully_loaded():
				return false
			_p = root.get_tree().get_first_node_in_group("player")
			## Find deep air FAR from every mouth (mouths keep a 24 m permanence
			## bubble that would survive a reshuffle on its own = a vacuous test).
			var reach = _region.field.reachable_air()
			var spot := Vector3.INF
			for s in reach:
				var wp = _region.field.sample_pos(s.x, s.y, s.z)
				if wp.y > -14.0:
					continue
				var far := true
				for m in _region.field.mouths:
					if Vector2(wp.x - m.x, wp.z - m.z).length() < 45.0:
						far = false
				if far:
					spot = wp
					break
			_ok(spot != Vector3.INF, "found deep air far from any mouth")
			if spot == Vector3.INF:
				quit(1)
			_p.global_position = spot
			## Dig a short distinctive corridor.
			for i in range(5):
				var at: Vector3 = spot + Vector3(float(i) * 1.3, 0, 0)
				_region.carve_bite(at)
				_dug.append(at)
			var air := 0
			for at in _dug:
				if not _region.field.is_rock(at):
					air += 1
			_ok(air == _dug.size(), "the pickaxe opened the corridor (%d/%d air)" % [air, _dug.size()])
			for at in _dug:
				_dens.append(_sample(at))
			_ok(SaveGame.save_game(_p) == "", "saved from underground")
			_step = 1
		1:
			## Reshuffle the whole underground — a different cave entirely.
			_ok(_region.reset_underground(), "cave reshuffled (a sleep-shift)")
			_step = 2
		2:
			if not _region.is_fully_loaded():
				return false
			var still := 0
			for at in _dug:
				if not _region.field.is_rock(at):
					still += 1
			var moved := 0
			for i in range(_dug.size()):
				if absf(_sample(_dug[i]) - _dens[i]) > 0.05:
					moved += 1
			print("  (after the reshuffle %d/%d still air, %d/%d densities CHANGED)"
				% [still, _dug.size(), moved, _dug.size()])
			_ok(moved > 0, "the reshuffle really did redraw that rock")
			_ok(SaveGame.load_game(_p) == "", "loaded the underground save")
			_step = 3
		3:
			if not _region.is_fully_loaded():
				return false
			var air := 0
			for at in _dug:
				if not _region.field.is_rock(at):
					air += 1
			_ok(air == _dug.size(), "the dug corridor came back (%d/%d air)" % [air, _dug.size()])
			var same := 0
			for i in range(_dug.size()):
				if absf(_sample(_dug[i]) - _dens[i]) < 0.02:
					same += 1
			_ok(same == _dug.size(),
				"...to the exact density it was saved at (%d/%d)" % [same, _dug.size()])
			_ok(_p.global_position.distance_to(_dug[0]) < 3.0, "you came back where you dug")
			print("")
			print("ALL CHECKS PASSED" if _fails.is_empty() else "FAILURES: " + ", ".join(_fails))
			quit(0 if _fails.is_empty() else 1)
	return false
