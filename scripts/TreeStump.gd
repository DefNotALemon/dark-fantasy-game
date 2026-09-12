class_name TreeStump
extends StaticBody3D

## ===========================================================================
## What's left standing.  docs/TREES_v2_SPEC.md §9
##
## Three more bites of the axe clears it: two firewood and a bare dirt scar you
## can plant a seed on. Stumps do not sprout — clearing one is how a felled
## clearing stops looking like a war zone.
## ===========================================================================

const CLEAR_HITS := 3
const STUMP_H := 0.42

## --- the break face --------------------------------------------------------
## A stump is not a dowel with a coaster on top. It wears TWO different kinds of
## wood: the bottom half of the wedge the chopper cut (the top half went with
## the log), which is clean and flat-faced, and everywhere else the fibres TORE
## when the trunk levered over on that wedge. The tear is this stump's own —
## seeded off the tree, so a reloaded stump rips exactly the way it did.
const SEG := 16              ## radial resolution
const TEAR_LOBES := 2        ## long fibres pull in a place or two...
const TEAR_JITTER := 0.45    ## ...and the rest is splinter noise

const BARK := {
	"maple": Color(0.145, 0.120, 0.105), "birch": Color(0.66, 0.66, 0.62),
	"oak": Color(0.125, 0.105, 0.092), "pine": Color(0.135, 0.105, 0.088),
	"fir": Color(0.115, 0.100, 0.092),
}
const HEART := Color(0.52, 0.39, 0.21)   ## fresh-cut heartwood, matches ChopTree

var species := "maple"
var radius := 0.3
## HOW TALL THE STUMP STANDS. The tree breaks on the notch, so this is however
## high the axe was working — a cut at the roots leaves a flush stump, one at
## your shoulder leaves a post. STUMP_H is only the fallback.
var height := STUMP_H
## The wedge this stump is wearing, in WORLD metres and radians, in the stump's
## own local frame (TreeV2._fell copies the tree's rotation.y across so the two
## frames are the same one). Zero depth = it came down without being chopped.
var notch_ang := 0.0
var notch_depth := 0.0
var notch_h := 0.40
var notch_arc := 1.20
var tear_seed := 0
var hits_left := CLEAR_HITS
var cleared := false


static func make(at: Vector3, r: float, species_id: String, h := STUMP_H) -> TreeStump:
	var s := TreeStump.new()
	s.position = at
	s.radius = r
	s.species = species_id
	s.height = maxf(h, 0.12)
	return s


func _ready() -> void:
	add_to_group("tree_stumps")
	add_to_group("choppable")

	if TreeV2.USE_PSX and _build_psx_stump():
		_add_collision()
		return

	_build_wood()
	_add_collision()


func _skin(y: float, a: float) -> Vector2:
	## (radius, cut) at one point on the stump's skin. The wedge is the BOTTOM
	## HALF of the chopper's notch — nothing at notch_h below the break, full
	## depth right at it — cut with exactly the curve TreeV2._carve_notch uses,
	## so the stump and the log it broke off match along the seam.
	var t := clampf(y / maxf(height, 0.001), 0.0, 1.0)
	var r := radius * lerpf(1.25, 0.98, clampf(t * 1.6, 0.0, 1.0))   ## root flare
	if notch_depth <= 0.0:
		return Vector2(r, 0.0)
	var da: float = absf(wrapf(a - notch_ang, -PI, PI))
	if da > notch_arc:
		return Vector2(r, 0.0)
	var fy: float = 1.0 - clampf((height - y) / maxf(notch_h, 0.001), 0.0, 1.0)
	if fy <= 0.0:
		return Vector2(r, 0.0)
	var fa: float = clampf((1.0 - da / notch_arc) / 0.35, 0.0, 1.0)
	var cut: float = notch_depth * fy * fa
	var rr: float = maxf(r - cut, r * 0.10)
	return Vector2(rr, r - rr)


func _wood_colour(cut: float) -> Color:
	## The bark shader reads (1 - COLOR.r) as "how much wood came off here":
	## white is untouched bark, black is bare heartwood. Same contract as
	## TreeV2._carve_notch, which is why the stump can wear the tree's own
	## material and still show a pale cut.
	var f: float = clampf(cut / maxf(notch_depth, 0.001), 0.0, 1.0)
	return Color(1.0 - f, 1.0 - f, 1.0 - f, 1.0)


func _face(st: SurfaceTool, col: Color, out_dir: Vector3,
		a: Array, b: Array, c: Array) -> void:
	## One triangle from three [position, uv] pairs, wound so its normal points
	## along `out_dir`. Guessing the winding of a generated ring is how you end
	## up with a stump you can see the inside of; this measures and flips.
	##
	## NOTE THE SIGN. Godot's front faces are CLOCKWISE, so the normal
	## generate_normals() gives a triangle is the NEGATIVE of the usual
	## (b-a) x (c-a). Measured, not assumed: with the other sign every side
	## vertex on this mesh came out facing into its own axis.
	var t1 := b
	var t2 := c
	if ((b[0] as Vector3) - (a[0] as Vector3)).cross(
			(c[0] as Vector3) - (a[0] as Vector3)).dot(out_dir) > 0.0:
		t1 = c
		t2 = b
	for v: Array in [a, t1, t2]:
		st.set_color(col)
		st.set_uv(v[1] as Vector2)
		st.add_vertex(v[0] as Vector3)


func _build_wood() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = tear_seed if tear_seed != 0 else hash(str(position))

	## How far the worst splinter stands above the break. A fat trunk tears
	## longer fibres than a sapling does.
	var tear_scale := clampf(radius * 1.15, 0.08, 0.85)
	var lobes := PackedFloat32Array()
	for _i in range(TEAR_LOBES):
		lobes.append(rng.randf() * TAU)
	var lobe_w := rng.randf_range(0.85, 1.75)
	var tear := PackedFloat32Array()
	tear.resize(SEG + 1)
	for s in range(SEG + 1):
		var a := TAU * float(s % SEG) / float(SEG)
		var pull := 0.0
		for l: float in lobes:
			pull = maxf(pull, maxf(1.0 - absf(wrapf(a - l, -PI, PI)) / lobe_w, 0.0))
		## Nothing tears where the axe already cut — that face is clean. The rip
		## climbs as you go round the back, where the hinge finally gave way.
		var torn := 1.0
		if notch_depth > 0.0:
			torn = clampf(absf(wrapf(a - notch_ang, -PI, PI)) / maxf(notch_arc, 0.01),
				0.0, 1.0)
			torn = torn * torn * torn      ## cubed: the cut face stays FLAT
		tear[s] = (pull * 0.8 + rng.randf() * TEAR_JITTER) * torn * tear_scale
	tear[SEG] = tear[0]        ## the seam column has to agree with itself

	## SEG + 1 columns, the last one a duplicate of the first at a WRAPPED UV:
	## sharing the seam vertex instead would run u backwards from +pi*r to
	## -pi*r across one quad and print a stripe of squashed bark down the stump.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	## ---- the standing wood: bark, and the bottom half of the wedge ----
	st.set_smooth_group(0)
	var ys: Array[float] = []
	var n := maxi(3, int(ceil(height / 0.30)))
	for i in range(n + 1):
		ys.append(height * float(i) / float(n))
	for f: float in [1.0, 0.72, 0.46, 0.24, 0.10]:
		var e := height - notch_h * f
		if e > 0.02 and e < height - 0.005:
			ys.append(e)
	ys.sort()

	var rings: Array = []      ## each: Array of [Vector3, Vector2]
	var cols: Array = []       ## each: PackedColorArray
	for y: float in ys:
		rings.append(_ring(y, PackedFloat32Array()))
		cols.append(_ring_cols(y))
	## ...and the torn rim, where every column ends at its own broken height.
	rings.append(_ring(height, tear))
	cols.append(_ring_cols(height))

	for i in range(rings.size() - 1):
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		var c0: PackedColorArray = cols[i]
		for s in range(SEG):
			var outward: Vector3 = ((r0[s][0] as Vector3) + (r0[s + 1][0] as Vector3)) * 0.5
			outward.y = 0.0
			if outward.length_squared() < 0.000001:
				outward = Vector3.RIGHT
			_face(st, c0[s], outward, r0[s], r1[s], r1[s + 1])
			_face(st, c0[s], outward, r0[s], r1[s + 1], r0[s + 1])

	## ---- the crown: torn heartwood, faceted so the splinters catch light ----
	st.set_smooth_group(-1)
	var heart := Color(0, 0, 0, 1)      ## fully bare — the shader paints the wood
	var lift := 0.0
	for s in range(SEG):
		lift += tear[s]
	lift = lift / float(SEG) * 0.55 + tear_scale * 0.10
	var rim: Array = rings[rings.size() - 1]
	var mid: Array = []
	for s in range(SEG + 1):
		var p: Vector3 = rim[s][0]
		## Weighted toward the LOCAL rim, not a global mound: the break face has
		## to slope from the clean cut face UP to the torn back, the way a
		## hinge actually gives. Pulling everything toward one central height
		## put a dome over the notch, which is the one place it should be flat.
		var my: float = lerpf(p.y, height + lift, 0.35) \
			+ (rng.randf() - 0.5) * tear_scale * 0.4
		## Never BELOW the break line: the jitter is splinters standing proud,
		## and a crown vertex that dips under the cut pokes out through the
		## side wall where the notch has pinched the trunk thin.
		my = maxf(my, height)
		var q := Vector3(p.x * 0.52, my, p.z * 0.52)
		mid.append([q, Vector2(q.x, q.z)])
	mid[SEG] = [Vector3((rim[0][0] as Vector3).x * 0.52, (mid[0][0] as Vector3).y,
		(rim[0][0] as Vector3).z * 0.52), mid[0][1]]
	var apex_p := Vector3(0, height + lift * 0.55, 0)
	var apex := [apex_p, Vector2(0, 0)]
	for s in range(SEG):
		## The rim's own UVs are arc-length; on the break face a flat overhead
		## projection is the honest one, so the crown re-projects its corners.
		var ra: Array = [rim[s][0], Vector2((rim[s][0] as Vector3).x, (rim[s][0] as Vector3).z)]
		var rb: Array = [rim[s + 1][0],
			Vector2((rim[s + 1][0] as Vector3).x, (rim[s + 1][0] as Vector3).z)]
		_face(st, heart, Vector3.UP, ra, mid[s], mid[s + 1])
		_face(st, heart, Vector3.UP, ra, mid[s + 1], rb)
		_face(st, heart, Vector3.UP, mid[s], apex, mid[s + 1])

	st.generate_normals()
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _bark_material(radius, height)
	add_child(mi)


func _ring(y: float, tear: PackedFloat32Array) -> Array:
	## One ring of [position, uv]. `tear` empty = a level ring; otherwise each
	## column is lifted to where its fibres broke. UVs are in METRES — arc
	## length across, height up — the same convention the tree meshes bake.
	var out: Array = []
	for s in range(SEG + 1):
		var a := TAU * float(s) / float(SEG)
		var yy: float = y + (tear[s] if s < tear.size() else 0.0)
		var sk := _skin(yy, a)
		out.append([Vector3(cos(a) * sk.x, yy, sin(a) * sk.x),
			Vector2(a * radius, yy)])
	return out


func _ring_cols(y: float) -> PackedColorArray:
	var out := PackedColorArray()
	for s in range(SEG + 1):
		out.append(_wood_colour(_skin(y, TAU * float(s) / float(SEG)).y))
	return out


func _add_collision() -> void:
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius * 1.1
	shape.height = height
	cs.shape = shape
	cs.position.y = height * 0.5
	add_child(cs)


func _build_psx_stump() -> bool:
	## The pack has two stumps. Scale the nearer one so its own trunk matches
	## the tree that stood here, and keep the pale cut face on top -- that disc
	## is the thing that says a person did this, and the pack's stump is a
	## weathered old one with bark right over the top.
	var asset := "SM_Stump_01" if radius >= 0.26 else "SM_Stump_02"
	var native_r := 0.40 if asset == "SM_Stump_01" else 0.28
	var packed = load(PSXNature.scene_path(asset))
	if packed == null:
		return false
	var m: Node3D = packed.instantiate()
	var s: float = clampf(radius / native_r, 0.45, 3.0)
	m.scale = Vector3.ONE * s
	m.rotation.y = randf() * TAU
	add_child(m)
	var mats := PSXNature.materials("Props", "temperate", false)
	for n in _all(m):
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh != null:
			for i in range(mi.mesh.get_surface_count()):
				mi.set_surface_override_material(i, mats[0])

	var top := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius * 0.92
	disc.bottom_radius = radius * 0.92
	disc.height = 0.02
	disc.radial_segments = 9
	top.mesh = disc
	top.position.y = float(PSXNature.info(asset).get("height", 0.7)) * s * 0.94
	var tm := StandardMaterial3D.new()
	tm.albedo_color = HEART
	tm.roughness = 0.9
	top.material_override = tm
	add_child(top)
	return true


func _all(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out


func chop_hit(_toward_chopper: Vector3, _aim := Vector3.INF) -> bool:
	if cleared:
		return false
	hits_left -= 1
	if hits_left > 0:
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector3(1.0, 0.94, 1.0), 0.05)
		tw.tween_property(self, "scale", Vector3.ONE, 0.14)
		return false
	_clear()
	return true


func _clear() -> void:
	cleared = true
	var world := get_parent()
	for _i in range(2):
		var w := DroppedItem.make({"name": "Firewood", "weight": 1.1, "count": 1, "slot": ""})
		world.add_child(w)
		w.global_position = global_position + Vector3(randf_range(-0.5, 0.5), 0.35,
			randf_range(-0.5, 0.5))
		w.velocity = Vector3(randf_range(-1.4, 1.4), randf_range(1.2, 2.2), randf_range(-1.4, 1.4))
	## The bare scar is plantable ground — TreeSeed checks for this group.
	var scar := Node3D.new()
	scar.add_to_group("planting_ground")
	world.add_child(scar)
	scar.global_position = global_position
	queue_free()


static func from_dict(d: Dictionary) -> TreeStump:
	var p: Array = d.get("pos", [0, 0, 0])
	var s := TreeStump.make(Vector3(float(p[0]), float(p[1]), float(p[2])),
		float(d.get("radius", 0.3)), str(d.get("species", "maple")),
		float(d.get("height", STUMP_H)))
	s.hits_left = int(d.get("hits", CLEAR_HITS))
	s.rotation.y = float(d.get("rot", 0.0))
	s.notch_ang = float(d.get("notch_ang", 0.0))
	s.notch_depth = float(d.get("notch", 0.0))
	s.notch_h = float(d.get("notch_h", 0.40))
	s.notch_arc = float(d.get("notch_arc", 1.20))
	s.tear_seed = int(d.get("tear", 0))
	return s


func save_dict() -> Dictionary:
	return {"kind": "stump", "species": species, "radius": radius, "hits": hits_left,
		"height": height, "rot": rotation.y,
		"notch_ang": notch_ang, "notch": notch_depth, "notch_h": notch_h,
		"notch_arc": notch_arc, "tear": tear_seed,
		"pos": [global_position.x, global_position.y, global_position.z]}


func _bark_material(_r: float, _along: float) -> Material:
	## One shared ShaderMaterial per species would tile wrongly on differently
	## sized logs, so this takes a duplicate and sets the tiling for THIS piece.
	var base: Material = TreeV2.materials_for(species)[0]
	var m: ShaderMaterial = (base as ShaderMaterial).duplicate()
	## The generated stump bakes its UVs in METRES (arc length across, height
	## up) exactly like the tree meshes, so tiling is repeats-per-metre and the
	## bark lands at the same texel density it had on the standing trunk. The
	## old numbers here were scaled for a CylinderMesh's 0..1 UVs.
	m.set_shader_parameter("tiling", Vector2(1.6, 1.6))
	m.set_shader_parameter("sway", 0.0)      ## it is on the ground; it does not sway
	return m
