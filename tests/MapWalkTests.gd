extends SceneTree

# =============================================================================
# tests/MapWalkTests.gd -- boot the REAL world and walk the map.
#
#   godot --headless --path . --script res://tests/MapWalkTests.gd
#
# The overworld's own suite (TerrainTests) checks the heightfield in
# isolation. This one boots scenes/World.tscn -- CaveRegion, Player, wildlife,
# the lot -- and asserts the things that were broken on 2026-08-31 when the
# map was "integrated" but could not actually be left:
#
#   * standing 300 m south of spawn (12 m below the valley floor) does NOT
#     teleport you home after a second ("The earth spat you out");
#   * being below y = 0 out on the map is not "The Hollow Depths": no cave
#     fog, no cave gloom;
#   * the cave mouths are open -- the first thing under the entrance ramp is
#     cave rock, not the heightfield's invisible collider;
#   * the streamer builds the near ring at boot without you walking 24 m;
#   * walk into deep water and you swim, floating at the surface;
#   * the nearest town announces itself;
#   * (2026-09-01) the water pass: WaterAudio is up, thirst and breath do
#     their sums, the sea is brine and the lake is not, the waterskin fills
#     and empties, a snapper takes a swimmer and six kicks free you, and the
#     Drowned comes up under a night swimmer in deep water and lets go after
#     eight.
#
# Every step waits real frames, because every bug above was a _process bug.
# =============================================================================

const MIN_ASSERTIONS := 55

var _world: Node = null
var _pass := 0
var _fail := 0
var _t := 0.0
var _step := 0
var _wait := 0.0
var _boot_t := 0.0
var _player: Node3D = null
var _ow: Node = null
var _stage_t := 0.0
var _shore := Vector3.ZERO
var _snapper: Node = null
var _hold_seen := false
var _hold_t0 := 0.0


func _initialize() -> void:
	print("\n=== MapWalkTests ===")
	_world = (load("res://scenes/World.tscn") as PackedScene).instantiate()
	root.add_child(_world)


func ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL  %s" % what)


func near(a: float, b: float, tol: float, what: String) -> void:
	ok(absf(a - b) <= tol, "%s (got %.3f, want %.3f +/- %.3f)" % [what, a, b, tol])


func _finish() -> void:
	print("\n--- %d passed, %d failed (floor %d) ---" % [_pass, _fail, MIN_ASSERTIONS])
	if _pass + _fail < MIN_ASSERTIONS:
		print("FAIL: only %d assertions ran; the suite lost a section." % (_pass + _fail))
		quit(1)
		return
	quit(1 if _fail > 0 else 0)


func _put(p: Vector3) -> void:
	_player.global_position = p
	_player.set("velocity", Vector3.ZERO)


func _ground(x: float, z: float) -> float:
	return float(_ow.sample_height(x, z))


func _process(delta: float) -> bool:
	_t += delta
	_boot_t += delta
	if _player == null:
		if not _world.is_world_ready():
			if _boot_t > 240.0:
				print("FAIL: world never became ready")
				quit(1)
				return true
			return false
		_player = root.get_tree().get_first_node_in_group("player") as Node3D
		_ow = root.get_tree().get_first_node_in_group("terrain")
		print("world ready after %.1f s" % _boot_t)
		_stage_t = 0.0
		_step = 0
	_stage_t += delta
	match _step:
		0:
			# --- the streamer woke up at boot, with the camera still at spawn
			ok(_ow != null, "the overworld is up")
			if _ow == null:
				_finish()
				return true
			ok(int(_ow._near.size()) > 0, "the near ring built at boot without moving (%d tiles)" % _ow._near.size())
			ok(_ow._focus.is_finite(), "the streamer has a focus")
			# --- 300 m south: off the valley floor's height (12 m under it on
			# the 08-30 bake, ~11 m over it on world v2), on a Portland meadow
			var g := _ground(0.0, 300.0)
			ok(absf(g) > 5.0, "the ground 300 m south is not at the valley floor's height (%.1f m)" % g)
			_put(Vector3(0.0, g + 1.2, 300.0))
			_step = 1
			_stage_t = 0.0
		1:
			if _stage_t < 3.0:
				return false
			# THE bug: after one second here the old net teleported you to (0,2,0)
			var p := _player.global_position
			ok(Vector2(p.x, p.z).distance_to(Vector2(0.0, 300.0)) < 6.0,
				"still standing 300 m south after 3 s (at %s)" % str(p))
			ok(not bool(_world._underground), "...and not 'underground'")
			near(float(_world._in_rock_t), 0.0, 0.001, "...and not being counted as buried in rock")
			var amb: float = _world._env.ambient_light_energy
			ok(amb > 0.25, "...and the light is the surface's, not the cave's (%.2f)" % amb)
			var fog: float = _world._env.fog_density
			ok(fog < 0.01, "...and so is the fog (%.4f)" % fog)
			ok(not bool(_player.get("_in_dark")), "...and the torch stayed put")
			ok(String(_world._title_label.text) != "The Hollow Depths", "no 'Hollow Depths' title on the beach")
			_step = 2
			_stage_t = 0.0
		2:
			# --- the cave mouths are open: nothing solid above the ramp floor
			# The ramp is open ground for its first metres (t -4..0), then dives
			# under the cap's stone brow. Wherever the ray goes, the heightfield
			# tile (named T128_*) must not be among the things it hits -- that
			# was the invisible floor at y = 0 sealing both caves. The region's
			# own rock (unnamed bodies) is fine at any height: it is the cave.
			var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
			var sealed := 0
			var probed := 0
			var floors := 0
			for site in _world._cave_sites:
				var m: Vector3 = site["mouth"]
				var d: Vector3 = site["dir"]
				for t in [-4.0, 0.0, 3.0, 6.0, 9.0, 12.0, 16.0]:
					var pos: Vector3 = m + d * t
					var start := Vector3(pos.x, 6.0, pos.z)
					probed += 1
					var lowest := 99.0
					for i in range(5):
						var q := PhysicsRayQueryParameters3D.create(start, Vector3(pos.x, -40.0, pos.z))
						var h := space.intersect_ray(q)
						if h.is_empty():
							break
						var nm := String((h["collider"] as Node).name)
						var y := (h["position"] as Vector3).y
						if nm.begins_with("T128"):
							sealed += 1
						lowest = minf(lowest, y)
						start = (h["position"] as Vector3) + Vector3(0, -0.3, 0)
					if lowest < -0.5:
						floors += 1
			ok(probed >= 14, "probed both mouth ramps (%d columns)" % probed)
			ok(sealed == 0, "the heightfield collider never crosses a cave ramp (%d columns hit it)" % sealed)
			ok(floors >= probed - 4, "the ramps go down under every column (%d of %d)" % [floors, probed])
			# and outside the square the terrain IS the floor
			var q2 := PhysicsRayQueryParameters3D.create(Vector3(160.0, 6.0, 4.0), Vector3(160.0, -40.0, 4.0))
			var h2 := space.intersect_ray(q2)
			ok(not h2.is_empty() and String((h2["collider"] as Node).name).begins_with("T128"),
				"160 m east the heightfield is the floor")
			# inside the square the region's rock is the floor, right at its edge
			var q3 := PhysicsRayQueryParameters3D.create(Vector3(103.0, 6.0, 4.0), Vector3(103.0, -40.0, 4.0))
			var h3 := space.intersect_ray(q3)
			ok(not h3.is_empty() and not String((h3["collider"] as Node).name).begins_with("T128"),
				"103 m east the cave block's rock is the floor")
			if not h3.is_empty():
				near((h3["position"] as Vector3).y, 0.0, 0.3, "...at y = 0, flush with the heightfield")
			# --- Portland announces itself
			var pg := _ground(240.0, 416.0)
			_put(Vector3(240.0, pg + 1.2, 416.0))
			_step = 3
			_stage_t = 0.0
		3:
			if _stage_t < 2.0:
				return false
			ok(String(_world._place_name) == "Portland", "the place title found Portland (got '%s')" % _world._place_name)
			# --- into the sea
			var sea: float = _ow.sea_level
			ok(_ground(2000.0, 1600.0) < sea - 2.0, "the Gulf of Maine is deeper than a wade")
			_put(Vector3(2000.0, sea + 0.3, 1600.0))
			_step = 4
			_stage_t = 0.0
		4:
			if _stage_t < 3.5:
				return false
			var sea: float = _ow.sea_level
			ok(bool(_player.get("swimming")), "chest-deep in the sea you swim")
			var py: float = _player.global_position.y
			var eye: float = float(_player.get("_eye_h"))
			near(py, sea - (eye - float(_player.SWIM_FLOAT_EYE)), 0.6, "...floating with the eyes clear of the surface")
			ok(absf(float(_player.velocity.y)) < 1.0, "...settled, not sinking (vy %.2f)" % float(_player.velocity.y))
			ok(not bool(_world._underground), "...and the sea is not a cave")
			# --- back onto land: the swim ends
			var g := _ground(0.0, 300.0)
			_put(Vector3(0.0, g + 1.2, 300.0))
			_step = 5
			_stage_t = 0.0
		5:
			if _stage_t < 1.5:
				return false
			ok(not bool(_player.get("swimming")), "back on land the swim ends")
			# --- deep wood: real trees grow around you within a few seconds
			var g := _ground(800.0, -1600.0)
			_put(Vector3(800.0, g + 1.2, -1600.0))
			_step = 6
			_stage_t = 0.0
		6:
			if _stage_t < 8.0:
				return false
			var real: int = _ow.real_tree_count()
			ok(real > 0, "real, choppable trees grew around the new position (%d)" % real)
			var p := _player.global_position
			ok(Vector2(p.x, p.z).distance_to(Vector2(800.0, -1600.0)) < 6.0, "still standing in the deep wood")
			print("  (streamer: %s)" % str(_ow.forest_stats()))
			_step = 7
			_stage_t = 0.0
		7:
			# ================= WATER (2026-09-01) =================
			# --- the water's voice is wired and the pack is there
			var wa: Node = _world.get("_water_audio")
			ok(wa != null, "World built a WaterAudio when the overworld was on")
			if wa != null:
				ok(int(wa.manifest.size()) >= 14, "...and it found the water sound pack (%d sounds)" % int(wa.manifest.size()))
			# --- thirst: survival by default, light forgives
			ok(int(_player.get("set_thirst_mode")) == 0, "thirst starts in Survival")
			near(float(_player.thirst_rate_per_sec()) * 1.5 * float(DayNight.DAY_SECONDS), 100.0, 0.01,
				"the meter empties in a day and a half")
			_player.thirst = 100.0
			_player.set("set_thirst_mode", 1)
			_player._thirst_tick(600.0)
			near(float(_player.thirst), 100.0, 0.001, "Light mode: ten minutes cost nothing")
			_player.set("set_thirst_mode", 0)
			_player._thirst_tick(600.0)
			ok(float(_player.thirst) < 100.0 and float(_player.thirst) > 40.0,
				"Survival: ten minutes standing cost a third of the meter (%.1f)" % float(_player.thirst))
			ok(_player._has_waterskin() >= 0, "a waterskin is in the starting pack")
			ok(_player._skin_fills(_player._has_waterskin()) == _player.SKIN_FILLS, "...full")
			# --- breath
			_player.breath = 100.0
			_player._breath_tick(10.0, 1.0)
			near(float(_player.breath), 75.0, 0.5, "ten seconds under costs a quarter of the air")
			_player._breath_tick(10.0, 0.0)
			near(float(_player.breath), 100.0, 0.5, "...and comes back three times as fast")
			# --- the sea is brine: stand on Portland's beach looking out
			var gz := 700.0
			while not Overworld.is_water_at(Vector3(300.0, 0.0, gz)) and gz < 800.0:
				gz += 0.5
			gz -= 1.2   # a long step back from the waterline
			var g := _ground(300.0, gz)
			_put(Vector3(300.0, g + 1.0, gz))
			_player.rotation.y = PI   # forward = +z = the sea
			_step = 8
			_stage_t = 0.0
		8:
			if _stage_t < 1.0:
				return false
			_player._update_water_target()
			ok(_player.get("_water_target") != Vector3.INF, "the sea in front of you is drinkable-looking water")
			ok(bool(_player.get("_water_is_sea")), "...and it is the SEA")
			var th0: float = _player.thirst
			_player._drink_water()
			near(float(_player.thirst), th0, 0.001, "drinking brine does nothing for thirst")
			# --- a fresh shore: walk east from Moosehead's marker to the water's edge
			var mx := 1285.9
			var mz := -4120.1
			ok(Overworld.is_water_at(Vector3(mx, 0.0, mz)), "Moosehead is water at its marker")
			ok(not Overworld.water_is_sea(Vector3(mx, 0.0, mz)), "...fresh")
			var sx := mx
			while Overworld.is_water_at(Vector3(sx, 0.0, mz)) and sx < mx + 2000.0:
				sx += 4.0
			sx -= 4.0
			while Overworld.is_water_at(Vector3(sx, 0.0, mz)):
				sx += 0.5   # the waterline, to half a metre
			_shore = Vector3(sx + 1.2, _ground(sx + 1.2, mz), mz)
			_put(_shore + Vector3.UP * 1.0)
			_player.rotation.y = PI * 0.5   # forward = -x = back toward the lake
			_ow.warm(_shore)
			_step = 9
			_stage_t = 0.0
		9:
			if _stage_t < 1.5:
				return false
			_player._update_water_target()
			ok(_player.get("_water_target") != Vector3.INF, "the lake is in reach from its shore")
			ok(not bool(_player.get("_water_is_sea")), "...and it is fresh")
			_player.thirst = 30.0
			_player.set("_drink_cd", 0.0)
			_player._drink_water()
			near(float(_player.thirst), 30.0 + float(_player.THIRST_DRAUGHT), 0.01, "E at the lake: a long drink")
			var idx: int = _player._has_waterskin()
			_player._set_skin_fills(idx, 0)
			_player.set("_drink_cd", 0.0)
			_player._fill_waterskin()
			ok(_player._skin_fills(idx) == _player.SKIN_FILLS, "F at the lake: the skin fills")
			_player.thirst = 30.0
			_player._drink_skin(idx)
			ok(_player._skin_fills(idx) == _player.SKIN_FILLS - 1, "a pull on the skin spends one draught")
			near(float(_player.thirst), 30.0 + float(_player.SKIN_DRAUGHT), 0.01, "...and slakes")
			# --- the snapper: a shallow spot just off this shore, swimmer over it
			# (deep enough to SWIM over first -- world v2's shores shelve gently,
			# so the first 1.3 m cell is standing depth -- then the old floor)
			var spot := Vector3.INF
			for lo in [2.0, 1.3]:
				for k in range(1, 40):
					var q := Vector3(_shore.x - 1.0 - float(k) * 2.0, 0.0, _shore.z)
					var dep := Overworld.water_depth_at(q)
					if dep >= float(lo) and dep <= 3.0:
						spot = q
						break
				if spot != Vector3.INF:
					break
			ok(spot != Vector3.INF, "found 1.3-3 m of water off the shore for the ambush")
			if spot == Vector3.INF:
				_finish()
				return true
			var wl: Node = _world.get("_wildlife")
			_snapper = wl.spawn_one("snapper", spot) if wl != null else null
			ok(_snapper != null, "a snapping turtle can be placed in the lake")
			if _snapper != null:
				_snapper.global_position = Vector3(spot.x, Overworld.ground_y(spot) + 0.12, spot.z)
			_player.thirst = 100.0
			_put(Vector3(spot.x, Overworld.water_y(spot) - 0.3, spot.z))
			_step = 10
			_stage_t = 0.0
		10:
			if _stage_t < 2.5:
				return false
			var held: Node = _player.get("grabbed_by")
			if not _hold_seen:
				ok(bool(_player.get("swimming")), "over the snapper you are swimming")
				ok(held != null and held == _snapper, "...and the snapper has your leg (held by %s)" % (str(held.name) if held else "nobody"))
				_hold_seen = true
				_hold_t0 = _stage_t
				if held == null or held != _snapper:
					_step = 11
					_stage_t = 0.0
				return false
			if _stage_t - _hold_t0 < 2.0:
				return false   # two seconds in its jaws
			ok(held != null and held == _snapper, "...and it is still holding two seconds later")
			ok(float(_player.breath) < 97.0, "your head is under while it holds you (breath %.0f)" % float(_player.breath))
			if held != null and held == _snapper:
				ok(String(_snapper.get("_ambush")) == "hold", "the snapper is in its hold")
				ok(float(_snapper.hold_seconds()) > 5.0, "the holder sets the clock, not the bear's 4.5 s")
				for _i in range(_snapper.AMBUSH_NEED):
					_snapper.struggled()
			_step = 11
			_stage_t = 0.0
		11:
			if _stage_t < 1.0:
				return false
			ok(_player.get("grabbed_by") == null, "six kicks and the snapper lets go")
			if _snapper != null and is_instance_valid(_snapper):
				ok(String(_snapper.get("_ambush")) == "flee", "...and it runs")
				_snapper.queue_free()
			# --- the Drowned: night, deep water, far from shore
			var dn: Node = _world.get("_daynight")
			if dn != null:
				dn.set("hour", 23.5)
			var deep := Vector3.INF
			for k in range(6, 200):
				var q := Vector3(_shore.x - float(k) * 4.0, 0.0, _shore.z)
				if Overworld.water_depth_at(q) >= 4.0 and float(Overworld.nearest_dry(q, 40.0).get("dist", INF)) >= 14.0:
					deep = q
					break
			ok(deep != Vector3.INF, "Moosehead has deep water more than 14 m from any shore")
			if deep == Vector3.INF:
				_finish()
				return true
			_ow.warm(deep)
			_put(Vector3(deep.x, Overworld.water_y(deep) - 0.3, deep.z))
			_world.set("_drowned_cd", 0.0)
			_world.set("_drowned_risk", 60.0)   # fires on the next tick
			_step = 12
			_stage_t = 0.0
		12:
			if _stage_t < 3.6:
				return false
			ok(bool(_world.drowned_active()), "something came up under the night swimmer")
			var held: Node = _player.get("grabbed_by")
			ok(held is Drowned, "...and it has you (held by %s)" % (str(held.name) if held else "nobody"))
			if held is Drowned:
				for _i in range(held.STRUGGLE_NEED):
					held.struggled()
			_step = 13
			_stage_t = 0.0
		13:
			if _stage_t < 3.5:
				return false
			ok(_player.get("grabbed_by") == null, "eight kicks and the Drowned lets go")
			ok(not bool(_world.drowned_active()), "...and it is gone")
			ok(float(_world.get("_drowned_cd")) > 0.0, "...with the cooldown running")
			_finish()
			return true
	return false
