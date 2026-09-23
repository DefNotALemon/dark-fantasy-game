class_name FortKnox
extends Node3D

## ===========================================================================
## FORT KNOX — scripts/FortKnox.gd
##
## The granite work on the west bank of the Penobscot narrows, across the
## water from Bucksport. Begun in 1844 in our world and never finished; built
## here in one pass at boot and left to the moss.
##
## WHAT IT IS
##   A five-sided casemated fort standing on a granite raft cut into the
##   bluff. Two river faces of vaulted gun casemates look east over the
##   narrows through real openings in the curtain; three land faces carry a
##   rampart walk behind a dry ditch. Two granite spiral stairs — the thing
##   the real place is famous for — run from the undercroft, through the
##   parade, up to the rampart. Under the parade: a barrel-vaulted passage,
##   two powder magazines, a hot shot furnace, and a postern out to the ditch.
##
## FOUR THINGS TO KNOW BEFORE EDITING
##
## 1. THE HOLE. The tunnels are genuinely below the heightfield, so the fort
##    punches its raft rect out of the terrain — mesh AND collider — via
##    Overworld.punch_hole(). That is the same mechanism the spawn valley
##    uses for CaveRegion, generalised. The raft is what replaces the ground
##    in there, so the raft must stay watertight across the WHOLE rect or
##    you get a window into nothing. Move the fort, move the rect with it.
##
## 2. ONE MESH PER MATERIAL. Every box, voussoir and stair tread goes into
##    `_boxes` and is baked into a single ArrayMesh per material at the end,
##    so the whole fort is ~8 draw calls and not 2,000. Colour variation
##    rides in the vertex colours, which is why there is one shared material
##    per id — the exact trap the optimisation audit found in Enemy._box.
##    Never add a bare MeshInstance3D here. Put it through `_box`.
##
## 3. THE FRAME. Local +X is east (the river), +Z is south, y = 0 is the
##    parade. CORNERS run clockwise. For a wall a -> b, `_outward(b - a)` is
##    the field side and `_inward()` is the parade side — get these backwards
##    and the whole fort turns itself inside out, which it did once already.
##    `bias` in _wall_run is in OUTWARD metres.
##
## 4. IT IS BUILT ONCE AND NEVER FREED. It is a landmark: you are meant to
##    see it from the far bank. Interior meshes carry a visibility_range_end
##    so the innards stop drawing at 200 m; the shell always draws.
##
## SAVE CONTRACT: none. The fort is world seed, exactly like World's
## boulders — identical every run, so it is not serialised. It joins group
## "fort", and deliberately NOT trees/beds/psx_props, which apply_state
## sweeps on load.
## ===========================================================================

# ===========================================================================
#  Where
# ===========================================================================

## World XZ of the fort's centre: the west bank bluff over the narrows, about
## 220 m from the Bucksport marker. Checked against the bake — dry, no water
## in the footprint, ground falling 19.0 -> 13.6 eastward to the water.
const SITE_X := 2310.1
const SITE_Z := -1305.9

## The parade stands this far over the ground sample at the centre. Two
## metres puts the paving clear of the grass layer, so the parade reads as
## cut stone rather than a lawn, and the land approach earns a ramp.
const PAD_LIFT := 2.0

## The granite raft, local metres: the structural mass the fort stands on.
const RAFT_X := Vector2(-42.0, 47.0)
const RAFT_Z := Vector2(-44.0, 44.0)

## The rect actually cut out of the heightfield. Wider than the raft, because
## the dry ditch and the water battery are excavations too and cannot be dug
## into terrain that is still there. Everything between the raft and this
## edge is rebuilt by `_apron` — checked against the bake, no water cell
## anywhere inside it (the shoreline starts at local x +64).
const PUNCH_X := Vector2(-58.0, 52.0)
const PUNCH_Z := Vector2(-58.0, 58.0)

const TUNNEL_Y := -7.0                    ## undercroft floor, local
const TUNNEL_H := 3.2
const TUNNEL_X := 6.0                     ## the passage runs along Z at this x
const TUNNEL_Z := Vector2(-24.5, 24.5)
const MAG_X1 := 22.0                      ## east limit of the magazine void

const RAMPART_Y := 6.0
const PARAPET_H := 2.0
const WALL_T := 2.6
const CASEMATE_D := 7.0
const PORT_SILL := 0.75                   ## gun port, bottom and top
const PORT_HEAD := 3.9
const PORT_W := 1.5
const FACE_INSET := 5.0                   ## no gun port this close to an angle:
const PORT_SPACING := 7.0                 ## at a salient it would look into the next face
const STAIR_Z := 28.0                     ## the two spiral wells, at +/- this
const STAIR_R := 2.55                     ## clear radius inside the shaft

const DITCH_FLOOR := -4.0
const DITCH_W := 7.0

## The five corners, local metres, clockwise from the north-west land angle.
## Corner 2 is the river salient.
const CORNERS: Array[Vector2] = [
	Vector2(-38.0, -34.0),
	Vector2(22.0, -40.0),
	Vector2(43.0, -2.0),
	Vector2(22.0, 40.0),
	Vector2(-38.0, 34.0),
]
const RIVER_FACES: Array[int] = [1, 2]    ## faces 1->2 and 2->3, the casemated ones
const LAND_FACES: Array[int] = [0, 3, 4]  ## the three with a ditch in front
const GATE_FACE := 4                      ## the west curtain, 4->0: the sally port

## Outer edge of the dry ditch, measured out from the curtain line.
const DITCH_OUT := WALL_T * 0.5 + DITCH_W
const APRON_CELL := 4.0                   ## the rebuilt ground's step

# ===========================================================================
#  Granite
# ===========================================================================
const MATS := {
	"granite":  Color(0.545, 0.535, 0.515),
	"ashlar":   Color(0.600, 0.585, 0.560),
	"dark":     Color(0.300, 0.300, 0.305),
	"timber":   Color(0.300, 0.215, 0.140),
	"iron":     Color(0.170, 0.175, 0.185),
	"moss":     Color(0.235, 0.310, 0.180),
	"earth":    Color(0.300, 0.270, 0.195),
}

const INNER_VIS := 200.0

static var inst: FortKnox = null
static var _mat_cache := {}

## Tests only. With this on, every solid box is kept so `solid_at()` can say
## whether a point is inside stone — which is how the suite proves the gun
## ports are holes and the stairs have headroom, with no physics server and no
## frame to step. Off in the game: 2,500 dictionaries is not free.
static var keep_probe := false

var pad_y := 0.0
var seated := false
var _rng := RandomNumberGenerator.new()
var _body: StaticBody3D = null
var _boxes := {}
var _inner := {}
var _late := {}
var _lights: Array[OmniLight3D] = []
var probe: Array = []             ## see keep_probe


# ===========================================================================
#  Build
# ===========================================================================

## Stand the fort up inside `world`. Call once, from World._ready, AFTER
## _build_terrain() — it needs a loaded Overworld to seat the footings, and
## returns null without one rather than building a fort in mid-air.
static func raise_fort(world: Node3D) -> FortKnox:
	if inst != null and is_instance_valid(inst):
		return inst
	if Overworld.inst == null or not Overworld.inst._loaded:
		return null
	Overworld.punch_hole(hole_rect(), floor_y())
	var f := FortKnox.new()
	f.name = "FortKnox"
	world.add_child(f)
	f.build()
	inst = f
	return f


## World XZ rect of the raft: what is cut out of the heightfield.
static func hole_rect() -> Rect2:
	return Rect2(SITE_X + PUNCH_X.x, SITE_Z + PUNCH_Z.x,
		PUNCH_X.y - PUNCH_X.x, PUNCH_Z.y - PUNCH_Z.x)


## Where the punched collider is parked. Well under the undercroft floor but
## nowhere near World._out_of_world's -60 m trapdoor, so a player who somehow
## clips through the raft lands on the fort's own bottom slab instead of
## being teleported back to spawn.
static func floor_y() -> float:
	return -22.0


## True while a world point stands over the raft. World uses it so the
## underground title reads the fort's name and not "The Hollow Depths".
static func contains(p: Vector3) -> bool:
	return hole_rect().has_point(Vector2(p.x, p.z))


## Build on flat ground with no terrain and no punched hole: the headless
## suite's way in. Never call this from the game — it does not set `inst`.
static func build_flat(parent: Node3D) -> FortKnox:
	var f := FortKnox.new()
	f.name = "FortKnoxTest"
	parent.add_child(f)
	f.build()
	return f


## True when `p` (LOCAL metres) is inside solid stone. Only answers after a
## build with keep_probe on; always false otherwise.
func solid_at(p: Vector3) -> bool:
	for e in probe:
		var b: Dictionary = e
		var half: Vector3 = (b["size"] as Vector3) * 0.5
		## our rotations are pure, so the transpose is the inverse
		var q: Vector3 = Basis.from_euler(b["rot"] as Vector3).transposed() \
			* (p - (b["pos"] as Vector3))
		if absf(q.x) <= half.x and absf(q.y) <= half.y and absf(q.z) <= half.z:
			return true
	return false


## True when every sample along a -> b (LOCAL) is open air.
func clear_line(a: Vector3, b: Vector3, step := 0.25) -> bool:
	var n := maxi(2, int((b - a).length() / step))
	for i in range(n + 1):
		if solid_at(a.lerp(b, float(i) / float(n))):
			return false
	return true


## Where a fast travel to "Fort Knox" should put you: on the parade, inside.
static func arrival() -> Vector3:
	var y: float = Overworld.ground_y(Vector3(SITE_X, 0.0, SITE_Z)) + PAD_LIFT
	return Vector3(SITE_X - 14.0, y + 1.2, SITE_Z + 20.0)


func build() -> void:
	_rng.seed = 0x4B4E4F58        ## "KNOX" — fixed, so the fort is the same every run
	add_to_group("fort")
	pad_y = Overworld.ground_y(Vector3(SITE_X, 0.0, SITE_Z)) + PAD_LIFT
	seated = true
	## `position`, not `global_position`: the fort is always a direct child of
	## World (which sits at the origin), and this way build_flat still works
	## in a headless suite where nothing is a Node3D above us.
	position = Vector3(SITE_X, pad_y, SITE_Z)

	_body = StaticBody3D.new()
	_body.name = "Stone"
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)

	_raft()
	_apron()
	_undercroft()
	_curtains()
	_casemates()
	_spiral(Vector2(TUNNEL_X, -STAIR_Z), 0)
	_spiral(Vector2(TUNNEL_X, STAIR_Z), 1)
	_gate()
	_ditch()
	_water_battery()
	_parade_dressing()
	_seat_lights()
	_bake()


# ===========================================================================
#  Frame helpers
# ===========================================================================

## Ground height at a LOCAL xz, in local metres (0 = the parade).
func _ground(local: Vector2) -> float:
	var g: float = Overworld.ground_y(Vector3(SITE_X + local.x, 0.0, SITE_Z + local.y))
	return (g - pad_y) if seated else g


func _low_under(a: Vector2, b: Vector2, samples := 9) -> float:
	var lo := 1e9
	for i in range(samples + 1):
		lo = minf(lo, _ground(a.lerp(b, float(i) / float(samples))))
	return lo


func _corner(i: int) -> Vector2:
	return CORNERS[i % CORNERS.size()]


## Field side of a wall running along `d`. CORNERS are clockwise in (x, z),
## which makes this the OUTWARD normal — see note 3 in the header.
static func _outward(d: Vector2) -> Vector2:
	return Vector2(d.y, -d.x).normalized()


static func _inward(d: Vector2) -> Vector2:
	return Vector2(-d.y, d.x).normalized()


## Yaw for a box whose local +Z should run along `d` (and whose local +X
## then points along _outward(d)).
static func _yaw_of(d: Vector2) -> float:
	return atan2(d.x, d.y)


# ===========================================================================
#  Geometry primitives — everything goes through these
# ===========================================================================

## Queue one box. `rot` is euler radians in Godot's default YXZ order, which
## composes as Y(yaw) * X(pitch) * Z(roll) — so Vector3(0, yaw, roll) rolls
## in the yawed plane, which is what the vault and arch code relies on.
func _box(size: Vector3, pos: Vector3, mat: String, tint := 0.0,
		rot := Vector3.ZERO, collide := true, inner := false) -> void:
	if size.x <= 0.001 or size.y <= 0.001 or size.z <= 0.001:
		return
	var bucket: Dictionary = _boxes
	if inner:
		bucket = _inner
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


## A wall from local `a` to `b`, `t` thick, `y0` to `y1`, laid in courses.
## `bias` slides it OUTWARD (negative = into the fort). `gaps` is a list of
## Vector2(t0, t1) distances along a->b left open between gap_y.x and
## gap_y.y — that is how the gun ports and the sally port become holes and
## not decoration.
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
		## does this course pass through the openings?
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


## A barrel vault of clear span `span`, running `length` along the direction
## given by `yaw` (the vault's axis), springing from `centre` — the middle of
## the springing line.
func _vault(centre: Vector3, yaw: float, span: float, length: float, thick: float,
		mat: String, segs := 9, collide := true, inner := false) -> void:
	var r := span * 0.5 + thick * 0.5
	var chord := (PI * r / float(segs)) * 1.20
	var perp := Vector3(cos(yaw), 0.0, -sin(yaw))
	for k in range(segs):
		var th := PI * (float(k) + 0.5) / float(segs)
		_box(Vector3(chord, thick, length),
			centre + perp * (cos(th) * r) + Vector3(0.0, sin(th) * r, 0.0),
			mat, 0.0, Vector3(0.0, yaw, th - PI * 0.5), collide, inner)


## The dressed voussoir ring around an opening `w` wide in a wall of yaw
## `wall_yaw`, springing at `spring`, ring `t` deep through the wall.
func _arch_ring(at: Vector2, wall_yaw: float, w: float, spring: float, t: float,
		inner := true) -> void:
	_vault(Vector3(at.x, spring, at.y), wall_yaw + PI * 0.5, w, t * 1.6, t,
		"ashlar", 9, true, inner)
	var along := Vector2(sin(wall_yaw), cos(wall_yaw))
	for s: float in [-1.0, 1.0]:
		var j := at + along * (s * (w * 0.5 + t * 0.5))
		_box(Vector3(t * 1.6, spring, t), Vector3(j.x, spring * 0.5, j.y), "ashlar",
			0.03, Vector3(0.0, wall_yaw, 0.0), true, inner)


## An annular wall (a solid column when r_in is 0). `skip` holds side indices
## left open for a doorway.
func _ring(centre: Vector3, r_in: float, r_out: float, y0: float, y1: float,
		sides: int, mat: String, skip: Array = [], inner := false) -> void:
	if y1 <= y0:
		return
	var thick := r_out - r_in
	var rm := (r_in + r_out) * 0.5
	var seg := (TAU * rm / float(sides)) * 1.12
	var courses := maxi(1, int(round((y1 - y0) / 1.1)))
	var ch := (y1 - y0) / float(courses)
	for c in range(courses):
		var cy := y0 + (float(c) + 0.5) * ch
		for s in range(sides):
			if skip.has(s):
				continue
			var a := TAU * float(s) / float(sides)
			_box(Vector3(thick, ch * 0.985, seg),
				centre + Vector3(cos(a) * rm, cy, sin(a) * rm), mat,
				-0.02 if (c % 2) == 0 else 0.02, Vector3(0.0, -a, 0.0), true, inner)


## A straight flight of steps from `a` to `b`, `w` wide.
func _flight(a: Vector3, b: Vector3, w: float, mat: String, inner := false) -> void:
	var n := maxi(1, int(round(absf(b.y - a.y) / 0.19)))
	var step := (b - a) / float(n)
	var yaw := atan2(step.x, step.z) - PI * 0.5   ## local +X along travel
	var run := Vector2(step.x, step.z).length()
	for i in range(n):
		var p := a + step * (float(i) + 0.5)
		_box(Vector3(maxf(run * 1.5, 0.35), absf(step.y) + 0.24, w),
			Vector3(p.x, p.y - 0.1, p.z), mat, _rng.randf_range(-0.05, 0.03),
			Vector3(0.0, yaw, 0.0), true, inner)


## Where the undercroft is, in local XZ, so the raft can leave it hollow.
## `top` is the crown of that room's vault: the raft fills from the lid down
## to there, so the stone between the parade and the ceiling below is real and
## not a two-metre bubble. `shaft` rooms pierce the parade lid as well — the
## two stair wells and the furnace flue.
func _void_rects() -> Array:
	var out: Array = []
	out.append({"r": Rect2(TUNNEL_X - 2.7, TUNNEL_Z.x - 1.6,
		5.4, TUNNEL_Z.y - TUNNEL_Z.x + 3.2), "top": -3.3, "shaft": false})
	for mz: float in [-14.0, 14.0]:
		out.append({"r": Rect2(8.4, mz - 5.7, 13.8, 11.4), "top": -2.7, "shaft": false})
	out.append({"r": Rect2(-6.2, 1.2, 10.4, 9.6), "top": -2.7, "shaft": false})   ## furnace
	out.append({"r": Rect2(-29.5, -9.2, 34.0, 6.4), "top": -3.0, "shaft": false}) ## postern
	for sz: float in [-STAIR_Z, STAIR_Z]:
		out.append({"r": Rect2(TUNNEL_X - 3.6, sz - 3.6, 7.2, 7.2),
			"top": RAMPART_Y + 1.0, "shaft": true})
	out.append({"r": Rect2(-3.7, 4.5, 3.0, 3.0), "top": RAMPART_Y, "shaft": true})  ## flue
	return out


# ===========================================================================
#  The raft — the granite mass the whole fort stands on
# ===========================================================================
## This replaces the terrain inside the punched hole, so it has to be
## watertight from the parade down past the lowest ground on the bluff.
##
## It is a lid, a run-merged fill, a skirt and a bottom slab. The fill skips
## the undercroft and stops at each room's vault crown, so the passage below
## is a real hole in real stone rather than the whole raft being one hollow
## box with a lid on it — which is what it was until FortTests went looking
## for the floor and found sixty per cent of the parade standing over nothing.

func _raft() -> void:
	var x0 := RAFT_X.x
	var x1 := RAFT_X.y
	var z0 := RAFT_Z.x
	var z1 := RAFT_Z.y
	var w := x1 - x0
	var d := z1 - z0
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var voids := _void_rects()

	## The lid: the parade paving, in slabs so it takes light unevenly, with
	## the shafts left open.
	var lid_t := 0.9
	var cols := int(round(w / 5.5))
	var rows := int(round(d / 5.5))
	var sx := w / float(cols)
	var sz := d / float(rows)
	for i in range(cols):
		for j in range(rows):
			var c := Vector2(x0 + (float(i) + 0.5) * sx, z0 + (float(j) + 0.5) * sz)
			if _pierced(c, voids):
				continue
			_box(Vector3(sx * 0.99, lid_t, sz * 0.99), Vector3(c.x, -lid_t * 0.5, c.y),
				"granite", _rng.randf_range(-0.06, 0.04))

	## The fill, row by row, merging runs of cells that share a floor so a
	## solid quarter of the raft is a handful of boxes and not four hundred.
	var top := -lid_t
	var bot := TUNNEL_Y - 2.4
	var cell := 3.0
	var nx := int(ceil(w / cell))
	var nz := int(ceil(d / cell))
	var cw := w / float(nx)
	var cd := d / float(nz)
	for j2 in range(nz):
		var zc := z0 + (float(j2) + 0.5) * cd
		var run_start := -1
		var run_floor := 0.0
		for i2 in range(nx + 1):
			var floor_here := bot
			var live := i2 < nx
			if live:
				floor_here = _fill_floor(Vector2(x0 + (float(i2) + 0.5) * cw, zc), voids, bot)
			if live and floor_here < top - 0.05 \
					and (run_start < 0 or absf(floor_here - run_floor) < 0.01):
				if run_start < 0:
					run_start = i2
					run_floor = floor_here
				continue
			if run_start >= 0:
				var a := x0 + float(run_start) * cw
				var b := x0 + float(i2) * cw
				_box(Vector3(b - a, top - run_floor, cd),
					Vector3((a + b) * 0.5, (top + run_floor) * 0.5, zc), "granite", -0.02)
				run_start = -1
			if live and floor_here < top - 0.05:
				run_start = i2
				run_floor = floor_here

	## The skirt, down past the lowest ground in the footprint, so no seam on
	## the rim ever shows daylight. Buried on the west; on the river side it
	## IS the escarp of the bluff.
	var foot := _apron_floor()
	var st := 2.2
	_box(Vector3(w, bot - foot, st), Vector3(cx, (foot + bot) * 0.5, z0 + st * 0.5), "granite")
	_box(Vector3(w, bot - foot, st), Vector3(cx, (foot + bot) * 0.5, z1 - st * 0.5), "granite")
	_box(Vector3(st, bot - foot, d), Vector3(x0 + st * 0.5, (foot + bot) * 0.5, cz), "granite")
	_box(Vector3(st, bot - foot, d), Vector3(x1 - st * 0.5, (foot + bot) * 0.5, cz), "granite")
	## the bottom slab: nothing can fall out of the fort into the punched hole
	_box(Vector3(w, 1.6, d), Vector3(cx, foot - 0.8, cz), "granite", -0.05)


## How far down the raft fill reaches at this cell: the bottom, or the crown
## of whatever room is under it.
func _fill_floor(c: Vector2, voids: Array, bot: float) -> float:
	var f := bot
	for v in voids:
		var vd: Dictionary = v
		if (vd["r"] as Rect2).has_point(c):
			f = maxf(f, float(vd["top"]))
	return f


## Does a shaft come up through the parade here?
func _pierced(c: Vector2, voids: Array) -> bool:
	for v in voids:
		var vd: Dictionary = v
		if bool(vd["shaft"]) and (vd["r"] as Rect2).has_point(c):
			return true
	return false


## The single floor level everything that reaches down reaches down TO: the
## raft skirt, the apron, the ditch walls. Well clear of the lowest ground in
## the punched rect and well above World's -60 m out-of-world trapdoor.
func _apron_floor() -> float:
	var low := 1e9
	for i in range(17):
		for j in range(17):
			low = minf(low, _ground(Vector2(
				lerpf(PUNCH_X.x, PUNCH_X.y, float(i) / 16.0),
				lerpf(PUNCH_Z.x, PUNCH_Z.y, float(j) / 16.0))))
	return minf(minf(low, DITCH_FLOOR) - 3.0, floor_y() + 3.0)


## Rebuild the ground inside the punched rect but outside the raft, and cut
## the dry ditch into it on the way past.
##
## This exists because punching the heightfield takes away the mesh AND the
## collider: without an apron the fort would stand on a doughnut of nothing.
## It is also the only way the ditch can be a real excavation — you cannot
## dig a trench into terrain that is still there.
##
## The cells step in APRON_CELL metres, which terraces the bluff a little.
## That reads as the cut the fort was set into, and it matches the blocky
## language of everything else in the game, so it is left alone on purpose.
func _apron() -> void:
	var foot := _apron_floor()
	var nx := int(ceil((PUNCH_X.y - PUNCH_X.x) / APRON_CELL))
	var nz := int(ceil((PUNCH_Z.y - PUNCH_Z.x) / APRON_CELL))
	var cw := (PUNCH_X.y - PUNCH_X.x) / float(nx)
	var cd := (PUNCH_Z.y - PUNCH_Z.x) / float(nz)
	for i in range(nx):
		for j in range(nz):
			var c := Vector2(PUNCH_X.x + (float(i) + 0.5) * cw,
				PUNCH_Z.x + (float(j) + 0.5) * cd)
			## the raft owns its own footprint
			if c.x > RAFT_X.x - 0.1 and c.x < RAFT_X.y + 0.1 \
					and c.y > RAFT_Z.x - 0.1 and c.y < RAFT_Z.y + 0.1:
				continue
			var top := _ground(c)
			var mat := "earth"
			if _in_ditch(c):
				top = DITCH_FLOOR
				mat = "granite"
			if top <= foot + 0.2:
				continue
			## rim cells run out past the punch edge, so the seam with the
			## live terrain is buried under stone instead of standing open
			var ew := cw + 0.5
			var ed := cd + 0.5
			var off := Vector2.ZERO
			if i == 0:
				ew += 5.0
				off.x = -2.5
			elif i == nx - 1:
				ew += 5.0
				off.x = 2.5
			if j == 0:
				ed += 5.0
				off.y = -2.5
			elif j == nz - 1:
				ed += 5.0
				off.y = 2.5
			_box(Vector3(ew, top - foot, ed),
				Vector3(c.x + off.x, (top + foot) * 0.5, c.y + off.y), mat,
				_rng.randf_range(-0.07, 0.05))


## Is this local point in the band the ditch occupies, off one of the land
## faces? Used only by _apron, to decide which cells get dug out.
func _in_ditch(p: Vector2) -> bool:
	for face: int in LAND_FACES:
		var a := _corner(face)
		var b := _corner(face + 1)
		var d := b - a
		var span := d.length()
		var t := (p - a).dot(d / span)
		if t < -2.5 or t > span + 2.5:
			continue
		var out := (p - a).dot(_outward(d))
		if out > WALL_T * 0.5 - 0.3 and out < DITCH_OUT:
			return true
	return false


# ===========================================================================
#  The undercroft — passage, magazines, furnace, postern
# ===========================================================================

func _undercroft() -> void:
	var fy := TUNNEL_Y
	var w := 3.0
	var spring := fy + TUNNEL_H - w * 0.5

	## The main passage, north to south under the parade.
	_box(Vector3(w + 1.6, 0.6, TUNNEL_Z.y - TUNNEL_Z.x + 2.0),
		Vector3(TUNNEL_X, fy - 0.3, (TUNNEL_Z.x + TUNNEL_Z.y) * 0.5), "dark",
		-0.04, Vector3.ZERO, true, true)
	## The side walls, with a gap cut where each throat comes off. Without
	## these gaps the magazines are sealed rooms behind a decorative arch —
	## which is exactly what they were until the suite tried to walk into one.
	var east_gaps: Array = []
	for mz: float in [-14.0, 14.0]:
		east_gaps.append(Vector2(mz - TUNNEL_Z.x - 1.9, mz - TUNNEL_Z.x + 1.9))
	var west_gaps: Array = [
		Vector2(6.0 - TUNNEL_Z.x - 1.9, 6.0 - TUNNEL_Z.x + 1.9),      ## the furnace
		Vector2(-6.0 - TUNNEL_Z.x - 1.9, -6.0 - TUNNEL_Z.x + 1.9),    ## the postern
	]
	for s: float in [-1.0, 1.0]:
		var gaps: Array = east_gaps if s > 0.0 else west_gaps
		_wall_run(Vector2(TUNNEL_X + s * (w * 0.5 + 0.4), TUNNEL_Z.x),
			Vector2(TUNNEL_X + s * (w * 0.5 + 0.4), TUNNEL_Z.y),
			0.8, fy, spring, "dark", 0.0, 1.0, true, gaps, Vector2(fy, fy + 2.7))
	_vault(Vector3(TUNNEL_X, spring, (TUNNEL_Z.x + TUNNEL_Z.y) * 0.5), 0.0,
		w, TUNNEL_Z.y - TUNNEL_Z.x + 2.0, 0.8, "dark", 9, true, true)

	## Two powder magazines off the east side, and their throats.
	for k in range(2):
		var mz: float = -14.0 if k == 0 else 14.0
		_chamber(Vector3(15.5, fy, mz), 11.0, 7.4, "dark", -1.0)
		_throat(Vector3(9.0, fy, mz), 4.8, PI * 0.5)
		for b in range(9):
			## stacked at the BACK of the magazine: barrels standing in the
			## doorway line is how the suite first found its way in blocked
			var bx := 16.3 + float(b % 3) * 1.6
			@warning_ignore("integer_division")
			var bz := mz - 2.4 + float(b / 3) * 1.7
			_box(Vector3(1.0, 1.25, 1.0), Vector3(bx, fy + 0.92, bz), "timber",
				_rng.randf_range(-0.08, 0.05),
				Vector3(0.0, _rng.randf_range(0.0, 1.5), 0.0), true, true)
			_box(Vector3(1.14, 0.12, 1.14), Vector3(bx, fy + 1.3, bz), "iron",
				0.0, Vector3.ZERO, false, true)

	## The hot shot furnace, west off the passage: a stone oven with an iron
	## grate, where round shot was heated before it went up to the guns.
	_chamber(Vector3(-1.0, fy, 6.0), 8.0, 6.4, "dark", 1.0)
	_throat(Vector3(3.5, fy, 6.0), 4.8, PI * 0.5)
	_box(Vector3(3.0, 2.6, 2.6), Vector3(-2.2, fy + 1.3, 6.0), "granite", -0.10,
		Vector3.ZERO, true, true)
	_box(Vector3(1.6, 1.3, 1.7), Vector3(-0.7, fy + 0.9, 6.0), "iron", 0.0,
		Vector3.ZERO, false, true)
	## its flue, up through the raft and out on the parade
	_ring(Vector3(-2.2, 0.0, 6.0), 0.55, 1.05, fy + 2.6, 1.9, 8, "granite")

	## The postern: a passage running west out under the ditch, with a stair
	## up into the counterscarp. The way out when the gate is shut.
	var py := -6.0
	_box(Vector3(13.0, 0.5, 3.6), Vector3(-8.5, fy - 0.25, py), "dark", 0.0,
		Vector3.ZERO, true, true)
	for s: float in [-1.0, 1.0]:
		_wall_run(Vector2(-15.0, py + s * 1.7), Vector2(-2.0, py + s * 1.7),
			0.7, fy, fy + 2.0, "dark", 0.0, 1.0, true)
	_vault(Vector3(-8.5, fy + 2.0, py), PI * 0.5, 2.6, 13.0, 0.7, "dark", 7, true, true)
	_flight(Vector3(-15.5, fy, py), Vector3(-27.0, DITCH_FLOOR, py), 2.6, "dark", true)
	_box(Vector3(1.2, 3.2, 3.4), Vector3(-28.2, DITCH_FLOOR + 1.6, py), "iron",
		0.0, Vector3.ZERO, false, true)


## A rectangular vaulted room. `w` runs along X, `d` along Z; the doorway is
## punched on the X side given by `door` (-1 = west wall, +1 = east wall).
func _chamber(origin: Vector3, w: float, d: float, mat: String, door: float) -> void:
	var cx := origin.x
	var cz := origin.z
	var fy := origin.y
	var spring := fy + TUNNEL_H - d * 0.5 + 0.6
	var half_w := w * 0.5
	var half_d := d * 0.5
	_box(Vector3(w + 1.6, 0.6, d + 1.6), Vector3(cx, fy - 0.3, cz), mat, -0.04,
		Vector3.ZERO, true, true)
	## the two long walls
	for s: float in [-1.0, 1.0]:
		_wall_run(Vector2(cx - half_w, cz + s * half_d), Vector2(cx + half_w, cz + s * half_d),
			0.8, fy, spring, mat, 0.0, 1.0, true)
	## the blind end wall
	var blind := cx - door * half_w
	_wall_run(Vector2(blind, cz - half_d), Vector2(blind, cz + half_d),
		0.8, fy, spring + half_d, mat, 0.0, 1.0, true)
	## the doorway end: a 3.2 m opening 2.6 m tall
	var dx := cx + door * half_w
	_wall_run(Vector2(dx, cz - half_d), Vector2(dx, cz + half_d),
		0.8, fy, spring + half_d, mat, 0.0, 1.0, true,
		[Vector2(half_d - 1.6, half_d + 1.6)], Vector2(fy, fy + 2.6))
	_vault(Vector3(cx, spring, cz), PI * 0.5, d, w, 0.8, mat, 9, true, true)


## A short connecting passage of clear span 2.4, `length` long, along `yaw`.
func _throat(centre: Vector3, length: float, yaw: float) -> void:
	_box(Vector3(length, 0.5, 3.6), Vector3(centre.x, centre.y - 0.25, centre.z),
		"dark", 0.0, Vector3(0.0, yaw - PI * 0.5, 0.0), true, true)
	_vault(Vector3(centre.x, centre.y + 1.9, centre.z), yaw, 2.4, length, 0.6,
		"dark", 7, true, true)


# ===========================================================================
#  Curtains and rampart
# ===========================================================================

func _curtains() -> void:
	for i in range(CORNERS.size()):
		var a := _corner(i)
		var b := _corner(i + 1)
		var length := (b - a).length()
		var is_river := RIVER_FACES.has(i)
		var foot := _low_under(a, b) - 2.0
		## the same width on every face: a 3.4 m land walk left your feet over
		## the edge where the suite stands you, and a fort walk you cannot
		## stand on is not a fort walk
		var walk := 4.4

		if is_river:
			_river_curtain(i, a, b, foot)
		elif i == GATE_FACE:
			## the sally port opening is cut here; _gate dresses it
			var mid := length * 0.5
			_wall_run(a, b, WALL_T, foot, RAMPART_Y, "granite", -WALL_T * 0.5, 1.15,
				false, [Vector2(mid - 2.0, mid + 2.0)], Vector2(-1.0, 5.6))
		else:
			_wall_run(a, b, WALL_T, foot, RAMPART_Y, "granite", -WALL_T * 0.5, 1.15)

		## the rampart walk, laid inward off the curtain line
		_wall_run(a, b, walk, RAMPART_Y - 0.6, RAMPART_Y, "granite", -walk * 0.5, 0.6)
		_parapet(a, b, i)
		## backing wall under the walk on the land faces, so the parade side
		## of the rampart is stone and not a floating slab
		if not is_river:
			var gaps: Array = []
			if i == GATE_FACE:
				gaps = [Vector2(length * 0.5 - 2.6, length * 0.5 + 2.6)]
			_wall_run(a, b, 1.0, 0.0, RAMPART_Y - 0.6, "granite", -(walk - 0.5), 1.15,
				false, gaps, Vector2(-1.0, 5.0))
			_ramp_to_rampart(a, b, i)

	## Dressed quoins standing proud at every angle — what makes a granite
	## fort read as granite and not as a grey box.
	for i in range(CORNERS.size()):
		var c := _corner(i)
		var qfoot := _ground(c) - 2.0
		_box(Vector3(3.4, RAMPART_Y + PARAPET_H - qfoot, 3.4),
			Vector3(c.x, (qfoot + RAMPART_Y + PARAPET_H) * 0.5, c.y), "ashlar", 0.03)


## A river face: solid below the gun ports, solid above them, piers between
## them. This is what makes the casemates actually see the water.
func _river_curtain(_face: int, a: Vector2, b: Vector2, foot: float) -> void:
	var ts := casemate_ts(a, b)
	var gaps: Array = []
	for t: float in ts:
		gaps.append(Vector2(t - PORT_W * 0.5, t + PORT_W * 0.5))
	## below the sill
	_wall_run(a, b, WALL_T, foot, PORT_SILL, "granite", -WALL_T * 0.5, 1.15)
	## the pierced band
	_wall_run(a, b, WALL_T, PORT_SILL, PORT_HEAD, "granite", -WALL_T * 0.5, 1.05,
		false, gaps, Vector2(PORT_SILL, PORT_HEAD))
	## above the head
	_wall_run(a, b, WALL_T, PORT_HEAD, RAMPART_Y, "granite", -WALL_T * 0.5, 1.15)
	## dressed ashlar around every port
	var dir := (b - a).normalized()
	var yaw := _yaw_of(b - a)
	var out := _outward(b - a)
	for t2: float in ts:
		var p := a + dir * t2 + out * (-WALL_T * 0.5)
		for s: float in [-1.0, 1.0]:
			var j := p + dir * (s * (PORT_W * 0.5 + 0.3))
			_box(Vector3(WALL_T + 0.5, PORT_HEAD - PORT_SILL, 0.6),
				Vector3(j.x, (PORT_SILL + PORT_HEAD) * 0.5, j.y), "ashlar", 0.04,
				Vector3(0.0, yaw, 0.0), true)
		_box(Vector3(WALL_T + 0.5, 0.55, PORT_W + 1.8), Vector3(p.x, PORT_SILL - 0.28, p.y),
			"ashlar", 0.02, Vector3(0.0, yaw, 0.0), true)
		_box(Vector3(WALL_T + 0.5, 0.6, PORT_W + 1.8), Vector3(p.x, PORT_HEAD + 0.3, p.y),
			"ashlar", 0.02, Vector3(0.0, yaw, 0.0), true)


## Distances along a river face at which a gun port (and the casemate behind
## it) sits. Inset from both angles, because a port cut too near a salient
## looks straight into the neighbouring face instead of at the water — the
## suite proves every port is a clear line out, and this is what makes it one.
static func casemate_ts(a: Vector2, b: Vector2) -> PackedFloat32Array:
	var usable := (b - a).length() - FACE_INSET * 2.0
	var out := PackedFloat32Array()
	if usable <= PORT_SPACING:
		return out
	var count := maxi(3, int(round(usable / PORT_SPACING)))
	for k in range(count):
		out.append(FACE_INSET + (float(k) + 0.5) * (usable / float(count)))
	return out


func _parapet(a: Vector2, b: Vector2, face: int) -> void:
	var d := b - a
	var length := d.length()
	var dir := d / length
	var out := _outward(d)
	var yaw := _yaw_of(d)
	var merlons := maxi(3, int(round(length / 3.4)))
	var step := length / float(merlons)
	var is_river := RIVER_FACES.has(face)
	for m in range(merlons):
		var t := (float(m) + 0.5) * step
		var p := a + dir * t + out * (-WALL_T * 0.5)
		_box(Vector3(WALL_T * 0.95, PARAPET_H, step * 0.62),
			Vector3(p.x, RAMPART_Y + PARAPET_H * 0.5, p.y), "granite",
			_rng.randf_range(-0.05, 0.05), Vector3(0.0, yaw, 0.0))
		if m < merlons - 1:
			var q := a + dir * (t + step * 0.5) + out * (-WALL_T * 0.5)
			_box(Vector3(WALL_T * 0.95, 0.55, step * 0.38),
				Vector3(q.x, RAMPART_Y + 0.275, q.y), "granite", 0.02,
				Vector3(0.0, yaw, 0.0))
		if is_river and (m % 3) == 1:
			_gun(p + _inward(d) * 2.4, yaw, RAMPART_Y)


## A short flight up the inside of a land curtain onto the rampart walk.
func _ramp_to_rampart(a: Vector2, b: Vector2, face: int) -> void:
	if face != 0 and face != 3:
		return
	var d := b - a
	var dir := d.normalized()
	var inw := _inward(d)
	var top := (a + b) * 0.5 + dir * 5.0 + inw * 3.6
	var base := top + inw * 11.0
	_flight(Vector3(base.x, -0.2, base.y), Vector3(top.x, RAMPART_Y - 0.6, top.y),
		2.8, "granite")


## An iron gun on a wooden carriage, sighted OUTWARD from a wall of yaw
## `wall_yaw` (the barrel runs along that wall's outward normal).
func _gun(at: Vector2, wall_yaw: float, y: float) -> void:
	var gy := wall_yaw + PI * 0.5      ## barrel along local +Z, pointing out
	var r := Vector3(0.0, gy, 0.0)
	var fwd := Vector2(sin(gy), cos(gy))
	var side := Vector2(cos(gy), -sin(gy))
	_box(Vector3(1.6, 0.35, 2.6), Vector3(at.x, y + 0.2, at.y), "timber", -0.05, r, false)
	for s: float in [-0.6, 0.6]:
		var wp := at + side * s
		_box(Vector3(0.22, 0.95, 0.95), Vector3(wp.x, y + 0.6, wp.y), "timber", 0.05, r, false)
	_box(Vector3(0.44, 0.44, 3.1), Vector3(at.x, y + 1.05, at.y), "iron", 0.0, r, true)
	var breech := at - fwd * 1.35
	_box(Vector3(0.62, 0.62, 0.72), Vector3(breech.x, y + 1.05, breech.y), "iron", -0.05, r, false)
	var pile := at + side * 1.8 - fwd * 0.6
	for k in range(4):
		@warning_ignore("integer_division")
		_box(Vector3(0.3, 0.3, 0.3),
			Vector3(pile.x + float(k % 2) * 0.33, y + 0.15 + float(k / 2) * 0.3,
				pile.y + float(k % 2) * 0.33), "iron", 0.0, Vector3.ZERO, false)


# ===========================================================================
#  Casemates — the vaulted gun rooms behind the river faces
# ===========================================================================

func _casemates() -> void:
	for face in RIVER_FACES:
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


## One gun room: piers, a barrel vault turned to sit along the face, an arch
## onto the parade at the back, a floor, and a gun on the port.
func _casemate(c: Vector2, yaw: float, width: float, inw: Vector2, dir: Vector2) -> void:
	var clear := clampf(width - 2.6, 3.0, 5.6)
	var spring := 4.4 - clear * 0.5

	## A yawed box has local +X through the wall and local +Z along it, so a
	## pier is (depth, height, width) in that order. Getting this pair the
	## wrong way round turned every pier into a 7 m slab lying ALONG the face,
	## which walled the casemates off and blinded their gun ports — the suite
	## caught it as "0 of 10 casemates reachable".
	for s: float in [-1.0, 1.0]:
		var p := c + dir * (s * (clear * 0.5 + 1.1))
		_box(Vector3(CASEMATE_D, spring, 2.2), Vector3(p.x, spring * 0.5, p.y),
			"granite", 0.02, Vector3(0.0, yaw, 0.0), true, true)
	## the vault runs from the curtain back into the parade: its axis is the
	## wall's normal, so yaw + 90.
	_vault(Vector3(c.x, spring, c.y), yaw + PI * 0.5, clear, CASEMATE_D, 0.9,
		"granite", 9, true, true)
	## floor
	_box(Vector3(CASEMATE_D, 0.4, clear + 2.4), Vector3(c.x, -0.2, c.y), "granite",
		-0.05, Vector3(0.0, yaw, 0.0), true, true)
	## the arch onto the parade
	var back := c + inw * (CASEMATE_D * 0.5)
	_arch_ring(back, yaw, clear, spring, 0.8)
	## and the gun, run up to the port
	_gun(c - inw * 1.6, yaw, 0.0)


# ===========================================================================
#  The spiral stairs — the thing people come to see
# ===========================================================================

## A granite helix in a round well, running the whole height of the fort:
## undercroft, parade, rampart. `which` picks the handedness so the two stairs
## mirror each other.
##
## The wells sit on the passage line at +/- STAIR_Z, so the undercroft door
## opens straight into the passage — a stair whose bottom landing came out in
## solid raft would look perfect and go nowhere. The rampart door faces the
## other way, onto a short gangway across to the wall walk.
func _spiral(at: Vector2, which: int) -> void:
	var r_in := 0.55
	var r_out := STAIR_R
	var y0 := TUNNEL_Y - 0.4
	var y1 := RAMPART_Y + 0.3
	var sides := 16
	var handed := 1.0 if which == 0 else -1.0
	## toward the passage at the two lower landings, out to the wall at the top
	var inward_a := (PI * 0.5) if which == 0 else (-PI * 0.5)
	var doors: Array = [inward_a, inward_a, inward_a + PI]

	## The shaft, in bands, so the three landings get real doorways and the
	## rest of the wall stays closed.
	var bands: Array = [
		[y0, TUNNEL_Y + 2.9, doors[0]],
		[TUNNEL_Y + 2.9, -0.1, null],
		[0.0, 2.9, doors[1]],
		[2.9, RAMPART_Y - 0.7, null],
		[RAMPART_Y - 0.7, y1, doors[2]],
	]
	for band in bands:
		var bv: Array = band
		var skip: Array = []
		if bv[2] != null:
			skip = _door_sides(float(bv[2]), sides)
		_ring(Vector3(at.x, 0.0, at.y), r_out, r_out + 0.8, float(bv[0]), float(bv[1]),
			sides, "granite", skip)

	## Newel.
	_box(Vector3(r_in * 2.0, y1 - y0, r_in * 2.0), Vector3(at.x, (y0 + y1) * 0.5, at.y),
		"ashlar", 0.04, Vector3.ZERO, true, true)

	## Treads.
	var rise := 0.185
	var per_turn := 20.0
	var steps := int((y1 - y0) / rise)
	var rm := (r_in + r_out) * 0.5
	var tread := (TAU * rm / per_turn) * 1.28
	for i in range(steps):
		var ang := handed * TAU * float(i) / per_turn
		_box(Vector3(r_out - r_in, 0.2, tread),
			Vector3(at.x + cos(ang) * rm, y0 + float(i) * rise, at.y + sin(ang) * rm),
			"granite", _rng.randf_range(-0.05, 0.04), Vector3(0.0, -ang, 0.0), true, true)

	## Threshold slabs out of each landing.
	var levels: Array = [TUNNEL_Y + 0.05, -0.05, RAMPART_Y - 0.65]
	for k in range(3):
		var da := float(doors[k])
		var dp := at + Vector2(cos(da), sin(da)) * (r_out + 1.4)
		_box(Vector3(3.0, 0.3, 2.8), Vector3(dp.x, float(levels[k]) - 0.15, dp.y),
			"ashlar", 0.02, Vector3(0.0, -da, 0.0), true, true)

	## The gangway from the top landing across to the rampart walk. The wall
	## is a few metres past the shaft; without this you step out of the stair
	## into fresh air six metres over the parade.
	var out_a := float(doors[2])
	var g0 := at + Vector2(cos(out_a), sin(out_a)) * (r_out + 0.4)
	## stop short of the parapet: run it to the wall and the gangway ends
	## inside a merlon, which is a lovely way to wall your own stair in
	var g1 := at + Vector2(cos(out_a), sin(out_a)) * (r_out + 5.5)
	_box(Vector3(2.8, 0.5, (g1 - g0).length()),
		Vector3((g0.x + g1.x) * 0.5, RAMPART_Y - 0.85, (g0.y + g1.y) * 0.5), "granite",
		0.02, Vector3(0.0, atan2(g1.x - g0.x, g1.y - g0.y), 0.0))

	## A slit window every turn and a half, so the shaft is not pitch black.
	var turns := int((y1 - y0) / (rise * per_turn))
	for t in range(turns):
		var wa := handed * TAU * (float(t) + 0.35)
		var wy := y0 + (float(t) + 0.35) * rise * per_turn
		if wy < 0.6:
			continue
		_box(Vector3(1.0, 1.1, 0.35),
			Vector3(at.x + cos(wa) * (r_out + 0.38), wy + 1.2, at.y + sin(wa) * (r_out + 0.38)),
			"dark", -0.25, Vector3(0.0, -wa, 0.0), false)


## Which ring sides a doorway at angle `a` opens.
func _door_sides(a: float, sides: int) -> Array:
	var c := int(round(fposmod(a, TAU) / TAU * float(sides))) % sides
	return [(c + sides - 1) % sides, c, (c + 1) % sides]


# ===========================================================================
#  Gate, ditch, water battery, parade
# ===========================================================================

func _gate() -> void:
	var a := _corner(GATE_FACE)
	var b := _corner(GATE_FACE + 1)
	var d := b - a
	var mid := (a + b) * 0.5
	var inw := _inward(d)
	var out := _outward(d)
	var yaw := _yaw_of(d)
	var clear := 3.4
	var spring := 3.0

	## The sally port passage through the curtain and the rampart backing.
	var depth := WALL_T + 5.0
	for s: float in [-1.0, 1.0]:
		var p := mid + d.normalized() * (s * (clear * 0.5 + 1.5)) + inw * 1.4
		_box(Vector3(depth, spring + clear * 0.5 + 1.4, 3.0),
			Vector3(p.x, (spring + clear * 0.5 + 1.4) * 0.5, p.y), "ashlar", 0.03,
			Vector3(0.0, yaw, 0.0))
	_box(Vector3(depth, 1.7, clear + 6.0),
		Vector3(mid.x + inw.x * 1.4, spring + clear * 0.5 + 0.85, mid.y + inw.y * 1.4),
		"ashlar", 0.02, Vector3(0.0, yaw, 0.0))
	_box(Vector3(depth, 0.35, clear + 0.4),
		Vector3(mid.x + inw.x * 1.4, -0.17, mid.y + inw.y * 1.4), "granite", -0.04,
		Vector3(0.0, yaw, 0.0))
	_arch_ring(mid + out * (WALL_T * 0.5 + 0.3), yaw, clear, spring, 0.9, false)
	_arch_ring(mid + inw * 4.6, yaw, clear, spring, 0.7, false)

	## The portcullis, half down and stuck there.
	var pc := mid + inw * 1.0
	var along := d.normalized()
	for g in range(7):
		var gx := -clear * 0.5 + (float(g) + 0.5) * (clear / 7.0)
		_box(Vector3(0.16, 2.3, 0.16), Vector3(pc.x + along.x * gx, spring + 1.95,
			pc.y + along.y * gx), "iron", 0.0, Vector3(0.0, yaw, 0.0), false)
	for g in range(3):
		_box(Vector3(0.16, 0.16, clear), Vector3(pc.x, spring + 1.15 + float(g) * 0.8, pc.y),
			"iron", 0.0, Vector3(0.0, yaw, 0.0), false)

	## The bridge over the ditch and the ramp up the glacis to meet it.
	var br0 := mid + out * (WALL_T * 0.5)
	var br1 := mid + out * (WALL_T * 0.5 + DITCH_W + 2.4)
	_box(Vector3(DITCH_W + 2.8, 0.4, 4.8),
		Vector3((br0.x + br1.x) * 0.5, -0.2, (br0.y + br1.y) * 0.5), "timber", -0.04,
		Vector3(0.0, yaw, 0.0))
	for s: float in [-1.0, 1.0]:
		for p in range(4):
			var px: Vector2 = br0.lerp(br1, (float(p) + 0.5) / 4.0) + along * (s * 2.2)
			_box(Vector3(0.28, 1.15, 0.28), Vector3(px.x, 0.575, px.y), "timber", 0.05,
				Vector3.ZERO, false)
	var app := br1 + out * 10.0
	_flight(Vector3(app.x, _ground(app) - 0.2, app.y), Vector3(br1.x, -0.2, br1.y),
		5.0, "earth")


## The ditch is CUT by `_apron` — it drops every ground cell in the band to
## DITCH_FLOOR. All that is left here is the granite counterscarp facing the
## fort across it, which is the wall you actually look at from down there.
func _ditch() -> void:
	for face in LAND_FACES:
		var a := _corner(face)
		var b := _corner(face + 1)
		var d := b - a
		var dir := d.normalized()
		var out := _outward(d)
		var ca := a + out * DITCH_OUT - dir * 3.0
		var cb := b + out * DITCH_OUT + dir * 3.0
		var low := _low_under(ca, cb)
		_wall_run(ca, cb, 1.8, DITCH_FLOOR - 1.2, low + 0.5, "granite", 0.9, 1.15)
		## and the escarp side, so the ditch has dressed stone on both walls
		var ea := a + out * (WALL_T * 0.5) - dir * 1.0
		var eb := b + out * (WALL_T * 0.5) + dir * 1.0
		_wall_run(ea, eb, 1.2, DITCH_FLOOR - 1.2, -0.6, "granite", -0.6, 1.15)


func _water_battery() -> void:
	## Below the east front, on the shoulder of the bluff: an open battery
	## looking straight down the narrows, reached by a stair off the salient.
	var p := _corner(2) + Vector2(2.0, 0.0)
	var by := _ground(p) + 0.8
	var half := 13.0
	_box(Vector3(12.0, 1.4, half * 2.0), Vector3(p.x, by - 0.7, p.y), "granite", -0.03)
	for m in range(9):
		var mz := -half + (float(m) + 0.5) * (half * 2.0 / 9.0)
		_box(Vector3(1.9, 1.7, half * 2.0 / 9.0 * 0.62),
			Vector3(p.x + 5.2, by + 0.85, p.y + mz), "granite", _rng.randf_range(-0.05, 0.05))
		if (m % 3) == 1:
			## a wall running along Z has yaw 0, so its outward normal is +X:
			## these guns look east, down the water.
			_gun(Vector2(p.x + 2.2, p.y + mz), 0.0, by)
	_flight(Vector3(_corner(2).x - 1.0, -0.2, _corner(2).y),
		Vector3(p.x - 5.0, by, p.y), 2.8, "granite")


func _parade_dressing() -> void:
	## A well, because a fort under siege needs one.
	_ring(Vector3(-14.0, 0.0, 0.0), 1.1, 1.8, 0.0, 1.0, 10, "granite")
	for s: float in [-1.6, 1.6]:
		_box(Vector3(0.24, 2.6, 0.24), Vector3(-14.0 + s, 1.3, 0.0), "timber", 0.0,
			Vector3.ZERO, false)
	_box(Vector3(3.6, 0.22, 0.5), Vector3(-14.0, 2.6, 0.0), "timber", -0.05,
		Vector3.ZERO, false)

	## The flagstaff on the parade.
	_box(Vector3(0.3, 11.0, 0.3), Vector3(-6.0, 5.5, -18.0), "timber", 0.06)
	_box(Vector3(2.4, 0.5, 2.4), Vector3(-6.0, 0.25, -18.0), "ashlar", 0.02)

	## Officers' quarters along the west curtain — a run that was never
	## finished in our world either.
	for k in range(4):
		var qz := -16.0 + float(k) * 11.0
		_box(Vector3(4.2, 3.2, 7.2), Vector3(-30.0, 1.6, qz), "granite",
			_rng.randf_range(-0.05, 0.03))
		_box(Vector3(1.4, 2.2, 1.1), Vector3(-27.7, 1.1, qz), "dark", -0.3,
			Vector3.ZERO, false)
		_box(Vector3(5.0, 0.4, 8.0), Vector3(-30.0, 3.4, qz), "granite", 0.05)

	## Fallen stone: it has been standing here a long time.
	for k in range(22):
		var fa := _rng.randf_range(0.0, TAU)
		var fr := _rng.randf_range(8.0, 30.0)
		var s := _rng.randf_range(0.5, 1.5)
		_box(Vector3(s, s * 0.7, s * 1.2), Vector3(cos(fa) * fr, s * 0.35, sin(fa) * fr),
			"granite", _rng.randf_range(-0.12, 0.02),
			Vector3(_rng.randf_range(-0.2, 0.2), _rng.randf_range(0.0, TAU),
				_rng.randf_range(-0.2, 0.2)))
	## and moss taking the parade
	for k in range(34):
		_box(Vector3(_rng.randf_range(1.5, 4.5), 0.06, _rng.randf_range(1.5, 4.5)),
			Vector3(_rng.randf_range(RAFT_X.x + 6.0, RAFT_X.y - 10.0), 0.03,
				_rng.randf_range(RAFT_Z.x + 6.0, RAFT_Z.y - 6.0)),
			"moss", _rng.randf_range(-0.15, 0.1),
			Vector3(0.0, _rng.randf_range(0.0, TAU), 0.0), false)


# ===========================================================================
#  Light
# ===========================================================================
## The undercroft is 7 m under the heightfield, so World's depth blend puts
## real cave gloom in there for free. These are the sconces that make it
## navigable: shadowless, short range, distance-faded — cheap.

func _seat_lights() -> void:
	var spots: Array[Vector3] = [
		Vector3(TUNNEL_X, TUNNEL_Y + 2.3, -24.0),
		Vector3(TUNNEL_X, TUNNEL_Y + 2.3, -8.0),
		Vector3(TUNNEL_X, TUNNEL_Y + 2.3, 8.0),
		Vector3(TUNNEL_X, TUNNEL_Y + 2.3, 24.0),
		Vector3(14.0, TUNNEL_Y + 2.3, -14.0),
		Vector3(14.0, TUNNEL_Y + 2.3, 14.0),
		Vector3(1.4, TUNNEL_Y + 2.3, 6.0),
		Vector3(-8.5, TUNNEL_Y + 2.3, -6.0),
		Vector3(-20.0, TUNNEL_Y + 2.3, -6.0),
		Vector3(TUNNEL_X, TUNNEL_Y + 2.4, -STAIR_Z + STAIR_R - 0.9),
		Vector3(TUNNEL_X, TUNNEL_Y + 2.4, STAIR_Z - STAIR_R + 0.9),
	]
	for p in spots:
		var l := OmniLight3D.new()
		add_child(l)
		l.position = p
		l.light_color = Color(1.0, 0.72, 0.42)
		l.light_energy = 2.1
		l.omni_range = 11.0
		l.shadow_enabled = false          ## project convention for fill lights
		l.distance_fade_enabled = true
		l.distance_fade_begin = 60.0
		l.distance_fade_length = 20.0
		_lights.append(l)
		_late_box(Vector3(0.22, 0.5, 0.22), p + Vector3(0.0, -0.45, 0.0), "iron")
		_late_box(Vector3(0.3, 0.34, 0.3), p, "moss", 0.6)


func _late_box(size: Vector3, pos: Vector3, mat: String, tint := 0.0) -> void:
	if not _late.has(mat):
		_late[mat] = []
	(_late[mat] as Array).append({"size": size, "pos": pos, "rot": Vector3.ZERO, "tint": tint})


# ===========================================================================
#  Baking — every box of a material becomes one mesh
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
	for mat_id3 in _late.keys():
		var mi3 := _mesh_of(_late[mat_id3] as Array, str(mat_id3))
		if mi3 != null:
			mi3.name = "Trim_" + str(mat_id3)
			mi3.visibility_range_end = INNER_VIS
			add_child(mi3)
	_boxes.clear()
	_inner.clear()
	_late.clear()


const _FACE_N: Array[Vector3] = [
	Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0),
	Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0),
]
## Corner signs per face, in winding order.
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
			## a touch of shade on the downward faces and light on the top, so
			## flat granite still reads as courses under the banded light
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
	m.metallic_specular = 0.05   ## Godot 4 name; `specular` is a 3.x remap and warns
	_mat_cache[id] = m
	return m
