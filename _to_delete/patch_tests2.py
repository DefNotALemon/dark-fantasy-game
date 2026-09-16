import sys, os
root = sys.argv[1] if len(sys.argv) > 1 else "."
P = os.path.join(root, "tests/WoodCutTests.gd")
s = open(P, encoding="utf-8").read()

def once(old, new):
    global s
    assert s.count(old) == 1, old[:60]
    s = s.replace(old, new)

once('''	_test_grain()
''', '''	_test_grain()
	_test_rings()
''')

once('''func _test_audio() -> void:''', '''func _test_rings() -> void:
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
	ok(absf(c.x - 1.0) > 0.03, "(the D's own centroid is off by %.3f -- that was the bug)" % absf(c.x - 1.0))
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


func _test_audio() -> void:''')

# ---- side split, in _test_trunk: between the first bite and "buck it all the way down"
once('''	## buck it all the way down: the last bite takes the remainder as a log
	var guard := 0
	while is_instance_valid(_trunk) and not _trunk.chop_hit(Vector3(0, 0, 1)) and guard < 30:
		guard += 1
	ok(guard < 30, "bucks all the way down")
''', '''	## what is left falls back to the ground instead of hanging where it was propped
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
''')
once('''	ok(total >= 3, "a whole oak is several logs (%d)" % total)''',
     '''	ok(total >= 4, "a whole oak is several logs (%d)" % total)''')
open(P, "w", encoding="utf-8").write(s)
print("patched tests", len(s))
