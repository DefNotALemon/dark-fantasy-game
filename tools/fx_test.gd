extends SceneTree
## Headless checks for: the Main Hand mirror, the long meteor fall, metal
## auras (fire/void/lamplight), burn damage, armor weather, and vein-chunk ore.

var _t := 0.0
var _step := 0
var _w: Node
var _p: Node
var _fails: Array[String] = []
var _meteoric_before := 0

func _ok(c: bool, what: String) -> void:
	print(("  PASS  " if c else "  FAIL  ") + what)
	if not c:
		_fails.append(what)

func _initialize() -> void:
	_w = (load("res://scenes/World.tscn") as PackedScene).instantiate()
	root.add_child(_w)

func _count_lights(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		if ch is OmniLight3D:
			c += 1
		c += _count_lights(ch)
	return c

func _count_particles(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		if ch is CPUParticles3D:
			c += 1
		c += _count_particles(ch)
	return c

func _give_and_equip(d: Dictionary) -> void:
	_p._give_item_dict(d.duplicate(true))
	_p._equip_from_pack(_p._find_item_index(String(d["name"])), String(d["slot"]))
	if String(d["slot"]) == "sword":
		_p._apply_equipped_sword()
	else:
		_p._apply_armor_visuals()

func _process(d: float) -> bool:
	_t += d
	if _t < 1.5:
		return false
	match _step:
		0:
			_p = root.get_tree().get_first_node_in_group("player")
			## --- Main Hand mirror ---
			_ok(_p.hands_root != null, "hands root exists")
			_ok(_p._settings_widgets.has("hand"), "Main Hand row is in the settings menu")
			_p.set_lefty = true
			_p._apply_settings()
			_ok(_p.hands_root.scale.x < 0.0, "lefty mirrors the first-person kit (x = %.0f)" % _p.hands_root.scale.x)
			_ok(_p.body_rig.scale.x < 0.0, "lefty mirrors the visible body")
			_p.set_lefty = false
			_p._apply_settings()
			_ok(_p.hands_root.scale.x > 0.0, "righty restores it")
			_step = 1
		1:
			## --- Blade fx per metal ---
			var host := Node3D.new()
			_w.add_child(host)
			var met: Node3D = _p._make_sword(host, Vector3.ZERO, "meteoric")
			_ok(_count_lights(met) >= 1, "meteoric blade carries a light")
			_ok(_count_particles(met) >= 1, "meteoric blade sheds pixel fire")
			var drg: Node3D = _p._make_sword(host, Vector3.ZERO, "dragonsteel")
			_ok(_count_lights(drg) >= 1 and _count_particles(drg) >= 1, "dragonsteel burns too")
			var mith: Node3D = _p._make_sword(host, Vector3.ZERO, "mithril")
			_ok(_count_lights(mith) >= 1, "mithril emits light")
			_ok(_count_particles(mith) == 0, "mithril light is clean (no particles)")
			var ada: Node3D = _p._make_sword(host, Vector3.ZERO, "adamant")
			_ok(_count_lights(ada) >= 1, "adamant emits amber light")
			var vs: Node3D = _p._make_sword(host, Vector3.ZERO, "voidsteel")
			_ok(_count_lights(vs) >= 1 and _count_particles(vs) >= 1, "voidsteel glows purple with a void flow")
			var irn: Node3D = _p._make_sword(host, Vector3.ZERO, "iron")
			_ok(_count_lights(irn) == 0 and _count_particles(irn) == 0, "iron is just honest iron")
			host.queue_free()
			_step = 2
		2:
			## --- Burn: direct, and through a meteoric swing ---
			var boar := Boar.new()
			_w.add_child(boar)
			boar.global_position = _p.global_position + Vector3(0, 0.5, -2.0)
			var hp0: float = boar.health
			boar.apply_burn(4.0, 2.0)
			_ok(boar.burn_t > 0.0, "burn takes hold")
			set_meta("boar", boar)
			set_meta("boar_hp0", hp0)
			_step = 3
		3:
			if _t < 3.5:
				return false
			var boar: Node = get_meta("boar")
			_ok(boar.health < float(get_meta("boar_hp0")), "burn ticks damage over time (%.1f lost)"
				% (float(get_meta("boar_hp0")) - boar.health))
			## Swing a meteoric blade at it.
			_give_and_equip({"name": "Meteoric Sword", "weight": 3.0, "count": 1,
				"slot": "sword", "material": "meteoric"})
			boar.burn_t = 0.0
			boar.health = boar.max_health
			## Two seconds of physics let it wander — pin it back in the
			## swing cone, dead ahead of the CAMERA, before the cut.
			var fwd: Vector3 = -_p.camera.global_transform.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			boar.global_position = _p.global_position + fwd * 1.7 + Vector3.UP * 0.4
			boar.velocity = Vector3.ZERO
			_p.sheathed = false
			_p.sheath_t = 0.0
			_p.attacking = false
			_p.committed = false
			_p._do_melee_hit()
			_ok(boar.burn_t > 0.0, "a meteoric swing leaves the wound burning")
			(boar as Node).queue_free()
			_step = 4
		4:
			## --- Armor weather ---
			_give_and_equip({"name": "Meteoric Chestpiece", "weight": 8.0, "count": 1,
				"slot": "chest", "material": "meteoric"})
			_ok(_p._armor_fx_mode == "fire", "meteoric plate smolders (fire weather)")
			_ok(is_instance_valid(_p._armor_fx), "the armor fire emitter exists")
			_give_and_equip({"name": "Voidsteel Chestpiece", "weight": 8.0, "count": 1,
				"slot": "chest", "material": "voidsteel"})
			_ok(_p._armor_fx_mode == "void", "voidsteel plate leaks the void")
			_p._unequip_slot("chest")
			_p._apply_armor_visuals()
			_ok(_p._armor_fx_mode == "", "bare padding carries no weather")
			_step = 5
		5:
			## --- Dropped ore looks like a piece of the vein ---
			var ore := DroppedItem.make({"name": "Silver Ore", "weight": 2.0, "count": 1,
				"slot": "", "material": "silver"})
			_w.add_child(ore)
			ore.global_position = _p.global_position + Vector3(2, 1, 0)
			var boxes := ore.get_child_count()
			_ok(boxes >= 6, "ore chunk is rock + glowing seams (%d parts)" % boxes)
			var wide := 0.0
			for ch in ore.get_children():
				if ch is MeshInstance3D and (ch as MeshInstance3D).mesh is BoxMesh:
					wide = maxf(wide, ((ch as MeshInstance3D).mesh as BoxMesh).size.x)
			_ok(wide >= 0.5, "and it is BIG now (%.2f m across)" % wide)
			_ok(OreVein.ORE_PER_VEIN[0] >= 2, "a vein breaks into a couple of them (%d-%d)"
				% [OreVein.ORE_PER_VEIN[0], OreVein.ORE_PER_VEIN[1]])
			ore.queue_free()
			_step = 6
		6:
			## --- The long meteor fall ---
			for v in root.get_tree().get_nodes_in_group("ore_veins"):
				if v is OreVein and (v as OreVein).mat_id == "meteoric":
					_meteoric_before += 1
			_w.drop_meteor()
			var m := root.get_tree().get_first_node_in_group("meteor")
			_ok(m != null, "the omen is in the sky")
			_ok(m.descent_dur > 15.0, "and it takes its time (%.0f s descent)" % m.descent_dur)
			_ok(m.global_position.y > 100.0, "high overhead (y = %.0f)" % m.global_position.y)
			## Fast-forward the omen so the test doesn't wait out the show.
			m.t = m.descent_dur - 0.05
			_step = 7
		7:
			if _t < 9.0:
				return false
			var after := 0
			for v in root.get_tree().get_nodes_in_group("ore_veins"):
				if v is OreVein and (v as OreVein).mat_id == "meteoric":
					after += 1
			_ok(after - _meteoric_before >= 6, "the dive landed: fused meteoric ball in the crater (+%d veins)"
				% (after - _meteoric_before))
			_ok(root.get_tree().get_first_node_in_group("meteor") == null, "and the star is spent")
			print("")
			print("ALL CHECKS PASSED" if _fails.is_empty() else "FAILURES: " + ", ".join(_fails))
			quit(0 if _fails.is_empty() else 1)
	return false
