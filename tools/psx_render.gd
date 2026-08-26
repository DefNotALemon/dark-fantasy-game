extends SceneTree

## ===========================================================================
## Renders the PSX forest so the swap can be LOOKED AT, not just asserted.
##
##   godot --path . --rendering-driver opengl3 --script res://tools/psx_render.gd
##
## Writes previews/*.png: the tree line, the four seasons off one uniform, the
## understory floor, and a tree in the middle of shedding its canopy.
## ===========================================================================

const OUT := "res://previews/"
const W := 1600
const H := 720

var _f := 0
var _shots: Array = []
var _idx := 0
var _wait_f := 0
var _pending := ""
var _cam: Camera3D
var _sun: DirectionalLight3D
var _stage_root: Node3D


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))


func _process(_d: float) -> bool:
	## No `await` in here. A SceneTree._process that awaits returns a coroutine
	## object instead of a bool, Godot reads that as "true", and the whole run
	## quits on frame one having rendered nothing.
	_f += 1
	if _f == 2:
		_build()
		return false
	if _f < 6:
		return false
	if _wait_f > 0:
		_wait_f -= 1
		return false
	if _pending != "":
		var img := root.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path(OUT + _pending + ".png"))
		print("wrote ", _pending, ".png  ", img.get_width(), "x", img.get_height())
		_pending = ""
		return false
	if _idx >= _shots.size():
		quit(0)
		return true
	var shot: Dictionary = _shots[_idx]
	_idx += 1
	_apply(shot)
	_pending = String(shot["name"])
	_wait_f = 5
	return false


## ------------------------------------------------------------------ scene ---

func _build() -> void:
	root.get_window().size = Vector2i(W, H)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.46, 0.55, 0.63)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.52, 0.60, 0.70)
	e.ambient_light_energy = 0.55
	e.fog_enabled = true
	e.fog_light_color = Color(0.55, 0.62, 0.68)
	e.fog_density = 0.007
	env.environment = e
	root.add_child(env)

	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-46, 38, 0)
	_sun.light_energy = 1.55
	_sun.light_color = Color(1.0, 0.95, 0.86)
	_sun.shadow_enabled = true
	root.add_child(_sun)

	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.current = true

	## Wind.gd owns the six globals every one of these shaders reads.
	var wind := Wind.new()
	root.add_child(wind)

	_stage_root = Node3D.new()
	root.add_child(_stage_root)

	_shots = [
		{"name": "psx_treeline", "build": "line", "cam": Vector3(0, 3.0, 30.0),
		 "look": Vector3(0, 5.0, 0), "season": 0.38},
		{"name": "psx_season_spring", "build": "grove", "cam": Vector3(0, 3.4, 26.0),
		 "look": Vector3(0, 5.0, 0), "season": 0.10},
		{"name": "psx_season_summer", "build": "keep", "cam": Vector3(0, 3.4, 26.0),
		 "look": Vector3(0, 5.0, 0), "season": 0.36},
		{"name": "psx_season_autumn", "build": "keep", "cam": Vector3(0, 3.4, 26.0),
		 "look": Vector3(0, 5.0, 0), "season": 0.62},
		{"name": "psx_season_winter", "build": "keep", "cam": Vector3(0, 3.4, 26.0),
		 "look": Vector3(0, 5.0, 0), "season": 0.86},
		{"name": "psx_floor", "build": "floor", "cam": Vector3(0, 1.55, 7.5),
		 "look": Vector3(0, 0.9, 0), "season": 0.36},
		{"name": "psx_shed", "build": "shed", "cam": Vector3(7.5, 4.6, 13.5),
		 "look": Vector3(0.5, 3.4, 0), "season": 0.42},
	]


func _apply(shot: Dictionary) -> void:
	RenderingServer.global_shader_parameter_set("season_phase", float(shot["season"]))
	if String(shot["build"]) != "keep":
		for c in _stage_root.get_children():
			c.free()
		match String(shot["build"]):
			"line": _stage_line()
			"grove": _stage_grove()
			"floor": _stage_floor()
			"shed": _stage_shed()
	_cam.position = shot["cam"]
	_cam.look_at(shot["look"], Vector3.UP)


func _ground(size := 90.0) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	pm.subdivide_width = 24
	pm.subdivide_depth = 24
	mi.mesh = pm
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/psx_ground.gdshader")
	var stops: Array = PSXNature.region_atlases("temperate")
	sm.set_shader_parameter("floor_warm", _tex(String(stops[1]), "ForestFloor"))
	sm.set_shader_parameter("floor_cold", _tex(String(stops[3]), "ForestFloor"))
	sm.set_shader_parameter("soil_tex", _tex(String(stops[1]), "Soil"))
	sm.set_shader_parameter("rock_tex", _tex(String(stops[1]), "RockGround"))
	mi.material_override = sm
	_stage_root.add_child(mi)


func _tex(biome: String, sheet: String) -> Texture2D:
	var p := "res://assets/psx_nature/textures/%s/T_%s_%s_BaseColor.png" % [biome, biome, sheet]
	return load(p) if ResourceLoader.exists(p) else null


func _tree(species: String, stage: int, at: Vector3, rng: RandomNumberGenerator,
		dead := false, sc := 1.0) -> TreeV2:
	var t := TreeV2.new()
	t.species = species
	t.stage = stage
	t.dead = dead
	t.scale_class = sc
	t.tree_seed = rng.randi()
	t.position = at
	t.rotation.y = rng.randf() * TAU
	_stage_root.add_child(t)
	return t


func _prop(asset: String, at: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	_stage_root.add_child(PSXProp.make(asset, at, rng.randf() * TAU, s))


func _scatter_floor(rng: RandomNumberGenerator, n: int, r: float) -> void:
	## Stand-in for Understory: the same meshes and materials, placed by hand
	## because the real one samples a voxel field this scene does not have.
	## Weighted the way Understory.LAYERS weights them: mostly plants, a good
	## share of ferns, the occasional pebble. An even draw made the floor read
	## as a patio.
	var by := {}
	for i in range(n):
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * r
		var roll := rng.randf()
		var pool: Array = PSXNature.PLANTS
		var s := rng.randf_range(0.55, 1.15)
		if roll > 0.94:
			pool = Understory.SMALL_ROCKS
			s = rng.randf_range(0.35, 0.8)
		elif roll > 0.90:
			pool = PSXNature.SHRUBS
			s = rng.randf_range(0.4, 0.9)
		elif roll > 0.58:
			pool = PSXNature.FERNS
			s = rng.randf_range(0.6, 1.3)
		var asset: String = pool[rng.randi() % pool.size()]
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s),
			Vector3(cos(a) * d, -0.02, sin(a) * d))
		if not by.has(asset):
			by[asset] = ([] as Array[Transform3D])
		(by[asset] as Array[Transform3D]).append(t)
	for asset: String in by:
		var wood := PSXNature.ROCKS.has(asset)
		var mesh := PSXNature.mesh_for(asset, "Trunk" if wood else "Foliage")
		if mesh == null:
			continue
		var mmi := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		var list: Array[Transform3D] = by[asset]
		mm.instance_count = list.size()
		for i in range(list.size()):
			mm.set_instance_transform(i, list[i])
		mmi.multimesh = mm
		mmi.material_override = PSXNature.materials(
			String(PSXNature.info(asset).get("atlas", "Props")), "temperate", false)[1 if not wood else 0]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_stage_root.add_child(mmi)


func _stage_line() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7717
	_ground()
	var row := [["maple", 2], ["birch", 2], ["oak", 3], ["pine", 2], ["fir", 2],
		["pine", 4], ["maple", 1], ["fir", 3]]
	var x := -19.0
	for e in row:
		_tree(String(e[0]), int(e[1]), Vector3(x, 0, 0), rng)
		x += 5.4
	_tree("pine", 3, Vector3(9.0, 0, -13.0), rng, false, 4.0)   ## a GREAT tree behind
	_scatter_floor(rng, 2600, 24.0)


func _stage_grove() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	_ground()
	## groves, the way World._build_forest lays them
	var last := Vector3(0, 0, -6)
	for i in range(46):
		var pos: Vector3
		if rng.randf() < 0.76:
			var a := rng.randf() * TAU
			var r := rng.randf_range(2.6, 6.5)
			pos = last + Vector3(cos(a) * r, 0, sin(a) * r)
		else:
			pos = Vector3(rng.randf_range(-22, 22), 0, rng.randf_range(-26, 4))
		if pos.length() > 30.0 or absf(pos.x) > 24.0:
			continue
		last = pos
		var sp: String = ["maple", "birch", "oak", "pine", "fir"][rng.randi() % 5]
		var st := 2 if rng.randf() < 0.7 else 3
		var dead := rng.randf() < 0.06
		_tree(sp, st, pos, rng, dead)
	_prop("SM_FallenLog_Large", Vector3(-6.0, 0, 4.5), rng, 0.9)
	_prop("SM_Stump_01", Vector3(3.4, 0, 6.0), rng, 1.1)
	_prop("SM_Rock_05", Vector3(8.0, 0, 3.0), rng, 1.1)
	_scatter_floor(rng, 5200, 30.0)


func _stage_floor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	_ground(40.0)
	_scatter_floor(rng, 4200, 14.0)
	_prop("SM_FallenLog_Small", Vector3(-2.6, 0, -1.0), rng, 1.0)
	_prop("SM_Rock_07", Vector3(2.9, 0, -2.4), rng, 0.9)
	_prop("SM_Stump_02", Vector3(1.2, 0, 1.4), rng, 1.2)
	for i in range(7):
		_tree(["maple", "pine", "fir"][i % 3], 2, Vector3(rng.randf_range(-14, 14), 0,
			rng.randf_range(-16, -6)), rng)


func _stage_shed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	_ground()
	_scatter_floor(rng, 1500, 22.0)
	for i in range(9):
		_tree(["maple", "oak", "pine"][i % 3], 2,
			Vector3(rng.randf_range(-18, 18), 0, rng.randf_range(-22, -6)), rng)
	## The one that is going over.
	var t := _tree("maple", 2, Vector3(0, 0, 0), rng)
	var model: Node3D = null
	for c in t.get_children():
		if c is Node3D and not (c is CollisionShape3D):
			model = c
	var burst := LeafBurst.spawn_from(model, "Trees", "temperate", _stage_root, 130)
	if burst != null:
		burst._t = LeafBurst.LIFETIME * 0.34
		burst._mat.set_shader_parameter("fall_t", 0.34)
	## and the trunk already on its way down
	model.rotation.z = deg_to_rad(-38.0)
	var leaf := PSXNature.materials("Trees", "temperate", false)[1].duplicate() as ShaderMaterial
	leaf.set_shader_parameter("shed", 0.62)
	for n in _walk(model):
		var mi := n as MeshInstance3D
		if mi != null and mi.name.begins_with("Foliage"):
			mi.set_surface_override_material(0, leaf)


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out
