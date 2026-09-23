extends SceneTree
## ===========================================================================
## GorgesTests.gd -- Fort Gorges (scripts/FortGorges.gd)
##
##   godot --headless --path . --script res://tests/GorgesTests.gd
##
## Headless, no renderer, no physics, no terrain: FortGorges.build_flat plus
## keep_probe. Every opening is proved by clear_line. MIN_ASSERTIONS is the
## lost-section floor (an await must not drop the rest; this suite has none).
## ===========================================================================

var _pass := 0
var _fail := 0
const MIN_ASSERTIONS := 55


func ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: %s" % what)


func eq(a, b, what: String) -> void:
	ok(a == b, "%s  (got %s, want %s)" % [what, str(a), str(b)])


func near(a: float, b: float, tol: float, what: String) -> void:
	ok(absf(a - b) <= tol, "%s  (got %.3f, want %.3f +/- %.3f)" % [what, a, b, tol])


func _init() -> void:
	print("GorgesTests")
	var host := Node3D.new()
	root.add_child(host)

	FortGorges.keep_probe = true
	var t0 := Time.get_ticks_msec()
	var f := FortGorges.build_flat(host)
	var build_ms := Time.get_ticks_msec() - t0
	FortGorges.keep_probe = false

	ok(f != null, "the fort builds")
	if f == null:
		_finish()
		return
	print("  built in %d ms, %d solid boxes" % [build_ms, f.probe.size()])

	_geometry(f)
	_frame(f)
	_openings(f)
	_ramparts(f)
	_stair(f)
	_island(f)
	_budget(f, build_ms)
	_statics()

	_finish()


func _geometry(f: FortGorges) -> void:
	var meshes := 0
	var shapes := 0
	for c in f.get_children():
		if c is MeshInstance3D:
			meshes += 1
	for c2 in f.get_node("Stone").get_children():
		if c2 is CollisionShape3D:
			shapes += 1
	ok(meshes > 0 and meshes <= 12, "one mesh per material per layer (%d)" % meshes)
	ok(shapes > 80, "the fort has real collision (%d shapes)" % shapes)
	eq(shapes, f.probe.size(), "every solid box got a collider")

	var empty := 0
	for c3 in f.get_children():
		if c3 is MeshInstance3D and (c3 as MeshInstance3D).mesh == null:
			empty += 1
	eq(empty, 0, "no empty meshes")

	var shell_always := true
	var inner_fades := true
	for c4 in f.get_children():
		if not (c4 is MeshInstance3D):
			continue
		var mi := c4 as MeshInstance3D
		if mi.name.begins_with("Shell_") and mi.visibility_range_end != 0.0:
			shell_always = false
		if mi.name.begins_with("Inner_") and mi.visibility_range_end <= 0.0:
			inner_fades = false
	ok(shell_always, "the shell always draws — it is a landmark")
	ok(inner_fades, "the innards stop drawing at range")

	var mats := {}
	for c5 in f.get_children():
		if c5 is MeshInstance3D:
			mats[(c5 as MeshInstance3D).material_override] = true
	ok(mats.size() <= FortGorges.MATS.size(),
		"at most one material per id, shared (%d)" % mats.size())

	var bad := 0
	var far := 0
	for e in f.probe:
		var b: Dictionary = e
		var s: Vector3 = b["size"]
		var p: Vector3 = b["pos"]
		if is_nan(s.x) or is_nan(s.y) or is_nan(s.z) or is_nan(p.x) or is_nan(p.y) or is_nan(p.z):
			bad += 1
		if s.x <= 0.0 or s.y <= 0.0 or s.z <= 0.0:
			bad += 1
		if absf(p.x) > 80.0 or absf(p.z) > 80.0 or absf(p.y) > 40.0:
			far += 1
	eq(bad, 0, "no NaN and no zero-size boxes")
	eq(far, 0, "nothing escaped the site")


func _frame(_f: FortGorges) -> void:
	var all_out := true
	var all_in := true
	for i in range(FortGorges.CORNERS.size()):
		var a: Vector2 = FortGorges.CORNERS[i]
		var b: Vector2 = FortGorges.CORNERS[(i + 1) % FortGorges.CORNERS.size()]
		var mid := (a + b) * 0.5
		var to_centre := (Vector2.ZERO - mid).normalized()
		if FortGorges._outward(b - a).dot(to_centre) > -0.3:
			all_out = false
		if FortGorges._inward(b - a).dot(to_centre) < 0.3:
			all_in = false
	ok(all_out, "_outward points away from the parade on every face")
	ok(all_in, "_inward points into the parade on every face")

	for i2 in range(FortGorges.CORNERS.size()):
		var a2: Vector2 = FortGorges.CORNERS[i2]
		var b2: Vector2 = FortGorges.CORNERS[(i2 + 1) % FortGorges.CORNERS.size()]
		var d := b2 - a2
		var yaw := FortGorges._yaw_of(d)
		var bz := Basis.from_euler(Vector3(0.0, yaw, 0.0)) * Vector3(0.0, 0.0, 1.0)
		var bx := Basis.from_euler(Vector3(0.0, yaw, 0.0)) * Vector3(1.0, 0.0, 0.0)
		near(Vector2(bz.x, bz.z).dot(d.normalized()), 1.0, 0.001,
			"face %d: local +Z runs along the wall" % i2)
		near(Vector2(bx.x, bx.z).dot(FortGorges._outward(d)), 1.0, 0.001,
			"face %d: local +X is the outward normal" % i2)

	eq(FortGorges.CORNERS.size(), 12, "twelve corners: a hex-star, not Knox's pentagon")
	var west_ok := true
	for face: int in FortGorges.CASEMATE_FACES:
		var a3: Vector2 = FortGorges.CORNERS[face]
		var b3: Vector2 = FortGorges.CORNERS[(face + 1) % FortGorges.CORNERS.size()]
		if FortGorges._outward(b3 - a3).x >= -0.3:
			west_ok = false
	ok(west_ok, "every casemate face looks west, toward Portland")
	var go: Vector2 = FortGorges.CORNERS[FortGorges.GATE_FACE]
	var gb: Vector2 = FortGorges.CORNERS[(FortGorges.GATE_FACE + 1) % FortGorges.CORNERS.size()]
	ok(FortGorges._outward(gb - go).x > 0.3, "the sally looks east, away from the quay")


func _openings(f: FortGorges) -> void:
	ok(not f.solid_at(Vector3(0.0, 1.4, 0.0)), "the parade is open air at head height")
	ok(not f.solid_at(Vector3(-4.0, 1.2, 4.0)), "...and off-centre too")
	ok(f.solid_at(Vector3(0.0, -0.5, 0.0)), "the paving under it is stone")

	var ports := 0
	var pierced := 0
	for face: int in FortGorges.CASEMATE_FACES:
		var a: Vector2 = FortGorges.CORNERS[face]
		var b: Vector2 = FortGorges.CORNERS[(face + 1) % FortGorges.CORNERS.size()]
		var d := b - a
		var length := d.length()
		var dir := d / length
		var out := FortGorges._outward(d)
		for t: float in FortGorges.casemate_ts(a, b):
			ports += 1
			var on_wall := a + dir * t
			var y := (FortGorges.PORT_SILL + FortGorges.PORT_HEAD) * 0.5
			var inside := on_wall + out * (-FortGorges.WALL_T - 1.2)
			var outside := on_wall + out * 4.0
			if f.clear_line(Vector3(inside.x, y, inside.y),
					Vector3(outside.x, y, outside.y), 0.2):
				pierced += 1
	eq(pierced, ports, "every gun port is a hole right through the curtain")
	ok(ports >= 6, "six or more casemates looking at Portland (%d)" % ports)

	var solid_between := 0
	for face2: int in FortGorges.CASEMATE_FACES:
		var a2: Vector2 = FortGorges.CORNERS[face2]
		var b2: Vector2 = FortGorges.CORNERS[(face2 + 1) % FortGorges.CORNERS.size()]
		var d2 := b2 - a2
		var dir2 := d2 / d2.length()
		var out2 := FortGorges._outward(d2)
		var ts2 := FortGorges.casemate_ts(a2, b2)
		for k2 in range(ts2.size() - 1):
			var mid := a2 + dir2 * ((ts2[k2] + ts2[k2 + 1]) * 0.5)
			var probe_p := mid + out2 * (-FortGorges.WALL_T * 0.5)
			if f.solid_at(Vector3(probe_p.x, 2.0, probe_p.y)):
				solid_between += 1
	ok(solid_between >= 4, "the pier between each pair of ports is solid (%d)" % solid_between)

	var ga: Vector2 = FortGorges.CORNERS[FortGorges.GATE_FACE]
	var gbb: Vector2 = FortGorges.CORNERS[(FortGorges.GATE_FACE + 1) % FortGorges.CORNERS.size()]
	var gmid := (ga + gbb) * 0.5
	var gout := FortGorges._outward(gbb - ga)
	var gin := FortGorges._inward(gbb - ga)
	var from := gmid + gout * (FortGorges.WALL_T * 0.5 + 1.0)
	var to := gmid + gin * 8.0
	ok(f.clear_line(Vector3(from.x, 1.1, from.y), Vector3(to.x, 1.1, to.y), 0.2),
		"the sally port is open from the landing to the parade")
	var beside := gmid + (gbb - ga).normalized() * 3.2 + gin * 1.2
	ok(f.solid_at(Vector3(beside.x, 1.5, beside.y)), "the gate jamb beside it is stone")

	var reached := 0
	for face3: int in FortGorges.CASEMATE_FACES:
		var a3: Vector2 = FortGorges.CORNERS[face3]
		var b3: Vector2 = FortGorges.CORNERS[(face3 + 1) % FortGorges.CORNERS.size()]
		var d3 := b3 - a3
		var dir3 := d3 / d3.length()
		var inw := FortGorges._inward(d3)
		for t3: float in FortGorges.casemate_ts(a3, b3):
			var c := a3 + dir3 * t3 \
				+ inw * (FortGorges.WALL_T * 0.5 + FortGorges.CASEMATE_D * 0.5)
			var parade := c + inw * (FortGorges.CASEMATE_D * 0.5 + 1.0)
			var room := c + inw * 0.35
			if f.clear_line(Vector3(parade.x, 1.2, parade.y), Vector3(room.x, 1.2, room.y), 0.2):
				reached += 1
	ok(reached >= 6, "you can walk into the casemates off the parade (%d)" % reached)


func _ramparts(f: FortGorges) -> void:
	var walkable := 0
	var faces := FortGorges.CORNERS.size()
	for i in range(faces):
		var a: Vector2 = FortGorges.CORNERS[i]
		var b: Vector2 = FortGorges.CORNERS[(i + 1) % faces]
		var d := b - a
		var inw := FortGorges._inward(d)
		var open_here := true
		for k in range(1, 5):
			var p := a + d * (float(k) / 5.0) + inw * (FortGorges.WALL_T * 0.5 + FortGorges.WALK * 0.45)
			if f.solid_at(Vector3(p.x, FortGorges.RAMPART_Y + 0.7, p.y)):
				open_here = false
		if open_here:
			walkable += 1
		var mid := (a + b) * 0.5 + inw * (FortGorges.WALL_T * 0.5 + FortGorges.WALK * 0.45)
		ok(f.solid_at(Vector3(mid.x, FortGorges.RAMPART_Y - 0.3, mid.y)),
			"face %d has a rampart walk under foot" % i)
	eq(walkable, faces, "every face's rampart walk is clear to walk")

	var merloned := 0
	for i2 in range(faces):
		var a2: Vector2 = FortGorges.CORNERS[i2]
		var b2: Vector2 = FortGorges.CORNERS[(i2 + 1) % faces]
		var d2 := b2 - a2
		var length := d2.length()
		var dir := d2 / length
		var out := FortGorges._outward(d2)
		var merlons := maxi(3, int(round(length / 3.2)))
		var step := length / float(merlons)
		var hits := 0
		for m in range(merlons):
			var p := a2 + dir * ((float(m) + 0.5) * step) + out * (-FortGorges.WALL_T * 0.5)
			if f.solid_at(Vector3(p.x, FortGorges.RAMPART_Y + 0.9, p.y)):
				hits += 1
		if hits >= merlons - 1:
			merloned += 1
	eq(merloned, faces, "every face has its merlons up")


func _stair(f: FortGorges) -> void:
	var a: Vector2 = FortGorges.CORNERS[FortGorges.STAIR_FACE]
	var b: Vector2 = FortGorges.CORNERS[(FortGorges.STAIR_FACE + 1) % FortGorges.CORNERS.size()]
	var inw := FortGorges._inward(b - a)
	var top := (a + b) * 0.5 + inw * (FortGorges.WALL_T + 1.5)
	var base := top + inw * 7.5
	var blocked := 0
	var checked := 0
	for i in range(2, 11):
		var t := float(i) / 12.0
		var on := Vector3(base.x, -0.2, base.y).lerp(
			Vector3(top.x, FortGorges.RAMPART_Y - 0.55, top.y), t)
		checked += 1
		if f.solid_at(on + Vector3(0.0, 1.15, 0.0)):
			blocked += 1
	ok(checked >= 8, "the stair has a real run of treads (%d)" % checked)
	ok(float(blocked) / float(checked) < 0.2,
		"the stair has headroom from the parade onto the rampart")
	var midp := Vector3(base.x, -0.2, base.y).lerp(Vector3(top.x, FortGorges.RAMPART_Y - 0.55, top.y), 0.5)
	ok(f.solid_at(midp + Vector3(0.0, -0.05, 0.0)),
		"the stair treads are stone under foot")


func _island(f: FortGorges) -> void:
	ok(f.solid_at(Vector3(0.0, -2.0, 0.0)), "the island fill is under the parade")
	ok(f.solid_at(Vector3(0.0, FortGorges.ISLAND_BOT + 0.4, 0.0)),
		"the island reaches its own bottom slab")
	ok(FortGorges.ISLAND_BOT > -60.0 + 20.0, "the island stays above World's -60 trapdoor")
	ok(not FortGorges.PUNCHES, "open water: granite island, no punched hole")


func _budget(f: FortGorges, build_ms: int) -> void:
	ok(f.probe.size() < 1200, "under twelve hundred solid boxes (%d)" % f.probe.size())
	ok(build_ms < 4000, "it builds in under four seconds headless (%d ms)" % build_ms)
	var meshes := 0
	var tris := 0
	for c in f.get_children():
		if c is MeshInstance3D:
			meshes += 1
			var m := (c as MeshInstance3D).mesh
			if m != null and m.get_surface_count() > 0:
				tris += m.surface_get_array_len(0) / 3
	ok(meshes <= 12, "under twelve draw calls (%d)" % meshes)
	ok(tris > 800, "the fort has real geometry (%d triangles)" % tris)
	print("  %d triangles across %d meshes" % [tris, meshes])


func _statics() -> void:
	ok(FortGorges.contains(Vector3(FortGorges.SITE_X, 0.0, FortGorges.SITE_Z)),
		"the centre is inside the fort bounds")
	ok(not FortGorges.contains(Vector3(FortGorges.SITE_X + 400.0, 0.0, FortGorges.SITE_Z)),
		"a point 400 m east is not")
	ok(not FortGorges.contains(Vector3.ZERO), "and neither is the spawn valley")
	ok(absf(FortGorges.SITE_X) > 80.0 and absf(FortGorges.SITE_Z) > 200.0,
		"the site is nowhere near the spawn hole")
	var d := Vector2(FortGorges.SITE_X - FortGorges.PORTLAND.x,
		FortGorges.SITE_Z - FortGorges.PORTLAND.y).length()
	ok(d > 210.0, "the star sits outside Portland's 190 m city pad (%.0f m)" % d)
	ok(d < 360.0, "and still close enough to be a harbor landmark (%.0f m)" % d)
	near(FortGorges.SITE_Z, FortGorges.PORTLAND.y, 80.0,
		"due east of the Old Port, same harbor latitude")
	var arr := FortGorges.arrival()
	ok(FortGorges.contains(arr), "the arrival point is on the parade")

	Overworld.clear_holes()
	var before := Overworld._extra_holes.size()
	ok(FortGorges.raise_fort(Node3D.new()) == null,
		"raise_fort refuses without loaded terrain")
	eq(Overworld._extra_holes.size(), before, "and it still does not punch a hole")
	ok(not Overworld.in_hole(Vector3(FortGorges.SITE_X, 0.0, FortGorges.SITE_Z)),
		"the harbor site is not a punched rect")
	Overworld.clear_holes()


func _finish() -> void:
	print("GorgesTests: %d passed, %d failed" % [_pass, _fail])
	if _pass + _fail < MIN_ASSERTIONS:
		print("  LOST A SECTION: only %d assertions ran (floor %d)" % [_pass + _fail, MIN_ASSERTIONS])
		_fail += 1
	quit(1 if _fail > 0 else 0)
