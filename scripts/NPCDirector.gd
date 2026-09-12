class_name NPCDirector
extends Node
## ===========================================================================
## Who the people are, where they are, and which of them have a body right
## now. One per world (group "npc_director"), booted from World._ready after
## the player exists: `NPCDirector.boot(self)`.
##
## A person is a RECORD (a dictionary in NPC.to_dict's shape) that lives as
## long as the world does and goes into the save; a BODY (an NPC node) exists
## only while the player is within STAGE_R of where the record says the
## person is. Walking away unstages the body back into its record; coming
## back stages it again — at the spot its SCHEDULE says it should be by now,
## not where you last saw it, because a night passed and people go home.
##
## Names come from here (old New England given names, Maine surnames). The
## camp at the spawn gets three people on day one so there is someone to
## talk to; the K menu's "Villager" row spawns a stranger who is adopted
## into a record the first time he thinks.
## ===========================================================================

const STAGE_R := 120.0
const UNSTAGE_R := 160.0
const TICK := 0.5
const RESTAGE_HOURS := 0.5     ## away longer than this and the schedule places the body

const GIVEN_M := ["Ezra", "Silas", "Asa", "Eli", "Jonas", "Amos", "Enoch", "Barnabas", "Obadiah", "Zeb",
	"Cyrus", "Josiah", "Hiram", "Levi", "Nathaniel", "Thaddeus", "Ephraim", "Jedediah", "Caleb", "Rufus"]
const GIVEN_F := ["Abigail", "Hannah", "Mercy", "Patience", "Temperance", "Prudence", "Thankful", "Susannah",
	"Dorcas", "Keziah", "Lydia", "Tabitha", "Hepzibah", "Mehitable", "Rhoda", "Zilpah", "Eunice", "Jerusha", "Olive", "Bathsheba"]
const SURNAMES := ["Libby", "Goodwin", "Merrill", "Tibbetts", "Sawyer", "Ricker", "Hussey", "Chadbourne",
	"Wentworth", "Tuttle", "Bragdon", "Foss", "Whitney", "Small", "Leighton", "Dunning", "Skillings", "Coombs",
	"Perkins", "Littlefield", "Moody", "Hutchins", "Spinney", "Emery", "Hodgdon", "Varney", "Stackpole",
	"Pettengill", "Osgood", "Cummings", "Stinson", "Grindle", "Haskell", "Bickford", "Whitten", "Pinkham"]
const JOBS := ["villager", "crofter", "woodcutter", "fisher", "guard", "merchant", "priest"]

var records: Dictionary = {}     ## id -> record
var bodies: Dictionary = {}      ## id -> NPC
var props: Array = []            ## benches and the like we placed
var crimes := 0                  ## people the player has killed
var world: Node = null
var _t := 0.0
var _next_id := 1
var _rng := RandomNumberGenerator.new()


## ------------------------------------------------------------- boot -------

static func boot(world_node: Node) -> NPCDirector:
	## Idempotent. Creates the director, hangs it under the world, seeds the
	## camp on a fresh world, and gives the player its focus.
	var tree := world_node.get_tree()
	var existing: Node = tree.get_first_node_in_group("npc_director") if tree != null else null
	if existing is NPCDirector:
		return existing
	var d := NPCDirector.new()
	d.name = "NPCDirector"
	d.world = world_node
	world_node.add_child(d)
	if d.records.is_empty():
		d.seed_camp()
	d.attach_focus()
	return d


static func state_of(world_node: Node) -> Dictionary:
	## World.save_state(): d["npcs"] = NPCDirector.state_of(self)
	var d := _find(world_node)
	return d.to_dict() if d != null else {}


static func restore(world_node: Node, state: Dictionary) -> void:
	## World.apply_state(): NPCDirector.restore(self, d.get("npcs", {}))
	var d := _find(world_node)
	if d == null:
		d = boot(world_node)
	if state.is_empty():
		return
	d.from_dict(state)


static func _find(world_node: Node) -> NPCDirector:
	var tree := world_node.get_tree()
	if tree == null:
		return null
	var n: Node = tree.get_first_node_in_group("npc_director")
	return n as NPCDirector


func _ready() -> void:
	add_to_group("npc_director")
	_rng.seed = 20260911
	if world == null:
		world = get_parent()


func attach_focus() -> void:
	var pl := _player()
	if pl != null:
		NPCFocus.attach(pl)


func _player() -> Node3D:
	var t := get_tree()
	if t == null:
		return null
	return t.get_first_node_in_group("player") as Node3D


## ------------------------------------------------------------- names ------

static func random_name(rng: RandomNumberGenerator, sex: String) -> String:
	var given: Array = GIVEN_F if sex == "f" else GIVEN_M
	return "%s %s" % [String(given[rng.randi() % given.size()]), String(SURNAMES[rng.randi() % SURNAMES.size()])]


static func random_personality(rng: RandomNumberGenerator) -> String:
	return String(NPCDialogue.PERSONALITIES[rng.randi() % NPCDialogue.PERSONALITIES.size()])


static func courage_for(job: String, rng: RandomNumberGenerator) -> float:
	match job:
		"guard":
			return rng.randf_range(0.8, 1.0)
		"woodcutter":
			return rng.randf_range(0.45, 0.85)
		"priest", "merchant":
			return rng.randf_range(0.1, 0.4)
		_:
			return rng.randf_range(0.2, 0.7)


## ------------------------------------------------------------- make -------

func make(job := "villager", npc_name := "", sex := "", personality := "") -> NPC:
	## A person with an identity, not yet in the tree. Give it places and
	## add it to the world; it adopts itself into a record on its first tick.
	var n := NPC.new()
	n.job = job if JOBS.has(job) else "villager"
	n.sex = sex if sex != "" else ("f" if _rng.randf() < 0.45 else "m")
	n.npc_name = npc_name if npc_name != "" else random_name(_rng, n.sex)
	n.personality = personality if personality != "" else random_personality(_rng)
	n.courage = courage_for(n.job, _rng)
	return n


func adopt(npc: NPC) -> String:
	## A body that has no record (the K menu's Villager, a scripted spawn):
	## name the nameless, and file it.
	if npc == null:
		return ""
	if npc.record_id != "" and records.has(npc.record_id):
		bodies[npc.record_id] = npc
		return npc.record_id
	if npc.npc_name == "":
		npc.npc_name = random_name(_rng, npc.sex)
	var id := "npc_%03d" % _next_id
	_next_id += 1
	npc.record_id = id
	records[id] = npc.to_dict()
	bodies[id] = npc
	return id


func place(npc: NPC, at: Vector3) -> NPC:
	## Add a made person to the world at a spot (ground-snapped) and file it.
	if npc == null or world == null:
		return npc
	world.add_child(npc)
	npc.global_position = _ground(at)
	if npc.anchor == Vector3.ZERO:
		npc.anchor = npc.global_position
	adopt(npc)
	return npc


func _ground(at: Vector3) -> Vector3:
	## The floor under a spot, if there is one to find.
	var w3 := (world as Node3D).get_world_3d() if world is Node3D else null
	if w3 == null:
		return at
	var space := w3.direct_space_state
	if space == null:
		return at
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 60.0, at + Vector3.DOWN * 60.0)
	q.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return at
	return (hit["position"] as Vector3) + Vector3.UP * 0.05


## ------------------------------------------------------------- the camp ---

func seed_camp() -> void:
	## Three people at the spawn clearing on a fresh world: someone cutting,
	## someone keeping the camp, someone keeping watch.
	var c := Vector3.ZERO
	var cutter := make("woodcutter", "Silas Pettengill", "m", "gruff")
	cutter.anchor = c + Vector3(7.0, 0.0, -4.0)
	cutter.work = c + Vector3(9.5, 0.0, -6.5)
	cutter.work_yaw = atan2(-1.0, 1.0)
	cutter.seat = c + Vector3(3.0, 0.0, 5.0)
	cutter.home = c + Vector3(6.0, 0.0, 2.0)
	cutter.home_kind = "bed"
	_seed_one(cutter, cutter.anchor)

	var keeper := make("villager", "Hannah Tibbetts", "f", "friendly")
	keeper.anchor = c + Vector3(-4.0, 0.0, 3.0)
	keeper.work = c + Vector3(-3.0, 0.0, 1.5)
	keeper.work_yaw = atan2(1.0, 0.5)
	keeper.seat = c + Vector3(3.0, 0.0, 5.0)
	keeper.home = c + Vector3(-6.0, 0.0, 5.0)
	keeper.home_kind = "bed"
	keeper.disposition = 15.0
	_seed_one(keeper, keeper.anchor)

	var watch := make("guard", "Amos Chadbourne", "m", "dour")
	watch.anchor = c + Vector3(0.0, 0.0, 11.0)
	watch.work = c + Vector3(0.0, 0.0, 12.0)
	watch.work_yaw = PI
	_seed_one(watch, watch.anchor)

	_make_bench(c + Vector3(3.0, 0.0, 5.0), 0.35)


func _seed_one(npc: NPC, at: Vector3) -> void:
	if world != null:
		place(npc, at)
	else:
		adopt(npc)


func _make_bench(at: Vector3, yaw: float) -> Node3D:
	## A log to sit on: a solid box the sit pose was measured against
	## (seat_h 0.45), so nobody sits in mid-air.
	var b := StaticBody3D.new()
	b.name = "Bench"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.4, 0.45, 0.42)
	cs.shape = bs
	cs.position = Vector3(0, 0.225, 0)
	b.add_child(cs)
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	m.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.26, 0.16)
	m.material_override = mat
	m.position = cs.position
	b.add_child(m)
	if world != null:
		world.add_child(b)
		b.global_position = _ground(at)
		b.rotation.y = yaw
	props.append(b)
	return b


## ------------------------------------------------------------- streaming --

func _physics_process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = TICK
	stream()


func stream() -> void:
	var pl := _player()
	if pl == null:
		return
	var ppos := pl.global_position
	for id in records.keys():
		var rec: Dictionary = records[id]
		if bool(rec.get("dead", false)):
			continue
		if bodies.has(id):
			var body = bodies[id]
			if body == null or not is_instance_valid(body):
				bodies.erase(id)
				continue
			if (body as NPC).global_position.distance_to(ppos) > UNSTAGE_R:
				unstage(id)
		else:
			var at := NPC._v3_in(rec.get("pos"), Vector3.INF)
			if at == Vector3.INF:
				at = NPC._v3_in(rec.get("anchor"), Vector3.ZERO)
			if at.distance_to(ppos) < STAGE_R:
				stage(id)


func stage(id: String) -> NPC:
	if not records.has(id) or bodies.has(id) or world == null:
		return null
	var rec: Dictionary = records[id]
	var n := NPC.new()
	n.apply_dict(rec)
	n.record_id = id
	var at := NPC._v3_in(rec.get("pos"), Vector3.INF)
	if at == Vector3.INF:
		at = NPC._v3_in(rec.get("anchor"), Vector3.ZERO)
	## Away a while: people moved on. Place the body where the schedule
	## says it is now, not where the player last saw it.
	var away := absf(_hour() - float(rec.get("unstaged_hour", _hour())))
	if rec.has("unstaged_hour") and away > RESTAGE_HOURS:
		var spot := n.expected_spot(_hour())
		if spot != Vector3.INF:
			at = spot
	world.add_child(n)
	n.global_position = _ground(at)
	bodies[id] = n
	return n


func unstage(id: String) -> void:
	if not bodies.has(id):
		return
	var body = bodies[id]
	if body != null and is_instance_valid(body):
		var rec: Dictionary = records[id]
		var snap: Dictionary = (body as NPC).to_dict()
		for k in snap.keys():
			rec[k] = snap[k]
		rec["id"] = id
		rec["unstaged_hour"] = _hour()
		if (body as NPC).indoors and (body as NPC).home != Vector3.INF:
			rec["pos"] = NPC._v3_out((body as NPC).home)
		(body as NPC).queue_free()
	bodies.erase(id)


func _hour() -> float:
	var t := get_tree()
	var w: Node = t.get_first_node_in_group("world") if t != null else world
	if w != null and w.has_method("daynight"):
		var dn: Object = w.call("daynight")
		if dn != null and "hour" in dn:
			return float(dn.get("hour")) + 24.0 * floorf(float(dn.get("day")) if "day" in dn else 0.0)
	return 12.0


func on_npc_died(npc: NPC, by_player := false) -> void:
	if npc == null:
		return
	var id := npc.record_id
	if id != "" and records.has(id):
		var rec: Dictionary = records[id]
		rec["dead"] = true
		rec["pos"] = NPC._v3_out(npc.global_position)
	if by_player:
		crimes += 1
	bodies.erase(id)


## ------------------------------------------------------------- save -------

func to_dict() -> Dictionary:
	## Live bodies are folded into their records first, so the save holds
	## what the world holds.
	for id in bodies.keys():
		var body = bodies[id]
		if body != null and is_instance_valid(body) and records.has(id):
			var rec: Dictionary = records[id]
			var snap: Dictionary = (body as NPC).to_dict()
			for k in snap.keys():
				rec[k] = snap[k]
			rec["id"] = id
	return {"records": records.duplicate(true), "crimes": crimes, "next_id": _next_id}


func from_dict(d: Dictionary) -> void:
	for id in bodies.keys():
		var body = bodies[id]
		if body != null and is_instance_valid(body):
			(body as NPC).queue_free()
	bodies.clear()
	var recs = d.get("records", {})
	records = (recs as Dictionary).duplicate(true) if recs is Dictionary else {}
	crimes = int(d.get("crimes", 0))
	_next_id = maxi(int(d.get("next_id", 1)), records.size() + 1)
	_t = 0.0   ## re-stage on the next tick


func census() -> Dictionary:
	var dead := 0
	var alive := 0
	for id in records.keys():
		if bool((records[id] as Dictionary).get("dead", false)):
			dead += 1
		else:
			alive += 1
	return {"records": records.size(), "alive": alive, "dead": dead, "staged": bodies.size(), "crimes": crimes}


func report() -> String:
	var c := census()
	var lines: Array = ["NPCs: %d (%d alive, %d dead), %d staged, %d crimes" % [c["records"], c["alive"], c["dead"], c["staged"], c["crimes"]]]
	for id in records.keys():
		var rec: Dictionary = records[id]
		var body = bodies.get(id, null)
		var where := "unstaged"
		if body != null and is_instance_valid(body):
			where = "%s @ %s" % [(body as NPC).mode_name(), str((body as NPC).global_position.round())]
		lines.append("  %s  %-22s %-10s %-9s disp %+.0f  %s" % [id, String(rec.get("name", "?")), String(rec.get("job", "?")),
			String(rec.get("personality", "?")), float(rec.get("disposition", 0.0)), where])
	return "\n".join(lines)
