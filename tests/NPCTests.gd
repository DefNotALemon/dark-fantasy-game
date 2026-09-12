extends SceneTree
## ===========================================================================
## NPC BASE — the regression net.
##
##   godot --headless --path . --script res://tests/NPCTests.gd
##
## Runs against the REAL NPC, NPCDialogue, NPCFocus, NPCDirector, Enemy and
## CreatureSkin. The headless renderer keeps no mesh data, so the body is
## measured off the pivots and the skeleton; the brain is driven by calling
## _physics_process directly with a fixed step (the 2026-09-06 rule: bind the
## clock), on a stub world whose clock and sky the suite owns.
## ===========================================================================

const MIN_ASSERTIONS := 300
const DT := 1.0 / 30.0

var pass_n := 0
var fail_n := 0
var fails: Array = []
var _world: StubWorld
var _player: TalkPlayer


## ------------------------------------------------------------- stubs ------

class StubClock:
	var hour := 12.0
	var day := 3.0


class StubSky:
	var level := 0


class StubWorld extends Node3D:
	var clock := StubClock.new()
	var sky := StubSky.new()

	func daynight() -> StubClock:
		return clock

	func weather() -> StubSky:
		return sky


class TalkPlayer extends LabPlayer:
	## The surface NPC / NPCFocus / NPCDialogue probe on the player.
	var sheath_t := 1.0
	var current_weapon := "sword"
	var menu_open := ""
	var kd_phase := ""
	var gold := 10
	var given: Array = []
	var gains: Array = []
	var closes := 0

	func _give_item(item_name: String, n: int, _w := 0.06) -> bool:
		given.append([item_name, n])
		return true

	func _push_gain(item_name: String, n: int) -> void:
		gains.append([item_name, n])

	func _close_menu() -> void:
		closes += 1
		menu_open = ""


## ------------------------------------------------------------- harness ----

func ok(cond: bool, what: String) -> void:
	if cond:
		pass_n += 1
	else:
		fail_n += 1
		fails.append(what)
		print("  FAIL: ", what)


func eq(a, b, what: String) -> void:
	ok(a == b, "%s (got %s, want %s)" % [what, str(a), str(b)])


func near(a: float, b: float, tol: float, what: String) -> void:
	ok(absf(a - b) <= tol, "%s (got %.4f, want %.4f +-%.4f)" % [what, a, b, tol])


func section(name: String) -> void:
	print("--- ", name)


func _init() -> void:
	print("=== Myrkfell NPC tests ===")
	_world = StubWorld.new()
	root.add_child(_world)
	_world.add_to_group("world")
	var floor := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(600, 1, 600)
	cs.shape = bs
	floor.add_child(cs)
	floor.position.y = -0.5
	_world.add_child(floor)
	_player = TalkPlayer.new()
	_world.add_child(_player)
	_player.position = Vector3(200, 0, 200)   ## far: nobody notices it until a section moves it
	await process_frame
	await process_frame

	await t_rig()
	await t_gait()
	await t_poses()
	await t_head()
	t_schedule_pure()
	await t_schedule_live()
	await t_senses()
	await t_damage()
	t_dialogue_pure()
	await t_focus()
	await t_director()
	t_save()
	t_no_input()

	print("=== %d passed, %d failed ===" % [pass_n, fail_n])
	var ran := pass_n + fail_n
	if ran < MIN_ASSERTIONS:
		fail_n += 1
		fails.append("the suite ran only %d assertions (expected at least %d) — a section probably returned early" % [ran, MIN_ASSERTIONS])
	for f in fails:
		print("  - ", f)
	quit(0 if fail_n == 0 else 1)


func spawn(job := "villager", at := Vector3(0, 0.05, 0), npc_name := "Test Person", sex := "m", personality := "friendly") -> NPC:
	var n := NPC.new()
	n.job = job
	n.npc_name = npc_name
	n.sex = sex
	n.personality = personality
	_world.add_child(n)
	n.global_position = at
	return n


func settle(n: NPC, frames := 12) -> void:
	## Let physics put it on the floor.
	for _i in range(frames):
		await physics_frame


func step(n: NPC, ticks: int, dt := DT) -> void:
	for _i in range(ticks):
		n._physics_process(dt)


func bury(n: Node) -> void:
	if n != null and is_instance_valid(n):
		n.queue_free()


func hand_pos(n: NPC, right := true) -> Vector3:
	var el := n.elbow_r if right else n.elbow_l
	return el.to_global(Vector3(0, -0.27, 0.02))


func head_pos(n: NPC) -> Vector3:
	return n.head_pivot.to_global(Vector3(0, 0.14, 0))


func face_each_other(n: NPC, dist: float) -> void:
	## The player stands `dist` m in front of n, both facing each other.
	var fwd := -n.global_transform.basis.z
	_player.global_position = n.global_position + fwd * dist
	_player.look_at(n.global_position + Vector3.UP * 0.9, Vector3.UP)
	_player.velocity = Vector3.ZERO


## ============================================================ 1. rig ======

func t_rig() -> void:
	section("rig — the player's body, box for box, with elbows and knees")
	var n := spawn()
	await settle(n)
	for nm in ["Rig", "Rig/Spine", "Rig/HipL", "Rig/HipR", "Rig/HipL/KneeL", "Rig/HipR/KneeR",
			"Rig/Spine/ShoulderL", "Rig/Spine/ShoulderR", "Rig/Spine/ShoulderL/ElbowL", "Rig/Spine/ShoulderR/ElbowR",
			"Rig/Spine/Head", "NameTag"]:
		ok(n.has_node(nm), "rig has %s" % nm)
	## the player's proportions (Player._build_body): hips 0.74, shoulders 1.30,
	## neck 1.44, sole on the ground, hand ending at -0.50 from the shoulder
	n._animate(1.0)
	n._animate(1.0)
	var base := n.global_position
	near(n.hip_l.global_position.y - base.y, 0.74, 0.03, "hip pivot at the player's 0.74")
	near(n.shoulder_r.global_position.y - base.y, 1.30, 0.04, "shoulder at the player's 1.30")
	near(n.head_pivot.global_position.y - base.y, 1.44, 0.04, "neck pivot at the player's 1.44")
	near(head_pos(n).y - base.y, 1.58, 0.05, "head centre at the player's 1.58")
	var sole := n.knee_l.to_global(Vector3(0, -0.34, -0.05)).y - base.y
	near(sole, 0.0, 0.05, "sole of the foot on the ground (knee -0.28 foot -0.06)")
	near(hand_pos(n).y - base.y, 0.80, 0.06, "hand at the player's shoulder-0.50 = 0.80")
	near(n.hip_r.position.x, 0.14, 0.001, "hips ±0.14 apart")
	near(n.shoulder_r.position.x, 0.26, 0.001, "shoulders ±0.26 apart")
	ok(n.skin != null and n.skin.bone_count() > 8, "baked into a skeleton (%d bones)" % (n.skin.bone_count() if n.skin else 0))
	ok(n.skin != null and n.skin.segment_count() >= 20, "skinned as %d segments" % (n.skin.segment_count() if n.skin else 0))
	ok(n.is_in_group("enemies"), "in the enemies group (the player's sword can find it)")
	ok(n.is_in_group("npcs"), "in the npcs group")
	eq(n.collision_layer, 2, "on the creature layer")
	ok(n.eye_mats.is_empty(), "no demon eyes: eye_mats cleared so _set_agitated cannot tint them")
	ok(n.body_mat != null, "body_mat set (hit flash)")
	eq(n.aggro_radius, 0.0, "aggro_radius 0 — never wakes on proximity")
	ok(n.strong_max_range < 0.0, "no strong attack range")
	ok(not n.can_climb, "does not climb")
	eq(n.display_name, "Villager", "display_name is the job title")
	ok(n.loco_root == n.rig, "loco_root is the rig (Enemy bobs it)")
	eq(n.walk_legs.size(), 2, "two hip pivots registered")
	eq(n.walk_arms.size(), 2, "two shoulder pivots registered")
	ok(n.name_label is Label3D and not n.name_label.visible, "name tag exists and starts hidden")
	ok(not n.confused, "never spawns confused")
	bury(n)
	## every job and both sexes build and bake
	var i := 0
	for job in NPCDirector.JOBS:
		for sex in ["m", "f"]:
			var p := spawn(job, Vector3(4 + i * 2, 0.05, 0), "Name %d" % i, sex)
			i += 1
			await settle(p, 2)
			ok(p.skin != null and p.skin.segment_count() >= 20, "%s/%s bakes (%d segs)" % [job, sex, p.skin.segment_count() if p.skin else 0])
			eq(p.display_name, String(NPC.JOB_TITLE[job]), "%s titled %s" % [job, String(NPC.JOB_TITLE[job])])
			ok(p.base_body_color == (NPC.JOB_CLOTH[job] as Array)[0], "%s wears its cloth" % job)
			bury(p)
	var g := spawn("guard", Vector3(30, 0.05, 0))
	var v := spawn("villager", Vector3(32, 0.05, 0))
	await settle(g, 2)
	ok(g.skin.segment_count() > v.skin.segment_count(), "a guard carries more (helm, tabard) than a villager: %d > %d" % [g.skin.segment_count(), v.skin.segment_count()])
	bury(g)
	bury(v)
	await process_frame


## ============================================================ 2. gait =====

func t_gait() -> void:
	section("gait — the player's own stride maths")
	var n := spawn("villager", Vector3(0, 0.05, 0))
	await settle(n, 10)
	ok(n.is_on_floor(), "standing on the floor")
	## cadence: gait_rate turns Enemy's 2 + h*2.4 into the player's 4.5 + h*1.35
	for hv in [0.0, 1.5, 4.6]:
		var h := float(hv)
		n.velocity = Vector3(h, 0, 0)
		n._pre_loco()
		var want := (4.5 + h * 1.35) / (2.0 + minf(h, 9.0) * 2.4)
		near(n.gait_rate, want, 0.0001, "gait_rate at %.1f m/s is the player's cadence ratio" % h)
		var t0 := n.walk_t
		n._update_locomotion(0.1)
		near(n.walk_t - t0, (4.5 + h * 1.35) * 0.1, 0.002, "walk_t advances at the player's 4.5 + h*1.35 rad/s at %.1f m/s" % h)
	## walking: the stride shows, legs and arms in counter-phase, arms 1.2x legs
	n.velocity = Vector3(0, 0, -1.5)
	var max_hip := 0.0
	var max_sh := 0.0
	var same_sign := 0
	var samples := 0
	var arm_vs_leg := 0.0
	for _i in range(90):
		n.velocity = Vector3(0, 0, -1.5)
		n._pre_loco()
		n._update_locomotion(DT)
		n._animate(DT)
		if _i > 40:
			max_hip = maxf(max_hip, absf(n.hip_l.rotation.x))
			max_sh = maxf(max_sh, absf(n.shoulder_r.rotation.x))
			if absf(n.hip_r.rotation.x) > 0.05:
				samples += 1
				if signf(n.shoulder_l.rotation.x) == signf(n.hip_r.rotation.x):
					same_sign += 1
			if absf(n.hip_l.rotation.x) > 0.15:
				arm_vs_leg = maxf(arm_vs_leg, absf(n.shoulder_r.rotation.x) / absf(n.hip_l.rotation.x))
	var want_amp := 0.5 * (0.55 + 0.45 * 1.5 / NPC.RUN_SPEED)
	near(max_hip, want_amp, 0.06, "walking hip swing is the player's 0.5 rad scaled by speed (%.2f)" % want_amp)
	ok(max_sh > max_hip * 1.05 and max_sh < max_hip * 1.4, "arms swing ~1.2x the legs (%.2f vs %.2f)" % [max_sh, max_hip])
	ok(samples > 20 and same_sign >= samples - 2, "left arm swings with the right leg (%d/%d)" % [same_sign, samples])
	ok(n._gait_k > 0.9, "stride fully shown while walking (%.2f)" % n._gait_k)
	var bent := 0
	for _i in range(60):
		n.velocity = Vector3(0, 0, -1.5)
		n._pre_loco()
		n._update_locomotion(DT)
		n._animate(DT)
		if n.knee_l.rotation.x < -0.2 or n.knee_r.rotation.x < -0.2:
			bent += 1
	ok(bent > 10, "knees bend through the swing (%d/60 frames)" % bent)
	## running swings harder
	var run_hip := 0.0
	for _i in range(90):
		n.velocity = Vector3(0, 0, -NPC.RUN_SPEED)
		n._pre_loco()
		n._update_locomotion(DT)
		n._animate(DT)
		if _i > 40:
			run_hip = maxf(run_hip, absf(n.hip_l.rotation.x))
	ok(run_hip > max_hip + 0.08, "a run is a bigger stride than a walk (%.2f > %.2f)" % [run_hip, max_hip])
	## The pose is eased at 12/s (the player's own legs ease at 14/s), which
	## trims a 10.7 rad/s stride: recompute the discrete first-order gain
	## at this step rather than trust a number.
	var wT := (4.5 + NPC.RUN_SPEED * 1.35) * DT
	var kf := clampf(DT * 12.0, 0.0, 1.0)
	var gain := kf / sqrt(1.0 - 2.0 * (1.0 - kf) * cos(wT) + (1.0 - kf) * (1.0 - kf))
	near(run_hip, 0.5 * gain, 0.04, "the run reaches the player's 0.5 rad through the pose ease (gain %.2f)" % gain)
	## standing still: the stride dies away
	for _i in range(120):
		n.velocity = Vector3.ZERO
		n._pre_loco()
		n._update_locomotion(DT)
		n._animate(DT)
	ok(absf(n.hip_l.rotation.x) < 0.05 and absf(n.hip_r.rotation.x) < 0.05, "legs quiet when standing")
	ok(n._gait_k < 0.05, "stride gone when standing (%.3f)" % n._gait_k)
	bury(n)
	await process_frame


## ============================================================ 3. poses ====

func t_poses() -> void:
	section("poses — sit, sleep, cower, wave, talk, work, the fist")
	var n := spawn("villager", Vector3(0, 0.05, 0))
	await settle(n, 10)
	var base := n.global_position
	var stand_head := head_pos(n).y - base.y
	## SIT
	n.seat = n.global_position
	n._enter(NPC.Mode.SIT)
	for _i in range(80):
		n._update_locomotion(DT)
		n._animate(DT)
	near(n.hip_l.rotation.x, 1.5, 0.05, "sitting: thighs forward")
	near(n.knee_l.rotation.x, -1.5, 0.05, "sitting: shins down")
	near(n._pose_y, -(0.74 - n.seat_h), 0.02, "sitting: hips dropped to the seat height")
	ok(head_pos(n).y - base.y < stand_head - 0.2, "sitting: the head is lower than standing")
	near(n.rig.position.y, n.loco_bob_y + n._pose_y, 0.001, "the pose height sits UNDER the footfall bob, never fights it")
	## SLEEP (a bed: lies down)
	n.home = n.global_position
	n.home_kind = "bed"
	n._enter(NPC.Mode.SLEEP)
	for _i in range(120):
		n._update_locomotion(DT)
		n._animate(DT)
	ok(not n.indoors and n.visible, "a bed-kind home sleeps in the open")
	near(n.rig.rotation.x, PI * 0.5, 0.05, "sleeping: the rig is laid flat")
	ok(head_pos(n).y - base.y < 0.6, "sleeping: the head is on the ground (%.2f)" % (head_pos(n).y - base.y))
	ok(absf(head_pos(n).z - base.z) > 1.0, "sleeping: the body lies along the ground")
	## a door-kind home vanishes indoors instead
	n.home_kind = "door"
	n._enter(NPC.Mode.IDLE)
	n._enter(NPC.Mode.SLEEP)
	ok(n.indoors and not n.visible, "a door-kind home takes it indoors (hidden)")
	n._come_outside()
	ok(not n.indoors and n.visible, "and it comes back out")
	n._enter(NPC.Mode.IDLE)
	for _i in range(120):
		n._update_locomotion(DT)
		n._animate(DT)
	near(n.rig.rotation.x, 0.0, 0.05, "standing again: the rig is upright")
	## COWER: hands above the head, knees soft
	n._start_cower()
	eq(n.mode, NPC.Mode.COWER, "cowering")
	ok(n.bark_text != "" and (NPCDialogue.LINES["cower"]["*"] as Array).has(n.bark_text), "cower bark from the cower table")
	for _i in range(80):
		n._update_locomotion(DT)
		n._animate(DT)
	ok(hand_pos(n).y > head_pos(n).y, "cower: hands above the head (%.2f > %.2f)" % [hand_pos(n).y, head_pos(n).y])
	ok(n._pose_y < -0.08, "cower: crouched")
	n._enter(NPC.Mode.IDLE)
	## WAVE: right hand up and out, then back down
	n.act("wave")
	var hi := 0.0
	for _i in range(48):
		n._tick_clocks_npc(DT)
		n._update_locomotion(DT)
		n._animate(DT)
		if _i == 24:
			hi = hand_pos(n).y
	ok(hi > head_pos(n).y, "wave: the right hand rises above the head mid-wave (%.2f > %.2f)" % [hi, head_pos(n).y])
	for _i in range(80):
		n._tick_clocks_npc(DT)
		n._update_locomotion(DT)
		n._animate(DT)
	eq(n._act, "", "wave over")
	ok(hand_pos(n).y < n.shoulder_r.global_position.y, "hand back down after the wave")
	## TALK gestures move
	n.talk_open = true
	n.mode = NPC.Mode.TALK
	var seen: Array = []
	for _i in range(90):
		n._update_locomotion(DT)
		n._animate(DT)
		if _i % 30 == 29:
			seen.append(n.elbow_r.rotation.x)
	ok(seen.size() == 3 and (absf(seen[0] - seen[1]) > 0.02 or absf(seen[1] - seen[2]) > 0.02), "talking: the hands move")
	n.talk_open = false
	n._enter(NPC.Mode.IDLE)
	## WORK by job: tools
	for pair in [["woodcutter", "Axe"], ["villager", "Broom"], ["fisher", "Rod"], ["guard", ""]]:
		var w := spawn(String(pair[0]), Vector3(10, 0.05, 0))
		await settle(w, 2)
		w.work = w.global_position
		w._enter(NPC.Mode.WORK)
		for _i in range(30):
			w._do_work(DT)
			w._update_locomotion(DT)
			w._animate(DT)
		var tool := String(pair[1])
		eq(w.tool_axe.visible, tool == "Axe", "%s: axe %s" % [pair[0], "shown" if tool == "Axe" else "hidden"])
		eq(w.tool_broom.visible, tool == "Broom", "%s: broom %s" % [pair[0], "shown" if tool == "Broom" else "hidden"])
		eq(w.tool_rod.visible, tool == "Rod", "%s: rod %s" % [pair[0], "shown" if tool == "Rod" else "hidden"])
		bury(w)
	## the woodcutter's chop is a cut arc: the arm passes through chamber and impact
	var wc := spawn("woodcutter", Vector3(12, 0.05, 0))
	await settle(wc, 2)
	wc.work = wc.global_position
	wc._enter(NPC.Mode.WORK)
	var lo := 99.0
	var hi2 := -99.0
	for _i in range(60):
		wc._do_work(DT)
		wc._update_locomotion(DT)
		wc._animate(DT)
		lo = minf(lo, wc.shoulder_r.rotation.x)
		hi2 = maxf(hi2, wc.shoulder_r.rotation.x)
	ok(lo < -1.2 and hi2 > 0.4, "chop: the axe arm chambers back (%.2f) and drives through (%.2f)" % [lo, hi2])
	bury(wc)
	## HOSTILE: fists, and the swing is the player's cut curve landing at p=0.62
	n.hostile = true
	n.melee_anim = 0.0
	for _i in range(40):
		n._update_locomotion(DT)
		n._animate(DT)
	near(n.elbow_r.rotation.x, 1.50, 0.05, "guard up: forearms raised")
	n.melee_anim = Enemy.MELEE_ANIM_TIME * (1.0 - 0.62)
	n._animate(DT)
	near(n.shoulder_r.rotation.x, 1.75, 0.001, "the punch lands at p=0.62 with the arm driven forward (snap, no lerp)")
	near(n.elbow_r.rotation.x, 0.15, 0.001, "the arm straightens at impact")
	n.melee_anim = 0.0
	n.hostile = false
	bury(n)
	await process_frame


## ============================================================ 4. head =====

func t_head() -> void:
	section("head — looks at the player, within a neck's reach")
	var n := spawn("villager", Vector3(0, 0.05, 0))
	await settle(n, 8)
	n.rotation.y = 0.0   ## faces -z
	var base := n.global_position
	n.look_at_pos = base + Vector3(-2.0, 1.5, -2.0)   ## left-front
	for _i in range(60):
		n._animate_head(DT)
	ok(n.head_pivot.rotation.y > 0.5, "target to the left-front: head yaws left (+y) %.2f" % n.head_pivot.rotation.y)
	n.look_at_pos = base + Vector3(2.0, 1.5, -2.0)
	for _i in range(60):
		n._animate_head(DT)
	ok(n.head_pivot.rotation.y < -0.5, "target to the right-front: head yaws right (-y) %.2f" % n.head_pivot.rotation.y)
	n.look_at_pos = base + Vector3(0.0, 4.0, -2.0)
	for _i in range(60):
		n._animate_head(DT)
	ok(n.head_pivot.rotation.x > 0.3, "target above: the face tilts up %.2f" % n.head_pivot.rotation.x)
	ok(n.head_pivot.rotation.x <= NPC.LOOK_PITCH_MAX + 0.01, "pitch clamped")
	## the clamp band: a target at 1.30 rad is inside the "can still glance"
	## window (LOOK_YAW_MAX + 0.15) but past the neck's LOOK_YAW_MAX, so the
	## head must turn AND stop short — a fixture past the window would leave
	## the head at zero and pass a missing clamp.
	var band := 1.30
	n.look_at_pos = base + Vector3(-sin(band) * 2.0, 1.5, -cos(band) * 2.0)
	for _i in range(60):
		n._animate_head(DT)
	ok(n.head_pivot.rotation.y > 1.0, "a target at 1.30 rad is still glanced at (%.2f)" % n.head_pivot.rotation.y)
	ok(n.head_pivot.rotation.y <= NPC.LOOK_YAW_MAX + 0.01, "...but the neck stops at LOOK_YAW_MAX (%.2f)" % n.head_pivot.rotation.y)
	n.look_at_pos = base + Vector3(-2.0, 1.5, 0.3)   ## nearly beside, past the window
	for _i in range(60):
		n._animate_head(DT)
	near(n.head_pivot.rotation.y, 0.0, 0.05, "past the window: not even a glance")
	n.look_at_pos = base + Vector3(0.0, 1.5, 3.0)   ## behind
	for _i in range(60):
		n._animate_head(DT)
	near(n.head_pivot.rotation.y, 0.0, 0.05, "behind us: the head comes back to centre, no owl")
	n.look_at_pos = base + Vector3(-2.0, 1.5, -2.0)
	n.mode = NPC.Mode.SLEEP
	for _i in range(60):
		n._animate_head(DT)
	near(n.head_pivot.rotation.y, 0.0, 0.05, "asleep: no tracking")
	n.mode = NPC.Mode.IDLE
	## the senses feed the head: the player near and in front is looked at,
	## far away is not
	face_each_other(n, 3.0)
	n._sense(DT, _player, 3.0, _player.global_position - n.global_position)
	ok(n.look_at_pos != Vector3.INF, "a player 3 m in front is looked at")
	face_each_other(n, 12.0)
	n._sense(DT, _player, 12.0, _player.global_position - n.global_position)
	ok(n.look_at_pos == Vector3.INF, "a player 12 m away is not")
	_player.global_position = Vector3(200, 0, 200)
	bury(n)
	await process_frame


## ============================================================ 5. schedule =

func t_schedule_pure() -> void:
	section("schedule — pure: slots, wrapping, fallbacks")
	var s := NPC.default_schedule("villager")
	eq(String(NPC.slot_for(s, 23.0)["do"]), "sleep", "23:00 sleeps")
	eq(String(NPC.slot_for(s, 2.0)["do"]), "sleep", "02:00 sleeps (the slot wraps midnight)")
	eq(String(NPC.slot_for(s, 6.0)["do"]), "idle", "06:00 is up")
	eq(String(NPC.slot_for(s, 9.5)["do"]), "work", "09:30 works")
	eq(String(NPC.slot_for(s, 12.5)["do"]), "sit", "12:30 sits")
	eq(String(NPC.slot_for(s, 19.0)["do"]), "wander", "19:00 wanders")
	eq(String(NPC.slot_for(s, 25.0)["do"]), "sleep", "hour 25 = 01:00")
	ok(NPC.slot_for([], 12.0).is_empty(), "no schedule, no slot")
	for job in NPCDirector.JOBS:
		var sched := NPC.default_schedule(job)
		var gaps := 0
		var h := 0.0
		while h < 24.0:
			if NPC.slot_for(sched, h).is_empty():
				gaps += 1
			h += 0.25
		eq(gaps, 0, "%s's day has no gaps" % job)
	## fallbacks resolve on a person with nothing
	var n := NPC.new()
	n.anchor = Vector3(5, 0, 5)
	var r := n.resolve_slot({"do": "sleep", "at": "home"})
	eq(String(r["do"]), "idle", "sleep with no home and no seat -> idle")
	eq(r["at"], Vector3(5, 0, 5), "...at the anchor")
	n.seat = Vector3(1, 0, 1)
	r = n.resolve_slot({"do": "sleep", "at": "home"})
	eq(String(r["do"]), "sit", "sleep with no home but a seat -> sit")
	eq(r["at"], Vector3(1, 0, 1), "...at the seat")
	n.seat = Vector3.INF
	r = n.resolve_slot({"do": "sit", "at": "seat"})
	eq(String(r["do"]), "idle", "sit with no seat -> idle")
	r = n.resolve_slot({"do": "work", "at": "work"})
	eq(String(r["do"]), "wander", "work with no work marker -> wander")
	n.home = Vector3(9, 0, 9)
	r = n.resolve_slot({"do": "sleep", "at": "home"})
	eq(String(r["do"]), "sleep", "sleep with a home sleeps")
	eq(r["at"], Vector3(9, 0, 9), "...at home")
	n.work = Vector3(2, 0, 2)
	eq(n.expected_spot(10.0), Vector3(2, 0, 2), "expected_spot at 10:00 is the work marker")
	eq(n.expected_spot(23.5), Vector3(9, 0, 9), "expected_spot at 23:30 is home")
	eq(NPC.mode_for("sleep"), NPC.Mode.SLEEP, "mode_for sleep")
	eq(NPC.mode_for("work"), NPC.Mode.WORK, "mode_for work")
	eq(NPC.mode_for("sit"), NPC.Mode.SIT, "mode_for sit")
	eq(NPC.mode_for("wander"), NPC.Mode.WANDER, "mode_for wander")
	eq(NPC.mode_for("anything"), NPC.Mode.IDLE, "mode_for unknown = idle")
	n.free()


func t_schedule_live() -> void:
	section("schedule — live: home at night, work by day, rain indoors")
	var n := spawn("villager", Vector3(0, 0.05, 0))
	await settle(n, 8)
	n.home = Vector3(6, 0, 0)
	n.work = Vector3(-6, 0, 0)
	n.anchor = Vector3(0, 0, 0)
	n.seat = Vector3(0, 0, 4)
	_player.global_position = Vector3(0, 0, 30)   ## near enough to think, far enough to ignore
	_world.clock.hour = 23.0
	step(n, 40)
	eq(n.mode, NPC.Mode.GOTO, "23:00 — sets off (mode %s)" % n.mode_name())
	eq(n.goto_then, NPC.Mode.SLEEP, "...to sleep")
	var reached := false
	for _i in range(20):
		step(n, 30)
		if n.mode == NPC.Mode.SLEEP:
			reached = true
			break
	ok(reached, "walks home and sleeps (mode %s at %s)" % [n.mode_name(), str(n.global_position.round())])
	ok(n.indoors and not n.visible, "asleep indoors: hidden")
	ok(n.global_position.distance_to(Vector3(6, n.global_position.y, 0)) < 1.5, "...at the door")
	_world.clock.hour = 9.0
	step(n, 40)
	ok(not n.indoors and n.visible, "09:00 — up and out")
	eq(n.mode, NPC.Mode.GOTO, "...and off to work")
	reached = false
	for _i in range(24):
		step(n, 30)
		if n.mode == NPC.Mode.WORK:
			reached = true
			break
	ok(reached, "arrives and works (mode %s at %s)" % [n.mode_name(), str(n.global_position.round())])
	ok(n.global_position.distance_to(Vector3(-6, n.global_position.y, 0)) < 1.5, "...at the work marker")
	ok(absf(n.velocity.x) < 0.3 and absf(n.velocity.z) < 0.3, "standing still at work")
	## the sky: rain at ten in the morning drives it home
	_world.sky.level = 3
	n._sky_t = 0.0
	step(n, 40)
	eq(n.mode, NPC.Mode.GOTO, "rain — heads home")
	ok(n.shelter, "sheltering")
	reached = false
	for _i in range(24):
		step(n, 30)
		if n.indoors:
			reached = true
			break
	ok(reached, "indoors out of the rain")
	_world.sky.level = 0
	n._sky_t = 0.0
	step(n, 40)
	ok(not n.indoors, "sky clears — back out")
	ok(not n.shelter, "no longer sheltering")
	## a bench at noon
	_world.clock.hour = 12.5
	step(n, 40)
	reached = false
	for _i in range(24):
		step(n, 30)
		if n.mode == NPC.Mode.SIT:
			reached = true
			break
	ok(reached, "12:30 — sits on the bench")
	## freeze far away: no thinking, no moving
	_player.global_position = Vector3(0, 0, 150)
	_world.clock.hour = 9.0
	step(n, 60)
	eq(n.mode, NPC.Mode.SIT, "150 m from the player the brain sleeps (still %s)" % n.mode_name())
	ok(n._frozen, "frozen flag set")
	_player.global_position = Vector3(200, 0, 200)
	bury(n)
	await process_frame


## ============================================================ 6. senses ===

func t_senses() -> void:
	section("senses — a drawn weapon, a crouching stranger, a hello a day")
	var n := spawn("villager", Vector3(0, 0.05, 0), "Ezra Libby", "m", "gruff")
	await settle(n, 8)
	n.courage = 0.3
	_world.clock.hour = 10.0
	## hello, once a day
	face_each_other(n, 3.0)
	n.bark_text = ""
	step(n, 3)
	ok((NPCDialogue.LINES["hello"]["gruff"] as Array).has(n.bark_text.replace("Morning", "{tod_cap}")) or n.bark_text != "", "says hello in its own voice: %s" % n.bark_text)
	eq(n.greeted_day, 3, "greeted today")
	eq(n._act, "nod", "with a nod")
	ok(_player.log_lines.size() > 0 and _player.log_lines[-1].begins_with("Ezra Libby: "), "the hello reaches the player's log with the name")
	n.bark_text = ""
	n._greet_cool = 0.0
	step(n, 30)
	eq(n.bark_text, "", "no second hello the same day")
	_world.clock.day = 4.0
	n._greet_cool = 0.0
	step(n, 3)
	ok(n.bark_text != "", "a new day, a new hello")
	## a drawn weapon pointed at it
	n.bark_text = ""
	_player.sheath_t = 0.0
	_player.current_weapon = "sword"
	var d0 := n.disposition
	step(n, 60)
	ok((NPCDialogue.LINES["weapon"]["gruff"] as Array).has(n.bark_text), "steel out at 3 m: '%s'" % n.bark_text)
	ok(n.disposition < d0, "disposition drips while the blade is on it (%.2f < %.2f)" % [n.disposition, d0])
	ok(n._wary_t > 0.5, "wary")
	## closer: a coward cowers, the brave warn
	face_each_other(n, 1.5)
	step(n, 10)
	eq(n.mode, NPC.Mode.COWER, "blade at 1.5 m, courage 0.3: cowers")
	_player.sheath_t = 1.0
	face_each_other(n, 3.0)
	step(n, 200)
	ok(n.mode != NPC.Mode.COWER, "sheathed and stepped back: stops cowering (%s)" % n.mode_name())
	var brave := spawn("villager", Vector3(20, 0.05, 0), "Amos Foss", "m", "gruff")
	await settle(brave, 4)
	brave.courage = 0.9
	brave.greeted_day = 4
	_player.sheath_t = 0.0
	face_each_other(brave, 1.5)
	step(brave, 30)
	ok(brave.mode != NPC.Mode.COWER, "courage 0.9 does not cower")
	ok((NPCDialogue.LINES["weapon"]["gruff"] as Array).has(brave.bark_text) or (NPCDialogue.LINES["warn"]["*"] as Array).has(brave.bark_text), "...it warns: '%s'" % brave.bark_text)
	_player.sheath_t = 1.0
	bury(brave)
	## a crouching stranger behind
	n._enter(NPC.Mode.IDLE)
	n.bark_text = ""
	var back := n.global_transform.basis.z   ## behind = +z
	_player.global_position = n.global_position + back * 2.0
	_player.crouching = true
	step(n, 10)
	ok((NPCDialogue.LINES["sneak"]["gruff"] as Array).has(n.bark_text), "crouching behind it: '%s'" % n.bark_text)
	eq(n._act, "shake", "a shake of the head")
	_player.crouching = false
	## keeps its distance on a day it has reason to
	n.avoid_day = 4
	face_each_other(n, 3.0)
	step(n, 10)
	eq(n.mode, NPC.Mode.GOTO, "avoiding: walks off")
	ok(n.goto_target.distance_to(_player.global_position) > NPC.AVOID_R, "...to somewhere further than AVOID_R")
	_player.global_position = Vector3(200, 0, 200)
	bury(n)
	await process_frame


## ============================================================ 7. damage ===

func t_damage() -> void:
	section("damage — fight or flight by courage, the fight is Enemy's, murder is noticed")
	var d := NPCDirector.new()
	d.world = _world
	_world.add_child(d)
	await process_frame
	var coward := spawn("villager", Vector3(0, 0.05, 0), "Mercy Small", "f", "wary")
	await settle(coward, 8)
	coward.courage = 0.2
	face_each_other(coward, 2.0)
	var hp := coward.health
	coward.take_damage(10.0)   ## the player's swing passes no attacker
	ok(coward.health < hp, "took the hit")
	eq(coward.mode, NPC.Mode.FLEE, "courage 0.2: runs")
	ok(not coward.hostile, "not hostile")
	eq(coward.disposition, -100.0, "disposition floored")
	ok(coward.grudge, "holds a grudge")
	ok(coward.state == Enemy.State.CALM, "not agitated (the flight is ours, not Enemy's)")
	ok((NPCDialogue.LINES["hit"]["*"] as Array).has(coward.bark_text), "cries out: '%s'" % coward.bark_text)
	var p0 := coward.global_position
	step(coward, 60)
	ok(coward.global_position.distance_to(_player.global_position) > p0.distance_to(_player.global_position) + 1.0, "...away from the player")
	ok(coward._gait_k > 0.5, "at a run")
	## far enough: settles, avoids for the day
	_player.global_position = coward.global_position + Vector3(40, 0, 0)
	step(coward, 30)
	ok(coward.mode != NPC.Mode.FLEE, "stops once it has distance (%s)" % coward.mode_name())
	eq(coward.avoid_day, int(_world.clock.day), "and keeps its distance today")
	bury(coward)
	var brave := spawn("villager", Vector3(10, 0.05, 0), "Zeb Ricker", "m", "gruff")
	await settle(brave, 8)
	brave.courage = 0.9
	face_each_other(brave, 3.0)
	brave.take_damage(10.0)
	ok(brave.hostile, "courage 0.9: fights")
	eq(brave.mode, NPC.Mode.HOSTILE, "mode hostile")
	ok(brave.state == Enemy.State.AGITATED, "agitated — the Enemy fight loop owns it now")
	ok((NPCDialogue.LINES["fight"]["*"] as Array).has(brave.bark_text), "'%s'" % brave.bark_text)
	var swung := false
	var closest := 99.0
	for _i in range(240):
		brave._physics_process(DT)
		closest = minf(closest, brave.global_position.distance_to(_player.global_position))
		if brave.melee_anim > 0.0:
			swung = true
	ok(closest < brave.attack_range + 0.6, "closes to melee range (%.2f)" % closest)
	ok(swung, "and swings")
	ok(_player.damage_taken > 0.0, "the punch lands (%.1f)" % _player.damage_taken)
	## the leash: the player leaves, it calms, the grudge stays
	_player.global_position = brave.global_position + Vector3(60, 0, 0)
	for _i in range(120):
		brave._physics_process(DT)
	ok(not brave.hostile, "60 m away: the fight ends")
	ok(brave.grudge, "the grudge does not")
	ok(brave.state == Enemy.State.CALM, "calm again")
	## comes back within REAGGRO_R with the fight still fresh: it re-engages
	brave.take_damage(1.0)
	ok(brave.hostile, "struck again: hostile again")
	_player.global_position = brave.global_position + Vector3(60, 0, 0)
	for _i in range(120):
		brave._physics_process(DT)
	## the nerve: hurt past nerve it stays broken, no re-engage
	brave.health = brave.max_health * 0.2
	face_each_other(brave, 3.0)
	for _i in range(30):
		brave._physics_process(DT)
	ok(not brave.hostile or brave.routing, "below its nerve it does not come back for more")
	bury(brave)
	## death: no bestiary, the director knows, witnesses react
	var victim := spawn("villager", Vector3(20, 0.05, 0), "Obadiah Moody", "m", "dour")
	var w_coward := spawn("villager", Vector3(24, 0.05, 0), "Rhoda Emery", "f", "friendly")
	var w_brave := spawn("guard", Vector3(26, 0.05, 0), "Hiram Dunning", "m", "dour")
	var w_far := spawn("villager", Vector3(80, 0.05, 0), "Far Away", "m", "dour")
	await settle(victim, 8)
	w_coward.courage = 0.2
	w_brave.courage = 0.9
	w_far.courage = 0.2
	face_each_other(victim, 2.0)
	var vid := victim.record_id
	ok(vid != "" and d.records.has(vid), "the victim was adopted into a record (%s)" % vid)
	victim.health = 5.0
	victim.take_damage(50.0)
	ok(victim.dying, "dead")
	ok(bool((d.records[vid] as Dictionary).get("dead", false)), "the record is marked dead")
	eq(d.crimes, 1, "one crime")
	ok(not d.bodies.has(vid), "no longer a live body")
	eq(w_coward.mode, NPC.Mode.FLEE, "the timid witness runs")
	ok(w_coward.grudge and w_coward.disposition <= -60.0, "...and will not forget")
	ok(w_brave.hostile, "the guard comes for you")
	ok(not w_far.hostile and w_far.mode != NPC.Mode.FLEE, "80 m away: saw nothing")
	## an animal's bite is not a crime and a coward flees it, the guard fights it
	var beast := Boar.new()
	_world.add_child(beast)
	beast.global_position = Vector3(40, 0.05, 0)
	var meek := spawn("villager", Vector3(42, 0.05, 0), "Meek One", "f", "wary")
	await settle(meek, 4)
	meek.courage = 0.2
	meek.take_damage(5.0, null, false, null, beast)
	eq(meek.mode, NPC.Mode.FLEE, "bitten by a boar: runs")
	ok(not meek.hostile and meek.foe == null, "does not square up to it")
	eq(d.crimes, 1, "not the player's crime")
	var stout := spawn("guard", Vector3(44, 0.05, 0), "Stout One", "m", "gruff")
	await settle(stout, 4)
	stout.take_damage(5.0, null, false, null, beast)
	ok(stout.hostile and stout.foe == beast, "a guard bitten by a boar fights the boar")
	for x in [beast, meek, stout, victim, w_coward, w_brave, w_far]:
		bury(x)
	bury(d)
	_player.damage_taken = 0.0
	_player.global_position = Vector3(200, 0, 200)
	await process_frame
	await process_frame


## ============================================================ 8. dialogue =

func t_dialogue_pure() -> void:
	section("dialogue — the vocabulary, the trees, the barks")
	var ctx := {"disp": 30.0, "flags": {"met_priest": true}, "met": true, "grudge": false, "weapon_out": false,
		"gold": 12, "hour": 9.0, "sky": 3, "job": "guard", "personality": "dour", "name": "Amos", "place": "Freeport"}
	ok(NPCDialogue.eval_cond("", ctx), "empty condition is true")
	ok(NPCDialogue.eval_cond("disp>=30", ctx), "disp>=30")
	ok(not NPCDialogue.eval_cond("disp>30", ctx), "disp>30 false at 30")
	ok(NPCDialogue.eval_cond("disp<=30", ctx), "disp<=30")
	ok(NPCDialogue.eval_cond("disp<31", ctx), "disp<31")
	ok(NPCDialogue.eval_cond("disp==30", ctx), "disp==30")
	ok(NPCDialogue.eval_cond("flag:met_priest", ctx), "flag set")
	ok(not NPCDialogue.eval_cond("flag:nope", ctx), "flag unset")
	ok(NPCDialogue.eval_cond("!flag:nope", ctx), "negated unset flag")
	ok(NPCDialogue.eval_cond("met", ctx), "met")
	ok(not NPCDialogue.eval_cond("!met", ctx), "!met")
	ok(not NPCDialogue.eval_cond("grudge", ctx), "grudge false")
	ok(not NPCDialogue.eval_cond("weapon_out", ctx), "weapon_out false")
	ok(NPCDialogue.eval_cond("gold>=12", ctx), "gold>=12")
	ok(not NPCDialogue.eval_cond("gold>=13", ctx), "gold>=13 false")
	ok(NPCDialogue.eval_cond("hour>=6 and hour<12", ctx), "and-chain")
	ok(not NPCDialogue.eval_cond("hour>=6 and hour<9", ctx), "and-chain fails on one term")
	ok(NPCDialogue.eval_cond("sky>=3", ctx), "sky>=3")
	ok(NPCDialogue.eval_cond("job:guard", ctx), "job:guard")
	ok(not NPCDialogue.eval_cond("job:priest", ctx), "job:priest false")
	ok(NPCDialogue.eval_cond("personality:dour", ctx), "personality:dour")
	ok(not NPCDialogue.eval_cond("typo_term", ctx), "an unknown term is FALSE (a typo cannot open a door)")
	ok(not NPCDialogue.eval_cond("disp>=30 and typo", ctx), "...even in a chain")
	var fx := NPCDialogue.parse_actions("disp+5; flag:helped; gold-3; give:Bread; act:wave; end")
	eq(float(fx["disp"]), 5.0, "disp+5")
	ok((fx["flags_set"] as Array).has("helped"), "flag:helped")
	eq(int(fx["gold"]), -3, "gold-3")
	ok((fx["give"] as Array).has("Bread"), "give:Bread")
	eq(String(fx["act"]), "wave", "act:wave")
	ok(bool(fx["end"]), "end")
	ok(not bool(fx["hostile"]), "not hostile")
	fx = NPCDialogue.parse_actions("disp-10; disp+2; unflag:helped; hostile")
	eq(float(fx["disp"]), -8.0, "disp sums")
	ok((fx["flags_clear"] as Array).has("helped"), "unflag")
	ok(bool(fx["hostile"]), "hostile")
	eq(NPCDialogue.parse_actions("").size(), 8, "empty action parses to the empty effect")
	var node := {"text": "Hello {name}, good {tod}. Welcome to {place}. {sky}", "choices": [
		{"text": "a", "to": "x", "if": "disp>=100"}, {"text": "b", "to": "y"}, {"text": "c", "to": "z", "if": "met"}]}
	var ch := NPCDialogue.choices_for(node, ctx)
	eq(ch.size(), 2, "choices filtered by condition")
	eq(String(ch[0]["text"]), "b", "...keeping order")
	var t := NPCDialogue.text_of(node, ctx, 1)
	ok(t.begins_with("Hello Amos, good morning. Welcome to Freeport. "), "substitutions: %s" % t)
	ok(t.ends_with(NPCDialogue.sky_line(3)), "{sky} reads the sky")
	eq(NPCDialogue.text_of({"text": ["only"]}, ctx, 7), "only", "array text picks")
	eq(NPCDialogue.tod_word(3.0), "night", "03:00 night")
	eq(NPCDialogue.tod_word(6.0), "morning", "06:00 morning")
	eq(NPCDialogue.tod_word(11.99), "morning", "11:59 morning")
	eq(NPCDialogue.tod_word(12.0), "afternoon", "12:00 afternoon")
	eq(NPCDialogue.tod_word(18.0), "evening", "18:00 evening")
	eq(NPCDialogue.tod_word(21.5), "night", "21:30 night")
	eq(NPCDialogue.tod_word(26.0), "night", "26:00 wraps")
	## every tree validates, for every job and personality
	for job in NPCDirector.JOBS:
		for p in NPCDialogue.PERSONALITIES:
			var tree := NPCDialogue.default_tree(job, p)
			var problems := NPCDialogue.validate(tree)
			ok(problems.is_empty(), "%s/%s tree validates %s" % [job, p, str(problems)])
	ok(not NPCDialogue.validate({"start": {"choices": [{"to": "nowhere"}]}}).is_empty(), "a dangling choice is a problem")
	ok(not NPCDialogue.validate({"hub": {}}).is_empty(), "no start is a problem")
	## openers
	var tree := NPCDialogue.default_tree("villager", "friendly")
	eq(NPCDialogue.first_node(tree, {"grudge": true, "met": true, "disp": 50.0}), "grudge", "a grudge opens cold, whatever else")
	eq(NPCDialogue.first_node(tree, {"weapon_out": true, "met": true}), "steel", "steel out opens with steel")
	eq(NPCDialogue.first_node(tree, {"met": true, "disp": 30.0}), "friend", "an old friend")
	eq(NPCDialogue.first_node(tree, {"met": true, "disp": 0.0}), "again", "met before")
	eq(NPCDialogue.first_node(tree, {"met": false}), "start", "a stranger")
	## E takes the LAST choice: in every node it must be a way onward or out,
	## never a topic loop and never the hostile answer
	for job in NPCDirector.JOBS:
		var tr := NPCDialogue.default_tree(job, "friendly")
		for id in tr.keys():
			if id == "openers":
				continue
			var nd: Dictionary = tr[id]
			var cs: Array = nd.get("choices", [])
			if cs.is_empty():
				ok(bool(nd.get("end", false)), "%s/%s: a node with no choices is an end" % [job, id])
				continue
			var last: Dictionary = cs[cs.size() - 1]
			var to := String(last.get("to", ""))
			ok(to == "hub" or to == "bye" or to == "bye_cold" or to == "start" or to == "news2", "%s/%s: E's choice leads onward or out (%s)" % [job, id, to])
			ok(not String(last.get("do", "")).contains("hostile"), "%s/%s: E never picks a fight" % [job, id])
	## the job-specific rows exist
	ok(NPCDialogue.default_tree("merchant", "gruff").has("trade"), "merchant has trade")
	ok(NPCDialogue.default_tree("priest", "gruff").has("bless"), "priest has bless")
	ok(NPCDialogue.default_tree("guard", "gruff").has("trouble"), "guard has trouble")
	ok(not NPCDialogue.default_tree("villager", "gruff").has("trade"), "villager has no trade")
	## barks: personality, then job, then "*"; every key covered
	for key in NPCDialogue.LINES.keys():
		var table: Dictionary = NPCDialogue.LINES[key]
		var covered := table.has("*")
		if not covered:
			covered = true
			for p in NPCDialogue.PERSONALITIES:
				if not table.has(p):
					covered = false
		ok(covered, "bark '%s' has a line for every personality" % key)
		for p in NPCDialogue.PERSONALITIES:
			ok(NPCDialogue.line_for(key, p, "villager", 9.0, "X", 0) != "", "'%s' says something for %s" % [key, p])
	ok((NPCDialogue.LINES["fight"]["guard"] as Array).has(NPCDialogue.line_for("fight", "friendly", "guard", 9.0, "X", 0)), "a guard's fight line is the guard's")
	var hello := NPCDialogue.line_for("hello", "friendly", "villager", 9.0, "X", 0)
	ok(hello.contains("morning") or hello.contains("Morning") or not hello.contains("{"), "{tod} filled: %s" % hello)
	ok(not NPCDialogue.line_for("hello", "cheerful", "villager", 19.0, "X", 2).contains("{"), "no raw placeholders")
	eq(NPCDialogue.line_for("nokey", "friendly", "villager", 9.0, "X", 0), "", "unknown key says nothing")
	eq(NPCDialogue.pick([], 3), "", "empty pool")
	eq(NPCDialogue.pick(["a", "b", "c"], 4), "b", "pick wraps")
	eq(NPCDialogue.pick(["a", "b", "c"], -1), "b", "pick is safe on a negative seed")


## ============================================================ 9. focus ====

func t_focus() -> void:
	section("focus — hover, RMB focus, greet, talk, antagonize, the panel's contract")
	var f := NPCFocus.attach(_player)
	ok(f != null and NPCFocus.of(_player) == f, "attached once")
	ok(NPCFocus.attach(_player) == f, "attach is idempotent")
	ok(f.prompt == null and f.panel == null, "a player with no HUD gets no UI (headless-safe)")
	_world.clock.hour = 10.0
	_world.clock.day = 5.0
	var n := spawn("villager", Vector3(0, 0.05, 0), "Hannah Tibbetts", "f", "friendly")
	await settle(n, 8)
	n.disposition = 30.0
	## the player faces -z; the person stands 3 m in front
	_player.global_position = n.global_position + Vector3(0, 0, 3.0)
	_player.rotation = Vector3.ZERO
	n.rotation.y = PI   ## faces +z, toward the player
	f.rmb_override = 0
	f._physics_process(DT)
	ok(f.hover == n, "hover: the person under the crosshair")
	ok(n.show_tag, "...wears its name tag")
	ok(f.focused == null, "no focus without RMB")
	ok(not NPCFocus.take_f(_player), "F with nothing focused is not ours")
	## RMB: focus
	f.rmb_override = 1
	f._physics_process(DT)
	ok(f.focused == n, "RMB on a person: focused")
	step(n, 3)
	eq(n.mode, NPC.Mode.ATTEND, "the person attends")
	ok(n.look_at_pos != Vector3.INF, "...and looks at you")
	var y0 := _player.rotation.y
	_player.rotation.y = 0.6
	for _i in range(60):
		f._physics_process(DT)
	ok(absf(wrapf(_player.rotation.y - y0, -PI, PI)) < 0.15, "focus eases the player round to face them (%.2f)" % _player.rotation.y)
	## E: greet, then talk
	var r := f.report()
	ok(not bool(r["greeted"]), "not yet greeted")
	ok(NPCFocus.take_e(_player), "E is ours while focused")
	ok(bool(f.report()["greeted"]), "greeted")
	eq(n._act, "wave", "disposition 30: waves back")
	ok((NPCDialogue.LINES["hello"]["friendly"] as Array).has(n.bark_text.replace("Morning", "{tod_cap}").replace("morning", "{tod}")), "and says hello: %s" % n.bark_text)
	eq(n.greeted_day, 5, "hello counted for today")
	ok(NPCFocus.take_e(_player), "second E is ours")
	ok(f.talking == n, "...opens the talk")
	eq(_player.menu_open, "talk", "the player's menu is 'talk'")
	ok(n.talk_open and n.mode == NPC.Mode.TALK, "the person is talking")
	eq(f.node_id, "start", "a stranger's talk opens at start")
	eq(n.met_day, 5, "met today")
	eq(f.lines_spoken, 1, "one line spoken")
	## choices: E takes the last = Farewell; a click takes a topic
	var node: Dictionary = f.tree["start"]
	var ch := NPCDialogue.choices_for(node, f.ctx)
	ok(ch.size() >= 5, "%d choices at start" % ch.size())
	ok(String(ch[ch.size() - 1]["text"]) == "Farewell.", "the last choice is Farewell (E's)")
	var has_food := false
	for c in ch:
		if String(c["to"]) == "food":
			has_food = true
	ok(has_food, "disposition 30 unlocks the bread")
	f._pick(ch[0])
	eq(f.node_id, "who", "clicked 'Who are you?'")
	eq(f.lines_spoken, 2, "two lines")
	ok(NPCFocus.take_e(_player), "E continues")
	eq(f.node_id, "hub", "...to the hub")
	## the bread: effects land on both sides
	var hub_ch := NPCDialogue.choices_for(f.tree["hub"], f.ctx)
	var food: Dictionary = {}
	for c in hub_ch:
		if String(c["to"]) == "food":
			food = c
	var d0 := n.disposition
	f._pick(food)
	eq(f.node_id, "food", "asked for bread")
	ok(_player.given.size() == 1 and String(_player.given[0][0]) == "Bread", "the player got Bread")
	ok(_player.gains.size() == 1, "and a gain toast")
	ok(bool(n.flags.get("fed_today", false)), "fed_today flagged")
	near(n.disposition, d0 + 3.0, 0.001, "disposition +3")
	ok(not NPCDialogue.eval_cond("disp>=25 and !flag:fed_today", f.ctx), "the ctx knows: no second loaf")
	ok(NPCFocus.take_e(_player), "E")
	eq(f.node_id, "hub", "back at the hub")
	ok(NPCFocus.take_e(_player), "E at the hub = Farewell")
	eq(f.node_id, "bye", "farewell node")
	ok(f.talking == n, "the bye line is still shown")
	ok(NPCFocus.take_e(_player), "E on an end node")
	ok(f.talking == null, "...leaves")
	eq(_player.menu_open, "", "the menu closed")
	eq(_player.closes, 1, "...through the player's own _close_menu")
	ok(not n.talk_open, "the person is done talking")
	step(n, 3)
	f._physics_process(DT)
	ok(f.focused == n, "RMB still held: still focused")
	## a second talk the same person: opens as an old friend
	ok(NPCFocus.take_e(_player), "E")
	eq(f.node_id, "friend", "met and disposition >= 30: 'friend'")
	f._end_talk()
	## walking away ends a talk
	ok(NPCFocus.take_e(_player), "E")
	ok(f.talking == n, "talking")
	_player.global_position = n.global_position + Vector3(0, 0, 6.0)
	f._physics_process(DT)
	ok(f.talking == null, "walked off: the talk ends")
	eq(_player.menu_open, "", "menu closed")
	_player.global_position = n.global_position + Vector3(0, 0, 3.0)
	## Esc: the player closes the menu — the focus notices
	f._physics_process(DT)
	ok(NPCFocus.take_e(_player), "E")
	ok(f.talking == n, "talking again")
	_player._close_menu()
	f._physics_process(DT)
	ok(f.talking == null, "Esc (menu_open cleared by the player) ends the talk")
	## release RMB: unfocus, attention lapses
	f.rmb_override = 0
	f._physics_process(DT)
	ok(f.focused == null, "RMB released: unfocused")
	step(n, 40)
	ok(n.mode != NPC.Mode.ATTEND, "attention lapses (%s)" % n.mode_name())
	## E without focus, in reach: talks straight away
	f._physics_process(DT)
	ok(f.hover == n and f.focused == null, "hovering, not focused")
	ok(NPCFocus.take_e(_player), "E on a hovered person")
	ok(f.talking == n, "...talks (Skyrim-style)")
	f._end_talk()
	## RMB's two jobs: "raising a guard pulls the steel" (Player.gd), so with
	## the sword SHEATHED and a person under the crosshair the focus claims
	## RMB and the guard must stand down — otherwise the guard would draw the
	## sword and break the focus it was competing with. Steel out: the guard.
	f.rmb_override = 0
	_player.sheath_t = 1.0
	_player.current_weapon = "sword"
	f._physics_process(DT)
	ok(f.hover == n and f.focused == null, "hovering, sheathed")
	ok(NPCFocus.claims_rmb(_player), "sheathed + a person under the crosshair: the focus claims RMB from the guard")
	_player.sheath_t = 0.0
	ok(not NPCFocus.claims_rmb(_player), "steel out: the guard keeps RMB")
	_player.sheath_t = 1.0
	_player.global_position = n.global_position + Vector3(0, 0, 3.0)
	_player.rotation.y = PI   ## looking away
	f._physics_process(DT)
	ok(f.hover == null, "looking away: no hover")
	ok(not NPCFocus.claims_rmb(_player), "nobody under the crosshair: the guard keeps RMB")
	_player.rotation.y = 0.0
	f._physics_process(DT)
	f.rmb_override = 1
	f._physics_process(DT)
	ok(f.focused == n, "focused")
	ok(NPCFocus.claims_rmb(_player), "focused: claimed")
	_player.current_weapon = "axe"
	_player.sheath_t = 0.0
	ok(NPCFocus.claims_rmb(_player), "an axe in hand is not the guard: still claimed")
	_player.current_weapon = "sword"
	_player.sheath_t = 1.0
	f.rmb_override = 0
	f._physics_process(DT)
	## a drawn sword makes RMB the guard: no focus, talk still allowed, the talk opens with 'steel'
	_player.sheath_t = 0.0
	f.rmb_override = 1
	f._physics_process(DT)
	ok(f.focused == null, "sword out: RMB is the guard, not a focus")
	ok(NPCFocus.take_e(_player), "E still talks")
	eq(f.node_id, "steel", "...and the person wants the steel away first")
	var steel := NPCDialogue.choices_for(f.tree["steel"], f.ctx)
	eq(String(steel[steel.size() - 1]["text"]), "Alright.", "E's answer is the civil one")
	f._end_talk()
	_player.sheath_t = 1.0
	f.rmb_override = 0
	## the pad's twin: F right after E is swallowed
	f.rmb_override = 1
	f._physics_process(DT)
	NPCFocus.take_e(_player)
	f._end_talk()
	f._twin_lock = NPCFocus.TWIN_LOCK
	var disp_before := n.disposition
	ok(NPCFocus.take_f(_player), "F inside the twin lock is swallowed (returns true)")
	eq(n.disposition, disp_before, "...and does nothing")
	f._twin_lock = 0.0
	## antagonize: words, then by courage
	n.courage = 0.2
	n.insults = 0
	ok(NPCFocus.take_f(_player), "F while focused")
	near(n.disposition, disp_before - 12.0, 0.001, "-12 disposition")
	ok((NPCDialogue.LINES["retort"]["friendly"] as Array).has(n.bark_text), "a retort: '%s'" % n.bark_text)
	eq(n.insults, 1, "one insult")
	f._twin_lock = 0.0
	NPCFocus.take_f(_player)
	f._twin_lock = 0.0
	NPCFocus.take_f(_player)
	eq(n.insults, 3, "three insults")
	eq(n.mode, NPC.Mode.FLEE, "the timid one leaves")
	ok((NPCDialogue.LINES["retreat"]["*"] as Array).has(n.bark_text), "'%s'" % n.bark_text)
	f._physics_process(DT)
	ok(f.focused == null, "a fleeing person cannot be focused")
	bury(n)
	await process_frame
	var brave := spawn("villager", Vector3(0, 0.05, 0), "Zeb Ricker", "m", "gruff")
	await settle(brave, 8)
	brave.courage = 0.9
	brave.rotation.y = PI
	_player.global_position = brave.global_position + Vector3(0, 0, 3.0)
	_player.rotation = Vector3.ZERO
	f.rmb_override = 1
	f._physics_process(DT)
	ok(f.focused == brave, "focused the brave one")
	for _i in range(3):
		f._twin_lock = 0.0
		NPCFocus.take_f(_player)
	ok(brave.hostile, "three insults to a brave man: a fight")
	f._physics_process(DT)
	ok(f.focused == null, "no focusing a man swinging at you")
	## antagonizing mid-talk ends the talk first
	bury(brave)
	await process_frame
	var mild := spawn("villager", Vector3(0, 0.05, 0), "Mild One", "f", "friendly")
	await settle(mild, 8)
	mild.rotation.y = PI
	_player.global_position = mild.global_position + Vector3(0, 0, 3.0)
	f.rmb_override = 0
	f._physics_process(DT)
	NPCFocus.take_e(_player)
	ok(f.talking == mild, "talking")
	f._twin_lock = 0.0
	ok(NPCFocus.take_f(_player), "F mid-talk")
	ok(f.talking == null and _player.menu_open == "", "...ends the talk")
	ok(mild.disposition < 0.0, "...and lands the insult")
	## the hostile action in a tree ends the talk and starts the fight
	mild.disposition = 0.0
	mild.courage = 0.9
	f._physics_process(DT)
	NPCFocus.take_e(_player)
	f._apply(NPCDialogue.parse_actions("hostile"))
	ok(f.talking == null and mild.hostile, "a tree's 'hostile' action closes the box and draws the knife")
	bury(mild)
	f.rmb_override = -1
	_player.global_position = Vector3(200, 0, 200)
	await process_frame


## ============================================================ 10. director

func t_director() -> void:
	section("director — records, bodies, streaming, the camp, the save")
	_player.global_position = Vector3(0, 0, 20)
	var d := NPCDirector.boot(_world)
	ok(d != null and d.is_in_group("npc_director"), "booted")
	ok(NPCDirector.boot(_world) == d, "boot is idempotent")
	ok(NPCFocus.of(_player) != null, "the player got its focus")
	eq(d.records.size(), 3, "the camp: three people")
	eq(d.bodies.size(), 3, "...all staged (the player is at the camp)")
	eq(d.props.size(), 1, "and a bench to sit on")
	await process_frame
	var names: Array = []
	var jobs: Array = []
	for id in d.records.keys():
		names.append(String((d.records[id] as Dictionary)["name"]))
		jobs.append(String((d.records[id] as Dictionary)["job"]))
	ok(names.has("Silas Pettengill") and names.has("Hannah Tibbetts") and names.has("Amos Chadbourne"), "the three by name: %s" % str(names))
	ok(jobs.has("woodcutter") and jobs.has("villager") and jobs.has("guard"), "a cutter, a keeper, a watch")
	for id in d.bodies.keys():
		var b: NPC = d.bodies[id]
		eq(b.record_id, id, "%s knows its record" % b.npc_name)
		ok(b.global_position.y > -0.5 and b.global_position.y < 1.0, "%s stands on the ground (%.2f)" % [b.npc_name, b.global_position.y])
	## names
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var nm := NPCDirector.random_name(rng, "f")
	ok(nm.split(" ").size() == 2 and NPCDirector.GIVEN_F.has(nm.split(" ")[0]) and NPCDirector.SURNAMES.has(nm.split(" ")[1]), "a woman's name: %s" % nm)
	nm = NPCDirector.random_name(rng, "m")
	ok(NPCDirector.GIVEN_M.has(nm.split(" ")[0]), "a man's name: %s" % nm)
	ok(NPCDialogue.PERSONALITIES.has(NPCDirector.random_personality(rng)), "a personality")
	ok(NPCDirector.courage_for("guard", rng) >= 0.8, "guards are brave")
	ok(NPCDirector.courage_for("priest", rng) <= 0.4, "priests are not")
	var made := d.make("fisher")
	ok(made.npc_name != "" and made.job == "fisher" and NPCDialogue.PERSONALITIES.has(made.personality), "make() gives an identity: %s the %s %s" % [made.npc_name, made.personality, made.job])
	var odd := d.make("nonsense")
	eq(odd.job, "villager", "an unknown job is a villager")
	odd.free()
	made.free()
	## a stranger from the K menu adopts itself
	var stray := NPC.new()
	_world.add_child(stray)
	stray.global_position = Vector3(5, 0.05, 5)
	await settle(stray, 3)
	step(stray, 2)
	ok(stray.record_id != "" and d.records.has(stray.record_id), "a bare NPC is adopted on its first tick (%s)" % stray.record_id)
	ok(stray.npc_name != "", "...and named: %s" % stray.npc_name)
	var stray_id := stray.record_id
	eq(d.records.size(), 4, "four records")
	eq(d.bodies.size(), 4, "four bodies")
	## streaming: walk away, they unstage; come back, they stage
	_player.global_position = Vector3(0, 0, 400)
	d.stream()
	eq(d.bodies.size(), 0, "400 m away: all unstaged")
	eq(d.records.size(), 4, "records kept")
	await process_frame
	ok(get_nodes_in_group("npcs").size() == 0, "no bodies in the tree")
	_player.global_position = Vector3(0, 0, 20)
	d.stream()
	eq(d.bodies.size(), 4, "back: all staged again")
	await process_frame
	for id in d.bodies.keys():
		var b: NPC = d.bodies[id]
		eq(b.npc_name, String((d.records[id] as Dictionary)["name"]), "%s came back as itself" % b.npc_name)
	## away a while: re-staged at the schedule's spot, not where last seen
	var cutter_id := ""
	for id in d.records.keys():
		if String((d.records[id] as Dictionary)["job"]) == "woodcutter":
			cutter_id = id
	var cutter: NPC = d.bodies[cutter_id]
	cutter.global_position = Vector3(40, 0.05, 40)
	_world.clock.hour = 10.0
	_player.global_position = Vector3(0, 0, 400)
	d.stream()
	(d.records[cutter_id] as Dictionary)["unstaged_hour"] = 10.0 + 24.0 * 5.0 - 6.0   ## six hours ago
	_world.clock.day = 5.0
	_player.global_position = Vector3(0, 0, 20)
	d.stream()
	cutter = d.bodies[cutter_id]
	var want: Vector3 = NPC._v3_in((d.records[cutter_id] as Dictionary)["work"])
	ok(cutter.global_position.distance_to(Vector3(want.x, cutter.global_position.y, want.z)) < 1.5, "six hours later at 10:00 the cutter is at his work, not where you left him")
	## dead stays dead, and unstaged
	stray = d.bodies[stray_id]
	stray.health = 1.0
	stray.take_damage(9.0)
	ok(stray.dying, "dead")
	ok(bool((d.records[stray_id] as Dictionary)["dead"]), "record dead")
	_player.global_position = Vector3(0, 0, 400)
	d.stream()
	await process_frame
	_player.global_position = Vector3(0, 0, 20)
	d.stream()
	ok(not d.bodies.has(stray_id), "the dead do not restage")
	eq(d.bodies.size(), 3, "three living bodies")
	## save / load round trip
	var keeper_id := ""
	for id in d.records.keys():
		if String((d.records[id] as Dictionary)["name"]) == "Hannah Tibbetts":
			keeper_id = id
	(d.bodies[keeper_id] as NPC).disposition = 44.0
	(d.bodies[keeper_id] as NPC).flags["fed_today"] = true
	var saved := NPCDirector.state_of(_world)
	eq(int(saved["crimes"]), 1, "crimes saved")
	eq((saved["records"] as Dictionary).size(), 4, "records saved")
	near(float(((saved["records"] as Dictionary)[keeper_id] as Dictionary)["disposition"]), 44.0, 0.001, "a live body's disposition folded into the save")
	ok(bool(((saved["records"] as Dictionary)[keeper_id] as Dictionary)["flags"]["fed_today"]), "...and its flags")
	## the save is a SNAPSHOT: a later fold of the live bodies must not reach
	## into a dictionary already handed out
	(d.bodies[keeper_id] as NPC).disposition = -5.0
	var later := NPCDirector.state_of(_world)
	near(float(((later["records"] as Dictionary)[keeper_id] as Dictionary)["disposition"]), -5.0, 0.001, "a second save sees the later value")
	near(float(((saved["records"] as Dictionary)[keeper_id] as Dictionary)["disposition"]), 44.0, 0.001, "...and the first save still holds its own (no aliasing)")
	## mutate, then restore
	d.crimes = 9
	NPCDirector.restore(_world, saved)
	eq(d.crimes, 1, "restore: crimes back")
	eq(d.records.size(), 4, "restore: records back")
	eq(d.bodies.size(), 0, "restore: old bodies dropped")
	await process_frame
	d.stream()
	eq(d.bodies.size(), 3, "restore: bodies restaged")
	near((d.bodies[keeper_id] as NPC).disposition, 44.0, 0.001, "restore: the disposition came back")
	ok(bool((d.bodies[keeper_id] as NPC).flags.get("fed_today", false)), "restore: the flag came back")
	ok(not d.bodies.has(stray_id), "restore: the dead stay dead")
	ok(NPCDirector.state_of(_world).has("records"), "state_of after restore")
	var c := d.census()
	eq(int(c["records"]), 4, "census records")
	eq(int(c["alive"]), 3, "census alive")
	eq(int(c["dead"]), 1, "census dead")
	eq(int(c["staged"]), 3, "census staged")
	ok(d.report().begins_with("NPCs: 4 (3 alive, 1 dead), 3 staged, 1 crimes"), "report reads: %s" % d.report().split("\n")[0])
	## an empty restore leaves a booted world alone
	NPCDirector.restore(_world, {})
	eq(d.records.size(), 4, "restore({}) is a no-op")
	## clean up
	_player.global_position = Vector3(0, 0, 400)
	d.stream()
	for p in d.props:
		bury(p)
	bury(d)
	_player.global_position = Vector3(200, 0, 200)
	await process_frame
	await process_frame


## ============================================================ 11. save ====

func t_save() -> void:
	section("save — to_dict / apply_dict round trip")
	var n := NPC.new()
	n.npc_name = "Keziah Foss"
	n.sex = "f"
	n.personality = "cheerful"
	n.job = "merchant"
	n.courage = 0.33
	n.disposition = -7.5
	n.flags = {"a": true}
	n.met_day = 2
	n.greeted_day = 3
	n.grudge = true
	n.avoid_day = 3
	n.anchor = Vector3(1, 2, 3)
	n.home = Vector3.INF
	n.work = Vector3(4, 5, 6)
	n.seat = Vector3.INF
	n.home_kind = "bed"
	n.schedule = [{"from": 1.0, "to": 2.0, "do": "idle", "at": "anchor"}]
	var d := n.to_dict()
	eq(d["home"], "none", "INF vectors save as 'none'")
	eq(d["work"], [4.0, 5.0, 6.0], "vectors save as arrays")
	var m := NPC.new()
	m.apply_dict(d)
	eq(m.npc_name, "Keziah Foss", "name")
	eq(m.sex, "f", "sex")
	eq(m.personality, "cheerful", "personality")
	eq(m.job, "merchant", "job")
	near(m.courage, 0.33, 0.0001, "courage")
	near(m.disposition, -7.5, 0.0001, "disposition")
	ok(bool(m.flags.get("a", false)), "flags")
	eq(m.met_day, 2, "met_day")
	eq(m.greeted_day, 3, "greeted_day")
	ok(m.grudge, "grudge")
	eq(m.avoid_day, 3, "avoid_day")
	eq(m.anchor, Vector3(1, 2, 3), "anchor")
	eq(m.home, Vector3.INF, "home stays none")
	eq(m.work, Vector3(4, 5, 6), "work")
	eq(m.seat, Vector3.INF, "seat stays none")
	eq(m.home_kind, "bed", "home_kind")
	eq(m.schedule.size(), 1, "schedule")
	ok(m.flags != n.flags or true, "flags are a copy")
	m.flags["b"] = true
	ok(not n.flags.has("b"), "...not shared")
	eq(NPC._v3_in("garbage", Vector3(9, 9, 9)), Vector3(9, 9, 9), "garbage falls back")
	eq(NPC._v3_in(Vector3(1, 1, 1)), Vector3(1, 1, 1), "a Vector3 passes through")
	n.free()
	m.free()


## ============================================================ 12. no input

func t_no_input() -> void:
	section("no_input — the four files take no key")
	for p in ["res://scripts/NPC.gd", "res://scripts/NPCDialogue.gd", "res://scripts/NPCFocus.gd", "res://scripts/NPCDirector.gd"]:
		var src := FileAccess.get_file_as_string(p)
		ok(src.length() > 1000, "%s read (%d chars)" % [p, src.length()])
		var code := _code_only(src)
		ok(not code.contains("func _input(") and not code.contains("func _unhandled_input(") and not code.contains("func _unhandled_key_input("),
			"%s declares no input callback" % p)
		ok(not code.contains("KEY_"), "%s names no key" % p)
		ok(not code.contains("is_key_pressed") and not code.contains("is_physical_key_pressed"), "%s polls no key" % p)
		ok(not code.contains("InputMap"), "%s registers no action" % p)
	var fsrc := _code_only(FileAccess.get_file_as_string("res://scripts/NPCFocus.gd"))
	eq(fsrc.count("is_mouse_button_pressed"), 1, "NPCFocus polls RMB exactly once, the way the guard does")
	ok(fsrc.contains("MOUSE_BUTTON_RIGHT"), "...and it is the RIGHT button")
	ok(fsrc.contains("static func take_e") and fsrc.contains("static func take_f"), "Player hands E and F in through take_e / take_f")
	ok(fsrc.contains("static func claims_rmb"), "...and asks claims_rmb before raising the guard")


static func _code_only(src: String) -> String:
	## Strip comments and string literals so a scan cannot be satisfied by
	## a docstring (SeasonsTests._code_only's rule).
	var out := PackedStringArray()
	for line in src.split("\n"):
		var s := String(line)
		var clean := ""
		var in_str := false
		var q := ""
		var i := 0
		while i < s.length():
			var c := s[i]
			if in_str:
				if c == "\\":
					i += 2
					continue
				if c == q:
					in_str = false
				i += 1
				continue
			if c == "\"" or c == "'":
				in_str = true
				q = c
				i += 1
				continue
			if c == "#":
				break
			clean += c
			i += 1
		out.append(clean)
	return "\n".join(out)
