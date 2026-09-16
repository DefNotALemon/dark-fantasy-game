extends SceneTree
## Does a bucked trunk come back down to the ground? Fell an oak onto a box,
## let it settle, cut it from the side, simulate, and report where the pieces
## ended up relative to the ground (y = 0).
##   godot --headless --path . --script res://_to_delete/resettle_probe.gd

var _t := 0.0
var _w: Node3D
var _tr: FallenTrunk
var _piece: FallenTrunk = null
var _phase := 0
var _report := {}


func _initialize() -> void:
	root.add_child(Wind.new())


func _process(_d: float) -> bool:
	if _w == null:
		_w = Node3D.new()
		root.add_child(_w)
		var g := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(300, 2, 300)
		cs.shape = b
		cs.position = Vector3(0, -1, 0)
		g.add_child(cs)
		_w.add_child(g)
		var t := TreeV2.new()
		t.species = "oak"
		t.stage = 3
		t.tree_seed = 77
		_w.add_child(t)
		while not t.felled:
			t.chop_hit(Vector3(0, 0, 1))
		for c in _w.get_children():
			if c is FallenTrunk:
				_tr = c
	return false


func _low_point(tr: FallenTrunk) -> float:
	## lowest point of the trunk cylinder, world y
	var a := tr.to_global(Vector3(0, tr._base, 0))
	var b := tr.to_global(Vector3(0, tr._base + tr.trunk_len, 0))
	return minf(a.y, b.y) - tr.trunk_r


func _physics_process(delta: float) -> bool:
	if _tr == null:
		return false
	_t += delta
	if _phase == 0 and _tr.settled:
		_report["settled_at"] = _t
		_report["low_before"] = _low_point(_tr)
		_report["len_before"] = _tr.trunk_len
		## cut it a third of the way up from the butt, from the side
		var aim := _tr.to_global(Vector3(0.3, _tr._base + _tr.trunk_len * 0.33, 0))
		_tr.chop_hit(Vector3(0, 0, 1), aim)
		for c in _w.get_children():
			if c is FallenTrunk and c != _tr:
				_piece = c
		_report["len_after"] = _tr.trunk_len
		_report["piece_len"] = _piece.trunk_len if _piece else -1.0
		_report["piece_low_at_cut"] = _low_point(_piece) if _piece else -1.0
		_report["a_low_at_cut"] = _low_point(_tr)
		_phase = 1
		_report["cut_at"] = _t
	elif _phase == 1 and _t > float(_report["cut_at"]) + 6.0:
		_report["a_frozen"] = _tr.freeze
		_report["a_resettle"] = _tr._resettle
		_report["a_low_after"] = _low_point(_tr)
		_report["a_tilt"] = rad_to_deg(acos(clampf(absf(_tr.global_transform.basis.y.dot(Vector3.UP)), 0, 1)))
		if _piece != null and is_instance_valid(_piece):
			_report["b_frozen"] = _piece.freeze
			_report["b_low_after"] = _low_point(_piece)
			_report["b_tilt"] = rad_to_deg(acos(clampf(absf(_piece.global_transform.basis.y.dot(Vector3.UP)), 0, 1)))
			_report["b_settled"] = _piece.settled
			_report["b_dist_from_a"] = _piece.global_position.distance_to(_tr.global_position)
			_report["axis_dot"] = _piece.global_transform.basis.y.dot(_tr.global_transform.basis.y)
			var a0 := _tr.to_global(Vector3(0, _tr._base, 0))
			var a1 := _tr.to_global(Vector3(0, _tr._base + _tr.trunk_len, 0))
			var b0 := _piece.to_global(Vector3(0, _piece._base, 0))
			var b1 := _piece.to_global(Vector3(0, _piece._base + _piece.trunk_len, 0))
			_report["a_ends"] = [a0, a1]
			_report["b_ends"] = [b0, b1]
			var cp := Geometry3D.get_closest_points_between_segments(a0, a1, b0, b1)
			_report["gap_between_axes"] = cp[0].distance_to(cp[1])
			_report["radii"] = [_tr.trunk_r, _piece.trunk_r]
		print("RESETTLE ", JSON.stringify(_report))
		quit(0)
		return true
	if _t > 40.0:
		print("RESETTLE timeout ", JSON.stringify(_report))
		quit(1)
		return true
	return false
