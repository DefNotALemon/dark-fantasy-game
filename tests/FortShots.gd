extends SceneTree
## Renders the fort from a few angles so a human can look at it.
##   xvfb-run godot --path . --script res://tests/FortShots.gd
const OUT := "user://shots/"

func _init() -> void:
	## the root Window is not "inside the tree" during _init, so anything added
	## here never renders — wait a frame before building
	await process_frame
	DirAccess.make_dir_recursive_absolute(OUT)
	var host := Node3D.new()
	root.add_child(host)
	var f := FortKnox.build_flat(host)
	## a ground plane so the fort is not floating in the void
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.30, 0.36, 0.22)
	gm.roughness = 1.0
	g.material_override = gm
	host.add_child(g)
	g.global_position = Vector3(f.position.x, f.position.y - 2.0, f.position.z)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.66, 0.78)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.66, 0.72)
	e.ambient_light_energy = 0.85
	env.environment = e
	host.add_child(env)
	var sun := DirectionalLight3D.new()
	host.add_child(sun)
	sun.rotation_degrees = Vector3(-42, 38, 0)
	sun.light_energy = 1.5

	var cam := Camera3D.new()
	host.add_child(cam)
	cam.current = true
	cam.far = 4000.0

	var o := f.position
	var shots := [
		["1_from_the_river", o + Vector3(150, 46, 30), o + Vector3(0, 4, 0), 55.0],
		["2_the_river_front", o + Vector3(96, 7, 4), o + Vector3(20, 5, 0), 62.0],
		["3_over_the_parade", o + Vector3(-46, 40, -52), o + Vector3(4, 0, 6), 60.0],
		["4_standing_on_the_parade", o + Vector3(-22, 1.7, 18), o + Vector3(30, 5, -4), 75.0],
		["5_the_gate_from_outside", o + Vector3(-72, 6, 2), o + Vector3(-20, 4, 0), 65.0],
		["6_the_passage", o + Vector3(4.9, -5.3, -20), o + Vector3(7.6, -5.9, 6), 72.0],
		["8_the_magazine", o + Vector3(11.0, -5.3, -14), o + Vector3(20, -5.9, -14), 80.0],
		["9_the_stair", o + Vector3(6, -5.3, -24.5), o + Vector3(6.3, -1.0, -28), 80.0],
		["7_plan", o + Vector3(2, 130, 2), o + Vector3(2, 0, 2), 55.0],
	]
	for s in shots:
		var sv: Array = s
		cam.global_position = sv[1]
		cam.look_at(sv[2], Vector3.UP)
		cam.fov = float(sv[3])
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img: Image = root.get_viewport().get_texture().get_image()
		img.save_png(OUT + str(sv[0]) + ".png")
		print("shot ", sv[0])
	quit(0)
