extends SceneTree
## CityLook — LOOK at a staged city and save PNGs.
##
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##       --resolution 1280x720 --script res://tests/CityLook.gd -- Portland out_dir
##
## Not a test: it stages one city on a flat green plane, walks a camera round
## it, and writes a picture per vantage. A green suite says nothing about
## the game; this is the cheapest way to look before believing it.

var _frame := 0
var _shot := 0
var _cam: Camera3D
var _cities: Cities
var _city := "Portland"
var _out := "user://"
var _shots: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_city = args[0]
	if args.size() >= 2:
		_out = args[1]
	var w := Node3D.new()
	w.name = "World"
	root.add_child(w)
	# ground
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1600, 1600)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.48, 0.24)
	gm.roughness = 1.0
	g.material_override = gm
	w.add_child(g)
	# light + sky
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 35.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	w.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.9
	env.environment = e
	w.add_child(env)
	# the city at the origin
	_cities = Cities.new()
	w.add_child(_cities)
	_cities.world_seed = 3
	_cities.set_roster([{"name": _city, "pos": [0.0, 0.0]}])
	_cities.set_road_dirs(_city, [Vector2(0, 1), Vector2(-0.8, -0.6).normalized(), Vector2(1, -0.2).normalized()])
	_cities.build()
	_cities.stage(_city)
	print(_cities.report())
	var R := float(_cities.cities[_city]["core_r"])
	var gate: Vector2 = (_cities.cities[_city]["gates"] as Array)[0]["pos"]
	_cam = Camera3D.new()
	_cam.fov = 60.0
	w.add_child(_cam)
	_cam.current = true
	_shots = [
		{"name": "aerial", "pos": Vector3(R * 1.9, R * 1.6, R * 2.3), "look": Vector3(0, 0, 0), "hour": 12.0},
		{"name": "gate", "pos": Vector3(gate.x * 1.25, 1.7, gate.y * 1.25), "look": Vector3(gate.x * 0.4, 3.0, gate.y * 0.4), "hour": 12.0},
		{"name": "square", "pos": Vector3(24.0, 4.0, 30.0), "look": Vector3(0, 2.0, 0), "hour": 12.0},
		{"name": "street_night", "pos": Vector3(gate.x * 0.7, 1.7, gate.y * 0.7), "look": Vector3(0, 2.0, 0), "hour": 22.5},
		{"name": "aerial_night", "pos": Vector3(R * 1.4, R * 1.2, R * 1.7), "look": Vector3(0, 0, 0), "hour": 22.5},
	]


func _process(_delta: float) -> bool:
	_frame += 1
	var idx := int(floorf(float(_frame) / 6.0))
	if idx >= _shots.size():
		return true
	var s: Dictionary = _shots[idx]
	if _frame % 6 == 1:
		_cam.position = s["pos"]
		_cam.look_at(s["look"], Vector3.UP)
		_cities.set_hour(float(s["hour"]))
		var env: WorldEnvironment = root.get_node("World").get_child(2)
		var night := float(s["hour"]) > 19.0
		env.environment.ambient_light_energy = 0.12 if night else 0.9
		(root.get_node("World").get_child(1) as DirectionalLight3D).light_energy = 0.05 if night else 1.2
		env.environment.background_mode = Environment.BG_COLOR if night else Environment.BG_SKY
		env.environment.background_color = Color(0.03, 0.04, 0.08)
	if _frame % 6 == 5:
		var img := root.get_viewport().get_texture().get_image()
		var path := _out.path_join("city_%s_%s.png" % [_city.to_lower().replace(" ", "_"), s["name"]])
		var err := img.save_png(path)
		print("shot ", path, " → ", err, " ", img.get_size())
		_shot += 1
	return false
