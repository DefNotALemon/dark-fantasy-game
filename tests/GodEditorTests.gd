extends SceneTree

## ===========================================================================
## tests/GodEditorTests.gd
##
##   godot --headless --path . --script res://tests/GodEditorTests.gd
##
## Covers the god editor's data layer end to end WITHOUT booting the world:
## WorldPlan's geometry, records, persistence and Markdown; BuildKit's whole
## catalog (every piece really builds, every prefab really references pieces
## that exist, every piece really has a price); BuiltPiece's round trip;
## PlanViz's outline sampling; GodEditor's aim maths.
##
## It writes ONLY into user://plan_test/ -- WorldPlan._dir is overridden before
## anything runs, so a test can never scribble over design/world_plan.json.
## ===========================================================================

var passed := 0
var failed := 0
var section_name := ""

const MIN_ASSERTIONS := 120


func ok(cond: bool, what: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  FAIL [%s] %s" % [section_name, what])


func eq(a, b, what: String) -> void:
	ok(a == b, "%s  (got %s, want %s)" % [what, str(a), str(b)])


func near(a: float, b: float, tol: float, what: String) -> void:
	ok(absf(a - b) <= tol, "%s  (got %f, want %f +/- %f)" % [what, a, b, tol])


func section(n: String) -> void:
	section_name = n
	print("-- %s" % n)


func _init() -> void:
	print("=== GodEditorTests ===")
	DirAccess.make_dir_recursive_absolute("user://plan_test")
	WorldPlan._dir = "user://plan_test/"
	## start from nothing every run
	for f in ["world_plan.json", "WORLD_PLAN.md", "build_placements.json"]:
		DirAccess.remove_absolute("user://plan_test/" + f)
	WorldPlan.load_plan()

	t_plan_paths()
	t_zone_geometry()
	t_zone_lookup()
	t_paths()
	t_notes()
	t_removal()
	t_persistence()
	t_markdown()
	t_buildkit_pieces()
	t_buildkit_prefabs()
	t_buildkit_costs()
	t_built_piece()
	t_planviz()
	t_editor_math()

	print("=== %d passed, %d failed ===" % [passed, failed])
	if passed < MIN_ASSERTIONS:
		print("!!! only %d assertions ran (floor is %d) -- a section died early"
			% [passed, MIN_ASSERTIONS])
		quit(2)
	quit(1 if failed > 0 else 0)


# ---------------------------------------------------------------------------

func t_plan_paths() -> void:
	section("paths")
	eq(WorldPlan.dir(), "user://plan_test/", "dir override holds")
	ok(WorldPlan.json_path().ends_with("world_plan.json"), "json path")
	ok(WorldPlan.md_path().ends_with("WORLD_PLAN.md"), "md path")
	eq(WorldPlan.zones.size(), 0, "starts empty (zones)")
	eq(WorldPlan.notes.size(), 0, "starts empty (notes)")


func square(cx: float, cz: float, half: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(cx - half, cz - half), Vector2(cx + half, cz - half),
		Vector2(cx + half, cz + half), Vector2(cx - half, cz + half)])


func t_zone_geometry() -> void:
	section("zone geometry")
	var z := WorldPlan.new_zone("village", square(0, 0, 25))
	eq(str(z["kind"]), "village", "kind kept")
	eq(WorldPlan.points_of(z).size(), 4, "four corners")
	near(WorldPlan.area_of(z), 2500.0, 0.5, "50x50 square is 2500 m2")
	var bb := WorldPlan.bbox_of(z)
	near(bb.size.x, 50.0, 0.01, "bbox width")
	near(bb.size.y, 50.0, 0.01, "bbox depth")
	var c := WorldPlan.center_of(z)
	near(c.x, 0.0, 0.01, "centroid x")
	near(c.y, 0.0, 0.01, "centroid z")
	ok(WorldPlan.contains(z, 10, 10), "inside is inside")
	ok(not WorldPlan.contains(z, 40, 0), "outside is outside")
	ok(str(z["id"]).begins_with("zone_"), "id prefix")

	var circ := WorldPlan.new_zone("farm", PackedVector2Array(), "circle", 20.0)
	circ["center"] = [100.0, 0.0]
	eq(WorldPlan.points_of(circ).size(), WorldPlan.CIRCLE_SEGS, "circle expands to a ring")
	near(WorldPlan.area_of(circ), PI * 400.0, PI * 400.0 * 0.02,
		"circle area within 2% of pi r^2")
	ok(WorldPlan.contains(circ, 110.0, 0.0), "point inside circle")
	ok(not WorldPlan.contains(circ, 130.0, 0.0), "point outside circle")
	near(WorldPlan.center_of(circ).x, 100.0, 0.01, "circle centre kept")
	## resizing a circle is one number, and everything follows
	circ["radius"] = 40.0
	near(WorldPlan.area_of(circ), PI * 1600.0, PI * 1600.0 * 0.02, "resize changes area")
	ok(WorldPlan.contains(circ, 130.0, 0.0), "resize changes containment")

	var col: Color = WorldPlan.kind_color(z)
	ok(col != Color(0.8, 0.8, 0.8), "known kind has its own colour")
	eq(WorldPlan.kind_label(z), "Village", "kind label")
	eq(WorldPlan.kind_label({"kind": "nonsense"}), "Nonsense", "unknown kind falls back")

	## every declared kind must be complete -- a missing colour crashes PlanViz
	for k in WorldPlan.ZONE_KINDS:
		var d: Dictionary = WorldPlan.ZONE_KINDS[k]
		ok(d.has("label") and d.has("color") and d.has("cat"), "zone kind %s complete" % k)


func t_zone_lookup() -> void:
	section("zone lookup")
	WorldPlan.zones.clear()
	var city := WorldPlan.new_zone("city", square(0, 0, 200))
	var market := WorldPlan.new_zone("market", square(0, 0, 20))
	var hit := WorldPlan.zone_at(0, 0)
	eq(str(hit.get("id", "")), str(market["id"]), "smallest zone wins at the centre")
	var hit2 := WorldPlan.zone_at(150, 0)
	eq(str(hit2.get("id", "")), str(city["id"]), "the big one wins further out")
	ok(WorldPlan.zone_at(9000, 9000).is_empty(), "nothing out in the ocean")


func t_paths() -> void:
	section("paths and roads")
	var p := WorldPlan.new_path("road", PackedVector2Array([
		Vector2(0, 0), Vector2(0, 100), Vector2(100, 100)]))
	near(WorldPlan.length_of(p), 200.0, 0.01, "polyline length")
	near(float(p["width"]), 6.0, 0.001, "road default width")
	var trail := WorldPlan.new_path("trail", PackedVector2Array([Vector2(0, 0), Vector2(3, 4)]))
	near(WorldPlan.length_of(trail), 5.0, 0.001, "3-4-5")
	near(float(trail["width"]), 1.8, 0.001, "trail default width")
	var wide := WorldPlan.new_path("trail", PackedVector2Array([Vector2(0, 0), Vector2(1, 0)]), 12.0)
	near(float(wide["width"]), 12.0, 0.001, "explicit width wins")
	for k in WorldPlan.PATH_KINDS:
		var d: Dictionary = WorldPlan.PATH_KINDS[k]
		ok(d.has("label") and d.has("color") and d.has("width"), "path kind %s complete" % k)
		ok(float(d["width"]) > 0.0, "path kind %s has a real width" % k)
	## names are unique enough to tell apart in the panel
	ok(str(p["name"]) != str(trail["name"]), "auto names differ")


func t_notes() -> void:
	section("notes")
	WorldPlan.zones.clear()
	WorldPlan.notes.clear()
	var z := WorldPlan.new_zone("village", square(0, 0, 30))
	var zid := str(z["id"])
	var n := WorldPlan.new_note(Vector3(1, 2, 3), "Put the inn here", "two storeys, faces the road",
		"todo", zid)
	eq(str(n["owner"]), zid, "note filed under its zone")
	eq(WorldPlan.notes_for(zid).size(), 1, "zone has one note")
	eq(WorldPlan.loose_notes().size(), 0, "nothing loose yet")
	WorldPlan.new_note(Vector3(500, 0, 500), "look at this ridge", "", "idea", "")
	eq(WorldPlan.loose_notes().size(), 1, "an unowned note is loose")
	WorldPlan.new_note(Vector3(0, 0, 0), "orphan", "", "todo", "zone_9999")
	eq(WorldPlan.loose_notes().size(), 2, "a note whose owner is gone is loose too")
	for t in WorldPlan.NOTE_TAGS:
		ok(WorldPlan.NOTE_TAG_COLOR.has(t), "tag %s has a colour" % t)
	## positions are stored, not lost
	var pa: Array = n["pos"]
	near(float(pa[0]), 1.0, 0.001, "note x")
	near(float(pa[2]), 3.0, 0.001, "note z")


func t_removal() -> void:
	section("removal")
	WorldPlan.zones.clear()
	WorldPlan.paths.clear()
	WorldPlan.notes.clear()
	var z := WorldPlan.new_zone("farm", square(10, 10, 15))
	var zid := str(z["id"])
	WorldPlan.new_note(Vector3.ZERO, "a", "", "todo", zid)
	WorldPlan.new_note(Vector3.ZERO, "b", "", "todo", zid)
	var keeper := WorldPlan.new_note(Vector3.ZERO, "keep me", "", "idea", "")
	eq(WorldPlan.notes.size(), 3, "three notes before")
	ok(WorldPlan.remove(zid), "zone removed")
	eq(WorldPlan.zones.size(), 0, "zone gone")
	eq(WorldPlan.notes.size(), 1, "its notes went with it")
	eq(str(WorldPlan.notes[0]["id"]), str(keeper["id"]), "the loose note survived")
	ok(not WorldPlan.remove("zone_does_not_exist"), "removing nothing returns false")
	ok(WorldPlan.remove(str(keeper["id"])), "a note can be removed on its own")
	eq(WorldPlan.notes.size(), 0, "and it is gone")


func t_persistence() -> void:
	section("persistence")
	WorldPlan.zones.clear()
	WorldPlan.paths.clear()
	WorldPlan.notes.clear()
	var z := WorldPlan.new_zone("city", square(-40, 60, 80))
	z["name"] = "Bramblewick"
	z["status"] = "building"
	z["priority"] = "next"
	WorldPlan.new_path("kingsroad", PackedVector2Array([Vector2(0, 0), Vector2(400, 90)]))
	WorldPlan.new_note(Vector3(-40, 12, 60), "market square", "cobbles, a well, four stalls",
		"todo", str(z["id"]))
	var next_before: int = WorldPlan._next_id
	ok(WorldPlan.save_plan(), "saved")
	ok(FileAccess.file_exists(WorldPlan.json_path()), "json on disk")
	ok(FileAccess.file_exists(WorldPlan.md_path()), "markdown on disk")

	## wipe memory, reload from disk, and check every field came home
	WorldPlan.zones.clear()
	WorldPlan.paths.clear()
	WorldPlan.notes.clear()
	WorldPlan.load_plan()
	eq(WorldPlan.zones.size(), 1, "one zone back")
	eq(WorldPlan.paths.size(), 1, "one path back")
	eq(WorldPlan.notes.size(), 1, "one note back")
	var zz: Dictionary = WorldPlan.zones[0]
	eq(str(zz["name"]), "Bramblewick", "name round-tripped")
	eq(str(zz["status"]), "building", "status round-tripped")
	eq(str(zz["priority"]), "next", "priority round-tripped")
	near(WorldPlan.area_of(zz), 160.0 * 160.0, 1.0, "geometry round-tripped")
	eq(WorldPlan.notes_for(str(zz["id"])).size(), 1, "the note is still filed under it")
	eq(WorldPlan._next_id, next_before, "the id counter round-tripped")
	## a fresh id after a reload must not collide with a loaded one
	var fresh := WorldPlan.new_zone("farm", square(0, 0, 5))
	var clash := 0
	for r in WorldPlan.zones:
		if str((r as Dictionary)["id"]) == str(fresh["id"]):
			clash += 1
	eq(clash, 1, "the new id is unique")


func t_markdown() -> void:
	section("markdown")
	var md := WorldPlan.markdown()
	ok(md.begins_with("# Myrkfell"), "has a title")
	ok(md.contains("## Open notes"), "open notes section")
	ok(md.contains("## Zones"), "zones section")
	ok(md.contains("## Roads, trails and lines"), "paths section")
	ok(md.contains("Bramblewick"), "names the zone")
	ok(md.contains("market square"), "carries the note title")
	ok(md.contains("cobbles, a well, four stalls"), "carries the note body")
	ok(md.contains("[ ]"), "open notes render as unticked boxes")
	ok(md.contains("### Settlement"), "grouped by category")
	ok(md.contains("`zone_"), "quotes the id so it can be referenced back")
	## a done note ticks its box
	WorldPlan.notes[0]["tag"] = "done"
	var md2 := WorldPlan.markdown()
	ok(md2.contains("[x]"), "a done note renders ticked")
	ok(md2.contains("## Open notes (0)"), "and drops out of the open list")
	WorldPlan.notes[0]["tag"] = "todo"
	## the file on disk matches what markdown() returns
	WorldPlan.save_plan()
	var f := FileAccess.open(WorldPlan.md_path(), FileAccess.READ)
	ok(f != null, "markdown reopens")
	if f != null:
		var disk := f.get_as_text()
		f.close()
		ok(disk.contains("Bramblewick"), "the file has the content, not just the return value")


func t_buildkit_pieces() -> void:
	section("build kit -- pieces")
	var n := 0
	for id in BuildKit.PIECES:
		var d: Dictionary = BuildKit.PIECES[id]
		ok(d.has("label") and d.has("cat") and d.has("mat"), "piece %s is described" % id)
		ok(BuildKit.MATS.has(str(d["mat"])), "piece %s names a real material" % id)
		var b := BuildKit.build(str(id))
		ok(b != null, "piece %s builds" % id)
		if b != null:
			ok(b.get_child_count() > 0, "piece %s has geometry" % id)
			var meshes := 0
			for c in b.get_children():
				if c is MeshInstance3D:
					meshes += 1
			ok(meshes > 0, "piece %s has at least one mesh" % id)
			b.free()
		n += 1
	ok(n >= 25, "the catalog is not a stub (%d pieces)" % n)
	## categories partition the catalog
	var seen := 0
	for cat in BuildKit.categories():
		seen += BuildKit.pieces_in(cat).size()
	eq(seen, n, "every piece lands in exactly one category")
	## a piece built into an existing body keeps that body
	var host := StaticBody3D.new()
	var same := BuildKit.build_into(host, "wall", "stone")
	eq(same, host, "build_into fills the body it was handed")
	ok(host.get_child_count() > 0, "and puts geometry in it")
	host.free()


func t_buildkit_prefabs() -> void:
	section("build kit -- prefabs")
	var n := 0
	for id in BuildKit.PREFABS:
		var recs := BuildKit.prefab(str(id))
		ok(recs.size() > 0, "prefab %s is not empty" % id)
		for r in recs:
			var rd: Dictionary = r
			ok(rd.has("piece") and rd.has("pos") and rd.has("rot") and rd.has("mat"),
				"prefab %s record is complete" % id)
			ok(BuildKit.PIECES.has(str(rd["piece"])),
				"prefab %s uses a real piece (%s)" % [id, str(rd["piece"])])
			ok(BuildKit.MATS.has(str(rd["mat"])),
				"prefab %s uses a real material (%s)" % [id, str(rd["mat"])])
			ok(typeof(rd["pos"]) == TYPE_VECTOR3, "prefab %s position is a Vector3" % id)
		n += 1
	ok(n >= 10, "there are enough prefabs to lay out a village (%d)" % n)
	var seen := 0
	for cat in BuildKit.prefab_categories():
		seen += BuildKit.prefabs_in(cat).size()
	eq(seen, n, "every prefab lands in exactly one category")
	## a cottage is a real building, not two boxes
	var cottage := BuildKit.prefab("cottage")
	ok(cottage.size() >= 20, "a cottage is %d pieces" % cottage.size())
	var has_door := false
	var has_roof := false
	for r in cottage:
		var p := str((r as Dictionary)["piece"])
		if p == "wall_door":
			has_door = true
		if p.begins_with("roof"):
			has_roof = true
	ok(has_door, "the cottage has a door")
	ok(has_roof, "the cottage has a roof")


func t_buildkit_costs() -> void:
	section("build kit -- the Stardew hook")
	for id in BuildKit.PIECES:
		ok(BuildKit.COST.has(id), "piece %s is priced" % id)
		if BuildKit.COST.has(id):
			var c: Dictionary = BuildKit.COST[id]
			ok(c.size() > 0, "piece %s costs something" % id)
			for item in c:
				ok(int(c[item]) > 0, "piece %s: %s count is positive" % [id, item])
	for id in BuildKit.COST:
		ok(BuildKit.PIECES.has(id), "priced piece %s still exists" % id)


func t_built_piece() -> void:
	section("built piece round trip")
	var b := BuiltPiece.make("wall_window", "stone", 1.5)
	b.position = Vector3(12.5, 3.25, -40.0)
	b.rotation.y = 1.25
	var d := b.save_dict()
	eq(str(d["kind"]), "piece", "kind tag")
	eq(str(d["piece"]), "wall_window", "piece id")
	eq(str(d["mat"]), "stone", "material")
	near(float(d["rot"]), 1.25, 0.001, "rotation")
	near(float(d["scale"]), 1.5, 0.001, "scale")
	var b2 := BuiltPiece.from_dict(d)
	eq(b2.piece, b.piece, "piece survives")
	eq(b2.mat_id, b.mat_id, "material survives")
	near(b2.position.x, 12.5, 0.001, "x survives")
	near(b2.position.y, 3.25, 0.001, "y survives")
	near(b2.rotation.y, 1.25, 0.001, "rotation survives")
	near(b2.scale.x, 1.5, 0.001, "scale survives")
	ok(b2.get_child_count() > 0, "the restored piece has its geometry")
	## defaults fill in for an old/partial record
	var b3 := BuiltPiece.from_dict({"piece": "floor"})
	eq(b3.mat_id, BuildKit.default_mat("floor"), "missing material defaults")
	near(b3.scale.x, 1.0, 0.001, "missing scale defaults")
	b.free()
	b2.free()
	b3.free()


func t_planviz() -> void:
	section("plan viz sampling")
	var ring := PackedVector2Array([Vector2(0, 0), Vector2(40, 0), Vector2(40, 40), Vector2(0, 40)])
	var closed := PlanViz._densify(ring, true, 4.0)
	eq(closed.size(), 40, "a closed 160 m outline at 4 m is 40 samples")
	var open_line := PlanViz._densify(PackedVector2Array([Vector2(0, 0), Vector2(40, 0)]),
		false, 4.0)
	eq(open_line.size(), 11, "an open 40 m line at 4 m is 10 spans + the end")
	var tiny := PlanViz._densify(PackedVector2Array([Vector2(0, 0)]), false, 4.0)
	eq(tiny.size(), 1, "one point stays one point")
	## samples actually walk the edge
	near(open_line[5].x, 20.0, 0.001, "midpoint lands where it should")
	## triangulating a plain square gives two triangles
	eq(Geometry2D.triangulate_polygon(ring).size(), 6, "square triangulates to 2 tris")


func t_editor_math() -> void:
	section("editor maths")
	near(GodEditor._dist_to_seg(Vector2(5, 10), Vector2(0, 0), Vector2(10, 0)), 10.0, 0.001,
		"distance to the middle of a segment")
	near(GodEditor._dist_to_seg(Vector2(-5, 0), Vector2(0, 0), Vector2(10, 0)), 5.0, 0.001,
		"past the start clamps to the start")
	near(GodEditor._dist_to_seg(Vector2(20, 0), Vector2(0, 0), Vector2(10, 0)), 10.0, 0.001,
		"past the end clamps to the end")
	near(GodEditor._dist_to_seg(Vector2(3, 4), Vector2(0, 0), Vector2(0, 0)), 5.0, 0.001,
		"a zero-length segment is a point")
	## the march step grows with distance but stays inside its bounds
	near(GodEditor._march_step(1.0), 0.6, 0.001, "near steps are the floor")
	near(GodEditor._march_step(100.0), 3.5, 0.001, "mid steps scale")
	near(GodEditor._march_step(9000.0), 14.0, 0.001, "far steps are the ceiling")
	ok(GodEditor._march_step(500.0) > GodEditor._march_step(50.0), "step is monotonic")
	## the panel constants are sane
	ok(GodEditor.SPEED_MIN < 1.0 and GodEditor.SPEED_MAX > 1.0,
		"the speed dial brackets normal speed")
	ok(GodEditor.SPEED_STEP > 1.0, "one wheel click speeds up")
	near(pow(GodEditor.SPEED_STEP, 12.0), 12.1, 3.0,
		"a dozen clicks is roughly a 12x -- the wheel crosses the map without a marathon")
	ok(GodEditor.REACH >= 1000.0, "you can aim at a mountain")
	eq(BuildKit.MODULE, 2.0, "the grid is 2 m")
