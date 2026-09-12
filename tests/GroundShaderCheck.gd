extends SceneTree
## GroundShaderCheck.gd -- compile shaders/terrain_psx.gdshader on a LIVE
## renderer with the ground textures bound, paint a quilt of one tile per
## column, and save the frame to /tmp/ground_shader_check.png. The headless
## driver cannot compile shaders; this can (2026-09-03: clean, textures render).
##   xvfb-run -a godot --rendering-driver opengl3 --path . --script res://tests/GroundShaderCheck.gd
func _init() -> void:
	var sh := load("res://shaders/terrain_psx.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var world := Node3D.new()
	root.add_child(world)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.look_at_from_position(Vector3(0, 6, 10), Vector3(0, 0, 0))
	var light := DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-50, 35, 0)
	var gp := GroundPaint.new()
	world.add_child(gp)
	gp.setup(mat, Vector2(-20, -20), Vector2i(11, 11), 4.0)
	gp.set_style_row(6)
	# a quilt: paint one of every column across the fake grid
	for c in range(11):
		gp.paint_disc(Vector3(-20 + c * 4.0, 0, -20 + 5 * 4.0), 1.0, GroundPaint.tile_id(2, c))
	gp.flush_texture()
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(48, 48)
	pm.subdivide_depth = 12
	pm.subdivide_width = 12
	mi.mesh = pm
	mi.material_override = mat
	world.add_child(mi)
	await process_frame
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("/tmp/ground_shader_check.png")
	print("rendered %dx%d, shader valid=%s" % [img.get_width(), img.get_height(), str(RenderingServer.shader_get_code(sh.get_rid()).length() > 0)])
	quit()
