class_name Wind
extends Node

## ===========================================================================
## The world's wind, in one place.  docs/TREES_v2_SPEC.md §7 / §18
##
## Every foliage shader — leaf cards, bark, and later grass and cloth — reads
## the same four global shader parameters this node publishes. One source, so
## the whole world leans the same way at the same moment instead of each system
## inventing its own breeze.
##
## Also publishes the player, so branches part when you shove through them.
##
## Wired up by World.gd:   add_child(Wind.new())
## ===========================================================================

## Ghost-of-Tsushima rule: the wind in this world BLOWS, always. The base
## never drops low enough for the canopy to sit still, and gusts roll through
## often. Calm is a mood the game does not have.
const BASE_MIN := 0.32          ## never fully still — dead air reads as a bug
const BASE_MAX := 0.60
const GUST_MAX := 0.50          ## added on top of base during a gust
const STORM_MAX := 1.0

const DIR_DRIFT := 0.06         ## radians/sec the prevailing direction wanders
const GUST_PERIOD := Vector2(2.6, 6.5)    ## seconds between gust peaks

## How hard the player has to be moving before foliage notices. Walking barely
## parts a branch; sprinting or swinging shoves it out of the way.
const PUSH_SPEED_FULL := 6.0
const SWING_PUSH := 1.0
const SWING_DECAY := 3.2

var player: Node3D                      ## set by World before add_child
var storm := 0.0 : set = _set_storm     ## 0..1, weather drives this later

## The last values published, readable from GDScript. Shaders get these as
## global parameters; SkyRig and Weather read them from here instead, because
## RenderingServer.global_shader_parameter_get() is editor-only and spams a
## warning every frame in an exported build.
var last_dir := Vector3(1, 0, 0)
var last_strength := 0.2

var _angle := 0.7
var _t := 0.0
var _gust_t := 0.0
var _gust_next := 6.0
var _gust := 0.0
var _swing := 0.0
var _last_player_pos := Vector3.ZERO


func _ready() -> void:
	## Global shader parameters have to exist before any shader that reads them
	## is compiled, so declare them all here, at startup, unconditionally.
	_declare("wind_dir", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(1, 0, 0))
	_declare("wind_strength", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.2)
	_declare("wind_time", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	_declare("season_phase", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.35)
	_declare("player_pos", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ZERO)
	_declare("player_push", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)


func _declare(n: String, type: int, value) -> void:
	## Always add: re-adding an existing global just overwrites it. Do NOT probe
	## with global_shader_parameter_get() first — that call is editor-only and
	## spams "should never be used outside the editor" every frame in a build.
	RenderingServer.global_shader_parameter_add(n, type, value)


func _set_storm(v: float) -> void:
	storm = clampf(v, 0.0, 1.0)


func swing() -> void:
	## Called by Player when an axe or sword goes through the air near foliage.
	_swing = SWING_PUSH


func _process(delta: float) -> void:
	_t += delta

	## --- direction: a slow wander, never a snap ---
	_angle += (sin(_t * 0.11) + sin(_t * 0.037 + 1.3)) * DIR_DRIFT * delta
	var dir := Vector3(cos(_angle), 0.0, sin(_angle))

	## --- strength: a breathing base, plus gusts that arrive and pass ---
	_gust_t += delta
	if _gust_t >= _gust_next:
		_gust_t = 0.0
		_gust_next = randf_range(GUST_PERIOD.x, GUST_PERIOD.y) * (1.0 - storm * 0.6)
		_gust = randf_range(0.55, 1.0)
	var gust_env := 0.0
	if _gust_next > 0.0:
		var u := clampf(_gust_t / maxf(_gust_next * 0.55, 0.01), 0.0, 1.0)
		gust_env = sin(u * PI) * _gust        ## rises, peaks, passes

	## The base BREATHES on two detuned waves so the lulls between gusts still
	## roll instead of flatlining — the canopy must never sit still.
	var base := lerpf(BASE_MIN, BASE_MAX,
		0.5 + 0.3 * sin(_t * 0.23) + 0.2 * sin(_t * 0.071 + 2.1))
	var strength := base + gust_env * GUST_MAX
	strength = lerpf(strength, STORM_MAX, storm * 0.8)
	strength = minf(strength, 1.05)

	## --- the player, for branch-parting ---
	## World.gd builds the wind before the player is in the tree, so find them
	## lazily rather than assuming they were there at _ready.
	var push := 0.0
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	if player != null and is_instance_valid(player):
		var p: Vector3 = player.global_position
		var moved := (p - _last_player_pos).length() / maxf(delta, 0.0001)
		_last_player_pos = p
		push = clampf(moved / PUSH_SPEED_FULL, 0.0, 1.0)
		RenderingServer.global_shader_parameter_set("player_pos", p)
	_swing = maxf(0.0, _swing - delta * SWING_DECAY)
	push = maxf(push, _swing)

	last_dir = dir
	last_strength = strength
	RenderingServer.global_shader_parameter_set("wind_dir", dir)
	RenderingServer.global_shader_parameter_set("wind_strength", strength)
	RenderingServer.global_shader_parameter_set("wind_time", _t)
	RenderingServer.global_shader_parameter_set("player_push", push)


## --------------------------------------------------------------- seasons ---

## One season = 24 game days, so a year is 96 (spec §7). DayNight owns the day
## counter; this converts it to the 0..1 phase every foliage shader reads.
const DAYS_PER_SEASON := 24.0
const DAYS_PER_YEAR := DAYS_PER_SEASON * 4.0


static func phase_for_day(day: float) -> float:
	return fposmod(day, DAYS_PER_YEAR) / DAYS_PER_YEAR


## The last published phase, readable at RUNTIME.
##
## `RenderingServer.global_shader_parameter_GET()` is EDITOR-ONLY: in a running
## game it returns null and logs "This function should never be used outside
## the editor", so the global is write-only once you press play. Anything on
## the game side that needs to know the season -- TreeImpostor, which shoots
## the distant forest's photograph and must not shoot it in a bare spring --
## reads this instead. -1.0 means nothing has published yet, which is NOT the
## same as phase 0.0 (the first day of spring, where every deciduous tree is
## held bare).
static var phase := -1.0


static func publish_season(day: float) -> void:
	phase = phase_for_day(day)
	RenderingServer.global_shader_parameter_set("season_phase", phase)


static func season_name(day: float) -> String:
	var i := int(phase_for_day(day) * 4.0) % 4
	return ["Spring", "Summer", "Autumn", "Winter"][i]
