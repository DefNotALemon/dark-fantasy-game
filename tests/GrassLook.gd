extends SceneTree
## GrassLook — LOOK at every style in design/grass_styles/ and save a PNG each.
##
##   godot --path . --rendering-driver opengl3 --resolution 960x600 \
##       --script res://tests/GrassLook.gd -- <out_dir>
##
## Not a test. GrassLabTests says the knobs do what they claim; it cannot say
## whether "Bloodmire bog" looks like anything. This stands one GrassSystem on
## the test CaveField, applies each preset whole (defaults first, so nothing
## leaks between styles), and shoots it from eye level across a clearing —
## the same vantage the browser bench uses, so the two can be compared.
##
## The palette swatch in the F3 panel is one flat colour; these are the
## contact sheet behind it.

## Two vantages, because one is never enough to judge a style: EYE is where
## the player's head is (does this grass let you SEE?), FIELD is the postcard
## (what does the meadow read as from the trail?). A style like "Jungle
## overgrowth" is a green wall from EYE and a proper swamp from FIELD; both
## facts matter.
const VANTAGES := [
	{"tag": "eye", "eye": Vector3(0.0, 1.55, 6.0), "at": Vector3(0.0, 0.55, -7.0)},
	{"tag": "field", "eye": Vector3(0.0, 3.4, 11.0), "at": Vector3(0.0, 0.30, -9.0)},
]

var _field: CaveField
var _gs: GrassSystem
var _cam: Camera3D
var _styles: Array = []
var _i := -1
var _wait := 0
var _v := 0            ## which vantage of the current style is next
var _out := "user://grass_look/"
var _only := ""


func _init() -> void:
	process_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_out = String(args[0])
	## a second arg is a FILTER: only styles whose file name contains it (and
	## "default" for the shipped look) -- one style is ten seconds, all of
	## them is three minutes
	if args.size() >= 2:
		_only = String(args[1])
	if not _out.ends_with("/"):
		_out += "/"
	DirAccess.make_dir_recursive_absolute(_out)

	## The foliage shader reads SIX global shader parameters that the Wind
	## autoload declares in _ready(). A --script SceneTree runs no autoloads,
	## so without this every blade samples an UNDECLARED global: season_phase
	## comes back garbage and the whole meadow renders bright red -- which is
	## the harness lying, not the game. (It also looks exactly like POLISH #5,
	## so a shot taken without these proves nothing about that bug.)
	_declare_wind_globals()

	var host := Node3D.new()
	host.name = "World"
	root.add_child(host)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 42.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	host.add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.9
	env.environment = e
	host.add_child(env)

	_cam = Camera3D.new()
	_cam.fov = 62.0
	host.add_child(_cam)
	_aim(0)

	## the GrassLabTests fixture, so a shot and an assertion stand on the
	## same ground
	_field = CaveField.new()
	_field.origin = Vector3(-CaveField.CELLS_X * CaveField.VOX * 0.5, -CaveField.DEPTH,
		-CaveField.CELLS_Z * CaveField.VOX * 0.5)
	_field.mouths = [Vector3(20, 0, -14), Vector3(-30, 0, 26)]
	_field.dirs = [Vector3(0, 0, -1), Vector3(1, 0, 0)]
	_field.generate(true)

	_gs = GrassSystem.new()
	_gs.draw_dist = 34.0     ## 24 reseeds at 90 m is a coffee break
	root.add_child(_gs)
	_gs.setup(_field, 4457)
	## the bench's trick: mow the tall patches around the origin so the camera
	## looks ACROSS the meadow instead of into a hiding tuft 30 cm from the
	## lens. _cut_cells is world-space and survives reseed(), so one cut holds
	## for all 25 styles.
	_gs.cut_at(Vector3(0.0, 0.0, 2.0), 6.0)

	_styles = [{"name": "Myrkfell now", "file": "default",
		"params": GrassSystem.STYLE_DEFAULTS.duplicate(true)}]
	for p in GrassSystem.preset_files():
		var d: Dictionary = p
		_styles.append({"name": String(d["name"]), "file": String(d["file"]),
			"params": GrassSystem.load_style_file(String(d["path"]))})
	if _only != "":
		var keep: Array = []
		for st in _styles:
			if String((st as Dictionary)["file"]).contains(_only) or String((st as Dictionary)["file"]) == "default":
				keep.append(st)
		_styles = keep
	print("GrassLook: %d styles -> %s" % [_styles.size(), _out])
	_next()
	process_frame.connect(_shoot_tick)


func _aim(v: int) -> void:
	var d: Dictionary = VANTAGES[v]
	_cam.global_position = d["eye"] as Vector3
	_cam.look_at(d["at"] as Vector3, Vector3.UP)


func _declare_wind_globals() -> void:
	var rs := RenderingServer
	rs.global_shader_parameter_add("wind_dir", rs.GLOBAL_VAR_TYPE_VEC3, Vector3(1, 0, 0))
	rs.global_shader_parameter_add("wind_strength", rs.GLOBAL_VAR_TYPE_FLOAT, 0.2)
	rs.global_shader_parameter_add("wind_time", rs.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	## 0.35 is Wind.gd's own default -- high summer, the season the styles
	## were authored against
	rs.global_shader_parameter_add("season_phase", rs.GLOBAL_VAR_TYPE_FLOAT, 0.35)
	rs.global_shader_parameter_add("player_pos", rs.GLOBAL_VAR_TYPE_VEC3, Vector3.ZERO)
	rs.global_shader_parameter_add("player_push", rs.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	rs.global_shader_parameter_add("weather_wetness", rs.GLOBAL_VAR_TYPE_FLOAT, 0.0)


func _next() -> void:
	_i += 1
	if _i >= _styles.size():
		print("GrassLook: done")
		quit()
		return
	var s: Dictionary = _styles[_i]
	## defaults first: a preset names only the keys it changes, so without this
	## every style would inherit the last one's leftovers
	var whole: Dictionary = GrassSystem.STYLE_DEFAULTS.duplicate(true)
	for k in (s["params"] as Dictionary).keys():
		whole[k] = (s["params"] as Dictionary)[k]
	_gs.apply_style(whole, true)
	_gs.reseed()
	_v = 0
	_aim(0)
	_wait = 4          ## let the reseed land and the shader settle


## The F3 palette's swatch pictures. The field shot is a third sky, which in a
## 196 px swatch is a third of nothing -- crop to the band that actually has
## grass in it before shrinking.
const THUMB_DIR := "res://design/grass_styles/thumbs/"
const THUMB_CROP_TOP := 0.30    ## fraction of the frame that is sky
const THUMB_SIZE := Vector2i(200, 125)


func _write_thumb(src: Image, file: String) -> void:
	DirAccess.make_dir_recursive_absolute(THUMB_DIR)
	var h := src.get_height()
	var top := int(float(h) * THUMB_CROP_TOP)
	var t := src.get_region(Rect2i(0, top, src.get_width(), h - top))
	t.resize(THUMB_SIZE.x, THUMB_SIZE.y, Image.INTERPOLATE_LANCZOS)
	t.save_png(THUMB_DIR + file + ".png")


func _shoot_tick() -> void:
	## A frame-driven state machine, NOT `await process_frame` inside the
	## handler: an async signal callback that reconnects itself re-enters
	## before its own awaits resolve, and every shot from that point on came
	## out byte-identical to the one before it. Count frames instead.
	if _wait > 0:
		_wait -= 1
		return
	var s: Dictionary = _styles[_i]
	var tag := String((VANTAGES[_v] as Dictionary)["tag"])
	DirAccess.make_dir_recursive_absolute(_out + tag)
	var img := root.get_texture().get_image()
	img.save_png("%s%s/%02d_%s.png" % [_out, tag, _i, String(s["file"])])
	if tag == "field":
		_write_thumb(img, String(s["file"]))
	_v += 1
	if _v < VANTAGES.size():
		_aim(_v)
		_wait = 2      ## the camera moved -- one rendered frame before the grab
		return
	print("  %-24s -> %02d_%s.png" % [String(s["name"]), _i, String(s["file"])])
	_next()
