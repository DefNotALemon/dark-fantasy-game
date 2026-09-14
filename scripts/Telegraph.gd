class_name Telegraph
extends Node

## ===========================================================================
## THE FOREST TELEGRAPH — one alarm bus for every wild thing.
##                                                     docs/WILDLIFE.md §1
##
## A jay screams. A red squirrel scolds you down the whole length of its
## territory. A deer blows and every deer on the hillside is gone before you
## saw the first one. That is not decoration — it is a SYSTEM, and this is it.
##
## Three things happen on every alarm:
##   1. prey inside the radius goes ALERT, and flees if the threat is close
##   2. other SENTINELs inside the radius RELAY it — a shrinking echo, so
##      one squirrel can carry the word two hundred metres and no further
##   3. predators inside the radius reprioritise: something is running
##      nearby, and running things are food
##
## And the fourth thing, the one that makes it worth building: the PLAYER can
## read it. A jay going off over the next rise means something is moving over
## there. In a world with goblins in the treeline, the forest rats them out
## too — if you have learned to listen. Free counter-intelligence, paid for in
## attention.
##
## Wired up by World.gd:  add_child(Telegraph.new())
## Anything can ring it:  Telegraph.ring(pos, radius, threat, source)
## ===========================================================================

## Threat levels. The chickadee literally encodes threat size in the number of
## dee notes it appends — that is real, and it is the tutorial for this whole
## system, so the scale is named after it.
enum Threat { CURIOUS = 0, WARY = 1, ALARM = 2, PANIC = 3 }

const RELAY_FALLOFF := 0.62      ## each relay hop keeps this much radius
const RELAY_MIN_RADIUS := 8.0    ## below this the word stops travelling
const RELAY_DELAY := Vector2(0.18, 0.55)  ## a beat before the next voice picks it up
const MAX_HOPS := 4
const ALERT_SECONDS := 9.0       ## how long a spooked animal stays wound up
const PLAYER_HEAR := 55.0        ## the player is told about alarms this close

## How far the player's own noise carries, from a careful walk to a sprint.
## These were literals inside player_noise() until the weather started reading
## them; they are named now so that WeatherwiseTests can ask its question --
## "at which sky does a sprint stop reaching a deer?" -- without either file
## restating the other's number.
const NOISE_NEAR := 10.0
const NOISE_FAR := 34.0

static var _instance: Telegraph = null

## Live alarms, for anything that wants to query rather than be pushed to:
## {pos, radius, threat, t, source_name}
var recent: Array[Dictionary] = []

## The player's own noise. Crashing through brush IS an alarm — the forest
## empties ahead of a careless walker, and that is the stealth mechanic.
var _player_noise_t := 0.0

## The sky, as WildlifeDirector hands it over every tick. Empty means "no
## weather", which Weatherwise reads as a clear day — so a Telegraph that
## nobody tells about the weather behaves exactly as this bus always has, and
## every suite written before today is untouched.
var weather: Dictionary = {}

signal alarmed(pos: Vector3, radius: float, threat: int, source_name: String)


func _ready() -> void:
	_instance = self
	add_to_group("telegraph")


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


static func get_bus(from: Node) -> Telegraph:
	## Never assume the bus exists — headless tests and the old world build
	## without one, and a missing telegraph must be a no-op, not a crash.
	if _instance != null and is_instance_valid(_instance):
		return _instance
	if from != null and from.is_inside_tree():
		var n := from.get_tree().get_first_node_in_group("telegraph")
		if n is Telegraph:
			_instance = n as Telegraph
			return _instance
	return null


## ================================ Ringing =================================


static func ring(from: Node, pos: Vector3, radius: float, threat: int,
		source_name := "", hops := 0) -> void:
	var bus := get_bus(from)
	if bus == null:
		return
	bus._ring(pos, radius, threat, source_name, hops)


func _ring(pos: Vector3, radius: float, threat: int, source_name: String, hops: int) -> void:
	recent.append({
		"pos": pos, "radius": radius, "threat": threat,
		"t": ALERT_SECONDS, "src": source_name, "hops": hops,
	})
	if recent.size() > 24:
		recent.pop_front()
	alarmed.emit(pos, radius, threat, source_name)

	var r2 := radius * radius
	var relays: Array = []
	for n in get_tree().get_nodes_in_group("critters"):
		var c := n as Node3D
		if c == null or not is_instance_valid(c):
			continue
		var d2 := c.global_position.distance_squared_to(pos)
		if d2 > r2:
			continue
		if c.has_method("hear_alarm"):
			c.call("hear_alarm", pos, threat, source_name)
		## Only a SENTINEL passes the word on, and only if it isn't the one
		## who started it — otherwise one squirrel rings forever.
		if hops < MAX_HOPS and radius > RELAY_MIN_RADIUS \
				and c.has_method("is_sentinel") and bool(c.call("is_sentinel")) \
				and c.get("_alarm_cool") != null and float(c.get("_alarm_cool")) <= 0.0 \
				and d2 > 4.0:
			relays.append(c)

	## Relay through the ONE nearest sentinel outside the middle of the ring,
	## not all of them — the word should travel, not detonate.
	if not relays.is_empty():
		relays.sort_custom(func(a, b):
			return a.global_position.distance_squared_to(pos) > b.global_position.distance_squared_to(pos))
		var carrier: Node3D = relays[0]
		var delay := randf_range(RELAY_DELAY.x, RELAY_DELAY.y)
		var cp: Vector3 = carrier.global_position
		## [weather] ...and the forest cannot hear either. The same rain that
		## hides a running man shortens every hop of the alarm chain, so the
		## word stops travelling: a 34 m alarm carries the full four hops this
		## bus allows on a clear day and exactly two in a storm.
		## Rain buys you stealth and takes away your intelligence.
		var next_r := radius * RELAY_FALLOFF * Weatherwise.relay_mult(weather)
		if carrier.has_method("relay_alarm"):
			carrier.call("relay_alarm", delay)
		get_tree().create_timer(delay).timeout.connect(
			func():
				if is_instance_valid(self):
					_ring(cp, next_r, maxi(threat - 1, Threat.WARY), source_name, hops + 1))

	## Predators hear opportunity, not danger.
	for n in get_tree().get_nodes_in_group("critter_predators"):
		var pd := n as Node3D
		if pd == null or not is_instance_valid(pd):
			continue
		if pd.global_position.distance_squared_to(pos) <= r2 * 2.25 and pd.has_method("hear_prey"):
			pd.call("hear_prey", pos)


## ============================== The player ================================


func player_noise(pos: Vector3, loudness: float) -> void:
	## Called by World every so often with how hard the player is moving.
	## Sprinting through brush is a broadcast; a crouched walk is not.
	_player_noise_t -= get_process_delta_time()
	if loudness < 0.35 or _player_noise_t > 0.0:
		return
	_player_noise_t = lerpf(1.4, 0.5, clampf(loudness, 0.0, 1.0))
	## [weather] RAIN IS LOUD, AND THAT IS THE POINT. A sprint rings at
	## NOISE_FAR on a clear day, which is just outside a whitetail's notice
	## radius; from drizzle onward it no longer reaches one, so you can run in
	## wet woods without emptying them ahead of you. The price is paid in the
	## same coin two functions down, where the relay is cut by the same rain.
	var heard_r := lerpf(NOISE_NEAR, NOISE_FAR, clampf(loudness, 0.0, 1.0))
	heard_r *= Weatherwise.noise_mult(weather)
	_ring(pos, heard_r, Threat.WARY if loudness < 0.7 else Threat.ALARM, "you", 1)


func heard_by_player(player_pos: Vector3) -> Array[Dictionary]:
	## What the player could plausibly have HEARD in the last few seconds,
	## nearest first. The HUD tell reads off this.
	var out: Array[Dictionary] = []
	for a in recent:
		var d: float = player_pos.distance_to(a["pos"] as Vector3)
		if d <= PLAYER_HEAR and String(a["src"]) != "you":
			var e := (a as Dictionary).duplicate()
			e["dist"] = d
			out.append(e)
	out.sort_custom(func(x, y): return float(x["dist"]) < float(y["dist"]))
	return out


func read_the_woods(player_pos: Vector3) -> String:
	## The line the HUD shows when the forest is trying to tell you something.
	## Deliberately vague about WHAT — learning to read it is the skill.
	var heard := heard_by_player(player_pos)
	if heard.is_empty():
		return ""
	var a := heard[0]
	var d := float(a["dist"])
	var where := "close by" if d < 18.0 else ("nearby" if d < 34.0 else "somewhere off")
	match int(a["threat"]):
		Threat.PANIC:
			return "Something put the woods up, %s." % where
		Threat.ALARM:
			return "%s — alarm calls %s." % [String(a["src"]).capitalize(), where]
		_:
			return "The birds have gone quiet %s." % where


## ============================== Bookkeeping ===============================


func _process(delta: float) -> void:
	var i := recent.size() - 1
	while i >= 0:
		recent[i]["t"] = float(recent[i]["t"]) - delta
		if float(recent[i]["t"]) <= 0.0:
			recent.remove_at(i)
		i -= 1


func alarm_level_at(pos: Vector3) -> int:
	## How wound up is this patch of woods right now? Spawning and predator
	## behaviour both read it — you do not walk into a hillside that just
	## emptied and find it full of deer.
	var worst := -1
	for a in recent:
		if pos.distance_to(a["pos"] as Vector3) <= float(a["radius"]):
			worst = maxi(worst, int(a["threat"]))
	return worst
