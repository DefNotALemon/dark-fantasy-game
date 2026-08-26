class_name Understory
extends Node3D

## ===========================================================================
## The forest floor, made of the PSX pack.   (docs/TREES_v3_PSX.md §6)
##
## This REPLACES GrassSystem's procedural blades. Lemon's call, in his words:
## he did not like the generated grass. Grass.gd is untouched on disk and one
## bool puts it back (CaveRegion.USE_PSX_UNDERSTORY) -- nothing here deletes
## three rounds of tuning, it just stops running it.
##
## What is kept from that work, deliberately, is the SITING: the same chunk
## grid, the same five noise fields with the same seeds, the same floor_point
## sampling and cliff rejection, the same deterministic per-chunk rng. So the
## ferns come up in the damp hollows exactly where the old ferns did.
##
## What changes is what gets drawn: the pack's ferns, plants and shrubs, plus
## the litter of the wood -- twigs, rocks, fallen logs and old stumps -- and
## no blades at all. The floor is carried by the ground TEXTURE (psx_ground)
## with things growing out of it, which is how the pack's own renders read.
##
## It keeps GrassSystem's public surface (group "grass_system", is_tall_at,
## cut_at, rebuild_area, save_state, apply_state) because Player, Enemy,
## CaveRegion and World all reach for those by name. Stealth in particular is
## load-bearing: Enemy aggro reads `grass_hidden` off the player and something
## has to keep writing it.
## ===========================================================================

const CHUNK_CELLS := 16          ## one rock chunk footprint, 12.8 m — same as grass

## Per-layer: how many placement attempts a chunk makes, what ground it wants,
## how big it stands, and how far away it is still worth drawing.
## `wood` layers use the opaque trunk material and take no instance tint (the
## wood shader reads COLOR as the axe-cut flag — tinting one would paint it
## heartwood).
const LAYERS: Array[Dictionary] = [
	{"name": "plant", "assets": PSXNature.PLANTS, "n": 520, "wood": false,
	 "scale": [0.55, 1.15], "cull": 32.0, "lean": 0.45, "moist": -1.0, "tall_ok": true},
	{"name": "fern", "assets": PSXNature.FERNS, "n": 300, "wood": false,
	 "scale": [0.60, 1.30], "cull": 40.0, "lean": 0.55, "moist": 0.10, "tall_ok": true},
	{"name": "shrub", "assets": PSXNature.SHRUBS, "n": 44, "wood": false,
	 "scale": [0.42, 0.95], "cull": 68.0, "lean": 0.30, "moist": -1.0, "tall_ok": true},
	{"name": "twig", "assets": PSXNature.TWIGS, "n": 90, "wood": true,
	 "scale": [0.70, 1.40], "cull": 26.0, "lean": 0.92, "moist": -1.0, "tall_ok": false},
	## Only the SMALL stones scatter here. Anything you could stand on, climb or
	## trip over needs a real collider, and four thousand of those is a worse
	## trade than a hundred hand-placed ones -- so the boulders, the fallen logs
	## and the old stumps are PSXProp bodies placed by World._build_props().
	{"name": "rock", "assets": SMALL_ROCKS, "n": 18, "wood": true,
	 "scale": [0.45, 1.15], "cull": 54.0, "lean": 0.80, "moist": -1.0, "tall_ok": false},
]

## The pebbles: Rock_01..04 are ankle-height (0.20-0.47 m) and read as ground
## litter. Rock_05, 07 and 08 are waist-to-chest and get colliders instead.
const SMALL_ROCKS := ["SM_Rock_01", "SM_Rock_02", "SM_Rock_03", "SM_Rock_06"]

## A chunk uses at most this many variants of a layer. Eight rock meshes in
## every chunk would be eight MultiMeshInstances holding two rocks each — the
## draw calls cost more than the rocks.
const VARIANTS_PER_CHUNK := 2

const TALL_T := 0.34             ## tall-noise above this = a HIDING patch
const CUT_CELL := 0.6            ## resolution of the trampled-ground record (m)
const WITHER_R := 11.0           ## the floor sickens this close to a cave mouth
const LOD_TICK := 0.25

var field: CaveField
var base_seed := 0
var region := PSXNature.DEFAULT_REGION

var _chunks := {}                ## Vector2i -> {asset: MultiMeshInstance3D}
var _cut_cells := {}             ## trampled/cleared cells, persists through a save
var _density := FastNoiseLite.new()
var _tall := FastNoiseLite.new()
var _clump := FastNoiseLite.new()
var _moist := FastNoiseLite.new()
var _lush := FastNoiseLite.new()
var _ncx := 0
var _ncz := 0
var _bkeys: Array[Vector2i] = []
var _bresults := []
var _lod_t := 0.0
var _mats := {}                  ## "atlas|wood" -> Material


func _ready() -> void:
	add_to_group("grass_system")   ## everything else looks for the floor by this name
	add_to_group("understory")


func setup(f: CaveField, seed_v: int, region_id := "") -> void:
	field = f
	base_seed = seed_v
	if region_id != "":
		region = region_id
	## Same fields, same seed arithmetic as Grass.setup(). Change one of these
	## and the ferns move off the damp ground they have always grown on.
	_density.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_density.frequency = 0.035
	_density.seed = seed_v * 7 + 3
	_tall.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_tall.frequency = 0.016
	_tall.seed = seed_v * 13 + 11
	_clump.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_clump.frequency = 0.42
	_clump.seed = seed_v * 17 + 5
	_moist.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_moist.frequency = 0.011
	_moist.seed = seed_v * 23 + 9
	_lush.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_lush.frequency = 0.045
	_lush.seed = seed_v * 31 + 19

	_ncx = int(ceil(float(CaveField.CELLS_X) / CHUNK_CELLS))
	_ncz = int(ceil(float(CaveField.CELLS_Z) / CHUNK_CELLS))
	_reseed_all()
	print("Understory: %d chunks seeded, %d instances" % [_chunks.size(), instance_count()])


func instance_count() -> int:
	var n := 0
	for key: Vector2i in _chunks:
		for a: String in _chunks[key]:
			var mmi := _chunks[key][a] as MultiMeshInstance3D
			if mmi != null and mmi.multimesh != null:
				n += mmi.multimesh.instance_count
	return n


## ------------------------------------------------------------- materials ---

func _material(asset: String, wood: bool) -> Material:
	var atlas := String(PSXNature.info(asset).get("atlas", "Props"))
	var key := atlas + ("|wood" if wood else "|leaf")
	if _mats.has(key):
		return _mats[key]
	var pair := PSXNature.materials(atlas, region, false)
	var m: Material = pair[0] if wood else pair[1]
	_mats[key] = m
	return m


## ------------------------------------------------------------- placement ---

func _reseed_all() -> void:
	_bkeys.clear()
	for cx in range(_ncx):
		for cz in range(_ncz):
			_bkeys.append(Vector2i(cx, cz))
	_bresults.resize(_bkeys.size())
	var gid := WorkerThreadPool.add_group_task(_build_task, _bkeys.size(), -1, true, "Understory")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	for n in range(_bkeys.size()):
		if _bresults[n] is Dictionary:
			_apply_chunk(_bkeys[n], _bresults[n] as Dictionary)
	_bresults.clear()


func _build_task(n: int) -> void:
	_bresults[n] = _place_chunk(_bkeys[n])


func _floor_cached(floors: Dictionary, i: int, k: int) -> Vector3:
	## floor_point walks a voxel column in interpreted GDScript and is by far
	## the most expensive thing in this loop. The floor of a cell cannot change
	## inside one pass, so memoise it. Local dict — nothing is shared across the
	## worker threads, and Godot Strings are NOT safe as shared dict keys here.
	var fk := i * 100000 + k
	var hit: Variant = floors.get(fk)
	if hit != null:
		return hit as Vector3
	var p := field.floor_point(Vector3i(i, CaveField.SY - 2, k))
	floors[fk] = p
	return p


func _cut_cell(wx: float, wz: float) -> Vector2i:
	return Vector2i(int(floor(wx / CUT_CELL)), int(floor(wz / CUT_CELL)))


func _tall_noise_at(wx: float, wz: float) -> bool:
	return _tall.get_noise_2d(wx, wz) > TALL_T


func _place_chunk(key: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = base_seed + key.x * 73856093 + key.y * 19349663

	## Which variants this chunk is allowed to use. Deterministic off the chunk
	## key, so a neighbouring chunk brings different ferns and the wood does not
	## read as one plant repeated four hundred times.
	var allowed: Array = []
	for li in range(LAYERS.size()):
		var pool: Array = LAYERS[li]["assets"]
		var picks: Array = []
		var off := absi(key.x * 31 + key.y * 17 + li * 7)
		for v in range(mini(VARIANTS_PER_CHUNK, pool.size())):
			picks.append(String(pool[(off + v) % pool.size()]))
		allowed.append(picks)

	var by_asset := {}          ## asset -> Array[Transform3D]
	var tint_by := {}           ## asset -> Array[Color]
	var cell0x := key.x * CHUNK_CELLS
	var cell0z := key.y * CHUNK_CELLS
	var floors := {}

	for li in range(LAYERS.size()):
		var L: Dictionary = LAYERS[li]
		var picks: Array = allowed[li]
		if picks.is_empty():
			continue
		var srange: Array = L["scale"]
		for _i in range(int(L["n"])):
			var i := cell0x + rng.randi_range(0, CHUNK_CELLS - 1)
			var k := cell0z + rng.randi_range(0, CHUNK_CELLS - 1)
			if i < 2 or k < 2 or i > CaveField.SX - 3 or k > CaveField.SZ - 3:
				continue                    ## the rim wall grows nothing
			var wx := field.origin.x + (float(i) + rng.randf()) * CaveField.VOX
			var wz := field.origin.z + (float(k) + rng.randf()) * CaveField.VOX

			var moist := _moist.get_noise_2d(wx, wz)
			if moist < float(L["moist"]):
				continue                    ## ferns want the damp hollows
			var lush := _lush.get_noise_2d(wx, wz)
			var in_tall := _tall_noise_at(wx, wz)
			if in_tall and not bool(L["tall_ok"]):
				continue

			## Clumping, exactly as the meadow did it: an even sprinkle is the
			## single most artificial thing ground cover can do.
			if _clump.get_noise_2d(wx, wz) < -0.58 and not in_tall:
				continue
			if not in_tall and rng.randf() > 0.90 + _density.get_noise_2d(wx, wz) * 0.10:
				continue
			if _cut_cells.has(_cut_cell(wx, wz)):
				continue                    ## trampled or cleared ground stays bare

			var p := _floor_cached(floors, i, k)
			if p == Vector3.INF or p.y < -1.1 or p.y > 6.5:
				continue
			var px := _floor_cached(floors, mini(i + 1, CaveField.SX - 3), k)
			if px == Vector3.INF or absf(px.y - p.y) > 0.6:
				continue                    ## no cliff faces
			var pz := _floor_cached(floors, i, mini(k + 1, CaveField.SZ - 3))

			var asset: String = String(picks[rng.randi() % picks.size()])
			var vigour := 1.0 + lush * 0.30 + maxf(moist, 0.0) * 0.14
			if in_tall:
				vigour *= 1.35              ## the hiding patches grow rank
			var s := rng.randf_range(float(srange[0]), float(srange[1])) * vigour
			var b := _ground_basis(p, px, pz, rng.randf() * TAU, float(L["lean"]))
			var t := Transform3D(Basis(b.x * s, b.y * s, b.z * s),
				Vector3(wx, p.y - 0.03 * s, wz))

			var tint := Color(1.0, 1.0, 1.0)
			if not bool(L["wood"]):
				var dry := clampf(-lush, 0.0, 1.0)
				tint = tint.lerp(Color(1.16, 1.05, 0.74), dry * 0.50)
				tint = tint.lerp(Color(0.84, 1.02, 0.82), clampf(moist, 0.0, 1.0) * 0.40)
				var md := 999.0
				for m in field.mouths:
					md = minf(md, Vector2(wx - m.x, wz - m.z).length())
				tint = tint.lerp(Color(1.05, 0.86, 0.62),
					clampf(1.0 - md / WITHER_R, 0.0, 1.0) * 0.80)
				tint = tint * rng.randf_range(0.90, 1.10)

			if not by_asset.has(asset):
				by_asset[asset] = ([] as Array[Transform3D])
				tint_by[asset] = ([] as Array[Color])
			(by_asset[asset] as Array[Transform3D]).append(t)
			(tint_by[asset] as Array[Color]).append(tint)

	## Packed* arrays are VALUE types in GDScript — building one inside the loop
	## and appending through a Dictionary lookup silently throws every write
	## away. Convert once, here, on plain Arrays that behaved.
	var cols := {}
	for a: String in tint_by:
		var pc := PackedColorArray()
		for c: Color in tint_by[a]:
			pc.append(c.srgb_to_linear())
		cols[a] = pc
	return {"xf": by_asset, "col": cols}


func _ground_basis(p: Vector3, px: Vector3, pz: Vector3, yaw: float, lean: float) -> Basis:
	## Plants grow mostly UP even on a slope; a rock or a log lies ON it. `lean`
	## is how far toward the ground normal this layer goes — 0 is dead vertical,
	## 1 is flat on the hillside.
	var up := Vector3.UP
	if px != Vector3.INF and pz != Vector3.INF:
		var n := (pz - p).cross(px - p)
		if n.length_squared() > 0.000001:
			n = n.normalized()
			if n.y < 0.0:
				n = -n
			up = Vector3.UP.lerp(n, lean).normalized()
	var fwd := Vector3(cos(yaw), 0.0, sin(yaw))
	var right := fwd.cross(up)
	if right.length_squared() < 0.000001:
		right = Vector3.RIGHT
	right = right.normalized()
	return Basis(right, up, up.cross(right).normalized())


func _apply_chunk(key: Vector2i, placed: Dictionary) -> void:
	var xf: Dictionary = placed.get("xf", {})
	var col: Dictionary = placed.get("col", {})
	if not _chunks.has(key):
		_chunks[key] = {}
	var per: Dictionary = _chunks[key]

	## Anything that used to grow here and no longer does goes away.
	for a: String in per.keys():
		if not xf.has(a):
			(per[a] as Node).queue_free()
			per.erase(a)

	var ox := field.origin.x + key.x * CHUNK_CELLS * CaveField.VOX
	var oz := field.origin.z + key.y * CHUNK_CELLS * CaveField.VOX
	var aabb := AABB(Vector3(ox, -3.0, oz),
		Vector3(CHUNK_CELLS * CaveField.VOX, 14.0, CHUNK_CELLS * CaveField.VOX))

	for a: String in xf:
		var list: Array[Transform3D] = xf[a]
		if list.is_empty():
			continue
		var L := _layer_of(a)
		var wood := bool(L.get("wood", false))
		var mesh := PSXNature.mesh_for(a, "Trunk" if wood else "Foliage")
		if mesh == null:
			continue
		if not per.has(a):
			var mmi := MultiMeshInstance3D.new()
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = float(L.get("cull", 40.0))
			mmi.visibility_range_end_margin = 6.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			mmi.material_override = _material(a, wood)
			add_child(mmi)
			per[a] = mmi
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		## Only the leafy layers carry a tint. psx_wood reads COLOR as the
		## axe-cut flag (white = untouched bark), so tinting a rock would paint
		## it fresh heartwood.
		mm.use_colors = not wood
		mm.mesh = mesh
		mm.instance_count = list.size()
		var pc: PackedColorArray = col.get(a, PackedColorArray())
		for n in range(list.size()):
			mm.set_instance_transform(n, list[n])
			if not wood and n < pc.size():
				mm.set_instance_color(n, pc[n])
		mm.custom_aabb = aabb
		(per[a] as MultiMeshInstance3D).multimesh = mm


func _layer_of(asset: String) -> Dictionary:
	for L in LAYERS:
		if (L["assets"] as Array).has(asset):
			return L
	return LAYERS[0]


## -------------------------------------------------------------- the game ---

func _process(delta: float) -> void:
	_lod_t += delta
	if _lod_t < LOD_TICK:
		return
	_lod_t = 0.0
	## Enemy aggro reads `grass_hidden` off the player, so something has to
	## keep writing it. Cover is now the rank patches of shrub and fern rather
	## than tall blades, but it is the same noise field deciding where.
	for p in get_tree().get_nodes_in_group("player"):
		if p is Node3D:
			var n3 := p as Node3D
			p.set("grass_hidden", n3.global_position.y > -1.1
				and is_tall_at(n3.global_position.x, n3.global_position.z))


func is_tall_at(wx: float, wz: float) -> bool:
	return _tall_noise_at(wx, wz) and not _cut_cells.has(_cut_cell(wx, wz))


func cut_at(center: Vector3, radius: float) -> bool:
	## A swing clears the undergrowth in front of you: the ferns and shrubs go
	## down and the patch stops hiding anyone. Same contract the mown meadow
	## had, so Player._do_melee_hit needs no change.
	if field == null or center.y < -1.6 or center.y > 7.0:
		return false
	var any := false
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
				continue
			_cut_cells[cell] = true
			any = true
			touched[_chunk_key_at(cw.x, cw.y)] = true
	if any:
		for key: Vector2i in touched:
			_apply_chunk(key, _place_chunk(key))
	return any


func _chunk_key_at(wx: float, wz: float) -> Vector2i:
	var i := int((wx - field.origin.x) / CaveField.VOX)
	var k := int((wz - field.origin.z) / CaveField.VOX)
	return Vector2i(clampi(i / CHUNK_CELLS, 0, _ncx - 1), clampi(k / CHUNK_CELLS, 0, _ncz - 1))


func rebuild_area(lo: Vector3i, hi: Vector3i) -> void:
	## The ground changed — a dig, a new mouth, a crater. Reseed what grew on it.
	if hi.y < CaveField.SY - 10:
		return
	for cx in range(maxi(int(lo.x / float(CHUNK_CELLS)), 0),
			mini(int(hi.x / float(CHUNK_CELLS)), _ncx - 1) + 1):
		for cz in range(maxi(int(lo.z / float(CHUNK_CELLS)), 0),
				mini(int(hi.z / float(CHUNK_CELLS)), _ncz - 1) + 1):
			var key := Vector2i(cx, cz)
			_apply_chunk(key, _place_chunk(key))


## ------------------------------------------------------------------ save ---

func save_state() -> Dictionary:
	var cells: Array[Vector2i] = []
	for c: Vector2i in _cut_cells:
		cells.append(c)
	return {"kind": "understory", "cut": cells}


func apply_state(d: Dictionary) -> void:
	_cut_cells.clear()
	for c in d.get("cut", []):
		_cut_cells[c as Vector2i] = true
	## A load has to re-place every chunk, or the cleared ground comes back
	## overgrown while the save says it was trampled flat.
	_reseed_all()
