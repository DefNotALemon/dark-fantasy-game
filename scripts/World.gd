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
	_build_blackout()  ## FIRST: the world builds behind a black curtain
	_build_environment()
	_pick_cave_sites()
	_build_ground()
	_build_forest()
	_build_rocks()
	_build_caves()
	_build_border()
	_build_camp()
	_spawn_player()
	_spawn_enemies()
	_build_titles()
	## Hold the curtain (and the player's hands) until the deep + content are
	## fully real — no first-minute lag spikes reach the eye.
	if _player:
		_player.input_locked = true


func _process(delta: float) -> void:
	if _player == null or _env == null:
		return

	## Safety net: fell out of the world somehow — OR ended up beyond the
	## border walls (old saves, climb edge cases) — back to the spawn.
	if _player.global_position.y < -40.0 \
			or absf(_player.global_position.x) > 103.5 or absf(_player.global_position.z) > 103.5:
		_player.global_position = Vector3(0, 2, 0)
		_player.velocity = Vector3.ZERO

	## And never trapped INSIDE the rock (slipped through some sliver into
	## the space between caves): a full second buried = pulled home.
	if _region != null and _region.is_fully_loaded() and _player.global_position.y < 0.0 \
			and _region.field.is_rock(_player.global_position + Vector3.UP * 0.9):
		_in_rock_t += delta
		if _in_rock_t > 1.0:
			_in_rock_t = 0.0
			_player.global_position = Vector3(0, 2, 0)
			_player.velocity = Vector3.ZERO
			_show_title("The earth spat you out")
	else:
		_in_rock_t = 0.0

	## Underground detection still fires the location titles (a threshold is
	## right for an EVENT)...
	var below := _player.global_position.y < -3.0
	if below != _underground:
		_underground = below
		_show_title("The Hollow Depths" if below else "The Dusk Forest")

	## ...but the LIGHT never flips at a line: it rides DEPTH. Descending a
	## throat dims by the meter — full daylight above -1.2, full cave gloom by
	## -8.5, smoothstepped between — so the dark closes over you the way deep
	## water does, and climbing out returns the sky shade by shade. A gentle
	## ease then chases that blend, so even a straight fall down a shaft
	## never snaps the eye. Surface targets still ride the day/night clock.
	var depth_u := clampf((-1.2 - _player.global_position.y) / 7.3, 0.0, 1.0)
	depth_u = depth_u * depth_u * (3.0 - 2.0 * depth_u)
	var s_amb := _daynight.surf_ambient if _daynight else BASE_AMBIENT
	var s_fog_col := _daynight.surf_fog if _daynight else BASE_FOG_COLOR
	var want_ambient := lerpf(s_amb, CAVE_AMBIENT, depth_u)
	var want_fog := lerpf(BASE_FOG, CAVE_FOG, depth_u)
	var want_fog_col := s_fog_col.lerp(CAVE_FOG_COLOR, depth_u)
	var k := 1.0 - pow(0.30, delta)  ## framerate-independent smoothing (unhurried)
	_env.fog_density = lerpf(_env.fog_density, want_fog, k)
	_env.ambient_light_energy = lerpf(_env.ambient_light_energy, want_ambient * _ambient_scale, k)
	_env.fog_light_color = _env.fog_light_color.lerp(want_fog_col, k)
	## Underground the sky goes DARK — the heavy cave fog fully covers it, so
	## any glimpse of sky through a crack reads as gloom, not blue daylight.
	## The brightness at a mouth comes from its own light shaft (god rays,
	## CaveRegion._dress_mouth), not from the sky peeking through the fog.
	_env.fog_sky_affect = lerpf(_env.fog_sky_affect, 1.0, k)

	## Startup curtain: lift it only when the whole underground (and its
	## content) is genuinely finished — the game begins already smooth.
	if _loading and _region != null and _region.is_fully_loaded():
		_loading = false
		set_blackout(false, "")
		if _player and _player.sleep_phase == "":
			_player.input_locked = false

	## Random events: now and then, the sky lets something go.
	_meteor_t += delta
	if _next_meteor <= 0.0:
		_next_meteor = _rng.randf_range(180.0, 320.0)  ## first star mid-session
	elif _meteor_t >= _next_meteor:
		_meteor_t = 0.0
		_next_meteor = _rng.randf_range(260.0, 460.0)
		drop_meteor()

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
	## the throats dive OUTWARD (away from center). The underground itself is
	## ONE map-wide voxel field now — mouths are just entrances into it, so
	## the only rule left is breathing room between them.
	var guard := 0
	while _cave_sites.size() < CAVE_COUNT and guard < 400:
		guard += 1
		var ang := _rng.randf() * TAU
		var rad := _rng.randf_range(30.0, 44.0)
		var mouth := Vector3(cos(ang) * rad, 0, sin(ang) * rad)
		var cdir := Vector3(signf(mouth.x), 0, 0) if absf(mouth.x) > absf(mouth.z) else Vector3(0, 0, signf(mouth.z))
		var ok := true
		for site in _cave_sites:
			if mouth.distance_to(site.mouth) < 60.0:
				ok = false
		if ok:
			_cave_sites.append({"mouth": mouth, "dir": cdir})


func _build_ground() -> void:
	## RETIRED as a slab: the map-wide CaveRegion's grass-skinned top IS the
	## ground now (one surface, no borders, no seams, diggable anywhere).
	## Nothing to build here — kept as a hook for future surface work.
	pass


var _region: CaveRegion = null  ## THE underground — one field under the whole map
var _meteor_t := 0.0            ## random event clock: falling stars
var _next_meteor := 0.0
var _loading := true            ## startup curtain still down
var _in_rock_t := 0.0           ## seconds the player's head has been in solid rock
var _blackout: ColorRect
var _black_label: Label


func _build_blackout() -> void:
	## The loading curtain: pure black, over EVERYTHING (layer 80), with a
	## quiet line of text. Used at startup and while sleep shifts the deep.
	var layer := CanvasLayer.new()
	layer.layer = 80
	add_child(layer)
	_blackout = ColorRect.new()
	_blackout.color = Color(0, 0, 0, 1)
	_blackout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_blackout)
	_black_label = Label.new()
	_black_label.text = "The Withering"
	_black_label.add_theme_font_size_override("font_size", 30)
	_black_label.modulate = Color(0.75, 0.78, 0.85, 0.85)
	_black_label.set_anchors_preset(Control.PRESET_CENTER)
	_black_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_blackout.add_child(_black_label)


func set_blackout(on: bool, text := "") -> void:
	if _blackout == null:
		return
	if text != "":
		_black_label.text = text
	if on:
		_blackout.visible = true
		_blackout.modulate = Color(1, 1, 1, 0.0)
		var tw := create_tween()
		tw.tween_property(_blackout, "modulate:a", 1.0, 0.3)
	else:
		var tw := create_tween()
		tw.tween_property(_blackout, "modulate:a", 0.0, 0.7)
		tw.tween_callback(func() -> void: _blackout.visible = false)


func is_world_ready() -> bool:
	return _region != null and _region.is_fully_loaded()


func drop_meteor() -> void:
	## A STAR FALLS (random event, also the M-menu dev button): picks a spot
	## away from the player and the permanent caves, streaks a burning light
	## down the sky, and hands the impact to the region — crater + a fused
	## BALL of meteoric ore in the middle (Terraria's gift, our way).
	var spot := Vector3.INF
	for _try in range(40):
		var ang := _rng.randf() * TAU
		var rad := sqrt(_rng.randf()) * (WORLD_RADIUS - 8.0)
		var p := Vector3(cos(ang) * rad, 0, sin(ang) * rad)
		if _player and p.distance_to(_player.global_position) < 30.0:
			continue  ## never on your head — it lands "off screen"
		var ok := true
		for site in _cave_sites:
			if p.distance_to(site.mouth as Vector3) < 28.0:
				ok = false  ## clear of the permanent caves
		if ok:
			spot = p
			break
	if spot == Vector3.INF:
		return
	## The fall is a PERFORMANCE now (MeteorFall.gd): a burning point ignites
	## high over the map — visible day or night, dimmer against daylight —
	## drifts down for ~23 s trailing pixel embers, then dives hard into the
	## ground. The title fires at IGNITION so there's time to look up.
	var m := MeteorFall.new()
	m.target = spot
	m.world = self
	add_child(m)
	if _player:
		_player.call("_add_log_msg", "Something burns in the sky to the %s..."
			% _compass(spot - _player.global_position), Color(1.0, 0.72, 0.38))
	_show_title("A Star Falls")


func _meteor_impact(spot: Vector3, streak: Node3D) -> void:
	if is_instance_valid(streak):
		streak.queue_free()
	if _region == null or not _region.meteor_strike(spot):
		_next_meteor = 15.0  ## ground busy (deep threads) — the sky tries again shortly
		_meteor_t = 0.0
		return
	if _player:
		var d := _player.global_position.distance_to(spot)
		_player.cam_shake = maxf(float(_player.cam_shake), clampf(0.62 - d * 0.004, 0.12, 0.62))
		_player.call("_add_log_msg", "The star has fallen to the %s!" % _compass(spot - _player.global_position),
			Color(1.0, 0.62, 0.28))


func _compass(v: Vector3) -> String:
	var a := fposmod(rad_to_deg(atan2(-v.x, v.z)) + 22.5, 360.0)
	return ["south", "south-west", "west", "north-west", "north", "north-east", "east", "south-east"][int(a / 45.0) % 8]


func is_dark_out() -> bool:
	## Underground, or night on the surface — anywhere a torch earns its keep.
	## The player's darkness watch (auto-torch) asks this every frame.
	return _underground or (_daynight != null and _daynight.is_night())


func spawn_cave_at(mouth: Vector3, cdir: Vector3) -> bool:
	## Tear a brand-new cave mouth open at runtime (M-menu dev button today;
	## DESIGN.MD's "caves open up in the earth over time" tomorrow). The
	## underground is one map-wide field now — a new mouth is just carved
	## straight into it, no ground surgery needed.
	mouth.y = 0.0
	if cdir.length_squared() < 0.5:
		cdir = Vector3(1, 0, 0)
	if _region == null:
		return false
	if absf(mouth.x) > 88.0 or absf(mouth.z) > 88.0:
		return false  ## too near the world's edge
	for site in _cave_sites:
		if mouth.distance_to(site.mouth as Vector3) < 30.0:
			return false  ## crowding an existing entrance
	if not _region.add_mouth(mouth, cdir):
		return false  ## deep threads mid-write — try again in a breath
	_cave_sites.append({"mouth": mouth, "dir": cdir})
	## The earth does not open politely (DESIGN.md: earthquake feedback).
	if _player:
		_player.cam_shake = maxf(float(_player.cam_shake), 0.5)
	_show_title("The World Has Shifted")
	return true


func _build_camp() -> void:
	## Your bedroll starts placed by the spawn clearing. F = sleep; look + E
	## packs it into the backpack; click the item in the inventory to put it
	## down anywhere (Bedroll.gd).
	var bed := Bedroll.new()
	add_child(bed)
	bed.global_position = Vector3(2.8, 0.0, 2.4)
	bed.rotation.y = deg_to_rad(24.0)


func sleep_at_bed() -> bool:
	## Sleep until dawn — and the earth USES the night: the whole underground
	## reseeds and re-carves (except the permanent caves around each mouth).
	## False if the previous build/shift is still running.
	if _region == null or not _region.reset_underground():
		return false
	if _daynight:
		_daynight.hour = 6.0  ## dawn
	if _player:
		_player.cam_shake = maxf(float(_player.cam_shake), 0.4)
	_show_title("The World Has Shifted")
	return true


func _build_border() -> void:
	## INVISIBLE border walls just inside the mesh edge: collision only, no
	## mesh — you cannot walk, fall, mantle, or be thrown out of the map.
	## Tall enough that no climb ever finds their top.
	var half := 103.0
	for w in [[Vector3(half, 10, 0), Vector3(2, 120, half * 2 + 4)],
			[Vector3(-half, 10, 0), Vector3(2, 120, half * 2 + 4)],
			[Vector3(0, 10, half), Vector3(half * 2 + 4, 120, 2)],
			[Vector3(0, 10, -half), Vector3(half * 2 + 4, 120, 2)]]:
		var body := StaticBody3D.new()
		body.position = w[0]
		add_child(body)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = w[1]
		col.shape = shape
		body.add_child(col)


func _build_caves() -> void:
	## Caves 2.0 (docs/CAVES_PLAN.md): ONE map-wide CaveRegion — the organic
	## noise caves run under the entire world, its grass top IS the ground,
	## every mouth is an entrance into the same underground.
	## (Cave.gd, the old tube builder, is retired but kept on disk.)
	var cave := CaveRegion.new()
	for site in _cave_sites:
		cave.mouths.append(site.mouth as Vector3)
		cave.dirs.append(site.dir as Vector3)
	cave.cave_seed = 4457
	add_child(cave)
	_region = cave


## =============================== Forest ===================================


func _build_forest() -> void:
	for i in range(TREE_COUNT):
		var pos := _random_ground_point()
		if pos == Vector3.INF:
			continue
		add_child(_make_tree(pos))

func _make_tree(pos: Vector3) -> StaticBody3D:
	## Trees are real objects now (ChopTree.gd): the axe eats a wedge out of
	## the trunk, the trunk breaks at that wedge, the canopy comes apart on
	## impact and the trunk splits into logs. All of that lives with the tree.
	var tree := ChopTree.make(_rng)
	tree.position = pos
	tree.rotation.y = _rng.randf() * TAU
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
		## Mineable: the pickaxe chips it apart (Player._chop_boulder) —
		## bigger boulders take more bites and shed more stone.
		rock.add_to_group("boulders")
		rock.set_meta("bites", 2 + int(s * 1.2))
		rock.set_meta("size", s)
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
			## Keep the whole entrance mound + approach + walk-in clear.
			var t := clampf((pos - m).dot(d), -9.0, 28.0)
			if pos.distance_to(m + d * t) < 11.5:
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


## ============================== Save / load ================================
## What the surface remembers. The caves are their own question (CaveRegion
## saves a sphere of dug rock around wherever you were); up here it's the hour
## of the day, which trees are still standing and how deep the axe got into
## each one, where the logs and the loot came to rest, and every square of
## grass the sword has been through.


func save_state() -> Dictionary:
	var trees: Array = []
	for group in ["trees", "tree_stumps"]:
		for t in get_tree().get_nodes_in_group(group):
			if t is ChopTree:
				trees.append((t as ChopTree).save_dict())
	var logs: Array = []
	for l in get_tree().get_nodes_in_group("carry_logs"):
		if l is CarryLog:
			logs.append((l as CarryLog).save_dict())
	var dropped: Array = []
	for d in get_tree().get_nodes_in_group("dropped_items"):
		var di := d as DroppedItem
		if di != null:
			dropped.append({"item": di.item.duplicate(true), "pos": di.global_position})
	var beds: Array = []
	for b in get_tree().get_nodes_in_group("beds"):
		if b is Node3D:
			beds.append({"pos": (b as Node3D).global_position, "rot_y": (b as Node3D).rotation.y})
	var out := {
		"hour": _daynight.hour if _daynight else 17.0,
		"trees": trees, "logs": logs, "dropped": dropped, "beds": beds,
	}
	if _region != null:
		out["cave"] = _region.save_state()
		if _region.grass() != null:
			out["grass"] = _region.grass().save_state()
	return out


func apply_state(d: Dictionary) -> void:
	if _daynight:
		_daynight.hour = float(d.get("hour", 17.0))
	## Sweep the surface clean, then lay the saved one back down.
	for group in ["trees", "tree_stumps", "carry_logs", "dropped_items", "beds"]:
		for n in get_tree().get_nodes_in_group(group):
			(n as Node).queue_free()
	for td in d.get("trees", []):
		var t := ChopTree.from_dict(td as Dictionary)
		t.position = (td as Dictionary).get("pos", Vector3.ZERO)
		t.rotation.y = float((td as Dictionary).get("rot_y", 0.0))
		add_child(t)
	for ld in d.get("logs", []):
		var l := CarryLog.from_dict(ld as Dictionary)
		add_child(l)
		l.global_position = (ld as Dictionary).get("pos", Vector3.ZERO)
		l.rotation = (ld as Dictionary).get("rot", Vector3.ZERO)
	for dd in d.get("dropped", []):
		var di := DroppedItem.make(((dd as Dictionary).get("item", {}) as Dictionary).duplicate(true))
		add_child(di)
		di.global_position = (dd as Dictionary).get("pos", Vector3.ZERO)
	for bd in d.get("beds", []):
		var bed := Bedroll.new()
		add_child(bed)
		bed.global_position = (bd as Dictionary).get("pos", Vector3.ZERO)
		bed.rotation.y = float((bd as Dictionary).get("rot_y", 0.0))
	if _region != null:
		if _region.grass() != null and d.has("grass"):
			_region.grass().apply_state(d["grass"] as Dictionary)
		if d.has("cave") and _region.apply_state(d["cave"] as Dictionary):
			## The underground has to redraw itself from the saved seed and
			## take your dig back. Hold the curtain the same way startup does —
			## _process lifts it when the region is genuinely finished.
			_loading = true
			set_blackout(true, "Remembering the world...")
			if _player:
				_player.input_locked = true
