class_name CarcassBody
extends Node3D

## ===========================================================================
## THE BODY OF A CARCASS — the animal's own skin, lying the way it died.
##
## `Carcasses` keeps the ledger; this is the picture of one row of it, and
## until 2026-09-14 the picture was four flat boxes and some spars — "some
## cube that's stuck", in Lemon's words on finding the butchery loop. So:
##
##   * the body is the species' OWN rig — `CritterRig.build` for the same
##     key the live animal was built from — baked through `CreatureSkin` into
##     the same rounded PSX skin every living creature in Myrkfell wears;
##   * it lies in the pose the DEATH left it in. When a wild animal dies its
##     ragdoll settles for five seconds and freezes; the bus reads the
##     skeleton at that moment and writes every bone's pose into the record
##     (`Carcasses._capture_pending`), and this body puts those bones back
##     exactly where they were. The corpse the creature left behind is hidden
##     in the same frame, so what you are looking at never changes — it just
##     stops being the animal's and starts being the ledger's. A record that
##     never had a ragdoll (an old save, a test, the console) gets a fallback
##     pose: rolled onto its side with the knees folded, on a hash of its id;
##   * the STAGES are the skin's own material-and-visibility mirror. The
##     proxy boxes the bake leaves behind are still the source of truth for
##     colour and `visible`, so an opened belly is a recoloured box and a
##     picked carcass is a hidden trunk over a smaller dark core and a set of
##     pale rib plates that were baked in from the start and kept invisible
##     until their stage. Nothing is rebuilt between stages;
##   * and at BONES the skin is hidden and what is left can be PICKED UP:
##     one `DroppedItem` per real bone — the skull, the ribs, two per leg —
##     laid at the bone's own settled position, in the ordinary loot group,
##     so the gaze, the reach-and-grab and the pack all take them without
##     knowing what a carcass is. Which ones are gone is written on the
##     record (`bones`), and `Carcasses._drive_bodies` is what notices one
##     leave.
##
## The stained slab under it stays, at every stage, for the reason it was
## first added: the bare ground is the longest-lived part of a carcass.
##
## No randomness anywhere in here: every choice is a hash of the record id,
## so two players with the same seed see the same body, and a reload shows
## you the one you left.
## ===========================================================================

const POSE_STRIDE := 12          ## floats per bone in a stored pose (basis + origin)
const FALL_ROLL := 1.42          ## fallback pose: radians onto its side
const FALL_KNEE := 0.62          ## ...with the knees folded
const FALL_HIP := 0.26           ## ...the hips splayed fore and aft
const FALL_NECK := 0.30          ## ...and the head down
const MIN_BONE_M := 0.10         ## a bone shorter than this is not worth stooping for
const SLAB_LIFT := 0.02

const BONE_COL := Color(0.88, 0.85, 0.76)
const MEAT := Color(0.44, 0.14, 0.13)
const MEAT_DARK := Color(0.30, 0.09, 0.08)
const EYE_DEAD := Color(0.30, 0.28, 0.26)
const SOIL_FRESH := Color(0.17, 0.12, 0.09)
const SOIL_OLD := Color(0.24, 0.20, 0.15)

## Kilograms of a bone item, by kind: a flat term plus one per metre of it.
const BONE_KG := {"long": [0.10, 0.70], "skull": [0.15, 1.60], "ribs": [0.20, 2.60]}

var rec_id := 0
var species := ""
var ground_fn := Callable()      ## world position -> terrain height, from the bus; empty in a bare test
var animal := "Beast"            ## the last word of the dex name, capitalised: "Bear"
var length := 1.0
var stage := -1
var world_seed := 0
var pose_from_death := false     ## true when the record carried a ragdoll pose we could wear
var skin: CreatureSkin = null
var rig: Dictionary = {}
var bones: Dictionary = {}       ## bone key -> DroppedItem lying here right now

var _trunk: MeshInstance3D = null
var _belly: Array = []           ## boxes under the body pivot, below its centre line
var _body_rest: Array = []       ## the rest of the body pivot's boxes (hump, chest, ...)
var _core: MeshInstance3D = null ## baked in, hidden until PICKED
var _ribs: Array = []            ## baked in, hidden until PICKED
var _neck: Array = []
var _upper: Array = []           ## upper-leg boxes
var _lower: Array = []           ## lower-leg boxes, paws and claws included
var _soft: Array = []            ## ears, tail, crest, fan, quills, wings: the first things gone
var _eyes: Array = []            ## the eye materials
var _live: Dictionary = {}       ## StandardMaterial3D -> its live colour
var _slab: MeshInstance3D = null
var _size: Dictionary = {}       ## MeshInstance3D -> its BoxMesh size, read BEFORE the bake empties it
var _bone_specs: Array = []      ## [{key, kind, bid, box}] in a stable order


## ================================================================ build ====

func _ready() -> void:
	## The bake ran OFF the tree, where every proxy reads as invisible and
	## the skin's data texture was filled with alpha 0. Push the real
	## colours the frame we arrive, not the frame after: this body replaces
	## a hidden corpse in the same sweep, and one blank frame is a flicker.
	if skin != null and skin.has_method("_sync_segments"):
		skin._sync_segments(true)


static func build(rec: Dictionary, seed_v: int, ground_y: float, ground := Callable()) -> CarcassBody:
	## The only way one is made. `ground_y` is the terrain under `rec.at`;
	## the root sits there UNROTATED, always — the yaw lives in the pose, so
	## a stored pose and a rebuilt body agree without a frame conversion.
	## `ground` answers the terrain height anywhere, for the bones: a body
	## two metres long on a hillside has an end under the turf, and a bone
	## laid under the turf falls out of the world.
	var b := CarcassBody.new()
	b.rec_id = int(rec.get("id", 0))
	b.species = String(rec.get("species", ""))
	b.world_seed = seed_v
	b.ground_fn = ground
	b.name = "Carcass%d" % b.rec_id
	var at: Vector3 = rec.get("at", Vector3.ZERO)
	b.position = Vector3(at.x, ground_y, at.z)
	b.add_to_group("carcass_bodies")
	b._assemble(rec)
	b.dress(rec)
	return b


static func animal_word(nm: String) -> String:
	## "black bear" -> "Bear", "white-tailed deer" -> "Deer": the last word,
	## the same rule `Butchery.meat_name` uses, so a bone and a steak off the
	## same animal are named the same way.
	var words := nm.strip_edges().split(" ", false)
	if words.is_empty():
		return "Beast"
	return String(words[words.size() - 1]).capitalize()


static func skin_tile(key: String, prof: Dictionary) -> String:
	## The same tile choice `Critter._skin_opts` makes, so the carcass wears
	## the coat the live animal wore. Kept in step by hand; the live one is
	## an instance method on a CharacterBody3D and this body is neither.
	var fam := String(prof.get("rig", "CHUNK"))
	var tile := "fur"
	match fam:
		"BIRD_GROUND", "BIRD_RAPTOR", "BIRD_PERCH", "BIRD_WATER": tile = "feather"
		"HERP", "FISH": tile = "scale"
		"URSID": tile = "fur_long"
		"CERVID": tile = "hide"
		"SWARM": tile = "chitin"
	if CritterDex.feat(key, "stripes", false) or CritterDex.feat(key, "stripe", false) \
			or CritterDex.feat(key, "barring", false):
		tile = "fur_striped"
	elif CritterDex.feat(key, "spots", false):
		tile = "fur_spotted"
	elif CritterDex.feat(key, "shaggy", false):
		tile = "fur_long"
	elif CritterDex.feat(key, "shell", false):
		tile = "scale"
	return tile


static func bone_item_name(kind: String, animal_nm: String) -> String:
	match kind:
		"skull": return "%s Skull" % animal_nm
		"ribs": return "%s Ribs" % animal_nm
		_: return "%s Bone" % animal_nm


static func bone_weight(kind: String, size_m: float) -> float:
	var row: Array = BONE_KG.get(kind, BONE_KG["long"])
	return snappedf(float(row[0]) + float(row[1]) * size_m, 0.05)


func _assemble(rec: Dictionary) -> void:
	var prof: Dictionary = CritterDex.get_profile(species)
	if prof.is_empty():
		prof = CritterDex.get_profile("hare")
	length = float(prof.get("len", 1.0))
	animal = animal_word(String(rec.get("nm", species)))
	rig = CritterRig.build(self, species)
	_sort_parts()
	_bake_stage_boxes()
	skin = CreatureSkin.bake(self, {
		"tile": skin_tile(species, prof),
		"mass": maxf(float(rec.get("mass", 10.0)), 1.0),
	})
	if skin == null or skin.bone_count() <= 1:
		## The skin is a debug switch away from not existing. Boxes it is,
		## then — at least on their side.
		var root := rig.get("root") as Node3D
		if root != null:
			root.rotation.z = FALL_ROLL
			root.position.y = length * 0.22
		_slab = _make_slab(0.0)
		return
	_lay(rec)
	_plan_bones()
	_slab = _make_slab(_body_yaw())


func _boxes_under(n: Variant) -> Array:
	## The boxes a pivot wears directly (child pivots are their own bones).
	var out: Array = []
	if not (n is Node):
		return out
	for c in (n as Node).get_children():
		if c is MeshInstance3D:
			out.append(c)
	return out


func _boxes_deep(n: Variant, out: Array) -> void:
	if not (n is Node):
		return
	for c in (n as Node).get_children():
		if c is MeshInstance3D:
			out.append(c)
		else:
			_boxes_deep(c, out)


func _sort_parts() -> void:
	## Address the rig by its CONTRACT (the keys `CritterRig.build` promises)
	## and never by walking the mesh tree — the same rule CritterAnim keeps.
	## The one walk is for SIZES: the bake sets every proxy's mesh to null,
	## and a bone is sized and aimed from the box its flesh was.
	var every: Array = []
	_boxes_deep(rig.get("root"), every)
	for b in every:
		var bx := b as MeshInstance3D
		if bx != null and bx.mesh is BoxMesh:
			_size[bx] = (bx.mesh as BoxMesh).size
	var body := rig.get("body") as Node3D
	var body_mat := rig.get("body_mat") as StandardMaterial3D
	if body != null:
		for c in body.get_children():
			var mi := c as MeshInstance3D
			if mi == null:
				continue
			if _trunk == null and body_mat != null and mi.material_override == body_mat:
				_trunk = mi
			elif mi.position.y < -0.001:
				_belly.append(mi)
			else:
				_body_rest.append(mi)
	_neck = _boxes_under(rig.get("neck"))
	for hp in (rig.get("legs", []) as Array):
		_upper.append_array(_boxes_under(hp))
	for kn in (rig.get("knees", []) as Array):
		_lower.append_array(_boxes_under(kn))
	for key in ["tail", "tail2", "crest", "quills", "fan"]:
		_soft.append_array(_boxes_under(rig.get(key)))
	for e in (rig.get("ears", []) as Array):
		_soft.append_array(_boxes_under(e))
	for w in (rig.get("wings", []) as Array):
		_boxes_deep(w, _soft)
	for m in (rig.get("eye_mats", []) as Array):
		_eyes.append(m)
	for m2 in (rig.get("mats", []) as Array):
		var sm := m2 as StandardMaterial3D
		if sm != null:
			_live[sm] = sm.albedo_color


func _bake_stage_boxes() -> void:
	## What PICKED shows has to be in the skin from the start: the bake
	## walks the boxes once, and a box added later is a plain crate again.
	## So the core and the rib plates go in now, hidden, and get their stage.
	if _trunk == null or not (_trunk.mesh is BoxMesh):
		return
	var body := _trunk.get_parent()
	var sz := (_trunk.mesh as BoxMesh).size
	## the long axis of the trunk is the animal's length
	var long_axis := 2
	if sz.x > sz.y and sz.x > sz.z:
		long_axis = 0
	elif sz.y > sz.x and sz.y > sz.z:
		long_axis = 1
	var core_sz := sz * 0.62
	core_sz[long_axis] = sz[long_axis] * 0.88
	_core = CritterRig.box(body, core_sz, MEAT_DARK, _trunk.position)
	_core.visible = false
	var n_ribs := clampi(int(round(sz[long_axis] / 0.24)), 3, 7)
	for i in n_ribs:
		var t := (float(i) + 0.5) / float(n_ribs) - 0.5
		var psz := sz * 0.96
		psz[long_axis] = maxf(sz[long_axis] * 0.05, 0.03)
		var pos := _trunk.position
		pos[long_axis] += t * sz[long_axis] * 0.84
		var plate := CritterRig.box(body, psz, BONE_COL, pos)
		plate.visible = false
		_ribs.append(plate)


## ================================================================= pose ====

static func pose_of(sk: CreatureSkin, origin: Vector3) -> PackedFloat32Array:
	## Every bone's WORLD pose, written relative to `origin` (translation
	## only, no rotation) so the body that wears it later only has to sit its
	## unrotated root on that point. Bone 0 is the synthetic root: identity.
	var out := PackedFloat32Array()
	if sk == null or sk.skeleton == null:
		return out
	var n := sk.bone_count()
	out.resize(n * POSE_STRIDE)
	for i in n:
		var t := sk.bone_global(i) if i > 0 else Transform3D.IDENTITY
		if i > 0:
			t.origin -= origin
		var k := i * POSE_STRIDE
		out[k + 0] = t.basis.x.x; out[k + 1] = t.basis.x.y; out[k + 2] = t.basis.x.z
		out[k + 3] = t.basis.y.x; out[k + 4] = t.basis.y.y; out[k + 5] = t.basis.y.z
		out[k + 6] = t.basis.z.x; out[k + 7] = t.basis.z.y; out[k + 8] = t.basis.z.z
		out[k + 9] = t.origin.x; out[k + 10] = t.origin.y; out[k + 11] = t.origin.z
	return out


static func pose_unpack(p: PackedFloat32Array) -> Array:
	var out: Array = []
	@warning_ignore("integer_division")
	var n := int(p.size() / POSE_STRIDE)
	for i in n:
		var k := i * POSE_STRIDE
		var b := Basis(Vector3(p[k], p[k + 1], p[k + 2]), Vector3(p[k + 3], p[k + 4], p[k + 5]),
				Vector3(p[k + 6], p[k + 7], p[k + 8]))
		out.append(Transform3D(b, Vector3(p[k + 9], p[k + 10], p[k + 11])))
	return out


func _lay(rec: Dictionary) -> void:
	## Wear the record's pose, or the fallback when it has none we can wear.
	var stored: Variant = rec.get("pose", null)
	if stored is PackedFloat32Array and (stored as PackedFloat32Array).size() == skin.bone_count() * POSE_STRIDE:
		var globals := pose_unpack(stored as PackedFloat32Array)
		skin.pose_apply(globals)
		pose_from_death = true
		return
	skin.pose_apply(_fallback_pose())
	pose_from_death = false


func _fallback_pose() -> Array:
	## On its side, knees folded, head down: what a dead animal looks like
	## when nobody watched it fall. Owner-space, parents before children, the
	## way `_plan_bones` orders them.
	var n := skin.bone_count()
	var h := Carcasses._hash(world_seed ^ rec_id, 0, Carcasses.SALT_BODY)
	var yaw := Carcasses._unit(h, 7) * TAU
	var side := 1.0 if Carcasses._unit(h, 3) < 0.5 else -1.0
	var frame := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, FALL_ROLL * side)
	var extra: Dictionary = {}     ## bone id -> local rotation on top of rest
	var knees: Array = rig.get("knees", [])
	for i in knees.size():
		var bid := skin.bone_of(knees[i] as Node)
		if bid > 0:
			extra[bid] = Basis(Vector3.RIGHT, FALL_KNEE)
	var legs: Array = rig.get("legs", [])
	for i in legs.size():
		var bid2 := skin.bone_of(legs[i] as Node)
		if bid2 > 0:
			extra[bid2] = Basis(Vector3.RIGHT, FALL_HIP * (1.0 if i < 2 else -1.0))
	var neck := skin.bone_of(rig.get("neck") as Node) if rig.get("neck") is Node else 0
	if neck > 0:
		extra[neck] = Basis(Vector3.RIGHT, FALL_NECK)
	var g: Array = []
	g.resize(n)
	g[0] = Transform3D.IDENTITY
	var pelvis := 1
	g[pelvis] = Transform3D(frame, Vector3.ZERO) * skin.rest_global(pelvis)
	for bid in range(2, n):
		var pid := skin.parent_of(bid)
		if pid <= 0:
			pid = pelvis
		var local := skin.rest_global(pid).affine_inverse() * skin.rest_global(bid)
		var t: Transform3D = (g[pid] as Transform3D) * local
		if extra.has(bid):
			t.basis = t.basis * (extra[bid] as Basis)
		g[bid] = t
	## and put the lowest thing on it on the ground
	var low := INF
	for bid2 in range(1, n):
		var box := skin.bone_aabb(bid2)
		if box.size == Vector3.ZERO and box.position == Vector3.ZERO:
			continue
		var t2: Transform3D = g[bid2]
		for c in 8:
			var corner := box.position + Vector3(
					box.size.x if (c & 1) != 0 else 0.0,
					box.size.y if (c & 2) != 0 else 0.0,
					box.size.z if (c & 4) != 0 else 0.0)
			low = minf(low, (t2 * corner).y)
	if low != INF:
		for bid3 in range(1, n):
			var t3: Transform3D = g[bid3]
			t3.origin.y -= low - 0.01
			g[bid3] = t3
	return g


func _body_yaw() -> float:
	## Which way the trunk lies, for the slab. Bodies face -Z in rest.
	if skin == null or skin.bone_count() <= 1:
		return 0.0
	var fwd := -skin.bone_pose(1).basis.z
	fwd.y = 0.0
	if fwd.length() < 0.05:
		fwd = -skin.bone_pose(1).basis.y
		fwd.y = 0.0
	if fwd.length() < 0.05:
		return 0.0
	fwd = fwd.normalized()
	return atan2(-fwd.x, -fwd.z)


## ================================================================ stages ===

func dress(rec: Dictionary) -> void:
	## The stage is the whole of what changes, and it is read off the
	## record every time — this body holds no opinion about how far down it
	## is. Cheap enough to call on every stage boundary and nowhere else.
	var st := Carcasses.stage_of(rec)
	stage = st
	set_meta("stage", st)
	if _slab != null:
		var soil := SOIL_FRESH if st < Carcasses.STAGE_PICKED else SOIL_OLD
		(_slab.material_override as StandardMaterial3D).albedo_color = soil
	if skin == null or skin.bone_count() <= 1:
		return
	match st:
		Carcasses.STAGE_WHOLE:
			_show_all(true)
			_paint(_live.keys(), 0.0, MEAT)
			_tint(_eyes, EYE_DEAD)
		Carcasses.STAGE_OPENED:
			_show_all(true)
			_paint(_live.keys(), 0.0, MEAT)
			_paint([_trunk], 0.32, MEAT)
			_paint(_mats_of(_belly), 0.85, MEAT)
			_tint(_eyes, EYE_DEAD)
		Carcasses.STAGE_PICKED:
			skin.visible = true
			_paint(_live.keys(), 0.0, MEAT)
			_paint(_mats_of(_upper), 0.60, MEAT)
			_paint(_mats_of(_neck), 0.70, MEAT_DARK)
			_tint(_eyes, EYE_DEAD)
			_vis([_trunk], false)
			_vis(_belly, false)
			_vis(_body_rest, false)
			_vis(_lower, false)
			_vis(_soft, false)
			_vis([_core], true)
			_vis(_ribs, true)
		_:
			skin.visible = false
	if st >= Carcasses.STAGE_BONES:
		_lay_bones(rec)
	else:
		for k in bones.keys():
			var n: Variant = bones[k]
			if n is Node and is_instance_valid(n as Node):
				(n as Node).queue_free()
		bones.clear()


func _show_all(on: bool) -> void:
	skin.visible = on
	_vis([_trunk], true)
	_vis(_belly, true)
	_vis(_body_rest, true)
	_vis(_neck, true)
	_vis(_upper, true)
	_vis(_lower, true)
	_vis(_soft, true)
	_vis([_core], false)
	_vis(_ribs, false)


func _vis(boxes: Array, on: bool) -> void:
	for b in boxes:
		var mi := b as MeshInstance3D
		if mi != null and is_instance_valid(mi):
			mi.visible = on


func _mats_of(boxes: Array) -> Array:
	var out: Array = []
	for b in boxes:
		var mi := b as MeshInstance3D
		if mi != null and is_instance_valid(mi) and mi.material_override is StandardMaterial3D:
			out.append(mi.material_override)
	return out


func _paint(mats: Array, k: float, toward: Color) -> void:
	## Live colour blended `k` of the way toward `toward`. k = 0 restores.
	for m in mats:
		var sm: StandardMaterial3D = null
		if m is MeshInstance3D:
			sm = (m as MeshInstance3D).material_override as StandardMaterial3D
		elif m is StandardMaterial3D:
			sm = m
		if sm == null or not _live.has(sm):
			continue
		var live: Color = _live[sm]
		sm.albedo_color = live.lerp(toward, k)


func _tint(mats: Array, col: Color) -> void:
	for m in mats:
		var sm := m as StandardMaterial3D
		if sm != null:
			sm.albedo_color = col
			sm.emission_energy_multiplier = 0.0


## ================================================================= bones ===

func _plan_bones() -> void:
	## Which bones are worth a pickup, in a stable order: the skull, the
	## ribs, then every leg bone hip-first. Keys are what the record's
	## `bones` map is written against, so they must not depend on anything
	## that can change between two builds of the same species.
	_bone_specs.clear()
	_add_bone_spec("skull", "skull", rig.get("head"))
	_add_bone_spec("ribs", "ribs", rig.get("body"))
	var legs: Array = rig.get("legs", [])
	var knees: Array = rig.get("knees", [])
	for i in legs.size():
		_add_bone_spec("leg%d_u" % i, "long", legs[i])
	for i in knees.size():
		_add_bone_spec("leg%d_l" % i, "long", knees[i])


func _add_bone_spec(key: String, kind: String, pivot: Variant) -> void:
	if not (pivot is Node):
		return
	var bid := skin.bone_of(pivot as Node)
	if bid <= 0:
		return
	var box := _biggest_box(pivot as Node)
	if box.is_empty():
		return
	_bone_specs.append({"key": key, "kind": kind, "bid": bid, "box": box})


func _biggest_box(pivot: Node) -> Dictionary:
	## The largest box a pivot wears, as it was before the bake: {pos, basis,
	## size} in the pivot's own space. A knee's is the shin, not the paw, so
	## a leg bone lies along the LEG even when the paw is the wider thing.
	var best := {}
	var bv := 0.0
	for c in pivot.get_children():
		var mi := c as MeshInstance3D
		if mi == null or not _size.has(mi):
			continue
		var sz: Vector3 = _size[mi]
		var v := sz.x * sz.y * sz.z
		if v > bv:
			bv = v
			best = {"pos": mi.position, "basis": mi.transform.basis, "size": sz}
	return best


func bone_keys() -> Array:
	var out: Array = []
	for s in _bone_specs:
		out.append(String((s as Dictionary)["key"]))
	return out


func _lay_bones(rec: Dictionary) -> void:
	## One DroppedItem per bone that is still here, where the bone lies.
	## Skipped: any the record says were taken, and any already lying.
	var taken: Dictionary = rec.get("bones", {})
	for s in _bone_specs:
		var spec := s as Dictionary
		var key := String(spec["key"])
		if taken.has(key):
			continue
		var cur: Variant = bones.get(key, null)
		if cur is Node and is_instance_valid(cur as Node):
			continue
		var di := _make_bone(spec)
		if di == null:
			continue
		bones[key] = di


func _make_bone(spec: Dictionary) -> DroppedItem:
	var bid := int(spec["bid"])
	var kind := String(spec["kind"])
	var box: Dictionary = spec["box"]
	var sz: Vector3 = box["size"]
	var long_axis := 0
	if sz.y > sz.x and sz.y >= sz.z:
		long_axis = 1
	elif sz.z > sz.x and sz.z > sz.y:
		long_axis = 2
	var len_m := sz[long_axis]
	if len_m < MIN_BONE_M:
		return null
	var others := [sz.x, sz.y, sz.z]
	others.remove_at(long_axis)
	var thick := minf(float(others[0]), float(others[1]))
	## A SKULL IS A HELM (Lemon, 2026-09-14): it carries the helmet slot, so
	## a click in the pack wears it, and a few per cent of bone between you
	## and a claw. The other bones are plain loot.
	var item := {
		"name": bone_item_name(kind, animal),
		"weight": bone_weight(kind, len_m),
		"count": 1,
		"slot": "helmet" if kind == "skull" else "",
		"protect": 0.03 if kind == "skull" else 0.0,
		"keep": true,
		"bone": kind,
		"bone_len": snappedf(len_m * 0.92, 0.01),
		"bone_r": snappedf(clampf(thick * 0.26, 0.018, 0.16), 0.005),
		"bone_w": snappedf(maxf(float(others[0]), float(others[1])) * 0.9, 0.01),
	}
	var di := DroppedItem.make(item)
	di.tumble = false
	di.keep_yaw = true
	## The bone lies along the axis its flesh was built on. Owner-space
	## poses, on purpose: this runs before the body is in the tree, and the
	## root never rotates, so owner space IS the body's local space.
	var t := skin.bone_pose(bid) * Transform3D(box["basis"] as Basis, box["pos"] as Vector3)
	var centre := t.origin
	if ground_fn.is_valid():
		## never under the turf: DroppedItem looks DOWN for its footing, and a
		## bone that starts below the surface finds nothing and keeps falling
		var gy := float(ground_fn.call(position + centre))
		centre.y = maxf(centre.y, gy - position.y + 0.06)
	var axis := Vector3.ZERO
	axis[long_axis] = 1.0
	var dir := (t.basis * axis).normalized()
	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.95:
		up = Vector3.BACK
	var bz := dir.cross(up).normalized()
	var by := bz.cross(dir).normalized()
	di.set_meta("carcass_bone", true)
	add_child(di)
	di.transform = Transform3D(Basis(dir, by, bz), centre)
	return di


func sweep_taken() -> Array:
	## The keys of every bone that was lying here and is not any more. A
	## bone only ever leaves by being picked up (they never expire), so a
	## freed node IS a taken bone — the bus writes it on the record.
	var gone: Array = []
	for k in bones.keys():
		var n: Variant = bones[k]
		## `is_instance_valid` FIRST: `is` on a freed instance is an error.
		if not is_instance_valid(n) or not (n is Node) or (n as Node).is_queued_for_deletion():
			gone.append(String(k))
			bones.erase(k)
	return gone


## ================================================================== slab ===

func _make_slab(yaw: float) -> MeshInstance3D:
	## The trodden ground. A flat box two centimetres proud of the terrain,
	## the size of the animal, along the line it lies on. Added AFTER the
	## bake on purpose: a box the skin can see becomes a rounded segment.
	var radius := length * Carcasses.GROUND_SCALE
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(radius * 1.5, 0.04, radius * 1.9)
	m.mesh = bm
	m.position = Vector3(0.0, SLAB_LIFT, 0.0)
	m.rotation.y = yaw
	var mat := StandardMaterial3D.new()
	mat.albedo_color = SOIL_FRESH
	mat.roughness = 0.95
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.material_override = mat
	m.name = "Slab"
	add_child(m)
	return m
