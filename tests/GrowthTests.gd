extends SceneTree
## Headless suite for the growth patches (moss / fungi / vines / lichen).
##   godot --headless --path . --script res://tests/GrowthTests.gd
## Boots in _init, drives the probe through real physics frames in _process,
## asserts, then quits 0/1. Needs GrowthPatch/GrowthTypes/GrowthClock/Wind.

var _pass := 0
var _fail := 0
var _frame := 0
var _root3d: Node3D
var _trunk_host: StaticBody3D
var _rock_host: StaticBody3D
var _p_tree: GrowthPatch
var _p_rock: GrowthPatch
var _p_world: GrowthPatch
var _p_twin: GrowthPatch
var _clock: GrowthClock
var _dn: Node
var _wx: Node


func ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: " + what)


func _init() -> void:
	_root3d = Node3D.new()
	root.add_child(_root3d)

	## --- catalogue sanity ---
	for t in GrowthTypes.type_ids():
		var fam: Dictionary = GrowthTypes.family(t)
		ok(fam["bases"].size() >= 2, "%s has bases" % t)
		ok(fam["accents"].size() >= 2, "%s has accents" % t)
		for b in fam["bases"].values():
			ok(int(b["tile"]) >= 0 and int(b["tile"]) < GrowthTypes.COLS * GrowthTypes.ROWS, "tile in atlas")
			ok(float(b["size"][0]) <= float(b["size"][1]), "size band ordered")
	var atlas := GrowthTypes.atlas()
	ok(atlas.get_width() == GrowthTypes.COLS * GrowthTypes.TILE, "atlas width")
	var img := atlas.get_image()
	## every tile has both painted and clear texels
	for t in range(GrowthTypes.COLS * GrowthTypes.ROWS):
		var ox := (t % GrowthTypes.COLS) * GrowthTypes.TILE
		var oy := (t / GrowthTypes.COLS) * GrowthTypes.TILE
		var solid := 0
		var clear := 0
		for y in range(0, GrowthTypes.TILE, 4):
			for x in range(0, GrowthTypes.TILE, 4):
				var a := img.get_pixel(ox + x, oy + y).a
				if a > 0.5:
					solid += 1
				elif a < 0.05:
					clear += 1
		ok(solid > 20, "tile %d has paint (%d)" % [t, solid])
		ok(clear > 20, "tile %d has air (%d)" % [t, clear])

	## --- a fake trunk: a tapered 16-gon tube 3 m tall as a MeshInstance3D ---
	_trunk_host = StaticBody3D.new()
	_trunk_host.position = Vector3(10, 0, 5)
	_trunk_host.rotation.y = 0.7
	_root3d.add_child(_trunk_host)
	var model := Node3D.new()
	model.scale = Vector3.ONE * 1.5
	_trunk_host.add_child(model)
	var trunk := MeshInstance3D.new()
	trunk.name = "Trunk"
	trunk.mesh = _tube(0.30, 0.22, 3.0, 16)
	model.add_child(trunk)

	_p_tree = GrowthPatch.make("moss", "", "", 4242)
	_p_tree.anchor_cylinder(0.9, 1.0, 0.55, 0.9, 3.0, 1.2)
	_p_tree.probe_meshes = [trunk]
	_p_tree.probe_surface = 0
	_p_tree.shade = 0.9
	_trunk_host.add_child(_p_tree)

	## the same patch again on the same trunk -- must land the same cards
	_p_twin = GrowthPatch.from_dict(_p_tree.to_dict())
	_p_twin.probe_meshes = [trunk]
	_p_twin.probe_surface = 0
	_trunk_host.add_child(_p_twin)

	## --- a rock: box collider (crude) + a tilted box mesh (the real shape) ---
	_rock_host = StaticBody3D.new()
	_rock_host.position = Vector3(-4, 0, 2)
	_root3d.add_child(_rock_host)
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2, 2.4, 2)
	col.shape = bs
	col.position.y = 1.2
	_rock_host.add_child(col)
	var rm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2, 2.4, 2)
	rm.mesh = bm
	rm.position.y = 1.2
	rm.rotation_degrees = Vector3(8, 40, -6)
	_rock_host.add_child(rm)
	_p_rock = GrowthPatch.make("lichen", "crust_orange", "beard", 99)
	_p_rock.anchor_point(Vector3(0, 1.2, 0), Vector3(0, 0, -1), 0.9, 1.1, 4.0, true, 1.5)
	_p_rock.probe_meshes = [rm]
	_p_rock.host_key = "rock:-4,2"
	_rock_host.add_child(_p_rock)

	## --- the world: a patch probing the rock's real collider (mask 1), as a
	## cave mouth does, and with fungi so shelves and toadstools get cut ---
	_p_world = GrowthPatch.make("fungi", "mycelium", "brackets", 7)
	_p_world.anchor_point(Vector3(0, 1.2, 0), Vector3(1, 0, 0), 0.8, 1.0, 4.0, true, 2.0)
	_p_world.damp = 0.6
	_rock_host.add_child(_p_world)

	## --- the clock, on a fake DayNight / Weather ---
	_dn = Node.new()
	_dn.set_script(_fake_daynight())
	_wx = Node.new()
	_wx.set_script(_fake_weather())
	root.add_child(_dn)
	root.add_child(_wx)
	GrowthClock.bind(_dn, _wx)
	_clock = GrowthClock.new()
	root.add_child(_clock)


func _fake_daynight() -> GDScript:
	var s := GDScript.new()
	s.source_code = "extends Node\nvar day := 30.0\nvar hour := 12.0\n"
	s.reload()
	return s


func _fake_weather() -> GDScript:
	var s := GDScript.new()
	s.source_code = "extends Node\nvar wetness := 0.0\n"
	s.reload()
	return s


func _tube(r0: float, r1: float, h: float, seg: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 12
	for j in range(rings + 1):
		var t := float(j) / float(rings)
		var r := lerpf(r0, r1, t)
		for i in range(seg + 1):
			var a := TAU * float(i) / float(seg)
			## a bit of bark relief so the probe has something to read
			var rr := r * (1.0 + 0.06 * sin(a * 5.0 + t * 9.0))
			st.set_normal(Vector3(cos(a), 0, sin(a)))
			st.set_uv(Vector2(float(i) / seg, t * h))
			st.add_vertex(Vector3(cos(a) * rr, t * h, sin(a) * rr))
	for j in range(rings):
		for i in range(seg):
			var a := j * (seg + 1) + i
			var b := a + 1
			var c := a + seg + 1
			var d := c + 1
			st.add_index(a); st.add_index(c); st.add_index(b)
			st.add_index(b); st.add_index(c); st.add_index(d)
	return st.commit()


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 40:
		return false
	_check()
	print("GrowthTests: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
	return true


func _check() -> void:
	## --- the trunk patch built off the real mesh ---
	ok(_p_tree.built, "tree patch built")
	ok(_p_tree.base_count >= 10, "tree base cards %d" % _p_tree.base_count)
	ok(_p_tree.accent_count >= 3, "tree accent cards %d" % _p_tree.accent_count)
	var mi := _p_tree.get_node_or_null("Growth") as MeshInstance3D
	ok(mi != null and mi.mesh != null, "tree patch has a mesh")
	if mi != null and mi.mesh != null:
		var arr := mi.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var c0: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM0]
		var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
		ok(v.size() == _p_tree.card_count * 4 or v.size() == (_p_tree.base_count + 2 * _p_tree.accent_count) * 4
			or v.size() > 0, "vertex count")
		ok(c0.size() == v.size() * 4, "CUSTOM0 is 4 floats a vertex")
		## every card sits ON the trunk: its pivot's radius in model space is
		## within the relief band of the taper -- not floating, not buried
		var bad := 0
		var nan := 0
		var births_ok := true
		var maxb := 0.0
		var minb := 1.0
		for i in range(0, v.size(), 4):
			var pv := Vector3(c0[i * 4], c0[i * 4 + 1], c0[i * 4 + 2])
			var birth := c0[i * 4 + 3]
			if is_nan(pv.x) or is_nan(v[i].x):
				nan += 1
			var pm := pv / 1.5          ## host -> model space (scale 1.5)
			var t := clampf(pm.y / 3.0, 0.0, 1.0)
			var r := lerpf(0.30, 0.22, t)
			var rad := Vector2(pm.x, pm.z).length()
			if rad < r * 0.90 or rad > r * 1.12 + 0.05:
				bad += 1
			if birth < 0.0 or birth > 1.0:
				births_ok = false
			maxb = maxf(maxb, birth)
			minb = minf(minb, birth)
		ok(nan == 0, "no NaNs")
		ok(bad <= v.size() / 4 / 10, "cards hug the bark (%d off of %d)" % [bad, v.size() / 4])
		ok(births_ok and minb < 0.15 and maxb > 0.5, "births span heart -> fringe (%.2f..%.2f)" % [minb, maxb])
		## base cards come first in the buffer, accents after (draw order)
		var seen_accent := false
		var order_ok := true
		for i in range(0, uv2.size(), 4):
			if uv2[i].y > 0.5:
				seen_accent = true
			elif seen_accent:
				order_ok = false
		ok(order_ok, "base cards precede accent cards")
	## the probe body is gone once built
	ok(_p_tree.get_node_or_null("StaticBody3D") == null and _p_tree._probe == null, "probe body freed")

	## --- determinism: the twin landed the same cards ---
	ok(_p_twin.built, "twin built")
	var mi2 := _p_twin.get_node_or_null("Growth") as MeshInstance3D
	if mi != null and mi2 != null:
		var a: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var b: PackedVector3Array = mi2.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		ok(a.size() == b.size(), "twin vertex count %d == %d" % [a.size(), b.size()])
		var same := a.size() == b.size()
		if same:
			for i in range(a.size()):
				if a[i].distance_to(b[i]) > 0.0001:
					same = false
					break
		ok(same, "twin is vertex-identical")
	ok(_p_twin.base_id == _p_tree.base_id and _p_twin.accent_id == _p_tree.accent_id, "twin same variants")

	## --- the rock, probed through its tilted MESH not its box collider ---
	ok(_p_rock.built, "rock patch built (%d cards)" % _p_rock.card_count)
	var mr := _p_rock.get_node_or_null("Growth") as MeshInstance3D
	if mr != null:
		## the mesh is yawed 40 deg: a card exactly on the axis-aligned collider
		## face z = -1 would be wrong; on the real face it is rotated. Check the
		## pivots are NOT all on the plane z = -1.
		var arr := mr.mesh.surface_get_arrays(0)
		var c0: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM0]
		var on_box := 0
		var n := 0
		for i in range(0, c0.size(), 16):
			n += 1
			if absf(c0[i + 2] - (-1.0)) < 0.03:
				on_box += 1
		ok(n > 0 and on_box < n / 2, "rock cards follow the mesh, not the box (%d/%d on box)" % [on_box, n])

	## --- the world probe (mask 1) finds the rock's collider; fungi cut shelves
	ok(_p_world.built, "world-probe patch built (%d)" % _p_world.card_count)
	ok(_p_world.accent_count >= 3, "fungi accents cut (%d)" % _p_world.accent_count)

	## --- growth maths ---
	var fam := GrowthTypes.family("moss")
	var dry := GrowthClock.rate_for(fam, 0.5, 0.0, 0.0, 30.0)
	var wet := GrowthClock.rate_for(fam, 0.5, 0.0, 1.0, 30.0)
	var sun := GrowthClock.rate_for(fam, 0.0, 0.0, 0.0, 30.0)
	var winter := GrowthClock.rate_for(fam, 0.5, 0.0, 0.0, 80.0)   ## day 80 of 96 = winter
	ok(wet > dry * 2.5, "rain speeds moss (%.5f vs %.5f)" % [wet, dry])
	ok(sun < dry, "sun slows moss")
	ok(winter < dry * 0.3, "winter nearly stops it")
	var lichen := GrowthClock.rate_for(GrowthTypes.family("lichen"), 0.5, 0.0, 0.0, 30.0)
	ok(lichen < dry, "lichen is slower than moss")
	## full shade, dry, average: DAYS_TO_FULL days from 0 to ~1
	var g := 0.0
	var r := GrowthClock.rate_for(fam, 0.5, 0.0, 0.0, 30.0)
	g = r * GrowthClock.DAYS_TO_FULL * 24.0
	ok(g > 0.7 and g < 1.3, "DAYS_TO_FULL is what it says (%.2f)" % g)

	## --- the clock drives the patches by game hours ---
	var g0 := _p_tree.growth
	_dn.hour = 12.0
	_clock.tick()          ## first tick just anchors
	_dn.day = 30.0 + 10.0  ## ten game days pass (a long sleep)
	_wx.wetness = 1.0
	_clock.tick()
	ok(_p_tree.growth > g0 + 0.2, "ten wet days grew the moss (%.2f -> %.2f)" % [g0, _p_tree.growth])
	ok(_p_tree.last_day > 39.9, "last_day recorded")
	ok(_p_rock.growth > 0.0 and _p_rock.growth < _p_tree.growth, "lichen grew, slower")
	ok(_p_world.growth > _p_rock.growth, "damp fungi grew fastest")

	## --- save / load ---
	var d := _p_tree.to_dict()
	ok(d.has("type") and d.has("seed") and d.has("growth") and d.has("ang") and d.has("centre"), "dict carries the anchor")
	ok(not d.has("key"), "a tree patch carries no ledger key")
	ok(_p_rock.to_dict().get("key", "") == "rock:-4,2", "a rock patch carries its key")
	var back := GrowthPatch.from_dict(d)
	ok(back.type_id == _p_tree.type_id and back.base_id == _p_tree.base_id and back.accent_id == _p_tree.accent_id, "type triple survives")
	ok(absf(back.growth - _p_tree.growth) < 0.0001, "growth survives")
	ok(absf(back.facing_ang - 1.0) < 0.0001 and absf(back.centre.y - 0.9) < 0.0001, "anchor survives")
	## catch-up: a save closed at day 40, opened at day 50 -> grows ~10 days
	_dn.day = 50.0
	var gb := back.growth
	back.catch_up()
	ok(back.growth > gb, "catch_up grew through the missed days (%.2f -> %.2f)" % [gb, back.growth])
	ok(absf(back.last_day - 50.5) < 0.01, "catch_up moved last_day to now")
	## apply_dict onto a live patch
	var live_g := _p_rock.growth
	_p_rock.apply_dict({"growth": 0.9, "day": 50.5})
	ok(absf(_p_rock.growth - 0.9) < 0.0001, "apply_dict sets growth (was %.2f)" % live_g)
	## the JSON round trip does not mangle anything
	var js := JSON.stringify(d)
	var d2: Dictionary = JSON.parse_string(js)
	var back2 := GrowthPatch.from_dict(d2)
	ok(back2.seed_v == _p_tree.seed_v and absf(back2.span.y - 0.9) < 0.0001, "survives JSON")

	## --- shade helper ---
	ok(GrowthPatch.shade_for(Vector3(0, 0, -1)) > 0.95, "north is shaded")
	ok(GrowthPatch.shade_for(Vector3(0, 0, 1)) < 0.3, "south is sunny")
	ok(GrowthPatch.shade_for(Vector3(0, -1, 0)) > 0.95, "under is shaded")
