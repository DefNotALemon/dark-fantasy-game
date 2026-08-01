extends SceneTree
## Headless checks: side-swinging axe, the item wheel, the health potion,
## the overburden fix, and the rucksack-as-capacity.

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
			## --- Potion ---
			var pidx: int = _p._find_item_index("Health Potion")
			_ok(pidx >= 0, "Health Potions are in the starting kit")
			_p.health = _p.max_health * 0.3
			var hp0: float = _p.health
			var n0: int = _p._count_item("Health Potion")
			_p._drink_potion(pidx)
			_ok(_p.health > hp0, "drinking heals (+%.0f)" % (_p.health - hp0))
			_ok(_p._count_item("Health Potion") == n0 - 1, "and consumes the draught")
			_p.health = _p.max_health
			var n1: int = _p._count_item("Health Potion")
			_p._drink_potion(_p._find_item_index("Health Potion"))
			_ok(_p._count_item("Health Potion") == n1, "refused at full health (not wasted)")
			_step = 1
		1:
			## --- The wheel ---
			_ok(_p.wheel.size() == 8, "the wheel has 8 seats")
			_ok(_p.wheel[0] == "Wooden Shield" and _p.wheel[1] == "Torch",
				"shield and torch ride it from the start")
			## Using the torch seat arms the offhand (move semantics).
			_p._set_offhand_pair("", "")
			_p._wheel_use(1)
			_ok(_p._slot_name("offhand") == "Torch", "selecting the torch seat arms the torch")
			_p._wheel_use(1)
			_ok(_p._slot_item("offhand").is_empty(), "selecting it again takes it back off")
			## Quick-add lands in the first free seat; duplicates are refused.
			_p._wheel_quick_add(_p._find_item_index("Arrow"))
			_ok(_p.wheel[4] == "Arrow", "quick-add takes the first free seat (5)")
			_p._wheel_quick_add(_p._find_item_index("Arrow"))
			var arrows := 0
			for nm in _p.wheel:
				if nm == "Arrow":
					arrows += 1
			_ok(arrows == 1, "an item rides ONE seat only")
			## Deliberate placement moves it.
			_p._wheel_assign_slot("Arrow", 7)
			_ok(_p.wheel[7] == "Arrow" and _p.wheel[4] == "", "hold-placement moves it to the chosen seat")
			## The potion seat heals through the wheel too.
			_p.health = _p.max_health * 0.4
			var hpw: float = _p.health
			_p._wheel_use(3)
			_ok(_p.health > hpw, "the potion seat drinks (+%.0f)" % (_p.health - hpw))
			_p.health = _p.max_health
			_step = 2
		2:
			## --- Overburden: named, and later to arrive ---
			_ok(PlayerStats.BASE_CARRY >= 90.0, "base carry raised to %.0f (was 60 — the 'sprint bug')" % PlayerStats.BASE_CARRY)
			_ok(_p.overload_label != null, "the overburdened HUD warning exists")
			_p._give_item("Rock", 200, 0.8)
			_step = 3
		3:
			if _t < 3.0:
				return false
			_ok(_p._was_overweight, "crossing the limit trips the named warning")
			var ridx: int = _p._find_item_index("Rock")
			if ridx >= 0:
				_p.inventory[ridx].count = 0
				_p._remove_inventory_index(ridx)
			_step = 4
		4:
			## --- Rucksack (now WORN on the Back slot) is the grid ---
			_ok(_p._backpack_capacity() == 27, "with the rucksack worn: 27 slots")
			_p._unequip_slot("back")
			_ok(_p._backpack_capacity() == 9, "taken off: pockets only (9)")
			_p._equip_from_pack(_p._find_item_index("Old Rucksack"), "back")
			_ok(_p._backpack_capacity() == 27, "worn again: 27")
			_ok(not _p._give_item_dict({"name": "Old Rucksack", "weight": 2.0, "count": 1,
				"slot": "back", "rows": 3}), "a second is refused — one back, one pack")
			_step = 5
		5:
			## --- The axe swings from the side ---
			_p.current_weapon = "axe"
			_p.stamina = _p.max_stamina
			_p.axe_side = 1
			_p._try_axe_swing()
			_ok(_p.axe_swinging and _p.axe_side == 0, "swing one: the FOREHAND sweep (side 0)")
			for _i in range(40):
				_p._update_axe(1.0 / 30.0)  ## run the whole authored arc — no crash = poses hold
			_ok(not _p.axe_swinging, "the sweep completes and settles to the carry")
			_p._try_axe_swing()
			_ok(_p.axe_side == 1, "swing two answers BACKHAND (side 1)")
			_p.axe_swinging = false
			_p.current_weapon = "sword"
			print("")
			print("ALL CHECKS PASSED" if _fails.is_empty() else "FAILURES: " + ", ".join(_fails))
			quit(0 if _fails.is_empty() else 1)
	return false
