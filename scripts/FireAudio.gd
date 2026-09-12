class_name FireAudio
extends Node

## ===========================================================================
## THE FIRE'S VOICE — scripts/FireAudio.gd
##
## `c89be45` gave Myrkfell a fire that burns, and `3a24658` gave it twenty-five
## croft hearths to burn in. Every one of them was SILENT. You could stand in a
## crofter's yard at midnight with a flame at your knees and hear the wind.
##
## Two things make this more than "add an AudioStreamPlayer3D to Firepit".
##
## 1. THE CRACKLE COMES OFF THE FLAME SIGNAL, NOT OFF A TIMER.
##    `Firepit.flame_signal(t)` is one number in 0..1 that the light's flicker
##    is computed from. This node reads the SAME number to decide when the fire
##    pops. So the crackle lands on the frame the flame brightens, and sound
##    and light can never drift apart — the trick `StepAudio` used to hang the
##    footstep off `Player.gait_phase`'s bob peaks instead of a step timer.
##    The rate scales with how hard the fire is burning: a fed campfire pops
##    several times a second, a dying one every couple of seconds.
##
## 2. TWENTY-SIX FIRES, THREE VOICES.
##    You cannot give a hearth-per-croft its own looping player: that is
##    twenty-six streams mixing at all times, most of them a kilometre away.
##    Instead this node is the FIRE BUS. Four times a second it ranks the
##    fires by distance to the listener and hands the nearest `BEDS` of them a
##    bed each, and the assignment is STABLE — a fire that already holds a bed
##    and is still in the top three keeps the same slot, so walking past a
##    croft does not restart the fire you are standing at.
##
## It spends that one ranked query on a third thing that is not audio at all,
## and says so out loud rather than pretending otherwise: `Firepit.apply_shadows`
## promotes exactly ONE fire in the world — the nearest burning one — to a
## shadow-casting light. That is the "light spill" half of the round, and it is
## here because this node already knows which fire that is, and because
## twenty-six lights each deciding for themselves is twenty-six distance
## queries a frame for an answer only one of them can have.
##
## Degrades to silence with no pack (`tools/firesounds.py` writes it), and is
## headless-safe: `boot()` is idempotent because a node parented from
## `_init()` never gets `_ready()` — the trap `StepAudio` and `WaterAudio` were
## both bitten by. Every pure decision in here is a static function taking
## plain data, so the whole mix can be tested with no world, no player and no
## audio device.
##
## Wired by World.gd: add_child(FireAudio.new()), then .listener = the player.
## ===========================================================================

const DIR := "res://assets/audio/fire/"
const MANIFEST := DIR + "manifest.json"

## --- the bus ----------------------------------------------------------------
const HEAR_R := 42.0            ## a fire is audible this far off
const BEDS := 3                 ## how many fires can hold a bed at once
const SHOTS := 6                ## voices for crackles and one-shots
const QUERY_GAP := 0.25         ## seconds between listener→fires rankings
const FADE_IN := 1.10           ## seconds for a bed to come up
const FADE_OUT := 1.80          ## ...and to go away. Longer: a fire fades out.

## --- gains, in dB -----------------------------------------------------------
const BED_DB := -7.0            ## a big flame at the stones
const SMALL_DB := -11.0         ## a low one
const EMBER_DB := -21.0         ## coals
const HISS_DB := -13.0          ## rain landing on an open flame
const SILENT_DB := -80.0
const POP_DB := -8.0

## --- what counts as a big fire ---------------------------------------------
const BIG_FUEL := 300.0         ## seconds of fuel above which the bed is the big one

## --- crackles ---------------------------------------------------------------
const POP_HZ_MIN := 0.55        ## pops per second on a nearly-dead flame
const POP_HZ_MAX := 3.30        ## ...and on a fresh one
const POP_WARP := 0.56          ## how far the visible flicker moves that rate
const POP_R := 26.0             ## you hear the pops closer than you hear the bed
const POP_KINDS := 6            ## crackle_1..crackle_6
const SETTLE_KINDS := 3         ## settle_1..settle_3
const SETTLE_EVERY := 11        ## every Nth pop is a log shifting instead

static var _instance: FireAudio = null

var manifest: Dictionary = {}
var listener: Node3D = null

var _streams: Dictionary = {}
var _shots: Array[AudioStreamPlayer3D] = []
var _beds: Array[AudioStreamPlayer3D] = []
var _bed_key: Array[String] = []          ## what each slot is currently playing
var _bed_gain: Array[float] = []          ## eased 0..1 per slot
var _bed_want: Array[float] = []          ## target 0..1 per slot
var _hiss: AudioStreamPlayer3D = null
var _hiss_gain := 0.0
var _claims: Dictionary = {}              ## fire instance id -> bed slot
var _pop_phase: Dictionary = {}           ## fire instance id -> 0..1 accumulator
var _pop_n: Dictionary = {}               ## fire instance id -> pops fired
var _query_t := 0.0
var _ranked: Array = []                   ## ids, nearest first, from the last query
var _by_id: Dictionary = {}               ## id -> Firepit, from the last query
var _missing_warned := false
var _booted := false


# ===========================================================================
#  Boot
# ===========================================================================

func _ready() -> void:
	boot()


func boot() -> void:
	## Idempotent: a node parented from _init() never gets _ready(), and a
	## re-parent runs _ready() a second time.
	if _booted:
		return
	_booted = true
	_instance = self
	add_to_group("fire_audio")
	_load_manifest()
	for _i in range(SHOTS):
		var p := AudioStreamPlayer3D.new()
		p.max_distance = POP_R + 8.0
		p.unit_size = 3.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.bus = "Master"
		add_child(p)
		_shots.append(p)
	for _i in range(BEDS):
		_beds.append(_make_bed())
		_bed_key.append("")
		_bed_gain.append(0.0)
		_bed_want.append(0.0)
	_hiss = _make_bed()


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _make_bed() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.max_distance = HEAR_R + 12.0
	p.unit_size = 6.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.volume_db = SILENT_DB
	p.bus = "Master"
	add_child(p)
	return p


static func get_bus(from: Node) -> FireAudio:
	if _instance != null and is_instance_valid(_instance):
		return _instance
	if from != null and from.is_inside_tree():
		var n := from.get_tree().get_first_node_in_group("fire_audio")
		if n is FireAudio:
			_instance = n as FireAudio
			return _instance
	return null


func _load_manifest() -> void:
	if not FileAccess.file_exists(MANIFEST):
		return
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		manifest = ((parsed as Dictionary).get("sounds", parsed) as Dictionary)


func has_sound(key: String) -> bool:
	return manifest.has(key)


func _stream(key: String) -> AudioStream:
	if _streams.has(key):
		return _streams[key] as AudioStream
	var path := DIR + key + ".wav"
	if not ResourceLoader.exists(path):
		if not _missing_warned:
			_missing_warned = true
			push_warning("FireAudio: no fire audio at %s -- run tools/firesounds.py" % DIR)
		_streams[key] = null
		return null
	var s := load(path) as AudioStream
	var info: Dictionary = manifest.get(key, {}) as Dictionary
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		if bool(info.get("loop", false)):
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = wav_loop_end(w.get_length(), w.mix_rate)
		else:
			w.loop_mode = AudioStreamWAV.LOOP_DISABLED
	_streams[key] = s
	return s


# ===========================================================================
#  The pure decisions — no node, no tree, no clock, no RNG
# ===========================================================================

static func wav_loop_end(length_s: float, mix_rate: int) -> int:
	## The frame a looping bed loops BACK from. Two defects live here and the
	## live pass found both; neither is visible from any pure function and
	## neither errors, logs, or shows up in a green suite.
	##
	## 1. `loop_end = 0` is a ZERO-LENGTH loop. The stream plays through once
	##    and stops, with `loop_mode` still reading LOOP_FORWARD and
	##    `AudioStreamPlayer3D.playing` quietly going false. The first draft of
	##    this file had it -- and so did `scripts/WaterAudio.gd` and
	##    `scripts/CritterAudio.gd`, which is why the lake stopped lapping
	##    eight seconds after you walked up to it and the forest's ambience bed
	##    played exactly once per session. `Weather.gd:788` is the only one in
	##    the project that ever got it right.
	##
	## 2. ⚠ AND THE FRAME COUNT CANNOT COME FROM `data.size()`. Godot's WAV
	##    importer had already re-encoded every one of these to **QOA**, so the
	##    byte count is the COMPRESSED size: 145 480 bytes for a bed of 359 416
	##    frames. Deriving frames from bytes put the loop point at 3.3 s of an
	##    8.15-second bed -- throwing away four and a half seconds of the sound
	##    and landing the seam in the MIDDLE of the file, where nothing was
	##    cross-faded. `get_length()` is decoded seconds whatever the format,
	##    and is the only honest source for this number.
	return maxi(0, int(round(length_s * float(mix_rate))) - 1)


static func bed_key(state: int, fuel: float) -> String:
	## What a fire in this condition sounds like. EMBERS are not a quiet flame,
	## they are a different sound: no roar at all, just coals ticking.
	if state == Firepit.State.LIT:
		return "fire_bed_big" if fuel >= BIG_FUEL else "fire_bed_small"
	if state == Firepit.State.EMBERS:
		return "ember_bed"
	return ""


static func bed_db(key: String) -> float:
	match key:
		"fire_bed_big":
			return BED_DB
		"fire_bed_small":
			return SMALL_DB
		"ember_bed":
			return EMBER_DB
		_:
			return SILENT_DB


static func pop_rate(f01: float, sig: float) -> float:
	## Pops per second. Two terms, and they are different in kind:
	##   f01  how much fuel is left — this is the fire's SIZE, and it decides
	##        the base rate.
	##   sig  Firepit.flame_signal() — the same number the light's flicker is
	##        made of. This is the fire's MOMENT, and it warps the rate up and
	##        down as the flame gutters, so a pop lands when the flame flares.
	var base := POP_HZ_MIN + (POP_HZ_MAX - POP_HZ_MIN) * clampf(f01, 0.0, 1.0)
	var warp := 1.0 - POP_WARP * 0.5 + POP_WARP * clampf(sig, 0.0, 1.0)
	return base * warp


static func pop_key(n: int) -> String:
	## Which sound the nth pop of this fire is. Every SETTLE_EVERY pops a log
	## shifts instead — deterministic, so two fires fed the same wood sound the
	## same, exactly like they burn down to the same second.
	if n > 0 and n % SETTLE_EVERY == 0:
		return "settle_%d" % (1 + ((n / SETTLE_EVERY) % SETTLE_KINDS))
	return "crackle_%d" % (1 + (n % POP_KINDS))


static func hiss_db(burn_rate: float) -> float:
	## The rain layer is gated on the MECHANIC, not on a second reading of the
	## sky: `Firepit.burn_rate()` is 2.0 exactly when rain is landing on an
	## unsheltered flame. So if you can hear the hiss, your wood is going twice
	## as fast, and a roof is the fix. One source of truth, and the sound is
	## information rather than decoration.
	if burn_rate <= 1.0001:
		return SILENT_DB
	return HISS_DB


static func rank_fires(entries: Array, at: Vector3, hear_r: float) -> Array:
	## Ids of the fires that are making a sound at all, nearest first.
	var live: Array = []
	for e in entries:
		var d: Dictionary = e
		if int(d.get("state", Firepit.State.OUT)) == Firepit.State.OUT:
			continue
		var pos: Vector3 = d.get("pos", Vector3.ZERO)
		var dist := pos.distance_to(at)
		if dist > hear_r:
			continue
		live.append({"id": int(d.get("id", -1)), "d": dist})
	live.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]))
	var out: Array = []
	for l in live:
		out.append(int(l["id"]))
	return out


static func assign_beds(prev: Dictionary, ranked: Array, budget: int) -> Dictionary:
	## STABILITY IS THE POINT. A fire already holding a slot and still in the
	## top `budget` keeps THAT slot, so the bed does not restart because you
	## turned around. Freed slots go to newcomers in rank order.
	var keep: Array = ranked.slice(0, budget)
	var out: Dictionary = {}
	var used: Dictionary = {}
	for id in keep:
		if not prev.has(id):
			continue
		var slot := int(prev[id])
		if slot >= 0 and slot < budget and not used.has(slot):
			out[id] = slot
			used[slot] = true
	var free: Array = []
	for s in range(budget):
		if not used.has(s):
			free.append(s)
	for id in keep:
		if out.has(id):
			continue
		if free.is_empty():
			break
		out[id] = int(free.pop_front())
	return out


static func ease_gain(now: float, want: float, delta: float) -> float:
	## A bed never pops in or out. Out is slower than in, because that is what
	## a fire does.
	var span := FADE_IN if want > now else FADE_OUT
	var step := delta / maxf(span, 0.001)
	return clampf(now + clampf(want - now, -step, step), 0.0, 1.0)


static func gain_to_db(gain: float, full_db: float) -> float:
	if gain <= 0.001:
		return SILENT_DB
	return full_db + linear_to_db(gain)


# ===========================================================================
#  The frame
# ===========================================================================

func _process(delta: float) -> void:
	if not _booted:
		boot()
	_query_t -= delta
	if _query_t <= 0.0:
		_query_t = QUERY_GAP
		_requery()
	_drive_beds(delta)
	_drive_pops(delta)


func _requery() -> void:
	_ranked = []
	_by_id = {}
	if listener == null or not is_instance_valid(listener):
		_claims = {}
		return
	var at := listener.global_position
	var fires := get_tree().get_nodes_in_group("fires")
	var entries: Array = []
	for f in fires:
		if not (f is Firepit):
			continue
		var fp := f as Firepit
		if not is_instance_valid(fp) or not fp.is_inside_tree():
			continue
		var id := int(fp.get_instance_id())
		_by_id[id] = fp
		entries.append({"id": id, "pos": fp.here(), "state": fp.state})
	_ranked = rank_fires(entries, at, HEAR_R)
	_claims = assign_beds(_claims, _ranked, BEDS)

	## The one non-audio thing this query pays for, and the reason it is here:
	## exactly one fire in the world gets to cast shadows.
	Firepit.apply_shadows(fires, at)


func _drive_beds(delta: float) -> void:
	for s in range(BEDS):
		_bed_want[s] = 0.0
	var want_key: Array[String] = []
	for s in range(BEDS):
		want_key.append("")
	var hiss_want := 0.0
	var hiss_at := Vector3.ZERO
	for id in _claims:
		var slot := int(_claims[id])
		var fp := _by_id.get(id, null) as Firepit
		if fp == null or not is_instance_valid(fp):
			continue
		var k := bed_key(fp.state, fp.fuel)
		if k == "":
			continue
		want_key[slot] = k
		_bed_want[slot] = 1.0
		_beds[slot].global_position = fp.here()
		if hiss_want <= 0.0 and fp.state == Firepit.State.LIT and fp.burn_rate() > 1.0001:
			hiss_want = 1.0
			hiss_at = fp.here()

	for s in range(BEDS):
		var p := _beds[s]
		var k := want_key[s]
		if k != "" and k != _bed_key[s]:
			## A slot changing what it plays (a flame dropping to embers) has
			## to duck out first, or the swap is a click.
			if _bed_gain[s] > 0.02:
				_bed_want[s] = 0.0
			else:
				var st := _stream(k)
				_bed_key[s] = k
				if st != null:
					p.stream = st
					p.play()
		if _bed_want[s] > 0.0 and _bed_key[s] != "" and p.stream != null and not p.playing:
			## A bed that stopped while it is still wanted comes back. Belt and
			## braces against exactly the failure `wav_loop_end` documents:
			## silence should never be a state the mixer can get stuck in
			## without anybody noticing.
			p.play()
		_bed_gain[s] = ease_gain(_bed_gain[s], _bed_want[s], delta)
		p.volume_db = gain_to_db(_bed_gain[s], bed_db(_bed_key[s]))
		if _bed_gain[s] <= 0.001 and p.playing and _bed_want[s] <= 0.0:
			p.stop()
			_bed_key[s] = ""

	if _hiss != null:
		if hiss_want > 0.0:
			_hiss.global_position = hiss_at
			if not _hiss.playing:
				var hs := _stream("rain_hiss")
				if hs != null:
					_hiss.stream = hs
					_hiss.play()
		_hiss_gain = ease_gain(_hiss_gain, hiss_want, delta)
		_hiss.volume_db = gain_to_db(_hiss_gain, HISS_DB)
		if _hiss_gain <= 0.001 and _hiss.playing and hiss_want <= 0.0:
			_hiss.stop()


func _drive_pops(delta: float) -> void:
	if listener == null or not is_instance_valid(listener):
		return
	var at := listener.global_position
	for id in _ranked:
		var fp := _by_id.get(id, null) as Firepit
		if fp == null or not is_instance_valid(fp):
			continue
		if fp.state != Firepit.State.LIT:
			_pop_phase[id] = 0.0
			continue
		var here := fp.here()
		if here.distance_to(at) > POP_R:
			continue
		var rate := pop_rate(fp.flame01(), fp.signal_now())
		var ph := float(_pop_phase.get(id, 0.0)) + delta * rate
		var fired := 0
		while ph >= 1.0 and fired < 3:
			ph -= 1.0
			fired += 1
			var n := int(_pop_n.get(id, 0))
			_pop_n[id] = n + 1
			_shoot(pop_key(n), here, POP_DB)
		_pop_phase[id] = ph


func _shoot(key: String, at: Vector3, vol_db: float) -> void:
	var s := _stream(key)
	if s == null:
		return
	for p in _shots:
		if not p.playing:
			p.stream = s
			p.global_position = at
			p.volume_db = vol_db
			p.pitch_scale = 1.0
			p.play()
			return


# ===========================================================================
#  One-shots the game fires at the fire
# ===========================================================================

static func play(from: Node, key: String, at: Vector3, vol_db := 0.0) -> void:
	var bus := get_bus(from)
	if bus == null:
		return
	bus._shoot(key, at, vol_db)


# ===========================================================================
#  Read-only, for the F1 god panel and the suite
# ===========================================================================

func readout() -> Dictionary:
	var slots: Array = []
	for s in range(_beds.size()):
		slots.append({"key": _bed_key[s], "gain": snappedf(_bed_gain[s], 0.01)})
	return {
		"audible": _ranked.size(),
		"claims": _claims.size(),
		"slots": slots,
		"hiss": snappedf(_hiss_gain, 0.01),
		"pack": manifest.size(),
	}
