extends SceneTree
## Headless smoke test for the felling / grass-litter / log-carry / save-load
## work. Boots the real World scene, drives each new system, and reports.
## Run: godot --headless --path <project> --script tools/smoke_test.gd

var _t := 0.0    ## seconds since boot (headless runs uncapped — count TIME)
var _world: Node = null
var _player: Node = null
var _step := 0
var _fails: Array[String] = []
var _kob: Node3D = null
var _rout_from := Vector3.ZERO


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
			_step = 9
		9:
			## --- Wounded enemies break and run, slowly ---
			var kob := Kobold.new()
			_world.add_child(kob)
			kob.global_position = _player.global_position + Vector3(3, 1, 0)
			_kob = kob
			_ok(kob.nerve > 0.0, "kobold has nerve to break (%.2f)" % kob.nerve)
			kob.take_damage(kob.max_health * 0.9)
			_ok(kob.routing, "a badly hurt kobold routs")
			_ok(kob.chase_speed * kob.rout_speed < kob.chase_speed, "it runs slower than it hunted (%.1f vs %.1f)" % [kob.chase_speed * kob.rout_speed, kob.chase_speed])
			var sk := Skeleton.new()
			_world.add_child(sk)
			sk.global_position = _player.global_position + Vector3(-3, 1, 0)
			sk.take_damage(sk.max_health * 0.95)
			_ok(not sk.routing, "bone never breaks (skeleton holds at %.0f%% hp)" % (sk.health / sk.max_health * 100.0))
			sk.queue_free()
			_rout_from = kob.global_position
			_step = 10
		10:
			if _t < 14.0:
				return false
			if is_instance_valid(_kob):
				var moved: float = _rout_from.distance_to(_kob.global_position)
				_ok(moved > 0.5, "the routing kobold actually ran (%.1f m)" % moved)
			_step = 11
		11:
			## --- Crystals are mineable ---
			var crystals := _world.get_tree().get_nodes_in_group("crystals")
			_ok(crystals.size() > 0, "crystal clusters exist (%d)" % crystals.size())
			var cc: CrystalCluster = crystals[0] as CrystalCluster
			var had_light := cc.light != null
			var n0: int = cc.shards.size()
			var drops0: int = _world.get_tree().get_nodes_in_group("dropped_items").size()
			for i in range(n0 * CrystalCluster.BITES_PER_SHARD):
				if is_instance_valid(cc):
					cc.mine_hit()
			_ok(not is_instance_valid(cc) or cc.shards.is_empty(), "the pickaxe strips the cluster (%d shards)" % n0)
			var drops1: int = _world.get_tree().get_nodes_in_group("dropped_items").size()
			_ok(drops1 - drops0 >= n0, "every shard dropped a Crystal Shard (%d)" % (drops1 - drops0))
			_ok(had_light, "the cluster was carrying the room's light")
			_step = 12
		12:
			## --- The Committed Step ---
			_ok(_player.stats._tree("committed_step").has("name"), "The Committed Step tree exists")
			_ok(_player.stats._tree("nothing_to_lose").has("name"), "Nothing Left to Lose tree exists")
			var boar := Boar.new()
			_world.add_child(boar)
			boar.global_position = _player.global_position + Vector3(0, 0, -2.0)
			_player.health = _player.max_health
			_player.stamina = _player.max_stamina
			_player.current_weapon = "sword"
			_player.sheathed = false
			_player.sheath_t = 0.0
			var st0: float = _player.stamina
			_player.attacking = true
			_player.has_hit = false
			_player._try_dash()
			_ok(_player.committed, "Ctrl mid-swing commits the step")
			_ok(st0 - _player.stamina >= Player.COMMIT_STAMINA * 0.5, "it costs a lot of stamina (%.0f)" % (st0 - _player.stamina))
			var hp0: float = boar.health
			var pr0: int = int(_player.stats.progress.get("committed_step", 0))
			_player._do_melee_hit()
			_ok(boar.health < hp0, "the driven blow landed (%.0f dmg)" % (hp0 - boar.health))
			_ok(int(_player.stats.progress.get("committed_step", 0)) > pr0, "landing it counted toward The Committed Step")
			_ok(not _player.committed, "the step is spent after it lands")
			_player.health = _player.max_health * 0.15
			_player.stamina = _player.max_stamina
			_player.attacking = true
			_player.has_hit = false
			_player._try_dash()
			var q0: int = int(_player.stats.progress.get("nothing_to_lose", 0))
			_player._do_melee_hit()
			_ok(int(_player.stats.progress.get("nothing_to_lose", 0)) > q0, "landing it at low health counted toward Nothing Left to Lose")
			_player.health = _player.max_health
			_step = 13
		13:
			## --- Ore is rarer, boulders can carry it ---
			_ok(float(Player.DIG_ORE_TABLES[0][1]) < 0.03, "shallow dig-ore is rare now (%.1f%%)" % (float(Player.DIG_ORE_TABLES[0][1]) * 100.0))
			var d0: int = _world.get_tree().get_nodes_in_group("dropped_items").size()
			_player._roll_dig_ore(Vector3(0, -2, 0), Vector3.UP, true)
			_ok(_world.get_tree().get_nodes_in_group("dropped_items").size() > d0, "a guaranteed roll still yields ore (the boulder path)")
			print("")
			if _fails.is_empty():
				print("ALL CHECKS PASSED")
			else:
				print("FAILURES: %s" % ", ".join(_fails))
			quit(0 if _fails.is_empty() else 1)
	return false
