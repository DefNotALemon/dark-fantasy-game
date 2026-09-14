extends SceneTree
## ===========================================================================
## WoodCutTests.gd -- cut faces, logs that lie where they were cut, nothing
## left floating, and the timber sound bus.
##
##   godot --headless --path . --script res://tests/WoodCutTests.gd
##
## Lemon 2026-09-14: "the logs should not look like mushrooms", "the bottom
## of a fallen tree should not be see through, it should be wood", "the trees
## should separate into logs from where they were, as tree lying on the
## ground", "chopping a fallen tree should not leave parts of the tree
## floating in the air", "when a tree is hit it plays a sound, different
## tools different sounds".
##
## Geometry is checked the way the stump was: with SurfaceTool.generate_normals
## as the oracle for which way a face renders (Godot's front faces are
## clockwise -- the rendered normal is -(b-a)x(c-a)). No renderer needed.
## ===========================================================================

var _pass := 0
var _fail := 0
const MIN_ASSERTIONS := 70
var _built := false
var _frames := 0
var _world: Node3D
var _trunk: FallenTrunk
var _tree_h := 0.0
var _branches_before := 0


func ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: %s" % what)


func _initialize() -> void:
	print("WoodCutTests")
	root.add_child(Wind.new())
	_test_tube()
	_test_slab()
	_test_lay_down()
	_test_cards()
	_test_grain()
	_test_rings()
	## the sound bus wants a live tree (is_inside_tree() is false during
	## _initialize), so it runs with the trunk on frame three


## The direction every triangle of `arr` renders with, as Godot sees it.
func _rendered_normals(arr: Array) -> Array:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var t := 0
	while t + 2 < idx.size():
		for k in range(3):
			st.add_vertex(v[idx[t + k]])
		t += 3
	st.generate_normals()
	var out: Array = st.commit_to_arrays()
	var n: PackedVector3Array = out[Mesh.ARRAY_NORMAL]
	var res: Array = []
	var i := 0
	while i + 2 < n.size():
		res.append(n[i])
		i += 3
	return res


func _test_tube() -> void:
	var arr := WoodCut.tube(0.30, 0.28, 2.0, 12, 5)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	ok(v.size() > 24 and idx.size() % 3 == 0, "tube: has vertices and whole triangles")
	var lo := INF
	var hi := -INF
	for p in v:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	ok(is_equal_approx(lo, 0.0) and is_equal_approx(hi, 2.0), "tube: runs 0..length up Y")
	var outward := true
	for i in range(v.size()):
		if n[i].dot(Vector3(v[i].x, 0, v[i].z).normalized()) < 0.9:
			outward = false
	ok(outward, "tube: stored normals point out")
	var faces_out := 0
	var faces_in := 0
	var rn := _rendered_normals(arr)
	var t := 0
	for k in range(rn.size()):
		var c := (v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0
		if (rn[k] as Vector3).dot(Vector3(c.x, 0, c.z).normalized()) > 0.0:
			faces_out += 1
		else:
			faces_in += 1
		t += 3
	ok(faces_in == 0 and faces_out > 0, "tube: every face RENDERS outward (%d out, %d in)" % [faces_out, faces_in])
	## the seam column is a true duplicate of column 0, so the loop welds
	var seam_ok := true
	var per := 13
	for i in range(0, v.size(), per):
		if v[i].distance_to(v[i + per - 1]) > 1e-5:
			seam_ok = false
	ok(seam_ok, "tube: UV seam column sits exactly on column 0")
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	ok(absf(uv[per - 1].x - TAU * 0.30) < 0.05, "tube: u runs the circumference in metres")


func _test_slab() -> void:
	var arr := WoodCut.tube(0.30, 0.30, 2.0, 12, 5)
	var cut := WoodCut.slab(arr, 0.5, 1.5, true, true)
	var wood: Array = cut["wood"]
	var caps: Array = cut["caps"]
	ok(not wood.is_empty(), "slab: wood survives")
	ok(caps.size() == 2, "slab: one cap per open end (got %d)" % caps.size())
	var v: PackedVector3Array = wood[Mesh.ARRAY_VERTEX]
	var inside := true
	for p in v:
		if p.y < 0.5 - 1e-5 or p.y > 1.5 + 1e-5:
			inside = false
	ok(inside, "slab: no wood vertex outside the slab")
	var on_lo := 0
	var on_hi := 0
	for p in v:
		if is_equal_approx(p.y, 0.5):
			on_lo += 1
		if is_equal_approx(p.y, 1.5):
			on_hi += 1
	ok(on_lo >= 12 and on_hi >= 12, "slab: the cut lands EXACTLY on the plane (%d/%d ring verts)" % [on_lo, on_hi])
	## attributes came along and stayed sane
	var n: PackedVector3Array = wood[Mesh.ARRAY_NORMAL]
	var tg: PackedFloat32Array = wood[Mesh.ARRAY_TANGENT]
	var col: PackedColorArray = wood[Mesh.ARRAY_COLOR]
	ok(n.size() == v.size() and tg.size() == v.size() * 4 and col.size() == v.size(),
		"slab: normal/tangent/colour arrays track the vertex count")
	var unit := true
	for nn in n:
		if absf(nn.length() - 1.0) > 1e-3:
			unit = false
	ok(unit, "slab: interpolated normals are unit length")
	## the wood still renders outward after the split
	var rn := _rendered_normals(wood)
	var idx: PackedInt32Array = wood[Mesh.ARRAY_INDEX]
	var bad := 0
	var t := 0
	for k in range(rn.size()):
		var c := (v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0
		if (rn[k] as Vector3).dot(Vector3(c.x, 0, c.z).normalized()) <= 0.0:
			bad += 1
		t += 3
	ok(bad == 0, "slab: split wood faces still render outward (%d wrong)" % bad)

	## caps: flat, on the plane, closed, facing out of the wood
	for ci in range(caps.size()):
		var cap: Array = caps[ci]
		var cv: PackedVector3Array = cap[Mesh.ARRAY_VERTEX]
		var cidx: PackedInt32Array = cap[Mesh.ARRAY_INDEX]
		var y := cv[0].y
		var flat := true
		for p in cv:
			if not is_equal_approx(p.y, y):
				flat = false
		ok(flat, "cap %d: flat" % ci)
		ok(is_equal_approx(y, 0.5) or is_equal_approx(y, 1.5), "cap %d: on a cut plane" % ci)
		var want := Vector3.UP if is_equal_approx(y, 1.5) else Vector3.DOWN
		var crn := _rendered_normals(cap)
		var wrong := 0
		for nn in crn:
			if (nn as Vector3).dot(want) < 0.99:
				wrong += 1
		ok(wrong == 0 and crn.size() > 0, "cap %d: every face renders %s (%d wrong of %d)"
			% [ci, "up" if want == Vector3.UP else "down", wrong, crn.size()])
		## area ~ pi r^2: the disc is closed, with no missing wedge at the seam
		var area := 0.0
		var tt := 0
		while tt + 2 < cidx.size():
			var a := cv[cidx[tt]]
			var b := cv[cidx[tt + 1]]
			var c := cv[cidx[tt + 2]]
			area += (b - a).cross(c - a).length() * 0.5
			tt += 3
		## a 12-gon is 0.955 of the circle; the knobbles move it a little
		ok(absf(area - PI * 0.09 * 0.955) < PI * 0.09 * 0.12,
			"cap %d: area %.3f is a closed disc of r=0.3 (%.3f)" % [ci, area, PI * 0.09 * 0.955])
		## the rim: one point per ring edge crossed plus one per quad diagonal,
		## welded so the seam column does not appear twice
		var dup := 0
		for i in range(cv.size()):
			for j in range(i + 1, cv.size()):
				if cv[i].distance_to(cv[j]) < WoodCut.WELD:
					dup += 1
		ok(dup == 0 and cv.size() <= 25, "cap %d: seam welded -- %d rim points, %d duplicates" % [ci, cv.size(), dup])
		var uv: PackedVector2Array = cap[Mesh.ARRAY_TEX_UV]
		## the rings are sized to the fitted trunk; bark plates stand a little
		## proud of it and sample the clamped edge of the grain sheet
		var uv_ok := true
		for u in uv:
			if u.x < -0.1 or u.x > 1.1 or u.y < -0.1 or u.y > 1.1:
				uv_ok = false
		ok(uv_ok, "cap %d: grain UVs on the sheet (bark relief may sit just past its edge)" % ci)

	## open ends stay open, and a slab that misses the wood is empty
	var open := WoodCut.slab(arr, -INF, 1.0, false, true)
	ok((open["caps"] as Array).size() == 1, "slab: an uncapped end gets no cap")
	var none := WoodCut.slab(arr, 5.0, 6.0, true, true)
	ok((none["wood"] as Array).is_empty() and (none["caps"] as Array).is_empty(),
		"slab: nothing in the slab -> nothing out")
	## whole-tube slab with a hair of margin still caps both ends
	var whole := WoodCut.slab(arr, 0.002, 1.998, true, true)
	ok((whole["caps"] as Array).size() == 2, "slab: a whole tube trimmed by 2 mm caps both ends")


func _test_lay_down() -> void:
	var arr := WoodCut.tube(0.25, 0.25, 2.0, 8, 3)
	var laid := WoodCut.lay_down(arr, 0.0, 1.0, 0.0, 1.0, -0.05)
	var v: PackedVector3Array = laid["arrays"][Mesh.ARRAY_VERTEX]
	var min_y := INF
	var min_x := INF
	var max_x := -INF
	for p in v:
		min_y = minf(min_y, p.y)
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
	ok(is_equal_approx(min_y, -0.05), "lay_down: underside on the asked floor (%.3f)" % min_y)
	ok(absf((max_x - min_x) - 2.0) < 1e-4, "lay_down: the length now runs along X")
	ok(absf(max_x + min_x) < 1e-4, "lay_down: centred on the section's middle")
	## it is a rotation, so the faces still render outward from the new axis
	var rn := _rendered_normals(laid["arrays"])
	var idx: PackedInt32Array = laid["arrays"][Mesh.ARRAY_INDEX]
	var bad := 0
	var t := 0
	for k in range(rn.size()):
		var c := (v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0
		c.y -= float(laid["lift"])
		if (rn[k] as Vector3).dot(Vector3(0, c.y, c.z).normalized()) <= 0.0:
			bad += 1
		t += 3
	ok(bad == 0, "lay_down: winding untouched, faces render outward (%d wrong)" % bad)
	var n: PackedVector3Array = laid["arrays"][Mesh.ARRAY_NORMAL]
	var along := 0
	for nn in n:
		if absf(nn.x) > 0.01:
			along += 1
	ok(along == 0, "lay_down: normals rotated with the wood (none point along the log)")

	## the whole log a DroppedItem carries
	var mi := WoodCut.log_instance("oak", 0.22, 1.05, Color(0.3, 0.2, 0.1), 9)
	ok(mi.mesh != null and mi.mesh.get_surface_count() == 3, "log_instance: bark + two faces of grain (%d surfaces)"
		% (mi.mesh.get_surface_count() if mi.mesh else 0))
	var aabb := mi.mesh.get_aabb()
	ok(absf(aabb.size.x - 1.05) < 0.01, "log_instance: %.2f m long along X" % aabb.size.x)
	ok(aabb.size.y < 0.5 and aabb.size.y > 0.38, "log_instance: as tall as it is thick (%.2f) -- no mushroom cap" % aabb.size.y)
	ok(aabb.position.y > -0.01 and aabb.position.y < 0.01, "log_instance: underside on y = 0")
	## the faces are no wider than the bark: the mushroom test
	var bark_v: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var bark_r := 0.0
	for p in bark_v:
		bark_r = maxf(bark_r, Vector2(p.y - 0.22, p.z).length())
	var cap_r := 0.0
	for si in range(1, 3):
		for p in (mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			cap_r = maxf(cap_r, Vector2(p.y - 0.22, p.z).length())
	ok(cap_r <= bark_r + 1e-4, "log_instance: end grain never stands proud of the bark (%.3f vs %.3f)" % [cap_r, bark_r])
	ok(mi.get_surface_override_material(1) is StandardMaterial3D
		and (mi.get_surface_override_material(1) as StandardMaterial3D).albedo_texture != null,
		"log_instance: the faces wear the end-grain texture")
	ok(mi.get_surface_override_material(0) is ShaderMaterial, "log_instance: oak wears the oak bark shader")
	var plain := WoodCut.log_instance("", 0.085, 0.4, Color(0.3, 0.2, 0.1), 2)
	ok(plain.get_surface_override_material(0) is StandardMaterial3D, "log_instance: no species -> plain bark colour")
	mi.free()
	plain.free()


func _test_cards() -> void:
	var arr := WoodCut.tube(0.2, 0.2, 2.0, 6, 1)
	var kept := WoodCut.cards(arr, -INF, 1.0)
	var all_idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var kidx: PackedInt32Array = kept[Mesh.ARRAY_INDEX]
	ok(kidx.size() > 0 and kidx.size() < all_idx.size(), "cards: keeps whole triangles by centre")
	var v: PackedVector3Array = kept[Mesh.ARRAY_VERTEX]
	var t := 0
	var high := 0
	while t + 2 < kidx.size():
		if (v[kidx[t]].y + v[kidx[t + 1]].y + v[kidx[t + 2]].y) / 3.0 > 1.0:
			high += 1
		t += 3
	ok(high == 0, "cards: nothing centred beyond the line survives")
	ok(WoodCut.cards(arr, 5.0, 6.0).is_empty(), "cards: nothing in range -> []")


func _test_grain() -> void:
	var img := WoodCut.grain_image(64, 3)
	ok(img.get_width() == 64, "grain: image built")
	var tones := {}
	var dark := 0
	for y in range(64):
		for x in range(64):
			var c := img.get_pixel(x, y)
			tones[snappedf(c.r, 0.01)] = true
			if c.r < 0.6:
				dark += 1
	ok(tones.size() >= 4 and tones.size() <= 16, "grain: a posterised palette (%d tones)" % tones.size())
	ok(dark > 40, "grain: has ring lines and checks (%d dark px)" % dark)
	## rings: brightness along a radius alternates
	var flips := 0
	var last := img.get_pixel(32, 32).r > 0.8
	for x in range(33, 63):
		var b := img.get_pixel(x, 32).r > 0.8
		if b != last:
			flips += 1
		last = b
	ok(flips >= 6, "grain: growth rings out from the pith (%d bands crossed)" % flips)
	var m := WoodCut.grain_material("birch")
	ok(m == WoodCut.grain_material("birch"), "grain: one material per species, cached")
	ok(WoodCut.grain_material("birch") != WoodCut.grain_material("oak"), "grain: species tint differ")
	ok(m.albedo_color.r > WoodCut.grain_material("oak").albedo_color.r, "grain: birch pale, oak dark")


func _test_rings() -> void:
	## the rings centre on the tree, not on the D the notch leaves
	var ring := PackedVector3Array()
	for k in range(24):
		var a := TAU * float(k) / 24.0
		var r := 0.30
		## a wedge taken out of the +X side, down to a third of the radius
		if absf(wrapf(a, -PI, PI)) < 0.9:
			r = 0.30 * (0.35 + 0.65 * absf(wrapf(a, -PI, PI)) / 0.9)
		ring.append(Vector3(1.0 + r * cos(a), 2.0, -0.5 + r * sin(a)))
	var fit := WoodCut.fit_circle(ring)
	ok(absf(float(fit[0]) - 1.0) < 0.015 and absf(float(fit[1]) + 0.5) < 0.015,
		"fit_circle: a notched rim still centres on the trunk (%.3f, %.3f)" % [float(fit[0]), float(fit[1])])
	ok(absf(float(fit[2]) - 0.30) < 0.012, "fit_circle: and finds the trunk's radius (%.3f)" % float(fit[2]))
	var c := Vector3.ZERO
	for p in ring:
		c += p
	c /= float(ring.size())
	ok(absf(c.x - 1.0) > 0.015, "(the D's own centroid is off by %.3f -- that was the bug)" % absf(c.x - 1.0))
	## and the cap built on that rim puts the pith there: the far-side point
	## (angle pi, x = 0.7) lands at u ~ 0.5 - 0.3/0.612, the notch floor closer in
	var cap := WoodCut._cap(ring, 2.0, true)
	var cv: PackedVector3Array = cap[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = cap[Mesh.ARRAY_TEX_UV]
	var far_u := 1.0
	var floor_u := 0.0
	for i in range(cv.size()):
		if absf(cv[i].x - 0.7) < 0.01:
			far_u = uv[i].x
		if absf(cv[i].x - 1.105) < 0.01:
			floor_u = uv[i].x
	ok(absf(far_u - (0.5 - 0.3 / 0.612)) < 0.03, "cap: bark side of the D sits on the ring's rim (u %.3f)" % far_u)
	ok(floor_u > 0.6 and floor_u < 0.72, "cap: the notch floor sits a third out from the pith (u %.3f)" % floor_u)
	var whole := PackedVector3Array()
	for k in range(16):
		var a := TAU * float(k) / 16.0
		whole.append(Vector3(0.25 * cos(a), 0.0, 0.25 * sin(a)))
	var f2 := WoodCut.fit_circle(whole)
	ok(absf(float(f2[0])) < 1e-4 and absf(float(f2[1])) < 1e-4 and absf(float(f2[2]) - 0.25) < 1e-4,
		"fit_circle: a whole ring is itself")


func _test_audio() -> void:
	var mf := "res://assets/audio/wood/manifest.json"
	ok(FileAccess.file_exists(mf), "wood manifest exists (run tools/woodsounds.py)")
	var wa := WoodAudio.new()
	root.add_child(wa)
	wa.boot()
	wa.boot()
	ok(wa.manifest.size() >= 19, "manifest parsed (%d sounds)" % wa.manifest.size())
	ok(wa._voices.size() == WoodAudio.VOICES and wa._big.size() == WoodAudio.BIG_VOICES, "boot() is idempotent")
	var complete := true
	for fam in WoodAudio.STRIKE_VARIANTS:
		for i in range(int(WoodAudio.STRIKE_VARIANTS[fam])):
			if not wa.has_sound("%s_%d" % [fam, i + 1]):
				complete = false
				print("    missing %s_%d" % [fam, i + 1])
	for k in ["creak_1", "creak_2", "crash_1", "crash_2", "thud_1", "thud_2", "limb_1", "limb_2"]:
		if not wa.has_sound(k):
			complete = false
			print("    missing " + k)
	ok(complete, "every tool has its variants; creak/crash/thud/limb present")
	## different tools, different families
	ok(WoodAudio.key_for("axe") == "axe" and WoodAudio.key_for("sword") == "sword"
		and WoodAudio.key_for("pickaxe") == "pick" and WoodAudio.key_for("arrow") == "arrow",
		"the four tools land on four different sample families")
	ok(WoodAudio.key_for("fist") == "axe", "an unknown tool still makes a sound")
	ok(WoodAudio.pitch_for(0.05) > WoodAudio.pitch_for(0.3) and WoodAudio.pitch_for(0.3) > WoodAudio.pitch_for(0.9),
		"thin wood rings higher than fat wood")
	## the streams load and play on the dummy driver
	var played := true
	for fam in ["axe", "sword", "pick", "arrow"]:
		WoodAudio.strike(wa, Vector3.ZERO, fam, 1.0, null)
		if wa._last_key.get_slice("_", 0) != fam:
			played = false
	ok(played, "strike() picks the tool's family (last: %s)" % wa._last_key)
	ok(wa._hits == 4, "four strikes counted")
	var busy_before: int = int(wa.report()["busy"])
	ok(int(busy_before) > 0 or wa._dropped == 0, "voices are actually playing or nothing was dropped (dropped %d, exists %s, stream %s)"
		% [wa._dropped, str(ResourceLoader.exists("res://assets/audio/wood/axe_1.wav")), str(wa._stream("axe_1"))])
	WoodAudio.creak(wa, Vector3.ZERO, 8.0)
	ok(wa._last_key == "creak", "creak() is the big-voice groan")
	WoodAudio.crash(wa, Vector3.ZERO, 4.0)
	ok(wa._last_key == "crash", "crash() lands")
	WoodAudio.thud(wa, Vector3.ZERO, 0.3)
	WoodAudio.limb(wa, Vector3.ZERO)
	ok(wa._last_key == "limb", "thud/limb go through")
	## nothing explodes with no bus in reach
	var orphan := Node.new()
	WoodAudio.strike(orphan, Vector3.ZERO, "axe", 1.0, null)
	orphan.free()
	ok(true, "strike() from a node outside the tree is a no-op")


## ---- the fallen tree: built on frame one so _ready() runs ------------------

func _process(_delta: float) -> bool:
	_frames += 1
	if not _built:
		_built = true
		_build_tree()
		return false
	if _frames < 3:
		return false
	_test_audio()
	_test_three_hits()
	_test_sword_limbs()
	_test_trunk()
	_finish()
	return true


func _build_tree() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	var t := TreeV2.new()
	t.species = "oak"
	t.stage = 2
	t.tree_seed = 4242
	_world.add_child(t)
	_tree_h = t.trunk_height()
	while not t.felled:
		t.chop_hit(Vector3(0, 0, 1))
	for c in _world.get_children():
		if c is FallenTrunk:
			_trunk = c
	## no physics in this suite: it is down, by fiat
	if _trunk != null:
		_trunk.settled = true
		_trunk.freeze = true


func _all_branch_meshes() -> Array:
	var out: Array = []
	for tw in _trunk._twigs:
		out.append(tw["mesh"])
	return out


func _log_items() -> Array:
	var out: Array = []
	for c in _world.get_children():
		var di := c as DroppedItem
		if di != null and String(di.item.get("name", "")) == "Log":
			out.append(di)
	return out


func _test_three_hits() -> void:
	## three swings fell any tree; a limb is one; the notch is bark OR wood
	ok(TreeBranch.MAX_HP == 1, "a limb is one cut (MAX_HP %d)" % TreeBranch.MAX_HP)
	for st in range(1, 5):
		ok(TreeV2.TRUNK_CHOPS[st] == 3, "stage %d trunk is three swings (%d)" % [st, TreeV2.TRUNK_CHOPS[st]])
	var t := TreeV2.new()
	t.species = "pine"
	t.stage = 3
	t.tree_seed = 5
	t.position = Vector3(120, 0, 0)
	_world.add_child(t)
	var swings := 0
	var felled := false
	while not felled and swings < 10:
		if swings == 0:
			## the first bite: look at the colours and normals it left
			t.chop_hit(Vector3(0, 0, 1))
			swings += 1
			var arr := t._trunk.mesh.surface_get_arrays(0)
			var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var pristine: PackedVector3Array = t._trunk_arrays[Mesh.ARRAY_NORMAL]
			var bare := 0
			var between := 0
			var turned := 0
			var untouched_moved := 0
			for i in range(cols.size()):
				if cols[i].r < 0.001:
					bare += 1
					## a cut vertex's normal was rebuilt from the carved faces
					## (the unwelded rim copies past the pristine count have no twin)
					if i < pristine.size() and n[i].angle_to(pristine[i]) > 0.03:
						turned += 1
				else:
					if cols[i].r < 0.999:
						between += 1
					## (surface_get_arrays hands back octahedral-compressed normals,
					## so "unchanged" is within a degree)
					if n[i].angle_to(pristine[i]) > 0.02:
						untouched_moved += 1
			ok(bare > 0, "the first bite bares wood (%d verts)" % bare)
			ok(between == 0, "and nothing is half-bark: every vertex is bark OR cut (%d in between)" % between)
			ok(turned > 0, "cut vertices are lit as a cut: normals rebuilt (%d of %d turned)" % [turned, bare])
			ok(untouched_moved == 0, "bark the axe did not touch keeps its normal (%d changed)" % untouched_moved)
			## UNWELDED: no triangle is half bark, half wood -- a slanted face is
			## all wood, a flat face is all bark
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var mixed := 0
			var wood_faces := 0
			var tt := 0
			while tt + 2 < idx.size():
				var ba := cols[idx[tt]].r < 0.5
				var bb := cols[idx[tt + 1]].r < 0.5
				var bc := cols[idx[tt + 2]].r < 0.5
				if ba != bb or bb != bc:
					mixed += 1
				elif ba:
					wood_faces += 1
				tt += 3
			ok(mixed == 0, "no triangle is half bark and half wood (%d mixed)" % mixed)
			ok(wood_faces > 0, "%d faces are wood all over" % wood_faces)
			ok(v.size() > pristine.size(), "the cut's rim was unwelded (%d -> %d verts)" % [pristine.size(), v.size()])
			ok(t.bites.size() == 1, "the bite was recorded (%d)" % t.bites.size())
			## a second bite somewhere ELSE strips bark there too
			var aim2: Vector3 = t.global_position + Vector3(0.35, 2.6, 0.0)
			t.chop_hit(Vector3(0, 0, 1), aim2)
			swings += 1
			if t.last_result == "trunk":
				ok(t.bites.size() == 2, "every bite is remembered where it landed (%d)" % t.bites.size())
				var a2 := t._trunk.mesh.surface_get_arrays(0)
				var c2: PackedColorArray = a2[Mesh.ARRAY_COLOR]
				var v2: PackedVector3Array = a2[Mesh.ARRAY_VERTEX]
				var lp: Vector3 = t._trunk.to_local(aim2)
				var near := 0
				var near_bare := 0
				for i in range(v2.size()):
					if absf(v2[i].y - lp.y) < 0.25 and Vector2(v2[i].x - lp.x, v2[i].z - lp.z).length() < 0.45:
						near += 1
						if c2[i].r < 0.5:
							near_bare += 1
				ok(near_bare > 0, "the second bite stripped bark where it hit, away from the notch (%d of %d verts near it)" % [near_bare, near])
				var d := t.save_dict()
				ok((d.get("bites", []) as Array).size() == 2, "bites are saved")
			else:
				ok(true, "(second bite took a limb instead: %s)" % t.last_result)
			felled = t.felled
			continue
			felled = t.felled
			continue
		felled = t.chop_hit(Vector3(0, 0, 1))
		swings += 1
	ok(felled and swings == 3, "an ancient pine goes over on the third swing (%d)" % swings)
	## a felled tree's bites travel with the trunk (the carved mesh is adopted)
	ok(t.bites.size() >= 2, "bites stayed on the record to the end (%d)" % t.bites.size())


func _count_sticks() -> int:
	var n := 0
	for c in _world.get_children():
		var di := c as DroppedItem
		if di != null and String(di.item.get("name", "")) == "Stick":
			n += 1
	return n


func _test_sword_limbs() -> void:
	## the blade takes the limb its sight-line crosses -- standing or downed
	var t := TreeV2.new()
	t.species = "maple"
	t.stage = 2
	t.tree_seed = 99
	t.position = Vector3(60, 0, 0)
	_world.add_child(t)
	var tb: TreeBranch = null
	for b in t._branches:
		if (b as TreeBranch).mesh != null:
			tb = b
			break
	ok(tb != null, "a standing maple has limbs to lop")
	if tb != null:
		var box: AABB = tb.mesh.global_transform * tb.mesh.mesh.get_aabb()
		var target := box.get_center()
		var from := target + Vector3(3.0, -0.5, 0.0)
		var dir := (target - from).normalized()
		var r: Array = t.branch_on_ray(from, dir, 8.0)
		ok(not r.is_empty(), "branch_on_ray: a sight-line through a limb finds one")
		ok(r.is_empty() or (r[1] as Vector3).distance_to(from) <= 8.0, "...within reach")
		ok(t.branch_on_ray(from, -dir, 8.0).is_empty(), "branch_on_ray: pointed away, nothing")
		ok(t.branch_on_ray(from, dir, 0.5).is_empty(), "branch_on_ray: out of reach, nothing")
		if not r.is_empty():
			var limb := r[0] as TreeBranch
			var sticks0 := _count_sticks()
			var off := false
			var swings := 0
			while not off and swings < 5:
				off = limb.take_hit(1)
				swings += 1
			ok(off and swings == 1, "ONE sword cut takes a standing limb (%d)" % swings)
			ok(limb.gone and _count_sticks() > sticks0, "and it is gone, with sticks on the ground (+%d)"
				% (_count_sticks() - sticks0))
			ok(t.branch_on_ray(from, dir, 8.0).is_empty() or (t.branch_on_ray(from, dir, 8.0)[0] as TreeBranch) != limb,
				"a lopped limb is never found again")
	## the same on the felled oak
	var vis := 0
	var pick: Dictionary = {}
	for tw in _trunk._twigs:
		if (tw["mesh"] as MeshInstance3D).visible:
			vis += 1
			if pick.is_empty():
				pick = tw
	ok(not pick.is_empty(), "the downed oak still carries branches")
	if not pick.is_empty():
		var mi := pick["mesh"] as MeshInstance3D
		var box2: AABB = mi.global_transform * mi.mesh.get_aabb()
		var target2 := box2.get_center()
		var from2 := target2 + Vector3(0.0, 2.5, 2.5)
		var dir2 := (target2 - from2).normalized()
		var r2: Array = _trunk.branch_on_ray(from2, dir2, 8.0)
		ok(not r2.is_empty(), "FallenTrunk.branch_on_ray finds a branch on the downed tree")
		if not r2.is_empty():
			var sticks1 := _count_sticks()
			var n := _trunk.lop_branch(r2[0] as Dictionary, r2[1] as Vector3)
			ok(n >= 1 and _count_sticks() == sticks1 + n, "lop_branch: %d stick(s) on the ground" % n)
			ok(not ((r2[0] as Dictionary)["mesh"] as MeshInstance3D).visible, "the branch is gone from the log")
			var vis2 := 0
			for tw in _trunk._twigs:
				if (tw["mesh"] as MeshInstance3D).visible:
					vis2 += 1
			ok(vis2 == vis - 1, "and out of the trunk's books (%d -> %d)" % [vis, vis2])
			ok(_trunk.lop_branch(r2[0] as Dictionary, r2[1] as Vector3) == 0, "lopping it twice gives nothing")
	t.queue_free()


func _test_trunk() -> void:
	ok(_trunk != null, "a felled oak hands over a FallenTrunk")
	if _trunk == null:
		return
	ok(_trunk.clip_below > 0.0, "it broke on the notch (clip_below %.2f)" % _trunk.clip_below)
	_trunk._cache_trunk_mesh()
	ok(_trunk._trunk_mi != null, "it adopted the tree's own trunk mesh")
	if _trunk._trunk_mi == null:
		return
	## THE BOTTOM IS WOOD: a cap surface exists on the butt, at the break line
	var kinds: Array = _trunk._trunk_kind
	ok(kinds.has("cap"), "the butt was capped with end grain (kinds %s)" % str(kinds))
	ok(kinds[0] == "wood", "surface 0 is still the bark tube")
	var ms: float = _trunk._model.scale.y
	var floor_y: float = _trunk.clip_below / ms
	var cap_on_floor := false
	var wood_under := 0
	for si in range(kinds.size()):
		var v: PackedVector3Array = _trunk._trunk_pristine[si][Mesh.ARRAY_VERTEX]
		if kinds[si] == "cap":
			cap_on_floor = cap_on_floor or is_equal_approx(v[0].y, floor_y)
		elif kinds[si] == "wood":
			for p in v:
				if p.y < floor_y - 1e-4:
					wood_under += 1
	ok(cap_on_floor, "the cap sits exactly on the break line")
	ok(wood_under == 0, "no stump wood left in the log's mesh")
	var mesh: ArrayMesh = _trunk._trunk_mi.mesh
	ok(mesh.get_surface_count() >= 2, "the drawn mesh carries the cap (%d surfaces)" % mesh.get_surface_count())
	var grain_used := false
	for si in range(mesh.get_surface_count()):
		if _trunk._trunk_mi.get_surface_override_material(si) == WoodCut.grain_material("oak"):
			grain_used = true
	ok(grain_used, "and the cap wears oak end grain")

	## limbs rooted below the break stayed with the stump
	var floating := 0
	for tw in _trunk._twigs:
		var mi := tw["mesh"] as MeshInstance3D
		if float(tw["base_y"]) < floor_y and mi.visible:
			floating += 1
	ok(floating == 0, "no branch rooted in the stump's wood came along (%d did)" % floating)
	_branches_before = 0
	for mi in _all_branch_meshes():
		if (mi as MeshInstance3D).visible:
			_branches_before += 1
	ok(_branches_before > 0, "%d branches ride along on the trunk" % _branches_before)

	## ---- BUCK IT: the log is that piece, lying where it was ---------------
	var len_before: float = _trunk.trunk_len
	var xf_before: Transform3D = _trunk.global_transform * _trunk._model.transform
	var hi := (len_before + _trunk.clip_below) / ms
	var lo := hi - FallenTrunk.BUCK_LENGTH / ms
	var centre_before: Vector3 = xf_before * Vector3(0, (lo + hi) * 0.5, 0)
	var logs0 := _log_items().size()
	var done: bool = _trunk.chop_hit(Vector3(0, 0, 1))
	ok(not done, "first bite does not finish a %.1f m trunk" % len_before)
	var logs := _log_items()
	ok(logs.size() == logs0 + 1, "one log came off")
	if logs.size() > logs0:
		var lg: DroppedItem = logs[logs.size() - 1]
		ok(lg.keep_yaw and not lg.tumble, "a bucked log lies along the trunk, no tumbling")
		ok(lg.log_r > 0.05, "it knows its own radius (%.2f)" % lg.log_r)
		ok(String(lg.item.get("species", "")) == "oak" and float(lg.item.get("log_len", 0.0)) > 1.9,
			"the item remembers species and size for the pack")
		var lmi: MeshInstance3D = null
		for c in lg.get_children():
			if c is MeshInstance3D:
				lmi = c
		ok(lmi != null and lmi.mesh != null, "the log carries a mesh")
		if lmi != null and lmi.mesh != null:
			var aabb := lmi.mesh.get_aabb()
			ok(absf(aabb.size.x - FallenTrunk.BUCK_LENGTH) < 0.05,
				"the log is the %.1f m section (%.2f along X)" % [FallenTrunk.BUCK_LENGTH, aabb.size.x])
			ok(lmi.mesh.get_surface_count() >= 3, "bark plus a face of grain at each end (%d surfaces)"
				% lmi.mesh.get_surface_count())
			ok(lmi.get_surface_override_material(0) is ShaderMaterial, "the log wears the tree's own bark")
			var world_centre: Vector3 = lg.global_transform * Vector3(0, float(aabb.position.y) + aabb.size.y * 0.5, 0)
			var drift := world_centre.distance_to(centre_before)
			ok(drift < 0.6, "and it lies WHERE THAT PIECE WAS (%.2f m from the section centre)" % drift)
			## its +X is the trunk's axis
			var ax: Vector3 = lg.global_transform.basis.x
			var trunk_axis: Vector3 = _trunk.global_transform.basis.y.normalized()
			ok(absf(ax.dot(trunk_axis)) > 0.98, "along the trunk's line (dot %.2f)" % absf(ax.dot(trunk_axis)))
	## the trunk that is left: shorter, capped on the new face, nothing floating
	ok(_trunk.trunk_len < len_before - 1.0, "the trunk got shorter")
	var m2: ArrayMesh = _trunk._trunk_mi.mesh
	var new_limit := (_trunk.trunk_len + _trunk.clip_below) / ms
	var cap_on_cut := false
	var above := 0
	for si in range(m2.get_surface_count()):
		var v: PackedVector3Array = m2.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
		if _trunk._trunk_mi.get_surface_override_material(si) == WoodCut.grain_material("oak"):
			for p in v:
				if is_equal_approx(p.y, new_limit):
					cap_on_cut = true
		for p in v:
			if p.y > new_limit + 1e-4:
				above += 1
	ok(cap_on_cut, "the fresh cut is capped with grain at the new end")
	ok(above == 0, "no wood beyond the cut (%d verts)" % above)
	var left_floating := 0
	var visible_now := 0
	for tw in _trunk._twigs:
		var mi := tw["mesh"] as MeshInstance3D
		if mi.visible:
			visible_now += 1
			if float(tw["base_y"]) > new_limit:
				left_floating += 1
	ok(left_floating == 0, "NO BRANCH LEFT FLOATING beyond the cut (%d were)" % left_floating)
	ok(visible_now < _branches_before, "branches on the bucked section went with it (%d -> %d)"
		% [_branches_before, visible_now])

	## what is left falls back to the ground instead of hanging where it was propped
	ok(not _trunk.freeze and _trunk._resettle and _trunk.settled,
		"after a bite the trunk is let go to fall again, still settled (buckable)")

	## ---- SPLIT WHERE THE AXE LANDS: a bite a third of the way up from the
	## butt takes the top two thirds off as a trunk of its own ----------------
	var len2: float = _trunk.trunk_len
	var trunks_before := 0
	for c in _world.get_children():
		if c is FallenTrunk:
			trunks_before += 1
	var vis_before := 0
	for tw in _trunk._twigs:
		if (tw["mesh"] as MeshInstance3D).visible:
			vis_before += 1
	var aim: Vector3 = _trunk.to_global(Vector3(0.2, _trunk._base + len2 * 0.3, 0))
	var butt_top_before: Vector3 = _trunk.to_global(Vector3(0, _trunk._base + FallenTrunk.BUCK_LENGTH * 0.75, 0))
	var clip_before: float = _trunk.clip_below
	var done2: bool = _trunk.chop_hit(Vector3(0, 0, 1), aim)
	ok(not done2, "a side bite does not finish the trunk")
	ok(absf(_trunk.trunk_len - FallenTrunk.BUCK_LENGTH * 0.75) < 0.01,
		"the butt side keeps what is below the cut, clamped to a stump's worth (%.2f m)" % _trunk.trunk_len)
	var piece: FallenTrunk = null
	var trunks_now := 0
	for c in _world.get_children():
		if c is FallenTrunk:
			trunks_now += 1
			if c != _trunk:
				piece = c
	ok(trunks_now == trunks_before + 1 and piece != null, "the top side is a NEW trunk lying there, not a log item")
	if piece != null:
		ok(piece._split and piece.settled and not piece.freeze and piece._resettle,
			"it starts down, buckable, and falling onto whatever is under it")
		ok(absf(piece.trunk_len - (len2 - FallenTrunk.BUCK_LENGTH * 0.75)) < 0.01,
			"it is the rest of the wood (%.2f m)" % piece.trunk_len)
		ok(absf(piece.clip_below - (clip_before + FallenTrunk.BUCK_LENGTH * 0.75)) < 0.01,
			"it knows how much tree is below its foot (%.2f)" % piece.clip_below)
		var butt_now: Vector3 = piece.to_global(Vector3(0, piece._base, 0))
		ok(butt_now.distance_to(butt_top_before) < 0.02,
			"its foot is exactly on the cut line (%.3f m off)" % butt_now.distance_to(butt_top_before))
		ok(piece.global_transform.basis.y.dot(_trunk.global_transform.basis.y) > 0.999,
			"and it lies along the same line")
		piece._cache_trunk_mesh()
		ok(piece._trunk_kind.size() >= 2 and piece._trunk_kind[0] == "wood" and piece._trunk_kind.has("cap"),
			"its mesh is bark with a face of grain on the cut (%s)" % str(piece._trunk_kind))
		var pms: float = piece._model.scale.y
		var pfloor: float = piece.clip_below / pms
		var under := 0
		var cap_at_foot := false
		for si in range(piece._trunk_kind.size()):
			var pv: PackedVector3Array = piece._trunk_pristine[si][Mesh.ARRAY_VERTEX]
			for p in pv:
				if p.y < pfloor - 1e-4:
					under += 1
			if piece._trunk_kind[si] == "cap" and is_equal_approx(pv[0].y, pfloor):
				cap_at_foot = true
		ok(under == 0 and cap_at_foot, "the grain sits on its foot and no wood is below it (%d verts under)" % under)
		var vis_a := 0
		for tw in _trunk._twigs:
			if (tw["mesh"] as MeshInstance3D).visible:
				vis_a += 1
		var vis_b := 0
		var stray := 0
		for tw in piece._twigs:
			var bm := tw["mesh"] as MeshInstance3D
			if bm.visible:
				vis_b += 1
			if float(tw["base_y"]) < pfloor - 1e-4:
				stray += 1
		ok(vis_b > 0 and vis_a + vis_b == vis_before,
			"the branches went with the wood they grew on (%d + %d = %d)" % [vis_a, vis_b, vis_before])
		ok(stray == 0, "none of them is rooted below the piece's foot")
		var pguard := 0
		while is_instance_valid(piece) and not piece.chop_hit(Vector3(0, 0, 1)) and pguard < 30:
			pguard += 1
		ok(pguard < 30, "the split-off trunk bucks all the way down too (%d bites)" % pguard)

	## buck it all the way down: the last bite takes the remainder as a log
	var guard := 0
	while is_instance_valid(_trunk) and not _trunk.chop_hit(Vector3(0, 0, 1)) and guard < 30:
		guard += 1
	ok(guard < 30, "bucks all the way down")
	var total := _log_items().size()
	ok(total >= 4, "a whole oak is several logs (%d)" % total)
	var short_ok := true
	for lg in _log_items():
		if float((lg as DroppedItem).item.get("log_len", 0.0)) < FallenTrunk.BUCK_LENGTH * 0.5 - 0.01:
			short_ok = false
	ok(short_ok, "no stub logs: the last bite took what was left as one piece")


func _finish() -> void:
	print("WoodCutTests: %d passed, %d failed" % [_pass, _fail])
	if _pass + _fail < MIN_ASSERTIONS:
		print("  LOST A SECTION: only %d assertions ran (floor %d)" % [_pass + _fail, MIN_ASSERTIONS])
		_fail += 1
	quit(1 if _fail > 0 else 0)
