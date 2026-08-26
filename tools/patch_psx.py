#!/usr/bin/env python3
"""
tools/patch_psx.py -- point the tree systems at the PSX Nature & Biomes pack.

Re-runnable: every edit is an exact-match replacement that asserts loudly if
the source has moved, and each touched file is copied to <name>.bak_prepsx the
first time. Nothing procedural is deleted -- TreeV2.USE_PSX = false puts the
generated trees back.

    python3 tools/patch_psx.py [--repo .]
"""
import argparse, os, shutil, sys

_restored = set()

def load(p):
    # ALWAYS patch from pristine, but only ONCE per file per run. The first run
    # copies the file to .bak_prepsx; every run after that reads THAT, so
    # re-running can never double-apply an edit whose replacement contains its
    # own anchor. A file opened twice in one run (World.gd is) must NOT be
    # rolled back the second time -- that quietly threw the first section's
    # edits away.
    bak = p + ".bak_prepsx"
    if os.path.exists(bak) and p not in _restored:
        shutil.copy2(bak, p)
    _restored.add(p)
    with open(p, encoding="utf-8") as f: return f.read()

def save(p, s):
    bak = p + ".bak_prepsx"
    if not os.path.exists(bak): shutil.copy2(p, bak)
    with open(p, "w", encoding="utf-8") as f: f.write(s)

def sub(s, old, new, what):
    if s.count(old) != 1:
        print(f"  ! {what}: expected 1 match, found {s.count(old)}"); sys.exit(2)
    print(f"  + {what}")
    return s.replace(old, new)

ap = argparse.ArgumentParser()
ap.add_argument("--repo", default=".")
A = ap.parse_args()
R = os.path.abspath(A.repo)

# ===========================================================================
print("TreeV2.gd")
p = os.path.join(R, "scripts/TreeV2.gd"); s = load(p)

s = sub(s, 'const GLB_PATH := "res://assets/trees/glb/%s_%d_%s.glb"',
'''## ART SOURCE. true = the PSX Nature & Biomes pack (assets/psx_nature),
## false = the procedural trees tools/treegen2.py bakes into assets/trees/glb.
## Everything below -- notch carving, felling physics, bucking, snags,
## save/load -- runs identically either way. The pack changed the models, not
## the game.
const USE_PSX := true

const GLB_PATH := "res://assets/trees/glb/%s_%d_%s.glb"''', "USE_PSX flag")

s = sub(s, '''var tree_seed := 0
var dead := false''', '''var tree_seed := 0
## Which of the six painted biomes this tree runs through the year.
## PSXNature.REGIONS holds the four-atlas recipe per region.
var region := "temperate"
## What PSXNature.pick_tree handed back: asset, scale, real height, the chop
## height in MODEL space and the trunk radius measured there.
var _psx: Dictionary = {}
var _psx_leaf: ShaderMaterial = null    ## this tree's own copy, once it sheds
var _dense := false                     ## the carve-ready trunk is in
var dead := false''', "region + psx vars")

# ---- make() ---------------------------------------------------------------
s = sub(s, '''	t.dead = t.stage == 4 or (t.stage >= 2 and rng.randf() < SNAG_CHANCE)
	return t''', '''	t.dead = t.stage == 4 or (t.stage >= 2 and rng.randf() < SNAG_CHANCE)
	if region_id != "":
		t.region = region_id
	return t''', "make(): region")
s = sub(s, 'static func make(rng: RandomNumberGenerator, species_id := "", stage_i := -1) -> TreeV2:',
        'static func make(rng: RandomNumberGenerator, species_id := "", stage_i := -1,\n\t\tregion_id := "") -> TreeV2:', "make(): signature")

# ---- _build() -------------------------------------------------------------
s = sub(s, '''func _build() -> void:
	var path := GLB_PATH % [species, stage, STAGE_NAMES[stage]]''',
'''func _build() -> void:
	if USE_PSX:
		_build_psx()
		return
	var path := GLB_PATH % [species, stage, STAGE_NAMES[stage]]''', "_build(): PSX branch")

s = sub(s, '''## -------------------------------------------------------------- materials ---

static func materials_for''',
'''## ------------------------------------------------------------------- PSX ---

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

static func materials_for''', "_build_psx + dense trunk + shed")

# ---- material matching ----------------------------------------------------
s = sub(s, '''		var is_leaf := src != null and str(src.resource_name).findn("leaf") >= 0''',
'''		var nm := str(src.resource_name) if src != null else ""
		var is_leaf := nm.findn("leaf") >= 0 or nm.findn("foliage") >= 0''',
        "_apply_materials: match foliage too")

# ---- radii ----------------------------------------------------------------
s = sub(s, '''func trunk_radius() -> float:
	return TRUNK_R[stage] * scale_class''',
'''func trunk_radius() -> float:
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
	return TRUNK_H[stage] * scale_class''', "trunk_radius / model_radius / trunk_height")

# ---- the notch, in model space -------------------------------------------
s = sub(s, '''	var src: PackedVector3Array = _trunk_arrays[Mesh.ARRAY_VERTEX]
	var verts := PackedVector3Array(src)
	var y_lo := (NOTCH_Y - NOTCH_H) * scale_class
	var y_hi := (NOTCH_Y + NOTCH_H) * scale_class
	var ny := NOTCH_Y * scale_class
	var nh := NOTCH_H * scale_class''',
'''	var src: PackedVector3Array = _trunk_arrays[Mesh.ARRAY_VERTEX]
	var verts := PackedVector3Array(src)
	## The wedge is authored in world metres but carved in the trunk mesh's own
	## space, so both the height and the half-height divide by the model scale.
	var ny := NOTCH_Y * scale_class
	var nh := NOTCH_H * scale_class
	if USE_PSX and not _psx.is_empty():
		ny = float(_psx["chop_y"])
		nh = NOTCH_H / maxf(float(_psx["scale"]), 0.001)
	var y_lo := ny - nh
	var y_hi := ny + nh''', "_carve_notch: model-space wedge")

s = sub(s, '''	_trunk.mesh = am
	var mats := materials_for(species, dead)''',
'''	_trunk.mesh = am
	var mats: Array = PSXNature.materials(String(_psx["atlas"]), region, dead) \\
		if (USE_PSX and not _psx.is_empty()) else materials_for(species, dead)''',
        "_carve_notch: PSX materials")

s = sub(s, '''	if not _spine.is_empty():
		return
	if _trunk == null''', '''	if not _spine.is_empty():
		return
	_swap_dense_trunk()
	if _trunk == null''', "_cache_trunk: pull the dense trunk in first")

s = sub(s, '''	var top := SPINE_TOP * scale_class''',
'''	var top := SPINE_TOP * scale_class
	if USE_PSX and not _psx.is_empty():
		top = maxf(SPINE_TOP, float(_psx["chop_y"]) * 1.8)''', "_cache_trunk: model-space top")

# ---- chop_hit -------------------------------------------------------------
s = sub(s, '''	chops_left -= 1
	var r := trunk_radius()
	notch_depth = minf(notch_depth + r * (BREAK_AT / float(maxi(TRUNK_CHOPS[stage], 1))),
		r * BREAK_AT)''',
'''	chops_left -= 1
	## notch_depth lives in MODEL metres because that is where the vertices are.
	var r := model_radius()
	notch_depth = minf(notch_depth + r * (BREAK_AT / float(maxi(TRUNK_CHOPS[stage], 1))),
		r * BREAK_AT)''', "chop_hit: model-space depth")

s = sub(s, '''	notch_depth = trunk_radius() * BREAK_AT
	chops_left = 0''', '''	notch_depth = model_radius() * BREAK_AT
	chops_left = 0''', "blast_fell: model-space depth")

# ---- _fell ----------------------------------------------------------------
s = sub(s, '''	var world := get_parent()
	var trunk := FallenTrunk.make(
		global_position,
		dir.normalized(),
		TRUNK_H[stage] * scale_class,
		trunk_radius(),
		species,
		LOG_YIELD[stage])''',
'''	var world := get_parent()
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
		trunk.leaf_mat = _psx_leaf''', "_fell: shed + PSX trunk size")

s = sub(s, '''		"scale": scale_class,
		"pos":''', '''		"scale": scale_class,
		"region": region,
		"pos":''', "save_dict: region")

s = sub(s, '''	t.scale_class = float(d.get("scale", 1.0))
	var p: Array''', '''	t.scale_class = float(d.get("scale", 1.0))
	t.region = str(d.get("region", "temperate"))
	var p: Array''', "from_dict: region")

save(p, s)

# ===========================================================================
print("FallenTrunk.gd")
p = os.path.join(R, "scripts/FallenTrunk.gd"); s = load(p)

s = sub(s, '''var _limbs: Array = []             ## [{mesh, shape, centre}] — props that can snap''',
'''## How many sticks the branches give up when it lands. A PSX tree is one piece
## of wood with no separable limbs, so the sticks come from the crash rather
## than from limbing it beforehand.
var sticks := 0
## The felled tree's OWN leaf material, so the canopy can keep shedding while
## the trunk is in the air.
var leaf_mat: ShaderMaterial = null
var _shed := 0.0
var _limbs: Array = []             ## [{mesh, shape, centre}] — props that can snap''', "sticks + leaf_mat")

s = sub(s, '''		_limbs.append({"mesh": mi, "shape": cs, "centre": cs.position})''',
'''		_limbs.append({"mesh": mi, "shape": cs, "centre": cs.position})

	if _limbs.is_empty():
		_prop_on_its_own_wood(base)


func _prop_on_its_own_wood(base: float) -> void:
	## A PSX trunk carries its limbs in the same mesh, so there is nothing to
	## walk. Two small props along its length do the same job the branch
	## colliders do: hold the log a hand's width off the dirt so it reads as
	## timber lying in a wood, not as a pipe painted onto the ground.
	for f in [0.42, 0.74]:
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = clampf(trunk_r * 1.35, 0.12, 0.40)
		cs.shape = sp
		cs.position = Vector3(0, base + trunk_len * f, trunk_r * 0.9)
		add_child(cs)''', "fallback props for one-piece trunks")

s = sub(s, '''		if world_perp.y > UNDER_LIMB:
			continue                                ## sticking up or out — it lives
		_snap_limb(L)''',
'''		if world_perp.y > UNDER_LIMB:
			continue                                ## sticking up or out — it lives
		_snap_limb(L)
	if _limbs.is_empty() and sticks > 0:
		_drop_sticks(sticks)
		sticks = 0


func _drop_sticks(n: int) -> void:
	## Branches caught between the trunk and the ground snap on impact. With a
	## one-piece trunk there is nothing to hide, so they just come off it.
	var world := get_parent()
	if world == null:
		return
	var axis := global_transform.basis.y.normalized()
	for i in range(n):
		var f := (float(i) + 0.6) / float(n)
		var at := global_position + axis * (trunk_len * (f - 0.5))
		var s := DroppedItem.make({"name": "Stick", "weight": 0.3, "count": 1, "slot": ""})
		world.add_child(s)
		s.global_position = at + Vector3(randf_range(-0.5, 0.5), 0.3, randf_range(-0.5, 0.5))
		s.velocity = Vector3(randf_range(-1.6, 1.6), randf_range(0.9, 2.0), randf_range(-1.6, 1.6))''',
        "sticks on crash")

s = sub(s, '''	_age += delta
	if _age < MIN_FALL_TIME:
		return''',
'''	_age += delta
	## The canopy keeps letting go all the way down, not in one pop at the top.
	if leaf_mat != null and _shed < 1.0:
		_shed = minf(_shed + delta * 0.85, 1.0)
		leaf_mat.set_shader_parameter("shed", _shed)
	if _age < MIN_FALL_TIME:
		return''', "shed ramp during the fall")

save(p, s)

# ===========================================================================
print("CaveRegion.gd")
p = os.path.join(R, "scripts/CaveRegion.gd"); s = load(p)

s = sub(s, "var _rock_mat: StandardMaterial3D",
"""## THE FLOOR. true = the PSX pack's understory + textured ground,
## false = the procedural blades in Grass.gd, which stay on disk untouched.
const USE_PSX_UNDERSTORY := true
## Which of the six painted biomes the surface runs. PSXNature.REGIONS.
const PSX_REGION := "temperate"

var _rock_mat: Material""", "CaveRegion: understory flag")

s = sub(s, """	_rock_mat = StandardMaterial3D.new()
	_rock_mat.vertex_color_use_as_albedo = true
	_rock_mat.roughness = 1.0""",
"""	_rock_mat = _psx_ground_material() if USE_PSX_UNDERSTORY else null
	if _rock_mat == null:
		var std := StandardMaterial3D.new()
		std.vertex_color_use_as_albedo = true
		std.roughness = 1.0
		_rock_mat = std""", "CaveRegion: PSX ground material")

s = sub(s, """	_rock_mat.cull_mode = BaseMaterial3D.CULL_DISABLED""",
"""	if _rock_mat is BaseMaterial3D:
		(_rock_mat as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	## (the PSX ground shader declares cull_disabled in its own render_mode)""",
    "CaveRegion: cull only on the standard material")

s = sub(s, """var _grass: GrassSystem          ## the living meadow on the surface skin""",
"""## GrassSystem or Understory -- both answer to the same names (group
## "grass_system", is_tall_at / cut_at / rebuild_area / save_state).
var _grass: Node3D               ## what grows on the surface skin""",
    "CaveRegion: untyped floor")

s = sub(s, """	## The meadow: instanced grass sampled off the freshly-built surface.
	_grass = GrassSystem.new()
	add_child(_grass)
	_grass.setup(field, cave_seed)""",
"""	## What grows on the surface skin, sampled off the freshly-built floor.
	if USE_PSX_UNDERSTORY:
		var u := Understory.new()
		_grass = u
		add_child(u)
		u.setup(field, cave_seed, PSX_REGION)
	else:
		var g := GrassSystem.new()
		_grass = g
		add_child(g)
		g.setup(field, cave_seed)""", "CaveRegion: build the understory")

s = sub(s, """func grass() -> GrassSystem:
	return _grass""",
"""func grass() -> Node:
	## Deliberately untyped: this is a GrassSystem or an Understory depending on
	## USE_PSX_UNDERSTORY, and every caller reaches for it by method name.
	return _grass


func _psx_ground_material() -> ShaderMaterial:
	var sh := load("res://shaders/psx_ground.gdshader")
	if sh == null:
		return null
	var stops: Array = PSXNature.region_atlases(PSX_REGION)
	var warm := String(stops[1])          ## the region's summer biome
	var cold := String(stops[3])          ## and its winter one
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("floor_warm", _ground_tex(warm, "ForestFloor"))
	m.set_shader_parameter("floor_cold", _ground_tex(cold, "ForestFloor"))
	m.set_shader_parameter("soil_tex", _ground_tex(warm, "Soil"))
	m.set_shader_parameter("rock_tex", _ground_tex(warm, "RockGround"))
	return m


func _ground_tex(biome: String, sheet: String) -> Texture2D:
	var path := "res://assets/psx_nature/textures/%s/T_%s_%s_BaseColor.png" % [biome, biome, sheet]
	return load(path) if ResourceLoader.exists(path) else null""",
    "CaveRegion: grass() untyped + ground textures")

save(p, s)

# ===========================================================================
print("World.gd")
p = os.path.join(R, "scripts/World.gd"); s = load(p)

s = sub(s, """		if _region.grass() != null:
			out["grass"] = _region.grass().save_state()""",
"""		## Untyped on purpose: the floor is a GrassSystem or an Understory.
		var floor_sys = _region.grass()
		if floor_sys != null and floor_sys.has_method("save_state"):
			out["grass"] = floor_sys.save_state()""", "World: save the floor by duck type")

s = sub(s, """		if _region.grass() != null and d.has("grass"):
			_region.grass().apply_state(d["grass"] as Dictionary)""",
"""		var floor_sys = _region.grass()
		if floor_sys != null and d.has("grass") and floor_sys.has_method("apply_state"):
			floor_sys.apply_state(d["grass"] as Dictionary)""", "World: restore the floor by duck type")

save(p, s)

# ===========================================================================
print("World.gd -- save/load, props, boulders")
p = os.path.join(R, "scripts/World.gd"); s = load(p)

# --- BUG 5, AGAIN: save_state only ever wrote ChopTree ----------------------
s = sub(s, """	var trees: Array = []
	for group in ["trees", "tree_stumps"]:
		for t in get_tree().get_nodes_in_group(group):
			if t is ChopTree:
				trees.append((t as ChopTree).save_dict())""",
"""	var trees: Array = []
	for group in ["trees", "tree_stumps"]:
		for t in get_tree().get_nodes_in_group(group):
			## BUG 5, BACK AGAIN (docs/TREES_v2_SPEC.md §21): this used to read
			## `if t is ChopTree` and nothing else, so the ENTIRE TreeV2 forest
			## was never written -- and apply_state cleared the group before
			## restoring, so a load silently deleted every tree in the world.
			## It was fixed once and a later patcher put the old World.gd back.
			## If you touch this loop, keep all three branches.
			if t is TreeV2:
				trees.append((t as TreeV2).save_dict())
			elif t is TreeStump:
				trees.append((t as TreeStump).save_dict())
			elif t is ChopTree:
				trees.append((t as ChopTree).save_dict())
	var props: Array = []
	for pr in get_tree().get_nodes_in_group("psx_props"):
		if pr is PSXProp:
			props.append((pr as PSXProp).save_dict())""", "World: save every kind of tree")

s = sub(s, """		"trees": trees, "logs": logs, "dropped": dropped, "beds": beds,""",
        """		"trees": trees, "props": props, "logs": logs, "dropped": dropped, "beds": beds,""",
        "World: props into the save")

s = sub(s, """	for group in ["trees", "tree_stumps", "carry_logs", "dropped_items", "beds"]:
		for n in get_tree().get_nodes_in_group(group):
			(n as Node).queue_free()
	for td in d.get("trees", []):
		var t := ChopTree.from_dict(td as Dictionary)
		t.position = (td as Dictionary).get("pos", Vector3.ZERO)
		t.rotation.y = float((td as Dictionary).get("rot_y", 0.0))
		add_child(t)""",
"""	for group in ["trees", "tree_stumps", "carry_logs", "dropped_items", "beds", "psx_props"]:
		for n in get_tree().get_nodes_in_group(group):
			(n as Node).queue_free()
	for td in d.get("trees", []):
		## Dispatch on "kind". An old save has no kind key at all, so it falls
		## through to ChopTree exactly as it always did.
		var rec: Dictionary = td as Dictionary
		match str(rec.get("kind", "")):
			"tree_v2":
				var tv := TreeV2.from_dict(rec)
				add_child(tv)
				tv.restore(rec)
			"stump":
				add_child(TreeStump.from_dict(rec))
			_:
				var t := ChopTree.from_dict(rec)
				t.position = rec.get("pos", Vector3.ZERO)
				t.rotation.y = float(rec.get("rot_y", 0.0))
				add_child(t)
	for pd in d.get("props", []):
		var pr := PSXProp.from_dict(pd as Dictionary)
		add_child(pr)
		pr.restore(pd as Dictionary)""", "World: restore by kind")

# --- boulders wear the pack's rock -----------------------------------------
s = sub(s, """		var mesh := MeshInstance3D.new()
		var bmesh := BoxMesh.new()
		bmesh.size = Vector3(s, s * 1.2, s)
		mesh.mesh = bmesh
		mesh.position = Vector3(0, s * 0.6, 0)
		mesh.rotation_degrees = Vector3(_rng.randf_range(-12, 12), _rng.randf_range(0, 360), _rng.randf_range(-12, 12))
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.16, 0.18, 0.20)
		mat.roughness = 1.0
		mesh.material_override = mat
		rock.add_child(mesh)""",
"""		## A grey box among the pack's art reads as a missing asset, so the
		## boulders wear real rock now. The body, the groups and the `bites`
		## meta are untouched -- Player._chop_boulder never learns about this.
		if USE_PSX_NATURE:
			var big := ["SM_Rock_05", "SM_Rock_07", "SM_Rock_08", "SM_Rock_04"]
			var asset: String = big[_rng.randi() % big.size()]
			var packed = load(PSXNature.scene_path(asset))
			if packed != null:
				var m3: Node3D = packed.instantiate()
				var native: float = maxf(float(PSXNature.info(asset).get("height", 1.0)), 0.05)
				m3.scale = Vector3.ONE * (s * 1.2 / native)
				m3.rotation.y = _rng.randf() * TAU
				rock.add_child(m3)
				var rmats := PSXNature.materials("Props", PSX_REGION, false)
				for n3 in _all_nodes(m3):
					var rmi := n3 as MeshInstance3D
					if rmi != null and rmi.mesh != null:
						for si in range(rmi.mesh.get_surface_count()):
							rmi.set_surface_override_material(si, rmats[0])
				continue
		var mesh := MeshInstance3D.new()
		var bmesh := BoxMesh.new()
		bmesh.size = Vector3(s, s * 1.2, s)
		mesh.mesh = bmesh
		mesh.position = Vector3(0, s * 0.6, 0)
		mesh.rotation_degrees = Vector3(_rng.randf_range(-12, 12), _rng.randf_range(0, 360), _rng.randf_range(-12, 12))
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.16, 0.18, 0.20)
		mat.roughness = 1.0
		mesh.material_override = mat
		rock.add_child(mesh)""", "World: PSX boulders")

# --- the wood's furniture ---------------------------------------------------
s = sub(s, """	_build_forest()
	_build_rocks()""", """	_build_forest()
	_build_rocks()
	_build_props()   ## fallen logs, stumps and boulders you can climb on""",
        "World: call _build_props")

s = sub(s, """const ROCK_COUNT := 14""",
"""const ROCK_COUNT := 14
## The PSX Nature pack (docs/TREES_v3_PSX.md). false puts the grey boxes and
## the procedural trees back.
const USE_PSX_NATURE := true
const PSX_REGION := "temperate"
## Fallen logs, old stumps and standing boulders -- the pieces of the wood you
## can trip over, climb onto or chop up. The small litter is instanced without
## collision by Understory; these are real bodies, so there are not many.
const PROP_COUNT := 96
const PROP_MIN_GAP := 3.2""", "World: prop consts")

s = sub(s, """func _random_ground_point() -> Vector3:""",
"""func _all_nodes(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_all_nodes(c))
	return out


func _build_props() -> void:
	## Deadfall reads as a wood that has been standing a long time, which is
	## most of what makes a forest feel old. Logs cluster where trees are
	## thickest, so these follow the same grove logic the timber does.
	if not USE_PSX_NATURE:
		return
	var kinds := {
		"SM_FallenLog_Large": [0.55, 1.05],
		"SM_FallenLog_Small": [0.70, 1.30],
		"SM_Stump_01": [0.70, 1.40],
		"SM_Stump_02": [0.80, 1.60],
		"SM_Rock_05": [0.60, 1.50],
		"SM_Rock_07": [0.60, 1.40],
		"SM_Rock_08": [0.55, 1.30],
	}
	var names: Array = kinds.keys()
	var placed: Array[Vector3] = []
	for i in range(PROP_COUNT):
		var pos := _random_ground_point()
		if pos == Vector3.INF:
			continue
		var clash := false
		for q in placed:
			if q.distance_to(pos) < PROP_MIN_GAP:
				clash = true
				break
		if clash:
			continue
		placed.append(pos)
		var asset: String = String(names[_rng.randi() % names.size()])
		var band: Array = kinds[asset]
		var s := _rng.randf_range(float(band[0]), float(band[1]))
		add_child(PSXProp.make(asset, pos, _rng.randf() * TAU, s, PSX_REGION))


func _random_ground_point() -> Vector3:""", "World: _build_props")

save(p, s)

# ===========================================================================
print("TreeStump.gd")
p = os.path.join(R, "scripts/TreeStump.gd"); s = load(p)

s = sub(s, """	var cyl := CylinderMesh.new()
	cyl.top_radius = radius * 0.98""",
"""	if TreeV2.USE_PSX and _build_psx_stump():
		_add_collision()
		return

	var cyl := CylinderMesh.new()
	cyl.top_radius = radius * 0.98""", "TreeStump: PSX branch")

s = sub(s, """	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius * 1.1
	shape.height = STUMP_H
	cs.shape = shape
	cs.position.y = STUMP_H * 0.5
	add_child(cs)""",
"""	_add_collision()


func _add_collision() -> void:
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius * 1.1
	shape.height = STUMP_H
	cs.shape = shape
	cs.position.y = STUMP_H * 0.5
	add_child(cs)


func _build_psx_stump() -> bool:
	## The pack has two stumps. Scale the nearer one so its own trunk matches
	## the tree that stood here, and keep the pale cut face on top -- that disc
	## is the thing that says a person did this, and the pack's stump is a
	## weathered old one with bark right over the top.
	var asset := "SM_Stump_01" if radius >= 0.26 else "SM_Stump_02"
	var native_r := 0.40 if asset == "SM_Stump_01" else 0.28
	var packed = load(PSXNature.scene_path(asset))
	if packed == null:
		return false
	var m: Node3D = packed.instantiate()
	var s: float = clampf(radius / native_r, 0.45, 3.0)
	m.scale = Vector3.ONE * s
	m.rotation.y = randf() * TAU
	add_child(m)
	var mats := PSXNature.materials("Props", "temperate", false)
	for n in _all(m):
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh != null:
			for i in range(mi.mesh.get_surface_count()):
				mi.set_surface_override_material(i, mats[0])

	var top := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius * 0.92
	disc.bottom_radius = radius * 0.92
	disc.height = 0.02
	disc.radial_segments = 9
	top.mesh = disc
	top.position.y = float(PSXNature.info(asset).get("height", 0.7)) * s * 0.94
	var tm := StandardMaterial3D.new()
	tm.albedo_color = HEART
	tm.roughness = 0.9
	top.material_override = tm
	add_child(top)
	return true


func _all(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out""", "TreeStump: collision split + PSX stump")

save(p, s)
print("done")
