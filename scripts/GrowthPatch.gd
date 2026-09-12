class_name GrowthPatch
extends Node3D

## ===========================================================================
## A patch of something growing over something else -- moss, fungi, vines or
## lichen creeping across a trunk, a boulder, the brow of a cave mouth.
##
## Lemon (2026-09-03): "a two layer moss system where each layer has some patch
## of moss/vines/fungi (we're gonna be reusing this growing patch) that's
## slightly transparent and can grow over a tree over time ... make sure that
## this patch is saved too" -- "also make it applicable to rocks" -- "and cave
## entrances".
##
## HOW IT WORKS
##   1. The host parents one of these at its own origin and gives it an ANCHOR:
##      where on the host the patch's heart is and how far it spreads. Two
##      shapes of anchor cover everything in the game:
##        CYLINDER  a height and an angle round a trunk (trees, stumps)
##        POINT     a centre and a facing on a lump (rocks, a cave cap)
##   2. On the next physics frame the patch PROBES the host with rays -- against
##      a throwaway trimesh built from the host's real meshes when it has them
##      (a trunk carries its bark relief; a boulder's collider is a box, its
##      mesh is not), or against the world when the host is the world itself
##      (a cave mouth is voxel chunks with deferred trimesh colliders, so the
##      probe waits and retries until the rock is actually there).
##   3. Every hit becomes a CARD: layer 0, the BASE, is flush films and cushions;
##      layer 1, the ACCENT, is what stands proud of them -- bracket shelves,
##      toadstools, hanging strands. Which family, which base, which accent:
##      GrowthTypes. Cards near the heart are born first; growth.gdshader
##      reveals each card as the patch's one `growth` float passes its birth.
##   4. GrowthClock ticks `advance()` in game hours, scaled by rain, shade and
##      season. Nothing is rebuilt as it grows -- it is one uniform.
##
## SAVING. `to_dict()` carries the whole anchor, the type triple, the seed and
## the growth, so `from_dict()` rebuilds the same patch on the same host from
## the same seed and lands the same cards. A TreeV2 saves its patches inside
## its own save_dict; rocks and cave mouths are not serialised by the world at
## all (they are rebuilt from the world seed), so their patches carry a
## `host_key` and World.save_state keeps them in a "growth" ledger keyed on it.
## A loaded patch catches up on the game days it slept through (catch_up).
## ===========================================================================

enum Mode { CYLINDER, POINT }

## Probe collider layer -- something no gameplay ray ever asks for.
const PROBE_LAYER := 1 << 19
const WORLD_MASK := 1
const BASE_RAYS := Vector2i(40, 320)     ## probe rays for the base layer, min..max
const ACCENT_RAYS := Vector2i(12, 90)
const MIN_HITS := 8             ## fewer than this = the surface is not there yet
const MAX_TRIES := 8            ## ...so wait and try again this many times
const RETRY_FRAMES := 12        ## physics frames between tries
const VIS_RANGE := 75.0         ## metres; a fist of moss is nothing past this
const UP := Vector3.UP

## --- what it is --------------------------------------------------------------
var type_id := "moss"
var base_id := ""
var accent_id := ""
var seed_v := 0
var growth := 0.0               ## 0 nothing .. 1 fully grown
var shade := 0.6                ## 0 full sun .. 1 deep shade (host decides)
var damp := 0.0                 ## the host's own wet (a cave drips): adds to weather
var host_key := ""              ## "" = the host saves me; else World's ledger key
var last_day := -1.0            ## game day (float) of the last advance, for catch-up

## --- where it is (host-local) ------------------------------------------------
var mode := Mode.CYLINDER
var centre := Vector3.ZERO      ## CYLINDER: (0, y, 0)  POINT: the lump's centre
var facing := Vector3.FORWARD   ## POINT: outward direction of the heart
var facing_ang := 0.0           ## CYLINDER: angle round the trunk (atan2(x, z))
var span := Vector2(0.6, 0.9)   ## CYLINDER: (metres up, radians round)
                                ## POINT: (radians pitch, radians yaw)
var reach := 3.0                ## how far out the rays start
var inward := true              ## rays converge on the centre (false: diverge)
var area := 1.0                 ## m^2 the patch covers, for the card budget

## --- what to probe ------------------------------------------------------------
## MeshInstance3D nodes of the host to raycast against. Empty = the world.
var probe_meshes: Array = []
var probe_surface := -1         ## only this surface of each mesh (-1 = all)

## --- runtime ---------------------------------------------------------------
var _mi: MeshInstance3D = null
var _probe: StaticBody3D = null
var _state := 0                 ## 0 new, 1 waiting, 2 built, 3 gave up
var _wait := 0
var _tries := 0
var built := false
var card_count := 0
var base_count := 0
var accent_count := 0


## ------------------------------------------------------------- building ---

static func make(p_type: String, p_base: String, p_accent: String, p_seed: int) -> GrowthPatch:
	var g := GrowthPatch.new()
	g.type_id = p_type if GrowthTypes.TYPES.has(p_type) else "moss"
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	g.base_id = p_base if p_base != "" else GrowthTypes.pick_base(g.type_id, rng)
	g.accent_id = p_accent if p_accent != "" else GrowthTypes.pick_accent(g.type_id, rng)
	g.seed_v = p_seed
	return g


func anchor_cylinder(y: float, ang: float, span_up: float, span_round: float,
		p_reach: float, p_area: float) -> GrowthPatch:
	mode = Mode.CYLINDER
	centre = Vector3(0.0, y, 0.0)
	facing_ang = ang
	span = Vector2(span_up, span_round)
	reach = p_reach
	inward = true
	area = p_area
	return self


func anchor_point(p_centre: Vector3, p_facing: Vector3, span_pitch: float, span_yaw: float,
		p_reach: float, p_inward: bool, p_area: float) -> GrowthPatch:
	mode = Mode.POINT
	centre = p_centre
	facing = p_facing.normalized() if p_facing.length_squared() > 0.0001 else Vector3.FORWARD
	span = Vector2(span_pitch, span_yaw)
	reach = p_reach
	inward = p_inward
	area = p_area
	return self


static func shade_for(world_dir: Vector3) -> float:
	## How shaded a surface facing this way is. North (-Z, as bark.gdshader has
	## it) is the shaded side; anything facing down is under something.
	var d := world_dir.normalized()
	var north := 0.5 - 0.5 * d.z
	var under := clampf(-d.y, 0.0, 1.0)
	return clampf(0.15 + 0.85 * maxf(north, under), 0.0, 1.0)


func _ready() -> void:
	add_to_group("growth_patches")
	## the patch sits at the host's origin: patch-local IS host-local
	transform = Transform3D.IDENTITY
	## born now, unless a save said otherwise (catch_up reads this)
	if last_day < 0.0:
		last_day = GrowthClock.now_days()
	_state = 0
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	match _state:
		0:
			_begin_probe()
		1:
			_wait -= 1
			if _wait <= 0:
				_probe_and_build()
		_:
			set_physics_process(false)


func _begin_probe() -> void:
	if not probe_meshes.is_empty():
		_probe = StaticBody3D.new()
		_probe.collision_layer = PROBE_LAYER
		_probe.collision_mask = 0
		var faces := _collect_faces()
		if faces.is_empty():
			_probe.queue_free()
			_probe = null
			_state = 3
			return
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		var col := CollisionShape3D.new()
		col.shape = shape
		_probe.add_child(col)
		add_child(_probe)
	_state = 1
	_wait = 2      ## the physics server sees the new shape next step


func _collect_faces() -> PackedVector3Array:
	## Every triangle of every probe mesh, in host space.
	var host := get_parent()
	var out := PackedVector3Array()
	for m in probe_meshes:
		var mi := m as MeshInstance3D
		if mi == null or not is_instance_valid(mi) or mi.mesh == null:
			continue
		var xf := _rel_transform(mi, host)
		var mesh := mi.mesh
		for s in range(mesh.get_surface_count()):
			if probe_surface >= 0 and s != probe_surface:
				continue
			if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arr := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				for p in v:
					out.append(xf * p)
			else:
				for i in idx:
					out.append(xf * v[i])
	return out


static func _rel_transform(n: Node3D, host: Node) -> Transform3D:
	## n's transform in host's space, walking the parent chain -- no global
	## transforms, so this works the frame the host is added.
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != host:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _probe_and_build() -> void:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		_state = 3
		return
	var mask := PROBE_LAYER if _probe != null else WORLD_MASK
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	## as many rays as the card budget wants, and a few spare for misses
	var base: Dictionary = GrowthTypes.base_of(type_id, base_id)
	var acc: Dictionary = GrowthTypes.accent_of(type_id, accent_id)
	var nb := clampi(int(float(base["n"]) * area * 1.3), BASE_RAYS.x, BASE_RAYS.y)
	var na := clampi(int(float(acc["n"]) * area * 1.3), ACCENT_RAYS.x, ACCENT_RAYS.y)
	var hits_base := _cast_set(space, mask, rng, nb)
	var hits_acc := _cast_set(space, mask, rng, na)
	if hits_base.size() < MIN_HITS:
		_tries += 1
		if _tries < MAX_TRIES:
			_wait = RETRY_FRAMES
			return
		_finish_probe()
		_state = 3
		return
	_build_mesh(hits_base, hits_acc, rng)
	_finish_probe()
	_state = 2
	built = true


func _finish_probe() -> void:
	if _probe != null:
		_probe.queue_free()
		_probe = null


## One probe ray set. Each entry: {pos, normal, d} in patch space, d = 0 at the
## heart .. ~1 at the edge (what decides the card's birth order).
func _cast_set(space: PhysicsDirectSpaceState3D, mask: int, rng: RandomNumberGenerator,
		count: int) -> Array:
	var out: Array = []
	var to_world := global_transform
	var to_local := to_world.affine_inverse()
	for i in range(count):
		## bunched toward the heart: a sum of three uniforms
		var u := (rng.randf() + rng.randf() + rng.randf()) / 1.5 - 1.0
		var v := (rng.randf() + rng.randf() + rng.randf()) / 1.5 - 1.0
		var d := clampf(sqrt(u * u + v * v) / 1.15, 0.0, 1.0)
		var a: Vector3
		var b: Vector3
		if mode == Mode.CYLINDER:
			var y := centre.y + u * span.x
			var ang := facing_ang + v * span.y
			var dir := Vector3(sin(ang), 0.0, cos(ang))
			var axis := Vector3(centre.x, y, centre.z)
			a = axis + dir * reach
			b = axis
		else:
			var basis := _facing_basis()
			var pitch := u * span.x
			var yaw := v * span.y
			var dir := basis * Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
			if inward:
				a = centre + dir * reach
				b = centre
			else:
				a = centre
				b = centre + dir * reach
		var q := PhysicsRayQueryParameters3D.create(to_world * a, to_world * b, mask)
		q.collide_with_areas = false
		q.hit_back_faces = true
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var n: Vector3 = (to_local.basis * (hit["normal"] as Vector3)).normalized()
		## an outward-facing card wants a normal pointing back at the ray
		var ray_dir: Vector3 = (b - a).normalized()
		if n.dot(ray_dir) > 0.0:
			n = -n
		out.append({"pos": to_local * (hit["position"] as Vector3), "normal": n, "d": d})
	return out


func _facing_basis() -> Basis:
	## z = facing, y = as near world-up as the facing allows
	var z := facing.normalized()
	var up := UP if absf(z.dot(UP)) < 0.98 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z)


## ------------------------------------------------------------ the cards ---

class Buf:
	## Mutable builder -- a CLASS, not a Dictionary of packed arrays, because
	## Packed* arrays are value types and an append into a dictionary slot is
	## an append into a copy (the Grass v2 trap, again).
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var col := PackedColorArray()
	var c0 := PackedFloat32Array()
	var idx := PackedInt32Array()


func _build_mesh(hits_base: Array, hits_acc: Array, rng: RandomNumberGenerator) -> void:
	var fam := GrowthTypes.family(type_id)
	var base: Dictionary = GrowthTypes.base_of(type_id, base_id)
	var acc: Dictionary = GrowthTypes.accent_of(type_id, accent_id)
	var buf := Buf.new()

	## budget: cards per m^2 x the area the host says it covers, capped by the
	## rays that actually landed
	var n_base := clampi(int(float(base["n"]) * area), 10, hits_base.size())
	var n_acc := clampi(int(float(acc["n"]) * area), 3, hits_acc.size())
	## nearest-to-heart first, so the budget trims the fringe, not the middle
	hits_base.sort_custom(func(p, q): return float(p["d"]) < float(q["d"]))
	hits_acc.sort_custom(func(p, q): return float(p["d"]) < float(q["d"]))

	base_count = 0
	for i in range(n_base):
		var h: Dictionary = hits_base[i]
		var birth := clampf(0.02 + 0.72 * pow(float(h["d"]), 1.2) + rng.randf() * 0.06, 0.0, 0.99)
		var size := rng.randf_range(float(base["size"][0]), float(base["size"][1]))
		if _card(buf, h["pos"], h["normal"], size, String(base["style"]), birth, 0.0,
				int(base["tile"]), float(base["off"]), rng):
			base_count += 1
	accent_count = 0
	for i in range(n_acc):
		var h: Dictionary = hits_acc[i]
		var birth := clampf(0.45 + 0.50 * float(h["d"]) + rng.randf() * 0.06, 0.0, 0.99)
		var size := rng.randf_range(float(acc["size"][0]), float(acc["size"][1]))
		if _card(buf, h["pos"], h["normal"], size, String(acc["style"]), birth, 1.0,
				int(acc["tile"]), float(acc["off"]), rng):
			accent_count += 1
	card_count = base_count + accent_count
	if card_count == 0:
		return

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = buf.v
	arrays[Mesh.ARRAY_NORMAL] = buf.n
	arrays[Mesh.ARRAY_TEX_UV] = buf.uv
	arrays[Mesh.ARRAY_TEX_UV2] = buf.uv2
	arrays[Mesh.ARRAY_COLOR] = buf.col
	arrays[Mesh.ARRAY_CUSTOM0] = buf.c0
	arrays[Mesh.ARRAY_INDEX] = buf.idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)

	if _mi != null and is_instance_valid(_mi):
		_mi.queue_free()
	_mi = MeshInstance3D.new()
	_mi.name = "Growth"
	_mi.mesh = am
	_mi.material_override = GrowthTypes.material()
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.visibility_range_end = VIS_RANGE
	_mi.visibility_range_end_margin = 6.0
	_mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(_mi)
	var op: Array = fam.get("opacity", [0.82, 0.92])
	_mi.set_instance_shader_parameter("tint_base", _tint(base["tint"]))
	_mi.set_instance_shader_parameter("tint_accent", _tint(acc["tint"]))
	_mi.set_instance_shader_parameter("opacity", Vector2(float(op[0]), float(op[1])))
	_apply_growth()


func _tint(c: Color) -> Vector3:
	## each patch is its own shade of its colour -- seeded, so a load matches
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 31 + 7
	var k := 0.88 + rng.randf() * 0.24
	var warm := (rng.randf() - 0.5) * 0.08
	return Vector3(clampf(c.r * k + warm, 0.0, 1.0), clampf(c.g * k, 0.0, 1.0),
		clampf(c.b * k - warm, 0.0, 1.0))


## Append one card. Returns false if the style makes no sense on this normal
## (a bracket on a rock's top, a hanging strand on the floor) -- it is then
## re-cut as the nearest style that does.
func _card(buf: Buf, pos: Vector3, n: Vector3, size: float, style: String, birth: float,
		layer: float, tile: int, off: float, rng: RandomNumberGenerator) -> bool:
	var uvr := GrowthTypes.tile_rect(tile)
	var shade_c := 0.84 + rng.randf() * 0.22
	var col := Color(shade_c, shade_c, shade_c, 1.0)
	var flat := absf(n.y)               ## 1 = floor/ceiling, 0 = a wall
	match style:
		"shelf":
			if flat > 0.75:
				style = "cross"          ## a bracket needs a wall
		"hang":
			if n.y > 0.5:
				style = "cross"          ## nothing hangs off a floor
	match style:
		"flush":
			var pivot := pos + n * off
			var t1 := _tangent(n, rng.randf() * TAU)
			var t2 := n.cross(t1).normalized()
			var hs := size * 0.5
			_quad(buf,
				pivot - t1 * hs - t2 * hs, pivot + t1 * hs - t2 * hs,
				pivot + t1 * hs + t2 * hs, pivot - t1 * hs + t2 * hs,
				n, uvr, Vector2(0, layer), Vector2(0, layer), col, pivot, birth, false, false)
		"shelf":
			var out := Vector3(n.x, 0.0, n.z).normalized()
			var right := UP.cross(out).normalized()
			## a shelf grows a little downhill and flares as it goes
			var w := size * 0.9
			var len := size * rng.randf_range(0.7, 1.0)
			var tip := pos + out * len - UP * len * 0.18
			var root := pos + out * 0.005
			var pivot := root
			_quad(buf,
				root - right * w * 0.5, root + right * w * 0.5,
				tip + right * w * 0.62, tip - right * w * 0.62,
				UP.lerp(out, 0.3).normalized(), uvr, Vector2(0, layer), Vector2(0, layer),
				col, pivot, birth, true, false)
		"cross":
			var up := (n * 0.55 + UP * 0.85).normalized()
			var h := size
			var w := size * 0.85
			var foot := pos + n * off
			var r1 := _tangent(up, rng.randf() * TAU)
			var r2 := up.cross(r1).normalized()
			## a toadstool tile has its foot at the tile's bottom; the wisp tile
			## is painted rooted at the TOP and thinning down, so standing it up
			## as a tuft means rooting it at v = 0
			var root_v1 := tile != GrowthTypes.T_WISP
			for r in [r1, r2]:
				_quad(buf,
					foot - r * w * 0.5, foot + r * w * 0.5,
					foot + r * w * 0.5 + up * h, foot - r * w * 0.5 + up * h,
					n, uvr, Vector2(0, layer), Vector2(0, layer), col, foot, birth, root_v1, false)
		"hang":
			var right := UP.cross(n)
			if right.length_squared() < 0.05:
				right = _tangent(n, rng.randf() * TAU)
			right = right.normalized()
			var w := size * 0.45
			var top := pos + n * off
			var bottom := top - UP * size + n * off * 2.0
			_quad(buf,
				top - right * w * 0.5, top + right * w * 0.5,
				bottom + right * w * 0.5, bottom - right * w * 0.5,
				n, uvr, Vector2(0, layer), Vector2(1, layer), col, top, birth, false, true)
		_:
			return false
	return true


static func _tangent(n: Vector3, ang: float) -> Vector3:
	var ref := UP if absf(n.dot(UP)) < 0.9 else Vector3.RIGHT
	var t1 := ref.cross(n).normalized()
	var t2 := n.cross(t1).normalized()
	return (t1 * cos(ang) + t2 * sin(ang)).normalized()


## A quad a,b,c,d, a-b the ROOT edge (a shelf's wall edge, a mushroom's foot, a
## strand's top). `root_v1`: the root edge lands on the tile's BOTTOM row
## (brackets, conks and toadstools are painted growing up from v = 1); false
## puts it on the top row (strands and wisps hang from v = 0; flush cards do
## not care). `hang`: uv2.x runs 0 on a-b .. 1 on c-d, which the shader sways.
func _quad(buf: Buf, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3,
		uvr: Rect2, uv2a: Vector2, uv2b: Vector2, col: Color, pivot: Vector3, birth: float,
		root_v1: bool, hang: bool) -> void:
	var base := buf.v.size()
	var u0 := uvr.position.x
	var u1 := uvr.end.x
	var v0 := uvr.position.y
	var v1 := uvr.end.y
	var va := v1 if root_v1 else v0
	var vc := v0 if root_v1 else v1
	buf.v.append(a); buf.v.append(b); buf.v.append(c); buf.v.append(d)
	for i in range(4):
		buf.n.append(n)
		buf.col.append(col)
		buf.c0.append(pivot.x); buf.c0.append(pivot.y); buf.c0.append(pivot.z); buf.c0.append(birth)
	buf.uv.append(Vector2(u0, va)); buf.uv.append(Vector2(u1, va))
	buf.uv.append(Vector2(u1, vc)); buf.uv.append(Vector2(u0, vc))
	buf.uv2.append(uv2a); buf.uv2.append(uv2a); buf.uv2.append(uv2b); buf.uv2.append(uv2b)
	for i in [0, 1, 2, 0, 2, 3]:
		buf.idx.append(base + i)


## --------------------------------------------------------------- growing ---

func advance(hours: float, wet: float, days: float) -> void:
	## Called by GrowthClock. `wet` is the weather's, `days` the game clock.
	if hours <= 0.0:
		return
	var fam := GrowthTypes.family(type_id)
	var rate := GrowthClock.rate_for(fam, shade, damp, wet, days)
	growth = minf(growth + rate * hours, 1.0)
	last_day = days
	if _mi != null and is_instance_valid(_mi):
		_mi.set_instance_shader_parameter("growth", growth)
		_mi.set_instance_shader_parameter("wet", clampf(wet + damp * 0.5, 0.0, 1.0))


func set_growth(g: float) -> void:
	growth = clampf(g, 0.0, 1.0)
	_apply_growth()


func _apply_growth() -> void:
	if _mi != null and is_instance_valid(_mi):
		_mi.set_instance_shader_parameter("growth", growth)


func catch_up() -> void:
	## A save was closed for N game days: grow through them at a nominal
	## dampness, since nobody recorded the weather while the game was off.
	var now := GrowthClock.now_days()
	if now < 0.0 or last_day < 0.0:
		return
	var hours := (now - last_day) * 24.0
	if hours > 0.0:
		advance(hours, GrowthClock.NOMINAL_WET, now)


## ------------------------------------------------------------------ save ---

func to_dict() -> Dictionary:
	var d := {
		"type": type_id, "base": base_id, "accent": accent_id, "seed": seed_v,
		"growth": growth, "day": last_day, "shade": shade, "damp": damp,
		"mode": int(mode), "centre": [centre.x, centre.y, centre.z],
		"span": [span.x, span.y], "reach": reach, "inward": inward, "area": area,
	}
	if mode == Mode.CYLINDER:
		d["ang"] = facing_ang
	else:
		d["facing"] = [facing.x, facing.y, facing.z]
	if host_key != "":
		d["key"] = host_key
	return d


static func from_dict(d: Dictionary) -> GrowthPatch:
	var g := make(str(d.get("type", "moss")), str(d.get("base", "")),
		str(d.get("accent", "")), int(d.get("seed", 0)))
	g.growth = clampf(float(d.get("growth", 0.0)), 0.0, 1.0)
	g.last_day = float(d.get("day", -1.0))
	g.shade = float(d.get("shade", 0.6))
	g.damp = float(d.get("damp", 0.0))
	g.host_key = str(d.get("key", ""))
	g.mode = Mode.POINT if int(d.get("mode", 0)) == 1 else Mode.CYLINDER
	var c: Array = d.get("centre", [0, 0, 0])
	g.centre = Vector3(float(c[0]), float(c[1]), float(c[2]))
	var s: Array = d.get("span", [0.6, 0.9])
	g.span = Vector2(float(s[0]), float(s[1]))
	g.reach = float(d.get("reach", 3.0))
	g.inward = bool(d.get("inward", true))
	g.area = float(d.get("area", 1.0))
	g.facing_ang = float(d.get("ang", 0.0))
	var f: Array = d.get("facing", [0, 0, -1])
	g.facing = Vector3(float(f[0]), float(f[1]), float(f[2]))
	return g


## Apply a saved record to a patch that already exists (a rock's, whose host
## was rebuilt from the world seed and grew a fresh patch at the same key).
func apply_dict(d: Dictionary) -> void:
	growth = clampf(float(d.get("growth", growth)), 0.0, 1.0)
	last_day = float(d.get("day", last_day))
	_apply_growth()
	catch_up()


## Every patch under a node, in tree order.
static func patches_under(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is GrowthPatch:
			out.append(c)
	return out
