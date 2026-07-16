extends Node3D
class_name Cave
## A procedural underground cave, built entirely in code:
##   - a rocky surface mouth (pillars, lintel, boulder gully, glowing crystals)
##   - a sloping entry tunnel that dives through the ground slab
##   - a seeded network of chambers on a coarse grid (drunk walk with branches),
##     connected by walkable tunnels through real doorways
##   - stalagmites, stalactites, rubble, and crystal light in every chamber
##   - a few cave dwellers lurking in the deeper rooms
## Dungeons and the "shifting caves" behavior come later (roadmap step 9).

const WALL_T := 0.5
const TUNNEL_W := 3.0    ## interior width of tunnels
const TUNNEL_H := 3.2    ## interior height of tunnels
const DOOR_W := 3.6      ## doorway cut into chamber walls
const DOOR_H := 3.4
const GRID := 19.0       ## spacing of the chamber grid (wider = room for bigger caverns + real tunnels)
const RAMP_RUN := 22.0   ## nominal horizontal run of the entry ramp (World.gd assumes first chamber at +29)
const CEIL_LIMIT := -1.5 ## dome apexes never rise above this, so caverns stay under the ground slab
const SECT := 9          ## perimeter verts of a tunnel cross-section: 2 flat-floor corners + a 7-vert arch

var mouth := Vector3.ZERO      ## surface position of the cave mouth (y = 0)
var dir := Vector3(1, 0, 0)    ## axis-aligned direction the cave descends toward
var cave_seed := 0
var occupied := {}             ## shared between caves so networks never overlap

var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()   ## coherent wall bulges for tunnels + domes
var _rock_mat: StandardMaterial3D
var _dark_mat: StandardMaterial3D

## cell (Vector2i) -> {center: Vector3 (y = floor height), w, d, h, doors: {side: true}}
var _chambers := {}
var _edges := []               ## connected pairs of cells


func _ready() -> void:
	_rng.seed = cave_seed
	_noise.seed = cave_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.5
	_rock_mat = StandardMaterial3D.new()
	_rock_mat.albedo_color = Color(0.24, 0.23, 0.26)
	_rock_mat.roughness = 1.0
	_dark_mat = StandardMaterial3D.new()
	_dark_mat.albedo_color = Color(0.14, 0.13, 0.15)
	_dark_mat.roughness = 1.0

	_plan_layout()
	_build_mouth()
	_build_hill()
	_build_ramp()
	for cell: Vector2i in _chambers.keys():
		_build_chamber(cell)
	for e: Array in _edges:
		_build_tunnel(e[0], e[1])
	_place_ore_veins()
	_spawn_dwellers()


## ============================ Layout planning =============================


func _cell_world(cell: Vector2i) -> Vector3:
	## World position of a chamber cell. The first chamber sits past the ramp.
	var first := mouth + dir * (RAMP_RUN + 7.0)
	return Vector3(first.x + cell.x * GRID, 0.0, first.z + cell.y * GRID)


func _gkey(world_pos: Vector3) -> Vector2i:
	## Key into the world-wide occupancy grid (shared across caves).
	return Vector2i(roundi(world_pos.x / GRID), roundi(world_pos.z / GRID))


func _make_chamber(cell: Vector2i, fy: float) -> Dictionary:
	var c := _cell_world(cell)
	c.y = fy
	var r := _rng.randf_range(6.0, 8.2)   ## wider caverns; the dome adds the real volume overhead
	return {
		"center": c,
		"r": r,          ## round rooms now — radius drives walls + doorways
		"w": r * 2.0,    ## kept for decoration bounds
		"d": r * 2.0,
		"h": _rng.randf_range(5.0, 6.8),  ## wall height; dome rises above this
		"doors": {},
	}


func _set_door(cell: Vector2i, side: Vector2i) -> void:
	(_chambers[cell].doors as Dictionary)[side] = true


func _shuffled_dirs() -> Array[Vector2i]:
	## Candidate directions shuffled with our own RNG (deterministic per seed).
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for i in range(dirs.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := dirs[i]
		dirs[i] = dirs[j]
		dirs[j] = tmp
	return dirs


func _shuffled_cells() -> Array:
	var cells: Array = _chambers.keys()
	for i in range(cells.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = cells[i]
		cells[i] = cells[j]
		cells[j] = tmp
	return cells


func _door_count(cell: Vector2i) -> int:
	return (_chambers[cell].doors as Dictionary).size()


func _has_junction() -> bool:
	for cell: Vector2i in _chambers.keys():
		if _door_count(cell) >= 3:
			return true
	return false


func _try_add_chamber(cur: Vector2i, d: Vector2i, forbidden: Vector2i) -> bool:
	var nxt := cur + d
	if nxt == forbidden or _chambers.has(nxt):
		return false
	var wpos := _cell_world(nxt)
	if maxf(absf(wpos.x), absf(wpos.z)) > 90.0:
		return false  ## stay under the ground slab (it spans ±104)
	if occupied.has(_gkey(wpos)):
		return false  ## another cave (or our ramp) is already there
	var fy := clampf(float(_chambers[cur].center.y) + _rng.randf_range(-2.5, 2.5), -16.0, -11.0)
	_chambers[nxt] = _make_chamber(nxt, fy)
	occupied[_gkey(wpos)] = true
	_edges.append([cur, nxt])
	_set_door(cur, d)
	_set_door(nxt, -d)
	return true


func _plan_layout() -> void:
	var dir_cell := Vector2i(int(dir.x), int(dir.z))
	var start := Vector2i.ZERO
	var forbidden := start - dir_cell   ## the ramp corridor — never build over it

	## Claim the ramp line and the start chamber in the shared occupancy grid.
	var steps := int(RAMP_RUN / (GRID * 0.5)) + 2
	for i in range(steps):
		occupied[_gkey(mouth + dir * (float(i) * GRID * 0.5))] = true
	occupied[_gkey(_cell_world(start))] = true

	_chambers[start] = _make_chamber(start, -13.0 + _rng.randf_range(-1.5, 1.5))
	var cells: Array[Vector2i] = [start]
	var count := _rng.randi_range(6, 9)
	var cur := start
	var guard := 0
	while _chambers.size() < count and guard < 80:
		guard += 1
		if _rng.randf() < 0.5:
			cur = cells[_rng.randi_range(0, cells.size() - 1)]  ## branch off an older room
		var moved := false
		for d in _shuffled_dirs():
			if _try_add_chamber(cur, d, forbidden):
				cells.append(cur + d)
				cur = cur + d
				moved = true
				break
		if not moved:
			cur = cells[_rng.randi_range(0, cells.size() - 1)]

	## Loop pass: sometimes link two adjacent rooms that grew apart, so routes
	## circle back instead of always dead-ending.
	var looped := false
	for cell: Vector2i in _shuffled_cells():
		if looped:
			break
		for d in _shuffled_dirs():
			var nxt := cell + d
			if _chambers.has(nxt) and not (_chambers[cell].doors as Dictionary).has(d) and _rng.randf() < 0.5:
				_edges.append([cell, nxt])
				_set_door(cell, d)
				_set_door(nxt, -d)
				looped = true
				break

	## Guarantee at least one true 3-way junction (three tunnels off one room).
	if not _has_junction():
		for cell: Vector2i in _shuffled_cells():
			if _door_count(cell) >= 2:
				for d in _shuffled_dirs():
					if _try_add_chamber(cell, d, forbidden):
						break
				if _has_junction():
					break

	## The entry ramp comes in through the mouth-facing wall of the start chamber.
	_set_door(start, -dir_cell)


## ============================ Building blocks =============================


func _solid_box(parent: Node3D, size: Vector3, pos: Vector3, mat: StandardMaterial3D, rot := Vector3.ZERO) -> StaticBody3D:
	var b := StaticBody3D.new()
	parent.add_child(b)
	b.position = pos
	b.rotation_degrees = rot
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	b.add_child(col)
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.material_override = mat
	b.add_child(m)
	return b


func _frame(tangent: Vector3) -> Array:
	## An un-rolled local frame for a cross-section: right + up stay near world-up
	## so the flat floor strip reads level (or evenly sloped), never barrel-rolled.
	var f := tangent.normalized()
	var up := Vector3.UP
	if absf(f.dot(up)) > 0.98:
		up = Vector3.FORWARD
	var right := f.cross(up).normalized()
	up = right.cross(f).normalized()
	return [right, up]


func _ring_verts(center: Vector3, right: Vector3, up: Vector3, hw: float, hh: float) -> Array:
	## One cross-section ring: two fixed floor corners (flat, walkable) with a
	## rounded, noise-bulged arch sweeping between them. SECT verts total.
	var pts: Array = []
	pts.append(center + right * hw)                         ## floor corner (right)
	for j in range(1, SECT - 1):                            ## the arch
		var tt := float(j) / float(SECT - 1)
		var ang := lerpf(deg_to_rad(10.0), deg_to_rad(170.0), tt)
		var probe := center + right * cos(ang) * hw + up * sin(ang) * hh
		var wob := 1.0 + _noise.get_noise_3d(probe.x, probe.y + float(j) * 7.0, probe.z) * 0.16
		var x := cos(ang) * hw * wob
		var y := (0.62 + sin(ang) * 0.55) * hh * wob        ## walls ~0.7H at the sides, ~1.17H domed center
		pts.append(center + right * x + up * y)
	pts.append(center - right * hw)                         ## floor corner (left); wrap back = flat floor
	return pts


func _add_tri(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, inward: Vector3) -> void:
	## Emit a flat-shaded triangle wound so its front face (and normal) point
	## toward 'inward' — i.e. into the hollow the player stands in.
	var a := v0
	var b := v1
	var c := v2
	var n := (b - a).cross(c - a)
	if n.length() < 1e-7:
		return
	n = n.normalized()
	var centroid := (a + b + c) / 3.0
	if n.dot(inward - centroid) < 0.0:
		var tmp := b
		b = c
		c = tmp
		n = -n
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_normal(n)
	st.add_vertex(c)


func _shell_body(mesh: ArrayMesh, mat: StandardMaterial3D) -> void:
	## Wrap a generated hollow mesh in a StaticBody with matching trimesh collision.
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var body := StaticBody3D.new()
	add_child(body)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	var col := CollisionShape3D.new()
	col.shape = mesh.create_trimesh_shape()
	body.add_child(col)


func _swept_tube(from: Vector3, to: Vector3, hw: float, hh: float, bow: float, sag: float, flare_a: float, flare_b: float) -> void:
	## A full, round, natural-looking passage: a gently bowed/sagged path with a
	## flat-floored rounded arch lofted along it, flaring wider at flared ends so
	## it opens into the rooms. Flat floor keeps it walkable; noise makes it rock.
	var axis := to - from
	var length := axis.length()
	if length < 0.2:
		return
	var perp := Vector3(-axis.z, 0.0, axis.x)
	perp = perp.normalized() if perp.length() > 0.001 else Vector3(1, 0, 0)
	## Quadratic-bezier control chosen so the curve passes through a bowed midpoint.
	var mid := (from + to) * 0.5 + perp * (_rng.randf_range(-1.0, 1.0) * bow) + Vector3(0, -sag, 0)
	var ctrl := mid * 2.0 - (from + to) * 0.5
	var nseg := clampi(int(length / 1.6) + 2, 3, 22)

	var centers: Array = []
	var rights: Array = []
	var ups: Array = []
	var rings: Array = []
	for i in range(nseg + 1):
		var t := float(i) / float(nseg)
		var omt := 1.0 - t
		var p := from * (omt * omt) + ctrl * (2.0 * omt * t) + to * (t * t)
		var tang := (ctrl - from) * (2.0 * omt) + (to - ctrl) * (2.0 * t)
		var fr := _frame(tang)
		var fa := clampf(1.0 - t / 0.30, 0.0, 1.0)          ## flare ramp near the start
		var fb := clampf(1.0 - (1.0 - t) / 0.30, 0.0, 1.0)  ## flare ramp near the end
		var flare := 1.0 + flare_a * fa + flare_b * fb
		centers.append(p)
		rights.append(fr[0])
		ups.append(fr[1])
		rings.append(_ring_verts(p, fr[0], fr[1], hw * flare, hh))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(nseg):
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		var cref: Vector3 = (centers[i] + centers[i + 1]) * 0.5 + (ups[i] as Vector3) * (hh * 0.5)
		for k in range(SECT):
			var k2 := (k + 1) % SECT
			_add_tri(st, r0[k], r0[k2], r1[k2], cref)
			_add_tri(st, r0[k], r1[k2], r1[k], cref)
	_shell_body(st.commit(), _rock_mat)


func _build_dome(c: Vector3, base_r: float, r: float, h: float) -> void:
	## A low-poly domed cavern ceiling capping a room, bulged with noise. Height is
	## clamped so the apex never punches up through the ground slab.
	var base_y := c.y + h - 0.3
	var dome_h := clampf(0.55 * r, 0.0, maxf(0.0, CEIL_LIMIT - base_y))
	if dome_h < 0.6:
		## Not enough headroom for a dome here — cap it flat instead.
		_solid_cylinder(base_r, WALL_T, Vector3(c.x, c.y + h + WALL_T * 0.5, c.z), _rock_mat)
		return
	var LAT := 4
	var LON := 12
	var apex := Vector3(c.x, base_y + dome_h, c.z)
	var iref := Vector3(c.x, base_y + dome_h * 0.35, c.z)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var drings: Array = []
	for la in range(LAT + 1):
		var v := float(la) / float(LAT)
		var ry := base_y + sin(v * PI * 0.5) * dome_h
		var rr := base_r * cos(v * PI * 0.5)
		var ring: Array = []
		for lo in range(LON):
			var ang := TAU * float(lo) / float(LON)
			var wob := 1.0 + _noise.get_noise_3d(c.x + cos(ang) * rr, ry + float(la) * 5.0, c.z + sin(ang) * rr) * 0.12
			ring.append(Vector3(c.x + cos(ang) * rr * wob, ry, c.z + sin(ang) * rr * wob))
		drings.append(ring)
	for la in range(LAT):
		var r0: Array = drings[la]
		var r1: Array = drings[la + 1]
		for lo in range(LON):
			var lo2 := (lo + 1) % LON
			if la == LAT - 1:
				_add_tri(st, r0[lo], r0[lo2], apex, iref)
			else:
				_add_tri(st, r0[lo], r0[lo2], r1[lo2], iref)
				_add_tri(st, r0[lo], r1[lo2], r1[lo], iref)
	_shell_body(st.commit(), _rock_mat)


func _door_point(cell: Vector2i, side: Vector2i) -> Vector3:
	## Floor-level center of a doorway, on the round wall at radius r.
	var ch: Dictionary = _chambers[cell]
	var p: Vector3 = ch.center
	var r := float(ch.r)
	if side.x != 0:
		p.x += side.x * r
	else:
		p.z += side.y * r
	return p


func _build_ramp() -> void:
	var dir_cell := Vector2i(int(dir.x), int(dir.z))
	var door := _door_point(Vector2i.ZERO, -dir_cell)
	var a := mouth - dir * 2.0
	var b := door + dir * 0.8
	## A wide, SOLID entry apron under the round mouth so the walk-in fully covers
	## the ground-slab hole (4.2m wide) — no side gaps to fall through into the void.
	_build_entry_floor(a, b)
	## Round entry tunnel, straight (bow 0) so it lines up with the apron; flare the
	## mouth wide (covers the hole) and the deep end (opens into the first chamber).
	_swept_tube(a, b, TUNNEL_W * 0.5, TUNNEL_H, 0.0, 0.0, 0.5, 0.45)


func _build_entry_floor(a: Vector3, b: Vector3) -> void:
	## A thick, solid plank down the first stretch of the ramp — wider than the
	## ground-slab hole — so the mouth has bulletproof footing before the round
	## tube walls take over and enclose you.
	var run := b - a
	var ea := a + run * 0.02
	var eb := a + run * 0.42
	var axis := eb - ea
	if axis.length() < 0.5:
		return
	var seg := Node3D.new()
	add_child(seg)
	seg.transform = Transform3D(Basis.looking_at(axis.normalized(), Vector3.UP), (ea + eb) * 0.5)
	_solid_box(seg, Vector3(4.8, 0.6, axis.length() + 1.0), Vector3(0, -0.3, 0), _dark_mat)


func _build_tunnel(a: Vector2i, b: Vector2i) -> void:
	var d2 := b - a
	var side := Vector2i(signi(d2.x), signi(d2.y))
	var dirv := Vector3(float(side.x), 0.0, float(side.y))
	var pa := _door_point(a, side) - dirv * 0.8
	var pb := _door_point(b, -side) + dirv * 0.8
	_swept_tube(pa, pb, TUNNEL_W * 0.5, TUNNEL_H, 0.9, 0.35, 0.42, 0.42)


func _solid_cylinder(radius: float, height: float, pos: Vector3, mat: StandardMaterial3D) -> void:
	## Faceted low-poly disc (used for round floors/ceilings), with collision.
	var b := StaticBody3D.new()
	add_child(b)
	b.position = pos
	var col := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = radius
	cs.height = height
	col.shape = cs
	b.add_child(col)
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 12
	m.mesh = cm
	m.material_override = mat
	b.add_child(m)


func _side_angle(side: Vector2i) -> float:
	var a := atan2(float(side.y), float(side.x))
	if a < 0.0:
		a += TAU
	return a


func _build_chamber(cell: Vector2i) -> void:
	var ch: Dictionary = _chambers[cell]
	var c: Vector3 = ch.center
	var r := float(ch.r)
	var h := float(ch.h)
	## Round floor + ceiling discs, oversized to cover the wonky wall ring.
	var disc_r := r * 1.18 + WALL_T
	_solid_cylinder(disc_r, WALL_T, Vector3(c.x, c.y - WALL_T * 0.5, c.z), _dark_mat)  ## flat, walkable floor
	_build_dome(c, disc_r, r, h)                                                       ## domed cavern ceiling
	_build_round_walls(c, r, h, ch.doors as Dictionary)
	_decorate_chamber(ch)


func _build_round_walls(c: Vector3, r: float, h: float, doors: Dictionary) -> void:
	## A ring of faceted wall panels — a wonky cylinder. Panels near a doorway
	## direction are omitted to leave the opening, and a lintel caps each door.
	var seg_count := 12
	var step := TAU / float(seg_count)

	## Facet centers land on i*step, so cardinal door directions (0/90/180/270)
	## each sit on a facet center — removing that facet gives a clean opening.
	var skip := {}
	for side: Vector2i in doors.keys():
		var idx := int(round(_side_angle(side) / step))
		skip[((idx % seg_count) + seg_count) % seg_count] = true

	for i in range(seg_count):
		if skip.has(i):
			continue
		var a := float(i) * step
		var rr := r * _rng.randf_range(0.90, 1.14)          ## wonky radius
		var hh := h * _rng.randf_range(0.90, 1.0)
		var seg_w := 2.0 * rr * sin(step * 0.5) + WALL_T * 1.6  ## chord + overlap
		var px := c.x + cos(a) * (rr + WALL_T * 0.5)
		var pz := c.z + sin(a) * (rr + WALL_T * 0.5)
		var py := c.y + hh * 0.5 + _rng.randf_range(-0.15, 0.15)
		var rot := Vector3(_rng.randf_range(-6, 6), 90.0 - rad_to_deg(a) + _rng.randf_range(-7, 7), _rng.randf_range(-6, 6))
		_solid_box(self, Vector3(seg_w, hh + WALL_T, WALL_T), Vector3(px, py, pz), _rock_mat, rot)

	## Cap the top of each doorway so there's no gap above the tunnel.
	for side: Vector2i in doors.keys():
		var da := _side_angle(side)
		var gap_h := h - TUNNEL_H
		if gap_h > 0.15:
			var lx := c.x + cos(da) * r
			var lz := c.z + sin(da) * r
			var ly := c.y + TUNNEL_H + gap_h * 0.5
			_solid_box(self, Vector3(DOOR_W + 1.4, gap_h + WALL_T, WALL_T), Vector3(lx, ly, lz), _rock_mat, Vector3(0, 90.0 - rad_to_deg(da), 0))


## ============================ Surface dressing ============================


func _build_mouth() -> void:
	var perp := Vector3(-dir.z, 0.0, dir.x)
	## Weathered pillars + a lintel framing the opening.
	for s: float in [-1.0, 1.0]:
		var p := mouth - dir * 2.0 + perp * s * (TUNNEL_W * 0.5 + 1.15)
		_solid_box(self, Vector3(1.5, 5.4, 1.5), p + Vector3(0, 2.1, 0), _rock_mat,
			Vector3(_rng.randf_range(-6, 6), _rng.randf_range(0, 360), _rng.randf_range(-6, 6)))
	var lin_size := Vector3(1.6, 1.4, TUNNEL_W + 4.0) if dir.x != 0.0 else Vector3(TUNNEL_W + 4.0, 1.4, 1.6)
	_solid_box(self, lin_size, mouth - dir * 2.0 + Vector3(0, 4.6, 0), _rock_mat,
		Vector3(0, 0, _rng.randf_range(-4, 4)))
	## A boulder gully along the first stretch, hiding the tunnel's buried shoulders.
	for i in range(8):
		var t := _rng.randf_range(-1.0, 9.0)
		var s2 := -1.0 if i % 2 == 0 else 1.0
		var sz := _rng.randf_range(1.4, 2.7)
		var p2 := mouth + dir * t + perp * s2 * (TUNNEL_W * 0.5 + WALL_T + sz * 0.45)
		_solid_box(self, Vector3(sz, sz * 0.9, sz), p2 + Vector3(0, sz * 0.25, 0), _rock_mat,
			Vector3(_rng.randf_range(-14, 14), _rng.randf_range(0, 360), _rng.randf_range(-14, 14)))
	## Crystals flanking the mouth so it glows faintly at dusk.
	_crystal(mouth - dir * 2.4 + perp * (TUNNEL_W * 0.5 + 0.5), true)
	_crystal(mouth - dir * 2.4 - perp * (TUNNEL_W * 0.5 + 0.5), false)


func _deco_box(size: Vector3, pos: Vector3, mat: StandardMaterial3D, rot := Vector3.ZERO) -> void:
	## Mesh-only block (no collision) — cheap surface dressing.
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot
	add_child(m)


func _hill_lump(pos: Vector3, sz: float, hgt: float, bottom_y: float, dirt: StandardMaterial3D, grass: StandardMaterial3D) -> void:
	## Torn-earth clump: a scatter of many tiny dirt-brown cubes, most capped with
	## broken chunks of green grass, so the ground reads as ripped open. Fills a
	## ~sz footprint, piling higher toward the center (up to ~hgt), based at bottom_y.
	var count := int(clampf(sz * 3.2, 6.0, 20.0))
	for _i in range(count):
		var bx := _rng.randf_range(-sz * 0.5, sz * 0.5)
		var bz := _rng.randf_range(-sz * 0.5, sz * 0.5)
		var edge := clampf(Vector2(bx, bz).length() / (sz * 0.5 + 0.01), 0.0, 1.0)
		var stack := (1.0 - edge) * hgt * _rng.randf_range(0.45, 1.0)
		var y := bottom_y + _rng.randf_range(0.0, maxf(0.1, stack))
		var bsz := _rng.randf_range(0.28, 0.66)
		var rot := Vector3(_rng.randf_range(-24, 24), _rng.randf_range(0, 360), _rng.randf_range(-24, 24))
		_deco_box(Vector3(bsz, bsz, bsz), pos + Vector3(bx, y + bsz * 0.5, bz), dirt, rot)
		## Broken grass turf chunk sitting on top of most blocks.
		if _rng.randf() < 0.78:
			var gsz := bsz * _rng.randf_range(0.55, 0.95)
			_deco_box(Vector3(gsz, gsz * 0.55, gsz),
				pos + Vector3(bx + _rng.randf_range(-0.08, 0.08), y + bsz + gsz * 0.25, bz + _rng.randf_range(-0.08, 0.08)),
				grass, rot)


func _build_hill() -> void:
	## A grassy dirt mound hugging the mouth and arching over the opening, so the
	## entrance reads as a little green hill with a hole in it. The walk-in lane
	## and the tunnel interior are kept clear (lump bases stay above the tunnel
	## ceiling, and nothing sits in front of the doorway).
	var perp := Vector3(-dir.z, 0.0, dir.x)
	var dirt := StandardMaterial3D.new()
	dirt.albedo_color = Color(0.30, 0.21, 0.13)
	dirt.roughness = 1.0
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.17, 0.29, 0.14)
	grass.roughness = 1.0

	## A dense, WALKABLE, LOW blanket that tightly covers the whole cave top:
	## solid flat-topped dirt columns tiled gap-free (tiny steps = easy to walk on),
	## kept as low as possible while still fully covering, with BROKEN-UP grass
	## scattered on top so dirt shows through. Doorway + walk-in lane stay clear.
	## ~3x bigger than before: footprint, block size and height all scaled up
	## together so it stays walkable and the block count doesn't explode.
	var half := 24.0
	var step := 2.1
	var cw := step + 0.6         ## overlap so there are no gaps between blocks
	var crown := 2.2             ## rise into a big hill around/over the mouth
	var base_y := -0.9

	## The entry tunnel's line, so the blanket never seals it: columns sitting
	## over the tunnel get their BASE lifted above the tube's ceiling apex
	## (floating roof cover) instead of running full height and piercing it.
	var dir_cell := Vector2i(int(dir.x), int(dir.z))
	var tun_b := _door_point(Vector2i.ZERO, -dir_cell) + dir * 0.8
	var tun_vb := (tun_b - mouth).dot(dir)   ## along-track end of the ramp
	var tun_clear_w := TUNNEL_W * 0.5 + 1.9  ## tube half-width incl. flare + wobble

	var vv := 0.6
	while vv < 40.0:
		var uu := -half
		while uu <= half + 0.001:
			var along := clampf(vv / 40.0, 0.0, 1.0)
			var edge := clampf(absf(uu) / half, 0.0, 1.0)
			## Ramp the cover UP from the mouth so there's no lip to step over.
			var front := clampf(vv / 10.0, 0.2, 1.0)
			var surf := (0.4 + crown * (1.0 - 0.2 * along) * (1.0 - edge * edge)) * front + _rng.randf_range(-0.1, 0.1)
			## Over the tunnel: base rises to clear the tube's arched ceiling
			## (apex ≈ floor + 1.17*H, plus noise wobble — 4.4 covers it all).
			var bottom := base_y
			if absf(uu) < tun_clear_w and vv < tun_vb + 2.0:
				var tt := clampf((vv + 2.0) / (tun_vb + 2.0), 0.0, 1.0)
				var tun_floor := lerpf(0.0, tun_b.y, tt)   ## the ramp is a straight line
				bottom = maxf(base_y, tun_floor + 4.4)
			var height := surf - bottom
			if height > 0.2:
				var cpos := mouth + dir * vv + perp * uu + Vector3(0, bottom + height * 0.5, 0)
				_solid_box(self, Vector3(cw, height, cw), cpos, dirt)   ## solid = walkable
				## Grass fully caps the top (complete cover), plus broken tufts for texture.
				_deco_box(Vector3(cw + 0.1, 0.3, cw + 0.1),
					mouth + dir * vv + perp * uu + Vector3(0, surf + 0.15, 0), grass,
					Vector3(_rng.randf_range(-6, 6), _rng.randf_range(0, 360), _rng.randf_range(-6, 6)))
				for _t in range(_rng.randi_range(0, 3)):
					var gsz := _rng.randf_range(0.5, 1.0)
					var ox := _rng.randf_range(-cw * 0.4, cw * 0.4)
					var oz := _rng.randf_range(-cw * 0.4, cw * 0.4)
					_deco_box(Vector3(gsz, _rng.randf_range(0.3, 0.55), gsz),
						mouth + dir * vv + perp * uu + Vector3(ox, surf + 0.45, oz), grass,
						Vector3(_rng.randf_range(-14, 14), _rng.randf_range(0, 360), _rng.randf_range(-14, 14)))
			uu += step
		vv += step


## =============================== Decor ====================================


func _cone(pos: Vector3, h: float, r: float, hanging: bool) -> void:
	## A stalagmite (floor) or stalactite (ceiling) — faceted low-poly cone.
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 5
	m.mesh = cm
	m.material_override = _rock_mat
	add_child(m)
	if hanging:
		m.position = pos - Vector3(0, h * 0.5, 0)
		m.rotation_degrees = Vector3(180, 0, 0)
	else:
		m.position = pos + Vector3(0, h * 0.5, 0)


func _crystal(pos: Vector3, with_light: bool) -> void:
	## A small cluster of glowing crystal shards; some carry an actual light.
	var col := Color(0.35, 0.85, 1.0) if _rng.randf() < 0.7 else Color(0.72, 0.42, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.2
	for _i in range(_rng.randi_range(2, 3)):
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var s := _rng.randf_range(0.18, 0.42)
		bm.size = Vector3(s, s * _rng.randf_range(1.6, 2.6), s)
		m.mesh = bm
		m.material_override = mat
		m.position = pos + Vector3(_rng.randf_range(-0.35, 0.35), bm.size.y * 0.35, _rng.randf_range(-0.35, 0.35))
		m.rotation_degrees = Vector3(_rng.randf_range(-18, 18), _rng.randf_range(0, 360), _rng.randf_range(-18, 18))
		add_child(m)
	if with_light:
		var l := OmniLight3D.new()
		l.light_color = col
		l.light_energy = 1.2
		l.omni_range = 9.0
		l.shadow_enabled = false
		l.position = pos + Vector3(0, 1.0, 0)
		add_child(l)


func _decorate_chamber(ch: Dictionary) -> void:
	var c: Vector3 = ch.center
	var w := float(ch.w)
	var d := float(ch.d)
	var h := float(ch.h)
	## Stalagmites + stalactites, kept off the central walk lanes.
	for _i in range(_rng.randi_range(2, 4)):
		var px := _rng.randf_range(-(w * 0.5 - 1.2), w * 0.5 - 1.2)
		var pz := _rng.randf_range(-(d * 0.5 - 1.2), d * 0.5 - 1.2)
		if absf(px) < 2.2 and absf(pz) < 2.2:
			continue  ## keep the middle of the room walkable
		var hgt := _rng.randf_range(0.9, 2.2)
		_cone(Vector3(c.x + px, c.y, c.z + pz), hgt, _rng.randf_range(0.25, 0.55), false)
		if _rng.randf() < 0.6:
			_cone(Vector3(c.x + px + _rng.randf_range(-1.0, 1.0), c.y + h, c.z + pz),
				_rng.randf_range(0.7, 1.6), _rng.randf_range(0.2, 0.4), true)
	## Glowing crystals — the cave's only real light.
	var n_crystals := _rng.randi_range(1, 3)
	for i in range(n_crystals):
		var px := _rng.randf_range(-(w * 0.5 - 1.0), w * 0.5 - 1.0)
		var pz := _rng.randf_range(-(d * 0.5 - 1.0), d * 0.5 - 1.0)
		_crystal(Vector3(c.x + px, c.y, c.z + pz), i == 0)
	## Loose rubble (mesh only, walk-through).
	for _i in range(_rng.randi_range(2, 5)):
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var s := _rng.randf_range(0.2, 0.55)
		bm.size = Vector3(s, s * 0.7, s)
		m.mesh = bm
		m.material_override = _dark_mat
		m.position = Vector3(c.x + _rng.randf_range(-w * 0.4, w * 0.4), c.y + s * 0.2, c.z + _rng.randf_range(-d * 0.4, d * 0.4))
		m.rotation_degrees = Vector3(_rng.randf_range(-20, 20), _rng.randf_range(0, 360), _rng.randf_range(-20, 20))
		add_child(m)


## ============================== Ore veins =================================
## Mineable metal (docs/MATERIALS.md sourcing): SILVER seams scattered through
## the network, METEORIC almost only in the deepest room — the deep prize.
## Iron you start with; steel comes from the smart mobs that forge it (drops).


func _place_ore_veins() -> void:
	var cells: Array = _chambers.keys()
	if cells.is_empty():
		return
	cells.sort_custom(func(a, b): return _depth(a) < _depth(b))
	var deepest: Vector2i = cells[cells.size() - 1]
	for cell: Vector2i in cells:
		var ch: Dictionary = _chambers[cell]
		## Silver: roughly half the rooms carry a seam or two (never the entry —
		## the first room stays a safe breath, same rule as the dwellers).
		if cell != Vector2i.ZERO and _rng.randf() < 0.5:
			for _i in range(_rng.randi_range(1, 2)):
				_add_vein("silver", ch)
		## Meteoric: the far chamber usually hides one; a whisper of a chance
		## anywhere else deep enough.
		if cell == deepest and cells.size() >= 2:
			if _rng.randf() < 0.7:
				_add_vein("meteoric", ch)
		elif _depth(cell) >= 3 and _rng.randf() < 0.08:
			_add_vein("meteoric", ch)


func _add_vein(mat_id: String, ch: Dictionary) -> void:
	## Hug the wall so veins never squat on the walk lanes or door paths.
	var c: Vector3 = ch.center
	var a := _rng.randf() * TAU
	var rr := float(ch.r) * _rng.randf_range(0.62, 0.74)
	var v := OreVein.make(mat_id)
	add_child(v)
	v.position = Vector3(c.x + cos(a) * rr, c.y, c.z + sin(a) * rr)
	v.rotation_degrees = Vector3(0, _rng.randf() * 360.0, 0)


## ============================== Dwellers ==================================


func _depth(cell: Vector2i) -> int:
	return absi(cell.x) + absi(cell.y)


func _spawn_pack(center: Vector3, cls: Variant, count: int) -> void:
	for _i in range(count):
		var e: Enemy = cls.new()
		add_child(e)
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(0.5, 3.2)
		e.position = center + Vector3(cos(a) * r, 1.0, sin(a) * r)


func _spawn_dwellers() -> void:
	## Each room hosts a PACK; deeper rooms hold tougher kinds, and the deepest is
	## a champion room. The entry chamber stays empty so you get a beat inside.
	var cells: Array = _chambers.keys()
	cells.erase(Vector2i.ZERO)
	if cells.is_empty():
		return
	cells.sort_custom(func(a, b): return _depth(a) < _depth(b))

	for idx in range(cells.size()):
		var cell: Vector2i = cells[idx]
		var c: Vector3 = _chambers[cell].center
		if idx == cells.size() - 1 and cells.size() >= 2:
			## Champion room: a dark knight leading a couple of orcs.
			_spawn_pack(c, DarkKnight, 1)
			_spawn_pack(c, Orc, _rng.randi_range(2, 3))
			continue
		var depth := _depth(cell)
		var roll := _rng.randf()
		if depth <= 1:
			if roll < 0.6:
				_spawn_pack(c, Kobold, _rng.randi_range(6, 10))
			else:
				_spawn_pack(c, Goblin, _rng.randi_range(3, 6))
		elif depth == 2:
			if roll < 0.4:
				_spawn_pack(c, Goblin, _rng.randi_range(3, 6))
			elif roll < 0.8:
				_spawn_pack(c, Skeleton, _rng.randi_range(4, 7))
			else:
				_spawn_pack(c, Ogre, _rng.randi_range(1, 2))
		else:
			if roll < 0.4:
				_spawn_pack(c, Skeleton, _rng.randi_range(4, 7))
			elif roll < 0.75:
				_spawn_pack(c, Orc, _rng.randi_range(2, 4))
			else:
				_spawn_pack(c, Ogre, _rng.randi_range(1, 2))
