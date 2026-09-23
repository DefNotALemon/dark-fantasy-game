extends SceneTree

# =============================================================================
# tests/WaterTests.gd -- the water pass (2026-09-01), the parts that need no
# player: the sound pack and its manifest, the Overworld's water queries on
# the real bake, the two water materials, the WildlifeDirector's map zones and
# water placement, the Drowned's own machine, and the thirst arithmetic.
#
#   godot --headless --path . --script res://tests/WaterTests.gd
#
# MapWalkTests boots the whole world and does the rest (drinking, the skin,
# the snapper's hold, the Drowned's grab) against the real Player.
# =============================================================================

const MIN_ASSERTIONS := 40

var _pass := 0
var _fail := 0
var _ow: Node3D = null
var _frame := 0
var _elapsed := 0.0
var _drowned: Node3D = null
var _dummy: Node3D = null


func ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL  %s" % what)


func near(a: float, b: float, tol: float, what: String) -> void:
	ok(absf(a - b) <= tol, "%s (got %.3f, want %.3f +/- %.3f)" % [what, a, b, tol])


func _initialize() -> void:
	print("\n=== WaterTests ===")
	var world := Node3D.new()
	root.add_child(world)
	_ow = load("res://scripts/Overworld.gd").new()
	world.add_child(_ow)


func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 1:
		_t_pack()
		_t_shader()
		_t_queries()
		_t_materials()
		_t_director()
		_t_thirst_math()
		_t_drowned_start()
		return false
	_elapsed += _d
	## ~400 frames AND six seconds: headless runs as fast as it can, so a
	## frame count alone is not 2.2 s of rise + 2.5 s of sink (world v2 found
	## the Drowned still sinking at frame 400 with 2.9 s on its clock)
	if _frame < 400 or _elapsed < 6.0:
		return false
	_t_drowned_end()
	print("\n--- %d passed, %d failed (floor %d) ---" % [_pass, _fail, MIN_ASSERTIONS])
	if _pass + _fail < MIN_ASSERTIONS:
		print("FAIL: only %d assertions ran" % (_pass + _fail))
		quit(1)
		return true
	quit(1 if _fail > 0 else 0)
	return true


# --- the pack ------------------------------------------------------------------
func _t_pack() -> void:
	print("[the sound pack]")
	var wa := WaterAudio.new()
	root.add_child(wa)
	ok(wa.manifest.size() >= 14, "manifest lists the set (%d)" % wa.manifest.size())
	for k in ["lake_lap", "sea_surf", "underwater_bed", "swim_stroke_1", "swim_stroke_2", "swim_stroke_3",
			"splash_in", "splash_out", "gulp", "fill_skin", "bubbles", "snapper_hiss", "drowned_rise", "drowned_grip"]:
		ok(wa.has_sound(k), "manifest has %s" % k)
		ok(FileAccess.file_exists(WaterAudio.DIR + k + ".wav"), "%s.wav is on disk" % k)
	ok(bool((wa.manifest["lake_lap"] as Dictionary).get("loop", false)), "the lap loops")
	ok(not bool((wa.manifest["splash_in"] as Dictionary).get("loop", true)), "a splash does not")
	## submersion drives a low-pass on Master, added only when needed
	var bus := AudioServer.get_bus_index("Master")
	var before := AudioServer.get_bus_effect_count(bus)
	WaterAudio.set_submerged(wa, 0.0)
	ok(AudioServer.get_bus_effect_count(bus) == before, "dry: the bus is left alone")
	WaterAudio.set_submerged(wa, 1.0)
	ok(AudioServer.get_bus_effect_count(bus) == before + 1, "under: a WaterMuffle low-pass appears on Master")
	near(wa.submerged(), 1.0, 0.001, "...and the node remembers the depth")
	WaterAudio.set_submerged(wa, 0.0)
	wa.queue_free()


func _t_shader() -> void:
	print("[the water shader]")
	var sh := load("res://shaders/terrain_water.gdshader") as Shader
	ok(sh != null, "terrain_water.gdshader loads")
	if sh == null:
		return
	var c := sh.code
	ok(c.contains("hint_depth_texture"), "it reads the depth buffer")
	ok(c.contains("hint_screen_texture") and c.contains("refract_on"), "refraction is there and switchable")
	ok(c.contains("foam_col"), "it draws foam")
	ok(c.contains("sky_col"), "it reflects a sky colour")
	ok(c.contains("CURRENT_RENDERER"), "depth is decoded per renderer (GL vs Vulkan)")


# --- queries on the real bake ------------------------------------------------
func _t_queries() -> void:
	print("[water queries]")
	ok(_ow._loaded, "the bake loaded")
	if not _ow._loaded:
		return
	var moose := Vector3(960.0, 0.0, -3480.0)
	for l in _ow.lakes():
		if String(l["name"]) == "Moosehead Lake":
			var mq: Array = l["pos"]
			moose = Vector3(float(mq[0]), 0.0, float(mq[1]))
	ok(Overworld.is_water_at(moose), "Moosehead's marker is water")
	ok(not Overworld.water_is_sea(moose), "...fresh")
	ok(Overworld.water_depth_at(moose) > 1.0, "...with some depth under it (%.1f m)" % Overworld.water_depth_at(moose))
	var moose_meta := -1e9
	for l in _ow.lakes():
		if String(l["name"]) == "Moosehead Lake":
			moose_meta = float(l["y"])
	## (the meta's y is the BED at the marker; the surface stands a few metres
	## over it -- world v2 puts Moosehead at ~29 m, the 08-30 bake had 54)
	var moose_w: float = Overworld.water_y(moose)
	ok(moose_w > moose_meta + 1.0 and moose_w < moose_meta + 40.0,
		"Moosehead's surface stands over its marker bed (%.1f over %.1f)" % [moose_w, moose_meta])
	var nd := Overworld.nearest_dry(moose, 60.0)
	ok(nd.has("dist"), "nearest_dry answers from the middle of a lake")
	## the tarn in Katahdin's cirque (world v2 draws it; the 08-30 bake's
	## pit-turned-tarn sat at (2312, -4911))
	var tarn := Vector3(2182.3, 0.0, -4480.0)
	ok(Overworld.is_water_at(tarn), "the Katahdin cirque holds a tarn")
	var ty := Overworld.water_y(tarn)
	ok(ty > 200.0 and ty < 400.0, "...high on the flank, not 40 m down a shaft (%.1f m)" % ty)
	## Portland's pad: buried tidal water is NOT water
	var portland := Vector3(-85.7, 0.0, 1056.0)
	ok(not Overworld.is_water_at(portland), "Portland's pad is dry even though the bake has sea cells under it")
	## the beach south of it finds the sea (walk +z from the pad to the waterline)
	var wz0 := 1060.0
	while not Overworld.is_water_at(Vector3(-85.7, 0.0, wz0)) and wz0 < 2640.0:
		wz0 += 2.0
	var beach := Vector3(-85.7, 0.0, wz0 - 12.0)
	var nw := Overworld.nearest_water(beach, 60.0)
	ok(float(nw.get("dist", INF)) <= 20.0, "from the beach the sea is within 20 m (%.1f)" % float(nw.get("dist", INF)))
	ok(bool(nw.get("sea", false)), "...and it is the sea")
	## deep wood: nothing near
	var wood := Vector3(74.1, 0.0, -1359.9)
	var nw2 := Overworld.nearest_water(wood, 30.0)
	ok(float(nw2.get("dist", INF)) > 5.0, "the deep wood is not standing in water")
	## deeper_dir points off the beach out to sea
	var edge := Vector3(-85.7, 0.0, wz0 + 4.0)
	ok(Overworld.is_water_at(edge), "the beach probe is in the water")
	var dd := Overworld.deeper_dir(edge, 6.0)
	ok(dd != Vector3.ZERO, "off the beach there is a deeper direction")
	ok(Overworld.water_depth_at(edge + dd * 6.0) > Overworld.water_depth_at(edge), "...and it really is deeper")
	## the valley never has water
	ok(not Overworld.is_water_at(Vector3(0.0, 0.0, 0.0)), "the spawn valley is dry")


func _t_materials() -> void:
	print("[the two waters]")
	if not _ow._loaded:
		return
	var lake: Material = _ow._water_material(false)
	var sea: Material = _ow._water_material(true)
	ok(lake != sea, "lakes and the sea wear different materials")
	if lake is ShaderMaterial and sea is ShaderMaterial:
		ok(float((sea as ShaderMaterial).get_shader_parameter("murk_depth")) > float((lake as ShaderMaterial).get_shader_parameter("murk_depth")),
			"the Gulf stays clear deeper than a tannin lake")
		_ow.set_refraction(false)
		ok(not bool((lake as ShaderMaterial).get_shader_parameter("refract_on")), "set_refraction(false) reaches the lakes")
		ok(not bool((sea as ShaderMaterial).get_shader_parameter("refract_on")), "...and the sea")
		_ow.set_refraction(true)
		_ow.set_water_sky(Color(1.0, 0.5, 0.2))
		ok((lake as ShaderMaterial).get_shader_parameter("sky_col") == Color(1.0, 0.5, 0.2), "the sky colour lands on the water")
	else:
		ok(false, "the water shader did not load (fallback materials)")


# --- the director on the map ---------------------------------------------------
func _t_director() -> void:
	print("[wildlife on the map]")
	if not _ow._loaded:
		return
	var wl := WildlifeDirector.new()
	root.add_child(wl)
	var moose := Vector3(960.0, 0.0, -3480.0)
	for l in _ow.lakes():
		if String(l["name"]) == "Moosehead Lake":
			var mq: Array = l["pos"]
			moose = Vector3(float(mq[0]), 0.0, float(mq[1]))
	ok(wl._zone_at(moose) == "lake", "Moosehead is the lake zone (%s)" % wl._zone_at(moose))
	var wz1 := 1060.0
	while not Overworld.is_water_at(Vector3(-85.7, 0.0, wz1)) and wz1 < 2640.0:
		wz1 += 2.0
	var beach := Vector3(-85.7, 0.0, wz1 - 12.0)
	ok(wl._zone_at(beach) == "beacon_coast", "Portland's beach is the coast (%s)" % wl._zone_at(beach))
	var sea := Vector3(-85.7, 0.0, wz1 + 60.0)
	ok(wl._zone_at(sea) == "gulf", "out in the water it is the Gulf (%s)" % wl._zone_at(sea))
	var wood := Vector3(74.1, 0.0, -1359.9)
	var wz := wl._zone_at(wood)
	ok(wz != "lake" and wz != "gulf" and wz != "beacon_coast", "the deep wood is not a water zone (%s)" % wz)
	var kat := Vector3(2118.1, 0.0, -4407.9)
	ok(wl._zone_at(kat) == "katahdin", "Katahdin's summit is the katahdin zone (%s)" % wl._zone_at(kat))
	## water placement
	var sx := moose.x
	while Overworld.is_water_at(Vector3(sx, 0.0, moose.z)) and sx < moose.x + 2000.0:
		sx += 4.0
	var shore := Vector3(sx, 0.0, moose.z)
	var sp: Vector3 = wl._water_spot("snapper", shore)
	ok(sp != Vector3.INF, "a snapper finds shallows off the Moosehead shore")
	if sp != Vector3.INF:
		var dep := Overworld.water_depth_at(sp)
		ok(dep >= 0.4 and dep <= 1.8, "...0.4-1.8 m deep (%.2f)" % dep)
		near(sp.y, Overworld.ground_y(sp) + 0.12, 0.01, "...lying on the bed")
	var lp: Vector3 = wl._water_spot("loon", shore)
	ok(lp != Vector3.INF, "a loon finds open water")
	if lp != Vector3.INF:
		near(lp.y, Overworld.water_y(lp) + 0.05, 0.01, "...on the surface")
	## the CritterDex flags the snapper the way the ambush needs
	ok(bool(CritterDex.flag("snapper", "ambush", false)) and bool(CritterDex.flag("snapper", "latch", false))
		and bool(CritterDex.flag("snapper", "water", false)), "the snapper is a water ambusher that latches")
	wl.queue_free()


func _t_thirst_math() -> void:
	print("[thirst arithmetic]")
	var r: float = Player.thirst_rate_per_sec()
	near(r * Player.THIRST_DAYS * DayNight.DAY_SECONDS, Player.THIRST_MAX, 0.001, "full to empty in THIRST_DAYS game days")
	ok(Player.THIRST_DRAUGHT * 3.0 >= Player.THIRST_MAX, "three long drinks fill the meter")
	ok(Player.SKIN_DRAUGHT * Player.SKIN_FILLS >= Player.THIRST_MAX, "a full skin is a full meter")
	ok(Player.BREATH_SECONDS >= 30.0, "at least half a minute of air")


# --- the Drowned, alone --------------------------------------------------------
func _t_drowned_start() -> void:
	print("[the Drowned]")
	if not _ow._loaded:
		return
	_dummy = Node3D.new()
	root.add_child(_dummy)
	var moose := Vector3(960.0, 0.0, -3480.0)
	for l in _ow.lakes():
		if String(l["name"]) == "Moosehead Lake":
			var mq: Array = l["pos"]
			moose = Vector3(float(mq[0]), 0.0, float(mq[1]))
	_dummy.global_position = Vector3(moose.x, Overworld.water_y(moose), moose.z)
	_drowned = Drowned.new()
	root.add_child(_drowned)
	_drowned.rise_under(_dummy)
	ok(String(_drowned.get("phase")) == "rise", "it starts rising")
	ok(_drowned.global_position.y < _dummy.global_position.y - 3.0, "...from well under the swimmer")
	ok(_drowned.get_child_count() > 0, "...with a body")
	near(float(_drowned.hold_seconds()), Drowned.HOLD_MAX + 0.5, 0.001, "it says how long it may hold")


func _t_drowned_end() -> void:
	## ~400 frames later: the dummy cannot be grabbed, so it should have given
	## up, sunk, and freed itself
	ok(_drowned == null or not is_instance_valid(_drowned), "with nothing to grab it sinks and is gone")
