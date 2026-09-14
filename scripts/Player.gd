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
##   V ........... camera: FP -> third person (right shoulder); short press in
##                 TP cycles right -> CENTRED -> left; HOLD 1.5 s glides back
##                 to first person.
##                 Every switch animates; last setting is remembered
##   C ........... toggle CROUCH (from prone, C rises to the crouch)
##   X ........... toggle PRONE (from prone, X stands you all the way up).
##                 Each stance down is slower, lower, harder to spot (tall
##                 grass: ×0.6 upright, ×0.35 crouched, ×0.22 prone). Going
##                 prone settles slow with a body-weight roll; jumping or
##                 climbing stands you up
##   F ........... mount / dismount a saddled horse (WASD ride, Shift gallop,
##                 Space jump; LMB sweeps the sword saddle-side — look left or
##                 right to pick the side, straight ahead to alternate)
##   Alt/Option .. sheathe / unsheathe sword (the shield stows/draws with it;
##                 THE HUNCH — settings toggle — auto-draws the moment anything
##                 turns hostile and auto-sheathes after 6.7 quiet seconds)
##   M ........... THE MAP — the whole of Maine, towns, peaks and lakes, with
##                 you on it. Wheel zooms, right-drag pans; in GOD MODE a left
##                 click anywhere on it travels you there
##   K ........... mob spawn menu
##   G ........... CREATIVE menu (dev): every item in the game — swords /
##                 armor sets / ores for all 10 metals, plus the mundane kit
##   Tab ......... menu (1 Inventory / 2 Stats / 3 Progression / 4 Bestiary)
##   I ........... straight to the Inventory page — its Armory column (dev)
##                 adds any material sword; click a sword in the list to wield it
##   Q ........... cycle offhand (shield / torch / shield+torch / empty — owned
##                 items only; the shield straps on so the torch shares the arm)
##   Esc ......... settings menu (ray-traced lighting, shadows, display, input,
##                 the hunch) — or closes whichever menu is open

const SPEED := 5.0
const SPRINT_SPEED := 8.0
const SPAWN_MENU_W := 552.0   ## --- wildlife menu ---  the M menu's scroller frame
const SPAWN_MENU_H := 520.0
const SPAWN_MENU_COLS := 3
const SPAWN_BTN_W := 174.0
const BLOCK_SPEED := 2.5
const ACCEL := 45.0          ## how fast we reach target speed
const DECEL := 24.0          ## lower than ACCEL -> "step into a stop" glide
const AIR_ACCEL := 12.0
const DASH_SPEED := 16.0
const DASH_TIME := 0.18
const JUMP_VELOCITY := 4.5
const STEP_HEIGHT := 0.45   ## auto-climb steps up to ~1/4 the player's height
## --- wedged in the timber (Lemon 2026-09-01: "I walked into a fallen tree and
## got stuck") --- how long you may ask to move, and get nowhere, before the
## body shoves itself clear. See _unwedge.
const UNSTICK_WINDOW := 0.7   ## seconds of asking
const UNSTICK_MOVED := 0.09   ## metres in that window that still count as moving
const UNSTICK_PROBE := 0.28   ## how far each of the 8 escape probes reaches
const UNSTICK_PUSH := 3.4     ## m/s of shove out of the pocket
const UNSTICK_HOP := 2.4      ## ...and up, because pockets have floors
const MOUSE_SENS := 0.0025

const SWING_TIME := 0.42
const HIT_AT := 0.22         ## damage lands AT the visual impact of the cut (p=0.52)
const ATTACK_STAMINA := 12.0
const DASH_STAMINA := 20.0

## --- THE COMMITTED STEP: dash INTO your own swing. Ctrl during a cut (or a
## cut started mid-dash) spends the dash on the blade instead of on your
## footwork — the body goes forward with the edge and the blow lands with all
## of your weight behind it. It costs a great deal of stamina and it cannot be
## taken back: you are committed to that line whether or not they move. ---
const COMMIT_STAMINA := 30.0     ## on TOP of the swing — this is the price
const COMMIT_DMG_MULT := 2.05    ## what a body's weight is worth
const COMMIT_REACH := 0.9        ## the step buys you this much extra range
const COMMIT_LOW_HP := 0.30      ## at or under this, it also feeds the other tree
const COMBO_RESET := 0.75    ## idle this long and the combo restarts at hit 1
const SHEATH_TIME := 0.40

## --- GOD MODE (scripts/GodEditor.gd -- F1) ---------------------------------
## The map-authoring mode. `god` pins health/stamina/thirst/breath and refuses
## every source of damage; `flying` is Minecraft flight (double-tap Space) with
## collision parked; `god_speed` is the scroll wheel, and it multiplies walking
## AND flying, so wheel-up is faster wherever you are and wheel-down comes back
## down to 1.0 = the ordinary walk.
const GOD_FLY_SPEED := 12.0    ## m/s at god_speed 1.0
const GOD_FLY_BOOST := 3.2     ## the SPACE toggle, while flying
const GOD_SPEED_MIN := 0.35
const GOD_SPEED_MAX := 24.0
const GOD_DOUBLE_TAP_MS := 320
var god := false
var flying := false
var god_speed := 1.0
var god_boost := false         ## SPACE toggle in god mode -- sticky, not held
var _space_boost_flip := false ## the first tap of a double tap flipped it
var godmode: GodEditor = null
var grass_lab: GrassLab = null   ## F3 -- the grass lab (scripts/GrassLab.gd)
var creator: CharacterCreator = null  ## Settings -> Dev Toolkit (scripts/CharacterCreator.gd)
var claude_chat: ClaudeChat = null   ## F4 -- Claude, riding along (scripts/ClaudeChat.gd)
var pad: Node = null             ## the gamepad translator (scripts/Pad.gd)
var _space_tap_ms := 0
var _god_mask_saved := -1      ## collision_mask parked while noclipping

## --- SPECTATOR MODE (scripts/EditorCam.gd) ---------------------------------
## `editing` means the camera has LEFT THE BODY. The character stands where you
## stepped out of them, collision_layer parked at 0 and EditorMode.active true,
## so nothing in the world can see, reach or hunt them; the editor camera flies
## on its own. Closing the editor puts you back in their head.
## `god_sticky` is the panel's GOD toggle: it decides whether the body you go
## BACK to is invulnerable. Spectating is invulnerable either way.
var editing := false
var god_sticky := false
var _editor_cam_mode := ""     ## the view you were using before you stepped out
var _god_layer_saved := -1     ## collision_layer parked while the body is out

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

var head: Node3D
var camera: Camera3D
var body_rig: Node3D
var leg_pivots: Array[Node3D] = []   ## visible legs — they stride with the gait
var viewmodel: Node3D
var sword_vm: Node3D    ## the held blade — rebuilt when a different sword is equipped
var hands_root: Node3D  ## every FP viewmodel hangs off this ONE node so the
						## Main Hand setting can mirror the whole kit (x = -1)
var cam_anim: Node3D    ## head -> cam_arm -> CAM_ANIM -> camera: the action
						## layer — swings, chops, draws and rummages LEAN the
						## lens without touching what bob/shake write to camera
var cam_punch := 0.0    ## impact impulse (landed hits) — decays fast
var pack_rig: Node3D    ## THE RUCKSACK on your back (always worn)
var bedroll_bundle: Node3D  ## the rolled bed strapped atop it (shown when owned)
var pack_reach := 0.0   ## 0..1 — hands are IN the pack (inventory open)

## --- THE ITEM WHEEL (Q): 8 slots of reach-without-looking. Hold Q in the
## world and drag toward a slot to use what rides there; in the inventory,
## TAP Q over an item to lash it to the first free slot, HOLD Q to choose
## exactly which slot it rides in. Saved with the character. ---
const WHEEL_SLOTS := 8
const WHEEL_R_WORLD := 165.0   ## the world radial: big, pinned to the screen centre
const WHEEL_R_PLACE := 92.0    ## the inventory slot-picker: compact, dropped at the cursor
var wheel: Array[String] = ["Wooden Shield", "Torch", "Bedroll", "Health Potion",
	"", "", "", ""]
var wheel_open := false          ## world: held-Q radial is up (look is frozen)
var wheel_place_open := false    ## inventory: held-Q slot picker is up
var _wheel_vec := Vector2.ZERO   ## accumulated mouse drag while the wheel is up
var _wheel_sel := -1
var _wheel_origin := Vector2.ZERO ## screen point the ring is drawn AND measured around
var _wheel_radius := WHEEL_R_WORLD
var _wheel_slot_box := Vector2(150, 26)
var _wheel_center_box := Vector2(240, 30)
var _wheel_slot_font := 16
var _wheel_center_font := 19
var _q_held := false
var _q_down_ms := 0
var _q_down_mouse := Vector2.ZERO ## where the cursor sat the instant Q went down
var _q_inv_idx := -1             ## the inventory row Q went down on
var wheel_panel: Control
var wheel_slot_labels: Array[Label] = []
var wheel_center: Label

const POTION_HEAL := 40.0        ## what the red draught gives back

var overload_label: Label        ## "~ overburdened ~" — the sprint thief, named
var _was_overweight := false
var _armor_fx: Node3D   ## fire/void weather on worn high-metal armor
var _armor_fx_mode := ""  ## "" | "fire" | "void" — rebuild only on change
var hip_sword: Node3D
var back_shield: Node3D ## stowed shield across the back — the offhand's scabbard
var left_arm: Node3D
var right_arm: Node3D
var tp_head: Node3D              ## third-person head (FP hides it — the camera lives inside)
var tp_helm: Node3D              ## worn helm, shown when the helmet slot is filled
var hair_meshes: Array[MeshInstance3D] = []   ## tuck away under the helm
var helm_meshes: Array[MeshInstance3D] = []   ## tinted by the helm's metal
var tp_torch: Node3D             ## body-held torch: the flame the world sees in TP
var tp_torch_light: OmniLight3D  ## its light — FP's offhand_light dies with the viewmodel
## Body-held gear (third person): the body wields real copies of what the
## hands hold — sword, shield, bow, pickaxe, axe — and the arms act out the
## swings/guards/draws from the same state the viewmodels animate from.
var tp_hand_r: Node3D            ## grip node at the right fist (weapons parent here)
var tp_sword: Node3D             ## rebuilt with the equipped material (like sword_vm)
var tp_pick: Node3D
var tp_axe: Node3D
var tp_shield: Node3D            ## strapped on the left forearm
var tp_bow: Node3D               ## held in the left fist, kept upright
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

## --- THE RUNNING VAULT (2026-09-14) -----------------------------------------
## A mantle you never press a button for. Sprint at a waist-high wall — a
## fence, a windowsill, a boulder, the lip of a trench — and you go OVER it
## without breaking stride, carrying most of your speed out the far side. It is
## the same machinery as the Space mantle (_try_climb / _update_climb) with
## tighter height bounds, a third of the duration, and an exit that is a stride
## rather than a stop. Anything taller than VAULT_MAX_H is still a real climb
## you have to ask for.
const VAULT_MIN_H := 0.50        ## below this _step_up already walks you over it
const VAULT_MAX_H := 1.35        ## about a hip — higher is a haul, not a hurdle
const VAULT_TIME := 0.34
const VAULT_STAMINA := 4.0       ## half a mantle: it is momentum doing the work
const VAULT_MIN_SPEED := 6.0     ## you have to actually be RUNNING at it — and
								 ## high enough that MIN_SPEED x KEEP still lands
								 ## you above a walk, so a hurdle never costs you
								 ## speed you would have had going round
const VAULT_KEEP := 0.88         ## fraction of that run speed you land with
var vaulting := false            ## this climb is a running vault, not a mantle
var _vault_exit := 0.0           ## m/s to leave the lip with
var _vault_cd := 0.0             ## no hurdling the same fence twice a frame

## --- THE SLIDE (2026-09-14) -------------------------------------------------
## Crouch at a sprint and you go down onto your hip and KEEP GOING, bleeding
## speed to friction instead of to the brakes. Jumping out of it keeps what is
## left, which is the whole point: sprint -> slide -> jump -> vault is meant to
## read as one continuous move rather than four inputs.
const SLIDE_MIN_SPEED := 6.0     ## a walk does not slide
const SLIDE_TIME := 0.9
const SLIDE_FRICTION := 5.5      ## m/s^2 the ground takes back
const SLIDE_BOOST := 1.9         ## the kick as you drop
const SLIDE_END_SPEED := 2.6     ## below this you are just crouching
const SLIDE_CD := 0.55
const SLIDE_STEER := 1.5         ## rad/s you can still aim it
const SLIDE_STAMINA := 5.0
const SLIDE_TILT := 4.0          ## degrees the lens lies over into it
var sliding := false
var slide_t := 0.0
var slide_cd := 0.0
var jump_queued := false         ## Space pressed — resolved next physics tick

var blocking := false
var committed := false       ## this swing is a dash-driven strike (see above)
var dash_timer := 0.0
var invuln_timer := 0.0
var hitstun_timer := 0.0     ## thrown out of your action when hit (unblocked)
var status_speed_mult := 1.0 ## Afflictions.gd: gummed / chilled — a slime left it on you
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
var _step_idx := -9999       ## [steps] which half-stride we are in; a change is a foot down
var land_dip := 0.0          ## soft knee-bend of the view after landing
var _was_on_floor := true
var _fall_speed := 0.0       ## how hard we were falling just before touchdown
var _fall_grace := false     ## F2 drop-in: the next landing is free
var _fall_grace_hold := 0.0  ## ...and the frame you drop in cannot spend it early

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
## What the last `Slumber.night()` returned, held between the blackout
## starting and the player getting up. Empty when nobody is asleep.
var _slept: Dictionary = {}
var level := 1

## One row per gain-log entry: {label, kind, amount, life}. A single array —
## the old four parallel arrays could drift apart and crash on an index the
## moment anything interrupted an append quartet mid-frame.
var log_rows: Array[Dictionary] = []

## --- Menus (M = mob spawner; Tab = Inventory | Stats | Progression) ---
const TAB_PANEL_SIZE := Vector2(840, 540)  ## every page shares this one size
var menu_open := ""              ## "", "map", "spawn", "tab"
var spawn_panel: PanelContainer
var tab_panel: PanelContainer
var tab_page := "inventory"      ## which page the Tab menu is showing
var tab_buttons := {}            ## page id -> header Button
var tab_pages := {}              ## page id -> page root Control
var points_badge: Label
var inv_cells: Array[Button] = []       ## the 9×N backpack grid cells
var inv_weight_label: Label
var inv_purse_label: Label              ## the coin purse (4 denominations)
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
## straps to the forearm, torch rides the same fist). The two ACCESSORY slots
## are Terraria-style trinket berths — nothing fills them yet (rings/charms
## come with later loot passes), but the paper doll shows them from day one.
const SLOT_ORDER: Array[String] = ["sword", "offhand", "offhand2", "back", "helmet", "chest",
	"arms", "pants", "shoes", "accessory1", "accessory2"]
const SLOT_NAMES := {
	"sword": "Right Hand", "offhand": "Left Hand", "offhand2": "Left Hand +",
	"back": "Back",
	"helmet": "Helmet", "chest": "Chest", "arms": "Arms",
	"pants": "Pants", "shoes": "Shoes",
	"accessory1": "Accessory 1", "accessory2": "Accessory 2",
}

## --- Backpack: Minecraft-style SLOTS on top of the weight limit. 9 wide,
## 3 rows to start — more backpacks later add rows (backpack_rows). A "slot"
## holds one STACK (items merge by name), so capacity = distinct item kinds. ---
const PACK_COLS := 9
var backpack_rows := 3
var inventory: Array[Dictionary] = []   ## the GRID only: {name, weight, count, slot [, material]}
var equipment := {}                     ## slot id -> the item Dictionary ITSELF
										## ({} = empty). TERRARIA RULES: a worn
										## thing is OUT of the grid and IN its
										## slot — equipping moves it, unequipping
										## moves it back. No index bookkeeping.
var hovered_item_idx := -1              ## inventory row under the mouse (B drops it; Q wheels it)
var inv_sets_box: VBoxContainer         ## one-click "Equip X set" buttons

## --- Dropped items (Q to toss from the inventory; look + E to reclaim) ---
var pickup_prompt: Label                ## "[E] Pick up ..." hint, bottom-center
var _drop_target: DroppedItem = null    ## the dropped item currently looked at
var _bed_target: Node3D = null          ## the bedroll under the gaze (E = pack up)
var _debris_target: RockDebris = null   ## a landed rock under the gaze (E = gather)
var _fire_target: Firepit = null        ## a fire pit under the gaze (E = light / feed)
var _carc_target: Dictionary = {}       ## a carcass record under the gaze (E = butcher)
var _cut_cd := 0.0                      ## seconds until the next cut can be taken
var _log_target: CarryLog = null        ## a felled log under the gaze (E = shoulder it)

## ------------------------- THE REACH-AND-GRAB -----------------------------
## Taking something off the ground is an ACT now, not a teleport into the pack.
## You drop into a crouch, the steel rides home, an OPEN HAND goes out to the
## thing, the fist closes on it, and the arm carries it back over the shoulder
## into the rucksack -- then the blade comes straight back out if it was out
## when you reached, and otherwise the arm just falls back to your side.
## LEFT CLICK does it as well as E, so long as the thing is inside GRAB_REACH;
## past that left click is still a swing, and E still snaps it up the old way.
const GRAB_REACH := 2.2          ## m from the waist -- an arm's length and a lean
const GRAB_T_DOWN := 0.30        ## crouch, and the blade rides home
const GRAB_T_OUT := 0.30         ## the open hand travels out to it
const GRAB_T_HOLD := 0.12        ## fingers close
const GRAB_T_BACK := 0.32        ## up and back over the shoulder, into the pack
const GRAB_T_UP := 0.28          ## stand, and the steel comes back out
const GRAB_ARM_OUT := 1.25       ## rotation.x at full reach (POSITIVE = forward)
const GRAB_ARM_FLARE := 0.30     ## elbow flares off the ribs on the way out
const GRAB_ARM_STOW := -2.05     ## hand up BEHIND the shoulder, at the pack flap
var reach_phase := ""             ## "" | "down" | "out" | "hold" | "back" | "up"
var reach_t := 0.0               ## seconds into the current phase
var reach_node: Node3D = null     ## the thing being taken, still out in the world
var reach_kind := ""              ## "item" | "debris" | "log"
var reach_spot := Vector3.ZERO    ## where it lay -- put back if the pack refuses
var reach_held := false           ## true once the fist has closed on it
var reach_redraw := false         ## the sword was drawn when you reached
var reach_was_crouch := false     ## the stance to come back up to
var reach_was_prone := false
## ------------------ THE PILE SWEEP (hold E) -------------------------------
## Tapping E takes the one thing you are looking at, exactly as before. KEEP
## E DOWN and, a third of a second later, everything of the SAME KIND lying
## around it starts coming in too, one every ninety milliseconds, until the
## pile is gone or you let go. Same kind means the same item name AND the
## same material, so a hold over a heap of iron ore does not sweep up the
## silver lying beside it, and the gain counter merges the lot into one
## "+9 Iron Ore" row. Nothing new is bound: the pad's Square already posts
## E's press and release, so this is a hold on the pad for free.
const GATHER_HOLD := 0.33        ## s of held E before the pile starts moving
const GATHER_RADIUS := 4.0       ## m from the waist -- a pile, not a field
const GATHER_STEP := 0.09        ## s between items, so it arrives as a stream
var _e_held := false             ## E is down right now
var _e_down_ms := 0              ## when it went down
var _gather_name := ""           ## item name the sweep is collecting
var _gather_mat := ""            ## ...and its material, so ores stay apart
var _gather_kind := ""           ## "" | "item" | "debris"
var _gather_t := 0.0             ## seconds until the next one comes in
var _gather_n := 0               ## how many this hold has taken
var reach_out := 0.0        ## 0..1 -- arm out at the ground
var reach_stow := 0.0         ## 0..1 -- arm back over the shoulder

## --- LOGS. Retired 2026-08-30: a log IS an inventory item now, and the stuff
## below is dead weight kept only so old saves and ~15 call sites still load.
## Look at one and press E to swing it up (four is all a back will take), and
## it rides there VISIBLY until something makes you let go. A shoulder is not
## a pocket: jump, climb, crouch, go prone, take a hit, or reach into your
## pack, and the whole load rolls off behind you and lies where it stops. ---
const MAX_CARRY_LOGS := 4
const LOG_STACK: Array[Vector3] = [      ## how a load sits across the shoulder
	Vector3(0.0, 0.0, 0.0), Vector3(-0.15, 0.03, 0.02),
	Vector3(-0.07, 0.19, -0.02), Vector3(0.08, 0.19, 0.03)]
var carried_logs: Array[Dictionary] = [] ## {length, radius, bark}
var log_rig: Node3D                      ## the visible load on the body
var log_label: Label                     ## "Logs 3/4" on the HUD

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
var kd_bounce := 0.0             ## ragdoll settle: the head bounces off the dirt and damps out
## --- MANHANDLED (the bear, mostly) ---
var grabbed_by: Node3D = null    ## a jaw has you: your body hangs off its grab_anchor()
var grab_t := 0.0
var pressed_by: Node3D = null    ## an animal's weight is on you: you can barely move
var press_t := 0.0

## --- Settings (Esc) — applied live, saved to user://settings.cfg ---
const SETTINGS_PATH := "user://settings.cfg"
## The blurb under the World row, rewritten as you pick. Indexed by
## GameMode.Mode — Peaceful, Normal, Hardcore.
const MODE_NOTES: Array[String] = [
	"Nothing starts a fight with you. The bear still rears up and huffs — it\njust never means it, unless you swing first. The caves still have things in\nthem: half the pack, noticing you late, every blow at 40%. Falls, fire and\nfalling timber still cost exactly what they cost. Wounds close three times faster.",
	"The world as it was built. Everything that wants to kill you is allowed to\ntry, and every number is the one it was tuned to.",
	"Normal, meaner — and you get one. Die and this save is SEALED: it can never\nbe loaded again, in this session or any other. New Run is the only way on, and\nit starts you with what you woke up with.",
]
var settings_panel: PanelContainer
var creative_panel: PanelContainer   ## G — every item in the game, one click away
var sky_panel: SkyMenu               ## ' — scrub the clock, force the weather
## M — the map. Loaded by path, not by class_name: Player is the one script
## MapPanel talks back to, and a name-level cycle between the two is exactly
## the kind of thing that turns into a parse error on a cold open.
const MapPanelScript := preload("res://scripts/MapPanel.gd")
const PadScript := preload("res://scripts/Pad.gd")
var map_panel: PanelContainer         ## M — the map of Maine
var set_rt := false              ## "ray-traced" lighting preset (SDFGI et al.)
var set_shadows := 1             ## 0 low / 1 medium / 2 high
var set_fullscreen := false
var set_vsync := true
var set_sens := 1.0              ## multiplier on MOUSE_SENS
var set_fov := 75.0
var set_hunch := true            ## the hunch: auto draw on aggro / auto sheathe when calm
var set_lefty := false           ## Main Hand: mirror the whole kit for southpaws
var set_blood := true            ## Blood: off swaps red for a neutral impact puff
var set_fall_dmg := false        ## Fall damage: OFF by default (Lemon, 2026-09-02).
								 ## Gates the hard-landing knockdown too -- that
								 ## was the half god mode did not already cover.
var set_clouds := 1              ## Clouds: 0 off / 1 painterly / 2 volumetric
var set_draw := 90.0             ## Draw Distance, m — how far the meadow reaches.
								 ## The grass streams across 78 km² now, so this
								 ## is the one number that decides what it costs:
								 ## area squares, so 45 -> 90 m is 4x the tufts.
								 ## GrassSystem.set_draw_distance() takes it.
var set_gamemode := 1            ## World: 0 Peaceful / 1 Normal / 2 Hardcore (GameMode.gd)
var gamemode_note: Label         ## the blurb under the World row, rewritten per mode
var _newborn := {}               ## the sheet you woke up with, snapshotted at the end
								 ## of _ready — Hardcore's "New Run" is this and nothing else
var _settings_widgets := {}      ## id -> {btns: [[value, Button]...]} or {label: Label}
var save_status: Label           ## "Last save: ..." line under the Save/Load row
const MENU_SCALE := 1.67         ## all menus render 67% larger (clamped to the screen)

## --- Offhand (left hand: shield / torch, cycled with Q) ---
const OH_REST_POS := Vector3(-0.30, -0.30, -0.52)
const OH_REST_ROT := Vector3(-4.0, 16.0, -8.0)
const OH_RAISE_TIME := 0.35      ## equip animation: lift up into view
var offhand_node: Node3D
var offhand_light: OmniLight3D   ## the torch flame's actual light
var offhand_shown := ""          ## item NAME currently displayed ("" none)
var offhand_shown2 := ""         ## companion displayed alongside (torch w/ shield)
var offhand_raise := 0.0         ## 0 = lowered off-screen, 1 = fully up

## --- Darkness watch: in a cave (or out at night) the torch comes out on its
## own, sharing the arm with the shield — and while it's dark, SHEATHING only
## puts the sword away: shield + torch stay raised so the guard never drops. ---
var _in_dark := false
var _dark_prev_names: Array[String] = []  ## offhand loadout from before the dark
var _dark_manual := false                 ## player cycled by hand in the dark — respect it

var grass_hidden := false        ## standing in TALL grass (GrassSystem writes
var hidden_label: Label          ## this) — calm mobs barely notice you

## --- THE GROUND UNDER YOU (2026-09-14, scripts/Locomotion.gd) ---------------
## Lemon: "make the movement more dynamic and flowy, I also want the movement
## to slow in tall grass". The model itself is static functions in Locomotion;
## these are the live numbers Player carries between frames.
var wade := 0.0                  ## 0..1 how deep the meadow is at your shins
var _bank := 0.0                 ## smoothed turn lean, -1 .. 1 (+ = turning left)
var _fov_extra := 0.0            ## degrees of speed push on top of set_fov
var _surface_mult := 1.0         ## what the ground family does to your speed
var _footing_t := 0.0            ## 10 Hz poll clock — the ground does not change
								 ## between two frames and both reads cost more
								 ## than the lerp they feed
var _grass_sys: Node = null      ## cached GrassSystem (group "grass_system")

## --- Mount hearts on the HUD: while riding, the horse's ♥♥♡ tally lives
## under your own bars — an enemy catching your mount shows up HERE (the
## over-head pips are for loose horses; Horse._take_heart_hit routes it). ---
var mount_hearts: Label
var mount_heart_flash := 0.0     ## Horse sets this when the mount takes a hit

## --- Blackout / cutscene lock: loading screens and the bed animations own
## the body. No input of any kind gets through while this is true. ---
var input_locked := false
var sleep_phase := ""            ## "" | "lying" | "black" | "rising"

## --- Camera modes (V): first person <-> third person over a shoulder.
## Short press in FP = out to the RIGHT shoulder; short press in TP = swap
## shoulders; HOLD 1.5 s in TP = glide back into first person. Every switch
## animates (the arm lerps), walls pull the perch in, last setting persists. ---
var cam_mode := "fp"             ## "fp" | "tp" (saved to settings)
var cam_snap := 0.0              ## >0 right after entering TP: the perch glides
								 ## out FAST so the lens never lingers at eye
								 ## height, seeing from where the head should be

## --- SKELETON + RAGDOLL (CreatureSkin) ---
## The third-person body is baked into a Skeleton3D + one skinned PSX mesh
## after _build_body; the first-person arms under the camera stay as they are.
## Knockdowns in third person hand the body to the ragdoll.
var body_skin: CreatureSkin = null
var mass := 80.0
var cam_shoulder := 1.0          ## +1 right, -1 left (saved)
var cam_arm: Node3D              ## head -> cam_arm -> camera (the TP offset)
var _v_held := false
var _v_down_ms := 0
var _v_consumed := false

## --- Stances (C toggles crouch, X toggles prone): each step down slower,
## lower, harder to spot. Crouched in tall grass = wake radius ×0.35; PRONE
## in it = ×0.22 — a shadow flat against the earth. Going prone has weight:
## the eyes sink slow with a settling roll. (Collision doesn't shrink yet —
## TODO(design): crawl-under-gaps needs a clearance check to stand.) ---
var crouching := false           ## true in crouch AND prone (stealth reads this)
var prone := false
var _eye_h := 1.62               ## eased eye height (1.62 / 1.08 / 0.45)
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
## Carried UPRIGHT like the sword (haft vertical, head up); the swing arcs
## were authored on the old forward-tilted base, so swings BLEND from the
## upright carry into that base over their first fifth — same trick the
## sword uses (the raise becomes part of the chop).
const PICK_REST_POS := Vector3(0.32, -0.30, -0.50)
const PICK_REST_ROT := Vector3(78.0, -10.0, 6.0)
const PICK_BASE_POS := Vector3(0.32, -0.34, -0.52)   ## swing-arc origin (old rest)
const PICK_BASE_ROT := Vector3(18.0, -14.0, 6.0)
var pick_vm: Node3D              ## pickaxe viewmodel (right hand + haft + head)
var pick_swinging := false
var pick_t := 0.0
var pick_hit_done := false
var pick_start_rot := Vector3.ZERO   ## pose captured when a chop begins
var pick_start_pos := Vector3.ZERO
var vein_hint_cd := 0.0          ## rate-limits the "needs a pickaxe" nudge
var axe_hint_cd := 0.0           ## rate-limits the "needs an axe" nudge

## --- War Axe (weapon 4): a heavy one-handed cleaver. Slower and harder-
## hitting than the sword, no combo ladder — two ALTERNATING committed swings
## (overhead chop / horizontal cleave), each with its own full animation.
## Honest iron: no material matchups yet.
## TODO(design): fold the axe into the metal system + weapon styles (step 4/5);
## should it eventually chop trees once TreeLife lands? ---
const AXE_TIME := 0.58           ## one full swing (DEX shortens it)
const AXE_WINDUP := 0.24         ## fraction spent hauling it back (= the
								 ## chamber beat in _pose_keys, so the body's
								 ## arm and the viewmodel stay in step)
const AXE_HIT_AT := 0.52         ## damage lands AT the visual impact — which
								 ## is now the MIDDLE of the arc, where the
								 ## edge is actually passing through the target
const AXE_STAMINA := 15.0
const AXE_RANGE := 2.8
const AXE_DMG_MULT := 1.35       ## × base_damage (STR rides along)
## How far off the trunk's centreline the crosshair has to sit before the
## wood gets to choose the shoulder. Inside this the tree reads as square-on
## and the swing goes back to alternating. Metres, measured ACROSS the trunk.
const AXE_SIDE_DEADZONE := 0.04
## Carried UPRIGHT like the sword; swings blend out of the vertical carry
## into arcs authored on the old forward-tilted base (see pickaxe note).
const AXE_REST_POS := Vector3(0.34, -0.32, -0.48)
const AXE_REST_ROT := Vector3(80.0, -10.0, 6.0)
const AXE_BASE_POS := Vector3(0.34, -0.34, -0.50)    ## swing-arc origin (old rest)
## Pitch here used to be 22 deg — the whole arc started nose-down, which is why
## even a flat stroke read as a chop. A feller's cut is LEVEL: the haft stays
## roughly parallel to the ground and the work is all in the hips.
const AXE_BASE_ROT := Vector3(6.0, -16.0, 4.0)

## Two felling strokes, alternating, each with the sword's three beats:
## [chamber, impact, follow-through] as [rot_offset, pos_offset] from the base
## above, run through the shared _pose_keys curve.
##
## THE HEAD LEADS THE HAND. That is the whole fix. The old arc yawed the axe
## one way while the hand travelled the other, so the head trailed BACKWARD
## through the sweep — hauled left, thrown right, edge dragging behind the
## wrist the whole way. Read the numbers as a pair: on the forehand, yaw runs
## -80 -> -4 -> +72 (right, through centre, out to the left) while the hand
## runs +0.30 -> +0.02 -> -0.30 (the same trip), and z drives to -0.32 at the
## impact so the whole thing travels AWAY from the camera where the swing
## should live. The backhand is the mirror.
##
## HORIZONTAL (Lemon 2026-09-01: "more from the side, like a horizontal
## swing"). Pitch used to run 40 -> -12 -> -30 and the hand fell 0.12 -> -0.16:
## a felling chop, driven down. It is now nearly LEVEL — pitch 12 -> -4 -> -10,
## hand 0.03 -> -0.02 -> -0.03 — so the head travels flat across the cut at the
## height you are aiming at, and everything that used to be vertical travel has
## gone into a WIDER lateral sweep instead. The wedge in the trunk is a
## horizontal V; the stroke that makes it should be too.
const AXE_KEYS := [
	[  ## forehand: coiled out to the RIGHT, whipped flat across to the LEFT
		[Vector3(12.0, -80.0, -14.0), Vector3(0.30, 0.03, 0.12)],
		[Vector3(-4.0, -4.0, -4.0), Vector3(0.02, -0.02, -0.32)],
		[Vector3(-10.0, 72.0, 12.0), Vector3(-0.30, -0.03, -0.10)],
	],
	[  ## backhand: coiled out to the LEFT, whipped flat across to the RIGHT
		[Vector3(11.0, 82.0, 16.0), Vector3(-0.28, 0.03, 0.12)],
		[Vector3(-4.0, 4.0, 4.0), Vector3(-0.02, -0.02, -0.32)],
		[Vector3(-9.0, -74.0, -12.0), Vector3(0.32, -0.03, -0.10)],
	],
]
var axe_vm: Node3D               ## axe viewmodel (right hand + haft + head)
var axe_swinging := false
var axe_t := 0.0
var axe_hit_done := false
var axe_side := 0                ## alternates: 0 = forehand sweep (R->L), 1 = backhand (L->R)
var axe_start_rot := Vector3.ZERO    ## pose captured when a swing begins
var axe_start_pos := Vector3.ZERO

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
	collision_layer = 1
	collision_mask = 1 | 2   ## the world, and the creatures on layer 2 (Enemy._ready)
	_build_body()
	body_skin = CreatureSkin.bake(self, {"tile": "cloth", "mass": mass, "exclude": [head]})
	_build_hud()
	_load_settings()
	_apply_settings()
	_refresh_derived(true)
	## You wake up with the blade on your hip, not in your fist. Nothing out
	## here has threatened you yet — and a drawn sword should MEAN something.
	## (Alt draws it; the Hunch pulls it the instant anything turns hostile.)
	sheathed = true
	sheath_t = 1.0
	## Stick to stairs going down, so stepping off small ledges doesn't launch you.
	floor_snap_length = STEP_HEIGHT
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	## THE CONTROLLER (scripts/Pad.gd). It posts the same key and mouse events
	## the keyboard does, so there is still only one definition of every action;
	## the sticks are the only thing it has to do for itself.
	pad = PadScript.new()
	pad.name = "Pad"
	add_child(pad)
	pad.player = self
	## THE NEWBORN SNAPSHOT: exactly what you woke up with, taken before the
	## world has had a chance to happen to you. Hardcore's "New Run" restores
	## this dictionary and nothing else (see _on_new_run_pressed).
	_newborn = save_state()


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
	var gold_col := Color(0.50, 0.42, 0.22)
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
	_box(s, Vector3(0.26, 0.05, 0.05), gold_col, Vector3(0, 0, -0.05))                        ## crossguard
	_box(s, Vector3(0.04, 0.04, 0.16), dark, Vector3(0, 0, 0.06))                          ## grip
	_box(s, Vector3(0.06, 0.06, 0.05), gold_col, Vector3(0, 0, 0.16))                          ## pommel
	## The high metals have WEATHER (Materials.blade_fx): the fire metals shed
	## pixel flame and orange lamplight, mithril burns white, adamant amber,
	## and voidsteel wears a slow pixel void crawling the steel.
	var fx: Dictionary = Materials.blade_fx(mat_id)
	if not fx.is_empty():
		var fl := OmniLight3D.new()
		fl.light_color = fx["light"]
		fl.light_energy = float(fx["energy"])
		fl.omni_range = float(fx["range"])
		fl.shadow_enabled = false
		fl.position = Vector3(0, 0, -0.55)
		s.add_child(fl)
		if bool(fx["fire"]):
			s.add_child(_pixel_weather(true, Vector3(0.05, 0.06, 0.50), Vector3(0, 0, -0.55)))
		if bool(fx["void"]):
			s.add_child(_pixel_weather(false, Vector3(0.06, 0.08, 0.50), Vector3(0, 0, -0.55)))
	return s


func _pixel_weather(fire: bool, extents: Vector3, at: Vector3) -> CPUParticles3D:
	## Our no-texture particle language: little emissive CUBES.
	##   fire — embers that rise and gutter, in WORLD space so a swing leaves
	##     a torn ribbon of flame hanging in the air behind the edge.
	##   void — the opposite of that: slow, heavy, LOCAL, purple-to-black
	##     squares crawling tipward along the steel like it's leaking somewhere.
	var p := CPUParticles3D.new()
	p.amount = 16 if fire else 12
	p.lifetime = 0.7 if fire else 1.4
	p.local_coords = not fire
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.position = at
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * (0.030 if fire else 0.042)
	p.mesh = bm
	if fire:
		p.direction = Vector3.UP
		p.spread = 25.0
		p.gravity = Vector3(0, 1.5, 0)
		p.initial_velocity_min = 0.1
		p.initial_velocity_max = 0.4
	else:
		p.direction = Vector3(0, 0, -1)  ## flows toward the tip
		p.spread = 8.0
		p.gravity = Vector3(0, -0.25, 0)
		p.initial_velocity_min = 0.12
		p.initial_velocity_max = 0.30
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var grad := Gradient.new()
	if fire:
		grad.set_color(0, Color(1.0, 0.78, 0.25, 1.0))
		grad.set_color(1, Color(0.8, 0.12, 0.02, 0.0))
		grad.add_point(0.45, Color(1.0, 0.38, 0.06, 0.9))
	else:
		grad.set_color(0, Color(0.62, 0.30, 0.95, 0.9))
		grad.set_color(1, Color(0.04, 0.0, 0.10, 0.0))
		grad.add_point(0.55, Color(0.28, 0.08, 0.48, 0.8))
	p.color_ramp = grad
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.10) if fire else Color(0.5, 0.2, 0.9)
	mat.emission_energy_multiplier = 1.6
	p.material_override = mat
	return p


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
	## HEAD BARRIER: the capsule's cap narrows toward the top, which let the
	## camera be walked into overhangs (and, pressed hard enough against thin
	## cave walls, peek out of the world). A full-width sphere at eye level
	## makes the head as solid as the shoulders.
	var head_col := CollisionShape3D.new()
	var head_sphere := SphereShape3D.new()
	head_sphere.radius = 0.34
	head_col.shape = head_sphere
	head_col.position = Vector3(0, 1.56, 0)
	add_child(head_col)

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

	## The load on the right shoulder — filled by _refresh_log_rig when you
	## hoist a felled log. Rides the body, so it reads in first AND third person.
	log_rig = Node3D.new()
	body_rig.add_child(log_rig)
	log_rig.position = Vector3(0.30, 1.38, 0.0)
	log_rig.rotation_degrees = Vector3(-6.0, 0.0, -9.0)

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

	## --- THE RUCKSACK: home rides your back. An old campaigner's rucksack in
	## worn leather and canvas — top-rolled flap, front pocket with a paler
	## patch sewn on, shoulder straps with brass buckles, a battered tin cup
	## dangling off the bottom corner — and a lashing spot on top where the
	## BEDROLL straps on whenever one is in the pack (shown/hidden live).
	## The stowed shield (z 0.24) lies OVER it, the way hikers actually stack. ---
	pack_rig = Node3D.new()
	body_rig.add_child(pack_rig)
	pack_rig.position = Vector3(0, 1.04, 0.185)
	var leath := Color(0.30, 0.22, 0.14)
	var canvas := Color(0.38, 0.33, 0.24)
	var brass := Color(0.55, 0.45, 0.22)
	_box(pack_rig, Vector3(0.34, 0.40, 0.15), leath, Vector3(0, 0, 0))                     ## main bag
	_box(pack_rig, Vector3(0.36, 0.13, 0.17), canvas, Vector3(0, 0.24, 0.0), Vector3(-8, 0, 0))  ## rolled top flap
	_box(pack_rig, Vector3(0.24, 0.17, 0.05), leath.darkened(0.12), Vector3(0, -0.07, 0.095))    ## front pocket
	_box(pack_rig, Vector3(0.09, 0.075, 0.01), Color(0.55, 0.48, 0.36), Vector3(0.05, -0.05, 0.125))  ## the sewn patch
	_box(pack_rig, Vector3(0.07, 0.15, 0.11), leath.darkened(0.06), Vector3(-0.20, 0.02, 0.0))  ## side pouch
	for bx: float in [-0.09, 0.09]:
		_box(pack_rig, Vector3(0.045, 0.16, 0.02), leath.darkened(0.2), Vector3(bx, -0.10, 0.085))  ## flap straps
		_box(pack_rig, Vector3(0.05, 0.03, 0.03), brass, Vector3(bx, -0.16, 0.09), Vector3.ZERO, true)  ## buckles
		## Shoulder straps arcing over the trapezius to the chest.
		_box(body_rig, Vector3(0.05, 0.05, 0.30), leath.darkened(0.2), Vector3(bx, 1.345, 0.02), Vector3(62, 0, 0))
	## The battered tin cup, hung by its ear off the bottom corner.
	var cup := Node3D.new()
	pack_rig.add_child(cup)
	cup.position = Vector3(0.16, -0.235, 0.03)
	cup.rotation_degrees = Vector3(0, 0, -14)
	_box(cup, Vector3(0.075, 0.08, 0.075), Color(0.62, 0.64, 0.66), Vector3.ZERO, Vector3.ZERO, true)
	_box(cup, Vector3(0.02, 0.045, 0.02), Color(0.62, 0.64, 0.66), Vector3(0.05, 0.015, 0), Vector3.ZERO, true)
	## The bedroll, rolled tight and lashed on top (Bedroll.gd's own colors).
	bedroll_bundle = Node3D.new()
	pack_rig.add_child(bedroll_bundle)
	bedroll_bundle.position = Vector3(0, 0.345, 0.0)
	_box(bedroll_bundle, Vector3(0.42, 0.115, 0.115), Color(0.34, 0.24, 0.15), Vector3.ZERO)  ## the roll
	_box(bedroll_bundle, Vector3(0.43, 0.05, 0.12), Color(0.22, 0.24, 0.38), Vector3(0, 0.035, 0))  ## blanket showing
	for lx: float in [-0.13, 0.13]:
		_box(bedroll_bundle, Vector3(0.03, 0.13, 0.13), leath.darkened(0.25), Vector3(lx, 0, 0))  ## lashings
	bedroll_bundle.visible = false

	## --- Third-person HEAD: shown only from outside (in first person the
	## camera literally lives inside it). Sits on a neck pivot so it can nod
	## with your gaze (_update_camera_arm tips it as you look up and down). ---
	tp_head = Node3D.new()
	body_rig.add_child(tp_head)
	tp_head.position = Vector3(0, 1.44, 0)
	var hair := Color(0.17, 0.12, 0.08)
	_box(tp_head, Vector3(0.24, 0.26, 0.25), skin, Vector3(0, 0.14, 0))            ## the head
	_box(tp_head, Vector3(0.05, 0.05, 0.04), skin, Vector3(0, 0.10, -0.14))        ## nose
	hair_meshes.append(_box(tp_head, Vector3(0.26, 0.09, 0.27), hair, Vector3(0, 0.295, 0.01)))  ## crown
	hair_meshes.append(_box(tp_head, Vector3(0.26, 0.20, 0.08), hair, Vector3(0, 0.17, 0.125)))  ## back
	tp_head.visible = false
	## The HELM (helmet slot): an open-faced cap with a nose guard, tinted by
	## its metal in _apply_armor_visuals — hair tucks away underneath it.
	tp_helm = Node3D.new()
	tp_head.add_child(tp_helm)
	helm_meshes.append(_box(tp_helm, Vector3(0.29, 0.13, 0.30), armor, Vector3(0, 0.295, 0), Vector3.ZERO, true))    ## cap
	helm_meshes.append(_box(tp_helm, Vector3(0.29, 0.18, 0.06), armor, Vector3(0, 0.17, 0.135), Vector3.ZERO, true)) ## back guard
	helm_meshes.append(_box(tp_helm, Vector3(0.05, 0.15, 0.03), armor, Vector3(0, 0.185, -0.14), Vector3.ZERO, true)) ## nose guard
	tp_helm.visible = false

	## --- Body-held TORCH (third person): the floating first-person hands hide
	## from outside, which used to take the torch's LIGHT with them. The brand
	## rides the body's left fist instead — same flame, same flicker, and the
	## world stays lit when the camera steps out (_update_offhand drives it). ---
	tp_torch = Node3D.new()
	left_arm.add_child(tp_torch)
	tp_torch.position = Vector3(0, -0.50, 0.02)      ## in the striding hand
	tp_torch.rotation_degrees = Vector3(-14, 0, 0)   ## tipped a touch forward
	var t_wood := Color(0.35, 0.24, 0.13)
	_box(tp_torch, Vector3(0.045, 0.42, 0.045), t_wood, Vector3(0, 0.14, -0.02))               ## stick
	_box(tp_torch, Vector3(0.07, 0.08, 0.07), Color(0.12, 0.08, 0.05), Vector3(0, 0.36, -0.02)) ## char
	var t_ember := _box(tp_torch, Vector3(0.075, 0.05, 0.075), Color(1.0, 0.45, 0.10), Vector3(0, 0.41, -0.02))
	var t_emat := t_ember.material_override as StandardMaterial3D
	t_emat.emission_enabled = true
	t_emat.emission = Color(1.0, 0.45, 0.10)
	t_emat.emission_energy_multiplier = 2.0
	var t_flame := _box(tp_torch, Vector3(0.065, 0.13, 0.065), Color(1.0, 0.72, 0.25), Vector3(0, 0.50, -0.02))
	var t_fmat := t_flame.material_override as StandardMaterial3D
	t_fmat.emission_enabled = true
	t_fmat.emission = Color(1.0, 0.62, 0.20)
	t_fmat.emission_energy_multiplier = 3.5
	tp_torch_light = OmniLight3D.new()
	tp_torch_light.light_color = Color(1.0, 0.66, 0.32)
	tp_torch_light.light_energy = 1.25
	tp_torch_light.omni_range = 9.0
	tp_torch_light.shadow_enabled = false
	tp_torch_light.position = Vector3(0, 0.52, -0.02)
	tp_torch.add_child(tp_torch_light)
	tp_torch.visible = false

	## --- Third-person HELD GEAR: real copies of the viewmodel weapons in the
	## body's fists, so from outside you SEE what you're swinging. The grip
	## sits the -z-built weapons nearly SQUARE out of the closed fist (a real
	## grip, not laid along the forearm): at the carry the blade rides forward-
	## low at the side, at the chamber the tip drops behind the shoulder, and
	## the whip drives it out FRONT at impact. The old -115 tilt laid every
	## weapon 25 degrees BEHIND the hanging arm, which is why the body held
	## its sword behind itself and every cut read as swinging backward.
	## (_update_body_arms poses the arms; _update_tp_gear picks what's shown.)
	tp_hand_r = Node3D.new()
	right_arm.add_child(tp_hand_r)
	tp_hand_r.position = Vector3(0, -0.52, 0.0)
	tp_hand_r.rotation_degrees = Vector3(-20, 0, 0)
	tp_sword = _make_sword(tp_hand_r, Vector3.ZERO, _sword_material_id())
	tp_sword.visible = false
	## Pickaxe: haft + twin-spike head (the viewmodel's boxes, minus the hand).
	var g_wood := Color(0.34, 0.23, 0.13)
	var g_iron := Color(0.36, 0.37, 0.40)
	tp_pick = Node3D.new()
	tp_hand_r.add_child(tp_pick)
	_box(tp_pick, Vector3(0.05, 0.05, 0.62), g_wood, Vector3(0, 0, -0.26))
	_box(tp_pick, Vector3(0.07, 0.09, 0.12), g_iron, Vector3(0, 0, -0.56), Vector3.ZERO, true)
	_box(tp_pick, Vector3(0.045, 0.26, 0.06), g_iron, Vector3(0, -0.13, -0.60), Vector3(-16, 0, 0), true)
	_box(tp_pick, Vector3(0.045, 0.20, 0.06), g_iron, Vector3(0, 0.11, -0.58), Vector3(14, 0, 0), true)
	tp_pick.visible = false
	## War axe: haft + broad wedge + back spike (same anatomy as the viewmodel).
	var g_haft := Color(0.30, 0.20, 0.11)
	var g_edge := Color(0.58, 0.60, 0.64)
	tp_axe = Node3D.new()
	tp_hand_r.add_child(tp_axe)
	_box(tp_axe, Vector3(0.055, 0.055, 0.66), g_haft, Vector3(0, 0.02, -0.34))
	_box(tp_axe, Vector3(0.07, 0.10, 0.13), g_edge, Vector3(0, 0.02, -0.64), Vector3.ZERO, true)
	_box(tp_axe, Vector3(0.045, 0.34, 0.16), g_edge, Vector3(0, -0.14, -0.66), Vector3(-8, 0, 0), true)
	_box(tp_axe, Vector3(0.04, 0.40, 0.05), g_edge, Vector3(0, -0.16, -0.73), Vector3(-8, 0, 0), true)
	_box(tp_axe, Vector3(0.05, 0.07, 0.10), g_edge, Vector3(0, 0.06, -0.58), Vector3(14, 0, 0), true)
	tp_axe.visible = false
	## Shield: strapped across the LEFT forearm (counter-tilted while raised so
	## the boards keep facing the threat — see _update_tp_gear).
	var g_boards := Color(0.38, 0.26, 0.14)
	var g_rim := Color(0.24, 0.16, 0.09)
	tp_shield = Node3D.new()
	left_arm.add_child(tp_shield)
	tp_shield.position = Vector3(-0.03, -0.38, -0.06)
	_box(tp_shield, Vector3(0.34, 0.44, 0.045), g_boards, Vector3.ZERO)
	_box(tp_shield, Vector3(0.44, 0.30, 0.045), g_boards, Vector3.ZERO)
	_box(tp_shield, Vector3(0.36, 0.46, 0.02), g_rim, Vector3(0, 0, -0.028))
	_box(tp_shield, Vector3(0.10, 0.10, 0.07), Color(0.60, 0.63, 0.68), Vector3(0, 0, -0.05), Vector3.ZERO, true)
	tp_shield.visible = false
	## Bow: in the left fist, counter-rotated upright while the arm points.
	tp_bow = Node3D.new()
	left_arm.add_child(tp_bow)
	tp_bow.position = Vector3(0, -0.50, 0.0)
	var g_bow := Color(0.30, 0.20, 0.11)
	_box(tp_bow, Vector3(0.05, 0.15, 0.06), Color(0.16, 0.11, 0.07), Vector3.ZERO)
	_box(tp_bow, Vector3(0.04, 0.30, 0.05), g_bow, Vector3(0, 0.20, -0.03), Vector3(-13, 0, 0))
	_box(tp_bow, Vector3(0.04, 0.30, 0.05), g_bow, Vector3(0, -0.20, -0.03), Vector3(13, 0, 0))
	_box(tp_bow, Vector3(0.008, 0.72, 0.008), Color(0.85, 0.82, 0.72), Vector3(0, 0, -0.10))
	tp_bow.visible = false

	## --- Head + camera ---
	head = Node3D.new()
	head.position = Vector3(0, 1.62, 0)
	add_child(head)
	## head -> cam_arm -> camera: everything that already writes
	## camera.position (bob, shake, climb dip) keeps working untouched — the
	## third-person offset lives on the arm BETWEEN them.
	cam_arm = Node3D.new()
	head.add_child(cam_arm)
	## The ACTION layer rides between arm and lens: everything that already
	## writes camera.position (bob, shake, climb dip) keeps working untouched,
	## while swings/chops/draws lean THIS node (_update_action_camera).
	cam_anim = Node3D.new()
	cam_arm.add_child(cam_anim)
	camera = Camera3D.new()
	cam_anim.add_child(camera)
	camera.current = true
	## [terrain] far plane: Katahdin is five kilometres out; the default
	## 4000 m far plane clips the ranges off the horizon.
	camera.far = 9000.0
	camera.near = 0.02  ## tight near plane: hugging a cave wall can't poke
						## the lens through it and show the void beyond

	## HANDS ROOT: every first-person viewmodel hangs off this one node.
	## The Main Hand setting mirrors it (scale.x = -1) — sword to the left
	## fist, shield to the right, every authored pose and swing playing back
	## mirrored — without touching a single animation constant.
	hands_root = Node3D.new()
	camera.add_child(hands_root)

	## --- First-person viewmodel: main hand + held sword (attached to camera). ---
	viewmodel = Node3D.new()
	hands_root.add_child(viewmodel)
	_box(viewmodel, Vector3(0.10, 0.10, 0.13), skin, Vector3(0, 0, 0.02))          ## hand
	forearm_mesh = _box(viewmodel, Vector3(0.09, 0.09, 0.30), armor, Vector3(0, -0.05, 0.18), Vector3(8, 0, 0))  ## forearm
	sword_vm = _make_sword(viewmodel, Vector3(0, 0.02, -0.04), _sword_material_id())
	viewmodel.position = vm_ready_pos
	viewmodel.rotation_degrees = vm_ready_rot

	## --- Offhand viewmodel: left hand holding the shield / torch. ---
	offhand_node = Node3D.new()
	hands_root.add_child(offhand_node)
	offhand_node.position = OH_REST_POS + Vector3(-0.10, -0.42, 0.10)  ## starts lowered
	offhand_node.rotation_degrees = OH_REST_ROT
	offhand_node.visible = false

	## --- Bow viewmodel (weapon 2): left fist on the grip, arrow on the string. ---
	bow_vm = Node3D.new()
	hands_root.add_child(bow_vm)
	bow_vm.position = Vector3(-0.26, -0.36, -0.52)
	bow_vm.rotation_degrees = Vector3(-6.0, 24.0, -14.0)
	bow_vm.visible = false
	_build_bow_mesh()

	## --- Pickaxe viewmodel (weapon 3): right hand on a haft, iron head. ---
	pick_vm = Node3D.new()
	hands_root.add_child(pick_vm)
	pick_vm.position = PICK_REST_POS
	pick_vm.rotation_degrees = PICK_REST_ROT
	pick_vm.visible = false
	_build_pick_mesh()

	## --- War axe viewmodel (weapon 4). ---
	axe_vm = Node3D.new()
	hands_root.add_child(axe_vm)
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
	var wrap_col := Color(0.20, 0.14, 0.09)
	var iron := Color(0.58, 0.60, 0.64)
	_box(axe_vm, Vector3(0.10, 0.10, 0.13), skin, Vector3(0, 0, 0.02))                          ## hand
	_box(axe_vm, Vector3(0.09, 0.09, 0.30), armor, Vector3(0, -0.05, 0.18), Vector3(8, 0, 0))   ## forearm
	_box(axe_vm, Vector3(0.055, 0.055, 0.66), wood, Vector3(0, 0.02, -0.34))                    ## haft (-z)
	_box(axe_vm, Vector3(0.06, 0.06, 0.10), wrap_col, Vector3(0, 0.02, -0.06))                      ## grip wrap
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
	var th := _make_bar(6.0, Color(0.40, 0.66, 0.92))    ## [water] thirst (blue)
	thirst_bar = th[0]
	thirst_fill = th[1]
	thirst_bar.modulate.a = 0.10
	var wm := _make_bar(6.0, Color(0.92, 0.62, 0.34))    ## [exposure] warmth (amber)
	warmth_bar = wm[0]
	warmth_fill = wm[1]
	warmth_bar.modulate.a = 0.10
	var br := _make_bar(5.0, Color(0.75, 0.92, 1.0))     ## [water] breath (pale)
	breath_bar = br[0]
	breath_fill = br[1]
	breath_bar.modulate.a = 0.0
	breath_bar.visible = false
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

	## The mount's hearts (saddle only): the horse's wellbeing rides your HUD.
	mount_hearts = Label.new()
	mount_hearts.add_theme_font_size_override("font_size", 24)
	mount_hearts.modulate = Color(1.0, 0.36, 0.42)
	mount_hearts.visible = false
	mount_hearts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(mount_hearts)

	## The sprint thief, named on screen (visible while over the carry limit).
	overload_label = Label.new()
	overload_label.add_theme_font_size_override("font_size", 15)
	overload_label.modulate = Color(1.0, 0.72, 0.38, 0.85)
	overload_label.visible = false
	overload_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(overload_label)

	## What's riding on your shoulder right now.
	log_label = Label.new()
	log_label.add_theme_font_size_override("font_size", 16)
	log_label.modulate = Color(0.86, 0.78, 0.58, 0.85)
	log_label.visible = false
	log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(log_label)

	## "~ hidden ~" whisper while crouched in tall grass.
	hidden_label = Label.new()
	hidden_label.text = "~ hidden ~"
	hidden_label.add_theme_font_size_override("font_size", 16)
	hidden_label.modulate = Color(0.75, 0.85, 0.65, 0.75)
	hidden_label.visible = false
	hidden_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(hidden_label)

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
	_build_creative_menu()
	## The sky menu builds itself (scripts/SkyMenu.gd) — Player only has to
	## hang it on the HUD and treat it like the other panels.
	sky_panel = SkyMenu.new()
	hud_layer.add_child(sky_panel)
	## M — the map builds itself too (scripts/MapPanel.gd); it only needs to
	## know whose arrow to draw and whose god flag to ask about.
	map_panel = MapPanelScript.new()
	hud_layer.add_child(map_panel)
	map_panel.player = self
	## The god editor builds itself too (scripts/GodEditor.gd) -- F1 opens it.
	godmode = GodEditor.new()
	hud_layer.add_child(godmode)
	## The grass lab builds itself too (scripts/GrassLab.gd) -- F3 opens it.
	grass_lab = GrassLab.new()
	hud_layer.add_child(grass_lab)
	## The character creator / dev toolkit (scripts/CharacterCreator.gd):
	## Settings -> Dev Toolkit -> Character Creator opens it as menu "creator".
	creator = CharacterCreator.new()
	creator.player = self
	hud_layer.add_child(creator)
	## Claude rides along too (scripts/ClaudeChat.gd) -- F4 opens the chat.
	claude_chat = ClaudeChat.new()
	hud_layer.add_child(claude_chat)
	claude_chat.player = self
	_build_wheel_ui()


func _unhandled_input(event: InputEvent) -> void:
	if input_locked:
		return  ## blackout / bed animation — even the eyes stay still
	## SPECTATOR: mouse motion turns the CAMERA, not the parked body. Returning
	## here matters -- without it your character spins on the spot while you fly.
	if godmode != null and godmode.take_motion(event):
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if wheel_open:
			## The wheel owns the mouse: the drag picks a slot, the world
			## holds still — release applies, and the look never moved.
			_wheel_vec += event.relative
			_wheel_highlight_from(_wheel_vec, 26.0)
			return
		rotate_y(-event.relative.x * MOUSE_SENS * set_sens)
		pitch = clampf(pitch - event.relative.y * MOUSE_SENS * set_sens, -1.4, 1.4)
		head.rotation.x = pitch
		_update_head_offset()


func _pad_move() -> Vector3:
	## The left stick, in the same shape the WASD blocks write. Zero when no
	## pad is plugged in or nothing is being pushed.
	if pad == null:
		return Vector3.ZERO
	return pad.move_vec()


func _update_head_offset() -> void:
	## Slide the camera forward (and slightly down) as you look down, so your
	## own body comes into view instead of filling the lens. Eye height rides
	## the crouch (eased in _update_camera_arm).
	if kd_phase != "":
		return  ## the knockdown owns the camera height until you're back up
	var down := clampf(-pitch / 1.4, 0.0, 1.0)
	## Prone pushes the head a touch forward — chin over the grass line.
	head.position = Vector3(0.0, _eye_h - down * 0.03, -0.18 * down - (0.12 if prone else 0.0))


func _stance_settle_pulse() -> void:
	## The settling roll of dropping to (or rising from) the ground: a brief
	## lean that rights itself. Skipped mid-sleep (the bed owns the roll).
	if sleep_phase != "":
		return
	var tw := create_tween()
	tw.tween_property(cam_arm, "rotation_degrees:z", 6.5, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(cam_arm, "rotation_degrees:z", 0.0, 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


func _set_cam_mode(m: String) -> void:
	cam_mode = m
	if m == "tp":
		cam_snap = 1.0   ## fast-glide the perch out — never look out of the skull
	_add_log_msg("Camera: %s" % ("third person" if m == "tp" else "first person"), Color(0.8, 0.8, 0.8))
	_save_settings()  ## "then it'll go by your last setting"


func _update_camera_arm(delta: float) -> void:
	## The camera GLIDES between eye and shoulder perch (that's the switch
	## animation), and walls shove the perch inward so it never clips rock.
	## During the bed sequence the sleep tweens own _eye_h — hands off.
	## Going prone (or rising from it) moves SLOW — a body's weight, not a
	## camera snap: that slow ease IS the going-prone animation, topped with
	## the settling roll pulse from _stance_settle_pulse.
	if sleep_phase == "":
		var eye_target := 0.45 if prone else (1.08 if crouching else 1.62)
		var ease_v := 4.2 if (prone or _eye_h < 0.9) else 7.0
		_eye_h = lerpf(_eye_h, eye_target, clampf(delta * ease_v, 0.0, 1.0))
	_update_head_offset()
	var want := Vector3.ZERO
	if cam_mode == "tp":
		## cam_shoulder is +1 right, -1 left, and 0 = CENTRED (Lemon
		## 2026-08-30: "add the middle view to the third person camera").
		## Dead centre puts your own back between the crosshair and the world,
		## so the middle view sits a little higher and a little further out —
		## you are looking OVER the character, not through him.
		var centred: float = 1.0 - minf(absf(cam_shoulder), 1.0)
		want = Vector3(0.55 * cam_shoulder, 0.32 + 0.14 * centred, 2.6 + 0.45 * centred)
		var from := head.global_position
		var to := head.to_global(want)
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var full := from.distance_to(to)
			want *= clampf((from.distance_to(hit.position as Vector3) - 0.22) / maxf(full, 0.001), 0.06, 1.0)
	## Entering third person snaps the perch out FAST (cam_snap): the lens must
	## never hang at eye height showing the world from where the head should be.
	cam_snap = maxf(0.0, cam_snap - delta * 3.0)
	var glide := 34.0 if cam_snap > 0.0 else 6.0
	cam_arm.position = cam_arm.position.lerp(want, clampf(delta * glide, 0.0, 1.0))
	## The third-person HEAD only exists from outside (in FP the camera sits
	## inside it), and it tips subtly to follow your gaze up and down.
	if tp_head:
		## The head only exists from OUTSIDE — and only once the camera has
		## actually GOT outside. While the lens is still gliding out of the
		## skull (entering third person), or a wall has shoved the perch back
		## into it, showing the head means looking at the world from behind
		## the inside of your own face. Gate it on real camera distance.
		var cam_out := camera.global_position.distance_to(head.global_position) \
			if camera else 0.0
		tp_head.visible = cam_mode == "tp" and cam_out > 0.85
		tp_head.rotation.x = pitch * 0.45
	## Third person hides the floating first-person hands — the body itself
	## performs: head, both arms, and body-held twins of every weapon (sword /
	## shield / bow / pickaxe / axe / torch — _update_tp_gear + the action
	## poses in _update_body_arms). Hip sword + back shield read when sheathed.
	if cam_mode == "tp":
		viewmodel.visible = false
		offhand_node.visible = false
		bow_vm.visible = false
		pick_vm.visible = false
		axe_vm.visible = false


func _input(event: InputEvent) -> void:
	if input_locked:
		return  ## nothing gets through a blackout
	## GOD MODE gets first refusal on every event while its panel is up, so
	## the editor and the game can never both act on one click or one key.
	## GodEditor.eat_input returns true when it has taken the event.
	if godmode != null and godmode.eat_input(event):
		return
	## THE CLAUDE CARD (F4) owns the keyboard while it is up -- a typed M
	## must never open the map. Esc and F4 fall through to close/toggle it.
	if claude_chat != null and claude_chat.eat_input(event):
		return
	## THE CREATOR owns a left click in the world while it is up: the click
	## selects the character under the cursor (scripts/CharacterCreator.gd).
	if creator != null and menu_open == "creator" and creator.eat_input(event):
		return
	if god and menu_open == "" and event is InputEventMouseButton \
			and (godmode == null or not godmode.visible):
		## The wheel is the speed dial even with the panel closed -- but not
		## while a menu owns the cursor, or it fights the map's zoom.
		var gmb := event as InputEventMouseButton
		if gmb.pressed and gmb.button_index == MOUSE_BUTTON_WHEEL_UP:
			god_speed = clampf(god_speed * 1.22, GOD_SPEED_MIN, GOD_SPEED_MAX)
			return
		if gmb.pressed and gmb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			god_speed = clampf(god_speed / 1.22, GOD_SPEED_MIN, GOD_SPEED_MAX)
			if absf(god_speed - 1.0) < 0.06:
				god_speed = 1.0
			return
	if event is InputEventMouseButton:
		if kd_phase != "":
			return  ## flat on the ground — no swinging, no drawing, nothing
		if event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if event.pressed:
				if reach_phase != "":
					return          ## the hand is already out -- let it finish
				## LOOT BEFORE STEEL: something on the ground, under the gaze,
				## inside arm's reach and nothing hunting you -- left click
				## reaches for it instead of swinging at it.
				if _try_grab(true):
					return
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
	elif event is InputEventKey and not event.pressed and (event as InputEventKey).keycode == KEY_Q:
		if _q_held:
			_q_held = false
			if wheel_open:
				_wheel_close(true)
			elif wheel_place_open:
				_wheel_place_finish()
			elif _q_inv_idx >= 0 and Time.get_ticks_msec() - _q_down_ms < 350:
				_wheel_quick_add(_q_inv_idx)
			_q_inv_idx = -1
	elif event is InputEventKey and not event.pressed and (event as InputEventKey).keycode == KEY_E:
		_gather_stop()
	elif event is InputEventKey and not event.pressed and (event as InputEventKey).keycode == KEY_V:
		## V released: short press cycles (FP -> TP right; TP -> swap shoulder);
		## the 1.5 s HOLD back to FP is consumed in _physics_process.
		if _v_held:
			_v_held = false
			if not _v_consumed and menu_open == "":
				if cam_mode == "fp":
					_set_cam_mode("tp")
				else:
					## right -> CENTRED -> left -> right
					if cam_shoulder > 0.5:
						cam_shoulder = 0.0
					elif cam_shoulder < -0.5:
						cam_shoulder = 1.0
					else:
						cam_shoulder = -1.0
					_add_log_msg("Camera: %s" % _cam_side_name(), Color(0.8, 0.8, 0.8))
					_save_settings()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_CTRL:
				## GOD MODE ONLY (2026-09-12): Ctrl is DESCEND while flying, so
				## it must not also spend a dash. Ordinary play is untouched.
				if god and flying:
					pass
				elif menu_open == "" and mount == null and kd_phase == "":  ## menus shouldn't leak dashes/jumps into the game
					_try_dash()
			KEY_F1:
				## F1 IS GOD MODE. Opens the editor panel and turns god on.
				_toggle_menu("god")
			KEY_F2:
				## F2 DROPS YOU IN. The body comes to wherever the spectator
				## camera is floating, you land in it, and the editor closes
				## into ordinary survival play. Only means anything while the
				## editor is up -- GodEditor.eat_input takes it first unless
				## the map is over the panel, which is why it also lives here.
				if godmode != null and godmode.visible:
					godmode.drop_in_here()
			KEY_F3:
				## F3 IS THE GRASS LAB. Styles, colours, shapes and sliders for the meadow.
				_toggle_menu("grass")
			KEY_F4:
				## F4 IS CLAUDE. A live chat card over the game; the game keeps running.
				_toggle_menu("claude")
			KEY_SPACE:
				## GOD: double-tap Space toggles flight, Minecraft-style. While
				## flying, a SINGLE tap toggles the speed boost (2026-09-12) --
				## Shift is height now, so the boost had to become sticky. The
				## first tap of a double tap flips it, so the second tap puts
				## it back before flipping flight.
				if god:
					var tap := Time.get_ticks_msec()
					if tap - _space_tap_ms < GOD_DOUBLE_TAP_MS:
						if _space_boost_flip:
							god_boost = not god_boost
							_space_boost_flip = false
						flying = not flying
						if not flying:
							velocity = Vector3.ZERO
						_space_tap_ms = 0
						if godmode != null:
							godmode._flag("fly", flying)
						_add_log_msg("Flight %s" % ("on" if flying else "off"),
							Color(0.62, 0.92, 1.0))
					else:
						_space_tap_ms = tap
						_space_boost_flip = false
						if flying:
							god_boost = not god_boost
							_space_boost_flip = true
							_add_log_msg("Boost %s" % ("on" if god_boost
								else "off"), Color(0.62, 0.92, 1.0))
					if flying:
						return
				if menu_open == "" and kd_phase == "" and not climbing:
					if mount != null:
						mount.request_jump()
					else:
						## Resolved in _physics_process — the climb check needs
						## physics-space raycasts, which _input can't touch.
						jump_queued = true
			KEY_F:
				## Pinned under a fallen trunk, F is the way out (spec §8b):
				## after ten seconds stuck it reloads your last save. Being
				## trapped under a log forever is a bug, not a story beat.
				if pinned_by != null:
					_pin_reload()
				elif (menu_open == "" or menu_open == "talk") and NPCFocus.take_f(self):
					pass  ## a person: antagonize (scripts/NPCFocus.gd)
				elif menu_open == "" and _water_target != Vector3.INF and _bed_target == null \
						and mount == null and _has_waterskin() >= 0 and not _water_is_sea:
					_fill_waterskin()   ## [water]
				elif menu_open == "":
					_try_interact()
			KEY_ALT:
				if current_weapon == "sword":
					sheathed = not sheathed
			KEY_B:
				## B is the DROP button: shed the hovered item at your feet.
				if menu_open == "tab" and tab_page == "inventory" and hovered_item_idx >= 0:
					_drop_item(hovered_item_idx)
			KEY_Q:
				## Q is the ITEM WHEEL. World: hold, drag toward a slot,
				## release to use it. Inventory: tap over an item to add it,
				## hold to pick which of the 8 slots it rides in.
				if not _q_held:
					_q_held = true
					_q_down_ms = Time.get_ticks_msec()
					## Remember the cursor NOW — the inventory ring is built
					## around this point 350 ms later, not around wherever the
					## mouse has drifted to by then.
					_q_down_mouse = get_viewport().get_mouse_position()
					_q_inv_idx = -1
					if menu_open == "" and kd_phase == "":
						_wheel_show(true)
					elif menu_open == "tab" and tab_page == "inventory" and hovered_item_idx >= 0:
						_q_inv_idx = hovered_item_idx
			KEY_E:
				## Arm the sweep BEFORE the tap is served -- the gaze targets are
				## still live on this frame, and the tap is about to clear them.
				_gather_arm()
				if (menu_open == "" or menu_open == "talk") and kd_phase == "" and NPCFocus.take_e(self):
					pass  ## a person: greet / talk / continue the talk (scripts/NPCFocus.gd)
				elif menu_open == "" and kd_phase == "" and _try_grab(false):
					pass    ## the reach: crouch, open hand, over the shoulder
				elif menu_open == "" and kd_phase == "" and _drop_target != null \
						and is_instance_valid(_drop_target):
					## Seen but out past arm's reach -- the old snap still takes it.
					_pickup_dropped(_drop_target)
				elif menu_open == "" and kd_phase == "" and _bed_target != null \
						and is_instance_valid(_bed_target):
					_pack_bedroll(_bed_target)
				elif menu_open == "" and kd_phase == "" and _debris_target != null \
						and is_instance_valid(_debris_target):
					if _give_item("Rock", 1, 0.8):
						_push_gain("Rock", 1)
						_debris_target.queue_free()
						_debris_target = null
				elif menu_open == "" and kd_phase == "" and _log_target != null \
						and is_instance_valid(_log_target):
					_hoist_log(_log_target)
				elif menu_open == "" and kd_phase == "" and _fire_target != null \
						and is_instance_valid(_fire_target):
					_use_firepit(_fire_target)   ## [fire]
				elif menu_open == "" and kd_phase == "" and not _carc_target.is_empty():
					_butcher_cut()   ## [butchery]
				elif menu_open == "" and kd_phase == "" and _water_target != Vector3.INF:
					_drink_water()   ## [water]
			KEY_M:
				## M IS THE MAP. (The mob menu it used to open moved to K.)
				_toggle_menu("map")
			KEY_K:
				_toggle_menu("spawn")
			KEY_G:
				_toggle_menu("creative")
			KEY_V:
				if menu_open == "" and not _v_held:
					_v_held = true
					_v_down_ms = Time.get_ticks_msec()
					_v_consumed = false
			KEY_C:
				if menu_open == "" and kd_phase == "" and mount == null and not climbing and not swimming:
					## AT A SPRINT, C IS A SLIDE. Same key, same pad button (O):
					## going down while you are already moving fast is a slide in
					## every game that has one, and it costs no new binding.
					## Below SLIDE_MIN_SPEED it is the crouch toggle it always was.
					if _try_slide():
						pass
					## C toggles CROUCH (per Lemon — the old C-cycle is gone).
					## From prone, C lifts you one stance, to the crouch.
					elif prone:
						prone = false
						crouching = true
						_stance_settle_pulse()
						_add_log_msg("Crouched", Color(0.8, 0.8, 0.8))
					elif crouching:
						crouching = false
						_stance_settle_pulse()
						_add_log_msg("Standing", Color(0.8, 0.8, 0.8))
					else:
						crouching = true
						prone = false
						_drop_carried_logs("you crouched")
						_add_log_msg("Crouched", Color(0.8, 0.8, 0.8))
			KEY_X:
				if menu_open == "" and kd_phase == "" and mount == null and not climbing and not swimming:
					## X toggles PRONE. From standing OR crouching you go flat;
					## from prone you come all the way back up to your feet.
					## (crouching stays true while prone — stealth reads it.)
					if prone:
						prone = false
						crouching = false
						_stance_settle_pulse()
						_add_log_msg("Standing", Color(0.8, 0.8, 0.8))
					else:
						crouching = true
						prone = true
						_drop_carried_logs("you went prone")
						_stance_settle_pulse()
						_add_log_msg("Prone — flat to the earth", Color(0.8, 0.8, 0.8))
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
			KEY_APOSTROPHE:
				## ' — the sky menu: time, season, weather, lightning, aurora.
				_toggle_menu("sky")
			KEY_ESCAPE:
				## DEV MODE (2026-09-12): with the editor up and nothing over
				## it, Esc opens SETTINGS as an overlay rather than throwing
				## you out -- F1, F2 and the panel's own button are the ways
				## out of dev mode. An overlay closes back to the editor first.
				if godmode != null and godmode.visible and god_overlay() == "":
					_toggle_menu("settings")
				elif menu_open != "":
					_close_menu()
				else:
					_toggle_menu("settings")  ## Esc = the settings/pause menu


func _physics_process(delta: float) -> void:
	since_last_attack += delta
	## SPECTATOR: the camera is out. The body is parked and owns nothing --
	## checked FIRST, above the knockdown and grab branches, because none of
	## those may run on a body the world is not allowed to touch.
	if editing:
		_editor_freeze(delta)
		return

	## Leaving flight (or god) puts the collision mask back exactly as found.
	if _god_mask_saved >= 0 and not (god and flying):
		collision_mask = _god_mask_saved
		_god_mask_saved = -1

	## Knocked flat (a horse's hoof, mostly): you eat dirt, lie there, and get
	## up slow — and everything out there is free to keep hitting you through
	## the entire fall-and-rise. Handles its own frame, then bails.
	if kd_phase != "":
		_update_knockdown(delta)
		return

	## In the jaws (the bear's grab): the animal's clip owns your position —
	## you hang off its mouth. You keep your eyes; it keeps everything else.
	if grabbed_by != null:
		_update_grabbed(delta)
		return

	## GOD FLIGHT owns the frame: noclip, no gravity, no gait, no stamina.
	if god and flying:
		_god_fly(delta)
		return

	## Blackout / bed animation: the body stands (or lies) quietly — gravity
	## and visuals only, no will. Sleep phases advance in _sleep_poll.
	if input_locked:
		if not is_on_floor():
			velocity.y -= gravity * delta
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
		move_and_slide()
		_frame_fx_and_regen(delta)
		_update_hud(delta)
		_update_log(delta)
		_sleep_poll()
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

	## [terrain] Chest-deep in a lake or the Gulf of Maine you SWIM. Owns the
	## frame while it lasts -- see _update_swim.
	if _update_swim(delta):
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	if block_broken_timer > 0.0:
		block_broken_timer -= delta
	var was_blocking := blocking
	blocking = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not NPCFocus.claims_rmb(self) and block_broken_timer <= 0.0 \
		and current_weapon == "sword" \
		and (godmode == null or not godmode.visible)  ## RMB is look-drag in god mode
	## Parry timing: how fresh is this guard? (A block raised within PARRY_WINDOW
	## of the hit landing counts as a perfect guard.)
	if blocking and not was_blocking:
		block_held_time = 0.0
		## Raising a guard pulls the steel — EXCEPT in the dark with the
		## shield already up: there you block behind the shield while the
		## sword stays sheathed (the torch keeps burning in the same fist).
		if sheathed and not (_in_dark and _offhand_is_shield()):
			sheathed = false
	elif blocking:
		block_held_time += delta
	else:
		block_held_time = 999.0

	_update_darkness()
	_update_hunch(delta)

	## V held 1.5 s in third person = glide home into first.
	if _v_held and not _v_consumed and cam_mode == "tp" \
			and Time.get_ticks_msec() - _v_down_ms >= 1500:
		_v_consumed = true
		_set_cam_mode("fp")

	## Space, resolved here where the physics space is queryable: a grabbable
	## ledge ahead beats a jump — otherwise jump if the ground agrees.
	if jump_queued:
		jump_queued = false
		## OUT OF THE SLIDE, NOT OUT OF THE SPEED. A jump ends the slide and
		## keeps the velocity it had built — this is the join in the chain.
		if sliding:
			_end_slide(true)
		if _try_climb():
			_drop_carried_logs("both hands went to the ledge")
		elif is_on_floor() and pressed_by == null:  ## no jumping out from under a bear
			velocity.y = JUMP_VELOCITY
			crouching = false  ## jumping stands you up
			prone = false
			_drop_carried_logs("you jumped")

	## LEANED ON: an animal's weight (the bear's press). It ends when the
	## animal says so, when it dies, or when you tear yourself out of reach —
	## a dash, mostly. Movement continues below at a crushed crawl.
	if pressed_by != null:
		press_t += delta
		var pb := pressed_by
		if pb == null or not is_instance_valid(pb) \
				or ("dying" in pb and bool(pb.get("dying"))) or press_t > 3.4 \
				or global_position.distance_to(pb.global_position) > 4.2:
			pressed_by = null
			press_t = 0.0
		else:
			cam_shake = maxf(cam_shake, 0.05)

	## THE RUNNING VAULT. No button: if you are sprinting and there is a
	## hip-high lip in front of you, you go over it. The probes are the mantle's
	## own three raycasts and they only fire while you are ACTUALLY running, so
	## the walking game pays nothing for this.
	if _vault_cd > 0.0:
		_vault_cd -= delta
	if slide_cd > 0.0:
		slide_cd -= delta
	if sprinting and is_on_floor() and not sliding and _vault_cd <= 0.0 \
			and kd_phase == "" and mount == null and not climbing and not input_locked \
			and pressed_by == null and reach_phase == "" \
			and Vector2(velocity.x, velocity.z).length() >= VAULT_MIN_SPEED:
		if _try_climb(true):
			_drop_carried_logs("you vaulted")
			return
		_vault_cd = maxf(_vault_cd, 0.08)   ## nothing there: do not re-probe next frame

	## Movement direction from raw keys (relative to facing).
	move_input = Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move_input.z -= 1.0
	if Input.is_key_pressed(KEY_S): move_input.z += 1.0
	if Input.is_key_pressed(KEY_A): move_input.x -= 1.0
	if Input.is_key_pressed(KEY_D): move_input.x += 1.0
	## CONTROLLER: the left stick adds into the same vector. dir is normalised
	## below, so a half-pushed stick would walk as fast as a key — pad_push
	## keeps the analog part and scales the speed with it instead.
	var pad_mv := _pad_move()
	var pad_push := 1.0
	if pad_mv != Vector3.ZERO:
		if move_input == Vector3.ZERO:
			pad_push = clampf(pad_mv.length(), 0.35, 1.0)
		move_input += pad_mv
	var dir := (transform.basis * move_input).normalized()
	dir.y = 0.0

	var overweight := _total_weight() > stats.carry_limit()
	## The silent sprint thief, named: crossing the carry limit used to just
	## quietly kill sprint ("the game broke") — now it says so, once, and the
	## HUD keeps saying it until you shed the weight.
	if overweight and not _was_overweight:
		_add_log_msg("Overburdened (%.0f / %.0f) — too heavy to sprint until you shed weight"
			% [_total_weight(), stats.carry_limit()], Color(1.0, 0.72, 0.38))
	_was_overweight = overweight
	var speed := SPEED * stats.speed_mult()  ## DEX: a little quicker on your feet
	sprinting = false
	if blocking or drawing:  ## guarding or holding a draw = slow, deliberate steps
		speed = BLOCK_SPEED
	elif Input.is_key_pressed(KEY_SHIFT) and stamina > 0.0 and move_input != Vector3.ZERO \
			and not overweight and not crouching:
		sprinting = true
		speed = SPRINT_SPEED * stats.speed_mult()
		stamina = maxf(0.0, stamina - SPRINT_DRAIN * stats.stamina_cost_mult() * delta)
		stamina_delay = maxf(stamina_delay, 0.4)  ## regen pauses briefly after you stop
	if overweight:
		speed *= 0.5  ## TODO(design): overburdened — flat 50% slowdown + no sprint for now
	speed *= status_speed_mult   ## tar gum, rime chill (Afflictions.gd)
	if prone:
		speed = minf(speed, SPEED * 0.22)  ## a crawl — belly to the ground
	elif crouching:
		speed = minf(speed, SPEED * 0.45)  ## low and slow — the hunter's walk
	if pressed_by != null:
		speed *= 0.12   ## pinned under an animal's weight — struggling, not walking
	speed *= pad_push   ## how far the left stick is actually pushed

	## THE GROUND DECIDES (2026-09-14). Three opinions, composed and clamped in
	## Locomotion.compose so a bog on a hillside under deep grass cannot stack
	## into a standstill: what you are standing ON, how deep the meadow is at
	## your shins, and whether you are climbing it or falling down it.
	_update_footing(delta)
	var slope := 1.0
	if is_on_floor() and dir != Vector3.ZERO:
		slope = Locomotion.slope_mult(get_floor_normal(), dir)
	speed = Locomotion.compose(speed, _surface_mult, wade, slope)
	## Shouldering through a meadow at a run costs more wind than the open road.
	if sprinting and wade > 0.05:
		stamina = maxf(0.0, stamina - SPRINT_DRAIN * (Locomotion.WADE_SPRINT_DRAIN - 1.0)
			* wade * stats.stamina_cost_mult() * delta)

	## Hit-stun (thrown out of an action) overrides input; otherwise dash; otherwise glide.
	if hitstun_timer > 0.0:
		hitstun_timer -= delta
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
	elif sliding:
		_update_slide(delta, dir)
	elif dash_timer > 0.0:
		dash_timer -= delta
		var d := dir if dir != Vector3.ZERO else -transform.basis.z
		if committed:
			d = -transform.basis.z  ## a committed step goes where the edge goes
		velocity.x = d.x * DASH_SPEED
		velocity.z = d.z * DASH_SPEED
	else:
		var rate := ACCEL if dir != Vector3.ZERO else DECEL
		var brake := DECEL
		if not is_on_floor():
			rate = AIR_ACCEL
			brake = AIR_ACCEL
		var hv := Vector3(velocity.x, 0.0, velocity.z)
		var target := dir * speed
		## MOMENTUM (2026-09-14). This used to be one move_toward at 45 m/s^2,
		## which reaches full sprint in a tenth of a second and turns a right
		## angle in ONE FRAME — honest, and completely lifeless. Locomotion.steer
		## keeps the standstill crisp (under a walk it IS that move_toward) and
		## arcs everything above it, charging you speed for an angle you could
		## not make. See scripts/Locomotion.gd; the feel is under test in
		## tests/LocomotionTests.gd.
		hv = Locomotion.steer(hv, target, rate, brake, delta, SPRINT_SPEED)
		velocity.x = hv.x
		velocity.z = hv.z
		_bank = lerpf(_bank, Locomotion.bank(hv, target, SPRINT_SPEED),
			clampf(delta * 5.0, 0.0, 1.0))

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
	_unwedge(delta, dir != Vector3.ZERO)
	_apply_step_smooth(delta)
	_update_body_arms(delta)
	_update_hud(delta)
	_update_log(delta)


func _update_action_camera(delta: float) -> void:
	## THE LENS FIGHTS WITH YOU. Every action the hands perform leans the
	## camera through its own little arc — swings roll it through the cut,
	## chops drive it down into the bite, the bow draw settles it onto the
	## cheek, landed hits PUNCH it forward, and rummaging in the pack drops
	## your eyes to the satchel. All of it lives on cam_anim (between the arm
	## and the camera) so bob/shake keep their own channel — and in third
	## person the same numbers lean the whole visible BODY into the action.
	if cam_anim == null:
		return
	var rot := Vector3.ZERO   ## degrees
	var pos := Vector3.ZERO
	var byaw := 0.0           ## torso YAW for the third-person body — the
							  ## shoulders coil against a slash and twist
							  ## through it (fed to body_rig at the bottom)
	var hand := -1.0 if set_lefty else 1.0  ## mirrored hands = mirrored leans

	if attacking and current_weapon == "sword":
		var st := SWING_TIME * stats.swing_mult()
		var p := clampf(swing_t / maxf(st, 0.01), 0.0, 1.0)
		var env := sin(p * PI)
		## THE RAMP: each swing of the chain leans harder — the first cut is a
		## suggestion, the second a commitment, the finisher takes the whole
		## upper body with it (1 -> 2 -> 3 and around again).
		var ramp: float = [1.0, 1.45, 1.9][clampi(combo_index, 1, 3) - 1]
		## THE SWEEP: coil slightly AGAINST the cut through the chamber, then
		## carry ACROSS with the edge and out the follow-through — real travel
		## from one side of the frame to the other, not a symmetric bump.
		var sweep: float
		if p < 0.30:
			var cu := p / 0.30
			sweep = -0.35 * (cu * cu)
		else:
			var wu := (p - 0.30) / 0.70
			sweep = -0.35 + 1.35 * (wu * wu * (3.0 - 2.0 * wu))
		var dirn := 1.0
		if mounted_swing:
			dirn = 1.0 if mounted_side == 0 else -1.0
		elif combo_index == 2:
			dirn = -1.0
		if combo_index == 3 and not mounted_swing:
			## The overhead finisher: the deepest beat — a hard dip driven
			## through the impact, the roll carrying out the follow-through.
			rot.x = env * 3.9 + maxf(sweep, 0.0) * 2.2
			rot.z = sweep * 2.4 * hand
			pos.y = env * -0.03
		else:
			rot.z = sweep * 3.6 * ramp * dirn * hand
			rot.y = sweep * -2.6 * ramp * dirn * hand
			rot.x = env * 0.8 * ramp
			pos.x = sweep * 0.028 * ramp * dirn * hand
		## The TORSO goes with the cut: coiled slightly against it through the
		## chamber, twisted THROUGH it with the edge. This is what makes the
		## third-person slash read from the shoulders, not just the wrist.
		byaw = sweep * 7.0 * ramp * dirn
		pos.z = env * -0.022 * ramp
		if committed:
			rot.x += env * 1.5
			pos.z -= env * 0.05               ## the step drives the lens forward
	elif axe_swinging:
		var pa := clampf(axe_t / maxf(AXE_TIME * stats.swing_mult(), 0.01), 0.0, 1.0)
		var enva := sin(pa * PI)
		## Side swings ROLL the lens through the sweep, forehand and back.
		## ...and the lens rolls WITH the stroke. Mirrored along with the arc:
		## the forehand now travels right-to-left, so the head leans that way.
		rot.z = enva * (-3.6 if axe_side == 0 else 3.6) * hand
		rot.y = enva * (2.4 if axe_side == 0 else -2.4) * hand
		rot.x = enva * 0.4   ## barely any nod now — the stroke is flat, not down
		byaw = enva * (12.0 if axe_side == 0 else -12.0)  ## hips behind the cleave
		pos.y = enva * -0.008
	elif pick_swinging:
		var pp := clampf(pick_t / maxf(PICK_TIME, 0.01), 0.0, 1.0)
		var envp := sin(pp * PI)
		rot.x = envp * 2.6
		pos.y = envp * -0.015
	if current_weapon == "bow" and (drawing or bow_draw > 0.0):
		rot.z += -1.3 * bow_draw * hand       ## head cants onto the string
		rot.x += -0.5 * bow_draw
		pos += Vector3(0.008 * hand, 0.006, 0.014) * bow_draw
	if blocking:
		rot.x += 0.9                          ## braced behind the guard
		pos.z += 0.018

	## Hands in the pack: eyes drop to the satchel, hands leave the frame.
	pack_reach = move_toward(pack_reach,
		1.0 if (menu_open == "tab" and tab_page == "inventory") else 0.0, delta * 5.0)
	var pe := pack_reach * pack_reach * (3.0 - 2.0 * pack_reach)
	rot.x += pe * 7.0
	rot.z += pe * 2.5 * hand
	pos.y += pe * -0.045
	if hands_root:
		hands_root.position = hands_root.position.lerp(
			Vector3(0, -0.36, 0.08) * pe, clampf(delta * 9.0, 0.0, 1.0))

	## The reach: your eyes go down with the hand and come back up with it, and
	## the torso turns a little as the arm swings the thing over the shoulder.
	if reach_phase != "" or reach_out > 0.001 or reach_stow > 0.001:
		var gr := reach_out * reach_out * (3.0 - 2.0 * reach_out)
		rot.x += gr * 9.0
		rot.z += reach_stow * 2.0 * hand
		pos.y += gr * -0.05

	## Impact: landed hits kick the lens forward and it eases right back.
	if cam_punch > 0.0:
		cam_punch = maxf(0.0, cam_punch - delta * 5.0)
		rot.x += cam_punch * 2.2
		pos.z += cam_punch * -0.03

	var k := clampf(delta * 12.0, 0.0, 1.0)
	cam_anim.rotation_degrees = cam_anim.rotation_degrees.lerp(rot, k)
	cam_anim.position = cam_anim.position.lerp(pos, k)

	## And the BODY leans with the lens — a third-person watcher sees the
	## torso commit into cuts and chops and stoop to the pack (mirror-safe:
	## rotation and scale live on separate channels).
	## Not while you're on your back — _update_knockdown owns the rig then.
	## ...and a turn leans the TORSO harder than it leans the eye — a watcher
	## sees you drop a shoulder into the corner (2026-09-14, Locomotion.bank).
	if body_rig and kd_phase == "":
		body_rig.rotation_degrees = body_rig.rotation_degrees.lerp(
			Vector3(clampf(rot.x, -8.0, 8.0) * 0.55, byaw,
				clampf(rot.z, -6.0, 6.0) * 0.6 - _bank * Locomotion.BODY_BANK_DEG), k)


func _frame_fx_and_regen(delta: float) -> void:
	if god:
		## GOD MODE pins the four bars every frame, so nothing drains while
		## you are laying out a town. Done here because every stance -- on
		## foot, flying, mounted, face-down -- comes through this one function.
		health = max_health
		stamina = max_stamina
		stamina_delay = 0.0
		thirst = THIRST_MAX
		breath = 100.0
	## The upkeep every stance shares — on foot, in the saddle, or face-down in
	## the dirt: camera shake, held-item animation, stamina/health regen, and
	## the progression timers.
	_update_grab(delta)          ## advance the reach BEFORE the camera reads it
	_update_gather(delta)        ## hold E: the rest of the pile comes in
	_update_action_camera(delta)
	_update_wheel_hold(delta)
	if bedroll_bundle:
		bedroll_bundle.visible = _count_item("Bedroll") > 0
	if pack_rig:
		pack_rig.visible = not _slot_item("back").is_empty()
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
	_update_tp_gear(delta)
	_update_camera_arm(delta)

	## Stamina regen: not while sprinting or blocking, and only after a short
	## breather following whatever last spent it. (Regen used to run DURING the
	## sprint drain, so sprinting netted +8/s and the bar never moved.)
	if stamina_delay > 0.0:
		stamina_delay -= delta
	if stamina < max_stamina and not blocking and not sprinting and not drawing and stamina_delay <= 0.0:
		stamina = minf(max_stamina, stamina + stamina_regen * _thirst_regen_mult() * delta)
	_thirst_tick(delta)
	_exposure_tick(delta)
	_cold_tick(delta)
	## breath comes back on land here; the swim and grab frames drain it
	if not swimming and grabbed_by == null and breath < 100.0:
		_breath_tick(delta, 0.0)

	## Very slow regen, only a few seconds after the last combat action.
	## CON makes the wounds close faster.
	combat_timer += delta
	## Peaceful closes wounds about three times faster and starts sooner;
	## Hardcore drags both out. Normal is exactly the tuned numbers.
	if combat_timer > COMBAT_HEAL_DELAY * GameMode.heal_delay_mult() and health < max_health:
		health = minf(max_health, health + stats.heal_rate() * GameMode.heal_rate_mult() * delta)

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


## --- swimming (the overworld's lakes and the Gulf of Maine) -----------------
## Overworld.water_y() says where the surface is. Water SWIM_DEPTH above your
## feet floats you: the body settles with the eyes just clear of the surface,
## WASD paddles, Space climbs, C dives, sprint is not a thing. Paddling drains
## stamina and at zero you crawl. There is no drowning yet -- the map rim would
## make a two-kilometre swim out to sea a death with no warning -- so the sea
## is a boundary you can turn back from, not a trap. Everything else about the
## body (knockdown, grab, mount, climb) is checked BEFORE this in
## _physics_process, so none of it has to know about water.
var swimming := false
var _swim_face := 0.0                  ## eased "how submerged is the lens"
var _water_tint: ColorRect = null
const SWIM_DEPTH := 1.15               ## water this far above the feet floats you
const SWIM_EXIT_DEPTH := 0.75          ## ...and this shallow puts them back down
const SWIM_SPEED := 3.4
const SWIM_ACCEL := 7.0
const SWIM_VERT := 2.4                 ## Space up / C down, m/s
const SWIM_FLOAT_EYE := 0.30           ## the surface sits this far under the eyes
const SWIM_DRAIN := 3.0                ## stamina a second while paddling
const SWIM_STROKE_GAP := 0.95          ## seconds between stroke sounds

## --- thirst, breath, the waterskin (water pass, 2026-09-01) ----------------
## THIRST is a survival meter: full to empty in THIRST_DAYS game days at rest,
## faster sprinting or swimming. Under THIRST_LOW stamina comes back at half
## pace; at zero the body starts to fail (THIRST_DAMAGE_PER_S, and it CAN
## finish you). Settings -> Thirst has two positions and swaps live:
##   Survival  the meter, as above
##   Light     no meter -- drinking is a stamina top-up and a 90 s "refreshed"
##             regen boost, and nothing punishes you for never drinking.
## Drink at any fresh water (look at it, E); the sea is brine and says so.
## The WATERSKIN in your pack holds SKIN_FILLS draughts, refilled at fresh
## water with F. BREATH: forty seconds with your ears under, coming back
## three times as fast; at zero you drown by DROWN_DAMAGE_PER_S.
const THIRST_MAX := 100.0
const THIRST_DAYS := 1.5
const THIRST_LOW := 30.0
const THIRST_DRAUGHT := 40.0           ## a long drink at the shore
const SKIN_DRAUGHT := 35.0             ## one pull on the waterskin
const SKIN_FILLS := 3
const SKIN_WEIGHT := 0.6
const SKIN_WATER_WEIGHT := 0.5         ## per draught carried
const THIRST_DAMAGE_PER_S := 0.4
const THIRST_SPRINT_MULT := 1.8
const THIRST_SWIM_MULT := 1.35
const REFRESHED_SECONDS := 90.0
const BREATH_SECONDS := 40.0
const BREATH_REGEN := 3.0              ## x the drain rate, coming back
const DROWN_DAMAGE_PER_S := 5.0
const DRINK_REACH := 1.9               ## how far ahead the shore may be
var thirst := THIRST_MAX
var breath := 100.0
var set_thirst_mode := 0               ## 0 Survival / 1 Light  (Settings)
var set_refract := true                ## Settings -> Water Refraction
var thirst_show := 0.0
var breath_show := 0.0
var thirst_bar: Control
var thirst_fill: ColorRect
var breath_bar: Control
var breath_fill: ColorRect
var _water_target := Vector3.INF       ## fresh (or salt) water under the gaze
var _water_is_sea := false
var _drink_cd := 0.0
var _thirst_msg_t := 0.0
var _drown_msg_t := 0.0
var _stroke_t := 0.0
var _refreshed_t := 0.0
var _struggle_space_held := false
var _struggle_click_held := false


static func thirst_rate_per_sec() -> float:
	return THIRST_MAX / (THIRST_DAYS * DayNight.DAY_SECONDS)


## 0 = ears in the air, 1 = fully under (eased). World reads it for the fog.
func submerged() -> float:
	return _swim_face


func thirst_survival() -> bool:
	return set_thirst_mode == 0


## --- exposure and warmth (2026-09-10, SYSTEMS) -----------------------------
## The model is scripts/Exposure.gd and every degree of it is a pure function.
## What lives here is the wiring: build the environment once a frame, hand it
## to `exposure.step()`, and do as the report says. No decision is taken in
## this file, which is why the whole feature is testable without a Player.
const EXPOSURE_SHELTER_UP := 7.0        ## how far overhead we look for a roof
const EXPOSURE_SHELTER_RECHECK := 1.5   ## seconds between shelter rays

var exposure := Exposure.new()

## [coldscreen] What the cold LOOKS like. Exposure has handed out a `felt`
## in degrees and a `sway_extra()` every frame since 4ac02b1 and nothing
## read either. Breath is the AIR (ambient, so a man at a hearth still
## sees it); the shiver and the grade are the BODY (warmth, from the
## shiver line down). Owns one overlay and one particle node and takes no
## decision: `step()` returns a report and `present()` draws it.
var cold := ColdScreen.new()
var set_warmth_mode := 0                ## 0 Survival / 1 Light  (Settings)
var warmth_show := 0.0
var warmth_bar: Control
var warmth_fill: ColorRect
var _exposure_sheltered := false
var _exposure_shelter_t := 0.0


func warmth_survival() -> bool:
	return set_warmth_mode == 0


func _exposure_roof() -> bool:
	## One ray straight up, EXPOSURE_SHELTER_RECHECK seconds apart. A roof
	## takes the wind AND the precipitation off you, which is the whole reason
	## to build one before you are cold rather than after.
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var from := global_position + Vector3(0.0, 1.2, 0.0)
	var q := PhysicsRayQueryParameters3D.create(from,
			from + Vector3(0.0, EXPOSURE_SHELTER_UP, 0.0))
	q.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	return not hit.is_empty()


func _exposure_env() -> Dictionary:
	## Everything Exposure needs, gathered from the four places that hold it.
	## Nothing here decides anything; it reads.
	var w := get_tree().get_first_node_in_group("world")
	var wx: Object = null
	var dn: Object = null
	var under := false
	if w != null:
		if w.has_method("weather"):
			wx = w.call("weather")
		if w.has_method("daynight"):
			dn = w.call("daynight")
		if w.has_method("underground"):
			under = bool(w.call("underground"))
	var hour := 12.0
	var day := 30.0
	if dn != null:
		hour = float(dn.get("hour"))
		day = float(dn.get("day"))
	var wx_level := 0
	var intensity := 0.0
	var snowing := false
	var wind := 0.0
	if wx != null:
		wx_level = int(wx.get("level"))
		intensity = clampf(float(wx.get("intensity")), 0.0, 1.0)
		if wx.has_method("is_snowing"):
			snowing = bool(wx.call("is_snowing"))
		var wnode: Object = wx.get("wind")
		if wnode != null:
			wind = clampf(float(wnode.get("last_strength")), 0.0, 1.0)
	return Exposure.env({
		"season": Exposure.season_for_day(day),
		"hour": hour,
		"y": global_position.y,
		"level": wx_level,
		"intensity": intensity,
		"snowing": snowing,
		"wind": wind,
		"sheltered": _exposure_sheltered,
		"underground": under,
		"fire_c": Exposure.fire_c(get_tree().get_nodes_in_group("fires"), global_position),
		## NOT `tp_torch.visible`: that node exists from boot, and its
		## visibility is also gated on `cam_mode == "tp"`, so reading it gave
		## the player a lit torch's 3.5 C for ever in third person and none of
		## it in first. What is actually in the left hand is `offhand_shown`
		## (found live, 2026-09-10).
		"torch": String(offhand_shown).contains("Torch") \
			or String(offhand_shown2).contains("Torch"),
		"asleep": false,
		"swimming": swimming,
		## WHAT IS ON YOUR BACK. `Garments` prices the five armour slots
		## in degrees; `equipment` also carries a sword and an offhand,
		## which `worn_metals()` leaves out rather than relying on the
		## other file to ignore them.
		"worn": worn_metals(),
		## AND WHERE YOU ARE STANDING. `Seasons.base_c_at()` is the
		## season's contribution to the air HERE, on this place's own
		## calendar, and it has had no caller since it shipped. With it,
		## a winter night in Aroostook is genuinely colder than the same
		## night on Casco Bay -- twelve degrees apart on day 66, when the
		## north is in winter and the south has not finished autumn.
		"base_c": Seasons.base_c_at(day, global_position),
		"mode": Exposure.mode_now(),
		"survival": warmth_survival(),
	})


func _exposure_tick(delta: float) -> void:
	warmth_show = maxf(0.0, warmth_show - delta)
	if god:
		## The map-authoring mode pins health, stamina and thirst; it pins this
		## too, or an afternoon spent building in a winter sky kills you.
		exposure.warmth = Exposure.WARMTH_MAX
		exposure.wet = 0.0
		return
	_exposure_shelter_t -= delta
	if _exposure_shelter_t <= 0.0:
		_exposure_shelter_t = EXPOSURE_SHELTER_RECHECK
		_exposure_sheltered = _exposure_roof()
	var r: Dictionary = exposure.step(_exposure_env(), delta)
	var crossed := String(r["crossed"])
	if crossed != "" and Exposure.MESSAGES.has(crossed):
		var m: Array = Exposure.MESSAGES[crossed]
		_add_log_msg(String(m[0]), m[1] as Color)
		warmth_show = 3.0
	var dmg := float(r["damage"])
	if dmg > 0.0 and invuln_timer <= 0.0 and health > 0.0:
		health = maxf(0.0, health - dmg)
		health_show = 1.0
		## THE COLD IS A WOUND, NOT A STATUS. Without this the out-of-combat
		## regen a few lines down in `_process` outruns WARMTH_DAMAGE_PER_S
		## and a soaked man at zero warmth in a winter gale sits at a hundred
		## health for ever -- which is what he did, live, before this line.
		combat_timer = 0.0
		if health <= 0.0:
			_die()


func _cold_tick(delta: float) -> void:
	## [coldscreen] Attached lazily: the HUD layer and the head are built by
	## different passes of _ready, and `attach()` is idempotent.
	##
	## Deliberately called OUTSIDE `_exposure_tick`'s god-mode early return.
	## God mode pins warmth at the maximum, so the shiver and the grade turn
	## themselves off with no branch here -- and an afternoon spent building
	## in a winter sky still has your breath in front of you, which is the
	## correct answer and falls out of the model for free.
	cold.attach(head, hud_layer)
	var ex := ColdScreen.exertion_of(sprinting, stamina / maxf(1.0, max_stamina))
	var rep: Dictionary = cold.step(_exposure_env(), exposure.warmth, ex, delta)
	cold.present(rep)
	var sh := float(rep["shake"])
	if sh > 0.0:
		## Fed into the EXISTING shake path rather than writing camera.position:
		## that line already decays, already composes with the walk-cycle bob,
		## and already loses to a real impact -- which is the right priority.
		cam_shake = maxf(cam_shake, sh)


## Stamina regen multiplier from thirst: half when parched, 1.5 while
## refreshed (Light mode's reward for drinking), else 1.
func _thirst_regen_mult() -> float:
	if _refreshed_t > 0.0:
		return 1.5
	if thirst_survival() and thirst < THIRST_LOW:
		return 0.5
	return 1.0


func _thirst_tick(delta: float) -> void:
	_refreshed_t = maxf(0.0, _refreshed_t - delta)
	_drink_cd = maxf(0.0, _drink_cd - delta)
	_thirst_msg_t = maxf(0.0, _thirst_msg_t - delta)
	if not thirst_survival():
		return
	var rate := thirst_rate_per_sec()
	if sprinting:
		rate *= THIRST_SPRINT_MULT
	elif swimming:
		rate *= THIRST_SWIM_MULT
	var before := thirst
	thirst = maxf(0.0, thirst - rate * delta)
	if before >= THIRST_LOW and thirst < THIRST_LOW:
		_add_log_msg("Thirsty -- your wind is going", Color(0.85, 0.80, 0.55))
		thirst_show = 3.0
	elif before >= 10.0 and thirst < 10.0:
		_add_log_msg("Parched. Find water.", Color(1.0, 0.70, 0.40))
		thirst_show = 3.0
	if thirst <= 0.0 and invuln_timer <= 0.0 and health > 0.0:
		health = maxf(0.0, health - THIRST_DAMAGE_PER_S * delta)
		health_show = 1.0
		## THIRST IS A WOUND, NOT A STATUS — the same bug the cold had, in the
		## same shape, and it has been sitting here since the meter was
		## written. `_process`'s out-of-combat regen waits only on
		## `combat_timer`, and dying of thirst is not a combat action, so a man
		## at zero water healed faster than he bled and sat at full health for
		## ever. Fixed for warmth by 4ac02b1; this is the other half of it.
		combat_timer = 0.0
		if _thirst_msg_t <= 0.0:
			_thirst_msg_t = 12.0
			_add_log_msg("Your body is failing without water", Color(1.0, 0.45, 0.30))
		if health <= 0.0:
			_die()


## Ears under: the air goes; back in the air it comes back three times as
## fast. `under` is the eased submersion so a bob at the surface is free.
func _breath_tick(delta: float, under: float) -> void:
	_drown_msg_t = maxf(0.0, _drown_msg_t - delta)
	var drain := 100.0 / BREATH_SECONDS
	if under > 0.5:
		var was := breath
		breath = maxf(0.0, breath - drain * delta)
		breath_show = 1.5
		if was > 25.0 and breath <= 25.0:
			_add_log_msg("Air running out", Color(0.75, 0.90, 1.0))
		if breath <= 0.0 and invuln_timer <= 0.0 and health > 0.0:
			health = maxf(0.0, health - DROWN_DAMAGE_PER_S * delta)
			health_show = 1.0
			cam_shake = maxf(cam_shake, 0.06)
			if _drown_msg_t <= 0.0:
				_drown_msg_t = 3.0
				_add_log_msg("Drowning!", Color(1.0, 0.40, 0.30))
			if health <= 0.0:
				_die()
	else:
		if breath < 100.0:
			breath = minf(100.0, breath + drain * BREATH_REGEN * delta)
			breath_show = 1.0


## --- drinking ----------------------------------------------------------------
## The gaze check: the point DRINK_REACH ahead at foot height. Fresh water
## whose surface is within reach of your hands is drinkable; while swimming,
## the water you are in is (if your head is out of it).
func _update_water_target() -> void:
	_water_target = Vector3.INF
	_water_is_sea = false
	if menu_open != "" or kd_phase != "" or grabbed_by != null or mount != null:
		return
	if swimming:
		if _swim_face < 0.5 and Overworld.is_water_at(global_position):
			_water_target = global_position
			_water_is_sea = Overworld.water_is_sea(global_position)
		return
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.001:
		return
	var p := global_position + fwd.normalized() * DRINK_REACH
	if not Overworld.is_water_at(p):
		return
	var wy := Overworld.water_y(p)
	if absf(wy - global_position.y) > 1.5:
		return
	_water_target = Vector3(p.x, wy, p.z)
	_water_is_sea = Overworld.water_is_sea(p)


func _has_waterskin() -> int:
	return _find_item_index("Waterskin")


func _skin_fills(idx: int) -> int:
	if idx < 0 or idx >= inventory.size():
		return 0
	return int(inventory[idx].get("fills", 0))


func _set_skin_fills(idx: int, n: int) -> void:
	if idx < 0 or idx >= inventory.size():
		return
	n = clampi(n, 0, SKIN_FILLS)
	inventory[idx]["fills"] = n
	inventory[idx]["weight"] = SKIN_WEIGHT + SKIN_WATER_WEIGHT * float(n)
	_refresh_inventory_ui()


func _apply_drink(amount: float, what: String) -> void:
	if thirst_survival():
		thirst = minf(THIRST_MAX, thirst + amount)
		thirst_show = 2.5
	else:
		stamina = minf(max_stamina, stamina + amount * 0.6)
		stam_show = 1.5
		_refreshed_t = REFRESHED_SECONDS
	cam_punch = maxf(cam_punch, 0.25)
	_add_log_msg(what, Color(0.62, 0.82, 1.0))


## E at water. Repeats as fast as you can swallow.
func _drink_water() -> void:
	if _water_target == Vector3.INF or _drink_cd > 0.0:
		return
	if _water_is_sea:
		_drink_cd = 1.0
		_add_log_msg("Brine. It would only make it worse.", Color(0.85, 0.85, 0.75))
		return
	_drink_cd = 1.1
	WaterAudio.play(self, "gulp", global_position + Vector3.UP * 1.2, -2.0)
	_apply_drink(THIRST_DRAUGHT, "You drink deep" if thirst_survival() else "Cold water -- you feel it in your legs")


## F at water with a skin in the pack.
func _fill_waterskin() -> void:
	var idx := _has_waterskin()
	if idx < 0 or _water_target == Vector3.INF or _drink_cd > 0.0:
		return
	if _water_is_sea:
		_drink_cd = 1.0
		_add_log_msg("You do not fill a skin from the sea", Color(0.85, 0.85, 0.75))
		return
	if _skin_fills(idx) >= SKIN_FILLS:
		_add_log_msg("The waterskin is full", Color(0.8, 0.8, 0.8))
		return
	_drink_cd = 1.4
	_set_skin_fills(idx, SKIN_FILLS)
	WaterAudio.play(self, "fill_skin", global_position + Vector3.UP * 0.6, -3.0)
	_add_log_msg("Waterskin filled -- %d draughts" % SKIN_FILLS, Color(0.62, 0.82, 1.0))


## Click the Waterskin in the pack (or the wheel): one pull.
func _drink_skin(idx: int) -> void:
	var n := _skin_fills(idx)
	if n <= 0:
		_add_log_msg("The waterskin is empty -- fill it at fresh water (F)", Color(0.9, 0.75, 0.4))
		return
	if thirst_survival() and thirst >= THIRST_MAX - 1.0:
		_add_log_msg("Not thirsty -- save it", Color(0.8, 0.8, 0.8))
		return
	_set_skin_fills(idx, n - 1)
	WaterAudio.play(self, "gulp", global_position + Vector3.UP * 1.2, -4.0)
	_apply_drink(SKIN_DRAUGHT, "A pull on the waterskin -- %d left" % (n - 1))


## Old saves have no skin; every wanderer gets one.
func _ensure_waterskin() -> void:
	if _has_waterskin() >= 0:
		return
	inventory.append({"name": "Waterskin", "weight": SKIN_WEIGHT + SKIN_WATER_WEIGHT * float(SKIN_FILLS),
		"count": 1, "slot": "", "fills": SKIN_FILLS, "keep": true})


func _update_swim(delta: float) -> bool:
	var wy: float = Overworld.water_y(global_position)
	var depth: float = (wy - global_position.y) if wy != Overworld.NO_WATER else -1.0
	if not swimming:
		if depth < SWIM_DEPTH:
			_set_water_tint(0.0)
			return false
		swimming = true
		crouching = false
		prone = false
		sprinting = false
		_fall_speed = 0.0
		velocity.y = maxf(velocity.y, -2.0)     ## the water takes the fall
		_drop_carried_logs("you went into the water")
		_add_log_msg("Swimming", Color(0.62, 0.80, 1.0))
		WaterAudio.play(self, "splash_in", global_position, 0.0)
		_stroke_t = 0.4
	elif depth < SWIM_EXIT_DEPTH:
		swimming = false
		_fall_speed = 0.0
		_set_water_tint(0.0)
		WaterAudio.play(self, "splash_out", global_position, -3.0)
		return false

	## --- the swim frame ---
	move_input = Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move_input.z -= 1.0
	if Input.is_key_pressed(KEY_S): move_input.z += 1.0
	if Input.is_key_pressed(KEY_A): move_input.x -= 1.0
	if Input.is_key_pressed(KEY_D): move_input.x += 1.0
	move_input += _pad_move()   ## CONTROLLER: left stick
	var dir := (transform.basis * move_input).normalized()
	dir.y = 0.0
	var tired := stamina <= 0.0
	var spd := SWIM_SPEED * stats.speed_mult() * (0.45 if tired else 1.0)
	var hv := Vector3(velocity.x, 0.0, velocity.z).move_toward(dir * spd, SWIM_ACCEL * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	## never under the bed: a hold (snapper, the Drowned) or a shove can put
	## the body inside the heightfield, and from inside it falls straight
	## through to the -60 m net and the valley
	var bed_y: float = Overworld.ground_y(global_position)
	if global_position.y < bed_y + 0.15:
		global_position.y = bed_y + 0.15
		velocity.y = maxf(velocity.y, 0.0)
	## buoyancy: the feet settle where the surface is SWIM_FLOAT_EYE under the eyes
	var float_y := wy - (_eye_h - SWIM_FLOAT_EYE)
	var want_vy := clampf((float_y - global_position.y) * 3.0, -2.2, 2.2)
	if Input.is_key_pressed(KEY_SPACE) and not tired:
		want_vy = SWIM_VERT
	elif Input.is_key_pressed(KEY_C):
		want_vy = -SWIM_VERT
	velocity.y = move_toward(velocity.y, want_vy, 9.0 * delta)
	if dir != Vector3.ZERO or want_vy > 0.5:
		stamina = maxf(0.0, stamina - SWIM_DRAIN * stats.stamina_cost_mult() * delta)
		stamina_delay = maxf(stamina_delay, 0.4)
		_stroke_t -= delta
		if _stroke_t <= 0.0:
			_stroke_t = SWIM_STROKE_GAP * (0.7 if tired else 1.0)
			WaterAudio.play(self, "swim_stroke_%d" % randi_range(1, 3),
				global_position + Vector3.UP * 0.9, -8.0 if _swim_face > 0.5 else -3.0)
	jump_queued = false
	_frame_fx_and_regen(delta)
	move_and_slide()
	## the lens under the surface wears a blue-green veil
	var cam_y := camera.global_position.y if camera != null else global_position.y + _eye_h
	_set_water_tint(1.0 if cam_y < wy - 0.05 else 0.0)
	_breath_tick(delta, _swim_face)
	_was_on_floor = false
	_update_body_arms(delta)
	_update_hud(delta)
	_update_log(delta)
	return true


func _set_water_tint(on: float) -> void:
	if _water_tint == null:
		if hud_layer == null or on <= 0.0:
			return
		_water_tint = ColorRect.new()
		_water_tint.name = "WaterTint"
		_water_tint.color = Color(0.05, 0.20, 0.28, 0.0)
		_water_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
		_water_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud_layer.add_child(_water_tint)
		hud_layer.move_child(_water_tint, 0)
	_swim_face = lerpf(_swim_face, on, 0.35)
	_water_tint.color.a = 0.32 * _swim_face   ## the fog does the rest (World)
	_water_tint.visible = _swim_face > 0.01
	WaterAudio.set_submerged(self, _swim_face)


func _update_darkness() -> void:
	## Edge-triggered like the hunch: entering the dark pulls the torch out
	## (with the shield when you own both); stepping back into the light
	## restores whatever you carried before — unless you chose otherwise
	## with Q while it was dark.
	## [terrain] Depth from the LOCAL surface, not raw y: the map runs to -27
	## at the sea floor, and raw y drew the torch on every beach in Maine.
	var dark := Overworld.depth_below_surface(global_position) > 3.0
	if not dark:
		var w := get_tree().get_first_node_in_group("world")
		if w != null and w.has_method("is_dark_out"):
			dark = bool(w.call("is_dark_out"))
	if dark == _in_dark:
		return
	_in_dark = dark
	if dark:
		_dark_prev_names = [_slot_name("offhand"), _slot_name("offhand2")]
		_dark_manual = false
		var shield_nm := ""
		var torch_nm := ""
		for nm in _offhand_owned_names():
			if shield_nm == "" and nm.contains("Shield"):
				shield_nm = nm
			elif torch_nm == "" and nm.contains("Torch"):
				torch_nm = nm
		if torch_nm != "":
			if shield_nm != "":
				_set_offhand_pair(shield_nm, torch_nm)
			else:
				_set_offhand_pair(torch_nm, "")
			_add_log_msg("Dark — the torch comes out", Color(1.0, 0.75, 0.35))
	elif not _dark_manual and _dark_prev_names.size() == 2:
		_set_offhand_pair(_dark_prev_names[0], _dark_prev_names[1])


func _offhand_owned_names() -> Array[String]:
	## Everything the left arm COULD hold: offhand items in the pack plus
	## whatever is already on the arm.
	var out: Array[String] = []
	for it in inventory:
		if String(it.get("slot", "")) == "offhand" and not out.has(String(it.name)):
			out.append(String(it.name))
	for slot in ["offhand", "offhand2"]:
		var nm := _slot_name(slot)
		if nm != "" and not out.has(nm):
			out.append(nm)
	return out


func _set_offhand_pair(nm_a: String, nm_b: String) -> void:
	## Arrange the left arm EXACTLY: everything comes off first (back into
	## the grid, forced — never lost), then the named items come out of it.
	for slot in ["offhand", "offhand2"]:
		var old: Dictionary = _slot_item(slot)
		if not old.is_empty():
			_give_item_dict(old, true)
		equipment[slot] = {}
	if nm_a != "":
		var i := _find_item_index(nm_a)
		if i >= 0:
			_equip_from_pack(i, "offhand")
	if nm_b != "":
		var j := _find_item_index(nm_b)
		if j >= 0:
			_equip_from_pack(j, "offhand2")
	if menu_open == "tab" and tab_page == "inventory":
		_refresh_inventory_ui()


func _update_hunch(delta: float) -> void:
	## THE HUNCH: a prickle on the back of the neck. The instant something out
	## there turns hostile the blade — and the shield with it — clears the
	## scabbard on its own; after HUNCH_SHEATHE_AFTER quiet seconds everything
	## rides home again. Toggleable in the Esc settings menu.
	## TODO(design): should the hunch also yank you off the pickaxe/bow onto
	## the sword when something jumps you mid-mining? For now it minds the
	## sword only — tools are a choice.
	## The reach owns both hands: the hunch may not yank the blade out from
	## under it (it would fight the sheathe every frame of the crouch).
	if not set_hunch or current_weapon != "sword" or mount != null \
			or kd_phase != "" or reach_phase != "":
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
		mi += _pad_move()   ## CONTROLLER: the left stick works the reins too
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


func _try_interact() -> void:
	## F: dismounting always wins; then a bed within reach; then mounting.
	if mount != null or kd_phase != "" or climbing:
		_try_mount_toggle()
		return
	for b in get_tree().get_nodes_in_group("beds"):
		if b is Node3D and (b as Node3D).global_position.distance_to(global_position) < 2.4:
			_sleep(b as Node3D)
			return
	_try_mount_toggle()


func _use_firepit(f: Firepit) -> void:
	## E on a fire pit. ONE VERB, and what it does is decided by what is burning
	## and what you are carrying:
	##
	##   burning          -> feed it, if you have wood
	##   embers + wood    -> back up to a flame; embers never need a torch
	##   cold + lit torch -> strike it, and put your first log straight in
	##   nothing to give  -> it says what it wants
	##
	## No new binding: E is already the interact verb that drinks, packs the
	## bedroll, gathers rock and hoists a log.
	if f == null or not is_instance_valid(f):
		return
	var idx := -1
	var fuel_name := ""
	for nm in Firepit.FUEL_ITEMS.keys():
		var i := _find_item_index(str(nm))
		if i >= 0:
			idx = i
			fuel_name = str(nm)
			break
	var torch: bool = offhand_shown.contains("Torch") or offhand_shown2.contains("Torch")

	if f.burning() and f.state == Firepit.State.LIT:
		if idx < 0:
			_add_log_msg("Burning -- about %d min left. It wants wood."
				% int(f.minutes_left()), Color(1.0, 0.78, 0.45))
			return
		if not _spend_fuel_item(idx):
			return
		f.feed(Firepit.fuel_value(fuel_name))
		_add_log_msg("%s on the fire -- about %d min of burning"
			% [fuel_name, int(f.minutes_left())], Color(1.0, 0.72, 0.36))
		return

	if f.state == Firepit.State.EMBERS and idx >= 0:
		if not _spend_fuel_item(idx):
			return
		f.feed(Firepit.fuel_value(fuel_name))
		_add_log_msg("The embers take the %s and come back up" % fuel_name.to_lower(),
			Color(1.0, 0.72, 0.36))
		return

	if not f.can_light():
		_add_log_msg("The wind takes every spark -- it needs a roof over it",
			Color(0.72, 0.80, 0.92))
		return
	if not torch:
		if f.state == Firepit.State.EMBERS:
			_add_log_msg("Embers, still warm -- feed them before they go",
				Color(1.0, 0.78, 0.45))
		else:
			_add_log_msg("Nothing to light it with -- a lit torch would do it",
				Color(0.80, 0.80, 0.80))
		return
	if not f.light():
		return
	if idx >= 0 and _spend_fuel_item(idx):
		f.feed(Firepit.fuel_value(fuel_name))
	_add_log_msg("The fire takes -- about %d min of burning" % int(f.minutes_left()),
		Color(1.0, 0.72, 0.36))


func _spend_fuel_item(idx: int) -> bool:
	## One off the stack, the same shape _place_bedroll spends its bedroll.
	if idx < 0 or idx >= inventory.size():
		return false
	var it: Dictionary = inventory[idx]
	it.count = int(it.count) - 1
	if int(it.count) <= 0:
		_remove_inventory_index(idx)
	_refresh_inventory_ui()
	return true


func _pack_bedroll(bed: Node3D) -> void:
	## Look + E: the bed folds into the backpack and straps onto the rucksack
	## (the bundle on your back shows it). Put it down again from the
	## inventory (click the Bedroll item) — camp anywhere the ground allows.
	if not _give_item("Bedroll", 1, 4.0):
		return  ## refused (a second bed, or a full pack) — it stays standing
	bed.queue_free()
	_push_gain("Bedroll", 1)
	_bed_target = null


func _place_bedroll(idx: int) -> void:
	## Click the Bedroll item: it unrolls on the ground just ahead of you.
	var fwd := -camera.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.001:
		fwd = -transform.basis.z
	fwd = fwd.normalized()
	var spot := global_position + fwd * 1.9
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 2.5, spot + Vector3.DOWN * 8.0)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty() or (hit.normal as Vector3).y < 0.55:
		_add_log_msg("No flat ground for the bedroll here", Color(0.8, 0.8, 0.8))
		return
	var bed := Bedroll.new()
	get_parent().add_child(bed)
	bed.global_position = (hit.position as Vector3) + Vector3.UP * 0.02
	bed.rotation.y = atan2(fwd.x, fwd.z) + PI
	## Spend one from the pack.
	var it := inventory[idx]
	it.count = int(it.count) - 1
	if int(it.count) <= 0:
		_remove_inventory_index(idx)
	_add_log_msg("Bedroll placed — F beside it to sleep", Color(0.85, 0.9, 1.0))
	_refresh_inventory_ui()


func _night_ahead() -> Dictionary:
	## Everything `Slumber` needs, read off the world at the moment the player
	## lies down. The sky is NOT forecast — you are walked against the weather
	## you went to bed in, because a forecast would be a lie you cannot see
	## into. The one thing that does change over the night is the FIRE, which
	## is the one thing you had a choice about, so its fuel comes along with
	## its heat.
	var e := _exposure_env()
	var season := int(e.get("season", 0))
	var hour := float(e.get("hour", 21.0))
	var planned := Slumber.hours_until(hour, Slumber.wake_hour(season))
	if god or not warmth_survival():
		## God mode pins the meter and Light mode has no meter to pin. The
		## night still PASSES — that is the bug being fixed — it just cannot
		## wake anybody.
		return {
			"warmth": exposure.warmth, "wet": exposure.wet,
			"hours_slept": planned, "hours_planned": planned,
			"woke": Slumber.WOKE_DAWN, "hour": Slumber.hour_after(hour, planned),
			"days": Slumber.days_crossed(hour, planned), "rest": 1.0,
			"coldest": 0.0, "fire_out_h": -1.0, "steps": 0,
		}
	var fire0 := float(e.get("fire_c", 0.0))
	var fuel := 0.0
	for f in get_tree().get_nodes_in_group("fires"):
		var pit := f as Node3D
		if pit == null or not ("fuel" in pit):
			continue
		if pit.global_position.distance_to(global_position) > Firepit.FIRE_RANGE:
			continue
		fuel = maxf(fuel, float(pit.get("fuel")))
	return Slumber.night(e, exposure.warmth, exposure.wet, planned, fire0, fuel)


func _apply_slept() -> void:
	## What the night was worth. A whole one closes the whole wound, exactly as
	## sleeping always did — taking that away would be a nerf nobody asked for
	## — and a night broken at four in the morning closes the fraction of it
	## you actually got. The reward for a warm camp is an UNINTERRUPTED night,
	## not a stronger one.
	var r: Dictionary = _slept
	var rest := clampf(float(r.get("rest", 1.0)), 0.0, 1.0)
	health = Slumber.heal_to(health, max_health, rest)
	stamina = Slumber.heal_to(stamina, max_stamina, rest)
	health_show = 2.0
	if not r.is_empty():
		exposure.warmth = clampf(float(r.get("warmth", exposure.warmth)),
				0.0, Exposure.WARMTH_MAX)
		exposure.wet = clampf(float(r.get("wet", exposure.wet)), 0.0, 1.0)
		warmth_show = 3.0
		if thirst_survival():
			thirst = Slumber.thirst_after(thirst, thirst_rate_per_sec(),
					float(r.get("hours_slept", 0.0)))
			thirst_show = 3.0
	var line: Array = Slumber.wake_line(r)
	_add_log_msg(String(line[0]), line[1] as Color)
	_slept = {}


func _sleep(_bed: Node3D) -> void:
	## Sleep until dawn — as a SEQUENCE now: lie down onto the bedroll (eyes
	## sink and tilt), BLACK SCREEN while the underground reseeds and re-carves
	## off-stage (the SHIFTING CAVES), then rise with the dawn. Input is
	## locked for the whole ritual.
	if _any_enemy_mad_at_me():
		_add_log_msg("No sleep — something out there means you harm", Color(1.0, 0.62, 0.35))
		return
	if Overworld.depth_below_surface(global_position) > 1.5:
		## The shift re-carves the deep — sleeping down there would entomb you.
		## TODO(design): step 9's player stability bubble lifts this rule.
		_add_log_msg("Too deep to sleep — the shifting earth would swallow you", Color(1.0, 0.62, 0.35))
		return
	var w := get_tree().get_first_node_in_group("world")
	if w == null or not w.has_method("sleep_at_bed"):
		return
	_drop_carried_logs("you lay down")
	input_locked = true
	sleep_phase = "lying"
	crouching = false
	_v_held = false
	velocity = Vector3.ZERO
	## Getting INTO bed: the eyes glide down over the roll and tilt to rest.
	var tw := create_tween()
	tw.tween_property(self, "_eye_h", 0.5, 0.95).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(cam_arm, "rotation_degrees:z", 13.0, 0.95) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_sleep_blackout)


func _sleep_blackout() -> void:
	var w := get_tree().get_first_node_in_group("world")
	if w == null:
		_sleep_rise()
		return
	## Walk the night BEFORE the clock moves, because how much of it you
	## actually get is what the clock is then moved BY. A man the cold wakes at
	## four in the morning wakes the world at four in the morning.
	_slept = _night_ahead()
	if not bool(w.call("sleep_at_bed", float(_slept.get("hours_slept", 0.0)))):
		## The earth's still settling (deep threads busy) — wake back up.
		_add_log_msg("Restless — the earth is still settling. Try again shortly.", Color(0.8, 0.8, 0.8))
		_slept = {}
		_sleep_rise()
		return
	sleep_phase = "black"
	if w.has_method("set_blackout"):
		w.call("set_blackout", true, "The world shifts beneath you...")


func _sleep_poll() -> void:
	## Runs each locked physics tick: once the shifted deep is fully rebuilt,
	## dawn breaks — fade the black away and get up.
	if sleep_phase != "black":
		return
	var w := get_tree().get_first_node_in_group("world")
	if w == null or not w.has_method("is_world_ready") or not bool(w.call("is_world_ready")):
		return
	if w.has_method("set_blackout"):
		w.call("set_blackout", false, "")
	## [coldscreen] Read BEFORE _apply_slept(), which clears `_slept`. A
	## night that ended at four in the morning because the fire went out
	## should not open the same way as one that ran to dawn: it holds the
	## dark longer, comes up slower, and opens on a hard shiver. Until
	## this, the whole difference was one line of log text.
	var woke_cold := String(_slept.get("woke", Slumber.WOKE_DAWN)) == Slumber.WOKE_COLD
	_apply_slept()
	cold.wake(woke_cold)
	_sleep_rise()


func _sleep_rise() -> void:
	## Getting OUT of bed: the eyes lift and level — then the body is yours.
	sleep_phase = "rising"
	var tw := create_tween()
	tw.tween_property(self, "_eye_h", 1.62, 1.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(cam_arm, "rotation_degrees:z", 0.0, 1.05) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(_sleep_done)


func _sleep_done() -> void:
	sleep_phase = ""
	input_locked = false


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
	if best.has_method("can_carry") and not best.can_carry():
		_add_log_msg("The horse is too spooked to carry anyone — let it breathe", Color(0.8, 0.8, 0.8))
		return
	_mount(best)


func _mount(h: Horse) -> void:
	if current_weapon != "sword":
		_select_weapon("sword")  ## only the sword works from the saddle
	_drop_carried_logs("you swung into the saddle")
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
	dmg *= GameMode.creature_damage_mult(attacker)   ## hooves are a creature too
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
	if god:
		return  ## ...except god mode. Every knockdown path funnels through here.
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
	if body_skin != null and cam_mode == "tp" and mount == null:
		## the body you can see goes limp for real; the camera fall below is
		## still what sells it from inside
		body_skin.ragdoll_start(Vector3(fling.x, 1.0, fling.z) * 0.6, 999.0, false)


func knockdown(fling: Vector3 = Vector3.ZERO, _seconds := 2.4) -> void:
	## Shoved off your feet by something heavier at speed (CreatureSkin's
	## shove rules — a charging moose, a bolting horse). Same fall as a kick.
	if kd_phase != "" or mount != null or invuln_timer > 0.0:
		return
	_start_knockdown(global_position - fling, Vector3(fling.x, 0.0, fling.z))


func _body_up() -> void:
	## Start standing the visible body back up (blend from the ragdoll pose).
	if body_skin != null and body_skin.ragdoll:
		body_skin.ragdoll_stop()


func _stand_up_hard() -> void:
	## End a knockdown OUT OF ORDER — dying face-down, or reloading a save while
	## pinned — instead of walking the "rise" phase that normally cleans up.
	##
	## THE BUG THIS FIXES: _update_knockdown lays the visible body down by
	## writing body_rig.rotation_degrees.x = 82 AND body_rig.position.z = -0.95,
	## and ONLY the end of "rise" (kd_phase -> "") ever undoes them. Skip that
	## and the tilt quietly heals itself in _update_action_camera's lerp, but
	## NOTHING anywhere else writes body_rig.position — so the body stands a
	## metre in FRONT of the lens for the rest of the run, which in first person
	## reads exactly as "my camera is several feet behind my player". Death and
	## load both take that shortcut, so both come through here.
	if pinned_by != null or _pin_watch != null:
		pinned_by = null
		pin_t = 0.0
		_hide_pin_prompt()
		if _pin_watch != null and is_instance_valid(_pin_watch):
			_pin_watch.queue_free()
		_pin_watch = null
	kd_phase = ""
	kd_t = 0.0
	kd_bounce = 0.0
	swimming = false
	_set_water_tint(0.0)
	## The manhandle states die here too — death and load must never leave
	## you hanging off a jaw that no longer has you (same class of bug as the
	## body_rig shift below: an out-of-order exit has to undo EVERYTHING).
	grabbed_by = null
	grab_t = 0.0
	pressed_by = null
	press_t = 0.0
	if body_col:
		body_col.set_deferred("disabled", false)
	_body_up()
	if body_rig != null:
		body_rig.position = Vector3.ZERO
		body_rig.rotation_degrees.x = 0.0
	if camera != null:
		camera.rotation_degrees.z = 0.0
	_update_head_offset()


func _update_knockdown(delta: float) -> void:
	kd_t += delta
	blocking = false
	sprinting = false
	if not is_on_floor():
		velocity.y -= gravity * delta
	velocity.x = move_toward(velocity.x, 0.0, 6.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 6.0 * delta)
	move_and_slide()

	## The camera sells the fall: drop hard, BOUNCE off the dirt like a body
	## (not a tripod), lie there, then climb back up with a stagger.
	## (Mouse-look stays live — you watch it happen.) NO invulnerability at
	## any point: whatever's out there is free to keep hitting you.
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
				kd_bounce = 1.0  ## the impact: loose weight hits and rebounds
		"pinned":
			## Under a fallen trunk (spec §8b). You stay exactly where the
			## impact left you — no rise timer at all. FallenTrunk rolling off
			## calls release_pin(), which is the only thing that ends this.
			head.position.y = 0.50 + sin(kd_t * 3.0) * 0.010
			roll = 24.0
		"down":
			## Ragdoll settle: a couple of damping bounces off the impact,
			## melting into the ragged-breath stillness.
			kd_bounce = maxf(0.0, kd_bounce - delta * 2.4)
			var bounce := absf(sin(kd_t * 13.0)) * 0.11 * kd_bounce * kd_bounce
			head.position.y = 0.50 + bounce + sin(kd_t * 5.0) * 0.012
			roll = 26.0 + sin(kd_t * 13.0) * 7.0 * kd_bounce
			if kd_t >= KD_DOWN:
				kd_phase = "rise"
				kd_t = 0.0
				_body_up()
		"rise":
			var u := clampf(kd_t / KD_RISE, 0.0, 1.0)
			var e := u * u * (3.0 - 2.0 * u)
			head.position.y = lerpf(0.50, 1.62, e) - sin(u * PI) * 0.06  ## a wobble on the way up
			roll = 26.0 * (1.0 - e)
			if u >= 1.0:
				kd_phase = ""
				kd_t = 0.0
				if body_rig:
					body_rig.position = Vector3.ZERO   ## back on your feet
					body_rig.rotation_degrees.x = 0.0
				_update_head_offset()  ## hand the camera back to mouse-look
	## RAGDOLL HONESTY: the fallen head lands ON the ground, never through it.
	## The capsule's feet ride the slope, but a half-meter eye on lumpy voxel
	## rock (with the anti-peek head sphere way up at standing height) could
	## dip beneath the surface and stare at the underside of the world — then
	## get "spat back out" on the rise. Read the ground directly under the
	## head's spot and keep the lens resting above it through every phase.
	var head_flat := to_global(Vector3(head.position.x, 0.0, head.position.z))
	var gq := PhysicsRayQueryParameters3D.create(
		head_flat + Vector3.UP * 1.6, head_flat + Vector3.DOWN * 2.5)
	gq.exclude = [get_rid()]
	var ghit: Dictionary = get_world_3d().direct_space_state.intersect_ray(gq)
	if not ghit.is_empty() and not (ghit.collider is CharacterBody3D):
		var min_eye := minf((ghit.position as Vector3).y + 0.30 - global_position.y, 1.55)
		head.position.y = maxf(head.position.y, min_eye)
	## THE BODY GOES DOWN WITH THE CAMERA. It used to stay standing while the eye
	## dropped to half a metre, which put the lens inside your own torso — every
	## knockdown in first person was spent staring up between your knees.
	## Tipping the rig onto its back and sliding it forward puts your legs out
	## ahead of you on the ground, which is what you should see lying there.
	if body_rig:
		var lay := 0.0
		match kd_phase:
			"fall":
				lay = clampf(kd_t / KD_FALL, 0.0, 1.0)
			"down", "pinned":
				lay = 1.0
			"rise":
				lay = 1.0 - clampf(kd_t / KD_RISE, 0.0, 1.0)
		var le := lay * lay * (3.0 - 2.0 * lay)
		body_rig.rotation_degrees = Vector3(82.0 * le, body_rig.rotation_degrees.y, 0.0)
		body_rig.position = Vector3(0.0, 0.0, -0.95 * le)

	camera.rotation_degrees.z = roll

	_frame_fx_and_regen(delta)
	_update_hud(delta)
	_update_log(delta)


func notify(text: String, col := Color(0.9, 0.9, 1.0)) -> void:
	## Public log hook (horses use it to tell you the trust just died).
	_add_log_msg(text, col)


## ================= Manhandled (bear jaws / bear weight) ====================


func creature_grab(attacker: Node3D, dmg: float) -> String:
	## A jaw closes on you (Lemon, 2026-08-29). Timing still saves you — dash
	## i-frames slip it, a perfect guard turns it into a stagger — but
	## anything less and you are IN THE MOUTH: your body hangs off the animal
	## (its grab_anchor(), read every frame) until it throws you or something
	## hits it hard enough that it lets go.
	if god or grabbed_by != null or pressed_by != null or mount != null or kd_phase != "" \
			or input_locked or climbing or attacker == null:
		return "no"
	if invuln_timer > 0.0:
		if dash_timer > 0.0 and dodge_cd <= 0.0:
			dodge_cd = 0.5
			_add_log_msg("Dodged!", Color(0.55, 0.95, 1.0))
			_record_progress("untouchable", 1)
		return "dodged"
	if blocking and block_held_time <= PARRY_WINDOW:
		block_held_time = 999.0
		block_impact = 0.22
		cam_shake = maxf(cam_shake, 0.12)
		_add_log_msg("Parried!", Color(1.0, 0.95, 0.55))
		if attacker.has_method("on_parried"):
			attacker.on_parried()
		_record_progress("perfect_guard", 1)
		return "parried"
	_drop_carried_logs("the jaws closed on you")
	take_damage(dmg, attacker.global_position, true, Vector3.INF, attacker)
	if health <= 0.0 or kd_phase != "":
		return "no"   ## the clamp itself finished it — nothing left to carry
	grabbed_by = attacker
	grab_t = 0.0
	attacking = false
	draw_attack = false
	drawing = false
	bow_draw = 0.0
	blocking = false
	climbing = false
	pick_swinging = false
	dash_timer = 0.0
	hitstun_timer = 0.0
	velocity = Vector3.ZERO
	if body_col:
		body_col.set_deferred("disabled", true)   ## carried: no capsule fights
	cam_shake = maxf(cam_shake, 0.5)
	_add_log_msg("It has you!", Color(1.0, 0.40, 0.25))
	return "grabbed"


func _update_grabbed(delta: float) -> void:
	grab_t += delta
	blocking = false
	sprinting = false
	var b := grabbed_by
	## [water] a holder that keeps its own clock (the snapper, the Drowned)
	## says how long it may keep you; a jaw without one gets the bear's 4.5 s
	var hold_max := 4.5
	if is_instance_valid(b) and b.has_method("hold_seconds"):
		hold_max = float(b.call("hold_seconds"))
	if b == null or not is_instance_valid(b) or ("dying" in b and bool(b.get("dying"))) \
			or grab_t > hold_max:
		grab_release(Vector3.ZERO)   ## whatever held you stopped holding
		return
	## [water] STRUGGLE: Space or the attack button, each press once, tells a
	## holder that listens. The Drowned and the snapper count them.
	if b.has_method("struggled"):
		var sp := Input.is_key_pressed(KEY_SPACE)
		var cl := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		if sp and not _struggle_space_held:
			b.call("struggled")
		if cl and not _struggle_click_held:
			b.call("struggled")
		_struggle_space_held = sp
		_struggle_click_held = cl
	## [water] held under: the tint, the muffle and the breath all follow the
	## lens against the surface, exactly as they do when you swim
	var wy_g: float = Overworld.water_y(global_position)
	if wy_g != Overworld.NO_WATER:
		var cam_y_g := camera.global_position.y if camera != null else global_position.y + _eye_h
		_set_water_tint(1.0 if cam_y_g < wy_g - 0.05 else 0.0)
		_breath_tick(delta, _swim_face)
	if b.has_method("grab_anchor"):
		var a: Dictionary = b.call("grab_anchor")
		var target: Vector3 = a.get("pos", global_position)
		global_position = global_position.lerp(target, clampf(delta * 22.0, 0.0, 1.0))
	velocity = Vector3.ZERO
	## You hang and you thrash: the lens rolls with the shaking, the visible
	## body dangles. Mouse-look stays yours — you watch it happen.
	cam_shake = maxf(cam_shake, 0.10)
	if camera:
		camera.rotation_degrees.z = lerpf(camera.rotation_degrees.z,
			13.0 * sin(grab_t * 8.5), clampf(delta * 8.0, 0.0, 1.0))
	if body_rig:
		body_rig.rotation_degrees.x = lerpf(body_rig.rotation_degrees.x, 38.0,
			clampf(delta * 10.0, 0.0, 1.0))
	_frame_fx_and_regen(delta)
	_update_hud(delta)
	_update_log(delta)


func grab_release(vel: Vector3) -> void:
	## The jaw opens. With a real throw vector you leave sideways and eat
	## dirt; with none you are simply dropped where it stood.
	if grabbed_by == null:
		return
	var from := (grabbed_by as Node3D).global_position if is_instance_valid(grabbed_by) \
		else global_position + Vector3.BACK
	grabbed_by = null
	grab_t = 0.0
	if body_col:
		body_col.set_deferred("disabled", false)
	if camera:
		camera.rotation_degrees.z = 0.0
	if body_rig:
		body_rig.rotation_degrees.x = 0.0
		body_rig.position = Vector3.ZERO
	if vel.length() > 0.5:
		_add_log_msg("Thrown!", Color(1.0, 0.45, 0.30))
		_start_knockdown(from, Vector3(vel.x, 0.0, vel.z))
		velocity.y = maxf(velocity.y, vel.y + 1.2)
	else:
		hitstun_timer = 0.45
		velocity = Vector3.ZERO


func creature_press(attacker: Node3D) -> bool:
	## The other bad place to be (Lemon, 2026-08-29): the animal reared up
	## and came down ON you. You are not carried — you are UNDER it: barely
	## able to move, no jumping out, and a dash is the one honest way out
	## from underneath before the shove puts you flat.
	if god or pressed_by != null or grabbed_by != null or mount != null or kd_phase != "" \
			or input_locked or climbing or attacker == null:
		return false
	if invuln_timer > 0.0:
		return false
	pressed_by = attacker
	press_t = 0.0
	_drop_carried_logs("the weight came down on you")
	cam_shake = maxf(cam_shake, 0.4)
	_add_log_msg("It leans its weight onto you!", Color(1.0, 0.55, 0.30))
	return true


func creature_press_end(fling: Vector3) -> void:
	## The lean ends: shoved flat (a real fling), or simply released.
	if pressed_by == null:
		return
	var from := (pressed_by as Node3D).global_position if is_instance_valid(pressed_by) \
		else global_position + Vector3.BACK
	pressed_by = null
	press_t = 0.0
	if fling.length() > 0.5 and kd_phase == "" and mount == null:
		_add_log_msg("Shoved down!", Color(1.0, 0.45, 0.30))
		_start_knockdown(from, Vector3(fling.x, 0.0, fling.z))


func _update_gait(delta: float) -> void:
	## The one shared stride. Amplitude eases toward "how fast are we actually
	## moving" so animations breathe in and out instead of snapping, and the
	## phase only advances on the ground — nobody pumps their arms in mid-air.
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var target := clampf(hspeed / SPRINT_SPEED, 0.0, 1.0) if is_on_floor() else 0.0
	gait_amount = lerpf(gait_amount, target, clampf(delta * 6.0, 0.0, 1.0))
	if is_on_floor():
		gait_phase += delta * (4.5 + hspeed * 1.35)
	## [steps] FOOTFALL. The bob already dips the camera at every
	## |sin(gait_phase)| peak -- twice a stride, once per foot. The sound
	## lands on that same beat, so what you hear is exactly what you see at
	## any speed, with no second clock to drift. (If it ever reads too fast,
	## the one-line halving is PI -> TAU on the line below.)
	var _si := int(floor((gait_phase - PI * 0.5) / PI))
	if _si != _step_idx:
		var _first := _step_idx == -9999
		_step_idx = _si
		if not _first and is_on_floor() and gait_amount > 0.12 \
				and not swimming and kd_phase == "" and mount == null \
				and not climbing and not sliding:
			StepAudio.footfall(self, global_position, gait_amount,
				crouching, prone)
			## AND THE GRASS ANSWERS. A second, quieter grass hit on the same beat
			## whenever you are actually pushing through something — so the 15%
			## you lost reads as a meadow round your knees rather than as the game
			## hitching. No new pack: this is the footstep grass family, under the
			## step that made it.
			if wade > 0.25:
				StepAudio.footfall(self, global_position, gait_amount * wade * 0.7,
					true, prone, "grass")
	## Landing: remember how hard we fell, dip the view, spring softly back.
	if not is_on_floor():
		_fall_speed = maxf(0.0, -velocity.y)
	elif not _was_on_floor:
		land_dip = maxf(land_dip, clampf(_fall_speed * 0.014, 0.0, 0.16))
		StepAudio.landing(self, global_position, _fall_speed)  ## [steps]
		_apply_fall_damage(_fall_speed)
	_was_on_floor = is_on_floor()
	## F2 DROP-IN GRACE. It lasts until your feet are properly under you again.
	## The short hold covers the frame you dropped on, when is_on_floor() is
	## still reporting the ground the parked body was standing on.
	if _fall_grace:
		if _fall_grace_hold > 0.0:
			_fall_grace_hold -= delta
		elif is_on_floor():
			_fall_grace = false
	land_dip = lerpf(land_dip, 0.0, clampf(delta * 8.0, 0.0, 1.0))
	## Head-bob target: a gentle side sway, plus a dip at each footfall.
	## Wading widens the SWAY (you are shouldering side to side through it), not
	## the footfall dip — a bigger dip would just read as a limp.
	var bt := Vector2(
		sin(gait_phase) * 0.016 * (1.0 + wade * Locomotion.WADE_SWAY),
		(absf(sin(gait_phase)) - 0.5) * -0.022)
	head_bob = head_bob.lerp(bt * gait_amount, clampf(delta * 10.0, 0.0, 1.0))
	## SPEED IN THE LENS. The FOV push is the cheapest honest signal that you
	## are moving fast; it rides on top of whatever FOV the player chose in
	## Settings and is folded back to zero whenever a menu owns the screen.
	if camera != null:
		var want_fov := 0.0
		if menu_open == "" and not god and kd_phase == "" and mount == null:
			want_fov = Locomotion.fov_bonus(hspeed, SPEED, SPRINT_SPEED)
		_fov_extra = lerpf(_fov_extra, want_fov, clampf(delta * 4.5, 0.0, 1.0))
		camera.fov = set_fov + _fov_extra


func _update_footing(delta: float) -> void:
	## WHAT IS UNDER YOU, polled at 10 Hz and eased the rest of the way. Both
	## reads here cost real work — GrassPaint.value_at is an Image fetch and
	## StepAudio.family_at walks the ground paint — and neither answer can change
	## meaningfully inside a tenth of a second at 8 m/s. The EASING is what makes
	## it feel continuous; the poll is what makes it free.
	_footing_t -= delta
	var want_surf := _surface_mult
	var want_wade := wade
	if _footing_t <= 0.0:
		_footing_t = 0.1
		want_surf = 1.0
		want_wade = 0.0
		if not swimming and mount == null and not god and kd_phase == "":
			var wet := 0.0
			var bus := StepAudio.get_bus(self)
			if bus != null:
				wet = bus.wetness
			want_surf = Locomotion.surface_mult(
				StepAudio.family_at(global_position.x, global_position.z, wet))
			## The meadow. `grass_hidden` is GrassSystem's OWN stealth read, so the
			## grass that hides you and the grass that slows you are the same patch
			## by construction — you can never be concealed by grass you are
			## walking through at full speed.
			var dens := 1.0
			if GrassPaint.inst != null:
				var d := GrassPaint.density_of(
					GrassPaint.inst.value_at(global_position.x, global_position.z))
				if d >= 0.0:
					dens = d          ## negative = AUTO, i.e. the world's own rule
			var blade := Locomotion.BASE_BLADE
			if _grass_sys == null or not is_instance_valid(_grass_sys):
				_grass_sys = get_tree().get_first_node_in_group("grass_system")
			if _grass_sys != null and "style" in _grass_sys:
				var st: Dictionary = _grass_sys.get("style")
				blade = float(st.get("height", Locomotion.BASE_BLADE))
			want_wade = Locomotion.wade_amount(grass_hidden, dens, blade)
	var k := clampf(delta * 6.0, 0.0, 1.0)
	_surface_mult = lerpf(_surface_mult, want_surf, k)
	wade = lerpf(wade, want_wade, k)


func _apply_fall_damage(spd: float) -> void:
	## Called once at touchdown with the impact speed. Bypasses blocking and
	## i-frames — the ground doesn't care how good your guard is.
	##
	## ...unless it is switched off, which it is by default (Settings -> Fall
	## Damage). This ONE early return kills the health hit, the death, and the
	## hard-landing knockdown together: leaving the knockdown behind would read
	## as "fall damage is still on" even with the number at zero. The camera
	## dip and the landing sound are not damage and stay.
	## F2 DROP-IN: the fall you are in the middle of is the editor's, not yours
	## -- you were 300 m up because you were building, not because you jumped.
	## One free touchdown (no damage, no death, no knockdown), then it is spent
	## and the very next landing is judged normally.
	if _fall_grace:
		_fall_grace = false
		_fall_grace_hold = 0.0
		return
	if not set_fall_dmg or god:
		return
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
		## The stride's own roll, plus the BANK: cut across your own momentum and
		## the horizon tips the way you are leaning. Subtracted, because a bank
		## to the LEFT is a positive Y-up angle and a leftward roll is negative z.
		var roll := sin(gait_phase) * 0.4 * gait_amount - _bank * Locomotion.BANK_ROLL_DEG
		if sliding:
			roll += SLIDE_TILT   ## hip down, shoulder over: the slide has a SIDE
		camera.rotation_degrees.z = lerpf(camera.rotation_degrees.z, roll,
			clampf(delta * 8.0, 0.0, 1.0))


func _boxed_in() -> bool:
	## Blocked AHEAD is a wall, and a wall is not a bug. Blocked in EVERY
	## direction is a pocket, and only geometry that should not exist does that
	## to you. Eight probes, run only while something already looks wrong.
	for i in range(8):
		var a := TAU * float(i) / 8.0
		if move_and_collide(Vector3(cos(a), 0.0, sin(a)) * UNSTICK_PROBE, true) == null:
			return false
	return true


func _wedged_in_wood() -> Node3D:
	## The fallen trunk you are inside of, measured to its AXIS rather than its
	## origin -- a twenty-metre log has both ends ten metres from its centre.
	var best: Node3D = null
	var best_d := 2.2
	for t in get_tree().get_nodes_in_group("fallen_trunks"):
		var n3 := t as Node3D
		if n3 == null or not is_instance_valid(n3):
			continue
		var half := 4.0
		if "trunk_len" in n3:
			half = maxf(float(n3.get("trunk_len")) * 0.5, 0.5)
		var ax: Vector3 = n3.global_transform.basis.y.normalized()
		var rel: Vector3 = global_position - n3.global_position
		var along := clampf(rel.dot(ax), -half, half)
		var d := (rel - ax * along).length()
		if d < best_d:
			best_d = d
			best = n3
	return best


func _unwedge(delta: float, wants_to_move: bool) -> void:
	## WEDGED IN THE TIMBER. A settled trunk is a long cylinder with a crowd of
	## limb spheres bolted along it, resting propped at an angle; walk a capsule
	## into one of the pockets between those shapes and every slide plane points
	## into another one. move_and_slide then resolves to nothing in every
	## direction and you are stuck there for good -- there is no pin state to
	## time out and no rise timer, so from your side it is the game locking up.
	## FallenTrunk now drops those colliders when it freezes, which should mean
	## this never fires; this is the belt to that pair of braces, and it is
	## cheap because it only measures until you stop moving.
	if not wants_to_move or kd_phase != "" or climbing or mount != null \
			or input_locked or pinned_by != null or grabbed_by != null:
		_unstick_t = 0.0
		_unstick_from = global_position
		return
	if _unstick_t <= 0.0:
		_unstick_from = global_position
	_unstick_t += delta
	if _unstick_t < UNSTICK_WINDOW:
		return
	var moved := global_position.distance_to(_unstick_from)
	_unstick_t = 0.0
	_unstick_from = global_position
	if moved > UNSTICK_MOVED:
		return
	if not _boxed_in():
		return
	var wood := _wedged_in_wood()
	if wood == null:
		return
	## Out PERPENDICULAR to the log: that is the short way off it. Along the
	## trunk is twenty more metres of the same problem.
	var axis: Vector3 = wood.global_transform.basis.y.normalized()
	var out: Vector3 = global_position - wood.global_position
	out -= axis * out.dot(axis)
	out.y = 0.0
	if out.length_squared() < 0.01:
		out = -_flat_forward()
	var push := out.normalized()
	velocity = push * UNSTICK_PUSH + Vector3.UP * UNSTICK_HOP
	## Plus an immediate nudge, but only into space that is actually clear --
	## the cure for being inside the world is never a teleport further into it.
	var probe := push * 0.22 + Vector3.UP * 0.14
	if move_and_collide(probe, true) == null:
		global_position += probe
	_add_log_msg("You shove clear of the timber.", Color(0.78, 0.72, 0.58))


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
	var hit := move_and_collide(motion, true)
	if hit == null:
		return
	## A WALKABLE SLOPE IS NOT A STEP (2026-09-03). move_and_slide already walks
	## you up anything shallower than floor_max_angle. While this fired on those
	## too, every physics frame on a hillside — or on the gentle roll of the
	## meadow — handed the body a free 0.12 m lift, so you rode up the grass in
	## little hops and paid four body_test_motion queries a frame for the whole
	## walk. Only a face too steep to walk up is a step.
	if hit.get_normal().y > cos(floor_max_angle) - 0.02:
		return
	var params := PhysicsTestMotionParameters3D.new()
	var result := PhysicsTestMotionResult3D.new()
	for h: float in [0.12, 0.24, 0.36, STEP_HEIGHT]:
		var lifted := global_transform
		lifted.origin += Vector3.UP * h
		params.from = lifted
		params.motion = motion
		if not PhysicsServer3D.body_test_motion(get_rid(), params, result):
			## ...and there has to be a LEDGE up there to land on. Clear air
			## ahead of a lifted capsule is a gap or an overhang, not a stair.
			var landed := lifted
			landed.origin += motion
			params.from = landed
			params.motion = Vector3.DOWN * (h + 0.06)
			var has_top := PhysicsServer3D.body_test_motion(get_rid(), params, result)
			params.motion = motion
			if not has_top:
				return
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
	## In THIRD PERSON the body also acts out what the hands are doing: cuts,
	## guards, chops and draws are posed from the SAME state machines the
	## viewmodels animate from, so the arm reaches its impact exactly when the
	## damage lands (the held twins are shown by _update_tp_gear).
	var s := sin(gait_phase) * 0.6 * gait_amount
	var k := clampf(delta * 14.0, 0.0, 1.0)
	var tp := cam_mode == "tp"

	## Action poses. Vector3.INF = nothing special (fall through to the
	## stride); r_now marks authored arcs, applied absolute so no lerp drags.
	## SIGN NOTE (the backward-swing disease, do not reinfect): these arms hang
	## along -y and the body faces -z, so POSITIVE rotation.x swings an arm
	## FORWARD and negative points it behind. Chambers/reaches-behind go
	## negative; anything held up, out, or at a target goes positive.
	var r_pose := Vector3.INF
	var l_pose := Vector3.INF
	var r_now := false
	if tp:
		if attacking:
			var p := clampf(swing_t / (SWING_TIME * stats.swing_mult()), 0.0, 1.0)
			r_pose = _tp_swing_arm_pose(p)
			r_now = true
		elif axe_swinging:
			var pa := clampf(axe_t / (AXE_TIME * stats.swing_mult()), 0.0, 1.0)
			## Both axe strokes are cleaves now, mirrored — the body alternates
			## sides in step with the viewmodel instead of chopping overhead on
			## one and sweeping flat on the other.
			r_pose = _tp_chop_arm_pose(pa, AXE_WINDUP, true, 1.0 if axe_side == 0 else -1.0)
			r_now = true
		elif pick_swinging:
			var pp := clampf(pick_t / PICK_TIME, 0.0, 1.0)
			r_pose = _tp_chop_arm_pose(pp, PICK_WINDUP, false)
			r_now = true
		elif current_weapon == "bow" and (drawing or bow_release > 0.0):
			r_pose = Vector3(0.95, 0.0, 0.30 + 0.25 * bow_draw)  ## string hand anchored up by the cheek, elbow flaring with the draw
		elif blocking and sheath_t < 0.5:
			r_pose = Vector3(0.85, 0.0, -0.40)  ## blade held UP across the guard, in front
		elif pack_reach > 0.35:
			## Rummaging: the arm swings BACK and up to the rucksack's flap
			## (negative x = behind the body, where the rucksack actually is).
			r_pose = Vector3(-0.95 * pack_reach, 0.0, -0.55 * pack_reach)
		elif (current_weapon == "sword" and sheath_t < 0.5) \
				or current_weapon == "pickaxe" or current_weapon == "axe":
			r_pose = Vector3(-0.35 + s * 0.25, 0.0, 0.0)  ## armed carry, a ghost of stride
		if blocking and _offhand_is_shield():
			l_pose = Vector3(1.05, 0.0, 0.50)   ## shield up, braced across the body's FRONT
		elif current_weapon == "bow":
			l_pose = Vector3(1.30, 0.0, 0.10)   ## bow arm out FORWARD at the target
		elif tp_torch and tp_torch.visible:
			## Carrying the torch: forearm raised FORWARD so the flame rides
			## high and proud, with just a ghost of the stride left in it.
			l_pose = Vector3(0.55 + s * 0.25, 0.0, 0.0)

	## THE REACH overrides the stride, the carry and the gear both ways round:
	## out and DOWN to the thing on the ground, then back and UP over the
	## shoulder to the rucksack flap. Applied absolute (r_now) so no lerp drags
	## behind the hand -- the fist has to actually be where the item is.
	if reach_phase != "" or reach_out > 0.001 or reach_stow > 0.001:
		var ge := reach_out * reach_out * (3.0 - 2.0 * reach_out)
		var gs := reach_stow * reach_stow * (3.0 - 2.0 * reach_stow)
		r_pose = Vector3(GRAB_ARM_OUT * ge + GRAB_ARM_STOW * gs, 0.0,
			GRAB_ARM_FLARE * ge - 0.35 * gs)
		r_now = true
		l_pose = Vector3(0.30 * ge, 0.0, -0.18 * ge)   ## off hand braced on the knee

	if mount != null:
		## In the saddle: thighs forward, feet in the stirrups, arms quiet —
		## except mid-sweep, where TP shows the saddle cut on the body's arm.
		for lp in leg_pivots:
			lp.rotation.x = lerpf(lp.rotation.x, -1.15, k)
		if left_arm:
			left_arm.rotation.x = lerpf(left_arm.rotation.x, (l_pose.x if l_pose != Vector3.INF else -0.35), k)
			left_arm.rotation.z = lerpf(left_arm.rotation.z, (l_pose.z if l_pose != Vector3.INF else 0.0), k)
		if right_arm:
			if r_now:
				right_arm.rotation.x = r_pose.x
				right_arm.rotation.z = r_pose.z
			else:
				right_arm.rotation.x = lerpf(right_arm.rotation.x, (r_pose.x if r_pose != Vector3.INF else -0.35), k)
				right_arm.rotation.z = lerpf(right_arm.rotation.z, (r_pose.z if r_pose != Vector3.INF else 0.0), k)
		return

	if left_arm:
		left_arm.rotation.x = lerpf(left_arm.rotation.x, (l_pose.x if l_pose != Vector3.INF else s), k)
		left_arm.rotation.z = lerpf(left_arm.rotation.z, (l_pose.z if l_pose != Vector3.INF else 0.0), k)
	if right_arm:
		## In THIRD PERSON the body performs, so the arm is always there. In
		## first person it shows only when sheathed (a drawn sword's right hand
		## IS the camera viewmodel) — and never while pinching the bowstring.
		right_arm.visible = tp \
			or (sheath_t >= 0.5 and not (current_weapon == "bow" and (drawing or bow_release > 0.0)))
		if r_now:
			right_arm.rotation.x = r_pose.x
			right_arm.rotation.z = r_pose.z
		else:
			right_arm.rotation.x = lerpf(right_arm.rotation.x, (r_pose.x if r_pose != Vector3.INF else -s), k)
			right_arm.rotation.z = lerpf(right_arm.rotation.z, (r_pose.z if r_pose != Vector3.INF else 0.0), k)
	## Legs stride on the same beat, opposite their arm (left arm + right leg
	## forward together — an actual walk when you look down).
	for i in range(leg_pivots.size()):
		var lph := PI if i == 0 else 0.0
		leg_pivots[i].rotation.x = lerpf(leg_pivots[i].rotation.x, sin(gait_phase + lph) * 0.5 * gait_amount, k)


func _tp_swing_arm_pose(p: float) -> Vector3:
	## The body's sword cut (third person): one arm-borne arc with the same
	## three beats as the viewmodel swing — chamber, whip THROUGH (damage
	## lands at p≈0.62), follow and settle. Built on the enemies' shared cut
	## curve so mobs and player read as one fencing world.
	if mounted_swing:
		## Saddle sweep: a flat cut past the horse's neck, side by mounted_side.
		var sx := Enemy._cut_arc(p, -0.45, -1.45, 0.30)
		var sz := Enemy._cut_arc(p, 0.0, 0.85, -0.85) * (1.0 if mounted_side == 0 else -1.0)
		return Vector3(sx, 0.0, sz)
	## SIDE-TO-SIDE slashes (Lemon's call — no stab-with-a-windup). The arm
	## coils OUT to one side at chest height and whips FLAT across the front;
	## the old arc hauled the fist to -2.05 (behind the head) and drove it
	## forward, which read as a thrust from behind the camera. lat picks the
	## coil side — forehand (+1) starts right and sweeps left, the backhand
	## (combo 2) mirrors it, and the finisher is the forehand thrown wider.
	## Damage still lands at p≈0.62, where the fist crosses the front.
	var lat := -1.0 if combo_index == 2 else 1.0
	var wide := 1.15 if combo_index == 3 else 1.0
	var x := Enemy._cut_arc(p, -0.35, 0.55 * wide, 1.00 * wide)
	var z := Enemy._cut_arc(p, 0.0, 1.15 * wide, -1.25 * wide) * lat
	return Vector3(x, 0.0, z)


func _tp_chop_arm_pose(p: float, windup: float, cleave: bool, mirror := 1.0) -> Vector3:
	## The body's tool swing. The PICKAXE still hoists overhead and drives down
	## — that is what a pick is. The AXE cleave is a SIDE swing: the arm coils
	## out to one flank at about chest height and whips FLAT across the front,
	## `mirror` picking the flank so the body matches the viewmodel exactly.
	##
	## Note the drive end is POSITIVE on x: negative there points the fist
	## behind the body, which is what made the third-person chop read as a
	## backward swing too. Across and away from the camera, always.
	##
	## HORIZONTAL (Lemon 2026-09-01). The cleave used to run x -1.35 -> +0.35,
	## which is a fist hoisted above the shoulder and dropped — a felling chop.
	## It now stays near the height it started at (-0.15 -> +0.65, the same band
	## the sword's flat cut lives in) and the travel has moved into z, which is
	## the lateral one: 1.25 out to the flank, 1.10 across to the other side.
	var x: float
	var z := 0.0
	if p < windup:
		var w := p / maxf(windup, 0.001)
		w = w * w  ## heavy iron is slow to start moving
		x = lerpf(-0.35, -2.15, w)
		if cleave:
			x = lerpf(-0.35, -0.15, w)          ## up to chest height, no higher...
			z = lerpf(0.0, 1.25 * mirror, w)    ## ...and coiled right out to that flank
	else:
		var w := (p - windup) / maxf(1.0 - windup, 0.001)
		var drive := 1.0 - pow(1.0 - clampf(w / 0.34, 0.0, 1.0), 3.0)
		var back := clampf((w - 0.42) / 0.58, 0.0, 1.0)
		back = back * back * (3.0 - 2.0 * back)
		x = lerpf(lerpf(-2.15, 0.80, drive), -0.35, back)
		if cleave:
			x = lerpf(lerpf(-0.15, 0.65, drive), -0.35, back)              ## stays level
			z = lerpf(lerpf(1.25 * mirror, -1.10 * mirror, drive), 0.0, back)  ## flat across the body
	return Vector3(x, 0.0, z)


func _update_tp_gear(_delta: float) -> void:
	## What the third-person body HOLDS this frame — the viewmodels' twins.
	## Sheathed states already read on the body in both modes (hip sword, back
	## shield), and the torch twin is driven from _update_offhand.
	if tp_hand_r == null:
		return
	var tp := cam_mode == "tp"
	if tp_sword:
		tp_sword.visible = tp and current_weapon == "sword" and sheath_t < 0.5
	if tp_pick:
		tp_pick.visible = tp and current_weapon == "pickaxe" and reach_phase == ""
	if tp_axe:
		tp_axe.visible = tp and current_weapon == "axe" and reach_phase == ""
	if tp_bow:
		tp_bow.visible = tp and current_weapon == "bow" and reach_phase == ""
		if tp_bow.visible and left_arm:
			tp_bow.rotation.x = -left_arm.rotation.x  ## stays upright as the arm points
	if tp_shield:
		tp_shield.visible = tp and (offhand_shown.contains("Shield") or offhand_shown2.contains("Shield"))
		if tp_shield.visible and left_arm:
			## Counter-tilt so the boards keep FACING the threat as the arm rises.
			tp_shield.rotation.x = -left_arm.rotation.x * 0.85


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
	## Each swing starts uncommitted; swinging while already dashing spends
	## that dash on the blade (the other half of _try_dash's bargain).
	committed = false
	if dash_timer > 0.0 and mount == null \
			and _enemy_ahead(attack_range + COMMIT_REACH + 1.4):
		_commit_swing()
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
	[  ## 1: flat forehand SLASH — coiled out to the RIGHT, whipped straight
	   ## across the frame to the LEFT. Lemon's rule: swings are side-to-side
	   ## slashes, never a stab — the forward pos punch stays small and the
	   ## yaw+roll travel is where the cut lives.
		[Vector3(-8.0, 74.0, 34.0), Vector3(0.16, 0.05, 0.08)],
		[Vector3(5.0, -10.0, -8.0), Vector3(-0.03, -0.02, -0.13)],
		[Vector3(16.0, -80.0, -34.0), Vector3(-0.18, -0.05, 0.0)],
	],
	[  ## 2: flat backhand out of 1's finish — carried LEFT, ripped back RIGHT
		[Vector3(-6.0, -76.0, -32.0), Vector3(-0.16, 0.04, 0.06)],
		[Vector3(5.0, 10.0, 8.0), Vector3(0.03, -0.02, -0.13)],
		[Vector3(14.0, 78.0, 32.0), Vector3(0.18, -0.05, 0.0)],
	],
	[  ## 3: the heavy finisher — a high forehand ripped DIAGONALLY down
	   ## across the body. Still a slash (side to side), just thrown wider
	   ## and with the shoulders behind it.
		[Vector3(-30.0, 82.0, 38.0), Vector3(0.18, 0.12, 0.10)],
		[Vector3(12.0, -14.0, -10.0), Vector3(-0.04, -0.05, -0.16)],
		[Vector3(30.0, -86.0, -36.0), Vector3(-0.20, -0.14, -0.02)],
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
		var u0 := p / 0.24
		u0 = 1.0 - (1.0 - u0) * (1.0 - u0)             ## ease OUT into the chamber
		return [Vector3.ZERO.lerp(cham_r, u0), Vector3.ZERO.lerp(cham_p, u0)]
	elif p < 0.52:
		var u1 := (p - 0.24) / 0.28
		u1 = u1 * u1                                    ## the whip — screaming at impact
		return [cham_r.lerp(imp_r, u1), cham_p.lerp(imp_p, u1)]
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
		var u0 := p / 0.52
		u0 = u0 * u0                                    ## accelerating out of the sheath
		return [start_r.lerp(imp_r, u0), start_p.lerp(imp_p, u0)]
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
			committed = false  ## the step is spent whether or not it found anything
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


## ==================== Impact effects: where a blow LANDS ==================
## Every hit in the game routes through here so it all speaks one language:
## find the actual point of contact, work out what you just hit, and throw
## the right thing out of it. See HitFX.gd for the effects themselves.


func _fx(node: Node3D) -> void:
	## Impact effects live in the WORLD, not on the player — they have to stay
	## where the blow landed while you walk away from it.
	if node == null:
		return
	get_parent().add_child(node)


func _fx_dir(normal := Vector3.INF) -> Vector3:
	## Which way the mess flies: back out along the swing, lifted a little so
	## it arcs instead of hugging the floor. A surface normal wins when we have
	## one — chips come off the face you struck.
	if normal != Vector3.INF and normal.length_squared() > 0.0001:
		return (normal.normalized() + Vector3.UP * 0.45).normalized()
	var f := -camera.global_transform.basis.z
	return (f + Vector3.UP * 0.35).normalized()


func _impact_on(e: Node3D, reach: float) -> Array:
	## The real point of contact, in this order of preference:
	##   1) whatever the crosshair ray actually struck on this creature
	##   2) a surface point on the line from your eye to its chest
	##   3) a guess just off its chest, facing you
	## Returns [point, normal].
	var from := _aim_origin()
	var space := get_world_3d().direct_space_state
	var aim := -camera.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + aim * (reach + 0.8))
	q.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	if not hit.is_empty() and CreatureSkin.owner_of(hit.collider) == e:
		return [hit.position, hit.normal]
	var chest: Vector3 = e.global_position + Vector3.UP * 0.9
	var q2 := PhysicsRayQueryParameters3D.create(from, chest)
	q2.exclude = [get_rid()]
	var hit2: Dictionary = space.intersect_ray(q2)
	if not hit2.is_empty() and CreatureSkin.owner_of(hit2.collider) == e:
		return [hit2.position, hit2.normal]
	var out := from - chest
	out.y *= 0.3
	if out.length_squared() < 0.0001:
		out = -aim
	out = out.normalized()
	return [chest + out * 0.35, out]


func _creature_impact(e: Node3D, reach: float, mat_id := "", power := 1.0) -> void:
	## One landed blow, dressed. `mat_id` is the metal that did it — pass the
	## blade's material and its own weather lands in the wound too (fire metals
	## throw embers, voidsteel leaks); pass "" or plain iron and nothing extra
	## happens, which is exactly right for an honest axe.
	var pn := _impact_on(e, reach)
	var at: Vector3 = pn[0]
	var dir := _fx_dir(pn[1])
	_fx(HitFX.for_creature(HitFX.kind_of(e), at, dir, power))
	if mat_id != "":
		_fx(HitFX.element(at, dir, Materials.blade_fx(mat_id), power))


func _self_impact(from_pos: Vector3, dmg: float) -> void:
	## The other half of "every hit does something": blows landing on YOU.
	## Sits out toward the attacker so it reads in first person too, instead
	## of erupting somewhere behind your own eyes.
	var toward := Vector3.ZERO
	if from_pos != Vector3.INF:
		toward = from_pos - global_position
		toward.y = 0.0
	if toward.length_squared() < 0.0001:
		toward = -camera.global_transform.basis.z
		toward.y = 0.0
	toward = toward.normalized()
	var at := global_position + Vector3.UP * 1.15 + toward * 0.42
	var dir := (-toward + Vector3.UP * 0.5).normalized()
	if dmg <= 0.01:
		## Turned completely: shield or plate ate it. Pure steel-on-steel.
		_fx(HitFX.armour(at, dir, 1.0))
		return
	## Worn metal still takes its cut of every blow — you get both, sparks off
	## the plate and blood through the gap in it.
	if _armor_mult() < 0.999:
		_fx(HitFX.armour(at, dir, 0.7))
		_fx(HitFX.flesh(at, dir, 0.7))
	else:
		_fx(HitFX.flesh(at, dir, 1.0))


const WOOD_GROUPS := ["trees", "choppable", "fallen_trunks", "tree_stumps"]


func _nearest_wood(forward: Vector3, reach: float) -> Node3D:
	## The nearest standing tree, downed trunk or stump in the swing arc.
	## Everything you can put an edge into answers to one of four groups —
	## v2 trees, the old ChopTree, bucked trunks, leftover stumps.
	var best: Node3D = null
	var best_d := reach + 1.0
	var seen := {}
	for g: String in WOOD_GROUPS:
		for t in get_tree().get_nodes_in_group(g):
			if not (t is Node3D) or seen.has(t):
				continue
			seen[t] = true
			var to_t: Vector3 = (t as Node3D).global_position - global_position
			to_t.y = 0.0
			var d := to_t.length()
			if d > reach or d >= best_d:
				continue
			if forward.dot(to_t.normalized()) > 0.35:
				best = t as Node3D
				best_d = d
	return best


func _wood_strike_point(wood: Node3D, reach: float) -> Array:
	## WHERE the edge went in. The crosshair ray owns this — chips have to come
	## out of the spot you actually aimed at, not off the middle of the trunk.
	## Falls back to the chopper's-side notch height when the ray misses (the
	## trunk collider is often narrower than the bark you can see).
	var from := _aim_origin()
	var aim := -camera.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + aim * (reach + 1.0))
	q.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var col := hit.collider as Node
		if col != null and (col == wood or wood.is_ancestor_of(col)):
			return [hit.position, hit.normal]
	var toward := global_position - wood.global_position
	toward.y = 0.0
	if toward.length_squared() < 0.01:
		toward = Vector3(1, 0, 0)
	toward = toward.normalized()
	return [wood.global_position + toward * 0.35 + Vector3.UP * ChopTree.NOTCH_Y, toward]


func _wood_impact(wood: Node3D, mat_id := "", power := 1.0, tool := "") -> Array:
	## Chips out of the cut, tinted to the species, plus real tumbling
	## splinters you can watch land. Returns [point, normal] so the caller can
	## reuse the strike point it just paid a raycast for.
	## AND THE SOUND OF IT: every tool that meets wood comes through here, so
	## this is where the trunk answers -- with the tool's own voice (an axe
	## bites, a sword slaps, a pick thuds) pitched to the size of the wood.
	## See WoodAudio.gd. `tool` defaults to what is in your hand.
	var pn := _wood_strike_point(wood, AXE_RANGE + 0.6)
	var at: Vector3 = pn[0]
	var normal: Vector3 = pn[1]
	var dir := _fx_dir(normal)
	var species := ""
	if "species" in wood:
		species = String(wood.get("species"))
	_fx(HitFX.wood(at, dir, species, power))
	WoodAudio.strike(self, at, tool if tool != "" else current_weapon, power, wood)
	if mat_id != "":
		_fx(HitFX.element(at, dir, Materials.blade_fx(mat_id), power * 0.7))
	## The heavy chips are physics, not particles — they bounce and lie there.
	var parent := get_parent()
	for _i in range(int(round(randi_range(3, 5) * power))):
		var v := dir * randf_range(1.6, 3.0) \
			+ Vector3(randf_range(-0.8, 0.8), randf_range(0.6, 1.8), randf_range(-0.8, 0.8))
		parent.add_child(RockDebris.make(at + Vector3(0, randf_range(-0.12, 0.12), 0),
			v, false, true))
	return pn


func _sword_lop_branch(reach: float, mat_id := "") -> bool:
	## The first branch the sight-line runs through, on any tree in reach --
	## a standing TreeV2 limb (its own HP: one to three cuts, like the axe) or
	## anything on a downed trunk (one cut). Chips, the blade's own sound on
	## the wood, and sticks on the ground when it comes off.
	var from := _aim_origin()
	var dir := -camera.global_transform.basis.z
	var best_t := INF
	var best_owner: Node3D = null
	var best_hit: Variant = null
	var best_p := Vector3.INF
	var cull := (reach + 14.0) * (reach + 14.0)     ## a crown is wide; the trunk is not
	for g in ["trees", "fallen_trunks"]:
		for n in get_tree().get_nodes_in_group(g):
			var holder := n as Node3D
			if holder == null or not holder.has_method("branch_on_ray"):
				continue
			if holder.global_position.distance_squared_to(global_position) > cull:
				continue
			var r: Array = holder.call("branch_on_ray", from, dir, reach)
			if r.is_empty():
				continue
			var t: float = (r[1] as Vector3).distance_to(from)
			if t < best_t:
				best_t = t
				best_owner = holder
				best_hit = r[0]
				best_p = r[1]
	if best_owner == null:
		return false
	var species := ""
	if "species" in best_owner:
		species = String(best_owner.get("species"))
	_fx(HitFX.wood(best_p, _fx_dir(-dir), species, 0.6))
	if mat_id != "":
		_fx(HitFX.element(best_p, _fx_dir(-dir), Materials.blade_fx(mat_id), 0.5))
	WoodAudio.strike(self, best_p, "sword", 0.7, best_owner)
	var off := false
	if best_hit is TreeBranch:
		off = (best_hit as TreeBranch).take_hit(1)
	elif best_owner is FallenTrunk:
		off = (best_owner as FallenTrunk).lop_branch(best_hit as Dictionary, best_p) > 0
	if off:
		WoodAudio.limb(self, best_p)
		_add_log_msg("Limb down", Color(0.72, 0.76, 0.66))
	return true


func _do_melee_hit() -> void:
	var mat_id := _sword_material_id()
	var forward := -camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	_swat_bugs(forward, attack_range)  ## --- swat ---
	var combo_mult := 1.0
	if combo_index == 3 and not mounted_swing:
		combo_mult = 1.6  ## finisher hits harder
	## A COMMITTED STEP doubles the blow and buys reach — the whole body is
	## behind it, and it was paid for in stamina before you knew if it'd land.
	var reach := attack_range
	if committed:
		combo_mult *= COMMIT_DMG_MULT
		reach += COMMIT_REACH
	var landed := false
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node3D):
			continue
		if e == mount:
			continue  ## the horse under you can NEVER be hit by your own swings
		var to_e: Vector3 = e.global_position - global_position
		to_e.y = 0.0
		var dist := to_e.length()
		if dist <= reach and forward.dot(to_e.normalized()) > 0.35:
			if e.has_method("take_damage") and _swing_reaches(e):
				## Material matchup + situational element bonus vs this creature's
				## families (silver shreds the undead, steel merely dents them...)
				var fams: Array = e.families if "families" in e else []
				var mat_mult := Materials.matchup_mult(mat_id, fams) * Materials.element_mult(mat_id, fams)
				e.take_damage(base_damage * combo_mult * mat_mult)  ## base_damage carries STR
				landed = true
				## THE CUT SHOWS: blood off bare flesh, sparks off plate, bone
				## dust off the undead — plus whatever this steel does to the
				## air. A finisher or a committed step throws more of it.
				_creature_impact(e, reach, mat_id, 1.5 if combo_mult > 1.3 else 1.0)
				## FIRE METALS BURN: meteoric and dragonsteel leave the wound
				## alight — a DoT the creature ticks itself (Enemy.apply_burn).
				var brn: Dictionary = Materials.burn_for(mat_id)
				if not brn.is_empty() and e.has_method("apply_burn"):
					e.apply_burn(float(brn["dps"]), float(brn["dur"]))
				## The bestiary learns by DOING: landing this metal on this
				## creature proves the matchup and reveals it on the page.
				_bestiary_prove(e, mat_id)
				## (kills are counted in on_mob_slain, fed from Enemy._die)
	## THE SWORD MOWS: every swing shears through the HIDING grass ahead —
	## tall blades fall to cut stubble (and hide nobody anymore). Short grass
	## is beneath the blade's notice. Works from the saddle too: gallop past
	## a meadow swinging and leave a mown stripe.
	var gs := get_tree().get_first_node_in_group("grass_system")
	if gs != null and gs.has_method("cut_at"):
		gs.cut_at(global_position + forward * 1.35, 1.5)
	## A sword in a tree is a bad idea and it LOOKS like one: chips fly out of
	## the spot you struck, the trunk shivers, and not one bit of the felling
	## job gets done. Bring an axe (2). Elemental steel still marks the bark.
	## ...but a BRANCH in the way of the blade comes off (Lemon 2026-09-14:
	## "make the sword capable of breaking off branches as sticks to any
	## tree"). Point at a limb, standing or downed, and the swing takes the
	## limb rather than nicking the trunk.
	if not landed and _sword_lop_branch(attack_range + 1.2, mat_id):
		cam_punch = maxf(cam_punch, 0.8)
	elif not landed:
		var wood_hit := _nearest_wood(forward, attack_range + 0.4)
		if wood_hit != null:
			_wood_impact(wood_hit, mat_id, 0.6)
			cam_punch = maxf(cam_punch, 0.7)
			if wood_hit.has_method("shiver_from"):
				wood_hit.call("shiver_from", global_position)
			if axe_hint_cd <= 0.0:
				axe_hint_cd = 8.0
				_add_log_msg("The blade bites, but this is an axe's work (2)", Color(0.8, 0.8, 0.8))
	if landed:
		cam_punch = maxf(cam_punch, 1.4 if committed else 1.0)  ## the lens feels contact
	if landed and combo_index == 3:
		_record_progress("combo_master", 1)
	## The Committed Step pays out only when the gamble actually connects —
	## and when it connects while you're nearly out of blood, it pays twice.
	if committed:
		if landed:
			cam_shake = maxf(cam_shake, 0.22)
			_record_progress("committed_step", 1)
			if health <= max_health * COMMIT_LOW_HP:
				_record_progress("nothing_to_lose", 1)
				_add_log_msg("COMMITTED — nothing left to lose", Color(1.0, 0.55, 0.45))
			else:
				_add_log_msg("Committed strike!", Color(1.0, 0.86, 0.55))
		else:
			_add_log_msg("Committed to nothing", Color(0.8, 0.8, 0.8))
		committed = false
	if not landed and vein_hint_cd <= 0.0:
		## Swung at rock? Nudge toward the right tool (once in a while).
		for v in get_tree().get_nodes_in_group("ore_veins"):
			if (v as Node3D).global_position.distance_to(global_position) <= attack_range + 0.8:
				_add_log_msg("The blade skates off the ore — a pickaxe (3) would bite", Color(0.8, 0.8, 0.8))
				vein_hint_cd = 6.0
				break


## ===================== Pickaxe (weapon 3): mining =========================


## Digging pays like Minecraft: every bite of bare rock has a depth-scaled
## chance to knock an ore chunk loose, and the good metals live DEEP.
## Endgame steel (dragonsteel/voidsteel) is NEVER dug from the ground — that
## comes from the world above (drops, and one day dragons), per MATERIALS.md.
## Rows: [max_depth, chance per bite, [[metal, weight]...]] — first row wins.
## RARER NOW (was 6/10/12/15%): ore still turns up wherever you break stone —
## digging cave rock, cracking a surface boulder — but it's a FIND again, not
## a toll the world pays you for swinging. Veins are still the reliable source.
const DIG_ORE_TABLES := [
	[4.0, 0.022, [["bronze", 60.0], ["iron", 40.0]]],
	[12.0, 0.035, [["iron", 45.0], ["bronze", 20.0], ["steel", 20.0], ["silver", 15.0]]],
	[22.0, 0.045, [["iron", 20.0], ["steel", 25.0], ["silver", 25.0], ["cold_iron", 18.0], ["meteoric", 12.0]]],
	[999.0, 0.06, [["silver", 18.0], ["cold_iron", 20.0], ["meteoric", 25.0], ["mithril", 21.0], ["adamant", 16.0]]],
]
const BOULDER_ORE_CHANCE := 0.28  ## a broken surface boulder sometimes has
								  ## something in it — one roll per whole rock,
								  ## not per bite, so it reads as a find


func _roll_dig_ore(point: Vector3, normal: Vector3, guaranteed := false) -> void:
	var depth := -point.y
	for row: Array in DIG_ORE_TABLES:
		if depth <= float(row[0]):
			if guaranteed or randf() < float(row[1]):
				var id := _weighted_metal(row[2] as Array)
				## Manual pickup like everything else now — the chunk tumbles
				## out and LIES there until you look at it and press E.
				var ore := DroppedItem.make({"name": "%s Ore" % Materials.display_name(id),
					"weight": 2.0, "count": 1, "slot": "", "material": id})
				get_parent().add_child(ore)
				ore.global_position = point + normal * 0.35
				ore.velocity = normal * 2.0 \
					+ Vector3(randf_range(-0.6, 0.6), randf_range(1.6, 2.4), randf_range(-0.6, 0.6))
				_add_log_msg("The rock gives up %s ore!" % Materials.display_name(id), Color(0.85, 0.9, 1.0))
			return


func _weighted_metal(tbl: Array) -> String:
	var total := 0.0
	for e: Array in tbl:
		total += float(e[1])
	var pick := randf() * total
	for e: Array in tbl:
		pick -= float(e[1])
		if pick <= 0.0:
			return String(e[0])
	return String(tbl[0][0])


func _chop_boulder(b: Node3D, point: Vector3, normal: Vector3) -> void:
	## Surface boulders mine like anything else: chips fly with every bite,
	## and the last bite bursts the whole rock into rubble + gatherable
	## Rock pickups (look + E, like all loot).
	cam_shake = maxf(cam_shake, 0.10)
	var parent := get_parent()
	for _i in range(randi_range(2, 4)):
		var v := normal * randf_range(1.2, 2.4) \
			+ Vector3(randf_range(-0.9, 0.9), randf_range(0.5, 1.5), randf_range(-0.9, 0.9))
		parent.add_child(RockDebris.make(point + normal * 0.1, v))
	var bites := int(b.get_meta("bites", 3)) - 1
	b.set_meta("bites", bites)
	if bites > 0:
		return
	var s := float(b.get_meta("size", 1.2))
	var c: Vector3 = b.global_position + Vector3.UP * (s * 0.5)
	for _i in range(randi_range(3, 5)):
		parent.add_child(RockDebris.make(c,
			Vector3(randf_range(-2.0, 2.0), randf_range(1.5, 3.0), randf_range(-2.0, 2.0)), randf() < 0.3))
	for _i in range(2 + int(s)):
		var rock := DroppedItem.make({"name": "Rock", "weight": 0.8, "count": 1, "slot": ""})
		parent.add_child(rock)
		rock.global_position = c
		rock.velocity = Vector3(randf_range(-2.2, 2.2), randf_range(2.0, 3.4), randf_range(-2.2, 2.2))
	_add_log_msg("The boulder comes apart", Color(0.85, 0.9, 1.0))
	## Sometimes there was something IN it — surface rock reads the shallow
	## table, so a boulder is bronze and iron country, never the deep metals.
	if randf() < BOULDER_ORE_CHANCE:
		_roll_dig_ore(c, Vector3.UP, true)
	b.queue_free()


func _spawn_mine_debris(point: Vector3, normal: Vector3) -> void:
	## Rocks fall when you mine: chips burst from every bite plus one honest
	## CHUNK (the bigger bite radius shows its work), and biting a CEILING
	## (normal pointing down) shakes loose a hazard slab from overhead.
	var parent := get_parent()
	var n := randi_range(3, 5)
	for _i in range(n):
		var v := normal * randf_range(1.2, 2.6) \
			+ Vector3(randf_range(-1.0, 1.0), randf_range(0.4, 1.4), randf_range(-1.0, 1.0))
		parent.add_child(RockDebris.make(point + normal * 0.12, v))
	## The big chunk: harmless, heavy, thuds when it lands.
	parent.add_child(RockDebris.make(point + normal * 0.25,
		normal * randf_range(1.0, 1.8) + Vector3(randf_range(-0.6, 0.6), randf_range(0.8, 1.6), randf_range(-0.6, 0.6)),
		true))
	if normal.y < -0.35:
		parent.add_child(RockDebris.make(point + Vector3(0, -0.15, 0),
			Vector3(randf_range(-0.4, 0.4), -0.5, randf_range(-0.4, 0.4)), true, false, true))


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
	if pick_vm:
		pick_start_rot = pick_vm.rotation_degrees  ## melt out of the upright carry
		pick_start_pos = pick_vm.position


func _update_pickaxe(delta: float) -> void:
	if pick_vm == null:
		return
	pick_vm.visible = current_weapon == "pickaxe" and reach_phase == ""
	if vein_hint_cd > 0.0:
		vein_hint_cd -= delta
	if axe_hint_cd > 0.0:
		axe_hint_cd -= delta
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
		## Arcs live on the old forward base — melt from the upright carry into
		## them over the first fifth (the lowering IS the start of the chop).
		var tgt_rot := PICK_BASE_ROT + Vector3(ang, 0, 0)
		var tgt_pos := PICK_BASE_POS + Vector3(0, 0.10 * absf(ang) / 58.0 * signf(-ang), -0.06 * absf(ang) / 58.0)
		var blend := clampf(u / 0.22, 0.0, 1.0)
		blend = blend * blend * (3.0 - 2.0 * blend)
		pick_vm.rotation_degrees = pick_start_rot.lerp(tgt_rot, blend)
		pick_vm.position = pick_start_pos.lerp(tgt_pos, blend)
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


func _axe_entry_side() -> int:
	## WHICH SHOULDER THE CHOP COMES OFF — decided by the wood, not by a coin
	## flip. A feller doesn't alternate for the sake of it: the edge travels
	## IN from the flank of the trunk he's facing, so every bite arrives from
	## OUTSIDE the tree and opens the notch on the way through. Swinging the
	## other way makes the haft cross the trunk before the head does, which is
	## what reads as chopping backwards.
	##
	## Reads the same crosshair ray the strike point and the notch already
	## use, so first and third person agree by construction. Returns 0
	## (forehand — in from the RIGHT), 1 (backhand — in from the LEFT), or -1
	## for "no wood in the arc, or dead square on the middle": keep
	## alternating, which is what a fight wants.
	if camera == null:
		return -1
	var forward := -camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.000001:
		return -1
	forward = forward.normalized()
	var wood := _nearest_wood(forward, AXE_RANGE + 0.5)
	if wood == null:
		return -1
	var right := camera.global_transform.basis.x
	right.y = 0.0
	if right.length_squared() < 0.000001:
		return -1
	right = right.normalized()
	## Where the edge would go in, measured ACROSS the trunk's own centreline:
	## positive = you are looking at its right flank.
	var pn := _wood_strike_point(wood, AXE_RANGE + 0.6)
	var across: Vector3 = (pn[0] as Vector3) - wood.global_position
	across.y = 0.0
	var lateral := right.dot(across)
	if absf(lateral) < AXE_SIDE_DEADZONE:
		## Square on the middle of the trunk — or the ray missed a collider
		## narrower than the bark you can see. Fall back to where the TREE
		## sits in your view: one off to your left is one you are seeing the
		## right side of.
		var off: Vector3 = wood.global_position - _aim_origin()
		off.y = 0.0
		lateral = -right.dot(off)
		if absf(lateral) < 0.001:
			return -1
	return 0 if lateral > 0.0 else 1


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
	## THE WOOD PICKS THE SHOULDER. The edge comes in from the flank of the
	## trunk you are looking at, and keeps coming in from there swing after
	## swing, so the axe always travels from outside the tree INTO it. With
	## nothing to chop in the arc — a fight — it alternates as it always did:
	## forehand, backhand, forehand, backhand...
	var entry := _axe_entry_side()
	axe_side = entry if entry >= 0 else 1 - axe_side
	if axe_vm:
		axe_start_rot = axe_vm.rotation_degrees  ## melt out of the upright carry
		axe_start_pos = axe_vm.position


func _update_axe(delta: float) -> void:
	if axe_vm == null:
		return
	axe_vm.visible = current_weapon == "axe" and reach_phase == ""
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
		## Two authored SIDE strokes, alternating — a feller's swings, not an
		## executioner's. Forehand hauled over the RIGHT shoulder and swept
		## down across to the left; the backhand answers from the other side.
		## Three beats, the same curve the sword uses: chamber (ease back),
		## WHIP through the cut (damage lands here, dead centre of the arc),
		## then the weight carries past and settles.
		##
		## The head leads the hand through all of it — see AXE_KEYS. The axe
		## used to counter-rotate against its own sweep, which is what made it
		## look like it was swinging backwards.
		var pr := _pose_keys(AXE_KEYS[clampi(axe_side, 0, 1)], u)
		var arc_rot: Vector3 = AXE_BASE_ROT + (pr[0] as Vector3)
		var arc_pos: Vector3 = AXE_BASE_POS + (pr[1] as Vector3)
		## Melt out of wherever the upright carry left it, over the first fifth
		## — the raise is part of the swing, not a pop before it.
		var blend := clampf(u / 0.20, 0.0, 1.0)
		blend = blend * blend * (3.0 - 2.0 * blend)
		var rot := axe_start_rot.lerp(arc_rot, blend)
		var pos := axe_start_pos.lerp(arc_pos, blend)
		## ...and home again to the UPRIGHT carry over the last quarter, so the
		## recovery is a return rather than a snap.
		if u > 0.74:
			var settle := (u - 0.74) / 0.26
			settle = settle * settle * (3.0 - 2.0 * settle)
			rot = rot.lerp(AXE_REST_ROT, settle)
			pos = pos.lerp(AXE_REST_POS, settle)
		axe_vm.rotation_degrees = rot
		axe_vm.position = pos
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
				cam_punch = maxf(cam_punch, 1.2)
				## Heavy iron opens a body wide — a bigger mess than the sword
				## makes, and it strikes sparks off plate all the same. No metal
				## passed: the axe is honest iron and does nothing to the air.
				_creature_impact(e, AXE_RANGE, "", 1.4)
	## And it's the forester's tool: the nearest piece of timber in the arc
	## takes the same swing — standing tree, downed trunk to buck, or a stump
	## left to clear. Chips fly, the wood shivers, the last bite finishes it.
	_swat_bugs(forward, AXE_RANGE)  ## --- swat ---
	var best_tree := _nearest_wood(forward, AXE_RANGE + 0.5)
	if best_tree != null:
		_chop_tree(best_tree)


func _chop_tree(tree: Node3D) -> void:
	## One bite of the axe: chips burst from the exact spot the edge went in
	## and the tree itself does the rest. Nothing gets ADDED to a chopped tree
	## any more — ChopTree.chop_hit EATS a wedge out of the trunk on the struck
	## side, deeper every swing, and when the wedge runs past the centre the
	## trunk breaks on it and goes over. See ChopTree.gd.
	## Also the door for BUCKING a downed trunk and CLEARING a stump — both
	## answer the same chop_hit(), and _nearest_wood now actually finds them.
	cam_shake = maxf(cam_shake, 0.07)
	var toward := global_position - tree.global_position
	toward.y = 0.0
	if toward.length_squared() < 0.01:
		toward = Vector3(1, 0, 0)
	toward = toward.normalized()
	## Chips burst out of the spot the EDGE went in — the crosshair picks it,
	## so a high swing throws high and one at the roots throws low, and the
	## species tints them (birch pale, oak dark). See HitFX.wood().
	var pn := _wood_impact(tree)
	## Trees v2 and the old ChopTree both answer chop_hit(); v2 also wants to
	## know WHERE you were aiming, so it can pick the limb you were looking at
	## rather than an arbitrary one. See docs/TREES_v2_SPEC.md §8. That aim is
	## now the REAL strike point, so the limb that comes off is the one under
	## the crosshair rather than one 2.6 m down the sightline.
	var aim: Vector3 = pn[0]
	var t2 := tree as TreeV2
	if t2 != null:
		## Line a limb-swing up with the limb; a trunk swing keeps the normal arc.
		var limb := t2.nearest_branch(global_position, aim)
		axe_swing_axis = limb.dir() if limb != null else Vector3.ZERO
		if t2.chop_hit(toward, aim):
			_add_log_msg("Timber!", Color(0.85, 0.75, 0.5))
			return
		## Limbs no longer gate anything — the wedge in the trunk is the whole
		## job, and the growing notch IS the feedback. A limb only answers if
		## you aimed straight at one, and that's worth a word because it's a
		## choice, not a chore.
		if t2.last_result == "limb_off":
			_add_log_msg("Limb down", Color(0.72, 0.76, 0.66))
		return
	if tree.has_method("chop_hit") and not (tree is ChopTree):
		## fallen trunks (bucking) and stumps (clearing) answer the same call
		tree.call("chop_hit", toward, aim)
		return
	var ct := tree as ChopTree
	if ct == null:
		return
	if ct.chop_hit(toward):
		_add_log_msg("Timber!", Color(0.85, 0.75, 0.5))


func tree_crash_shake(at: Vector3) -> void:
	## A trunk hitting the ground is felt, not heard — ChopTree calls this the
	## instant the crown lands, and the shake falls off with distance.
	cam_shake = maxf(cam_shake, clampf(0.26 - global_position.distance_to(at) * 0.012, 0.05, 0.26))


func _do_pick_hit() -> void:
	_swat_bugs(_flat_forward(), 2.4)  ## --- swat ---
	combat_timer = 0.0
	var forward := -camera.global_transform.basis.z
	## Ore first: bite the nearest vein in front of you.
	var best: Node3D = null
	var best_d := PICK_RANGE + 1.0
	for v in get_tree().get_nodes_in_group("ore_veins"):
		if not (v is Node3D):
			continue
		var to_v: Vector3 = (v as Node3D).global_position + Vector3(0, 0.6, 0) - _aim_origin()
		var d := to_v.length()
		if d <= PICK_RANGE and forward.dot(to_v.normalized()) > 0.30 and d < best_d:
			best = v
			best_d = d
	## Crystals mine too, and they're closer to hand than a vein — a cluster
	## in the arc wins the swing (CrystalCluster.gd: shards come off one at a
	## time and the light in the room goes with them).
	for cnode in get_tree().get_nodes_in_group("crystals"):
		if not (cnode is Node3D):
			continue
		var to_c: Vector3 = (cnode as Node3D).global_position + Vector3(0, 0.5, 0) - _aim_origin()
		var dc := to_c.length()
		if dc <= PICK_RANGE and forward.dot(to_c.normalized()) > 0.30 and dc < best_d:
			best = cnode as Node3D
			best_d = dc
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
	var rq := PhysicsRayQueryParameters3D.create(_aim_origin(),
		_aim_origin() + forward * PICK_RANGE)
	rq.exclude = [get_rid()]
	var rhit := space.intersect_ray(rq)
	if not rhit.is_empty() and (rhit.collider as Node).is_in_group("cave_rock"):
		## Duck-typed: the real CaveRegion AND the cave-lab test massifs both
		## answer carve_bite — the pickaxe doesn't care whose rock it is.
		var region := (rhit.collider as Node).get_meta("cave_region") as Node
		if region != null and region.has_method("carve_bite") \
				and region.carve_bite((rhit.position as Vector3) + forward * 0.22):
			cam_shake = maxf(cam_shake, 0.12)
			_spawn_mine_debris(rhit.position as Vector3, rhit.normal as Vector3)
			_roll_dig_ore(rhit.position as Vector3, rhit.normal as Vector3)
			return
	if not rhit.is_empty() and (rhit.collider as Node).is_in_group("boulders"):
		_chop_boulder(rhit.collider as Node3D, rhit.position as Vector3, rhit.normal as Vector3)
		return
	## No rock — it's a poor weapon, but it IS a heavy spike of iron.
	var fwd_flat := forward
	fwd_flat.y = 0.0
	fwd_flat = fwd_flat.normalized()
	## Timber in the arc: the point goes in with a dull thud, a few chips
	## come out, and not one bit of the felling job gets done. Bring an axe.
	## (Every tool sounds like itself on a trunk -- WoodAudio.gd.)
	var wood_hit := _nearest_wood(fwd_flat, PICK_RANGE)
	if wood_hit != null:
		_wood_impact(wood_hit, "", 0.5, "pickaxe")
		cam_punch = maxf(cam_punch, 0.6)
		if wood_hit.has_method("shiver_from"):
			wood_hit.call("shiver_from", global_position)
		if axe_hint_cd <= 0.0:
			axe_hint_cd = 8.0
			_add_log_msg("The pick thuds in, but this is an axe's work (2)", Color(0.8, 0.8, 0.8))
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node3D):
			continue
		var to_e: Vector3 = e.global_position - global_position
		to_e.y = 0.0
		if to_e.length() <= PICK_RANGE * 0.8 and fwd_flat.dot(to_e.normalized()) > 0.45:
			if e.has_method("take_damage") and _swing_reaches(e):
				e.take_damage(base_damage * 0.5)  ## blunt, slow, no matchups
				_creature_impact(e, PICK_RANGE * 0.8, "", 0.8)
				break  ## a tool chops ONE thing, not an arc


## ========================= Bow (weapon 2) =================================


func _select_weapon(w: String) -> void:
	if current_weapon == w:
		return
	if mount != null and w != "sword":
		_add_log_msg("Not from the saddle — the sword or nothing", Color(0.8, 0.8, 0.8))
		return
	current_weapon = w
	_drop_carried_logs("you drew a weapon")
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
	a.global_position = _aim_origin() + fwd * 0.55 + camera.global_transform.basis.x * -0.08
	a.velocity = fwd * (26.0 + 14.0 * bow_draw)
	bow_release = 0.10
	bow_draw = 0.0
	combat_timer = 0.0


func _update_bow(delta: float) -> void:
	if bow_vm == null:
		return
	bow_vm.visible = current_weapon == "bow" and reach_phase == ""
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


func _give_item(item_name: String, n: int, weight := 0.06) -> bool:
	return _give_item_dict({"name": item_name, "weight": weight, "count": n, "slot": ""})


func _cam_side_name() -> String:
	if cam_shoulder > 0.5:
		return "third person, right shoulder"
	if cam_shoulder < -0.5:
		return "third person, left shoulder"
	return "third person, centred"


func _aim_origin() -> Vector3:
	## Where aim/interact measurements START. In first person this IS the
	## camera; in third person the camera hangs meters BEHIND the body, and
	## measuring reach from back there made close things read as out of range
	## (loot at your feet, the rock face, a vein). The body's eye keeps every
	## range honest in both modes — the crosshair direction stays the camera's.
	return head.global_position


func _swing_reaches(e: Node3D) -> bool:
	## Mirror of the enemies' ghost-hit guard: your blade doesn't cut through
	## cave walls or floors either. Other creatures don't block the swing.
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 1.3, e.global_position + Vector3.UP * 0.7)
	q.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return true
	var who := CreatureSkin.owner_of(hit.collider)
	return who == e or who is Enemy


## ===================== Climbing (Space near a ledge) =======================


func _try_climb(vault := false) -> bool:
	## THE MANTLE: find a wall ahead with a standable top within reach, then
	## haul up onto it. Returns false (so Space falls through to a jump) when
	## there's nothing to grab. Works grounded OR mid-air (grab as you fall).
	##
	## `vault` is the same search run automatically at a sprint (2026-09-14):
	## a tighter height window, a third of the duration, the RUN's direction
	## instead of the camera's, and an exit that is a stride rather than a stop.
	## One function, because a vault that read the world differently from a
	## mantle would find ledges the mantle refuses and vice versa.
	if climbing or mount != null or kd_phase != "" or hitstun_timer > 0.0:
		return false
	if stamina < (VAULT_STAMINA if vault else 1.0):
		return false  ## utterly winded — no grip left in the fingers
	var fwd := -camera.global_transform.basis.z
	if vault:
		## You hurdle where your FEET are going, not where you are looking.
		fwd = Vector3(velocity.x, 0.0, velocity.z)
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
	var lo := VAULT_MIN_H if vault else CLIMB_MIN_H
	var hi := VAULT_MAX_H if vault else CLIMB_MAX_H
	if rise < lo or rise > hi or (top.normal as Vector3).y < 0.5:
		return false  ## too low to bother / too high to reach / not standable
	## A vault that finds nothing must not re-probe every single frame of the
	## run — and one that finds something must not re-fire on the far side.
	if vault:
		_vault_cd = 0.25
	## 3b) Headroom on the lip — never mantle your skull into a ceiling.
	var land := (top.position as Vector3) + fwd * 0.22
	var qh := PhysicsRayQueryParameters3D.create(land + Vector3.UP * 0.25, land + Vector3.UP * 1.75)
	qh.exclude = [get_rid()]
	if not space.intersect_ray(qh).is_empty():
		return false

	## Grab it.
	stamina = maxf(0.0, stamina - (VAULT_STAMINA if vault else CLIMB_STAMINA) * stats.stamina_cost_mult())
	stamina_delay = STAMINA_DELAY
	climbing = true
	vaulting = vault
	_vault_exit = Vector2(velocity.x, velocity.z).length() * VAULT_KEEP if vault else 0.0
	climb_t = 0.0
	crouching = false  ## the grab stands you up — crouch/prone again at the top
	prone = false
	_fall_speed = 0.0  ## the grab kills the fall — no phantom fall damage on top-out
	climb_from = global_position
	climb_to = land + Vector3.UP * 0.02
	climb_dur = VAULT_TIME if vault else CLIMB_TIME + clampf((rise - 1.0) * 0.16, 0.0, 0.35)
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
			## A MANTLE puts you on the ledge; a VAULT puts you back into your run
			## with most of the speed you hit it carrying (VAULT_KEEP). Losing it
			## all is what makes a hurdle feel like a wall you climbed.
			velocity = push.normalized() * (maxf(_vault_exit, 1.6) if vaulting else 1.6)
		vaulting = false
		_vault_exit = 0.0


## ======================= The slide (C at a sprint) ========================


func _try_slide() -> bool:
	## Returns true when C was spent on a slide, so the crouch toggle below it
	## does not ALSO fire. Everything that could make going down a bad idea is
	## checked here rather than at the key, so the pad's O button gets the same
	## answer for free.
	if sliding or slide_cd > 0.0 or not is_on_floor() or prone or climbing:
		return false
	if kd_phase != "" or mount != null or swimming or input_locked or pressed_by != null:
		return false
	if reach_phase != "" or god:
		return false
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	if hv.length() < SLIDE_MIN_SPEED or stamina < SLIDE_STAMINA:
		return false
	sliding = true
	slide_t = SLIDE_TIME
	crouching = true                ## the eye drops through _update_camera_arm
	prone = false
	stamina = maxf(0.0, stamina - SLIDE_STAMINA * stats.stamina_cost_mult())
	stamina_delay = STAMINA_DELAY
	## The kick: you do not slow down as you go down, you speed up for a beat.
	var boosted := hv.normalized() * (hv.length() + SLIDE_BOOST)
	velocity.x = boosted.x
	velocity.z = boosted.z
	_drop_carried_logs("you slid")
	cam_shake = maxf(cam_shake, 0.06)
	StepAudio.landing(self, global_position, 4.0)   ## the scrape as you go down
	_add_log_msg("Slide", Color(0.8, 0.8, 0.8))
	return true


func _update_slide(delta: float, dir: Vector3) -> void:
	## Owns the horizontal velocity while it lasts. You keep a little steering
	## (SLIDE_STEER rad/s — enough to thread a gap, not enough to turn it into
	## a crouch-walk) and the ground takes the rest back at SLIDE_FRICTION.
	slide_t -= delta
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var spd := hv.length()
	if spd > 0.01 and dir != Vector3.ZERO:
		var ang := (hv / spd).signed_angle_to(dir, Vector3.UP)
		var step := clampf(ang, -SLIDE_STEER * delta, SLIDE_STEER * delta)
		hv = (hv / spd).rotated(Vector3.UP, step) * spd
	## A slide runs DOWNHILL longer and dies going up one — the same grade term
	## the walk reads, leaned on harder because there is nothing else pushing.
	var fr := SLIDE_FRICTION
	if is_on_floor():
		fr *= 2.0 - Locomotion.slope_mult(get_floor_normal(), hv.normalized())
	spd = maxf(0.0, spd - fr * delta)
	hv = hv.normalized() * spd
	velocity.x = hv.x
	velocity.z = hv.z
	if slide_t <= 0.0 or spd < SLIDE_END_SPEED or not is_on_floor() \
			or kd_phase != "" or swimming or pressed_by != null:
		_end_slide(false)


func _end_slide(keep_speed: bool) -> void:
	## You come up CROUCHED, because C is a toggle and you pressed it — standing
	## back up on its own would leave the stance disagreeing with the key. A
	## jump out of the slide (keep_speed) skips the friction tail entirely.
	if not sliding:
		return
	sliding = false
	slide_t = 0.0
	slide_cd = SLIDE_CD
	if not keep_speed:
		_stance_settle_pulse()


func _try_dash() -> void:
	if climbing:
		return  ## both hands are full of cliff
	## Mid-swing, Ctrl doesn't dodge — it COMMITS, driving the step into the
	## cut. But only when there is something in front of you to drive it INTO:
	## Ctrl with nothing ahead is still the dodge it always was, and a commit
	## you can't pay for falls back to one too. Never take the escape away.
	if attacking and not has_hit and not mounted_swing and current_weapon == "sword" \
			and _enemy_ahead(attack_range + COMMIT_REACH + 1.4) and _commit_swing():
		return
	var cost := DASH_STAMINA * stats.stamina_cost_mult()  ## DEX: cheaper dashes
	if dash_timer > 0.0 or stamina < cost:
		return
	dash_timer = DASH_TIME
	invuln_timer = 0.12
	stamina -= cost
	stamina_delay = STAMINA_DELAY


func _enemy_ahead(reach: float) -> bool:
	## Is there something in the swing's line worth committing to?
	var fwd := -camera.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.001:
		return false
	fwd = fwd.normalized()
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node3D) or e == mount:
			continue
		var to_e: Vector3 = (e as Node3D).global_position - global_position
		to_e.y = 0.0
		var d := to_e.length()
		if d <= reach and d > 0.01 and fwd.dot(to_e / d) > 0.35:
			return true
	return false


func _commit_swing() -> bool:
	## Put the dash through the blade. Expensive on purpose — this is the one
	## move in the loop you can't afford to throw out casually, and once your
	## feet have gone there is no pulling the strike back. Returns false when
	## it can't be paid for, so the caller can fall back to an honest dodge.
	if committed:
		return true
	var cost := COMMIT_STAMINA * stats.stamina_cost_mult()
	if stamina < cost:
		return false
	committed = true
	stamina -= cost
	stamina_delay = STAMINA_DELAY
	dash_timer = DASH_TIME
	invuln_timer = 0.10          ## the step itself carries a sliver of i-frames
	cam_shake = maxf(cam_shake, 0.09)
	combat_timer = 0.0
	return true


func take_damage(amount: float, from_pos := Vector3.INF, strong := false, lunge_throw := Vector3.INF, attacker: Node = null) -> void:
	if god:
		return  ## GOD MODE: nothing in the world gets to touch you.
	## THE MODE TAX. Peaceful softens every blow thrown by something ALIVE and
	## Hardcore leans on it — but damage with no attacker behind it (the ground
	## at the end of a fall, fire, a trunk landing on your back) is the world,
	## not a creature, and the world charges full price in all three modes.
	amount *= GameMode.creature_damage_mult(attacker)
	if invuln_timer > 0.0:
		## Untouchable: dashed clean through a special that would have landed.
		if strong and dash_timer > 0.0 and dodge_cd <= 0.0:
			dodge_cd = 0.5
			_add_log_msg("Dodged!", Color(0.55, 0.95, 1.0))
			_record_progress("untouchable", 1)
		return
	combat_timer = 0.0  ## taking a hit counts as combat (delays regen)

	## IN THE SADDLE THE HORSE IS THE GUARD: a blow that lands on the rider
	## costs the horse a HEART instead of your health — speed is your armor,
	## and the horse pays for the gaps in it. Three hearts gone and it has had
	## enough (Horse.rider_shielded_hit: it bucks you into the dirt and bolts,
	## alive — hearts grow back, and shielding you breaks no trust).
	if mount != null and not mount.dying:
		cam_shake = maxf(cam_shake, 0.18)
		mount.rider_shielded_hit()
		return

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

	## A blow that actually reaches you — even one your shield eats — throws
	## the load off your shoulder. You can carry logs or you can be fought.
	_drop_carried_logs("something hit you")

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
	## YOU bleed too. A blow that gets through throws blood off your own body,
	## back toward whoever swung; one your plate turns, or that a shield ate,
	## strikes sparks instead. Same rules the creatures play by.
	_self_impact(from_pos, dmg)
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
	## HARDCORE: you got one. The slot is sealed on the way past — Load will
	## refuse it in this session and every session after it, and Save has
	## nothing left to write. Settings -> New Run is the only door out, and it
	## starts you with what you woke up with. The body still respawns, because
	## a frozen corpse staring at a menu is not a death screen, it is a bug.
	if GameMode.is_hardcore() and not GameMode.run_lost:
		GameMode.run_lost = true
		SaveGame.seal("died at level %d" % level)
		_add_log_msg("HARDCORE — the run is over. That save is sealed.", Color(1.0, 0.28, 0.22))
	print("You died. Respawning...")
	if mount != null:
		_dismount()
	health = max_health
	stamina = max_stamina
	breath = 100.0                      ## [water] you come up
	thirst = maxf(thirst, 60.0)         ## [water] never respawn already dying of it
	cold.reset()                        ## [coldscreen] a new body is not still shaking
	exposure.on_respawn()               ## [exposure] nor already dying of cold
	swimming = false
	_set_water_tint(0.0)
	global_position = Vector3(0, 2, 0)
	climbing = false
	_fall_speed = 0.0
	## Respawn cancels everything in flight: no lingering knockback or queued hits.
	velocity = Vector3.ZERO
	hitstun_timer = 0.0
	block_broken_timer = 0.0
	cam_shake = 0.0
	## Death also stands you back up (the hard way) — and it must undo the
	## LYING-DOWN RIG too, not just the phase flag. Dying while knocked flat
	## skips the "rise" that would have done it, and the leftover -0.95 m
	## body_rig shift never heals: you respawn with your own body a metre out
	## in front of the camera.
	_stand_up_hard()
	near_death_active = false  ## dying is not "coming back from near death"
	invuln_timer = 2.0   ## brief grace so incoming damage right after respawn is ignored


func _update_hud(delta: float) -> void:
	## Dropped-item gaze check + the "[E] Pick up" prompt.
	_cut_cd = maxf(0.0, _cut_cd - delta)
	_update_drop_target()
	_update_water_target()
	if pickup_prompt:
		pickup_prompt.visible = _drop_target != null or _bed_target != null \
			or _debris_target != null or _log_target != null or _water_target != Vector3.INF
		pickup_prompt.visible = pickup_prompt.visible or _fire_target != null   ## [fire]
		pickup_prompt.visible = pickup_prompt.visible or not _carc_target.is_empty()  ## [butchery]
		if _drop_target != null:
			pickup_prompt.text = "[E] / [LMB]  Pick up %s" % _drop_target.display_name()
			var pile := _pile_count()
			if pile > 1:
				pickup_prompt.text += "   ·   hold [E]  take all %d" % pile
		elif _bed_target != null:
			pickup_prompt.text = "[E]  Pack up the bedroll   ·   [F]  Sleep"
		elif _debris_target != null:
			pickup_prompt.text = "[E] / [LMB]  Gather rock"
			var rpile := _pile_count()
			if rpile > 1:
				pickup_prompt.text += "   ·   hold [E]  take all %d" % rpile
		elif _log_target != null:
			pickup_prompt.text = "[E] / [LMB]  Take the log"
		elif _fire_target != null:
			if _fire_target.burning():
				pickup_prompt.text = "[E]  Feed the fire   ·   %s, %d min" \
					% [_fire_target.state_name(), int(_fire_target.minutes_left())]
			elif not _fire_target.can_light():
				pickup_prompt.text = "Too wild a wind to strike a light"
			else:
				pickup_prompt.text = "[E]  Light the fire"
		elif not _carc_target.is_empty():
			var chv: Dictionary = (CritterDex.get_profile(
				String(_carc_target.get("species", ""))) as Dictionary).get("harv", {})
			pickup_prompt.text = Butchery.prompt_for(_carc_target, chv, _edge_mat(),
				_total_weight(), stats.carry_limit())
		elif _water_target != Vector3.INF:
			if _water_is_sea:
				pickup_prompt.text = "Sea water -- brine"
			else:
				var skin := _has_waterskin()
				if skin >= 0 and _skin_fills(skin) < SKIN_FILLS:
					pickup_prompt.text = "[E]  Drink   ·   [F]  Fill waterskin"
				else:
					pickup_prompt.text = "[E]  Drink"

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
	if overload_label:
		overload_label.visible = _was_overweight and menu_open == ""
		if overload_label.visible:
			overload_label.text = "~ overburdened %.0f/%.0f — no sprint ~" % [_total_weight(), stats.carry_limit()]
			overload_label.position = Vector2((vp.x - overload_label.size.x) * 0.5, vp.y - 92.0)
	if log_label:
		## The shoulder counter is retired with the shoulder itself; logs show
		## up in the pack and their weight shows up in the overburdened line.
		log_label.visible = false
	if hidden_label:
		hidden_label.visible = grass_hidden and not sprinting and menu_open == ""
		if hidden_label.visible:
			hidden_label.position = Vector2((vp.x - hidden_label.size.x) * 0.5, vp.y * 0.66)

	## Mount hearts: while riding, the horse's three hearts sit just above
	## your bars. A hit flares them bright and full-size for a beat; between
	## scares they idle calm — and they breathe back in as hearts regrow.
	if mount_hearts:
		mount_hearts.visible = mount != null and not mount.dying
		if mount_hearts.visible:
			mount_heart_flash = maxf(0.0, mount_heart_flash - delta)
			var mh := maxi(mount.hearts, 0)
			mount_hearts.text = "♥".repeat(mh) + "♡".repeat(maxi(3 - mh, 0))
			var fl := clampf(mount_heart_flash / 0.5, 0.0, 1.0)
			mount_hearts.modulate = Color(1.0, 0.36 + 0.34 * fl, 0.42 + 0.30 * fl,
				(1.0 if mh < 3 else 0.55) + 0.45 * fl)
			mount_hearts.position = Vector2((vp.x - mount_hearts.size.x) * 0.5, vp.y - 96.0)

	## [water] Thirst sits above stamina (Survival only; Light hides it) and
	## breath above that, only while it is not full. Same fade rules.
	thirst_show = maxf(0.0, thirst_show - delta)
	breath_show = maxf(0.0, breath_show - delta)
	if thirst_bar:
		thirst_bar.visible = thirst_survival()
		thirst_bar.position = Vector2(cx, vp.y - 80.0)
		(thirst_bar.get_child(0) as ColorRect).size.x = bw
		thirst_fill.size.x = bw * clampf(thirst / THIRST_MAX, 0.0, 1.0)
		thirst_fill.color = Color(0.40, 0.66, 0.92) if thirst >= THIRST_LOW else Color(0.90, 0.62, 0.30)
		var t_target := 1.0 if (thirst < THIRST_LOW or thirst_show > 0.0) else 0.10
		thirst_bar.modulate.a = lerpf(thirst_bar.modulate.a, t_target, delta * 6.0)
	if warmth_bar:
		warmth_bar.visible = warmth_survival()
		warmth_bar.position = Vector2(cx, vp.y - 104.0)
		(warmth_bar.get_child(0) as ColorRect).size.x = bw
		warmth_fill.size.x = bw * clampf(exposure.warmth / Exposure.WARMTH_MAX, 0.0, 1.0)
		## amber while you are warm, and the colour of the weather when you are not
		warmth_fill.color = Color(0.92, 0.62, 0.34) if exposure.warmth >= Exposure.WARMTH_LOW else Color(0.55, 0.76, 1.0)
		var w_target := 1.0 if (exposure.warmth < Exposure.WARMTH_LOW or warmth_show > 0.0) else 0.10
		warmth_bar.modulate.a = lerpf(warmth_bar.modulate.a, w_target, delta * 6.0)
	if breath_bar:
		breath_bar.visible = breath < 99.9 or breath_show > 0.0
		breath_bar.position = Vector2(cx, vp.y - (92.0 if thirst_survival() else 80.0))
		(breath_bar.get_child(0) as ColorRect).size.x = bw
		breath_fill.size.x = bw * clampf(breath / 100.0, 0.0, 1.0)
		breath_fill.color = Color(0.75, 0.92, 1.0) if breath > 25.0 else Color(1.0, 0.45, 0.35)
		breath_bar.modulate.a = lerpf(breath_bar.modulate.a, 1.0 if breath < 99.9 else 0.0, delta * 6.0)

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
		elif menu_open == "creative":
			panel = creative_panel
		elif menu_open == "sky":
			panel = sky_panel
		elif menu_open == "map":
			panel = map_panel
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
	## EVERY MENU OVER GOD MODE (Lemon, 2026-09-12). While the editor is up a
	## menu is an OVERLAY, not a menu change: the editor stays visible and
	## spectating underneath, and closing the menu hands the cursor back to it.
	## Until now only the map did this (tools/patch_ground.py) and every other
	## menu dropped you out of the editor and back into your body.
	if which != "god" and godmode != null and godmode.visible:
		_menu_over_god(which, true)
		return
	## F1 with a menu over the editor: just drop the menu. Re-running
	## godmode.opened() here would snap the spectator camera back to the body.
	if which == "god" and godmode != null and godmode.visible and god_overlay() != "":
		_menu_over_god(god_overlay(), false)
		return
	menu_open = which
	drawing = false  ## opening a menu eases the bowstring back down
	bow_draw = 0.0
	_show_menu_panels(which)
	if godmode != null:
		if which == "god":
			godmode.opened()
		elif godmode.visible:
			godmode.closed()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _show_menu_panels(which: String) -> void:
	## THE PANEL TABLE, in one place. _toggle_menu and the god-mode overlay
	## both go through it, so a menu can never be wired into one of them and
	## forgotten in the other. "" or "god" means every panel down.
	spawn_panel.visible = which == "spawn"
	tab_panel.visible = which == "tab"
	settings_panel.visible = which == "settings"
	creative_panel.visible = which == "creative"
	if sky_panel:
		sky_panel.visible = which == "sky"
	if map_panel:
		map_panel.visible = which == "map"
	if grass_lab:
		grass_lab.visible = which == "grass"
	if creator:
		creator.visible = which == "creator"
	if claude_chat:
		claude_chat.visible = which == "claude"
	if which == "sky" and sky_panel:
		sky_panel.refresh()
	if which == "map" and map_panel:
		map_panel.opened()
	if which == "tab":
		_set_tab_page(tab_page)
	elif which == "settings":
		_refresh_settings_ui()


func god_overlay() -> String:
	## The menu currently sitting ON TOP of the god editor, or "" if there is
	## none (or the editor is not up). "god" itself is the editor, not an
	## overlay. This is the one test for "a menu is over the editor".
	if godmode == null or not godmode.visible:
		return ""
	if menu_open == "" or menu_open == "god":
		return ""
	return menu_open


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
	## A menu over the god editor is an OVERLAY: closing it goes back to the
	## editor, not out to the body. Esc twice is still the way out.
	var over := god_overlay()
	if over != "":
		_menu_over_god(over, false)
		return
	menu_open = ""
	if godmode != null and godmode.visible:
		godmode.closed()
	_show_menu_panels("")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _map_over_god(on: bool) -> void:
	## The map over the editor -- now just the general overlay with a name.
	## (tools/patch_ground.py -- map_over_god helper; kept as the entry point
	## GodEditor and the patcher already call.)
	_menu_over_god("map", on)


func _menu_over_god(which: String, on: bool) -> void:
	## Show / hide ANY menu on top of the god editor without touching the
	## editor: menu_open becomes that menu, its panel appears, the spectator
	## camera stays out and the body stays parked. Off goes back to "god".
	if godmode == null:
		return
	if on:
		menu_open = which
		drawing = false
		bow_draw = 0.0
		_show_menu_panels(which)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if godmode.has_method("overlay_opened"):
			godmode.overlay_opened(which)
	else:
		menu_open = "god"
		_show_menu_panels("god")    ## every panel down; the editor is not one
		if godmode.has_method("overlay_closed"):
			godmode.overlay_closed()
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func map_eye() -> Node3D:
	## The node the M map's arrow marks: the spectator camera while god mode
	## has you out of your body, the body otherwise. (tools/patch_ground.py)
	if godmode != null and godmode.has_method("spectating") and godmode.spectating() \
			and godmode.cam != null:
		return godmode.cam
	return self


## ========================= Creative menu (G, dev) ==========================


func _build_creative_menu() -> void:
	## CREATIVE (dev): EVERY item in the game, one click away — the full metal
	## catalogue (sword / 5-piece armor set / raw ore per metal, endgame
	## included) plus every mundane item. K spawns mobs; G fills pockets.
	creative_panel = PanelContainer.new()
	creative_panel.visible = false
	hud_layer.add_child(creative_panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	creative_panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	margin.add_child(vb)
	var title := Label.new()
	title.text = "Creative (dev) — every item in the game"
	title.add_theme_font_size_override("font_size", 22)
	vb.add_child(title)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 22)
	vb.add_child(hb)

	## Column 1: the metal catalogue.
	var mcol := VBoxContainer.new()
	mcol.add_theme_constant_override("separation", 3)
	hb.add_child(mcol)
	var mt := Label.new()
	mt.text = "Metals — sword / armor set / ore"
	mt.add_theme_font_size_override("font_size", 17)
	mcol.add_child(mt)
	for id: String in Materials.ORDER:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		mcol.add_child(row)
		var nm := Label.new()
		nm.text = Materials.display_name(id)
		nm.custom_minimum_size = Vector2(96, 0)
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
		var bo := Button.new()
		bo.text = "Ore"
		bo.focus_mode = Control.FOCUS_NONE
		bo.pressed.connect(_creative_give_ore.bind(id))
		row.add_child(bo)

	## Column 2: everything else that exists so far.
	var icol := VBoxContainer.new()
	icol.add_theme_constant_override("separation", 3)
	hb.add_child(icol)
	var it := Label.new()
	it.text = "Items"
	it.add_theme_font_size_override("font_size", 17)
	icol.add_child(it)
	for entry: Array in [
		["Wooden Shield", 1, 6.0], ["Torch", 1, 1.0], ["Iron Pickaxe", 1, 3.5],
		["Arrow", 20, 0.06], ["Bedroll", 1, 4.0], ["Wood", 5, 1.5],
		["Health Potion", 3, 0.5], ["Old Rucksack", 1, 2.0],
		["Boar Tusk", 1, 0.5], ["Old Bone", 1, 1.0],
	]:
		var b := Button.new()
		b.text = "%s ×%d" % [String(entry[0]), int(entry[1])]
		b.custom_minimum_size = Vector2(160, 0)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_creative_give_item.bind(String(entry[0]), int(entry[1]), float(entry[2])))
		icol.add_child(b)

	var hint := Label.new()
	hint.text = "G / Esc to close  —  K spawns mobs  —  full sets get a one-click Equip in the Inventory"
	hint.modulate = Color(1, 1, 1, 0.55)
	vb.add_child(hint)


func _creative_give_ore(id: String) -> void:
	var nm := "%s Ore" % Materials.display_name(id)
	_give_item(nm, 1, 2.0)
	_push_gain(nm, 1)


func _creative_give_item(nm: String, count: int, weight: float) -> void:
	if nm == "Old Rucksack":
		## The pack is EQUIPMENT (Back slot) — it must arrive wearing its
		## slot tag and its rows, or it could never be put on.
		if _give_item_dict({"name": nm, "weight": weight, "count": 1, "slot": "back", "rows": 3}):
			_push_gain(nm, 1)
		return
	_give_item(nm, count, weight)
	_push_gain(nm, count)


## ========================= Mob spawn menu (M) =============================


func _mob_types() -> Array:
	## The bestiary's canon: one row per creature (wild and saddled horses
	## share the "Horse" page — a horse is a horse).
	return [
		["Boar", Boar], ["Kobold", Kobold], ["Goblin", Goblin], ["Skeleton", Skeleton],
		["Orc", Orc], ["Ogre", Ogre], ["Dark Knight", DarkKnight], ["Horse", Horse],
	] + _slime_types()


func _spawn_types() -> Array:
	## The M menu offers both kinds of horse; the bestiary doesn't need to.
	return [
		["Villager", NPC],  ## a person (scripts/NPC.gd)
		## The hand-made humanoids (Kobold, Goblin, Skeleton, Orc, Ogre, Dark
		## Knight) no longer spawn (Lemon, 2026-09-14) -- the generator does.
		## Their scripts stay for the bestiary.
		["Monster (rolled for here)", Monster],
		["Boar", Boar],
		["Horse (wild)", Horse], ["Horse (saddled)", SaddledHorse],
	]


func _slime_types() -> Array:
	## The slimes, in Slime.ORDER (scripts/Slime.gd) — one class per colour
	## because the menu and the bestiary both spawn by `cls.new()`.
	return [
		["Green Slime", SlimeGreen], ["Blue Slime", SlimeBlue], ["Ember Slime", SlimeRed],
		["Jolt Slime", SlimeYellow], ["Venom Slime", SlimePurple], ["Tar Slime", SlimeBlack],
		["Rime Slime", SlimeWhite], ["Gilt Slime", SlimeGold], ["Leech Slime", SlimePink],
	]


func _build_spawn_menu() -> void:
	## --- wildlife menu ---
	## The roster outgrew a single column the day the wildlife landed: nine
	## mobs, sixty-five wild species and the legends is seventy-nine buttons,
	## about twice the height of the viewport. Everything below the title now
	## lives in a fixed-size scroller, three buttons to a row, under headings.
	spawn_panel = PanelContainer.new()
	spawn_panel.visible = false
	hud_layer.add_child(spawn_panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	spawn_panel.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	margin.add_child(outer)

	var title := Label.new()
	title.text = "Spawn (~10 ft ahead)"
	outer.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(SPAWN_MENU_W, SPAWN_MENU_H)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)

	_menu_head(vb, "MOBS")
	var mob_grid := _menu_grid(vb)
	for entry: Array in _spawn_types():
		_menu_btn(mob_grid, String(entry[0])).pressed.connect(_spawn_mob.bind(entry[1]))

	## The jellies (scripts/Slime.gd): nine colours, one row each.
	_menu_head(vb, "SLIMES")
	var slime_grid := _menu_grid(vb)
	for entry: Array in _slime_types():
		_menu_btn(slime_grid, String(entry[0])).pressed.connect(_spawn_mob.bind(entry[1]))

	## Wildlife, straight out of the dex.
	for group: Array in _critter_groups():
		_menu_head(vb, String(group[0]))
		var g := _menu_grid(vb)
		for row: Array in (group[1] as Array):
			_menu_btn(g, String(row[0])).pressed.connect(_spawn_critter.bind(String(row[1])))

	_menu_head(vb, "WORLD")
	var bc := _menu_btn(vb, "Tear open a CAVE (~30 m ahead)", 2)
	bc.pressed.connect(_spawn_cave)
	var bmet := _menu_btn(vb, "Call down a METEOR", 2)
	bmet.pressed.connect(_call_meteor)

	_menu_head(vb, "CAVE LAB — rival generators (~45 m ahead)")
	for entry: Array in [["New Cave 1 — Polished Worms", 1],
			["New Cave 2 — Halls & Passages", 2],
			["New Cave 3 — The Riverbed", 3],
			["New Cave 4 — The Cathedral", 4]]:
		_menu_btn(vb, String(entry[0]), 2).pressed.connect(_spawn_test_cave.bind(int(entry[1])))

	var hint := Label.new()
	hint.text = "K / Esc to close  •  scroll for wildlife"
	hint.modulate = Color(1, 1, 1, 0.55)
	outer.add_child(hint)


func _menu_head(parent: Node, text: String) -> void:
	parent.add_child(HSeparator.new())
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.modulate = Color(1, 1, 1, 0.7)
	parent.add_child(l)


func _menu_grid(parent: Node) -> GridContainer:
	var g := GridContainer.new()
	g.columns = SPAWN_MENU_COLS
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(g)
	return g


func _menu_btn(parent: Node, text: String, span := 1) -> Button:
	var b := Button.new()
	b.text = text
	## Long names ("Black-capped Chickadee") must not blow the grid out — clip
	## and put the full name in the tooltip instead of wrapping the row.
	b.clip_text = true
	b.tooltip_text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(SPAWN_BTN_W * span + (6.0 * (span - 1)), 0)
	b.add_theme_font_size_override("font_size", 13)
	parent.add_child(b)
	return b


func _critter_groups() -> Array:
	## --- wildlife menu ---
	## Every wild thing, read out of CritterDex — so a species added to the dex
	## turns up in this menu with no edit here. Grouped by body plan, because
	## that is how you think when you want to go and look at something.
	var buckets := {
		"BIG GAME": ["CERVID", "URSID"],
		"PREDATORS": ["CANID", "FELID", "MUSTELID"],
		"CRITTERS": ["CHUNK", "RODENT_S"],
		"BIRDS": ["BIRD_GROUND", "BIRD_RAPTOR", "BIRD_PERCH", "BIRD_WATER"],
		"WATER & COLD BLOOD": ["HERP", "FISH"],
		"SWARMS & BUGS": ["SWARM"],
	}
	var out: Array = []
	for g: String in ["BIG GAME", "PREDATORS", "CRITTERS", "BIRDS",
			"WATER & COLD BLOOD", "SWARMS & BUGS"]:
		var rows: Array = []
		for k: String in CritterDex.keys():
			if CritterDex.flag(k, "legend", false):
				continue
			if (buckets[g] as Array).has(CritterDex.rig_of(k)):
				rows.append([String(CritterDex.get_profile(k).get("nm", k)), k])
		rows.sort_custom(func(a, b): return String(a[0]) < String(b[0]))
		if not rows.is_empty():
			out.append([g, rows])
	## Legends last, and clearly separated — spawning one by hand is a
	## different act from spawning a squirrel.
	var legends: Array = []
	for k: String in CritterDex.legends():
		legends.append([String(CritterDex.get_profile(k).get("nm", k)), k])
	legends.sort_custom(func(a, b): return String(a[0]) < String(b[0]))
	if not legends.is_empty():
		out.append(["LEGENDS", legends])
	return out


func _spawn_spot_ahead(dist: float) -> Vector3:
	## Ground under a point `dist` in front of you. Shared by the mob and the
	## wildlife spawners so they can never disagree about where "ahead" is.
	var fwd := -transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var pos := global_position + fwd * dist
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 3.0, pos + Vector3.DOWN * 30.0)
	q.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	if hit:
		return (hit.position as Vector3) + Vector3.UP * 0.2
	pos.y = global_position.y + 0.5
	return pos


func _spawn_critter(key: String) -> void:
	## --- wildlife menu ---
	## Wildlife does NOT spawn confused. A disoriented goblin wandering in
	## circles is funny; a deer doing it just looks broken, and half the point
	## of spawning one is to watch it behave.
	var pos := _spawn_spot_ahead(3.0)
	var nm := String(CritterDex.get_profile(key).get("nm", key))
	var dir := get_tree().get_first_node_in_group("wildlife_director")

	if CritterDex.rig_of(key) == "SWARM":
		var sw := CritterSwarm.make(key, pos + Vector3.UP * 1.2)
		get_parent().add_child(sw)
		if dir != null and dir.has_method("adopt_swarm"):
			dir.call("adopt_swarm", sw)
		_add_log_msg("%s — a cloud of them" % nm, Color(0.72, 0.86, 0.70))
		return

	var c := Critter.make(key)
	get_parent().add_child(c)
	c.global_position = pos
	c.rotation.y = rotation.y + PI   ## facing you, so you see the front of it
	if dir != null and dir.has_method("adopt"):
		dir.call("adopt", c)
	var note := ""
	if CritterDex.flag(key, "legend", false):
		note = "  (legend)"
	elif CritterDex.flag(key, "water", false):
		note = "  (wants water)"
	elif CritterDex.flag(key, "glide", false):
		note = "  (flier)"
	_add_log_msg("%s%s" % [nm, note], Color(0.80, 0.90, 0.75))


func _spawn_test_cave(v: int) -> void:
	## CAVE LAB: raise a freestanding rock massif ~45 m ahead, carved by rival
	## generator v (TestCave.gd), walk-in entrance facing you. One lab at a
	## time — spawning the next one clears the last (and its crystals).
	## Free the old lab NOW (not end-of-frame): two multi-hundred-body
	## massifs must never coexist, even for one frame.
	for old in get_tree().get_nodes_in_group("test_cave"):
		(old as Node).free()
	var fwd := -camera.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.001:
		fwd = -transform.basis.z
	fwd = fwd.normalized()
	var spot := global_position + fwd * 45.0
	spot.x = clampf(spot.x, -68.0, 68.0)
	spot.z = clampf(spot.z, -68.0, 68.0)
	## Foot the massif on the actual ground under that spot.
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 30.0, spot + Vector3.DOWN * 30.0)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	var gy := float(hit.position.y) if not hit.is_empty() else 0.0
	var lab := TestCave.make(v, 20260 + v)
	get_parent().add_child(lab)
	## The node's min-corner is its origin; center it on the spot, sink the
	## footing, and turn the entrance (low local z) back toward you.
	lab.rotation.y = atan2(-(-fwd).x, -(-fwd).z)
	## Interior floors live at local y ~3.2 — sink the massif so they meet
	## the grade and the front door is a WALK, not a step up a cliff.
	lab.global_position = spot - lab.global_transform.basis * Vector3(
		TestCave.SX * TestCave.VOX * 0.5, 0.0, TestCave.SZ * TestCave.VOX * 0.5) \
		+ Vector3.UP * (gy - 3.0)
	var names := ["Polished Worms", "Halls & Passages", "The Riverbed", "The Cathedral"]
	_add_log_msg("Cave Lab %d: %s — walk in through the front" % [v, names[v - 1]],
		Color(0.8, 0.9, 1.0))
	_close_menu()


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


func _call_meteor() -> void:
	## Dev: yank a star out of the sky (lands away from you, as always).
	var w := get_tree().get_first_node_in_group("world")
	if w != null and w.has_method("drop_meteor"):
		w.call("drop_meteor")
		_add_log_msg("Something tears loose in the sky...", Color(1.0, 0.62, 0.28))


func _spawn_mob(mob_script: Variant) -> void:
	if mob_script == Monster:
		_spawn_generated_monster()
		return
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


func _spawn_generated_monster() -> void:
	## One of the species MonsterGen rolls for THIS zone at THIS level
	## (scripts/MonsterGen.gd) -- the same roll the MonsterDirector makes.
	var fwd := -transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var pos := global_position + fwd * 3.0
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 3.0, pos + Vector3.DOWN * 30.0)
	q.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	if hit:
		pos = hit.position + Vector3.UP * 0.2
	else:
		pos.y = global_position.y + 0.5
	var wseed := MonsterDirector.DEFAULT_SEED
	var w := get_parent()
	if w != null and w.has_method("monsters") and w.call("monsters") != null:
		wseed = int((w.call("monsters") as MonsterDirector).world_seed)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var g := MonsterGen.for_spot(wseed, global_position, level, rng)
	if g.is_empty():
		return
	var m := Monster.from(g)
	m.confused = true
	get_parent().add_child(m)
	m.global_position = pos
	_add_log_msg("%s -- %s" % [m.display_name, MonsterGen.describe(g)], Color(0.85, 0.80, 0.70))


## ========================= The Item Wheel (Q) ==============================
## Eight slots of muscle memory. The wheel is a RADIAL: hold Q in the world
## and the mouse stops steering your eyes and starts steering your reach —
## drag toward a slot, let go, and whatever rides there is used exactly as if
## you'd clicked it in the pack (swords wield, shield/torch take the arm,
## the bedroll unrolls, the potion goes down your throat). Missing items show
## dim — the wheel remembers what you WANT there even when the pack is empty.


func _build_wheel_ui() -> void:
	wheel_panel = Control.new()
	wheel_panel.visible = false
	wheel_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(wheel_panel)
	wheel_center = Label.new()
	wheel_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wheel_center.add_theme_font_size_override("font_size", 19)
	wheel_center.custom_minimum_size = Vector2(240, 30)
	wheel_panel.add_child(wheel_center)
	for i in range(WHEEL_SLOTS):
		var l := Label.new()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 16)
		l.custom_minimum_size = Vector2(150, 26)
		wheel_panel.add_child(l)
		wheel_slot_labels.append(l)


func _wheel_layout() -> void:
	## Ring the labels around _wheel_origin, slot 1 at the top, clockwise —
	## the same geometry the drag angle is read against. The world radial sits
	## at the middle of the screen; the inventory slot-picker is a SMALL ring
	## dropped wherever the cursor was when Q went down.
	var c := _wheel_origin
	wheel_center.add_theme_font_size_override("font_size", _wheel_center_font)
	wheel_center.custom_minimum_size = _wheel_center_box
	wheel_center.size = _wheel_center_box
	wheel_center.position = c - _wheel_center_box * 0.5
	for i in range(WHEEL_SLOTS):
		var ang := deg_to_rad(float(i) * 45.0 - 90.0)
		var at := c + Vector2(cos(ang), sin(ang)) * _wheel_radius
		var l := wheel_slot_labels[i]
		l.add_theme_font_size_override("font_size", _wheel_slot_font)
		l.custom_minimum_size = _wheel_slot_box
		l.size = _wheel_slot_box
		l.pivot_offset = _wheel_slot_box * 0.5  ## the 1.25x pick-pop grows from the middle
		l.scale = Vector2.ONE
		l.position = at - _wheel_slot_box * 0.5


func _wheel_refresh_labels() -> void:
	for i in range(WHEEL_SLOTS):
		var nm := wheel[i]
		var l := wheel_slot_labels[i]
		if nm == "":
			l.text = "%d ·" % (i + 1)
			l.modulate = Color(1, 1, 1, 0.30)
		else:
			l.text = "%d · %s" % [i + 1, nm]
			## Dim what you don't currently have (pack OR worn).
			l.modulate = Color(1, 1, 1, 0.95) \
				if (_find_item_index(nm) >= 0 or _is_equipped_name(nm)) else Color(1, 1, 1, 0.40)


func _wheel_show(world: bool) -> void:
	wheel_open = world
	wheel_place_open = not world
	_wheel_vec = Vector2.ZERO
	_wheel_sel = -1
	var vp := get_viewport().get_visible_rect().size
	if world:
		## Eyes are locked and the cursor is captured — the ring belongs dead
		## centre, big enough to read at a glance.
		_wheel_radius = WHEEL_R_WORLD
		_wheel_slot_box = Vector2(150, 26)
		_wheel_center_box = Vector2(240, 30)
		_wheel_slot_font = 16
		_wheel_center_font = 19
		_wheel_origin = vp * 0.5
	else:
		## The pack is open and you can SEE the cursor: a compact ring drops
		## right where the item is, so the wrist barely moves. Nudged back
		## inside the screen if Q went down near an edge.
		_wheel_radius = WHEEL_R_PLACE
		_wheel_slot_box = Vector2(104, 20)
		_wheel_center_box = Vector2(152, 22)
		_wheel_slot_font = 12
		_wheel_center_font = 13
		var m := Vector2(_wheel_radius + _wheel_slot_box.x * 0.5 + 6.0,
			_wheel_radius + _wheel_slot_box.y * 0.5 + 20.0)
		_wheel_origin = Vector2(
			clampf(_q_down_mouse.x, minf(m.x, vp.x * 0.5), maxf(vp.x - m.x, vp.x * 0.5)),
			clampf(_q_down_mouse.y, minf(m.y, vp.y * 0.5), maxf(vp.y - m.y, vp.y * 0.5)))
	_wheel_layout()
	_wheel_refresh_labels()
	wheel_center.text = "Item Wheel" if world else "Choose its slot"
	wheel_center.modulate = Color(1, 1, 1, 0.6)
	wheel_panel.visible = true


func _wheel_highlight_from(v: Vector2, dead: float) -> void:
	## Angle -> sector, slot 0 at the top, clockwise. Inside the dead zone
	## nothing is chosen (a tap selects nothing — closing the wheel is free).
	if v.length() < dead:
		_wheel_sel = -1
	else:
		var ang := fposmod(rad_to_deg(atan2(v.x, -v.y)) + 22.5, 360.0)
		_wheel_sel = int(ang / 45.0) % WHEEL_SLOTS
	for i in range(WHEEL_SLOTS):
		var chosen := i == _wheel_sel
		wheel_slot_labels[i].scale = Vector2.ONE * (1.25 if chosen else 1.0)
		if chosen:
			wheel_slot_labels[i].modulate = Color(1.0, 0.9, 0.55, 1.0)
	if _wheel_sel >= 0:
		wheel_center.text = wheel[_wheel_sel] if wheel[_wheel_sel] != "" else "—"
	_wheel_refresh_dim()


func _wheel_refresh_dim() -> void:
	for i in range(WHEEL_SLOTS):
		if i == _wheel_sel:
			continue
		var nm := wheel[i]
		if nm == "":
			wheel_slot_labels[i].modulate = Color(1, 1, 1, 0.30)
		else:
			wheel_slot_labels[i].modulate = Color(1, 1, 1, 0.95) \
				if (_find_item_index(nm) >= 0 or _is_equipped_name(nm)) else Color(1, 1, 1, 0.40)


func _wheel_close(apply: bool) -> void:
	wheel_panel.visible = false
	wheel_open = false
	wheel_place_open = false
	if apply and _wheel_sel >= 0:
		_wheel_use(_wheel_sel)
	_wheel_sel = -1


func _wheel_use(slot: int) -> void:
	var nm := wheel[slot]
	if nm == "":
		return
	## Already WORN? The wheel toggles it back off (except the sword — the
	## main hand is never empty).
	for s2 in SLOT_ORDER:
		if _slot_name(s2) == nm:
			if s2 == "sword":
				_add_log_msg("Already in your fist", Color(0.8, 0.8, 0.8))
			else:
				_unequip_slot(s2)
				_apply_armor_visuals()
			return
	var idx := _find_item_index(nm)
	if idx < 0:
		_add_log_msg("No %s in the pack" % nm, Color(0.9, 0.75, 0.4))
		return
	if nm == "Health Potion":
		_drink_potion(idx)
		return
	if nm == "Waterskin":
		_drink_skin(idx)   ## [water]
		return
	_item_clicked(idx)  ## exactly a pack click: wield / arm / unroll


func _wheel_quick_add(idx: int) -> void:
	if idx < 0 or idx >= inventory.size():
		return
	var nm := String(inventory[idx].name)
	for i in range(WHEEL_SLOTS):
		if wheel[i] == nm:
			_add_log_msg("%s already rides the wheel (hold Q to move it)" % nm, Color(0.8, 0.8, 0.8))
			return
	for i in range(WHEEL_SLOTS):
		if wheel[i] == "":
			wheel[i] = nm
			_add_log_msg("On the wheel: %s (slot %d)" % [nm, i + 1], Color(0.85, 0.9, 1.0))
			return
	_add_log_msg("The wheel is full — hold Q over an item to choose its slot", Color(0.9, 0.75, 0.4))


func _wheel_assign_slot(nm: String, slot: int) -> void:
	## Deliberate placement: the item takes THIS slot (evicting whatever had
	## it) and leaves any old berth — one item, one seat.
	if slot < 0 or slot >= WHEEL_SLOTS or nm == "":
		return
	for i in range(WHEEL_SLOTS):
		if wheel[i] == nm:
			wheel[i] = ""
	wheel[slot] = nm
	_add_log_msg("On the wheel: %s (slot %d)" % [nm, slot + 1], Color(0.85, 0.9, 1.0))


func _wheel_place_finish() -> void:
	var nm := ""
	if _q_inv_idx >= 0 and _q_inv_idx < inventory.size():
		nm = String(inventory[_q_inv_idx].name)
	if _wheel_sel >= 0 and nm != "":
		_wheel_assign_slot(nm, _wheel_sel)
	_wheel_close(false)


func _update_wheel_hold(_delta: float) -> void:
	## The inventory HOLD: Q kept down over an item grows into the slot
	## picker; while it's up, the visible mouse steers the highlight.
	if _q_held and _q_inv_idx >= 0 and not wheel_place_open \
			and Time.get_ticks_msec() - _q_down_ms >= 350:
		_wheel_show(false)
	if wheel_place_open:
		## Measured from the ring's OWN centre (the point Q went down on), with
		## a dead zone that shrinks with the ring so a small wheel still has a
		## generous "chose nothing" middle.
		var v := get_viewport().get_mouse_position() - _wheel_origin
		_wheel_highlight_from(v, maxf(16.0, _wheel_radius * 0.26))


func _drink_potion(idx: int) -> void:
	## The red draught: 40 health back, one gulp, gone. Refused at full
	## health — it's too dear to waste on a whole body.
	if health >= max_health:
		_add_log_msg("Already whole — save the draught", Color(0.8, 0.8, 0.8))
		return
	_drop_carried_logs("you reached for a potion")
	health = minf(max_health, health + POTION_HEAL)
	health_show = 1.8
	cam_punch = maxf(cam_punch, 0.5)  ## the grimace-and-gulp
	var it := inventory[idx]
	it.count = int(it.count) - 1
	if int(it.count) <= 0:
		_remove_inventory_index(idx)
	_add_log_msg("The red draught burns going down — +%d health" % int(POTION_HEAL), Color(1.0, 0.5, 0.5))
	_refresh_inventory_ui()


func _find_item_index(item_name: String) -> int:
	for i in range(inventory.size()):
		if String(inventory[i].get("name", "")) == item_name:
			return i
	return -1


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

	## THE WORLD'S TEMPERAMENT — first row, because it changes what the game IS.
	_settings_option_row(vb, "World", "gamemode",
		[["Peaceful", 0], ["Normal", 1], ["Hardcore", 2]])
	gamemode_note = Label.new()
	gamemode_note.text = MODE_NOTES[clampi(set_gamemode, 0, 2)]
	gamemode_note.add_theme_font_size_override("font_size", 13)
	gamemode_note.modulate = Color(1, 1, 1, 0.55)
	vb.add_child(gamemode_note)
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
	_settings_option_row(vb, "Water Refraction", "refract",
		[["Off", false], ["On", true]])
	var wr_note := Label.new()
	wr_note.text = "The lake bed seen through the ripples. One screen read per frame of water;\nOff keeps the depth, foam and sky and blends the water the plain way."
	wr_note.add_theme_font_size_override("font_size", 13)
	wr_note.modulate = Color(1, 1, 1, 0.55)
	vb.add_child(wr_note)
	_settings_option_row(vb, "Thirst", "thirst",
		[["Survival", 0], ["Light", 1]])
	var th_note := Label.new()
	th_note.text = "Survival: a thirst meter, a day and a half to empty; low and your wind goes,\nempty and your body fails. Light: no meter -- a drink is a stamina top-up.\nSwitches live, any time."
	th_note.add_theme_font_size_override("font_size", 13)
	th_note.modulate = Color(1, 1, 1, 0.55)
	vb.add_child(th_note)
	_settings_option_row(vb, "Warmth", "warmth",
		[["Survival", 0], ["Light", 1]])
	var wa_note := Label.new()
	wa_note.text = "Survival: the cold is real -- an autumn night is a slow problem and a\nwinter one is not, being soaked doubles it, and a roof, a torch and a lit fire\nare the three answers. Light: no meter, and no cold. Switches live, any time."
	wa_note.add_theme_font_size_override("font_size", 13)
	wa_note.modulate = Color(1, 1, 1, 0.55)
	vb.add_child(wa_note)
	_settings_option_row(vb, "Draw Distance", "draw",
		[["Low", 45.0], ["Medium", 90.0], ["High", 130.0], ["Ultra", 180.0]])
	var draw_note := Label.new()
	draw_note.text = "How far the meadow reaches. Grass streams across the whole map now, so\nthis is the single biggest thing you own: the ring's area goes as the SQUARE of\nit, and Low draws roughly a quarter of what Medium does. Past the fade line the\nmeadow thins on its own, which is what makes the far settings affordable."
	draw_note.add_theme_font_size_override("font_size", 13)
	draw_note.modulate = Color(1, 1, 1, 0.55)
	vb.add_child(draw_note)
	_settings_option_row(vb, "Display", "fullscreen",
		[["Windowed", false], ["Fullscreen", true]])
	_settings_option_row(vb, "VSync", "vsync",
		[["Off", false], ["On", true]])
	_settings_option_row(vb, "Clouds", "clouds",
		[["Off", 0], ["Painterly", 1], ["Volumetric", 2]])
	var cloud_note := Label.new()
	cloud_note.text = "Painterly is two scrolling layers with lit edges - near free, and it\ncatches the sunset. Volumetric marches real depth through the deck: puffier,\nand it costs GPU. Off leaves a clean sky."
	cloud_note.add_theme_font_size_override("font_size", 13)
	cloud_note.modulate = Color(1, 1, 1, 0.55)
	vb.add_child(cloud_note)
	## THE DEV TOOLKIT (Lemon, 2026-09-14): the character creator is a full
	## screen of its own, and it carries this whole menu inside it as a tab.
	vb.add_child(HSeparator.new())
	var tk_row := HBoxContainer.new()
	tk_row.add_theme_constant_override("separation", 8)
	vb.add_child(tk_row)
	var tk_lbl := Label.new()
	tk_lbl.text = "Dev Toolkit"
	tk_lbl.custom_minimum_size = Vector2(190, 0)
	tk_lbl.add_theme_font_size_override("font_size", 17)
	tk_row.add_child(tk_lbl)
	var tk_btn := Button.new()
	tk_btn.text = "Character Creator"
	tk_btn.focus_mode = Control.FOCUS_NONE
	tk_btn.custom_minimum_size = Vector2(160, 0)
	tk_btn.pressed.connect(func() -> void: _toggle_menu("creator"))
	tk_row.add_child(tk_btn)
	var tk_note := Label.new()
	tk_note.text = "People and monsters: click any character in the world to select it (white outline),\nedit its body, face, clothes and mind live; roll, spawn and save generated species."
	tk_note.add_theme_font_size_override("font_size", 13)
	tk_note.modulate = Color(1, 1, 1, 0.55)
	vb.add_child(tk_note)
	vb.add_child(HSeparator.new())
	_settings_step_row(vb, "Mouse Sensitivity", "sens")
	_settings_step_row(vb, "Field of View", "fov")

	_settings_option_row(vb, "The Hunch", "hunch",
		[["Off", false], ["On", true]])
	var hunch_note := Label.new()
	hunch_note.text = "Steel answers intent: the moment something turns hostile, sword and shield\nclear the scabbard on their own — after 6.7 quiet seconds they ride home again."
	hunch_note.add_theme_font_size_override("font_size", 13)
	hunch_note.modulate = Color(1, 1, 1, 0.55)
	vb.add_child(hunch_note)

	_settings_option_row(vb, "Main Hand", "hand",
		[["Right", false], ["Left", true]])
	var hand_note := Label.new()
	hand_note.text = "Southpaw: the whole kit mirrors — sword to the left fist, shield to the\nright, every swing played back mirrored. The world is even-handed about it."
	hand_note.add_theme_font_size_override("font_size", 13)
	hand_note.modulate = Color(1, 1, 1, 0.55)
	vb.add_child(hand_note)

	_settings_option_row(vb, "Fall Damage", "falldmg",
		[["Off", false], ["On", true]])
	var fall_note := Label.new()
	fall_note.text = "Off: the ground cannot hurt you and a hard landing never knocks you down.\nOn: over 11 m/s at touchdown costs health, and over 17.5 m/s puts you flat.\nSwitches live, any time."
	fall_note.add_theme_font_size_override("font_size", 13)
	fall_note.modulate = Color(1, 1, 1, 0.55)
	vb.add_child(fall_note)

	_settings_option_row(vb, "Blood", "blood",
		[["Off", false], ["On", true]])
	var blood_note := Label.new()
	blood_note.text = "Off trades the red for a colourless puff of impact dust. Every hit still\nlands, sparks off armour and chips off timber exactly the same."
	blood_note.add_theme_font_size_override("font_size", 13)
	blood_note.modulate = Color(1, 1, 1, 0.55)
	vb.add_child(blood_note)

	## --- The one slot (SaveGame.gd). ---
	vb.add_child(HSeparator.new())
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	vb.add_child(srow)
	var snm := Label.new()
	snm.text = "Saved Game"
	snm.custom_minimum_size = Vector2(190, 0)
	snm.add_theme_font_size_override("font_size", 17)
	srow.add_child(snm)
	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.focus_mode = Control.FOCUS_NONE
	save_btn.custom_minimum_size = Vector2(96, 0)
	save_btn.pressed.connect(_on_save_pressed)
	srow.add_child(save_btn)
	var load_btn := Button.new()
	load_btn.text = "Load"
	load_btn.focus_mode = Control.FOCUS_NONE
	load_btn.custom_minimum_size = Vector2(96, 0)
	load_btn.pressed.connect(_on_load_pressed)
	srow.add_child(load_btn)
	## The only door out of a sealed Hardcore run — and a fresh start in any
	## other mode, for anyone who wants one.
	var new_btn := Button.new()
	new_btn.text = "New Run"
	new_btn.focus_mode = Control.FOCUS_NONE
	new_btn.custom_minimum_size = Vector2(96, 0)
	new_btn.pressed.connect(_on_new_run_pressed)
	srow.add_child(new_btn)
	save_status = Label.new()
	save_status.add_theme_font_size_override("font_size", 13)
	save_status.modulate = Color(1, 1, 1, 0.55)
	vb.add_child(save_status)
	var save_note := Label.new()
	save_note.text = "Keeps you, your pack, the hour, every tree and log and cutting —\nand a 30 m sphere of the rock you dug, if you save underground."
	save_note.add_theme_font_size_override("font_size", 13)
	save_note.modulate = Color(1, 1, 1, 0.55)
	vb.add_child(save_note)

	vb.add_child(HSeparator.new())
	var hint := Label.new()
	hint.text = "Esc to close — changes apply instantly and are remembered"
	hint.modulate = Color(1, 1, 1, 0.55)
	vb.add_child(hint)


func _on_save_pressed() -> void:
	if GameMode.run_lost:
		## Hardcore. Writing a fresh save over the grave would unpick the
		## death, so the slot stays shut until you deliberately start over.
		_add_log_msg("The run is over — there is nothing left to write.", Color(0.95, 0.7, 0.5))
		_refresh_save_status()
		return
	var err := SaveGame.save_game(self)
	if err == "":
		_add_log_msg("Saved", Color(0.75, 0.95, 0.75))
	else:
		_add_log_msg("Save failed: %s" % err, Color(0.95, 0.7, 0.5))
	_refresh_save_status(err, true)


func _on_load_pressed() -> void:
	var err := SaveGame.load_game(self)
	if err == "":
		_close_menu()   ## out of the menu and into the world you saved
		_add_log_msg("Loaded", Color(0.75, 0.95, 0.75))
	else:
		_add_log_msg("Load failed: %s" % err, Color(0.95, 0.7, 0.5))
	_refresh_save_status(err, false)


func _on_new_run_pressed() -> void:
	## Begin again. The seal is broken, the session's death is forgotten, and
	## you are handed back the snapshot taken at the end of _ready — the body,
	## the sheet, the pack and the blade you woke up with the very first time.
	## The WORLD is not reset: the forest you felled is still felled. This is
	## a new life in an old land, which is the honest version of starting over
	## in a world that has one save slot.
	SaveGame.unseal()
	GameMode.run_lost = false
	if not _newborn.is_empty():
		apply_state(_newborn)
	global_position = Vector3(0, 2, 0)
	velocity = Vector3.ZERO
	_refresh_derived(true)
	health = max_health
	stamina = max_stamina
	invuln_timer = 2.0
	_add_log_msg("A new run begins.", Color(0.75, 0.95, 0.75))
	_refresh_save_status()
	_close_menu()


func _refresh_save_status(err := "", was_save := false) -> void:
	if save_status == null:
		return
	if err != "":
		save_status.text = err
		return
	if SaveGame.is_sealed():
		save_status.text = "That run ended in Hardcore — the slot is sealed. New Run starts over."
		return
	var when := SaveGame.stamp()
	if when == "":
		save_status.text = "No saved game yet."
	else:
		save_status.text = ("Saved %s" if was_save else "Last save: %s") % when.replace("T", "  ")


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
		"hand": set_lefty = bool(value)
		"falldmg": set_fall_dmg = bool(value)
		"blood": set_blood = bool(value)
		"clouds": set_clouds = int(value)
		"draw": set_draw = float(value)
		"gamemode": set_gamemode = int(value)
		"refract": set_refract = bool(value)
		"thirst": set_thirst_mode = int(value)
		"warmth":
			set_warmth_mode = int(value)
			## Switching to Light TOPS the meter, so switching back can never
			## start you freezing. The thirst pass established that rule.
			if set_warmth_mode == 1:
				exposure.to_light()
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
				"hand": cur = set_lefty
				"falldmg": cur = set_fall_dmg
				"blood": cur = set_blood
				"clouds": cur = set_clouds
				"refract": cur = set_refract
				"thirst": cur = set_thirst_mode
				"warmth": cur = set_warmth_mode
				"draw": cur = set_draw
				"gamemode": cur = set_gamemode
			for pair: Array in (w["btns"] as Array):
				(pair[1] as Button).button_pressed = pair[0] == cur
		elif w.has("label"):
			var lbl := w["label"] as Label
			if id == "sens":
				lbl.text = "%.1f x" % set_sens
			elif id == "fov":
				lbl.text = "%d deg" % int(set_fov)
	if gamemode_note != null:
		gamemode_note.text = MODE_NOTES[clampi(set_gamemode, 0, 2)]
	_refresh_save_status()


func _apply_settings() -> void:
	## Everything lands live: lighting through the World, the rest right here.
	var w := get_tree().get_first_node_in_group("world")
	if w != null:
		if w.has_method("set_rt_lighting"):
			w.set_rt_lighting(set_rt)
		if w.has_method("set_shadow_quality"):
			w.set_shadow_quality(set_shadows)
		if w.has_method("set_cloud_mode"):
			w.set_cloud_mode(set_clouds)
	## Draw Distance goes straight to the grass system through its group, the
	## same way the sword finds it to mow with. Untyped `set()` would be wrong
	## here — set_draw_distance rescales the fade, the detail ring and every
	## live chunk's visibility range, so it has to be the METHOD, not the field.
	var gsys := get_tree().get_first_node_in_group("grass_system")
	if gsys != null and gsys.has_method("set_draw_distance"):
		gsys.call("set_draw_distance", set_draw)
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if set_fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if set_vsync else DisplayServer.VSYNC_DISABLED)
	if camera:
		camera.fov = set_fov
	## Southpaw: one scale flips the whole first-person kit AND the visible
	## body across the spine (scabbard to the right hip, load to the left
	## shoulder) — mirrored geometry means mirrored animation, for free.
	if hands_root:
		hands_root.scale = Vector3(-1.0 if set_lefty else 1.0, 1.0, 1.0)
	if body_rig:
		body_rig.scale = Vector3(-1.0 if set_lefty else 1.0, 1.0, 1.0)
	## Impact effects read this straight off the static — the very next hit
	## after you touch the switch already obeys it.
	HitFX.blood_enabled = set_blood
	## The world's temperament. set_mode also SETTLES the fight you are already
	## in — a bear mid-charge when you pick Peaceful stands down where it
	## stands, instead of the switch being a lie for the next ten seconds.
	GameMode.set_mode(set_gamemode, get_tree())
	## [water] the one screen read the lakes make
	if Overworld.inst != null and Overworld.inst.has_method("set_refraction"):
		Overworld.inst.set_refraction(set_refract)
	## [water] Light mode forgives: switching into it tops the meter so the
	## next switch back does not start you parched from a bar you never saw
	if set_thirst_mode == 1:
		thirst = THIRST_MAX


func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("gfx", "rt", set_rt)
	cf.set_value("gfx", "shadows", set_shadows)
	cf.set_value("gfx", "fullscreen", set_fullscreen)
	cf.set_value("gfx", "vsync", set_vsync)
	cf.set_value("gfx", "fov", set_fov)
	cf.set_value("gfx", "clouds", set_clouds)
	cf.set_value("gfx", "draw", set_draw)
	cf.set_value("input", "sens", set_sens)
	cf.set_value("game", "hunch", set_hunch)
	cf.set_value("game", "lefty", set_lefty)
	cf.set_value("game", "blood", set_blood)
	cf.set_value("game", "fall_dmg", set_fall_dmg)
	## Stored as the KEY, not the int, so the file stays readable and a future
	## reshuffle of the enum cannot silently move somebody into Hardcore.
	cf.set_value("game", "mode", GameMode.KEYS[clampi(set_gamemode, 0, 2)])
	cf.set_value("game", "cam_mode", cam_mode)
	cf.set_value("game", "cam_shoulder", cam_shoulder)
	cf.set_value("gfx", "refract", set_refract)
	cf.set_value("game", "thirst", "survival" if set_thirst_mode == 0 else "light")
	cf.set_value("game", "warmth", "survival" if set_warmth_mode == 0 else "light")
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
	set_clouds = clampi(int(cf.get_value("gfx", "clouds", 1)), 0, 2)
	## Clamped to GrassSystem's own DRAW_MIN/DRAW_MAX rather than to the four
	## preset buttons: a hand-edited settings.cfg is allowed to ask for 72 m,
	## and the four buttons simply none of them light up when it does.
	set_draw = clampf(float(cf.get_value("gfx", "draw", 90.0)), 30.0, 180.0)
	set_sens = clampf(float(cf.get_value("input", "sens", 1.0)), 0.3, 2.5)
	set_hunch = bool(cf.get_value("game", "hunch", true))
	set_lefty = bool(cf.get_value("game", "lefty", false))
	set_blood = bool(cf.get_value("game", "blood", true))
	set_fall_dmg = bool(cf.get_value("game", "fall_dmg", false))
	set_gamemode = GameMode.from_key(String(cf.get_value("game", "mode", "normal")))
	## First run starts first person; afterwards, your last camera wins.
	cam_mode = String(cf.get_value("game", "cam_mode", "fp"))
	if cam_mode == "tp":
		cam_snap = 1.0   ## booting straight into TP snaps the perch out too
	## 0.0 is a REAL setting now (the centred view), so it must not be snapped
	## back onto a shoulder the way it was when only +-1 existed.
	cam_shoulder = clampf(float(cf.get_value("game", "cam_shoulder", 1.0)), -1.0, 1.0)
	cam_shoulder = 0.0 if absf(cam_shoulder) < 0.5 else signf(cam_shoulder)
	set_refract = bool(cf.get_value("gfx", "refract", true))
	set_thirst_mode = 1 if String(cf.get_value("game", "thirst", "survival")) == "light" else 0
	set_warmth_mode = 1 if String(cf.get_value("game", "warmth", "survival")) == "light" else 0


## ========================= Inventory (I / Tab) ============================


func _init_inventory() -> void:
	## Placeholder gear so the slots and weight limit can be exercised now.
	## TODO(design): real item definitions (armor values, set bonuses?) come with step 4/5.
	## You are BORN DRESSED: the clothes start in their slots (Terraria
	## rules), the grid holds only what a wanderer would actually pack.
	inventory = [
		{"name": "Wooden Shield", "weight": 6.0, "count": 1, "slot": "offhand"},
		{"name": "Torch", "weight": 1.0, "count": 1, "slot": "offhand"},
		{"name": "Iron Pickaxe", "weight": 3.5, "count": 1, "slot": ""},
		{"name": "Arrow", "weight": 0.06, "count": 20, "slot": ""},
		{"name": "Health Potion", "weight": 0.5, "count": 2, "slot": ""},
		{"name": "Waterskin", "weight": 2.1, "count": 1, "slot": "", "fills": 3, "keep": true},
		{"name": "Boar Tusk", "weight": 0.5, "count": 3, "slot": ""},
		{"name": "Old Bone", "weight": 1.0, "count": 2, "slot": ""},
	]
	equipment = {}
	for slot in SLOT_ORDER:
		equipment[slot] = {}
	equipment["sword"] = {"name": "Iron Sword", "weight": Materials.sword_weight("iron"), "count": 1, "slot": "sword", "material": "iron"}
	equipment["helmet"] = {"name": "Rusty Helmet", "weight": 4.0, "count": 1, "slot": "helmet"}
	equipment["chest"] = {"name": "Leather Chestpiece", "weight": 8.0, "count": 1, "slot": "chest"}
	equipment["arms"] = {"name": "Iron Bracers", "weight": 5.0, "count": 1, "slot": "arms"}
	equipment["pants"] = {"name": "Cloth Pants", "weight": 2.0, "count": 1, "slot": "pants"}
	equipment["shoes"] = {"name": "Worn Boots", "weight": 3.0, "count": 1, "slot": "shoes"}
	## The Old Rucksack is WORN, on its own Back slot — and it IS the grid:
	## rows come from the pack on your back (rows 3 = 27 slots; bare back = 9).
	equipment["back"] = {"name": "Old Rucksack", "weight": 2.0, "count": 1, "slot": "back", "rows": 3}


## ---------------- Slots are containers (Terraria rules) -------------------


func _slot_item(slot: String) -> Dictionary:
	var v: Variant = equipment.get(slot)
	return v as Dictionary if v is Dictionary else {}


func _slot_name(slot: String) -> String:
	return String(_slot_item(slot).get("name", ""))


func _is_equipped_name(nm: String) -> bool:
	for s in SLOT_ORDER:
		if _slot_name(s) == nm:
			return true
	return false


func _equip_from_pack(idx: int, slot: String) -> bool:
	## Equipping MOVES: one unit leaves the grid stack and takes the slot;
	## whatever held the slot goes back to the pack (forced — a swap can
	## never vanish something you own).
	if idx < 0 or idx >= inventory.size():
		return false
	var it := inventory[idx]
	var want := String(it.get("slot", ""))
	if want != slot and not (slot == "offhand2" and want == "offhand"):
		return false
	var piece := it.duplicate(true)
	piece.count = 1
	it.count = int(it.count) - 1
	if int(it.count) <= 0:
		_remove_inventory_index(idx)
	var old: Dictionary = _slot_item(slot)
	equipment[slot] = piece
	if not old.is_empty():
		_give_item_dict(old, true)
	return true


func _unequip_slot(slot: String) -> bool:
	## Click a worn thing to take it OFF — back into the grid. Refused when
	## the grid genuinely has no room (nothing is ever dropped silently),
	## and the sword refuses always: the main hand is never empty.
	var old: Dictionary = _slot_item(slot)
	if old.is_empty():
		return false
	if slot == "sword":
		_add_log_msg("The main hand is never empty — equip another sword to swap", Color(0.9, 0.75, 0.4))
		return false
	## Clear the slot BEFORE offering the item back — the one-of-a-kind caps
	## (one back, one pack) must not mistake a thing for its own duplicate.
	equipment[slot] = {}
	if not _give_item_dict(old, false):
		equipment[slot] = old  ## no room — it stays worn ("Backpack full" logged)
		return false
	if slot == "offhand" and not _slot_item("offhand2").is_empty():
		equipment["offhand"] = equipment["offhand2"]
		equipment["offhand2"] = {}
	if menu_open == "tab" and tab_page == "inventory":
		_refresh_inventory_ui()
	return true


func _sword_material_id() -> String:
	## Material of the currently wielded sword (drives visuals + damage math).
	var e: Dictionary = _slot_item("sword")
	if not e.is_empty():
		return String(e.get("material", "iron"))
	return "iron"


func _apply_equipped_sword() -> void:
	## Rebuild the held blade to match the newly equipped sword's material.
	var mat_id := _sword_material_id()
	if sword_vm:
		sword_vm.queue_free()
	sword_vm = _make_sword(viewmodel, Vector3(0, 0.02, -0.04), mat_id)
	## The body-held twin wears the same steel (third person shows it).
	if tp_sword:
		var was_vis := tp_sword.visible
		tp_sword.queue_free()
		tp_sword = _make_sword(tp_hand_r, Vector3.ZERO, mat_id)
		tp_sword.visible = was_vis
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
	if String(_slot_item("sword").get("material", "")) == mat_id:
		return true
	for it in inventory:
		if String(it.get("slot", "")) == "sword" and String(it.get("material", "")) == mat_id:
			return true
	return false


## ==================== Armor sets (material plate) ==========================


func _backpack_capacity() -> int:
	## THE GRID IS WHAT'S ON YOUR BACK: the Back slot's item brings its own
	## rows (Old Rucksack: 3 = 27 slots; later packs can bring more). A bare
	## back is 9 — just what two hands and pockets can manage. Note WORN, not
	## owned: a rucksack sitting in the grid holds nothing.
	var rows := int(_slot_item("back").get("rows", 0))
	return PACK_COLS * maxi(rows, 1)


func _has_room(item_name: String) -> bool:
	## Room = an existing stack to merge into, or a free slot.
	for it in inventory:
		if String(it.name) == item_name:
			return true
	return inventory.size() < _backpack_capacity()


func _count_item(item_name: String) -> int:
	var n := 0
	for it in inventory:
		if String(it.name) == item_name:
			n += int(it.count)
	return n


func _give_item_dict(d: Dictionary, force := false) -> bool:
	## Generic give: merge into an existing stack by name, else new entry —
	## REFUSED when the backpack's slots are full (force = auto-forge etc.
	## may overflow; better a 28th stack than a vanished sword).
	## THE BEDROLL STACKS TO ONE: a bed is a home, not an inventory — the
	## rucksack has exactly one lashing spot for it and that spot is visible.
	if String(d.name) == "Bedroll" and _count_item("Bedroll") >= 1:
		_add_log_msg("One bed is all the rucksack will lash on", Color(0.9, 0.75, 0.4))
		return false
	if String(d.name) == "Old Rucksack" \
			and (_count_item("Old Rucksack") >= 1 or _slot_name("back") == "Old Rucksack"):
		_add_log_msg("One back, one pack", Color(0.9, 0.75, 0.4))
		return false
	for it in inventory:
		if String(it.name) == String(d.name):
			it.count = int(it.count) + int(d.count)
			if menu_open == "tab" and tab_page == "inventory":
				_refresh_inventory_ui()
			return true
	## The rucksack is never refused for space — it IS the space (losing it
	## shrinks the grid to pockets, and pockets must still take the pack back).
	if not force and String(d.name) != "Old Rucksack" \
			and inventory.size() >= _backpack_capacity():
		_add_log_msg("Backpack full", Color(0.9, 0.75, 0.4))
		return false
	inventory.append(d.duplicate())
	if menu_open == "tab" and tab_page == "inventory":
		_refresh_inventory_ui()
	return true


func _find_armor_index(mat_id: String, slot: String) -> int:
	for i in range(inventory.size()):
		var it := inventory[i]
		if String(it.get("slot", "")) == slot and String(it.get("material", "")) == mat_id:
			return i
	return -1


func _equip_set(mat_id: String) -> void:
	## The whole kit goes on in one motion — helmet to boots. (Re-find each
	## piece per slot: every equip MOVES an item, so grid indices shift.)
	for slot: String in Materials.ARMOR_SLOTS:
		var idx := _find_armor_index(mat_id, slot)
		if idx != -1:
			_equip_from_pack(idx, slot)
	_apply_armor_visuals()
	_add_log_msg("%s set equipped — head to toe" % Materials.display_name(mat_id), Color(0.85, 0.9, 1.0))
	_garment_note()
	_refresh_inventory_ui()


func _give_armor_set(mat_id: String) -> void:
	## The full 5-piece kit of one material, straight into the pack.
	for slot: String in Materials.ARMOR_SLOTS:
		_give_item_dict({"name": Materials.armor_piece_name(mat_id, slot),
			"weight": Materials.armor_piece_weight(mat_id, slot), "count": 1,
			"slot": slot, "material": mat_id})


func worn_metals() -> Dictionary:
	## The five armour slots as `Garments` wants them: slot -> material id.
	## Empty slots are left OUT rather than carried as "", so `cover()` and
	## `pieces()` agree with what is actually on the body.
	var w: Dictionary = {}
	for slot: String in Materials.ARMOR_SLOTS:
		var it: Dictionary = equipment.get(slot, {})
		var m := String(it.get("material", ""))
		if m != "":
			w[slot] = m
	return w


func _garment_note() -> void:
	## What the set you have just put on is worth TONIGHT, said at the one
	## moment the choice is in front of you. Every number is `Garments`';
	## this reads and prints.
	var worn := worn_metals()
	if worn.is_empty():
		return
	var e := _exposure_env()
	var g := Exposure.garment_c(e, exposure.wet)
	var v := Garments.verdict(worn, Exposure.still_air_c(e), exposure.wet,
		clampf(float(e.get("wind", 0.0)), 0.0, 1.0))
	_add_log_msg("%s out here: %+.1f C - %s" % [Garments.describe(worn), g, v],
		Color(0.72, 0.84, 1.0) if g >= 0.0 else Color(1.0, 0.76, 0.55))


func _armor_mult() -> float:
	## Damage multiplier from worn material armor: each piece shaves 2/3/4/5%
	## by tier (full set: common 10% -> end-game 25%), capped at 40% total so
	## plate never trivializes the game. Placeholder rags protect nothing.
	var protect := 0.0
	for slot: String in Materials.ARMOR_SLOTS:
		var m := _slot_metal(slot)
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
	var m := String(_slot_item(slot).get("material", ""))
	if m != "":
		return [Materials.get_mat(m)["color"], true]
	return [def, false]


func _apply_armor_visuals() -> void:
	## The visible body wears what you equipped: helm -> the third-person head
	## (open-faced cap, hair tucks under it), chest -> torso plate, bracers ->
	## both upper arms + the viewmodel forearm, greaves -> pelvis and legs,
	## boots -> feet.
	var h: Array = _slot_wear_color("helmet", BODY_ARMOR_COL)
	var has_helm := not _slot_item("helmet").is_empty()
	if tp_helm:
		tp_helm.visible = has_helm
		for hm in helm_meshes:
			_tint(hm, h[0], h[1])
		for hm2 in hair_meshes:
			hm2.visible = not has_helm
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
	_apply_armor_weather()


func _slot_metal(slot: String) -> String:
	return String(_slot_item(slot).get("material", ""))


func _apply_armor_weather() -> void:
	## Worn high metal is WEATHER too: meteoric/dragonsteel plate smolders —
	## the pieces glow ember-hot at the edges and pixel fire sheds off the
	## torso — and voidsteel plate leaks the same slow purple void the blade
	## wears. One emitter + one soft light, keyed to what's actually worn.
	var fiery := false
	var voidy := false
	var sets: Array = [
		["helmet", helm_meshes], ["chest", [torso_mesh]],
		["arms", arm_meshes], ["pants", leg_meshes], ["shoes", foot_meshes]]
	for entry: Array in sets:
		var metal := _slot_metal(String(entry[0]))
		var f := metal == "meteoric" or metal == "dragonsteel"
		var v := metal == "voidsteel"
		fiery = fiery or f
		voidy = voidy or v
		for mesh in entry[1]:
			_smolder(mesh as MeshInstance3D,
				Color(1.0, 0.45, 0.12) if f else (Color(0.55, 0.22, 0.9) if v else Color.BLACK))
	## The forearm rides the bracers' weather in first person too.
	var am := _slot_metal("arms")
	_smolder(forearm_mesh, Color(1.0, 0.45, 0.12) if (am == "meteoric" or am == "dragonsteel")
		else (Color(0.55, 0.22, 0.9) if am == "voidsteel" else Color.BLACK))
	## Pelvis wears the greaves' weather.
	var pm := _slot_metal("pants")
	_smolder(pelvis_mesh, Color(1.0, 0.45, 0.12) if (pm == "meteoric" or pm == "dragonsteel")
		else (Color(0.55, 0.22, 0.9) if pm == "voidsteel" else Color.BLACK))

	var want := "fire" if fiery else ("void" if voidy else "")
	if want == _armor_fx_mode:
		return
	_armor_fx_mode = want
	if is_instance_valid(_armor_fx):
		_armor_fx.queue_free()
		_armor_fx = null
	if want == "":
		return
	_armor_fx = Node3D.new()
	body_rig.add_child(_armor_fx)
	var em := _pixel_weather(want == "fire", Vector3(0.24, 0.34, 0.15), Vector3(0, 1.05, 0))
	em.amount = 20
	em.local_coords = false  ## armor weather trails as you run, both kinds
	_armor_fx.add_child(em)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.5, 0.15) if want == "fire" else Color(0.60, 0.25, 0.95)
	l.light_energy = 0.6
	l.omni_range = 2.6
	l.shadow_enabled = false
	l.position = Vector3(0, 1.1, 0)
	_armor_fx.add_child(l)


func _smolder(mesh: MeshInstance3D, col: Color) -> void:
	## Edge-heat on a worn plate — Color.BLACK means "plain steel, no glow".
	if mesh == null:
		return
	var m := mesh.material_override as StandardMaterial3D
	if m == null:
		return
	m.emission_enabled = col != Color.BLACK
	if col != Color.BLACK:
		m.emission = col
		m.emission_energy_multiplier = 0.55


## ============= Dropped items (Q to toss, look + E to reclaim) ==============


func _doll_clicked(slot: String) -> void:
	## The paper doll is interactive now: click a worn thing to take it off.
	if _unequip_slot(slot):
		_apply_armor_visuals()


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
	## (Grid swords are SPARES now — the wielded blade lives safe in its
	## slot, so any of these can go.) The pack itself still can't:
	if String(it.name) == "Old Rucksack":
		_add_log_msg("Your whole life is in that rucksack — it stays on", Color(0.9, 0.75, 0.4))
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
	node.global_position = _aim_origin() + fwd * 0.7 + Vector3.DOWN * 0.2
	node.velocity = fwd * 4.2 + Vector3.UP * 2.2
	_drop_carried_logs("you reached into your pack")
	_add_log_msg("Dropped: %s" % String(d.name), Color(0.9, 0.9, 1.0))
	_refresh_inventory_ui()


func _remove_inventory_index(idx: int) -> void:
	## Grid indices shift on removal — and nothing cares any more: worn
	## things live IN their slots now, not as pointers into the pack.
	inventory.remove_at(idx)
	hovered_item_idx = -1


func _set_hovered_item(idx: int) -> void:
	hovered_item_idx = idx


func _unset_hovered_item(idx: int) -> void:
	if hovered_item_idx == idx:
		hovered_item_idx = -1


## ==================== The reach (crouch, hand, shoulder) ==================
## One arm, five beats, and the thing itself rides in the fist for the last
## three of them -- there is no second copy of it and no particle stand-in, so
## what you watch go into the pack is the very node that was lying there.


func _grab_target() -> Node3D:
	## The one thing a reach could take right now. Loot first, then a landed
	## rock, then a felled log -- the same order the gaze already ranks them
	## in. Bedrolls are not grabbed; they are packed (E) or slept in (F).
	if _drop_target != null and is_instance_valid(_drop_target):
		return _drop_target
	if _debris_target != null and is_instance_valid(_debris_target):
		return _debris_target
	if _log_target != null and is_instance_valid(_log_target):
		return _log_target
	return null


func _try_grab(from_click: bool) -> bool:
	## Start the reach. Returns FALSE when there is nothing to take, and the
	## caller then does whatever it would have done anyway -- so left click
	## near your loot pile still swings, and E still falls through to the bed,
	## the water and the old out-of-reach snap.
	if reach_phase != "" or menu_open != "" or kd_phase != "" or climbing \
			or mount != null or grabbed_by != null or swimming or input_locked \
			or editing or attacking or axe_swinging or pick_swinging or drawing:
		return false
	var n := _grab_target()
	if n == null:
		return false
	if n.global_position.distance_to(get_waist_point()) > GRAB_REACH:
		return false  ## seen, but not within an arm and a lean of you
	if from_click and _any_enemy_mad_at_me():
		return false  ## a fight is on -- left click stays a swing. E still reaches.
	reach_node = n
	reach_kind = "item"
	if n is RockDebris:
		reach_kind = "debris"
	elif n is CarryLog:
		reach_kind = "log"
	reach_spot = n.global_position
	reach_held = false
	reach_phase = "down"
	reach_t = 0.0
	reach_out = 0.0
	reach_stow = 0.0
	## What to put back on the way up: the stance you were in, and whether the
	## sword was actually drawn (a tool in the fist just goes away and comes
	## back -- only steel gets pulled again).
	reach_was_crouch = crouching
	reach_was_prone = prone
	reach_redraw = current_weapon == "sword" and not sheathed
	blocking = false
	sheathed = true          ## the blade rides home while the hand is busy
	prone = false
	crouching = true         ## down onto one knee for it
	_stance_settle_pulse()
	return true


func _update_grab(delta: float) -> void:
	## Called from _frame_fx_and_regen, which every stance routes through, so
	## the reach keeps ticking whatever else the body is doing. Anything that
	## takes the body AWAY from you -- a hoof, a jaw, a menu, a bed -- abandons
	## it, and whatever was in the fist goes back on the ground where it lay.
	if reach_phase == "":
		return
	if kd_phase != "" or grabbed_by != null or input_locked or menu_open != "" \
			or climbing or mount != null or editing or swimming:
		_grab_abort()
		return
	if reach_node == null or not is_instance_valid(reach_node):
		_grab_abort()   ## something ate it mid-reach (a fade-out, a save load)
		return
	reach_t += delta
	match reach_phase:
		"down":
			## Knees bend, the scabbard takes the blade. Nothing moves yet.
			if reach_t >= GRAB_T_DOWN:
				reach_phase = "out"
				reach_t = 0.0
		"out":
			reach_out = clampf(reach_t / GRAB_T_OUT, 0.0, 1.0)
			## Ownership is taken the moment the hand starts moving, so the
			## thing stops rolling and settling while you are reaching for it.
			if not reach_held:
				_grab_take()
			if reach_t >= GRAB_T_OUT:
				reach_out = 1.0
				reach_phase = "hold"
				reach_t = 0.0
		"hold":
			reach_out = 1.0
			if reach_t >= GRAB_T_HOLD:
				reach_phase = "back"
				reach_t = 0.0
		"back":
			var p := clampf(reach_t / GRAB_T_BACK, 0.0, 1.0)
			reach_out = 1.0 - p
			reach_stow = p
			if reach_t >= GRAB_T_BACK:
				reach_out = 0.0
				reach_stow = 1.0
				reach_phase = "up"
				reach_t = 0.0
				_grab_deliver()
		"up":
			reach_out = 0.0
			reach_stow = 1.0 - clampf(reach_t / GRAB_T_UP, 0.0, 1.0)
			if reach_t >= GRAB_T_UP:
				_grab_finish()
				return
	## Once the fist is closed the thing rides IN it -- tracked off tp_hand_r,
	## the same grip node the sword hangs from, so it follows the arm's real
	## pose instead of a guess at where the hand probably is.
	## The last half of the reach draws it up to meet the closing fist, gently;
	## from the moment the fingers shut it is welded there.
	if reach_held and reach_node != null and is_instance_valid(reach_node) \
			and (reach_phase != "out" or reach_out > 0.45):
		var hand := to_global(Vector3(0.30, 0.95, -0.40))
		if tp_hand_r != null and is_instance_valid(tp_hand_r):
			hand = tp_hand_r.global_position
		var w := 9.0 if reach_phase == "out" else 24.0
		reach_node.global_position = reach_node.global_position.lerp(
			hand, clampf(delta * w, 0.0, 1.0))
		if reach_phase == "back" or reach_phase == "up":
			## Shrinking away into the pack rather than popping out of the world.
			reach_node.scale = Vector3.ONE * maxf(0.06, 1.0 - reach_stow * 0.94)


func _grab_take() -> void:
	## The fist closes. The thing stops being the world's and becomes yours:
	## its own falling/rolling/settling process is switched off so nothing
	## fights the hand for it on the way to your back.
	if reach_node == null or not is_instance_valid(reach_node):
		return
	reach_held = true
	reach_node.set_physics_process(false)
	var di := reach_node as DroppedItem
	if di != null:
		di.velocity = Vector3.ZERO
	var cl := reach_node as CarryLog
	if cl != null:
		cl.velocity = Vector3.ZERO
	var rd := reach_node as RockDebris
	if rd != null:
		rd.vel = Vector3.ZERO


func _grab_deliver() -> void:
	## Over the shoulder and IN. Everything the old instant E did happens here
	## instead, at the end of the arm's travel -- so a full pack refuses at the
	## last moment and the hand sets the thing back down where it was found.
	reach_held = false
	if reach_node == null or not is_instance_valid(reach_node):
		reach_node = null
		return
	var n := reach_node
	if reach_kind == "debris":
		if _give_item("Rock", 1, 0.8):
			_push_gain("Rock", 1)
			n.queue_free()
			_debris_target = null
		else:
			_add_log_msg("Backpack full", Color(0.9, 0.75, 0.4))
	elif reach_kind == "log":
		_hoist_log(n as CarryLog)
	else:
		_pickup_dropped(n as DroppedItem)
	if is_instance_valid(n) and not n.is_queued_for_deletion():
		_grab_put_back(n)
	reach_node = null


func _grab_put_back(n: Node3D) -> void:
	## Refused, or interrupted: the thing goes back to the exact spot it was
	## lying in, full size, falling and settling for itself again.
	n.scale = Vector3.ONE
	n.global_position = reach_spot
	n.set_physics_process(true)


func _grab_clear() -> void:
	reach_phase = ""
	reach_t = 0.0
	reach_out = 0.0
	reach_stow = 0.0
	reach_held = false
	reach_node = null
	reach_kind = ""


func _grab_finish() -> void:
	## Standing back up. The stance you were in comes back, and the sword comes
	## back out only if it was out when you reached -- otherwise the arm simply
	## falls to your side and nothing is drawn that you did not draw yourself.
	_grab_clear()
	crouching = reach_was_crouch
	prone = reach_was_prone
	if reach_redraw:
		sheathed = false
	reach_redraw = false
	_stance_settle_pulse()


func _grab_abort() -> void:
	## Something took the body away mid-reach. Put whatever was in the fist
	## back on the ground and forget the whole thing -- but still give the
	## stance and the steel back, or you would stand up from a bear's jaws
	## permanently crouched with your sword mysteriously put away.
	if reach_held and reach_node != null and is_instance_valid(reach_node):
		_grab_put_back(reach_node)
	var redraw := reach_redraw
	var was_crouch := reach_was_crouch
	var was_prone := reach_was_prone
	_grab_clear()
	reach_redraw = false
	if kd_phase == "" and grabbed_by == null:
		crouching = was_crouch
		prone = was_prone
	if redraw and current_weapon == "sword":
		sheathed = false


func _pickup_dropped(di: DroppedItem) -> void:
	if _take_dropped_item(di):
		di.queue_free()
		_drop_target = null


func _take_dropped_item(di: DroppedItem) -> bool:
	## The PACK half of a pickup -- everything except making the node go away,
	## so the hold-E sweep can count a thing in and then fly the node home
	## instead of blinking it out. False means the rucksack refused it and it
	## is still lying there.
	var d: Dictionary = di.item
	var nm := String(d.get("name", ""))
	var mat := String(d.get("material", ""))
	if mat != "" and nm.ends_with(" Ore"):
		## Ore keeps its unlock magic: the first chunk of a new metal still
		## forges that sword on the spot (collect_pickup handles it).
		if not _has_room(nm) and _owns_sword_of(mat):
			_add_log_msg("Backpack full", Color(0.9, 0.75, 0.4))
			return false  ## leave it lying
		collect_pickup("ore", int(d.get("count", 1)), mat)
		return true
	if not _give_item_dict(d):
		return false  ## backpack full — it stays on the ground
	_push_gain(nm, int(d.count))
	return true


## ===================== Logs on the shoulder (look + E) ====================
## The tree gives you weight, not lumber. Four logs is a load; everything that
## needs your hands, your balance, or your back puts them on the ground.


func _hoist_log(cl: CarryLog) -> void:
	## SHOULDER-CARRYING IS GONE (Lemon 2026-08-30). A log is an ordinary
	## inventory item now — bucking a trunk drops one on the ground and you
	## take it like anything else. This is kept only so that logs already lying
	## in an old save can still be picked up: it converts one into the item.
	##
	## The old four-log cap is not gone, it just is not a number any more. A log
	## weighs FallenTrunk.LOG_WEIGHT against a base carry limit of 90, so four
	## or five is still all a back will take — and the game says so by making
	## you overburdened rather than by refusing the pickup.
	if not _give_item_dict({"name": "Log", "weight": FallenTrunk.LOG_WEIGHT,
			"count": 1, "slot": "", "material": ""}):
		return                          ## pack is full — it stays on the ground
	cl.queue_free()
	_log_target = null
	_push_gain("Log", 1)


func _drop_carried_logs(_why: String) -> void:
	## DELIBERATELY EMPTY. Logs live in the pack now (Lemon 2026-08-30), so
	## there is no load to shed: nothing about jumping, crouching, going prone,
	## drawing a weapon, climbing, mounting, being hit or reaching into the
	## rucksack should tip timber out of it any more. Roughly fifteen call
	## sites across this file still ask, and every one of them is still right
	## to ask — this is the single place that answers, and the answer now is
	## that there is nothing on your shoulder to drop.
	pass


func _refresh_log_rig() -> void:
	## The shoulder rig is retired with the carrying — see _drop_carried_logs.
	## It still EMPTIES itself, so a save written before 2026-08-30 that comes
	## back with logs on its shoulder does not leave billets floating beside
	## the player's head forever.
	if log_rig == null:
		return
	for c in log_rig.get_children():
		log_rig.remove_child(c)
		c.queue_free()


## ===================== The pile sweep (hold E) ============================
## Look at one thing and TAP E and you take that thing, exactly as before.
## Look at one thing and HOLD E and the heap it is lying in comes in after it,
## one every ninety milliseconds, nearest first. Same kind means the same item
## name AND the same material, so a hold over a heap of iron ore leaves the
## silver beside it alone. The hold only ever ADDS to the tap -- it never
## delays it -- and it ends the moment you let go, the pack fills, the pile
## runs out, or anything at all opens over the screen.


func _gather_arm() -> void:
	## E has just gone down. Remember WHAT is under the gaze now, because the
	## tap being served on this same frame is about to take it and clear the
	## target out from under us.
	_e_held = true
	_e_down_ms = Time.get_ticks_msec()
	_gather_t = 0.0
	_gather_n = 0
	_gather_name = ""
	_gather_mat = ""
	_gather_kind = ""
	if menu_open != "" or kd_phase != "":
		return
	if _drop_target != null and is_instance_valid(_drop_target):
		_gather_name = _drop_target.display_name()
		_gather_mat = String(_drop_target.item.get("material", ""))
		_gather_kind = "item"
	elif _debris_target != null and is_instance_valid(_debris_target):
		_gather_name = "Rock"
		_gather_kind = "debris"


func _gather_stop() -> void:
	_e_held = false
	_gather_name = ""
	_gather_mat = ""
	_gather_kind = ""
	_gather_n = 0


func _update_gather(delta: float) -> void:
	if not _e_held or _gather_kind == "":
		return
	## Anything that takes the world away from you ends the sweep.
	if menu_open != "" or kd_phase != "" or input_locked or climbing \
			or mount != null or grabbed_by != null or swimming or editing:
		_gather_stop()
		return
	if Time.get_ticks_msec() - _e_down_ms < int(GATHER_HOLD * 1000.0):
		return                       ## still inside the tap window
	_gather_t -= delta
	if _gather_t > 0.0:
		return
	_gather_t = GATHER_STEP
	if not _gather_one():
		_gather_stop()               ## pile empty, or the pack said no


func _gather_one() -> bool:
	## The nearest one left of the same kind, within a pile's width of the
	## waist. ONE per call -- the stream is the point. The thing already in
	## the reaching hand is skipped: the reach is going to deliver it itself,
	## and taking it here as well would put two of it in the pack.
	var from := get_waist_point()
	var best: Node3D = null
	var bd := GATHER_RADIUS * GATHER_RADIUS
	if _gather_kind == "item":
		for n in get_tree().get_nodes_in_group("dropped_items"):
			var di := n as DroppedItem
			if di == null or di == reach_node or di.gather_to != null:
				continue
			if di.is_queued_for_deletion():
				continue
			if di.display_name() != _gather_name:
				continue
			if String(di.item.get("material", "")) != _gather_mat:
				continue
			var d2 := di.global_position.distance_squared_to(from)
			if d2 < bd:
				bd = d2
				best = di
		if best == null:
			return false
		var take := best as DroppedItem
		if not _take_dropped_item(take):
			return false             ## full pack -- the rest stays where it lies
		take.gather_fly(self)
		if _drop_target == take:
			_drop_target = null
	else:
		for n in get_tree().get_nodes_in_group("debris"):
			var rd := n as RockDebris
			if rd == null or rd == reach_node or rd.gather_to != null:
				continue
			if not rd.landed or rd.wood or rd.is_queued_for_deletion():
				continue
			var rd2 := rd.global_position.distance_squared_to(from)
			if rd2 < bd:
				bd = rd2
				best = rd
		if best == null:
			return false
		if not _give_item("Rock", 1, 0.8):
			_add_log_msg("Backpack full", Color(0.9, 0.75, 0.4))
			return false
		_push_gain("Rock", 1)
		(best as RockDebris).gather_fly(self)
		if _debris_target == best:
			_debris_target = null
	_gather_n += 1
	return true


func _pile_count() -> int:
	## How many of the looked-at thing are lying within a sweep of you -- the
	## number the prompt offers to take, counting the one you can see.
	var from := get_waist_point()
	var r2 := GATHER_RADIUS * GATHER_RADIUS
	var n := 0
	if _drop_target != null and is_instance_valid(_drop_target):
		var nm := _drop_target.display_name()
		var mat := String(_drop_target.item.get("material", ""))
		for x in get_tree().get_nodes_in_group("dropped_items"):
			var di := x as DroppedItem
			if di == null or di.gather_to != null:
				continue
			if di.display_name() == nm and String(di.item.get("material", "")) == mat \
					and di.global_position.distance_squared_to(from) < r2:
				n += 1
	elif _debris_target != null and is_instance_valid(_debris_target):
		for x in get_tree().get_nodes_in_group("debris"):
			var rd := x as RockDebris
			if rd == null or rd.gather_to != null or not rd.landed or rd.wood:
				continue
			if rd.global_position.distance_squared_to(from) < r2:
				n += 1
	return n


func _update_drop_target() -> void:
	## Which dropped item is under the gaze? Close (<3.2m) and near the center
	## of the view — the same "look at it" feel as aiming a swing.
	_drop_target = null
	_bed_target = null
	_debris_target = null
	_fire_target = null
	_log_target = null
	_carc_target = {}
	if menu_open != "" or kd_phase != "" or reach_phase != "":
		return  ## mid-reach the gaze picks nothing new up
	var best := 0.92
	var fwd := -camera.global_transform.basis.z
	for n in get_tree().get_nodes_in_group("dropped_items"):
		var di := n as DroppedItem
		if di == null:
			continue
		var to := di.global_position - _aim_origin()
		var dist := to.length()
		if dist > 3.2 or dist < 0.05:
			continue
		var d := fwd.dot(to.normalized())
		if d > best:
			best = d
			_drop_target = di
	if _drop_target != null:
		return  ## loot wins the gaze — beds are bigger targets anyway
	var bbest := 0.86
	for n in get_tree().get_nodes_in_group("beds"):
		if not (n is Node3D):
			continue
		var to := (n as Node3D).global_position + Vector3.UP * 0.15 - _aim_origin()
		var dist := to.length()
		if dist > 3.0 or dist < 0.05:
			continue
		var d := fwd.dot(to.normalized())
		if d > bbest:
			bbest = d
			_bed_target = n as Node3D
	if _bed_target != null:
		return
	## Landed ROCKS from mining can be gathered too (wood chips are dressing).
	var rbest := 0.90
	for n in get_tree().get_nodes_in_group("debris"):
		var rd := n as RockDebris
		if rd == null or not rd.landed or rd.wood:
			continue
		var to := rd.global_position - _aim_origin()
		var dist := to.length()
		if dist > 2.8 or dist < 0.05:
			continue
		var d := fwd.dot(to.normalized())
		if d > rbest:
			rbest = d
			_debris_target = rd
	if _debris_target != null:
		return
	## And the logs a felled tree left lying — E swings one onto your shoulder.
	var lbest := 0.86
	for n in get_tree().get_nodes_in_group("carry_logs"):
		var cl := n as CarryLog
		if cl == null:
			continue
		var to := cl.global_position - _aim_origin()
		var dist := to.length()
		if dist > 3.2 or dist < 0.05:
			continue
		var d := fwd.dot(to.normalized())
		if d > lbest:
			lbest = d
			_log_target = cl

	if _log_target != null:
		return
	## And a fire pit. E lights it, feeds it, or tells you what it wants. The
	## cone is a touch wider than the others because a firepit is a two-metre
	## ring of stones and you are usually standing right in it.
	var fbest := 0.84
	for n in get_tree().get_nodes_in_group("fires"):
		var fp := n as Firepit
		if fp == null:
			continue
		var to := fp.here() + Vector3.UP * 0.3 - _aim_origin()
		var dist := to.length()
		if dist > 3.4 or dist < 0.05:
			continue
		var d := fwd.dot(to.normalized())
		if d > fbest:
			fbest = d
			_fire_target = fp

	## And a carcass. E butchers it -- see `Butchery`, which is the caller
	## `Carcasses.harvest_at` had been waiting for since `a23a20e`.
	##
	## It competes with the fire rather than deferring to it, because
	## butchering BESIDE a fire is the whole winter play (a cut leaves you
	## bloody, and wet is worth three and a half minutes of a winter warmth
	## bar) and an early return here would have made the smart move the one
	## the game refuses.
	var carc := Carcasses.get_bus(self)
	if carc == null or not is_instance_valid(carc):
		return
	var cbest: float = maxf(Butchery.CONE, fbest if _fire_target != null else 0.0)
	for row in carc.near(_aim_origin(), Butchery.REACH):
		var rec: Dictionary = (row as Dictionary)["rec"]
		var to2: Vector3 = (rec["at"] as Vector3) + Vector3.UP * 0.25 - _aim_origin()
		var dist2 := to2.length()
		if dist2 > Butchery.REACH or dist2 < 0.05:
			continue
		var d2 := fwd.dot(to2.normalized())
		if d2 > cbest:
			cbest = d2
			_carc_target = rec
	if not _carc_target.is_empty():
		_fire_target = null


func _edge_mat() -> String:
	## What you would open an animal with, as a `Materials` id, or "" for
	## nothing. THE SWORD ON YOUR HIP IS AN EDGE -- a wretched butcher's tool
	## and the only one Myrkfell has -- so this is reachable from the first
	## minute of a new game rather than gated behind a knife that does not
	## exist anywhere in the project. A pickaxe is not an edge.
	var sw: Dictionary = _slot_item("sword")
	if not sw.is_empty():
		var m := String(sw.get("material", ""))
		if Butchery.edge_tier(m) >= 0:
			return m
	for it in inventory:
		var nm := String(it.get("name", ""))
		if nm.contains("Knife") or nm.contains("Dagger"):
			var m2 := String(it.get("material", "iron"))
			return m2 if Butchery.edge_tier(m2) >= 0 else "iron"
	return ""


func _butcher_cut() -> void:
	## ONE CUT. Everything it refuses, it refuses out loud, because a verb
	## that silently does nothing is indistinguishable from a broken one.
	var carc := Carcasses.get_bus(self)
	if carc == null or not is_instance_valid(carc) or _carc_target.is_empty():
		return
	if _cut_cd > 0.0:
		return
	var rec := _carc_target
	var carcass_mass := float(rec.get("mass", 0.0))
	var before := float(rec.get("left", 0.0))
	var species0 := String(rec.get("species", ""))
	var harv0: Dictionary = (CritterDex.get_profile(species0) as Dictionary).get("harv", {})
	if Carcasses.stage_of(rec) >= Carcasses.STAGE_BONES:
		_add_log_msg("Bones. There is nothing on it to take", Color(0.75, 0.75, 0.75))
		return
	if not Butchery.butcherable(harv0):
		_add_log_msg("There is nothing on a %s a knife is for"
			% String(rec.get("nm", "beast")).to_lower(), Color(0.80, 0.80, 0.80))
		return
	var edge := _edge_mat()
	if edge == "":
		_add_log_msg("Nothing on you will open it -- it wants an edge", Color(0.90, 0.75, 0.40))
		return
	var limit := stats.carry_limit()
	var carried := _total_weight()
	var want := Butchery.take_for(before, Butchery.cut_kg(edge), carried, limit)
	if want <= 0.0:
		_add_log_msg("Your back is full -- %.0f / %.0f" % [carried, limit],
			Color(0.90, 0.75, 0.40))
		return
	if stamina < Butchery.CUT_STAMINA:
		_add_log_msg("No strength left in your arms for it", Color(0.80, 0.80, 0.80))
		return

	## THE LEDGER IS THE TRUTH: what the bus gives back is what goes in the
	## pack, never what we asked for.
	var got := carc.harvest_at(rec["at"] as Vector3, 1.0, want)
	if got <= 0.0:
		return
	var after := float(rec.get("left", before - got))
	_cut_cd = Butchery.CUT_SECONDS
	stamina = maxf(0.0, stamina - Butchery.CUT_STAMINA)

	var species := species0
	var nm := String(rec.get("nm", "beast"))
	var harv := harv0

	## The meat is counted in whole kilograms, one weight unit each, so the
	## pack and the carcass ledger can never drift apart by a rounding error.
	if int(harv.get("meat", 0)) > 0:
		var mn := Butchery.meat_name(species, nm)
		var kg := Butchery.meat_count(got)
		if _give_item_dict({"name": mn, "weight": 1.0, "count": kg, "slot": ""}):
			_push_gain(mn, kg)

	## And the parts, out of the dex's own `harv` row -- its first reader in
	## the life of the project.
	var due: Dictionary = Butchery.parts_due(harv, carcass_mass, carcass_mass - before, carcass_mass - after)
	for k in due.keys():
		var part := String(k)
		var cnt := int(due[k])
		var pnm := Butchery.part_name(part, nm)
		if _give_item_dict({"name": pnm, "weight": Butchery.part_weight(part),
				"count": cnt, "slot": ""}):
			_push_gain(pnm, cnt)

	## A CUT IS WET WORK, and in autumn that is an eight-fold hazard.
	if warmth_survival():
		exposure.wet = minf(1.0, exposure.wet + Butchery.CUT_WET)

	if Carcasses.open_mult(carcass_mass, before) == 1.0 and Carcasses.open_mult(carcass_mass, after) > 1.0:
		_add_log_msg("It is open now, and the woods can smell it", Color(0.95, 0.78, 0.55))
	for id in Butchery.crossed(carcass_mass, before, after):
		var line := Butchery.denied_line(String(id))
		if line != "":
			_add_log_msg(line, Color(0.72, 0.88, 0.72))


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
	## Worn gear counts at HALF weight — a thing on your body carries easier
	## than a thing in your pack (which is now a genuinely separate place).
	var w := 0.0
	for it in inventory:
		w += float(it.weight) * float(it.count)
	for slot in SLOT_ORDER:
		var e: Dictionary = _slot_item(slot)
		if not e.is_empty():
			w += float(e.get("weight", 0.0)) * float(e.get("count", 1)) * 0.5
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
	## Diablo/Minecraft layout: the EQUIPPED paper doll on the left (hands,
	## armor, two accessory berths), the 9-wide BACKPACK GRID on the right,
	## weight + coin purse underneath. (The old dev Armory column moved to
	## the G creative menu.)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 26)

	## Equipped column — the paper doll.
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	hb.add_child(left)
	var eq_title := Label.new()
	eq_title.text = "Equipped"
	eq_title.add_theme_font_size_override("font_size", 22)
	left.add_child(eq_title)
	## Every doll row is a real CONTAINER now (Terraria rules): click a worn
	## thing to take it OFF, back into the grid. The sword politely refuses.
	for slot in SLOT_ORDER:
		var lbl := Button.new()
		lbl.custom_minimum_size = Vector2(214, 0)
		lbl.alignment = HORIZONTAL_ALIGNMENT_LEFT
		lbl.flat = true
		lbl.focus_mode = Control.FOCUS_NONE
		lbl.pressed.connect(_doll_clicked.bind(String(slot)))
		left.add_child(lbl)
		inv_slot_labels[slot] = lbl
	## One-click set equip: a button appears here for every material whose
	## full 5-piece kit is in the pack.
	inv_sets_box = VBoxContainer.new()
	inv_sets_box.add_theme_constant_override("separation", 3)
	left.add_child(inv_sets_box)

	## Backpack column — the slot grid.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	hb.add_child(right)
	var title := Label.new()
	title.text = "Backpack  (%d × %d)" % [PACK_COLS, backpack_rows]
	title.add_theme_font_size_override("font_size", 22)
	right.add_child(title)
	var grid := GridContainer.new()
	grid.columns = PACK_COLS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	right.add_child(grid)
	inv_cells.clear()
	for n in range(_backpack_capacity()):
		var b := Button.new()
		b.custom_minimum_size = Vector2(74, 52)
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(_cell_clicked.bind(n))
		b.mouse_entered.connect(_set_hovered_item.bind(n))
		b.mouse_exited.connect(_unset_hovered_item.bind(n))
		grid.add_child(b)
		inv_cells.append(b)
	inv_weight_label = Label.new()
	right.add_child(inv_weight_label)
	inv_purse_label = Label.new()
	right.add_child(inv_purse_label)
	var hint := Label.new()
	hint.text = "Click a pack item to EQUIP / use it (it moves into its slot — Terraria rules);\nclick a worn slot on the doll to take it back off. B drops · Q wheels (hold Q = pick seat)\n1 / 2 / 3 / 4 switch pages — Esc closes"
	hint.modulate = Color(1, 1, 1, 0.55)
	right.add_child(hint)
	return hb


func _cell_clicked(cell: int) -> void:
	if cell < inventory.size():
		_item_clicked(cell)


func _purse_text() -> String:
	## Terraria's ladder as a COUNT, not slots: 100 copper = 1 silver,
	## 100 silver = 1 gold, 100 gold = 1 platinum. `gold` stores raw copper.
	var c := gold
	var p := int(c / 1000000.0)
	c -= p * 1000000
	var s := int(c / 10000.0)
	c -= s * 10000
	var si := int(c / 100.0)
	c -= si * 100
	return "Purse:  %dp  %dg  %ds  %dc" % [p, s, si, c]


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
	_detail_label(String(MOB_FLAVOR.get(nm, Slime.flavor_of(nm))), 14, Color(1, 1, 1, 0.65))
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

		var head_lbl := Label.new()
		head_lbl.add_theme_font_size_override("font_size", 19)
		prog_box.add_child(head_lbl)
		if bool(t.locked):
			head_lbl.text = "???  —  %s" % stat_name
			head_lbl.modulate = Color(1, 1, 1, 0.45)
			var why := _prog_line("     %s" % String(t.desc), Color(1, 1, 1, 0.35))
			prog_box.add_child(why)
			prog_box.add_child(_prog_gap())
			continue
		var suffix := "   (%d earned)" % earned if earned > 0 else ""
		head_lbl.text = "%s  —  %s%s" % [String(t.name), stat_name, suffix]
		head_lbl.modulate = Color(1.0, 0.85, 0.45) if earned > 0 else Color(1, 1, 1, 0.9)
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
	var wrap_ctl := Control.new()
	wrap_ctl.custom_minimum_size = Vector2(300, 10)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.5)
	bg.size = Vector2(260, 6)
	bg.position = Vector2(40, 2)
	wrap_ctl.add_child(bg)
	var fill := ColorRect.new()
	fill.color = Color(0.45, 0.70, 1.0)
	fill.size = Vector2(260.0 * clampf(ratio, 0.0, 1.0), 6)
	fill.position = Vector2(40, 2)
	wrap_ctl.add_child(fill)
	return wrap_ctl


func _refresh_inventory_ui() -> void:
	var w := _total_weight()
	var lim := stats.carry_limit()  ## STR raises it
	if inv_weight_label:
		if w > lim:
			inv_weight_label.text = "Weight: %.1f / %.1f  — OVERBURDENED (slowed, no sprint)" % [w, lim]
			inv_weight_label.modulate = Color(1.0, 0.40, 0.30)
		else:
			inv_weight_label.text = "Weight: %.1f / %.1f" % [w, lim]
			inv_weight_label.modulate = Color(1, 1, 1)
	if inv_purse_label:
		inv_purse_label.text = _purse_text()
		inv_purse_label.modulate = Color(1.0, 0.85, 0.30)
	## Fill the backpack grid: one cell per stack, ● marks equipped.
	for n in range(inv_cells.size()):
		var b := inv_cells[n]
		if n < inventory.size():
			var it := inventory[n]
			b.text = "%s\n×%d" % [String(it.name), int(it.count)]
			b.tooltip_text = "%s ×%d  —  %.1f wt%s" % [it.name, int(it.count),
				float(it.weight) * float(it.count),
				("   [" + String(SLOT_NAMES.get(it.slot, it.slot)) + "]") if String(it.get("slot", "")) != "" else ""]
		else:
			b.text = ""
			b.tooltip_text = "empty slot"
	for slot in SLOT_ORDER:
		var nm := _slot_name(slot)
		(inv_slot_labels[slot] as Button).text = "%s:  %s" % [SLOT_NAMES[slot], nm if nm != "" else "—"]
	## Full-set shortcuts: one button per complete 5-piece kit in the pack.
	if inv_sets_box:
		for c in inv_sets_box.get_children():
			(c as Control).visible = false
			c.queue_free()
		for id: String in Materials.ORDER:
			var have := 0
			for slot: String in Materials.ARMOR_SLOTS:
				if _find_armor_index(id, slot) != -1:
					have += 1
			if have == Materials.ARMOR_SLOTS.size():
				var b := Button.new()
				b.text = "Equip %s set (5 pc)" % Materials.display_name(id)
				b.focus_mode = Control.FOCUS_NONE
				b.pressed.connect(_equip_set.bind(id))
				inv_sets_box.add_child(b)


func _item_clicked(idx: int) -> void:
	var it := inventory[idx]
	if String(it.name) == "Bedroll":
		_drop_carried_logs("you reached into your pack")
		_place_bedroll(idx)
		return
	if String(it.name) == "Health Potion":
		_drink_potion(idx)
		return
	if String(it.name) == "Waterskin":
		_drink_skin(idx)   ## [water]
		return
	if it.slot == "":
		return  ## plain loot — nothing to equip. TODO(design): use/drop actions later
	## Anything you actually pull out of the pack needs the hand that's
	## steadying the load — so the load goes down first.
	_drop_carried_logs("you reached into your pack")
	var slot := String(it.slot)
	if slot == "sword":
		## Clicking a grid sword SWAPS it with the wielded one (the main hand
		## is never empty — the old blade lands back in the grid).
		if _equip_from_pack(idx, "sword"):
			_apply_equipped_sword()
		_refresh_inventory_ui()
		return
	if slot == "offhand":
		## One arm, two berths: the first item takes the hand; a second joins
		## it (shield straps on, torch keeps the fist); a third swaps the hand.
		if _slot_item("offhand").is_empty():
			_equip_from_pack(idx, "offhand")
		elif _slot_item("offhand2").is_empty():
			_equip_from_pack(idx, "offhand2")
		else:
			_equip_from_pack(idx, "offhand")
		if _in_dark:
			_dark_manual = true
		_refresh_inventory_ui()
		return
	_equip_from_pack(idx, slot)
	_apply_armor_visuals()  ## the body wears what you just put on
	_refresh_inventory_ui()


## ===================== Offhand (shield / torch, Q) ========================


func _cycle_offhand() -> void:
	## Cycle the offhand through what you actually OWN: shield -> torch ->
	## shield+torch (the shield straps to the forearm so the torch can ride
	## the same fist) -> empty hand -> around again.
	if current_weapon == "bow":
		_add_log_msg("Hands are full (bow)", Color(0.8, 0.8, 0.8))
		return
	var owned := _offhand_owned_names()
	var shield_nm := ""
	var torch_nm := ""
	for nm in owned:
		if shield_nm == "" and nm.contains("Shield"):
			shield_nm = nm
		elif torch_nm == "" and nm.contains("Torch"):
			torch_nm = nm
	if owned.is_empty():
		_add_log_msg("No offhand items", Color(0.8, 0.8, 0.8))
		return
	## Build the ordered mode list: each single item, the pair, the empty hand.
	var modes: Array = []
	for nm in owned:
		modes.append([nm, ""])
	if shield_nm != "" and torch_nm != "":
		modes.append([shield_nm, torch_nm])
	modes.append(["", ""])
	var cur_a := _slot_name("offhand")
	var cur_b := _slot_name("offhand2")
	var pos := -1
	for m in range(modes.size()):
		if String(modes[m][0]) == cur_a and String(modes[m][1]) == cur_b:
			pos = m
			break
	var nxt: Array = modes[0] if pos == -1 else modes[(pos + 1) % modes.size()]
	_set_offhand_pair(String(nxt[0]), String(nxt[1]))
	if _in_dark:
		_dark_manual = true  ## your call now — the darkness watch steps back
	if String(nxt[0]) == "":
		_add_log_msg("Offhand: empty", Color(0.8, 0.8, 0.8))
	elif String(nxt[1]) != "":
		_add_log_msg("Offhand: %s + %s" % [nxt[0], nxt[1]], Color(0.85, 0.9, 1.0))
	else:
		_add_log_msg("Offhand: %s" % nxt[0], Color(0.85, 0.9, 1.0))


func _offhand_is_shield() -> bool:
	## Either displayed offhand item counts — a strapped shield still blocks.
	return offhand_shown.contains("Shield") or offhand_shown2.contains("Shield")


func _build_offhand_mesh(nm: String, nm2: String = "") -> void:
	## One left hand, up to two items: alone, an item sits in the fist; paired,
	## the shield straps across the forearm and the torch keeps the fist.
	for c in offhand_node.get_children():
		c.queue_free()
	offhand_light = null
	if nm == "" and nm2 == "":
		return
	var skin := Color(0.62, 0.46, 0.36)
	_box(offhand_node, Vector3(0.09, 0.09, 0.12), skin, Vector3(0, -0.02, 0.03))  ## left hand
	if nm != "":
		_add_offhand_item(nm)
	if nm2 != "":
		_add_offhand_item(nm2)


func _add_offhand_item(item_name: String) -> void:
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
	var want := _slot_name("offhand")
	var want2 := _slot_name("offhand2")
	if want == "" and want2 != "":
		## Never a companion without a main (a drop/unequip edge) — slide it up.
		equipment["offhand"] = equipment["offhand2"]
		equipment["offhand2"] = {}
		want = want2
		want2 = ""
	if current_weapon == "bow":
		want = ""   ## the left hand is on the bow grip — shield/torch lower away
		want2 = ""
	elif sheathed and not _in_dark:
		## In daylight the shield sheathes WITH the sword — it rides your back
		## while the blade rides the hip (torch stays up regardless). In the
		## DARK the whole left arm stays out even with the sword away: shield
		## raised, torch burning — the guard never drops down there.
		if want2.contains("Shield"):
			want2 = ""
		if want.contains("Shield"):
			want = want2  ## a torch sharing the arm slides into the fist alone
			want2 = ""
	## The stowed shield shows on your back whenever you WEAR one that isn't in hand.
	if back_shield:
		var eq_shield := _slot_name("offhand").contains("Shield") \
			or _slot_name("offhand2").contains("Shield")
		back_shield.visible = eq_shield and not (want.contains("Shield") or want2.contains("Shield"))

	if want != offhand_shown or want2 != offhand_shown2:
		## Lower whatever is up first, then swap to the new items and raise them.
		offhand_raise = maxf(0.0, offhand_raise - delta / OH_RAISE_TIME)
		if offhand_raise <= 0.0:
			_build_offhand_mesh(want, want2)
			offhand_shown = want
			offhand_shown2 = want2
	elif offhand_shown != "" and offhand_raise < 1.0:
		offhand_raise = minf(1.0, offhand_raise + delta / OH_RAISE_TIME)

	if offhand_shown == "" and offhand_raise <= 0.0:
		offhand_node.visible = false
		if tp_torch:
			tp_torch.visible = false  ## nothing in the left hand — body torch too
		return
	offhand_node.visible = true
	## Body-held twin (third person): the FP viewmodels hide from outside, so
	## whenever a torch is up it ALSO burns in the body's left fist — that's
	## the flame (and the light) the world sees with the camera stepped out.
	if tp_torch:
		tp_torch.visible = cam_mode == "tp" \
			and (offhand_shown.contains("Torch") or offhand_shown2.contains("Torch"))

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
	## Torch flame flicker — the body-held twin breathes on the same clock.
	var flick := 1.25 + sin(oh_bob_t * 7.3) * 0.12 + sin(oh_bob_t * 13.7) * 0.08
	if offhand_light:
		offhand_light.light_energy = flick
	if tp_torch_light and tp_torch and tp_torch.visible:
		tp_torch_light.light_energy = flick


## ============================ Save / load =================================
## Everything about YOU that a seed can't reproduce: where you're standing and
## which way you're looking, what's left in the pools, the whole character
## sheet (levels, banked points, every progression counter), the pack and what
## it's wearing, the coin purse, what the bestiary has learned, and what's
## riding on your shoulder. SaveGame.gd does the file; this does the state.


func save_state() -> Dictionary:
	return {
		"pos": global_position,
		"yaw": rotation.y,
		"pitch": pitch,
		"health": health,
		"stamina": stamina,
		"thirst": thirst,
		"warmth": exposure.warmth,
		"wet": exposure.wet,
		"breath": breath,
		"xp": xp,
		"level": level,
		"gold": gold,
		"weapon": current_weapon,
		"sheathed": sheathed,
		"crouching": crouching,
		"prone": prone,
		"backpack_rows": backpack_rows,
		"inventory": inventory.duplicate(true),
		"equipment": equipment.duplicate(true),
		"carried_logs": carried_logs.duplicate(true),
		"stat_vals": stats.vals.duplicate(true),
		"stat_points": stats.points,
		"progress": stats.progress.duplicate(true),
		"tiers": stats.tiers_earned.duplicate(true),
		"bestiary": bestiary_kills.duplicate(true),
		"proven": bestiary_proven.duplicate(true),
		"wheel": wheel.duplicate(),
	}


func apply_state(d: Dictionary) -> void:
	if d.is_empty():
		return
	## Put the body down first — nothing below should run against a stale pose.
	velocity = Vector3.ZERO
	global_position = d.get("pos", global_position)
	rotation.y = float(d.get("yaw", rotation.y))
	pitch = clampf(float(d.get("pitch", pitch)), -1.4, 1.4)
	head.rotation.x = pitch
	## A load can land mid-knockdown — [F] from under a fallen trunk is exactly
	## that — and nothing else would ever end it: kd_phase would stay "pinned"
	## forever, with the body laid out a metre in front of the lens.
	_stand_up_hard()

	## The sheet.
	var vals: Dictionary = d.get("stat_vals", {})
	for id: String in PlayerStats.STAT_ORDER:
		if vals.has(id):
			stats.vals[id] = clampi(int(vals[id]), PlayerStats.BASE_STAT, PlayerStats.STAT_CAP)
	stats.points = int(d.get("stat_points", 0))
	stats.progress = (d.get("progress", {}) as Dictionary).duplicate(true)
	stats.tiers_earned = (d.get("tiers", {}) as Dictionary).duplicate(true)
	xp = int(d.get("xp", 0))
	level = maxi(int(d.get("level", 1)), 1)
	gold = int(d.get("gold", 0))
	bestiary_kills = (d.get("bestiary", {}) as Dictionary).duplicate(true)
	bestiary_proven = (d.get("proven", {}) as Dictionary).duplicate(true)
	for id: String in PlayerStats.STAT_ORDER:
		pending[id] = 0

	## The pack, and what it's wearing — restored EXACTLY as it was left:
	## worn things back in their slots, grid things in the grid.
	backpack_rows = maxi(int(d.get("backpack_rows", 3)), 1)
	inventory.clear()
	for it in d.get("inventory", []):
		inventory.append((it as Dictionary).duplicate(true))
	var eq_in: Dictionary = (d.get("equipment", {}) as Dictionary)
	equipment = {}
	for slot in SLOT_ORDER:
		equipment[slot] = {}
	var v1 := false
	for slot in eq_in:
		var v: Variant = eq_in[slot]
		if v is Dictionary and not (v as Dictionary).is_empty():
			equipment[slot] = (v as Dictionary).duplicate(true)
		elif (v is int or v is float) and int(v) >= 0 and int(v) < inventory.size():
			## An OLD save (equipment stored grid indices): lift those items
			## into their slots, then strip one of each from the grid below.
			var piece: Dictionary = inventory[int(v)].duplicate(true)
			piece["count"] = 1
			equipment[slot] = piece
			v1 = true
	if v1:
		for slot in SLOT_ORDER:
			var e: Dictionary = _slot_item(slot)
			if e.is_empty():
				continue
			var gi := _find_item_index(String(e.name))
			if gi >= 0:
				inventory[gi].count = int(inventory[gi].count) - 1
				if int(inventory[gi].count) <= 0:
					_remove_inventory_index(gi)
		## Old saves also carried the rucksack as a grid item — wear it.
		if _slot_item("back").is_empty():
			var ri := _find_item_index("Old Rucksack")
			if ri >= 0:
				inventory[ri]["slot"] = "back"
				inventory[ri]["rows"] = 3
				_equip_from_pack(ri, "back")
	## The main hand is never empty — even a broken save wakes armed.
	if _slot_item("sword").is_empty():
		equipment["sword"] = {"name": "Iron Sword", "weight": Materials.sword_weight("iron"),
			"count": 1, "slot": "sword", "material": "iron"}

	## The wheel remembers its eight seats.
	var wsaved: Array = d.get("wheel", [])
	for i in range(mini(wsaved.size(), WHEEL_SLOTS)):
		wheel[i] = String(wsaved[i])

	## A SAVE FROM BEFORE 2026-08-30 can still have logs on its shoulder.
	## Shoulder-carrying is gone, so rather than dropping them on the floor of
	## whatever room you saved in, they come back as what they are now: items
	## in the pack. Nobody loses timber to a patch note.
	carried_logs.clear()
	var hauled: Array = d.get("carried_logs", [])
	for _l in hauled:
		_give_item_dict({"name": "Log", "weight": FallenTrunk.LOG_WEIGHT,
			"count": 1, "slot": "", "material": ""}, true)
	if not hauled.is_empty():
		_add_log_msg("The logs off your shoulder are in your pack now (%d)"
			% hauled.size(), Color(0.85, 0.78, 0.58))
	_refresh_log_rig()

	## Stance, steel, and the pools — derived caps first so the fill clamps right.
	current_weapon = String(d.get("weapon", "sword"))
	crouching = bool(d.get("crouching", false))
	sliding = false          ## never restore INTO a slide
	slide_t = 0.0
	vaulting = false
	prone = bool(d.get("prone", false))
	_refresh_derived(false)
	health = clampf(float(d.get("health", max_health)), 1.0, max_health)
	stamina = clampf(float(d.get("stamina", max_stamina)), 0.0, max_stamina)
	thirst = clampf(float(d.get("thirst", THIRST_MAX)), 0.0, THIRST_MAX)
	exposure.apply_dict(d)
	breath = clampf(float(d.get("breath", 100.0)), 0.0, 100.0)
	_ensure_waterskin()   ## [water] saves from before the skin existed
	sheathed = bool(d.get("sheathed", true))
	sheath_t = 1.0 if sheathed else 0.0
	attacking = false
	draw_attack = false
	blocking = false
	drawing = false
	bow_draw = 0.0
	climbing = false
	kd_phase = ""
	_body_up()
	hitstun_timer = 0.0
	invuln_timer = 0.6   ## a breath of grace on the way back in

	_apply_equipped_sword()
	_apply_armor_visuals()
	_refresh_inventory_ui()
	_add_log_msg("The world remembers where you left it", Color(0.8, 0.9, 1.0))

## ===================== Trees v2: limbing, pinning, rescue ===================
## docs/TREES_v2_SPEC.md §8. Added by tools/patch_repo.py — self-contained on
## purpose: nothing here needs a call from _process or _physics_process, so the
## main loops stay exactly as they were.

const PIN_STUCK_PROMPT := 10.0     ## seconds pinned before F offers a reload

## Set by _chop_tree so the axe animation can swing ALONG a limb instead of
## across it. Zero means "no limb in particular" — swing normally.
## TODO(anim): read this in the axe swing to rotate the arc onto the limb axis.
var axe_swing_axis := Vector3.ZERO

## Wedged-in-timber watchdog — see _unwedge.
var _unstick_t := 0.0
var _unstick_from := Vector3.ZERO

var pinned_by: Node3D = null
var pin_t := 0.0
var _pin_watch: Node
var _pin_label: Label


func armor_tier() -> int:
	## How much plate is between you and a falling tree. A trunk knocks an
	## armoured body down; it PINS an unarmoured one.
	## TODO(equipment): return the worn chest piece's material tier here — one
	## line once the equipment slot exposes its material id.
	return 0


func pin_under(what: Node3D, _seconds := 7.0) -> void:
	if pinned_by != null or god:
		return
	pinned_by = what
	pin_t = 0.0
	_start_knockdown(what.global_position if is_instance_valid(what) else global_position)
	kd_phase = "pinned"          ## stays down until the trunk moves off
	_add_log_msg("Pinned!", Color(0.85, 0.35, 0.25))

	## A tiny watcher node runs the timer, so Player's main loops are untouched.
	_pin_watch = Node.new()
	_pin_watch.set_script(preload("res://scripts/PinWatcher.gd"))
	_pin_watch.set("target", self)
	add_child(_pin_watch)


func release_pin() -> void:
	if pinned_by == null:
		return
	pinned_by = null
	pin_t = 0.0
	kd_phase = "rise"
	kd_t = 0.0
	_body_up()
	_hide_pin_prompt()
	if _pin_watch != null and is_instance_valid(_pin_watch):
		_pin_watch.queue_free()
		_pin_watch = null


func pin_tick(delta: float) -> void:
	## Called by PinWatcher.
	if pinned_by == null or not is_instance_valid(pinned_by):
		release_pin()
		return
	pin_t += delta
	if pin_t >= PIN_STUCK_PROMPT:
		_show_pin_prompt()


func _show_pin_prompt() -> void:
	if _pin_label != null:
		return
	_pin_label = Label.new()
	_pin_label.text = "[F]  reload last save"
	_pin_label.add_theme_font_size_override("font_size", 19)
	_pin_label.modulate = Color(0.88, 0.84, 0.72, 0.92)
	_pin_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_pin_label.offset_top = -140.0
	_pin_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if hud_layer != null:
		hud_layer.add_child(_pin_label)


func _hide_pin_prompt() -> void:
	if _pin_label != null and is_instance_valid(_pin_label):
		_pin_label.queue_free()
	_pin_label = null


func _pin_reload() -> void:
	if pin_t < PIN_STUCK_PROMPT:
		return               ## no bailing out of the first ten seconds
	_hide_pin_prompt()
	SaveGame.load_game(self)


func _swat_bugs(forward: Vector3, reach: float) -> void:
	## --- swat2 ---
	## A swing kills blackflies. Two clears a cloud — the sweep takes the
	## nearest 60% of it, so the first swing leaves 40% and the second
	## finishes them. It still does not SOLVE blackflies: they come back on
	## their own clocks and smoke is the real answer. It is just enormously
	## satisfying, which is the whole point.
	##
	## Fired from the damage frame of each weapon, not the button press, so the
	## flies die where the blade actually is. All of the geometry lives in
	## CritterSwarm.swat_from() — it used to live here, where no test could
	## reach it, and a swing killed six flies out of sixty for a week.
	var n := CritterSwarm.swat_from(self, forward, reach)
	if n <= 0:
		return
	cam_shake = maxf(cam_shake, 0.02)
	_add_log_msg("Swatted %d." % n, Color(0.72, 0.70, 0.62))


func _flat_forward() -> Vector3:
	## --- swat ---
	var f := -camera.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else -transform.basis.z


## ========================== GOD FLIGHT (F1 mode) ===========================

func _god_fly(delta: float) -> void:
	## Minecraft rules. You hang where you let go. WASD is FLAT (2026-09-12):
	## it slides you across the world plane the way you are facing and a
	## nose-down look never dives you into the dirt. SHIFT climbs, CTRL drops,
	## SPACE toggles the boost (sticky, see _input), and the scroll wheel's
	## god_speed multiplies the lot. GOD MODE ONLY -- ordinary walking keeps
	## Shift to sprint, Space to jump and Ctrl to dash. Collision is parked for
	## the duration and restored the instant flight ends.
	if _god_mask_saved < 0:
		_god_mask_saved = collision_mask
		collision_mask = 0
	var typing := godmode != null and godmode.typing
	var iv := Vector3.ZERO
	if not typing:
		if Input.is_key_pressed(KEY_W): iv.z -= 1.0
		if Input.is_key_pressed(KEY_S): iv.z += 1.0
		if Input.is_key_pressed(KEY_A): iv.x -= 1.0
		if Input.is_key_pressed(KEY_D): iv.x += 1.0
		iv += _pad_move()   ## CONTROLLER: the left stick flies too
	## FLAT: take the head's RIGHT (horizontal whatever the pitch), rebuild
	## forward from it, and throw the nose away.
	var rgt := head.global_transform.basis.x
	rgt.y = 0.0
	if rgt.length_squared() < 0.000001:
		rgt = transform.basis.x
		rgt.y = 0.0
	rgt = rgt.normalized() if rgt.length_squared() > 0.000001 else Vector3.RIGHT
	var fwd := Vector3.UP.cross(rgt)
	var dir := rgt * iv.x + fwd * -iv.z
	dir.y = 0.0
	if not typing:
		if Input.is_key_pressed(KEY_SHIFT):
			dir.y += 1.0
		if Input.is_key_pressed(KEY_CTRL):
			dir.y -= 1.0
	if dir.length_squared() > 0.000001:
		dir = dir.normalized()
	else:
		dir = Vector3.ZERO
	var spd := GOD_FLY_SPEED * god_speed
	if god_boost:
		spd *= GOD_FLY_BOOST
	## Snappy but not instant -- a 60 m/s stop on one key-up reads as a bug.
	velocity = velocity.move_toward(dir * spd, maxf(60.0, spd * 6.0) * delta)
	move_and_slide()
	## Keep the streamer looking at us so there is ground under the landing.
	crouching = false
	prone = false
	sprinting = false
	_frame_fx_and_regen(delta)
	_update_body_arms(delta)
	_update_hud(delta)
	_update_log(delta)


func god_teleport(to: Vector3) -> void:
	## Used by the editor's teleport buttons: build the near ring FIRST so the
	## body does not fall through a tile that has not arrived yet.
	if Overworld.inst != null:
		Overworld.inst.warm(to)
	global_position = to
	velocity = Vector3.ZERO


func fall_grace() -> void:
	## "Whatever happens on the way down is free." Armed by the F2 drop-in: the
	## next touchdown costs no health, cannot kill you and cannot fold your legs
	## -- and that is the whole of it. The landing after that is a normal one.
	_fall_grace = true
	_fall_grace_hold = 0.35
	_fall_speed = 0.0


func set_editing(on: bool) -> void:
	## STEP OUT OF THE BODY, and step back in. The one place `editing`,
	## EditorMode.active and the parked collision layer are allowed to change,
	## so the flag and the body can never disagree.
	if editing == on:
		return
	editing = on
	god = editing or god_sticky
	EditorMode.active = editing
	if on:
		flying = false
		jump_queued = false
		drawing = false
		attacking = false
		blocking = false
		## Third person while you are out, so you can SEE the body you left --
		## and so the first-person hands are not hanging in the air where your
		## head used to be. cam_mode is set directly, not through
		## _set_cam_mode, because this is temporary and must not be saved as
		## your camera preference.
		_editor_cam_mode = cam_mode
		cam_mode = "tp"
		cam_snap = 1.0
		sheathed = true
		if _god_layer_saved < 0:
			_god_layer_saved = collision_layer
		## THE UNTOUCHABLE HALF: with no layer, nothing's sensor, ray, hitbox
		## or falling trunk can find the body at all. EditorMode covers the
		## half that finds you by group instead.
		collision_layer = 0
	else:
		if _editor_cam_mode != "":
			cam_mode = _editor_cam_mode
			_editor_cam_mode = ""
		cam_snap = 1.0
		if _god_layer_saved >= 0:
			collision_layer = _god_layer_saved
			_god_layer_saved = -1
		velocity = Vector3.ZERO
		if camera != null:
			camera.current = true
		_update_head_offset()


func _editor_freeze(delta: float) -> void:
	## The parked body. It keeps its weight -- step out mid-jump and it lands
	## and stands there -- but it has no will: no input, no gait, no attack,
	## no interaction. Everything that only DRAWS still runs, so the character
	## you are looking at from the camera breathes and holds its gear properly.
	if not is_on_floor():
		velocity.y -= gravity * delta
	velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)
	move_and_slide()
	_frame_fx_and_regen(delta)
	_update_camera_arm(delta)
	_update_body_arms(delta)
	_update_tp_gear(delta)
	_update_hud(delta)
	_update_log(delta)
