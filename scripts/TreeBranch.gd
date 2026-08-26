class_name TreeBranch
extends Node3D

## ===========================================================================
## One order-1 limb.  docs/TREES_v2_SPEC.md §8a
##
## Wraps a `Branch_NN` MeshInstance3D exported by tools/treegen2.py. It carries
## its own collider, its own HP, and the leaves that hang off it — so when the
## axe takes it down, the leaves go with it and what lands is a stick.
##
## The axe's swing is aligned to `dir()`: you swing ALONG the limb, outward and
## away from the camera, never across it.
## ===========================================================================

const HIT_RADIUS_PER_HP := 0.03    ## spec §8a: hp = ceil(radius / 0.03)
const MAX_HP := 3        ## was 7, then 4 — see the swing-count note below
const MIN_LIMB_R := 0.045   ## thinner than this and it isn't worth an axe swing
const MAX_LIMBS := 4        ## the most a single tree will ever ask you to clear
## Limbing is optional now — worth doing for the sticks, never a gate.
const REACH_HEIGHT := 4.5
const LEAF_BURST := 22             ## cards that visibly flutter down on the break

var mesh: MeshInstance3D
var tree: Node3D
var hp := 2
var gone := false
## Vestigial: limbs no longer gate felling at all — you cut a wedge out of the
## trunk and it goes over. Kept only so old callers and saves still compile.
var blocks_trunk := false

var _area: Area3D
var _base := Vector3.ZERO
var _tip := Vector3.ZERO
var _radius := 0.06


func setup(mi: MeshInstance3D, owner_tree: Node3D) -> void:
	mesh = mi
	tree = owner_tree
	name = "Limb_" + mi.name.replace("Branch_", "")

	var aabb: AABB = mi.mesh.get_aabb() if mi.mesh != null else AABB()
	_base = mi.position
	_tip = mi.position + aabb.get_center()
	## A limb's thickness is roughly its shortest cross-axis. Good enough, and
	## it makes twigs one-shot while an ancient oak's arm takes real work.
	## Thickness comes from the exported NAME (Branch_03_r085 -> 0.085 m).
	## Deriving it from the AABB was the bug that made a mature tree take ~84
	## swings to fell: a long thin limb has a big bounding box, so every limb
	## came out at max HP.
	_radius = _radius_from_name(mi.name)
	hp = clampi(int(ceil(_radius / HIT_RADIUS_PER_HP)), 1, MAX_HP)

	## Collision so the axe (and arrows, and the player's shins) can find it.
	_area = Area3D.new()
	_area.monitoring = false
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = maxf(_radius, 0.10)
	cap.height = maxf(aabb.size.length() * 0.7, 0.4)
	cs.shape = cap
	cs.position = aabb.get_center()
	## lie the capsule along the limb instead of standing it upright
	var d := aabb.get_center()
	if d.length() > 0.01:
		cs.look_at_from_position(cs.position, cs.position + d, Vector3.UP)
		cs.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	_area.add_child(cs)
	add_child(_area)
	position = mi.position


static func _radius_from_name(n: String) -> float:
	var i := n.rfind("_r")
	if i < 0:
		return 0.06
	var digits := n.substr(i + 2)
	if not digits.is_valid_int():
		return 0.06
	return clampf(float(digits.to_int()) / 1000.0, 0.01, 0.40)


func hit_point() -> Vector3:
	return to_global(_tip - _base)


func dir() -> Vector3:
	## The axis the axe should swing along.
	var d := (_tip - _base)
	return (global_transform.basis * d).normalized() if d.length() > 0.001 else Vector3.FORWARD


func take_hit(n := 1) -> bool:
	## Returns true if this swing took the limb off.
	if gone:
		return false
	hp -= n
	if hp > 0:
		_shudder()
		return false
	break_off()
	return true


func _shudder() -> void:
	if mesh == null:
		return
	var away := dir() * 0.06
	var tw := create_tween()
	tw.tween_property(mesh, "position", mesh.position + away, 0.05)
	tw.tween_property(mesh, "position", mesh.position, 0.18)


func break_off() -> void:
	## Leaves burst and drift down, the limb is gone, and what's left on the
	## ground is firewood — 2-3 sticks for a real limb, 1 for a twig.
	if gone:
		return
	gone = true
	var at := hit_point()
	var world := get_tree().current_scene
	if world == null:
		world = tree.get_parent()

	_spawn_leaf_fall(world, at)

	var sticks := 1 if _radius < 0.08 else (2 if _radius < 0.16 else 3)
	for _i in range(sticks):
		var s := DroppedItem.make({"name": "Stick", "weight": 0.3, "count": 1, "slot": ""})
		world.add_child(s)
		s.global_position = at + Vector3(randf_range(-0.5, 0.5), randf_range(0.0, 0.4),
			randf_range(-0.5, 0.5))
		s.velocity = Vector3(randf_range(-1.6, 1.6), randf_range(1.0, 2.4), randf_range(-1.6, 1.6))

	if mesh != null:
		mesh.queue_free()
		mesh = null
	if _area != null:
		_area.queue_free()
		_area = null


func remove_silently() -> void:
	## Save-load: this limb was already taken off in a previous session.
	gone = true
	if mesh != null:
		mesh.queue_free()
		mesh = null
	if _area != null:
		_area.queue_free()
		_area = null


func _spawn_leaf_fall(world: Node, at: Vector3) -> void:
	## A short-lived shower of leaf cards. Deliberately particles and not physics
	## bodies: LEAF_BURST rigid bodies per limb on an ancient oak is a stutter,
	## and nobody can tell the difference on the way down.
	var p := GPUParticles3D.new()
	p.amount = LEAF_BURST
	p.lifetime = 2.6
	p.one_shot = true
	p.explosiveness = 0.55
	p.emitting = true

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 55.0
	mat.initial_velocity_min = 0.4
	mat.initial_velocity_max = 1.6
	mat.gravity = Vector3(0, -1.4, 0)          ## leaves fall slowly, that's the point
	mat.damping_min = 0.4
	mat.damping_max = 1.2
	mat.angular_velocity_min = -180.0
	mat.angular_velocity_max = 180.0
	mat.scale_min = 0.10
	mat.scale_max = 0.22
	p.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	p.draw_pass_1 = quad
	## Reuse the tree's own leaf material so the burst is the right species and
	## the right season without any extra bookkeeping.
	if tree != null and tree.has_method("leaf_material"):
		p.material_override = tree.leaf_material()

	world.add_child(p)
	p.global_position = at
	var t := world.get_tree().create_timer(4.0)
	t.timeout.connect(func(): if is_instance_valid(p): p.queue_free())


func radius() -> float:
	return _radius


func base_height() -> float:
	return _base.y
