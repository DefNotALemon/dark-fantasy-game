class_name Weather
extends Node

## ===========================================================================
## The weather — scripts/Weather.gd
##
## Five levels, and the world walks between them on its own:
##
##   0 CLEAR     open sky, the sun does the work
##   1 OVERCAST  the deck closes in, colour drains, no rain
##   2 DRIZZLE   thin rain, quiet, everything goes wet
##   3 RAIN      real rain, splash, the sun is gone
##   4 STORM     black bellies, sheets of rain, wind at full, THUNDER
##
## Thunder only ever happens at STORM — that's the point of the ladder.
##
## In winter (season_phase 0.75+) precipitation falls as SNOW instead: slower,
## bigger, no splashes, no thunder.
##
## Everything it touches, it borrows:
##   SkyRig.gd   clouds, gloom, lightning flash, aurora
##   Wind.gd     .storm drives gusts to full
##   DayNight    the clock, and the day counter for seasons
##   Environment fog thickens with the weather
##
## All audio is SYNTHESISED at runtime — no .wav files to ship, no import step.
##
## Wired up by World.gd:
##     _weather = Weather.new()
##     _weather.env = env
##     _weather.sky = _sky
##     _weather.wind = _wind
##     _weather.daynight = _daynight
##     add_child(_weather)
## ===========================================================================

enum Level { CLEAR = 0, OVERCAST = 1, DRIZZLE = 2, RAIN = 3, STORM = 4 }

# ===========================================================================
#  NORTHERN LIGHTS — the knob Lemon asked for
# ===========================================================================
#  Every night, once, the sky rolls for an aurora. Keep it rare and it stays
#  a story ("I saw them on my third winter"). Set it to 1.0 and you get them
#  every clear night, which is what a personal build is for.
#
#      AURORA_CHANCE = 0.04   ->  ~1 night in 25   (shipping default)
#      AURORA_CHANCE = 1.00   ->  every clear night
#
#  Two more levers, same idea:
#      AURORA_WINTER_BONUS  winter multiplies the odds (real, and it's when
#                           you're outdoors at night anyway)
#      aurora_forced        set true from anywhere for an instant show
# ===========================================================================
const AURORA_CHANCE := 0.04           ## <-- CHANGE THIS ONE (0.0 .. 1.0)
const AURORA_WINTER_BONUS := 3.0      ## odds ×3 in winter, ×1.6 in autumn
const AURORA_MAX_CLOUD := 0.55        ## a closed sky hides them; storms never show
const AURORA_FADE := 90.0             ## seconds to bloom in / out
const AURORA_BRIGHTNESS := 0.85       ## peak strength when they do turn up

## Set this true anywhere (`get_node("/root/World/Weather").aurora_forced = true`)
## and they come up on the next nightfall regardless of the roll.
var aurora_forced := false

## Hard override, for the sky menu (' key) and the console: -1 hands the sky
## back to the nightly roll; 0..1 pins that strength right now, ignoring the
## hour, the roll and the cloud deck alike.
var aurora_override := -1.0

## --- pacing ----------------------------------------------------------------
const MIN_DWELL := 150.0              ## seconds a level holds before it may change
const MAX_DWELL := 900.0              ## 20-min game day, so this is up to ~3/4 of one
const TRANSITION := 25.0              ## seconds to slide between two levels

## Where the weather is likely to go next, per level. Rows are the current
## level, columns are CLEAR..STORM. Weather is sticky and mostly walks one
## rung at a time — Maine does not go from blue sky to thunder.
const TRANSITIONS := [
	[0.55, 0.35, 0.08, 0.02, 0.00],   ## from CLEAR
	[0.35, 0.30, 0.22, 0.11, 0.02],   ## from OVERCAST
	[0.10, 0.38, 0.24, 0.24, 0.04],   ## from DRIZZLE
	[0.03, 0.28, 0.34, 0.23, 0.12],   ## from RAIN
	[0.00, 0.22, 0.34, 0.34, 0.10],   ## from STORM
]

## Per-level look. coverage / darkness / gloom go to the sky, fog to the
## Environment, rain is the particle rate multiplier, wind is Wind.storm.
const LOOKS := [
	{"coverage": 0.30, "darkness": 0.00, "gloom": 0.00, "fog": 1.00, "rain": 0.00, "wind": 0.00},
	{"coverage": 0.72, "darkness": 0.25, "gloom": 0.30, "fog": 1.35, "rain": 0.00, "wind": 0.20},
	{"coverage": 0.82, "darkness": 0.42, "gloom": 0.45, "fog": 1.90, "rain": 0.22, "wind": 0.30},
	{"coverage": 0.92, "darkness": 0.68, "gloom": 0.66, "fog": 2.60, "rain": 0.62, "wind": 0.55},
	{"coverage": 1.00, "darkness": 0.95, "gloom": 0.88, "fog": 3.40, "rain": 1.00, "wind": 1.00},
]

## --- thunder ---------------------------------------------------------------
const STRIKE_GAP := Vector2(6.0, 26.0)  ## seconds between strikes at STORM
const FLASH_LIGHT_ENERGY := 5.0         ## how hard a bolt lights the world
const THUNDER_DELAY := 6.0              ## seconds of delay at maximum distance
const MIX_RATE := 11025                 ## thunder is all bass; half rate is plenty

## --- rain ------------------------------------------------------------------
const RAIN_AMOUNT := 2600               ## particle count at STORM
const RAIN_BOX := Vector3(14.0, 1.0, 14.0)   ## emitter half-extents above you
const RAIN_HEIGHT := 11.0               ## how far above the camera it falls from

var env: Environment          ## set by World before add_child
var sky: SkyRig               ## set by World before add_child
var wind: Wind                ## set by World before add_child
var daynight: DayNight        ## set by World before add_child
var hud_cb: Callable          ## optional: World._on_sky_title, for "A storm is coming"

var level: int = Level.CLEAR          ## where we are headed
var _from: int = Level.CLEAR          ## where we came from
var _blend := 1.0                     ## 0 = at _from, 1 = at level
var _dwell := 0.0
var _next_change := 300.0
var _locked := false                  ## true while something scripted owns the sky

## live, blended values
var intensity := 0.0                  ## 0..1 precipitation, what everything reads
var wetness := 0.0                    ## 0..1 lags behind rain; ground stays wet after

var _rain: GPUParticles3D
var _splash: GPUParticles3D
var _rain_mat: ParticleProcessMaterial
var _splash_mat: ParticleProcessMaterial
var _rain_mesh_rain: QuadMesh
var _rain_mesh_snow: QuadMesh
var _flash: DirectionalLight3D
var _flash_t := 0.0
var _flash_dur := 0.2
var _flash_power := 1.0
var _flash_seq: Array = []            ## queued sub-flashes of one bolt
var _strike_t := 0.0
var _thunder: AudioStreamPlayer
var _rain_audio: AudioStreamPlayer
var _thunder_banks: Array[AudioStreamWAV] = []
var _pending_thunder: Array = []       ## [[time_left, distance01], ...]
var _rng := RandomNumberGenerator.new()

var _aurora := 0.0
var _aurora_target := 0.0
var _aurora_rolled_night := -1
var _cam: Camera3D
var _player: Node3D
var _world: Node
var _base_fog := 0.0
var _snowing := false


func _ready() -> void:
	## After DayNight (0) and SkyRig (10) — we react to both.
	process_priority = 20
	_rng.randomize()
	_base_fog = env.fog_density if env != null else 0.006
	_next_change = _rng.randf_range(MIN_DWELL, MAX_DWELL)
	RenderingServer.global_shader_parameter_add(
		"weather_wetness", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	_build_rain()
	_build_flash()
	_build_audio()
	_apply_look(true)


# ===========================================================================
#  The loop
# ===========================================================================

func _process(delta: float) -> void:
	_tick_clock(delta)
	_tick_blend(delta)
	_tick_aurora(delta)
	_tick_storm(delta)
	_follow_camera()


func _tick_clock(delta: float) -> void:
	if _locked:
		return
	_dwell += delta
	if _dwell >= _next_change and _blend >= 1.0:
		_dwell = 0.0
		_next_change = _rng.randf_range(MIN_DWELL, MAX_DWELL)
		set_weather(_roll_next(), false)


func _roll_next() -> int:
	var row: Array = TRANSITIONS[level]
	## Season bias: autumn and winter are wetter and darker; summer clears.
	var s := _season()          ## 0 spring, 1 summer, 2 autumn, 3 winter
	var bias := [1.0, 1.0, 1.0, 1.0, 1.0]
	match s:
		0: bias = [0.8, 1.0, 1.3, 1.2, 1.0]     ## spring: mud season
		1: bias = [1.4, 1.0, 0.8, 0.8, 1.1]     ## summer: clear, but real thunderheads
		2: bias = [0.9, 1.2, 1.2, 1.1, 0.8]     ## autumn: grey
		3: bias = [1.0, 1.3, 1.0, 0.9, 0.5]     ## winter: overcast, rarely violent
	var total := 0.0
	var w: Array[float] = []
	for i in range(5):
		var v: float = float(row[i]) * float(bias[i])
		w.append(v)
		total += v
	var r := _rng.randf() * total
	for i in range(5):
		r -= w[i]
		if r <= 0.0:
			return i
	return Level.CLEAR


func _tick_blend(delta: float) -> void:
	if _blend < 1.0:
		_blend = minf(1.0, _blend + delta / TRANSITION)
		_apply_look(false)
	## Wetness rises with the rain and dries out slowly — a road stays dark
	## for a while after the shower passes, which is most of what sells rain.
	var target := intensity
	var k := (delta * 0.35) if target > wetness else (delta * 0.04)
	wetness = move_toward(wetness, target, k)
	RenderingServer.global_shader_parameter_set("weather_wetness", wetness)


func _apply_look(instant: bool) -> void:
	var a: Dictionary = LOOKS[_from]
	var b: Dictionary = LOOKS[level]
	var t := 1.0 if instant else smoothstep(0.0, 1.0, _blend)

	intensity = lerpf(float(a["rain"]), float(b["rain"]), t)
	_snowing = _season() == 3

	if sky != null and is_instance_valid(sky):
		sky.cloud_coverage = lerpf(float(a["coverage"]), float(b["coverage"]), t)
		sky.cloud_darkness = lerpf(float(a["darkness"]), float(b["darkness"]), t)
		sky.storm_gloom = lerpf(float(a["gloom"]), float(b["gloom"]), t)

	if wind != null and is_instance_valid(wind):
		wind.storm = lerpf(float(a["wind"]), float(b["wind"]), t)

	## Fog: World._process lerps fog_density toward its own target every frame,
	## so we can't just write it. We scale the number World is aiming AT.
	## Guard the lookup: set_weather() is public, and someone calling it on a
	## Weather that isn't parented yet would otherwise crash on a null tree.
	if (_world == null or not is_instance_valid(_world)) and is_inside_tree():
		_world = get_tree().get_first_node_in_group("world")
	var fogmul := lerpf(float(a["fog"]), float(b["fog"]), t)
	if _world != null and "weather_fog_scale" in _world:
		_world.weather_fog_scale = fogmul
	elif env != null:
		env.fog_density = _base_fog * fogmul

	_update_rain()


func _update_rain() -> void:
	if _rain == null:
		return
	var underground := false
	if _world != null and is_instance_valid(_world) and "_underground" in _world:
		underground = bool(_world._underground)
	var on := intensity > 0.005 and not underground

	_rain.emitting = on
	_rain.visible = on
	_rain.amount_ratio = clampf(intensity, 0.02, 1.0)
	if _splash:
		var splashing := on and not _snowing and intensity > 0.15
		_splash.emitting = splashing
		_splash.visible = splashing
		_splash.amount_ratio = clampf(intensity, 0.05, 1.0)

	## Snow is a different animal: slow, wandering, and it doesn't streak.
	if _rain_mat:
		if _snowing:
			_rain.draw_pass_1 = _rain_mesh_snow
			_rain.lifetime = 7.0
			_rain_mat.initial_velocity_min = 0.8
			_rain_mat.initial_velocity_max = 1.8
			_rain_mat.gravity = Vector3(0, -1.4, 0)
			_rain_mat.damping_min = 0.4
			_rain_mat.damping_max = 1.0
			_rain_mat.turbulence_enabled = true
			_rain_mat.turbulence_noise_strength = 0.6
			_rain_mat.turbulence_noise_scale = 2.0
		else:
			_rain.draw_pass_1 = _rain_mesh_rain
			_rain.lifetime = 1.5
			_rain_mat.initial_velocity_min = 14.0
			_rain_mat.initial_velocity_max = 20.0
			_rain_mat.gravity = Vector3(0, -34.0, 0)
			_rain_mat.damping_min = 0.0
			_rain_mat.damping_max = 0.0
			_rain_mat.turbulence_enabled = false
		## Wind blows the fall sideways — harder in a storm.
		var lean := Vector3.ZERO
		if wind != null and is_instance_valid(wind):
			lean = wind.last_dir * wind.last_strength * (7.0 if not _snowing else 2.2)
		_rain_mat.gravity = Vector3(lean.x, _rain_mat.gravity.y, lean.z)

	if _rain_audio:
		var vol := -60.0
		if on:
			## Rain audio is quiet at a drizzle and loud in a storm, in dB.
			vol = lerpf(-26.0, -6.0, clampf(intensity, 0.0, 1.0))
			if _snowing:
				vol -= 18.0   ## snow is nearly silent, and that silence is the point
		_rain_audio.volume_db = vol
		if on and not _rain_audio.playing:
			_rain_audio.play()
		elif not on and _rain_audio.playing:
			_rain_audio.stop()


func _follow_camera() -> void:
	if _cam == null or not is_instance_valid(_cam):
		_cam = get_viewport().get_camera_3d()
		if _cam == null:
			return
	var p := _cam.global_position
	if _rain:
		## The emitter rides above the camera; particles are in world space
		## (local_coords = false) so they don't get dragged when you walk.
		_rain.global_position = p + Vector3(0.0, RAIN_HEIGHT, 0.0)
	if _splash:
		if (_player == null or not is_instance_valid(_player)) and is_inside_tree():
			_player = get_tree().get_first_node_in_group("player")
		var foot := p.y - 1.6
		if _player != null:
			foot = _player.global_position.y
		_splash.global_position = Vector3(p.x, foot + 0.03, p.z)


# ===========================================================================
#  Storm: bolts, flash, thunder
# ===========================================================================

func _tick_storm(delta: float) -> void:
	## The flash light: burn down whatever is queued. A bolt is a hard spike
	## and a fast square falloff — anything slower reads as a lamp, not a bolt.
	if _flash_t > 0.0:
		_flash_t -= delta
		var u := clampf(_flash_t / maxf(_flash_dur, 0.001), 0.0, 1.0)
		var e := u * u * _flash_power
		_flash.light_energy = FLASH_LIGHT_ENERGY * e
		if sky != null and is_instance_valid(sky):
			sky.lightning = e
		if _flash_t <= 0.0:
			_flash.light_energy = 0.0
			_flash.visible = false
			if sky != null and is_instance_valid(sky):
				sky.lightning = 0.0
	elif not _flash_seq.is_empty():
		## Multi-stroke: a real bolt flickers two or three times.
		var nxt: Array = _flash_seq[0]
		nxt[0] -= delta
		if nxt[0] <= 0.0:
			_flash_seq.pop_front()
			_do_flash(float(nxt[1]))

	## Thunder arrives late, the way it does.
	for i in range(_pending_thunder.size() - 1, -1, -1):
		var e2: Array = _pending_thunder[i]
		e2[0] -= delta
		if e2[0] <= 0.0:
			_play_thunder(float(e2[1]))
			_pending_thunder.remove_at(i)

	## Only a real storm makes lightning, and only above ground.
	if level != Level.STORM or _blend < 0.35 or _snowing:
		return
	if _world != null and is_instance_valid(_world) and "_underground" in _world:
		if bool(_world._underground):
			return
	_strike_t -= delta
	if _strike_t <= 0.0:
		_strike_t = _rng.randf_range(STRIKE_GAP.x, STRIKE_GAP.y)
		strike(_rng.randf())


## Fire one bolt. distance01: 0 = right on top of you, 1 = far off over the ridge.
func strike(distance01: float) -> void:
	distance01 = clampf(distance01, 0.0, 1.0)
	var near := 1.0 - distance01
	## Sub-flashes: near bolts flicker harder.
	_do_flash(0.35 + near * 0.65)
	_flash_seq.clear()
	var strokes := _rng.randi_range(0, 2)
	var t := 0.06
	for i in range(strokes):
		t += _rng.randf_range(0.05, 0.14)
		_flash_seq.append([t, (0.25 + near * 0.5) * _rng.randf_range(0.5, 1.0)])
	## The gap between the light and the sound IS the distance. Real seconds
	## would be 15 for 5 km; compressed so it still reads as "that was close".
	_pending_thunder.append([0.12 + distance01 * THUNDER_DELAY, distance01])


func _do_flash(power: float) -> void:
	if _flash == null:
		return
	## The bolt comes from a random quarter of the sky, low and hard.
	_flash.rotation = Vector3(
		deg_to_rad(_rng.randf_range(-70.0, -25.0)),
		_rng.randf_range(0.0, TAU), 0.0)
	_flash.visible = true
	_flash_power = clampf(power, 0.0, 1.0)
	_flash_dur = 0.10 + _flash_power * 0.14
	_flash_t = _flash_dur


func _play_thunder(distance01: float) -> void:
	if _thunder == null or _thunder_banks.is_empty():
		return
	var idx := clampi(int(distance01 * float(_thunder_banks.size())),
		0, _thunder_banks.size() - 1)
	_thunder.stream = _thunder_banks[idx]
	_thunder.volume_db = lerpf(0.0, -17.0, distance01)
	_thunder.pitch_scale = _rng.randf_range(0.88, 1.12)
	_thunder.play()


# ===========================================================================
#  Northern lights
# ===========================================================================

func _tick_aurora(delta: float) -> void:
	if sky == null or not is_instance_valid(sky):
		return

	## Menu / console override wins over everything, including daylight.
	if aurora_override >= 0.0:
		_aurora = aurora_override
		_aurora_target = aurora_override
		sky.aurora_strength = _aurora
		return

	var hour := daynight.hour if daynight != null else 22.0
	var night := hour >= 20.5 or hour < 5.0

	if night:
		## One roll per night, the first time we cross into it.
		var night_id := _day_number()
		if hour < 5.0:
			night_id -= 1     ## after midnight still belongs to last night's roll
		if night_id != _aurora_rolled_night:
			_aurora_rolled_night = night_id
			_aurora_target = _roll_aurora()
	else:
		_aurora_target = 0.0

	## Clouds curtain them off — you can't see the lights through a storm.
	var hidden := 0.0
	if sky.cloud_coverage > AURORA_MAX_CLOUD:
		hidden = smoothstep(AURORA_MAX_CLOUD, 0.85, sky.cloud_coverage)
	var want := _aurora_target * (1.0 - hidden)

	_aurora = move_toward(_aurora, want, delta / AURORA_FADE)
	sky.aurora_strength = _aurora


func _roll_aurora() -> float:
	if aurora_forced:
		return AURORA_BRIGHTNESS
	var chance := AURORA_CHANCE
	match _season():
		2: chance *= 1.6                     ## autumn
		3: chance *= AURORA_WINTER_BONUS     ## winter — long nights, cold clear air
	if _rng.randf() < clampf(chance, 0.0, 1.0):
		## Not every showing is a great one. Most nights it's a faint green
		## smear low in the north; once in a while the whole sky moves.
		var big := _rng.randf() < 0.25
		var s := AURORA_BRIGHTNESS * (1.0 if big else _rng.randf_range(0.25, 0.55))
		if hud_cb.is_valid() and big:
			hud_cb.call("The lights are out")
		return s
	return 0.0


# ===========================================================================
#  Public API — for the Pamola storm crown, quests, or the console
# ===========================================================================

## Move to a level. instant skips the 25-second slide.
func set_weather(new_level: int, instant := false) -> void:
	new_level = clampi(new_level, 0, 4)
	if new_level == level and _blend >= 1.0:
		return
	_from = _current_level_float()
	level = new_level
	_blend = 1.0 if instant else 0.0
	_apply_look(instant)
	if hud_cb.is_valid() and new_level == Level.STORM:
		hud_cb.call("A storm breaks")


func _current_level_float() -> int:
	## When a change lands mid-transition, start the new slide from whichever
	## end we are closest to rather than snapping backward.
	return level if _blend > 0.5 else _from


## Hold a level until release_weather() — for scripted moments (Katahdin's
## storm crown, a boss arena, a cutscene).
func lock_weather(new_level: int, instant := false) -> void:
	set_weather(new_level, instant)
	_locked = true


func release_weather() -> void:
	_locked = false
	_dwell = 0.0


func level_name() -> String:
	return ["Clear", "Overcast", "Drizzle", "Rain", "Storm"][level]


func is_raining() -> bool:
	return intensity > 0.05


func _season() -> int:
	## Wind.gd owns the 24-day-season maths (spec §7).
	return int(Wind.phase_for_day(_day_number_f()) * 4.0) % 4


func _day_number() -> int:
	return int(_day_number_f())


func _day_number_f() -> float:
	if daynight != null and is_instance_valid(daynight) and "day" in daynight:
		return float(daynight.day)
	return 0.0


# ===========================================================================
#  Construction
# ===========================================================================

func _build_rain() -> void:
	## --- the streak, and the flake ---
	_rain_mesh_rain = QuadMesh.new()
	_rain_mesh_rain.size = Vector2(0.022, 0.62)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(0.74, 0.82, 0.92, 0.38)
	rm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y  ## stays vertical, turns to face you
	rm.billboard_keep_scale = true
	rm.disable_receive_shadows = true
	rm.no_depth_test = false
	rm.vertex_color_use_as_albedo = true
	_rain_mesh_rain.material = rm

	_rain_mesh_snow = QuadMesh.new()
	_rain_mesh_snow.size = Vector2(0.07, 0.07)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0.95, 0.97, 1.0, 0.85)
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.billboard_keep_scale = true
	sm.disable_receive_shadows = true
	_rain_mesh_snow.material = sm

	## --- the fall ---
	_rain_mat = ParticleProcessMaterial.new()
	_rain_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_mat.emission_box_extents = RAIN_BOX
	_rain_mat.direction = Vector3(0, -1, 0)
	_rain_mat.spread = 0.0
	_rain_mat.initial_velocity_min = 14.0
	_rain_mat.initial_velocity_max = 20.0
	_rain_mat.gravity = Vector3(0, -34.0, 0)
	_rain_mat.scale_min = 0.8
	_rain_mat.scale_max = 1.5
	_rain_mat.color = Color(1, 1, 1, 1)

	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.process_material = _rain_mat
	_rain.draw_pass_1 = _rain_mesh_rain
	_rain.amount = RAIN_AMOUNT
	_rain.lifetime = 1.5
	_rain.preprocess = 1.4          ## so it's already raining when it switches on
	_rain.local_coords = false      ## particles stay put when the emitter moves
	_rain.fixed_fps = 0
	_rain.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	_rain.emitting = false
	_rain.visible = false
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rain)

	## --- the splash ---
	var spm := QuadMesh.new()
	spm.size = Vector2(0.11, 0.11)
	var spmat := StandardMaterial3D.new()
	spmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spmat.albedo_color = Color(0.80, 0.88, 0.96, 0.30)
	spmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	spmat.billboard_keep_scale = true
	spmat.disable_receive_shadows = true
	spm.material = spmat

	_splash_mat = ParticleProcessMaterial.new()
	_splash_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_splash_mat.emission_box_extents = Vector3(9.0, 0.05, 9.0)
	_splash_mat.direction = Vector3(0, 1, 0)
	_splash_mat.spread = 32.0
	_splash_mat.initial_velocity_min = 0.5
	_splash_mat.initial_velocity_max = 1.4
	_splash_mat.gravity = Vector3(0, -7.0, 0)
	_splash_mat.scale_min = 0.4
	_splash_mat.scale_max = 1.0
	var curve := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(1.0, 0.0))
	curve.curve = c
	_splash_mat.alpha_curve = curve

	_splash = GPUParticles3D.new()
	_splash.name = "RainSplash"
	_splash.process_material = _splash_mat
	_splash.draw_pass_1 = spm
	_splash.amount = 320
	_splash.lifetime = 0.45
	_splash.local_coords = false
	_splash.visibility_aabb = AABB(Vector3(-14, -4, -14), Vector3(28, 8, 28))
	_splash.emitting = false
	_splash.visible = false
	_splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_splash)


func _build_flash() -> void:
	## A bolt has to light the WORLD, not just the sky, or it reads as a bug in
	## the sky shader. One directional light, off except for a fifth of a second.
	_flash = DirectionalLight3D.new()
	_flash.name = "LightningFlash"
	_flash.light_color = Color(0.86, 0.90, 1.0)
	_flash.light_energy = 0.0
	_flash.shadow_enabled = false     ## a shadow pass for two frames isn't worth it
	_flash.visible = false
	add_child(_flash)


func _build_audio() -> void:
	_thunder = AudioStreamPlayer.new()
	_thunder.name = "Thunder"
	_thunder.bus = "Master"
	add_child(_thunder)

	_rain_audio = AudioStreamPlayer.new()
	_rain_audio.name = "RainLoop"
	_rain_audio.bus = "Master"
	_rain_audio.volume_db = -60.0
	_rain_audio.stream = _make_rain_loop()
	add_child(_rain_audio)

	## Three thunders: on top of you, over the next ridge, way off.
	## Generated once, at boot, at 11 kHz — thunder has no highs to lose.
	_thunder_banks.append(_make_thunder(0.0))
	_thunder_banks.append(_make_thunder(0.5))
	_thunder_banks.append(_make_thunder(1.0))


# ---------------------------------------------------------- synthesis ------
# No .wav files, no import step, no licensing. Thunder is noise plus an
# envelope plus a low-pass, and distance is just a heavier low-pass.

func _make_thunder(distance01: float) -> AudioStreamWAV:
	var dur := 2.4 + distance01 * 3.4
	var n := int(MIX_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = 90210 + int(distance01 * 1000.0)

	## Distance eats the top end: a near strike CRACKS, a far one only rumbles.
	var cutoff := lerpf(0.55, 0.045, distance01)
	var crack := 1.0 - distance01              ## how much sharp attack there is
	var lp := 0.0
	var lp2 := 0.0
	var brown := 0.0

	## Three or four rolls of sound stacked on a long decay — that lumpiness is
	## what makes it thunder instead of a jet flying over.
	var bumps := [
		[0.00, 1.00], [0.22 + distance01 * 0.4, 0.72],
		[0.55 + distance01 * 0.8, 0.55], [1.05 + distance01 * 1.3, 0.38],
	]

	for i in range(n):
		var t := float(i) / float(MIX_RATE)
		var white := rng.randf_range(-1.0, 1.0)

		## Brown noise: the rumble. Leaky integration keeps it from wandering off.
		brown = brown * 0.985 + white * 0.06
		var s := brown * 6.0

		## The crack: only the first 90 ms, only when it's close.
		if crack > 0.05 and t < 0.09:
			var env_c: float = exp(-t * 46.0) * crack
			s += white * env_c * 1.6

		## Two poles of low-pass. The second is what makes distance sound like
		## distance rather than just quieter.
		lp += (s - lp) * cutoff
		lp2 += (lp - lp2) * cutoff
		var v := lp2

		## Envelope: the stacked rolls, times an overall decay.
		var amp := 0.0
		for b in bumps:
			var bt: float = t - float(b[0])
			if bt > -0.15:
				amp += float(b[1]) * exp(-(bt * bt) / (0.16 + distance01 * 0.5))
		amp *= exp(-t / (0.9 + distance01 * 1.6))
		## Far thunder swells in instead of starting flat out.
		if distance01 > 0.3:
			amp *= clampf(t / (0.25 * distance01), 0.0, 1.0)

		v *= amp * 1.5
		v = clampf(v, -1.0, 1.0)
		## Soft clip so the loud ones distort like weather, not like a bad file.
		v = v - (v * v * v) / 3.0
		data.encode_s16(i * 2, int(clampf(v * 1.3, -1.0, 1.0) * 30000.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav


func _make_rain_loop() -> AudioStreamWAV:
	## Two seconds of filtered hiss with the tail cross-faded into the head, so
	## it loops without a click. Volume does the rest — this same loop is a
	## drizzle at -26 dB and a downpour at -6.
	var dur := 2.0
	var n := int(MIX_RATE * dur)
	var fade := int(MIX_RATE * 0.25)
	var raw := PackedFloat32Array()
	raw.resize(n)

	var rng := RandomNumberGenerator.new()
	rng.seed = 4477
	var lp := 0.0
	var hp := 0.0
	for i in range(n):
		var white := rng.randf_range(-1.0, 1.0)
		lp += (white - lp) * 0.42          ## take the hiss down to a wash
		hp = hp * 0.92 + (lp - hp) * 0.08  ## and pull the mud out from under it
		raw[i] = (lp - hp) * 0.55

	## Crossfade the last `fade` samples over the first `fade`.
	for i in range(fade):
		var u := float(i) / float(fade)
		raw[i] = lerpf(raw[n - fade + i], raw[i], u)

	var data := PackedByteArray()
	data.resize((n - fade) * 2)
	for i in range(n - fade):
		data.encode_s16(i * 2, int(clampf(raw[i], -1.0, 1.0) * 26000.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n - fade
	return wav


# ---------------------------------------------------------- save/load ------

func to_dict() -> Dictionary:
	return {"level": level, "dwell": _dwell, "wetness": wetness}


func from_dict(d: Dictionary) -> void:
	set_weather(int(d.get("level", 0)), true)
	_dwell = float(d.get("dwell", 0.0))
	wetness = float(d.get("wetness", 0.0))
