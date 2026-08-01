class_name CrystalCluster
extends StaticBody3D
## THE LIGHT IN THE DARK — and now something you can take.
##
## The caves' only native glow used to be scenery: a few emissive shards and an
## OmniLight, welded to the rock. It is a resource now. Swing a PICKAXE at a
## cluster and the shards come off one at a time — each bite shears a shard
## loose (real geometry gone, a burst of glittering chips, the cluster judders)
## and drops a **Crystal Shard** you can gather.
##
## The light goes with them. Every shard taken dims the cluster; take the last
## one and the pool of light you were standing in is simply not there any more.
## Mining out the pretty thing costs you the only lamp in the room — that's the
## trade, and it should feel like one.

const BITES_PER_SHARD := 2       ## pickaxe swings to shear one shard loose

var col := Color(0.35, 0.85, 1.0)
var shards: Array[MeshInstance3D] = []
var light: OmniLight3D
var _bites := BITES_PER_SHARD
var _base_energy := 1.2
var _flash := 0.0
var _shake := 0.0
var _pose_captured := false
var _base_pos := Vector3.ZERO
var _mat: StandardMaterial3D


static func make(p_col: Color, count: int, with_light: bool, rng: RandomNumberGenerator) -> CrystalCluster:
	var c := CrystalCluster.new()
	c.col = p_col
	c._pending = count
	c._pending_light = with_light
	c._seed = rng.randi()
	return c


var _pending := 3
var _pending_light := true
var _seed := 0


func _ready() -> void:
	add_to_group("crystals")
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = col
	_mat.emission_enabled = true
	_mat.emission = col
	_mat.emission_energy_multiplier = 2.2
	for _i in range(_pending):
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var s := rng.randf_range(0.18, 0.42)
		bm.size = Vector3(s, s * rng.randf_range(1.6, 2.6), s)
		m.mesh = bm
		m.material_override = _mat
		m.position = Vector3(rng.randf_range(-0.35, 0.35), bm.size.y * 0.35, rng.randf_range(-0.35, 0.35))
		m.rotation_degrees = Vector3(rng.randf_range(-18, 18), rng.randf_range(0, 360), rng.randf_range(-18, 18))
		add_child(m)
		shards.append(m)
	if _pending_light:
		light = OmniLight3D.new()
		light.light_color = col
		light.light_energy = _base_energy
		light.omni_range = 9.0
		light.shadow_enabled = false
		light.position = Vector3(0, 1.0, 0)
		add_child(light)
	## A shape to swing at — the pickaxe ray needs something to strike.
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 1.1, 1.0)
	cs.shape = shape
	cs.position = Vector3(0, 0.5, 0)
	add_child(cs)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 3.4)
		_mat.emission_energy_multiplier = 2.2 + _flash * 5.0
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 5.0)
		position = _base_pos + Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)) * _shake * 0.05
		if _shake <= 0.0:
			position = _base_pos


func mine_hit() -> void:
	## One pickaxe bite. Two bites shear a shard off; the last shard takes the
	## light with it.
	if shards.is_empty():
		return
	if not _pose_captured:
		_base_pos = position
		_pose_captured = true
	_flash = 1.0
	_shake = 1.0
	_chips(4)
	_bites -= 1
	if _bites > 0:
		return
	_bites = BITES_PER_SHARD
	var m: MeshInstance3D = shards.pop_back()
	var at: Vector3 = m.global_position
	m.queue_free()
	_drop_shard(at)
	## Fewer shards, less light — the room dims as you take it apart.
	if light != null:
		if shards.is_empty():
			light.queue_free()
			light = null
		else:
			light.light_energy = _base_energy * float(shards.size()) / float(maxi(_pending, 1))
	if shards.is_empty():
		## Nothing left to swing at.
		var p := get_tree().get_first_node_in_group("player")
		if p != null and p.has_method("_add_log_msg"):
			p._add_log_msg("The last of the light comes away in your hand", Color(0.7, 0.9, 1.0))
		queue_free()


func _drop_shard(at: Vector3) -> void:
	var d := DroppedItem.make({"name": "Crystal Shard", "weight": 0.5, "count": 1, "slot": "",
		"glow": col})
	get_parent().add_child(d)
	d.global_position = at
	d.velocity = Vector3(randf_range(-1.4, 1.4), randf_range(1.8, 3.0), randf_range(-1.4, 1.4))


func _chips(n: int) -> void:
	for _i in range(n):
		var chip := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var s := randf_range(0.04, 0.09)
		bm.size = Vector3(s, s, s)
		chip.mesh = bm
		chip.material_override = _mat
		add_child(chip)
		chip.position = Vector3(randf_range(-0.35, 0.35), randf_range(0.4, 0.9), randf_range(-0.35, 0.35))
		var dir := Vector3(randf() - 0.5, randf() * 0.8 + 0.3, randf() - 0.5).normalized()
		var t := create_tween()
		t.set_parallel(true)
		t.tween_property(chip, "position", chip.position + dir * randf_range(0.5, 1.0), 0.30)
		t.tween_property(chip, "scale", Vector3.ONE * 0.05, 0.32)
		t.chain().tween_callback(chip.queue_free)
