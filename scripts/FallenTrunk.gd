class_name FallenTrunk
extends RigidBody3D

## ===========================================================================
## The trunk on its way down, and where it lies afterwards.
## docs/TREES_v2_SPEC.md §8b
##
## It takes the WHOLE TREE with it — the carved trunk, its bark, and every limb
## still attached. Those limbs are real colliders, so a felled tree lands on its
## own branches and rests propped a little off the ground, like the real thing.
## The limbs caught underneath snap on impact and drop as sticks.
##
## It only hurts what it actually TOUCHES, and it only pins you if it came down
## on top of you rather than beside you.
##
## Once it is lying still, chopping it BUCKS it: one log per bite.
## ===========================================================================

const CRUSH_DAMAGE := 46.0         ## a mature trunk across the back
const PIN_ARMOR_TIER := 3          ## wear this or better and it only knocks you down
const PIN_SECONDS := 7.0           ## how long until it rolls off you
const PIN_ABOVE := 0.55            ## it must be THIS far above you to pin you
const BUCK_LENGTH := 2.0           ## metres of trunk per log (spec §8b)
## A log weighs what a log weighs. Shoulder-carrying is gone (Lemon
## 2026-08-30) and logs go in the pack like everything else -- but at 12.0
## against a base carry limit of 90 you still only get four or five before you
## are overburdened and cannot sprint. The old MAX_CARRY_LOGS = 4 survives as
## a consequence of weight instead of a hard-coded cap.
const LOG_WEIGHT := 12.0
const MIN_FALL_TIME := 1.6         ## it may not "settle" before it has fallen
const TOPPLE_SPIN := 0.35          ## rad/s the trunk starts leaning at
## The foot has to GRIP the stump rather than skate off it, or a tall conifer
## slides away from its own stump instead of hinging on it.
const FOOT_FRICTION := 1.4
## No felling tree ever needs to move faster than this. A hard cap is the cheap
## insurance against any solver blow-up throwing a log across the county again.
const MAX_FALL_SPEED := 18.0
## And if one somehow still refuses to settle, put it to sleep anyway rather
## than simulate a heavy compound body forever. chop_hit() needs `settled`, so
## a trunk that never settles can also never be bucked.
const SETTLE_DEADLINE := 12.0
const UNDER_LIMB := -0.05          ## a limb this far under the trunk axis is crushed

const BARK := {
	"maple": Color(0.145, 0.120, 0.105), "birch": Color(0.66, 0.66, 0.62),
	"oak": Color(0.125, 0.105, 0.092), "pine": Color(0.135, 0.105, 0.088),
	"fir": Color(0.115, 0.100, 0.092),
}

var species := "maple"
var trunk_len := 8.0
var trunk_r := 0.3
var logs_left := 3
var settled := false

var _crashed := false
var _age := 0.0
var _pinned_player: Node3D = null
var _pin_t := 0.0
var _mesh: MeshInstance3D
var _model: Node3D                 ## the whole felled tree, if one was handed over
## Bucking eats the trunk from its TOP end, so the butt has to stay where it
## fell. Both of these are fixed at _ready and never change with trunk_len.
var _orig_len := 0.0
var _base := 0.0
var _trunk_mi: MeshInstance3D = null      ## the model's own trunk mesh
var _trunk_pristine: Array = []           ## its surfaces, kept whole
var _trunk_mats: Array = []
## Per pristine surface: "wood" (the bark tube -- split on a cut and capped),
## "card" (leaf cards -- kept whole or dropped, never sliced), "cap" (an end
## grain disc an earlier cut already left on the wood).
var _trunk_kind: Array = []
## EVERY branch mesh on the model, big or small, with where it grows from the
## trunk in MESH space. _limbs only ever held the ones long enough to prop the
## trunk up; the twigs were never in any list, so when the section they grew
## on was bucked away they stayed exactly where they were -- floating in the
## air over the ground (Lemon 2026-09-14). A branch goes with the wood it is
## rooted in, whatever its size.
var _twigs: Array = []             ## [{mesh, base_y}]
var _landed := false               ## the crown has met the ground (sound)
var _prev_spd := 0.0
## How many sticks the branches give up when it lands. A PSX tree is one piece
## of wood with no separable limbs, so the sticks come from the crash rather
## than from limbing it beforehand.
var sticks := 0
## The felled tree's OWN leaf material, so the canopy can keep shedding while
## the trunk is in the air.
var leaf_mat: ShaderMaterial = null
var _shed := 0.0
var _limbs: Array = []             ## [{mesh, shape, centre}] — props that can snap
## THE TREE BROKE AT THE NOTCH. World metres of wood, measured from the old
## tree's foot, that stayed behind as the stump and are NOT part of this piece.
## Set by TreeV2._fell before the body enters the tree; zero for anything that
## came down whole.
var clip_below := 0.0


static func make(at: Vector3, fall_dir: Vector3, length: float, radius: float,
		species_id: String, logs: int) -> FallenTrunk:
	var t := FallenTrunk.new()
	t.species = species_id
	t.trunk_len = length
	t.trunk_r = radius
	t.logs_left = maxi(logs, 1)
	t.position = at
	t.set_meta("fall_dir", fall_dir)
	return t


func adopt(model: Node3D) -> void:
	## Take the standing tree's own geometry down with us: the notch stays cut,
	## the bark stays on, and the limbs come along still attached.
	_model = model


func _ready() -> void:
	add_to_group("fallen_trunks")
	add_to_group("choppable")
	mass = clampf(trunk_len * trunk_r * 120.0, 60.0, 900.0)
	contact_monitor = true
	max_contacts_reported = 6
	continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.friction = FOOT_FRICTION
	pm.bounce = 0.0
	physics_material_override = pm

	## Stand it up where the tree stood: the body's origin is the MIDDLE of the
	## cylinder, so it has to sit half a trunk above the stump or the log spawns
	## buried to the waist.
	position.y += trunk_len * 0.5
	_orig_len = trunk_len
	_base = -trunk_len * 0.5          ## local Y of the old tree's foot
	var base := _base
	## One log per BUCK_LENGTH of actual timber, so the count and the shrinking
	## trunk always agree. The old LOG_YIELD table was a flat per-stage number
	## and the trunk is species-length now: a 20 m ancient pine handing over
	## five logs and vanishing was most of why bucking read as broken.
	logs_left = clampi(int(round(trunk_len / BUCK_LENGTH)), 1, 14)

	if _model != null:
		add_child(_model)
		## The adopted geometry is the WHOLE tree, foot at its own origin. Drop
		## it by the break height so the line the axe cut sits on this body's
		## foot -- at the instant of felling nothing moves, the piece above the
		## notch is simply the only piece we own now.
		base -= clip_below
		_model.position = Vector3(0, base, 0)
		_build_limb_props(base)
		_clip_below_cut()
	else:
		var cyl := CylinderMesh.new()
		cyl.top_radius = trunk_r * 0.72
		cyl.bottom_radius = trunk_r
		cyl.height = trunk_len
		cyl.radial_segments = 10
		_mesh = MeshInstance3D.new()
		_mesh.mesh = cyl
		_mesh.material_override = _bark_material(trunk_r, trunk_len)
		add_child(_mesh)

	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = trunk_r
	shape.height = trunk_len
	cs.shape = shape
	add_child(cs)

	var dir: Vector3 = get_meta("fall_dir", Vector3.FORWARD)
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	call_deferred("_start_topple", dir)

	body_entered.connect(_on_body_entered)
	## The hinge goes: one long groan that ends on the snap, about as long as
	## the fall itself. A stump-less blast fell creaks too -- it is wood tearing.
	WoodAudio.creak(self, global_position + Vector3.DOWN * trunk_len * 0.5, trunk_len)


func _start_topple(dir: Vector3) -> void:
	## A REAL TREE HINGES ON ITS STUMP. This used to shove the top over with an
	## off-centre impulse, which sounds like the same thing and is not: a rigid
	## body rotates about its CENTRE OF MASS, and this body's centre is halfway
	## up the trunk. So the bottom half swung straight down THROUGH THE GROUND,
	## the solver answered a metres-deep penetration the way it always does, and
	## the log came out at up to 430 m/s. Measured landing distances from the
	## stump: 75 m to 310 m. That is the "cut a tree down and the base lags out
	## and freezes" report -- a 900 kg, 31-shape body with continuous_cd on,
	## ploughing through the world's collision at a hundred metres a second for
	## the better part of ten seconds.
	##
	## Instead: just NUDGE it into a slow lean and let the solver do the rest.
	## The body rotates about its centre of mass, the foot dips a few
	## centimetres into the ground, and the ground's own contact force is what
	## turns that into a pivot about the stump -- which is exactly how it works
	## with a real tree and a real floor. The whole trick is keeping the initial
	## spin SMALL enough that the dip is centimetres and not metres.
	##
	## The centre of mass gets v = w x r as well, which is what makes the foot
	## instantaneously stationary and the whole thing a pivot rather than a
	## body rocking on a contact. Without it a fat trunk never goes over at all:
	## a cylinder standing on a plane with its centre inside its own footprint
	## is statically stable, the ground absorbs the nudge, and an ancient oak
	## sat on its stump at 3 degrees for twelve seconds. WITH it, TOPPLE_SPIN
	## has to stay small -- it is also the sideways drift, and at 0.85 rad/s a
	## pine skated 26 m downrange still standing upright.
	## Deferred so the body is in the physics world before it gets hit.
	var w := dir.cross(Vector3.UP).normalized() * -TOPPLE_SPIN
	angular_velocity = w
	linear_velocity = w.cross(Vector3.UP * trunk_len * 0.5)


func _clip_below_cut() -> void:
	## Everything under the break line belongs to the stump, so it comes out of
	## this piece for good -- mesh and limbs both. Done ONCE, into the pristine
	## surfaces themselves, so the bucking clip later starts from a trunk whose
	## bottom already IS the break face and cannot resurrect the stump's wood.
	##
	## And the break face is WOOD. The tube is split exactly on the line, and
	## the loop it leaves is capped with end grain -- before this the butt of a
	## felled tree was an open tube you could see straight into (cull_back
	## draws nothing from inside), which is the "see-through bottom".
	if clip_below <= 0.0 or _model == null:
		return
	_cache_trunk_mesh()
	if _trunk_mi == null:
		return
	var floor_y := clip_below / maxf(_model.scale.y, 0.001)   ## mesh space
	var pr: Array = []
	var mats: Array = []
	var kinds: Array = []
	for si in range(_trunk_pristine.size()):
		var src: Array = _trunk_pristine[si]
		var kind := String(_trunk_kind[si])
		if kind == "card":
			var kept := WoodCut.cards(src, floor_y, INF)
			if not kept.is_empty():
				pr.append(kept)
				mats.append(_trunk_mats[si])
				kinds.append("card")
			continue
		var cut := WoodCut.slab(src, floor_y, INF, kind == "wood", false)
		if not (cut["wood"] as Array).is_empty():
			pr.append(cut["wood"])
			mats.append(_trunk_mats[si])
			kinds.append(kind)
		for cap in (cut["caps"] as Array):
			pr.append(cap)
			mats.append(WoodCut.grain_material(species))
			kinds.append("cap")
	_trunk_pristine = pr
	_trunk_mats = mats
	_trunk_kind = kinds
	_apply_surfaces(pr, mats)
	## A limb growing out of the stump's half stays on the stump.
	_hide_branches(-INF, floor_y, false)


func _build_limb_props(base: float) -> void:
	## One collider per limb. This is what holds a felled tree off the ground —
	## a bare cylinder lies flat and dead; a real one rests on its own branches.
	var parts: Node = _model
	if _model.get_child_count() == 1 and _model.get_child(0).get_child_count() > 0:
		parts = _model.get_child(0)
	for child in parts.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.name.begins_with("Branch"):
			continue
		var aabb := mi.mesh.get_aabb()
		## The model is a SCALED node (elder 1.7, great 3.5-4.5) and these
		## colliders are children of the BODY, so every length off the mesh has
		## to come across in body metres or a big tree props itself on spheres
		## in the wrong places at the wrong size.
		var ms := maxf(_model.scale.y, 0.001)
		var reach := aabb.size.length() * ms
		## every branch, whatever its size, is rooted somewhere on the trunk --
		## TreeKit puts a Branch mesh's origin at its own base, so mi.position.y
		## IS where it grows from, in mesh space
		_twigs.append({"mesh": mi, "base_y": mi.position.y, "reach": reach})
		if reach < 1.0:
			continue                      ## twigs don't hold a tree up
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		## Small props. Fat ones turned the tree into a tripod that stood there
		## at twenty degrees off vertical instead of coming down — a felled tree
		## rests ON its limbs, it does not get held up by them.
		sp.radius = clampf(reach * 0.09, 0.10, 0.38)
		cs.shape = sp
		cs.position = (mi.position + aabb.get_center()) * ms + Vector3(0, base, 0)
		## OFF UNTIL IT LANDS. These exist to hold a downed tree off the dirt,
		## and during the fall they do the opposite: up to 41 spheres bolted to
		## a rotating 15 m body sweep through the ground, each one penetrating
		## and each penetration answered with a shove. That is what kept the
		## logs travelling 20-40 m and stopped them ever lying flat. The trunk
		## falls as a clean cylinder hinging on its foot; the branches take over
		## the moment it touches down.
		cs.disabled = true
		add_child(cs)
		_limbs.append({"mesh": mi, "shape": cs, "centre": cs.position})

	if _limbs.is_empty():
		_prop_on_its_own_wood(base)


func _prop_on_its_own_wood(base: float) -> void:
	## A PSX trunk carries its limbs in the same mesh, so there is nothing to
	## walk. Two small props along its length do the same job the branch
	## colliders do: hold the log a hand's width off the dirt so it reads as
	## timber lying in a wood, not as a pipe painted onto the ground.
	for f in [0.42, 0.74]:
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = clampf(trunk_r * 1.35, 0.12, 0.40)
		cs.shape = sp
		cs.position = Vector3(0, base + trunk_len * f, trunk_r * 0.9)
		cs.disabled = true
		add_child(cs)
		_limbs.append({"mesh": null, "shape": cs, "centre": cs.position})


func _physics_process(delta: float) -> void:
	## THE BUG THAT KEPT TREES STANDING: this used to freeze the body the instant
	## it was slow — which on frame one, before gravity had touched it, was
	## immediately. The trunk froze bolt upright and never fell.
	_age += delta
	## The canopy keeps letting go all the way down, not in one pop at the top.
	if leaf_mat != null and _shed < 1.0:
		_shed = minf(_shed + delta * 0.85, 1.0)
		leaf_mat.set_shader_parameter("shed", _shed)
	## Hard speed cap — see _start_topple for what this is insuring against.
	if not freeze:
		var v := linear_velocity.length()
		if v > MAX_FALL_SPEED:
			linear_velocity = linear_velocity / v * MAX_FALL_SPEED
		if angular_velocity.length() > 8.0:
			angular_velocity = angular_velocity.normalized() * 8.0
	if not _landed and not settled and not freeze:
		## THE CROWN MEETING THE GROUND, heard. A falling trunk only ever speeds
		## up until something stops it, so the first hard drop in speed while
		## it is well over is the landing -- and it is one moment, not a
		## contact list, so it cannot fire at the foot's own touch on the stump.
		var spd := linear_velocity.length()
		var over := absf(global_transform.basis.y.dot(Vector3.UP)) < 0.85
		if over and _prev_spd - spd > 1.2 and _prev_spd > 1.5:
			_land_sound()
		_prev_spd = spd
	if _age < MIN_FALL_TIME:
		return
	if settled:
		return
	## "Finished falling" is not the same as "moving slowly". A trunk that has
	## only just started to lean is ALSO moving slowly, and freezing it there is
	## bug 8 from the v2 spec coming back -- the tree stands bolt upright with a
	## wedge cut out of it and never comes down. It has to be slow AND DOWN.
	var down := absf(global_transform.basis.y.dot(Vector3.UP)) < 0.64   ## >50 deg over
	var slow := linear_velocity.length() < 0.3 and angular_velocity.length() < 0.35
	if (slow and down) or _age > SETTLE_DEADLINE:
		settled = true
		freeze = true     ## stop simulating a log that has finished falling
		_land_sound()     ## if nothing else caught the landing, it is down now
		## ...and it sheds its limb colliders the moment it does. Those spheres
		## exist for ONE job: holding the trunk propped off the dirt while it is
		## still simulating. A frozen body is held up by nothing, so once it is
		## frozen they hold nothing -- all they still do is present up to forty
		## concave pockets to anything that walks into the log. A capsule that
		## wanders into one has no slide plane that reduces penetration (every
		## one points into the next sphere), move_and_slide resolves to zero in
		## every direction, and you are welded there with no pin state to time
		## out. Nothing MOVES when they go: the body is frozen, so the trunk
		## stays exactly where and how it landed. See Player._unwedge for the
		## belt to this pair of braces.
		_set_limb_colliders(false)

	if _pinned_player != null:
		_pin_t += delta
		if _pin_t >= PIN_SECONDS:
			_release_pin()


func _on_body_entered(body: Node) -> void:
	if not _crashed:
		_crashed = true
		for p in get_tree().get_nodes_in_group("player"):
			if p.has_method("tree_crash_shake"):
				p.tree_crash_shake(global_position)
		_snap_limbs_underneath()
	## a new contact once it is well over is the crown coming down
	if absf(global_transform.basis.y.dot(Vector3.UP)) < 0.85:
		_land_sound()

	## Only what the trunk ACTUALLY TOUCHES gets hurt. This used to sweep a
	## radius on impact and flatten everyone standing near the crash — which is
	## why felling a tree knocked you down every single time, wherever you were.
	var n3 := body as Node3D
	if n3 == null or not is_instance_valid(n3):
		return
	if not (n3.is_in_group("player") or n3.is_in_group("enemies")):
		return
	## A trunk that has finished falling is furniture. Without this, walking into
	## a log that has been lying there for a minute crushes you for CRUSH_DAMAGE
	## and pins you flat -- and the pinned phase has no rise timer, so from the
	## player's side that is the game locking up.
	if settled or freeze:
		return
	if n3.has_method("take_damage"):
		n3.take_damage(CRUSH_DAMAGE, global_position, true)
	_try_pin(n3)


func _land_sound() -> void:
	## Once, however it was noticed. Sized by the wood: a sapling flops, an
	## ancient oak is felt through the floor.
	if _landed:
		return
	_landed = true
	WoodAudio.crash(self, global_position, trunk_len * trunk_r)


func _set_limb_colliders(on: bool) -> void:
	## The limb spheres, all at once. Deferred because this is called from
	## inside the physics step.
	for L in _limbs:
		var cs := L["shape"] as CollisionShape3D
		if is_instance_valid(cs):
			cs.set_deferred("disabled", not on)


func _snap_limbs_underneath() -> void:
	## Whatever was caught between the trunk and the ground breaks. The limbs
	## that survive keep their colliders and hold the trunk up off the dirt --
	## and this is where those colliders come ON (see _build_limb_props).
	for L in _limbs:
		var cs := L["shape"] as CollisionShape3D
		if is_instance_valid(cs):
			cs.set_deferred("disabled", false)
	var axis := global_transform.basis.y.normalized()
	for L in _limbs.duplicate():
		var p: Vector3 = L["centre"]
		var perp := p - axis * p.dot(axis)          ## offset from the centre-line
		var world_perp := global_transform.basis * perp
		if world_perp.y > UNDER_LIMB:
			continue                                ## sticking up or out — it lives
		_snap_limb(L)
	if _limbs.is_empty() and sticks > 0:
		_drop_sticks(sticks)
		sticks = 0


func _drop_sticks(n: int) -> void:
	## Branches caught between the trunk and the ground snap on impact. With a
	## one-piece trunk there is nothing to hide, so they just come off it.
	var world := get_parent()
	if world == null:
		return
	var axis := global_transform.basis.y.normalized()
	for i in range(n):
		var f := (float(i) + 0.6) / float(n)
		var at := global_position + axis * (trunk_len * (f - 0.5))
		var s := DroppedItem.make({"name": "Stick", "weight": 0.3, "count": 1, "slot": ""})
		world.add_child(s)
		s.global_position = at + Vector3(randf_range(-0.5, 0.5), 0.3, randf_range(-0.5, 0.5))
		s.velocity = Vector3(randf_range(-1.6, 1.6), randf_range(0.9, 2.0), randf_range(-1.6, 1.6))


func _snap_limb(L: Dictionary) -> void:
	_limbs.erase(L)
	if L["mesh"] == null:
		return          ## a bare prop, not a limb: nothing to break off
	var mi: MeshInstance3D = L["mesh"] as MeshInstance3D if L["mesh"] != null else null
	var cs := L["shape"] as CollisionShape3D
	var at := global_position
	if mi != null and is_instance_valid(mi):
		at = mi.global_position
		mi.visible = false
	if is_instance_valid(cs):
		cs.queue_free()
	var world := get_parent()
	if world == null:
		return
	for _i in range(randi_range(1, 2)):
		var s := DroppedItem.make({"name": "Stick", "weight": 0.3, "count": 1, "slot": ""})
		world.add_child(s)
		s.global_position = at + Vector3(randf_range(-0.4, 0.4), 0.25, randf_range(-0.4, 0.4))
		s.velocity = Vector3(randf_range(-1.4, 1.4), randf_range(0.8, 1.8), randf_range(-1.4, 1.4))


func _try_pin(who: Node3D) -> void:
	## It can only pin you if it came down ON you. A trunk that lands alongside
	## knocks you flat at worst; it does not hold you there.
	if _pinned_player != null or not who.is_in_group("player"):
		return
	if global_position.y < who.global_position.y + PIN_ABOVE:
		return
	var tier := 0
	if who.has_method("armor_tier"):
		tier = int(who.call("armor_tier"))
	if tier >= PIN_ARMOR_TIER:
		return                      ## plate holds; the knockdown is enough
	if who.has_method("pin_under"):
		who.call("pin_under", self, PIN_SECONDS)
		_pinned_player = who
		_pin_t = 0.0


func _release_pin() -> void:
	if _pinned_player != null and is_instance_valid(_pinned_player) \
			and _pinned_player.has_method("release_pin"):
		_pinned_player.call("release_pin")
	_pinned_player = null
	_pin_t = 0.0
	## it rolls off — a shove away from whoever was under it. It is simulating
	## again, so it needs its limbs back to land on.
	freeze = false
	settled = false
	_set_limb_colliders(true)
	apply_central_impulse(Vector3(randf_range(-1.0, 1.0), 0.4, randf_range(-1.0, 1.0)) * mass * 0.05)


func free_pinned() -> void:
	## Someone else rolled it off you. (Co-op hook — see spec §8b.)
	_release_pin()


## ---------------------------------------------------------------- bucking ---

func chop_hit(_toward_chopper: Vector3, _aim := Vector3.INF) -> bool:
	## One bite of the axe on a downed trunk cuts one log free -- and the log
	## is THAT PIECE OF THE TREE, lying where it was, not a token that pops
	## off the end (Lemon 2026-09-14: "separate into logs from where the logs
	## were, as tree lying on the ground"). The last bite takes whatever is
	## left rather than leaving a stub that vanishes.
	if not settled:
		return false
	logs_left -= 1
	var last := logs_left <= 0 or trunk_len - BUCK_LENGTH < BUCK_LENGTH * 0.5
	var cut_len := trunk_len if last else BUCK_LENGTH
	_spawn_log(cut_len)
	trunk_len = maxf(trunk_len - cut_len, 0.0)
	if last:
		_scatter_last()
		queue_free()
		return true
	_resize()
	return false


func _resize() -> void:
	## THE BUG BEHIND "chopping trees into logs is broken": this only ever
	## resized `_mesh`, the plain cylinder used when NOTHING was handed over --
	## and a real felled tree always hands its whole model over, which leaves
	## `_mesh` null. So every bite spat out a log while the tree on the ground
	## did not change at all, and then the entire thing vanished on the last
	## one. The trunk has to visibly get shorter.
	##
	## It also resized the collider about its CENTRE, which ate the log from
	## both ends at once and walked the collision away from the mesh. Bucking
	## takes wood off the TOP; the butt stays where the tree fell.
	if _mesh != null and _mesh.mesh is CylinderMesh:
		(_mesh.mesh as CylinderMesh).height = trunk_len
		_mesh.position.y = _base + trunk_len * 0.5
	_clip_model()
	for c in get_children():
		var cs := c as CollisionShape3D
		if cs != null and cs.shape is CylinderShape3D:
			(cs.shape as CylinderShape3D).height = trunk_len
			cs.position.y = _base + trunk_len * 0.5


func _cache_trunk_mesh() -> void:
	## Lazy: a trunk nobody ever chops should not pay to copy its own mesh.
	if _trunk_mi != null or _model == null:
		return
	var parts: Node = _model
	if _model.get_child_count() == 1 and _model.get_child(0).get_child_count() > 0:
		parts = _model.get_child(0)
	for child in parts.get_children():
		var mi := child as MeshInstance3D
		if mi != null and mi.mesh != null and mi.name.begins_with("Trunk"):
			_trunk_mi = mi
			for i in range(mi.mesh.get_surface_count()):
				_trunk_pristine.append(mi.mesh.surface_get_arrays(i))
				_trunk_mats.append(mi.get_surface_override_material(i))
				## surface 0 is the bark tube; everything after it is leaf
				## cards (TreeKit._mesh_of), which are never sliced
				_trunk_kind.append("wood" if i == 0 else "card")
			return


func _clip_model() -> void:
	## Cut the trunk mesh off at the new length and put away everything beyond
	## it. Always rebuilt from the PRISTINE surfaces, never from the last clip,
	## so the cut is absolute and cannot compound -- the same rule
	## TreeV2._carve_notch follows for the notch.
	if _model == null:
		return
	_cache_trunk_mesh()
	if _trunk_mi == null:
		return
	## Mesh space, where the OLD TREE'S foot is still y = 0 -- so the cut has to
	## carry the wood already left behind on the stump, and come across the
	## model's scale.
	var limit := (trunk_len + clip_below) / maxf(_model.scale.y, 0.001)
	var surfaces: Array = []
	var mats: Array = []
	for si in range(_trunk_pristine.size()):
		var src: Array = _trunk_pristine[si]
		var kind := String(_trunk_kind[si])
		if kind == "card":
			var kept := WoodCut.cards(src, -INF, limit)
			if not kept.is_empty():
				surfaces.append(kept)
				mats.append(_trunk_mats[si])
			continue
		## the tube is split ON the line and the cut end capped with end
		## grain, so what is left is a log with a wooden face, not a pipe
		var cut := WoodCut.slab(src, -INF, limit, false, kind == "wood")
		if not (cut["wood"] as Array).is_empty():
			surfaces.append(cut["wood"])
			mats.append(_trunk_mats[si])
		for cap in (cut["caps"] as Array):
			surfaces.append(cap)
			mats.append(WoodCut.grain_material(species))
	_apply_surfaces(surfaces, mats)
	## branches rooted beyond the cut went with that section -- hidden, and
	## the big ones snap off as sticks the way limbs caught under it do
	_hide_branches(limit, INF, true)


func _apply_surfaces(surfaces: Array, mats: Array) -> void:
	if _trunk_mi == null:
		return
	if surfaces.is_empty():
		_trunk_mi.visible = false
		return
	var am := ArrayMesh.new()
	for arr in surfaces:
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_trunk_mi.mesh = am
	_trunk_mi.visible = true
	for i in range(mats.size()):
		_trunk_mi.set_surface_override_material(i, mats[i])


func _hide_branches(lo: float, hi: float, sticks_too: bool) -> void:
	## Put away every branch ROOTED between lo and hi (mesh-space heights on
	## the old tree's trunk). Rooted, not centred: a limb growing from wood
	## that is still here stays, however far it reaches; one growing from wood
	## that is gone goes with it, however small. Nothing is left in the air.
	var dropped := 0
	for tw in _twigs:
		var by := float(tw["base_y"])
		if by < lo or by > hi:
			continue
		var mi := tw["mesh"] as MeshInstance3D
		if mi == null or not is_instance_valid(mi) or not mi.visible:
			continue
		mi.visible = false
		## and if it was one of the props, its collider goes with it
		for L in _limbs.duplicate():
			if L["mesh"] == mi:
				var cs := L["shape"] as CollisionShape3D
				if is_instance_valid(cs):
					cs.queue_free()
				_limbs.erase(L)
				if sticks_too and dropped < 3 and float(tw["reach"]) >= 1.0:
					dropped += 1
					_stick_at(mi.global_position)


func _stick_at(at: Vector3) -> void:
	var world := get_parent()
	if world == null:
		return
	var s := DroppedItem.make({"name": "Stick", "weight": 0.3, "count": 1, "slot": ""})
	world.add_child(s)
	s.global_position = at + Vector3(randf_range(-0.4, 0.4), 0.25, randf_range(-0.4, 0.4))
	s.velocity = Vector3(randf_range(-1.4, 1.4), randf_range(0.8, 1.8), randf_range(-1.4, 1.4))


func _spawn_log(cut_len: float) -> void:
	## The log is the far `cut_len` metres of what is left, cut off ON the
	## line and lying exactly where that piece of trunk lay -- its own bark,
	## its own notch if the cut ran through one, end grain on both faces. It
	## is an ordinary dropped item: look at it, press E, it is in your pack.
	## (It used to be a CarryLog you hefted onto your shoulder; Lemon
	## 2026-08-30: logs are inventory now.)
	var world := get_parent()
	if world == null:
		return
	var r_here := maxf(trunk_r * 0.9, 0.05)
	var d := DroppedItem.make({"name": "Log", "weight": LOG_WEIGHT, "count": 1,
		"slot": "", "material": "",
		## timber does not rot away on a ten-minute fuse -- see DroppedItem.KEEPS
		"keep": true,
		"species": species, "log_len": cut_len, "log_r": r_here,
		"bark": BARK.get(species, Color(0.28, 0.19, 0.12))})
	world.add_child(d)
	if _model != null and _hand_section(d, cut_len):
		return
	## No model (a plain-cylinder trunk): a built log of the same size, laid
	## along the trunk's axis over the piece it replaces.
	var axis := global_transform.basis.y.normalized()
	var mi := WoodCut.log_instance(species, r_here, cut_len,
		BARK.get(species, Color(0.28, 0.19, 0.12)), hash(str(global_position, trunk_len)))
	d.adopt_log(mi, r_here)
	var centre := global_position + axis * (_base + trunk_len - cut_len * 0.5)
	var gb := (global_transform.basis * Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0),
		Vector3(0, 0, 1))).orthonormalized()
	d.global_transform = Transform3D(gb, centre - gb.y * r_here)


func _hand_section(d: DroppedItem, cut_len: float) -> bool:
	## Slice the section out of the trunk's own pristine tube, lay it down
	## along +X in the item's frame, and place the item so the piece has not
	## moved a millimetre from where it was on the trunk.
	_cache_trunk_mesh()
	if _trunk_mi == null:
		return false
	var ms := maxf(_model.scale.y, 0.001)
	var hi := (trunk_len + clip_below) / ms
	var lo := (trunk_len - cut_len + clip_below) / ms
	## never exactly on the butt's own cap: a hair above it, so the tube is
	## split there and gets its own face rather than inheriting a second,
	## coplanar one
	lo = maxf(lo, clip_below / ms + 0.002)
	if hi - lo < 0.02:
		return false
	var wood: Array = []
	var caps: Array = []
	for si in range(_trunk_pristine.size()):
		if String(_trunk_kind[si]) != "wood":
			continue      ## leaves and old faces stay behind; a log is bark and grain
		var cut := WoodCut.slab(_trunk_pristine[si], lo, hi, true, true)
		if not (cut["wood"] as Array).is_empty():
			wood.append(cut["wood"])
		caps.append_array(cut["caps"] as Array)
	if wood.is_empty():
		return false
	## the section's own centre-line, mesh space
	var v: PackedVector3Array = wood[0][Mesh.ARRAY_VERTEX]
	var cx := 0.0
	var cz := 0.0
	for p in v:
		cx += p.x
		cz += p.z
	cx /= float(v.size())
	cz /= float(v.size())
	var rsum := 0.0
	for p in v:
		rsum += Vector2(p.x - cx, p.z - cz).length()
	var r_here := maxf(rsum / float(v.size()) * ms, 0.05)
	var ymid := (lo + hi) * 0.5

	var mi := MeshInstance3D.new()
	var am := ArrayMesh.new()
	var laid := WoodCut.lay_down(wood[0], cx, ymid, cz, ms, -0.05)
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, laid["arrays"])
	var lift: float = laid["lift"]
	for extra in range(1, wood.size()):
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
			WoodCut.lay_down(wood[extra], cx, ymid, cz, ms, -0.05, lift)["arrays"])
	var n_wood := am.get_surface_count()
	for cap in caps:
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
			WoodCut.lay_down(cap, cx, ymid, cz, ms, -0.05, lift)["arrays"])
	mi.mesh = am
	## the tree's OWN bark (dead bark stays dead), just not swaying any more
	var bark: Material = _trunk_mats[0]
	if bark is ShaderMaterial:
		bark = (bark as ShaderMaterial).duplicate()
		(bark as ShaderMaterial).set_shader_parameter("sway", 0.0)
	else:
		bark = WoodCut.bark_material(species, BARK.get(species, Color(0.28, 0.19, 0.12)))
	for si in range(n_wood):
		mi.set_surface_override_material(si, bark)
	for si in range(n_wood, am.get_surface_count()):
		mi.set_surface_override_material(si, WoodCut.grain_material(species))
	## and this tree's own cut of the bark sheet
	for pname in ["bark_var", "bark_value"]:
		var val = _trunk_mi.get_instance_shader_parameter(pname)
		if val != null:
			mi.set_instance_shader_parameter(pname, val)
	d.adopt_log(mi, r_here)
	d.item["log_r"] = r_here

	## Where it was: the section centre, mesh -> body -> world, and the item's
	## +X along the trunk's +Y. The centre sits `lift` up the item's own Y.
	var xf := global_transform * _model.transform
	var centre := xf * Vector3(cx, ymid, cz)
	var gb := (xf.basis * Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1))).orthonormalized()
	d.global_transform = Transform3D(gb, centre - gb.y * lift)
	return true


func _scatter_last() -> void:
	var world := get_parent()
	for _i in range(randi_range(1, 3)):
		var s := DroppedItem.make({"name": "Stick", "weight": 0.3, "count": 1, "slot": ""})
		world.add_child(s)
		s.global_position = global_position + Vector3(randf_range(-0.8, 0.8), 0.3,
			randf_range(-0.8, 0.8))
		s.velocity = Vector3(randf_range(-1.5, 1.5), randf_range(1.0, 2.0), randf_range(-1.5, 1.5))


func _bark_material(r: float, along: float) -> Material:
	## One shared ShaderMaterial per species would tile wrongly on differently
	## sized logs, so this takes a duplicate and sets the tiling for THIS piece.
	var base: Material = TreeV2.materials_for(species)[0]
	var m: ShaderMaterial = (base as ShaderMaterial).duplicate()
	m.set_shader_parameter("tiling", Vector2(maxf(TAU * r * 1.6, 0.5), maxf(along * 1.6, 0.5)))
	m.set_shader_parameter("sway", 0.0)      ## it is on the ground; it does not sway
	return m