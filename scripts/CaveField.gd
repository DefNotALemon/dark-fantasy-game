extends RefCounted
class_name CaveField
## The voxel density field under one cave region (Caves 2.0, docs/CAVES_PLAN.md).
## Rock is POSITIVE, air is NEGATIVE, the surface lives at the zero crossing.
## Solid ground carved by three noise carvers (worm tunnels that swell/pinch,
## cheese caverns, thin fitable cracks) + an explicit mouth ramp — then edited
## live by the pickaxe (carve_sphere), which is how mining digs real holes.
## Pure math + one PackedFloat32Array; no scene nodes live here.

const VOX := 0.8                 ## meters per voxel (the "higher poly" knob)
const CELLS_X := 80              ## 64 m
const CELLS_Y := 54              ## y = -36 .. +7.2 — headroom for the entrance mound
const CELLS_Z := 80
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

## Deep rows below this world-y are PLACEHOLDER rock at world build and only
## get carved (threaded, off-screen) once the player actually enters — the
## vast underneath loads itself while you're still in the throat.
const DEEP_Y := -8.0
const J_DEEP := int((DEPTH + DEEP_Y) / VOX)  ## sample rows < this are "deep"

var origin := Vector3.ZERO       ## min corner of the sample grid (x, -DEPTH, z)
var data := PackedFloat32Array() ## SX*SY*SZ densities — THE cave, edits persist
var mouth := Vector3.ZERO
var dir := Vector3(1, 0, 0)
var vast := 0.0                  ## 1.0 = a VAST system: fatter worms, far
                                 ## bigger caverns, wider cracks (seeded roll)

var _worm_a := FastNoiseLite.new()
var _worm_b := FastNoiseLite.new()
var _worm_r := FastNoiseLite.new()   ## modulates tunnel radius: swell and pinch
var _cheese := FastNoiseLite.new()
var _crack_a := FastNoiseLite.new()
var _crack_b := FastNoiseLite.new()
var band := FastNoiseLite.new()      ## strata banding (the mesher reads this)
var _mouth_pts: Array[Vector3] = []  ## the entry tunnel's smoothed capsule chain
var _mouth_min := Vector3.ZERO       ## chain AABB (early-out for the sampler)
var _mouth_max := Vector3.ZERO


func setup(p_mouth: Vector3, p_dir: Vector3, seed_v: int, p_vast := 0.0) -> void:
	mouth = p_mouth
	dir = p_dir
	vast = p_vast
	var center := mouth + dir * 22.0
	origin = Vector3(center.x - CELLS_X * VOX * 0.5, -DEPTH, center.z - CELLS_Z * VOX * 0.5)

	for pair: Array in [[_worm_a, 0.030], [_worm_b, 0.031], [_worm_r, 0.013], [_cheese, 0.021],
			[_crack_a, 0.052], [_crack_b, 0.054], [band, 0.09]]:
		var n := pair[0] as FastNoiseLite
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX
		n.fractal_octaves = 2
		n.frequency = float(pair[1])
		n.seed = seed_v
		seed_v = seed_v * 31 + 17  ## every noise its own seed, all from one root
	## Domain warp bends the tunnels so nothing runs straight.
	for n: FastNoiseLite in [_worm_a, _worm_b, _cheese]:
		n.domain_warp_enabled = true
		n.domain_warp_amplitude = 14.0
		n.domain_warp_frequency = 0.024

	## The mouth tunnel: starts in open air OUTSIDE the mound (so it bores a
	## walk-in archway through the mound's face at ground level), runs level
	## through it, then dives to ~-11.5 m where the noise caves take over.
	## The throat: an OPEN sunken ramp — starts at grade, descends under the
	## sky for its first meters (a grass-walled cut in the ground), and is
	## already ~2 m deep when it passes beneath the cap's stone brow. The cap
	## only ever roofs rock that's genuinely below grade, so its shell stays
	## thick and its back slope stays sealed.
	var ctrl: Array[Vector3] = [
		mouth - dir * 7.0 + Vector3(0, 1.45, 0),
		mouth - dir * 1.0 + Vector3(0, -0.2, 0),
		mouth + dir * 5.0 + Vector3(0, -3.4, 0),
		mouth + dir * 13.0 + Vector3(0, -7.6, 0),
		mouth + dir * 21.0 + Vector3(0, -11.8, 0),
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
	_mouth_pts = ctrl
	## Chain bounding box (+ max radius) — lets the sampler skip the mouth
	## SDF for the ~99% of the region nowhere near the entrance.
	_mouth_min = ctrl[0]
	_mouth_max = ctrl[0]
	for p in ctrl:
		_mouth_min = _mouth_min.min(p)
		_mouth_max = _mouth_max.max(p)
	_mouth_min -= Vector3(3.0, 3.0, 3.0)
	_mouth_max += Vector3(3.0, 3.0, 3.0)


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


func start_deep_generation() -> int:
	## Phase 2, NON-blocking: kick threaded carving of the deep rows and hand
	## back the group id (the region polls it). minf() in the writer preserves
	## any holes the player already dug into the placeholder rock.
	return WorkerThreadPool.add_group_task(_gen_deep_plane, SX, -1, true, "CaveFieldDeep")


func _gen_deep_plane(i: int) -> void:
	_gen_rows(i, 0, J_DEEP, true)


func _gen_plane(i: int) -> void:
	_gen_rows(i, J_DEEP if shallow_only else 0, SY, false)


func _gen_rows(i: int, row0: int, row1: int, preserve: bool) -> void:
	var wx := origin.x + i * VOX
	if data.size() > 0:  ## (guard keeps the original loop nesting intact)
		for j in range(row0, row1):
			var wy := origin.y + j * VOX
			## Base: flat ground plane — rock below y=0, sky above.
			var base := -wy * 0.8
			var depth := -wy
			for k in range(SZ):
				## Region rim columns are forced AIR so the mesher closes the
				## block with real side walls (the slab overhangs this seam);
				## the bottom row is forced ROCK — the world has a floor.
				if i == 0 or k == 0 or i == SX - 1 or k == SZ - 1:
					data[(i * SY + j) * SZ + k] = -1.0
					continue
				if j == 0:
					data[(i * SY + j) * SZ + k] = 1.0
					continue
				var wz := origin.z + k * VOX
				## Rim dip: the grass skin sinks a few cm as it slides in under
				## the slab's 1.2 m overhang — the two surfaces never share a
				## plane, so the border can't z-fight (that was the flicker).
				var edge_m := float(mini(mini(i, SX - 1 - i), mini(k, SZ - 1 - k))) * VOX
				var dip := 0.07 * clampf(1.0 - (edge_m - 0.8) / 3.0, 0.0, 1.0)
				var d := base - dip * 0.8
				## The entrance mound: rock heaped ABOVE the ground plane around
				## the mouth, noise-wobbled so the silhouette reads as crag, not
				## dome. (Grass skins its top automatically via the mesher.)
				var mc := mouth + dir * MOUND_FWD
				var mdx := wx - mc.x
				var mdz := wz - mc.z
				var mdist := sqrt(mdx * mdx + mdz * mdz)
				if mdist < MOUND_R + 1.5:
					var u := clampf(1.0 - mdist / MOUND_R, 0.0, 1.0)
					u = u * u * (3.0 - 2.0 * u)
					var h := MOUND_H * u + band.get_noise_3d(wx * 1.7, 0.0, wz * 1.7) * 0.5 * u
					d = maxf(d, (h - wy) * 0.8)
				## Carvers only wake below a ~2.2 m rock roof (the mouth is the
				## one honest way in — until a pickaxe makes another).
				var guard := clampf((depth - 2.2) / 2.5, 0.0, 1.0)
				if guard > 0.0:
					var carve := 0.0
					## Worm tunnels: near the crossing lines of two noises.
					## Radius rides a third noise — swelling into halls,
					## pinching to squeezes, entirely on its own.
					var wa := _worm_a.get_noise_3d(wx, wy * 1.6, wz)
					var wb := _worm_b.get_noise_3d(wx, wy * 1.6, wz)
					var wr := 1.9 + vast * 1.4 + _worm_r.get_noise_3d(wx, wy, wz) * 1.5 \
						+ clampf((depth - 6.0) / 26.0, 0.0, 1.0) * 1.2
					carve = maxf(carve, wr - sqrt(wa * wa + wb * wb) * 21.0)
					## Cheese caverns: fat low-frequency blobs, deeper = bigger.
					## Vast systems open them earlier, wider, and MUCH taller.
					var cramp := clampf((depth - (8.0 - vast * 2.0)) / 7.0, 0.0, 1.0)
					if cramp > 0.0:
						var cv := _cheese.get_noise_3d(wx, wy * 1.35, wz)
						carve = maxf(carve, (cv - (0.38 - vast * 0.10)) * (17.0 + vast * 8.0) * cramp)
					## Cracks: thin, tall seams — narrow but fitable, and they
					## love connecting systems that never planned to meet.
					var ca := _crack_a.get_noise_3d(wx, wy * 0.55, wz)
					var cb := _crack_b.get_noise_3d(wx, wy * 0.55, wz)
					carve = maxf(carve, 0.62 + vast * 0.15 - sqrt(ca * ca + cb * cb) * 24.0)
					if carve > 0.0:
						d = minf(d, -carve * guard)
				## The mouth tunnel ignores the roof guard — it IS the opening.
				## But near the surface it may ONLY cut within MOUTH_OPEN_R of
				## the mouth: that's what keeps the throat's back half from
				## tearing holes out of the ground (or the cap's back slope).
				## (AABB early-out: the chain only lives near the entrance.)
				if wx >= _mouth_min.x and wx <= _mouth_max.x \
						and wy >= _mouth_min.y and wy <= _mouth_max.y \
						and wz >= _mouth_min.z and wz <= _mouth_max.z:
					var surf_ok := wy <= -1.7 \
						or Vector2(wx - mouth.x, wz - mouth.z).length() <= MOUTH_OPEN_R
					if surf_ok:
						var md := _mouth_sdf(Vector3(wx, wy, wz))
						if md > 0.0:
							d = minf(d, -md)
				var id := (i * SY + j) * SZ + k
				## preserve = deep pass: keep anything the player already dug
				## out of the placeholder rock (their edits are always lower).
				data[id] = minf(data[id], clampf(d, -4.0, 4.0)) if preserve else clampf(d, -4.0, 4.0)


func _mouth_sdf(p: Vector3) -> float:
	## Positive inside the entry tunnel (capsule chain: archway through the
	## mound face, level walk-in, then the dive). No surface pit anymore —
	## the mound IS the entrance landmark.
	var best := -999.0
	var segs := _mouth_pts.size() - 1
	for s in range(segs):
		var a := _mouth_pts[s]
		var b := _mouth_pts[s + 1]
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
	## Rim columns and the bottom row are protected — the block stays sealed
	## no matter how long you swing.
	var i0 := maxi(int(floor(lo.x)), 1)
	var j0 := maxi(int(floor(lo.y)), j_floor)
	var k0 := maxi(int(floor(lo.z)), 1)
	var i1 := mini(int(ceil(hi.x)), SX - 2)
	var j1 := mini(int(ceil(hi.y)), SY - 1)
	var k1 := mini(int(ceil(hi.z)), SZ - 2)
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


func reachable_air(max_nodes := 20000) -> Array[Vector3i]:
	## Coarse BFS over air samples (stride 2) from just inside the mouth ramp —
	## everywhere a walking/climbing player could plausibly reach. Drives where
	## crystals, veins, and dwellers go, and finds the deep prize spot.
	var start_w := mouth + dir * 8.0 + Vector3(0, -3.0, 0)
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
	if not found:
		return []
	var seen := {start: true}
	var queue: Array[Vector3i] = [start]
	var out: Array[Vector3i] = [start]
	var head := 0
	while head < queue.size() and out.size() < max_nodes:
		var cur := queue[head]
		head += 1
		for n: Vector3i in [Vector3i(2, 0, 0), Vector3i(-2, 0, 0), Vector3i(0, 2, 0),
				Vector3i(0, -2, 0), Vector3i(0, 0, 2), Vector3i(0, 0, -2)]:
			var nxt := cur + n
			if seen.has(nxt) or not _air_at(nxt):
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
