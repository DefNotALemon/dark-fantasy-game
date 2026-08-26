class_name CritterAudio
extends Node

## ===========================================================================
## THE SOUNDSCAPE — half the feature, five percent of the cost.
##                                                     docs/WILDLIFE.md §1
##
## A loon two lakes over costs ONE AudioStreamPlayer3D and buys more Maine
## than a whole herd of meshes. That is why the audio bed is phase 1 of this
## system and not phase 9: you can stand in an empty clearing at dusk with a
## barred owl behind you and a coyote chorus a half mile off and the forest is
## already alive before a single animal has spawned in it.
##
## Two layers:
##   BED     one looping ambience per zone x time-of-day x season, cross-faded.
##           Crickets and peepers live here — they are not creatures, they are
##           weather.
##   CALLS   one-shot positional voices. Fired by Critter._say, and by this
##           node itself for the DISTANT ones — animals that are not spawned
##           and never will be, out past the streaming radius. Most of the
##           wildlife a player hears in a session does not exist.
##
## Sources are generated, not recorded: tools/crittercalls.py synthesises
## every one of them from oscillators and noise, deterministic on a seed, the
## same way leafgen.py makes the leaves. assets/audio/wildlife/manifest.json
## is the contract between the two.
##
## Wired up by World.gd:  add_child(CritterAudio.new())
## ===========================================================================

const DIR := "res://assets/audio/wildlife/"
const MANIFEST := DIR + "manifest.json"

const VOICES := 10               ## concurrent one-shot calls; past this it is mush
const BED_FADE := 3.5            ## seconds to cross-fade one bed into another
const DISTANT_GAP := Vector2(11.0, 34.0)   ## seconds between far-off voices
const CALL_MIN_GAP := 0.35       ## never stack two copies of the same voice

## Distance model. A loon carries; a chipmunk does not.
const CARRY := {
	"loon_wail": 260.0, "loon_yodel": 240.0, "loon_tremolo": 200.0,
	"coyote_chorus": 300.0, "coyote_howl": 240.0, "barred_owl": 180.0,
	"great_horned_owl": 200.0, "snowy_owl_hoot": 160.0, "grouse_drum": 150.0,
	"raven_kraa": 140.0, "crow_caw": 120.0, "moose_bellow": 200.0,
	"fisher_scream": 150.0, "lynx_caterwaul": 140.0, "beaver_slap": 120.0,
	"turkey_gobble": 160.0, "goose_skein": 320.0, "goose_honk": 150.0,
	"pileated_drum": 130.0, "pileated_call": 120.0, "heron_croak": 110.0,
	"eagle_cry": 140.0, "bullfrog": 90.0, "deer_snort": 80.0,
}
const CARRY_DEFAULT := 55.0

static var _instance: CritterAudio = null

var manifest: Dictionary = {}            ## call key -> {file, seconds, loop, ...}
var render_info: Dictionary = {}         ## the seed and rate the pack was made at
var _streams: Dictionary = {}            ## key -> AudioStream (lazy loaded)
var _voices: Array[AudioStreamPlayer3D] = []
var _bed_a: AudioStreamPlayer = null
var _bed_b: AudioStreamPlayer = null
var _bed_key := ""
var _bed_flip := false
var _last_played: Dictionary = {}        ## key -> msec, so we do not double-fire
var _distant_t := 6.0
var _missing_warned := false

## Pushed in by the director every frame or so.
var hour := 17.0
var phase := 0.35
var zone := "deep_woods"
var listener: Node3D = null


func _ready() -> void:
	_instance = self
	add_to_group("critter_audio")
	_load_manifest()
	for _i in range(VOICES):
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 320.0
		p.unit_size = 12.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.bus = "Master"
		add_child(p)
		_voices.append(p)
	_bed_a = AudioStreamPlayer.new()
	_bed_b = AudioStreamPlayer.new()
	for b in [_bed_a, _bed_b]:
		b.volume_db = -80.0
		add_child(b)


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


static func get_bus(from: Node) -> CritterAudio:
	if _instance != null and is_instance_valid(_instance):
		return _instance
	if from != null and from.is_inside_tree():
		var n := from.get_tree().get_first_node_in_group("critter_audio")
		if n is CritterAudio:
			_instance = n as CritterAudio
			return _instance
	return null


func _load_manifest() -> void:
	## No manifest is not an error — it means the generator has not been run
	## yet. Everything downstream degrades to silence rather than to a crash.
	if not FileAccess.file_exists(MANIFEST):
		return
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return
	## crittercalls.py writes the per-call table under "calls", alongside the
	## render settings (seed, sample rate, generator version) it used. Keep
	## reading a bare flat table too, so an older manifest still loads.
	var d := parsed as Dictionary
	manifest = (d.get("calls", d) as Dictionary)
	render_info = {
		"seed": d.get("seed", null), "sample_rate": d.get("sample_rate", null),
		"generator": d.get("generator", null), "version": d.get("version", null),
	}


func has_call(key: String) -> bool:
	if manifest.is_empty():
		return ResourceLoader.exists(DIR + key + ".wav")
	return manifest.has(key)


func _stream(key: String) -> AudioStream:
	if _streams.has(key):
		return _streams[key] as AudioStream
	var path := DIR + key + ".wav"
	if not ResourceLoader.exists(path):
		if not _missing_warned:
			_missing_warned = true
			push_warning("CritterAudio: no wildlife audio at %s — run tools/crittercalls.py" % DIR)
		_streams[key] = null
		return null
	var s := load(path) as AudioStream
	## Beds loop; calls must not, or a loon wails forever.
	var info: Dictionary = manifest.get(key, {}) as Dictionary
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		if bool(info.get("loop", false)):
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = 0
		else:
			w.loop_mode = AudioStreamWAV.LOOP_DISABLED
	_streams[key] = s
	return s


## =============================== One-shots ================================


static func play_at(from: Node, key: String, at: Vector3, vol_db := 0.0) -> void:
	var bus := get_bus(from)
	if bus == null:
		return
	bus._play(key, at, vol_db)


func _play(key: String, at: Vector3, vol_db: float) -> void:
	if key == "":
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(key, -99999)) < int(CALL_MIN_GAP * 1000.0):
		return
	var s := _stream(key)
	if s == null:
		return
	_last_played[key] = now
	## Steal the quietest idle voice; if they are all busy, the call is simply
	## lost. Better a missing raven than a wall of overlapping ravens.
	var v := _free_voice()
	if v == null:
		return
	v.stream = s
	v.global_position = at
	v.max_distance = float(CARRY.get(key, CARRY_DEFAULT))
	v.volume_db = vol_db
	v.pitch_scale = randf_range(0.94, 1.07)   ## no two individuals sound alike
	v.play()


func _free_voice() -> AudioStreamPlayer3D:
	for v in _voices:
		if not v.playing:
			return v
	return null


## ============================ The distant ones ============================


func _distant_tick(delta: float) -> void:
	## The animals that are never spawned. A player hears far more wildlife
	## than the world ever instances, and this is where most of that comes
	## from — pick a plausible species for the zone, hour and season, and put
	## its voice somewhere out past the trees.
	_distant_t -= delta
	if _distant_t > 0.0 or listener == null:
		return
	_distant_t = randf_range(DISTANT_GAP.x, DISTANT_GAP.y)
	var cands: Array = []
	for entry in CritterDex.species_for_zone(zone):
		var k := String(entry["key"])
		var call_key := String((CritterDex.get_profile(k).get("call", {}) as Dictionary).get("idle", ""))
		if call_key == "" or not has_call(call_key):
			continue
		if not CritterDex.is_awake(k, hour, phase):
			continue
		## Nocturnal voices at noon are the fastest way to break the illusion.
		var night := hour >= 20.6 or hour < 6.0
		if CritterDex.flag(k, "night", false) and not night:
			continue
		cands.append({"call": call_key, "w": float(entry["w"]) * float(CARRY.get(call_key, CARRY_DEFAULT))})
	if cands.is_empty():
		return
	var total := 0.0
	for c in cands:
		total += float(c["w"])
	var roll := randf() * total
	for c in cands:
		roll -= float(c["w"])
		if roll <= 0.0:
			var ang := randf() * TAU
			var rad := randf_range(70.0, 180.0)
			var at: Vector3 = listener.global_position + Vector3(cos(ang) * rad, randf_range(-2.0, 8.0), sin(ang) * rad)
			_play(String(c["call"]), at, -6.0)
			return


## ================================= Beds ===================================


func bed_for(z: String, h: float, p: float) -> String:
	## One looping bed at a time. The choice is deliberately coarse — the
	## specific voices come from the one-shot layer, so the bed only has to
	## carry the *texture* of the hour.
	var season := CritterDex.season_of(p)
	var night := h >= 20.6 or h < 6.0
	var wet := z in ["bog", "river", "lake", "moosehead"]
	if season == CritterDex.SPRING and (night or h > 18.6) and wet:
		return "peepers"          ## the spring wall of sound, and nothing else
	if season == CritterDex.SUMMER and night:
		return "crickets"
	if season == CritterDex.SPRING and wet and h > 8.0 and h < 19.0:
		return "blackflies"       ## the true apex predator of Maine
	if season == CritterDex.SUMMER and wet and h > 10.0 and h < 17.0:
		return "blackflies"
	if night:
		return "crickets" if season != CritterDex.WINTER else ""
	return ""


func _bed_tick(_delta: float) -> void:
	var want := bed_for(zone, hour, phase)
	if want != _bed_key:
		_bed_key = want
		var incoming := _bed_b if _bed_flip else _bed_a
		var outgoing := _bed_a if _bed_flip else _bed_b
		_bed_flip = not _bed_flip
		if want != "":
			var s := _stream(want)
			if s != null:
				incoming.stream = s
				incoming.volume_db = -80.0
				incoming.play()
				var t1 := create_tween()
				t1.tween_property(incoming, "volume_db", -14.0, BED_FADE)
		if outgoing.playing:
			var t2 := create_tween()
			t2.tween_property(outgoing, "volume_db", -80.0, BED_FADE)
			t2.tween_callback(outgoing.stop)


func _process(delta: float) -> void:
	_bed_tick(delta)
	_distant_tick(delta)


func set_clock(h: float, p: float, z: String, who: Node3D) -> void:
	hour = h
	phase = p
	zone = z
	listener = who


## ============================== Diagnostics ===============================


func report() -> Dictionary:
	## Used by the test suite and by anyone wondering why it is quiet.
	var have := 0
	var want := 0
	var missing: Array = []
	for k in CritterDex.keys():
		var calls: Dictionary = CritterDex.get_profile(k).get("call", {}) as Dictionary
		for slot in ["idle", "alarm"]:
			var c := String(calls.get(slot, ""))
			if c == "":
				continue
			want += 1
			if has_call(c):
				have += 1
			elif not missing.has(c):
				missing.append(c)
	return {"manifest": manifest.size(), "referenced": want, "found": have, "missing": missing}
