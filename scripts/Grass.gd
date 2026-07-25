extends Node3D
class_name GrassSystem
## GRASS — Valheim's architecture with TotK's priorities.
##   Architecture (Valheim): chunked MultiMesh instancing of real low-poly
##   tuft GEOMETRY (no textures, no billboards — 3 faceted blades per tuft),
##   placed by sampling the voxel surface, faded out in a ring so the world
##   reads lush while the count stays honest.
##   Priorities (TotK/BotW): MOTION sells grass — gust waves sweep the whole
##   meadow, every blade sways on its own phase, and blades BEND AWAY from
##   the player as you wade through. Near cave mouths the grass withers
##   grey-brown, because that's the fiction.
## Chunks rebuild when digging (or a new mouth) changes the surface under
## them — same dirty-area pattern as the rock chunks.

const CHUNK_CELLS := 16          ## grass chunk = one rock chunk footprint (12.8 m)
const TUFTS_PER_CHUNK := 650     ## placement attempts per chunk — 2.5× the old
                                 ## meadow. The keep-rates below spend that:
                                 ## short grass lands ~2× denser, the tall
                                 ## hiding patches ~2.5×, so wading through a
                                 ## meadow reads as wading.
const SHORT_KEEP := 0.80         ## short grass takes 4/5 of its old share of a
                                 ## much bigger draw = 2× on the ground
const FADE_END := 38.0           ## blades shrink to nothing by here (shader)
const CULL_END := 55.0           ## whole chunks stop rendering here
const WITHER_R := 11.0           ## grass sickens this close to a cave mouth
const TALL_T := 0.34             ## tall-noise above this = a HIDING patch
const CUT_CELL := 0.6            ## resolution of the mown-grass record (m)
const LITTER_CAP := 1800         ## resting cut blades / fallen leaves held at
                                 ## once, oldest recycled — one draw call each
const GUST_EVERY_MIN := 16.0     ## seconds between wind gusts through the litter
const GUST_EVERY_MAX := 38.0
const GUST_RANGE := 34.0         ## only lift leaves someone can see lift

var field: CaveField
var base_seed := 0
var _mat: ShaderMaterial
var _tuft: ArrayMesh
var _tall_tuft: ArrayMesh        ## chest-high blades — the hiding grass
var _stub_tuft: ArrayMesh        ## CUT grass: flat-topped dried stumps where tall fell
var _cut_cells := {}             ## Vector2i cut-grid cell -> true (persists digs + shifts)
var _chunks := {}                ## Vector2i -> {std: MMI, tall: MMI, stub: MMI}
var _litter := {}                ## kind -> {mmi, mm, next, count} — what CAME OFF
                                 ## the world and settled: cut blades, fallen
                                 ## leaves. A ring buffer, so a long afternoon
                                 ## of mowing never becomes a frame cost.
var _density := FastNoiseLite.new()
var _tall := FastNoiseLite.new() ## slow noise carves out the tall meadows —
                                 ## the SAME noise answers "am I hidden here?"
var _wind_t := 0.0
var _gust_t := 0.0               ## the leaf-litter gust clock (Tsushima drift)
var _gust_next := 22.0
var _ncx := 0
var _ncz := 0
var _bkeys: Array[Vector2i] = [] ## threaded first build
var _bresults := []


func _ready() -> void:
	add_to_group("grass_system")  ## the sword asks for cuts through here


func setup(f: CaveField, seed_v: int) -> void:
	field = f
	base_seed = seed_v
	_density.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_density.frequency = 0.035
	_density.seed = seed_v * 7 + 3
	_tall.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_tall.frequency = 0.016
	_tall.seed = seed_v * 13 + 11
	_build_material()
	_tuft = _build_tuft_mesh(0.42, 0.045, 3)
	_tall_tuft = _build_tuft_mesh(1.15, 0.06, 5)
	_stub_tuft = _build_stub_mesh(0.17, 0.05, 5)
	_ncx = int(ceil(float(CaveField.CELLS_X) / CHUNK_CELLS))
	_ncz = int(ceil(float(CaveField.CELLS_Z) / CHUNK_CELLS))
	_reseed_all()
	print("GrassSystem: %d chunks seeded" % _chunks.size())


func _reseed_all() -> void:
	## Placement is pure field reads — thread it like the rock. Used by the
	## first build AND by a load (which has to re-place every chunk so the
	## stubble matches the restored record of what's been mown).
	_bkeys.clear()
	for cx in range(_ncx):
		for cz in range(_ncz):
			_bkeys.append(Vector2i(cx, cz))
	_bresults.resize(_bkeys.size())
	var gid := WorkerThreadPool.add_group_task(_build_task, _bkeys.size(), -1, true, "Grass")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	for n in range(_bkeys.size()):
		if _bresults[n] is Dictionary:
			_apply_chunk(_bkeys[n], _bresults[n] as Dictionary)
	_bresults.clear()


func _build_task(n: int) -> void:
	_bresults[n] = _place_chunk(_bkeys[n])


func _process(delta: float) -> void:
	## The two uniforms that make it ALIVE: time (gust waves) and you.
	_wind_t += delta
	_mat.set_shader_parameter("wind_t", _wind_t)
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p != null:
		_mat.set_shader_parameter("player_pos", p.global_position)
		## The stealth question, answered by the same noise that grew the
		## patches: standing in tall grass on the surface = concealed.
		p.set("grass_hidden", p.global_position.y > -1.1
			and is_tall_at(p.global_position.x, p.global_position.z))
	## Now and then the wind gets under the leaf fall and takes a FEW of them
	## somewhere else. The carpet stays; a handful of it moves.
	_gust_t += delta
	if _gust_t >= _gust_next:
		_gust_t = 0.0
		_gust_next = randf_range(GUST_EVERY_MIN, GUST_EVERY_MAX)
		_gust_leaves(p)


func _gust_leaves(p: Node3D) -> void:
	if p == null or not _litter.has("leaf"):
		return
	var pool: Dictionary = _litter["leaf"]
	if int(pool["count"]) <= 0:
		return
	var on: Array = pool["on"]
	var xf: Array = pool["xf"]
	var cols: Array = pool["col"]
	var ga := randf() * TAU
	var gust := Vector3(cos(ga), 0.0, sin(ga))   ## one bearing — one gust
	var want := randi_range(2, 6)
	var taken := 0
	var start := randi() % LITTER_CAP
	for s in range(LITTER_CAP):
		if taken >= want:
			break
		var i: int = (start + s) % LITTER_CAP
		if not on[i]:
			continue
		var t: Transform3D = xf[i]
		if p.global_position.distance_to(t.origin) > GUST_RANGE:
			continue  ## only lift what someone is there to see lift
		var fl := FallingLitter.make("leaf", t.origin + Vector3.UP * 0.06,
			Vector3(randf_range(-0.3, 0.3), randf_range(0.5, 1.5), randf_range(-0.3, 0.3)),
			cols[i] as Color, t.basis.get_scale().x)
		add_child(fl)
		fl.carry(gust + Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3)),
			randf_range(2.0, 12.0), randf_range(0.8, 2.2))
		remove_litter("leaf", i)
		taken += 1


func is_tall_at(wx: float, wz: float) -> bool:
	## The stealth answer: a patch only hides you while it's STANDING —
	## mown stubble conceals no one.
	return _tall_noise_at(wx, wz) and not _cut_cells.has(_cut_cell(wx, wz))


func _tall_noise_at(wx: float, wz: float) -> bool:
	## The raw noise: where tall grass GROWS (cut or not).
	return _tall.get_noise_2d(wx, wz) > TALL_T


func _cut_cell(wx: float, wz: float) -> Vector2i:
	return Vector2i(int(floor(wx / CUT_CELL)), int(floor(wz / CUT_CELL)))


func _chunk_key_at(wx: float, wz: float) -> Vector2i:
	var i := int((wx - field.origin.x) / CaveField.VOX)
	var k := int((wz - field.origin.z) / CaveField.VOX)
	return Vector2i(clampi(i / CHUNK_CELLS, 0, _ncx - 1), clampi(k / CHUNK_CELLS, 0, _ncz - 1))


func cut_at(center: Vector3, radius: float) -> bool:
	## THE SWORD MOWS (Player._do_melee_hit): fell every standing TALL tuft
	## inside the swing circle. Short grass is spared (nothing worth cutting),
	## and because chunk seeds are deterministic, the felled tufts turn into
	## flat dried STUBBLE in the exact spots they stood — while the patch
	## stops hiding anyone (is_tall_at). Cuts persist through digs and
	## sleep-shifts. TODO(design): a regrowth pass (days? seasons?).
	if field == null or center.y < -1.6 or center.y > 7.0:
		return false  ## no meadow down the throat or over the deeps
	var any_new := false
	var cut_count := 0
	var touched := {}
	var c := Vector2(center.x, center.z)
	var c0 := _cut_cell(center.x, center.z)
	var r_cells := int(ceil(radius / CUT_CELL)) + 1
	for dx in range(-r_cells, r_cells + 1):
		for dz in range(-r_cells, r_cells + 1):
			var cell := Vector2i(c0.x + dx, c0.y + dz)
			var cw := Vector2((float(cell.x) + 0.5) * CUT_CELL, (float(cell.y) + 0.5) * CUT_CELL)
			if cw.distance_to(c) > radius or _cut_cells.has(cell):
				continue
			if not _tall_noise_at(cw.x, cw.y):
				continue  ## only the hiding grass falls
			_cut_cells[cell] = true
			any_new = true
			cut_count += 1
			touched[_chunk_key_at(cw.x, cw.y)] = true
	if any_new:
		for k: Vector2i in touched:
			_apply_chunk(k, _place_chunk(k))
		_burst_clippings(center, cut_count)
	return any_new


func rebuild_area(lo: Vector3i, hi: Vector3i) -> void:
	## The ground changed (dig / new mouth) — reseed the grass chunks over it.
	## Only worth it when the change reached near-surface rows.
	if hi.y < CaveField.SY - 10:
		return
	for cx in range(maxi(int(lo.x / float(CHUNK_CELLS)), 0), mini(int(hi.x / float(CHUNK_CELLS)), _ncx - 1) + 1):
		for cz in range(maxi(int(lo.z / float(CHUNK_CELLS)), 0), mini(int(hi.z / float(CHUNK_CELLS)), _ncz - 1) + 1):
			var key := Vector2i(cx, cz)
			_apply_chunk(key, _place_chunk(key))


func _place_chunk(key: Vector2i) -> Dictionary:
	## Sample the voxel surface for standable grass spots. Deterministic per
	## chunk (seeded rng) so rebuilds don't reshuffle the whole meadow.
	var rng := RandomNumberGenerator.new()
	rng.seed = base_seed + key.x * 73856093 + key.y * 19349663
	var transforms: Array[Transform3D] = []
	var colors := PackedColorArray()
	var tall_transforms: Array[Transform3D] = []
	var tall_colors := PackedColorArray()
	var stub_transforms: Array[Transform3D] = []
	var stub_colors := PackedColorArray()
	var cell0x := key.x * CHUNK_CELLS
	var cell0z := key.y * CHUNK_CELLS
	for _i in range(TUFTS_PER_CHUNK):
		var i := cell0x + rng.randi_range(0, CHUNK_CELLS - 1)
		var k := cell0z + rng.randi_range(0, CHUNK_CELLS - 1)
		if i < 2 or k < 2 or i > CaveField.SX - 3 or k > CaveField.SZ - 3:
			continue  ## the rim wall grows no meadow
		var wx := field.origin.x + (float(i) + rng.randf()) * CaveField.VOX
		var wz := field.origin.z + (float(k) + rng.randf()) * CaveField.VOX
		var in_tall := _tall_noise_at(wx, wz)
		## SHORT GRASS EVERYWHERE (Valheim-lush baseline — paths come later);
		## the noise only breathes a little variation into it. Hiding patches
		## plant dense — that's what makes them cover.
		if in_tall:
			if rng.randf() > 0.85:
				continue
		elif rng.randf() > (0.88 + _density.get_noise_2d(wx, wz) * 0.10) * SHORT_KEEP:
			continue
		var p := field.floor_point(Vector3i(i, CaveField.SY - 2, k))
		if p == Vector3.INF or p.y < -1.1 or p.y > 6.5:
			continue  ## no grass down the throat or floating over caves
		## Skip cliff faces: the neighbour column shouldn't drop far.
		var p2 := field.floor_point(Vector3i(mini(i + 1, CaveField.SX - 3), CaveField.SY - 2, k))
		if p2 == Vector3.INF or absf(p2.y - p.y) > 0.6:
			continue
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(
			Vector3(rng.randf_range(0.8, 1.3), rng.randf_range(0.7, 1.4), rng.randf_range(0.8, 1.3))),
			Vector3(wx, p.y - 0.02, wz))
		## Withered-realm palette, sickening toward grey-brown near mouths.
		var col := Color(0.19, 0.30, 0.14).lerp(Color(0.30, 0.34, 0.15), rng.randf())
		var md := 999.0
		for m in field.mouths:
			md = minf(md, Vector2(wx - m.x, wz - m.z).length())
		col = col.lerp(Color(0.33, 0.27, 0.16), clampf(1.0 - md / WITHER_R, 0.0, 1.0) * 0.85)
		if in_tall:
			if _cut_cells.has(_cut_cell(wx, wz)):
				## The tuft that stood here was MOWN: same seed, same spot — a
				## flat-topped stump in dried straw where the hiding blades fell.
				stub_transforms.append(t)
				stub_colors.append((col.lerp(Color(0.52, 0.45, 0.22), 0.6) * 0.92).srgb_to_linear())
			else:
				tall_transforms.append(t)
				tall_colors.append((col * 0.82).srgb_to_linear())  ## duller, shadier
		else:
			transforms.append(t)
			colors.append(col.srgb_to_linear())  ## hand the shader linear (slab lesson)
	return {"transforms": transforms, "colors": colors,
		"tall_transforms": tall_transforms, "tall_colors": tall_colors,
		"stub_transforms": stub_transforms, "stub_colors": stub_colors}


func _apply_chunk(key: Vector2i, placed: Dictionary) -> void:
	var transforms: Array[Transform3D] = placed.transforms
	var tall_transforms: Array[Transform3D] = placed.tall_transforms
	var stub_transforms: Array[Transform3D] = placed.stub_transforms
	if transforms.is_empty() and tall_transforms.is_empty() and stub_transforms.is_empty():
		if _chunks.has(key):
			for which in _chunks[key]:
				(_chunks[key][which] as Node).queue_free()
			_chunks.erase(key)
		return
	if not _chunks.has(key):
		var pair := {}
		for which in ["std", "tall", "stub"]:
			var mmi := MultiMeshInstance3D.new()
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = CULL_END
			mmi.material_override = _mat
			add_child(mmi)
			pair[which] = mmi
		_chunks[key] = pair
	var ox := field.origin.x + key.x * CHUNK_CELLS * CaveField.VOX
	var oz := field.origin.z + key.y * CHUNK_CELLS * CaveField.VOX
	var aabb := AABB(Vector3(ox, -3.0, oz),
		Vector3(CHUNK_CELLS * CaveField.VOX, 12.0, CHUNK_CELLS * CaveField.VOX))
	_fill_mm(_chunks[key].std as MultiMeshInstance3D, _tuft, transforms, placed.colors, aabb)
	_fill_mm(_chunks[key].tall as MultiMeshInstance3D, _tall_tuft, tall_transforms, placed.tall_colors, aabb)
	_fill_mm(_chunks[key].stub as MultiMeshInstance3D, _stub_tuft, stub_transforms,
		placed.stub_colors, aabb)


func _fill_mm(mmi: MultiMeshInstance3D, mesh: ArrayMesh, transforms: Array[Transform3D],
		colors: PackedColorArray, aabb: AABB) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for n in range(transforms.size()):
		mm.set_instance_transform(n, transforms[n])
		mm.set_instance_color(n, colors[n])
	## Instances live in world space around an identity node — hand the
	## renderer an honest AABB or distant chunks cull wrong.
	mm.custom_aabb = aabb
	mmi.multimesh = mm


func _build_tuft_mesh(height: float, width: float, blades: int) -> ArrayMesh:
	## One tuft = single-triangle blades fanned around the base, tips leaning
	## outward. Pure faceted geometry — our art language, no textures. The
	## tall variant (chest-high, 5 blades) is the HIDING grass.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in range(blades):
		var ang := TAU * float(b) / float(blades) + 0.35
		var out := Vector3(cos(ang), 0, sin(ang))
		var side := Vector3(-sin(ang), 0, cos(ang))
		var base := out * (0.05 + 0.03 * float(blades > 3))
		var h := height * (0.85 + 0.3 * float(b % 2))
		var tip := base + out * (0.16 + height * 0.12) + Vector3.UP * h
		var v0 := base - side * width
		var v1 := base + side * width
		var n := (v1 - v0).cross(tip - v0).normalized()
		st.set_normal(n)
		st.add_vertex(v0)
		st.set_normal(n)
		st.add_vertex(tip)
		st.set_normal(n)
		st.add_vertex(v1)
	return st.commit()


func _build_stub_mesh(height: float, width: float, blades: int) -> ArrayMesh:
	## CUT grass — the "texture" of a mown patch in our no-texture language:
	## the same fan of blades as the tall tuft, but TRUNCATED — flat-topped
	## little stumps, sheared where the sword went through. Quads, not spikes:
	## the flat cut is what reads "mown" at a glance.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in range(blades):
		var ang := TAU * float(b) / float(blades) + 0.35
		var out := Vector3(cos(ang), 0, sin(ang))
		var side := Vector3(-sin(ang), 0, cos(ang))
		var base := out * 0.08
		var h := height * (0.8 + 0.4 * float(b % 2))
		var top := base + out * 0.05 + Vector3.UP * h
		var v0 := base - side * width
		var v1 := base + side * width
		var v2 := top + side * width * 0.7
		var v3 := top - side * width * 0.7
		var n := (v1 - v0).cross(v3 - v0).normalized()
		st.set_normal(n)
		st.add_vertex(v0)
		st.set_normal(n)
		st.add_vertex(v3)
		st.set_normal(n)
		st.add_vertex(v1)
		st.set_normal(n)
		st.add_vertex(v1)
		st.set_normal(n)
		st.add_vertex(v3)
		st.set_normal(n)
		st.add_vertex(v2)
	return st.commit()


func _burst_clippings(center: Vector3, cells: int) -> void:
	## THE CUT BLADES THEMSELVES. The swing throws them, and then physics of a
	## sort takes over that has nothing to do with rocks: a severed blade of
	## grass PLANES down like a leaf, swinging on the air, and comes to rest
	## on the dirt — where it STAYS. Mowing leaves a floor of cuttings behind
	## you, not a puff of particles (FallingLitter → add_litter).
	var n := clampi(cells, 6, 18)
	for _i in range(n):
		var a := randf() * TAU
		var rr := sqrt(randf()) * 0.75
		var at := center + Vector3(cos(a) * rr, randf_range(-0.15, 0.45), sin(a) * rr)
		var v := Vector3(cos(a), 0.0, sin(a)) * randf_range(0.5, 1.7) \
			+ Vector3.UP * randf_range(0.5, 1.9)
		var col := Color(0.24, 0.36, 0.15).lerp(Color(0.45, 0.44, 0.21), randf())
		add_child(FallingLitter.make("blade", at, v, col, randf_range(0.85, 1.4)))


## ------------------------- Litter: what lies there ------------------------
## Everything that has come OFF the world and settled — mown blades, leaves
## shaken out of a falling canopy. One MultiMesh per kind, written as a ring
## buffer: the oldest blade quietly gives up its slot when the meadow has been
## worked hard enough, so this never becomes a budget you have to think about.


func _litter_pool(kind: String) -> Dictionary:
	if _litter.has(kind):
		return _litter[kind]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = FallingLitter.mesh_for(kind)
	mm.instance_count = LITTER_CAP
	var gone := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for i in range(LITTER_CAP):
		mm.set_instance_transform(i, gone)
		mm.set_instance_color(i, Color.WHITE)
	## Instances live in world space around an identity node — a world-sized
	## AABB keeps distant litter from culling out from under itself.
	mm.custom_aabb = AABB(Vector3(-130, -50, -130), Vector3(260, 80, 260))
	var mmi := MultiMeshInstance3D.new()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mmi.material_override = mat
	mmi.multimesh = mm
	add_child(mmi)
	## A CPU-side mirror of the buffer: the save reads from THIS, never back
	## out of the renderer. Plain Arrays on purpose — Godot's Packed*Arrays are
	## value types, so `dict["col"][i] = c` would quietly write to a copy.
	var xf: Array = []
	xf.resize(LITTER_CAP)
	var cs: Array = []
	cs.resize(LITTER_CAP)
	var on: Array = []
	on.resize(LITTER_CAP)
	var pool := {"mmi": mmi, "mm": mm, "next": 0, "count": 0, "xf": xf, "col": cs, "on": on}
	_litter[kind] = pool
	return pool


func add_litter(kind: String, xf: Transform3D, col: Color) -> void:
	var pool := _litter_pool(kind)
	var mm: MultiMesh = pool["mm"]
	var i: int = pool["next"]
	mm.set_instance_transform(i, xf)
	mm.set_instance_color(i, col.srgb_to_linear())
	(pool["xf"] as Array)[i] = xf
	(pool["col"] as Array)[i] = col
	(pool["on"] as Array)[i] = true
	pool["next"] = (i + 1) % LITTER_CAP
	pool["count"] = mini(int(pool["count"]) + 1, LITTER_CAP)


func remove_litter(kind: String, i: int) -> void:
	## One piece leaves the floor again (the wind took it).
	if not _litter.has(kind):
		return
	var pool: Dictionary = _litter[kind]
	(pool["mm"] as MultiMesh).set_instance_transform(i,
		Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
	(pool["on"] as Array)[i] = false
	pool["count"] = maxi(int(pool["count"]) - 1, 0)


func clear_litter() -> void:
	var gone := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for kind: String in _litter:
		var pool: Dictionary = _litter[kind]
		var mm: MultiMesh = pool["mm"]
		var on: Array = pool["on"]
		for i in range(LITTER_CAP):
			mm.set_instance_transform(i, gone)
			on[i] = false
		pool["next"] = 0
		pool["count"] = 0


## ------------------------------ Save / load -------------------------------


func save_state() -> Dictionary:
	var cells: Array[Vector2i] = []
	for c: Vector2i in _cut_cells:
		cells.append(c)
	var lit := {}
	for kind: String in _litter:
		var pool: Dictionary = _litter[kind]
		var src: Array = pool["xf"]
		var scol: Array = pool["col"]
		var on: Array = pool["on"]
		var xf: Array[Transform3D] = []
		var cs := PackedColorArray()
		for i in range(LITTER_CAP):
			if not on[i]:
				continue  ## an empty slot
			xf.append(src[i] as Transform3D)
			cs.append(scol[i] as Color)
		lit[kind] = {"xf": xf, "col": cs}
	return {"cut": cells, "litter": lit}


func apply_state(d: Dictionary) -> void:
	_cut_cells.clear()
	for c in d.get("cut", []):
		_cut_cells[c as Vector2i] = true
	clear_litter()
	var lit: Dictionary = d.get("litter", {})
	for kind in lit:
		var pool := _litter_pool(String(kind))
		var mm: MultiMesh = pool["mm"]
		var dst: Array = pool["xf"]
		var dcol: Array = pool["col"]
		var on: Array = pool["on"]
		var xf: Array = (lit[kind] as Dictionary).get("xf", [])
		var cs: PackedColorArray = (lit[kind] as Dictionary).get("col", PackedColorArray())
		var n := mini(xf.size(), LITTER_CAP)
		for i in range(n):
			var t := xf[i] as Transform3D
			var c: Color = cs[i] if i < cs.size() else Color.WHITE
			mm.set_instance_transform(i, t)
			mm.set_instance_color(i, c.srgb_to_linear())
			dst[i] = t
			dcol[i] = c
			on[i] = true
		pool["next"] = n % LITTER_CAP
		pool["count"] = n
	## Every chunk reseeds so the stubble matches the restored cut record.
	_reseed_all()


func _build_material() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 player_pos = vec3(0.0);
uniform float wind_t = 0.0;
varying float v_h;
void vertex() {
	v_h = clamp(VERTEX.y / 0.5, 0.0, 1.0);
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float vis = clamp((38.0 - distance(wpos, cam)) / 6.0, 0.0, 1.0);
	VERTEX *= vis; // blades sink into the ground at range, no popping
	if (vis > 0.0) {
		float bend = v_h * v_h;
		// Gust WAVES travelling across the meadow (the TotK move):
		float ph = wpos.x * 0.09 + wpos.z * 0.06 - wind_t * 1.35;
		float gust = max(sin(ph) + sin(ph * 2.33 + 1.7), 0.0) * 0.5;
		float amp = 0.045 + gust * 0.11;
		vec2 sway = vec2(sin(wind_t * 1.9 + wpos.x * 0.7),
			cos(wind_t * 1.6 + wpos.z * 0.7)) * amp;
		// And YOU: blades shoulder aside as you wade through.
		vec2 away = wpos.xz - player_pos.xz;
		float d = length(away);
		if (d < 1.7 && d > 0.001) {
			sway += (away / d) * (1.0 - d / 1.7) * 0.5;
		}
		VERTEX.x += sway.x * bend;
		VERTEX.z += sway.y * bend;
	}
}
void fragment() {
	ALBEDO = mix(COLOR.rgb * 0.45, COLOR.rgb, v_h); // shaded base, lit tips
	ROUGHNESS = 1.0;
}
"""
	_mat = ShaderMaterial.new()
	_mat.shader = sh
