class_name FortGorges
extends Node3D

## ===========================================================================
## FORT GORGES — scripts/FortGorges.gd
##
## A six-bastion granite star on a built island in Portland Harbor, due east
## of the Old Port quay. Real Fort Gorges sits on Hog Island Ledge; at this
## map's 1:47 the ledge is inside Portland's city pad, so the star is offset
## seaward onto the first all-water cell that does not eat the quay. No
## punched hole: a hole in the sea is a window into nothing. The island is
## the floor.
##
## Copy of the Knox idiom (one mesh per material, keep_probe, group "fort",
## clockwise corners, _outward / _yaw_of), not of the pentagon.
##
## SAVE CONTRACT: none. World seed, like Knox. Not trees/beds/psx_props.
## ===========================================================================

# ===========================================================================
#  Where — Portland Harbor, seaward of the Old Port
# ===========================================================================

## Bake Portland is (-85.7, 1056). The quay is the east face of a 190 m pad.
## A 60 m star on Hog Island's geo-scale seat would overlap that pad, so the
## site is the first 100 %-water footprint due east that stays outside CORE_R.
## Cell-checked against maine_water.r16: every 4 m sample in a 76 m square
## is wet, none of them sit on the city pad. See docs/FORT_GORGES.md.
const SITE_X := 172.0
const SITE_Z := 1056.0
const PORTLAND := Vector2(-85.7, 1056.0)

## Parade sits this far over sea-level. The island plants from 8 m below the
## parade (through ~2 m of harbor water into the bed) up to the paving.
const PARADE_ABOVE_SEA := 4.0
const ISLAND_BOT := -8.0
const ISLAND_R := 36.0
const PUNCHES := false

const RAMPART_Y := 5.0
const PARAPET_H := 1.6
const WALL_T := 2.2
const WALK := 3.6
const CASEMATE_D := 4.2
const PORT_SILL := 0.70
const PORT_HEAD := 3.20
const PORT_W := 1.40
const FACE_INSET := 5.0
const PORT_SPACING := 5.0
const STAIR_FACE := 4                    ## south curtain: parade → rampart
const GATE_FACE := 2                     ## east bastion, away from Portland

## Twelve corners of a hex-star, clockwise from the north tip. Even indices
## are bastion points (R = 32), odd are re-entrants (r = 24). Local +X is
## east (Portland is west), +Z is south, y = 0 is the parade. The inner
## radius is kept fat on purpose: a 67° salient ate the casemate throats.
const CORNERS: Array[Vector2] = [
	Vector2(0.00, -32.00),
	Vector2(12.00, -20.78),
	Vector2(27.71, -16.00),
	Vector2(24.00, 0.00),
	Vector2(27.71, 16.00),
	Vector2(12.00, 20.78),
	Vector2(0.00, 32.00),
	Vector2(-12.00, 20.78),
	Vector2(-27.71, 16.00),
	Vector2(-24.00, 0.00),
	Vector2(-27.71, -16.00),
	Vector2(-12.00, -20.78),
]

## West faces: casemates looking toward the Old Port.
const CASEMATE_FACES: Array[int] = [6, 8, 9, 11]

const MATS := {
	"granite": Color(0.545, 0.535, 0.515),
	"ashlar":  Color(0.600, 0.585, 0.560),
	"timber":  Color(0.300, 0.215, 0.140),
	"iron":    Color(0.170, 0.175, 0.185),
}

const INNER_VIS := 180.0

static var inst: FortGorges = null
static var _mat_cache := {}
static var keep_probe := false

var pad_y := 0.0
var seated := false
var _rng := RandomNumberGenerator.new()
var _body: StaticBody3D = null
var _boxes := {}
var _inner := {}
var _poly: PackedVector2Array = PackedVector2Array()
var probe: Array = []


# ===========================================================================
#  Build
# ===========================================================================

static func raise_fort(world: Node3D) -> FortGorges:
	if inst != null and is_instance_valid(inst):
		return inst
	if Overworld.inst == null or not Overworld.inst._loaded:
		return null
	## Open water: the island IS the floor. Never punch the sea.
	var f := FortGorges.new()
	f.name = "FortGorges"
	world.add_child(f)
	f.build()
	inst = f
	return f


static func contains(p: Vector3) -> bool:
	return absf(p.x - SITE_X) <= 38.0 and absf(p.z - SITE_Z) <= 40.0


static func build_flat(parent: Node3D) -> FortGorges:
	var f := FortGorges.new()
	f.name = "FortGorgesTest"
	parent.add_child(f)
	f.build()
	return f


func solid_at(p: Vector3) -> bool:
	for e in probe:
		var b: Dictionary = e
		var half: Vector3 = (b["size"] as Vector3) * 0.5
		var q: Vector3 = Basis.from_euler(b["rot"] as Vector3).transposed() \
			* (p - (b["pos"] as Vector3))
		if absf(q.x) <= half.x and absf(q.y) <= half.y and absf(q.z) <= half.z:
			return true
	return false


func clear_line(a: Vector3, b: Vector3, step := 0.25) -> bool:
	var n := maxi(2, int((b - a).length() / step))
	for i in range(n + 1):
		if solid_at(a.lerp(b, float(i) / float(n))):
			return false
	return true


static func arrival() -> Vector3:
	var y := 0.0
	if Overworld.inst != null and Overworld.inst._loaded:
		y = Overworld.inst.sea_level + PARADE_ABOVE_SEA
	return Vector3(SITE_X, y + 1.2, SITE_Z)


func build() -> void:
	_rng.seed = 0x474F5247        ## "GORG"
	add_to_group("fort")
	_poly = PackedVector2Array(CORNERS)
	if Overworld.inst != null and Overworld.inst._loaded:
		pad_y = Overworld.inst.sea_level + PARADE_ABOVE_SEA
		seated = true
	else:
		pad_y = 0.0
		seated = false
	position = Vector3(SITE_X, pad_y, SITE_Z)

	_body = StaticBody3D.new()
	_body.name = "Stone"
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)

	_island()
	_curtains()
	_casemates()
	_gate()
	_stair()
	_parade_dressing()
	_bake()


# ===========================================================================
#  Frame
# ===========================================================================

func _in_star(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, _poly)


func _corner(i: int) -> Vector2:
	return CORNERS[i % CORNERS.size()]


static func _outward(d: Vector2) -> Vector2:
	return Vector2(d.y, -d.x).normalized()


static func _inward(d: Vector2) -> Vector2:
	return Vector2(-d.y, d.x).normalized()


static func _yaw_of(d: Vector2) -> float:
	return atan2(d.x, d.y)


# ===========================================================================
#  Geometry primitives
# ===========================================================================

func _box(size: Vector3, pos: Vector3, mat: String, tint := 0.0,
		rot := Vector3.ZERO, collide := true, inner := false) -> void:
	if size.x <= 0.001 or size.y <= 0.001 or size.z <= 0.001:
		return
	var bucket: Dictionary = _inner if inner else _boxes
	if not bucket.has(mat):
		bucket[mat] = []
	var jitter: float = tint + _rng.randf_range(-0.055, 0.055)
	(bucket[mat] as Array).append({"size": size, "pos": pos, "rot": rot, "tint": jitter})
	if collide:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = pos
		cs.rotation = rot
		_body.add_child(cs)
		if keep_probe:
			probe.append({"size": size, "pos": pos, "rot": rot})


func _wall_run(a: Vector2, b: Vector2, t: float, y0: float, y1: float, mat: String,
		bias := 0.0, course := 1.1, inner := false,
		gaps: Array = [], gap_y := Vector2.ZERO) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.01 or y1 <= y0:
		return
	var dir := d / length
	var off := _outward(d) * bias
	var yaw := _yaw_of(d)
	var courses := maxi(1, int(ceil((y1 - y0) / course)))
	var ch := (y1 - y0) / float(courses)
	for i in range(courses):
		var cy0 := y0 + float(i) * ch
		var cy1 := cy0 + ch
		var cy := cy0 + ch * 0.5
		var batter := 0.05 * float(i)
		var tint := -0.03 if (i % 2) == 0 else 0.03
		var open: bool = not gaps.is_empty() and cy1 > gap_y.x + 0.001 and cy0 < gap_y.y - 0.001
		var spans: Array = []
		if open:
			var cursor := 0.0
			for g in gaps:
				var gv: Vector2 = g
				if gv.x > cursor:
					spans.append(Vector2(cursor, gv.x))
				cursor = maxf(cursor, gv.y)
			if cursor < length:
				spans.append(Vector2(cursor, length))
		else:
			spans.append(Vector2(0.0, length))
		for s in spans:
			var sv: Vector2 = s
			var seg := sv.y - sv.x
			if seg <= 0.05:
				continue
			var mid := a + dir * ((sv.x + sv.y) * 0.5) + off
			_box(Vector3(t - batter, ch * 0.985, seg), Vector3(mid.x, cy, mid.y),
				mat, tint, Vector3(0.0, yaw, 0.0), true, inner)


func _vault(centre: Vector3, yaw: float, span: float, length: float, thick: float,
		mat: String, segs := 7, collide := true, inner := false) -> void:
	var r := span * 0.5 + thick * 0.5
	var chord := (PI * r / float(segs)) * 1.20
	var perp := Vector3(cos(yaw), 0.0, -sin(yaw))
	for k in range(segs):
		var th := PI * (float(k) + 0.5) / float(segs)
		_box(Vector3(chord, thick, length),
			centre + perp * (cos(th) * r) + Vector3(0.0, sin(th) * r, 0.0),
			mat, 0.0, Vector3(0.0, yaw, th - PI * 0.5), collide, inner)


func _flight(a: Vector3, b: Vector3, w: float, mat: String) -> void:
	var n := maxi(1, int(round(absf(b.y - a.y) / 0.19)))
	var step := (b - a) / float(n)
	var yaw := atan2(step.x, step.z) - PI * 0.5
	var run := Vector2(step.x, step.z).length()
	for i in range(n):
		var p := a + step * (float(i) + 0.5)
		_box(Vector3(maxf(run * 1.5, 0.35), absf(step.y) + 0.24, w),
			Vector3(p.x, p.y - 0.1, p.z), mat, _rng.randf_range(-0.05, 0.03),
			Vector3(0.0, yaw, 0.0))


func _gun(at: Vector2, wall_yaw: float, y: float) -> void:
	var gy := wall_yaw + PI * 0.5
	var r := Vector3(0.0, gy, 0.0)
	_box(Vector3(1.4, 0.32, 2.2), Vector3(at.x, y + 0.18, at.y), "timber", -0.05, r, false)
	_box(Vector3(0.40, 0.40, 2.6), Vector3(at.x, y + 0.95, at.y), "iron", 0.0, r, false)


static func casemate_ts(a: Vector2, b: Vector2) -> PackedFloat32Array:
	var usable := (b - a).length() - FACE_INSET * 2.0
	var out := PackedFloat32Array()
	if usable <= PORT_SPACING * 0.6:
		return out
	var count := maxi(2, int(round(usable / PORT_SPACING)))
	for k in range(count):
		out.append(FACE_INSET + (float(k) + 0.5) * (usable / float(count)))
	return out


# ===========================================================================
#  Island — granite from below sea to the parade. No punched hole.
# ===========================================================================

func _island() -> void:
	var sea := -PARADE_ABOVE_SEA
	var cell := 4.0
	var n := int(ceil((ISLAND_R * 2.0) / cell))
	var origin := -ISLAND_R
	## Core (inside the star): merged fill up to the paving underside.
	## Rim: the same cells, stopped at a plinth just over the water.
	for j in range(n):
		var zc := origin + (float(j) + 0.5) * cell
		var run_start := -1
		var run_core := false
		for i in range(n + 1):
			var live := i < n
			var core := false
			var in_isle := false
			if live:
				var p := Vector2(origin + (float(i) + 0.5) * cell, zc)
				in_isle = p.length() <= ISLAND_R
				core = in_isle and _in_star(p)
			if live and in_isle and (run_start < 0 or core == run_core):
				if run_start < 0:
					run_start = i
					run_core = core
				continue
			if run_start >= 0:
				var a := origin + float(run_start) * cell
				var b := origin + float(i) * cell
				var top := -0.45 if run_core else (sea + 0.7)
				_box(Vector3(b - a, top - ISLAND_BOT, cell),
					Vector3((a + b) * 0.5, (top + ISLAND_BOT) * 0.5, zc),
					"granite", -0.02)
				run_start = -1
			if live and in_isle:
				run_start = i
				run_core = core

	## Parade paving: slabs only inside the star, so the yard is stone under
	## foot and open air at head height.
	var lid := 6.0
	var ln := int(ceil((ISLAND_R * 2.0) / lid))
	for j2 in range(ln):
		for i2 in range(ln):
			var c := Vector2(origin + (float(i2) + 0.5) * lid,
				origin + (float(j2) + 0.5) * lid)
			if not _in_star(c):
				continue
			_box(Vector3(lid * 0.98, 0.9, lid * 0.98), Vector3(c.x, -0.45, c.y),
				"granite", _rng.randf_range(-0.06, 0.04))


# ===========================================================================
#  Curtains, casemates, sally, stair
# ===========================================================================

func _curtains() -> void:
	for i in range(CORNERS.size()):
		var a := _corner(i)
		var b := _corner(i + 1)
		var length := (b - a).length()
		var is_case := CASEMATE_FACES.has(i)
		if is_case:
			_casemate_curtain(a, b)
		elif i == GATE_FACE:
			var mid := length * 0.5
			_wall_run(a, b, WALL_T, -0.4, RAMPART_Y, "granite", -WALL_T * 0.5, 1.15,
				false, [Vector2(mid - 1.8, mid + 1.8)], Vector2(-1.0, 4.4))
		else:
			_wall_run(a, b, WALL_T, -0.4, RAMPART_Y, "granite", -WALL_T * 0.5, 1.15)

		_wall_run(a, b, WALK, RAMPART_Y - 0.55, RAMPART_Y, "granite", -WALK * 0.5, 0.55)
		_parapet(a, b, i)

		if not is_case:
			var gaps: Array = []
			if i == GATE_FACE:
				gaps = [Vector2(length * 0.5 - 2.2, length * 0.5 + 2.2)]
			_wall_run(a, b, 0.9, 0.0, RAMPART_Y - 0.55, "granite", -(WALK - 0.45), 1.15,
				false, gaps, Vector2(-1.0, 4.2))

	for i2 in range(CORNERS.size()):
		var c := _corner(i2)
		_box(Vector3(2.6, RAMPART_Y + PARAPET_H + 0.4, 2.6),
			Vector3(c.x, (RAMPART_Y + PARAPET_H) * 0.5, c.y), "ashlar", 0.03)


func _casemate_curtain(a: Vector2, b: Vector2) -> void:
	var ts := casemate_ts(a, b)
	var gaps: Array = []
	for t: float in ts:
		gaps.append(Vector2(t - PORT_W * 0.5, t + PORT_W * 0.5))
	_wall_run(a, b, WALL_T, -0.4, PORT_SILL, "granite", -WALL_T * 0.5, 1.15)
	_wall_run(a, b, WALL_T, PORT_SILL, PORT_HEAD, "granite", -WALL_T * 0.5, 1.05,
		false, gaps, Vector2(PORT_SILL, PORT_HEAD))
	_wall_run(a, b, WALL_T, PORT_HEAD, RAMPART_Y, "granite", -WALL_T * 0.5, 1.15)
	var dir := (b - a).normalized()
	var yaw := _yaw_of(b - a)
	var out := _outward(b - a)
	for t2: float in ts:
		var p := a + dir * t2 + out * (-WALL_T * 0.5)
		for s: float in [-1.0, 1.0]:
			var j := p + dir * (s * (PORT_W * 0.5 + 0.28))
			_box(Vector3(WALL_T + 0.4, PORT_HEAD - PORT_SILL, 0.5),
				Vector3(j.x, (PORT_SILL + PORT_HEAD) * 0.5, j.y), "ashlar", 0.04,
				Vector3(0.0, yaw, 0.0), true)
		_box(Vector3(WALL_T + 0.4, 0.45, PORT_W + 1.5), Vector3(p.x, PORT_SILL - 0.22, p.y),
			"ashlar", 0.02, Vector3(0.0, yaw, 0.0), true)
		_box(Vector3(WALL_T + 0.4, 0.5, PORT_W + 1.5), Vector3(p.x, PORT_HEAD + 0.25, p.y),
			"ashlar", 0.02, Vector3(0.0, yaw, 0.0), true)


func _parapet(a: Vector2, b: Vector2, _face: int) -> void:
	var d := b - a
	var length := d.length()
	var dir := d / length
	var out := _outward(d)
	var yaw := _yaw_of(d)
	var merlons := maxi(3, int(round(length / 3.2)))
	var step := length / float(merlons)
	for m in range(merlons):
		var t := (float(m) + 0.5) * step
		var p := a + dir * t + out * (-WALL_T * 0.5)
		_box(Vector3(WALL_T * 0.95, PARAPET_H, step * 0.60),
			Vector3(p.x, RAMPART_Y + PARAPET_H * 0.5, p.y), "granite",
			_rng.randf_range(-0.05, 0.05), Vector3(0.0, yaw, 0.0))
		if m < merlons - 1:
			var q := a + dir * (t + step * 0.5) + out * (-WALL_T * 0.5)
			_box(Vector3(WALL_T * 0.95, 0.50, step * 0.40),
				Vector3(q.x, RAMPART_Y + 0.25, q.y), "granite", 0.02,
				Vector3(0.0, yaw, 0.0))


func _casemates() -> void:
	for face in CASEMATE_FACES:
		var a := _corner(face)
		var b := _corner(face + 1)
		var d := b - a
		var dir := d.normalized()
		var inw := _inward(d)
		var yaw := _yaw_of(d)
		var ts := casemate_ts(a, b)
		var pitch := PORT_SPACING
		if ts.size() > 1:
			pitch = ts[1] - ts[0]
		for t: float in ts:
			var c := a + dir * t + inw * (WALL_T * 0.5 + CASEMATE_D * 0.5)
			_casemate(c, yaw, pitch, inw, dir)


func _casemate(c: Vector2, yaw: float, width: float, inw: Vector2, dir: Vector2) -> void:
	var clear := clampf(width - 2.4, 2.8, 4.8)
	var spring := 3.05
	## local +X through the wall, +Z along it: piers are (depth, height, width).
	for s: float in [-1.0, 1.0]:
		var p := c + dir * (s * (clear * 0.5 + 0.85))
		_box(Vector3(CASEMATE_D * 0.92, spring, 1.6), Vector3(p.x, spring * 0.5, p.y),
			"granite", 0.02, Vector3(0.0, yaw, 0.0), true, true)
	## Vault sits toward the curtain, not as a bulkhead on the parade arch.
	var vc := c - inw * 0.35
	_vault(Vector3(vc.x, spring, vc.y), yaw + PI * 0.5, clear, CASEMATE_D * 0.82, 0.7,
		"granite", 7, true, true)
	_box(Vector3(CASEMATE_D, 0.35, clear + 1.6), Vector3(c.x, -0.18, c.y), "granite",
		-0.05, Vector3(0.0, yaw, 0.0), true, true)
	_gun(c - inw * 1.1, yaw, 0.0)


func _gate() -> void:
	var a := _corner(GATE_FACE)
	var b := _corner(GATE_FACE + 1)
	var d := b - a
	var mid := (a + b) * 0.5
	var inw := _inward(d)
	var out := _outward(d)
	var yaw := _yaw_of(d)
	var clear := 3.2
	var depth := WALL_T + 3.6
	for s: float in [-1.0, 1.0]:
		var p := mid + d.normalized() * (s * (clear * 0.5 + 1.2)) + inw * 1.2
		_box(Vector3(depth, 4.6, 2.4), Vector3(p.x, 2.3, p.y), "ashlar", 0.03,
			Vector3(0.0, yaw, 0.0))
	_box(Vector3(depth, 1.2, clear + 4.8),
		Vector3(mid.x + inw.x * 1.2, 4.5, mid.y + inw.y * 1.2),
		"ashlar", 0.02, Vector3(0.0, yaw, 0.0))
	## granite landing, low enough that the sally stays a hole at head height
	var jet := mid + out * (WALL_T * 0.5 + 3.5)
	_box(Vector3(7.0, 0.45, 4.2), Vector3(jet.x, -0.22, jet.y), "granite", -0.04,
		Vector3(0.0, yaw, 0.0))
	_box(Vector3(7.0, -ISLAND_BOT - 0.4, 1.1),
		Vector3(jet.x + out.x * 2.6, (ISLAND_BOT - 0.2) * 0.5, jet.y + out.y * 2.6),
		"granite", -0.06, Vector3(0.0, yaw, 0.0))


func _stair() -> void:
	var a := _corner(STAIR_FACE)
	var b := _corner(STAIR_FACE + 1)
	var inw := _inward(b - a)
	var top := (a + b) * 0.5 + inw * (WALL_T + 1.5)
	var base := top + inw * 7.5
	_flight(Vector3(base.x, -0.2, base.y), Vector3(top.x, RAMPART_Y - 0.55, top.y),
		2.4, "granite")


func _parade_dressing() -> void:
	_box(Vector3(0.28, 9.5, 0.28), Vector3(0.0, 4.75, -6.0), "timber", 0.06)
	_box(Vector3(2.0, 0.4, 2.0), Vector3(0.0, 0.20, -6.0), "ashlar", 0.02)
	## a cistern rim — siege water, no well shaft through the island
	for k in range(8):
		var ang := TAU * float(k) / 8.0
		_box(Vector3(0.45, 0.85, 0.85),
			Vector3(cos(ang) * 1.45, 0.42, sin(ang) * 1.45 + 4.0), "granite", 0.02,
			Vector3(0.0, -ang, 0.0))


# ===========================================================================
#  Bake — one ArrayMesh per material per layer
# ===========================================================================

func _bake() -> void:
	for mat_id in _boxes.keys():
		var mi := _mesh_of(_boxes[mat_id] as Array, str(mat_id))
		if mi != null:
			mi.name = "Shell_" + str(mat_id)
			add_child(mi)
	for mat_id2 in _inner.keys():
		var mi2 := _mesh_of(_inner[mat_id2] as Array, str(mat_id2))
		if mi2 != null:
			mi2.name = "Inner_" + str(mat_id2)
			mi2.visibility_range_end = INNER_VIS
			mi2.visibility_range_end_margin = 24.0
			add_child(mi2)
	_boxes.clear()
	_inner.clear()


const _FACE_N: Array[Vector3] = [
	Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0),
	Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0),
]
const _FACE_V := [
	[Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)],
	[Vector3(1, -1, -1), Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1)],
	[Vector3(1, -1, 1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1)],
	[Vector3(-1, -1, -1), Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1)],
	[Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(-1, 1, -1)],
	[Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(-1, -1, 1)],
]
const _WIND: Array[int] = [0, 1, 2, 0, 2, 3]


func _mesh_of(boxes: Array, mat_id: String) -> MeshInstance3D:
	if boxes.is_empty():
		return null
	var base: Color = MATS["granite"]
	if MATS.has(mat_id):
		base = MATS[mat_id]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for entry in boxes:
		var b: Dictionary = entry
		var size: Vector3 = b["size"]
		var half := size * 0.5
		var bas := Basis.from_euler(b["rot"] as Vector3)
		var origin: Vector3 = b["pos"]
		var t: float = b["tint"]
		var col := base.lightened(t) if t > 0.0 else base.darkened(-t)
		for f in range(6):
			var n: Vector3 = bas * _FACE_N[f]
			var quad: Array = _FACE_V[f]
			var p: Array = []
			for c in range(4):
				var s: Vector3 = quad[c]
				p.append(origin + bas * Vector3(s.x * half.x, s.y * half.y, s.z * half.z))
			var fc := col
			if f == 5:
				fc = col.darkened(0.20)
			elif f == 4:
				fc = col.lightened(0.05)
			for idx in _WIND:
				st.set_normal(n)
				st.set_color(fc)
				st.add_vertex(p[idx])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _material(mat_id)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi


static func _material(id: String) -> StandardMaterial3D:
	if _mat_cache.has(id):
		return _mat_cache[id]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.55 if id == "iron" else 0.94
	m.metallic = 0.55 if id == "iron" else 0.0
	m.metallic_specular = 0.05
	_mat_cache[id] = m
	return m
