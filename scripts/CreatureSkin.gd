class_name CreatureSkin
extends Node3D
## ============================================================================
## CREATURE SKIN — real skeletons for a game whose bodies are made of boxes.
##
## Every creature in Myrkfell (nine mobs, 73 wild species, the third-person
## player) is authored as a tree of Node3D PIVOTS with BoxMesh parts hanging off
## them, and every animation in the game — Enemy._update_locomotion, the mobs'
## _animate chains, CritterAnim's 180 clips, the Player's SWING_KEYS — poses
## those pivots. That authoring is the whole studio; nothing here throws it out.
##
## bake(owner) walks the finished box rig ONCE and turns it into:
##   * a Skeleton3D whose bones mirror the pivot tree one-for-one, so every
##     existing pose write still lands (the skin copies pivot -> bone each
##     frame; the pivots stay the source of truth),
##   * ONE skinned ArrayMesh: each box becomes a rounded PSX segment (superellipse
##     rings, bevelled ends) weighted to its pivot's bone, with the joint end
##     blended toward the parent bone so knees, shoulders and necks flex instead
##     of hinging like a cupboard door,
##   * one ShaderMaterial (shaders/psx_skin.gdshader) fed by a 128x2 data
##     texture that mirrors the ORIGINAL box materials every frame — hit flash,
##     coat swap, eyeshine, buff glow, spectral legends, armour tint, and every
##     `visible` toggle on gear keep working with no callers changed. The old
##     MeshInstance3Ds stay in the tree as invisible proxies (mesh = null) so
##     every reference the game holds to them is still valid.
##   * a PhysicalBone3D ragdoll, built lazily the first time it is needed:
##     knockdowns, tramples, and death all run through it (ragdoll_start /
##     ragdoll_stop), with a pose blend on the way back up so a goblin gets to
##     its feet from where it fell instead of snapping to rest.
##   * mass-based SHOVING: creatures push each other (and corpses) by mass and
##     closing speed, and a heavy enough hit at speed knocks the lighter one
##     flat. That is the "trample" the sandbox asked for.
##
## Headless note: the renderer keeps none of this (dummy meshes), but the
## Skeleton3D bone maths, the data texture, and the physics all run, which is
## what tests/SkinTests.gd leans on.
## ============================================================================

const MAX_SEG := 128
const SHADER_PATH := "res://shaders/psx_skin.gdshader"
const OUTLINE_SHADER_PATH := "res://shaders/psx_outline.gdshader"   ## the creator's selection rim
const RAGDOLL_LAYER := 8          ## bit 8 (value 128): corpses and the knocked-down
const KNOCK_SPEED := 3.4          ## m/s of shove that puts something on the ground
const KNOCK_MASS_RATIO := 1.45    ## and the shover must outweigh it by this much
const CORPSE_SETTLE := 5.0        ## seconds a dead ragdoll keeps simulating
const CORPSE_LINGER := 16.0       ## then how long it lies frozen before it fades
const CORPSE_FADE := 1.6
const GETUP_BLEND := 0.45

static var _shader: Shader = null
static var _outline_shader: Shader = null
var _outline: MeshInstance3D = null    ## the inverted-hull rim (set_outline)
static var enabled := true        ## debug switch: false leaves the boxes as they are

var owner_node: Node3D = null
var skeleton: Skeleton3D = null
var mesh_inst: MeshInstance3D = null
var mat: ShaderMaterial = null
var mass := 60.0
var tile_world := 0.4

## segments
var seg_src: Array = []          ## Array[MeshInstance3D] — the proxy boxes
var seg_bone: PackedInt32Array = PackedInt32Array()
var _seg_col: PackedColorArray = PackedColorArray()
var _seg_emis: PackedColorArray = PackedColorArray()
var _seg_img: Image = null
var _seg_tex: ImageTexture = null

## bones
var bone_nodes: Array = []       ## Array[Node3D]; index = bone id; [0] is the synthetic root (null)
var _bone_of: Dictionary = {}    ## Node3D -> bone id
var _parent: Array = []          ## bone id -> parent bone id
var _rest_global: Array = []     ## bone id -> owner-space rest transform
var _g: Array = []               ## scratch: owner-space globals this frame
var _bone_geo: Dictionary = {}   ## bone id -> AABB (bone space) of its boxes
var _bone_vol: Dictionary = {}   ## bone id -> volume

## ragdoll
var ragdoll := false
var permanent := false
var frozen := false
var _phys_built := false
var _phys_bones: Array = []      ## Array[PhysicalBone3D]
var _phys_by_bone: Dictionary = {} ## bone id -> PhysicalBone3D
var _sim: PhysicalBoneSimulator3D = null
var _pelvis_bone := 0
var _ragdoll_t := 0.0
var _blend_t := 0.0
var _blend_from: Array = []      ## world-space bone global poses captured at stop
var _fade_t := -1.0
var _linger_t := 0.0
var _player: Node3D = null
var _player_scan := 0.0
var _last_sync_far := false


## ================================================================== bake ==

static func bake(who: Node3D, opts: Dictionary = {}) -> CreatureSkin:
	## Convert `owner`'s box rig into a skeleton + skinned PSX mesh. Call once,
	## after _build_body(). Returns the skin node (also stored as meta
	## "creature_skin" on the owner). opts:
	##   tile: String          default pattern tile (see PsxTex.TILES)
	##   exclude: Array[Node]  subtrees left as plain boxes (first-person arms)
	##   mass: float
	##   tile_world: float     metres of creature one texture tile spans
	var s := CreatureSkin.new()
	s.name = "CreatureSkin"
	s.owner_node = who
	s.mass = float(opts.get("mass", 60.0))
	who.add_child(s)
	if enabled:
		s._build(opts)
	who.set_meta("creature_skin", s)
	return s


static func of(n: Node) -> CreatureSkin:
	if n != null and n.has_meta("creature_skin"):
		var s = n.get_meta("creature_skin")
		if s is CreatureSkin and is_instance_valid(s):
			return s
	return null


static func owner_of(collider: Object) -> Object:
	## Raycasts that used to hit a creature's CharacterBody3D can now hit one of
	## its PhysicalBone3Ds instead. This maps the bone back to the creature so
	## `hit.collider == e` checks keep meaning what they meant.
	if collider is PhysicalBone3D:
		var p: Node = (collider as Node).get_parent()
		while p != null:
			if p.has_meta("creature_skin"):
				return p
			p = p.get_parent()
	return collider


func _build(opts: Dictionary) -> void:
	var excl: Array = opts.get("exclude", [])
	var def_tile := PsxTex.tile_index(String(opts.get("tile", "hide")))
	## ---- 1. find the boxes
	var boxes: Array = []
	_collect_boxes(owner_node, excl, boxes)
	if boxes.is_empty():
		return
	boxes = boxes.slice(0, MAX_SEG)
	## texel density scales with the animal
	var reach := 0.0
	for b in boxes:
		var bx := b as MeshInstance3D
		var p := _rel_to_owner(bx).origin
		reach = maxf(reach, p.length() + (bx.mesh as BoxMesh).size.length() * 0.5)
	tile_world = float(opts.get("tile_world", clampf(reach * 0.42, 0.14, 0.75)))

	## ---- 2. bones: one per pivot that carries boxes. The bone tree does NOT
	## have to mirror the node tree — poses are written in owner space every
	## frame — so a pivot with nothing on it (the wildlife `root`, an empty
	## shoulder) is skipped and its children hang from the nearest ancestor
	## that has flesh, or from the pelvis. That is what lets the ragdoll be
	## one connected body: every PhysicalBone3D joints to a real parent.
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton"
	add_child(skeleton)
	_plan_bones(boxes)

	## ---- 3. geometry
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var idx := PackedInt32Array()
	var rest_g: Array = _rest_global
	for si in boxes.size():
		var bx := boxes[si] as MeshInstance3D
		var bone: int = _bone_of.get(bx.get_parent(), 0)
		var parent_bone: int = _parent[bone] if bone > 0 else -1
		var tile := _tile_for(bx, def_tile)
		seg_src.append(bx)
		seg_bone.append(bone)
		_seg_col.append(Color(1, 1, 1, 1))
		_seg_emis.append(Color(0, 0, 0, 0))
		_emit_segment(bx, si, bone, parent_bone, tile, rest_g[bone],
			verts, norms, uvs, uv2s, bones, weights, idx)
		## proxy: keep the node (references, visibility, materials), drop the draw
		bx.mesh = null

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = weights
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh_inst = MeshInstance3D.new()
	mesh_inst.name = "Skin"
	mesh_inst.mesh = am
	skeleton.add_child(mesh_inst)
	mesh_inst.skeleton = mesh_inst.get_path_to(skeleton)
	mesh_inst.skin = skeleton.create_skin_from_rest_transforms()
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	## ---- 4. material + data texture
	_seg_img = Image.create(MAX_SEG, 2, false, Image.FORMAT_RGBAF)
	_seg_tex = ImageTexture.create_from_image(_seg_img)
	if _shader == null:
		_shader = load(SHADER_PATH)
	mat = ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("seg_tex", _seg_tex)
	mat.set_shader_parameter("pattern_tex", PsxTex.atlas())
	mesh_inst.material_override = mat
	_sync_segments(true)
	_sync_bones()


func _collect_boxes(n: Node, excl: Array, out: Array) -> void:
	if n is Skeleton3D or n is CreatureSkin or excl.has(n):
		return
	if n is MeshInstance3D and n != mesh_inst:
		var mi := n as MeshInstance3D
		if mi.mesh is BoxMesh and mi.material_override is StandardMaterial3D and mi.get_parent() is Node3D:
			out.append(mi)
	for c in n.get_children():
		_collect_boxes(c, excl, out)


func _plan_bones(boxes: Array) -> void:
	## Geometry pivots, their depth, their volume; then the pelvis; then ids
	## in an order that keeps every parent ahead of its children.
	var geo: Array = []            ## Node3D
	var vol: Dictionary = {}       ## node -> volume
	var depth: Dictionary = {}     ## node -> depth from owner
	for b in boxes:
		var bx := b as MeshInstance3D
		var pv := bx.get_parent() as Node3D
		if not vol.has(pv):
			geo.append(pv)
			vol[pv] = 0.0
			var d := 0
			var q: Node = pv
			while q != null and q != owner_node:
				d += 1
				q = q.get_parent()
			depth[pv] = d
		var sz := (bx.mesh as BoxMesh).size
		vol[pv] = float(vol[pv]) + sz.x * sz.y * sz.z
	## nearest geometry ancestor of each geometry pivot (null = top level)
	var geo_parent: Dictionary = {}
	for n in geo:
		var q: Node = (n as Node).get_parent()
		var found: Node = null
		while q != null and q != owner_node:
			if vol.has(q):
				found = q
				break
			q = q.get_parent()
		geo_parent[n] = found
	## pelvis: the biggest top-level pivot (volume over depth so a torso beats
	## a hoof of the same size)
	var pelvis: Node3D = null
	var best := -1.0
	for n in geo:
		if geo_parent[n] != null:
			continue
		var score: float = float(vol[n]) / float(depth[n])
		if score > best:
			best = score
			pelvis = n
	## order: pelvis, then everything by depth
	var order: Array = [pelvis]
	var rest: Array = geo.duplicate()
	rest.erase(pelvis)
	rest.sort_custom(func(a, b): return int(depth[a]) < int(depth[b]))
	order.append_array(rest)
	bone_nodes = [null]
	_parent = [-1]
	_rest_global = [Transform3D.IDENTITY]
	skeleton.add_bone("root")
	skeleton.set_bone_rest(0, Transform3D.IDENTITY)
	for n in order:
		var id := bone_nodes.size()
		var nm := String((n as Node).name)
		if nm == "" or nm.begins_with("@") or skeleton.find_bone(nm) >= 0:
			nm = "b%d" % id
		skeleton.add_bone(nm)
		bone_nodes.append(n)
		_bone_of[n] = id
		var gp: Node = geo_parent[n]
		var pid := 0
		if gp != null:
			pid = _bone_of[gp]
		elif n != pelvis:
			pid = 1   ## a loose top-level pivot hangs from the pelvis
		_parent.append(pid)
		skeleton.set_bone_parent(id, pid)
		var g := _rel_to_owner(n as Node3D)
		_rest_global.append(g)
		var local := g if pid == 0 else (_rest_global[pid] as Transform3D).affine_inverse() * g
		skeleton.set_bone_rest(id, local)
		skeleton.set_bone_pose_position(id, local.origin)
		skeleton.set_bone_pose_rotation(id, local.basis.get_rotation_quaternion())
		skeleton.set_bone_pose_scale(id, local.basis.get_scale())
	_pelvis_bone = 1


func _rel_to_owner(n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var p: Node = n
	while p != null and p != owner_node:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


func _tile_for(bx: MeshInstance3D, def_tile: int) -> int:
	if bx.has_meta("psx_tile"):
		return PsxTex.tile_index(String(bx.get_meta("psx_tile")))
	var m := bx.material_override as StandardMaterial3D
	if m != null and m.metallic > 0.3:
		return PsxTex.tile_index("metal")
	var s := (bx.mesh as BoxMesh).size
	if maxf(s.x, maxf(s.y, s.z)) < 0.09:
		return PsxTex.tile_index("flat")
	return def_tile


## ============================================================ geometry ====

func _emit_segment(bx: MeshInstance3D, seg: int, bone: int, parent_bone: int, tile: int,
		rest_g: Transform3D, verts: PackedVector3Array, norms: PackedVector3Array,
		uvs: PackedVector2Array, uv2s: PackedVector2Array, bones: PackedInt32Array,
		weights: PackedFloat32Array, idx: PackedInt32Array) -> void:
	var size := (bx.mesh as BoxMesh).size
	var xf := bx.transform                 ## box -> pivot (bone) space
	## longest axis of the box carries the rings
	var a := 0
	if size.y > size.x and size.y >= size.z:
		a = 1
	elif size.z > size.x and size.z > size.y:
		a = 2
	var b := (a + 1) % 3
	var c := (a + 2) % 3
	var L := size[a]
	var hb := size[b] * 0.5
	var hc := size[c] * 0.5
	var tiny := maxf(size.x, maxf(size.y, size.z)) < 0.09
	var bevel := 0.0 if tiny else minf(L * 0.22, minf(hb, hc) * 0.9)
	var end_scale := 0.9 if tiny else 0.66
	## ring stations along the axis: [pos, scale]
	var stations: Array = []
	if bevel > 0.001 and L > bevel * 2.2:
		stations = [[-L * 0.5, end_scale], [-L * 0.5 + bevel, 1.0], [L * 0.5 - bevel, 1.0], [L * 0.5, end_scale]]
	else:
		stations = [[-L * 0.5, end_scale], [L * 0.5, end_scale]]
	var ring_n := 8
	var base := verts.size()
	var joint_r := minf(hb, hc) * 1.8
	var box_centre_d := xf.origin.length()
	var blend_ok := parent_bone > 0 and box_centre_d > joint_r * 0.45
	## bone-space AABB for the ragdoll shape + volume
	var aabb := AABB(xf.origin, Vector3.ZERO)
	var perim := 2.0 * (size[b] + size[c])
	## cross-section: superellipse so a box reads as a rounded limb, not a crate
	for st in stations:
		var ax: float = st[0]
		var sc: float = st[1]
		for k in ring_n:
			var th := (float(k) + 0.5) / ring_n * TAU
			var cs := cos(th)
			var sn := sin(th)
			var pb := signf(cs) * pow(absf(cs), 0.7) * hb * sc
			var pc := signf(sn) * pow(absf(sn), 0.7) * hc * sc
			var v := Vector3.ZERO
			v[a] = ax
			v[b] = pb
			v[c] = pc
			var n := Vector3.ZERO
			n[b] = cs / maxf(hb, 0.001)
			n[c] = sn / maxf(hc, 0.001)
			n = n.normalized()
			if sc < 0.99:
				var tip := Vector3.ZERO
				tip[a] = signf(ax)
				n = (n + tip * 0.9).normalized()
			_push_vert(v, n, Vector2(float(k) / ring_n * perim / tile_world, (ax + L * 0.5) / tile_world),
				seg, tile, bone, parent_bone, blend_ok, joint_r, xf, rest_g,
				verts, norms, uvs, uv2s, bones, weights)
			aabb = aabb.expand(xf * v)
	## caps
	for e in 2:
		var ax := -L * 0.5 if e == 0 else L * 0.5
		var v := Vector3.ZERO
		v[a] = ax
		var n := Vector3.ZERO
		n[a] = signf(ax)
		_push_vert(v, n, Vector2(0.5 * perim / tile_world, (ax + L * 0.5) / tile_world),
			seg, tile, bone, parent_bone, blend_ok, joint_r, xf, rest_g,
			verts, norms, uvs, uv2s, bones, weights)
	var cap0 := base + stations.size() * ring_n
	var cap1 := cap0 + 1
	## side quads between rings
	for r in stations.size() - 1:
		for k in ring_n:
			var k1 := (k + 1) % ring_n
			var i0 := base + r * ring_n + k
			var i1 := base + r * ring_n + k1
			var i2 := base + (r + 1) * ring_n + k
			var i3 := base + (r + 1) * ring_n + k1
			_tri(idx, i0, i2, i1)
			_tri(idx, i1, i2, i3)
	## end fans
	var last := base + (stations.size() - 1) * ring_n
	for k in ring_n:
		var k1 := (k + 1) % ring_n
		## ...and the caps wind the same way the sides do. Both fans used to be
		## stated in the opposite order, which is the whole bug.
		_tri(idx, cap0, base + k, base + k1)
		_tri(idx, cap1, last + k1, last + k)
	## ragdoll bookkeeping
	if _bone_geo.has(bone):
		_bone_geo[bone] = (_bone_geo[bone] as AABB).merge(aabb)
	else:
		_bone_geo[bone] = aabb
	_bone_vol[bone] = float(_bone_vol.get(bone, 0.0)) + size.x * size.y * size.z


func _tri(idx: PackedInt32Array, i0: int, i1: int, i2: int) -> void:
	## Emit one triangle, CLOCKWISE as seen from outside — Godot's front face.
	##
	## THERE IS NO AXIS TERM HERE ANY MORE, AND THERE NEVER SHOULD HAVE BEEN.
	## The ring frame is (a, b, c) = (a, a+1, a+2) mod 3: a CYCLIC rotation of
	## (x, y, z), which is an EVEN permutation for all three values of a. So the
	## local frame is right-handed whichever axis is longest, and a winding that
	## is correct for one is correct for all of them. The old `if axis == 1:
	## swap` was not compensating for the frame — it was papering over the fact
	## that the SIDE quads and the END FANS below called this function with
	## opposite vertex orders. With the swap on, every Y-long segment's sides
	## were inside-out; with it off, every X- and Z-long segment's caps were.
	## Either way roughly half of every creature was invisible under the skin
	## shader's `cull_back`, which is what tests/SkinTests.gd::t_winding found
	## once its own comparison was pointing the right way round.
	idx.append(i0)
	idx.append(i1)
	idx.append(i2)


func _push_vert(v_local: Vector3, n_local: Vector3, uv: Vector2, seg: int, tile: int,
		bone: int, parent_bone: int, blend_ok: bool, joint_r: float,
		xf: Transform3D, rest_g: Transform3D,
		verts: PackedVector3Array, norms: PackedVector3Array, uvs: PackedVector2Array,
		uv2s: PackedVector2Array, bones: PackedInt32Array, weights: PackedFloat32Array) -> void:
	var v_bone := xf * v_local
	var n_bone := (xf.basis * n_local).normalized()
	verts.append(rest_g * v_bone)
	norms.append((rest_g.basis * n_bone).normalized())
	uvs.append(uv)
	uv2s.append(Vector2(float(seg), float(tile)))
	var wp := 0.0
	if blend_ok:
		wp = 0.5 * clampf(1.0 - v_bone.length() / maxf(joint_r, 0.001), 0.0, 1.0)
	bones.append(bone)
	bones.append(parent_bone if wp > 0.0 else bone)
	bones.append(bone)
	bones.append(bone)
	weights.append(1.0 - wp)
	weights.append(wp)
	weights.append(0.0)
	weights.append(0.0)


## ================================================================ sync =====

func _process(delta: float) -> void:
	## Render-side: mirror materials and pivots into the skin. No clocks here
	## — every timer lives in _physics_process, on the fixed step.
	if skeleton == null or owner_node == null or not is_instance_valid(owner_node):
		return
	_player_scan -= delta
	if _player_scan <= 0.0:
		_player_scan = 1.0
		_player = get_tree().get_first_node_in_group("player") as Node3D
	var far := false
	if _player != null and is_instance_valid(_player) and _player != owner_node:
		far = owner_node.global_position.distance_squared_to(_player.global_position) > 80.0 * 80.0
	if far and _last_sync_far and not ragdoll and _blend_t <= 0.0:
		return   ## asleep and out of sight: the pose it has is the pose it keeps
	## ⚠ `_blend_t > 0.0` HAS TO BE AN EXEMPTION, exactly like `ragdoll`.
	## `_tick_clocks` runs the get-up blend down on the fixed step whether or
	## not this function ever gets to apply it. Without the exemption, a
	## creature that is knocked over more than 80 m from the player stops
	## being synced the moment it stops ragdolling, the blend clock expires
	## against a pose nobody wrote, and it stands up FROZEN PART-WAY THROUGH
	## THE GET-UP — measured in tests/SkinTests.gd as a pelvis left 0.17 to
	## 0.32 m off its rest height, at a different height every time, and
	## staying there for as long as you keep your distance. The blend is a
	## handful of frames; sleeping through it saves nothing.
	_last_sync_far = far
	_sync_segments(false)
	if _fade_t >= 0.0:
		mat.set_shader_parameter("ghost", clampf(1.0 - _fade_t / CORPSE_FADE, 0.0, 1.0))
		return
	if ragdoll:
		_pull_bones_from_physics()
		return
	if frozen:
		return
	if _blend_t > 0.0:
		_sync_bones_blended(1.0 - clampf(_blend_t / GETUP_BLEND, 0.0, 1.0))
	else:
		_sync_bones()


func _tick_clocks(delta: float) -> void:
	## Fixed-step timers: the knockdown/corpse clock, the get-up blend, the fade.
	if _fade_t >= 0.0:
		_fade_t += delta
		if _fade_t >= CORPSE_FADE:
			_fade_t = -1.0
			owner_node.queue_free()
		return
	if ragdoll:
		_ragdoll_tick(delta)
		return
	if frozen and _linger_t > 0.0:
		_linger_t -= delta
		if _linger_t <= 0.0:
			_begin_fade()
		return
	if _blend_t > 0.0:
		_blend_t -= delta


func _apply_globals() -> void:
	## _g holds every bone's owner-space transform; write them as local poses.
	for i in range(1, bone_nodes.size()):
		var pid: int = _parent[i]
		var local: Transform3D = _g[i] if pid == 0 else (_g[pid] as Transform3D).affine_inverse() * (_g[i] as Transform3D)
		skeleton.set_bone_pose_position(i, local.origin)
		skeleton.set_bone_pose_rotation(i, local.basis.get_rotation_quaternion())
		skeleton.set_bone_pose_scale(i, local.basis.get_scale())


func _gather_globals() -> void:
	if _g.size() != bone_nodes.size():
		_g.resize(bone_nodes.size())
		_g[0] = Transform3D.IDENTITY
	for i in range(1, bone_nodes.size()):

		var n := bone_nodes[i] as Node3D
		if n == null or not is_instance_valid(n):
			_g[i] = _rest_global[i]
			continue
		_g[i] = _rel_to_owner(n)


func _sync_bones() -> void:
	_gather_globals()
	_apply_globals()


func _sync_bones_blended(k: float) -> void:
	## Getting up: bones travel from where the ragdoll left them to where the
	## animation wants them. Both ends are world poses.
	_gather_globals()
	var inv := skeleton.global_transform.affine_inverse()
	var e := k * k * (3.0 - 2.0 * k)
	for i in range(1, bone_nodes.size()):
		if i >= _blend_from.size():
			break
		var from_local: Transform3D = inv * (_blend_from[i] as Transform3D)
		_g[i] = from_local.interpolate_with(_g[i], e)
	_apply_globals()


func _sync_segments(force: bool) -> void:
	if _seg_img == null:
		return
	var dirty := force
	for i in seg_src.size():
		var src = seg_src[i]
		if src == null or not is_instance_valid(src):
			continue
		var mi := src as MeshInstance3D
		var m := mi.material_override as StandardMaterial3D
		if m == null:
			continue
		var col := m.albedo_color
		## alpha only counts when the material was actually transparent: a
		## StandardMaterial3D ignores it otherwise, and `col * 0.75` (a hoof)
		## quietly carries 0.75 alpha that must not dither the leg away
		if m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			col.a = 1.0
		if not mi.is_visible_in_tree():
			col.a = 0.0
		var em := Color(0, 0, 0, m.metallic)
		if m.emission_enabled:
			var ec := m.emission * m.emission_energy_multiplier
			em = Color(ec.r, ec.g, ec.b, m.metallic)
		if force or col != _seg_col[i] or em != _seg_emis[i]:
			_seg_col[i] = col
			_seg_emis[i] = em
			_seg_img.set_pixel(i, 0, col)
			_seg_img.set_pixel(i, 1, em)
			dirty = true
	if dirty:
		_seg_tex.update(_seg_img)


func set_flash(amount: float) -> void:
	if mat:
		mat.set_shader_parameter("flash", amount)


func set_outline(on: bool, col := Color(1, 1, 1), width := 0.035) -> void:
	## The selection rim (Lemon, 2026-09-14: "click on any character which
	## will outline them with white"): the skin's own skinned mesh drawn a
	## second time as an inverted hull (shaders/psx_outline.gdshader), so it
	## follows every bone and skips every hidden segment. Built lazily, kept
	## hidden when off; the Character Creator is the only caller today.
	if skeleton == null or mesh_inst == null:
		return
	if not on:
		if _outline != null and is_instance_valid(_outline):
			_outline.visible = false
		return
	if _outline == null or not is_instance_valid(_outline):
		if _outline_shader == null:
			_outline_shader = load(OUTLINE_SHADER_PATH)
		_outline = MeshInstance3D.new()
		_outline.name = "Outline"
		_outline.mesh = mesh_inst.mesh
		skeleton.add_child(_outline)
		_outline.skeleton = _outline.get_path_to(skeleton)
		_outline.skin = mesh_inst.skin
		_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var om := ShaderMaterial.new()
		om.shader = _outline_shader
		om.set_shader_parameter("seg_tex", _seg_tex)
		_outline.material_override = om
	var m := _outline.material_override as ShaderMaterial
	if m != null:
		m.set_shader_parameter("colour", col)
		m.set_shader_parameter("width", width)
	_outline.visible = true


func outline_on() -> bool:
	return _outline != null and is_instance_valid(_outline) and _outline.visible


func segment_count() -> int:
	return seg_src.size()


func bone_count() -> int:
	return skeleton.get_bone_count() if skeleton else 0


func segment_alpha(i: int) -> float:
	return _seg_col[i].a if i < _seg_col.size() else 0.0


func segment_colour(i: int) -> Color:
	return _seg_col[i] if i < _seg_col.size() else Color()


func bone_global(id: int) -> Transform3D:
	## World-space pose of a bone right now.
	return skeleton.global_transform * skeleton.get_bone_global_pose(id)


func pelvis_global() -> Transform3D:
	return bone_global(_pelvis_bone)


## ================================================================ poses ====
## A carcass wears the pose its death left it in (CarcassBody). These are the
## doors it uses: read a settled skeleton, write one back, and hold it.

func bone_of(n: Node) -> int:
	## The bone a pivot drives, or 0 for a node that carries no flesh.
	return int(_bone_of.get(n, 0))


func bone_aabb(id: int) -> AABB:
	## Bone-space box around everything the bone wears -- what the ragdoll
	## shape is cut from, and what a bone item is sized from.
	return _bone_geo.get(id, AABB())


func rest_global(id: int) -> Transform3D:
	return _rest_global[id] if id >= 0 and id < _rest_global.size() else Transform3D.IDENTITY


func parent_of(id: int) -> int:
	return int(_parent[id]) if id >= 0 and id < _parent.size() else -1


func bone_pose(id: int) -> Transform3D:
	## Owner-space pose of a bone right now (skeleton space == owner space:
	## the skin and its skeleton both sit at identity under the owner).
	## Works OFF the tree, which `bone_global` cannot.
	if skeleton == null or id < 0 or id >= skeleton.get_bone_count():
		return Transform3D.IDENTITY
	return skeleton.get_bone_global_pose(id)


func pose_globals() -> Array:
	## Every bone's owner-space pose, index = bone id, [0] identity. A frozen
	## corpse answers with the pose the ragdoll left it in.
	var out: Array = []
	if skeleton == null:
		return out
	for i in skeleton.get_bone_count():
		out.append(Transform3D.IDENTITY if i == 0 else skeleton.get_bone_global_pose(i))
	return out


func pose_apply(globals: Array) -> void:
	## Write a pose straight onto the bones and HOLD it: no pivots, no
	## physics, no clocks. After this call nothing in here moves a bone
	## again -- `frozen` short-circuits the sync, and the corpse clocks never
	## start because `_linger_t` stays at zero. The segment mirror keeps
	## running, so colour and `visible` on the proxies still land.
	if skeleton == null or globals.size() != bone_nodes.size():
		return
	if ragdoll and _sim != null:
		_sim.physical_bones_stop_simulation()
	ragdoll = false
	_blend_t = 0.0
	_fade_t = -1.0
	_linger_t = 0.0
	_g = globals.duplicate()
	_g[0] = Transform3D.IDENTITY
	_apply_globals()
	frozen = true
	permanent = true


## ============================================================== ragdoll ====

func _build_physics() -> void:
	if _phys_built or skeleton == null:
		return
	_phys_built = true
	## The 4.3+ way: a PhysicalBoneSimulator3D modifier under the skeleton
	## owns the bones (Skeleton3D.physical_bones_start_simulation is the
	## deprecated compat path and the project targets 4.7).
	_sim = PhysicalBoneSimulator3D.new()
	_sim.name = "Ragdoll"
	skeleton.add_child(_sim)
	var total_v := 0.0
	for id in _bone_vol.keys():
		total_v += float(_bone_vol[id])
	## One body per bone, box-shaped from the bone's own boxes. Every bone has
	## geometry (see _plan_bones), so every joint has a real parent body.
	for bid in range(1, skeleton.get_bone_count()):
		if not _bone_geo.has(bid):
			continue
		var pb := PhysicalBone3D.new()
		pb.name = "PB_" + skeleton.get_bone_name(bid)
		pb.bone_name = skeleton.get_bone_name(bid)
		var cs := CollisionShape3D.new()
		var box: AABB = _bone_geo[bid]
		var sz := box.size
		sz.x = maxf(sz.x, 0.04)
		sz.y = maxf(sz.y, 0.04)
		sz.z = maxf(sz.z, 0.04)
		pb.body_offset = Transform3D(Basis.IDENTITY, box.position + box.size * 0.5)
		## clamp the spread: a 150 kg torso jointed to a 0.2 kg ear is a
		## solver tantrum waiting to happen
		pb.mass = clampf(mass * float(_bone_vol.get(bid, 0.0)) / maxf(total_v, 0.0001), mass * 0.03, mass * 0.6)
		var shp := BoxShape3D.new()
		shp.size = sz * 0.92
		cs.shape = shp
		pb.collision_layer = 1 << (RAGDOLL_LAYER - 1)
		pb.collision_mask = 1 | (1 << (RAGDOLL_LAYER - 1))
		pb.linear_damp = 0.6
		pb.angular_damp = 3.0
		pb.friction = 0.55
		if skeleton.get_bone_parent(bid) <= 0:
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
		else:
			## A cone joint's axis is the joint frame's +X. Bones point their
			## geometry along -Y (limbs) or -Z (necks, tails), so the frame is
			## rotated to put +X down the limb — a cone that opens along the
			## bone instead of across it. Left as identity, every limb starts
			## 90 degrees outside its own cone and the solver spends the whole
			## ragdoll trying to fix that (the drift and the explosions).
			var box2: AABB = _bone_geo[bid]
			var along := (box2.position + box2.size * 0.5)
			if along.length() < 0.01:
				along = Vector3.DOWN
			along = along.normalized()
			pb.joint_offset = Transform3D(Basis(Quaternion(Vector3.RIGHT, along)), Vector3.ZERO)
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			pb.set("joint_constraints/swing_span", 70.0)
			pb.set("joint_constraints/twist_span", 35.0)
		pb.add_child(cs)
		_sim.add_child(pb)
		_phys_bones.append(pb)
		_phys_by_bone[bid] = pb
	## a body never collides with itself: overlapping bone boxes would fling
	## the whole thing apart on the first frame
	for i in _phys_bones.size():
		for j in range(i + 1, _phys_bones.size()):
			(_phys_bones[i] as PhysicalBone3D).add_collision_exception_with(_phys_bones[j])
	## ...nor with the CharacterBody3D it belongs to. (Skeleton3D's own
	## physical_bones_add_collision_exception goes through the deprecated
	## simulator path and did not reach these bones — the corpse sat on its
	## own capsule like a shelf.)
	if owner_node is CollisionObject3D:
		for pb in _phys_bones:
			(pb as PhysicalBone3D).add_collision_exception_with(owner_node)


func _pull_bones_from_physics() -> void:
	## Physics -> skeleton, explicitly. (PhysicalBone3D writes the pose back
	## itself on desktop builds, but doing it here keeps the bone poses honest
	## under every renderer and physics backend the tests run on.)
	if _g.size() != bone_nodes.size():
		_gather_globals()
	var inv := skeleton.global_transform.affine_inverse()
	for bid in range(1, skeleton.get_bone_count()):
		var pb: PhysicalBone3D = _phys_by_bone.get(bid, null)
		if pb == null:
			continue
		_g[bid] = inv * pb.global_transform * pb.body_offset.affine_inverse()
	_apply_globals()


func ragdoll_start(impulse: Vector3 = Vector3.ZERO, seconds := 2.4, is_death := false) -> void:
	## Let go of the pivots and hand the bones to physics. `impulse` is a
	## world-space kick applied at the pelvis (N·s-ish, scaled by mass inside).
	if skeleton == null or ragdoll:
		return
	_build_physics()
	if _phys_bones.is_empty():
		return
	_sync_bones()
	ragdoll = true
	frozen = false
	permanent = is_death
	_ragdoll_t = CORPSE_SETTLE if is_death else seconds
	_sim.physical_bones_start_simulation()
	var kick := impulse
	if is_death and kick.length() < 0.5:
		## a corpse with no blow behind it still needs to fall SOME way: four
		## stiff legs under a level body is a table, not a death
		var a := randf() * TAU
		kick = Vector3(cos(a), 0.0, sin(a)) * 1.6
	if kick.length() > 0.001:
		## a knockdown carries the shove's speed; a death only needs a nudge
		var carry := 0.35 if is_death else 0.6
		for pb in _phys_bones:
			var p := pb as PhysicalBone3D
			var share := p.mass / mass
			p.apply_central_impulse(kick * share * mass * carry)
		## and a shove high on the body so it topples rather than skids
		var pelvis := _phys_bone_for(_pelvis_bone)
		if pelvis:
			var top := Vector3.UP * maxf(0.15, _bone_geo.get(_pelvis_bone, AABB()).size.y * 0.5)
			pelvis.apply_impulse(kick * 0.5 * mass, top)
			## and let the legs go out from under it
			for pb2 in _phys_bones:
				var p2 := pb2 as PhysicalBone3D
				if p2 != pelvis:
					p2.apply_central_impulse(Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)) * p2.mass * 1.2)


func _phys_bone_for(id: int) -> PhysicalBone3D:
	return _phys_by_bone.get(id, null)


func _ragdoll_tick(delta: float) -> void:
	_ragdoll_t -= delta
	if _ragdoll_t > 0.0:
		return
	if permanent:
		## the corpse settles, then lies still (no physics cost), then fades
		_pull_bones_from_physics()
		_sim.physical_bones_stop_simulation()
		ragdoll = false
		frozen = true
		_linger_t = CORPSE_LINGER
		return
	## the owner stops us (and reads where the body is) if it knows how;
	## otherwise just get up in place
	if owner_node.has_method("_on_ragdoll_up"):
		owner_node.call("_on_ragdoll_up")
	else:
		ragdoll_stop()


func _begin_fade() -> void:
	_fade_t = 0.0


func ragdoll_stop() -> Dictionary:
	## Stop simulating and start the get-up blend. Returns where the body is:
	## {"pos": pelvis world position, "yaw": facing} so the owner can move its
	## CharacterBody3D to where it actually fell.
	if skeleton == null or not ragdoll:
		return {}
	_pull_bones_from_physics()
	_blend_from.clear()
	for i in bone_nodes.size():
		_blend_from.append(bone_global(i))
	_sim.physical_bones_stop_simulation()
	ragdoll = false
	frozen = false
	_blend_t = GETUP_BLEND
	var pel: Transform3D = _blend_from[_pelvis_bone]
	var fwd := -pel.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.05:
		fwd = -pel.basis.y
		fwd.y = 0.0
	var yaw := owner_node.rotation.y
	if fwd.length() > 0.05:
		yaw = atan2(-fwd.normalized().x, -fwd.normalized().z)
	return {"pos": pel.origin, "yaw": yaw}


func is_down() -> bool:
	return ragdoll or frozen


## ================================================================ shove =====

func _physics_process(delta: float) -> void:
	## Runs AFTER the owner's move_and_slide (children tick after parents), so
	## the slide collisions of this frame are fresh.
	if skeleton == null or owner_node == null or not is_instance_valid(owner_node):
		return
	_tick_clocks(delta)
	## the owner's lean/fidget layer runs here, after its _animate
	if owner_node.has_method("_update_flow"):
		owner_node.call("_update_flow", delta)
	if ragdoll or frozen:
		return
	if not (owner_node is CharacterBody3D):
		return
	var me := owner_node as CharacterBody3D
	var n := me.get_slide_collision_count()
	if n == 0:
		return
	for i in n:
		var col := me.get_slide_collision(i)
		var other := col.get_collider()
		## `velocity` is already the post-slide value (zero into a wall of
		## goblin); the motion it TRIED to make this step is travel + remainder
		var my_v := (col.get_travel() + col.get_remainder()) / maxf(delta, 0.0001)
		var dir := -col.get_normal()
		dir.y = 0.0
		if dir.length() < 0.01:
			continue
		dir = dir.normalized()
		if not (other is CharacterBody3D):
			continue
		var os := CreatureSkin.of(other)
		if os != null and os.is_down():
			continue
		var ob := other as CharacterBody3D
		var other_mass := os.mass if os != null else (float(other.get("mass")) if "mass" in other else 80.0)
		var rel := (my_v - ob.velocity).dot(dir)   ## how fast we close on it
		if rel <= 0.25:
			continue
		var share := mass / (mass + other_mass)
		var push := rel * share
		## a velocity to reach, not an impulse to stack: leaning on something
		## for a second must not wind it up to your own speed
		var cur := ob.velocity.dot(dir)
		if cur < push:
			var add := (push - cur) * 0.9
			var v := ob.velocity
			v.x += dir.x * add
			v.z += dir.z * add
			ob.velocity = v
		var back := rel * (1.0 - share) * 0.5
		me.velocity.x -= dir.x * back
		me.velocity.z -= dir.z * back
		## TRAMPLE: heavy and fast enough, and the smaller one goes down
		if push >= KNOCK_SPEED and mass >= other_mass * KNOCK_MASS_RATIO and other.has_method("knockdown"):
			var fling := dir * push * 0.6 + Vector3.UP * 0.25 * push
			other.call("knockdown", fling, clampf(1.6 + push * 0.25, 1.8, 3.4))
			if other.has_method("take_damage") and push > KNOCK_SPEED + 1.5:
				other.call("take_damage", minf((push - KNOCK_SPEED) * mass * 0.02, 20.0),
					me.global_position, false, Vector3.INF, me)
