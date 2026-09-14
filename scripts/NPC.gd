class_name NPC
extends Enemy
## ===========================================================================
## NPC — a PERSON. The base every villager, crofter, guard, pedlar and priest
## in Myrkfell is built on.
##
## Looks like the player: the box rig is the third-person player's body,
## proportion for proportion (Player._build_body), with two things the player
## never needed — elbows and knees — so a person can sit on a bench, cross
## their arms, wave, and put their hands up. The rig is baked into a skeleton
## + PSX skin by CreatureSkin exactly like every other creature, which means
## it ragdolls, gets shoved, flinches and falls over for free.
##
## Moves like the player: the stride is the player's own gait maths (phase
## rate 4.5 + speed*1.35, legs ±0.5 rad, arms ±0.6 rad in counter-phase), the
## head tracks what it is looking at (the player, mostly), and the Enemy FLOW
## layer breathes, leans and fidgets on top.
##
## Behaves like a person: a schedule by the hour (sleep at home, work at the
## work marker, sit on the bench, wander the yard), a personality that decides
## how it greets you and how it takes an insult, a disposition toward the
## player that survives the save, and reactions — a drawn weapon makes it
## wary, being hit makes it fight or flee by its courage, a crouching stranger
## behind it gets asked what they think they are doing.
##
## Extends Enemy on purpose: hostile NPCs fight with the same melee loop,
## flinch, nerve and rout as every mob; the player's sword finds them through
## the "enemies" group; mobs' swings clip them too. `aggro_radius` is 0 so
## the base never wakes it on its own — only a struck NPC (or a witnessed
## murder) ever calls _set_agitated.
##
## Focus / talk (RDR2-style): NPCFocus (on the player) drives `attend()`,
## `greet()`, `antagonize()`, `begin_talk()` / `end_talk()`. Dialogue trees
## live in NPCDialogue; the records that outlive this node live in
## NPCDirector. This file owns the BODY and the BRAIN and nothing else.
## ===========================================================================

## ---------------------------------------------------------- identity ------
var npc_name := ""                ## "Ezra Libby" (NPCDirector names the nameless)
var sex := "m"                    ## "m" | "f" — hair, beard, the cut of the tunic
var personality := "friendly"     ## friendly | gruff | wary | cheerful | dour
var job := "villager"             ## villager | crofter | woodcutter | fisher | guard | merchant | priest
var courage := 0.5                ## 0 runs from a raised voice, 1 fights back
var disposition := 0.0            ## -100 .. 100 toward the player (saved)
var flags: Dictionary = {}        ## dialogue flags (saved)
var met_day := -1                 ## last day the player TALKED to this person
var greeted_day := -1             ## last day a hello was exchanged
var insults := 0                  ## antagonize count this encounter
var grudge := false               ## struck by the player, ever (saved)
var avoid_day := -1               ## keeps its distance from the player this day
var record_id := ""               ## NPCDirector record key ("" = unadopted)
var dialogue: Dictionary = {}     ## an authored talk tree; empty = NPCDialogue.default_tree
var look: Dictionary = {}         ## the Character Creator's knobs (default_look / random_look)

## ---------------------------------------------------------- places --------
var anchor := Vector3.ZERO        ## where it belongs (set on spawn)
var home := Vector3.INF           ## a door: it goes INDOORS here (INF = none)
var work := Vector3.INF           ## the work marker (INF = none)
var seat := Vector3.INF           ## a bench / log (INF = none)
var seat_h := 0.45                ## seat height above the ground
var work_yaw := INF               ## facing at the work marker (INF = face anchor)
var schedule: Array = []          ## [{from, to, do, at}] — default_schedule(job)

## ---------------------------------------------------------- brain ---------
enum Mode { IDLE, WANDER, GOTO, WORK, SIT, SLEEP, ATTEND, TALK, FLEE, COWER, HOSTILE }
const MODE_NAMES := ["idle", "wander", "goto", "work", "sit", "sleep", "attend", "talk", "flee", "cower", "hostile"]

const WALK_SPEED := 1.5
const HURRY_SPEED := 2.6
const RUN_SPEED := 4.6
const ARRIVE_R := 0.7
const WANDER_R := 6.0
const LOOK_R := 7.0               ## the head follows the player inside this
const LOOK_YAW_MAX := 1.2         ## rad — a neck, not an owl
const LOOK_PITCH_MAX := 0.55
const GREET_R := 4.0
const WARY_R := 4.5               ## a drawn weapon this close is noticed
const COWER_R := 2.2              ## ...and this close it is a threat
const SNEAK_R := 3.0
const FLEE_UNTIL := 26.0          ## m of distance that ends a flight
const FLEE_MAX_T := 14.0
const COWER_T := 4.0
const AVOID_R := 8.0
const ATTEND_HOLD := 0.5          ## s without a refresh before attention lapses
const REAGGRO_R := 14.0           ## a hostile calmed by the leash re-engages inside this
const FREEZE_R := 70.0            ## beyond this from the player the brain sleeps
const STUCK_T := 2.5
const GIVE_UP_T := 14.0
const INSULT_SNAP := -35.0        ## disposition below which an insult draws a reaction

var mode: int = Mode.IDLE
var mode_t := 0.0
var goto_target := Vector3.INF
var goto_then: int = Mode.IDLE
var goto_speed := WALK_SPEED
var focus_by: Node3D = null       ## who is focusing / talking to us
var talk_open := false
var hostile := false
var indoors := false              ## hidden inside its house
var slot_key := ""                ## the schedule slot last applied
var slot_at := Vector3.INF        ## where that slot wanted us
var shelter := false              ## the sky drove it indoors
var bark_text := ""               ## last thing said (NPCFocus draws it)
var bark_t := 0.0
var _attend_t := 0.0
var _idle_next := 0.0
var _work_break := 0.0
var _flee_t := 0.0
var _cower_t := 0.0
var _flee_from := Vector3.INF
var _stuck_t := 0.0
var _stuck_pos := Vector3.INF
var _dodge_t := 0.0
var _dodge_dir := Vector3.ZERO
var _give_up_t := 0.0
var _wary_t := 0.0
var _wary_cool := 0.0
var _sneak_cool := 0.0
var _greet_cool := 0.0
var _bark_cool := 0.0
var _sched_t := 0.0
var _sky_t := 0.0
var _sky_level := 0
var _resume_mode: int = Mode.IDLE
var _frozen := false
var _booted := false
var _hit_by_player := false       ## the last blow was the player's
var show_tag := false             ## NPCFocus: the player is looking at us
var home_kind := "door"           ## "door" = vanishes indoors to sleep; "bed" = lies down at `home`

## ------------------------------------------------------------- rig --------
var rig: Node3D
var spine: Node3D
var head_pivot: Node3D
var shoulder_l: Node3D
var shoulder_r: Node3D
var elbow_l: Node3D
var elbow_r: Node3D
var hip_l: Node3D
var hip_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var tool_axe: Node3D
var tool_broom: Node3D
var tool_rod: Node3D
var name_label: Label3D
var _act := ""                    ## one-shot gesture playing
var _act_t := 0.0
var _act_len := 0.0
var _gait_k := 0.0                ## 0..1 — how much of the stride to show
var _talk_t := 0.0
var _work_t := 0.0
var _head_rot := Vector2.ZERO     ## (pitch, yaw) the head is at
var _pose_y := 0.0                ## rig height offset of the pose (sit, cower), under the bob
var _p_lsh := Vector3.ZERO        ## eased pose state, written absolutely each frame
var _p_rsh := Vector3.ZERO
var _p_lel := Vector3.ZERO
var _p_rel := Vector3.ZERO
var _p_hl := Vector3.ZERO
var _p_hr := Vector3.ZERO
var _p_kl := Vector3.ZERO
var _p_kr := Vector3.ZERO
var _p_sp := Vector3.ZERO
var look_at_pos := Vector3.INF    ## what the head tracks (INF = ahead)

const ACT_LEN := {"wave": 1.6, "nod": 0.7, "shrug": 1.0, "point": 1.4, "bow": 1.3, "shake": 0.9}

## Palette (the player's own skin / hair / leather, plus cloth by job)
const SKIN_COL := Color(0.62, 0.46, 0.36)
const HAIR_COLS := [Color(0.17, 0.12, 0.08), Color(0.32, 0.22, 0.12), Color(0.55, 0.45, 0.30), Color(0.08, 0.07, 0.06), Color(0.60, 0.58, 0.55)]
const LEATHER_COL := Color(0.26, 0.18, 0.12)
const FOOT_COL := Color(0.10, 0.09, 0.08)
const JOB_CLOTH := {
	"villager": [Color(0.42, 0.36, 0.26), Color(0.30, 0.24, 0.18)],
	"crofter": [Color(0.36, 0.34, 0.24), Color(0.28, 0.22, 0.16)],
	"woodcutter": [Color(0.34, 0.26, 0.18), Color(0.24, 0.20, 0.14)],
	"fisher": [Color(0.28, 0.34, 0.38), Color(0.22, 0.24, 0.24)],
	"guard": [Color(0.24, 0.26, 0.34), Color(0.20, 0.18, 0.16)],
	"merchant": [Color(0.46, 0.26, 0.22), Color(0.28, 0.20, 0.16)],
	"priest": [Color(0.16, 0.14, 0.16), Color(0.14, 0.12, 0.12)],
}
const JOB_TITLE := {
	"villager": "Villager", "crofter": "Crofter", "woodcutter": "Woodcutter",
	"fisher": "Fisher", "guard": "Guard", "merchant": "Merchant", "priest": "Priest",
}


func _init() -> void:
	display_name = "Villager"
	max_health = 60.0
	wander_speed = WALK_SPEED
	chase_speed = RUN_SPEED
	attack_range = 1.7
	attack_damage = 9.0
	attack_cooldown = 1.1
	aggro_radius = 0.0            ## NEVER wakes on proximity — only when struck
	leash_radius = 40.0
	strong_max_range = -1.0       ## no telegraphed special: fists and a knife
	strong_from_melee = false
	can_climb = false
	duelist = false
	nerve = 0.3
	rout_line = "runs for it"
	mass = 78.0
	skin_tile = "cloth"
	families = ["humanoid"]
	xp_tier = 0
	orb_tier = 0


func _ready() -> void:
	if display_name == "Villager":
		display_name = String(JOB_TITLE.get(job, "Villager"))
	if schedule.is_empty():
		schedule = default_schedule(job)
	if anchor == Vector3.ZERO:
		anchor = global_position
	if look.is_empty():
		look = default_look(npc_name, sex, job)
	super()
	add_to_group("npcs")
	_idle_next = randf_range(4.0, 9.0)
	_work_break = randf_range(18.0, 40.0)
	## Nobody spawns from a menu "confused" — that is the mob's lost-circles walk.
	confused = false


func _process(_delta: float) -> void:
	## The tag over the head: the last thing said while it is fresh, the name
	## while the player is looking at us, nothing otherwise.
	if name_label == null:
		return
	if bark_t > 0.0 and bark_text != "" and not dying:
		name_label.text = "\"%s\"" % bark_text
		name_label.modulate = Color(0.96, 0.93, 0.84)
		name_label.visible = true
	elif show_tag and not dying and not indoors:
		name_label.text = npc_name if npc_name != "" else display_name
		name_label.modulate = Color(0.94, 0.90, 0.80)
		name_label.visible = true
	else:
		name_label.visible = false


## ============================================================ the body ====

func _build_body() -> void:
	## The player's third-person body, box for box, plus elbows and knees —
	## now PARAMETERISED by `look` (the Character Creator's knobs, 2026-09-14):
	## height / bulk / limb / head scale the rig, the colours are the
	## person's own, and hair, beard and hat are picked, not hashed.
	## Everything is a BoxMesh + StandardMaterial3D under a Node3D pivot,
	## which is exactly what CreatureSkin bakes.
	if look.is_empty():
		look = default_look(npc_name, sex, job)
	var H := clampf(float(look.get("height", 1.0)), 0.6, 1.6)      ## whole-body height
	var B := clampf(float(look.get("bulk", 1.0)), 0.6, 1.6)        ## widths
	var LB := clampf(float(look.get("limb", 1.0)), 0.7, 1.4)       ## limb length
	var HS := clampf(float(look.get("head", 1.0)), 0.7, 1.4)       ## head size
	var skin_c: Color = look.get("skin", SKIN_COL)
	var hair: Color = look.get("hair_col", HAIR_COLS[0])
	var cloth: Array = JOB_CLOTH.get(job, JOB_CLOTH["villager"])
	var tunic: Color = look.get("tunic", cloth[0])
	var breeches: Color = look.get("breeches", cloth[1])
	var hair_style := str(look.get("hair", "short"))
	var beard := str(look.get("beard", "none"))
	var hat := str(look.get("hat", "job"))
	if hat == "job":
		hat = _job_hat(job)
	_add_collision(Vector3(0.62 * B, 1.78 * H, 0.56 * B), Vector3(0, 0.89 * H, 0))
	base_body_color = tunic

	rig = Node3D.new()
	rig.name = "Rig"
	add_child(rig)
	loco_root = rig

	## Legs: hip pivot -> thigh -> knee pivot -> shin + foot. Hips at the
	## player's (±0.14, 0.74) scaled; the foot's sole lands on y = 0.
	var leg := H * LB
	var hip_y := 0.74 * leg
	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		var hip := Node3D.new()
		hip.name = "HipL" if i == 0 else "HipR"
		rig.add_child(hip)
		hip.position = Vector3(0.14 * side * B, hip_y, 0.0)
		_box_in(hip, Vector3(0.18 * B, 0.40 * leg, 0.22 * B), breeches, Vector3(0, -0.20 * leg, 0))
		var knee := Node3D.new()
		knee.name = "KneeL" if i == 0 else "KneeR"
		hip.add_child(knee)
		knee.position = Vector3(0, -0.40 * leg, 0)
		_box_in(knee, Vector3(0.17 * B, 0.34 * leg, 0.21 * B), breeches, Vector3(0, -0.17 * leg, 0))
		_box_in(knee, Vector3(0.20 * B, 0.12 * leg, 0.34), FOOT_COL, Vector3(0, -0.28 * leg, -0.05))
		walk_legs.append(hip)
		if i == 0:
			hip_l = hip
			knee_l = knee
		else:
			hip_r = hip
			knee_r = knee

	## Pelvis on the rig; everything above the waist on the spine so the
	## upper body can lean and twist without the legs coming along.
	_box_in(rig, Vector3(0.38 * B, 0.22 * H, 0.24 * B), breeches, Vector3(0, hip_y - 0.02 * H, 0))
	spine = Node3D.new()
	spine.name = "Spine"
	rig.add_child(spine)
	spine.position = Vector3(0, hip_y + 0.09 * H, 0)
	var torso := _box_in(spine, Vector3(0.44 * B, 0.62 * H, 0.26 * B), tunic, Vector3(0, 0.22 * H, 0))
	body_mat = torso.material_override as StandardMaterial3D
	if sex == "f":
		## a long skirt over the breeches
		_box_in(rig, Vector3(0.42 * B, 0.50 * leg, 0.28 * B), tunic.darkened(0.12), Vector3(0, hip_y - 0.30 * leg, 0))
	if job == "guard":
		_box_in(spine, Vector3(0.46 * B, 0.50 * H, 0.28 * B), Color(0.55, 0.16, 0.14), Vector3(0, 0.20 * H, 0.0))  ## tabard
	elif job == "priest":
		_box_in(rig, Vector3(0.46 * B, 0.66 * H, 0.30 * B), tunic, Vector3(0, hip_y - 0.38 * leg + 0.66 * H * 0.5 - 0.1 * H, 0))  ## the robe

	## Arms: shoulder pivot -> upper arm -> elbow pivot -> forearm + hand.
	## Shoulders at the player's (±0.26, 1.30) => spine-local y 0.47; the hand
	## ends at the player's -0.50.
	var arm := H * LB
	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		var sh := Node3D.new()
		sh.name = "ShoulderL" if i == 0 else "ShoulderR"
		spine.add_child(sh)
		sh.position = Vector3(0.26 * side * B, 0.47 * H, 0.0)
		_box_in(sh, Vector3(0.14 * B, 0.24 * arm, 0.15 * B), tunic, Vector3(0, -0.12 * arm, 0))
		var el := Node3D.new()
		el.name = "ElbowL" if i == 0 else "ElbowR"
		sh.add_child(el)
		el.position = Vector3(0, -0.24 * arm, 0)
		_box_in(el, Vector3(0.13 * B, 0.22 * arm, 0.14 * B), tunic.darkened(0.08), Vector3(0, -0.11 * arm, 0))
		_box_in(el, Vector3(0.13 * B, 0.15 * arm, 0.14 * B), skin_c, Vector3(0, -0.27 * arm, 0.02))
		walk_arms.append(sh)
		if i == 0:
			shoulder_l = sh
			elbow_l = el
		else:
			shoulder_r = sh
			elbow_r = el

	## Head: the player's neck pivot at y 1.44 => spine-local 0.61.
	head_pivot = Node3D.new()
	head_pivot.name = "Head"
	spine.add_child(head_pivot)
	head_pivot.position = Vector3(0, 0.61 * H, 0)
	_box_in(head_pivot, Vector3(0.24, 0.26, 0.25) * HS, skin_c, Vector3(0, 0.14 * HS, 0))
	_box_in(head_pivot, Vector3(0.05, 0.05, 0.04) * HS, skin_c, Vector3(0, 0.10 * HS, -0.14 * HS))
	## Hair by style; the cap of hair is everyone's but the bald.
	if hair_style != "bald":
		_box_in(head_pivot, Vector3(0.26, 0.09, 0.27) * HS, hair, Vector3(0, 0.295 * HS, 0.01 * HS))
	match hair_style:
		"long":
			_box_in(head_pivot, Vector3(0.26, 0.30, 0.09) * HS, hair, Vector3(0, 0.12 * HS, 0.13 * HS))
		"bun":
			_box_in(head_pivot, Vector3(0.26, 0.20, 0.08) * HS, hair, Vector3(0, 0.17 * HS, 0.125 * HS))
			_box_in(head_pivot, Vector3(0.12, 0.12, 0.12) * HS, hair, Vector3(0, 0.26 * HS, 0.17 * HS))
		"mohawk":
			_box_in(head_pivot, Vector3(0.06, 0.14, 0.24) * HS, hair, Vector3(0, 0.36 * HS, 0.0))
		"bald":
			pass
		_:
			_box_in(head_pivot, Vector3(0.26, 0.20, 0.08) * HS, hair, Vector3(0, 0.17 * HS, 0.125 * HS))
	match beard:
		"stubble":
			_box_in(head_pivot, Vector3(0.22, 0.07, 0.05) * HS, hair.lerp(skin_c, 0.55), Vector3(0, 0.03 * HS, -0.11 * HS))
		"full":
			_box_in(head_pivot, Vector3(0.20, 0.10, 0.06) * HS, hair, Vector3(0, 0.02 * HS, -0.11 * HS))
		"braided":
			_box_in(head_pivot, Vector3(0.20, 0.10, 0.06) * HS, hair, Vector3(0, 0.02 * HS, -0.11 * HS))
			_box_in(head_pivot, Vector3(0.06, 0.16, 0.05) * HS, hair, Vector3(0, -0.10 * HS, -0.10 * HS))
		_:
			pass
	_add_eye(Vector3(-0.06 * HS, 0.16 * HS, -0.125 * HS), Vector3(0.04, 0.03, 0.02) * HS, head_pivot)
	_add_eye(Vector3(0.06 * HS, 0.16 * HS, -0.125 * HS), Vector3(0.04, 0.03, 0.02) * HS, head_pivot)
	var eye_c: Color = look.get("eye_col", Color(0.12, 0.10, 0.08))
	for em in eye_mats:
		em.albedo_color = eye_c
	match hat:
		"helm":
			_box_in(head_pivot, Vector3(0.29, 0.13, 0.30) * HS, Color(0.45, 0.46, 0.50), Vector3(0, 0.30 * HS, 0), Vector3.ZERO, true)
			_box_in(head_pivot, Vector3(0.05, 0.15, 0.03) * HS, Color(0.45, 0.46, 0.50), Vector3(0, 0.185 * HS, -0.14 * HS), Vector3.ZERO, true)
		"cap":
			_box_in(head_pivot, Vector3(0.30, 0.06, 0.31) * HS, LEATHER_COL, Vector3(0, 0.31 * HS, 0))  ## cap
		"hood":
			_box_in(head_pivot, Vector3(0.30, 0.22, 0.30) * HS, tunic, Vector3(0, 0.23 * HS, 0.04 * HS))    ## hood
		"brim":
			_box_in(head_pivot, Vector3(0.34, 0.05, 0.36) * HS, Color(0.30, 0.22, 0.14), Vector3(0, 0.30 * HS, 0))  ## brim
		_:
			pass

	## Tools live in the right hand and show only while the job is at work.
	tool_axe = Node3D.new()
	tool_axe.name = "Axe"
	elbow_r.add_child(tool_axe)
	tool_axe.position = Vector3(0, -0.28 * arm, 0.0)
	_box_in(tool_axe, Vector3(0.05, 0.05, 0.78), Color(0.36, 0.26, 0.16), Vector3(0, 0, -0.30))
	_box_in(tool_axe, Vector3(0.05, 0.18, 0.16), Color(0.40, 0.42, 0.44), Vector3(0, -0.06, -0.66), Vector3.ZERO, true)
	tool_axe.visible = false
	tool_broom = Node3D.new()
	tool_broom.name = "Broom"
	elbow_r.add_child(tool_broom)
	tool_broom.position = Vector3(0, -0.28 * arm, 0.0)
	_box_in(tool_broom, Vector3(0.04, 1.30, 0.04), Color(0.50, 0.40, 0.24), Vector3(0, -0.30, 0))
	_box_in(tool_broom, Vector3(0.22, 0.20, 0.08), Color(0.62, 0.52, 0.30), Vector3(0, -0.98, 0))
	tool_broom.visible = false
	tool_rod = Node3D.new()
	tool_rod.name = "Rod"
	elbow_r.add_child(tool_rod)
	tool_rod.position = Vector3(0, -0.28 * arm, 0.0)
	_box_in(tool_rod, Vector3(0.03, 0.03, 1.60), Color(0.42, 0.34, 0.20), Vector3(0, 0.05, -0.70))
	tool_rod.visible = false

	## Name / bark label — a billboard the focus code turns on.
	name_label = Label3D.new()
	name_label.name = "NameTag"
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.no_depth_test = true
	name_label.font_size = 36
	name_label.pixel_size = 0.0045
	name_label.outline_size = 8
	name_label.modulate = Color(0.94, 0.90, 0.80)
	name_label.position = Vector3(0, 2.08 * H, 0)
	name_label.visible = false
	add_child(name_label)
	## Enemy tints eye_mats red when agitated. People do not get demon eyes.
	eye_mats.clear()


static func _job_hat(for_job: String) -> String:
	match for_job:
		"guard":
			return "helm"
		"woodcutter", "crofter":
			return "cap"
		"priest":
			return "hood"
		"merchant":
			return "brim"
		_:
			return "none"


func rebuild_body() -> void:
	## The Character Creator changed `look`, `sex` or `job`: tear the rig,
	## the collision, the tag and the skin down and build them again, in
	## place, mid-game. The nodes are removed NOW (not queue_free'd alone),
	## or CreatureSkin.bake would collect the old boxes along with the new.
	var was_pos := global_position if is_inside_tree() else position
	if skin != null and is_instance_valid(skin):
		remove_child(skin)
		skin.queue_free()
		skin = null
	if has_meta("creature_skin"):
		remove_meta("creature_skin")
	for c in get_children():
		if c is CollisionShape3D or c == rig or c == name_label or c is MeshInstance3D:
			remove_child(c)
			c.queue_free()
	walk_legs.clear()
	walk_arms.clear()
	eye_mats.clear()
	_flow_applied.clear()
	rig = null
	spine = null
	head_pivot = null
	tool_axe = null
	tool_broom = null
	tool_rod = null
	name_label = null
	_build_body()
	skin = CreatureSkin.bake(self, _skin_opts())
	if is_inside_tree():
		global_position = was_pos


## ------------------------------------------------------------- the look --

const LOOK_KEYS := ["height", "bulk", "limb", "head", "skin", "hair_col", "eye_col", "hair", "beard", "hat", "tunic", "breeches"]
const SKIN_TONES := [Color(0.62, 0.46, 0.36), Color(0.72, 0.56, 0.44), Color(0.55, 0.40, 0.30), Color(0.80, 0.66, 0.54), Color(0.45, 0.32, 0.24)]


static func default_look(for_name: String, for_sex: String, for_job: String) -> Dictionary:
	## What a person looked like before there was a creator: the hashed
	## hair colour and beard, the job's cloth, the one skin tone.
	var h := absi(hash(for_name))
	var cloth: Array = JOB_CLOTH.get(for_job, JOB_CLOTH["villager"])
	return {
		"height": 1.0, "bulk": 1.0, "limb": 1.0, "head": 1.0,
		"skin": SKIN_COL, "hair_col": HAIR_COLS[h % HAIR_COLS.size()],
		"eye_col": Color(0.12, 0.10, 0.08),
		"hair": "long" if for_sex == "f" else "short",
		"beard": ("full" if absi(hash(for_name + "beard")) % 3 == 0 else "none") if for_sex != "f" else "none",
		"hat": "job", "tunic": cloth[0], "breeches": cloth[1],
	}


static func random_look(rng: RandomNumberGenerator, for_sex: String, for_job: String) -> Dictionary:
	var cloth: Array = JOB_CLOTH.get(for_job, JOB_CLOTH["villager"])
	var tunic: Color = cloth[0]
	var breeches: Color = cloth[1]
	tunic = Color.from_hsv(fmod(tunic.h + rng.randf_range(-0.08, 0.08) + 1.0, 1.0), clampf(tunic.s + rng.randf_range(-0.1, 0.1), 0.0, 1.0), clampf(tunic.v + rng.randf_range(-0.1, 0.1), 0.1, 0.9))
	breeches = Color.from_hsv(fmod(breeches.h + rng.randf_range(-0.05, 0.05) + 1.0, 1.0), breeches.s, clampf(breeches.v + rng.randf_range(-0.08, 0.08), 0.1, 0.8))
	var hairs := ["short", "long", "bald", "bun", "mohawk"]
	var beards := ["none", "stubble", "full", "braided"]
	return {
		"height": snappedf(rng.randf_range(0.88, 1.14), 0.01),
		"bulk": snappedf(rng.randf_range(0.85, 1.22), 0.01),
		"limb": snappedf(rng.randf_range(0.92, 1.08), 0.01),
		"head": snappedf(rng.randf_range(0.92, 1.10), 0.01),
		"skin": SKIN_TONES[rng.randi_range(0, SKIN_TONES.size() - 1)],
		"hair_col": HAIR_COLS[rng.randi_range(0, HAIR_COLS.size() - 1)],
		"eye_col": [Color(0.12, 0.10, 0.08), Color(0.25, 0.32, 0.20), Color(0.22, 0.30, 0.42), Color(0.35, 0.24, 0.14)][rng.randi_range(0, 3)],
		"hair": hairs[rng.randi_range(0, hairs.size() - 1)] if for_sex != "f" else ["long", "bun", "short"][rng.randi_range(0, 2)],
		"beard": beards[rng.randi_range(0, beards.size() - 1)] if for_sex != "f" else "none",
		"hat": "job", "tunic": tunic, "breeches": breeches,
	}


static func look_to_json(lk: Dictionary) -> Dictionary:
	var d := {}
	for k in lk.keys():
		var v = lk[k]
		d[k] = (v as Color).to_html(false) if v is Color else v
	return d


static func look_from_json(d: Dictionary) -> Dictionary:
	var lk := {}
	for k in d.keys():
		var v = d[k]
		if k in ["skin", "hair_col", "eye_col", "tunic", "breeches"] and v is String:
			lk[k] = Color.html(String(v))
		else:
			lk[k] = v
	return lk


func _skin_opts() -> Dictionary:
	return {"tile": skin_tile, "mass": mass, "exclude": [name_label]}


## ============================================================ schedule ====

static func default_schedule(for_job: String) -> Array:
	## Hours are game hours on the 24-hour clock; a slot may wrap midnight.
	match for_job:
		"guard":
			return [{"from": 0.0, "to": 24.0, "do": "work", "at": "work"}]
		"woodcutter", "crofter":
			return [
				{"from": 21.0, "to": 5.5, "do": "sleep", "at": "home"},
				{"from": 5.5, "to": 7.0, "do": "idle", "at": "anchor"},
				{"from": 7.0, "to": 12.0, "do": "work", "at": "work"},
				{"from": 12.0, "to": 13.0, "do": "sit", "at": "seat"},
				{"from": 13.0, "to": 18.5, "do": "work", "at": "work"},
				{"from": 18.5, "to": 21.0, "do": "idle", "at": "anchor"},
			]
		"merchant":
			return [
				{"from": 22.0, "to": 6.5, "do": "sleep", "at": "home"},
				{"from": 6.5, "to": 8.0, "do": "idle", "at": "anchor"},
				{"from": 8.0, "to": 19.0, "do": "work", "at": "work"},
				{"from": 19.0, "to": 22.0, "do": "sit", "at": "seat"},
			]
		"priest":
			return [
				{"from": 23.0, "to": 5.0, "do": "sleep", "at": "home"},
				{"from": 5.0, "to": 9.0, "do": "work", "at": "work"},
				{"from": 9.0, "to": 17.0, "do": "wander", "at": "anchor"},
				{"from": 17.0, "to": 20.0, "do": "work", "at": "work"},
				{"from": 20.0, "to": 23.0, "do": "sit", "at": "seat"},
			]
		_:
			return [
				{"from": 22.0, "to": 6.0, "do": "sleep", "at": "home"},
				{"from": 6.0, "to": 8.0, "do": "idle", "at": "anchor"},
				{"from": 8.0, "to": 12.0, "do": "work", "at": "work"},
				{"from": 12.0, "to": 13.0, "do": "sit", "at": "seat"},
				{"from": 13.0, "to": 18.0, "do": "work", "at": "work"},
				{"from": 18.0, "to": 22.0, "do": "wander", "at": "anchor"},
			]


static func slot_for(sched: Array, hour: float) -> Dictionary:
	## The slot that owns `hour` (wrapping midnight). Empty = no slot.
	var h := fposmod(hour, 24.0)
	for s in sched:
		var a := float(s.get("from", 0.0))
		var b := float(s.get("to", 24.0))
		if a <= b:
			if h >= a and h < b:
				return s
		elif h >= a or h < b:
			return s
	return {}


func place_for(at: String) -> Vector3:
	## Resolve a slot's "at" to a point, with honest fallbacks: no bench means
	## idling where it belongs, no house means no indoors.
	match at:
		"home":
			return home
		"work":
			return work if work != Vector3.INF else anchor
		"seat":
			return seat if seat != Vector3.INF else anchor
		_:
			return anchor


func sched() -> Array:
	## The schedule in force: the authored one, else the job's default (a
	## bare NPC.new() has not been through _ready yet).
	return schedule if not schedule.is_empty() else default_schedule(job)


func resolve_slot(s: Dictionary) -> Dictionary:
	## What a slot actually means for THIS person: {"do": ..., "at": Vector3}.
	## sleep without a home becomes sitting (or idling); sitting without a
	## seat becomes idling.
	var what := String(s.get("do", "idle"))
	var where := place_for(String(s.get("at", "anchor")))
	if what == "sleep" and where == Vector3.INF:
		what = "sit" if seat != Vector3.INF else "idle"
		where = place_for("seat")
	if what == "sit" and seat == Vector3.INF:
		what = "idle"
	if what == "work" and work == Vector3.INF:
		what = "wander"
	if where == Vector3.INF:
		where = anchor
	return {"do": what, "at": where}


static func mode_for(what: String) -> int:
	match what:
		"sleep":
			return Mode.SLEEP
		"work":
			return Mode.WORK
		"sit":
			return Mode.SIT
		"wander":
			return Mode.WANDER
		_:
			return Mode.IDLE


func expected_spot(hour: float) -> Vector3:
	## Where the schedule says this person is at `hour` — the director uses it
	## to place a body it re-stages after the player was away.
	var r := resolve_slot(slot_for(sched(), hour))
	var at: Vector3 = r["at"]
	return at


## ============================================================ the world ====

func _world_node() -> Node:
	return get_tree().get_first_node_in_group("world")


func hour_now() -> float:
	var w := _world_node()
	if w == null:
		return 12.0
	if w.has_method("daynight"):
		var dn: Object = w.call("daynight")
		if dn != null and "hour" in dn:
			return float(dn.get("hour"))
	var dnv = w.get("_daynight")
	if dnv != null and dnv is Object and "hour" in dnv:
		return float(dnv.get("hour"))
	return 12.0


func day_now() -> int:
	var w := _world_node()
	if w == null:
		return 0
	if w.has_method("daynight"):
		var dn: Object = w.call("daynight")
		if dn != null and "day" in dn:
			return int(floorf(float(dn.get("day"))))
	var dnv = w.get("_daynight")
	if dnv != null and dnv is Object and "day" in dnv:
		return int(floorf(float(dnv.get("day"))))
	return 0


func sky_level() -> int:
	## Weather.Level: CLEAR 0 · OVERCAST 1 · DRIZZLE 2 · RAIN 3 · STORM 4.
	var w := _world_node()
	if w == null or not w.has_method("weather"):
		return 0
	var we: Object = w.call("weather")
	if we == null or not ("level" in we):
		return 0
	return int(we.get("level"))


## ============================================================ the brain ====

func _physics_process(delta: float) -> void:
	mode_t += delta
	_tick_clocks_npc(delta)
	if not _booted:
		_boot()

	if hostile:
		_hostile_check()
		if hostile:
			## The Enemy loop fights: chase, shuffle, swing, flinch, nerve, rout.
			_pre_loco()
			super(delta)
			return

	if knocked:
		_knocked_tick(delta)
		return
	if dying:
		if skin == null or not skin.is_down():
			move_and_slide()
		return
	if burn_t > 0.0:
		## Alight: nothing else matters, it runs. Enemy's own tick burns it.
		if mode != Mode.FLEE:
			_start_flee(global_position + Vector3(randf() - 0.5, 0.0, randf() - 0.5))
		burn_t -= delta
		_burn_tick -= delta
		if _burn_tick <= 0.0:
			_burn_tick = 0.45
			health -= burn_dps * 0.45
			_shed_embers()
			if health <= 0.0:
				burn_t = 0.0
				_die()
				move_and_slide()
				return

	var pl := _get_player()
	var pd := 9999.0
	var to_p := Vector3.ZERO
	if pl != null:
		to_p = pl.global_position - global_position
		to_p.y = 0.0
		pd = to_p.length()

	## Far from the player the brain sleeps: gravity, the schedule's
	## teleport-free version (it just stands), nothing else.
	_frozen = pd > FREEZE_R and mode != Mode.FLEE and not talk_open
	if _frozen:
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	if hit_flash > 0.0:
		hit_flash -= delta
		if body_mat:
			body_mat.albedo_color = Color(0.9, 0.6, 0.55) if hit_flash > 0.0 else base_body_color

	if flinch_timer > 0.0:
		flinch_timer -= delta
		velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
		_pre_loco()
		_update_locomotion(delta)
		_animate(delta)
		move_and_slide()
		return

	_sense(delta, pl, pd, to_p)
	_schedule_tick(delta)

	match mode:
		Mode.IDLE:
			_do_idle(delta)
		Mode.WANDER:
			_do_wander_npc(delta)
		Mode.GOTO:
			_do_goto(delta)
		Mode.WORK:
			_do_work(delta)
		Mode.SIT:
			_steer(Vector3.ZERO, delta, 12.0)
		Mode.SLEEP:
			_steer(Vector3.ZERO, delta, 12.0)
		Mode.ATTEND, Mode.TALK:
			_do_attend(delta, pl)
		Mode.FLEE:
			_do_flee(delta, pl, pd)
		Mode.COWER:
			_do_cower(delta, pl, pd)

	_pre_loco()
	_update_locomotion(delta)
	_animate(delta)
	move_and_slide()


func _tick_clocks_npc(delta: float) -> void:
	bark_t = maxf(0.0, bark_t - delta)
	_bark_cool = maxf(0.0, _bark_cool - delta)
	_wary_cool = maxf(0.0, _wary_cool - delta)
	_sneak_cool = maxf(0.0, _sneak_cool - delta)
	_greet_cool = maxf(0.0, _greet_cool - delta)
	_dodge_t = maxf(0.0, _dodge_t - delta)
	if _act != "":
		_act_t += delta
		if _act_t >= _act_len:
			_act = ""
	if mode == Mode.ATTEND or mode == Mode.TALK:
		_attend_t += delta
		if talk_open:
			_attend_t = 0.0
		elif _attend_t > ATTEND_HOLD:
			_release_attention()


func _pre_loco() -> void:
	## Match the player's cadence: Player._update_gait advances its phase at
	## 4.5 + speed*1.35 rad/s; Enemy's stride runs 2 + speed*2.4. gait_rate is
	## the ratio, so walk_t IS the player's phase clock.
	var h := Vector2(velocity.x, velocity.z).length()
	gait_rate = (4.5 + h * 1.35) / (2.0 + minf(h, 9.0) * 2.4)


## ------------------------------------------------------------- senses -----

func _sense(delta: float, pl: Node3D, pd: float, to_p: Vector3) -> void:
	if pl == null:
		look_at_pos = Vector3.INF
		return
	var fwd := -global_transform.basis.z
	var dir_to := to_p.normalized() if pd > 0.01 else fwd
	var in_front := fwd.dot(dir_to) > 0.15
	## The head: the player is worth looking at inside LOOK_R; behind us it is
	## a glance over the shoulder, the neck clamp does the rest.
	look_at_pos = pl.global_position + Vector3.UP * 1.5 if pd < LOOK_R and fwd.dot(dir_to) > -0.35 else Vector3.INF
	if mode == Mode.SLEEP or indoors:
		look_at_pos = Vector3.INF
		return
	if mode == Mode.FLEE or mode == Mode.COWER or talk_open:
		return

	## A drawn weapon, this close, pointed our way: wary. Too close: a threat.
	var weapon_out := _player_weapon_out(pl)
	var pointed := false
	if weapon_out and pd < WARY_R and in_front:
		var pf: Vector3 = -pl.global_transform.basis.z
		pointed = pf.dot(-dir_to) > 0.55
	if pointed:
		_wary_t += delta
		disposition = maxf(-100.0, disposition - 0.4 * delta)
		if _wary_cool <= 0.0:
			_wary_cool = 25.0
			bark(NPCDialogue.line(self, "weapon"))
		if pd < COWER_R and mode != Mode.HOSTILE:
			if courage < 0.6:
				_start_cower()
			elif _bark_cool <= 0.0:
				bark(NPCDialogue.line(self, "warn"))
	else:
		_wary_t = maxf(0.0, _wary_t - delta)

	## A crouching stranger behind us.
	if _sneak_cool <= 0.0 and pd < SNEAK_R and _player_flag(pl, "crouching") and fwd.dot(dir_to) < -0.3:
		_sneak_cool = 30.0
		bark(NPCDialogue.line(self, "sneak"))
		act("shake")

	## Keeping our distance from someone we have reason to.
	if avoid_day == day_now() and pd < AVOID_R and mode != Mode.FLEE and mode != Mode.GOTO:
		var away := global_position - dir_to * (AVOID_R + 3.0)
		_start_goto(away, Mode.IDLE, HURRY_SPEED)
		slot_key = ""   ## the schedule re-seats it once you have moved on
		return

	## Hello. Once a day, in passing, if they are looking our way and we have
	## no quarrel with them.
	if _greet_cool <= 0.0 and pd < GREET_R and in_front and disposition > -20.0 \
			and greeted_day != day_now() and not weapon_out and mode != Mode.SLEEP:
		var pf2: Vector3 = -pl.global_transform.basis.z
		if pf2.dot(-dir_to) > 0.4:
			greeted_day = day_now()
			_greet_cool = 40.0
			bark(NPCDialogue.line(self, "hello"))
			act("nod")


static func _player_weapon_out(pl: Node) -> bool:
	if pl == null:
		return false
	var st: float = float(pl.get("sheath_t")) if "sheath_t" in pl else 1.0
	var w: String = String(pl.get("current_weapon")) if "current_weapon" in pl else ""
	return st < 0.5 and w != ""


static func _player_flag(pl: Node, flag: String) -> bool:
	return pl != null and flag in pl and bool(pl.get(flag))


## ------------------------------------------------------------- schedule ---

func _schedule_tick(delta: float) -> void:
	_sched_t -= delta
	_sky_t -= delta
	if _sky_t <= 0.0:
		_sky_t = 5.0
		_sky_level = sky_level()
	if _sched_t > 0.0:
		return
	_sched_t = 1.0
	if mode in [Mode.ATTEND, Mode.TALK, Mode.FLEE, Mode.COWER, Mode.GOTO]:
		return
	var s := slot_for(sched(), hour_now())
	var r := resolve_slot(s)
	var what := String(r["do"])
	var where: Vector3 = r["at"]
	## Rain drives a household indoors — if it has a door to go through.
	var want_shelter := _sky_level >= 3 and home != Vector3.INF and home_kind == "door" and what != "sleep"
	if want_shelter:
		what = "sleep"
		where = home
	var key := what + "@" + str(where.round())
	if key == slot_key:
		return
	slot_key = key
	slot_at = where
	shelter = want_shelter
	if indoors:
		_come_outside()
	var then := mode_for(what)
	if global_position.distance_to(where) > ARRIVE_R * 1.5 and what != "wander":
		_start_goto(where, then, HURRY_SPEED if what == "sleep" else WALK_SPEED)
	else:
		_enter(then)


func _enter(m: int) -> void:
	if mode == Mode.SLEEP and m != Mode.SLEEP and indoors:
		_come_outside()
	mode = m
	mode_t = 0.0
	match m:
		Mode.SLEEP:
			if home != Vector3.INF and global_position.distance_to(home) < 2.5:
				if home_kind == "door":
					_go_inside()
				else:
					global_position = Vector3(home.x, global_position.y, home.z)
		Mode.SIT:
			if seat != Vector3.INF:
				global_position = Vector3(seat.x, global_position.y, seat.z)
		Mode.WORK:
			_work_break = randf_range(18.0, 40.0)
		Mode.IDLE:
			_idle_next = randf_range(4.0, 9.0)


func _go_inside() -> void:
	indoors = true
	visible = false
	for c in get_children():
		if c is CollisionShape3D:
			c.set_deferred("disabled", true)
	velocity = Vector3.ZERO


func _come_outside() -> void:
	indoors = false
	visible = true
	for c in get_children():
		if c is CollisionShape3D:
			c.set_deferred("disabled", false)
	if home != Vector3.INF:
		global_position = Vector3(home.x, global_position.y, home.z)


## ------------------------------------------------------------- modes ------

func _do_idle(delta: float) -> void:
	_steer(Vector3.ZERO, delta, 6.0)
	_idle_next -= delta
	if _idle_next <= 0.0:
		_idle_next = randf_range(5.0, 12.0)
		if randf() < 0.55:
			_pick_amble(slot_at if slot_at != Vector3.INF else anchor, 3.5)
		else:
			act("shrug" if randf() < 0.3 else "nod")


func _do_wander_npc(delta: float) -> void:
	if goto_target == Vector3.INF:
		_steer(Vector3.ZERO, delta, 6.0)
		_idle_next -= delta
		if _idle_next <= 0.0:
			_idle_next = randf_range(3.0, 8.0)
			_pick_amble(slot_at if slot_at != Vector3.INF else anchor, WANDER_R)
		return
	_walk_to(goto_target, WALK_SPEED, delta)
	if _arrived(goto_target):
		goto_target = Vector3.INF
		_idle_next = randf_range(3.0, 8.0)


func _pick_amble(around: Vector3, r: float) -> void:
	var a := randf() * TAU
	var d := randf_range(1.5, r)
	goto_target = Vector3(around.x + cos(a) * d, global_position.y, around.z + sin(a) * d)
	if mode == Mode.IDLE:
		mode = Mode.WANDER
		mode_t = 0.0


func _start_goto(where: Vector3, then: int, speed: float) -> void:
	goto_target = Vector3(where.x, global_position.y, where.z)
	goto_then = then
	goto_speed = speed
	mode = Mode.GOTO
	mode_t = 0.0
	_stuck_t = 0.0
	_give_up_t = 0.0
	_stuck_pos = global_position


func _do_goto(delta: float) -> void:
	if goto_target == Vector3.INF:
		_enter(goto_then)
		return
	_walk_to(goto_target, goto_speed, delta)
	_give_up_t += delta
	if _arrived(goto_target):
		var then := goto_then
		goto_target = Vector3.INF
		_enter(then)
	elif _give_up_t > GIVE_UP_T:
		## Somewhere it cannot reach. It does its thing here rather than
		## pressing its face into a tree until dusk.
		goto_target = Vector3.INF
		_enter(goto_then if goto_then != Mode.SLEEP else Mode.IDLE)


func _arrived(where: Vector3) -> bool:
	var d := where - global_position
	d.y = 0.0
	return d.length() < ARRIVE_R


func _walk_to(where: Vector3, speed: float, delta: float) -> void:
	var d := where - global_position
	d.y = 0.0
	if d.length() < 0.01:
		_steer(Vector3.ZERO, delta, 8.0)
		return
	var dir := d.normalized()
	## Whisker: something solid ahead at chest height -> slide round it.
	if _dodge_t <= 0.0 and _blocked_ahead(dir):
		_dodge_t = 0.8
		_dodge_dir = Vector3(-dir.z, 0.0, dir.x) * (1.0 if randf() < 0.5 else -1.0)
	if _dodge_t > 0.0:
		dir = (dir * 0.4 + _dodge_dir).normalized()
	## Stuck: no progress for a while -> a sidestep.
	_stuck_t += delta
	if _stuck_t > STUCK_T:
		_stuck_t = 0.0
		if global_position.distance_to(_stuck_pos) < 0.35:
			_dodge_t = 1.0
			_dodge_dir = Vector3(-dir.z, 0.0, dir.x) * (1.0 if randf() < 0.5 else -1.0)
		_stuck_pos = global_position
	var sp := speed if d.length() > 1.4 else maxf(speed * 0.5, 0.6)
	_steer(dir * sp, delta, 7.0)
	_face(dir, delta, 6.0)


func _blocked_ahead(dir: Vector3) -> bool:
	var w := get_world_3d()
	if w == null:
		return false
	var space := w.direct_space_state
	if space == null:
		return false
	var from := global_position + Vector3.UP * 0.9
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 1.3)
	q.exclude = [get_rid()]
	q.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return false
	## a slope is not a wall
	var n: Vector3 = hit.get("normal", Vector3.UP)
	return absf(n.y) < 0.6


func _do_work(delta: float) -> void:
	_steer(Vector3.ZERO, delta, 10.0)
	## turn to the work (over time — a snap after a talk reads as a glitch)
	if work_yaw != INF:
		_face(Vector3(-sin(work_yaw), 0.0, -cos(work_yaw)), delta, 4.0)
	elif work != Vector3.INF:
		var d := anchor - work
		d.y = 0.0
		if d.length() > 0.1:
			_face(d.normalized(), delta, 4.0)
	_work_t += delta
	_work_break -= delta
	if _work_break <= 0.0:
		## straighten up, look about, back to it
		_work_break = randf_range(18.0, 40.0)
		act("shrug")


func _do_attend(delta: float, pl: Node3D) -> void:
	_steer(Vector3.ZERO, delta, 12.0)
	if pl != null and mode != Mode.SIT:
		var d := pl.global_position - global_position
		d.y = 0.0
		if d.length() > 0.3:
			_face(d.normalized(), delta, 6.0)


func _start_flee(from: Vector3) -> void:
	_flee_from = from
	_flee_t = 0.0
	goto_target = Vector3.INF
	if talk_open:
		end_talk()
	mode = Mode.FLEE
	mode_t = 0.0
	act("")


func _do_flee(delta: float, pl: Node3D, pd: float) -> void:
	_flee_t += delta
	var from := _flee_from
	if pl != null:
		from = pl.global_position
	var away := global_position - from
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3(randf() - 0.5, 0.0, randf() - 0.5)
	away = away.normalized()
	if _dodge_t <= 0.0 and _blocked_ahead(away):
		_dodge_t = 0.7
		_dodge_dir = Vector3(-away.z, 0.0, away.x) * (1.0 if randf() < 0.5 else -1.0)
	if _dodge_t > 0.0:
		away = (away * 0.5 + _dodge_dir).normalized()
	_steer(away * RUN_SPEED, delta, 9.0)
	_face(away, delta, 8.0)
	if pd > FLEE_UNTIL or _flee_t > FLEE_MAX_T:
		avoid_day = day_now()
		_enter(Mode.IDLE)
		slot_key = ""   ## the schedule re-seats it from wherever it ended up


func _start_cower() -> void:
	if mode == Mode.COWER:
		_cower_t = 0.0
		return
	_resume_mode = mode if mode != Mode.ATTEND and mode != Mode.TALK else Mode.IDLE
	if talk_open:
		end_talk()
	_cower_t = 0.0
	mode = Mode.COWER
	mode_t = 0.0
	bark(NPCDialogue.line(self, "cower"))


func _do_cower(delta: float, pl: Node3D, pd: float) -> void:
	_cower_t += delta
	if pl != null:
		var d := pl.global_position - global_position
		d.y = 0.0
		if d.length() > 0.05:
			_face(d.normalized(), delta, 8.0)
			## back away, slowly, hands up
			_steer(-d.normalized() * 0.9, delta, 6.0)
	if _cower_t > COWER_T or pd > WARY_R + 1.0:
		if _player_weapon_out(pl) and pd < WARY_R:
			_start_flee(pl.global_position if pl != null else global_position)
		else:
			_enter(_resume_mode)


## ------------------------------------------------------------- hostile ----

func _hostile_check() -> void:
	## The Enemy loop fights; we only decide whether it should still be.
	if dying or knocked or routing or flinch_timer > 0.0 or retreat_timer > 0.0 \
			or state == State.AGITATED:
		return
	var pl := _get_player()
	var pd := 9999.0
	if pl != null:
		pd = global_position.distance_to(pl.global_position)
	if health <= max_health * nerve or pl == null or pd > REAGGRO_R:
		## broken, or it calmed on the leash: the grudge stays, the fight ends
		hostile = false
		_enter(Mode.IDLE)
		slot_key = ""
		avoid_day = day_now()
		return
	_set_agitated(true)


func _boot() -> void:
	## First physics tick: the spawner has placed us by now (add_child runs
	## _ready BEFORE global_position is set), so this is where "where we
	## belong" and the director's record can be settled.
	_booted = true
	if anchor == Vector3.ZERO:
		anchor = global_position
	_stuck_pos = global_position
	if record_id == "":
		var dir := get_tree().get_first_node_in_group("npc_director")
		if dir != null and dir.has_method("adopt"):
			dir.call("adopt", self)


func make_hostile() -> void:
	if dying:
		return
	hostile = true
	grudge = true
	disposition = -100.0
	indoors = false
	visible = true
	if talk_open:
		end_talk()
	goto_target = Vector3.INF
	mode = Mode.HOSTILE
	mode_t = 0.0
	act("")
	if "provoked" in self:
		set("provoked", true)
	_set_agitated(true)


## ------------------------------------------------------------- damage -----

func take_damage(amount: float, _from_pos = null, _strong = false, _throw = null, attacker: Node = null) -> void:
	if dying:
		return
	var by_player := attacker == null or (attacker != null and attacker.is_in_group("player"))
	var was_calm := not hostile
	_hit_by_player = by_player
	super(amount, _from_pos, _strong, _throw, attacker)
	if dying:
		return
	if by_player:
		_struck_by_player()
	elif attacker is Enemy and was_calm:
		## Another creature's swing found us. The brave square up (the base
		## already made it our foe); the rest run.
		if courage >= 0.6 or job == "guard":
			hostile = true
			mode = Mode.HOSTILE
		else:
			foe = null
			_set_agitated(false)
			_start_flee(attacker.global_position)


func _struck_by_player() -> void:
	grudge = true
	disposition = -100.0
	insults = 0
	if talk_open:
		end_talk()
	if courage >= 0.55 or job == "guard":
		make_hostile()
		bark(NPCDialogue.line(self, "fight"))
	else:
		hostile = false
		_set_agitated(false)
		avoid_day = day_now()
		bark(NPCDialogue.line(self, "hit"))
		var pl := _get_player()
		_start_flee(pl.global_position if pl != null else global_position)


func _die() -> void:
	## Same ragdoll death as every creature, but a person is not a bestiary
	## entry: no kill ledger. The neighbours notice.
	dying = true
	velocity = Vector3.ZERO
	hostile = false
	if talk_open:
		end_talk()
	name_label.visible = false
	for c in get_children():
		if c is CollisionShape3D:
			c.set_deferred("disabled", true)
	var dir := get_tree().get_first_node_in_group("npc_director")
	if dir != null and dir.has_method("on_npc_died"):
		dir.call("on_npc_died", self, _hit_by_player)
	if _hit_by_player:
		_witnesses_react()
	if RAGDOLL_DEATH and skin != null and skin.bone_count() > 1:
		knocked = false
		var fling := _last_hit_dir * 2.2 + Vector3.UP * 0.6
		if skin.ragdoll:
			skin.permanent = true
		else:
			skin.ragdoll_start(fling, 0.0, true)
		return
	var t := create_tween()
	t.tween_interval(1.2)
	t.tween_callback(queue_free)


func _witnesses_react() -> void:
	for n in get_tree().get_nodes_in_group("npcs"):
		var o := n as NPC
		if o == null or o == self or o.dying or o.indoors:
			continue
		if o.global_position.distance_to(global_position) > 25.0:
			continue
		o.grudge = true
		o.disposition = minf(o.disposition, -60.0)
		if o.courage >= 0.6 or o.job == "guard":
			o.make_hostile()
			o.bark(NPCDialogue.line(o, "fight"))
		else:
			o._start_flee(global_position)
			o.bark(NPCDialogue.line(o, "murder"))


## ------------------------------------------------------------- focus API --

func attend(by: Node3D) -> void:
	## Called every frame while the player focuses on us: stop, face them,
	## keep looking. Attention lapses ATTEND_HOLD after the last call.
	if dying or hostile or indoors:
		return
	focus_by = by
	_attend_t = 0.0
	if mode == Mode.ATTEND or mode == Mode.TALK:
		return
	if mode == Mode.FLEE or mode == Mode.COWER:
		return
	if mode != Mode.SIT:
		_resume_mode = Mode.IDLE if mode == Mode.GOTO or mode == Mode.WANDER else mode
		goto_target = Vector3.INF
		mode = Mode.ATTEND
		mode_t = 0.0
	else:
		_resume_mode = Mode.SIT


func _release_attention() -> void:
	focus_by = null
	if mode == Mode.TALK:
		return
	if mode == Mode.ATTEND:
		_enter(_resume_mode)
		slot_key = ""


func can_be_greeted() -> bool:
	return not dying and not hostile and not indoors and mode != Mode.FLEE and mode != Mode.COWER


func greet(by: Node3D) -> String:
	## The player says hello (E while focused). A wave back from a friend, a
	## nod from anyone else, a cold shoulder from someone with a grudge.
	if not can_be_greeted():
		return ""
	attend(by)
	var today := day_now()
	if disposition <= -40.0 or grudge:
		bark(NPCDialogue.line(self, "cold"))
		act("shake")
		return bark_text
	if greeted_day != today:
		greeted_day = today
		disposition = minf(100.0, disposition + 2.0)
	if disposition >= 20.0:
		act("wave")
	elif job == "priest":
		act("bow")
	else:
		act("nod")
	bark(NPCDialogue.line(self, "hello"))
	return bark_text


func antagonize(by: Node3D) -> String:
	## The player picks a fight with words (F while focused). Disposition
	## drops; past INSULT_SNAP the person reacts by their courage.
	if dying or hostile or indoors:
		return ""
	attend(by)
	insults += 1
	disposition = maxf(-100.0, disposition - 12.0)
	if talk_open:
		end_talk()
	if disposition < INSULT_SNAP or insults >= 3:
		if courage >= 0.6 or job == "guard":
			bark(NPCDialogue.line(self, "fight"))
			make_hostile()
		else:
			bark(NPCDialogue.line(self, "retreat"))
			avoid_day = day_now()
			_start_flee(by.global_position if by != null else global_position)
	else:
		bark(NPCDialogue.line(self, "retort"))
		act("shake" if randf() < 0.5 else "shrug")
	return bark_text


func begin_talk(by: Node3D) -> bool:
	if dying or hostile or indoors or mode == Mode.FLEE or mode == Mode.COWER:
		return false
	attend(by)
	talk_open = true
	met_day = day_now()
	if mode != Mode.SIT:
		mode = Mode.TALK
		mode_t = 0.0
	_talk_t = 0.0
	return true


func end_talk() -> void:
	talk_open = false
	if mode == Mode.TALK:
		mode = Mode.ATTEND
		_attend_t = ATTEND_HOLD   ## lapses next tick unless the focus is still held
	focus_by = null


func on_line_spoken() -> void:
	## A new line in the dialogue box: a beat of the head.
	if _act == "":
		act("nod")


## ------------------------------------------------------------- talk -------

func bark(text: String) -> void:
	## One line, said out loud: onto the name tag over the head, and into the
	## player's log if they are near enough to hear it.
	if text == "":
		return
	bark_text = text
	bark_t = maxf(3.0, 1.6 + text.length() * 0.06)
	_bark_cool = 1.5
	var pl := _get_player()
	if pl != null and pl.has_method("_add_log_msg") and pl.global_position.distance_to(global_position) < 12.0:
		pl.call("_add_log_msg", "%s: \"%s\"" % [npc_name if npc_name != "" else display_name, text], Color(0.86, 0.82, 0.70))


func act(kind: String) -> void:
	_act = kind
	_act_t = 0.0
	_act_len = float(ACT_LEN.get(kind, 1.0))


func mode_name() -> String:
	return MODE_NAMES[mode] if mode >= 0 and mode < MODE_NAMES.size() else "?"


## ============================================================ animation ===

func _animate(delta: float) -> void:
	if rig == null or spine == null:
		return
	var k := clampf(delta * 12.0, 0.0, 1.0)
	var hspeed := Vector2(velocity.x, velocity.z).length()
	_gait_k = lerpf(_gait_k, clampf(hspeed / 0.9, 0.0, 1.0) if is_on_floor() else 0.0, clampf(delta * 8.0, 0.0, 1.0))
	## The player's stride: legs ±0.5 rad, arms ±0.6, counter-phase, scaled by
	## how fast we are actually going (a walk is a smaller stride than a run).
	var amp := 0.5 * clampf(0.55 + 0.45 * hspeed / RUN_SPEED, 0.0, 1.0) * _gait_k
	var sl := sin(walk_t)          ## left leg (player: leg 0 carries phase PI —
	var sr := sin(walk_t + PI)     ## which leg leads is a convention, not a look)
	var lsh := Vector3(sr * 1.2 * amp, 0.0, 0.0)   ## left arm swings with the right leg
	var rsh := Vector3(sl * 1.2 * amp, 0.0, 0.0)
	var lel := Vector3(0.22 + 0.18 * maxf(0.0, sr) * _gait_k, 0.0, 0.0)
	var rel := Vector3(0.22 + 0.18 * maxf(0.0, sl) * _gait_k, 0.0, 0.0)
	var hl := Vector3(sl * amp, 0.0, 0.0)
	var hr := Vector3(sr * amp, 0.0, 0.0)
	var kl := Vector3(-0.6 * clampf(sin(walk_t + 1.1), 0.0, 1.0) * _gait_k, 0.0, 0.0)
	var kr := Vector3(-0.6 * clampf(sin(walk_t + PI + 1.1), 0.0, 1.0) * _gait_k, 0.0, 0.0)
	var sp := Vector3(-0.04 * _gait_k, 0.0, 0.0)   ## a little forward into the walk
	var rig_y := 0.0
	var rig_rx := 0.0
	var show_axe := false
	var show_broom := false
	var show_rod := false
	var snap := false   ## absolute pose (no lerp) — swings must land on time

	if hostile:
		## Fists up. The swing is the player's own cut curve.
		lsh = Vector3(0.75, 0.0, -0.25)
		lel = Vector3(1.55, 0.0, 0.0)
		rsh = Vector3(0.85, 0.0, 0.20)
		rel = Vector3(1.50, 0.0, 0.0)
		sp = Vector3(-0.10, 0.0, 0.0)
		if melee_anim > 0.0:
			var p := 1.0 - melee_anim / MELEE_ANIM_TIME
			rsh = Vector3(Enemy._cut_arc(p, 0.85, -0.55, 1.75), 0.0, Enemy._cut_arc(p, 0.20, 0.55, -0.35))
			rel = Vector3(Enemy._cut_arc(p, 1.50, 1.85, 0.15), 0.0, 0.0)
			sp = Vector3(-0.10 + Enemy._cut_arc(p, 0.0, 0.10, -0.22), Enemy._cut_arc(p, 0.0, 0.35, -0.40), 0.0)
			snap = true
	else:
		match mode:
			Mode.SIT:
				rig_y = -(0.74 - seat_h)
				hl = Vector3(1.5, 0.0, 0.05)
				hr = Vector3(1.5, 0.0, -0.05)
				kl = Vector3(-1.5, 0.0, 0.0)
				kr = Vector3(-1.5, 0.0, 0.0)
				sp = Vector3(-0.14, 0.0, 0.0)
				lsh = Vector3(0.55, 0.0, -0.08)
				rsh = Vector3(0.55, 0.0, 0.08)
				lel = Vector3(0.95, 0.0, 0.0)
				rel = Vector3(0.95, 0.0, 0.0)
			Mode.SLEEP:
				## flat on the back, head toward +z, arms along the body
				rig_rx = PI * 0.5
				rig_y = 0.16
				hl = Vector3(0.10, 0.0, 0.05)
				hr = Vector3(0.10, 0.0, -0.05)
				kl = Vector3(-0.15, 0.0, 0.0)
				kr = Vector3(-0.15, 0.0, 0.0)
				lsh = Vector3(0.0, 0.0, -0.12)
				rsh = Vector3(0.0, 0.0, 0.12)
				lel = Vector3(0.0, 0.0, 0.0)
				rel = Vector3(0.0, 0.0, 0.0)
				sp = Vector3(0.06, 0.0, 0.0)
			Mode.WORK:
				var wp := _work_pose()
				lsh = wp[0]
				lel = wp[1]
				rsh = wp[2]
				rel = wp[3]
				sp = wp[4]
				show_axe = job == "woodcutter"
				show_broom = job == "villager" or job == "merchant"
				show_rod = job == "fisher"
				snap = job == "woodcutter" or job == "crofter"
			Mode.COWER:
				## hands up, knees soft, leaning away
				lsh = Vector3(2.6, 0.0, -0.35)
				rsh = Vector3(2.6, 0.0, 0.35)
				lel = Vector3(0.35, 0.0, 0.0)
				rel = Vector3(0.35, 0.0, 0.0)
				hl = Vector3(0.45, 0.0, 0.0)
				hr = Vector3(0.45, 0.0, 0.0)
				kl = Vector3(-0.85, 0.0, 0.0)
				kr = Vector3(-0.85, 0.0, 0.0)
				rig_y = -0.14
				sp = Vector3(0.18, 0.0, 0.0)
			Mode.TALK, Mode.ATTEND:
				if talk_open:
					_talk_t += delta
					## talking with the hands, the way people do
					rsh = Vector3(0.35 + 0.15 * sin(_talk_t * 1.7), 0.0, 0.10)
					rel = Vector3(0.95 + 0.35 * sin(_talk_t * 2.3 + 1.0), 0.0, 0.0)
					lsh = Vector3(0.18 + 0.08 * sin(_talk_t * 1.1 + 2.0), 0.0, -0.06)
					lel = Vector3(0.55 + 0.20 * sin(_talk_t * 1.3), 0.0, 0.0)
					sp = Vector3(-0.05, 0.0, 0.0)
				else:
					sp = Vector3(-0.03, 0.0, 0.0)
			Mode.FLEE:
				## arms pump higher, body pitches into the run
				lsh.x *= 1.35
				rsh.x *= 1.35
				lel = Vector3(1.1, 0.0, 0.0)
				rel = Vector3(1.1, 0.0, 0.0)
				sp = Vector3(-0.16, 0.0, 0.0)
			_:
				if _gait_k < 0.1:
					var ip := _idle_pose()
					lsh = ip[0]
					lel = ip[1]
					rsh = ip[2]
					rel = ip[3]

	## One-shot gestures ride over everything but a swing.
	if _act != "" and not hostile:
		var t := clampf(_act_t / maxf(_act_len, 0.01), 0.0, 1.0)
		var env := sin(t * PI)
		match _act:
			"wave":
				rsh = Vector3(0.35, 0.0, 2.35 * Enemy._ease_hold(t))
				rel = Vector3(0.25, 0.0, 0.45 * sin(_act_t * 11.0) * Enemy._ease_hold(t))
				snap = false
			"nod":
				sp.x -= 0.05 * env
			"shrug":
				lsh = Vector3(0.25, 0.0, -0.45 * env)
				rsh = Vector3(0.25, 0.0, 0.45 * env)
				lel = Vector3(1.6 * env, 0.0, 0.0)
				rel = Vector3(1.6 * env, 0.0, 0.0)
			"point":
				rsh = Vector3(1.45 * Enemy._ease_hold(t), 0.0, 0.15)
				rel = Vector3(0.05, 0.0, 0.0)
			"bow":
				sp.x -= 0.55 * env
				lsh = Vector3(0.30 * env, 0.0, 0.0)
				rsh = Vector3(0.30 * env, 0.0, 0.0)
				lel = Vector3(1.2 * env, 0.0, 0.0)
				rel = Vector3(1.2 * env, 0.0, 0.0)
			"shake":
				sp.y += 0.20 * sin(_act_t * 14.0) * env

	## Apply. The pose is eased in OUR OWN state and written absolutely:
	## Enemy._update_locomotion writes the hip and shoulder pivots every frame
	## before us (its own stride), so a lerp read off the node would restart
	## from zero each frame and never arrive.
	var kk := 1.0 if snap else k
	_p_lsh = _p_lsh.lerp(lsh, kk)
	_p_rsh = _p_rsh.lerp(rsh, kk)
	_p_lel = _p_lel.lerp(lel, kk)
	_p_rel = _p_rel.lerp(rel, kk)
	_p_hl = _p_hl.lerp(hl, k)
	_p_hr = _p_hr.lerp(hr, k)
	_p_kl = _p_kl.lerp(kl, k)
	_p_kr = _p_kr.lerp(kr, k)
	_p_sp = _p_sp.lerp(sp, kk)
	shoulder_l.rotation = _p_lsh
	shoulder_r.rotation = _p_rsh
	elbow_l.rotation = _p_lel
	elbow_r.rotation = _p_rel
	hip_l.rotation = _p_hl
	hip_r.rotation = _p_hr
	knee_l.rotation = _p_kl
	knee_r.rotation = _p_kr
	spine.rotation = _p_sp
	rig.rotation.x = lerpf(rig.rotation.x, rig_rx, clampf(delta * 6.0, 0.0, 1.0))
	## loco_root's y is the footfall bob (Enemy writes it every frame); the
	## pose's own height (a seat, a crouch) is kept apart and added under it.
	_pose_y = lerpf(_pose_y, rig_y, clampf(delta * 6.0, 0.0, 1.0))
	rig.position.y = loco_bob_y + _pose_y
	tool_axe.visible = show_axe
	tool_broom.visible = show_broom
	tool_rod.visible = show_rod
	_animate_head(delta)


func _idle_pose() -> Array:
	## Standing about, by temperament: arms crossed, hands clasped, or hanging.
	match job:
		"merchant":
			return [Vector3(0.45, 0.0, -0.35), Vector3(1.9, 0.0, 0.0), Vector3(0.45, 0.0, 0.35), Vector3(1.9, 0.0, 0.0)]
		"priest":
			return [Vector3(0.40, 0.0, -0.20), Vector3(1.5, 0.0, 0.0), Vector3(0.40, 0.0, 0.20), Vector3(1.5, 0.0, 0.0)]
		"guard":
			return [Vector3(-0.30, 0.0, -0.15), Vector3(-0.6, 0.0, 0.0), Vector3(-0.30, 0.0, 0.15), Vector3(-0.6, 0.0, 0.0)]
		_:
			if personality == "gruff" or personality == "dour":
				return [Vector3(0.45, 0.0, -0.35), Vector3(1.9, 0.0, 0.0), Vector3(0.45, 0.0, 0.35), Vector3(1.9, 0.0, 0.0)]
			return [Vector3(0.05, 0.0, -0.06), Vector3(0.22, 0.0, 0.0), Vector3(0.05, 0.0, 0.06), Vector3(0.22, 0.0, 0.0)]


func _work_pose() -> Array:
	## [lsh, lel, rsh, rel, spine] for the job's work loop.
	match job:
		"woodcutter":
			## two-handed chop on a 1.6 s cycle, the player's cut curve
			var p := fmod(_work_t / 1.6, 1.0)
			var x := Enemy._cut_arc(p, -0.20, -1.55, 0.55)
			var z := Enemy._cut_arc(p, 0.0, 0.85, -0.55)
			return [Vector3(x, 0.0, -z * 0.6), Vector3(0.35, 0.0, 0.0), Vector3(x, 0.0, z), Vector3(0.30, 0.0, 0.0),
				Vector3(-0.28 * clampf(x + 0.2, 0.0, 1.0) - 0.05, 0.0, 0.0)]
		"crofter":
			## hoeing: a slower, lower stroke
			var p := fmod(_work_t / 2.2, 1.0)
			var x := Enemy._cut_arc(p, 0.30, -0.35, 0.95)
			return [Vector3(x * 0.8, 0.0, -0.15), Vector3(0.45, 0.0, 0.0), Vector3(x, 0.0, 0.15), Vector3(0.40, 0.0, 0.0),
				Vector3(-0.30 - 0.12 * x, 0.0, 0.0)]
		"fisher":
			var bob := sin(_work_t * 0.9) * 0.05
			return [Vector3(0.75, 0.0, -0.10), Vector3(0.30, 0.0, 0.0), Vector3(0.95 + bob, 0.0, 0.10), Vector3(0.25, 0.0, 0.0),
				Vector3(-0.04, 0.0, 0.0)]
		"guard":
			## at ease: hands behind the back, weight square
			return [Vector3(-0.30, 0.0, -0.15), Vector3(-0.65, 0.0, 0.0), Vector3(-0.30, 0.0, 0.15), Vector3(-0.65, 0.0, 0.0),
				Vector3(0.02, 0.0, 0.0)]
		"priest":
			## hands clasped, a slow sway of the whole body
			return [Vector3(0.45, 0.0, -0.22), Vector3(1.55, 0.0, 0.0), Vector3(0.45, 0.0, 0.22), Vector3(1.55, 0.0, 0.0),
				Vector3(-0.08, 0.06 * sin(_work_t * 0.6), 0.0)]
		_:
			## sweeping: broom low, the body turning side to side
			var sw := sin(_work_t * 2.6)
			return [Vector3(0.55, 0.0, -0.20), Vector3(0.75, 0.0, 0.0), Vector3(0.60, 0.0, 0.15), Vector3(0.70, 0.0, 0.0),
				Vector3(-0.22, 0.32 * sw, 0.0)]


func _animate_head(delta: float) -> void:
	## The head follows look_at_pos inside a neck's reach; otherwise it drifts
	## back to straight ahead. Pitch positive = face tilts UP; yaw positive =
	## face turns to the body's LEFT (-x).
	var target := Vector2.ZERO
	if look_at_pos != Vector3.INF and mode != Mode.SLEEP:
		var local: Vector3 = spine.global_transform.affine_inverse() * look_at_pos
		local -= head_pivot.position + Vector3(0, 0.14, 0)
		var hd := Vector2(local.x, local.z).length()
		var yaw := atan2(-local.x, -local.z)
		if absf(yaw) <= LOOK_YAW_MAX + 0.15:
			target = Vector2(clampf(atan2(local.y, maxf(hd, 0.05)), -LOOK_PITCH_MAX, LOOK_PITCH_MAX),
				clampf(yaw, -LOOK_YAW_MAX, LOOK_YAW_MAX))
	if _act == "nod":
		var t := clampf(_act_t / maxf(_act_len, 0.01), 0.0, 1.0)
		target.x -= 0.28 * sin(t * PI * 2.0) * sin(t * PI)
	if talk_open:
		target.x += 0.04 * sin(_talk_t * 3.1)
	_head_rot = _head_rot.lerp(target, clampf(delta * 6.0, 0.0, 1.0))
	head_pivot.rotation = Vector3(_head_rot.x, _head_rot.y, 0.0)


## ============================================================ save ========

static func _v3_out(v: Vector3) -> Variant:
	if v == Vector3.INF:
		return "none"
	return [v.x, v.y, v.z]


static func _v3_in(x: Variant, fallback := Vector3.INF) -> Vector3:
	if x is Array and (x as Array).size() == 3:
		return Vector3(float(x[0]), float(x[1]), float(x[2]))
	if x is Vector3:
		return x
	return fallback


func to_dict() -> Dictionary:
	return {
		"id": record_id, "name": npc_name, "sex": sex, "personality": personality, "job": job,
		"courage": courage, "disposition": disposition, "flags": flags.duplicate(true),
		"met_day": met_day, "greeted_day": greeted_day, "grudge": grudge, "avoid_day": avoid_day,
		"pos": _v3_out(global_position if is_inside_tree() else position), "anchor": _v3_out(anchor), "home": _v3_out(home),
		"work": _v3_out(work), "seat": _v3_out(seat), "seat_h": seat_h, "work_yaw": work_yaw,
		"home_kind": home_kind, "schedule": schedule.duplicate(true), "health": health, "dead": dying,
		"look": look_to_json(look),
	}


func apply_dict(d: Dictionary) -> void:
	record_id = String(d.get("id", record_id))
	npc_name = String(d.get("name", npc_name))
	sex = String(d.get("sex", sex))
	personality = String(d.get("personality", personality))
	job = String(d.get("job", job))
	courage = float(d.get("courage", courage))
	disposition = float(d.get("disposition", disposition))
	var fl = d.get("flags", flags)
	flags = (fl as Dictionary).duplicate(true) if fl is Dictionary else {}
	met_day = int(d.get("met_day", met_day))
	greeted_day = int(d.get("greeted_day", greeted_day))
	grudge = bool(d.get("grudge", grudge))
	avoid_day = int(d.get("avoid_day", avoid_day))
	anchor = _v3_in(d.get("anchor"), anchor)
	home = _v3_in(d.get("home"), home)
	work = _v3_in(d.get("work"), work)
	seat = _v3_in(d.get("seat"), seat)
	seat_h = float(d.get("seat_h", seat_h))
	work_yaw = float(d.get("work_yaw", work_yaw))
	home_kind = String(d.get("home_kind", home_kind))
	var sc = d.get("schedule", schedule)
	if sc is Array and not (sc as Array).is_empty():
		schedule = (sc as Array).duplicate(true)
	var lk = d.get("look", null)
	if lk is Dictionary and not (lk as Dictionary).is_empty():
		look = look_from_json(lk)
	if d.has("health"):
		health = clampf(float(d["health"]), 1.0, max_health)
