class_name Monster
extends Enemy
## ===========================================================================
## MONSTER — one generated species, standing in the world.
##
## `genome` (MonsterGen.roll_species) is the whole animal: the body plan the
## rig is built from, the colours and tile the CreatureSkin bakes, the stats
## Enemy fights with, the special it telegraphs and the abilities it carries.
## Nothing about a Monster is authored by hand: two Monsters with the same
## genome are the same species, box for box.
##
## The body is the same Node3D-pivot + BoxMesh rig every other creature uses
## (Enemy._box_in), so CreatureSkin bakes it into one PSX skin with a
## skeleton, a ragdoll, a shove rule and the hit flash — for free. The
## walk cycle is Enemy._update_locomotion driving `walk_legs` (ordered here
## for a trot, a tripod skitter or a two-legged stride), and `_animate`
## poses the rest: the head that bites, the arm that swings, the segments
## that wave, the tail that lashes.
##
## Fighting is Enemy's: melee loop, strong attack with a telegraph glow,
## duelist pacing, nerve. `configure()` maps the genome's `special` onto the
## strong_* knobs and `_on_hit_landed` (Enemy's hook) puts the touch on you
## through Afflictions.gd, the way the slimes do.
## ===========================================================================

var genome: Dictionary = {}
var species_id := ""

## rig pivots
var rig: Node3D
var spine: Node3D
var head_pivot: Node3D
var arm: Node3D            ## bipeds: the weapon / claw arm (right)
var tail_pivot: Node3D
var segs: Array[Node3D] = []   ## serpents: the chain, head end first

## eased pose state (written absolutely each frame — see the NPC trap:
## lerping off a node that locomotion rewrites never arrives)
var _p_rig_y := 0.0
var _p_rig_rot := Vector3.ZERO
var _p_head := Vector3.ZERO
var _p_arm := Vector3.ZERO
var _p_tail := 0.0
var _base_dmg := 0.0
var _since_hit := 99.0
var _howled := false
var _eye_col := Color(0.05, 0.03, 0.03)

const TOUCH := {
	"burn": [4.0, 3.0], "poison": [8.0, 1.4], "chill": [3.0, 0.80], "tar": [4.0, 0.50],
}
const REGEN_AFTER := 4.0       ## s without a hit before it knits
const REGEN_RATE := 0.025      ## fraction of max per second
const HOWL_R := 26.0


static func from(g: Dictionary) -> Monster:
	var m := Monster.new()
	m.configure(g)
	return m


func _init() -> void:
	display_name = "Monster"
	monster = true
	aggro_radius = 12.0
	leash_radius = 28.0
	families = ["beast"]


func configure(g: Dictionary) -> void:
	## Stats before the body: call this BEFORE add_child (Enemy._ready reads
	## max_health and builds the body).
	genome = g.duplicate(true)
	if not genome.has("abilities"):
		genome["abilities"] = []
	species_id = str(genome.get("id", ""))
	display_name = str(genome.get("name", "Monster"))
	max_health = float(genome.get("hp", 50.0))
	health = max_health
	attack_damage = float(genome.get("dmg", 8.0))
	_base_dmg = attack_damage
	chase_speed = float(genome.get("speed", 4.5))
	wander_speed = clampf(chase_speed * 0.32, 0.8, 2.2)
	mass = float(genome.get("mass", 60.0))
	nerve = float(genome.get("nerve", 0.2))
	xp_tier = int(genome.get("xp_tier", 0))
	orb_tier = int(genome.get("orb_tier", 0))
	families = (genome.get("families", ["beast"]) as Array).duplicate()
	skin_tile = str(genome.get("tile", "hide"))
	duelist = bool(genome.get("duelist", false))
	can_climb = bool(genome.get("climber", false))
	var s := float(genome.get("size", 1.0))
	attack_range = clampf(1.5 * sqrt(s), 1.3, 3.2)
	attack_cooldown = clampf(1.25 - 0.15 * float(genome.get("tier", 0)) + (s - 1.0) * 0.25, 0.55, 1.8)
	climb_speed = clampf(3.4 / sqrt(s), 1.6, 3.6)
	gait_rate = clampf(1.15 / sqrt(s), 0.6, 1.6)
	telegraph_color = genome.get("accent", Color(0.95, 0.2, 0.1))
	_eye_col = genome.get("eye_col", Color(0.9, 0.8, 0.2))
	rout_line = "breaks and bolts"
	if abilities().has("armored"):
		armored = true
	_configure_special()


func abilities() -> Array:
	return genome.get("abilities", []) as Array


func has_ability(a: String) -> bool:
	return abilities().has(a)


func _configure_special() -> void:
	var sp := str(genome.get("special", ""))
	var d := attack_damage
	match sp:
		"lunge":
			strong_mode = "lunge"
			strong_damage = d * 1.8
			strong_speed = 9.5
			strong_windup_time = 0.45
			strong_duration = 0.42
			strong_cooldown = 4.5
			strong_min_range = 2.6
			strong_max_range = 6.5
			strong_hit_range = attack_range + 0.2
			strong_breaks_guard = true
			strong_from_melee = false
			strong_throws = false
		"charge":
			strong_mode = "charge"
			strong_damage = d * 1.5
			strong_speed = 11.0
			strong_windup_time = 0.55
			strong_duration = 0.9
			strong_cooldown = 5.0
			strong_min_range = 3.5
			strong_max_range = 10.0
			strong_hit_range = attack_range + 0.3
			strong_breaks_guard = true
			strong_from_melee = false
			strong_throws = true
			strong_throw_mode = "side"
			strong_throw_power = 6.0 + float(genome.get("size", 1.0)) * 1.5
			always_moving = true
		"slam":
			strong_mode = "slam"
			strong_damage = d * 2.2
			strong_speed = 1.5
			strong_windup_time = 0.65
			strong_duration = 0.45
			strong_cooldown = 6.0
			strong_min_range = 0.0
			strong_max_range = attack_range + 0.8
			strong_hit_range = attack_range + 0.4
			strong_breaks_guard = true
			strong_from_melee = true
			strong_throws = true
			strong_throw_mode = "away"
			strong_throw_power = 7.0 + float(genome.get("size", 1.0)) * 2.0
		"flurry":
			strong_mode = "flurry"
			strong_damage = d * 0.6
			strong_speed = 1.5
			strong_windup_time = 0.3
			strong_duration = 0.75
			strong_cooldown = 5.0
			strong_min_range = 0.0
			strong_max_range = attack_range + 0.5
			strong_hit_range = attack_range + 0.2
			strong_breaks_guard = false
			strong_from_melee = true
			strong_multi_hits = 3
			strong_hit_interval = 0.22
			strong_throws = false
		_:
			strong_mode = ""
			strong_max_range = -1.0   ## no special at all
			strong_from_melee = false


## ============================================================ the body ====

func _part(parent: Node, size: Vector3, col: Color, pos: Vector3, rot := Vector3.ZERO, tile := "", metal := false) -> MeshInstance3D:
	var m := _box_in(parent, size, col, pos, rot, metal)
	if tile != "":
		m.set_meta("psx_tile", tile)
	return m


func _build_body() -> void:
	if genome.is_empty():
		super()
		return
	rig = Node3D.new()
	rig.name = "Rig"
	add_child(rig)
	loco_root = rig
	match str(genome.get("plan", "quadruped")):
		"biped":
			_build_biped()
		"hexapod":
			_build_hexapod()
		"serpent":
			_build_serpent()
		_:
			_build_quadruped()
	## Enemy tints the eyes red when agitated; calm eyes get the species colour.
	_recolour_eyes(false)


func _col() -> Color:
	return genome.get("col", Color(0.4, 0.35, 0.3))


func _acc() -> Color:
	return genome.get("accent", Color(0.7, 0.6, 0.4))


func _build_quadruped() -> void:
	var s := float(genome["size"])
	var b := float(genome["bulk"])
	var L := float(genome["leg_len"])
	var h := 0.55 * s * L                 ## hip height (foot sole on y = 0)
	var len := 1.1 * s
	var col := _col()
	_add_collision(Vector3(0.5 * s * b, h + 0.5 * s, len), Vector3(0, (h + 0.5 * s) * 0.5, 0))
	base_body_color = col
	stride_deg = 30.0
	bob_h = 0.05 * s
	var torso := _part(rig, Vector3(0.44 * s * b, 0.42 * s, len * 0.8), col, Vector3(0, h + 0.18 * s, 0))
	body_mat = torso.material_override as StandardMaterial3D
	_part(rig, Vector3(0.46 * s * b, 0.40 * s, 0.32 * s), col, Vector3(0, h + 0.22 * s, -len * 0.38))
	_part(rig, Vector3(0.42 * s * b, 0.36 * s, 0.30 * s), col.darkened(0.08), Vector3(0, h + 0.15 * s, len * 0.36))
	## Legs — registered FL, FR, BR, BL so Enemy's even/odd phase makes a trot
	## (diagonal pairs together).
	for leg in [[-1.0, -len * 0.36], [1.0, -len * 0.36], [1.0, len * 0.34], [-1.0, len * 0.34]]:
		var hip := Node3D.new()
		rig.add_child(hip)
		hip.position = Vector3(float(leg[0]) * 0.17 * s * b, h, float(leg[1]))
		_part(hip, Vector3(0.14 * s, h * 0.55, 0.16 * s), col, Vector3(0, -h * 0.275, 0))
		_part(hip, Vector3(0.11 * s, h * 0.5, 0.12 * s), col.darkened(0.1), Vector3(0, -h * 0.75, 0.02 * s))
		_part(hip, Vector3(0.13 * s, 0.08 * s, 0.18 * s), col.darkened(0.3), Vector3(0, -h + 0.04 * s, -0.03 * s))
		walk_legs.append(hip)
	## Head on a neck at the front.
	var neck := float(genome.get("neck", 0.2))
	head_pivot = Node3D.new()
	head_pivot.name = "Head"
	rig.add_child(head_pivot)
	head_pivot.position = Vector3(0, h + 0.28 * s + neck * 0.25 * s, -len * 0.5 - neck * 0.25 * s)
	if neck > 0.15:
		_part(rig, Vector3(0.22 * s, 0.22 * s, (0.2 + neck * 0.3) * s), col, Vector3(0, h + 0.25 * s + neck * 0.1 * s, -len * 0.45 - neck * 0.12 * s), Vector3(20.0 * neck, 0, 0))
	_build_head(head_pivot, s * float(genome.get("head_size", 1.0)))
	_build_back(rig, Vector3(0, h + 0.39 * s, 0), len * 0.7, s)
	_build_tail(rig, Vector3(0, h + 0.2 * s, len * 0.5), s)


func _build_biped() -> void:
	var s := float(genome["size"])
	var b := float(genome["bulk"])
	var L := float(genome["leg_len"])
	var h := 0.7 * s * L                  ## hip height
	var col := _col()
	_add_collision(Vector3(0.5 * s * b, h + 0.85 * s, 0.45 * s), Vector3(0, (h + 0.85 * s) * 0.5, 0))
	base_body_color = col
	stride_deg = 28.0
	bob_h = 0.05 * s
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		rig.add_child(hip)
		hip.position = Vector3(side * 0.11 * s * b, h, 0)
		_part(hip, Vector3(0.14 * s * b, h * 0.5, 0.15 * s), col.darkened(0.05), Vector3(0, -h * 0.25, 0))
		_part(hip, Vector3(0.12 * s, h * 0.5, 0.13 * s), col.darkened(0.12), Vector3(0, -h * 0.75, 0))
		_part(hip, Vector3(0.14 * s, 0.08 * s, 0.24 * s), col.darkened(0.3), Vector3(0, -h + 0.04 * s, -0.04 * s))
		walk_legs.append(hip)
	_part(rig, Vector3(0.34 * s * b, 0.16 * s, 0.22 * s), col.darkened(0.08), Vector3(0, h + 0.02 * s, 0))
	spine = Node3D.new()
	spine.name = "Spine"
	rig.add_child(spine)
	spine.position = Vector3(0, h + 0.1 * s, 0)
	var torso := _part(spine, Vector3(0.40 * s * b, 0.50 * s, 0.26 * s * b), col, Vector3(0, 0.25 * s, 0))
	body_mat = torso.material_override as StandardMaterial3D
	## Arms: the left hangs loose and pumps with the stride; the right is the
	## weapon arm, posed by _animate.
	for side in [-1.0, 1.0]:
		var sh := Node3D.new()
		spine.add_child(sh)
		sh.position = Vector3(side * 0.24 * s * b, 0.44 * s, 0)
		_part(sh, Vector3(0.10 * s, 0.36 * s, 0.10 * s), col, Vector3(0, -0.18 * s, 0))
		if side < 0.0:
			walk_arms.append(sh)
			_part(sh, Vector3(0.09 * s, 0.10 * s, 0.09 * s), col.darkened(0.15), Vector3(0, -0.40 * s, 0))
		else:
			arm = sh
			_build_arm_tool(sh, s)
	head_pivot = Node3D.new()
	head_pivot.name = "Head"
	spine.add_child(head_pivot)
	head_pivot.position = Vector3(0, 0.55 * s, 0)
	_build_head(head_pivot, s * float(genome.get("head_size", 1.0)), Vector3(0, 0.14 * s, 0))
	_build_back(spine, Vector3(0, 0.30 * s, 0.14 * s * b), 0.4 * s, s, true)
	_build_tail(rig, Vector3(0, h + 0.04 * s, 0.12 * s), s)


func _build_arm_tool(sh: Node3D, s: float) -> void:
	var col := _col()
	match str(genome.get("arms", "none")):
		"claws":
			for i in range(3):
				_part(sh, Vector3(0.03 * s, 0.03 * s, 0.16 * s), _acc(), Vector3((float(i) - 1.0) * 0.035 * s, -0.40 * s, -0.08 * s), Vector3(-15, 0, 0), "bone")
		"club":
			var wood := Color(0.36, 0.25, 0.14)
			_part(sh, Vector3(0.08 * s, 0.08 * s, 0.46 * s), wood, Vector3(0.02 * s, -0.37 * s, -0.16 * s), Vector3(12, 0, 0), "wood")
			_part(sh, Vector3(0.13 * s, 0.13 * s, 0.17 * s), wood.darkened(0.1), Vector3(0.02 * s, -0.34 * s, -0.38 * s), Vector3.ZERO, "wood")
		"blade":
			var iron := Color(0.55, 0.56, 0.6)
			_part(sh, Vector3(0.05 * s, 0.05 * s, 0.14 * s), Color(0.3, 0.2, 0.12), Vector3(0.02 * s, -0.38 * s, -0.08 * s), Vector3.ZERO, "wood")
			_part(sh, Vector3(0.035 * s, 0.09 * s, 0.62 * s), iron, Vector3(0.02 * s, -0.38 * s, -0.45 * s), Vector3.ZERO, "metal", true)
		_:
			_part(sh, Vector3(0.09 * s, 0.10 * s, 0.09 * s), col.darkened(0.15), Vector3(0, -0.40 * s, 0))


func _build_hexapod() -> void:
	var s := float(genome["size"])
	var b := float(genome["bulk"])
	var L := float(genome["leg_len"])
	var h := 0.32 * s * L
	var col := _col()
	_add_collision(Vector3(0.7 * s * b, h + 0.3 * s, 1.0 * s), Vector3(0, (h + 0.3 * s) * 0.5, 0))
	base_body_color = col
	stride_deg = 38.0
	bob_h = 0.02 * s
	var body := _part(rig, Vector3(0.5 * s * b, 0.26 * s, 1.0 * s), col, Vector3(0, h + 0.08 * s, 0))
	body_mat = body.material_override as StandardMaterial3D
	_part(rig, Vector3(0.42 * s * b, 0.22 * s, 0.4 * s), col.darkened(0.1), Vector3(0, h + 0.06 * s, 0.45 * s))
	## Six legs, splayed. Registered FL, FR, MR, ML, BL, BR: even = one tripod,
	## odd = the other, so the walk is the alternating-tripod skitter.
	for leg in [[-1.0, -0.32], [1.0, -0.32], [1.0, 0.0], [-1.0, 0.0], [-1.0, 0.32], [1.0, 0.32]]:
		var side := float(leg[0])
		var hip := Node3D.new()
		rig.add_child(hip)
		hip.position = Vector3(side * 0.26 * s * b, h + 0.05 * s, float(leg[1]) * s)
		hip.rotation_degrees = Vector3(0, 0, side * 55.0)   ## points out and up
		_part(hip, Vector3(0.07 * s, 0.34 * s, 0.07 * s), col.darkened(0.05), Vector3(0, 0.17 * s, 0))
		var knee := Node3D.new()
		hip.add_child(knee)
		knee.position = Vector3(0, 0.34 * s, 0)
		knee.rotation_degrees = Vector3(0, 0, -side * 125.0)   ## and back down to the ground
		_part(knee, Vector3(0.055 * s, 0.42 * s, 0.055 * s), col.darkened(0.15), Vector3(0, 0.21 * s, 0))
		walk_legs.append(hip)
	head_pivot = Node3D.new()
	head_pivot.name = "Head"
	rig.add_child(head_pivot)
	head_pivot.position = Vector3(0, h + 0.1 * s, -0.55 * s)
	_build_head(head_pivot, s * 0.85 * float(genome.get("head_size", 1.0)))
	_build_back(rig, Vector3(0, h + 0.21 * s, 0), 0.8 * s, s)
	_build_tail(rig, Vector3(0, h + 0.06 * s, 0.6 * s), s)


func _build_serpent() -> void:
	var s := float(genome["size"])
	var b := float(genome["bulk"])
	var n := maxi(int(genome.get("segments", 6)), 3)
	var rad := 0.16 * s * b
	var col := _col()
	_add_collision(Vector3(0.5 * s, rad * 2.0 + 0.1, 1.2 * s), Vector3(0, rad + 0.05, 0.25 * s))
	base_body_color = col
	bob_h = 0.01
	var seg_len := 0.45 * s
	var parent: Node3D = rig
	var at := Vector3(0, rad, -0.1 * s)
	for i in range(n):
		var seg := Node3D.new()
		seg.name = "Seg%d" % i
		parent.add_child(seg)
		seg.position = at
		var taper := 1.0 - float(i) / float(n) * 0.55
		var box := _part(seg, Vector3(rad * 2.0 * taper, rad * 2.0 * taper, seg_len * 1.05), col if i % 2 == 0 else col.darkened(0.08), Vector3(0, 0, seg_len * 0.5))
		if i == 0:
			body_mat = box.material_override as StandardMaterial3D
		segs.append(seg)
		parent = seg
		at = Vector3(0, 0, seg_len)
	## The head hangs off the first segment, facing forward (-z).
	head_pivot = Node3D.new()
	head_pivot.name = "Head"
	segs[0].add_child(head_pivot)
	head_pivot.position = Vector3(0, rad * 0.4, -0.12 * s)
	_build_head(head_pivot, s * 0.9 * float(genome.get("head_size", 1.0)))
	_build_back(segs[0], Vector3(0, rad, seg_len * 0.5), seg_len, s)
	## no legs: the wave in _animate is the walk


func _build_head(pivot: Node3D, hs: float, at := Vector3.ZERO) -> void:
	var col := _col()
	var acc := _acc()
	var kind := str(genome.get("head", "blunt"))
	var tile := ""
	var base := Vector3(0.28, 0.26, 0.28) * hs
	if kind == "skull":
		col = Color(0.82, 0.78, 0.68)
		tile = "bone"
	elif kind == "maw":
		base = Vector3(0.34, 0.24, 0.30) * hs
	elif kind == "eyeless":
		base = Vector3(0.24, 0.22, 0.36) * hs
	_part(pivot, base, col, at, Vector3.ZERO, tile)
	var front := at + Vector3(0, 0, -base.z * 0.5)
	match kind:
		"snout":
			_part(pivot, Vector3(0.16, 0.14, 0.24) * hs, col, front + Vector3(0, -0.04 * hs, -0.10 * hs))
			_part(pivot, Vector3(0.05, 0.04, 0.05) * hs, Color(0.08, 0.06, 0.06), front + Vector3(0, -0.02 * hs, -0.23 * hs), Vector3.ZERO, "flat")
		"skull":
			_part(pivot, Vector3(0.22, 0.06, 0.20) * hs, col.darkened(0.1), at + Vector3(0, -0.15 * hs, -0.05 * hs), Vector3.ZERO, "bone")
		"maw":
			_part(pivot, Vector3(0.32, 0.08, 0.26) * hs, col.darkened(0.15), at + Vector3(0, -0.17 * hs, -0.05 * hs))
			for i in range(4):
				_part(pivot, Vector3(0.03, 0.07, 0.03) * hs, Color(0.9, 0.88, 0.8), front + Vector3((float(i) - 1.5) * 0.07 * hs, -0.11 * hs, 0.01 * hs), Vector3.ZERO, "bone")
		"crest":
			_part(pivot, Vector3(0.04, 0.26, 0.30) * hs, acc, at + Vector3(0, 0.22 * hs, 0.02 * hs), Vector3(-15, 0, 0))
		_:
			pass
	## Horns: on top, spread and splayed.
	var horns := int(genome.get("horns", 0))
	for i in range(horns):
		var t := 0.0 if horns == 1 else (float(i) / float(horns - 1) - 0.5)
		_part(pivot, Vector3(0.05, 0.22, 0.05) * hs, acc, at + Vector3(t * 0.22 * hs, base.y * 0.5 + 0.08 * hs, -0.02 * hs), Vector3(-10, 0, -t * 50.0), "bone")
	## Eyes: on the front face, by count.
	var spots: Array = []
	match int(genome.get("eyes", 2)):
		0: spots = []
		1: spots = [Vector2(0, 0.05)]
		2: spots = [Vector2(-0.07, 0.04), Vector2(0.07, 0.04)]
		3: spots = [Vector2(-0.07, 0.03), Vector2(0.07, 0.03), Vector2(0, 0.10)]
		4: spots = [Vector2(-0.07, 0.03), Vector2(0.07, 0.03), Vector2(-0.04, 0.10), Vector2(0.04, 0.10)]
		_: spots = [Vector2(-0.07, 0.03), Vector2(0.07, 0.03), Vector2(-0.04, 0.10), Vector2(0.04, 0.10), Vector2(-0.11, 0.09), Vector2(0.11, 0.09)]
	var es := 0.05 * hs if kind != "maw" else 0.04 * hs
	for sp in spots:
		_add_eye(front + Vector3(float(sp.x) * hs, float(sp.y) * hs, 0.005), Vector3(es, es, es * 0.8), pivot)


func _build_back(parent: Node3D, top: Vector3, length: float, s: float, upright := false) -> void:
	## Plates: a row of armour along the spine. Spines: a ridge of thorns.
	var acc := _acc()
	if bool(genome.get("plates", false)):
		var tile := "stone" if str(genome.get("tile", "")) == "stone" else "chitin"
		for i in range(3):
			var t := (float(i) - 1.0) * length * 0.3
			var pos := top + (Vector3(0, t, 0) if upright else Vector3(0, 0, t))
			_part(parent, Vector3(0.30 * s, 0.05 * s, 0.24 * s) if not upright else Vector3(0.30 * s, 0.22 * s, 0.05 * s), acc.darkened(0.2), pos, Vector3.ZERO, tile)
	if bool(genome.get("spines", false)):
		for i in range(4):
			var t := (float(i) - 1.5) * length * 0.22
			var pos := top + (Vector3(0, t, 0) if upright else Vector3(0, 0.04 * s, t))
			_part(parent, Vector3(0.03 * s, 0.16 * s, 0.03 * s), acc, pos + (Vector3(0, 0, -0.05 * s) if upright else Vector3.ZERO), Vector3(-25 if upright else -12, 0, 0), "bone")


func _build_tail(parent: Node3D, at: Vector3, s: float) -> void:
	var kind := str(genome.get("tail", ""))
	if kind == "":
		return
	var col := _col()
	tail_pivot = Node3D.new()
	tail_pivot.name = "Tail"
	parent.add_child(tail_pivot)
	tail_pivot.position = at
	match kind:
		"whip":
			_part(tail_pivot, Vector3(0.10, 0.10, 0.45) * s, col, Vector3(0, 0, 0.22 * s))
			_part(tail_pivot, Vector3(0.06, 0.06, 0.40) * s, col.darkened(0.1), Vector3(0, 0.02 * s, 0.62 * s), Vector3(8, 0, 0))
		"club":
			_part(tail_pivot, Vector3(0.10, 0.10, 0.40) * s, col, Vector3(0, 0, 0.2 * s))
			_part(tail_pivot, Vector3(0.18, 0.18, 0.18) * s, _acc().darkened(0.2), Vector3(0, 0, 0.48 * s), Vector3.ZERO, "stone")
		"stinger":
			_part(tail_pivot, Vector3(0.09, 0.09, 0.40) * s, col, Vector3(0, 0.05 * s, 0.2 * s), Vector3(-25, 0, 0))
			_part(tail_pivot, Vector3(0.05, 0.05, 0.18) * s, _acc(), Vector3(0, 0.25 * s, 0.42 * s), Vector3(-60, 0, 0), "bone")


func _recolour_eyes(angry: bool) -> void:
	if angry:
		return
	for em in eye_mats:
		em.albedo_color = _eye_col
		em.emission_enabled = true
		em.emission = _eye_col
		em.emission_energy_multiplier = 0.6


func _set_agitated(on: bool) -> void:
	var was := state == State.AGITATED
	super(on)
	_recolour_eyes(on)
	if on and not was and has_ability("howl") and not _howled:
		_howled = true
		_howl()


func _howl() -> void:
	## The pack answers: every calm monster of this species within HOWL_R
	## wakes and comes. (Not on Peaceful — Enemy's own aggro rules still
	## decide who chases; this only wakes them.)
	if not is_inside_tree():
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or not (e is Monster):
			continue
		var m := e as Monster
		if m.species_id != species_id or m.dying or m.state == State.AGITATED:
			continue
		if m.global_position.distance_to(global_position) <= HOWL_R:
			m.confused = false
			m.provoked = provoked
			m._set_agitated(true)


## ============================================================ the brain ===

func _physics_process(delta: float) -> void:
	_since_hit += delta
	if not dying and has_ability("regen") and _since_hit > REGEN_AFTER and health < max_health:
		health = minf(max_health, health + max_health * REGEN_RATE * delta)
	if has_ability("frenzy"):
		attack_damage = _base_dmg * (1.5 if health < max_health * 0.5 else 1.0)
	super(delta)


func take_damage(amount: float, _from_pos = null, _strong = false, _throw = null, attacker: Node = null) -> void:
	if dying:
		return
	if has_ability("thick_hide"):
		amount *= 0.7
	_since_hit = 0.0
	## Thorns: a blade that lands on it pays a little back — only the player's
	## own blows (bare calls, or the player as attacker), never infighting.
	if has_ability("thorns") and (attacker == null or (attacker is Node and (attacker as Node).is_in_group("player"))):
		var pl := _get_player()
		if pl != null and pl.has_method("take_damage") and pl.global_position.distance_to(global_position) <= attack_range + 1.0:
			pl.take_damage(maxf(1.0, _base_dmg * 0.25), global_position, false, Vector3.INF, self)
	super(amount, _from_pos, _strong, _throw, attacker)


func _on_hit_landed(target: Node) -> void:
	## Enemy's hook, called after any melee or strong hit lands on `target`.
	## The touch: whichever affliction the species carries goes on the player.
	if target == null or not (target is Node) or not (target as Node).is_in_group("player"):
		return
	var tier := int(genome.get("tier", 0))
	for a in abilities():
		var k := str(a)
		if TOUCH.has(k):
			var t: Array = TOUCH[k]
			var kind := "gummed" if k == "tar" else k
			var secs := float(t[0]) * (1.0 + 0.15 * float(tier))
			var power := float(t[1])
			if k == "burn" or k == "poison":
				power *= 1.0 + 0.25 * float(tier)
			Afflictions.apply(target, kind, secs, power)
			if k == "chill":
				Afflictions.drain_warmth(target, 10.0 + 3.0 * float(tier))
		elif k == "shock":
			Afflictions.shock(target, 0.5, 22.0 + 4.0 * float(tier))


## ============================================================ animation ===

func _choose_strong(dist: float) -> void:
	## One special per species (configure set the knobs); the flurry and the
	## slam only fire from melee range, the rest only from a gap.
	pass


func _animate(delta: float) -> void:
	if rig == null:
		return
	var k := clampf(delta * 12.0, 0.0, 1.0)
	var plan := str(genome.get("plan", "quadruped"))
	## --- targets by what the body is doing
	var t_rig_y := loco_bob_y
	var t_rig_rot := Vector3.ZERO
	var t_head := Vector3.ZERO
	var t_arm := Vector3(sin(walk_t) * 8.0 * _loco_amount, 0, 0)
	var sp := str(genome.get("special", ""))
	if strong_windup > 0.0:
		var p := 1.0 - strong_windup / maxf(strong_windup_time, 0.01)
		match sp:
			"lunge":
				t_rig_y = loco_bob_y - 0.12 * p
				t_rig_rot = Vector3(12.0 * p, 0, 0)
				t_head = Vector3(-18.0 * p, 0, 0)
				t_arm = Vector3(-45.0 * p, 0, 0)
			"charge":
				t_rig_rot = Vector3(-8.0 * p, 0, 0)
				t_head = Vector3(-22.0 * p, 0, 0)
			"slam":
				t_rig_y = loco_bob_y + 0.10 * p
				t_rig_rot = Vector3(-14.0 * p, 0, 0)
				t_head = Vector3(-30.0 * p, 0, 0)
				t_arm = Vector3(-110.0 * p, 0, 0)
			"flurry":
				t_arm = Vector3(-80.0 * p, 0, 0)
	elif strong_active:
		var p := 1.0 - strong_time / maxf(strong_duration, 0.01)
		match sp:
			"lunge":
				t_rig_y = lerpf(-0.12, 0.08, minf(p * 2.0, 1.0))
				t_rig_rot = Vector3(lerpf(12.0, -10.0, p), 0, 0)
				t_head = Vector3(lerpf(-18.0, 22.0, minf(p * 1.6, 1.0)), 0, 0)
				t_arm = Vector3(lerpf(-45.0, 50.0, minf(p * 1.8, 1.0)), 0, 0)
			"charge":
				t_rig_rot = Vector3(-10.0, 0, 0)
				t_head = Vector3(-8.0, 0, 0)
			"slam":
				t_rig_y = lerpf(0.10, -0.06, minf(p * 1.5, 1.0))
				t_rig_rot = Vector3(lerpf(-14.0, 16.0, minf(p * 1.4, 1.0)), 0, 0)
				t_head = Vector3(lerpf(-30.0, 25.0, minf(p * 1.4, 1.0)), 0, 0)
				t_arm = Vector3(lerpf(-110.0, 40.0, minf(p * 1.4, 1.0)), 0, 0)
			"flurry":
				t_arm = Vector3(-25.0 + sin(p * TAU * 1.5) * -55.0, 0, 0)
				t_rig_rot = Vector3(6.0, sin(p * TAU * 1.5) * 8.0, 0)
	elif melee_anim > 0.0:
		## The plain bite / swipe: cocked, then through on the damage frame.
		var p := 1.0 - melee_anim / MELEE_ANIM_TIME
		var q := (p - 0.30) / 0.32 if p >= 0.30 else 0.0
		t_arm = Vector3(-75.0, 0, 0) if p < 0.30 else Vector3(lerpf(-75.0, 35.0, minf(q, 1.0)), 0, 0)
		t_head = Vector3(-20.0, 0, 0) if p < 0.30 else Vector3(lerpf(-20.0, 24.0, minf(q, 1.0)), 0, 0)
		t_rig_rot = Vector3(4.0 if p < 0.30 else 9.0, 0, 0)
	else:
		t_rig_rot = Vector3(0, 0, sin(walk_t) * 1.5 * _loco_amount)
	## --- ease and write absolutely
	_p_rig_y = lerpf(_p_rig_y, t_rig_y, k)
	_p_rig_rot = _p_rig_rot.lerp(t_rig_rot, k)
	_p_head = _p_head.lerp(t_head, k)
	_p_arm = _p_arm.lerp(t_arm, k)
	rig.position.y = _p_rig_y
	if plan != "serpent":
		rig.rotation_degrees = _p_rig_rot
	if head_pivot != null:
		head_pivot.rotation_degrees = _p_head
	if arm != null:
		arm.rotation_degrees = _p_arm
	if tail_pivot != null:
		_p_tail = lerpf(_p_tail, sin(_sway_t * 1.7 + walk_t * 0.5) * (14.0 + 16.0 * _loco_amount), k)
		tail_pivot.rotation_degrees = Vector3(0, _p_tail, 0)
	if plan == "serpent":
		_animate_serpent()


func _animate_serpent() -> void:
	## The chain waves: each segment yaws behind the one ahead, driven by the
	## gait phase, so the body writes an S on the ground as it goes.
	var amp := 0.32 * (0.35 + 0.65 * _loco_amount)
	var strike := 0.0
	if strong_active or melee_anim > 0.0:
		strike = -0.35
	for i in range(segs.size()):
		var seg := segs[i]
		seg.rotation.y = sin(walk_t * 1.2 - float(i) * 0.9 + _sway_t * 0.3) * amp * (0.4 if i == 0 else 1.0)
		seg.rotation.x = strike if i == 0 else 0.0
