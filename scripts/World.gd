extends Node3D
## Forest test world for the vertical slice. Builds everything in code so there
## are no fragile scene-wiring dependencies: atmosphere, ground (with cave entry
## holes cut into it), a scattered low-poly forest, procedural caves, the player,
## and a few roaming enemies. Also runs the underground ambience shift and the
## "Now Entering"-style location titles.

const WORLD_RADIUS := 80.0
const TREE_COUNT := 140
const ROCK_COUNT := 14
const SPAWN_CLEAR := 7.0  ## keep trees/rocks away from the player spawn
const CAVE_COUNT := 2

## Surface / underground atmosphere targets.
const BASE_FOG := 0.018
const BASE_AMBIENT := 0.45
const BASE_FOG_COLOR := Color(0.42, 0.48, 0.46)
const CAVE_FOG := 0.05
const CAVE_AMBIENT := 0.10
const CAVE_FOG_COLOR := Color(0.05, 0.07, 0.08)
const TITLE_TIME := 3.0

var _rng := RandomNumberGenerator.new()
var _cave_sites: Array[Dictionary] = []  ## {mouth: Vector3, dir: Vector3, rect: Rect2}
var _env: Environment
var _daynight: DayNight
var _player: Player
var _underground := false
var _title_label: Label
var _title_timer := 0.0
var _ambient_scale := 1.0  ## RT lighting trades flat ambient for bounced light


func _ready() -> void:
	add_to_group("world")  ## the settings menu finds the lighting through this
	_rng.seed = 20260630  ## fixed seed = same world each run (change for variety)
	_build_environment()
	_pick_cave_sites()
	_build_ground()
	_build_forest()
	_build_rocks()
	_build_caves()
	_spawn_player()
	_spawn_enemies()
	_build_titles()


func _process(delta: float) -> void:
	if _player == null or _env == null:
		return

	## Safety net: fell out of the world somehow — back to the spawn.
	if _player.global_position.y < -40.0:
		_player.global_position = Vector3(0, 2, 0)
		_player.velocity = Vector3.ZERO

	## Underground detection drives the ambience shift + location titles.
	var below := _player.global_position.y < -3.0
	if below != _underground:
		_underground = below
		_show_title("The Hollow Depths" if below else "The Dusk Forest")

	## Surface targets ride the day/night clock; the caves ignore the sky.
	var want_ambient := CAVE_AMBIENT if _underground else (_daynight.surf_ambient if _daynight else BASE_AMBIENT)
	var want_fog_col := CAVE_FOG_COLOR if _underground else (_daynight.surf_fog if _daynight else BASE_FOG_COLOR)
	var k := 1.0 - pow(0.15, delta)  ## framerate-independent smoothing
	_env.fog_density = lerpf(_env.fog_density, CAVE_FOG if _underground else BASE_FOG, k)
	_env.ambient_light_energy = lerpf(_env.ambient_light_energy, want_ambient * _ambient_scale, k)
	_env.fog_light_color = _env.fog_light_color.lerp(want_fog_col, k)

	## Title fade: quick in, hold, ease out.
	if _title_timer > 0.0:
		_title_timer -= delta
		var a := clampf(minf((TITLE_TIME - _title_timer) * 3.0, _title_timer), 0.0, 1.0)
		_title_label.modulate = Color(1, 1, 1, a)
	elif _title_label and _title_label.modulate.a > 0.0:
		_title_label.modulate = Color(1, 1, 1, 0)


func _build_environment() -> void:
	var env := Environment.new()

	## Moody dusk sky with a green-tinged horizon.
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.12, 0.16, 0.24)
	sky_mat.sky_horizon_color = Color(0.40, 0.42, 0.40)
	sky_mat.ground_horizon_color = Color(0.22, 0.26, 0.22)
	sky_mat.ground_bottom_color = Color(0.08, 0.10, 0.09)
	sky.sky_material = sky_mat
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = BASE_AMBIENT

	## Forest fog for depth and atmosphere (thickens underground).
	env.fog_enabled = true
	env.fog_light_color = BASE_FOG_COLOR
	env.fog_density = BASE_FOG

	## Subtle tonemap so the vibrant accents read without blowing out.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_env = env

	## The sky's clock owns the sun and moon now — a full Skyrim-pace day/night
	## cycle (20 real minutes per game day). It publishes the surface ambience
	## targets that _process lerps toward; underground still wins down there.
	_daynight = DayNight.new()
	_daynight.env = env
	_daynight.sky_mat = sky_mat
	_daynight.title_cb = _on_sky_title
	add_child(_daynight)


## ====================== Graphics settings (Esc menu) ======================


func set_rt_lighting(on: bool) -> void:
	## The "Ray-Traced Lighting" option. Godot has no hardware RT; this is its
	## real-time equivalent stacked into one preset: SDFGI (ray-marched global
	## illumination — sunlight genuinely bounces off the world), screen-space
	## indirect light + AO + reflections, volumetric fog (dawn shafts through
	## the trees), and glow (elemental blades and crystals bloom). Flat ambient
	## steps back so the bounced light does the talking.
	if _env == null:
		return
	_env.sdfgi_enabled = on
	_env.sdfgi_use_occlusion = true
	_env.sdfgi_bounce_feedback = 0.4
	_env.sdfgi_read_sky_light = true
	_env.ssil_enabled = on
	_env.ssao_enabled = on
	_env.ssr_enabled = on
	_env.ssr_max_steps = 48
	_env.glow_enabled = on
	_env.glow_intensity = 0.55
	_env.glow_bloom = 0.05
	_env.volumetric_fog_enabled = on
	_env.volumetric_fog_density = 0.02
	_env.volumetric_fog_anisotropy = 0.55  ## light shafts lean toward the sun
	_ambient_scale = 0.55 if on else 1.0


func set_shadow_quality(level: int) -> void:
	## 0 Low / 1 Medium / 2 High — atlas sizes + soft-shadow filtering for the
	## sun/moon and every torch and crystal.
	var idx := clampi(level, 0, 2)
	var sizes: Array[int] = [2048, 4096, 8192]
	var quals: Array[int] = [
		RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
		RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
	]
	get_viewport().positional_shadow_atlas_size = sizes[idx]
	RenderingServer.directional_shadow_atlas_set_size(sizes[idx], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(quals[idx])
	RenderingServer.positional_soft_shadow_filter_set_quality(quals[idx])


## ============================ Caves + ground ==============================


func _pick_cave_sites() -> void:
	## Cave mouths sit out in the forest with their openings facing the spawn;
	## the entry tunnels dive OUTWARD (away from center), which keeps the two
	## cave networks naturally far apart. Each needs a hole cut into the ground
	## slab; the holes' x-ranges must not overlap (the slab is x-strips).
	var guard := 0
	while _cave_sites.size() < CAVE_COUNT and guard < 300:
		guard += 1
		var ang := _rng.randf() * TAU
		var rad := _rng.randf_range(30.0, 50.0)
		var mouth := Vector3(cos(ang) * rad, 0, sin(ang) * rad)
		var cdir := Vector3(signf(mouth.x), 0, 0) if absf(mouth.x) > absf(mouth.z) else Vector3(0, 0, signf(mouth.z))
		## The hole must reach until the tunnel's ceiling is fully below the slab
		## (~9.5m past the mouth at a ~30-degree descent).
		var rect: Rect2
		if cdir.x != 0.0:
			rect = Rect2(minf(mouth.x - cdir.x * 1.0, mouth.x + cdir.x * 10.0), mouth.z - 2.1, 11.0, 4.2)
		else:
			rect = Rect2(mouth.x - 2.1, minf(mouth.z - cdir.z * 1.0, mouth.z + cdir.z * 10.0), 4.2, 11.0)
		var first_chamber := mouth + cdir * 29.0
		var ok := true
		for site in _cave_sites:
			if mouth.distance_to(site.mouth) < 60.0:
				ok = false
			if first_chamber.distance_to((site.mouth as Vector3) + (site.dir as Vector3) * 29.0) < 45.0:
				ok = false  ## keep the underground networks well apart
			if rect.position.x < (site.rect as Rect2).end.x + 2.0 and rect.end.x > (site.rect as Rect2).position.x - 2.0:
				ok = false
		if ok:
			_cave_sites.append({"mouth": mouth, "dir": cdir, "rect": rect})


func _build_ground() -> void:
	## The ground slab, assembled from x-strips so each cave's entry hole is a
	## real opening (boxes can't be carved, so we tile around the holes).
	var w_half := WORLD_RADIUS * 1.3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.24, 0.14)  ## mossy forest floor
	mat.roughness = 1.0

	var holes: Array[Rect2] = []
	for site in _cave_sites:
		holes.append(site.rect as Rect2)
	holes.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.x < b.position.x)

	var xs: Array[float] = [-w_half]
	for h in holes:
		xs.append(h.position.x)
		xs.append(h.end.x)
	xs.append(w_half)

	for i in range(xs.size() - 1):
		var x0 := xs[i]
		var x1 := xs[i + 1]
		if x1 - x0 < 0.01:
			continue
		var hole := Rect2()
		var has_hole := false
		for h in holes:
			if h.position.x <= x0 + 0.01 and h.end.x >= x1 - 0.01:
				hole = h
				has_hole = true
				break
		if has_hole:
			_ground_slab(x0, x1, -w_half, hole.position.y, mat)
			_ground_slab(x0, x1, hole.end.y, w_half, mat)
		else:
			_ground_slab(x0, x1, -w_half, w_half, mat)


func _ground_slab(x0: float, x1: float, z0: float, z1: float, mat: StandardMaterial3D) -> void:
	var body := StaticBody3D.new()
	body.position = Vector3((x0 + x1) * 0.5, -1, (z0 + z1) * 0.5)
	add_child(body)
	var size := Vector3(x1 - x0, 2, z1 - z0)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = mat
	body.add_child(mesh)


func _build_caves() -> void:
	var occupied := {}  ## shared so the two cave networks can never overlap
	for i in range(_cave_sites.size()):
		var site := _cave_sites[i]
		var cave := Cave.new()
		cave.mouth = site.mouth
		cave.dir = site.dir
		cave.cave_seed = 4457 + i * 7919
		cave.occupied = occupied
		add_child(cave)


## =============================== Forest ===================================


func _build_forest() -> void:
	for i in range(TREE_COUNT):
		var pos := _random_ground_point()
		if pos == Vector3.INF:
			continue
		add_child(_make_tree(pos))

func _make_tree(pos: Vector3) -> StaticBody3D:
	var tree := StaticBody3D.new()
	tree.position = pos
	tree.rotation.y = _rng.randf() * TAU

	var height := _rng.randf_range(3.5, 7.0)
	var trunk_r := _rng.randf_range(0.18, 0.30)

	## Trunk (low-poly cylinder).
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = trunk_r * 0.7
	tm.bottom_radius = trunk_r
	tm.height = height
	tm.radial_segments = 6
	trunk.mesh = tm
	trunk.position = Vector3(0, height * 0.5, 0)
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.22, 0.15, 0.10).lerp(Color(0.30, 0.20, 0.13), _rng.randf())
	trunk_mat.roughness = 1.0
	trunk.material_override = trunk_mat
	tree.add_child(trunk)

	## Foliage: 3 stacked faceted cones for a low-poly conifer.
	var foliage_mat := StandardMaterial3D.new()
	foliage_mat.albedo_color = Color(0.10, 0.26, 0.13).lerp(Color(0.16, 0.34, 0.18), _rng.randf())
	foliage_mat.roughness = 1.0
	var layers := 3
	for l in range(layers):
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		var t := float(l) / float(layers - 1)
		cm.top_radius = 0.0
		cm.bottom_radius = lerp(2.0, 0.7, t) * _rng.randf_range(0.9, 1.1)
		cm.height = 2.0
		cm.radial_segments = 6
		cone.mesh = cm
		cone.material_override = foliage_mat
		cone.position = Vector3(0, height * 0.62 + l * 1.35, 0)
		tree.add_child(cone)

	## Collision so you can't walk through trunks.
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = max(0.4, trunk_r + 0.15)
	cap.height = height
	col.shape = cap
	col.position = Vector3(0, height * 0.5, 0)
	tree.add_child(col)

	return tree

func _build_rocks() -> void:
	for i in range(ROCK_COUNT):
		var pos := _random_ground_point()
		if pos == Vector3.INF:
			continue
		var rock := StaticBody3D.new()
		rock.position = pos
		add_child(rock)
		var s := _rng.randf_range(0.8, 2.4)
		var col := CollisionShape3D.new()
		var bshape := BoxShape3D.new()
		bshape.size = Vector3(s, s * 1.2, s)
		col.shape = bshape
		col.position = Vector3(0, s * 0.6, 0)
		rock.add_child(col)
		var mesh := MeshInstance3D.new()
		var bmesh := BoxMesh.new()
		bmesh.size = Vector3(s, s * 1.2, s)
		mesh.mesh = bmesh
		mesh.position = Vector3(0, s * 0.6, 0)
		mesh.rotation_degrees = Vector3(_rng.randf_range(-12, 12), _rng.randf_range(0, 360), _rng.randf_range(-12, 12))
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.16, 0.18, 0.20)
		mat.roughness = 1.0
		mesh.material_override = mat
		rock.add_child(mesh)

func _random_ground_point() -> Vector3:
	## Returns a random point inside the world disc, clear of the spawn and of
	## every cave mouth / entry gully, or INF if none was found.
	for _attempt in range(8):
		var ang := _rng.randf() * TAU
		var rad := sqrt(_rng.randf()) * WORLD_RADIUS
		var pos := Vector3(cos(ang) * rad, 0, sin(ang) * rad)
		if pos.length() < SPAWN_CLEAR:
			continue
		var clear := true
		for site in _cave_sites:
			var m := site.mouth as Vector3
			var d := site.dir as Vector3
			var t := clampf((pos - m).dot(d), -4.0, 28.0)
			if pos.distance_to(m + d * t) < 8.0:
				clear = false
				break
		if clear:
			return pos
	return Vector3.INF


## ============================ Titles + spawns ==============================


func _build_titles() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 34)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.anchor_left = 0.0
	_title_label.anchor_right = 1.0
	_title_label.offset_top = 84.0
	_title_label.offset_bottom = 140.0
	_title_label.modulate = Color(1, 1, 1, 0)
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_title_label)


func _show_title(text: String) -> void:
	if _title_label == null:
		return
	_title_label.text = text
	_title_timer = TITLE_TIME


func _spawn_player() -> void:
	_player = Player.new()
	_player.position = Vector3(0, 2, 0)
	add_child(_player)

func _spawn_enemies() -> void:
	## Only boars and horses roam the overworld — every hostile creature spawns
	## in packs down in the caves (see Cave._spawn_dwellers).
	for _i in range(_rng.randi_range(4, 6)):
		var e := Boar.new()
		var ang := _rng.randf() * TAU
		var rad := _rng.randf_range(16.0, 40.0)
		e.position = Vector3(cos(ang) * rad, 2, sin(ang) * rad)
		add_child(e)
	_spawn_horses()


func _spawn_horses() -> void:
	## Step 6 (passive wildlife) first pass. Two saddled mounts graze the
	## meadow near the spawn — yours for as long as you never hurt one — and a
	## couple of wild herds keep to the far tree line and bolt on approach.
	for _i in range(2):
		var h := SaddledHorse.new()
		var ang := _rng.randf() * TAU
		var rad := _rng.randf_range(10.0, 16.0)
		h.position = Vector3(cos(ang) * rad, 2, sin(ang) * rad)
		h.rotation.y = _rng.randf() * TAU
		add_child(h)
	for _herd in range(2):
		var center := Vector3.INF
		for _attempt in range(10):
			var p := _random_ground_point()
			if p != Vector3.INF and p.length() > 24.0:
				center = p
				break
		if center == Vector3.INF:
			continue
		for _i in range(_rng.randi_range(3, 4)):
			var w := Horse.new()
			w.position = center + Vector3(_rng.randf_range(-4.0, 4.0), 2, _rng.randf_range(-4.0, 4.0))
			w.rotation.y = _rng.randf() * TAU
			add_child(w)


func _on_sky_title(text: String) -> void:
	## Daybreak / Nightfall banners — only where you can actually see the sky.
	if not _underground:
		_show_title(text)
