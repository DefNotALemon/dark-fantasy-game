extends SceneTree
## Can horses climb now? Loose (flight climb) and ridden (the scramble).

var _t := 0.0
var _step := 0
var _w: Node
var _h: Horse
var _wall: StaticBody3D
var _y0 := 0.0
var _frames := 0
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
			## A sheer test wall on open ground near spawn.
			_wall = StaticBody3D.new()
			_w.add_child(_wall)
			_wall.global_position = Vector3(8.0, 4.0, 6.0)
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(1.0, 8.0, 8.0)   ## a cliff face, facing -x
			cs.shape = box
			_wall.add_child(cs)
			_h = Horse.new()
			_w.add_child(_h)
			_h.global_position = Vector3(6.0, 0.6, 6.0)
			_h.set_physics_process(false)  ## the test drives the body by hand
			_ok(_h.can_climb, "horses can climb now")
			_ok(_h.climb_away, "and their climb is a FLIGHT climb (away from threats)")
			_ok(_h.climb_speed > 1.0, "at an honest haul (%.1f m/s)" % _h.climb_speed)
			_step = 1
		1:
			if _t < 3.0:
				return false
			## Settle onto the ground by hand first (manual driving means
			## is_on_floor() only becomes true after real move_and_slide()s).
			for _i in range(80):
				if _h.is_on_floor():
					break
				_h.velocity = Vector3(0, -3.0, 0)  ## steady sink, no buildup
				_h.move_and_slide()
			_ok(_h.is_on_floor(), "settled on its feet (y = %.2f)" % _h.global_position.y)
			## --- The ridden scramble: reins pressed into the face ---
			var dir := Vector3(1, 0, 0)  ## straight at the wall
			var got: bool = _h._try_scramble(dir)
			_ok(got, "reins into a steep face start the scramble")
			_ok(_h._scramble, "the horse is on the wall")
			_h.move_and_slide()  ## the grip frame — contact registers here (as in-game)
			_y0 = _h.global_position.y
			_frames = 0
			_step = 2
		2:
			## Drive the scramble by hand, on REAL frame time: reins held in.
			if _t < 6.5:
				if _h._scramble:
					_h._update_scramble(d, Vector3(1, 0, 0))
					_h.move_and_slide()
				return false
			var climbed: float = _h.global_position.y - _y0
			_ok(climbed > 3.0, "it hauled the wall (+%.1f m in ~3.5 s)" % climbed)
			_ok(_h.global_position.y > 2.5, "well off the ground (y = %.1f)" % _h.global_position.y)
			_step = 3
		3:
			## --- Easing off the reins lets go ---
			if _h._scramble:
				_h._update_scramble(1.0 / 30.0, Vector3.ZERO)  ## reins slack
			_ok(not _h._scramble, "slack reins detach the scramble")
			print("")
			print("ALL CHECKS PASSED" if _fails.is_empty() else "FAILURES: " + ", ".join(_fails))
			quit(0 if _fails.is_empty() else 1)
	return false
