extends RefCounted
class_name CaveField
## The voxel density field under one cave region (Caves 2.0, docs/CAVES_PLAN.md).
## Rock is POSITIVE, air is NEGATIVE, the surface lives at the zero crossing.
## Solid ground carved by three noise carvers (worm tunnels that swell/pinch,
## cheese caverns, thin fitable cracks) + an explicit mouth ramp — then edited
## live by the pickaxe (carve_sphere), which is how mining digs real holes.
## Pure math + one PackedFloat32Array; no scene nodes live here.

const VOX := 0.8                 ## meters per voxel (the "higher poly" knob)
const CELLS_X := 260             ## 208 m — the ENTIRE map: one continuous
const CELLS_Y := 54              ##   underground, caves run wherever the noise
const CELLS_Z := 260             ##   takes them. y = -36 .. +7.2
const SX := CELLS_X + 1          ## sample grid (one more than cells)
const SY := CELLS_Y + 1
const SZ := CELLS_Z + 1
const DEPTH := 36.0              ## world y of the bottom sample row

## The entrance: ONLY THE TOP breaks the surface — a low craggy rock CAP
## arching over a descending throat. The ground opens into a shallow ramp
## trench that dives under the cap's stone brow; everything else is below.
const MOUND_R := 5.2             ## cap footprint radius
const MOUND_H := 2.5             ## cap crown height — a brow, not a hill
const MOUND_FWD := 5.0           ## cap sits OVER the throat's already-deep end
const MOUTH_OPEN_R := 8.0        ## the chain may only cut the surface this
                                 ## close to the mouth (kills back-side holes)

## Deep rows below this world-y are PLACEHOLDER rock for the first instants of
## a run; the full underground carves itself on worker threads immediately at
## load-in (and again on every sleep — the shifting caves).
const DEEP_Y := -8.0
const J_DEEP := int((DEPTH + DEEP_Y) / VOX)  ## sample rows < this are "deep"

## THE SHIFTING CAVES (sleep): everything underground reseeds and re-carves —
## EXCEPT inside the permanence bubble around each mouth (the "permanent
## caves": entrance throats and their first chambers never move, and content
## respects a no-spawn barrier around them).
const PERM_R := 24.0             ## permanence bubble radius around each mouth
const J_RESET_TOP := 43          ## reset touches rows below wy ≈ -1.6 only
                                 ## (surface skin, mounds, grass never shift)

var origin := Vector3.ZERO       ## min corner of the sample grid (x, -DEPTH, z)
var data := PackedFloat32Array() ## SX*SY*SZ densities — THE cave, edits persist
var mouths: Array[Vector3] = []  ## every entrance (worldgen picks 2; the M-menu
var dirs: Array[Vector3] = []    ##   button can tear open more at runtime)
var _chains: Array = []          ## per mouth: smoothed capsule chain (Array[Vector3])
var _chain_min: Array[Vector3] = []  ## per-chain AABB (early-out for the sampler)
var _chain_max: Array[Vector3] = []

## THE CATHEDRAL UNDERGROUND (authored shapes — the lab's winner, graduated):
## big terrain-floored caverns joined by slope-capped tunnels, evaluated as
## SDFs in _gen_rows with AABB early-outs. Re-authored on every reseed.
var _cath_ell: Array = []        ## [center, radii] caverns
var _cath_lo: Array = []         ## per-cavern AABB
var _cath_hi: Array = []
var _cath_caps: Array = []       ## [a, b, r] tunnels
var _ccap_lo: Array = []
var _ccap_hi: Array = []
var _cath_floors: Array = []     ## [Vector2 xz, r, y] sediment discs
var _cath_cols: Array = []       ## [Vector2 xz, r, y0, y1] rock columns

var _worm_a := FastNoiseLite.new()
var _worm_b := FastNoiseLite.new()
var _worm_r := FastNoiseLite.new()   ## modulates tunnel radius: swell and pinch
var _cheese := FastNoiseLite.new()
var _crack_a := FastNoiseLite.new()
var _crack_b := FastNoiseLite.new()
var _zone := FastNoiseLite.new()     ## the DISTRICT map: one slow smooth noise
                                     ## deals the underground into deliberate
                                     ## zones — warrens / galleries / halls
var band := FastNoiseLite.new()      ## strata banding (the mesher reads this)


func setup(p_mouths: Array[Vector3], p_dirs: Array[Vector3], seed_v: int) -> void:
	## ONE field under the whole map, centered on the world origin.
	origin = Vector3(-CELLS_X * VOX * 0.5, -DEPTH, -CELLS_Z * VOX * 0.5)

	for pair: Array in [[_worm_a, 0.030], [_worm_b, 0.031], [_worm_r, 0.013], [_cheese, 0.021],
			[_crack_a, 0.052], [_crack_b, 0.054], [_zone, 0.012], [band, 0.09]]:
		var n := pair[0] as FastNoiseLite
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX
		n.fractal_octaves = 2
		n.frequency = float(pair[1])
		n.seed = seed_v
		seed_v = seed_v * 31 + 17  ## every noise its own seed, all from one root
	_zone.fractal_octaves = 1  ## district borders should be broad, not ragged
	## Domain warp bends the tunnels so nothing runs straight.
	for n: FastNoiseLite in [_worm_a, _worm_b, _cheese]:
		n.domain_warp_enabled = true
		n.domain_warp_amplitude = 14.0
		n.domain_warp_frequency = 0.024

	for m in range(p_mouths.size()):
		_add_mouth_geometry(p_mouths[m], p_dirs[m])
	_author_cathedrals(seed_v)


func _author_cathedrals(seed_v: int) -> void:
	## Scatter the caverns (grand naves mid-depth, chapels shallow, crypts in
	## the deeps), lay flat sediment floors, raise columns in the big ones,
	## then join EVERYTHING into one connected system: a minimum-spanning
	## tree of slope-capped tunnels plus a couple of loops, and a connector
	## from every mouth-throat's end to its nearest cavern.
	_cath_ell.clear()
	_cath_lo.clear()
	_cath_hi.clear()
	_cath_caps.clear()
	_ccap_lo.clear()
	_ccap_hi.clear()
	_cath_floors.clear()
	_cath_cols.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 131 + 7
	var kinds: Array = [
		[4, 13.0, 19.0, 6.0, 8.5, -20.0, -12.0],   ## grand naves
		[6, 7.0, 11.0, 3.8, 5.5, -15.0, -7.0],     ## chapels
		[3, 10.0, 15.0, 5.0, 7.5, -29.0, -23.0],   ## deep crypts
	]
	for kind: Array in kinds:
		var placed := 0
		var tries := 0
		while placed < int(kind[0]) and tries < 90:
			tries += 1
			var rx := rng.randf_range(float(kind[1]), float(kind[2]))
			var ry := rng.randf_range(float(kind[3]), float(kind[4]))
			var rz := rx * rng.randf_range(0.75, 1.1)
			var c := Vector3(rng.randf_range(-74.0 + rx, 74.0 - rx),
				rng.randf_range(float(kind[5]), float(kind[6])),
				rng.randf_range(-74.0 + rz, 74.0 - rz))
			c.y = minf(c.y, -3.6 - ry)  ## the 2.2 m surface roof stays sacred
			var ok := true
			for n in range(_cath_ell.size()):
				var o := _cath_ell[n][0] as Vector3
				var orx := (_cath_ell[n][1] as Vector3).x
				if Vector2(c.x - o.x, c.z - o.z).length() < (rx + orx) * 0.8 + 4.0:
					ok = false
					break
			if not ok:
				continue
			placed += 1
			_cath_ell.append([c, Vector3(rx, ry, rz)])
			_cath_lo.append(c - Vector3(rx, ry, rz) - Vector3.ONE * 1.5)
			_cath_hi.append(c + Vector3(rx, ry, rz) + Vector3.ONE * 1.5)
			_cath_floors.append([Vector2(c.x, c.z), rx * 0.85, c.y - ry * 0.5])
			if rx >= 11.0:
				for _col in range(rng.randi_range(3, 5)):
					var a := rng.randf() * TAU
					var d := rng.randf_range(rx * 0.3, rx * 0.72)
					_cath_cols.append([Vector2(c.x + cos(a) * d, c.z + sin(a) * d),
						rng.randf_range(1.0, 1.8), c.y - ry - 1.0, c.y + ry + 1.0])
	## The network: Prim's MST over the caverns, then two loop links.
	if _cath_ell.size() >= 2:
		var linked: Array[int] = [0]
		var todo: Array[int] = []
		for n in range(1, _cath_ell.size()):
			todo.append(n)
		while not todo.is_empty():
			var best_a := -1
			var best_b := -1
			var best_d := 1e9
			for a in linked:
				for b in todo:
					var dd := (_cath_ell[a][0] as Vector3).distance_to(_cath_ell[b][0] as Vector3)
					if dd < best_d:
						best_d = dd
						best_a = a
						best_b = b
			_link_caverns(_cath_ell[best_a][0] as Vector3, _cath_ell[best_b][0] as Vector3, rng)
			linked.append(best_b)
			todo.erase(best_b)
		for _extra in range(2):
			var a2 := linked[rng.randi_range(0, linked.size() - 1)]
			var b2 := linked[rng.randi_range(0, linked.size() - 1)]
			if a2 != b2:
				_link_caverns(_cath_ell[a2][0] as Vector3, _cath_ell[b2][0] as Vector3, rng)
	## Every front door leads somewhere: throat end -> nearest cavern.
	for ci in range(_chains.size()):
		_connect_chain_to_cathedral(ci)


func _link_caverns(a: Vector3, b: Vector3, rng: RandomNumberGenerator) -> void:
	var mid := (a + b) * 0.5 + Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6))
	var cap_dy := Vector2(mid.x - a.x, mid.z - a.z).length() * 0.36
	mid.y = clampf(mid.y, minf(a.y, b.y) - cap_dy, maxf(a.y, b.y) + cap_dy)
	mid.y = minf(mid.y, -4.6)
	var r := rng.randf_range(2.3, 2.9)
	var p1 := a.lerp(mid, 0.75)
	var p2 := mid.lerp(b, 0.25)
	_add_cath_cap(a, p1, r)
	_add_cath_cap(p1, p2, r)
	_add_cath_cap(p2, b, r)


func _add_cath_cap(a: Vector3, b: Vector3, r: float) -> void:
	_cath_caps.append([a, b, r])
	var m := r + 1.5
	_ccap_lo.append(Vector3(minf(a.x, b.x) - m, minf(a.y, b.y) - m, minf(a.z, b.z) - m))
	_ccap_hi.append(Vector3(maxf(a.x, b.x) + m, maxf(a.y, b.y) + m, maxf(a.z, b.z) + m))


func _connect_chain_to_cathedral(ci: int) -> void:
	## The throat dives to ~-11.5 and the cathedral system takes it from
	## there: one tunnel from the chain's end to the nearest cavern heart.
	if _cath_ell.is_empty() or ci >= _chains.size():
		return
	var chain: Array[Vector3] = _chains[ci]
	var tail: Vector3 = chain[chain.size() - 1]
	var best := Vector3.INF
	var best_d := 1e9
	for e: Array in _cath_ell:
		var d := tail.distance_to(e[0] as Vector3)
		if d < best_d:
			best_d = d
			best = e[0] as Vector3
	if best == Vector3.INF:
		return
	var mid := (tail + best) * 0.5
	mid.y = minf(minf(tail.y, best.y) + 1.0, -5.0)
	_add_cath_cap(tail, mid, 2.5)
	_add_cath_cap(mid, best, 2.5)


func _add_mouth_geometry(p_mouth: Vector3, p_dir: Vector3) -> void:
	## The throat: an OPEN sunken ramp — starts at grade, descends under the
	## sky for its first meters (a grass-walled cut in the ground), and is
	## already ~2 m deep when it passes beneath the cap's stone brow. The cap
	## only ever roofs rock that's genuinely below grade, so its shell stays
	## thick and its back slope stays sealed.
	mouths.append(p_mouth)
	dirs.append(p_dir)
	var ctrl: Array[Vector3] = [
		p_mouth - p_dir * 7.0 + Vector3(0, 1.45, 0),
		p_mouth - p_dir * 1.0 + Vector3(0, -0.2, 0),
		p_mouth + p_dir * 5.0 + Vector3(0, -3.4, 0),
		p_mouth + p_dir * 13.0 + Vector3(0, -7.6, 0),
		p_mouth + p_dir * 21.0 + Vector3(0, -11.8, 0),
	]
	## Round the elbows (two Chaikin corner-cut passes) so the tunnel floor
	## bows smoothly — a hard kink between capsules makes a 45°+ face a
	## walker can slip on but never climb back out of.
	for _pass in range(2):
		var sm: Array[Vector3] = [ctrl[0]]
		for s in range(ctrl.size() - 1):
			sm.append(ctrl[s].lerp(ctrl[s + 1], 0.25))
			sm.append(ctrl[s].lerp(ctrl[s + 1], 0.75))
		sm.append(ctrl[ctrl.size() - 1])
		ctrl = sm
	_chains.append(ctrl)
	## Chain bounding box (+ max radius) — lets the sampler skip this mouth's
	## SDF for the ~99% of the map nowhere near it.
	var lo := ctrl[0]
	var hi := ctrl[0]
	for p in ctrl:
		lo = lo.min(p)
		hi = hi.max(p)
	_chain_min.append(lo - Vector3(3.0, 3.0, 3.0))
	_chain_max.append(hi + Vector3(3.0, 3.0, 3.0))


func add_mouth(p_mouth: Vector3, p_dir: Vector3) -> Array[Vector3i]:
	## RUNTIME: tear a new entrance into the existing field (M-menu button).
	## Recomputes the affected sample box (mound + chain footprint) and hands
	## back its range so the region can remesh those chunks. This box is
	## resampled fresh (player digs inside it are blasted away — the earth
	## just tore open; the quake covers the paperwork).
	_add_mouth_geometry(p_mouth, p_dir)
	var ci := _chains.size() - 1
	var caps_before := _cath_caps.size()
	_connect_chain_to_cathedral(ci)
	var lo_w: Vector3 = _chain_min[ci]
	var hi_w: Vector3 = _chain_max[ci]
	## The new connector tunnel is part of the tear — recompute its box too.
	for n in range(caps_before, _cath_caps.size()):
		lo_w = lo_w.min(_ccap_lo[n] as Vector3)
		hi_w = hi_w.max(_ccap_hi[n] as Vector3)
	## Include the cap mound footprint + a margin.
	var mc := p_mouth + p_dir * MOUND_FWD
	lo_w = lo_w.min(mc - Vector3(MOUND_R + 2.0, 0.0, MOUND_R + 2.0))
	hi_w = hi_w.max(mc + Vector3(MOUND_R + 2.0, MOUND_H + 2.0, MOUND_R + 2.0))
	var lo := ((lo_w - origin) / VOX).floor()
	var hi := ((hi_w - origin) / VOX).ceil()
	var i0 := clampi(int(lo.x), 1, SX - 2)
	var k0 := clampi(int(lo.z), 1, SZ - 2)
	var i1 := clampi(int(hi.x), 1, SX - 2)
	var k1 := clampi(int(hi.z), 1, SZ - 2)
	for i in range(i0, i1 + 1):
		_gen_rows(i, 1, SY, false, k0, k1 + 1)
	return [Vector3i(i0, 1, k0), Vector3i(i1, SY - 1, k1)]


func idx(i: int, j: int, k: int) -> int:
	return (i * SY + j) * SZ + k


func sample_pos(i: int, j: int, k: int) -> Vector3:
	return origin + Vector3(i, j, k) * VOX


var shallow_only := false        ## deep rows still placeholder rock (phase 1)


func generate(p_shallow := false) -> void:
	## Sampling densities × several noises is the heavy step — spread the
	## X-planes across the worker pool (each thread writes disjoint indices).
	## Shallow mode carves only the surface/entrance rows (wy >= DEEP_Y) and
	## leaves everything deeper as solid placeholder rock — the vast underneath
	## is generated later, off-screen, once the player actually enters.
	shallow_only = p_shallow
	data.resize(SX * SY * SZ)
	if shallow_only:
		data.fill(1.0)  ## solid placeholder — real values overwrite the top rows
	var gid := WorkerThreadPool.add_group_task(_gen_plane, SX, -1, true, "CaveField")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	## Seal hairline walls + dissolve floating specks before anything meshes.
	var pid := start_polish()
	WorkerThreadPool.wait_for_group_task_completion(pid)


func start_deep_generation() -> int:
	## Phase 2, NON-blocking: kick threaded carving of the deep rows and hand
	## back the group id (the region polls it). minf() in the writer preserves
	## any holes the player already dug into the placeholder rock.
	shallow_only = false  ## the deep becomes real — later passes cover all rows
	return WorkerThreadPool.add_group_task(_gen_deep_plane, SX, -1, true, "CaveFieldDeep")


func reseed(seed_v: int) -> void:
	## New bones for the underground — the cathedral system re-authors itself
	## whole (new caverns, new tunnels; the permanence bubbles still shield
	## the mouths). Strata banding keeps its seed — rock TYPE doesn't shift.
	for n: FastNoiseLite in [_worm_a, _worm_b, _worm_r, _cheese, _crack_a, _crack_b, _zone]:
		n.seed = seed_v
		seed_v = seed_v * 31 + 17
	_author_cathedrals(seed_v)


func start_polish() -> int:
	## Second pass over the carved field, threaded (center-writes only, so
	## planes can run in parallel):
	##   1) WALL THICKENING — air beside a 1-sample-thin rock wall fills in,
	##      so no face is ever thinner than ~1.6 voxels: the see-through
	##      pinch-cracks between rocks close for good.
	##   2) DESPECKLE — a rock sample with no rock neighbours is a floating
	##      shard touching the world at nothing but tips; it dissolves.
	return WorkerThreadPool.add_group_task(_polish_plane, SX, -1, true, "CaveFieldPolish")


func _polish_plane(i: int) -> void:
	if i < 2 or i > SX - 3:
		return
	var j0 := J_DEEP if shallow_only else 2
	for j in range(j0, J_RESET_TOP):
		for k in range(2, SZ - 2):
			var id := (i * SY + j) * SZ + k
			var d := data[id]
			if d > 0.0:
				if data[((i - 1) * SY + j) * SZ + k] <= 0.0 and data[((i + 1) * SY + j) * SZ + k] <= 0.0 \
						and data[(i * SY + j - 1) * SZ + k] <= 0.0 and data[(i * SY + j + 1) * SZ + k] <= 0.0 \
						and data[(i * SY + j) * SZ + k - 1] <= 0.0 and data[(i * SY + j) * SZ + k + 1] <= 0.0:
					data[id] = -0.2  ## floating speck — gone
			else:
				## Thin-wall check along each axis: rock right beside me whose
				## far side is air again = a 1-sample wall — I become rock,
				## and the wall is two samples thick from now on.
				if (data[((i - 1) * SY + j) * SZ + k] > 0.0 and data[((i - 2) * SY + j) * SZ + k] <= 0.0) \
						or (data[((i + 1) * SY + j) * SZ + k] > 0.0 and data[((i + 2) * SY + j) * SZ + k] <= 0.0) \
						or (data[(i * SY + j - 1) * SZ + k] > 0.0 and data[(i * SY + j - 2) * SZ + k] <= 0.0) \
						or (data[(i * SY + j + 1) * SZ + k] > 0.0 and data[(i * SY + j + 2) * SZ + k] <= 0.0) \
						or (data[(i * SY + j) * SZ + k - 1] > 0.0 and data[(i * SY + j) * SZ + k - 2] <= 0.0) \
						or (data[(i * SY + j) * SZ + k + 1] > 0.0 and data[(i * SY + j) * SZ + k + 2] <= 0.0):
					data[id] = 0.3


func start_reset_generation() -> int:
	## The shift itself, NON-blocking: recompute every underground sample
	## OUTSIDE the mouth permanence bubbles. Player digs outside the bubbles
	## are swallowed by the shift — that's the price of a moving labyrinth.
	return WorkerThreadPool.add_group_task(_reset_plane, SX, -1, true, "CaveFieldReset")


func _reset_plane(i: int) -> void:
	if i == 0 or i == SX - 1:
		return  ## rim columns never change
	var wx := origin.x + i * VOX
	for k in range(1, SZ - 1):
		var wz := origin.z + k * VOX
		var protected := false
		for m in mouths:
			if Vector2(wx - m.x, wz - m.z).length() < PERM_R:
				protected = true
				break
		if protected:
			continue  ## the permanent caves hold their shape
		_gen_rows(i, 1, J_RESET_TOP, false, k, k + 1)


func _gen_deep_plane(i: int) -> void:
	_gen_rows(i, 0, J_DEEP, true)


func _gen_plane(i: int) -> void:
	_gen_rows(i, J_DEEP if shallow_only else 0, SY, false)


func _gen_rows(i: int, row0: int, row1: int, preserve: bool, kk0 := 0, kk1 := SZ) -> void:
	var wx := origin.x + i * VOX
	if data.size() > 0:  ## (guard keeps the original loop nesting intact)
		for j in range(row0, row1):
			var wy := origin.y + j * VOX
			## Base: flat ground plane — rock below y=0, sky above.
			var base := -wy * 0.8
			var depth := -wy
			for k in range(kk0, kk1):
				## THE WORLD'S EDGE: no wall — the ground runs flat and uncarved
				## to the boundary and simply ENDS (step off and you fall; the
				## safety net catches the player). Caves still taper shut well
				## before here (carver edge fade), and the outer shells stay
				## unmineable so nobody digs a hole out the side of the world.
				if i <= 1 or k <= 1 or i >= SX - 2 or k >= SZ - 2:
					data[(i * SY + j) * SZ + k] = clampf(base, -4.0, 4.0)
					continue
				if j == 0:
					data[(i * SY + j) * SZ + k] = 1.0
					continue
				var wz := origin.z + k * VOX
				var d := base
				## Entrance mounds: rock heaped ABOVE the ground plane around
				## each mouth, noise-wobbled so the silhouette reads as crag.
				## (Grass skins their tops automatically via the mesher.)
				for m in range(mouths.size()):
					var mc: Vector3 = mouths[m] + dirs[m] * MOUND_FWD
					var mdx := wx - mc.x
					var mdz := wz - mc.z
					var mdist := sqrt(mdx * mdx + mdz * mdz)
					if mdist < MOUND_R + 1.5:
						var u := clampf(1.0 - mdist / MOUND_R, 0.0, 1.0)
						u = u * u * (3.0 - 2.0 * u)
						var h := MOUND_H * u + band.get_noise_3d(wx * 1.7, 0.0, wz * 1.7) * 0.5 * u
						d = maxf(d, (h - wy) * 0.8)
				## Carvers only wake below a ~2.2 m rock roof (the mouths are
				## the honest ways in — until a pickaxe makes another). And
				## they DIE OUT approaching the rim wall: every tunnel tapers,
				## pinches, and ENDS naturally in solid rock before the edge —
				## no chopped-off cave faces, nowhere to fall out of the world.
				var edge_m := float(mini(mini(i, SX - 1 - i), mini(k, SZ - 1 - k))) * VOX
				var guard := clampf((depth - 2.2) / 2.5, 0.0, 1.0) \
					* clampf((edge_m - 6.0) / 14.0, 0.0, 1.0)
				if guard > 0.0:
					## THE CATHEDRAL UNDERGROUND (the lab's winner, live):
					## authored caverns with terrain floors and columns, joined
					## by slope-capped tunnels — evaluated as SDFs with AABB
					## early-outs, wobbled by one noise so no wall is geometric.
					## `guard` still tapers everything shut near edges/surface.
					var carve := 0.0
					var in_cavern := -1
					for n in range(_cath_ell.size()):
						var lo := _cath_lo[n] as Vector3
						var hi := _cath_hi[n] as Vector3
						if wx < lo.x or wx > hi.x or wy < lo.y or wy > hi.y \
								or wz < lo.z or wz > hi.z:
							continue
						var e: Array = _cath_ell[n]
						var ec := e[0] as Vector3
						var er := e[1] as Vector3
						var v := Vector3((wx - ec.x) / er.x, (wy - ec.y) / er.y, (wz - ec.z) / er.z)
						var sd := (1.0 - v.length()) * minf(er.x, minf(er.y, er.z))
						if sd > carve:
							carve = sd
							in_cavern = n
					for n in range(_cath_caps.size()):
						var lo2 := _ccap_lo[n] as Vector3
						var hi2 := _ccap_hi[n] as Vector3
						if wx < lo2.x or wx > hi2.x or wy < lo2.y or wy > hi2.y \
								or wz < lo2.z or wz > hi2.z:
							continue
						var cp: Array = _cath_caps[n]
						carve = maxf(carve, -_capsule_d(Vector3(wx, wy, wz),
							cp[0] as Vector3, cp[1] as Vector3, float(cp[2])))
					if carve > 0.0:
						## The rock-character wobble: walls breathe, floors don't.
						carve += _worm_r.get_noise_3d(wx * 2.2, wy * 2.2, wz * 2.2) * 0.55
						d = minf(d, -carve * guard)
						## TERRAIN FLOORS: sediment fills the cavern's belly to
						## a gently mounded walking line (band noise = mounds).
						if in_cavern >= 0 and in_cavern < _cath_floors.size():
							var fl: Array = _cath_floors[in_cavern]
							var fxz := fl[0] as Vector2
							if Vector2(wx - fxz.x, wz - fxz.y).length() < float(fl[1]):
								var fy := float(fl[2]) + band.get_noise_2d(wx * 1.7, wz * 1.7) * 0.55
								if wy < fy:
									d = maxf(d, (fy - wy) * 1.5)
						## COLUMNS: rock re-planted through the void.
						for n in range(_cath_cols.size()):
							var col: Array = _cath_cols[n]
							if wy < float(col[2]) or wy > float(col[3]):
								continue
							var cxz := col[0] as Vector2
							var cdx := wx - cxz.x
							var cdz := wz - cxz.y
							if absf(cdx) > 3.0 or absf(cdz) > 3.0:
								continue
							var rr := float(col[1]) * (1.0 + 0.35 * absf(sin(wy * 0.8)))
							d = maxf(d, rr - sqrt(cdx * cdx + cdz * cdz))
				## The mouth tunnels ignore the roof guard — they ARE the
				## openings. But near the surface each may ONLY cut within
				## MOUTH_OPEN_R of its own mouth: that keeps a throat's deeper
				## half from tearing holes out of the ground behind its cap.
				## (Per-chain AABB early-out: chains only live near entrances.)
				for ci in range(_chains.size()):
					var cmin: Vector3 = _chain_min[ci]
					var cmax: Vector3 = _chain_max[ci]
					if wx < cmin.x or wx > cmax.x or wy < cmin.y or wy > cmax.y \
							or wz < cmin.z or wz > cmax.z:
						continue
					var mm: Vector3 = mouths[ci]
					if wy > -1.7 and Vector2(wx - mm.x, wz - mm.z).length() > MOUTH_OPEN_R:
						continue
					var md := _chain_sdf(Vector3(wx, wy, wz), ci)
					if md > 0.0:
						d = minf(d, -md)
				var id := (i * SY + j) * SZ + k
				## preserve = deep pass: keep anything the player already dug
				## out of the placeholder rock (their edits are always lower).
				data[id] = minf(data[id], clampf(d, -4.0, 4.0)) if preserve else clampf(d, -4.0, 4.0)


static func _capsule_d(p: Vector3, a: Vector3, b: Vector3, r: float) -> float:
	var pa := p - a
	var ba := b - a
	var h := clampf(pa.dot(ba) / maxf(ba.dot(ba), 0.0001), 0.0, 1.0)
	return (pa - ba * h).length() - r


func _chain_sdf(p: Vector3, ci: int) -> float:
	## Positive inside mouth ci's entry tunnel (smoothed capsule chain: open
	## sunken ramp, under the cap's brow, then the dive).
	var pts: Array[Vector3] = _chains[ci]
	var best := -999.0
	var segs := pts.size() - 1
	for s in range(segs):
		var a := pts[s]
		var b := pts[s + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var r := lerpf(1.75, 2.05, (float(s) + t) / float(segs))  ## a low dark throat, opening as it dives
		best = maxf(best, r - p.distance_to(a + ab * t))
	return best


## ============================ Live carving =================================


func carve_sphere(center: Vector3, r: float, j_floor := 1) -> Array[Vector3i]:
	## The pickaxe bite: scoop a sphere of rock into air. Returns the touched
	## sample range [min, max] so the region knows which chunks to remesh —
	## empty if the bite changed nothing (already open, or out of bounds).
	## j_floor > 1 = the deep rows are mid-generation and briefly off limits.
	var lo := ((center - Vector3(r, r, r)) - origin) / VOX
	var hi := ((center + Vector3(r, r, r)) - origin) / VOX
	## The rim WALL (outer 2 shells) and the bottom row are protected — the
	## world stays sealed no matter how long you swing.
	var i0 := maxi(int(floor(lo.x)), 2)
	var j0 := maxi(int(floor(lo.y)), j_floor)
	var k0 := maxi(int(floor(lo.z)), 2)
	var i1 := mini(int(ceil(hi.x)), SX - 3)
	var j1 := mini(int(ceil(hi.y)), SY - 1)
	var k1 := mini(int(ceil(hi.z)), SZ - 3)
	if i0 > i1 or j0 > j1 or k0 > k1:
		return []
	var changed := false
	for i in range(i0, i1 + 1):
		for j in range(j0, j1 + 1):
			for k in range(k0, k1 + 1):
				var id := (i * SY + j) * SZ + k
				var nd := sample_pos(i, j, k).distance_to(center) - r
				if nd < data[id]:
					data[id] = nd
					changed = true
	if not changed:
		return []
	return [Vector3i(i0, j0, k0), Vector3i(i1, j1, k1)]


func is_rock(world: Vector3) -> bool:
	var g := (world - origin) / VOX
	var i := clampi(int(round(g.x)), 0, SX - 1)
	var j := clampi(int(round(g.y)), 0, SY - 1)
	var k := clampi(int(round(g.z)), 0, SZ - 1)
	return data[idx(i, j, k)] >= 0.0


## ===================== Reachability (content placement) ====================


func reachable_air(max_nodes := 60000) -> Array[Vector3i]:
	## Coarse BFS over air samples (stride 2), seeded from inside EVERY mouth
	## ramp — everywhere a walking/climbing player could plausibly reach.
	## Drives where crystals, veins, and dwellers go, and finds the deep prize.
	var seen := {}
	var queue: Array[Vector3i] = []
	var out: Array[Vector3i] = []
	for m in range(mouths.size()):
		var start_w: Vector3 = mouths[m] + dirs[m] * 8.0 + Vector3(0, -3.0, 0)
		var sg := (start_w - origin) / VOX
		var start := Vector3i(int(sg.x) & ~1, int(sg.y) & ~1, int(sg.z) & ~1)
		## Hunt a nearby air sample if the exact start is rock.
		var found := false
		for r in range(0, 8, 2):
			if found:
				break
			for off: Vector3i in [Vector3i(0, 0, 0), Vector3i(r, 0, 0), Vector3i(-r, 0, 0),
					Vector3i(0, -r, 0), Vector3i(0, 0, r), Vector3i(0, 0, -r), Vector3i(0, r, 0)]:
				var c := start + off
				if _air_at(c):
					start = c
					found = true
					break
		if found and not seen.has(start):
			seen[start] = true
			queue.append(start)
			out.append(start)
	if queue.is_empty():
		return []
	var head := 0
	while head < queue.size() and out.size() < max_nodes:
		var cur := queue[head]
		head += 1
		for n: Vector3i in [Vector3i(2, 0, 0), Vector3i(-2, 0, 0), Vector3i(0, 2, 0),
				Vector3i(0, -2, 0), Vector3i(0, 0, 2), Vector3i(0, 0, -2)]:
			var nxt := cur + n
			## Midpoint check too: the stride-2 walk must never HOP a rock
			## wall into a sealed pocket — content only ever spawns in air
			## that genuinely connects to a mouth.
			if seen.has(nxt) or not _air_at(nxt) or not _air_at(cur + n / 2):
				continue
			seen[nxt] = true
			queue.append(nxt)
			out.append(nxt)
	return out


func _air_at(s: Vector3i) -> bool:
	if s.x < 1 or s.y < 1 or s.z < 1 or s.x >= SX - 1 or s.y >= SY - 1 or s.z >= SZ - 1:
		return false
	return data[idx(s.x, s.y, s.z)] < 0.0


func floor_point(s: Vector3i) -> Vector3:
	## Walk straight down from an air sample to the rock under it — where a
	## thing standing "here" actually stands. INF if it bottoms out.
	var j := s.y
	while j > 0 and data[idx(s.x, j - 1, s.z)] < 0.0:
		j -= 1
	if j <= 0:
		return Vector3.INF
	## Zero-crossing between rock (j-1) and air (j) for a flush floor y.
	var d_air := data[idx(s.x, j, s.z)]
	var d_rock := data[idx(s.x, j - 1, s.z)]
	var t := d_rock / maxf(d_rock - d_air, 0.0001)
	var p := sample_pos(s.x, j - 1, s.z)
	p.y += t * VOX
	return p
