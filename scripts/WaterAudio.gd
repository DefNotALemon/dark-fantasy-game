class_name WaterAudio
extends Node

## ===========================================================================
## THE WATER'S VOICE — lapping shores, the surf, strokes, splashes, and the
## pressure hum when your ears go under.
##
## Same shape as CritterAudio: a generated WAV pack (tools/watersounds.py,
## no recordings) behind a manifest, lazy-loaded, degrading to silence when
## the pack is missing. Two things are different:
##   * the BEDS are positional. Four times a second the node asks the
##     Overworld for the nearest visible water; the lap (or the surf, if it
##     is the sea) plays from THAT point on the shore, so the lake is to your
##     left when it is to your left, and it fades with distance for free.
##   * SUBMERSION owns a low-pass on the Master bus. Under the surface every
##     sound in the game -- thunder, a loon, your own heart -- goes dull, and
##     the underwater bed comes up. The filter is added to the bus at runtime
##     if the project has none, and left at 20 kHz (transparent) on land.
##
## Wired by World.gd when the overworld is on: add_child(WaterAudio.new()),
## then .listener = the player. The Player fires the one-shots through
## WaterAudio.play(self, "splash_in", pos).
## ===========================================================================

const DIR := "res://assets/audio/water/"
const MANIFEST := DIR + "manifest.json"
const QUERY_GAP := 0.25            ## seconds between shoreline queries
const HEAR_R := 60.0               ## the lap carries this far
const VOICES := 6
const UNDER_CUTOFF := 520.0        ## Hz, ears fully under
const DRY_CUTOFF := 20500.0

static var _instance: WaterAudio = null

var manifest: Dictionary = {}
var listener: Node3D = null
var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer3D] = []
var _lap: AudioStreamPlayer3D = null
var _surf: AudioStreamPlayer3D = null
var _under: AudioStreamPlayer = null
var _lowpass: AudioEffectLowPassFilter = null
var _lowpass_idx := -1
var _query_t := 0.0
var _submerged := 0.0              ## eased 0..1
var _missing_warned := false
var _nearest: Dictionary = {"dist": INF}


func _ready() -> void:
	_instance = self
	add_to_group("water_audio")
	_load_manifest()
	_lap = _make_bed_3d()
	_surf = _make_bed_3d()
	_under = AudioStreamPlayer.new()
	_under.volume_db = -80.0
	_under.bus = "Master"
	add_child(_under)
	for _i in range(VOICES):
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 40.0
		p.unit_size = 4.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.bus = "Master"
		add_child(p)
		_voices.append(p)


func _exit_tree() -> void:
	if _instance == self:
		_instance = null
	_set_cutoff(DRY_CUTOFF)


func _make_bed_3d() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.max_distance = HEAR_R + 10.0
	p.unit_size = 9.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.volume_db = -80.0
	p.bus = "Master"
	add_child(p)
	return p


static func get_bus(from: Node) -> WaterAudio:
	if _instance != null and is_instance_valid(_instance):
		return _instance
	if from != null and from.is_inside_tree():
		var n := from.get_tree().get_first_node_in_group("water_audio")
		if n is WaterAudio:
			_instance = n as WaterAudio
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
			push_warning("WaterAudio: no water audio at %s -- run tools/watersounds.py" % DIR)
		_streams[key] = null
		return null
	var s := load(path) as AudioStream
	var info: Dictionary = manifest.get(key, {}) as Dictionary
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		if bool(info.get("loop", false)):
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			## `loop_end = 0` was a ZERO-LENGTH loop: the lap played through
			## once, stopped, and left loop_mode still reading LOOP_FORWARD.
			## Verified live 2026-09-10: `_lap.playing` and `_surf.playing`
			## were both false with the player standing on a shore.
			w.loop_end = FireAudio.wav_loop_end(w.get_length(), w.mix_rate)
		else:
			w.loop_mode = AudioStreamWAV.LOOP_DISABLED
	_streams[key] = s
	return s


## =============================== One-shots ================================


static func play(from: Node, key: String, at: Vector3, vol_db := 0.0) -> void:
	var bus := get_bus(from)
	if bus == null:
		return
	bus._play(key, at, vol_db)


func _play(key: String, at: Vector3, vol_db: float) -> void:
	var s := _stream(key)
	if s == null:
		return
	var v: AudioStreamPlayer3D = null
	for p in _voices:
		if not p.playing:
			v = p
			break
	if v == null:
		return
	v.stream = s
	v.global_position = at
	v.volume_db = vol_db
	v.pitch_scale = randf_range(0.93, 1.08)
	v.play()


## ================================== Beds ==================================


func _process(delta: float) -> void:
	if listener == null or not is_instance_valid(listener):
		return
	_query_t -= delta
	if _query_t <= 0.0:
		_query_t = QUERY_GAP
		_nearest = Overworld.nearest_water(listener.global_position, HEAR_R)
	var dist: float = float(_nearest.get("dist", INF))
	var k := clampf(delta * 3.0, 0.0, 1.0)
	if dist == INF:
		_fade(_lap, -80.0, k)
		_fade(_surf, -80.0, k)
	else:
		var at: Vector3 = _nearest.get("pos", listener.global_position)
		## standing IN the water the bed plays from just beside your head, not
		## from a point under your feet that the 3D falloff would treat as far
		if dist <= 0.0:
			at = listener.global_position + Vector3(0.0, 0.4, 0.0) - listener.global_transform.basis.z * 1.5
		var sea: bool = bool(_nearest.get("sea", false))
		var bed := _surf if sea else _lap
		var other := _lap if sea else _surf
		_ensure_playing(bed, "sea_surf" if sea else "lake_lap")
		bed.global_position = bed.global_position.lerp(at, k) if bed.playing else at
		## quieter with your ears under: the surface is a lid
		_fade(bed, -4.0 - 14.0 * _submerged, k)
		_fade(other, -80.0, k)
	## the underwater hum
	if _submerged > 0.02:
		_ensure_playing_1d(_under, "underwater_bed")
		_under.volume_db = lerpf(_under.volume_db, -10.0 + 8.0 * (1.0 - _submerged), k)
	else:
		_under.volume_db = lerpf(_under.volume_db, -80.0, k)
		if _under.volume_db < -60.0 and _under.playing:
			_under.stop()


func _ensure_playing(p: AudioStreamPlayer3D, key: String) -> void:
	if p.playing:
		return
	var s := _stream(key)
	if s == null:
		return
	p.stream = s
	p.play(randf() * 4.0)


func _ensure_playing_1d(p: AudioStreamPlayer, key: String) -> void:
	if p.playing:
		return
	var s := _stream(key)
	if s == null:
		return
	p.stream = s
	p.play(randf() * 3.0)


func _fade(p: AudioStreamPlayer3D, to_db: float, k: float) -> void:
	p.volume_db = lerpf(p.volume_db, to_db, k)
	if p.volume_db < -60.0 and p.playing and to_db <= -60.0:
		p.stop()


## ============================== Submersion ================================


## 0 = ears in the air, 1 = fully under. The Player feeds this every frame
## from where its camera sits against the water surface.
static func set_submerged(from: Node, u: float) -> void:
	var bus := get_bus(from)
	if bus == null:
		return
	bus._submerged = clampf(u, 0.0, 1.0)
	bus._set_cutoff(lerpf(DRY_CUTOFF, UNDER_CUTOFF, bus._submerged))


func submerged() -> float:
	return _submerged


func _set_cutoff(hz: float) -> void:
	if _lowpass == null:
		var bus_idx := AudioServer.get_bus_index("Master")
		if bus_idx < 0:
			return
		## reuse one that is already on the bus (a project setting, or a
		## previous WaterAudio that did not get to clean up)
		for i in range(AudioServer.get_bus_effect_count(bus_idx)):
			var e := AudioServer.get_bus_effect(bus_idx, i)
			if e is AudioEffectLowPassFilter and e.resource_name == "WaterMuffle":
				_lowpass = e as AudioEffectLowPassFilter
				_lowpass_idx = i
				break
		if _lowpass == null:
			if hz >= DRY_CUTOFF - 1.0:
				return   ## nothing to do on land; do not touch the bus until needed
			_lowpass = AudioEffectLowPassFilter.new()
			_lowpass.resource_name = "WaterMuffle"
			_lowpass.cutoff_hz = DRY_CUTOFF
			_lowpass.resonance = 0.4
			AudioServer.add_bus_effect(bus_idx, _lowpass)
			_lowpass_idx = AudioServer.get_bus_effect_count(bus_idx) - 1
	_lowpass.cutoff_hz = hz
	## the effect itself costs a little every frame; switch it off dry
	var bi := AudioServer.get_bus_index("Master")
	if bi >= 0 and _lowpass_idx >= 0 and _lowpass_idx < AudioServer.get_bus_effect_count(bi):
		AudioServer.set_bus_effect_enabled(bi, _lowpass_idx, hz < DRY_CUTOFF - 1.0)


func report() -> Dictionary:
	return {"sounds": manifest.size(), "nearest": _nearest, "submerged": _submerged,
		"lap": _lap.playing if _lap else false, "surf": _surf.playing if _surf else false,
		"under": _under.playing if _under else false}
