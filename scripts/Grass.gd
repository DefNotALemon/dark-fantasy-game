extends Node3D
class_name GrassSystem
## GRASS v2 — a real ground layer.
##
##   Architecture (unchanged, it was right): chunked MultiMesh instancing of
##   real low-poly GEOMETRY placed by sampling the voxel surface, faded out in
##   a ring so the world reads lush while the count stays honest.
##
##   What changed (v2):
##     • BLADES ARE CURVED. A blade is a tapered multi-segment strip that arcs
##       over under its own weight, not a flat isoceles triangle. It carries
##       ROUNDED NORMALS — the face normal is rotated outward at each edge, so
##       a flat strip lights like a cylinder. That one trick is most of the
##       difference between "grass" and "green confetti".
##     • ONE WIND. The hand-rolled sine is gone; the shader reads the same
##       global wind_dir / wind_strength / wind_time / player_push that the
##       leaves and bark read (Wind.gd), so the meadow and the canopy lean the
##       same way in the same gust. Weather drives it, so a storm flattens it.
##     • A GROUND LAYER, not just grass: clover, fern, wildflower, sedge and
##       moss, sited by moisture and lushness noise instead of sprinkled.
##     • SEASONS. Same four-stop hold-and-turn ramp as foliage.gdshader, so the
##       meadow browns off in autumn and takes snow in winter without a rebuild.
##     • SLOPE. Tufts tilt with the ground they grow out of instead of standing
##       dead vertical on a hillside.
##     • LOD. Three meshes per kind; each chunk swaps which one its MultiMesh
##       points at as you walk. Same instances, same transforms — one property
##       assignment. The near meadow is 35 triangles a tuft, the far one is 3.
##
## Chunks rebuild when digging (or a new mouth) changes the surface under
## them — same dirty-area pattern as the rock chunks.

const CHUNK_CELLS := 16          ## grass chunk = one rock chunk footprint (12.8 m)
const TUFTS_PER_CHUNK := 3400    ## placement attempts per chunk. History: 650 at
                                 ## v2, ×2.6 at v2.1 ("much denser"), doubled again
                                 ## at v2.2 for the SHORT grass specifically —
                                 ## the tall-patch keep below halves twice to hold
                                 ## the hiding grass at half its v2.1 density.
                                 ## The LOD ladder is what makes this affordable:
                                 ## the extra tufts are mostly 3-triangle far-field.
const SHORT_KEEP := 0.94         ## short grass keeps nearly all of its draw

## Distance bands. LOD keeps the near meadow expensive and the far one nearly
## free, so the ring can be much wider than v1's 38 m without costing frames.
const LOD_HI := 12.0             ## curved 4-segment blades (pulled in from 15 —
                                 ## at 2.6× density the near ring pays for it)
const LOD_MID := 21.0            ## 2-segment blades (27→22 at v2.2, →21 at v2.3:
                                 ## every density or species add pays its bill here)
const FADE_START := 34.0         ## blades start sinking + taking the ground's colour
const FADE_END := 46.0           ## by here they ARE the ground
const CULL_END := 60.0           ## whole chunks stop rendering
const DETAIL_CULL := 27.0        ## flowers/clover/moss are small — cull them early

const WITHER_R := 11.0           ## grass sickens this close to a cave mouth
const TALL_T := 0.34             ## tall-noise above this = a HIDING patch
const CUT_CELL := 0.6            ## resolution of the mown-grass record (m)
const LITTER_CAP := 1800         ## resting cut blades / fallen leaves held at once
const GUST_EVERY_MIN := 16.0     ## seconds between wind gusts through the litter
const GUST_EVERY_MAX := 38.0
const GUST_RANGE := 34.0         ## only lift leaves someone can see lift
const LOD_TICK := 0.22           ## seconds between LOD re-bands

## Every ground-cover kind. "std"/"tall"/"stub" keep their v1 names so saves,
## the mower and the stealth check all still mean the same thing.
##
## v2.3 — THE GRASS IS MAINE GRASS NOW (per Lemon: "a couple different Maine
## types, whatever's common"). Three real species join the layer:
##   std      = RED FESCUE. The fine, dense field grass — Maine's default
##              ground cover, and the baseline short kind here.
##   timothy  = TIMOTHY. THE Maine hayfield grass: a near-vertical stem with
##              the dense cylindrical seed-head spike on top — reads like a
##              slim cattail and identifies a field at fifty metres.
##   bluestem = LITTLE BLUESTEM. Native bunchgrass of dry, thin, sandy ground.
##              Upright and knee-high, blue-green in summer — and it CURES
##              COPPER-RED in autumn and stands all winter, which is the
##              single best colour event a Maine field has.
##   (tall = the generic hiding bunchgrass, sedge = the wet-ground grass —
##    both already read as bluejoint / sedge meadow and stay as they are.)
const KINDS: Array[String] = ["std", "tall", "stub", "clover", "fern", "flower", "sedge", "moss", "timothy", "bluestem"]
const DETAIL_KINDS := {"clover": true, "flower": true, "moss": true}

## Placement runs on the worker pool, and inside a worker thread the kinds are
## INTEGERS, never these strings.
##
## Why: _place_chunk is a group task, so eight threads run it at once. Using
## `KINDS[i]` as a Dictionary key in there has every thread hashing and
## refcounting the SAME shared String objects concurrently, and Godot's String
## refcount is not safe against that. It does not fail cleanly — it corrupts the
## keys (a lookup comes back as invalid unicode) and then double-frees. It also
## only shows up when the chunks take long enough to genuinely overlap, which a
## small test field never does. Names are attached on the main thread, in
## _apply_chunk, where there is exactly one of us.
const K_STD := 0
const K_TALL := 1
const K_STUB := 2
const K_CLOVER := 3
const K_FERN := 4
const K_FLOWER := 5
const K_SEDGE := 6
const K_MOSS := 7
const K_TIMOTHY := 8
const K_BLUESTEM := 9

## Material ids handed to the shader in UV2.x: 0 living foliage, 1 petal,
## 2 dried straw, 3 moss, 4 seed head (timothy's spike — straw-tan all year),
## 5 bluestem (its own season story: blue-green summer, copper autumn, and it
## STAYS copper through the winter). Everything else about a kind is geometry.
const MAT_LEAF := 0.0
const MAT_PETAL := 1.0
const MAT_DRY := 2.0
const MAT_MOSS := 3.0
const MAT_SEEDHEAD := 4.0
const MAT_BLUESTEM := 5.0

var field: CaveField
var base_seed := 0
var _mat: ShaderMaterial
var _mesh := {}                  ## kind -> [hi, mid, lo] ArrayMesh
var _cut_cells := {}             ## Vector2i cut-grid cell -> true (persists digs + shifts)
var _chunks := {}                ## Vector2i -> {kind: MultiMeshInstance3D}
var _chunk_lod := {}             ## Vector2i -> 0/1/2, so a re-band is one assignment
var _litter := {}                ## kind -> ring buffer of what CAME OFF the world
var _density := FastNoiseLite.new()
var _tall := FastNoiseLite.new() ## slow noise carves the tall meadows — the SAME
                                 ## noise answers "am I hidden here?"
var _clump := FastNoiseLite.new()  ## 2 m scale: tufts grow in clumps, with dirt between
var _moist := FastNoiseLite.new()  ## wet ground -> sedge, moss, fern, deeper green
var _lush := FastNoiseLite.new()   ## rich vs thin ground -> height and colour
var _gust_t := 0.0               ## the leaf-litter gust clock (Tsushima drift)
var _gust_next := 22.0
var _lod_t := 0.0
var _weather: Node = null
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
	## The near-scale one. Real grass grows in clumps with bare dirt showing
	## between them; an even sprinkle is the single most artificial thing a
	## grass system can do.
	_clump.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_clump.frequency = 0.42
	_clump.seed = seed_v * 17 + 5
	_moist.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_moist.frequency = 0.011
	_moist.seed = seed_v * 23 + 9
	_lush.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_lush.frequency = 0.045
	_lush.seed = seed_v * 31 + 19
	_build_material()
	_build_meshes()
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
	## v1 pushed wind_t and player_pos into this shader by hand. Both are now
	## global shader parameters published once by Wind.gd for every foliage
	## shader in the game, so the meadow gusts with the canopy instead of
	## keeping its own private weather. Nothing to push per frame but the wet.
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p != null:
		## The stealth question, answered by the same noise that grew the
		## patches: standing in tall grass on the surface = concealed.
		p.set("grass_hidden", p.global_position.y > -1.1
			and is_tall_at(p.global_position.x, p.global_position.z))

	## Rain darkens the meadow and makes it shine; the ground stays wet a while
	## after the rain stops, which is what Weather.wetness already tracks.
	if _weather == null or not is_instance_valid(_weather):
		var w := get_tree().get_first_node_in_group("world")
		if w != null and w.has_method("weather"):
			_weather = w.call("weather")
	if _weather != null and is_instance_valid(_weather):
		_mat.set_shader_parameter("wetness", float(_weather.get("wetness")))

	## LOD: which mesh each chunk's MultiMeshes point at. Cheap enough to do
	## on a tick rather than a frame — a chunk is 12.8 m and you can't cross a
	## band boundary in a fifth of a second.
	_lod_t += delta
	if _lod_t >= LOD_TICK:
		_lod_t = 0.0
		if p != null:
			_update_lod(p.global_position)

	## Now and then the wind gets under the leaf fall and takes a FEW of them
	## somewhere else. The carpet stays; a handful of it moves.
	_gust_t += delta
	if _gust_t >= _gust_next:
		_gust_t = 0.0
		_gust_next = randf_range(GUST_EVERY_MIN, GUST_EVERY_MAX)
		_gust_leaves(p)


## ---------------------------------------------------------------- LOD ------


func _lod_for(d: float) -> int:
	if d < LOD_HI:
		return 0
	if d < LOD_MID:
		return 1
	return 2


func _chunk_center(key: Vector2i) -> Vector3:
	var half := CHUNK_CELLS * CaveField.VOX * 0.5
	return Vector3(field.origin.x + key.x * CHUNK_CELLS * CaveField.VOX + half, 0.0,
		field.origin.z + key.y * CHUNK_CELLS * CaveField.VOX + half)


func _update_lod(at: Vector3) -> void:
	## One property assignment per changed chunk. MultiMesh.mesh can be swapped
	## without touching the instance buffer, so a whole hillside changes detail
	## for the cost of a pointer — no rebuild, no reupload, no hitch.
	var half := CHUNK_CELLS * CaveField.VOX * 0.5
	for key: Vector2i in _chunks:
		var c := _chunk_center(key)
		var d := maxf(Vector2(c.x - at.x, c.z - at.z).length() - half, 0.0)
		var want := _lod_for(d)
		if int(_chunk_lod.get(key, -1)) == want:
			continue
		_chunk_lod[key] = want
		var per_kind: Dictionary = _chunks[key]
		for kind: String in per_kind:
			var mmi := per_kind[kind] as MultiMeshInstance3D
			if mmi.multimesh != null:
				mmi.multimesh.mesh = (_mesh[kind] as Array)[want]


## ------------------------------------------------------- the stealth read ---


func is_tall_at(wx: float, wz: float) -> bool:
	## A patch only hides you while it's STANDING — mown stubble conceals no one.
	return _tall_noise_at(wx, wz) and not _cut_cells.has(_cut_cell(wx, wz))


func _tall_noise_at(wx: float, wz: float) -> bool:
	return _tall.get_noise_2d(wx, wz) > TALL_T


func _cut_cell(wx: float, wz: float) -> Vector2i:
	return Vector2i(int(floor(wx / CUT_CELL)), int(floor(wz / CUT_CELL)))


func _chunk_key_at(wx: float, wz: float) -> Vector2i:
	var i := int((wx - field.origin.x) / CaveField.VOX)
	var k := int((wz - field.origin.z) / CaveField.VOX)
	return Vector2i(clampi(i / CHUNK_CELLS, 0, _ncx - 1), clampi(k / CHUNK_CELLS, 0, _ncz - 1))


func cut_at(center: Vector3, radius: float) -> bool:
	## THE SWORD MOWS (Player._do_melee_hit): fell every standing TALL tuft
	## inside the swing circle. Short grass is spared, and because chunk seeds
	## are deterministic the felled tufts turn into flat dried STUBBLE in the
	## exact spots they stood — while the patch stops hiding anyone.
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
	if hi.y < CaveField.SY - 10:
		return
	for cx in range(maxi(int(lo.x / float(CHUNK_CELLS)), 0), mini(int(hi.x / float(CHUNK_CELLS)), _ncx - 1) + 1):
		for cz in range(maxi(int(lo.z / float(CHUNK_CELLS)), 0), mini(int(hi.z / float(CHUNK_CELLS)), _ncz - 1) + 1):
			var key := Vector2i(cx, cz)
			_apply_chunk(key, _place_chunk(key))


## --------------------------------------------------------------- placing ---


func _ground_basis(p: Vector3, px: Vector3, pz: Vector3, yaw: float, lean: float) -> Basis:
	## Grass is gravitropic — it grows mostly UP even on a slope — but not
	## perfectly, and a meadow of dead-vertical tufts on a hillside is one of
	## the tells that reads as "instanced". Tilt part of the way to the ground
	## normal and leave the rest to gravity.
	var up := Vector3.UP
	if px != Vector3.INF and pz != Vector3.INF:
		var n := (pz - p).cross(px - p)
		if n.length_squared() > 0.000001:
			n = n.normalized()
			if n.y < 0.0:
				n = -n
			up = n.lerp(Vector3.UP, lean).normalized()
	var fwd := Vector3(cos(yaw), 0.0, sin(yaw))
	var right := fwd.cross(up)
	if right.length_squared() < 0.000001:
		right = Vector3.RIGHT
	right = right.normalized()
	return Basis(right, up, up.cross(right).normalized())


func _pick_kind(rng: RandomNumberGenerator, in_tall: bool, cut: bool,
		moist: float, lush: float) -> int:
	## Which ground cover grows on this square metre. Moisture and richness
	## decide, not a flat dice roll — so ferns come in drifts in the damp
	## hollows and the flowers come up where the ground is worth flowering on.
	## Returns an INDEX, not a name — see the note by K_STD.
	if in_tall:
		if cut:
			return K_STUB
		return K_SEDGE if moist > 0.30 else K_TALL
	var r := rng.randf()
	if moist > 0.50 and r < 0.14:
		return K_MOSS
	if moist > 0.32 and r < 0.30:
		return K_FERN
	if lush > 0.22 and r < 0.24:
		return K_CLOVER
	if lush > 0.06 and r < 0.055:
		return K_FLOWER
	## Little bluestem owns the DRY, thin, sandy ground — where fescue thins
	## out, bluestem takes over in drifts, exactly as it does on a Maine
	## roadside bank. Timothy scatters through the open richer field the way
	## an old hayfield gone wild does: everywhere, but never wall-to-wall.
	if lush < -0.10 and moist < 0.25 and r < 0.55:
		return K_BLUESTEM
	if lush > -0.05 and r < 0.085:
		return K_TIMOTHY
	return K_STD


func _place_chunk(key: Vector2i) -> Dictionary:
	## Sample the voxel surface for standable spots. Deterministic per chunk
	## (seeded rng) so rebuilds don't reshuffle the whole meadow.
	var rng := RandomNumberGenerator.new()
	rng.seed = base_seed + key.x * 73856093 + key.y * 19349663
	## Accumulate into plain Arrays, NOT PackedColorArrays. Godot's Packed*
	## types are VALUE types: `dict[k]["col"].append(c)` appends to a temporary
	## copy and throws it away, so every tuft would have come out colourless.
	## (Same trap the litter ring buffer already carries a warning about.)
	##
	## Indexed by kind INDEX, not name — this function runs on eight threads at
	## once and must not touch the shared KINDS strings. See K_STD.
	var n_kinds := KINDS.size()
	var xf_by: Array = []
	var col_by: Array = []
	for _k in range(n_kinds):
		xf_by.append([] as Array[Transform3D])
		col_by.append([] as Array[Color])
	var cell0x := key.x * CHUNK_CELLS
	var cell0z := key.y * CHUNK_CELLS
	## floor_point walks a voxel column top-down in interpreted GDScript, and
	## at v2.2 density each cell gets ~13 tuft attempts × 3 lookups (self + two
	## neighbours). Uncached, that walk was ~85% of the whole seed time
	## (measured: 10.3 s of a 12 s seed). The floor of a CELL never changes
	## within one placement pass, so memoise it per chunk — local Dictionary,
	## thread-safe because nothing shares it.
	var floors := {}
	for _i in range(TUFTS_PER_CHUNK):
		var i := cell0x + rng.randi_range(0, CHUNK_CELLS - 1)
		var k := cell0z + rng.randi_range(0, CHUNK_CELLS - 1)
		if i < 2 or k < 2 or i > CaveField.SX - 3 or k > CaveField.SZ - 3:
			continue  ## the rim wall grows no meadow
		var wx := field.origin.x + (float(i) + rng.randf()) * CaveField.VOX
		var wz := field.origin.z + (float(k) + rng.randf()) * CaveField.VOX
		var in_tall := _tall_noise_at(wx, wz)
		## SHORT GRASS EVERYWHERE (the baseline is lush on purpose — the player
		## asked for no visible gaps); the noise only breathes variation into it.
		if in_tall:
			if rng.randf() > 0.235:
				continue      ## HALF the v2.1 tall density (per Lemon), against
				              ## a doubled draw: 3400 × 0.235 ≈ 1700 × 0.47.
				              ## Chest-high blades overlap so much that half the
				              ## tufts still reads as full cover, and wading
				              ## through costs half the overdraw
		elif rng.randf() > (0.88 + _density.get_noise_2d(wx, wz) * 0.10) * SHORT_KEEP:
			continue
		## ...but at the near scale it still CLUMPS — the gaps just tightened
		## from "bare patches" to "seams". A meadow with zero structure reads as
		## carpet, so the cutoff stays, moved out to reject only the deepest
		## troughs of the noise.
		if not in_tall and _clump.get_noise_2d(wx, wz) < -0.62:
			continue
		var p := _floor_cached(floors, i, k)
		if p == Vector3.INF or p.y < -1.1 or p.y > 6.5:
			continue  ## no grass down the throat or floating over caves
		## Skip cliff faces: the neighbour column shouldn't drop far.
		var px := _floor_cached(floors, mini(i + 1, CaveField.SX - 3), k)
		if px == Vector3.INF or absf(px.y - p.y) > 0.6:
			continue
		var pz := _floor_cached(floors, i, mini(k + 1, CaveField.SZ - 3))

		var moist := _moist.get_noise_2d(wx, wz)
		var lush := _lush.get_noise_2d(wx, wz)
		var kind := _pick_kind(rng, in_tall, _cut_cells.has(_cut_cell(wx, wz)), moist, lush)

		## Rich ground grows taller. One noise doing two jobs keeps the height
		## variation and the colour variation agreeing with each other, which is
		## what makes a meadow read as ground rather than as scatter.
		var vigour := 1.0 + lush * 0.34 + moist * 0.12
		var sxz := rng.randf_range(0.82, 1.28)
		var sy := rng.randf_range(0.72, 1.36) * vigour
		var lean := 0.55 if kind == K_MOSS else 0.42   ## moss hugs the slope
		var b := _ground_basis(p, px, pz, rng.randf() * TAU, lean)
		var t := Transform3D(Basis(b.x * sxz, b.y * sy, b.z * sxz), Vector3(wx, p.y - 0.02, wz))

		## The instance colour is now a TINT, not the albedo — the shader owns
		## the season. What the placer knows and the shader can't is local: how
		## rich this ground is, and how close it is to a mouth that is killing it.
		var tint := Color(1.0, 1.0, 1.0)
		var dry := clampf(-lush, 0.0, 1.0)
		tint = tint.lerp(Color(1.18, 1.06, 0.72), dry * 0.55)          ## thin ground burns off
		tint = tint.lerp(Color(0.82, 1.02, 0.80), clampf(moist, 0.0, 1.0) * 0.45)  ## damp ground is deeper
		var md := 999.0
		for m in field.mouths:
			md = minf(md, Vector2(wx - m.x, wz - m.z).length())
		tint = tint.lerp(Color(1.05, 0.86, 0.62), clampf(1.0 - md / WITHER_R, 0.0, 1.0) * 0.85)
		tint = tint * rng.randf_range(0.90, 1.10)
		if kind == K_TALL or kind == K_SEDGE:
			tint = tint * 0.88     ## the deep patches are shadier inside
		(xf_by[kind] as Array[Transform3D]).append(t)
		(col_by[kind] as Array[Color]).append(tint.srgb_to_linear())
	var cols: Array = []
	for k in range(n_kinds):
		var pc := PackedColorArray()
		for c: Color in col_by[k]:
			pc.append(c)
		cols.append(pc)
	## Parallel arrays indexed by kind. The main thread puts the names back on
	## in _apply_chunk.
	##
	## (Measured while chasing v2.2's seed time: the main-thread fill is only
	## ~0.3 s even at 614k instances — do NOT be tempted to pre-bake raw
	## MultiMesh buffers here. The actual cost was floor_point, cached below.)
	return {"xf": xf_by, "col": cols}


func _floor_cached(floors: Dictionary, i: int, k: int) -> Vector3:
	var fk := i * 100000 + k
	var hit: Variant = floors.get(fk)
	if hit != null:
		return hit as Vector3
	var p := field.floor_point(Vector3i(i, CaveField.SY - 2, k))
	floors[fk] = p
	return p


func _apply_chunk(key: Vector2i, placed: Dictionary) -> void:
	## Main thread only. This is where the kind INDEXES the worker threads
	## produced get their names back (see K_STD).
	var xf_by: Array = placed["xf"]
	var col_by: Array = placed["col"]
	var any := false
	for ki in range(KINDS.size()):
		if not (xf_by[ki] as Array).is_empty():
			any = true
			break
	if not any:
		if _chunks.has(key):
			for kind: String in _chunks[key]:
				(_chunks[key][kind] as Node).queue_free()
			_chunks.erase(key)
			_chunk_lod.erase(key)
		return
	if not _chunks.has(key):
		_chunks[key] = {}
	var per_kind: Dictionary = _chunks[key]
	var lod := int(_chunk_lod.get(key, 2))
	var ox := field.origin.x + key.x * CHUNK_CELLS * CaveField.VOX
	var oz := field.origin.z + key.y * CHUNK_CELLS * CaveField.VOX
	var aabb := AABB(Vector3(ox, -3.0, oz),
		Vector3(CHUNK_CELLS * CaveField.VOX, 12.0, CHUNK_CELLS * CaveField.VOX))
	for ki in range(KINDS.size()):
		var kind: String = KINDS[ki]
		var xfs: Array[Transform3D] = xf_by[ki]
		if xfs.is_empty():
			if per_kind.has(kind):
				(per_kind[kind] as Node).queue_free()
				per_kind.erase(kind)
			continue
		## An MMI is only born when its kind actually grows here. Creating all
		## eight in all 289 chunks would be 2,312 nodes for a world that mostly
		## wants three of them.
		if not per_kind.has(kind):
			var mmi := MultiMeshInstance3D.new()
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = DETAIL_CULL if DETAIL_KINDS.has(kind) else CULL_END
			mmi.material_override = _mat
			add_child(mmi)
			per_kind[kind] = mmi
		_fill_mm(per_kind[kind] as MultiMeshInstance3D, (_mesh[kind] as Array)[lod],
			xfs, col_by[ki], aabb)


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


## --------------------------------------------------------------- geometry ---
## Everything below builds meshes ONCE at setup. Three LODs per kind; a chunk
## points its MultiMesh at whichever one matches its distance.


func _build_meshes() -> void:
	## segs, blades: the LOD ladder. A 4-segment blade genuinely arcs; a
	## 1-segment blade is v1's flat triangle, which is all a tuft 40 m away
	## has ever needed to be.
	## Field grass. ~0.5 m standing, ~0.3 m across, tips leaning about 50°.
	_mesh["std"] = [
		_tuft(0.44, 0.050, 5, 4, 0.35, 0.55),
		_tuft(0.44, 0.050, 5, 2, 0.35, 0.55),
		_tuft(0.44, 0.058, 3, 1, 0.35, 0.55),
	]
	## The hiding grass: a bunchgrass stand about 1.5 m standing and 1 m across,
	## straight for its bottom half and flopping over above that. This is the
	## one you wade through, so its silhouette has to read at a glance.
	_mesh["tall"] = [
		_tuft(1.35, 0.068, 6, 4, 0.30, 0.80),
		_tuft(1.35, 0.068, 5, 2, 0.30, 0.80),
		_tuft(1.35, 0.076, 3, 1, 0.30, 0.80),
	]
	## Sedge: wetland grass. Narrower blades that arc right over the top and
	## fall back toward the water — the giveaway silhouette at a pond edge.
	_mesh["sedge"] = [
		_tuft(1.15, 0.034, 7, 4, 0.45, 2.10),
		_tuft(1.15, 0.034, 5, 2, 0.45, 2.10),
		_tuft(1.15, 0.042, 3, 1, 0.45, 2.10),
	]
	var stub_hi := _stub(0.17, 0.052, 5)
	_mesh["stub"] = [stub_hi, stub_hi, _stub(0.17, 0.060, 3)]
	_mesh["clover"] = [_clover(3, 4), _clover(2, 3), _clover(1, 3)]
	_mesh["fern"] = [_fern(3, 5), _fern(3, 0), _fern(2, 0)]
	_mesh["flower"] = [_flower(5), _flower(4), _flower(0)]
	var moss_hi := _moss(6)
	_mesh["moss"] = [moss_hi, _moss(4), _moss(3)]
	## Timothy: the seed head IS the identity, so every LOD keeps it — the far
	## mesh is one stem and one spike, which is exactly what timothy looks like
	## at range anyway.
	_mesh["timothy"] = [_timothy(3, 4, 3), _timothy(2, 2, 2), _timothy(1, 2, 0)]
	## Little bluestem: an upright, narrow, knee-high bunch — stiffer than
	## fescue (bunchgrass barely nods), tagged MAT_BLUESTEM for its own
	## season colours.
	_mesh["bluestem"] = [
		_tuft(0.62, 0.038, 6, 4, 0.18, 0.30, MAT_BLUESTEM),
		_tuft(0.62, 0.038, 5, 2, 0.18, 0.30, MAT_BLUESTEM),
		_tuft(0.62, 0.046, 3, 1, 0.18, 0.30, MAT_BLUESTEM),
	]


func _strip(st: SurfaceTool, base: Vector3, out_dir: Vector3, height: float,
		width: float, lean: float, droop: float, segs: int, round_amt: float,
		matid: float, twist := 0.0) -> void:
	## ONE BLADE. The whole realism argument lives in this function.
	##
	## The centre-line is integrated, not lerped: at each step the blade's
	## direction is tilted `(lean + droop*u) * u²` radians off vertical and we
	## walk that way, so the thing genuinely arcs and a long enough blade tips
	## past horizontal and points back at the ground. A straight triangle
	## cannot do that at any vertex count.
	##
	## The u² is not a fudge — a uniformly loaded cantilever deflects as the
	## square of its length, and a blade of grass is exactly that. It puts the
	## bend where a real blade puts it: the bottom half stands up straight and
	## the top third flops. A linear profile splays the whole clump outward
	## instead, and a metre-tall tuft ends up two metres wide.
	##
	## The width tapers as pow(1-u, 0.55) — a spear, not a rectangle.
	##
	## And the normals: the face normal is rotated OUTWARD about the blade's
	## own tangent, by +round_amt on one edge and -round_amt on the other. The
	## rasteriser interpolates between them, so a flat two-triangle strip
	## shades exactly like a curved one. This costs nothing and it is the
	## single biggest difference between grass and green paper.
	var seg_len := height / float(segs)
	var pts: Array[Vector3] = [base]
	var tans: Array[Vector3] = []
	var p := base
	for s in range(segs):
		var u := (float(s) + 0.5) / float(segs)
		var a := (lean + droop * u) * u * u
		var d := (Vector3.UP * cos(a) + out_dir * sin(a)).normalized()
		tans.append(d)
		p += d * seg_len
		pts.append(p)
	for s in range(segs):
		var u0 := float(s) / float(segs)
		var u1 := float(s + 1) / float(segs)
		var w0 := width * pow(maxf(1.0 - u0, 0.0), 0.55)
		var w1 := width * pow(maxf(1.0 - u1, 0.0), 0.55)
		var t0 := tans[s]
		var t1 := tans[mini(s + 1, segs - 1)]
		var side0 := out_dir.cross(t0).normalized().rotated(t0, twist * u0)
		var side1 := out_dir.cross(t1).normalized().rotated(t1, twist * u1)
		var n0 := side0.cross(t0).normalized()
		var n1 := side1.cross(t1).normalized()
		var a0 := pts[s] - side0 * w0
		var b0 := pts[s] + side0 * w0
		var a1 := pts[s + 1] - side1 * w1
		var b1 := pts[s + 1] + side1 * w1
		## rounded normals: lean each edge's normal away from the centre
		var na0 := n0.rotated(t0, -round_amt)
		var nb0 := n0.rotated(t0, round_amt)
		var na1 := n1.rotated(t1, -round_amt)
		var nb1 := n1.rotated(t1, round_amt)
		if s == segs - 1:
			## the last ring collapses to a point — a blade ends in a tip
			var tip := pts[segs]
			_v(st, a0, na0, 0.0, u0, matid)
			_v(st, tip, n1, 0.5, 1.0, matid)
			_v(st, b0, nb0, 1.0, u0, matid)
		else:
			_v(st, a0, na0, 0.0, u0, matid)
			_v(st, a1, na1, 0.0, u1, matid)
			_v(st, b0, nb0, 1.0, u0, matid)
			_v(st, b0, nb0, 1.0, u0, matid)
			_v(st, a1, na1, 0.0, u1, matid)
			_v(st, b1, nb1, 1.0, u1, matid)


func _v(st: SurfaceTool, pos: Vector3, n: Vector3, side: float, u: float, matid: float) -> void:
	## UV carries the blade's own coordinates — side across, height along — so
	## the shader can bend, shade and tint by position along the blade without
	## a texture. UV2.x is which MATERIAL this vertex is (leaf / petal / dry /
	## moss), which is how one shader covers eight kinds of ground cover.
	st.set_normal(n)
	st.set_uv(Vector2(side, u))
	st.set_uv2(Vector2(matid, 0.0))
	st.add_vertex(pos)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3,
		ua: float, ub: float, uc: float, matid: float) -> void:
	_v(st, a, n, 0.0, ua, matid)
	_v(st, b, n, 0.5, ub, matid)
	_v(st, c, n, 1.0, uc, matid)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		n: Vector3, u0: float, u1: float, matid: float) -> void:
	_v(st, a, n, 0.0, u0, matid)
	_v(st, d, n, 0.0, u1, matid)
	_v(st, b, n, 1.0, u0, matid)
	_v(st, b, n, 1.0, u0, matid)
	_v(st, d, n, 0.0, u1, matid)
	_v(st, c, n, 1.0, u1, matid)


func _tuft(height: float, width: float, blades: int, segs: int,
		lean: float, droop: float, matid := MAT_LEAF) -> ArrayMesh:
	## A tuft is a fan of blades around one root, each with its own height,
	## its own lean and its own twist. Identical blades read as a fan; varied
	## ones read as a plant.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in range(blades):
		var ang := TAU * float(b) / float(blades) + 0.35 + float(b % 3) * 0.21
		var out := Vector3(cos(ang), 0.0, sin(ang))
		var vary := 0.78 + 0.44 * float((b * 7) % 5) / 4.0
		_strip(st, out * (0.018 + 0.020 * float(b % 2)), out,
			height * vary, width * (0.85 + 0.3 * float(b % 2)),
			lean * (0.72 + 0.5 * float((b * 3) % 4) / 3.0), droop * vary,
			segs, 0.58, matid, 0.5 - float(b % 2))
	return st.commit()


func _timothy(stems: int, segs: int, basal: int) -> ArrayMesh:
	## TIMOTHY. A hayfield in one silhouette: a thin, nearly straight stem
	## (lean 0.10, droop 0.14 — hay stands, it does not flop) carrying the
	## dense cylindrical seed-head spike, plus a few ordinary blades at the
	## boot. The spike is a 4-sided prism tagged MAT_SEEDHEAD so the shader
	## keeps it straw-tan whatever the season is doing to the leaves.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in range(stems):
		var ang := TAU * float(s) / float(maxi(stems, 1)) + 0.8
		var out := Vector3(cos(ang), 0.0, sin(ang))
		var h := 0.82 * (0.88 + 0.24 * float(s % 2))
		var lean := 0.10 * (0.7 + 0.6 * float((s * 3) % 3) / 2.0)
		var droop := 0.14
		var base := out * 0.014
		_strip(st, base, out, h, 0.013, lean, droop, segs, 0.5, MAT_LEAF)
		## Walk the same arc _strip walks to find the true stem tip, then set
		## the spike on it, aligned with the stem's final direction.
		var seg_len := h / float(segs)
		var p := base
		var d := Vector3.UP
		for q in range(segs):
			var u := (float(q) + 0.5) / float(segs)
			var a := (lean + droop * u) * u * u
			d = (Vector3.UP * cos(a) + out * sin(a)).normalized()
			p += d * seg_len
		var head_h := 0.085 * (0.9 + 0.3 * float(s % 2))
		var r := 0.016
		var side_a := out.cross(d).normalized()
		var side_b := d.cross(side_a).normalized()
		## four quads around the spike, normals facing out — a tiny prism
		for f in range(4):
			var n0 := (side_a if f % 2 == 0 else side_b) * (1.0 if f < 2 else -1.0)
			var t0 := (side_b if f % 2 == 0 else side_a) * (1.0 if f < 2 else -1.0)
			var c0 := p + n0 * r
			_quad(st, c0 - t0 * r, c0 + t0 * r,
				c0 + t0 * r * 0.7 + d * head_h, c0 - t0 * r * 0.7 + d * head_h,
				n0, 0.9, 1.0, MAT_SEEDHEAD)
	for b in range(basal):
		var ang2 := TAU * float(b) / float(maxi(basal, 1)) + 0.25
		var out2 := Vector3(cos(ang2), 0.0, sin(ang2))
		_strip(st, out2 * 0.02, out2, 0.30, 0.030, 0.45, 0.6, 2, 0.58, MAT_LEAF)
	return st.commit()


func _stub(height: float, width: float, blades: int) -> ArrayMesh:
	## CUT grass. The same fan, TRUNCATED — flat-topped little stumps, sheared
	## where the sword went through. The flat cut is what reads "mown", so this
	## one stays square-ended on purpose while everything else got a tip.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in range(blades):
		var ang := TAU * float(b) / float(blades) + 0.35
		var out := Vector3(cos(ang), 0.0, sin(ang))
		var side := Vector3(-sin(ang), 0.0, cos(ang))
		var base := out * 0.08
		var h := height * (0.8 + 0.4 * float(b % 2))
		var top := base + out * 0.05 + Vector3.UP * h
		var n := side.cross(Vector3.UP).normalized()
		_quad(st, base - side * width, base + side * width,
			top + side * width * 0.7, top - side * width * 0.7, n, 0.0, 1.0, MAT_DRY)
	return st.commit()


func _clover(segs: int, leaflets: int) -> ArrayMesh:
	## Broadleaf ground cover — the low round leaves that carpet good soil
	## between the grass. Nearly horizontal, normals nearly up, so a patch of
	## it reads as a soft green FLOOR that the blades come up through.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in range(leaflets):
		var ang := TAU * float(b) / float(leaflets) + 0.6
		var out := Vector3(cos(ang), 0.0, sin(ang))
		var side := Vector3(-sin(ang), 0.0, cos(ang))
		var lift := 0.055 + 0.03 * float(b % 2)
		var stem := out * 0.03 + Vector3.UP * lift
		var reach := 0.085 + 0.03 * float(b % 3)
		var tipv := stem + out * reach + Vector3.UP * 0.012
		var w := 0.052
		var n := (Vector3.UP * 3.0 + out).normalized()
		if segs <= 1:
			_tri(st, stem - side * w * 0.5, tipv, stem + side * w * 0.5, n, 0.0, 1.0, 0.0, MAT_LEAF)
			continue
		var mid := stem.lerp(tipv, 0.55) + Vector3.UP * 0.008
		_quad(st, stem - side * w * 0.45, stem + side * w * 0.45,
			mid + side * w, mid - side * w, n, 0.0, 0.55, MAT_LEAF)
		_tri(st, mid - side * w, tipv, mid + side * w, n, 0.55, 1.0, 0.55, MAT_LEAF)
	return st.commit()


func _fern(fronds: int, pinnae: int) -> ArrayMesh:
	## The shade plant. A frond is one hard-arcing rachis with leaflets down
	## both sides — at range the leaflets are invisible, which is exactly why
	## the far LOD drops them and keeps the arc.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in range(fronds):
		var ang := TAU * float(f) / float(fronds) + 0.9
		var out := Vector3(cos(ang), 0.0, sin(ang))
		var side := Vector3(-sin(ang), 0.0, cos(ang))
		var h := 0.42 + 0.10 * float(f % 2)
		_strip(st, out * 0.02, out, h, 0.030, 0.62, 1.05, 3, 0.42, MAT_LEAF)
		for s in range(pinnae):
			## leaflets ride the arc, shrinking toward the tip
			var u := 0.30 + 0.62 * float(s) / float(maxi(pinnae - 1, 1))
			var a := (0.62 + 1.05 * u) * u * u   ## same arc the rachis walks
			var alongd := (Vector3.UP * cos(a) + out * sin(a)).normalized()
			var at := out * 0.02 + alongd * (h * u)
			var lw := 0.062 * (1.0 - u * 0.7)
			var sgn := 1.0 if s % 2 == 0 else -1.0
			var tipv := at + side * sgn * lw * 2.1 + alongd * lw * 0.7
			var n := (side * sgn * 0.35 + Vector3.UP).normalized()
			_tri(st, at - alongd * lw * 0.5, tipv, at + alongd * lw * 0.5,
				n, 0.4, 0.9, 0.4, MAT_LEAF)
	return st.commit()


func _flower(petals: int) -> ArrayMesh:
	## A stem and a head. The head's vertices are tagged MAT_PETAL, so the
	## shader colours them off the per-tuft hash instead of off the season
	## ramp — which is how one instanced mesh becomes daisies, buttercups,
	## asters and paintbrush in the same meadow.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 0.30
	for b in range(2):
		var ang := 1.1 + PI * float(b)
		var out := Vector3(cos(ang), 0.0, sin(ang))
		_strip(st, out * 0.012, out, h * (0.86 + 0.2 * float(b)), 0.016,
			0.20, 0.28, 2, 0.5, MAT_LEAF)
	if petals <= 0:
		return st.commit()
	var head := Vector3(cos(1.1), 0.0, sin(1.1)) * 0.045 + Vector3.UP * h * 0.97
	for pt in range(petals):
		var a := TAU * float(pt) / float(petals)
		var out2 := Vector3(cos(a), 0.22, sin(a)).normalized()
		var side2 := Vector3(-sin(a), 0.0, cos(a))
		var tipv := head + out2 * 0.042
		var n := (Vector3.UP * 2.2 + out2).normalized()
		_tri(st, head - side2 * 0.014, tipv, head + side2 * 0.014, n, 0.3, 1.0, 0.3, MAT_PETAL)
	return st.commit()


func _moss(facets: int) -> ArrayMesh:
	## A cushion, not a plant. Overlapping near-flat facets domed slightly up,
	## so a damp hollow gets a soft dark-green skin the blades stand out of.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := 0.13
	for f in range(facets):
		var a0 := TAU * float(f) / float(facets)
		var a1 := TAU * float(f + 1) / float(facets)
		var lift := 0.022 + 0.010 * float(f % 3)
		var v0 := Vector3(cos(a0) * r, 0.004, sin(a0) * r)
		var v1 := Vector3(cos(a1) * r, 0.004, sin(a1) * r)
		var c := Vector3(0.0, lift, 0.0)
		var n := ((v0 - c).cross(v1 - c)).normalized()
		if n.y < 0.0:
			n = -n
		_tri(st, v0, c, v1, n, 0.0, 1.0, 0.0, MAT_MOSS)
	return st.commit()


## ------------------------------------------------------------- clippings ---


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


func _burst_clippings(center: Vector3, cells: int) -> void:
	## THE CUT BLADES THEMSELVES. A severed blade PLANES down like a leaf and
	## comes to rest on the dirt — where it STAYS. Mowing leaves a floor of
	## cuttings behind you, not a puff of particles.
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


## ------------------------------- Diagnostics -------------------------------


func stats() -> Dictionary:
	## For the debug menu and the geometry harness: how much meadow is actually
	## standing, and what it costs.
	var by_kind := {}
	var total := 0
	for key: Vector2i in _chunks:
		for kind: String in _chunks[key]:
			var mmi := _chunks[key][kind] as MultiMeshInstance3D
			var n := 0 if mmi.multimesh == null else mmi.multimesh.instance_count
			by_kind[kind] = int(by_kind.get(kind, 0)) + n
			total += n
	return {"chunks": _chunks.size(), "tufts": total, "by_kind": by_kind,
		"cut_cells": _cut_cells.size()}


func _build_material() -> void:
	var sh := Shader.new()
	sh.code = GRASS_SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh


const GRASS_SHADER := """
shader_type spatial;
// ===========================================================================
// GRASS v2 — Myrkfell
//
// One shader for eight kinds of ground cover. What varies per kind is
// geometry plus a material id in UV2.x; what varies per SEASON is a single
// global float; what varies per TUFT is a hash of its root position.
//
// UV.x  = across the blade, 0 .. 1   (the rounded-normal axis)
// UV.y  = along the blade,  0 root .. 1 tip
// UV2.x = 0 living foliage | 1 petal | 2 dried straw | 3 moss
// COLOR = the placer's local TINT (rich / thin / damp ground, wither near a
//         cave mouth). Not the albedo — the season owns the albedo now.
// ===========================================================================
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// --- the one wind. Wind.gd publishes these for every foliage shader --------
global uniform vec3 wind_dir;
global uniform float wind_strength;
global uniform float wind_time;
global uniform float season_phase;
global uniform vec3 player_pos;
global uniform float player_push;

uniform float fade_start = 34.0;
uniform float fade_end = 46.0;
uniform float trample_radius = 1.35;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float snow_amount : hint_range(0.0, 1.0) = 1.0;
uniform vec3 ground_tint : source_color = vec3(0.15, 0.16, 0.12);

uniform vec3 col_spring : source_color = vec3(0.35, 0.53, 0.19);
uniform vec3 col_summer : source_color = vec3(0.25, 0.40, 0.15);
uniform vec3 col_autumn : source_color = vec3(0.53, 0.45, 0.19);
uniform vec3 col_winter : source_color = vec3(0.40, 0.36, 0.24);
uniform vec3 col_dry    : source_color = vec3(0.56, 0.48, 0.25);
uniform vec3 col_moss   : source_color = vec3(0.19, 0.33, 0.14);
uniform vec3 col_snow   : source_color = vec3(0.80, 0.84, 0.90);
uniform vec3 col_seedhead : source_color = vec3(0.70, 0.60, 0.40);
uniform vec3 col_bluestem_summer : source_color = vec3(0.34, 0.46, 0.34);
uniform vec3 col_bluestem_cured  : source_color = vec3(0.62, 0.33, 0.20);

// --- REALISTIC-PIXELED (the new style, per Lemon) ------------------------
// Real species, real silhouettes — shaded like pixel art. Three moves:
//   1. every blade is carved into TEXEL CELLS (pixel_cells along its length,
//      a couple across) and each cell gets one flat value — no gradients
//      inside a cell, a hard step between cells;
//   2. the final colour is POSTERIZED to palette_steps levels per channel,
//      so the whole meadow shares one limited palette like a sprite sheet;
//   3. lighting is BANDED in light() — lit / mid / shade / dark, four flat
//      tones, no smooth falloff and no specular smear.
uniform float pixel_cells : hint_range(4.0, 32.0) = 13.0;
uniform float pixel_side_cells : hint_range(1.0, 6.0) = 3.0;
uniform float palette_steps : hint_range(3.0, 16.0) = 7.0;
uniform float cell_jitter : hint_range(0.0, 0.5) = 0.14;

varying float v_u;
varying float v_side;
varying float v_hash;
varying float v_matid;
varying vec3 v_wnormal;
varying float v_fade;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	v_u = UV.y;
	v_side = UV.x;
	v_matid = UV2.x;

	// MODEL_MATRIX carries the instance transform, so its translation IS this
	// tuft's world position — one stable hash per plant, free.
	vec3 root = MODEL_MATRIX[3].xyz;
	v_hash = hash13(root);

	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = distance(root, INV_VIEW_MATRIX[3].xyz);
	v_fade = 1.0 - clamp((dist - fade_start) / max(fade_end - fade_start, 0.01), 0.0, 1.0);
	// Sink into the sod over the last stretch instead of popping out. It never
	// reaches zero — by then it is the ground's colour anyway (see fragment).
	VERTEX.y *= mix(0.34, 1.0, v_fade);

	float bend = v_u * v_u;   // the root is planted; only the tip swings

	// --- gust: two detuned waves so it never reads as a loop, plus flutter --
	float ph = wind_time * 1.15 + v_hash * 6.283 + root.x * 0.085 + root.z * 0.065;
	float gust = sin(ph) * 0.62 + sin(ph * 2.37 + 1.7) * 0.38;
	float flutter = sin(ph * 6.1 + v_hash * 3.0) * 0.20 * wind_strength;
	vec3 off = wind_dir * ((0.10 + gust * 0.26 + flutter) * wind_strength) * bend;

	// --- you, wading through: aside AND down. Grass you walk on lies down. --
	vec2 away = world.xz - player_pos.xz;
	float d = length(away);
	if (d < trample_radius) {
		float k = 1.0 - d / trample_radius;
		vec2 dirn = (d > 0.0001) ? away / d : vec2(1.0, 0.0);
		float shove = k * k * (0.30 + 0.60 * player_push);
		off.xz += dirn * shove;
		off.y -= shove * 0.5 * bend;
	}

	// A blade that has bent over is SHORTER standing up — it did not stretch,
	// it leaned. Without this the whole meadow visibly grows in a gust.
	off.y -= dot(off.xz, off.xz) * 0.55 * bend;

	// Model-space offset without a 4x4 inverse: transpose the normalised basis
	// and divide out the scale. Same result, a fraction of the cost, and this
	// runs on every vertex of every blade in the world.
	mat3 M = mat3(MODEL_MATRIX[0].xyz, MODEL_MATRIX[1].xyz, MODEL_MATRIX[2].xyz);
	vec3 sc = vec3(length(M[0]), length(M[1]), length(M[2]));
	mat3 Rt = transpose(mat3(M[0] / max(sc.x, 0.0001), M[1] / max(sc.y, 0.0001),
		M[2] / max(sc.z, 0.0001)));
	VERTEX += (Rt * off) / max(sc, vec3(0.0001));

	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// season_phase 0..1 -> four stops, held then turned (same curve as the leaves,
// so the meadow and the canopy change colour on the same week)
vec3 season_colour(float p) {
	float t = fract(p) * 4.0;
	int i = int(floor(t));
	float f = smoothstep(0.55, 1.0, fract(t));
	vec3 a = col_spring;
	vec3 b = col_summer;
	if (i == 1) { a = col_summer; b = col_autumn; }
	else if (i == 2) { a = col_autumn; b = col_winter; }
	else if (i == 3) { a = col_winter; b = col_spring; }
	return mix(a, b, f);
}

// One instanced flower mesh, four species — the hash picks which.
vec3 petal_colour(float h) {
	if (h < 0.34) return vec3(0.92, 0.90, 0.84);   // oxeye daisy
	if (h < 0.62) return vec3(0.95, 0.80, 0.20);   // buttercup
	if (h < 0.86) return vec3(0.55, 0.46, 0.78);   // aster
	return vec3(0.83, 0.28, 0.22);                 // paintbrush
}

void fragment() {
	vec3 col;
	if (v_matid > 4.5) {
		// LITTLE BLUESTEM has its own year: blue-green through summer, cures
		// copper in early autumn, and STANDS copper all winter — the cure only
		// releases when the spring flush comes in.
		float p = fract(season_phase);
		float cure = smoothstep(0.50, 0.70, p);
		cure = max(cure, 1.0 - smoothstep(0.06, 0.20, p));
		col = mix(col_bluestem_summer, col_bluestem_cured, cure);
		col *= 0.85 + 0.3 * v_hash;
	}
	else if (v_matid > 3.5) col = col_seedhead * (0.82 + 0.36 * v_hash); // timothy spike
	else if (v_matid > 2.5) col = col_moss;
	else if (v_matid > 1.5) col = col_dry;
	else if (v_matid > 0.5) col = petal_colour(fract(v_hash * 7.13));
	else col = season_colour(season_phase);

	if (v_matid < 0.5) {
		// no two plants the same green: value spread, then a small hue rotate
		col *= 0.80 + 0.38 * v_hash;
		col = mix(col, col.gbr, (v_hash - 0.5) * 0.12);
	}
	col *= COLOR.rgb;   // the placer's local tint

	// ---- REALISTIC-PIXELED: carve the blade into texel cells ----
	// Everything below shades by the CELL's coordinate, never the fragment's,
	// so each cell comes out one flat colour with a hard step to the next —
	// the blade reads as a little column of pixels.
	float cu = (floor(v_u * pixel_cells) + 0.5) / pixel_cells;
	float cs = floor(v_side * pixel_side_cells);
	// one stable random per cell per plant — sprite-noise, not film grain
	float cj = fract(sin(cu * 127.1 + cs * 311.7 + v_hash * 74.7) * 43758.5453);
	col *= 1.0 - cell_jitter * 0.5 + cell_jitter * cj;

	// Depth in the mass, per-cell: shaded root cells, lit yellowing tip cells.
	col *= mix(0.38, 1.0, smoothstep(0.0, 0.55, cu));
	col = mix(col, col * vec3(1.22, 1.15, 0.76), smoothstep(0.5, 1.0, cu) * 0.40);

	// rain: darker, and it stays that way a while after
	col *= mix(1.0, 0.60, wetness);

	// winter: snow settles cell by cell — tip cells whiten first, and the
	// per-cell jitter decides stragglers, so the line between snow and blade
	// is ragged pixels, not a smooth ramp
	float winter = smoothstep(0.74, 0.90, fract(season_phase))
		* (1.0 - smoothstep(0.97, 1.0, fract(season_phase)));
	float up = clamp(v_wnormal.y, 0.0, 1.0);
	float snow_cell = step(1.0 - winter * snow_amount * up * (0.20 + 0.80 * cu), cj);
	col = mix(col, col_snow, snow_cell);

	// far edge: still becomes the ground it grows out of
	col = mix(ground_tint, col, 0.30 + 0.70 * v_fade);

	// ---- and POSTERIZE: the whole meadow shares one limited palette ----
	col = floor(col * palette_steps + 0.5) / palette_steps;

	ALBEDO = col;

	// ROUNDED NORMALS, then blended toward world-up at the base. The tips stay
	// round so they read as blades; the roots read as ground. Without the
	// blend a meadow sparkles like tinsel at every camera move.
	vec3 n = normalize(mix(v_wnormal, vec3(0.0, 1.0, 0.0), mix(0.48, 0.06, v_u)));
	if (!FRONT_FACING) n = -n;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	// Pixel style: no specular smear — a sprite doesn't glint. Wet grass gets
	// its darkening above and one extra light band below instead of gloss.
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	// BANDED LIGHT — four flat tones, hard edges. This is the half of the
	// pixel look that is not the texels: smooth Lambert falloff across a
	// curved blade reads as 3D render; three steps read as sprite shading.
	float nl = dot(NORMAL, LIGHT);
	float band;
	if (nl > 0.55) band = 1.0;
	else if (nl > 0.18) band = 0.72;
	else if (nl > -0.12) band = 0.45;
	else band = 0.26;
	// wet meadow: the lit band brightens a step instead of glinting
	band *= 1.0 + wetness * 0.18 * step(0.9, band);
	DIFFUSE_LIGHT += LIGHT_COLOR * ALBEDO * band * ATTENUATION / PI;
	// backlight, banded too: sun behind a thin blade lights the tip cells —
	// two flat steps, strongest at the tip, none at the root
	float back = max(-nl, 0.0);
	float bband = back > 0.6 ? 0.42 : (back > 0.25 ? 0.20 : 0.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ALBEDO * bband * v_u * (1.0 - wetness * 0.45) * ATTENUATION / PI;
}
"""
