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
const USE_PSX := false

## ART SOURCE, second axis. true = trees v4: the model is assembled at runtime
## from TreeKit's authored part library by natural botanical ratios, with the
## bark relief carved into the mesh. false = the tools/treegen2.py GLBs.
## USE_PSX still wins over both. Nothing else changes either way -- the kit
## builds the same node structure the GLBs did, on purpose.
##
## NOTE for the two perf passes below: the kit carries FEWER seed cards than the
## GLBs it replaces (measured: mature maple 1400 -> ~1250, mature fir 2006 ->
## ~1500, ancient oak 1639 -> ~1400) and a fraction of the wood (mature fir
## 15,380 tris -> 4,400) and roughly a THIRD the mesh nodes. So the PAD_* dials
## and the shadow cull are, on the kit, a smaller bill than they were tuned for.
const USE_KIT := true

const GLB_PATH := "res://assets/trees/glb/%s_%d_%s.glb"
const STAGE_NAMES: Array[String] = ["sapling", "young", "mature", "ancient", "withered"]
const ALL_SPECIES: Array[String] = ["maple", "birch", "oak", "pine", "fir"]

## Stage -> how many 2 m logs the trunk bucks into (spec §4)
const LOG_YIELD: Array[int] = [0, 1, 3, 5, 2]
## Stage -> axe bites to eat through the trunk
## THREE SWINGS FELL A TREE, whatever its size (Lemon 2026-09-14: "the full
## tree should take 3 hits with the axe"); a sapling is one. Was [1,3,5,7,4].
const TRUNK_CHOPS: Array[int] = [1, 3, 3, 3, 3]
## Stage -> trunk radius in metres, for the collider and the fallen log
const TRUNK_R: Array[float] = [0.03, 0.10, 0.30, 0.46, 0.30]
const TRUNK_H: Array[float] = [1.1, 3.6, 8.2, 11.0, 8.0]

## --- the notch -------------------------------------------------------------
const NOTCH_Y := 1.02        ## FALLBACK line, world metres -- the height a
                             ## chopper naturally swings at, used only when a
                             ## bite arrives with no aim (a save, a blast fell)
const NOTCH_H := 0.40        ## half-height of the wedge at FULL depth
const NOTCH_ANG := 1.20      ## half-angle the wedge wraps at FULL depth
## The wedge does not arrive full size. A first nick gets this share of the
## opening above and grows toward it as the cut deepens, so what you watch is a
## keen little mark turning into a mouth you can see daylight through.
const NOTCH_OPEN_MIN := 0.34
const NOTCH_ANG_MIN := 0.45
## THE CUT DOES NOT MOVE. The first bite decides the line and every swing after
## it only makes the same wedge bigger -- which is also why there is no dial
## here any more. It is the break height too, so a wandering cut would be a
## wandering break.
const BREAK_AT := 1.02       ## wedge depth / trunk radius that drops the tree
const HEART := Color(0.52, 0.39, 0.21)   ## fresh-cut heartwood

const LIMB_AIM := 1.6        ## aim this close to a limb and the axe takes it

## --- the dense canopy (Lemon 2026-08-29) ------------------------------------
## The GLB's baked leaf cards are treated as SEEDS: each one grows a cluster of
## flat HORIZONTAL leaf pads, tops up at the sun, laid adjacent so the crown
## reads as layered shelves of foliage. The outer shell is small pads on the
## fully wind-animated material; the inside is fewer, BIGGER, darker pads on
## the STATIC material (they just ride the branch) — that skip is what makes
## the density affordable. Non-fir gets the huge factor; fir was already the
## budget's heaviest species and stays modest.
##
## GPU PASS 2026-08-30 (Lemon: "turn the blown leaves hella down, they're
## deeply affecting the run speed"). The v1 dials grew SEVEN pads per seed card
## on every one of 420 trees — and every pad is an alpha-DISCARD quad, which
## kills early-Z, so each one costs a full fragment evaluation in the colour
## pass AND again in every directional shadow split. Fill rate, not triangles,
## was the wall. Cut to THREE pads per seed (~53% less leaf coverage) with the
## survivors grown slightly so the crown does not go gappy:
##   outer 5 -> 2 @ 0.72 -> 0.86   |   inner 2 -> 1 @ 1.55 -> 1.40
## To put the old look back, restore the numbers in the table below — nothing
## else in the densifier changed.
## CANOPY FIX 2026-09-01 (Lemon: "the one with leaves just has a green blob on
## top", "I don't want green blobs"). Two things made a crown read as one flat
## green mass, and they compounded:
##
##   1. The densifier THREW THE AUTHORED CARDS AWAY. TreeKit orients every leaf
##      card along its own twig with the species' gravity droop — that is the
##      whole reason `_cards()` exists — and `_densify_canopy` collected them
##      as seed points and then rebuilt the surface out of pads ONLY. So the
##      shipped canopy was pads and nothing else.
##   2. Every pad's normal was UP (tilt maxed at 0.34 rad = 19°). foliage's
##      light() is FOUR flat bands, so identical normals means every pad lands
##      in the SAME band — one colour across the whole crown — and from the
##      player's eye, at ground level, a horizontal quad is edge-on. A crown of
##      them is a green silhouette with no leaves in it. A blob.
##
## So: the authored cards go back in as the outer shell (they are what a player
## actually sees, and they get the wind), the pads drop to filler behind them,
## and the pads now tilt across a real range so their normals spread over the
## light bands. Fill rate is held roughly flat by taking one pad off every
## species — the card that replaces it was already being built and thrown away.
const CANOPY_DENSIFY := true
const KEEP_AUTHORED_CARDS := true   ## false = the old pads-only crown
const PAD_OUTER_N := {"maple": 1, "birch": 1, "oak": 1, "pine": 1, "fir": 0}
const PAD_INNER_N := {"maple": 1, "birch": 1, "oak": 1, "pine": 1, "fir": 1}
const PAD_OUTER_SIZE := 0.86     ## × the seed card's half-size
const PAD_INNER_SIZE := 1.40
const PAD_INNER_SHADE := 0.80    ## the inside of a crown shades itself
## How far off horizontal a pad may tilt, radians. This is a LOOK dial, not a
## cost one: it is what spreads the pads' normals across light()'s bands. At
## the old 0.34/0.16 every pad shaded identically.
const PAD_OUTER_TILT := 1.15     ## was 0.34 — outer pads stand up and lean over
const PAD_INNER_TILT := 0.55     ## was 0.16 — inner filler stays flatter
## NEXT LEVER, not taken yet: leaves cast real shadows, so the whole canopy is
## re-rasterised once per directional cascade — probably more fragment work
## than the colour pass. It cannot be switched off per-surface (wood and leaves
## share one MeshInstance), so the honest fix is a `shadows_disabled` variant of
## foliage.gdshader for the INNER pads only: they sit inside the crown and cast
## nothing anyone can see, and they are the biggest pads on the tree.
static var _canopy_cache := {}   ## "species#stage#mesh" -> {mesh, roles}

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
## Which authored TreeKit recipe this tree was built from. Derived from the
## tree's OWN seed, so a tree restored from a save is the same tree it was --
## get this wrong and every load reshuffles the forest.
var kit_variant := 0
var _dense := false                     ## the carve-ready trunk is in
var dead := false             ## a snag: deadwood bark, bare branches
var felled := false
var chops_left := 0
var notch_depth := 0.0        ## metres of wood taken out of the struck side
var notch_ang := 0.0          ## which way the wedge faces, tree-local radians
var notch_y := 0.0            ## THE LINE THE BLADE HIT, model metres. 0 = no
							  ## bite has landed yet, so NOTCH_Y stands in.
var scale_class := 1.0        ## NORMAL 1.0 / ELDER 1.7 / GREAT 3.5-4.5 (spec §4)

## What the last swing did, for the HUD: "limb", "limb_off", "trunk", "felled".
var last_result := ""

## --- what grows on it (2026-09-03) -------------------------------------------
## GrowthPatch children: moss, fungi, vines or lichen creeping up the low,
## shaded side of the trunk. Rolled from the tree's own seed the frame after
## _ready (deferred, so a restore() that arrives in the same frame -- World and
## GodEditor both add_child then restore -- wins and the roll is skipped).
## Saved inside save_dict, so a hand-placed tree's moss survives a new run
## through build_placements.json exactly as the tree does.
const GROWTH_CHANCE: Array[float] = [0.0, 0.45, 0.80, 0.95, 0.90]   ## per stage
## An old tree is already mossy when you meet it: starting coverage per stage,
## jittered. A sapling starts bare and earns it.
const GROWTH_START: Array[float] = [0.0, 0.08, 0.30, 0.55, 0.45]
var _growth_restored := false

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
	_shed_shadows()
	call_deferred("_seed_growth")


## --- shadows -----------------------------------------------------------------
## THE SINGLE BIGGEST FRAME COST IN THE GAME, measured in the live build on
## 2026-08-30: of 14,505 visible MeshInstances on screen, **14,418 were casting
## shadows** — 8,670 draw calls, 12 fps. A mature TreeV2 is ~113 separate mesh
## nodes (the trunk, every limb, and the densified canopy pads on each), and
## every one of them was being re-rendered into every cascade of the sun's
## shadow map. 360 trees is 40,000 shadow casters.
##
## The TRUNK keeps its shadow. That is the shadow you actually read — the one
## that says where the tree is standing and which way the light falls. The limbs
## and the canopy pads do not, and the distant impostor forest already casts
## none (Overworld._scatter_impostors), so this makes the near woods agree with
## the far ones instead of costing forty times what they do.
##
## What you give up is dappled shade under a canopy. Set SHADOW_LIMBS true to
## buy it back, and expect the framerate that came with it.
const SHADOW_LIMBS := false


func _shed_shadows() -> void:
	if SHADOW_LIMBS:
		return
	for n in _flatten(self):
		var mi := n as MeshInstance3D
		if mi == null or mi.name.begins_with("Trunk"):
			continue
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build() -> void:
	if USE_PSX:
		_build_psx()
		return
	if USE_KIT:
		_build_kit()
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
		_densify_canopy(mi)
		_apply_materials(mi, mats)
		_seed_bark_look(mi)
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


## ------------------------------------------------------------------- KIT ---

func _build_kit() -> void:
	## Trees v4. TreeKit hands back exactly what the GLB used to: a `Trunk`
	## mesh and one `Branch_NN_rXXX` per limb, wood on surface 0 and leaf cards
	## on surface 1. So everything below this function is the code that was
	## already here.
	var sd: int = tree_seed if tree_seed != 0 else hash(str(position))
	kit_variant = posmod(sd / 7, TreeKit.variants(species))
	_model = TreeKit.build(species, stage, kit_variant, dead)
	if _model == null:
		push_warning("TreeV2: TreeKit built nothing for %s/%d" % [species, stage])
		return
	_model.scale = Vector3.ONE * scale_class
	add_child(_model)

	var mats := materials_for(species, dead)
	for child in _model.get_children():
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		_densify_canopy(mi)
		_apply_materials(mi, mats)
		_seed_bark_look(mi)
		if mi.name.begins_with("Trunk"):
			_trunk = mi
		elif mi.name.begins_with("Branch"):
			var b := TreeBranch.new()
			b.setup(mi, self)
			add_child(b)
			_branches.append(b)

	_col = CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = maxf(trunk_radius(), 0.06)
	cyl.height = trunk_height()
	_col.shape = cyl
	_col.position.y = cyl.height * 0.5
	add_child(_col)
	## the kit path has to shed shadows too, or the whole 12-fps fix is bypassed
	## the moment USE_KIT is on
	_shed_shadows()


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

	## The inner-canopy variant: same species and season, NO vertex wind, a
	## shade darker — the static filler that pays for the dense crown.
	var leaf_in: ShaderMaterial = leaf.duplicate()
	leaf_in.set_shader_parameter("animated", 0.0)
	leaf_in.set_shader_parameter("shade", PAD_INNER_SHADE)

	_mat_cache[key] = [bark, leaf, leaf_in]
	return _mat_cache[key]


func _apply_materials(mi: MeshInstance3D, mats: Array) -> void:
	## Match by the glTF material NAME, not by surface index: a trunk with no
	## leaves on it has only one surface, so indices don't line up.
	if mi.mesh == null:
		return
	if mi.has_meta("leaf_roles"):
		## densified canopy: the rebuilt mesh knows its own surface roles
		var roles: Array = mi.get_meta("leaf_roles")
		for i in range(mi.mesh.get_surface_count()):
			var role := String(roles[i]) if i < roles.size() else "wood"
			var m: Material = mats[0]
			if role == "outer":
				m = mats[1]
			elif role == "inner":
				m = mats[2] if mats.size() > 2 else mats[1]
			mi.set_surface_override_material(i, m)
		return
	for i in range(mi.mesh.get_surface_count()):
		var src: Material = mi.mesh.surface_get_material(i)
		var nm := str(src.resource_name) if src != null else ""
		var is_leaf := nm.findn("leaf") >= 0 or nm.findn("foliage") >= 0
		mi.set_surface_override_material(i, mats[1] if is_leaf else mats[0])


## Lemon 2026-08-30: "I just want each tree to have its own unique bark/pattern."
##
## The forest shares meshes and materials on purpose -- that sharing is most of
## why 420 trees are affordable -- so the variation cannot live in either. It
## lives in INSTANCE UNIFORMS, which Godot patches per draw call: no material
## duplication, no extra draw calls, nothing added to the ~1,530-material
## problem the optimization audit already flagged.
##
## Four things move per tree, all off the tree's OWN seed so a save restores the
## same tree: where on the tiling bark sheet this trunk is cut from, whether that
## sheet is mirrored, how warm the bark is, and how light it is. The RELIEF
## varies too, but a step coarser -- it is baked into the shared mesh, so it is
## seeded per authored recipe rather than per tree (TreeKit._bark_offset).
##
## Needs Forward+ or Mobile; this project is Forward Plus.
func _seed_bark_look(mi: MeshInstance3D) -> void:
	var sd: int = tree_seed if tree_seed != 0 else hash(str(position))
	var a := float(posmod(sd, 977)) / 977.0
	var b := float(posmod(sd / 977, 811)) / 811.0
	var c := float(posmod(sd / 13, 599)) / 599.0
	var d := float(posmod(sd / 7, 421)) / 421.0
	mi.set_instance_shader_parameter("bark_var",
		Vector4(a * 4.0, b * 6.0, 1.0 if c > 0.5 else 0.0, d))
	mi.set_instance_shader_parameter("bark_value", 0.88 + a * 0.24)
	## the canopy varies with it -- one stem's leaves are not the next one's
	mi.set_instance_shader_parameter("leaf_var", Vector2(0.90 + b * 0.20, c))


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
	if USE_KIT:
		return TreeKit.base_radius(species, stage) * scale_class
	return TRUNK_R[stage] * scale_class


func model_radius() -> float:
	## MODEL metres -- what the notch is carved in. The two differ by the
	## model's scale, and mixing them up is how a sapling ends up with a wedge
	## wider than the tree.
	if USE_PSX and not _psx.is_empty():
		return maxf(float(_psx["radius"]) / maxf(float(_psx["scale"]), 0.001), 0.02)
	if USE_KIT:
		## The wood ACTUALLY THERE at the height the axe swings at, straight off
		## the taper curve the mesh was built from -- not the butt radius. A
		## table lookup here cuts a wedge that is the wrong share of the tree.
		## And "the height the axe swings at" means THE LINE THE BLADE ACTUALLY
		## HIT once one has: cut high on a taper and there is less wood to eat,
		## so the same number of bites still fells it.
		return TreeKit.radius_at(species, stage, notch_line())
	return TRUNK_R[stage]


func trunk_height() -> float:
	if USE_PSX and not _psx.is_empty():
		return maxf(float(_psx["height"]), 0.2)
	if USE_KIT:
		return TreeKit.height_of(species, stage) * scale_class
	return TRUNK_H[stage] * scale_class


func notch_line() -> float:
	## The height of the cut in MODEL metres -- where the blade went in, or the
	## height a chopper naturally swings at before anything has.
	##
	## NOTE the DIVIDE. The trunk mesh is built at unit size and the whole model
	## is then scaled by scale_class, so a world height converts to model space
	## by dividing. This used to MULTIPLY, which put an elder tree's wedge at
	## head height and a GREAT tree's twenty metres up the trunk.
	if notch_y > 0.0:
		return notch_y
	if USE_PSX and not _psx.is_empty():
		return float(_psx["chop_y"])
	return NOTCH_Y / maxf(scale_class, 0.001)


func notch_shape() -> Array:
	## [half-height, half-angle] of the wedge AS IT STANDS, model metres and
	## radians. One place owns the opening curve, because two things read it
	## now: the carve, and the stump's break face — and a stump wearing a
	## different wedge from the one the axe cut is worse than no wedge at all.
	var grow := clampf(notch_depth / maxf(model_radius() * BREAK_AT, 0.0001), 0.0, 1.0)
	var open := sqrt(grow)
	var full_h := NOTCH_H / maxf(scale_class, 0.001)
	if USE_PSX and not _psx.is_empty():
		full_h = NOTCH_H / maxf(float(_psx["scale"]), 0.001)
	return [maxf(full_h * lerpf(NOTCH_OPEN_MIN, 1.0, open), 0.01),
		NOTCH_ANG * lerpf(NOTCH_ANG_MIN, 1.0, open)]


func _aim_to_notch(aim: Vector3) -> bool:
	## PUT THE CUT WHERE THE EDGE WENT IN. `aim` is the world-space point the
	## chopper's crosshair ray actually found on this tree, so the line is his
	## line: chop low and the notch is at the roots, chop high and it is at your
	## shoulder, work the left flank and the wedge faces left.
	##
	## The first bite anchors both the height and the facing, and then THE SPOT
	## STAYS PUT: every swing after it lands in that same notch and only makes
	## it bigger. Returns false when a bite arrives blind and the caller should
	## fall back to the side the chopper is standing on.
	if aim == Vector3.INF or _trunk == null:
		return false
	var lp: Vector3 = _trunk.to_local(aim)
	var c := _ring_centre(lp.y)
	var rel := Vector3(lp.x - c.x, 0.0, lp.z - c.z)
	if rel.length_squared() < 0.000001:
		return false
	var ang := atan2(rel.z, rel.x)
	## Keep it on the trunk: never under the soil, never off the top of the wood.
	var top := maxf(trunk_height() / maxf(scale_class, 0.001) - 0.25, 0.15)
	var y := clampf(lp.y, 0.12, top)
	if notch_y <= 0.0:
		notch_y = y
		notch_ang = ang
	## ...and that is the last time it moves. Later bites land in the SAME cut
	## and only make it bigger — see _carve_notch, where the wedge opens up as
	## it deepens. Returning true either way keeps the caller off its
	## side-you're-standing-on fallback.
	return true


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
	## WHERE, and HOW BIG. The line is wherever the blade went in; the wedge
	## around it OPENS UP as the cut deepens, so the triangle you are watching
	## gets taller and wraps further round the trunk with every bite instead of
	## just getting a little deeper in a fixed-size slot.
	var ny := notch_line()
	var shape := notch_shape()
	var nh: float = shape[0]
	var nang: float = shape[1]
	var y_lo := ny - nh
	var y_hi := ny + nh

	## Per-vertex "how much wood came off here", 0..1. The bark shader reads it
	## and paints heartwood, so the cut face stops wearing bark.
	var cols := PackedColorArray()
	cols.resize(verts.size())
	var moved := PackedByteArray()
	moved.resize(verts.size())
	moved.fill(0)
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
		if da > nang:
			continue
		## A SHARP TRIANGLE, not a gouge. Down the trunk the depth falls off
		## LINEARLY from the strike line to nothing at the top and bottom of the
		## wedge -- a clean V with its point buried in the wood. The old curve
		## held full depth across the middle 45% of the opening, which is a
		## flat-bottomed slot and reads as a dent pressed into the bark.
		var fy: float = 1.0 - absf(v.y - ny) / nh
		if fy <= 0.0:
			continue
		## ACROSS the trunk it stays a FACE: full depth over the middle of the
		## arc, tapering only out at the corners where the wedge runs out of
		## wood. A V in both axes at once would be a cone, not an axe cut.
		var fa: float = clampf((1.0 - da / nang) / 0.35, 0.0, 1.0)
		var cut: float = notch_depth * fy * fa
		var nr: float = maxf(r - cut, 0.012)
		verts[i] = Vector3(c.x + rel.x / r * nr, v.y, c.z + rel.z / r * nr)
		## Anything the axe actually moved is exposed wood -- ALL the way. No
		## "half-bark" at the wedge's edges (Lemon 2026-09-14: "each part of the
		## tree either is untouched or hit ... no more gradients between bark
		## and not bark"); the shader steps on this, it does not blend.
		if cut > 0.004:
			cols[i] = Color(0, 0, 0, 1)
			moved[i] = 1

	var arrays := _trunk_arrays.duplicate()
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	## The cut is LIT as a cut: every vertex the axe moved gets its normal
	## rebuilt from the faces it now sits on, instead of keeping the round
	## trunk's outward normal and shading the notch as if it were still bark.
	## Godot's front faces are clockwise, so a face's normal is -(b-a)x(c-a).
	if _trunk_arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
		var nrm := PackedVector3Array(_trunk_arrays[Mesh.ARRAY_NORMAL])
		var idx: PackedInt32Array = _trunk_arrays[Mesh.ARRAY_INDEX]
		if nrm.size() == verts.size() and not idx.is_empty():
			var acc := PackedVector3Array()
			acc.resize(verts.size())
			acc.fill(Vector3.ZERO)
			var t := 0
			while t + 2 < idx.size():
				var ia := idx[t]
				var ib := idx[t + 1]
				var ic := idx[t + 2]
				t += 3
				if moved[ia] == 0 and moved[ib] == 0 and moved[ic] == 0:
					continue
				var fn := -(verts[ib] - verts[ia]).cross(verts[ic] - verts[ia])
				acc[ia] = acc[ia] + fn
				acc[ib] = acc[ib] + fn
				acc[ic] = acc[ic] + fn
			for i in range(verts.size()):
				if moved[i] == 1 and acc[i].length_squared() > 1e-12:
					nrm[i] = acc[i].normalized()
			arrays[Mesh.ARRAY_NORMAL] = nrm
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	## keep every other surface (sapling twigs) exactly as it was
	for s in range(1, _trunk.mesh.get_surface_count()):
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _trunk.mesh.surface_get_arrays(s))
	_trunk.mesh = am
	_seed_bark_look(_trunk)   ## a carve rebuilds the mesh; keep this tree's bark
	var mats: Array = PSXNature.materials(String(_psx["atlas"]), region, dead) \
		if (USE_PSX and not _psx.is_empty()) else materials_for(species, dead)
	_trunk.set_surface_override_material(0, mats[0])
	var lroles: Array = _trunk.get_meta("leaf_roles") if _trunk.has_meta("leaf_roles") else []
	for s in range(1, am.get_surface_count()):
		var role := String(lroles[s]) if s < lroles.size() else "outer"
		_trunk.set_surface_override_material(s,
			mats[2] if role == "inner" and mats.size() > 2 else mats[1])


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


## The first limb a sight-line runs through, within `reach` of `from` --
## for a blade that cuts what it is pointed at rather than what it is near.
## Returns [TreeBranch, world point] or [] when the ray crosses no limb.
## A limb's box is its mesh (leaves included), so a blade aimed into the
## foliage of a limb still finds the limb: generous on purpose.
func branch_on_ray(from: Vector3, dir: Vector3, reach: float) -> Array:
	var best: TreeBranch = null
	var best_t := INF
	var best_p := Vector3.INF
	for b in _branches:
		var tb := b as TreeBranch
		if not is_instance_valid(tb) or tb.gone or tb.mesh == null \
				or not is_instance_valid(tb.mesh) or tb.mesh.mesh == null:
			continue
		var box: AABB = tb.mesh.global_transform * tb.mesh.mesh.get_aabb()
		var hit = box.intersects_ray(from, dir)
		if hit == null:
			continue
		var t: float = (hit as Vector3).distance_to(from)
		if t <= reach and t < best_t:
			best_t = t
			best = tb
			best_p = hit as Vector3
	return [best, best_p] if best != null else []


func chop_hit(toward_chopper: Vector3, aim := Vector3.INF) -> bool:
	## One bite. Returns TRUE only on the swing that fells the tree.
	if felled:
		return false

	## Aiming straight at a limb takes the limb — worth doing for the sticks,
	## never required.
	var limb := nearest_branch(global_position, aim)
	if limb != null:
		last_result = "limb_off" if limb.take_hit(1) else "limb"
		if last_result == "limb_off":
			WoodAudio.limb(self, aim if aim != Vector3.INF else global_position + Vector3.UP * 2.0)
		return false

	## Otherwise the wedge goes into the trunk ON THE LINE THE BLADE HIT.
	## _aim_to_notch owns that; the side you're standing on is only the
	## fallback for a bite that arrived without an aim point.
	_cache_trunk()
	if not _aim_to_notch(aim):
		var local := (global_transform.basis.inverse() * toward_chopper).normalized()
		notch_ang = atan2(local.z, local.x)
		if notch_y <= 0.0:
			notch_y = notch_line()
	chops_left -= 1
	## notch_depth lives in MODEL metres because that is where the vertices are,
	## and it ACCELERATES: bite one leaves a mark, and every bite after takes
	## more wood than the one before, so the wedge tears open toward the swing
	## that drops the tree instead of creeping in equal slices.
	var total := float(maxi(TRUNK_CHOPS[stage], 1))
	var t := clampf((total - float(chops_left)) / total, 0.0, 1.0)
	notch_depth = model_radius() * BREAK_AT * (0.55 * t + 0.45 * t * t)
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
	##
	## AND IT BREAKS ON THE NOTCH. The tree splits at the line the axe has been
	## working: everything below it stays rooted as a stump exactly as tall as
	## the cut was high, everything above it is what goes over, and the break
	## face is the wedge. Before this the WHOLE tree lifted off — stump wood and
	## all — and a knee-high stump was spawned underneath it, which is why
	## felling read as the trunk teleporting off its own base.
	felled = true
	remove_from_group("trees")
	remove_from_group("choppable")

	var world := get_parent()
	## Throw the canopy before the model changes hands, or the burst spawns
	## parented to a body that is already rolling.
	_shed_leaves()

	var h := trunk_height()
	## The break line, WORLD metres above the foot. Clamped so a bite at the
	## roots still leaves something to stand on and one up in the crown still
	## leaves something worth felling.
	var cut := clampf(notch_line() * scale_class, 0.22, maxf(h - 0.6, 0.3))
	## The falling piece is as thick as the tree was AT THE BREAK, not at the
	## butt — a 20 m pine snapped at the shoulder is not a 0.58 m log.
	var cut_r := trunk_radius()
	if USE_KIT:
		cut_r = maxf(TreeKit.radius_at(species, stage,
			cut / maxf(scale_class, 0.001)) * scale_class, 0.05)

	var trunk := FallenTrunk.make(
		global_position + Vector3.UP * cut,
		dir.normalized(),
		h - cut,
		cut_r,
		species,
		LOG_YIELD[stage])
	## What stays behind. FallenTrunk drops this much wood out of the geometry
	## it adopts, so the two halves do not both own the same metre of trunk.
	trunk.clip_below = cut
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
		## As tall as the cut was high, wearing the bottom half of the wedge the
		## axe cut, and torn off the rest of the way — see TreeStump._build_wood.
		var stump := TreeStump.make(global_position, trunk_radius(), species, cut)
		stump.rotation.y = rotation.y      ## notch_ang is TREE-local; share the frame
		var ns := notch_shape()
		stump.notch_ang = notch_ang
		stump.notch_h = float(ns[0]) * scale_class      ## model -> world metres
		stump.notch_arc = float(ns[1])
		stump.notch_depth = notch_depth * scale_class
		## Its own rip, and the same rip every time this tree is loaded.
		stump.tear_seed = tree_seed if tree_seed != 0 else hash(str(global_position))
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
		"notch_y": notch_y,
		"branches": _branch_state(),
		"growth": growth_state(),
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
	notch_y = float(d.get("notch_y", 0.0))
	var st: Array = d.get("branches", [])
	for i in range(mini(st.size(), _branches.size())):
		if int(st[i]) == 1:
			(_branches[i] as TreeBranch).remove_silently()
	if notch_depth > 0.0:
		_carve_notch()      ## a half-chopped tree comes back half-chopped
	if d.has("growth"):
		_growth_restored = true
		for gd in d["growth"]:
			if gd is Dictionary:
				var g := GrowthPatch.from_dict(gd as Dictionary)
				_add_growth(g)
				g.catch_up()    ## the days the save slept through


## ---------------------------------------------------------------- growth ---

func growth_state() -> Array:
	var out: Array = []
	for g in GrowthPatch.patches_under(self):
		out.append((g as GrowthPatch).to_dict())
	return out


func growth_patches() -> Array:
	return GrowthPatch.patches_under(self)


func _add_growth(g: GrowthPatch) -> void:
	## The patch probes the trunk's REAL mesh (bark relief and all), not the
	## cylinder collider -- surface 0 is the wood; leaf cards, if any, are 1.
	if _trunk != null:
		g.probe_meshes = [_trunk]
		g.probe_surface = 0
	add_child(g)


func _seed_growth() -> void:
	## Deferred from _ready. A restore that landed first has already put the
	## saved patches on; a felled tree, or one that built nothing, grows nothing.
	if _growth_restored or felled or _trunk == null or not is_inside_tree():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = (tree_seed if tree_seed != 0 else hash(str(position))) * 17 + 3
	var st := clampi(stage, 0, GROWTH_CHANCE.size() - 1)
	if rng.randf() >= GROWTH_CHANCE[st]:
		return
	var n := 1
	if st >= 3 and rng.randf() < 0.5:
		n += 1
	if dead and rng.randf() < 0.6:
		n += 1
	for i in range(n):
		add_growth_patch(_roll_growth_type(rng), rng.randi(), i)


func _roll_growth_type(rng: RandomNumberGenerator) -> String:
	## What a tree like this grows. Dead wood rots (fungi); birch bark takes
	## lichen; an ancient trunk can carry a vine; everything else is mostly moss.
	var r := rng.randf()
	if dead:
		return "fungi" if r < 0.6 else ("moss" if r < 0.85 else "lichen")
	if species == "birch" and r < 0.35:
		return "lichen"
	if stage >= 3 and r < 0.30:
		return "vine"
	if r < 0.72:
		return "moss"
	return "lichen" if r < 0.88 else "fungi"


## Put a patch on this trunk. `slot` spreads a second or third patch round the
## trunk instead of stacking them. Also the editor's hook (a future Trees-tool
## chip): add_growth_patch("fungi", randi()).
func add_growth_patch(type_id: String, seed_v: int, slot := 0) -> GrowthPatch:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	## the shaded side: world north (-Z, as bark.gdshader has it) in tree space
	var north_local := Vector3(0, 0, -1).rotated(Vector3.UP, -rotation.y)
	var ang := atan2(north_local.x, north_local.z) + rng.randf_range(-0.7, 0.7) + float(slot) * 1.4
	var r := maxf(trunk_radius(), 0.05)
	var h := trunk_height()
	## low on the trunk: the heart sits between the roots and chest height
	var y := rng.randf_range(0.12, clampf(h * 0.30, 0.3, 1.25))
	var span_up := clampf(0.30 + r * 0.9, 0.28, 0.95)
	var span_round := clampf(0.70 + r * 0.35, 0.6, 1.15)
	var area := (2.0 * span_up) * (2.0 * span_round * r)
	var g := GrowthPatch.make(type_id, "", "", seed_v)
	g.anchor_cylinder(y, ang, span_up, span_round, r * 4.0 + 1.0, area)
	var world_dir := Vector3(sin(ang), 0.0, cos(ang)).rotated(Vector3.UP, rotation.y)
	g.shade = GrowthPatch.shade_for(world_dir)
	var st := clampi(stage, 0, GROWTH_START.size() - 1)
	g.growth = clampf(GROWTH_START[st] * rng.randf_range(0.6, 1.25), 0.0, 1.0)
	_add_growth(g)
	return g


## ---------------------------------------------------- canopy densifier ---
## Lemon 2026-08-29: "make the leaves on trees more dense, especially the
## non-fir trees by a huge factor, with the outer couple layers actually
## animated, and the inner layers swaying with the branch, so it runs better.
## I also want the leaves ... positioned horizontally adjacent, so they look
## natural with the flat top part pointed at the sun."

class PadBuf:
	## Mutable mesh-array builder. Deliberately a CLASS and not a Dictionary of
	## packed arrays — Packed* arrays are value types (the Grass v2 trap), so
	## appending to one stored in a Dictionary appends to a copy and is lost.
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var t := PackedFloat32Array()
	var uv := PackedVector2Array()
	var i := PackedInt32Array()


func _densify_canopy(mi: MeshInstance3D) -> void:
	## The GLB's baked leaf cards become SEED POINTS: each grows a cluster of
	## flat horizontal pads — small animated ones ringing the outside, bigger
	## darker STATIC ones filling the inside. Rebuilt once per (species, stage,
	## mesh name) and cached, so 420 trees share a handful of meshes and the
	## work happens on the first tree of each kind only.
	if not CANOPY_DENSIFY or mi == null or mi.mesh == null:
		return
	## The variant belongs in the key: two recipes both have a mesh called
	## `Trunk`, so without it the second one would be handed the first one's
	## canopy and every tree of that species would wear the same crown.
	var key := "%s#%d#%d#%s" % [species, stage, kit_variant, mi.name]
	if _canopy_cache.has(key):
		var e: Dictionary = _canopy_cache[key]
		mi.mesh = e["mesh"]
		mi.set_meta("leaf_roles", e["roles"])
		return
	var src: Mesh = mi.mesh
	var wood: Array = []
	var cards: Array = []
	var authored: Array = []     ## the leaf surfaces exactly as TreeKit made them
	for i in range(src.get_surface_count()):
		var m: Material = src.surface_get_material(i)
		var nm := str(m.resource_name) if m != null else ""
		if nm.findn("leaf") >= 0 or nm.findn("foliage") >= 0:
			var la: Array = src.surface_get_arrays(i)
			_collect_cards(la, cards)
			authored.append(la)
		else:
			wood.append(src.surface_get_arrays(i))
	if cards.is_empty():
		return

	## pads radiate outward from the middle of THIS mesh's own canopy — for a
	## branch mesh that is the branch's leaf mass, so its pads fan out with it
	var centroid := Vector3.ZERO
	for cd in cards:
		centroid += cd["c"] as Vector3
	centroid /= float(cards.size())

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)      ## same model -> same canopy, every launch
	var k_out: int = PAD_OUTER_N.get(species, 4)
	var k_in: int = PAD_INNER_N.get(species, 1)

	var pads_out := PadBuf.new()
	var pads_in := PadBuf.new()
	for cd in cards:
		var c: Vector3 = cd["c"]
		var s: float = maxf(float(cd["s"]), 0.05)
		var out_h: Vector3 = c - centroid
		out_h.y = 0.0
		if out_h.length() > 0.05:
			out_h = out_h.normalized()
		else:
			out_h = Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1) + 0.001).normalized()
		for k in range(k_out):
			var ang := TAU * (float(k) + rng.randf()) / float(k_out)
			var rad := s * rng.randf_range(0.15, 1.35)
			var pos := c + Vector3(cos(ang), 0, sin(ang)) * rad \
				+ Vector3(0, rng.randf_range(-0.25, 0.35) * s, 0)
			_emit_pad(pads_out, pos, out_h, s * PAD_OUTER_SIZE * rng.randf_range(0.82, 1.18),
				PAD_OUTER_TILT, rng, cd)
		for _k in range(k_in):
			var pos2 := c - out_h * s * rng.randf_range(0.2, 0.7) \
				+ Vector3(0, rng.randf_range(-0.5, 0.05) * s, 0)
			_emit_pad(pads_in, pos2, out_h, s * PAD_INNER_SIZE * rng.randf_range(0.85, 1.15),
				PAD_INNER_TILT, rng, cd)

	var am := ArrayMesh.new()
	var roles: Array = []
	for wa in wood:
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, wa)
		roles.append("wood")
	## the inner filler first, then the authored cards and the outer pads on top
	var fin_in: Array = _pad_finish(pads_in)
	var fin_out: Array = _pad_finish(pads_out)
	if not (fin_in[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, fin_in)
		roles.append("inner")
	## THE CROWN A PLAYER ACTUALLY SEES: TreeKit's own cards, aimed along their
	## twigs with the species droop. Without these the canopy is flat plates.
	if KEEP_AUTHORED_CARDS:
		for la in authored:
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, la)
			roles.append("outer")
	if not (fin_out[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, fin_out)
		roles.append("outer")
	mi.mesh = am
	mi.set_meta("leaf_roles", roles)
	_canopy_cache[key] = {"mesh": am, "roles": roles}


static func _collect_cards(arrays: Array, out: Array) -> void:
	## Walk the leaf surface's triangles in 6-index windows; each window over 4
	## unique positions is one card plane. The two crossed planes of a card
	## share their exact centre, so a coarse spatial bucket collapses them into
	## ONE seed. Each seed keeps its atlas cell (uv rect) and its half-size.
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if verts.is_empty() or uvs.is_empty():
		return
	var n := idx.size() if idx.size() > 0 else verts.size()
	var seen := {}
	var w := 0
	while w + 5 < n:
		var uniq := {}
		for k in range(6):
			var vi: int = idx[w + k] if idx.size() > 0 else w + k
			uniq[Vector3i((verts[vi] * 2048.0).round())] = vi
		if uniq.size() == 4:
			var c := Vector3.ZERO
			for vi in uniq.values():
				c += verts[vi]
			c /= 4.0
			var qk := Vector3i((c * 33.0).round())
			if not seen.has(qk):
				seen[qk] = true
				var mx := 0.0
				var u0 := Vector2(1e9, 1e9)
				var u1 := Vector2(-1e9, -1e9)
				for vi in uniq.values():
					mx = maxf(mx, (verts[vi] - c).length())
					var tuv := uvs[vi]
					u0 = Vector2(minf(u0.x, tuv.x), minf(u0.y, tuv.y))
					u1 = Vector2(maxf(u1.x, tuv.x), maxf(u1.y, tuv.y))
				out.append({"c": c, "s": mx * 0.707, "uv0": u0, "uv1": u1})
		w += 6


static func _emit_pad(p: PadBuf, c: Vector3, out_h: Vector3, hs: float,
		tilt: float, rng: RandomNumberGenerator, card: Dictionary) -> void:
	## One flat quad lying (nearly) horizontal — the flat top points at the
	## sun. The atlas cell's stem edge faces the trunk and the spray runs
	## outward; a small random tilt keeps side-on views from going paper-thin.
	## Stem = uv MAX y (the exporter authored stem-at-bottom in Blender uv
	## space and the glTF flip put it at the top of the rect).
	var vax := out_h.rotated(Vector3.UP, rng.randf_range(-0.7, 0.7))
	var taxis := Vector3(rng.randf_range(-1, 1), 0.001, rng.randf_range(-1, 1)).normalized()
	var rot := Basis(taxis, rng.randf_range(tilt * 0.25, tilt))
	var nrm: Vector3 = rot * Vector3.UP
	vax = (rot * vax).normalized()
	var uax := vax.cross(nrm).normalized()
	vax = nrm.cross(uax).normalized()
	var base := p.v.size()
	var u0: Vector2 = card["uv0"]
	var u1: Vector2 = card["uv1"]
	var corners := [c - uax * hs - vax * hs, c + uax * hs - vax * hs,
		c + uax * hs + vax * hs, c - uax * hs + vax * hs]
	var cuv := [Vector2(u0.x, u1.y), Vector2(u1.x, u1.y),
		Vector2(u1.x, u0.y), Vector2(u0.x, u0.y)]
	for k in range(4):
		p.v.append(corners[k])
		p.n.append(nrm)
		p.t.append_array(PackedFloat32Array([uax.x, uax.y, uax.z, 1.0]))
		p.uv.append(cuv[k])
	p.i.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))


static func _pad_finish(p: PadBuf) -> Array:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = p.v
	arr[Mesh.ARRAY_NORMAL] = p.n
	arr[Mesh.ARRAY_TANGENT] = p.t
	arr[Mesh.ARRAY_TEX_UV] = p.uv
	arr[Mesh.ARRAY_INDEX] = p.i
	return arr
