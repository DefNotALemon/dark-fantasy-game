extends SceneTree
## Render the overworld on a LIVE renderer and save the frame -- the headless
## renderer cannot compile shaders, this can:
##   xvfb-run -a godot --rendering-driver opengl3 --path . --script res://tests/TerrainRender.gd
## Writes /tmp/terrain_render_*.png. Look at them. A magenta or black ground is
## a shader that did not compile (the error is in stderr, "SHADER ERROR").
var _ow: Node3D
var _cam: Camera3D
var _frame := 0
var _shots: Array = []


func _init() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.68, 0.85)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.6, 0.7)
	e.ambient_light_energy = 0.7
	e.fog_enabled = true
	e.fog_density = 0.0011
	e.fog_light_color = Color(0.6, 0.7, 0.8)
	env.environment = e
	world.add_child(env)
	var light := DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-48, 30, 0)
	light.light_energy = 1.3
	# the wind globals the water shader reads
	var wind = load("res://scripts/Wind.gd").new()
	world.add_child(wind)
	_ow = load("res://scripts/Overworld.gd").new()
	world.add_child(_ow)
	_cam = Camera3D.new()
	_cam.far = 9000.0
	_cam.fov = 70.0
	world.add_child(_cam)
	_cam.make_current()
	# 1: the valley's edge looking east over the ring and the woods
	# 2: Moosehead lake with the ranges behind it
	# 3: Portland's coast
	_shots = [
		[Vector3(90.0, 12.0, 0.0), Vector3(400.0, 0.0, 0.0), "valley_east"],
		[Vector3(1150.0, 120.0, -3760.0), Vector3(1350.0, 54.0, -4200.0), "moosehead"],
		[Vector3(2210.0, 420.0, -4830.0), Vector3(2312.0, 359.0, -4911.0), "katahdin_tarn"],
		[Vector3(240.0, 28.0, 380.0), Vector3(240.0, -18.0, 520.0), "portland"],
		[Vector3(800.0, 8.0, -1590.0), Vector3(820.0, 6.0, -1660.0), "deepwood"],
	]


func _process(_d: float) -> bool:
	_frame += 1
	@warning_ignore("integer_division")
	var idx := (_frame - 1) / 12
	if idx >= _shots.size():
		quit()
		return true
	var s: Array = _shots[idx]
	if (_frame - 1) % 12 == 0:
		_cam.global_position = s[0]
		_cam.look_at(s[1])
		_ow.warm(s[0])
		# no real trees here: their per-instance uniforms overflow the compat
		# renderer's 4096-slot buffer under llvmpipe, and this check is about
		# the ground, the water and the baked woods
		for k in _ow._plans.keys():
			var st: PackedInt32Array = _ow._plans[k]["state"]
			for c in range(st.size()):
				if st[c] == 1:
					_ow._demote_cell(k, c)
			_ow._felled.clear()
			_ow._rebuild_impostors(k)
		_ow._cell_queue.clear()
		print("shot %s: %s" % [s[2], str(_ow.forest_stats())])
	elif (_frame - 1) % 12 == 10:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("/tmp/terrain_render_%s.png" % s[2])
		print("saved /tmp/terrain_render_%s.png" % s[2])
	return false
