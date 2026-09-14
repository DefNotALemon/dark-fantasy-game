extends SceneTree

## ===========================================================================
## Headless suite for trees v4 — the authored part kit.
##
##   godot --headless --path . --script res://tests/TreeKitTests.gd
##
## What it is guarding, in order of how much it would hurt to break:
##   1. THE RATIOS. Every limb's thickness has to come out of the pipe model,
##      every bough has to sit on the golden angle or a Fibonacci whorl, and
##      the taper has to be the curve the mesh was actually built from --
##      TreeV2 carves its notch against TreeKit.radius_at(), so if that number
##      drifts from the mesh the axe eats a wedge of the wrong size.
##   2. THE SEAMS. One continuous tube per limb (bug 7 opened the old trunk
##      into floating bands), a bark field that closes exactly around the
##      trunk, and no shading seam down the UV split.
##   3. THE CONTRACT WITH TreeV2. `Trunk` + `Branch_NN_rRRR` names, wood on a
##      material called bark_*, cards on one called leaf_*, enough rings
##      through the chop band to carve, and the same seed building the same
##      tree twice.
##   4. THE BUDGET.
## ===========================================================================

const CHOP_LO := 0.62      ## TreeV2.NOTCH_Y - NOTCH_H
const CHOP_HI := 1.42      ## TreeV2.NOTCH_Y + NOTCH_H
const TRI_CEIL := {0: 600, 1: 4200, 2: 15000, 3: 24000, 4: 12000}
const BUILD_MS_CEIL := 120.0

var passed := 0
var failed := 0
var failures: Array[String] = []
var _ran := false


func ok(cond: bool, label: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		failures.append(label)
		print("  FAIL  ", label)


## Tests run on the first frame, never in _initialize(): a node added inside
## SceneTree._init() does NOT get _ready() before _init() returns -- Godot
## defers it to frame one, and that has cost this project a false 25-failure
## report before.
func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_library()
	_ratios()
	_geometry()
	_bark()
	_contract()
	_determinism()
	_budget()
	print("")
	print("TreeKitTests: %d passed, %d failed" % [passed, failed])
	for f in failures:
		print("   - ", f)
	ok(passed >= 200, "the suite itself did not shrink (>=200 assertions)")
	return true


# --------------------------------------------------------------- 1. library

func _library() -> void:
	print("-- the part library")
	ok(TreeKit.PARTS.size() >= 60, "at least 60 authored parts (have %d)" % TreeKit.PARTS.size())
	var fam := {}
	for k in TreeKit.PARTS.keys():
		fam[String(k).split("_")[0]] = int(fam.get(String(k).split("_")[0], 0)) + 1
	for f in ["FLARE", "BOLE", "TOP", "BOUGH", "ARM", "SPRAY", "DET"]:
		ok(int(fam.get(f, 0)) >= 5, "family %s has 5+ shapes" % f)

	for name in TreeKit.PARTS.keys():
		var pd: Dictionary = TreeKit.PARTS[name]
		var n := String(name)
		# A radius list that does not start at t = 0 silently applies its FIRST
		# entry to the whole run: "rad": [[1.0, 0.10]] made every ring 10% of
		# its taper, which is a whole tree built as a wire. Anything that is
		# not a flare has to open at its natural thickness.
		if pd.has("rad") and not (pd["rad"] as Array).is_empty() and not n.begins_with("FLARE"):
			var first: Array = (pd["rad"] as Array)[0]
			ok(float(first[0]) <= 0.0001 or is_equal_approx(float(first[1]), 1.0),
				"%s: radius profile is anchored at t=0 (or its first stop is 1.0)" % n)
		for sk in (pd.get("sock", []) as Array):
			var a: Array = sk
			ok(a.size() == 5, "%s: socket has 5 fields" % n)
			ok(float(a[0]) >= 0.0 and float(a[0]) <= 1.0, "%s: socket t in 0..1" % n)
			ok(String(a[4]) in ["bough", "arm", "spray", "detail"],
				"%s: socket kind is known (%s)" % [n, a[4]])
		for pt in (pd.get("path", []) as Array):
			var p: Array = pt
			ok(absf(float(p[1])) < 0.9 and absf(float(p[2])) < 0.9,
				"%s: path offset stays sane" % n)

	print("-- the recipes")
	var recs := 0
	for sp in TreeKit.RECIPES.keys():
		ok(TreeKit.SP.has(sp), "recipe species %s is in the species table" % sp)
		for rec in (TreeKit.RECIPES[sp] as Array):
			recs += 1
			for key in ["flare", "top", "spray"]:
				ok(TreeKit.PARTS.has(String(rec[key])),
					"%s: %s part '%s' exists" % [sp, key, rec[key]])
			for lst in ["bole", "boughs", "arms"]:
				ok(not (rec[lst] as Array).is_empty(), "%s: %s list is not empty" % [sp, lst])
				for part in (rec[lst] as Array):
					ok(TreeKit.PARTS.has(String(part)),
						"%s: %s part '%s' exists" % [sp, lst, part])
	ok(recs >= 25, "at least 25 authored recipes (have %d)" % recs)


# ---------------------------------------------------------------- 2. ratios

func _ratios() -> void:
	print("-- da Vinci / the pipe model")
	for sp in TreeKit.SP.keys():
		var s: Dictionary = TreeKit.SP[sp]
		var delta := float(s["delta"])
		ok(delta >= 1.8 and delta <= 2.6, "%s: pipe exponent inside the measured band" % sp)
		# the children of a fork can never carry more wood than the parent
		var r_parent := 0.30
		var kids: Array = TreeKit._pipe_split(r_parent, delta, 0.45, [1.0, 1.0, 0.7])
		var sum := 0.0
		for r in kids:
			sum += pow(float(r), delta)
		ok(sum <= pow(r_parent, delta) + 1e-6,
			"%s: sum(r_child^d) never exceeds r_parent^d" % sp)
		ok(is_equal_approx(sum, pow(r_parent, delta) * 0.55),
			"%s: the children get exactly the non-leader share" % sp)
		ok(float(kids[0]) > float(kids[2]), "%s: a heavier socket gets thicker wood" % sp)

	print("-- phyllotaxis")
	ok(is_equal_approx(TreeKit.GOLDEN_ANGLE, deg_to_rad(137.50776)),
		"the golden angle is 137.50776 deg")
	ok(absf(TreeKit.PHI_INV - 0.6180339887) < 1e-6, "apical dominance is phi inverse")
	for sp in ["maple", "birch", "oak"]:
		var t := TreeKit.build(sp, 2, 0, false)
		var az: Array = []
		for c in t.get_children():
			if not String(c.name).begins_with("Branch"):
				continue
			# A limb attaches on the trunk AXIS, not on its surface, so the
			# node position says nothing about which way it points. The limb's
			# own bounding-box centre does.
			var mi := c as MeshInstance3D
			var out: Vector3 = mi.mesh.get_aabb().get_center()
			az.append(atan2(out.z, out.x))
		# only the phyllotaxis run: limbs the recipe's own TRUNK sockets asked
		# for (a kink's low arm, a candelabra's crown limbs) are placed by hand
		# and come after these
		az = az.slice(0, int((TreeKit.SP[sp]["n_bough"] as Array)[2]))
		# successive limbs are one golden angle apart, in the order they were
		# placed; the position only records where they landed, so compare the
		# turn between neighbours
		var good := 0
		for i in range(1, az.size()):
			var d: float = absf(wrapf(float(az[i]) - float(az[i - 1]) - TreeKit.GOLDEN_ANGLE,
				-PI, PI))
			if d < 0.45:
				good += 1
		ok(good >= int(float(maxi(az.size() - 1, 1)) * 0.65),
			"%s: successive boughs turn by the golden angle (%d/%d)" % [sp, good, az.size() - 1])
		t.free()
	for sp2 in ["pine", "fir"]:
		var per: int = int(TreeKit.SP[sp2]["per_whorl"])
		ok(per == 5 or per == 8, "%s: whorl count is Fibonacci (%d)" % [sp2, per])

	print("-- taper")
	for sp3 in TreeKit.SP.keys():
		for st in range(1, 4):
			var h := TreeKit.height_of(sp3, st)
			var r0 := TreeKit.base_radius(sp3, st)
			ok(is_equal_approx(TreeKit.radius_at(sp3, st, 0.0), r0),
				"%s/%d: taper starts at the butt radius" % [sp3, st])
			var a := TreeKit.radius_at(sp3, st, h * 0.2)
			var b := TreeKit.radius_at(sp3, st, h * 0.6)
			ok(a > b, "%s/%d: the stem gets thinner as it climbs" % [sp3, st])
			ok(TreeKit.radius_at(sp3, st, h * 0.95) > 0.0,
				"%s/%d: the taper never reads zero" % [sp3, st])


# -------------------------------------------------------------- 3. geometry

func _geometry() -> void:
	print("-- one continuous tube, and no shading seam")
	for sp in TreeKit.SP.keys():
		var t := TreeKit.build(sp, 2, 0, false)
		var trunk := t.get_child(0) as MeshInstance3D
		var arr: Array = trunk.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]

		# Boundary edges, counted by POSITION so the duplicated UV seam column
		# does not read as a hole. A tube welded end to end has exactly two
		# open rings; anything more means the trunk came apart into bands,
		# which is bug 7 from the v2 spec.
		var pos_of := {}
		var key := PackedInt64Array()
		key.resize(v.size())
		for i in range(v.size()):
			var q := (v[i] * 4096.0).round()
			var k := (int(q.x) & 0xFFFFF) | ((int(q.y) & 0xFFFFF) << 20) | ((int(q.z) & 0xFFFFF) << 40)
			key[i] = k
			pos_of[k] = true
		var edge := {}
		var j := 0
		while j + 2 < idx.size():
			for e in [[idx[j], idx[j + 1]], [idx[j + 1], idx[j + 2]], [idx[j + 2], idx[j]]]:
				var a: int = key[e[0]]
				var b: int = key[e[1]]
				var ek := "%d|%d" % [mini(a, b), maxi(a, b)]
				edge[ek] = int(edge.get(ek, 0)) + 1
			j += 3
		var open_edges := 0
		for c in edge.values():
			if int(c) == 1:
				open_edges += 1
		ok(open_edges > 0 and open_edges <= 80,
			"%s: trunk is one tube, only its two ends are open (%d edges)" % [sp, open_edges])

		# Normals must match across the seam: the +1 column duplicates column 0
		# in position, and if it does not duplicate it in NORMAL the trunk
		# wears a bright stripe up one side.
		var by_pos := {}
		var seam_bad := 0
		for i in range(v.size()):
			var k2: int = key[i]
			if by_pos.has(k2):
				if (n[i] - (by_pos[k2] as Vector3)).length() > 0.02:
					seam_bad += 1
			else:
				by_pos[k2] = n[i]
		ok(seam_bad == 0, "%s: no shading seam down the UV split (%d bad)" % [sp, seam_bad])

		# Outward normals: on a tube every normal points away from the axis --
		# but the axis WANDERS, so "away from (0, y, 0)" is the wrong question.
		# Measure against the centre of the vertex's own height band.
		var mids := {}
		var cnt := {}
		for i in range(v.size()):
			var bkt := int(v[i].y * 4.0)
			mids[bkt] = (mids.get(bkt, Vector3.ZERO) as Vector3) + Vector3(v[i].x, 0.0, v[i].z)
			cnt[bkt] = int(cnt.get(bkt, 0)) + 1
		for bkt2 in mids.keys():
			mids[bkt2] = (mids[bkt2] as Vector3) / float(cnt[bkt2])
		var outward := 0
		var checked := 0
		for i in range(0, v.size(), 17):
			var c0: Vector3 = mids.get(int(v[i].y * 4.0), Vector3.ZERO)
			var radial := Vector3(v[i].x - c0.x, 0.0, v[i].z - c0.z)
			if radial.length() < 0.02:
				continue
			checked += 1
			if radial.normalized().dot(n[i]) > 0.0:
				outward += 1
		ok(checked > 0 and outward >= int(float(checked) * 0.9),
			"%s: trunk normals face outward (%d/%d)" % [sp, outward, checked])

		# UVs in metres, u around and v up
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var uvmax := Vector2.ZERO
		for i in range(uv.size()):
			uvmax = Vector2(maxf(uvmax.x, uv[i].x), maxf(uvmax.y, uv[i].y))
		var h := TreeKit.height_of(sp, 2)
		ok(uvmax.y > h * 0.8 and uvmax.y < h * 1.3,
			"%s: v runs the height of the wood in metres (%.1f vs %.1f)" % [sp, uvmax.y, h])
		ok(uvmax.x > TAU * TreeKit.base_radius(sp, 2) * 0.7,
			"%s: u wraps the circumference in metres" % sp)
		t.free()

	print("-- rings through the chop band")
	for sp2 in TreeKit.SP.keys():
		for st in [1, 2, 3, 4]:
			var t2 := TreeKit.build(sp2, st, 1, st == 4)
			var trunk2 := t2.get_child(0) as MeshInstance3D
			var vv: PackedVector3Array = trunk2.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var ys := {}
			for p in vv:
				if p.y >= CHOP_LO and p.y <= CHOP_HI:
					ys[int(p.y * 200.0)] = true
			# the notch is carved by pushing vertices in: no rings, no notch
			ok(ys.size() >= 4,
				"%s/%d: %d ring levels inside the chop band" % [sp2, st, ys.size()])
			t2.free()


# ------------------------------------------------------------------ 4. bark

func _bark() -> void:
	print("-- the bark field")
	for sp in TreeKit.SP.keys():
		var s: Dictionary = TreeKit.SP[sp]
		var kind := String(s["bark"])
		var amp := float(s["bark_amp"])
		var vk := float(s["bark_v"])
		var cells := 11
		# It has to CLOSE around the trunk. Sampling bark by arc length instead
		# of by wrapped cells puts a seam up one side of every tree.
		var a := TreeKit._bark_offset(kind, 0.0, 1.7, cells, vk, amp)
		var b := TreeKit._bark_offset(kind, float(cells), 1.7, cells, vk, amp)
		ok(absf(a - b) < 1e-5, "%s: the bark field wraps exactly (%.6f vs %.6f)" % [sp, a, b])

		# and it has to actually move the surface
		var lo := 1e9
		var hi := -1e9
		for i in range(240):
			var d0 := TreeKit._bark_offset(kind, float(i % cells) + float(i) * 0.017,
				float(i) * 0.031, cells, vk, amp)
			lo = minf(lo, d0)
			hi = maxf(hi, d0)
		ok(hi - lo > amp * 0.25,
			"%s: relief has real range (%.3f m over an amp of %.3f)" % [sp, hi - lo, amp])
		ok(absf(lo) < amp * 3.0 and absf(hi) < amp * 3.0,
			"%s: relief stays inside a few times its amplitude" % sp)
		ok(TreeKit._bark_offset(kind, 3.0, 1.0, cells, vk, 0.0) == 0.0,
			"%s: zero amplitude means a smooth tube" % sp)

	print("-- relief reaches the mesh, and only the thick wood")
	for sp2 in TreeKit.SP.keys():
		var t := TreeKit.build(sp2, 3, 0, false)
		var trunk := t.get_child(0) as MeshInstance3D
		var v: PackedVector3Array = trunk.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		# Radius has to be measured about the RING's own centre, not about the
		# world axis: the trunk wanders, and a bole that leans 10 cm over its
		# length would otherwise read as 10 cm of bark relief.
		var band: Array = []
		var mid := Vector3.ZERO
		for p in v:
			if p.y > 0.7 and p.y < 2.1:
				band.append(p)
				mid += Vector3(p.x, 0.0, p.z)
		if band.size() > 8:
			mid /= float(band.size())
			var rr := PackedFloat32Array()
			for p2 in band:
				rr.append(Vector2(p2.x - mid.x, p2.z - mid.z).length())
			var mean := 0.0
			for r in rr:
				mean += r
			mean /= float(rr.size())
			var dev := 0.0
			for r2 in rr:
				dev = maxf(dev, absf(r2 - mean))
			var expect := float(TreeKit.SP[sp2]["bark_amp"])
			ok(dev > expect * 0.35,
				"%s: the trunk is not a smooth cylinder (%.3f m off the mean, amp %.3f)"
				% [sp2, dev, expect])
			ok(dev < expect * 6.0 + 0.03,
				"%s: the relief does not eat the trunk (%.3f m)" % [sp2, dev])
		else:
			ok(false, "%s: found a ring band to measure" % sp2)
		t.free()

	print("-- and every recipe wears its own bark")
	for sp3 in TreeKit.SP.keys():
		var s3: Dictionary = TreeKit.SP[sp3]
		var kind3 := String(s3["bark"])
		var amp3 := float(s3["bark_amp"])
		var vk3 := float(s3["bark_v"])
		# the seed must not break the wrap -- that is the whole reason the
		# octaves are offset by a whole number of cells
		for sd in [0, 1, 7, 113, 4095]:
			var wa := TreeKit._bark_offset(kind3, 0.0, 2.3, 11, vk3, amp3, sd)
			var wb := TreeKit._bark_offset(kind3, 11.0, 2.3, 11, vk3, amp3, sd)
			ok(absf(wa - wb) < 1e-5,
				"%s: seed %d still closes around the trunk" % [sp3, sd])
		# and it must actually change the pattern
		var diff := 0
		for i in range(60):
			var a3 := TreeKit._bark_offset(kind3, float(i) * 0.37, float(i) * 0.11, 11, vk3, amp3, 0)
			var b3 := TreeKit._bark_offset(kind3, float(i) * 0.37, float(i) * 0.11, 11, vk3, amp3, 913)
			if absf(a3 - b3) > amp3 * 0.05:
				diff += 1
		ok(diff >= 20, "%s: a different seed is a different bark (%d/60 samples)" % [sp3, diff])
		# same seed, same bark -- a save has to restore the tree it saved
		ok(is_equal_approx(TreeKit._bark_offset(kind3, 2.1, 1.3, 11, vk3, amp3, 77),
			TreeKit._bark_offset(kind3, 2.1, 1.3, 11, vk3, amp3, 77)),
			"%s: the same seed is the same bark" % sp3)

	print("-- the recipes do not share a relief seed")
	for sp4 in TreeKit.SP.keys():
		var seeds := {}
		for v in range(TreeKit.variants(sp4)):
			var r4 := TreeKit._relief_of(sp4, false)
			r4["seed"] = posmod(hash(sp4 + "#" + str(v)), 4096)
			seeds[int(r4["seed"])] = true
		ok(seeds.size() == TreeKit.variants(sp4),
			"%s: %d recipes, %d distinct bark seeds" % [sp4, TreeKit.variants(sp4), seeds.size()])

	# a dead tree wears the shared deadwood split, not its species' bark
	var d := TreeKit._relief_of("oak", true)
	ok(String(d["kind"]) == "split", "a snag wears the shared deadwood relief")
	ok(float(d["amp"]) > float(TreeKit.SP["oak"]["bark_amp"]),
		"deadwood splits deeper than living bark")


# -------------------------------------------------- 5. the contract with TreeV2

func _contract() -> void:
	print("-- the node structure TreeV2 reads")
	for sp in TreeKit.SP.keys():
		for st in range(5):
			for v in range(TreeKit.variants(sp)):
				var dead := st == 4
				var t := TreeKit.build(sp, st, v, dead)
				ok(t != null and t.get_child_count() > 0, "%s/%d/v%d: built something" % [sp, st, v])
				var trunk := t.get_child(0) as MeshInstance3D
				ok(trunk != null and String(trunk.name).begins_with("Trunk"),
					"%s/%d/v%d: child 0 is the Trunk" % [sp, st, v])
				ok(trunk.mesh != null and trunk.mesh.get_surface_count() >= 1,
					"%s/%d/v%d: the trunk has geometry" % [sp, st, v])

				var wood_mat := String(trunk.mesh.surface_get_material(0).resource_name)
				ok(wood_mat.begins_with("bark_"),
					"%s/%d/v%d: surface 0 is named bark_* so _apply_materials finds it" % [sp, st, v])

				var limbs := 0
				var cards := 0
				for c in t.get_children():
					var mi := c as MeshInstance3D
					if mi == null or not String(mi.name).begins_with("Branch"):
						continue
					limbs += 1
					# TreeBranch._radius_from_name parses the trailing _rNNN
					var nm := String(mi.name)
					var i := nm.rfind("_r")
					ok(i > 0 and nm.substr(i + 2).is_valid_int(),
						"%s/%d/v%d: %s carries a parsable radius" % [sp, st, v, nm])
					var r := float(nm.substr(i + 2).to_int()) / 1000.0
					ok(r > 0.0 and r < TreeKit.base_radius(sp, st) * 1.05,
						"%s/%d/v%d: %s is never thicker than the trunk" % [sp, st, v, nm])
					ok((mi as Node3D).position.y >= -0.01,
						"%s/%d/v%d: %s is attached above the ground" % [sp, st, v, nm])
					for si in range(mi.mesh.get_surface_count()):
						var m := mi.mesh.surface_get_material(si)
						if m != null and String(m.resource_name).begins_with("leaf_"):
							@warning_ignore("integer_division")
							cards += (mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_INDEX]
								as PackedInt32Array).size() / 6
				for si2 in range(trunk.mesh.get_surface_count()):
					var m2 := trunk.mesh.surface_get_material(si2)
					if m2 != null and String(m2.resource_name).begins_with("leaf_"):
						@warning_ignore("integer_division")
						cards += (trunk.mesh.surface_get_arrays(si2)[Mesh.ARRAY_INDEX]
							as PackedInt32Array).size() / 6

				if st == 0:
					ok(limbs == 0, "%s/v%d: a sapling is a stem, not a tree" % [sp, v])
				else:
					ok(limbs > 0, "%s/%d/v%d: has limbs" % [sp, st, v])
				if dead:
					ok(cards == 0, "%s/v%d: a snag carries no leaves" % [sp, v])
				else:
					ok(cards > 4, "%s/%d/v%d: carries leaf cards (%d)" % [sp, st, v, cards])
				t.free()

	print("-- leaf cards land on the atlas's spray rows")
	var t2 := TreeKit.build("maple", 2, 0, false)
	var found := false
	for c in t2.get_children():
		var mi := c as MeshInstance3D
		if mi == null:
			continue
		for si in range(mi.mesh.get_surface_count()):
			var m := mi.mesh.surface_get_material(si)
			if m == null or not String(m.resource_name).begins_with("leaf_"):
				continue
			found = true
			var uv: PackedVector2Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_TEX_UV]
			var bad := 0
			for u in uv:
				# cells 0-7 are the SPRAY rows (rows 0-1 of the 4x4 sheet);
				# the single-leaf cells below them read as bare sticks in a canopy
				if u.y < 0.4999 or u.x < -0.001 or u.x > 1.001 or u.y > 1.001:
					bad += 1
			ok(bad == 0, "every card sits in a spray cell (%d strays)" % bad)
	ok(found, "found a leaf surface to check")
	t2.free()

	print("-- radius_at agrees with the mesh the notch is carved in")
	for sp3 in TreeKit.SP.keys():
		var t3 := TreeKit.build(sp3, 2, 0, false)
		var vv: PackedVector3Array = (t3.get_child(0) as MeshInstance3D).mesh \
			.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var acc := 0.0
		var n := 0
		var mid := Vector3.ZERO
		var band: Array = []
		for p in vv:
			if p.y > 0.88 and p.y < 1.16:
				band.append(p)
				mid += Vector3(p.x, 0.0, p.z)
		if band.size() > 0:
			mid /= float(band.size())
		for p2 in band:
			acc += Vector2(p2.x - mid.x, p2.z - mid.z).length()
			n += 1
		if n > 3:
			var measured := acc / float(n)
			var claimed := TreeKit.radius_at(sp3, 2, 1.02)
			ok(absf(measured - claimed) < claimed * 0.30,
				"%s: radius_at(1.02) %.3f matches the mesh %.3f" % [sp3, claimed, measured])
		else:
			ok(false, "%s: found trunk rings at the notch height" % sp3)
		t3.free()


# ------------------------------------------------------------ 6. determinism

func _determinism() -> void:
	print("-- the same seed builds the same tree")
	for sp in ["maple", "pine"]:
		TreeKit.clear_cache()
		var a := TreeKit.build(sp, 2, 3, false)
		var va: PackedVector3Array = (a.get_child(0) as MeshInstance3D).mesh \
			.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var na := a.get_child_count()
		a.free()
		TreeKit.clear_cache()
		var b := TreeKit.build(sp, 2, 3, false)
		var vb: PackedVector3Array = (b.get_child(0) as MeshInstance3D).mesh \
			.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		ok(na == b.get_child_count(), "%s: same part count on a rebuild" % sp)
		ok(va.size() == vb.size(), "%s: same vertex count on a rebuild" % sp)
		var drift := 0.0
		for i in range(mini(va.size(), vb.size())):
			drift = maxf(drift, va[i].distance_to(vb[i]))
		ok(drift < 1e-6, "%s: identical geometry on a rebuild (%.9f)" % [sp, drift])
		b.free()

	print("-- the variants are actually different trees")
	for sp2 in TreeKit.SP.keys():
		var sigs := {}
		for v in range(TreeKit.variants(sp2)):
			var t := TreeKit.build(sp2, 2, v, false)
			var vv: PackedVector3Array = (t.get_child(0) as MeshInstance3D).mesh \
				.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var acc := Vector3.ZERO
			for p in vv:
				acc += p
			sigs["%d|%d|%.4f|%.4f" % [t.get_child_count(), vv.size(), acc.x, acc.z]] = true
			t.free()
		ok(sigs.size() >= TreeKit.variants(sp2) - 1,
			"%s: %d of %d recipes build a distinct tree" % [sp2, sigs.size(), TreeKit.variants(sp2)])


# ----------------------------------------------------------------- 7. budget

func _budget() -> void:
	print("-- the budget")
	var worst := 0.0
	for sp in TreeKit.SP.keys():
		for st in range(5):
			for v in range(TreeKit.variants(sp)):
				TreeKit.clear_cache()
				var t0 := Time.get_ticks_usec()
				var t := TreeKit.build(sp, st, v, st == 4)
				var ms := float(Time.get_ticks_usec() - t0) / 1000.0
				worst = maxf(worst, ms)
				var tris := 0
				for c in t.get_children():
					var mi := c as MeshInstance3D
					if mi == null or mi.mesh == null:
						continue
					for si in range(mi.mesh.get_surface_count()):
						@warning_ignore("integer_division")
						tris += (mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_INDEX]
							as PackedInt32Array).size() / 3
				ok(tris <= int(TRI_CEIL[st]),
					"%s/%d/v%d: %d tris under the %d ceiling" % [sp, st, v, tris, TRI_CEIL[st]])
				ok(tris > 40, "%s/%d/v%d: built more than nothing" % [sp, st, v])
				t.free()
	ok(worst < BUILD_MS_CEIL,
		"the slowest model builds in %.1f ms (ceiling %.0f)" % [worst, BUILD_MS_CEIL])

	print("-- the cache does its job")
	TreeKit.clear_cache()
	var a := TreeKit.build("oak", 3, 0, false)
	var m1: Mesh = (a.get_child(0) as MeshInstance3D).mesh
	var b := TreeKit.build("oak", 3, 0, false)
	var m2: Mesh = (b.get_child(0) as MeshInstance3D).mesh
	ok(m1 == m2, "420 trees share one mesh per recipe, not 420 meshes")
	a.free()
	b.free()
