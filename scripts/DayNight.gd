extends Node
class_name DayNight
## The sky's clock — a full Skyrim-pace day/night cycle: one game day every
## 20 real minutes (72× time). Owns the sun and the moon (directional lights)
## and publishes the SURFACE ambience targets (ambient energy + fog color) that
## World._process lerps toward — underground still overrides everything, so the
## caves stay midnight-black at noon.
##
## The 17:30 keyframe IS the game's original fixed dusk look: at that hour the
## world looks exactly the way it did before time existed. Dawn (~06:00) and
## nightfall (~20:36) fire the world-event titles through title_cb.

const DAY_SECONDS := 1200.0     ## 20 real minutes per 24 game hours
## Boot straight into the pink hour. (Was 17.0, which under the old sun wheel
## was the signature dusk; with the arc pinned to dawn/nightfall above, 19.7 is
## where that light lives now. One number — put it back if you miss it.)
const START_HOUR := 19.7
## Which day of the 96-day year a fresh world opens on. This is NOT cosmetic:
## foliage.gdshader defoliates by season_phase, and phase 0 is the FIRST day of
## spring — before the flush — so a world booted on day 0 stands every maple,
## birch and oak bare until game-day ~15, and only the evergreens keep a crown.
## 30 is mid-summer (phase 0.3125), which is also what Wind.gd declares as the
## global's default. Set to 0.0 for a bare-branch spring start.
const START_DAY := 30.0
const DAWN_HOUR := 6.0
const NIGHTFALL_HOUR := 20.6

var env: Environment                    ## set by World before add_child
var sky_mat: ProceduralSkyMaterial      ## set by World before add_child
var title_cb: Callable                  ## World's title hook (skips underground)

var hour := START_HOUR
## Days since the world began. One season is 24 of these, one year 96
## (Wind.DAYS_PER_SEASON) — this is what makes autumn ever arrive.
var day := START_DAY
## How fast the clock runs. 1.0 is the authored 20-minute day; 0.0 freezes the
## sun where it stands. The sky menu (' key) drives this — nothing else should.
var time_scale := 1.0
var sun: DirectionalLight3D
var moon: DirectionalLight3D

## What the surface looks like RIGHT NOW — World._process lerps the live
## Environment toward these when the player is above ground.
var surf_ambient := 0.45
var surf_fog := Color(0.42, 0.48, 0.46)
var sky_horizon := Color(0.40, 0.42, 0.40)   ## [water] what the lakes reflect

## Keyframes around the clock, blended smoothly (the table wraps past midnight):
## [hour, sky_top, sky_horizon, ambient, fog_color, sun_energy, sun_color, moon_energy]
const KEYS := [
	[0.0,  Color(0.030, 0.045, 0.085), Color(0.060, 0.085, 0.120), 0.10, Color(0.055, 0.075, 0.105), 0.00, Color(1.00, 0.91, 0.78), 0.30],
	[4.6,  Color(0.030, 0.045, 0.085), Color(0.060, 0.085, 0.120), 0.10, Color(0.055, 0.075, 0.105), 0.00, Color(1.00, 0.80, 0.60), 0.30],
	[6.0,  Color(0.140, 0.150, 0.260), Color(0.760, 0.470, 0.320), 0.30, Color(0.360, 0.360, 0.380), 0.55, Color(1.00, 0.72, 0.50), 0.05],
	[8.0,  Color(0.220, 0.320, 0.470), Color(0.520, 0.560, 0.540), 0.52, Color(0.470, 0.530, 0.500), 1.20, Color(1.00, 0.95, 0.85), 0.00],
	[13.0, Color(0.280, 0.410, 0.580), Color(0.560, 0.620, 0.600), 0.62, Color(0.500, 0.560, 0.530), 1.35, Color(1.00, 0.98, 0.92), 0.00],
	[17.5, Color(0.120, 0.160, 0.240), Color(0.400, 0.420, 0.400), 0.45, Color(0.420, 0.480, 0.460), 1.05, Color(1.00, 0.91, 0.78), 0.00],
	[19.5, Color(0.090, 0.100, 0.190), Color(0.780, 0.400, 0.240), 0.30, Color(0.300, 0.280, 0.300), 0.50, Color(1.00, 0.60, 0.38), 0.05],
	[21.0, Color(0.030, 0.045, 0.085), Color(0.060, 0.085, 0.120), 0.10, Color(0.055, 0.075, 0.105), 0.00, Color(1.00, 0.60, 0.38), 0.30],
]


func _ready() -> void:
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.91, 0.78)
	sun.shadow_enabled = true
	add_child(sun)
	## The moon: the frost-blue half of the accent palette, dim but honest —
	## nights are DARK, and a torch matters out there.
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.58, 0.66, 0.90)
	moon.light_energy = 0.0
	moon.shadow_enabled = false
	add_child(moon)
	_apply()


func _process(delta: float) -> void:
	var prev := hour
	hour = fmod(hour + delta * time_scale * (24.0 / DAY_SECONDS), 24.0)
	## Midnight rolled over: another day on the calendar, and the season with it.
	if hour < prev:
		day += 1.0
		Wind.publish_season(day)
		if title_cb.is_valid() and int(day) % int(Wind.DAYS_PER_SEASON) == 0:
			title_cb.call(Wind.season_name(day))
	if title_cb.is_valid():
		if _crossed(prev, hour, DAWN_HOUR):
			title_cb.call("Daybreak")
		elif _crossed(prev, hour, NIGHTFALL_HOUR):
			title_cb.call("Nightfall")
	_apply()


static func _crossed(a: float, b: float, mark: float) -> bool:
	## Did the clock tick past `mark` this frame? (Handles the midnight wrap.)
	if a == b:
		return false
	if a <= b:
		return a < mark and mark <= b
	return mark > a or mark <= b


func _sample() -> Array:
	## Blend the two keyframes around the current hour. Returns the same shape
	## as a KEYS row (index 0 is meaningless afterward).
	var n := KEYS.size()
	for i in range(n):
		var a: Array = KEYS[i]
		var b: Array = KEYS[(i + 1) % n]
		var h0 := float(a[0])
		var h1 := float(b[0]) + (24.0 if i == n - 1 else 0.0)
		var h := hour + (24.0 if (i == n - 1 and hour < h0) else 0.0)
		if h >= h0 and h < h1:
			var u := (h - h0) / maxf(h1 - h0, 0.001)
			u = u * u * (3.0 - 2.0 * u)  ## smoothstep — dawn BLOOMS, not flips
			return [0.0,
				(a[1] as Color).lerp(b[1] as Color, u),
				(a[2] as Color).lerp(b[2] as Color, u),
				lerpf(float(a[3]), float(b[3]), u),
				(a[4] as Color).lerp(b[4] as Color, u),
				lerpf(float(a[5]), float(b[5]), u),
				(a[6] as Color).lerp(b[6] as Color, u),
				lerpf(float(a[7]), float(b[7]), u)]
	return KEYS[0]


func _apply() -> void:
	var s := _sample()
	if sky_mat:
		sky_mat.sky_top_color = s[1] as Color
		sky_mat.sky_horizon_color = s[2] as Color
		sky_mat.ground_horizon_color = (s[2] as Color) * 0.55
		sky_mat.ground_bottom_color = Color(0.05, 0.06, 0.055)
	surf_ambient = float(s[3])
	surf_fog = s[4] as Color
	sky_horizon = s[2] as Color

	## Sun + moon ride one great wheel: 06:00 sunrise, 12:00 overhead, the moon
	## always directly opposite. The procedural sky draws the sun disc for free.
	## The arc used to be a plain 24-hour wheel, which crossed the horizon at
	## 18:00 — an hour and a half before the 19.5 dusk keyframe and 2.6 hours
	## before NIGHTFALL_HOUR. With a procedural sky nobody could see the
	## mismatch; with shaders/sky.gdshader, which reads the sun's real
	## elevation, the sky went black while the fog was still orange.
	##
	## So the arc is pinned to the day this game actually authored: the sun
	## crosses the horizon exactly at DAWN_HOUR and again at NIGHTFALL_HOUR,
	## and rides highest halfway between (13:18). Long summer days, and the
	## pink hour now lands on the orange keyframe where it belongs.
	var ang := 0.0
	var day_len := NIGHTFALL_HOUR - DAWN_HOUR
	if hour >= DAWN_HOUR and hour < NIGHTFALL_HOUR:
		ang = PI * (hour - DAWN_HOUR) / day_len
	else:
		var nh := hour - NIGHTFALL_HOUR
		if nh < 0.0:
			nh += 24.0
		ang = PI + PI * nh / (24.0 - day_len)
	if sun:
		sun.rotation = Vector3(-ang, deg_to_rad(-115.0), 0.0)
		sun.light_energy = float(s[5])
		sun.light_color = s[6] as Color
		sun.visible = float(s[5]) > 0.01
		sun.shadow_enabled = float(s[5]) > 0.05
	if moon:
		moon.rotation = Vector3(-ang + PI, deg_to_rad(-115.0), 0.0)
		moon.light_energy = float(s[7])
		moon.visible = float(s[7]) > 0.01
		moon.shadow_enabled = float(s[7]) > 0.10


func is_night() -> bool:
	## For the danger cycles to come (step 9): undead bolder in the dark.
	return hour >= NIGHTFALL_HOUR or hour < DAWN_HOUR
