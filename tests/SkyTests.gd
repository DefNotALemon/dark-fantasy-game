extends SceneTree

## Headless smoke test for the sky + weather pack (docs/SKY_WEATHER.md).
##
##     godot --headless --path . --script res://tests/SkyTests.gd
##
## NOTE: headless Godot does NOT compile shader code — the dummy renderer
## never touches it. This suite proves the SCRIPTS are right and that every
## uniform they write exists. To prove the GLSL compiles you have to render
## for real (see docs/SKY_WEATHER.md §8).

var fails: Array[String] = []
var checks := 0


func ck(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails.append(what)
		print("  FAIL: ", what)


var _ran := false


func _process(_delta: float) -> bool:
	# Run on the first real frame: nodes added during _initialize() only get
	# their _ready() on the frame after they enter the tree.
	if not _ran:
		_ran = true
		_run()
	return true


func _run() -> void:
	print("=== sky/weather smoke test ===")

	# --- shader compiles at all ---
	var sh: Shader = load("res://shaders/sky.gdshader")
	ck(sh != null, "sky.gdshader loads")
	if sh == null:
		_done()
		return

	var mat := ShaderMaterial.new()
	mat.shader = sh

	# --- every uniform the scripts write must exist in the shader ---
	var declared := {}
	for u in sh.get_shader_uniform_list():
		declared[String(u["name"])] = true
	var written := [
		"sun_dir_override", "cloud_mode", "cloud_coverage", "cloud_darkness",
		"cloud_wind", "storm_gloom", "aurora_strength", "lightning",
		"vol_density", "cloud_opacity", "cloud_scale", "cloud_softness",
		"star_density", "aurora_color_a", "aurora_color_b",
	]
	for w in written:
		ck(declared.has(w), "shader declares uniform '%s'" % w)
	print("  uniforms declared: ", declared.size())

	# --- the world scaffold ---
	var root_node := Node3D.new()
	root.add_child(root_node)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.fog_enabled = true
	env.fog_density = 0.018
	var we := WorldEnvironment.new()
	we.environment = env
	root_node.add_child(we)

	var dn := DayNight.new()
	dn.env = env
	dn.sky_mat = env.sky.sky_material as ProceduralSkyMaterial
	root_node.add_child(dn)

	var wind := Wind.new()
	root_node.add_child(wind)

	var sky := SkyRig.new()
	sky.env = env
	sky.daynight = dn
	sky.wind = wind
	root_node.add_child(sky)

	ck(sky.sky_mat != null, "SkyRig installed a ShaderMaterial")
	ck(env.sky.sky_material == sky.sky_mat, "Environment.sky uses it")
	ck(dn.sky_mat == null, "DayNight stood down from painting the sky")

	var wx := Weather.new()
	wx.env = env
	wx.sky = sky
	wx.wind = wind
	wx.daynight = dn
	root_node.add_child(wx)

	ck(wx.get_node_or_null("Rain") != null, "rain particles built")
	ck(wx.get_node_or_null("RainSplash") != null, "splash particles built")
	ck(wx.get_node_or_null("LightningFlash") != null, "flash light built")
	ck(wx.get_node_or_null("Thunder") != null, "thunder player built")
	ck(wx.get_node_or_null("RainLoop") != null, "rain loop built")
	ck((wx.get_node("RainLoop") as AudioStreamPlayer).stream != null, "rain loop has audio")

	# --- synthesised audio is sane ---
	var t0: AudioStreamWAV = wx._make_thunder(0.0)
	var t1: AudioStreamWAV = wx._make_thunder(1.0)
	ck(t0.data.size() > 1000, "near thunder has samples (%d)" % t0.data.size())
	ck(t1.data.size() > t0.data.size(), "far thunder is longer")
	ck(t0.get_length() > 2.0 and t0.get_length() < 8.0,
		"thunder length sane (%.2fs)" % t0.get_length())
	var loop: AudioStreamWAV = wx._make_rain_loop()
	ck(loop.loop_mode == AudioStreamWAV.LOOP_FORWARD, "rain loop loops")
	ck(loop.loop_end > 0, "rain loop has a loop point")
	# peak level check — silence would mean the synth is broken
	var peak := 0
	for i in range(0, mini(t0.data.size(), 40000), 2):
		peak = maxi(peak, absi(t0.data.decode_s16(i)))
	ck(peak > 8000, "thunder is actually audible (peak %d/32767)" % peak)
	var rpeak := 0
	for i in range(0, mini(loop.data.size(), 40000), 2):
		rpeak = maxi(rpeak, absi(loop.data.decode_s16(i)))
	ck(rpeak > 2000, "rain hiss is audible (peak %d)" % rpeak)

	# --- the weather ladder ---
	for lv in range(5):
		wx.set_weather(lv, true)
		ck(wx.level == lv, "set_weather(%d) sticks" % lv)
	wx.set_weather(Weather.Level.STORM, true)
	ck(wx.intensity > 0.9, "storm is full rain (%.2f)" % wx.intensity)
	ck(sky.cloud_darkness > 0.9, "storm blackens the clouds")
	ck(wind.storm > 0.9, "storm drives Wind.storm to full")
	ck((wx.get_node("Rain") as GPUParticles3D).emitting, "storm is emitting rain")

	wx.set_weather(Weather.Level.CLEAR, true)
	ck(wx.intensity == 0.0, "clear is dry")
	ck(not (wx.get_node("Rain") as GPUParticles3D).emitting, "clear stops the rain")
	ck(sky.storm_gloom == 0.0, "clear clears the gloom")

	# --- lightning ---
	wx.set_weather(Weather.Level.STORM, true)
	wx.strike(0.0)
	ck((wx.get_node("LightningFlash") as DirectionalLight3D).visible, "a strike lights the world")
	ck(wx._pending_thunder.size() == 1, "a strike queues its thunder")
	var near_delay: float = float(wx._pending_thunder[0][0])
	wx._pending_thunder.clear()
	wx.strike(1.0)
	var far_delay: float = float(wx._pending_thunder[0][0])
	ck(far_delay > near_delay, "distant thunder arrives later (%.2fs vs %.2fs)"
		% [far_delay, near_delay])

	# --- clouds toggle ---
	for m in [SkyRig.Clouds.OFF, SkyRig.Clouds.PAINTERLY, SkyRig.Clouds.VOLUMETRIC]:
		sky.set_cloud_mode(m)
		ck(sky.cloud_mode == m, "cloud mode %d sticks" % m)
		ck(int(sky.sky_mat.get_shader_parameter("cloud_mode")) == m,
			"cloud mode %d reaches the shader" % m)
	sky.set_cloud_mode(99)
	ck(sky.cloud_mode == 2, "cloud mode clamps")

	# --- aurora ---
	wx.set_weather(Weather.Level.CLEAR, true)
	wx.aurora_forced = true
	ck(wx._roll_aurora() > 0.5, "forced aurora rolls bright")
	wx.aurora_forced = false
	dn.hour = 22.0
	wx._tick_aurora(1000.0)   # a big step: straight to target
	# with AURORA_CHANCE at the shipping 0.04 this is usually 0 — just check the
	# plumbing moves the value where it is told to.
	wx._aurora_target = 0.8
	wx._tick_aurora(1000.0)
	ck(sky.aurora_strength > 0.5, "aurora reaches the sky (%.2f)" % sky.aurora_strength)
	ck(float(sky.sky_mat.get_shader_parameter("aurora_strength")) > 0.5,
		"aurora reaches the shader")
	dn.hour = 13.0
	wx._tick_aurora(1000.0)
	ck(sky.aurora_strength < 0.01, "daylight kills the aurora")

	# aurora hides behind a storm deck
	dn.hour = 23.0
	wx._aurora_target = 1.0
	wx.set_weather(Weather.Level.STORM, true)
	wx._tick_aurora(1000.0)
	ck(sky.aurora_strength < 0.05, "a storm deck hides the lights (%.2f)"
		% sky.aurora_strength)

	# --- the sun actually drives the sky ---
	dn.hour = 13.3
	dn._apply()
	sky._process(0.016)
	var noon: Vector3 = sky.sky_mat.get_shader_parameter("sun_dir_override")
	dn.hour = 6.0
	dn._apply()
	sky._process(0.016)
	var dawn: Vector3 = sky.sky_mat.get_shader_parameter("sun_dir_override")
	dn.hour = 0.0
	dn._apply()
	sky._process(0.016)
	var midnight: Vector3 = sky.sky_mat.get_shader_parameter("sun_dir_override")
	print("  sun at noon=%.2f dawn=%.2f midnight=%.2f (y)" % [noon.y, dawn.y, midnight.y])
	ck(noon.y > 0.98, "sun is overhead at solar noon (13:18)")
	ck(absf(dawn.y) < 0.12, "sun is on the horizon at dawn")
	ck(midnight.y < -0.85, "sun is under the world at midnight")
	dn.hour = DayNight.NIGHTFALL_HOUR
	dn._apply()
	sky._process(0.016)
	var setting: Vector3 = sky.sky_mat.get_shader_parameter("sun_dir_override")
	ck(absf(setting.y) < 0.02, "the sun sets exactly at NIGHTFALL_HOUR (y=%.3f)" % setting.y)
	dn.hour = 19.5
	dn._apply()
	sky._process(0.016)
	var golden: Vector3 = sky.sky_mat.get_shader_parameter("sun_dir_override")
	ck(golden.y > 0.05 and golden.y < 0.35,
		"19:30 (the orange keyframe) is the low pink sun (y=%.2f)" % golden.y)

	# --- wind pushes the clouds ---
	var before: Vector2 = sky.sky_mat.get_shader_parameter("cloud_wind")
	wind.last_dir = Vector3(1, 0, 0)
	wind.last_strength = 1.0
	for i in range(30):
		sky._process(0.1)
	var after: Vector2 = sky.sky_mat.get_shader_parameter("cloud_wind")
	ck(after.x > before.x, "wind drifts the cloud deck")

	# --- wetness lags and dries ---
	wx.set_weather(Weather.Level.STORM, true)
	for i in range(80):
		wx._tick_blend(0.1)
	ck(wx.wetness > 0.15, "rain wets the world (%.2f)" % wx.wetness)
	var wet_peak := wx.wetness
	wx.set_weather(Weather.Level.CLEAR, true)
	for i in range(20):
		wx._tick_blend(0.1)
	ck(wx.wetness < wet_peak, "it dries out after")
	ck(wx.wetness > 0.0, "...but slowly (%.2f)" % wx.wetness)

	# --- save / load ---
	wx.set_weather(Weather.Level.RAIN, true)
	var d := wx.to_dict()
	wx.set_weather(Weather.Level.CLEAR, true)
	wx.from_dict(d)
	ck(wx.level == Weather.Level.RAIN, "weather survives save/load")

	# --- lock / release ---
	wx.lock_weather(Weather.Level.STORM, true)
	wx._dwell = 99999.0
	wx._tick_clock(1.0)
	ck(wx.level == Weather.Level.STORM, "a locked sky ignores the clock")
	wx.release_weather()
	ck(wx.level_name() == "Storm", "level_name reads right")

	# --- the transition table is a valid distribution ---
	for i in range(5):
		var s := 0.0
		for v in Weather.TRANSITIONS[i]:
			s += float(v)
		ck(absf(s - 1.0) < 0.001, "transition row %d sums to 1 (%.3f)" % [i, s])

	# ======================= the sky menu (' key) ==========================
	var stub: Node = load("res://tests/StubWorld.gd").new()
	stub._sky = sky
	stub._daynight = dn
	stub._weather = wx
	stub.add_to_group("world")
	root_node.add_child(stub)

	var menu := SkyMenu.new()
	root_node.add_child(menu)
	ck(not menu.visible, "the menu starts closed")
	menu.visible = true
	menu.refresh()
	ck(menu._dn == dn, "menu found DayNight")
	ck(menu._wx == wx, "menu found Weather")
	ck(menu._sky == sky, "menu found SkyRig")

	# time jumps
	menu._set_hour(6.0)
	ck(absf(dn.hour - 6.0) < 0.001, "Dawn button sets 06:00")
	menu._set_hour(13.3)
	ck(dn.sun.global_transform.basis.z.normalized().y > 0.98, "Noon button puts the sun up")
	menu._set_hour(20.3)
	var dusk_y: float = dn.sun.global_transform.basis.z.normalized().y
	ck(dusk_y > 0.0 and dusk_y < 0.10, "Dusk button lands on the horizon (%.3f)" % dusk_y)
	menu._set_hour(-1.0)
	ck(absf(dn.hour - 23.0) < 0.001, "hour wraps instead of going negative")

	# the clock readout
	dn.hour = 19.7
	dn.day = 30.0
	menu.refresh()
	ck(menu._clock.text.begins_with("19:42"), "clock reads 19:42 (got %s)" % menu._clock.text)
	ck("Summer" in menu._clock.text, "day 30 is summer (got %s)" % menu._clock.text)

	# speed / freeze
	menu._set_speed(0.0)
	ck(dn.time_scale == 0.0, "Frozen stops the clock")
	var frozen := dn.hour
	dn._process(10.0)
	ck(absf(dn.hour - frozen) < 0.0001, "...and the clock really does not move")
	menu._set_speed(60.0)
	dn._process(1.0)
	ck(dn.hour > frozen, "60x runs the clock fast")
	menu._set_speed(1.0)

	# calendar
	dn.day = 30.0
	menu._add_days(7.0)
	ck(dn.day == 37.0, "+7 days")
	menu._add_days(-100.0)
	ck(dn.day == 0.0, "days never go negative")
	dn.day = 130.0                        # year 2 (96/yr), 34 days in = summer
	menu._set_season(2)
	ck(dn.day == 96.0 + 48.0, "Autumn jumps to day %d, got %d" % [144, int(dn.day)])
	ck(Wind.season_name(dn.day) == "Autumn", "...and it really is autumn")
	menu._set_season(3)
	ck(Wind.season_name(dn.day) == "Winter", "Winter button")
	menu._set_season(0)
	ck(Wind.season_name(dn.day) == "Spring", "Spring button stays in the same year")
	ck(dn.day == 96.0, "Spring of year 2, not year 1")

	# weather buttons
	menu._snap = true
	menu._set_level(Weather.Level.STORM)
	ck(wx.level == Weather.Level.STORM, "Storm button")
	ck(wx.intensity > 0.9, "...and it snapped, not eased")
	menu.refresh()
	ck("Storm" in menu._weather_line.text, "readout names the level")
	menu._snap = false
	menu._set_level(Weather.Level.CLEAR)
	ck(wx.intensity > 0.5, "Ease leaves it mid-transition")
	menu._snap = true
	menu._set_level(Weather.Level.CLEAR)

	# hold / release
	menu._set_lock(true)
	wx._dwell = 99999.0
	wx._tick_clock(1.0)
	ck(wx.level == Weather.Level.CLEAR, "Hold pins the weather")
	menu._set_lock(false)
	ck(not bool(wx.get("_locked")), "Auto releases it")

	# lightning from any level
	wx._pending_thunder.clear()
	menu._strike(0.0)
	ck(wx._pending_thunder.size() == 1, "the bolt button fires at Clear too")

	# clouds go through World, and reach the shader
	menu._set_clouds(2)
	ck(stub.cloud_calls.back() == 2, "clouds route through World.set_cloud_mode")
	ck(int(sky.sky_mat.get_shader_parameter("cloud_mode")) == 2, "...and reach the shader")
	menu._set_clouds(1)

	# coverage slider
	menu._on_coverage(0.77)
	ck(absf(sky.cloud_coverage - 0.77) < 0.001, "coverage slider moves the deck")

	# aurora override beats daylight AND the cloud deck
	dn.hour = 13.0
	wx.set_weather(Weather.Level.STORM, true)
	menu._set_aurora(0.9)
	wx._tick_aurora(0.5)
	ck(sky.aurora_strength > 0.85, "forced aurora ignores noon and a storm (%.2f)"
		% sky.aurora_strength)
	menu._set_aurora(-1.0)
	wx._tick_aurora(1000.0)
	ck(sky.aurora_strength < 0.05, "Normal hands it back to the roll")
	wx.set_weather(Weather.Level.CLEAR, true)

	# the lit-button state tracks the world, not the click
	dn.hour = 22.0
	wx.set_weather(Weather.Level.RAIN, true)
	sky.set_cloud_mode(0)
	menu.refresh()
	ck(_lit(menu, "level") == Weather.Level.RAIN, "the lit level button follows the world")
	ck(_lit(menu, "clouds") == 0, "the lit cloud button follows the world")

	# --- run the whole thing for a while and see if anything explodes ---
	for i in range(400):
		wx._process(0.25)
		sky._process(0.25)
		menu._process(0.25)
	ck(true, "600 simulated seconds without a crash")

	_done()


func _lit(menu: SkyMenu, id: String) -> Variant:
	for pair: Array in menu._btn_groups[id]:
		if (pair[1] as Button).button_pressed:
			return pair[0]
	return null


func _done() -> void:
	print("---")
	if fails.is_empty():
		print("ALL GREEN — %d checks" % checks)
	else:
		print("%d/%d FAILED:" % [fails.size(), checks])
		for f in fails:
			print("  - ", f)
	quit(0 if fails.is_empty() else 1)
