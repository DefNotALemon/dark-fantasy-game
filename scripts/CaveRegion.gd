extends Node3D
class_name CaveRegion
## One Caves 2.0 region (docs/CAVES_PLAN.md): a 64×64 m, 36 m deep block of
## voxel underground. CaveField carves it (worm tunnels / cheese caverns /
## cracks / mouth ramp), CaveMesher skins it in flat-shaded rock chunks, and
## this node owns the scene side: chunk bodies (group "cave_rock"), crystals,
## ore veins, dweller packs — and carve_bite(), the pickaxe's way of digging
## real holes (all the way up to the surface if you have the patience).

const CH := CaveMesher.CHUNK
const BITE_R := 0.62             ## rock removed per pickaxe bite — "slowly"

var mouth := Vector3.ZERO
var dir := Vector3(1, 0, 0)
var cave_seed := 0

var field: CaveField
var _rng := RandomNumberGenerator.new()
var _rock_mat: StandardMaterial3D
var _chunks := {}                ## Vector3i -> {body, shape, mesh} (lazy, sparse)
var _ncx := 0
var _ncy := 0
var _ncz := 0
var _bkeys: Array[Vector3i] = [] ## threaded first build: chunk keys + results
var _bresults := []


## Deep loading: the vast underneath doesn't exist at world build. It carves
## itself on worker threads the moment the player approaches the mouth, and
## is walkable long before they've descended the throat.
## 0 = shallow shell only · 1 = deep field carving (threads) ·
## 2 = deep chunks meshing (threads) · 3 = fully loaded
var _deep_state := 0
var _deep_gid := -1
var _vast := 0.0


func _ready() -> void:
	_rng.seed = cave_seed
	_rock_mat = StandardMaterial3D.new()
	_rock_mat.vertex_color_use_as_albedo = true
	_rock_mat.roughness = 1.0
	## Two-sided rock: where the noise leaves a wall thinner than a voxel, the
	## surface-net has to pinch two sheets through one cell vertex — the
	## twisted sliver shows its BACKFACE, which culling turned into a
	## see-through crack in the world. Drawing both sides seals every such
	## pinhole (collision has been two-sided all along; now the eye agrees).
	_rock_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	## Every system is roomy underneath; ~40% roll properly VAST.
	_vast = 1.0 if _rng.randf() < 0.4 else 0.6
	field = CaveField.new()
	field.setup(mouth, dir, cave_seed, _vast)
	var t0 := Time.get_ticks_msec()
	field.generate(true)  ## SHALLOW: surface skin + cap + throat only
	_ncx = int(ceil(float(CaveField.CELLS_X) / CH))
	_ncy = int(ceil(float(CaveField.CELLS_Y) / CH))
	_ncz = int(ceil(float(CaveField.CELLS_Z) / CH))
	## Mesh every chunk across the worker pool (pure reads of the field, each
	## task writes only its own result slot), then wire nodes on the main
	## thread. Deep chunks are solid placeholder rock = empty = free.
	_bkeys.clear()
	for cx in range(_ncx):
		for cy in range(_ncy):
			for cz in range(_ncz):
				_bkeys.append(Vector3i(cx, cy, cz))
	_bresults.resize(_bkeys.size())
	var gid := WorkerThreadPool.add_group_task(_build_task, _bkeys.size(), -1, true, "CaveRegion")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	var failed := 0
	for n in range(_bkeys.size()):
		## A task that errored leaves null — rebuild that chunk here on the main
		## thread instead of leaving a hole in the world.
		if _bresults[n] is Dictionary:
			_apply_chunk(_bkeys[n], _bresults[n] as Dictionary)
		else:
			failed += 1
			_remesh_chunk(_bkeys[n])
	if failed > 0:
		push_warning("CaveRegion: %d chunk task(s) failed in threads; rebuilt serially" % failed)
	_bresults.clear()
	print("CaveRegion shell built in %d ms (%d chunks%s)" % [Time.get_ticks_msec() - t0, _chunks.size(), " — VAST" if _vast > 0.9 else ""])
	_place_mouth_crystal()  ## the glow that marks the entrance — deep content waits


func _process(_delta: float) -> void:
	match _deep_state:
		0:
			## Waiting at the door: approach the mouth (or drop below grade
			## inside the region) and the deeps start carving themselves.
			var p := get_tree().get_first_node_in_group("player") as Node3D
			if p == null:
				return
			var pp := p.global_position
			var inside_xz: bool = pp.x > field.origin.x + 2.0 \
				and pp.x < field.origin.x + CaveField.CELLS_X * CaveField.VOX - 2.0 \
				and pp.z > field.origin.z + 2.0 \
				and pp.z < field.origin.z + CaveField.CELLS_Z * CaveField.VOX - 2.0
			if Vector2(pp.x - mouth.x, pp.z - mouth.z).length() < 13.0 or (inside_xz and pp.y < -0.5):
				_deep_state = 1
				_deep_gid = field.start_deep_generation()
		1:
			if WorkerThreadPool.is_group_task_completed(_deep_gid):
				WorkerThreadPool.wait_for_group_task_completion(_deep_gid)
				## Field's real now — mesh the deep chunks in the background too.
				_bkeys.clear()
				var cy_deep := int(ceil(float(CaveField.J_DEEP + 2) / CH))
				for cx in range(_ncx):
					for cy in range(mini(cy_deep, _ncy)):
						for cz in range(_ncz):
							_bkeys.append(Vector3i(cx, cy, cz))
				_bresults.resize(_bkeys.size())
				_deep_gid = WorkerThreadPool.add_group_task(_build_task, _bkeys.size(), -1, true, "CaveRegionDeep")
				_deep_state = 2
		2:
			if WorkerThreadPool.is_group_task_completed(_deep_gid):
				WorkerThreadPool.wait_for_group_task_completion(_deep_gid)
				for n in range(_bkeys.size()):
					if _bresults[n] is Dictionary:
						_apply_chunk(_bkeys[n], _bresults[n] as Dictionary)
					else:
						_remesh_chunk(_bkeys[n])
				_bresults.clear()
				## The depths are real — light them, seed them, people them.
				var reach := field.reachable_air()
				_place_crystals(reach)
				_place_veins(reach)
				_spawn_dwellers(reach)
				_deep_state = 3
				set_process(false)
				print("CaveRegion deeps loaded%s" % (" — VAST" if _vast > 0.9 else ""))


func _build_task(n: int) -> void:
	_bresults[n] = CaveMesher.build_chunk(field, _bkeys[n].x, _bkeys[n].y, _bkeys[n].z)


func _remesh_chunk(key: Vector3i) -> void:
	_apply_chunk(key, CaveMesher.build_chunk(field, key.x, key.y, key.z))


func _apply_chunk(key: Vector3i, built: Dictionary) -> void:
	if built.is_empty():
		if _chunks.has(key):  ## chunk mined into pure air — retire its nodes
			(_chunks[key].body as Node).queue_free()
			_chunks.erase(key)
		return
	if not _chunks.has(key):
		var body := StaticBody3D.new()
		body.add_to_group("cave_rock")
		body.set_meta("cave_region", self)
		add_child(body)
		var col := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true  ## trimesh is one-sided by default; the
		## rare non-manifold sliver a naive surface net emits must never become
		## a hole you can fall through
		col.shape = shape
		body.add_child(col)
		var mi := MeshInstance3D.new()
		mi.material_override = _rock_mat
		body.add_child(mi)
		_chunks[key] = {"body": body, "shape": shape, "mesh": mi}
	var c: Dictionary = _chunks[key]
	(c.mesh as MeshInstance3D).mesh = built.mesh
	(c.shape as ConcavePolygonShape3D).set_faces(built.faces)


## ============================== Digging ====================================


func carve_bite(pos: Vector3) -> bool:
	## One pickaxe bite: scoop BITE_R of rock and remesh whatever it touched.
	## While the deeps are mid-generation (threads writing/reading those rows),
	## bites can't reach below the shallow shell — a second later they can.
	var j_floor := 1 if _deep_state == 0 or _deep_state == 3 else CaveField.J_DEEP + 2
	var rng_range := field.carve_sphere(pos, BITE_R, j_floor)
	if rng_range.is_empty():
		return false
	## Dirty every chunk whose cells could reference the changed samples
	## (cell verts read samples c..c+1; quads read neighbor cells — pad by 2).
	var lo: Vector3i = rng_range[0] - Vector3i(2, 2, 2)
	var hi: Vector3i = rng_range[1] + Vector3i(1, 1, 1)
	for cx in range(maxi(floori(lo.x / float(CH)), 0), mini(floori(hi.x / float(CH)), _ncx - 1) + 1):
		for cy in range(maxi(floori(lo.y / float(CH)), 0), mini(floori(hi.y / float(CH)), _ncy - 1) + 1):
			for cz in range(maxi(floori(lo.z / float(CH)), 0), mini(floori(hi.z / float(CH)), _ncz - 1) + 1):
				_remesh_chunk(Vector3i(cx, cy, cz))
	return true


## =========================== Content placement =============================


func _pick_spots(reach: Array[Vector3i], count: int, y_min: float, y_max: float,
		spacing: float, avoid_mouth := 10.0) -> Array[Vector3]:
	## Shuffle reachable air, keep floor-snapped points inside the depth band,
	## spaced apart and clear of the entry ramp.
	var picks: Array[Vector3] = []
	var order := reach.duplicate()
	## Seeded Fisher-Yates (Array.shuffle() ignores _rng — world must stay
	## identical run to run, same rule as everything else here).
	for i in range(order.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Vector3i = order[i]  ## explicit — duplicate() loses the array's element type for inference
		order[i] = order[j]
		order[j] = tmp
	for s: Vector3i in order:  ## typed — `order` is an untyped duplicate()
		if picks.size() >= count:
			break
		var wy := field.origin.y + s.y * CaveField.VOX
		if wy < y_min or wy > y_max:
			continue
		var p := field.floor_point(s)
		if p == Vector3.INF:
			continue
		if Vector2(p.x - mouth.x, p.z - mouth.z).length() < avoid_mouth:
			continue
		var ok := true
		for q in picks:
			if q.distance_to(p) < spacing:
				ok = false
				break
		if ok:
			picks.append(p)
	return picks


func _place_crystals(reach: Array[Vector3i]) -> void:
	## The caves' only native light — sparse pools of glow in the long dark.
	for p in _pick_spots(reach, 14, -30.0, -3.5, 7.0, 6.0):
		_crystal(p, _rng.randf() < 0.6)


func _place_mouth_crystal() -> void:
	## One welcoming cluster just inside the throat, so the mouth glows at
	## night and reads as an entrance, not a shadow. (Placed at shell build —
	## the deep content arrives later, when the deeps do.)
	var gate := (mouth + dir * 3.0 - field.origin) / CaveField.VOX
	var gs := Vector3i(int(gate.x), int(gate.y) + 2, int(gate.z))
	var gp := field.floor_point(gs)
	if gp != Vector3.INF:
		_crystal(gp + dir.cross(Vector3.UP) * 1.6, true)


func _place_veins(reach: Array[Vector3i]) -> void:
	## Silver seams through the middle depths; meteoric guards the deepest
	## reachable pocket (docs/MATERIALS.md sourcing, same rules as caves v1).
	for p in _pick_spots(reach, _rng.randi_range(3, 5), -26.0, -8.0, 9.0):
		var v := OreVein.make("silver")
		add_child(v)
		v.global_position = p
		v.rotation_degrees = Vector3(0, _rng.randf() * 360.0, 0)
	var deepest := Vector3.INF
	for s in reach:
		var p := field.floor_point(s)
		if p != Vector3.INF and (deepest == Vector3.INF or p.y < deepest.y):
			deepest = p
	if deepest != Vector3.INF and deepest.y < -14.0 and _rng.randf() < 0.85:
		var v := OreVein.make("meteoric")
		add_child(v)
		v.global_position = deepest
		v.rotation_degrees = Vector3(0, _rng.randf() * 360.0, 0)


func _spawn_pack(center: Vector3, cls: Variant, count: int) -> void:
	for _i in range(count):
		var e: Enemy = cls.new()
		add_child(e)
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(0.5, 3.2)
		e.global_position = center + Vector3(cos(a) * r, 1.2, sin(a) * r)


func _spawn_dwellers(reach: Array[Vector3i]) -> void:
	## Packs at reachable pockets; deeper = meaner; the deepest big pocket is
	## the champion's court (same tables as caves v1 — see CONTEXT.md).
	var pockets := _pick_spots(reach, 6, -30.0, -5.0, 13.0, 15.0)
	if pockets.is_empty():
		return
	pockets.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y > b.y)
	for i in range(pockets.size()):
		var c := pockets[i]
		if i == pockets.size() - 1 and pockets.size() >= 2:
			_spawn_pack(c, DarkKnight, 1)
			_spawn_pack(c, Orc, _rng.randi_range(2, 3))
			continue
		var roll := _rng.randf()
		if c.y > -12.0:
			if roll < 0.6:
				_spawn_pack(c, Kobold, _rng.randi_range(6, 10))
			else:
				_spawn_pack(c, Goblin, _rng.randi_range(3, 6))
		elif c.y > -21.0:
			if roll < 0.4:
				_spawn_pack(c, Goblin, _rng.randi_range(3, 6))
			elif roll < 0.8:
				_spawn_pack(c, Skeleton, _rng.randi_range(4, 7))
			else:
				_spawn_pack(c, Ogre, _rng.randi_range(1, 2))
		else:
			if roll < 0.4:
				_spawn_pack(c, Skeleton, _rng.randi_range(4, 7))
			elif roll < 0.75:
				_spawn_pack(c, Orc, _rng.randi_range(2, 4))
			else:
				_spawn_pack(c, Ogre, _rng.randi_range(1, 2))


func _crystal(pos: Vector3, with_light: bool) -> void:
	## Same glowing shard cluster the old caves used (Cave.gd heritage).
	var col := Color(0.35, 0.85, 1.0) if _rng.randf() < 0.7 else Color(0.72, 0.42, 1.0)
	if pos.y < -23.0:
		col = Color(1.0, 0.55, 0.25)  ## the deeps burn ember
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.2
	for _i in range(_rng.randi_range(2, 3)):
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var s := _rng.randf_range(0.18, 0.42)
		bm.size = Vector3(s, s * _rng.randf_range(1.6, 2.6), s)
		m.mesh = bm
		m.material_override = mat
		m.position = pos + Vector3(_rng.randf_range(-0.35, 0.35), bm.size.y * 0.35, _rng.randf_range(-0.35, 0.35))
		m.rotation_degrees = Vector3(_rng.randf_range(-18, 18), _rng.randf_range(0, 360), _rng.randf_range(-18, 18))
		add_child(m)
	if with_light:
		var l := OmniLight3D.new()
		l.light_color = col
		l.light_energy = 1.2
		l.omni_range = 9.0
		l.shadow_enabled = false
		l.position = pos + Vector3(0, 1.0, 0)
		add_child(l)
