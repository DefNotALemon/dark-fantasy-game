extends SceneTree
## ===========================================================================
## SKELETON / PSX SKIN / RAGDOLL / SHOVE / FLOW — the regression net.
##
##   godot --headless --path . --script res://tests/SkinTests.gd
##
## Runs against the REAL Enemy, Critter, mobs, CreatureSkin and PsxTex. The
## headless renderer keeps no mesh data, so everything here is measured off
## the Skeleton3D, the data texture and the physics — which is exactly where
## the bugs were (see docs/SKELETON_SKIN.md).
## ===========================================================================

const MIN_ASSERTIONS := 360

var pass_n := 0
var fail_n := 0
var fails: Array = []
var _world: Node3D
var _player: LabPlayer


func ok(cond: bool, what: String) -> void:
	if cond:
		pass_n += 1
	else:
		fail_n += 1
		fails.append(what)
		print("  FAIL: ", what)


func eq(a, b, what: String) -> void:
	ok(a == b, "%s (got %s, want %s)" % [what, str(a), str(b)])


func near(a: float, b: float, tol: float, what: String) -> void:
	ok(absf(a - b) <= tol, "%s (got %.4f, want %.4f +-%.4f)" % [what, a, b, tol])


func _init() -> void:
	print("=== Myrkfell skin tests ===")
	_world = Node3D.new()
	root.add_child(_world)
	_world.add_to_group("world")
	var flr := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(400, 1, 400)
	cs.shape = bs
	flr.add_child(cs)
	flr.position.y = -0.5
	_world.add_child(flr)
	_player = LabPlayer.new()
	_world.add_child(_player)
	_player.position = Vector3(60, 0, 60)   ## far: nothing notices it
	await process_frame

	t_atlas()
	await t_bake_all()
	await t_winding()
	await t_sync()
	await t_ragdoll()
	await t_shove()
	await t_flow()
	await t_layers()

	print("=== %d passed, %d failed ===" % [pass_n, fail_n])
	var ran := pass_n + fail_n
	if ran < MIN_ASSERTIONS:
		fail_n += 1
		fails.append("the suite ran only %d assertions (expected at least %d) — a section probably returned early" % [ran, MIN_ASSERTIONS])
	for f in fails:
		print("  - ", f)
	quit(0 if fail_n == 0 else 1)


func _spawn(e: Node3D, at: Vector3) -> Node3D:
	_world.add_child(e)
	e.global_position = at
	if e is Enemy:
		(e as Enemy).confused = true
	return e


func _step(frames: int) -> void:
	for i in frames:
		await physics_frame


## ------------------------------------------------------------- atlas ------

func t_atlas() -> void:
	print("-- atlas --")
	var img := PsxTex.image()
	eq(img.get_width(), 256, "atlas is 256 wide")
	eq(img.get_height(), 256, "atlas is 256 tall")
	eq(PsxTex.TILES.size(), 16, "16 tiles")
	for k in PsxTex.TILES.keys():
		var t: int = PsxTex.TILES[k]
		var ox := (t % 4) * 64
		@warning_ignore("integer_division")
		var oy := (t / 4) * 64
		var lo := 2.0
		var hi := -1.0
		for i in 64:
			var c := img.get_pixel(ox + i, oy + (i * 7) % 64)
			lo = minf(lo, c.r)
			hi = maxf(hi, c.r)
		ok(hi <= 1.0 and lo >= 0.3, "tile %s stays in a sane luminance band (%.2f..%.2f)" % [k, lo, hi])
		ok(hi - lo > 0.02 or k == "flat", "tile %s has detail" % k)
	ok(PsxTex.atlas() == PsxTex.atlas(), "atlas texture is cached")
	## the shader must compile-load
	var sh := load(CreatureSkin.SHADER_PATH) as Shader
	ok(sh != null, "psx_skin shader loads")


## ---------------------------------------------------------- bake all ------

func t_bake_all() -> void:
	print("-- bake --")
	## the nine mobs
	var mobs: Array = [Goblin.new(), Kobold.new(), Orc.new(), Ogre.new(), Skeleton.new(),
		DarkKnight.new(), Boar.new(), Horse.new(), SaddledHorse.new()]
	var x := 0.0
	for m in mobs:
		_spawn(m, Vector3(x, 0.05, -20))
		x += 4.0
	await process_frame
	for m in mobs:
		var e := m as Enemy
		var nm := String(e.get_script().get_global_name())
		ok(e.skin != null, "%s baked a skin" % nm)
		if e.skin == null:
			continue
		ok(e.skin.bone_count() > 1, "%s has bones (%d)" % [nm, e.skin.bone_count()])
		ok(e.skin.segment_count() >= 6, "%s has segments (%d)" % [nm, e.skin.segment_count()])
		ok(e.mass > 0.0 and e.skin.mass == e.mass, "%s mass reached the skin (%.0f)" % [nm, e.mass])
		ok(e.skin.mesh_inst != null and e.skin.mesh_inst.mesh != null, "%s has a skinned mesh" % nm)
		ok(e.skin.mesh_inst.skin != null, "%s has bind poses" % nm)
		var proxies_hidden := true
		for src in e.skin.seg_src:
			if (src as MeshInstance3D).mesh != null:
				proxies_hidden = false
		ok(proxies_hidden, "%s: every source box became a proxy (mesh = null)" % nm)
		## every bone carries geometry (no hubs: the ragdoll needs real parents)
		var geo_all := true
		for b in range(1, e.skin.bone_count()):
			if not e.skin._bone_geo.has(b):
				geo_all = false
		ok(geo_all, "%s: every bone has geometry" % nm)
		## bone 1 is the pelvis and hangs from the root
		eq(e.skin._parent[1], 0, "%s: pelvis bone hangs from root" % nm)
		## parent ids precede children
		var ordered := true
		for b in range(1, e.skin.bone_count()):
			if int(e.skin._parent[b]) >= b:
				ordered = false
		ok(ordered, "%s: bone parents precede their children" % nm)
		## body_mat proxy is one of the segments
		var has_body := false
		for src in e.skin.seg_src:
			if (src as MeshInstance3D).material_override == e.body_mat:
				has_body = true
		ok(has_body or e.body_mat == null, "%s: body_mat box is a skinned segment" % nm)
		e.queue_free()
	## mesh arrays sanity on one
	var g := Goblin.new()
	_spawn(g, Vector3(0, 0.05, -30))
	await process_frame
	var am := g.skin.mesh_inst.mesh as ArrayMesh
	var arr := am.surface_get_arrays(0)
	var nv := (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	eq((arr[Mesh.ARRAY_BONES] as PackedInt32Array).size(), nv * 4, "4 bone slots per vertex")
	eq((arr[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array).size(), nv * 4, "4 weights per vertex")
	eq((arr[Mesh.ARRAY_TEX_UV2] as PackedVector2Array).size(), nv, "uv2 carries segment + tile per vertex")
	var w := arr[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
	var sums_ok := true
	var blended := 0
	for i in nv:
		var sum := w[i * 4] + w[i * 4 + 1] + w[i * 4 + 2] + w[i * 4 + 3]
		if absf(sum - 1.0) > 0.001:
			sums_ok = false
		if w[i * 4 + 1] > 0.0:
			blended += 1
	ok(sums_ok, "weights sum to one")
	ok(blended > 0, "some vertices blend toward the parent bone (joints flex): %d" % blended)
	var uv2 := arr[Mesh.ARRAY_TEX_UV2] as PackedVector2Array
	var seg_max := 0.0
	for v in uv2:
		seg_max = maxf(seg_max, v.x)
	eq(int(seg_max) + 1, g.skin.segment_count(), "uv2.x indexes every segment")
	eq((arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() % 3, 0, "index buffer is triangles")
	g.queue_free()

	## every species in the dex bakes
	var baked := 0
	var boxless := 0
	for key in CritterDex.DEX.keys():
		var p: Dictionary = CritterDex.get_profile(key)
		if String(p.get("rig", "")) == "SWARM":
			continue
		var c := Critter.make(key)
		_spawn(c, Vector3(0, 0.05, 40))
		await process_frame
		if c.skin != null and c.skin.bone_count() > 1:
			baked += 1
			ok(c.skin.segment_count() == c.skin.seg_src.size(), "%s: segment bookkeeping" % key)
			ok(c.mass >= 0.05, "%s: has a mass (%.2f)" % [key, c.mass])
		else:
			boxless += 1
			print("  (no skin for %s)" % key)
		c.queue_free()
	ok(baked >= 60, "%d species baked (boxless: %d)" % [baked, boxless])
	## mass sanity: the moose outweighs the hare by a lot
	var moose := Critter.make("moose")
	var hare := Critter.make("hare")
	_spawn(moose, Vector3(0, 0.05, 44))
	_spawn(hare, Vector3(4, 0.05, 44))
	await process_frame
	ok(moose.mass > 300.0 and moose.mass < 1200.0, "moose mass is moose-sized (%.0f)" % moose.mass)
	ok(hare.mass > 1.0 and hare.mass < 8.0, "hare mass is hare-sized (%.1f)" % hare.mass)
	ok(moose.skin.tile_world > hare.skin.tile_world, "texel density scales with the animal")
	moose.queue_free()
	hare.queue_free()
	## a box-less owner must not explode
	var bare := CharacterBody3D.new()
	_world.add_child(bare)
	var bs := CreatureSkin.bake(bare, {})
	ok(bs != null and bs.skeleton == null, "bake on a boxless body is a no-op")
	bare.queue_free()
	await process_frame


## ----------------------------------------------------------- winding -----

func _winding_report(s: CreatureSkin) -> Dictionary:
	return _winding_of(s.mesh_inst.mesh as ArrayMesh)


func _winding_of(am: ArrayMesh) -> Dictionary:
	## Every triangle in a baked skin must wind OUTWARD — the same way its own
	## vertex normals point. A segment wound the other way is invisible under
	## `cull_back`: you look straight through the body and see the inside of
	## its far wall. That is exactly what quadrupeds did (barrels, chests and
	## heads are X/Z-long boxes) while Y-long limbs looked fine, so this walks
	## the whole index buffer rather than spot-checking.
	##
	## ⚠ GODOT WINDS ITS FRONT FACES CLOCKWISE, not counter-clockwise. So for a
	## correctly-wound triangle (v1-v0) x (v2-v0) points AGAINST the vertex
	## normals, and the test for "outward" is dot < 0. The first draft of this
	## used the OpenGL convention and called every face of every creature
	## inside-out — and so, checked the same way, is every face of Godot's own
	## SphereMesh, BoxMesh and CylinderMesh. t_winding() now asserts a stock
	## BoxMesh through this very function before it asks about any skin, so the
	## sign can never be flipped again without the control going red first.
	var out := {"good": 0, "bad": 0, "skipped": 0}
	if am == null or am.get_surface_count() == 0:
		return out
	var arr := am.surface_get_arrays(0)
	var v := arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var n := arr[Mesh.ARRAY_NORMAL] as PackedVector3Array
	var idx := arr[Mesh.ARRAY_INDEX] as PackedInt32Array
	var t := 0
	while t + 2 < idx.size():
		var i0 := idx[t]
		var i1 := idx[t + 1]
		var i2 := idx[t + 2]
		t += 3
		var face := (v[i1] - v[i0]).cross(v[i2] - v[i0])
		if face.length() < 1e-9:
			out["skipped"] = int(out["skipped"]) + 1
			continue
		var want := (n[i0] + n[i1] + n[i2])
		if want.length() < 1e-6:
			out["skipped"] = int(out["skipped"]) + 1
			continue
		if face.normalized().dot(want.normalized()) < 0.0:
			out["good"] = int(out["good"]) + 1
		else:
			out["bad"] = int(out["bad"]) + 1
	return out


func t_winding() -> void:
	print("-- winding --")
	## CONTROL FIRST. Godot's own primitives are, by definition, wound the way
	## Godot wants. If this goes red the checker is wrong, not the art — which
	## is exactly the mistake this section shipped with.
	for prim: PrimitiveMesh in [BoxMesh.new(), SphereMesh.new(), CylinderMesh.new()]:
		var ctrl := ArrayMesh.new()
		ctrl.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, prim.get_mesh_arrays())
		var cr := _winding_of(ctrl)
		var cname := String(prim.get_class())
		ok(int(cr["good"]) > 0, "control: %s has triangles to check (%d)" % [cname, cr["good"]])
		eq(cr["bad"], 0, "control: Godot's own %s winds outward (%d inside-out)" % [cname, cr["bad"]])
	var mobs: Array = [Goblin.new(), Kobold.new(), Orc.new(), Ogre.new(), Skeleton.new(),
		DarkKnight.new(), Boar.new(), Horse.new(), SaddledHorse.new()]
	var x := 0.0
	for m in mobs:
		_spawn(m, Vector3(x, 0.05, -26))
		x += 4.0
	await process_frame
	for m in mobs:
		var e := m as Enemy
		var nm := String(e.get_script().get_global_name())
		if e.skin == null or e.skin.mesh_inst == null:
			ok(false, "%s: no skin to check winding on" % nm)
			continue
		var r := _winding_report(e.skin)
		ok(int(r["good"]) > 0, "%s: skin has triangles to check (%d)" % [nm, r["good"]])
		eq(r["bad"], 0, "%s: every face winds outward (%d inside-out)" % [nm, r["bad"]])
		e.queue_free()
	## and the wildlife, where the long-axis mix is widest (barrels, necks,
	## antlers, tails all pick different axes)
	for key in ["whitetail", "moose", "black_bear", "hare", "coyote", "porcupine"]:
		var c := Critter.make(key)
		_spawn(c, Vector3(0, 0.05, 52))
		await process_frame
		if c.skin == null or c.skin.mesh_inst == null:
			c.queue_free()
			continue
		var r2 := _winding_report(c.skin)
		ok(int(r2["good"]) > 0, "%s: skin has triangles to check (%d)" % [key, r2["good"]])
		eq(r2["bad"], 0, "%s: every face winds outward (%d inside-out)" % [key, r2["bad"]])
		c.queue_free()
	await process_frame


## -------------------------------------------------------------- sync ------

func t_sync() -> void:
	print("-- sync --")
	_player.global_position = Vector3(20, 0, -40)   ## awake, not aggro (goblin sees 7 m)
	var g := Goblin.new()
	_spawn(g, Vector3(0, 0.05, -40))
	g.wander_speed = 0.0
	await process_frame
	await process_frame
	var s := g.skin
	## pivots drive bones: rotate the club arm, the bone follows next frame
	var arm := g.get("arm") as Node3D
	var bid: int = s._bone_of[arm]
	ok(bid > 0, "the goblin's arm pivot is a bone")
	var before := s.skeleton.get_bone_pose_rotation(bid)
	arm.rotation.z = 1.1
	## Goblin._animate lerps the arm every physics frame; check right after the
	## process sync, before physics runs again
	s._sync_bones()
	var after := s.skeleton.get_bone_pose_rotation(bid)
	ok(before != after, "bone pose changed with the pivot")
	near(after.get_euler().z, 1.1, 0.05, "bone rotation matches the pivot")
	## and owner-space globals honour the chain: the arm bone's global pose
	## origin equals the pivot's owner-relative origin
	var g_pose := s.skeleton.get_bone_global_pose(bid)
	var rel := s._rel_to_owner(arm)
	ok(g_pose.origin.distance_to(rel.origin) < 0.001, "bone global origin == pivot owner-space origin")
	## visibility -> alpha 0 in the data texture
	var src0 := s.seg_src[0] as MeshInstance3D
	src0.visible = false
	s._sync_segments(false)
	eq(s.segment_alpha(0), 0.0, "hidden proxy box -> segment alpha 0")
	src0.visible = true
	s._sync_segments(false)
	eq(s.segment_alpha(0), 1.0, "shown again -> alpha 1")
	## opaque materials never dither: a hoof coloured `col * 0.75` has alpha
	## 0.75 on a material that ignores it, and so must the skin
	var m0 := src0.material_override as StandardMaterial3D
	var keep_a := m0.albedo_color
	m0.albedo_color = Color(0.3, 0.2, 0.1, 0.75)
	s._sync_segments(false)
	eq(s.segment_alpha(0), 1.0, "alpha on an opaque material is ignored")
	m0.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	s._sync_segments(false)
	near(s.segment_alpha(0), 0.75, 0.001, "alpha on a transparent material dithers")
	m0.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	m0.albedo_color = keep_a
	s._sync_segments(false)
	## albedo -> segment colour (this is the hit flash / coat swap path)
	var m := src0.material_override as StandardMaterial3D
	var keep := m.albedo_color
	m.albedo_color = Color(0.9, 0.6, 0.55)
	s._sync_segments(false)
	ok(s.segment_colour(0).is_equal_approx(Color(0.9, 0.6, 0.55)), "albedo change reaches the segment")
	m.albedo_color = keep
	## emission -> row 1
	m.emission_enabled = true
	m.emission = Color(1, 1, 1)
	m.emission_energy_multiplier = 5.0
	s._sync_segments(false)
	var em := s._seg_img.get_pixel(0, 1)
	near(em.r, 5.0, 0.01, "emission x energy reaches row 1")
	m.emission_enabled = false
	s._sync_segments(false)
	near(s._seg_img.get_pixel(0, 1).r, 0.0, 0.01, "emission off clears row 1")
	## hit flash on the real path: take_damage flashes body_mat, the skin follows
	g.take_damage(1.0, null, false, null, _player)
	await physics_frame
	await process_frame
	await process_frame
	var body_i := -1
	for i in s.seg_src.size():
		if (s.seg_src[i] as MeshInstance3D).material_override == g.body_mat:
			body_i = i
	ok(body_i >= 0, "found the body segment")
	if body_i >= 0:
		ok(s.segment_colour(body_i).r > 0.8, "hit flash reached the skin (r=%.2f)" % s.segment_colour(body_i).r)
	## metallic -> row 1 alpha
	var dk := DarkKnight.new()
	_spawn(dk, Vector3(4, 0.05, -40))
	await process_frame
	var metal_segs := 0
	for i in dk.skin.segment_count():
		if dk.skin._seg_img.get_pixel(i, 1).a > 0.3:
			metal_segs += 1
	ok(metal_segs > 0, "dark knight has metal segments (%d)" % metal_segs)
	var metal_tiles := 0
	var arr := (dk.skin.mesh_inst.mesh as ArrayMesh).surface_get_arrays(0)
	for v in (arr[Mesh.ARRAY_TEX_UV2] as PackedVector2Array):
		if int(v.y) == PsxTex.tile_index("metal"):
			metal_tiles += 1
	ok(metal_tiles > 0, "metal boxes got the metal tile")
	dk.queue_free()
	## eyes are flat-tile tiny boxes and land in eye_mats -> emission path works
	var c := Critter.make("coyote")
	_spawn(c, Vector3(8, 0.05, -40))
	await process_frame
	c.set_clock(23.0, 0.5)   ## night: eyeshine
	c._season_tick(0.1)
	c.skin._sync_segments(false)
	var shine := 0
	for i in c.skin.segment_count():
		if c.skin._seg_img.get_pixel(i, 1).g > 0.1:
			shine += 1
	ok(shine >= 2, "coyote eyeshine reaches the skin at night (%d glowing segments)" % shine)
	c.queue_free()
	g.queue_free()
	_player.global_position = Vector3(60, 0, 60)
	await process_frame


## ----------------------------------------------------------- ragdoll ------

func _spread(s: CreatureSkin) -> float:
	var pel := s.pelvis_global().origin
	var m := 0.0
	for pb in s._phys_bones:
		m = maxf(m, (pb as PhysicalBone3D).global_position.distance_to(pel))
	return m


func t_ragdoll() -> void:
	print("-- ragdoll --")
	## knockdown + get up
	var g := Goblin.new()
	_spawn(g, Vector3(0, 0.05, 0))
	g.wander_speed = 0.0
	await _step(3)
	## THE REFERENCE IS MEASURED THE WAY THE ASSERTION MEASURES IT. The first
	## version banked the pelvis's ABSOLUTE y and later compared it against a
	## height RELATIVE to the root, minus the spawn height as a fudge — two
	## different quantities that only agreed because the tolerance was ±0.25.
	## That is what made it a coin flip: the true miss was 0.17-0.32 m and the
	## slack hid it half the time. Both ends are the same offset now and the
	## margin is a tenth of what the bug moved.
	var rest_off := g.skin.pelvis_global().origin.y - g.global_position.y
	g.knockdown(Vector3(5.0, 1.2, 0.0), 1.0)
	ok(g.knocked, "goblin is knocked")
	ok(g.skin.ragdoll, "skin is ragdolling")
	ok(g.skin._phys_bones.size() == g.skin.bone_count() - 1, "one physical bone per bone (%d)" % g.skin._phys_bones.size())
	var col_off := true
	await process_frame
	for ch in g.get_children():
		if ch is CollisionShape3D and not (ch as CollisionShape3D).disabled:
			col_off = false
	ok(col_off, "capsule disabled while down")
	await _step(40)
	ok(_spread(g.skin) < 1.4, "goblin holds together while down (spread %.2f)" % _spread(g.skin))
	var waited := 0
	while g.knocked and waited < 240:
		await physics_frame
		waited += 1
	ok(not g.knocked, "goblin got back up after its clock (%d frames)" % waited)
	ok(not g.skin.ragdoll, "skin stopped simulating")
	ok(g.skin._blend_t > 0.0, "get-up blend engaged")
	var col_on := true
	await process_frame
	for ch in g.get_children():
		if ch is CollisionShape3D and (ch as CollisionShape3D).disabled:
			col_on = false
	ok(col_on, "capsule re-enabled on its feet")
	ok(g.global_position.distance_to(Vector3(0, 0, 0)) > 0.15, "it stood up where it landed, not where it fell from (moved %.2f)" % g.global_position.distance_to(Vector3.ZERO))
	near(g.rotation.x, 0.0, 0.001, "root is upright after the get-up")
	near(g.rotation.z, 0.0, 0.001, "root is level after the get-up")
	waited = 0
	while g.skin._blend_t > 0.0 and waited < 240:
		await physics_frame
		waited += 1
	ok(g.skin._blend_t <= 0.0, "blend finished (%d frames)" % waited)
	await _step(5)
	near(g.skin.pelvis_global().origin.y - g.global_position.y, rest_off, 0.03, "pelvis back at rest height over the root")
	## a second knockdown while already down is ignored
	g.knockdown(Vector3(1, 0, 0), 0.5)
	await _step(2)
	g.knockdown(Vector3(1, 0, 0), 0.5)
	ok(g.knocked and g.skin.ragdoll, "double knockdown is idempotent")
	await _step(80)
	g.queue_free()

	## death: corpses fall over and stay
	for key in ["whitetail", "black_bear", "moose", "hare", "porcupine"]:
		var c := Critter.make(key)
		_spawn(c, Vector3(0, 0.05, 10))
		await _step(3)
		var stand_y := c.skin.pelvis_global().origin.y
		c.take_damage(99999.0, null, false, null, _player)
		ok(c.dying, "%s is dying" % key)
		ok(c.skin.ragdoll and c.skin.permanent, "%s: death is a permanent ragdoll" % key)
		await _step(75)
		var y := c.skin.pelvis_global().origin.y
		ok(y < stand_y * 0.72, "%s fell over (pelvis %.2f -> %.2f)" % [key, stand_y, y])
		ok(_spread(c.skin) < c.skin.tile_world * 6.0, "%s corpse is in one piece (spread %.2f)" % [key, _spread(c.skin)])
		ok(is_instance_valid(c) and not c.is_queued_for_deletion(), "%s corpse persists" % key)
		c.queue_free()
		await process_frame
	## the death clock: settle -> freeze -> (linger) -> fade -> free
	var o := Goblin.new()
	_spawn(o, Vector3(0, 0.05, 14))
	await _step(2)
	o.take_damage(99999.0, null, false, null, _player)
	await _step(int(CreatureSkin.CORPSE_SETTLE * 60.0) + 10)
	ok(o.skin.frozen and not o.skin.ragdoll, "corpse froze after settling")
	var frozen_pose := o.skin.skeleton.get_bone_pose_position(1)
	await _step(30)
	ok(o.skin.skeleton.get_bone_pose_position(1) == frozen_pose, "frozen corpse keeps its pose (no pivot sync)")
	o.queue_free()
	## killed while knocked down: stays down as a corpse
	var k := Kobold.new()
	_spawn(k, Vector3(0, 0.05, 18))
	await _step(2)
	k.knockdown(Vector3(2, 0.5, 0), 3.0)
	await _step(10)
	k.take_damage(99999.0, null, false, null, _player)
	ok(k.dying and k.skin.ragdoll and k.skin.permanent, "killed while down -> permanent ragdoll, no get-up")
	k.queue_free()
	## owner_of maps a bone back to its creature
	var b := Boar.new()
	_spawn(b, Vector3(0, 0.05, 22))
	await _step(2)
	b.knockdown(Vector3(1, 0, 0), 1.0)
	var pb := b.skin._phys_bones[0] as PhysicalBone3D
	eq(CreatureSkin.owner_of(pb), b, "owner_of(bone) is the boar")
	eq(CreatureSkin.owner_of(b), b, "owner_of(creature) is itself")
	eq(CreatureSkin.owner_of(null), null, "owner_of(null) is null")
	eq(pb.collision_layer, 1 << (CreatureSkin.RAGDOLL_LAYER - 1), "bones live on the ragdoll layer")
	ok((pb.collision_mask & 2) == 0, "bones ignore creature capsules (trample passes through)")
	ok((pb.collision_mask & 1) != 0, "bones collide with the world")
	## masses are clamped so no bone is under 3% or over 60% of the body
	var mass_ok := true
	for p2 in b.skin._phys_bones:
		var pm := (p2 as PhysicalBone3D).mass
		if pm < b.mass * 0.03 - 0.001 or pm > b.mass * 0.6 + 0.001:
			mass_ok = false
	ok(mass_ok, "bone masses are clamped to 3%..60% of the body")
	## joint axes: every jointed bone's cone axis points down its geometry
	var axes_ok := true
	for p3 in b.skin._phys_bones:
		var pb3 := p3 as PhysicalBone3D
		if pb3.joint_type == PhysicalBone3D.JOINT_TYPE_CONE:
			var bid: int = b.skin.skeleton.find_bone(pb3.bone_name)
			var box: AABB = b.skin._bone_geo[bid]
			var along := (box.position + box.size * 0.5)
			if along.length() > 0.01:
				var ax := pb3.joint_offset.basis.x
				if ax.dot(along.normalized()) < 0.98:
					axes_ok = false
	ok(axes_ok, "cone joint axes run along the limbs")
	await _step(80)
	b.queue_free()
	await process_frame


## ------------------------------------------------------------- shove ------

func t_shove() -> void:
	print("-- shove --")
	## a galloping horse through a goblin
	var h := Horse.new()
	_spawn(h, Vector3(-6, 0.05, 30))
	var g := Goblin.new()
	_spawn(g, Vector3(0, 0.05, 30))
	await _step(2)
	h.dying = true   ## AI off; we drive the velocity
	var knocked_at := -1.0
	for i in 120:
		h.velocity = Vector3(9.0, 0.0, 0.0)
		await physics_frame
		if g.knocked and knocked_at < 0.0:
			knocked_at = i / 60.0
	ok(knocked_at >= 0.0, "a galloping horse knocks a goblin flat (t=%.2f)" % knocked_at)
	ok(h.global_position.x > 5.0, "the horse ran on through (x=%.1f)" % h.global_position.x)
	ok(g.skin.pelvis_global().origin.distance_to(Vector3(0, 0, 30)) < 8.0, "goblin landed nearby, not carried off (%.1f m)" % g.skin.pelvis_global().origin.distance_to(Vector3(0, 0, 30)))
	h.queue_free()
	g.queue_free()
	## a goblin walking into an ogre moves it a little and never knocks it
	var o := Ogre.new()
	_spawn(o, Vector3(0, 0.05, 36))
	var g2 := Goblin.new()
	_spawn(g2, Vector3(-1.2, 0.05, 36))
	await _step(2)
	o.dying = true
	g2.dying = true
	var pushed := 0.0
	for i in 60:
		g2.velocity = Vector3(3.0, 0.0, 0.0)
		await physics_frame
		pushed = maxf(pushed, o.velocity.x)
	ok(not o.knocked, "a goblin cannot knock an ogre down")
	ok(pushed > 0.0 and pushed < 1.0, "the ogre is nudged, not launched (%.2f m/s)" % pushed)
	## and the goblin bounces back some
	ok(g2.velocity.x < 3.0, "the goblin loses speed pushing (%.2f)" % g2.velocity.x)
	o.queue_free()
	g2.queue_free()
	## equals: two goblins shove each other, neither falls
	var a := Goblin.new()
	var b := Goblin.new()
	_spawn(a, Vector3(-1.5, 0.05, 42))
	_spawn(b, Vector3(0, 0.05, 42))
	await _step(2)
	a.dying = true
	b.dying = true
	for i in 40:
		a.velocity = Vector3(5.0, 0.0, 0.0)
		await physics_frame
	ok(not b.knocked and not a.knocked, "equal masses shove without a knockdown")
	ok(b.global_position.x > 0.05, "the shoved goblin moved (x=%.2f)" % b.global_position.x)
	a.queue_free()
	b.queue_free()
	## the player takes a trample too (LabPlayer has no knockdown; a real
	## Player.knockdown exists — assert the shove path only asks for it)
	ok(_player.has_method("knockdown") == false, "LabPlayer has no knockdown, so the shove skips it cleanly")
	var m := Critter.make("moose")
	_spawn(m, Vector3(-5, 0.05, 48))
	_player.global_position = Vector3(0, 0.05, 48)
	await _step(2)
	m.dying = true
	for i in 60:
		m.velocity = Vector3(8.0, 0.0, 0.0)
		await physics_frame
	ok(_player.velocity.length() > 0.5 or _player.global_position.x > 0.2, "the moose shoves the player (x=%.2f)" % _player.global_position.x)
	m.queue_free()
	_player.global_position = Vector3(60, 0, 60)
	_player.velocity = Vector3.ZERO
	await process_frame


## -------------------------------------------------------------- flow ------

func t_flow() -> void:
	print("-- flow --")
	_player.global_position = Vector3(25, 0, -60)   ## awake, not aggro
	var g := Goblin.new()
	_spawn(g, Vector3(0, 0.05, -60))
	g.wander_speed = 0.0
	await _step(2)
	var rig := g.get("rig") as Node3D
	var kinds := {}
	var maxrot := 0.0
	## ⚠ WATCH LONG ENOUGH THAT LUCK CANNOT DECIDE IT. A fidget is a cooldown
	## of randf_range(1.4, 4.5) plus a body of 0.9-2.8 s, so 900 frames is
	## two or three draws — and the picker's bag is
	## ["shift","shift","look","look","stomp","arms","roll"], where two draws
	## land on the same kind about one time in five. That is exactly the rate
	## this assertion was failing at. 3600 frames is nine to thirteen draws and
	## the all-one-kind case is under a thousandth.
	for i in 3600:
		await physics_frame
		if g._fid_kind != "":
			kinds[g._fid_kind] = true
		maxrot = maxf(maxrot, rig.rotation_degrees.length())
	ok(kinds.size() >= 2, "a standing goblin fidgets in more than one way (%s)" % [kinds.keys()])
	ok(maxrot < 30.0, "fidgets stay small (max %.1f deg)" % maxrot)
	ok(g._flow_applied.size() > 0, "offsets are live after the skin tick")
	g._flow_unapply()
	eq(g._flow_applied.size(), 0, "unapply clears the ledger")
	near(rig.rotation_degrees.length(), 0.0, 0.5, "rig is back on the authored pose once offsets are stripped")
	## acting cancels fidgets
	g.melee_anim = 0.3
	g._fid_kind = "look"
	g._flow_ready = true
	g._update_flow(0.016)
	eq(g._fid_kind, "", "a swing cancels the fidget")
	g.melee_anim = 0.0
	## lean: a sudden acceleration pitches the body forward (negative x)
	g._flow_unapply()
	g._prev_vel = Vector3.ZERO
	g.velocity = -g.global_transform.basis.z * 6.0
	g._loco_amount = 1.0
	for i in 12:
		g._flow_unapply()
		g._flow_ready = true
		g._update_flow(0.016)
		g._prev_vel = Vector3.ZERO   ## keep "accelerating"
	ok(g._lean.x < -2.0, "acceleration leans the body forward (%.1f deg)" % g._lean.x)
	g._flow_unapply()
	## wildlife: lean only, no mob fidgets
	var c := Critter.make("whitetail")
	_spawn(c, Vector3(4, 0.05, -60))
	await _step(30)
	eq(c._fid_kind, "", "wildlife leaves the mob fidgets to CritterAnim's buzz")
	## a sleeping / knocked creature leaves nothing behind
	g.knockdown(Vector3(1, 0, 0), 0.5)
	await _step(3)
	eq(g._flow_applied.size(), 0, "no offsets while down")
	await _step(60)
	g.queue_free()
	c.queue_free()
	_player.global_position = Vector3(60, 0, 60)
	await process_frame


## ------------------------------------------------------------ layers ------

func t_layers() -> void:
	print("-- layers --")
	var g := Goblin.new()
	_spawn(g, Vector3(0, 0.05, -70))
	await process_frame
	eq(g.collision_layer, 2, "creatures live on layer 2")
	eq(g.collision_mask, 3, "creatures collide with the world and each other")
	var c := Critter.make("hare")
	_spawn(c, Vector3(2, 0.05, -70))
	await process_frame
	eq(c.collision_layer, 2, "wildlife too")
	## LOS through a bone maps to the creature
	g.knockdown(Vector3(1, 0, 0), 1.0)
	await _step(5)
	var space := g.get_world_3d().direct_space_state
	var pel := g.skin.pelvis_global().origin
	var q := PhysicsRayQueryParameters3D.create(pel + Vector3(0, 3, 0), pel + Vector3(0, -1, 0))
	var hit: Dictionary = space.intersect_ray(q)
	ok(not hit.is_empty(), "a ray from above hits the downed goblin")
	if not hit.is_empty():
		ok(hit.collider is PhysicalBone3D, "…on a physical bone")
		eq(CreatureSkin.owner_of(hit.collider), g, "…that maps back to the goblin")
	## and _can_see through it treats the bone as its owner
	ok(c._can_see(g), "the hare can see the downed goblin (bone hit == target)")
	await _step(70)
	g.queue_free()
	c.queue_free()
	await process_frame
