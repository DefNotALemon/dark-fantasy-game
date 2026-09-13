class_name SlimeDirector
extends Node
## ============================================================================
## SLIME DIRECTOR — who puts jellies on the surface, where, and when.
##
## The caves seed their own (CaveRegion._spawn_dwellers rolls slime pockets
## in the shallow and middle galleries). Up top, this node keeps a small
## population of them near the player: every CHECK seconds, if fewer than
## BUDGET director-spawned slimes are alive, it rolls a pocket — two to four
## of one colour, out of sight in the 28..55 m ring, on dry ground, the colour
## picked by Slime.kind_for_zone from the same zone reading the wildlife uses
## (lakes are the blue one's, the frozen north is the rime one's, night lets
## the venom and the tar out). Pockets that fall far behind the player are
## culled, so the population follows you rather than littering the map.
##
## Set USE_SLIMES = false to turn the surface population off in one line —
## the caves, the M menu and the bestiary are unaffected.
## ============================================================================

const USE_SLIMES := true
const CHECK := 18.0
const BUDGET := 6
const RING := Vector2(28.0, 55.0)
const CULL_R := 140.0
const DAY_CHANCE := 0.40
const NIGHT_CHANCE := 0.65
const NIGHT := [20.5, 5.5]      ## from .. to (wraps midnight)
const POCKET := Vector2i(2, 4)
const WATER_ZONE_R := 36.0

var player: Node3D = null
var live: Array = []            ## the slimes this node made (culled by it too)
var spawned := 0                ## lifetime count (tests, census)
var _t := 6.0                   ## first roll a few seconds after boot
var _rng := RandomNumberGenerator.new()
var _daynight: Node = null


func bind_world(world: Node) -> void:
	if world == null:
		return
	if "_player" in world:
		player = world.get("_player") as Node3D
	if "_daynight" in world:
		_daynight = world.get("_daynight") as Node
	_rng.randomize()


func _physics_process(delta: float) -> void:
	if not USE_SLIMES or player == null or not is_instance_valid(player):
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = CHECK
	_cull()
	if live.size() >= BUDGET:
		return
	if EditorMode.active:
		return
	var chance := NIGHT_CHANCE if is_night() else DAY_CHANCE
	if _rng.randf() > chance:
		return
	var at := _spawn_point()
	if at == Vector3.INF:
		return
	spawn_pocket(at)


func is_night() -> bool:
	var h := 12.0
	if _daynight != null and is_instance_valid(_daynight) and "hour" in _daynight:
		h = float(_daynight.get("hour"))
	return h >= float(NIGHT[0]) or h < float(NIGHT[1])


func zone_at(pos: Vector3) -> String:
	## The wildlife's reading of the land, for the colour roll: water first,
	## then the bake's named region (through WildlifeDirector.REGION_ZONE),
	## then the woods by density. No map loaded: everything is "deep_woods".
	if Overworld.inst == null or not Overworld.inst._loaded:
		return "deep_woods"
	var nw: Dictionary = Overworld.nearest_water(pos, WATER_ZONE_R)
	if float(nw.get("dist", INF)) <= WATER_ZONE_R:
		return "gulf" if bool(nw.get("sea", false)) else "lake"
	var rn: String = Overworld.inst.region_name_at(pos)
	if WildlifeDirector.REGION_ZONE.has(rn):
		return String(WildlifeDirector.REGION_ZONE[rn])
	var w: float = Overworld.inst._plantable(pos.x, pos.z)
	return "deep_woods" if w > 0.45 else "field"


func _spawn_point() -> Vector3:
	## In the ring, on dry ground, in bounds, and preferably not in front of
	## the player's eyes.
	for _a in range(10):
		var ang := _rng.randf() * TAU
		var rad := _rng.randf_range(RING.x, RING.y)
		var p: Vector3 = player.global_position + Vector3(cos(ang) * rad, 0, sin(ang) * rad)
		var map_on := Overworld.inst != null and Overworld.inst._loaded
		if map_on and not Overworld.in_bounds(p):
			continue
		if map_on and Overworld.is_water_at(p):
			continue
		var fwd := -player.global_transform.basis.z
		var to := (p - player.global_position).normalized()
		if to.dot(fwd) > 0.5 and _rng.randf() < 0.7:
			continue
		var g := _ground_at(p)
		if g == Vector3.INF:
			continue
		return g
	return Vector3.INF


func _ground_at(pos: Vector3) -> Vector3:
	var space := get_tree().root.world_3d.direct_space_state
	if space == null:
		return Vector3.INF
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 30.0, pos + Vector3.DOWN * 40.0)
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return Vector3.INF
	return (hit["position"] as Vector3) + Vector3.UP * 0.2


func spawn_pocket(at: Vector3, kind := "") -> Array:
	## A pocket of one colour at `at`. Returns the slimes. `kind` empty =
	## roll it for the zone and the hour.
	if kind == "":
		kind = Slime.kind_for_zone(zone_at(at), is_night(), _rng)
	var n := _rng.randi_range(POCKET.x, POCKET.y)
	if kind == "gold":
		n = 1
	elif kind == "black":
		n = _rng.randi_range(1, 2)
	n = mini(n, BUDGET - live.size())
	var out: Array = []
	var parent := get_parent()
	if parent == null or n <= 0:
		return out
	for i in range(n):
		var s := Slime.make(kind)
		parent.add_child(s)
		var off := Vector3.ZERO if i == 0 else Vector3(_rng.randf_range(-2.5, 2.5), 0.0, _rng.randf_range(-2.5, 2.5))
		var g := _ground_at(at + off)
		s.global_position = g if g != Vector3.INF else at + off
		live.append(s)
		out.append(s)
		spawned += 1
	return out


func _cull() -> void:
	var i := live.size() - 1
	while i >= 0:
		var s = live[i]
		if s == null or not is_instance_valid(s) or (s as Node).is_queued_for_deletion():
			live.remove_at(i)
		elif player != null and (s as Node3D).global_position.distance_to(player.global_position) > CULL_R:
			(s as Node).queue_free()
			live.remove_at(i)
		i -= 1


func census() -> Dictionary:
	_cull()
	var by := {}
	for s in live:
		var key := String((s as Slime).kind)
		by[key] = int(by.get(key, 0)) + 1
	return {"live": live.size(), "spawned": spawned, "by_kind": by}
