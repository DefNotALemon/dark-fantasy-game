#!/usr/bin/env python3
"""patch_mobgen.py -- wire the monster generator + character creator into the repo.

Anchored, idempotent hunks (each checks its own marker before applying) on:
  scripts/Enemy.gd        the _on_hit_landed hook (2 call sites + the virtual)
  scripts/CreatureSkin.gd set_outline (the white selection rim)
  scripts/NPC.gd          `look` + the parameterised body + rebuild_body + save
  scripts/Player.gd       creator panel, menu "creator", click hand-off,
                          Settings -> Dev Toolkit button, M menu rows, Monster spawn
  scripts/World.gd        the MonsterDirector
  scripts/CaveRegion.gd   generated packs instead of the humanoid tables
  scripts/Warbands.gd     raiders instead of Goblins

Run from the repo root:  python3 tools/patch_mobgen.py [--check]
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHECK = "--check" in sys.argv
applied = []
skipped = []
failed = []


def read(p):
    with open(os.path.join(ROOT, p), encoding="utf-8") as f:
        return f.read()


def write(p, s):
    if CHECK:
        return
    with open(os.path.join(ROOT, p), "w", encoding="utf-8") as f:
        f.write(s)


def hunk(path, name, marker, anchor, replacement, count=1):
    """Replace `anchor` with `replacement` once, unless `marker` is already present."""
    s = read(path)
    if marker in s:
        skipped.append(f"{path}: {name}")
        return
    n = s.count(anchor)
    if n != count:
        failed.append(f"{path}: {name} -- anchor found {n}x (wanted {count})")
        return
    s = s.replace(anchor, replacement)
    write(path, s)
    applied.append(f"{path}: {name}")


def hunk_regex(path, name, marker, pattern, replacement):
    s = read(path)
    if marker in s:
        skipped.append(f"{path}: {name}")
        return
    new, n = re.subn(pattern, replacement, s, count=1, flags=re.S)
    if n != 1:
        failed.append(f"{path}: {name} -- pattern not found")
        return
    write(path, new)
    applied.append(f"{path}: {name}")


# =========================================================================== Enemy
hunk("scripts/Enemy.gd", "E1 melee hook", "_on_hit_landed(mp)",
     "\t\t\t\t\tmp.take_damage(attack_damage, global_position, false, Vector3.INF, self)\n",
     "\t\t\t\t\tmp.take_damage(attack_damage, global_position, false, Vector3.INF, self)\n"
     "\t\t\t\t\t_on_hit_landed(mp)\n")
hunk("scripts/Enemy.gd", "E2 strong hook", "_on_hit_landed(player)",
     "\t\t\t\tplayer.take_damage(strong_damage, global_position, strong_breaks_guard, throw, self)\n",
     "\t\t\t\tplayer.take_damage(strong_damage, global_position, strong_breaks_guard, throw, self)\n"
     "\t\t\t\t_on_hit_landed(player)\n")
hunk("scripts/Enemy.gd", "E3 virtual", "func _on_hit_landed(",
     "func _animate(_delta: float) -> void:\n\t## Virtual: subclasses pose their limbs here every frame.\n\tpass\n",
     "func _animate(_delta: float) -> void:\n\t## Virtual: subclasses pose their limbs here every frame.\n\tpass\n\n\n"
     "func _on_hit_landed(_target: Node) -> void:\n"
     "\t## Virtual: a melee or strong hit just landed on `_target` (the player,\n"
     "\t## or another creature). Generated monsters put their touch — burn,\n"
     "\t## poison, chill, shock, tar — on you here (scripts/Monster.gd).\n"
     "\tpass\n")

# ===================================================================== CreatureSkin
hunk("scripts/CreatureSkin.gd", "C1 outline vars", "OUTLINE_SHADER_PATH",
     "const SHADER_PATH := \"res://shaders/psx_skin.gdshader\"\n",
     "const SHADER_PATH := \"res://shaders/psx_skin.gdshader\"\n"
     "const OUTLINE_SHADER_PATH := \"res://shaders/psx_outline.gdshader\"   ## the creator's selection rim\n")
hunk("scripts/CreatureSkin.gd", "C2 outline node", "var _outline: MeshInstance3D",
     "static var _shader: Shader = null\n",
     "static var _shader: Shader = null\n"
     "static var _outline_shader: Shader = null\n"
     "var _outline: MeshInstance3D = null    ## the inverted-hull rim (set_outline)\n")
hunk("scripts/CreatureSkin.gd", "C3 set_outline", "func set_outline(",
     "func set_flash(amount: float) -> void:\n\tif mat:\n\t\tmat.set_shader_parameter(\"flash\", amount)\n",
     "func set_flash(amount: float) -> void:\n\tif mat:\n\t\tmat.set_shader_parameter(\"flash\", amount)\n\n\n"
     "func set_outline(on: bool, col := Color(1, 1, 1), width := 0.035) -> void:\n"
     "\t## The selection rim (Lemon, 2026-09-14: \"click on any character which\n"
     "\t## will outline them with white\"): the skin's own skinned mesh drawn a\n"
     "\t## second time as an inverted hull (shaders/psx_outline.gdshader), so it\n"
     "\t## follows every bone and skips every hidden segment. Built lazily, kept\n"
     "\t## hidden when off; the Character Creator is the only caller today.\n"
     "\tif skeleton == null or mesh_inst == null:\n"
     "\t\treturn\n"
     "\tif not on:\n"
     "\t\tif _outline != null and is_instance_valid(_outline):\n"
     "\t\t\t_outline.visible = false\n"
     "\t\treturn\n"
     "\tif _outline == null or not is_instance_valid(_outline):\n"
     "\t\tif _outline_shader == null:\n"
     "\t\t\t_outline_shader = load(OUTLINE_SHADER_PATH)\n"
     "\t\t_outline = MeshInstance3D.new()\n"
     "\t\t_outline.name = \"Outline\"\n"
     "\t\t_outline.mesh = mesh_inst.mesh\n"
     "\t\tskeleton.add_child(_outline)\n"
     "\t\t_outline.skeleton = _outline.get_path_to(skeleton)\n"
     "\t\t_outline.skin = mesh_inst.skin\n"
     "\t\t_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF\n"
     "\t\tvar om := ShaderMaterial.new()\n"
     "\t\tom.shader = _outline_shader\n"
     "\t\tom.set_shader_parameter(\"seg_tex\", _seg_tex)\n"
     "\t\t_outline.material_override = om\n"
     "\tvar m := _outline.material_override as ShaderMaterial\n"
     "\tif m != null:\n"
     "\t\tm.set_shader_parameter(\"colour\", col)\n"
     "\t\tm.set_shader_parameter(\"width\", width)\n"
     "\t_outline.visible = true\n\n\n"
     "func outline_on() -> bool:\n"
     "\treturn _outline != null and is_instance_valid(_outline) and _outline.visible\n")

# ============================================================================== NPC
hunk("scripts/NPC.gd", "N1 look var", "var look: Dictionary",
     "var dialogue: Dictionary = {}     ## an authored talk tree; empty = NPCDialogue.default_tree\n",
     "var dialogue: Dictionary = {}     ## an authored talk tree; empty = NPCDialogue.default_tree\n"
     "var look: Dictionary = {}         ## the Character Creator's knobs (default_look / random_look)\n")
hunk("scripts/NPC.gd", "N2 default look in _ready", "look = default_look(",
     "\tif anchor == Vector3.ZERO:\n\t\tanchor = global_position\n\tsuper()\n",
     "\tif anchor == Vector3.ZERO:\n\t\tanchor = global_position\n"
     "\tif look.is_empty():\n\t\tlook = default_look(npc_name, sex, job)\n"
     "\tsuper()\n")

NEW_BODY = r'''func _build_body() -> void:
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


'''

hunk_regex("scripts/NPC.gd", "N3 parameterised body", "func rebuild_body()",
           r"func _build_body\(\) -> void:\n.*?(?=func _skin_opts\(\) -> Dictionary:)",
           NEW_BODY.replace("\\", "\\\\"))
hunk("scripts/NPC.gd", "N4 to_dict look", "\"look\": look_to_json(look)",
     "\t\t\"home_kind\": home_kind, \"schedule\": schedule.duplicate(true), \"health\": health, \"dead\": dying,\n",
     "\t\t\"home_kind\": home_kind, \"schedule\": schedule.duplicate(true), \"health\": health, \"dead\": dying,\n"
     "\t\t\"look\": look_to_json(look),\n")
hunk("scripts/NPC.gd", "N5 apply_dict look", "look = look_from_json(",
     "\tif d.has(\"health\"):\n\t\thealth = clampf(float(d[\"health\"]), 1.0, max_health)\n",
     "\tvar lk = d.get(\"look\", null)\n"
     "\tif lk is Dictionary and not (lk as Dictionary).is_empty():\n"
     "\t\tlook = look_from_json(lk)\n"
     "\tif d.has(\"health\"):\n\t\thealth = clampf(float(d[\"health\"]), 1.0, max_health)\n")

# ============================================================================ Player
hunk("scripts/Player.gd", "P1 creator var", "var creator: CharacterCreator",
     "var grass_lab: GrassLab = null   ## F3 -- the grass lab (scripts/GrassLab.gd)\n",
     "var grass_lab: GrassLab = null   ## F3 -- the grass lab (scripts/GrassLab.gd)\n"
     "var creator: CharacterCreator = null  ## Settings -> Dev Toolkit (scripts/CharacterCreator.gd)\n")
hunk("scripts/Player.gd", "P2 creator build", "creator = CharacterCreator.new()",
     "\tgrass_lab = GrassLab.new()\n\thud_layer.add_child(grass_lab)\n",
     "\tgrass_lab = GrassLab.new()\n\thud_layer.add_child(grass_lab)\n"
     "\t## The character creator / dev toolkit (scripts/CharacterCreator.gd):\n"
     "\t## Settings -> Dev Toolkit -> Character Creator opens it as menu \"creator\".\n"
     "\tcreator = CharacterCreator.new()\n"
     "\tcreator.player = self\n"
     "\thud_layer.add_child(creator)\n")
hunk("scripts/Player.gd", "P3 panel table", "creator.visible = which == \"creator\"",
     "\tif grass_lab:\n\t\tgrass_lab.visible = which == \"grass\"\n",
     "\tif grass_lab:\n\t\tgrass_lab.visible = which == \"grass\"\n"
     "\tif creator:\n\t\tcreator.visible = which == \"creator\"\n")
hunk("scripts/Player.gd", "P4 dev toolkit row", "tk_btn.text = \"Character Creator\"",
     "\t_settings_step_row(vb, \"Mouse Sensitivity\", \"sens\")\n",
     "\t## THE DEV TOOLKIT (Lemon, 2026-09-14): the character creator is a full\n"
     "\t## screen of its own, and it carries this whole menu inside it as a tab.\n"
     "\tvb.add_child(HSeparator.new())\n"
     "\tvar tk_row := HBoxContainer.new()\n"
     "\ttk_row.add_theme_constant_override(\"separation\", 8)\n"
     "\tvb.add_child(tk_row)\n"
     "\tvar tk_lbl := Label.new()\n"
     "\ttk_lbl.text = \"Dev Toolkit\"\n"
     "\ttk_lbl.custom_minimum_size = Vector2(190, 0)\n"
     "\ttk_lbl.add_theme_font_size_override(\"font_size\", 17)\n"
     "\ttk_row.add_child(tk_lbl)\n"
     "\tvar tk_btn := Button.new()\n"
     "\ttk_btn.text = \"Character Creator\"\n"
     "\ttk_btn.focus_mode = Control.FOCUS_NONE\n"
     "\ttk_btn.custom_minimum_size = Vector2(160, 0)\n"
     "\ttk_btn.pressed.connect(func() -> void: _toggle_menu(\"creator\"))\n"
     "\ttk_row.add_child(tk_btn)\n"
     "\tvar tk_note := Label.new()\n"
     "\ttk_note.text = \"People and monsters: click any character in the world to select it (white outline),\\nedit its body, face, clothes and mind live; roll, spawn and save generated species.\"\n"
     "\ttk_note.add_theme_font_size_override(\"font_size\", 13)\n"
     "\ttk_note.modulate = Color(1, 1, 1, 0.55)\n"
     "\tvb.add_child(tk_note)\n"
     "\tvb.add_child(HSeparator.new())\n"
     "\t_settings_step_row(vb, \"Mouse Sensitivity\", \"sens\")\n")
hunk("scripts/Player.gd", "P5 creator click", "creator.eat_input(event)",
     "\tif claude_chat != null and claude_chat.eat_input(event):\n\t\treturn\n",
     "\tif claude_chat != null and claude_chat.eat_input(event):\n\t\treturn\n"
     "\t## THE CREATOR owns a left click in the world while it is up: the click\n"
     "\t## selects the character under the cursor (scripts/CharacterCreator.gd).\n"
     "\tif creator != null and menu_open == \"creator\" and creator.eat_input(event):\n\t\treturn\n")
hunk("scripts/Player.gd", "P6 spawn rows", "[\"Monster (rolled for here)\", Monster]",
     "\t\t[\"Villager\", NPC],  ## a person (scripts/NPC.gd)\n"
     "\t\t[\"Boar\", Boar], [\"Kobold\", Kobold], [\"Goblin\", Goblin], [\"Skeleton\", Skeleton],\n"
     "\t\t[\"Orc\", Orc], [\"Ogre\", Ogre], [\"Dark Knight\", DarkKnight],\n"
     "\t\t[\"Horse (wild)\", Horse], [\"Horse (saddled)\", SaddledHorse],\n",
     "\t\t[\"Villager\", NPC],  ## a person (scripts/NPC.gd)\n"
     "\t\t## The hand-made humanoids (Kobold, Goblin, Skeleton, Orc, Ogre, Dark\n"
     "\t\t## Knight) no longer spawn (Lemon, 2026-09-14) -- the generator does.\n"
     "\t\t## Their scripts stay for the bestiary.\n"
     "\t\t[\"Monster (rolled for here)\", Monster],\n"
     "\t\t[\"Boar\", Boar],\n"
     "\t\t[\"Horse (wild)\", Horse], [\"Horse (saddled)\", SaddledHorse],\n")
hunk("scripts/Player.gd", "P7 monster spawn", "_spawn_generated_monster",
     "func _spawn_mob(mob_script: Variant) -> void:\n\tvar fwd := -transform.basis.z\n",
     "func _spawn_mob(mob_script: Variant) -> void:\n"
     "\tif mob_script == Monster:\n"
     "\t\t_spawn_generated_monster()\n"
     "\t\treturn\n"
     "\tvar fwd := -transform.basis.z\n")
hunk("scripts/Player.gd", "P8 generated spawn fn", "func _spawn_generated_monster()",
     "## ========================= The Item Wheel (Q) ==============================\n",
     "func _spawn_generated_monster() -> void:\n"
     "\t## One of the species MonsterGen rolls for THIS zone at THIS level\n"
     "\t## (scripts/MonsterGen.gd) -- the same roll the MonsterDirector makes.\n"
     "\tvar fwd := -transform.basis.z\n"
     "\tfwd.y = 0.0\n"
     "\tfwd = fwd.normalized()\n"
     "\tvar pos := global_position + fwd * 3.0\n"
     "\tvar space := get_world_3d().direct_space_state\n"
     "\tvar q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 3.0, pos + Vector3.DOWN * 30.0)\n"
     "\tq.exclude = [get_rid()]\n"
     "\tvar hit: Dictionary = space.intersect_ray(q)\n"
     "\tif hit:\n"
     "\t\tpos = hit.position + Vector3.UP * 0.2\n"
     "\telse:\n"
     "\t\tpos.y = global_position.y + 0.5\n"
     "\tvar wseed := MonsterDirector.DEFAULT_SEED\n"
     "\tvar w := get_parent()\n"
     "\tif w != null and w.has_method(\"monsters\") and w.call(\"monsters\") != null:\n"
     "\t\twseed = int((w.call(\"monsters\") as MonsterDirector).world_seed)\n"
     "\tvar rng := RandomNumberGenerator.new()\n"
     "\trng.randomize()\n"
     "\tvar g := MonsterGen.for_spot(wseed, global_position, level, rng)\n"
     "\tif g.is_empty():\n"
     "\t\treturn\n"
     "\tvar m := Monster.from(g)\n"
     "\tm.confused = true\n"
     "\tget_parent().add_child(m)\n"
     "\tm.global_position = pos\n"
     "\t_add_log_msg(\"%s -- %s\" % [m.display_name, MonsterGen.describe(g)], Color(0.85, 0.80, 0.70))\n\n\n"
     "## ========================= The Item Wheel (Q) ==============================\n")

hunk("scripts/Player.gd", "P9 warmth note newlines", "an autumn night is a slow problem and a\\nwinter one is not, being soaked doubles it, and a roof, a torch and a lit fire\\nare the three answers",
     "wa_note.text = \"Survival: the cold is real -- an autumn night is a slow problem and a\\\\nwinter one is not, being soaked doubles it, and a roof, a torch and a lit fire\\\\nare the three answers. Light: no meter, and no cold. Switches live, any time.\"\n",
     "wa_note.text = \"Survival: the cold is real -- an autumn night is a slow problem and a\\nwinter one is not, being soaked doubles it, and a roof, a torch and a lit fire\\nare the three answers. Light: no meter, and no cold. Switches live, any time.\"\n")

# ============================================================================= World
hunk("scripts/World.gd", "W1 director var", "var _monsters: MonsterDirector",
     "var _slimes: SlimeDirector           ## [slimes] the jellies on the surface (scripts/SlimeDirector.gd)\n",
     "var _slimes: SlimeDirector           ## [slimes] the jellies on the surface (scripts/SlimeDirector.gd)\n"
     "var _monsters: MonsterDirector       ## [mobgen] generated monsters on the surface (scripts/MonsterDirector.gd)\n")
hunk("scripts/World.gd", "W2 director boot", "_monsters = MonsterDirector.new()",
     "\t_slimes = SlimeDirector.new()\n\t_slimes.name = \"SlimeDirector\"\n\tadd_child(_slimes)\n\t_slimes.bind_world(self)\n",
     "\t_slimes = SlimeDirector.new()\n\t_slimes.name = \"SlimeDirector\"\n\tadd_child(_slimes)\n\t_slimes.bind_world(self)\n"
     "\t## [mobgen] the generated monsters up top (scripts/MonsterDirector.gd):\n"
     "\t## one roster per zone, one newcomer per level tier.\n"
     "\t_monsters = MonsterDirector.new()\n"
     "\t_monsters.name = \"MonsterDirector\"\n"
     "\tadd_child(_monsters)\n"
     "\t_monsters.bind_world(self)\n")
hunk("scripts/World.gd", "W3 accessor", "func monsters() -> MonsterDirector",
     "func slimes() -> SlimeDirector:\n",
     "func monsters() -> MonsterDirector:\n\treturn _monsters\n\n\nfunc slimes() -> SlimeDirector:\n")

# ======================================================================== CaveRegion
CAVE_NEW = '''func _spawn_dwellers(reach: Array[Vector3i]) -> void:
	## Packs at reachable pockets; deeper = meaner; the deepest big pocket is
	## the champion's court. The dwellers are GENERATED (Lemon, 2026-09-14 --
	## scripts/MonsterGen.gd): this cave rolls its own bestiary, one roster
	## per depth band (MonsterGen.cave_key), at the player's level tier
	## pushed one up in the middle galleries and two in the deep. The slime
	## pockets stay as they were.
	## avoid_mouth = the NO-SPAWN BARRIER: nothing spawns near permanent caves.
	var pockets := _pick_spots(reach, 13, -30.0, -5.0, 17.0, CaveField.PERM_R + 2.0)
	if pockets.is_empty():
		return
	pockets.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y > b.y)
	for i in range(pockets.size()):
		var c := pockets[i]
		if i == pockets.size() - 1 and pockets.size() >= 2:
			## the champion: the deep band's meanest, alone, with a guard of the shallow kind
			_spawn_gen(c, _gen_pick(c.y, true), 1)
			_spawn_gen(c, _gen_pick(-6.0, false), _rng.randi_range(2, 3))
			continue
		var roll := _rng.randf()
		if c.y > -12.0:
			if roll < 0.72:
				_spawn_gen(c, _gen_pick(c.y, false), _rng.randi_range(3, 6))
			else:
				## [slimes] the shallow jellies: a green pocket, sometimes with
				## a jolt or two skittering among them
				_spawn_pack(c, SlimeGreen, _rng.randi_range(3, 5))
				if _rng.randf() < 0.5:
					_spawn_pack(c, SlimeYellow, _rng.randi_range(1, 2))
		elif c.y > -21.0:
			if roll < 0.85:
				_spawn_gen(c, _gen_pick(c.y, false), _rng.randi_range(2, 5))
			else:
				## [slimes] the venom creeps in the middle galleries
				_spawn_pack(c, SlimePurple, _rng.randi_range(2, 3))
		else:
			if roll < 0.85:
				_spawn_gen(c, _gen_pick(c.y, false), _rng.randi_range(2, 4))
			else:
				## [slimes] the deeps burn ember -- and one tar sits in the dark
				_spawn_pack(c, SlimeRed, _rng.randi_range(2, 4))
				if _rng.randf() < 0.5:
					_spawn_pack(c, SlimeBlack, 1)
	## THE DEEP IS FULLER: an extra belt of mean packs below -20 -- the wide
	## deep galleries deserve their garrisons.
	for c in _pick_spots(reach, 9, -36.0, -20.0, 14.0, CaveField.PERM_R + 2.0):
		_spawn_gen(c, _gen_pick(c.y, _rng.randf() < 0.1), _rng.randi_range(2, 5))


func _player_tier() -> int:
	var pl: Node = get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	var lvl := 1
	if pl != null and "level" in pl:
		lvl = maxi(int(pl.get("level")), 1)
	return MonsterGen.tier_for_level(lvl)


func _gen_pick(depth_y: float, apex: bool) -> Dictionary:
	## A species from this cave's roster for the depth band. `apex` takes the
	## roster's meanest (largest) instead of a weighted roll.
	var key := MonsterGen.cave_key(global_position, depth_y)
	var tier := MonsterGen.band_tier(key, _player_tier())
	var wseed := int(cave_seed)
	if apex:
		var best := {}
		for g in MonsterGen.roster(wseed, key, tier):
			if best.is_empty() or float((g as Dictionary).get("hp", 0.0)) > float(best.get("hp", 0.0)):
				best = g
		return best
	return MonsterGen.pick(wseed, key, tier, _rng)


func _spawn_gen(center: Vector3, genome: Dictionary, count: int) -> void:
	## _spawn_pack for a generated species: the same ring, the same rock
	## check, the same PEACEFUL halving.
	if genome.is_empty():
		return
	for _i in range(GameMode.pack_count(count)):
		var e := Monster.from(genome)
		_content_root.add_child(e)
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(0.5, 3.2)
		var pos := center + Vector3(cos(a) * r, 1.2, sin(a) * r)
		if field.is_rock(pos) or field.is_rock(pos + Vector3.UP * 0.6):
			pos = center + Vector3(0, 1.2, 0)
		e.global_position = pos


'''
hunk_regex("scripts/CaveRegion.gd", "V1 generated dwellers", "func _spawn_gen(",
           r"func _spawn_dwellers\(reach: Array\[Vector3i\]\) -> void:\n.*?(?=func _crystal\()",
           CAVE_NEW.replace("\\", "\\\\"))

# ========================================================================== Warbands
hunk("scripts/Warbands.gd", "B1 raiders", "MonsterGen.raider(",
     "\tfor i in range(n):\n\t\tvar g := Goblin.new()\n",
     "\t## The band's fighters are GENERATED raiders now (Lemon, 2026-09-14):\n"
     "\t## one armed biped species per band cell (MonsterGen.raider), at the\n"
     "\t## player's level tier. Goblin.gd stays in the repo; it just no longer\n"
     "\t## spawns.\n"
     "\tvar raider_g := MonsterGen.raider(world_seed, int(c[\"cell\"]), _player_tier())\n"
     "\tfor i in range(n):\n\t\tvar g := Monster.from(raider_g)\n")
hunk("scripts/Warbands.gd", "B2 tier helper", "func _player_tier()",
     "func _ground_y(flat: Vector2) -> float:\n",
     "func _player_tier() -> int:\n"
     "\tvar pl: Node = get_tree().get_first_node_in_group(\"player\") if is_inside_tree() else null\n"
     "\tvar lvl := 1\n"
     "\tif pl != null and \"level\" in pl:\n"
     "\t\tlvl = maxi(int(pl.get(\"level\")), 1)\n"
     "\treturn MonsterGen.tier_for_level(lvl)\n\n\n"
     "func _ground_y(flat: Vector2) -> float:\n")

print("applied:", len(applied))
for a in applied:
    print("  +", a)
print("already there:", len(skipped))
for a in skipped:
    print("  =", a)
if failed:
    print("FAILED:", len(failed))
    for a in failed:
        print("  !", a)
    sys.exit(1)
