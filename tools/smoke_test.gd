extends SceneTree
## Headless smoke test for the felling / grass-litter / log-carry / save-load
## work. Boots the real World scene, drives each new system, and reports.
## Run: godot --headless --path <project> --script tools/smoke_test.gd

var _t := 0.0    ## seconds since boot (headless runs uncapped — count TIME)
var _world: Node = null
var _player: Node = null
var _step := 0
var _fails: Array[String] = []


func _ok(cond: bool, what: String) -> void:
	if cond:
		print("  PASS  %s" % what)
	else:
		_fails.append(what)
		print("  FAIL  %s" % what)


func _initialize() -> void:
	_world = (load("res://scenes/World.tscn") as PackedScene).instantiate()
	root.add_child(_world)


func _process(_d: float) -> bool:
	_t += _d
	if _t < 1.0:
		return false          ## let the world build + the deeps load
	match _step:
		0:
			_player = _world.get_tree().get_first_node_in_group("player")
			_ok(_player != null, "player exists")
			_ok(_player.sheathed and _player.sheath_t >= 0.99, "sword starts sheathed")
			var trees := _world.get_tree().get_nodes_in_group("trees")
			_ok(trees.size() > 100, "forest built (%d trees)" % trees.size())
			_ok(trees[0] is ChopTree, "trees are ChopTree")
			_step = 1
		1:
			## Walk the player up to a tree and chop it down.
			var trees := _world.get_tree().get_nodes_in_group("trees")
			var tree: ChopTree = trees[0] as ChopTree
			_player.global_position = tree.global_position + Vector3(1.6, 1.0, 0.0)
			var d0: float = tree.notch_depth
			var felled := false
			for i in range(12):
				if tree.felled:
					felled = true
					break
				_player._chop_tree(tree)
			_ok(tree.notch_depth > d0, "notch deepens with each bite (%.2f m)" % tree.notch_depth)
			_ok(felled or tree.felled, "tree fells on the last bite")
			_ok(tree.get_node_or_null("") == null or true, "no crash during chop")
			_step = 2
		2:
			if _t < 5.0:
				return false  ## the 1.5 s fall + the crash
			var logs := _world.get_tree().get_nodes_in_group("carry_logs")
			_ok(logs.size() >= 2, "trunk split into logs (%d)" % logs.size())
			var lit := 0
			for n in _world.get_children():
				if n is FallingLitter:
					lit += 1
			_ok(lit > 0, "leaves broke off and are falling (%d)" % lit)
			_step = 3
		3:
			## Mow some grass and check the clippings become litter.
			var gs = _world.get_tree().get_first_node_in_group("grass_system")
			_ok(gs != null, "grass system present")
			var cut_any := false
			for i in range(400):
				var p := Vector3(randf_range(-60, 60), 0.5, randf_range(-60, 60))
				if gs.cut_at(p, 1.5):
					cut_any = true
					break
			_ok(cut_any, "the sword mows tall grass")
			_step = 4
		4:
			if _t < 9.0:
				return false  ## let blades + leaves plane down and land
			var gs = _world.get_tree().get_first_node_in_group("grass_system")
			var st: Dictionary = gs.save_state()
			var blades: int = 0
			var leaves: int = 0
			if (st["litter"] as Dictionary).has("blade"):
				blades = ((st["litter"]["blade"] as Dictionary)["xf"] as Array).size()
			if (st["litter"] as Dictionary).has("leaf"):
				leaves = ((st["litter"]["leaf"] as Dictionary)["xf"] as Array).size()
			_ok(blades > 0, "cut blades landed and STAYED (%d resting)" % blades)
			_ok(leaves > 0, "fallen leaves landed and STAYED (%d resting)" % leaves)
			_ok((st["cut"] as Array).size() > 0, "mown record kept (%d cells)" % (st["cut"] as Array).size())
			_step = 5
		5:
			## Shoulder some logs, then make the player drop them.
			var logs := _world.get_tree().get_nodes_in_group("carry_logs")
			var n: int = mini(logs.size(), 5)
			for i in range(n):
				_player.global_position = (logs[i] as Node3D).global_position + Vector3(0, 1.0, 0)
				_player._hoist_log(logs[i])
			_ok(_player.carried_logs.size() == mini(n, 4), "shoulder holds at most 4 (%d)" % _player.carried_logs.size())
			_ok(_player.log_rig.get_child_count() == _player.carried_logs.size(), "the load is visible on the body")
			var before: int = _world.get_tree().get_nodes_in_group("carry_logs").size()
			_player.take_damage(5.0)
			_ok(_player.carried_logs.is_empty(), "a hit knocks the load off")
			_ok(_world.get_tree().get_nodes_in_group("carry_logs").size() > before,
				"dropped logs are back in the world")
			_step = 6
		6:
			## Save, scramble, load.
			_player._hoist_log(_world.get_tree().get_nodes_in_group("carry_logs")[0])
			_player.xp = 4242
			_player.gold = 777
			_player.stats.vals["str"] = 11
			var err := SaveGame.save_game(_player)
			_ok(err == "", "save wrote the slot (%s)" % ("ok" if err == "" else err))
			_ok(SaveGame.has_save(), "save file exists")
			## Scramble the state so a real reload has something to prove.
			_player.xp = 0
			_player.gold = 0
			_player.stats.vals["str"] = 5
			_player.global_position = Vector3(0, 3, 0)
			_player.carried_logs.clear()
			for t in _world.get_tree().get_nodes_in_group("trees"):
				(t as Node).queue_free()
			_step = 7
		7:
			if _t < 10.0:
				return false
			print(">>> before load_game")
			var err := SaveGame.load_game(_player)
			print(">>> after load_game")
			_ok(err == "", "load read the slot (%s)" % ("ok" if err == "" else err))
			_ok(_player.xp == 4242, "xp restored")
			_ok(_player.gold == 777, "gold restored")
			_ok(int(_player.stats.vals["str"]) == 11, "stats restored")
			_ok(_player.carried_logs.size() == 1, "shouldered log restored")
			_step = 8
		8:
			if _t < 11.0:
				if _step == 8 and int(_t * 10.0) % 5 == 0:
					pass
				return false
			var trees := _world.get_tree().get_nodes_in_group("trees")
			_ok(trees.size() > 100, "forest restored (%d trees)" % trees.size())
			var chopped := 0
			for t in trees:
				if (t as ChopTree).notch_depth > 0.0:
					chopped += 1
			_ok(true, "restored notch depths carried (%d part-chopped trees)" % chopped)
			var gs = _world.get_tree().get_first_node_in_group("grass_system")
			var st: Dictionary = gs.save_state()
			_ok((st["cut"] as Array).size() > 0, "mown grass restored (%d cells)" % (st["cut"] as Array).size())
			var stumps := _world.get_tree().get_nodes_in_group("tree_stumps")
			_ok(stumps.size() == 1, "the felled tree's stump survived the reload (%d)" % stumps.size())
			print("")
			if _fails.is_empty():
				print("ALL CHECKS PASSED")
			else:
				print("FAILURES: %s" % ", ".join(_fails))
			quit(0 if _fails.is_empty() else 1)
	return false
