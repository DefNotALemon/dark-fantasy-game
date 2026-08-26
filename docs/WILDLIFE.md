# Myrkfell — Wildlife (built spec)

**Status:** shipped 2026-08-23 into `dark-fantasy-game`. 68 species + 5 legends, live, and all 73
reachable from the M spawn menu.
The pick-list this came from is `claude/wildlife-roster.md` in the Myrkfell project; Lemon's
answer was "add it all in", so all of it is in.

**Test suite:** `tests/WildlifeTests.gd` — **3,319 assertions, all green**, run under headless
Godot against the **real** `Enemy.gd`, `HitFX.gd`, `Wind.gd`, `DayNight.gd` and a patched
`World.gd`, not a lab copy.

```
godot --headless --path . --script res://tests/WildlifeTests.gd
```

---

## 1. The shape of it

Eight files. The split is the whole design, and it is the same one that made trees-v2 work:
**a species is data, a body is a family, an action is a clip, and the brain is shared.**

| File | Lines | What it owns |
|---|---|---|
| `scripts/CritterDex.gd` | 1,099 | **Every species, as data.** Adding #74 is one entry and zero code. |
| `scripts/CritterRig.gd` | 1,223 | **14 rig families.** Parametric box bodies + the named-pivot contract. |
| `scripts/CritterAnim.gd` | 4,805 | **180 signature animations.** The part you asked for. |
| `scripts/Critter.gd` | 1,073 | The brain: 8 archetypes, seasons, specials, save/load. `extends Enemy`. |
| `scripts/Telegraph.gd` | 207 | The forest's alarm bus. |
| `scripts/CritterAudio.gd` | 316 | Calls, beds, and the animals that are never spawned. |
| `scripts/CritterSwarm.gd` | 220 | MultiMesh swarms — bats, fireflies, blackflies, monarchs. |
| `scripts/WildlifeDirector.gd` | 529 | Spawning, budgets, the calendar, events, legends. |
| `tools/crittercalls.py` | 1,972 | Synthesises all 42 animal calls from oscillators. No recordings. |
| `tools/patch_wildlife.py` | — | Wires it into `World.gd`. Re-runnable, keeps a `.bak`. |
| `tools/patch_spawn_menu.py` | — | Rebuilds the M spawn menu around the roster. Re-runnable, keeps a `.bak`. |
| `tools/patch_swat.py` | — | Points the sword/axe/pick damage frames at the swarm sweep. Re-runnable, keeps a `.bak`. |
| `tools/patch_swat2.py` | — | Moves the swing geometry out of `Player.gd` into `CritterSwarm.swat_from()`. |

### Why `Critter extends Enemy`

Because it means wildlife bleeds through the code path that already exists. `HitFX.kind_of()`
resolves every one of them as `flesh` on day one, so **Settings → Blood, the bestiary, the XP
ledger, the weapon-material tables, the infighting grudge, flinch, burn, and death all work on
wildlife with no second implementation to keep in sync.** `Boar.gd` already proved the pattern;
this is the same trick at 73× the scale.

What `Critter` does NOT inherit is the combat brain. `_physics_process` is replaced outright, and
`duelist` / `always_moving` / `strong_*` are all forced off in `_configure()` — otherwise the
inherited duelling code fights the archetype for the steering wheel.

---

## 2. `CritterDex` — the data layer

One `const DEX` dictionary. Per species: display name, rig family, AI archetype, body length and
height, health, damage, amble/run speeds, notice/panic radii, three palette colours, signature
animation list, call keys, **per-zone spawn weights**, feature flags (antlers, quills, mask,
stripes, ear tufts, bill shape…), behaviour flags, and a harvest table that the hunting loop can
read whenever it exists.

Zones are map v1's ten (`beacon_coast`, `freeport_road`, `mill_reaches`, `kennebec_seat`,
`western_peaks`, `moosehead`, `bangor_gate`, `katahdin`, `dawnwatch`, `county`) plus the habitats
that cut across them (`river`, `lake`, `bog`, `field`, `deep_woods`, `gulf`).

`is_awake(key, hour, phase)` is the single gate for time-of-day and calendar. It is what stops
owls spawning at noon, bears walking around in February, loons sitting on an iced lake, and snowy
owls existing in July. The spawner and the already-spawned animals both read it, so they can never
disagree.

**The natural history is asserted, not assumed.** The suite checks that the opossum has not reached
the County (they are genuinely new arrivals to Maine), that puffins are offshore and never in the
deep woods, that a lynx has bigger ear tufts and bigger paws than a bobcat, and that the garter
snake can never be made hostile — Maine has no venomous snakes and that stays true here.

---

## 3. Rig families — 14 skeletons, 73 animals

`CERVID · URSID · CANID · FELID · MUSTELID · CHUNK · RODENT_S · BIRD_GROUND · BIRD_RAPTOR ·
BIRD_PERCH · BIRD_WATER · HERP · FISH · SWARM`

A family owns a body *plan*; the dex owns the numbers. A marten is a fisher at 0.73 scale with a
bib, and neither needed new code. Everything is boxes in the game's existing no-texture language,
bodies face **−Z** like every other creature.

`build()` returns a pivot dictionary that is a **contract** — `root body neck head jaw tail tail2
crest quills fan dewlap shell spine`, arrays `legs knees ears wings segments`, plus `mats` and
`eye_mats`. `CritterAnim` addresses limbs by name and never reaches into the mesh tree.

Feature flags reaching geometry is asserted: the moose has antlers **and** its bell, the deer has
antlers and no bell, the porcupine has a quill set to raise, the turkey has a fan to spread, the
jay has a crest, the snake is a chain of ≥6 segments, the snapper has a carapace.

`eye_mats` carries **night eyeshine** — a coyote at the edge of your torchlight is two points of
light before it is a coyote.

---

## 4. The 180 signature animations

The thing you actually asked for. Every one is a **pure function of `t` (0..1)** — no stored
phase, no tweens — so a clip can be scrubbed, replayed, or run at any speed. Rest poses are
cached per rig, so every setter is rest-relative and `neutral()` restores exactly.

Measured, in the animation harness:

| | |
|---|---|
| `moose_dunk` | head drops **1.67 m below the body pivot**, submerged 62% of the clip |
| `mouse_dive` (fox) | apex 0.79 m at t=0.57, **77° nose-down** at impact — second difference of `root.y` constant to 0.00000, i.e. a real parabola |
| `head_track` (owl) | peak yaw **2.90 rad (166°)** with the body dead still |
| `log_drum` (grouse) | **48 beats**, first gap 0.339 s, last 0.164 s — accelerating, and locked to `grouse_drum.wav` thump for thump |
| `silent_glide` | wing z-range **0.03 rad**. It does not flap. That is the point. |
| `bob_walk` (woodcock) | body travels 0.086 m fore/aft, head travels **0.000 m** |
| `specter_fade` | alpha 0.12–0.74, emission to 2.75, fully restored by `neutral()` |

Poses that must **hold** are frozen, not oscillating: `tail_flag`, `quill_bristle`, `play_dead`,
`freeze_solid`, `freeze_crouch` all measure 0.00000 drift on their load-bearing pivot.
(`banana_pose` wobbles by 0.08 on purpose — holding that pose costs a seal real effort.)

`idle()` runs every frame underneath: breathing, drifting head, independent ear flicks, tail sway,
and knee counter-rotation so legs bend instead of swinging rigid. It drives only `knees` and never
fights `Enemy._update_locomotion`, which owns the hips.

---

## 5. The eight archetypes

- **SKITTER** — flee, and keep fleeing until there is real distance. Prey zigzags; a hare that runs
  in a straight line is a dead hare and also looks like a bug.
- **SENTINEL** — **shout first, run second.** The call is the whole reason this archetype exists.
- **BLUFFER** — the escalation ladder. How many rungs is `bold` in the dex (default 2: warn, warn
  harder, then mean it). Skunks end the ladder with spray instead of a charge.
  - **`relentless` takes the ladder away going down.** A relentless bluffer commits from the full
    warn radius instead of waiting for you to close, stays in the charge between hits instead of
    dropping back to a huff, has `nerve = 0`, cannot be spooked by a hit or by an alarm, and turns
    back around if something ever manages to put it to flight. It disengages on exactly one
    condition: you get past its `leash`.
  - **The bear is the one that has it** (Lemon, 2026-08-23). `bold: 1` — one warning, then it comes.
    Notices at 30 m, commits at 15 m, 240 HP, 38 damage, **10.2 m/s against a sprinting player's
    8.0**. You do not outrun a black bear; you fight it, you climb, or you put 58 m between you.
    That leash is the honest way out and the reason this is a fight rather than a death sentence.
  - The moose still bluffs properly at `bold: 2` — the test suite asserts that specifically, because
    if the bear change had leaked into the archetype instead of living in the dex, the moose is
    where it would show.

### The rear-up — `bear_stand`

The bear's opening move, and a real decision rather than a flourish. Three tables in `Critter.gd`
drive it, and all three are general: any species can be given a gated, rooted, paying move.

| | |
|---|---|
| `SIG_HEALTH_GATE` | **needs ≥ 2/3 health.** Below that the bear physically cannot rear up and opens with the huff instead. |
| `SIG_ROOTS` | **it stops dead.** While standing it does not steer, chase or swing — the archetype is skipped entirely, not merely asked to behave. It can still turn to keep you in front. |
| `SIG_PAYOFF` | **coming all the way down pays.** ×1.55 attack and ×0.65 damage taken for 18 s, and it cannot chain into a second one. |

Two consequences worth playing around:

- **Hurting the bear past a third takes the move away permanently for that fight.** The wounded bear
  is angrier and weaker at the same time, which is the reward for having got hits in.
- **Interrupting the rear-up denies the payoff outright.** The buff lands only on the full return to
  the ground, so a hit that knocks it out of the pose costs it the whole thing. `_end_sig()` at any
  point before `t = 1` grants nothing.

Idle flavour never picks a payoff move — rearing up is a decision the animal makes about *you*, and
a buff handed out by a random idle roll with nobody watching is a bug wearing an animation.

**The front feet now leave the ground.** They did not before, and the reason is worth recording:
`CritterRig` parents the hip pivots to `root`, not to `body` (because `Enemy._update_locomotion`
drives those hips directly and would fight anything that re-parented them), so rearing the body
lifted the chest and left all four paws nailed to the dirt — the bear grew upward out of its own
shoulders. The fix moves the front hip *pivots* on the arc a rearing quadruped actually travels:
about the hind feet, up by `sin θ` and back by `1 − cos θ` of the hip separation. Measured on the
real rig at the top of the rear: **front paw +1.24 m, hind paw +0.17 m** — a 7× ratio, asserted in
the suite so it cannot silently regress.
- **STALKER** — hunts other wildlife, not you. Withdraws and watches when a person turns up. Will
  not mark anything ≥95% its own size, so no lynx ever stalks a moose.
- **RAIDER** — goes for your stuff. Cases the camp, unlatches containers, freezes and stares when
  caught, then leaves with your dinner.
- **ENGINEER** — the beaver, alone. **Actually fells trees through the real `chop_hit` path.**
- **SCAVENGER** — finds the dead and circles it, visible from a long way off.
- **AMBIENT** — fish, swarms, the Aurora Herd. No fear, no hunger, no opinions.

---

## 6. The Forest Telegraph

One alarm bus. Every alarm does four things: prey inside the radius goes alert or flees; **the
nearest sentinel outside the middle of the ring relays it** after a short delay at 62% radius
(so the word *travels* rather than detonating, capped at 4 hops); predators reprioritise, because
running things are food; and the player can read it back.

`read_the_woods()` returns the HUD line — deliberately vague about *what*, because learning to read
it is the skill. `alarm_level_at()` lets the spawner refuse to refill a hillside that just emptied.

**The player is on the wire too.** `player_noise()` turns movement speed into an alarm: sprinting
through brush broadcasts at 34 m, a careful walk does not ring at all. That is the stealth mechanic,
and it is why a jay going off over the next rise is worth listening to — in a world with goblins in
the treeline, the forest rats them out as readily as it rats you out.

*Verified:* one ring at 40 m put 5 of 5 deer up, produced a real player-facing line, flagged the
patch as wound up, and did **not** make the coyote flee its own dinner bell.

---

## 7. Audio — built first, on purpose

`tools/crittercalls.py` synthesises **42 calls** from oscillators, noise and envelopes — no
recordings, no downloads, deterministic on `--seed 7717`, 4.8 MB total. Same philosophy as
`leafgen.py` and `barkgen.py`.

```
python3 tools/crittercalls.py --out assets/audio/wildlife
```

Loon wail / tremolo / yodel, barred owl's *who-cooks-for-you* in its real 4+4 phrasing, great
horned owl, coyote howl and chorus, the grouse's accelerating drum, spring peepers, raven, moose
bellow, bear huff, deer snort-wheeze, beaver slap, red squirrel scold, jay, crow, chickadee
*fee-bee* and *chicka-dee-dee-dee*, turkey gobble, woodcock peent and twitter, heron, goose honk
and skein, fisher scream, fox scream, lynx caterwaul, bullfrog, pileated drum and laugh, eagle,
osprey, snowy owl, porcupine moan, otter chirp, crickets, blackflies.

Two layers at runtime. **Beds** are one looping ambience per zone × hour × season, cross-faded —
peepers on a spring night over water, crickets on a summer one, blackflies over a late-spring bog,
and a winter night that is *silent*. **Calls** are one-shot and positional, with a per-species carry
distance: a loon reaches 260 m, a deer's snort 80 m.

And the layer that does most of the work: **the distant ones.** Most of the wildlife a player hears
in a session is never spawned. `_distant_tick()` picks a species plausible for this zone, hour and
season and puts its voice 70–180 m out. One `AudioStreamPlayer3D` buys more Maine than a herd.

---

## 8. Seasons

`is_awake()` gates existence; `Critter.set_clock()` gates appearance.

- **Coat swap** — hare and ermine ramp brown↔white off `season_phase`, lerped from cached original
  albedos so tints never compound. The ramp is deliberately offset from the calendar so an animal
  can be **caught out** — white on bare ground in a late autumn is real, and it is the best argument
  the whole system makes for itself. *Asserted at three phases.*
- **Denning** — bears are gone all winter.
- **Migration** — loons, ospreys, herons, geese, woodcock, wood ducks and vultures leave and return
  on per-species windows that wrap midwinter correctly.
- **Winter-only** — snowy owls, with irruption logic so some winters have none.
- **Season turn** culls anything that should no longer be here, so the world never keeps a loon on
  an iced-over lake.

### The calendar is DayNight's, not ours

`DayNight.day` counts days at the midnight rollover and calls `Wind.publish_season()` itself, with
a season-name title on the turn. Wildlife reads that clock and never keeps its own — two counters
that can disagree about what season it is would be worse than none.

*(Worth recording, because it cost a build: the World.gd snapshot this work started from had no day
counter at all and pinned `season_phase` to 0.0 forever. That was fixed in the repo mid-session,
along with a new `Weather.gd` and `SkyRig.gd`. The first version of `patch_wildlife.py` added its
own `_game_day`, which collided with the real one and produced a duplicate `"day"` key in
`save_state()`. Caught by importing the real project rather than reading it — the same lesson
TREES_v2_SPEC §21 wrote down. **Re-read `World.gd` before patching it.**)*

---

## 9. Events and legends

- **Goose skein** — spring and autumn, a V of honking crossing the whole sky as a moving sound at
  90 m altitude. No meshes. Cheapest "the world is bigger than you" effect in the game.
- **Big Night** — one warm rainy night in early spring, every frog and salamander crosses at once
  and the raccoons feast. Fires **once per game year**, tracked across save/load.

Legends are **placed, never rolled** — the spawn table refuses anything flagged `legend`, asserted
across every zone. Each has one condition and exactly one instance:

| | Condition |
|---|---|
| **The Specter Moose** | dusk/night in Moosehead country. Pale, half again scale, antlers like a dead tree. |
| **The Ghost Cat** | night, anywhere. Never attacks — `nofight`, damage zero. |
| **The Aurora Herd** | winter nights in the County. Nine spectral caribou, non-interactive. |
| **The King Snapper** | any beaver pond. |
| **The White Raven** | Katahdin. 1.5% per check. An omen. |

---

## 9a. The M spawn menu

`tools/patch_spawn_menu.py` rebuilds `Player._build_spawn_menu()`. The old one was a single column
of nine buttons; nine mobs plus 68 wild species plus 5 legends is 82, about twice the viewport, so
it is now a fixed 552×520 scroller of three-wide grids under headings:

`MOBS · BIG GAME · PREDATORS · CRITTERS · BIRDS · WATER & COLD BLOOD · SWARMS & BUGS · LEGENDS ·
WORLD · CAVE LAB`

**The wildlife rows are read out of `CritterDex` at runtime, not listed in `Player.gd`** — a species
added to the dex turns up in the menu with no edit here, which is the same promise the rest of the
system makes. `t_spawn_menu()` asserts total coverage: every rig family lands in exactly one bucket,
every non-legend species is listed exactly once, and 68 + 5 = the whole dex.

Details that matter:

- **Wildlife does not spawn `confused`.** A disoriented goblin wandering in circles is funny; a deer
  doing it just looks broken, and half the point of spawning one is to watch it behave.
- Spawns face **you**, so you see the front of the animal.
- Swarms route to `CritterSwarm.make()`, not `Critter.make()`.
- Everything spawned is **adopted by the director**, so it saves with the world and shows in the
  census — but it does *not* count against the spawn budget on the way in, because a dev spawn must
  never be refused for a full forest. (Natural spawning just pauses until the count falls back.)
- A hand-spawned **legend is not registered with the legend gate**, so spawning a Specter Moose at
  noon does not get it silently deleted a moment later by the condition check.
- Long names clip with the full name in the tooltip, rather than wrapping and blowing out the grid.

---

## 10. Specials

- **Quills** — swing at a porcupine and it costs you damage *and* leaves quills in you
  (`stick_quills`). Coyotes route through the same call, so they learn too. *Asserted.*
- **Spray** — the skunk's debuff is social: `apply_stink()` on the player, and every critter within
  20 m spooks. It cannot immediately do it again. *Asserted.*
- **Latch** — the snapper bites and holds for 4.5 s, dragging itself to you. *Asserted.*
- **Play dead** — the opossum collapses, jaw open, and holds; it fools coyote AI and it fools a
  player exactly once. *Asserted.*
- **Blackfly harassment** — the only swarm that touches you. Smoke within 7 m of a campfire stops it.
- **Swatting** — a weapon swing kills blackflies, and **two swings clear a cloud**: the sweep takes
  the nearest 60% of the swarm, so 60 → 24 → 0, with the sword or the axe. Fired from the **damage
  frame** of each weapon, so the flies die where the blade actually is rather than on the button
  press. Killed members go to a per-member respawn clock (18–34 s each, staggered), and harassment
  scales with the surviving share — one swing drops the bite rate from 0.900 to 0.360. It never
  *solves* them: there are sixty, they come back on their own clocks, and smoke is still the real
  answer. The swing is relief and it is satisfying, which is the whole design of it.
  - **The geometry lives in `CritterSwarm.swat_from()`, not in `Player.gd`.** It started in Player,
    where the suite could not reach it, and the suite therefore called `swat()` with a hand-picked
    point at the middle of the cloud — which passed, while the game anchored the sweep a metre in
    *front* of the player. Blackflies orbit your head, so most of the cloud sat behind the swing
    origin and a real swing killed **6 of 60**. The rule that came out of it: anything the player's
    swing depends on is tested through the player's own call path, never through a convenient inner
    one. `tools/patch_swat2.py` moved it.
  - Standing **inside** a cloud drops the arc test entirely — you are swatting around your own head,
    and a fly at your shoulder is as fair as one at your nose. Outside it, a swing still has to
    point at them; a swing pointed away from a cloud twelve metres off kills nothing.
  - **Only blackflies are `swattable`.** Everything else scatters — fireflies, monarchs and the luna
    moth blow apart for a second and all survive. An axe that murders the prettiest thing in the game
    for walking past it is a punishment, not a mechanic. A swing that hits nothing still scatters,
    so the blade reads as moving air rather than passing through a photograph.
  - The kill burst is **one** `HitFX.flesh` at the centroid of what died, not one per fly — sixty
    particle systems in a frame is a stutter, and a single pop mid-arc reads better. Red on purpose:
    a blackfly that has been on you for ten seconds is full of your blood. Blood: Off swaps it for a
    colourless puff with no special case.

---

## 11. Budget

`BUDGET = 26` live critters, `SWARM_BUDGET = 5`. Modest on purpose: the forest already costs 420
trees against a budget written for 250 (TREES_v2_SPEC §11), and a forest reads as alive at a
surprisingly low density. The trick is never *more* animals — it is the right animal in the right
place at the right hour, plus the audio layer carrying the ones that were never spawned.

Spawns land in a 26–62 m ring, preferentially behind the player, raycast onto the ground, and are
refused where the Telegraph says the woods just went up. Despawn at 96 m, but never mid-flee and
never a legend. *Budget ceiling and no-spawn-in-your-lap are both asserted.*

---

## 12. Wiring

```
python3 tools/crittercalls.py --out assets/audio/wildlife
python3 tools/patch_wildlife.py
godot --headless --path . --script res://tests/WildlifeTests.gd
```

`World.USE_WILDLIFE = false` turns the whole thing off in one line, same escape hatch as
`USE_TREES_V2`. `--revert` on the patcher restores `World.gd` from its `.bak_wildlife`.

---

## 13. Known gaps

Honest list. None of these is a crash; all are places the world isn't built out yet.

1. **Zones are radial rings, not the painted map.** `WildlifeDirector._zone_at()` derives a zone
   from distance to world centre because map v1 is art, not data. When the real zone map lands,
   replace that one function and nothing else changes.
2. **No water in the blockout, so no water animals spawn.** Species flagged `water`, `marine`,
   `cliff`, `island_only` or `far_only` are excluded from rolls until there is something for them to
   be on — loons, beavers, otters, seals, whales, puffins, peregrines. They all work; place them by
   hand with `spawn_one()` to see them. `_has_water_near()` looks for a `"water"` group.
3. **The hunting loop does not exist.** `harv` tables are in the dex and cost nothing while unused.
4. **Untested in the live game.** The suite runs against the real wildlife scripts with a stub
   `Enemy`/`Player`; the Player chop/shoot path, framerate with 26 critters on top of 420 trees, and
   the audio at real listener distances are all unverified in `World.tscn`.
5. **`apply_stink` / `stick_quills` / `apply_bug_bites` do not exist on Player yet.** Every call is
   `has_method()`-guarded and falls back to a damage tick, so nothing breaks — but the skunk is
   currently a 1-damage inconvenience rather than a social problem. Three small methods on
   `Player.gd` finish it.
6. **Godot version.** Everything was validated under headless **4.4.1**; the project targets 4.7.
   Note for anyone writing tests here: the headless renderer does **not** keep MultiMesh instance
   transforms, so any gameplay that reads them back works in the editor and silently does nothing
   in a test. `CritterSwarm` keeps its own `_pos` array for exactly this reason — the swat cost a
   build finding that out.
7. **Weather is not wired to wildlife yet.** `Weather.gd` landed in the repo the same day this did.
   Rain should quiet the birds and put the deer up; a storm should empty the sky of soaring
   raptors; and `red_eft` is flagged `rain_only` but nothing checks for rain. One hook —
   `WildlifeDirector` reading `World.weather()` — closes all three.
