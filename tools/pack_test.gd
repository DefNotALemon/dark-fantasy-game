extends SceneTree
## Headless checks: the action-camera layer, the rummage animation, the
## rucksack on the back, the strapped bedroll bundle, and the one-bed rule.

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
			## --- The action layer sits between arm and lens ---
			_ok(_p.cam_anim != null, "cam_anim exists")
			_ok(_p.camera.get_parent() == _p.cam_anim, "camera hangs off the action layer")
			_ok(_p.cam_anim.get_parent() == _p.cam_arm, "which hangs off the arm")
			## --- Swings lean the lens (and the body) ---
			_p.attacking = true
			_p.current_weapon = "sword"
			_p.combo_index = 1
			_p.swing_t = 0.30  ## deep in the carry-across
			for _i in range(24):
				_p._update_action_camera(1.0 / 60.0)
			var roll1: float = absf(_p.cam_anim.rotation_degrees.z)
			_ok(roll1 > 1.0,
				"a sword swing carries the camera ACROSS (%.2f deg)" % _p.cam_anim.rotation_degrees.z)
			_ok(absf(_p.body_rig.rotation_degrees.z) > 0.4,
				"and leans the visible body with it (%.2f deg)" % _p.body_rig.rotation_degrees.z)
			## The chain RAMPS: swing two leans harder than swing one.
			_p.combo_index = 2
			for _i in range(30):
				_p._update_action_camera(1.0 / 60.0)
			var roll2: float = absf(_p.cam_anim.rotation_degrees.z)
			_ok(roll2 > roll1 * 1.2,
				"each swing ramps the lean (%.2f -> %.2f deg)" % [roll1, roll2])
			_p.attacking = false
			_p.swing_t = 0.0
			## --- Impact punch ---
			_p.cam_punch = 1.0
			for _i in range(4):
				_p._update_action_camera(1.0 / 60.0)
			_ok(_p.cam_anim.rotation_degrees.x > 0.15, "a landed hit punches the lens forward")
			for _i in range(120):
				_p._update_action_camera(1.0 / 60.0)
			_ok(absf(_p.cam_anim.rotation_degrees.x) < 0.4, "and it settles back to rest")
			_step = 1
		1:
			## --- The rucksack itself ---
			_ok(_p.pack_rig != null and _p.pack_rig.get_child_count() >= 6,
				"the rucksack rides the back (%d parts)" % _p.pack_rig.get_child_count())
			_ok(_p._slot_name("back") == "Old Rucksack", "the Old Rucksack starts WORN (Back slot)")
			_ok(_p.pack_rig.visible, "and shows on the back")
			_p._unequip_slot("back")
			var ridx: int = _p._find_item_index("Old Rucksack")
			_p._drop_item(ridx)
			_ok(_p._find_item_index("Old Rucksack") >= 0, "in the grid it still can't be dropped")
			_p._equip_from_pack(_p._find_item_index("Old Rucksack"), "back")
			## --- The bedroll bundle + the one-bed rule ---
			_ok(not _p.bedroll_bundle.visible, "no bedroll owned = bare lashing spot")
			_ok(_p._give_item("Bedroll", 1, 4.0), "packing a bedroll works")
			_p._frame_fx_and_regen(0.016)
			_ok(_p.bedroll_bundle.visible, "the roll straps onto the rucksack, visibly")
			_ok(not _p._give_item("Bedroll", 1, 4.0), "a SECOND bedroll is refused")
			_ok(_p._count_item("Bedroll") == 1, "one bed, and only one")
			_step = 2
		2:
			## --- The rummage: hands into the pack when the inventory opens ---
			_p._open_tab_menu("inventory")
			_step = 3
		3:
			if _t < 4.0:
				return false
			_ok(_p.pack_reach > 0.6, "opening the pack starts the rummage (%.2f)" % _p.pack_reach)
			_ok(_p.cam_anim.rotation_degrees.x > 2.0,
				"the eyes drop to the satchel (%.1f deg)" % _p.cam_anim.rotation_degrees.x)
			_ok(_p.hands_root.position.y < -0.15,
				"the hands leave the frame (y %.2f)" % _p.hands_root.position.y)
			_p._close_menu()
			_step = 4
		4:
			if _t < 6.5:
				return false
			_ok(_p.pack_reach < 0.1, "closing it brings the hands back (%.2f)" % _p.pack_reach)
			_ok(absf(_p.hands_root.position.y) < 0.08, "hands home again")
			print("")
			print("ALL CHECKS PASSED" if _fails.is_empty() else "FAILURES: " + ", ".join(_fails))
			quit(0 if _fails.is_empty() else 1)
	return false
