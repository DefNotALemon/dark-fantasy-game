class_name TestCave
extends Node3D
## THE CAVE LAB (M menu, "New Cave 1-4") — four rival cave generators built
## as freestanding rock massifs you can walk into and compare, side by side,
## without touching the real underground. One lab stands at a time.
##
## All four share the same substrate the real caves use — a 0.8 m voxel
## density field, diggable with the pickaxe — and the same NEW smooth mesher:
## true surface nets with EDGE-INTERPOLATED vertices (no jitter) and
## gradient-smooth normals, which is the "Cave 1" upgrade applied everywhere
## so you compare SHAPES, not shading.
##
##   1 POLISHED WORMS — the current noise-carver anatomy under the new skin.
##   2 HALLS & PASSAGES — designed anatomy: big flat-floored chambers joined
##     by slope-capped smoothed passages. Guaranteed arenas, guaranteed walks.
##   3 THE RIVERBED — flow-carved: streams walk downhill, meandering, pooling
##     where they merge — floors graded gently because water insists.
##   4 THE CATHEDRAL — one huge cavern with a terrain floor and rock columns,
##     the boss-arena shape and the framerate stress test.

const VOX := 0.8
const SX := 82                   ## samples: 64.8 m across
const SY := 37                   ##          28.8 m tall
const SZ := 82
const CH := 16                   ## mesh chunk, in cells
const HULL_HALF := Vector3(28.0, 11.0, 28.0)  ## the massif's rounded bulk

var variant := 1
var lab_seed := 1337
var field := PackedFloat32Array()

var _capsules: Array = []        ## [a, b, r] carved tunnels
var _ellipsoids: Array = []      ## [center, radii] carved rooms
var _columns: Array = []         ## [Vector2 xz, r, y0, y1] rock pillars
var _floors: Array = []          ## [Vector2 xz, r, y] sediment discs (flat floors)
var _n1 := FastNoiseLite.new()
var _n2 := FastNoiseLite.new()
var _rock_mat: StandardMaterial3D
var _chunks := {}                ## Vector3i -> {body, shape, mesh}
var _bkeys: Array[Vector3i] = []
var _bres := []
var _blur_src := PackedFloat32Array()
var _blur_dst := PackedFloat32Array()
var _crystal_spots: Array[Vector3] = []


static func make(v: int, seed_v: int) -> TestCave:
	var t := TestCave.new()
	t.variant = clampi(v, 1, 4)
	t.lab_seed = seed_v
	return t


func _ready() -> void:
	add_to_group("test_cave")
	var t0 := Time.get_ticks_msec()
	_rock_mat = StandardMaterial3D.new()
	_rock_mat.vertex_color_use_as_albedo = true
	_rock_mat.roughness = 1.0
	_rock_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_n1.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_n1.frequency = 0.085
	_n1.seed = lab_seed
	_n2.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_n2.frequency = 0.05
	_n2.seed = lab_seed * 7 + 3

	_author_shapes()
	_bound_shapes()
	field.resize(SX * SY * SZ)
	var gid := WorkerThreadPool.add_group_task(_gen_plane, SX, -1, true, "TestCaveGen")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	## One smoothing breath over the whole field: pits fill, spikes melt —
	## the voxel grain stops printing through the rock. Threads READ one
	## array and WRITE a fresh other (never duplicate-then-write-in-place:
	## copy-on-write plus concurrent member writes is a race).
	_blur_src = field
	_blur_dst = PackedFloat32Array()
	_blur_dst.resize(field.size())
	gid = WorkerThreadPool.add_group_task(_blur_plane, SX, -1, true, "TestCaveBlur")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	field = _blur_dst
	_blur_src = PackedFloat32Array()
	_blur_dst = PackedFloat32Array()
	_mesh_all()
	_place_crystals()
	_dress_entrance()
	_spawn_dwellers()
	print("TestCave %d built in %d ms (%d chunks)" % [variant, Time.get_ticks_msec() - t0, _chunks.size()])


## ============================ The four shapes ==============================


func _author_shapes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = lab_seed + variant * 991
	var cx := SX * VOX * 0.5
	match variant:
		1:
			_author_worms()
		2:
			_author_halls(rng)
		3:
			_author_riverbed(rng)
		4:
			_author_cathedral(rng)
	## Every lab gets the same front door: a comfortable tunnel from the open
	## air (low-z face) to the interior's starting point.
	var start := _entry_point()
	## The mouth BELLS: wide at the daylight, tapering as the rock takes over
	## — the same welcome shape as the real throats.
	_capsules.append([Vector3(cx, 3.6, -4.0), Vector3(cx, 3.3, 6.0), 2.8])
	_capsules.append([Vector3(cx, 3.3, 6.0), Vector3(cx, 3.2, 12.0), 2.2])
	_capsules.append([Vector3(cx, 3.2, 12.0), start, 2.1])
	if variant != 4:
		_crystal_spots.append(start + Vector3(0, 0.4, 0))


func _entry_point() -> Vector3:
	match variant:
		2, 4:
			if not _ellipsoids.is_empty():
				var e: Array = _ellipsoids[0]
				return (e[0] as Vector3) + Vector3(0, -(e[1] as Vector3).y * 0.4, 0)
		3:
			if not _capsules.is_empty():
				return _capsules[0][0] as Vector3
	return Vector3(SX * VOX * 0.5, 4.2, 22.0)


func _author_worms() -> void:
	## Variant 1 is carved by NOISE inside _density_at (the current caves'
	## anatomy) — nothing to author but a couple of low cheese pockets.
	_ellipsoids.append([Vector3(20.0, 5.5, 40.0), Vector3(6.5, 3.2, 6.5)])
	_ellipsoids.append([Vector3(46.0, 6.5, 30.0), Vector3(5.5, 3.0, 5.5)])
	_crystal_spots.append(Vector3(20.0, 3.4, 40.0))
	_crystal_spots.append(Vector3(46.0, 4.4, 30.0))


func _author_halls(rng: RandomNumberGenerator) -> void:
	## Variant 2: DESIGNED anatomy. Big flat-floored chambers scattered with
	## breathing room, joined by smoothed, slope-capped passages.
	var centers: Array[Vector3] = []
	for _i in range(26):
		if centers.size() >= 5:
			break
		var c := Vector3(rng.randf_range(12.0, 52.0), rng.randf_range(4.5, 16.0),
			rng.randf_range(16.0, 52.0))
		var ok := true
		for o in centers:
			if Vector2(c.x - o.x, c.z - o.z).length() < 15.0:
				ok = false
		if ok:
			centers.append(c)
	centers.sort_custom(func(a, b): return a.z > b.z)  ## front room first
	for c in centers:
		var r := Vector3(rng.randf_range(5.5, 8.5), rng.randf_range(3.4, 4.6), rng.randf_range(5.5, 8.5))
		_ellipsoids.append([c, r])
		## The sediment disc: a genuinely FLAT floor across the chamber.
		_floors.append([Vector2(c.x, c.z), r.x * 0.9, c.y - r.y * 0.55])
		_crystal_spots.append(Vector3(c.x, c.y - r.y * 0.4, c.z))
	## Passages: each room to the next, with one cross-link — mid points
	## jittered then slope-capped so every walk is a walk, not a climb.
	for i in range(centers.size() - 1):
		_link_rooms(centers[i], centers[i + 1], rng)
	if centers.size() >= 4:
		_link_rooms(centers[0], centers[2], rng)


func _link_rooms(a: Vector3, b: Vector3, rng: RandomNumberGenerator) -> void:
	var mid := (a + b) * 0.5 + Vector3(rng.randf_range(-5, 5), 0, rng.randf_range(-5, 5))
	## Slope cap: no leg steeper than ~20 degrees.
	var max_dy_a := Vector2(mid.x - a.x, mid.z - a.z).length() * 0.36
	mid.y = clampf(mid.y, minf(a.y, b.y) - max_dy_a, maxf(a.y, b.y) + max_dy_a)
	var r := rng.randf_range(1.9, 2.5)
	## Chaikin once: four gentle legs instead of two hard ones.
	var p1 := a.lerp(mid, 0.75)
	var p2 := mid.lerp(b, 0.25)
	_capsules.append([a, p1, r])
	_capsules.append([p1, p2, r])
	_capsules.append([p2, b, r])


func _author_riverbed(rng: RandomNumberGenerator) -> void:
	## Variant 3: WATER LOGIC. Streams start high near the back, walk downhill
	## with a meander, widen as they gather, pool where they meet, and end in
	## a low gallery. Floors are gentle because water only carves gentle.
	var ends: Array[Vector3] = []
	for s in range(3):
		var p := Vector3(rng.randf_range(16.0, 48.0), rng.randf_range(13.0, 17.0),
			rng.randf_range(44.0, 54.0))
		var heading := rng.randf_range(PI * 0.75, PI * 1.25)  ## broadly toward -z
		var flow := 1.35
		var steps := 0
		while p.y > 4.2 and steps < 40:
			steps += 1
			heading += rng.randf_range(-0.55, 0.55)
			var step := Vector3(sin(heading), 0.0, cos(heading)) * 2.6
			var q := p + step
			q.y = p.y - rng.randf_range(0.22, 0.55)
			q.x = clampf(q.x, 8.0, 56.0)
			q.z = clampf(q.z, 10.0, 56.0)
			flow = minf(flow + 0.045, 2.6)
			_capsules.append([p, q, flow])
			## Every so often the water rests: a pool, wider and flat-floored.
			if steps % 7 == 0:
				_ellipsoids.append([q, Vector3(flow * 2.2, flow * 1.1, flow * 2.2)])
				_floors.append([Vector2(q.x, q.z), flow * 2.0, q.y - flow * 0.5])
			p = q
		ends.append(p)
	## All water arrives somewhere: the low gallery where the streams meet.
	var g := Vector3.ZERO
	for e in ends:
		g += e
	g /= float(ends.size())
	g.y = 3.6
	_ellipsoids.append([g, Vector3(9.0, 3.6, 9.0)])
	_floors.append([Vector2(g.x, g.z), 8.0, 2.9])
	_crystal_spots.append(g + Vector3(0, 0.6, 0))
	for e in ends:
		_capsules.append([e, g + Vector3(0, 0.8, 0), 2.2])
	_capsules.insert(0, [g + Vector3(0, 0.8, 0), g, 2.2])  ## entry aims here


func _author_cathedral(rng: RandomNumberGenerator) -> void:
	## Variant 4: ONE room, but what a room — 40 m across, a terrain floor,
	## columns holding a 15 m ceiling. The floor itself is authored by
	## _density_at (noise heightfield); here: the void, the pillars, alcoves.
	var c := Vector3(SX * VOX * 0.5, 10.5, SZ * VOX * 0.52)
	_ellipsoids.append([c, Vector3(21.0, 8.5, 17.0)])
	_floors.append([Vector2(c.x, c.z), 19.0, 3.4])  ## the nave floor line
	for _i in range(5):
		var a := rng.randf() * TAU
		var d := rng.randf_range(6.0, 14.0)
		_columns.append([Vector2(c.x + cos(a) * d, c.z + sin(a) * d),
			rng.randf_range(1.0, 1.7), 2.0, 19.5])
	## Two side alcoves off the nave.
	for sx: float in [-1.0, 1.0]:
		var ac := c + Vector3(sx * 24.0, -3.5, rng.randf_range(-6.0, 6.0))
		_ellipsoids.append([ac, Vector3(5.0, 3.0, 5.0)])
		_floors.append([Vector2(ac.x, ac.z), 4.4, ac.y - 1.6])
		_capsules.append([c + Vector3(sx * 16.0, -4.5, 0), ac, 2.2])
		_crystal_spots.append(ac + Vector3(0, 0.5, 0))
	_crystal_spots.append(c + Vector3(0, -5.5, 0))
	_crystal_spots.append(c + Vector3(6, -5.0, 6))


## ======================= The field (rock = positive) ======================


var _cap_lo: Array = []          ## per-capsule AABB (the hot-loop early-out)
var _cap_hi: Array = []
var _ell_lo: Array = []
var _ell_hi: Array = []


func _bound_shapes() -> void:
	## A quarter-million samples ask every shape "am I near you?" — answer
	## almost all of them with two vector compares instead of real SDF math.
	for cp: Array in _capsules:
		var a := cp[0] as Vector3
		var b := cp[1] as Vector3
		var r := float(cp[2]) + 1.5
		_cap_lo.append(Vector3(minf(a.x, b.x) - r, minf(a.y, b.y) - r, minf(a.z, b.z) - r))
		_cap_hi.append(Vector3(maxf(a.x, b.x) + r, maxf(a.y, b.y) + r, maxf(a.z, b.z) + r))
	for e: Array in _ellipsoids:
		var c := e[0] as Vector3
		var rr := (e[1] as Vector3) + Vector3.ONE * 1.5
		_ell_lo.append(c - rr)
		_ell_hi.append(c + rr)


func _density_at(p: Vector3) -> float:
	## SDF-flavored density in METERS: + rock, − air, 0 at the surface.
	## The massif hull first: a rounded block with a craggy noised skin.
	var c := Vector3(SX * VOX * 0.5, HULL_HALF.y + 1.0, SZ * VOX * 0.5)
	var q := (p - c).abs() - HULL_HALF
	var outside := Vector3(maxf(q.x, 0), maxf(q.y, 0), maxf(q.z, 0)).length()
	var inside := minf(maxf(q.x, maxf(q.y, q.z)), 0.0)
	var d := -(outside + inside) + 3.0            ## rock inside, air outside
	d += _n2.get_noise_3dv(p * 0.9) * 1.6         ## the crag on the skin
	if p.y < 1.6:
		d = maxf(d, 1.0)                          ## rooted into the ground
	## Variant 1's whole anatomy is noise (the current caves' worms):
	if variant == 1 and d > 0.0:
		var na := absf(_n1.get_noise_3dv(p))
		var nb := absf(_n2.get_noise_3dv(p * 1.35 + Vector3(37, 11, 91)))
		var worm := (maxf(na, nb) - 0.16) * 16.0
		d = minf(d, worm)
	## Carved shapes (all variants), AABB-gated.
	for n in range(_ellipsoids.size()):
		var lo := _ell_lo[n] as Vector3
		var hi := _ell_hi[n] as Vector3
		if p.x < lo.x or p.x > hi.x or p.y < lo.y or p.y > hi.y or p.z < lo.z or p.z > hi.z:
			continue
		var e: Array = _ellipsoids[n]
		var r := e[1] as Vector3
		var v := (p - (e[0] as Vector3)) / r
		d = minf(d, (v.length() - 1.0) * minf(r.x, minf(r.y, r.z)))
	for n in range(_capsules.size()):
		var lo2 := _cap_lo[n] as Vector3
		var hi2 := _cap_hi[n] as Vector3
		if p.x < lo2.x or p.x > hi2.x or p.y < lo2.y or p.y > hi2.y or p.z < lo2.z or p.z > hi2.z:
			continue
		var cp: Array = _capsules[n]
		d = minf(d, _capsule_sdf(p, cp[0] as Vector3, cp[1] as Vector3, float(cp[2])))
	## Sediment floors: fill everything below the disc line back to rock —
	## the flat, packed-earth walking surface every arena deserves.
	for f: Array in _floors:
		var xz := f[0] as Vector2
		if Vector2(p.x - xz.x, p.z - xz.y).length() < float(f[1]):
			var fy := float(f[2]) + _n2.get_noise_2d(p.x * 2.2, p.z * 2.2) * 0.14
			if p.y < fy:
				d = maxf(d, (fy - p.y) * 1.5)
	## Columns: rock re-planted through the void (cathedral pillars).
	for col: Array in _columns:
		var xz2 := col[0] as Vector2
		if p.y > float(col[2]) and p.y < float(col[3]):
			var rr := float(col[1]) * (1.0 + 0.35 * absf(sin(p.y * 0.8)))
			d = maxf(d, rr - Vector2(p.x - xz2.x, p.z - xz2.y).length())
	return d


func _gen_plane(i: int) -> void:
	for j in range(SY):
		for k in range(SZ):
			field[(i * SY + j) * SZ + k] = _density_at(Vector3(i * VOX, j * VOX, k * VOX))


func _blur_plane(i: int) -> void:
	for j in range(SY):
		for k in range(SZ):
			var id := (i * SY + j) * SZ + k
			if i == 0 or i >= SX - 1 or j == 0 or j >= SY - 1 or k == 0 or k >= SZ - 1:
				_blur_dst[id] = _blur_src[id]  ## edges pass through untouched
				continue
			var nsum: float = _blur_src[((i - 1) * SY + j) * SZ + k] \
				+ _blur_src[((i + 1) * SY + j) * SZ + k] \
				+ _blur_src[(i * SY + j - 1) * SZ + k] \
				+ _blur_src[(i * SY + j + 1) * SZ + k] \
				+ _blur_src[(i * SY + j) * SZ + k - 1] \
				+ _blur_src[(i * SY + j) * SZ + k + 1]
			_blur_dst[id] = _blur_src[id] * 0.55 + nsum * 0.075


func _f(i: int, j: int, k: int) -> float:
	return field[(clampi(i, 0, SX - 1) * SY + clampi(j, 0, SY - 1)) * SZ + clampi(k, 0, SZ - 1)]


static func _capsule_sdf(p: Vector3, a: Vector3, b: Vector3, r: float) -> float:
	var pa := p - a
	var ba := b - a
	var h := clampf(pa.dot(ba) / maxf(ba.dot(ba), 0.0001), 0.0, 1.0)
	return (pa - ba * h).length() - r


## ===================== The SMOOTH mesher (surface nets) ===================
## True surface nets: each boundary cell gets ONE vertex at the MEAN of its
## edge crossings (real interpolation — the fix), faces stitch neighbor cells
## across every sign-changing edge, and normals come from the field GRADIENT,
## so the rock is smooth the way rock is smooth. No jitter anywhere.


func _mesh_all() -> void:
	_bkeys.clear()
	var ncx := int(ceil(float(SX - 1) / CH))
	var ncy := int(ceil(float(SY - 1) / CH))
	var ncz := int(ceil(float(SZ - 1) / CH))
	for a in range(ncx):
		for b in range(ncy):
			for c in range(ncz):
				_bkeys.append(Vector3i(a, b, c))
	_bres.resize(_bkeys.size())
	var gid := WorkerThreadPool.add_group_task(_mesh_task, _bkeys.size(), -1, true, "TestCaveMesh")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	for n in range(_bkeys.size()):
		if _bres[n] is Dictionary:
			_apply_chunk(_bkeys[n], _bres[n] as Dictionary)
	_bres.clear()


func _mesh_task(n: int) -> void:
	_bres[n] = _build_chunk(_bkeys[n])


func _cell_vertex(i: int, j: int, k: int) -> Vector3:
	## Mean of interpolated crossings on the cell's 12 edges.
	var sum := Vector3.ZERO
	var cnt := 0
	for e: Array in [
			[Vector3i(0, 0, 0), Vector3i(1, 0, 0)], [Vector3i(0, 1, 0), Vector3i(1, 1, 0)],
			[Vector3i(0, 0, 1), Vector3i(1, 0, 1)], [Vector3i(0, 1, 1), Vector3i(1, 1, 1)],
			[Vector3i(0, 0, 0), Vector3i(0, 1, 0)], [Vector3i(1, 0, 0), Vector3i(1, 1, 0)],
			[Vector3i(0, 0, 1), Vector3i(0, 1, 1)], [Vector3i(1, 0, 1), Vector3i(1, 1, 1)],
			[Vector3i(0, 0, 0), Vector3i(0, 0, 1)], [Vector3i(1, 0, 0), Vector3i(1, 0, 1)],
			[Vector3i(0, 1, 0), Vector3i(0, 1, 1)], [Vector3i(1, 1, 0), Vector3i(1, 1, 1)]]:
		var a := e[0] as Vector3i
		var b := e[1] as Vector3i
		var da := _f(i + a.x, j + a.y, k + a.z)
		var db := _f(i + b.x, j + b.y, k + b.z)
		if (da >= 0.0) == (db >= 0.0):
			continue
		var t := da / (da - db)
		sum += (Vector3(a) + (Vector3(b) - Vector3(a)) * t + Vector3(i, j, k))
		cnt += 1
	if cnt == 0:
		return Vector3(i, j, k) + Vector3.ONE * 0.5
	return sum / float(cnt)


func _grad(p: Vector3) -> Vector3:
	var i := int(round(p.x))
	var j := int(round(p.y))
	var k := int(round(p.z))
	var g := Vector3(_f(i + 1, j, k) - _f(i - 1, j, k),
		_f(i, j + 1, k) - _f(i, j - 1, k), _f(i, j, k + 1) - _f(i, j, k - 1))
	return g.normalized() if g.length_squared() > 0.000001 else Vector3.UP


const PIX := 1.1


func _rock_color(p: Vector3) -> Color:
	## THE PIXEL TEXTURE: strata sampled at the center of a coarse texel with
	## a hashed per-texel value roll — chunky patches, never a clean gradient.
	var w := p * VOX
	var q := Vector3(floor(w.x / PIX), floor(w.y / PIX), floor(w.z / PIX))
	var qc := (q + Vector3.ONE * 0.5) * PIX
	var col := Color(0.30, 0.30, 0.34)                     ## slate
	if qc.y > 17.0:
		col = Color(0.34, 0.36, 0.34)                      ## weathered top
	elif qc.y < 5.0:
		col = Color(0.26, 0.24, 0.27)                      ## dark footing
	var n := _n2.get_noise_3dv(qc * 1.7 / VOX) * 0.05
	col = Color(col.r + n, col.g + n, col.b + n)
	var h := fposmod(sin(q.x * 12.9898 + q.y * 78.233 + q.z * 37.719) * 43758.5453, 1.0)
	return (col * (0.90 + h * 0.20)).srgb_to_linear()


func _build_chunk(key: Vector3i) -> Dictionary:
	var c0 := Vector3i(key.x * CH, key.y * CH, key.z * CH)
	var c1 := Vector3i(mini(c0.x + CH, SX - 1), mini(c0.y + CH, SY - 1), mini(c0.z + CH, SZ - 1))
	## Plain Arrays on purpose: GDScript passes Packed*Arrays BY VALUE — a
	## lambda or helper appending to one mutates a private copy. Reference
	## types (Array/Dictionary) make the closure below actually work; we
	## convert to Packed buffers once, at the end.
	var vids := {}
	var pos := []
	var nrm := []
	var col := []
	var idx := []
	var tris := []  ## collision faces

	var vert := func(i: int, j: int, k: int) -> int:
		var kk := (i * SY + j) * SZ + k
		if vids.has(kk):
			return vids[kk]
		var v := _cell_vertex(i, j, k)
		var id: int = pos.size()
		vids[kk] = id
		pos.append(v * VOX)
		return id

	for i in range(c0.x, c1.x):
		for j in range(c0.y, c1.y):
			for k in range(c0.z, c1.z):
				var d0 := _f(i, j, k)
				## X edge -> quad of the 4 cells sharing it (in y/z).
				if j > 0 and k > 0 and (d0 >= 0.0) != (_f(i + 1, j, k) >= 0.0):
					_quad(idx, tris, pos, d0 < 0.0,
						vert.call(i, j, k), vert.call(i, j - 1, k),
						vert.call(i, j - 1, k - 1), vert.call(i, j, k - 1))
				## Y edge.
				if i > 0 and k > 0 and (d0 >= 0.0) != (_f(i, j + 1, k) >= 0.0):
					_quad(idx, tris, pos, d0 >= 0.0,
						vert.call(i, j, k), vert.call(i - 1, j, k),
						vert.call(i - 1, j, k - 1), vert.call(i, j, k - 1))
				## Z edge.
				if i > 0 and j > 0 and (d0 >= 0.0) != (_f(i, j, k + 1) >= 0.0):
					_quad(idx, tris, pos, d0 < 0.0,
						vert.call(i, j, k), vert.call(i - 1, j, k),
						vert.call(i - 1, j - 1, k), vert.call(i, j - 1, k))
	if idx.is_empty():
		return {}
	## LESS REAL, on purpose: geometry stays edge-interpolated (smooth to
	## walk), but lighting goes FLAT per facet and color goes PIXELATED —
	## strata sampled per coarse texel with a hashed value roll. The gradient
	## normal only referees which way each facet faces (toward the air).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in range(0, idx.size(), 3):
		var a := pos[idx[t]] as Vector3
		var b := pos[idx[t + 1]] as Vector3
		var c := pos[idx[t + 2]] as Vector3
		var fn := (b - a).cross(c - a)
		if fn.length_squared() < 0.000001:
			fn = Vector3.UP
		fn = fn.normalized()
		var centroid := (a + b + c) / 3.0
		if fn.dot(-_grad(centroid / VOX)) < 0.0:
			fn = -fn  ## every facet lights from its AIR side
		var fc := _rock_color(centroid / VOX)
		for v: Vector3 in [a, b, c]:
			st.set_color(fc)
			st.set_normal(fn)
			st.add_vertex(v)
	return {"mesh": st.commit(), "tris": PackedVector3Array(tris)}


static func _quad(idx: Array, tris: Array, pos: Array,
		flip: bool, a: int, b: int, c: int, d: int) -> void:
	var order := [a, b, c, a, c, d] if flip else [a, d, c, a, c, b]
	for o: int in order:
		idx.append(o)
		tris.append(pos[o])


func _apply_chunk(key: Vector3i, built: Dictionary) -> void:
	if built.is_empty():
		if _chunks.has(key):
			(_chunks[key].body as Node).queue_free()
			_chunks.erase(key)
		return
	if not _chunks.has(key):
		var body := StaticBody3D.new()
		body.add_to_group("cave_rock")
		body.set_meta("cave_region", self)
		add_child(body)
		var cs := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		cs.shape = shape
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.material_override = _rock_mat
		body.add_child(mi)
		_chunks[key] = {"body": body, "shape": shape, "mesh": mi}
	var ch: Dictionary = _chunks[key]
	(ch.mesh as MeshInstance3D).mesh = built.mesh
	(ch.shape as ConcavePolygonShape3D).call_deferred("set_faces", built.tris)


## ============================ Digging works here ===========================


func carve_bite(pos_world: Vector3) -> bool:
	## The pickaxe treats the lab exactly like the real rock: a 0.95 m scoop
	## out of the field, dirty chunks re-skinned with the smooth mesher.
	var lp := to_local(pos_world)
	var r := 0.95
	var lo := Vector3i(maxi(int((lp.x - r) / VOX), 1), maxi(int((lp.y - r) / VOX), 1),
		maxi(int((lp.z - r) / VOX), 1))
	var hi := Vector3i(mini(int((lp.x + r) / VOX) + 1, SX - 2),
		mini(int((lp.y + r) / VOX) + 1, SY - 2), mini(int((lp.z + r) / VOX) + 1, SZ - 2))
	if hi.x < lo.x or hi.y < lo.y or hi.z < lo.z:
		return false
	var any := false
	for i in range(lo.x, hi.x + 1):
		for j in range(lo.y, hi.y + 1):
			for k in range(lo.z, hi.z + 1):
				var d := (Vector3(i, j, k) * VOX).distance_to(lp)
				if d > r:
					continue
				var id := (i * SY + j) * SZ + k
				var carved := (d - r) * 1.3
				if field[id] > carved:
					field[id] = carved
					any = true
	if not any:
		return false
	for a in range(maxi((lo.x - 1) / CH, 0), (hi.x + 1) / CH + 1):
		for b in range(maxi((lo.y - 1) / CH, 0), (hi.y + 1) / CH + 1):
			for c in range(maxi((lo.z - 1) / CH, 0), (hi.z + 1) / CH + 1):
				var key := Vector3i(a, b, c)
				if _bkeys.has(key):
					_apply_chunk(key, _build_chunk(key))
	return true


func _dress_entrance() -> void:
	## The lab door is dressed like a REAL mouth (CaveRegion._dress_mouth):
	## warm daylight pouring down the throat from outside, a lit crystal just
	## inside as the night marker, and a pair of craggy doorstep boulders so
	## the entrance reads from across the meadow.
	var cx := SX * VOX * 0.5
	var from := Vector3(cx, 6.4, -1.5)
	var to := Vector3(cx, 2.6, 13.0)
	var spot := SpotLight3D.new()
	add_child(spot)
	spot.position = from
	spot.look_at_from_position(to_global(from), to_global(to))
	spot.light_color = Color(1.0, 0.95, 0.78)
	spot.light_energy = 3.2
	spot.spot_range = (to - from).length() + 7.0
	spot.spot_angle = 36.0
	spot.spot_angle_attenuation = 1.6
	spot.shadow_enabled = false
	## The night marker, just inside and off to one side of the walk line.
	var mc := CrystalCluster.make(Color(0.35, 0.85, 1.0), 3, true,
		RandomNumberGenerator.new())
	add_child(mc)
	mc.position = Vector3(cx + 2.1, 3.3, 11.0)
	## Doorstep boulders flanking the mouth.
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.28, 0.28, 0.32)
	bmat.roughness = 1.0
	for sx: float in [-1.0, 1.0]:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.7, 1.5, 1.5) * (1.0 if sx < 0 else 0.8)
		b.mesh = bm
		b.material_override = bmat
		add_child(b)
		b.position = Vector3(cx + sx * 4.0, 1.3, 1.2)
		b.rotation_degrees = Vector3(sx * 9.0, sx * 34.0, sx * -7.0)


## ========================= Normal cave spawns ==============================
## The lab is a REAL cave as far as its dwellers are concerned: the same
## roster the live underground uses, placed on genuine interior floor spots
## (rock underfoot, headroom above, and a ROOF overhead — the roof test is
## what keeps spawns off the massif's outer skin and the grass outside).
## Front rooms get the fodder, the back gets the bones, and the Cathedral's
## nave keeps a champion pair. Everything frees with the lab.


func _floor_spots(rng: RandomNumberGenerator) -> Array[Vector3]:
	var found: Array[Vector3] = []
	for i in range(9, SX - 9, 2):
		for k in range(9, SZ - 9, 2):
			for j in range(2, SY - 6):
				var id0 := (i * SY + j) * SZ + k
				if field[id0] < 0.0:
					continue  ## need rock underfoot
				if field[(i * SY + j + 1) * SZ + k] >= 0.0 \
						or field[(i * SY + j + 2) * SZ + k] >= 0.0 \
						or field[(i * SY + j + 3) * SZ + k] >= 0.0:
					continue  ## and 2.4 m of air above it
				## The INTERIOR test: something must roof this spot, or it's
				## the top of the massif / the meadow outside the walls.
				var roofed := false
				for j2 in range(j + 4, SY):
					if field[(i * SY + j2) * SZ + k] >= 0.0:
						roofed = true
						break
				if roofed:
					found.append(Vector3(i * VOX, (j + 1) * VOX + 0.25, k * VOX))
				break  ## one spot per column — the lowest floor wins
	## Spread: greedy far-apart picks from a shuffled deck.
	var picked: Array[Vector3] = []
	found.shuffle()
	var rng_skip := rng.randi_range(0, 3)
	for _i in range(rng_skip):
		if not found.is_empty():
			found.push_back(found.pop_front())
	for f in found:
		var ok := true
		for q in picked:
			if Vector2(f.x - q.x, f.z - q.z).length() < 7.0:
				ok = false
				break
		if ok:
			picked.append(f)
	return picked


func _spawn_pack(cls: Variant, count: int, at: Vector3, rng: RandomNumberGenerator) -> void:
	for n in range(count):
		var e: Node3D = cls.new()
		add_child(e)
		var a := TAU * float(n) / float(maxi(count, 1)) + rng.randf() * 0.7
		e.position = at + Vector3(cos(a) * rng.randf_range(0.6, 2.0), 0.6,
			sin(a) * rng.randf_range(0.6, 2.0))
		e.rotation.y = rng.randf() * TAU


func _spawn_dwellers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = lab_seed * 31 + variant
	var spots := _floor_spots(rng)
	if spots.is_empty():
		return
	## Depth = distance from the front door: fodder greets you, bones wait.
	spots.sort_custom(func(a, b): return a.z < b.z)
	var front: Vector3 = spots[0]
	var back: Vector3 = spots[spots.size() - 1]
	var mid: Vector3 = spots[spots.size() / 2]
	_spawn_pack(Kobold, rng.randi_range(4, 6), front, rng)
	if spots.size() >= 2:
		_spawn_pack(Goblin, rng.randi_range(3, 4), mid, rng)
	if spots.size() >= 3:
		_spawn_pack(Skeleton, rng.randi_range(3, 4), back, rng)
	## The showpiece: the Cathedral keeps a champion pair mid-nave; the other
	## roomy labs post a single orc at their deepest point.
	if variant == 4 and not _ellipsoids.is_empty():
		var nave := (_ellipsoids[0][0] as Vector3) + Vector3(0, -4.0, 0)
		_spawn_pack(Orc, 1, nave + Vector3(2.0, 0, 0), rng)
		_spawn_pack(Ogre, 1, nave + Vector3(-2.0, 0, 0), rng)
	elif spots.size() >= 4:
		_spawn_pack(Orc, 1, back + Vector3(1.5, 0, 1.5), rng)


func _place_crystals() -> void:
	for s in _crystal_spots:
		var c := CrystalCluster.make(Color(0.35, 0.85, 1.0), 3, true,
			RandomNumberGenerator.new())
		add_child(c)
		c.position = s
