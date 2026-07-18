extends RefCounted
class_name CaveMesher
## Turns one chunk of a CaveField into flat-shaded low-poly rock: naive surface
## nets (one vertex per boundary cell, quads across sign-flipping grid edges —
## no lookup tables, even topology, chunky facets). Winding/orientation logic
## sim-verified (tools note: normals face the AIR side, i.e. the player).
## Also hands back the raw triangle soup for the chunk's collision shape.

const CHUNK := 16                ## cells per chunk side
const JITTER := 0.24             ## deterministic vertex shake — hewn, not gridded

## Palette (vertex colors; material uses them as albedo)
const GRASS := Color(0.16, 0.24, 0.14)   ## matches the World ground slab
const ROCK := Color(0.30, 0.31, 0.37)    ## slate/indigo base
const FROST := Color(0.33, 0.40, 0.50)   ## cool tint, upper band
const EMBER := Color(0.40, 0.28, 0.23)   ## warmed stone, the deeps

## Cell-corner offsets and the 12 cell edges between them (index pairs).
const CORN: Array[Vector3i] = [
	Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0),
	Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1),
]
## Flat pairs (a,b, a,b, ...) — int-indexed only, no nested-array lookups.
## (Plain literal: constructor calls aren't constant expressions in GDScript.)
const CEDGE := [0, 1, 2, 3, 4, 5, 6, 7, 0, 2, 1, 3, 4, 6, 5, 7, 0, 4, 1, 5, 2, 6, 3, 7]


static func build_chunk(f: CaveField, cx: int, cy: int, cz: int) -> Dictionary:
	## Returns {mesh: ArrayMesh, faces: PackedVector3Array} or {} if empty air/rock.
	var x0 := cx * CHUNK
	var y0 := cy * CHUNK
	var z0 := cz * CHUNK
	var x1 := mini(x0 + CHUNK, CaveField.CELLS_X)
	var y1 := mini(y0 + CHUNK, CaveField.CELLS_Y)
	var z1 := mini(z0 + CHUNK, CaveField.CELLS_Z)

	var verts := {}  ## Vector3i cell -> Vector3 (computed lazily, incl. neighbors)
	var faces := PackedVector3Array()
	var cols := PackedColorArray()   ## one color per triangle

	## X-edges owned by this chunk (sample-space j/k, cell-space i).
	for i in range(x0, x1):
		for j in range(maxi(y0, 1), mini(y1, CaveField.CELLS_Y)):
			for k in range(maxi(z0, 1), mini(z1, CaveField.CELLS_Z)):
				var d0 := f.data[(i * CaveField.SY + j) * CaveField.SZ + k]
				var d1 := f.data[((i + 1) * CaveField.SY + j) * CaveField.SZ + k]
				if (d0 < 0.0) != (d1 < 0.0):
					_quad(f, verts, faces, cols, [Vector3i(i, j - 1, k - 1),
						Vector3i(i, j, k - 1), Vector3i(i, j, k), Vector3i(i, j - 1, k)], d0 < 0.0)
	## Y-edges.
	for j in range(y0, y1):
		for i in range(maxi(x0, 1), mini(x1, CaveField.CELLS_X)):
			for k in range(maxi(z0, 1), mini(z1, CaveField.CELLS_Z)):
				var d0 := f.data[(i * CaveField.SY + j) * CaveField.SZ + k]
				var d1 := f.data[(i * CaveField.SY + j + 1) * CaveField.SZ + k]
				if (d0 < 0.0) != (d1 < 0.0):
					_quad(f, verts, faces, cols, [Vector3i(i - 1, j, k - 1),
						Vector3i(i - 1, j, k), Vector3i(i, j, k), Vector3i(i, j, k - 1)], d0 < 0.0)
	## Z-edges.
	for k in range(z0, z1):
		for i in range(maxi(x0, 1), mini(x1, CaveField.CELLS_X)):
			for j in range(maxi(y0, 1), mini(y1, CaveField.CELLS_Y)):
				var d0 := f.data[(i * CaveField.SY + j) * CaveField.SZ + k]
				var d1 := f.data[(i * CaveField.SY + j) * CaveField.SZ + k + 1]
				if (d0 < 0.0) != (d1 < 0.0):
					_quad(f, verts, faces, cols, [Vector3i(i - 1, j - 1, k),
						Vector3i(i, j - 1, k), Vector3i(i, j, k), Vector3i(i - 1, j, k)], d0 < 0.0)

	if faces.is_empty():
		return {}

	## Flat-shaded mesh: every triangle gets its own normal + strata color.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri := 0
	for t in range(0, faces.size(), 3):
		var a := faces[t]
		var b := faces[t + 1]
		var c := faces[t + 2]
		## Triangles arrive CW-from-air (Godot front face); the LIGHTING normal
		## must still point at the air — that's the reversed-operand cross.
		var n := (c - a).cross(b - a)
		if n.length_squared() < 0.000001:
			n = Vector3.UP
		n = n.normalized()
		st.set_color(cols[tri])
		tri += 1
		st.set_normal(n)
		st.add_vertex(a)
		st.set_normal(n)
		st.add_vertex(b)
		st.set_normal(n)
		st.add_vertex(c)
	return {"mesh": st.commit(), "faces": faces}


static func _quad(f: CaveField, verts: Dictionary, faces: PackedVector3Array,
		cols: PackedColorArray, cells: Array, flip: bool) -> void:
	var v: Array[Vector3] = []
	for c: Vector3i in cells:
		if c.x < 0 or c.y < 0 or c.z < 0 \
				or c.x >= CaveField.CELLS_X or c.y >= CaveField.CELLS_Y or c.z >= CaveField.CELLS_Z:
			return  ## boundary edge — a missing cell means no face here
		if not verts.has(c):
			var cv := _cell_vert(f, c)
			if cv == Vector3.INF:
				return
			verts[c] = cv
		v.append(verts[c])
	if flip:  ## air on the negative side — wind the other way to face it
		v.reverse()
	## Two flat triangles; color decided once per quad from its centroid.
	## NOTE Godot's front face is CLOCKWISE — emit (0,2,1)/(0,3,2) so the
	## visible/collidable side faces the AIR (the sim verified the right-hand
	## normal (v1-v0)×(v2-v0) points at the air; CW-front is its reverse).
	var centroid := (v[0] + v[1] + v[2] + v[3]) * 0.25
	var n := (v[1] - v[0]).cross(v[2] - v[0])
	var col := _strata_color(f, centroid, n.normalized() if n.length_squared() > 0.000001 else Vector3.UP)
	faces.append(v[0]); faces.append(v[2]); faces.append(v[1])
	cols.append(col)
	faces.append(v[0]); faces.append(v[3]); faces.append(v[2])
	cols.append(col)


static func _cell_vert(f: CaveField, c: Vector3i) -> Vector3:
	## Average of this cell's edge zero-crossings + a deterministic jitter.
	var ds: Array[float] = []
	for off in CORN:
		ds.append(f.data[((c.x + off.x) * CaveField.SY + (c.y + off.y)) * CaveField.SZ + (c.z + off.z)])
	if ds.size() != 8:  ## insurance: an upstream error mid-append must not cascade
		return Vector3.INF
	var acc := Vector3.ZERO
	var n := 0
	for ei in range(0, CEDGE.size(), 2):
		var ea: int = CEDGE[ei]  ## explicit — untyped const array can't drive inference
		var eb: int = CEDGE[ei + 1]
		var d0 := ds[ea]
		var d1 := ds[eb]
		if (d0 < 0.0) != (d1 < 0.0):
			var t := d0 / (d0 - d1)
			var p0 := Vector3(CORN[ea])
			acc += p0 + (Vector3(CORN[eb]) - p0) * t
			n += 1
	if n == 0:
		return Vector3.INF
	var local := (Vector3(c) + acc / float(n)) * CaveField.VOX
	return f.origin + local + _jitter(f, c) * CaveField.VOX


static func _jitter(f: CaveField, c: Vector3i) -> Vector3:
	## The hewn-rock shake is an UNDERGROUND texture. On the open surface the
	## region must be indistinguishable from the world slab it meets — same
	## color (exact), same flatness, same lighting — so jitter fades to zero:
	##   · toward the region rim (the seam itself), and
	##   · anywhere near the surface AWAY from the entrance (the "giant patch"
	##     was flat-but-faceted grass catching light differently than the slab).
	## Relief only survives at the entrance zone and below ground.
	var edge := mini(mini(c.x, CaveField.CELLS_X - 1 - c.x), mini(c.z, CaveField.CELLS_Z - 1 - c.z))
	var fade := clampf((float(edge) * CaveField.VOX - 1.2) / 4.5, 0.0, 1.0)
	var wy := f.origin.y + (float(c.y) + 0.5) * CaveField.VOX
	if wy > -1.8 and fade > 0.0:
		var wx := f.origin.x + (float(c.x) + 0.5) * CaveField.VOX
		var wz := f.origin.z + (float(c.z) + 0.5) * CaveField.VOX
		var near_mouth := false
		for m in f.mouths:
			if Vector2(wx - m.x, wz - m.z).length() <= 13.0:
				near_mouth = true
				break
		if not near_mouth:
			fade *= clampf((-wy - 0.55) / 1.25, 0.0, 1.0)
	if fade <= 0.0:
		return Vector3.ZERO
	var s := float(c.x) * 12.9898 + float(c.y) * 78.233 + float(c.z) * 37.719
	return Vector3(
		fposmod(sin(s) * 43758.5453, 1.0) - 0.5,
		fposmod(sin(s + 1.7) * 43758.5453, 1.0) - 0.5,
		fposmod(sin(s + 4.2) * 43758.5453, 1.0) - 0.5) * (JITTER * fade)


static func _strata_color(f: CaveField, p: Vector3, n: Vector3) -> Color:
	## Grass skin up top; below, banded slate that cools mid-depth and warms
	## toward ember down in the deeps.
	## NOTE the srgb_to_linear() at every exit: material albedo_color gets an
	## sRGB→linear conversion on upload, raw VERTEX colors do not — without
	## this, the same numeric green renders visibly brighter on cave ground
	## than on the world slab. Author in sRGB, hand the shader linear.
	var depth := -p.y
	if n.y > 0.55 and depth < 1.4:
		return GRASS.srgb_to_linear()
	var c := ROCK
	var bandv := f.band.get_noise_3d(p.x * 0.6, p.y * 2.2, p.z * 0.6)  ## horizontal-ish strata
	c = c * (1.0 + bandv * 0.16)
	c = c.lerp(FROST, clampf((depth - 3.0) / 9.0, 0.0, 1.0) * 0.22)
	c = c.lerp(EMBER, clampf((depth - 23.0) / 9.0, 0.0, 1.0) * 0.55)
	c.a = 1.0
	return c.srgb_to_linear()
