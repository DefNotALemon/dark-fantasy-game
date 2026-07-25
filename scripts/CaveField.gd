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
	var lo_w: Vector3 = _chain_min[ci]
	var hi_w: Vector3 = _chain_max[ci]
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
	## New bones for the underground — every carver rolls new dice. The strata
	## banding keeps its seed (the rock TYPE doesn't change, just its shape).
	for n: FastNoiseLite in [_worm_a, _worm_b, _worm_r, _cheese, _crack_a, _crack_b, _zone]:
		n.seed = seed_v
		seed_v = seed_v * 31 + 17


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
					## THE ZONED UNDERGROUND — deliberate districts instead of
					## everything-everywhere chaos. One slow smooth noise deals
					## the map into three characters, parameters blending at
					## the borders:
					##   WARRENS ..... tight round tunnels, walkable, cracked
					##   GALLERIES ... WIDE corridors squashed flat top+bottom
					##   HALLS ....... where it truly opens up (the caverns)
					var zv := _zone.get_noise_2d(wx, wz)
					var gal := smoothstep(-0.2, 0.05, zv) * (1.0 - smoothstep(0.3, 0.55, zv))
					var hall := smoothstep(0.3, 0.55, zv)
					var warren := 1.0 - smoothstep(-0.2, 0.05, zv)
					var carve := 0.0
					## Worm tunnels: near the crossing lines of two noises.
					## Galleries compress the noise VERTICALLY (flat lids and
					## floors), widen the bore, and steady the radius wobble.
					var ys := 1.6 + gal * 1.1
					var wa := _worm_a.get_noise_3d(wx, wy * ys, wz)
					var wb := _worm_b.get_noise_3d(wx, wy * ys, wz)
					var deep_ramp := clampf((depth - 6.0) / 26.0, 0.0, 1.0)
					var wr := 1.9 + gal * 1.8 + hall * 0.5 \
						+ _worm_r.get_noise_3d(wx, wy, wz) * (1.5 - gal * 0.7) \
						+ deep_ramp * 3.0
					wr = maxf(wr, 2.0 + deep_ramp * 2.4)  ## never pinches shut down deep
					carve = maxf(carve, wr - sqrt(wa * wa + wb * wb) * 21.0)
					## Caverns belong to the HALLS (a whisper elsewhere).
					var cramp := clampf((depth - 6.5) / 7.0, 0.0, 1.0) * (0.12 + hall * 0.88)
					if cramp > 0.0:
						var cv := _cheese.get_noise_3d(wx, wy * 1.35, wz)
						carve = maxf(carve, (cv - (0.38 - hall * 0.12)) * (17.0 + hall * 9.0) * cramp)
					## Cracks thread the WARRENS — elsewhere they barely whisper.
					var ca := _crack_a.get_noise_3d(wx, wy * 0.55, wz)
					var cb := _crack_b.get_noise_3d(wx, wy * 0.55, wz)
					carve = maxf(carve, 0.48 + warren * 0.16 - sqrt(ca * ca + cb * cb) * 24.0)
					if carve > 0.0:
						d = minf(d, -carve * guard)
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
