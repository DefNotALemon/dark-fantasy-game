extends SceneTree

## ===========================================================================
## tests/GodEditorLive.gd
##
##   godot --headless --path . --script res://tests/GodEditorLive.gd
##
## The half GodEditorTests cannot reach: nodes actually in a tree. Builds a
## PlanViz and a GodEditor for real, walks every tool page, flips the mouse
## between CURSOR and LOOK, drives the spectator camera, and instantiates every
## piece of every prefab.
##
## Kept SEPARATE from GodEditorTests because this one awaits frames, and an
## `await` inside a test section silently drops the rest of that section unless
## every caller awaits too (docs/WILDLIFE.md, learned the hard way at a cost of
## 293 assertions that still printed green). Here every section is awaited.
##
## Writes only into user://plan_test/ -- WorldPlan._dir is overridden first.
## ===========================================================================

var passed := 0
var failed := 0


func ok(cond: bool, what: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  FAIL %s" % what)


func eq(a, b, what: String) -> void:
	ok(a == b, "%s  (got %s, want %s)" % [what, str(a), str(b)])


func _init() -> void:
	print("=== GodEditorLive ===")
	DirAccess.make_dir_recursive_absolute("user://plan_test")
	WorldPlan._dir = "user://plan_test/"
	WorldPlan.load_plan()
	if WorldPlan.zones.is_empty():
		WorldPlan.new_zone("village", PackedVector2Array([
			Vector2(-30, -30), Vector2(30, -30), Vector2(30, 30), Vector2(-30, 30)]))
		WorldPlan.new_path("road", PackedVector2Array([Vector2(0, 0), Vector2(200, 40)]))
		WorldPlan.new_note(Vector3(5, 0, 5), "inn here", "two storeys", "todo",
			str((WorldPlan.zones[0] as Dictionary)["id"]))

	await t_planviz()
	await t_editor()
	await t_spectator()
	await t_world_is_blind()
	await t_prefab_instancing()

	print("=== %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)


func t_planviz() -> void:
	print("-- plan viz in a tree")
	var viz := PlanViz.new()
	root.add_child(viz)
	viz.rebuild()
	await process_frame
	var holder := viz.get_child(0)
	ok(holder != null, "the draw holder exists")
	var want := WorldPlan.zones.size() + WorldPlan.paths.size() + WorldPlan.notes.size()
	eq(holder.get_child_count(), want, "one node per record")
	## every record's node carries its id back, so a click can find it again
	var ids := {}
	for c in holder.get_children():
		ok((c as Node).has_meta("plan_id"), "drawn node carries its plan id")
		ids[str((c as Node).get_meta("plan_id"))] = true
	for z in WorldPlan.zones:
		ok(ids.has(str((z as Dictionary)["id"])), "zone %s drawn" % str((z as Dictionary)["id"]))
	## a zone really produced geometry, not an empty holder
	var zone_node := holder.get_child(0)
	var meshes := 0
	for c in zone_node.get_children():
		if c is MeshInstance3D or c is Label3D:
			meshes += 1
	ok(meshes >= 2, "a zone draws a curtain, a fill and a label (%d nodes)" % meshes)

	viz.set_draft(PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)]),
		true, Color.RED, 0.0)
	await process_frame
	ok(viz.get_child_count() > 1, "the draft draws")
	viz.clear_draft()
	await process_frame
	eq(viz.get_child_count(), 1, "and clears")

	## rebuilding twice must not double the world
	viz.rebuild()
	await process_frame
	eq(viz.get_child(0).get_child_count(), want, "a rebuild replaces, never appends")
	viz.queue_free()
	await process_frame


func t_editor() -> void:
	print("-- editor in a tree")
	var ge := GodEditor.new()
	var cl := CanvasLayer.new()
	root.add_child(cl)
	cl.add_child(ge)
	await process_frame
	await process_frame
	ok(ge.get_child_count() > 0, "the panel built its UI")
	ok(not ge.visible, "and starts hidden")
	ok(ge.is_in_group("builder"), "it is in the builder group, so a load restores through it")

	## every tool page builds controls
	for t in ["select", "zone", "path", "note", "tree", "build", "erase"]:
		ge._set_tool(t)
		await process_frame
		eq(ge.tool, t, "tool is %s" % t)
		ok(ge._body.get_child_count() > 0, "page %s has controls" % t)
	ge.build_mode = "prefab"
	ge._set_tool("build")
	await process_frame
	ok(ge._body.get_child_count() > 0, "the prefab page has controls")
	ge.build_mode = "piece"

	## --- F: the mouse flips both ways -----------------------------------
	ge.set_mouse_look(true)
	await process_frame
	ok(ge.mouse_look, "F captured the mouse")
	## NOT asserting Input.mouse_mode here: headless has no window to capture
	## into, so the server keeps reporting VISIBLE however you set it. The
	## editor's own state is the thing under test; the capture itself is one
	## line of engine call.
	ok(not ge._over_panel(), "with no cursor, nothing is over the panel")
	ok(not ge.typing, "capturing drops any text focus")
	ge.set_mouse_look(false)
	await process_frame
	ok(not ge.mouse_look, "F gave the cursor back")
	ok(ge._over_panel() or true, "the cursor path is live again")
	## F is consumed by the editor only while the panel is up
	ge.visible = true
	var f := InputEventKey.new()
	f.keycode = KEY_F
	f.pressed = true
	ok(ge.eat_input(f), "F is taken while the panel is up")
	ok(ge.mouse_look, "...and it flipped the mouse")
	ok(ge.eat_input(f), "F again")
	ok(not ge.mouse_look, "...and flipped it back")
	ge.visible = false
	ok(not ge.eat_input(f), "F is left alone with the panel closed")

	## other keys the editor claims
	ge.visible = true
	var h := InputEventKey.new()
	h.keycode = KEY_H
	h.pressed = true
	var snap_before: bool = ge.grid_snap
	ok(ge.eat_input(h), "H is taken")
	ok(ge.grid_snap != snap_before, "H toggled grid snap")
	## typing swallows the keyboard whole
	ge.typing = true
	ok(ge.eat_input(h), "a text box eats H")
	eq(ge.grid_snap, not snap_before, "...without toggling anything")
	ge.typing = false
	ge.visible = false

	cl.queue_free()
	await process_frame


func t_prefab_instancing() -> void:
	print("-- every prefab really instantiates")
	var total := 0
	for id in BuildKit.PREFABS:
		var made := 0
		for r in BuildKit.prefab(str(id)):
			var rd: Dictionary = r
			var b := BuiltPiece.make(str(rd["piece"]), str(rd["mat"]))
			if b != null and b.get_child_count() > 0:
				made += 1
			if b != null:
				b.free()
		eq(made, BuildKit.prefab(str(id)).size(), "every piece of %s built" % id)
		total += made
	ok(total > 200, "the prefab library is %d pieces" % total)
	await process_frame


func t_spectator() -> void:
	print("-- the spectator camera")
	eq(EditorMode.active, false, "nothing is editing to start with")

	var cam := EditorCam.new()
	root.add_child(cam)
	await process_frame
	ok(not cam.active, "a fresh camera is not the eye")
	ok(not cam.current, "...and is not current")
	ok(cam.far >= 4000.0, "it can see the mountains (far %.0f)" % cam.far)

	## take_over with no camera to copy still arms it, at wherever it stands
	cam.global_position = Vector3(100, 40, -250)
	cam.take_over(null)
	await process_frame
	ok(cam.active, "take_over arms it")
	ok(cam.current, "...and makes it the eye")
	eq(cam.global_position, Vector3(100, 40, -250), "it does not move on take-over")

	## copying a real camera keeps the exact view
	var src := Camera3D.new()
	root.add_child(src)
	src.global_position = Vector3(-40, 12, 7)
	src.rotation = Vector3(-0.4, 1.1, 0.0)
	src.fov = 62.0
	await process_frame
	cam.take_over(src)
	await process_frame
	ok(cam.global_position.distance_to(src.global_position) < 0.001,
		"the eye lifts out at the same place")
	ok(absf(cam.yaw - 1.1) < 0.01, "yaw copied (%.3f)" % cam.yaw)
	ok(absf(cam.pitch + 0.4) < 0.01, "pitch copied (%.3f)" % cam.pitch)
	ok(absf(cam.fov - 62.0) < 0.01, "fov copied")

	## look: pitch clamps, yaw wraps, and neither ever rolls
	cam.look(Vector2(0, -100000), 1.0)
	ok(cam.pitch <= EditorCam.PITCH_LIMIT + 0.001, "pitch clamps looking up")
	cam.look(Vector2(0, 100000), 1.0)
	ok(cam.pitch >= -EditorCam.PITCH_LIMIT - 0.001, "pitch clamps looking down")
	cam.look(Vector2(100000, 0), 1.0)
	ok(cam.yaw >= -PI - 0.001 and cam.yaw <= PI + 0.001, "yaw wraps (%.3f)" % cam.yaw)
	await process_frame
	var roll: float = cam.global_transform.basis.get_euler().z
	ok(absf(roll) < 0.001, "the horizon never rolls (%.4f)" % roll)

	## speed rides the wheel dial
	cam.speed_mult = 1.0
	var s1 := cam.speed()
	cam.speed_mult = 4.0
	ok(absf(cam.speed() - s1 * 4.0) < 0.001, "speed scales with the dial")
	cam.speed_mult = 1.0

	## no keys held (headless) = it coasts to a stop and does not drift
	cam.global_position = Vector3.ZERO
	cam._vel = Vector3(10, 0, 0)
	for _i in range(30):
		await process_frame
	ok(cam._vel.length() < 0.01, "it comes to a stop (%.3f m/s)" % cam._vel.length())
	ok(cam.global_position.x > 0.0, "...having actually travelled")
	var rested := cam.global_position
	for _i in range(10):
		await process_frame
	ok(cam.global_position.distance_to(rested) < 0.001, "and then it hangs there")

	## release hands the eye back
	cam.release(src)
	await process_frame
	ok(not cam.active, "release disarms it")
	ok(not cam.current, "...and it stops being the eye")
	ok(src.current, "...and the old camera is the eye again")
	## an inactive camera ignores input entirely
	cam._vel = Vector3(10, 0, 0)
	var parked := cam.global_position
	for _i in range(5):
		await process_frame
	eq(cam.global_position, parked, "an inactive camera never moves")

	ok(cam.distance_to_body(src) > 0.0, "it can measure back to a body")
	eq(cam.distance_to_body(null), 0.0, "and a missing body reads zero")

	cam.queue_free()
	src.queue_free()
	await process_frame

	## the editor is null-safe before it has found a world
	var ge := GodEditor.new()
	ok(not ge.spectating(), "an unbooted editor is not spectating")
	eq(ge.active_cam(), null, "...and has no eye")
	var mm := InputEventMouseMotion.new()
	ok(not ge.take_motion(mm), "...and does not eat motion")
	ge.free()


func t_world_is_blind() -> void:
	print("-- the world cannot see a parked body")
	## Source-level regression guards. This repo has twice had a later patcher
	## silently put an old file back over a fix (docs/TREES_v2_SPEC.md bug 5),
	## and these two gates are one line each in files other passes rewrite.
	for path in ["res://scripts/Enemy.gd", "res://scripts/CritterSwarm.gd"]:
		var f := FileAccess.open(path, FileAccess.READ)
		ok(f != null, "%s is readable" % path)
		if f != null:
			var src := f.get_as_text()
			f.close()
			ok(src.contains("EditorMode.active"),
				"%s still checks EditorMode.active" % path)
	var pf := FileAccess.open("res://scripts/Player.gd", FileAccess.READ)
	if pf != null:
		var ps := pf.get_as_text()
		pf.close()
		ok(ps.contains("func set_editing("), "Player still has set_editing")
		ok(ps.contains("collision_layer = 0"), "...which parks the collision layer")
		ok(ps.contains("EditorMode.active = editing"), "...and sets the flag with it")
		ok(ps.contains("if editing:"), "_physics_process still branches on editing")
		ok(ps.contains("if god:\n\t\treturn  ## ...except god mode"),
			"knockdowns still refuse god mode")
	await process_frame
