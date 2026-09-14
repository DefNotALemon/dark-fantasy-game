extends SceneTree
## Dumps the timber geometry as OBJ so it can be looked at in Blender:
##   godot --headless --path . --script res://tools/timber_probe.gd
## Writes /tmp/timber_log.obj (a built log), /tmp/timber_trunk.obj (a felled
## oak after one buck) and /tmp/timber_section.obj (the log that came off).

var _frames := 0
var _world: Node3D
var _trunk: FallenTrunk


func _initialize() -> void:
	root.add_child(Wind.new())


func _obj(path: String, mesh: Mesh, xf: Transform3D) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	var base := 1
	for si in range(mesh.get_surface_count()):
		var arr := mesh.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		f.store_line("o surface_%d" % si)
		f.store_line("usemtl %s" % ("bark" if si == 0 else "grain"))
		for p in v:
			var w := xf * p
			f.store_line("v %f %f %f" % [w.x, w.y, w.z])
		var t := 0
		while t + 2 < idx.size():
			## OBJ is CCW-front; Godot is CW-front, so flip
			f.store_line("f %d %d %d" % [base + idx[t], base + idx[t + 2], base + idx[t + 1]])
			t += 3
		base += v.size()
	f.close()


func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 1:
		var mi := WoodCut.log_instance("oak", 0.25, 2.0, Color(0.3, 0.2, 0.1), 3)
		_obj("/tmp/timber_log.obj", mi.mesh, Transform3D.IDENTITY)
		mi.free()
		_world = Node3D.new()
		root.add_child(_world)
		var t := TreeV2.new()
		t.species = "oak"
		t.stage = 2
		t.tree_seed = 4242
		_world.add_child(t)
		while not t.felled:
			t.chop_hit(Vector3(0, 0, 1))
		for c in _world.get_children():
			if c is FallenTrunk:
				_trunk = c
		_trunk.settled = true
		_trunk.freeze = true
		return false
	if _frames < 3:
		return false
	_trunk.chop_hit(Vector3(0, 0, 1))
	var mi: MeshInstance3D = _trunk._trunk_mi
	_obj("/tmp/timber_trunk.obj", mi.mesh, mi.global_transform)
	for c in _world.get_children():
		var di := c as DroppedItem
		if di != null and String(di.item.get("name", "")) == "Log":
			for cc in di.get_children():
				if cc is MeshInstance3D:
					_obj("/tmp/timber_section.obj", (cc as MeshInstance3D).mesh, (cc as MeshInstance3D).global_transform)
	## branches still shown, as separate objects, to see nothing floats
	var f := FileAccess.open("/tmp/timber_branches.obj", FileAccess.WRITE)
	var base := 1
	for tw in _trunk._twigs:
		var bm := tw["mesh"] as MeshInstance3D
		if not bm.visible:
			continue
		var arr := bm.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		f.store_line("o %s" % bm.name)
		for p in v:
			var w := bm.global_transform * p
			f.store_line("v %f %f %f" % [w.x, w.y, w.z])
		var t := 0
		while t + 2 < idx.size():
			f.store_line("f %d %d %d" % [base + idx[t], base + idx[t + 2], base + idx[t + 1]])
			t += 3
		base += v.size()
	f.close()
	print("probe done: trunk_len %.2f, base %.2f" % [_trunk.trunk_len, _trunk._base])
	quit(0)
	return true
