class_name MonsterDirector
extends Node
## ============================================================================
## MONSTER DIRECTOR — who puts generated monsters on the surface, where, when.
##
## The successor to the hand-made humanoid packs (Lemon, 2026-09-14: "scrap
## the current humanoid mobs for ... a monster random generator spawner, to
## make unique mobs at each level"). The caves roll their own through
## CaveRegion (MonsterGen.cave_key), the warbands stage their raiders
## through Warbands (MonsterGen.raider); up top THIS node keeps a small
## population near the player, the way SlimeDirector keeps the jellies:
## every CHECK seconds, if fewer than BUDGET of its monsters are alive, it
## rolls a pack out of sight in the 30..60 m ring, on dry ground, of one
## species picked from the ROSTER of the zone the spot is in at the
## player's current level tier (MonsterGen.pick). Packs that fall far
## behind are culled, so the population follows you.
##
## The roster is the zone's — walk into the next zone and the species
## change; level up and every zone gains a newcomer. `roster_here()` is
## what the Character Creator's Monster Lab and the M menu read.
##
## Set USE_MONSTERS = false to switch the surface population off in one
## line; the caves, the bands and the M menu are unaffected.
## ============================================================================

const USE_MONSTERS := true
const CHECK := 16.0
const BUDGET := 7
const RING := Vector2(30.0, 60.0)
const CULL_R := 150.0
const DAY_CHANCE := 0.45
const NIGHT_CHANCE := 0.75
const NIGHT := [20.5, 5.5]
const SETTLEMENT_KINDS := ["city", "town", "village", "hamlet", "camp", "docks", "market", "farm", "spawn", "keepout"]
const DEFAULT_SEED := 20260914

var player: Node3D = null
var live: Array = []
var spawned := 0
var world_seed := DEFAULT_SEED
var _t := 8.0
var _rng := RandomNumberGenerator.new()
var _daynight: Node = null


func bind_world(world: Node) -> void:
	if world == null:
		return
	if "_player" in world:
		player = world.get("_player") as Node3D
	if "_daynight" in world:
		_daynight = world.get("_daynight") as Node
	if "world_seed" in world:
		world_seed = int(world.get("world_seed"))
	_rng.randomize()


func _physics_process(delta: float) -> void:
	if not USE_MONSTERS or player == null or not is_instance_valid(player):
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
	spawn_pack(at)


func is_night() -> bool:
	var h := 12.0
	if _daynight != null and is_instance_valid(_daynight) and "hour" in _daynight:
		h = float(_daynight.get("hour"))
	return h >= float(NIGHT[0]) or h < float(NIGHT[1])


func player_level() -> int:
	if player != null and is_instance_valid(player) and "level" in player:
		return maxi(int(player.get("level")), 1)
	return 1


func tier() -> int:
	return MonsterGen.tier_for_level(player_level())


func key_at(pos: Vector3) -> String:
	return MonsterGen.zone_key(pos)


func roster_here() -> Array:
	## The species that hunt where the player stands, at the player's tier.
	if player == null or not is_instance_valid(player):
		return MonsterGen.roster(world_seed, "wild:wild:0,0", tier())
	return MonsterGen.roster(world_seed, key_at(player.global_position), tier())


func roll_for(pos: Vector3) -> Dictionary:
	return MonsterGen.pick(world_seed, key_at(pos), tier(), _rng)


func _in_settlement(pos: Vector3) -> bool:
	var z: Dictionary = WorldPlan.zone_at(pos.x, pos.z)
	return not z.is_empty() and SETTLEMENT_KINDS.has(str(z.get("kind", "")))


func _spawn_point() -> Vector3:
	for _a in range(10):
		var ang := _rng.randf() * TAU
		var rad := _rng.randf_range(RING.x, RING.y)
		var p: Vector3 = player.global_position + Vector3(cos(ang) * rad, 0, sin(ang) * rad)
		var map_on := Overworld.inst != null and Overworld.inst._loaded
		if map_on and not Overworld.in_bounds(p):
			continue
		if map_on and Overworld.is_water_at(p):
			continue
		if _in_settlement(p):
			continue   ## nothing spawns in the village square
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


func spawn_pack(at: Vector3, genome: Dictionary = {}) -> Array:
	## A pack of one species at `at`. Empty genome = roll it for the zone.
	if genome.is_empty():
		genome = roll_for(at)
	var out: Array = []
	var parent := get_parent()
	if parent == null or genome.is_empty():
		return out
	var pk: Array = genome.get("pack", [1, 2])
	var n := _rng.randi_range(int(pk[0]), int(pk[1]))
	n = mini(n, BUDGET - live.size())
	for i in range(n):
		var m := Monster.from(genome)
		parent.add_child(m)
		var off := Vector3.ZERO if i == 0 else Vector3(_rng.randf_range(-3.0, 3.0), 0.0, _rng.randf_range(-3.0, 3.0))
		var g := _ground_at(at + off)
		m.global_position = g if g != Vector3.INF else at + off
		live.append(m)
		out.append(m)
		spawned += 1
	return out


func _cull() -> void:
	var i := live.size() - 1
	while i >= 0:
		var m = live[i]
		if m == null or not is_instance_valid(m) or (m as Node).is_queued_for_deletion():
			live.remove_at(i)
		elif player != null and (m as Node3D).global_position.distance_to(player.global_position) > CULL_R:
			(m as Node).queue_free()
			live.remove_at(i)
		i -= 1


func census() -> Dictionary:
	_cull()
	var by := {}
	for m in live:
		var key := String((m as Monster).display_name)
		by[key] = int(by.get(key, 0)) + 1
	return {"live": live.size(), "spawned": spawned, "by_species": by}
