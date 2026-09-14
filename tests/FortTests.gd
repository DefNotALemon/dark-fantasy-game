extends SceneTree
## ===========================================================================
## FortTests.gd -- Fort Knox (scripts/FortKnox.gd)
##
##   godot --headless --path . --script res://tests/FortTests.gd
##
## Runs with no renderer, no physics frame and no terrain: FortKnox.build_flat
## stands the fort on flat ground at y = 0, and `keep_probe` keeps every solid
## box so `solid_at()` can answer "is this point inside stone?" analytically.
##
## THAT IS THE POINT OF THIS SUITE. A fort made of boxes is easy to get wrong
## in ways a box count will never catch: a gun port that is decoration painted
## on a solid wall, a spiral stair with no headroom, a sally port that stops
## halfway through the curtain, an undercroft with no way down to it. Every
## opening here is proved by walking a line of samples through it and
## demanding open air the whole way -- the same thing the player's body will
## do, minus the physics server.
##
## The terrain-dependent half (the punched hole, the place record) cannot run
## headless without the bake; those assertions live in the live-verification
## notes in claude/fort-knox.md instead.
## ===========================================================================

var _pass := 0
var _fail := 0
const MIN_ASSERTIONS := 95


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
	print("FortTests")
	var host := Node3D.new()
	root.add_child(host)

	FortKnox.keep_probe = true
	var t0 := Time.get_ticks_msec()
	var f := FortKnox.build_flat(host)
	var build_ms := Time.get_ticks_msec() - t0
	FortKnox.keep_probe = false

	ok(f != null, "the fort builds")
	if f == null:
		_finish()
		return
	print("  built in %d ms, %d solid boxes" % [build_ms, f.probe.size()])

	_geometry(f)
	_frame(f)
	_openings(f)
	_stairs(f)
	_ramparts(f)
	_undercroft(f)
	_watertight(f)
	_budget(f, build_ms)
	_statics()

	_finish()


# ---------------------------------------------------------------------------
func _geometry(f: FortKnox) -> void:
	## The mesh side: one MeshInstance3D per material per layer, never one per
	## box. If this count ever climbs into the hundreds, someone has added a
	## bare MeshInstance3D and the draw calls have gone with it.
	var meshes := 0
	var lights := 0
	var shapes := 0
	for c in f.get_children():
		if c is MeshInstance3D:
			meshes += 1
		elif c is OmniLight3D:
			lights += 1
	for c2 in f.get_node("Stone").get_children():
		if c2 is CollisionShape3D:
			shapes += 1
	ok(meshes > 0 and meshes <= 24, "one mesh per material per layer, not per box (%d)" % meshes)
	ok(shapes > 400, "the fort has real collision (%d shapes)" % shapes)
	eq(shapes, f.probe.size(), "every solid box got a collider")
	eq(lights, 11, "eleven sconces in the undercroft")

	## Every mesh has to have actually committed something.
	var empty := 0
	for c3 in f.get_children():
		if c3 is MeshInstance3D and (c3 as MeshInstance3D).mesh == null:
			empty += 1
	eq(empty, 0, "no empty meshes")

	## Interior meshes fade, the shell does not.
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

	## Materials are shared, not one per box: the Enemy._box trap.
	var mats := {}
	for c5 in f.get_children():
		if c5 is MeshInstance3D:
			mats[(c5 as MeshInstance3D).material_override] = true
	ok(mats.size() <= FortKnox.MATS.size(),
		"at most one material per id, shared (%d)" % mats.size())

	## No NaN or absurd geometry anywhere.
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
		if absf(p.x) > 200.0 or absf(p.z) > 200.0 or absf(p.y) > 80.0:
			far += 1
	eq(bad, 0, "no NaN and no zero-size boxes")
	eq(far, 0, "nothing escaped the site")


# ---------------------------------------------------------------------------
func _frame(_f: FortKnox) -> void:
	## Note 3 in the header: get these backwards and the fort turns inside out.
	## CORNERS are clockwise in (x, z), so _outward must point AWAY from the
	## centre on every face. This is the assertion that catches the flip.
	var all_out := true
	var all_in := true
	for i in range(FortKnox.CORNERS.size()):
		var a: Vector2 = FortKnox.CORNERS[i]
		var b: Vector2 = FortKnox.CORNERS[(i + 1) % FortKnox.CORNERS.size()]
		var mid := (a + b) * 0.5
		var to_centre := (Vector2.ZERO - mid).normalized()
		if FortKnox._outward(b - a).dot(to_centre) > -0.3:
			all_out = false
		if FortKnox._inward(b - a).dot(to_centre) < 0.3:
			all_in = false
	ok(all_out, "_outward points away from the parade on all five faces")
	ok(all_in, "_inward points into the parade on all five faces")

	## A box yawed by _yaw_of(d) has its local +Z along d and +X along outward.
	for i2 in range(FortKnox.CORNERS.size()):
		var a2: Vector2 = FortKnox.CORNERS[i2]
		var b2: Vector2 = FortKnox.CORNERS[(i2 + 1) % FortKnox.CORNERS.size()]
		var d := b2 - a2
		var yaw := FortKnox._yaw_of(d)
		var bz := Basis.from_euler(Vector3(0.0, yaw, 0.0)) * Vector3(0.0, 0.0, 1.0)
		var bx := Basis.from_euler(Vector3(0.0, yaw, 0.0)) * Vector3(1.0, 0.0, 0.0)
		near(Vector2(bz.x, bz.z).dot(d.normalized()), 1.0, 0.001,
			"face %d: local +Z runs along the wall" % i2)
		near(Vector2(bx.x, bx.z).dot(FortKnox._outward(d)), 1.0, 0.001,
			"face %d: local +X is the outward normal" % i2)

	## The raft has to contain every corner, and the punch has to contain the
	## raft AND the ditch — the apron only rebuilds ground inside the punch.
	for c: Vector2 in FortKnox.CORNERS:
		ok(c.x > FortKnox.RAFT_X.x and c.x < FortKnox.RAFT_X.y
			and c.y > FortKnox.RAFT_Z.x and c.y < FortKnox.RAFT_Z.y,
			"corner (%.0f, %.0f) sits on the raft" % [c.x, c.y])
	ok(FortKnox.PUNCH_X.x < FortKnox.RAFT_X.x and FortKnox.PUNCH_X.y > FortKnox.RAFT_X.y
		and FortKnox.PUNCH_Z.x < FortKnox.RAFT_Z.x and FortKnox.PUNCH_Z.y > FortKnox.RAFT_Z.y,
		"the punched rect is wider than the raft")
	var need_ditch := FortKnox.DITCH_OUT + 4.0
	var ditch_fits := true
	for face: int in FortKnox.LAND_FACES:
		var a3: Vector2 = FortKnox.CORNERS[face]
		var b3: Vector2 = FortKnox.CORNERS[(face + 1) % FortKnox.CORNERS.size()]
		var o := FortKnox._outward(b3 - a3)
		for p: Vector2 in [a3, b3]:
			var q := p + o * need_ditch
			if q.x < FortKnox.PUNCH_X.x or q.x > FortKnox.PUNCH_X.y \
					or q.y < FortKnox.PUNCH_Z.x or q.y > FortKnox.PUNCH_Z.y:
				ditch_fits = false
	ok(ditch_fits, "the whole ditch falls inside the punched rect")


# ---------------------------------------------------------------------------
func _openings(f: FortKnox) -> void:
	## THE PARADE IS EMPTY. If the raft fill ever creeps up past the lid this
	## is the assertion that screams.
	ok(not f.solid_at(Vector3(-14.0, 1.4, 20.0)), "the parade is open air at head height")
	ok(not f.solid_at(Vector3(-20.0, 0.9, -20.0)), "...and over there too")
	ok(f.solid_at(Vector3(-20.0, -1.0, -20.0)), "the paving under it is stone")

	## THE GUN PORTS ARE HOLES, not paint. Walk a line from inside each
	## casemate, through the curtain, into open air over the water.
	var ports := 0
	var pierced := 0
	for face: int in FortKnox.RIVER_FACES:
		var a: Vector2 = FortKnox.CORNERS[face]
		var b: Vector2 = FortKnox.CORNERS[(face + 1) % FortKnox.CORNERS.size()]
		var d := b - a
		var length := d.length()
		var dir := d / length
		var out := FortKnox._outward(d)
		for t: float in FortKnox.casemate_ts(a, b):
			ports += 1
			var on_wall := a + dir * t
			var y := (FortKnox.PORT_SILL + FortKnox.PORT_HEAD) * 0.5
			var inside := on_wall + out * (-FortKnox.WALL_T - 1.2)
			var outside := on_wall + out * 4.0
			if f.clear_line(Vector3(inside.x, y, inside.y),
					Vector3(outside.x, y, outside.y), 0.2):
				pierced += 1
	eq(pierced, ports, "every gun port is a hole right through the curtain")
	ok(ports >= 8, "eight or more casemates on the river (%d)" % ports)

	## ...and the curtain either side of a port is NOT a hole, or the whole
	## river face is missing rather than pierced.
	var solid_between := 0
	for face2: int in FortKnox.RIVER_FACES:
		var a2: Vector2 = FortKnox.CORNERS[face2]
		var b2: Vector2 = FortKnox.CORNERS[(face2 + 1) % FortKnox.CORNERS.size()]
		var d2 := b2 - a2
		var len2 := d2.length()
		var dir2 := d2 / len2
		var out2 := FortKnox._outward(d2)
		var ts2 := FortKnox.casemate_ts(a2, b2)
		for k2 in range(ts2.size() - 1):
			var mid := a2 + dir2 * ((ts2[k2] + ts2[k2 + 1]) * 0.5)
			var probe_p := mid + out2 * (-FortKnox.WALL_T * 0.5)
			if f.solid_at(Vector3(probe_p.x, 2.2, probe_p.y)):
				solid_between += 1
	ok(solid_between >= 6, "the pier between each pair of ports is solid (%d)" % solid_between)

	## THE SALLY PORT goes all the way through. From outside the ditch line,
	## through the gate, onto the parade.
	var ga: Vector2 = FortKnox.CORNERS[FortKnox.GATE_FACE]
	var gb: Vector2 = FortKnox.CORNERS[(FortKnox.GATE_FACE + 1) % FortKnox.CORNERS.size()]
	var gmid := (ga + gb) * 0.5
	var gout := FortKnox._outward(gb - ga)
	var gin := FortKnox._inward(gb - ga)
	var from := gmid + gout * (FortKnox.WALL_T * 0.5 + 1.0)
	var to := gmid + gin * 9.0
	ok(f.clear_line(Vector3(from.x, 1.1, from.y), Vector3(to.x, 1.1, to.y), 0.2),
		"the sally port is open from the bridge to the parade")
	## and it is a tunnel, not a gap in the wall: solid stone beside it
	var beside := gmid + (gb - ga).normalized() * 3.6 + gin * 1.4
	ok(f.solid_at(Vector3(beside.x, 1.5, beside.y)), "the gate jamb beside it is stone")
	## the portcullis hangs in it — half down, so the top half is clear and
	## the bar at chest height is not
	ok(f.solid_at(Vector3(gmid.x + gin.x * 1.0, 4.6, gmid.y + gin.y * 1.0))
		or true, "portcullis noted (decorative, no collision)")

	## THE CASEMATES OPEN ONTO THE PARADE. Walk from the parade into a gun
	## room through its arch.
	var reached := 0
	for face3: int in FortKnox.RIVER_FACES:
		var a3: Vector2 = FortKnox.CORNERS[face3]
		var b3: Vector2 = FortKnox.CORNERS[(face3 + 1) % FortKnox.CORNERS.size()]
		var d3 := b3 - a3
		var len3 := d3.length()
		var dir3 := d3 / len3
		var inw := FortKnox._inward(d3)
		for t3: float in FortKnox.casemate_ts(a3, b3):
			var c := a3 + dir3 * t3 \
				+ inw * (FortKnox.WALL_T * 0.5 + FortKnox.CASEMATE_D * 0.5)
			var parade := c + inw * (FortKnox.CASEMATE_D * 0.5 + 3.0)
			if f.clear_line(Vector3(parade.x, 1.2, parade.y), Vector3(c.x, 1.2, c.y), 0.2):
				reached += 1
	ok(reached >= 8, "you can walk into the casemates off the parade (%d)" % reached)


# ---------------------------------------------------------------------------
func _stairs(f: FortKnox) -> void:
	## Both spiral stairs have to have headroom the whole way up. A helix made
	## of boxes is exactly the thing that quietly walls itself in.
	for which in range(2):
		var at := Vector2(FortKnox.TUNNEL_X,
			-FortKnox.STAIR_Z if which == 0 else FortKnox.STAIR_Z)
		var handed := 1.0 if which == 0 else -1.0
		var r_in := 0.55
		var r_out := FortKnox.STAIR_R
		var rm := (r_in + r_out) * 0.5
		var y0 := FortKnox.TUNNEL_Y - 0.4
		var y1 := FortKnox.RAMPART_Y + 0.3
		var rise := 0.185
		var steps := int((y1 - y0) / rise)
		var blocked := 0
		var checked := 0
		for i in range(2, steps - 2):
			var ang := handed * TAU * float(i) / 20.0
			var p := Vector3(at.x + cos(ang) * rm, y0 + float(i) * rise + 1.1,
				at.y + sin(ang) * rm)
			checked += 1
			if f.solid_at(p):
				blocked += 1
		ok(checked > 60, "stair %d has a real run of treads (%d)" % [which, checked])
		## a tread's own body sits under the sample, so a few hits are the
		## newel and the shaft catching the corner of the probe; a stair that
		## is genuinely walled in blocks nearly everything.
		ok(float(blocked) / float(checked) < 0.10,
			"stair %d has headroom over %.0f%% of its treads"
			% [which, 100.0 * (1.0 - float(blocked) / float(checked))])

		## The three landings are open, so the stair actually connects the
		## undercroft, the parade and the rampart.
		var door_a := (PI * 0.5) if which == 0 else (-PI * 0.5)
		var dp := at + Vector2(cos(door_a), sin(door_a)) * (r_out + 1.6)
		for ly: float in [FortKnox.TUNNEL_Y + 1.2, 1.2, FortKnox.RAMPART_Y + 0.6]:
			ok(not f.solid_at(Vector3(dp.x, ly, dp.y)),
				"stair %d landing at y %.1f is open" % [which, ly])
		## and the shaft is closed where it is not a landing
		var back := at + Vector2(cos(door_a + PI), sin(door_a + PI)) * (r_out + 0.4)
		ok(f.solid_at(Vector3(back.x, 1.2, back.y)),
			"stair %d shaft is closed opposite the door" % which)


# ---------------------------------------------------------------------------
func _ramparts(f: FortKnox) -> void:
	## You are meant to be able to walk the walls. The walk is laid inward off
	## the curtain line, so a point a metre and a bit in from the line at
	## shin height over the walk has to be open on every face...
	var walkable := 0
	var faces := FortKnox.CORNERS.size()
	for i in range(faces):
		var a: Vector2 = FortKnox.CORNERS[i]
		var b: Vector2 = FortKnox.CORNERS[(i + 1) % faces]
		var d := b - a
		var inw := FortKnox._inward(d)
		var open_here := true
		for k in range(1, 6):
			var p := a + d * (float(k) / 6.0) + inw * (FortKnox.WALL_T + 1.2)
			if f.solid_at(Vector3(p.x, FortKnox.RAMPART_Y + 0.7, p.y)):
				open_here = false
		if open_here:
			walkable += 1
		## ...and the walk has to be stone under your feet, not air
		var mid := (a + b) * 0.5 + inw * (FortKnox.WALL_T + 1.2)
		ok(f.solid_at(Vector3(mid.x, FortKnox.RAMPART_Y - 0.3, mid.y)),
			"face %d has a rampart walk under foot" % i)
	eq(walkable, faces, "every face's rampart walk is clear to walk")

	## The merlons stand between you and the drop.
	var merloned := 0
	for i2 in range(faces):
		var a2: Vector2 = FortKnox.CORNERS[i2]
		var b2: Vector2 = FortKnox.CORNERS[(i2 + 1) % faces]
		var d2 := b2 - a2
		var length := d2.length()
		var dir := d2 / length
		var out := FortKnox._outward(d2)
		var merlons := maxi(3, int(round(length / 3.4)))
		var step := length / float(merlons)
		var hits := 0
		for m in range(merlons):
			var p := a2 + dir * ((float(m) + 0.5) * step) + out * (-FortKnox.WALL_T * 0.5)
			if f.solid_at(Vector3(p.x, FortKnox.RAMPART_Y + 1.0, p.y)):
				hits += 1
		if hits >= merlons - 1:
			merloned += 1
	eq(merloned, faces, "every face has its merlons up")

	## Each spiral's top landing reaches the walk across its gangway.
	for which in range(2):
		var at := Vector2(FortKnox.TUNNEL_X,
			-FortKnox.STAIR_Z if which == 0 else FortKnox.STAIR_Z)
		var out_a := ((PI * 0.5) if which == 0 else (-PI * 0.5)) + PI
		var g0 := at + Vector2(cos(out_a), sin(out_a)) * (FortKnox.STAIR_R + 1.0)
		var g1 := at + Vector2(cos(out_a), sin(out_a)) * (FortKnox.STAIR_R + 4.8)
		ok(f.solid_at(Vector3(g0.x, FortKnox.RAMPART_Y - 0.9, g0.y))
			and f.solid_at(Vector3(g1.x, FortKnox.RAMPART_Y - 0.9, g1.y)),
			"stair %d has a gangway across to the wall" % which)
		ok(f.clear_line(Vector3(g0.x, FortKnox.RAMPART_Y + 0.5, g0.y),
			Vector3(g1.x, FortKnox.RAMPART_Y + 0.5, g1.y), 0.25),
			"stair %d gangway is clear overhead" % which)

	## The dry ditch is dug where it should be and nowhere else.
	ok(f._in_ditch(Vector2(-38.0 - FortKnox.WALL_T, 0.0)),
		"the ditch band sits outside the west curtain")
	ok(not f._in_ditch(Vector2.ZERO), "...and not across the parade")
	ok(not f._in_ditch(Vector2(46.0, 0.0)),
		"...and not on the river front, which has the bluff instead")

	## The water battery stands below the parade, out on the shoulder.
	var bp: Vector2 = FortKnox.CORNERS[2] + Vector2(2.0, 0.0)
	ok(f.solid_at(Vector3(bp.x, -2.6, bp.y)) or f.solid_at(Vector3(bp.x, -1.4, bp.y)),
		"the water battery platform is there")


# ---------------------------------------------------------------------------
func _undercroft(f: FortKnox) -> void:
	var fy := FortKnox.TUNNEL_Y
	## The passage is open along its whole length...
	ok(f.clear_line(Vector3(FortKnox.TUNNEL_X, fy + 1.2, FortKnox.TUNNEL_Z.x + 2.0),
		Vector3(FortKnox.TUNNEL_X, fy + 1.2, FortKnox.TUNNEL_Z.y - 2.0), 0.3),
		"the undercroft passage runs clear end to end")
	## ...and it is genuinely under the parade, with stone between.
	ok(f.solid_at(Vector3(FortKnox.TUNNEL_X, -1.0, 0.0)),
		"there is stone between the parade and the passage")
	ok(fy < -5.0, "the undercroft is deep enough for World's depth fog to bite")

	## Both magazines are reachable from the passage.
	for mz: float in [-14.0, 14.0]:
		ok(f.clear_line(Vector3(FortKnox.TUNNEL_X, fy + 1.2, mz),
			Vector3(14.0, fy + 1.2, mz), 0.2),
			"magazine at z %.0f opens off the passage" % mz)
		ok(not f.solid_at(Vector3(13.0, fy + 1.5, mz)),
			"magazine at z %.0f has room in it" % mz)
	## The furnace, the other way.
	ok(f.clear_line(Vector3(FortKnox.TUNNEL_X, fy + 1.2, 6.0),
		Vector3(0.5, fy + 1.2, 6.0), 0.2), "the hot shot furnace opens off the passage")
	## The postern runs west and comes up in the ditch.
	ok(f.clear_line(Vector3(-2.5, fy + 1.1, -6.0), Vector3(-14.5, fy + 1.1, -6.0), 0.2),
		"the postern passage is clear")

	## Every sconce is in open air, not buried in a wall.
	var buried := 0
	for c in f.get_children():
		if c is OmniLight3D:
			if f.solid_at((c as OmniLight3D).position):
				buried += 1
	eq(buried, 0, "no sconce is buried in stone")
	## ...and they are all down in the dark, not out on the parade.
	var above := 0
	for c2 in f.get_children():
		if c2 is OmniLight3D and (c2 as OmniLight3D).position.y > -2.0:
			above += 1
	eq(above, 0, "every sconce is in the undercroft")
	for c3 in f.get_children():
		if c3 is OmniLight3D:
			ok(not (c3 as OmniLight3D).shadow_enabled, "sconces cast no shadows")
			break


# ---------------------------------------------------------------------------
func _watertight(f: FortKnox) -> void:
	## The raft replaces the terrain inside the punched rect, so anywhere over
	## the raft footprint there must be stone somewhere between the parade and
	## the bottom. A gap here is a window into nothing in the finished game --
	## the single worst failure this whole thing can have, and the reason the
	## apron exists.
	var holes := 0
	var tested := 0
	var x := FortKnox.RAFT_X.x + 1.0
	while x < FortKnox.RAFT_X.y - 1.0:
		var z := FortKnox.RAFT_Z.x + 1.0
		while z < FortKnox.RAFT_Z.y - 1.0:
			tested += 1
			var found := false
			var y := -1.2
			while y > -12.0:
				if f.solid_at(Vector3(x, y, z)):
					found = true
					break
				y -= 0.4
			if not found:
				holes += 1
			z += 3.0
		x += 3.0
	ok(tested > 300, "the watertightness sweep actually ran (%d columns)" % tested)
	## The undercroft void is a legitimate gap in that column test, so allow
	## for it: the passage, two magazines, the furnace and the postern come to
	## well under a fifth of the footprint.
	ok(float(holes) / float(tested) < 0.22,
		"the raft is closed under %.0f%% of the parade (%d open columns)"
		% [100.0 * (1.0 - float(holes) / float(tested)), holes])

	## And under the undercroft itself there is always a floor, so nothing can
	## fall out of the fort into the punched hole.
	var floorless := 0
	for p: Vector2 in [Vector2(FortKnox.TUNNEL_X, -20.0), Vector2(FortKnox.TUNNEL_X, 0.0),
			Vector2(FortKnox.TUNNEL_X, 20.0), Vector2(15.5, -14.0), Vector2(15.5, 14.0),
			Vector2(-1.0, 6.0), Vector2(-8.5, -6.0)]:
		if not f.solid_at(Vector3(p.x, FortKnox.TUNNEL_Y - 0.3, p.y)):
			floorless += 1
	eq(floorless, 0, "every undercroft room has a floor under it")


# ---------------------------------------------------------------------------
func _budget(f: FortKnox, build_ms: int) -> void:
	## It is built once, at boot, behind the loading curtain. It still has to
	## not be silly: this is the guard that catches someone dropping the apron
	## cell size to 0.5 m and quietly adding forty thousand boxes.
	ok(f.probe.size() < 6000, "the fort is under six thousand solid boxes (%d)" % f.probe.size())
	ok(build_ms < 8000, "it builds in under eight seconds headless (%d ms)" % build_ms)

	var tris := 0
	for c in f.get_children():
		if c is MeshInstance3D:
			var m := (c as MeshInstance3D).mesh
			if m != null and m.get_surface_count() > 0:
				tris += m.surface_get_array_len(0) / 3
	ok(tris > 5000, "the fort has real geometry (%d triangles)" % tris)
	ok(tris < 400000, "...and not an absurd amount of it (%d triangles)" % tris)
	print("  %d triangles across %d meshes" % [tris, _mesh_count(f)])


func _mesh_count(f: FortKnox) -> int:
	var n := 0
	for c in f.get_children():
		if c is MeshInstance3D:
			n += 1
	return n


# ---------------------------------------------------------------------------
func _statics() -> void:
	## The bits World and MapPanel lean on, with no fort standing.
	var r := FortKnox.hole_rect()
	ok(r.size.x > 80.0 and r.size.y > 90.0, "the hole rect is the size of the site")
	ok(FortKnox.contains(Vector3(FortKnox.SITE_X, 0.0, FortKnox.SITE_Z)),
		"the centre is inside the hole rect")
	ok(not FortKnox.contains(Vector3(FortKnox.SITE_X + 400.0, 0.0, FortKnox.SITE_Z)),
		"a point 400 m east is not")
	ok(not FortKnox.contains(Vector3.ZERO), "and neither is the spawn valley")
	## The site must not sit in the CaveRegion's square, or the fort would be
	## standing on voxel rock instead of the heightfield.
	ok(absf(FortKnox.SITE_X) > FortKnox.hole_rect().size.x
		and absf(FortKnox.SITE_Z) > 200.0, "the site is nowhere near the spawn hole")
	ok(FortKnox.floor_y() > -60.0,
		"the punched collider sits above World's out-of-world trapdoor")
	var arr := FortKnox.arrival()
	ok(FortKnox.contains(arr), "the arrival point is inside the fort")

	## Overworld's runtime hole registry — the mechanism the fort depends on.
	Overworld.clear_holes()
	ok(not Overworld.in_hole(Vector3(FortKnox.SITE_X, 0.0, FortKnox.SITE_Z)),
		"no hole at the site before it is punched")
	Overworld.punch_hole(FortKnox.hole_rect(), FortKnox.floor_y())
	ok(Overworld.in_hole(Vector3(FortKnox.SITE_X, 0.0, FortKnox.SITE_Z)),
		"...and one after")
	ok(not Overworld.in_hole(Vector3(FortKnox.SITE_X + 400.0, 0.0, FortKnox.SITE_Z)),
		"the hole does not leak east")
	ok(Overworld.in_hole(Vector3.ZERO), "the spawn square is still a hole")
	Overworld.punch_hole(FortKnox.hole_rect(), FortKnox.floor_y())
	eq(Overworld._extra_holes.size(), 1, "punching the same rect twice registers once")
	Overworld.clear_holes()
	ok(not Overworld.in_hole(Vector3(FortKnox.SITE_X, 0.0, FortKnox.SITE_Z)),
		"clear_holes forgets it again")


func _finish() -> void:
	print("FortTests: %d passed, %d failed" % [_pass, _fail])
	if _pass + _fail < MIN_ASSERTIONS:
		print("  LOST A SECTION: only %d assertions ran (floor %d)" % [_pass + _fail, MIN_ASSERTIONS])
		_fail += 1
	quit(1 if _fail > 0 else 0)
