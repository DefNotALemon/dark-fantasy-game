import sys, os
root = sys.argv[1] if len(sys.argv) > 1 else "."
P = os.path.join(root, "tests/WoodCutTests.gd")
s = open(P, encoding="utf-8").read()
def once(old, new):
    global s
    assert s.count(old) == 1, old[:60]
    s = s.replace(old, new)
once('''			ok(untouched_moved == 0, "bark the axe did not touch keeps its normal (%d changed)" % untouched_moved)
			ok(v.size() == pristine.size(), "same vertices as the pristine trunk")''',
'''			ok(untouched_moved == 0, "bark the axe did not touch keeps its normal (%d changed)" % untouched_moved)
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
			continue''')
once('''	ok(felled and swings == 3, "an ancient pine goes over on the third swing (%d)" % swings)''',
     '''	ok(felled and swings == 3, "an ancient pine goes over on the third swing (%d)" % swings)
	## a felled tree's bites travel with the trunk (the carved mesh is adopted)
	ok(t.bites.size() >= 2, "bites stayed on the record to the end (%d)" % t.bites.size())''')
open(P, "w", encoding="utf-8").write(s)
print("patched tests", len(s))
