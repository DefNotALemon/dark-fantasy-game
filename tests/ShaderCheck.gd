extends SceneTree
## Render a few baked creatures on a LIVE renderer and save the frame:
##   xvfb-run -a godot --rendering-driver opengl3 --path . --script res://tests/ShaderCheck.gd
## The headless renderer cannot compile shaders; this can. Look at the PNG.
func _init() -> void:
	var sh := load("res://shaders/psx_skin.gdshader") as Shader
	print("shader loaded: %s" % (sh != null))
	var world := Node3D.new()
	root.add_child(world)
	world.add_to_group("world")
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.45, 0.55, 0.65)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.6)
	e.ambient_light_energy = 0.8
	env.environment = e
	world.add_child(env)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.position = Vector3(0, 1.4, 5.5)
	cam.look_at(Vector3(0.5, 0.8, 0))
	var light := DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-50, 35, 0)
	light.light_energy = 1.4
	var flr := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	flr.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.25, 0.32, 0.18)
	flr.material_override = fm
	world.add_child(flr)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(40, 1, 40)
	cs.shape = bs
	sb.add_child(cs)
	sb.position.y = -0.5
	world.add_child(sb)
	var g := Goblin.new()
	world.add_child(g)
	g.position = Vector3(-1.6, 0, 0)
	g.confused = true
	var d := Critter.make("whitetail")
	world.add_child(d)
	d.position = Vector3(1.2, 0, -1.5)
	var b := Critter.make("black_bear")
	world.add_child(b)
	b.position = Vector3(-3.5, 0, -2.5)
	var f := Critter.make("red_fox")
	world.add_child(f)
	f.position = Vector3(2.8, 0, 0.8)
	var t := Critter.make("turkey")
	world.add_child(t)
	t.position = Vector3(0.3, 0, 1.2)
	var dk := DarkKnight.new()
	world.add_child(dk)
	dk.position = Vector3(4.0, 0, -1.5)
	dk.confused = true
	for i in 8:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("/tmp/skin_frame.png")
		print("frame saved %dx%d" % [img.get_width(), img.get_height()])
	## close-up on the deer and bear
	cam.position = Vector3(0.0, 1.3, 1.6)
	cam.look_at(Vector3(0.6, 0.8, -1.5))
	for i in 4:
		await process_frame
	img = root.get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("/tmp/skin_close.png")
	## the bear knocked down, the deer dead — the ragdolls on screen
	b.knockdown(Vector3(1.5, 0.5, 0), 3.0)
	d.take_damage(9999, null, false, null, null)
	cam.position = Vector3(-1.0, 1.6, 2.5)
	cam.look_at(Vector3(-0.8, 0.4, -2.0))
	for i in 70:
		await process_frame
	img = root.get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("/tmp/skin_ragdoll.png")
	print("SHADER CHECK DONE")
	quit()
