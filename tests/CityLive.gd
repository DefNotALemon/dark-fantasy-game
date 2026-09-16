extends SceneTree
## Boot the real World.tscn headless and ask the CITIES what world they read:
## the roster source, the six names, and whether the gates came off the real
## RoadNet (a city with only the two default gates read no roads).
##   godot --headless --path . --script res://tests/CityLive.gd

var _t := 0.0
var _world: Node = null
var _pass := 0
var _fail := 0


func ok(c: bool, what: String) -> void:
	if c:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: ", what)


## THE UNDERGROUND TOWNS, 2026-09-13. Every city was laid out flat at y = 0
## because World spells its height probe `_surface_y(Vector3)` and Cities
## looked for four (x, z) names it does not have. On a bake whose benches
## stand at 8 to 108 m, that buried all six. Nothing in the headless suite
## could see it: the suite injects its own ground and the injection worked.
## This is the assertion that would have caught it — measured against the
## REAL heightfield, on the REAL World.
func _t_not_buried(c: Node, cities: Dictionary) -> void:
	var buried := 0
	var worst_name := ""
	var worst := 0.0
	var checked := 0
	for nm in cities.keys():
		var lay: Dictionary = cities[nm]
		var cen: Vector3 = lay["centre"]
		var ground: float = float(_world.call("_surface_y", cen))
		if absf(cen.y - ground) > 0.5:
			buried += 1
			if absf(cen.y - ground) > absf(worst):
				worst = cen.y - ground
				worst_name = nm
		var node: Node3D = c.call("stage", nm)
		if node == null:
			continue
		## the roof ridge of every house, and the head of every lamp: if the
		## town is under its own hill these are the first things to vanish.
		for holder_name in ["Lots", "Lamps"]:
			var holder: Node3D = node.get_node_or_null(holder_name)
			if holder == null:
				continue
			for ch in holder.get_children():
				var n3 := ch as Node3D
				if n3 == null:
					continue
				var g: float = float(_world.call("_surface_y", n3.global_position))
				checked += 1
				var under: float = g - n3.global_position.y
				if under > 1.6:      ## deeper than the plinth: genuinely buried
					buried += 1
					if under > worst:
						worst = under
						worst_name = "%s/%s" % [nm, n3.name]
		c.call("strike", nm)
	ok(checked > 300, "there were houses and lamps to check (%d)" % checked)
	ok(buried == 0, "nothing is underground (%d buried, worst %s by %.1f m)" % [buried, worst_name, worst])
	ok(float((cities["Presque Isle"]["centre"] as Vector3).y) > 100.0, "the Shelf Town stands on its 108 m shelf")
	ok(float((cities["Portland"]["centre"] as Vector3).y) > 8.0, "Portland stands on its harbour bench")


func _initialize() -> void:
	_world = (load("res://scenes/World.tscn") as PackedScene).instantiate()
	root.add_child(_world)


var _phase := 0


func _process(d: float) -> bool:
	_t += d
	if _phase == 0:
		## Behind the main menu nothing has been built yet: walk through the
		## front door the way PLAY does, then wait for begin_world.
		if _t < 3.0:
			return false
		_phase = 1
		if _world.has_method("front_door_done"):
			_world.call("front_door_done", false)
		return false
	var c: Node = _world.call("cities") if _world.has_method("cities") else null
	if c == null:
		if _t < 240.0:
			return false
		ok(false, "World.cities() never answered (begin_world did not run in 240 s)")
		print("=== CITY LIVE: %d passed, %d failed ===" % [_pass, _fail])
		quit(1)
		return true
	ok(true, "World.cities() answers after begin_world (%.0f s)" % _t)
	print(c.call("report"))
	ok(String(c.get("roster_source")) == "world", "roster is the world's (%s)" % String(c.get("roster_source")))
	var cities: Dictionary = c.get("cities")
	ok(cities.size() == 6, "six cities (%d)" % cities.size())
	for nm in ["Portland", "Bangor", "Augusta", "Brunswick", "Presque Isle", "Lewiston-Auburn"]:
		ok(cities.has(nm), "%s is a city" % nm)
	var net: Object = _world.call("roadnet") if _world.has_method("roadnet") else null
	ok(net != null, "the road net exists")
	var with_roads := 0
	for nm in cities.keys():
		var dirs: Array = c.call("road_dirs_for", nm)
		var lay: Dictionary = cities[nm]
		var gates: Array = lay.get("gates", [])
		print("  %-16s roads %d  gates %d  centre %s" % [nm, dirs.size(), gates.size(), str(lay.get("centre", "?"))])
		if dirs.size() > 0:
			with_roads += 1
	ok(with_roads >= 5, "at least five of six cities read their roads off the net (%d)" % with_roads)
	_t_not_buried(c, cities)
	print("=== CITY LIVE: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
	return true
