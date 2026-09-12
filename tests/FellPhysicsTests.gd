extends SceneTree

## ===========================================================================
## Headless suite for FELLING PHYSICS.
##
##   godot --headless --path . --script res://tests/FellPhysicsTests.gd
##
## Lemon 2026-08-30: "if I cut a tree down and walk into the base it lags out
## and freezes my game."
##
## It was not the base. `_start_topple` used to shove the trunk over with an
## impulse of mass x 3.2 applied high up — and a rigid body rotates about its
## CENTRE OF MASS, which on this body is halfway up the trunk. So the bottom
## half swung metres through the ground every frame, the solver answered the
## penetration the way it always does, and the log came out at up to 430 m/s
## and landed 75-310 m away. A 900 kg, 31-shape body with continuous_cd on,
## ploughing through the world's collision at that speed for the better part of
## ten seconds, is what "lags out and freezes" looks like from the player's
## chair. (Measured with USE_KIT both on and off: the fault predates trees v4,
## which only made the logs longer and heavier and so the flights longer.)
##
## This suite is here because this exact class of bug has come back before —
## v2 spec bug 8, "the fallen trunk froze standing up". Four things are locked:
##   1. a felled trunk stays NEAR ITS STUMP
##   2. it never moves at a speed no falling tree could reach
##   3. it ends up LYING DOWN, and it always becomes buckable
##   4. a settled log is furniture: it does not crush or pin anyone
## ===========================================================================

## A felled trunk's centre of mass starts at half its height and ends up on the
## ground, so it MUST travel about half its length. Anything past this multiple
## of its own length is the solver throwing it, not gravity.
const MAX_TRAVEL_PER_LENGTH := 2.0
const HARD_TRAVEL_CAP := 45.0
const SIM_SECONDS := 16.0

var passed := 0
var failed := 0
var failures: Array[String] = []
var _cases: Array = []
var _t := 0.0
var _done := false


func ok(cond: bool, label: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		failures.append(label)
		print("  FAIL  ", label)


class Victim extends CharacterBody3D:
	var hits := 0
	var pins := 0
	func take_damage(_d: float, _from: Vector3, _crush := false) -> void:
		hits += 1
	func armor_tier() -> int:
		return 0
	func pin_under(_by: Node, _s: float) -> void:
		pins += 1
	func release_pin() -> void:
		pass


func _initialize() -> void:
	root.add_child(Wind.new())


## Built on frame one, never in _initialize(): a node added under a parent that
## is not itself inside the tree does NOT get _ready() before the call returns.
func _process(_delta: float) -> bool:
	if _cases.is_empty():
		_build()
	return false


func _build() -> void:
	var slot := 0
	for spec in [["maple", 2], ["maple", 3], ["birch", 2], ["birch", 3],
			["oak", 2], ["oak", 3], ["pine", 2], ["pine", 3],
			["fir", 2], ["fir", 3]]:
		# each tree gets its own patch of ground, far from the others, or they
		# land on each other and every distance reading is meaningless
		var ox := float(slot) * 500.0
		slot += 1
		var w := Node3D.new()
		root.add_child(w)
		var g := StaticBody3D.new()
		var gcs := CollisionShape3D.new()
		var gb := BoxShape3D.new()
		gb.size = Vector3(300, 2, 300)
		gcs.shape = gb
		gcs.position = Vector3(ox, -1.0, 0)
		g.add_child(gcs)
		w.add_child(g)

		var t := TreeV2.new()
		t.species = String(spec[0])
		t.stage = int(spec[1])
		t.tree_seed = 991
		t.position = Vector3(ox, 0, 0)
		w.add_child(t)
		var length := t.trunk_height()
		while not t.felled:
			t.chop_hit(Vector3(0, 0, 1))

		var tr: FallenTrunk = null
		for c in w.get_children():
			if c is FallenTrunk:
				tr = c
		_cases.append({"tr": tr, "world": w, "ox": ox, "len": length,
			"label": "%s/%d" % [spec[0], spec[1]],
			"peak": 0.0, "far": 0.0, "settle_t": -1.0, "victim": null})


func _physics_process(delta: float) -> bool:
	if _cases.is_empty() or _done:
		return _done
	_t += delta
	for c in _cases:
		var tr: FallenTrunk = c["tr"]
		if tr == null or not is_instance_valid(tr):
			continue
		c["peak"] = maxf(float(c["peak"]), tr.linear_velocity.length())
		c["far"] = maxf(float(c["far"]),
			Vector2(tr.position.x - float(c["ox"]), tr.position.z).length())
		if tr.settled and float(c["settle_t"]) < 0.0:
			c["settle_t"] = _t
			# the moment it is down, walk something into the base of it
			var v := Victim.new()
			var cs := CollisionShape3D.new()
			var cap := CapsuleShape3D.new()
			cap.radius = 0.4
			cap.height = 1.8
			cs.shape = cap
			cs.position.y = 0.9
			v.add_child(cs)
			v.add_to_group("player")
			(c["world"] as Node3D).add_child(v)
			v.global_position = Vector3(float(c["ox"]), 0.1, 3.0)
			c["victim"] = v
		var vic = c["victim"]
		if vic != null and is_instance_valid(vic):
			vic.velocity = Vector3(0, -8.0, -3.0)
			vic.move_and_slide()

	if _t < SIM_SECONDS:
		return false
	_done = true
	_assert()
	return true


func _trunk_tris(tr: FallenTrunk) -> int:
	if tr._trunk_mi == null or not is_instance_valid(tr._trunk_mi):
		tr._cache_trunk_mesh()
	if tr._trunk_mi == null or tr._trunk_mi.mesh == null:
		return 0
	var n := 0
	for i in range(tr._trunk_mi.mesh.get_surface_count()):
		n += (tr._trunk_mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_INDEX]
			as PackedInt32Array).size() / 3
	return n


func _trunk_cyl(tr: FallenTrunk) -> CollisionShape3D:
	for c in tr.get_children():
		var cs := c as CollisionShape3D
		if cs != null and cs.shape is CylinderShape3D:
			return cs
	return null


func _count_logs(world: Node3D) -> int:
	var n := 0
	for c in world.get_children():
		var di := c as DroppedItem
		if di != null and String(di.item.get("name", "")) == "Log":
			n += 1
	return n


func _last_log(world: Node3D) -> DroppedItem:
	var out: DroppedItem = null
	for c in world.get_children():
		var di := c as DroppedItem
		if di != null and String(di.item.get("name", "")) == "Log":
			out = di
	return out


func _assert() -> void:
	print("-- a felled trunk stays where it fell")
	for c in _cases:
		var tr: FallenTrunk = c["tr"]
		var label := String(c["label"])
		var length := float(c["len"])
		var far := float(c["far"])
		var peak := float(c["peak"])
		ok(tr != null and is_instance_valid(tr), "%s: the trunk still exists" % label)
		if tr == null or not is_instance_valid(tr):
			continue

		ok(far <= length * MAX_TRAVEL_PER_LENGTH and far <= HARD_TRAVEL_CAP,
			"%s: landed %.1f m from the stump (a %.1f m trunk may travel %.1f m)"
			% [label, far, length, minf(length * MAX_TRAVEL_PER_LENGTH, HARD_TRAVEL_CAP)])
		ok(peak <= FallenTrunk.MAX_FALL_SPEED + 2.0,
			"%s: peak speed %.1f m/s stayed under the cap (%.0f)"
			% [label, peak, FallenTrunk.MAX_FALL_SPEED])
		ok(tr.settled, "%s: settled inside %.0f s" % [label, SIM_SECONDS])
		ok(tr.freeze, "%s: a settled log stops simulating" % label)

		# ---- BUCKING (Lemon 2026-08-30: "fix the chopping trees into logs") --
		# chop_hit refuses to buck a trunk that has not settled, so a log that
		# never settles is also a log you can never turn into firewood
		var before := tr.logs_left
		var len_before := tr.trunk_len
		var tris_before := _trunk_tris(tr)
		var world: Node3D = c["world"]
		var logs_before := _count_logs(world)

		tr.chop_hit(Vector3(0, 0, 1))
		ok(tr.logs_left < before, "%s: a settled log bucks when you chop it" % label)
		ok(tr.trunk_len < len_before - 0.5,
			"%s: and the trunk gets SHORTER (%.1f -> %.1f m)" % [label, len_before, tr.trunk_len])
		ok(_count_logs(world) == logs_before + 1,
			"%s: exactly one Log item comes off per bite" % label)
		var lg := _last_log(world)
		ok(lg != null, "%s: found the log it just cut" % label)
		if lg != null:
			ok(is_equal_approx(float(lg.item.get("weight", 0.0)), FallenTrunk.LOG_WEIGHT),
				"%s: it weighs a log (%.1f)" % [label, float(lg.item.get("weight", 0.0))])
			ok(bool(lg.item.get("keep", false)),
				"%s: timber does NOT rot away on the 10-minute dropped-item fuse" % label)
			ok(lg.display_name() == "Log", "%s: and the prompt calls it a log" % label)

		# the whole reported bug: the tree on the ground never changed
		var tris_after := _trunk_tris(tr)
		ok(tris_after < tris_before,
			"%s: the trunk MESH shrinks too (%d -> %d tris) -- it used to spit out logs and not change at all"
			% [label, tris_before, tris_after])

		# the collider has to follow the mesh, and eat from the top so the butt
		# stays where the tree fell
		var cyl := _trunk_cyl(tr)
		ok(cyl != null, "%s: still has its trunk collider" % label)
		if cyl != null:
			ok(absf((cyl.shape as CylinderShape3D).height - tr.trunk_len) < 0.01,
				"%s: the collider matches the wood that is left" % label)
			ok(absf(cyl.position.y - (tr._base + tr.trunk_len * 0.5)) < 0.01,
				"%s: it shrank from the TOP, not around its middle" % label)

		# and it bucks all the way down without getting stuck
		var guard := 0
		while is_instance_valid(tr) and not tr.chop_hit(Vector3(0, 0, 1)) and guard < 30:
			guard += 1
		ok(guard < 30, "%s: bucks all the way down (%d more bites)" % [label, guard])
		ok(_count_logs(world) >= 2, "%s: a whole trunk yields real timber (%d logs)"
			% [label, _count_logs(world)])

		var tilt := rad_to_deg(acos(clampf(absf(tr.global_transform.basis.y.dot(Vector3.UP)),
			0.0, 1.0)))
		ok(tilt > 20.0, "%s: it actually went over (%.0f deg off vertical)" % [label, tilt])

		# and the report that started all this
		var vic = c["victim"]
		if vic != null and is_instance_valid(vic):
			ok(vic.hits == 0,
				"%s: walking into a settled log does not crush you (%d hits)" % [label, vic.hits])
			ok(vic.pins == 0,
				"%s: and it does not PIN you (%d pins) -- the pinned phase has no rise timer, so a pin here reads as the game locking up"
				% [label, vic.pins])
		else:
			ok(false, "%s: got a body to walk into the base" % label)

	print("")
	print("FellPhysicsTests: %d passed, %d failed" % [passed, failed])
	for f in failures:
		print("   - ", f)
	quit()
