class_name CritterAnim
extends RefCounted

## ===========================================================================
## SIGNATURE ANIMATION — the part a player actually recognises.
##                                                          docs/WILDLIFE.md §3
##
## CritterRig gives every animal a body. This file gives it a TELL. A moose is
## not a big deer because its boxes are bigger; it is a big deer because it
## puts its entire head underwater for two and a half seconds and comes up
## like a breaching whale. That is what someone remembers at fifty metres in
## fog, and it is the only thing that survives the render distance.
##
## HOUSE RULES — every function below assumes all of these.
##
##   * Pure functions of t. No stored phase, no tweens, no state machine. A
##     signature can be scrubbed, previewed at 0.1x or replayed backwards and
##     it still poses correctly. `delta` exists for sub-frame blur and nothing
##     else; `c` is accepted for future target lookups and never touched.
##
##   * Everything is written ABSOLUTE, never accumulated. idle() lays the
##     resting pose down every frame and play() overwrites only the pivots it
##     owns — the ones it ignores keep breathing on their own. That layering
##     is free and it is why a squirrel doing tail_flick still has a pulse.
##
##   * Poses are written RELATIVE TO REST, not to zero. A bird's body sits a
##     few degrees nose-down from the moment it is built; raw angles would
##     fight that on every bird in the dex.
##
##   * Bodies face -Z. Rotations are RADIANS on `.rotation`. Degrees appear
##     nowhere in this file. Sign conventions, worth memorising:
##         +X on head / neck  = nose UP           -X = nose down
##         -X on a tail       = tail UP           +X = clamped down
##         +X on a hip        = that leg swings FORWARD
##         +X on an ear       = pinned flat back
##         ±Z on a wing       = up; wings[0] is the LEFT one, so it mirrors
##
##   * Every pivot may be absent. _p() returns null, every setter eats null
##     silently, and a rig with no antlers must not crash antler_thrash — it
##     just thrashes a bare head, which is exactly what a doe does.
##
##   * Amplitudes are in _unit(rig): one body-length-ish metre, measured off
##     the rig itself at first touch. A whale and a firefly run the same code
##     and neither of them ends up moving in the other's units.
## ===========================================================================


## Test hook. play() has a branch for every key in the dex; if one ever goes
## missing this is what tells you, once, instead of silently fidgeting forever.
static var last_unhandled := ""


## ============================ SAFE ACCESSORS ==============================
## Written once, used everywhere. Nothing below this line touches rig[...]
## directly, which is the whole reason a half-built rig cannot take the game
## down with it.


static func _p(rig: Dictionary, key: String) -> Node3D:
	var n := rig.get(key) as Node3D
	return n if n != null and is_instance_valid(n) else null


static func _a(rig: Dictionary, key: String) -> Array:
	## `as Array` is not null-safe for a built-in type — it throws on a missing
	## key rather than handing back null, which is exactly the case this
	## library exists to survive (`segments` only exists on the snake).
	var v: Variant = rig.get(key, null)
	return v if v is Array else []


static func _at(rig: Dictionary, key: String, i: int) -> Node3D:
	var arr := _a(rig, key)
	if i < 0 or i >= arr.size():
		return null
	var n := arr[i] as Node3D
	return n if n != null and is_instance_valid(n) else null


## ============================== REST CACHE ================================
## A pivot's rest pose is not the identity — hips sit at hip height, a heron's
## neck is half a metre up. So the first time anything touches a rig we record
## where every pivot started, and neutral() puts it all back. The cache lives
## in metadata on the rig root, not in the rig Dictionary, so nothing that
## iterates the contract keys ever trips over it.

const _REST := "_critanim_rest"


static func _reach(root: Node3D, n: Node3D) -> float:
	## Distance from the root out to a pivot, summing local offsets up the
	## chain. Rest rotations are zero or near it everywhere in CritterRig, so
	## ignoring them costs a percent and saves a matrix walk per pivot.
	var p := Vector3.ZERO
	var q: Node3D = n
	var guard := 0
	while q != null and q != root and guard < 32:
		p += q.position
		q = q.get_parent() as Node3D
		guard += 1
	return p.length()


static func _collect(rig: Dictionary, out: Array[Node3D]) -> void:
	for k: String in ["root", "body", "spine", "neck", "head", "jaw", "tail", "tail2",
			"crest", "quills", "fan", "dewlap", "shell", "antler"]:
		var n := _p(rig, k)
		if n != null and not out.has(n):
			out.append(n)          ## "fan" is often "tail" again — hence has()
	for k: String in ["legs", "knees", "ears", "wings", "segments"]:
		for e in _a(rig, k):
			var n := e as Node3D
			if n != null and is_instance_valid(n) and not out.has(n):
				out.append(n)


static func _cache(rig: Dictionary) -> Dictionary:
	var root := _p(rig, "root")
	if root == null:
		return {}
	if root.has_meta(_REST):
		return root.get_meta(_REST)
	var nodes: Array[Node3D] = []
	_collect(rig, nodes)
	var pos: Array = []
	var rot: Array = []
	var scl: Array = []
	var ids := {}
	var reach := 0.0
	for i in nodes.size():
		var n := nodes[i]
		pos.append(n.position)
		rot.append(n.rotation)
		scl.append(n.scale)
		ids[n.get_instance_id()] = i
		reach = maxf(reach, _reach(root, n))
	## Materials: only emission energy and albedo alpha ever move, and only for
	## the legends. Captured so specter_fade can be undone without this file
	## needing to know whether the rig was built spectral in the first place.
	var me: Array = []
	var ma: Array = []
	for m in _a(rig, "mats"):
		var mat := m as StandardMaterial3D
		me.append(mat.emission_energy_multiplier if mat != null else 0.0)
		ma.append(mat.albedo_color.a if mat != null else 1.0)
	## One body-length-ish metre. 1.3x the outermost pivot's reach lands within
	## about fifteen percent of nose-to-rump on every family in the rig file —
	## measured, not guessed, because a moose and a chipmunk both have to leap
	## a sensible fraction of themselves off the same constant. The floor keeps
	## a firefly (whose only pivot is at the origin) from getting a unit of 0.
	var d := {"n": nodes, "p": pos, "r": rot, "s": scl, "id": ids,
		"u": maxf(reach * 1.3, 0.03), "me": me, "ma": ma}
	root.set_meta(_REST, d)
	return d


static func _unit(rig: Dictionary) -> float:
	var c := _cache(rig)
	return float(c.get("u", 1.0)) if not c.is_empty() else 1.0


static func _idx(rig: Dictionary, n: Node3D) -> int:
	var c := _cache(rig)
	if c.is_empty():
		return -1
	return int((c["id"] as Dictionary).get(n.get_instance_id(), -1))


static func _rest_pos(rig: Dictionary, n: Node3D) -> Vector3:
	var i := _idx(rig, n)
	return (_cache(rig)["p"] as Array)[i] if i >= 0 else n.position


static func _rest_rot(rig: Dictionary, n: Node3D) -> Vector3:
	var i := _idx(rig, n)
	return (_cache(rig)["r"] as Array)[i] if i >= 0 else Vector3.ZERO


static func _rest_scl(rig: Dictionary, n: Node3D) -> Vector3:
	var i := _idx(rig, n)
	return (_cache(rig)["s"] as Array)[i] if i >= 0 else Vector3.ONE


## ============================== POSE SETTERS ==============================
## Every one of these is rest-relative and null-safe. The *k variants take a
## contract key, the *i variants take a key and an index — between them the
## signature bodies below read as poses instead of as pointer chasing.


static func _rot(rig: Dictionary, n: Node3D, x: float, y := 0.0, z := 0.0) -> void:
	if n == null:
		return
	n.rotation = _rest_rot(rig, n) + Vector3(x, y, z)


static func _rk(rig: Dictionary, key: String, x: float, y := 0.0, z := 0.0) -> void:
	_rot(rig, _p(rig, key), x, y, z)


static func _ri(rig: Dictionary, key: String, i: int, x: float, y := 0.0, z := 0.0) -> void:
	_rot(rig, _at(rig, key, i), x, y, z)


static func _mv(rig: Dictionary, n: Node3D, off: Vector3) -> void:
	if n == null:
		return
	n.position = _rest_pos(rig, n) + off


static func _pk(rig: Dictionary, key: String, off: Vector3) -> void:
	_mv(rig, _p(rig, key), off)


static func _pi(rig: Dictionary, key: String, i: int, off: Vector3) -> void:
	_mv(rig, _at(rig, key, i), off)


static func _scl(rig: Dictionary, n: Node3D, s: Vector3) -> void:
	if n == null:
		return
	n.scale = _rest_scl(rig, n) * s


static func _sk(rig: Dictionary, key: String, s: Vector3) -> void:
	_scl(rig, _p(rig, key), s)


static func _si(rig: Dictionary, key: String, i: int, s: Vector3) -> void:
	_scl(rig, _at(rig, key, i), s)


## ================================ EASING ==================================
## Nothing in this file moves at constant velocity. Muscle is a spring, water
## is a drag, and gravity is t squared — linear ramps read as machinery.


static func _ease_in(t: float) -> float:
	return t * t


static func _ease_out(t: float) -> float:
	var u := 1.0 - t
	return 1.0 - u * u


static func _ease_io(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


static func _snap(t: float) -> float:
	## Harder than _ease_out, for what happens faster than the eye tracks: a
	## hoof landing, a heron's bill, a snapper's jaw.
	var u := 1.0 - t
	return 1.0 - u * u * u * u


static func _gravity(t: float) -> float:
	return t * t


static func _arc(t: float) -> float:
	## A real parabola, 0 at both ends and 1 at the apex. Every leap in this
	## file goes through here, which is why they all read as the same physics.
	return 4.0 * t * (1.0 - t)


static func _overshoot(t: float, k := 1.9) -> float:
	var u := t - 1.0
	return u * u * ((k + 1.0) * u + k) + 1.0


static func _bounce(t: float, freq := 3.4, decay := 7.0) -> float:
	## A decaying ring, exactly 0 at t=0. Multiply it into whatever the impact
	## shook and the shake stops on its own.
	return sin(t * TAU * freq) * exp(-t * decay)


static func _pulse(t: float, at: float, width: float) -> float:
	## A raised cosine bump centred on `at`. The workhorse of this file: every
	## discrete beat — a huff, a chew, a wingbeat, a hoot, a stamp — is one of
	## these, and they sum without ever kinking.
	if width <= 0.0:
		return 0.0
	var d := absf(t - at) / width
	if d >= 1.0:
		return 0.0
	return 0.5 + 0.5 * cos(d * PI)


static func _seg(t: float, a: float, b: float) -> float:
	## Remap a slice of the clip to 0..1, clamped. All phase structure below is
	## written as _seg(t, from, to) so the phase boundaries stay readable.
	if b <= a:
		return 1.0 if t >= b else 0.0
	return clampf((t - a) / (b - a), 0.0, 1.0)


static func _tri(t: float) -> float:
	return 1.0 - absf(t * 2.0 - 1.0)


static func _rand(n: int) -> float:
	## Deterministic 0..1 from an integer. randf() inside a per-frame function
	## gives you static, not personality — every "random" ear flick, war-dance
	## beat and swarm wobble in this file is seeded from here instead.
	var x := (n * 374761393 + 668265263) & 0x7FFFFFFF
	x = (x ^ (x >> 13)) * 1274126177
	return float((x >> 8) & 65535) / 65536.0


static func _blur(rig: Dictionary, n: Node3D, amp: float, hz: float, delta: float,
		axis := 2) -> void:
	## Wingbeats past about 12 Hz alias into nonsense when sampled off t, and a
	## hovering chickadee beats at 25. So blur runs off the engine clock and is
	## sampled half a frame late — the frame midpoint, which is where a real
	## shutter would have caught it. The aliasing that is left is the point:
	## it smears, which is what a blurred wing looks like.
	if n == null:
		return
	var ph := (float(Time.get_ticks_msec()) * 0.001 + delta * 0.5) * hz * TAU
	var v := sin(ph) * amp
	match axis:
		0: _rot(rig, n, v)
		1: _rot(rig, n, 0.0, v)
		_: _rot(rig, n, 0.0, 0.0, v)


## =============================== MATERIALS ================================


static func _emit(rig: Dictionary, energy: float) -> void:
	for m in _a(rig, "mats"):
		var mat := m as StandardMaterial3D
		if mat == null:
			continue
		mat.emission_enabled = true
		mat.emission_energy_multiplier = energy


static func _emit_wave(rig: Dictionary, base: float, amp: float, phase: float) -> void:
	## A shimmer that travels down the body instead of pulsing the whole animal
	## at once. Costs one sin per material and it is the difference between
	## "glowing" and "haunted".
	var mats := _a(rig, "mats")
	for i in mats.size():
		var mat := mats[i] as StandardMaterial3D
		if mat == null:
			continue
		mat.emission_enabled = true
		mat.emission_energy_multiplier = maxf(0.0, base + amp * sin(phase - float(i) * 0.35))


static func _alpha(rig: Dictionary, a: float) -> void:
	for m in _a(rig, "mats"):
		var mat := m as StandardMaterial3D
		if mat == null:
			continue
		if a < 0.995 and mat.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var c := mat.albedo_color
		c.a = clampf(a, 0.0, 1.0)
		mat.albedo_color = c


## ============================== DURATIONS =================================
## One play of each signature, in seconds. Where a call exists in the audio
## manifest the clip is matched to it to the frame — log_drum runs 9.7 s
## because grouse_drum.wav is 9.71 s of accelerating thumps and a wingbeat
## that finishes before the sound does looks like a dub.

const DUR := {
	"amble": 4.0, "antler_thrash": 1.6, "banana_pose": 4.0, "bank_slide": 2.0,
	"barrel_roll": 1.4, "bask": 6.0, "bat_ribbon": 2.2, "bear_grab": 2.5,
	"bear_huff": 1.2, "bear_press": 3.6, "bear_stand": 5.0, "berry_gorge": 3.0,
	"blow_spout": 3.0, "boat_wheel": 3.2,
	"bob_walk": 2.6, "breach": 4.0, "burrow_dive": 1.0, "cache_run": 2.4,
	"camp_case": 3.6, "camp_rob": 2.4, "caterwaul": 2.9, "cattail_feed": 3.0,
	"caw": 1.55, "cheek_stuff": 2.2, "chick_ride": 4.0, "chorus_hole": 2.0,
	"cliff_ledge": 3.0, "cling": 2.4, "corner_of_eye": 2.2, "corpse_circle": 6.0,
	"crest_raise": 1.2, "crest_slick": 1.6, "deadfall_run": 2.6, "dee_count": 0.95,
	"drum_roll": 1.5, "duckling_leap": 1.2, "dust_bathe": 4.0, "excavate": 3.2,
	"fake_hawk": 1.6, "falls_leap": 1.8, "fish_carry": 3.0, "fish_gulp": 2.0,
	"fish_mustache": 2.0, "fish_snatch": 2.6, "fish_toss": 2.0, "flit": 1.0,
	"fluke_dive": 4.0, "flush": 0.9, "food_wash": 3.0, "fool_hen": 3.0,
	"foot_stamp": 0.9, "fox_curl": 4.0, "freeze_crouch": 2.0, "freeze_solid": 5.0,
	"glide_in": 2.0, "gnaw_ring": 4.0, "gobble_back": 1.5, "grazing_line": 4.0,
	"ground_sit": 4.0, "hackles": 1.4, "hand_land": 2.2, "hand_steal": 1.6,
	"harass_cloud": 1.4, "hare_ambush": 2.2, "haul_out": 5.0, "head_track": 3.0,
	"hiss_charge": 2.4, "hiss_gape": 2.0, "hold_current": 3.0, "honk": 0.95,
	"hoof_stomp": 0.8, "hoot": 3.45, "hop": 0.7, "hover_dart": 1.6,
	"hover_plunge": 3.2, "howl": 2.55, "jug_o_rum": 1.65, "kraa": 1.65,
	"lantern_arrive": 3.0, "laugh": 2.6, "lead_wolves": 4.0, "leap_splash": 1.0,
	"ledge_shuffle": 2.4, "limb_nap": 6.0, "lodge_dive": 1.8, "log_drag": 3.6,
	"log_drum": 9.7, "log_plop": 1.4, "log_rip": 2.2, "loon_wail": 4.05,
	"lunge_latch": 2.0, "mask_stare": 2.4, "midden": 3.0, "mob": 3.0,
	"moose_dunk": 6.0, "mouse_dive": 1.6, "mouse_pounce": 1.3, "noodle_bound": 1.6,
	"oil_slip": 2.0, "omen_perch": 5.0, "one_scream": 2.9, "osprey_mug": 2.8,
	"otter_row": 2.4, "pack_pincer": 3.4, "paddle": 3.0, "peent": 0.65,
	"penguin_dance": 3.0, "periscope": 2.6, "piling_perch": 3.0, "play_dead": 12.0,
	"pogo_bound": 0.9, "porc_flip": 2.6, "porpoise": 1.6, "ptero_takeoff": 3.0,
	"quill_bristle": 1.0, "ribbon_flee": 2.0, "rise_ring": 1.4, "road_hiss": 2.4,
	"roll_arc": 1.8, "roost_flap": 2.6, "ruff_up": 1.2, "rummage": 3.4,
	"rut_spar": 2.4, "scold": 2.8, "scratch_line": 2.6, "scream": 1.7,
	"screech": 1.15, "scuttle": 1.2, "seal_follow": 4.0, "seed_hammer": 2.0,
	"sentry_post": 4.0, "shake_off": 1.6, "shell_tuck": 2.0, "silent_glide": 2.8,
	"silent_stalk": 4.0, "silt_ambush": 4.0, "sit_scan": 3.0, "skein": 6.3,
	"skulk": 3.0, "skunk_take": 2.4, "sky_dance": 9.0, "snag_sentinel": 5.0,
	"snort_wheeze": 1.2, "snow_dive": 1.1, "snow_float": 3.0, "snow_pop": 1.4,
	"soar": 6.0, "south_drift": 3.0, "spear_strike": 1.1, "specter_fade": 5.0,
	"spectral_cross": 6.0, "spray": 3.6, "spy_hop": 3.0, "statue_stalk": 5.0,
	"stoop": 2.4, "strut_drum": 5.0, "sun_coil": 5.0, "swim_wake": 3.0,
	"tail_flag": 1.0, "tail_flick": 1.0, "tail_slap": 0.9, "tail_swat": 0.7,
	"tail_up": 1.0, "teeter_soar": 5.0, "torpedo_dive": 2.2, "track_leave": 4.0,
	"tree_climb": 3.4, "tree_spiral": 3.4, "trunk_scramble": 2.4, "trunk_spiral": 2.4,
	"twinkle_drift": 2.4, "u_pose": 1.4, "unlatch": 3.0, "velvet_rub": 3.4,
	"waddle": 2.4, "wall_dash": 1.6, "war_dance": 3.2, "water_run": 2.6,
	"whir_flight": 2.0, "whistle": 0.55, "wing_dry": 4.0, "zigzag": 1.8,
	## --- buzz: the generic idle library, any family (see BUZZ below) ---------
	"graze": 3.2, "sniff_ground": 2.6, "paw_ground": 2.0, "huff_toss": 1.6,
	"wet_shake": 1.4, "stretch": 2.8, "look_about": 3.0, "scratch": 1.8,
	"sit_rest": 4.0, "tail_swish": 2.0, "peck_ground": 1.8, "preen": 2.6,
	"ruffle": 1.2, "wing_stretch": 2.4, "sun_bask": 4.0,
}


static func duration(sig: String) -> float:
	return float(DUR.get(sig, 1.2))


## =============================== NEUTRAL ==================================


static func neutral(rig: Dictionary) -> void:
	## Put every pivot back where CritterRig left it. Called when a signature
	## ends, so the next one starts from a pose it can reason about instead of
	## from whatever the last frame of a barrel roll happened to be.
	var c := _cache(rig)
	if c.is_empty():
		return
	var nodes := c["n"] as Array
	var pos := c["p"] as Array
	var rot := c["r"] as Array
	var scl := c["s"] as Array
	for i in nodes.size():
		var n := nodes[i] as Node3D
		if n == null or not is_instance_valid(n):
			continue
		n.position = pos[i]
		n.rotation = rot[i]
		n.scale = scl[i]
	## Coats too. specter_fade, corner_of_eye and track_leave all leave the
	## animal half-transparent, and nothing downstream should inherit a ghost.
	var mats := _a(rig, "mats")
	var me := c["me"] as Array
	var ma := c["ma"] as Array
	for i in mats.size():
		var mat := mats[i] as StandardMaterial3D
		if mat == null or i >= me.size():
			continue
		mat.emission_energy_multiplier = float(me[i])
		var col := mat.albedo_color
		col.a = float(ma[i])
		mat.albedo_color = col


## ================================ VERBS ===================================
## The moves that recur across thirty species. Written once here so a fox's
## crouch and a lynx's crouch are the same crouch, and so the signature bodies
## further down stay short enough to read as choreography.


static func _still(rig: Dictionary) -> void:
	## Pin the pivots idle() breathes on. Only for signatures whose whole point
	## is that nothing moves — play_dead, freeze_solid, head_track's body.
	for k: String in ["body", "neck", "head", "jaw", "tail", "tail2", "spine"]:
		var n := _p(rig, k)
		if n == null:
			continue
		n.position = _rest_pos(rig, n)
		n.rotation = _rest_rot(rig, n)
		n.scale = _rest_scl(rig, n)


static func _look(rig: Dictionary, yaw: float, pitch: float, roll := 0.0) -> void:
	## A head turn is a neck turn plus a head turn. Splitting it a third/two
	## thirds is what keeps a 0.8 rad look from snapping the skull off.
	_rk(rig, "neck", pitch * 0.34, yaw * 0.34, roll * 0.2)
	_rk(rig, "head", pitch * 0.66, yaw * 0.66, roll * 0.8)


static func _jaw_open(rig: Dictionary, amt: float) -> void:
	_rk(rig, "jaw", -clampf(amt, 0.0, 1.6))


static func _ears(rig: Dictionary, pin: float, yaw := 0.0, spread := 0.0) -> void:
	## pin 0 = up and forward, 1 = flat back along the skull. The single most
	## legible piece of body language a boxy animal has.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "ears", i, pin * 1.45 - 0.12, yaw * side, spread * side)


static func _legs_all(rig: Dictionary, swing: float, bend := -0.6) -> void:
	var legs := _a(rig, "legs")
	for i in legs.size():
		_ri(rig, "legs", i, swing)
		_ri(rig, "knees", i, bend)


static func _walk_legs(rig: Dictionary, ph: float, reach: float, lift: float) -> void:
	## Diagonal gait: FL+BR, then FR+BL. The foot only leaves the ground on the
	## return half of the cycle, which is what stops a walk looking like a
	## windmill.
	var legs := _a(rig, "legs")
	for i in legs.size():
		var a := ph + (0.0 if (i == 0 or i == 3) else PI)
		var swing := sin(a) * reach
		var raise := maxf(0.0, cos(a)) * lift
		_ri(rig, "legs", i, swing + raise * 0.5)
		_ri(rig, "knees", i, -swing * 0.7 - raise)


static func _bird_legs(rig: Dictionary, ph: float, reach: float, lift: float) -> void:
	for i in 2:
		var a := ph + (0.0 if i == 0 else PI)
		var swing := sin(a) * reach
		var raise := maxf(0.0, cos(a)) * lift
		_ri(rig, "legs", i, swing + raise * 0.4)
		_ri(rig, "knees", i, -swing * 0.9 - raise * 1.2)


static func _flap(rig: Dictionary, ph: float, amp: float, sweep := 0.0) -> void:
	## The downstroke is faster than the upstroke on every bird alive. Skewing
	## the sine by its own absolute value is the cheapest fix for a wingbeat
	## that otherwise ticks like a metronome.
	var s := sin(ph)
	var v := (s + 0.35 * s * absf(s)) * amp
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		## Undo whatever tuck idle() left on the wing — a flying bird's wing is
		## full length and nothing downstream should have to remember that.
		_si(rig, "wings", i, Vector3.ONE)
		_ri(rig, "wings", i, 0.0, -sweep * side, v * side)


static func _wings_fold(rig: Dictionary, amt: float) -> void:
	## 0 spread, 1 shut against the flank. Scaling X is a cheat and it is the
	## right cheat — a folded wing is mostly a shorter wing from any angle a
	## player sees it from.
	amt = clampf(amt, 0.0, 1.0)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_si(rig, "wings", i, Vector3(lerpf(1.0, 0.18, amt), 1.0, lerpf(1.0, 0.85, amt)))
		_ri(rig, "wings", i, 0.0, -0.85 * amt * side, -0.12 * amt * side)


static func _wings_v(rig: Dictionary, angle: float, sweep := 0.0) -> void:
	## Held dihedral, no beat. A vulture's ID mark and an owl's approach.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_si(rig, "wings", i, Vector3.ONE)
		_ri(rig, "wings", i, 0.0, -sweep * side, angle * side)


static func _tail_lift(rig: Dictionary, amt: float, fan := 1.0) -> void:
	_rk(rig, "tail", -amt)
	_rk(rig, "tail2", -amt * 0.35)
	if fan != 1.0:
		_sk(rig, "tail", Vector3(fan, 1.0, 1.0))


static func _crouch(rig: Dictionary, amt: float, u: float) -> void:
	_pk(rig, "root", Vector3(0, -0.11 * u * amt, 0))
	_sk(rig, "body", Vector3(1.0 + 0.05 * amt, 1.0 - 0.10 * amt, 1.0))
	var legs := _a(rig, "legs")
	for i in legs.size():
		_ri(rig, "legs", i, 0.30 * amt * (1.0 if i < 2 else -1.0))
		_ri(rig, "knees", i, -0.55 * amt)


static func _breathe(rig: Dictionary, ph: float, amt: float) -> void:
	var s := sin(ph)
	_sk(rig, "body", Vector3(1.0 + amt * 0.5 * s, 1.0 + amt * s, 1.0))


static func _wave_segments(rig: Dictionary, phase: float, amp: float, per_seg := 0.9) -> void:
	## The snake's entire locomotion: a sine running down a chain of pivots.
	## Because the segments are parented in series the rotations compound, so
	## the amplitude here is per-joint and small numbers go a long way.
	var segs := _a(rig, "segments")
	for i in segs.size():
		_ri(rig, "segments", i, 0.0, sin(phase - float(i) * per_seg) * amp)


## ================================= IDLE ===================================
## The resting overlay, applied EVERY frame before any signature. This is the
## layer that decides whether a herd of deer standing in a field looks alive
## or looks like furniture, and it costs about twenty sin() calls per animal.
##
## loco is 0..1, how much the animal is actually moving. walk_t is the gait
## phase Enemy._update_locomotion already drives the hips with — this function
## READS that and never writes it. Only `knees` are ours; fighting the hips
## produces a deer walking in two directions at once.


static func idle(rig: Dictionary, family: String, loco: float, walk_t: float,
		breathe_t: float) -> void:
	if _cache(rig).is_empty():
		return
	var fam := family if family != "" else String(rig.get("family", "CHUNK"))
	loco = clampf(loco, 0.0, 1.0)
	## Breathing runs 0.24 Hz asleep and 0.95 Hz at a flat run. Below that the
	## chest looks mechanical; above it, panicked.
	var br := breathe_t * TAU * lerpf(0.24, 0.95, loco)
	match fam:
		"BIRD_GROUND", "BIRD_PERCH":
			_idle_bird(rig, loco, walk_t, breathe_t, br, true)
		"BIRD_RAPTOR", "BIRD_WATER":
			_idle_bird(rig, loco, walk_t, breathe_t, br, false)
		"HERP":
			_idle_herp(rig, loco, walk_t, breathe_t, br)
		"FISH":
			_idle_fish(rig, loco, breathe_t)
		"SWARM":
			_idle_swarm(rig, loco, breathe_t)
		_:
			_idle_quad(rig, fam, loco, walk_t, breathe_t, br)


static func _idle_knees(rig: Dictionary, loco: float) -> void:
	## The hips are already swinging — read them and counter-rotate so the leg
	## FOLDS instead of scything through the ground like a compass leg. Hind
	## limbs keep a standing bend at the hock; front ones stay nearly straight.
	## That difference alone is most of what separates a deer from a table.
	var legs := _a(rig, "legs")
	var knees := _a(rig, "knees")
	var n := mini(legs.size(), knees.size())
	for i in n:
		var hip := legs[i] as Node3D
		var knee := knees[i] as Node3D
		if hip == null or knee == null or not is_instance_valid(knee):
			continue
		var front := i < 2
		var bend := -hip.rotation.x * (0.85 if front else 0.62)
		bend += (-0.05 if front else 0.16) * (0.4 + 0.6 * loco)
		knee.rotation = Vector3(bend, 0.0, 0.0)


static func _ear_flick(rig: Dictionary, breathe_t: float, alert: float) -> void:
	## Ears twitch at unpredictable intervals or they read as ornaments. One
	## lottery per 1.7 s per ear, seeded off the slot index — deterministic,
	## so it never jitters between frames, and independent per side.
	for i in 2:
		var slot := floori(breathe_t / 1.7) + i * 977
		var local := fposmod(breathe_t, 1.7) / 1.7
		var r := _rand(slot * 7 + i * 31)
		var flick := 0.0
		if r < 0.42:
			flick = _pulse(local, 0.15 + r * 1.2, 0.09)
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "ears", i, -0.10 - 0.45 * flick - alert * 0.18,
			side * (0.22 * flick + alert * 0.10), side * 0.30 * flick)


static func _idle_quad(rig: Dictionary, fam: String, loco: float, walk_t: float,
		breathe_t: float, br: float) -> void:
	var u := _unit(rig)
	var rest := 1.0 - loco
	var puff := sin(br)
	## Chest, not belly: scale Y a touch more than X so the ribcage reads.
	_sk(rig, "body", Vector3(1.0 + 0.010 * puff, 1.0 + 0.016 * puff, 1.0))
	_pk(rig, "body", Vector3(0, 0.006 * u * puff, 0))

	## Look-around. Two incommensurate periods so the animal never repeats a
	## pattern the player can learn; it drops off almost entirely at speed,
	## because a running animal looks where it is going.
	var yaw := 0.36 * rest * (sin(breathe_t * 0.31) * 0.7 + sin(breathe_t * 0.113) * 0.3)
	var pitch := -0.06 + 0.09 * sin(breathe_t * 0.23 + 1.1) * rest
	## Head bob on the gait. A moose nods; a cat does not — hence the family
	## multiplier rather than one number for everything on four legs.
	var nod := (0.075 if fam in ["CERVID", "URSID", "CHUNK"] else 0.035) * loco
	_look(rig, yaw, pitch + nod * sin(walk_t * 2.0))

	_ear_flick(rig, breathe_t, loco * 0.5)
	## Tail: a lazy sway at rest, a faster one at speed, and a slow curl that
	## never quite lines up with either.
	var tsway := (0.06 + 0.26 * loco) * sin(walk_t * 1.0 + breathe_t * 0.4)
	_rk(rig, "tail", -0.05 * loco + 0.03 * sin(breathe_t * 0.7), tsway)
	_rk(rig, "tail2", 0.04 * sin(breathe_t * 0.9 + 1.0), tsway * 0.8)
	## Mustelids flex through the middle even standing still — that spine is
	## the whole reason they are shaped like that.
	if fam == "MUSTELID":
		_rk(rig, "spine", 0.05 * sin(br * 0.5), 0.10 * sin(breathe_t * 0.6) * rest)
	_idle_knees(rig, loco)


static func _idle_bird(rig: Dictionary, loco: float, walk_t: float,
		breathe_t: float, br: float, ground: bool) -> void:
	var u := _unit(rig)
	var rest := 1.0 - loco
	_sk(rig, "body", Vector3(1.0 + 0.008 * sin(br), 1.0 + 0.012 * sin(br), 1.0))
	## The pigeon trick: the head holds still in world space while the body
	## walks out from under it, then catches up in one jerk. Sampling the front
	## half of the cycle only is what gives it the snap.
	if ground:
		var w := fposmod(walk_t, TAU) / TAU
		var thrust := (_ease_out(_seg(w, 0.0, 0.35)) - _ease_in(_seg(w, 0.55, 1.0))) * loco
		_pk(rig, "neck", Vector3(0, 0, -0.055 * u * thrust))
		_rk(rig, "head", 0.10 * thrust + 0.05 * sin(breathe_t * 0.9) * rest,
			0.30 * rest * sin(breathe_t * 0.37))
		_bird_legs(rig, walk_t, 0.34 * loco, 0.30 * loco)
	else:
		## Perched birds scan in flicks, not sweeps — small, quick, and mostly
		## still. Quantising the yaw is what makes a crow look like it is
		## thinking.
		var slot := floori(breathe_t / 1.3)
		var local := fposmod(breathe_t, 1.3) / 1.3
		var target := (_rand(slot) - 0.5) * 1.1
		var prev := (_rand(slot - 1) - 0.5) * 1.1
		_rk(rig, "head", 0.04 * sin(breathe_t * 0.8),
			lerpf(prev, target, _snap(_seg(local, 0.0, 0.18))))
		_bird_legs(rig, walk_t, 0.20 * loco, 0.18 * loco)
	## Wings tuck at rest and only start to open as the bird gets busy.
	_wings_fold(rig, lerpf(0.92, 0.35, loco))
	_rk(rig, "tail", 0.06 * sin(breathe_t * 0.55) - 0.10 * loco)


static func _idle_herp(rig: Dictionary, loco: float, walk_t: float,
		breathe_t: float, _br: float) -> void:
	var segs := _a(rig, "segments")
	if segs.size() > 0:
		## A snake at rest is not still, it is slow. Same travelling wave as
		## ribbon_flee, an eighth of the speed and half the amplitude.
		_wave_segments(rig, breathe_t * lerpf(1.1, 7.0, loco),
			lerpf(0.09, 0.26, loco), 0.9)
		_rk(rig, "head", 0.0, 0.10 * sin(breathe_t * 1.3))
		return
	## Everything else on this rig is a turtle, a frog or an eft: throat pumps
	## instead of ribs, and legs that splay rather than swing.
	var throat := sin(breathe_t * TAU * 0.8)
	_sk(rig, "jaw", Vector3(1.0, 1.0 + 0.10 * throat, 1.0))
	_rk(rig, "head", 0.05 * throat, 0.22 * sin(breathe_t * 0.29) * (1.0 - loco))
	_rk(rig, "neck", 0.03 * throat)
	var legs := _a(rig, "legs")
	for i in legs.size():
		var a := walk_t + (0.0 if (i == 0 or i == 3) else PI)
		_ri(rig, "legs", i, sin(a) * 0.30 * loco, 0.0, 0.0)
		_ri(rig, "knees", i, -0.20 * loco * sin(a))
	_rk(rig, "tail", 0.0, 0.16 * sin(walk_t * 0.5 + 1.0))


static func _idle_fish(rig: Dictionary, loco: float, breathe_t: float) -> void:
	## Continuous lateral beat, running from the body back through the tail so
	## the thrust looks like it comes from the animal rather than the fin. The
	## cetaceans on this rig get their vertical motion from roll_arc and
	## fluke_dive instead — a lateral beat is wrong for them but invisible at
	## the distance the gulf spawns them at.
	var ph := breathe_t * TAU * lerpf(1.1, 3.2, loco)
	var amp := lerpf(0.10, 0.30, loco)
	_rk(rig, "body", 0.0, -amp * 0.18 * sin(ph + 1.2))
	_rk(rig, "tail", 0.0, amp * sin(ph))
	_rk(rig, "tail2", 0.0, amp * 1.5 * sin(ph - 0.85))
	_rk(rig, "head", 0.0, amp * 0.30 * sin(ph + 1.6))
	## Pectorals hold and trim rather than row.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "legs", i, 0.10 * sin(ph * 0.5 + side), 0.0, side * 0.12)


static func _idle_swarm(rig: Dictionary, loco: float, breathe_t: float) -> void:
	## Cheap on purpose: sixty blackflies run this. Two sins and a wing blur.
	var u := _unit(rig)
	_pk(rig, "body", Vector3(0.15 * u * sin(breathe_t * 1.7),
		0.12 * u * sin(breathe_t * 2.3 + 1.0), 0.0))
	_rk(rig, "body", 0.0, 0.0, 0.20 * sin(breathe_t * 2.1))
	var beat := sin(breathe_t * TAU * lerpf(9.0, 16.0, loco))
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "wings", i, 0.0, 0.0, beat * 0.9 * side)


## ================================= PLAY ===================================
## t is 0..1 through ONE play of the action. Everything below is a pure pose
## function of t — see the house rules at the top of the file for why.
##
## `c` is part of the contract for future target lookups (a heron needs to
## know where the fish is eventually) and is deliberately not read yet, so a
## signature can be previewed against a rig with no Critter attached at all.

@warning_ignore("unused_parameter")
static func play(rig: Dictionary, sig: String, t: float, delta: float, c: Node = null) -> void:
	if _cache(rig).is_empty():
		return
	t = clampf(t, 0.0, 1.0)
	var u := _unit(rig)
	match sig:
		## --- cervids ------------------------------------------------------
		"moose_dunk": _moose_dunk(rig, t, u)
		"antler_thrash": _antler_thrash(rig, t, u)
		"rut_spar": _rut_spar(rig, t, u)
		"hackles": _hackles(rig, t, u)
		"velvet_rub": _velvet_rub(rig, t, u)
		"tail_flag": _tail_flag(rig, t, u)
		"hoof_stomp": _hoof_stomp(rig, t, u)
		"snort_wheeze": _snort_wheeze(rig, t, u)
		"pogo_bound": _pogo_bound(rig, t, u)
		## --- bears --------------------------------------------------------
		"bear_stand": _bear_stand(rig, t, u)
		"bear_huff": _bear_huff(rig, t, u)
		"bear_grab": _bear_grab(rig, t, u)
		"bear_press": _bear_press(rig, t, u)
		"log_rip": _log_rip(rig, t, u)
		"berry_gorge": _berry_gorge(rig, t, u)
		"tree_climb": _tree_climb(rig, t, u)
		## --- dogs ---------------------------------------------------------
		"howl": _howl(rig, t, u)
		"mouse_dive": _mouse_dive(rig, t, u, 1.0)
		"mouse_pounce": _mouse_dive(rig, t, u, 0.52)
		"skulk": _skulk(rig, t, u)
		"pack_pincer": _pack_pincer(rig, t, u)
		"fox_curl": _fox_curl(rig, t, u)
		"scream": _scream(rig, t, u)
		"trunk_scramble": _trunk_scramble(rig, t, u)
		## --- cats ---------------------------------------------------------
		"snow_float": _snow_float(rig, t, u)
		"hare_ambush": _hare_ambush(rig, t, u)
		"caterwaul": _caterwaul(rig, t, u)
		"silent_stalk": _silent_stalk(rig, t, u)
		"corner_of_eye": _corner_of_eye(rig, t, u)
		"one_scream": _one_scream(rig, t, u)
		"track_leave": _track_leave(rig, t, u)
		## --- mustelids ----------------------------------------------------
		"war_dance": _war_dance(rig, t, u)
		"snow_pop": _snow_pop(rig, t, u)
		"noodle_bound": _noodle_bound(rig, t, u)
		"oil_slip": _oil_slip(rig, t, u)
		"deadfall_run": _deadfall_run(rig, t, u)
		"tree_spiral": _tree_spiral(rig, t, u)
		"porc_flip": _porc_flip(rig, t, u)
		"bank_slide": _bank_slide(rig, t, u)
		"porpoise": _porpoise(rig, t, u)
		"fish_toss": _fish_toss(rig, t, u)
		"otter_row": _otter_row(rig, t, u)
		## --- the low waddlers ---------------------------------------------
		"quill_bristle": _quill_bristle(rig, t, u)
		"tail_swat": _tail_swat(rig, t, u)
		"limb_nap": _limb_nap(rig, t, u)
		"waddle": _waddle(rig, t, u)
		"foot_stamp": _foot_stamp(rig, t, u)
		"tail_up": _tail_up(rig, t, u)
		"u_pose": _u_pose(rig, t, u)
		"spray": _spray(rig, t, u)
		"camp_case": _camp_case(rig, t, u)
		"unlatch": _unlatch(rig, t, u)
		"rummage": _rummage(rig, t, u)
		"food_wash": _food_wash(rig, t, u)
		"mask_stare": _mask_stare(rig, t, u)
		"tail_slap": _tail_slap(rig, t, u)
		"gnaw_ring": _gnaw_ring(rig, t, u)
		"log_drag": _log_drag(rig, t, u)
		"lodge_dive": _lodge_dive(rig, t, u)
		"swim_wake": _swim_wake(rig, t, u)
		"play_dead": _play_dead(rig, t, u)
		"hiss_gape": _hiss_gape(rig, t, u)
		"periscope": _periscope(rig, t, u)
		"whistle": _whistle(rig, t, u)
		"burrow_dive": _burrow_dive(rig, t, u)
		"cattail_feed": _cattail_feed(rig, t, u)
		## --- seals --------------------------------------------------------
		"banana_pose": _banana_pose(rig, t, u)
		"spy_hop": _spy_hop(rig, t, u)
		"haul_out": _haul_out(rig, t, u)
		"seal_follow": _seal_follow(rig, t, u)
		## --- small rodents ------------------------------------------------
		"zigzag": _zigzag(rig, t, u)
		"freeze_crouch": _freeze_crouch(rig, t, u)
		"sit_scan": _sit_scan(rig, t, u)
		"hop": _hop(rig, t, u)
		"trunk_spiral": _trunk_spiral(rig, t, u)
		"scold": _scold(rig, t, u)
		"midden": _midden(rig, t, u)
		"cache_run": _cache_run(rig, t, u)
		"tail_flick": _tail_flick(rig, t, u)
		"cheek_stuff": _cheek_stuff(rig, t, u)
		"wall_dash": _wall_dash(rig, t, u)
		## --- ground birds -------------------------------------------------
		"strut_drum": _strut_drum(rig, t, u)
		"scratch_line": _scratch_line(rig, t, u)
		"dust_bathe": _dust_bathe(rig, t, u)
		"roost_flap": _roost_flap(rig, t, u, delta)
		"gobble_back": _gobble_back(rig, t, u)
		"log_drum": _log_drum(rig, t, u)
		"flush": _flush(rig, t, u, delta)
		"snow_dive": _snow_dive(rig, t, u)
		"ruff_up": _ruff_up(rig, t, u)
		"fool_hen": _fool_hen(rig, t, u)
		"bob_walk": _bob_walk(rig, t, u)
		"sky_dance": _sky_dance(rig, t, u, delta)
		"peent": _peent(rig, t, u)
		## --- raptors ------------------------------------------------------
		"fish_snatch": _fish_snatch(rig, t, u)
		"osprey_mug": _osprey_mug(rig, t, u)
		"snag_sentinel": _snag_sentinel(rig, t, u)
		"soar": _soar(rig, t, u)
		"hover_plunge": _hover_plunge(rig, t, u, delta)
		"shake_off": _shake_off(rig, t, u)
		"fish_carry": _fish_carry(rig, t, u)
		"silent_glide": _silent_glide(rig, t, u)
		"head_track": _head_track(rig, t, u)
		"hoot": _hoot(rig, t, u)
		"skunk_take": _skunk_take(rig, t, u)
		"stoop": _stoop(rig, t, u)
		"cliff_ledge": _cliff_ledge(rig, t, u)
		"ground_sit": _ground_sit(rig, t, u)
		"teeter_soar": _teeter_soar(rig, t, u)
		"corpse_circle": _corpse_circle(rig, t, u)
		"wing_dry": _wing_dry(rig, t, u)
		## --- perching birds -----------------------------------------------
		"barrel_roll": _barrel_roll(rig, t, u)
		"kraa": _kraa(rig, t, u)
		"lead_wolves": _lead_wolves(rig, t, u)
		"mob": _mob(rig, t, u)
		"sentry_post": _sentry_post(rig, t, u)
		"caw": _caw(rig, t, u)
		"hand_land": _hand_land(rig, t, u, delta)
		"dee_count": _dee_count(rig, t, u)
		"flit": _flit(rig, t, u, delta)
		"seed_hammer": _seed_hammer(rig, t, u)
		"screech": _screech(rig, t, u)
		"fake_hawk": _fake_hawk(rig, t, u)
		"crest_raise": _crest_raise(rig, t, u)
		"cling": _cling(rig, t, u)
		"excavate": _excavate(rig, t, u)
		"drum_roll": _drum_roll(rig, t, u)
		"laugh": _laugh(rig, t, u)
		"camp_rob": _camp_rob(rig, t, u, delta)
		"glide_in": _glide_in(rig, t, u)
		"omen_perch": _omen_perch(rig, t, u)
		## --- water birds --------------------------------------------------
		"loon_wail": _loon_wail(rig, t, u)
		"torpedo_dive": _torpedo_dive(rig, t, u)
		"water_run": _water_run(rig, t, u, delta)
		"chick_ride": _chick_ride(rig, t, u)
		"penguin_dance": _penguin_dance(rig, t, u, delta)
		"statue_stalk": _statue_stalk(rig, t, u)
		"spear_strike": _spear_strike(rig, t, u)
		"fish_gulp": _fish_gulp(rig, t, u)
		"ptero_takeoff": _ptero_takeoff(rig, t, u)
		"hiss_charge": _hiss_charge(rig, t, u)
		"skein": _skein(rig, t, u)
		"honk": _honk(rig, t, u)
		"grazing_line": _grazing_line(rig, t, u)
		"duckling_leap": _duckling_leap(rig, t, u)
		"paddle": _paddle(rig, t, u)
		"crest_slick": _crest_slick(rig, t, u)
		"hand_steal": _hand_steal(rig, t, u)
		"piling_perch": _piling_perch(rig, t, u)
		"boat_wheel": _boat_wheel(rig, t, u)
		"whir_flight": _whir_flight(rig, t, u, delta)
		"fish_mustache": _fish_mustache(rig, t, u)
		"ledge_shuffle": _ledge_shuffle(rig, t, u)
		## --- herps --------------------------------------------------------
		"lunge_latch": _lunge_latch(rig, t, u)
		"silt_ambush": _silt_ambush(rig, t, u)
		"road_hiss": _road_hiss(rig, t, u)
		"shell_tuck": _shell_tuck(rig, t, u)
		"bask": _bask(rig, t, u)
		"log_plop": _log_plop(rig, t, u)
		"ribbon_flee": _ribbon_flee(rig, t, u)
		"sun_coil": _sun_coil(rig, t, u)
		"jug_o_rum": _jug_o_rum(rig, t, u)
		"leap_splash": _leap_splash(rig, t, u)
		"freeze_solid": _freeze_solid(rig, t, u)
		"amble": _amble(rig, t, u)
		"scuttle": _scuttle(rig, t, u)
		## --- fish and cetaceans -------------------------------------------
		"roll_arc": _roll_arc(rig, t, u)
		"blow_spout": _blow_spout(rig, t, u)
		"breach": _breach(rig, t, u)
		"fluke_dive": _fluke_dive(rig, t, u)
		"rise_ring": _rise_ring(rig, t, u)
		"falls_leap": _falls_leap(rig, t, u)
		"hold_current": _hold_current(rig, t, u)
		## --- swarms -------------------------------------------------------
		"bat_ribbon": _bat_ribbon(rig, t, u, delta)
		"twinkle_drift": _twinkle_drift(rig, t, u)
		"hover_dart": _hover_dart(rig, t, u, delta)
		"harass_cloud": _harass_cloud(rig, t, u, delta)
		"south_drift": _south_drift(rig, t, u)
		"lantern_arrive": _lantern_arrive(rig, t, u, delta)
		"chorus_hole": _chorus_hole(rig, t, u)
		## --- legends ------------------------------------------------------
		"specter_fade": _specter_fade(rig, t, u)
		"spectral_cross": _spectral_cross(rig, t, u)
		## --- buzz (generic, any family) -----------------------------------
		"graze": _graze(rig, t, u)
		"sniff_ground": _sniff_ground(rig, t, u)
		"paw_ground": _paw_ground(rig, t, u)
		"huff_toss": _huff_toss(rig, t, u)
		"wet_shake": _wet_shake(rig, t, u)
		"stretch": _stretch(rig, t, u)
		"look_about": _look_about(rig, t, u)
		"scratch": _scratch(rig, t, u)
		"sit_rest": _sit_rest(rig, t, u)
		"tail_swish": _tail_swish(rig, t, u)
		"peck_ground": _peck_ground(rig, t, u)
		"preen": _preen(rig, t, u)
		"ruffle": _ruffle(rig, t, u)
		"wing_stretch": _wing_stretch(rig, t, u)
		"sun_bask": _sun_bask(rig, t, u)
		_:
			## Should be unreachable: the dex and this match are checked against
			## each other in tests. Warn once, then at least look alive.
			if last_unhandled != sig:
				last_unhandled = sig
				push_warning("CritterAnim: no branch for signature '%s'" % sig)
			_fidget(rig, t, u)


static func _fidget(rig: Dictionary, t: float, u: float) -> void:
	## The fallback. Deliberately bland — if you ever see an animal doing this
	## in game, a signature key is misspelled somewhere.
	_look(rig, 0.25 * sin(t * TAU), -0.05 + 0.08 * sin(t * TAU * 2.0))
	_pk(rig, "body", Vector3(0, 0.01 * u * sin(t * TAU * 2.0), 0))


## ============================== CERVIDS ===================================


static func _moose_dunk(rig: Dictionary, t: float, u: float) -> void:
	## The signature shot of the whole feature. A horse-sized animal puts its
	## entire face underwater, stays there long enough to be alarming, and
	## comes up wearing the pond.
	var down := _ease_io(_seg(t, 0.0, 0.20))       ## reach for the water
	var sink := _ease_in(_seg(t, 0.20, 0.30))      ## and drop through it
	var under := _seg(t, 0.30, 0.70)               ## 40% of the clip, gone
	var up := _snap(_seg(t, 0.70, 0.82))           ## and back, fast
	var settle := _seg(t, 0.82, 1.0)

	var depth := clampf(down * 0.5 + sink * 0.5 - up, 0.0, 1.0)
	var grub := sin(under * TAU * 1.6) if (under > 0.0 and under < 1.0) else 0.0
	## Coming up the neck overshoots past level and rings down. That recoil,
	## not the height, is what makes it read as heavy.
	var rear := up * (1.0 - settle * 0.5) * (1.0 + 0.30 * _bounce(settle, 2.3, 5.0))

	_rk(rig, "neck", -1.50 * depth + 0.48 * rear)
	_rk(rig, "head", -0.55 * depth + 0.12 * grub * depth + 0.34 * rear,
		0.20 * grub * depth)
	## Rotating the neck alone only gets the skull down to water level. The
	## head pivot has to physically drop below the body or it is a moose
	## drinking, which nobody remembers.
	_pk(rig, "head", Vector3(0, -0.62 * u * depth, -0.10 * u * depth))
	_pk(rig, "body", Vector3(0, -0.10 * u * depth, -0.06 * u * depth))
	_rk(rig, "body", -0.18 * depth + 0.12 * rear)
	_jaw_open(rig, (0.18 + 0.14 * sin(under * TAU * 3.2)) * depth)

	## Forelegs splay into the mud to reach; the hind pair never move.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "legs", i, 0.26 * depth, 0.0, side * 0.10 * depth)
		_ri(rig, "knees", i, -0.32 * depth)

	## The bell. It lags the neck by about a fifth of a second and keeps
	## swinging long after the head stops — the one part of a moose that
	## behaves like wet cloth, and the reason the recovery reads at all.
	_rk(rig, "dewlap", -0.55 * depth + 0.90 * up * _bounce(settle + 0.03, 1.6, 3.2),
		0.0, 0.40 * up * _bounce(settle + 0.06, 1.2, 2.6))
	_ears(rig, 0.40 * depth + 0.30 * up)


static func _antler_thrash(rig: Dictionary, t: float, u: float) -> void:
	## Side to side, hard, with the rack lagging the skull. A bull clearing a
	## sapling sounds like furniture breaking and looks like this.
	var env := _ease_out(_seg(t, 0.0, 0.10)) * (1.0 - _ease_in(_seg(t, 0.66, 1.0)))
	var ph := t * TAU * 3.4
	_rk(rig, "neck", -0.26 * env, 0.30 * sin(ph) * env)
	_rk(rig, "head", -0.12 * env, 0.62 * sin(ph) * env, 0.26 * sin(ph * 0.5) * env)
	## A fifth of a beat of lag. Antlers are heavy; that quarter radian of whip
	## is the difference between a threat and a shrug.
	_rk(rig, "antler", 0.0, 0.30 * sin(ph - 1.1) * env, 0.24 * sin(ph - 0.8) * env)
	_rk(rig, "body", -0.06 * env, -0.14 * sin(ph) * env, 0.10 * sin(ph) * env)
	_pk(rig, "body", Vector3(0.05 * u * sin(ph) * env, 0, 0))
	## Braced wide. Nothing steps — all of the motion is above the shoulder.
	for i in 4:
		var side := -1.0 if i % 2 == 0 else 1.0
		_ri(rig, "legs", i, 0.0, 0.0, side * 0.16 * env)
		_ri(rig, "knees", i, -0.10 * env)
	_ears(rig, 0.95 * env)


static func _rut_spar(rig: Dictionary, t: float, u: float) -> void:
	## Head down, antlers presented, and three shoving lunges off planted front
	## feet. Sparring is a pushing match, not a fight — the drive comes from
	## the hind legs and the front pair just refuse to give ground.
	var set_up := _ease_io(_seg(t, 0.0, 0.18))
	var shove := _pulse(t, 0.32, 0.09) + _pulse(t, 0.54, 0.09) + _pulse(t, 0.76, 0.10)
	_rk(rig, "neck", -0.74 * set_up - 0.18 * shove)
	_rk(rig, "head", -0.48 * set_up + 0.34 * shove)
	_rk(rig, "antler", 0.0, 0.10 * sin(t * TAU * 2.0) * set_up, 0.14 * shove)
	_rk(rig, "body", -0.18 * set_up - 0.14 * shove, 0.05 * sin(t * TAU * 1.3) * set_up)
	_pk(rig, "body", Vector3(0, -0.05 * u * set_up, -0.18 * u * shove))
	for i in 2:
		_ri(rig, "legs", i, -0.34 * set_up - 0.28 * shove)
		_ri(rig, "knees", i, 0.24 * set_up + 0.20 * shove)
	for i in range(2, 4):
		_ri(rig, "legs", i, 0.30 * set_up + 0.46 * shove)
		_ri(rig, "knees", i, 0.20 * set_up + 0.30 * shove)
	_ears(rig, 1.0)


static func _hackles(rig: Dictionary, t: float, u: float) -> void:
	## The pre-charge tell, and the most important pose in the file after the
	## dunk: if a player learns one piece of animal body language it should be
	## this one, because ignoring it costs them thirty-four damage.
	var on := _ease_out(_seg(t, 0.0, 0.30))
	## Shoulder hump first — it is what reads at range.
	_sk(rig, "body", Vector3(1.0 + 0.02 * on, 1.0 + 0.17 * on, 1.0 + 0.04 * on))
	_pk(rig, "body", Vector3(0, 0.045 * u * on, 0))
	_rk(rig, "body", -0.11 * on)
	## The neck goes down and the skull comes back UP, so the face stays
	## pointed at whatever it is about to run over. A lowered head that also
	## looks at the ground is an animal that has lost interest in you.
	_rk(rig, "neck", -0.54 * on)
	_rk(rig, "head", 0.48 * on + 0.018 * sin(t * TAU * 9.0) * on)
	_ears(rig, on)                       ## pinned flat, the moment it means it
	_rk(rig, "tail", 0.28 * on)
	_jaw_open(rig, 0.06 * on)
	for i in 4:
		var side := -1.0 if i % 2 == 0 else 1.0
		_ri(rig, "legs", i, (0.10 if i < 2 else -0.10) * on, 0.0, side * 0.10 * on)
		_ri(rig, "knees", i, -0.16 * on)


static func _velvet_rub(rig: Dictionary, t: float, u: float) -> void:
	## Scrubbing the velvet off on a sapling. Autumn only, and the reason
	## every rub line in the woods is chest high on one side of a tree.
	var on := _ease_io(_seg(t, 0.0, 0.16)) * (1.0 - _ease_io(_seg(t, 0.88, 1.0)))
	var scrub := sin(t * TAU * 2.4)
	_rk(rig, "neck", -0.55 * on, 0.30 * on)
	_rk(rig, "head", -0.20 * on + 0.10 * scrub * on, (0.30 + 0.34 * scrub) * on,
		0.40 * scrub * on)
	_rk(rig, "antler", 0.16 * scrub * on, 0.0, 0.20 * scrub * on)
	_rk(rig, "body", 0.0, 0.14 * scrub * on, 0.07 * scrub * on)
	_pk(rig, "body", Vector3(0.05 * u * scrub * on, 0, -0.04 * u * on))
	## Hind feet shuffle for purchase every second or so.
	for i in range(2, 4):
		_ri(rig, "legs", i, 0.16 * sin(t * TAU * 1.2 + float(i)) * on)
	_ears(rig, 0.55 * on)


static func _tail_flag(rig: Dictionary, t: float, u: float) -> void:
	## A POSE, not a cycle. The tail comes up in under a fifth of a second,
	## flares, and stays there until the deer is out of the county.
	var up := _overshoot(_seg(t, 0.0, 0.18), 2.6)
	_rk(rig, "tail", -2.45 * up)
	_rk(rig, "tail2", -0.35 * up)
	## The white underside is only visible flared. That is the entire point of
	## the animal's name, so widen it rather than trusting the rotation.
	_sk(rig, "tail", Vector3(1.0 + 0.8 * up, 1.0, 1.0))
	_rk(rig, "neck", 0.32 * up)
	_rk(rig, "head", -0.14 * up, 0.10 * sin(t * TAU * 0.8))
	_ears(rig, 0.0, 0.30)
	_pk(rig, "body", Vector3(0, 0.02 * u * up, 0))
	_rk(rig, "body", 0.05 * up)


static func _hoof_stomp(rig: Dictionary, t: float, u: float) -> void:
	## Lift, hang, and drive it into the dirt. The deer is not warning you, it
	## is trying to make you move so it can see what you are.
	var lift := _ease_out(_seg(t, 0.0, 0.45))
	var drop := _snap(_seg(t, 0.45, 0.56))
	var land := _seg(t, 0.56, 1.0)
	var leg := lift - drop
	_ri(rig, "legs", 0, 0.66 * leg)
	_ri(rig, "knees", 0, -1.00 * leg)
	## The impact rings through the body for a fifth of a second and stops.
	_pk(rig, "root", Vector3(0, 0.018 * u * _bounce(land, 5.0, 13.0) - 0.02 * u * drop, 0))
	_rk(rig, "body", 0.0, 0.0, -0.06 * leg)
	## Head high and locked forward for the whole beat. It never looks away.
	_rk(rig, "neck", 0.36)
	_rk(rig, "head", -0.28)
	_ears(rig, 0.0, 0.60)                ## both ears swivelled onto you


static func _snort_wheeze(rig: Dictionary, t: float, u: float) -> void:
	## Matched to deer_snort.wav: an explosive burst, then a descending wheeze.
	## Two body pulses, the second softer, and the head thrown forward and down
	## on the first.
	var thrust := _ease_out(_seg(t, 0.0, 0.16)) * (1.0 - _ease_in(_seg(t, 0.66, 1.0)))
	var blow := _pulse(t, 0.14, 0.10) + 0.7 * _pulse(t, 0.44, 0.13)
	_rk(rig, "neck", -0.44 * thrust - 0.12 * blow)
	_rk(rig, "head", -0.30 * thrust - 0.18 * blow)
	_pk(rig, "neck", Vector3(0, 0, -0.07 * u * thrust))
	_jaw_open(rig, 0.34 * blow + 0.08 * thrust)
	_sk(rig, "body", Vector3(1.0 - 0.05 * blow, 1.0 - 0.04 * blow, 1.0 + 0.09 * blow))
	_pk(rig, "body", Vector3(0, 0, -0.05 * u * blow))
	_rk(rig, "tail", -1.1 * thrust)      ## half a flag; the full one comes next
	_ears(rig, 0.10, 0.50)


static func _pogo_bound(rig: Dictionary, t: float, u: float) -> void:
	## Stotting. Four legs land and leave together, stiff, and the animal goes
	## UP more than forward — it is a fitness advertisement aimed at the
	## predator, not an escape.
	var air := _arc(_seg(t, 0.06, 0.94))
	var tuck := _tri(_seg(t, 0.02, 0.98))
	var land := _pulse(t, 0.96, 0.06)
	_pk(rig, "root", Vector3(0, 0.55 * u * air, 0))
	for i in 4:
		_ri(rig, "legs", i, 0.08 + 0.34 * tuck)
		_ri(rig, "knees", i, -1.10 * tuck)
	_rk(rig, "body", 0.36 * _seg(t, 0.0, 0.42) - 0.56 * _seg(t, 0.46, 1.0))
	_rk(rig, "neck", 0.22 * air)
	_sk(rig, "body", Vector3(1.0, 1.0 - 0.12 * land, 1.0 + 0.06 * land))
	_tail_lift(rig, 2.2 * _ease_out(_seg(t, 0.0, 0.20)), 1.5)
	_ears(rig, 0.25)


## =============================== BEARS ====================================


static func _bear_stand(rig: Dictionary, t: float, u: float) -> void:
	## A black bear stands because it is short-sighted, not because it is
	## angry. The nose going up is the whole reason for the move; the height
	## is a side effect the player is welcome to misread.
	var gather := _ease_io(_seg(t, 0.0, 0.20))
	var rise := _ease_out(_seg(t, 0.20, 0.42))
	var hold := _seg(t, 0.42, 0.80)
	var fall := _ease_in(_seg(t, 0.80, 0.93))
	var land := _seg(t, 0.93, 1.0)
	var up := clampf(rise - fall, 0.0, 1.0)
	var pre := gather * (1.0 - rise)

	_rk(rig, "body", 1.26 * up - 0.18 * pre)
	_pk(rig, "body", Vector3(0, 0.30 * u * up, 0.14 * u * up))
	_pk(rig, "root", Vector3(0, -0.07 * u * pre + 0.035 * u * _bounce(land, 4.5, 10.0), 0))

	## THE FRONT FEET LEAVE THE GROUND.
	##
	## They did not, before. CritterRig parents the hip pivots to `root`, NOT
	## to `body` — Enemy._update_locomotion drives those hips directly and
	## would fight anything that re-parented them — so rearing the body lifted
	## the chest and left all four paws planted. The bear grew upward out of
	## its own shoulders.
	##
	## A rearing quadruped pivots about its HIND FEET, so the front hips travel
	## on an arc around them: up by sin(theta), back by (1 - cos(theta)). At the
	## 1.26 rad this animation reaches that is 0.95 and 0.69 of the hip
	## separation, which is where the two numbers below come from. They are
	## applied to the hip PIVOTS, so the whole front leg — thigh, knee, paw and
	## claws — goes up with the chest instead of staying nailed to the dirt.
	var lift := 0.95 * up
	var draw_back := 0.69 * up
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_pi(rig, "legs", i, Vector3(0, 0.63 * u * lift, 0.30 * u * draw_back))
		## Forelegs hang. Bears do not hold them up like a cartoon — they
		## dangle, and the wrists hang lower still. The hang is measured from
		## the raised shoulder now, so it reads as dangling rather than as a
		## leg bent backwards into the ground.
		_ri(rig, "legs", i, -1.05 * up + 0.24 * pre, 0.0, side * 0.14 * up)
		_ri(rig, "knees", i, -0.48 * up)
	## The hind legs straighten and take the whole animal — that is what the
	## front feet are standing on now.
	for i in range(2, 4):
		_pi(rig, "legs", i, Vector3(0, 0.07 * u * up, -0.05 * u * up))
		_ri(rig, "legs", i, 0.52 * up + 0.34 * pre)
		_ri(rig, "knees", i, -0.30 * up - 0.50 * pre)
	## Reading the air: a slow sweep with the nose leading, and a faster
	## sniffing bob riding on top of it.
	var sweep := sin(hold * TAU * 0.85)
	var sniff := sin(hold * TAU * 1.9)
	_rk(rig, "neck", (0.44 + 0.12 * sniff) * up)
	_rk(rig, "head", (0.32 + 0.10 * sniff) * up, 0.52 * sweep * up)
	_jaw_open(rig, (0.08 + 0.08 * maxf(0.0, sniff)) * up)
	_ears(rig, 0.0, 0.30 * sweep)
	## The drop is heavy. One frame of squash and it is over.
	var squash := _pulse(t, 0.945, 0.05)
	_sk(rig, "body", Vector3(1.0 + 0.08 * squash, 1.0 - 0.13 * squash, 1.0))


static func _bear_huff(rig: Dictionary, t: float, u: float) -> void:
	## Matched to bear_huff.wav: three explosive breaths and a jaw pop. The
	## fourth beat is not a huff — it is both front paws hitting the ground,
	## which is the part that actually moves people.
	var h := _pulse(t, 0.10, 0.07) + _pulse(t, 0.34, 0.07) + _pulse(t, 0.58, 0.07)
	_sk(rig, "body", Vector3(1.0 - 0.06 * h, 1.0 - 0.05 * h, 1.0 + 0.11 * h))
	_pk(rig, "body", Vector3(0, 0, -0.05 * u * h))
	_rk(rig, "neck", -0.22 - 0.16 * h)
	_rk(rig, "head", -0.10 - 0.12 * h)
	_jaw_open(rig, 0.60 * h)
	var swing := _ease_out(_seg(t, 0.72, 0.84)) - _snap(_seg(t, 0.84, 0.90))
	for i in 2:
		_ri(rig, "legs", i, 0.72 * swing)
		_ri(rig, "knees", i, -0.55 * swing)
	_pk(rig, "root", Vector3(0, 0.03 * u * _bounce(_seg(t, 0.90, 1.0), 5.0, 11.0), 0))
	_ears(rig, 0.80)


static func _bear_grab(rig: Dictionary, t: float, u: float) -> void:
	## THE JAW GRAB (Lemon, 2026-08-29). Lunge with the head dropping, clamp,
	## haul the whole front end up with the catch swinging from the mouth,
	## wrench it twice, then WHIP the head left and let go — the throw is the
	## head, not the paws. Critter._grab_tick deals the damage and hangs the
	## player off the jaw pivot every frame, so the clip and the mechanics
	## cannot drift apart.
	var lunge := _ease_out(_seg(t, 0.0, 0.14))          ## nose drops, body loads
	var clamp_k := _snap(_seg(t, 0.14, 0.22))           ## the bite lands
	var rear := _ease_io(_seg(t, 0.22, 0.40))           ## front end hauls up
	var fling := _ease_in(_seg(t, 0.70, 0.80))          ## the sideways whip
	var settle := _ease_io(_seg(t, 0.82, 1.0))          ## back to all fours
	var up := rear * (1.0 - settle)
	var down := lunge * (1.0 - clamp_k)                 ## only before the clamp

	## Body: load down-forward into the lunge, then rear back to lift the prey.
	_rk(rig, "body", -0.26 * down + 0.52 * up, 0.30 * fling * (1.0 - settle))
	_pk(rig, "body", Vector3(0, -0.06 * u * down + 0.17 * u * up,
		-0.10 * u * down + 0.06 * u * up))
	## The shake: two hard wrenches while carrying, riding on the hold window.
	var hold := _seg(t, 0.24, 0.68)
	var shake := (_pulse(hold, 0.24, 0.10) + _pulse(hold, 0.64, 0.10)) * up
	## Head: down into the clamp, up for the carry, wrenching side to side,
	## then the whip — the nose sweeps hard LEFT (+yaw) as the mouth opens.
	_rk(rig, "neck", -0.55 * down + 0.34 * up - 0.10 * shake)
	_rk(rig, "head", -0.62 * down + 0.24 * up + 0.14 * shake,
		0.42 * sin(hold * TAU * 2.1) * shake + 1.05 * fling * (1.0 - settle * 0.7))
	## Jaw: gapes for the clamp, half-shut around the body, opens to let go.
	_jaw_open(rig, 1.25 * down + 0.55 * up * (1.0 - fling) + 0.95 * fling * (1.0 - settle))
	_ears(rig, 0.9 * maxf(down, up))
	## Front hips ride the rear-up arc (the bear_stand lesson: the hips are
	## parented to root, so the arc must be written onto the PIVOTS).
	var k := up * 0.41
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_pi(rig, "legs", i, Vector3(0, 0.63 * u * 0.95 * k, 0.30 * u * 0.69 * k))
		_ri(rig, "legs", i, 0.30 * down - 0.72 * k + 0.10 * shake * side)
		_ri(rig, "knees", i, -0.30 * down - 0.40 * k)
	## Hind end takes the weight.
	for i in range(2, 4):
		_ri(rig, "legs", i, 0.30 * k + 0.18 * down)
		_ri(rig, "knees", i, -0.26 * k - 0.16 * down)
	## The release recoils the whole animal a step; one squash on the settle.
	_pk(rig, "root", Vector3(0.04 * u * fling * (1.0 - settle), -0.045 * u * down, 0))
	var squash := _pulse(t, 0.86, 0.06)
	_sk(rig, "body", Vector3(1.0 + 0.05 * squash, 1.0 - 0.08 * squash, 1.0))


static func _bear_press(rig: Dictionary, t: float, u: float) -> void:
	## THE PRESS (Lemon, 2026-08-29). Up onto the hind legs — but this one is
	## not reading the air, it is choosing you: it bends over at the top,
	## brings the whole front end down ON the player, leans there biting,
	## then drives forward to shove them flat and steps off to the side.
	## Critter._press_tick holds the player under the chest and lands the
	## bites on the jaw pulses below.
	var rise := _ease_out(_seg(t, 0.0, 0.26))           ## up it goes
	var bend := _ease_io(_seg(t, 0.26, 0.44))           ## and folds over you
	var shove := _snap(_seg(t, 0.74, 0.84))             ## the push-down
	var off := _ease_io(_seg(t, 0.84, 1.0))             ## back to all fours
	var up := rise * (1.0 - off)
	## Body: full rear, then pitch back down over the target while STAYING
	## tall — bent over you, not standing over you. The shove drives it
	## forward and down straight through where you were standing.
	_rk(rig, "body", 1.15 * up - 0.72 * bend * up - 0.28 * shove * (1.0 - off))
	_pk(rig, "body", Vector3(0,
		(0.28 * up - 0.10 * bend * up) * u,
		(0.13 * up - 0.34 * bend * up - 0.16 * shove * (1.0 - off)) * u))
	## The lean BREATHES: its weight settles onto you in slow pushes.
	var lean_hold := _seg(t, 0.44, 0.74)
	var breathe_w := sin(lean_hold * TAU * 1.6) * bend * (1.0 - shove)
	_pk(rig, "root", Vector3(0,
		(-0.03 * breathe_w - 0.05 * shove * (1.0 - off)) * u, 0))
	## Head and neck: craned down at the thing under it, working at it.
	_rk(rig, "neck", 0.30 * up - 0.88 * bend * up - 0.20 * shove)
	_rk(rig, "head", 0.18 * up - 0.46 * bend * up + 0.10 * breathe_w,
		0.24 * sin(lean_hold * TAU * 2.3) * bend)
	## Two bites while leaning (the brain's damage ticks land on these), and
	## the jaw hangs half-open through the lean — it is TALKING to you.
	var bite := _pulse(t, 0.48, 0.05) + _pulse(t, 0.64, 0.05)
	_jaw_open(rig, 0.30 * bend + 0.85 * bite + 0.35 * shove * (1.0 - off))
	_ears(rig, 0.95 * up)
	## Front hips: the full bear_stand arc on the way up, then they come
	## FORWARD with the bend — the paws land on the player, press with the
	## breathing weight, and punch down with the shove.
	var reach := bend * up
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_pi(rig, "legs", i, Vector3(0,
			(0.63 * 0.95 * up - 0.38 * reach) * u,
			(0.30 * 0.69 * up - 0.22 * reach) * u))
		_ri(rig, "legs", i,
			-1.05 * up + 1.55 * reach + 0.10 * breathe_w + 0.30 * shove,
			0.0, side * (0.14 * up - 0.06 * reach))
		_ri(rig, "knees", i, -0.48 * up + 0.10 * reach - 0.22 * shove)
	## Hind legs straighten under the whole show, exactly like the stand.
	for i in range(2, 4):
		_pi(rig, "legs", i, Vector3(0, 0.07 * u * up, -0.05 * u * up))
		_ri(rig, "legs", i, 0.52 * up)
		_ri(rig, "knees", i, -0.30 * up)
	## Coming off: one heavy landing squash as the front feet take ground.
	var squash := _pulse(t, 0.90, 0.06)
	_sk(rig, "body", Vector3(1.0 + 0.07 * squash, 1.0 - 0.11 * squash, 1.0))


static func _log_rip(rig: Dictionary, t: float, u: float) -> void:
	## Hook a claw under the log, haul back with the whole body behind it, then
	## put your face in the hole. Bears eat more ants than salmon.
	var hook := _ease_out(_seg(t, 0.0, 0.26))
	var haul := _ease_in(_seg(t, 0.26, 0.46))
	var dive := _ease_io(_seg(t, 0.50, 0.78)) * (1.0 - _ease_io(_seg(t, 0.88, 1.0)))
	_ri(rig, "legs", 0, 0.95 * hook - 2.00 * haul, 0.0, -0.20 * hook)
	_ri(rig, "knees", 0, -0.70 * hook + 0.60 * haul)
	_ri(rig, "legs", 1, 0.30 * hook - 0.45 * haul)
	_ri(rig, "knees", 1, -0.25 * hook)
	_rk(rig, "body", -0.20 * hook + 0.44 * haul - 0.34 * dive,
		0.22 * hook - 0.14 * haul)
	_pk(rig, "body", Vector3(0, 0.04 * u * haul, 0.22 * u * haul - 0.12 * u * dive))
	_rk(rig, "neck", -0.30 * hook - 0.85 * dive)
	_rk(rig, "head", -0.25 * dive, 0.28 * sin(dive * TAU * 1.4))
	_jaw_open(rig, 0.30 * dive)
	_ears(rig, 0.30 + 0.40 * dive)


static func _berry_gorge(rig: Dictionary, t: float, u: float) -> void:
	## Forty thousand berries a day. Head down, jaw working, and a slow sway
	## along the patch — the animal is not paying attention to anything else,
	## which is exactly how people walk into one.
	var down := _ease_io(_seg(t, 0.0, 0.15)) * (1.0 - _ease_io(_seg(t, 0.88, 1.0)))
	var chew := sin(t * TAU * 2.6)
	_rk(rig, "neck", -0.82 * down + 0.07 * chew * down)
	_rk(rig, "head", -0.28 * down + 0.10 * chew * down, 0.24 * sin(t * TAU * 0.7))
	_jaw_open(rig, (0.14 + 0.16 * maxf(0.0, sin(t * TAU * 5.2))) * down)
	_rk(rig, "body", 0.0, 0.11 * sin(t * TAU * 0.55), 0.08 * sin(t * TAU * 0.4))
	_pk(rig, "body", Vector3(0, -0.03 * u * down, 0))
	_walk_legs(rig, t * TAU * 0.35, 0.09, 0.05)
	_ears(rig, 0.10)


static func _tree_climb(rig: Dictionary, t: float, u: float) -> void:
	## Body vertical against the trunk, diagonal limbs reaching in pairs. Cubs
	## do this to get away from you; adults do it to get at beechnuts.
	var on := _ease_io(_seg(t, 0.0, 0.15))
	var ph := t * TAU * 2.0
	_rk(rig, "body", 1.34 * on)
	_pk(rig, "root", Vector3(0, 0.90 * u * _ease_io(t) * on, 0))
	for i in 4:
		var side := -1.0 if i % 2 == 0 else 1.0
		var reach := sin(ph + (0.0 if (i == 0 or i == 3) else PI))
		_ri(rig, "legs", i, (0.75 + 0.60 * reach) * on, 0.0, side * 0.26 * on)
		_ri(rig, "knees", i, (-0.50 - 0.45 * maxf(0.0, -reach)) * on)
	_rk(rig, "neck", 0.32 * on)
	_rk(rig, "head", 0.16 * on, 0.30 * sin(ph * 0.5) * on)
	_rk(rig, "tail", 0.40 * on)
	_ears(rig, 0.20)


## ================================ DOGS ====================================


static func _mouse_dive(rig: Dictionary, t: float, u: float, k := 1.0) -> void:
	## The one everybody has seen a photograph of. A fox hears a vole under
	## sixty centimetres of snow, aims with its ears, and posts itself into the
	## drift head first. k scales the whole acrobatic: 1.0 is the fox, 0.52 is
	## the coyote, who does the same job with far less commitment.
	var coil := _ease_io(_seg(t, 0.0, 0.28))
	var launch := _snap(_seg(t, 0.28, 0.34))
	var air := _ease_out(_seg(t, 0.30, 0.44)) * (1.0 - _seg(t, 0.80, 0.92))
	var hit := _seg(t, 0.80, 0.90)
	var rec := _ease_io(_seg(t, 0.90, 1.0))

	## A real parabola — up fast, hang at the top, down fast. Nearly a metre
	## over the snow for a fox, half that for the coyote, and that difference
	## is the entire distinction between the two animals doing the same trick.
	_pk(rig, "root", Vector3(0,
		0.95 * u * k * _arc(_seg(t, 0.34, 0.80))
		- 0.10 * u * coil * (1.0 - launch)
		- 0.07 * u * hit * (1.0 - rec), 0))
	## Nose-up off the ground, hard nose-DOWN through the fall. Landing at any
	## other attitude throws the whole thing away.
	var pitch := 0.42 * _seg(t, 0.30, 0.42) - 1.55 * k * _ease_in(_seg(t, 0.42, 0.82))
	pitch += (1.55 * k - 0.42) * rec
	_rk(rig, "body", pitch - 0.22 * coil)
	## Weight shifts back before the launch and the front end gets light.
	## Without this the leap reads as a teleport.
	_pk(rig, "body", Vector3(0, -0.06 * u * coil, 0.11 * u * coil - 0.06 * u * launch))

	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		## Forelegs go forward TOGETHER — a fox lands on both front feet at
		## once, pinning whatever it heard between them.
		_ri(rig, "legs", i, -0.30 * coil + 0.88 * air + 0.55 * hit, 0.0, side * 0.05 * air)
		_ri(rig, "knees", i, -0.75 * coil - 0.12 * air + 0.32 * hit)
	for i in range(2, 4):
		_ri(rig, "legs", i, 0.62 * coil - 0.95 * launch - 0.60 * air)
		_ri(rig, "knees", i, -1.05 * coil + 0.90 * launch - 0.10 * air)

	## Tail straight up like a dart: rudder, counterweight, and the shape in
	## every photograph of this that has ever been printed.
	_rk(rig, "tail", -1.55 * air - 0.30 * coil)
	_rk(rig, "tail2", -0.45 * air)
	## Ears hard forward through the coil. It cannot see the target at all.
	_ears(rig, -0.06 * coil, -0.20 * coil)
	_look(rig, 0.0, -0.32 * coil - 0.48 * air + (0.32 + 1.55 * k * 0.0) * rec)
	_pk(rig, "head", Vector3(0, -0.10 * u * hit * (1.0 - rec), -0.06 * u * hit))
	_jaw_open(rig, 0.40 * _pulse(t, 0.84, 0.06))
	_sk(rig, "body", Vector3(1.0, 1.0 - 0.10 * _pulse(t, 0.85, 0.05), 1.0))


static func _howl(rig: Dictionary, t: float, u: float) -> void:
	## Matched to coyote_howl.wav: a rising note that breaks into yips. Nose
	## goes vertical, the animal settles onto its haunches, and the last third
	## is all chatter.
	var rise := _ease_io(_seg(t, 0.0, 0.22))
	var hold := 1.0 - _ease_io(_seg(t, 0.86, 1.0))
	var yip := _seg(t, 0.62, 1.0)
	var chatter := sin(yip * TAU * 6.0) * yip * (1.0 - _seg(t, 0.92, 1.0))
	_rk(rig, "neck", (0.62 + 0.06 * chatter) * rise * hold)
	_rk(rig, "head", (0.55 + 0.10 * chatter) * rise * hold, 0.10 * chatter)
	_jaw_open(rig, (0.42 + 0.22 * chatter) * rise * hold)
	## Sitting down into it — the hindquarters drop about a hand's width.
	_pk(rig, "root", Vector3(0, -0.10 * u * rise * hold, 0))
	_rk(rig, "body", -0.16 * rise * hold)
	for i in range(2, 4):
		_ri(rig, "legs", i, 0.50 * rise * hold)
		_ri(rig, "knees", i, -0.80 * rise * hold)
	_ears(rig, 0.55 * rise * hold)       ## laid back, the way they always are mid-note
	_rk(rig, "tail", 0.20 * rise, 0.10 * sin(t * TAU * 0.8))


static func _skulk(rig: Dictionary, t: float, u: float) -> void:
	## The low crossing. Body dropped, head level with the shoulders, no
	## vertical bob at all, and one pause halfway to look back at you over its
	## own spine. Foxes do this on every field edge in the game.
	var low := _ease_io(_seg(t, 0.0, 0.12))
	var pause := _pulse(t, 0.52, 0.16)
	var move := low * (1.0 - pause * 0.9)
	_pk(rig, "root", Vector3(0, -0.10 * u * low, 0))
	_rk(rig, "body", 0.06 * low, 0.0, 0.04 * sin(t * TAU * 2.0) * move)
	_rk(rig, "neck", -0.34 * low)
	## The look back: 1.4 radians of head yaw with the body still walking away.
	_rk(rig, "head", 0.30 * low, 1.40 * pause)
	_ears(rig, 0.10, 0.45 * pause)
	_walk_legs(rig, t * TAU * 3.0 * (1.0 - pause), 0.42 * move, 0.16 * move)
	## Tail straight out behind and level — a skulking fox does not wag.
	_rk(rig, "tail", -0.30 * low, 0.10 * sin(t * TAU * 1.5) * move)
	_rk(rig, "tail2", -0.10 * low)


static func _pack_pincer(rig: Dictionary, t: float, u: float) -> void:
	## Not coming at you — going AROUND you, at a lope, with its head turned
	## the whole way. Two coyotes doing this from opposite sides is the moment
	## the player realises the pack has a plan.
	var on := _ease_io(_seg(t, 0.0, 0.15))
	var flank := sin(t * PI) * on           ## out and back across the clip
	_rk(rig, "root", 0.0, 0.62 * flank)
	_pk(rig, "root", Vector3(0.35 * u * flank, 0.03 * u * absf(sin(t * TAU * 3.4)), 0))
	## Body angled off its own line of travel — the crab-run every canid does
	## when it is watching one thing and heading somewhere else.
	_rk(rig, "body", -0.06 * on, -0.24 * flank, 0.10 * sin(t * TAU * 3.4) * on)
	_look(rig, -0.85 * flank, -0.10 * on)
	_ears(rig, 0.0, -0.30 * on)
	_walk_legs(rig, t * TAU * 3.4, 0.55 * on, 0.30 * on)
	_rk(rig, "tail", -0.15 * on, 0.30 * flank)


static func _fox_curl(rig: Dictionary, t: float, u: float) -> void:
	## Curling up in the open with the brush over the nose. A fox will sleep on
	## a snowbank at minus twenty doing exactly this, and it is the only time
	## the tail earns its length.
	var down := _ease_io(_seg(t, 0.0, 0.30))
	var wrap := _ease_io(_seg(t, 0.25, 0.55))
	_pk(rig, "root", Vector3(0, -0.16 * u * down, 0))
	_rk(rig, "root", 0.0, 0.0, 0.30 * down)
	_rk(rig, "body", 0.0, 0.55 * down, 0.20 * down)
	_sk(rig, "body", Vector3(1.0, 1.0 - 0.12 * down, 1.0 - 0.08 * down))
	## Nose tucks toward the flank; the tail comes round the other way to meet
	## it. Between them the fox becomes a circle.
	_rk(rig, "neck", -0.50 * wrap, -0.85 * wrap)
	_rk(rig, "head", -0.30 * wrap, -0.60 * wrap, 0.35 * wrap)
	_rk(rig, "tail", -0.55 * wrap, -1.35 * wrap)
	_rk(rig, "tail2", -0.20 * wrap, -0.80 * wrap)
	for i in 4:
		_ri(rig, "legs", i, (0.85 if i < 2 else -0.70) * down)
		_ri(rig, "knees", i, -1.20 * down)
	_ears(rig, 0.65 * wrap)
	## Asleep, not dead: one slow breath every three seconds.
	_pk(rig, "body", Vector3(0, 0.012 * u * sin(t * TAU * 1.3) * wrap, 0))


static func _scream(rig: Dictionary, t: float, u: float) -> void:
	## Matched to fox_scream.wav and fisher_scream.wav — the noise in the woods
	## at 2 a.m. that makes new players quit for the night. Head thrust up and
	## forward, jaw wide, body rigid, one hard shudder in the middle of it.
	var on := _ease_out(_seg(t, 0.0, 0.10)) * (1.0 - _ease_in(_seg(t, 0.78, 1.0)))
	var shudder := _bounce(_seg(t, 0.40, 0.62), 6.0, 5.0)
	_rk(rig, "neck", (0.48 + 0.08 * shudder) * on)
	_rk(rig, "head", (0.34 + 0.12 * shudder) * on, 0.06 * shudder)
	_pk(rig, "neck", Vector3(0, 0, -0.06 * u * on))
	_jaw_open(rig, (0.95 + 0.10 * shudder) * on)
	_sk(rig, "body", Vector3(1.0 - 0.04 * on, 1.0 - 0.03 * on, 1.0 + 0.06 * on))
	_ears(rig, 0.85 * on)
	_rk(rig, "tail", -0.35 * on, 0.12 * shudder)
	for i in 4:
		_ri(rig, "legs", i, 0.0, 0.0, (-0.10 if i % 2 == 0 else 0.10) * on)


static func _trunk_scramble(rig: Dictionary, t: float, u: float) -> void:
	## The gray fox climbs, which no other canid does, and it looks exactly as
	## wrong as that sounds: all four legs clawing, no technique, and a slip
	## halfway up that it recovers from by scrabbling harder.
	var on := _ease_out(_seg(t, 0.0, 0.10))
	var slip := _pulse(t, 0.52, 0.09)
	var climb := _ease_io(t) - 0.12 * slip
	_rk(rig, "body", 1.15 * on - 0.20 * slip)
	_pk(rig, "root", Vector3(0, 0.85 * u * climb * on, 0))
	var ph := t * TAU * 4.2
	for i in 4:
		var side := -1.0 if i % 2 == 0 else 1.0
		var reach := sin(ph + float(i) * 1.6)
		_ri(rig, "legs", i, (0.60 + 0.70 * reach + 0.5 * slip) * on, 0.0, side * (0.30 + 0.20 * slip) * on)
		_ri(rig, "knees", i, (-0.45 - 0.50 * maxf(0.0, -reach)) * on)
	_rk(rig, "neck", 0.35 * on - 0.30 * slip)
	_rk(rig, "head", 0.10 * on, 0.35 * sin(ph * 0.4))
	_rk(rig, "tail", 0.55 * on, 0.30 * sin(ph * 0.3))
	_ears(rig, 0.30 + 0.4 * slip)


## ================================ CATS ====================================


static func _silent_stalk(rig: Dictionary, t: float, u: float) -> void:
	## One foot at a time, lifted high, hung, and set down without weight. The
	## shoulder line never rises or falls — that flatness is the tell, and it
	## is why the shared _walk_legs would be wrong here.
	var on := _ease_io(_seg(t, 0.0, 0.10))
	var beat := t * 4.0
	## Placed-foot order: FL, BR, FR, BL. Never two feet of the same end.
	var slot: Array[int] = [0, 2, 3, 1]
	for i in 4:
		var s := float(slot[i])
		var swing := (_ease_io(clampf(beat - s, 0.0, 1.0)) * 2.0 - 1.0) * 0.34
		var lift := _pulse(beat, s + 0.5, 0.5)
		_ri(rig, "legs", i, (swing + lift * 0.30) * on)
		_ri(rig, "knees", i, (-swing * 0.6 - lift * 0.85) * on)
	_pk(rig, "root", Vector3(0, -0.12 * u * on, 0))
	_sk(rig, "body", Vector3(1.0 + 0.04 * on, 1.0 - 0.08 * on, 1.0))
	_rk(rig, "body", 0.05 * on, 0.0, 0.03 * sin(t * TAU * 1.0) * on)
	## Head locked forward and low, level with the shoulders.
	_rk(rig, "neck", -0.30 * on)
	_rk(rig, "head", 0.26 * on, 0.08 * sin(t * TAU * 0.7) * on)
	_ears(rig, -0.05, -0.15)
	## The tail tip is the only loud thing on a stalking cat.
	_rk(rig, "tail", -0.20 * on, 0.10 * sin(t * TAU * 0.9))
	_rk(rig, "tail2", 0.0, 0.55 * sin(t * TAU * 2.6) * on)


static func _snow_float(rig: Dictionary, t: float, _u: float) -> void:
	## A lynx walks ON the crust the player is posting through. Exaggerated
	## lift, splayed paws, and a body height that does not change by a
	## millimetre — it is not sinking, and the animation has to say so.
	var ph := t * TAU * 1.6
	for i in 4:
		var a := ph + (0.0 if (i == 0 or i == 3) else PI)
		var swing := sin(a)
		var lift := maxf(0.0, cos(a))
		_ri(rig, "legs", i, swing * 0.30 + lift * 0.55, 0.0, (-0.14 if i % 2 == 0 else 0.14) * lift)
		_ri(rig, "knees", i, -swing * 0.25 - lift * 1.15)
	_pk(rig, "root", Vector3(0, 0.0, 0))     ## deliberately flat: see above
	_rk(rig, "body", 0.0, 0.05 * sin(ph), 0.05 * sin(ph))
	_look(rig, 0.30 * sin(t * TAU * 0.5), -0.10)
	_ears(rig, 0.0, 0.12 * sin(t * TAU * 0.8))
	_rk(rig, "tail", -0.25, 0.18 * sin(ph * 0.5))


static func _hare_ambush(rig: Dictionary, t: float, u: float) -> void:
	## Coil, waggle, launch, pin. The hindquarter waggle before the leap is not
	## decoration — every cat alive does it to load both hind legs evenly, and
	## it is the frame that tells you the pounce is coming.
	var coil := _ease_io(_seg(t, 0.0, 0.34))
	var waggle := sin(t * TAU * 7.0) * _seg(t, 0.12, 0.34) * (1.0 - _seg(t, 0.34, 0.40))
	var air := _arc(_seg(t, 0.40, 0.78))
	var pin := _seg(t, 0.78, 0.92)
	var rec := _ease_io(_seg(t, 0.92, 1.0))
	_pk(rig, "root", Vector3(0, 0.62 * u * air - 0.13 * u * coil * (1.0 - _seg(t, 0.36, 0.44)), 0))
	_pk(rig, "body", Vector3(0.05 * u * waggle, 0, 0.08 * u * coil))
	_rk(rig, "body", -0.10 * coil + 0.30 * _seg(t, 0.38, 0.5) - 0.75 * _ease_in(_seg(t, 0.5, 0.82)) + 0.60 * rec,
		0.10 * waggle)
	for i in 2:
		_ri(rig, "legs", i, -0.40 * coil + 1.05 * _seg(t, 0.40, 0.62) + 0.70 * pin)
		_ri(rig, "knees", i, -0.85 * coil - 0.20 * air + 0.35 * pin)
	for i in range(2, 4):
		_ri(rig, "legs", i, 0.70 * coil - 1.10 * _seg(t, 0.36, 0.48))
		_ri(rig, "knees", i, -1.15 * coil + 1.00 * _seg(t, 0.36, 0.48))
	_look(rig, 0.0, -0.20 * coil - 0.40 * air + 0.35 * rec)
	_ears(rig, -0.08 * coil)
	_jaw_open(rig, 0.55 * _pulse(t, 0.80, 0.06))
	_rk(rig, "tail", -0.30 * coil - 0.90 * air, 0.40 * waggle)


static func _caterwaul(rig: Dictionary, t: float, u: float) -> void:
	## Matched to lynx_caterwaul.wav: a long wavering yowl that sags into a
	## growl. The head goes back, the jaw stays open for the whole note, and
	## the wobble in the yaw is the wobble in the sound.
	var on := _ease_out(_seg(t, 0.0, 0.12))
	var sag := _ease_in(_seg(t, 0.66, 1.0))
	var waver := sin(t * TAU * 4.2) * (1.0 - sag)
	_rk(rig, "neck", (0.46 - 0.55 * sag) * on, 0.10 * waver)
	_rk(rig, "head", (0.30 - 0.45 * sag) * on + 0.05 * waver, 0.22 * waver)
	_jaw_open(rig, (0.85 + 0.12 * waver) * on * (1.0 - 0.55 * sag))
	_sk(rig, "body", Vector3(1.0, 1.0 + 0.05 * on * (1.0 - sag), 1.0))
	_ears(rig, 0.35 * on + 0.5 * sag)
	_rk(rig, "tail", -0.20 * on, 0.35 * sin(t * TAU * 1.1))
	_pk(rig, "root", Vector3(0, -0.05 * u * sag, 0))


static func _corner_of_eye(rig: Dictionary, t: float, u: float) -> void:
	## The Ghost Cat's only trick, and it is a magic trick: by the time the
	## player turns their head it has turned its body, dropped, and gone. It
	## must never be seen standing still and it must never be seen twice.
	var turn := _ease_io(_seg(t, 0.0, 0.34))
	var go := _ease_in(_seg(t, 0.30, 0.75))
	_rk(rig, "root", 0.0, 2.30 * turn)
	_pk(rig, "root", Vector3(0, -0.14 * u * turn, 0.9 * u * go))
	_sk(rig, "body", Vector3(1.0 + 0.06 * turn, 1.0 - 0.16 * turn, 1.0 + 0.05 * go))
	_rk(rig, "body", 0.08 * turn, 0.0, 0.09 * sin(t * TAU * 4.0) * go)
	_rk(rig, "neck", -0.42 * turn)
	## One glance back, early, and then never again.
	_rk(rig, "head", 0.34 * turn, 0.95 * _pulse(t, 0.22, 0.14))
	_ears(rig, 0.30 * go)
	_walk_legs(rig, t * TAU * 5.0, 0.55 * go, 0.22 * go)
	_rk(rig, "tail", -0.20 * turn, 0.25 * sin(t * TAU * 3.0) * go)
	## And it fades. A legend flagged never_seen does not get to be looked at.
	_alpha(rig, 1.0 - 0.85 * _ease_in(_seg(t, 0.62, 1.0)))


static func _one_scream(rig: Dictionary, t: float, u: float) -> void:
	## The cougar scream: one, in the dark, close, and then nothing. Every
	## report of this animal in the state for eighty years is somebody hearing
	## exactly this and being told they did not.
	var arch := _ease_out(_seg(t, 0.0, 0.14))
	var hold := 1.0 - _ease_io(_seg(t, 0.72, 0.88))
	var stare := _seg(t, 0.86, 1.0)
	_rk(rig, "body", -0.22 * arch * hold)
	_sk(rig, "body", Vector3(1.0, 1.0 + 0.10 * arch * hold, 1.0))
	_rk(rig, "neck", (0.60 * arch - 0.60 * stare) * hold + 0.0)
	_rk(rig, "head", 0.45 * arch * hold - 0.30 * stare, 1.10 * stare)
	_jaw_open(rig, 1.05 * arch * hold)
	_ears(rig, 0.75 * arch * hold)
	_rk(rig, "tail", -0.45 * arch * hold, 0.30 * sin(t * TAU * 1.6))
	_pk(rig, "root", Vector3(0, -0.06 * u * arch * hold, 0))
	_alpha(rig, 1.0 - 0.5 * _ease_in(_seg(t, 0.9, 1.0)))


static func _track_leave(rig: Dictionary, t: float, u: float) -> void:
	## Walking away in a straight line at a deliberate pace, leaving prints in
	## the snow that will still be there in the morning. The prints are the
	## only proof the player ever gets, so the walk has to look measured, not
	## panicked.
	var on := _ease_io(_seg(t, 0.0, 0.10))
	var beat := t * 5.0
	var slot: Array[int] = [0, 2, 3, 1]
	for i in 4:
		var s := float(slot[i]) + floorf(beat / 4.0) * 4.0
		var swing := (_ease_io(clampf(beat - s, 0.0, 1.0)) * 2.0 - 1.0) * 0.30
		_ri(rig, "legs", i, (swing + _pulse(beat, s + 0.5, 0.5) * 0.24) * on)
		_ri(rig, "knees", i, (-swing * 0.6 - _pulse(beat, s + 0.5, 0.5) * 0.60) * on)
	_pk(rig, "root", Vector3(0, -0.04 * u * on, 0))
	_rk(rig, "body", 0.0, 0.0, 0.04 * sin(beat * PI) * on)
	## One look back over the shoulder at three quarters, then gone.
	_look(rig, 1.20 * _pulse(t, 0.74, 0.10), -0.12 * on)
	_ears(rig, 0.10)
	_rk(rig, "tail", 0.15 * on, 0.20 * sin(t * TAU * 1.2))
	_alpha(rig, 1.0 - 0.9 * _ease_in(_seg(t, 0.80, 1.0)))


## ============================= MUSTELIDS ==================================


static func _war_dance(rig: Dictionary, t: float, u: float) -> void:
	## The stoat's kill-jig. Hops, spins, back-arches and a full body twist in
	## an order that has to look chosen at random and be identical every time
	## it plays — hence _rand and not randf(). A rabbit watches this until it
	## forgets to run, and so, reliably, does a player.
	const BEATS := 7
	var f := t * float(BEATS)
	var b := mini(int(f), BEATS - 1)
	var v := f - float(b)
	## Spin accumulates across beats so the animal never snaps back to facing
	## front. Seven iterations a frame is nothing and the alternative is state.
	var spin := 0.0
	for i in b:
		spin += (1.0 if _rand(i * 5 + 1) > 0.45 else -1.0) * PI * 0.6
	spin += (1.0 if _rand(b * 5 + 1) > 0.45 else -1.0) * PI * 0.6 * _ease_io(v)
	var kind := int(_rand(b * 13 + 7) * 3.0)
	var hop := _arc(v) * (0.55 if kind == 0 else 0.20)
	var arch := sin(v * PI) * (1.0 if kind == 1 else 0.30)
	var twist := sin(v * TAU) * (1.0 if kind == 2 else 0.25)
	_rk(rig, "root", 0.0, spin, twist * 0.9)
	_pk(rig, "root", Vector3(0, hop * 0.55 * u, 0))
	_rk(rig, "body", -0.55 * arch, 0.20 * twist)
	_rk(rig, "spine", 0.80 * arch, 0.35 * twist)
	_rk(rig, "neck", 0.30 * arch, 0.50 * sin(f * 2.3))
	_rk(rig, "head", 0.20 - 0.30 * arch, 0.70 * sin(f * 3.1), 0.50 * twist)
	_rk(rig, "tail", -0.30 - 0.90 * arch, 0.70 * sin(f * 1.7))
	_rk(rig, "tail2", 0.0, 0.60 * sin(f * 2.7))
	for i in 4:
		_ri(rig, "legs", i, sin(f * TAU + float(i) * 1.9) * 0.55)
		_ri(rig, "knees", i, -0.50 - 0.50 * hop)
	_jaw_open(rig, 0.25 * _pulse(v, 0.30, 0.20))
	_ears(rig, -0.10)


static func _snow_pop(rig: Dictionary, t: float, u: float) -> void:
	## Straight up out of the snowpack, a look around, and straight back in.
	## An ermine spends the winter in the subnivean and this is the entire
	## amount of it a player will ever see.
	var out := _snap(_seg(t, 0.0, 0.18))
	var back := _ease_in(_seg(t, 0.74, 0.94))
	var up := clampf(out - back, 0.0, 1.0)
	_pk(rig, "root", Vector3(0, u * (0.80 * up - 0.55 * (1.0 - out)), 0))
	_rk(rig, "body", 1.20 * up)
	_rk(rig, "spine", -0.25 * up)
	## The look: two quick head snaps while it is up, nothing while it moves.
	var look := _seg(t, 0.20, 0.72)
	_rk(rig, "neck", 0.30 * up)
	_rk(rig, "head", 0.10 * up, 1.10 * sin(look * TAU * 1.5) * up)
	_ears(rig, -0.10 * up)
	for i in 4:
		_ri(rig, "legs", i, (0.90 if i < 2 else -0.30) * up)
		_ri(rig, "knees", i, -0.80 * up)
	_rk(rig, "tail", 0.55 * up, 0.30 * sin(t * TAU * 2.0))


static func _noodle_bound(rig: Dictionary, t: float, u: float) -> void:
	## The slinky gallop. Three bounds, and all of the distance comes from the
	## spine doubling and extending rather than from the legs, which is why a
	## weasel at speed looks like something spilled.
	var f := t * 3.0
	var v := fposmod(f, 1.0)
	var arc := _arc(v)
	_pk(rig, "root", Vector3(0, 0.30 * u * arc, 0))
	## Doubled at the top of the bound, stretched at the bottom.
	var fold := cos(v * TAU)
	_rk(rig, "spine", 0.85 * fold)
	_rk(rig, "body", -0.35 * fold)
	_sk(rig, "body", Vector3(1.0, 1.0, 1.0 - 0.14 * fold))
	_rk(rig, "neck", 0.25 * fold + 0.20)
	_rk(rig, "head", -0.15 * fold)
	for i in 2:
		_ri(rig, "legs", i, 0.55 - 0.95 * fold)
		_ri(rig, "knees", i, -0.45 - 0.40 * maxf(0.0, fold))
	for i in range(2, 4):
		_ri(rig, "legs", i, -0.45 + 0.95 * fold)
		_ri(rig, "knees", i, -0.55 - 0.50 * maxf(0.0, fold))
	_rk(rig, "tail", -0.45 - 0.35 * fold, 0.20 * sin(f * TAU))
	_ears(rig, 0.05)


static func _oil_slip(rig: Dictionary, t: float, u: float) -> void:
	## A mink does not climb over things, it pours over them. Body flattens and
	## lengthens, the head leads by a body length, and the legs disappear.
	var on := _ease_io(_seg(t, 0.0, 0.20)) * (1.0 - _ease_io(_seg(t, 0.85, 1.0)))
	var flow := _ease_io(t)
	_sk(rig, "body", Vector3(1.0 - 0.14 * on, 1.0 - 0.22 * on, 1.0 + 0.22 * on))
	_pk(rig, "root", Vector3(0, -0.10 * u * on + 0.10 * u * sin(flow * PI) * on, 0))
	_rk(rig, "body", 0.30 * sin(flow * TAU) * on, 0.20 * sin(flow * TAU * 0.5) * on,
		0.35 * sin(flow * TAU * 0.75) * on)
	_rk(rig, "spine", -0.45 * sin(flow * TAU) * on, 0.30 * sin(flow * TAU * 0.5 + 1.0) * on)
	_rk(rig, "neck", -0.30 * on, 0.25 * sin(flow * TAU * 0.5 + 2.0) * on)
	_rk(rig, "head", 0.20 * on, 0.20 * sin(flow * TAU * 0.5 + 2.4) * on)
	for i in 4:
		_ri(rig, "legs", i, (0.55 if i < 2 else -0.45) * on)
		_ri(rig, "knees", i, -0.95 * on)
	_rk(rig, "tail", 0.20 * on, 0.45 * sin(flow * TAU * 0.75 - 0.8) * on)


static func _deadfall_run(rig: Dictionary, t: float, u: float) -> void:
	## Four bounds over blowdown with a beat of stillness on each landing. A
	## fisher covers ground in a series of decisions, not a run.
	var f := t * 4.0
	var b := int(f)
	var v := fposmod(f, 1.0)
	## Bound heights vary — a big one over the log, small ones between.
	var h := 0.22 + 0.32 * _rand(b * 3 + 2)
	var arc := _arc(clampf(v / 0.72, 0.0, 1.0))
	var fold := cos(clampf(v / 0.72, 0.0, 1.0) * TAU)
	_pk(rig, "root", Vector3(0, h * u * arc, 0))
	_rk(rig, "root", 0.0, (_rand(b * 7 + 5) - 0.5) * 0.5 * _ease_io(clampf(v * 2.0, 0.0, 1.0)))
	_rk(rig, "spine", 0.75 * fold)
	_rk(rig, "body", -0.30 * fold)
	_rk(rig, "neck", 0.20 * fold + 0.15)
	_rk(rig, "head", -0.20 * fold, 0.35 * sin(f * 1.3))
	for i in 4:
		var front := i < 2
		_ri(rig, "legs", i, (0.50 - 0.90 * fold) * (1.0 if front else -1.0))
		_ri(rig, "knees", i, -0.50 - 0.45 * maxf(0.0, fold))
	_rk(rig, "tail", -0.35 - 0.30 * fold, 0.25 * sin(f * TAU * 0.5))
	_ears(rig, 0.0)


static func _tree_spiral(rig: Dictionary, t: float, u: float) -> void:
	## Up the trunk in a corkscrew. A fisher can also come DOWN one head first,
	## which nothing else in the woods can do, but that is a different clip.
	var on := _ease_io(_seg(t, 0.0, 0.12))
	_rk(rig, "root", 0.0, TAU * 0.85 * _ease_io(t) * on)
	_pk(rig, "root", Vector3(0.30 * u * sin(t * TAU * 0.85) * on,
		1.30 * u * _ease_io(t) * on, 0.30 * u * (cos(t * TAU * 0.85) - 1.0) * on))
	_rk(rig, "body", 1.25 * on, 0.0, 0.20 * on)
	_rk(rig, "spine", -0.20 * sin(t * TAU * 4.0) * on)
	var ph := t * TAU * 4.0
	for i in 4:
		var side := -1.0 if i % 2 == 0 else 1.0
		var reach := sin(ph + (0.0 if (i == 0 or i == 3) else PI))
		_ri(rig, "legs", i, (0.70 + 0.65 * reach) * on, 0.0, side * 0.30 * on)
		_ri(rig, "knees", i, (-0.45 - 0.45 * maxf(0.0, -reach)) * on)
	_rk(rig, "neck", 0.30 * on)
	_rk(rig, "head", 0.10 * on, 0.40 * sin(ph * 0.25) * on)
	_rk(rig, "tail", 0.45 * on, 0.35 * sin(ph * 0.5) * on)


static func _porc_flip(rig: Dictionary, t: float, u: float) -> void:
	## The trick nothing else does: dart in low, get under the quills, and turn
	## the porcupine over. Fishers are the only reason porcupine populations in
	## this state are a number and not a curve.
	var dart := _ease_in(_seg(t, 0.0, 0.24))
	var duck := _ease_io(_seg(t, 0.22, 0.38))
	var flip := _snap(_seg(t, 0.40, 0.52))
	var out := _ease_out(_seg(t, 0.58, 0.86))
	_pk(rig, "root", Vector3(0, -0.14 * u * duck + 0.22 * u * flip - 0.10 * u * out,
		-0.55 * u * dart + 0.75 * u * out))
	_rk(rig, "root", 0.0, 2.6 * out)
	_rk(rig, "body", -0.30 * duck + 0.95 * flip - 0.40 * out, 0.0, 0.35 * flip)
	_rk(rig, "spine", 0.50 * duck - 0.60 * flip)
	## Both forelegs come up together for the toss.
	for i in 2:
		_ri(rig, "legs", i, -0.40 * duck + 1.45 * flip - 0.30 * out)
		_ri(rig, "knees", i, -0.80 * duck - 0.20 * flip)
	for i in range(2, 4):
		_ri(rig, "legs", i, 0.55 * duck - 0.70 * flip + 0.40 * out)
		_ri(rig, "knees", i, -0.90 * duck)
	_rk(rig, "neck", -0.55 * duck + 0.85 * flip)
	_rk(rig, "head", -0.30 * duck + 0.50 * flip, 0.30 * out)
	_jaw_open(rig, 0.70 * flip)
	_rk(rig, "tail", -0.30 * duck - 0.60 * flip, 0.40 * out)
	_ears(rig, 0.85 * duck)


static func _bank_slide(rig: Dictionary, t: float, u: float) -> void:
	## Otters do this for no reason at all, repeatedly, and the joy is in the
	## first fifteen percent — a deliberate two-legged kick-off — and then in
	## the fact that absolutely nothing moves for the rest of the slide.
	var kick := _pulse(t, 0.09, 0.09)
	var down := _ease_out(_seg(t, 0.10, 0.32))
	var slide := _seg(t, 0.30, 1.0)
	_pk(rig, "root", Vector3(0, -0.16 * u * down + 0.06 * u * kick, 0))
	## Belly flat, forelegs tucked BACK along the flanks, and a forward tilt
	## that says the whole animal is on a slope.
	_rk(rig, "body", -0.35 * down + 0.10 * kick, 0.0, 0.06 * sin(slide * TAU * 1.2) * down)
	_sk(rig, "body", Vector3(1.0 + 0.16 * down, 1.0 - 0.26 * down, 1.0 + 0.06 * down))
	_rk(rig, "spine", 0.18 * down)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "legs", i, -1.30 * down + 0.55 * kick, 0.0, side * 0.20 * down)
		_ri(rig, "knees", i, -0.30 * down)
	for i in range(2, 4):
		_ri(rig, "legs", i, -0.80 * down + 1.10 * kick)
		_ri(rig, "knees", i, -0.25 * down - 0.60 * kick)
	_rk(rig, "neck", 0.35 * down)
	_rk(rig, "head", 0.15 * down, 0.18 * sin(slide * TAU * 0.8))
	_jaw_open(rig, 0.18 * down)
	_rk(rig, "tail", -0.15 * down, 0.20 * sin(slide * TAU * 1.4) * down)


static func _porpoise(rig: Dictionary, t: float, u: float) -> void:
	## The swimming arc — up through the surface, over, and under again, with
	## everything tucked. Three otters doing this in a line is the single best
	## thing in the river.
	var ph := t * TAU
	_pk(rig, "root", Vector3(0, 0.34 * u * sin(ph), 0))
	_rk(rig, "body", 0.55 * cos(ph))
	_rk(rig, "spine", -0.30 * cos(ph))
	_rk(rig, "neck", 0.25 * cos(ph))
	_rk(rig, "head", 0.10 * cos(ph))
	for i in 4:
		_ri(rig, "legs", i, (0.75 if i < 2 else -0.60))
		_ri(rig, "knees", i, -0.85)
	_rk(rig, "tail", -0.30 - 0.45 * cos(ph))
	_rk(rig, "tail2", -0.20 * cos(ph))


static func _fish_toss(rig: Dictionary, t: float, u: float) -> void:
	## On its back, working a fish between both forepaws. The otter is not
	## eating it yet — it is playing with it, which is the whole species.
	var roll := _ease_io(_seg(t, 0.0, 0.18)) * (1.0 - _ease_io(_seg(t, 0.88, 1.0)))
	_rk(rig, "root", 0.0, 0.0, 1.45 * roll)
	_pk(rig, "root", Vector3(0, -0.12 * u * roll, 0))
	var ph := t * TAU * 3.0
	for i in 2:
		_ri(rig, "legs", i, (0.95 + 0.45 * sin(ph + float(i) * PI)) * roll)
		_ri(rig, "knees", i, (-0.70 - 0.40 * sin(ph + float(i) * PI)) * roll)
	for i in range(2, 4):
		_ri(rig, "legs", i, -0.30 * roll + 0.20 * sin(ph * 0.4 + float(i)))
		_ri(rig, "knees", i, -0.50 * roll)
	_rk(rig, "neck", 0.45 * roll)
	_rk(rig, "head", -0.35 * roll + 0.12 * sin(ph), 0.20 * sin(ph * 0.5))
	_jaw_open(rig, 0.20 + 0.18 * maxf(0.0, sin(ph)) * roll)
	_rk(rig, "tail", -0.25 * roll, 0.40 * sin(ph * 0.5))
	_rk(rig, "spine", 0.15 * sin(ph * 0.5) * roll)


static func _otter_row(rig: Dictionary, t: float, u: float) -> void:
	## Sculling along on its back with the head up out of the water. All the
	## drive is in the hind legs; the forepaws are folded on the chest like a
	## man in a bath.
	var roll := _ease_io(_seg(t, 0.0, 0.15))
	_rk(rig, "root", 0.0, 0.0, 1.30 * roll)
	_pk(rig, "root", Vector3(0, -0.10 * u * roll, 0))
	var ph := t * TAU * 2.2
	for i in 2:
		_ri(rig, "legs", i, 1.15 * roll, 0.0, (-0.25 if i == 0 else 0.25) * roll)
		_ri(rig, "knees", i, -1.30 * roll)
	for i in range(2, 4):
		var a := ph + (0.0 if i == 2 else PI)
		_ri(rig, "legs", i, (0.30 + 0.75 * sin(a)) * roll)
		_ri(rig, "knees", i, (-0.40 - 0.55 * maxf(0.0, cos(a))) * roll)
	_rk(rig, "neck", 0.55 * roll)
	_rk(rig, "head", -0.30 * roll, 0.30 * sin(t * TAU * 0.6))
	_rk(rig, "spine", 0.10 * sin(ph) * roll)
	_rk(rig, "tail", -0.20 * roll, 0.55 * sin(ph * 0.5) * roll)
	_rk(rig, "tail2", 0.0, 0.40 * sin(ph * 0.5 - 0.7) * roll)


## ========================= PORCUPINE & SKUNK ==============================


static func _quill_bristle(rig: Dictionary, t: float, u: float) -> void:
	## The silhouette doubles. That IS the warning — one transform on the quill
	## node rather than two hundred boxes animating, exactly as CritterRig
	## built it for. Reached in a fifth of a second and then HELD.
	var on := _overshoot(_seg(t, 0.0, 0.22), 2.2)
	_sk(rig, "quills", Vector3(1.0 + 1.15 * on, 1.0 + 1.45 * on, 1.0 + 1.15 * on))
	_pk(rig, "quills", Vector3(0, 0.05 * u * on, 0))
	## Hunched, so the back is the biggest thing you can see.
	_rk(rig, "body", -0.22 * on)
	_sk(rig, "body", Vector3(1.0, 1.0 + 0.12 * on, 1.0 - 0.05 * on))
	_pk(rig, "root", Vector3(0, -0.05 * u * on, 0))
	## Head turned away and down — a porcupine presents its back and its
	## opinion of you is that you are not worth watching.
	_rk(rig, "neck", -0.50 * on, 0.40 * on)
	_rk(rig, "head", -0.20 * on, 0.45 * on)
	_rk(rig, "tail", -0.85 * on, 0.15 * sin(t * TAU * 2.0) * on)
	_ears(rig, 0.9 * on)


static func _tail_swat(rig: Dictionary, t: float, u: float) -> void:
	## Backwards, and fast. A porcupine cannot throw quills but it can put a
	## hundred of them into your leg with a tail it swings like a bat.
	var wind := _ease_io(_seg(t, 0.0, 0.34))
	var whip := _snap(_seg(t, 0.34, 0.48))
	var back := _ease_io(_seg(t, 0.55, 1.0))
	var swing := wind - whip * 1.6 + back * 0.6
	_rk(rig, "tail", 0.45 * wind - 0.95 * whip + 0.30 * back, 0.65 * swing)
	_sk(rig, "quills", Vector3(1.6, 1.9, 1.6))
	_rk(rig, "body", -0.10 * wind, -0.20 * swing * 0.4, 0.12 * swing)
	_pk(rig, "root", Vector3(0, -0.03 * u * wind, 0))
	_rk(rig, "neck", -0.35 * wind, -0.30 * swing)
	_rk(rig, "head", -0.15 * wind, -0.40 * swing)
	for i in 4:
		_ri(rig, "legs", i, 0.0, 0.0, (-0.12 if i % 2 == 0 else 0.12) * wind)
		_ri(rig, "knees", i, -0.20 * wind)


static func _limb_nap(rig: Dictionary, t: float, u: float) -> void:
	## Draped over a branch, asleep, twelve metres up. Ninety percent of
	## porcupine sightings in this game are this pose, seen from below, and
	## mistaken for a burl.
	var on := _ease_io(_seg(t, 0.0, 0.18))
	_pk(rig, "root", Vector3(0, -0.10 * u * on, 0))
	_rk(rig, "body", 0.10 * on, 0.0, 0.22 * on)
	_sk(rig, "body", Vector3(1.0 + 0.10 * on, 1.0 - 0.14 * on, 1.0))
	_sk(rig, "quills", Vector3(1.0 - 0.15 * on, 1.0 - 0.20 * on, 1.0 - 0.15 * on))
	_rk(rig, "neck", -0.55 * on, 0.25 * on)
	_rk(rig, "head", -0.35 * on, 0.20 * on, 0.30 * on)
	## All four legs hang. Nothing is holding on; it is simply too wide to fall.
	for i in 4:
		var side := -1.0 if i % 2 == 0 else 1.0
		_ri(rig, "legs", i, (0.30 if i < 2 else -0.25) * on, 0.0, side * 0.55 * on)
		_ri(rig, "knees", i, -0.25 * on)
	_rk(rig, "tail", 0.55 * on, 0.10 * sin(t * TAU * 0.4))
	## One very slow breath. This is the only thing moving.
	_pk(rig, "body", Vector3(0, 0.010 * u * sin(t * TAU * 1.2) * on, 0))


static func _waddle(rig: Dictionary, t: float, u: float) -> void:
	## The low roll. All of the motion is lateral — a porcupine or an opossum
	## rocks over each planted foot instead of bobbing, and the near-total lack
	## of vertical is what makes it read as heavy and slow.
	var ph := t * TAU * 2.0
	_rk(rig, "body", 0.0, 0.10 * sin(ph), 0.20 * sin(ph))
	_pk(rig, "body", Vector3(0.06 * u * sin(ph), 0.008 * u * absf(sin(ph * 2.0)), 0))
	_walk_legs(rig, ph, 0.28, 0.14)
	_rk(rig, "neck", -0.20, 0.14 * sin(ph * 0.5))
	_rk(rig, "head", 0.10 + 0.05 * sin(ph * 2.0), 0.20 * sin(ph * 0.5))
	_rk(rig, "tail", 0.10, 0.28 * sin(ph + 0.8))
	_ears(rig, 0.15)


static func _foot_stamp(rig: Dictionary, t: float, u: float) -> void:
	## Both forefeet, twice, fast. This is stage one of four and a player who
	## learns to leave at stage one saves themselves a lot of trouble.
	var d1 := _seg(t, 0.05, 0.28)
	var d2 := _seg(t, 0.42, 0.65)
	var drum := sin(d1 * TAU * 2.0) * _tri(d1) + sin(d2 * TAU * 2.0) * _tri(d2)
	for i in 2:
		_ri(rig, "legs", i, 0.55 * maxf(0.0, drum) * (1.0 if i == 0 else -1.0) + 0.28 * absf(drum))
		_ri(rig, "knees", i, -0.75 * absf(drum))
	_pk(rig, "root", Vector3(0, 0.02 * u * absf(drum), 0))
	_rk(rig, "body", -0.14 * absf(drum), 0.0, 0.06 * drum)
	_rk(rig, "neck", -0.25)
	_rk(rig, "head", 0.30, 0.10 * drum)
	_rk(rig, "tail", -0.55 * _ease_out(_seg(t, 0.55, 1.0)))
	_ears(rig, 0.30)


static func _tail_up(rig: Dictionary, t: float, u: float) -> void:
	## Stage two. Tail vertical, held, and the body squared onto you so that
	## the two white stripes are as wide as they can possibly be.
	var on := _overshoot(_seg(t, 0.0, 0.25), 2.0)
	_rk(rig, "tail", -2.30 * on)
	_rk(rig, "tail2", -0.40 * on)
	_sk(rig, "tail", Vector3(1.0 + 0.35 * on, 1.0, 1.0))
	_rk(rig, "body", 0.0, 0.30 * on, 0.0)
	_pk(rig, "root", Vector3(0, -0.03 * u * on, 0))
	_rk(rig, "neck", -0.20 * on, -0.45 * on)
	_rk(rig, "head", 0.25 * on, -0.55 * on)     ## still watching you over its back
	_ears(rig, 0.20)


static func _u_pose(rig: Dictionary, t: float, u: float) -> void:
	## Stage three: the body bends into a U so the head AND the business end
	## both face you at once. A skunk will not spray something it cannot see.
	var on := _ease_out(_seg(t, 0.0, 0.35))
	_rk(rig, "root", 0.0, 0.55 * on)
	_rk(rig, "body", 0.0, 0.85 * on, 0.10 * on)
	_rk(rig, "tail", -2.30 * on, -0.75 * on)
	_sk(rig, "tail", Vector3(1.0 + 0.35 * on, 1.0, 1.0))
	## Head cranes back the other way. This is the pose, and it is genuinely
	## how the animal is shaped for the two seconds before it fires.
	_rk(rig, "neck", -0.15 * on, -1.35 * on)
	_rk(rig, "head", 0.20 * on, -0.75 * on, 0.25 * on)
	_pk(rig, "root", Vector3(0, -0.04 * u * on, 0))
	for i in 4:
		_ri(rig, "legs", i, 0.0, 0.0, (-0.18 if i % 2 == 0 else 0.18) * on)
		_ri(rig, "knees", i, -0.22 * on)
	_ears(rig, 0.45 * on)


static func _spray(rig: Dictionary, t: float, u: float) -> void:
	## The whole escalation in one clip: stamps, tail, U, fire. Four seconds of
	## increasingly unambiguous warning followed by the least ambiguous thing
	## in the game.
	var stamp := _seg(t, 0.0, 0.25)
	var drum := sin(stamp * TAU * 3.0) * _tri(stamp) * (1.0 - _seg(t, 0.22, 0.28))
	var tail := _ease_out(_seg(t, 0.25, 0.45))
	var bend := _ease_out(_seg(t, 0.45, 0.68))
	var fire := _pulse(t, 0.74, 0.05)
	var recoil := _bounce(_seg(t, 0.74, 0.90), 4.5, 9.0)
	var relax := _ease_io(_seg(t, 0.90, 1.0))
	var hold := 1.0 - relax * 0.7

	for i in 2:
		_ri(rig, "legs", i, 0.30 * absf(drum) + 0.50 * maxf(0.0, drum) * (1.0 if i == 0 else -1.0))
		_ri(rig, "knees", i, -0.70 * absf(drum))
	_pk(rig, "root", Vector3(0, 0.02 * u * absf(drum) - 0.04 * u * bend, 0.08 * u * fire))
	## Tail up at 0.25, and it does not come down again.
	_rk(rig, "tail", (-2.30 - 0.25 * recoil) * tail * hold, -0.75 * bend * hold)
	_sk(rig, "tail", Vector3(1.0 + 0.40 * tail, 1.0, 1.0))
	_rk(rig, "root", 0.0, 0.55 * bend * hold)
	_rk(rig, "body", -0.10 * absf(drum) + 0.18 * fire, 0.85 * bend * hold, 0.08 * recoil)
	_rk(rig, "neck", -0.15 * bend * hold, -1.35 * bend * hold)
	_rk(rig, "head", 0.22 * bend * hold, -0.75 * bend * hold, 0.25 * bend * hold)
	_sk(rig, "body", Vector3(1.0 - 0.06 * fire, 1.0 - 0.05 * fire, 1.0 + 0.10 * fire))
	_ears(rig, 0.45 * bend)


## =============================== RACCOON ==================================


static func _camp_case(rig: Dictionary, t: float, u: float) -> void:
	## Casing the camp: a slow circling approach with the nose down and three
	## freezes in it. The freezes are the raccoon deciding whether you are
	## asleep, and they are what make it feel deliberate rather than random.
	var freeze := _pulse(t, 0.22, 0.07) + _pulse(t, 0.55, 0.08) + _pulse(t, 0.84, 0.07)
	var move := 1.0 - clampf(freeze, 0.0, 1.0) * 0.95
	_rk(rig, "root", 0.0, 1.1 * _ease_io(t))
	_pk(rig, "root", Vector3(0.5 * u * sin(t * PI), 0, 0.35 * u * (cos(t * PI) - 1.0)))
	_walk_legs(rig, t * TAU * 3.0 * move, 0.30 * move, 0.16 * move)
	## Nose down while moving, head UP and locked while frozen.
	_rk(rig, "neck", -0.42 * move + 0.35 * freeze)
	_rk(rig, "head", -0.10 * move + 0.30 * freeze, 0.35 * sin(t * TAU * 1.3) * move)
	_ears(rig, -0.05, 0.25 * freeze)
	_rk(rig, "body", 0.0, 0.08 * sin(t * TAU * 3.0) * move, 0.10 * sin(t * TAU * 3.0) * move)
	_rk(rig, "tail", -0.20 - 0.25 * freeze, 0.20 * sin(t * TAU * 1.5) * move)


static func _unlatch(rig: Dictionary, t: float, u: float) -> void:
	## The hands. Both forepaws working a latch in small precise alternating
	## motions with the head cocked to listen to it, and then one pull that
	## opens the thing. Raccoons in this game will get into anything the
	## player has not actually locked.
	var work := _seg(t, 0.05, 0.80)
	var sit := _ease_out(_seg(t, 0.0, 0.14))
	var ph := work * TAU * 5.0
	_rk(rig, "body", 0.55 * sit)
	_pk(rig, "root", Vector3(0, -0.05 * u * sit, 0))
	for i in 2:
		_ri(rig, "legs", i, (1.05 + 0.30 * sin(ph + float(i) * 2.1)) * sit,
			0.0, (0.20 * sin(ph * 0.7 + float(i))) * sit)
		_ri(rig, "knees", i, (-0.55 - 0.35 * sin(ph + float(i) * 2.1)) * sit)
	for i in range(2, 4):
		_ri(rig, "legs", i, 0.45 * sit)
		_ri(rig, "knees", i, -0.75 * sit)
	## Head cocked over the work, not looking at it — it is doing this by feel.
	_rk(rig, "neck", -0.20 * sit, 0.20 * sit)
	_rk(rig, "head", -0.15 * sit, 0.25 * sit, 0.45 * sit)
	## The pull.
	var pull := _snap(_seg(t, 0.82, 0.90))
	for i in 2:
		_ri(rig, "legs", i, (1.05 - 1.30 * pull) * sit)
	_rk(rig, "body", 0.55 * sit + 0.30 * pull)
	_rk(rig, "tail", -0.30 * sit, 0.25 * sin(t * TAU * 1.1))


static func _rummage(rig: Dictionary, t: float, u: float) -> void:
	## Head buried to the shoulders, both arms working, tail up for balance,
	## and every four seconds a lift-and-listen. The listen is the part that
	## makes it feel like an animal with a plan.
	var lift := _pulse(t, 0.46, 0.09) + _pulse(t, 0.92, 0.08)
	var inside := 1.0 - clampf(lift, 0.0, 1.0)
	var ph := t * TAU * 4.0
	_rk(rig, "body", -0.35 * inside + 0.20 * lift, 0.10 * sin(ph * 0.5))
	_rk(rig, "neck", -0.90 * inside + 0.55 * lift)
	_rk(rig, "head", -0.25 * inside + 0.25 * lift, 0.30 * sin(ph * 0.33))
	_pk(rig, "neck", Vector3(0, 0, -0.06 * u * inside))
	for i in 2:
		_ri(rig, "legs", i, (0.85 + 0.45 * sin(ph + float(i) * 2.4)) * inside)
		_ri(rig, "knees", i, (-0.60 - 0.40 * sin(ph + float(i) * 2.4)) * inside)
	for i in range(2, 4):
		_ri(rig, "legs", i, -0.20 * inside)
		_ri(rig, "knees", i, -0.35 * inside)
	_rk(rig, "tail", -0.85 * inside, 0.30 * sin(ph * 0.4))
	_ears(rig, -0.10, 0.30 * lift)
	_pk(rig, "root", Vector3(0, -0.04 * u * inside, 0))


static func _food_wash(rig: Dictionary, t: float, u: float) -> void:
	## Sat up with both forepaws scrubbing something in front of it. Raccoons
	## are not washing it — they are feeling it, because those hands have more
	## nerve endings than their eyes have use. The hands are the whole clip:
	## everything else holds still and lets them work.
	var sit := _ease_out(_seg(t, 0.0, 0.15))
	var ph := t * TAU * 4.5
	_rk(rig, "body", 0.62 * sit)
	_pk(rig, "root", Vector3(0, -0.06 * u * sit, 0))
	for i in 2:
		var o := float(i) * PI
		_ri(rig, "legs", i, (1.10 + 0.28 * sin(ph + o)) * sit, 0.25 * cos(ph + o) * sit,
			(0.30 * sin(ph * 0.5 + o)) * sit)
		_ri(rig, "knees", i, (-0.70 + 0.30 * cos(ph + o)) * sit)
	for i in range(2, 4):
		_ri(rig, "legs", i, 0.50 * sit)
		_ri(rig, "knees", i, -0.85 * sit)
	_rk(rig, "neck", -0.35 * sit)
	_rk(rig, "head", -0.20 * sit + 0.04 * sin(ph), 0.10 * sin(ph * 0.25))
	_jaw_open(rig, 0.10 * maxf(0.0, sin(ph * 0.5)) * sit)
	_rk(rig, "tail", -0.15 * sit, 0.15 * sin(t * TAU * 0.8))


static func _mask_stare(rig: Dictionary, t: float, u: float) -> void:
	## The head comes up, locks onto you, and does not move again. Then, once,
	## it tilts. Nothing else in the file is this still and that is exactly why
	## it is unsettling at two in the morning by a campfire.
	var up := _snap(_seg(t, 0.0, 0.12))
	var tilt := _ease_io(_seg(t, 0.55, 0.68))
	_still(rig)
	_rk(rig, "neck", 0.42 * up)
	_rk(rig, "head", 0.10 * up, 0.0, 0.55 * tilt)
	_ears(rig, -0.12 * up)
	_pk(rig, "root", Vector3(0, 0.02 * u * up, 0))
	_rk(rig, "body", -0.08 * up)
	for i in 4:
		_ri(rig, "legs", i, 0.0)
		_ri(rig, "knees", i, -0.12 * up)
	_rk(rig, "tail", -0.15 * up)


## ========================= BEAVER & THE BOG ===============================


static func _tail_slap(rig: Dictionary, t: float, u: float) -> void:
	## Matched to beaver_slap.wav. Everything before the impact is loading and
	## everything after it is water — the slap itself is one frame, and if it
	## takes two it stops sounding like a gunshot and starts looking like a
	## paddle being lowered.
	var rear := _ease_out(_seg(t, 0.0, 0.42))
	var lift := _ease_out(_seg(t, 0.08, 0.45))
	var slam := _snap(_seg(t, 0.45, 0.52))
	var ring := _seg(t, 0.52, 1.0)
	_rk(rig, "tail", -1.60 * lift + 2.15 * slam)
	_rk(rig, "body", 0.38 * rear - 0.50 * slam + 0.10 * _bounce(ring, 4.0, 8.0))
	_pk(rig, "root", Vector3(0, 0.10 * u * rear - 0.15 * u * slam
		+ 0.05 * u * _bounce(ring, 5.0, 9.0), 0))
	for i in 2:
		_ri(rig, "legs", i, -0.60 * rear + 0.70 * slam)
		_ri(rig, "knees", i, -0.40 * rear)
	for i in range(2, 4):
		_ri(rig, "legs", i, 0.45 * rear - 0.30 * slam)
		_ri(rig, "knees", i, -0.55 * rear)
	_rk(rig, "neck", 0.32 * rear - 0.35 * slam)
	_rk(rig, "head", 0.12 * rear - 0.20 * slam, 0.15 * sin(ring * TAU))
	_ears(rig, 0.40 * slam)


static func _gnaw_ring(rig: Dictionary, t: float, u: float) -> void:
	## Cutting a ring around a trunk. Head cocked, incisors working at seven a
	## second, and the whole animal creeping slowly around the tree — that
	## orbit is why the cut comes out as a ring and not a notch.
	var on := _ease_io(_seg(t, 0.0, 0.10))
	var orbit := _ease_io(t) * on
	_rk(rig, "root", 0.0, 0.95 * orbit)
	_pk(rig, "root", Vector3(0.35 * u * sin(0.95 * orbit),
		0, 0.35 * u * (1.0 - cos(0.95 * orbit))))
	_rk(rig, "body", 0.35 * on)
	_rk(rig, "neck", -0.15 * on, 0.15 * on)
	## The cock of the head is the tell — a beaver gnaws sideways.
	_rk(rig, "head", 0.05 * on, 0.20 * on, 0.55 * on)
	var chew := t * TAU * 7.0
	_jaw_open(rig, (0.16 + 0.16 * (0.5 + 0.5 * sin(chew))) * on)
	_pk(rig, "head", Vector3(0, 0.012 * u * sin(chew) * on, -0.012 * u * sin(chew) * on))
	for i in 2:
		_ri(rig, "legs", i, (0.95 + 0.10 * sin(chew * 0.5)) * on, 0.0,
			(-0.25 if i == 0 else 0.25) * on)
		_ri(rig, "knees", i, -0.70 * on)
	for i in range(2, 4):
		_ri(rig, "legs", i, 0.35 * on)
		_ri(rig, "knees", i, -0.60 * on)
	_rk(rig, "tail", 0.30 * on, 0.15 * sin(t * TAU * 0.8))


static func _log_drag(rig: Dictionary, t: float, u: float) -> void:
	## Hauling a limb backwards to the pond, which is how every beaver canal in
	## the game got there. The heave is on a four-second cycle: brace, pull,
	## step back, repeat, and the head stays high because the load is in the
	## teeth.
	var ph := t * TAU * 1.6
	var heave := maxf(0.0, sin(ph))
	_rk(rig, "body", 0.30 + 0.22 * heave)
	_pk(rig, "body", Vector3(0, 0, 0.10 * u * heave))
	_pk(rig, "root", Vector3(0, -0.03 * u * heave, 0.10 * u * _ease_io(t)))
	_rk(rig, "neck", 0.50 + 0.15 * heave)
	_rk(rig, "head", -0.30 - 0.10 * heave, 0.08 * sin(ph * 0.5))
	_jaw_open(rig, 0.22)
	for i in 2:
		_ri(rig, "legs", i, -0.35 - 0.45 * heave, 0.0, (-0.18 if i == 0 else 0.18))
		_ri(rig, "knees", i, 0.25 + 0.30 * heave)
	for i in range(2, 4):
		var a := ph + (0.0 if i == 2 else PI)
		_ri(rig, "legs", i, -0.30 * sin(a) - 0.20)
		_ri(rig, "knees", i, -0.45 - 0.30 * maxf(0.0, cos(a)))
	_rk(rig, "tail", 0.20, 0.30 * sin(ph * 0.5))


static func _lodge_dive(rig: Dictionary, t: float, u: float) -> void:
	## A forward roll into the water with the paddle going over last. No
	## splash worth the name — beavers enter water the way other animals leave
	## a room.
	var tip := _ease_in(_seg(t, 0.0, 0.35))
	var down := _ease_in(_seg(t, 0.25, 0.80))
	var gone := _seg(t, 0.75, 1.0)
	_rk(rig, "body", -1.20 * tip)
	_pk(rig, "root", Vector3(0, -0.85 * u * down - 0.35 * u * gone, -0.25 * u * tip))
	_rk(rig, "neck", -0.30 * tip)
	_rk(rig, "head", -0.20 * tip)
	for i in 4:
		_ri(rig, "legs", i, (0.60 if i < 2 else -0.70) * tip)
		_ri(rig, "knees", i, -0.50 * tip)
	## The tail is the last thing over and it flips up as it goes.
	_rk(rig, "tail", -1.30 * _ease_out(_seg(t, 0.35, 0.70)) + 0.60 * gone)


static func _swim_wake(rig: Dictionary, t: float, u: float) -> void:
	## Only the head and a hand's width of back above water, a steady tail
	## scull, and a slow bow-wave nod. Everything below the waterline is
	## sunk out of sight, which is why the body drops rather than the legs
	## paddling.
	var ph := t * TAU * 1.8
	_pk(rig, "root", Vector3(0, -0.30 * u, 0))
	_rk(rig, "body", -0.10 + 0.05 * sin(ph * 0.5), 0.08 * sin(ph * 0.5))
	_rk(rig, "neck", 0.35 + 0.05 * sin(ph))
	_rk(rig, "head", 0.05 + 0.04 * sin(ph), 0.25 * sin(ph * 0.33))
	_rk(rig, "tail", 0.10, 0.45 * sin(ph))
	_rk(rig, "tail2", 0.0, 0.30 * sin(ph - 0.7))
	for i in 4:
		var a := ph + float(i) * 1.6
		_ri(rig, "legs", i, 0.25 * sin(a) - 0.30)
		_ri(rig, "knees", i, -0.35)
	_ears(rig, 0.0)


## =========================== OPOSSUM & FIELD ==============================


static func _play_dead(rig: Dictionary, t: float, u: float) -> void:
	## Twelve seconds, eight of which are nothing at all. That is the joke and
	## the animal: an opossum's defence is to become furniture and wait you
	## out. It is involuntary, so the collapse is a FALL — not a lie-down —
	## and the waking is a slow reboot from the head backwards.
	var fall := _ease_in(_seg(t, 0.0, 0.06))
	var settle := _seg(t, 0.06, 0.14)
	var stiff := _ease_out(_seg(t, 0.05, 0.13))
	var wake := _ease_io(_seg(t, 0.86, 0.93))
	var up := _ease_io(_seg(t, 0.93, 1.0))
	var dead := clampf(fall - up, 0.0, 1.0)
	var rigid := stiff * (1.0 - up)
	## Nothing may breathe while this runs. idle() has already written a chest
	## rise this frame and it has to go.
	_still(rig)
	_rk(rig, "root", 0.0, 0.0, 1.48 * dead + 0.09 * _bounce(settle, 3.0, 8.0) * (1.0 - up))
	_pk(rig, "root", Vector3(0, -0.24 * u * dead, 0))
	## Legs out straight and locked. Bent legs read as asleep; straight ones
	## read as wrong, and wrong is the entire performance.
	for i in 4:
		var side := -1.0 if i % 2 == 0 else 1.0
		_ri(rig, "legs", i, (1.05 if i < 2 else -0.95) * rigid, 0.0, side * 0.25 * rigid)
		_ri(rig, "knees", i, 0.12 * rigid)
	## Jaw hangs and the tongue lolls out. The tongue is the jaw pivot pushed
	## forward — one box, and it does the entire job.
	_jaw_open(rig, 0.78 * rigid)
	_pk(rig, "jaw", Vector3(0, 0, -0.07 * u * rigid))
	_rk(rig, "neck", -0.28 * rigid, 0.45 * rigid - 0.20 * wake * (1.0 - up))
	_rk(rig, "head", -0.20 * rigid + 0.62 * wake * (1.0 - up), 0.30 * rigid, 0.35 * rigid)
	_rk(rig, "tail", 0.20 * rigid)
	_ears(rig, 0.90 * rigid)


static func _hiss_gape(rig: Dictionary, t: float, u: float) -> void:
	## Fifty teeth, all of them visible, and none of them any use. The opossum
	## opens its mouth as wide as a jaw can open and shivers, and that is the
	## whole defence before it falls over.
	var on := _ease_out(_seg(t, 0.0, 0.12)) * (1.0 - _ease_io(_seg(t, 0.86, 1.0)))
	var shiver := sin(t * TAU * 11.0) * on
	_jaw_open(rig, 1.15 * on)
	_rk(rig, "neck", -0.30 * on + 0.01 * shiver)
	_rk(rig, "head", 0.18 * on + 0.02 * shiver, 0.03 * shiver)
	_pk(rig, "neck", Vector3(0, 0, -0.08 * u * on))
	_pk(rig, "root", Vector3(0.004 * u * shiver, -0.06 * u * on, 0))
	_rk(rig, "body", -0.12 * on, 0.0, 0.02 * shiver)
	for i in 4:
		_ri(rig, "legs", i, 0.0, 0.0, (-0.20 if i % 2 == 0 else 0.20) * on)
		_ri(rig, "knees", i, -0.35 * on)
	_rk(rig, "tail", 0.30 * on, 0.10 * shiver)
	_ears(rig, 0.75 * on)


static func _periscope(rig: Dictionary, t: float, u: float) -> void:
	## Straight up on the hind legs to full stretch, forepaws folded at the
	## chest, one unhurried scan. A woodchuck is a marmot and this is the pose
	## the whole family is famous for.
	var up := _ease_out(_seg(t, 0.0, 0.28))
	var down := _ease_io(_seg(t, 0.88, 1.0))
	var on := up * (1.0 - down)
	_rk(rig, "body", 1.35 * on)
	_pk(rig, "root", Vector3(0, 0.10 * u * on, 0))
	for i in 2:
		_ri(rig, "legs", i, (1.20) * on, 0.0, (-0.30 if i == 0 else 0.30) * on)
		_ri(rig, "knees", i, -1.05 * on)
	for i in range(2, 4):
		_ri(rig, "legs", i, 0.35 * on)
		_ri(rig, "knees", i, -0.20 * on)
	## One slow scan, and then it holds — the holding is what makes it a
	## sentinel rather than a fidget.
	_rk(rig, "neck", 0.20 * on)
	_rk(rig, "head", -0.05 * on, 0.85 * sin(_seg(t, 0.3, 0.8) * PI) * on)
	_ears(rig, -0.05 * on)
	_rk(rig, "tail", 0.30 * on)


static func _whistle(rig: Dictionary, t: float, u: float) -> void:
	## Half a second: everything stops, the head snaps up, one chest pulse.
	## The name whistle-pig is earned right here and the sound carries three
	## hundred metres.
	var snap := _snap(_seg(t, 0.0, 0.10))
	var blow := _pulse(t, 0.24, 0.14)
	_still(rig)
	_rk(rig, "neck", 0.50 * snap)
	_rk(rig, "head", 0.30 * snap + 0.10 * blow)
	_jaw_open(rig, 0.30 * blow)
	_sk(rig, "body", Vector3(1.0 - 0.05 * blow, 1.0 - 0.04 * blow, 1.0 + 0.08 * blow))
	_ears(rig, -0.10 * snap)
	_pk(rig, "root", Vector3(0, 0.02 * u * snap, 0))


static func _burrow_dive(rig: Dictionary, t: float, u: float) -> void:
	## One second flat: a scurry, a head-first vanish, and the hind feet
	## kicking a last spray of dirt out of the hole.
	var run := _seg(t, 0.0, 0.35)
	var dive := _ease_in(_seg(t, 0.30, 0.85))
	_walk_legs(rig, run * TAU * 4.0, 0.50, 0.30)
	_rk(rig, "body", -0.95 * dive)
	_pk(rig, "root", Vector3(0, -1.10 * u * dive, -0.30 * u * dive))
	_rk(rig, "neck", -0.45 * dive)
	_rk(rig, "head", -0.20 * dive)
	## Hind legs are the last thing above ground and they are still running.
	for i in range(2, 4):
		_ri(rig, "legs", i, sin(t * TAU * 9.0 + float(i)) * 0.70 * dive - 0.30 * dive)
		_ri(rig, "knees", i, -0.55 * dive)
	_ears(rig, 0.65 * dive)
	_rk(rig, "tail", -0.40 * dive)


static func _cattail_feed(rig: Dictionary, t: float, u: float) -> void:
	## Sat in the shallows turning a cattail stalk against its teeth like a man
	## with corn on the cob. Muskrats eat five hundred of these a winter and
	## the rotation is the reason the stumps are all cut at a bevel.
	var sit := _ease_out(_seg(t, 0.0, 0.14))
	var ph := t * TAU * 8.0
	_rk(rig, "body", 0.55 * sit)
	_pk(rig, "root", Vector3(0, -0.10 * u * sit, 0))
	for i in 2:
		_ri(rig, "legs", i, (1.15 + 0.06 * sin(ph * 0.25)) * sit, 0.0,
			(-0.22 if i == 0 else 0.22) * sit)
		_ri(rig, "knees", i, -0.80 * sit)
	for i in range(2, 4):
		_ri(rig, "legs", i, 0.40 * sit)
		_ri(rig, "knees", i, -0.80 * sit)
	_rk(rig, "neck", -0.28 * sit)
	_rk(rig, "head", -0.12 * sit, 0.45 * sin(t * TAU * 0.75) * sit, 0.30 * sit)
	_jaw_open(rig, (0.10 + 0.14 * (0.5 + 0.5 * sin(ph))) * sit)
	_rk(rig, "tail", 0.20 * sit, 0.35 * sin(t * TAU * 0.9))


## ================================ SEALS ===================================
## The flippered chunk: `legs` holds two fore-flippers parented to the body and
## `tail` is the hind pair. Nothing here has knees, so every knee call below
## is a deliberate no-op and the guards handle it.


static func _banana_pose(rig: Dictionary, t: float, u: float) -> void:
	## Head AND tail off the rock with the belly still on it. Seals hold this
	## for minutes and it costs them real effort, so the pose is reached early,
	## HELD, and wobbles slightly the whole time it is being held.
	var on := _ease_out(_seg(t, 0.0, 0.25)) * (1.0 - _ease_io(_seg(t, 0.90, 1.0)))
	var wob := sin(t * TAU * 1.6) * 0.05
	_rk(rig, "neck", (0.80 + wob) * on)
	_rk(rig, "head", (0.34 + wob * 0.5) * on, 0.22 * sin(t * TAU * 0.4) * on)
	_rk(rig, "tail", -(0.95 + wob) * on)
	_rk(rig, "body", -0.12 * on)
	_pk(rig, "body", Vector3(0, -0.04 * u * on, 0))
	_sk(rig, "body", Vector3(1.0 + 0.04 * on, 1.0 - 0.05 * on, 1.0))
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "legs", i, 0.25 * on, side * 0.30 * on, side * 0.20 * on)


static func _spy_hop(rig: Dictionary, t: float, u: float) -> void:
	## Straight up out of the water to look at you, hang there, and sink back
	## down without a ripple. Harbour seals are relentlessly curious and this
	## is how the player finds that out.
	var rise := _ease_out(_seg(t, 0.0, 0.25))
	var sink := _ease_in(_seg(t, 0.75, 1.0))
	var up := clampf(rise - sink, 0.0, 1.0)
	_rk(rig, "body", 1.40 * up)
	_pk(rig, "root", Vector3(0, 0.55 * u * up - 0.30 * u * (1.0 - up), 0))
	## The scan is slow and it is the only motion once it is up.
	_rk(rig, "neck", 0.15 * up)
	_rk(rig, "head", -0.10 * up, 0.75 * sin(_seg(t, 0.28, 0.72) * TAU * 0.75) * up)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "legs", i, -0.35 * up, side * 0.55 * up, side * 0.30 * up)
	_rk(rig, "tail", 0.30 * up)


static func _haul_out(rig: Dictionary, t: float, u: float) -> void:
	## Getting a hundred kilos of seal up a rock, which it does by inching:
	## compress, throw the front end forward, drag the back end after it. Four
	## cycles and a settle. On land they are magnificently bad at this.
	var ph := t * TAU * 4.0
	var hump := sin(ph)
	var done := _ease_io(_seg(t, 0.80, 1.0))
	var work := 1.0 - done
	_sk(rig, "body", Vector3(1.0, 1.0 + 0.10 * hump * work, 1.0 - 0.16 * hump * work))
	_pk(rig, "root", Vector3(0, 0.05 * u * maxf(0.0, hump) * work,
		-0.30 * u * _ease_io(t)))
	_rk(rig, "body", (-0.18 * hump) * work + 0.05 * done)
	_rk(rig, "neck", (0.35 + 0.30 * maxf(0.0, hump)) * work + 0.20 * done)
	_rk(rig, "head", (0.10 - 0.15 * hump) * work, 0.20 * sin(ph * 0.25))
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		## The fore-flippers actually push. Everything else is momentum.
		_ri(rig, "legs", i, (-0.55 - 0.60 * hump) * work, side * (0.25 + 0.35 * maxf(0.0, hump)) * work,
			side * 0.20 * work)
	_rk(rig, "tail", (-0.20 + 0.45 * hump) * work)


static func _seal_follow(rig: Dictionary, t: float, u: float) -> void:
	## Just a head, twenty metres out, keeping pace with the player along the
	## shore. It sinks, comes up somewhere slightly different, and is still
	## looking at you. Nothing else in the game does this.
	var sink := _pulse(t, 0.50, 0.14)
	_pk(rig, "root", Vector3(0.25 * u * sin(t * TAU * 0.5), -0.55 * u - 0.35 * u * sink, 0))
	_rk(rig, "body", 0.95)
	## The head tracks continuously; that is the entire point of the clip.
	_rk(rig, "neck", 0.20)
	_rk(rig, "head", -0.05, 0.55 * sin(t * TAU * 0.45))
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "legs", i, -0.30, side * (0.40 + 0.25 * sin(t * TAU * 1.5)), side * 0.20)
	_rk(rig, "tail", 0.20 + 0.20 * sin(t * TAU * 1.5))


## ============================ SMALL RODENTS ===============================


static func _hop(rig: Dictionary, t: float, u: float) -> void:
	## One hop. Hind legs do everything, the front pair land first and take the
	## weight for a moment, and the whole thing is over in seven tenths of a
	## second. Hares do not run, they punctuate.
	var load := _ease_io(_seg(t, 0.0, 0.18))
	var push := _snap(_seg(t, 0.18, 0.28))
	var air := _arc(_seg(t, 0.22, 0.88))
	var land := _seg(t, 0.84, 1.0)
	_pk(rig, "root", Vector3(0, 0.55 * u * air - 0.08 * u * load, 0))
	_rk(rig, "body", 0.30 * push - 0.45 * _ease_in(_seg(t, 0.5, 0.9)) + 0.30 * land)
	for i in 2:
		_ri(rig, "legs", i, -0.30 * load + 0.90 * air + 0.70 * land)
		_ri(rig, "knees", i, -0.70 * load - 0.30 * air + 0.40 * land)
	for i in range(2, 4):
		_ri(rig, "legs", i, 0.95 * load - 1.15 * push - 0.55 * air + 0.80 * land)
		_ri(rig, "knees", i, -1.30 * load + 1.10 * push - 0.30 * air - 0.90 * land)
	_rk(rig, "neck", 0.20 * air)
	## Ears stream back in the air and come up again on the landing.
	_ears(rig, 0.55 * air)
	_rk(rig, "tail", -0.35 * air)


static func _zigzag(rig: Dictionary, t: float, u: float) -> void:
	## The escape. Hard alternating yaw with the body banking into each turn,
	## bounds between them, ears flat. A hare that runs in a straight line is a
	## hare that gets caught, so the direction changes are the animation.
	var cut := sin(t * TAU * 1.5)
	var f := t * 5.0
	var v := fposmod(f, 1.0)
	_rk(rig, "root", 0.0, 0.85 * cut)
	_pk(rig, "root", Vector3(0.45 * u * cut, 0.30 * u * _arc(v), 0))
	_rk(rig, "body", 0.25 * cos(v * TAU) * -1.0, -0.20 * cut, 0.45 * cut)
	for i in 2:
		_ri(rig, "legs", i, 0.55 - 0.85 * cos(v * TAU))
		_ri(rig, "knees", i, -0.55 - 0.35 * maxf(0.0, cos(v * TAU)))
	for i in range(2, 4):
		_ri(rig, "legs", i, -0.60 + 1.05 * cos(v * TAU))
		_ri(rig, "knees", i, -1.10 + 0.70 * cos(v * TAU))
	_ears(rig, 0.95)
	_look(rig, -0.35 * cut, 0.10)
	_rk(rig, "tail", -0.55, 0.30 * cut)


static func _freeze_crouch(rig: Dictionary, t: float, u: float) -> void:
	## Flat in under a tenth of a second, and then nothing whatsoever. A hare's
	## first defence is being a lump of ground, and the player walking past one
	## at two metres is the intended outcome.
	var down := _snap(_seg(t, 0.0, 0.08))
	_still(rig)
	_pk(rig, "root", Vector3(0, -0.16 * u * down, 0))
	_sk(rig, "body", Vector3(1.0 + 0.10 * down, 1.0 - 0.28 * down, 1.0 + 0.06 * down))
	_rk(rig, "body", 0.06 * down)
	_rk(rig, "neck", -0.35 * down)
	_rk(rig, "head", 0.20 * down)
	## Ears go flat along the back — the one part of a hare that gives it away
	## from above, folded out of the silhouette.
	_ears(rig, 1.0 * down)
	for i in 4:
		_ri(rig, "legs", i, (0.35 if i < 2 else -0.30) * down)
		_ri(rig, "knees", i, -0.95 * down)
	_rk(rig, "tail", 0.30 * down)


static func _sit_scan(rig: Dictionary, t: float, u: float) -> void:
	## Up on the haunches, forepaws off the ground, and the two ears rotating
	## INDEPENDENTLY — a hare tracks two things at once and that asymmetry is
	## the whole reason it survives an owl.
	var sit := _ease_out(_seg(t, 0.0, 0.20))
	_rk(rig, "body", 0.85 * sit)
	_pk(rig, "root", Vector3(0, 0.04 * u * sit, 0))
	for i in 2:
		_ri(rig, "legs", i, 1.15 * sit, 0.0, (-0.15 if i == 0 else 0.15) * sit)
		_ri(rig, "knees", i, -0.95 * sit)
	for i in range(2, 4):
		_ri(rig, "legs", i, 0.55 * sit)
		_ri(rig, "knees", i, -1.05 * sit)
	_rk(rig, "neck", 0.10 * sit)
	_rk(rig, "head", -0.10 * sit, 0.45 * sin(t * TAU * 0.6) * sit)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "ears", i, -0.25 * sit, side * (0.55 * sin(t * TAU * (0.7 + 0.5 * float(i)) + float(i) * 2.0)) * sit)
	_rk(rig, "tail", 0.20 * sit)


static func _trunk_spiral(rig: Dictionary, t: float, u: float) -> void:
	## Round the far side of the trunk and stop dead. A squirrel does not flee
	## upward, it flees around, and the freeze on the blind side is the part
	## that infuriates the player holding the bow.
	var run1 := _seg(t, 0.0, 0.34)
	var hide := _pulse(t, 0.52, 0.16)
	var run2 := _seg(t, 0.62, 1.0)
	var spin := (run1 * 2.2 + run2 * 2.6) * (1.0 - hide * 0.5)
	_rk(rig, "root", 0.0, spin)
	_pk(rig, "root", Vector3(0.20 * u * sin(spin), 0.55 * u * _ease_io(t), 0.20 * u * (1.0 - cos(spin))))
	_rk(rig, "body", 1.10 - 0.20 * hide)
	var ph := t * TAU * 7.0
	var scurry := 1.0 - hide
	for i in 4:
		var reach := sin(ph + (0.0 if (i == 0 or i == 3) else PI))
		_ri(rig, "legs", i, (0.65 + 0.70 * reach) * scurry + 0.55 * hide)
		_ri(rig, "knees", i, (-0.45 - 0.45 * maxf(0.0, -reach)) * scurry - 0.60 * hide)
	## The peek: head round the trunk, body still hidden.
	_rk(rig, "neck", 0.15 - 0.20 * hide)
	_rk(rig, "head", 0.05, -1.10 * hide)
	_rk(rig, "tail", -0.30 - 0.55 * hide, 0.45 * sin(ph * 0.2))


static func _scold(rig: Dictionary, t: float, u: float) -> void:
	## Matched to red_squirrel_scold.wav: three intro chips and then a long
	## rattling trill. The whole animal jerks with every chip and the tail
	## whips in the same rhythm — a red squirrel scolds with its entire body
	## and it will do it for four minutes if you let it.
	var chip := _pulse(t, 0.06, 0.04) + _pulse(t, 0.16, 0.04) + _pulse(t, 0.26, 0.04)
	var trill := _seg(t, 0.34, 0.92)
	var buzz := (0.5 + 0.5 * sin(trill * TAU * 14.0)) * trill * (1.0 - _seg(t, 0.88, 1.0))
	var jerk := chip + buzz * 0.55
	_rk(rig, "body", 0.35 - 0.25 * jerk)
	_pk(rig, "body", Vector3(0, 0, -0.05 * u * jerk))
	_rk(rig, "neck", 0.20 - 0.30 * jerk)
	_rk(rig, "head", 0.10 - 0.20 * jerk, 0.15 * sin(t * TAU * 1.3))
	_jaw_open(rig, 0.35 * jerk)
	## Tail semaphore, one flick per chip and a continuous quiver on the trill.
	_rk(rig, "tail", -0.85 - 0.55 * jerk, 0.30 * sin(t * TAU * 6.0) * buzz)
	_rk(rig, "tail2", -0.30 - 0.30 * jerk)
	for i in 2:
		_ri(rig, "legs", i, 0.95 + 0.20 * jerk)
		_ri(rig, "knees", i, -0.85)
	for i in range(2, 4):
		_ri(rig, "legs", i, 0.40)
		_ri(rig, "knees", i, -0.75)
	_ears(rig, -0.10)


static func _midden(rig: Dictionary, t: float, _u: float) -> void:
	## Sat on the cone pile, spinning a cone against its teeth and stripping
	## the scales off in a spiral. The middens under spruce in this game are
	## years deep and this is how they got that way.
	var sit := _ease_out(_seg(t, 0.0, 0.12))
	var spin := t * TAU * 1.5
	var chew := t * TAU * 9.0
	_rk(rig, "body", 0.70 * sit)
	for i in 2:
		_ri(rig, "legs", i, (1.10 + 0.10 * sin(spin)) * sit, 0.20 * sin(spin) * sit,
			(-0.20 if i == 0 else 0.20) * sit)
		_ri(rig, "knees", i, -0.75 * sit)
	for i in range(2, 4):
		_ri(rig, "legs", i, 0.45 * sit)
		_ri(rig, "knees", i, -0.90 * sit)
	_rk(rig, "neck", -0.25 * sit)
	_rk(rig, "head", -0.15 * sit + 0.05 * sin(chew), 0.20 * sin(spin), 0.35 * sin(spin) * sit)
	_jaw_open(rig, (0.10 + 0.12 * (0.5 + 0.5 * sin(chew))) * sit)
	_rk(rig, "tail", -0.95 * sit, 0.25 * sin(t * TAU * 0.8))
	_rk(rig, "tail2", -0.35 * sit)


static func _cache_run(rig: Dictionary, t: float, u: float) -> void:
	## Two bounds, a stop, four fast digs, a look around, and a tamp with the
	## nose. Squirrels bury far more than they retrieve, which is where half
	## the oak trees in the world come from.
	var bound := _seg(t, 0.0, 0.30)
	var dig := _seg(t, 0.34, 0.66)
	var scan := _pulse(t, 0.74, 0.09)
	var tamp := _pulse(t, 0.90, 0.07)
	var v := fposmod(bound * 2.0, 1.0)
	_pk(rig, "root", Vector3(0, 0.28 * u * _arc(v) * _seg(t, 0.0, 0.30) * (1.0 - _seg(t, 0.28, 0.34)), 0))
	_rk(rig, "body", -0.30 * cos(v * TAU) * (1.0 - _seg(t, 0.30, 0.36)) + 0.45 * dig - 0.30 * tamp)
	## Digging: both forepaws alternating fast, head down between them.
	var ph := dig * TAU * 6.0
	for i in 2:
		_ri(rig, "legs", i, (0.55 - 0.95 * cos(v * TAU)) * (1.0 - dig)
			+ (0.95 + 0.55 * sin(ph + float(i) * PI)) * dig)
		_ri(rig, "knees", i, -0.55 - 0.45 * dig)
	for i in range(2, 4):
		_ri(rig, "legs", i, (-0.60 + 1.05 * cos(v * TAU)) * (1.0 - dig) + 0.35 * dig)
		_ri(rig, "knees", i, -0.80)
	_rk(rig, "neck", -0.55 * dig + 0.55 * scan - 0.65 * tamp)
	_rk(rig, "head", -0.25 * dig + 0.20 * scan - 0.30 * tamp, 0.85 * sin(scan * PI * 2.0))
	_rk(rig, "tail", -0.60 - 0.35 * dig, 0.35 * sin(t * TAU * 2.0))


static func _tail_flick(rig: Dictionary, t: float, _u: float) -> void:
	## Three sharp flicks with the body frozen. The tail is a semaphore — it
	## means "I have seen you and I am not going anywhere", and the stillness
	## of everything else is what makes the flick legible at thirty metres.
	var f := _pulse(t, 0.12, 0.09) + _pulse(t, 0.40, 0.09) + _pulse(t, 0.68, 0.10)
	_still(rig)
	_rk(rig, "tail", -0.55 - 1.30 * f, 0.30 * sin(t * TAU * 3.0) * f)
	_rk(rig, "tail2", -0.20 - 0.55 * f)
	_rk(rig, "body", 0.25 - 0.08 * f)
	_rk(rig, "neck", 0.15)
	_rk(rig, "head", 0.05 - 0.12 * f, 0.20 * f)
	for i in 2:
		_ri(rig, "legs", i, 0.75)
		_ri(rig, "knees", i, -0.65)


static func _cheek_stuff(rig: Dictionary, t: float, _u: float) -> void:
	## Four seeds in, and the head gets visibly wider each time. Scaling the
	## skull in steps is a cheat that reads instantly at chipmunk scale, and a
	## chipmunk with full pouches is one of the few genuinely funny silhouettes
	## available to a box.
	var sit := _ease_out(_seg(t, 0.0, 0.12))
	var n := 0.0
	for k in 4:
		n += _ease_out(_seg(t, 0.14 + float(k) * 0.18, 0.22 + float(k) * 0.18))
	var pick := _pulse(t, 0.16, 0.06) + _pulse(t, 0.34, 0.06) + _pulse(t, 0.52, 0.06) + _pulse(t, 0.70, 0.06)
	_sk(rig, "head", Vector3(1.0 + 0.11 * n, 1.0 + 0.07 * n, 1.0 + 0.05 * n))
	_rk(rig, "body", 0.60 * sit)
	_rk(rig, "neck", -0.20 * sit - 0.30 * pick)
	_rk(rig, "head", -0.10 * sit - 0.25 * pick, 0.12 * sin(t * TAU * 2.0))
	_jaw_open(rig, 0.16 + 0.20 * pick)
	for i in 2:
		_ri(rig, "legs", i, (1.15 - 0.35 * pick) * sit)
		_ri(rig, "knees", i, -0.80 * sit)
	for i in range(2, 4):
		_ri(rig, "legs", i, 0.45 * sit)
		_ri(rig, "knees", i, -0.90 * sit)
	_rk(rig, "tail", -0.70 * sit, 0.25 * sin(t * TAU * 1.6))


static func _wall_dash(rig: Dictionary, t: float, u: float) -> void:
	## Flat out along a stone wall with two hard stops in it. The stops are
	## instantaneous — a chipmunk has exactly two speeds and no transition
	## between them.
	var stop1 := _pulse(t, 0.34, 0.07)
	var stop2 := _pulse(t, 0.74, 0.07)
	var run := 1.0 - clampf(stop1 + stop2, 0.0, 1.0)
	var ph := t * TAU * 11.0
	_pk(rig, "root", Vector3(0, 0.10 * u * absf(sin(ph * 0.5)) * run, 0))
	_rk(rig, "body", -0.25 * cos(ph * 0.5) * run + 0.35 * (1.0 - run))
	for i in 4:
		var reach := sin(ph + (0.0 if (i == 0 or i == 3) else PI))
		_ri(rig, "legs", i, (0.60 * reach) * run + (0.85 if i < 2 else 0.35) * (1.0 - run))
		_ri(rig, "knees", i, -0.45 - 0.35 * maxf(0.0, -reach) * run)
	## On the stops it goes vertical and looks straight at you.
	_rk(rig, "neck", 0.10 * run + 0.35 * (1.0 - run))
	_rk(rig, "head", 0.05 * run + 0.15 * (1.0 - run), 0.55 * (stop1 - stop2))
	_rk(rig, "tail", -0.45 - 0.60 * (1.0 - run), 0.35 * sin(ph * 0.25))
	_ears(rig, -0.05)


## ============================= GROUND BIRDS ===============================


static func _log_drum(rig: Dictionary, t: float, u: float) -> void:
	## Matched thump for thump to grouse_drum.wav: forty-eight beats, the first
	## gap 0.42 s and the last under a fifth of that. The exponent is 1.233
	## because that is the value that puts beat one at 0.42 s and beat
	## forty-eight on the last frame of the file — anything else and the wings
	## finish before the sound does, which reads instantly as a bad dub.
	## The bird is not hitting the log. It is hitting the air, hard enough to
	## make a sound you feel in your chest a hundred metres away.
	var ph := TAU * 48.0 * pow(t, 1.233)
	var amp := 0.55 + 0.90 * _ease_in(t)
	var beat := sin(ph)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_si(rig, "wings", i, Vector3.ONE)
		## Cupped in FRONT of the chest, not out to the side — the sweep is
		## what makes the silhouette right.
		_ri(rig, "wings", i, 0.0, -(0.55 + 0.35 * beat) * side, (0.25 + amp * beat) * side)
	_rk(rig, "body", 0.32 + 0.07 * cos(ph))
	_pk(rig, "root", Vector3(0, 0.012 * u * cos(ph), 0))
	_sk(rig, "neck", Vector3(1.30, 1.0, 1.30))       ## ruff out for the display
	_rk(rig, "crest", -0.55)
	_rk(rig, "neck", 0.28)
	_rk(rig, "head", 0.06, 0.05 * sin(t * TAU * 0.5))
	_rk(rig, "tail", -0.32)
	_sk(rig, "tail", Vector3(1.30, 1.0, 1.0))
	for i in 2:                                       ## planted; nothing steps
		_ri(rig, "legs", i, 0.0)
		_ri(rig, "knees", i, -0.10)


static func _flush(rig: Dictionary, t: float, u: float, delta: float) -> void:
	## The explosive takeoff, and the reason grouse are hunted with a shotgun
	## and not a rifle. Nine tenths of a second from lump-of-leaves to gone,
	## with the crouch that precedes it lasting one frame.
	var crouch := _snap(_seg(t, 0.0, 0.09))
	var go := _seg(t, 0.09, 1.0)
	var ph := go * TAU * 5.5
	_pk(rig, "root", Vector3(0,
		-0.11 * u * crouch * (1.0 - _seg(t, 0.09, 0.17)) + 2.80 * u * _ease_in(go), 0))
	_flap(rig, ph, 1.20, 0.12)
	if t > 0.35:
		_blur(rig, _at(rig, "wings", 0), 1.10, 9.0, delta)
		_blur(rig, _at(rig, "wings", 1), -1.10, 9.0, delta)
	_rk(rig, "body", -0.22 * crouch + 0.90 * _ease_out(_seg(t, 0.11, 0.42))
		- 0.50 * _seg(t, 0.50, 1.0))
	_rk(rig, "neck", 0.30 * go)
	_rk(rig, "head", -0.20 * go)
	_sk(rig, "tail", Vector3(1.0 + 0.45 * go, 1.0, 1.0))
	_rk(rig, "tail", -0.55 * go)
	for i in 2:
		_ri(rig, "legs", i, 0.55 * crouch - 1.20 * go)
		_ri(rig, "knees", i, -1.10 * crouch + 0.70 * go)


static func _snow_dive(rig: Dictionary, t: float, u: float) -> void:
	## Head first into the powder at speed, and gone. Grouse roost under the
	## snow all winter and they get in by flying into it without slowing down,
	## which is exactly as alarming to watch as it sounds.
	var pitch := _ease_io(_seg(t, 0.0, 0.30))
	var down := _ease_in(_seg(t, 0.10, 0.80))
	var under := _seg(t, 0.75, 1.0)
	_rk(rig, "body", -1.25 * pitch)
	_pk(rig, "root", Vector3(0, 0.55 * u * (1.0 - down) - 0.95 * u * under, -0.35 * u * down))
	## Wings fold at the last moment, not before — the bird is still flying
	## when it hits.
	_wings_fold(rig, _ease_in(_seg(t, 0.45, 0.72)))
	if t < 0.5:
		_flap(rig, t * TAU * 7.0, 0.85, 0.20)
	_rk(rig, "neck", -0.35 * pitch)
	_rk(rig, "head", -0.15 * pitch)
	for i in 2:
		_ri(rig, "legs", i, -0.95 * pitch)
		_ri(rig, "knees", i, 0.45 * pitch)
	_rk(rig, "tail", 0.35 * pitch)


static func _ruff_up(rig: Dictionary, t: float, _u: float) -> void:
	## Neck ruff out, crest up, fan open, everything puffed. It is a bluff and
	## it works on exactly nothing, but it is what the bird is named for.
	var on := _overshoot(_seg(t, 0.0, 0.30), 1.8)
	_sk(rig, "neck", Vector3(1.0 + 0.55 * on, 1.0, 1.0 + 0.55 * on))
	_rk(rig, "crest", -0.65 * on)
	_sk(rig, "tail", Vector3(1.0 + 1.10 * on, 1.0, 1.0))
	_rk(rig, "tail", -0.85 * on)
	_sk(rig, "body", Vector3(1.0 + 0.14 * on, 1.0 + 0.14 * on, 1.0 + 0.06 * on))
	_rk(rig, "body", 0.18 * on)
	_rk(rig, "neck", -0.12 * on)
	_rk(rig, "head", 0.20 * on, 0.20 * sin(t * TAU * 1.2) * on)
	_wings_fold(rig, 0.55)
	for i in 2:
		_ri(rig, "legs", i, 0.0)
		_ri(rig, "knees", i, -0.14 * on)


static func _fool_hen(rig: Dictionary, t: float, u: float) -> void:
	## Does nothing. That IS the animation: a spruce grouse will let you walk
	## up and take it off a branch by hand, and any fidget at all would be a
	## lie about the species. One head tilt and one unhurried step in three
	## seconds, and both of them are slower than the player expects.
	var tilt := _pulse(t, 0.42, 0.16)
	var step := _seg(t, 0.62, 0.86)
	_still(rig)
	_rk(rig, "head", 0.04, 0.20 * tilt, 0.35 * tilt)
	_rk(rig, "neck", 0.03)
	_wings_fold(rig, 0.95)
	for i in 2:
		var a := step * PI
		var mine := 1.0 if i == 0 else 0.0
		_ri(rig, "legs", i, sin(a) * 0.28 * mine)
		_ri(rig, "knees", i, -sin(a) * 0.55 * mine)
	_pk(rig, "root", Vector3(0, 0.010 * u * sin(step * PI), 0))


static func _strut_drum(rig: Dictionary, t: float, u: float) -> void:
	## The full gobbler: fan up and spread, wings dropped and dragging, body
	## inflated, head pulled back into the shoulders, and a walk slowed to a
	## quarter speed. A strutting turkey is trying to be a circle and very
	## nearly manages it.
	var puff := _ease_out(_seg(t, 0.0, 0.25))
	_sk(rig, "body", Vector3(1.0 + 0.18 * puff, 1.0 + 0.20 * puff, 1.0 + 0.10 * puff))
	## The fan is the tail node; rotate it up to vertical and widen it.
	_rk(rig, "fan", -1.35 * puff)
	_sk(rig, "fan", Vector3(1.0 + 1.30 * puff, 1.0, 1.0 + 0.35 * puff))
	## Wings drop and drag. The primaries scraping the dirt is half the sound.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_si(rig, "wings", i, Vector3.ONE)
		_ri(rig, "wings", i, 0.25 * puff, -0.30 * puff * side, -0.65 * puff * side)
	## Head hauled back INTO the body — shortening the neck is what does it,
	## and it is the difference between a turkey and a chicken.
	_sk(rig, "neck", Vector3(1.0 + 0.35 * puff, 1.0 - 0.42 * puff, 1.0 + 0.35 * puff))
	_rk(rig, "neck", -0.30 * puff)
	_rk(rig, "head", 0.45 * puff, 0.12 * sin(t * TAU * 0.6))
	## Steps at one and a half a second, with a hard lateral rock on each.
	var ph := t * TAU * 1.5
	_rk(rig, "body", 0.20 * puff, 0.06 * sin(ph), 0.13 * sin(ph) * puff)
	_bird_legs(rig, ph, 0.26, 0.34)
	_pk(rig, "root", Vector3(0.04 * u * sin(ph), 0.012 * u * absf(sin(ph)), 0))


static func _scratch_line(rig: Dictionary, t: float, u: float) -> void:
	## Two backward rakes with one foot, a step off it, and a look down at what
	## turned up. Every turkey scratching in the game leaves a bare patch and a
	## line of leaf litter behind it, which is how you track them.
	var s1 := _seg(t, 0.05, 0.28)
	var s2 := _seg(t, 0.30, 0.53)
	var back := _seg(t, 0.55, 0.72)
	var look := _seg(t, 0.74, 1.0)
	var rake := sin(s1 * PI) + sin(s2 * PI)
	_ri(rig, "legs", 0, 0.75 * rake - 0.45 * back)
	_ri(rig, "knees", 0, -1.05 * maxf(0.0, sin(s1 * PI)) - 1.05 * maxf(0.0, sin(s2 * PI)))
	_ri(rig, "legs", 1, -0.15 * rake + 0.35 * back)
	_ri(rig, "knees", 1, -0.20)
	_rk(rig, "body", 0.15 * rake + 0.20 * back - 0.30 * sin(look * PI))
	_pk(rig, "root", Vector3(0, 0.02 * u * absf(rake), 0.10 * u * back))
	_rk(rig, "neck", -0.20 - 0.70 * sin(look * PI))
	_rk(rig, "head", 0.05 - 0.25 * sin(look * PI), 0.30 * sin(look * TAU))
	_wings_fold(rig, 0.9)


static func _dust_bathe(rig: Dictionary, t: float, u: float) -> void:
	## Down in a scrape, throwing dirt through the feathers in short bursts and
	## rolling between them. It is parasite control and it looks like an
	## animal having a seizure in a hole.
	var down := _ease_io(_seg(t, 0.0, 0.15)) * (1.0 - _ease_io(_seg(t, 0.88, 1.0)))
	var burst := _pulse(t, 0.28, 0.10) + _pulse(t, 0.52, 0.10) + _pulse(t, 0.76, 0.10)
	var roll := sin(t * TAU * 1.1) * down
	_pk(rig, "root", Vector3(0, -0.17 * u * down, 0))
	_rk(rig, "body", -0.25 * down, 0.20 * roll, 0.45 * roll)
	_sk(rig, "body", Vector3(1.0 + 0.10 * down, 1.0 - 0.14 * down, 1.0))
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_si(rig, "wings", i, Vector3.ONE)
		_ri(rig, "wings", i, 0.0, -0.25 * down * side,
			(-0.35 * down + 1.10 * burst * sin(t * TAU * 14.0)) * side)
	_rk(rig, "neck", -0.35 * down - 0.25 * burst)
	_rk(rig, "head", 0.10 * down, 0.55 * sin(t * TAU * 3.0) * burst)
	for i in 2:
		_ri(rig, "legs", i, 0.55 * down + 0.35 * burst * sin(t * TAU * 9.0 + float(i)))
		_ri(rig, "knees", i, -0.85 * down)
	_rk(rig, "tail", 0.30 * down, 0.30 * roll)


static func _roost_flap(rig: Dictionary, t: float, u: float, delta: float) -> void:
	## Getting five kilos of turkey twelve metres up a pine at dusk, which it
	## does badly and loudly: one hopeless leap and then brute force. Every
	## evening in the game this happens somewhere within earshot.
	var leap := _snap(_seg(t, 0.0, 0.12))
	var climb := _ease_out(_seg(t, 0.10, 0.82))
	var land := _seg(t, 0.82, 1.0)
	_pk(rig, "root", Vector3(0, 3.2 * u * climb, -0.25 * u * climb))
	_flap(rig, t * TAU * 6.5, 1.25, 0.10)
	_blur(rig, _at(rig, "wings", 0), 1.15, 7.5, delta)
	_blur(rig, _at(rig, "wings", 1), -1.15, 7.5, delta)
	_rk(rig, "body", 0.55 * leap + 0.35 * climb - 0.55 * land)
	_rk(rig, "neck", 0.30 * climb - 0.20 * land)
	_rk(rig, "head", -0.15 * climb + 0.25 * land)
	## Legs reaching for the limb the whole way up — that is the scrabble.
	for i in 2:
		_ri(rig, "legs", i, -0.90 * leap + (0.85 + 0.35 * sin(t * TAU * 5.0 + float(i) * PI)) * climb)
		_ri(rig, "knees", i, -1.20 * leap - 0.60 * climb + 0.40 * land)
	_sk(rig, "tail", Vector3(1.0 + 0.4 * climb, 1.0, 1.0))
	_rk(rig, "tail", -0.45 * climb + 0.30 * land)


static func _gobble_back(rig: Dictionary, t: float, _u: float) -> void:
	## Matched to turkey_gobble.wav: a burbling cascade about a second and a
	## half long. The head is thrown back and SHAKEN — the wattles doing their
	## own thing a beat behind is most of what makes it look involuntary.
	var on := _ease_out(_seg(t, 0.0, 0.10)) * (1.0 - _ease_io(_seg(t, 0.82, 1.0)))
	var shake := sin(t * TAU * 9.0) * on
	_rk(rig, "neck", 0.55 * on + 0.06 * shake, 0.10 * shake)
	_rk(rig, "head", 0.40 * on + 0.10 * shake, 0.28 * shake, 0.20 * sin(t * TAU * 6.0) * on)
	_jaw_open(rig, 0.35 * on + 0.12 * absf(shake))
	_sk(rig, "body", Vector3(1.0 + 0.10 * on, 1.0 + 0.12 * on, 1.0))
	_rk(rig, "body", 0.15 * on, 0.0, 0.05 * shake)
	_wings_fold(rig, 0.75)
	_sk(rig, "tail", Vector3(1.0 + 0.25 * on, 1.0, 1.0))
	for i in 2:
		_ri(rig, "legs", i, 0.06 * shake)
		_ri(rig, "knees", i, -0.12 * on)


static func _bob_walk(rig: Dictionary, t: float, u: float) -> void:
	## The woodcock rock. The body pumps forward and back over planted feet
	## while the head stays exactly where it is — the theory is that it makes
	## worms move. The theory is not the point. The point is that it is the
	## single funniest thing any animal in this game does, and it only lands
	## if the fore-and-aft translation is unmistakable and the head is nailed
	## in place while it happens.
	var ph := t * TAU * 2.0
	var rock := sin(ph)
	_pk(rig, "body", Vector3(0, 0.02 * u * absf(rock), -0.16 * u * rock))
	_rk(rig, "body", 0.10 * rock)
	## Counter-translate the neck by exactly what the body just did. The head
	## is a fixed point and the bird swings around it.
	_pk(rig, "neck", Vector3(0, 0, 0.16 * u * rock))
	_rk(rig, "neck", -0.10 * rock)
	_rk(rig, "head", 0.10 * rock, 0.06 * sin(ph * 0.25))
	## Feet stay put. The knees take the whole rock.
	for i in 2:
		_ri(rig, "legs", i, -0.30 * rock)
		_ri(rig, "knees", i, 0.42 * rock)
	_wings_fold(rig, 0.95)
	_rk(rig, "tail", 0.15 * rock)


static func _sky_dance(rig: Dictionary, t: float, u: float, delta: float) -> void:
	## Up in a widening spiral until it is a speck, then down in a zigzag
	## flutter, twittering the whole way. Woodcock do this at dusk in April and
	## it is the best reason in the game to be standing in a wet field at
	## eight in the evening.
	var climb := _ease_out(_seg(t, 0.0, 0.62))
	var fall := _ease_in(_seg(t, 0.66, 1.0))
	var flut := _seg(t, 0.66, 1.0)
	_rk(rig, "root", 0.0, TAU * 2.6 * climb + 0.6 * sin(flut * TAU * 5.0))
	_pk(rig, "root", Vector3(
		0.55 * u * sin(climb * TAU * 2.6) + 0.9 * u * sin(flut * TAU * 4.0) * flut,
		9.0 * u * climb - 8.6 * u * fall, 0.55 * u * cos(climb * TAU * 2.6)))
	_flap(rig, t * TAU * 9.0, 0.75 - 0.35 * flut, 0.08)
	_blur(rig, _at(rig, "wings", 0), 0.65, 11.0, delta)
	_blur(rig, _at(rig, "wings", 1), -0.65, 11.0, delta)
	_rk(rig, "body", 0.45 * climb - 0.35 * fall, 0.0, 0.55 * sin(flut * TAU * 4.0) * flut)
	_rk(rig, "neck", 0.20 * climb)
	for i in 2:
		_ri(rig, "legs", i, -0.85)
		_ri(rig, "knees", i, 0.35)
	_sk(rig, "tail", Vector3(1.0 + 0.5 * flut, 1.0, 1.0))


static func _peent(rig: Dictionary, t: float, u: float) -> void:
	## One buzzy nasal note, 0.63 s, and the bird's whole body behind it. The
	## note is the punctuation between sky dances and the player will hear
	## twenty of them before they ever see the bird.
	var on := _ease_out(_seg(t, 0.0, 0.14))
	var buzz := sin(t * TAU * 30.0) * _tri(_seg(t, 0.15, 0.85))
	_still(rig)
	_rk(rig, "neck", -0.30 * on + 0.02 * buzz)
	_rk(rig, "head", -0.25 * on + 0.03 * buzz)
	_pk(rig, "neck", Vector3(0, 0, -0.05 * u * on))
	_jaw_open(rig, 0.22 * on)
	_sk(rig, "body", Vector3(1.0 - 0.05 * on, 1.0 - 0.04 * on, 1.0 + 0.07 * on))
	_wings_fold(rig, 0.95)


## ================================ RAPTORS =================================


static func _soar(rig: Dictionary, t: float, u: float) -> void:
	## A wide, lazy circle on flat wings with maybe one adjustment in six
	## seconds. Soaring birds do not flap and the temptation to make them is
	## the most common way this kind of animation gets ruined.
	var bank := sin(t * TAU) * 0.30
	_rk(rig, "root", 0.0, TAU * t, bank)
	_pk(rig, "root", Vector3(2.2 * u * sin(TAU * t), 0.35 * u * sin(t * TAU * 0.5),
		2.2 * u * (cos(TAU * t) - 1.0)))
	_wings_v(rig, 0.06, 0.02)
	## One correction, and it is a twitch of the wingtips, not a flap.
	var fix := _pulse(t, 0.58, 0.05)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "wings", i, 0.0, -0.02 * side, (0.06 + 0.30 * fix) * side)
	_rk(rig, "body", 0.05, 0.0, -bank * 0.25)
	_rk(rig, "neck", -0.10)
	_rk(rig, "head", -0.25, 0.35 * sin(t * TAU * 1.5))     ## scanning the ground
	_sk(rig, "tail", Vector3(1.25, 1.0, 1.0))
	_rk(rig, "tail", 0.05, 0.15 * bank)
	for i in 2:
		_ri(rig, "legs", i, -0.75)
		_ri(rig, "knees", i, 0.55)


static func _teeter_soar(rig: Dictionary, t: float, u: float) -> void:
	## The vulture's ID mark: wings in a hard V and the whole bird rocking side
	## to side, never flapping, always looking a little out of control. Two
	## incommensurate periods so the teeter never settles into a rhythm.
	var rock := sin(t * TAU * 1.7) * 0.62 + sin(t * TAU * 1.1 + 1.0) * 0.28
	_rk(rig, "root", 0.0, TAU * 0.6 * t, rock * 0.55)
	_pk(rig, "root", Vector3(1.8 * u * sin(TAU * 0.6 * t), 0.30 * u * sin(t * TAU * 0.8),
		1.8 * u * (cos(TAU * 0.6 * t) - 1.0)))
	## Dihedral, and it stays. A vulture holds a shallow V for hours.
	_wings_v(rig, 0.34 + 0.05 * rock, 0.04)
	_rk(rig, "body", 0.08, 0.10 * rock, -0.30 * rock)
	_rk(rig, "head", -0.30, 0.25 * sin(t * TAU * 0.9))
	_sk(rig, "tail", Vector3(1.15, 1.0, 1.0))
	for i in 2:
		_ri(rig, "legs", i, -0.70)


static func _corpse_circle(rig: Dictionary, t: float, u: float) -> void:
	## The tightening spiral over something dead. Ravens and vultures both do
	## it and it is the game's way of putting a marker on a kill without a HUD
	## element — if there are birds turning above the ridge, something is under
	## them.
	var r := 1.0 - 0.55 * t
	var a := TAU * 2.2 * t
	_rk(rig, "root", 0.0, a, 0.42 * r)
	_pk(rig, "root", Vector3(2.6 * u * r * sin(a), 1.6 * u * (1.0 - t),
		2.6 * u * r * cos(a) - 2.6 * u))
	_wings_v(rig, 0.14, 0.06)
	## One lazy beat every second and a half, more often as it drops.
	var beat := sin(t * TAU * (2.0 + 3.0 * t))
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "wings", i, 0.0, -0.06 * side, (0.14 + 0.35 * maxf(0.0, beat)) * side)
	_rk(rig, "body", 0.05, 0.0, -0.18 * r)
	_rk(rig, "neck", -0.15)
	_rk(rig, "head", -0.55, 0.30 * sin(a))            ## looking straight down
	_sk(rig, "tail", Vector3(1.2, 1.0, 1.0))


static func _silent_glide(rig: Dictionary, t: float, u: float) -> void:
	## Wings in a shallow V and NOT A SINGLE FLAP. That is the entire point:
	## an owl coming through the trees makes no sound at all, and any wingbeat
	## in this clip is a lie about the animal. The only motion is a slow
	## descent and a lazy bank.
	_wings_v(rig, 0.20 + 0.03 * sin(t * TAU * 0.5), 0.05)
	var bank := 0.16 * sin(t * TAU * 0.5)
	_rk(rig, "root", 0.0, 0.55 * sin(t * TAU * 0.5), bank)
	_pk(rig, "root", Vector3(0.45 * u * sin(t * TAU * 0.5), -0.55 * u * t, -1.6 * u * t))
	_rk(rig, "body", 0.10, 0.0, -bank * 0.4)
	## The face stays locked on the target no matter what the body does.
	_rk(rig, "neck", -0.12)
	_rk(rig, "head", -0.30, -0.55 * sin(t * TAU * 0.5))
	_sk(rig, "tail", Vector3(1.35, 1.0, 1.0))
	_rk(rig, "tail", 0.10)
	for i in 2:
		_ri(rig, "legs", i, -0.60)
		_ri(rig, "knees", i, 0.45)


static func _head_track(rig: Dictionary, t: float, _u: float) -> void:
	## The owl trick, and the reason the barred owl is the creepiest thing in
	## the deep woods: the body does not move at all — not a feather — and the
	## head goes round past where a neck should be able to go. Owls do not
	## sweep, they STEP: a fast settle and a long hold, four times.
	var steps: Array[float] = [0.0, 1.30, 2.90, -1.15, 0.0]
	var f := t * 4.0
	var i := mini(int(f), 3)
	var v := _snap(clampf((f - float(i)) / 0.28, 0.0, 1.0))
	var yaw := lerpf(float(steps[i]), float(steps[i + 1]), v)
	## The body is pinned. Everything idle() wrote this frame gets overwritten,
	## which is the whole illusion.
	_still(rig)
	_wings_fold(rig, 0.95)
	_rk(rig, "neck", 0.0, yaw * 0.12)         ## the neck barely participates
	## And the tilt: at the third hold the whole head rolls ninety degrees.
	_rk(rig, "head", 0.05, yaw * 0.88, 1.10 * _pulse(t, 0.68, 0.10))
	for i2 in 2:
		_ri(rig, "legs", i2, 0.0)
		_ri(rig, "knees", i2, 0.0)


static func _hoot(rig: Dictionary, t: float, u: float) -> void:
	## Matched to barred_owl.wav: eight notes in two phrases with the last one
	## drawn right out. Who cooks for you — who cooks for you ALL. The tail
	## cocks on every note and the throat puffs, which is all the body language
	## an owl has.
	var n := 0.0
	for at: float in [0.08, 0.19, 0.30, 0.44, 0.60, 0.70, 0.80, 0.93]:
		n += _pulse(t, at, 0.045)
	var last := _pulse(t, 0.95, 0.09)          ## the drawn-out one
	var voice := clampf(n + last, 0.0, 1.4)
	_still(rig)
	_wings_fold(rig, 0.95)
	_sk(rig, "neck", Vector3(1.0 + 0.20 * voice, 1.0, 1.0 + 0.20 * voice))
	_rk(rig, "body", 0.20 * voice)
	_rk(rig, "neck", -0.12 * voice)
	_rk(rig, "head", 0.06 * voice, 0.15 * sin(t * TAU * 0.5))
	_jaw_open(rig, 0.22 * voice)
	_rk(rig, "tail", -0.45 * voice)
	_pk(rig, "root", Vector3(0, 0.008 * u * voice, 0))


static func _hover_plunge(rig: Dictionary, t: float, u: float, delta: float) -> void:
	## The osprey's whole living. Hover on hard beats, fold, fall, and then at
	## the very last instant the legs come THROUGH and forward so the feet hit
	## the water before the face does. That last-moment swing is the animation;
	## without it this is just a bird falling in a lake.
	var hover := _seg(t, 0.0, 0.45)
	var fold := _ease_in(_seg(t, 0.45, 0.55))
	var drop := _ease_in(_seg(t, 0.55, 0.88))
	var feet := _snap(_seg(t, 0.86, 0.96))
	var hit := _seg(t, 0.96, 1.0)
	_pk(rig, "root", Vector3(0, 3.00 * u * (1.0 - drop) + 0.05 * u * sin(hover * TAU * 3.0)
		- 0.18 * u * hit, -0.55 * u * drop))
	if t < 0.5:
		_flap(rig, hover * TAU * 4.2, 1.10, 0.05)
		_blur(rig, _at(rig, "wings", 0), 1.0, 5.0, delta)
		_blur(rig, _at(rig, "wings", 1), -1.0, 5.0, delta)
	else:
		_wings_fold(rig, fold * (1.0 - 0.75 * feet))
	## Nose down through the drop, then pitched back up as the feet come in.
	_rk(rig, "body", 0.35 * hover - 1.05 * fold - 0.20 * drop + 1.05 * feet)
	## Head locked on the fish from the first frame to the last.
	_rk(rig, "neck", -0.55 - 0.30 * drop + 0.30 * feet)
	_rk(rig, "head", -0.35 - 0.10 * drop + 0.20 * feet)
	## Legs trail, then swing forward under the body at the last moment.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "legs", i, -0.75 * (1.0 - feet) + 1.55 * feet, 0.0, side * 0.35 * feet)
		_ri(rig, "knees", i, 0.50 * (1.0 - feet) - 0.35 * feet)
	_sk(rig, "tail", Vector3(1.0 + 0.5 * hover - 0.4 * fold, 1.0, 1.0))
	_rk(rig, "tail", -0.35 * hover + 0.30 * feet)


static func _fish_snatch(rig: Dictionary, t: float, u: float) -> void:
	## Low and flat over the water, feet down, one grab, and then the heavy
	## work of getting back up with a fish. An eagle does not dive — it reaches
	## down and takes it while going past.
	var run := _ease_io(_seg(t, 0.0, 0.45))
	var grab := _pulse(t, 0.55, 0.07)
	var climb := _ease_in(_seg(t, 0.60, 1.0))
	_pk(rig, "root", Vector3(0, 1.1 * u * (1.0 - run) + 0.05 * u - 0.10 * u * grab
		+ 1.3 * u * climb, -1.4 * u * _ease_io(t)))
	_flap(rig, t * TAU * 2.6, 0.55 + 0.55 * climb, 0.05)
	## The flare: wings hard back and open at the moment of the grab.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "wings", i, 0.0, -(0.05 + 0.55 * grab) * side, (0.75 * grab) * side)
	_rk(rig, "body", -0.20 * run + 0.65 * grab + 0.25 * climb)
	_rk(rig, "neck", -0.40 - 0.25 * run + 0.35 * climb)
	_rk(rig, "head", -0.30 * run + 0.20 * climb)
	## Talons open on the way in and shut on the beat.
	for i in 2:
		var side2 := -1.0 if i == 0 else 1.0
		_ri(rig, "legs", i, 0.85 * run + 0.55 * grab - 0.95 * climb,
			0.0, side2 * (0.30 * run - 0.25 * grab))
		_ri(rig, "knees", i, -0.35 * run + 0.65 * climb)
	_sk(rig, "tail", Vector3(1.0 + 0.45 * grab, 1.0, 1.0))
	_rk(rig, "tail", -0.55 * grab)


static func _osprey_mug(rig: Dictionary, t: float, u: float) -> void:
	## Piracy. The eagle does not fish if there is an osprey nearby that
	## already has: it comes in fast from above, rolls, takes the fish out of
	## the other bird's feet, and peels away. Half the eagles on this lake feed
	## this way and the player will watch it happen over the water.
	var close := _ease_in(_seg(t, 0.0, 0.35))
	var roll := _ease_io(_seg(t, 0.30, 0.55))
	var take := _pulse(t, 0.58, 0.06)
	var peel := _ease_out(_seg(t, 0.60, 1.0))
	_rk(rig, "root", 0.0, 1.35 * peel, -1.30 * roll * (1.0 - peel * 0.7))
	_pk(rig, "root", Vector3(1.2 * u * peel, 1.4 * u * (1.0 - close) - 0.25 * u * peel,
		-1.9 * u * close + 0.9 * u * peel))
	_flap(rig, t * TAU * 3.4, 0.70 + 0.40 * peel, 0.20 * close)
	_rk(rig, "body", -0.35 * close + 0.55 * take + 0.20 * peel, 0.0, -0.30 * roll)
	_rk(rig, "neck", -0.35 - 0.20 * close)
	_rk(rig, "head", -0.25 * close, 0.55 * roll - 0.75 * peel)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "legs", i, 0.35 * close + 1.35 * roll - 0.85 * peel, 0.0,
			side * (0.45 * roll - 0.30 * take))
		_ri(rig, "knees", i, -0.45 * roll + 0.55 * peel)
	_jaw_open(rig, 0.45 * take)
	_sk(rig, "tail", Vector3(1.0 + 0.4 * take, 1.0, 1.0))
	_rk(rig, "tail", -0.30 * take, 0.35 * roll)


static func _fish_carry(rig: Dictionary, t: float, u: float) -> void:
	## Level flight with a fish, which an osprey carries head-first and
	## lengthwise like a torpedo because it cannot afford the drag. Heavy slow
	## beats, a nose-up trim to hold the load, and one re-grip shudder.
	var regrip := _pulse(t, 0.55, 0.06)
	_flap(rig, t * TAU * 2.4, 0.85, 0.04)
	_pk(rig, "root", Vector3(0, 0.10 * u * sin(t * TAU * 2.4 - 1.2), -2.2 * u * t))
	_rk(rig, "body", 0.18 + 0.06 * sin(t * TAU * 2.4) + 0.25 * regrip)
	_rk(rig, "neck", -0.15)
	_rk(rig, "head", -0.15, 0.20 * sin(t * TAU * 0.7) - 0.30 * regrip)
	## Legs tucked forward and under, holding the load against the belly.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "legs", i, 0.95 + 0.35 * regrip, 0.0, side * 0.12)
		_ri(rig, "knees", i, -0.85 - 0.30 * regrip)
	_sk(rig, "tail", Vector3(1.1, 1.0, 1.0))
	_rk(rig, "tail", 0.12 + 0.20 * regrip)


static func _shake_off(rig: Dictionary, t: float, u: float) -> void:
	## The mid-air shake. An osprey comes off the water soaked and gets rid of
	## it in about a second by rolling its whole body at twelve hertz, wings
	## held out, still flying. It is a wet dog at three hundred feet.
	var on := _ease_out(_seg(t, 0.0, 0.18)) * (1.0 - _ease_io(_seg(t, 0.78, 1.0)))
	var shake := sin(t * TAU * 12.0) * on
	_rk(rig, "root", 0.0, 0.10 * shake, 0.45 * shake)
	_pk(rig, "root", Vector3(0.05 * u * shake, 0.05 * u * absf(shake), 0))
	_wings_v(rig, 0.55, 0.10)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "wings", i, 0.10 * shake * side, -0.10 * side, (0.55 + 0.20 * shake) * side)
	_rk(rig, "body", 0.10, 0.15 * shake, -0.25 * shake)
	_rk(rig, "head", 0.0, -0.45 * shake, 0.30 * shake)
	_sk(rig, "tail", Vector3(1.3, 1.0, 1.0))
	_rk(rig, "tail", -0.20, 0.30 * shake)
	for i in 2:
		_ri(rig, "legs", i, -0.55)


static func _stoop(rig: Dictionary, t: float, u: float) -> void:
	## Three hundred and twenty kilometres an hour, and the animation problem
	## is that at that speed a bird stops looking like a bird. Wings shut
	## completely, tail closed, body vertical, and then absolutely nothing
	## changes for two thirds of the clip. It should read as a dropped stone,
	## because that is what the falcon is imitating.
	var setup := _ease_io(_seg(t, 0.0, 0.12))
	var fold := _ease_in(_seg(t, 0.12, 0.24))
	var fall := _seg(t, 0.24, 0.90)
	var pull := _ease_out(_seg(t, 0.90, 1.0))
	if t < 0.14:
		_flap(rig, t * TAU * 7.0, 0.90, 0.10)
	else:
		_wings_fold(rig, fold * (1.0 - 0.65 * pull))
	## Gravity, squared, over a very long way.
	_pk(rig, "root", Vector3(0, -9.0 * u * _gravity(fall) + 1.2 * u * pull, -1.8 * u * fall))
	_rk(rig, "body", -0.35 * setup - 1.00 * fold + 1.35 * pull)
	_rk(rig, "neck", -0.10 * fold)
	_rk(rig, "head", -0.10 * fold + 0.25 * pull)         ## eyes on the target, always
	_sk(rig, "tail", Vector3(1.0 - 0.45 * fold + 0.55 * pull, 1.0, 1.0))
	_rk(rig, "tail", 0.10 * fold - 0.35 * pull)
	for i in 2:
		_ri(rig, "legs", i, -1.05 * fold + 0.85 * pull)
		_ri(rig, "knees", i, 0.75 * fold)


static func _skunk_take(rig: Dictionary, t: float, u: float) -> void:
	## Great horned owls are the only thing that eats skunks, because they
	## cannot smell. Silent drop, feet through first, hard flare, and then the
	## wings come forward over the kill — mantling — which is the part that
	## says this is finished.
	var drop := _ease_in(_seg(t, 0.0, 0.45))
	var flare := _ease_out(_seg(t, 0.45, 0.58))
	var grab := _pulse(t, 0.60, 0.05)
	var mantle := _ease_io(_seg(t, 0.66, 0.86))
	_pk(rig, "root", Vector3(0, 1.9 * u * (1.0 - drop) - 0.10 * u * grab, -0.9 * u * drop))
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_si(rig, "wings", i, Vector3.ONE)
		## Swept back on the drop, thrown wide on the flare, then curled
		## forward and down over the prey.
		_ri(rig, "wings", i, 0.35 * mantle * side, -(0.65 * drop - 0.35 * flare + 0.95 * mantle) * side,
			(0.10 + 1.05 * flare - 0.85 * mantle) * side)
	_rk(rig, "body", -0.55 * drop + 0.95 * flare - 0.45 * mantle)
	_rk(rig, "neck", -0.45 - 0.20 * drop + 0.25 * mantle)
	_rk(rig, "head", -0.30 * drop - 0.35 * mantle, 0.25 * sin(mantle * TAU * 0.5))
	for i in 2:
		var side2 := -1.0 if i == 0 else 1.0
		_ri(rig, "legs", i, 0.45 * drop + 1.45 * flare - 0.55 * mantle, 0.0, side2 * 0.30 * flare)
		_ri(rig, "knees", i, -0.55 * flare)
	_sk(rig, "tail", Vector3(1.0 + 0.5 * flare, 1.0, 1.0))
	_rk(rig, "tail", -0.55 * flare + 0.30 * mantle)


static func _snag_sentinel(rig: Dictionary, t: float, _u: float) -> void:
	## An eagle on a dead pine over the lake, doing nothing whatsoever for five
	## seconds except turning its head twice — and then a rouse, the full-body
	## feather shake every bird does when it has decided the sitting is over.
	var look := _seg(t, 0.15, 0.30) - _seg(t, 0.50, 0.65)
	var rouse := _seg(t, 0.82, 0.96)
	var shake := sin(rouse * TAU * 7.0) * _tri(rouse)
	_still(rig)
	_wings_fold(rig, 0.92 - 0.35 * _tri(rouse))
	_rk(rig, "neck", 0.05 + 0.10 * _tri(rouse), 0.30 * _ease_io(clampf(look, -1.0, 1.0)))
	_rk(rig, "head", -0.10, 0.85 * _ease_io(clampf(look, -1.0, 1.0)) + 0.06 * shake, 0.10 * shake)
	_sk(rig, "body", Vector3(1.0 + 0.12 * _tri(rouse), 1.0 + 0.14 * _tri(rouse), 1.0))
	_rk(rig, "body", 0.0, 0.05 * shake, 0.12 * shake)
	_rk(rig, "tail", 0.10 - 0.25 * _tri(rouse), 0.15 * shake)
	for i in 2:
		_ri(rig, "legs", i, 0.0)
		_ri(rig, "knees", i, 0.0)


static func _cliff_ledge(rig: Dictionary, t: float, _u: float) -> void:
	## A peregrine on a ledge is never relaxed. Head snapping between fixed
	## points, one shoulder shrug, one foot lifted and held against the breast,
	## and the whole thing done at twice the speed of any other bird here.
	var slot := floori(t * 5.0)
	var local := fposmod(t * 5.0, 1.0)
	var yaw: float = lerpf((_rand(slot - 1) - 0.5) * 1.6, (_rand(slot) - 0.5) * 1.6,
		_snap(clampf(local / 0.15, 0.0, 1.0)))
	var shrug := _pulse(t, 0.46, 0.08)
	var foot := _seg(t, 0.62, 0.78) - _seg(t, 0.88, 0.96)
	_still(rig)
	_wings_fold(rig, 0.90 - 0.30 * shrug)
	_rk(rig, "neck", 0.05, yaw * 0.25)
	_rk(rig, "head", -0.05, yaw * 0.75, 0.20 * _pulse(t, 0.30, 0.06))
	_rk(rig, "body", 0.10 * shrug, 0.0, 0.0)
	_sk(rig, "body", Vector3(1.0 + 0.10 * shrug, 1.0 + 0.08 * shrug, 1.0))
	_ri(rig, "legs", 0, 0.85 * clampf(foot, 0.0, 1.0))
	_ri(rig, "knees", 0, -1.10 * clampf(foot, 0.0, 1.0))
	_rk(rig, "tail", 0.10, 0.10 * yaw)


static func _ground_sit(rig: Dictionary, t: float, u: float) -> void:
	## A snowy owl on open ground looks like a bag of laundry until the head
	## moves. Legs folded away entirely, body low and round, and two very slow
	## ninety-degree scans in four seconds.
	var down := _ease_io(_seg(t, 0.0, 0.12))
	var scan := sin(t * TAU * 0.55)
	_still(rig)
	_pk(rig, "root", Vector3(0, -0.16 * u * down, 0))
	_rk(rig, "body", -0.30 * down)
	_sk(rig, "body", Vector3(1.0 + 0.12 * down, 1.0 + 0.05 * down, 1.0 + 0.08 * down))
	_wings_fold(rig, 0.96)
	for i in 2:
		_ri(rig, "legs", i, 1.35 * down)         ## folded up out of sight
		_ri(rig, "knees", i, -1.45 * down)
	_rk(rig, "neck", 0.10 * down, scan * 0.30)
	_rk(rig, "head", -0.05, scan * 1.15, 0.25 * _pulse(t, 0.72, 0.08))
	_rk(rig, "tail", 0.25 * down)


static func _wing_dry(rig: Dictionary, t: float, _u: float) -> void:
	## Both wings held fully open to the sun, motionless, for as long as it
	## takes. Vultures do this every morning and a row of them on a dead pine
	## in the fog is the best free set dressing in the game.
	var open := _ease_out(_seg(t, 0.0, 0.22))
	var adjust := _pulse(t, 0.58, 0.09)
	var shrug := _pulse(t, 0.88, 0.06)
	_still(rig)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_si(rig, "wings", i, Vector3.ONE)
		_ri(rig, "wings", i, -0.10 * open, -(0.30 * open + 0.20 * adjust) * side,
			(0.35 * open + 0.25 * adjust + 0.45 * shrug) * side)
	_rk(rig, "body", 0.12 * open + 0.10 * shrug)
	_rk(rig, "neck", 0.10 * open, 0.30 * sin(t * TAU * 0.4))
	_rk(rig, "head", -0.15 * open, 0.45 * sin(t * TAU * 0.4))
	_sk(rig, "tail", Vector3(1.0 + 0.3 * open, 1.0, 1.0))
	_rk(rig, "tail", 0.15 * open)


## ============================ PERCHING BIRDS ==============================


static func _barrel_roll(rig: Dictionary, t: float, u: float) -> void:
	## A full three hundred and sixty on the roll axis, mid-flight, for no
	## reason at all. Ravens do this in wind and it is the clearest signal in
	## the game that this bird is not a background prop.
	var r := _ease_io(t)
	_rk(rig, "root", 0.0, 0.0, TAU * r)
	## It loses a little height in the middle and takes it back on the exit.
	_pk(rig, "root", Vector3(0.35 * u * sin(TAU * r), -0.45 * u * sin(PI * r), -1.6 * u * t))
	## Wings half-shut through the roll, thrown wide on the way out.
	var tuck := sin(PI * r)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_si(rig, "wings", i, Vector3(1.0 - 0.35 * tuck, 1.0, 1.0))
		_ri(rig, "wings", i, 0.0, -(0.35 * tuck) * side, (0.15 + 0.55 * (1.0 - tuck)) * side)
	_rk(rig, "body", 0.15 - 0.20 * tuck)
	_rk(rig, "head", -0.10, 0.30 * sin(TAU * r))
	_sk(rig, "tail", Vector3(1.0 + 0.35 * (1.0 - tuck), 1.0, 1.0))
	for i in 2:
		_ri(rig, "legs", i, -0.85)
		_ri(rig, "knees", i, 0.55)


static func _kraa(rig: Dictionary, t: float, u: float) -> void:
	## Matched to raven_kraa.wav: three harsh croaks. On each one the bird
	## leans hard forward, the tail comes up as a counterweight, and the shaggy
	## throat hackles flare — a raven calling puts its whole body into it in a
	## way a crow never does.
	var k := _pulse(t, 0.12, 0.07) + _pulse(t, 0.42, 0.07) + _pulse(t, 0.72, 0.08)
	_wings_fold(rig, 0.90 - 0.15 * k)
	_rk(rig, "body", -0.45 * k)
	_pk(rig, "body", Vector3(0, 0, -0.05 * u * k))
	_sk(rig, "neck", Vector3(1.0 + 0.40 * k, 1.0, 1.0 + 0.40 * k))
	_rk(rig, "neck", -0.35 * k)
	_rk(rig, "head", -0.15 * k, 0.12 * sin(t * TAU * 0.7))
	_jaw_open(rig, 0.55 * k)
	_rk(rig, "tail", -0.55 * k)
	for i in 2:
		_ri(rig, "legs", i, 0.0)
		_ri(rig, "knees", i, -0.12 * k)


static func _caw(rig: Dictionary, t: float, u: float) -> void:
	## Matched to crow_caw.wav: three caws, and unlike the raven the crow
	## delivers them with a shallow bob and a wing twitch rather than the whole
	## body. Same rhythm, less theatre — that difference is how you tell the
	## two birds apart at range without seeing the tail.
	var k := _pulse(t, 0.10, 0.06) + _pulse(t, 0.40, 0.06) + _pulse(t, 0.70, 0.07)
	_wings_fold(rig, 0.92)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "wings", i, 0.0, -0.85 * 0.92 * side, (-0.11 + 0.30 * k) * side)
	_rk(rig, "body", -0.28 * k)
	_rk(rig, "neck", -0.25 * k)
	_rk(rig, "head", -0.10 * k, 0.20 * sin(t * TAU * 1.1))
	_jaw_open(rig, 0.48 * k)
	_rk(rig, "tail", -0.35 * k)
	_pk(rig, "root", Vector3(0, 0.006 * u * k, 0))


static func _lead_wolves(rig: Dictionary, t: float, u: float) -> void:
	## The raven's oldest job: find the carcass, go get something with teeth,
	## and bring it back. Fly out, look back over the shoulder, call, and
	## return — the look back is the entire meaning of the clip and it has to
	## be unmistakable.
	var out := _ease_io(_seg(t, 0.0, 0.40))
	var back := _ease_io(_seg(t, 0.60, 1.0))
	var glance := _pulse(t, 0.46, 0.12) + _pulse(t, 0.92, 0.08)
	_flap(rig, t * TAU * 4.0, 0.75, 0.05)
	_pk(rig, "root", Vector3(0, 0.20 * u * sin(t * TAU * 2.0),
		-2.4 * u * out + 2.4 * u * back))
	_rk(rig, "root", 0.0, PI * back)
	_rk(rig, "body", 0.10, 0.0, 0.25 * sin(t * TAU * 1.0))
	## Head cranked round to check you are following.
	_rk(rig, "neck", 0.05, 0.55 * glance)
	_rk(rig, "head", -0.10, 1.35 * glance)
	_jaw_open(rig, 0.45 * _pulse(t, 0.50, 0.05))
	_sk(rig, "tail", Vector3(1.15, 1.0, 1.0))
	for i in 2:
		_ri(rig, "legs", i, -0.85)


static func _mob(rig: Dictionary, t: float, u: float) -> void:
	## Three dive passes at something bigger, each one a climb, a stall and a
	## screaming drop that pulls out early. Crows do this to owls all day and
	## it is how the player finds the owl.
	var f := t * 3.0
	var v := fposmod(f, 1.0)
	var climb := _ease_out(_seg(v, 0.0, 0.35))
	var dive := _ease_in(_seg(v, 0.40, 0.75))
	var peel := _ease_out(_seg(v, 0.75, 1.0))
	_pk(rig, "root", Vector3(0.6 * u * sin(f * PI), 1.5 * u * climb - 1.6 * u * dive,
		-0.9 * u * dive + 0.6 * u * peel))
	_rk(rig, "root", 0.0, 0.55 * sin(f * PI), -0.65 * sin(f * TAU * 0.5))
	_flap(rig, v * TAU * 5.0, 0.95 - 0.45 * dive, 0.30 * dive)
	_rk(rig, "body", 0.45 * climb - 0.85 * dive + 0.65 * peel)
	_rk(rig, "neck", -0.30 * dive)
	_rk(rig, "head", -0.45 * dive + 0.20 * climb, 0.30 * sin(f * TAU))
	_jaw_open(rig, 0.55 * _pulse(v, 0.62, 0.08))
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "legs", i, -0.75 + 0.95 * peel, 0.0, side * 0.25 * peel)
	_sk(rig, "tail", Vector3(1.0 + 0.4 * peel, 1.0, 1.0))


static func _sentry_post(rig: Dictionary, t: float, _u: float) -> void:
	## One crow up high while the rest of them feed. It does not move except to
	## snap its head between four fixed compass points, and the snap is the
	## thing — a smooth pan would read as a camera, not a bird.
	var f := t * 4.0
	var i := mini(int(f), 3)
	var v := _snap(clampf((f - float(i)) / 0.22, 0.0, 1.0))
	var dirs: Array[float] = [0.0, -1.15, 0.75, -0.45, 1.30]
	var yaw := lerpf(float(dirs[i]), float(dirs[i + 1]), v)
	_still(rig)
	_wings_fold(rig, 0.94 - 0.25 * _pulse(t, 0.70, 0.05))
	_rk(rig, "neck", 0.05, yaw * 0.25)
	_rk(rig, "head", -0.05, yaw * 0.75)
	_rk(rig, "tail", 0.10 - 0.30 * _pulse(t, 0.44, 0.05))
	for i2 in 2:
		_ri(rig, "legs", i2, 0.0)
		_ri(rig, "knees", i2, 0.0)


static func _hand_land(rig: Dictionary, t: float, u: float, delta: float) -> void:
	## A chickadee landing on your outstretched hand, which is the warmest
	## thing in a game otherwise about being cold. Hover in, brake, settle, and
	## then weigh nothing at all.
	var approach := _ease_out(_seg(t, 0.0, 0.55))
	var brake := _ease_io(_seg(t, 0.55, 0.72))
	var down := _ease_out(_seg(t, 0.62, 0.78))
	var perched := _seg(t, 0.78, 1.0)
	_pk(rig, "root", Vector3(0, 0.55 * u * (1.0 - down) + 0.03 * u * sin(t * TAU * 6.0) * (1.0 - down),
		-0.9 * u * approach))
	if t < 0.80:
		## Twenty-five hertz. Sampled off t it would be a strobe, so it is not.
		_blur(rig, _at(rig, "wings", 0), 1.15 * (1.0 - perched), 24.0, delta)
		_blur(rig, _at(rig, "wings", 1), -1.15 * (1.0 - perched), 24.0, delta)
		for i in 2:
			_si(rig, "wings", i, Vector3.ONE)
	else:
		_wings_fold(rig, _ease_out(_seg(t, 0.80, 0.90)))
	## The flare: body pitches up hard to kill the last of the speed.
	_rk(rig, "body", -0.20 * approach + 0.85 * brake - 0.75 * perched)
	_rk(rig, "neck", 0.15 - 0.10 * perched)
	_rk(rig, "head", -0.10, 0.45 * sin(t * TAU * 1.6) * (0.3 + 0.7 * perched))
	## Feet down and forward before it arrives, then folded.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "legs", i, 0.95 * brake - 0.35 * perched, 0.0, side * 0.20 * brake)
		_ri(rig, "knees", i, -0.75 * brake + 0.45 * perched)
	_sk(rig, "tail", Vector3(1.0 + 0.35 * brake, 1.0, 1.0))
	_rk(rig, "tail", -0.30 * brake + 0.15 * _bounce(_seg(t, 0.80, 1.0), 4.0, 8.0))


static func _dee_count(rig: Dictionary, t: float, u: float) -> void:
	## Matched to chickadee_dee.wav: two clear intro notes then four buzzy
	## dees. The number of dees is the alarm level in real chickadees, so the
	## bobs are counted out deliberately and the tail flicks on each one.
	var n := _pulse(t, 0.08, 0.05) + _pulse(t, 0.24, 0.05)
	for k in 4:
		n += _pulse(t, 0.42 + float(k) * 0.14, 0.045)
	_still(rig)
	_wings_fold(rig, 0.93)
	_rk(rig, "neck", -0.18 * n)
	_rk(rig, "head", -0.22 * n, 0.15 * sin(t * TAU * 0.9))
	_jaw_open(rig, 0.30 * n)
	_rk(rig, "tail", -0.45 * n, 0.20 * sin(t * TAU * 5.0) * n)
	_pk(rig, "root", Vector3(0, 0.004 * u * n, 0))
	for i in 2:
		_ri(rig, "legs", i, 0.0)
		_ri(rig, "knees", i, -0.08 * n)


static func _flit(rig: Dictionary, t: float, u: float, delta: float) -> void:
	## One hop-flight between two twigs. A second, start to finish, and small
	## birds do it about four hundred times an hour.
	var go := _snap(_seg(t, 0.0, 0.12))
	var air := _arc(_seg(t, 0.10, 0.80))
	var land := _seg(t, 0.80, 1.0)
	_pk(rig, "root", Vector3(0, 0.55 * u * air, -1.1 * u * _ease_io(_seg(t, 0.08, 0.85))))
	if t < 0.82:
		_blur(rig, _at(rig, "wings", 0), 1.20, 18.0, delta)
		_blur(rig, _at(rig, "wings", 1), -1.20, 18.0, delta)
		for i in 2:
			_si(rig, "wings", i, Vector3.ONE)
	else:
		_wings_fold(rig, _snap(_seg(t, 0.82, 0.92)))
	_rk(rig, "body", -0.35 * go + 0.75 * land)
	_rk(rig, "head", 0.10 * go - 0.15 * land, 0.30 * sin(t * TAU * 2.0))
	for i in 2:
		_ri(rig, "legs", i, -0.65 * go + 1.05 * land)
		_ri(rig, "knees", i, 0.45 * go - 0.85 * land)
	_rk(rig, "tail", -0.25 * land + 0.20 * _bounce(land, 5.0, 10.0))


static func _seed_hammer(rig: Dictionary, t: float, _u: float) -> void:
	## A sunflower seed held under one foot and hit until it opens. Two
	## clusters of four strikes with a pause between, because the bird checks
	## its work — which is the detail that makes it look like a decision
	## rather than a loop.
	var c1 := _seg(t, 0.05, 0.38)
	var c2 := _seg(t, 0.55, 0.88)
	var hits := 0.0
	for k in 4:
		hits += _pulse(c1, 0.12 + float(k) * 0.25, 0.10) * (1.0 if c1 > 0.0 and c1 < 1.0 else 0.0)
		hits += _pulse(c2, 0.12 + float(k) * 0.25, 0.10) * (1.0 if c2 > 0.0 and c2 < 1.0 else 0.0)
	_wings_fold(rig, 0.94)
	_rk(rig, "body", 0.25 - 0.20 * hits)
	_rk(rig, "neck", -0.30 - 0.45 * hits)
	_rk(rig, "head", -0.25 - 0.55 * hits, 0.10 * sin(t * TAU * 1.5))
	_jaw_open(rig, 0.25 * hits)
	## The foot holding the seed never moves; the other one takes the weight.
	_ri(rig, "legs", 0, 0.55)
	_ri(rig, "knees", 0, -0.65)
	_ri(rig, "legs", 1, 0.0)
	_ri(rig, "knees", 1, -0.10)
	_rk(rig, "tail", 0.20 + 0.20 * hits)


static func _screech(rig: Dictionary, t: float, u: float) -> void:
	## Matched to blue_jay_scream.wav: two harsh descending screeches. Head
	## down and forward on each, tail up, wings flicked half-open. A jay makes
	## this noise to clear a feeder and it works on everything including deer.
	var s := _pulse(t, 0.18, 0.11) + _pulse(t, 0.62, 0.12)
	_rk(rig, "crest", -0.65 * clampf(s + 0.3, 0.0, 1.0))
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_si(rig, "wings", i, Vector3(1.0 - 0.55 * (1.0 - s), 1.0, 1.0))
		_ri(rig, "wings", i, 0.0, -0.55 * (1.0 - s) * side, (0.10 + 0.55 * s) * side)
	_rk(rig, "body", -0.45 * s)
	_rk(rig, "neck", -0.35 * s)
	_rk(rig, "head", -0.30 * s)
	_jaw_open(rig, 0.65 * s)
	_rk(rig, "tail", -0.60 * s)
	_pk(rig, "root", Vector3(0, 0.008 * u * s, -0.03 * u * s))


static func _fake_hawk(rig: Dictionary, t: float, _u: float) -> void:
	## The jay does a red-shouldered hawk impression to clear a feeder, and the
	## comedy is entirely in the recovery: full menace, and then instantly a
	## small blue bird again with no transition at all.
	var wind := _ease_io(_seg(t, 0.0, 0.22))
	var call := _seg(t, 0.25, 0.62)
	var innocent := _seg(t, 0.66, 0.74)
	var on := wind * (1.0 - innocent)
	_rk(rig, "crest", -0.75 * on)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_si(rig, "wings", i, Vector3(1.0 - 0.35 * (1.0 - on), 1.0, 1.0))
		_ri(rig, "wings", i, 0.0, -0.25 * side, (0.45 * on) * side)
	_rk(rig, "body", -0.30 * on)
	_rk(rig, "neck", -0.30 * on, 0.55 * sin(call * PI) * on)
	_rk(rig, "head", -0.25 * on, 0.85 * sin(call * PI) * on)
	_jaw_open(rig, 0.70 * on * (0.4 + 0.6 * _tri(call)))
	_rk(rig, "tail", -0.45 * on)
	## And then nothing ever happened.
	_wings_fold(rig, 0.92 * innocent)
	if innocent > 0.5:
		_rk(rig, "crest", -0.05)
		_rk(rig, "head", 0.05, 0.20 * sin(t * TAU * 2.0))


static func _crest_raise(rig: Dictionary, t: float, _u: float) -> void:
	## Crest up and held, head turned to point at whatever caused it. On a jay
	## the crest is a mood ring and this is the only tell the player gets
	## before the screaming starts.
	var on := _overshoot(_seg(t, 0.0, 0.20), 2.2)
	_still(rig)
	_wings_fold(rig, 0.92)
	_rk(rig, "crest", -0.80 * on)
	_rk(rig, "neck", 0.10 * on, 0.25 * on)
	_rk(rig, "head", -0.05 * on, 0.55 * on, 0.15 * _pulse(t, 0.62, 0.10))
	_sk(rig, "body", Vector3(1.0 + 0.05 * on, 1.0 - 0.04 * on, 1.0))
	_rk(rig, "tail", -0.20 * on)


static func _cling(rig: Dictionary, t: float, u: float) -> void:
	## Clamped to the side of a trunk with the tail braced against the bark and
	## taking a third of the weight. Woodpeckers are a tripod and everything
	## they do up there follows from that.
	var on := _ease_out(_seg(t, 0.0, 0.14))
	var hitch := _pulse(t, 0.40, 0.10) + _pulse(t, 0.78, 0.10)
	_rk(rig, "body", 1.20 * on)
	_pk(rig, "root", Vector3(0, 0.22 * u * (_seg(t, 0.40, 0.50) + _seg(t, 0.78, 0.88)), 0))
	## Feet splayed wide, toes locked; a hitch is both feet at once.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "legs", i, (0.55 + 0.75 * hitch) * on, 0.0, side * 0.45 * on)
		_ri(rig, "knees", i, (-0.85 - 0.35 * hitch) * on)
	## Tail jammed down against the trunk. It is a prop, not a rudder.
	_rk(rig, "tail", (0.85 - 0.30 * hitch) * on)
	_wings_fold(rig, 0.95)
	_rk(rig, "neck", 0.15 * on)
	_rk(rig, "head", -0.10 * on, 0.55 * sin(t * TAU * 0.8) * on)


static func _excavate(rig: Dictionary, t: float, u: float) -> void:
	## Big slow chisel strokes, not a drum roll — a pileated cutting a roost
	## hole swings from the shoulders and stops every fourth stroke to shake
	## the chips out of its face. The holes it leaves are rectangular and the
	## player will find them.
	var on := _ease_out(_seg(t, 0.0, 0.10))
	var f := t * 9.0
	var strike := pow(maxf(0.0, sin(f * PI)), 3.0)
	var clear := _pulse(t, 0.46, 0.05) + _pulse(t, 0.92, 0.05)
	_rk(rig, "body", 1.20 * on)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "legs", i, 0.60 * on, 0.0, side * 0.45 * on)
		_ri(rig, "knees", i, -0.85 * on)
	_rk(rig, "tail", 0.85 * on)
	_wings_fold(rig, 0.95)
	## The stroke: wind the head back, then drive it. Ninety percent of the
	## travel happens in the last fifteen percent of the swing.
	_rk(rig, "neck", (0.45 - 0.85 * strike) * on)
	_rk(rig, "head", (0.30 - 0.75 * strike) * on + 0.20 * clear,
		0.85 * sin(clear * PI * 6.0) * clear, 0.15 * sin(f * 0.5))
	_pk(rig, "head", Vector3(0, 0, -0.05 * u * strike * on))
	_rk(rig, "crest", -0.35 * on - 0.25 * strike)


static func _drum_roll(rig: Dictionary, t: float, u: float) -> void:
	## Matched to pileated_drum.wav: twenty-one hits, hard and even, in a
	## second and a half. Unlike the grouse this one does NOT accelerate — a
	## woodpecker's roll is a flat machine-gun burst and the difference between
	## the two is how you tell the sounds apart in the dark.
	var ph := t * TAU * 14.0
	var env := _ease_out(_seg(t, 0.0, 0.06)) * (1.0 - _ease_in(_seg(t, 0.86, 1.0)))
	var hit := (0.5 + 0.5 * sin(ph)) * env
	_rk(rig, "body", 1.20 - 0.06 * hit)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "legs", i, 0.60, 0.0, side * 0.45)
		_ri(rig, "knees", i, -0.85)
	_rk(rig, "tail", 0.85)
	_wings_fold(rig, 0.96)
	_rk(rig, "neck", 0.25 - 0.42 * hit)
	_rk(rig, "head", 0.15 - 0.35 * hit)
	_pk(rig, "head", Vector3(0, 0, -0.045 * u * hit))
	_pk(rig, "root", Vector3(0, 0.006 * u * hit, 0))
	_rk(rig, "crest", -0.30 - 0.20 * hit)


static func _laugh(rig: Dictionary, t: float, u: float) -> void:
	## Matched to pileated_call.wav: the maniacal kuk-kuk-kuk cascade, which
	## descends in both pitch and amplitude. The head snaps back and down on
	## every note and the crest flares on the first one.
	var f := t * 14.0
	var fade := 1.0 - _ease_in(t) * 0.7
	var kuk := pow(maxf(0.0, sin(f * PI)), 2.0) * fade * (1.0 - _ease_in(_seg(t, 0.85, 1.0)))
	_wings_fold(rig, 0.92)
	_rk(rig, "crest", -0.75 * _ease_out(_seg(t, 0.0, 0.10)))
	_rk(rig, "body", -0.25 * kuk)
	_rk(rig, "neck", 0.30 * kuk - 0.10)
	_rk(rig, "head", -0.45 * kuk, 0.25 * sin(t * TAU * 1.5))
	_jaw_open(rig, 0.65 * kuk)
	_rk(rig, "tail", -0.40 * kuk)
	_pk(rig, "root", Vector3(0, 0.008 * u * kuk, 0))


static func _camp_rob(rig: Dictionary, t: float, u: float, delta: float) -> void:
	## A Canada jay taking food off your pack while you are wearing it. Glide
	## in, one braking beat, a snatch without ever really landing, and away.
	## They are completely fearless and the animation should be too.
	var glide := _ease_io(_seg(t, 0.0, 0.42))
	var brake := _pulse(t, 0.48, 0.10)
	var grab := _pulse(t, 0.56, 0.05)
	var away := _ease_in(_seg(t, 0.60, 1.0))
	_pk(rig, "root", Vector3(0, 0.85 * u * (1.0 - glide) + 0.9 * u * away,
		-1.5 * u * glide + 1.1 * u * away))
	if t > 0.42 and t < 0.70:
		_blur(rig, _at(rig, "wings", 0), 1.10, 14.0, delta)
		_blur(rig, _at(rig, "wings", 1), -1.10, 14.0, delta)
		for i in 2:
			_si(rig, "wings", i, Vector3.ONE)
	else:
		_flap(rig, t * TAU * 4.0, 0.35 + 0.65 * away, 0.05)
	_rk(rig, "body", -0.15 * glide + 0.85 * brake + 0.25 * away)
	_rk(rig, "neck", -0.30 * glide - 0.20 * grab)
	_rk(rig, "head", -0.25 * glide - 0.30 * grab, 0.20 * sin(t * TAU))
	_jaw_open(rig, 0.55 * grab)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "legs", i, 1.15 * brake - 0.85 * away, 0.0, side * 0.25 * brake)
		_ri(rig, "knees", i, -0.85 * brake + 0.55 * away)
	_sk(rig, "tail", Vector3(1.0 + 0.45 * brake, 1.0, 1.0))
	_rk(rig, "tail", -0.45 * brake)


static func _glide_in(rig: Dictionary, t: float, u: float) -> void:
	## A long flat glide onto a branch with one adjusting beat in the middle
	## of it. Canada jays travel between trees this way and it is almost
	## soundless.
	var down := _ease_io(t)
	var fix := _pulse(t, 0.45, 0.07)
	var land := _seg(t, 0.82, 1.0)
	_pk(rig, "root", Vector3(0, 1.3 * u * (1.0 - down), -2.0 * u * down))
	_wings_v(rig, 0.12 + 0.55 * fix, 0.10)
	if land > 0.0:
		_wings_fold(rig, _snap(land))
	_rk(rig, "body", -0.10 + 0.30 * fix + 0.80 * _ease_out(_seg(t, 0.78, 0.92)) - 0.55 * _seg(t, 0.92, 1.0))
	_rk(rig, "neck", 0.10)
	_rk(rig, "head", -0.20 + 0.20 * land, 0.25 * sin(t * TAU * 0.8))
	for i in 2:
		_ri(rig, "legs", i, -0.70 * (1.0 - land) + 1.05 * land)
		_ri(rig, "knees", i, 0.45 * (1.0 - land) - 0.75 * land)
	_sk(rig, "tail", Vector3(1.0 + 0.4 * land, 1.0, 1.0))


static func _omen_perch(rig: Dictionary, t: float, _u: float) -> void:
	## The White Raven does one thing: it is already there when you look up,
	## and it is already looking at you. Perfect stillness, one deliberate head
	## turn, a half-open mantle, and a shimmer that is never quite bright
	## enough to be sure about.
	var turn := _ease_io(_seg(t, 0.28, 0.42))
	var mantle := _ease_io(_seg(t, 0.55, 0.70)) * (1.0 - _ease_io(_seg(t, 0.88, 1.0)))
	_still(rig)
	_wings_fold(rig, 0.95 - 0.55 * mantle)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "wings", i, 0.0, -(0.85 * (0.95 - 0.55 * mantle)) * side,
			(-0.12 + 0.35 * mantle) * side)
	_rk(rig, "neck", 0.05, -0.30 * turn)
	_rk(rig, "head", -0.05, -0.95 * turn, 0.15 * _pulse(t, 0.80, 0.06))
	_rk(rig, "body", 0.05 * mantle)
	_rk(rig, "tail", 0.10 - 0.20 * mantle)
	## Not a pulse — a breath. Slow enough that the player is not sure it moved.
	_emit_wave(rig, 0.55 + 0.25 * sin(t * TAU * 0.5), 0.30, t * TAU * 0.8)
	for i2 in 2:
		_ri(rig, "legs", i2, 0.0)
		_ri(rig, "knees", i2, 0.0)


## ============================= WATER BIRDS ================================


static func _loon_wail(rig: Dictionary, t: float, u: float) -> void:
	## Matched to loon_wail.wav: four seconds of rising-then-falling glissando
	## with an echo off the far shore. The bird holds one pose for the whole
	## note — head back, bill up, neck at full stretch — and sweeps it slowly
	## across the lake. THE sound of the north woods, and it deserves stillness.
	var on := _ease_out(_seg(t, 0.0, 0.15)) * (1.0 - _ease_io(_seg(t, 0.86, 1.0)))
	var sweep := sin(_seg(t, 0.10, 0.90) * PI - PI * 0.5)
	_sk(rig, "neck", Vector3(1.0, 1.0 + 0.30 * on, 1.0))
	_rk(rig, "neck", 0.70 * on, sweep * 0.35 * on)
	_rk(rig, "head", 0.55 * on, sweep * 0.45 * on)
	_jaw_open(rig, 0.35 * on)
	## One long breath's worth of chest, and nothing else.
	_sk(rig, "body", Vector3(1.0, 1.0 + 0.08 * on * sin(t * PI), 1.0))
	_pk(rig, "root", Vector3(0, -0.14 * u, 0))      ## sitting low in the water
	_wings_fold(rig, 0.96)
	for i in 2:
		_ri(rig, "legs", i, 0.85)                   ## feet are behind and under
		_ri(rig, "knees", i, -0.90)
	_rk(rig, "tail", 0.15 * on)


static func _torpedo_dive(rig: Dictionary, t: float, u: float) -> void:
	## No splash. A loon does not jump to dive — it simply pitches forward and
	## is not there any more, and the total absence of drama is the whole
	## reason the player never sees where it comes up.
	var tip := _ease_io(_seg(t, 0.0, 0.35))
	var slide := _ease_in(_seg(t, 0.25, 0.85))
	var kick := _seg(t, 0.55, 0.90)
	_rk(rig, "body", -1.30 * tip)
	_pk(rig, "root", Vector3(0, -0.14 * u - 1.35 * u * slide, -0.35 * u * slide))
	_wings_fold(rig, 0.98)
	_rk(rig, "neck", -0.45 * tip)
	_rk(rig, "head", -0.20 * tip)
	## Two hard leg drives once it is under, and only then.
	for i in 2:
		var a := kick * TAU * 2.0 + (0.0 if i == 0 else PI)
		_ri(rig, "legs", i, 0.55 * tip + 0.75 * sin(a) * kick)
		_ri(rig, "knees", i, -0.70 * tip - 0.45 * maxf(0.0, cos(a)) * kick)
	_rk(rig, "tail", 0.30 * tip)


static func _water_run(rig: Dictionary, t: float, u: float, delta: float) -> void:
	## Loons cannot take off from land and they need a hundred metres of lake
	## to get off water. Feet slapping at six a second, wings hammering, body
	## flat, and the height does not change at all until the very last moment.
	var run := _seg(t, 0.0, 0.82)
	var lift := _ease_in(_seg(t, 0.78, 1.0))
	_pk(rig, "root", Vector3(0, -0.12 * u * (1.0 - lift) + 0.85 * u * lift,
		-2.4 * u * _ease_in(t)))
	_flap(rig, t * TAU * 7.0, 1.05, 0.08)
	_blur(rig, _at(rig, "wings", 0), 1.0, 8.0, delta)
	_blur(rig, _at(rig, "wings", 1), -1.0, 8.0, delta)
	_rk(rig, "body", -0.30 * run + 0.55 * lift)
	## Neck straight out and low — a running loon is a spear with wings.
	_rk(rig, "neck", -0.55 * run + 0.20 * lift)
	_rk(rig, "head", 0.45 * run)
	_bird_legs(rig, t * TAU * 6.0, 0.65 * (1.0 - lift), 0.55 * (1.0 - lift))
	for i in 2:
		if lift > 0.4:
			_ri(rig, "legs", i, -0.95 * lift)
	_rk(rig, "tail", -0.20 * lift)


static func _chick_ride(rig: Dictionary, t: float, u: float) -> void:
	## Two chicks asleep on its back, which is the single most photographed
	## thing a loon does. The adult swims like it is carrying a full cup: no
	## bobbing, no wake, and a slow check over each shoulder.
	var check := sin(t * TAU * 0.5)
	_still(rig)
	_pk(rig, "root", Vector3(0, -0.14 * u, 0))
	## Wings held a fraction out to make the back into a shelf.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_si(rig, "wings", i, Vector3(0.55, 1.0, 0.95))
		_ri(rig, "wings", i, 0.0, -0.55 * side, -0.28 * side)
	_rk(rig, "body", 0.05, 0.02 * check)
	_rk(rig, "neck", 0.10, check * 0.30)
	_rk(rig, "head", -0.20 * absf(check), check * 0.85)
	for i in 2:
		var a := t * TAU * 1.1 + (0.0 if i == 0 else PI)
		_ri(rig, "legs", i, 0.85 + 0.18 * sin(a))
		_ri(rig, "knees", i, -0.90)
	_rk(rig, "tail", 0.10)


static func _penguin_dance(rig: Dictionary, t: float, u: float, delta: float) -> void:
	## The loon's threat display: it rears straight up out of the water and
	## treads to stay there, wings paddling, head shaking. It means leave, and
	## a player who does not is the only way to get bitten by a loon.
	var up := _ease_out(_seg(t, 0.0, 0.22)) * (1.0 - _ease_io(_seg(t, 0.85, 1.0)))
	_rk(rig, "body", 1.35 * up)
	_pk(rig, "root", Vector3(0, -0.14 * u + 0.85 * u * up + 0.03 * u * sin(t * TAU * 5.0) * up, 0))
	_blur(rig, _at(rig, "wings", 0), 0.85 * up, 6.0, delta)
	_blur(rig, _at(rig, "wings", 1), -0.85 * up, 6.0, delta)
	for i in 2:
		_si(rig, "wings", i, Vector3.ONE)
	_rk(rig, "neck", 0.25 * up, 0.10 * sin(t * TAU * 4.0) * up)
	_rk(rig, "head", 0.15 * up, 0.45 * sin(t * TAU * 4.0) * up)
	_jaw_open(rig, 0.35 * up)
	_bird_legs(rig, t * TAU * 5.0, 0.55 * up, 0.45 * up)
	_rk(rig, "tail", 0.35 * up)


static func _statue_stalk(rig: Dictionary, t: float, u: float) -> void:
	## Frozen for five seconds with the neck in an S, and then ONE foot lifts,
	## hangs, and is put down thirty centimetres further on. A heron hunts by
	## being scenery, and any fidget at all in the still phases ruins it.
	var step := _seg(t, 0.35, 0.65)
	var place := _seg(t, 0.62, 0.88)
	_still(rig)
	_wings_fold(rig, 0.96)
	## The coiled S. It never changes during the stalk — the strike is what
	## uses it.
	_rk(rig, "neck", 0.45)
	_rk(rig, "head", -0.55, 0.08 * sin(t * TAU * 0.3))
	_sk(rig, "neck", Vector3(1.0, 0.80, 1.0))
	## One leg, very slowly. _ease_io over a third of the clip is about six
	## times slower than the same step in _bird_legs, which is the point.
	var lift := sin(_ease_io(step) * PI)
	_ri(rig, "legs", 0, 0.55 * lift + 0.30 * _ease_io(place))
	_ri(rig, "knees", 0, -1.15 * lift - 0.20 * _ease_io(place))
	_ri(rig, "legs", 1, -0.10 * _ease_io(place))
	_ri(rig, "knees", 1, 0.05)
	_pk(rig, "body", Vector3(0, 0, -0.06 * u * _ease_io(place)))


static func _spear_strike(rig: Dictionary, t: float, u: float) -> void:
	## The neck coils and then FIRES. A heron strikes in about forty
	## milliseconds and the animation cheats nothing: the extension is one
	## sixth of the clip, driven by _snap, and everything else is before and
	## after.
	var coil := _ease_io(_seg(t, 0.0, 0.50))
	var fire := _snap(_seg(t, 0.50, 0.62))
	var back := _ease_out(_seg(t, 0.66, 0.90))
	var ext := fire * (1.0 - back)
	## Compressed and drawn back, then thrown out to half again its length.
	_sk(rig, "neck", Vector3(1.0, 0.62 * (1.0 - ext) + 1.55 * ext, 1.0))
	_rk(rig, "neck", 0.60 * coil - 1.85 * ext)
	_rk(rig, "head", -0.65 * coil + 0.55 * ext, 0.0)
	_pk(rig, "neck", Vector3(0, 0, -0.30 * u * ext))
	_jaw_open(rig, 0.45 * fire * (1.0 - _seg(t, 0.60, 0.68)))
	_rk(rig, "body", -0.12 * coil + 0.30 * ext - 0.20 * back)
	_wings_fold(rig, 0.94 - 0.25 * fire)
	for i in 2:
		_ri(rig, "legs", i, 0.10 * ext)
		_ri(rig, "knees", i, -0.15 * ext)
	## And it comes back up with something. The lift is slower than the strike.
	_pk(rig, "root", Vector3(0, 0.10 * u * back, 0))


static func _fish_gulp(rig: Dictionary, t: float, u: float) -> void:
	## Bill vertical, and the fish goes down in three visible stages. The bulge
	## travelling down the neck is a scale pulse walked along it, which is
	## exactly the kind of thing boxes are good at.
	var up := _ease_out(_seg(t, 0.0, 0.18))
	var g1 := _pulse(t, 0.30, 0.09)
	var g2 := _pulse(t, 0.52, 0.09)
	var g3 := _pulse(t, 0.74, 0.10)
	var g := g1 + g2 + g3
	_rk(rig, "neck", 1.15 * up)
	_rk(rig, "head", 0.65 * up + 0.20 * g)
	_jaw_open(rig, 0.55 * up + 0.25 * g)
	## The bulge: neck fattens and shortens on each swallow.
	_sk(rig, "neck", Vector3(1.0 + 0.30 * g, 1.0 - 0.10 * g, 1.0 + 0.30 * g))
	_rk(rig, "body", 0.20 * up + 0.10 * g)
	_wings_fold(rig, 0.95)
	for i in 2:
		_ri(rig, "legs", i, 0.06 * g)
		_ri(rig, "knees", i, -0.10 * g)
	_pk(rig, "root", Vector3(0, 0.012 * u * g, 0))


static func _ptero_takeoff(rig: Dictionary, t: float, u: float) -> void:
	## A great blue leaving a bog is the closest thing to a pterosaur anyone
	## alive has seen: enormous slow beats, legs trailing straight out behind,
	## neck folded back into the shoulders. Slow is the whole effect — one and
	## a half beats a second and not one more.
	var go := _ease_out(_seg(t, 0.0, 0.18))
	var ph := t * TAU * 1.6
	## Asymmetric: the downstroke does the work and takes half the time.
	var beat := sin(ph) + 0.35 * sin(ph) * absf(sin(ph))
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_si(rig, "wings", i, Vector3.ONE)
		_ri(rig, "wings", i, 0.0, -0.06 * side, beat * 1.15 * side)
	## Climbs in steps, one per downbeat — herons do not accelerate smoothly.
	_pk(rig, "root", Vector3(0, 1.9 * u * _ease_io(t) + 0.10 * u * cos(ph), -0.8 * u * t))
	_rk(rig, "body", 0.25 * go + 0.10 * cos(ph))
	## Neck folded back on itself; the head sits between the shoulders.
	_sk(rig, "neck", Vector3(1.0 + 0.25 * go, 1.0 - 0.45 * go, 1.0 + 0.25 * go))
	_rk(rig, "neck", 0.55 * go)
	_rk(rig, "head", -0.45 * go, 0.10 * sin(ph * 0.5))
	## Legs straight out behind, and they never move again.
	for i in 2:
		_ri(rig, "legs", i, -1.35 * go)
		_ri(rig, "knees", i, 0.45 * go)
	_sk(rig, "tail", Vector3(1.0 + 0.2 * go, 1.0, 1.0))


static func _hiss_charge(rig: Dictionary, t: float, u: float) -> void:
	## Neck stretched LOW and dead straight, bill open, and it is running at
	## you. Everyone thinks geese are comic until one does this, and the pose
	## is genuinely reptilian — the head goes level and forward, not up.
	var on := _ease_out(_seg(t, 0.0, 0.15))
	var accel := _ease_in(t)
	_sk(rig, "neck", Vector3(1.0, 1.0 + 0.40 * on, 1.0))
	_rk(rig, "neck", -1.35 * on)
	_rk(rig, "head", 1.20 * on, 0.10 * sin(t * TAU * 3.0) * on)
	_pk(rig, "neck", Vector3(0, -0.05 * u * on, -0.10 * u * on))
	_jaw_open(rig, 0.60 * on)
	_rk(rig, "body", -0.28 * on, 0.0, 0.10 * sin(t * TAU * (3.0 + 3.0 * accel)) * on)
	_pk(rig, "root", Vector3(0, 0.02 * u * absf(sin(t * TAU * (3.0 + 3.0 * accel))), 0))
	## Wings half up and out — it is not flying, it is looking bigger.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_si(rig, "wings", i, Vector3(1.0 - 0.35 * (1.0 - on), 1.0, 1.0))
		_ri(rig, "wings", i, 0.0, -0.35 * on * side, (0.55 * on) * side)
	_bird_legs(rig, t * TAU * (3.0 + 3.0 * accel), 0.55 * on, 0.40 * on)


static func _skein(rig: Dictionary, t: float, u: float) -> void:
	## Formation cruise, matched to goose_skein.wav. Deep steady beats, a very
	## slow vertical drift, neck straight out, and nothing else — a skein of
	## these with the phase offset by index reads as a V from the ground.
	var ph := t * TAU * 2.2
	_flap(rig, ph, 0.85, 0.03)
	_pk(rig, "root", Vector3(0, 0.14 * u * sin(ph - 1.1) + 0.35 * u * sin(t * TAU * 0.5),
		-3.0 * u * t))
	_rk(rig, "body", 0.06 + 0.05 * sin(ph - 1.1))
	_sk(rig, "neck", Vector3(1.0, 1.15, 1.0))
	_rk(rig, "neck", -1.15)
	_rk(rig, "head", 1.05, 0.06 * sin(t * TAU * 0.7))
	for i in 2:
		_ri(rig, "legs", i, -1.05)
		_ri(rig, "knees", i, 0.65)
	_rk(rig, "tail", 0.08)


static func _honk(rig: Dictionary, t: float, u: float) -> void:
	## Matched to goose_honk.wav: the short nasal note and then the rising one.
	## The head comes up and forward on each, and the second is bigger.
	var h := 0.6 * _pulse(t, 0.20, 0.09) + _pulse(t, 0.62, 0.12)
	_rk(rig, "neck", 0.30 * h)
	_rk(rig, "head", 0.35 * h)
	_pk(rig, "neck", Vector3(0, 0, -0.05 * u * h))
	_jaw_open(rig, 0.45 * h)
	_sk(rig, "body", Vector3(1.0, 1.0 + 0.05 * h, 1.0))
	_wings_fold(rig, 0.90)
	_rk(rig, "tail", -0.15 * h)


static func _grazing_line(rig: Dictionary, t: float, _u: float) -> void:
	## Head down, two plucks, up, scan, side-step, repeat. Offset by index
	## across a flock this makes the line of heads that comes up in sequence
	## when something walks into the field — which is the actual alarm system,
	## and it is emergent rather than scripted.
	var f := t * 2.0
	var v := fposmod(f, 1.0)
	var down := 1.0 - _seg(v, 0.55, 0.72) + _seg(v, 0.92, 1.0)
	var pluck := _pulse(v, 0.18, 0.08) + _pulse(v, 0.38, 0.08)
	_rk(rig, "neck", -1.15 * down - 0.15 * pluck + 0.35 * (1.0 - down))
	_rk(rig, "head", 0.55 * down - 0.35 * pluck, 0.30 * sin(f * PI) * (1.0 - down))
	_jaw_open(rig, 0.30 * pluck)
	_rk(rig, "body", -0.12 * down, 0.06 * sin(f * PI))
	_bird_legs(rig, f * TAU * 0.5, 0.16, 0.12)
	_wings_fold(rig, 0.94)
	_rk(rig, "tail", 0.10 * down)


static func _duckling_leap(rig: Dictionary, t: float, u: float) -> void:
	## Wood ducks nest in tree cavities and the young get down by jumping —
	## eight metres, on day one, with wings that do not work yet. Legs splayed,
	## everything flailing, and a bounce on landing because they weigh nothing.
	var fall := _gravity(_seg(t, 0.0, 0.86))
	var land := _seg(t, 0.86, 1.0)
	_pk(rig, "root", Vector3(0, 1.7 * u * (1.0 - fall) + 0.10 * u * _bounce(land, 5.0, 9.0), 0))
	_rk(rig, "root", 0.0, 0.30 * sin(t * TAU * 2.0), 0.35 * sin(t * TAU * 3.0) * (1.0 - land))
	## Legs out sideways as far as they go. This is not a technique.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "legs", i, 0.65 - 1.15 * land, 0.0, side * 0.85 * (1.0 - land))
		_ri(rig, "knees", i, -0.30 + 0.45 * land)
	for i in 2:
		var side2 := -1.0 if i == 0 else 1.0
		_si(rig, "wings", i, Vector3.ONE)
		_ri(rig, "wings", i, 0.0, -0.25 * side2,
			(0.75 + 0.35 * sin(t * TAU * 8.0)) * side2 * (1.0 - land))
	_rk(rig, "body", 0.35 * sin(t * TAU * 2.5) * (1.0 - land) + 0.55 * land)
	_rk(rig, "neck", 0.25 - 0.30 * land)
	_rk(rig, "head", -0.15, 0.35 * sin(t * TAU * 3.0))


static func _paddle(rig: Dictionary, t: float, u: float) -> void:
	## Feet alternating below the waterline, the body dead level, and the head
	## nodding forward in time with each stroke. All the effort is invisible,
	## which is the joke everyone makes about ducks and is also true.
	var ph := t * TAU * 2.4
	_pk(rig, "root", Vector3(0, -0.12 * u, 0))
	_rk(rig, "body", 0.03 * sin(ph), 0.04 * sin(ph * 0.5))
	for i in 2:
		var a := ph + (0.0 if i == 0 else PI)
		_ri(rig, "legs", i, 0.55 + 0.65 * sin(a))
		_ri(rig, "knees", i, -0.75 - 0.35 * maxf(0.0, cos(a)))
	_rk(rig, "neck", 0.10 - 0.12 * sin(ph))
	_rk(rig, "head", -0.10 * sin(ph), 0.25 * sin(t * TAU * 0.6))
	_wings_fold(rig, 0.95)
	_rk(rig, "tail", 0.12)


static func _crest_slick(rig: Dictionary, t: float, u: float) -> void:
	## The wood duck's crest flattens back to nothing when it is nervous and
	## springs up again when it is not. A shake in the middle resets it, and
	## the whole clip is one and a half seconds of a bird changing its mind.
	var slick := _ease_out(_seg(t, 0.0, 0.20)) * (1.0 - _ease_io(_seg(t, 0.62, 0.80)))
	var shake := _pulse(t, 0.70, 0.08)
	_still(rig)
	_wings_fold(rig, 0.94)
	_rk(rig, "crest", 0.85 * slick - 0.45 * (1.0 - slick))
	_rk(rig, "neck", -0.20 * slick + 0.10 * shake)
	_rk(rig, "head", 0.15 * slick, 0.75 * sin(t * TAU * 9.0) * shake)
	_sk(rig, "body", Vector3(1.0 - 0.06 * slick, 1.0 - 0.05 * slick, 1.0 + 0.05 * slick))
	_pk(rig, "root", Vector3(0, -0.12 * u, 0))
	_rk(rig, "tail", 0.15 * slick)


static func _hand_steal(rig: Dictionary, t: float, u: float) -> void:
	## A herring gull taking food out of a hand at speed, without landing and
	## without slowing down. It comes in from behind and to the side, and the
	## only part of it that stops moving is the bill.
	var pass_by := _ease_io(t)
	var jab := _pulse(t, 0.52, 0.05)
	var flare := _pulse(t, 0.50, 0.12)
	_pk(rig, "root", Vector3(2.0 * u * (pass_by - 0.5), 0.35 * u * sin(t * PI), -0.8 * u * pass_by))
	_rk(rig, "root", 0.0, -0.55 * (pass_by - 0.5), -0.85 * flare)
	_flap(rig, t * TAU * 3.5, 0.75 + 0.35 * flare, 0.10)
	_rk(rig, "body", 0.15 + 0.45 * flare)
	_rk(rig, "neck", -0.35 * jab, -0.55 * flare)
	_rk(rig, "head", -0.25 * jab, -0.85 * flare)
	_jaw_open(rig, 0.65 * jab)
	for i in 2:
		_ri(rig, "legs", i, -0.85 + 0.55 * flare)
	_sk(rig, "tail", Vector3(1.0 + 0.5 * flare, 1.0, 1.0))
	_rk(rig, "tail", -0.35 * flare)


static func _piling_perch(rig: Dictionary, t: float, _u: float) -> void:
	## One leg, the other tucked into the belly feathers, swaying with the wind
	## on top of a wharf piling. The sway is what makes the one leg readable —
	## a motionless bird on one leg just looks like a modelling error.
	var wind := sin(t * TAU * 0.9) * 0.10 + sin(t * TAU * 1.7 + 1.0) * 0.04
	var shrug := _pulse(t, 0.68, 0.07)
	_still(rig)
	_wings_fold(rig, 0.94 - 0.35 * shrug)
	_rk(rig, "body", 0.03, 0.05 * wind, wind)
	_rk(rig, "neck", 0.05, -wind * 0.6)
	_rk(rig, "head", -0.05, 0.85 * sin(t * TAU * 0.45) - wind * 0.6)
	_ri(rig, "legs", 0, 0.0, 0.0, wind * 0.3)
	_ri(rig, "knees", 0, 0.0)
	_ri(rig, "legs", 1, 1.30)                    ## folded up and out of sight
	_ri(rig, "knees", 1, -1.40)
	_rk(rig, "tail", 0.10, wind * 0.5)


static func _boat_wheel(rig: Dictionary, t: float, u: float) -> void:
	## Gulls wheeling behind a boat: a slow banked circle with three flaps and
	## a long hang, all of them hunting the same patch of water. Every harbour
	## in the game has half a dozen of these doing it at slightly different
	## radii.
	var a := TAU * t
	var bank := 0.45 + 0.12 * sin(t * TAU * 2.0)
	_rk(rig, "root", 0.0, a, bank)
	_pk(rig, "root", Vector3(2.4 * u * sin(a), 0.45 * u * sin(t * TAU * 1.5),
		2.4 * u * (cos(a) - 1.0)))
	## Three beats and then a hang. The hang is longer than the beats.
	var burst := _seg(fposmod(t * 3.0, 1.0), 0.0, 0.45)
	if burst < 1.0:
		_flap(rig, fposmod(t * 3.0, 1.0) * TAU * 3.0, 0.85, 0.06)
	else:
		_wings_v(rig, 0.10, 0.05)
	_rk(rig, "body", 0.05, 0.0, -bank * 0.3)
	_rk(rig, "head", -0.45, 0.55 * sin(a))       ## looking straight down the whole time
	_sk(rig, "tail", Vector3(1.2, 1.0, 1.0))
	for i in 2:
		_ri(rig, "legs", i, -0.85)


static func _whir_flight(rig: Dictionary, t: float, u: float, delta: float) -> void:
	## A puffin flies like a bumblebee: four hundred beats a minute, body
	## rigid, feet trailing, and no gliding at any point. It is not elegant and
	## it is very fast, and the wings should be a smear at all times.
	_blur(rig, _at(rig, "wings", 0), 1.05, 20.0, delta)
	_blur(rig, _at(rig, "wings", 1), -1.05, 20.0, delta)
	for i in 2:
		_si(rig, "wings", i, Vector3.ONE)
	_pk(rig, "root", Vector3(0.25 * u * sin(t * TAU * 1.5), 0.20 * u * sin(t * TAU * 2.0),
		-3.4 * u * t))
	_rk(rig, "root", 0.0, 0.20 * sin(t * TAU * 1.5), 0.25 * sin(t * TAU * 1.5))
	_rk(rig, "body", 0.10)
	_rk(rig, "neck", 0.05)
	_rk(rig, "head", 0.0, 0.15 * sin(t * TAU * 2.5))
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "legs", i, -1.15, 0.0, side * 0.25)
		_ri(rig, "knees", i, 0.35)
	_rk(rig, "tail", 0.05)


static func _fish_mustache(rig: Dictionary, t: float, _u: float) -> void:
	## Standing on a ledge with a dozen sand eels crosswise in its bill,
	## turning its head so you can see them. The turn is a display — it is
	## showing the colony, and it will hold the fish for a minute doing it.
	var up := _ease_out(_seg(t, 0.0, 0.15))
	var turn := sin(t * TAU * 0.75)
	_still(rig)
	_wings_fold(rig, 0.92 - 0.20 * _pulse(t, 0.55, 0.08))
	_rk(rig, "body", 0.35 * up)                  ## upright, penguin-ish
	_rk(rig, "neck", 0.10 * up, turn * 0.35)
	_rk(rig, "head", -0.05 * up, turn * 0.85, 0.10 * turn)
	_jaw_open(rig, 0.22 * up)                    ## bill never fully closes on a load
	_bird_legs(rig, t * TAU * 0.6, 0.12, 0.10)
	_rk(rig, "tail", 0.15 * up)


static func _ledge_shuffle(rig: Dictionary, t: float, u: float) -> void:
	## Sidling along a cliff ledge in tiny fast steps with the wings half out
	## for balance. Puffins are built for water and it shows the moment they
	## have to walk anywhere.
	var ph := t * TAU * 5.0
	_rk(rig, "body", 0.30, 0.10 * sin(ph * 0.5), 0.18 * sin(ph))
	_pk(rig, "root", Vector3(0.35 * u * _ease_io(t), 0.012 * u * absf(sin(ph)), 0))
	_bird_legs(rig, ph, 0.26, 0.30)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_si(rig, "wings", i, Vector3(0.75, 1.0, 1.0))
		_ri(rig, "wings", i, 0.0, -0.35 * side, (0.35 + 0.20 * sin(ph)) * side)
	_rk(rig, "neck", 0.10)
	_rk(rig, "head", -0.10, 0.45 * sin(ph * 0.25))
	_rk(rig, "tail", 0.10, 0.15 * sin(ph))


## ================================ HERPS ===================================


static func _lunge_latch(rig: Dictionary, t: float, u: float) -> void:
	## The neck coils back into the shell, FIRES out to nearly twice its
	## length, and the jaw shuts. Then it holds — a snapper does not let go,
	## it hauls, and the last forty percent of this clip is the player being
	## slowly dragged toward a bog.
	var coil := _ease_io(_seg(t, 0.0, 0.40))
	var fire := _snap(_seg(t, 0.40, 0.50))
	var bite := _snap(_seg(t, 0.50, 0.57))
	var hold := _seg(t, 0.57, 1.0)
	_sk(rig, "neck", Vector3(1.0, 1.0, 1.0 - 0.65 * coil + 1.50 * fire))
	_pk(rig, "neck", Vector3(0, 0, 0.10 * u * coil - 0.28 * u * fire))
	_rk(rig, "neck", 0.22 * coil - 0.35 * fire)
	_rk(rig, "head", -0.18 * coil + 0.30 * fire)
	_jaw_open(rig, 1.25 * fire * (1.0 - bite))
	_rk(rig, "body", -0.16 * coil + 0.26 * fire + 0.06 * sin(hold * TAU * 0.8) * hold)
	## Hauling backwards, with a twist. This is how they take fingers off.
	_rk(rig, "root", 0.0, 0.22 * sin(hold * TAU * 0.6) * hold, 0.14 * sin(hold * TAU * 0.9) * hold)
	_pk(rig, "root", Vector3(0, 0, 0.14 * u * _ease_io(hold)))
	for i in 4:
		var side := -1.0 if i % 2 == 0 else 1.0
		_ri(rig, "legs", i, -0.25 * coil - 0.40 * hold, 0.0, side * 0.20 * hold)
		_ri(rig, "knees", i, -0.30 * hold)


static func _silt_ambush(rig: Dictionary, t: float, u: float) -> void:
	## Settles into the mud until only the head is showing, and then does
	## nothing for as long as it takes. This is the animation that makes the
	## bog dangerous: there is no tell, because being invisible IS the tell.
	var sink := _ease_io(_seg(t, 0.0, 0.45))
	var shuffle := _tri(_seg(t, 0.0, 0.30))
	_pk(rig, "root", Vector3(0, -0.48 * u * sink, 0))
	_rk(rig, "body", -0.10 * sink)
	## Head stays up while everything under it goes down.
	_rk(rig, "neck", 0.55 * sink)
	_rk(rig, "head", -0.30 * sink, 0.08 * sin(t * TAU * 0.3))
	## The legs stir up the silt on the way in and then stop dead.
	for i in 4:
		var side := -1.0 if i % 2 == 0 else 1.0
		_ri(rig, "legs", i, 0.35 * shuffle * sin(t * TAU * 3.0 + float(i)),
			0.0, side * 0.25 * shuffle)
		_ri(rig, "knees", i, -0.30 * shuffle)
	_rk(rig, "tail", 0.20 * sink, 0.25 * shuffle)


static func _road_hiss(rig: Dictionary, t: float, u: float) -> void:
	## On land a snapper stands as TALL as its legs go, which nobody expects
	## from a turtle, and lunges with its mouth open. It cannot retreat into
	## its own shell, so it does the opposite of retreating.
	var up := _ease_out(_seg(t, 0.0, 0.20))
	var lunge := _pulse(t, 0.45, 0.10) + _pulse(t, 0.78, 0.10)
	_pk(rig, "root", Vector3(0, 0.32 * u * up, -0.20 * u * lunge))
	for i in 4:
		var side := -1.0 if i % 2 == 0 else 1.0
		_ri(rig, "legs", i, -0.35 * up, 0.0, side * -0.55 * up)
		_ri(rig, "knees", i, 0.20 * up)
	_rk(rig, "body", -0.18 * up - 0.22 * lunge)
	_sk(rig, "neck", Vector3(1.0, 1.0, 1.0 + 0.35 * up + 0.55 * lunge))
	_rk(rig, "neck", 0.25 * up - 0.30 * lunge)
	_rk(rig, "head", 0.10 * up + 0.20 * lunge, 0.25 * sin(t * TAU * 0.8))
	_jaw_open(rig, 0.85 * up * (0.5 + 0.5 * clampf(lunge, 0.0, 1.0)))
	_rk(rig, "tail", -0.25 * up)


static func _shell_tuck(rig: Dictionary, t: float, u: float) -> void:
	## Everything withdraws at once — and for a snapper it is a half measure,
	## because the shell is far too small for the animal. Half a head still
	## sticks out, which is exactly why the species evolved a temper instead.
	var inn := _ease_out(_seg(t, 0.0, 0.22))
	_sk(rig, "neck", Vector3(1.0 - 0.35 * inn, 1.0 - 0.30 * inn, 1.0 - 0.55 * inn))
	_pk(rig, "neck", Vector3(0, -0.03 * u * inn, 0.14 * u * inn))
	_rk(rig, "neck", -0.20 * inn)
	_rk(rig, "head", 0.15 * inn)
	_jaw_open(rig, 0.10 * inn)
	_pk(rig, "root", Vector3(0, -0.12 * u * inn, 0))
	for i in 4:
		var side := -1.0 if i % 2 == 0 else 1.0
		_ri(rig, "legs", i, 0.55 * inn * (1.0 if i < 2 else -1.0), 0.0, side * 0.75 * inn)
		_ri(rig, "knees", i, -0.85 * inn)
	_rk(rig, "tail", 0.25 * inn, 0.35 * inn)
	## One suspicious re-emergence at the end, about a centimetre of it.
	var peek := _pulse(t, 0.88, 0.09)
	_pk(rig, "neck", Vector3(0, -0.03 * u * inn, 0.14 * u * inn - 0.05 * u * peek))


static func _bask(rig: Dictionary, t: float, u: float) -> void:
	## A painted turtle on a log with all four legs stretched straight out and
	## its face tipped up at the sun. It is a solar panel and it does not move
	## for six seconds except to adjust the angle once.
	var out := _ease_io(_seg(t, 0.0, 0.20))
	var adjust := _pulse(t, 0.62, 0.10)
	_still(rig)
	_rk(rig, "neck", 0.55 * out + 0.12 * adjust)
	_sk(rig, "neck", Vector3(1.0, 1.0, 1.0 + 0.45 * out))
	_rk(rig, "head", 0.35 * out, 0.30 * adjust)
	for i in 4:
		var side := -1.0 if i % 2 == 0 else 1.0
		## Straight out and back, like a thrown starfish.
		_ri(rig, "legs", i, (-0.45 if i < 2 else -0.65) * out, 0.0, side * -0.65 * out)
		_ri(rig, "knees", i, 0.35 * out)
	_rk(rig, "tail", -0.20 * out)
	_pk(rig, "root", Vector3(0, 0.004 * u * sin(t * TAU * 0.5), 0))


static func _log_plop(rig: Dictionary, t: float, u: float) -> void:
	## The sound of the bog: a row of turtles going in one after another as you
	## walk the shore. A shuffle to the edge, a tip, and a drop with the legs
	## still splayed from basking.
	var creep := _ease_io(_seg(t, 0.0, 0.32))
	var tip := _ease_in(_seg(t, 0.34, 0.50))
	var drop := _gravity(_seg(t, 0.48, 0.86))
	var splash := _seg(t, 0.86, 1.0)
	_pk(rig, "root", Vector3(0, -0.60 * u * drop - 0.15 * u * splash,
		-0.16 * u * creep - 0.18 * u * tip))
	_rk(rig, "root", -0.55 * tip + 0.45 * splash)
	for i in 4:
		var side := -1.0 if i % 2 == 0 else 1.0
		var scrabble := sin(creep * TAU * 3.0 + float(i) * 1.6) * 0.25 * (1.0 - tip)
		_ri(rig, "legs", i, scrabble - 0.35 * drop, 0.0, side * (-0.35 - 0.45 * drop))
		_ri(rig, "knees", i, -0.20 * (1.0 - drop))
	_rk(rig, "neck", 0.25 * creep - 0.35 * drop)
	_rk(rig, "head", 0.10 * creep - 0.20 * drop)
	_rk(rig, "tail", 0.20 * drop)


static func _ribbon_flee(rig: Dictionary, t: float, u: float) -> void:
	## The travelling wave at speed. A garter snake leaving is one continuous
	## motion with no start and no stop, and the head leads it — the head is
	## already gone before the tail has decided to.
	_wave_segments(rig, t * TAU * 6.5, 0.42, 0.95)
	_rk(rig, "head", 0.0, 0.30 * sin(t * TAU * 6.5 + 0.9))
	_pk(rig, "root", Vector3(0.10 * u * sin(t * TAU * 3.2), 0, -1.4 * u * t))
	_rk(rig, "root", 0.0, 0.18 * sin(t * TAU * 3.2))
	_rk(rig, "body", 0.0, 0.20 * sin(t * TAU * 6.5))


static func _sun_coil(rig: Dictionary, t: float, u: float) -> void:
	## Coiled on a warm rock. A constant yaw per segment turns the chain into a
	## spiral, which is a two-line trick that produces a genuinely correct
	## snake coil — and then it stops, because a basking snake is a rock that
	## occasionally tastes the air.
	var coil := _ease_io(_seg(t, 0.0, 0.35))
	var segs := _a(rig, "segments")
	for i in segs.size():
		## Increasing turn toward the tail tightens the spiral inward.
		_ri(rig, "segments", i, 0.0, (0.42 + 0.05 * float(i)) * coil)
	_rk(rig, "head", 0.0, -0.55 * coil, 0.25 * coil)
	_pk(rig, "root", Vector3(0, -0.02 * u * coil, 0))
	## The tongue, in the only currency this rig has: a small head bob.
	var flick := _pulse(t, 0.62, 0.035) + _pulse(t, 0.70, 0.035) + _pulse(t, 0.90, 0.035)
	_pk(rig, "head", Vector3(0, 0, -0.04 * u * flick))


static func _jug_o_rum(rig: Dictionary, t: float, u: float) -> void:
	## Matched to bullfrog.wav: three low pulsed notes. The throat inflates to
	## most of the animal's own volume and the mouth stays SHUT the whole time,
	## which is the detail everyone gets wrong — frogs call with a closed mouth
	## by cycling the same lungful of air.
	var n := _pulse(t, 0.18, 0.11) + _pulse(t, 0.50, 0.11) + _pulse(t, 0.82, 0.12)
	_sk(rig, "jaw", Vector3(1.0 + 1.30 * n, 1.0 + 1.55 * n, 1.0 + 0.85 * n))
	_pk(rig, "jaw", Vector3(0, -0.05 * u * n, -0.02 * u * n))
	_rk(rig, "jaw", 0.0)                          ## deliberately shut
	_sk(rig, "body", Vector3(1.0 + 0.08 * n, 1.0 - 0.05 * n, 1.0 - 0.04 * n))
	_rk(rig, "neck", 0.15 * n)
	_rk(rig, "head", 0.20 * n)
	_pk(rig, "root", Vector3(0, 0.012 * u * n, 0))
	for i in 4:
		_ri(rig, "legs", i, 0.0, 0.0, (-0.10 if i % 2 == 0 else 0.10))


static func _leap_splash(rig: Dictionary, t: float, u: float) -> void:
	## Fold, fire, and land flat. All of the power is in the hind legs going
	## from fully folded to fully straight in about eighty milliseconds, and
	## the front legs do nothing at all except stop the face.
	var fold := _ease_io(_seg(t, 0.0, 0.20))
	var fire := _snap(_seg(t, 0.20, 0.30))
	var air := _arc(_seg(t, 0.22, 0.86))
	var land := _seg(t, 0.86, 1.0)
	_pk(rig, "root", Vector3(0, 0.75 * u * air - 0.06 * u * fold, 0))
	_rk(rig, "body", -0.20 * fold + 0.45 * fire - 0.55 * _ease_in(_seg(t, 0.5, 0.9)) + 0.35 * land)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "legs", i, -0.55 * fold + 0.85 * air + 0.65 * land, 0.0, side * -0.45)
		_ri(rig, "knees", i, -0.30 * fold + 0.35 * land)
	for i in range(2, 4):
		var side2 := -1.0 if i % 2 == 0 else 1.0
		_ri(rig, "legs", i, 1.05 * fold - 1.35 * fire - 0.85 * air, 0.0, side2 * -0.75)
		_ri(rig, "knees", i, -1.45 * fold + 1.35 * fire + 0.20 * air)
	_rk(rig, "neck", 0.20 * air - 0.15 * land)
	_rk(rig, "head", 0.10 * air)


static func _freeze_solid(rig: Dictionary, t: float, u: float) -> void:
	## A wood frog spends the winter frozen through with its heart stopped, and
	## comes back. The animation is: draw everything in tight over the first
	## third, and then be a stone. Nothing moves for three and a half seconds —
	## no breath, no sway — and that absolute stillness is the effect. It
	## should read as death, because functionally it is.
	var pull := _ease_io(_seg(t, 0.0, 0.30))
	_still(rig)
	_sk(rig, "body", Vector3(1.0 - 0.10 * pull, 1.0 - 0.08 * pull, 1.0 - 0.10 * pull))
	_pk(rig, "root", Vector3(0, -0.05 * u * pull, 0))
	for i in 4:
		var side := -1.0 if i % 2 == 0 else 1.0
		_ri(rig, "legs", i, (0.85 if i < 2 else 1.05) * pull, 0.0, side * 0.85 * pull)
		_ri(rig, "knees", i, -1.35 * pull)
	_rk(rig, "neck", -0.35 * pull)
	_rk(rig, "head", -0.25 * pull)
	_jaw_open(rig, 0.0)


static func _amble(rig: Dictionary, t: float, u: float) -> void:
	## A red eft crossing a trail in the rain at two centimetres a second. The
	## body waves side to side against the diagonal leg pattern, which is how
	## salamanders have walked since before there were legs worth the name.
	var ph := t * TAU * 0.8
	_rk(rig, "body", 0.0, 0.24 * sin(ph))
	_rk(rig, "neck", 0.0, 0.20 * sin(ph + 0.7))
	_rk(rig, "head", 0.0, 0.22 * sin(ph + 1.2))
	_rk(rig, "tail", 0.0, -0.35 * sin(ph - 0.5))
	for i in 4:
		var a := ph + (0.0 if (i == 0 or i == 3) else PI)
		var side := -1.0 if i % 2 == 0 else 1.0
		_ri(rig, "legs", i, sin(a) * 0.32, 0.0, side * 0.12 * cos(a))
		_ri(rig, "knees", i, -0.22 - 0.25 * maxf(0.0, cos(a)))
	_pk(rig, "root", Vector3(0.02 * u * sin(ph), 0, 0))


static func _scuttle(rig: Dictionary, t: float, u: float) -> void:
	## Sideways, fast, and stopping dead twice. Everything in a tidepool moves
	## like this and none of it moves in the direction it is facing.
	var stop := _pulse(t, 0.38, 0.06) + _pulse(t, 0.80, 0.06)
	var go := 1.0 - clampf(stop, 0.0, 1.0)
	_pk(rig, "root", Vector3(0.9 * u * _ease_io(t), 0.02 * u * absf(sin(t * TAU * 9.0)) * go, 0))
	_rk(rig, "root", 0.0, 1.30 + 0.20 * sin(t * TAU * 4.0) * go)
	_rk(rig, "body", 0.0, 0.0, 0.12 * sin(t * TAU * 9.0) * go)
	for i in 4:
		var side := -1.0 if i % 2 == 0 else 1.0
		_ri(rig, "legs", i, sin(t * TAU * 9.0 + float(i) * 1.6) * 0.45 * go,
			0.0, side * 0.30)
		_ri(rig, "knees", i, -0.30)
	for i in 2:
		var side2 := -1.0 if i == 0 else 1.0
		_ri(rig, "wings", i, 0.0, 0.0, 0.35 * sin(t * TAU * 11.0) * side2 * go)


## =========================== FISH & CETACEANS =============================


static func _roll_arc(rig: Dictionary, t: float, u: float) -> void:
	## A harbour porpoise surfacing: the back comes over in a smooth wheel, the
	## dorsal is the last thing to show, and it is gone. Nobody ever sees the
	## head, so the animation must not show it either.
	var a := t * TAU
	_pk(rig, "root", Vector3(0, 0.55 * u * sin(a) - 0.30 * u, -1.2 * u * t))
	## The whole animal rotates around the arc rather than pitching within it.
	_rk(rig, "root", -0.85 * cos(a))
	_rk(rig, "body", 0.15 * cos(a))
	## Vertical fluke beat — cetaceans, not fish. The idle lateral beat is
	## wrong for these two species and this is where it gets corrected.
	_rk(rig, "tail", 0.35 * sin(a * 2.0), 0.0)
	_rk(rig, "tail2", 0.45 * sin(a * 2.0 - 0.8), 0.0)
	_rk(rig, "head", 0.0, 0.0)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "legs", i, 0.10 * sin(a), 0.0, side * 0.15)


static func _blow_spout(rig: Dictionary, t: float, u: float) -> void:
	## The back rolls up, the blowhole clears with one hard exhale, and it goes
	## down again. In the gulf this is the only part of a whale most players
	## will ever see, so the exhale beat has to be sharp enough to time a
	## screenshot to.
	var up := _ease_io(_seg(t, 0.0, 0.30))
	var blow := _pulse(t, 0.38, 0.05)
	var down := _ease_io(_seg(t, 0.62, 1.0))
	var surf := up - down
	_pk(rig, "root", Vector3(0, 0.30 * u * surf - 0.06 * u * blow, -0.8 * u * t))
	_rk(rig, "root", -0.18 * surf + 0.10 * blow)
	## The exhale is a body-length shudder, not a mouth movement.
	_sk(rig, "body", Vector3(1.0 - 0.03 * blow, 1.0 + 0.05 * blow, 1.0 - 0.02 * blow))
	_rk(rig, "body", 0.08 * surf - 0.12 * blow)
	_rk(rig, "tail", 0.22 * sin(t * TAU * 1.5))
	_rk(rig, "tail2", 0.30 * sin(t * TAU * 1.5 - 0.7))
	_rk(rig, "head", -0.10 * blow)


static func _breach(rig: Dictionary, t: float, u: float) -> void:
	## Thirty tonnes leaving the water. Up on a parabola, rotating past
	## vertical, a roll onto the flank at the top, and then the entire mass
	## coming down again — the landing is the shot, so the fall is faster than
	## the climb and everything rings afterwards.
	var launch := _ease_out(_seg(t, 0.0, 0.18))
	var air := _seg(t, 0.05, 0.72)
	var fall := _ease_in(_seg(t, 0.55, 0.86))
	var hit := _seg(t, 0.86, 1.0)
	_pk(rig, "root", Vector3(0, 0.85 * u * _arc(_seg(t, 0.05, 0.86))
		- 0.20 * u * hit + 0.08 * u * _bounce(hit, 3.0, 6.0), -0.9 * u * _ease_io(t)))
	## Past vertical on the way up, over onto the back at the top.
	_rk(rig, "root", 1.35 * launch - 1.85 * fall, 0.0, 1.25 * _ease_io(air))
	_rk(rig, "body", 0.20 * launch - 0.30 * fall + 0.15 * _bounce(hit, 4.0, 8.0))
	_rk(rig, "tail", 0.55 * launch - 0.35 * fall)
	_rk(rig, "tail2", 0.35 * launch - 0.25 * fall)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "legs", i, -0.55 * launch + 0.35 * fall, 0.0, side * 0.75 * _ease_io(air))
	_jaw_open(rig, 0.35 * launch)


static func _fluke_dive(rig: Dictionary, t: float, u: float) -> void:
	## The back arches high, then the tail comes clear of the water and stands
	## there for a moment before it slides under. That pause with the flukes up
	## is the picture on every whale-watching brochure ever printed and it is
	## worth holding an extra beat for.
	var arch := _ease_io(_seg(t, 0.0, 0.28))
	var pitch := _ease_io(_seg(t, 0.25, 0.55))
	var hold := _seg(t, 0.55, 0.72)
	var slide := _ease_in(_seg(t, 0.72, 1.0))
	_pk(rig, "root", Vector3(0, 0.22 * u * arch - 0.30 * u * pitch - 0.95 * u * slide,
		-0.55 * u * _ease_io(t)))
	_rk(rig, "root", -0.35 * arch - 1.15 * pitch)
	_rk(rig, "body", 0.25 * arch - 0.15 * pitch)
	## Flukes up and held, with the smallest amount of drift in the hold so it
	## is not a freeze-frame.
	_rk(rig, "tail", 0.65 * pitch + 0.04 * sin(hold * TAU * 0.8) - 0.45 * slide)
	_rk(rig, "tail2", 0.45 * pitch - 0.30 * slide)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "legs", i, 0.25 * pitch, 0.0, side * 0.20)


static func _rise_ring(rig: Dictionary, t: float, u: float) -> void:
	## A trout taking something off the surface: drift up, tip over, sip, and
	## turn back down. The ring on the water is a particle's job — the fish's
	## job is the roll, and the roll is what tells you where it went.
	var up := _ease_io(_seg(t, 0.0, 0.42))
	var sip := _pulse(t, 0.50, 0.06)
	var turn := _ease_in(_seg(t, 0.52, 1.0))
	_pk(rig, "root", Vector3(0, 0.45 * u * up - 0.55 * u * turn, -0.25 * u * up))
	_rk(rig, "root", 0.55 * up - 1.05 * turn, 0.0, 0.65 * turn)
	_jaw_open(rig, 0.75 * sip)
	_rk(rig, "head", 0.20 * up - 0.10 * turn)
	## The tail keeps beating throughout; a trout never stops swimming.
	var ph := t * TAU * 3.0
	_rk(rig, "tail", 0.0, 0.28 * sin(ph))
	_rk(rig, "tail2", 0.0, 0.42 * sin(ph - 0.85))
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "legs", i, 0.15 * sin(ph * 0.5), 0.0, side * (0.20 + 0.25 * turn))


static func _falls_leap(rig: Dictionary, t: float, u: float) -> void:
	## Straight up a falls, body vertical, tail beating furiously in mid-air
	## because that is genuinely what they do — a salmon does not stop swimming
	## when it leaves the water, it just gets no purchase.
	var rise := _seg(t, 0.0, 0.55)
	var top := _seg(t, 0.45, 0.70)
	var over := _ease_in(_seg(t, 0.62, 1.0))
	_pk(rig, "root", Vector3(0, 1.9 * u * _arc(_seg(t, 0.0, 0.95)), -1.1 * u * _ease_io(t)))
	_rk(rig, "root", 1.15 * _ease_out(rise) - 1.85 * over, 0.0, 0.55 * over)
	## The beat gets faster in the air, not slower. It is fighting.
	var ph := t * TAU * (5.0 + 6.0 * top)
	_rk(rig, "tail", 0.0, 0.45 * sin(ph))
	_rk(rig, "tail2", 0.0, 0.60 * sin(ph - 0.8))
	_rk(rig, "body", 0.0, 0.20 * sin(ph + 1.2))
	_rk(rig, "head", 0.0, 0.25 * sin(ph + 1.6))
	_jaw_open(rig, 0.25 * top)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "legs", i, 0.0, 0.0, side * 0.35)


static func _hold_current(rig: Dictionary, t: float, u: float) -> void:
	## Station-keeping in moving water: hard steady beats and no forward
	## progress whatsoever, with small lateral corrections as the current
	## shoves it about. A trout holding a lie is doing work to stay still.
	var ph := t * TAU * 4.5
	var shove := sin(t * TAU * 0.7) * 0.6 + sin(t * TAU * 1.3 + 1.0) * 0.4
	_pk(rig, "root", Vector3(0.06 * u * shove, 0.03 * u * sin(t * TAU * 1.1), 0))
	_rk(rig, "root", 0.0, 0.10 * shove, 0.08 * shove)
	_rk(rig, "tail", 0.0, 0.30 * sin(ph))
	_rk(rig, "tail2", 0.0, 0.45 * sin(ph - 0.85))
	_rk(rig, "body", 0.0, -0.10 * sin(ph + 1.2))
	_rk(rig, "head", 0.0, 0.08 * sin(ph + 1.6) - 0.12 * shove)
	_jaw_open(rig, 0.12 + 0.08 * sin(t * TAU * 2.0))    ## gills working
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "legs", i, 0.20 * sin(ph * 0.5), 0.0, side * (0.30 + 0.15 * shove * side))


## ================================ SWARMS ==================================
## Fourteen bats, forty fireflies, sixty blackflies. These run on many
## instances at once, so every function here is a handful of sins and nothing
## else — no phase loops, no per-material work except the firefly, which earns
## it by being the whole reason anyone looks at a field at night.
##
## These are also the one place where _unit() is the wrong yardstick: a bat's
## ribbon is metres wide whatever the bat measures, so each of them floors the
## unit at a real distance instead of scaling off a two-centimetre body.


static func _bat_ribbon(rig: Dictionary, t: float, u: float, delta: float) -> void:
	## The erratic ribbon a bat draws over a mill pond. Three incommensurate
	## frequencies so the path never repeats inside the clip, and a hard bank
	## into every turn — bats corner by falling sideways.
	var m := maxf(u, 0.9)
	var x := sin(t * TAU * 1.7) + 0.5 * sin(t * TAU * 2.9 + 1.0)
	var y := 0.6 * sin(t * TAU * 2.3 + 2.0)
	_pk(rig, "body", Vector3(1.4 * m * x, 0.9 * m * y, 1.1 * m * sin(t * TAU * 1.1)))
	_rk(rig, "body", -0.35 * y, 0.55 * x, -0.85 * cos(t * TAU * 1.7))
	_blur(rig, _at(rig, "wings", 0), 1.10, 11.0, delta)
	_blur(rig, _at(rig, "wings", 1), -1.10, 11.0, delta)


static func _twinkle_drift(rig: Dictionary, t: float, u: float) -> void:
	## A firefly is a light that drifts. The flash is the animation: a fast
	## rise, a held quarter second, and a slow decay — get the asymmetry wrong
	## and it reads as a blinking LED instead of an insect.
	var flash := _ease_in(_seg(t, 0.30, 0.36)) * (1.0 - _ease_out(_seg(t, 0.44, 0.72)))
	_emit(rig, 0.15 + 3.2 * flash)
	## Fireflies rise as they flash and sink between. That vertical sawtooth
	## across a whole field is the effect nobody can name but everyone notices.
	var m := maxf(u, 0.40)
	_pk(rig, "body", Vector3(0.5 * m * sin(t * TAU * 0.7),
		0.9 * m * (t + 0.35 * flash), 0.4 * m * sin(t * TAU * 0.5 + 1.0)))
	_rk(rig, "body", 0.0, 0.35 * sin(t * TAU * 0.7), 0.20 * sin(t * TAU * 0.9))


static func _hover_dart(rig: Dictionary, t: float, u: float, delta: float) -> void:
	## Dead still, then somewhere else. A dragonfly does not accelerate — it
	## teleports, and the hold between darts has to be genuinely motionless for
	## the dart to land.
	var f := t * 3.0
	var i := int(f)
	var v := fposmod(f, 1.0)
	var step := _snap(clampf(v / 0.10, 0.0, 1.0))
	var from := Vector3(_rand(i * 3) - 0.5, _rand(i * 3 + 1) - 0.5, _rand(i * 3 + 2) - 0.5)
	var to := Vector3(_rand(i * 3 + 3) - 0.5, _rand(i * 3 + 4) - 0.5, _rand(i * 3 + 5) - 0.5)
	_pk(rig, "body", from.lerp(to, step) * 3.0 * maxf(u, 0.55))
	_rk(rig, "body", 0.0, (to.x - from.x) * 1.2, 0.0)
	_blur(rig, _at(rig, "wings", 0), 0.85, 30.0, delta)
	_blur(rig, _at(rig, "wings", 1), -0.85, 30.0, delta)


static func _harass_cloud(rig: Dictionary, t: float, u: float, delta: float) -> void:
	## Blackflies orbiting a head. Tight, jittery, and always coming back —
	## the one thing about this state everyone who has been here remembers.
	var m := maxf(u, 0.50)
	var a := t * TAU * 3.0
	var jit := sin(t * TAU * 17.0) * 0.25
	_pk(rig, "body", Vector3((0.8 + jit) * m * sin(a), (0.35 + jit) * m * sin(a * 1.7),
		(0.8 + jit) * m * cos(a)))
	_rk(rig, "body", 0.0, -a, 0.30 * sin(t * TAU * 9.0))
	_blur(rig, _at(rig, "wings", 0), 0.70, 34.0, delta)
	_blur(rig, _at(rig, "wings", 1), -0.70, 34.0, delta)


static func _south_drift(rig: Dictionary, t: float, u: float) -> void:
	## A monarch's flap-flap-glide, on the way to Mexico. The beat is slow
	## enough to see each stroke and the bob is enormous relative to the animal
	## — butterflies do not fly so much as fall upward repeatedly.
	var beat := sin(t * TAU * 4.0)
	var glide := _seg(fposmod(t * 2.0, 1.0), 0.45, 1.0)
	var b := beat * (1.0 - glide * 0.8)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "wings", i, 0.0, 0.0, (0.35 + 1.10 * b) * side)
	var m := maxf(u, 0.55)
	_pk(rig, "body", Vector3(0.6 * m * sin(t * TAU * 0.5), 0.55 * m * b * 0.5 + 1.2 * m * t,
		-1.6 * m * t))
	_rk(rig, "body", 0.25 * b, 0.20 * sin(t * TAU * 0.5), 0.30 * sin(t * TAU * 0.7))


static func _lantern_arrive(rig: Dictionary, t: float, u: float, delta: float) -> void:
	## A luna moth finding a lit window. A wide spiral closing in, a settle,
	## and then the slow open-and-close of the wings that stops people mid
	## sentence. Worth the extra sin: there is only ever one of these.
	var m := maxf(u, 0.75)
	var close := _ease_io(t)
	var a := TAU * 2.2 * (1.0 - close)
	var r := 2.6 * (1.0 - close)
	_pk(rig, "body", Vector3(r * m * sin(a), 0.8 * m * (1.0 - close) * sin(t * TAU * 1.5),
		r * m * cos(a)))
	_rk(rig, "body", 0.0, -a, 0.35 * (1.0 - close) * sin(t * TAU * 1.7))
	if t < 0.72:
		_blur(rig, _at(rig, "wings", 0), 0.95, 9.0, delta)
		_blur(rig, _at(rig, "wings", 1), -0.95, 9.0, delta)
	else:
		## Settled: one slow fold and unfold, about a second and a half.
		var fan := 0.5 + 0.5 * sin(_seg(t, 0.72, 1.0) * TAU)
		for i in 2:
			var side := -1.0 if i == 0 else 1.0
			_ri(rig, "wings", i, 0.0, 0.0, (0.10 + 0.85 * fan) * side)


static func _chorus_hole(rig: Dictionary, t: float, u: float) -> void:
	## Peepers and crickets are audio-only — nothing is ever drawn at the
	## player's distance. This exists so the one instance that does get built
	## has a pulse: a throat sac at three hertz and nothing else at all.
	var pulse := 0.5 + 0.5 * sin(t * TAU * 3.0)
	_sk(rig, "body", Vector3(1.0 + 0.10 * pulse, 1.0 + 0.22 * pulse, 1.0))
	_pk(rig, "body", Vector3(0, 0.02 * u * pulse, 0))


## =============================== LEGENDS ==================================


static func _specter_fade(rig: Dictionary, t: float, u: float) -> void:
	## The Specter Moose going in and out of being there. Emission and alpha
	## move together but not in phase — the glow leads the solidity, so for
	## about half a second it is a light with no animal attached, which is the
	## part that makes people take a screenshot and argue about it.
	var breath := 0.5 + 0.5 * sin(t * TAU)
	var lead := 0.5 + 0.5 * sin(t * TAU - 0.9)
	_emit(rig, 0.35 + 2.4 * lead)
	_alpha(rig, 0.12 + 0.62 * breath)
	## And it drifts. Nothing this heavy should move this smoothly.
	_pk(rig, "root", Vector3(0.10 * u * sin(t * TAU * 0.5), 0.06 * u * sin(t * TAU * 0.75), 0))
	_rk(rig, "body", 0.02 * sin(t * TAU * 0.5))
	_look(rig, 0.35 * sin(t * TAU * 0.33), -0.05)
	_rk(rig, "tail", 0.0, 0.15 * sin(t * TAU * 0.4))


static func _spectral_cross(rig: Dictionary, t: float, u: float) -> void:
	## The Aurora Herd crossing a field in the dark. A trot at the right
	## cadence with the vertical bob removed entirely — they do not touch the
	## ground, and the missing bob is what tells the player that before they
	## consciously notice the glow.
	var ph := t * TAU * 2.6
	_walk_legs(rig, ph, 0.42, 0.22)
	_pk(rig, "root", Vector3(0, 0.0, -2.4 * u * t))   ## deliberately flat: see above
	_rk(rig, "body", 0.0, 0.04 * sin(ph * 0.5), 0.05 * sin(ph * 0.5))
	_look(rig, 0.25 * sin(t * TAU * 0.4), -0.08 + 0.04 * sin(ph))
	_rk(rig, "tail", -0.10, 0.20 * sin(ph * 0.5))
	## A shimmer that travels down the body rather than pulsing all of it at
	## once — the difference between "glowing" and "haunted".
	_emit_wave(rig, 1.10, 0.75, t * TAU * 1.5)
	_alpha(rig, 0.55 + 0.12 * sin(t * TAU * 0.8))


## ================================= BUZZ ===================================
## The generic idle library — none of this is a tell, all of it is life. A
## deer grazes, a fox scratches, a jay preens, and the same fifteen clips run
## on every family through the null-safe setters: a rig with no tail swishes
## nothing and a rig with two legs skips the hind-leg half of a stretch.
## Critter._idle_flavour rolls these far more often than the species
## signatures, off buzz_for(family), so a field of animals is never furniture.
## Same house rules as everything above: pure in t, rest-relative, radians.


static func buzz_for(family: String) -> Array:
	## Weighted candidate list per rig family — duplicates are the weights.
	match family:
		"CERVID", "CHUNK", "URSID", "RODENT_S":
			return ["graze", "graze", "graze", "sniff_ground", "paw_ground", "huff_toss",
				"wet_shake", "look_about", "look_about", "stretch", "sit_rest", "tail_swish"]
		"CANID", "FELID", "MUSTELID":
			return ["sniff_ground", "sniff_ground", "scratch", "stretch", "wet_shake",
				"look_about", "look_about", "sit_rest", "tail_swish", "huff_toss"]
		"BIRD_GROUND", "BIRD_RAPTOR", "BIRD_PERCH", "BIRD_WATER":
			return ["peck_ground", "peck_ground", "preen", "ruffle", "wing_stretch",
				"look_about", "wet_shake"]
		"HERP", "FISH":
			return ["sun_bask", "look_about"]
		_:
			return []


static func _env(t: float, a: float, b: float) -> float:
	## Ease in over 0..a, hold, ease out over b..1. Every "get down there, stay
	## a while, come back up" clip below is shaped by one of these.
	return _ease_io(_seg(t, 0.0, a)) * (1.0 - _ease_io(_seg(t, b, 1.0)))


static func _graze(rig: Dictionary, t: float, u: float) -> void:
	## Nose to the ground, three tugs at the grass, chewing in between. The
	## body dips with the neck because on a boxy rig the neck alone does not
	## reach — a real deer splays its front legs for the same reason.
	var down := _env(t, 0.22, 0.80)
	var tug := minf(1.0, _pulse(t, 0.34, 0.05) + _pulse(t, 0.48, 0.05) + _pulse(t, 0.63, 0.05))
	var chew := down * maxf(0.0, sin(t * TAU * 7.0)) * (1.0 - tug)
	_rk(rig, "body", -0.18 * down)
	_pk(rig, "root", Vector3(0, -0.07 * u * down, 0))
	_rk(rig, "neck", -1.35 * down + 0.30 * tug)
	_rk(rig, "head", -0.55 * down + 0.25 * tug)
	_jaw_open(rig, 0.28 * chew)
	_ears(rig, 0.15 * down, -0.20 * down)
	for i in 2:
		_ri(rig, "legs", i, 0.22 * down)
		_ri(rig, "knees", i, -0.10 * down)
	_rk(rig, "tail", 0.0, 0.12 * sin(t * TAU * 1.5) * down)


static func _sniff_ground(rig: Dictionary, t: float, u: float) -> void:
	## Head low and sweeping, ears forward, the front feet creeping along
	## under it. A fox reads a trail like this; a deer checks the ground.
	var down := _env(t, 0.18, 0.85)
	var sweep := sin(t * TAU * 1.5) * down
	_rk(rig, "neck", -1.0 * down, 0.25 * sweep)
	_rk(rig, "head", -0.45 * down, 0.35 * sweep)
	_rk(rig, "body", -0.10 * down)
	_pk(rig, "root", Vector3(0, -0.03 * u * down, 0))
	_jaw_open(rig, 0.06 * down * maxf(0.0, sin(t * TAU * 9.0)))
	_ears(rig, -0.05 * down, 0.25 * down)
	for i in 2:
		var raise := maxf(0.0, sin(t * TAU * 1.5 + (0.0 if i == 0 else PI))) * down
		_ri(rig, "legs", i, 0.18 * raise)
		_ri(rig, "knees", i, -0.35 * raise)


static func _paw_ground(rig: Dictionary, t: float, u: float) -> void:
	## Front-left leg scrapes back three times: a slow lift forward, a quick
	## drag, the body dipping on the drag while the head looks at what it dug.
	var look := _env(t, 0.15, 0.90)
	var scrape := 0.0
	var drag := 0.0
	for k in 3:
		var c := 0.22 + float(k) * 0.24
		scrape += _pulse(t, c, 0.12)
		drag += _pulse(t, c + 0.10, 0.06)
	scrape = minf(scrape, 1.0)
	drag = minf(drag, 1.0)
	_ri(rig, "legs", 0, 0.55 * scrape - 0.35 * drag)
	_ri(rig, "knees", 0, -0.90 * scrape)
	_pk(rig, "root", Vector3(0, -0.03 * u * drag, 0))
	_rk(rig, "body", -0.06 * drag, 0.0, 0.06 * scrape)
	_rk(rig, "neck", -0.45 * look)
	_rk(rig, "head", -0.35 * look, 0.10 * look)
	_ears(rig, 0.10 * look)


static func _huff_toss(rig: Dictionary, t: float, u: float) -> void:
	## Two head throws, up and to alternate sides, ears flicking, the chest
	## puffing on each and a short step back. Idle flavour, not an alarm — it
	## deliberately owns no sound and no species.
	var toss := _pulse(t, 0.25, 0.14) + _pulse(t, 0.62, 0.14)
	var flick := _pulse(t, 0.22, 0.08) + _pulse(t, 0.59, 0.08)
	var side := 1.0 if t < 0.45 else -1.0     ## both pulses are zero at 0.45
	var back := _ease_io(_seg(t, 0.15, 0.55)) * (1.0 - _ease_io(_seg(t, 0.70, 1.0)))
	var step := _pulse(t, 0.35, 0.15)
	_rk(rig, "neck", 0.35 * toss, 0.20 * toss * side)
	_rk(rig, "head", 0.45 * toss, 0.35 * toss * side, 0.15 * toss * side)
	_ears(rig, 0.6 * flick, 0.0, 0.3 * flick)
	_sk(rig, "body", Vector3(1.0 + 0.04 * toss, 1.0 + 0.05 * toss, 1.0))
	_jaw_open(rig, 0.25 * flick)
	_pk(rig, "root", Vector3(0, 0, 0.04 * u * back))
	_ri(rig, "legs", 2, -0.25 * step)
	_ri(rig, "knees", 2, -0.40 * step)


static func _wet_shake(rig: Dictionary, t: float, u: float) -> void:
	## The wet-dog shake on anything: a ~6 Hz roll that starts at the head and
	## runs back to the tail a quarter-turn behind, ears flapping, and dies
	## out to exactly rest before the clip ends.
	var on := _ease_out(_seg(t, 0.0, 0.12)) * (1.0 - _ease_io(_seg(t, 0.72, 1.0)))
	var ph := t * TAU * 8.4
	var head := sin(ph) * on
	var body := sin(ph - 0.9) * on
	var tail := sin(ph - 1.8) * on
	_rk(rig, "head", 0.0, 0.25 * head, 0.45 * head)
	_rk(rig, "neck", 0.0, 0.10 * body, 0.25 * body)
	_rk(rig, "body", 0.0, 0.05 * body, 0.30 * body)
	_rk(rig, "tail", 0.0, 0.35 * tail, 0.25 * tail)
	_rk(rig, "tail2", 0.0, 0.30 * tail)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "ears", i, -0.12 - 0.20 * absf(head), 0.0, side * (0.35 * head + 0.25 * on))
	_crouch(rig, 0.25 * on, u)


static func _stretch(rig: Dictionary, t: float, u: float) -> void:
	## The downward dog: front legs slide out, chest to the ground, head up
	## and held. Then it stands and pushes each hind leg out behind it.
	var bow := _ease_io(_seg(t, 0.0, 0.25)) * (1.0 - _ease_io(_seg(t, 0.48, 0.60)))
	var b1 := _pulse(t, 0.70, 0.12)
	var b2 := _pulse(t, 0.90, 0.12)
	for i in 2:
		_ri(rig, "legs", i, 0.85 * bow)
		_ri(rig, "knees", i, 0.10 * bow)
	_pk(rig, "root", Vector3(0, -0.10 * u * bow, 0.03 * u * bow))
	_rk(rig, "body", -0.30 * bow + 0.05 * (b1 + b2))
	_rk(rig, "neck", 0.55 * bow)
	_rk(rig, "head", 0.30 * bow)
	_rk(rig, "tail", -0.30 * bow)
	_ri(rig, "legs", 2, -0.75 * b1)
	_ri(rig, "knees", 2, 0.35 * b1)
	_ri(rig, "legs", 3, -0.75 * b2)
	_ri(rig, "knees", 3, 0.35 * b2)


static func _look_about(rig: Dictionary, t: float, _u: float) -> void:
	## A slow turn to one side, a hold, over to the other, a hold, and back.
	## Ears lead the head by half the angle.
	var yaw := 0.7 * _ease_io(_seg(t, 0.05, 0.25)) - 1.4 * _ease_io(_seg(t, 0.40, 0.62)) \
		+ 0.7 * _ease_io(_seg(t, 0.80, 1.0))
	_look(rig, yaw, 0.08 * _env(t, 0.2, 0.85))
	_ears(rig, -0.05, yaw * 0.5)


static func _scratch(rig: Dictionary, t: float, u: float) -> void:
	## Back-left foot up and kicking at the ear, five or six times, the head
	## tipped down to meet it and the body leaning off the lifted leg. On a
	## two-legged rig only the head tilt survives, which is fine.
	var on := _env(t, 0.18, 0.85)
	var kick := maxf(0.0, sin(t * TAU * 8.0)) * on
	var quad := _a(rig, "legs").size() >= 4
	_rk(rig, "neck", -0.15 * on, 0.30 * on, -0.25 * on)
	_rk(rig, "head", -0.10 * on + 0.05 * kick, 0.35 * on, -0.35 * on)
	_ears(rig, 0.30 * on, 0.0, 0.2 * kick)
	if not quad:
		return
	_ri(rig, "legs", 2, 0.90 * on + 0.35 * kick, 0.0, -0.35 * on)
	_ri(rig, "knees", 2, -1.20 * on + 0.50 * kick)
	_rk(rig, "body", 0.0, 0.0, 0.18 * on)
	_pk(rig, "root", Vector3(0.03 * u * on, -0.02 * u * on, 0))


static func _sit_rest(rig: Dictionary, t: float, u: float) -> void:
	## Hindquarters down, front legs propped, a slow scan, and back up. Held
	## for most of the clip because sitting is the point.
	var sit := _ease_io(_seg(t, 0.0, 0.18)) * (1.0 - _ease_io(_seg(t, 0.82, 1.0)))
	for i in [2, 3]:
		_ri(rig, "legs", i, 1.10 * sit)
		_ri(rig, "knees", i, -1.60 * sit)
	for i in 2:
		_ri(rig, "knees", i, -0.15 * sit)
	_pk(rig, "root", Vector3(0, -0.10 * u * sit, 0))
	_rk(rig, "body", 0.22 * sit)
	_pk(rig, "body", Vector3(0, -0.04 * u * sit, 0.02 * u * sit))
	_rk(rig, "neck", -0.15 * sit)
	_rk(rig, "head", -0.05 * sit, 0.25 * sin(t * TAU * 0.8) * sit)
	_rk(rig, "tail", 0.35 * sit)


static func _tail_swish(rig: Dictionary, t: float, _u: float) -> void:
	## Three lazy figure-eights, the tip trailing the base.
	var on := _env(t, 0.10, 0.90)
	var ph := t * TAU * 3.0
	_rk(rig, "tail", (-0.10 + 0.18 * sin(ph * 2.0)) * on, 0.55 * sin(ph) * on)
	_rk(rig, "tail2", 0.12 * sin(ph * 2.0 - 0.6) * on, 0.45 * sin(ph - 0.7) * on)


static func _peck_ground(rig: Dictionary, t: float, u: float) -> void:
	## Head down and six quick pecks, the whole body dipping with each.
	var down := _env(t, 0.15, 0.90)
	var pk := 0.0
	for k in 6:
		pk += _pulse(t, 0.22 + float(k) * 0.11, 0.05)
	pk = minf(pk, 1.0)
	_rk(rig, "neck", -0.70 * down - 0.35 * pk)
	_rk(rig, "head", -0.40 * down - 0.45 * pk)
	_pk(rig, "neck", Vector3(0, -0.02 * u * down, -0.03 * u * pk))
	_rk(rig, "body", -0.12 * down - 0.05 * pk)
	_pk(rig, "root", Vector3(0, -0.02 * u * (down + pk), 0))
	_jaw_open(rig, 0.20 * pk)
	_rk(rig, "tail", 0.10 * down + 0.08 * pk)


static func _preen(rig: Dictionary, t: float, _u: float) -> void:
	## Head round to one wing, the wing lifting a touch to meet it, a run of
	## nibbles, then the other side.
	var a := _ease_io(_seg(t, 0.05, 0.20)) * (1.0 - _ease_io(_seg(t, 0.40, 0.50)))
	var b := _ease_io(_seg(t, 0.55, 0.70)) * (1.0 - _ease_io(_seg(t, 0.90, 1.0)))
	var side := a - b
	var both := a + b
	var nib := maxf(0.0, sin(t * TAU * 10.0)) * both
	_rk(rig, "neck", -0.25 * both, 0.60 * side)
	_rk(rig, "head", -0.35 * both, 1.00 * side, 0.30 * side)
	_jaw_open(rig, 0.25 * nib)
	_wings_fold(rig, 0.92)
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var lift := a if i == 0 else b
		_ri(rig, "wings", i, 0.0, -0.78 * s, (-0.11 + 0.35 * lift) * s)


static func _ruffle(rig: Dictionary, t: float, _u: float) -> void:
	## Every feather up at once: body puffs, wings shiver briefly, the tail
	## fans, and it all settles.
	var puff := _ease_out(_seg(t, 0.0, 0.15)) * (1.0 - _ease_io(_seg(t, 0.55, 1.0)))
	var flut := sin(t * TAU * 9.0) * _env(t, 0.10, 0.60)
	_sk(rig, "body", Vector3(1.0 + 0.14 * puff, 1.0 + 0.10 * puff, 1.0 + 0.10 * puff))
	_sk(rig, "head", Vector3(1.0 + 0.10 * puff, 1.0 + 0.10 * puff, 1.0 + 0.05 * puff))
	_rk(rig, "head", 0.10 * puff)
	_wings_fold(rig, 0.75)
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		_ri(rig, "wings", i, 0.0, -0.64 * s, (-0.09 + 0.25 * absf(flut) + 0.20 * flut) * s)
	_tail_lift(rig, 0.15 * puff, 1.0 + 0.6 * puff)


static func _wing_stretch(rig: Dictionary, t: float, _u: float) -> void:
	## One wing out to full span and held, the same-side leg pushed back
	## under it; fold; then the other. The bird leans off the stretched side.
	var a := _ease_io(_seg(t, 0.05, 0.25)) * (1.0 - _ease_io(_seg(t, 0.42, 0.52)))
	var b := _ease_io(_seg(t, 0.55, 0.75)) * (1.0 - _ease_io(_seg(t, 0.90, 1.0)))
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var amt := a if i == 0 else b
		_si(rig, "wings", i, Vector3(lerpf(0.18, 1.0, amt), 1.0, lerpf(0.85, 1.0, amt)))
		_ri(rig, "wings", i, 0.0, -0.78 * (1.0 - amt) * s, (0.70 * amt - 0.11 * (1.0 - amt)) * s)
		_ri(rig, "legs", i, -0.50 * amt)
		_ri(rig, "knees", i, 0.30 * amt)
	_rk(rig, "body", 0.0, 0.0, 0.08 * (b - a))
	_rk(rig, "head", 0.0, 0.30 * (a - b))


static func _sun_bask(rig: Dictionary, t: float, u: float) -> void:
	## Flatten, widen, lift the face, and hold. Fins and legs spread a little
	## to catch more of it.
	var on := _env(t, 0.20, 0.88)
	_sk(rig, "body", Vector3(1.0 + 0.12 * on, 1.0 - 0.10 * on, 1.0 + 0.04 * on))
	_pk(rig, "root", Vector3(0, -0.03 * u * on, 0))
	_rk(rig, "neck", 0.30 * on)
	_rk(rig, "head", 0.25 * on + 0.05 * sin(t * TAU * 0.7) * on)
	for i in _a(rig, "legs").size():
		var side := -1.0 if i % 2 == 0 else 1.0
		_ri(rig, "legs", i, 0.0, 0.0, side * 0.35 * on)
		_ri(rig, "knees", i, 0.20 * on)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ri(rig, "wings", i, 0.0, 0.0, 0.30 * on * side)
	_rk(rig, "tail", 0.10 * on)
