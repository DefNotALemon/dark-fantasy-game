extends SceneTree

# =============================================================================
# tests/TerrainTests.gd -- the overworld, checked against the real baked data.
#
#   godot --headless --path . --script res://tests/TerrainTests.gd
#
# NOTE (traps this suite exists to catch):
#   * a ground triangle wound the wrong way lights pitch black in game and
#     looks like a broken shader -- _t_winding asserts the generated normal
#     of flat ground points +Y.
#   * *.r16 missing from the export filter makes the height buffer short --
#     _t_data asserts the exact byte count.
#   * never put `await` inside a section without awaiting the caller: Godot
#     turns the function into a coroutine and silently drops the rest of the
#     run while still printing green.
# =============================================================================

const MIN_ASSERTIONS := 180

var _pass := 0
var _fail := 0
var _section := ""


var _T: Node3D = null
var _ran := false


# TRAP: a node added inside SceneTree._init() does NOT get _ready() before
# _init() returns -- Godot defers it to the first frame. The first version of
# this suite tested an unloaded Terrain and "failed" on a working build. Boot
# in _init, assert in _process. No `await` anywhere in here: it would turn the
# function into a coroutine, which Godot reads as "true" and quits on frame one.
func _init() -> void:
	print("\n=== TerrainTests ===")
	_T = load("res://scripts/Overworld.gd").new()
	root.add_child(_T)


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run(_T)
	return true


func _run(T: Node3D) -> void:
	_t_data(T)
	_t_frame(T)
	_t_facade(T)
	_t_places(T)
	_t_water(T)
	_t_winding(T)
	_t_valley(T)
	_t_name_collision(T)
	_t_forest(T)
	_t_hole(T)
	_t_streamer_boot(T)
	_t_cells(T)
	_t_crowns(T)
	_t_water_mesh(T)
	_t_ground_look(T)
	_t_depth(T)
	_t_safety(T)

	print("\n--- %d passed, %d failed (floor %d) ---" % [_pass, _fail, MIN_ASSERTIONS])
	if _pass + _fail < MIN_ASSERTIONS:
		print("FAIL: only %d assertions ran; the suite lost a section." % (_pass + _fail))
		quit(1)
	quit(1 if _fail > 0 else 0)


func sec(s: String) -> void:
	_section = s
	print("\n[%s]" % s)


func ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL  %s" % what)


func near(a: float, b: float, tol: float, what: String) -> void:
	ok(absf(a - b) <= tol, "%s (got %.3f, want %.3f +/- %.3f)" % [what, a, b, tol])


# -----------------------------------------------------------------------------
func _t_data(T: Node3D) -> void:
	sec("baked data")
	ok(T.get("_loaded"), "the bake loaded")
	var nx: int = T.get("nx")
	var nz: int = T.get("nz")
	ok(nx == 1800, "1800 columns")
	ok(nz == 2700, "2700 rows")
	near(T.get("step"), 4.0, 0.001, "4 m spacing")
	near(float(nx) * T.get("step"), 7200.0, 1.0, "7.2 km wide")
	near(float(nz) * T.get("step"), 10800.0, 1.0, "10.8 km tall")
	var h: PackedByteArray = T.get("_h")
	var w: PackedByteArray = T.get("_w")
	ok(h.size() == nx * nz * 2, "height buffer is %d bytes (is *.r16 exported?)" % (nx * nz * 2))
	ok(w.size() == nx * nz * 2, "water buffer is the same size")
	near(T.get("sea_level"), -22.5, 0.01, "sea level -22.5")
	near(T.get("h_max"), 597.0, 0.5, "the roof is Katahdin at 597 m")
	ok(T.get("h_min") < T.get("sea_level"), "the ocean floor is under the sea")


func _t_frame(T: Node3D) -> void:
	sec("coordinate frame")
	# Row 0 is NORTH. Walking north (-z) must not walk off the top of the map.
	var x0: float = T.get("x0")
	var z0: float = T.get("z0")
	var nx: int = T.get("nx")
	var nz: int = T.get("nz")
	var step: float = T.get("step")
	ok(x0 < 0.0, "the map extends west of the spawn valley")
	ok(z0 < 0.0, "the map extends north of the spawn valley")
	ok(x0 + float(nx) * step > 0.0, "...and east of it")
	ok(z0 + float(nz) * step > 0.0, "...and south of it")
	ok(T.pos_in_bounds(Vector3.ZERO), "the origin is inside the map")
	ok(not T.pos_in_bounds(Vector3(x0 - 50.0, 0, 0)), "west of the rim is out")
	ok(not T.pos_in_bounds(Vector3(0, 0, z0 - 50.0)), "north of the rim is out")
	ok(not T.pos_in_bounds(Vector3(0, 0, z0 + float(nz) * step + 50.0)), "south of the rim is out")


func _t_facade(T: Node3D) -> void:
	sec("the facade")
	ok(T.ground_y(Vector3.ZERO) != null, "ground_y answers at the origin")
	# static access must work through the singleton
	ok(load("res://scripts/Overworld.gd").inst == T, "Overworld.inst is the live node")
	var regions := {}
	for p in [Vector3(0, 0, 0), Vector3(2400, 0, -5000), Vector3(100, 0, 400),
			Vector3(-1000, 0, -2000), Vector3(3000, 0, -1000)]:
		var r: String = T.region_for(p.x, p.z)
		regions[r] = true
		ok(r in ["temperate", "deepwood", "highland"], "region_for gives a known region (%s)" % r)
	ok(regions.size() >= 2, "the map has more than one region in it")
	# highland must actually be high
	var hi: String = T.region_for(2329.0, -5046.0)
	ok(hi == "highland", "Katahdin's shoulder is highland (got %s)" % hi)


func _t_places(T: Node3D) -> void:
	sec("named places")
	var places: Array = T.places()
	var peaks: Array = T.peaks()
	var lakes: Array = T.lakes()
	ok(places.size() == 50, "50 cities recovered (got %d)" % places.size())
	ok(lakes.size() == 30, "30 lakes recovered (got %d)" % lakes.size())
	ok(peaks.size() >= 12, "at least a dozen distinct summits (got %d)" % peaks.size())

	var portland: Dictionary = {}
	for p in places:
		if String(p["name"]) == "Portland":
			portland = p
	ok(not portland.is_empty(), "Portland is on the map")
	if not portland.is_empty():
		var pp: Array = portland["pos"]
		var pos := Vector3(float(pp[0]), 0.0, float(pp[1]))
		# The 2026-08-27 build documented Portland as ~400 m south of spawn.
		near(pos.z, 400.0, 60.0, "Portland is ~400 m south of the valley")
		ok(absf(pos.x) < 400.0, "...and roughly due south, not across the map")
		ok(T.place_name_at(pos) == "Portland", "place_name_at finds Portland at Portland")
		ok(T.place_name_at(pos + Vector3(4000, 0, 4000)) != "Portland", "...and not from 5 km away")
		near(T.ground_y(pos), float(portland["y"]), 3.0, "Portland's ground matches its meta height")
		ok(T.ground_y(pos) > T.get("sea_level"), "Portland is above the waterline")

	var kat: Dictionary = {}
	for p in peaks:
		if String(p["name"]) == "Katahdin":
			kat = p
	ok(not kat.is_empty(), "Katahdin is on the map")
	if not kat.is_empty():
		var kp: Array = kat["pos"]
		var pos := Vector3(float(kp[0]), 0.0, float(kp[1]))
		# documented: five kilometres north-east of the valley, 597 m tall
		near(pos.z, -5000.0, 400.0, "Katahdin is ~5 km north")
		ok(pos.x > 1500.0, "...and east of the valley")
		near(T.ground_y(pos), 597.0, 3.0, "Katahdin's summit is 597 m")
		ok(T.ground_y(pos) > T.ground_y(Vector3(pos.x + 900.0, 0, pos.z)), "it falls away to the east")
		ok(T.ground_y(pos) > T.ground_y(Vector3(pos.x, 0, pos.z + 900.0)), "and to the south")

	# every city stands on land
	var drowned := 0
	for p in places:
		var q: Array = p["pos"]
		if T.ground_y(Vector3(float(q[0]), 0, float(q[1]))) <= T.get("sea_level"):
			drowned += 1
	ok(drowned == 0, "no city is underwater (%d drowned)" % drowned)
	# and inside the map
	var outside := 0
	for p in places:
		var q: Array = p["pos"]
		if not T.pos_in_bounds(Vector3(float(q[0]), 0, float(q[1]))):
			outside += 1
	ok(outside == 0, "no city is off the map (%d outside)" % outside)


func _t_water(T: Node3D) -> void:
	sec("water")
	var NO: float = T.NO_WATER
	# far out to sea, south-east of everything
	var sea := Vector3(2000.0, 0.0, 1600.0)
	var sy: float = T.water_y(sea)
	ok(sy != NO, "there is water in the Gulf of Maine")
	if sy != NO:
		near(sy, T.get("sea_level"), 0.01, "the sea sits at sea level")
	ok(T.ground_y(sea) < T.get("sea_level"), "and the seabed is under it")
	# a summit is dry
	ok(T.water_y(Vector3(2329.0, 0, -5046.0)) == NO, "Katahdin's summit is dry")
	# every lake surface is above its own bed
	var bad := 0
	var checked := 0
	for l in T.lakes():
		var q: Array = l["pos"]
		var p := Vector3(float(q[0]), 0, float(q[1]))
		var wy: float = T.water_y(p)
		if wy == NO:
			continue
		checked += 1
		if wy <= T.ground_y(p):
			bad += 1
	ok(checked >= 20, "most lakes have water at their marker (%d/30)" % checked)
	ok(bad == 0, "no lake surface is under its own bed (%d bad)" % bad)


func _t_winding(T: Node3D) -> void:
	sec("mesh winding")
	# THE trap: Godot flips NORMAL on back faces even under cull_disabled, so a
	# backwards heightfield lights pitch black. Build a real tile and check.
	var tile: Node3D = T._make_tile(Vector2i(6, -30), 128.0, 8, true)
	ok(tile != null, "a tile out on the map builds")
	if tile == null:
		return
	var mi: MeshInstance3D = null
	var cs: CollisionShape3D = null
	for c in tile.get_children():
		if c is MeshInstance3D:
			mi = c
		elif c is CollisionShape3D:
			cs = c
	ok(mi != null, "the tile has a mesh")
	ok(cs != null, "the tile has a collider")
	if mi != null and mi.mesh != null:
		var arr: Array = mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		ok(verts.size() > 0, "the mesh has vertices")
		ok(norms.size() == verts.size(), "every vertex got a normal")
		var up := 0
		var down := 0
		for n in norms:
			if n.y > 0.0:
				up += 1
			elif n.y < 0.0:
				down += 1
		ok(down == 0, "no ground normal points DOWN (%d of %d did -- winding is backwards)"
			% [down, norms.size()])
		ok(up == norms.size(), "every ground normal points up")
		# vertices must sit at the sampled height
		var worst := 0.0
		for i in range(mini(verts.size(), 64)):
			var v: Vector3 = verts[i]
			worst = maxf(worst, absf(v.y - T.ground_y(Vector3(v.x, 0, v.z))))
		near(worst, 0.0, 0.01, "mesh vertices sit on the sampled surface")
	if cs != null:
		ok(cs.shape is HeightMapShape3D, "the collider is a heightmap")
		near(cs.scale.y, 1.0, 0.0001, "collider Y is never scaled (that would scale heights)")
		near(cs.scale.x, 16.0, 0.001, "collider X scale is the quad size")


func _t_valley(T: Node3D) -> void:
	sec("the spawn clearing")
	near(T.ground_y(Vector3.ZERO), 0.0, 0.01, "the valley floor is y = 0")
	near(T.ground_y(Vector3(60, 0, 0)), 0.0, 0.01, "...flat across the disc")
	near(T.ground_y(Vector3(0, 0, -100)), 0.0, 0.01, "...and to its north edge")
	ok(T.in_valley(Vector3(80, 0, 0)), "80 m out is still the clearing")
	ok(not T.in_valley(Vector3(600, 0, 0)), "600 m out is not")
	ok(absf(T.ground_y(Vector3(900, 0, 0))) > 0.01, "the real hills start outside the ease")
	ok(T.water_y(Vector3.ZERO) == T.NO_WATER, "no pond in the clearing")
	# the tile builder must leave the CaveRegion's SQUARE empty for its rock
	# top -- and mesh everything outside it, right up to the square's edge.
	# (It used to skip a 150 m CIRCLE around a 208 m square: a 46 m moat of
	# nothing ran round the valley with grass floating over it.)
	var tile: Node3D = T._make_tile(Vector2i(0, 0), 128.0, 32, true)
	ok(tile != null, "the origin tile builds (the square does not swallow it)")
	if tile != null:
		var mi: MeshInstance3D = null
		for c in tile.get_children():
			if c is MeshInstance3D:
				mi = c
		if mi != null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var inside := 0
			var moat := 0
			var half: float = T.HOLE_HALF
			for v in verts:
				if absf(v.x) < half - 0.01 and absf(v.z) < half - 0.01:
					inside += 1
				elif Vector2(v.x, v.z).length() < T.get("valley_flat") - 1.0:
					moat += 1
			ok(inside == 0, "no ground is meshed inside the cave square (%d verts were)" % inside)
			ok(moat > 0, "the ring between the square and the old circle IS meshed (%d verts)" % moat)
		else:
			ok(false, "the origin tile has no mesh")


func _t_forest(T: Node3D) -> void:
	sec("the forest")
	# --- LOD ring arithmetic. If these stop dividing evenly the rings overlap
	# and the ground z-fights, which is very hard to read as a spacing bug.
	ok(int(T.MID_SPAN) % int(T.NEAR_SPAN) == 0, "a mid tile is whole near tiles")
	ok(int(T.FAR_SPAN) % int(T.MID_SPAN) == 0, "a far block is whole mid tiles")
	ok(T._mid_to_near(Vector2i.ZERO) == 4, "4x4 near tiles cover a mid tile")
	ok(T._far_to_mid(Vector2i.ZERO) == 4, "4x4 mid tiles cover a far block")
	ok(T.NEAR_RANGE < T.MID_RANGE, "the mid ring reaches past the near ring")
	ok(T.REAL_R < T.NEAR_RANGE, "real trees stop inside the near ring")
	ok(T.TREE_VIS_END > T.REAL_R, "a real tree is still drawn at the edge of its ring")

	# --- the detail ladder must actually descend, and in the right order
	ok(T._lod_for(0.0) == "mid", "close tiles get the detailed bake")
	ok(T._lod_for(T.LOD_MID_DIST + 1.0) == "far", "past LOD_MID_DIST they get cards")
	ok(T._lod_for(T.LOD_FAR_DIST + 1.0) == "tiny", "past LOD_FAR_DIST they get sticks")
	ok(T.LOD_MID_DIST < T.LOD_FAR_DIST, "the bands are in order")
	ok(T.LOD_DENSITY["tiny"] >= T.LOD_DENSITY["mid"], "cheaper trees are allowed to be denser")

	# --- the far ring exists and covers the map
	ok(T._far.size() > 0, "the far ring built (%d blocks)" % T._far.size())
	var span: float = T.FAR_SPAN
	var need := int(ceil(float(T.nx) * T.step / span)) * int(ceil(float(T.nz) * T.step / span))
	ok(T._far.size() >= need, "far blocks cover the whole map (%d >= %d)" % [T._far.size(), need])
	# and the far ring is FORESTED, not just tinted -- the forest used to stop
	# dead at MID_RANGE and leave the last four kilometres as painted ground.
	if ResourceLoader.exists("res://assets/trees/glb/maple_2_mature.glb"):
		var st: Dictionary = T.forest_stats()
		ok(int(st["trees"]) > 5000, "the whole map is standing trees (%d)" % st["trees"])
		var per: float = float(st["tris"]) / maxf(float(st["trees"]), 1.0)
		ok(per <= 48.0, "the far ring uses the cheapest tier (%.1f tris/tree)" % per)

	# --- THE bug this section exists for. `_plantable` used to refuse anything
	# within valley_ease (340 m) of the origin "to protect the clearing", which
	# meant that with walking as the only travel, every metre of ground the
	# player could actually reach was bald. Measured before the fix: 0.0%
	# plantable from 0 to 340 m. Coverage, not just "a tree exists somewhere".
	ok(T.FOREST_INNER_R < T.valley_ease,
		"the forest starts well inside the valley ease (%.0f < %.0f)" % [T.FOREST_INNER_R, T.valley_ease])
	for band in [[110.0, 200.0], [200.0, 340.0], [340.0, 700.0]]:
		var hit := 0
		var tot := 0
		for i in range(600):
			var a := TAU * float(i) / 600.0
			var r: float = lerpf(band[0], band[1], float(i % 25) / 24.0)
			tot += 1
			if T._plantable(cos(a) * r, sin(a) * r) > 0.0:
				hit += 1
		var pct := 100.0 * float(hit) / float(tot)
		ok(pct > 40.0, "%.0f-%.0f m from spawn is forested (%.1f%%)" % [band[0], band[1], pct])
	# ...and the camp itself stays a clearing
	var camp := 0
	for i in range(200):
		var a := TAU * float(i) / 200.0
		if T._plantable(cos(a) * 60.0, sin(a) * 60.0) > 0.0:
			camp += 1
	ok(camp == 0, "the camp clearing is still clear (%d of 200 planted)" % camp)

	# --- what can be planted where
	near(T._plantable(0.0, 0.0), 0.0, 0.0001, "nothing is planted in the spawn clearing")
	var sea := Vector3(2000.0, 0.0, 1600.0)
	near(T._plantable(sea.x, sea.z), 0.0, 0.0001, "nothing is planted in the sea")
	near(T._plantable(999999.0, 0.0), 0.0, 0.0001, "nothing is planted off the map")
	var forested := 0
	var probes := 0
	for p in T.places():
		var q: Array = p["pos"]
		probes += 1
		if T._plantable(float(q[0]) + 300.0, float(q[1]) + 300.0) > 0.05:
			forested += 1
	ok(forested > probes / 5, "the land around towns is plantable (%d of %d)" % [forested, probes])

	# --- every region picks real species
	var all := ["maple", "birch", "oak", "pine", "fir"]
	for reg in ["temperate", "deepwood", "highland"]:
		var list: Array = T.LOD_SPECIES[reg]
		ok(list.size() > 0, "%s has species" % reg)
		var bad := 0
		for sp in list:
			if not (String(sp) in all):
				bad += 1
		ok(bad == 0, "%s only names species TreeV2 can build" % reg)

	# --- the far tint greens the horizon, and ONLY on the coarse rings
	var fx := 0.0
	var fz := 0.0
	for p in T.places():
		var q: Array = p["pos"]
		var cand := Vector3(float(q[0]) + 300.0, 0.0, float(q[1]) + 300.0)
		if T._plantable(cand.x, cand.z) > 0.4:
			fx = cand.x
			fz = cand.z
			break
	if fx != 0.0:
		var plain: Color = T._ground_tint(fx, fz, false)
		var tinted: Color = T._ground_tint(fx, fz, true)
		ok(plain == T.sample_color(fx, fz), "an untinted ring is the raw ground colour")
		ok(tinted != plain, "forested ground is tinted toward canopy on the coarse rings")
		ok(tinted.g > tinted.r and tinted.g > tinted.b, "...and the tint is green")
		ok(tinted.v <= plain.v + 0.001, "...and darker, like a canopy")
	else:
		ok(false, "could not find forested ground to tint")

	# --- the bakes. Skipped with a note if the models are not in this project,
	# because the suite has to stay runnable on a source-only checkout.
	if not ResourceLoader.exists("res://assets/trees/glb/maple_2_mature.glb"):
		ok(true, "tree models absent -- bake assertions skipped")
		return
	var tris := {}
	for lod in ["mid", "far", "tiny"]:
		var m: ArrayMesh = T._bake_species("maple", lod)
		ok(m != null, "maple bakes at lod %s" % lod)
		if m == null:
			continue
		var n := 0
		for i in range(m.get_surface_count()):
			n += m.surface_get_arrays(i)[Mesh.ARRAY_VERTEX].size() / 3
		tris[lod] = n
		ok(m.get_surface_count() == 2, "lod %s has a wood surface and a leaf surface" % lod)
	if tris.size() == 3:
		ok(tris["mid"] > tris["far"], "far is cheaper than mid (%d < %d)" % [tris["far"], tris["mid"]])
		ok(tris["far"] > tris["tiny"], "tiny is cheaper than far (%d < %d)" % [tris["tiny"], tris["far"]])
		ok(tris["tiny"] <= 40, "a tiny tree is %d triangles" % tris["tiny"])
		ok(tris["far"] <= 230, "a far tree is %d triangles" % tris["far"])

	# --- THE ask: distant trees must not move. TreeV2.materials_for()[2] is the
	# no-wind variant; every baked leaf surface has to be wearing it.
	var mats: Array = load("res://scripts/TreeV2.gd").materials_for("maple", false)
	ok(mats.size() >= 3, "TreeV2 offers a still-leaf material")
	for lod in ["mid", "far", "tiny"]:
		var m: ArrayMesh = T._bake_species("maple", lod)
		if m == null or m.get_surface_count() < 2:
			continue
		var lm := m.surface_get_material(m.get_surface_count() - 1) as ShaderMaterial
		ok(lm != null, "lod %s leaf surface has a material" % lod)
		if lm != null:
			ok(lm.get_shader_parameter("animated") == 0.0,
				"lod %s does NOT sway in the wind" % lod)
			ok(lm.get_shader_parameter("leaf_atlas") == mats[2].get_shader_parameter("leaf_atlas"),
				"lod %s wears the species' own leaf atlas" % lod)


func _t_hole(T: Node3D) -> void:
	sec("the hole in the ground is the cave block")
	# the square has to be the CaveRegion's footprint, exactly
	near(T.HOLE_HALF, CaveField.CELLS_X * CaveField.VOX * 0.5, 0.001,
		"HOLE_HALF is half the cave field's width")
	ok(T.HOLE_HALF < T.get("valley_flat"), "the square sits inside the flattened clearing")
	ok(T.HOLE_SINK < -CaveField.DEPTH, "the sunk collider is below the cave field's floor")
	ok(T.in_hole(Vector3(100, 0, -100)), "(100,-100) is in the hole")
	ok(not T.in_hole(Vector3(106, 0, 0)), "(106,0) is not")
	ok(not T.in_hole(Vector3(0, 0, -105)), "(0,-105) is not")
	# THE cave-sealing bug: the near tile's heightmap collider used to lay a
	# flat floor at y = 0 across the whole square, over both cave mouths.
	var tile: Node3D = T._make_tile(Vector2i(0, 0), 128.0, 32, true)
	var cs: CollisionShape3D = null
	if tile != null:
		for c in tile.get_children():
			if c is CollisionShape3D:
				cs = c
	ok(cs != null, "the origin tile has a collider")
	if cs != null:
		var hm := cs.shape as HeightMapShape3D
		var qs := 4.0
		var w := hm.map_width
		# sample (i, j) sits at world (i*qs, j*qs) for tile (0,0)
		var at_100: float = hm.map_data[(100 / 4) * w + (100 / 4)]
		var at_104: float = hm.map_data[(4 / 4) * w + (104 / 4)]
		var at_108: float = hm.map_data[(4 / 4) * w + (108 / 4)]
		var mouth: float = hm.map_data[(4 / 4) * w + (48 / 4)]
		near(at_100, T.HOLE_SINK, 0.001, "a collider sample inside the square is sunk")
		near(mouth, T.HOLE_SINK, 0.001, "...including over the cave mouths (x = 48)")
		near(at_104, T.ground_y(Vector3(104, 0, 4)), 0.01, "the boundary sample keeps its real height")
		near(at_108, T.ground_y(Vector3(108, 0, 4)), 0.01, "the first sample outside is real ground")
		# and NOTHING sunk leaks outside the square
		var leaked := 0
		for j in range(w):
			for i in range(w):
				var wx := float(i) * qs
				var wz := float(j) * qs
				if hm.map_data[j * w + i] <= T.HOLE_SINK + 0.001 \
						and not (absf(wx) < T.HOLE_HALF - 0.01 and absf(wz) < T.HOLE_HALF - 0.01):
					leaked += 1
		ok(leaked == 0, "no sunk sample outside the square (%d leaked)" % leaked)
	# a tile that does not touch the square is untouched
	var far_tile: Node3D = T._make_tile(Vector2i(6, -30), 128.0, 8, true)
	if far_tile != null:
		for c in far_tile.get_children():
			if c is CollisionShape3D:
				var hm2 := (c as CollisionShape3D).shape as HeightMapShape3D
				var lo := 1e9
				for v in hm2.map_data:
					lo = minf(lo, v)
				ok(lo > T.HOLE_SINK + 1.0, "a tile away from spawn has no sunk samples")


func _t_streamer_boot(T: Node3D) -> void:
	sec("the streamer wakes up at boot")
	# The first focus used to be Vector3.ZERO, and the camera starts at the
	# origin, so nothing built until you had walked REFOCUS_DIST (24 m). This
	# suite's Overworld has had one _process by now (there is no camera, so the
	# focus fell back to ZERO) -- the near ring must already be queued or built.
	# (This suite's _process runs BEFORE the nodes' this frame, so drive it.)
	T._process(0.016)
	ok(T._near.size() + T._queue.size() > 0,
		"the near ring is queued or built after the first frame (%d built, %d queued)"
		% [T._near.size(), T._queue.size()])
	T._queue.clear()
	var fresh = load("res://scripts/Overworld.gd").new()
	var f0: Vector3 = fresh.get("_focus")
	ok(not f0.is_finite(), "a fresh streamer's focus is unset, not the origin")
	fresh.free()


func _t_cells(T: Node3D) -> void:
	sec("the real trees travel with the player")
	if not ResourceLoader.exists("res://assets/trees/glb/maple_2_mature.glb"):
		ok(true, "tree models absent -- forest cell assertions skipped")
		return
	var a := Vector3(800.0, 0.0, -1600.0)   ## deep wood, forest weight ~0.7
	T.warm(a)
	ok(T._near.size() > 0, "warm() built a near ring (%d tiles)" % T._near.size())
	ok(T._cell_queue.is_empty(), "warm() promoted every cell in reach")
	var real: int = T.real_tree_count()
	ok(real > 0, "there are real trees around the focus (%d)" % real)
	# every real tree is within reach; none further
	var too_far := 0
	var streamed := 0
	var nodes: Array = []
	for k in T._plans.keys():
		for cell_nodes in (T._plans[k]["nodes"] as Array):
			for t in (cell_nodes as Array):
				if t == null or not is_instance_valid(t):
					continue
				nodes.append(t)
				if (t as Node).has_meta("streamed"):
					streamed += 1
				if Vector2((t as Node3D).position.x - a.x, (t as Node3D).position.z - a.z).length() > T.REAL_R + T.CELL:
					too_far += 1
	ok(too_far == 0, "no real tree stands further than REAL_R + a cell from the focus (%d did)" % too_far)
	ok(streamed == nodes.size(), "every real tree is flagged streamed (save skips it)")
	# they are TreeV2s, on the ground, and chop-able
	var tv := 0
	var on_ground := 0
	for t in nodes:
		if t is TreeV2:
			tv += 1
		if absf((t as Node3D).position.y - T.ground_y((t as Node3D).position)) < 0.05:
			on_ground += 1
	ok(tv == nodes.size(), "every real tree is a TreeV2 (%d of %d)" % [tv, nodes.size()])
	ok(on_ground == nodes.size(), "every real tree sits on the sampled ground")
	# a promoted cell has no impostor drawn for its slots; a far cell does
	var k0 := Vector2i(int(floor(a.x / T.NEAR_SPAN)), int(floor(a.z / T.NEAR_SPAN)))
	ok(T._near.has(k0), "the focus tile is live")
	if T._near.has(k0):
		var plan: Dictionary = T._plans[k0]
		var state: PackedInt32Array = plan["state"]
		var promoted := 0
		for st in state:
			promoted += st
		ok(promoted > 0, "cells on the focus tile are promoted (%d)" % promoted)
		var drawn := 0
		for c in (T._near[k0] as Node).get_children():
			if c is MultiMeshInstance3D and String(c.name).begins_with("Forest_"):
				drawn += (c as MultiMeshInstance3D).multimesh.instance_count
		var slots: int = (plan["pos"] as PackedVector3Array).size()
		var real_here := 0
		for cell_nodes in (plan["nodes"] as Array):
			real_here += (cell_nodes as Array).size()
		ok(drawn + real_here <= slots, "a slot is never drawn twice (%d baked + %d real <= %d slots)"
			% [drawn, real_here, slots])
		ok(drawn + real_here >= slots - int(T.felled_count()), "...and never dropped")
	# walk 800 m: the old woods demote, new ones grow around the new focus
	var b := Vector3(-800.0, 0.0, -1200.0)  ## 1.65 km away, weight ~0.6
	T.warm(b)
	var moved_far := 0
	for k in T._plans.keys():
		for cell_nodes in (T._plans[k]["nodes"] as Array):
			for t in (cell_nodes as Array):
				if t != null and is_instance_valid(t) \
						and Vector2((t as Node3D).position.x - b.x, (t as Node3D).position.z - b.z).length() > T.REAL_R + T.CELL:
					moved_far += 1
	ok(moved_far == 0, "after moving, no real tree is left behind at the old focus (%d)" % moved_far)
	ok(T.real_tree_count() > 0, "and the new focus has real trees (%d)" % T.real_tree_count())
	# determinism: the same tile plans the same slots twice
	var kb := Vector2i(int(floor(b.x / T.NEAR_SPAN)), int(floor(b.z / T.NEAR_SPAN)))
	if T._plans.has(kb):
		var p1: PackedVector3Array = (T._plans[kb]["pos"] as PackedVector3Array).duplicate()
		T._plans.erase(kb)
		var p2: PackedVector3Array = T._plan_tile(kb)["pos"]
		ok(p1 == p2, "a tile's slots are deterministic in its key")
		T._plans.erase(kb)
		T._plan_tile(kb)
		T._refresh_tile_cells(kb)
	# THE LEDGER: fell a tree, walk away, come back -- nothing regrows there
	var victim: TreeV2 = null
	var vk := Vector2i.ZERO
	var vcell := -1
	for k in T._plans.keys():
		var cells: Array = T._plans[k]["nodes"]
		for ci in range(cells.size()):
			if not (cells[ci] as Array).is_empty() and victim == null:
				victim = (cells[ci] as Array)[0] as TreeV2
				vk = k
				vcell = ci
	ok(victim != null, "found a real tree to fell")
	if victim != null:
		var slot := int(victim.get_meta("slot"))
		var before: int = ((T._plans[vk]["nodes"] as Array)[vcell] as Array).size()
		victim.felled = true            ## what _fell() does first
		T._demote_cell(vk, vcell)
		ok(T.felled_count() == 1, "the felled slot went into the ledger")
		ok(T._felled.has(T._slot_key(vk, slot)), "...under its own key")
		T._promote_cell(Vector3i(vk.x, vk.y, vcell))
		var after: int = ((T._plans[vk]["nodes"] as Array)[vcell] as Array).size()
		ok(after == before - 1, "coming back regrows every slot but the cut one (%d -> %d)" % [before, after])
		var regrew := false
		for t in ((T._plans[vk]["nodes"] as Array)[vcell] as Array):
			if int((t as Node).get_meta("slot")) == slot:
				regrew = true
		ok(not regrew, "no tree stands on the stump's slot")
		# and the ledger survives a save
		var saved: Dictionary = T.save_state()
		T.apply_state({})
		ok(T.felled_count() == 0, "apply_state({}) clears the ledger")
		T.apply_state(saved)
		ok(T.felled_count() == 1, "...and a saved ledger comes back")
		T._felled.clear()
	T.warm(Vector3.ZERO)


func _t_crowns(T: Node3D) -> void:
	sec("the distant crowns are solid")
	if not ResourceLoader.exists("res://assets/trees/glb/maple_2_mature.glb"):
		ok(true, "tree models absent -- crown assertions skipped")
		return
	for sp in ["maple", "birch", "oak", "pine", "fir"]:
		ok(T.BLOB_UV.has(sp), "%s has a pinned atlas texel" % sp)
		# the texel really is solid, 9 x 9 around it, in the actual atlas
		var path := "res://assets/trees/leaves/%s_leaf_atlas.png" % sp
		if ResourceLoader.exists(path):
			var tex: Texture2D = load(path)
			var img: Image = tex.get_image()
			if img != null:
				if img.is_compressed():
					img.decompress()
				var uv: Vector2 = T.BLOB_UV[sp]
				var px := int(uv.x * img.get_width())
				var py := int(uv.y * img.get_height())
				var clear := 0
				for dy in range(-4, 5):
					for dx in range(-4, 5):
						if img.get_pixel(clampi(px + dx, 0, img.get_width() - 1),
								clampi(py + dy, 0, img.get_height() - 1)).a < 0.98:
							clear += 1
				ok(clear == 0, "%s's blob texel is opaque 9x9 (%d clear texels)" % [sp, clear])
		for lod in ["far", "tiny"]:
			var m: ArrayMesh = T._bake_species(sp, lod)
			if m == null or m.get_surface_count() < 2:
				ok(false, "%s bakes at %s with a leaf surface" % [sp, lod])
				continue
			var arr: Array = m.surface_get_arrays(m.get_surface_count() - 1)
			var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var off := 0
			for u in uvs:
				if u.distance_to(T.BLOB_UV[sp]) > 0.0005:
					off += 1
			ok(off == 0, "%s %s: every crown vertex sits on the solid texel (%d did not)" % [sp, lod, off])
			# winding: the tip's (smoothed) normal points up, the base's down.
			# A flipped fan gives a tip normal pointing DOWN into the tree.
			var lo := 1e9
			var hi := -1e9
			for v in verts:
				lo = minf(lo, v.y)
				hi = maxf(hi, v.y)
			var tip_up := 0
			var tip_n := 0
			var base_down := 0
			var base_n := 0
			for i in range(verts.size()):
				if verts[i].y > hi - 0.01:
					tip_n += 1
					if norms[i].y > 0.5:
						tip_up += 1
				elif verts[i].y < lo + 0.01:
					base_n += 1
					if norms[i].y < -0.5:
						base_down += 1
			ok(tip_n > 0 and tip_up == tip_n, "%s %s: the crown tips face up (%d of %d)" % [sp, lod, tip_up, tip_n])
			ok(base_n > 0 and base_down == base_n, "%s %s: the crown bases face down (%d of %d)" % [sp, lod, base_down, base_n])
			ok(verts.size() / 3 >= 12, "%s %s: the crown has volume (%d tris)" % [sp, lod, verts.size() / 3])
			# it fills the crown, not the trunk: the lowest crown vertex is off the ground
			ok(lo > 0.2 and hi > lo + 1.0, "%s %s: the crown spans %.1f..%.1f m" % [sp, lod, lo, hi])


func _t_water_mesh(T: Node3D) -> void:
	sec("water off the map, not off the markers")
	var lakes: Node = T._water_root.get_node_or_null("Lakes")
	ok(lakes != null, "there is an inland water mesh")
	ok(T._inland_water_quads > 10000, "it covers the inland bodies (%d quads)" % T._inland_water_quads)
	if lakes != null:
		var mesh: ArrayMesh = (lakes as MeshInstance3D).mesh
		var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		ok(verts.size() == T._inland_water_quads * 4, "four vertices a quad")
		# no quad floats more than SKY_WATER_MAX over its bed, and none is sea
		var sky := 0
		var sea := 0
		var under := 0
		var i := 0
		while i < verts.size():
			var v: Vector3 = verts[i]
			var g: float = T.ground_y(v + Vector3(2.0, 0.0, 2.0))
			if v.y - g > T.SKY_WATER_MAX + 4.0:
				sky += 1
			if absf(v.y - T.get("sea_level")) < 0.4:
				sea += 1
			i += 4 * 97   ## a stride through the quads, ~1%
		ok(sky == 0, "no lake quad hangs in the sky (%d did)" % sky)
		ok(sea == 0, "the sea is not double-drawn as lake quads (%d were)" % sea)
		# winding: +Y up, like the ground
		var norms: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
		var down := 0
		for n in norms:
			if n.y <= 0.0:
				down += 1
		ok(down == 0, "every water normal points up")
	# Sebago's remnant (the marker itself may sit on the dry pan the valley
	# ease made) -- within 400 m of its marker there IS water
	var seb_wet := false
	for l in T.lakes():
		if String(l["name"]) == "Sebago Lake":
			var lp: Array = l["pos"]
			for i in range(24):
				var a := TAU * float(i) / 24.0
				for r in [0.0, 150.0, 300.0, 400.0]:
					if T.water_y(Vector3(float(lp[0]) + cos(a) * r, 0, float(lp[1]) + sin(a) * r)) != T.NO_WATER:
						seb_wet = true
	ok(seb_wet, "Sebago has water within 400 m of its marker")
	# the lake that floated 130 m over its valley (Rangeley-Kennebago): either
	# re-levelled onto its bed or dried -- never in the sky
	var kb := Vector3(-479.8, 0, -3040.1)
	var kw: float = T.water_y(kb)
	ok(kw == T.NO_WATER or kw - T.ground_y(kb) < 15.0,
		"Rangeley-Kennebago is not a lake in the sky (surface %.1f over ground %.1f)" % [kw, T.ground_y(kb)])
	# and the runtime guard itself: a raw surface 40 m over the bed reads dry
	var keep_w: PackedByteArray = T._w
	var probe := PackedByteArray()
	probe.resize(T.nx * T.nz * 2)
	var wv := int(round((float(T.ground_y(Vector3(0, 0, -600))) + 40.0 - T.w_min) / (T.w_max - T.w_min) * 65534.0)) + 1
	probe.encode_u16((clampi(int(round(T._row_of(-600.0))), 0, T.nz - 1) * T.nx + clampi(int(round(T._col_of(0.0))), 0, T.nx - 1)) * 2, wv)
	T._w = probe
	ok(T._w_raw(clampi(int(round(T._col_of(0.0))), 0, T.nx - 1), clampi(int(round(T._row_of(-600.0))), 0, T.nz - 1)) != T.NO_WATER,
		"(probe) the raw map says wet")
	ok(T.water_y(Vector3(0, 0, -600)) == T.NO_WATER, "sample_water() treats water 40 m over the bed as dry")
	T._w = keep_w
	# a sane lake still answers (at its own marker, wherever the bake put it)
	var moose := Vector3(1285.9, 0, -4120.1)
	for l in T.lakes():
		if String(l["name"]) == "Moosehead Lake":
			moose = Vector3(float(l["pos"][0]), 0, float(l["pos"][1]))
	ok(T.water_y(moose) != T.NO_WATER, "Moosehead still has water")
	var moose_d: float = T.water_y(moose) - T.ground_y(moose)
	ok(moose_d > 2.0 and moose_d < 40.0, "...a few metres deep at its marker (%.1f)" % moose_d)
	# the water MAP itself is sane: no inland surface under its bed, none more
	# than SKY_WATER_MAX over it. tools/water_relevel.py keeps it so (and
	# mainegen.py calls it); a re-bake that skips it fails here first.
	var under := 0
	var sky2 := 0
	var wet := 0
	var iz2 := 0
	while iz2 < T.nz:
		var ix2 := 0
		while ix2 < T.nx:
			var s: float = T._w_raw(ix2, iz2)
			if s != T.NO_WATER and absf(s - T.get("sea_level")) >= 0.4:
				wet += 1
				var bed: float = T._h_at(ix2, iz2)
				if s < bed - 0.5:
					under += 1
				if s - bed > T.SKY_WATER_MAX:
					sky2 += 1
			ix2 += 3
		iz2 += 3
	ok(wet > 5000, "the map has inland water (%d sampled cells)" % wet)
	ok(under == 0, "no inland water surface sits under its own bed (%d did)" % under)
	ok(sky2 == 0, "no inland water surface floats over SKY_WATER_MAX (%d did)" % sky2)
	# Portland is a town, not a lake: dry at the marker and no deep water within 200 m
	var flooded := 0
	for i in range(24):
		var a := TAU * float(i) / 24.0
		var p := Vector3(240.2 + cos(a) * 150.0, 0, 415.9 + sin(a) * 150.0)
		var wy2: float = T.water_y(p)
		if wy2 != T.NO_WATER and wy2 - T.ground_y(p) > 8.0:
			flooded += 1
	ok(flooded == 0, "Portland is not under a lake (%d deep-water probes of 24)" % flooded)
	# the old per-marker planes are gone
	var planes := 0
	for c in T._water_root.get_children():
		if String(c.name).begins_with("Lake_"):
			planes += 1
	ok(planes == 0, "no per-marker lake planes remain (%d)" % planes)


func _t_ground_look(T: Node3D) -> void:
	sec("the ground's colours")
	var m: Material = T._ground_material()
	ok(m != null, "the ground has a material")
	if m is ShaderMaterial:
		ok(ResourceLoader.exists("res://shaders/terrain_psx.gdshader"), "it is the terrain shader")
		near(float((m as ShaderMaterial).get_shader_parameter("sea_level")), T.get("sea_level"), 0.01,
			"the shader knows the sea level (for the beach band)")
		var code: String = (m as ShaderMaterial).shader.code
		ok(code.find("2.2") >= 0, "the shader linearises the sRGB vertex tints")
		ok(code.find("void light()") >= 0, "the shader has the banded light() the grass and bark use")
	elif m is StandardMaterial3D:
		ok((m as StandardMaterial3D).vertex_color_is_srgb, "vertex tints are declared sRGB (no pastel wash)")
	else:
		ok(false, "unknown ground material")
	var w: Material = T._water_material()
	ok(w != null, "water has a material")
	ok(T._water_root.get_node_or_null("Sea") != null, "the sea plane exists")


func _t_depth(T: Node3D) -> void:
	sec("depth is measured from the local surface")
	# Portland's ground is not the valley floor (world v2: +13; the 08-30 bake
	# had it at -17.7). Standing on it is depth 0, not |g| m down.
	var portland := Vector3(240.2, 0, 415.9)
	var g: float = T.ground_y(portland)
	ok(absf(g) > 5.0, "Portland is not at the valley floor's height (%.1f)" % g)
	near(T.depth_below_surface(Vector3(portland.x, g, portland.z)), 0.0, 0.01, "standing on Portland is depth 0")
	near(T.depth_below_surface(Vector3(portland.x, g - 4.0, portland.z)), 4.0, 0.01, "4 m under Portland is depth 4")
	near(T.depth_below_surface(Vector3(0, -5, 0)), 5.0, 0.01, "5 m under the valley floor is depth 5")
	ok(T.depth_below_surface(Vector3(portland.x, g + 30.0, portland.z)) < 0.0, "up in the air is negative")


func _t_name_collision(T: Node3D) -> void:
	sec("the class name is not shadowed")
	# TerraBrush registers a NATIVE, non-instantiable `Terrain` (Node3D). A
	# native ClassDB name beats a script class_name, so `class_name Terrain`
	# made Terrain.new() return null with no parse-time warning at all. If a
	# future addon ever registers `Overworld`, this fails before the game does.
	ok(not ClassDB.class_exists("Overworld"),
		"no native class has stolen the name Overworld")
	var made = load("res://scripts/Overworld.gd").new()
	ok(made != null, "the script instantiates by path")
	ok(made is Node3D, "...as a Node3D")
	if made != null:
		made.free()
	# and the thing that actually bit us, asserted directly
	if ClassDB.class_exists("Terrain"):
		ok(not ClassDB.can_instantiate("Terrain"),
			"the native Terrain (TerraBrush) is non-instantiable -- as expected")
	else:
		ok(true, "no native Terrain in this project")


func _t_safety(T: Node3D) -> void:
	sec("safe with the terrain off")
	# Everything must survive the singleton being gone: World.USE_TERRAIN false,
	# a headless tool, a test harness. These are static and must not crash.
	var S = load("res://scripts/Overworld.gd")
	var keep = S.inst
	S.inst = null
	near(S.ground_y(Vector3(500, 0, 500)), 0.0, 0.0001, "ground_y is 0 with no terrain")
	ok(S.water_y(Vector3(500, 0, 500)) == S.NO_WATER, "water_y is NO_WATER with no terrain")
	ok(S.in_bounds(Vector3(99999, 0, 99999)), "in_bounds is permissive with no terrain")
	ok(S.in_valley(Vector3(99999, 0, 0)), "in_valley is true with no terrain")
	S.inst = keep
	ok(S.inst == T, "the singleton is restored")
