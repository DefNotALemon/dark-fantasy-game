class_name CritterSwarm
extends Node3D

## ===========================================================================
## SWARMS — the things there are too many of to think.  docs/WILDLIFE.md §1
##
## Bats out of the mill gables at dusk, fireflies over a June meadow, a
## blackfly cloud that follows you across a bog, monarchs drifting one way
## south all September. None of these has AI, a health bar, or a collision
## shape. They are ONE MultiMeshInstance3D each, steered by noise, and they
## carry more atmosphere per millisecond than anything else in the feature.
##
## The rule that keeps them cheap: no per-member nodes, no physics, no
## allocation after build. The whole swarm is a transform array rewritten in
## place each frame.
##
## Blackflies are the exception that earns its keep — they are the only swarm
## that touches the player, and being chased off a bog by insects in late
## spring is a real Maine experience and a real reason to plan travel around
## the season.
## ===========================================================================

const HARASS_DPS := 0.9          ## the nagging tick, not a threat
const HARASS_RADIUS := 2.6
const SMOKE_RADIUS := 7.0        ## a fire or a smudge keeps them off you

## --------------------------------------------------------------- swatting ---
## A swing kills blackflies. It does NOT solve blackflies — they come back, one
## at a time, on their own clocks, and there are sixty of them. Smoke is still
## the answer; the axe is just satisfying. That gap is the whole design of it:
## the swat has to FEEL like it worked without ever actually working.
const RESPAWN := Vector2(18.0, 34.0)   ## seconds before a swatted one is back
## Lenient on purpose. The first version used a 0.25 cone anchored a metre in
## FRONT of the player, and blackflies orbit your head — so most of the cloud
## sat behind the swing origin and six of sixty died. You are not fencing with
## them, you are flailing at your own face; anything not squarely behind you is
## fair. -0.35 still means a swing pointed away from them misses.
const SWAT_ARC := -0.35
const SWAT_REACH_MULT := 1.6           ## the sweep is bigger than the weapon
## Standing INSIDE the cloud, the arc stops meaning anything — you are swatting
## around your own head, and flies at your shoulder are as fair as flies at
## your nose. Inside this fraction of the sweep radius the arc is dropped
## entirely; outside it, a swing still has to point at them.
const SWAT_INSIDE := 0.8
const SWAT_CHEST := 1.2                ## swung at head/chest height, where they are
const SWAT_LEAD := 0.15                ## barely ahead of you — the cloud is ON you
## Share of the WHOLE cloud one swing may take, nearest first. 0.6 means the
## first swing leaves 40% and the second finishes them: two hits clears it,
## which is what was asked for and is far easier to read than a slow grind.
const SWAT_SHARE := 0.6
const SCATTER_TIME := 0.9              ## how long an unswattable cloud blows apart
const SCATTER_PUSH := 2.6

var species := "firefly"
var count := 20
var radius := 9.0                ## how far members range from the swarm centre
var height := 3.0
var speed := 1.4
var follows_player := false
var glows := false

var _mm: MultiMeshInstance3D
var _phase: PackedFloat32Array = PackedFloat32Array()
var _seed: PackedFloat32Array = PackedFloat32Array()
## Per-member respawn clock. 0 = flying, > 0 = swatted and counting back.
## A parallel float array, not an object per fly — the whole point of a swarm
## is that nothing in it is a node.
var _dead: PackedFloat32Array = PackedFloat32Array()
## Where every member actually is, in LOCAL space, as of the last _write.
## The swat reads this rather than asking the MultiMesh — a render-server
## readback per fly per swing is both slower and a lie: the headless renderer
## does not keep instance transforms at all, so anything that reads them back
## works in the editor and silently does nothing in a test or a dedicated
## server. Own your own data.
var _pos: PackedVector3Array = PackedVector3Array()
var _t := 0.0
var _harass_t := 0.0
var _home := Vector3.ZERO
var _scatter_t := 0.0
var _scatter_from := Vector3.ZERO


static func make(key: String, at: Vector3) -> CritterSwarm:
	var s := CritterSwarm.new()
	s.species = key
	var _p := CritterDex.get_profile(key)
	s.count = int(CritterDex.flag(key, "swarm", 12))
	s.glows = bool(CritterDex.flag(key, "glows", false))
	s.follows_player = bool(CritterDex.flag(key, "harasses", false)) \
		or bool(CritterDex.flag(key, "lightseek", false))
	match key:
		"bat":
			s.radius = 22.0
			s.height = 7.0
			s.speed = 7.5
		"firefly":
			s.radius = 14.0
			s.height = 1.9
			s.speed = 0.8
		"blackfly":
			s.radius = 2.4
			s.height = 1.7
			s.speed = 2.4
		"dragonfly":
			s.radius = 10.0
			s.height = 1.4
			s.speed = 4.5
		"monarch":
			s.radius = 16.0
			s.height = 2.6
			s.speed = 1.6
		"luna_moth":
			s.radius = 4.0
			s.height = 2.0
			s.speed = 1.1
		"tidepool":
			s.radius = 3.0
			s.height = 0.10
			s.speed = 0.35
		_:
			s.radius = 8.0
	s.position = at
	return s


func _ready() -> void:
	add_to_group("critter_swarms")
	add_to_group("wildlife")
	_home = global_position
	_build()


func _build() -> void:
	var p := CritterDex.get_profile(species)
	var L := float(p.get("len", 0.05))
	var col: Color = p.get("col", Color.WHITE)

	var mesh := BoxMesh.new()
	## Fliers read as a smear, not a body — a wide flat box at this size is a
	## wingbeat. A crab is a crab.
	if species == "tidepool":
		mesh.size = Vector3(L * 1.6, L * 0.7, L * 1.4)
	else:
		mesh.size = Vector3(maxf(L * 3.0, 0.03), maxf(L * 0.7, 0.008), maxf(L * 1.4, 0.02))

	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 1.0
	mat.vertex_color_use_as_albedo = false
	if glows:
		## Fireflies are the whole reason the gloom is worth having.
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 3.2
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if species == "blackfly" or species == "bat":
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count

	_mm = MultiMeshInstance3D.new()
	_mm.multimesh = mm
	_mm.material_override = mat
	_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mm)

	_phase.resize(count)
	_seed.resize(count)
	_dead.resize(count)
	_pos.resize(count)
	for i in range(count):
		_phase[i] = randf() * TAU
		_seed[i] = randf() * 10.0
		_dead[i] = 0.0
		mm.set_instance_color(i, Color.WHITE)
	_write(0.0)


func _process(delta: float) -> void:
	_t += delta
	## Off-screen swarms do nothing. There is no state to keep warm.
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl != null:
		var d := global_position.distance_to(pl.global_position)
		if d > 90.0:
			return
		if follows_player and d < 40.0:
			## Blackflies find you. That is their entire personality.
			var want := pl.global_position + Vector3(0, 0.6, 0)
			global_position = global_position.lerp(want, clampf(delta * 0.55, 0.0, 1.0))
		if bool(CritterDex.flag(species, "harasses", false)) and d < HARASS_RADIUS:
			_harass(pl, delta)
	_write(delta)


func _harass(pl: Node3D, delta: float) -> void:
	## Smoke, water and speed all beat them. Standing still in a bog does not.
	for f in get_tree().get_nodes_in_group("campfires"):
		if (f as Node3D).global_position.distance_to(pl.global_position) < SMOKE_RADIUS:
			return
	## Thinning the cloud thins the biting — proportionally, and no more than
	## that. Swat half of them and it is half as bad, which is exactly as much
	## relief as swatting half of them deserves.
	var share := float(alive_count()) / maxf(float(count), 1.0)
	if share <= 0.0:
		return
	if pl.has_method("apply_bug_bites"):
		pl.call("apply_bug_bites", HARASS_DPS * share * delta)
		return
	_harass_t += delta
	if _harass_t >= 1.0:
		_harass_t = 0.0
		if pl.has_method("take_damage"):
			pl.take_damage(HARASS_DPS * share, global_position, false, Vector3.INF, null)


## =============================== Swatting =================================


func alive_count() -> int:
	var n := 0
	for i in range(_dead.size()):
		if _dead[i] <= 0.0:
			n += 1
	return n


static func swat_from(who: Node3D, forward: Vector3, reach: float) -> int:
	## THE ONE PLACE THE SWING GEOMETRY LIVES.
	##
	## It used to live in Player._swat_bugs, where the test suite could not
	## reach it — so the suite hand-picked a swat point at the middle of the
	## cloud, passed happily, and the actual game killed six flies out of
	## sixty. Geometry that gameplay depends on belongs somewhere it can be
	## measured. Player now calls this and does nothing else.
	if who == null or not who.is_inside_tree():
		return 0
	var f := forward
	f.y = 0.0
	f = f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD
	var at := who.global_position + Vector3.UP * SWAT_CHEST + f * (reach * SWAT_LEAD)
	return swat_all(who, at, reach * SWAT_REACH_MULT, f)


static func swat_all(from: Node, at: Vector3, reach: float, dir: Vector3) -> int:
	## One call for the whole world. The player swings, every swarm in range
	## gets asked what that did to it — the biting ones lose members, the
	## pretty ones just blow apart for a second.
	if from == null or not from.is_inside_tree():
		return 0
	var killed := 0
	for n in from.get_tree().get_nodes_in_group("critter_swarms"):
		var s := n as CritterSwarm
		if s != null and is_instance_valid(s):
			killed += s.swat(at, reach, dir)
	return killed


func swat(at: Vector3, reach: float, dir: Vector3) -> int:
	## Everything inside the arc dies, or scatters if it is not the kind of
	## thing an axe should kill. A firefly is not a pest and a luna moth is
	## the best thing in the game — neither is worth punishing the player for
	## swinging near.
	if not visible:
		return 0
	if global_position.distance_to(at) > reach + radius + 2.0:
		return 0
	if not bool(CritterDex.flag(species, "swattable", false)):
		_scatter_t = SCATTER_TIME
		_scatter_from = at
		return 0

	var d := dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	var r2 := reach * reach
	## Gather everything the swing could reach, then take the nearest share of
	## it. Sorting sixty floats once per swing is nothing, and it means the
	## ones that die are the ones that were in your face — not an arbitrary
	## slice in array order.
	var inside := global_position.distance_to(at) <= reach * SWAT_INSIDE
	var hits: Array = []
	for i in range(count):
		if _dead[i] > 0.0:
			continue
		## Where this one actually is, from the array _write keeps — the same
		## numbers that produced the transform, with no readback and no second
		## copy of the flight maths to drift out of sync.
		var wp: Vector3 = global_transform * _pos[i]
		var to := wp - at
		## Full 3D distance, deliberately: a swing at chest height should not
		## kill the ones around your boots.
		if to.length_squared() > r2:
			continue
		if not inside and to.length() > 0.01 and d.dot(to.normalized()) < SWAT_ARC:
			continue
		hits.append({"i": i, "d2": to.length_squared(), "wp": wp})
	hits.sort_custom(func(a, b): return float(a["d2"]) < float(b["d2"]))

	var cap := maxi(1, int(ceil(float(count) * SWAT_SHARE)))
	var killed := 0
	var centroid := Vector3.ZERO
	for h in hits:
		if killed >= cap:
			break
		_dead[int(h["i"])] = randf_range(RESPAWN.x, RESPAWN.y)
		centroid += h["wp"] as Vector3
		killed += 1
	if killed == 0:
		## Missed, but the air still moved.
		_scatter_t = SCATTER_TIME * 0.6
		_scatter_from = at
		return 0
	centroid /= float(killed)
	## ONE burst for the whole swat, not one per fly — sixty particle systems
	## in a frame is a stutter, and a single pop at the middle of the arc reads
	## better anyway. And it is red on purpose: a blackfly that has been on you
	## for ten seconds is full of your blood. Settings -> Blood: Off swaps it
	## for a colourless puff like everything else, no special case needed.
	HitFX.flesh(centroid, d, clampf(0.10 + float(killed) * 0.035, 0.10, 0.55))
	return killed


func _write(delta: float) -> void:
	## The whole swarm, rewritten in place. Three sines and a seed per member
	## gives every one of them its own wandering path without a single
	## allocation or a single branch.
	var mm := _mm.multimesh
	var flat := species == "tidepool"
	_scatter_t = maxf(0.0, _scatter_t - delta)
	for i in range(count):
		## Swatted. Park it at zero scale and count it back — the array slot
		## stays put, so a returning fly keeps its own phase and seed and
		## rejoins the cloud on the path it always flew.
		if _dead[i] > 0.0:
			_dead[i] = maxf(0.0, _dead[i] - delta)
			if _dead[i] > 0.0:
				mm.set_instance_transform(i, Transform3D(
					Basis().scaled(Vector3(0.0001, 0.0001, 0.0001)), Vector3(0, -900.0, 0)))
				continue
		var s := _seed[i]
		var ph := _phase[i]
		var t := _t * speed
		var x := sin(t * 0.31 + ph) * radius * (0.35 + 0.65 * sin(s))
		var z := cos(t * 0.27 + ph * 1.7) * radius * (0.35 + 0.65 * cos(s * 1.3))
		var y := height * (0.5 + 0.5 * sin(t * 0.53 + s * 2.1))
		if flat:
			## Tidepool life scuttles; it does not fly.
			y = 0.02
			x = sin(t * 0.5 + ph) * radius
			z = cos(t * 0.41 + s) * radius
		elif species == "monarch":
			## The one-way southward drift — a calendar you can watch.
			z += fposmod(t * 0.5 + s * 3.0, radius * 2.0) - radius
			y = height * (0.4 + 0.35 * sin(t * 1.7 + ph))
		elif species == "bat":
			## Bats strafe: fast, erratic, and mostly in a plane.
			x += sin(t * 2.3 + s) * 3.4
			z += cos(t * 1.9 + s * 2.0) * 3.4
			y = height * (0.7 + 0.3 * sin(t * 3.1 + ph))
		var pos := Vector3(x, y, z)

		## A swing through a cloud that is not worth killing still blows it
		## apart — fireflies burst outward and drift back. Costs one lerp and
		## it is the difference between an axe that moves air and one that
		## passes through a photograph.
		if _scatter_t > 0.0:
			var away := (global_transform * pos) - _scatter_from
			away.y = absf(away.y) + 0.2      ## up and out, never down into the ground
			if away.length_squared() > 0.0001:
				var u := _scatter_t / SCATTER_TIME
				pos += global_transform.basis.inverse() * (away.normalized() * SCATTER_PUSH * u * u)

		_pos[i] = pos

		## Face travel. Cheap approximation: the derivative of the sines.
		var vx := cos(t * 0.31 + ph)
		var vz := -sin(t * 0.27 + ph * 1.7)
		var yaw := atan2(vx, vz)
		var b := Basis(Vector3.UP, yaw)
		if not flat:
			b = b.rotated(b.x, sin(t * 9.0 + ph) * 0.5)   ## wingbeat roll
		mm.set_instance_transform(i, Transform3D(b, pos))

		if glows:
			## Fireflies do not glow continuously — they pulse, out of step,
			## and the dark between the flashes is the effect.
			var blink := pow(maxf(sin(t * 1.7 + ph * 3.1), 0.0), 8.0)
			mm.set_instance_color(i, Color(1, 1, 1, 1) * blink)


func set_visible_for(hour: float, phase: float) -> void:
	## The director keeps swarms honest about when they exist: no fireflies in
	## February, no blackflies in the snow, no bats at noon.
	visible = CritterDex.is_awake(species, hour, phase)
	set_process(visible)
