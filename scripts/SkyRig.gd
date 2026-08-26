class_name SkyRig
extends Node

## ===========================================================================
## The sky itself — scripts/SkyRig.gd
##
## Swaps the world's ProceduralSkyMaterial for shaders/sky.gdshader and feeds it
## the three things it can't know on its own: where the sun actually is, which
## way the wind is pushing the clouds, and how thick the weather is.
##
## Named SkyRig, not Sky — `Sky` is a Godot built-in resource class and a
## class_name collision is a hard parse error.
##
## Division of labour, on purpose:
##   DayNight.gd  still owns the clock, the sun/moon wheel, ambient and fog.
##   SkyRig       owns everything you SEE up there.
##   Weather.gd   owns rain, thunder, and the aurora roll; it talks to SkyRig.
##
## Wired up by World.gd:
##     _sky = SkyRig.new()
##     _sky.env = env
##     _sky.daynight = _daynight
##     add_child(_sky)
## ===========================================================================

const SHADER_PATH := "res://shaders/sky.gdshader"

## Cloud modes — Painterly is the default because it is roughly free.
## Volumetric marches a slab of noise: prettier, and it costs real GPU.
enum Clouds { OFF = 0, PAINTERLY = 1, VOLUMETRIC = 2 }

## Radiance is what lights the world off the sky. REALTIME re-renders the
## cubemap every frame (expensive with a marching sky); INCREMENTAL spreads it
## over several frames, which is invisible for something as slow as a sunset.
const RADIANCE_SIZE := Sky.RADIANCE_SIZE_128

var env: Environment           ## set by World before add_child
var daynight: DayNight         ## set by World before add_child
var wind: Wind                 ## set by World before add_child (optional)

var sky_mat: ShaderMaterial
var _sky: Sky

## --- what the world can drive from outside ---------------------------------
var cloud_mode: int = Clouds.PAINTERLY : set = set_cloud_mode
var cloud_coverage := 0.42 : set = _set_coverage      ## 0 clear ... 1 solid deck
var cloud_darkness := 0.0 : set = _set_darkness       ## storm bellies
var storm_gloom := 0.0 : set = _set_gloom             ## desaturate + darken the whole sky
var aurora_strength := 0.0 : set = _set_aurora        ## Weather.gd rolls this at dusk
var lightning := 0.0 : set = _set_lightning           ## 0..1 flash, pulsed by Weather.gd

var _wind_off := Vector2.ZERO
var _sun: DirectionalLight3D


func _ready() -> void:
	## Run AFTER DayNight each frame so the sun transform we read is this
	## frame's, not last frame's. (Lower priority runs first in Godot.)
	process_priority = 10
	_install()


func _install() -> void:
	if env == null:
		push_warning("SkyRig: no Environment — nothing to install into.")
		return
	var sh: Shader = load(SHADER_PATH)
	if sh == null:
		push_warning("SkyRig: %s missing — keeping the procedural sky." % SHADER_PATH)
		return

	sky_mat = ShaderMaterial.new()
	sky_mat.shader = sh

	_sky = env.sky if env.sky != null else Sky.new()
	_sky.sky_material = sky_mat
	_sky.radiance_size = RADIANCE_SIZE
	_sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.sky = _sky
	env.background_mode = Environment.BG_SKY

	## DayNight writes sky_top_color / sky_horizon_color into a
	## ProceduralSkyMaterial. There isn't one any more, and its `if sky_mat:`
	## guard means handing it null is all it takes to stand it down. The clock
	## keeps running; it just stops painting.
	if daynight != null:
		daynight.sky_mat = null

	set_cloud_mode(cloud_mode)
	_push_all()


func _process(delta: float) -> void:
	if sky_mat == null:
		return

	## --- where is the sun, really ---
	## DirectionalLight3D shines down its local -Z, so +basis.z is the vector
	## pointing AT the sun — which is exactly what the sky shader wants.
	if _sun == null or not is_instance_valid(_sun):
		_sun = _find_sun()
	if _sun != null:
		sky_mat.set_shader_parameter("sun_dir_override",
			_sun.global_transform.basis.z.normalized())

	## --- clouds ride the world's wind ---
	## Wind.gd is the one breeze in the world (spec §18); the sky is a long way
	## up, so it gets a slower, steadier version of what the leaves feel.
	##
	## Read it off the node, NOT off the global shader parameter:
	## RenderingServer.global_shader_parameter_get() is editor-only and screams
	## once a frame in an exported build. Wind.gd's own comment says so.
	var dir := Vector2(1.0, 0.0)
	var strength := 0.25
	if wind != null and is_instance_valid(wind):
		var v: Vector3 = wind.last_dir
		if v.length() > 0.001:
			dir = Vector2(v.x, v.z).normalized()
		strength = wind.last_strength
	## Accumulate an offset instead of setting a velocity, so a gust can't make
	## the whole cloud deck jump sideways when the wind changes its mind.
	_wind_off += dir * (0.0022 + strength * 0.010) * delta
	sky_mat.set_shader_parameter("cloud_wind", _wind_off)


func _find_sun() -> DirectionalLight3D:
	if daynight != null and is_instance_valid(daynight) and daynight.sun != null:
		return daynight.sun
	for n in get_tree().get_nodes_in_group("sun"):
		if n is DirectionalLight3D:
			return n
	## Last resort: the brightest directional light in the scene.
	var best: DirectionalLight3D = null
	for n in _all_lights(get_tree().root):
		if best == null or n.light_energy > best.light_energy:
			best = n
	return best


func _all_lights(n: Node) -> Array[DirectionalLight3D]:
	var out: Array[DirectionalLight3D] = []
	if n is DirectionalLight3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_lights(c))
	return out


## ------------------------------------------------------------- setters -----

func set_cloud_mode(m: int) -> void:
	cloud_mode = clampi(m, 0, 2)
	if sky_mat:
		sky_mat.set_shader_parameter("cloud_mode", cloud_mode)


func _set_coverage(v: float) -> void:
	cloud_coverage = clampf(v, 0.0, 1.0)
	if sky_mat:
		sky_mat.set_shader_parameter("cloud_coverage", cloud_coverage)


func _set_darkness(v: float) -> void:
	cloud_darkness = clampf(v, 0.0, 1.0)
	if sky_mat:
		sky_mat.set_shader_parameter("cloud_darkness", cloud_darkness)


func _set_gloom(v: float) -> void:
	storm_gloom = clampf(v, 0.0, 1.0)
	if sky_mat:
		sky_mat.set_shader_parameter("storm_gloom", storm_gloom)


func _set_aurora(v: float) -> void:
	aurora_strength = clampf(v, 0.0, 1.0)
	if sky_mat:
		sky_mat.set_shader_parameter("aurora_strength", aurora_strength)


func _set_lightning(v: float) -> void:
	lightning = clampf(v, 0.0, 1.0)
	if sky_mat:
		sky_mat.set_shader_parameter("lightning", lightning)


func _push_all() -> void:
	_set_coverage(cloud_coverage)
	_set_darkness(cloud_darkness)
	_set_gloom(storm_gloom)
	_set_aurora(aurora_strength)
	_set_lightning(lightning)


## Settings-menu entry point: "Clouds — Off / Painterly / Volumetric".
func apply_cloud_setting(idx: int) -> void:
	set_cloud_mode(idx)
