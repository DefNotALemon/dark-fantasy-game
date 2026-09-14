class_name WoodAudio
extends Node

## ===========================================================================
## TIMBER — what iron sounds like on a trunk, and what a tree sounds like
## coming down.
##
## Same shape as StepAudio / FireAudio: a generated WAV pack behind a manifest
## (tools/woodsounds.py, no recordings), lazy-loaded, degrading to silence when
## the pack is missing, a fixed pool of AudioStreamPlayer3D and nothing
## allocated per hit. Wired by World.gd next to StepAudio.
##
## Lemon 2026-09-14: "when a tree is hit it plays a sound. different tools
## should have different sounds." So the key is the TOOL, not the tree:
##
##   axe      the bite -- edge click, a deep chock, chips           (Player axe)
##   sword    a blade in a tree: thin slap with a steel ring        (Player sword)
##   pickaxe  a spike of iron: dull low thunk                        (Player pick)
##   arrow    the thock of a broadhead and the shaft quivering       (Arrow.gd)
##
## and the wood answers with its SIZE: a sapling's pitch sits a fifth above an
## ancient oak's, off the same sample, so a stand of trees does not all make
## one identical knock. FallenTrunk plays the felling: creak at the moment the
## hinge goes (one long groan with the snap on its tail), crash when the crown
## meets the ground, and every bucked log thuds as it rolls onto the dirt.
## ===========================================================================

const DIR := "res://assets/audio/wood/"
const MANIFEST := DIR + "manifest.json"
const VOICES := 6               ## strikes, thuds, limbs
const BIG_VOICES := 3           ## creak / crash: heard across a valley
const STRIKE_VARIANTS := {"axe": 3, "sword": 3, "pick": 3, "arrow": 2}
## current_weapon -> sample family. Anything unlisted (a fist, a mystery
## tool) swings like an axe rather than staying silent.
const TOOL_KEY := {"axe": "axe", "sword": "sword", "pickaxe": "pick",
	"pick": "pick", "arrow": "arrow", "bow": "arrow"}

const STRIKE_DB := {"axe": -3.0, "sword": -7.0, "pick": -4.0, "arrow": -8.0}
const CREAK_DB := -2.0
const CRASH_DB := 1.0
const THUD_DB := -5.0
const LIMB_DB := -6.0
## Pitch by trunk radius, metres: a 0.10 m sapling rings high, a 0.60 m
## ancient sits low. Straight line between the two, clamped.
const R_THIN := 0.10
const R_FAT := 0.60
const PITCH_THIN := 1.28
const PITCH_FAT := 0.84

static var _instance: WoodAudio = null

var manifest: Dictionary = {}
var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer3D] = []
var _big: Array[AudioStreamPlayer3D] = []
var _missing_warned := false
var _booted := false
var _last_key := ""              ## for report()/tests
var _hits := 0
var _dropped := 0


## Idempotent. _ready() drives it in the running game; a headless SceneTree
## test drives it by hand (a node added inside SceneTree._init() gets no
## _ready() before the first frame).
func boot() -> void:
	if _booted:
		return
	_booted = true
	_instance = self
	if not is_in_group("wood_audio"):
		add_to_group("wood_audio")
	_load_manifest()
	for _i in range(VOICES):
		_voices.append(_make_voice(26.0, 4.0))
	for _i in range(BIG_VOICES):
		_big.append(_make_voice(110.0, 9.0))


func _ready() -> void:
	boot()


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _make_voice(max_d: float, unit: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.max_distance = max_d
	p.unit_size = unit
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.bus = "Master"
	add_child(p)
	return p


static func get_bus(from: Node) -> WoodAudio:
	if _instance != null and is_instance_valid(_instance):
		return _instance
	if from != null and from.is_inside_tree():
		var n := from.get_tree().get_first_node_in_group("wood_audio")
		if n is WoodAudio:
			_instance = n as WoodAudio
			_instance.boot()
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
			push_warning("WoodAudio: no timber pack at %s -- run tools/woodsounds.py" % DIR)
		_streams[key] = null
		return null
	var s := load(path) as AudioStream
	if s is AudioStreamWAV:
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
	_streams[key] = s
	return s


## ============================== The wood ===================================


## The radius of whatever was struck, metres, so the pitch can follow it.
## Every choppable thing answers one of these; anything else is a mid trunk.
static func radius_of(wood: Node) -> float:
	if wood == null or not is_instance_valid(wood):
		return 0.3
	if wood.has_method("trunk_radius"):
		return maxf(float(wood.call("trunk_radius")), 0.03)
	if "trunk_r" in wood:
		return maxf(float(wood.get("trunk_r")), 0.03)
	if "radius" in wood:
		return maxf(float(wood.get("radius")), 0.03)
	return 0.3


static func pitch_for(radius: float) -> float:
	var t := clampf((radius - R_THIN) / (R_FAT - R_THIN), 0.0, 1.0)
	return lerpf(PITCH_THIN, PITCH_FAT, t)


## Which sample family a tool name lands on.
static func key_for(tool: String) -> String:
	return String(TOOL_KEY.get(tool, "axe"))


## =============================== Strikes ===================================


## Iron on wood. `tool` is the Player's current_weapon ("axe", "sword",
## "pickaxe") or "arrow"; `power` is the same 0..1 the chip burst uses.
static func strike(from: Node, at: Vector3, tool: String, power := 1.0,
		wood: Node = null) -> void:
	var bus := get_bus(from)
	if bus == null:
		return
	bus._strike(at, tool, power, wood)


func _strike(at: Vector3, tool: String, power: float, wood: Node) -> void:
	var fam := key_for(tool)
	var n: int = int(STRIKE_VARIANTS.get(fam, 3))
	var key := "%s_%d" % [fam, randi_range(1, n)]
	_last_key = key
	_hits += 1
	var db: float = float(STRIKE_DB.get(fam, -4.0)) + lerpf(-6.0, 0.0, clampf(power, 0.0, 1.0))
	var pitch := pitch_for(radius_of(wood)) * randf_range(0.96, 1.04)
	## a downed trunk is bucked lying on the ground: the whole log rings, lower
	if wood != null and is_instance_valid(wood) and wood.is_in_group("fallen_trunks"):
		pitch *= 0.92
	if not _shot_in(_voices, key, at, db, pitch):
		_dropped += 1


## =============================== Felling ===================================


## The hinge letting go. Played the moment the trunk starts over; the groan
## runs two seconds and ends on the snap, which is about how long a tree takes
## to reach the ground.
static func creak(from: Node, at: Vector3, length := 8.0) -> void:
	var bus := get_bus(from)
	if bus == null:
		return
	## a big tree groans lower and longer
	var pitch := clampf(1.15 - length * 0.02, 0.72, 1.15) * randf_range(0.97, 1.03)
	bus._last_key = "creak"
	bus._shot_in(bus._big, "creak_%d" % randi_range(1, 2), at, CREAK_DB, pitch)


## The crown meeting the ground. `mass` is trunk_len * trunk_r: a sapling
## flops, an ancient oak is felt through the floor.
static func crash(from: Node, at: Vector3, mass := 2.0) -> void:
	var bus := get_bus(from)
	if bus == null:
		return
	var big := clampf(mass / 6.0, 0.0, 1.0)
	var pitch := lerpf(1.18, 0.82, big) * randf_range(0.97, 1.03)
	var db := CRASH_DB + lerpf(-9.0, 0.0, big)
	bus._last_key = "crash"
	bus._shot_in(bus._big, "crash_%d" % randi_range(1, 2), at, db, pitch)


## A bucked log rolling onto the dirt.
static func thud(from: Node, at: Vector3, radius := 0.3) -> void:
	var bus := get_bus(from)
	if bus == null:
		return
	bus._last_key = "thud"
	bus._shot_in(bus._voices, "thud_%d" % randi_range(1, 2), at,
		THUD_DB + clampf(radius * 6.0, 0.0, 4.0), pitch_for(radius) * randf_range(0.95, 1.05))


## One limb coming off the trunk.
static func limb(from: Node, at: Vector3) -> void:
	var bus := get_bus(from)
	if bus == null:
		return
	bus._last_key = "limb"
	bus._shot_in(bus._voices, "limb_%d" % randi_range(1, 2), at, LIMB_DB,
		randf_range(0.92, 1.10))


## ================================= Voices ==================================


func _shot_in(pool: Array[AudioStreamPlayer3D], key: String, at: Vector3,
		db: float, pitch: float) -> bool:
	var s := _stream(key)
	if s == null or not is_inside_tree():
		return false
	for p in pool:
		if not p.playing:
			p.stream = s
			p.global_position = at
			p.volume_db = db
			p.pitch_scale = pitch
			p.play()
			return true
	return false                     ## all voices busy: drop it, never queue


func report() -> Dictionary:
	return {"sounds": manifest.size(), "last": _last_key, "hits": _hits,
		"dropped": _dropped,
		"busy": _voices.filter(func(p): return p.playing).size()}
