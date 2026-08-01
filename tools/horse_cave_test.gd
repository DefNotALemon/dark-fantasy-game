extends SceneTree
## Do loose horses keep away from cave mouths on their own?

var _t := 0.0
var _step := 0
var _w: Node
var _h: Horse
var _mouth := Vector3.ZERO
var _d0 := 0.0
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
	if _t < 2.0:
		return false
	match _step:
		0:
			var regs := root.get_tree().get_nodes_in_group("cave_regions")
			_ok(regs.size() > 0, "the cave region is findable by horses (%d)" % regs.size())
			_mouth = (regs[0].get("mouths") as Array)[0]
			## Drop a horse right beside the mouth — exactly where it shouldn't graze.
			_h = Horse.new()
			_w.add_child(_h)
			_h.global_position = _mouth + Vector3(4.0, 2.0, 0.0)
			## Mobs past 45 m of the player SLEEP (Enemy._physics_process) — park the
			## player close enough to keep this one ticking, outside its skittish radius.
			var p := root.get_tree().get_first_node_in_group("player")
			p.global_position = _mouth + Vector3(0, 3, 14)  ## near enough to keep it awake, far enough not to spook it
			_step = 1
		1:
			if _t < 4.0:
				return false
			_d0 = Vector2(_h.global_position.x - _mouth.x, _h.global_position.z - _mouth.z).length()
			_ok(_h._mouths.size() > 0, "the horse knows where the mouths are (%d)" % _h._mouths.size())
			_step = 2
		2:
			if _t < 26.0:
				return false
			var d1 := Vector2(_h.global_position.x - _mouth.x, _h.global_position.z - _mouth.z).length()
			_ok(d1 > _d0, "it walked AWAY from the mouth (%.1f m -> %.1f m)" % [_d0, d1])
			_ok(d1 > Horse.CAVE_SHUN_HARD, "it cleared the close zone (%.1f m > %.1f)" % [d1, Horse.CAVE_SHUN_HARD])
			_ok(_h.global_position.y > -1.0, "it never went down the throat (y = %.1f)" % _h.global_position.y)
			_ok(_h._panic_t <= 0.0, "and it never had to panic about it")
			print("")
			print("ALL CHECKS PASSED" if _fails.is_empty() else "FAILURES: " + ", ".join(_fails))
			quit(0 if _fails.is_empty() else 1)
	return false
