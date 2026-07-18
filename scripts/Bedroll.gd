extends StaticBody3D
class_name Bedroll
## A placeable camp bed. Lives in the world as this body (group "beds"):
##   F beside it ..... sleep until dawn (Player._sleep — shifts the deep)
##   look + E ........ pack it up into the backpack ("Bedroll" item)
## Click the Bedroll item in the inventory to put it back down ahead of you.
## Built in code like everything else — leather roll, blanket, pillow.


func _ready() -> void:
	add_to_group("beds")
	var mats := {
		"roll": Color(0.34, 0.24, 0.15), "blanket": Color(0.22, 0.24, 0.38),
		"pillow": Color(0.72, 0.66, 0.55),
	}
	var parts := [
		["roll", Vector3(0.95, 0.16, 2.0), Vector3(0, 0.08, 0)],
		["blanket", Vector3(0.9, 0.10, 1.25), Vector3(0, 0.19, 0.28)],
		["pillow", Vector3(0.52, 0.14, 0.42), Vector3(0, 0.2, -0.7)],
	]
	for pr: Array in parts:
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = pr[1]
		m.mesh = bm
		m.position = pr[2]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = mats[pr[0]]
		mat.roughness = 1.0
		m.material_override = mat
		add_child(m)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.95, 0.16, 2.0)
	col.shape = shape
	col.position = Vector3(0, 0.08, 0)
	add_child(col)
