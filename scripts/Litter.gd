class_name FallingLitter
extends Node3D
## CUT GRASS AND FALLEN LEAVES — the slow way down.
##
## A mown blade does not drop like a stone: it PLANES. This node carries one
## facet through a leaf's descent — a pendulum swing across a drift axis, a
## lazy rock about its own length, terminal velocity measured in centimetres —
## and the moment it touches dirt it hands its resting transform to the
## GrassSystem litter pool and disappears. What lies there afterwards is a
## MultiMesh instance, so an afternoon of mowing costs one draw call.
##
## Two kinds, one behaviour: "blade" (cut grass, matches the tuft geometry —
## same faceted no-texture language) and "leaf" (shaken off a falling canopy).

const GRAV := 3.1                ## a fraction of real gravity: air holds a leaf up
const SETTLE_LIFE := 24.0        ## safety net — nothing flutters forever
const GROUND_EPS := 0.02

static var _blade_mesh: ArrayMesh = null
static var _leaf_mesh: ArrayMesh = null

var kind := "blade"              ## "blade" | "leaf"
var col := Color(0.28, 0.38, 0.18)
var size := 1.0

var vel := Vector3.ZERO
var wind := Vector3.ZERO         ## a steady lateral push — this is what carries
                                 ## the few leaves that travel, while the rest
                                 ## drop straight into the canopy's own shadow
var _term := 0.0                 ## terminal fall speed (m/s); 0 = roll one in _ready
var _drift := Vector3.RIGHT      ## the axis the pendulum swings along
var _phase := 0.0
var _rate := 2.3                 ## pendulum speed
var _amp := 0.55                 ## pendulum reach
var _rock := 1.7                 ## rotation rate about the drift axis
var _spin := 0.9                 ## slow yaw as it comes down
var _life := SETTLE_LIFE
var _spawn := Vector3.ZERO
var _ray_t := randf() * 0.05     ## staggered ground checks (hundreds may fall at once)


static func make(p_kind: String, at: Vector3, v: Vector3, c: Color, s := 1.0) -> FallingLitter:
	var n := FallingLitter.new()
	n.kind = p_kind
	n.col = c
	n.size = s
	n.vel = v
	n._spawn = at
	return n


static func mesh_for(p_kind: String) -> ArrayMesh:
	## Shared geometry — the "sprite" for cut grass and for a fallen leaf.
	## Both are authored LYING FLAT in the XZ plane, so an identity transform
	## is already a blade at rest on the ground.
	if p_kind == "leaf":
		if _leaf_mesh == null:
			_leaf_mesh = _build_leaf()
		return _leaf_mesh
	if _blade_mesh == null:
		_blade_mesh = _build_blade()
	return _blade_mesh


static func _flat_fan(pts: PackedVector3Array) -> ArrayMesh:
	## Triangle fan around pts[0], normals up — the flat facet language.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, pts.size() - 1):
		for v: Vector3 in [pts[0], pts[i], pts[i + 1]]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	return st.commit()


static func _build_blade() -> ArrayMesh:
	## CUT GRASS: one blade of the same tapered facet the standing tufts are
	## made of, severed at the butt — wide where the sword went through,
	## drawn to a point, with a shallow crown so it catches the light instead
	## of reading as a flat sticker.
	var pts := PackedVector3Array([
		Vector3(-0.105, 0.000, -0.017),   ## the cut butt
		Vector3(-0.020, 0.007, -0.026),
		Vector3(0.060, 0.006, -0.019),
		Vector3(0.135, 0.000, 0.000),     ## the tip
		Vector3(0.060, 0.006, 0.019),
		Vector3(-0.020, 0.007, 0.026),
		Vector3(-0.105, 0.000, 0.017),
	])
	return _flat_fan(pts)


static func _build_leaf() -> ArrayMesh:
	## A canopy leaf: stem, shoulders, a rounded body, a drawn tip.
	var pts := PackedVector3Array([
		Vector3(-0.095, 0.000, 0.000),    ## stem
		Vector3(-0.040, 0.009, -0.034),
		Vector3(0.010, 0.013, -0.048),
		Vector3(0.062, 0.009, -0.032),
		Vector3(0.105, 0.000, 0.000),     ## tip
		Vector3(0.062, 0.009, 0.032),
		Vector3(0.010, 0.013, 0.048),
		Vector3(-0.040, 0.009, 0.034),
	])
	return _flat_fan(pts)


func _ready() -> void:
	global_position = _spawn
	var m := MeshInstance3D.new()
	m.mesh = mesh_for(kind)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.material_override = mat
	add_child(m)
	scale = Vector3.ONE * size
	## Every blade falls on its own bearing, at its own lazy pace.
	var a := randf() * TAU
	_drift = Vector3(cos(a), 0.0, sin(a))
	_phase = randf() * TAU
	_rate = randf_range(1.7, 3.1)
	_amp = randf_range(0.35, 0.80)
	_rock = randf_range(1.1, 2.4) * (1.0 if randf() < 0.5 else -1.0)
	_spin = randf_range(-1.4, 1.4)
	if _term <= 0.0:
		_term = randf_range(0.55, 0.95)
	rotation = Vector3(randf_range(-0.7, 0.7), randf() * TAU, randf_range(-0.7, 0.7))


func carry(dir: Vector3, metres: float, from_height: float) -> void:
	## Send this one TRAVELLING: pick the horizontal speed that lands it about
	## `metres` away given how far it has to fall, and slow its descent so it
	## has the time to get there. Used for the handful of leaves the wind takes
	## off a crashing canopy, and for the later gusts that lift them again.
	_term = randf_range(0.30, 0.55)
	_life = SETTLE_LIFE
	var fall_time := maxf(from_height, 0.4) / _term
	wind = dir.normalized() * (metres / maxf(fall_time, 0.5))
	_amp = randf_range(0.5, 1.0)   ## a travelling leaf tacks harder


func _process(delta: float) -> void:
	_life -= delta
	_phase += _rate * delta
	## The toss decays into a planing descent: horizontal speed bleeds off,
	## vertical eases onto terminal velocity instead of accelerating away.
	vel.x = move_toward(vel.x, 0.0, delta * 2.6)
	vel.z = move_toward(vel.z, 0.0, delta * 2.6)
	vel.y = move_toward(vel.y, -_term, GRAV * delta)
	## The pendulum: a leaf slides sideways, stalls, and slides back.
	var swing := _drift * (cos(_phase) * _amp)
	global_position += (vel + swing + wind) * delta
	rotate_object_local(Vector3.RIGHT, _rock * delta)
	rotate(Vector3.UP, _spin * delta)
	if _life <= 0.0:
		_land(global_position, Vector3.UP)
		return
	if vel.y >= 0.0:
		return
	## The ground question is only worth asking a few times a second — a
	## crashing canopy puts a hundred of these in the air at once.
	_ray_t -= delta
	if _ray_t > 0.0:
		return
	_ray_t = 0.05
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.22, global_position + Vector3.DOWN * 0.30)
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return
	if global_position.y <= float((hit.position as Vector3).y) + GROUND_EPS:
		_land(hit.position as Vector3, hit.normal as Vector3)


func _land(at: Vector3, up: Vector3) -> void:
	## Touchdown: hand the resting pose to the litter pool and vanish. The
	## blade stays where it fell — mown grass is a mark on the world.
	var gs := get_tree().get_first_node_in_group("grass_system")
	if gs != null and gs.has_method("add_litter"):
		if up.length_squared() < 0.01 or up.y < 0.25:
			up = Vector3.UP
		up = up.normalized()
		var fwd := Vector3(cos(_phase), 0.0, sin(_phase))
		var right := up.cross(fwd)
		if right.length_squared() < 0.001:
			right = up.cross(Vector3.FORWARD)
		right = right.normalized()
		var b := Basis(right, up, right.cross(up).normalized())
		gs.add_litter(kind, Transform3D(b.scaled(Vector3.ONE * size),
			at + up * 0.012), col)
	queue_free()
