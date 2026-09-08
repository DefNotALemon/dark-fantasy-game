extends SceneTree
## ===========================================================================
## StepAudioTests.gd -- footsteps and foley (scripts/StepAudio.gd)
##
##   godot --headless --path . --script res://tests/StepAudioTests.gd
##
## Runs without a renderer or a sound card: the dummy audio driver still
## accepts streams and reports `playing`, and every surface decision is
## arithmetic over the same ground-paint images the shader reads. Writes only
## into user://step_test/.
## ===========================================================================

var _pass := 0
var _fail := 0
const MIN_ASSERTIONS := 55


func ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: %s" % what)


func eq(a, b, what: String) -> void:
	ok(a == b, "%s  (got %s, want %s)" % [what, str(a), str(b)])


func _init() -> void:
	print("StepAudioTests")

	## --- the pack ----------------------------------------------------------
	var mf := "res://assets/audio/footsteps/manifest.json"
	ok(FileAccess.file_exists(mf), "footstep manifest exists (run tools/stepsounds.py)")

	var sa := StepAudio.new()
	root.add_child(sa)
	## A node added to `root` from SceneTree._init() gets no _ready() before
	## the first frame, and this suite quits inside _init(). boot() is
	## idempotent for exactly this.
	sa.boot()
	ok(sa.manifest.size() > 0, "manifest parsed")
	ok(sa.is_in_group("step_audio"), "the bus registers its group")
	sa.boot()
	eq(sa._voices.size(), StepAudio.VOICES, "boot() is idempotent")
	eq(StepAudio.FAMILIES.size(), 9, "nine surface families")
	eq(StepAudio.COL_FAMILY.size(), GroundPaint.GROUNDS.size(),
		"one family per ground column")
	var all_known := true
	for f in StepAudio.COL_FAMILY:
		if not StepAudio.FAMILIES.has(f):
			all_known = false
	ok(all_known, "every column maps to a real family")
	ok(StepAudio.FAMILIES.has(StepAudio.FALLBACK), "fallback is a real family")
	ok(StepAudio.FAMILIES.has(StepAudio.WATER_FAMILY), "water family is real")
	## every family has its three variants and its landing
	var complete := true
	for f in StepAudio.FAMILIES:
		for i in range(StepAudio.VARIANTS):
			if not sa.has_sound("%s_%d" % [f, i + 1]):
				complete = false
				print("    missing %s_%d" % [f, i + 1])
		if not sa.has_sound("%s_land" % f):
			complete = false
			print("    missing %s_land" % f)
	ok(complete, "every family has %d steps + a landing" % StepAudio.VARIANTS)
	for k in ["cloth_1", "cloth_2", "cloth_3", "mail_1", "mail_2"]:
		ok(sa.has_sound(k), "foley %s present" % k)
	## streams really load and are one-shots, not loops
	var s := sa._stream("grass_1")
	ok(s is AudioStreamWAV, "grass_1 loads as a WAV")
	if s is AudioStreamWAV:
		eq((s as AudioStreamWAV).loop_mode, AudioStreamWAV.LOOP_DISABLED,
			"a footstep never loops")
	ok(sa._stream("no_such_family_9") == null, "a missing sound is null, not a crash")

	## --- the surface, on a real ground-paint grid --------------------------
	DirAccess.make_dir_recursive_absolute("user://step_test")
	for f in ["ground_paint.dat", "ground.json"]:
		if FileAccess.file_exists("user://step_test/" + f):
			DirAccess.remove_absolute("user://step_test/" + f)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain_psx.gdshader") as Shader
	var gp := GroundPaint.new()
	gp._dir = "user://step_test/"
	root.add_child(gp)
	var setup_ok: bool = gp.setup(mat, Vector2(-80.0, -60.0), Vector2i(40, 30), 4.0)
	ok(setup_ok, "ground paint sets up on the test grid")
	GroundPaint.inst = gp          ## _ready() has not fired yet -- see above
	ok(GroundPaint.inst == gp, "GroundPaint.inst points at it")
	## The shipped 1800x2700 base does not fit this 40x30 test grid, so the
	## base map is blank here: an UNPAINTED cell has no ground class at all,
	## which is the same shape as standing on water.
	gp.clear_all()
	eq(StepAudio.family_at(0.0, 0.0), StepAudio.WATER_FAMILY,
		"a cell with no ground class reads as the water family")

	## paint one disc per ground column and hear it back
	var heard_all := true
	for col in range(GroundPaint.GROUNDS.size()):
		var id := GroundPaint.tile_id(gp.style_row if gp.style_row >= 0 else 6, col)
		gp.paint_disc(Vector3(0.0, 0.0, 0.0), 6.0, id)
		var got := StepAudio.family_at(0.0, 0.0)
		if got != StepAudio.COL_FAMILY[col]:
			heard_all = false
			print("    column %d (%s) -> %s, want %s"
				% [col, GroundPaint.GROUNDS[col][1], got, StepAudio.COL_FAMILY[col]])
	ok(heard_all, "every painted ground column resolves to its family")
	gp.paint_disc(Vector3.ZERO, 6.0, GroundPaint.tile_id(6, 5))
	eq(StepAudio.family_at(0.0, 0.0), "leaf", "forest floor is leaf litter")
	gp.paint_disc(Vector3.ZERO, 6.0, GroundPaint.tile_id(6, 7))
	eq(StepAudio.family_at(0.0, 0.0), "gravel", "gravel is gravel")
	## off the grid falls back rather than reading garbage
	eq(StepAudio.family_at(9.0e5, 9.0e5), StepAudio.FALLBACK, "off-grid falls back")

	## rain turns soil, and only soil, into mud
	gp.paint_disc(Vector3.ZERO, 6.0, GroundPaint.tile_id(6, 0))    ## meadow
	eq(StepAudio.family_at(0.0, 0.0, 0.0), "grass", "dry meadow is grass")
	eq(StepAudio.family_at(0.0, 0.0, 1.0), "mud", "soaked meadow squelches")
	eq(StepAudio.family_at(0.0, 0.0, StepAudio.WET_SWAP - 0.01), "grass",
		"just under the threshold stays grass")
	gp.paint_disc(Vector3.ZERO, 6.0, GroundPaint.tile_id(6, 7))    ## gravel
	eq(StepAudio.family_at(0.0, 0.0, 1.0), "gravel", "rain does not soften gravel")
	gp.paint_disc(Vector3.ZERO, 6.0, GroundPaint.tile_id(6, 8))    ## sand
	eq(StepAudio.family_at(0.0, 0.0, 1.0), "sand", "wet sand is still sand")

	## --- footfalls ---------------------------------------------------------
	gp.paint_disc(Vector3.ZERO, 6.0, GroundPaint.tile_id(6, 0))
	var before: int = sa._steps
	StepAudio.footfall(sa, Vector3.ZERO, 1.0)
	eq(sa._steps, before + 1, "a footfall is counted")
	eq(sa._last_family, "grass", "and it read the ground under it")
	StepAudio.footfall(sa, Vector3.ZERO, 0.5, false, false, "wood")
	eq(sa._last_family, "wood", "an explicit surface overrides the ground")
	ok(sa.report().has("dropped"), "report carries the drop count")

	## The pool is finite and a footfall it cannot voice is DROPPED, never
	## queued. (Headless, nothing under `root` is "inside the scene tree"
	## during _init, so every shot takes the drop path -- which is exactly
	## the branch worth proving does not error.)
	for i in range(StepAudio.VOICES * 3):
		StepAudio.footfall(sa, Vector3.ZERO, 1.0)
	var busy: int = sa.report()["busy"]
	ok(busy <= StepAudio.VOICES, "never more voices than the pool (%d)" % busy)
	ok(sa._dropped > 0, "unvoiceable footfalls are dropped, not queued")
	eq(sa._voices.size(), StepAudio.VOICES, "the step pool is a fixed size")
	eq(sa._foley.size(), 2, "foley has its own pool so it cannot steal a step")
	var empty: Array[AudioStreamPlayer3D] = []
	ok(not sa._shot_in(empty, "grass_1", Vector3.ZERO, -6.0, 1.0),
		"an exhausted pool returns false rather than allocating")

	## --- the constants are ordered the way the design says -----------------
	ok(StepAudio.VOL_QUIET < StepAudio.VOL_LOUD, "a sprint is louder than a creep")
	ok(StepAudio.CROUCH_DB < 0.0, "crouching costs volume")
	ok(StepAudio.PRONE_DB < StepAudio.CROUCH_DB, "prone costs more than crouch")
	ok(StepAudio.WET_PITCH < 1.0, "wet ground sits lower")
	ok(StepAudio.WET_SWAP > 0.5 and StepAudio.WET_SWAP < 1.0, "the swap is a downpour, not a drizzle")
	ok(StepAudio.FOLEY_DB < StepAudio.VOL_LOUD, "gear stays under the foot")
	## every terrain family except the two prop surfaces is reachable
	var reach := true
	for f in StepAudio.FAMILIES:
		if f == "wood" or f == "stone":
			continue
		if not StepAudio.COL_FAMILY.has(f):
			reach = false
			print("    no ground column ever sounds like %s" % f)
	ok(reach, "every terrain family is reachable from some ground column")

	## --- one cell is 4 m wide, and the sound respects that -----------------
	gp.paint_disc(Vector3.ZERO, 1.0, GroundPaint.tile_id(6, 8))       ## sand
	eq(StepAudio.family_at(0.0, 0.0), "sand", "the cell under the foot")
	eq(StepAudio.family_at(1.5, 1.5), "sand", "still the same 4 m cell")
	gp.paint_disc(Vector3(12.0, 0.0, 0.0), 1.0, GroundPaint.tile_id(6, 7))
	eq(StepAudio.family_at(12.0, 0.0), "gravel", "three cells over is its own ground")
	eq(StepAudio.family_at(0.0, 0.0), "sand", "and painting there did not move this one")

	## quiet feet: crouching and prone attenuate, and prone is the quietest
	var loud := sa._db_for(1.0, false, false)
	var creep := sa._db_for(1.0, true, false)
	var flat := sa._db_for(1.0, false, true)
	ok(creep < loud, "crouching is quieter than walking")
	ok(flat < creep, "prone is quieter than crouching")
	ok(sa._db_for(0.0, false, false) < sa._db_for(1.0, false, false),
		"a sprint carries further than a crawl of a walk")

	## --- landings ----------------------------------------------------------
	gp.paint_disc(Vector3.ZERO, 6.0, GroundPaint.tile_id(6, 0))
	sa._last_family = ""
	StepAudio.landing(sa, Vector3.ZERO, StepAudio.LAND_MIN_SPEED - 0.1)
	eq(sa._last_family, "", "stepping off a kerb is not a landing")
	StepAudio.landing(sa, Vector3.ZERO, 9.0)
	eq(sa._last_family, "grass", "a real landing reads the ground")
	ok(sa._land_db(9.0) > sa._land_db(3.0), "a harder landing is louder")
	ok(absf(sa._land_db(400.0) - sa._land_db(40.0)) < 0.001,
		"and past the ceiling it stops getting louder")
	ok(sa._land_db(StepAudio.LAND_MIN_SPEED) <= StepAudio.LAND_DB,
		"the softest landing is not the loudest sound in the game")

	## --- what the report says ----------------------------------------------
	var rep := sa.report()
	for k in ["sounds", "families", "last", "steps", "dropped", "wetness",
			"mailed", "busy"]:
		ok(rep.has(k), "report carries %s" % k)
	eq(rep["families"], StepAudio.FAMILIES.size(), "report counts the families")
	ok(int(rep["steps"]) > 0, "report counts the steps taken")

	## --- a missing pack degrades to silence, never to an error -------------
	ok(not sa._shot("no_such_family_9", Vector3.ZERO, -6.0, 1.0),
		"a sound that is not in the pack is dropped, not played")
	sa._last_family = ""
	StepAudio.footfall(sa, Vector3.ZERO, 1.0, false, false, "no_such_family_9")
	eq(sa._last_family, "no_such_family_9",
		"an unknown surface is recorded but makes no sound")

	_finish()


func _finish() -> void:
	print("StepAudioTests: %d passed, %d failed" % [_pass, _fail])
	if _pass + _fail < MIN_ASSERTIONS:
		print("  LOST A SECTION: only %d assertions ran (floor %d)" % [_pass + _fail, MIN_ASSERTIONS])
		_fail += 1
	quit(1 if _fail > 0 else 0)
