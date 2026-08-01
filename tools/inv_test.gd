extends SceneTree
## Headless checks for TERRARIA-RULES equipment: slots are containers, the
## Back slot carries the grid, fresh starts are born dressed, saves round-trip.

var _t := 0.0
var _step := 0
var _w: Node
var _p: Node
var _fails: Array[String] = []

func _ok(c: bool, what: String) -> void:
	print(("  PASS  " if c else "  FAIL  ") + what)
	if not c:
		_fails.append(what)

func _initialize() -> void:
	_w = (load("res://scenes/World.tscn") as PackedScene).instantiate()
	root.add_child(_w)

func _process(d: float) -> bool:
	_t += d
	if _t < 1.5:
		return false
	match _step:
		0:
			_p = root.get_tree().get_first_node_in_group("player")
			## --- Born dressed: clothing starts IN its slots, not the grid ---
			_ok(_p._slot_name("sword") == "Iron Sword", "the iron sword starts in the hand slot")
			_ok(_p._slot_name("helmet") == "Rusty Helmet", "the helmet starts on the head")
			_ok(_p._slot_name("chest") == "Leather Chestpiece", "the chest starts on the chest")
			_ok(_p._slot_name("back") == "Old Rucksack", "the rucksack starts WORN on the Back slot")
			_ok(_p._find_item_index("Iron Sword") < 0 and _p._find_item_index("Rusty Helmet") < 0,
				"and none of the worn things sit in the grid")
			_ok(_p.inventory.size() == 7, "the grid holds just the packed kit (%d stacks)" % _p.inventory.size())
			_step = 1
		1:
			## --- The Back slot IS the capacity ---
			_ok(_p._backpack_capacity() == 27, "rucksack worn: 27 slots")
			_ok(_p._unequip_slot("back"), "it can be taken off (into the grid)")
			_ok(_p._find_item_index("Old Rucksack") >= 0, "now it sits in the grid")
			_ok(_p._backpack_capacity() == 9, "bare back: 9 pocket slots (owning it is not wearing it)")
			_ok(_p._equip_from_pack(_p._find_item_index("Old Rucksack"), "back"), "and it goes back on")
			_ok(_p._backpack_capacity() == 27, "27 again")
			_ok(not _p._give_item_dict({"name": "Old Rucksack", "weight": 2.0, "count": 1,
				"slot": "back", "rows": 3}), "a second rucksack is refused while one is worn")
			_step = 2
		2:
			## --- Equip = move; unequip = move back; swap keeps both ---
			var n0: int = _p.inventory.size()
			_ok(_p._unequip_slot("helmet"), "the helmet comes off")
			_ok(_p._slot_item("helmet").is_empty(), "the head slot is empty")
			_ok(_p._find_item_index("Rusty Helmet") >= 0, "the helmet is a grid item now")
			_ok(_p.inventory.size() == n0 + 1, "grid grew by one")
			_p._item_clicked(_p._find_item_index("Rusty Helmet"))
			_ok(_p._slot_name("helmet") == "Rusty Helmet", "clicking it puts it back on")
			_ok(_p._find_item_index("Rusty Helmet") < 0, "and it LEFT the grid")
			## Sword swap: a steel blade trades places with the iron one.
			_p._give_item_dict({"name": "Steel Sword", "weight": 3.4, "count": 1,
				"slot": "sword", "material": "steel"})
			_p._item_clicked(_p._find_item_index("Steel Sword"))
			_ok(_p._slot_name("sword") == "Steel Sword", "clicking a grid sword wields it")
			_ok(_p._find_item_index("Iron Sword") >= 0, "the old blade landed back in the grid")
			_ok(not _p._unequip_slot("sword"), "the main hand refuses to empty")
			_step = 3
		3:
			## --- The offhand pair through move semantics ---
			_p._item_clicked(_p._find_item_index("Wooden Shield"))
			_ok(_p._slot_name("offhand") == "Wooden Shield", "the shield takes the hand")
			_p._item_clicked(_p._find_item_index("Torch"))
			_ok(_p._slot_name("offhand2") == "Torch", "the torch joins the same arm")
			_ok(_p._find_item_index("Wooden Shield") < 0 and _p._find_item_index("Torch") < 0,
				"both left the grid")
			_ok(_p._unequip_slot("offhand"), "the shield comes off")
			_ok(_p._slot_name("offhand") == "Torch" and _p._slot_item("offhand2").is_empty(),
				"the torch slides up to the main berth")
			_step = 4
		4:
			## --- Worn weight counts (at half) ---
			var w: float = _p._total_weight()
			_p._unequip_slot("chest")
			_ok(_p._total_weight() > w, "unequipping to the grid RAISES carried weight (half->full)")
			_p._item_clicked(_p._find_item_index("Leather Chestpiece"))
			_step = 5
		5:
			## --- Save / load round-trips the slots exactly as left ---
			_p._unequip_slot("helmet")  ## leave the head deliberately bare
			var err: String = SaveGame.save_game(_p)
			_ok(err == "", "saved mid-arrangement")
			## Scramble everything wearable.
			_p._item_clicked(_p._find_item_index("Rusty Helmet"))
			_p._unequip_slot("offhand")
			_p._unequip_slot("back")
			_step = 6
		6:
			if _t < 4.5:
				return false
			var err: String = SaveGame.load_game(_p)
			_ok(err == "", "loaded")
			_ok(_p._slot_item("helmet").is_empty(), "the bare head came back bare")
			_ok(_p._find_item_index("Rusty Helmet") >= 0, "with the helmet in the grid where it was left")
			_ok(_p._slot_name("sword") == "Steel Sword", "the steel sword is still wielded")
			_ok(_p._slot_name("offhand") == "Torch", "the torch is still on the arm")
			_ok(_p._slot_name("back") == "Old Rucksack", "the rucksack is still worn")
			_ok(_p._backpack_capacity() == 27, "and the grid is still 27")
			_step = 7
		7:
			if _t < 6.0:
				return false
			## --- A v1-shaped save (equipment as grid indices) migrates ---
			_p.apply_state({
				"pos": _p.global_position, "health": 80.0, "stamina": 90.0,
				"inventory": [
					{"name": "Rusty Helmet", "weight": 4.0, "count": 1, "slot": "helmet"},
					{"name": "Old Rucksack", "weight": 2.0, "count": 1, "slot": ""},
					{"name": "Torch", "weight": 1.0, "count": 1, "slot": "offhand"},
				],
				"equipment": {"helmet": 0, "sword": -1},
			})
			_ok(_p._slot_name("helmet") == "Rusty Helmet", "v1 save: indexed helmet migrated onto the head")
			_ok(_p._find_item_index("Rusty Helmet") < 0, "and was stripped from the grid")
			_ok(_p._slot_name("back") == "Old Rucksack", "v1 save: the grid rucksack got worn")
			_ok(_p._slot_name("sword") == "Iron Sword", "the main hand backfilled — never empty")
			print("")
			print("ALL CHECKS PASSED" if _fails.is_empty() else "FAILURES: " + ", ".join(_fails))
			quit(0 if _fails.is_empty() else 1)
	return false
