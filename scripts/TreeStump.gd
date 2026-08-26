class_name TreeStump
extends StaticBody3D

## ===========================================================================
## What's left standing.  docs/TREES_v2_SPEC.md §9
##
## Three more bites of the axe clears it: two firewood and a bare dirt scar you
## can plant a seed on. Stumps do not sprout — clearing one is how a felled
## clearing stops looking like a war zone.
## ===========================================================================

const CLEAR_HITS := 3
const STUMP_H := 0.42

const BARK := {
	"maple": Color(0.145, 0.120, 0.105), "birch": Color(0.66, 0.66, 0.62),
	"oak": Color(0.125, 0.105, 0.092), "pine": Color(0.135, 0.105, 0.088),
	"fir": Color(0.115, 0.100, 0.092),
}
const HEART := Color(0.52, 0.39, 0.21)   ## fresh-cut heartwood, matches ChopTree

var species := "maple"
var radius := 0.3
var hits_left := CLEAR_HITS
var cleared := false


static func make(at: Vector3, r: float, species_id: String) -> TreeStump:
	var s := TreeStump.new()
	s.position = at
	s.radius = r
	s.species = species_id
	return s


func _ready() -> void:
	add_to_group("tree_stumps")
	add_to_group("choppable")

	if TreeV2.USE_PSX and _build_psx_stump():
		_add_collision()
		return

	var cyl := CylinderMesh.new()
	cyl.top_radius = radius * 0.98
	cyl.bottom_radius = radius * 1.25    ## the root flare stays in the ground
	cyl.height = STUMP_H
	cyl.radial_segments = 9
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.position.y = STUMP_H * 0.5
	mi.material_override = _bark_material(radius, STUMP_H)
	add_child(mi)

	## the pale cut face on top — the thing that says a person did this
	var top := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius * 0.97
	disc.bottom_radius = radius * 0.97
	disc.height = 0.02
	disc.radial_segments = 9
	top.mesh = disc
	top.position.y = STUMP_H + 0.011
	var tm := StandardMaterial3D.new()
	tm.albedo_color = HEART
	tm.roughness = 0.9
	top.material_override = tm
	add_child(top)

	_add_collision()


func _add_collision() -> void:
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius * 1.1
	shape.height = STUMP_H
	cs.shape = shape
	cs.position.y = STUMP_H * 0.5
	add_child(cs)


func _build_psx_stump() -> bool:
	## The pack has two stumps. Scale the nearer one so its own trunk matches
	## the tree that stood here, and keep the pale cut face on top -- that disc
	## is the thing that says a person did this, and the pack's stump is a
	## weathered old one with bark right over the top.
	var asset := "SM_Stump_01" if radius >= 0.26 else "SM_Stump_02"
	var native_r := 0.40 if asset == "SM_Stump_01" else 0.28
	var packed = load(PSXNature.scene_path(asset))
	if packed == null:
		return false
	var m: Node3D = packed.instantiate()
	var s: float = clampf(radius / native_r, 0.45, 3.0)
	m.scale = Vector3.ONE * s
	m.rotation.y = randf() * TAU
	add_child(m)
	var mats := PSXNature.materials("Props", "temperate", false)
	for n in _all(m):
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh != null:
			for i in range(mi.mesh.get_surface_count()):
				mi.set_surface_override_material(i, mats[0])

	var top := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius * 0.92
	disc.bottom_radius = radius * 0.92
	disc.height = 0.02
	disc.radial_segments = 9
	top.mesh = disc
	top.position.y = float(PSXNature.info(asset).get("height", 0.7)) * s * 0.94
	var tm := StandardMaterial3D.new()
	tm.albedo_color = HEART
	tm.roughness = 0.9
	top.material_override = tm
	add_child(top)
	return true


func _all(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out


func chop_hit(_toward_chopper: Vector3, _aim := Vector3.INF) -> bool:
	if cleared:
		return false
	hits_left -= 1
	if hits_left > 0:
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector3(1.0, 0.94, 1.0), 0.05)
		tw.tween_property(self, "scale", Vector3.ONE, 0.14)
		return false
	_clear()
	return true


func _clear() -> void:
	cleared = true
	var world := get_parent()
	for _i in range(2):
		var w := DroppedItem.make({"name": "Firewood", "weight": 1.1, "count": 1, "slot": ""})
		world.add_child(w)
		w.global_position = global_position + Vector3(randf_range(-0.5, 0.5), 0.35,
			randf_range(-0.5, 0.5))
		w.velocity = Vector3(randf_range(-1.4, 1.4), randf_range(1.2, 2.2), randf_range(-1.4, 1.4))
	## The bare scar is plantable ground — TreeSeed checks for this group.
	var scar := Node3D.new()
	scar.add_to_group("planting_ground")
	world.add_child(scar)
	scar.global_position = global_position
	queue_free()


static func from_dict(d: Dictionary) -> TreeStump:
	var p: Array = d.get("pos", [0, 0, 0])
	var s := TreeStump.make(Vector3(float(p[0]), float(p[1]), float(p[2])),
		float(d.get("radius", 0.3)), str(d.get("species", "maple")))
	s.hits_left = int(d.get("hits", CLEAR_HITS))
	return s


func save_dict() -> Dictionary:
	return {"kind": "stump", "species": species, "radius": radius, "hits": hits_left,
		"pos": [global_position.x, global_position.y, global_position.z]}


func _bark_material(r: float, along: float) -> Material:
	## One shared ShaderMaterial per species would tile wrongly on differently
	## sized logs, so this takes a duplicate and sets the tiling for THIS piece.
	var base: Material = TreeV2.materials_for(species)[0]
	var m: ShaderMaterial = (base as ShaderMaterial).duplicate()
	m.set_shader_parameter("tiling", Vector2(maxf(TAU * r * 1.6, 0.5), maxf(along * 1.6, 0.5)))
	m.set_shader_parameter("sway", 0.0)      ## it is on the ground; it does not sway
	return m
