class_name Drowned
extends Node3D

## ===========================================================================
## THE DROWNED — what reaches up under a night swimmer in deep water.
##
## Not an animal and not in the wildlife dex: an EVENT with a body. World's
## _drowned_tick decides when (night, deep, far from shore, never Peaceful,
## long cooldown); this node does the rest --
##
##   RISE   2.2 s. A pale pair of arms comes up out of the dark under you,
##          bubbles ahead of them, the groan. You can still get away: it is
##          slow, and a dash's i-frames slip the grab like any jaw.
##   HOLD   The hands close on your ankles (Player.creature_grab -- the same
##          hold the bear's jaw uses, so guard timing and the parry work).
##          The anchor it holds you at sinks: eyes under in a second, then
##          down, and your breath is the clock. STRUGGLE_NEED presses of
##          Space or the attack button break the grip (each press also drags
##          you a hand's breadth back up); after HOLD_MAX seconds it loses
##          you on its own and you surface with whatever air you had left.
##   SINK   It lets go and goes back down. Gone.
##
## It never leaves the water and never has hit points -- you do not fight the
## Drowned, you get out of the lake. Every quantity that touches the player
## goes through the Player's own grab API, so nothing here can strand a state.
## ===========================================================================

const RISE_SECONDS := 2.2
const HOLD_MAX := 9.0
const STRUGGLE_NEED := 8
const PULL_RATE := 0.55            ## m/s the hold point sinks
const PULL_MAX := 1.6              ## the eyes never go deeper than this under the surface
const GRIP_DAMAGE := 6.0           ## the clamp itself
const COLD_PER_S := 1.2            ## ...and the cold, while it holds
const SKIN := Color(0.56, 0.62, 0.55)
const NAIL := Color(0.30, 0.32, 0.26)
const EYE := Color(0.25, 0.85, 0.45)

var dying := false                 ## Player._update_grabbed lets go when this flips
var phase := ""                    ## "" | "rise" | "hold" | "sink"
var _t := 0.0
var _target: Node3D = null
var _surface_y := 0.0
var _anchor := Vector3.ZERO
var _struggle := 0
var _arms: Array[Node3D] = []
var _head: Node3D = null
var _rig: Node3D = null
var _cold_acc := 0.0


func rise_under(who: Node3D) -> void:
	_target = who
	var wy: float = Overworld.water_y(who.global_position)
	_surface_y = wy if wy != Overworld.NO_WATER else who.global_position.y + 1.0
	global_position = Vector3(who.global_position.x, _surface_y - 4.0, who.global_position.z)
	_build_rig()
	phase = "rise"
	_t = 0.0
	WaterAudio.play(self, "drowned_rise", global_position)
	WaterAudio.play(self, "bubbles", global_position + Vector3.UP * 2.0, -3.0)


## ------------------------------------------------------------- the body --
func _build_rig() -> void:
	_rig = Node3D.new()
	add_child(_rig)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = SKIN
	skin.roughness = 1.0
	var nail := StandardMaterial3D.new()
	nail.albedo_color = NAIL
	nail.roughness = 1.0
	var eye := StandardMaterial3D.new()
	eye.albedo_color = EYE
	eye.emission_enabled = true
	eye.emission = EYE
	eye.emission_energy_multiplier = 1.6
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(0.22 * side, 0.0, 0.0)
		_rig.add_child(arm)
		_box(arm, Vector3(0.09, 0.62, 0.09), Vector3(0.0, 0.31, 0.0), skin)      # forearm
		var hand := _box(arm, Vector3(0.11, 0.05, 0.16), Vector3(0.0, 0.64, 0.02), skin)
		for f in range(4):
			_box(hand, Vector3(0.018, 0.02, 0.09), Vector3(-0.04 + 0.027 * float(f), 0.0, 0.12), skin)
			_box(hand, Vector3(0.016, 0.01, 0.025), Vector3(-0.04 + 0.027 * float(f), 0.0, 0.17), nail)
		_arms.append(arm)
	_head = Node3D.new()
	_head.position = Vector3(0.0, -0.55, 0.0)
	_rig.add_child(_head)
	_box(_head, Vector3(0.22, 0.26, 0.24), Vector3.ZERO, skin)
	_box(_head, Vector3(0.04, 0.03, 0.02), Vector3(-0.06, 0.03, 0.12), eye)
	_box(_head, Vector3(0.04, 0.03, 0.02), Vector3(0.06, 0.03, 0.12), eye)
	_box(_head, Vector3(0.30, 0.34, 0.20), Vector3(0.0, -0.32, -0.02), skin)     # shoulders, fading down


func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## --------------------------------------------------------------- the act --
func _process(delta: float) -> void:
	_t += delta
	if _target == null or not is_instance_valid(_target):
		_finish()
		return
	match phase:
		"rise":
			## come up under the swimmer, wherever they have paddled to
			var tp: Vector3 = _target.global_position
			var u := clampf(_t / RISE_SECONDS, 0.0, 1.0)
			var y := lerpf(_surface_y - 4.0, tp.y - 0.35, u * u)
			global_position = Vector3(lerpf(global_position.x, tp.x, delta * 3.0), y,
				lerpf(global_position.z, tp.z, delta * 3.0))
			_sway(delta, 1.0)
			if u >= 1.0:
				_try_grab()
		"hold":
			var g: Variant = _target.get("grabbed_by") if "grabbed_by" in _target else null
			if g != self:
				## slipped it (dash), parried it, or the Player dropped the hold
				_let_go(false)
				return
			## the hold point sinks, and every struggle wins a little back
			_anchor.y = maxf(_anchor.y - PULL_RATE * delta, _surface_y - (_eye_of() + PULL_MAX))
			_anchor.y = maxf(_anchor.y, Overworld.ground_y(_anchor) + 0.3)   ## never through the bed
			global_position = _anchor - Vector3(0.0, 0.75, 0.0)
			_sway(delta, 2.4)
			_cold_acc += COLD_PER_S * delta
			if _cold_acc >= 1.0 and _target.has_method("take_damage"):
				_target.take_damage(floorf(_cold_acc), global_position, false, Vector3.INF, self)
				_cold_acc -= floorf(_cold_acc)
			if _struggle >= STRUGGLE_NEED:
				_let_go(true)
			elif _t > HOLD_MAX:
				_let_go(false)
		"sink":
			global_position.y -= 1.4 * delta
			_sway(delta, 0.6)
			if _t > 2.5:
				_finish()
		_:
			pass


func _sway(_delta: float, rate: float) -> void:
	var s := sin(_t * 2.1 * rate)
	for i in range(_arms.size()):
		var a := _arms[i]
		var side := -1.0 if i == 0 else 1.0
		a.rotation_degrees.z = side * (8.0 + 6.0 * s)
		a.rotation_degrees.x = 10.0 * sin(_t * 1.7 * rate + float(i))
	if _head != null:
		_head.rotation_degrees.y = 12.0 * sin(_t * 0.9)


func _try_grab() -> void:
	if not _target.has_method("creature_grab"):
		_start_sink()
		return
	## it can only take a swimmer -- if they got out, it sinks back
	var swimming: bool = bool(_target.get("swimming")) if "swimming" in _target else false
	if not swimming:
		_start_sink()
		return
	var res: String = _target.creature_grab(self, GRIP_DAMAGE)
	if res != "grabbed":
		_start_sink()
		return
	phase = "hold"
	_t = 0.0
	_struggle = 0
	_anchor = _target.global_position
	_anchor.y = _surface_y - (_eye_of() - 0.15)   ## eyes at the surface; under within the second
	WaterAudio.play(self, "drowned_grip", global_position)
	if _target.has_method("_add_log_msg"):
		_target.call("_add_log_msg", "Something has your ankle!", Color(0.55, 0.95, 0.65))


## Player._update_grabbed: where to hold the body this frame.
func grab_anchor() -> Dictionary:
	return {"pos": _anchor}


## Player._update_grabbed: the longest this holder is allowed to keep you.
func hold_seconds() -> float:
	return HOLD_MAX + 0.5


## Player._update_grabbed: Space / attack pressed while held.
func struggled() -> void:
	if phase != "hold":
		return
	_struggle += 1
	_anchor.y = minf(_anchor.y + 0.32, _surface_y - (_eye_of() - 0.35))
	WaterAudio.play(self, "swim_stroke_%d" % (1 + _struggle % 3), global_position + Vector3.UP, -2.0)
	if _struggle == STRUGGLE_NEED - 3 and _target.has_method("_add_log_msg"):
		_target.call("_add_log_msg", "Its grip is slipping --", Color(0.75, 0.95, 0.80))


func _eye_of() -> float:
	if _target != null and is_instance_valid(_target) and "_eye_h" in _target:
		return float(_target.get("_eye_h"))
	return 1.6


func struggles_left() -> int:
	return maxi(0, STRUGGLE_NEED - _struggle)


func _let_go(broken: bool) -> void:
	if _target != null and is_instance_valid(_target) and "grabbed_by" in _target \
			and _target.get("grabbed_by") == self and _target.has_method("grab_release"):
		_target.grab_release(Vector3.ZERO)
	if _target != null and is_instance_valid(_target) and _target.has_method("_add_log_msg"):
		_target.call("_add_log_msg", "You kick free of it" if broken else "It lets go, and sinks",
			Color(0.70, 0.90, 1.0))
	_start_sink()


func _start_sink() -> void:
	dying = true
	phase = "sink"
	_t = 0.0
	WaterAudio.play(self, "bubbles", global_position, -4.0)


func _finish() -> void:
	dying = true
	queue_free()
