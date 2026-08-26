class_name TreeV2
extends StaticBody3D

## ===========================================================================
## A standing tree.  docs/TREES_v2_SPEC.md §5, §8
##
## Shape comes from a GLB built by tools/treegen2.py: an empty root with a
## `Trunk` child and one `Branch_NN_rXXX` child per order-1 limb.
##
## CHOPPING (rewritten — limbs no longer gate anything):
## the axe eats a WEDGE out of the struck side of the trunk, deeper every swing,
## and when the wedge passes the centre the trunk breaks on it and goes over.
## The notch is carved into the real trunk mesh by pushing its vertices inward,
## which is why tools/treegen2.py packs rings every 12 cm through the chop zone.
## Limbs are still choppable for sticks if you aim at one; they are never a gate.
## ===========================================================================

## ART SOURCE. true = the PSX Nature & Biomes pack (assets/psx_nature),
## false = the procedural trees tools/treegen2.py bakes into assets/trees/glb.
## Everything below -- notch carving, felling physics, bucking, snags,
## save/load -- runs identically either way. The pack changed the models, not
## the game.
const USE_PSX := true

const GLB_PATH := "res://assets/trees/glb/%s_%d_%s.glb"
const STAGE_NAMES: Array[String] = ["sapling", "young", "mature", "ancient", "withered"]
const ALL_SPECIES: Array[String] = ["maple", "birch", "oak", "pine", "fir"]

## Stage -> how many 2 m logs the trunk bucks into (spec §4)
const LOG_YIELD: Array[int] = [0, 1, 3, 5, 2]
## Stage -> axe bites to eat through the trunk
const TRUNK_CHOPS: Array[int] = [1, 3, 5, 7, 4]
## Stage -> trunk radius in metres, for the collider and the fallen log
const TRUNK_R: Array[float] = [0.03, 0.10, 0.30, 0.46, 0.30]
const TRUNK_H: Array[float] = [1.1, 3.6, 8.2, 11.0, 8.0]

## --- the notch -------------------------------------------------------------
const NOTCH_Y := 1.02        ## the height a chopper naturally swings at
const NOTCH_H := 0.40        ## half-height of the wedge (the V opening)
const NOTCH_ANG := 1.20      ## half-angle the wedge wraps around the trunk
const BREAK_AT := 1.02       ## wedge depth / trunk radius that drops the tree
const HEART := Color(0.52, 0.39, 0.21)   ## fresh-cut heartwood

const LIMB_AIM := 1.6        ## aim this close to a limb and the axe takes it

## --- materials -------------------------------------------------------------
## The GLBs ship with NO textures on purpose (one shared atlas beats 25 embedded
## copies), so their glTF materials are placeholders and must never be used.
const FOLIAGE_SHADER := "res://shaders/foliage.gdshader"
const BARK_SHADER := "res://shaders/bark.gdshader"
const LEAF_ATLAS := "res://assets/trees/leaves/%s_leaf_atlas.png"
const LEAF_NORMAL := "res://assets/trees/leaves/%s_leaf_normal.png"
const BARK_TEX := "res://assets/trees/bark/%s_bark_%s.png"

## spring / summer / autumn / winter, straight out of tools/leafgen.py
const SEASON_RAMPS := {
	"maple": [Color(0.44, 0.56, 0.26), Color(0.24, 0.36, 0.18), Color(0.86, 0.34, 0.09), Color(0.40, 0.22, 0.14)],
	"birch": [Color(0.56, 0.66, 0.31), Color(0.31, 0.43, 0.21), Color(0.87, 0.63, 0.17), Color(0.44, 0.34, 0.18)],
	"oak":   [Color(0.36, 0.46, 0.23), Color(0.19, 0.29, 0.15), Color(0.56, 0.27, 0.12), Color(0.34, 0.22, 0.13)],
	"pine":  [Color(0.20, 0.33, 0.22), Color(0.16, 0.28, 0.20), Color(0.16, 0.27, 0.19), Color(0.21, 0.33, 0.34)],
	"fir":   [Color(0.17, 0.28, 0.21), Color(0.13, 0.24, 0.19), Color(0.13, 0.23, 0.18), Color(0.19, 0.30, 0.33)],
}
const MARCESCENCE := {"maple": 0.0, "birch": 0.0, "oak": 0.25, "pine": 0.0, "fir": 0.0}
const EVERGREEN := {"pine": true, "fir": true}

## --- dying ------------------------------------------------------------------
## A dead tree wears deadwood bark (one shared set — a snag stops looking like an
## oak or a maple within a season) and goes bare but for a few clinging leaves.
## The WITHERED stage is always dead; anything else dies only on a slim roll.
const DEAD_BARK := "res://assets/trees/bark/dead_bark_%s.png"
const SNAG_CHANCE := 0.02      ## a standing mature/ancient tree that simply died
const BRITTLE := 2             ## dead wood gives up this many chops sooner

static var _mat_cache := {}

@export var species := "maple"
@export var stage := 2

var tree_seed := 0
## Which of the six painted biomes this tree runs through the year.
## PSXNature.REGIONS holds the four-atlas recipe per region.
var region := "temperate"
## What PSXNature.pick_tree handed back: asset, scale, real height, the chop
## height in MODEL space and the trunk radius measured there.
var _psx: Dictionary = {}
var _psx_leaf: ShaderMaterial = null    ## this tree's own copy, once it sheds
var _dense := false                     ## the carve-ready trunk is in
var dead := false             ## a snag: deadwood bark, bare branches
var felled := false
var chops_left := 0
var notch_depth := 0.0        ## metres of wood taken out of the struck side
var notch_ang := 0.0          ## which way the wedge faces, tree-local radians
var scale_class := 1.0        ## NORMAL 1.0 / ELDER 1.7 / GREAT 3.5-4.5 (spec §4)

## What the last swing did, for the HUD: "limb", "limb_off", "trunk", "felled".
var last_result := ""

var _model: Node3D
var _trunk: MeshInstance3D
var _branches: Array = []     ## of TreeBranch
var _col: CollisionShape3D

## The trunk mesh as exported, kept pristine so every carve starts from it
## instead of compounding on the last one.
var _trunk_arrays: Array = []
## The trunk's own axis, sampled every SPINE_STEP up through the chop zone.
## (0, y, 0) is NOT the centre — the trunk wanders as it climbs.
var _spine := PackedVector3Array()


static func make(rng: RandomNumberGenerator, species_id := "", stage_i := -1,
		region_id := "") -> TreeV2:
	var t := TreeV2.new()
	t.species = species_id if species_id != "" else ALL_SPECIES[rng.randi() % ALL_SPECIES.size()]
	if stage_i >= 0:
		t.stage = stage_i
	else:
		var r := rng.randf()
		## withered is DEAD standing timber — it should be a rare sight, not 8%
		t.stage = 1 if r < 0.18 else (2 if r < 0.74 else (3 if r < 0.96 else 4))
	t.tree_seed = rng.randi()
	if t.stage >= 2 and rng.randf() < 0.04:
		t.scale_class = 1.7      ## ELDER — the tree you notice (spec §4)
	## Withered trees are dead by definition; a live one dies only on a slim roll.
	t.dead = t.stage == 4 or (t.stage >= 2 and rng.randf() < SNAG_CHANCE)
	if region_id != "":
		t.region = region_id
	return t


func _ready() -> void:
	add_to_group("trees")
	add_to_group("choppable")
	## A withered tree is dead however it was built — placed by hand, restored
	## from a save, or rolled by make(). Don't leave that rule in one code path.
	if stage == 4:
		dead = true
	chops_left = TRUNK_CHOPS[stage]
	if dead:
		chops_left = maxi(chops_left - BRITTLE, 1)   ## dead wood is brittle
	_build()


func _build() -> void:
	if USE_PSX:
		_build_psx()
		return
	var path := GLB_PATH % [species, stage, STAGE_NAMES[stage]]
	var packed := load(path)
	if packed == null:
		push_warning("TreeV2: missing model %s" % path)
		return
	_model = packed.instantiate()
	_model.scale = Vector3.ONE * scale_class
	add_child(_model)

	var mats := materials_for(species, dead)

	var parts: Node = _model
	if _model.get_child_count() == 1 and _model.get_child(0).get_child_count() > 0:
		parts = _model.get_child(0)     ## Godot wraps the glTF scene in a root
	for child in parts.get_children():
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		_apply_materials(mi, mats)
		if mi.name.begins_with("Trunk"):
			_trunk = mi
		elif mi.name.begins_with("Branch"):
			var b := TreeBranch.new()
			b.setup(mi, self)
			add_child(b)
			_branches.append(b)

	_col = CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = maxf(TRUNK_R[stage] * scale_class, 0.06)
	cyl.height = TRUNK_H[stage] * scale_class
	_col.shape = cyl
	_col.position.y = cyl.height * 0.5
	add_child(_col)


## ------------------------------------------------------------------- PSX ---

func _build_psx() -> void:
	## Seeded from the tree's own seed, so a tree restored from a save picks the
	## SAME model it had before. Get this wrong and every load reshuffles the
	## forest.
	var rng := RandomNumberGenerator.new()
	rng.seed = tree_seed if tree_seed != 0 else hash(str(global_position))
	_psx = PSXNature.pick_tree(species, stage, dead, scale_class, rng)

	var packed = load(PSXNature.scene_path(_psx["asset"]))
	if packed == null:
		push_warning("TreeV2: missing PSX model %s" % _psx.get("asset", "?"))
		return
	_model = packed.instantiate()
	_model.scale = Vector3.ONE * float(_psx["scale"])
	add_child(_model)

	var mats := PSXNature.materials(String(_psx["atlas"]), region, dead)
	for n in _flatten(_model):
		var mi := n as MeshInstance3D
		if mi == null:
			continue
		var leafy := mi.name.begins_with("Foliage")
		for i in range(maxi(mi.mesh.get_surface_count() if mi.mesh else 0, 1)):
			mi.set_surface_override_material(i, mats[1] if leafy else mats[0])
		if mi.name.begins_with("Trunk"):
			_trunk = mi
		## No Branch_NN nodes in the pack: a PSX tree is one piece of wood.
		## Limbing was already optional (spec §22) -- now it simply is not a
		## thing, and every swing goes into the trunk where the player aimed.

	_col = CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = maxf(float(_psx["radius"]), 0.06)
	cyl.height = maxf(float(_psx["height"]), 0.2)
	_col.shape = cyl
	_col.position.y = cyl.height * 0.5
	add_child(_col)


func _flatten(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_flatten(c))
	return out


## The pack's trunks are four- to eight-sided tubes with nothing through the
## chop band -- no geometry, no notch. The dense trunk is a separate GLB so 420
## standing trees never pay for it; it is swapped in the first time an axe
## lands, and the shape is identical, so the swap is invisible.
func _swap_dense_trunk() -> void:
	if _dense or _trunk == null:
		return
	_dense = true
	var path := PSXNature.scene_path(String(_psx.get("asset", "")) + "_chop")
	if not ResourceLoader.exists(path):
		return
	var packed = load(path)
	if packed == null:
		return
	var inst: Node = packed.instantiate()
	for n in _flatten(inst):
		var mi := n as MeshInstance3D
		if mi != null and mi.name.begins_with("Trunk") and mi.mesh != null:
			_trunk.mesh = mi.mesh
			_trunk.set_surface_override_material(0,
				PSXNature.materials(String(_psx["atlas"]), region, dead)[0])
			break
	inst.queue_free()


## The canopy comes off on the way down -- Lemon's call: leaves SHOULD shed,
## just properly. The cards drop out of the mesh card-by-card over the fall
## (one hashed threshold in the shader, no rebuild) while a burst of real
## leaves flutters down out of the crown.
func _shed_leaves() -> void:
	if not USE_PSX or _model == null:
		return
	if float(_psx.get("canopy_hi", 0.0)) <= 0.0:
		return    ## a snag or a bare tree has nothing to throw

	var shared := PSXNature.materials(String(_psx["atlas"]), region, dead)[1] as ShaderMaterial
	_psx_leaf = shared.duplicate() as ShaderMaterial
	for n in _flatten(_model):
		var mi := n as MeshInstance3D
		if mi != null and mi.name.begins_with("Foliage"):
			for i in range(maxi(mi.mesh.get_surface_count() if mi.mesh else 0, 1)):
				mi.set_surface_override_material(i, _psx_leaf)

	var n_cards := 34 + stage * 12
	LeafBurst.spawn_from(_model, String(_psx["atlas"]), region, get_parent(), n_cards)


## -------------------------------------------------------------- materials ---

static func materials_for(species_id: String, is_dead := false) -> Array:
	var key := species_id + ("_dead" if is_dead else "")
	if _mat_cache.has(key):
		return _mat_cache[key]

	var tex := DEAD_BARK if is_dead else BARK_TEX
	var bark := ShaderMaterial.new()
	bark.shader = load(BARK_SHADER)
	if is_dead:
		bark.set_shader_parameter("bark_albedo", load(tex % "albedo"))
		bark.set_shader_parameter("bark_normal", load(tex % "normal"))
		bark.set_shader_parameter("bark_rough", load(tex % "rough"))
		bark.set_shader_parameter("bark_height", load(tex % "height"))
		bark.set_shader_parameter("moss_amount", 0.10)   ## dead wood grows little
	else:
		bark.set_shader_parameter("bark_albedo", load(tex % [species_id, "albedo"]))
		bark.set_shader_parameter("bark_normal", load(tex % [species_id, "normal"]))
		bark.set_shader_parameter("bark_rough", load(tex % [species_id, "rough"]))
		bark.set_shader_parameter("bark_height", load(tex % [species_id, "height"]))
	## UVs are baked in METRES (treegen2._part_mesh), so tiling is "repeats per
	## metre" — the same texel density on a fat trunk and a thin twig.
	bark.set_shader_parameter("tiling", Vector2(1.6, 1.6))

	var leaf := ShaderMaterial.new()
	leaf.shader = load(FOLIAGE_SHADER)
	leaf.set_shader_parameter("leaf_atlas", load(LEAF_ATLAS % species_id))
	leaf.set_shader_parameter("leaf_normal", load(LEAF_NORMAL % species_id))
	var ramp: Array = SEASON_RAMPS.get(species_id, SEASON_RAMPS["maple"])
	leaf.set_shader_parameter("col_spring", ramp[0])
	leaf.set_shader_parameter("col_summer", ramp[1])
	leaf.set_shader_parameter("col_autumn", ramp[2])
	leaf.set_shader_parameter("col_winter", ramp[3])
	leaf.set_shader_parameter("deciduous", not EVERGREEN.has(species_id))
	leaf.set_shader_parameter("marcescence", float(MARCESCENCE.get(species_id, 0.0)))
	leaf.set_shader_parameter("dead", is_dead)

	_mat_cache[key] = [bark, leaf]
	return _mat_cache[key]


func _apply_materials(mi: MeshInstance3D, mats: Array) -> void:
	## Match by the glTF material NAME, not by surface index: a trunk with no
	## leaves on it has only one surface, so indices don't line up.
	if mi.mesh == null:
		return
	for i in range(mi.mesh.get_surface_count()):
		var src: Material = mi.mesh.surface_get_material(i)
		var nm := str(src.resource_name) if src != null else ""
		var is_leaf := nm.findn("leaf") >= 0 or nm.findn("foliage") >= 0
		mi.set_surface_override_material(i, mats[1] if is_leaf else mats[0])


func leaf_material() -> Material:
	return materials_for(species, dead)[1]


## ------------------------------------------------------------- the notch ---

const SPINE_STEP := 0.05     ## how finely the trunk axis is sampled
const SPINE_WINDOW := 0.07   ## averaging window: wide enough to cover a tilted ring
const SPINE_TOP := 3.2       ## only the chop zone needs an axis

func _cache_trunk() -> void:
	## Lazy: 420 standing trees should not pay for a spine none of them needs
	## until an axe actually lands.
	if not _spine.is_empty():
		return
	_swap_dense_trunk()
	if _trunk == null or _trunk.mesh == null or _trunk.mesh.get_surface_count() == 0:
		return
	_trunk_arrays = _trunk.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = _trunk_arrays[Mesh.ARRAY_VERTEX]

	var top := SPINE_TOP * scale_class
	if USE_PSX and not _psx.is_empty():
		top = maxf(SPINE_TOP, float(_psx["chop_y"]) * 1.8)
	var slots := int(top / SPINE_STEP) + 2
	var sums := PackedVector3Array()
	var counts := PackedInt32Array()
	sums.resize(slots)
	counts.resize(slots)

	for v in verts:
		if v.y < -0.2 or v.y > top:
			continue
		## Add the vertex to every slot within the window. A whole ring — often
		## two — lands in each slot, which is what makes the centre an axis and
		## not just the vertex itself.
		var lo := maxi(int((v.y - SPINE_WINDOW) / SPINE_STEP), 0)
		var hi := mini(int((v.y + SPINE_WINDOW) / SPINE_STEP), slots - 1)
		for i in range(lo, hi + 1):
			sums[i] += v
			counts[i] += 1

	_spine.resize(slots)
	var last := Vector3.ZERO
	for i in range(slots):
		if counts[i] > 0:
			last = sums[i] / float(counts[i])
		_spine[i] = Vector3(last.x, float(i) * SPINE_STEP, last.z)


func _ring_centre(y: float) -> Vector3:
	if _spine.is_empty():
		return Vector3(0, y, 0)
	var i := clampi(int(y / SPINE_STEP), 0, _spine.size() - 1)
	var c := _spine[i]
	return Vector3(c.x, y, c.z)


func trunk_radius() -> float:
	## World metres -- what the fallen trunk and the stump are built from.
	if USE_PSX and not _psx.is_empty():
		return maxf(float(_psx["radius"]), 0.05)
	return TRUNK_R[stage] * scale_class


func model_radius() -> float:
	## MODEL metres -- what the notch is carved in. The two differ by the
	## model's scale, and mixing them up is how a sapling ends up with a wedge
	## wider than the tree.
	if USE_PSX and not _psx.is_empty():
		return maxf(float(_psx["radius"]) / maxf(float(_psx["scale"]), 0.001), 0.02)
	return TRUNK_R[stage]


func trunk_height() -> float:
	if USE_PSX and not _psx.is_empty():
		return maxf(float(_psx["height"]), 0.2)
	return TRUNK_H[stage] * scale_class


func _carve_notch() -> void:
	## Push the trunk's own vertices inward inside the wedge. Always rebuilt
	## from the pristine arrays, so depth is absolute and never compounds.
	_cache_trunk()
	if _trunk == null or _trunk_arrays.is_empty():
		return
	var src: PackedVector3Array = _trunk_arrays[Mesh.ARRAY_VERTEX]
	var verts := PackedVector3Array(src)
	## The wedge is authored in world metres but carved in the trunk mesh's own
	## space, so both the height and the half-height divide by the model scale.
	var ny := NOTCH_Y * scale_class
	var nh := NOTCH_H * scale_class
	if USE_PSX and not _psx.is_empty():
		ny = float(_psx["chop_y"])
		nh = NOTCH_H / maxf(float(_psx["scale"]), 0.001)
	var y_lo := ny - nh
	var y_hi := ny + nh

	## Per-vertex "how much wood came off here", 0..1. The bark shader reads it
	## and paints heartwood, so the cut face stops wearing bark.
	var cols := PackedColorArray()
	cols.resize(verts.size())
	## White = untouched bark. The bark shader reads (1 - COLOR.r), so anything
	## without a colour array (every branch mesh) correctly reads as no cut.
	for i in range(cols.size()):
		cols[i] = Color(1, 1, 1, 1)

	for i in range(verts.size()):
		var v := verts[i]
		if v.y < y_lo or v.y > y_hi:
			continue
		var c := _ring_centre(v.y)
		var rel := Vector3(v.x - c.x, 0.0, v.z - c.z)
		var r := rel.length()
		if r < 0.001:
			continue
		var a := atan2(rel.z, rel.x)
		var da: float = absf(wrapf(a - notch_ang, -PI, PI))
		if da > NOTCH_ANG:
			continue
		## V in both axes: deepest at the middle of the cut, tapering to nothing
		## at the top, bottom and sides of the wedge.
		## Hold full depth through the middle of the cut and taper only near the
		## edges: a linear falloff in both axes gives a shallow cone that reads
		## as a dent, not as something an axe did.
		var fy: float = clampf((1.0 - absf(v.y - ny) / nh) / 0.55, 0.0, 1.0)
		var fa: float = clampf((1.0 - da / NOTCH_ANG) / 0.55, 0.0, 1.0)
		var cut: float = notch_depth * fy * fa
		var nr: float = maxf(r - cut, 0.012)
		verts[i] = Vector3(c.x + rel.x / r * nr, v.y, c.z + rel.z / r * nr)
		## Anything the axe actually moved is exposed wood. Scale by the bite so
		## the shallow edges of the wedge are half-bark, the middle is bare.
		if cut > 0.004:
			var bare: float = 1.0 - clampf(cut / maxf(notch_depth, 0.001), 0.0, 1.0)
			cols[i] = Color(bare, bare, bare, 1)

	var arrays := _trunk_arrays.duplicate()
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	## keep every other surface (sapling twigs) exactly as it was
	for s in range(1, _trunk.mesh.get_surface_count()):
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _trunk.mesh.surface_get_arrays(s))
	_trunk.mesh = am
	var mats: Array = PSXNature.materials(String(_psx["atlas"]), region, dead) \
		if (USE_PSX and not _psx.is_empty()) else materials_for(species, dead)
	_trunk.set_surface_override_material(0, mats[0])
	for s in range(1, am.get_surface_count()):
		_trunk.set_surface_override_material(s, mats[1])


## --------------------------------------------------------------- gameplay ---

func branches_left() -> int:
	var n := 0
	for b in _branches:
		var tb := b as TreeBranch
		if is_instance_valid(tb) and not tb.gone:
			n += 1
	return n


func trunk_blocked() -> bool:
	## Kept so older callers still compile. Limbs never gate the trunk now.
	return false


func nearest_branch(_from: Vector3, aim: Vector3) -> TreeBranch:
	## Only a limb you are actually pointing at gets hit; otherwise the swing
	## belongs to the trunk.
	if aim == Vector3.INF:
		return null
	var best: TreeBranch = null
	var best_d := INF
	for b in _branches:
		var tb := b as TreeBranch
		if not is_instance_valid(tb) or tb.gone:
			continue
		var d := tb.hit_point().distance_to(aim)
		if d < best_d:
			best_d = d
			best = tb
	return best if best_d <= LIMB_AIM * scale_class else null


func chop_hit(toward_chopper: Vector3, aim := Vector3.INF) -> bool:
	## One bite. Returns TRUE only on the swing that fells the tree.
	if felled:
		return false

	## Aiming straight at a limb takes the limb — worth doing for the sticks,
	## never required.
	var limb := nearest_branch(global_position, aim)
	if limb != null:
		last_result = "limb_off" if limb.take_hit(1) else "limb"
		return false

	## Otherwise the wedge goes into the trunk on the side you're standing.
	var local := (global_transform.basis.inverse() * toward_chopper).normalized()
	notch_ang = atan2(local.z, local.x)
	chops_left -= 1
	## notch_depth lives in MODEL metres because that is where the vertices are.
	var r := model_radius()
	notch_depth = minf(notch_depth + r * (BREAK_AT / float(maxi(TRUNK_CHOPS[stage], 1))),
		r * BREAK_AT)
	_carve_notch()
	_shiver(toward_chopper)

	if chops_left > 0:
		last_result = "trunk"
		return false
	last_result = "felled"
	_fell(-toward_chopper)
	return true


func blast_fell(from: Vector3) -> void:
	## Something took the ground out from under this tree — a meteor crater, for
	## one. Put it over AWAY from the blast, and leave a real trunk on the
	## ground: before this the crater simply swallowed the base and the tree
	## stood there with nothing under it.
	if felled:
		return
	var away := global_position - from
	away.y = 0.0
	if away.length_squared() < 0.04:
		away = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	notch_depth = model_radius() * BREAK_AT
	chops_left = 0
	last_result = "felled"
	_fell(away.normalized(), false)   ## the crater ate the stump too


func _shiver(world_toward: Vector3) -> void:
	if _model == null:
		return
	var tw := create_tween()
	var away := -world_toward.normalized() * 0.05
	tw.tween_property(_model, "position", away, 0.05)
	tw.tween_property(_model, "position", Vector3.ZERO, 0.16)


func _fell(dir: Vector3, leave_stump := true) -> void:
	## Physics, not animation: the trunk goes over the way the wedge points and
	## crashes onto its side.
	felled = true
	remove_from_group("trees")
	remove_from_group("choppable")

	var world := get_parent()
	## Throw the canopy before the model changes hands, or the burst spawns
	## parented to a body that is already rolling.
	_shed_leaves()
	var trunk := FallenTrunk.make(
		global_position,
		dir.normalized(),
		trunk_height(),
		trunk_radius(),
		species,
		LOG_YIELD[stage])
	trunk.sticks = 1 + int(stage >= 2) + int(stage >= 3)
	if _psx_leaf != null:
		trunk.leaf_mat = _psx_leaf
	## Hand the whole tree over — carved trunk, bark, and every limb still on
	## it. The limbs become colliders, so it lands propped on its own branches
	## instead of lying flat like a telegraph pole.
	if _model != null and is_instance_valid(_model):
		remove_child(_model)
		trunk.adopt(_model)
		_model = null
	world.add_child(trunk)

	if leave_stump:
		var stump := TreeStump.make(global_position, trunk_radius(), species)
		world.add_child(stump)

	for p in get_tree().get_nodes_in_group("player"):
		if p.has_method("tree_crash_shake"):
			p.tree_crash_shake(global_position)

	queue_free()


## ------------------------------------------------------------------ save ---

func save_dict() -> Dictionary:
	return {
		"kind": "tree_v2",
		"species": species,
		"stage": stage,
		"seed": tree_seed,
		"dead": dead,
		"scale": scale_class,
		"region": region,
		"pos": [global_position.x, global_position.y, global_position.z],
		"rot": rotation.y,
		"chops": chops_left,
		"notch": notch_depth,
		"notch_ang": notch_ang,
		"branches": _branch_state(),
	}


func _branch_state() -> Array:
	var out: Array = []
	for b in _branches:
		out.append(0 if (is_instance_valid(b) and not b.gone) else 1)
	return out


static func from_dict(d: Dictionary) -> TreeV2:
	var t := TreeV2.new()
	t.species = str(d.get("species", "maple"))
	t.stage = int(d.get("stage", 2))
	t.tree_seed = int(d.get("seed", 0))
	t.dead = bool(d.get("dead", false))
	t.scale_class = float(d.get("scale", 1.0))
	t.region = str(d.get("region", "temperate"))
	var p: Array = d.get("pos", [0, 0, 0])
	t.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	t.rotation.y = float(d.get("rot", 0.0))
	return t


func restore(d: Dictionary) -> void:
	chops_left = int(d.get("chops", TRUNK_CHOPS[stage]))
	notch_depth = float(d.get("notch", 0.0))
	notch_ang = float(d.get("notch_ang", 0.0))
	var st: Array = d.get("branches", [])
	for i in range(mini(st.size(), _branches.size())):
		if int(st[i]) == 1:
			(_branches[i] as TreeBranch).remove_silently()
	if notch_depth > 0.0:
		_carve_notch()      ## a half-chopped tree comes back half-chopped
