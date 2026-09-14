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

	print("\n-- 7c. v2.4: the fescue is mown-short, and cut still reads as cut --")
	## Height is the one knob that moves FILL RATE rather than triangles, and
	## fescue is ~78% of every tuft in the world, so this number is most of the
	## frame budget. Pin it: a regression that quietly restores 0.44 m would
	## cost more than any geometry change in this file.
	var std_h := std_m.get_aabb().size.y
	_ok(std_h > 0.12 and std_h < 0.26,
		"red fescue stands ankle-height (%.2f m — it was 0.50)" % std_h)
	var stub_m: ArrayMesh = (gs._mesh["stub"] as Array)[0]
	var stub_h := stub_m.get_aabb().size.y
	_ok(stub_h < std_h * 0.55,
		"mown stubble still reads shorter than the grass around it (%.2f vs %.2f m)"
			% [stub_h, std_h])
	_note("fescue %.2f m, stubble %.2f m — %.0f%% of the v2.3 blade height"
		% [std_h, stub_h, 100.0 * std_h / 0.4956])
	_ok(int((budget["std"] as Array)[0]) < 35,
		"and a near fescue tuft is lighter than v2.3's 35 triangles (%d now)"
			% int((budget["std"] as Array)[0]))

	print("\n-- 8. placement over a real (synthetic) hillside --")
	_note("the valley is %d x %d chunks; the world beyond it is unbounded" % [gs._ncx, gs._ncz])

	## v2.5: chunk keys are WORLD-space — floor(world / 12.8) — not CaveField
	## chunk indices, and they run negative. The valley spans ±108.8 m, so keys
	## −8 .. 7 sit inside it. Vector2i(8, 8) is now (102 .. 115 m), straddling
	## the rim; with no Overworld in a headless harness the outside half grows
	## nothing and every count below would quietly halve.
	var key := Vector2i(-2, 3)
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
		for cx in range(-7, 7):
			for cz in range(-7, 7):
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

	print("\n-- 12. the cost of the RING, measured --")
	## v2.5: "the whole map" stopped being a number. The map is 78 km² and the
	## meadow streams, so the only quantity that costs frames is what stands
	## inside draw_dist of you. Measure a chunk, then integrate the ring.
	var per_chunk := {}
	var sample := 0
	for kind in GrassSystem.KINDS:
		per_chunk[kind] = 0
	for cx in range(-7, 8, 2):
		for cz in range(-7, 8, 2):
			var pl: Dictionary = gs._place_chunk(Vector2i(cx, cz))
			for kind in GrassSystem.KINDS:
				per_chunk[kind] = int(per_chunk[kind]) + (_of(pl, kind) as Array).size()
			sample += 1
	var chunk_area := GrassSystem.CHUNK_M * GrassSystem.CHUNK_M
	var dens := 0.0                 ## tufts per m²
	var hi_rate := 0.0              ## triangles per m² if every tuft drew its hi mesh
	var lo_rate := 0.0              ## ...and its lo mesh
	for kind in GrassSystem.KINDS:
		var mean := float(per_chunk[kind]) / float(sample)
		dens += mean / chunk_area
		hi_rate += mean * float((budget[kind] as Array)[0]) / chunk_area
		lo_rate += mean * float((budget[kind] as Array)[2]) / chunk_area
		if mean >= 1.0:
			_note("%-7s %6.0f per 12.8 m chunk" % [kind, mean])
	_note("density %.1f tufts/m²  (%.0f per chunk)" % [dens, dens * chunk_area])

	## The bands, as areas rather than fractions of a fixed map.
	var d0 := gs.draw_dist
	var near_a := PI * GrassSystem.LOD_HI * GrassSystem.LOD_HI
	var mid_a := PI * GrassSystem.LOD_MID * GrassSystem.LOD_MID - near_a
	var fade_r := d0 * GrassSystem.FADE_START_F
	var full_a := maxf(PI * fade_r * fade_r - near_a - mid_a, 0.0)
	var thin_a := maxf(PI * d0 * d0 - PI * fade_r * fade_r, 0.0)
	## Past the fade line the chunk keeps its far mesh but draws only FAR_KEEP
	## of its instances — the thing that makes a 90 m ring affordable at all.
	var drawn := int(dens * (near_a + mid_a + full_a + thin_a * GrassSystem.FAR_KEEP))
	var est_tris := int(hi_rate * near_a) \
		+ int(hi_rate * 0.35 * mid_a) \
		+ int(lo_rate * (full_a + thin_a * GrassSystem.FAR_KEEP))
	_note("at %.0f m: ~%s tufts standing, ~%s triangles of grass on screen"
		% [d0, _commas(drawn), _commas(est_tris)])
	_note("without the far thinning it would be ~%s tufts"
		% _commas(int(dens * (near_a + mid_a + full_a + thin_a))))
	_ok(est_tris < 1000000, "the ring fits a sane triangle budget")
	_ok(drawn < 300000, "and a sane instance budget")

	## The setting has to actually buy something. Area squares, so halving the
	## ring should quarter it — this is the claim the Esc menu's note makes.
	var lo_r := 45.0
	var lo_fade := lo_r * GrassSystem.FADE_START_F
	var lo_full := maxf(PI * lo_fade * lo_fade - near_a - mid_a, 0.0)
	var lo_thin := maxf(PI * lo_r * lo_r - PI * lo_fade * lo_fade, 0.0)
	var lo_drawn := int(dens * (near_a + mid_a + lo_full + lo_thin * GrassSystem.FAR_KEEP))
	_note("at %.0f m (Low): ~%s tufts — %.0f%% of Medium"
		% [lo_r, _commas(lo_drawn), 100.0 * float(lo_drawn) / maxf(float(drawn), 1.0)])
	_ok(float(lo_drawn) / maxf(float(drawn), 1.0) < 0.45,
		"Draw Distance Low really is well under half of Medium")

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
	## Distances are measured to the chunk's EDGE — _update_lod subtracts the
	## 6.4 m half-chunk — and v2.4 pulled the bands in (hi 9 m, mid 16 m). The
	## mid sample moves 25 m -> 20 m accordingly: 20 - 6.4 = 13.6 m, which is
	## mid. Left at 25 m it would band as FAR and this would assert nothing.
	for d in [90.0, 20.0, 4.0, 90.0]:
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

	print("\n-- 15. the ring: the meadow streams, and grows back the same --")
	## THE CONTRACT THAT MAKES FREEING A CHUNK SAFE. Placement is deterministic
	## in the WORLD key, so walking away from a meadow and walking back gives
	## you the same tufts in the same spots — including the flat stubble
	## wherever you mowed, because _cut_cells is a sparse world-space record
	## that outlives the chunk that drew it. Break this and the world reshuffles
	## itself behind your back.
	var far_key := Vector2i(400, 400)          ## 5.1 km from spawn, never seen
	var fa: Dictionary = gs._place_chunk(far_key)
	var fb: Dictionary = gs._place_chunk(far_key)
	var det := true
	for kind in GrassSystem.KINDS:
		var aa: Array = _of(fa, kind)
		var bb: Array = _of(fb, kind)
		if aa.size() != bb.size():
			det = false
			break
		for i in range(aa.size()):
			if (aa[i] as Transform3D).origin.distance_to((bb[i] as Transform3D).origin) > 0.0001:
				det = false
				break
	_ok(det, "a chunk five kilometres from spawn places identically twice")

	gs.warm(Vector3.ZERO)
	var n_spawn := gs._chunks.size()
	_ok(n_spawn > 0, "warm() built a ring at spawn (%d chunks)" % n_spawn)
	var outside := 0
	for k2: Vector2i in gs._chunks:
		if gs._chunk_dist(k2) > gs.draw_dist * GrassSystem.STREAM_KEEP:
			outside += 1
	_ok(outside == 0, "every live chunk is inside the ring (%d strays)" % outside)

	## Walk out of the valley and the old ring must be GONE, not merely hidden —
	## a streamer that only hides is a memory leak with a view.
	var before_keys := {}
	for k3: Vector2i in gs._chunks:
		before_keys[k3] = true
	gs.warm(Vector3(400.0, 0.0, 0.0))
	var overlap := 0
	for k4: Vector2i in gs._chunks:
		if before_keys.has(k4):
			overlap += 1
	_ok(overlap == 0, "walking 400 m frees the whole old ring (%d kept)" % overlap)
	gs.warm(Vector3.ZERO)
	_ok(gs._chunks.size() == n_spawn,
		"and walking back rebuilds exactly the same ring (%d -> %d)"
			% [n_spawn, gs._chunks.size()])

	## Draw Distance (Esc) has to move everything, not just the cull ring.
	gs.set_draw_distance(45.0)
	gs.warm(Vector3.ZERO)
	var n_low := gs._chunks.size()
	var ratio := float(n_low) / maxf(float(n_spawn), 1.0)
	_ok(n_low < n_spawn, "Low streams fewer chunks than Medium (%d vs %d)" % [n_low, n_spawn])
	_ok(ratio < 0.40, "and the area squares — Low is %.0f%% of Medium" % (ratio * 100.0))
	var worst_vr := 0.0
	for k5: Vector2i in gs._chunks:
		for kind: String in gs._chunks[k5]:
			var mmi5 := gs._chunks[k5][kind] as MultiMeshInstance3D
			if not GrassSystem.DETAIL_KINDS.has(kind):
				worst_vr = maxf(worst_vr, mmi5.visibility_range_end)
	_ok(absf(worst_vr - 45.0) < 0.01,
		"every live chunk's cull range followed the setting (%.0f m)" % worst_vr)
	gs.set_draw_distance(GrassSystem.CULL_END)
	gs.warm(Vector3.ZERO)
	_ok(absf(gs.draw_dist - GrassSystem.CULL_END) < 0.01, "and it goes back")

	## The far thinning: past the fade line a chunk keeps its mesh and drops
	## most of its instances. This is what pays for the 90 m default.
	gs._update_lod(Vector3.ZERO)
	var thinned := 0
	var full := 0
	var overclaim := 0
	var thin_shown := 0
	var thin_held := 0
	for k6: Vector2i in gs._chunks:
		for kind: String in gs._chunks[k6]:
			var mm6 := (gs._chunks[k6][kind] as MultiMeshInstance3D).multimesh
			if mm6 == null:
				continue
			if mm6.visible_instance_count < 0:
				full += 1
				continue
			thinned += 1
			thin_shown += mm6.visible_instance_count
			thin_held += mm6.instance_count
			if mm6.visible_instance_count > mm6.instance_count:
				overclaim += 1
	_ok(thinned > 0 and full > 0,
		"past the fade line the meadow thins, inside it does not (%d thinned, %d full)"
			% [thinned, full])
	_ok(overclaim == 0, "no thinned MultiMesh claims more instances than it holds")
	if thin_held > 0:
		var shown := float(thin_shown) / float(thin_held)
		_ok(absf(shown - GrassSystem.FAR_KEEP) < 0.05,
			"a thinned chunk draws FAR_KEEP of its tufts (%.2f vs %.2f)"
				% [shown, GrassSystem.FAR_KEEP])
		_note("thinned band draws %.0f%% of what it holds — %s tufts hidden for free"
			% [shown * 100.0, _commas(thin_held - thin_shown)])

	print("\n-- 16. v3.1: the horizon, the towns and the paving --")
	## THE HORIZON. The GPU field's band table is arithmetic nobody can see
	## until they are standing on a mountain, so check its shape here: the
	## radii climb, every parallel table is the same length, and the hollow
	## grid a band addresses is sized by the rule the process shader's slot
	## addressing assumes (both sides EVEN, count = S^2 - Si^2).
	var br: Array = GrassGPU.BAND_R
	var climbing := true
	for i in range(br.size() - 1):
		if float(br[i + 1]) <= float(br[i]):
			climbing = false
	_ok(climbing, "the band radii climb, 0 -> %.0f m" % float(br[br.size() - 1]))
	_ok(br.size() - 1 == GrassGPU.BANDS
		and GrassGPU.BAND_MESH.size() == GrassGPU.BANDS
		and GrassGPU.BAND_KEEP.size() == GrassGPU.BANDS
		and GrassGPU.BAND_SCALE.size() == GrassGPU.BANDS
		and GrassGPU.BAND_FADE.size() == GrassGPU.BANDS,
		"%d bands, and every parallel table agrees" % GrassGPU.BANDS)
	_ok(float(br[GrassGPU.RING_BAND + 1]) == float(br[GrassGPU.FAR_BAND]),
		"the first horizon band starts where the draw ring ends (%.0f m)"
			% float(br[GrassGPU.FAR_BAND]))
	var horizon := float(br[GrassGPU.BANDS])
	_ok(horizon >= 300.0, "the grass reaches %.0f m, not %.0f" % [horizon, GrassSystem.CULL_END])
	var far_thin := float(GrassGPU.BAND_KEEP[GrassGPU.BANDS - 1]) < 0.05
	var far_big := float(GrassGPU.BAND_SCALE[GrassGPU.BANDS - 1]) > 2.0
	_ok(far_thin and far_big, "the last band is thin (%.3f) and its tufts are big (x%.1f)"
		% [float(GrassGPU.BAND_KEEP[GrassGPU.BANDS - 1]),
			float(GrassGPU.BAND_SCALE[GrassGPU.BANDS - 1])])
	_ok(float(GrassGPU.BAND_FADE[GrassGPU.FAR_BAND]) < 0.75
		and float(GrassGPU.BAND_FADE[0]) > 0.75,
		"a horizon blade carries the FAR fade flag, a ring blade the near one")
	var gpu := GrassGPU.new()
	var pm := ShaderMaterial.new()
	var cnt := gpu._size_grid(pm, 1.0, 40.0, 100.0)
	var gs_S := int(pm.get_shader_parameter("grid_S"))
	var gs_Si := int(pm.get_shader_parameter("grid_Si"))
	_ok(gs_S % 2 == 0 and gs_Si % 2 == 0, "both sides of the hollow grid are even (%d, %d)"
		% [gs_S, gs_Si])
	_ok(cnt == gs_S * gs_S - gs_Si * gs_Si and gs_Si < gs_S,
		"the band allocates the ring and not the hole it will never draw (%s cells)"
			% _commas(cnt))
	_ok(int(pm.get_shader_parameter("grid_t")) * 2 == gs_S - gs_Si,
		"the strip width is half the difference — the slot addressing assumes it")
	_note("horizon %.0f m; a 90-460 m field is ~%s cells against the ring's own"
		% [horizon, _commas(cnt)])
	gpu.free()

	## The material carries BOTH fades, and the blade picks one off COLOR.a.
	var src: String = GrassSystem.GRASS_SHADER
	_ok(src.contains("uniform float fade_start_far") and src.contains("uniform float fade_end_far"),
		"the grass shader declares the horizon fade")
	_ok(src.contains("(COLOR.a < 0.75) ? fade_start_far : fade_start"),
		"...and a blade picks its fade off the flag the placer set")
	var gsrc: String = GrassGPU.PLACE_SHADER
	_ok(gsrc.contains("uniform float band_scale") and gsrc.contains("* band_scale"),
		"the process shader grows the far tufts")
	_ok(gsrc.contains("uniform vec4 skip_rect[8]") and gsrc.contains("skip_n"),
		"...and steps out of a town's rect the way it steps out of the valley")
	_ok(gsrc.contains("col.a = fade_flag"),
		"even a dead particle carries the fade flag (it is read before it is drawn)")

	## THE TOWNS. A rect handed over by a staged city is the CPU's ground again.
	var town_c := Vector3(240.0, 0.0, -180.0)
	var town_key := gs._chunk_key_at(town_c.x, town_c.z)
	_ok(not gs._town_chunk(town_key), "no towns yet: the chunk is the world's")
	gs.set_towns([Rect2(town_c.x - 60.0, town_c.z - 60.0, 120.0, 120.0)])
	_ok(gs._town_chunk(town_key), "the chunk under a staged city is the town's")
	_ok(not gs._town_chunk(gs._chunk_key_at(town_c.x + 1200.0, town_c.z)),
		"a chunk a kilometre away is not")
	gs.set_towns([])
	_ok(not gs._town_chunk(town_key), "...and striking the city gives it back")

	## THE PAVING. A street is laid over ground the grass has already grown on,
	## 0.6 m thick with its top AT the ground — so a tuft left standing under
	## one comes up through the cobbles. Pave it and nothing is placed there.
	var pave_key := Vector2i(2, -3)
	var pc := gs._chunk_center(pave_key)
	var before: Dictionary = gs._place_chunk(pave_key)
	var half := 3.3
	gs.pave([{"a": Vector2(pc.x - 40.0, pc.z), "b": Vector2(pc.x + 40.0, pc.z), "w": half * 2.0}])
	var after: Dictionary = gs._place_chunk(pave_key)
	var p_before := 0
	var p_after := 0
	var on_street := 0
	for k in range(GrassSystem.KINDS.size()):
		p_before += ((before["xf"] as Array)[k] as Array).size()
		for t: Transform3D in ((after["xf"] as Array)[k] as Array):
			p_after += 1
			if absf(t.origin.z - pc.z) <= half:
				on_street += 1
	_ok(on_street == 0, "not one tuft stands in the street (%d checked)" % p_after)
	_ok(p_after < p_before, "the street took its strip out of the chunk (%d -> %d tufts)"
		% [p_before, p_after])
	## ...and ONLY its strip. A 6.6 m street straight through a 12.8 m chunk is
	## 52% of its area, so a little over half the tufts is exactly right and
	## anything near 100% would mean the whole chunk went bald.
	var lost := 1.0 - float(p_after) / maxf(float(p_before), 1.0)
	_ok(lost > 0.40 and lost < 0.62,
		"...and only its strip: %.0f%% gone against %.0f%% of the chunk covered"
			% [lost * 100.0, half * 2.0 / GrassSystem.CHUNK_M * 100.0])
	_ok(not gs._paved.has(Vector2i(40, 40)),
		"a chunk the street never reaches holds no street record")
	_note("paving a 6.6 m street through a 12.8 m chunk cost it %d of %d tufts"
		% [p_before - p_after, p_before])

	print("\n-- 17. GRASS PAINT: where it grows is a map, and the map is painted --")
	## The map (scripts/GrassPaint.gd) on a grid over the valley: 60 x 60 cells
	## of 4 m, cell (0,0) centred at (-118, -118) -- Overworld's convention.
	var paint := GrassPaint.new()
	paint._dir = "user://grass_test/"
	DirAccess.make_dir_recursive_absolute("user://grass_test")
	root.add_child(paint)
	paint.setup(null, Vector2(-118.0, -118.0), Vector2i(60, 60), 4.0)
	_ok(gs._paint == paint, "a map that comes up after the grass finds it through the group")
	var pk := Vector2i(1, 1)                   ## 12.8 .. 25.6 m, well inside the valley
	var pc2 := gs._chunk_center(pk)
	var n_auto := 0
	for k in range(GrassSystem.KINDS.size()):
		n_auto += ((gs._place_chunk(pk)["xf"] as Array)[k] as Array).size()
	_ok(n_auto > 200, "unpainted: the world's rule grows a meadow (%d tufts)" % n_auto)
	## BARE
	paint.paint_disc(pc2, 14.0, GrassPaint.BARE)
	var n_bare := 0
	for k in range(GrassSystem.KINDS.size()):
		n_bare += ((gs._place_chunk(pk)["xf"] as Array)[k] as Array).size()
	_ok(n_bare == 0, "painted bare: not one tuft (%d)" % n_bare)
	## AUTO again -- the same meadow, tuft for tuft (deterministic placement)
	paint.paint_disc(pc2, 14.0, GrassPaint.AUTO)
	var n_back := 0
	for k in range(GrassSystem.KINDS.size()):
		n_back += ((gs._place_chunk(pk)["xf"] as Array)[k] as Array).size()
	_ok(n_back == n_auto, "erased back to auto: the same meadow returns (%d)" % n_back)
	## HALF density
	paint.paint_disc(pc2, 14.0, GrassPaint.value_of_density(0.5))
	var n_half := 0
	for k in range(GrassSystem.KINDS.size()):
		n_half += ((gs._place_chunk(pk)["xf"] as Array)[k] as Array).size()
	var half_r := float(n_half) / float(maxi(n_auto, 1))
	_ok(half_r > 0.30 and half_r < 0.70, "painted at 50%%: about half the tufts (%.0f%%)" % (half_r * 100.0))
	## a dab that covers only PART of the chunk takes only its part
	paint.paint_disc(pc2, 14.0, GrassPaint.AUTO)
	paint.paint_disc(Vector3(pc2.x - GrassSystem.CHUNK_M * 0.5, 0.0, pc2.z), 4.0, GrassPaint.BARE)
	var placed17: Dictionary = gs._place_chunk(pk)
	var in_dab := 0
	var n_part := 0
	for k in range(GrassSystem.KINDS.size()):
		for t: Transform3D in ((placed17["xf"] as Array)[k] as Array):
			n_part += 1
			if Vector2(t.origin.x - (pc2.x - GrassSystem.CHUNK_M * 0.5), t.origin.z - pc2.z).length() < 1.0:
				in_dab += 1
	_ok(in_dab == 0 and n_part > n_auto / 2,
		"a 4 m dab on the chunk's edge bares the dab and nothing else (%d -> %d, %d in the dab)"
			% [n_auto, n_part, in_dab])
	paint.paint_disc(Vector3(pc2.x - GrassSystem.CHUNK_M * 0.5, 0.0, pc2.z), 4.0, GrassPaint.AUTO)

	## THE STROKE REGROWS THE STANDING RING, off-thread, through the streamer.
	gs.warm(Vector3.ZERO)
	_ok(gs._chunks.has(pk), "the chunk is standing in the ring")
	var mmi_before := 0
	for kind: String in gs._chunks[pk]:
		var mm17 := (gs._chunks[pk][kind] as MultiMeshInstance3D).multimesh
		mmi_before += 0 if mm17 == null else mm17.instance_count
	paint.paint_disc(pc2, 14.0, GrassPaint.BARE)
	_ok(gs.regrow_pending() == 0, "a stroke alone marks nothing (the texture flush is the tick)")
	paint.flush_texture()
	_ok(gs.regrow_pending() > 0, "the flush's `changed` marks %d standing chunks to regrow"
		% gs.regrow_pending())
	## pump the streamer by hand: one batch out, wait, one batch in
	var pumps := 0
	while (gs.regrow_pending() > 0 or gs._job_gid >= 0 or not gs._apply_q.is_empty()) and pumps < 400:
		gs._stream_step()
		gs._drain_applies()
		if gs._job_gid >= 0:
			OS.delay_msec(5)
		pumps += 1
	_ok(pumps < 400, "the regrow drains (%d pumps)" % pumps)
	_ok(not gs._chunks.has(pk), "...and the bared chunk is GONE from the ring, not hidden")
	_ok(gs._empty.has(pk), "the streamer remembers it found nothing there")
	gs._focus = Vector3.ZERO
	gs._restream()
	_ok(not gs._queue.has(pk), "...so it does not ask for it again on the next tick")
	## paint it back: the empty memo lifts and the meadow returns
	paint.paint_disc(pc2, 14.0, GrassPaint.AUTO)
	paint.flush_texture()
	_ok(not gs._empty.has(pk), "a stroke over an empty chunk lifts the memo")
	gs._restream()
	_ok(gs._queue.has(pk) or gs._pending.has(pk), "...and the streamer asks for it again")
	pumps = 0
	while (not gs._queue.is_empty() or gs.regrow_pending() > 0 or gs._job_gid >= 0
			or not gs._apply_q.is_empty()) and pumps < 400:
		gs._stream_step()
		gs._drain_applies()
		if gs._job_gid >= 0:
			OS.delay_msec(5)
		pumps += 1
	var mmi_after := 0
	if gs._chunks.has(pk):
		for kind: String in gs._chunks[pk]:
			var mm18 := (gs._chunks[pk][kind] as MultiMeshInstance3D).multimesh
			mmi_after += 0 if mm18 == null else mm18.instance_count
	_ok(mmi_after == mmi_before, "the meadow came back exactly (%d -> %d instances)" % [mmi_before, mmi_after])
	_note("paint: %d tufts auto, 0 bare, %d at half; regrow drained in %d pumps"
		% [n_auto, n_half, pumps])
	_ok(gs._job_gid < 0 and gs._queue.is_empty() and gs._pending.is_empty()
		and gs._regrow.is_empty() and gs._apply_q.is_empty(),
		"the streamer is at rest afterwards (job %d, queue %d, pending %d, regrow %d, applies %d)"
			% [gs._job_gid, gs._queue.size(), gs._pending.size(), gs._regrow.size(), gs._apply_q.size()])
	gs.set_paint(null)
	paint.queue_free()

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
