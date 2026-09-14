class_name Locomotion
extends Node
## ===========================================================================
## HOW THE BODY CROSSES THE GROUND.  (2026-09-14, Lemon: "make the movement
## more dynamic and flowy, I also want the movement to slow in tall grass")
##
## Player.gd used to be honest and lifeless: move_toward() a target velocity at
## 45 m/s^2, which reaches full sprint in a tenth of a second and turns a right
## angle in ONE FRAME. Nothing in the world could push back on it either -- a
## hillside, a bog and a chest-high meadow all walked at exactly 5 m/s.
##
## Everything here is a STATIC PURE FUNCTION of numbers. No nodes, no tree, no
## globals -- so tests/LocomotionTests.gd can drive the whole feel of the game
## headless in milliseconds, and Player.gd keeps a dozen call sites instead of
## a second physics engine inlined in a 9,500-line file.
##
## The four ideas, in the order you feel them:
##
##   1. STEER, not snap. Under a walk you still pivot on a dime (anything else
##      reads as input lag). Above it your velocity ARCS toward the direction
##      you asked for, at a rate that TIGHTENS as you slow down -- so a sprint
##      carves and a walk corners. An angle you could not make this frame
##      SCRUBS speed: cutting hard costs you, which is the whole feeling of
##      weight.
##   2. BANK. The same unsatisfied angle rolls the lens (and the third-person
##      body) into the turn. Free, and it is most of what reads as "flowy".
##   3. THE GROUND DECIDES. Slope, surface family and how deep the meadow is
##      all scale the target speed -- one multiplier each, composed, clamped.
##   4. THE WADE. Tall grass is a 15% tax (Lemon picked subtle: felt, not
##      fought), and the same 0..1 wade number drives the blades parting, the
##      rustle on the stride and the extra sway in the lens, so the slowdown
##      reads as GRASS rather than as the game hitching.
## ===========================================================================

## --- 1. steering ------------------------------------------------------------
## Below this you are not carrying enough momentum for an arc to mean anything,
## so the old snap behaviour stands: standing starts and shuffling in a doorway
## must stay crisp.
const PIVOT_SPEED := 2.2
## Degrees per second of heading change available, by speed. The walk figure is
## deliberately enormous (a body at 3 m/s really can turn that fast); the sprint
## figure is the one that does the work.
const TURN_DEG_WALK := 900.0
const TURN_DEG_SPRINT := 265.0
## YOU CANNOT HOLD A SPRINT THROUGH A HAIRPIN. The turn you asked for and did
## not get this frame caps the speed you are allowed to be carrying, by this
## fraction at a full reversal. It has to be a CAP rather than a per-frame
## subtraction -- ACCEL is 45 m/s^2 and would simply refill anything scrubbed
## off, which is exactly what the first version of this did (and the tests
## caught). As the heading closes the cap lifts and you accelerate out of the
## corner, which is the whole shape of the feeling.
const CORNER_CUT := 0.70

## --- 2. the lens ------------------------------------------------------------
const BANK_ROLL_DEG := 2.6       ## camera roll at a full-speed hard turn
const BODY_BANK_DEG := 7.0       ## the third-person body leans harder than the eye
const FOV_SPRINT := 7.0          ## degrees added at full sprint
const FOV_DASH := 4.0            ## ...and more again while a dash is carrying you
const FOV_OVER := 8.0            ## m/s past sprint that counts as "full dash"

## --- 3. the ground ----------------------------------------------------------
const SLOPE_GAIN := 0.85         ## x sin(grade): uphill costs, downhill pays
const SLOPE_MIN := 0.55          ## a wall of a hill is still climbable, just slow
const SLOPE_MAX := 1.18          ## downhill helps, but this is not a sled
## What each ground family does to your speed. Keys are StepAudio.family_at()'s
## vocabulary exactly, so sound and footing can never disagree about what you
## are standing on.
const SURFACE := {
	"grass": 1.0, "dirt": 1.0, "stone": 1.0, "wood": 1.0,
	"leaf": 0.97, "gravel": 0.94, "snow": 0.84, "sand": 0.86, "mud": 0.80,
}

## --- 4. the wade ------------------------------------------------------------
const WADE_DRAG := 0.15          ## Lemon, 2026-09-14: subtle. Felt, not fought.
const WADE_SPRINT_DRAIN := 1.25  ## x stamina while sprinting through deep meadow
const SHORT_WADE := 0.34         ## the most a SHORT meadow can wade you (tall = 1.0)
const WADE_SWAY := 0.75          ## x head-bob sway at full wade
const WADE_PUSH := 0.55          ## added to Wind's player_push so blades part harder
const BASE_BLADE := 0.18         ## STYLE_DEFAULTS.height -- what "normal" grass is


## ===========================================================================
##  1. STEERING
## ===========================================================================

static func steer(hv: Vector3, want: Vector3, accel: float, decel: float,
		delta: float, sprint_speed: float) -> Vector3:
	## The whole momentum model, in one call. `hv` is the current horizontal
	## velocity, `want` is dir * speed (zero when there is no input). Returns the
	## new horizontal velocity; y is never touched.
	##
	## Degenerate inputs return something sane rather than NaN -- this runs every
	## physics frame of the whole game and a single normalized() of a zero vector
	## here would poison the player's transform permanently.
	if delta <= 0.0:
		return hv
	var cur := hv.length()
	if want.length_squared() < 1e-8:
		return hv.move_toward(Vector3.ZERO, decel * delta)
	if cur < PIVOT_SPEED:
		return hv.move_toward(want, accel * delta)   ## crisp from a standstill
	var cur_dir := hv / cur
	var want_spd := want.length()
	var want_dir := want / want_spd
	var ang := cur_dir.signed_angle_to(want_dir, Vector3.UP)
	var t := clampf(cur / maxf(sprint_speed, 0.001), 0.0, 1.0)
	var rate := deg_to_rad(lerpf(TURN_DEG_WALK, TURN_DEG_SPRINT, t)) * delta
	var step := clampf(ang, -rate, rate)
	var nd := cur_dir.rotated(Vector3.UP, step).normalized()
	## The turn you asked for and did not get is paid in speed.
	var hard := clampf((absf(ang) - absf(step)) / PI, 0.0, 1.0)
	var cap := want_spd * (1.0 - hard * CORNER_CUT)
	var r := accel if cap > cur else decel
	return nd * move_toward(cur, cap, r * delta)


static func bank(hv: Vector3, want: Vector3, sprint_speed: float) -> float:
	## -1 .. 1: which way and how hard the body is leaning into its turn. Positive
	## is a turn to the LEFT (the Y-up signed angle's sign), which is why the
	## caller subtracts it from the roll.
	var cur := hv.length()
	if cur < PIVOT_SPEED or want.length_squared() < 1e-8:
		return 0.0
	var ang := (hv / cur).signed_angle_to(want.normalized(), Vector3.UP)
	return clampf(ang / (PI * 0.5), -1.0, 1.0) * clampf(cur / maxf(sprint_speed, 0.001), 0.0, 1.0)


## ===========================================================================
##  2. THE LENS
## ===========================================================================

static func fov_bonus(hspeed: float, walk_speed: float, sprint_speed: float) -> float:
	## Degrees to ADD to the player's chosen FOV. Nothing below a walk (the world
	## must not breathe while you potter around), smoothstepped up to sprint, and
	## a further push while a dash is carrying you past it.
	var span := maxf(sprint_speed - walk_speed, 0.001)
	var t := clampf((hspeed - walk_speed) / span, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	var over := clampf((hspeed - sprint_speed) / FOV_OVER, 0.0, 1.0)
	return FOV_SPRINT * t + FOV_DASH * over


## ===========================================================================
##  3. THE GROUND
## ===========================================================================

static func slope_mult(floor_normal: Vector3, move_dir: Vector3) -> float:
	## A floor normal tilts AWAY from the uphill direction, so its horizontal
	## component points downhill and its length is sin(grade). Walking along that
	## component is descending; against it is climbing.
	var down := Vector3(floor_normal.x, 0.0, floor_normal.z)
	var steep := down.length()
	if steep < 0.001 or move_dir.length_squared() < 1e-8:
		return 1.0
	var along := move_dir.normalized().dot(down / steep)
	return clampf(1.0 + along * steep * SLOPE_GAIN, SLOPE_MIN, SLOPE_MAX)


static func surface_mult(family: String) -> float:
	## Unknown ground is ordinary ground -- a new StepAudio family should change
	## how the world sounds without silently halving your speed.
	return float(SURFACE.get(family, 1.0))


## ===========================================================================
##  4. THE WADE
## ===========================================================================

static func wade_amount(hidden: bool, density: float, blade_height: float) -> float:
	## 0 = bare ground, 1 = the chest-high stuff you can hide in. `hidden` is the
	## Player's own grass_hidden, which GrassSystem already writes every frame --
	## the stealth read and the wade are the SAME patch, by construction, so you
	## can never be concealed by grass that is not slowing you down.
	##
	## `density` is GrassPaint's 0..1 (a painted-bare cell wades you not at all),
	## and `blade_height` is the live grass style's -- Woven turf is thicker than
	## the default and should drag a little more for it.
	if hidden:
		return 1.0
	var h := clampf(blade_height / BASE_BLADE, 0.0, 2.5)
	return clampf(clampf(density, 0.0, 1.0) * h * SHORT_WADE, 0.0, 1.0)


static func wade_mult(wade: float) -> float:
	return 1.0 - WADE_DRAG * clampf(wade, 0.0, 1.0)


static func compose(base: float, surface: float, wade: float, slope: float) -> float:
	## One place where the ground's three opinions are multiplied together, so a
	## bog on a hillside under deep grass cannot stack into a standstill.
	return base * clampf(surface * wade_mult(wade) * slope, 0.30, 1.25)
