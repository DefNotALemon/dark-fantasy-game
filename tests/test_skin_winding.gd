extends Node
## In-EDITOR winding probe for the baked creature skins.
##
## tests/SkinTests.gd::t_winding is the real regression gate (run it headless
## with the rest of the suite). This file exists so the MCP test runner can ask
## the same question inside the live editor without a terminal: it bakes a few
## mobs, walks every triangle of each baked mesh, and reports any face whose
## winding disagrees with its own vertex normals — i.e. any surface that
## `cull_back` would make invisible from the outside.


func _report(s) -> Array:
	var am: ArrayMesh = s.mesh_inst.mesh
	if am == null or am.get_surface_count() == 0:
		return [0, 0, 0]
	var arr: Array = am.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var good := 0
	var bad := 0
	var skipped := 0
	var t := 0
	while t + 2 < idx.size():
		var i0: int = idx[t]
		var i1: int = idx[t + 1]
		var i2: int = idx[t + 2]
		t += 3
		var face: Vector3 = (v[i1] - v[i0]).cross(v[i2] - v[i0])
		var want: Vector3 = n[i0] + n[i1] + n[i2]
		if face.length() < 0.000000001 or want.length() < 0.000001:
			skipped += 1
			continue
		## Godot's front face is CLOCKWISE, so a correctly-wound triangle's
		## (v1-v0) x (v2-v0) points AGAINST its vertex normals. Checking this
		## with dot > 0 calls every face of Godot's own BoxMesh inside-out.
		if face.normalized().dot(want.normalized()) < 0.0:
			good += 1
		else:
			bad += 1
	return [good, bad, skipped]


func test_every_skin_face_winds_outward() -> void:
	var host := Node3D.new()
	add_child(host)
	var subjects := {
		"horse": Horse.new(),
		"saddled_horse": SaddledHorse.new(),
		"boar": Boar.new(),
		"goblin": Goblin.new(),
		"ogre": Ogre.new(),
		"dark_knight": DarkKnight.new(),
		"whitetail": Critter.make("whitetail"),
		"moose": Critter.make("moose"),
		"black_bear": Critter.make("black_bear"),
		"hare": Critter.make("hare"),
	}
	var total_bad := 0
	var total_good := 0
	for key in subjects.keys():
		var e: Node3D = subjects[key]
		host.add_child(e)
		var s = e.get_meta("creature_skin") if e.has_meta("creature_skin") else null
		if s == null or s.mesh_inst == null:
			print("[winding] %-14s NO SKIN" % key)
			continue
		var r: Array = _report(s)
		total_good += int(r[0])
		total_bad += int(r[1])
		print("[winding] %-14s outward=%d  INSIDE-OUT=%d  degenerate=%d  segments=%d"
			% [key, r[0], r[1], r[2], s.segment_count()])
	print("[winding] TOTAL outward=%d INSIDE-OUT=%d" % [total_good, total_bad])
	host.queue_free()
	if total_bad > 0:
		push_error("[winding] %d creature faces are inside-out" % total_bad)
