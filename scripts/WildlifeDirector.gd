class_name WildlifeDirector
extends Node

## ===========================================================================
## THE DIRECTOR — who is out, where, and when.          docs/WILDLIFE.md §1
##
## Streams wildlife around the player against a per-zone budget, honours the
## clock and the calendar, keeps herds together, runs the once-a-year events,
## and places the legends by hand because legends are level design, not a
## spawn roll.
##
## The single most important number in here is the BUDGET. A forest reads as
## alive at a surprisingly low density — the trick is not MORE animals, it is
## the right animal in the right place at the right hour, plus an audio layer
## carrying the ones that were never spawned at all (see CritterAudio).
##
## Wired up by World.gd:
##     var wl := WildlifeDirector.new()
##     wl.player = _player
##     wl.world_radius = WORLD_RADIUS
##     add_child(wl)
## ===========================================================================

## How many live critters may exist at once, by how far the player is from
## anything interesting. Deliberately modest — the trees already cost 420
## draw calls and the budget in TREES_v2_SPEC §11 was written for 250.
const BUDGET := 26
const SWARM_BUDGET := 5
const SPAWN_RING := Vector2(26.0, 62.0)   ## never spawn inside the player's view
const DESPAWN_AT := 96.0
const RESPAWN_GAP := 1.1                  ## seconds between spawn attempts
const HERD_SPREAD := 5.5
const LEGEND_CHECK := 45.0

## The world's zones are not painted yet (map v1 is art, not data), so the
## director derives one from position. When the real zone map lands, replace
## _zone_at() and NOTHING else in this file changes.
const ZONE_RINGS := [
	{"zone": "field", "r0": 0.0, "r1": 0.22},
	{"zone": "deep_woods", "r0": 0.22, "r1": 0.62},
	{"zone": "moosehead", "r0": 0.62, "r1": 0.82},
	{"zone": "county", "r0": 0.82, "r1": 1.01},
]

var player: Node3D = null
var world_radius := 80.0
var enabled := true

var _t := 0.0
var _spawn_t := 0.0
var _legend_t := 12.0
var _rng := RandomNumberGenerator.new()
var _hour := 17.0
var _phase := 0.35
var _day := 0.0
var _last_season := -1
var _big_night_done := -1        ## which year's Big Night has already fired
var _skein_t := 60.0
var _audio: CritterAudio = null
var _tele: Telegraph = null

## Everything the director has placed, so save/load and the budget agree.
var live: Array[Critter] = []
var swarms: Array[CritterSwarm] = []
var legends_placed: Dictionary = {}


func _ready() -> void:
	add_to_group("wildlife_director")
	_rng.seed = 90210
	_audio = CritterAudio.get_bus(self)
	_tele = Telegraph.get_bus(self)


## ================================ Clock ===================================


func set_clock(hour: float, day: float) -> void:
	_hour = hour
	_day = day
	_phase = Wind.phase_for_day(day)
	var s := CritterDex.season_of(_phase)
	if s != _last_season:
		_last_season = s
		_on_season_turn(s)
	for c in live:
		if is_instance_valid(c):
			c.set_clock(_hour, _phase)
	for sw in swarms:
		if is_instance_valid(sw):
			sw.set_visible_for(_hour, _phase)
	if _audio != null and is_instance_valid(_audio) and player != null:
		_audio.set_clock(_hour, _phase, _zone_at(player.global_position), player)


func _on_season_turn(season: int) -> void:
	## The turns that matter. Bears go under, geese go over, the hares change
	## colour, and everything that migrated leaves or comes back — enforced by
	## culling anything that should no longer be here, so the world does not
	## keep a loon on an iced-over lake.
	var i := live.size() - 1
	while i >= 0:
		var c := live[i]
		if not is_instance_valid(c):
			live.remove_at(i)
		elif not CritterDex.is_awake(c.species, _hour, _phase):
			c.queue_free()
			live.remove_at(i)
		i -= 1
	if season == CritterDex.AUTUMN or season == CritterDex.SPRING:
		_skein_t = _rng.randf_range(20.0, 90.0)


## =============================== Main loop ================================


func _process(delta: float) -> void:
	if not enabled or player == null or not is_instance_valid(player):
		return
	_t += delta
	_spawn_t -= delta
	_legend_t -= delta
	_skein_t -= delta

	_cull()
	if _spawn_t <= 0.0:
		_spawn_t = RESPAWN_GAP
		if live.size() < BUDGET:
			_try_spawn()
		if swarms.size() < SWARM_BUDGET:
			_try_swarm()
	if _legend_t <= 0.0:
		_legend_t = LEGEND_CHECK
		_legend_check()
	if _skein_t <= 0.0:
		_skein_t = _rng.randf_range(180.0, 520.0)
		_maybe_skein()
	_maybe_big_night()
	## The player's own noise goes on the wire — crashing through the brush
	## empties the woods ahead of you, and that IS the stealth mechanic.
	if _tele != null and is_instance_valid(_tele) and player.has_method("get") :
		var v = player.get("velocity")
		if v is Vector3:
			var spd: float = Vector2((v as Vector3).x, (v as Vector3).z).length()
			_tele.player_noise(player.global_position, clampf(spd / 7.0, 0.0, 1.0))


func _cull() -> void:
	var i := live.size() - 1
	while i >= 0:
		var c := live[i]
		if not is_instance_valid(c) or c.dying:
			live.remove_at(i)
		elif c.global_position.distance_to(player.global_position) > DESPAWN_AT and c.mood == Critter.Mood.EASY:
			if not c.legend:
				c.queue_free()
			live.remove_at(i)
		i -= 1
	var j := swarms.size() - 1
	while j >= 0:
		var s := swarms[j]
		if not is_instance_valid(s):
			swarms.remove_at(j)
		elif s.global_position.distance_to(player.global_position) > DESPAWN_AT * 1.4:
			s.queue_free()
			swarms.remove_at(j)
		j -= 1


## =============================== Spawning =================================


func _zone_at(pos: Vector3) -> String:
	## Placeholder zoning until the painted map becomes data. Radial rings,
	## plus wet ground wherever the world says there is water.
	var u := clampf(pos.length() / maxf(world_radius, 1.0), 0.0, 1.0)
	for r in ZONE_RINGS:
		if u >= float(r["r0"]) and u < float(r["r1"]):
			return String(r["zone"])
	return "deep_woods"


func _ground_at(pos: Vector3) -> Vector3:
	## Drop onto whatever is under the point. Without this, everything spawns
	## at y=2 and falls, which looks exactly as bad as it sounds.
	var space := get_tree().root.world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 30.0, pos + Vector3.DOWN * 40.0)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return pos
	return (hit["position"] as Vector3) + Vector3.UP * 0.15


func _spawn_point() -> Vector3:
	## In the ring, out of sight, and not on top of the player.
	for _a in range(10):
		var ang := _rng.randf() * TAU
		var rad := _rng.randf_range(SPAWN_RING.x, SPAWN_RING.y)
		var p: Vector3 = player.global_position + Vector3(cos(ang) * rad, 0, sin(ang) * rad)
		if p.length() > world_radius * 0.98:
			continue
		## Behind the player is better than in front of them.
		if player.has_method("get"):
			var basis_z = player.global_transform.basis.z
			if basis_z is Vector3:
				var to := (p - player.global_position).normalized()
				if to.dot((basis_z as Vector3).normalized()) < -0.4 and _rng.randf() < 0.6:
					continue
		return _ground_at(p)
	return Vector3.INF


func _try_spawn() -> void:
	var at := _spawn_point()
	if at == Vector3.INF:
		return
	var zone := _zone_at(at)
	## A hillside that just went up in alarm calls does not immediately fill
	## with fresh deer.
	if _tele != null and is_instance_valid(_tele) and _tele.alarm_level_at(at) >= Telegraph.Threat.ALARM:
		return
	var key := _roll_species(zone)
	if key == "":
		return
	var n := 1
	var herd = CritterDex.flag(key, "herd", 0)
	if herd is int and int(herd) > 1:
		n = _rng.randi_range(2, int(herd))
	n = mini(n, BUDGET - live.size())
	for i in range(n):
		var off := Vector3(_rng.randf_range(-HERD_SPREAD, HERD_SPREAD), 0,
			_rng.randf_range(-HERD_SPREAD, HERD_SPREAD)) if i > 0 else Vector3.ZERO
		_place(key, _ground_at(at + off), zone)


func _roll_species(zone: String) -> String:
	var cands := CritterDex.species_for_zone(zone)
	if cands.is_empty():
		return ""
	var pool: Array = []
	var total := 0.0
	for e in cands:
		var k := String(e["key"])
		if CritterDex.rig_of(k) == "SWARM":
			continue          ## swarms are their own budget
		if not CritterDex.is_awake(k, _hour, _phase):
			continue
		if CritterDex.flag(k, "audio_only", false):
			continue
		if CritterDex.flag(k, "water", false) and not _has_water_near():
			continue
		if CritterDex.flag(k, "cliff", false) or CritterDex.flag(k, "island_only", false) \
				or CritterDex.flag(k, "far_only", false) or CritterDex.flag(k, "marine", false):
			continue          ## these need real map features; not in the blockout yet
		var w := float(e["w"])
		## Rare things are rare. This is the only knob that separates "a lynx
		## exists" from "lynxes are a nuisance".
		var rare = CritterDex.flag(k, "rare", 1.0)
		w *= float(rare) if rare is float else 1.0
		## Crepuscular animals are commonest at the edges of the day.
		if CritterDex.flag(k, "dusk", false):
			var dusk := (_hour >= 18.6 and _hour < 21.2) or (_hour >= 4.6 and _hour < 7.4)
			w *= 1.8 if dusk else 0.45
		pool.append({"key": k, "w": w})
		total += w
	if pool.is_empty() or total <= 0.0:
		return ""
	var roll := _rng.randf() * total
	for e in pool:
		roll -= float(e["w"])
		if roll <= 0.0:
			return String(e["key"])
	return String(pool[0]["key"])


func _has_water_near() -> bool:
	## The blockout has no lakes yet. When it does, point this at them; until
	## then beavers and loons are placed by the hand-seed pass below rather
	## than rolled, so they never end up grazing a dry hillside.
	return not get_tree().get_nodes_in_group("water").is_empty()


func _place(key: String, at: Vector3, zone: String) -> Critter:
	if at == Vector3.INF:
		return null
	var c := Critter.make(key)
	c._zone = zone
	get_parent().add_child(c)
	c.global_position = at
	c.rotation.y = _rng.randf() * TAU
	c.set_clock(_hour, _phase)
	live.append(c)
	return c


func spawn_one(key: String, at: Vector3) -> Critter:
	## Public: for the hand-placed pass, the tests, and the debug console.
	return _place(key, _ground_at(at), _zone_at(at))


func adopt(c: Critter) -> void:
	## Something else built this one — the M spawn menu — but it still belongs
	## to the director, so it saves with the world, shows in the census, and
	## gets the clock. It deliberately does NOT count against the spawn budget
	## on the way in: a dev spawn must never be refused because the woods are
	## already full. Natural spawning simply pauses until the count falls back.
	##
	## An adopted legend is NOT registered in legends_placed, so the legend
	## gate will not quietly delete it the moment its condition lapses. Spawn a
	## Specter Moose at noon and it stays a Specter Moose at noon.
	if c == null or not is_instance_valid(c) or live.has(c):
		return
	live.append(c)
	c.set_clock(_hour, _phase)


func adopt_swarm(s: CritterSwarm) -> void:
	if s == null or not is_instance_valid(s) or swarms.has(s):
		return
	swarms.append(s)
	s.set_visible_for(_hour, _phase)


## ================================ Swarms ==================================


func _try_swarm() -> void:
	var at := _spawn_point()
	if at == Vector3.INF:
		return
	var zone := _zone_at(at)
	var pool: Array = []
	for e in CritterDex.species_for_zone(zone):
		var k := String(e["key"])
		if CritterDex.rig_of(k) != "SWARM":
			continue
		if CritterDex.flag(k, "audio_only", false):
			continue
		if not CritterDex.is_awake(k, _hour, _phase):
			continue
		pool.append(k)
	if pool.is_empty():
		return
	var key: String = pool[_rng.randi() % pool.size()]
	for s in swarms:
		if is_instance_valid(s) and s.species == key:
			return      ## one cloud of each per neighbourhood is plenty
	var sw := CritterSwarm.make(key, at + Vector3.UP * 0.4)
	get_parent().add_child(sw)
	sw.set_visible_for(_hour, _phase)
	swarms.append(sw)


## ================================ Events ==================================


func _maybe_skein() -> void:
	## The goose skein: a V of honking crossing the whole sky, spring and
	## autumn. No meshes needed at that altitude — it is a sound moving over
	## the map, and it is the cheapest "the world is bigger than you" effect
	## in the game.
	var season := CritterDex.season_of(_phase)
	if season != CritterDex.AUTUMN and season != CritterDex.SPRING:
		return
	if _audio == null or not is_instance_valid(_audio) or player == null:
		return
	var from_ang := _rng.randf() * TAU
	var start: Vector3 = player.global_position + Vector3(cos(from_ang) * 150.0, 90.0, sin(from_ang) * 150.0)
	var end: Vector3 = player.global_position - Vector3(cos(from_ang) * 150.0, -90.0, sin(from_ang) * 150.0)
	var steps := 7
	for i in range(steps):
		var u := float(i) / float(steps - 1)
		var at := start.lerp(end, u)
		var delay := u * 14.0
		get_tree().create_timer(delay).timeout.connect(func():
			if is_instance_valid(_audio):
				_audio._play("goose_skein" if i == 0 else "goose_honk", at, -4.0))
	_notify("Geese, going over.")


func _maybe_big_night() -> void:
	## One warm rainy night in early spring, every salamander and frog in the
	## woods crosses at once, and the raccoons and coyotes have the best meal
	## of their year. It happens once. Players who have seen it tell players
	## who have not.
	var year := int(_day / (Wind.DAYS_PER_SEASON * 4.0))
	if _big_night_done == year:
		return
	var p := fposmod(_phase, 1.0)
	if p < 0.03 or p > 0.09:
		return
	if _hour < 21.0 and _hour > 4.0:
		return
	if player == null:
		return
	_big_night_done = year
	_notify("Big Night — the whole forest is crossing.")
	for _i in range(14):
		var ang := _rng.randf() * TAU
		var rad := _rng.randf_range(6.0, 30.0)
		var at: Vector3 = player.global_position + Vector3(cos(ang) * rad, 0, sin(ang) * rad)
		_place("wood_frog" if _rng.randf() < 0.6 else "red_eft", _ground_at(at), _zone_at(at))
	for _j in range(2):
		var a2 := _rng.randf() * TAU
		var at2: Vector3 = player.global_position + Vector3(cos(a2) * 24.0, 0, sin(a2) * 24.0)
		_place("raccoon", _ground_at(at2), _zone_at(at2))


func _notify(text: String) -> void:
	var w := get_tree().get_first_node_in_group("world")
	if w != null and w.has_method("_show_title"):
		w.call("_show_title", text)


## =============================== Legends ==================================


func _legend_check() -> void:
	## Legends are placed, never rolled. Each has one condition, and when it
	## is met exactly one of that legend exists in the world.
	if player == null:
		return
	var season := CritterDex.season_of(_phase)
	var night := _hour >= 20.6 or _hour < 6.0

	## The Specter Moose: fog and dusk, in the Moosehead country. Reported near
	## Lobster Lake since the 1890s — a giant pale bull nobody ever brings back
	## a body of.
	_legend_gate("specter_moose",
		(_hour > 18.6 or _hour < 6.6) and _zone_at(player.global_position) == "moosehead",
		0.06, 120.0)

	## The Ghost Cat: the cougar that "isn't in Maine any more". Never attacks.
	## Just is, at the edge of your vision, all night.
	_legend_gate("ghost_cat", night, 0.04, 90.0)

	## The Aurora Herd: caribou are gone from Maine, so here they are literally
	## ghosts, and only on the nights the sky is up.
	_legend_gate("aurora_herd", night and season == CritterDex.WINTER
		and _zone_at(player.global_position) == "county", 0.10, 100.0)

	## The King Snapper: the pond that lost a dog.
	_legend_gate("king_snapper", _has_water_near(), 0.05, 40.0)

	## The White Raven: one exists. Seeing it means something.
	_legend_gate("white_raven", true, 0.015, 70.0)


func _legend_gate(key: String, condition: bool, chance: float, at_range: float) -> void:
	var placed: Variant = legends_placed.get(key, null)
	if placed != null and is_instance_valid(placed):
		## Already out there. Retire it when the condition lapses so a specter
		## does not stand around in daylight.
		if not condition:
			(placed as Node).queue_free()
			legends_placed.erase(key)
		return
	if not condition or _rng.randf() > chance:
		return
	var ang := _rng.randf() * TAU
	var at: Vector3 = player.global_position + Vector3(cos(ang) * at_range, 0, sin(ang) * at_range)
	if at.length() > world_radius:
		return
	var n := 1
	var herd = CritterDex.flag(key, "herd", 0)
	if herd is int and int(herd) > 1:
		n = int(herd)
	var first: Critter = null
	for i in range(n):
		var off := Vector3(_rng.randf_range(-7.0, 7.0), 0, _rng.randf_range(-7.0, 7.0)) if i > 0 else Vector3.ZERO
		var c := _place(key, _ground_at(at + off), _zone_at(at))
		if c != null and first == null:
			first = c
	if first != null:
		legends_placed[key] = first


## ============================= Hand-seeding ===============================


func seed_world() -> void:
	## Called once by World after the forest exists. Puts the animals that
	## need a PLACE rather than a roll — the ones a spawn table cannot site
	## correctly on its own.
	if player == null:
		return
	## A resident chickadee flock near the camp: the first wildlife most
	## players will meet, and the one that will land on their hand.
	for _i in range(4):
		var ang := _rng.randf() * TAU
		var at: Vector3 = Vector3(cos(ang) * _rng.randf_range(9.0, 18.0), 0, sin(ang) * _rng.randf_range(9.0, 18.0))
		_place("chickadee", _ground_at(at + Vector3.UP * 2.4), "deep_woods")
	## A red squirrel in the near timber, so the player learns immediately that
	## the forest talks about them.
	for _j in range(2):
		var a2 := _rng.randf() * TAU
		var p2 := Vector3(cos(a2) * _rng.randf_range(14.0, 26.0), 0, sin(a2) * _rng.randf_range(14.0, 26.0))
		_place("red_squirrel", _ground_at(p2), "deep_woods")
	## And one deer out at the tree line, because the first thing you should
	## see moving in these woods is something that runs.
	var a3 := _rng.randf() * TAU
	_place("whitetail", _ground_at(Vector3(cos(a3) * 42.0, 0, sin(a3) * 42.0)), "deep_woods")


## ============================== Save / load ===============================


func save_state() -> Dictionary:
	var out: Array = []
	for c in live:
		if is_instance_valid(c) and not c.dying:
			out.append(c.save_dict())
	return {
		"critters": out,
		"big_night": _big_night_done,
		"legends": legends_placed.keys(),
	}


func apply_state(d: Dictionary) -> void:
	for c in live:
		if is_instance_valid(c):
			c.queue_free()
	live.clear()
	legends_placed.clear()
	_big_night_done = int(d.get("big_night", -1))
	for cd in d.get("critters", []):
		var dict := cd as Dictionary
		var c := Critter.from_dict(dict)
		get_parent().add_child(c)
		c.global_position = dict.get("pos", Vector3.ZERO)
		c.rotation.y = float(dict.get("rot_y", 0.0))
		c.set_clock(_hour, _phase)
		live.append(c)
		if c.legend:
			legends_placed[c.species] = c


## ============================== Diagnostics ===============================


func census() -> Dictionary:
	var by_species: Dictionary = {}
	for c in live:
		if is_instance_valid(c):
			by_species[c.species] = int(by_species.get(c.species, 0)) + 1
	return {
		"live": live.size(), "budget": BUDGET, "swarms": swarms.size(),
		"zone": _zone_at(player.global_position) if player != null else "?",
		"hour": _hour, "season": ["Spring", "Summer", "Autumn", "Winter"][CritterDex.season_of(_phase)],
		"by_species": by_species,
	}
