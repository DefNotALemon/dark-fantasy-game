class_name MeteorFall
extends Node3D
## A STAR FALLS — slowly, and in public.
##
## The old meteor was an 0.85-second streak: if you blinked, the world just
## grew a crater. Now the sky gives you the whole performance. Something
## ignites high over the map — a burning point you can pick out day or night
## (by day it reads dimmer, a hot cinder against the blue; by night it burns
## like a second star) — and for the next twenty-odd seconds it FALLS, gently,
## trailing pixel embers, close enough to watch and far enough to wonder about.
## Then the air stops carrying it: the last second and a half is a hard
## accelerating DIVE, the trail tears, the light arrives before the sound
## would, and the ground takes it (World._meteor_impact — crater, fused
## meteoric ball, rubble, quake).
##
## Fog would normally eat anything 200 m up — the core and trail render with
## disable_fog so the omen stays visible from anywhere on the map.

const TRAIL_LIFE := 1.6

var target := Vector3.ZERO       ## where it lands (World picks this)
var world: Node3D = null         ## the World — brightness asks it about the sun
var descent_dur := 23.0          ## the long omen
var dive_dur := 1.5              ## the part gravity wins

var t := 0.0
var phase := 0                   ## 0 = drifting descent, 1 = the dive, 2 = spent
var _start := Vector3.ZERO
var _hover := Vector3.ZERO       ## where the drift ends and the dive begins
var _dive_from := Vector3.ZERO
var _core: MeshInstance3D
var _cmat: StandardMaterial3D
var _light: OmniLight3D
var _trail_t := 0.0
var _bright := 1.0               ## eased day/night presence
var _sway_seed := 0.0


func _ready() -> void:
	add_to_group("meteor")
	_sway_seed = randf() * TAU
	var a := randf() * TAU
	_start = target + Vector3(cos(a) * 120.0, 185.0, sin(a) * 120.0)
	_hover = target + Vector3(cos(a) * 14.0, 88.0, sin(a) * 14.0)
	global_position = _start

	_core = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.15
	sm.height = 2.3
	sm.radial_segments = 8
	sm.rings = 4
	_core.mesh = sm
	_cmat = StandardMaterial3D.new()
	_cmat.albedo_color = Color(0.25, 0.12, 0.06)
	_cmat.emission_enabled = true
	_cmat.emission = Color(1.0, 0.5, 0.15)
	_cmat.emission_energy_multiplier = 7.0
	_cmat.disable_fog = true  ## the omen must read through 200 m of forest fog
	_core.material_override = _cmat
	add_child(_core)

	## The light stays dark until the dive — a point 200 m up lights nothing,
	## and the approach glow arriving with the fall is half the drama.
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.light_energy = 0.0
	_light.omni_range = 34.0
	_light.shadow_enabled = false
	add_child(_light)


func _process(delta: float) -> void:
	if phase >= 2:
		return
	## Presence rides the sky: a cinder by day, a second star by night.
	var dark := true
	if world != null and world.has_method("is_dark_out"):
		dark = bool(world.is_dark_out())
	_bright = lerpf(_bright, 1.0 if dark else 0.38, delta * 2.0)
	_cmat.emission_energy_multiplier = 1.5 + 7.0 * _bright

	t += delta
	if phase == 0:
		var u := clampf(t / descent_dur, 0.0, 1.0)
		## Mostly vertical, faintly eased, with a lazy sway — falling the way
		## a thing falls when the air still has a say in it.
		var eased := u * u * (3.0 - 2.0 * u) * 0.25 + u * 0.75
		var p := _start.lerp(_hover, eased)
		p += Vector3(sin(t * 0.6 + _sway_seed), 0.0, cos(t * 0.47 + _sway_seed)) * 2.6 * (1.0 - u)
		global_position = p
		_trail(delta, 0.24, 0.5)
		if u >= 1.0:
			phase = 1
			t = 0.0
			_dive_from = global_position
	elif phase == 1:
		var u := clampf(t / dive_dur, 0.0, 1.0)
		var k := u * u  ## gravity stops negotiating
		global_position = _dive_from.lerp(target + Vector3.UP * 0.6, k)
		_core.scale = Vector3.ONE * (1.0 + u * 0.8)
		_light.light_energy = 5.0 * u  ## the glow arrives with it
		_trail(delta, 0.05, 0.75)
		if u >= 1.0:
			phase = 2
			_impact_flash()
			if world != null and world.has_method("_meteor_impact"):
				world._meteor_impact(target, self)
			else:
				queue_free()


func _trail(delta: float, every: float, size: float) -> void:
	## Pixel embers shed along the path — they hang a moment and gutter out.
	_trail_t += delta
	if _trail_t < every:
		return
	_trail_t = 0.0
	if world == null:
		return
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * size * randf_range(0.7, 1.3)
	m.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.09, 0.04)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.12).lerp(Color(1.0, 0.7, 0.3), randf())
	mat.emission_energy_multiplier = (2.0 + 4.0 * _bright)
	mat.disable_fog = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material_override = mat
	world.add_child(m)
	m.global_position = global_position + Vector3(randf_range(-0.7, 0.7),
		randf_range(-0.4, 0.9), randf_range(-0.7, 0.7))
	m.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	var tw := m.create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3.ONE * 0.05, TRAIL_LIFE) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(m, "position", m.position + Vector3.UP * randf_range(0.4, 1.2), TRAIL_LIFE)
	tw.chain().tween_callback(m.queue_free)


func _impact_flash() -> void:
	## One hard blink of light at the strike, independent of this node's fate.
	if world == null:
		return
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.2)
	l.light_energy = 7.0
	l.omni_range = 40.0
	l.shadow_enabled = false
	world.add_child(l)
	l.global_position = target + Vector3.UP * 2.0
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(l.queue_free)
