extends Node3D
## Forest test world for the vertical slice. Builds everything in code so there
## are no fragile scene-wiring dependencies: atmosphere, ground (with cave entry
## holes cut into it), a scattered low-poly forest, procedural caves, the player,
## and a few roaming enemies. Also runs the underground ambience shift and the
## "Now Entering"-style location titles.

const WORLD_RADIUS := 80.0
## 140 trees over an 80 m disc is one tree every twelve metres — a savanna with
## gaps you can see clean through. A wood wants roughly one every five or six,
## and it wants them in GROVES with clearings between, not evenly sprinkled.
const TREE_COUNT := 420
## MASTER SWITCH for the camp's own 420-tree wood. Off 2026-09-02 (Lemon:
## "remove all trees for now... I want to hand place them") -- pair with
## Overworld.SCATTER, which owns the streamed forest everywhere else.
## The god editor's Trees tool plants regardless; those are tagged "built"
## and live in design/build_placements.json.
const PLANT_FOREST := false
const GROVE_CHANCE := 0.76      ## odds the next tree joins the last one's grove
const GROVE_SPREAD := Vector2(2.6, 6.5)   ## how far from its neighbour it lands
const TREE_MIN_GAP := 2.1       ## trunks must not grow through each other

## --- what actually grows where (trees v4, 2026-08-30) ---------------------
## A five-way coin flip per tree is why the wood read as a garden centre: real
## stands are one species with a minority mixed through, and real size classes
## are a reverse J, not a bell. Both of those are applied PER GROVE.
##   FOREST_MIX      a northern-hardwood / spruce-fir composition, which is
##                   what a Maine wood at this latitude actually is
##   GROVE_DOMINANCE the share of a stand that is its dominant species
##   DE_LIOCOURT_Q   in an uneven-aged stand, each size class up holds 1/q of
##                   the one below it. 1.30 is the gentle end of the measured
##                   1.2-1.6 band, kept gentle on purpose: the real ratio buries
##                   the wood in saplings and there is a game to play here.
## Set FOREST_RATIOS = false for the old flat roll.
const FOREST_RATIOS := true
const FOREST_MIX := {"maple": 0.26, "fir": 0.24, "birch": 0.18, "oak": 0.16, "pine": 0.16}
const GROVE_DOMINANCE := 0.72
const DE_LIOCOURT_Q := 1.30
## A meteor crater is 4.6 m across; anything rooted within this of the centre
## has lost the ground it stood on.
const METEOR_FELL_RADIUS := 7.5
const ROCK_COUNT := 14
## The PSX Nature pack (docs/TREES_v3_PSX.md). false puts the grey boxes and
## the procedural trees back.
const USE_PSX_NATURE := false
const PSX_REGION := "temperate"
## Fallen logs, old stumps and standing boulders -- the pieces of the wood you
## can trip over, climb onto or chop up. The small litter is instanced without
## collision by Understory; these are real bodies, so there are not many.
const PROP_COUNT := 96
const PROP_MIN_GAP := 3.2
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

## [fort] the granite work on the narrows. One flag off and the fort, its
## punched hole and its map marker all stay out of the world.
const USE_FORT := true
const FORT_NAME := "Fort Knox"


var _rng := RandomNumberGenerator.new()
var _cave_sites: Array[Dictionary] = []  ## {mouth: Vector3, dir: Vector3, rect: Rect2}
var _env: Environment
var _daynight: DayNight
var _cities: Node3D = null    ## [cities] the big six, scripts/Cities.gd
var _wind: Wind
var _sky: SkyRig
var _weather: Weather
## Weather thickens surface fog. _process aims the Environment at BASE_FOG
## scaled by this — caves keep their own fog untouched.
var weather_fog_scale := 1.0
## --- wildlife ---
var _wildlife: WildlifeDirector      ## who is out there, and when
var _chronicle: Chronicle            ## [chronicle] what happened while you were away
var _incidents: IncidentDirector     ## [incidents] and what of it you can walk into
var _rumours: RumourFeed             ## [rumours] and what they are saying about it
var _roads: RoadNet                  ## [roadnet] and the roads between the places
var _wayfarers: Wayfarers            ## [wayfarers] and who is out walking them
var _crofts: Crofts                   ## [crofts] and who lives out between them
var _carcasses: Carcasses            ## [carcasses] and what the woods do with a kill
var _warbands: Warbands              ## [warbands] and who holds the ground it happens on
var _water_audio: WaterAudio = null  ## [water] shores, strokes, the muffle under
var _step_audio: StepAudio = null    ## [steps] the ground under your feet
var _drowned: Node3D = null          ## [water] the thing that has the swimmer, if any
var _drowned_risk := 0.0             ## [water] builds while you swim deep water at night
var _drowned_cd := 0.0               ## [water] seconds until it can happen again
var _telegraph: Telegraph            ## the forest's alarm bus
var _critter_audio: CritterAudio     ## calls, and the ambience bed
var _fire_audio: FireAudio = null    ## [fire] beds, crackles, and the one shadow

## Trees v2 master switch — see _make_tree().
const USE_TREES_V2 := true

## --- the overworld --------------------------------------- ## [terrain] flags
## USE_TERRAIN false = the old walled valley, and nothing else changes.
const USE_TERRAIN := true
## The valley's fog is built for a 100 m box. Maine needs to see Katahdin from
## five kilometres away, so the surface fog thins hard when the terrain is on.
const TERRAIN_FOG := 0.0011
## [water] underwater: fog density and its colour per water kind
const UNDER_FOG := 0.055
const UNDER_FOG_LAKE := Color(0.10, 0.13, 0.06)   ## tannin: tea held to the light
const UNDER_FOG_SEA := Color(0.05, 0.11, 0.13)    ## the Gulf: cold slate-green
const TERRAIN_FAR := 9000.0        ## camera far plane, so the ranges render
## Loaded by PATH, never by class_name. A GDExtension can register a native
## class that shadows any script class_name without a parse-time warning --
## TerraBrush registers a non-instantiable `Terrain` and that is exactly what
## bit us. preload() resolves the file, so nothing can shadow it.
const OverworldScript := preload("res://scripts/Overworld.gd")
var _terrain: Node3D = null        ## the ground, or null when USE_TERRAIN is off
const PLACE_TITLE_R := 240.0       ## a town's name shows within this of its marker
var _place_name := ""              ## the last place/region announced
var _place_t := 0.0

var _player: Player
var _underground := false
var _title_label: Label
var _title_timer := 0.0
var _ambient_scale := 1.0  ## RT lighting trades flat ambient for bounced light


func _ready() -> void:
	add_to_group("world")  ## the settings menu finds the lighting through this
	_rng.seed = 20260630  ## fixed seed = same world each run (change for variety)
	## ===================== PHASE ONE: the front end ======================
	## Lemon, 2026-09-04: "main menu should be it's own seperate part that
	## loads fully with the setting menu... all before the actual game."
	##
	## So _ready builds ONLY what the menu needs: the curtain, an atmosphere
	## to hang it in, the parked body (which is what owns the settings panel),
	## and the card itself. That is a fraction of a second — every row on the
	## menu is live almost the moment the window opens, instead of after a
	## whole map has been generated.
	_build_blackout()
	_build_environment()
	_build_titles()      ## a Label; _show_title must never find it null
	_build_park_floor()  ## something for the parked body to stand on
	_spawn_player()
	## The body is parked and blind until a row is picked.
	if _player:
		_player.input_locked = true
	_build_main_menu()   ## THE FRONT DOOR
	## ===== PHASE TWO is begin_world(), and it waits for PLAY / DEV MODE ===


func begin_world() -> void:
	## PHASE TWO: the actual game. Called a few frames after the card is gone
	## (see front_door_done), so the black MYRKFELL curtain is already on
	## screen when the main thread disappears in here to generate a map.
	if _park_floor != null:
		_park_floor.queue_free()
		_park_floor = null
	_build_terrain()  ## [terrain] build call
	_pick_cave_sites()
	_build_ground()
	_build_forest()
	_build_rocks()
	_build_props()   ## fallen logs, stumps and boulders you can climb on
	_build_caves()
	_build_border()
	_build_fort()  ## [fort]
	_build_camp()  ## the bedroll starts in the pack
	_build_water_audio()  ## [water] needs the player as its listener
	_spawn_enemies()
	_build_wildlife()  ## --- wildlife ---
	## Set the body down on the ground that now exists, not on the slab that
	## no longer does.
	if _player:
	_player.input_locked = true
	_player.global_position = _world_home()
	_player.velocity = Vector3.ZERO


_cities = Cities.boot(self)    ## [cities] the big six stand up last, after the roster, the net and the crofts

func _build_park_floor() -> void:
	## Phase one has no ground. A CharacterBody3D with nothing under it falls
	## until the out-of-world net yanks it home, over and over, for as long as
	## the player reads the menu. One invisible slab at y = 0 — the valley
	## floor's own height — freed the instant the real world starts building.
	_park_floor = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 2, 400)
	shape.shape = box
	_park_floor.add_child(shape)
	_park_floor.position = Vector3(0, -1, 0)
	add_child(_park_floor)



func _process(delta: float) -> void:
	## The window grows DURING _ready — _build_blackout is the first thing that
	## runs and the viewport it sees is half the one the player ends up with,
	## and size_changed does not fire again for it. So the curtain's MYRKFELL
	## re-cuts itself whenever the size it was cut for stops being true.
	if _black_title != null and _black_vp != get_viewport().get_visible_rect().size:
		_fit_black_title()

	## The countdown front_door_done started: the curtain has had its frames,
	## now go and build a world.
	if _world_wait > 0:
		_world_wait -= 1
		if _world_wait == 0:
			_world_begun = true
			begin_world()

	if _player == null or _env == null:
		return

	## [steps] the wetness feed. One line per frame; the bus itself is
	## built next to WaterAudio and does nothing until it has a surface.
	_feed_step_wetness()

	## [seasons] the local-year feed. Same shape as the line above: one call
	## per frame, and the season the foliage shaders paint becomes the season
	## at the PLAYER'S FEET rather than the one on the calendar.
	_feed_local_season()

	## Safety net: fell out of the world somehow — OR ended up beyond the
	## border walls (old saves, climb edge cases) — back to the spawn.
	if _out_of_world(_player.global_position) and not _player.god:  ## [terrain] bounds net
		_player.global_position = _world_home()
		_player.velocity = Vector3.ZERO

	## And never trapped INSIDE the rock (slipped through some sliver into
	## the space between caves): a full second buried = pulled home.
	## [terrain] ONLY inside the CaveRegion's footprint. CaveField.is_rock()
	## used to clamp any position into the 208 m field, so every metre of the
	## overworld below y = 0 -- Portland sits at -17 -- read as "buried" and
	## yanked you back to spawn after one second. That was the whole "I can't
	## leave the valley" bug (survey 2026-08-31).
	if _region != null and _region.is_fully_loaded() and _player.global_position.y < 0.0 \
			and not _player.god \
			and _region.in_footprint(_player.global_position) \
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
	## [terrain] Depth is measured from the LOCAL surface, never from y = 0:
	## the valley floor is 0 but the map runs from -27 (sea floor) to 597.
	## With the raw y, the whole coast was "The Hollow Depths" in cave gloom.
	var surf_y: float = _surface_y(_player.global_position)
	var below := _player.global_position.y < surf_y - 3.0
	if below != _underground:
		_underground = below
		_show_title(_place_title_for(below))  ## [fort]

	## ...but the LIGHT never flips at a line: it rides DEPTH. Descending a
	## throat dims by the meter — full daylight above -1.2, full cave gloom by
	## -8.5, smoothstepped between — so the dark closes over you the way deep
	## water does, and climbing out returns the sky shade by shade. A gentle
	## ease then chases that blend, so even a straight fall down a shaft
	## never snaps the eye. Surface targets still ride the day/night clock.
	var depth_u := clampf((surf_y - 1.2 - _player.global_position.y) / 7.3, 0.0, 1.0)
	depth_u = depth_u * depth_u * (3.0 - 2.0 * depth_u)
	var s_amb := _daynight.surf_ambient if _daynight else BASE_AMBIENT
	var s_fog_col := _daynight.surf_fog if _daynight else BASE_FOG_COLOR
	var want_ambient := lerpf(s_amb, CAVE_AMBIENT, depth_u)
	## Surface fog thickens with the weather; the cave end of the lerp doesn't.
	## [terrain] fog base: the valley's fog is tuned for a 100 m box and
	## would bury Katahdin. _process re-aims fog_density every frame, so
	## the base has to change HERE, not once at build time.
	var _fog0: float = TERRAIN_FOG if _terrain != null else BASE_FOG
	var want_fog := lerpf(_fog0 * weather_fog_scale, CAVE_FOG, depth_u)
	var want_fog_col := s_fog_col.lerp(CAVE_FOG_COLOR, depth_u)
	var k := 1.0 - pow(0.30, delta)  ## framerate-independent smoothing (unhurried)
	_env.fog_density = lerpf(_env.fog_density, want_fog, k)
	_env.ambient_light_energy = lerpf(_env.ambient_light_energy, want_ambient * _ambient_scale, k)
	_env.fog_light_color = _env.fog_light_color.lerp(want_fog_col, k)
	## Underground the sky goes DARK — the heavy cave fog fully covers it, so
	## any glimpse of sky through a crack reads as gloom, not blue daylight.
	## The brightness at a mouth comes from its own light shaft (god rays,
	## CaveRegion._dress_mouth), not from the sky peeking through the fog.
	## [terrain] ...and ONLY underground. This lerped toward 1.0 everywhere,
	## which painted the whole sky the fog colour on the surface too -- a flat
	## grey-green lid over Maine at noon, and the sky shader's sunsets and
	## clouds never showed. It rides the same depth blend as the fog now.
	_env.fog_sky_affect = lerpf(_env.fog_sky_affect, depth_u, k)

	## [water] Ears under: the world closes in. Dense tea-coloured fog a few
	## metres deep, the sky gone, the light dimmed -- the plane's own underside
	## is a dark mirror, and this is what makes it read as being IN the lake
	## rather than looking at a blue rectangle. Rides the player's eased
	## submersion so a bob at the surface never flickers it.
	var uw: float = _player.submerged() if _player.has_method("submerged") else 0.0
	if uw > 0.001:
		var sea_uw := Overworld.water_is_sea(_player.global_position)
		var uw_col := UNDER_FOG_SEA if sea_uw else UNDER_FOG_LAKE
		_env.fog_density = lerpf(_env.fog_density, UNDER_FOG, uw * 0.9)
		_env.fog_light_color = _env.fog_light_color.lerp(uw_col, uw * 0.9)
		_env.fog_sky_affect = maxf(_env.fog_sky_affect, uw)
		_env.ambient_light_energy = lerpf(_env.ambient_light_energy, want_ambient * _ambient_scale * 0.55, uw)
	_drowned_tick(delta, uw)

	## Startup curtain: lift it only when the whole underground (and its
	## content) is genuinely finished — the game begins already smooth.
	if _loading and _region != null and _region.is_fully_loaded():
		_loading = false
		set_blackout(false, "")
		## ...unless the front door is still up: MainMenu holds the body until
		## you pick a row, and calls front_door_done() when you do. If you
		## picked one WHILE the deep was still streaming, this is the moment
		## it takes effect — the black MYRKFELL curtain was the wait.
		if not main_menu_open:
			_hand_over()

	## --- wildlife ---  The wildlife runs on DayNight's calendar, never its own.
	if _wildlife != null and _daynight != null:
		_wildlife.set_clock(_daynight.hour, _daynight.day)

	## [terrain] "Now entering": the nearest named town, else the region you
	## are crossing. Checked a few times a second, announced once per place.
	if _terrain != null:
		_place_t -= delta
		if _place_t <= 0.0:
			_place_t = 0.6
			## [water] the sky the lakes reflect follows the clock
			if _daynight != null and _terrain.has_method("set_water_sky"):
				_terrain.set_water_sky(_daynight.sky_horizon)
			var nm: String = _terrain.place_name_at(_player.global_position, PLACE_TITLE_R)
			if nm == "":
				nm = _terrain.region_name_at(_player.global_position)
			if nm != _place_name:
				_place_name = nm
				if nm != "" and not _underground:
					_show_title(nm)

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

	## One wind for the whole world: leaves, bark, and later grass and cloth all
	## read the same global shader parameters. See scripts/Wind.gd, spec §7.
	_wind = Wind.new()
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
	add_child(_weather)

	## ...and the clock the moss grows by: game hours x rain x shade x season.
	## Bound to the live DayNight/Weather so a patch restored mid-apply_state
	## reads the day the save just set, not last frame's.
	GrowthClock.bind(_daynight, _weather)
	add_child(GrowthClock.new())


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
var _black_title: TextureRect  ## MYRKFELL, white, on the loading curtain
var _black_vp := Vector2.ZERO  ## the viewport size that word was cut for


var main_menu_open := false  ## the front door is up; nothing unlocks the body
var _menu_dev := false       ## DEV MODE was the row picked; open god on hand-over
var _park_floor: StaticBody3D = null  ## phase-one ground under the parked body
var _world_begun := false    ## begin_world() has run — phase two is done or under way
var _world_wait := 0         ## frames left before it does, so the curtain draws first


func _build_main_menu() -> void:
	## THE FRONT DOOR (scripts/MainMenu.gd, 2026-09-04). An overlay at layer 90,
	## above the loading curtain at 80, so the world streams in behind the title
	## card instead of behind a black rectangle. It owns input_locked until you
	## pick PLAY or DEV MODE, which is why the unlock below asks it first.
	##
	## Loaded BY PATH, never by class_name — same rule as MapPanel in
	## Player._build_hud: this runs on the cold open and a name-level cycle
	## here is a parse error before anything boots.
	var menu: Node = load("res://scripts/MainMenu.gd").new()
	main_menu_open = true
	add_child(menu)
	if menu.has_method("setup"):
		menu.setup(self, _player)


func front_door_done(dev: bool) -> void:
	## The card is gone. Nothing on it is ever greyed out (Lemon, 2026-09-04:
	## "don't dim the buttons, let it go to the myrkfell loading screen"), so
	## PLAY can land while the deep is still streaming. If it does, the black
	## MYRKFELL curtain is already underneath and _process hands the body back
	## the moment the region finishes. Otherwise it happens right now.
	main_menu_open = false
	_menu_dev = dev
	if not _world_begun:
		## Phase two has not run. Give the black MYRKFELL curtain a few frames
		## to actually reach the screen before the main thread vanishes into
		## begin_world() — otherwise the last frame of the menu is what sits
		## there frozen while the map generates.
		_world_wait = 4
		return
	if _loading:
		return
	_hand_over()


func _hand_over() -> void:
	## Give the player their body, their mouse, and — if DEV MODE was the row —
	## F1's own path, so god mode comes up exactly as it does live.
	if _player == null:
		return
	if _player.sleep_phase == "":
		_player.input_locked = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _menu_dev:
		_menu_dev = false
		if _player.has_method("_toggle_menu"):
			_player._toggle_menu("god")


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
	## THE LOADING SCREEN (Lemon, 2026-09-04): black, with MYRKFELL in white,
	## in the menu's own lettering. PixelFont is loaded BY PATH and never by
	## class_name — this is the coldest part of the cold open.
	var stack := VBoxContainer.new()
	stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 22)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blackout.add_child(stack)

	_black_title = TextureRect.new()
	_black_title.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_black_title.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_black_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_black_title)
	## Sized from the viewport, and RE-sized when it changes: _build_blackout
	## is the first thing _ready does and the viewport it reports there is not
	## the one the player ends up looking at — cut the word once at boot and it
	## comes out a quarter of the size it should be.
	_fit_black_title()
	get_viewport().size_changed.connect(_fit_black_title)

	## The quiet line underneath — empty at boot, used by set_blackout() for
	## "Remembering the world..." and the sleep shift.
	_black_label = Label.new()
	_black_label.text = ""
	_black_label.add_theme_font_size_override("font_size", 18)
	_black_label.modulate = Color(0.62, 0.64, 0.70, 0.80)
	_black_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_black_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_black_label)


func _fit_black_title() -> void:
	## MYRKFELL wants to read as a title, not a caption: about a third of the
	## width, cut fresh at a whole-number pixel scale every time the window
	## changes so it never blurs.
	if _black_title == null:
		return
	var vs := get_viewport().get_visible_rect().size
	_black_vp = vs
	var sc := clampi(mini(int(vs.x / 210.0), int(vs.y / 90.0)), 3, 16)
	var pf: GDScript = load("res://scripts/PixelFont.gd")
	_black_title.texture = pf.render("MYRKFELL", Color(1, 1, 1), Color(0, 0, 0, 0), sc)
	_black_title.custom_minimum_size = Vector2(0, _black_title.texture.get_height())


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
	## The crater takes the ground out from under whatever was standing on it.
	## Trees inside the blast go over, away from the impact, and leave a real
	## trunk on the ground — before this the hole simply swallowed the base and
	## the tree stood there with nothing underneath it.
	for t in get_tree().get_nodes_in_group("trees"):
		var tv := t as TreeV2
		if tv == null or tv.felled:
			continue
		if tv.global_position.distance_to(spot) <= METEOR_FELL_RADIUS:
			tv.blast_fell(spot)

	if _player:
		var d := _player.global_position.distance_to(spot)
		_player.cam_shake = maxf(float(_player.cam_shake), clampf(0.62 - d * 0.004, 0.12, 0.62))
		_player.call("_add_log_msg", "The star has fallen to the %s!" % _compass(spot - _player.global_position),
			Color(1.0, 0.62, 0.28))


func _compass(v: Vector3) -> String:
	var a := fposmod(rad_to_deg(atan2(-v.x, v.z)) + 22.5, 360.0)
	return ["south", "south-west", "west", "north-west", "north", "north-east", "east", "south-east"][int(a / 45.0) % 8]


## [seasons] THE YEAR IS A PLACE. `Wind.publish_season(day)` put ONE phase on
## the whole 41.7 km map, and published it only at the midnight rollover and
## on load — so sleeping (which moves the day by any amount without crossing
## a rollover in `DayNight._process`) left every foliage shader painting
## yesterday's season until the next natural midnight, and setting the day by
## hand never updated them at all.
##
## Both halves are fixed here. The phase published is `Seasons.local_phase` at
## the player's position, so walking north or climbing turns the meadow and
## brings the snow in under your boots; and it is republished whenever it has
## actually moved, which no longer depends on how the day changed.
##
## Cheap by construction: the compare is against the last value PUBLISHED, so
## a standing player costs one float subtraction a frame and no RenderingServer
## traffic at all.
const SEASON_FEED_EPS := 0.0004   ## ~0.04 of a game day — finer than the eye
var _season_pub := -1.0

func _feed_local_season() -> void:
	if _daynight == null or _player == null:
		return
	var p := Seasons.local_phase(_daynight.day, _player.global_position)
	## A year-wrap (0.999 -> 0.001) is a LARGE delta and publishes, which is
	## what we want; there is no second clause guarding it, because one would
	## be unreachable under any EPS below a half.
	if _season_pub >= 0.0 and absf(p - _season_pub) < SEASON_FEED_EPS:
		return
	_season_pub = p
	Wind.phase = p
	RenderingServer.global_shader_parameter_set("season_phase", p)


func daynight() -> DayNight:
	## [exposure] The clock, for anything that needs the hour or the day.
	## `_daynight` was private and Exposure is the third customer to want it.
	return _daynight


func underground() -> bool:
	## [exposure] Public face of `_underground`: a cave shelters you from the
	## wind and the rain exactly as a roof does.
	return _underground


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



## [fort] Stand Fort Knox up on the west bank of the Penobscot narrows, and
## register it as a place so the map dot and the on-screen title both come
## free — Overworld.places() hands back the live array, so appending to it is
## all a landmark needs to exist everywhere the towns do.
func _build_fort() -> void:
	if not USE_FORT or _terrain == null:
		return
	var f := FortKnox.raise_fort(self)
	if f == null:
		push_warning("World: Fort Knox needs loaded terrain — skipped.")
		return
	for p in _terrain.places():
		if String((p as Dictionary).get("name", "")) == FORT_NAME:
			return
	_terrain.places().append({
		"name": FORT_NAME,
		"pos": [FortKnox.SITE_X, FortKnox.SITE_Z],
		"y": f.pad_y,
		"rank": 1,
	})


## [fort] underground title — the depth title is right for a cave and wrong
## for a magazine, so the fort names its own inside.
func _place_title_for(below: bool) -> String:
	if USE_FORT and _player != null and FortKnox.contains(_player.global_position):
		if below:
			return "%s — the Undercroft" % FORT_NAME
		return FORT_NAME
	return "The Hollow Depths" if below else "The Dusk Forest"

func _build_camp() -> void:
	## Your bedroll starts ROLLED UP IN THE PACK -- nothing is laid out on the
	## ground at spawn any more. Click the Bedroll item in the inventory to
	## unroll it wherever the ground is flat; look + E packs it back up
	## (Bedroll.gd). The roll shows strapped to the rucksack while you own it.
	if _player == null:
		return
	_player._give_item("Bedroll", 1, 4.0)


func sleep_at_bed(hours: float = 8.0) -> bool:
	## Sleep until dawn — and the earth USES the night: the whole underground
	## reseeds and re-carves (except the permanent caves around each mouth).
	## False if the previous build/shift is still running.
	##
	## `hours` is how much of the night the sleeper actually GOT. The cold can
	## cut it short (see `Slumber`), and a man woken at four in the morning
	## wakes the world at four in the morning, not at dawn.
	if _region == null or not _region.reset_underground():
		return false
	if _daynight:
		## FORWARD, ALWAYS. This line used to read `hour = 6.0` with no day
		## increment, which from any evening walks the sky BACKWARDS — fifteen
		## hours, from nine at night. Chronicle, Crofts, Carcasses, Wayfarers
		## and GrowthClock every one bank FORWARD time only (`d > 0.0` in their
		## `_tick_clock`), so every one of them correctly ignored the single
		## action a player uses to skip time; `IncidentDirector._now_days()`
		## carries a `maxf` floor whose comment names this bug by name.
		## Turning the hand the right way is the entire fix: all five catch up
		## on their own, off their own clock reading, with no new plumbing.
		var slept := maxf(0.0, hours)
		var from_h := fposmod(float(_daynight.hour), 24.0)
		_daynight.day = _daynight.day + Slumber.days_crossed(from_h, slept)
		_daynight.hour = Slumber.hour_after(from_h, slept)
	if _player:
		_player.cam_shake = maxf(float(_player.cam_shake), 0.4)
	_show_title("The World Has Shifted")
	return true


func _build_border() -> void:
	## [terrain] border: the map rim replaces the walls when the
	## overworld is on -- _out_of_world() is the net out there.
	if _terrain != null:
		return
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



## [terrain] builder -----------------------------------------------------------
## Build the ground BEFORE _build_border and _spawn_player: the border net and
## the camera's far plane both ask the terrain how big the world is, and the
## player must have something to stand on before it is dropped.
func _build_terrain() -> void:
	if not USE_TERRAIN:
		return
	_terrain = OverworldScript.new()
	_terrain.name = "Terrain"
	add_child(_terrain)
	if not _terrain._loaded:
		## No bake on disk (or *.r16 missing from the export filter). Fall back
		## to the valley rather than dropping the player into nothing.
		push_warning("World: terrain data did not load -- staying in the valley.")
		_terrain.queue_free()
		_terrain = null
		return
	if _env != null:
		_env.fog_density = TERRAIN_FOG


## [terrain] The ground height under a position: the heightfield's answer out
## on the map, 0 in the valley (and everywhere when the terrain is off). Every
## "how deep am I" question in this file goes through here.
func _surface_y(p: Vector3) -> float:
	if _terrain != null:
		return _terrain.sample_height(p.x, p.z)
	return 0.0


## [terrain] True once the player has left the map entirely. With the terrain
## on this is the map rim; without it, the old +/-103 box.
func _out_of_world(p: Vector3) -> bool:
	if p.y < -60.0:
		return true
	if _terrain != null:
		return not _terrain.pos_in_bounds(p)
	return absf(p.x) > 103.5 or absf(p.z) > 103.5


## [terrain] Where a lost player is put back. The valley, always -- it is the
## one place in the world guaranteed to have ground at y = 0.
func _world_home() -> Vector3:
	return Vector3(0, 2, 0)

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
	if not PLANT_FOREST:
		return        ## hand-placed only -- see PLANT_FOREST
	## Grow the wood in groves: most trees land near the previous one, some
	## start a new stand somewhere else. That leaves clearings and thickets
	## instead of an even sprinkle, and it closes the see-through gaps.
	var placed: Array[Vector3] = []
	var last := Vector3.INF
	for i in range(TREE_COUNT):
		var pos := Vector3.INF
		## ONE roll decides both things, or the stand's species and the stand's
		## position stop agreeing with each other.
		var join := last != Vector3.INF and _rng.randf() < GROVE_CHANCE
		if not join:
			## a new stand: its own dominant species, its own leader
			_grove_species = _pick_species()
			_grove_leader = true
		if join:
			for _try in range(6):
				var a := _rng.randf() * TAU
				var r := _rng.randf_range(GROVE_SPREAD.x, GROVE_SPREAD.y)
				var cand := last + Vector3(cos(a) * r, 0.0, sin(a) * r)
				if cand.length() > WORLD_RADIUS or cand.length() < SPAWN_CLEAR:
					continue
				pos = cand
				break
		if pos == Vector3.INF:
			pos = _random_ground_point()
		if pos == Vector3.INF:
			continue
		var clash := false
		for q in placed:
			if q.distance_to(pos) < TREE_MIN_GAP:
				clash = true
				break
		if clash:
			continue
		placed.append(pos)
		last = pos
		add_child(_make_tree(pos))

func _make_tree(pos: Vector3) -> StaticBody3D:
	## Trees v2 (docs/TREES_v2_SPEC.md): five New England species, five life
	## stages, real limbs. The axe takes the BRANCHES off first — the trunk
	## refuses a bite until the tree is bare — then the trunk goes over as a
	## physics body, and the fallen trunk bucks into logs.
	##
	## Set USE_TREES_V2 = false to fall back to the old cone trees (ChopTree.gd)
	## if something in the new pipeline misbehaves.
	if USE_TREES_V2:
		var t := TreeV2.make(_rng) if not FOREST_RATIOS \
			else TreeV2.make(_rng, _grove_species_pick(), _pick_stage())
		t.position = pos
		t.rotation.y = _rng.randf() * TAU
		return t
	var tree := ChopTree.make(_rng)
	tree.position = pos
	tree.rotation.y = _rng.randf() * TAU
	return tree

## --- the stand's own composition -----------------------------------------

var _grove_species := "maple"
var _grove_leader := false


func _pick_species() -> String:
	var r := _rng.randf()
	for sp in FOREST_MIX.keys():
		r -= float(FOREST_MIX[sp])
		if r <= 0.0:
			return String(sp)
	return "maple"


func _grove_species_pick() -> String:
	## Most of a stand is its dominant species; the rest is whatever else grows
	## at this latitude. A pure monoculture reads as fake in the other direction.
	return _grove_species if _rng.randf() < GROVE_DOMINANCE else _pick_species()


func _pick_stage() -> int:
	var r := _rng.randf()
	if _grove_leader:
		## The stem that won the light. A stand has one or two of these standing
		## over everything else, and they are what you see from a ridge.
		_grove_leader = false
		return 4 if r < 0.05 else (3 if r < 0.50 else 2)
	## de Liocourt in the understory: each size class up holds 1/q of the one
	## below it, which is why a real stand is a crowd of small stems under a few
	## big ones instead of an even spread of middling ones.
	var w1 := 1.0
	var w2 := 1.0 / DE_LIOCOURT_Q
	var w3 := 1.0 / (DE_LIOCOURT_Q * DE_LIOCOURT_Q)
	r *= (w1 + w2 + w3)
	if r < w1:
		return 1
	if r < w1 + w2:
		return 2
	return 3


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
		## A grey box among the pack's art reads as a missing asset, so the
		## boulders wear real rock now. The body, the groups and the `bites`
		## meta are untouched -- Player._chop_boulder never learns about this.
		if USE_PSX_NATURE:
			var big := ["SM_Rock_05", "SM_Rock_07", "SM_Rock_08", "SM_Rock_04"]
			var asset: String = big[_rng.randi() % big.size()]
			var packed = load(PSXNature.scene_path(asset))
			if packed != null:
				var m3: Node3D = packed.instantiate()
				var native: float = maxf(float(PSXNature.info(asset).get("height", 1.0)), 0.05)
				m3.scale = Vector3.ONE * (s * 1.2 / native)
				m3.rotation.y = _rng.randf() * TAU
				rock.add_child(m3)
				var rmats := PSXNature.materials("Props", PSX_REGION, false)
				var rmeshes: Array = []
				for n3 in _all_nodes(m3):
					var rmi := n3 as MeshInstance3D
					if rmi != null and rmi.mesh != null:
						for si in range(rmi.mesh.get_surface_count()):
							rmi.set_surface_override_material(si, rmats[0])
						rmeshes.append(rmi)
				_dress_rock(rock, rmeshes, s, i)
				continue
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
		_dress_rock(rock, [mesh], s, i)


## What grows on a boulder (2026-09-03): moss on its shaded north face and
## down its foot, lichen crusting its top. The patches probe the rock's MESH
## (the tilted one you see), not its axis-aligned box collider, so they sit on
## the stone and not in the air beside it. Boulders are not serialised -- they
## come back from the world seed -- so each patch carries a ledger key and
## save_state/apply_state keep its growth under "growth".
func _dress_rock(rock: StaticBody3D, meshes: Array, s: float, i: int) -> void:
	var seed_v := _rng.randi()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var centre := Vector3(0, s * 0.55, 0)
	if rng.randf() < 0.85:
		var yaw := rng.randf_range(-0.5, 0.5)
		var facing := Vector3(sin(yaw) * 0.9, -0.2, -cos(yaw) * 0.9).normalized()
		var g := GrowthPatch.make(["moss", "moss", "moss", "fungi"][rng.randi() % 4], "", "", rng.randi())
		g.anchor_point(centre, facing, 0.55, 0.75, s * 3.0 + 1.0, true, s * s * 0.7)
		g.shade = GrowthPatch.shade_for(facing)
		g.growth = rng.randf_range(0.25, 0.75)
		g.probe_meshes = meshes
		g.host_key = "rock:%d:side" % i
		rock.add_child(g)
	if rng.randf() < 0.65:
		var g2 := GrowthPatch.make("lichen", "", "", rng.randi())
		g2.anchor_point(centre, Vector3.UP, 0.6, PI, s * 3.0 + 1.0, true, s * s * 0.5)
		g2.shade = 0.5
		g2.growth = rng.randf_range(0.5, 1.0)     ## lichen is slow; a rock is old
		g2.probe_meshes = meshes
		g2.host_key = "rock:%d:top" % i
		rock.add_child(g2)


func _all_nodes(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_all_nodes(c))
	return out


func _build_props() -> void:
	## Deadfall reads as a wood that has been standing a long time, which is
	## most of what makes a forest feel old. Logs cluster where trees are
	## thickest, so these follow the same grove logic the timber does.
	if not USE_PSX_NATURE:
		return
	var kinds := {
		"SM_FallenLog_Large": [0.55, 1.05],
		"SM_FallenLog_Small": [0.70, 1.30],
		"SM_Stump_01": [0.70, 1.40],
		"SM_Stump_02": [0.80, 1.60],
		"SM_Rock_05": [0.60, 1.50],
		"SM_Rock_07": [0.60, 1.40],
		"SM_Rock_08": [0.55, 1.30],
	}
	var names: Array = kinds.keys()
	var placed: Array[Vector3] = []
	for i in range(PROP_COUNT):
		var pos := _random_ground_point()
		if pos == Vector3.INF:
			continue
		var clash := false
		for q in placed:
			if q.distance_to(pos) < PROP_MIN_GAP:
				clash = true
				break
		if clash:
			continue
		placed.append(pos)
		var asset: String = String(names[_rng.randi() % names.size()])
		var band: Array = kinds[asset]
		var s := _rng.randf_range(float(band[0]), float(band[1]))
		add_child(PSXProp.make(asset, pos, _rng.randf() * TAU, s, PSX_REGION))


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
	## Hand-placed trees live in design/build_placements.json, not in this
	## save -- and their moss grows between the editor's own writes. Flush the
	## builder first so the file a load restores them from carries the growth
	## they have NOW, not the growth they had when you last planted something.
	get_tree().call_group("builder", "save_now")
	var trees: Array = []
	for group in ["trees", "tree_stumps"]:
		for t in get_tree().get_nodes_in_group(group):
			## [terrain] streamed trees: the ones the terrain scattered are
			## regenerated on load, never serialised -- 4,000 of them would
			## bloat every save and pin them to a tile that has moved on.
			if (t as Node).has_meta("streamed"):
				continue
			## ...and neither are the ones the god editor planted: those live
			## in design/build_placements.json and are restored by the
			## "builder" group, so they survive a new run, not just a load.
			if (t as Node).has_meta("built"):
				continue
			## BUG 5, BACK AGAIN (docs/TREES_v2_SPEC.md §21): this used to read
			## `if t is ChopTree` and nothing else, so the ENTIRE TreeV2 forest
			## was never written -- and apply_state cleared the group before
			## restoring, so a load silently deleted every tree in the world.
			## It was fixed once and a later patcher put the old World.gd back.
			## If you touch this loop, keep all three branches.
			if t is TreeV2:
				trees.append((t as TreeV2).save_dict())
			elif t is TreeStump:
				trees.append((t as TreeStump).save_dict())
			elif t is ChopTree:
				trees.append((t as ChopTree).save_dict())
	var props: Array = []
	for pr in get_tree().get_nodes_in_group("psx_props"):
		if pr is PSXProp:
			props.append((pr as PSXProp).save_dict())
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
	## The growth LEDGER: patches whose host is not itself serialised (boulders,
	## cave mouths -- both rebuilt from the world seed). Trees carry their own
	## inside save_dict, and those have no key.
	var growth: Array = []
	for g in get_tree().get_nodes_in_group("growth_patches"):
		if g is GrowthPatch and (g as GrowthPatch).host_key != "":
			growth.append((g as GrowthPatch).to_dict())
	var out := {
		"hour": _daynight.hour if _daynight else 17.0,
		"day": _daynight.day if _daynight else 0.0,
		## marks a save whose day counter already starts at DayNight.START_DAY,
		## so apply_state does not shift it forward a second time
		"season_based": true,
		"weather": _weather.to_dict() if _weather else {},
		"trees": trees, "props": props, "logs": logs, "dropped": dropped, "beds": beds,
		"growth": growth,
	}
	if _wildlife != null:
		out["wildlife"] = _wildlife.save_state()  ## --- wildlife ---
	out["chronicle"] = _chronicle.to_dict() if _chronicle else {}  ## [chronicle]
	out["incidents"] = _incidents.to_dict() if _incidents else {}  ## [incidents]
	out["rumours"] = _rumours.to_dict() if _rumours else {}        ## [rumours]
	out["wayfarers"] = _wayfarers.to_dict() if _wayfarers else {}    ## [wayfarers]
	out["crofts"] = _crofts.to_dict() if _crofts else {}          ## [crofts]
	out["carcasses"] = _carcasses.to_dict() if _carcasses else {}  ## [carcasses]
	out["warbands"] = _warbands.to_dict() if _warbands else {}    ## [warbands]
	if _terrain != null:
		out["overworld"] = _terrain.save_state()  ## [terrain] the felled-slot ledger
	if _region != null:
		out["cave"] = _region.save_state()
		## Untyped on purpose: the floor is a GrassSystem or an Understory.
		var floor_sys = _region.grass()
		if floor_sys != null and floor_sys.has_method("save_state"):
			out["grass"] = floor_sys.save_state()
	return out


func apply_state(d: Dictionary) -> void:
	if _daynight:
		_daynight.hour = float(d.get("hour", 17.0))
		## Seasons. Every save written before 2026-09-01 counted days from 0, and
		## day 0 is the first day of spring — before the flush — where
		## foliage.gdshader strips every deciduous tree bare. Shift those saves
		## forward by the new start so a loaded world keeps the days it has
		## lived without standing in a leafless spring. `season_based` marks a
		## save that already counts from DayNight.START_DAY.
		var sday := float(d.get("day", 0.0))
		if not bool(d.get("season_based", false)):
			sday += DayNight.START_DAY
		_daynight.day = sday
		Wind.publish_season(_daynight.day)
	if _weather and d.has("weather"):
		_weather.from_dict(d["weather"] as Dictionary)
	if _wildlife != null:
		_wildlife.apply_state(d.get("wildlife", {}) as Dictionary)  ## --- wildlife ---
	if _chronicle:  ## [chronicle]
		_chronicle.from_dict(d.get("chronicle", {}) as Dictionary)
	if _incidents:  ## [incidents]
		_incidents.from_dict(d.get("incidents", {}) as Dictionary)
	if _rumours:  ## [rumours]
		_rumours.from_dict(d.get("rumours", {}) as Dictionary)
	if _wayfarers:  ## [wayfarers]
		_wayfarers.from_dict(d.get("wayfarers", {}) as Dictionary)
	if _crofts:  ## [crofts]
		_crofts.from_dict(d.get("crofts", {}) as Dictionary)
	if _carcasses:  ## [carcasses]
		_carcasses.from_dict(d.get("carcasses", {}) as Dictionary)
	if _warbands:  ## [warbands]
		_warbands.from_dict(d.get("warbands", {}) as Dictionary)
	## Sweep the surface clean, then lay the saved one back down.
	for group in ["trees", "tree_stumps", "carry_logs", "dropped_items", "beds", "psx_props"]:
		for n in get_tree().get_nodes_in_group(group):
			(n as Node).queue_free()
	## [terrain] rebuild on load: the sweep above just deleted every
	## streamed tree along with the saved ones. Put the forest back -- minus
	## every slot the ledger says was cut, so no tree regrows over its stump.
	if _terrain != null:
		_terrain.apply_state(d.get("overworld", {}) as Dictionary)
		_terrain.rebuild_all()
	for td in d.get("trees", []):
		## Dispatch on "kind". An old save has no kind key at all, so it falls
		## through to ChopTree exactly as it always did.
		var rec: Dictionary = td as Dictionary
		match str(rec.get("kind", "")):
			"tree_v2":
				var tv := TreeV2.from_dict(rec)
				add_child(tv)
				tv.restore(rec)
			"stump":
				add_child(TreeStump.from_dict(rec))
			_:
				var t := ChopTree.from_dict(rec)
				t.position = rec.get("pos", Vector3.ZERO)
				t.rotation.y = float(rec.get("rot_y", 0.0))
				add_child(t)
	for pd in d.get("props", []):
		var pr := PSXProp.from_dict(pd as Dictionary)
		add_child(pr)
		pr.restore(pd as Dictionary)
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
		var floor_sys = _region.grass()
		if floor_sys != null and d.has("grass") and floor_sys.has_method("apply_state"):
			floor_sys.apply_state(d["grass"] as Dictionary)
		if d.has("cave") and _region.apply_state(d["cave"] as Dictionary):
			## The underground has to redraw itself from the saved seed and
			## take your dig back. Hold the curtain the same way startup does —
			## _process lifts it when the region is genuinely finished.
			_loading = true
			set_blackout(true, "Remembering the world...")
			if _player:
				_player.input_locked = true
	## The growth ledger: the rocks and cave mouths were never swept, so their
	## patches are still there -- hand each its saved growth by key.
	if d.has("growth"):
		var by_key := {}
		for g in get_tree().get_nodes_in_group("growth_patches"):
			if g is GrowthPatch and (g as GrowthPatch).host_key != "":
				by_key[(g as GrowthPatch).host_key] = g
		for gd in d["growth"]:
			if gd is Dictionary and by_key.has(str((gd as Dictionary).get("key", ""))):
				(by_key[str((gd as Dictionary).get("key", ""))] as GrowthPatch).apply_dict(gd as Dictionary)
	## A load just swept every tree and prop in the world, the god editor's
	## included. Put the built world back (GodEditor.restore_all).
	get_tree().call_group("builder", "restore_all")

## ---------------------------------------------------------------- sky ------

func set_cloud_mode(idx: int) -> void:
	## Settings -> Clouds. 0 off, 1 painterly, 2 volumetric.
	if _sky != null and is_instance_valid(_sky):
		_sky.set_cloud_mode(idx)


## [steps] Weather.wetness has been published since the sky pass and read by
## nothing. The footsteps are its first consumer: soaked soil squelches, and
## gravel and sand do not.
func _feed_step_wetness() -> void:
	if _step_audio == null or not is_instance_valid(_step_audio):
		return
	if _weather == null or not is_instance_valid(_weather):
		return
	var w = _weather.get("wetness")
	_step_audio.wetness = clampf(float(w), 0.0, 1.0) if w != null else 0.0


func chronicle() -> Chronicle:
	## [chronicle] The off-screen world, for the console, the tavern board
	## and the tests: World.chronicle().rumours_at(pos). Null until
	## _build_wildlife() has run, or forever if USE_WILDLIFE is off.
	return _chronicle


func roadnet() -> RoadNet:
	## [roadnet] The road net, or null before begin_world has run. The
	## Incident Director and the map both read it; neither may assume it.
	return _roads


func incidents() -> IncidentDirector:
	## [incidents] The physical half of the off-screen world, for the
	## console and the tests. Null until _build_wildlife() has run, or
	## forever if USE_WILDLIFE is off -- every caller must tolerate that.
	return _incidents


func wayfarers() -> Wayfarers:
	## [wayfarers] Who is on the roads, for the console, the map and the
	## tests: World.wayfarers().report(). Null until _build_wildlife()
	## has run, or forever if USE_WILDLIFE is off -- every caller must
	## tolerate that, and every caller does.
	return _wayfarers


func crofts() -> Crofts:
	## [crofts] The smallholdings off the roads, for the console, the map
	## and the tests: World.crofts().report(). Null until _build_wildlife()
	## has run, or forever if USE_WILDLIFE is off -- every caller must
	## tolerate that.
	return _crofts


func carcasses() -> Carcasses:
	## [carcasses] What the woods are doing with what you killed, for the
	## console, the map and the tests: World.carcasses().report(). Null until
	## _build_wildlife() has run, or forever if USE_WILDLIFE is off -- every
	## caller must tolerate that.
	return _carcasses


func warbands() -> Warbands:
	## [warbands] The goblin camps and who is in them, for the console, the
	## map and the tests: World.warbands().report(). Null until
	## _build_wildlife() has run, or forever if USE_WILDLIFE is off -- every
	## caller must tolerate that.
	return _warbands


func rumours() -> RumourFeed:
	## [rumours] The ear on the Chronicle, for the console and the tests:
	## World.rumours().report(). Null until _build_wildlife() has run, or
	## forever if USE_WILDLIFE is off -- every caller must tolerate that.
	return _rumours


func weather() -> Weather:
	## Handy from the console, and how a scripted moment (Katahdin's storm
	## crown) grabs the sky: World.weather().lock_weather(Weather.Level.STORM)
	return _weather


## ============================== Wildlife ===================================
## --- wildlife ---
## Three nodes, in this order, because each finds the last one:
##   Telegraph         the alarm bus every animal rings and listens to
##   CritterAudio      the calls and the ambience bed (half the feature)
##   WildlifeDirector  who spawns, where, and when
##
## See docs/WILDLIFE.md. Set USE_WILDLIFE = false to turn the whole thing off
## in one line if it ever misbehaves — same escape hatch as USE_TREES_V2.


const USE_WILDLIFE := true


func _build_wildlife() -> void:
	if not USE_WILDLIFE:
		return
	_telegraph = Telegraph.new()
	add_child(_telegraph)
	_critter_audio = CritterAudio.new()
	add_child(_critter_audio)
	_wildlife = WildlifeDirector.new()
	_wildlife.player = _player
	_wildlife.world_radius = WORLD_RADIUS
	add_child(_wildlife)
	if _daynight != null:
		_wildlife.set_clock(_daynight.hour, _daynight.day)
	## The hand-placed pass: a chickadee flock by the camp, a squirrel in the
	## near timber, and one deer out at the tree line — so the first three
	## things a player meets are the one that lands on your hand, the one that
	## tells the forest you are here, and the one that runs.
	_wildlife.seed_world()
	## [chronicle] The Chronicle rides behind the wildlife: the off-screen
	## world that talks -- what the wolves did to whose fold, which road the
	## caravan gave up on. It binds to the same clock and sky the animals
	## keep, so a rumour about last night's storm is about the storm you saw.
	_chronicle = Chronicle.new()
	_chronicle.name = "Chronicle"
	Chronicle.bind(_daynight, _weather)
	add_child(_chronicle)
	_chronicle.boot()
	## [incidents] The Chronicle knows a caravan is on the Freeport road at
	## hour nine and that wolves took a ewe at Sebec last night. It will
	## never put either of them in front of you -- it deals in places, not
	## nodes, on purpose. This is the half that makes them physical: the
	## party you can actually meet, and the torn hurdle with the crows on
	## it that you can stumble into three days later and read.
	## [roadnet] the travel graph over the fifty places. Built BEFORE the
	## Incident Director, because bind_world() reaches for roadnet() and a
	## net that does not exist yet binds as null and stays null all session.
	_roads = RoadNet.new()
	_roads.name = "RoadNet"
	add_child(_roads)
	_roads.bind_world(self)
	_roads.boot()

	_incidents = IncidentDirector.new()
	_incidents.name = "IncidentDirector"
	add_child(_incidents)
	_incidents.bind_world(self)
	## [rumours] The Chronicle talks to itself and the Director makes it
	## physical. This is the half that makes it AUDIBLE: walk into a
	## village and you start catching what the village is saying. It
	## finds the player and the Chronicle for itself, so it can be built
	## before either of them and survive both being replaced.
	_rumours = RumourFeed.new()
	_rumours.name = "RumourFeed"
	add_child(_rumours)
	_rumours.boot()
	## [wayfarers] Fifty-eight roads and, until now, nobody on one. A band
	## is a named traveller walking a fixed circuit of three to five places
	## for the rest of the game, at a pace its trade can manage, stopping
	## where the light fails and holding where the weather is worse than
	## that -- and carrying whatever the last village was talking about to
	## the next one. Built LAST, because bind_world reaches for roadnet(),
	## chronicle() and rumours(), and a collaborator that does not exist
	## yet binds as null and stays null for the session.
	_wayfarers = Wayfarers.new()
	_wayfarers.name = "Wayfarers"
	add_child(_wayfarers)
	_wayfarers.bind_world(self)
	## [crofts] Fifty-eight roads with somebody on them, and still nobody
	## LIVING beside one. A croft is a smallholding seated off a road, out
	## of sight of its village, whose whole day is a query rather than a
	## script: hearth lit at rise and banked at dusk, beasts out unless it
	## is raining, washing on the line because the sky was clear at eight
	## and soaked on it because it was not clear at noon -- and a woodpile
	## that an autumn spent barred indoors will not see the far side of.
	## Built LAST, because bind_world reaches for roadnet(), chronicle()
	## and rumours(), and a collaborator that does not exist yet binds as
	## null and stays null for the session.
	_crofts = Crofts.new()
	_crofts.name = "Crofts"
	add_child(_crofts)
	_crofts.bind_world(self)
	## [carcasses] Sixty-five animals that can die and nothing downstream of
	## a death but a twenty-two second ragdoll clock. A carcass is a LEDGER
	## ENTRY with a number of kilograms on it, and five claimants bill
	## against that number over the days after a kill -- the crows, a fox, a
	## coyote pack, a bear and the ground itself -- in an order the hour, the
	## sky and the season decide between them. Drop a deer at noon and the
	## crows have it inside the hour; drop the same deer at midnight and a
	## fox has been and gone before the crows are awake. Butcher it past a
	## fifth and the pack that would have walked into your camp never comes.
	## Built LAST, because bind_world reaches for chronicle(), rumours() and
	## _wildlife, and a collaborator that does not exist yet binds as null
	## and stays null for the session.
	_carcasses = Carcasses.new()
	_carcasses.name = "Carcasses"
	add_child(_carcasses)
	_carcasses.bind_world(self)
	## [warbands] The frontier had numbers and a line on the map and not one
	## goblin standing on it. A WARBAND does not spawn: it CAMPS, and the camp
	## is always there -- 115 sites marched off the map, deep ground, no road
	## within 220 m, clear of every town -- while who is IN it is the goblin
	## share of that region's hold, read out of the Chronicle's own faction
	## field. So a border that moves is a fire in a clearing that was dark last
	## month, and you can walk to it. At dusk the band walks out to the nearest
	## road its season can reach and stands on it at midnight, which is the
	## whole of why the north is dangerous after dark and empty at noon. Kill
	## one to the last goblin and the region carries a negative goblin push --
	## it does NOT become men's ground; whoever presses on it from next door
	## divides it, and in the north that is as often the wolves.
	## Built LAST, because bind_world reaches for roadnet(), chronicle() and
	## rumours(), and a collaborator that does not exist yet binds as null and
	## stays null for the session.
	_warbands = Warbands.new()
	_warbands.name = "Warbands"
	add_child(_warbands)
	_warbands.bind_world(self)


func wildlife_census() -> Dictionary:
	## For the debug menu and the test suite.
	return _wildlife.census() if _wildlife != null else {}


func cities() -> Node3D:    ## [cities] the built cities, or null before begin_world
	return _cities

## [water] ------------------------------------------------------------------
func _build_water_audio() -> void:
	if _terrain == null:
		return
	_water_audio = WaterAudio.new()
	_water_audio.name = "WaterAudio"
	add_child(_water_audio)
	_water_audio.listener = _player
	## [steps] the footstep bus rides along -- it needs no listener, the
	## Player hands it the position of every foot it puts down.
	_step_audio = StepAudio.new()
	_step_audio.name = "StepAudio"
	add_child(_step_audio)
	## [fire] the fire bus. Twenty-five croft hearths and every camp you build
	## share three beds between them, ranked by distance four times a second,
	## and that same ranking is what decides which single fire in the world
	## casts shadows. See scripts/FireAudio.gd.
	_fire_audio = FireAudio.new()
	_fire_audio.name = "FireAudio"
	add_child(_fire_audio)
	_fire_audio.listener = _player


## THE DROWNED. Swim deep water at night, far from any shore, and sooner or
## later something dead reaches up. It is an EVENT, not a spawn-table animal:
## one at a time, gated on the clock, the depth, the distance to shore and
## the World's temperament (never in Peaceful), with a long cooldown after.
## The risk builds by the second while the conditions hold and empties the
## moment they stop, so a quick crossing is safe and a long night swim is
## not -- which is the rule swimmers in the north have always known.
const DROWNED_DEPTH := 4.0          ## metres of water under the swimmer
const DROWNED_SHORE := 14.0         ## metres from the nearest dry ground
const DROWNED_NIGHT := [21.5, 4.5]  ## from .. to (wraps midnight)
const DROWNED_RISK_PER_S := 0.022   ## ~45 s of exposure on average
const DROWNED_COOLDOWN := 150.0


func _drowned_tick(delta: float, uw: float) -> void:
	if _player != null and _player.god:
		return   ## god / spectator: the lake has no claim on a body it cannot see
	_drowned_cd = maxf(0.0, _drowned_cd - delta)
	if _drowned != null and not is_instance_valid(_drowned):
		_drowned = null
	if _drowned != null or _terrain == null or _player == null:
		return
	var swimming: bool = bool(_player.get("swimming")) if "swimming" in _player else false
	if not swimming or _drowned_cd > 0.0 or GameMode.mode == GameMode.Mode.PEACEFUL \
			or _player.grabbed_by != null:
		_drowned_risk = maxf(0.0, _drowned_risk - delta * 0.2)
		return
	var h: float = _daynight.hour if _daynight != null else 12.0
	var night := h >= float(DROWNED_NIGHT[0]) or h < float(DROWNED_NIGHT[1])
	var p: Vector3 = _player.global_position
	if not night or Overworld.water_depth_at(p) < DROWNED_DEPTH:
		_drowned_risk = maxf(0.0, _drowned_risk - delta * 0.2)
		return
	var shore: Dictionary = Overworld.nearest_dry(p, 40.0)
	if float(shore.get("dist", INF)) < DROWNED_SHORE:
		_drowned_risk = maxf(0.0, _drowned_risk - delta * 0.2)
		return
	_drowned_risk += delta * DROWNED_RISK_PER_S
	if _rng.randf() < _drowned_risk * delta:
		_drowned_risk = 0.0
		_drowned_cd = DROWNED_COOLDOWN
		var d := Drowned.new()
		add_child(d)
		d.rise_under(_player)
		_drowned = d


func drowned_active() -> bool:
	return _drowned != null and is_instance_valid(_drowned)

