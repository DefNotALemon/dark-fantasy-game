class_name WoodCut
extends RefCounted

## ===========================================================================
## CUTTING TIMBER — a trunk mesh sliced at a plane, and the cut face dressed
## as wood.
##
## Lemon 2026-09-14: "the bottom of a fallen tree should not be see through,
## it should be wood" and "the logs should not look like mushrooms".
##
## Before this, FallenTrunk cut its trunk by keeping WHOLE TRIANGLES on one
## side of a height and throwing the rest away. That leaves an open tube: from
## the cut end you look straight into the back faces of the bark, which
## cull_back does not draw, so the log was hollow and see-through at both ends
## -- and the cut itself sat wherever the nearest ring happened to be, never
## on the line you chopped.
##
## slab() does it properly:
##   * every triangle that crosses a cut plane is SPLIT on it, with all its
##     attributes (normal, tangent, uv, colour) interpolated, so the cut lands
##     exactly on the plane and the edge is a clean loop, not a fringe;
##   * the split edges are welded into loops and each loop is CAPPED with a
##     flat disc of end grain -- a separate surface, so it wears its own
##     material: growth rings, not stretched bark.
##
## tube() builds a plain log from scratch (bark UVs in metres, so it wears
## the species' bark shader unchanged), and log_instance() turns one into the
## MeshInstance3D a DroppedItem carries -- lying along +X, bottom on y = 0.
##
## THE WINDING RULE, measured not assumed (see myrkfell-chopping notes):
## Godot's front faces are CLOCKWISE, so the normal a triangle renders with is
## the NEGATIVE of (b - a) x (c - a). Every cap and every tube quad here is
## checked against the direction it must face and flipped if it disagrees.
## ===========================================================================

const CAP_GRAIN_PX := 128
const WELD := 1.0e-4          ## split points closer than this are one point
const BILLET_SIDES := 12

## Fresh end grain by species: the tint the ring texture is multiplied by.
const GRAIN_TINT := {
	"maple": Color(1.00, 0.95, 0.86), "birch": Color(1.00, 0.98, 0.92),
	"oak": Color(0.86, 0.74, 0.58), "pine": Color(1.00, 0.88, 0.66),
	"fir": Color(0.92, 0.82, 0.68),
}
const GRAIN_DEFAULT := Color(0.95, 0.88, 0.75)
## Bark for a log with no species (a generic "Wood" billet)
const BARK_DEFAULT := Color(0.28, 0.19, 0.12)

static var _grain_tex: ImageTexture = null
static var _grain_mats: Dictionary = {}


## ============================== The slab ===================================


## Keep the part of `src` (Mesh.ARRAY_* arrays, PRIMITIVE_TRIANGLES) between
## y_lo and y_hi, splitting triangles on both planes. Returns
##   {"wood": arrays or [], "caps": [arrays, ...]}
## with one cap surface per closed loop on a capped plane. Pass -INF / INF to
## leave an end open.
static func slab(src: Array, y_lo: float, y_hi: float, cap_lo: bool, cap_hi: bool) -> Dictionary:
	var out := {"wood": [], "caps": []}
	var m := _from_arrays(src)
	if m.is_empty():
		return out
	if y_lo > -INF:
		var r := _half(m, y_lo, true)
		m = r["m"]
		if cap_lo:
			for loop in _loops(m, r["segs"]):
				var cap := _cap(loop, y_lo, false)
				if not cap.is_empty():
					out["caps"].append(cap)
	if y_hi < INF and not m.is_empty():
		var r2 := _half(m, y_hi, false)
		m = r2["m"]
		if cap_hi:
			for loop in _loops(m, r2["segs"]):
				var cap := _cap(loop, y_hi, true)
				if not cap.is_empty():
					out["caps"].append(cap)
	if not m.is_empty() and (m["idx"] as PackedInt32Array).size() >= 3:
		out["wood"] = _to_arrays(m)
	return out


## Leaf cards and other things that must not be sliced: a triangle survives
## whole if its centre is inside the slab, otherwise it goes. Returns arrays
## or [] when nothing is left.
static func cards(src: Array, y_lo: float, y_hi: float) -> Array:
	if src.size() < Mesh.ARRAY_MAX:
		return []
	var v: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = src[Mesh.ARRAY_INDEX]
	if v.is_empty() or idx.is_empty():
		return []
	var keep := PackedInt32Array()
	var t := 0
	while t + 2 < idx.size():
		var cy := (v[idx[t]].y + v[idx[t + 1]].y + v[idx[t + 2]].y) / 3.0
		if cy >= y_lo and cy <= y_hi:
			keep.append_array(PackedInt32Array([idx[t], idx[t + 1], idx[t + 2]]))
		t += 3
	if keep.is_empty():
		return []
	var arr: Array = src.duplicate()
	arr[Mesh.ARRAY_INDEX] = keep
	return arr


## ---- working form: one dictionary of packed arrays -------------------------

static func _from_arrays(src: Array) -> Dictionary:
	if src == null or src.size() < Mesh.ARRAY_MAX:
		return {}
	var v: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = src[Mesh.ARRAY_INDEX]
	if v.is_empty() or idx.is_empty():
		return {}
	var m := {"v": v, "idx": idx}
	m["n"] = src[Mesh.ARRAY_NORMAL] if src[Mesh.ARRAY_NORMAL] is PackedVector3Array else PackedVector3Array()
	m["t"] = src[Mesh.ARRAY_TANGENT] if src[Mesh.ARRAY_TANGENT] is PackedFloat32Array else PackedFloat32Array()
	m["uv"] = src[Mesh.ARRAY_TEX_UV] if src[Mesh.ARRAY_TEX_UV] is PackedVector2Array else PackedVector2Array()
	m["col"] = src[Mesh.ARRAY_COLOR] if src[Mesh.ARRAY_COLOR] is PackedColorArray else PackedColorArray()
	## attribute arrays that do not match the vertex count are ignored rather
	## than trusted -- a half-filled one would index off the end
	var nv := v.size()
	if (m["n"] as PackedVector3Array).size() != nv:
		m["n"] = PackedVector3Array()
	if (m["t"] as PackedFloat32Array).size() != nv * 4:
		m["t"] = PackedFloat32Array()
	if (m["uv"] as PackedVector2Array).size() != nv:
		m["uv"] = PackedVector2Array()
	if (m["col"] as PackedColorArray).size() != nv:
		m["col"] = PackedColorArray()
	return m


static func _to_arrays(m: Dictionary) -> Array:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = m["v"]
	arr[Mesh.ARRAY_INDEX] = m["idx"]
	if not (m["n"] as PackedVector3Array).is_empty():
		arr[Mesh.ARRAY_NORMAL] = m["n"]
	if not (m["t"] as PackedFloat32Array).is_empty():
		arr[Mesh.ARRAY_TANGENT] = m["t"]
	if not (m["uv"] as PackedVector2Array).is_empty():
		arr[Mesh.ARRAY_TEX_UV] = m["uv"]
	if not (m["col"] as PackedColorArray).is_empty():
		arr[Mesh.ARRAY_COLOR] = m["col"]
	return arr


## A mesh under construction. PLAIN Arrays, not Packed ones: a Packed array
## pulled out of a Dictionary is a COPY (they are value types in GDScript),
## so `(o["v"] as PackedVector3Array).append(p)` appends to a temporary and
## the dictionary never changes. Arrays are references; they are packed once
## at the end in _finish().
static func _empty_like(m: Dictionary) -> Dictionary:
	## an attribute the source does not carry stays null, so _finish() leaves it
	## out of the surface arrays entirely. Written as ifs, not ternaries: `[] if c
	## else null` has no common type and GDScript flags it as an incompatible one.
	var out: Dictionary = {"v": [], "idx": [], "n": null, "t": null, "uv": null, "col": null}
	if not (m["n"] as PackedVector3Array).is_empty():
		out["n"] = []
	if not (m["t"] as PackedFloat32Array).is_empty():
		out["t"] = []
	if not (m["uv"] as PackedVector2Array).is_empty():
		out["uv"] = []
	if not (m["col"] as PackedColorArray).is_empty():
		out["col"] = []
	return out


static func _finish(o: Dictionary) -> Dictionary:
	## the builder's plain Arrays into packed ones; absent attributes to empty
	o["v"] = PackedVector3Array(o["v"])
	o["idx"] = PackedInt32Array(o["idx"])
	o["n"] = PackedVector3Array(o["n"]) if o["n"] != null else PackedVector3Array()
	o["t"] = PackedFloat32Array(o["t"]) if o["t"] != null else PackedFloat32Array()
	o["uv"] = PackedVector2Array(o["uv"]) if o["uv"] != null else PackedVector2Array()
	o["col"] = PackedColorArray(o["col"]) if o["col"] != null else PackedColorArray()
	return o


static func _copy_vertex(m: Dictionary, o: Dictionary, i: int) -> int:
	var ov: Array = o["v"]
	ov.append((m["v"] as PackedVector3Array)[i])
	if o["n"] != null:
		(o["n"] as Array).append((m["n"] as PackedVector3Array)[i])
	if o["t"] != null:
		var t: PackedFloat32Array = m["t"]
		(o["t"] as Array).append_array(Array(t.slice(i * 4, i * 4 + 4)))
	if o["uv"] != null:
		(o["uv"] as Array).append((m["uv"] as PackedVector2Array)[i])
	if o["col"] != null:
		(o["col"] as Array).append((m["col"] as PackedColorArray)[i])
	return ov.size() - 1


static func _lerp_vertex(m: Dictionary, o: Dictionary, i: int, j: int, f: float, y: float) -> int:
	var v: PackedVector3Array = m["v"]
	var p := v[i].lerp(v[j], f)
	p.y = y                          ## exactly on the plane, no float drift
	var ov: Array = o["v"]
	ov.append(p)
	if o["n"] != null:
		var n: PackedVector3Array = m["n"]
		var nn := n[i].lerp(n[j], f)
		(o["n"] as Array).append(nn.normalized() if nn.length_squared() > 1e-8 else n[i])
	if o["t"] != null:
		var t: PackedFloat32Array = m["t"]
		var ta := Vector3(t[i * 4], t[i * 4 + 1], t[i * 4 + 2])
		var tb := Vector3(t[j * 4], t[j * 4 + 1], t[j * 4 + 2])
		var tt := ta.lerp(tb, f)
		tt = tt.normalized() if tt.length_squared() > 1e-8 else ta
		(o["t"] as Array).append_array([tt.x, tt.y, tt.z, t[i * 4 + 3]])
	if o["uv"] != null:
		var uv: PackedVector2Array = m["uv"]
		(o["uv"] as Array).append(uv[i].lerp(uv[j], f))
	if o["col"] != null:
		var c: PackedColorArray = m["col"]
		(o["col"] as Array).append(c[i].lerp(c[j], f))
	return ov.size() - 1


## Everything on one side of y = `y`. Triangles crossing the plane are split;
## the new edges lying on the plane come back as index pairs in "segs".
static func _half(m: Dictionary, y: float, keep_above: bool) -> Dictionary:
	var v: PackedVector3Array = m["v"]
	var idx: PackedInt32Array = m["idx"]
	var side := 1.0 if keep_above else -1.0
	var o := _empty_like(m)
	var rmap := PackedInt32Array()
	rmap.resize(v.size())
	rmap.fill(-1)
	var cache := {}
	var segs := PackedInt32Array()
	var t := 0
	while t + 2 < idx.size():
		var tri := [idx[t], idx[t + 1], idx[t + 2]]
		t += 3
		var d := [side * (v[tri[0]].y - y), side * (v[tri[1]].y - y), side * (v[tri[2]].y - y)]
		var ins := [d[0] >= 0.0, d[1] >= 0.0, d[2] >= 0.0]
		var n_in := int(ins[0]) + int(ins[1]) + int(ins[2])
		if n_in == 0:
			continue
		if n_in == 3:
			for k in range(3):
				var i: int = tri[k]
				if rmap[i] < 0:
					rmap[i] = _copy_vertex(m, o, i)
			(o["idx"] as Array).append_array([rmap[tri[0]], rmap[tri[1]], rmap[tri[2]]])
			continue
		## rotate (cyclic, so the winding is untouched) until the odd one out
		## is where the cases below expect it: the lone IN vertex first, or
		## the lone OUT vertex last
		var shift := 0
		if n_in == 1:
			shift = 0 if ins[0] else (1 if ins[1] else 2)
		else:
			shift = 1 if not ins[0] else (2 if not ins[1] else 0)
		var a: int = tri[shift]
		var b: int = tri[(shift + 1) % 3]
		var c: int = tri[(shift + 2) % 3]
		if n_in == 1:
			var ab := _split(m, o, cache, a, b, y)
			var ac := _split(m, o, cache, a, c, y)
			if rmap[a] < 0:
				rmap[a] = _copy_vertex(m, o, a)
			(o["idx"] as Array).append_array([rmap[a], ab, ac])
			segs.append_array(PackedInt32Array([ab, ac]))
		else:
			var bc := _split(m, o, cache, b, c, y)
			var ac := _split(m, o, cache, a, c, y)
			if rmap[a] < 0:
				rmap[a] = _copy_vertex(m, o, a)
			if rmap[b] < 0:
				rmap[b] = _copy_vertex(m, o, b)
			(o["idx"] as Array).append_array([rmap[a], rmap[b], bc, rmap[a], bc, ac])
			segs.append_array(PackedInt32Array([bc, ac]))
	return {"m": _finish(o), "segs": segs}


static func _split(m: Dictionary, o: Dictionary, cache: Dictionary, i: int, j: int, y: float) -> int:
	var key := Vector2i(mini(i, j), maxi(i, j))
	if cache.has(key):
		return int(cache[key])
	var v: PackedVector3Array = m["v"]
	var dy := v[j].y - v[i].y
	var f := 0.5 if absf(dy) < 1e-9 else clampf((y - v[i].y) / dy, 0.0, 1.0)
	var k := _lerp_vertex(m, o, i, j, f, y)
	cache[key] = k
	return k


## ---- loops and caps --------------------------------------------------------

## Weld the split edges into closed loops of positions. The tube's UV seam
## column is a duplicate of column 0 at a different index, so welding is by
## POSITION, not index -- otherwise every loop would have a one-vertex gap
## at the seam and never close.
static func _loops(m: Dictionary, segs: PackedInt32Array) -> Array:
	var loops: Array = []
	if segs.size() < 6:
		return loops
	var v: PackedVector3Array = m["v"]
	var key_of := {}          ## quantised position -> canonical id
	var pos := PackedVector3Array()
	var adj: Array = []
	var ids := PackedInt32Array()
	ids.resize(segs.size())
	for s in range(segs.size()):
		var p := v[segs[s]]
		var q := Vector3i(int(round(p.x / WELD)), int(round(p.y / WELD)), int(round(p.z / WELD)))
		if not key_of.has(q):
			key_of[q] = pos.size()
			pos.append(p)
			adj.append([])          ## a plain Array: appended through the reference
		ids[s] = int(key_of[q])
	var e := 0
	while e + 1 < ids.size():
		var a := ids[e]
		var b := ids[e + 1]
		e += 2
		if a == b:
			continue
		(adj[a] as Array).append(b)
		(adj[b] as Array).append(a)
	var visited := PackedByteArray()
	visited.resize(pos.size())
	visited.fill(0)
	for start in range(pos.size()):
		if visited[start] == 1 or (adj[start] as Array).is_empty():
			continue
		var loop := PackedVector3Array()
		var cur := start
		var prev := -1
		while true:
			visited[cur] = 1
			loop.append(pos[cur])
			var nxt := -1
			for nb in (adj[cur] as Array):
				if nb != prev and visited[nb] == 0:
					nxt = nb
					break
			if nxt < 0:
				break
			prev = cur
			cur = nxt
		if loop.size() >= 3:
			loops.append(loop)
	return loops


## A flat disc of end grain over one loop, facing `up` (+Y) or down.
## A least-squares circle through a rim, refitted on its inliers: a plain
## Kasa fit over every point, then the points that sit on or outside that
## circle (within the bark's relief) are kept and the fit repeated. On a whole ring that
## is the ring; on a notched one the bark that is left is the majority and
## agrees with itself, so the wedge the axe took drops out as outliers and
## cannot drag the centre. Returns [cx, cz, r] in the loop's x/z, or the
## centroid and its max radius when the fit is degenerate.
static func fit_circle(loop: PackedVector3Array) -> Array:
	var n := loop.size()
	var c := Vector3.ZERO
	for p in loop:
		c += p
	c /= float(maxi(n, 1))
	var rmax := 0.0
	for p in loop:
		rmax = maxf(rmax, Vector2(p.x - c.x, p.z - c.z).length())
	if n < 4 or rmax < 1e-6:
		return [c.x, c.z, rmax]
	var use := PackedByteArray()
	use.resize(n)
	use.fill(1)
	var best := [c.x, c.z, rmax]
	for _pass in range(6):
		var fit := _kasa(loop, use, c)
		if fit.is_empty():
			break
		best = fit
		## The axe only ever takes wood AWAY, so the points that disagree with
		## the circle all sit INSIDE it. Keep everything on or outside it, and
		## anything inside by no more than the bark's own relief (1.5x the
		## median miss, never under 4% of the radius); the notch drops out.
		var inside := PackedFloat32Array()
		var miss := PackedFloat32Array()
		for i in range(n):
			var di := Vector2(loop[i].x - float(fit[0]), loop[i].z - float(fit[1])).length()
			inside.append(float(fit[2]) - di)
			miss.append(absf(float(fit[2]) - di))
		var sorted := PackedFloat32Array(miss)
		sorted.sort()
		@warning_ignore("integer_division")
		var tol: float = maxf(sorted[n / 2] * 1.5, float(fit[2]) * 0.04)
		var kept := 0
		var changed := false
		for i in range(n):
			var u := 1 if inside[i] <= tol else 0
			if u != use[i]:
				changed = true
			use[i] = u
			kept += u
		if kept < 4 or not changed:
			break
	return best


static func _kasa(loop: PackedVector3Array, use: PackedByteArray, about: Vector3) -> Array:
	## normal equations for x^2 + z^2 + D x + E z + F = 0 over the used points,
	## about `about` so the 3x3 stays well conditioned
	var sxx := 0.0
	var sxz := 0.0
	var szz := 0.0
	var sx := 0.0
	var sz := 0.0
	var m := 0.0
	var bx := 0.0
	var bz := 0.0
	var b1 := 0.0
	for i in range(loop.size()):
		if use[i] == 0:
			continue
		var x := loop[i].x - about.x
		var z := loop[i].z - about.z
		var r2 := x * x + z * z
		sxx += x * x
		sxz += x * z
		szz += z * z
		sx += x
		sz += z
		m += 1.0
		bx += -r2 * x
		bz += -r2 * z
		b1 += -r2
	if m < 3.0:
		return []
	var A := Basis(Vector3(sxx, sxz, sx), Vector3(sxz, szz, sz), Vector3(sx, sz, m))
	if absf(A.determinant()) < 1e-14:
		return []
	var sol := A.inverse() * Vector3(bx, bz, b1)
	var cx := -sol.x * 0.5
	var cz := -sol.y * 0.5
	var rr := cx * cx + cz * cz - sol.z
	if rr <= 0.0 or is_nan(rr):
		return []
	return [about.x + cx, about.z + cz, sqrt(rr)]


static func _cap(loop: PackedVector3Array, y: float, up: bool) -> Array:
	var n := loop.size()
	if n < 3:
		return []
	var c := Vector3.ZERO
	for p in loop:
		c += p
	c /= float(n)
	var rmax := 0.0
	for p in loop:
		rmax = maxf(rmax, Vector2(p.x - c.x, p.z - c.z).length())
	if rmax < 1e-5:
		return []
	## THE RINGS BELONG TO THE TREE, NOT TO THE CUT (Lemon 2026-09-14). Where
	## the break runs through the notch the loop is a D, and a disc centred on
	## the D's centroid puts the pith in the wrong place with rings that follow
	## the axe. Fit a circle to the OUTER rim -- the bark that is still there --
	## and centre the grain on that: the pith sits where it grew, and the
	## rings simply stop where the wood was taken out.
	var fit := fit_circle(loop)
	var ring_c := Vector3(float(fit[0]), c.y, float(fit[1]))
	var ring_r := float(fit[2])
	if ring_r < rmax * 0.5 or ring_r > rmax * 1.6:
		ring_c = c                       ## a fit that ran away: fall back
		ring_r = rmax
	var span := ring_r * 2.04
	var want := Vector3.UP if up else Vector3.DOWN

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var poly := PackedVector2Array()
	for p in loop:
		var q := Vector3(p.x, y, p.z)
		verts.append(q)
		norms.append(want)
		uvs.append(Vector2(0.5 + (p.x - ring_c.x) / span, 0.5 + (p.z - ring_c.z) / span))
		poly.append(Vector2(p.x, p.z))
	var tris := Geometry2D.triangulate_polygon(poly)
	var idx := PackedInt32Array()
	if tris.size() >= 3:
		idx = tris
	else:
		## a loop the triangulator would not take (self-touching at a pinched
		## notch, say): fan it from the centre instead
		verts.append(Vector3(c.x, y, c.z))
		norms.append(want)
		uvs.append(Vector2(0.5, 0.5))
		var ci := n
		for i in range(n):
			idx.append_array(PackedInt32Array([ci, i, (i + 1) % n]))
	## face the right way: the rendered normal is -(b-a)x(c-a)
	var t := 0
	while t + 2 < idx.size():
		var a := verts[idx[t]]
		var b := verts[idx[t + 1]]
		var cc := verts[idx[t + 2]]
		if (b - a).cross(cc - a).dot(want) > 0.0:
			var tmp := idx[t + 1]
			idx[t + 1] = idx[t + 2]
			idx[t + 2] = tmp
		t += 3
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


## ============================== A plain log ================================


## A bark tube standing along +Y from 0 to `length`, radius r0 at the foot
## and r1 at the top, UVs in metres (u around, v up) so the bark shader's
## default tiling is right. Slightly knobbly so it never reads as a pipe.
static func tube(r0: float, r1: float, length: float, sides := BILLET_SIDES, sd := 0) -> Array:
	sides = clampi(sides, 5, 32)
	var rings := maxi(2, int(ceil(length / 0.35)) + 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = sd if sd != 0 else 7
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var t := PackedFloat32Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	var per := sides + 1
	## one knobble per angular column that runs the whole length, plus a
	## little per-vertex grit; the seam column copies column 0 exactly
	var knob := PackedFloat32Array()
	for k in range(sides):
		knob.append(rng.randf_range(-0.05, 0.05))
	for i in range(rings):
		var f := float(i) / float(rings - 1)
		var y := length * f
		var r := lerpf(r0, r1, f)
		var ravg := r
		for k in range(per):
			var kk := k % sides
			var a := TAU * float(kk) / float(sides)
			var ua := TAU * float(k) / float(sides)       ## the seam column is u = 2*pi*r, not 0
			var rr := r * (1.0 + knob[kk] + rng.randf_range(-0.02, 0.02) * (1.0 if k < sides else 0.0))
			if k == sides:
				rr = v[v.size() - sides].distance_to(Vector3(0, y, 0))   ## seam = column 0
			var dir := Vector3(cos(a), 0.0, sin(a))
			v.append(Vector3(dir.x * rr, y, dir.z * rr))
			n.append(dir)
			t.append_array(PackedFloat32Array([-sin(a), 0.0, cos(a), 1.0]))
			uv.append(Vector2(ua * ravg, y))
			col.append(Color(1, 1, 1, 1))
	for i in range(rings - 1):
		for k in range(sides):
			var a0 := i * per + k
			var a1 := a0 + 1
			var b0 := a0 + per
			var b1 := b0 + 1
			## (a0, a1, b0) and (a1, b1, b0): rendered normal = -(b-a)x(c-a),
			## which for this order is the outward radial -- see the header
			idx.append_array(PackedInt32Array([a0, a1, b0, a1, b1, b0]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_TANGENT] = t
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


## Lay a standing (+Y) piece down along +X. Mesh-space point (x, y, z) about
## the centre (cx, ymid, cz) becomes ((y - ymid) s, -(x - cx) s, (z - cz) s)
## -- a proper rotation, so normals and tangents come along and the winding
## is untouched -- and the whole thing is lifted so its lowest point sits at
## y = `floor_y`. Returns {"arrays": ..., "lift": how far up it was lifted}
## so a caller can put the piece back exactly where the standing one was.
static func lay_down(src: Array, cx: float, ymid: float, cz: float, s: float,
		floor_y := 0.0, lift_override := NAN) -> Dictionary:
	var m := _from_arrays(src)
	if m.is_empty():
		return {"arrays": [], "lift": 0.0}
	var v: PackedVector3Array = m["v"]
	var out := PackedVector3Array()
	out.resize(v.size())
	var min_y := INF
	for i in range(v.size()):
		var p := v[i]
		var q := Vector3((p.y - ymid) * s, -(p.x - cx) * s, (p.z - cz) * s)
		out[i] = q
		min_y = minf(min_y, q.y)
	var lift := (floor_y - min_y) if is_nan(lift_override) else lift_override
	for i in range(out.size()):
		var q := out[i]              ## a packed element is a copy: write it back
		q.y += lift
		out[i] = q
	m["v"] = out
	var n: PackedVector3Array = m["n"]
	if not n.is_empty():
		var nn := PackedVector3Array()
		nn.resize(n.size())
		for i in range(n.size()):
			nn[i] = Vector3(n[i].y, -n[i].x, n[i].z)
		m["n"] = nn
	var t: PackedFloat32Array = m["t"]
	if not t.is_empty():
		var tt := PackedFloat32Array(t)
		var i := 0
		while i + 3 < tt.size():
			var tx := tt[i]
			tt[i] = tt[i + 1]
			tt[i + 1] = -tx
			i += 4
		m["t"] = tt
	return {"arrays": _to_arrays(m), "lift": lift}


## The MeshInstance3D a DroppedItem carries for a log or a billet: a knobbly
## bark tube with end grain on both faces, lying along +X with its underside
## on y = 0. `species` "" means a generic billet in `bark` colour.
static func log_instance(species: String, r: float, length: float,
		bark: Color = BARK_DEFAULT, sd := 0) -> MeshInstance3D:
	var arrays := tube(r, r * 0.93, length, BILLET_SIDES, sd)
	## a hair inside both ends, so the tube is split there and the loops it
	## leaves become the faces -- a plane exactly on the end ring cuts nothing
	var cut := slab(arrays, 0.002, length - 0.002, true, true)
	var laid := lay_down(cut["wood"], 0.0, length * 0.5, 0.0, 1.0, 0.0)
	var mi := MeshInstance3D.new()
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, laid["arrays"])
	var lift: float = laid["lift"]
	for cap in cut["caps"]:
		var lc := lay_down(cap, 0.0, length * 0.5, 0.0, 1.0, 0.0, lift)
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, lc["arrays"])
	mi.mesh = am                     ## before the overrides: they index its surfaces
	mi.set_surface_override_material(0, bark_material(species, bark))
	for si in range(1, am.get_surface_count()):
		mi.set_surface_override_material(si, grain_material(species))
	return mi


## ============================== Materials ==================================


## Bark for a piece lying on the ground: the species' own shader, but it
## does not sway, and its UVs are already metres so the tiling stays default.
static func bark_material(species: String, fallback: Color = BARK_DEFAULT) -> Material:
	if species != "" and TreeV2.ALL_SPECIES.has(species):
		var base: Material = TreeV2.materials_for(species)[0]
		if base is ShaderMaterial:
			var m: ShaderMaterial = (base as ShaderMaterial).duplicate()
			m.set_shader_parameter("sway", 0.0)
			return m
	var sm := StandardMaterial3D.new()
	sm.albedo_color = fallback
	sm.roughness = 1.0
	return sm


## End grain: growth rings, a darker heart, a few radial checks -- one shared
## texture, tinted per species. Rings in the same "realistic pixeled" register
## as the bark: nearest-filtered cells, a posterised palette.
static func grain_material(species: String) -> StandardMaterial3D:
	var key := species if GRAIN_TINT.has(species) else ""
	if _grain_mats.has(key):
		return _grain_mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = grain_texture()
	m.albedo_color = GRAIN_TINT.get(key, GRAIN_DEFAULT)
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.texture_repeat = false
	m.resource_name = "end_grain_" + (key if key != "" else "wood")
	_grain_mats[key] = m
	return m


static func grain_texture() -> ImageTexture:
	if _grain_tex != null:
		return _grain_tex
	var img := grain_image(CAP_GRAIN_PX, 20260914)
	_grain_tex = ImageTexture.create_from_image(img)
	return _grain_tex


## The rings themselves. Deterministic on `seed`; greys-and-creams, meant to
## be tinted. Exposed so a test can look at it without a renderer.
static func grain_image(px: int, sd: int) -> Image:
	var img := Image.create_empty(px, px, true, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	var checks: Array = []
	for i in range(rng.randi_range(3, 5)):
		checks.append([rng.randf_range(0.0, TAU), rng.randf_range(0.35, 1.0)])   ## angle, reach
	var ring_n := 9.0
	for yy in range(px):
		for xx in range(px):
			var dx := (float(xx) + 0.5) / float(px) - 0.5
			var dy := (float(yy) + 0.5) / float(px) - 0.5
			var r := sqrt(dx * dx + dy * dy) * 2.0          ## 0 centre .. 1 rim
			var a := atan2(dy, dx)
			## rings are never true circles
			var rr := r + 0.03 * sin(a * 3.0 + 1.7) + 0.02 * sin(a * 7.0 + 0.4) \
				+ (rng.randf() - 0.5) * 0.012
			var ring := fposmod(rr * ring_n, 1.0)
			var v := 0.94 if ring < 0.62 else 0.74            ## early wood / late wood
			## heart darker than sapwood
			v *= lerpf(0.80, 1.0, smoothstep(0.50, 0.66, rr))
			## pith
			if rr < 0.045:
				v *= 0.68
			## radial checks: dark hairlines from the pith outward
			for ck in checks:
				var da := absf(wrapf(a - float(ck[0]), -PI, PI))
				if rr > 0.12 and rr < float(ck[1]) and da < 0.018 + 0.010 * rr:
					v *= 0.52
			## a little grit, then onto the palette
			v *= 1.0 + (rng.randf() - 0.5) * 0.06
			v = floor(clampf(v, 0.0, 1.0) * 9.0 + 0.5) / 9.0
			img.set_pixel(xx, yy, Color(v, v * 0.90, v * 0.76))
	img.generate_mipmaps()
	return img
