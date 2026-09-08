class_name StepAudio
extends Node

## ===========================================================================
## THE GROUND UNDER YOUR FEET — footsteps, landings and gear foley, chosen by
## the ground-paint material the shader is actually drawing at your position.
##
## Same shape as WaterAudio / CritterAudio: a generated WAV pack behind a
## manifest (tools/stepsounds.py, no recordings), lazy-loaded, degrading to
## silence when the pack is missing. What is different:
##
##   * THE BEAT COMES FROM THE GAIT, NOT A TIMER. Player._update_gait already
##     dips the camera at every |sin(gait_phase)| peak -- two per stride, one
##     per foot. The sound lands on that same beat, so what you hear is
##     exactly what you see, at any speed, with no second clock to drift.
##   * THE SURFACE COMES FROM THE PAINT. GroundPaint.worn_id_at() is what the
##     terrain shader itself reads, so a dirt path the player painted in god
##     mode sounds like packed dirt the moment it is painted -- no extra map,
##     no bake, no raycast. Cell resolution is the bake's 4 m.
##   * NOTHING IS ALLOCATED PER STEP. A fixed pool of AudioStreamPlayer3D; a
##     footfall with no free voice is dropped, never queued.
##
## Wired by World.gd next to WaterAudio: add_child(StepAudio.new()).
## Player fires it from _update_gait -- StepAudio does the material resolve
## itself, so the Player-side diff stays at a dozen lines.
## ===========================================================================

const DIR := "res://assets/audio/footsteps/"
const MANIFEST := DIR + "manifest.json"
const VOICES := 8
const VARIANTS := 3
const FAMILIES := ["grass", "dirt", "mud", "leaf", "gravel", "sand", "snow",
	"wood", "stone"]

## GroundPaint.GROUNDS column (0..10) -> which family that ground sounds like.
## Index order is GroundPaint.GROUNDS, so a new ground column needs one entry
## here and nothing else.
const COL_FAMILY := [
	"grass",   ##  0 lush_meadow
	"grass",   ##  1 dry_grass / Shelf
	"dirt",    ##  2 patchy grass-dirt
	"dirt",    ##  3 packed dirt
	"mud",     ##  4 mud / wet track
	"leaf",    ##  5 forest floor
	"dirt",    ##  6 barrens / heath
	"gravel",  ##  7 gravel / scree
	"sand",    ##  8 sand / beach
	"mud",     ##  9 moss / bog
	"snow",    ## 10 snow-dusted grass
]
const FALLBACK := "dirt"          ## no GroundPaint yet, or off the grid
const WATER_FAMILY := "mud"       ## the shallows at the edge of the lake

## Volume, in dB, by how deep into the stride we are. A creep is nearly
## silent; a sprint carries. `gait_amount` is already eased 0..1 by the
## Player, so this curve inherits the same start/stop melt.
const VOL_QUIET := -26.0          ## gait_amount ~ 0
const VOL_LOUD := -6.0            ## gait_amount ~ 1 (sprint)
const CROUCH_DB := -9.0
const PRONE_DB := -15.0
const LAND_DB := 0.0
const LAND_MIN_SPEED := 2.0        ## m/s below which a touchdown is silent
const WET_SWAP := 0.85            ## wetness at or above this: grass/dirt -> mud
const WET_PITCH := 0.96
const WET_DB := -1.5
const FOLEY_DB := -13.0           ## cloth under the step
const MAIL_DB := -11.0
const FOLEY_MIN_GAIT := 0.45      ## gear only talks once you are really moving

static var _instance: StepAudio = null

var manifest: Dictionary = {}
var wetness := 0.0                ## 0..1, fed by World/Weather; 1 = soaked ground
var mailed := false               ## wearing metal armour -> mail_* rides the step
var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer3D] = []
var _foley: Array[AudioStreamPlayer3D] = []
var _missing_warned := false
var _last_family := ""
var _steps := 0                   ## lifetime footfalls, for report()/tests
var _dropped := 0                 ## footfalls with no free voice
var _booted := false


## Idempotent. _ready() drives it in the running game; a headless SceneTree
## test drives it by hand, because a node added to `root` inside SceneTree
## ._init() does NOT get _ready() before the first frame -- and a test that
## quits inside _init() never sees one.
func boot() -> void:
	if _booted:
		return
	_booted = true
	_instance = self
	if not is_in_group("step_audio"):
		add_to_group("step_audio")
	_load_manifest()
	for _i in range(VOICES):
		_voices.append(_make_voice(14.0, 3.0))
	for _i in range(2):
		_foley.append(_make_voice(9.0, 2.0))


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


static func get_bus(from: Node) -> StepAudio:
	if _instance != null and is_instance_valid(_instance):
		return _instance
	if from != null and from.is_inside_tree():
		var n := from.get_tree().get_first_node_in_group("step_audio")
		if n is StepAudio:
			_instance = n as StepAudio
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
			push_warning("StepAudio: no footstep pack at %s -- run tools/stepsounds.py" % DIR)
		_streams[key] = null
		return null
	var s := load(path) as AudioStream
	if s is AudioStreamWAV:
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
	_streams[key] = s
	return s


## ============================== The surface ===============================


## What the ground at (wx, wz) sounds like. Reads the SAME map the terrain
## shader reads, so paint and sound can never disagree.
static func family_at(wx: float, wz: float, wet := 0.0) -> String:
	var fam := FALLBACK
	var gp := GroundPaint.inst
	if gp != null and gp.ready_ok and gp.in_grid(gp.cell_of(wx, wz)):
		var col := -1
		var id := gp.worn_id_at(wx, wz)
		if id > 0:
			col = GroundPaint.col_of(id)
		else:
			## style row is off (tint-only), or we are over water
			var b := gp.base_col_at(wx, wz)
			col = b - 1                      ## b == 0 -> -1, i.e. water
			if col < 0:
				return WATER_FAMILY
		if col >= 0 and col < COL_FAMILY.size():
			fam = COL_FAMILY[col]
	## Rain does not make gravel squelch, but it does make soil do it.
	if wet >= WET_SWAP and (fam == "grass" or fam == "dirt"):
		fam = "mud"
	return fam


## ================================ Footfall =================================


## One foot down. `hard` is the Player's eased gait_amount (0..1).
## `surface` overrides the terrain lookup -- pass "wood" off a built piece or
## a fallen trunk, "stone" on a cave floor; "" means ask the ground paint.
static func footfall(from: Node, at: Vector3, hard: float,
		crouched := false, is_prone := false, surface := "") -> void:
	var bus := get_bus(from)
	if bus == null:
		return
	bus._footfall(at, hard, crouched, is_prone, surface)


func _footfall(at: Vector3, hard: float, crouched: bool, is_prone: bool,
		surface: String) -> void:
	var h := clampf(hard, 0.0, 1.0)
	var fam := surface if surface != "" else family_at(at.x, at.z, wetness)
	_last_family = fam
	_steps += 1
	var db := _db_for(h, crouched, is_prone)
	## Left foot / right foot: alternate a touch of pitch so a run does not
	## machine-gun one identical sample.
	var side := 1.0 + (0.03 if (_steps & 1) == 0 else -0.03)
	var pitch := side * randf_range(0.97, 1.03)
	if wetness >= WET_SWAP:
		pitch *= WET_PITCH
	if not _shot("%s_%d" % [fam, randi_range(1, VARIANTS)], at, db, pitch):
		_dropped += 1
		return
	## Gear rides the same beat, quieter and a hair late is fine -- it goes
	## out on its own small pool so it can never steal a footstep's voice.
	if h >= FOLEY_MIN_GAIT and not is_prone:
		if mailed:
			_shot_in(_foley, "mail_%d" % randi_range(1, 2), at,
				MAIL_DB + 6.0 * h, randf_range(0.95, 1.06))
		elif randf() < 0.5:
			_shot_in(_foley, "cloth_%d" % randi_range(1, 3), at,
				FOLEY_DB + 6.0 * h, randf_range(0.94, 1.08))


## How loud one foot is: the eased stride, then the stance tax, then the rain.
## Split out so the curve can be asserted without a sound card.
func _db_for(hard: float, crouched: bool, is_prone: bool) -> float:
	var db := lerpf(VOL_QUIET, VOL_LOUD, clampf(hard, 0.0, 1.0))
	if is_prone:
		db += PRONE_DB
	elif crouched:
		db += CROUCH_DB
	if wetness >= WET_SWAP:
		db += WET_DB
	return db


## Touchdown after a fall. `spd` is the Player's _fall_speed at contact.
static func landing(from: Node, at: Vector3, spd: float, surface := "") -> void:
	var bus := get_bus(from)
	if bus == null:
		return
	if spd < LAND_MIN_SPEED:
		return                       ## stepping off a kerb is not a landing
	var fam := surface if surface != "" else family_at(at.x, at.z, bus.wetness)
	bus._last_family = fam
	bus._shot("%s_land" % fam, at, bus._land_db(spd), randf_range(0.94, 1.02))


## A landing gets louder the harder it was, and then stops getting louder --
## a 40 m fall must not be eight times a 5 m one.
func _land_db(spd: float) -> float:
	return LAND_DB - 8.0 + clampf((spd - LAND_MIN_SPEED) * 0.6, 0.0, 8.0)


## ================================= Voices ==================================


func _shot(key: String, at: Vector3, db: float, pitch: float) -> bool:
	return _shot_in(_voices, key, at, db, pitch)


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
	return {"sounds": manifest.size(), "families": FAMILIES.size(),
		"last": _last_family, "steps": _steps, "dropped": _dropped,
		"wetness": wetness, "mailed": mailed,
		"busy": _voices.filter(func(p): return p.playing).size()}
