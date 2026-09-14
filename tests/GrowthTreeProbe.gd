extends SceneTree
## The real TreeV2 grows real patches, saves them, and a restored tree gets
## the same ones back without re-rolling.
var _f := 0
var _pass := 0
var _fail := 0
var _trees: Array = []
var _restored: TreeV2
var _src_dict: Dictionary
var _dn: Node
var _wx: Node

func ok(c: bool, w: String) -> void:
	if c: _pass += 1
	else:
		_fail += 1
		printerr("FAIL: " + w)

func _init() -> void:
	_dn = Node.new(); _dn.set_script(_gd("extends Node\nvar day := 30.0\nvar hour := 12.0\n"))
	_wx = Node.new(); _wx.set_script(_gd("extends Node\nvar wetness := 0.5\n"))
	root.add_child(_dn); root.add_child(_wx)
	GrowthClock.bind(_dn, _wx)
	root.add_child(GrowthClock.new())
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var i := 0
	for sp in ["oak", "maple", "birch", "pine", "fir"]:
		for st in [2, 3, 4]:
			var t := TreeV2.make(rng, sp, st)
			t.position = Vector3(i * 6.0, 0, 0)
			t.rotation.y = rng.randf() * TAU
			root.add_child(t)
			_trees.append(t)
			i += 1

func _gd(src: String) -> GDScript:
	var s := GDScript.new(); s.source_code = src; s.reload(); return s

func _process(_d: float) -> bool:
	_f += 1
	if _f == 30:
		## every tree has rolled; count patches
		var with := 0
		var patches := 0
		var built := 0
		var types := {}
		for t in _trees:
			var ps: Array = (t as TreeV2).growth_patches()
			if ps.size() > 0: with += 1
			for p in ps:
				patches += 1
				if (p as GrowthPatch).built: built += 1
				types[(p as GrowthPatch).type_id] = true
		print("trees with growth: %d/%d, patches %d, built %d, types %s" % [with, _trees.size(), patches, built, types.keys()])
		ok(with >= 8, "most mature/ancient trees grow something")
		ok(built == patches and patches > 0, "every patch built off the kit trunk")
		ok(types.size() >= 2, "more than one family rolled")
		## card positions hug the real trunk: radius at the pivot height within the taper
		var off := 0
		var total := 0
		for t in _trees:
			var tv := t as TreeV2
			for p in tv.growth_patches():
				var mi := (p as GrowthPatch).get_node_or_null("Growth") as MeshInstance3D
				if mi == null: continue
				var c0: PackedFloat32Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0]
				for k in range(0, c0.size(), 16):
					var pv := Vector3(c0[k], c0[k+1], c0[k+2])
					var r_here := TreeKit.radius_at(tv.species, tv.stage, pv.y / tv.scale_class) * tv.scale_class
					var rad := Vector2(pv.x, pv.z).length()
					total += 1
					if rad < r_here * 0.6 or rad > r_here * 1.5 + 0.08: off += 1
		print("pivots off the taper: %d / %d" % [off, total])
		@warning_ignore("integer_division")
		ok(total > 50 and off < total / 5, "cards sit on the bark, not in the air")
		## save + restore
		var t0: TreeV2 = null
		for t in _trees:
			if (t as TreeV2).growth_patches().size() > 0:
				t0 = t; break
		_src_dict = t0.save_dict()
		ok(_src_dict.has("growth") and (_src_dict["growth"] as Array).size() == t0.growth_patches().size(), "save_dict carries the patches")
		var js := JSON.stringify(_src_dict)
		var back: Dictionary = JSON.parse_string(js)
		_restored = TreeV2.from_dict(back)
		root.add_child(_restored)
		_restored.restore(back)
		_restored.position.z = 20.0
	if _f == 60:
		ok(_restored.growth_patches().size() == (_src_dict["growth"] as Array).size(), "restored tree has the saved patch count, not a re-roll")
		var a: Array = _src_dict["growth"]
		var b: Array = _restored.growth_state()
		var same := a.size() == b.size()
		for i in range(mini(a.size(), b.size())):
			var da: Dictionary = a[i]; var db: Dictionary = b[i]
			if da["type"] != db["type"] or da["base"] != db["base"] or da["accent"] != db["accent"] or int(da["seed"]) != int(db["seed"]) or absf(float(da["ang"]) - float(db["ang"])) > 0.0001:
				same = false
		ok(same, "restored patches are the same patches")
		for p in _restored.growth_patches():
			ok((p as GrowthPatch).built, "restored patch built")
		print("GrowthTreeProbe: %d passed, %d failed" % [_pass, _fail])
		quit(1 if _fail > 0 else 0)
		return true
	return false
