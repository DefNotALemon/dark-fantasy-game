extends SceneTree
## ===========================================================================
## IncidentTests.gd -- the Incident Director (scripts/IncidentDirector.gd) and
## the Incident Kit (scripts/IncidentKit.gd)
##
##   godot --headless --path . --script res://tests/IncidentTests.gd
##
## Runs without a renderer, a terrain or a sky. Every Director built in here
## is deliberately kept OUT of the SceneTree: a node inside the tree is torn
## down with queue_free(), which needs a frame to drain, and this suite quits
## inside _init() and never runs one -- so "the nodes are gone" would be a
## claim nothing could check. Outside the tree the Director frees its props
## immediately and `is_instance_valid` tells the truth.
##
## The Chronicle underneath is real: real places, real positions, real uids
## drawn from its own counter, so the anchors below land on the actual map.
##
## Every section is its own function. A runtime error inside one aborts that
## function and returns here, so one broken section cannot take the rest of
## the run with it -- the summary still prints and quit(1) still fires.
##
## 2026-09-07: rewritten against the post-critic contract. The record carries
## `resolved_at`; the live->resolved transition emits `incident_redressed`
## rather than a second `incident_staged`; the cohort is preemptive and built
## STAGE_PER_SCAN at a time; `shore` is a fourth staging axis; `critter` is a
## prop kind the Kit does not build; prop specs carry `layout`; the aftermath
## rings `threat_after`; and the save writes vectors as arrays so JSON works.
## Every one of those has a section, and the four bugs the critic found have a
## named regression section each (B1, B3, S1, S4/S5).
## ===========================================================================

var _pass := 0
var _fail := 0
## Claims that must be settled before the run ends. A GDScript runtime error
## aborts the function it happened in and returns straight to `_init`, so an
## assertion written AFTER a call that throws never runs at all -- it does not
## fail, it simply vanishes, and the suite goes quiet about the thing it was
## built to catch. A claim is staked before the dangerous call and settled
## immediately after it; `_finish` turns every unsettled claim into a failure.
## Both outcomes count as exactly one assertion.
var _claims: Array = []
## Nodes a section could not free because it was aborted mid-way. Reaped in
## `_finish` so one throwing source function does not also leak a Chronicle.
var _to_free: Array = []
const MIN_ASSERTIONS := 880

## The seed every section uses unless it says otherwise.
const SEED := 0x494E4344            ## "INCD"
## The record contract. Thirteen keys since `resolved_at` landed: `born` is
## when the event FIRED and `resolved_at` is when it ENDED, and `linger` can
## only honestly be measured from the second one.
const REC_KEYS := ["uid", "kind", "outcome", "place", "pos", "born", "resolved_at",
	"live", "state", "staged_at", "heard", "anchor", "props"]
const STATES := ["known", "staged", "spent"]
const STAGES := ["place", "road", "wild", "shore"]
## The Kit builds every prop kind out of boxes except this one: a critter is a
## live animal, and the Director hands it to the WildlifeDirector instead.
## `IncidentKit.problems()` exempts it from the geometry sweep; so does this
## suite, in exactly the same place and for exactly the same reason.
const NOT_BUILT := "critter"
## Args whose geometry is legitimately identical to the no-arg default,
## because they name the colour the default already uses. Anything else that
## builds identically to its default is a `track: "wolf"` waiting to happen --
## an arg with no builder branch, silently staging the wrong animal.
const ARG_SYNONYMS := ["cloth/sack", "feather/crow"]
## A steady-state scan over ~64 records with nothing to build measures ~0.3 ms
## headless. Ten times that is still inside a frame and is far below what any
## per-record allocation regression would cost.
const SCAN_BUDGET_USEC := 5000.0


## ---------------------------------------------------------------------------
##  harness
## ---------------------------------------------------------------------------


func ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: %s" % what)


func eq(a, b, what: String) -> void:
	ok(a == b, "%s  (got %s, want %s)" % [what, str(a), str(b)])


func near(a: float, b: float, tol: float, what: String) -> void:
	ok(absf(a - b) <= tol, "%s  (got %s, want %s +/- %s)" % [what, str(a), str(b), str(tol)])


func claim(what: String) -> void:
	_claims.append(what)


func settle(what: String) -> void:
	if _claims.has(what):
		_claims.erase(what)
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: settled a claim nobody staked: %s" % what)


func _init() -> void:
	print("IncidentTests")

	_test_catalogue()
	_test_lookups()
	_test_props()
	_test_anchors()
	_test_shore()
	_test_layout()
	_test_critters()
	_test_determinism()
	_test_idempotency()
	_test_live_to_resolved()
	_test_ageing()
	_test_redress_budget()
	_test_scope_gate()
	_test_long_event()
	_test_cap()
	_test_earshot()
	_test_threat_after()
	_test_hysteresis()
	_test_save_round_trip()
	_test_roster_drift()
	_test_clock_binding()
	_test_null_safety()
	_test_harvest_reach()
	_test_cost()
	_test_critter_cull()

	_finish()


## ---------------------------------------------------------------------------
##  helpers
## ---------------------------------------------------------------------------

## A booted Chronicle under `root`. Nothing added to `root` from
## SceneTree._init() ever gets _ready(), so boot() is called by hand -- the
## same explicit setup ChronicleTests uses.
func _chron(seed_: int = SEED) -> Chronicle:
	var c := Chronicle.new()
	c.world_seed = seed_
	root.add_child(c)
	c.boot()
	return c


## A Director that is NOT in the tree, on purpose. See the file header.
func _dir(c: Chronicle, p: Node3D, seed_: int = SEED) -> IncidentDirector:
	var d := IncidentDirector.new()
	d.chronicle = c
	d.player = p
	d.world_seed = seed_
	return d


func _body() -> Node3D:
	return Node3D.new()


func _put(p: Node3D, at: Vector2) -> void:
	p.position = Vector3(at.x, 0.0, at.y)


## An event in the Chronicle's own shape, carrying a uid drawn from the
## Chronicle's own counter -- unique, never reused, exactly as `_fire` would
## have handed it out. `ends` is the Chronicle's resolve time and is what the
## Director now stamps `resolved_at` from, so it is a real field here and not
## decoration.
func _ev(c: Chronicle, kind: String, pl: Dictionary, born: float, outcome := "",
		life := 0.1) -> Dictionary:
	var uid: int = c._uid
	c._uid = uid + 1
	return {
		"uid": uid,
		"kind": kind,
		"place": String(pl.get("name", "")),
		"pos": pl.get("pos", Vector2.ZERO) as Vector2,
		"born": born,
		"ends": born + life,
		"state": "resolved" if not outcome.is_empty() else "active",
		"outcome": outcome,
		"line": "",
	}


## Move an event from the Chronicle's active list into its resolved ring, the
## same way `Chronicle._resolve` does it: the SAME dictionary, mutated.
func _resolve(c: Chronicle, ev: Dictionary, outcome := "") -> void:
	c.active.erase(ev)
	ev["state"] = "resolved"
	ev["outcome"] = outcome if not outcome.is_empty() else _first_outcome(String(ev["kind"]))
	c.resolved.append(ev)


## How many critters a scene ASKS FOR. Since 2026-09-07 `props` counts the
## request, not the delivery -- see `_test_critters`.
func _critters_wanted(kind_id: String, outcome_id: String, live: bool) -> int:
	var n := 0
	for raw in IncidentKit.props_for(kind_id, outcome_id, live):
		var spec := raw as Dictionary
		if String(spec.get("kind", "")) == NOT_BUILT:
			n += maxi(int(spec.get("n", 1)), 1)
	return n


func _first_outcome(kind_id: String) -> String:
	var kd := ChronicleEvents.by_id(kind_id)
	var outs := kd.get("outcomes", []) as Array
	return String((outs[0] as Dictionary).get("id", "")) if not outs.is_empty() else ""


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _mesh_count(n: Node) -> int:
	var k := 0
	for ch in n.get_children():
		if ch is MeshInstance3D:
			k += 1
		k += _mesh_count(ch)
	return k


func _null_meshes(n: Node) -> int:
	var k := 0
	for ch in n.get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh == null:
			k += 1
		k += _null_meshes(ch)
	return k


## Everything about a built prop that a restage has to reproduce: the shape of
## the tree, every transform in it, and which mesh and colour sit on which
## node.
func _walk(n: Node, out: PackedStringArray, depth: int) -> void:
	## Position in the tree, never the node NAME: Godot hands an unnamed node a
	## fresh instance id every time, so a digest that included the name would
	## call two identical props different and pass a purity test that means
	## nothing.
	var idx := 0
	for ch in n.get_children():
		var line := "%d.%d/%s" % [depth, idx, ch.get_class()]
		if ch is Node3D:
			line += "|%s" % str((ch as Node3D).transform)
		if ch is MeshInstance3D:
			var mi := ch as MeshInstance3D
			line += "|%s" % (mi.mesh.get_class() if mi.mesh != null else "NOMESH")
			var mat := mi.material_override as StandardMaterial3D
			line += "|%s" % (str(mat.albedo_color) if mat != null else "NOMAT")
		out.append(line)
		_walk(ch, out, depth + 1)
		idx += 1


func _digest_node(n: Node) -> String:
	var out := PackedStringArray()
	_walk(n, out, 0)
	return "\n".join(out)


func _prop_digest(spec: Dictionary, index: int, unit: float) -> String:
	var n := IncidentKit.build_prop(spec, index, unit)
	if n == null:
		return "<null>"
	var s := _digest_node(n)
	n.free()
	return s


func _uids_of(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		out.append(int(String(r).split("|")[0]))
	return out


## The direct children of a staged incident's root whose prop kind is `kind`,
## in build order.
func _props_of(root: Node, kind: String) -> Array:
	var out: Array = []
	for ch in root.get_children():
		if String(ch.name).begins_with("Prop_%s_" % kind):
			out.append(ch)
	return out


## Scan once and report how many incidents were built by that one scan.
func _scan_counting(d: IncidentDirector, day: float) -> int:
	var n := [0]
	var cb := func(_r): n[0] += 1
	d.incident_staged.connect(cb)
	d.scan(day)
	d.incident_staged.disconnect(cb)
	return n[0]


## Scan once and report how many incidents were RE-DRESSED by that one scan.
func _scan_redressing(d: IncidentDirector, day: float) -> int:
	var n := [0]
	var cb := func(_r): n[0] += 1
	d.incident_redressed.connect(cb)
	d.scan(day)
	d.incident_redressed.disconnect(cb)
	return n[0]


## Every scan's build count, and the check both budgets have to satisfy: no
## scan may exceed STAGE_PER_SCAN plus the earshot grace, ever, for any reason.
func _check_budget(per_scan: Array, where: String) -> int:
	var over_hard := 0
	var over_soft := 0
	for n in per_scan:
		if int(n) > IncidentDirector.STAGE_PER_SCAN + IncidentDirector.EARSHOT_GRACE:
			over_hard += 1
		if int(n) > IncidentDirector.STAGE_PER_SCAN:
			over_soft += 1
	eq(over_hard, 0, "%s: no scan exceeded STAGE_PER_SCAN + EARSHOT_GRACE (%s)" % [where, str(per_scan)])
	return over_soft


## ---------------------------------------------------------------------------
##  1. the catalogue audits itself
## ---------------------------------------------------------------------------


func _test_catalogue() -> void:
	claim("_test_catalogue ran to the end")
	var probs := IncidentKit.problems()
	for p in probs:
		print("    catalogue: %s" % String(p))
	eq(probs.size(), 0, "the catalogue reports no problems")

	var kinds := ChronicleEvents.ids()
	eq(kinds.size(), 34, "the Chronicle has thirty-four kinds")
	eq(IncidentKit.RECIPES.size(), 34, "the Kit has thirty-four recipes")

	## Every single kind, named, so a missing one says WHICH.
	for kid in kinds:
		ok(not IncidentKit.recipe_for(String(kid)).is_empty(), "kind '%s' has a recipe" % String(kid))

	var ids := IncidentKit.ids()
	eq(ids.size(), 34, "ids() lists every recipe")
	var sorted_copy := PackedStringArray(Array(ids))
	sorted_copy.sort()
	eq(Array(ids), Array(sorted_copy), "ids() comes back sorted")
	var seen := {}
	var dupes := 0
	for i in ids:
		if seen.has(String(i)):
			dupes += 1
		seen[String(i)] = true
	eq(dupes, 0, "ids() holds no duplicate")
	var kinds_sorted := PackedStringArray(Array(kinds))
	kinds_sorted.sort()
	eq(Array(ids), Array(kinds_sorted), "ids() is exactly the Chronicle's kind list")

	## Now the body of every recipe, counted rather than named: the audit above
	## already names the broken one.
	var bad_stage := 0
	var bad_scope := 0
	var bad_threat := 0
	var bad_after_threat := 0
	var bad_linger := 0
	var bad_note := 0
	var bad_length := 0
	var no_place := 0
	var bad_hear := 0
	var no_live := 0
	var bad_after_key := 0
	var missing_after := 0
	var bad_prop_kind := 0
	var bad_arg := 0
	var bad_layout := 0
	var bad_key := 0
	var bad_n := 0
	var over_cap := 0
	var after_keys := 0
	var real_outcomes := 0
	var silent := 0
	var explicit_after := 0
	var scoped := {"place": 0, "road": 0, "wild": 0, "shore": 0}
	var used_props := {}
	for r in IncidentKit.RECIPES:
		var rec := r as Dictionary
		var id := String(rec.get("id", ""))
		var kd := ChronicleEvents.by_id(id)
		var scope := String(kd.get("scope", ""))
		var stage := String(rec.get("stage", ""))
		if not STAGES.has(stage):
			bad_stage += 1
		else:
			scoped[stage] = int(scoped[stage]) + 1
		## `shore` is a REFINEMENT of `place`, not a fourth Chronicle scope --
		## the Chronicle has no idea where the water is. So it must sit on a
		## place kind, and every other stage must equal the catalogue's scope.
		if stage == "shore":
			if scope != "place":
				bad_scope += 1
		elif stage != scope:
			bad_scope += 1
		var threat := int(rec.get("threat", -99))
		if threat < -1 or threat > 3:
			bad_threat += 1
		if threat == -1:
			silent += 1
		if rec.has("threat_after"):
			explicit_after += 1
			var ta := int(rec.get("threat_after", -99))
			if ta < -1 or ta > 3:
				bad_after_threat += 1
		var linger := float(rec.get("linger", -1.0))
		if linger < 0.0 or not is_finite(linger):
			bad_linger += 1
		var note := String(rec.get("note", ""))
		if note.is_empty() or note.count("%s") > 1 or note.contains("!") or not note.ends_with("."):
			bad_note += 1
		## The prose bar itself, which nothing else checks: a line read in a dark
		## wood at two in the morning is a sentence, not a label and not a
		## paragraph, and it names the place it is about.
		if note.length() < 30 or note.length() > 160:
			bad_length += 1
		if note.count("%s") != 1:
			no_place += 1
		if String(rec.get("hear", "")).is_empty():
			bad_hear += 1
		var live := rec.get("live", []) as Array
		if live.is_empty():
			no_live += 1
		var outs := kd.get("outcomes", []) as Array
		var real := {}
		for o in outs:
			real[String((o as Dictionary).get("id", ""))] = true
		real_outcomes += real.size()
		var after := rec.get("after", {}) as Dictionary
		after_keys += after.size()
		for key in after.keys():
			if not real.has(String(key)):
				bad_after_key += 1
		for oid in real.keys():
			if not after.has(oid):
				missing_after += 1
		## Every scene the Kit can stage, live or aftermath, counted against
		## the Director's own per-incident ceiling.
		var scenes: Array = [live]
		for key in after.keys():
			scenes.append(after[key] as Array)
		for sc in scenes:
			var total := 0
			for raw in (sc as Array):
				var spec := raw as Dictionary
				var pk := String(spec.get("kind", ""))
				used_props[pk] = true
				if not IncidentKit.PROP_KINDS.has(pk):
					bad_prop_kind += 1
				## The arg table, which is the whole point of the 2026-09-07
				## pass: four recipes had been naming args with no builder
				## behind them for a release.
				var arg := String(spec.get("arg", ""))
				if not IncidentKit.PROP_ARGS.has(pk):
					bad_arg += 1
				elif not (IncidentKit.PROP_ARGS[pk] as Array).has(arg):
					bad_arg += 1
				if not ["", "line"].has(String(spec.get("layout", ""))):
					bad_layout += 1
				for key in spec.keys():
					if not ["kind", "n", "spread", "arg", "y", "layout"].has(String(key)):
						bad_key += 1
				if int(spec.get("n", 1)) < 1:
					bad_n += 1
				total += maxi(int(spec.get("n", 1)), 1)
			if total > IncidentDirector.MAX_PROPS:
				over_cap += 1

	eq(bad_stage, 0, "every recipe stages on place|road|wild|shore")
	eq(bad_scope, 0, "every stage agrees with the catalogue scope, shore refining place")
	eq(bad_threat, 0, "every threat sits in -1..3")
	eq(bad_after_threat, 0, "every threat_after that is present sits in -1..3")
	eq(bad_linger, 0, "every linger is finite and >= 0")
	eq(bad_note, 0, "every note is one plain sentence with at most one %s")
	eq(bad_length, 0, "and every one of them is a sentence, not a label or a paragraph")
	eq(no_place, 0, "and every one of them names the place it is about")
	eq(bad_hear, 0, "every recipe names something to hear")
	eq(no_live, 0, "every recipe dresses its live event")
	eq(bad_after_key, 0, "every after key is a real outcome id of that kind")
	eq(missing_after, 0, "every outcome of every kind has an aftermath")
	eq(after_keys, 112, "the Kit dresses all one hundred and twelve outcomes")
	eq(real_outcomes, 112, "the catalogue still has one hundred and twelve outcomes")
	eq(bad_prop_kind, 0, "every prop spec names a kind in PROP_KINDS")
	eq(bad_arg, 0, "every prop spec names an arg the PROP_ARGS table allows")
	eq(bad_layout, 0, "every layout is \"\" or \"line\"")
	eq(bad_key, 0, "no prop spec carries a key the schema does not name")
	eq(bad_n, 0, "every prop spec asks for at least one of the thing")
	eq(over_cap, 0, "no single scene asks for more props than the Director will build")
	eq(used_props.size(), IncidentKit.PROP_KINDS.size(), "every prop kind in the vocabulary is staged by something")
	ok(silent >= 1, "at least one incident is silent (threat -1): %d of them" % silent)
	ok(explicit_after >= 3, "some recipes override the aftermath threat (%d)" % explicit_after)
	ok(int(scoped["shore"]) >= 3, "the shore axis is used (%d recipes)" % int(scoped["shore"]))
	ok(int(scoped["place"]) > 0 and int(scoped["road"]) > 0 and int(scoped["wild"]) > 0,
		"and so are the other three (%s)" % str(scoped))
	eq(int(scoped["place"]) + int(scoped["road"]) + int(scoped["wild"]) + int(scoped["shore"]), 34,
		"every recipe lands on one of the four axes")

	## PROP_ARGS itself: one entry per buildable prop kind, no orphans.
	var arg_gaps := 0
	for pk in IncidentKit.PROP_KINDS:
		if not IncidentKit.PROP_ARGS.has(pk):
			arg_gaps += 1
	eq(arg_gaps, 0, "every prop kind has a PROP_ARGS entry")
	var arg_orphans := 0
	for pk in IncidentKit.PROP_ARGS.keys():
		if not IncidentKit.PROP_KINDS.has(String(pk)):
			arg_orphans += 1
	eq(arg_orphans, 0, "and PROP_ARGS names no prop kind that does not exist")
	## The critter table is the short list this catalogue actually asks the
	## WildlifeDirector for; pinning it is what catches a typo'd species, which
	## `spawn_one` would answer with a silent null.
	eq(Array(IncidentKit.PROP_ARGS.get(NOT_BUILT, [])), ["crow", "deer"],
		"the critter table names exactly the species the recipes ask for")
	settle("_test_catalogue ran to the end")


## ---------------------------------------------------------------------------
##  2. the static lookups
## ---------------------------------------------------------------------------


func _test_lookups() -> void:
	claim("_test_lookups ran to the end")
	eq(IncidentKit.recipe_for("no_such_kind"), {}, "an unknown kind has no recipe")
	eq(IncidentKit.props_for("no_such_kind", "", true), [], "an unknown kind stages nothing")
	eq(IncidentKit.note_for("no_such_kind", "Sebec"), "", "an unknown kind says nothing")
	eq(IncidentKit.hear_for("no_such_kind"), "", "an unknown kind sounds like nothing")
	eq(IncidentKit.threat_for("no_such_kind"), -1, "an unknown kind is silent")
	eq(IncidentKit.threat_after_for("no_such_kind"), -1, "and its aftermath is silent too")
	eq(IncidentKit.linger_for("no_such_kind"), 0.0, "an unknown kind lingers not at all")
	eq(IncidentKit.stage_for("no_such_kind"), "place", "an unknown kind falls back to the place axis")

	## The catalogue is a const; what a caller gets is a copy of it.
	var a := IncidentKit.recipe_for("wolves_at_fold")
	a["note"] = "vandalised"
	(a["live"] as Array).clear()
	var b := IncidentKit.recipe_for("wolves_at_fold")
	ok(String(b.get("note", "")) != "vandalised", "recipe_for hands out a copy, not the catalogue")
	ok(not (b.get("live", []) as Array).is_empty(), "and a deep copy: the nested arrays are safe too")

	eq(IncidentKit.threat_for("murrain"), -1, "a murrain rings nothing")
	eq(IncidentKit.threat_for("fire"), 3, "a fire is a panic")
	eq(IncidentKit.stage_for("caravan_in"), "road", "a caravan is staged on the road")
	eq(IncidentKit.stage_for("wolf_hunt"), "wild", "a wolf hunt is staged in the wild")
	eq(IncidentKit.stage_for("wolves_at_fold"), "place", "a fold is staged at the place")
	eq(IncidentKit.stage_for("wreck_ashore"), "shore", "a wreck is staged on the shore")
	eq(IncidentKit.stage_for("boat_overdue"), "shore", "so is a boat that did not come back")
	eq(IncidentKit.stage_for("herring_run"), "shore", "and the herring run")
	ok(IncidentKit.linger_for("goblin_sign") > 0.0, "goblin sign leaves something behind")

	## ADDENDUM B. The aftermath threat: explicit where it is set, one step
	## below the live threat and never above WARY where it is not.
	eq(IncidentKit.threat_after_for("fire"), -1, "cold char rings nothing, whatever the fire did")
	eq(IncidentKit.threat_after_for("bell_wrong"), -1, "nor does a bell that has stopped")
	eq(IncidentKit.threat_after_for("lost_child"), -1, "nor a search that has ended")
	eq(IncidentKit.threat_after_for("goblin_raid"), 2, "a raided hall is still worth the watch")
	eq(IncidentKit.threat_after_for("ravens_field"), 2, "and a field the ravens are still on")
	eq(IncidentKit.threat_for("wolves_at_fold"), 2, "the wolves themselves are an ALARM")
	eq(IncidentKit.threat_after_for("wolves_at_fold"), 1,
		"and the fold they left is a WARY, one step down, because the recipe sets no override")
	var louder := 0
	var out_of_range := 0
	var loud_after := 0
	for kid in IncidentKit.ids():
		var t := IncidentKit.threat_after_for(String(kid))
		if t > IncidentKit.threat_for(String(kid)):
			louder += 1
		if t < -1 or t > 3:
			out_of_range += 1
		if t > 1:
			loud_after += 1
	eq(louder, 0, "no aftermath is louder than the event that made it")
	eq(out_of_range, 0, "and every aftermath threat is a legal Telegraph level")
	eq(loud_after, 2, "and exactly two aftermaths are still worth an ALARM days later")

	var note := IncidentKit.note_for("wolves_at_fold", "Sebec")
	ok(note.contains("Sebec"), "note_for puts the place in the line (%s)" % note)
	ok(not note.contains("%s"), "and leaves no format token behind")

	var live_specs := IncidentKit.props_for("wolves_at_fold", "", true)
	var after_specs := IncidentKit.props_for("wolves_at_fold", "ewes_lost", false)
	ok(not live_specs.is_empty(), "a live fold has props")
	ok(not after_specs.is_empty(), "a lost fold has aftermath")
	ok(live_specs != after_specs, "the aftermath is not the live dressing")
	eq(IncidentKit.props_for("wolves_at_fold", "no_such_outcome", false), [],
		"an outcome nobody dressed is an empty stage, not a crash")
	(after_specs[0] as Dictionary)["n"] = 999
	var again := IncidentKit.props_for("wolves_at_fold", "ewes_lost", false)
	ok(int((again[0] as Dictionary).get("n", 1)) != 999, "props_for hands out a copy too")

	## Every kind's live dressing and every dressed outcome resolve to specs.
	var empty_live := 0
	var empty_after := 0
	for kid in IncidentKit.ids():
		if IncidentKit.props_for(String(kid), "", true).is_empty():
			empty_live += 1
		for o in (ChronicleEvents.by_id(String(kid)).get("outcomes", []) as Array):
			if IncidentKit.props_for(String(kid), String((o as Dictionary).get("id", "")), false).is_empty():
				empty_after += 1
	eq(empty_live, 0, "props_for returns live specs for all thirty-four kinds")
	eq(empty_after, 0, "props_for returns aftermath for all one hundred and twelve outcomes")
	settle("_test_lookups ran to the end")


## ---------------------------------------------------------------------------
##  3. the props themselves
## ---------------------------------------------------------------------------


func _test_props() -> void:
	claim("_test_props ran to the end")
	var moved_on_unit := 0
	var moved_on_index := 0
	var null_meshes := 0
	var buildable := 0
	for pk in IncidentKit.PROP_KINDS:
		## `critter` is exempt from the geometry sweep, exactly as it is in
		## `IncidentKit.problems()`: it is a live animal, the WildlifeDirector
		## owns it, and holding it to this would mean a box bird nothing ever
		## renders. It gets its own section instead.
		if String(pk) == NOT_BUILT:
			continue
		buildable += 1
		var spec := {"kind": pk}
		var n := IncidentKit.build_prop(spec, 0, 0.37)
		ok(n is Node3D, "prop '%s' builds a Node3D" % pk)
		if n == null:
			continue
		ok(_mesh_count(n) > 0, "prop '%s' carries real geometry (%d meshes)" % [pk, _mesh_count(n)])
		null_meshes += _null_meshes(n)
		n.free()
		## PURE: the whole idempotency promise of the Director rests on this.
		var d1 := _prop_digest(spec, 2, 0.37)
		eq(_prop_digest(spec, 2, 0.37), d1, "prop '%s' is a pure function of (spec, index, unit)" % pk)
		## Pure is half of it. A builder that ignores its roll entirely is pure
		## and also wrong: `n` copies of it are n identical objects standing in
		## a field, which is exactly what the Director's jitter cannot hide.
		ok(_prop_digest(spec, 2, 0.81) != d1, "prop '%s' varies with the roll" % pk)
		ok(_prop_digest(spec, 5, 0.37) != d1, "prop '%s' varies between its own copies" % pk)
		if _prop_digest(spec, 2, 0.81) != d1:
			moved_on_unit += 1
		if _prop_digest(spec, 5, 0.37) != d1:
			moved_on_index += 1

	eq(buildable, IncidentKit.PROP_KINDS.size() - 1, "every prop kind but the critter is built here")
	eq(null_meshes, 0, "no prop hangs a MeshInstance3D with no mesh on it")
	eq(moved_on_unit, buildable, "every buildable prop kind actually varies with the roll")
	eq(moved_on_index, buildable, "every buildable prop kind varies between its own copies")

	## THE ARG SWEEP. `problems()` checked the prop kind and never the arg, and
	## four recipes went a release staging `track: "wolf"`, `scat: "wolf"`,
	## `scat: "fox"` and `feather: "raven"` -- args with no builder branch, all
	## of which fell through to the default and came out as the wrong animal.
	## Every arg the table allows must build, must be pure, and must be
	## DIFFERENT from the no-arg default unless it is a known synonym for it.
	var arg_pairs := 0
	var arg_empty := 0
	var arg_impure := 0
	var arg_same: Array = []
	for pk in IncidentKit.PROP_ARGS.keys():
		var kind := String(pk)
		if kind == NOT_BUILT:
			continue
		var base := _prop_digest({"kind": kind}, 1, 0.42)
		for raw in (IncidentKit.PROP_ARGS[pk] as Array):
			var arg := String(raw)
			arg_pairs += 1
			var s := {"kind": kind, "arg": arg}
			var node := IncidentKit.build_prop(s, 1, 0.42)
			if node == null or _mesh_count(node) == 0:
				arg_empty += 1
			if node != null:
				node.free()
			var dg := _prop_digest(s, 1, 0.42)
			if dg != _prop_digest(s, 1, 0.42):
				arg_impure += 1
			if not arg.is_empty() and dg == base:
				arg_same.append("%s/%s" % [kind, arg])
	ok(arg_pairs >= 70, "the arg table is worth sweeping (%d kind/arg pairs)" % arg_pairs)
	eq(arg_empty, 0, "every allowed arg builds real geometry")
	eq(arg_impure, 0, "and every allowed arg is pure")
	arg_same.sort()
	eq(arg_same, ARG_SYNONYMS,
		"the only args identical to their default are the named colour synonyms")

	## The arg is part of the spec, so it has to be part of the function.
	eq(_prop_digest({"kind": "hurdle", "arg": "broken"}, 0, 0.5),
		_prop_digest({"kind": "hurdle", "arg": "broken"}, 0, 0.5),
		"a broken hurdle is pure too")
	ok(_prop_digest({"kind": "hurdle", "arg": "broken"}, 0, 0.5)
		!= _prop_digest({"kind": "hurdle"}, 0, 0.5), "a broken hurdle is not a whole one")
	ok(_prop_digest({"kind": "post", "arg": "burnt"}, 0, 0.5)
		!= _prop_digest({"kind": "post"}, 0, 0.5), "a burnt post is not a standing one")

	## The Kit does not build a critter and must not pretend to.
	var cr := IncidentKit.build_prop({"kind": NOT_BUILT, "arg": "crow"}, 0, 0.5)
	ok(cr != null, "asking the Kit for a critter still returns a node")
	ok(cr is Node3D, "and it is a Node3D")
	eq(_mesh_count(cr), 0, "but the Kit puts no geometry on it -- the Director routes it")
	cr.free()

	## An unknown prop kind is an empty stage, never a crash and never a null.
	var u := IncidentKit.build_prop({"kind": "definitely_not_a_prop"}, 0, 0.5)
	ok(u != null, "an unknown prop kind still returns a node")
	eq(_mesh_count(u), 0, "with nothing on it")
	u.free()
	var e := IncidentKit.build_prop({}, 0, 0.5)
	ok(e != null, "an empty spec returns a node rather than null")
	e.free()

	## `unit` is documented as [0,1); out-of-range must clamp, not fold.
	eq(_prop_digest({"kind": "barrel"}, 0, -3.0), _prop_digest({"kind": "barrel"}, 0, 0.0),
		"a roll below zero is clamped to zero, not folded")
	eq(_prop_digest({"kind": "barrel"}, 0, 7.5), _prop_digest({"kind": "barrel"}, 0, 0.999999),
		"and a roll above one is clamped to the top of the range")
	ok(_prop_digest({"kind": "barrel"}, 0, -3.0) != _prop_digest({"kind": "barrel"}, 0, 7.5),
		"and the two ends of the range are still different barrels")

	## The Kit's own vertical offset: a spec with a y is lifted by exactly that.
	var flat := IncidentKit.build_prop({"kind": "feather"}, 0, 0.5)
	var lifted := IncidentKit.build_prop({"kind": "feather", "y": 1.25}, 0, 0.5)
	near(lifted.position.y - flat.position.y, 1.25, 1e-5, "a spec 'y' lifts the prop by that much")
	flat.free()
	lifted.free()

	## And the whole catalogue builds: every spec of every scene, once.
	var built := 0
	var empties := 0
	var critters := 0
	for kid in IncidentKit.ids():
		var scenes: Array = [IncidentKit.props_for(String(kid), "", true)]
		for o in (ChronicleEvents.by_id(String(kid)).get("outcomes", []) as Array):
			scenes.append(IncidentKit.props_for(String(kid), String((o as Dictionary).get("id", "")), false))
		for sc in scenes:
			for raw in (sc as Array):
				var spec := raw as Dictionary
				if String(spec.get("kind", "")) == NOT_BUILT:
					critters += 1
					continue
				var node := IncidentKit.build_prop(spec, 0, 0.5)
				if node == null or _mesh_count(node) == 0:
					empties += 1
					continue
				built += 1
				node.free()
	ok(built > 400, "the whole catalogue builds (%d props)" % built)
	eq(empties, 0, "and not one buildable spec in it stages an empty node")
	ok(critters >= 6, "and the catalogue really does stage critters (%d specs)" % critters)
	settle("_test_props ran to the end")


## ---------------------------------------------------------------------------
##  4. where an incident lands
## ---------------------------------------------------------------------------


class Ground extends Node:
	## The duck-typed height provider, at a height nothing else in this suite
	## could produce by accident.
	var y := 31.5
	func _surface_y(_p: Vector3) -> float:
		return y


func _test_anchors() -> void:
	claim("_test_anchors ran to the end")
	var c := _chron()
	var p := _body()
	var d := _dir(c, p)
	var pos := Vector2(1000.0, -2000.0)

	var place_bad := 0
	var wild_bad := 0
	var moved := 0
	for uid in range(1, 121):
		var pr := {"uid": uid, "kind": "wolves_at_fold", "pos": pos}
		var wr := {"uid": uid, "kind": "wolf_hunt", "pos": pos}
		var dp := _flat(d.anchor_for(pr)).distance_to(pos)
		var dw := _flat(d.anchor_for(wr)).distance_to(pos)
		if dp < IncidentDirector.PLACE_NEAR - 1e-3 or dp > IncidentDirector.PLACE_FAR + 1e-3:
			place_bad += 1
		if dw < IncidentDirector.WILD_NEAR - 1e-3 or dw > IncidentDirector.WILD_FAR + 1e-3:
			wild_bad += 1
		if not is_equal_approx(dp, dw):
			moved += 1
	eq(place_bad, 0, "a place incident lands in the 18-34 m band, over a hundred and twenty uids")
	eq(wild_bad, 0, "a wild incident lands in the 60-140 m band, over the same")
	ok(moved > 100, "the two axes are genuinely different rolls (%d of 120)" % moved)

	## A road incident lands on the segment between its place and the nearest
	## OTHER place, in the middle 60% of it.
	var home: Dictionary = c.places[9]
	var hp: Vector2 = home["pos"]
	var best := Vector2.ZERO
	var bd := INF
	for q in c.places:
		var qp: Vector2 = (q as Dictionary)["pos"]
		var dd := qp.distance_to(hp)
		if dd <= 0.001:
			continue
		if dd < bd:
			bd = dd
			best = qp
	var off_line := 0
	var off_band := 0
	for uid in range(1, 61):
		var rr := {"uid": uid, "kind": "caravan_in", "pos": hp}
		var an := _flat(d.anchor_for(rr))
		var t := (an - hp).length() / maxf(bd, 1e-6)
		if t < 0.2 - 1e-3 or t > 0.8 + 1e-3:
			off_band += 1
		## On the segment: the distance to each end sums to the whole.
		if absf(an.distance_to(hp) + an.distance_to(best) - bd) > 0.05:
			off_line += 1
	eq(off_line, 0, "every road anchor sits on the segment to the nearest other place")
	eq(off_band, 0, "and inside the middle 60% of it")

	## anchor_for is a function of (seed, uid, scope, pos) and nothing else --
	## not the outcome, not how many times it has been asked.
	var rec := {"uid": 77, "kind": "wolves_at_fold", "pos": pos, "outcome": "held"}
	var a1 := d.anchor_for(rec)
	rec["outcome"] = "ewes_lost"
	rec["live"] = true
	rec["state"] = "staged"
	var a2 := d.anchor_for(rec)
	eq(a1, a2, "the anchor does not move when the outcome does")
	eq(a1, d.anchor_for(rec), "and asking again does not move it either")
	var d_other := _dir(c, p, SEED + 1)
	ok(d_other.anchor_for(rec) != a1, "a different world seed puts it somewhere else")

	## Ground height: none is y = 0, a provider is the provider's answer.
	near(a1.y, 0.0, 1e-6, "with no terrain an anchor sits honestly at y = 0")
	var g := Ground.new()
	d._ground = g
	near(d.anchor_for(rec).y, 31.5, 1e-4, "with a height provider the anchor is on the ground")
	near(_flat(d.anchor_for(rec)).distance_to(_flat(a1)), 0.0, 1e-4,
		"and the ground moves a place anchor only vertically")
	d._ground = null

	## Without a Chronicle there is no map to draw a road on, so a road
	## incident falls back to the place band rather than to the origin.
	var lone := _dir(null, p)
	var la := lone.anchor_for({"uid": 5, "kind": "caravan_in", "pos": pos})
	var ld := _flat(la).distance_to(pos)
	ok(ld >= IncidentDirector.PLACE_NEAR - 1e-3 and ld <= IncidentDirector.PLACE_FAR + 1e-3,
		"with no map a road incident falls back to the place band (%.2f m)" % ld)
	eq(la, lone.anchor_for({"uid": 5, "kind": "caravan_in", "pos": pos}),
		"and the fallback is deterministic too")

	ok(IncidentDirector.STRIKE_RADIUS > IncidentDirector.STAGE_RADIUS,
		"the strike radius is outside the stage radius")
	ok(IncidentDirector.EARSHOT < IncidentDirector.STAGE_RADIUS,
		"the props are built long before the player is told about them")
	ok(IncidentDirector.STAGE_PER_SCAN < IncidentDirector.MAX_STAGED,
		"a full cohort takes more than one scan to build")

	d.free()
	d_other.free()
	lone.free()
	g.free()
	p.free()
	c.free()
	settle("_test_anchors ran to the end")


## ---------------------------------------------------------------------------
##  5. the shore arm  (ADDENDUM A)
## ---------------------------------------------------------------------------


class Sea extends Node:
	## Land to the west of `edge`, water to the east of it. A half-plane is the
	## crudest possible coast and it is exactly enough: the walk only ever asks
	## "is this sample at or below the waterline".
	var edge := 0.0
	func _surface_y(p: Vector3) -> float:
		return 14.0 if p.x < edge else -3.0


class Highland extends Node:
	## Dry in every direction, forever. There is no shore to find.
	func _surface_y(_p: Vector3) -> float:
		return 22.0


class Flat extends Node:
	## What `World._surface_y` actually returns with the terrain switched off:
	## exactly 0.0, everywhere. Under a `<= 0.0` waterline that made the whole
	## world sea and parked every wreck two metres from the village square.
	var y := 0.0
	var calls := 0
	func _surface_y(_p: Vector3) -> float:
		calls += 1
		return y


## The shore walk, done by hand: sixteen bearings starting at the anchor hash,
## eight metres a step, first sample at or below the waterline, back off six.
## Mirroring it here rather than asserting on the ground height is deliberate --
## the back-off is 6 m and the step is 8, so on a straight coast met at a
## shallow angle the anchor can still be a metre or two wet, and that is the
## algorithm the addendum specifies rather than a bug in it.
func _shore_expect(at: Vector2, uid: int, seed_: int, ground: Object) -> Vector2:
	var h := IncidentDirector._hash(seed_, uid, IncidentDirector.SALT_ANCHOR)
	var start := int(IncidentDirector._unit(h, 0) * 16.0) % 16
	for b in range(16):
		var ang := float((start + b) % 16) * TAU / 16.0
		var dir := Vector2(cos(ang), sin(ang))
		var step := IncidentDirector.SHORE_STEP
		while step <= IncidentDirector.SHORE_REACH:
			var q := at + dir * step
			if float(ground.call("_surface_y", Vector3(q.x, IncidentDirector.GROUND_PROBE, q.y))) <= 0.0:
				return at + dir * maxf(step - IncidentDirector.SHORE_BACK, 0.0)
			step += IncidentDirector.SHORE_STEP
	## No water on any bearing: the ordinary place band, same hash.
	var bearing := IncidentDirector._unit(h, 0) * TAU
	var dd := lerpf(IncidentDirector.PLACE_NEAR, IncidentDirector.PLACE_FAR,
		IncidentDirector._unit(h, 1))
	return at + Vector2(cos(bearing), sin(bearing)) * dd


func _test_shore() -> void:
	claim("_test_shore ran to the end")
	var c := _chron()
	var p := _body()
	var d := _dir(c, p)
	var pl: Dictionary = c.places[4]
	var at: Vector2 = pl["pos"]
	var rec := {"uid": 101, "kind": "wreck_ashore", "pos": at}

	## Headless, with no ground provider, there is no waterline to walk to, so
	## the shore arm falls back to the ordinary place band. Everything else in
	## this suite depends on that.
	var dry_anchor := d.anchor_for(rec)
	var dd := _flat(dry_anchor).distance_to(at)
	ok(dd >= IncidentDirector.PLACE_NEAR - 1e-3 and dd <= IncidentDirector.PLACE_FAR + 1e-3,
		"with no ground provider a shore incident falls back to the place band (%.2f m)" % dd)
	eq(dry_anchor, d.anchor_for(rec), "and that fallback is deterministic")
	eq(dry_anchor, d.anchor_for({"uid": 101, "kind": "wolves_at_fold", "pos": at}),
		"it is the same band a place incident would have used")

	## Now put water 40 m east. The walk steps out on sixteen bearings until
	## the ground reports it is at or below zero, then backs off six metres.
	var sea := Sea.new()
	sea.edge = at.x + 40.0
	d._ground = sea
	var wet := d.anchor_for(rec)
	var arm := _flat(wet) - at
	ok(arm.length() > IncidentDirector.PLACE_FAR,
		"a shore anchor walks past the place band to reach the water (%.2f m)" % arm.length())
	ok(arm.length() <= IncidentDirector.SHORE_REACH,
		"and stops inside the hard reach (%.2f m)" % arm.length())
	near(wet.y, 14.0, 1e-4, "and it stands on the land side of the waterline, not in the sea")

	## Work the walk out by hand and check the Director landed on the same
	## grain of sand: same bearing set, same step, same back-off.
	var want := _shore_expect(at, 101, d.world_seed, sea)
	near(_flat(wet).distance_to(want), 0.0, 1e-3, "the hand-walked sweep lands on the same point")
	near(sea._surface_y(Vector3(wet.x + arm.normalized().x * IncidentDirector.SHORE_BACK, 0.0,
		wet.z + arm.normalized().y * IncidentDirector.SHORE_BACK)), -3.0, 1e-4,
		"six metres further along the bearing really is water")
	near(fmod(arm.length() + IncidentDirector.SHORE_BACK, IncidentDirector.SHORE_STEP), 0.0, 1e-3,
		"and the wet sample it backed off from is a whole number of steps out")

	## Deterministic and uid-stable: same uid, same beach; different uid,
	## generally a different one; different seed, different again.
	eq(wet, d.anchor_for(rec), "asking twice gives the same beach")
	var d2 := _dir(c, p)
	d2._ground = sea
	eq(d2.anchor_for(rec), wet, "and a second Director with the same seed picks the same beach")
	var d3 := _dir(c, p, SEED + 31)
	d3._ground = sea
	ok(d3.anchor_for(rec) != wet, "a different seed picks a different one")
	var spread := {}
	for uid in range(1, 33):
		var a := d.anchor_for({"uid": uid, "kind": "herring_run", "pos": at})
		spread["%.3f,%.3f" % [a.x, a.z]] = true
		near(_flat(a).distance_to(_shore_expect(at, uid, d.world_seed, sea)), 0.0, 1e-3,
			"shore uid %d walked the sweep the addendum specifies" % uid)
	ok(spread.size() >= 2, "thirty-two uids do not all pile onto one spot (%d distinct)" % spread.size())

	## NEW-4. `World._surface_y` returns exactly 0.0 for every sample when the
	## terrain is off, and the valley floor is documented as ground at y = 0, so
	## the waterline cannot be `<= 0.0`. A flat-zero world is LAND.
	var flat := Flat.new()
	d._ground = flat
	var on_zero := d.anchor_for(rec)
	var zd := _flat(on_zero).distance_to(at)
	ok(zd >= IncidentDirector.PLACE_NEAR - 1e-3 and zd <= IncidentDirector.PLACE_FAR + 1e-3,
		"a flat-zero world is land, so a wreck lands in the place band (%.2f m)" % zd)
	ok(zd > IncidentDirector.SHORE_STEP - IncidentDirector.SHORE_BACK + 1e-3,
		"and not two metres from the village square, which is what a 0.0 waterline gave")
	near(_flat(on_zero).distance_to(_flat(dry_anchor)), 0.0, 1e-4,
		"it is exactly the band it would have used with no provider at all")
	## And the threshold itself is where the constant says it is.
	flat.y = IncidentDirector.WATER_Y + 0.01
	var barely_dry := d.anchor_for(rec)
	near(_flat(barely_dry).distance_to(_flat(dry_anchor)), 0.0, 1e-4,
		"a hair above WATER_Y is still land")
	flat.y = IncidentDirector.WATER_Y
	var barely_wet := d.anchor_for(rec)
	near(_flat(barely_wet).distance_to(at), IncidentDirector.SHORE_STEP - IncidentDirector.SHORE_BACK, 1e-3,
		"and WATER_Y itself is water: the walk stops on its very first step")
	ok(_flat(barely_wet).distance_to(_flat(barely_dry)) > 1.0,
		"so a hundredth of a metre either side of WATER_Y is a different beach")

	## A place with no water anywhere near it walks all sixteen bearings out to
	## SHORE_REACH, finds nothing, and falls back to the place band rather than
	## dropping the wreck at the map origin.
	var high := Highland.new()
	d._ground = high
	var inland := d.anchor_for(rec)
	var idist := _flat(inland).distance_to(at)
	ok(idist >= IncidentDirector.PLACE_NEAR - 1e-3 and idist <= IncidentDirector.PLACE_FAR + 1e-3,
		"a shore incident inland falls back to the place band (%.2f m)" % idist)
	near(_flat(inland).distance_to(_flat(dry_anchor)), 0.0, 1e-4,
		"and to exactly the band it would have used with no provider at all")
	near(inland.y, 22.0, 1e-4, "sitting on the hill it is actually on")

	## All three shore kinds take the arm, and nothing else does.
	d._ground = sea
	var band := d.anchor_for({"uid": 55, "kind": "fair", "pos": at})
	for kid in ["boat_overdue", "wreck_ashore", "herring_run"]:
		var sa := d.anchor_for({"uid": 55, "kind": kid, "pos": at})
		near(_flat(sa).distance_to(_shore_expect(at, 55, d.world_seed, sea)), 0.0, 1e-3,
			"'%s' walks out to the water" % kid)
		ok(_flat(sa).distance_to(_flat(band)) > 1.0,
			"'%s' does not land where a plain place incident would" % kid)
	ok(_flat(band).distance_to(at) <= IncidentDirector.PLACE_FAR + 1e-3,
		"a plain place incident does not go looking for the sea")

	d._ground = null
	d.free()
	d2.free()
	d3.free()
	sea.free()
	high.free()
	flat.free()
	p.free()
	c.free()
	settle("_test_shore ran to the end")


## ---------------------------------------------------------------------------
##  6. the line layout  (ADDENDUM C)
## ---------------------------------------------------------------------------


func _test_layout() -> void:
	claim("_test_layout ran to the end")
	## A fold is a fence and the gap in it is the story, so the hurdles are laid
	## along one bearing with one shared yaw rather than scattered on a disc.
	ok((IncidentKit.props_for("wolves_at_fold", "", true)[0] as Dictionary).get("layout", "") == "line",
		"the fold's hurdles are a line in the catalogue")

	var c := _chron()
	var pl: Dictionary = c.places[6]
	var at: Vector2 = pl["pos"]
	var p := _body()
	_put(p, at)
	var d := _dir(c, p)
	var e := _ev(c, "wolves_at_fold", pl, 900.0)
	c.active.append(e)
	d.scan(900.05)
	var uid := int(e["uid"])
	eq(d.record_for(uid).get("state", ""), "staged", "the fold is up")
	var root: Node = d._nodes[uid]

	var hurdles := _props_of(root, "hurdle")
	eq(hurdles.size(), 3, "three hurdle panels were built")
	var tracks := _props_of(root, "track")
	ok(tracks.size() >= 4, "and a scatter of tracks to compare them against (%d)" % tracks.size())

	## A line is a line: every panel on one bearing through the anchor.
	var q0 := _flat((hurdles[0] as Node3D).position)
	var q1 := _flat((hurdles[1] as Node3D).position)
	var q2 := _flat((hurdles[2] as Node3D).position)
	var axis := (q2 - q0).normalized()
	var off_axis := absf((q1 - q0).cross(axis))
	near(off_axis, 0.0, 1e-3, "the three panels are collinear (%.5f m off)" % off_axis)
	near(q1.length(), 0.0, 1e-3, "and the middle one sits on the anchor")
	near((q0 + q1 + q2).length(), 0.0, 1e-3, "so the run is centred on it")
	near(q0.distance_to(q1), q1.distance_to(q2), 1e-3, "and evenly spaced")
	## Spacing is spread/n, so a three-panel run at spread 3.2 steps 1.067 m.
	var spec := IncidentKit.props_for("wolves_at_fold", "", true)[0] as Dictionary
	near(q0.distance_to(q1), float(spec["spread"]) / 3.0, 1e-3,
		"at the spacing the addendum specifies")

	## One yaw down the whole fence, and it is not the per-copy yaw a disc gets.
	var yaws := {}
	for n in hurdles:
		yaws["%.6f" % (n as Node3D).rotation.y] = true
	eq(yaws.size(), 1, "every panel of the fence shares one yaw")
	var tyaws := {}
	for n in tracks:
		tyaws["%.6f" % (n as Node3D).rotation.y] = true
	ok(tyaws.size() > 1, "while the scattered tracks each got their own (%d)" % tyaws.size())

	## And the disc really is a disc: three scattered props are not collinear.
	var t0 := _flat((tracks[0] as Node3D).position)
	var t1 := _flat((tracks[1] as Node3D).position)
	var t2 := _flat((tracks[2] as Node3D).position)
	ok(absf((t1 - t0).cross((t2 - t0).normalized())) > 1e-2,
		"the scattered props are not on a line")

	## PURE. Strike it, restage it, and every panel is on the same grass.
	var before := _digest_node(root)
	_put(p, at + Vector2(5000.0, 0.0))
	d.scan(900.1)
	_put(p, at)
	d.scan(900.15)
	eq(d.record_for(uid).get("state", ""), "staged", "restaged after the walk")
	var after := _digest_node(d._nodes[uid] as Node)
	eq(after, before, "and the whole incident, line layout and all, is byte-identical")

	## A second Director with the same seed lays the same fence.
	var p2 := _body()
	_put(p2, at)
	var d2 := _dir(c, p2)
	d2.scan(900.2)
	eq(_digest_node(d2._nodes[uid] as Node), before, "and so does a second Director on the same seed")

	d.free()
	d2.free()
	p.free()
	p2.free()
	c.free()
	settle("_test_layout ran to the end")


## ---------------------------------------------------------------------------
##  7. critters  (ADDENDUM D)
## ---------------------------------------------------------------------------


class Wild extends Node:
	## Stands in for the WildlifeDirector. Records what it was asked for, hands
	## back a Node3D it owns, and can cull one behind the Director's back --
	## which is exactly what `WildlifeDirector._cull` really does.
	var asked: Array = []
	var made: Array = []
	var refuse := false
	func spawn_one(key: String, at: Vector3) -> Node3D:
		asked.append([key, at])
		if refuse:
			return null
		var n := Node3D.new()
		n.name = "critter_%s_%d" % [key, made.size()]
		n.position = at
		add_child(n)
		made.append(n)
		return n
	func cull(n: Node) -> void:
		## Exactly what WildlifeDirector._cull does: frees the animal on its own
		## budget and tells nobody.
		made.erase(n)
		n.free()


func _test_critters() -> void:
	claim("_test_critters ran to the end")
	var c := _chron()
	var pl: Dictionary = c.places[8]
	var at: Vector2 = pl["pos"]
	var p := _body()
	_put(p, at)
	var d := _dir(c, p)
	var w := Wild.new()
	d._wildlife = w

	## deer_yard promises deer in its note; it had better stage deer.
	var deer_specs := IncidentKit.props_for("deer_yard", "", true)
	var want_deer := 0
	for s in deer_specs:
		if String((s as Dictionary).get("kind", "")) == NOT_BUILT:
			want_deer += int((s as Dictionary).get("n", 1))
	ok(want_deer > 0, "the deer yard stages actual deer (%d of them)" % want_deer)

	var e := _ev(c, "deer_yard", pl, 950.0)
	c.active.append(e)
	d.scan(950.05)
	var uid := int(e["uid"])
	eq(d.record_for(uid).get("state", ""), "staged", "the deer yard is up")
	eq(w.asked.size(), want_deer, "the Director asked the wildlife director for every one")
	var species := {}
	for a in w.asked:
		species[String((a as Array)[0])] = true
	eq(species.keys(), ["deer"], "and asked for deer, which is what the note promises")
	eq((d._critters.get(uid, []) as Array).size(), want_deer, "and tracked them all under this uid")

	## The critters are NOT children of the incident root -- the wildlife
	## director owns them -- but they DO count towards the incident's props.
	var root: Node = d._nodes[uid]
	eq(_props_of(root, NOT_BUILT).size(), 0, "no box deer was parented to the incident")
	eq(int(d.record_for(uid).get("props", 0)), root.get_child_count() + want_deer,
		"the prop count is the geometry on the ground plus every animal asked for")
	var placed := 0
	for a in w.asked:
		if _flat((a as Array)[1] as Vector3).distance_to(_flat(d.record_for(uid)["anchor"])) <= 20.0:
			placed += 1
	eq(placed, want_deer, "and every one was put down near the anchor, not at the origin")

	## WHERE each one goes is deterministic even though what it does next is
	## not: a second Director with the same seed asks for the same positions.
	var p2 := _body()
	_put(p2, at)
	var d2 := _dir(c, p2)
	var w2 := Wild.new()
	d2._wildlife = w2
	d2.scan(950.06)
	eq(w2.asked.size(), w.asked.size(), "the second Director asked for the same number")
	var same_spots := 0
	for i in w.asked.size():
		if ((w.asked[i] as Array)[1] as Vector3) == ((w2.asked[i] as Array)[1] as Vector3):
			same_spots += 1
	eq(same_spots, w.asked.size(), "and put every one of them on the same spot")

	## A strike takes the incident's own animals down with it.
	var held: Array = (d._critters.get(uid, []) as Array).duplicate()
	eq(w.made.size(), want_deer, "the wildlife director is holding them")
	_put(p, at + Vector2(6000.0, 0.0))
	d.scan(950.1)
	eq(d.record_for(uid).get("state", ""), "known", "walked away: struck")
	eq(d._critters.has(uid), false, "and the incident stopped tracking its animals")
	var still := 0
	for n in held:
		if is_instance_valid(n):
			still += 1
	eq(still, 0, "and every one of them was freed with the props")
	w.made.clear()

	## The cull -- the wildlife director freeing an animal behind the Director's
	## back -- is its own section at the end of the run. See `_test_critter_cull`.

	## THE DIGEST MUST NOT KNOW. `spawn_one` is free to refuse -- no ground under
	## the spot, no water for a water species -- and `_cull` frees animals on its
	## own budget afterwards, so counting the ANIMAL rather than the DECISION ran
	## the wildlife director's non-determinism straight into `props`, which is in
	## `report()` and in `to_dict()`. Two Directors with the same seed on the same
	## Chronicle were measured disagreeing 24 vs 23. Hard Rule 2 says they may
	## not. So: a Director whose stub refuses EVERY spawn must produce a
	## byte-identical digest to one whose stub accepts them all.
	w.refuse = true
	_put(p, at)
	d.scan(950.3)
	eq(d.record_for(uid).get("state", ""), "staged", "a refused spawn still stages the incident")
	eq(d._critters.has(uid), false, "with nothing tracked")
	eq(int(d.record_for(uid).get("props", 0)), (d._nodes[uid] as Node).get_child_count() + want_deer,
		"and a prop count that still counts every animal it asked for")

	## No wildlife director at all: same again, and no complaint.
	d._wildlife = null
	_put(p, at)
	d._free_nodes(uid)
	d.scan(950.35)
	eq(d.record_for(uid).get("state", ""), "staged", "and with no wildlife director bound at all")
	eq(int(d.record_for(uid).get("props", 0)), (d._nodes[uid] as Node).get_child_count() + want_deer,
		"the count is still the request, not the delivery")

	## Three Directors, one Chronicle, one seed, three different wildlife
	## directors: one that spawns everything, one that refuses everything, and
	## one bound to nothing at all. Their digests must be indistinguishable.
	var c3 := _chron(SEED + 29)
	var pl3: Dictionary = c3.places[8]
	var at3: Vector2 = pl3["pos"]
	for i in 4:
		c3.resolved.append(_ev(c3, "ravens_field", pl3, 960.0, _first_outcome("ravens_field")))
		c3.resolved.append(_ev(c3, "wolves_at_fold", pl3, 960.0, "ewes_lost"))
	var wanted := 0
	for e2 in c3.resolved:
		wanted += _critters_wanted(String((e2 as Dictionary)["kind"]),
			String((e2 as Dictionary)["outcome"]), false)
	ok(wanted >= 8, "the workload really does ask for animals (%d)" % wanted)

	var pa := _body()
	var pb := _body()
	var pz := _body()
	_put(pa, at3)
	_put(pb, at3)
	_put(pz, at3)
	var da := _dir(c3, pa)
	var db := _dir(c3, pb)
	var dz := _dir(c3, pz)
	var wa := Wild.new()
	var wb := Wild.new()
	wb.refuse = true
	da._wildlife = wa
	db._wildlife = wb
	## dz gets no wildlife director at all.
	for i in 6:
		da.scan(960.1 + float(i) * 0.001)
		db.scan(960.1 + float(i) * 0.001)
		dz.scan(960.1 + float(i) * 0.001)
	ok(wa.made.size() >= 8, "the accepting stub really did spawn animals (%d)" % wa.made.size())
	eq(wb.made.size(), 0, "the refusing stub spawned none")
	ok(wb.asked.size() >= 8, "though it was asked for just as many (%d)" % wb.asked.size())
	eq(da.report(), db.report(), "and the two Directors report identically all the same")
	eq(da.report(), dz.report(), "and so does one with no wildlife director at all")
	eq(da.to_dict(), db.to_dict(), "and they save byte-identical worlds")
	eq(da.to_dict(), dz.to_dict(), "all three of them")
	eq(int(da.report()["props"]), int(db.report()["props"]),
		"the prop total does not move with the wildlife director's mood")

	## And the cull cannot move it either: freeing half the animals behind the
	## Director's back changes what is on the hillside, never what is recorded.
	var props_before := int(da.report()["props"])
	var digest_before := da.report()
	var alive_now: Array = wa.made.duplicate()
	for i in range(0, alive_now.size(), 2):
		if is_instance_valid(alive_now[i]):
			wa.cull(alive_now[i])
	eq(int(da.report()["props"]), props_before, "culling animals does not change the prop count")
	eq(da.report(), digest_before, "nor anything else in the digest")

	d.free()
	d2.free()
	da.free()
	db.free()
	dz.free()
	w.free()
	w2.free()
	wa.free()
	wb.free()
	p.free()
	p2.free()
	pa.free()
	pb.free()
	pz.free()
	c.free()
	c3.free()
	settle("_test_critters ran to the end")


## ---------------------------------------------------------------------------
##  8. two Directors, one story
## ---------------------------------------------------------------------------


func _test_determinism() -> void:
	claim("_test_determinism ran to the end")
	## A real twenty-day run: real kinds, real places, real uids.
	var c := _chron()
	c.advance(24.0 * 20.0)
	ok(c.resolved.size() > 0, "twenty days of Chronicle produced aftermath (%d)" % c.resolved.size())

	## Walk both Directors past the same three places in the same order.
	var route: Array = []
	for e in c.resolved:
		var ev := e as Dictionary
		if route.size() < 3:
			route.append(ev.get("pos", Vector2.ZERO) as Vector2)

	var pa := _body()
	var pb := _body()
	var pc := _body()
	var a := _dir(c, pa)
	var b := _dir(c, pb)
	var z := _dir(c, pc, SEED + 977)
	var day := c.days
	for step in route.size():
		_put(pa, route[step])
		_put(pb, route[step])
		_put(pc, route[step])
		for again in 5:
			a.scan(day + float(step) * 0.01 + float(again) * 0.001)
			b.scan(day + float(step) * 0.01 + float(again) * 0.001)
			z.scan(day + float(step) * 0.01 + float(again) * 0.001)

	ok(a.incidents.size() > 0, "the Director recorded something (%d)" % a.incidents.size())
	eq(a.incidents.size(), b.incidents.size(), "two Directors on one Chronicle record the same count")
	eq(a.report(), b.report(), "and report identically")
	eq(a.staged_uids(), b.staged_uids(), "and stage the same uids")

	var moved := 0
	var missing := 0
	for uid in a.incidents.keys():
		var ra: Dictionary = a.record_for(int(uid))
		var rb: Dictionary = b.record_for(int(uid))
		if rb.is_empty():
			missing += 1
			continue
		if (ra["anchor"] as Vector3) != (rb["anchor"] as Vector3):
			moved += 1
	eq(moved, 0, "and put every anchor on the same tuft of grass")
	eq(missing, 0, "with no record missing from either")
	## The save is the other digest two Directors that lived the same life must
	## agree on, and unlike `report()` it is the one that reaches the disk.
	eq(a.to_dict(), b.to_dict(), "and they save byte-identical worlds")
	ok(a.to_dict() != z.to_dict(), "while the third seed does not")

	## A third seed is a different world.
	eq(z.incidents.size(), a.incidents.size(), "a different seed still sees the same events")
	ok((z.report()["rows"] as Array) != (a.report()["rows"] as Array),
		"but reports different anchors")
	var differing := 0
	for uid in a.incidents.keys():
		var rz: Dictionary = z.record_for(int(uid))
		if rz.is_empty():
			continue
		if (rz["anchor"] as Vector3) != (a.record_for(int(uid))["anchor"] as Vector3):
			differing += 1
	ok(differing >= a.incidents.size() - 1,
		"a different seed moves essentially every anchor (%d of %d)" % [differing, a.incidents.size()])

	## Every record carries exactly the contract's keys, no more and no fewer.
	var wrong_keys := 0
	var bad_state := 0
	var bad_types := 0
	var bad_clock := 0
	for uid in a.incidents.keys():
		var r: Dictionary = a.record_for(int(uid))
		for k in REC_KEYS:
			if not r.has(k):
				wrong_keys += 1
		if r.size() != REC_KEYS.size():
			wrong_keys += 1
		if not STATES.has(String(r.get("state", ""))):
			bad_state += 1
		if not (r.get("pos") is Vector2) or not (r.get("anchor") is Vector3):
			bad_types += 1
		if not (r.get("live") is bool) or not (r.get("heard") is bool):
			bad_types += 1
		## `resolved_at` is -1.0 while live and a real day once resolved, and it
		## can never be in the future.
		var ra := float(r.get("resolved_at", -99.0))
		if bool(r.get("live", false)):
			if ra != -1.0:
				bad_clock += 1
		elif ra < 0.0 or ra > a._last_days + 1e-6:
			bad_clock += 1
	eq(wrong_keys, 0, "every record holds exactly the contract's thirteen keys")
	eq(bad_state, 0, "every state is known|staged|spent and nothing else")
	eq(bad_types, 0, "pos is a Vector2, anchor a Vector3, live and heard bools")
	eq(bad_clock, 0, "resolved_at is -1 while live and a past day once resolved")
	## The save's key set is the record's key set, checked against the SOURCE
	## rather than against this file's own constant: a key added to the record
	## and forgotten in `to_dict` is a key that does not survive a load.
	var rows := a.to_dict()["incidents"] as Array
	ok(not rows.is_empty(), "the save has rows to check")
	var row_keys: Array = (rows[0] as Dictionary).keys()
	row_keys.sort()
	var live_keys: Array = a.record_for(int(a.incidents.keys()[0])).keys()
	live_keys.sort()
	eq(row_keys, live_keys, "every key on the record is a key in the save, and no others")
	## And the transient re-dress queue is Director state, never a record key.
	ok(not row_keys.has("redress"), "the re-dress queue does not leak into the save")

	a.free()
	b.free()
	z.free()
	pa.free()
	pb.free()
	pc.free()
	c.free()
	settle("_test_determinism ran to the end")


## ---------------------------------------------------------------------------
##  9. walk away, walk back
## ---------------------------------------------------------------------------


func _test_idempotency() -> void:
	claim("_test_idempotency ran to the end")
	var c := _chron()
	var pl: Dictionary = c.places[3]
	var at: Vector2 = pl["pos"]
	var p := _body()
	_put(p, at)
	var d := _dir(c, p)

	var staged_seen := {}
	var stage_events := [0]
	var strike_events := [0]
	var redress_events := [0]
	d.incident_staged.connect(func(rec): staged_seen[int(rec["uid"])] = int(staged_seen.get(int(rec["uid"]), 0)) + 1; stage_events[0] += 1)
	d.incident_struck.connect(func(_r): strike_events[0] += 1)
	d.incident_redressed.connect(func(_r): redress_events[0] += 1)

	var e := _ev(c, "wolves_at_fold", pl, 100.0, "ewes_lost")
	c.resolved.append(e)
	var uid := int(e["uid"])

	d.scan(100.1)
	var r: Dictionary = d.record_for(uid)
	eq(r.get("state", ""), "staged", "the incident is physical when the player is standing in it")
	var anchor0: Vector3 = r["anchor"]
	var props0 := int(r["props"])
	var size0 := d.incidents.size()
	ok(props0 > 0, "and it built something (%d props)" % props0)
	## A lost fold asks for crows, and `props` counts what was asked for -- so
	## the node count is the props MINUS the animals, which are the wildlife
	## director's children and not the incident's.
	var crows := _critters_wanted("wolves_at_fold", "ewes_lost", false)
	ok(crows > 0, "the aftermath of a lost fold asks for crows (%d)" % crows)
	eq(int((d._nodes[uid] as Node).get_child_count()), props0 - crows,
		"the record's prop count is the node count plus the animals it asked for")
	eq(size0, 1, "one event is one record")
	var digest0 := _digest_node(d._nodes[uid] as Node)

	var far := at + Vector2(5000.0, 0.0)
	for cycle in 3:
		## away
		_put(p, far)
		d.scan(100.2 + float(cycle) * 0.1)
		eq(r.get("state", ""), "known", "cycle %d: struck, the record kept" % cycle)
		eq(int(r["props"]), 0, "cycle %d: no props while struck" % cycle)
		eq(d._nodes.size(), 0, "cycle %d: no nodes while struck" % cycle)
		eq(d.incidents.size(), size0, "cycle %d: striking did not change the record count" % cycle)
		eq(d.staged_uids(), [], "cycle %d: nothing is staged out there" % cycle)
		eq((r["anchor"] as Vector3), anchor0, "cycle %d: the anchor survived the strike" % cycle)
		## back
		_put(p, at)
		d.scan(100.25 + float(cycle) * 0.1)
		eq(r.get("state", ""), "staged", "cycle %d: restaged on return" % cycle)
		eq((r["anchor"] as Vector3), anchor0, "cycle %d: on the same tuft of grass" % cycle)
		eq(int(r["props"]), props0, "cycle %d: with the same props" % cycle)
		eq(d.incidents.size(), size0, "cycle %d: still one record, not two" % cycle)
		eq(d.staged_uids(), [uid], "cycle %d: and only the one uid staged" % cycle)
		eq(_digest_node(d._nodes[uid] as Node), digest0,
			"cycle %d: and every prop back on the same grass, box for box" % cycle)

	eq(staged_seen.size(), 1, "only ever one uid was staged")
	eq(int(staged_seen[uid]), 4, "staged once at the start and once per return")
	eq(strike_events[0], 3, "struck once per departure")
	eq(redress_events[0], 0, "and never re-dressed, because it never resolved under us")
	eq(d.incidents.size(), 1, "three round trips grew nothing")
	eq(_uids_of(d.report()["rows"] as Array), [uid], "and the report still lists it once")
	## THE MATCHED PAIR. `incident_staged` and `incident_struck` are one each per
	## uid per visit, and a listener that pools audio emitters off them has every
	## right to assume so: what is currently up is exactly staged minus struck.
	eq(stage_events[0] - strike_events[0], d.staged_uids().size(),
		"staged minus struck is exactly what is standing")

	## The record survives having its nodes taken out from under it -- a chunk
	## unload is exactly this, and the next scan must put them back.
	d._free_nodes(uid)
	eq(d._nodes.size(), 0, "the nodes are gone")
	eq(r.get("state", ""), "staged", "but the record still says staged")
	d.scan(100.9)
	eq(r.get("state", ""), "staged", "and the next scan makes the scene agree again")
	eq(int(r["props"]), props0, "with the same props once more")
	eq((r["anchor"] as Vector3), anchor0, "in the same place once more")
	eq(d.incidents.size(), 1, "and still one record")

	d.free()
	p.free()
	c.free()
	settle("_test_idempotency ran to the end")


## ---------------------------------------------------------------------------
##  10. the event that ends while you are watching it
## ---------------------------------------------------------------------------


func _test_live_to_resolved() -> void:
	claim("_test_live_to_resolved ran to the end")
	var c := _chron()
	var pl: Dictionary = c.places[7]
	var at: Vector2 = pl["pos"]
	var p := _body()
	_put(p, at)
	var d := _dir(c, p)
	var stages := [0]
	var strikes := [0]
	var redress: Array = []
	d.incident_staged.connect(func(_r): stages[0] += 1)
	d.incident_struck.connect(func(_r): strikes[0] += 1)
	d.incident_redressed.connect(func(rec): redress.append(int(rec["uid"])))

	var e := _ev(c, "fire", pl, 200.0, "", 0.06)
	c.active.append(e)
	d.scan(200.05)
	var uid := int(e["uid"])
	var r: Dictionary = d.record_for(uid)
	eq(d.incidents.size(), 1, "the live event is one record")
	eq(r.get("live", false), true, "and it is marked live")
	eq(String(r.get("outcome", "x")), "", "with no outcome yet")
	eq(float(r.get("resolved_at", 0.0)), -1.0, "and no aftermath clock yet")
	eq(r.get("state", ""), "staged", "and it is physical")
	var anchor0: Vector3 = r["anchor"]
	var live_props := int(r["props"])
	ok(live_props > 0, "the live event has props (%d)" % live_props)
	eq(stages[0], 1, "one staging so far")

	## The Chronicle resolves it: the SAME dictionary, moved from active to
	## resolved, exactly as Chronicle._resolve does it.
	var oid := _first_outcome("fire")
	_resolve(c, e, oid)

	d.scan(200.1)
	eq(d.incidents.size(), 1, "the resolution did not make a second record")
	ok(d.record_for(uid) == r, "it is the same record object, updated in place")
	eq(r.get("live", true), false, "the record is no longer live")
	eq(String(r.get("outcome", "")), oid, "and now carries the outcome")
	eq(r.get("state", ""), "staged", "and it is still physical")
	eq((r["anchor"] as Vector3), anchor0, "the anchor did not move when the ending arrived")
	## THE AFTERMATH CLOCK, stamped from the Chronicle's own `ends` rather than
	## from whenever the Director happened to look.
	near(float(r.get("resolved_at", -1.0)), float(e["ends"]), 1e-6,
		"resolved_at is the Chronicle's own end time")
	ok(float(r.get("resolved_at", -1.0)) < 200.1,
		"which is before the scan that noticed it, not at it")
	ok(float(r.get("resolved_at", -1.0)) > float(r.get("born", 0.0)),
		"and after the event fired")
	## RE-DRESSED, not staged twice: staged and struck stay a matched pair.
	eq(stages[0], 1, "no second incident_staged was emitted")
	eq(strikes[0], 0, "and nothing was struck")
	eq(redress, [uid], "the transition emitted incident_redressed instead")
	eq(stages[0] - strikes[0], d.staged_uids().size(), "so the matched pair still balances")
	var after_props := int(r["props"])
	ok(after_props > 0, "the aftermath has props (%d)" % after_props)
	var crows := _critters_wanted("fire", oid, false)
	eq(int((d._nodes[uid] as Node).get_child_count()), after_props - crows,
		"and they are the nodes on the ground")
	ok(after_props != live_props, "the aftermath is dressed differently from the live event")
	## NEW-6. A re-dress FREES the old dressing before building the new one. It
	## is the one line in `_build_nodes` that makes a rebuild a rebuild rather
	## than a second copy, and dropping it leaves the whole previous dressing on
	## the hillside under a record that says it is not there.
	eq(d.get_child_count(), d.staged_uids().size(),
		"one node tree per staged incident, so the re-dress freed the live dressing")
	eq(d._nodes.size(), d.staged_uids().size(), "and the node table agrees")

	## Reading the resolved ring again must not touch it a third time.
	d.scan(200.15)
	d.scan(200.2)
	eq(d.incidents.size(), 1, "rescanning the same resolved ring adds nothing")
	eq(stages[0], 1, "and stages nothing")
	eq(redress.size(), 1, "and re-dresses nothing")
	eq(String(r.get("outcome", "")), oid, "and leaves the outcome alone")
	near(float(r.get("resolved_at", -1.0)), float(e["ends"]), 1e-6, "and the clock alone")

	## An event that resolves while the player is a valley away is still
	## updated -- the resolved ring is read whole, with no distance filter --
	## and it is NOT re-dressed, because it was not physical to begin with.
	var e2 := _ev(c, "bees", pl, 200.0, "", 0.05)
	c.active.append(e2)
	d.scan(200.25)
	var r2: Dictionary = d.record_for(int(e2["uid"]))
	eq(r2.get("live", false), true, "the second event is live")
	_put(p, at + Vector2(9000.0, 0.0))
	d.scan(200.28)
	eq(r2.get("state", ""), "known", "and it is struck when the player walks over the hill")
	_resolve(c, e2)
	d.scan(200.3)
	eq(r2.get("live", true), false, "an event that ends while you are far away is still ended")
	eq(String(r2.get("outcome", "")), _first_outcome("bees"), "with its outcome filled in")
	near(float(r2.get("resolved_at", -1.0)), float(e2["ends"]), 1e-6, "and its clock stamped")
	eq(r2.get("state", ""), "known", "and it is not physical out there")
	eq(redress.size(), 1, "and nothing was re-dressed for it, because it was not physical")
	eq(d.incidents.size(), 2, "two events, two records")
	## An incident that resolves while it is STILL physical is the re-dress
	## case, and it is the only one: the fire above proved it, this proves the
	## other half.
	_put(p, at)
	d.scan(200.35)
	eq(r2.get("state", ""), "staged", "walking back stages its aftermath")
	eq(redress.size(), 1, "which is a staging, not a re-dressing")

	d.free()
	p.free()
	c.free()
	settle("_test_live_to_resolved ran to the end")


## ---------------------------------------------------------------------------
##  11. ageing out, and staying out
## ---------------------------------------------------------------------------


func _test_ageing() -> void:
	claim("_test_ageing ran to the end")
	var c := _chron()
	var pl: Dictionary = c.places[5]
	var at: Vector2 = pl["pos"]
	var p := _body()
	_put(p, at)
	var d := _dir(c, p)
	var spent := [0]
	var spent_uids := {}
	var stages := [0]
	d.incident_spent.connect(func(rec): spent[0] += 1; spent_uids[int(rec["uid"])] = true)
	d.incident_staged.connect(func(_r): stages[0] += 1)

	## aurora lingers half a day; storm_damage lingers three.
	var quick := _ev(c, "aurora", pl, 300.0, _first_outcome("aurora"))
	var slow := _ev(c, "storm_damage", pl, 300.0, _first_outcome("storm_damage"))
	c.resolved.append(quick)
	c.resolved.append(slow)
	var qu := int(quick["uid"])
	var su := int(slow["uid"])
	var ended := float(quick["ends"])

	d.scan(300.1)
	eq(d.incidents.size(), 2, "two aftermaths recorded")
	near(float(d.record_for(qu).get("resolved_at", -1.0)), ended, 1e-6,
		"the aftermath clock is the event's own end time")
	eq(d.record_for(qu).get("state", ""), "staged", "the aurora is up")
	eq(d.record_for(su).get("state", ""), "staged", "so is the storm damage")
	eq(spent[0], 0, "nothing is spent yet")
	var staged_after_first: int = stages[0]

	## AGED FROM `resolved_at`, NOT FROM `born`. Past the aurora's half-day
	## linger measured from its ending, and nothing else's.
	d.scan(ended + 0.49)
	eq(d.record_for(qu).get("state", ""), "staged", "half a day after it ended, the aurora is still there")
	d.scan(ended + 0.51)
	eq(d.record_for(qu).get("state", ""), "spent", "and just past its linger it is gone")
	eq(d.record_for(su).get("state", ""), "staged", "the storm damage did not")
	eq(spent[0], 1, "one incident_spent, and only one")
	ok(spent_uids.has(qu), "and it was the aurora that was spent")
	eq(int(d.record_for(qu).get("props", -1)), 0, "a spent incident has no props")
	ok(not d._nodes.has(qu), "and no nodes")
	eq(d.staged_uids(), [su], "only the storm damage is still standing")

	## A spent uid that is still sitting in the Chronicle's resolved ring must
	## never be harvested back to life. This is the loop that would restage the
	## same blood trail every 1.7 seconds for the rest of the game.
	ok(c.resolved.has(quick), "the aurora is still in the Chronicle's ring")
	var stages_before: int = stages[0]
	for i in 12:
		d.scan(ended + 0.52 + float(i) * 0.01)
	eq(d.record_for(qu).get("state", ""), "spent", "twelve more scans and it is still spent")
	eq(d.incidents.size(), 2, "and no second record was made for it")
	eq(spent[0], 1, "and incident_spent did not fire again")
	eq(stages[0], stages_before, "and it was never restaged")
	ok(stages[0] >= staged_after_first, "the staging count only ever went up")

	## The Director's own ceiling: MEMORY_DAYS past the ENDING, everything is
	## spent, even a recipe that would happily linger for exactly that long.
	d.scan(ended + IncidentDirector.MEMORY_DAYS - 0.01)
	eq(d.record_for(su).get("state", ""), "staged", "a hair inside MEMORY_DAYS it is still up")
	d.scan(ended + IncidentDirector.MEMORY_DAYS + 0.01)
	eq(d.record_for(su).get("state", ""), "spent", "past MEMORY_DAYS the storm damage is spent too")
	eq(spent[0], 2, "two spendings in all")
	eq(d.staged_uids(), [], "and nothing is physical")
	eq(d._nodes.size(), 0, "and no nodes are left behind")

	## THE STALE RING. A save loaded next to a ring of week-old resolutions must
	## read them as week-old. Before `resolved_at` this was stamped at whatever
	## moment the Director first looked, so a week of history staged itself as
	## fresh blood on the grass the instant the player loaded the game.
	## Its own Chronicle: `d` above is still watching `c`, and a record it also
	## harvested would show up in the forget arithmetic below.
	var c2 := _chron(SEED + 11)
	var pl2: Dictionary = c2.places[5]
	var p2 := _body()
	_put(p2, pl2["pos"] as Vector2)
	var d2 := _dir(c2, p2)
	var fresh_staged := [0]
	var stale_spent := [0]
	d2.incident_staged.connect(func(_r): fresh_staged[0] += 1)
	d2.incident_spent.connect(func(_r): stale_spent[0] += 1)
	var stale := _ev(c2, "wolves_at_fold", pl2, 400.0, "ewes_lost")
	c2.resolved.append(stale)
	## Seven game days after it ended, the player loads the game standing on it.
	d2.scan(float(stale["ends"]) + 7.0)
	var sr: Dictionary = d2.record_for(int(stale["uid"]))
	near(float(sr.get("resolved_at", -1.0)), float(stale["ends"]), 1e-6,
		"the stale resolution is stamped with when it actually ended")
	eq(sr.get("state", ""), "spent", "so it is spent on sight, not staged as fresh")
	eq(int(sr.get("props", -1)), 0, "with nothing built for it")
	ok(not d2._nodes.has(int(stale["uid"])), "and no nodes on the ground")
	eq(fresh_staged[0], 0, "a week-old ring stages nothing at all")
	ok(stale_spent[0] >= 1, "and reports what it aged out")

	## Forgetting is timid: while the Chronicle still remembers the uid, the
	## Director keeps the record however old it is.
	d.scan(300.0 + IncidentDirector.FORGET_DAYS + 5.0)
	eq(d.incidents.size(), 2, "a uid still in the resolved ring is never forgotten")
	## Once the ring has rolled past it, and only then, it is dropped.
	c.resolved.erase(quick)
	c.resolved.erase(slow)
	d.scan(300.0 + IncidentDirector.FORGET_DAYS + 6.0)
	eq(d.incidents.size(), 0, "a uid the Chronicle has forgotten is forgotten here too")
	eq(d._nodes.size(), 0, "with nothing left on the ground")

	d.free()
	d2.free()
	p.free()
	p2.free()
	c.free()
	c2.free()
	settle("_test_ageing ran to the end")


## ---------------------------------------------------------------------------
##  11b. the re-dress budget  (NEW-2, and the NEW-6 leak with it)
## ---------------------------------------------------------------------------
##  `STAGE_PER_SCAN` was on the staging pass alone, which left the whole point
##  of it open: `Chronicle._resolve_due` resolves EVERY event past its ending in
##  one tick, so a dozen staged incidents could re-dress in a single scan --
##  measured at 23 ms, the exact dropped frame the budget exists to prevent.
##  One budget, both doors, and a queue for what does not fit.
## ---------------------------------------------------------------------------


## A cohort of live `fire` events at one place, all staged, all about to end at
## the same instant. Returns the events.
func _fire_cohort(c: Chronicle, pl: Dictionary, d: IncidentDirector, born: float,
		ends_at: float, n: int) -> Array:
	var made: Array = []
	for i in n:
		var e := _ev(c, "fire", pl, born, "", ends_at - born)
		c.active.append(e)
		made.append(e)
	## Five a scan with the earshot grace, so three scans clears twelve.
	for i in 5:
		d.scan(born + 0.001 * float(i))
	return made


func _test_redress_budget() -> void:
	claim("_test_redress_budget ran to the end")
	var c := _chron(SEED + 41)
	var pl: Dictionary = c.places[15]
	var at: Vector2 = pl["pos"]
	var p := _body()
	_put(p, at)
	var d := _dir(c, p)

	var cohort := _fire_cohort(c, pl, d, 1000.0, 1000.5, IncidentDirector.MAX_STAGED)
	eq(d.staged_uids().size(), IncidentDirector.MAX_STAGED, "twelve fires are burning")
	var live_props := int(d.record_for(int(cohort[0]["uid"])).get("props", 0))
	ok(live_props > 0, "each with its live dressing (%d props)" % live_props)
	eq(d.get_child_count(), IncidentDirector.MAX_STAGED, "one node tree apiece, and no more")

	## THE TICK. `Chronicle._resolve_due` walks the active list and resolves
	## everything past its ending, so all twelve end in the same instant.
	for e in cohort:
		_resolve(c, e as Dictionary)
	eq(c.active.size(), 0, "the Chronicle resolved the whole cohort in one tick")

	var per_scan: Array = []
	for i in 6:
		per_scan.append(_scan_redressing(d, 1000.6 + float(i) * 0.001))
	var over := 0
	for n in per_scan:
		if int(n) > IncidentDirector.STAGE_PER_SCAN:
			over += 1
	eq(over, 0, "no scan re-dressed more than STAGE_PER_SCAN incidents (%s)" % str(per_scan))
	ok(int(per_scan[0]) < IncidentDirector.MAX_STAGED,
		"and certainly not all twelve at once, which is the dropped frame")
	var total := 0
	for n in per_scan:
		total += int(n)
	eq(total, IncidentDirector.MAX_STAGED, "but every one of the twelve was re-dressed in the end")
	ok(per_scan.count(0) >= 2, "and the queue really did drain and stop (%s)" % str(per_scan))

	## The record is right IMMEDIATELY. Only the dressing is deferred; nothing
	## a save or a rumour reads is ever allowed to lag behind the Chronicle.
	var stale_props := 0
	var wrong := 0
	for e in cohort:
		var r: Dictionary = d.record_for(int((e as Dictionary)["uid"]))
		if bool(r.get("live", true)) or String(r.get("outcome", "")).is_empty():
			wrong += 1
		if absf(float(r.get("resolved_at", -1.0)) - float((e as Dictionary)["ends"])) > 1e-6:
			wrong += 1
	eq(wrong, 0, "every record was live-false, outcomed and clocked before its props caught up")
	eq(d.get_child_count(), IncidentDirector.MAX_STAGED,
		"and the re-dress freed the old dressing rather than stacking a second one on it")
	var mismatched := 0
	for e in cohort:
		var uid := int((e as Dictionary)["uid"])
		var r: Dictionary = d.record_for(uid)
		var crows := _critters_wanted("fire", String(r["outcome"]), false)
		if int((d._nodes[uid] as Node).get_child_count()) != int(r["props"]) - crows:
			mismatched += 1
		if int(r["props"]) == live_props:
			stale_props += 1
	eq(mismatched, 0, "and every incident's nodes match the count on its record")
	eq(stale_props, 0, "with the aftermath dressing on all twelve, not the live one")

	## STRUCK BEFORE IT DRAINS. A queued re-dress is about props that no longer
	## exist, so the strike drops it and nothing rebuilds behind the player.
	var c2 := _chron(SEED + 43)
	var pl2: Dictionary = c2.places[15]
	var at2: Vector2 = pl2["pos"]
	var p2 := _body()
	_put(p2, at2)
	var d2 := _dir(c2, p2)
	var cohort2 := _fire_cohort(c2, pl2, d2, 1000.0, 1000.5, IncidentDirector.MAX_STAGED)
	for e in cohort2:
		_resolve(c2, e as Dictionary)
	var first := _scan_redressing(d2, 1000.6)
	eq(first, IncidentDirector.STAGE_PER_SCAN, "three re-dressed on the first scan")
	var queued := d2._redress_q.size()
	eq(queued, IncidentDirector.MAX_STAGED - IncidentDirector.STAGE_PER_SCAN,
		"and nine are queued for later")
	## The strike is what drops a queued re-dress, and it is asserted here on
	## `_strike_far` alone rather than through a whole scan: within one scan the
	## re-dress pass runs BEFORE the strike pass, so the scan on which the player
	## walks out of range still spends its budget on things it is about to tear
	## down -- bounded by STAGE_PER_SCAN, and asserted as such below.
	_put(p2, at2 + Vector2(6000.0, 0.0))
	d2._strike_far(_flat(Vector3(at2.x + 6000.0, 0.0, at2.y)))
	eq(d2.staged_uids().size(), 0, "striking took all twelve down")
	eq(d2._redress_q.size(), 0, "and emptied the queue with them, rather than holding it")
	eq(d2.get_child_count(), 0, "and no node trees at all")
	var after_strike := _scan_redressing(d2, 1000.61)
	eq(after_strike, 0, "so the next scan re-dresses nothing")
	eq(d2.staged_uids().size(), 0, "because there is nothing physical left to re-dress")

	## And the bound on the wasteful case: a scan that both drains and strikes
	## still cannot spend more than the budget on props it is about to free.
	var c4 := _chron(SEED + 44)
	var pl4: Dictionary = c4.places[15]
	var at4: Vector2 = pl4["pos"]
	var p4 := _body()
	_put(p4, at4)
	var d4 := _dir(c4, p4)
	var cohort4 := _fire_cohort(c4, pl4, d4, 1000.0, 1000.5, IncidentDirector.MAX_STAGED)
	for e in cohort4:
		_resolve(c4, e as Dictionary)
	eq(_scan_redressing(d4, 1000.6), IncidentDirector.STAGE_PER_SCAN, "three re-dressed")
	_put(p4, at4 + Vector2(6000.0, 0.0))
	var leaving := _scan_redressing(d4, 1000.61)
	ok(leaving <= IncidentDirector.STAGE_PER_SCAN,
		"the scan the player leaves on re-dresses at most the budget (%d)" % leaving)
	eq(d4.staged_uids().size(), 0, "and strikes everything anyway")
	eq(d4.get_child_count(), 0, "leaving nothing on the ground")
	eq(d4._redress_q.size(), 0, "and nothing queued")
	## And walking back builds the AFTERMATH, through the ordinary staging pass.
	_put(p2, at2)
	for i in 4:
		d2.scan(1000.62 + float(i) * 0.001)
	eq(d2.staged_uids().size(), IncidentDirector.MAX_STAGED, "walking back stages them again")
	var still_live := 0
	for e in cohort2:
		if int(d2.record_for(int((e as Dictionary)["uid"])).get("props", 0)) == live_props:
			still_live += 1
	eq(still_live, 0, "and every one of them came back wearing its aftermath")
	d4.free()
	p4.free()
	c4.free()

	## SPENT BEFORE IT DRAINS. Terminal beats queued: a record that aged out
	## while it was waiting for a rebuild must never get one.
	var c3 := _chron(SEED + 47)
	var pl3: Dictionary = c3.places[15]
	var at3: Vector2 = pl3["pos"]
	var p3 := _body()
	_put(p3, at3)
	var d3 := _dir(c3, p3)
	var cohort3 := _fire_cohort(c3, pl3, d3, 1000.0, 1000.5, IncidentDirector.MAX_STAGED)
	for e in cohort3:
		_resolve(c3, e as Dictionary)
	eq(_scan_redressing(d3, 1000.6), IncidentDirector.STAGE_PER_SCAN, "three re-dressed")
	ok(d3._redress_q.size() > 0, "and the rest queued (%d)" % d3._redress_q.size())
	var spent := [0]
	d3.incident_spent.connect(func(_r): spent[0] += 1)
	var late := _scan_redressing(d3, 1000.5 + IncidentKit.linger_for("fire") + 0.05)
	eq(late, 0, "a scan past their linger re-dressed none of them")
	eq(spent[0], IncidentDirector.MAX_STAGED, "it spent all twelve instead")
	eq(d3._redress_q.size(), 0, "and dropped the queue on the way")
	eq(d3.staged_uids().size(), 0, "nothing is physical")
	eq(d3.get_child_count(), 0, "and nothing is parented to the Director")
	var props_left := 0
	for e in cohort3:
		props_left += int(d3.record_for(int((e as Dictionary)["uid"])).get("props", 0))
	eq(props_left, 0, "and every spent record reports no props")
	d3.scan(1000.5 + IncidentKit.linger_for("fire") + 0.06)
	eq(d3.staged_uids().size(), 0, "and a further scan does not resurrect any of them")

	d.free()
	d2.free()
	d3.free()
	p.free()
	p2.free()
	p3.free()
	c.free()
	c2.free()
	c3.free()
	settle("_test_redress_budget ran to the end")


## ---------------------------------------------------------------------------
##  11c. what the harvest sweep is allowed to cost  (NEW-3)
## ---------------------------------------------------------------------------
##  The speculative anchor sweep runs on every scan for the whole life of every
##  active event, and `anchor_for` is not free: the shore walk is up to sixteen
##  bearings by twenty ground samples. A place/wild/shore anchor is displaced
##  from its place by a BOUNDED amount, so an event whose place is further away
##  than the reach plus that bound cannot have an anchor inside the reach and
##  does not need computing. A road anchor has no such bound -- 941 m was
##  measured -- so road is deliberately ungated.
## ---------------------------------------------------------------------------


func _test_scope_gate() -> void:
	claim("_test_scope_gate ran to the end")
	var c := _chron(SEED + 53)
	var pl: Dictionary = c.places[6]
	var at: Vector2 = pl["pos"]
	var p := _body()
	var d := _dir(c, p)
	var counter := Flat.new()
	counter.y = 12.0
	d._ground = counter
	var reach := IncidentDirector.STAGE_RADIUS * IncidentDirector.HARVEST_MULT

	## A shore event a long way off. Nothing else is in play, so every ground
	## sample this scan is the shore walk being run for it.
	var e := _ev(c, "wreck_ashore", pl, 1100.0, "", 5.0)
	c.active.append(e)
	_put(p, at + Vector2(reach + IncidentDirector.SHORE_REACH + 400.0, 0.0))
	counter.calls = 0
	d.scan(1100.05)
	eq(d.incidents.size(), 0, "a shore event that far off is not harvested")
	eq(counter.calls, 0, "and its anchor is not walked at all -- the gate caught it first")
	for i in 5:
		d.scan(1100.06 + float(i) * 0.001)
	eq(counter.calls, 0, "nor on any of the five scans after it")

	## Step inside the gate and the walk happens.
	_put(p, at + Vector2(reach + IncidentDirector.SHORE_REACH - 20.0, 0.0))
	counter.calls = 0
	d.scan(1100.1)
	ok(counter.calls > 0, "inside reach + SHORE_REACH the anchor is worked out (%d samples)" % counter.calls)

	## A WILD event uses the tighter WILD_FAR bound, so the same distance that
	## admits a shore event turns a wild one away.
	var c2 := _chron(SEED + 59)
	var pl2: Dictionary = c2.places[6]
	var at2: Vector2 = pl2["pos"]
	var p2 := _body()
	var d2 := _dir(c2, p2)
	var counter2 := Flat.new()
	counter2.y = 12.0
	d2._ground = counter2
	c2.active.append(_ev(c2, "goblin_sign", pl2, 1100.0, "", 5.0))
	_put(p2, at2 + Vector2(reach + IncidentDirector.WILD_FAR + 40.0, 0.0))
	counter2.calls = 0
	d2.scan(1100.05)
	eq(counter2.calls, 0, "a wild event past reach + WILD_FAR is gated out too")
	eq(d2.incidents.size(), 0, "and not harvested")
	_put(p2, at2 + Vector2(reach + IncidentDirector.WILD_FAR - 20.0, 0.0))
	counter2.calls = 0
	d2.scan(1100.1)
	ok(counter2.calls > 0, "and inside that bound it is worked out (%d samples)" % counter2.calls)

	## ROAD IS UNGATED, on purpose, and the memo is the evidence: `_road_point`
	## snapshots the far end for any uid it is asked about, so an entry appearing
	## for an event five hundred metres past every bounded slack is the sweep
	## having asked. This is what keeps the 941 m case in `_test_harvest_reach`
	## working, and it is the cost the comment accepts.
	var c3 := _chron(SEED + 61)
	var pl3: Dictionary = c3.places[6]
	var at3: Vector2 = pl3["pos"]
	var p3 := _body()
	var d3 := _dir(c3, p3)
	var road := _ev(c3, "bandits_road", pl3, 1100.0, "", 5.0)
	c3.active.append(road)
	_put(p3, at3 + Vector2(reach + IncidentDirector.SHORE_REACH + 500.0, 0.0))
	d3.scan(1100.05)
	eq(d3.incidents.size(), 0, "the road event is still too far to harvest")
	ok(d3._road_ends.has(int(road["uid"])),
		"but its anchor WAS worked out: road is ungated, because a road anchor has no bound")
	## And a wild event at the same distance was not, on the same Director.
	var wild := _ev(c3, "goblin_sign", pl3, 1100.0, "", 5.0)
	c3.active.append(wild)
	d3.scan(1100.06)
	eq(d3.incidents.size(), 0, "neither is harvested")
	ok(not d3._road_ends.has(int(wild["uid"])), "but only the road one was ever computed")

	d._ground = null
	d2._ground = null
	d.free()
	d2.free()
	d3.free()
	counter.free()
	counter2.free()
	p.free()
	p2.free()
	p3.free()
	c.free()
	c2.free()
	c3.free()
	settle("_test_scope_gate ran to the end")


## ---------------------------------------------------------------------------
##  12. the long event  (B1 regression)
## ---------------------------------------------------------------------------
##  `bridge_out` runs 72 to 240 game hours -- up to ten days. The ageing rule
##  used to spend any live record older than MEMORY_DAYS on the assumption that
##  no kind stays active near three days, which was simply untrue for six of
##  the thirty-four: the event was killed mid-flight and, because spent is
##  terminal, its aftermath was never allowed to exist either.
## ---------------------------------------------------------------------------


func _test_long_event() -> void:
	claim("_test_long_event ran to the end")
	var kd := ChronicleEvents.by_id("bridge_out")
	var band: Vector2 = kd.get("active", Vector2.ZERO)
	ok(band.y / 24.0 > IncidentDirector.MEMORY_DAYS,
		"bridge_out really can outlive MEMORY_DAYS (%.1f days)" % (band.y / 24.0))

	var c := _chron()
	var pl: Dictionary = c.places[12]
	var at: Vector2 = pl["pos"]
	var p := _body()
	_put(p, at)
	var d := _dir(c, p)
	var spent: Array = []
	d.incident_spent.connect(func(rec): spent.append(int(rec["uid"])))

	## Ten game days of active event, scanned every few hours the whole way.
	var e := _ev(c, "bridge_out", pl, 500.0, "", 10.0)
	c.active.append(e)
	var uid := int(e["uid"])
	d.scan(500.05)
	eq(d.record_for(uid).get("live", false), true, "the bridge is out and the event is live")
	eq(d.record_for(uid).get("state", ""), "staged", "and physical")
	for i in range(1, 41):
		d.scan(500.0 + float(i) * 0.25)
	eq(spent, [], "ten days of a still-running event spends nothing")
	eq(d.record_for(uid).get("state", ""), "staged", "and it is still standing on day ten")
	eq(d.record_for(uid).get("live", false), true, "and still live")
	ok(c.active.has(e), "because the Chronicle still has it running")

	## And when it finally does resolve, the aftermath is allowed to exist --
	## which is the half of the bug that mattered, because spent is terminal.
	_resolve(c, e)
	d.scan(510.05)
	var r: Dictionary = d.record_for(uid)
	eq(r.get("live", true), false, "it resolved on day ten")
	eq(r.get("state", ""), "staged", "and its aftermath is physical")
	ok(int(r.get("props", 0)) > 0, "with props on the ground (%d)" % int(r.get("props", 0)))
	near(float(r.get("resolved_at", -1.0)), float(e["ends"]), 1e-6, "clocked from its ending")
	eq(spent, [], "and still nothing has been spent")
	## The aftermath then ages from the ENDING, so it gets its full linger.
	d.scan(float(e["ends"]) + IncidentKit.linger_for("bridge_out") - 0.01)
	eq(d.record_for(uid).get("state", ""), "staged", "it gets its whole linger after the ending")
	d.scan(float(e["ends"]) + IncidentKit.linger_for("bridge_out") + 0.02)
	eq(d.record_for(uid).get("state", ""), "spent", "and then, properly, it is spent")
	eq(spent, [uid], "once")

	## THE ORPHAN CONTROL. A live record the Chronicle no longer has running has
	## no ending coming -- the Chronicle drops an active event outright if its
	## kind was renamed under a save -- so it must still age out at MEMORY_DAYS
	## or it would stage forever.
	## Its own Chronicle: `c` is still holding the resolved bridge above, and a
	## second Director watching it would harvest that too.
	var c2 := _chron(SEED + 13)
	var pl2: Dictionary = c2.places[12]
	var p2 := _body()
	_put(p2, pl2["pos"] as Vector2)
	var d2 := _dir(c2, p2)
	var orphaned: Array = []
	d2.incident_spent.connect(func(rec): orphaned.append(int(rec["uid"])))
	var o := _ev(c2, "bridge_out", pl2, 600.0, "", 10.0)
	c2.active.append(o)
	d2.scan(600.05)
	var ou := int(o["uid"])
	eq(d2.record_for(ou).get("live", false), true, "the orphan starts life live")
	## The Chronicle forgets it without resolving it.
	c2.active.erase(o)
	d2.scan(600.0 + IncidentDirector.MEMORY_DAYS - 0.01)
	eq(d2.record_for(ou).get("state", ""), "staged", "just inside MEMORY_DAYS it is still there")
	eq(orphaned, [], "and not yet spent")
	d2.scan(600.0 + IncidentDirector.MEMORY_DAYS + 0.01)
	eq(d2.record_for(ou).get("state", ""), "spent", "past it, an orphan is spent")
	eq(orphaned, [ou], "exactly once")
	eq(d2._nodes.has(ou), false, "and its nodes are down")

	d.free()
	d2.free()
	p.free()
	p2.free()
	c.free()
	c2.free()
	settle("_test_long_event ran to the end")


## ---------------------------------------------------------------------------
##  13. the cap on how much can be physical at once
## ---------------------------------------------------------------------------


func _test_cap() -> void:
	claim("_test_cap ran to the end")
	var c := _chron()
	var pl: Dictionary = c.places[13]
	var at: Vector2 = pl["pos"]
	var p := _body()
	_put(p, at)
	var d := _dir(c, p)

	var made: Array = []
	for i in 20:
		var e := _ev(c, "wolves_at_fold", pl, 400.0, "held")
		c.resolved.append(e)
		made.append(int(e["uid"]))

	## BUILT A FEW AT A TIME. A whole cohort in one frame is a dropped frame on
	## every fast travel, respawn and save load; three a scan spreads it over a
	## few seconds of wall clock and the nearest always arrive first.
	##
	## Every one of these twenty is inside EARSHOT of the player, so the grace
	## applies to all of them and the worst scan is five, not three. That is the
	## deliberate exemption: earshot only fires on a staged record, so a strict
	## budget means the world stays silent for three scans about a thing the
	## player is standing next to.
	var per_scan: Array = []
	for i in 6:
		per_scan.append(_scan_counting(d, 400.05 + float(i) * 0.001))
	eq(d.incidents.size(), 20, "twenty eligible aftermaths, all recorded")
	var graced := _check_budget(per_scan, "an all-in-earshot cohort")
	ok(graced > 0, "and the grace was actually spent (%s)" % str(per_scan))
	eq(per_scan[0], IncidentDirector.STAGE_PER_SCAN + IncidentDirector.EARSHOT_GRACE,
		"the first scan built the budget and the whole grace")
	eq(per_scan[1], IncidentDirector.STAGE_PER_SCAN + IncidentDirector.EARSHOT_GRACE,
		"and so did the second")
	eq(per_scan[2], IncidentDirector.MAX_STAGED - 2 * (IncidentDirector.STAGE_PER_SCAN
		+ IncidentDirector.EARSHOT_GRACE), "and the third finished the cohort")
	eq(per_scan[3], 0, "and the fourth had nothing left to build")
	eq(per_scan[4], 0, "nor the fifth")
	eq(per_scan[5], 0, "nor the sixth")
	var total := 0
	for n in per_scan:
		total += int(n)
	eq(total, IncidentDirector.MAX_STAGED, "and the cohort came to exactly the cap, never one more")
	eq(d.staged_uids().size(), IncidentDirector.MAX_STAGED, "the cap holds at twelve staged")
	eq(d._nodes.size(), IncidentDirector.MAX_STAGED, "and twelve node trees exist")

	## Nearest first. Work out by hand which twelve those should be.
	var rows: Array = []
	for uid in made:
		var r: Dictionary = d.record_for(uid)
		rows.append([_flat(r["anchor"] as Vector3).distance_to(at), uid])
	rows.sort_custom(func(x, y):
		if not is_equal_approx(float(x[0]), float(y[0])):
			return float(x[0]) < float(y[0])
		return int(x[1]) < int(y[1]))
	var want: Array = []
	for i in IncidentDirector.MAX_STAGED:
		want.append(int(rows[i][1]))
	want.sort()
	eq(d.staged_uids(), want, "the twelve staged are the twelve nearest")

	var worst_staged := 0.0
	var best_unstaged := INF
	var staged_now := d.staged_uids()
	for row in rows:
		var uid := int(row[1])
		if staged_now.has(uid):
			worst_staged = maxf(worst_staged, float(row[0]))
		else:
			best_unstaged = minf(best_unstaged, float(row[0]))
	ok(worst_staged <= best_unstaged + 1e-4,
		"nothing further away was preferred to something nearer (%.2f vs %.2f)" % [worst_staged, best_unstaged])

	var unstaged := 0
	for uid in made:
		if String(d.record_for(uid).get("state", "")) == "known":
			unstaged += 1
	eq(unstaged, 20 - IncidentDirector.MAX_STAGED, "the eight over the cap stay known, not lost")
	eq(d.staged_uids().size(), d.report()["staged"], "the report agrees with the cap")

	## A strike releases budget: walk away from everything, then back.
	_put(p, at + Vector2(4000.0, 0.0))
	d.scan(400.2)
	eq(d.staged_uids().size(), 0, "everything struck when the player left")
	eq(d._nodes.size(), 0, "and every node with it")
	eq(d.incidents.size(), 20, "and every record kept")
	_put(p, at)
	for i in 5:
		d.scan(400.3 + float(i) * 0.001)
	eq(d.staged_uids(), want, "and the same twelve come back")

	d.free()
	p.free()
	c.free()

	## ------------------------------------------------------------------------
	## PREEMPTION (SERIOUS-2). The old pass spent a slot on everything already
	## staged before it looked at a candidate, so twelve incidents at two
	## hundred metres starved one at the player's boots -- and because earshot
	## only fires on a staged record, that incident was not merely invisible,
	## it was permanently SILENT.
	## ------------------------------------------------------------------------
	var c2 := _chron()
	var far_pl: Dictionary = c2.places[20]
	var far_at: Vector2 = far_pl["pos"]
	var p2 := _body()
	var d2 := _dir(null, p2)
	var struck: Array = []
	var heard: Array = []
	d2.incident_struck.connect(func(rec): struck.append(int(rec["uid"])))
	d2.incident_heard.connect(func(rec): heard.append(int(rec["uid"])))

	## Twelve records two hundred metres out, one at the player's boots. Loaded
	## rather than harvested, so the anchors are exactly where this test wants.
	var rows2: Array = []
	for i in IncidentDirector.MAX_STAGED:
		var ang := float(i) * TAU / float(IncidentDirector.MAX_STAGED)
		rows2.append({
			"uid": 700 + i, "kind": "wolves_at_fold", "outcome": "held", "place": "Far",
			"pos": [0.0, 0.0], "born": 0.0, "resolved_at": 0.0, "live": false,
			"state": "known", "staged_at": -1.0, "heard": false,
			"anchor": [cos(ang) * 200.0, 0.0, sin(ang) * 200.0], "props": 0,
		})
	_put(p2, Vector2.ZERO)
	d2.from_dict({"v": 1, "seed": SEED, "days": 0.0, "incidents": rows2})
	## NOTHING here is inside EARSHOT, so the grace is not spendable and the
	## budget is strictly STAGE_PER_SCAN a scan. That is the control for the
	## graced cohort above: the exemption is for the thing at your boots, not a
	## general raise.
	var cold: Array = []
	for i in 6:
		cold.append(_scan_counting(d2, 0.01 * float(i)))
	var cold_graced := _check_budget(cold, "a cohort entirely out of earshot")
	eq(cold_graced, 0, "no scan exceeded STAGE_PER_SCAN when nothing was in earshot (%s)" % str(cold))
	eq(cold[0], IncidentDirector.STAGE_PER_SCAN, "the first cold scan built exactly three")
	eq(cold[3], IncidentDirector.STAGE_PER_SCAN, "and so did the fourth")
	var cold_total := 0
	for n in cold:
		cold_total += int(n)
	eq(cold_total, IncidentDirector.MAX_STAGED, "and four scans of three filled the cap exactly")
	eq(d2.staged_uids().size(), IncidentDirector.MAX_STAGED, "twelve distant incidents fill the cap")
	eq(heard.size(), 0, "and none of them is in earshot")
	eq(struck.size(), 0, "and nothing has been struck")

	## Now one arrives five metres from the player's boots.
	d2.from_dict({"v": 1, "incidents": [{
		"uid": 999, "kind": "wolves_at_fold", "outcome": "ewes_lost", "place": "Here",
		"pos": [0.0, 0.0], "born": 0.0, "resolved_at": 0.0, "live": false,
		"state": "known", "staged_at": -1.0, "heard": false,
		"anchor": [5.0, 0.0, 0.0], "props": 0,
	}]})
	eq(d2.incidents.size(), IncidentDirector.MAX_STAGED + 1, "thirteen records, twelve slots")
	d2.scan(0.1)
	eq(d2.staged_uids().size(), IncidentDirector.MAX_STAGED, "the cap still holds at twelve")
	ok(d2.staged_uids().has(999), "and the one at the player's boots is staged")
	eq(struck.size(), 1, "exactly one distant incident was preempted for it")
	ok(not d2.staged_uids().has(struck[0]), "and it really did come down")
	ok(heard.has(999), "and it was heard the same scan it was built")
	eq(d2.record_for(999).get("heard", false), true, "the latch is on the record")
	ok(int(d2.record_for(999).get("props", 0)) > 0, "with props on the ground")

	## Steady state: it does not thrash. The far twelve minus one stay put.
	var struck_before := struck.size()
	for i in 8:
		d2.scan(0.2 + float(i) * 0.01)
	eq(struck.size(), struck_before, "eight more scans preempt nothing further")
	eq(d2.staged_uids().size(), IncidentDirector.MAX_STAGED, "and the cap is still twelve")
	eq(heard.size(), 1, "and nothing is heard twice")

	d2.free()
	p2.free()
	c2.free()

	## ------------------------------------------------------------------------
	## The tiebreak, forced. Two records at EXACTLY the same distance and only
	## one slot left: the lower uid wins, every time, or the determinism test
	## is resting on whatever sort_custom felt like doing.
	## ------------------------------------------------------------------------
	var p3 := _body()
	_put(p3, Vector2.ZERO)
	var d3 := _dir(null, p3)
	var rows3: Array = []
	for i in IncidentDirector.MAX_STAGED - 1:
		rows3.append({
			"uid": 500 + i, "kind": "wolves_at_fold", "outcome": "held", "place": "X",
			"pos": [0.0, 0.0], "born": 0.0, "resolved_at": 0.0, "live": false,
			"state": "known", "staged_at": -1.0, "heard": false,
			"anchor": [10.0 + float(i), 0.0, 0.0], "props": 0,
		})
	for i in 2:
		rows3.append({
			"uid": 900 + i * 7, "kind": "wolves_at_fold", "outcome": "held", "place": "X",
			"pos": [0.0, 0.0], "born": 0.0, "resolved_at": 0.0, "live": false,
			"state": "known", "staged_at": -1.0, "heard": false,
			"anchor": [0.0, 0.0, 100.0 if i == 0 else -100.0], "props": 0,
		})
	d3.from_dict({"v": 1, "seed": SEED, "days": 0.0, "incidents": rows3})
	eq(d3.incidents.size(), IncidentDirector.MAX_STAGED + 1, "thirteen records loaded, twelve slots")
	for i in 6:
		d3.scan(float(i) * 0.01)
	eq(d3.staged_uids().size(), IncidentDirector.MAX_STAGED, "twelve of the thirteen are staged")
	ok(d3.staged_uids().has(900), "the tied pair is broken towards the lower uid")
	ok(not d3.staged_uids().has(907), "and the higher uid of the pair waits")
	var first := d3.staged_uids()
	var d4 := _dir(null, p3)
	d4.from_dict({"v": 1, "seed": SEED, "days": 0.0, "incidents": rows3})
	for i in 6:
		d4.scan(float(i) * 0.01)
	eq(d4.staged_uids(), first, "and the tiebreak is the same on a second Director")

	## ------------------------------------------------------------------------
	## NEW-8. `_stage_near` used to admit any already-staged record at any
	## distance and rely on `_strike_far` having run first to take the far ones
	## down. That is a silent dependency on pass ORDER, and the file's own
	## header says the two passes touch disjoint sets so their order cannot
	## matter. Called on its own with the player a hundred kilometres away, the
	## staging pass must build nothing and keep nothing.
	## ------------------------------------------------------------------------
	var p5 := _body()
	var d5 := _dir(null, p5)
	var staged5: Array = []
	var struck5: Array = []
	d5.incident_staged.connect(func(rec): staged5.append(int(rec["uid"])))
	d5.incident_struck.connect(func(rec): struck5.append(int(rec["uid"])))
	d5.from_dict({"v": 1, "seed": SEED, "days": 0.0, "incidents": [{
		"uid": 811, "kind": "wolves_at_fold", "outcome": "held", "place": "Near",
		"pos": [0.0, 0.0], "born": 0.0, "resolved_at": 0.0, "live": false,
		"state": "known", "staged_at": -1.0, "heard": false,
		"anchor": [1.0, 0.0, 0.0], "props": 0,
	}]})
	_put(p5, Vector2.ZERO)
	d5.scan(0.01)
	eq(d5.staged_uids(), [811], "the record stages while the player is on it")
	eq(staged5, [811], "once")
	## Now the far side of the map, and ONLY the staging pass.
	var away := Vector2(100000.0, -100000.0)
	_put(p5, away)
	d5._stage_near(away, 0.02)
	eq(d5.staged_uids(), [], "the staging pass alone took it down at a hundred kilometres")
	eq(struck5, [811], "striking it exactly once")
	eq(d5._nodes.size(), 0, "with its nodes")
	eq(staged5, [811], "and it did not stage anything out there")
	d5._stage_near(away, 0.03)
	eq(staged5, [811], "nor on a second call")
	eq(d5.staged_uids(), [], "and nothing is standing")
	eq(d5.incidents.size(), 1, "and the record is kept, as always")

	d3.free()
	d4.free()
	d5.free()
	p3.free()
	p5.free()
	settle("_test_cap ran to the end")


## ---------------------------------------------------------------------------
##  14. earshot
## ---------------------------------------------------------------------------


class Tap extends Telegraph:
	## A Telegraph that records rather than relays. The real bus walks the
	## SceneTree looking for critters, and nothing in this suite is ever in a
	## live tree -- so the bus is stood in for at the one method the Director
	## actually calls.
	var log: Array = []
	func _ring(pos: Vector3, radius: float, threat: int, source_name: String, hops: int) -> void:
		log.append({"pos": pos, "radius": radius, "threat": threat, "src": source_name, "hops": hops})


func _test_earshot() -> void:
	claim("_test_earshot ran to the end")
	var tap := Tap.new()
	Telegraph._instance = tap
	ok(Telegraph.get_bus(null) == tap, "the test bus is the bus")

	var c := _chron()
	var pl: Dictionary = c.places[17]
	var at: Vector2 = pl["pos"]
	var p := _body()
	_put(p, at)
	var d := _dir(c, p)
	var heard: Array = []
	d.incident_heard.connect(func(rec): heard.append(int(rec["uid"])))

	## A fire is a panic and rings. A murrain is silent and does not.
	var loud := _ev(c, "fire", pl, 500.0)
	var quiet := _ev(c, "murrain", pl, 500.0)
	c.active.append(loud)
	c.active.append(quiet)
	var lu := int(loud["uid"])
	var qu := int(quiet["uid"])

	d.scan(500.05)
	eq(d.staged_uids().size(), 2, "both incidents are physical")
	eq(heard.size(), 2, "and the player is standing in both of them, so both are heard")
	eq(d.record_for(lu).get("heard", false), true, "the fire latched")
	eq(d.record_for(qu).get("heard", false), true, "the murrain latched too -- it is plainly visible")
	eq(tap.log.size(), 1, "but only one of them rang the Telegraph")
	var ring: Dictionary = tap.log[0]
	eq(int(ring["threat"]), IncidentKit.threat_for("fire"), "the ring carries the recipe's live threat")
	eq(String(ring["src"]), IncidentKit.hear_for("fire"), "and the recipe's sound")
	near(float(ring["radius"]), IncidentDirector.EARSHOT, 1e-4, "and rings at earshot")
	eq((ring["pos"] as Vector3), (d.record_for(lu)["anchor"] as Vector3), "from the anchor, not the village")
	ok(d.last_note.length() > 0, "and the world had a line ready to say")
	ok(not d.last_note.contains("%s"), "with the place already in it")

	## Once per incident, EVER. Twelve more scans standing right in it.
	for i in 12:
		d.scan(500.06 + float(i) * 0.01)
	eq(heard.size(), 2, "twelve more scans in earshot and nothing was heard twice")
	eq(tap.log.size(), 1, "and the Telegraph rang once")

	## Across a strike and a restage.
	_put(p, at + Vector2(6000.0, 0.0))
	d.scan(500.3)
	eq(d.staged_uids().size(), 0, "walked away: struck")
	_put(p, at)
	d.scan(500.4)
	eq(d.staged_uids().size(), 2, "walked back: restaged")
	eq(heard.size(), 2, "and the world did not tell the same thing twice")
	eq(tap.log.size(), 1, "the Telegraph stayed quiet on the second visit")
	eq(d.record_for(lu).get("heard", false), true, "the latch survived the teardown")

	## Across a save round trip.
	var saved := d.to_dict()
	var p2 := _body()
	_put(p2, at)
	var d2 := _dir(c, p2)
	var heard2: Array = []
	d2.incident_heard.connect(func(rec): heard2.append(int(rec["uid"])))
	d2.from_dict(saved)
	eq(d2.record_for(lu).get("heard", false), true, "the latch was saved")
	d2.scan(500.5)
	eq(d2.staged_uids().size(), 2, "the loaded Director rebuilt both")
	eq(heard2.size(), 0, "and heard nothing: the latch survived the save")
	eq(tap.log.size(), 1, "and rang nothing")

	## Earshot is a radius, not a chunk boundary: staged but out of earshot is
	## staged and silent.
	var p3 := _body()
	var anchor: Vector3 = d2.record_for(lu)["anchor"]
	_put(p3, _flat(anchor) + Vector2(IncidentDirector.EARSHOT + 40.0, 0.0))
	var d3 := _dir(c, p3)
	var heard3: Array = []
	d3.incident_heard.connect(func(rec): heard3.append(int(rec["uid"])))
	d3.scan(500.6)
	ok(d3.staged_uids().has(lu), "an incident 100 m off is built")
	eq(heard3.size(), 0, "but is not heard from there")
	eq(d3.record_for(lu).get("heard", false), false, "and has not latched")
	_put(p3, _flat(anchor))
	d3.scan(500.7)
	ok(heard3.has(lu), "walk into it and it is heard")
	eq(d3.record_for(lu).get("heard", false), true, "and latches then")

	Telegraph._instance = null
	tap.free()
	d.free()
	d2.free()
	d3.free()
	p.free()
	p2.free()
	p3.free()
	c.free()
	settle("_test_earshot ran to the end")


## ---------------------------------------------------------------------------
##  15. what the aftermath is worth ringing at  (ADDENDUM B)
## ---------------------------------------------------------------------------
##  A thing in progress and the mess it left are not the same noise. Ringing
##  PANIC over three-day-old cold char is how a player learns to ignore the
##  Telegraph.
## ---------------------------------------------------------------------------


func _test_threat_after() -> void:
	claim("_test_threat_after ran to the end")
	var tap := Tap.new()
	Telegraph._instance = tap

	var c := _chron()
	var pl: Dictionary = c.places[19]
	var at: Vector2 = pl["pos"]
	var p := _body()
	_put(p, at)
	var d := _dir(c, p)
	var heard: Array = []
	d.incident_heard.connect(func(rec): heard.append(int(rec["uid"])))

	## The live fire: a panic, and it rings like one.
	var fire := _ev(c, "fire", pl, 700.0, "", 0.05)
	c.active.append(fire)
	d.scan(700.02)
	var fu := int(fire["uid"])
	eq(heard, [fu], "the fire is heard while it burns")
	eq(tap.log.size(), 1, "and it rang")
	eq(int((tap.log[0] as Dictionary)["threat"]), 3, "at PANIC")
	eq(int((tap.log[0] as Dictionary)["threat"]), IncidentKit.threat_for("fire"),
		"which is exactly the recipe's live threat")

	## The aftermath of that same fire is `threat_after: -1` -- cold char, and
	## the Telegraph has nothing to say about it. It still latches `heard`,
	## because the player has plainly seen it.
	var p2 := _body()
	_put(p2, at)
	var d2 := _dir(c, p2)
	var heard2: Array = []
	d2.incident_heard.connect(func(rec): heard2.append(int(rec["uid"])))
	_resolve(c, fire)
	tap.log.clear()
	d2.scan(700.1)
	eq(d2.record_for(fu).get("live", true), false, "the second Director sees the fire as finished")
	eq(d2.record_for(fu).get("state", ""), "staged", "and stages the char")
	eq(heard2, [fu], "and the char is still noticed")
	eq(d2.record_for(fu).get("heard", false), true, "and latched")
	eq(tap.log.size(), 0, "but it rang nothing at all")
	eq(IncidentKit.threat_after_for("fire"), -1, "because its threat_after is -1")

	## A raided hall is the other way round: still worth the watch turning out.
	## Its own Chronicle, so the fire above cannot ring into this reading.
	var c3 := _chron(SEED + 17)
	var pl3: Dictionary = c3.places[19]
	var p3 := _body()
	_put(p3, pl3["pos"] as Vector2)
	var d3 := _dir(c3, p3)
	var raid := _ev(c3, "goblin_raid", pl3, 700.0, _first_outcome("goblin_raid"))
	c3.resolved.append(raid)
	tap.log.clear()
	d3.scan(700.2)
	eq(d3.record_for(int(raid["uid"])).get("heard", false), true, "the raided hall is heard")
	eq(tap.log.size(), 1, "and rings")
	eq(int((tap.log[0] as Dictionary)["threat"]), 2, "at ALARM, days later")
	eq(int((tap.log[0] as Dictionary)["threat"]), IncidentKit.threat_after_for("goblin_raid"),
		"which is the recipe's explicit threat_after")

	## And a recipe that says nothing gets mini(threat, 1): quieter, not silent.
	var c4 := _chron(SEED + 19)
	var pl4: Dictionary = c4.places[19]
	var p4 := _body()
	_put(p4, pl4["pos"] as Vector2)
	var d4 := _dir(c4, p4)
	var fold := _ev(c4, "wolves_at_fold", pl4, 700.0, "ewes_lost")
	c4.resolved.append(fold)
	tap.log.clear()
	d4.scan(700.3)
	eq(tap.log.size(), 1, "an unset aftermath still rings")
	eq(int((tap.log[0] as Dictionary)["threat"]), mini(IncidentKit.threat_for("wolves_at_fold"), 1),
		"at mini(threat, 1)")
	ok(int((tap.log[0] as Dictionary)["threat"]) < IncidentKit.threat_for("wolves_at_fold"),
		"which is quieter than the wolves themselves were")
	eq(String((tap.log[0] as Dictionary)["src"]), IncidentKit.hear_for("wolves_at_fold"),
		"and it is still the same sound")

	Telegraph._instance = null
	tap.free()
	d.free()
	d2.free()
	d3.free()
	d4.free()
	p.free()
	p2.free()
	p3.free()
	p4.free()
	c.free()
	c3.free()
	c4.free()
	settle("_test_threat_after ran to the end")


## ---------------------------------------------------------------------------
##  16. the boundary a player actually stands on
## ---------------------------------------------------------------------------


func _test_hysteresis() -> void:
	claim("_test_hysteresis ran to the end")
	var c := _chron()
	var pl: Dictionary = c.places[21]
	var at: Vector2 = pl["pos"]
	var p := _body()
	_put(p, at)
	var d := _dir(c, p)
	var stages := [0]
	var strikes := [0]
	d.incident_staged.connect(func(_r): stages[0] += 1)
	d.incident_struck.connect(func(_r): strikes[0] += 1)

	var e := _ev(c, "mill_broken", pl, 600.0, _first_outcome("mill_broken"))
	c.resolved.append(e)
	d.scan(600.05)
	var r: Dictionary = d.record_for(int(e["uid"]))
	eq(r.get("state", ""), "staged", "the mill is built while the player is in it")
	eq(stages[0], 1, "one staging")
	eq(strikes[0], 0, "no strikes")
	var props0 := int(r["props"])
	var anchor: Vector3 = r["anchor"]

	## Park in the gap: past STAGE_RADIUS, short of STRIKE_RADIUS. This is
	## where a one-radius system thrashes a dozen meshes every frame forever.
	var mid := 0.5 * (IncidentDirector.STAGE_RADIUS + IncidentDirector.STRIKE_RADIUS)
	_put(p, _flat(anchor) + Vector2(mid, 0.0))
	ok(mid > IncidentDirector.STAGE_RADIUS and mid < IncidentDirector.STRIKE_RADIUS,
		"the parking spot is genuinely between the two radii (%.1f m)" % mid)
	for i in 20:
		d.scan(600.1 + float(i) * 0.02)
	eq(stages[0], 1, "twenty scans on the boundary and it staged no second time")
	eq(strikes[0], 0, "and was never struck")
	eq(r.get("state", ""), "staged", "it is still up")
	eq(int(r["props"]), props0, "with the props it was built with")
	eq(d._nodes.size(), 1, "and exactly one node tree")
	eq(d.incidents.size(), 1, "and one record")

	## Just inside STRIKE_RADIUS is still up; just outside is down. Once.
	_put(p, _flat(anchor) + Vector2(IncidentDirector.STRIKE_RADIUS - 1.0, 0.0))
	d.scan(600.6)
	eq(r.get("state", ""), "staged", "a metre inside the strike radius it is still up")
	eq(strikes[0], 0, "and still not struck")
	_put(p, _flat(anchor) + Vector2(IncidentDirector.STRIKE_RADIUS + 1.0, 0.0))
	d.scan(600.7)
	eq(r.get("state", ""), "known", "a metre outside it comes down")
	eq(strikes[0], 1, "struck exactly once")
	## And it does NOT come straight back up at 299 m -- the gap is one-way.
	_put(p, _flat(anchor) + Vector2(mid, 0.0))
	for i in 10:
		d.scan(600.8 + float(i) * 0.02)
	eq(r.get("state", ""), "known", "and back in the gap it stays down")
	eq(stages[0], 1, "with no restaging in the gap at all")
	eq(strikes[0], 1, "and no second strike")
	_put(p, _flat(anchor) + Vector2(IncidentDirector.STAGE_RADIUS - 1.0, 0.0))
	d.scan(601.2)
	eq(r.get("state", ""), "staged", "it takes coming back inside the stage radius")
	eq(stages[0], 2, "and only then does it build again")
	eq(stages[0] - strikes[0], d.staged_uids().size(), "and the matched pair still balances")

	d.free()
	p.free()
	c.free()
	settle("_test_hysteresis ran to the end")


## ---------------------------------------------------------------------------
##  17. save and load
## ---------------------------------------------------------------------------


func _test_save_round_trip() -> void:
	claim("_test_save_round_trip ran to the end")
	var c := _chron()
	var pl: Dictionary = c.places[2]
	var at: Vector2 = pl["pos"]
	var p := _body()
	_put(p, at)
	var d := _dir(c, p)

	var live := _ev(c, "bandits_road", pl, 700.0, "", 2.0)
	var done := _ev(c, "harvest_in", pl, 700.0, _first_outcome("harvest_in"))
	var old := _ev(c, "aurora", pl, 690.0, _first_outcome("aurora"))
	c.active.append(live)
	c.resolved.append(done)
	c.resolved.append(old)
	d.scan(700.1)
	eq(d.incidents.size(), 3, "three records to save")
	eq(String(d.record_for(int(old["uid"])).get("state", "")), "spent", "one of them is already spent")

	var saved := d.to_dict()
	eq(int(saved.get("v", 0)), 1, "the save is version 1")
	eq(int(saved.get("seed", 0)), SEED, "and carries the world seed")
	near(float(saved.get("days", -1.0)), 700.1, 1e-4, "and the day it was written")
	eq((saved.get("incidents", []) as Array).size(), 3, "and all three records")

	## VECTORS GO OUT AS ARRAYS. `JSON.stringify(Vector2(12.5, -3.25))` does not
	## emit two numbers -- it emits the STRING "(12.5, -3.25)", which matches no
	## arm of `_as_vec2`, which used to relocate every incident in a reloaded
	## world to the map origin.
	ok(JSON.parse_string(JSON.stringify(Vector2(12.5, -3.25))) is String,
		"a Vector2 does not survive JSON as a vector, which is why arrays are written")
	var row0 := (saved["incidents"] as Array)[0] as Dictionary
	ok(row0["pos"] is Array, "so to_dict writes pos as an array")
	ok(row0["anchor"] is Array, "and anchor as an array")
	eq((row0["pos"] as Array).size(), 2, "two numbers for a position")
	eq((row0["anchor"] as Array).size(), 3, "three for an anchor")
	ok(row0.has("resolved_at"), "and the aftermath clock goes in the save")

	var p2 := _body()
	_put(p2, at)
	var d2 := _dir(c, p2, 1)
	d2.from_dict(saved)
	eq(d2.world_seed, SEED, "loading restored the seed")
	near(d2._last_days, 700.1, 1e-4, "and the clock reading")
	eq(d2.incidents.size(), 3, "and every record")

	var mismatched := 0
	var key_gaps := 0
	for uid in d.incidents.keys():
		var a: Dictionary = d.record_for(int(uid))
		var b: Dictionary = d2.record_for(int(uid))
		if b.is_empty():
			mismatched += 1
			continue
		for k in REC_KEYS:
			if not b.has(k):
				key_gaps += 1
			elif a[k] != b[k]:
				mismatched += 1
				print("    round trip lost '%s': %s vs %s" % [k, str(a[k]), str(b[k])])
	eq(key_gaps, 0, "every saved record has every contract key")
	eq(mismatched, 0, "and every value came back exactly as it went in")

	var rec: Dictionary = d2.record_for(int(done["uid"]))
	ok(rec["pos"] is Vector2, "pos came back a Vector2")
	ok(rec["anchor"] is Vector3, "anchor came back a Vector3")
	eq((rec["pos"] as Vector2), at, "with the place's own coordinates")
	eq(rec.get("heard", false), d.record_for(int(done["uid"])).get("heard", false), "heard survived")
	eq(float(rec.get("resolved_at", -99.0)), float(done["ends"]), "and the aftermath clock survived")
	eq(d2.record_for(int(old["uid"])).get("state", ""), "spent", "and spent survived")
	eq(d2.record_for(int(live["uid"])).get("live", false), true, "and a live event is still live")
	eq(float(d2.record_for(int(live["uid"])).get("resolved_at", 0.0)), -1.0,
		"and a live record still has no aftermath clock")

	## A save restores records, never nodes. The first scan after a load is
	## where the scene is made to agree with the records again.
	eq(d2._nodes.size(), 0, "a fresh load has no nodes")
	d2.scan(700.2)
	eq(d2.staged_uids(), d.staged_uids(), "and the first scan rebuilds exactly what was up")
	eq(d2.report()["rows"], d.report()["rows"], "and the two Directors now report the same world")
	eq(d2.record_for(int(old["uid"])).get("state", ""), "spent", "a spent record was not rebuilt")

	## THE JSON ROUND TRIP, in full: stringify, parse, load. Every anchor has to
	## come back on the same grass or every incident in the world has moved.
	var text := JSON.stringify(d.to_dict())
	ok(text.length() > 0, "the save serialises to JSON")
	var parsed = JSON.parse_string(text)
	ok(parsed is Dictionary, "and parses back to a Dictionary")
	var p3 := _body()
	_put(p3, at)
	var d3 := _dir(c, p3, 1)
	d3.from_dict(parsed as Dictionary)
	eq(d3.incidents.size(), d.incidents.size(), "with every record")
	eq(d3.world_seed, SEED, "and the seed")
	var jmoved := 0
	var jbad := 0
	for uid in d.incidents.keys():
		var a: Dictionary = d.record_for(int(uid))
		var b: Dictionary = d3.record_for(int(uid))
		if b.is_empty():
			jbad += 1
			continue
		if not (b["pos"] is Vector2) or not (b["anchor"] is Vector3):
			jbad += 1
			continue
		if (b["anchor"] as Vector3) != (a["anchor"] as Vector3):
			jmoved += 1
		if (b["pos"] as Vector2) != (a["pos"] as Vector2):
			jmoved += 1
	eq(jbad, 0, "every record came back as vectors, not strings")
	eq(jmoved, 0, "and not one incident in the world moved through JSON")
	var janch := 0
	for uid in d3.incidents.keys():
		if (d3.record_for(int(uid))["anchor"] as Vector3) == Vector3.ZERO:
			janch += 1
	eq(janch, 0, "and nothing relocated to the map origin")
	d3.scan(700.25)
	eq(d3.report()["rows"], d.report()["rows"], "and a JSON-loaded Director reports the same world")

	## THE LEGACY SAVE. Every save on disk predates this file and has no
	## incidents key at all; loading one must not wipe a running world.
	d2.from_dict({"v": 1, "seed": SEED, "days": 701.0})
	eq(d2.incidents.size(), 3, "a save with no incidents key merges, it does not replace")
	near(d2._last_days, 701.0, 1e-4, "though it does bring the clock forward")
	d2.from_dict({})
	eq(d2.incidents.size(), 3, "an empty save changes nothing at all")
	d2.from_dict({"v": 2, "incidents": []})
	eq(d2.incidents.size(), 3, "a save from a future version is refused rather than obeyed")
	## A PRESENT-BUT-BROKEN payload is not a legacy save. It must change
	## nothing -- not the records, and not the clock on the way to refusing it.
	var days_before := d2._last_days
	var seed_before := d2.world_seed
	d2.from_dict({"v": 1, "seed": 12345, "days": 999.0, "incidents": "not an array"})
	eq(d2.incidents.size(), 3, "a malformed incidents key does not wipe anything")
	near(d2._last_days, days_before, 1e-6, "and does not wind the clock on its way out")
	eq(d2.world_seed, seed_before, "and does not reseed the world either")

	## A record with no resolved_at -- which is what every save written before
	## the key existed carries -- falls back to `born` rather than to nothing.
	var p4 := _body()
	## The legacy record's anchor is the origin, so that is where the player is.
	_put(p4, Vector2.ZERO)
	var d4 := _dir(null, p4)
	d4.from_dict({"v": 1, "incidents": [{
		"uid": 321, "kind": "aurora", "outcome": _first_outcome("aurora"), "place": "Old",
		"pos": [0.0, 0.0], "born": 10.0, "live": false, "state": "known",
		"staged_at": -1.0, "heard": false, "anchor": [0.0, 0.0, 0.0], "props": 0,
	}]})
	eq(float(d4.record_for(321).get("resolved_at", 0.0)), -1.0,
		"a legacy record loads with no aftermath clock")
	d4.scan(10.1)
	eq(d4.record_for(321).get("state", ""), "staged", "and is aged from born instead")
	d4.scan(10.0 + IncidentKit.linger_for("aurora") + 0.02)
	eq(d4.record_for(321).get("state", ""), "spent", "spending exactly one linger after it was born")

	## NEW-5. A row carrying a `resolved_at` in the far future would never age:
	## `now - resolved_at` is negative forever, so the aftermath is immortal and
	## the record is never spent and never forgotten. `from_dict` clamps it to
	## the day the save says it was written.
	var p5 := _body()
	_put(p5, Vector2.ZERO)
	var d5 := _dir(null, p5)
	d5.from_dict({"v": 1, "days": 800.0, "incidents": [{
		"uid": 777, "kind": "aurora", "outcome": _first_outcome("aurora"), "place": "Forever",
		"pos": [0.0, 0.0], "born": 800.0, "resolved_at": 1e18, "live": false,
		"state": "known", "staged_at": -1.0, "heard": false, "anchor": [0.0, 0.0, 0.0], "props": 0,
	}]})
	ok(float(d5.record_for(777).get("resolved_at", 0.0)) <= 800.0 + 1e-6,
		"a resolved_at from the far future is clamped to the save's own day (%s)"
		% str(d5.record_for(777).get("resolved_at", 0.0)))
	d5.scan(800.05)
	eq(d5.record_for(777).get("state", ""), "staged", "and the record behaves normally")
	d5.scan(800.0 + IncidentKit.linger_for("aurora") + 0.02)
	eq(d5.record_for(777).get("state", ""), "spent", "and ages out on time rather than never")

	## A partial save merges over the top: the uid in it is replaced, the
	## others are left standing.
	var one := {"v": 1, "incidents": [{
		"uid": int(done["uid"]), "kind": "harvest_in", "outcome": _first_outcome("harvest_in"),
		"place": "Elsewhere", "pos": [1.0, 2.0], "born": 705.0, "resolved_at": 705.0,
		"live": false, "state": "known", "staged_at": -1.0, "heard": true,
		"anchor": [3.0, 4.0, 5.0], "props": 0,
	}]}
	d2.from_dict(one)
	eq(d2.incidents.size(), 3, "a one-record save still leaves the other two")
	eq(String(d2.record_for(int(done["uid"])).get("place", "")), "Elsewhere", "and overwrites the one it names")
	eq((d2.record_for(int(done["uid"]))["anchor"] as Vector3), Vector3(3.0, 4.0, 5.0), "anchor and all")
	eq(d2._nodes.has(int(done["uid"])), false, "and takes its nodes down with it")

	## Vectors that arrive as Vector2/Vector3 -- a var_to_bytes save -- still
	## read as vectors, because both formats have to work.
	d2.from_dict({"v": 1, "incidents": [{
		"uid": 4242, "kind": "fair", "outcome": _first_outcome("fair"), "place": "J",
		"pos": Vector2(11.0, 22.0), "born": 700.0, "resolved_at": 700.0, "live": false,
		"state": "known", "staged_at": -1.0, "heard": false,
		"anchor": Vector3(1.0, 2.0, 3.0), "props": 0,
	}]})
	eq((d2.record_for(4242)["pos"] as Vector2), Vector2(11.0, 22.0), "a binary pos is read as a Vector2")
	eq((d2.record_for(4242)["anchor"] as Vector3), Vector3(1.0, 2.0, 3.0), "a binary anchor as a Vector3")
	## And rubbish in a row is dropped, not crashed on.
	d2.from_dict({"v": 1, "incidents": [7, "nonsense", {"uid": 0}, {"uid": -3}]})
	eq(d2.incidents.size(), 4, "junk rows and uid 0 are dropped without taking the save with them")
	d2.from_dict({"v": 1, "incidents": [{"uid": 99, "state": "wandering"}]})
	eq(d2.record_for(99).get("state", ""), "known", "and an unknown state is cleaned to known")

	d.free()
	d2.free()
	d3.free()
	d4.free()
	d5.free()
	p.free()
	p2.free()
	p3.free()
	p4.free()
	p5.free()
	c.free()
	settle("_test_save_round_trip ran to the end")


## ---------------------------------------------------------------------------
##  18. the roster moves under us  (S1 regression)
## ---------------------------------------------------------------------------
##  `chronicle.places` is MUTABLE. The fort builder appends to it at runtime and
##  `Chronicle.from_dict` overlays a save's roster on top of the live one, so
##  "the nearest other place" is not a stable answer -- and a road anchor is
##  drawn from it. Measured, one moved 748 m when a place was appended. An
##  incident does not get to relocate because a village was founded elsewhere.
## ---------------------------------------------------------------------------


func _test_roster_drift() -> void:
	claim("_test_roster_drift ran to the end")
	var c := _chron()
	var home: Dictionary = c.places[9]
	var at: Vector2 = home["pos"]
	var p := _body()
	var d := _dir(c, p)

	var e := _ev(c, "caravan_in", home, 800.0, "", 3.0)
	c.active.append(e)
	var uid := int(e["uid"])
	## Stand on the anchor so the incident is staged and heard from the start.
	var predicted := d.anchor_for({"uid": uid, "kind": "caravan_in", "pos": at})
	_put(p, _flat(predicted))
	d.scan(800.05)
	var r: Dictionary = d.record_for(uid)
	eq(r.get("state", ""), "staged", "the caravan is on the road and physical")
	var anchor0: Vector3 = r["anchor"]
	eq(anchor0, predicted, "and its anchor is where anchor_for said it would be")
	var digest0 := _digest_node(d._nodes[uid] as Node)
	var props0 := int(r["props"])

	## A village is founded a hundred metres away -- nearer than anything else
	## on the map, so "the nearest other place" now has a different answer.
	var before_end := c.places.size()
	c.places.append({
		"name": "New Fort", "pos": at + Vector2(100.0, 0.0), "y": 0.0, "rank": 0,
		"region": "BANGOR", "mood": 0.5, "stores": 0.5, "alarm": 0.0, "watch": 0.3,
		"rumours": [],
	})
	eq(c.places.size(), before_end + 1, "the roster really did grow under the Director")
	var naive := c.places[before_end] as Dictionary
	ok((naive["pos"] as Vector2).distance_to(at) < 200.0,
		"and the new place really is the nearest other one now")

	## Rescan: nothing about this incident may move.
	d.scan(800.06)
	eq((r["anchor"] as Vector3), anchor0, "a rescan did not move the anchor")
	eq(r.get("state", ""), "staged", "and it is still standing")
	eq(int(r["props"]), props0, "with the same props")
	eq(_digest_node(d._nodes[uid] as Node), digest0, "and every box on the same grass")
	eq(d.anchor_for({"uid": uid, "kind": "caravan_in", "pos": at}), anchor0,
		"and anchor_for still answers with the snapshotted road")

	## Strike and restage across the change.
	_put(p, _flat(anchor0) + Vector2(5000.0, 0.0))
	d.scan(800.1)
	eq(r.get("state", ""), "known", "walked away")
	_put(p, _flat(anchor0))
	d.scan(800.15)
	eq(r.get("state", ""), "staged", "walked back")
	eq((r["anchor"] as Vector3), anchor0, "and the anchor is byte-identical across the roster change")
	eq(_digest_node(d._nodes[uid] as Node), digest0, "and so is every prop under it")

	## And the live -> resolved transition, which is the other place an anchor
	## used to be recomputed.
	_resolve(c, e)
	d.scan(800.2)
	eq(r.get("live", true), false, "the caravan arrived")
	eq((r["anchor"] as Vector3), anchor0, "and the anchor did not move when it did")
	eq(r.get("state", ""), "staged", "and it is still physical")
	ok(int(r["props"]) > 0, "with its aftermath on the ground")

	## The road far end is remembered per uid, and dropped with the record.
	ok(d._road_ends.has(uid), "the road's far end is snapshotted for this uid")
	d.free()
	p.free()
	c.free()
	settle("_test_roster_drift ran to the end")


## ---------------------------------------------------------------------------
##  19. the clock -- the section the Chronicle suite did not have
## ---------------------------------------------------------------------------
##  A suite that never bound the game's clock let the Chronicle run a whole
##  season out of step with the sky on 2026-09-06. The Director ages every
##  record against a day number, so the question "whose day number" is the
##  same question again, and it is answered here by a clock the test winds
##  rather than by a float the test hands to scan().
## ---------------------------------------------------------------------------


class FakeClock extends Node:
	var day := 0.0
	var hour := 0.0


func _test_clock_binding() -> void:
	claim("_test_clock_binding ran to the end")
	var clock := FakeClock.new()
	clock.day = 30.0
	clock.hour = 19.7
	root.add_child(clock)

	var p := _body()
	_put(p, Vector2.ZERO)
	var d := _dir(null, p)
	d.clock = clock
	near(d._now_days(), 30.0 + 19.7 / 24.0, 1e-4, "the Director reads the sky's calendar")

	## One record, aged only ever against the clock. from_dict is the only way
	## in here: this Director has no Chronicle at all.
	var born := 30.0 + 19.7 / 24.0
	d.from_dict({"v": 1, "seed": SEED, "days": born, "incidents": [{
		"uid": 31, "kind": "storm_damage", "outcome": _first_outcome("storm_damage"),
		"place": "Sky", "pos": [0.0, 0.0], "born": born, "resolved_at": born, "live": false,
		"state": "known", "staged_at": -1.0, "heard": false,
		"anchor": [0.0, 0.0, 0.0], "props": 0,
	}]})
	var spent := [0]
	var staged := [0]
	d.incident_spent.connect(func(_r): spent[0] += 1)
	d.incident_staged.connect(func(_r): staged[0] += 1)

	## A DIRECT _process call. The first one always scans -- the interval
	## starts at zero -- and it must scan at the clock's day, not at zero.
	eq(d._last_days, born, "the loaded save set the last-known day")
	d._process(0.016)
	near(d._last_days, 30.0 + 19.7 / 24.0, 1e-4, "_process scanned at the clock's day")
	near(d._scan_t, IncidentDirector.SCAN_SECONDS, 1e-6, "and armed the next scan")
	eq(staged[0], 1, "and staged the incident the player is standing in")
	eq(spent[0], 0, "and spent nothing")

	## The interval is real: a frame inside it does no work.
	clock.day = 90.0
	d._process(0.1)
	near(d._last_days, 30.0 + 19.7 / 24.0, 1e-4, "a frame inside the interval does not scan")
	eq(spent[0], 0, "so a sixty-day jump is not noticed yet")
	near(d._scan_t, IncidentDirector.SCAN_SECONDS - 0.1, 1e-6, "it only counts down")

	## And when the interval elapses, the Director ages against the SKY's new
	## day, not against the last number anybody handed scan().
	d._process(IncidentDirector.SCAN_SECONDS)
	near(d._last_days, 90.0 + 19.7 / 24.0, 1e-4, "the next scan adopts the wound-forward clock")
	eq(spent[0], 1, "and sixty days of sky spends the aftermath")
	eq(d.record_for(31).get("state", ""), "spent", "the record says so")
	eq(d._nodes.size(), 0, "and its nodes are down")

	## Disabled, the Director is inert however the clock moves.
	clock.day = 200.0
	d.enabled = false
	var was := d._last_days
	d._process(10.0)
	eq(d._last_days, was, "a disabled Director does not scan")
	d.enabled = true
	d._process(10.0)
	near(d._last_days, 200.0 + 19.7 / 24.0, 1e-4, "and picks the clock straight back up")

	## TIME ONLY GOES FORWARD. `World.sleep_at_bed` winds the sky BACKWARDS --
	## sleeping to dawn from 20:00 is a sixteen-hour step back down the hour
	## hand -- and a day number that goes backwards un-ages every record in the
	## world and puts `staged_at` in the future.
	var high := d._last_days
	clock.day = 120.0
	clock.hour = 4.0
	d._process(IncidentDirector.SCAN_SECONDS)
	ok(d._now_days() >= high - 1e-6, "a clock wound backwards does not wind the Director back")
	near(d._last_days, high, 1e-4, "the last day stands as the floor")

	## The Chronicle's clock outranks the sky whenever there is one: every
	## `born` the Director ages against is a reading of THAT clock.
	var c := _chron()
	c.advance(24.0 * 4.0)
	var d2 := _dir(c, p)
	d2.clock = clock
	near(d2._now_days(), c.days, 1e-6, "with a Chronicle bound, its day wins over the sky's")
	ok(absf(d2._now_days() - (clock.day + clock.hour / 24.0)) > 100.0,
		"and the two really are far apart, so that was a choice and not a coincidence")
	d2._process(0.016)
	near(d2._last_days, c.days, 1e-6, "and _process scans at the Chronicle's day")

	## A Chronicle that nothing is driving sits at day zero forever, which is
	## the silent failure the fallback exists for: a bound sky still carries
	## the world forward.
	var still := _chron(SEED + 5)
	eq(still.days, 0.0, "an un-advanced Chronicle is at day zero")
	var d5 := _dir(still, p)
	d5.clock = clock
	near(d5._now_days(), clock.day + clock.hour / 24.0, 1e-4,
		"a Chronicle that has never been advanced is not a clock, so the sky is used")

	## No clock and no Chronicle: the last day handed in is the floor.
	var d3 := _dir(null, p)
	d3.scan(12.5)
	near(d3._now_days(), 12.5, 1e-6, "with neither, the last known day is the answer")
	d3._process(5.0)
	near(d3._last_days, 12.5, 1e-6, "and _process does not invent one")

	d.free()
	d2.free()
	d3.free()
	d5.free()
	p.free()
	clock.free()
	c.free()
	still.free()
	settle("_test_clock_binding ran to the end")


## ---------------------------------------------------------------------------
##  20. with nothing bound at all
## ---------------------------------------------------------------------------


class BadGround extends Node:
	var mode := 0
	func _surface_y(_p: Vector3) -> float:
		return NAN if mode == 0 else INF


func _test_null_safety() -> void:
	claim("_test_null_safety ran to the end")
	## No chronicle, no player, no Telegraph, no ground, no wildlife, not even
	## a tree. Everything below is the headless case the contract promises.
	ok(Telegraph.get_bus(null) == null, "there is no Telegraph bus in this section")

	var d := IncidentDirector.new()
	d.scan(0.0)
	d.scan(1.0)
	d.scan(1000.0)
	eq(d.incidents.size(), 0, "a Director with nothing bound records nothing")
	eq(d.staged_uids(), [], "and stages nothing")
	eq(d._nodes.size(), 0, "and builds nothing")
	eq(int(d.report()["total"]), 0, "and reports an empty world")
	eq(int(d.report()["nodes"]), 0, "with no nodes in it")
	eq((d.report()["rows"] as Array), [], "and no rows")
	eq(d.record_for(1), {}, "an unknown uid is an empty record, not a crash")
	eq(d.to_dict()["incidents"], [], "and it saves an empty list")
	near(d._last_days, 1000.0, 1e-6, "though it still knows what day it is")

	## bind_world against every shape of nothing.
	d.bind_world(null)
	var bare := Node.new()
	d.bind_world(bare)
	ok(d.chronicle == null, "binding a world with no Chronicle leaves it null")
	ok(d.player == null, "and no player leaves that null too")
	d.scan(1001.0)
	eq(d.incidents.size(), 0, "and scanning after a null bind is still quiet")

	## Records loaded into a Director with nothing bound still keep house:
	## they stage, they are heard, they age, they save.
	var born := 1001.0
	d.from_dict({"v": 1, "seed": SEED, "days": born, "incidents": [{
		"uid": 61, "kind": "wolves_at_fold", "outcome": "held", "place": "Nowhere",
		"pos": [0.0, 0.0], "born": born, "resolved_at": born, "live": false,
		"state": "known", "staged_at": -1.0, "heard": false, "anchor": [0.0, 0.0, 0.0], "props": 0,
	}]})
	var heard := [0]
	d.incident_heard.connect(func(_r): heard[0] += 1)
	## No player means the player is at the origin, which is where this is.
	d.scan(born + 0.1)
	eq(d.record_for(61).get("state", ""), "staged", "a record stages with no player bound")
	ok(int(d.record_for(61).get("props", 0)) > 0, "and builds real props with no terrain")
	eq(heard[0], 1, "and is heard with no Telegraph on the bus")
	eq(d.record_for(61).get("heard", false), true, "and latches all the same")
	near((d.record_for(61)["anchor"] as Vector3).y, 0.0, 1e-6, "with no ground provider it sits at y = 0")
	eq(d.get_child_count(), 1, "one node tree, parented to the Director itself")

	d.scan(born + IncidentDirector.MEMORY_DAYS + 0.1)
	eq(d.record_for(61).get("state", ""), "spent", "and ages out with nothing bound")
	eq(d._nodes.size(), 0, "freeing its nodes on the way")
	eq(d.get_child_count(), 0, "and leaving nothing parented behind")
	eq(d.incidents.size(), 1, "with no Chronicle, nothing is ever forgotten")
	d.scan(born + IncidentDirector.FORGET_DAYS + 50.0)
	eq(d.incidents.size(), 1, "not even fifty days later")

	## A ground provider that answers with nonsense is treated as no provider.
	var bad := BadGround.new()
	d._ground = bad
	var a := d.anchor_for({"uid": 61, "kind": "wolves_at_fold", "pos": Vector2.ZERO})
	near(a.y, 0.0, 1e-6, "a NaN ground height is read as y = 0")
	bad.mode = 1
	near(d.anchor_for({"uid": 61, "kind": "wolves_at_fold", "pos": Vector2.ZERO}).y, 0.0, 1e-6,
		"and so is an infinite one")
	## A shore incident on a nonsense heightfield reads every sample as zero,
	## which is at-or-below the waterline, so it takes the very first step and
	## backs off -- it must still land somewhere finite and repeatable.
	var sa := d.anchor_for({"uid": 61, "kind": "wreck_ashore", "pos": Vector2.ZERO})
	ok(is_finite(sa.x) and is_finite(sa.y) and is_finite(sa.z),
		"a shore walk over a nonsense heightfield still lands somewhere finite")
	eq(sa, d.anchor_for({"uid": 61, "kind": "wreck_ashore", "pos": Vector2.ZERO}),
		"and lands there again")
	d._ground = null

	## A wildlife director that cannot spawn is not a crash either.
	d._wildlife = bare
	d.scan(born + IncidentDirector.FORGET_DAYS + 51.0)
	eq(d.incidents.size(), 1, "a wildlife director with no spawn_one is simply not used")
	eq(d._critters.size(), 0, "and nothing was tracked for it")

	d.free()
	bare.free()
	bad.free()
	settle("_test_null_safety ran to the end")


## ---------------------------------------------------------------------------
##  21. how far the Director can actually hear the Chronicle  (B3 regression)
## ---------------------------------------------------------------------------
##  `events_near` filters on the event's PLACE. Staging is judged on the
##  ANCHOR, which is somewhere else: a wild anchor is up to 140 m out and a
##  road anchor is halfway to the next village -- the critic measured one 941 m
##  from its own place. An incident can be at the player's boots with its place
##  four hundred metres behind the harvest ring.
## ---------------------------------------------------------------------------


func _test_harvest_reach() -> void:
	claim("_test_harvest_reach ran to the end")
	var c := _chron()
	var p := _body()
	var d := _dir(c, p)
	var reach := IncidentDirector.STAGE_RADIUS * IncidentDirector.HARVEST_MULT

	## THE ROAD CASE, which is the common one: seven road kinds, and roughly a
	## fifth of the map's places have a road arm longer than the harvest ring.
	var road_uid := -1
	var road_place: Dictionary = {}
	var road_anchor := Vector3.ZERO
	for i in c.places.size():
		var pl := c.places[i] as Dictionary
		var at: Vector2 = pl["pos"]
		var a := d.anchor_for({"uid": 3000 + i, "kind": "bandits_road", "pos": at})
		if _flat(a).distance_to(at) > reach + 50.0:
			road_uid = 3000 + i
			road_place = pl
			road_anchor = a
			break
	ok(road_uid > 0, "the map has a road anchor further from its place than the harvest ring")
	if road_uid > 0:
		var at: Vector2 = road_place["pos"]
		ok(_flat(road_anchor).distance_to(at) > reach,
			"that road incident is %.0f m from its own place" % _flat(road_anchor).distance_to(at))
		## Wind the Chronicle's counter to that uid -- still a uid it handed
		## out, still unique, still never reused -- and fire the event.
		c._uid = road_uid
		var e := _ev(c, "bandits_road", road_place, 850.0, "", 3.0)
		eq(int(e["uid"]), road_uid, "the event carries the uid the anchor was worked out for")
		c.active.append(e)
		_put(p, _flat(road_anchor))
		var heard: Array = []
		d.incident_heard.connect(func(rec): heard.append(int(rec["uid"])))
		d.scan(850.05)
		eq(d.incidents.size(), 1, "an incident at the player's boots was harvested")
		## `.get` rather than `[]`: if the harvest above regressed, the record is
		## empty, and a subscript on it would abort this whole section and take
		## the rest of its assertions quietly with it.
		var r: Dictionary = d.record_for(road_uid)
		eq(r.get("anchor", Vector3.ZERO), road_anchor, "at the anchor the sweep predicted")
		ok(at.distance_to(_flat(road_anchor)) > reach,
			"even though its place is well outside events_near's ring")
		eq(r.get("state", ""), "staged", "and it was staged")
		ok(heard.has(road_uid), "and heard, which is the only way the contract lets it be found")
		ok(int(r.get("props", 0)) > 0, "with props on the ground")

	## THE WILD CASE. A wild anchor is up to WILD_FAR out, and
	## STAGE_RADIUS * HARVEST_MULT (352 m) is less than
	## STAGE_RADIUS + WILD_FAR (360 m), so the ring pass alone leaves a band it
	## cannot see. The anchor sweep is what closes it.
	ok(reach < IncidentDirector.STAGE_RADIUS + IncidentDirector.WILD_FAR,
		"the ring alone cannot reach every wild anchor (%.0f < %.0f)"
		% [reach, IncidentDirector.STAGE_RADIUS + IncidentDirector.WILD_FAR])
	var c2 := _chron(SEED + 3)
	var p2 := _body()
	var d2 := _dir(c2, p2)
	var pl2: Dictionary = c2.places[11]
	var at2: Vector2 = pl2["pos"]
	var want_arm := IncidentDirector.STAGE_RADIUS * (IncidentDirector.HARVEST_MULT - 1.0) + 5.0
	var pick := -1
	for u in range(int(c2._uid), int(c2._uid) + 4000):
		var probe := d2.anchor_for({"uid": u, "kind": "goblin_sign", "pos": at2})
		if (_flat(probe) - at2).length() >= want_arm:
			pick = u
			break
	ok(pick > 0, "there is a uid whose wild anchor reaches far enough out to test this")
	if pick > 0:
		c2._uid = pick
		var e2 := _ev(c2, "goblin_sign", pl2, 800.0, "", 3.0)
		c2.active.append(e2)
		var anchor := d2.anchor_for({"uid": int(e2["uid"]), "kind": "goblin_sign", "pos": at2})
		var arm := _flat(anchor) - at2
		ok(arm.length() >= want_arm,
			"the test event is anchored well out from its place (%.1f m)" % arm.length())
		var stand := at2 + arm.normalized() * (reach + 1.0)
		_put(p2, stand)
		ok(at2.distance_to(stand) > reach,
			"the place is outside the harvest ring (%.1f m)" % at2.distance_to(stand))
		ok(_flat(anchor).distance_to(stand) < IncidentDirector.STAGE_RADIUS,
			"but the incident itself is inside the stage radius (%.1f m)" % _flat(anchor).distance_to(stand))
		d2.scan(800.05)
		eq(d2.incidents.size(), 1, "an incident the player could walk into was harvested")
		ok(d2.staged_uids().has(int(e2["uid"])), "and staged")

	## And the sweep does not over-harvest: an event whose place AND anchor are
	## both far away is still none of the Director's business.
	var c3 := _chron(SEED + 4)
	var p3 := _body()
	_put(p3, Vector2(500000.0, 500000.0))
	var d3 := _dir(c3, p3)
	var far_pl: Dictionary = c3.places[0]
	c3.active.append(_ev(c3, "bandits_road", far_pl, 800.0, "", 3.0))
	c3.active.append(_ev(c3, "goblin_sign", far_pl, 800.0, "", 3.0))
	d3.scan(800.05)
	eq(d3.incidents.size(), 0, "an event nowhere near the player is still not harvested")

	d.free()
	d2.free()
	d3.free()
	p.free()
	p2.free()
	p3.free()
	c.free()
	c2.free()
	c3.free()
	settle("_test_harvest_reach ran to the end")


## ---------------------------------------------------------------------------
##  22. what a scan costs  (S4 / S5 regression)
## ---------------------------------------------------------------------------
##  `Time.get_ticks_usec` is used for TIMING and never for logic: nothing below
##  branches on it, and no number the Director records is downstream of it.
## ---------------------------------------------------------------------------


func _test_cost() -> void:
	claim("_test_cost ran to the end")
	var c := _chron()
	c.advance(24.0 * 60.0)
	var p := _body()
	var d := _dir(c, p)
	## Sixty days of Chronicle, read from the far side of the map so nothing is
	## near enough to build: this is the steady state, which is the state the
	## Director is in for essentially the whole game.
	_put(p, Vector2(400000.0, -400000.0))
	for i in 8:
		d.scan(c.days + float(i) * 0.001)
	ok(d.incidents.size() >= 40, "the resolved ring gave us a real workload (%d records)" % d.incidents.size())
	eq(d.staged_uids().size(), 0, "and none of it is physical from out here")

	var worst := 0.0
	var total := 0.0
	for i in 20:
		var t0 := Time.get_ticks_usec()
		d.scan(c.days + 1.0 + float(i) * 0.0001)
		var dt := float(Time.get_ticks_usec() - t0)
		total += dt
		worst = maxf(worst, dt)
	var avg := total / 20.0
	ok(avg < SCAN_BUDGET_USEC,
		"a steady-state scan over %d records averages %.0f us (budget %.0f)"
		% [d.incidents.size(), avg, SCAN_BUDGET_USEC])
	ok(worst < SCAN_BUDGET_USEC * 3.0,
		"and the worst of twenty is %.0f us" % worst)

	## And the build budget holds however big the cohort wanted to be: walking
	## into the middle of sixty days of history builds three a scan, not sixty.
	var pl: Dictionary = c.places[13]
	var at: Vector2 = pl["pos"]
	for i in 24:
		c.resolved.append(_ev(c, "wolves_at_fold", pl, c.days, "held"))
	var p2 := _body()
	_put(p2, at)
	var d2 := _dir(c, p2)
	var per_scan: Array = []
	for i in 8:
		per_scan.append(_scan_counting(d2, c.days + 0.001 * float(i)))
	_check_budget(per_scan, "walking into sixty days of history")
	eq(d2.staged_uids().size(), IncidentDirector.MAX_STAGED, "and the cohort filled up anyway")
	var sum := 0
	for n in per_scan:
		sum += int(n)
	eq(sum, IncidentDirector.MAX_STAGED, "building exactly the cap in total, never one more")

	d.free()
	d2.free()
	p.free()
	p2.free()
	c.free()
	settle("_test_cost ran to the end")


## ---------------------------------------------------------------------------
##  23. the animal that was culled behind our back  (ADDENDUM D)
## ---------------------------------------------------------------------------
##  `WildlifeDirector._cull` frees incident critters on its own budget, with no
##  notice, and the Director's own header accepts that: "every touch of
##  `_critters` is guarded by `is_instance_valid`". This section is LAST in the
##  run because it currently throws inside `_free_nodes`, and a GDScript
##  runtime error takes the rest of its function with it.
## ---------------------------------------------------------------------------


func _test_critter_cull() -> void:
	claim("_test_critter_cull ran to the end")
	var c := _chron(SEED + 23)
	var pl: Dictionary = c.places[8]
	var at: Vector2 = pl["pos"]
	var p := _body()
	_put(p, at)
	var d := _dir(c, p)
	var w := Wild.new()
	d._wildlife = w
	## Held rather than freed inline: if the scan below throws, this function
	## never reaches its own cleanup, and `_finish` does it instead.
	_to_free.append(c)
	_to_free.append(p)
	_to_free.append(d)
	_to_free.append(w)

	var e := _ev(c, "deer_yard", pl, 950.0)
	c.active.append(e)
	d.scan(950.05)
	var uid := int(e["uid"])
	eq(d.record_for(uid).get("state", ""), "staged", "the deer yard is up")
	var mine: Array = (d._critters.get(uid, []) as Array).duplicate()
	ok(mine.size() >= 2, "with animals in it (%d)" % mine.size())

	w.cull(mine[0])
	w.cull(mine[1])
	ok(not is_instance_valid(mine[0]) and not is_instance_valid(mine[1]),
		"the wildlife director culled two behind the Director's back")
	ok(d._critters.has(uid), "and the Director is still holding the dead references")

	## A scan that touches nothing of theirs is fine.
	d.scan(950.1)
	eq(d.record_for(uid).get("state", ""), "staged", "a scan that does not free them is unbothered")

	## AND NOW THE STRIKE, which walks `_critters` and frees what is left.
	var struck: Array = []
	d.incident_struck.connect(func(rec): struck.append(int(rec["uid"])))
	_put(p, at + Vector2(6000.0, 0.0))
	claim("striking an incident whose critters were culled does not throw")
	d.scan(950.15)
	settle("striking an incident whose critters were culled does not throw")

	eq(struck, [uid], "and the strike emitted incident_struck as it always does")
	eq(d.record_for(uid).get("state", ""), "known", "and put the record back to known")
	eq(d._nodes.has(uid), false, "with the props gone")
	eq(d._critters.has(uid), false, "and the tracking cleared")
	var alive := 0
	for n in mine:
		if is_instance_valid(n):
			alive += 1
	eq(alive, 0, "and the animals that were still alive freed with it")

	## And it comes back cleanly afterwards.
	_put(p, at)
	d.scan(950.2)
	eq(d.record_for(uid).get("state", ""), "staged", "and the incident restages afterwards")
	ok((d._critters.get(uid, []) as Array).size() >= 2, "with a fresh set of animals")
	settle("_test_critter_cull ran to the end")


## ---------------------------------------------------------------------------


func _finish() -> void:
	for what in _claims:
		_fail += 1
		print("  FAIL: %s  (the call never returned -- the section was aborted)" % String(what))
	_claims.clear()
	for n in _to_free:
		if n is Node and is_instance_valid(n):
			(n as Node).free()
	_to_free.clear()
	print("IncidentTests: %d passed, %d failed (%d assertions)" % [_pass, _fail, _pass + _fail])
	if _pass + _fail < MIN_ASSERTIONS:
		print("  LOST A SECTION: only %d assertions ran (floor %d)" % [_pass + _fail, MIN_ASSERTIONS])
		_fail += 1
	quit(1 if _fail > 0 else 0)
