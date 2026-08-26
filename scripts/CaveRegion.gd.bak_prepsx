extends Node3D
class_name CaveRegion
## One Caves 2.0 region (docs/CAVES_PLAN.md): a 64×64 m, 36 m deep block of
## voxel underground. CaveField carves it (worm tunnels / cheese caverns /
## cracks / mouth ramp), CaveMesher skins it in flat-shaded rock chunks, and
## this node owns the scene side: chunk bodies (group "cave_rock"), crystals,
## ore veins, dweller packs — and carve_bite(), the pickaxe's way of digging
## real holes (all the way up to the surface if you have the patience).

const CH := CaveMesher.CHUNK
const BITE_R := 0.95             ## rock removed per pickaxe bite — honest shovelfuls

var mouths: Array[Vector3] = []  ## every entrance (World seeds 2; M-menu adds)
var dirs: Array[Vector3] = []
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
var _shifts := 0                 ## how many times sleep has moved the deep
var _grass: GrassSystem          ## the living meadow on the surface skin
var _content_root: Node3D        ## resettable content (mobs/veins/deep crystals)
								 ## — mouth dressing lives outside it, permanent


func _ready() -> void:
	add_to_group("cave_regions")  ## horses ask us where the holes are (Horse.gd)
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

	## Vastness is SPATIAL now (a slow noise inside the field): the one map-wide
	## underground swings between tight warrens and grand halls on its own.
	field = CaveField.new()
	field.setup(mouths, dirs, cave_seed)
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
	print("CaveRegion shell built in %d ms (%d chunks, %d mouths)" % [Time.get_ticks_msec() - t0, _chunks.size(), mouths.size()])
	_content_root = Node3D.new()
	add_child(_content_root)
	for m in range(mouths.size()):
		_dress_mouth(m)  ## crystal + daylight shaft — deep content waits
	## The meadow: instanced grass sampled off the freshly-built surface.
	_grass = GrassSystem.new()
	add_child(_grass)
	_grass.setup(field, cave_seed)
	## The underground loads WITH the game: kick the deep carve right now
	## (threaded, polled in _process) instead of waiting for an approach.
	_deep_state = 1
	_deep_gid = field.start_deep_generation()


func _process(_delta: float) -> void:
	match _deep_state:
		1:
			if WorkerThreadPool.is_group_task_completed(_deep_gid):
				WorkerThreadPool.wait_for_group_task_completion(_deep_gid)
				## Field carved — polish it (seal cracks, dissolve specks)...
				_deep_gid = field.start_polish()
				_deep_state = 4
		4:
			if WorkerThreadPool.is_group_task_completed(_deep_gid):
				WorkerThreadPool.wait_for_group_task_completion(_deep_gid)
				## A LOAD lands here: the noise has just redrawn the whole
				## underground from the saved seed, and now the sphere of rock
				## you actually dug gets stamped back over it — so the world
				## regenerates AROUND your tunnel and joins onto it.
				if not _restore_sphere.is_empty():
					_stamp_sphere(_restore_sphere)
					_restore_sphere = {}
				## ...now it's real — mesh the deep chunks in the background.
				_bkeys.clear()
				var seen := {}
				var cy_deep := int(ceil(float(CaveField.J_DEEP + 2) / CH))
				for cx in range(_ncx):
					for cy in range(mini(cy_deep, _ncy)):
						for cz in range(_ncz):
							var k := Vector3i(cx, cy, cz)
							seen[k] = true
							_bkeys.append(k)
				## A restored dig can sit anywhere — including the shallow rows
				## the deep pass never touches. Mesh exactly what it reached.
				if _restore_lo.x <= _restore_hi.x:
					for cx in range(_restore_lo.x, _restore_hi.x + 1):
						for cy in range(_restore_lo.y, _restore_hi.y + 1):
							for cz in range(_restore_lo.z, _restore_hi.z + 1):
								var k2 := Vector3i(cx, cy, cz)
								if not seen.has(k2):
									seen[k2] = true
									_bkeys.append(k2)
					_restore_lo = Vector3i(1, 1, 1)
					_restore_hi = Vector3i(0, 0, 0)
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
				print("CaveRegion deeps loaded (%d reachable air nodes)" % reach.size())


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
	## DEFERRED: carve_bite runs inside the physics step (pickaxe hit), and
	## rewriting a concave shape the player is STANDING ON mid-step is a
	## known engine crash (digging straight down guaranteed it). After the
	## step, it's safe.
	(c.shape as ConcavePolygonShape3D).call_deferred("set_faces", built.faces)


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
	if _grass:
		_grass.rebuild_area(lo, hi)  ## digging the surface uproots its grass
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
		var too_close := false
		for mo in mouths:
			if Vector2(p.x - mo.x, p.z - mo.z).length() < avoid_mouth:
				too_close = true
				break
		if too_close:
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
	## Counts scaled for the map-wide underground. Deep crystals are content:
	## they shift away with the caves on every sleep (mouth crystals don't).
	for p in _pick_spots(reach, 44, -30.0, -3.5, 8.0, 6.0):
		_crystal(p, _rng.randf() < 0.6, _content_root)


func _dress_mouth(m: int) -> void:
	## Every entrance gets: a crystal just inside (the night marker) — and
	## DAYLIGHT: a warm shaft pouring down the throat. A spotlight does the
	## actual lighting; two nested additive cones make the visible god rays.
	var mo: Vector3 = mouths[m]
	var md: Vector3 = dirs[m]
	var gate := (mo + md * 3.0 - field.origin) / CaveField.VOX
	var gs := Vector3i(int(gate.x), int(gate.y) + 2, int(gate.z))
	var gp := field.floor_point(gs)
	if gp != Vector3.INF:
		_crystal(gp + md.cross(Vector3.UP) * 1.6, true)
	## Daylight pours down the throat: a warm spot doing the actual lighting.
	## (The visible god-ray beam cones were tried and dropped — too cheesy.)
	var from := mo - md * 2.0 + Vector3(0, 2.8, 0)
	var to := mo + md * 6.0 + Vector3(0, -3.8, 0)
	var spot := SpotLight3D.new()
	add_child(spot)
	spot.global_position = from
	spot.look_at(to)
	spot.light_color = Color(1.0, 0.95, 0.78)
	spot.light_energy = 3.2
	spot.spot_range = (to - from).length() + 7.0
	spot.spot_angle = 36.0
	spot.spot_angle_attenuation = 1.6
	spot.shadow_enabled = false


func is_fully_loaded() -> bool:
	## True only when the deep is carved, meshed, AND content is placed.
	return _deep_state == 3


func reset_underground(force_shifts := -1) -> bool:
	## THE SHIFT (sleep): the whole underground reseeds and re-carves on the
	## worker threads — everything but the permanence bubbles around the
	## mouths. Old content (mobs, veins, deep crystals) is swept away and
	## reseeded once the new rock is real. False while a build is running.
	## `force_shifts` >= 0 rewinds the shift counter to an exact value instead
	## of advancing it — that's how a LOAD reproduces the cave you saved in.
	if _busy():
		return false
	if force_shifts >= 0:
		_shifts = force_shifts
	else:
		_shifts += 1
	field.reseed(cave_seed + _shifts * 104729)
	if is_instance_valid(_content_root):
		_content_root.queue_free()
	_content_root = Node3D.new()
	add_child(_content_root)
	_deep_state = 1
	_deep_gid = field.start_reset_generation()
	set_process(true)
	return true


func meteor_strike(spot: Vector3) -> bool:
	## The impact: a REAL crater carved into the ground, ember-glowing
	## meteoric veins fused into a half-buried BALL at its center (mine the
	## ball apart — each vein bursts into meteoric ore), rubble everywhere.
	## Parented to the region root: sleep-shifts never touch the surface, so
	## a crash site stays until it's mined clean.
	if _deep_state == 1 or _deep_state == 2:
		return false  ## field threads busy — the sky can wait a breath
	var rng_range := field.carve_sphere(spot + Vector3.UP * 1.6, 4.6)
	if rng_range.size() == 2:
		var lo: Vector3i = rng_range[0] - Vector3i(2, 2, 2)
		var hi: Vector3i = rng_range[1] + Vector3i(1, 1, 1)
		for cx in range(maxi(floori(lo.x / float(CH)), 0), mini(floori(hi.x / float(CH)), _ncx - 1) + 1):
			for cy in range(maxi(floori(lo.y / float(CH)), 0), mini(floori(hi.y / float(CH)), _ncy - 1) + 1):
				for cz in range(maxi(floori(lo.z / float(CH)), 0), mini(floori(hi.z / float(CH)), _ncz - 1) + 1):
					_remesh_chunk(Vector3i(cx, cy, cz))
		if _grass:
			_grass.rebuild_area(lo, hi)  ## the blast scorches the meadow bare
	## The ore ball, nested down in the bowl.
	var ball_c := spot + Vector3(0, -1.2, 0)
	for i in range(6):
		var a := TAU * float(i) / 6.0
		var v := OreVein.make("meteoric")
		add_child(v)
		v.global_position = ball_c + Vector3(cos(a) * 1.05, 0.5 * float(i % 2) - 0.3, sin(a) * 1.05)
		v.rotation_degrees = Vector3(randf_range(-22.0, 22.0), randf() * 360.0, randf_range(-22.0, 22.0))
	var crown := OreVein.make("meteoric")
	add_child(crown)
	crown.global_position = ball_c + Vector3(0, 0.75, 0)
	crown.rotation_degrees = Vector3(0, randf() * 360.0, 0)
	## Smoking rubble flung out of the bowl.
	for _i in range(7):
		var ra := randf() * TAU
		var rd := randf_range(2.0, 5.5)
		add_child(RockDebris.make(spot + Vector3(cos(ra) * rd, 1.2, sin(ra) * rd),
			Vector3(randf_range(-2.0, 2.0), randf_range(2.0, 4.0), randf_range(-2.0, 2.0)), randf() < 0.3))
	return true


func add_mouth(p_mouth: Vector3, p_dir: Vector3) -> bool:
	## RUNTIME (M-menu): tear a new entrance into the living field. Refused
	## only while the deep threads are actively writing (a second, tops).
	if _deep_state == 1 or _deep_state == 2:
		return false
	mouths.append(p_mouth)
	dirs.append(p_dir)
	var rng_range := field.add_mouth(p_mouth, p_dir)
	if rng_range.size() == 2:
		var lo: Vector3i = rng_range[0] - Vector3i(2, 2, 2)
		var hi: Vector3i = rng_range[1] + Vector3i(1, 1, 1)
		for cx in range(maxi(floori(lo.x / float(CH)), 0), mini(floori(hi.x / float(CH)), _ncx - 1) + 1):
			for cy in range(maxi(floori(lo.y / float(CH)), 0), mini(floori(hi.y / float(CH)), _ncy - 1) + 1):
				for cz in range(maxi(floori(lo.z / float(CH)), 0), mini(floori(hi.z / float(CH)), _ncz - 1) + 1):
					_remesh_chunk(Vector3i(cx, cy, cz))
	if rng_range.size() == 2 and _grass:
		_grass.rebuild_area(rng_range[0], rng_range[1])
	_dress_mouth(mouths.size() - 1)
	return true


func _place_veins(reach: Array[Vector3i]) -> void:
	## Silver seams through the middle depths; meteoric guards the deepest
	## reachable pocket (docs/MATERIALS.md sourcing, same rules as caves v1).
	## avoid_mouth = the NO-SPAWN BARRIER around the permanent entrance caves.
	for p in _pick_spots(reach, _rng.randi_range(12, 16), -26.0, -8.0, 12.0, CaveField.PERM_R + 2.0):
		var v := OreVein.make("silver")
		_content_root.add_child(v)
		v.global_position = p
		v.rotation_degrees = Vector3(0, _rng.randf() * 360.0, 0)
	## THE DEEP IS RICHER: an extra seam belt below -20, plus loose meteoric
	## beyond the single deepest-point prize.
	for p in _pick_spots(reach, _rng.randi_range(7, 10), -36.0, -20.0, 10.0, CaveField.PERM_R + 2.0):
		var v := OreVein.make("silver")
		_content_root.add_child(v)
		v.global_position = p
		v.rotation_degrees = Vector3(0, _rng.randf() * 360.0, 0)
	for p in _pick_spots(reach, 2, -36.0, -23.0, 26.0, CaveField.PERM_R + 2.0):
		var v := OreVein.make("meteoric")
		_content_root.add_child(v)
		v.global_position = p
		v.rotation_degrees = Vector3(0, _rng.randf() * 360.0, 0)
	var deepest := Vector3.INF
	for s in reach:
		var p := field.floor_point(s)
		if p != Vector3.INF and (deepest == Vector3.INF or p.y < deepest.y):
			deepest = p
	if deepest != Vector3.INF and deepest.y < -14.0 and _rng.randf() < 0.85:
		var v := OreVein.make("meteoric")
		_content_root.add_child(v)
		v.global_position = deepest
		v.rotation_degrees = Vector3(0, _rng.randf() * 360.0, 0)


func _spawn_pack(center: Vector3, cls: Variant, count: int) -> void:
	for _i in range(count):
		var e: Enemy = cls.new()
		_content_root.add_child(e)
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(0.5, 3.2)
		var pos := center + Vector3(cos(a) * r, 1.2, sin(a) * r)
		## Never inside the rock: if the ring spot is solid (small chamber),
		## fold back onto the pocket's center — which is guaranteed open air.
		if field.is_rock(pos) or field.is_rock(pos + Vector3.UP * 0.6):
			pos = center + Vector3(0, 1.2, 0)
		e.global_position = pos


func _spawn_dwellers(reach: Array[Vector3i]) -> void:
	## Packs at reachable pockets; deeper = meaner; the deepest big pocket is
	## the champion's court (same tables as caves v1 — see CONTEXT.md).
	## avoid_mouth = the NO-SPAWN BARRIER: nothing spawns near permanent caves.
	var pockets := _pick_spots(reach, 13, -30.0, -5.0, 17.0, CaveField.PERM_R + 2.0)
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
	## THE DEEP IS FULLER: an extra belt of mean packs below -20 — the wide
	## deep galleries deserve their garrisons.
	for c in _pick_spots(reach, 9, -36.0, -20.0, 14.0, CaveField.PERM_R + 2.0):
		var roll := _rng.randf()
		if roll < 0.35:
			_spawn_pack(c, Skeleton, _rng.randi_range(5, 8))
		elif roll < 0.7:
			_spawn_pack(c, Orc, _rng.randi_range(3, 5))
		elif roll < 0.92:
			_spawn_pack(c, Ogre, _rng.randi_range(1, 3))
		else:
			_spawn_pack(c, DarkKnight, 1)
			_spawn_pack(c, Orc, 2)


func _crystal(pos: Vector3, with_light: bool, parent: Node3D = null) -> void:
	## The glowing shard cluster (Cave.gd heritage) — now a real, MINEABLE
	## object (`CrystalCluster.gd`, group "crystals"): the pickaxe shears
	## shards off it one at a time and the light dims with every one taken.
	## parent = _content_root for shiftable deep crystals; default = permanent.
	if parent == null:
		parent = self
	var col := Color(0.35, 0.85, 1.0) if _rng.randf() < 0.7 else Color(0.72, 0.42, 1.0)
	if pos.y < -23.0:
		col = Color(1.0, 0.55, 0.25)  ## the deeps burn ember
	var c := CrystalCluster.make(col, _rng.randi_range(2, 3), with_light, _rng)
	parent.add_child(c)
	c.position = pos


## ============================== Save / load ================================
## The underground is 3.7 million samples — far too much to write to disk, and
## pointless anyway: the noise redraws it exactly from its seed. What the noise
## can NOT redraw is the part you changed with a pickaxe. So a save keeps the
## seed, the shift count (which shift of the shifting caves you were standing
## in), and a 30 m SPHERE of raw density around wherever you were. On load the
## whole cave regenerates from the seed and the sphere is stamped back over it,
## blended at the rim — the world rebuilds around your tunnel and connects to
## it, instead of your tunnel ending in a wall.

const SPHERE_R := 30.0           ## how much of your own digging travels with you
const SPHERE_BLEND := 4.0        ## rim over which saved rock fades into new rock
const SPHERE_SAVE_Y := -1.5      ## only underground saves carry a sphere

var _restore_sphere := {}        ## stamped in once the reseeded field is carved
var _restore_lo := Vector3i(1, 1, 1)   ## chunk range the stamp touched (lo > hi
var _restore_hi := Vector3i(0, 0, 0)   ##   means "nothing pending")


func grass() -> GrassSystem:
	return _grass


func _busy() -> bool:
	## Field or mesh threads are writing — nothing may reseed or stamp now.
	return _deep_state == 1 or _deep_state == 2 or _deep_state == 4


func save_state() -> Dictionary:
	var out := {"seed": cave_seed, "shifts": _shifts}
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p != null and p.global_position.y < SPHERE_SAVE_Y:
		out["sphere"] = _capture_sphere(p.global_position, SPHERE_R)
	return out


func apply_state(d: Dictionary) -> bool:
	if _busy():
		return false
	_restore_sphere = d.get("sphere", {})
	return reset_underground(int(d.get("shifts", 0)))


func _capture_sphere(center: Vector3, r: float) -> Dictionary:
	var rv := int(ceil(r / CaveField.VOX)) + 1
	var ci := int(round((center.x - field.origin.x) / CaveField.VOX))
	var cj := int(round((center.y - field.origin.y) / CaveField.VOX))
	var ck := int(round((center.z - field.origin.z) / CaveField.VOX))
	var i0 := maxi(ci - rv, 0)
	var i1 := mini(ci + rv, CaveField.SX - 1)
	var j0 := maxi(cj - rv, 0)
	var j1 := mini(cj + rv, CaveField.SY - 1)
	var k0 := maxi(ck - rv, 0)
	var k1 := mini(ck + rv, CaveField.SZ - 1)
	if i1 < i0 or j1 < j0 or k1 < k0:
		return {}
	var nx := i1 - i0 + 1
	var ny := j1 - j0 + 1
	var nz := k1 - k0 + 1
	var data := PackedFloat32Array()
	data.resize(nx * ny * nz)
	var n := 0
	for i in range(i0, i1 + 1):
		for j in range(j0, j1 + 1):
			for k in range(k0, k1 + 1):
				data[n] = field.data[field.idx(i, j, k)]
				n += 1
	return {"lo": Vector3i(i0, j0, k0), "size": Vector3i(nx, ny, nz),
		"center": center, "r": r, "data": data}


func _stamp_sphere(s: Dictionary) -> void:
	var size: Vector3i = s.get("size", Vector3i.ZERO)
	var data: PackedFloat32Array = s.get("data", PackedFloat32Array())
	if size.x <= 0 or size.y <= 0 or size.z <= 0 or data.size() != size.x * size.y * size.z:
		return
	var lo: Vector3i = s.get("lo", Vector3i.ZERO)
	var center: Vector3 = s.get("center", Vector3.ZERO)
	var r := float(s.get("r", SPHERE_R))
	var inner := maxf(r - SPHERE_BLEND, 0.5)
	for i in range(lo.x, lo.x + size.x):
		for j in range(lo.y, lo.y + size.y):
			for k in range(lo.z, lo.z + size.z):
				var dist := field.sample_pos(i, j, k).distance_to(center)
				if dist > r:
					continue
				var n := ((i - lo.x) * size.y + (j - lo.y)) * size.z + (k - lo.z)
				var w := 1.0 - clampf((dist - inner) / maxf(r - inner, 0.001), 0.0, 1.0)
				w = w * w * (3.0 - 2.0 * w)   ## smooth join at the rim
				var id := field.idx(i, j, k)
				field.data[id] = lerpf(field.data[id], data[n], w)
	## Remember which chunks this reached so only those get re-skinned.
	var hi := lo + size
	_restore_lo = Vector3i(clampi(lo.x / CH, 0, _ncx - 1), clampi(lo.y / CH, 0, _ncy - 1),
		clampi(lo.z / CH, 0, _ncz - 1))
	_restore_hi = Vector3i(clampi(hi.x / CH, 0, _ncx - 1), clampi(hi.y / CH, 0, _ncy - 1),
		clampi(hi.z / CH, 0, _ncz - 1))
	## A dig that broke the surface changes the meadow above it too.
	if _grass != null and hi.y >= CaveField.SY - 10:
		_grass.rebuild_area(lo, hi)
