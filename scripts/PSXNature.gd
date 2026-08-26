class_name PSXNature
extends RefCounted

## ===========================================================================
## The PSX Nature & Biomes pack, as data.       (docs/TREES_v3_PSX.md §1-§2)
##
## Everything that knows an asset NAME lives here: which mesh a species wears
## at a stage, how tall it really is, how fat its trunk is where you swing,
## which of the six painted atlases a region runs through the year, and the
## one shared material pair per (atlas, region) so 420 trees are three draw
## calls' worth of state, not 420.
##
## The pack ships the same three atlases painted six ways. That is the whole
## season system: a region binds four of them and the shader crossfades off
## `season_phase`. No mesh is rebuilt, no texture is tinted, nothing is
## regenerated when the year turns.
## ===========================================================================

const GLB := "res://assets/psx_nature/glb/%s.glb"
const MANIFEST := "res://assets/psx_nature/glb/manifest.json"
const TEX := "res://assets/psx_nature/textures/%s/T_%s_%s_BaseColor.png"

const WOOD_SHADER := "res://shaders/psx_wood.gdshader"
const FOLIAGE_SHADER := "res://shaders/psx_foliage.gdshader"

## region -> the four atlases it runs, spring / summer / autumn / winter.
## Six painted biomes, five ways of living in them.
const REGIONS := {
	"temperate": ["Spring", "Temperate", "Autumn", "Snowy"],    ## the ordinary woods
	"deepwood":  ["Dark", "Dark", "Dark", "Snowy"],             ## Myrkfell proper — gloom all year
	"redwood":   ["Redwood", "Redwood", "Redwood", "Snowy"],    ## a stand of giants
	"highland":  ["Spring", "Temperate", "Snowy", "Snowy"],     ## snow comes early up the mountain
	"blight":    ["Dark", "Dark", "Autumn", "Dark"],            ## ground that never really greens
}
const DEFAULT_REGION := "temperate"

## --- which mesh a species wears -------------------------------------------
## Species survives the art swap as SHAPE and BEHAVIOUR — log yield, seed,
## growth rate, how it reads on a ridge — not as its own leaf texture. The
## atlas carries the colour now, and it carries it for the whole biome.
const TREE_MESH := {
	"maple": {"live": ["SM_Tree_01"], "bare": ["SM_BareTree_01"], "sapling": ["SM_Plant_02"]},
	"birch": {"live": ["SM_Tree_02"], "bare": ["SM_BareTree_02"], "sapling": ["SM_Plant_02"]},
	"oak":   {"live": ["SM_Tree_01", "SM_Tree_02"], "bare": ["SM_BareTree_01", "SM_BareTree_02"],
			  "sapling": ["SM_Plant_02"]},
	"pine":  {"live": ["SM_Pine_01", "SM_Pine_02", "SM_Pine_04"], "bare": ["SM_BarePine_01"],
			  "sapling": ["SM_Pine_05"], "great": ["SM_GiantPine_01", "SM_GiantPine_02"]},
	"fir":   {"live": ["SM_Pine_03", "SM_Pine_05", "SM_Pine_06"], "bare": ["SM_BarePine_02"],
			  "sapling": ["SM_Pine_06"], "great": ["SM_GiantPine_01", "SM_GiantPine_02"]},
}

## Stage -> the height it should stand at, in metres (spec §4, unchanged).
const STAGE_H := [[0.8, 1.4], [3.0, 4.0], [7.0, 9.0], [10.0, 13.0], [7.0, 9.0]]

## --- the understory and the litter ----------------------------------------
const FERNS := ["SM_Fern_01", "SM_Fern_02"]
const PLANTS := ["SM_Plant_01", "SM_Plant_02", "SM_Plant_03", "SM_Plant_04"]
const SHRUBS := ["SM_Shrub_01", "SM_Shrub_02"]
const ROCKS := ["SM_Rock_01", "SM_Rock_02", "SM_Rock_03", "SM_Rock_04",
				"SM_Rock_05", "SM_Rock_06", "SM_Rock_07", "SM_Rock_08"]
const LOGS := ["SM_FallenLog_Large", "SM_FallenLog_Small"]
const STUMPS := ["SM_Stump_01", "SM_Stump_02"]
const TWIGS := ["SM_Twig_01", "SM_Twig_02", "SM_Twig_03", "SM_Twig_04"]

static var _manifest: Dictionary = {}
static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}


## ------------------------------------------------------------- manifest ---

static func manifest() -> Dictionary:
	if not _manifest.is_empty():
		return _manifest
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		push_warning("PSXNature: no manifest at %s" % MANIFEST)
		return _manifest
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_manifest = parsed
	return _manifest


static func info(asset: String) -> Dictionary:
	var m := manifest()
	return m.get(asset, {})


static func has(asset: String) -> bool:
	return manifest().has(asset)


static func scene_path(asset: String) -> String:
	return GLB % asset


## How fat the trunk is at `y` metres up the UNSCALED model. The exporter
## samples every 25 cm; gaps (a height with no ring near it) are bridged from
## the neighbours rather than reported as zero, which would let the axe fall
## straight through the tree.
static func radius_at(asset: String, y: float) -> float:
	var d := info(asset)
	var prof: Array = d.get("profile", [])
	if prof.is_empty():
		return float(d.get("radius", 0.25))
	var i := int(clampf(y / 0.25, 0.0, float(prof.size() - 1)))
	for step in range(prof.size()):
		var lo := i - step
		var hi := i + step
		if lo >= 0 and float(prof[lo]) > 0.0:
			return float(prof[lo])
		if hi < prof.size() and float(prof[hi]) > 0.0:
			return float(prof[hi])
	return float(d.get("radius", 0.25))


## --------------------------------------------------------------- picking ---

## Everything TreeV2 needs to stand one tree up: which model, how far to scale
## it, and the real measured trunk it will be swinging at.
static func pick_tree(species: String, stage: int, dead: bool, scale_class: float,
		rng: RandomNumberGenerator) -> Dictionary:
	var table: Dictionary = TREE_MESH.get(species, TREE_MESH["maple"])
	var pool: Array = table.get("live", [])
	if stage == 0:
		pool = table.get("sapling", pool)
	elif dead or stage == 4:
		pool = table.get("bare", pool)
	## A great tree is a landmark, and the pack has two of them.
	if scale_class >= 3.0 and table.has("great") and not dead and stage >= 2:
		pool = table["great"]
	if pool.is_empty():
		pool = ["SM_Tree_01"]

	var band: Array = STAGE_H[clampi(stage, 0, STAGE_H.size() - 1)]
	var target: float = rng.randf_range(float(band[0]), float(band[1])) * maxf(scale_class, 0.1)

	## Take the model whose REAL size is closest to the height we want, so a
	## mature fir is a six-metre fir scaled a little rather than a four-metre
	## one blown up to twice its size. Second-closest gets a look-in so a stand
	## does not turn out to be one tree copied forty times.
	var ranked := pool.duplicate()
	ranked.sort_custom(func(a, b):
		return absf(float(info(a).get("height", 1.0)) - target) \
			 < absf(float(info(b).get("height", 1.0)) - target))
	var asset: String = String(ranked[0])
	if ranked.size() > 1 and rng.randf() < 0.32:
		asset = String(ranked[1])
	var d := info(asset)
	var native: float = maxf(float(d.get("height", 1.0)), 0.01)
	var s: float = target / native

	## The notch is carved in MODEL space, and the exporter only packed rings
	## through 0.28-2.20 m of it. Clamp the chop height into that window so a
	## sapling-scaled or giant-scaled trunk still has geometry to lose.
	## 1.45 m up the MODEL, not 1.95: above that the pack's trunks are already
	## opening into the crotch, and sampling the radius there gave a three-metre
	## sapling a trunk a third of a metre thick.
	var chop_y: float = clampf(1.02 / maxf(s, 0.001), 0.45, 1.45)

	return {
		"asset": asset, "scale": s, "height": target, "chop_y": chop_y,
		## Floored: the leafy shoots that stand in for saplings have no wood in
		## them at all, and a zero-radius trunk makes the notch maths divide by
		## nothing.
		"radius": maxf(radius_at(asset, chop_y) * s, 0.035),
		"atlas": String(d.get("atlas", "Props")),
		"choppable": bool(d.get("choppable", false)),
		"canopy_lo": float(d.get("canopy_lo", 0.0)) * s,
		"canopy_hi": float(d.get("canopy_hi", 0.0)) * s,
	}


## The species the registry knows, for callers that want to walk them all.
static func ALL_SPECIES_TEST() -> Array:
	return TREE_MESH.keys()


static func pick(list: Array, rng: RandomNumberGenerator) -> String:
	return String(list[rng.randi() % list.size()])


## ------------------------------------------------------------- materials ---

static func region_atlases(region: String) -> Array:
	return REGIONS.get(region, REGIONS[DEFAULT_REGION])


static func _tex(biome: String, atlas: String) -> Texture2D:
	var p := TEX % [biome, biome, atlas + "Atlas"]
	if not ResourceLoader.exists(p):
		push_warning("PSXNature: missing atlas %s" % p)
		return null
	return load(p)


## One shared [wood, foliage] pair per (atlas group, region, alive/dead).
## Never edit these in place — a felled tree that wants its own `shed` value
## takes a duplicate (see TreeV2._shed_leaves).
static func materials(atlas: String, region := DEFAULT_REGION, dead := false) -> Array:
	var key := "%s|%s|%s" % [atlas, region, "dead" if dead else "live"]
	if _mats.has(key):
		return _mats[key]

	var stops := region_atlases(region)
	var names := ["atlas_spring", "atlas_summer", "atlas_autumn", "atlas_winter"]

	var wood := ShaderMaterial.new()
	wood.shader = load(WOOD_SHADER)
	var leaf := ShaderMaterial.new()
	leaf.shader = load(FOLIAGE_SHADER)
	for i in range(4):
		var t := _tex(String(stops[i]), atlas)
		wood.set_shader_parameter(names[i], t)
		leaf.set_shader_parameter(names[i], t)
	wood.set_shader_parameter("dead", dead)
	leaf.set_shader_parameter("dead", dead)
	## A snag keeps only the needles that never fell off it.
	leaf.set_shader_parameter("dead_cling", 0.30 if dead else 1.0)

	_mats[key] = [wood, leaf]
	return _mats[key]


## For the scatter layers, which want the raw Mesh rather than a scene.
## `part` is "Trunk" or "Foliage".
static func mesh_for(asset: String, part := "Foliage") -> Mesh:
	var key := asset + "|" + part
	if _meshes.has(key):
		return _meshes[key]
	var packed = load(GLB % asset)
	if packed == null:
		_meshes[key] = null
		return null
	var inst: Node = packed.instantiate()
	var found: Mesh = null
	for n in _walk(inst):
		var mi := n as MeshInstance3D
		if mi != null and mi.name.begins_with(part):
			found = mi.mesh
			break
	inst.queue_free()
	_meshes[key] = found
	return found


static func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out


## Test seam: forget every cached material so a suite can rebuild them.
static func flush() -> void:
	_mats.clear()
	_meshes.clear()
