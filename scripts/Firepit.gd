class_name Firepit
extends Node3D

## ===========================================================================
## A FIRE THAT ACTUALLY BURNS — scripts/Firepit.gd
##
## `BuildKit`'s "firepit" piece was nine stones, a scorched base and four
## leaning sticks: a picture of a fire. This is the fire. It rides as a child
## of the BuiltPiece that draws it, owns the only three things a fire needs to
## have — a state, a quantity of fuel, and a radius it warms — and writes all
## three down so the camp you banked before you slept is still glowing when
## you get up.
##
## THREE STATES, ONE DIRECTION: OUT -> LIT -> EMBERS -> OUT. Embers are not
## decoration; they hold a quarter of the heat and they will take a log
## without a torch, which is the whole reason you bank a fire instead of
## letting it die.
##
## WHAT IT PLUGS INTO
##   group "fires"      the heat query every warmth system will read.
##                      `Firepit.heat_from(get_tree().get_nodes_in_group("fires"), pos)`
##                      takes the MAXIMUM, never the sum — two campfires are
##                      not a furnace.
##   group "campfires"  ALREADY READ by CritterSwarm._harass (line 207) and
##                      until now never joined by anything: standing in the
##                      smoke is supposed to call the blackflies off you and
##                      never once has. A lit pit joins; a dead one leaves.
##   Weather.intensity  rain in the open burns your wood twice as fast, and a
##                      STORM will not take a light at all. That is the line
##                      that makes a roof worth building BEFORE you are cold.
##
## No RNG anywhere except the flame flicker, which is cosmetic and never read
## back — two Firepits fed the same wood burn down to the same second.
## ===========================================================================

enum State { OUT = 0, LIT = 1, EMBERS = 2 }

## --- fuel, in seconds of burning -------------------------------------------
const FUEL_MAX := 1800.0          ## a day and a half of game time, banked
const FUEL_PER_LOG := 420.0       ## a felled log is the real currency
const FUEL_PER_PLANK := 180.0
const FUEL_PER_STICK := 60.0
const FUEL_KINDLING := 120.0      ## what a torch alone buys you
const EMBER_SECONDS := 90.0       ## how long a dead fire stays relightable

## --- heat -------------------------------------------------------------------
const FIRE_HEAT_C := 14.0         ## degrees added at the stones
const FIRE_CORE := 0.9            ## full heat inside this radius
const FIRE_RANGE := 5.5           ## nothing beyond this
const EMBER_HEAT_MULT := 0.25

## --- weather ------------------------------------------------------------------
const RAIN_BURN_MULT := 2.0
const RAIN_THRESHOLD := 0.5       ## Weather.intensity above which rain bites
const STORM_LEVEL := 4            ## Weather.Level.STORM, without the dependency
const SHELTER_UP := 7.0           ## how far up we look for a roof
const SHELTER_RECHECK := 1.5      ## seconds between shelter rays

## --- fuel names the pack can spend -------------------------------------------
const FUEL_ITEMS := {
	"Log": FUEL_PER_LOG,
	"Plank": FUEL_PER_PLANK,
	"Branch": FUEL_PER_STICK,
	"Stick": FUEL_PER_STICK,
	"Thatch": FUEL_PER_STICK,
}

var state: int = State.OUT
var fuel := 0.0
var ember_t := 0.0

var _light: OmniLight3D
var _flame: GPUParticles3D
var _smoke: GPUParticles3D
var _ember_mesh: MeshInstance3D
var _flicker := 0.0
var _shelter_t := 0.0
var _sheltered := false
var _booted := false


# ===========================================================================
#  Boot
# ===========================================================================

static func make() -> Firepit:
	var f := Firepit.new()
	f.name = "Fire"
	return f


func _ready() -> void:
	boot()


func boot() -> void:
	## Idempotent: a node parented from _init() never gets _ready(), and a
	## BuiltPiece restored from disk builds its children before it is in the
	## tree. Everything here must survive being called twice.
	if _booted:
		return
	_booted = true
	add_to_group("fires")
	_build_visuals()
	_apply_visuals()


func _build_visuals() -> void:
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.62, 0.28)
	_light.light_energy = 0.0
	_light.omni_range = 9.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 0.55, 0)
	add_child(_light)

	## The flame: a short, fat, upward cone of hot quads.
	_flame = GPUParticles3D.new()
	_flame.amount = 26
	_flame.lifetime = 0.7
	_flame.emitting = false
	_flame.position = Vector3(0, 0.18, 0)
	var fm := ParticleProcessMaterial.new()
	fm.direction = Vector3(0, 1, 0)
	fm.spread = 14.0
	fm.initial_velocity_min = 0.9
	fm.initial_velocity_max = 1.7
	fm.gravity = Vector3(0, 0.6, 0)
	fm.scale_min = 0.35
	fm.scale_max = 0.85
	fm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	fm.emission_sphere_radius = 0.22
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.86, 0.42, 1.0))
	ramp.set_color(1, Color(0.85, 0.22, 0.05, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	fm.color_ramp = gt
	_flame.process_material = fm
	var q := QuadMesh.new()
	q.size = Vector2(0.30, 0.42)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.vertex_color_use_as_albedo = true
	qm.albedo_color = Color(1.0, 0.72, 0.30)
	q.material = qm
	_flame.draw_pass_1 = q
	add_child(_flame)

	## The smoke: the part CritterSwarm cares about, and the part you see from
	## across a valley before you see the camp.
	_smoke = GPUParticles3D.new()
	_smoke.amount = 14
	_smoke.lifetime = 3.4
	_smoke.emitting = false
	_smoke.position = Vector3(0, 0.55, 0)
	var sm := ParticleProcessMaterial.new()
	sm.direction = Vector3(0, 1, 0)
	sm.spread = 9.0
	sm.initial_velocity_min = 0.5
	sm.initial_velocity_max = 0.9
	sm.gravity = Vector3(0, 0.25, 0)
	sm.scale_min = 0.6
	sm.scale_max = 1.9
	var sramp := Gradient.new()
	sramp.set_color(0, Color(0.36, 0.34, 0.32, 0.30))
	sramp.set_color(1, Color(0.52, 0.52, 0.52, 0.0))
	var sgt := GradientTexture1D.new()
	sgt.gradient = sramp
	sm.color_ramp = sgt
	_smoke.process_material = sm
	var sq := QuadMesh.new()
	sq.size = Vector2(0.7, 0.7)
	var sqm := StandardMaterial3D.new()
	sqm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sqm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sqm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sqm.vertex_color_use_as_albedo = true
	sqm.albedo_color = Color(0.42, 0.40, 0.38)
	sq.material = sqm
	_smoke.draw_pass_1 = sq
	add_child(_smoke)

	## The coal bed — the thing that is still orange at four in the morning.
	_ember_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.62, 0.07, 0.62)
	_ember_mesh.mesh = bm
	var em := StandardMaterial3D.new()
	em.albedo_color = Color(0.55, 0.13, 0.03)
	em.emission_enabled = true
	em.emission = Color(1.0, 0.42, 0.10)
	em.emission_energy_multiplier = 1.4
	em.roughness = 1.0
	_ember_mesh.material_override = em
	_ember_mesh.position = Vector3(0, 0.10, 0)
	_ember_mesh.visible = false
	add_child(_ember_mesh)


# ===========================================================================
#  The three verbs
# ===========================================================================

func can_light() -> bool:
	if state == State.LIT:
		return false
	return not storm_bound()


func storm_bound() -> bool:
	## A gale takes a match out of your hand. Under a roof it does not.
	var w := weather()
	if w == null:
		return false
	if sheltered():
		return false
	return int(w.level) >= STORM_LEVEL and float(w.intensity) > 0.55


func light(starter := FUEL_KINDLING) -> bool:
	if not can_light():
		return false
	fuel = minf(FUEL_MAX, maxf(fuel, 0.0) + maxf(starter, 0.0))
	if fuel <= 0.0:
		return false
	state = State.LIT
	ember_t = 0.0
	_apply_visuals()
	return true


func feed(seconds: float) -> bool:
	## Feeding embers relights them — that is what banking a fire is for.
	if seconds <= 0.0 or state == State.OUT:
		return false
	fuel = minf(FUEL_MAX, fuel + seconds)
	if state == State.EMBERS:
		state = State.LIT
		ember_t = 0.0
	_apply_visuals()
	return true


func douse() -> void:
	state = State.OUT
	fuel = 0.0
	ember_t = 0.0
	_apply_visuals()


func burning() -> bool:
	return state != State.OUT


# ===========================================================================
#  Heat
# ===========================================================================

func heat_at(at: Vector3) -> float:
	if state == State.OUT:
		return 0.0
	var d := here().distance_to(at)
	var h := FIRE_HEAT_C * smoothstep(FIRE_RANGE, FIRE_CORE, d)
	if state == State.EMBERS:
		h *= EMBER_HEAT_MULT
	return h


static func heat_from(fires: Array, at: Vector3) -> float:
	## MAXIMUM, never the sum. Two campfires are not a furnace.
	var best := 0.0
	for n in fires:
		var f := n as Firepit
		if f == null or not is_instance_valid(f):
			continue
		best = maxf(best, f.heat_at(at))
	return best


func here() -> Vector3:
	return global_position if is_inside_tree() else position


# ===========================================================================
#  Burning down
# ===========================================================================

func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	tick(delta)


func tick(delta: float) -> void:
	## Public so the suite can run a fire through a night without a frame loop.
	if state == State.OUT:
		return
	_shelter_t -= delta
	if _shelter_t <= 0.0:
		_shelter_t = SHELTER_RECHECK
		_sheltered = _raycast_roof()
	if state == State.EMBERS:
		ember_t -= delta
		if ember_t <= 0.0:
			douse()
		else:
			_apply_visuals()
		return
	fuel = maxf(0.0, fuel - delta * burn_rate())
	if fuel <= 0.0:
		state = State.EMBERS
		ember_t = EMBER_SECONDS
	_flicker += delta
	_apply_visuals()


func burn_rate() -> float:
	## 1.0 normally; doubled by rain landing on it. A roof is the whole fix.
	var w := weather()
	if w == null:
		return 1.0
	if float(w.intensity) > RAIN_THRESHOLD and not sheltered():
		return RAIN_BURN_MULT
	return 1.0


func minutes_left() -> float:
	if state == State.EMBERS:
		return ember_t / 60.0
	return fuel / maxf(burn_rate(), 0.001) / 60.0


# ===========================================================================
#  Shelter — the half of the design that makes roofs matter
# ===========================================================================

func sheltered() -> bool:
	if not is_inside_tree():
		return _sheltered
	if _shelter_t <= 0.0:
		_shelter_t = SHELTER_RECHECK
		_sheltered = _raycast_roof()
	return _sheltered


func _raycast_roof() -> bool:
	if not is_inside_tree():
		return false
	var w3 := get_world_3d()
	if w3 == null:
		return false
	var space := w3.direct_space_state
	if space == null:
		return false
	var from := here() + Vector3.UP * 0.6
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * SHELTER_UP)
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	return not hit.is_empty()


# ===========================================================================
#  Look
# ===========================================================================

func _apply_visuals() -> void:
	if _light == null:
		return
	var f01 := clampf(fuel / 600.0, 0.0, 1.0)
	match state:
		State.LIT:
			var flick := 1.0 + sin(_flicker * 11.3) * 0.06 + sin(_flicker * 4.1) * 0.04
			_light.light_energy = (1.1 + 1.4 * f01) * flick
			_light.omni_range = 6.5 + 3.5 * f01
			_flame.emitting = true
			_flame.amount_ratio = 0.35 + 0.65 * f01
			_smoke.emitting = true
			_ember_mesh.visible = true
			_set_ember_glow(1.4)
		State.EMBERS:
			var e01 := clampf(ember_t / EMBER_SECONDS, 0.0, 1.0)
			_light.light_energy = 0.45 * e01
			_light.omni_range = 4.5
			_flame.emitting = false
			_smoke.emitting = true
			_ember_mesh.visible = true
			_set_ember_glow(0.35 + 0.9 * e01)
		_:
			_light.light_energy = 0.0
			_flame.emitting = false
			_smoke.emitting = false
			_ember_mesh.visible = false
	_sync_swarm_group()


func _set_ember_glow(e: float) -> void:
	if _ember_mesh == null:
		return
	var m := _ember_mesh.material_override as StandardMaterial3D
	if m != null:
		m.emission_energy_multiplier = e


func _sync_swarm_group() -> void:
	## CritterSwarm._harass has been reading "campfires" since the swarm pass
	## and nothing has ever been in it. Smoke calls the blackflies off you now.
	var want := burning()
	var have := is_in_group("campfires")
	if want and not have:
		add_to_group("campfires")
	elif not want and have:
		remove_from_group("campfires")


# ===========================================================================
#  Plumbing
# ===========================================================================

func weather() -> Object:
	if not is_inside_tree():
		return null
	var w := get_tree().get_first_node_in_group("world")
	if w == null or not w.has_method("weather"):
		return null
	return w.call("weather")


static func fuel_value(item_name: String) -> float:
	return float(FUEL_ITEMS.get(item_name, 0.0))


static func is_fuel(item_name: String) -> bool:
	return FUEL_ITEMS.has(item_name)


func state_name() -> String:
	match state:
		State.LIT: return "lit"
		State.EMBERS: return "embers"
	return "out"


# ===========================================================================
#  Save
# ===========================================================================

func to_dict() -> Dictionary:
	return {"state": int(state), "fuel": fuel, "ember": ember_t}


func apply_dict(d: Dictionary) -> void:
	state = int(d.get("state", State.OUT))
	if state < State.OUT or state > State.EMBERS:
		state = State.OUT
	fuel = clampf(float(d.get("fuel", 0.0)), 0.0, FUEL_MAX)
	ember_t = clampf(float(d.get("ember", 0.0)), 0.0, EMBER_SECONDS)
	## A dict that says LIT with no wood left is a dict from a crash; the fire
	## it describes had already gone to embers.
	if state == State.LIT and fuel <= 0.0:
		state = State.EMBERS
		ember_t = maxf(ember_t, EMBER_SECONDS * 0.5)
	if state == State.EMBERS and ember_t <= 0.0:
		state = State.OUT
	_apply_visuals()
