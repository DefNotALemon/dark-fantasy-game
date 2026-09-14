extends SceneTree
## ===========================================================================
## HeldTests.gd -- EVERY THING IS HOLDABLE, AND A SKULL IS A HELM.
##
##   godot --headless --path . --script res://tests/HeldTests.gd
##
## Lemon 2026-09-14: "can you make all the items holdable, as an item fairly
## large but still in the players hand (every item). can you also make the
## bear skull equipable on the head".
##
## What is asserted here: that a click on plain loot puts ONE unit of it in
## the right fist and the rest stays in the grid (the pack's weight does not
## change -- it moved, it did not vanish); that a right-click holds ANYTHING,
## potion or blade; that the held look is the thing's own DroppedItem look,
## out of the loot group (the gaze must never target your own hand), sized
## between HELD_MIN_M and HELD_MAX_M whatever it was on the ground, and turned
## to point forward when it was built lying along +X; that steel, a tool or
## the bow takes the hand back and the thing goes home to the pack by itself;
## that holding another thing swaps, that the doll's hand row puts it away,
## that a save carries it; that a skull wears the helmet slot straight off
## the carcass, sits on the head as a skull and not as the iron cap, and is
## worth a little; and that B-dropping a skull drops a SKULL, not a cap.
##
## The real Player is built here, not a stub, for the same reason GatherTests
## builds one: a stub would only prove the stub. Everything runs on frame two.
## ===========================================================================

var _pass := 0
var _fail := 0
const MIN_ASSERTIONS := 45
var _frames := 0
var _p: Player


func ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: %s" % what)


func near_f(a: float, b: float, tol: float, what: String) -> void:
	ok(absf(a - b) <= tol, "%s (got %.4f, want %.4f +/- %.4f)" % [what, a, b, tol])


func _initialize() -> void:
	print("HeldTests")
	_p = Player.new()
	root.add_child(_p)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false          ## let the Player actually enter the tree
	_p.global_position = Vector3.ZERO
	_test_hold_plain()
	_test_hold_anything()
	_test_sized_to_read()
	_test_hand_taken_back()
	_test_swap_and_stow()
	_test_save()
	_test_skull_is_a_helm()
	_test_skull_off_the_carcass()
	_test_drop_keeps_the_dict()
	print("HeldTests: %d passed, %d failed" % [_pass, _fail])
	ok(_pass + _fail >= MIN_ASSERTIONS, "the suite still has its assertions")
	if _fail > 0:
		print("HELD TESTS FAILED")
	else:
		print("HELD TESTS PASSED")
	quit(1 if _fail > 0 else 0)
	return true


## --------------------------- fixtures -------------------------------------


func _give(nm: String, n: int, weight := 0.8, slot := "", extra := {}) -> int:
	var d := {"name": nm, "weight": weight, "count": n, "slot": slot}
	for k in extra:
		d[k] = extra[k]
	_p._give_item_dict(d, true)
	return _p._find_item_index(nm)


func _reset() -> void:
	_p._stow_held("")
	_p.inventory.clear()
	_p.current_weapon = "sword"
	_p.sheathed = false
	_p.sheath_t = 0.0


func _skull() -> Dictionary:
	## exactly what CarcassBody._make_bone hands a bear's skull to the pack as
	return {"name": "Bear Skull", "weight": 0.8, "count": 1, "slot": "helmet",
		"protect": 0.03, "keep": true, "bone": "skull",
		"bone_len": 0.35, "bone_r": 0.05, "bone_w": 0.32}


func _longest(look: Node3D) -> float:
	var box := _p._look_aabb(look)
	return maxf(box.size.x, maxf(box.size.y, box.size.z))


## ------------------------------- holding ----------------------------------


func _test_hold_plain() -> void:
	_reset()
	var idx := _give("Rock", 3)
	var w0 := _p._total_weight()
	_p._item_clicked(idx)
	ok(_p._holding(), "click plain loot and it is in your hand")
	ok(String(_p.held_item.get("name", "")) == "Rock", "the rock")
	ok(int(_p.held_item.get("count", 0)) == 1, "one of them")
	ok(_p._count_item("Rock") == 2, "and two stay in the grid (%d)" % _p._count_item("Rock"))
	near_f(_p._total_weight(), w0, 1e-6, "nothing vanished: the pack weighs the same")
	ok(_p.sheathed and _p.current_weapon == "sword", "the sword rides the hip while you hold it")
	ok(_p.held_vm_look != null and is_instance_valid(_p.held_vm_look), "a first-person look was built")
	ok(_p.tp_held != null and _p.tp_held.get_child_count() == 1, "and a third-person twin on the body's fist")
	var di := _p.held_vm_look.get_child(0)
	ok(di is DroppedItem, "the look IS the thing's own DroppedItem look")
	ok(not (di as Node).is_in_group("dropped_items"), "but OUT of the loot group: the gaze cannot take your own hand")
	ok(not (di as Node).is_physics_processing(), "and it does not fall")
	_p.sheath_t = 1.0
	_p._update_held(0.016)
	ok(_p.held_vm.visible, "shown once the blade is home")
	## the same thing again puts it away
	_p._item_clicked(_p._find_item_index("Rock"))
	ok(not _p._holding(), "click the rock again and it goes back")
	ok(_p._count_item("Rock") == 3, "all three in the grid (%d)" % _p._count_item("Rock"))
	ok(_p.held_vm_look == null, "and the look is gone")


func _test_hold_anything() -> void:
	_reset()
	## a potion's click DRINKS; right-click holds it anyway
	var idx := _give("Health Potion", 2)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	_p._cell_gui_input(ev, idx)
	ok(String(_p.held_item.get("name", "")) == "Health Potion", "right-click holds a potion")
	ok(_p._count_item("Health Potion") == 1, "one stays in the grid")
	## and steel: a spare sword in the grid, right-clicked, is a held sword
	_p._stow_held("")
	var si := _give("Iron Sword", 1, 3.0, "sword", {"material": "iron"})
	_p._cell_gui_input(ev, si)
	ok(String(_p.held_item.get("name", "")) == "Iron Sword", "right-click holds a spare blade like a stick")
	ok(_p._slot_name("sword") != "", "and the wielded one stays in its slot")
	## a left-click on it would have EQUIPPED it: the two verbs stay apart
	_p._stow_held("")
	var si2 := _p._find_item_index("Iron Sword")
	ok(si2 >= 0, "the spare is back in the grid")


func _test_sized_to_read() -> void:
	_reset()
	## a LOG is over a metre on the ground; in the fist it is HELD_MAX_M
	var li := _give("Log", 1, 9.0, "", {"keep": true, "log_r": 0.22, "log_len": 1.05, "species": ""})
	_p._hold_from_pack(li)
	var look := _p.held_vm_look
	near_f(_longest(look), Player.HELD_MAX_M, 0.01, "a log shrinks to the hand")
	ok(absf(look.rotation_degrees.y - (90.0 + Player.HELD_TURN)) < 0.01,
		"and turns forward and toward the middle of the view, so you see its length")
	## a nothing-sized thing grows to HELD_MIN_M
	_p._stow_held("")
	var fi := _give("Feather", 1, 0.02)
	_p._hold_from_pack(fi)
	near_f(_longest(_p.held_vm_look), Player.HELD_MIN_M, 0.01, "a feather grows to be seen")
	## a skull is already a fistful: it keeps its size
	_p._stow_held("")
	_p._give_item_dict(_skull(), true)
	_p._hold_from_pack(_p._find_item_index("Bear Skull"))
	var sl := _longest(_p.held_vm_look)
	ok(sl > Player.HELD_MIN_M and sl < Player.HELD_MAX_M, "a bear skull is held at its own size (%.2f m)" % sl)
	ok(Player.HELD_MAX_M < 0.6 and Player.HELD_MIN_M > 0.15, "fairly large, still in a hand")
	_p._stow_held("")


func _test_hand_taken_back() -> void:
	_reset()
	var idx := _give("Rock", 2)
	_p._hold_from_pack(idx)
	ok(_p._holding(), "holding")
	_p.sheathed = false      ## the hunch, a draw-slash, a guard, the saddle: all land here
	_p._update_held(0.016)
	ok(not _p._holding(), "draw steel and the thing goes home by itself")
	ok(_p._count_item("Rock") == 2, "back in the grid, both of them")
	_p._hold_from_pack(_p._find_item_index("Rock"))
	_p._select_weapon("pickaxe")
	_p._update_held(0.016)
	ok(not _p._holding(), "a tool takes the hand back too")
	_p._select_weapon("sword")
	_p._hold_from_pack(_p._find_item_index("Rock"))
	ok(_p._holding() and _p.sheathed, "and holding puts the sword back on the hip")


func _test_swap_and_stow() -> void:
	_reset()
	var ri := _give("Rock", 1)
	_give("Stick", 1)
	_p._hold_from_pack(ri)
	ok(_p._count_item("Rock") == 0, "the only rock left the grid")
	_p._hold_from_pack(_p._find_item_index("Stick"))
	ok(String(_p.held_item.get("name", "")) == "Stick", "holding something else swaps")
	ok(_p._count_item("Rock") == 1, "and the rock went back, not into nothing")
	_p._stow_held("")
	ok(not _p._holding() and _p._count_item("Stick") == 1, "the hand row puts it away")
	## the weight of a held thing is carried in FULL, worn gear at half
	var w0 := _p._total_weight()
	_p._hold_from_pack(_p._find_item_index("Stick"))
	near_f(_p._total_weight(), w0, 1e-6, "a thing in the fist weighs what it weighed in the pack")
	_p._stow_held("")


func _test_save() -> void:
	_reset()
	_p._hold_from_pack(_give("Rock", 2))
	var d := _p.save_state()
	ok(String((d.get("held", {}) as Dictionary).get("name", "")) == "Rock", "the save says what is in your hand")
	_p.held_item = {}
	_p._clear_held_visuals()
	_p.apply_state(d)
	ok(String(_p.held_item.get("name", "")) == "Rock", "and a load puts it back in the hand")
	ok(_p.held_vm_look != null and _p.tp_held.get_child_count() == 1, "with its looks rebuilt")
	ok(_p.sheathed and _p.current_weapon == "sword", "sword on the hip, as it was")
	var d2 := d.duplicate(true)
	d2.erase("held")
	_p.apply_state(d2)
	ok(not _p._holding(), "an older save without a hand berth loads empty-handed")


## ------------------------------- the skull --------------------------------


func _test_skull_is_a_helm() -> void:
	_reset()
	_p._doll_clicked("helmet")   ## whatever the kit wears comes off first
	_p._give_item_dict(_skull(), true)
	var idx := _p._find_item_index("Bear Skull")
	ok(idx >= 0 and String(_p.inventory[idx].get("slot", "")) == "helmet", "a skull carries the helmet slot")
	var m0 := _p._armor_mult()
	_p._item_clicked(idx)
	ok(_p._slot_name("helmet") == "Bear Skull", "click it and it is on your head")
	ok(_p.tp_skull != null and is_instance_valid(_p.tp_skull) and _p.tp_skull.get_child_count() == 1,
		"worn as a skull on the body's head")
	ok(_p.tp_helm != null and not _p.tp_helm.visible, "and NOT as the iron cap")
	var hair_hidden := true
	for hm in _p.hair_meshes:
		if (hm as MeshInstance3D).visible:
			hair_hidden = false
	ok(hair_hidden, "the hair tucks under it like under any helm")
	near_f(_p._armor_mult(), m0 - 0.03, 1e-6, "and it is worth three per cent of bone")
	## it comes off the doll like anything worn
	_p._doll_clicked("helmet")
	ok(_p._slot_name("helmet") == "", "click the doll row and it is off")
	ok(_p.tp_skull == null, "the worn skull is gone")
	ok(_p._count_item("Bear Skull") == 1, "and back in the grid")
	near_f(_p._armor_mult(), m0, 1e-6, "protection back to what it was")
	## a skull on the ground is a skull, whatever berth it fits
	var di := DroppedItem.make(_skull())
	var boxes := 0
	for c in di.get_children():
		if c is MeshInstance3D:
			boxes += 1
	ok(boxes == 5, "DroppedItem draws a helmet-slot skull as a skull (%d boxes, the cap is 2)" % boxes)
	di.free()


func _test_skull_off_the_carcass() -> void:
	## The carcass hands the skull over already wearing the helmet slot -- and
	## ONLY the skull. Built through the real bus and a real bear.
	var c := Carcasses.new()
	root.add_child(c)
	c.player = _p
	var mass := Carcasses.mass_of("black_bear", 1.7)
	var rec := c.add("black_bear", "black bear", Vector3(3.0, 0.0, 0.0), mass)
	rec["left"] = mass * 0.10
	c._restage()
	var body: Node3D = c._staged.get(int(rec["id"]), null)
	ok(body != null, "a bear at the bones stage is a body")
	if body != null:
		var bones: Dictionary = body.get("bones")
		var skull := bones.get("skull", null) as DroppedItem
		ok(skull != null and String(skull.item.get("slot", "")) == "helmet", "its skull wears the helmet slot")
		ok(skull != null and absf(float(skull.item.get("protect", 0.0)) - 0.03) < 1e-6, "and says what it is worth")
		var ribs := bones.get("ribs", null) as DroppedItem
		ok(ribs != null and String(ribs.item.get("slot", "")) == "", "the ribs are plain loot")
		var leg := bones.get("leg0_u", null) as DroppedItem
		ok(leg != null and String(leg.item.get("slot", "")) == "", "and so is a leg bone")
		## picked up, it is the same dict -- and a click wears it
		if skull != null:
			_reset()
			_p._doll_clicked("helmet")
			_p._pickup_dropped(skull)
			var idx := _p._find_item_index("Bear Skull")
			ok(idx >= 0, "picked up off the carcass")
			_p._item_clicked(idx)
			ok(_p._slot_name("helmet") == "Bear Skull" and _p.tp_skull != null, "and worn straight from the ground")
			_p._doll_clicked("helmet")
	c.free()


func _test_drop_keeps_the_dict() -> void:
	_reset()
	_p._give_item_dict(_skull(), true)
	var before := root.get_tree().get_nodes_in_group("dropped_items").size()
	_p._drop_item(_p._find_item_index("Bear Skull"))
	var found: DroppedItem = null
	for n in root.get_tree().get_nodes_in_group("dropped_items"):
		var di := n as DroppedItem
		if di != null and String(di.item.get("name", "")) == "Bear Skull":
			found = di
	ok(found != null, "B drops the skull on the ground (%d -> %d loot nodes)"
		% [before, root.get_tree().get_nodes_in_group("dropped_items").size()])
	ok(found != null and found.item.has("bone") and String(found.item.get("slot", "")) == "helmet",
		"and it is still a skull that fits a head, not five keys of nothing")
	if found != null:
		found.queue_free()
