extends SceneTree
## ===========================================================================
## StanceTests.gd -- crouch and prone actually pose the body.
##
##   godot --headless --path . --script res://tests/StanceTests.gd
##
## The camera has always dropped with C / X. This suite holds the visible
## body to it: knees, a hip drop, a belly-down pitch, and a crawl cycle.
## The real Player is built, not a stub — the pivots only exist after
## _build_body, and CreatureSkin.bake has to still succeed with the new knees.
## ===========================================================================

var _pass := 0
var _fail := 0
const MIN_ASSERTIONS := 22
var _frames := 0
var _p: Player


func ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: %s" % what)


func _initialize() -> void:
	print("StanceTests")
	_p = Player.new()
	root.add_child(_p)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false
	_test_rig()
	_test_stand()
	_test_crouch()
	_test_prone()
	_test_crawl_cycle()
	_test_knockdown_still_owns()
	_test_clear_stance()
	print("StanceTests: %d passed, %d failed" % [_pass, _fail])
	ok(_pass + _fail >= MIN_ASSERTIONS, "the suite still has its assertions")
	if _fail > 0:
		print("STANCE TESTS FAILED")
	else:
		print("STANCE TESTS PASSED")
	quit(1 if _fail > 0 else 0)
	return true


func _snap_stance() -> void:
	## Large delta so every lerp lands on its target this call.
	_p._tick_stance(1.0)
	_p._update_action_camera(1.0)
	_p._update_body_arms(1.0)


func _test_rig() -> void:
	ok(_p.leg_pivots.size() == 2, "two hip pivots")
	ok(_p.knee_pivots.size() == 2, "two knee pivots (crouch needs a shin)")
	ok(_p.knee_pivots[0].get_parent() == _p.leg_pivots[0], "left shin hangs off the left hip")
	ok(_p.body_skin != null, "CreatureSkin still bakes with the split legs")


func _test_stand() -> void:
	_p.crouching = false
	_p.prone = false
	_p.sliding = false
	_p._stance_w = 0.0
	_p.gait_amount = 0.0
	_snap_stance()
	ok(absf(_p.body_rig.position.y) < 0.04, "standing body sits on the origin")
	ok(absf(_p.body_rig.rotation_degrees.x) < 3.0, "standing body is upright")
	ok(absf(_p.leg_pivots[0].rotation.x) < 0.08, "standing hips are at rest")
	ok(absf(_p.knee_pivots[0].rotation.x) < 0.08, "standing knees are at rest")


func _test_crouch() -> void:
	_p.crouching = true
	_p.prone = false
	_p._stance_w = 1.0
	_p.gait_amount = 0.0
	_snap_stance()
	ok(_p.body_rig.position.y < -0.2, "crouch drops the hips (y=%.2f)" % _p.body_rig.position.y)
	ok(_p.body_rig.rotation_degrees.x > 8.0, "crouch hunches the torso (%.1f deg)" % _p.body_rig.rotation_degrees.x)
	ok(_p.leg_pivots[0].rotation.x > 0.6, "crouch folds the thighs forward")
	ok(_p.knee_pivots[0].rotation.x < -0.8, "crouch folds the shins back")
	ok(_p.left_arm.rotation.x > 0.15, "crouch brings the arms forward")


func _test_prone() -> void:
	_p.crouching = true
	_p.prone = true
	_p._stance_w = 2.0
	_p.gait_amount = 0.0
	_snap_stance()
	ok(_p.body_rig.rotation_degrees.x < -50.0,
		"prone pitches onto the belly (%.1f deg)" % _p.body_rig.rotation_degrees.x)
	ok(_p.body_rig.position.z > 0.8, "prone keeps the skull at the capsule (z=%.2f)" % _p.body_rig.position.z)
	ok(_p.left_arm.rotation.x > 0.7, "prone plants the arms forward")


func _test_crawl_cycle() -> void:
	_p.crouching = true
	_p.prone = true
	_p._stance_w = 2.0
	_p.gait_amount = 1.0
	_p.gait_phase = PI * 0.5
	_snap_stance()
	var hip_a := _p.leg_pivots[0].rotation.x
	var arm_a := _p.left_arm.rotation.x
	_p.gait_phase = PI * 1.5
	_snap_stance()
	ok(absf(_p.leg_pivots[0].rotation.x - hip_a) > 0.2, "crawl hips travel across a cycle")
	ok(absf(_p.left_arm.rotation.x - arm_a) > 0.3, "crawl arms reach across a cycle")


func _test_knockdown_still_owns() -> void:
	## Knockdown writes the rig AFTER the stance tick. A leftover crouch
	## weight must not win the pose while you're on your back.
	_p.crouching = true
	_p.prone = false
	_p._stance_w = 1.0
	_p.kd_phase = "down"
	_p.kd_t = 0.5
	_p._tick_stance(1.0)
	ok(_p._stance_w < 0.2, "knockdown eases the stance weight back to stand")
	_p.kd_phase = ""
	_p.crouching = false
	_p._stance_w = 0.0


func _test_clear_stance() -> void:
	_p.crouching = true
	_p.prone = true
	_p._stance_w = 2.0
	_p.gait_amount = 0.0
	_snap_stance()
	ok(_p.body_rig.rotation_degrees.x < -50.0, "setup: body is belly-down")
	_p._clear_stance(true)
	ok(not _p.crouching and not _p.prone, "snap stand clears both flags")
	near_f(_p._stance_w, 0.0, 0.001, "snap stand zeros the eased weight")
	ok(absf(_p.body_rig.rotation_degrees.x) < 1.0, "snap stand rights the rig")
	ok(absf(_p.body_rig.position.z) < 0.01, "snap stand puts the body back on the origin")


func near_f(a: float, b: float, tol: float, what: String) -> void:
	ok(absf(a - b) <= tol, "%s (got %.4f, want %.4f +/- %.4f)" % [what, a, b, tol])
