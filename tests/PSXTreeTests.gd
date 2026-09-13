extends SceneTree

## ===========================================================================
## Headless suite for the PSX Nature swap.   docs/TREES_v3_PSX.md §10
##
##   godot --headless --path . --script res://tests/PSXTreeTests.gd
##
## What this is here to stop happening again:
##   1. a tree that renders with the glTF placeholder material instead of ours
##   2. a notch with no geometry to carve, so the axe passes through the trunk
##   3. a save that comes back a different forest (or no forest -- see §21)
##   4. a felled tree whose canopy pops out of existence instead of shedding
## ===========================================================================

var passed := 0
var failed := 0
var failures: Array[String] = []
var _ran := false


## ---------------------------------------------------------------------------
## THE MODEL HALF OF THIS SUITE ONLY MEANS ANYTHING WHILE TreeV2.USE_PSX IS ON.
##
## Lemon moved the art to the trees-v4 authored kit in bd14707: `USE_PSX` is
## false and `USE_KIT` is true, so `TreeV2._build_psx()` is never called, `_psx`
## stays an empty Dictionary, and the node in the scene is a TreeKit assembly —
## a `Trunk` and a row of `Branch_NN_rXXX`, with no `Foliage` child, no asset
## name and real limbs. Every assertion below that reaches into that model was
## therefore reporting a failure about a code path the game does not run, 27 of
## them, and one of them (`t._psx["asset"]`) crashed the suite outright before
## the last section could finish.
##
## What still runs either way is the part worth keeping green: the PSXNature
## MANIFEST, the PICKER, DETERMINISM and the MATERIALS are pure tables, and
## they are exactly what would rot in silence if the pack were re-exported or
## a file renamed. Flip USE_PSX back to true and the model sections arm again.
## ---------------------------------------------------------------------------
func _psx_on() -> bool:
	return TreeV2.USE_PSX


func skip(label: String) -> void:
	## A skip is a RESULT, and it says which switch silenced it.
	ok(true, "TreeV2.USE_PSX is off -- %s" % label)


func ok(cond: bool, label: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		failures.append(label)
		print("  FAIL  ", label)


func _process(_delta: float) -> bool:
	## Tests run on the first FRAME, not in _initialize(): the root is not in
	## the tree during _initialize, so nothing added there ever gets _ready().
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	print("\n=========== PSX NATURE SUITE ===========\n")
	_test_manifest()
	_test_picking()
	_test_determinism()
	_test_materials()
	_test_build()
	_test_notch_geometry()
	_test_chop_to_fell()
	_test_shedding()
	_test_snags()
	_test_great_trees()
	_test_props()
	_test_save_round_trip()
	_report()
	quit(1 if failed > 0 else 0)


func _all(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out


func _meshes(n: Node) -> Array:
	var out: Array = []
	for x in _all(n):
		var mi := x as MeshInstance3D
		if mi != null and mi.mesh != null:
			out.append(mi)
	return out


func _spawn(species: String, stage: int, dead := false, sc := 1.0, seed_v := 991) -> TreeV2:
	var t := TreeV2.new()
	t.species = species
	t.stage = stage
	t.dead = dead
	t.scale_class = sc
	t.tree_seed = seed_v
	root.add_child(t)
	return t


## ---------------------------------------------------------------- assets ---

func _test_manifest() -> void:
	var m := PSXNature.manifest()
	ok(m.size() == 38, "manifest holds all 38 pack assets (got %d)" % m.size())

	var lean := 0
	for k in m:
		lean += int(m[k]["wood"]) + int(m[k]["foliage"])
		ok(ResourceLoader.exists(PSXNature.scene_path(k)), "%s has a GLB" % k)
	## The whole point of the swap: a mature tree was 5-13k triangles and is now
	## a couple of hundred. If this ever creeps back up, something re-baked the
	## dense trunk into the standing model.
	ok(lean < 5000, "the whole pack is under 5k triangles standing (got %d)" % lean)
	ok(int(m["SM_Tree_01"]["wood"]) + int(m["SM_Tree_01"]["foliage"]) < 400,
		"a mature hardwood is under 400 triangles")

	for species in PSXNature.TREE_MESH:
		var table: Dictionary = PSXNature.TREE_MESH[species]
		for role in table:
			for a in table[role]:
				ok(m.has(a), "%s/%s -> %s is a real asset" % [species, role, a])

	## Every choppable tree needs its dense twin, and it must actually be denser.
	for k in m:
		if not bool(m[k]["choppable"]):
			continue
		ok(ResourceLoader.exists(PSXNature.scene_path(k + "_chop")),
			"%s has a dense chop trunk" % k)
		ok(int(m[k]["chop_tris"]) > int(m[k]["wood"]),
			"%s's chop trunk carries more geometry than the standing one" % k)


func _test_picking() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for species in PSXNature.ALL_SPECIES_TEST():
		for stage in range(5):
			var d := PSXNature.pick_tree(species, stage, false, 1.0, rng)
			var band: Array = PSXNature.STAGE_H[stage]
			ok(PSXNature.has(d["asset"]), "%s/%d picks a real asset" % [species, stage])
			ok(float(d["height"]) >= float(band[0]) - 0.01
				and float(d["height"]) <= float(band[1]) + 0.01,
				"%s/%d stands inside its stage's height band" % [species, stage])
			ok(float(d["scale"]) > 0.05 and float(d["scale"]) < 3.6,
				"%s/%d is not scaled past recognition (x%.2f)" % [species, stage, d["scale"]])
			ok(float(d["chop_y"]) >= 0.45 and float(d["chop_y"]) <= 1.45,
				"%s/%d chops inside the packed band" % [species, stage])
			ok(float(d["radius"]) > 0.0, "%s/%d has a trunk with a radius" % [species, stage])

	## The radius profile must never read zero anywhere in the chop window --
	## a zero there lets the axe eat through the tree in one bite.
	for k in PSXNature.manifest():
		if not bool(PSXNature.info(k)["choppable"]):
			continue
		for y in [0.5, 0.75, 1.0, 1.25, 1.45]:
			ok(PSXNature.radius_at(k, y) > 0.01,
				"%s has real wood at %.2f m" % [k, y])


func _test_determinism() -> void:
	## A tree restored from a save re-rolls its model from tree_seed. If that
	## ever stops matching, every load reshuffles the whole forest.
	for seed_v in [1, 7717, 99991]:
		var a := RandomNumberGenerator.new(); a.seed = seed_v
		var b := RandomNumberGenerator.new(); b.seed = seed_v
		var x := PSXNature.pick_tree("oak", 2, false, 1.0, a)
		var y := PSXNature.pick_tree("oak", 2, false, 1.0, b)
		ok(x["asset"] == y["asset"] and is_equal_approx(x["scale"], y["scale"]),
			"seed %d picks the same tree twice" % seed_v)


func _test_materials() -> void:
	PSXNature.flush()
	var names := ["atlas_spring", "atlas_summer", "atlas_autumn", "atlas_winter"]
	for region in PSXNature.REGIONS:
		for atlas in ["Trees", "Props", "GiantPine"]:
			var pair := PSXNature.materials(atlas, region, false)
			ok(pair.size() == 2, "%s/%s builds a wood+foliage pair" % [region, atlas])
			for m in pair:
				var sm := m as ShaderMaterial
				ok(sm != null and sm.shader != null, "%s/%s has a shader" % [region, atlas])
				for n in names:
					ok(sm.get_shader_parameter(n) != null,
						"%s/%s binds %s" % [region, atlas, n])
	## The same pair is handed out every time, or 420 trees become 420 materials.
	ok(PSXNature.materials("Trees", "temperate", false)
		== PSXNature.materials("Trees", "temperate", false), "materials are cached and shared")
	ok(PSXNature.materials("Trees", "temperate", false)
		!= PSXNature.materials("Trees", "deepwood", false), "regions get their own pair")


## ----------------------------------------------------------------- trees ---

func _test_build() -> void:
	for species in ["maple", "birch", "oak", "pine", "fir"]:
		var t := _spawn(species, 2)
		var ms := _meshes(t)
		ok(ms.size() >= 1, "%s builds geometry" % species)
		var has_trunk := false
		var has_leaf := false
		for mi in ms:
			var m3 := mi as MeshInstance3D
			if m3.name.begins_with("Trunk"):
				has_trunk = true
			if m3.name.begins_with("Foliage"):
				has_leaf = true
			for i in range(m3.mesh.get_surface_count()):
				var mat := m3.get_surface_override_material(i)
				ok(mat is ShaderMaterial,
					"%s/%s surface %d wears OUR shader, not the glTF placeholder"
					% [species, m3.name, i])
		ok(has_trunk, "%s has a trunk" % species)
		if _psx_on():
			ok(has_leaf, "%s has a canopy" % species)
		else:
			skip("the kit names its canopy Branch_NN, not Foliage (%s)" % species)
		var col: CollisionShape3D = null
		for c in t.get_children():
			if c is CollisionShape3D:
				col = c
		ok(col != null, "%s has a collider" % species)
		if col != null:
			var cyl := col.shape as CylinderShape3D
			ok(cyl != null and cyl.radius > 0.04 and cyl.height > 1.0,
				"%s's collider matches a real tree (r=%.2f h=%.2f)"
				% [species, cyl.radius if cyl else -1.0, cyl.height if cyl else -1.0])
		t.free()


func _test_notch_geometry() -> void:
	## The whole reason the dense trunk exists: the pack's standing trunk has no
	## rings through the chop band, so there is nothing to push inward.
	for species in ["maple", "pine"]:
		var t := _spawn(species, 2)
		var before := 0
		for mi in _meshes(t):
			if (mi as MeshInstance3D).name.begins_with("Trunk"):
				before = (mi as MeshInstance3D).mesh.get_faces().size()
		t.chop_hit(Vector3.FORWARD)
		var after := 0
		var moved := false
		var painted := false
		for mi in _meshes(t):
			var m3 := mi as MeshInstance3D
			if not m3.name.begins_with("Trunk"):
				continue
			after = m3.mesh.get_faces().size()
			var arr: Array = m3.mesh.surface_get_arrays(0)
			var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			for c in cols:
				if c.r < 0.999:
					painted = true
					break
			moved = t.notch_depth > 0.0
		if not _psx_on():
			skip("the dense-trunk swap is a pack model trick (%s)" % species)
		else:
			ok(after > before, "%s swaps in the dense trunk on the first bite (%d -> %d)"
				% [species, before, after])
		ok(moved, "%s's first swing cut a notch" % species)
		ok(painted, "%s shows pale heartwood inside the cut" % species)
		t.free()


func _test_chop_to_fell() -> void:
	for species in ["maple", "birch", "oak", "pine", "fir"]:
		for stage in [1, 2, 3]:
			var t := _spawn(species, stage)
			var swings := 0
			var felled := false
			while swings < 30 and not felled:
				swings += 1
				felled = t.chop_hit(Vector3.FORWARD)
			ok(felled, "%s/%d comes down" % [species, stage])
			ok(swings <= 8, "%s/%d takes a sane number of swings (%d)"
				% [species, stage, swings])
			## No limbs on a PSX tree -- every swing must land on the trunk.
			## The kit DOES build limbs, on purpose, so this is a pack claim.
			if _psx_on():
				ok(t.branches_left() == 0, "%s/%d gates nothing behind limbs" % [species, stage])
			else:
				skip("the kit builds real limbs by design (%s/%d)" % [species, stage])
			var trunk: FallenTrunk = null
			var stump: TreeStump = null
			for c in root.get_children():
				if c is FallenTrunk:
					trunk = c
				elif c is TreeStump:
					stump = c
			ok(trunk != null, "%s/%d leaves a trunk on the ground" % [species, stage])
			ok(stump != null, "%s/%d leaves a stump" % [species, stage])
			if trunk != null:
				ok(trunk.sticks > 0, "%s/%d gives up sticks when it lands" % [species, stage])
				ok(trunk.trunk_len > 1.0 and trunk.trunk_r > 0.03,
					"%s/%d's fallen trunk is the size the tree was" % [species, stage])
			for c in root.get_children():
				if c is FallenTrunk or c is TreeStump or c is LeafBurst:
					c.free()


func _test_shedding() -> void:
	## Lemon's call: the leaves SHOULD come off -- as a burst, not a pop.
	var t := _spawn("maple", 3)
	var model: Node3D = null
	for c in t.get_children():
		if c is Node3D and not (c is CollisionShape3D):
			model = c
	var burst := LeafBurst.spawn_from(model, "Trees", "temperate", root, 48)
	if not _psx_on():
		skip("LeafBurst reads the pack's own Foliage UVs, which a kit tree has not got")
	else:
		ok(burst != null, "a canopy throws a leaf burst")
	if burst != null:
		ok(burst.mesh != null and burst.mesh.get_surface_count() == 1,
			"the burst is one mesh, one draw call")
		var arr: Array = burst.mesh.surface_get_arrays(0)
		var custom: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM0]
		ok(custom.size() > 0, "every leaf carries its own centre and seed")
		ok(arr[Mesh.ARRAY_TEX_UV] != null and (arr[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() > 0,
			"the leaves keep the pack's own atlas UVs")
		ok(burst.custom_aabb.size.length() > 20.0,
			"the burst keeps a big AABB so it is not culled the moment it falls")
		burst.free()
	## A bare snag has nothing to throw and must not try.
	var snag := _spawn("maple", 4, true)
	var snag_model: Node3D = null
	for c in snag.get_children():
		if c is Node3D and not (c is CollisionShape3D):
			snag_model = c
	ok(LeafBurst.spawn_from(snag_model, "Trees", "temperate", root, 20) == null,
		"a bare snag throws nothing")
	t.free()
	snag.free()
	for c in root.get_children():
		if c is LeafBurst:
			c.free()


func _test_snags() -> void:
	for species in ["maple", "oak", "pine", "fir"]:
		var t := _spawn(species, 2, true)
		var asset := String(t._psx.get("asset", ""))
		if _psx_on():
			ok(asset.findn("Bare") >= 0, "a dead %s wears a bare model (%s)" % [species, asset])
		else:
			skip("a kit snag is built dead, it does not swap to a Bare* asset (%s)" % species)
		## Dead wood is brittle: fewer bites than the same living tree.
		var alive := _spawn(species, 2, false)
		ok(t.chops_left < alive.chops_left, "dead %s wood is brittle" % species)
		t.free()
		alive.free()
	## The withered stage is dead however it was built.
	var w := _spawn("birch", 4, false)
	ok(w.dead, "a withered tree is dead even when nothing rolled it")
	w.free()


func _test_great_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for species in ["pine", "fir"]:
		var d := PSXNature.pick_tree(species, 3, false, 4.0, rng)
		ok(String(d["asset"]).begins_with("SM_GiantPine"),
			"a great %s is one of the pack's giants" % species)
		ok(float(d["height"]) > 24.0, "a great %s clears the canopy (%.1f m)"
			% [species, d["height"]])
	var oak := PSXNature.pick_tree("oak", 3, false, 4.0, rng)
	ok(float(oak["height"]) > 24.0, "a great hardwood is huge too (%.1f m)" % oak["height"])


func _test_props() -> void:
	for asset in ["SM_FallenLog_Large", "SM_Stump_01", "SM_Rock_05"]:
		var p := PSXProp.make(asset, Vector3.ZERO, 0.0, 1.0)
		root.add_child(p)
		ok(_meshes(p).size() > 0, "%s builds geometry" % asset)
		var shapes := 0
		for c in p.get_children():
			if c is CollisionShape3D:
				shapes += 1
		ok(shapes > 0, "%s can be bumped into" % asset)
		p.free()

	## Wood you can chop, stone you cannot.
	ok(PSXProp.chop_yield("SM_FallenLog_Large") > 0, "a big fallen log is firewood")
	ok(PSXProp.chop_yield("SM_Stump_02") > 0, "an old stump can be cleared")
	ok(PSXProp.chop_yield("SM_Rock_05") == 0, "a boulder is not firewood")

	var log_p := PSXProp.make("SM_FallenLog_Small", Vector3.ZERO, 0.0, 1.0)
	root.add_child(log_p)
	var n := PSXProp.chop_yield("SM_FallenLog_Small")
	var done := false
	for i in range(n):
		done = log_p.chop_hit(Vector3.FORWARD)
	ok(done, "a small log breaks up in exactly %d swings" % n)
	var wood := 0
	for c in root.get_children():
		if c is DroppedItem:
			wood += 1
			c.free()
	ok(wood > 0, "and leaves something worth carrying")
	if is_instance_valid(log_p):
		log_p.free()


func _test_save_round_trip() -> void:
	var t := _spawn("oak", 3, false, 1.0, 4242)
	t.region = "deepwood"
	t.chop_hit(Vector3.FORWARD)
	t.chop_hit(Vector3.FORWARD)
	## ⚠ THIS LINE CRASHED THE WHOLE SUITE. With USE_PSX off `_psx` is an empty
	## Dictionary, and `_psx["asset"]` is an invalid key access, not a null —
	## it threw before the last four assertions of the run could be reached.
	var asset := String(t._psx.get("asset", ""))
	var t_variant: int = t.kit_variant
	var d := t.save_dict()
	ok(str(d.get("kind", "")) == "tree_v2", "a PSX tree saves as tree_v2")
	ok(str(d.get("region", "")) == "deepwood", "and remembers its biome")
	t.free()

	var back := TreeV2.from_dict(d)
	root.add_child(back)
	back.restore(d)
	if _psx_on():
		ok(String(back._psx.get("asset", "")) == asset,
			"it comes back as the SAME model (%s)" % asset)
	else:
		ok(back.kit_variant == t_variant,
			"it comes back as the SAME kit variant (%d)" % back.kit_variant)
	ok(back.region == "deepwood", "and in the same biome")
	ok(back.chops_left == int(d["chops"]), "part-chopped stays part-chopped")
	ok(back.notch_depth > 0.0, "and keeps its notch")
	back.free()


func _report() -> void:
	print("\n-------------------------------------------")
	print("  passed: %d   failed: %d" % [passed, failed])
	if failed > 0:
		print("  failures:")
		for f in failures:
			print("    - ", f)
	## A floor, so a suite that silently stops running half its sections cannot
	## report green. (Learned the hard way: an `await` inside a section drops
	## the rest of it and still prints a pass.)
	var floor_n := 300
	if passed + failed < floor_n:
		print("  !! only %d assertions ran, expected at least %d" % [passed + failed, floor_n])
	print("===========================================\n")
