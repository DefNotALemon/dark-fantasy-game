extends SceneTree
## Geometry + placement harness for GRASS v2.
## Runs the REAL Grass.gd against a stub CaveField (a synthetic rolling
## hillside), so every number below is measured off the actual meshes the
## game will instance, not off a lab copy.

var _pass := 0
var _fail := 0


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL  ", msg)


func _note(msg: String) -> void:
	print("        ", msg)


## ---------------------------------------------------------------- helpers ---

func _verts(m: ArrayMesh) -> PackedVector3Array:
	return m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array


func _norms(m: ArrayMesh) -> PackedVector3Array:
	return m.surface_get_arrays(0)[Mesh.ARRAY_NORMAL] as PackedVector3Array


func _uvs(m: ArrayMesh) -> PackedVector2Array:
	return m.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV] as PackedVector2Array


func _uv2s(m: ArrayMesh) -> PackedVector2Array:
	return m.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2] as PackedVector2Array


func _tris(m: ArrayMesh) -> int:
	var idx = m.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	if idx != null and (idx as PackedInt32Array).size() > 0:
		return (idx as PackedInt32Array).size() / 3
	return _verts(m).size() / 3


func _pairs(m: ArrayMesh) -> Array:
	## Matched edge pairs, read off the emission order rather than guessed by
	## proximity. In every triangle the builder emits, vertex 0 is the UV.x=0
	## edge and vertex 2 is the UV.x=1 edge; where they share a height they are
	## the two sides of the SAME blade at the SAME point along it. Pairing by
	## nearest-neighbour instead (the first version of this harness) silently
	## matched blades on opposite sides of the fan and reported nonsense.
	var v := _verts(m)
	var uv := _uvs(m)
	var nn := _norms(m)
	var out: Array = []
	for t in range(v.size() / 3):
		var i := t * 3
		if uv[i].x > 0.01 or uv[i + 2].x < 0.99:
			continue
		if absf(uv[i].y - uv[i + 2].y) > 0.001:
			continue
		out.append({"u": uv[i].y, "a": v[i], "b": v[i + 2],
			"mid": (v[i] + v[i + 2]) * 0.5, "na": nn[i], "nb": nn[i + 2],
			"w": v[i].distance_to(v[i + 2])})
	return out


func _radius_at(m: ArrayMesh, u_lo: float, u_hi: float) -> float:
	## Mean horizontal distance of the blade's CENTRE-LINE from the tuft axis.
	var sum := 0.0
	var n := 0
	for p in _pairs(m):
		if float(p["u"]) >= u_lo and float(p["u"]) <= u_hi:
			var mid: Vector3 = p["mid"]
			sum += Vector2(mid.x, mid.z).length()
			n += 1
	return sum / maxf(float(n), 1.0)


func _tip_radius(m: ArrayMesh) -> float:
	## The tip is a single collapsed vertex (UV.x = 0.5, UV.y = 1), so it has no
	## edge pair — read it directly.
	var v := _verts(m)
	var uv := _uvs(m)
	var sum := 0.0
	var n := 0
	for i in range(v.size()):
		if absf(uv[i].x - 0.5) < 0.01 and uv[i].y > 0.99:
			sum += Vector2(v[i].x, v[i].z).length()
			n += 1
	return sum / maxf(float(n), 1.0)


func _height_at(m: ArrayMesh, u_lo: float, u_hi: float) -> float:
	var v := _verts(m)
	var uv := _uvs(m)
	var sum := 0.0
	var n := 0
	for i in range(v.size()):
		if uv[i].y >= u_lo and uv[i].y <= u_hi:
			sum += v[i].y
			n += 1
	return sum / maxf(float(n), 1.0)


## ------------------------------------------------------------------ main ---

func _init() -> void:
	## root is not in the tree during _init, so add_child() would not fire
	## _ready() — run on the first real frame instead.
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	print("=========  GRASS v2 — geometry + placement  =========")
	## The REAL field, generated shallow: grass only ever reads the surface
	## rows, and shallow is what CaveRegion hands it at startup anyway.
	var field := CaveField.new()
	## CaveField.new() does NOT set origin — CaveRegion does, and grass reads it
	## for every world<->voxel conversion. Without this the whole map sits 104 m
	## off in x and z and 36 m too high, and not one tuft lands on the ground.
	field.origin = Vector3(-CaveField.CELLS_X * CaveField.VOX * 0.5, -CaveField.DEPTH,
		-CaveField.CELLS_Z * CaveField.VOX * 0.5)
	field.mouths = [Vector3(20, 0, -14), Vector3(-30, 0, 26)]
	field.dirs = [Vector3(0, 0, -1), Vector3(1, 0, 0)]   ## mouths and dirs are parallel arrays
	var t0 := Time.get_ticks_msec()
	field.generate(true)
	_note("real CaveField generated in %d ms" % (Time.get_ticks_msec() - t0))
	var gs := GrassSystem.new()
	root.add_child(gs)
	var t1 := Time.get_ticks_msec()
	gs.setup(field, 4457)
	_note("grass seeded over the whole map in %d ms" % (Time.get_ticks_msec() - t1))
	var st: Dictionary = gs.stats()
	_note("standing meadow: %d chunks, %d tufts" % [st["chunks"], st["tufts"]])

	print("\n-- 1. the meshes exist, at three levels of detail --")
	for kind in GrassSystem.KINDS:
		var lods: Array = gs._mesh[kind]
		_ok(lods.size() == 3, "%s has three LODs" % kind)
		for l in range(3):
			_ok(lods[l] is ArrayMesh and (lods[l] as ArrayMesh).get_surface_count() == 1,
				"%s LOD%d is a real surface" % [kind, l])

	print("\n-- 2. LOD actually sheds triangles --")
	var budget := {}
	for kind in GrassSystem.KINDS:
		var lods: Array = gs._mesh[kind]
		var t := [_tris(lods[0]), _tris(lods[1]), _tris(lods[2])]
		budget[kind] = t
		_ok(t[0] >= t[1] and t[1] >= t[2], "%s: %d -> %d -> %d tris" % [kind, t[0], t[1], t[2]])
		_note("%-7s hi %4d   mid %4d   lo %4d" % [kind, t[0], t[1], t[2]])
	_ok(int((budget["std"] as Array)[2]) <= 6, "a distant short tuft is <= 6 triangles")
	_ok(int((budget["std"] as Array)[0]) >= 20, "a near short tuft is a real curved plant")

	print("\n-- 3. a blade CURVES: the arc is not a straight lean --")
	## Straight-lean prediction from the base->mid slope, extended to the tip.
	## A genuine arc overshoots it, because the blade keeps tilting as it rises.
	for kind in ["std", "tall", "sedge"]:
		var m: ArrayMesh = (gs._mesh[kind] as Array)[0]
		var r_lo := _radius_at(m, 0.0, 0.13)
		var r_mid := _radius_at(m, 0.44, 0.56)
		var r_tip := _tip_radius(m)
		var linear := r_lo + (r_mid - r_lo) * 2.0
		_ok(r_tip > linear * 1.4,
			"%s tip radius %.3f overshoots the straight line %.3f" % [kind, r_tip, linear])
		_note("%-6s reach  base %.3f  mid %.3f  TIP %.3f m   (a straight lean would put the tip at %.3f)"
			% [kind, r_lo, r_mid, r_tip, linear])

	print("\n-- 4. a long blade tips over: the top droops back down --")
	## sedge is lean 1.15 + droop 1.30, so the tip passes horizontal (>90 deg).
	var sedge: ArrayMesh = (gs._mesh["sedge"] as Array)[0]
	var h_top := _height_at(sedge, 0.72, 0.86)
	var h_tip := _height_at(sedge, 0.94, 1.0)
	_ok(h_tip < h_top, "sedge falls back toward the ground (%.3f -> %.3f)" % [h_top, h_tip])
	var tall: ArrayMesh = (gs._mesh["tall"] as Array)[0]
	var th_mid := _height_at(tall, 0.45, 0.55)
	var th_tip := _height_at(tall, 0.94, 1.0)
	_ok(th_tip > th_mid, "the hiding grass still stands (%.3f -> %.3f)" % [th_mid, th_tip])
	var aabb := tall.get_aabb()
	_ok(aabb.size.y > 1.0 and aabb.size.y < 1.9,
		"tall tuft stands %.2f m — chest-high on a 1.8 m player" % aabb.size.y)
	_note("tall tuft AABB %.2f x %.2f x %.2f m" % [aabb.size.x, aabb.size.y, aabb.size.z])

	print("\n-- 5. a blade TAPERS to a point --")
	for kind in ["std", "tall", "sedge"]:
		var m2: ArrayMesh = (gs._mesh[kind] as Array)[0]
		var base_spread := _edge_spread(m2, 0.0, 0.12)
		var high_spread := _edge_spread(m2, 0.72, 0.88)
		_ok(high_spread < base_spread * 0.62,
			"%s narrows toward the tip (%.4f -> %.4f m)" % [kind, base_spread, high_spread])
		_note("%-6s width  base %.4f m  ->  three-quarters up %.4f m"
			% [kind, base_spread, high_spread])

	print("\n-- 6. ROUNDED NORMALS: the two edges of a flat strip disagree --")
	## This is the trick that makes a two-triangle strip light like a cylinder.
	for kind in ["std", "tall", "sedge", "fern", "clover", "moss"]:
		var m3: ArrayMesh = (gs._mesh[kind] as Array)[0]
		var best := 0.0
		var worst := 999.0
		for p in _pairs(m3):
			var ang := rad_to_deg((p["na"] as Vector3).angle_to(p["nb"] as Vector3))
			best = maxf(best, ang)
			worst = minf(worst, ang)
		if kind == "clover" or kind == "moss":
			_ok(best < 1.0, "%s stays flat (edge normals differ by %.1f deg)" % [kind, best])
		elif kind == "fern":
			## fronds use a gentler round (0.42 rad) than blades (0.58)
			_ok(best > 40.0 and best < 60.0, "fern rachis splay %.1f deg" % best)
		else:
			_ok(best > 60.0 and best < 72.0 and worst > 60.0,
				"%s edge normals splay %.1f deg apart (want ~66)" % [kind, best])
		_note("%-7s edge-normal splay %.1f deg" % [kind, best])
	for kind in GrassSystem.KINDS:
		var m4: ArrayMesh = (gs._mesh[kind] as Array)[0]
		var nn2 := _norms(m4)
		var bad := 0
		for n in nn2:
			if absf(n.length() - 1.0) > 0.01 or not is_finite(n.x + n.y + n.z):
				bad += 1
		_ok(bad == 0, "%s: every normal is a finite unit vector" % kind)

	print("\n-- 7. the material id rides UV2, so one shader covers eight kinds --")
	var expect := {"std": 0.0, "tall": 0.0, "sedge": 0.0, "clover": 0.0, "fern": 0.0,
		"stub": 2.0, "moss": 3.0, "bluestem": 5.0}
	for kind in expect:
		var m5: ArrayMesh = (gs._mesh[kind] as Array)[0]
		var ids := {}
		for u in _uv2s(m5):
			ids[u.x] = true
		_ok(ids.size() == 1 and ids.has(float(expect[kind])),
			"%s is tagged material %d" % [kind, int(expect[kind])])
	var flower: ArrayMesh = (gs._mesh["flower"] as Array)[0]
	var fids := {}
	for u in _uv2s(flower):
		fids[u.x] = true
	_ok(fids.has(0.0) and fids.has(1.0), "a wildflower is a green stem AND a petal head")

	print("\n-- 7b. the Maine species --")
	## TIMOTHY: green stem + straw seed-head spike, and the spike rides the top.
	var tim: ArrayMesh = (gs._mesh["timothy"] as Array)[0]
	var tids := {}
	for u in _uv2s(tim):
		tids[u.x] = true
	_ok(tids.has(0.0) and tids.has(4.0), "timothy is a green stem AND a seed-head spike")
	var tv := _verts(tim)
	var tuv := _uv2s(tim)
	var head_lo := 99.0
	var stem_hi := -99.0
	var head_hi := -99.0
	for i in range(tv.size()):
		if tuv[i].x > 3.5:
			head_lo = minf(head_lo, tv[i].y)
			head_hi = maxf(head_hi, tv[i].y)
		else:
			stem_hi = maxf(stem_hi, tv[i].y)
	_ok(head_hi > 0.70, "the spike tops out chest-high on the stem (%.2f m)" % head_hi)
	_ok(head_lo > stem_hi * 0.55, "the spike sits UP the stem, not at the boot (%.2f vs stem %.2f)" % [head_lo, stem_hi])
	for l in range(3):
		var ml: ArrayMesh = (gs._mesh["timothy"] as Array)[l]
		var has_head := false
		for u in _uv2s(ml):
			if u.x > 3.5:
				has_head = true
				break
		_ok(has_head, "timothy LOD%d keeps its seed head — it IS the identity" % l)
	## LITTLE BLUESTEM: upright bunch, knee-high, its own material.
	var blu: ArrayMesh = (gs._mesh["bluestem"] as Array)[0]
	var b_aabb := blu.get_aabb()
	_ok(b_aabb.size.y > 0.42 and b_aabb.size.y < 0.85,
		"bluestem stands knee-high (%.2f m)" % b_aabb.size.y)
	var std_m: ArrayMesh = (gs._mesh["std"] as Array)[0]
	_ok(b_aabb.size.y > std_m.get_aabb().size.y,
		"and taller than the fescue around it")
	var spread_ratio := b_aabb.size.x / b_aabb.size.y
	_ok(spread_ratio < 1.4, "upright bunch, not a splay (w/h %.2f)" % spread_ratio)

	print("\n-- 8. placement over a real (synthetic) hillside --")
	_note("%d x %d = %d chunks over the map" % [gs._ncx, gs._ncz, gs._ncx * gs._ncz])

	var key := Vector2i(8, 8)
	var placed: Dictionary = gs._place_chunk(key)
	var total := 0
	var kinds_seen := 0
	for kind in GrassSystem.KINDS:
		var n: int = (_of(placed, kind) as Array).size()
		total += n
		if n > 0:
			kinds_seen += 1
		_note("%-7s %4d" % [kind, n])
	_ok(total > 100, "the chunk grew something (%d tufts)" % total)
	_ok(kinds_seen >= 4, "%d different kinds of ground cover in one chunk" % kinds_seen)

	print("\n-- 9. tufts sit ON the ground, and lean with it --")
	var off_ground := 0
	var tilted := 0
	var checked := 0
	var non_finite := 0
	for kind in GrassSystem.KINDS:
		for t in (_of(placed, kind) as Array):
			var xf := t as Transform3D
			if not is_finite(xf.origin.x + xf.origin.y + xf.origin.z):
				non_finite += 1
				continue
			var ground := field.floor_point(Vector3i(
				int((xf.origin.x - field.origin.x) / CaveField.VOX), CaveField.SY - 2,
				int((xf.origin.z - field.origin.z) / CaveField.VOX)))
			if absf(xf.origin.y - ground.y) > 0.75:
				off_ground += 1
			var up := xf.basis.y.normalized()
			if up.angle_to(Vector3.UP) > deg_to_rad(1.5):
				tilted += 1
			checked += 1
	_ok(non_finite == 0, "no NaN transforms")
	_ok(off_ground == 0, "every tuft is planted on the surface (%d checked)" % checked)
	## The current blockout ground is FLAT — World._build_ground lays a plane and
	## the Maine heightmap from claude/terrain-blockout.md is not in the game
	## yet. So the honest assertion is: on flat ground nothing tilts (correct),
	## and the tilt maths itself works when there IS a slope to read.
	_note("%d of %d tufts tilted — the blockout ground is flat, so 0 is right" % [tilted, checked])
	var flat := gs._ground_basis(Vector3.ZERO, Vector3(0.8, 0.0, 0.0), Vector3(0.0, 0.0, 0.8), 0.0, 0.42)
	_ok(flat.y.angle_to(Vector3.UP) < deg_to_rad(0.5), "flat ground grows vertical grass")
	## a 1-in-2 slope: 0.4 m of rise over 0.8 m of run = 26.6 degrees
	var slope := gs._ground_basis(Vector3.ZERO, Vector3(0.8, 0.4, 0.0), Vector3(0.0, 0.0, 0.8), 0.0, 0.42)
	var tilt := rad_to_deg(slope.y.angle_to(Vector3.UP))
	_ok(tilt > 8.0 and tilt < 22.0,
		"a 26.6 deg hillside leans the tuft %.1f deg — part way, not all the way" % tilt)
	_ok(absf(slope.x.dot(slope.y)) < 0.001 and absf(slope.x.length() - 1.0) < 0.001,
		"the tilted basis stays orthonormal")
	var steep := gs._ground_basis(Vector3.ZERO, Vector3(0.8, 0.8, 0.0), Vector3(0.0, 0.0, 0.8), 0.0, 0.42)
	_ok(rad_to_deg(steep.y.angle_to(Vector3.UP)) > tilt, "a steeper bank leans it further")
	_note("gravitropism check: 26.6 deg ground -> %.1f deg lean, 45 deg ground -> %.1f deg lean"
		% [tilt, rad_to_deg(steep.y.angle_to(Vector3.UP))])

	print("\n-- 10. placement is deterministic (stubble must land where the blades stood) --")
	var again: Dictionary = gs._place_chunk(key)
	var same := true
	for kind in GrassSystem.KINDS:
		var a: Array = _of(placed, kind)
		var b: Array = _of(again, kind)
		if a.size() != b.size():
			same = false
			break
		for i in range(a.size()):
			if (a[i] as Transform3D).origin.distance_to((b[i] as Transform3D).origin) > 0.0001:
				same = false
				break
	_ok(same, "the same chunk places identically twice")

	print("\n-- 11. the sword mows: tall grass becomes stubble in the same spot --")
	var tall_before: Array = (_of(placed, "tall") as Array).duplicate()
	if tall_before.is_empty():
		_note("(no tall grass in this chunk — searching for one that has it)")
		for cx in range(4, 13):
			for cz in range(4, 13):
				var k2 := Vector2i(cx, cz)
				var pl2: Dictionary = gs._place_chunk(k2)
				if (_of(pl2, "tall") as Array).size() > 4:
					key = k2
					placed = pl2
					tall_before = (_of(pl2, "tall") as Array).duplicate()
					break
			if not tall_before.is_empty():
				break
	_ok(not tall_before.is_empty(), "found standing tall grass to cut")
	if not tall_before.is_empty():
		var spot := (tall_before[0] as Transform3D).origin
		_ok(gs.is_tall_at(spot.x, spot.z), "that patch hides you while it stands")
		gs._cut_cells[gs._cut_cell(spot.x, spot.z)] = true
		_ok(not gs.is_tall_at(spot.x, spot.z), "and stops hiding you once it is mown")
		var after: Dictionary = gs._place_chunk(key)
		var found := false
		for t in (_of(after, "stub") as Array):
			if (t as Transform3D).origin.distance_to(spot) < 0.0001:
				found = true
				break
		_ok(found, "a flat-topped stump now stands exactly where the blades did")
		_ok((_of(after, "tall") as Array).size() < tall_before.size(),
			"and the standing count went down (%d -> %d)"
				% [tall_before.size(), (_of(after, "tall") as Array).size()])
		gs._cut_cells.clear()

	print("\n-- 12. the whole-map cost, measured --")
	var per_chunk := {}
	var sample := 0
	var grand := {}
	for kind in GrassSystem.KINDS:
		grand[kind] = 0
	for cx in range(0, gs._ncx, 3):
		for cz in range(0, gs._ncz, 3):
			var pl: Dictionary = gs._place_chunk(Vector2i(cx, cz))
			for kind in GrassSystem.KINDS:
				grand[kind] = int(grand[kind]) + (_of(pl, kind) as Array).size()
			sample += 1
	var scale := float(gs._ncx * gs._ncz) / float(sample)
	var world_tufts := 0
	var tri_hi := 0
	var tri_lo := 0
	for kind in GrassSystem.KINDS:
		var est := int(float(grand[kind]) * scale)
		world_tufts += est
		tri_hi += est * int((budget[kind] as Array)[0])
		tri_lo += est * int((budget[kind] as Array)[2])
		_note("%-7s ~%7d tufts world-wide" % [kind, est])
	_note("TOTAL   ~%d tufts; %s triangles if every one were near, %s if every one were far"
		% [world_tufts, _commas(tri_hi), _commas(tri_lo)])
	## Only the chunks inside LOD_HI are ever near. A 15 m radius over 12.8 m
	## chunks is about a dozen chunks of the 289.
	var near_frac := (PI * GrassSystem.LOD_HI * GrassSystem.LOD_HI) \
		/ float(gs._ncx * gs._ncz * GrassSystem.CHUNK_CELLS * GrassSystem.CHUNK_CELLS
			* CaveField.VOX * CaveField.VOX)
	var mid_frac := (PI * GrassSystem.LOD_MID * GrassSystem.LOD_MID) \
		/ float(gs._ncx * gs._ncz * GrassSystem.CHUNK_CELLS * GrassSystem.CHUNK_CELLS
			* CaveField.VOX * CaveField.VOX) - near_frac
	var cull_frac := (PI * GrassSystem.CULL_END * GrassSystem.CULL_END) \
		/ float(gs._ncx * gs._ncz * GrassSystem.CHUNK_CELLS * GrassSystem.CHUNK_CELLS
			* CaveField.VOX * CaveField.VOX)
	var drawn := int(float(world_tufts) * cull_frac)
	var est_tris := int(float(tri_hi) * near_frac) \
		+ int(float(tri_hi) * mid_frac * 0.35) \
		+ int(float(tri_lo) * maxf(cull_frac - near_frac - mid_frac, 0.0))
	_note("of those, ~%s are inside the %.0f m draw ring at any moment"
		% [_commas(drawn), GrassSystem.CULL_END])
	_note("=> roughly %s triangles of grass on screen — v1 drew ~%s and could not curve"
		% [_commas(est_tris), _commas(int(float(world_tufts) * cull_frac * 4.0))])
	_ok(est_tris < 900000, "the standing meadow fits a sane triangle budget")

	print("\n-- 13. the shader --")
	var sh := Shader.new()
	sh.code = GrassSystem.GRASS_SHADER
	_ok(sh.code.length() > 500, "shader source is attached")
	for needed in ["global uniform vec3 wind_dir", "global uniform float wind_strength",
			"global uniform float season_phase", "global uniform float player_push",
			"FRONT_FACING", "cull_disabled"]:
		_ok(sh.code.contains(needed), "shader uses %s" % needed)
	_ok(not sh.code.contains("inverse(MODEL_MATRIX)"),
		"no 4x4 inverse per vertex (the transpose trick is in)")
	for px in ["pixel_cells", "palette_steps", "void light()", "col_bluestem_cured", "col_seedhead"]:
		_ok(sh.code.contains(px), "pixel-style shader carries %s" % px)
	_ok(sh.code.contains("floor(col * palette_steps"), "the palette is posterized")
	_ok(not sh.code.contains("BACKLIGHT ="), "no smooth backlight — banded in light() instead")

	print("\n-- 14. the runtime path: MultiMeshes, and LOD swapping under your feet --")
	var live: Dictionary = gs._place_chunk(key)
	gs._apply_chunk(key, live)
	_ok(gs._chunks.has(key), "the chunk built its MultiMeshes")
	var per_kind: Dictionary = gs._chunks[key]
	var born := 0
	for kind: String in per_kind:
		var mmi := per_kind[kind] as MultiMeshInstance3D
		_ok(mmi.multimesh != null and mmi.multimesh.instance_count > 0,
			"%s has live instances" % kind)
		_ok(mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"%s casts no shadow (grass shadows are not worth the pass)" % kind)
		var want_cull: float = GrassSystem.DETAIL_CULL if GrassSystem.DETAIL_KINDS.has(kind) \
			else GrassSystem.CULL_END
		_ok(absf(mmi.visibility_range_end - want_cull) < 0.01,
			"%s culls at %.0f m" % [kind, mmi.visibility_range_end])
		_ok(mmi.material_override == gs._mat, "%s shares the one grass material" % kind)
		born += 1
	_ok(born <= GrassSystem.KINDS.size(),
		"only the kinds that actually grow here got a node (%d of %d)"
			% [born, GrassSystem.KINDS.size()])
	_note("%d MultiMeshInstances for this chunk, not %d" % [born, GrassSystem.KINDS.size()])

	## Walk toward the chunk and confirm the meshes actually change under you.
	var centre := gs._chunk_center(key)
	var seen: Array = []
	for d in [90.0, 25.0, 4.0, 90.0]:
		gs._update_lod(centre + Vector3(d, 0, 0))
		var kind0: String = per_kind.keys()[0]
		var mm := (per_kind[kind0] as MultiMeshInstance3D).multimesh
		var which := -1
		for l in range(3):
			if mm.mesh == (gs._mesh[kind0] as Array)[l]:
				which = l
		seen.append(which)
		_ok(which >= 0, "at %.0f m the chunk points at a real LOD mesh" % d)
	_ok(seen[0] == 2 and seen[1] == 1 and seen[2] == 0 and seen[3] == 2,
		"LOD follows you in and back out again: %s" % str(seen))
	_note("far -> mid -> near -> far  =  LOD %s" % str(seen))
	var kind_check: String = per_kind.keys()[0]
	var n_before: int = (per_kind[kind_check] as MultiMeshInstance3D).multimesh.instance_count
	gs._update_lod(centre)
	var n_after: int = (per_kind[kind_check] as MultiMeshInstance3D).multimesh.instance_count
	_ok(n_before == n_after,
		"swapping detail does NOT touch the instance buffer (%d tufts before and after)" % n_after)

	print("\n=====================================================")
	print("  %d passed, %d failed" % [_pass, _fail])
	print("=====================================================")
	quit(1 if _fail > 0 else 0)


func _edge_spread(m: ArrayMesh, u_lo: float, u_hi: float) -> float:
	## How wide the blade actually is in that height band.
	var sum := 0.0
	var n := 0
	for p in _pairs(m):
		if float(p["u"]) >= u_lo and float(p["u"]) <= u_hi:
			sum += float(p["w"])
			n += 1
	return sum / maxf(float(n), 1.0)


func _of(placed: Dictionary, kind: String) -> Array:
	## Placement comes back indexed by kind INDEX (the worker threads must not
	## touch shared Strings — see GrassSystem.K_STD). Put the name back on here.
	return (placed["xf"] as Array)[GrassSystem.KINDS.find(kind)] as Array


func _commas(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out
