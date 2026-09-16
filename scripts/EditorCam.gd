class_name EditorCam
extends Camera3D

## ===========================================================================
## THE SPECTATOR CAMERA — scripts/EditorCam.gd
##
## A camera with no body. While the map editor is open THIS is the eye: it
## lifts out of the player's head at the exact transform the player was
## looking from, and flies wherever you want with nothing to collide with,
## nothing to fall off, and nothing that can touch it.
##
## The body does not come along. It stays standing where you left it (parked
## by Player.set_editing), and closing the editor puts the camera back inside
## its head — so leaving the editor always returns you to your character,
## wherever the camera wandered off to.
##
## GOD CONTROLS (Lemon, 2026-09-12): WASD is FLAT -- it moves you on the
## world plane along the way you are facing, and nose-down never dives you
## into the dirt. SHIFT rises, CTRL drops, both in world up/down. SPACE is a
## TOGGLE, not a held key: on = fast, press again = normal. `speed_mult` is
## the scroll wheel and `boost` is the Space toggle, both shared with the
## player's god flight so the dial and the toggle read the same in both.
##
## It owns its own yaw and pitch rather than rotating a parent, so nothing in
## the player's camera rig (the perch glide, the walk bob, the hit shake) can
## reach in and move it.
## ===========================================================================

const BASE_SPEED := 12.0        ## m/s at speed_mult 1.0
const BOOST := 3.2              ## the Space toggle
const ACCEL := 9.0              ## how hard it chases the target velocity
const STOP := 14.0              ## ...and how hard it stops. Higher = tighter.
const PITCH_LIMIT := 1.5

var active := false
var typing := false             ## a panel text box has the keyboard
var speed_mult := 1.0
var boost := false              ## SPACE toggle -- sticky, not a held key
var yaw := 0.0
var pitch := 0.0

var _vel := Vector3.ZERO


func _ready() -> void:
	current = false
	far = 9000.0                ## the ranges have to render from up here too
	near = 0.05
	set_process(true)


func take_over(from: Camera3D) -> void:
	## Lift out of the head, keeping the exact view the player had, so entering
	## the editor never jumps the picture.
	if from != null and from.is_inside_tree():
		global_transform = from.global_transform
		fov = from.fov
		far = maxf(from.far, 4000.0)
		var e := global_transform.basis.get_euler()
		yaw = e.y
		pitch = clampf(e.x, -PITCH_LIMIT, PITCH_LIMIT)
	_vel = Vector3.ZERO
	active = true
	current = true
	_apply_rot()


func release(back_to: Camera3D) -> void:
	## Back into the head. The camera keeps its position so re-entering the
	## editor picks up where you left off, but it is no longer the eye.
	active = false
	current = false
	_vel = Vector3.ZERO
	if back_to != null and back_to.is_inside_tree():
		back_to.current = true


func place(pos: Vector3, look_at_pos: Vector3) -> void:
	## Put the eye somewhere and point it at something (the map's fast travel).
	## Goes through yaw/pitch like everything else, so the horizon stays level.
	global_position = pos
	var d := look_at_pos - pos
	if d.length_squared() > 0.0001:
		yaw = atan2(-d.x, -d.z)
		pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -PITCH_LIMIT, PITCH_LIMIT)
	_vel = Vector3.ZERO
	_apply_rot()


func look(rel: Vector2, sens: float) -> void:
	yaw = wrapf(yaw - rel.x * sens, -PI, PI)
	pitch = clampf(pitch - rel.y * sens, -PITCH_LIMIT, PITCH_LIMIT)
	_apply_rot()


func _apply_rot() -> void:
	## Set outright, never rotate()d: an accumulated basis drifts and rolls.
	global_transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)),
		global_transform.origin)


func speed() -> float:
	var s := BASE_SPEED * speed_mult
	if boost:
		s *= BOOST
	return s


func _process(delta: float) -> void:
	if not active:
		return
	var iv := Vector3.ZERO
	if not typing:
		if Input.is_key_pressed(KEY_W): iv.z -= 1.0
		if Input.is_key_pressed(KEY_S): iv.z += 1.0
		if Input.is_key_pressed(KEY_A): iv.x -= 1.0
		if Input.is_key_pressed(KEY_D): iv.x += 1.0
	var lift := 0.0
	if not typing:
		## Height is its own pair of keys, in WORLD up and down.
		if Input.is_key_pressed(KEY_SHIFT):
			lift += 1.0
		if Input.is_key_pressed(KEY_CTRL):
			lift -= 1.0
	var dir := move_dir(iv, lift)
	var target := dir * speed()
	var rate := (ACCEL if dir != Vector3.ZERO else STOP) * maxf(1.0, speed_mult) * delta * 10.0
	_vel = _vel.move_toward(target, rate)
	if _vel.length_squared() > 0.000001:
		global_position += _vel * delta


func move_dir(iv: Vector3, lift: float) -> Vector3:
	## The direction the keys are asking for, as a unit vector. FLAT: the
	## input goes through YAW ONLY and the pitch is thrown away, so you slide
	## across the map at the height you are at however far down the nose is --
	## which is what you want when you are looking at ground you are laying
	## out. Height is `lift`, in world up/down, and it is the only thing that
	## can put a y in the result.
	##
	## Pure maths, no Input: it is the part the tests can drive.
	var dir := Basis.from_euler(Vector3(0.0, yaw, 0.0)) * iv
	dir.y = lift
	if dir.length_squared() > 0.000001:
		return dir.normalized()
	return Vector3.ZERO


func distance_to_body(body: Node3D) -> float:
	if body == null or not is_instance_valid(body):
		return 0.0
	return global_position.distance_to(body.global_position)
