extends StaticBody3D
class_name OreVein
## A mineable ore vein: a dark boulder shot through with glinting seams of one
## material (Materials.gd). Swing a PICKAXE at it (weapon 3) — each bite flashes
## the seams, shakes the rock, and chips sparks off; the last one bursts it into
## ore chunks that magnet to the player like any loot. Swords just skate off.
##
## Built in code: OreVein.make("silver") -> add_child -> position it.

const HITS_TO_BREAK := 4
const ORE_PER_VEIN := [1, 2]     ## min/max ore chunks a vein yields

var mat_id := "silver"
var hits_left := HITS_TO_BREAK
var broken := false

var _seam_mats: Array[StandardMaterial3D] = []   ## flashed when struck
var _seam_base_energy := 1.1
var _flash := 0.0            ## >0 = seams burning bright after a hit
var _shake := 0.0            ## brief rock judder after a hit
## Rest pose is captured on the FIRST strike, not in _ready — the cave positions
## the vein after add_child (after _ready ran), so capturing early would snap the
## rock back to the cave origin when its first shake settled.
var _pose_captured := false
var _base_pos := Vector3.ZERO
var _rest_rot := Vector3.ZERO


static func make(id: String) -> OreVein:
	var v := OreVein.new()
	v.mat_id = id
	return v


func _ready() -> void:
	add_to_group("ore_veins")

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.5, 1.3, 1.5)
	col.shape = shape
	col.position = Vector3(0, 0.6, 0)
	add_child(col)

	var mat: Dictionary = Materials.get_mat(mat_id)
	var seam_col: Color = mat["color"]
	var elem: Dictionary = mat["element"]
	var glow_col := seam_col if elem.is_empty() else Color(elem["color"])
	_seam_base_energy = 0.7 if elem.is_empty() else 1.6

	## The boulder: a couple of tilted dark-rock lumps.
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.16, 0.15, 0.17)
	rock.roughness = 1.0
	_lump(Vector3(1.35, 1.15, 1.35), Vector3(0, 0.55, 0), Vector3(randf_range(-8, 8), randf() * 360.0, randf_range(-8, 8)), rock)
	_lump(Vector3(1.0, 0.85, 1.0), Vector3(randf_range(-0.3, 0.3), 0.95, randf_range(-0.3, 0.3)),
		Vector3(randf_range(-14, 14), randf() * 360.0, randf_range(-14, 14)), rock)

	## Ore seams: bright studs punched through the rock faces. They glow so the
	## vein reads in a lightless cave — elemental metals burn noticeably hotter.
	for _i in range(randi_range(4, 6)):
		var sm := StandardMaterial3D.new()
		sm.albedo_color = seam_col
		sm.metallic = 0.8
		sm.roughness = 0.3
		sm.emission_enabled = true
		sm.emission = glow_col
		sm.emission_energy_multiplier = _seam_base_energy
		_seam_mats.append(sm)
		var stud := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var s := randf_range(0.16, 0.30)
		bm.size = Vector3(s, s * randf_range(0.9, 1.5), s)
		stud.mesh = bm
		var a := randf() * TAU
		var rr := randf_range(0.55, 0.78)
		stud.position = Vector3(cos(a) * rr, randf_range(0.25, 1.05), sin(a) * rr)
		stud.rotation_degrees = Vector3(randf_range(-25, 25), randf() * 360.0, randf_range(-25, 25))
		stud.material_override = sm
		add_child(stud)

	## Rare metal advertises itself: meteoric veins throw faint ember light.
	if not elem.is_empty():
		var l := OmniLight3D.new()
		l.light_color = glow_col
		l.light_energy = 0.7
		l.omni_range = 5.0
		l.shadow_enabled = false
		l.position = Vector3(0, 1.0, 0)
		add_child(l)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 3.0, 0.0)
		for sm in _seam_mats:
			sm.emission_energy_multiplier = _seam_base_energy + _flash * 5.0
	if _shake > 0.0 and _pose_captured:
		_shake = maxf(_shake - delta * 4.0, 0.0)
		position = _base_pos + Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)) * 0.035 * _shake
		rotation_degrees = _rest_rot + Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)) * 1.2 * _shake
	elif _pose_captured and position != _base_pos:
		position = _base_pos
		rotation_degrees = _rest_rot


func mine_hit() -> void:
	## One pickaxe bite. Feedback first, geology second.
	if broken:
		return
	if not _pose_captured:
		_base_pos = position
		_rest_rot = rotation_degrees
		_pose_captured = true
	hits_left -= 1
	_flash = 1.0
	_shake = 1.0
	_spawn_chips(3)
	if hits_left <= 0:
		_break_apart()


func _spawn_chips(n: int) -> void:
	## Sparks/chips that jump off the strike and die quickly.
	var mat: Dictionary = Materials.get_mat(mat_id)
	for _i in range(n):
		var chip := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var s := randf_range(0.05, 0.11)
		bm.size = Vector3(s, s, s)
		chip.mesh = bm
		var cm := StandardMaterial3D.new()
		cm.albedo_color = mat["color"]
		cm.emission_enabled = true
		cm.emission = mat["color"]
		cm.emission_energy_multiplier = 2.0
		chip.material_override = cm
		add_child(chip)
		chip.position = Vector3(randf_range(-0.4, 0.4), randf_range(0.5, 1.0), randf_range(-0.4, 0.4))
		var dir := Vector3(randf() - 0.5, randf() * 0.8 + 0.3, randf() - 0.5).normalized()
		var t := create_tween()
		t.set_parallel(true)
		t.tween_property(chip, "position", chip.position + dir * randf_range(0.6, 1.1), 0.28)
		t.tween_property(chip, "scale", Vector3.ONE * 0.05, 0.30)
		t.chain().tween_callback(chip.queue_free)


func _break_apart() -> void:
	## The vein gives: burst into ore pickups + a shower of dead rock chips.
	broken = true
	## Hide the rock at once (collision too) — BEFORE spawning the burst chips,
	## so the hide sweep doesn't catch them.
	for c in get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).visible = false
		elif c is CollisionShape3D:
			(c as CollisionShape3D).set_deferred("disabled", true)
		elif c is OmniLight3D:
			(c as OmniLight3D).visible = false
	_spawn_chips(8)
	var n := randi_range(ORE_PER_VEIN[0], ORE_PER_VEIN[1])
	for _i in range(n):
		var ore := PickupOrb.make_ore(mat_id)
		get_parent().add_child(ore)
		ore.global_position = global_position + Vector3(0, 1.0, 0)
		var a := randf() * TAU
		ore.burst_dir = Vector3(cos(a) * 1.6, 0.8, sin(a) * 1.6)
	var t := create_tween()
	t.tween_interval(0.5)
	t.tween_callback(queue_free)


func _lump(size: Vector3, pos: Vector3, rot: Vector3, mat: StandardMaterial3D) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot
	add_child(m)
