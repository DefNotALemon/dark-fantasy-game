class_name PSXProp
extends StaticBody3D

## ===========================================================================
## One piece of the wood's furniture — a fallen log, an old stump, a boulder.
##                                            (docs/TREES_v3_PSX.md §8)
##
## The small litter (twigs, pebbles, ferns) is instanced by Understory and has
## no collision, because four thousand colliders for things you step over is a
## bad trade. Anything you can actually stand on, climb, or trip over is one of
## these instead: a real StaticBody3D with a convex hull off its own mesh.
##
## Fallen logs and stumps are CHOPPABLE — a log lying in the wood is firewood
## someone else already felled, and the axe should know that.
## ===========================================================================

const HEART := Color(0.62, 0.47, 0.28)

@export var asset := "SM_FallenLog_Large"
@export var region := "temperate"
var prop_scale := 1.0
var hits_left := 0
var cleared := false

var _model: Node3D


static func make(asset_id: String, at: Vector3, yaw: float, s: float,
		region_id := "temperate") -> PSXProp:
	var p := PSXProp.new()
	p.asset = asset_id
	p.region = region_id
	p.prop_scale = s
	p.position = at
	p.rotation.y = yaw
	return p


static func chop_yield(asset_id: String) -> int:
	## Axe bites before it gives up its wood. A big log is a job; a stump is a
	## couple of swings; a rock is not wood and takes none.
	if asset_id.begins_with("SM_FallenLog_Large"):
		return 4
	if asset_id.begins_with("SM_FallenLog_Small"):
		return 2
	if asset_id.begins_with("SM_Stump"):
		return 3
	return 0


func _ready() -> void:
	add_to_group("psx_props")
	hits_left = chop_yield(asset)
	if hits_left > 0:
		add_to_group("choppable")

	var packed = load(PSXNature.scene_path(asset))
	if packed == null:
		push_warning("PSXProp: missing %s" % asset)
		return
	_model = packed.instantiate()
	_model.scale = Vector3.ONE * prop_scale
	add_child(_model)

	var atlas := String(PSXNature.info(asset).get("atlas", "Props"))
	var mats := PSXNature.materials(atlas, region, false)
	var shapes := 0
	for n in _walk(_model):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var leafy := mi.name.begins_with("Foliage")
		for i in range(mi.mesh.get_surface_count()):
			mi.set_surface_override_material(i, mats[1] if leafy else mats[0])
		if leafy:
			continue                       ## you do not bump into moss
		## A convex hull off the mesh itself. These are 16-48 triangle rocks and
		## hollow logs — the hull is a handful of planes and it beats a box for
		## anything you can climb onto.
		var shape := mi.mesh.create_convex_shape(true, true)
		if shape == null:
			continue
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * prop_scale),
			mi.position * prop_scale)
		add_child(cs)
		shapes += 1
	if shapes == 0:
		var box := BoxShape3D.new()
		var h: float = maxf(float(PSXNature.info(asset).get("height", 0.5)) * prop_scale, 0.2)
		box.size = Vector3(h, h, h)
		var cs2 := CollisionShape3D.new()
		cs2.shape = box
		cs2.position.y = h * 0.5
		add_child(cs2)


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out


func chop_hit(_toward_chopper: Vector3, _aim := Vector3.INF) -> bool:
	## Same contract as TreeV2 / TreeStump / FallenTrunk: true only on the swing
	## that finishes it.
	if cleared or hits_left <= 0:
		return false
	hits_left -= 1
	if _model != null:
		var tw := create_tween()
		tw.tween_property(_model, "scale", Vector3.ONE * prop_scale * 0.94, 0.05)
		tw.tween_property(_model, "scale", Vector3.ONE * prop_scale, 0.14)
	if hits_left > 0:
		return false
	_break_up()
	return true


func _break_up() -> void:
	cleared = true
	remove_from_group("choppable")
	var world := get_parent()
	if world == null:
		queue_free()
		return
	## Old wood off the forest floor is firewood and kindling, not fresh timber.
	var logs := 2 if asset.begins_with("SM_FallenLog_Large") else 1
	for i in range(logs):
		var w := DroppedItem.make({"name": "Wood", "weight": 1.2, "count": 1, "slot": ""})
		world.add_child(w)
		w.global_position = global_position + Vector3(randf_range(-0.6, 0.6), 0.4,
			randf_range(-0.6, 0.6))
		w.velocity = Vector3(randf_range(-1.2, 1.2), randf_range(1.0, 2.0), randf_range(-1.2, 1.2))
	for i in range(randi_range(1, 3)):
		var s := DroppedItem.make({"name": "Stick", "weight": 0.3, "count": 1, "slot": ""})
		world.add_child(s)
		s.global_position = global_position + Vector3(randf_range(-0.7, 0.7), 0.3,
			randf_range(-0.7, 0.7))
		s.velocity = Vector3(randf_range(-1.5, 1.5), randf_range(0.8, 1.8), randf_range(-1.5, 1.5))
	queue_free()


func save_dict() -> Dictionary:
	return {"kind": "psx_prop", "asset": asset, "region": region, "scale": prop_scale,
		"pos": [global_position.x, global_position.y, global_position.z],
		"rot": rotation.y, "hits": hits_left}


static func from_dict(d: Dictionary) -> PSXProp:
	var p := PSXProp.new()
	p.asset = str(d.get("asset", "SM_Rock_05"))
	p.region = str(d.get("region", "temperate"))
	p.prop_scale = float(d.get("scale", 1.0))
	var v: Array = d.get("pos", [0, 0, 0])
	p.position = Vector3(float(v[0]), float(v[1]), float(v[2]))
	p.rotation.y = float(d.get("rot", 0.0))
	p.set_meta("restore_hits", int(d.get("hits", 0)))
	return p


func restore(d: Dictionary) -> void:
	hits_left = int(d.get("hits", hits_left))
	if hits_left <= 0 and chop_yield(asset) > 0:
		queue_free()
