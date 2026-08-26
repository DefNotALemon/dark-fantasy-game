"""Wire the sky + weather pack into the live game. Run from the repo root.

    python3 tools/patch_sky.py

Anchored, verified, re-runnable, and it leaves a .bak beside every file it
touches. Running it twice is a no-op.

What it changes:
    Wind.gd      publishes last_dir / last_strength so the sky can read the
                 wind without global_shader_parameter_get() (editor-only).
    DayNight.gd  gains a real DAY COUNTER — and with it, seasons that actually
                 advance. (World.gd was calling Wind.publish_season(0.0) every
                 boot, so season_phase has been frozen at spring this whole
                 time. This is that bug, fixed.)
    World.gd     builds SkyRig + Weather, lets the weather scale surface fog,
                 exposes set_cloud_mode() for the settings menu, and saves the
                 day and the weather alongside the hour.
    Player.gd    adds the "Clouds — Off / Painterly / Volumetric" settings row
                 and persists it.
"""
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
if os.path.basename(ROOT) == "tools":
    ROOT = os.path.dirname(ROOT)

changed = []
skipped = []


def patch(path, pairs, append=""):
    """Apply anchored replacements. Safe to re-run.

    The "have I already done this?" test is `new in src`, and it has to be
    exactly that. Two weaker tests both failed here:

      * comparing the FIRST line of `new` — most of these edits keep the
        anchor and add around it, so new's first line IS old's first line and
        the anchor is still present afterwards. Run it twice, get the addition
        twice: a duplicate `var` declaration and a parse error.
      * comparing the first line of `new` that isn't in `old` — better, but
        two hunks in the same file can add the same line (`if sky_panel:`
        appears in both _toggle_menu and _close_menu). The second hunk then
        reports "already patched" and is silently skipped.

    `new` is inserted verbatim, so testing for the whole block can neither
    double-apply nor collide.
    """
    p = os.path.join(ROOT, path)
    if not os.path.exists(p):
        print("  ! MISSING:", path)
        skipped.append(path)
        return
    src = open(p, encoding="utf-8").read()
    orig = src
    for old, new in pairs:
        if new in src:
            print("  = already patched:", path)
            continue
        if old not in src:
            print("  ! ANCHOR NOT FOUND in %s -- skipped:\n      %s"
                  % (path, old.strip().splitlines()[0][:78]))
            skipped.append(path)
            continue
        src = src.replace(old, new, 1)
        print("  + patched", path)
    if append and append.strip().splitlines()[0] not in src:
        src = src.rstrip() + "\n\n" + append
        print("  + appended to", path)
    if src != orig:
        shutil.copyfile(p, p + ".bak")
        open(p, "w", encoding="utf-8").write(src)
        changed.append(path)


# ============================================================== Wind.gd =====
# The sky needs the wind, but RenderingServer.global_shader_parameter_get() is
# editor-only (Wind's own comment says so). So Wind publishes its last values
# on itself, and anything that isn't a shader reads them from there.

patch("scripts/Wind.gd", [(
    '''var storm := 0.0 : set = _set_storm     ## 0..1, weather drives this later''',
    '''var storm := 0.0 : set = _set_storm     ## 0..1, weather drives this later

## The last values published, readable from GDScript. Shaders get these as
## global parameters; SkyRig and Weather read them from here instead, because
## RenderingServer.global_shader_parameter_get() is editor-only and spams a
## warning every frame in an exported build.
var last_dir := Vector3(1, 0, 0)
var last_strength := 0.2'''
), (
    '''	RenderingServer.global_shader_parameter_set("wind_dir", dir)
	RenderingServer.global_shader_parameter_set("wind_strength", strength)''',
    '''	last_dir = dir
	last_strength = strength
	RenderingServer.global_shader_parameter_set("wind_dir", dir)
	RenderingServer.global_shader_parameter_set("wind_strength", strength)'''
)])


# ========================================================== DayNight.gd =====
# The day counter. Without it season_phase never moves off whatever World set
# at boot, which means the whole seasonal foliage system (spec §7) has been
# stuck in one season since it shipped.

patch("scripts/DayNight.gd", [(
    '''var hour := START_HOUR
var sun: DirectionalLight3D
var moon: DirectionalLight3D''',
    '''var hour := START_HOUR
## Days since the world began. One season is 24 of these, one year 96
## (Wind.DAYS_PER_SEASON) — this is what makes autumn ever arrive.
var day := 0.0
## How fast the clock runs. 1.0 is the authored 20-minute day; 0.0 freezes the
## sun where it stands. The sky menu (' key) drives this — nothing else should.
var time_scale := 1.0
var sun: DirectionalLight3D
var moon: DirectionalLight3D'''
), (
    '''func _process(delta: float) -> void:
	var prev := hour
	hour = fmod(hour + delta * (24.0 / DAY_SECONDS), 24.0)''',
    '''func _process(delta: float) -> void:
	var prev := hour
	hour = fmod(hour + delta * time_scale * (24.0 / DAY_SECONDS), 24.0)
	## Midnight rolled over: another day on the calendar, and the season with it.
	if hour < prev:
		day += 1.0
		Wind.publish_season(day)
		if title_cb.is_valid() and int(day) % int(Wind.DAYS_PER_SEASON) == 0:
			title_cb.call(Wind.season_name(day))'''
), (
    '''	var ang := (hour - 6.0) / 24.0 * TAU''',
    '''	## The arc used to be a plain 24-hour wheel, which crossed the horizon at
	## 18:00 — an hour and a half before the 19.5 dusk keyframe and 2.6 hours
	## before NIGHTFALL_HOUR. With a procedural sky nobody could see the
	## mismatch; with shaders/sky.gdshader, which reads the sun's real
	## elevation, the sky went black while the fog was still orange.
	##
	## So the arc is pinned to the day this game actually authored: the sun
	## crosses the horizon exactly at DAWN_HOUR and again at NIGHTFALL_HOUR,
	## and rides highest halfway between (13:18). Long summer days, and the
	## pink hour now lands on the orange keyframe where it belongs.
	var ang := 0.0
	var day_len := NIGHTFALL_HOUR - DAWN_HOUR
	if hour >= DAWN_HOUR and hour < NIGHTFALL_HOUR:
		ang = PI * (hour - DAWN_HOUR) / day_len
	else:
		var nh := hour - NIGHTFALL_HOUR
		if nh < 0.0:
			nh += 24.0
		ang = PI + PI * nh / (24.0 - day_len)'''
), (
    '''const START_HOUR := 17.0        ## boot into the signature dusk''',
    '''## Boot straight into the pink hour. (Was 17.0, which under the old sun wheel
## was the signature dusk; with the arc pinned to dawn/nightfall above, 19.7 is
## where that light lives now. One number — put it back if you miss it.)
const START_HOUR := 19.7'''
)])


# ============================================================= World.gd =====

patch("scripts/World.gd", [(
    '''var _env: Environment
var _daynight: DayNight
var _wind: Wind''',
    '''var _env: Environment
var _daynight: DayNight
var _wind: Wind
var _sky: SkyRig
var _weather: Weather
## Weather thickens surface fog. _process aims the Environment at BASE_FOG
## scaled by this — caves keep their own fog untouched.
var weather_fog_scale := 1.0'''
), (
    '''	_wind = Wind.new()
	_wind.player = get_tree().get_first_node_in_group("player")
	add_child(_wind)
	Wind.publish_season(0.0)''',
    '''	_wind = Wind.new()
	_wind.player = get_tree().get_first_node_in_group("player")
	add_child(_wind)
	Wind.publish_season(_daynight.day)

	## The sky itself: shaders/sky.gdshader replaces the procedural gradient —
	## pink dusk, clouds, stars, northern lights. DayNight keeps the clock and
	## the sun; SkyRig paints what you look at. (scripts/SkyRig.gd)
	_sky = SkyRig.new()
	_sky.env = env
	_sky.daynight = _daynight
	_sky.wind = _wind
	add_child(_sky)

	## ...and the weather on top of it: clear -> overcast -> drizzle -> rain ->
	## storm, with thunder only at the top of the ladder. (scripts/Weather.gd)
	_weather = Weather.new()
	_weather.env = env
	_weather.sky = _sky
	_weather.wind = _wind
	_weather.daynight = _daynight
	_weather.hud_cb = _on_sky_title
	add_child(_weather)'''
), (
    '''	var want_fog := lerpf(BASE_FOG, CAVE_FOG, depth_u)''',
    '''	## Surface fog thickens with the weather; the cave end of the lerp doesn't.
	var want_fog := lerpf(BASE_FOG * weather_fog_scale, CAVE_FOG, depth_u)'''
), (
    '''	var out := {
		"hour": _daynight.hour if _daynight else 17.0,''',
    '''	var out := {
		"hour": _daynight.hour if _daynight else 17.0,
		"day": _daynight.day if _daynight else 0.0,
		"weather": _weather.to_dict() if _weather else {},'''
), (
    '''func apply_state(d: Dictionary) -> void:
	if _daynight:
		_daynight.hour = float(d.get("hour", 17.0))''',
    '''func apply_state(d: Dictionary) -> void:
	if _daynight:
		_daynight.hour = float(d.get("hour", 17.0))
		_daynight.day = float(d.get("day", 0.0))
		Wind.publish_season(_daynight.day)
	if _weather and d.has("weather"):
		_weather.from_dict(d["weather"] as Dictionary)'''
)], append='''## ---------------------------------------------------------------- sky ------

func set_cloud_mode(idx: int) -> void:
	## Settings -> Clouds. 0 off, 1 painterly, 2 volumetric.
	if _sky != null and is_instance_valid(_sky):
		_sky.set_cloud_mode(idx)


func weather() -> Weather:
	## Handy from the console, and how a scripted moment (Katahdin's storm
	## crown) grabs the sky: World.weather().lock_weather(Weather.Level.STORM)
	return _weather
''')


# ============================================================ Player.gd =====

patch("scripts/Player.gd", [(
    '''var set_blood := true            ## Blood: off swaps red for a neutral impact puff''',
    '''var set_blood := true            ## Blood: off swaps red for a neutral impact puff
var set_clouds := 1              ## Clouds: 0 off / 1 painterly / 2 volumetric'''
), (
    '''	_settings_option_row(vb, "VSync", "vsync",
		[["Off", false], ["On", true]])''',
    '''	_settings_option_row(vb, "VSync", "vsync",
		[["Off", false], ["On", true]])
	_settings_option_row(vb, "Clouds", "clouds",
		[["Off", 0], ["Painterly", 1], ["Volumetric", 2]])
	var cloud_note := Label.new()
	cloud_note.text = "Painterly is two scrolling layers with lit edges - near free, and it\\ncatches the sunset. Volumetric marches real depth through the deck: puffier,\\nand it costs GPU. Off leaves a clean sky."
	cloud_note.add_theme_font_size_override("font_size", 13)
	cloud_note.modulate = Color(1, 1, 1, 0.55)
	vb.add_child(cloud_note)'''
), (
    '''		"blood": set_blood = bool(value)
	_apply_settings()''',
    '''		"blood": set_blood = bool(value)
		"clouds": set_clouds = int(value)
	_apply_settings()'''
), (
    '''				"blood": cur = set_blood
			for pair: Array in (w["btns"] as Array):''',
    '''				"blood": cur = set_blood
				"clouds": cur = set_clouds
			for pair: Array in (w["btns"] as Array):'''
), (
    '''		if w.has_method("set_shadow_quality"):
			w.set_shadow_quality(set_shadows)''',
    '''		if w.has_method("set_shadow_quality"):
			w.set_shadow_quality(set_shadows)
		if w.has_method("set_cloud_mode"):
			w.set_cloud_mode(set_clouds)'''
), (
    '''	cf.set_value("gfx", "fov", set_fov)''',
    '''	cf.set_value("gfx", "fov", set_fov)
	cf.set_value("gfx", "clouds", set_clouds)'''
), (
    '''	set_fov = clampf(float(cf.get_value("gfx", "fov", 75.0)), 60.0, 110.0)''',
    '''	set_fov = clampf(float(cf.get_value("gfx", "fov", 75.0)), 60.0, 110.0)
	set_clouds = clampi(int(cf.get_value("gfx", "clouds", 1)), 0, 2)'''
),
# ---- the sky menu: ' opens it, and it behaves like every other panel ----
(
    '''var creative_panel: PanelContainer   ## G — every item in the game, one click away''',
    '''var creative_panel: PanelContainer   ## G — every item in the game, one click away
var sky_panel: SkyMenu               ## \' — scrub the clock, force the weather'''
), (
    '''	_build_creative_menu()''',
    '''	_build_creative_menu()
	## The sky menu builds itself (scripts/SkyMenu.gd) — Player only has to
	## hang it on the HUD and treat it like the other panels.
	sky_panel = SkyMenu.new()
	hud_layer.add_child(sky_panel)'''
), (
    '''	creative_panel.visible = which == "creative"
	if which == "tab":''',
    '''	creative_panel.visible = which == "creative"
	if sky_panel:
		sky_panel.visible = which == "sky"
	if which == "sky" and sky_panel:
		sky_panel.refresh()
	if which == "tab":'''
), (
    '''	creative_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED''',
    '''	creative_panel.visible = false
	if sky_panel:
		sky_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED'''
), (
    '''		elif menu_open == "creative":
			panel = creative_panel''',
    '''		elif menu_open == "creative":
			panel = creative_panel
		elif menu_open == "sky":
			panel = sky_panel'''
), (
    '''			KEY_ESCAPE:
				if menu_open != "":''',
    '''			KEY_APOSTROPHE:
				## \' — the sky menu: time, season, weather, lightning, aurora.
				_toggle_menu("sky")
			KEY_ESCAPE:
				if menu_open != "":'''
)])


# =============================================================== report =====

print("")
if changed:
    print("patched %d file(s): %s" % (len(changed), ", ".join(sorted(set(changed)))))
    print(".bak left beside each one.")
else:
    print("nothing to do -- already wired up.")
if skipped:
    print("")
    print("!! %d anchor(s) missed: %s" % (len(skipped), ", ".join(sorted(set(skipped)))))
    print("   Those files drifted since this was written; wire them by hand.")
    sys.exit(1)
