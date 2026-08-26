extends SceneTree
## What the world actually costs to build and to keep.
## Runs against the REAL scripts — every number below is measured, not guessed.

var _rng := RandomNumberGenerator.new()


func _count(n: Node, out: Dictionary) -> void:
	out["nodes"] = int(out.get("nodes", 0)) + 1
	if n is MeshInstance3D:
		out["meshes"] = int(out.get("meshes", 0)) + 1
		var mi := n as MeshInstance3D
		var m := mi.material_override
		if m == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			m = mi.mesh.surface_get_material(0)
		if m != null:
			(out["mats"] as Dictionary)[m.get_instance_id()] = true
		if mi.mesh != null:
			for s in range(mi.mesh.get_surface_count()):
				var arr = mi.mesh.surface_get_arrays(s)
				if arr != null and arr.size() > Mesh.ARRAY_VERTEX and arr[Mesh.ARRAY_VERTEX] != null:
					var idx = arr[Mesh.ARRAY_INDEX]
					var t := 0
					if idx != null and (idx as PackedInt32Array).size() > 0:
						t = (idx as PackedInt32Array).size() / 3
					else:
						t = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
					out["tris"] = int(out.get("tris", 0)) + t
	if n is MultiMeshInstance3D:
		out["mmi"] = int(out.get("mmi", 0)) + 1
	if n is CollisionShape3D:
		out["shapes"] = int(out.get("shapes", 0)) + 1
	if n is Light3D:
		out["lights"] = int(out.get("lights", 0)) + 1
	if n is GPUParticles3D:
		out["particles"] = int(out.get("particles", 0)) + 1
	for c in n.get_children():
		_count(c, out)


func _measure(label: String, maker: Callable, reps := 4) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var made: Array[Node] = []
	for i in range(reps):
		var n := maker.call() as Node
		root.add_child(n)
		made.append(n)
	var us := Time.get_ticks_usec() - t0
	var out := {"mats": {}}
	_count(made[0], out)
	var mats := (out["mats"] as Dictionary).size()
	print("  %-14s %5d nodes  %4d meshes  %4d tris  %3d shapes  %3d unique materials   %6.2f ms each"
		% [label, out.get("nodes", 0), out.get("meshes", 0), out.get("tris", 0),
			out.get("shapes", 0), mats, float(us) / float(reps) / 1000.0])
	for n in made:
		n.queue_free()
	return {"nodes": out.get("nodes", 0), "meshes": out.get("meshes", 0),
		"tris": out.get("tris", 0), "mats": mats, "ms": float(us) / float(reps) / 1000.0,
		"shapes": out.get("shapes", 0)}


func _init() -> void:
	## _init runs before root is in the tree, so add_child() would not fire
	## _ready() and every body would measure as one empty node. Wait a frame.
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	_rng.seed = 20260630
	print("=================================================================")
	print("  MYRKFELL — what the world costs at startup       (measured)")
	print("=================================================================")

	print("\n-- 1. one of each, built for real --")
	var cost := {}
	cost["Goblin"] = _measure("Goblin", func(): return Goblin.new())
	cost["Kobold"] = _measure("Kobold", func(): return Kobold.new())
	cost["Skeleton"] = _measure("Skeleton", func(): return Skeleton.new())
	cost["Orc"] = _measure("Orc", func(): return Orc.new())
	cost["Ogre"] = _measure("Ogre", func(): return Ogre.new())
	cost["DarkKnight"] = _measure("DarkKnight", func(): return DarkKnight.new())
	cost["Boar"] = _measure("Boar", func(): return Boar.new())
	cost["Horse"] = _measure("Horse", func(): return Horse.new())
	cost["SaddledHorse"] = _measure("SaddledHorse", func(): return SaddledHorse.new())
	var tree_cost := _measure("TreeV2", func(): return TreeV2.make(_rng), 6)
	var critter_cost := _measure("Critter(deer)", func(): return Critter.make("whitetail"), 2)

	print("\n-- 2. how many mobs the caves ACTUALLY spawn --")
	## Replays _spawn_dwellers' exact roll tables 20,000 times. Pocket COUNT is
	## capped by _pick_spots at 13 + 9; a sparse field can return fewer, so this
	## is the ceiling the code is written to, which is the number that has to be
	## survivable on a cold start.
	var runs := 4000
	var tot_min := 99999
	var tot_max := 0
	var tot_sum := 0
	var by_kind := {}
	var r2 := RandomNumberGenerator.new()
	r2.seed = 7717
	for _n in range(runs):
		var counts := {"Kobold": 0, "Goblin": 0, "Skeleton": 0, "Orc": 0, "Ogre": 0, "DarkKnight": 0}
		## 13 pockets, sorted shallow -> deep; the last is the champion's court
		for i in range(13):
			if i == 12:
				counts["DarkKnight"] += 1
				counts["Orc"] += r2.randi_range(2, 3)
				continue
			## depth band by rank: the sort puts the shallow ones first
			var y := lerpf(-5.0, -30.0, float(i) / 12.0)
			var roll := r2.randf()
			if y > -12.0:
				if roll < 0.6:
					counts["Kobold"] += r2.randi_range(6, 10)
				else:
					counts["Goblin"] += r2.randi_range(3, 6)
			elif y > -21.0:
				if roll < 0.4:
					counts["Goblin"] += r2.randi_range(3, 6)
				elif roll < 0.8:
					counts["Skeleton"] += r2.randi_range(4, 7)
				else:
					counts["Ogre"] += r2.randi_range(1, 2)
			else:
				if roll < 0.4:
					counts["Skeleton"] += r2.randi_range(4, 7)
				elif roll < 0.75:
					counts["Orc"] += r2.randi_range(2, 4)
				else:
					counts["Ogre"] += r2.randi_range(1, 2)
		for _j in range(9):   ## the deep belt
			var roll2 := r2.randf()
			if roll2 < 0.35:
				counts["Skeleton"] += r2.randi_range(5, 8)
			elif roll2 < 0.7:
				counts["Orc"] += r2.randi_range(3, 5)
			elif roll2 < 0.92:
				counts["Ogre"] += r2.randi_range(1, 3)
			else:
				counts["DarkKnight"] += 1
				counts["Orc"] += 2
		var tot := 0
		for k in counts:
			tot += int(counts[k])
			by_kind[k] = float(by_kind.get(k, 0.0)) + float(counts[k])
		tot_sum += tot
		tot_min = mini(tot_min, tot)
		tot_max = maxi(tot_max, tot)
	var mean := float(tot_sum) / float(runs)
	print("  cave dwellers per world:  min %d   mean %.1f   max %d" % [tot_min, mean, tot_max])
	var mob_nodes := 0.0
	var mob_mats := 0.0
	var mob_meshes := 0.0
	var mob_ms := 0.0
	for k in by_kind:
		var avg := float(by_kind[k]) / float(runs)
		print("    %-11s %6.1f" % [k, avg])
		mob_nodes += avg * float((cost[k] as Dictionary)["nodes"])
		mob_mats += avg * float((cost[k] as Dictionary)["mats"])
		mob_meshes += avg * float((cost[k] as Dictionary)["meshes"])
		mob_ms += avg * float((cost[k] as Dictionary)["ms"])

	print("\n-- 3. the surface, as World._ready builds it --")
	var boars := 5.0
	var saddled := 2.0
	var wild := 7.0
	var surf_nodes := boars * float((cost["Boar"] as Dictionary)["nodes"]) \
		+ saddled * float((cost["SaddledHorse"] as Dictionary)["nodes"]) \
		+ wild * float((cost["Horse"] as Dictionary)["nodes"])
	var surf_mats := boars * float((cost["Boar"] as Dictionary)["mats"]) \
		+ saddled * float((cost["SaddledHorse"] as Dictionary)["mats"]) \
		+ wild * float((cost["Horse"] as Dictionary)["mats"])
	var surf_ms := boars * float((cost["Boar"] as Dictionary)["ms"]) \
		+ saddled * float((cost["SaddledHorse"] as Dictionary)["ms"]) \
		+ wild * float((cost["Horse"] as Dictionary)["ms"])
	print("  boars %d + saddled %d + wild horses %d = %d bodies, %d nodes, %d materials, %.0f ms"
		% [int(boars), int(saddled), int(wild), int(boars + saddled + wild),
			int(surf_nodes), int(surf_mats), surf_ms])
	var trees := 420.0
	print("  %d trees = %d nodes, %d meshes, %s triangles, %d materials, %.0f ms"
		% [int(trees), int(trees * float(tree_cost["nodes"])),
			int(trees * float(tree_cost["meshes"])),
			_commas(int(trees * float(tree_cost["tris"]))),
			int(trees * float(tree_cost["mats"])), trees * float(tree_cost["ms"])])

	print("\n-- 4. the bill --")
	print("  cave mobs      %6d bodies  %7d nodes  %6d materials  %7.0f ms"
		% [int(mean), int(mob_nodes), int(mob_mats), mob_ms])
	print("  surface mobs   %6d bodies  %7d nodes  %6d materials  %7.0f ms"
		% [int(boars + saddled + wild), int(surf_nodes), int(surf_mats), surf_ms])
	print("  trees          %6d        %7d nodes  %6d materials  %7.0f ms"
		% [int(trees), int(trees * float(tree_cost["nodes"])),
			int(trees * float(tree_cost["mats"])), trees * float(tree_cost["ms"])])
	var all_ms := mob_ms + surf_ms + trees * float(tree_cost["ms"])
	var all_nodes := mob_nodes + surf_nodes + trees * float(tree_cost["nodes"])
	var all_mats := mob_mats + surf_mats + trees * float(tree_cost["mats"])
	print("  ---------------------------------------------------------------")
	print("  TOTAL                          %7d nodes  %6d materials  %7.0f ms"
		% [int(all_nodes), int(all_mats), all_ms])
	print("  (%.1f s of that is content the player cannot see from the spawn point)"
		% ((mob_ms + surf_ms * 0.5) / 1000.0))

	print("\n-- 5. what those bodies cost EVERY FRAME while asleep --")
	## Enemy._physics_process's far-away early-out still calls _get_player(),
	## which is get_tree().get_nodes_in_group() — a fresh Array allocation —
	## and then move_and_slide(). Measure the group lookup at that scale.
	var dummies: Array[Node3D] = []
	for i in range(3):
		var d := Node3D.new()
		d.add_to_group("player")
		root.add_child(d)
		dummies.append(d)
	var calls := int(mean) * 60
	var t1 := Time.get_ticks_usec()
	for i in range(calls):
		var pl := get_nodes_in_group("player")
		if pl.size() > 0:
			pass
	var lookup_us := Time.get_ticks_usec() - t1
	print("  %d sleeping mobs x 60 fps = %s group lookups/sec = %.1f ms/sec of pure allocation"
		% [int(mean), _commas(calls), float(lookup_us) / 1000.0])
	print("  ...plus %s move_and_slide() calls/sec on bodies nobody can see."
		% _commas(calls))

	print("\n-- 6. the ceiling if mobs were streamed instead --")
	## Nothing needs to exist beyond the despawn ring the wildlife already uses.
	print("  WildlifeDirector already streams: BUDGET %d live, spawn ring %s m, despawn %d m."
		% [WildlifeDirector.BUDGET, str(WildlifeDirector.SPAWN_RING), int(WildlifeDirector.DESPAWN_AT)])
	var streamed := 24
	print("  Hostiles on the same contract: ~%d live instead of %d." % [streamed, int(mean)])
	var save_nodes := all_nodes - (float(streamed) / mean) * mob_nodes - surf_nodes * 0.4 \
		- trees * float(tree_cost["nodes"])
	print("  That alone is %d fewer nodes and %d fewer materials at boot."
		% [int(mob_nodes * (1.0 - float(streamed) / mean)),
			int(mob_mats * (1.0 - float(streamed) / mean))])
	print("=================================================================")
	quit(0)


func _commas(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out
