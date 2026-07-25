class_name ChopTree
extends StaticBody3D
## A TREE YOU CAN ACTUALLY FELL.
##
## The trunk is procedural: rings of faceted geometry whose radius the axe
## EATS. Every bite deepens a V-shaped wedge on the struck side — a real
## notch cut into the wood, pale heartwood laid open inside it, biting past
## the centre by the last swing. Nothing is added to the tree when you chop
## it; something is taken out of it.
##
## The fall follows the same honesty. The trunk breaks AT THE NOTCH: a stump
## stays rooted with the wedge still showing, and everything above it tips
## over on that hinge, accelerating like real weight. When the crown finally
## hits dirt the canopy comes apart — every leaf breaks off and planes down
## to the ground on its own (Litter.gd) and stays there — and the trunk
## splits into as many logs as the tree was metres tall, which tumble off the
## fall line and lie where they stop (CarryLog.gd). Branches shatter into
## sticks. What's left standing is a stump and a mess, which is what felling
## a tree leaves.

const SEG_PLAIN := 8             ## radial resolution of an untouched trunk
const SEG_CUT := 16              ## ...and of one the axe has opened up
const NOTCH_Y := 1.05            ## the height a chopper naturally swings at
const NOTCH_H := 0.36            ## half-height of the wedge (V opening)
const NOTCH_ANG := 1.15          ## half-angle the wedge wraps around the trunk
const HEART := Color(0.52, 0.39, 0.21)   ## fresh-cut heartwood
const BREAK_LIP := 0.12          ## the stump keeps a little wood above the notch

var height := 5.0
var trunk_r := 0.24
var bark_col := Color(0.24, 0.16, 0.11)
var leaf_col := Color(0.13, 0.29, 0.15)
var max_chops := 4
var chops := 4
var notch_depth := 0.0           ## metres of wood taken out of the struck side
var notch_ang := 0.0             ## which way the wedge faces (tree-local radians)
var cone_seed := 0
var felled := false

var _trunk: MeshInstance3D
var _cones: Array[MeshInstance3D] = []
var _col: CollisionShape3D
var _upper: Node3D               ## everything above the notch, once it's falling
var _fall_dir := Vector3.FORWARD


static func make(rng: RandomNumberGenerator) -> ChopTree:
	var t := ChopTree.new()
	t.height = rng.randf_range(3.5, 7.0)
	t.trunk_r = rng.randf_range(0.18, 0.30)
	t.bark_col = Color(0.22, 0.15, 0.10).lerp(Color(0.30, 0.20, 0.13), rng.randf())
	t.leaf_col = Color(0.10, 0.26, 0.13).lerp(Color(0.16, 0.34, 0.18), rng.randf())
	t.max_chops = 3 + int(t.height / 2.6)
	t.chops = t.max_chops
	t.cone_seed = rng.randi()
	return t


static func from_dict(d: Dictionary) -> ChopTree:
	var t := ChopTree.new()
	t.height = float(d.get("height", 5.0))
	t.trunk_r = float(d.get("trunk_r", 0.24))
	t.bark_col = Color(d.get("bark", Color(0.24, 0.16, 0.11)))
	t.leaf_col = Color(d.get("leaf", Color(0.13, 0.29, 0.15)))
	t.max_chops = int(d.get("max_chops", 4))
	t.chops = int(d.get("chops", t.max_chops))
	t.notch_depth = float(d.get("notch_depth", 0.0))
	t.notch_ang = float(d.get("notch_ang", 0.0))
	t.cone_seed = int(d.get("cone_seed", 0))
	t.felled = bool(d.get("felled", false))
	return t


func save_dict() -> Dictionary:
	return {"height": height, "trunk_r": trunk_r, "bark": bark_col, "leaf": leaf_col,
		"max_chops": max_chops, "chops": chops, "notch_depth": notch_depth,
		"notch_ang": notch_ang, "cone_seed": cone_seed, "felled": felled,
		"pos": position, "rot_y": rotation.y}


func break_height() -> float:
	## Where the trunk lets go: just above the wedge, unless the tree is short
	## enough that a waist-high notch would be most of it.
	var b: float = NOTCH_Y + BREAK_LIP
	if b > height - 0.6:
		b = maxf(height * 0.28, 0.35)
	return b


func _ready() -> void:
	## A reloaded stump comes back as a stump: rooted, wearing the wedge that
	## killed the tree, and no longer worth swinging at.
	add_to_group("tree_stumps" if felled else "trees")
	## Metas kept live so anything still reading the old contract keeps working.
	set_meta("height", height)
	set_meta("chops", chops)
	_build()


## ============================ Building it =================================


func _build() -> void:
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.vertex_color_use_as_albedo = true
	trunk_mat.roughness = 1.0
	## A notch bitten past the centre pinches the trunk into a sliver — draw
	## both sides so the wound never reads as a hole through the world.
	trunk_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trunk = MeshInstance3D.new()
	_trunk.material_override = trunk_mat
	add_child(_trunk)
	_col = CollisionShape3D.new()
	add_child(_col)

	if felled:
		var bh := break_height()
		_trunk.mesh = _trunk_mesh(0.0, bh, true, 0.0, false, true)
		var st := CapsuleShape3D.new()
		st.radius = maxf(0.34, trunk_r + 0.12)
		st.height = maxf(bh, st.radius * 2.0 + 0.01)
		_col.shape = st
		_col.position = Vector3(0, bh * 0.5, 0)
		return

	_trunk.mesh = _trunk_mesh(0.0, height, true)

	## Foliage: 3 stacked faceted cones, seeded so a reloaded tree is the
	## same tree it was when you saved.
	var rng := RandomNumberGenerator.new()
	rng.seed = cone_seed
	var foliage_mat := StandardMaterial3D.new()
	foliage_mat.albedo_color = leaf_col
	foliage_mat.roughness = 1.0
	var layers := 3
	for l in range(layers):
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		var t := float(l) / float(layers - 1)
		cm.top_radius = 0.0
		cm.bottom_radius = lerpf(2.0, 0.7, t) * rng.randf_range(0.9, 1.1)
		cm.height = 2.0
		cm.radial_segments = 6
		cone.mesh = cm
		cone.material_override = foliage_mat
		cone.position = Vector3(0, height * 0.62 + l * 1.35, 0)
		add_child(cone)
		_cones.append(cone)

	var cap := CapsuleShape3D.new()
	cap.radius = maxf(0.4, trunk_r + 0.15)
	cap.height = height
	_col.shape = cap
	_col.position = Vector3(0, height * 0.5, 0)


func _radius_at(y: float, ang: float, with_notch: bool) -> Vector2:
	## (radius, cut) at one point on the trunk skin. The wedge is a V in
	## elevation — deepest at its middle, closing to nothing top and bottom —
	## and wraps a bounded arc of the circumference, so what the axe removes
	## is a triangular bite, not a dent.
	var r := lerpf(trunk_r, trunk_r * 0.7, clampf(y / height, 0.0, 1.0))
	if not with_notch or notch_depth <= 0.0:
		return Vector2(r, 0.0)
	var dy := (y - NOTCH_Y) / NOTCH_H
	if absf(dy) >= 1.0:
		return Vector2(r, 0.0)
	var da := wrapf(ang - notch_ang, -PI, PI) / NOTCH_ANG
	if absf(da) >= 1.0:
		return Vector2(r, 0.0)
	var cut := notch_depth * (1.0 - absf(dy)) * (1.0 - da * da)
	var rr := maxf(r - cut, r * 0.10)
	return Vector2(rr, r - rr)


func _trunk_mesh(y0: float, y1: float, with_notch: bool, y_shift := 0.0,
		broken_bottom := false, broken_top := false) -> ArrayMesh:
	var cut_open: bool = with_notch and notch_depth > 0.0
	var seg: int = SEG_CUT if cut_open else SEG_PLAIN
	## Ring heights — coarse on plain wood, dense across the wedge so the V
	## resolves as an edge instead of a smudge.
	var ys: Array[float] = []
	var step := 0.42 if cut_open else 0.9
	var n := maxi(2, int(ceil((y1 - y0) / step)))
	for s in range(n + 1):
		ys.append(lerpf(y0, y1, float(s) / float(n)))
	if cut_open:
		for e: float in [NOTCH_Y - NOTCH_H, NOTCH_Y - NOTCH_H * 0.55,
				NOTCH_Y - NOTCH_H * 0.2, NOTCH_Y, NOTCH_Y + NOTCH_H * 0.2,
				NOTCH_Y + NOTCH_H * 0.55, NOTCH_Y + NOTCH_H]:
			if e > y0 + 0.02 and e < y1 - 0.02:
				ys.append(e)
		ys.sort()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  ## faceted wood — our art language
	var rings: Array = []
	var cols: Array = []
	for y: float in ys:
		var ring := PackedVector3Array()
		var rcol := PackedColorArray()
		for s in range(seg):
			var a := TAU * float(s) / float(seg)
			var rc := _radius_at(y, a, with_notch)
			ring.append(Vector3(cos(a) * rc.x, y - y_shift, sin(a) * rc.x))
			rcol.append(bark_col.lerp(HEART, clampf(rc.y / maxf(trunk_r * 0.12, 0.01), 0.0, 1.0)))
		rings.append(ring)
		cols.append(rcol)

	for i in range(rings.size() - 1):
		var r0: PackedVector3Array = rings[i]
		var r1: PackedVector3Array = rings[i + 1]
		var c0: PackedColorArray = cols[i]
		var c1: PackedColorArray = cols[i + 1]
		for s in range(seg):
			var s2 := (s + 1) % seg
			for pair: Array in [[r0[s], c0[s]], [r1[s], c1[s]], [r1[s2], c1[s2]],
					[r0[s], c0[s]], [r1[s2], c1[s2]], [r0[s2], c0[s2]]]:
				st.set_color(pair[1])
				st.add_vertex(pair[0])

	## Caps. A break face shows heartwood; a plain end just closes the tube.
	_cap(st, rings[0] as PackedVector3Array, true,
		HEART if broken_bottom else bark_col.darkened(0.3))
	_cap(st, rings[rings.size() - 1] as PackedVector3Array, false,
		HEART if broken_top else bark_col.darkened(0.3))
	st.generate_normals()
	return st.commit()


func _cap(st: SurfaceTool, ring: PackedVector3Array, downward: bool, col: Color) -> void:
	var c := Vector3.ZERO
	for v: Vector3 in ring:
		c += v
	c /= float(ring.size())
	for s in range(ring.size()):
		var s2 := (s + 1) % ring.size()
		var tri: Array = [c, ring[s], ring[s2]] if downward else [c, ring[s2], ring[s]]
		for v: Vector3 in tri:
			st.set_color(col)
			st.add_vertex(v)


func _rebuild_trunk() -> void:
	_trunk.mesh = _trunk_mesh(0.0, height, true)


## ============================= Chopping ===================================


func chop_hit(toward_chopper: Vector3) -> bool:
	## One bite of the axe. `toward_chopper` points from the tree out to
	## whoever swung — that's the face the wedge opens on. Returns true when
	## this was the swing that put it down.
	if felled:
		return false
	var lt := (global_transform.basis.inverse() * toward_chopper).normalized()
	if notch_depth <= 0.0:
		notch_ang = atan2(lt.z, lt.x)  ## the first bite decides the face
	chops = maxi(chops - 1, 0)
	set_meta("chops", chops)
	var bites := max_chops - chops
	## The wedge deepens on a curve that runs past the trunk's centre by the
	## last standing bite — which is exactly when a tree lets go.
	notch_depth = trunk_r * (0.42 + 0.95 * float(bites) / float(max_chops))
	_rebuild_trunk()
	var world_toward := (global_transform.basis * Vector3(cos(notch_ang), 0.0, sin(notch_ang))).normalized()
	if chops > 0:
		_shiver(world_toward)
		return false
	fell(-world_toward)
	return true


func _shiver(world_toward: Vector3) -> void:
	## The whole tree flinches away from the blow and comes back.
	var axis := Vector3.UP.cross(-world_toward)
	if axis.length_squared() < 0.001:
		axis = Vector3.RIGHT
	axis = (global_transform.basis.inverse() * axis.normalized()).normalized()
	var base_basis := basis
	var tw := create_tween()
	tw.tween_method(_tip_node.bind(self, axis, base_basis), 0.0, 0.035, 0.07)
	tw.tween_method(_tip_node.bind(self, axis, base_basis), 0.035, 0.0, 0.11)


func _tip_node(a: float, node: Node3D, axis: Vector3, base_basis: Basis) -> void:
	if is_instance_valid(node):
		node.basis = Basis(axis, a) * base_basis


## ============================== Timber ====================================


func fell(fall_dir: Vector3) -> void:
	if felled:
		return
	felled = true
	remove_from_group("trees")
	add_to_group("tree_stumps")   ## what's left is part of the world now
	fall_dir.y = 0.0
	if fall_dir.length_squared() < 0.001:
		fall_dir = Vector3.FORWARD
	_fall_dir = fall_dir.normalized()

	var break_y: float = break_height()

	## What stays rooted: a stump wearing the wedge that killed the tree.
	_trunk.mesh = _trunk_mesh(0.0, break_y, true, 0.0, false, true)
	var stump := CapsuleShape3D.new()
	stump.radius = maxf(0.34, trunk_r + 0.12)
	stump.height = maxf(break_y, stump.radius * 2.0 + 0.01)
	_col.set_deferred("shape", stump)
	_col.position = Vector3(0, break_y * 0.5, 0)

	## What goes over: the trunk above the notch, canopy and all, hinged on
	## the wedge. Cones ride along — they only break on impact.
	_upper = Node3D.new()
	add_child(_upper)
	_upper.position = Vector3(0, break_y, 0)
	var um := MeshInstance3D.new()
	var umat := StandardMaterial3D.new()
	umat.vertex_color_use_as_albedo = true
	umat.roughness = 1.0
	um.material_override = umat
	um.mesh = _trunk_mesh(break_y, height, false, break_y, true, false)
	_upper.add_child(um)
	for c in _cones:
		if is_instance_valid(c):
			var cy: float = c.position.y - break_y
			remove_child(c)
			_upper.add_child(c)
			c.position = Vector3(0, cy, 0)

	var axis := Vector3.UP.cross(_fall_dir)
	if axis.length_squared() < 0.001:
		axis = Vector3.RIGHT
	axis = (global_transform.basis.inverse() * axis.normalized()).normalized()
	var base := Basis()
	var tw := create_tween()
	tw.tween_method(_tip_node.bind(_upper, axis, base), 0.0, deg_to_rad(84.0), 1.5) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(_crash.bind(break_y))


func _crash(break_y: float) -> void:
	## The crown hits the dirt. Everything comes apart at once.
	if not is_instance_valid(_upper):
		return
	var world := get_parent()
	var crash_at: Vector3 = _upper.global_transform * Vector3(0, (height - break_y) * 0.72, 0)
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("tree_crash_shake"):
		p.tree_crash_shake(crash_at)

	_shed_leaves()
	_split_into_logs(break_y, world)
	_scatter_sticks(crash_at, world)
	for _i in range(randi_range(4, 6)):
		var at := crash_at + Vector3(randf_range(-1.2, 1.2), 0.1, randf_range(-1.2, 1.2))
		var v := Vector3(randf_range(-1.5, 1.5), randf_range(1.4, 2.8), randf_range(-1.5, 1.5))
		world.add_child(RockDebris.make(at, v, false, true))
	_upper.queue_free()
	_upper = null


const LEAF_BLOWN := 0.16         ## the share of a canopy the wind actually takes


func _shed_leaves() -> void:
	## EVERY LEAF BREAKS OFF. The canopy stops being a shape and becomes a few
	## hundred separate things falling at their own speeds.
	##
	## Where they land matters as much as that they fall: MOST drop almost
	## straight down out of the crown they were part of, so what prints on the
	## ground is the SHAPE OF THE TOP OF THE TREE lying there — a leaf-litter
	## silhouette of the canopy that crashed. Only a minority (LEAF_BLOWN)
	## catch the wind, and those travel: a couple of metres out to fifteen at
	## the very most, all on the same bearing, because it's one gust.
	var world := get_parent()
	var ga := randf() * TAU
	var gust := Vector3(cos(ga), 0.0, sin(ga))
	for c in _cones:
		if not is_instance_valid(c):
			continue
		var cm := c.mesh as CylinderMesh
		var rad: float = 1.4 if cm == null else cm.bottom_radius
		var count := clampi(int(16.0 + rad * 16.0), 14, 46)
		var origin: Vector3 = c.global_position
		for _i in range(count):
			var a := randf() * TAU
			var rr := sqrt(randf()) * rad
			var at := origin + c.global_transform.basis * Vector3(
				cos(a) * rr, randf_range(-0.9, 0.9), sin(a) * rr)
			var col := leaf_col.lerp(Color(0.36, 0.30, 0.14), randf() * 0.45)
			## Barely any push: it comes off where it grew and drops there.
			var v := Vector3(randf_range(-0.35, 0.35), randf_range(0.0, 0.8),
				randf_range(-0.35, 0.35))
			var fl := FallingLitter.make("leaf", at, v, col, randf_range(0.8, 1.35))
			world.add_child(fl)
			if randf() < LEAF_BLOWN:
				fl.carry(gust + Vector3(randf_range(-0.35, 0.35), 0.0, randf_range(-0.35, 0.35)),
					randf_range(2.0, 15.0), maxf(at.y, 0.6))
		c.visible = false
		c.queue_free()
	_cones.clear()


func _split_into_logs(break_y: float, world: Node) -> void:
	## The trunk breaks into as many logs as the tree stood metres tall.
	var span := height - break_y
	var n := clampi(int(round(height)), 2, 8)
	var seg := span / float(n)
	var along: Vector3 = (_upper.global_transform.basis * Vector3.UP).normalized()
	for i in range(n):
		var mid: float = (float(i) + 0.5) * seg
		var at: Vector3 = _upper.global_transform * Vector3(0, mid, 0)
		var r := lerpf(trunk_r, trunk_r * 0.7, clampf((break_y + mid) / height, 0.0, 1.0))
		var cl := CarryLog.make(seg * 0.86, r, bark_col)
		world.add_child(cl)
		cl.global_position = at + Vector3.UP * 0.12
		## Lie along the fall line (the log mesh runs down its local Z).
		var look := at + along
		if absf(along.y) < 0.94:
			cl.look_at(look, Vector3.UP)
		## They don't stay stacked: each section kicks a little off the line.
		var side := along.cross(Vector3.UP).normalized()
		cl.toss(side * randf_range(-1.5, 1.5) + Vector3.UP * randf_range(0.4, 1.3)
			+ _fall_dir * randf_range(-0.3, 0.7))


func _scatter_sticks(at: Vector3, world: Node) -> void:
	## The branches shatter where the crown lands — real pickups, look + E.
	for _i in range(randi_range(2, 4)):
		var stick := DroppedItem.make({"name": "Stick", "weight": 0.3, "count": 1, "slot": ""})
		world.add_child(stick)
		stick.global_position = at + Vector3(randf_range(-1.0, 1.0), 0.35, randf_range(-1.0, 1.0))
		stick.velocity = Vector3(randf_range(-2.0, 2.0), randf_range(1.5, 3.0), randf_range(-2.0, 2.0))
