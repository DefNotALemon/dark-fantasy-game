# Myrkfell — sky, clouds & weather (v1)

Built 2026-08-23. Five files, one patcher, no new assets — every texture is
procedural noise in a shader and every sound is synthesised at boot.

| File | What it is |
|---|---|
| `shaders/sky.gdshader` | the sky: gradient, sun, clouds, stars, aurora, storm, lightning |
| `scripts/SkyRig.gd` | installs the shader, feeds it the sun and the wind |
| `scripts/Weather.gd` | the five-level weather ladder, rain, thunder, the aurora roll |
| `scripts/SkyMenu.gd` | the `'` dev menu: scrub time, force weather, throw bolts |
| `tools/patch_sky.py` | wires all of it into World / DayNight / Wind / Player |
| `assets/sky/previews/sky_states.png` | 14 rendered states, proof it works |

Run the patcher once from the repo root:

```
python3 tools/patch_sky.py
```

It is anchored, re-runnable, and leaves a `.bak` beside every file it edits.

---

## 1. Who owns what

The clock did not move. `DayNight.gd` still owns the hour, the sun and moon
transforms, and the ambient/fog targets `World._process` lerps toward. What
changed is that it no longer **paints** — `SkyRig` hands it `sky_mat = null`,
its existing `if sky_mat:` guard does the rest, and the shader takes over.

```
DayNight   the clock, the sun wheel, ambient + fog targets
SkyRig     everything you see up there
Weather    rain, thunder, the aurora roll — talks to SkyRig and Wind
Wind       one breeze for the whole world; the sky reads it too
```

Process order matters and is set explicitly: DayNight (0) → SkyRig (10) →
Weather (20). SkyRig reads the sun transform DayNight wrote *this* frame.

---

## 2. The sky shader

One `sky()` function, driven almost entirely by **the sun's real elevation**
rather than by the hour. Feed it a different sun and the whole sky follows.

```
day   = smoothstep(-0.03, 0.25, sun.y)   full daylight
dusk  = 1 - smoothstep(0.10, 0.35, |sun.y|)   peaks with the sun ON the horizon
night = 1 - smoothstep(-0.16, -0.01, sun.y)
```

**The pink hour** is three things stacked: the sky washes toward
`dusk_horizon` (a hot pink) weighted low and toward the sun; a warm
`dusk_glow` bloom wraps the sun itself at `pow(sun_dot, 5)`; and the clouds
sample their lit colour from the same pink instead of white. All three ride
the one `dusk` factor, so there is exactly one knob for "how pink".

**Stars** are a hashed grid in spherical UV — one cell per star, jittered
position, per-star twinkle rate, hidden behind clouds and gloom.

**Storm gloom** desaturates toward slate and drops exposure. It is separate
from cloud darkness on purpose: an overcast day is grey-bright, a storm is
grey-*dark*, and you want to dial them independently.

### Clouds: the toggle

`cloud_mode` — 0 off, 1 painterly, 2 volumetric. Settings → **Clouds**.

**Painterly (1)** — two scrolling fbm layers projected on a dome. The lit
edge is the trick worth knowing: it resamples the noise shifted *toward the
sun*, and where density falls off in that direction, that's a sunlit rim. One
extra fbm call buys the entire silver lining. Roughly free; this is the
default and what most players should run.

**Volumetric (2)** — marches 20 steps through a slab of 3D noise between
`vol_base` and `vol_base + vol_thick`, with two shadow taps toward the sun per
step. The shadow taps are the whole point: they give a cloud a bright top and
a dark belly instead of a flat white blob. Costs real GPU — it is per-pixel
raymarching on every pixel of open sky.

Two details that were bugs first:

- The march start is **jittered per pixel** (`hash21(SCREEN_UV * 1024)`).
  Without it, 20 steps band into visible slabs — you see the sampling, not
  the cloud.
- Detail noise **erodes** the base shape (`base - (1-detail) * 0.22`) rather
  than adding to it. Adding just raises the average and the deck turns to fog.

Tuning handles, all exposed as uniforms: `vol_freq` (puff size — lower is
bigger), `vol_far` (march cutoff near the horizon), `vol_brightness`,
`vol_base` / `vol_thick` (where the deck sits, in metres).

### One shader rule worth remembering

`TIME` only exists inside `sky()`. Touching it from a helper function is a
**compile error**, not a warning — and headless Godot will not catch it,
because the dummy renderer never compiles shaders at all. `cloud_density()`
takes time as a parameter for exactly this reason.

---

## 3. The weather ladder

```
0 CLEAR     open sky
1 OVERCAST  deck closes in, colour drains, no rain
2 DRIZZLE   thin rain, quiet, everything goes wet
3 RAIN      real rain, splashes, the sun is gone
4 STORM     black bellies, sheets of rain, wind at full, THUNDER
```

**Thunder only ever happens at STORM.** That is what the ladder is for.

It walks itself: a level holds 150–900 s, then rolls the next one off
`TRANSITIONS` — a sticky matrix that mostly moves one rung at a time, because
Maine does not go from blue sky to thunder. Season biases the roll (summer
clears but throws real thunderheads; winter is overcast and rarely violent).
Transitions slide over 25 s; nothing snaps.

`LOOKS` is the whole art direction in five rows: coverage, cloud darkness,
gloom, fog multiplier, rain rate, wind. Retune the weather there and nowhere
else.

**Rain** is one `GPUParticles3D` riding above the camera with
`local_coords = false`, so the drops stay put in the world when you walk
instead of being dragged along. Streaks are Y-billboards (vertical, turning
to face you). A second flat emitter at your feet does splashes above
`intensity 0.15`. Wind leans the fall sideways. Underground it switches off.

**Snow** in winter: the same emitter with a different mesh, slower fall,
turbulence on, no splashes, no thunder, and the audio drops 18 dB — the
silence is the point.

**Wetness** rises fast and dries slow (`0.35/s` up, `0.04/s` down), published
as the global shader parameter `weather_wetness`. Nothing reads it yet — it is
there for when ground, bark and stone want to darken in the rain.

### Lightning

`strike(distance01)` fires a bolt. A bolt is:

1. a flash light — a real `DirectionalLight3D` pulsed for ~0.2 s, because a
   flash has to light the **world**, not just the sky, or it reads as a bug;
2. one to three sub-strokes, because real lightning flickers;
3. thunder queued with a delay proportional to distance.

The light/sound gap **is** the distance. Real seconds would be 15 for 5 km, so
it is compressed to at most 6 — still long enough that a close one lands
before you have finished flinching.

### Audio — all of it synthesised

No `.wav` files, no import step, no licensing. Generated once at boot, at
11 kHz (thunder has no highs to lose):

- **Thunder** is brown noise, a stack of decaying "rolls", and a two-pole
  low-pass. Distance is just a heavier low-pass plus a slower swell — near
  bolts get a sharp white-noise crack in the first 90 ms, far ones don't.
  Three banks: near, mid, far.
- **Rain** is filtered hiss, two seconds, with the tail cross-faded over the
  head so it loops without a click. The same loop is a drizzle at −26 dB and
  a downpour at −6.

This is the first audio in the game. It plays on `Master`.

---

## 4. Northern lights

Every night, once, the sky rolls for an aurora. Top of `Weather.gd`:

```gdscript
const AURORA_CHANCE := 0.04           ## <-- CHANGE THIS ONE (0.0 .. 1.0)
const AURORA_WINTER_BONUS := 3.0      ## odds x3 in winter, x1.6 in autumn
const AURORA_MAX_CLOUD := 0.55        ## a closed sky hides them
const AURORA_BRIGHTNESS := 0.85
```

`0.04` is about one night in twenty-five, which is what keeps them a story.
**Set it to `1.0` for a personal build** and you get them every clear night.
There is also `aurora_forced = true`, settable from anywhere, for an instant
show without touching the constant.

Three quiet rules on top of the roll: a cloud deck past `AURORA_MAX_CLOUD`
curtains them off (so a storm never shows lights), only a quarter of showings
are the full sky-wide display — the rest are a faint green smear low in the
north — and they bloom in over 90 seconds rather than switching on.

In the shader they're three stacked wavy bands built from fbm, with a vertical
ray shimmer, drifting between green and violet by height and noise, and
confined to a band above the horizon. They sit *behind* clouds and add on top
of the stars.

---

## 5. The two bugs this pass fixed on the way past

**Seasons never advanced.** `World.gd` called `Wind.publish_season(0.0)` at
boot and nothing ever called it again — there was no day counter anywhere.
`season_phase` has been pinned at spring since the trees v2 work shipped, so
autumn colour, defoliation, marcescence and snow (spec §7) were all dead code
in practice. `DayNight` now counts days, publishes the season when midnight
rolls over, announces the turn of each season through `title_cb`, and saves
and loads `day` alongside `hour`.

**The sun set an hour and a half early.** The arc was a plain 24-hour wheel
anchored at 06:00, which crossed the horizon at exactly 18:00 — while the
art keyframes put the orange dusk at 19:30 and `NIGHTFALL_HOUR` at 20:36.
Nobody could see it before, because the procedural sky's colours came from
the keyframe table rather than the sun. A physically-lit sky shows it
instantly: the sky went black while the fog was still orange.

The arc is now pinned to the day the game already authored — horizon at
`DAWN_HOUR`, horizon again at `NIGHTFALL_HOUR`, highest halfway between
(13:18). Long summer days, and the pink hour lands on the orange keyframe.

Consequence: `START_HOUR` moved 17.0 → **19.7**, so the game boots into the
pink hour the way it used to boot into dusk. One constant, easy to put back.

---

## 5a. The sky menu — `'`

`scripts/SkyMenu.gd`, on the apostrophe key, alongside the other dev panels
(G creative, M spawn). It owns no state: every control writes straight into
DayNight / Weather / SkyRig, and every readout is read back the same frame, so
the panel cannot drift out of sync with the world.

**Time** — a live `19:42 · Day 54 · Autumn` readout, a scrub bar across the
whole 24 hours, and jump buttons: Dawn 6:00, Morning 9:00, Noon 13:18,
Golden 19:30, Dusk 20:20, Night 22:30, Midnight. Speed is
Frozen / 1x / 10x / 60x / 300x — **Frozen** is the one that earns its keep:
park the sun mid-sunset and go walk around in it.

**Calendar** — day ±1 / ±7 / +1 season, and four buttons that jump straight to
the first day of Spring / Summer / Autumn / Winter in the current year. This is
how you look at the foliage ramps, the marcescent oak, the conifer snow and
(later) the hare and ermine coats without playing for eight real hours.

**Weather** — the five levels, Snap vs. Ease-25s, and Auto vs. Hold (the same
lock a scripted moment uses). Four lightning buttons by distance, which work at
any weather level even though the storm itself only throws bolts at Storm.

**Sky** — cloud mode (kept in sync with the Settings row and saved with it), a
coverage slider, and an aurora override: Normal hands it back to the nightly
roll, while Off / Faint / Full pin it regardless of the hour, the roll, and the
cloud deck.

The lit button in each row follows **the world**, not your last click — set the
weather from code and the panel updates itself.

`DayNight.time_scale` is new and exists for this menu. Nothing else should
write it.

---

## 6. Public API

```gdscript
var w := World.weather()

w.set_weather(Weather.Level.STORM)          # slide over 25 s
w.set_weather(Weather.Level.STORM, true)    # snap
w.lock_weather(Weather.Level.STORM)         # hold it — Katahdin's storm crown
w.release_weather()
w.strike(0.2)                               # one bolt, close
w.aurora_forced = true
w.is_raining()  /  w.level_name()  /  w.intensity  /  w.wetness

World.set_cloud_mode(0|1|2)                 # also the settings row
```

---

## 7. Budget notes

- Painterly clouds: 2 fbm (5 octaves) + 1 for the lit edge. Cheap.
- Volumetric: 20 steps × (1 fbm + 1 vnoise3) + 2 shadow taps at 2 octaves.
  This is the expensive setting. It halves its step and octave count in the
  cubemap pass, and the `Sky` resource runs `PROCESS_MODE_INCREMENTAL` so the
  radiance cubemap spreads across frames instead of re-rendering every one.
  If the MacBook struggles with 420 trees, drop the toggle to Painterly first.
- Rain: 2,600 particles at STORM, one draw call, scaled by `amount_ratio`
  rather than by rebuilding the emitter.
- Season change and weather change cost **zero** mesh rebuilds and zero
  allocations, same as the foliage system.

---

## 8. Verified

111 headless assertions (`tests/SkyTests.gd`, with `tests/StubWorld.gd`) against the real scripts: the
shader's uniform list vs. every parameter the scripts write, material
installation, the audio synthesis actually producing audible samples, the full
weather ladder, lightning queueing thunder with distance-proportional delay,
the cloud toggle reaching the shader, the aurora fading in and being curtained
by cloud, the sun sitting exactly on the horizon at `NIGHTFALL_HOUR`, wetness
rising and drying, save/load, and 600 simulated seconds without a crash. The
menu gets its own block: every time jump landing on the right sun elevation,
the clock string rounding to the minute (19.7 h is 41.999… minutes in float —
truncating printed 19:41 for an hour that is exactly 19:42), Frozen actually
freezing, season jumps staying inside the current year, Hold pinning the
weather against the clock, cloud mode routing through `World.set_cloud_mode`
and reaching the shader, the forced aurora beating both noon and a storm deck,
and the lit buttons tracking the world rather than the click.

Separately, the shader was compiled and rendered through a real GL renderer in
all three cloud modes — **headless Godot never compiles shaders**, so a
headless pass proves nothing about GLSL. That render pass is what caught the
`TIME`-in-a-helper error and the volumetric blowout, and it produced
`assets/sky/previews/sky_states.png`.

### Not yet verified in the live game

The patcher's edits to `World.gd` and `Player.gd` are anchored and checked,
but the game has not been launched with them. Watch for: framerate with
volumetric clouds + 420 trees, rain particles vs. the cave transition, and
whether `BASE_FOG * 3.4` at STORM is too thick to see the trees you are
trying to chop.
