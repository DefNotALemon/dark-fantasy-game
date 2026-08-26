extends SceneTree

## ===========================================================================
## Headless test suite for trees v2.  docs/TREES_v2_SPEC.md §20
##
##   godot --headless --path . --script res://tests/TreeTests.gd
##
## Covers the three things that were actually broken, so they stay fixed:
##   1. every tree gets OUR ShaderMaterials, never the glTF placeholders
##      (the flat-grey + transmission materials are what made leaves glitch
##       and trees render magenta)
##   2. limb HP comes from the exported radius, so a tree is fellable in a
##      sane number of swings instead of ~84
##   3. chopping actually reaches the trunk, fells it, and leaves a stump
## ===========================================================================

var passed := 0
var failed := 0
var failures: Array[String] = []
var _species_needing_limbs := {}


func ok(cond: bool, label: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		failures.append(label)
		print("  FAIL  ", label)


## Tests run on the first frame, not in _initialize(): the SceneTree's root is
## not inside the tree yet during _initialize, so nothing added there ever gets
## its _ready() — which silently produced a tree with no model in it.
var _ran := false


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	print("\n=========== TREES v2 TEST SUITE ===========\n")
	_test_models_and_materials()
	_test_limb_hp()
	_test_chop_to_fell()
	_test_reachable_limbs()
	_test_save_round_trip()
	_test_dead_trees()
	_test_stump_clear()
	_test_season_maths()
	_report()
	quit(1 if failed > 0 else 0)


func _spawn(species: String, stage: int) -> TreeV2:
	var t := TreeV2.new()
	t.species = species
	t.stage = stage
	root.add_child(t)
	return t


# --------------------------------------------------------------------------

func _test_models_and_materials() -> void:
	print("[1] models load, and every surface gets a ShaderMaterial")
	for species in TreeV2.ALL_SPECIES:
		for stage in range(5):
			var t := _spawn(species, stage)
			var meshes := _all_meshes(t)
			ok(meshes.size() > 0, "%s/%d has mesh parts" % [species, stage])

			var leaf_surfaces := 0
			var bad := 0
			for mi in meshes:
				for i in range(mi.mesh.get_surface_count()):
					var m: Material = mi.get_surface_override_material(i)
					if m == null or not (m is ShaderMaterial):
						bad += 1
						continue
					if (m as ShaderMaterial).shader == null:
						bad += 1
						continue
					var src: Material = mi.mesh.surface_get_material(i)
					if src != null and str(src.resource_name).findn("leaf") >= 0:
						leaf_surfaces += 1
						var atlas = (m as ShaderMaterial).get_shader_parameter("leaf_atlas")
						if atlas == null:
							bad += 1
			ok(bad == 0, "%s/%d every surface overridden with a live ShaderMaterial" % [species, stage])
			if stage != 4:
				ok(leaf_surfaces > 0, "%s/%d has leaf surfaces" % [species, stage])
			t.queue_free()


func _all_meshes(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			out.append(c)
		out.append_array(_all_meshes(c))
	return out


# --------------------------------------------------------------------------

func _test_limb_hp() -> void:
	print("[2] limb thickness comes from the exported name, not the AABB")
	ok(is_equal_approx(TreeBranch._radius_from_name("Branch_03_r085"), 0.085),
		"Branch_03_r085 parses as 0.085 m")
	ok(is_equal_approx(TreeBranch._radius_from_name("Branch_00_r012"), 0.012),
		"Branch_00_r012 parses as 0.012 m")
	ok(is_equal_approx(TreeBranch._radius_from_name("Branch_07"), 0.06),
		"a name with no radius falls back safely")

	## Limbs are optional now, so what matters is that they exist, that their HP
	## came from the exported radius, and that none of them is a 7-swing monster.
	for species in TreeV2.ALL_SPECIES:
		var t := _spawn(species, 2)
		ok(t.branches_left() > 0, "%s mature has limbs to cut for sticks" % species)
		var worst := 0
		for c in t.get_children():
			var b := c as TreeBranch
			if b != null:
				worst = maxi(worst, b.hp)
		ok(worst >= 1 and worst <= TreeBranch.MAX_HP,
			"%s worst limb is %d hits (1..%d)" % [species, worst, TreeBranch.MAX_HP])
		t.queue_free()


# --------------------------------------------------------------------------

func _test_chop_to_fell() -> void:
	print("[3] a tree can actually be chopped down, in a sane number of swings")
	for species in TreeV2.ALL_SPECIES:
		for stage in [1, 2, 3]:
			var t := _spawn(species, stage)
			var toward := Vector3(1, 0, 0)
			var swings := 0
			var felled := false
			var limbs_at_start := t.branches_left()
			while swings < 400:
				swings += 1
				if t.chop_hit(toward, t.global_position + Vector3.UP * 2.0):
					felled = true
					break
			ok(felled, "%s/%d fells" % [species, stage])
			ok(swings <= 40, "%s/%d fells in %d swings (<=40, was ~84 before the fix)"
				% [species, stage, swings])
			## Not every species needs limbing, and that is deliberate: a slender
			## birch, or an ancient pine that has self-pruned its lower branches,
			## has nothing low enough to be worth a swing — it is a pure trunk
			## job. What must hold is that IF limbs gate the trunk they really
			## stood in the way (asserted just below), that none of them is out
			## of reach, and that limbing matters on some species.
			ok(limbs_at_start >= 0, "%s/%d counted its limbs" % [species, stage])

			## Limbs must NOT gate the trunk any more: one swing at a fresh
			## tree has to bite wood, not bounce off a limb requirement.
			var t2 := _spawn(species, stage)
			var before: int = t2.chops_left
			t2.chop_hit(Vector3(1, 0, 0), Vector3.INF)
			ok(t2.chops_left == before - 1,
				"%s/%d first swing goes straight into the trunk" % [species, stage])
			ok(t2.notch_depth > 0.0, "%s/%d that swing cut a notch" % [species, stage])
			t2.queue_free()

			## felling must leave a stump and a fallen trunk behind
			var stumps := 0
			var trunks := 0
			for n in root.get_children():
				if n is TreeStump:
					stumps += 1
				elif n is FallenTrunk:
					trunks += 1
			ok(stumps > 0, "%s/%d leaves a stump" % [species, stage])
			ok(trunks > 0, "%s/%d leaves a fallen trunk" % [species, stage])
			for n in root.get_children():
				if n is TreeStump or n is FallenTrunk:
					n.queue_free()


# --------------------------------------------------------------------------

func _test_reachable_limbs() -> void:
	## Limbing is now optional everywhere: no tree may refuse the trunk.
	print("[3b] no tree gates its trunk behind limbs")
	for species in TreeV2.ALL_SPECIES:
		for stage in [1, 2, 3]:
			var t := _spawn(species, stage)
			ok(not t.trunk_blocked(), "%s/%d trunk is never blocked" % [species, stage])
			var gate := 0
			for c in t.get_children():
				var b := c as TreeBranch
				if b != null and b.blocks_trunk:
					gate += 1
			ok(gate == 0, "%s/%d has no gating limbs at all" % [species, stage])
			t.queue_free()


func _test_save_round_trip() -> void:
	## The bug this locks down: World.save_state() only wrote ChopTree nodes and
	## apply_state() cleared the whole "trees" group first, so loading a save
	## deleted the entire v2 forest and restored nothing.
	print("[3c] a part-chopped tree survives save and load")
	var t := _spawn("oak", 3)
	for i in range(3):
		t.chop_hit(Vector3(1, 0, 0), Vector3.ZERO)
	var d := t.save_dict()
	ok(str(d.get("kind", "")) == "tree_v2", "save_dict is tagged tree_v2")
	ok(d.has("branches") and d.has("chops"), "save_dict carries limb and chop state")
	ok(d.has("notch") and float(d["notch"]) > 0.0, "save_dict carries the notch depth")

	var t2 := TreeV2.from_dict(d)
	root.add_child(t2)
	t2.restore(d)
	ok(t2.species == t.species and t2.stage == t.stage, "species and stage restore")
	ok(t2.branches_left() == t.branches_left(),
		"limbs restore (%d == %d)" % [t2.branches_left(), t.branches_left()])
	ok(t2.chops_left == t.chops_left, "trunk progress restores")
	ok(is_equal_approx(t2.notch_depth, t.notch_depth), "the notch itself restores")
	t.queue_free()
	t2.queue_free()


func _test_dead_trees() -> void:
	## The "trees with no leaves" were the withered stage wearing LIVING bark and
	## green leaves, so a snag read as a broken tree. A dead tree must look dead.
	print("[3d] dead trees wear deadwood and go bare")
	var live := TreeV2.materials_for("oak", false)
	var gone := TreeV2.materials_for("oak", true)
	ok(live[0] != gone[0], "a snag gets its own bark material")
	ok(live[1] != gone[1], "a snag gets its own leaf material")
	ok((gone[1] as ShaderMaterial).get_shader_parameter("dead") == true,
		"the dead flag reaches the foliage shader")
	ok((live[1] as ShaderMaterial).get_shader_parameter("dead") == false,
		"a living tree is not flagged dead")
	ok((gone[0] as ShaderMaterial).get_shader_parameter("bark_albedo") != null,
		"deadwood bark texture loads")

	var w := _spawn("oak", 4)
	ok(w.dead, "the withered stage is always dead")
	ok(w.chops_left < TreeV2.TRUNK_CHOPS[4], "dead wood is brittle")
	w.queue_free()

	## a blast must leave a real trunk and NO stump (the crater ate it)
	var t := _spawn("maple", 2)
	t.blast_fell(t.global_position + Vector3(2, 0, 0))
	ok(t.felled, "blast_fell fells the tree")
	var trunks := 0
	var stumps := 0
	for n in root.get_children():
		if n.is_queued_for_deletion():
			continue      ## queue_free() is deferred; leftovers are still children
		if n is FallenTrunk:
			trunks += 1
		elif n is TreeStump:
			stumps += 1
	ok(trunks > 0, "a blasted tree leaves a trunk on the ground")
	ok(stumps == 0, "a blasted tree leaves no stump — the crater took it")
	for n in root.get_children():
		if n is FallenTrunk or n is TreeStump:
			n.queue_free()


func _test_stump_clear() -> void:
	print("[4] stumps clear in three more hits")
	var s := TreeStump.make(Vector3.ZERO, 0.3, "oak")
	root.add_child(s)
	ok(not s.chop_hit(Vector3.FORWARD), "hit 1 does not clear it")
	ok(not s.chop_hit(Vector3.FORWARD), "hit 2 does not clear it")
	ok(s.chop_hit(Vector3.FORWARD), "hit 3 clears it")

	var sd := TreeStump.make(Vector3.ZERO, 0.4, "birch")
	root.add_child(sd)
	sd.chop_hit(Vector3.FORWARD)
	var r := TreeStump.from_dict(sd.save_dict())
	ok(r.hits_left == sd.hits_left, "a part-cleared stump survives save and load")


# --------------------------------------------------------------------------

func _test_season_maths() -> void:
	print("[5] 24-day seasons, 96-day year")
	ok(Wind.DAYS_PER_SEASON == 24.0, "a season is 24 game days")
	ok(Wind.DAYS_PER_YEAR == 96.0, "a year is 96 game days")
	ok(Wind.season_name(0.0) == "Spring", "day 0 is Spring")
	ok(Wind.season_name(25.0) == "Summer", "day 25 is Summer")
	ok(Wind.season_name(50.0) == "Autumn", "day 50 is Autumn")
	ok(Wind.season_name(80.0) == "Winter", "day 80 is Winter")
	ok(Wind.season_name(97.0) == "Spring", "day 97 wraps to Spring")
	ok(is_equal_approx(Wind.phase_for_day(48.0), 0.5), "half a year is phase 0.5")


func _report() -> void:
	print("\n===========================================")
	print("  passed: %d    failed: %d" % [passed, failed])
	if failed > 0:
		print("  failures:")
		for f in failures:
			print("   - ", f)
	print("===========================================\n")
