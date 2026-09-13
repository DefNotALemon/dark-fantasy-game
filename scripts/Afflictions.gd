class_name Afflictions
extends Node
## ============================================================================
## AFFLICTIONS — status effects ON THE PLAYER, dealt by creatures.
##
## Born with the slimes (scripts/Slime.gd, 2026-09-13): the ember slime's
## burn, the venom slime's poison, the tar slime's gum, the rime slime's
## chill, the jolt slime's shock, the blue slime's soak. Anything that wants
## to leave something ticking on the player goes through here, so the next
## creature with a bite that lingers adds one `match` arm, not a new system.
##
## One node, attached LAZILY as a child of the player the first time anything
## is applied (Afflictions.on(player)), ticking on the physics step. Timed
## effects live in `active` {kind: {t, power}}; refreshing keeps the longer
## clock and the stronger power, never stacks. Everything the node does to
## the player is DUCK-TYPED (`"x" in player`), so it works on the real
## Player, the LabPlayer of the test suites, and anything else with the
## right names:
##   take_damage(amount, from, strong, throw, attacker)  burn / poison ticks
##   status_speed_mult                                   gummed / chill slow
##   exposure.warmth / exposure.wet                      chill drain / soak
##   stamina, hitstun_timer                              shock
##   swimming                                            water puts a burn out
##   _add_log_msg(text, colour)                          one line per effect
## ============================================================================

const TICK := 0.45           ## damage-over-time cadence (matches Enemy's burn)
const KINDS := ["burn", "poison", "gummed", "chill"]
const LOG_LINES := {
	"burn": ["You're burning!", Color(1.0, 0.55, 0.20)],
	"poison": ["Venom in the wound.", Color(0.75, 0.45, 1.0)],
	"gummed": ["Gummed up — you can barely move.", Color(0.75, 0.55, 0.35)],
	"chill": ["The cold goes straight through you.", Color(0.70, 0.90, 1.0)],
}

var active := {}             ## kind -> {"t": seconds left, "power": float}
var _tick := {}              ## kind -> seconds to the next damage tick
var _player: Node = null
var damage_dealt := 0.0      ## total DoT dealt (the tests read it)
var ticks := 0


## ------------------------------------------------------------ entry -----

static func on(player: Node) -> Afflictions:
	## The player's affliction node, made on first use.
	if player == null or not is_instance_valid(player):
		return null
	var existing := player.get_node_or_null("Afflictions")
	if existing is Afflictions:
		return existing as Afflictions
	var a := Afflictions.new()
	a.name = "Afflictions"
	a._player = player
	player.add_child(a)
	return a


static func apply(player: Node, kind: String, seconds: float, power: float) -> void:
	var a := on(player)
	if a != null:
		a.add(kind, seconds, power)


static func shock(player: Node, stun: float, stamina: float) -> void:
	## Instant: legs lock for a beat, and the wind goes out of you.
	if player == null:
		return
	if "hitstun_timer" in player:
		player.set("hitstun_timer", maxf(float(player.get("hitstun_timer")), stun))
	if "stamina" in player:
		player.set("stamina", maxf(0.0, float(player.get("stamina")) - stamina))
	if "stamina_delay" in player:
		player.set("stamina_delay", maxf(float(player.get("stamina_delay")), 1.2))
	_say(player, "Shocked!", Color(1.0, 1.0, 0.55))


static func soak(player: Node, wet: float) -> void:
	## Instant: you are wet (Exposure counts it) — and no longer on fire.
	if player == null:
		return
	var ex = player.get("exposure") if "exposure" in player else null
	if ex != null and "wet" in ex:
		ex.set("wet", clampf(float(ex.get("wet")) + wet, 0.0, 1.0))
	var a := on(player)
	if a != null and a.active.has("burn"):
		a.clear("burn")
		_say(player, "Soaked — the fire's out.", Color(0.55, 0.80, 1.0))
	else:
		_say(player, "Soaked through.", Color(0.55, 0.80, 1.0))


static func drain_warmth(player: Node, amount: float) -> void:
	if player == null:
		return
	var ex = player.get("exposure") if "exposure" in player else null
	if ex != null and "warmth" in ex:
		ex.set("warmth", maxf(0.0, float(ex.get("warmth")) - amount))


static func _say(player: Node, text: String, col: Color) -> void:
	if player != null and player.has_method("_add_log_msg"):
		player.call("_add_log_msg", text, col)


## ------------------------------------------------------------ state -----

func add(kind: String, seconds: float, power: float) -> void:
	if not (kind in KINDS):
		return
	var fresh := not active.has(kind)
	if fresh:
		active[kind] = {"t": seconds, "power": power}
		_tick[kind] = TICK * 0.5   ## the first tick lands soon, not a full beat later
		if LOG_LINES.has(kind):
			var l: Array = LOG_LINES[kind]
			_say(_player, String(l[0]), l[1])
	else:
		var d: Dictionary = active[kind]
		d["t"] = maxf(float(d["t"]), seconds)
		d["power"] = maxf(float(d["power"]), power)
	_push_speed()


func has(kind: String) -> bool:
	return active.has(kind)


func clear(kind: String) -> void:
	active.erase(kind)
	_tick.erase(kind)
	_push_speed()


func clear_all() -> void:
	active.clear()
	_tick.clear()
	_push_speed()


func speed_mult() -> float:
	## The slows multiply: gummed AND chilled is worse than either.
	var m := 1.0
	if active.has("gummed"):
		m *= float(active["gummed"]["power"])
	if active.has("chill"):
		m *= float(active["chill"]["power"])
	return m


func _push_speed() -> void:
	if _player != null and is_instance_valid(_player) and "status_speed_mult" in _player:
		_player.set("status_speed_mult", speed_mult())


## ------------------------------------------------------------- tick -----

func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if active.is_empty():
		return
	step(delta)


func step(delta: float) -> void:
	## One step of every clock. Public so a headless suite can drive it
	## without waiting on real physics frames.
	## Water puts a fire out — a burning player who goes under is not burning.
	if active.has("burn") and "swimming" in _player and bool(_player.get("swimming")):
		clear("burn")
	var gone: Array = []
	for kind in active.keys():
		var d: Dictionary = active[kind]
		d["t"] = float(d["t"]) - delta
		if kind == "burn" or kind == "poison":
			_tick[kind] = float(_tick.get(kind, TICK)) - delta
			if float(_tick[kind]) <= 0.0:
				_tick[kind] = TICK
				_hurt(float(d["power"]) * TICK, kind)
		if float(d["t"]) <= 0.0:
			gone.append(kind)
	for kind in gone:
		active.erase(kind)
		_tick.erase(kind)
	if not gone.is_empty():
		_push_speed()


func _hurt(amount: float, kind: String) -> void:
	## The world's damage, not a creature's: no attacker, full price in every
	## mode (Player.take_damage's rule for fire and falls).
	damage_dealt += amount
	ticks += 1
	if _player.has_method("take_damage"):
		_player.call("take_damage", amount, Vector3.INF, false, Vector3.INF, null)
	if kind == "burn":
		_embers()


func _embers() -> void:
	## Two little embers off the player's body per tick (Enemy._shed_embers'
	## look, so a burning player and a burning goblin match).
	if not (_player is Node3D):
		return
	var p := _player as Node3D
	var parent := p.get_parent()
	if parent == null:
		return
	for _i in range(2):
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * randf_range(0.05, 0.09)
		m.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.25, 0.08, 0.02)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.45, 0.10).lerp(Color(1.0, 0.7, 0.25), randf())
		mat.emission_energy_multiplier = 2.4
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.material_override = mat
		parent.add_child(m)
		m.global_position = p.global_position + Vector3(randf_range(-0.3, 0.3), randf_range(0.5, 1.5), randf_range(-0.3, 0.3))
		var tw := m.create_tween()
		tw.set_parallel(true)
		tw.tween_property(m, "position", m.position + Vector3(randf_range(-0.3, 0.3),
			randf_range(0.5, 1.0), randf_range(-0.3, 0.3)), 0.5)
		tw.tween_property(m, "scale", Vector3.ONE * 0.05, 0.5)
		tw.chain().tween_callback(m.queue_free)
