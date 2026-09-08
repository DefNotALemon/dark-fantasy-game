class_name IncidentDirector
extends Node

## ===========================================================================
## THE INCIDENT DIRECTOR — the place where the Chronicle stops being a rumour.
##
## Chronicle.gd simulates fifty places off-screen and refuses, on purpose, to
## touch the scene. That refusal is what keeps it cheap and deterministic, and
## it is also what makes it invisible: a wolf pack took three ewes at Sebec
## last night, the tavern board says so, and the fold itself is an untouched
## square of grass. The news arrives and the world does not.
##
## This file is the other half. It reads the Chronicle on two channels —
## `events_near()` for what is still HAPPENING, `resolved` for what has just
## FINISHED happening — and turns whichever of them are near the player into
## props you can walk up to: the torn hurdle, the blood trail, the crows that
## lift off it when you get close. Nothing else in the game gets to invent an
## incident. If it is physical, the Chronicle said so first.
##
## FIVE RULES this file will not break:
##
##   1. **The record is the incident; the nodes are not.** Every incident is a
##      Dictionary in `incidents`, keyed on the Chronicle's `uid`, which is
##      unique, never reused, and stable across a save. Freeing the meshes is
##      a rendering decision. It does not delete anything. Walk away, come
##      back, and you meet the SAME incident again, not a second one.
##   2. **It is deterministic.** No RandomNumberGenerator, no randf, no randi,
##      anywhere in here — same rule as the Chronicle, for the same reason.
##      Every bearing, distance, jitter and yaw is a hash of
##      (world_seed, uid, salt), so restaging a uid a hundred times puts the
##      same barrel on the same tuft of grass a hundred times. The statics at
##      the bottom are this file's OWN mixer with its own constants: the
##      Chronicle's are private to the Chronicle, and two systems sharing a
##      hash by reaching into each other is how a tuning change over there
##      silently moves every prop over here.
##   3. **Earshot, never a marker.** You find out an incident is there by
##      hearing it — a Telegraph ring, crows going up, dogs. There is no HUD
##      pip and no raycast. The latch is once per incident, EVER: across a
##      teardown, across a rebuild, across a save. The world does not tell you
##      the same thing twice.
##   4. **Everything is optional.** `chronicle`, `player`, Telegraph, the
##      ground provider and the WildlifeDirector are all nullable and all
##      absent in the headless suite. With none of them `scan()` still runs
##      and still does the full record bookkeeping — which is exactly what
##      makes the lifecycle testable without a renderer.
##   5. **It never touches the Player.** World.gd integration is additive.
##
## Wired up by World.gd (tools/patch_incidents.py):
##     _incidents = IncidentDirector.new()
##     add_child(_incidents); _incidents.bind_world(self)
## ===========================================================================

signal incident_staged(rec: Dictionary)
signal incident_struck(rec: Dictionary)    ## nodes torn down, record kept
## Re-dressed in place: the incident was already physical and STAYS physical,
## but the props under it were rebuilt because the event resolved while the
## player was standing in it. Deliberately NOT `incident_staged`: staged and
## struck are a matched pair, one each per uid per visit, and a listener that
## counts them (an audio emitter pool, a save-dirty flag) has every right to
## assume so. A second `staged` with no `struck` between them is a leak.
signal incident_redressed(rec: Dictionary)
signal incident_spent(rec: Dictionary)     ## aged out, will never stage again
signal incident_heard(rec: Dictionary)     ## player came into earshot, first time only

## ============================== The dials =================================

## Where an incident becomes physical. 220 m is a little past the far edge of
## the tree impostor band, so a staged incident fades up with the trees around
## it rather than popping into an already-drawn hillside.
const STAGE_RADIUS := 220.0
## Where it is torn down again. This MUST be larger than STAGE_RADIUS, and the
## gap is the whole point.
##
## With one radius, a player standing ON the boundary — which is to say every
## player who stops to look at the thing that is 220 m away — crosses it back
## and forth by centimetres of walk-bob and head-turn, and every crossing is a
## full teardown and rebuild of a dozen meshes and materials. That is a hitch
## per frame, forever, and it is the single most common way a streaming system
## gets shipped broken. With 220 in and 300 out, an incident that has been
## built must be walked 80 m away from before it comes down, and 80 m back
## before it goes up again: at a sprint that is several seconds, and SCAN
## happens every 1.7 s, so the boundary cannot be crossed twice inside one
## scan at any speed a person moves. The two radii also never overlap in
## meaning — nothing is both "far enough to build" and "far enough to strike"
## — so the stage pass and the strike pass touch disjoint sets and their order
## cannot matter.
const STRIKE_RADIUS := 300.0
## How close before the world tells you. Deliberately shorter than the staging
## radius: the props are built long before you are allowed to notice them, so
## the crows go up because you walked into them, not because a chunk loaded.
const EARSHOT := 60.0
## The Director's hard ceiling on memory, in game days. Aftermath older than
## this is spent whatever its recipe says — three days is long enough that a
## night's walk back to the fold still finds the blood, short enough that the
## woods are not a museum of everything that ever happened in them.
const MEMORY_DAYS := 3.0
## Wall-clock seconds between scans. Not a frame count: the scan is O(records)
## and the records are counted in dozens, so ~35 of these a minute is free,
## and 1.7 is prime-ish enough not to beat against the other second-ish timers
## in World (grass trample, chunk streaming) every single time.
const SCAN_SECONDS := 1.7
## The most incidents that may be physical at once. Twelve x a dozen props is
## already 150-odd extra nodes on top of the trees; past that the answer is a
## better incident, not more of them.
const MAX_STAGED := 12
## The most incidents that may be BUILT in a single scan. Building is the one
## genuinely expensive thing this file does — a full MAX_STAGED cohort measures
## 22 ms headless, which is a guaranteed dropped frame — and there is exactly
## one moment when a whole cohort is wanted at once: a fast travel, a respawn,
## a save load. Three a scan spreads that over ~5 s of wall clock, which fits
## inside the 80 m hysteresis gap at any speed a person moves, so nothing that
## was going to be built is ever struck before it gets its turn.
const STAGE_PER_SCAN := 3

## A small SEPARATE allowance that only a record already inside EARSHOT may
## spend. Earshot is the one discovery channel this system has and it only
## fires on a staged record, so a strict build budget means the world can stay
## silent about a thing the player is standing next to for three scans while
## they walk past it -- ten aftermaths at one place measured at five seconds.
## An unbounded exemption is not the answer either: a cluster that is ALL
## inside earshot is then the whole cohort in one frame, which is the 22 ms
## this budget exists to prevent. Two, so the worst scan is five builds.
## (2026-09-07)
const EARSHOT_GRACE := 2
## The y the ground probe vector carries. World's heightfield sampler answers
## from (x, z) alone and ignores it, so today this number changes nothing; it
## is here because a provider that answers by raycasting DOWN needs a start
## height above the tallest place on the bake (Jackman sits at 367 m), and a
## probe that starts at zero would begin inside every hill on the map.
const GROUND_PROBE := 400.0

## `events_near` is asked for a wider ring than STAGE_RADIUS so that an
## incident is a RECORD — known, aged, saved — for a while before it is ever
## physical. Without the margin, the first scan that could stage something is
## also the first scan that has heard of it, and an incident would blink into
## existence at exactly 220 m every time.
const HARVEST_MULT := 1.6
## Anchor bands, in metres from the event's place. `place` incidents happen at
## the edge of the settlement — the fold, the mill, the tithe barn — not in
## the middle of the square; `wild` ones are out where you would have to be
## walking to find them.
const PLACE_NEAR := 18.0
const PLACE_FAR := 34.0
const WILD_NEAR := 60.0
const WILD_FAR := 140.0
## How much of a road segment is usable. The middle 60% — an incident on a
## road belongs on the road, not in the first house at either end of it.
const ROAD_MID := 0.6
## A ceiling on props per incident, so one over-enthusiastic recipe cannot
## put four hundred boxes on a hillside.
const MAX_PROPS := 48
## The `shore` walk. Sixteen bearings, 8 m a step, and a hard stop at 160 m so
## a place that is nowhere near water cannot turn one anchor into an unbounded
## sweep of the heightfield. The 6 m back-off is what keeps the net and the
## floats on the beach rather than under it.
const SHORE_STEP := 8.0
const SHORE_REACH := 160.0
const SHORE_BACK := 6.0

## What counts as water when the shore walk is looking for it. NOT 0.0:
## `World._surface_y` returns exactly 0.0 for every sample when the terrain is
## switched off, and `World._world_home` documents the valley floor as the one
## place guaranteed to have ground at y = 0 -- so a `<= 0.0` test called the
## whole world water and parked every wreck two metres from the village.
const WATER_Y := -0.25
## How long a SPENT record is kept before the Director forgets it entirely.
## It has to outlive the Chronicle's 64-deep resolved ring by a wide margin:
## forget a uid that is still in the ring and the next scan harvests it back
## as brand new and stages the same aftermath a second time. Thirty game days
## is roughly ten times the deepest that ring ever reaches.
const FORGET_DAYS := 30.0

## Salts. New behaviour gets a NEW salt; never re-use one to get "another"
## number, or the two rolls correlate and every incident in the world starts
## leaning the same way.
const SALT_ANCHOR := 4801
const SALT_ROAD := 5011
const SALT_PROP := 6199

## ============================== The state =================================

var chronicle: Chronicle = null
var player: Node3D = null
## Only ever read for `day` + `hour`, and only when there is no Chronicle to
## ask. See `_now_days()` for why the Chronicle wins when both exist.
var clock: Node = null
var world_seed := 20260907
var enabled := true

## uid:int -> record. THE state of this file. See the header: this survives
## chunk unload, save/load and the player walking to the other end of Maine.
##
##   {uid:int, kind:String, outcome:String, place:String, pos:Vector2,
##    born:float, resolved_at:float, live:bool, state:String, staged_at:float,
##    heard:bool, anchor:Vector3, props:int}
##
## `state` is "known" (recorded, not physical), "staged" (nodes exist) or
## "spent" (aged out, never stages again). Nothing else is ever written to it.
##
## `born` is when the EVENT fired and `resolved_at` is when it ENDED, and they
## are two different clocks on purpose. `linger` is "days the AFTERMATH is
## worth walking up to", so it can only ever be measured from the ending: a
## bridge is out for ten days and a mill is broken for seven, and ageing their
## wreckage against the day the thing STARTED spends it before it exists.
## `resolved_at` is -1.0 while the event is still live.
var incidents: Dictionary = {}

## uid:int -> Node3D. Deliberately NOT part of the record and deliberately not
## saved: these are the disposable half.
var _nodes: Dictionary = {}
## uid:int -> Array of critters we asked the WildlifeDirector for, so a strike
## takes its own animals down with it.
var _critters: Dictionary = {}

var _ground: Object = null      ## anything with _surface_y(Vector3) -> float
var _wildlife: Node = null      ## anything with spawn_one(String, Vector3)
var _scan_t := 0.0
var _last_days := 0.0
## kind_id -> the four numbers this file actually reads off a recipe.
## `IncidentKit.recipe_for` hands back a DEEP COPY of the whole recipe — every
## prop spec, every outcome's dressing — and at 24 us a call the ageing and
## earshot passes alone were spending 2+ ms every scan duplicating dictionaries
## for incidents a hundred kilometres away. The catalogue is a `const`; it
## cannot change under us; so it is read once per kind and remembered.
var _kind_cache: Dictionary = {}
## uid -> Vector2, the far end of the road segment, snapshotted the first time
## it is worked out. See `_road_point`: `chronicle.places` is MUTABLE (the fort
## builder appends to it, and `Chronicle.from_dict` overlays a save's roster on
## top of the live one) and "the nearest other place" is not a stable answer
## across such a change. Measured, a road anchor moved 748 m when a place was
## appended. The snapshot is what makes `anchor_for` honestly repeatable for
## the life of a Director.
var _road_ends: Dictionary = {}

## The scan's remaining build allowance, shared by the staging pass and the
## re-dressing pass. It was on staging alone at first, which left the whole
## point of it open: `Chronicle._resolve_due` resolves EVERY event past its
## ending in one tick, so a dozen incidents can re-dress in a single scan --
## measured at 23 ms, the exact dropped frame `STAGE_PER_SCAN` exists to
## prevent. One budget, both doors. (2026-09-07)
var _build_left := 0

## The earshot allowance, reset with `_build_left` and spendable only by a
## record that is already within EARSHOT of the player.
var _grace_left := 0

## Staged incidents whose dressing is out of date and whose rebuild did not
## fit in this scan's budget. Director state, deliberately NOT a record key:
## it is transient, it must never reach `to_dict`, and the record shape is a
## contract the suite asserts on.
var _redress_q: Dictionary = {}
## The last note the world said out loud, for a HUD that wants to print it.
## Kept off the record on purpose: the record shape is a contract.
var last_note := ""


## ============================== Wiring up =================================


func bind_world(w: Node) -> void:
	## Duck-typed on every single hook, because this same class has to come up
	## inside the full game, inside a stripped test project with three scripts
	## in it, and inside whatever World looks like six months from now. A hard
	## reference to World.gd would be a parse error in two of those three.
	if w == null or not is_instance_valid(w):
		return
	if w.has_method("chronicle"):
		var c: Variant = w.call("chronicle")
		if c is Chronicle:
			chronicle = c as Chronicle
	if chronicle == null:
		## The group lookup is the same contract Telegraph.get_bus uses:
		## never assume, never crash, null is a legal answer.
		chronicle = Chronicle.get_bus(self)
	var p: Variant = w.get("_player")
	if p is Node3D:
		player = p as Node3D
	## The heightfield, through World's own accessor rather than the terrain
	## node: World already knows what to do when the terrain is off.
	if w.has_method("_surface_y") or w.has_method("surface_y"):
		_ground = w
	var wl: Variant = w.get("_wildlife")
	if wl is Node:
		_wildlife = wl as Node
	var dn: Variant = w.get("_daynight")
	if dn is Node:
		clock = dn as Node


func _process(delta: float) -> void:
	## Interval -> scan(). Nothing else lives in here on purpose: everything
	## the Director does is in `scan()`, which takes a day number and needs no
	## frame, no delta and no tree, which is what makes the whole lifecycle
	## testable in a headless suite.
	if not enabled:
		return
	_scan_t -= delta
	if _scan_t > 0.0:
		return
	_scan_t = SCAN_SECONDS
	scan(_now_days())


func _now_days() -> float:
	## The Chronicle's clock wins whenever there is a Chronicle, and it is not
	## a close call: every `born` the Director ages against is a reading of
	## THAT clock. Ageing an event born on Chronicle day 12 against a sky that
	## says day 30 spends the whole world on the first scan. The sky is only
	## consulted for a Director running without a Chronicle at all, and the
	## last day we were handed is the floor under both.
	##
	## The floor is `maxf`, and it is not decoration. `World.sleep_at_bed` winds
	## the sky backwards — sleeping to dawn from 20:00 is a SIXTEEN HOUR step
	## back down the hour hand — and a day number that goes backwards un-ages
	## every record in the world: an aftermath that was one hour from spent is
	## suddenly two thirds of a day from it, and a `staged_at` in the future is
	## a number nothing downstream can reason about. Time in here only ever
	## goes forward.
	##
	## FAILURE MODE, named because it is silent: `Chronicle.days` only advances
	## if something is driving `Chronicle._process`, which means `Chronicle.bind`
	## must have been handed the day/night node. Bind it and forget, and
	## `chronicle.days` sits at 0.0 forever — every scan reads day zero, nothing
	## ever ages, nothing is ever spent, and there is no error to see. The clock
	## fallback below is the safety net: with no Chronicle clock moving, a bound
	## sky still carries the world forward.
	if chronicle != null and is_instance_valid(chronicle):
		var cd := float(chronicle.days)
		if cd <= 0.0 and clock != null and is_instance_valid(clock) \
				and "day" in clock and "hour" in clock:
			## A Chronicle that has never been advanced is not a clock.
			return maxf(float(clock.day) + float(clock.hour) / 24.0, _last_days)
		return maxf(cd, _last_days)
	if clock != null and is_instance_valid(clock) and "day" in clock and "hour" in clock:
		return maxf(float(clock.day) + float(clock.hour) / 24.0, _last_days)
	return _last_days


## =============================== The scan =================================


func scan(now_days: float) -> void:
	## THE TESTABLE CORE, and the only thing that ever changes a record.
	##
	## Order is: harvest, age, strike, stage, earshot. The build contract
	## lists staging before striking; it is done the other way round here
	## because a strike RELEASES budget. Walking a straight line past a dozen
	## incidents, the twelve behind you are outside STRIKE_RADIUS and the
	## twelve ahead are inside STAGE_RADIUS, and staging first means the cap
	## is still held by the ones you have already left — the world in front of
	## you stays empty for a whole extra scan every time. The two passes touch
	## disjoint sets (STRIKE_RADIUS > STAGE_RADIUS, so nothing is both near
	## enough to build and far enough to tear down), so nothing else about the
	## outcome depends on which runs first.
	##
	## `_stage_near` strikes too, for a different reason: `_strike_far` takes
	## down what has gone OUT OF RANGE, and the stage pass takes down what has
	## been out-competed for a slot by something nearer. The first is geometry,
	## the second is the budget, and keeping them apart is what lets the budget
	## be decided nearest-first over the whole set rather than first-come.
	if not enabled:
		return
	_last_days = now_days
	var here := _player_flat()
	## Built ONCE and handed to both passes that need it. "Which uids is the
	## Chronicle still running?" is the same question in `_age` (do not spend an
	## event that is still happening) and in `_forget` (do not drop a uid the
	## next harvest would read back), and asking it twice a scan means walking
	## the active list twice to build two identical dictionaries.
	var running := _active_uids()
	_build_left = STAGE_PER_SCAN
	_grace_left = EARSHOT_GRACE
	_harvest(now_days)
	_age(now_days, running)
	_reconcile()
	_redress(now_days)
	_strike_far(here)
	_stage_near(here, now_days)
	_earshot(here)
	_forget(now_days, running)
	## The anchor sweep in `_harvest` asks `anchor_for` about events it has NOT
	## recorded — that is the whole point of it — and a road anchor memoises its
	## far end when asked. Those entries have no record to be dropped with, so
	## they are swept up here rather than accumulating one Vector2 per road
	## event the player never got near, for the length of a playthrough.
	if _road_ends.size() > incidents.size() + 64:
		var keep := {}
		for uid in _road_ends:
			if incidents.has(uid):
				keep[uid] = _road_ends[uid]
		_road_ends = keep


func _active_uids() -> Dictionary:
	## uid -> true for everything the Chronicle currently has RUNNING. Not the
	## resolved ring: an event in there has finished, and finished is exactly
	## what the ageing pass is allowed to act on.
	var out := {}
	if chronicle == null or not is_instance_valid(chronicle):
		return out
	for e in chronicle.active:
		if e is Dictionary:
			out[int((e as Dictionary).get("uid", 0))] = true
	return out


func _player_flat() -> Vector2:
	## Flat, always. The map is a hundred kilometres across and four hundred
	## metres tall; height is noise at these radii, and it is also the one
	## number a headless test does not have.
	if player != null and is_instance_valid(player):
		## `global_position` is only legal inside a tree, and the headless
		## suite builds its whole world from SceneTree._init(), where nothing
		## has entered one yet — asking anyway is an engine error per scan and
		## a Transform3D() of zeroes for an answer. Outside a tree the local
		## position IS the global one, so read that instead.
		var p := player.global_position if player.is_inside_tree() else player.position
		return Vector2(p.x, p.z)
	return Vector2.ZERO


## 1. Harvest ---------------------------------------------------------------


func _harvest(now_days: float) -> void:
	## Both channels, in the same pass, through the same door. `_ingest` is
	## the ONLY function that may add a key to `incidents`, which is how the
	## "never a second record for a uid" rule is enforced structurally rather
	## than by everybody remembering it.
	if chronicle == null or not is_instance_valid(chronicle):
		return
	var here := _player_flat()
	var probe := Vector3(here.x, 0.0, here.y)
	var reach := STAGE_RADIUS * HARVEST_MULT
	var took := {}
	for e in chronicle.events_near(probe, reach):
		if e is Dictionary:
			took[int((e as Dictionary).get("uid", 0))] = true
			_ingest(e as Dictionary, true, now_days)
	## THE SECOND SWEEP, and it is not an optimisation — it is the live channel.
	##
	## `events_near` filters on the event's `pos`, which is the PLACE. Staging
	## is judged on the ANCHOR, which is somewhere else: a `wild` anchor is up
	## to WILD_FAR (140 m) out, and a `road` anchor is halfway to the nearest
	## other village — measured, 941 m from its own place at Jackman. So an
	## incident can be thirty metres in front of the player's boots with its
	## place four hundred metres behind the harvest ring, and the ring pass will
	## never hear of it. That is not a rare corner: it is roughly half the time
	## you are on a road, for all seven road kinds.
	##
	## The exact fix is to stop filtering by proxy and ask the anchor directly.
	## `Chronicle.MAX_ACTIVE` is 18, so the whole active list is eighteen
	## dictionaries; sweeping it costs less than the ring query it backstops.
	## Uids the first pass already took are skipped, so nothing is ingested
	## twice and the anchor of a record we already hold is never recomputed.
	for e in chronicle.active:
		if not (e is Dictionary):
			continue
		var ev := e as Dictionary
		var uid := int(ev.get("uid", 0))
		if uid <= 0 or took.has(uid) or incidents.has(uid):
			continue
		took[uid] = true
		## Cheap gate FIRST. `anchor_for` is not free for every scope: the
		## shore walk is up to sixteen bearings by twenty steps of ground
		## sampling, and this sweep runs on every scan for the whole life of
		## an event the player may never go near. A place/wild/shore anchor
		## is displaced from its place by a bounded amount, so an event whose
		## PLACE is further than the reach plus that bound cannot possibly
		## have an anchor inside the reach, and does not need computing. A
		## `road` anchor has no such bound -- it was measured 941 m out -- so
		## road is deliberately not gated here; `_road_ends` memoises it
		## instead. (2026-09-07)
		var slack := _scope_slack(String(ev.get("kind", "")))
		if slack >= 0.0 and _as_vec2(ev.get("pos", Vector2.ZERO)).distance_to(here) > reach + slack:
			continue
		## A record that does not exist yet has no stored anchor, so this is
		## the one place the anchor is computed speculatively. It is the same
		## pure function `_ingest` will call a line later for the same uid.
		var a := anchor_for({
			"uid": uid,
			"kind": String(ev.get("kind", "")),
			"pos": _as_vec2(ev.get("pos", Vector2.ZERO)),
		})
		if Vector2(a.x, a.z).distance_to(here) > reach:
			continue
		_ingest(ev, true, now_days)
	## The resolved ring is read WHOLE, with no distance filter. It has to be:
	## an event can fire in front of you, be recorded live, and resolve twenty
	## minutes later while you are two valleys away, and if the aftermath pass
	## skipped it for being far the record would sit "live" forever with an
	## empty outcome. Sixty-four dictionaries is nothing; correctness is not.
	for e in chronicle.resolved:
		if e is Dictionary:
			_ingest(e as Dictionary, false, now_days)


func _ingest(ev: Dictionary, live: bool, now_days: float) -> void:
	var uid := int(ev.get("uid", 0))
	if uid <= 0:
		return
	if not incidents.has(uid):
		## A kind with no recipe is a kind the Kit has nothing to show for. It
		## still happened — the Chronicle knows, the tavern board knows — it
		## just never becomes physical, and a record for it would be a record
		## that can never leave "known".
		##
		## This is asked ONLY on the path that could create a record. It used
		## to be the first thing in the function, which meant every scan asked
		## the catalogue about every uid it already held — ~132 lookups a scan,
		## each one a deep copy of a whole recipe — to answer a question whose
		## answer was already sitting in `incidents`.
		var kind := String(ev.get("kind", ""))
		if not bool(_kind_meta(kind).get("ok", false)):
			return
		var rec := {
			"uid": uid,
			"kind": kind,
			"outcome": String(ev.get("outcome", "")),
			"place": String(ev.get("place", "")),
			"pos": _as_vec2(ev.get("pos", Vector2.ZERO)),
			"born": float(ev.get("born", now_days)),
			## Live events have not ended, so they have no aftermath clock yet.
			## One harvested from the resolved ring HAS ended, and it ended when
			## the Chronicle said it did — `ends` — not when we happened to walk
			## past it. That distinction is the whole of the fix: a save loaded
			## next to a ring full of week-old resolutions must read them as
			## week-old, not as fresh blood on the grass.
			"resolved_at": -1.0 if live else _ended_at(ev, now_days),
			"live": live,
			"state": "known",
			"staged_at": -1.0,
			"heard": false,
			"anchor": Vector3.ZERO,
			"props": 0,
		}
		rec["anchor"] = anchor_for(rec)
		incidents[uid] = rec
		return

	var r: Dictionary = incidents[uid]
	## Spent is terminal. An event still sitting in the resolved ring long
	## after its aftermath aged out must not be harvested back to life — that
	## is the loop that would restage the same blood trail every scan for the
	## rest of the game.
	if String(r.get("state", "known")) == "spent":
		return
	if not bool(r.get("live", false)) or live:
		return
	## THE TRANSITION. The event we were showing as live has resolved: the
	## same incident, now with an ending. One record, updated in place — never
	## a second one, and never a new uid.
	r["live"] = false
	r["outcome"] = String(ev.get("outcome", ""))
	r["born"] = float(ev.get("born", r.get("born", now_days)))
	## THE AFTERMATH CLOCK, stamped here and nowhere else. `linger` counts from
	## this instant, not from `born`: four kinds in the catalogue are always
	## born-spent if you count from the firing (`bridge_out` runs ten days,
	## `deer_yard` four) and fifteen more can be, which is a third of the
	## catalogue whose aftermath no player would ever have seen.
	r["resolved_at"] = _ended_at(ev, now_days)
	## The same place it always was: an event does not move house on resolving.
	r["pos"] = _as_vec2(ev.get("pos", r.get("pos", Vector2.ZERO)))
	## The anchor is NOT recomputed, and that is a change. Every input to it is
	## the same — seed, uid, scope, pos — so recomputing SHOULD be a no-op, and
	## the only way it can fail to be one is if the world moved underneath it:
	## `_road_point` reads the mutable place roster. An incident that jumps
	## several hundred metres at the instant it resolves is a worse bug than the
	## staleness the recompute was guarding against. It is set once, at ingest.
	##
	## If it was physical, it is still physical — but the props are the wrong
	## ones now. The caravan you were walking towards is a burnt cart. That is a
	## RE-DRESSING, not a second staging: see `incident_redressed`.
	if String(r.get("state", "known")) == "staged":
		if _build_left > 0:
			_build_left -= 1
			r["props"] = _build_nodes(r)
			r["staged_at"] = now_days
			incident_redressed.emit(r)
		else:
			## Out of budget. The record is already correct -- `outcome` and
			## `resolved_at` are written above -- it is only the props on the
			## ground that are stale, so it queues and gets its rebuild in a
			## later scan rather than blowing the frame here.
			_redress_q[int(r.get("uid", 0))] = true


## 2. Age -------------------------------------------------------------------


func _age(now_days: float, running: Dictionary) -> void:
	for uid in _uids():
		var r: Dictionary = incidents[uid]
		if String(r.get("state", "known")) == "spent":
			continue
		var live := bool(r.get("live", false))
		if live and running.has(uid):
			## STILL HAPPENING. Never spend an event the Chronicle is still
			## running, at any age — and "spent" is terminal, so doing it once
			## destroys the aftermath as well as the live dressing.
			##
			## The rule this replaces assumed no kind stays active near three
			## days. That was simply untrue: `bridge_out` runs up to ten days,
			## `mill_broken` and `murrain` seven, `charcoal` five, `deer_yard`
			## and `boat_overdue` four. Six of thirty-four kinds — about a
			## fifth of the catalogue — were being killed mid-event and then
			## never allowed an ending.
			continue
		## Two clocks, and which one applies is the whole of the ageing rule.
		##
		## A LIVE record that the Chronicle no longer has running is an orphan
		## — the Chronicle drops an active event outright if its kind was
		## renamed out from under a save — and an orphan has no ending coming,
		## so it is aged from `born` against the Director's ceiling. Without
		## this it would stage forever.
		##
		## A RESOLVED record is aged from its ending, against `linger`: how
		## long THIS kind of aftermath is worth walking up to — a burnt mill
		## reads for days, a lost hurdle for hours — with MEMORY_DAYS the
		## ceiling over all of them. `linger` 0 means the recipe is live-only:
		## the moment it resolves it is done and there is nothing to leave on
		## the ground.
		var since := float(r.get("born", now_days))
		var keep := MEMORY_DAYS
		if not live:
			since = _aftermath_clock(r)
			keep = minf(maxf(float(_kind_meta(String(r.get("kind", ""))).get(
				"linger", MEMORY_DAYS)), 0.0), MEMORY_DAYS)
		if now_days - since <= keep:
			continue
		_free_nodes(uid)
		r["state"] = "spent"
		r["props"] = 0
		incident_spent.emit(r)


func _ended_at(ev: Dictionary, now_days: float) -> float:
	## When the event ENDED, as the Chronicle understands it. `ends` is written
	## by `Chronicle._fire` and is the instant `_resolve_due` acts on, so it is
	## the honest resolve time and — unlike "whenever the Director next looked"
	## — it is the same number on every machine, in every save, forever. Capped
	## at now so a malformed row cannot stamp a clock in the future, and falls
	## back to now for an event dictionary that was not built by the Chronicle.
	var t := float(ev.get("ends", 0.0))
	if t <= 0.0:
		return now_days
	return minf(t, now_days)


func _redress(now_days: float) -> void:
	## Rebuild the dressing of incidents that resolved while the budget was
	## spent. Nearest-first is not worth the sort here: the queue only ever
	## holds things that are already STAGED, which means they are already
	## inside STRIKE_RADIUS and already built once.
	if _redress_q.is_empty():
		return
	var q: Array = _redress_q.keys()
	q.sort()
	for uid in q:
		if _build_left <= 0:
			break
		if not incidents.has(uid):
			_redress_q.erase(uid)
			continue
		var r: Dictionary = incidents[uid]
		if String(r.get("state", "known")) != "staged":
			## Struck or spent since it queued: nothing to re-dress, and the
			## normal staging pass will build it correctly if it comes back.
			_redress_q.erase(uid)
			continue
		_redress_q.erase(uid)
		_build_left -= 1
		r["props"] = _build_nodes(r)
		r["staged_at"] = now_days
		incident_redressed.emit(r)


func _scope_slack(kind: String) -> float:
	## The furthest an anchor of this kind's scope can sit from its place, or
	## -1.0 for "unbounded, do not gate on it".
	match String(_kind_meta(kind).get("stage", "place")):
		"wild":
			return WILD_FAR
		"shore":
			return SHORE_REACH
		"road":
			return -1.0
		_:
			return PLACE_FAR


func _aftermath_clock(r: Dictionary) -> float:
	## `resolved_at`, with `born` as the fallback — which is what a save written
	## before this key existed carries, and what a hand-built record in a test
	## carries. Older behaviour, not wrong behaviour: it is the ending time for
	## everything that resolves promptly, which is most of the catalogue.
	var t := float(r.get("resolved_at", -1.0))
	return t if t >= 0.0 else float(r.get("born", 0.0))


func _kind_meta(kind: String) -> Dictionary:
	## The four numbers and one string this file reads off a recipe, worked out
	## once per kind and then remembered. See `_kind_cache` for why.
	var hit: Variant = _kind_cache.get(kind, null)
	if hit is Dictionary:
		return hit as Dictionary
	var rc := IncidentKit.recipe_for(kind)
	var threat := int(rc.get("threat", -1))
	var meta := {
		"ok": not rc.is_empty(),
		"stage": String(rc.get("stage", "place")),
		"linger": float(rc.get("linger", MEMORY_DAYS)),
		"threat": threat,
		## ADDENDUM B. Absent means "whatever it was, quieter": an aftermath is
		## a thing that has finished happening. A recipe says so explicitly only
		## where the leavings are still genuinely dangerous (a raided hall, a
		## field the ravens are still on) or genuinely silent.
		"threat_after": int(rc.get("threat_after", mini(threat, 1))),
		"hear": String(rc.get("hear", "")),
	}
	_kind_cache[kind] = meta
	return meta


## 3. Reconcile -------------------------------------------------------------


func _reconcile() -> void:
	## A save restores records; it never restores nodes. `from_dict` keeps
	## `state` exactly as it was written — including "staged", because the
	## round trip is a contract — so the first scan after a load is where the
	## record and the scene are made to agree again. Demoting to "known" hands
	## it straight back to the normal staging pass, which will rebuild it this
	## same scan if the player is still standing next to it.
	for uid in _uids():
		var r: Dictionary = incidents[uid]
		if String(r.get("state", "known")) != "staged":
			continue
		var n: Variant = _nodes.get(uid, null)
		if n != null and is_instance_valid(n):
			continue
		## The entries themselves have to go, not just the record's state.
		## Something outside freed that node — a chunk teardown, an editor undo
		## — and a dead key left in `_nodes` is a key that never comes back: it
		## makes `report()["nodes"]` over-report forever and it leaks one
		## dictionary slot per externally-freed incident for the life of the
		## session. `_free_nodes` rather than a bare erase because the CRITTERS
		## of that incident may well still be alive: they are parented to the
		## wildlife director, not to the root that just went.
		_free_nodes(uid)
		r["state"] = "known"
		r["props"] = 0


## 4. Strike ----------------------------------------------------------------


func _strike_far(here: Vector2) -> void:
	for uid in _uids():
		var r: Dictionary = incidents[uid]
		if String(r.get("state", "known")) != "staged":
			continue
		if _flat_dist(r, here) <= STRIKE_RADIUS:
			continue
		_strike(r)


func _strike(r: Dictionary) -> void:
	## Nodes down, record kept. This is the whole of rule 1 in four lines: an
	## incident that has been struck is indistinguishable from one that has
	## never been staged, EXCEPT that `heard` and `outcome` and `born` are
	## still exactly what they were.
	var uid := int(r.get("uid", 0))
	_free_nodes(uid)
	## A queued re-dress is about props that no longer exist.
	_redress_q.erase(uid)
	r["state"] = "known"
	r["props"] = 0
	incident_struck.emit(r)


## 5. Stage -----------------------------------------------------------------


func _stage_near(here: Vector2, now_days: float) -> void:
	## THE COHORT, decided from scratch every scan: of everything eligible, the
	## MAX_STAGED nearest are the ones that get to be physical.
	##
	## Deciding it from scratch is the point. The old pass spent a slot on every
	## record that was ALREADY staged before it looked at a single candidate and
	## never preempted anything, so twelve incidents at two hundred metres could
	## starve one five metres from the player's boots — and because `_earshot`
	## only fires on a staged record, and earshot is the only way the contract
	## lets you find out an incident is there, that incident was not merely
	## invisible, it was permanently SILENT. First-come is not a policy; it is
	## the absence of one.
	##
	## Already-staged records are candidates on the same footing as anything
	## else, which is what makes the cap preemptive. They are admitted from
	## anywhere inside STRIKE_RADIUS rather than STAGE_RADIUS, or the hysteresis
	## gap would vanish: `_strike_far` has already taken down everything beyond
	## STRIKE_RADIUS, so "still staged" IS "still inside the strike radius", and
	## judging those by the stage radius would tear down every incident in the
	## 220–300 m band on the very scan it entered it.
	var want: Array = []
	for uid in _uids():
		var r: Dictionary = incidents[uid]
		var st := String(r.get("state", "known"))
		if st == "spent":
			continue
		var d := _flat_dist(r, here)
		## Belt and braces: `_strike_far` has already removed everything past
		## STRIKE_RADIUS, so this line changes nothing today. It is here so
		## that a future reorder of the passes cannot silently leave an
		## incident standing a hundred kilometres behind the player.
		if d > STRIKE_RADIUS:
			continue
		if st != "staged" and d > STAGE_RADIUS:
			continue
		want.append([d, uid])
	## Nearest first, tiebroken on uid so the order is TOTAL. Two incidents at
	## the same distance is not a hypothetical — two aftermaths at the same
	## place share a `pos` — and "whatever sort_custom did with the tie" is
	## not something a determinism test may rest on.
	want.sort_custom(func(a, b):
		if not is_equal_approx(float(a[0]), float(b[0])):
			return float(a[0]) < float(b[0])
		return int(a[1]) < int(b[1]))
	if want.size() > MAX_STAGED:
		want.resize(MAX_STAGED)
	var cohort := {}
	for row in want:
		cohort[int(row[1])] = true
	## Anything staged that did not make the cut comes down, so the slot is free
	## this scan and not the next one.
	for uid in _uids():
		var r: Dictionary = incidents[uid]
		if String(r.get("state", "known")) != "staged" or cohort.has(uid):
			continue
		_strike(r)
	## And then build, NEAREST FIRST and at most STAGE_PER_SCAN of them. A whole
	## cohort in one frame is 22 ms headless — a dropped frame on every fast
	## travel, respawn and save load — and there is nothing to be gained by it:
	## the rest arrive over the next few seconds, and the nearest are always the
	## ones that arrive first. The anchor is NOT recomputed here. It was set at
	## ingest, restored verbatim by `from_dict`, and recomputing it at stage time
	## meant a record chosen by its saved anchor was then built somewhere else
	## entirely the moment the place roster had changed under it.
	for row in want:
		var r: Dictionary = incidents[int(row[1])]
		if String(r.get("state", "known")) == "staged":
			continue
		## The budget has ONE exemption, and it is the one that matters:
		## anything already inside EARSHOT is built regardless. Earshot is the
		## only discovery channel this system has, and it only fires on a
		## staged record -- so rate-limiting a thing the player is standing
		## next to means the world stays silent about it for up to three
		## scans while they walk past. Ten aftermaths at one place was
		## measured at five seconds of silence. (2026-09-07)
		var near := float(row[0]) <= EARSHOT
		if _build_left <= 0 and not (near and _grace_left > 0):
			## `want` is sorted nearest-first, so everything after this row is
			## further away and cannot qualify for the grace either.
			return
		if _build_left > 0:
			_build_left -= 1
		else:
			_grace_left -= 1
		r["props"] = _build_nodes(r)
		r["state"] = "staged"
		r["staged_at"] = now_days
		incident_staged.emit(r)


## 6. Earshot ---------------------------------------------------------------


func _earshot(here: Vector2) -> void:
	for uid in _uids():
		var r: Dictionary = incidents[uid]
		if String(r.get("state", "known")) != "staged" or bool(r.get("heard", false)):
			continue
		if _flat_dist(r, here) > EARSHOT:
			continue
		## Latched on the RECORD, not on the nodes, which is the only reason
		## this survives a strike, a restage and a save. Set before the ring
		## goes out, so a listener that turns round and scans again inside the
		## same frame cannot hear it twice.
		r["heard"] = true
		last_note = IncidentKit.note_for(String(r.get("kind", "")), String(r.get("place", "")))
		var rc := _kind_meta(String(r.get("kind", "")))
		## ADDENDUM B. A thing in progress and the mess it left are not the same
		## noise. The fire is a panic while it burns and a smell afterwards; the
		## raid is still worth the watch turning out days later. A recipe that
		## says nothing about its aftermath gets `mini(threat, 1)` — quieter,
		## but not silent.
		var threat := int(rc.get("threat", -1)) if bool(r.get("live", false)) \
			else int(rc.get("threat_after", -1))
		if threat >= 0:
			## A missing bus is a no-op by Telegraph's own contract, so there
			## is nothing to guard here. threat -1 is a SILENT incident — the
			## charcoal burn, the aurora — which still counts as heard,
			## because you have plainly seen it, but rings nothing.
			##
			## DETERMINISM BOUNDARY, deliberately crossed and only here:
			## `Telegraph._ring` relays with `randf_range` off a scene timer, so
			## WHEN the news reaches the next listener is not a hash of anything.
			## That is the right call — a village that answers on the same frame
			## every time reads as machinery — and it is safe because nothing
			## the Director records is downstream of it. What is deterministic
			## is that the ring happens, from this anchor, at this level.
			Telegraph.ring(self, _anchor_of(r), EARSHOT,
				clampi(threat, 0, 3), String(rc.get("hear", "")))
		incident_heard.emit(r)


## 7. Forget ----------------------------------------------------------------


func _forget(now_days: float, running: Dictionary) -> void:
	## The one place a record is ever removed, and it is deliberately timid.
	## A spent record may only be dropped once the Chronicle itself has no
	## memory of the uid — drop one that is still in the 64-deep resolved ring
	## and the very next harvest reads it back as brand new. Without a
	## Chronicle to ask, nothing is forgotten at all.
	if chronicle == null or not is_instance_valid(chronicle):
		return
	## Nothing spent, nothing to forget — and checking is one integer compare
	## against building and filling an 82-entry Dictionary of the Chronicle's
	## whole memory, every 1.7 seconds, for the entire run. The overwhelmingly
	## common case is that no record has aged out since the last scan.
	var spent: Array = []
	for uid in _uids():
		if String((incidents[uid] as Dictionary).get("state", "known")) == "spent":
			spent.append(uid)
	if spent.is_empty():
		return
	## The active half is the set `scan` already built for the ageing pass; only
	## the resolved ring has to be walked here.
	var known := running.duplicate()
	for e in chronicle.resolved:
		if e is Dictionary:
			known[int((e as Dictionary).get("uid", 0))] = true
	for uid in spent:
		var r: Dictionary = incidents[uid]
		if known.has(uid):
			continue
		if now_days - float(r.get("born", now_days)) < FORGET_DAYS:
			continue
		_free_nodes(uid)
		_road_ends.erase(uid)
		incidents.erase(uid)


## ============================ Where it lands ==============================


func anchor_for(rec: Dictionary) -> Vector3:
	## The anchor is a function of (world_seed, uid, the kind's staging scope,
	## the place's position). Not of the frame, not of the outcome, not of how
	## many times it has been staged before. Restage a uid a thousand times and
	## the barrel is on the same tuft of grass; that is what the idempotency
	## test rests on.
	##
	## HONESTLY, though, two of the four scopes also read the WORLD, and saying
	## "pure" without saying that was a lie the critic was right to catch:
	##
	##   `road`  reads `chronicle.places` to find the nearest other village.
	##           That list is mutable — the fort builder appends to it, and
	##           `Chronicle.from_dict` overlays a save's roster on the live one
	##           — so the answer can change under a running game. It is
	##           snapshotted per uid (`_road_ends`) the first time it is asked,
	##           which makes it stable for the life of a Director.
	##   `shore` reads the ground provider, which is bound at `bind_world` and
	##           does not change after it.
	##
	## And the anchor is COMPUTED EXACTLY ONCE, at ingest, then carried on the
	## record and round-tripped through the save. Nothing downstream recomputes
	## it. That, not the purity of this function, is what actually guarantees an
	## incident is built where it was selected from.
	var uid := int(rec.get("uid", 0))
	var pos := _as_vec2(rec.get("pos", Vector2.ZERO))
	var scope := String(_kind_meta(String(rec.get("kind", ""))).get("stage", "place"))
	var h := _hash(world_seed, uid, SALT_ANCHOR)
	var flat := pos
	match scope:
		"road":
			flat = _road_point(rec, uid)
		"wild":
			flat = _ring_point(pos, h, WILD_NEAR, WILD_FAR)
		"shore":
			flat = _shore_point(pos, h)
		_:
			## "place" and anything unrecognised. An incident belongs at the
			## EDGE of a settlement — the fold, the mill, the tithe barn are
			## never in the middle of the square — so the band starts at 18 m
			## rather than at zero.
			flat = _ring_point(pos, h, PLACE_NEAR, PLACE_FAR)
	return Vector3(flat.x, _ground_y(flat), flat.y)


func _ring_point(pos: Vector2, h: int, near: float, far: float) -> Vector2:
	var bearing := _unit(h, 0) * TAU
	var d := lerpf(near, far, _unit(h, 1))
	return pos + Vector2(cos(bearing), sin(bearing)) * d


func _shore_point(pos: Vector2, h: int) -> Vector2:
	## ADDENDUM A. `shore` is a refinement of `place`: the boat that did not come
	## back, the wreck, the herring. The village is a dot on a hillside and the
	## incident belongs at the water, so rather than guess a bearing this walks
	## out on sixteen of them until the ground reports it is at or below the
	## waterline, then steps 6 m back up the same bearing so the net is on the
	## sand and not under it.
	##
	## The sweep STARTS at the anchor hash and takes the first bearing that
	## finds water, so which way it goes is uid-stable without spending a new
	## hash input; two Directors with the same seed pick the same beach. Bearing
	## by bearing rather than ring by ring, because a shore is a direction, and
	## the first bearing that reaches water is the one this place faces.
	##
	## Headless there is no ground provider and no waterline, so this falls back
	## to the ordinary `place` band and the suite is unaffected.
	if _ground == null or not is_instance_valid(_ground):
		return _ring_point(pos, h, PLACE_NEAR, PLACE_FAR)
	var start := int(_unit(h, 0) * 16.0) % 16
	for b in range(16):
		var ang := float((start + b) % 16) * TAU / 16.0
		var dir := Vector2(cos(ang), sin(ang))
		var d := SHORE_STEP
		while d <= SHORE_REACH:
			if _ground_y(pos + dir * d) <= WATER_Y:
				return pos + dir * maxf(d - SHORE_BACK, 0.0)
			d += SHORE_STEP
	## A place with no water within 160 m in any direction. Nothing to stand on
	## the beach of; the ordinary band is the honest answer.
	return _ring_point(pos, h, PLACE_NEAR, PLACE_FAR)


func _road_point(rec: Dictionary, uid: int) -> Vector2:
	## THE HONEST STAND-IN. There is no road net yet — it is Sunday item 3 —
	## so "the road" here is the straight line from this place to the nearest
	## OTHER place on the map, and the incident lands in the middle 60% of it.
	## That is wrong in detail and right in shape: the caravan is between two
	## villages rather than inside one, which is the only property the staging
	## actually depends on. When the road net lands, this function is the one
	## thing that changes and every anchor downstream of it stays deterministic
	## for the same reason it is now.
	##
	## The far end is SNAPSHOTTED per uid the first time it is worked out. The
	## place roster is not a constant — `Chronicle.from_dict` appends every
	## place a save knows that the live roster does not, and the fort builder
	## appends at runtime — so "the nearest other place" can change answer mid
	## session, and measured, that moved one road anchor 748 m. An incident does
	## not get to relocate because a village was founded somewhere else.
	var pos := _as_vec2(rec.get("pos", Vector2.ZERO))
	var h := _hash(world_seed, uid, SALT_ROAD)
	var best := Vector2.ZERO
	var found := false
	var memo: Variant = _road_ends.get(uid, null)
	if memo is Vector2:
		best = memo as Vector2
		found = true
	elif chronicle != null and is_instance_valid(chronicle):
		var bd := INF
		for p in chronicle.places:
			var pd := p as Dictionary
			var q := _as_vec2(pd.get("pos", Vector2.ZERO))
			var d := q.distance_to(pos)
			## Strictly the nearest OTHER place: the same coordinates are the
			## same village, and a segment of zero length is not a road.
			if d <= 0.001:
				continue
			if d < bd:
				bd = d
				best = q
				found = true
		if found and uid > 0:
			_road_ends[uid] = best
	if not found:
		## No map to draw a road on — no Chronicle bound yet, or a roster with
		## nowhere else in it. Falling back to the `place` band keeps the anchor
		## deterministic and on solid ground, which matters for a Director
		## restored from a save before World has bound anything.
		return _ring_point(pos, _hash(world_seed, uid, SALT_ANCHOR), PLACE_NEAR, PLACE_FAR)
	var t := (1.0 - ROAD_MID) * 0.5 + _unit(h, 0) * ROAD_MID
	return pos.lerp(best, t)


func _ground_y(flat: Vector2) -> float:
	## Duck-typed, and null is the normal case: the headless suite has no
	## terrain at all and every incident in it sits honestly at y = 0.
	if _ground == null or not is_instance_valid(_ground):
		return 0.0
	var probe := Vector3(flat.x, GROUND_PROBE, flat.y)
	var y := 0.0
	if _ground.has_method("_surface_y"):
		y = float(_ground.call("_surface_y", probe))
	elif _ground.has_method("surface_y"):
		y = float(_ground.call("surface_y", probe))
	if is_nan(y) or is_inf(y):
		return 0.0
	return y


func _anchor_of(rec: Dictionary) -> Vector3:
	var a: Variant = rec.get("anchor", Vector3.ZERO)
	if a is Vector3:
		return a as Vector3
	return anchor_for(rec)


func _flat_dist(rec: Dictionary, here: Vector2) -> float:
	## Measured to the ANCHOR, never to the place. The anchor is where the
	## props are and where the sound comes from, and it can be 140 m out into
	## the wild from the village the Chronicle filed the event under. Judging
	## "near enough to build" by the village would build things you cannot see
	## and stay silent about things you are standing in.
	var a := _anchor_of(rec)
	return Vector2(a.x, a.z).distance_to(here)


## ============================== The props =================================


func _build_nodes(rec: Dictionary) -> int:
	## Idempotent by construction: whatever was there for this uid is freed
	## first, so a rebuild is a rebuild and not a second copy. Every number
	## used in here is a hash of (seed, uid, salt+spec+index) — no counters, no
	## frame, no generator — which is what makes stage/strike/restage produce
	## byte-identical placements.
	var uid := int(rec.get("uid", 0))
	_free_nodes(uid)
	var kind := String(rec.get("kind", ""))
	var specs := IncidentKit.props_for(kind, String(rec.get("outcome", "")),
		bool(rec.get("live", false)))
	var anchor := _anchor_of(rec)
	## The root is built and kept even when the recipe has nothing to show for
	## this outcome. An entry in `_nodes` is what "this record is physical"
	## MEANS to `_reconcile`, and a staged record with no entry would be
	## demoted and restaged on every single scan, emitting a staging signal
	## every 1.7 seconds for an incident that is a patch of grass.
	var root := Node3D.new()
	root.name = "incident_%d" % uid
	root.position = anchor
	var made := 0
	var mine: Array = []
	for s in range(specs.size()):
		## MAX_PROPS is a ceiling on the whole incident, not on one spec, so it
		## has to stop the OUTER loop too. Breaking only the inner one left the
		## outer walking the rest of the specs to break again in each of them.
		if made >= MAX_PROPS:
			break
		if not (specs[s] is Dictionary):
			continue
		var spec := specs[s] as Dictionary
		var n := maxi(int(spec.get("n", 1)), 1)
		var spread := maxf(float(spec.get("spread", 2.0)), 0.0)
		## ADDENDUM C. Per-SPEC rolls, not per-copy: a `line` layout is a fence,
		## and a fence has one bearing and one yaw down its whole length. The
		## disc layout ignores these and rolls per copy as before.
		var sh := _hash(world_seed, uid, SALT_PROP + s * 131)
		var line := String(spec.get("layout", "")) == "line"
		var line_dir := Vector2(cos(_unit(sh, 1) * TAU), sin(_unit(sh, 1) * TAU))
		var line_yaw := _unit(sh, 3) * TAU
		for i in range(n):
			if made >= MAX_PROPS:
				break
			var h := _hash(world_seed, uid, SALT_PROP + s * 131 + i * 17)
			var off := Vector3.ZERO
			if line:
				## Centred on the anchor: copy i sits at its offset from the
				## middle of the run, so a three-panel hurdle and a nine-panel
				## one are both centred on the same post.
				var t := (float(i) - float(n - 1) * 0.5) * spread / maxf(float(n), 1.0)
				off = Vector3(line_dir.x * t, 0.0, line_dir.y * t)
			else:
				var ang := _unit(h, 1) * TAU
				## sqrt of the roll, so the props fill the disc evenly instead
				## of crowding the anchor — a linear radius puts half of
				## everything in the middle quarter of the area.
				var rad := sqrt(_unit(h, 2)) * spread
				off = Vector3(cos(ang) * rad, 0.0, sin(ang) * rad)
			var wf := Vector2(anchor.x + off.x, anchor.z + off.z)
			off.y = _ground_y(wf) - anchor.y + float(spec.get("y", 0.0))
			if String(spec.get("kind", "")) == "critter":
				## Counted whether or not the wildlife director delivered.
				## `props` is part of `report()` and of `to_dict()`, and
				## `WildlifeDirector.spawn_one` is free to refuse (no ground
				## under the spot, no water for a water species) and to cull
				## on its own budget afterwards. Counting the ANIMAL rather
				## than the DECISION would run that non-determinism straight
				## into the digest that two Directors which lived the same
				## life are required to agree on -- which is Hard Rule 2. We
				## count what we asked for. (2026-09-07)
				made += 1
				var c := _spawn_critter(String(spec.get("arg", "")), anchor + off)
				if c != null:
					mine.append(c)
				continue
			var node := IncidentKit.build_prop(spec, i, _unit(h, 0))
			if node == null:
				continue
			node.position = off
			node.rotation.y = line_yaw if line else _unit(h, 3) * TAU
			root.add_child(node)
			made += 1
	add_child(root)
	_nodes[uid] = root
	if not mine.is_empty():
		_critters[uid] = mine
	return made


func _spawn_critter(key: String, at: Vector3) -> Node3D:
	## The one prop the Kit cannot build out of boxes: the wolves that are
	## still there, the crows on the field, the deer standing in the yard the
	## note promises. Optional in every direction — no director, no method, no
	## spawn, no complaint.
	##
	## ACCEPTED, and worth being explicit about because it is the one place this
	## file steps outside its own second rule: an incident critter is NOT
	## deterministic once it exists. The WildlifeDirector owns it from the
	## moment it is handed back — it wanders, it flees, and `WildlifeDirector.
	## _cull` will free it behind our back on its own budget, with no notice.
	## That is why every touch of `_critters` is guarded by `is_instance_valid`
	## and why nothing in a record is ever derived from a critter. What stays
	## deterministic is what this file decides: which species, how many, and
	## where each one is put down. What it does afterwards is the animal's.
	if key.is_empty() or _wildlife == null or not is_instance_valid(_wildlife):
		return null
	if not _wildlife.has_method("spawn_one"):
		return null
	var c: Variant = _wildlife.call("spawn_one", key, at)
	if c is Node3D and is_instance_valid(c):
		return c as Node3D
	return null


func _free_nodes(uid: int) -> void:
	var n: Variant = _nodes.get(uid, null)
	_nodes.erase(uid)
	if n != null and is_instance_valid(n):
		var node := n as Node
		## queue_free inside the tree, free outside it: a node that was never
		## in a tree has nobody to drain the deletion queue, and the headless
		## suite builds Directors that never enter one.
		if node.is_inside_tree():
			node.queue_free()
		else:
			node.free()
	var cs: Variant = _critters.get(uid, null)
	_critters.erase(uid)
	if cs is Array:
		for c in (cs as Array):
			## ORDER MATTERS. In Godot 4.7 `is` on a previously freed instance
			## throws "Left operand of 'is' is a previously freed instance", so
			## a type test placed FIRST defeats the very guard it was meant to
			## be protected by -- and WildlifeDirector._cull frees these behind
			## our back on its own budget, which is exactly the case the header
			## promises is handled. Validity first, always. (2026-09-07)
			if is_instance_valid(c) and c is Node:
				var cn := c as Node
				if cn.is_inside_tree():
					cn.queue_free()
				else:
					cn.free()


## ============================== Reading it ================================


func staged_uids() -> Array:
	var out: Array = []
	for uid in _uids():
		if String((incidents[uid] as Dictionary).get("state", "known")) == "staged":
			out.append(uid)
	return out


func record_for(uid: int) -> Dictionary:
	## The live record, not a copy — callers watch it change, the same way
	## Chronicle.place_by_name hands out the place itself.
	var r: Variant = incidents.get(uid, null)
	return r as Dictionary if r is Dictionary else {}


func note_for(rec: Dictionary) -> String:
	## The line the world says when you come into earshot. Kept OFF the record
	## on purpose — the record shape is a contract and prose is not state.
	return IncidentKit.note_for(String(rec.get("kind", "")), String(rec.get("place", "")))


func _uids() -> Array:
	## Sorted, everywhere, always. Every pass in this file iterates in uid
	## order so that two Directors handed the same events do the same work in
	## the same sequence — which matters the moment MAX_STAGED starts
	## refusing things.
	var k: Array = incidents.keys()
	k.sort()
	return k


func report() -> Dictionary:
	## A stable digest: sorted, rounded, and free of anything that could
	## differ between two Directors that lived the same life. Two Directors
	## with the same seed and the same events must report the same string.
	var rows: Array = []
	var known := 0
	var staged := 0
	var spent := 0
	var heard := 0
	var props := 0
	for uid in _uids():
		var r: Dictionary = incidents[uid]
		var st := String(r.get("state", "known"))
		match st:
			"staged":
				staged += 1
			"spent":
				spent += 1
			_:
				known += 1
		if bool(r.get("heard", false)):
			heard += 1
		props += int(r.get("props", 0))
		var a := _anchor_of(r)
		rows.append("%d|%s|%s|%s|%s|%.2f|%.2f|%.2f|%d" % [
			uid,
			String(r.get("kind", "")),
			String(r.get("outcome", "")),
			st,
			"h" if bool(r.get("heard", false)) else "-",
			snappedf(a.x, 0.01), snappedf(a.y, 0.01), snappedf(a.z, 0.01),
			int(r.get("props", 0)),
		])
	return {
		"seed": world_seed,
		"total": incidents.size(),
		"known": known,
		"staged": staged,
		"spent": spent,
		"heard": heard,
		"props": props,
		"nodes": _nodes.size(),
		"staged_uids": staged_uids(),
		"rows": rows,
	}


## ============================== Save / load ===============================


func to_dict() -> Dictionary:
	## Records only. The nodes are not in here and never will be: they are a
	## rendering decision, they are rebuilt from the record in a millisecond,
	## and a save that stored meshes would be a save that could not survive
	## the next time a recipe is retuned.
	##
	## Vectors go out as ARRAYS. `var_to_bytes` would carry a Vector2 through
	## as itself, but JSON is the format World actually writes, and
	## `JSON.stringify(Vector2(12.5, -3.25))` does not emit two numbers — it
	## emits the STRING "(12.5, -3.25)", which comes back a String, which
	## matches none of the arms in `_as_vec2`, which means every incident in a
	## reloaded world relocates to the map origin. `[x, y]` survives both
	## formats and both readers already accept it.
	var rows: Array = []
	for uid in _uids():
		var r: Dictionary = incidents[uid]
		var p := _as_vec2(r.get("pos", Vector2.ZERO))
		var a := _anchor_of(r)
		rows.append({
			"uid": int(r.get("uid", uid)),
			"kind": String(r.get("kind", "")),
			"outcome": String(r.get("outcome", "")),
			"place": String(r.get("place", "")),
			"pos": [p.x, p.y],
			"born": float(r.get("born", 0.0)),
			"resolved_at": float(r.get("resolved_at", -1.0)),
			"live": bool(r.get("live", false)),
			"state": String(r.get("state", "known")),
			"staged_at": float(r.get("staged_at", -1.0)),
			"heard": bool(r.get("heard", false)),
			"anchor": [a.x, a.y, a.z],
			"props": int(r.get("props", 0)),
		})
	return {
		"v": 1,
		"seed": world_seed,
		"days": _last_days,
		"incidents": rows,
	}


func from_dict(d: Dictionary) -> void:
	## MERGES, never replaces. Every save on disk today predates this file
	## entirely and has no "incidents" key at all; loading one must leave a
	## running Director exactly as it was rather than wiping a world's worth
	## of records because the save is old. Same reasoning as
	## Chronicle.from_dict overlaying places instead of swapping the list.
	if d.is_empty():
		return
	if int(d.get("v", 1)) > 1:
		return
	## The payload is judged BEFORE a single field is written, and there are two
	## different kinds of "no incidents" that used to be treated as one:
	##
	##   ABSENT — a legacy save, which is every save on disk that predates this
	##            file. It is a perfectly good save of the rest of the game; its
	##            seed and its day are real and are taken, and the records
	##            already in memory are simply left alone.
	##   PRESENT BUT NOT AN ARRAY — a truncated write, a hand edit, a version
	##            that meant something else by the key. That is not a save this
	##            file understands, and the old code reseeded the entire world
	##            and wound the clock on its way to refusing it. A payload that
	##            is rejected must change nothing at all.
	var rows: Variant = d.get("incidents", null)
	if rows != null and not (rows is Array):
		return
	world_seed = int(d.get("seed", world_seed))
	_last_days = float(d.get("days", _last_days))
	if rows == null:
		return
	for row in (rows as Array):
		if not (row is Dictionary):
			continue
		var s := row as Dictionary
		var uid := int(s.get("uid", 0))
		if uid <= 0:
			continue
		## A uid arriving from a save takes over from whatever is in memory
		## for that uid, nodes included — the saved record is the truth about
		## it now, and its `state` is restored verbatim (see `_reconcile`:
		## the next scan is what makes the scene agree with it again).
		_free_nodes(uid)
		## The road snapshot goes with it: the saved record may carry a
		## different `pos` for this uid than the one in memory did, and a
		## memoised far end from the old one would be a road to nowhere.
		_road_ends.erase(uid)
		incidents[uid] = {
			"uid": uid,
			"kind": String(s.get("kind", "")),
			"outcome": String(s.get("outcome", "")),
			"place": String(s.get("place", "")),
			"pos": _as_vec2(s.get("pos", Vector2.ZERO)),
			"born": float(s.get("born", 0.0)),
			## A save written before this key existed has no aftermath clock;
			## -1.0 sends `_aftermath_clock` back to `born`, which is the
			## behaviour that save was written under.
			## Clamped like every other number this function trusts a file
			## for. An unclamped `resolved_at` in the far future never ages,
			## so the record is never spent, so `_forget` never reaches it:
			## one corrupt row and that incident is immortal.
			"resolved_at": minf(float(s.get("resolved_at", -1.0)), _last_days),
			"live": bool(s.get("live", false)),
			"state": _clean_state(String(s.get("state", "known"))),
			"staged_at": float(s.get("staged_at", -1.0)),
			"heard": bool(s.get("heard", false)),
			"anchor": _as_vec3(s.get("anchor", Vector3.ZERO)),
			"props": maxi(int(s.get("props", 0)), 0),
		}


func _clean_state(s: String) -> String:
	return s if ["known", "staged", "spent"].has(s) else "known"


func _as_vec2(v: Variant) -> Vector2:
	## Three shapes come in here: a Vector2 (a `var_to_bytes` save, or a live
	## Chronicle event), a two-element Array (what `to_dict` writes, and what a
	## JSON save therefore reads back), and a Vector3 from a caller that had an
	## anchor where a position was wanted. Anything else is the origin.
	if v is Vector2:
		return v as Vector2
	if v is Vector3:
		var w := v as Vector3
		return Vector2(w.x, w.z)
	if v is Array and (v as Array).size() >= 2:
		var a := v as Array
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO


func _as_vec3(v: Variant) -> Vector3:
	if v is Vector3:
		return v as Vector3
	if v is Array and (v as Array).size() >= 3:
		var a := v as Array
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


## ================================ Rolling =================================
## No RandomNumberGenerator in this file, on purpose, exactly as in
## Chronicle.gd — and a SEPARATE mixer from the Chronicle's, with its own
## constants, on equal purpose. The Chronicle's `_hash` is private to the
## Chronicle; sharing it would mean that retuning the world's story rolls
## silently moves every barrel and blood-splash in the game, and a bug over
## there would arrive over here wearing a disguise. Same shape, different
## numbers, independent streams.
##
## If you ever need "one more random number here", reach for a new salt.


static func _hash(a: int, b: int, c: int) -> int:
	var h := a * 2246822519 + b * 3266489917 + c * 668265263
	h = (h ^ (h >> 15)) * 2654435761
	h = h ^ (h >> 13)
	h = h * 374761393
	h = h ^ (h >> 16)
	return h


static func _unit(h: int, k: int) -> float:
	## 0..1, masked rather than modulo'd off a signed int so a negative hash
	## cannot fold onto a narrow band of the range.
	var x := (h + k * 1274126177) * 2246822519
	x = x ^ (x >> 16)
	x = x * 3266489917
	x = x ^ (x >> 15)
	return float(x & 0x3FFFFFFF) / 1073741824.0
