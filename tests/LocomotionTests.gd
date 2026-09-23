extends SceneTree
## ===========================================================================
## LocomotionTests.gd -- how the body crosses the ground (scripts/Locomotion.gd)
##
##   godot --headless --path . --script res://tests/LocomotionTests.gd
##
## Every function under test is static and takes only numbers, so this whole
## suite is arithmetic: no world, no player, no renderer, no frames. That is
## the entire reason the momentum model lives in its own file -- the feel of
## the game is now something a test can hold an opinion about.
## ===========================================================================

var _pass := 0
var _fail := 0
const MIN_ASSERTIONS := 165
const DT := 1.0 / 60.0
const SPRINT := 8.0
const WALK := 5.0


func ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: %s" % what)


func near(a: float, b: float, eps: float, what: String) -> void:
	ok(absf(a - b) <= eps, "%s  (got %.4f, want %.4f +- %.4f)" % [what, a, b, eps])


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


## Walk the steer() integrator for `secs` and report where the velocity ended.
func _drive(hv: Vector3, want: Vector3, secs: float, accel := 45.0, decel := 24.0) -> Vector3:
	var steps := int(round(secs / DT))
	for _i in range(steps):
		hv = Locomotion.steer(hv, want, accel, decel, DT, SPRINT)
	return hv


func _run() -> void:
	print("LocomotionTests")

	## --- 1. steering: the standstill stays crisp -------------------------------
	## The whole risk of a momentum model is that it reads as input lag. Under
	## PIVOT_SPEED nothing arcs at all -- it is the old move_toward, exactly.
	var fwd := Vector3(0.0, 0.0, -1.0)
	var hv := Locomotion.steer(Vector3.ZERO, fwd * WALK, 45.0, 24.0, DT, SPRINT)
	near(hv.length(), 45.0 * DT, 0.001, "from a standstill it is plain acceleration")
	ok(hv.normalized().dot(fwd) > 0.999, "...straight where you asked")
	var side := Vector3(1.0, 0.0, 0.0)
	## "On a dime" is a fifth of a second, not one frame -- move_toward still has
	## to travel the whole (want - hv) vector, it just does not arc on the way.
	var turned := _drive(fwd * 1.0, side * WALK, 0.2)
	ok(turned.normalized().dot(side) > turned.normalized().dot(fwd),
		"a slow body turns on a dime (no arc under PIVOT_SPEED)")
	var arced := _drive(fwd * SPRINT, side * SPRINT, 0.2)
	ok(turned.normalized().dot(side) > arced.normalized().dot(side),
		"...and it is round the corner long before a sprinting body is")

	## --- 2. steering: a sprint carves ------------------------------------------
	var run := fwd * SPRINT
	var one := Locomotion.steer(run, side * SPRINT, 45.0, 24.0, DT, SPRINT)
	var deg := rad_to_deg(fwd.signed_angle_to(one.normalized(), Vector3.UP))
	ok(absf(deg) > 0.01, "a sprinting turn does move the heading")
	ok(absf(deg) < Locomotion.TURN_DEG_SPRINT * DT + 0.01,
		"...but never more than the sprint turn rate in one frame (%.2f deg)" % deg)
	ok(absf(deg) < 90.0, "a right angle at full sprint is NOT a one-frame snap")
	## and the slower you go the tighter you corner
	var fast_turn := absf(rad_to_deg(fwd.signed_angle_to(
		Locomotion.steer(fwd * SPRINT, side * SPRINT, 45.0, 24.0, DT, SPRINT).normalized(), Vector3.UP)))
	var mid_turn := absf(rad_to_deg(fwd.signed_angle_to(
		Locomotion.steer(fwd * 3.0, side * 3.0, 45.0, 24.0, DT, SPRINT).normalized(), Vector3.UP)))
	ok(mid_turn > fast_turn, "a jog corners tighter than a sprint (%.1f > %.1f deg)" % [mid_turn, fast_turn])

	## --- 3. steering: the turn is PAID FOR -------------------------------------
	var reversed := _drive(fwd * SPRINT, -fwd * SPRINT, 0.25)
	ok(reversed.length() < SPRINT, "hauling a 180 at sprint scrubs speed off (%.2f)" % reversed.length())
	var straight := _drive(fwd * SPRINT, fwd * SPRINT, 0.25)
	near(straight.length(), SPRINT, 0.01, "...while running straight keeps every metre of it")
	ok(reversed.length() < straight.length(), "cutting hard costs more than not cutting")
	## it still gets there in the end
	var eventually := _drive(fwd * SPRINT, -fwd * SPRINT, 3.0)
	ok(eventually.normalized().dot(-fwd) > 0.98, "a reversal does complete, given a second or two")
	near(eventually.length(), SPRINT, 0.05, "...and rebuilds to full sprint once pointed")

	## --- 4. steering: it never explodes ----------------------------------------
	var z := Locomotion.steer(Vector3.ZERO, Vector3.ZERO, 45.0, 24.0, DT, SPRINT)
	ok(z == Vector3.ZERO, "no velocity and no input stays exactly zero")
	ok(not is_nan(z.x) and not is_nan(z.z), "...with no NaN from normalising nothing")
	var stopping := _drive(fwd * SPRINT, Vector3.ZERO, 1.0)
	ok(stopping.length() < 0.01, "letting go coasts to a stop at DECEL")
	var glide := Locomotion.steer(fwd * SPRINT, Vector3.ZERO, 45.0, 24.0, DT, SPRINT)
	near(glide.length(), SPRINT - 24.0 * DT, 0.001, "...at exactly DECEL, so the stop still glides")
	ok(Locomotion.steer(fwd * SPRINT, side * SPRINT, 45.0, 24.0, 0.0, SPRINT) == fwd * SPRINT,
		"a zero delta changes nothing (a paused frame must not teleport you)")
	var tiny := Locomotion.steer(fwd * 0.0001, fwd * SPRINT, 45.0, 24.0, DT, SPRINT)
	ok(not is_nan(tiny.x), "a hair of velocity does not divide by zero")
	var big := Locomotion.steer(fwd * 400.0, side * SPRINT, 45.0, 24.0, DT, SPRINT)
	ok(big.length() < 400.0 and not is_nan(big.x), "an absurd launch speed still decays sanely")

	## --- 5. the bank ------------------------------------------------------------
	ok(Locomotion.bank(fwd * SPRINT, fwd * SPRINT, SPRINT) == 0.0, "running straight does not lean")
	ok(Locomotion.bank(fwd * 0.5, side * SPRINT, SPRINT) == 0.0, "and neither does a shuffle")
	var bl := Locomotion.bank(fwd * SPRINT, Vector3(-1.0, 0.0, -1.0).normalized() * SPRINT, SPRINT)
	var br := Locomotion.bank(fwd * SPRINT, Vector3(1.0, 0.0, -1.0).normalized() * SPRINT, SPRINT)
	ok(signf(bl) == -signf(br) and absf(bl) > 0.01, "left and right lean opposite ways")
	near(absf(bl), absf(br), 0.001, "...and by the same amount")
	var hard := absf(Locomotion.bank(fwd * SPRINT, side * SPRINT, SPRINT))
	var soft := absf(Locomotion.bank(fwd * SPRINT, Vector3(0.3, 0.0, -1.0).normalized() * SPRINT, SPRINT))
	ok(hard > soft, "a sharper turn leans harder")
	var quick := absf(Locomotion.bank(fwd * SPRINT, side * SPRINT, SPRINT))
	var amble := absf(Locomotion.bank(fwd * 3.0, side * SPRINT, SPRINT))
	ok(quick > amble, "and the same turn leans harder the faster you take it")
	for a in range(0, 360, 15):
		var d := Vector3(cos(deg_to_rad(float(a))), 0.0, sin(deg_to_rad(float(a))))
		ok(absf(Locomotion.bank(fwd * SPRINT, d * SPRINT, SPRINT)) <= 1.0, "bank stays in range at %d deg" % a)

	## --- 6. the lens ------------------------------------------------------------
	near(Locomotion.fov_bonus(0.0, WALK, SPRINT), 0.0, 0.001, "standing still: no FOV push")
	near(Locomotion.fov_bonus(WALK, WALK, SPRINT), 0.0, 0.001, "a walk: still none")
	near(Locomotion.fov_bonus(SPRINT, WALK, SPRINT), Locomotion.FOV_SPRINT, 0.001, "full sprint: the full push")
	ok(Locomotion.fov_bonus(SPRINT * 0.5 + WALK * 0.5, WALK, SPRINT) < Locomotion.FOV_SPRINT * 0.6,
		"...eased in, not linear (it must not breathe at a jog)")
	ok(Locomotion.fov_bonus(16.0, WALK, SPRINT) > Locomotion.FOV_SPRINT, "a dash pushes further again")
	near(Locomotion.fov_bonus(999.0, WALK, SPRINT), Locomotion.FOV_SPRINT + Locomotion.FOV_DASH, 0.001,
		"...and the push is capped, whatever launches you")
	var mono := true
	var prev := -1.0
	for i in range(0, 200):
		var f := Locomotion.fov_bonus(float(i) * 0.15, WALK, SPRINT)
		if f < prev - 0.0001:
			mono = false
		prev = f
	ok(mono, "FOV never lurches backwards as you speed up")

	## --- 7. slope ---------------------------------------------------------------
	var flat := Vector3.UP
	near(Locomotion.slope_mult(flat, fwd), 1.0, 0.0001, "flat ground costs nothing")
	## a 30 degree hill whose downhill side faces -Z
	var n30 := Vector3(0.0, cos(deg_to_rad(30.0)), -sin(deg_to_rad(30.0))).normalized()
	var down := Locomotion.slope_mult(n30, fwd)          ## -Z is downhill here
	var up := Locomotion.slope_mult(n30, -fwd)
	ok(down > 1.0, "downhill pays you (%.3f)" % down)
	ok(up < 1.0, "uphill costs you (%.3f)" % up)
	near(Locomotion.slope_mult(n30, side), 1.0, 0.0001, "traversing across the grade is free")
	var n60 := Vector3(0.0, cos(deg_to_rad(60.0)), -sin(deg_to_rad(60.0))).normalized()
	ok(Locomotion.slope_mult(n60, -fwd) < up, "a steeper climb costs more")
	ok(Locomotion.slope_mult(n60, -fwd) >= Locomotion.SLOPE_MIN, "...but never below the floor")
	ok(Locomotion.slope_mult(n60, fwd) <= Locomotion.SLOPE_MAX, "and a descent is not a sled")
	near(Locomotion.slope_mult(Vector3.ZERO, fwd), 1.0, 0.0001, "a null normal (mid-air) is flat ground")
	near(Locomotion.slope_mult(n30, Vector3.ZERO), 1.0, 0.0001, "standing still on a hill is flat ground")

	## --- 8. surfaces ------------------------------------------------------------
	near(Locomotion.surface_mult("grass"), 1.0, 0.0001, "meadow is the baseline")
	near(Locomotion.surface_mult("stone"), 1.0, 0.0001, "so is stone")
	ok(Locomotion.surface_mult("mud") < Locomotion.surface_mult("sand"), "mud drags harder than sand")
	ok(Locomotion.surface_mult("sand") < Locomotion.surface_mult("gravel"), "sand harder than gravel")
	ok(Locomotion.surface_mult("snow") < 1.0, "snow drags")
	near(Locomotion.surface_mult("a ground nobody has invented yet"), 1.0, 0.0001,
		"an unknown family is ordinary ground, never a silent halving")
	## every family StepAudio can name has an opinion here, and a sane one
	for fam in StepAudio.FAMILIES:
		ok(Locomotion.SURFACE.has(fam), "the footing table knows '%s'" % fam)
		ok(Locomotion.surface_mult(fam) > 0.5 and Locomotion.surface_mult(fam) <= 1.0,
			"...and '%s' is a drag, not a wall" % fam)

	## --- 9. the wade ------------------------------------------------------------
	near(Locomotion.wade_amount(false, 0.0, Locomotion.BASE_BLADE), 0.0, 0.0001, "bare ground: no wade")
	near(Locomotion.wade_amount(true, 0.0, Locomotion.BASE_BLADE), 1.0, 0.0001,
		"the tall stuff wades you fully, even where the paint says bare")
	var short_w := Locomotion.wade_amount(false, 1.0, Locomotion.BASE_BLADE)
	ok(short_w > 0.0 and short_w < 0.5, "a full SHORT meadow is a nudge, not a bog (%.2f)" % short_w)
	ok(Locomotion.wade_amount(false, 1.0, 0.36) > short_w, "taller blades wade more")
	ok(Locomotion.wade_amount(false, 0.5, Locomotion.BASE_BLADE) < short_w, "a thin meadow wades less")
	ok(Locomotion.wade_amount(false, 9.0, 9.0) <= 1.0, "the wade is capped at 1")
	ok(Locomotion.wade_amount(false, -3.0, -3.0) >= 0.0, "...and floored at 0")

	## Lemon picked SUBTLE: felt, not fought. Deep grass is a 15% tax and no more.
	near(Locomotion.wade_mult(0.0), 1.0, 0.0001, "no grass, no tax")
	near(Locomotion.wade_mult(1.0), 1.0 - Locomotion.WADE_DRAG, 0.0001, "deep grass is exactly the drag")
	near(Locomotion.WADE_DRAG, 0.15, 0.0001, "and the drag is the 15% Lemon asked for")
	ok(Locomotion.wade_mult(1.0) > 0.8, "you can still RUN through a meadow -- this is not a swamp")
	near(Locomotion.wade_mult(0.5), 1.0 - Locomotion.WADE_DRAG * 0.5, 0.0001, "and it grades smoothly")
	near(Locomotion.wade_mult(4.0), 1.0 - Locomotion.WADE_DRAG, 0.0001, "an out-of-range wade clamps")

	## --- 10. composing: the ground cannot stack into a standstill ---------------
	near(Locomotion.compose(WALK, 1.0, 0.0, 1.0), WALK, 0.0001, "flat dry bare ground is the base speed")
	var worst := Locomotion.compose(WALK, Locomotion.surface_mult("mud"), 1.0, Locomotion.SLOPE_MIN)
	ok(worst >= WALK * 0.30, "deep grass + a bog + a cliff still moves you (%.2f m/s)" % worst)
	ok(worst < WALK * 0.6, "...but it is unmistakably awful")
	var best := Locomotion.compose(WALK, 1.0, 0.0, Locomotion.SLOPE_MAX)
	ok(best <= WALK * 1.25, "and no combination turns a walk into a sprint")
	ok(Locomotion.compose(WALK, 1.0, 0.4, 1.0) < WALK, "a half-wade is slower than none")

	## --- 11. the moves Player.gd hangs off this file ----------------------------
	## The vault and the slide are stateful and live in Player.gd, so what a
	## headless test can hold is the SHAPE of them: the constants have to stay in
	## the right order relative to each other and to the walk, or the move stops
	## being reachable at all. (A vault you cannot run fast enough to trigger is
	## not a bug that shows up anywhere else.)
	var P := load("res://scripts/Player.gd") as GDScript
	ok(P != null, "Player.gd loads")
	var c: Dictionary = P.get_script_constant_map()
	for k in ["VAULT_MIN_H", "VAULT_MAX_H", "VAULT_TIME", "VAULT_STAMINA", "VAULT_MIN_SPEED",
			"VAULT_KEEP", "SLIDE_MIN_SPEED", "SLIDE_TIME", "SLIDE_FRICTION", "SLIDE_BOOST",
			"SLIDE_END_SPEED", "SLIDE_CD", "SLIDE_STAMINA"]:
		ok(c.has(k), "Player still defines %s" % k)
	var walk: float = c["SPEED"]
	var sprint: float = c["SPRINT_SPEED"]

	## the vault
	ok(c["VAULT_MIN_H"] > c["STEP_HEIGHT"],
		"a vault starts above what auto-step already walks you over")
	ok(c["VAULT_MAX_H"] < c["CLIMB_MAX_H"], "...and stops below a real mantle's reach")
	ok(c["VAULT_MAX_H"] > c["VAULT_MIN_H"], "the vault window is a window")
	ok(c["VAULT_MIN_SPEED"] > walk, "a WALK never vaults (it would fire on doorsteps)")
	ok(c["VAULT_MIN_SPEED"] < sprint, "...but a sprint comfortably reaches the trigger")
	ok(c["VAULT_TIME"] < c["CLIMB_TIME"], "a hurdle is quicker than a haul")
	ok(c["VAULT_STAMINA"] < c["CLIMB_STAMINA"], "...and cheaper, because momentum did it")
	ok(c["VAULT_KEEP"] > 0.5 and c["VAULT_KEEP"] <= 1.0,
		"you land with most of your speed, and never more than you had")
	ok(c["VAULT_MIN_SPEED"] * float(c["VAULT_KEEP"]) > walk,
		"the slowest legal vault still spits you out above a walk (no dead stop)")

	## the slide
	ok(c["SLIDE_MIN_SPEED"] > walk, "a walk does not slide")
	ok(c["SLIDE_MIN_SPEED"] <= sprint, "...and a sprint can always start one")
	ok(c["SLIDE_END_SPEED"] < c["SLIDE_MIN_SPEED"], "a slide does not end the instant it starts")
	ok(c["SLIDE_BOOST"] > 0.0, "going down speeds you up for a beat")
	ok(c["SLIDE_CD"] > 0.0, "and you cannot slide-spam across the map")
	ok(c["SLIDE_STAMINA"] > 0.0, "a slide costs wind")
	## Walk the friction out: the slowest legal slide must still run most of its
	## clock before dropping under SLIDE_END_SPEED, or the move is a stutter.
	var sp: float = float(c["SLIDE_MIN_SPEED"]) + float(c["SLIDE_BOOST"])
	var lived := 0.0
	while sp > float(c["SLIDE_END_SPEED"]) and lived < float(c["SLIDE_TIME"]):
		sp -= float(c["SLIDE_FRICTION"]) * DT
		lived += DT
	ok(lived > float(c["SLIDE_TIME"]) * 0.7,
		"the slowest legal slide lasts (%.2f s of its %.2f s)" % [lived, float(c["SLIDE_TIME"])])
	## ...and the fastest one is still bounded by the clock, not by friction alone
	var fast: float = sprint + float(c["SLIDE_BOOST"]) - float(c["SLIDE_FRICTION"]) * float(c["SLIDE_TIME"])
	ok(fast > 0.0, "a full-speed slide is ended by its timer, not by running out of speed")

	## --- 12. stance poses: squat, crawl, and the blend between them ------------
	near(Locomotion.stance_target(false, false), 0.0, 0.001, "standing wants weight 0")
	near(Locomotion.stance_target(true, false), 1.0, 0.001, "crouch wants weight 1")
	near(Locomotion.stance_target(true, true), 2.0, 0.001, "prone wants weight 2")
	near(Locomotion.stance_target(false, true), 2.0, 0.001, "prone wins even if crouch is false")
	ok(Locomotion.stance_target(true, false, true) > 1.0, "a slide sits lower than a crouch")
	ok(Locomotion.stance_ease(0.0, 1.0) > Locomotion.stance_ease(0.0, 2.0) - 0.01,
		"going prone eases slower than a crouch (or equal)")
	ok(Locomotion.stance_ease(1.6, 0.0) < Locomotion.stance_ease(0.2, 1.0),
		"...and rising through prone is the slow one")

	var idle := Locomotion.stance_pose(0.0, 0.0, 0.0)
	near(float(idle["body_y"]), 0.0, 0.001, "stand idle does not drop the hips")
	near(float(idle["pitch_deg"]), 0.0, 0.001, "stand idle does not pitch the body")
	near(float(idle["hip_l"]), 0.0, 0.001, "stand idle hips are at rest")

	var squat := Locomotion.stance_pose(1.0, 0.0, 0.0)
	ok(float(squat["body_y"]) < -0.2, "crouch drops the hips (%.2f)" % float(squat["body_y"]))
	ok(float(squat["pitch_deg"]) > 8.0, "crouch hunches the torso")
	ok(float(squat["hip_l"]) > 0.6, "crouch folds the thighs forward")
	ok(float(squat["knee_l"]) < -0.8, "crouch folds the shins back")
	ok(float(squat["arm_l"]) > 0.1, "crouch brings the arms a little forward")

	var belly := Locomotion.stance_pose(2.0, 0.0, 0.0)
	ok(float(belly["pitch_deg"]) < -50.0, "prone pitches onto the belly")
	ok(float(belly["body_z"]) > 0.8, "prone pulls the skull back to the capsule")
	ok(float(belly["arm_l"]) > 0.8, "prone plants the arms forward")
	ok(float(belly["gait_rate"]) < float(squat["gait_rate"]), "a crawl cycles slower than a squat-walk")

	## Blend is monotonic: half-crouch is between stand and squat.
	var half := Locomotion.stance_pose(0.5, 0.0, 0.0)
	ok(float(half["body_y"]) < float(idle["body_y"]) and float(half["body_y"]) > float(squat["body_y"]),
		"going-down blend sits between stand and crouch")
	var dropping := Locomotion.stance_pose(1.5, 0.0, 0.0)
	ok(float(dropping["pitch_deg"]) < float(squat["pitch_deg"]) and float(dropping["pitch_deg"]) > float(belly["pitch_deg"]),
		"going-prone blend sits between crouch and prone")

	## Walk and crawl actually cycle: opposite hips, and a later phase differs.
	var walk_a := Locomotion.stance_pose(1.0, 1.0, PI * 0.5)
	var walk_b := Locomotion.stance_pose(1.0, 1.0, PI * 1.5)
	ok(absf(float(walk_a["hip_l"]) - float(walk_b["hip_l"])) > 0.2,
		"crouch-walk hips travel across a stride")
	ok((float(walk_a["hip_l"]) - float(walk_a["hip_r"])) * (float(walk_b["hip_l"]) - float(walk_b["hip_r"])) < 0.0,
		"...and left/right stay opposite")
	var crawl_a := Locomotion.stance_pose(2.0, 1.0, PI * 0.5)
	var crawl_b := Locomotion.stance_pose(2.0, 1.0, PI * 1.5)
	ok(absf(float(crawl_a["arm_l"]) - float(crawl_b["arm_l"])) > 0.3,
		"prone crawl reaches the arms across a cycle")
	ok((float(crawl_a["arm_l"]) - 1.08) * (float(crawl_a["hip_l"]) - 0.38) < 0.0,
		"crawl is contralateral: left arm with right hip")

	var slide_p := Locomotion.stance_pose(1.0, 0.0, 0.0, true)
	ok(float(slide_p["pitch_deg"]) > float(squat["pitch_deg"]), "a slide lays out further than a crouch")
	ok(float(slide_p["hip_r"]) < float(slide_p["hip_l"]), "a slide trails the right (uphill) leg")

	## --- 13. the wiring is still in Player.gd -----------------------------------
	## Three other Claude sessions edit this repo at the same time and Player.gd is
	## 9,600 lines. If the momentum call site is ever reverted by a bad merge, the
	## game silently goes back to sliding around like a chess piece and NOTHING
	## else in the suite notices. So: check the source text.
	var psrc := FileAccess.get_file_as_string("res://scripts/Player.gd")
	ok(psrc.length() > 1000, "Player.gd source is readable")
	for needle in ["Locomotion.steer(", "Locomotion.compose(", "Locomotion.bank(",
			"Locomotion.fov_bonus(", "Locomotion.wade_amount(", "Locomotion.stance_pose(",
			"Locomotion.stance_target(", "_tick_stance(", "_clear_stance(", "_make_leg(",
			"_update_footing(", "_try_climb(true)", "_try_slide()", "_update_slide("]:
		ok(psrc.contains(needle), "Player.gd still calls %s" % needle)
	ok(not psrc.contains("hv.move_toward(target,"),
		"...and the old snap-to-target line is gone, not sitting alongside it")
	var wsrc := FileAccess.get_file_as_string("res://scripts/Wind.gd")
	ok(wsrc.contains("WADE_PUSH"), "Wind still opens the blades wider for a wading player")

	_finish()


func _finish() -> void:
	print("LocomotionTests: %d passed, %d failed" % [_pass, _fail])
	if _pass + _fail < MIN_ASSERTIONS:
		print("  LOST A SECTION: only %d assertions ran (floor %d)" % [_pass + _fail, MIN_ASSERTIONS])
		_fail += 1
	quit(1 if _fail > 0 else 0)
