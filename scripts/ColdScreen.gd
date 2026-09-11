class_name ColdScreen

# =============================================================================
#  ColdScreen -- what the cold LOOKS like (2026-09-11 06:00, POLISH).
#
#  Exposure has handed the caller a `felt` in degrees and a `sway_extra()`
#  every frame since 4ac02b1 and nothing read either: the cold had no screen
#  language at all. Slumber (1978496) then made that a real hole rather than a
#  cosmetic one -- the game now wakes you in the dark at warmth 28 as a
#  DESIGNED BEAT, and the only thing on screen saying why was one line of log
#  text.
#
#  THE DIVISION THIS FILE IS BUILT ON: the cold shows up in two places that
#  are not the same signal, and conflating them is what makes a cold filter
#  feel like a filter.
#
#    * BREATH is the AIR. It reads `Exposure.ambient_c()` -- not `felt`, not
#      `warmth` -- so you can stand at a roaring fire on a winter morning,
#      perfectly warm, and still see your own breath. That is true, and it is
#      the detail that sells a season. It is also the EARLY half: breath
#      appears long before anything is wrong with you, which is exactly what
#      an atmospheric cue is for.
#
#    * SHIVER and the GRADE are the BODY. They read `warmth`, they start at
#      `Exposure.WARMTH_LOW` and deepen to `Exposure.WARMTH_NUMB`, and above
#      the shiver line the screen is untouched and costs nothing to draw.
#
#  THE THRESHOLD WAS MEASURED, NOT CHOSEN. A probe printed the real
#  `ambient_c` table over four seasons and six hours before a constant in
#  this file existed, and `BREATH_C` was set against it:
#
#      spring   6.9   5.0   8.5  14.0  14.5  11.1      (h00 h04 h08 h12 h16 h20)
#      summer  14.9  13.0  16.5  22.0  22.5  19.1
#      autumn   4.9   3.0   6.5  12.0  12.5   9.1
#      winter  -7.1  -9.0  -5.5   0.0   0.5  -2.9
#
#  At 7 degrees WINTER breathes at every hour of the day, AUTUMN breathes
#  from dusk to dawn and stops by mid-morning, SPRING breathes only in the
#  hour or two either side of four in the morning, and SUMMER never breathes
#  at all. Nothing else in the file had to be tuned to get that: the season
#  table already had the shape, and one number found it. A threshold at 2
#  would have cost autumn its mornings; one at 12 would have put breath on a
#  summer afternoon.
#
#  Weather and altitude come along for free because they are already in
#  `ambient_c`: an autumn gale breathes like deep winter, and climbing to
#  nine hundred metres gives an autumn morning its breath back.
#
#  A SHIVER IS A BOUT, NOT A LEVEL. Shivering comes in bursts with quiet in
#  between, and that is the one piece of genuine STATE in this file: once a
#  bout has started it runs its course even if you step to a fire halfway
#  through, so it is a thing that can be CAUGHT IN by a turn in your
#  circumstances rather than a query on them. The pure half says how hard the
#  body wants to shiver; the sim owns whether it is shaking right now.
#  (Crofts' washing line, Carcasses' arrival, Slumber's waking -- same rule.)
#
#  NO FIFTH NUMBER FOR THE RUNGS. `shiver_grade()` is asserted equal to
#  `int(Exposure.sway_extra())` for every warmth: this file borrows the two
#  rungs the project already had rather than inventing its own, so a designer
#  moving WARMTH_LOW moves the sway, the stamina tax, the HUD bar's colour
#  and the screen together.
#
#  This file draws no random numbers. Every value below is a function of
#  warmth, of the air, and of how hard you are working -- which is what makes
#  a headless suite able to walk a whole night of it. The only jitter in the
#  picture comes from the camera-shake path that was already there.
#
#  Dev affordance: `readout()`, read-only. NO NEW BINDING: this file declares
#  no event hook and claims no key, asserted against the source in
#  ColdScreenTests `no_bindings`. (That assertion is a NEGATIVE source scan,
#  which has gone red on the comment explaining it three rounds running, so
#  the words it looks for are deliberately not spelled anywhere above.)
# =============================================================================


# ===========================================================================
#  Breath -- a function of the air
# ===========================================================================

## Air at or below this and your breath shows. See the table in the header:
## this one number is what gives winter every hour, autumn its nights, spring
## its dawns and summer none.
const BREATH_C := 7.0

## Degrees below BREATH_C for a full plume. At -2 the breath is as thick as
## it gets, which a winter night clears before midnight.
const BREATH_SPAN_C := 9.0

## Below this the plume is too thin to be worth a draw call, so the effective
## air threshold is a little under BREATH_C rather than exactly at it -- a
## breath you can barely see is worse than none.
const BREATH_MIN := 0.12

## Seconds between exhales, at rest and at full exertion. Breathing rides the
## work you are doing, never a fixed timer: sprint up a hill in the cold and
## the plumes come three times as often, which is the whole reason to take
## the signal off the body instead of off a clock.
const BREATH_CALM_S := 4.2
const BREATH_HARD_S := 1.5

## How long one exhale hangs.
const BREATH_PUFF_S := 0.9

## The size of one breath quad, in METRES. This lives on the mesh and not on
## the process material's per-particle scale because `BILLBOARD_PARTICLES`
## ignores that scale -- which is how the first draft drew one-metre quads
## forty-five centimetres from the eye. Twelve centimetres at that range is a
## wisp; the live pass is the only thing that could have told us which.
const BREATH_QUAD_M := 0.12

## A hard breath is a bigger cloud as well as a more frequent one.
const BREATH_WORK_SIZE := 0.45


# ===========================================================================
#  Shiver -- a function of the body
# ===========================================================================

## A bout at the shiver line, and a bout once your hands have gone.
const BOUT_LEN_LOW := 1.6
const BOUT_LEN_NUMB := 3.4

## Quiet between bouts. At the numb line this reaches zero, which is how
## shivering becomes continuous without a special case for it.
const BOUT_GAP_LOW := 5.5
const BOUT_GAP_NUMB := 0.0

## What a bout is worth as a camera-shake impulse. Deliberately fed into the
## EXISTING `Player.cam_shake` path rather than writing `camera.position`:
## that line is already owned, already decays, and already loses to a real
## impact, which is the correct priority.
const SHAKE_LOW := 0.030
const SHAKE_NUMB := 0.085


# ===========================================================================
#  The grade -- a function of the body
# ===========================================================================

## Never all the way to grey: a fully desaturated screen reads as a death
## screen, and this is a warning, not an ending.
const GRADE_SAT := 0.55
const GRADE_BLUE := 0.35
const GRADE_VIGNETTE := 0.50

## Frost is the NUMB language, the second rung, the same place `sway_extra`
## doubles and `windup_mult` starts costing you swings.
const FROST_MAX := 0.85


# ===========================================================================
#  The waking
# ===========================================================================

## A held black and a fade. Waking cold holds longer and comes up slower --
## the difference between opening your eyes and dragging them open.
const WAKE_HOLD_S := 0.45
const WAKE_FADE_S := 1.8
const WAKE_COLD_HOLD_S := 1.1
const WAKE_COLD_FADE_S := 2.9


# ===========================================================================
#  State -- and there is only this much of it
# ===========================================================================

var bout_t := 0.0        ## seconds left in the bout being shaken RIGHT NOW
var gap_t := 0.0         ## seconds of quiet left before the next one
var breath_t := 0.0      ## seconds until the next exhale
var wake_t := 0.0        ## seconds left of the waking fade
var wake_total := 0.0    ## how long that fade was, so it can be normalised
var wake_hold := 0.0     ## of which this much is held fully black

var _rect: ColorRect
var _mat: ShaderMaterial
var _puff: GPUParticles3D
var _last: Dictionary = {}


# ===========================================================================
#  Pure -- no node, no clock, no tree
# ===========================================================================

static func breath_amount(amb: float) -> float:
	## How thick the plume is, 0 for air nobody would see their breath in.
	var a := clampf((BREATH_C - amb) / BREATH_SPAN_C, 0.0, 1.0)
	return 0.0 if a < BREATH_MIN else a


static func breathes(amb: float) -> bool:
	return breath_amount(amb) > 0.0


static func exertion_of(sprinting: bool, stamina01: float) -> float:
	## How hard you are working, 0..1. Sprinting is the whole of it; short of
	## that, a drained meter is the tell -- a man at a third of his wind is
	## breathing hard whether or not he is still running.
	if sprinting:
		return 1.0
	return clampf(1.0 - clampf(stamina01, 0.0, 1.0), 0.0, 1.0)


static func breath_interval(exertion: float) -> float:
	return lerpf(BREATH_CALM_S, BREATH_HARD_S, clampf(exertion, 0.0, 1.0))


static func puff_size(amb: float, exertion: float) -> float:
	## Thicker air and harder work both make a bigger cloud.
	return breath_amount(amb) * (1.0 + BREATH_WORK_SIZE * clampf(exertion, 0.0, 1.0))


static func shiver_grade(warmth: float) -> int:
	## 0 steady, 1 shivering, 2 hands gone. THE SAME TWO RUNGS the rest of the
	## project already uses: this is asserted equal to `Exposure.sway_extra()`
	## for every warmth, so the screen cannot drift away from the model.
	if warmth < Exposure.WARMTH_NUMB:
		return 2
	if warmth < Exposure.WARMTH_LOW:
		return 1
	return 0


static func shiver_t(warmth: float) -> float:
	## 0 at the shiver line, 1 at the numb line and below -- the ramp every
	## bout number is drawn along.
	var span := Exposure.WARMTH_LOW - Exposure.WARMTH_NUMB
	if span <= 0.0:
		return 1.0 if warmth < Exposure.WARMTH_LOW else 0.0
	return clampf((Exposure.WARMTH_LOW - warmth) / span, 0.0, 1.0)


static func bout_len(warmth: float) -> float:
	return lerpf(BOUT_LEN_LOW, BOUT_LEN_NUMB, shiver_t(warmth))


static func bout_gap(warmth: float) -> float:
	return lerpf(BOUT_GAP_LOW, BOUT_GAP_NUMB, shiver_t(warmth))


static func shake_for(warmth: float) -> float:
	return lerpf(SHAKE_LOW, SHAKE_NUMB, shiver_t(warmth))


static func grade_t(warmth: float) -> float:
	## The grade opens exactly where the game says you are shivering and is
	## full at nothing left. Above the shiver line it is zero and the overlay
	## is hidden outright, so a warm player pays nothing for this file.
	if Exposure.WARMTH_LOW <= 0.0:
		return 0.0
	return clampf((Exposure.WARMTH_LOW - warmth) / Exposure.WARMTH_LOW, 0.0, 1.0)


static func frost_t(warmth: float) -> float:
	if Exposure.WARMTH_NUMB <= 0.0:
		return 0.0
	return clampf((Exposure.WARMTH_NUMB - warmth) / Exposure.WARMTH_NUMB, 0.0, 1.0)


static func look(warmth: float) -> Dictionary:
	## The whole picture as four numbers, for anything that wants to know what
	## the screen is doing without owning a viewport.
	var g := grade_t(warmth)
	return {
		"grade": g,
		"sat": GRADE_SAT * g,
		"blue": GRADE_BLUE * g,
		"vignette": GRADE_VIGNETTE * g,
		"frost": FROST_MAX * frost_t(warmth),
	}


static func air_c(e: Dictionary) -> float:
	## Exposure's real front door, and the only one this file has. Breath is
	## the AIR: a fire in the env dictionary must not warm it.
	return Exposure.ambient_c(e)



# ===========================================================================
#  The sim -- one call a frame, and the only state is the bout and the fade
# ===========================================================================

var bout_shake := 0.0    ## what the bout being shaken now is worth, fixed at its start


func step(e: Dictionary, warmth: float, exertion: float, delta: float) -> Dictionary:
	## Returns a REPORT and touches no node: `present()` is what puts it on a
	## screen, and the suite calls this without one.
	var d := maxf(0.0, delta)
	var amb := air_c(e)

	wake_t = maxf(0.0, wake_t - d)

	## --- Breath is an EVENT. An exhale is a thing that HAPPENS, written
	## down at the moment it does, not a level the presenter samples: derive
	## it and the one frame it occurs on is unreachable.
	var amount := 0.0 if bool(e.get("swimming", false)) else breath_amount(amb)
	var puff := false
	if amount <= 0.0:
		## Warm air resets the cycle, so stepping out into a frost gives you
		## a plume straight away instead of up to four seconds of nothing.
		breath_t = 0.0
	else:
		breath_t -= d
		if breath_t <= 0.0:
			breath_t = breath_interval(exertion)
			puff = true

	## --- The shiver. A bout RUNS ITS COURSE: warm up halfway through one
	## and you are still shaking, at the strength the bout began at.
	var grade := shiver_grade(warmth)
	var started := false
	if bout_t > 0.0:
		bout_t = maxf(0.0, bout_t - d)
		if bout_t <= 0.0:
			gap_t = bout_gap(warmth)
			bout_shake = 0.0
	elif grade > 0:
		gap_t = maxf(0.0, gap_t - d)
		if gap_t <= 0.0:
			bout_t = bout_len(warmth)
			bout_shake = shake_for(warmth)
			started = true
	else:
		gap_t = 0.0

	var rep: Dictionary = look(warmth)
	rep["amb"] = amb
	rep["breath"] = amount
	rep["puff"] = puff
	rep["puff_size"] = puff_size(amb, exertion) if puff else 0.0
	rep["rung"] = grade
	rep["bout"] = bout_t > 0.0
	rep["started"] = started
	rep["shake"] = bout_shake if bout_t > 0.0 else 0.0
	rep["blackout"] = blackout()
	_last = rep
	return rep


func blackout() -> float:
	## 1 while the waking is held black, then down to 0 over the fade.
	if wake_t <= 0.0 or wake_total <= 0.0:
		return 0.0
	var fade := wake_total - wake_hold
	if fade <= 0.0:
		return 0.0
	## The HOLD needs no branch of its own: while it is running, `wake_t` is
	## larger than the fade, so the ratio is over one and the clamp is already
	## returning exactly 1.0. A first draft had an explicit `if wake_t > fade:
	## return 1.0` above this line, and the mutation sweep removed it with
	## nothing moving at all -- a redundancy rather than a missing test, so
	## the line went rather than an assertion being manufactured for it.
	return clampf(wake_t / fade, 0.0, 1.0)


func wake(cold: bool) -> void:
	## Slumber's waking, given weight. A night that ended at four in the
	## morning because the fire went out should not open the same way as one
	## that ran to dawn: it holds longer, comes up slower, and OPENS ON A
	## SHAKE. Until this, the difference between the two was one line of log.
	wake_hold = WAKE_COLD_HOLD_S if cold else WAKE_HOLD_S
	wake_total = wake_hold + (WAKE_COLD_FADE_S if cold else WAKE_FADE_S)
	wake_t = wake_total
	if cold:
		bout_t = BOUT_LEN_NUMB
		bout_shake = SHAKE_NUMB
		gap_t = 0.0


func reset() -> void:
	## Death, respawn, a load. Nothing about the last body carries over.
	bout_t = 0.0
	gap_t = 0.0
	breath_t = 0.0
	wake_t = 0.0
	wake_total = 0.0
	wake_hold = 0.0
	bout_shake = 0.0
	_last = {}


# ===========================================================================
#  The presenter -- the only part that owns a node
# ===========================================================================

const OVERLAY_SHADER := """
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float sat_drop  : hint_range(0.0, 1.0) = 0.0;
uniform float blue_push : hint_range(0.0, 1.0) = 0.0;
uniform float vignette  : hint_range(0.0, 1.0) = 0.0;
uniform float frost     : hint_range(0.0, 1.0) = 0.0;
uniform float blackout  : hint_range(0.0, 1.0) = 0.0;

float h21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// Cheap Worley. THE VEINS ARE THE CELL BOUNDARIES, which means the SECOND
// nearest seed minus the nearest -- not the distance to the nearest, which
// is what the first draft returned and which the live pass showed up at once
// as a screenful of round white BOKEH BLOBS rather than ice. Frost is a web
// of thin bright lines; the only place a web lives in a Worley field is
// where two cells meet, so the loop has to keep both distances.
float veins(vec2 uv) {
    vec2 g = uv * vec2(26.0, 15.0);
    vec2 ip = floor(g);
    vec2 fp = fract(g);
    float best = 8.0;
    float b2 = 8.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 o = vec2(float(x), float(y));
            vec2 s = o + vec2(h21(ip + o), h21(ip + o + 17.0)) - fp;
            float dd = dot(s, s);
            if (dd < best) { b2 = best; best = dd; } else if (dd < b2) { b2 = dd; }
        }
    }
    return 1.0 - smoothstep(0.0, 0.085, sqrt(b2) - sqrt(best));
}

void fragment() {
    vec2 uv = SCREEN_UV;
    vec3 c = texture(screen_tex, uv).rgb;

    // The colour goes out of the world before the light does.
    float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
    c = mix(c, vec3(l), sat_drop);
    c = mix(c, c * vec3(0.80, 0.93, 1.20), blue_push);

    float d = distance(uv, vec2(0.5)) * 1.42;
    c *= 1.0 - smoothstep(0.30, 1.0, d) * vignette * 0.85;

    if (frost > 0.001) {
        // Frost grows IN FROM THE EDGES, the way it does on a window.
        float edge = smoothstep(0.34, 1.02, d);
        float m = clamp(frost * edge * veins(uv), 0.0, 1.0);
        c = mix(c, mix(vec3(0.74, 0.86, 1.0), c, 0.28), m);
    }

    c *= 1.0 - clamp(blackout, 0.0, 1.0);
    COLOR = vec4(c, 1.0);
}
"""


func attach(head: Node3D, hud: CanvasLayer) -> void:
	## Idempotent: a second call rebuilds nothing.
	if hud != null and _rect == null:
		var sh := Shader.new()
		sh.code = OVERLAY_SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_rect = ColorRect.new()
		_rect.name = "ColdScreen"
		_rect.material = _mat
		_rect.color = Color(1, 1, 1, 1)
		_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rect.visible = false
		hud.add_child(_rect)
		hud.move_child(_rect, 0)     ## under every bar and label, over the world
	if head != null and _puff == null:
		## EVERY NUMBER BELOW WAS SET BY LOOKING AT IT, and the first draft of
		## this block put a WHITE WALL across two thirds of the screen. Three
		## separate causes, none of them visible from any pure function:
		##
		##  1. WORLD-SPACE particle coordinates were chosen so the cloud would
		##     be left behind as you turn -- but in world space `direction` is
		##     a world vector too, so the exhale sprayed along global -Z
		##     whichever way the head was pointing, which half the time is
		##     straight into the lens. For a puff that lives under a second,
		##     the cloud following the head is invisible and being sprayed in
		##     the face is not. (The assertion holding this is a NEGATIVE
		##     source scan, so the spelling it forbids is not written here --
		##     the fourth round running to be caught by its own comment.)
		##  2. `BILLBOARD_PARTICLES` ignores the process material's per-particle
		##     scale, so `scale_min/max` of five to thirteen CENTIMETRES drew
		##     quads at the mesh's own size, which was ONE METRE, forty-five
		##     centimetres from the eye. The size has to live on the MESH.
		##  3. A flat quad of uniform alpha is a visible SQUARE. Breath needs a
		##     radial falloff, which is a GradientTexture2D and no asset file.
		_puff = GPUParticles3D.new()
		_puff.name = "Breath"
		_puff.amount = 12
		_puff.one_shot = true
		_puff.emitting = false
		_puff.explosiveness = 0.35
		_puff.lifetime = BREATH_PUFF_S
		_puff.local_coords = true    ## see (1): direction must be head-relative
		_puff.position = Vector3(0.0, -0.13, -0.45)   ## out of the mouth, not the eyes
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0.0, -0.10, -1.0)   ## leaves angled down...
		pm.spread = 11.0
		pm.initial_velocity_min = 0.9
		pm.initial_velocity_max = 1.6
		pm.damping_min = 2.6
		pm.damping_max = 3.6
		pm.gravity = Vector3(0.0, 0.55, 0.0)       ## ...and rises as it slows
		pm.scale_min = 0.6
		pm.scale_max = 1.4
		var g := Gradient.new()
		g.set_color(0, Color(0.88, 0.92, 0.97, 0.18))
		g.set_color(1, Color(0.88, 0.92, 0.97, 0.0))
		pm.color_ramp = GradientTexture1D.new()
		(pm.color_ramp as GradientTexture1D).gradient = g
		_puff.process_material = pm
		var qm := QuadMesh.new()
		qm.size = Vector2(BREATH_QUAD_M, BREATH_QUAD_M)   ## see (2)
		var soft := Gradient.new()
		soft.set_color(0, Color(1, 1, 1, 1))
		soft.set_color(1, Color(1, 1, 1, 0))
		soft.add_point(0.45, Color(1, 1, 1, 0.72))
		var round_tex := GradientTexture2D.new()
		round_tex.gradient = soft
		round_tex.fill = GradientTexture2D.FILL_RADIAL
		round_tex.fill_from = Vector2(0.5, 0.5)
		round_tex.fill_to = Vector2(1.0, 0.5)
		round_tex.width = 64
		round_tex.height = 64
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		sm.vertex_color_use_as_albedo = true
		sm.disable_receive_shadows = true
		sm.albedo_color = Color(1, 1, 1, 1)
		sm.albedo_texture = round_tex             ## see (3)
		qm.material = sm
		_puff.draw_pass_1 = qm
		head.add_child(_puff)


func present(rep: Dictionary) -> void:
	if _rect != null and _mat != null:
		var black := float(rep.get("blackout", 0.0))
		var on := float(rep.get("grade", 0.0)) > 0.0 or black > 0.0
		_rect.visible = on
		if on:
			_mat.set_shader_parameter("sat_drop", float(rep.get("sat", 0.0)))
			_mat.set_shader_parameter("blue_push", float(rep.get("blue", 0.0)))
			_mat.set_shader_parameter("vignette", float(rep.get("vignette", 0.0)))
			_mat.set_shader_parameter("frost", float(rep.get("frost", 0.0)))
			_mat.set_shader_parameter("blackout", black)
	if _puff != null and bool(rep.get("puff", false)):
		var sz := clampf(float(rep.get("puff_size", 0.0)), 0.0, 1.5)
		_puff.scale = Vector3.ONE * lerpf(0.72, 1.5, sz / 1.5)
		_puff.restart()
		_puff.emitting = true


func has_overlay() -> bool:
	return _rect != null


func readout() -> String:
	if _last.is_empty():
		return "cold: nothing stepped yet"
	return "cold: air %.1fC breath %.2f rung %d bout %s shake %.3f / sat %.2f vig %.2f frost %.2f black %.2f" % [
		float(_last.get("amb", 0.0)), float(_last.get("breath", 0.0)),
		int(_last.get("rung", 0)), str(bool(_last.get("bout", false))),
		float(_last.get("shake", 0.0)), float(_last.get("sat", 0.0)),
		float(_last.get("vignette", 0.0)), float(_last.get("frost", 0.0)),
		float(_last.get("blackout", 0.0)),
	]
