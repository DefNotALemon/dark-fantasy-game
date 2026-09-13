class_name HitFX
extends Node3D

## ========================= Impact effects (hits) ==========================
## Nothing in this world gets hit for free any more. Every blow that lands
## leaves something in the air, in the same no-texture particle language as
## the rest of the game — little CUBES, emissive when they're supposed to
## glow — so an impact reads at a glance and costs almost nothing to draw.
##
##   flesh()    blood, dark and wet, thrown along the swing. Settings ->
##              Blood: Off swaps it for a neutral dust puff. Nothing else
##              about the hit changes: same damage, same feel.
##   armour()   SPARKS — white-hot flecks skidding off steel, plus a
##              one-beat flash so plate reads as PLATE the moment you hit it.
##   bone()     the undead have nothing left to bleed: pale shards, grey dust.
##   wood()     chips and splinters burst out of the exact spot you struck,
##              tinted to the species you're cutting.
##   element()  whatever your blade IS, fed straight from Materials.blade_fx:
##              the fire metals throw embers into the wound, voidsteel leaks
##              purple, mithril and adamant flash their own colour of light.
##
## Everything here is ONE-SHOT and self-freeing: build it, drop it in the
## world, forget it. Nothing to tick, nothing to clean up.

## Settings -> Blood. Player._apply_settings drives this; every flesh() call
## reads it, so the switch takes effect on the very next hit.
static var blood_enabled := true

## Fresh-cut wood, by species — the pale heart under each bark.
const CHIP_TINT := {
	"maple": Color(0.46, 0.33, 0.20),
	"birch": Color(0.80, 0.75, 0.66),
	"oak": Color(0.38, 0.27, 0.17),
	"pine": Color(0.60, 0.44, 0.24),
	"fir": Color(0.44, 0.34, 0.21),
}
const CHIP_DEFAULT := Color(0.45, 0.33, 0.18)

var _life := 1.6              ## how long the node hangs around before freeing
var _flash_col := Color.BLACK ## a light flash at the impact (BLACK = none)
var _flash_energy := 0.0
var _flash_range := 3.0
var _flash_time := 0.14


func _ready() -> void:
	## The flash: a light that exists for a blink. It's what sells metal on
	## metal, and it's why a fire blade lights the wound it just opened.
	if _flash_energy > 0.0:
		var fl := OmniLight3D.new()
		fl.light_color = _flash_col
		fl.light_energy = _flash_energy
		fl.omni_range = _flash_range
		fl.shadow_enabled = false
		add_child(fl)
		var tw := create_tween()
		tw.tween_property(fl, "light_energy", 0.0, _flash_time)
	get_tree().create_timer(_life).timeout.connect(queue_free)


## ============================ The flavours ================================


static func flesh(at: Vector3, dir: Vector3, power := 1.0) -> HitFX:
	## A cut opens and throws. With blood turned off you still get the hit —
	## a colourless puff of impact dust — so nothing reads as a miss.
	var fx := _root(at, 1.4)
	var d := _safe(dir)
	if not blood_enabled:
		fx.add_child(_cubes(int(11 * power), 0.048, 0.55, d, 58.0, 1.4, 3.6, 4.0,
			_ramp(Color(0.60, 0.56, 0.50, 0.55), Color(0.50, 0.46, 0.41, 0.35),
				Color(0.42, 0.38, 0.34, 0.0))))
		return fx
	## The spray: fine, fast, along the line of the swing.
	fx.add_child(_cubes(int(15 * power), 0.034, 0.55, d, 40.0, 3.6, 7.4, 15.0,
		_ramp(Color(0.55, 0.03, 0.04, 1.0), Color(0.34, 0.015, 0.02, 0.95),
			Color(0.15, 0.0, 0.01, 0.0))))
	## The gouts: heavier, slower, they fall out of the wound rather than fly.
	fx.add_child(_cubes(int(6 * power), 0.062, 0.95, d, 74.0, 1.1, 3.0, 17.0,
		_ramp(Color(0.44, 0.02, 0.03, 1.0), Color(0.30, 0.01, 0.02, 1.0),
			Color(0.12, 0.0, 0.0, 0.0))))
	return fx


static func armour(at: Vector3, dir: Vector3, power := 1.0) -> HitFX:
	## Steel on steel. Sparks skid off the plate in a wide fan and die fast —
	## the flash is what your eye actually catches.
	var fx := _root(at, 1.0)
	var d := _safe(dir)
	fx._flash_col = Color(1.0, 0.80, 0.45)
	fx._flash_energy = 2.6 * power
	fx._flash_range = 3.4
	fx._flash_time = 0.13
	fx.add_child(_cubes(int(24 * power), 0.021, 0.40, d, 66.0, 5.0, 11.5, 19.0,
		_ramp(Color(1.0, 0.98, 0.86, 1.0), Color(1.0, 0.58, 0.14, 1.0),
			Color(0.55, 0.10, 0.0, 0.0)),
		true, Color(1.0, 0.72, 0.28)))
	## A few that ricochet the OTHER way — off the bevel, back past your ear.
	fx.add_child(_cubes(int(7 * power), 0.018, 0.30, -d, 80.0, 3.0, 7.0, 21.0,
		_ramp(Color(1.0, 0.95, 0.80, 1.0), Color(1.0, 0.50, 0.10, 0.9),
			Color(0.45, 0.08, 0.0, 0.0)),
		true, Color(1.0, 0.66, 0.22)))
	return fx


static func bone(at: Vector3, dir: Vector3, power := 1.0) -> HitFX:
	## The undead kept the frame and lost everything else. Shards and grave dust.
	var fx := _root(at, 1.4)
	var d := _safe(dir)
	fx.add_child(_cubes(int(11 * power), 0.042, 0.80, d, 52.0, 2.6, 5.6, 16.0,
		_ramp(Color(0.88, 0.86, 0.78, 1.0), Color(0.72, 0.70, 0.62, 0.9),
			Color(0.55, 0.53, 0.46, 0.0))))
	fx.add_child(_cubes(int(9 * power), 0.030, 0.70, d, 70.0, 0.9, 2.4, 3.0,
		_ramp(Color(0.62, 0.60, 0.55, 0.55), Color(0.52, 0.50, 0.46, 0.35),
			Color(0.44, 0.42, 0.38, 0.0))))
	return fx


static func wood(at: Vector3, dir: Vector3, species := "", power := 1.0) -> HitFX:
	## Chips out of the cut. The heart colour follows the species, so birch
	## throws pale and oak throws dark — you can tell what you're felling by
	## what comes off it.
	var fx := _root(at, 1.5)
	var d := _safe(dir)
	var tint: Color = CHIP_TINT.get(species, CHIP_DEFAULT)
	fx.add_child(_cubes(int(14 * power), 0.050, 1.00, d, 46.0, 2.6, 5.8, 13.0,
		_ramp(tint, tint.darkened(0.18), Color(tint.r, tint.g, tint.b, 0.0))))
	## Sawdust: the fine stuff that hangs in the air a beat after the chips land.
	var dust := tint.lightened(0.35)
	fx.add_child(_cubes(int(10 * power), 0.020, 0.85, d, 72.0, 0.8, 2.3, 3.0,
		_ramp(Color(dust.r, dust.g, dust.b, 0.6), Color(dust.r, dust.g, dust.b, 0.35),
			Color(dust.r, dust.g, dust.b, 0.0))))
	return fx


static func element(at: Vector3, dir: Vector3, blade: Dictionary, power := 1.0) -> HitFX:
	## The blade's OWN signature, landing where the blade landed. An honest
	## metal returns null — iron doesn't do anything to the air, and it
	## shouldn't pretend to. See Materials.blade_fx().
	if blade.is_empty():
		return null
	var fx := _root(at, 1.6)
	var d := _safe(dir)
	var col: Color = blade.get("light", Color.WHITE)
	fx._flash_col = col
	fx._flash_energy = float(blade.get("energy", 1.0)) * 2.2 * power
	fx._flash_range = float(blade.get("range", 3.0)) * 1.2
	fx._flash_time = 0.22
	if bool(blade.get("fire", false)):
		## Fire metals push embers INTO the wound and let them climb out again.
		fx.add_child(_cubes(int(18 * power), 0.030, 0.85, d, 55.0, 2.2, 5.2, -1.6,
			_ramp(Color(1.0, 0.86, 0.35, 1.0), Color(1.0, 0.42, 0.07, 0.95),
				Color(0.65, 0.09, 0.01, 0.0)),
			true, Color(1.0, 0.45, 0.10)))
	elif bool(blade.get("void", false)):
		## Voidsteel doesn't spark. It LEAKS — slow purple squares that sink.
		fx.add_child(_cubes(int(14 * power), 0.042, 1.30, d, 85.0, 0.7, 2.0, 1.2,
			_ramp(Color(0.66, 0.34, 1.0, 0.95), Color(0.30, 0.09, 0.52, 0.85),
				Color(0.04, 0.0, 0.10, 0.0)),
			true, Color(0.52, 0.22, 0.92)))
	else:
		## Mithril, adamant: no weather, just their own light off the edge.
		fx.add_child(_cubes(int(13 * power), 0.024, 0.45, d, 62.0, 3.6, 8.0, 12.0,
			_ramp(col, Color(col.r, col.g, col.b, 0.8), Color(col.r, col.g, col.b, 0.0)),
			true, col))
	return fx


static func kind_of(body: Node) -> String:
	## What KIND of thing did you just hit? Three answers, three messes:
	##   armour — plate between you and it (the Dark Knight, anything tagged
	##            "armored"/"construct", or an enemy with armored = true)
	##   bone   — the undead have nothing left to bleed
	##   flesh  — everything else
	if body == null:
		return "flesh"
	var fams: Array = body.families if "families" in body else []
	if "armored" in fams or "construct" in fams:
		return "armour"
	if "armored" in body and bool(body.get("armored")):
		return "armour"
	if "undead" in fams or "skeleton" in fams:
		return "bone"
	if "slime" in fams:
		## goo, in the jelly's own colour — carried in the kind string so the
		## one-door for_creature() below can pour the right colour
		var gc: Color = body.get("goo_color") if "goo_color" in body else Color(0.4, 0.9, 0.3)
		return "slime:" + gc.to_html(false)
	return "flesh"


static func for_creature(kind: String, at: Vector3, dir: Vector3, power := 1.0) -> HitFX:
	## One door for the three kinds of body. kind_of() picks it.
	if kind.begins_with("slime"):
		var col := Color(0.4, 0.9, 0.3)
		if kind.length() > 6:
			col = Color.html(kind.substr(6))
		return goo(at, dir, col, power)
	match kind:
		"armour":
			return armour(at, dir, power)
		"bone":
			return bone(at, dir, power)
		_:
			return flesh(at, dir, power)


static func goo(at: Vector3, dir: Vector3, col: Color, power := 1.0) -> HitFX:
	## SLIME: a wet burst of jelly in the creature's own colour — fat slow
	## gobbets that fall and a fine faintly-lit spray that hangs a moment.
	## (scripts/Slime.gd uses it for landings and the death splat too.)
	var fx := _root(at, 1.1)
	var d := _safe(dir)
	var dim := Color(col.r * 0.55, col.g * 0.55, col.b * 0.55, 1.0)
	fx.add_child(_cubes(int(10 * power), 0.075, 0.75, d, 55.0, 2.0, 4.5, 11.0,
		_ramp(col, dim, Color(dim.r, dim.g, dim.b, 0.0))))
	fx.add_child(_cubes(int(18 * power), 0.030, 0.55, d, 80.0, 3.0, 6.5, 7.0,
		_ramp(Color(col.r, col.g, col.b, 0.95), Color(col.r, col.g, col.b, 0.6), Color(col.r, col.g, col.b, 0.0)),
		true, col))
	return fx


## ============================== Plumbing ==================================


static func _root(at: Vector3, life: float) -> HitFX:
	var fx := HitFX.new()
	fx.position = at
	fx._life = life
	return fx


static func _safe(dir: Vector3) -> Vector3:
	## A zero direction would emit into a single point. Fall back to "up and
	## out", which is a fine default for anything struck.
	if dir.length_squared() < 0.0001:
		return Vector3.UP
	return dir.normalized()


static func _ramp(a: Color, mid: Color, b: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	g.add_point(0.45, mid)
	return g


static func _cubes(amount: int, size: float, life: float, dir: Vector3, spread: float,
		vmin: float, vmax: float, grav: float, ramp: Gradient,
		emissive := false, emit_col := Color.WHITE) -> CPUParticles3D:
	## One burst of cubes. WORLD space, one-shot, fully explosive — the whole
	## amount leaves at the instant of contact and nothing trails the player.
	var p := CPUParticles3D.new()
	p.amount = maxi(amount, 1)
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = Vector3(0.0, -grav, 0.0)
	p.damping_min = 0.5
	p.damping_max = 2.0
	p.scale_amount_min = 0.55
	p.scale_amount_max = 1.45
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * size
	p.mesh = bm
	p.color_ramp = ramp
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 1.0
	if emissive:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.emission = emit_col
		mat.emission_energy_multiplier = 2.4
	else:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	p.material_override = mat
	return p
