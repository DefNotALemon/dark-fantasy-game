extends CharacterBody3D
class_name Player
## First-person player controller for the vertical slice.
## Built entirely in code (collision, body, viewmodel, camera, HUD) so it can be
## spawned with Player.new() and needs no scene wiring.
##
## Controls:
##   WASD ........ move          Mouse ....... look
##   Shift ....... sprint        Space ....... jump
##   Left click .. attack (sword: flowing 1-2-3 combo / bow: hold to draw, release
##                 to loose / pickaxe: chop — bites ore veins + digs cave rock /
##                 war axe: alternating overhead chop + horizontal cleave)
##   Right click . block (sword) / ease the string down (bow)
##   1 / 2 / 3 / 4 weapon: sword / bow / pickaxe / war axe (while no menu is open)
##   Ctrl ........ dash
##   Space ....... jump — or MANTLE: a grabbable ledge ahead (≤ ~2.6 m) gets
##                 climbed instead, hands planting, camera dipping into the
##                 pull; works mid-air too (grab as you fall), costs stamina
##   F ........... mount / dismount a saddled horse (WASD ride, Shift gallop,
##                 Space jump; LMB sweeps the sword saddle-side — look left or
##                 right to pick the side, straight ahead to alternate)
##   Alt/Option .. sheathe / unsheathe sword (the shield stows/draws with it;
##                 THE HUNCH — settings toggle — auto-draws the moment anything
##                 turns hostile and auto-sheathes after 6.7 quiet seconds)
##   M ........... mob spawn menu
##   Tab ......... menu (1 Inventory / 2 Stats / 3 Progression / 4 Bestiary)
##   I ........... straight to the Inventory page — its Armory column (dev)
##                 adds any material sword; click a sword in the list to wield it
##   Q ........... cycle offhand (shield / torch / shield+torch / empty — owned
##                 items only; the shield straps on so the torch shares the arm)
##   Esc ......... settings menu (ray-traced lighting, shadows, display, input,
##                 the hunch) — or closes whichever menu is open

const SPEED := 5.0
const SPRINT_SPEED := 8.0
const BLOCK_SPEED := 2.5
const ACCEL := 45.0          ## how fast we reach target speed
const DECEL := 24.0          ## lower than ACCEL -> "step into a stop" glide
const AIR_ACCEL := 12.0
const DASH_SPEED := 16.0
const DASH_TIME := 0.18
const JUMP_VELOCITY := 4.5
const STEP_HEIGHT := 0.45   ## auto-climb steps up to ~1/4 the player's height
const MOUSE_SENS := 0.0025

const SWING_TIME := 0.42
const HIT_AT := 0.22         ## damage lands AT the visual impact of the cut (p=0.52)
const ATTACK_STAMINA := 12.0
const DASH_STAMINA := 20.0
const COMBO_RESET := 0.75    ## idle this long and the combo restarts at hit 1
const SHEATH_TIME := 0.40

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

var head: Node3D
var camera: Camera3D
var body_rig: Node3D
var leg_pivots: Array[Node3D] = []   ## visible legs — they stride with the gait
var viewmodel: Node3D
var sword_vm: Node3D    ## the held blade — rebuilt when a different sword is equipped
var hip_sword: Node3D
var back_shield: Node3D ## stowed shield across the back — the offhand's scabbard
var left_arm: Node3D
var right_arm: Node3D
var pitch := 0.0

var xp := 0
var gold := 0

## Resting pose of the held sword viewmodel (relative to the camera): carried
## point-UP like a ready guard. Swings blend onto the flat combat base below
## so the attack arcs still read the way they were authored.
var vm_ready_pos := Vector3(0.30, -0.32, -0.50)
var vm_ready_rot := Vector3(84.0, -8.0, 4.0)
var vm_combat_pos := Vector3(0.30, -0.30, -0.55)
var vm_combat_rot := Vector3(-6.0, -10.0, 4.0)
var _attack_start_rot := Vector3.ZERO   ## pose captured when a swing begins
var _attack_start_pos := Vector3.ZERO

## Character sheet (five stats, banked points, XP curve, progression trees) —
## see Stats.gd. The deriveds below are pulled from it by _refresh_derived()
## whenever a point is spent or a tree tier pays out.
var stats := PlayerStats.new()
var max_health := 100.0
var health := 100.0
var max_stamina := 100.0
var stamina := 100.0
var stamina_regen := 20.0
var sprinting := false
var stamina_delay := 0.0     ## short pause after spending stamina before regen kicks in
const STAMINA_DELAY := 0.8
const SPRINT_DRAIN := 12.0

var attack_range := 2.6
var base_damage := 22.0
var attacking := false
var swing_t := 0.0
var has_hit := false
var combo_index := 0
var since_last_attack := 999.0

var sheathed := false
var sheath_t := 0.0          ## 0 = drawn, 1 = fully sheathed
var draw_attack := false     ## true while performing a draw-from-sheath slash

## --- The Hunch: steel answers intent (settings toggle). The moment a hostile
## creature turns AGITATED at you the blade+shield clear the scabbard on their
## own; after HUNCH_SHEATHE_AFTER quiet seconds they ride home again. ---
const HUNCH_SHEATHE_AFTER := 6.7
var hunch_calm_t := 0.0
var hunch_aggro_prev := false    ## edge trigger — Alt can still defy it mid-fight

## --- Climbing (Space): if a grabbable ledge is ahead, Space MANTLES it
## instead of jumping — hands plant, camera dips into the pull, you rise then
## haul over the lip. Works on cave walls, dig-steps, pit lips; costs stamina,
## so scaling a rock face is a real climb, not an elevator. ---
const CLIMB_TIME := 0.55         ## base mantle duration (taller = a beat longer)
const CLIMB_STAMINA := 8.0
const CLIMB_MAX_H := 2.65        ## highest ledge you can grab above your feet
const CLIMB_MIN_H := 0.55        ## lower lips are just walked/stepped up
var climbing := false
var climb_t := 0.0
var climb_from := Vector3.ZERO
var climb_to := Vector3.ZERO
var climb_dur := CLIMB_TIME
var jump_queued := false         ## Space pressed — resolved next physics tick

var blocking := false
var dash_timer := 0.0
var invuln_timer := 0.0
var hitstun_timer := 0.0     ## thrown out of your action when hit (unblocked)
var block_impact := 0.0      ## brief recoil when a block absorbs a hit
var _step_smooth := 0.0      ## camera offset that eases out after an auto-step (smooth stairs)
var _eye_smooth := 0.0       ## signed bump absorber: small body hops (jittery
							 ## voxel floors) reach the EYE as an eased glide
var _prev_body_y := 0.0
var move_input := Vector3.ZERO
var bob_t := 0.0             ## slow "breathing" sway of held items when standing still

## --- Gait: ONE shared stride drives the arms, sword, offhand, and head bob,
## and its amplitude eases in/out with real speed — so starting, stopping, and
## strafing melt between animation states instead of snapping. ---
var gait_phase := 0.0        ## radians through the walk cycle
var gait_amount := 0.0       ## eased 0..1 — how deep into the walk we are
var head_bob := Vector2.ZERO ## smoothed camera offset (x sway, y footfall dip)
var land_dip := 0.0          ## soft knee-bend of the view after landing
var _was_on_floor := true
var _fall_speed := 0.0       ## how hard we were falling just before touchdown

## --- Fall damage: gravity keeps its receipts. Safe to ~6 m; past that the
## landing takes flesh, and a truly hard one folds your legs (knockdown). ---
const FALL_SAFE_SPEED := 11.0    ## m/s at touchdown — under this is free
const FALL_DMG_PER_MS := 6.5     ## damage per m/s beyond safe
const FALL_KD_SPEED := 17.5      ## land this hard and you eat the floor

const BAR_W := 340.0
## Out-of-combat HP regen now lives on the sheet — stats.heal_rate() (CON raises it).
const COMBAT_HEAL_DELAY := 3.0

var hud_layer: CanvasLayer
var health_bar: Control
var health_fill: ColorRect
var stamina_bar: Control
var stamina_fill: ColorRect
var level_bar: Control
var level_fill: ColorRect

var _last_health := 100.0
var _last_stamina := 100.0
var _last_xp := 0
var _last_level := 1
var health_show := 0.0
var stam_show := 0.0
var xp_show := 0.0
var combat_timer := 99.0      ## time since last combat action
var level := 1

## One row per gain-log entry: {label, kind, amount, life}. A single array —
## the old four parallel arrays could drift apart and crash on an index the
## moment anything interrupted an append quartet mid-frame.
var log_rows: Array[Dictionary] = []

## --- Menus (M = mob spawner; Tab = Inventory | Stats | Progression) ---
const TAB_PANEL_SIZE := Vector2(840, 540)  ## every page shares this one size
var menu_open := ""              ## "", "spawn", "tab"
var spawn_panel: PanelContainer
var tab_panel: PanelContainer
var tab_page := "inventory"      ## which page the Tab menu is showing
var tab_buttons := {}            ## page id -> header Button
var tab_pages := {}              ## page id -> page root Control
var points_badge: Label
var inv_items_box: VBoxContainer
var inv_weight_label: Label
var inv_slot_labels := {}        ## slot id -> Label

## --- Stats page (hover an attribute to see exactly what it changes) ---
var stat_rows := {}              ## stat id -> {"value": Label, "minus": Button, "plus": Button}
var stat_avail_label: Label
var stat_confirm: Button
var stat_reset: Button
var detail_title: Label
var detail_flavor: Label
var detail_box: VBoxContainer
var pending := {}                ## stat id -> points queued before Confirm
var hovered_stat := "con"

## --- Progression page ---
var prog_box: VBoxContainer

## --- Progression tracking (feeds the trees in Stats.gd) ---
const PARRY_WINDOW := 0.18       ## block raised this close to impact = parry
var block_held_time := 999.0     ## how long the current block has been up
var near_death_active := false   ## dropped to the brink; recover to score it
var near_death_cd := 0.0         ## anti-farm: breather between brink recoveries
var dodge_cd := 0.0              ## don't double-count one dash through a flurry
var dist_accum := 0.0            ## sub-meter remainder for Marathoner

## --- Inventory ---
## Carry limit lives on the sheet now — stats.carry_limit() (STR raises it).
## "offhand2" is the companion slot: a torch can share the shield arm (shield
## straps to the forearm, torch rides the same fist).
const SLOT_ORDER: Array[String] = ["sword", "helmet", "chest", "arms", "pants", "shoes", "offhand", "offhand2"]
const SLOT_NAMES := {
	"sword": "Main Hand", "helmet": "Helmet", "chest": "Chest", "arms": "Arms",
	"pants": "Pants", "shoes": "Shoes", "offhand": "Offhand", "offhand2": "Offhand 2",
}
var inventory: Array[Dictionary] = []   ## {name, weight, count, slot [, material]}
var equipment := {}                     ## slot id -> inventory index (-1 = empty)
var hovered_item_idx := -1              ## inventory row under the mouse (Q drops it)

## --- Dropped items (Q to toss from the inventory; look + E to reclaim) ---
var pickup_prompt: Label                ## "[E] Pick up ..." hint, bottom-center
var _drop_target: DroppedItem = null    ## the dropped item currently looked at

## --- Worn armor visuals: the visible body tints to the equipped material ---
const BODY_ARMOR_COL := Color(0.20, 0.22, 0.28)     ## default padded slate
const BODY_LEATHER_COL := Color(0.26, 0.18, 0.12)   ## default leg leather
const BODY_FOOT_COL := Color(0.10, 0.09, 0.08)      ## default worn boots
var torso_mesh: MeshInstance3D
var pelvis_mesh: MeshInstance3D
var leg_meshes: Array[MeshInstance3D] = []
var foot_meshes: Array[MeshInstance3D] = []
var arm_meshes: Array[MeshInstance3D] = []          ## upper-arm plates, L/R
var forearm_mesh: MeshInstance3D                    ## viewmodel forearm (right)

## --- Guard break ---
var block_broken_timer := 0.0    ## a strong attack broke your guard: no blocking
var cam_shake := 0.0

## --- Riding (E near a saddled horse). While mounted the horse's body does the
## moving; the player just rides the saddle point and swings from it. ---
var mount: Horse = null
var mounted_swing := false       ## the current swing is a saddle sweep
var mounted_side := 0            ## 0 = left sweep, 1 = right (alternates)
var body_col: CollisionShape3D   ## disabled while in the saddle

## --- Knockdown (a horse's kick / being bucked off): you go DOWN — fall flat,
## then pick yourself up, and you are fully vulnerable the whole way through.
## No i-frames, no blocking, no attacking; enemies keep swinging. ---
const KD_FALL := 0.42            ## eating the dirt
const KD_DOWN := 0.75            ## flat on the ground
const KD_RISE := 1.05            ## staggering back upright
var kd_phase := ""               ## "" | "fall" | "down" | "rise"
var kd_t := 0.0

## --- Settings (Esc) — applied live, saved to user://settings.cfg ---
const SETTINGS_PATH := "user://settings.cfg"
var settings_panel: PanelContainer
var set_rt := false              ## "ray-traced" lighting preset (SDFGI et al.)
var set_shadows := 1             ## 0 low / 1 medium / 2 high
var set_fullscreen := false
var set_vsync := true
var set_sens := 1.0              ## multiplier on MOUSE_SENS
var set_fov := 75.0
var set_hunch := true            ## the hunch: auto draw on aggro / auto sheathe when calm
var _settings_widgets := {}      ## id -> {btns: [[value, Button]...]} or {label: Label}
const MENU_SCALE := 1.67         ## all menus render 67% larger (clamped to the screen)

## --- Offhand (left hand: shield / torch, cycled with Q) ---
const OH_REST_POS := Vector3(-0.30, -0.30, -0.52)
const OH_REST_ROT := Vector3(-4.0, 16.0, -8.0)
const OH_RAISE_TIME := 0.35      ## equip animation: lift up into view
var offhand_node: Node3D
var offhand_light: OmniLight3D   ## the torch flame's actual light
var offhand_shown := -1          ## inventory index currently displayed (-1 none)
var offhand_shown2 := -1         ## companion item displayed alongside (torch w/ shield)
var offhand_raise := 0.0         ## 0 = lowered off-screen, 1 = fully up
var oh_bob_t := 0.0

## --- Weapons (1 = sword, 2 = bow, 3 = pickaxe, while no menu is open) ---
const BOW_DRAW_TIME := 0.85      ## seconds to a full draw (DEX shortens it)
const BOW_STAMINA := 14.0        ## cost to start a draw (DEX discounts it)
var current_weapon := "sword"
var bow_vm: Node3D               ## bow viewmodel (left fist, limbs, string)
var bow_string: MeshInstance3D
var bow_arrow_vm: Node3D         ## the nocked arrow, slides back with the draw
var bow_hand_vm: Node3D          ## right hand pinching the string
var drawing := false
var bow_draw := 0.0              ## 0..1 — how far the string is pulled
var bow_release := 0.0           ## brief string-snap kick after loosing

## --- Pickaxe (weapon 3): the mining tool. Bites ore veins in 4 chops; barely
## a weapon (slow, weak, teaches the bestiary nothing) — bring a sword too. ---
const PICK_TIME := 0.62          ## one full chop
const PICK_WINDUP := 0.34        ## fraction spent hoisting it up
const PICK_HIT_AT := 0.52        ## fraction where the spike visually lands — the bite
const PICK_STAMINA := 10.0
const PICK_RANGE := 2.9
const PICK_REST_POS := Vector3(0.32, -0.34, -0.52)
const PICK_REST_ROT := Vector3(18.0, -14.0, 6.0)
var pick_vm: Node3D              ## pickaxe viewmodel (right hand + haft + head)
var pick_swinging := false
var pick_t := 0.0
var pick_hit_done := false
var vein_hint_cd := 0.0          ## rate-limits the "needs a pickaxe" nudge

## --- War Axe (weapon 4): a heavy one-handed cleaver. Slower and harder-
## hitting than the sword, no combo ladder — two ALTERNATING committed swings
## (overhead chop / horizontal cleave), each with its own full animation.
## Honest iron: no material matchups yet.
## TODO(design): fold the axe into the metal system + weapon styles (step 4/5);
## should it eventually chop trees once TreeLife lands? ---
const AXE_TIME := 0.58           ## one full swing (DEX shortens it)
const AXE_WINDUP := 0.36         ## fraction spent hauling it back
const AXE_HIT_AT := 0.52         ## damage lands AT the visual impact
const AXE_STAMINA := 15.0
const AXE_RANGE := 2.8
const AXE_DMG_MULT := 1.35       ## × base_damage (STR rides along)
const AXE_REST_POS := Vector3(0.34, -0.36, -0.50)
const AXE_REST_ROT := Vector3(22.0, -16.0, 8.0)
var axe_vm: Node3D               ## axe viewmodel (right hand + haft + head)
var axe_swinging := false
var axe_t := 0.0
var axe_hit_done := false
var axe_side := 0                ## alternates: 0 = overhead chop, 1 = cleave

## --- Bestiary (Tab page 4): what you've slain and what you've LEARNED. ---
## A mob's row stays ??? until your first kill of it; each material's matchup
## stays ??? until you land that metal on that creature. Learn by doing.
var bestiary_kills := {}         ## display_name -> kills this run
var bestiary_proven := {}        ## display_name -> {material id: true}
var bestiary_selected := "Boar"
var best_list_box: VBoxContainer
var best_detail: VBoxContainer
var _mob_stat_cache := {}        ## display_name -> {hp, dmg, fams, flavor}

const FAMILY_NAMES := {
	"beast": "Beast", "humanoid": "Humanoid", "undead": "Undead",
	"cursed": "Cursed", "armored": "Armored", "construct": "Construct",
	"demon": "Demon", "fae": "Fae", "dragonkin": "Dragonkin",
}
const MOB_FLAVOR := {
	"Boar": "Doesn't want trouble until you're close — then the head drops and the ground drums.",
	"Kobold": "Twitchy tunnel vermin with a spear and a grudge. Weak alone. Never alone.",
	"Goblin": "A raider that fights dirty. The low crouch is the tell — the pounce follows.",
	"Skeleton": "An old soldier with no flesh left to bruise. Only the right metal talks to bone.",
	"Orc": "A duelist's patience wrapped in scarred muscle. It waits for your mistake.",
	"Ogre": "A siege engine that breathes. Treats a raised shield as a suggestion.",
	"Dark Knight": "Something cursed rattles inside that plate, and it does not tire. Steel dents the armor; the curse drinks the rest.",
	"Horse": "Fast, wary, and stronger than it looks. The saddled ones will carry you for as long as you deserve it; all of them remember a blade.",
}


func _ready() -> void:
	add_to_group("player")
	for id in PlayerStats.STAT_ORDER:
		pending[id] = 0
	_init_inventory()
	_build_body()
	_build_hud()
	_load_settings()
	_apply_settings()
	_refresh_derived(true)
	## Stick to stairs going down, so stepping off small ledges doesn't launch you.
	floor_snap_length = STEP_HEIGHT
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _box(parent: Node, size: Vector3, color: Color, pos: Vector3, rot := Vector3.ZERO, metal := false) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.4 if metal else 1.0
	if metal:
		mat.metallic = 0.7
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot
	parent.add_child(m)
	return m


func _make_sword(parent: Node, base_pos := Vector3.ZERO, mat_id := "iron") -> Node3D:
	## The held sword, built from its material (Materials.gd): blade takes the
	## metal's color, elemental metals glow and wear a translucent aura shell.
	var s := Node3D.new()
	parent.add_child(s)
	s.position = base_pos
	var mat: Dictionary = Materials.get_mat(mat_id)
	var blade_col: Color = mat["color"]
	var elem: Dictionary = mat["element"]
	var dark := Color(0.12, 0.10, 0.09)
	var gold := Color(0.50, 0.42, 0.22)
	var blade := _box(s, Vector3(0.05, 0.09, 0.95), blade_col, Vector3(0, 0, -0.55), Vector3.ZERO, true)  ## blade (-z)
	if not elem.is_empty():
		var ecol: Color = elem["color"]
		var bmat := blade.material_override as StandardMaterial3D
		bmat.emission_enabled = true
		bmat.emission = ecol
		bmat.emission_energy_multiplier = 0.9
		## The aura: element light wrapped around the blade. Fixed mid intensity —
		## TODO(design): scale with the sword's evolution level (step 5).
		var shell := _box(s, Vector3(0.10, 0.15, 1.02), ecol, Vector3(0, 0, -0.55))
		var smat := shell.material_override as StandardMaterial3D
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.albedo_color = Color(ecol.r, ecol.g, ecol.b, 0.20)
		smat.emission_enabled = true
		smat.emission = ecol
		smat.emission_energy_multiplier = 2.0
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_box(s, Vector3(0.26, 0.05, 0.05), gold, Vector3(0, 0, -0.05))                        ## crossguard
	_box(s, Vector3(0.04, 0.04, 0.16), dark, Vector3(0, 0, 0.06))                          ## grip
	_box(s, Vector3(0.06, 0.06, 0.05), gold, Vector3(0, 0, 0.16))                          ## pommel
	return s


func _make_arm(shoulder: Vector3, armor_col: Color, skin_col: Color) -> Node3D:
	## Arm hanging from a shoulder pivot (rotate the pivot's X to swing it).
	var pivot := Node3D.new()
	body_rig.add_child(pivot)
	pivot.position = shoulder
	_box(pivot, Vector3(0.14, 0.42, 0.15), armor_col, Vector3(0, -0.23, 0))   ## upper arm
	_box(pivot, Vector3(0.13, 0.15, 0.14), skin_col, Vector3(0, -0.50, 0.02)) ## hand
	return pivot


func _build_body() -> void:
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.4
	col.shape = capsule
	col.position = Vector3(0, 0.9, 0)
	add_child(col)
	body_col = col  ## switched off while riding (the horse's body carries you)

	## --- Visible body (seen when you look down). Attached to the body, not camera. ---
	body_rig = Node3D.new()
	add_child(body_rig)
	var armor := Color(0.20, 0.22, 0.28)
	var leather := Color(0.26, 0.18, 0.12)
	var skin := Color(0.62, 0.46, 0.36)
	torso_mesh = _box(body_rig, Vector3(0.44, 0.62, 0.26), armor, Vector3(0, 1.05, 0))      ## torso
	pelvis_mesh = _box(body_rig, Vector3(0.38, 0.22, 0.24), leather, Vector3(0, 0.72, 0))    ## pelvis
	## Legs on hip pivots so they stride with the gait (look down and walk).
	for sx: float in [-0.14, 0.14]:
		var leg := Node3D.new()
		body_rig.add_child(leg)
		leg.position = Vector3(sx, 0.74, 0)
		leg_meshes.append(_box(leg, Vector3(0.18, 0.72, 0.22), leather, Vector3(0, -0.36, 0)))    ## leg
		foot_meshes.append(_box(leg, Vector3(0.20, 0.12, 0.34), BODY_FOOT_COL, Vector3(0, -0.68, -0.05)))  ## foot
		leg_pivots.append(leg)
	## Arms hang from shoulder pivots so they can swing with your stride.
	## Left arm is always shown; the right arm only appears when the sword is
	## sheathed (otherwise the right hand is the sword viewmodel on the camera).
	left_arm = _make_arm(Vector3(-0.26, 1.30, 0.0), armor, skin)
	right_arm = _make_arm(Vector3(0.26, 1.30, 0.0), armor, skin)
	right_arm.visible = false
	## The upper-arm plates tint with the equipped Bracers material.
	arm_meshes.append(left_arm.get_child(0) as MeshInstance3D)
	arm_meshes.append(right_arm.get_child(0) as MeshInstance3D)

	## Scabbard on the left hip — ALWAYS visible. This is the spot the sword is
	## drawn from and returned to (you can see it when you look down).
	_box(body_rig, Vector3(0.09, 0.52, 0.11), Color(0.09, 0.07, 0.05), Vector3(-0.30, 0.92, 0.06), Vector3(105, 0, 12))
	_box(body_rig, Vector3(0.12, 0.06, 0.14), Color(0.45, 0.38, 0.20), Vector3(-0.27, 1.15, -0.02), Vector3(105, 0, 12))  ## scabbard mouth
	## The sword HANDLE poking up out of the belt scabbard (shown only while sheathed).
	hip_sword = Node3D.new()
	body_rig.add_child(hip_sword)
	hip_sword.position = Vector3(-0.27, 1.16, -0.03)
	hip_sword.rotation_degrees = Vector3(105, 0, 12)
	var hilt_gold := Color(0.50, 0.42, 0.22)
	var hilt_dark := Color(0.12, 0.10, 0.09)
	_box(hip_sword, Vector3(0.20, 0.04, 0.04), hilt_gold, Vector3(0, 0, 0.0))      ## crossguard
	_box(hip_sword, Vector3(0.035, 0.035, 0.14), hilt_dark, Vector3(0, 0, 0.10))   ## grip
	_box(hip_sword, Vector3(0.06, 0.06, 0.05), hilt_gold, Vector3(0, 0, 0.18))     ## pommel
	hip_sword.visible = false

	## Stowed shield across the upper back — the offhand's own "scabbard".
	## Shown whenever an equipped shield is sheathed with the blade (or slung
	## because both hands are on the bow). Same boards as the held version.
	back_shield = Node3D.new()
	body_rig.add_child(back_shield)
	back_shield.position = Vector3(0.04, 1.28, 0.24)
	back_shield.rotation_degrees = Vector3(4.0, 0.0, 14.0)
	var bs_wood := Color(0.38, 0.26, 0.14)
	var bs_rim := Color(0.24, 0.16, 0.09)
	_box(back_shield, Vector3(0.34, 0.44, 0.045), bs_wood, Vector3.ZERO)
	_box(back_shield, Vector3(0.44, 0.30, 0.045), bs_wood, Vector3.ZERO)
	_box(back_shield, Vector3(0.36, 0.46, 0.02), bs_rim, Vector3(0, 0, 0.024))
	_box(back_shield, Vector3(0.10, 0.10, 0.07), Color(0.60, 0.63, 0.68), Vector3(0, 0, 0.05), Vector3.ZERO, true)
	back_shield.visible = false

	## --- Head + camera ---
	head = Node3D.new()
	head.position = Vector3(0, 1.62, 0)
	add_child(head)
	camera = Camera3D.new()
	head.add_child(camera)
	camera.current = true

	## --- First-person viewmodel: right hand + held sword (attached to camera). ---
	viewmodel = Node3D.new()
	camera.add_child(viewmodel)
	_box(viewmodel, Vector3(0.10, 0.10, 0.13), skin, Vector3(0, 0, 0.02))          ## hand
	forearm_mesh = _box(viewmodel, Vector3(0.09, 0.09, 0.30), armor, Vector3(0, -0.05, 0.18), Vector3(8, 0, 0))  ## forearm
	sword_vm = _make_sword(viewmodel, Vector3(0, 0.02, -0.04), _sword_material_id())
	viewmodel.position = vm_ready_pos
	viewmodel.rotation_degrees = vm_ready_rot

	## --- Offhand viewmodel: left hand holding the shield / torch. ---
	offhand_node = Node3D.new()
	camera.add_child(offhand_node)
	offhand_node.position = OH_REST_POS + Vector3(-0.10, -0.42, 0.10)  ## starts lowered
	offhand_node.rotation_degrees = OH_REST_ROT
	offhand_node.visible = false

	## --- Bow viewmodel (weapon 2): left fist on the grip, arrow on the string. ---
	bow_vm = Node3D.new()
	camera.add_child(bow_vm)
	bow_vm.position = Vector3(-0.26, -0.36, -0.52)
	bow_vm.rotation_degrees = Vector3(-6.0, 24.0, -14.0)
	bow_vm.visible = false
	_build_bow_mesh()

	## --- Pickaxe viewmodel (weapon 3): right hand on a haft, iron head. ---
	pick_vm = Node3D.new()
	camera.add_child(pick_vm)
	pick_vm.position = PICK_REST_POS
	pick_vm.rotation_degrees = PICK_REST_ROT
	pick_vm.visible = false
	_build_pick_mesh()

	## --- War axe viewmodel (weapon 4). ---
	axe_vm = Node3D.new()
	camera.add_child(axe_vm)
	axe_vm.position = AXE_REST_POS
	axe_vm.rotation_degrees = AXE_REST_ROT
	axe_vm.visible = false
	_build_axe_mesh()

	_apply_armor_visuals()  ## start in whatever the slots say (defaults today)


func _build_bow_mesh() -> void:
	var wood := Color(0.30, 0.20, 0.11)
	var dark := Color(0.16, 0.11, 0.07)
	var skin := Color(0.62, 0.46, 0.36)
	_box(bow_vm, Vector3(0.05, 0.15, 0.06), dark, Vector3(0, 0, 0))                                ## grip
	_box(bow_vm, Vector3(0.04, 0.30, 0.05), wood, Vector3(0, 0.20, -0.03), Vector3(-13, 0, 0))     ## upper limb
	_box(bow_vm, Vector3(0.04, 0.30, 0.05), wood, Vector3(0, -0.20, -0.03), Vector3(13, 0, 0))     ## lower limb
	_box(bow_vm, Vector3(0.035, 0.10, 0.045), wood, Vector3(0, 0.36, -0.085), Vector3(-28, 0, 0))  ## upper tip
	_box(bow_vm, Vector3(0.035, 0.10, 0.045), wood, Vector3(0, -0.36, -0.085), Vector3(28, 0, 0))  ## lower tip
	bow_string = _box(bow_vm, Vector3(0.008, 0.78, 0.008), Color(0.85, 0.82, 0.72), Vector3(0, 0, -0.115))
	_box(bow_vm, Vector3(0.09, 0.09, 0.11), skin, Vector3(0.0, -0.02, 0.01))                       ## left fist
	## The nocked arrow — visible while drawing, slides back with the pull.
	bow_arrow_vm = Node3D.new()
	bow_vm.add_child(bow_arrow_vm)
	_box(bow_arrow_vm, Vector3(0.014, 0.014, 0.52), Color(0.45, 0.33, 0.18), Vector3(0, 0, -0.30))
	_box(bow_arrow_vm, Vector3(0.028, 0.028, 0.05), Color(0.75, 0.78, 0.82), Vector3(0, 0, -0.57), Vector3.ZERO, true)
	_box(bow_arrow_vm, Vector3(0.05, 0.012, 0.08), Color(0.90, 0.88, 0.80), Vector3(0, 0, -0.02))
	bow_arrow_vm.visible = false
	## Right hand pinching the string (drawing only).
	bow_hand_vm = Node3D.new()
	bow_vm.add_child(bow_hand_vm)
	_box(bow_hand_vm, Vector3(0.085, 0.085, 0.12), skin, Vector3.ZERO)
	bow_hand_vm.visible = false


func _build_axe_mesh() -> void:
	## A soldier's cleaver: fist, wrapped haft, and a broad wedge of a head
	## with a blunt back-spike. Placeholder boxes like everything else.
	var skin := Color(0.62, 0.46, 0.36)
	var armor := Color(0.30, 0.31, 0.36)
	var wood := Color(0.30, 0.20, 0.11)
	var wrap := Color(0.20, 0.14, 0.09)
	var iron := Color(0.58, 0.60, 0.64)
	_box(axe_vm, Vector3(0.10, 0.10, 0.13), skin, Vector3(0, 0, 0.02))                          ## hand
	_box(axe_vm, Vector3(0.09, 0.09, 0.30), armor, Vector3(0, -0.05, 0.18), Vector3(8, 0, 0))   ## forearm
	_box(axe_vm, Vector3(0.055, 0.055, 0.66), wood, Vector3(0, 0.02, -0.34))                    ## haft (-z)
	_box(axe_vm, Vector3(0.06, 0.06, 0.10), wrap, Vector3(0, 0.02, -0.06))                      ## grip wrap
	_box(axe_vm, Vector3(0.07, 0.10, 0.13), iron, Vector3(0, 0.02, -0.64), Vector3.ZERO, true)  ## head socket
	## The blade: a broad wedge sweeping down-forward, edge proud of the haft.
	_box(axe_vm, Vector3(0.045, 0.34, 0.16), iron, Vector3(0, -0.14, -0.66), Vector3(-8, 0, 0), true)
	_box(axe_vm, Vector3(0.04, 0.40, 0.05), iron, Vector3(0, -0.16, -0.73), Vector3(-8, 0, 0), true)  ## edge
	_box(axe_vm, Vector3(0.05, 0.07, 0.10), iron, Vector3(0, 0.06, -0.58), Vector3(14, 0, 0), true)   ## back spike


func _build_pick_mesh() -> void:
	## Right hand gripping a wooden haft; a dark iron head with two tapering
	## picks, one biting forward. Placeholder boxes like everything else.
	var skin := Color(0.62, 0.46, 0.36)
	var armor := Color(0.20, 0.22, 0.28)
	var wood := Color(0.34, 0.23, 0.13)
	var iron := Color(0.36, 0.37, 0.40)
	_box(pick_vm, Vector3(0.10, 0.10, 0.13), skin, Vector3(0, 0, 0.02))                         ## hand
	_box(pick_vm, Vector3(0.09, 0.09, 0.30), armor, Vector3(0, -0.05, 0.18), Vector3(8, 0, 0))  ## forearm
	_box(pick_vm, Vector3(0.055, 0.055, 0.78), wood, Vector3(0, 0.02, -0.42))                   ## haft (-z)
	_box(pick_vm, Vector3(0.07, 0.11, 0.16), iron, Vector3(0, 0.02, -0.78), Vector3.ZERO, true) ## head socket
	## The two picks: a long spike dipping toward the rock, a stub behind.
	_box(pick_vm, Vector3(0.05, 0.42, 0.06), iron, Vector3(0, -0.16, -0.80), Vector3(-16, 0, 0), true)
	_box(pick_vm, Vector3(0.045, 0.14, 0.055), iron, Vector3(0, 0.13, -0.77), Vector3(14, 0, 0), true)


func _make_bar(h: float, fill_col: Color) -> Array:
	var bar := Control.new()
	bar.size = Vector2(BAR_W, h)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(bar)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.5)
	bg.size = Vector2(BAR_W, h)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(bg)
	var fill := ColorRect.new()
	fill.color = fill_col
	fill.size = Vector2(BAR_W, h)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(fill)
	return [bar, fill]


func _build_hud() -> void:
	hud_layer = CanvasLayer.new()
	add_child(hud_layer)

	var sp := _make_bar(10.0, Color(0.85, 0.72, 0.28))   ## stamina (amber)
	stamina_bar = sp[0]
	stamina_fill = sp[1]
	var hpp := _make_bar(16.0, Color(0.82, 0.16, 0.16))  ## health (red)
	health_bar = hpp[0]
	health_fill = hpp[1]
	var lv := _make_bar(7.0, Color(0.45, 0.70, 1.0))     ## level / xp (blue)
	level_bar = lv[0]
	level_fill = lv[1]

	## "[E] Pick up ..." — appears when a dropped item is under your gaze.
	pickup_prompt = Label.new()
	pickup_prompt.add_theme_font_size_override("font_size", 17)
	pickup_prompt.visible = false
	pickup_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(pickup_prompt)

	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 22)
	cross.anchor_left = 0.5
	cross.anchor_top = 0.5
	cross.position = Vector2(-7, -16)
	hud_layer.add_child(cross)

	_build_spawn_menu()
	_build_tab_menu()
	_build_settings_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS * set_sens)
		pitch = clampf(pitch - event.relative.y * MOUSE_SENS * set_sens, -1.4, 1.4)
		head.rotation.x = pitch
		_update_head_offset()


func _update_head_offset() -> void:
	## Slide the camera forward (and slightly down) as you look down, so your
	## own body comes into view instead of filling the lens.
	if kd_phase != "":
		return  ## the knockdown owns the camera height until you're back up
	var down := clampf(-pitch / 1.4, 0.0, 1.0)
	head.position = Vector3(0.0, 1.62 - down * 0.03, -0.18 * down)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if kd_phase != "":
			return  ## flat on the ground — no swinging, no drawing, nothing
		if event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if event.pressed:
				if current_weapon == "bow":
					_bow_start_draw()
				elif current_weapon == "pickaxe":
					_try_pick_swing()
				elif current_weapon == "axe":
					_try_axe_swing()
				else:
					_try_attack()
			elif current_weapon == "bow":
				_bow_loose()  ## release the string
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and drawing:
			drawing = false  ## right click eases the string back down
			bow_draw = 0.0
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_CTRL:
				if menu_open == "" and mount == null and kd_phase == "":  ## menus shouldn't leak dashes/jumps into the game
					_try_dash()
			KEY_SPACE:
				if menu_open == "" and kd_phase == "" and not climbing:
					if mount != null:
						mount.request_jump()
					else:
						## Resolved in _physics_process — the climb check needs
						## physics-space raycasts, which _input can't touch.
						jump_queued = true
			KEY_F:
				if menu_open == "":
					_try_mount_toggle()
			KEY_ALT:
				if current_weapon == "sword":
					sheathed = not sheathed
			KEY_Q:
				## In the inventory, Q drops the hovered item at your feet;
				## out in the world it cycles the offhand as always.
				if menu_open == "tab" and tab_page == "inventory" and hovered_item_idx >= 0:
					_drop_item(hovered_item_idx)
				elif menu_open == "":
					_cycle_offhand()
			KEY_E:
				if menu_open == "" and kd_phase == "" and _drop_target != null \
						and is_instance_valid(_drop_target):
					_pickup_dropped(_drop_target)
			KEY_M:
				_toggle_menu("spawn")
			KEY_5:
				if menu_open == "":  ## number keys switch pages while a menu is up
					get_tree().reload_current_scene()  ## quick restart of the whole world
			KEY_TAB:
				_open_tab_menu(tab_page)
			KEY_I:
				_open_tab_menu("inventory")
			KEY_1:
				if menu_open == "tab":
					_set_tab_page("inventory")
				else:
					_select_weapon("sword")
			KEY_2:
				if menu_open == "tab":
					_set_tab_page("stats")
				else:
					_select_weapon("bow")
			KEY_3:
				if menu_open == "tab":
					_set_tab_page("progression")
				else:
					_select_weapon("pickaxe")
			KEY_4:
				if menu_open == "tab":
					_set_tab_page("bestiary")
				elif menu_open == "":
					_select_weapon("axe")
			KEY_ESCAPE:
				if menu_open != "":
					_close_menu()
				else:
					_toggle_menu("settings")  ## Esc = the settings/pause menu


func _physics_process(delta: float) -> void:
	since_last_attack += delta

	## Knocked flat (a horse's hoof, mostly): you eat dirt, lie there, and get
	## up slow — and everything out there is free to keep hitting you through
	## the entire fall-and-rise. Handles its own frame, then bails.
	if kd_phase != "":
		_update_knockdown(delta)
		return

	## Mid-mantle: the climb owns the body until you're up and over.
	if climbing:
		_update_climb(delta)
		return

	## In the saddle: the horse's body does the moving — feed it the reins,
	## ride its back, keep the sword arm live. Handles its own frame too.
	if mount != null:
		_update_mounted(delta)
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	if block_broken_timer > 0.0:
		block_broken_timer -= delta
	var was_blocking := blocking
	blocking = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and block_broken_timer <= 0.0 \
		and current_weapon == "sword"  ## both hands are busy with the bow
	## Parry timing: how fresh is this guard? (A block raised within PARRY_WINDOW
	## of the hit landing counts as a perfect guard.)
	if blocking and not was_blocking:
		block_held_time = 0.0
		if sheathed:
			sheathed = false  ## raising a guard pulls the steel — and the shield off your back
	elif blocking:
		block_held_time += delta
	else:
		block_held_time = 999.0

	_update_hunch(delta)

	## Space, resolved here where the physics space is queryable: a grabbable
	## ledge ahead beats a jump — otherwise jump if the ground agrees.
	if jump_queued:
		jump_queued = false
		if not _try_climb() and is_on_floor():
			velocity.y = JUMP_VELOCITY

	## Movement direction from raw keys (relative to facing).
	move_input = Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move_input.z -= 1.0
	if Input.is_key_pressed(KEY_S): move_input.z += 1.0
	if Input.is_key_pressed(KEY_A): move_input.x -= 1.0
	if Input.is_key_pressed(KEY_D): move_input.x += 1.0
	var dir := (transform.basis * move_input).normalized()
	dir.y = 0.0

	var overweight := _total_weight() > stats.carry_limit()
	var speed := SPEED * stats.speed_mult()  ## DEX: a little quicker on your feet
	sprinting = false
	if blocking or drawing:  ## guarding or holding a draw = slow, deliberate steps
		speed = BLOCK_SPEED
	elif Input.is_key_pressed(KEY_SHIFT) and stamina > 0.0 and move_input != Vector3.ZERO and not overweight:
		sprinting = true
		speed = SPRINT_SPEED * stats.speed_mult()
		stamina = maxf(0.0, stamina - SPRINT_DRAIN * stats.stamina_cost_mult() * delta)
		stamina_delay = maxf(stamina_delay, 0.4)  ## regen pauses briefly after you stop
	if overweight:
		speed *= 0.5  ## TODO(design): overburdened — flat 50% slowdown + no sprint for now

	## Hit-stun (thrown out of an action) overrides input; otherwise dash; otherwise glide.
	if hitstun_timer > 0.0:
		hitstun_timer -= delta
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
	elif dash_timer > 0.0:
		dash_timer -= delta
		var d := dir if dir != Vector3.ZERO else -transform.basis.z
		velocity.x = d.x * DASH_SPEED
		velocity.z = d.z * DASH_SPEED
	else:
		var rate := ACCEL if dir != Vector3.ZERO else DECEL
		if not is_on_floor():
			rate = AIR_ACCEL
		var hv := Vector3(velocity.x, 0.0, velocity.z)
		var target := dir * speed
		hv = hv.move_toward(target, rate * delta)
		velocity.x = hv.x
		velocity.z = hv.z

	_frame_fx_and_regen(delta)

	move_and_slide()
	## Marathoner: meters actually covered on foot.
	if is_on_floor():
		dist_accum += Vector2(velocity.x, velocity.z).length() * delta
		if dist_accum >= 1.0:
			var whole := int(dist_accum)
			dist_accum -= float(whole)
			_record_progress("marathoner", whole)
	_update_gait(delta)
	_step_up(delta)
	_apply_step_smooth(delta)
	_update_body_arms(delta)
	_update_hud(delta)
	_update_log(delta)


func _frame_fx_and_regen(delta: float) -> void:
	## The upkeep every stance shares — on foot, in the saddle, or face-down in
	## the dirt: camera shake, held-item animation, stamina/health regen, and
	## the progression timers.
	if invuln_timer > 0.0:
		invuln_timer -= delta

	## Camera shake (guard break / heavy hits) — random jitter that eases out.
	## When calm, the camera settles onto the walk-cycle sway instead of dead
	## zero (the vertical half of the bob is composed in _apply_step_smooth).
	if cam_shake > 0.0:
		cam_shake = maxf(0.0, cam_shake - delta)
		camera.position = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * cam_shake * 0.12
	else:
		camera.position.x = lerpf(camera.position.x, head_bob.x, clampf(delta * 10.0, 0.0, 1.0))
		camera.position.z = lerpf(camera.position.z, 0.0, clampf(delta * 12.0, 0.0, 1.0))

	_update_viewmodel(delta)
	_update_offhand(delta)
	_update_bow(delta)
	_update_pickaxe(delta)
	_update_axe(delta)

	## Stamina regen: not while sprinting or blocking, and only after a short
	## breather following whatever last spent it. (Regen used to run DURING the
	## sprint drain, so sprinting netted +8/s and the bar never moved.)
	if stamina_delay > 0.0:
		stamina_delay -= delta
	if stamina < max_stamina and not blocking and not sprinting and not drawing and stamina_delay <= 0.0:
		stamina = minf(max_stamina, stamina + stamina_regen * delta)

	## Very slow regen, only a few seconds after the last combat action.
	## CON makes the wounds close faster.
	combat_timer += delta
	if combat_timer > COMBAT_HEAL_DELAY and health < max_health:
		health = minf(max_health, health + stats.heal_rate() * delta)

	## Progression timers + Death's Door: you hit the brink earlier — climbing
	## back past 60% (which only regen can do) scores the recovery.
	if dodge_cd > 0.0:
		dodge_cd -= delta
	if near_death_cd > 0.0:
		near_death_cd -= delta
	if near_death_active and health >= max_health * 0.6:
		near_death_active = false
		near_death_cd = 45.0
		_add_log_msg("Back from the brink!", Color(1.0, 0.55, 0.45))
		_record_progress("deaths_door", 1)


## ================== The Hunch (auto sheathe / unsheathe) ===================


func _any_enemy_mad_at_me() -> bool:
	## "Mad at you" = a hostile creature sitting in its AGITATED state. Horses
	## don't count — their agitation is flight (or one indignant kick), not menace.
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en == null or en is Horse or en.dying:
			continue
		if en.state == Enemy.State.AGITATED:
			return true
	return false


func _update_hunch(delta: float) -> void:
	## THE HUNCH: a prickle on the back of the neck. The instant something out
	## there turns hostile the blade — and the shield with it — clears the
	## scabbard on its own; after HUNCH_SHEATHE_AFTER quiet seconds everything
	## rides home again. Toggleable in the Esc settings menu.
	## TODO(design): should the hunch also yank you off the pickaxe/bow onto
	## the sword when something jumps you mid-mining? For now it minds the
	## sword only — tools are a choice.
	if not set_hunch or current_weapon != "sword" or mount != null or kd_phase != "":
		hunch_aggro_prev = false
		hunch_calm_t = 0.0
		return
	var mad := _any_enemy_mad_at_me()
	if mad:
		hunch_calm_t = 0.0
		## Edge-triggered on fresh aggro only, so Alt can still sheathe
		## mid-fight in open defiance without being fought every frame.
		if sheathed and not hunch_aggro_prev and not attacking:
			sheathed = false
			_add_log_msg("The hunch: something means you harm", Color(1.0, 0.62, 0.35))
	elif sheathed or attacking or blocking or since_last_attack < 1.2:
		hunch_calm_t = 0.0  ## still busy — calm hasn't started counting
	else:
		hunch_calm_t += delta
		if hunch_calm_t >= HUNCH_SHEATHE_AFTER:
			sheathed = true  ## calm confirmed — steel and shield ride home
			hunch_calm_t = 0.0
	hunch_aggro_prev = mad


## ====================== Riding (E near a saddled horse) ====================


func _update_mounted(delta: float) -> void:
	blocking = false     ## no guard from the saddle — speed IS the guard
	sprinting = false
	drawing = false
	if block_broken_timer > 0.0:
		block_broken_timer -= delta
	if hitstun_timer > 0.0:
		hitstun_timer -= delta  ## a hit still rattles you in the saddle

	## Feed the reins: raw WASD, camera-relative — the horse does the turning.
	var mi := Vector3.ZERO
	if menu_open == "":
		if Input.is_key_pressed(KEY_W): mi.z -= 1.0
		if Input.is_key_pressed(KEY_S): mi.z += 1.0
		if Input.is_key_pressed(KEY_A): mi.x -= 1.0
		if Input.is_key_pressed(KEY_D): mi.x += 1.0
	mount.ride_input = Vector2(mi.x, mi.z)
	mount.ride_run = Input.is_key_pressed(KEY_SHIFT) and mi != Vector3.ZERO
	move_input = Vector3.ZERO

	## Ride the saddle point; the horse's capsule is the one doing physics.
	global_position = mount.saddle_world()
	velocity = Vector3.ZERO

	## The saddle's rhythm replaces your own stride in the camera.
	head_bob = head_bob.lerp(Vector2(
		sin(mount.walk_t) * 0.020,
		(absf(sin(mount.walk_t)) - 0.5) * -0.030) * mount._loco_amount,
		clampf(delta * 10.0, 0.0, 1.0))
	gait_amount = lerpf(gait_amount, 0.0, clampf(delta * 6.0, 0.0, 1.0))

	_frame_fx_and_regen(delta)
	_apply_step_smooth(delta)
	_update_body_arms(delta)
	_update_hud(delta)
	_update_log(delta)


func _try_mount_toggle() -> void:
	if kd_phase != "" or climbing:
		return
	if mount != null:
		_dismount()
		return
	if attacking or hitstun_timer > 0.0 or dash_timer > 0.0:
		return
	var best: Horse = null
	var best_d := 3.4
	for h in get_tree().get_nodes_in_group("horses"):
		if not (h is Horse) or (h as Horse).dying:
			continue
		var d := (h as Horse).global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = h as Horse
	if best == null:
		return
	if not best.rideable:
		_add_log_msg("The horse shies away — it will never take a rider", Color(0.8, 0.8, 0.8))
		return
	if best.trust_broken:
		_add_log_msg("It remembers your blade. It will not carry you", Color(0.95, 0.55, 0.45))
		return
	_mount(best)


func _mount(h: Horse) -> void:
	if current_weapon != "sword":
		_select_weapon("sword")  ## only the sword works from the saddle
	mount = h
	h.rider = self
	h.confused = false
	if body_col:
		body_col.set_deferred("disabled", true)
	velocity = Vector3.ZERO
	attacking = false
	draw_attack = false
	blocking = false
	drawing = false
	bow_draw = 0.0
	pick_swinging = false
	sheathed = false  ## ride with steel in hand
	_add_log_msg("Mounted — Shift gallop, Space jump, F dismount", Color(0.85, 0.9, 1.0))


func _dismount() -> void:
	var h := mount
	mount = null
	if h != null:
		h.rider = null
		h.ride_input = Vector2.ZERO
		h.ride_run = false
		## Step down on the horse's left.
		global_position = h.global_position - h.transform.basis.x * 1.35 + Vector3.UP * 0.45
	if body_col:
		body_col.set_deferred("disabled", false)
	velocity = Vector3.ZERO


func thrown_from_mount(h: Node3D) -> void:
	## Bucked off — or the horse died under you. Either way you leave the
	## saddle the hard way and hit the ground in a heap.
	mount = null
	if body_col:
		body_col.set_deferred("disabled", false)
	global_position = h.global_position - h.transform.basis.x * 1.15 + Vector3.UP * 0.9
	var side := (-h.transform.basis.x + Vector3(randf() - 0.5, 0.0, randf() - 0.5) * 0.3).normalized()
	_start_knockdown(h.global_position, side * 5.5)
	_add_log_msg("Thrown!", Color(1.0, 0.45, 0.30))


## ================== Knockdown (kicked flat / bucked off) ===================


func horse_kick(dmg: float, from_pos: Vector3, attacker: Node = null) -> void:
	## Two hooves like hammers. Timing still saves you — a dash's i-frames or a
	## perfect guard turn it aside — but anything less puts you on the ground.
	if invuln_timer > 0.0:
		if dash_timer > 0.0 and dodge_cd <= 0.0:
			dodge_cd = 0.5
			_add_log_msg("Dodged!", Color(0.55, 0.95, 1.0))
			_record_progress("untouchable", 1)
		return
	combat_timer = 0.0
	if blocking and block_held_time <= PARRY_WINDOW:
		block_held_time = 999.0
		block_impact = 0.22
		cam_shake = maxf(cam_shake, 0.12)
		_add_log_msg("Parried!", Color(1.0, 0.95, 0.55))
		if attacker != null and attacker.has_method("on_parried"):
			attacker.on_parried()
		_record_progress("perfect_guard", 1)
		return
	health -= dmg * stats.damage_taken_mult()
	cam_shake = maxf(cam_shake, 0.4)
	if kd_phase == "":
		var away := global_position - from_pos
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else Vector3.BACK
		_start_knockdown(from_pos, away * 5.0)
	if health > 0.0 and health <= max_health * 0.15 and not near_death_active and near_death_cd <= 0.0:
		near_death_active = true
	if health <= 0.0:
		_die()


func _start_knockdown(_from_pos: Vector3, fling := Vector3.ZERO) -> void:
	## Down you go. Cancels everything in your hands; protects NOTHING.
	attacking = false
	draw_attack = false
	drawing = false
	bow_draw = 0.0
	climbing = false  ## knocked clean off the wall
	pick_swinging = false
	blocking = false
	dash_timer = 0.0
	hitstun_timer = 0.0
	kd_phase = "fall"
	kd_t = 0.0
	velocity = Vector3(fling.x, 2.6, fling.z)


func _update_knockdown(delta: float) -> void:
	kd_t += delta
	blocking = false
	sprinting = false
	if not is_on_floor():
		velocity.y -= gravity * delta
	velocity.x = move_toward(velocity.x, 0.0, 6.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 6.0 * delta)
	move_and_slide()

	## The camera sells the fall: drop hard and roll onto your side, lie there,
	## then climb back up with a stagger. (Mouse-look stays live — you watch it
	## happen.) NO invulnerability at any point: whatever's out there is free
	## to keep hitting you through the whole thing.
	var roll := 0.0
	match kd_phase:
		"fall":
			var u := clampf(kd_t / KD_FALL, 0.0, 1.0)
			var e := 1.0 - (1.0 - u) * (1.0 - u)  ## fast in — the ground arrives
			head.position.y = lerpf(1.62, 0.50, e)
			roll = 26.0 * e
			if u >= 1.0:
				kd_phase = "down"
				kd_t = 0.0
		"down":
			head.position.y = 0.50 + sin(kd_t * 5.0) * 0.012  ## ragged breath
			roll = 26.0
			if kd_t >= KD_DOWN:
				kd_phase = "rise"
				kd_t = 0.0
		"rise":
			var u := clampf(kd_t / KD_RISE, 0.0, 1.0)
			var e := u * u * (3.0 - 2.0 * u)
			head.position.y = lerpf(0.50, 1.62, e) - sin(u * PI) * 0.06  ## a wobble on the way up
			roll = 26.0 * (1.0 - e)
			if u >= 1.0:
				kd_phase = ""
				kd_t = 0.0
				_update_head_offset()  ## hand the camera back to mouse-look
	camera.rotation_degrees.z = roll

	_frame_fx_and_regen(delta)
	_update_hud(delta)
	_update_log(delta)


func notify(text: String, col := Color(0.9, 0.9, 1.0)) -> void:
	## Public log hook (horses use it to tell you the trust just died).
	_add_log_msg(text, col)


func _update_gait(delta: float) -> void:
	## The one shared stride. Amplitude eases toward "how fast are we actually
	## moving" so animations breathe in and out instead of snapping, and the
	## phase only advances on the ground — nobody pumps their arms in mid-air.
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var target := clampf(hspeed / SPRINT_SPEED, 0.0, 1.0) if is_on_floor() else 0.0
	gait_amount = lerpf(gait_amount, target, clampf(delta * 6.0, 0.0, 1.0))
	if is_on_floor():
		gait_phase += delta * (4.5 + hspeed * 1.35)
	## Landing: remember how hard we fell, dip the view, spring softly back.
	if not is_on_floor():
		_fall_speed = maxf(0.0, -velocity.y)
	elif not _was_on_floor:
		land_dip = maxf(land_dip, clampf(_fall_speed * 0.014, 0.0, 0.16))
		_apply_fall_damage(_fall_speed)
	_was_on_floor = is_on_floor()
	land_dip = lerpf(land_dip, 0.0, clampf(delta * 8.0, 0.0, 1.0))
	## Head-bob target: a gentle side sway, plus a dip at each footfall.
	var bt := Vector2(
		sin(gait_phase) * 0.016,
		(absf(sin(gait_phase)) - 0.5) * -0.022)
	head_bob = head_bob.lerp(bt * gait_amount, clampf(delta * 10.0, 0.0, 1.0))


func _apply_fall_damage(spd: float) -> void:
	## Called once at touchdown with the impact speed. Bypasses blocking and
	## i-frames — the ground doesn't care how good your guard is.
	if spd <= FALL_SAFE_SPEED or kd_phase != "" or mount != null or climbing:
		return
	var dmg := (spd - FALL_SAFE_SPEED) * FALL_DMG_PER_MS
	health -= dmg
	health_show = 3.0
	combat_timer = 0.0
	cam_shake = maxf(cam_shake, clampf(0.10 + (spd - FALL_SAFE_SPEED) * 0.018, 0.0, 0.34))
	_add_log_msg("Hard landing! -%d" % int(dmg), Color(1.0, 0.5, 0.35))
	if health <= 0.0:
		_add_log_msg("The fall was too far.", Color(1.0, 0.35, 0.25))
		_die()
		return
	if spd >= FALL_KD_SPEED:
		_start_knockdown(global_position)  ## legs fold — down you go


func _apply_step_smooth(delta: float) -> void:
	## Compose the camera's vertical motion in ONE place — step-up easing,
	## landing dip, bump absorption, and walk bob (plus a whisper of roll) —
	## so the different effects layer instead of fighting over camera.position.
	if _step_smooth <= 0.0005:
		_step_smooth = 0.0
	else:
		_step_smooth = lerpf(_step_smooth, 0.0, clampf(delta * 16.0, 0.0, 1.0))
	## Bump absorption: whatever small vertical hop the BODY just made walking
	## the lumpy voxel rock, the EYE holds its height and eases after — the
	## feet do the bumping, the view glides. Grounded, small deltas only
	## (jumps, falls, and mantles stay raw and physical).
	var dy := global_position.y - _prev_body_y
	_prev_body_y = global_position.y
	if is_on_floor() and _was_on_floor and absf(dy) <= 0.5 and kd_phase == "" and not climbing:
		_eye_smooth = clampf(_eye_smooth - dy, -0.42, 0.42)
	_eye_smooth = lerpf(_eye_smooth, 0.0, clampf(delta * 13.0, 0.0, 1.0))
	if absf(_eye_smooth) < 0.0005:
		_eye_smooth = 0.0
	if camera:
		## Hard floor on the combined downward offset — whatever step-smoothing
		## and landing dips stack up, the lens never sinks into your own body.
		var down := maxf(-_step_smooth - land_dip, -0.26)
		camera.position.y = clampf(down + head_bob.y + _eye_smooth, -0.34, 0.55)
		camera.rotation_degrees.z = lerpf(camera.rotation_degrees.z,
			sin(gait_phase) * 0.4 * gait_amount, clampf(delta * 8.0, 0.0, 1.0))


func _step_up(delta: float) -> void:
	## Let the player walk up small ledges (anything up to STEP_HEIGHT). If the
	## path ahead is blocked at foot level but clear once lifted by a small amount,
	## snap up by the smallest height that clears — so short steps don't stop you,
	## but real walls still do.
	if not is_on_floor():
		return
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if horiz.length() < 0.05:
		return
	## Probe a little way ahead (min distance) so we catch small things we're
	## pressing into even at low speed — a gentle autojump over them.
	var motion := horiz.normalized() * maxf(horiz.length() * delta, 0.10)
	## Only bother if something is actually blocking us at foot level.
	if move_and_collide(motion, true) == null:
		return
	var params := PhysicsTestMotionParameters3D.new()
	var result := PhysicsTestMotionResult3D.new()
	for h: float in [0.12, 0.24, 0.36, STEP_HEIGHT]:
		var lifted := global_transform
		lifted.origin += Vector3.UP * h
		params.from = lifted
		params.motion = motion
		if not PhysicsServer3D.body_test_motion(get_rid(), params, result):
			## Clear at this height — it's a step, not a wall. Snap the body up, but
			## record the rise as a camera offset so the VIEW eases up smoothly
			## instead of popping. Capped LOW: repeated auto-steps (backing up a
			## cave ramp) used to stack this until the camera sank into the torso.
			global_position.y += h
			_step_smooth = minf(_step_smooth + h, 0.26)
			_prev_body_y += h  ## already compensated here — don't double-count in the bump absorber
			return


func _update_body_arms(delta: float) -> void:
	## Arms swing on the shared stride and ease with gait_amount, then lerp
	## toward their pose — stopping melts to rest instead of freezing mid-swing.
	## Both swing when sheathed; only the left arm swings when the sword is
	## drawn (the right hand is busy holding it).
	var s := sin(gait_phase) * 0.6 * gait_amount
	var k := clampf(delta * 14.0, 0.0, 1.0)
	if mount != null:
		## In the saddle: thighs forward, feet in the stirrups, arms quiet.
		for lp in leg_pivots:
			lp.rotation.x = lerpf(lp.rotation.x, -1.15, k)
		if left_arm:
			left_arm.rotation.x = lerpf(left_arm.rotation.x, -0.35, k)
		if right_arm:
			right_arm.rotation.x = lerpf(right_arm.rotation.x, -0.35, k)
		return
	if left_arm:
		left_arm.rotation.x = lerpf(left_arm.rotation.x, s, k)
	if right_arm:
		## Shown only when sheathed — and not while that hand is on the bowstring.
		right_arm.visible = sheath_t >= 0.5 and not (current_weapon == "bow" and (drawing or bow_release > 0.0))
		right_arm.rotation.x = lerpf(right_arm.rotation.x, -s, k)
	## Legs stride on the same beat, opposite their arm (left arm + right leg
	## forward together — an actual walk when you look down).
	for i in range(leg_pivots.size()):
		var lph := PI if i == 0 else 0.0
		leg_pivots[i].rotation.x = lerpf(leg_pivots[i].rotation.x, sin(gait_phase + lph) * 0.5 * gait_amount, k)


func get_waist_point() -> Vector3:
	## World position of your left waist / hand, where loot flies to.
	return to_global(Vector3(-0.30, 1.0, 0.12))


func collect_pickup(pickup_kind: String, amount: int, payload := "") -> void:
	if pickup_kind == "coin":
		var g := maxi(1, roundi(float(amount) * stats.gold_mult()))  ## CHA: richer finds
		gold += g
		_push_gain("coin", g)
	elif pickup_kind == "sword":
		## A rare material-sword drop — payload carries the material id.
		var mat_id := payload if payload != "" else "iron"
		_give_sword(mat_id, amount)
		_push_gain(Materials.sword_name(mat_id), amount)
	elif pickup_kind == "ore":
		## Mined ore. The FIRST chunk of a new metal is struck into a blade on
		## the spot (the unlock moment); spares stack for the smithing loop later.
		var mat_id := payload if payload != "" else "iron"
		var ore_name := "%s Ore" % Materials.display_name(mat_id)
		if not _owns_sword_of(mat_id):
			_give_sword(mat_id, 1)
			_add_log_msg("New metal! %s forged — click it in the Inventory" % Materials.sword_name(mat_id), Color(1.0, 0.85, 0.35))
			_push_gain(Materials.sword_name(mat_id), 1)
		else:
			_give_item(ore_name, amount, 2.0)  ## raw rock is heavy
			_push_gain(ore_name, amount)
	elif pickup_kind == "arrow":
		_give_item("Arrow", amount)
		_push_gain("Arrow", amount)
	elif pickup_kind == "xp":
		_record_progress("essence_drinker", 1)
		var gained := maxi(1, roundi(float(amount) * stats.xp_mult()))  ## WIS: learn faster
		_push_gain("xp", gained)
		if level >= PlayerStats.MAX_LEVEL:
			xp = _xp_needed()  ## capped: the bar just stays full
			return
		xp += gained
		while xp >= _xp_needed() and level < PlayerStats.MAX_LEVEL:
			xp -= _xp_needed()
			level += 1
			var got := stats.on_level_up()
			_add_log_msg("Level %d!  +%d stat points (Tab)" % [level, got], Color(1.0, 0.9, 0.4))
		if level >= PlayerStats.MAX_LEVEL:
			xp = _xp_needed()
	else:
		_add_log_msg("+%d %s" % [amount, pickup_kind], Color(0.9, 0.9, 1.0))


func _xp_needed() -> int:
	return stats.xp_needed(level)


func _xp_progress() -> float:
	return clampf(float(xp) / float(_xp_needed()), 0.0, 1.0)


func _refresh_derived(fill := false) -> void:
	## Pull the numbers the sheet drives. Raising CON tops the pools up by the
	## gained amount (a fresh point should feel immediate); nothing else heals.
	var old_hp := max_health
	var old_st := max_stamina
	max_health = stats.max_health()
	max_stamina = stats.max_stamina()
	stamina_regen = stats.stamina_regen()
	base_damage = stats.damage()
	if fill:
		health = max_health
		stamina = max_stamina
	else:
		health = minf(health + maxf(max_health - old_hp, 0.0), max_health)
		stamina = minf(stamina + maxf(max_stamina - old_st, 0.0), max_stamina)


func _record_progress(id: String, amount := 1) -> void:
	## Feed a progression tree; toast any tier that pays out. The reward already
	## went into the linked stat (or the banked pool if that stat is capped).
	var done := stats.record(id, amount)
	if done.is_empty():
		return
	for d: Dictionary in done:
		var stat_name := String(PlayerStats.STAT_NAMES[String(d.stat)])
		if bool(d.overflow):
			_add_log_msg("%s — +%d point (%s capped)" % [String(d.name), int(d.points), stat_name], Color(1.0, 0.78, 0.30))
		else:
			_add_log_msg("%s — +%d %s" % [String(d.name), int(d.points), stat_name], Color(1.0, 0.78, 0.30))
	_refresh_derived()
	if menu_open == "tab":
		_refresh_tab_pages()


func _try_attack() -> void:
	## Being stunned cancels your offense too — no swinging while hit-stunned.
	if current_weapon != "sword" or kd_phase != "" or climbing:
		return
	var cost := ATTACK_STAMINA * stats.stamina_cost_mult()  ## DEX: cheaper swings
	if attacking or stamina < cost or blocking or hitstun_timer > 0.0:
		return
	## Remember where the sword is right now — the swing blends out of it.
	_attack_start_rot = viewmodel.rotation_degrees
	_attack_start_pos = viewmodel.position
	draw_attack = false
	if mount != null:
		## Saddle sweeps: flat cuts past the horse's neck, left and right. Look
		## clearly to one side and the blade favors it; look ahead and the
		## sides alternate like a rhythm.
		var rel := wrapf(rotation.y - mount.rotation.y, -PI, PI)
		if rel > 0.35:
			mounted_side = 0
		elif rel < -0.35:
			mounted_side = 1
		else:
			mounted_side = 1 - mounted_side
		mounted_swing = true
		sheathed = false  ## the sweep draws the blade if it was riding the hip
		combo_index = 1  ## no finishers from the saddle — the horse is the finisher
		since_last_attack = 0.0
		attacking = true
		swing_t = 0.0
		has_hit = false
		stamina -= cost
		stamina_delay = STAMINA_DELAY
		combat_timer = 0.0
		return
	mounted_swing = false
	if sheathed or sheath_t > 0.0:
		## Draw-from-sheath: pull the blade from the hip and slash in one motion.
		sheathed = false
		sheath_t = 0.0
		draw_attack = true
		combo_index = 1  ## the draw slash counts as the first hit
	else:
		if since_last_attack > COMBO_RESET:
			combo_index = 0  ## paused too long -> restart the streak
		combo_index = (combo_index % 3) + 1
	since_last_attack = 0.0
	attacking = true
	swing_t = 0.0
	has_hit = false
	stamina -= cost
	stamina_delay = STAMINA_DELAY
	combat_timer = 0.0  ## swinging counts as combat (delays regen)


## Keyposes per combo step: [chamber, impact, follow-through], each [rot, pos].
## A real cut has three beats — coil back, whip THROUGH the target, then the
## blade's weight carries past and settles. Damage lands at the impact pose.
const SWING_KEYS := [
	[  ## 1: high diagonal cut — chambered over the right shoulder, ripped down-left
		[Vector3(-28.0, 62.0, 18.0), Vector3(0.10, 0.06, 0.06)],
		[Vector3(6.0, -12.0, -4.0), Vector3(-0.02, -0.02, -0.16)],
		[Vector3(26.0, -58.0, -14.0), Vector3(-0.10, -0.08, -0.06)],
	],
	[  ## 2: rising back-cut out of 1's finish — low-left whipped up to high-right
		[Vector3(24.0, -60.0, -16.0), Vector3(-0.08, -0.06, 0.04)],
		[Vector3(-2.0, 8.0, 2.0), Vector3(0.0, 0.0, -0.15)],
		[Vector3(-20.0, 54.0, 12.0), Vector3(0.08, 0.04, -0.04)],
	],
	[  ## 3: overhead chop — chambered high, driven down-forward with the lunge
		[Vector3(-72.0, 6.0, 2.0), Vector3(0.02, 0.10, 0.10)],
		[Vector3(40.0, -4.0, 0.0), Vector3(0.0, -0.04, -0.20)],
		[Vector3(66.0, -8.0, -4.0), Vector3(-0.02, -0.10, -0.10)],
	],
]


## Saddle sweeps: two flat, whipping cuts past the horse's neck — the LEFT
## sweep (forehand across the body) and the RIGHT (the backhand). Same
## three-beat anatomy as the ground combo.
const MOUNTED_KEYS := [
	[  ## left sweep: chambered high over the right shoulder, dragged flat left
		[Vector3(-18.0, 58.0, 16.0), Vector3(0.12, 0.03, 0.05)],
		[Vector3(4.0, -16.0, -5.0), Vector3(-0.04, -0.05, -0.17)],
		[Vector3(16.0, -74.0, -15.0), Vector3(-0.15, -0.09, -0.03)],
	],
	[  ## right sweep: low over the left knee, whipped out and away to the right
		[Vector3(-16.0, -52.0, -12.0), Vector3(-0.11, 0.02, 0.05)],
		[Vector3(4.0, 22.0, 6.0), Vector3(0.05, -0.05, -0.17)],
		[Vector3(15.0, 80.0, 14.0), Vector3(0.16, -0.07, -0.03)],
	],
]


func _swing_pose(step: int, p: float) -> Array:
	return _pose_keys(SWING_KEYS[clampi(step - 1, 0, 2)], p)


func _mounted_pose(side: int, p: float) -> Array:
	return _pose_keys(MOUNTED_KEYS[clampi(side, 0, 1)], p)


func _pose_keys(keys: Array, p: float) -> Array:
	## Chamber (ease back) -> whip (accelerating, fastest AT the impact) ->
	## follow-through (heavy deceleration). Returns [rot_offset, pos_offset].
	var cham_r: Vector3 = keys[0][0]
	var cham_p: Vector3 = keys[0][1]
	var imp_r: Vector3 = keys[1][0]
	var imp_p: Vector3 = keys[1][1]
	var fol_r: Vector3 = keys[2][0]
	var fol_p: Vector3 = keys[2][1]
	if p < 0.24:
		var u := p / 0.24
		u = 1.0 - (1.0 - u) * (1.0 - u)             ## ease OUT into the chamber
		return [Vector3.ZERO.lerp(cham_r, u), Vector3.ZERO.lerp(cham_p, u)]
	elif p < 0.52:
		var u := (p - 0.24) / 0.28
		u = u * u                                    ## the whip — screaming at impact
		return [cham_r.lerp(imp_r, u), cham_p.lerp(imp_p, u)]
	var u := (p - 0.52) / 0.48
	u = 1.0 - pow(1.0 - u, 3.0)                      ## weight carries past, settles
	return [imp_r.lerp(fol_r, u), imp_p.lerp(fol_p, u)]


func _draw_pose(p: float) -> Array:
	## Draw-from-sheath: the pull from the hip IS the chamber — then whip
	## up-across the body and follow through to the left.
	var start_r := Vector3(45.0, 62.0, 28.0)
	var start_p := Vector3(0.10, -0.26, 0.12)
	var imp_r := Vector3(-4.0, -6.0, -2.0)
	var imp_p := Vector3(0.0, 0.0, -0.14)
	var fol_r := Vector3(-24.0, -48.0, -12.0)
	var fol_p := Vector3(-0.06, 0.04, -0.04)
	if p < 0.52:
		var u := p / 0.52
		u = u * u                                    ## accelerating out of the sheath
		return [start_r.lerp(imp_r, u), start_p.lerp(imp_p, u)]
	var u := (p - 0.52) / 0.48
	u = 1.0 - pow(1.0 - u, 3.0)
	return [imp_r.lerp(fol_r, u), imp_p.lerp(fol_p, u)]


func _update_viewmodel(delta: float) -> void:
	## Sheathing takes priority over everything else.
	var target_s := 1.0 if sheathed else 0.0
	if sheath_t < target_s:
		sheath_t = minf(sheath_t + delta / SHEATH_TIME, target_s)
	elif sheath_t > target_s:
		sheath_t = maxf(sheath_t - delta / SHEATH_TIME, target_s)
	viewmodel.visible = sheath_t < 0.5
	hip_sword.visible = sheath_t >= 0.5

	if sheath_t > 0.0:
		viewmodel.rotation_degrees = vm_ready_rot + Vector3(75.0, -25.0, 0.0) * sheath_t
		viewmodel.position = vm_ready_pos + Vector3(0.0, -0.35, 0.12) * sheath_t
		return

	if attacking:
		swing_t += delta
		## DEX shortens the whole swing (and the hit lands proportionally sooner).
		var st := SWING_TIME * stats.swing_mult()
		var p := clampf(swing_t / st, 0.0, 1.0)
		var pr: Array
		if draw_attack:
			pr = _draw_pose(p)
		elif mounted_swing:
			pr = _mounted_pose(mounted_side, p)
		else:
			pr = _swing_pose(combo_index, p)
		var srot: Vector3 = pr[0]
		var spos: Vector3 = pr[1]
		## The arcs were authored on the flat combat base; the sword now RESTS
		## point-up, so melt from wherever it was into the arc over the first
		## fifth of the swing — the raise becomes part of the attack.
		var blend := clampf(p / 0.22, 0.0, 1.0)
		blend = blend * blend * (3.0 - 2.0 * blend)
		viewmodel.rotation_degrees = _attack_start_rot.lerp(vm_combat_rot + srot, blend)
		viewmodel.position = _attack_start_pos.lerp(vm_combat_pos + spos, blend)
		if swing_t >= HIT_AT * stats.swing_mult() and not has_hit:
			has_hit = true
			_do_melee_hit()
		if swing_t >= st:
			attacking = false
			draw_attack = false
			mounted_swing = false
		return

	## Block: hold the sword across the screen as a guard until you let go.
	if blocking:
		if block_impact > 0.0:
			block_impact = maxf(0.0, block_impact - delta)
		var brot := Vector3(6.0, 88.0, 8.0)
		var bpos := Vector3(0.06, -0.04, -0.42 + block_impact * 0.9)  ## recoils toward you on impact
		viewmodel.rotation_degrees = viewmodel.rotation_degrees.lerp(brot, delta * 16.0)
		viewmodel.position = viewmodel.position.lerp(bpos, delta * 16.0)
		return

	## Idle: the held sword rides the shared stride, counter-phase to the head
	## (like a real carry), with a slow breathing sway when standing still.
	bob_t += delta * 2.1
	var bob := Vector3(
		sin(gait_phase + PI) * 0.017 * gait_amount + sin(bob_t) * 0.0018,
		absf(sin(gait_phase + PI)) * 0.014 * gait_amount + absf(sin(bob_t * 0.8)) * 0.0024,
		0.0)
	var roll := sin(gait_phase + PI) * 1.1 * gait_amount
	viewmodel.position = viewmodel.position.lerp(vm_ready_pos + bob, delta * 10.0)
	viewmodel.rotation_degrees = viewmodel.rotation_degrees.lerp(vm_ready_rot + Vector3(0.0, 0.0, roll), delta * 10.0)


func _do_melee_hit() -> void:
	var mat_id := _sword_material_id()
	var forward := -camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var combo_mult := 1.0
	if combo_index == 3 and not mounted_swing:
		combo_mult = 1.6  ## finisher hits harder
	var landed := false
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node3D):
			continue
		if e == mount:
			continue  ## the horse under you can NEVER be hit by your own swings
		var to_e: Vector3 = e.global_position - global_position
		to_e.y = 0.0
		var dist := to_e.length()
		if dist <= attack_range and forward.dot(to_e.normalized()) > 0.35:
			if e.has_method("take_damage") and _swing_reaches(e):
				## Material matchup + situational element bonus vs this creature's
				## families (silver shreds the undead, steel merely dents them...)
				var fams: Array = e.families if "families" in e else []
				var mat_mult := Materials.matchup_mult(mat_id, fams) * Materials.element_mult(mat_id, fams)
				e.take_damage(base_damage * combo_mult * mat_mult)  ## base_damage carries STR
				landed = true
				## The bestiary learns by DOING: landing this metal on this
				## creature proves the matchup and reveals it on the page.
				_bestiary_prove(e, mat_id)
				## (kills are counted in on_mob_slain, fed from Enemy._die)
	if landed and combo_index == 3:
		_record_progress("combo_master", 1)
	if not landed and vein_hint_cd <= 0.0:
		## Swung at rock? Nudge toward the right tool (once in a while).
		for v in get_tree().get_nodes_in_group("ore_veins"):
			if (v as Node3D).global_position.distance_to(global_position) <= attack_range + 0.8:
				_add_log_msg("The blade skates off the ore — a pickaxe (3) would bite", Color(0.8, 0.8, 0.8))
				vein_hint_cd = 6.0
				break


## ===================== Pickaxe (weapon 3): mining =========================


func _spawn_mine_debris(point: Vector3, normal: Vector3) -> void:
	## Rocks fall when you mine: a few chips burst from every bite, and biting
	## a CEILING (normal pointing down) shakes loose a big slab from overhead.
	var parent := get_parent()
	var n := randi_range(2, 4)
	for _i in range(n):
		var v := normal * randf_range(1.2, 2.6) \
			+ Vector3(randf_range(-1.0, 1.0), randf_range(0.4, 1.4), randf_range(-1.0, 1.0))
		parent.add_child(RockDebris.make(point + normal * 0.12, v))
	if normal.y < -0.35:
		parent.add_child(RockDebris.make(point + Vector3(0, -0.15, 0),
			Vector3(randf_range(-0.4, 0.4), -0.5, randf_range(-0.4, 0.4)), true))


func _try_pick_swing() -> void:
	if pick_swinging or hitstun_timer > 0.0 or blocking or climbing:
		return
	var cost := PICK_STAMINA * stats.stamina_cost_mult()
	if stamina < cost:
		return
	stamina -= cost
	stamina_delay = STAMINA_DELAY
	pick_swinging = true
	pick_t = 0.0
	pick_hit_done = false


func _update_pickaxe(delta: float) -> void:
	if pick_vm == null:
		return
	pick_vm.visible = current_weapon == "pickaxe"
	if vein_hint_cd > 0.0:
		vein_hint_cd -= delta
	if not pick_vm.visible:
		pick_swinging = false
		pick_t = 0.0
		return

	if pick_swinging:
		pick_t += delta * stats.swing_mult()  ## DEX chops a touch faster
		var u := clampf(pick_t / PICK_TIME, 0.0, 1.0)
		if not pick_hit_done and u >= PICK_HIT_AT:
			pick_hit_done = true
			_do_pick_hit()
		## Raise over the shoulder, drive down into the bite, ease back up.
		## The damage fires at PICK_HIT_AT — right as the spike visually lands
		## (the drive below finishes at ~the same fraction), not at the top.
		var ang: float
		if u < PICK_WINDUP:
			var w := u / PICK_WINDUP
			ang = lerpf(0.0, -46.0, w * w)              ## windup: hoist it up
		else:
			var w := (u - PICK_WINDUP) / (1.0 - PICK_WINDUP)
			var drive := clampf(w / 0.30, 0.0, 1.0)      ## fast drive down...
			var back := clampf((w - 0.30) / 0.70, 0.0, 1.0)
			ang = lerpf(-46.0, 58.0, 1.0 - pow(1.0 - drive, 3.0)) - back * 58.0
		pick_vm.rotation_degrees = PICK_REST_ROT + Vector3(ang, 0, 0)
		pick_vm.position = PICK_REST_POS + Vector3(0, 0.10 * absf(ang) / 58.0 * signf(-ang), -0.06 * absf(ang) / 58.0)
		if pick_t >= PICK_TIME:
			pick_swinging = false
			pick_t = 0.0
	else:
		## At rest: breathe with the shared gait, like the other held things.
		var bob := Vector3(
			sin(gait_phase + PI) * 0.015 * gait_amount,
			absf(sin(gait_phase + PI)) * 0.013 * gait_amount + sin(bob_t) * 0.0018,
			0.0)
		pick_vm.position = pick_vm.position.lerp(PICK_REST_POS + bob, delta * 10.0)
		pick_vm.rotation_degrees = pick_vm.rotation_degrees.lerp(
			PICK_REST_ROT + Vector3(0, 0, sin(gait_phase + PI) * 1.0 * gait_amount), delta * 10.0)


## ======================== War Axe (weapon 4) ==============================


func _try_axe_swing() -> void:
	if axe_swinging or hitstun_timer > 0.0 or blocking or climbing or kd_phase != "":
		return
	var cost := AXE_STAMINA * stats.stamina_cost_mult()
	if stamina < cost:
		return
	stamina -= cost
	stamina_delay = STAMINA_DELAY
	combat_timer = 0.0
	since_last_attack = 0.0
	axe_swinging = true
	axe_t = 0.0
	axe_hit_done = false
	axe_side = 1 - axe_side  ## chop, cleave, chop, cleave...


func _update_axe(delta: float) -> void:
	if axe_vm == null:
		return
	axe_vm.visible = current_weapon == "axe"
	if not axe_vm.visible:
		axe_swinging = false
		axe_t = 0.0
		return

	if axe_swinging:
		axe_t += delta
		var at := AXE_TIME * stats.swing_mult()  ## DEX quickens the whole swing
		var u := clampf(axe_t / at, 0.0, 1.0)
		if not axe_hit_done and u >= AXE_HIT_AT:
			axe_hit_done = true
			_do_axe_hit()
		## Two authored swings, alternating. Each: HAUL back (slow, heavy),
		## WHIP through the arc (damage lands mid-whip), ease back to rest.
		var wrot: Vector3
		var wpos: Vector3
		var srot: Vector3
		var spos: Vector3
		if axe_side == 0:
			## Overhead chop: up over the shoulder, down through the skull line.
			wrot = Vector3(-78.0, 10.0, -14.0)
			wpos = Vector3(0.02, 0.16, 0.10)
			srot = Vector3(58.0, -6.0, 4.0)
			spos = Vector3(-0.04, -0.18, -0.16)
		else:
			## Horizontal cleave: hauled across the right shoulder, swept flat
			## right-to-left through the ribs.
			wrot = Vector3(-18.0, 62.0, -66.0)
			wpos = Vector3(0.16, 0.02, 0.06)
			srot = Vector3(-6.0, -58.0, -74.0)
			spos = Vector3(-0.22, -0.06, -0.12)
		if u < AXE_WINDUP:
			var w := u / AXE_WINDUP
			w = w * w  ## heavy thing, slow to start moving
			axe_vm.rotation_degrees = AXE_REST_ROT + wrot * w
			axe_vm.position = AXE_REST_POS + wpos * w
		else:
			var w := (u - AXE_WINDUP) / (1.0 - AXE_WINDUP)
			var drive := clampf(w / 0.34, 0.0, 1.0)
			drive = 1.0 - pow(1.0 - drive, 3.0)  ## whips out of the windup
			var back := clampf((w - 0.42) / 0.58, 0.0, 1.0)
			back = back * back * (3.0 - 2.0 * back)
			var swing_rot := (AXE_REST_ROT + wrot).lerp(AXE_REST_ROT + srot, drive)
			var swing_pos := AXE_REST_POS + wpos.lerp(spos, drive)
			axe_vm.rotation_degrees = swing_rot.lerp(AXE_REST_ROT, back)
			axe_vm.position = swing_pos.lerp(AXE_REST_POS, back)
		if axe_t >= at:
			axe_swinging = false
			axe_t = 0.0
	else:
		## At rest: breathe on the shared gait like everything else held.
		var bob := Vector3(
			sin(gait_phase + PI) * 0.016 * gait_amount,
			absf(sin(gait_phase + PI)) * 0.014 * gait_amount + sin(bob_t) * 0.002,
			0.0)
		axe_vm.position = axe_vm.position.lerp(AXE_REST_POS + bob, delta * 10.0)
		axe_vm.rotation_degrees = axe_vm.rotation_degrees.lerp(
			AXE_REST_ROT + Vector3(0, 0, sin(gait_phase + PI) * 1.2 * gait_amount), delta * 10.0)


func _do_axe_hit() -> void:
	## Heavy iron, no finesse: everything in the arc takes the same big hit.
	## No material matchups (yet) — see the TODO(design) on the constants.
	var forward := -camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node3D):
			continue
		if e == mount:
			continue
		var to_e: Vector3 = e.global_position - global_position
		to_e.y = 0.0
		if to_e.length() <= AXE_RANGE and forward.dot(to_e.normalized()) > 0.30:
			if e.has_method("take_damage") and _swing_reaches(e):
				e.take_damage(base_damage * AXE_DMG_MULT)
				cam_shake = maxf(cam_shake, 0.06)  ## the bite of contact


func _do_pick_hit() -> void:
	combat_timer = 0.0
	var forward := -camera.global_transform.basis.z
	## Ore first: bite the nearest vein in front of you.
	var best: Node3D = null
	var best_d := PICK_RANGE + 1.0
	for v in get_tree().get_nodes_in_group("ore_veins"):
		if not (v is Node3D):
			continue
		var to_v: Vector3 = (v as Node3D).global_position + Vector3(0, 0.6, 0) - camera.global_position
		var d := to_v.length()
		if d <= PICK_RANGE and forward.dot(to_v.normalized()) > 0.30 and d < best_d:
			best = v
			best_d = d
	if best != null:
		cam_shake = maxf(cam_shake, 0.10)  ## the bite kicks back a little
		if best.has_method("mine_hit"):
			best.mine_hit()
		return
	## Bare cave rock: the pick actually DIGS (Caves 2.0). Each bite scoops a
	## small scoop out of the voxel field — walls, floor, ceiling, even a slow
	## stubborn shaft all the way up to the surface — and the dislodged rock
	## physically falls. Mining the ceiling over your own head drops a slab
	## that HURTS: undercut at an angle like anyone with sense.
	var space := get_world_3d().direct_space_state
	var rq := PhysicsRayQueryParameters3D.create(camera.global_position,
		camera.global_position + forward * PICK_RANGE)
	rq.exclude = [get_rid()]
	var rhit := space.intersect_ray(rq)
	if not rhit.is_empty() and (rhit.collider as Node).is_in_group("cave_rock"):
		var region := (rhit.collider as Node).get_meta("cave_region") as CaveRegion
		if region != null and region.carve_bite((rhit.position as Vector3) + forward * 0.22):
			cam_shake = maxf(cam_shake, 0.12)
			_spawn_mine_debris(rhit.position as Vector3, rhit.normal as Vector3)
			return
	## No rock — it's a poor weapon, but it IS a heavy spike of iron.
	var fwd_flat := forward
	fwd_flat.y = 0.0
	fwd_flat = fwd_flat.normalized()
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node3D):
			continue
		var to_e: Vector3 = e.global_position - global_position
		to_e.y = 0.0
		if to_e.length() <= PICK_RANGE * 0.8 and fwd_flat.dot(to_e.normalized()) > 0.45:
			if e.has_method("take_damage") and _swing_reaches(e):
				e.take_damage(base_damage * 0.5)  ## blunt, slow, no matchups
				break  ## a tool chops ONE thing, not an arc


## ========================= Bow (weapon 2) =================================


func _select_weapon(w: String) -> void:
	if current_weapon == w:
		return
	if mount != null and w != "sword":
		_add_log_msg("Not from the saddle — the sword or nothing", Color(0.8, 0.8, 0.8))
		return
	current_weapon = w
	drawing = false
	bow_draw = 0.0
	attacking = false
	draw_attack = false
	pick_swinging = false
	pick_t = 0.0
	axe_swinging = false
	axe_t = 0.0
	if w == "bow":
		sheathed = true   ## the sword rides the hip while the bow is out
		_add_log_msg("Weapon: Bow — hold LMB, release to loose", Color(0.85, 0.9, 1.0))
	elif w == "pickaxe":
		sheathed = true   ## sword to the hip; the tool takes the right hand
		_add_log_msg("Tool: Pickaxe — chop ore veins for new metal", Color(0.85, 0.9, 1.0))
	elif w == "axe":
		sheathed = true   ## sword to the hip; the cleaver fills the right hand
		_add_log_msg("Weapon: War Axe — heavy, honest iron", Color(0.85, 0.9, 1.0))
	else:
		sheathed = false  ## pulls the blade back out
		_add_log_msg("Weapon: Sword", Color(0.85, 0.9, 1.0))


func _bow_start_draw() -> void:
	if drawing or hitstun_timer > 0.0 or climbing:
		return
	if _arrow_count() <= 0:
		_add_log_msg("No arrows", Color(0.9, 0.75, 0.4))
		return
	var cost := BOW_STAMINA * stats.stamina_cost_mult()  ## DEX: cheaper draws
	if stamina < cost:
		return
	stamina -= cost
	stamina_delay = STAMINA_DELAY
	combat_timer = 0.0
	drawing = true
	bow_draw = 0.0


func _bow_loose() -> void:
	if not drawing:
		return
	drawing = false
	if bow_draw < 0.2:
		bow_draw = 0.0
		return  ## barely pulled — the arrow just sags off the string
	_consume_arrow()
	var fwd := -camera.global_transform.basis.z
	var a := Arrow.new()
	## Damage rides the draw (35%..100%) on top of STR's melee scaling.
	a.damage = stats.damage() * 1.35 * (0.35 + 0.65 * bow_draw)
	get_parent().add_child(a)
	a.global_position = camera.global_position + fwd * 0.55 + camera.global_transform.basis.x * -0.08
	a.velocity = fwd * (26.0 + 14.0 * bow_draw)
	bow_release = 0.10
	bow_draw = 0.0
	combat_timer = 0.0


func _update_bow(delta: float) -> void:
	if bow_vm == null:
		return
	bow_vm.visible = current_weapon == "bow"
	if not bow_vm.visible:
		drawing = false
		bow_draw = 0.0
		return
	if hitstun_timer > 0.0 and drawing:
		drawing = false  ## the hit knocks the draw loose
		bow_draw = 0.0
	if drawing:
		bow_draw = minf(1.0, bow_draw + delta / (BOW_DRAW_TIME * stats.swing_mult()))
		combat_timer = 0.0  ## holding a draw is combat — no healing mid-aim
	bow_release = maxf(0.0, bow_release - delta)

	## Pose: low carry at rest, raised toward center while drawing, with the
	## same stride-sway as everything else and a small kick when the string snaps.
	var d := bow_draw if drawing else 0.0
	var raise := d
	if bow_release > 0.0:
		raise = maxf(raise, 0.8 * (bow_release / 0.10))
	var tpos := Vector3(-0.26, -0.36, -0.52).lerp(Vector3(-0.06, -0.23, -0.46), raise)
	var trot := Vector3(-6.0, 24.0, -14.0).lerp(Vector3(0.0, 7.0, -3.0), raise)
	tpos += Vector3(
		sin(gait_phase + PI * 0.4) * 0.012 * gait_amount,
		absf(sin(gait_phase + PI * 0.4)) * 0.011 * gait_amount, 0.0)
	if bow_release > 0.0:
		trot.x += -7.0 * (bow_release / 0.10)
	bow_vm.position = bow_vm.position.lerp(tpos, clampf(delta * 12.0, 0.0, 1.0))
	bow_vm.rotation_degrees = bow_vm.rotation_degrees.lerp(trot, clampf(delta * 12.0, 0.0, 1.0))

	## The nocked arrow + string hand slide back with the pull.
	if bow_arrow_vm:
		bow_arrow_vm.visible = drawing and _arrow_count() > 0
		bow_arrow_vm.position = Vector3(0.015, 0.0, -0.02 + 0.17 * d)
	if bow_hand_vm:
		bow_hand_vm.visible = drawing or bow_release > 0.0
		var hz := (0.10 + 0.17 * d) if drawing else 0.05
		bow_hand_vm.position = Vector3(0.02, -0.015, hz)


func _arrow_count() -> int:
	for it in inventory:
		if String(it.name) == "Arrow":
			return int(it.count)
	return 0


func _consume_arrow() -> void:
	for it in inventory:
		if String(it.name) == "Arrow":
			it.count = maxi(0, int(it.count) - 1)
			break
	if menu_open == "tab" and tab_page == "inventory":
		_refresh_inventory_ui()


func _give_item(item_name: String, n: int, weight := 0.06) -> void:
	for it in inventory:
		if String(it.name) == item_name:
			it.count = int(it.count) + n
			if menu_open == "tab" and tab_page == "inventory":
				_refresh_inventory_ui()
			return
	inventory.append({"name": item_name, "weight": weight, "count": n, "slot": ""})
	if menu_open == "tab" and tab_page == "inventory":
		_refresh_inventory_ui()


func _swing_reaches(e: Node3D) -> bool:
	## Mirror of the enemies' ghost-hit guard: your blade doesn't cut through
	## cave walls or floors either. Other creatures don't block the swing.
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 1.3, e.global_position + Vector3.UP * 0.7)
	q.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty() or hit.collider == e:
		return true
	return hit.collider is Enemy


## ===================== Climbing (Space near a ledge) =======================


func _try_climb() -> bool:
	## THE MANTLE: find a wall ahead with a standable top within reach, then
	## haul up onto it. Returns false (so Space falls through to a jump) when
	## there's nothing to grab. Works grounded OR mid-air (grab as you fall).
	if climbing or mount != null or kd_phase != "" or hitstun_timer > 0.0:
		return false
	if stamina < 1.0:
		return false  ## utterly winded — no grip left in the fingers
	var fwd := -camera.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.001:
		return false  ## staring straight down a hole — no wall to read
	fwd = fwd.normalized()
	var space := get_world_3d().direct_space_state

	## 1) A face to grab? Probe chest height first, then shin (low lips count).
	var wall_d := -1.0
	for h: float in [1.25, 0.5]:
		var from := global_position + Vector3.UP * h
		var q := PhysicsRayQueryParameters3D.create(from, from + fwd * 1.45)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and (hit.normal as Vector3).y < 0.55:
			wall_d = ((hit.position as Vector3) - from).dot(fwd)
			break
	if wall_d < 0.0:
		return false

	## 2) Where's its top? Drop a ray from above, just past the wall face.
	var over := global_position + fwd * (wall_d + 0.55) + Vector3.UP * (CLIMB_MAX_H + 0.75)
	var qd := PhysicsRayQueryParameters3D.create(over, over + Vector3.DOWN * (CLIMB_MAX_H + 0.95))
	qd.exclude = [get_rid()]
	var top := space.intersect_ray(qd)
	if top.is_empty():
		return false
	var rise := (top.position as Vector3).y - global_position.y
	if rise < CLIMB_MIN_H or rise > CLIMB_MAX_H or (top.normal as Vector3).y < 0.5:
		return false  ## too low to bother / too high to reach / not standable

	## 3) Headroom on the lip — never mantle your skull into a ceiling.
	var land := (top.position as Vector3) + fwd * 0.22
	var qh := PhysicsRayQueryParameters3D.create(land + Vector3.UP * 0.25, land + Vector3.UP * 1.75)
	qh.exclude = [get_rid()]
	if not space.intersect_ray(qh).is_empty():
		return false

	## Grab it.
	stamina = maxf(0.0, stamina - CLIMB_STAMINA * stats.stamina_cost_mult())
	stamina_delay = STAMINA_DELAY
	climbing = true
	climb_t = 0.0
	_fall_speed = 0.0  ## the grab kills the fall — no phantom fall damage on top-out
	climb_from = global_position
	climb_to = land + Vector3.UP * 0.02
	climb_dur = CLIMB_TIME + clampf((rise - 1.0) * 0.16, 0.0, 0.35)
	velocity = Vector3.ZERO
	blocking = false
	drawing = false
	bow_draw = 0.0
	attacking = false
	draw_attack = false
	pick_swinging = false
	return true


func _update_climb(delta: float) -> void:
	## The mantle animation: RISE first (arms doing the work), then the haul
	## forward over the lip — two overlapping eased phases. Hands plant low,
	## the camera dips into the pull and pops level at the top-out.
	climb_t += delta / climb_dur
	var t := clampf(climb_t, 0.0, 1.0)
	var uv := minf(t / 0.62, 1.0)
	uv = uv * uv * (3.0 - 2.0 * uv)
	var uh := clampf((t - 0.28) / 0.72, 0.0, 1.0)
	uh = uh * uh * (3.0 - 2.0 * uh)
	global_position = Vector3(
		lerpf(climb_from.x, climb_to.x, uh),
		lerpf(climb_from.y, climb_to.y, uv),
		lerpf(climb_from.z, climb_to.z, uh))
	velocity = Vector3.ZERO
	camera.position.y = -sin(t * PI) * 0.16  ## the dip of a real pull-up
	if viewmodel:  ## sword hand plants forward-low, like bracing on the rock
		viewmodel.position = viewmodel.position.lerp(vm_ready_pos + Vector3(-0.05, -0.20, -0.10), delta * 14.0)
		viewmodel.rotation_degrees = viewmodel.rotation_degrees.lerp(vm_ready_rot + Vector3(40.0, 8.0, -12.0), delta * 14.0)
	if offhand_node and offhand_node.visible:
		offhand_node.position = offhand_node.position.lerp(OH_REST_POS + Vector3(0.05, -0.18, -0.06), delta * 14.0)
	if climb_t >= 1.0:
		climbing = false
		camera.position.y = 0.0
		cam_shake = maxf(cam_shake, 0.05)  ## soft top-out thud
		var push := (climb_to - climb_from)
		push.y = 0.0
		if push.length_squared() > 0.001:
			velocity = push.normalized() * 1.6  ## a step onto the ledge, not a stop


func _try_dash() -> void:
	if climbing:
		return  ## both hands are full of cliff
	var cost := DASH_STAMINA * stats.stamina_cost_mult()  ## DEX: cheaper dashes
	if dash_timer > 0.0 or stamina < cost:
		return
	dash_timer = DASH_TIME
	invuln_timer = 0.12
	stamina -= cost
	stamina_delay = STAMINA_DELAY


func take_damage(amount: float, from_pos := Vector3.INF, strong := false, lunge_throw := Vector3.INF, attacker: Node = null) -> void:
	if invuln_timer > 0.0:
		## Untouchable: dashed clean through a special that would have landed.
		if strong and dash_timer > 0.0 and dodge_cd <= 0.0:
			dodge_cd = 0.5
			_add_log_msg("Dodged!", Color(0.55, 0.95, 1.0))
			_record_progress("untouchable", 1)
		return
	combat_timer = 0.0  ## taking a hit counts as combat (delays regen)

	## Perfect Guard: the block came up in the last instant before impact — a
	## parry. No damage, no stamina, and the attacker staggers open for a
	## counter. Timing beats even guard-breakers.
	if blocking and block_held_time <= PARRY_WINDOW:
		block_held_time = 999.0  ## one parry per raise — hold on and it's a normal block
		block_impact = 0.22
		cam_shake = maxf(cam_shake, 0.12)
		_add_log_msg("Parried!", Color(1.0, 0.95, 0.55))
		if attacker != null and attacker.has_method("on_parried"):
			attacker.on_parried()
		_record_progress("perfect_guard", 1)
		return

	## STR: every hit lands softer. Worn material armor shaves off its share too.
	var dmg := amount * stats.damage_taken_mult() * _armor_mult()
	## A shield negates ALL damage; a bare sword is a poor guard — 70% of the
	## hit still gets through the blade. Want to block properly? Carry the
	## shield, or parry (a perfect block still negates everything).
	var full_block := _offhand_is_shield()
	if blocking and stamina > 0.0:
		if strong:
			## A strong attack still crashes through a raised guard (2s disable +
			## knockback); a shield eats the damage, a bare sword lets 70% through.
			block_broken_timer = 2.0
			blocking = false
			attacking = false
			draw_attack = false
			hitstun_timer = 0.35
			cam_shake = 0.5
			dmg = 0.0 if full_block else dmg * 0.7
			_add_log_msg("Shield holds!" if full_block else "Guard broken!", Color(1.0, 0.35, 0.25))
			## Blocking keeps your feet planted: a shove, never a throw.
			_knockback_from(from_pos, 4.5)
		else:
			dmg = 0.0 if full_block else dmg * 0.7
			stamina = maxf(0.0, stamina - amount * 0.4)
			stamina_delay = STAMINA_DELAY
			block_impact = 0.14  ## guard absorbs it — small recoil, stay on your feet
	else:
		## Unblocked: thrown out of whatever you were doing, with knockback.
		attacking = false
		draw_attack = false
		if strong:
			cam_shake = 0.35
		## A lunge/charge tosses you — how far depends on WHO hit you: the throw
		## vector's length carries the mob's strong_throw_power (boar = a shove
		## off its path, ogre = a real hurl). Only lands when you're NOT blocking.
		if lunge_throw != Vector3.INF and lunge_throw.length() > 0.01:
			hitstun_timer = 0.5
			var power := lunge_throw.length()
			var t := lunge_throw.normalized()
			velocity.x = t.x * power
			velocity.z = t.z * power
			velocity.y = minf(3.2, 1.2 + power * 0.25)
		else:
			hitstun_timer = 0.30
			_knockback_from(from_pos, 6.0)
	health -= dmg
	## Death's Door: an enemy just put you at the brink. Survive and recover
	## past 60% to score it (recovering takes real time out of combat).
	if health > 0.0 and health <= max_health * 0.15 and not near_death_active and near_death_cd <= 0.0:
		near_death_active = true
	if health <= 0.0:
		_die()


func _knockback_from(from_pos: Vector3, force: float) -> void:
	if from_pos == Vector3.INF:
		return
	var away := global_position - from_pos
	away.y = 0.0
	if away.length() > 0.01:
		away = away.normalized()
		velocity.x = away.x * force
		velocity.z = away.z * force


func _die() -> void:
	print("You died. Respawning...")
	if mount != null:
		_dismount()
	health = max_health
	stamina = max_stamina
	global_position = Vector3(0, 2, 0)
	climbing = false
	_fall_speed = 0.0
	## Respawn cancels everything in flight: no lingering knockback or queued hits.
	velocity = Vector3.ZERO
	hitstun_timer = 0.0
	block_broken_timer = 0.0
	cam_shake = 0.0
	## Death also stands you back up (the hard way).
	kd_phase = ""
	kd_t = 0.0
	camera.rotation_degrees.z = 0.0
	_update_head_offset()
	near_death_active = false  ## dying is not "coming back from near death"
	invuln_timer = 2.0   ## brief grace so incoming damage right after respawn is ignored


func _update_hud(delta: float) -> void:
	## Dropped-item gaze check + the "[E] Pick up" prompt.
	_update_drop_target()
	if pickup_prompt:
		pickup_prompt.visible = _drop_target != null
		if _drop_target != null:
			pickup_prompt.text = "[E]  Pick up %s" % _drop_target.display_name()

	## Fade logic: bars go bright when in use, dim (but never gone) when idle.
	if absf(health - _last_health) > 0.01:
		health_show = 1.8
	if absf(stamina - _last_stamina) > 0.01:
		stam_show = 1.0
	if xp != _last_xp or level != _last_level:
		xp_show = 2.2  ## a little longer — savor the drip
	_last_health = health
	_last_stamina = stamina
	_last_xp = xp
	_last_level = level
	health_show = maxf(0.0, health_show - delta)
	stam_show = maxf(0.0, stam_show - delta)
	xp_show = maxf(0.0, xp_show - delta)

	var vp := get_viewport().get_visible_rect().size
	## CON visibly widens the HP/stamina bars (capped so they never eat the
	## screen); the XP bar keeps its base width.
	var bw := BAR_W * stats.bar_scale()
	var cx := (vp.x - bw) * 0.5
	var cx0 := (vp.x - BAR_W) * 0.5

	if pickup_prompt and pickup_prompt.visible:
		pickup_prompt.position = Vector2((vp.x - pickup_prompt.size.x) * 0.5, vp.y * 0.60)

	## Stack, bottom-centered: stamina (top), health (middle, red), level (bottom).
	if stamina_bar:
		stamina_bar.position = Vector2(cx, vp.y - 66.0)
		(stamina_bar.get_child(0) as ColorRect).size.x = bw  ## dark backing
		stamina_fill.size.x = bw * clampf(stamina / max_stamina, 0.0, 1.0)
		var s_target := 1.0 if (stamina < max_stamina or stam_show > 0.0) else 0.10
		stamina_bar.modulate.a = lerpf(stamina_bar.modulate.a, s_target, delta * 6.0)
	if health_bar:
		health_bar.position = Vector2(cx, vp.y - 48.0)
		(health_bar.get_child(0) as ColorRect).size.x = bw
		health_fill.size.x = bw * clampf(health / max_health, 0.0, 1.0)
		var h_target := 1.0 if (health < max_health or health_show > 0.0) else 0.10
		health_bar.modulate.a = lerpf(health_bar.modulate.a, h_target, delta * 6.0)
	if level_bar:
		level_bar.position = Vector2(cx0, vp.y - 34.0)
		level_fill.size.x = BAR_W * _xp_progress()
		## Same fade as the others: bright while XP trickles in, dim when idle.
		var l_target := 1.0 if xp_show > 0.0 else 0.10
		level_bar.modulate.a = lerpf(level_bar.modulate.a, l_target, delta * 6.0)

	## Keep whichever menu is open centered on screen.
	if menu_open != "":
		var panel := tab_panel
		if menu_open == "spawn":
			panel = spawn_panel
		elif menu_open == "settings":
			panel = settings_panel
		if panel:
			## Menus render MENU_SCALE (67%) bigger — clamped so the largest
			## pages never spill off a small window. floor() keeps text crisp.
			var sc := minf(MENU_SCALE, minf(
				vp.x * 0.97 / maxf(panel.size.x, 1.0),
				vp.y * 0.97 / maxf(panel.size.y, 1.0)))
			panel.scale = Vector2(sc, sc)
			panel.position = ((vp - panel.size * sc) * 0.5).floor()


func _new_log_label() -> Label:
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.size = Vector2(190, 22)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(lbl)
	return lbl


func _push_gain(kind: String, amount: int) -> void:
	## Merge into the newest entry if it's the same kind and still fresh.
	if not log_rows.is_empty():
		var last: Dictionary = log_rows[log_rows.size() - 1]
		if String(last.kind) == kind and float(last.life) > 2.2:
			last.amount = int(last.amount) + amount
			last.life = 3.0
			_refresh_gain_label(last)
			return
	var row := {"label": _new_log_label(), "kind": kind, "amount": amount, "life": 3.0}
	log_rows.append(row)
	_refresh_gain_label(row)


func _refresh_gain_label(row: Dictionary) -> void:
	var lbl := row.label as Label
	if lbl == null or not is_instance_valid(lbl):
		return
	var kind := String(row.kind)
	var amt := int(row.amount)
	if kind == "coin":
		lbl.text = "+%d Gold" % amt
		lbl.modulate = Color(1.0, 0.85, 0.30)
	elif kind == "xp":
		lbl.text = "+%d XP" % amt
		lbl.modulate = Color(0.40, 1.0, 0.55)
	else:
		lbl.text = "+%d %s" % [amt, kind]
		lbl.modulate = Color(1, 1, 1)


func _add_log_msg(text: String, col: Color) -> void:
	var lbl := _new_log_label()
	if lbl != null:
		lbl.text = text
		lbl.modulate = col
	log_rows.append({"label": lbl, "kind": "msg", "amount": 0, "life": 3.0})


func _update_log(delta: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	## Expire old entries (iterate backward for safe removal).
	var i := log_rows.size() - 1
	while i >= 0:
		var row: Dictionary = log_rows[i]
		row.life = float(row.life) - delta
		if float(row.life) <= 0.0:
			var lbl := row.label as Label
			if lbl != null and is_instance_valid(lbl):
				lbl.queue_free()
			log_rows.remove_at(i)
		i -= 1
	## Reposition top-right, ~3/4 up the screen, newest on top.
	var y := vp.y * 0.25
	var j := log_rows.size() - 1
	while j >= 0:
		var row: Dictionary = log_rows[j]
		var lbl := row.label as Label
		if lbl != null and is_instance_valid(lbl):
			lbl.position = Vector2(vp.x - 210.0, y)
			var a := clampf(float(row.life) / 0.6, 0.0, 1.0)
			var m := lbl.modulate
			m.a = a
			lbl.modulate = m
			y += 26.0
		j -= 1


## ============================== Menus =====================================


func _toggle_menu(which: String) -> void:
	if menu_open == which:
		_close_menu()
		return
	menu_open = which
	drawing = false  ## opening a menu eases the bowstring back down
	bow_draw = 0.0
	spawn_panel.visible = which == "spawn"
	tab_panel.visible = which == "tab"
	settings_panel.visible = which == "settings"
	if which == "tab":
		_set_tab_page(tab_page)
	elif which == "settings":
		_refresh_settings_ui()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _open_tab_menu(page: String) -> void:
	## Tab / I: open the big menu on a page — or close it if it's already
	## showing that page (I on the stats page hops to inventory instead).
	if menu_open == "tab" and tab_page == page:
		_close_menu()
		return
	tab_page = page
	if menu_open == "tab":
		_set_tab_page(page)
	else:
		_toggle_menu("tab")


func _close_menu() -> void:
	menu_open = ""
	spawn_panel.visible = false
	tab_panel.visible = false
	settings_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## ========================= Mob spawn menu (M) =============================


func _mob_types() -> Array:
	## The bestiary's canon: one row per creature (wild and saddled horses
	## share the "Horse" page — a horse is a horse).
	return [
		["Boar", Boar], ["Kobold", Kobold], ["Goblin", Goblin], ["Skeleton", Skeleton],
		["Orc", Orc], ["Ogre", Ogre], ["Dark Knight", DarkKnight], ["Horse", Horse],
	]


func _spawn_types() -> Array:
	## The M menu offers both kinds of horse; the bestiary doesn't need to.
	return [
		["Boar", Boar], ["Kobold", Kobold], ["Goblin", Goblin], ["Skeleton", Skeleton],
		["Orc", Orc], ["Ogre", Ogre], ["Dark Knight", DarkKnight],
		["Horse (wild)", Horse], ["Horse (saddled)", SaddledHorse],
	]


func _build_spawn_menu() -> void:
	spawn_panel = PanelContainer.new()
	spawn_panel.visible = false
	hud_layer.add_child(spawn_panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	spawn_panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	margin.add_child(vb)

	var title := Label.new()
	title.text = "Spawn mob (~10 ft ahead)"
	vb.add_child(title)
	for entry: Array in _spawn_types():
		var b := Button.new()
		b.text = entry[0]
		b.custom_minimum_size = Vector2(200, 0)
		b.pressed.connect(_spawn_mob.bind(entry[1]))
		vb.add_child(b)
	vb.add_child(HSeparator.new())
	var bc := Button.new()
	bc.text = "Tear open a CAVE (~30 m ahead)"
	bc.custom_minimum_size = Vector2(200, 0)
	bc.focus_mode = Control.FOCUS_NONE
	bc.pressed.connect(_spawn_cave)
	vb.add_child(bc)
	var hint := Label.new()
	hint.text = "M / Esc to close"
	hint.modulate = Color(1, 1, 1, 0.55)
	vb.add_child(hint)


func _spawn_cave() -> void:
	## Dev: rip a whole new cave system open ahead of you (~40% roll VAST).
	## The world handles the slab surgery + the quake; we just point.
	var w := get_tree().get_first_node_in_group("world")
	if w == null or not w.has_method("spawn_cave_at"):
		return
	var fwd := -transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var mouth := global_position + fwd * 30.0
	## The system dives outward, away from the world center — the same rule
	## worldgen uses, so new regions never crowd the spawn clearing.
	var cdir := Vector3(signf(mouth.x), 0, 0) if absf(mouth.x) > absf(mouth.z) else Vector3(0, 0, signf(mouth.z))
	if cdir.length_squared() < 0.5:
		cdir = Vector3(1, 0, 0)
	if bool(w.call("spawn_cave_at", mouth, cdir)):
		_add_log_msg("The earth tears open ahead...", Color(1.0, 0.75, 0.35))
	else:
		_add_log_msg("The rock refuses here — too close to another cave", Color(0.8, 0.8, 0.8))


func _spawn_mob(mob_script: Variant) -> void:
	var fwd := -transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var pos := global_position + fwd * 3.0  ## ~10 feet ahead
	## Snap to the ground under that point.
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 3.0, pos + Vector3.DOWN * 30.0)
	q.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	if hit:
		pos = hit.position + Vector3.UP * 0.2
	else:
		pos.y = global_position.y + 0.5
	var e: Enemy = mob_script.new()
	e.confused = true  ## spawned mobs blink in disoriented — they wander in lost
					   ## circles and won't aggro until you hit them
	get_parent().add_child(e)
	e.global_position = pos


## ========================== Settings menu (Esc) ============================
## Applied LIVE (no restart) and saved to user://settings.cfg. The star option
## is Ray-Traced Lighting — Godot's SDFGI real-time GI preset (bounced sunlight,
## reflections, dawn light shafts, glowing blades). See World.set_rt_lighting.


func _build_settings_menu() -> void:
	settings_panel = PanelContainer.new()
	settings_panel.visible = false
	hud_layer.add_child(settings_panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	settings_panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	margin.add_child(vb)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 24)
	vb.add_child(title)
	vb.add_child(HSeparator.new())

	_settings_option_row(vb, "Ray-Traced Lighting", "rt",
		[["Off", false], ["On", true]])
	var rt_note := Label.new()
	rt_note.text = "SDFGI real-time global illumination: bounced sunlight, reflections,\nlight shafts through the trees, glowing elemental steel. Heavy on the GPU."
	rt_note.add_theme_font_size_override("font_size", 13)
	rt_note.modulate = Color(1, 1, 1, 0.55)
	vb.add_child(rt_note)

	_settings_option_row(vb, "Shadows", "shadows",
		[["Low", 0], ["Medium", 1], ["High", 2]])
	_settings_option_row(vb, "Display", "fullscreen",
		[["Windowed", false], ["Fullscreen", true]])
	_settings_option_row(vb, "VSync", "vsync",
		[["Off", false], ["On", true]])
	_settings_step_row(vb, "Mouse Sensitivity", "sens")
	_settings_step_row(vb, "Field of View", "fov")

	_settings_option_row(vb, "The Hunch", "hunch",
		[["Off", false], ["On", true]])
	var hunch_note := Label.new()
	hunch_note.text = "Steel answers intent: the moment something turns hostile, sword and shield\nclear the scabbard on their own — after 6.7 quiet seconds they ride home again."
	hunch_note.add_theme_font_size_override("font_size", 13)
	hunch_note.modulate = Color(1, 1, 1, 0.55)
	vb.add_child(hunch_note)

	vb.add_child(HSeparator.new())
	var hint := Label.new()
	hint.text = "Esc to close — changes apply instantly and are remembered"
	hint.modulate = Color(1, 1, 1, 0.55)
	vb.add_child(hint)


func _settings_option_row(parent: Control, label_text: String, id: String, options: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var nm := Label.new()
	nm.text = label_text
	nm.custom_minimum_size = Vector2(190, 0)
	nm.add_theme_font_size_override("font_size", 17)
	row.add_child(nm)
	var btns: Array = []
	for opt: Array in options:
		var b := Button.new()
		b.text = String(opt[0])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(96, 0)
		b.pressed.connect(_settings_pick.bind(id, opt[1]))
		row.add_child(b)
		btns.append([opt[1], b])
	_settings_widgets[id] = {"btns": btns}


func _settings_step_row(parent: Control, label_text: String, id: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var nm := Label.new()
	nm.text = label_text
	nm.custom_minimum_size = Vector2(190, 0)
	nm.add_theme_font_size_override("font_size", 17)
	row.add_child(nm)
	var minus := Button.new()
	minus.text = "-"
	minus.custom_minimum_size = Vector2(40, 0)
	minus.focus_mode = Control.FOCUS_NONE
	minus.pressed.connect(_settings_step.bind(id, -1))
	row.add_child(minus)
	var val := Label.new()
	val.custom_minimum_size = Vector2(80, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.add_theme_font_size_override("font_size", 17)
	row.add_child(val)
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(40, 0)
	plus.focus_mode = Control.FOCUS_NONE
	plus.pressed.connect(_settings_step.bind(id, 1))
	row.add_child(plus)
	_settings_widgets[id] = {"label": val}


func _settings_pick(id: String, value: Variant) -> void:
	match id:
		"rt": set_rt = bool(value)
		"shadows": set_shadows = int(value)
		"fullscreen": set_fullscreen = bool(value)
		"vsync": set_vsync = bool(value)
		"hunch": set_hunch = bool(value)
	_apply_settings()
	_save_settings()
	_refresh_settings_ui()


func _settings_step(id: String, dir: int) -> void:
	match id:
		"sens": set_sens = clampf(set_sens + 0.1 * dir, 0.3, 2.5)
		"fov": set_fov = clampf(set_fov + 5.0 * dir, 60.0, 110.0)
	_apply_settings()
	_save_settings()
	_refresh_settings_ui()


func _refresh_settings_ui() -> void:
	for id: String in _settings_widgets:
		var w: Dictionary = _settings_widgets[id]
		if w.has("btns"):
			var cur: Variant = null
			match id:
				"rt": cur = set_rt
				"shadows": cur = set_shadows
				"fullscreen": cur = set_fullscreen
				"vsync": cur = set_vsync
				"hunch": cur = set_hunch
			for pair: Array in (w["btns"] as Array):
				(pair[1] as Button).button_pressed = pair[0] == cur
		elif w.has("label"):
			var lbl := w["label"] as Label
			if id == "sens":
				lbl.text = "%.1f x" % set_sens
			elif id == "fov":
				lbl.text = "%d deg" % int(set_fov)


func _apply_settings() -> void:
	## Everything lands live: lighting through the World, the rest right here.
	var w := get_tree().get_first_node_in_group("world")
	if w != null:
		if w.has_method("set_rt_lighting"):
			w.set_rt_lighting(set_rt)
		if w.has_method("set_shadow_quality"):
			w.set_shadow_quality(set_shadows)
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if set_fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if set_vsync else DisplayServer.VSYNC_DISABLED)
	if camera:
		camera.fov = set_fov


func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("gfx", "rt", set_rt)
	cf.set_value("gfx", "shadows", set_shadows)
	cf.set_value("gfx", "fullscreen", set_fullscreen)
	cf.set_value("gfx", "vsync", set_vsync)
	cf.set_value("gfx", "fov", set_fov)
	cf.set_value("input", "sens", set_sens)
	cf.set_value("game", "hunch", set_hunch)
	cf.save(SETTINGS_PATH)


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return  ## first run — the defaults are the settings
	set_rt = bool(cf.get_value("gfx", "rt", false))
	set_shadows = clampi(int(cf.get_value("gfx", "shadows", 1)), 0, 2)
	set_fullscreen = bool(cf.get_value("gfx", "fullscreen", false))
	set_vsync = bool(cf.get_value("gfx", "vsync", true))
	set_fov = clampf(float(cf.get_value("gfx", "fov", 75.0)), 60.0, 110.0)
	set_sens = clampf(float(cf.get_value("input", "sens", 1.0)), 0.3, 2.5)
	set_hunch = bool(cf.get_value("game", "hunch", true))


## ========================= Inventory (I / Tab) ============================


func _init_inventory() -> void:
	## Placeholder gear so the slots and weight limit can be exercised now.
	## TODO(design): real item definitions (armor values, set bonuses?) come with step 4/5.
	inventory = [
		{"name": "Iron Sword", "weight": Materials.sword_weight("iron"), "count": 1, "slot": "sword", "material": "iron"},
		{"name": "Rusty Helmet", "weight": 4.0, "count": 1, "slot": "helmet"},
		{"name": "Leather Chestpiece", "weight": 8.0, "count": 1, "slot": "chest"},
		{"name": "Iron Bracers", "weight": 5.0, "count": 1, "slot": "arms"},
		{"name": "Cloth Pants", "weight": 2.0, "count": 1, "slot": "pants"},
		{"name": "Worn Boots", "weight": 3.0, "count": 1, "slot": "shoes"},
		{"name": "Wooden Shield", "weight": 6.0, "count": 1, "slot": "offhand"},
		{"name": "Torch", "weight": 1.0, "count": 1, "slot": "offhand"},
		{"name": "Iron Pickaxe", "weight": 3.5, "count": 1, "slot": ""},
		{"name": "Arrow", "weight": 0.06, "count": 20, "slot": ""},
		{"name": "Boar Tusk", "weight": 0.5, "count": 3, "slot": ""},
		{"name": "Old Bone", "weight": 1.0, "count": 2, "slot": ""},
	]
	for slot in SLOT_ORDER:
		equipment[slot] = -1
	equipment["sword"] = 0  ## you start with the iron blade in hand


func _sword_material_id() -> String:
	## Material of the currently wielded sword (drives visuals + damage math).
	var idx := int(equipment.get("sword", -1))
	if idx >= 0 and idx < inventory.size() and inventory[idx].has("material"):
		return String(inventory[idx].material)
	return "iron"


func _apply_equipped_sword() -> void:
	## Rebuild the held blade to match the newly equipped sword's material.
	var mat_id := _sword_material_id()
	if sword_vm:
		sword_vm.queue_free()
	sword_vm = _make_sword(viewmodel, Vector3(0, 0.02, -0.04), mat_id)
	var e := Materials.element_name(mat_id)
	var suffix := (" — " + e) if e != "" else ""
	_add_log_msg("Wielding: %s%s" % [Materials.sword_name(mat_id), suffix], Color(0.85, 0.9, 1.0))


func _give_sword(mat_id: String, n := 1) -> void:
	## Swords stack by material for now — per-sword evolution bars/durability
	## (step 5) will split them into individual items later.
	var item_name := Materials.sword_name(mat_id)
	for it in inventory:
		if String(it.name) == item_name:
			it.count = int(it.count) + n
			if menu_open == "tab" and tab_page == "inventory":
				_refresh_inventory_ui()
			return
	inventory.append({"name": item_name, "weight": Materials.sword_weight(mat_id),
		"count": n, "slot": "sword", "material": mat_id})
	if menu_open == "tab" and tab_page == "inventory":
		_refresh_inventory_ui()


func _owns_sword_of(mat_id: String) -> bool:
	for it in inventory:
		if String(it.get("slot", "")) == "sword" and String(it.get("material", "")) == mat_id:
			return true
	return false


## ==================== Armor sets (material plate) ==========================


func _give_item_dict(d: Dictionary) -> void:
	## Generic give: merge into an existing stack by name, else new entry.
	for it in inventory:
		if String(it.name) == String(d.name):
			it.count = int(it.count) + int(d.count)
			if menu_open == "tab" and tab_page == "inventory":
				_refresh_inventory_ui()
			return
	inventory.append(d.duplicate())
	if menu_open == "tab" and tab_page == "inventory":
		_refresh_inventory_ui()


func _give_armor_set(mat_id: String) -> void:
	## The full 5-piece kit of one material, straight into the pack.
	for slot: String in Materials.ARMOR_SLOTS:
		_give_item_dict({"name": Materials.armor_piece_name(mat_id, slot),
			"weight": Materials.armor_piece_weight(mat_id, slot), "count": 1,
			"slot": slot, "material": mat_id})


func _armor_mult() -> float:
	## Damage multiplier from worn material armor: each piece shaves 2/3/4/5%
	## by tier (full set: common 10% -> end-game 25%), capped at 40% total so
	## plate never trivializes the game. Placeholder rags protect nothing.
	var protect := 0.0
	for slot: String in Materials.ARMOR_SLOTS:
		var idx := int(equipment.get(slot, -1))
		if idx < 0 or idx >= inventory.size():
			continue
		var m := String(inventory[idx].get("material", ""))
		if m != "":
			protect += Materials.armor_piece_protect(m)
	return 1.0 - minf(protect, 0.4)


func _tint(mesh: MeshInstance3D, col: Color, metal: bool) -> void:
	if mesh == null:
		return
	var m := mesh.material_override as StandardMaterial3D
	if m == null:
		return
	m.albedo_color = col
	m.metallic = 0.65 if metal else 0.0
	m.roughness = 0.4 if metal else 1.0


func _slot_wear_color(slot: String, def: Color) -> Array:
	## [color, is_metal] for a body part: the equipped piece's material color,
	## or the default padding when the slot is empty / placeholder rags.
	var idx := int(equipment.get(slot, -1))
	if idx >= 0 and idx < inventory.size():
		var m := String(inventory[idx].get("material", ""))
		if m != "":
			return [Materials.get_mat(m)["color"], true]
	return [def, false]


func _apply_armor_visuals() -> void:
	## The visible body wears what you equipped: chest -> torso plate,
	## bracers -> both upper arms + the viewmodel forearm, greaves -> pelvis
	## and legs, boots -> feet. (No head mesh yet — helmets are stats-only.)
	var c: Array = _slot_wear_color("chest", BODY_ARMOR_COL)
	_tint(torso_mesh, c[0], c[1])
	var a: Array = _slot_wear_color("arms", BODY_ARMOR_COL)
	for am in arm_meshes:
		_tint(am, a[0], a[1])
	_tint(forearm_mesh, a[0], a[1])
	var p: Array = _slot_wear_color("pants", BODY_LEATHER_COL)
	_tint(pelvis_mesh, p[0], p[1])
	for lm in leg_meshes:
		_tint(lm, p[0], p[1])
	var s: Array = _slot_wear_color("shoes", BODY_FOOT_COL)
	for fm in foot_meshes:
		_tint(fm, s[0], s[1])


## ============= Dropped items (Q to toss, look + E to reclaim) ==============


func _sword_total() -> int:
	var n := 0
	for it in inventory:
		if String(it.get("slot", "")) == "sword":
			n += int(it.count)
	return n


func _drop_item(idx: int) -> void:
	if idx < 0 or idx >= inventory.size():
		return
	var it := inventory[idx]
	## The main hand is never empty — your very last sword stays with you.
	if String(it.get("slot", "")) == "sword" and _sword_total() <= 1:
		_add_log_msg("Can't drop your last sword", Color(0.9, 0.75, 0.4))
		return
	## Peel ONE off the stack and toss it out ahead of you.
	var d := {"name": it.name, "weight": it.weight, "count": 1,
		"slot": String(it.get("slot", "")), "material": String(it.get("material", ""))}
	it.count = int(it.count) - 1
	if int(it.count) <= 0:
		_remove_inventory_index(idx)
	var node := DroppedItem.make(d)
	get_parent().add_child(node)
	var fwd := -camera.global_transform.basis.z
	node.global_position = camera.global_position + fwd * 0.7 + Vector3.DOWN * 0.2
	node.velocity = fwd * 4.2 + Vector3.UP * 2.2
	_add_log_msg("Dropped: %s" % String(d.name), Color(0.9, 0.9, 1.0))
	_refresh_inventory_ui()


func _remove_inventory_index(idx: int) -> void:
	## Inventory indices shift on removal, and equipment maps slots to indices —
	## remap everything, unequipping whatever pointed at the removed entry.
	inventory.remove_at(idx)
	hovered_item_idx = -1
	var sword_gone := false
	for slot in SLOT_ORDER:
		var e := int(equipment.get(slot, -1))
		if e == idx:
			equipment[slot] = -1
			if slot == "sword":
				sword_gone = true
		elif e > idx:
			equipment[slot] = e - 1
	if sword_gone:
		_equip_any_sword()
	_apply_armor_visuals()


func _equip_any_sword() -> void:
	## The wielded sword left the pack — snap to the first sword still owned.
	## (_drop_item guarantees one exists.)
	for i in range(inventory.size()):
		if String(inventory[i].get("slot", "")) == "sword":
			equipment["sword"] = i
			_apply_equipped_sword()
			return


func _set_hovered_item(idx: int) -> void:
	hovered_item_idx = idx


func _unset_hovered_item(idx: int) -> void:
	if hovered_item_idx == idx:
		hovered_item_idx = -1


func _pickup_dropped(di: DroppedItem) -> void:
	var d: Dictionary = di.item
	_give_item_dict(d)
	_push_gain(String(d.name), int(d.count))
	di.queue_free()
	_drop_target = null


func _update_drop_target() -> void:
	## Which dropped item is under the gaze? Close (<3.2m) and near the center
	## of the view — the same "look at it" feel as aiming a swing.
	_drop_target = null
	if menu_open != "" or kd_phase != "":
		return
	var best := 0.92
	var fwd := -camera.global_transform.basis.z
	for n in get_tree().get_nodes_in_group("dropped_items"):
		var di := n as DroppedItem
		if di == null:
			continue
		var to := di.global_position - camera.global_position
		var dist := to.length()
		if dist > 3.2 or dist < 0.05:
			continue
		var d := fwd.dot(to.normalized())
		if d > best:
			best = d
			_drop_target = di


## ==================== Bestiary ledger (learn by doing) ====================


func on_mob_slain(e: Node) -> void:
	## Called by Enemy._die for EVERY death — sword, arrow, or pickaxe. First
	## kill of a kind opens its bestiary row; every kill feeds the Slayer tree.
	var nm := String(e.display_name) if "display_name" in e else "Creature"
	var first: bool = not bestiary_kills.has(nm)
	bestiary_kills[nm] = int(bestiary_kills.get(nm, 0)) + 1
	if first:
		_add_log_msg("Bestiary: %s — page opened (Tab, 4)" % nm, Color(0.75, 0.95, 0.75))
	_record_progress("slayer", 1)
	if menu_open == "tab" and tab_page == "bestiary":
		_refresh_bestiary_page()


func _bestiary_prove(e: Node, mat_id: String) -> void:
	## Landing material X on creature Y proves that matchup — the bestiary
	## stops showing ??? for that pairing. One log line, the first time only.
	var nm := String(e.display_name) if "display_name" in e else "Creature"
	if not bestiary_proven.has(nm):
		bestiary_proven[nm] = {}
	var proven: Dictionary = bestiary_proven[nm]
	if proven.has(mat_id):
		return
	proven[mat_id] = true
	var fams: Array = e.families if "families" in e else []
	var mult := Materials.matchup_mult(mat_id, fams) * Materials.element_mult(mat_id, fams)
	var verdict := "no purchase either way"
	var col := Color(0.8, 0.8, 0.8)
	if mult > 1.01:
		verdict = "it BITES (×%.2f)" % mult
		col = Color(0.55, 0.95, 0.55)
	elif mult < 0.99:
		verdict = "it's resisted (×%.2f)" % mult
		col = Color(0.95, 0.55, 0.45)
	_add_log_msg("%s vs %s — %s" % [Materials.display_name(mat_id), nm, verdict], col)
	if menu_open == "tab" and tab_page == "bestiary":
		_refresh_bestiary_page()


func _total_weight() -> float:
	## Worn armor counts at HALF weight — gear on your body is easier to carry
	## than gear in your pack.
	var w := 0.0
	var equipped_indices := equipment.values()
	for i in range(inventory.size()):
		var it := inventory[i]
		var iw := float(it.weight) * float(it.count)
		if i in equipped_indices:
			iw *= 0.5
		w += iw
	return w


## ============== Tab menu (Inventory | Stats | Progression) ================


func _build_tab_menu() -> void:
	tab_panel = PanelContainer.new()
	tab_panel.visible = false
	## One fixed size for every page — pages must fit INSIDE this, and
	## _set_tab_page snaps back to it so no page can permanently grow the panel.
	tab_panel.custom_minimum_size = TAB_PANEL_SIZE
	hud_layer.add_child(tab_panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	tab_panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)

	## Header: page tabs on the left, the banked-points badge on the right.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vb.add_child(header)
	for pg: Array in [["inventory", "[1] Inventory"], ["stats", "[2] Stats"], ["progression", "[3] Progression"], ["bestiary", "[4] Bestiary"]]:
		var b := Button.new()
		b.text = pg[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_set_tab_page.bind(pg[0]))
		header.add_child(b)
		tab_buttons[pg[0]] = b
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	points_badge = Label.new()
	points_badge.add_theme_font_size_override("font_size", 18)
	header.add_child(points_badge)
	vb.add_child(HSeparator.new())

	tab_pages["inventory"] = _build_inventory_page()
	tab_pages["stats"] = _build_stats_page()
	tab_pages["progression"] = _build_progression_page()
	tab_pages["bestiary"] = _build_bestiary_page()
	for k: String in tab_pages:
		var pgc := tab_pages[k] as Control
		pgc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		pgc.visible = false
		vb.add_child(pgc)


func _set_tab_page(page: String) -> void:
	tab_page = page
	for k: String in tab_pages:
		(tab_pages[k] as Control).visible = k == page
		(tab_buttons[k] as Button).button_pressed = k == page
	_refresh_tab_pages()
	## Snap back to the shared size — containers grow to fit content but never
	## shrink on their own, so without this the biggest page wins forever.
	## DEFERRED: resizing in the same frame as the visibility flip ran before
	## the container re-sorted the newly shown page, which drew the panel as a
	## blank gray sheet until the next switch. Let layout settle first.
	tab_panel.set_deferred("size", TAB_PANEL_SIZE)


func _refresh_tab_pages() -> void:
	points_badge.text = "Stat points: %d" % stats.points
	points_badge.modulate = Color(1.0, 0.85, 0.35) if stats.points > 0 else Color(1, 1, 1, 0.55)
	match tab_page:
		"inventory":
			_refresh_inventory_ui()
		"stats":
			_refresh_stats_page()
			_show_stat_detail(hovered_stat)
		"progression":
			_refresh_progression_page()
		"bestiary":
			_refresh_bestiary_page()


## --------------------------- Inventory page -------------------------------


func _build_inventory_page() -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 24)

	## Left column: item list + carry weight.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	hb.add_child(left)
	var title := Label.new()
	title.text = "Inventory"
	title.add_theme_font_size_override("font_size", 22)
	left.add_child(title)
	inv_weight_label = Label.new()
	left.add_child(inv_weight_label)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(sc)
	inv_items_box = VBoxContainer.new()
	inv_items_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_items_box.add_theme_constant_override("separation", 4)
	sc.add_child(inv_items_box)

	## Middle column: the ARMORY — dev selector (like the M mob menu) that adds
	## a sword of ANY material to the inventory, dropped or not.
	var armory := VBoxContainer.new()
	armory.add_theme_constant_override("separation", 4)
	hb.add_child(armory)
	var arm_title := Label.new()
	arm_title.text = "Armory (dev)"
	arm_title.add_theme_font_size_override("font_size", 22)
	armory.add_child(arm_title)
	var arm_note := Label.new()
	arm_note.text = "Sword, or the 5-piece armor set"
	arm_note.modulate = Color(1, 1, 1, 0.55)
	armory.add_child(arm_note)
	var arm_scroll := ScrollContainer.new()
	arm_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	armory.add_child(arm_scroll)
	var arm_box := VBoxContainer.new()
	arm_box.add_theme_constant_override("separation", 3)
	arm_scroll.add_child(arm_box)
	for id: String in Materials.ORDER:
		var mat: Dictionary = Materials.get_mat(id)
		var el := Materials.element_name(id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		arm_box.add_child(row)
		var nm := Label.new()
		nm.text = String(mat["name"])
		nm.custom_minimum_size = Vector2(92, 0)
		nm.mouse_filter = Control.MOUSE_FILTER_STOP  ## hover for the tooltip
		nm.tooltip_text = "%s%s" % [Materials.TIER_NAMES[int(mat["tier"])],
			(" · " + el + " element") if el != "" else ""]
		row.add_child(nm)
		var bs := Button.new()
		bs.text = "Sword"
		bs.focus_mode = Control.FOCUS_NONE
		bs.pressed.connect(_armory_give.bind(id))
		row.add_child(bs)
		var ba := Button.new()
		ba.text = "Armor"
		ba.focus_mode = Control.FOCUS_NONE
		ba.pressed.connect(_armory_give_armor.bind(id))
		row.add_child(ba)

	## Right column: equipped armor + offhand slots.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	hb.add_child(right)
	var eq_title := Label.new()
	eq_title.text = "Equipped"
	eq_title.add_theme_font_size_override("font_size", 22)
	right.add_child(eq_title)
	for slot in SLOT_ORDER:
		var lbl := Label.new()
		lbl.custom_minimum_size = Vector2(200, 0)
		right.add_child(lbl)
		inv_slot_labels[slot] = lbl
	var hint := Label.new()
	hint.text = "Click an item to equip / unequip\n(swords: click to wield; shield + torch\ncan share the offhand arm)\nQ over an item drops one at your feet\n1 / 2 / 3 / 4 switch pages — Esc closes"
	hint.modulate = Color(1, 1, 1, 0.55)
	right.add_child(hint)
	return hb


func _armory_give(mat_id: String) -> void:
	## Dev shortcut: conjure a sword of this material straight into the pack.
	_give_sword(mat_id, 1)
	_add_log_msg("Armory: +1 %s" % Materials.sword_name(mat_id), Color(0.85, 0.9, 1.0))


func _armory_give_armor(mat_id: String) -> void:
	## Dev shortcut: the full 5-piece kit of this material.
	_give_armor_set(mat_id)
	_add_log_msg("Armory: +%s set (5 pc)" % Materials.display_name(mat_id), Color(0.85, 0.9, 1.0))


## ----------------------------- Bestiary page -------------------------------
## Every creature is LISTED from the start, but its page is sealed (???) until
## your first kill of one. Weaknesses are stricter still: each metal's matchup
## stays ??? until you've landed that metal on that creature. Folklore is
## earned, not read — you learn silver-vs-skeleton by trying it.


func _build_bestiary_page() -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 24)

	## Left: the creature list (??? rows for kinds you haven't slain).
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(230, 0)
	left.add_theme_constant_override("separation", 6)
	hb.add_child(left)
	var title := Label.new()
	title.text = "Bestiary"
	title.add_theme_font_size_override("font_size", 22)
	left.add_child(title)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(sc)
	best_list_box = VBoxContainer.new()
	best_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	best_list_box.add_theme_constant_override("separation", 3)
	sc.add_child(best_list_box)
	var hint := Label.new()
	hint.text = "Slay one to open its page.\nStrike it with a metal to\nlearn what that metal does."
	hint.modulate = Color(1, 1, 1, 0.45)
	left.add_child(hint)

	## Right: the open page for the selected creature.
	var right := ScrollContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_child(right)
	best_detail = VBoxContainer.new()
	best_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	best_detail.add_theme_constant_override("separation", 6)
	right.add_child(best_detail)
	return hb


func _mob_lore(nm: String) -> Dictionary:
	## Stats straight from the archetype itself — spawn a throwaway instance
	## (subclass _init fills the sheet) and read it, so the bestiary can never
	## drift out of date when a mob gets retuned.
	if _mob_stat_cache.has(nm):
		return _mob_stat_cache[nm]
	for entry: Array in _mob_types():
		if String(entry[0]) != nm:
			continue
		var cls: GDScript = entry[1]
		var tmp: Enemy = cls.new()
		var lore := {
			"hp": tmp.max_health, "dmg": tmp.attack_damage,
			"strong": tmp.strong_damage, "fams": tmp.families.duplicate(),
		}
		tmp.free()
		_mob_stat_cache[nm] = lore
		return lore
	return {"hp": 0.0, "dmg": 0.0, "strong": 0.0, "fams": []}


func _refresh_bestiary_page() -> void:
	## Left list: names for the slain, ??? for the strangers.
	for c in best_list_box.get_children():
		(c as Control).visible = false  ## hide before free — see _refresh_inventory_ui
		c.queue_free()
	for entry: Array in _mob_types():
		var nm := String(entry[0])
		var known := int(bestiary_kills.get(nm, 0)) > 0
		var b := Button.new()
		b.text = ("%s   ×%d" % [nm, int(bestiary_kills[nm])]) if known else "???"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_pressed = nm == bestiary_selected
		b.focus_mode = Control.FOCUS_NONE
		if not known:
			b.modulate = Color(1, 1, 1, 0.5)
		b.pressed.connect(_bestiary_select.bind(nm))
		best_list_box.add_child(b)
	_rebuild_bestiary_detail()


func _bestiary_select(nm: String) -> void:
	bestiary_selected = nm
	_refresh_bestiary_page()


func _detail_label(text: String, size: int, col := Color(1, 1, 1)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.modulate = col
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	best_detail.add_child(l)
	return l


func _rebuild_bestiary_detail() -> void:
	for c in best_detail.get_children():
		(c as Control).visible = false
		c.queue_free()
	var nm := bestiary_selected
	var kills := int(bestiary_kills.get(nm, 0))

	if kills <= 0:
		## Sealed page: it exists, but you haven't put one down yet.
		_detail_label("???", 26, Color(1, 1, 1, 0.6))
		_detail_label("Nothing is written here yet.", 15, Color(1, 1, 1, 0.5))
		_detail_label("Slay one and the page will open.", 15, Color(1, 1, 1, 0.5))
		return

	var lore := _mob_lore(nm)
	var fams: Array = lore["fams"]
	_detail_label(nm, 26)
	var fam_names: Array[String] = []
	for f in fams:
		fam_names.append(String(FAMILY_NAMES.get(f, String(f).capitalize())))
	_detail_label(" · ".join(fam_names), 15, Color(0.75, 0.85, 1.0))
	_detail_label(String(MOB_FLAVOR.get(nm, "")), 14, Color(1, 1, 1, 0.65))
	_detail_label("Vitality %d    Strike %d    Fury %d    —    slain ×%d" %
		[int(lore["hp"]), int(lore["dmg"]), int(lore["strong"]), kills], 15, Color(0.9, 0.9, 0.9))
	best_detail.add_child(HSeparator.new())
	_detail_label("Weaknesses — proven blade by blade:", 16, Color(1.0, 0.9, 0.6))

	var proven: Dictionary = bestiary_proven.get(nm, {})
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 4)
	best_detail.add_child(grid)
	for id: String in Materials.ORDER:
		var cell := Label.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if proven.has(id):
			var mult := Materials.matchup_mult(id, fams) * Materials.element_mult(id, fams)
			if mult > 1.01:
				cell.text = "%s  ×%.2f  — bites deep" % [Materials.display_name(id), mult]
				cell.modulate = Color(0.55, 0.95, 0.55)
			elif mult < 0.99:
				cell.text = "%s  ×%.2f  — resisted" % [Materials.display_name(id), mult]
				cell.modulate = Color(0.95, 0.55, 0.45)
			else:
				cell.text = "%s  ×1.00  — indifferent" % Materials.display_name(id)
				cell.modulate = Color(0.8, 0.8, 0.8)
		else:
			cell.text = "%s  ???" % Materials.display_name(id)
			cell.modulate = Color(1, 1, 1, 0.35)
		grid.add_child(cell)


## ------------------------------ Stats page --------------------------------
## Cyberpunk-style sheet: attributes on the left (+/- queues points, Confirm
## commits them), hover an attribute to see exactly what it changes with live
## before -> after numbers on the right.


func _build_stats_page() -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 28)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(330, 0)
	left.add_theme_constant_override("separation", 8)
	hb.add_child(left)
	var title := Label.new()
	title.text = "Attributes"
	title.add_theme_font_size_override("font_size", 22)
	left.add_child(title)
	stat_avail_label = Label.new()
	left.add_child(stat_avail_label)

	for id: String in PlayerStats.STAT_ORDER:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.mouse_entered.connect(_show_stat_detail.bind(id))
		left.add_child(row)
		var nm := Label.new()
		nm.text = String(PlayerStats.STAT_NAMES[id])
		nm.custom_minimum_size = Vector2(140, 0)
		nm.add_theme_font_size_override("font_size", 18)
		row.add_child(nm)
		var val := Label.new()
		val.custom_minimum_size = Vector2(72, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val.add_theme_font_size_override("font_size", 22)
		row.add_child(val)
		var minus := Button.new()
		minus.text = "-"
		minus.custom_minimum_size = Vector2(34, 0)
		minus.focus_mode = Control.FOCUS_NONE
		minus.pressed.connect(_adjust_pending.bind(id, -1))
		row.add_child(minus)
		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(34, 0)
		plus.focus_mode = Control.FOCUS_NONE
		plus.pressed.connect(_adjust_pending.bind(id, 1))
		row.add_child(plus)
		stat_rows[id] = {"value": val, "minus": minus, "plus": plus}

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	left.add_child(btns)
	stat_confirm = Button.new()
	stat_confirm.text = "Confirm"
	stat_confirm.focus_mode = Control.FOCUS_NONE
	stat_confirm.pressed.connect(_confirm_pending)
	btns.add_child(stat_confirm)
	stat_reset = Button.new()
	stat_reset.text = "Reset"
	stat_reset.focus_mode = Control.FOCUS_NONE
	stat_reset.pressed.connect(_reset_pending)
	btns.add_child(stat_reset)
	var how := Label.new()
	how.text = "Trees on the Progression page also\nfeed these — grow what you use."
	how.modulate = Color(1, 1, 1, 0.45)
	left.add_child(how)

	## Right: what the hovered attribute actually does.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	hb.add_child(right)
	detail_title = Label.new()
	detail_title.add_theme_font_size_override("font_size", 22)
	right.add_child(detail_title)
	detail_flavor = Label.new()
	detail_flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_flavor.modulate = Color(1, 1, 1, 0.65)
	right.add_child(detail_flavor)
	right.add_child(HSeparator.new())
	detail_box = VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 4)
	right.add_child(detail_box)
	return hb


func _pending_total() -> int:
	var n := 0
	for id: String in pending:
		n += int(pending[id])
	return n


func _adjust_pending(id: String, dir: int) -> void:
	if dir > 0:
		if stats.points - _pending_total() <= 0:
			return
		if stats.get_stat(id) + int(pending[id]) >= PlayerStats.STAT_CAP:
			return
		pending[id] = int(pending[id]) + 1
	else:
		pending[id] = maxi(0, int(pending[id]) - 1)
	hovered_stat = id
	_refresh_tab_pages()


func _confirm_pending() -> void:
	var spent := 0
	for id: String in PlayerStats.STAT_ORDER:
		if int(pending[id]) > 0:
			spent += stats.spend(id, int(pending[id]))
		pending[id] = 0
	if spent > 0:
		_refresh_derived()
		_add_log_msg("+%d stat point%s assigned" % [spent, "" if spent == 1 else "s"], Color(1.0, 0.85, 0.35))
	_refresh_tab_pages()


func _reset_pending() -> void:
	for id: String in PlayerStats.STAT_ORDER:
		pending[id] = 0
	_refresh_tab_pages()


func _refresh_stats_page() -> void:
	var queued := _pending_total()
	var avail := stats.points - queued
	if queued > 0:
		stat_avail_label.text = "Unspent: %d   (%d queued — Confirm to apply)" % [avail, queued]
		stat_avail_label.modulate = Color(1.0, 0.85, 0.35)
	else:
		stat_avail_label.text = "Unspent points: %d" % avail
		stat_avail_label.modulate = Color(1, 1, 1, 0.8) if avail > 0 else Color(1, 1, 1, 0.55)
	for id: String in PlayerStats.STAT_ORDER:
		var row: Dictionary = stat_rows[id]
		var cur := stats.get_stat(id)
		var pend := int(pending[id])
		var val := row.value as Label
		if pend > 0:
			val.text = "%d +%d" % [cur, pend]
			val.modulate = Color(1.0, 0.85, 0.35)
		else:
			val.text = str(cur)
			val.modulate = Color(1, 1, 1)
		(row.plus as Button).disabled = avail <= 0 or cur + pend >= PlayerStats.STAT_CAP
		(row.minus as Button).disabled = pend <= 0
	stat_confirm.disabled = queued <= 0
	stat_reset.disabled = queued <= 0


func _show_stat_detail(id: String) -> void:
	hovered_stat = id
	if detail_title == null:
		return
	var pend := int(pending[id])
	var queued_note := " (+%d queued)" % pend if pend > 0 else ""
	detail_title.text = "%s — %d%s" % [String(PlayerStats.STAT_NAMES[id]), stats.get_stat(id), queued_note]
	detail_flavor.text = String(PlayerStats.STAT_FLAVOR[id])
	for c in detail_box.get_children():
		(c as Control).visible = false  ## hide before free — see _refresh_inventory_ui
		c.queue_free()
	var capped := stats.get_stat(id) + pend >= PlayerStats.STAT_CAP
	for line: Array in stats.effect_lines(id, pend):
		var row := HBoxContainer.new()
		detail_box.add_child(row)
		var lab := Label.new()
		lab.text = String(line[0])
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lab)
		var now := Label.new()
		now.text = String(line[1])
		row.add_child(now)
		if not capped and String(line[1]) != String(line[2]):
			var nxt := Label.new()
			nxt.text = "  ->  %s" % String(line[2])
			nxt.modulate = Color(0.55, 0.95, 0.55)
			row.add_child(nxt)
	var foot := Label.new()
	foot.text = "(capped)" if capped else "green: with one more point"
	foot.modulate = Color(1, 1, 1, 0.45)
	detail_box.add_child(foot)


## --------------------------- Progression page -----------------------------
## Hidden achievement trees: earned tiers in gold, the next tier with live
## progress, and ??? beyond it. Every payout feeds the tree's linked stat.


func _build_progression_page() -> Control:
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prog_box = VBoxContainer.new()
	prog_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prog_box.add_theme_constant_override("separation", 4)
	sc.add_child(prog_box)
	return sc


func _refresh_progression_page() -> void:
	for c in prog_box.get_children():
		(c as Control).visible = false  ## hide before free — see _refresh_inventory_ui
		c.queue_free()
	for t: Dictionary in PlayerStats.TREES:
		var id := String(t.id)
		var earned := int(stats.tiers_earned[id])
		var stat_name := String(PlayerStats.STAT_NAMES[String(t.stat)])

		var head := Label.new()
		head.add_theme_font_size_override("font_size", 19)
		prog_box.add_child(head)
		if bool(t.locked):
			head.text = "???  —  %s" % stat_name
			head.modulate = Color(1, 1, 1, 0.45)
			var why := _prog_line("     %s" % String(t.desc), Color(1, 1, 1, 0.35))
			prog_box.add_child(why)
			prog_box.add_child(_prog_gap())
			continue
		var suffix := "   (%d earned)" % earned if earned > 0 else ""
		head.text = "%s  —  %s%s" % [String(t.name), stat_name, suffix]
		head.modulate = Color(1.0, 0.85, 0.45) if earned > 0 else Color(1, 1, 1, 0.9)
		prog_box.add_child(_prog_line("     %s" % String(t.desc), Color(1, 1, 1, 0.5)))

		## Earned tiers in gold — long histories collapse to the last few.
		var first_shown := maxi(0, earned - 4)
		if first_shown > 0:
			prog_box.add_child(_prog_line("     ... %d earlier tier%s earned" % [first_shown, "" if first_shown == 1 else "s"], Color(1.0, 0.8, 0.35, 0.5)))
		for i in range(first_shown, earned):
			prog_box.add_child(_prog_line(
				"     * %s %s  —  %s %s   (+%d %s)" % [String(t.name), PlayerStats.roman(i + 1),
				_tree_amount(id, stats.tier_threshold(id, i)), String(t.noun),
				stats.tier_points(i), stat_name],
				Color(1.0, 0.8, 0.35)))

		## The next tier always exists — they scale forever. Show live progress;
		## everything beyond stays hidden.
		var cur := int(stats.progress[id])
		var need := stats.tier_threshold(id, earned)
		prog_box.add_child(_prog_line(
			"     > %s %s  —  %s / %s %s" % [String(t.name), PlayerStats.roman(earned + 1),
			_tree_amount(id, cur), _tree_amount(id, need), String(t.noun)],
			Color(1, 1, 1, 0.9)))
		prog_box.add_child(_mini_bar(clampf(float(cur) / float(need), 0.0, 1.0)))
		prog_box.add_child(_prog_line("     ... and beyond", Color(1, 1, 1, 0.35)))
		prog_box.add_child(_prog_gap())


func _prog_line(text: String, col: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.modulate = col
	return lbl


func _prog_gap() -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	return gap


func _tree_amount(id: String, n: int) -> String:
	## Big meter counts read better as kilometers.
	if id == "marathoner" and n >= 1000:
		var s := "%.1f" % (float(n) / 1000.0)
		return s.trim_suffix(".0") + " km"
	elif id == "marathoner":
		return "%d m" % n
	return str(n)


func _mini_bar(ratio: float) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(300, 10)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.5)
	bg.size = Vector2(260, 6)
	bg.position = Vector2(40, 2)
	wrap.add_child(bg)
	var fill := ColorRect.new()
	fill.color = Color(0.45, 0.70, 1.0)
	fill.size = Vector2(260.0 * clampf(ratio, 0.0, 1.0), 6)
	fill.position = Vector2(40, 2)
	wrap.add_child(fill)
	return wrap


func _refresh_inventory_ui() -> void:
	for c in inv_items_box.get_children():
		## Hide BEFORE queue_free: freed nodes still occupy the layout until end
		## of frame, and a container that grew to fit them never shrinks back.
		(c as Control).visible = false
		c.queue_free()
	var w := _total_weight()
	var lim := stats.carry_limit()  ## STR raises it
	if w > lim:
		inv_weight_label.text = "Weight: %.1f / %.1f  — OVERBURDENED (slowed, no sprint)" % [w, lim]
		inv_weight_label.modulate = Color(1.0, 0.40, 0.30)
	else:
		inv_weight_label.text = "Weight: %.1f / %.1f" % [w, lim]
		inv_weight_label.modulate = Color(1, 1, 1)
	for i in range(inventory.size()):
		var it := inventory[i]
		var b := Button.new()
		var txt := "%s  ×%d  —  %.1f wt" % [it.name, it.count, float(it.weight) * float(it.count)]
		if it.slot != "":
			txt += "   [%s]" % SLOT_NAMES[it.slot]
			if int(equipment.get(it.slot, -1)) == i \
					or (String(it.slot) == "offhand" and int(equipment.get("offhand2", -1)) == i):
				txt += "   (equipped)"
		b.text = txt
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_item_clicked.bind(i))
		## Track the row under the mouse so Q knows what to drop.
		b.mouse_entered.connect(_set_hovered_item.bind(i))
		b.mouse_exited.connect(_unset_hovered_item.bind(i))
		inv_items_box.add_child(b)
	for slot in SLOT_ORDER:
		var idx := int(equipment.get(slot, -1))
		var nm: String = "—" if idx < 0 else String(inventory[idx].name)
		(inv_slot_labels[slot] as Label).text = "%s:  %s" % [SLOT_NAMES[slot], nm]


func _item_clicked(idx: int) -> void:
	var it := inventory[idx]
	if it.slot == "":
		return  ## plain loot — nothing to equip. TODO(design): use/drop actions later
	if String(it.slot) == "sword":
		## The main hand is never empty — clicking a sword wields it.
		if int(equipment.get("sword", -1)) != idx:
			equipment["sword"] = idx
			_apply_equipped_sword()
		_refresh_inventory_ui()
		return
	if String(it.slot) == "offhand":
		## One arm, two berths: a shield and a torch can ride together (the
		## shield straps on, the torch keeps the fist). Click toggles each.
		var a := int(equipment.get("offhand", -1))
		var b := int(equipment.get("offhand2", -1))
		if idx == a:
			equipment["offhand"] = b   ## the companion (if any) slides up
			equipment["offhand2"] = -1
		elif idx == b:
			equipment["offhand2"] = -1
		elif a == -1:
			equipment["offhand"] = idx
		else:
			equipment["offhand2"] = idx  ## joins the arm that's already busy
		_refresh_inventory_ui()
		return
	if int(equipment.get(it.slot, -1)) == idx:
		equipment[it.slot] = -1
	else:
		equipment[it.slot] = idx
	_apply_armor_visuals()  ## the body wears what you just (un)equipped
	_refresh_inventory_ui()


## ===================== Offhand (shield / torch, Q) ========================


func _cycle_offhand() -> void:
	## Cycle the offhand through what you actually OWN: shield -> torch ->
	## shield+torch (the shield straps to the forearm so the torch can ride
	## the same fist) -> empty hand -> around again.
	if current_weapon == "bow":
		_add_log_msg("Hands are full (bow)", Color(0.8, 0.8, 0.8))
		return
	var owned: Array[int] = []
	var shield_i := -1
	var torch_i := -1
	for i in range(inventory.size()):
		if String(inventory[i].slot) == "offhand":
			owned.append(i)
			if shield_i == -1 and String(inventory[i].name).contains("Shield"):
				shield_i = i
			elif torch_i == -1 and String(inventory[i].name).contains("Torch"):
				torch_i = i
	if owned.is_empty():
		_add_log_msg("No offhand items", Color(0.8, 0.8, 0.8))
		return
	## Build the ordered mode list: each single item, the pair, the empty hand.
	var modes: Array = []
	for i in owned:
		modes.append([i, -1])
	if shield_i != -1 and torch_i != -1:
		modes.append([shield_i, torch_i])
	modes.append([-1, -1])
	var cur_a := int(equipment.get("offhand", -1))
	var cur_b := int(equipment.get("offhand2", -1))
	var pos := -1
	for m in range(modes.size()):
		if int(modes[m][0]) == cur_a and int(modes[m][1]) == cur_b:
			pos = m
			break
	var nxt: Array = modes[0] if pos == -1 else modes[(pos + 1) % modes.size()]
	equipment["offhand"] = nxt[0]
	equipment["offhand2"] = nxt[1]
	if int(nxt[0]) == -1:
		_add_log_msg("Offhand: empty", Color(0.8, 0.8, 0.8))
	elif int(nxt[1]) != -1:
		_add_log_msg("Offhand: %s + %s" % [inventory[nxt[0]].name, inventory[nxt[1]].name], Color(0.85, 0.9, 1.0))
	else:
		_add_log_msg("Offhand: %s" % inventory[nxt[0]].name, Color(0.85, 0.9, 1.0))
	if menu_open == "tab" and tab_page == "inventory":
		_refresh_inventory_ui()


func _idx_is(idx: int, what: String) -> bool:
	## Does this inventory index hold an item whose name contains `what`?
	return idx >= 0 and idx < inventory.size() and String(inventory[idx].name).contains(what)


func _offhand_is_shield() -> bool:
	## Either displayed offhand item counts — a strapped shield still blocks.
	return _idx_is(offhand_shown, "Shield") or _idx_is(offhand_shown2, "Shield")


func _build_offhand_mesh(idx: int, idx2: int = -1) -> void:
	## One left hand, up to two items: alone, an item sits in the fist; paired,
	## the shield straps across the forearm and the torch keeps the fist.
	for c in offhand_node.get_children():
		c.queue_free()
	offhand_light = null
	if idx < 0 and idx2 < 0:
		return
	var skin := Color(0.62, 0.46, 0.36)
	_box(offhand_node, Vector3(0.09, 0.09, 0.12), skin, Vector3(0, -0.02, 0.03))  ## left hand
	if idx >= 0:
		_add_offhand_item(idx)
	if idx2 >= 0:
		_add_offhand_item(idx2)


func _add_offhand_item(idx: int) -> void:
	var item_name := String(inventory[idx].name)
	if item_name.contains("Shield"):
		## Round-ish wooden shield: boards, a rim, and a steel boss.
		var wood := Color(0.38, 0.26, 0.14)
		var rim := Color(0.24, 0.16, 0.09)
		_box(offhand_node, Vector3(0.34, 0.44, 0.045), wood, Vector3(0, 0.06, -0.05))
		_box(offhand_node, Vector3(0.44, 0.30, 0.045), wood, Vector3(0, 0.06, -0.05))
		_box(offhand_node, Vector3(0.36, 0.46, 0.02), rim, Vector3(0, 0.06, -0.028))
		_box(offhand_node, Vector3(0.10, 0.10, 0.07), Color(0.60, 0.63, 0.68), Vector3(0, 0.06, -0.08), Vector3.ZERO, true)
	elif item_name.contains("Torch"):
		## A burning brand: stick, char, ember wrap, and a flickering flame.
		var wood := Color(0.35, 0.24, 0.13)
		_box(offhand_node, Vector3(0.045, 0.42, 0.045), wood, Vector3(0, 0.14, -0.02))
		_box(offhand_node, Vector3(0.07, 0.08, 0.07), Color(0.12, 0.08, 0.05), Vector3(0, 0.36, -0.02))
		var ember := _box(offhand_node, Vector3(0.075, 0.05, 0.075), Color(1.0, 0.45, 0.10), Vector3(0, 0.41, -0.02))
		var emat := ember.material_override as StandardMaterial3D
		emat.emission_enabled = true
		emat.emission = Color(1.0, 0.45, 0.10)
		emat.emission_energy_multiplier = 2.0
		var flame := _box(offhand_node, Vector3(0.065, 0.13, 0.065), Color(1.0, 0.72, 0.25), Vector3(0, 0.50, -0.02))
		var fmat := flame.material_override as StandardMaterial3D
		fmat.emission_enabled = true
		fmat.emission = Color(1.0, 0.62, 0.20)
		fmat.emission_energy_multiplier = 3.5
		offhand_light = OmniLight3D.new()
		offhand_light.light_color = Color(1.0, 0.66, 0.32)
		offhand_light.light_energy = 1.25
		offhand_light.omni_range = 9.0
		offhand_light.shadow_enabled = false
		offhand_light.position = Vector3(0, 0.52, -0.02)
		offhand_node.add_child(offhand_light)
	else:
		## Unknown offhand item: a plain held box.
		_box(offhand_node, Vector3(0.16, 0.16, 0.16), Color(0.5, 0.5, 0.5), Vector3(0, 0.08, -0.03))


func _update_offhand(delta: float) -> void:
	var want := int(equipment.get("offhand", -1))
	var want2 := int(equipment.get("offhand2", -1))
	if want == -1 and want2 != -1:
		## Never a companion without a main (a drop/unequip edge) — slide it up.
		equipment["offhand"] = want2
		equipment["offhand2"] = -1
		want = want2
		want2 = -1
	if current_weapon == "bow":
		want = -1   ## the left hand is on the bow grip — shield/torch lower away
		want2 = -1
	elif sheathed:
		## The shield sheathes WITH the sword — it rides your back while the
		## blade rides the hip. The torch stays up: light is welcome company
		## even with the steel put away.
		if _idx_is(want2, "Shield"):
			want2 = -1
		if _idx_is(want, "Shield"):
			want = want2  ## a torch sharing the arm slides into the fist alone
			want2 = -1
	## The stowed shield shows on your back whenever you WEAR one that isn't in hand.
	if back_shield:
		var eq_shield := _idx_is(int(equipment.get("offhand", -1)), "Shield") \
			or _idx_is(int(equipment.get("offhand2", -1)), "Shield")
		back_shield.visible = eq_shield and not (_idx_is(want, "Shield") or _idx_is(want2, "Shield"))

	if want != offhand_shown or want2 != offhand_shown2:
		## Lower whatever is up first, then swap to the new items and raise them.
		offhand_raise = maxf(0.0, offhand_raise - delta / OH_RAISE_TIME)
		if offhand_raise <= 0.0:
			_build_offhand_mesh(want, want2)
			offhand_shown = want
			offhand_shown2 = want2
	elif offhand_shown != -1 and offhand_raise < 1.0:
		offhand_raise = minf(1.0, offhand_raise + delta / OH_RAISE_TIME)

	if offhand_shown == -1 and offhand_raise <= 0.0:
		offhand_node.visible = false
		return
	offhand_node.visible = true

	var r := offhand_raise * offhand_raise * (3.0 - 2.0 * offhand_raise)  ## smoothstep
	## The offhand rides the same stride, trailing the sword by a beat, with a
	## soft breathing sway when still. (The constant-rate timer also keeps the
	## torch flicker steady instead of strobing when you sprint.)
	oh_bob_t += delta * 6.0
	var bob := Vector3(
		sin(gait_phase + PI * 0.55) * 0.013 * gait_amount + sin(oh_bob_t * 0.9) * 0.002,
		absf(sin(gait_phase + PI * 0.55)) * 0.012 * gait_amount + absf(sin(oh_bob_t * 1.8)) * 0.003,
		0.0)
	var tpos := OH_REST_POS + Vector3(-0.10, -0.42, 0.10) * (1.0 - r) + bob
	var trot := OH_REST_ROT + Vector3(-40.0, -14.0, 18.0) * (1.0 - r)
	## The shield raises to guard the view while blocking.
	if blocking and _offhand_is_shield() and offhand_raise >= 1.0:
		tpos = Vector3(-0.12, -0.14, -0.40) + bob * 0.4
		trot = Vector3(4.0, 26.0, -2.0)
	offhand_node.position = offhand_node.position.lerp(tpos, delta * 14.0)
	offhand_node.rotation_degrees = offhand_node.rotation_degrees.lerp(trot, delta * 14.0)
	## Torch flame flicker.
	if offhand_light:
		offhand_light.light_energy = 1.25 + sin(oh_bob_t * 7.3) * 0.12 + sin(oh_bob_t * 13.7) * 0.08
