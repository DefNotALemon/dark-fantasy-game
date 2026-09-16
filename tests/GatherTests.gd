extends SceneTree
## ===========================================================================
## GatherTests.gd -- HOLD E TAKES THE WHOLE PILE.
##
##   godot --headless --path . --script res://tests/GatherTests.gd
##
## Lemon 2026-09-14: "when you're looking at a stackable item next to a bunch
## of other item's of the same kind, you can hold e to pick them all up at
## once".
##
## What is actually asserted here: that the tap still takes exactly one; that
## the hold takes the pile NEAREST FIRST and stops at the edge of it; that
## "the same kind" means name AND material, so the iron in a heap does not
## drag the silver in with it; that the thing already travelling up the
## reaching arm is never ALSO swept (the duplication this feature invites);
## that a full rucksack stops the sweep instead of eating the pile; and that
## every swept node leaves its gatherable group on the same frame it is
## counted in, which is the other way one item becomes two.
##
## The real Player is built here, not a stub -- the sweep reads the live
## inventory, the live capacity and the live groups, and a stub would only
## prove the stub. Everything runs on frame two, once add_child has actually
## put the nodes in the tree.
## ===========================================================================

var _pass := 0
var _fail := 0
const MIN_ASSERTIONS := 40
var _frames := 0
var _p: Player


func ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: %s" % what)


func _initialize() -> void:
	print("GatherTests")
	_p = Player.new()
	root.add_child(_p)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false          ## let the Player actually enter the tree
	_p.global_position = Vector3.ZERO
	_test_pile()
	_test_material()
	_test_reach_node()
	_test_full_pack()
	_test_hold_window()
	_test_fly_home()
	print("GatherTests: %d passed, %d failed" % [_pass, _fail])
	ok(_pass + _fail >= MIN_ASSERTIONS, "the suite still has its assertions")
	if _fail > 0:
		print("GATHER TESTS FAILED")
	else:
		print("GATHER TESTS PASSED")
	return true


## --------------------------- fixtures -------------------------------------


func _drop(nm: String, at: Vector3, mat := "") -> DroppedItem:
	var di := DroppedItem.make({"name": nm, "weight": 0.5, "count": 1,
		"slot": "", "material": mat, "keep": true})
	root.add_child(di)
	di.global_position = at
	return di


func _clear_drops() -> void:
	for n in root.get_tree().get_nodes_in_group("dropped_items"):
		n.get_parent().remove_child(n)
		n.queue_free()


func _sweep(nm: String, mat: String) -> int:
	## Run the sweep to exhaustion the way a long hold would, and say how many
	## it took. No timers: _gather_one is the beat, the clock only spaces it.
	_p._gather_name = nm
	_p._gather_mat = mat
	_p._gather_kind = "item"
	var n := 0
	while _p._gather_one() and n < 200:
		n += 1
	return n


## ------------------------- the pile itself --------------------------------


func _test_pile() -> void:
	_clear_drops()
	_p.inventory.clear()
	var pile: Array[DroppedItem] = []
	for i in range(5):
		pile.append(_drop("Rock", Vector3(0.6 + 0.3 * i, 0.0, 0.0)))
	var wood := _drop("Wood", Vector3(1.0, 0.0, 0.4))
	var far := _drop("Rock", Vector3(40.0, 0.0, 0.0))

	_p._drop_target = pile[0]
	ok(_p._pile_count() == 5, "the prompt counts the five rocks at your feet (%d)"
		% _p._pile_count())
	ok(Player.GATHER_RADIUS < 40.0, "and a pile is a pile, not the whole meadow")

	## THE TAP is unchanged: one press, one rock.
	_p._pickup_dropped(pile[0])
	ok(_p._count_item("Rock") == 1, "a tap takes exactly one")
	ok(pile[0].is_queued_for_deletion(), "and that one is gone from the ground")

	## THE HOLD takes what is left of the same kind.
	var took := _sweep("Rock", "")
	ok(took == 4, "the hold sweeps up the other four (%d)" % took)
	ok(_p._count_item("Rock") == 5, "five rocks in one stack (%d)" % _p._count_item("Rock"))
	ok(_p.inventory.size() == 1, "one stack, not five entries (%d)" % _p.inventory.size())
	ok(wood.gather_to == null and wood.is_in_group("dropped_items"),
		"the log lying in the same heap is NOT rock and stays on the ground")
	ok(far.gather_to == null, "and the rock forty metres off is somebody else's")
	for i in range(1, 5):
		ok(not pile[i].is_in_group("dropped_items"),
			"swept rock %d left the group on the frame it was counted" % i)
		ok(pile[i].gather_to == _p, "and is flying to the pack, not blinking out")


## ------------------- same name, different metal ---------------------------


func _test_material() -> void:
	_clear_drops()
	_p.inventory.clear()
	for i in range(3):
		_drop("Sword", Vector3(0.5 + 0.2 * i, 0.0, 0.0), "iron")
	var silver := _drop("Sword", Vector3(0.5, 0.0, 0.5), "silver")
	var took := _sweep("Sword", "iron")
	ok(took == 3, "three iron swords come in (%d)" % took)
	ok(silver.gather_to == null and silver.is_in_group("dropped_items"),
		"the silver one in the same heap is a DIFFERENT kind and is left lying")


## ---------------- the thing already in the hand ---------------------------


func _test_reach_node() -> void:
	## The bug this whole feature invites: the tap starts the reach, the node
	## is still out in the world and still in the group for the length of the
	## animation, and the sweep running underneath it takes it a second time.
	_clear_drops()
	_p.inventory.clear()
	var a := _drop("Rock", Vector3(0.6, 0.0, 0.0))
	var b := _drop("Rock", Vector3(0.9, 0.0, 0.0))
	_p.reach_node = a
	var took := _sweep("Rock", "")
	_p.reach_node = null
	ok(took == 1, "the sweep takes only the one that is not in the hand (%d)" % took)
	ok(a.gather_to == null and a.is_in_group("dropped_items"),
		"the reaching hand keeps its own rock -- no second copy")
	ok(b.gather_to != null, "and the other one comes in")
	ok(_p._count_item("Rock") == 1, "one rock counted, not two (%d)" % _p._count_item("Rock"))


## ------------------------ a full rucksack ---------------------------------


func _test_full_pack() -> void:
	_clear_drops()
	_p.inventory.clear()
	for i in range(_p._backpack_capacity()):
		_p.inventory.append({"name": "Filler %d" % i, "weight": 0.1, "count": 1,
			"slot": "", "material": ""})
	var before := _p.inventory.size()
	for i in range(4):
		_drop("Rock", Vector3(0.6 + 0.2 * i, 0.0, 0.0))
	var took := _sweep("Rock", "")
	ok(took == 0, "a full pack takes none of the pile (%d)" % took)
	ok(_p.inventory.size() == before, "and the grid did not grow (%d -> %d)"
		% [before, _p.inventory.size()])
	for n in root.get_tree().get_nodes_in_group("dropped_items"):
		ok((n as DroppedItem).gather_to == null, "every rock is still lying there")
	_p.inventory.clear()


## ------------------- tap window vs. hold window ---------------------------


func _test_hold_window() -> void:
	_clear_drops()
	_p.inventory.clear()
	for i in range(3):
		_drop("Rock", Vector3(0.6 + 0.2 * i, 0.0, 0.0))
	_p._drop_target = null
	_p._debris_target = null
	_p._gather_arm()
	ok(_p._e_held, "E down arms the sweep")
	ok(_p._gather_kind == "", "but with nothing under the gaze there is nothing to sweep")

	_p._drop_target = root.get_tree().get_nodes_in_group("dropped_items")[0] as DroppedItem
	_p._gather_arm()
	ok(_p._gather_kind == "item" and _p._gather_name == "Rock",
		"looking at a rock, E down remembers rock")
	_p._update_gather(0.016)
	ok(_p._count_item("Rock") == 0, "a third of a second has not passed -- a tap is still a tap")
	_p._e_down_ms -= int(Player.GATHER_HOLD * 1000.0) + 50
	_p._update_gather(1.0)
	ok(_p._count_item("Rock") == 1, "held past the window, the pile starts coming in")
	_p._gather_stop()
	ok(not _p._e_held and _p._gather_kind == "", "letting go ends it")
	_p._update_gather(1.0)
	ok(_p._count_item("Rock") == 1, "and nothing else follows you home (%d)"
		% _p._count_item("Rock"))

	## A menu opening mid-hold ends it too.
	_p._drop_target = root.get_tree().get_nodes_in_group("dropped_items")[0] as DroppedItem
	_p._gather_arm()
	ok(_p._gather_kind == "item", "armed again over what is left of the pile")
	_p._e_down_ms -= int(Player.GATHER_HOLD * 1000.0) + 50
	_p.menu_open = "tab"
	_p._update_gather(1.0)
	_p.menu_open = ""
	ok(not _p._e_held, "opening the rucksack mid-sweep stops the sweep")


## ------------------------- the flight home --------------------------------


func _test_fly_home() -> void:
	_clear_drops()
	_p.inventory.clear()
	var di := _drop("Rock", Vector3(0.6, 0.0, 0.0))
	di.gather_fly(_p)
	ok(not di.is_in_group("dropped_items"), "a gathered item leaves the group at once")
	di._fly_home(0.10)
	ok(not di.is_queued_for_deletion(), "it is still on its way after a tenth of a second")
	ok(di.scale.x < 1.0, "shrinking as it goes")
	di._fly_home(DroppedItem.GATHER_FLY)
	ok(di.is_queued_for_deletion(), "and it is gone when it reaches the pack")

	var rd := RockDebris.make(Vector3(0.6, 0.0, 0.0), Vector3.ZERO)
	root.add_child(rd)
	rd.landed = true
	rd.gather_fly(_p)
	ok(not rd.is_in_group("debris"), "a gathered chunk of rock leaves the debris group")
	rd._fly_home(RockDebris.GATHER_FLY)
	ok(rd.is_queued_for_deletion(), "and frees itself at the pack")
