# Myrkfell — Skeletons, PSX skins, ragdolls, shoving, and idle buzz (built spec)

**Status:** shipped 2026-08-26 into `dark-fantasy-game`. Every creature — the nine mobs, all 73
wild species, and the third-person player — now has a real `Skeleton3D`, one skinned low-poly
mesh in a PlayStation-era look, a PhysicalBone3D ragdoll, mass, and a shove rule. Wildlife got a
generic idle "buzz" library (15 clips); the mobs got a lean-and-fidget layer.

**Test suites** (all headless, Godot 4.4.1, against the real scripts):

```
godot --headless --path . --script res://tests/SkinTests.gd       # 369 assertions
godot --headless --path . --script res://tests/WildlifeTests.gd   # 3,502 assertions (was 3,319)
godot --headless --path . --script res://tests/WorldBoot.gd       # boots World.tscn: 105 creatures + player all skinned
godot --headless --path . --script res://tests/ParseCheck.gd      # every touched script compiles
xvfb-run -a godot --rendering-driver opengl3 --path . --script res://tests/ShaderCheck.gd
                                                                   # LIVE renderer: compiles the shader, saves /tmp/skin_*.png
```

The lab stand-in the wildlife suite needed (`LabPlayer`) had never been committed; it is now
`tests/LabPlayer.gd`, so the suite runs again from a fresh clone.

---

## 1. The shape of it

| File | Lines | What it owns |
|---|---|---|
| `scripts/CreatureSkin.gd` | ~780 | **The whole thing.** Bakes a box rig into bones + one skinned mesh, keeps it in sync, owns the ragdoll and the shove rule. |
| `scripts/PsxTex.gd` | ~190 | The texture atlas: 16 procedural 64×64 surface tiles in one 256×256 image. No files. |
| `shaders/psx_skin.gdshader` | ~110 | Vertex snap, affine UVs, banded light, palette posterize, screen-door alpha. |
| `scripts/Enemy.gd` | +~230 | Bakes after `_build_body`; `knockdown()`, `_on_ragdoll_up()`, ragdoll death, `mass`, layers, the FLOW layer. |
| `scripts/Critter.gd` | +~60 | `_skin_opts()` (tile by family, mass from the dex), the buzz picker. |
| `scripts/CritterAnim.gd` | +~420 | 15 generic buzz clips + `buzz_for(family)`. |
| `scripts/Player.gd` | +~40 | Bakes the third-person body; TP knockdowns ragdoll; `knockdown()` for shoves; ray hits map bones → creature. |
| `scripts/Horse.gd`, `Arrow.gd`, 7 mob scripts | small | mass + tile per mob; a horse going down bucks its rider; arrows into a ragdoll count. |

### The one idea

**Nothing that authors a pose changed.** Every creature was a tree of `Node3D` pivots with
`BoxMesh` parts, and every animation in the game (`Enemy._update_locomotion`, the mobs'
`_animate` chains, CritterAnim's 180 signatures, the Player's `SWING_KEYS`) writes those pivots.
`CreatureSkin.bake(owner)` walks that finished tree once and:

1. makes a **bone for every pivot that carries boxes** (pivots with nothing on them are skipped —
   see §4 for why that matters),
2. turns **every box into a rounded PSX segment** (8-vertex superellipse rings, bevelled ends,
   ~34 verts) in ONE `ArrayMesh`, weighted to its pivot's bone, with the joint end blended
   toward the parent bone so knees, shoulders and necks flex instead of hinging,
3. leaves the old `MeshInstance3D`s in the tree as **proxies** (`mesh = null`) — every reference
   the game holds (`torso_mesh`, `hair_meshes`, `body_mat`, `eye_mats`, `rig["mats"]`) is still
   valid, and every `visible` toggle on gear still works,
4. every frame copies pivot → bone (`_process`) and mirrors each proxy's `StandardMaterial3D`
   (albedo, alpha, emission × energy, metallic, `is_visible_in_tree`) into a **128×2 RGBAF data
   texture** the shader reads per segment. Hit flash, coat swap, eyeshine, buff glow, spectral
   legends, armour tint, helm/hair swaps: **all of it kept working with zero callers changed.**

Materials per creature went from ~15 (one per box — the optimisation audit's 1,530-material
finding) to **one** ShaderMaterial + one shared atlas texture.

---

## 2. The PSX look

`shaders/psx_skin.gdshader`:

- **Vertex snapping** to a 426×240 grid in clip space (`snap_res`, `snap_amount`). The wobble.
- **Affine texture mapping**: `UV * w` interpolated perspective-correctly and divided by
  interpolated `w` comes out screen-linear. The swim. On purpose.
- **Banded light** — the same four flat tones Grass v2.3 uses, so a deer in the meadow is lit by
  the same sun; metal gets one extra glint band square-on.
- **Posterize** to `palette_steps` (12).
- **Screen-door alpha**: a 4×4 Bayer dither, never a blend — the ghost cat and the Specter Moose
  are dithered, corpses dither away, hidden gear is discarded. Opaque pipeline always.
- Whole-creature `ghost` and `flash` uniforms for corpses / hit flashes.

`PsxTex` tiles: `flat fur fur_striped fur_spotted hide feather scale skin cloth leather wood
metal bone stone fur_long chitin`. Grayscale-ish detail (quantised to 14 steps) multiplied by the
segment colour, so a fox and a lynx share the fur tile and differ only by the numbers the dex
already holds. Tile per creature by rig family (`Critter._skin_opts`) — feathers for birds,
scale for herps and fish, long fur for bears, hide for cervids — with dex feature flags
(`stripes`/`stripe`/`barring`, `spots`, `shaggy`, `shell`) overriding, `metallic > 0.3` boxes
getting the metal tile, tiny boxes (eyes) the flat one, and a per-box `psx_tile` meta as the
escape hatch. Texel density scales with the animal (`tile_world` ≈ 0.42 × reach, 0.14–0.75 m).

**Alpha rule** (found on the live renderer): `CritterRig` colours hooves as `col * 0.75`, which
carries 0.75 *alpha* that a `StandardMaterial3D` ignores. The skin ignores it too unless the
material's `transparency` is actually enabled — otherwise every hoof in Maine was a dither.

---

## 3. Ragdoll

Built lazily the first time a creature needs it (the ~100 cave mobs that never fall over never
pay for it). One `PhysicalBone3D` per bone under a `PhysicalBoneSimulator3D` (the 4.3+ API, not
the deprecated `Skeleton3D.physical_bones_*` compat path — the project targets 4.7): a box shape
from the bone's own boxes, mass by volume **clamped to 3–60 % of the body**, the pelvis (bone 1)
free, everything else a **cone joint whose axis is rotated to run down the limb** (80° swing,
40° twist, engine-default softness), friction 0.55, damping 0.6 / 3.0. Bones never collide with
each other or with their own CharacterBody3D.

- `knockdown(fling, seconds)` — capsule off, brain off (`knocked`), body to physics. The clock
  runs on the fixed step. When it ends the creature **stands up where the pelvis is**: root
  moved to the pelvis, dropped to the floor by a ray, yaw from the pelvis, and a 0.45 s pose
  blend from the ragdoll pose to the animated one (`_sync_bones_blended`, in world space).
- **Death is a ragdoll** (`Enemy.RAGDOLL_DEATH`). Corpse settles 5 s, freezes (no physics
  cost), lies 16 s, dithers out over 1.6 s, frees. Loot drops 0.35 s in. The old white-flash-
  and-shards path is still there behind the constant. Killed while down → stays down.
- The player: third-person knockdowns (`_start_knockdown`) hand `body_rig` to the ragdoll; the
  camera fall/bounce/rise that sells it from inside is unchanged; `"rise"` and every path that
  clears `kd_phase` calls `_body_up()`. First person never ragdolls the (invisible) body.
- `CreatureSkin.owner_of(collider)` maps a bone back to its creature. `Enemy._can_see`,
  `Player._impact_on`, `Player._swing_reaches`, `Arrow` use it, so LOS, impact FX and arrows
  treat a downed creature as itself.

### The five bugs, in the order they were found (all asserted now)

1. **CreatureSkin was a `Node`** — a `Skeleton3D` under a non-Node3D does not inherit the
   transform. Mesh at the origin, bones in the wrong space. It is a `Node3D`.
2. **A cone joint's axis is the joint frame's +X.** Limbs point along −Y/−Z, so with the default
   frame every limb started 90° outside its own cone and the solver spent the whole ragdoll
   fixing that: goblins drifting at 1.5 m/s, deer exploding. `joint_offset` now rotates +X down
   the bone's geometry.
3. **Self-collision.** Overlapping bone boxes flung everything apart on frame one.
   `add_collision_exception_with` across every pair.
4. **Hubs.** The first design gave pivots with no boxes (the wildlife `root`) a tiny shapeless
   body so the hips hanging off `root` had a parent — a shapeless body has no inertia and the
   solver nailed it to the world: the standing corpse. Now bones exist only for pivots with
   geometry, poses are written in owner space every frame (so the bone tree need not mirror the
   node tree), a bone's parent is the nearest ancestor *with* geometry or the pelvis, and every
   joint has a real parent body.
5. **`Skeleton3D.physical_bones_add_collision_exception(owner)` did not reach the bones** on
   the compat path — the deer lay on its own capsule like a shelf. Each bone excludes the
   owner directly.

Mass ratios above ~20:1 also make Godot's solver unhappy; the 3 % floor keeps ears from
detonating torsos.

---

## 4. Shoving and trampling

`CreatureSkin._physics_process` runs **after** its owner's `move_and_slide` (children tick after
parents) and reads the slide collisions. `velocity` is already the post-slide value (zero into a
wall of goblin), so closing speed uses `travel + remainder` — the motion the body *tried* to make.

For each CharacterBody3D hit: `share = m₁ / (m₁ + m₂)`, `push = closing × share`. The pushed body
is brought **up to** `push` along the contact (a velocity to reach, not an impulse to stack —
leaning on an ogre for a second must not wind it up to your speed) and the pusher loses a share.
If `push ≥ 3.4 m/s` and the pusher outweighs the pushed by 1.45×, `knockdown()` — the lighter one
goes flat with the shove's speed, plus a little trample damage above that. Equal masses jostle.
The player is on the receiving end too (`Player.knockdown`); the `LabPlayer` in the tests
deliberately isn't, so the path is covered both ways.

**Layers.** Creatures moved to **layer 2** (mask 1|2); the player stays on 1 (mask 1|2); ragdoll
bones on **layer 8**, mask 1|8. So a charging horse runs *through* a downed goblin instead of
bulldozing its corpse twenty metres down the road (measured: 20 m, before the layers), corpses
pile on each other, the player walks over them, and you can still kick one. Every raycast in the
game uses the default all-layers mask, so nothing else noticed.

Masses: goblin 35, kobold 25, orc 110, ogre 420, skeleton 40, dark knight 140, boar 90, horse 480,
player 80; wildlife from a `mass` dex key or `60 · len² · hgt` (hare 2.8, whitetail 190, bear
173, moose ~640), floor 0.05 kg.

---

## 5. Idle buzz (wildlife) — "save the tokens"

15 generic clips in `CritterAnim`, pure functions of `t`, rest-relative, family-agnostic through
the null-safe setters: `graze sniff_ground paw_ground huff_toss wet_shake stretch look_about
scratch sit_rest tail_swish` and, for birds, `peck_ground preen ruffle wing_stretch`, and
`sun_bask` for herps/fish. (`shake_off` and `bask` were already species signatures — the
osprey's mid-air shake, the turtle's log bask — hence the names.) `buzz_for(family)` returns a
weighted candidate list per rig family; SWARM gets none.

`Critter._idle_flavour` gained a second, faster cooldown (`BUZZ_COOLDOWN` 2.5–8 s vs the species
signature's 4–13 s): calm, standing (`_loco_amount < 0.25`), within 60 m, nothing playing → a
buzz clip via `_play_buzz`, which does **not** spend `_sig_cool` (buzz never starves the real
tells) and plays **no audio** (a huff is flavour, not an alarm). Buzz keys are never rooted or
payoff moves; any mood change already ends the clip.

Measured on the whitetail: `graze` puts the nose ≥ 35 % of rest height lower, `paw_ground`
moves the front hip > 0.2 rad, `huff_toss` pitches the head > 0.25 rad, `wet_shake` ends within
0.01 of rest, `look_about` yaws both ways.

---

## 6. Flow (mobs) — the layer between standing and acting

`Enemy._update_flow`, called by the skin after `_animate`, writes small offsets **on top of**
whatever the authored pose left and `_update_locomotion` strips them again next frame
(`_flow_applied` ledger), so nothing accumulates and no authored pose ever sees them:

- **Lean** (everything, wildlife included): acceleration pitches the body nose-down into a sprint
  start (≤ 9°), turning banks it into the turn (≤ 11°, scaled by speed), smoothed at 7/s.
- **Breath** (everything): ±0.55° on the body, slower when running.
- **Fidgets** (mobs only — wildlife has buzz): while standing and not acting, every 1.4–4.5 s one
  of `shift` (weight onto a hip, that knee softens), `look` (glance and hold, 24°), `stomp` (lift
  a foot, plant, dip), `arms` (a loose swing and a shrug), `roll` (shoulders, neck). A swing,
  windup, flinch, climb, rout or retreat cancels the fidget instantly.

---

## 7. What to look at in the live game

Not verifiable headless; the live-renderer frame (`tests/ShaderCheck.gd`) confirms the shader
compiles and the bodies read right, but these want eyes:

1. **Snap and swim strength.** `snap_res` 426×240 and `snap_amount` 1.0 are full PS1. If it
   crawls too much at 1080p, 640×360 is the next stop; `tex_strength` dials the texture.
2. **Knockdown feel.** `KNOCK_SPEED` 3.4 m/s / `KNOCK_MASS_RATIO` 1.45 mean a sprinting player
   (80 kg, 8 m/s) sends hares, foxes, goblins and kobolds flying and bounces off an orc. A
   galloping horse flattens anything under ~330 kg. Fling carry is 0.6 × shove speed.
3. **Corpse clock.** 5 s settle + 16 s linger + 1.6 s fade. 26 wildlife + a cave of mobs means
   at most a handful of ragdolls simulating at once; frozen corpses cost nothing.
4. **The turkey's wings** read as a wide rod in both the box rig and the skin — that is the
   existing `_bird_common` wing pose, not the skin. Worth a look separately.
5. **Player TP knockdown blend**: the scripted `body_rig` tip (82°) is now underneath a real
   ragdoll; when the rise begins the bones blend from where they lie to the tipped pose and the
   rise animates up from there.

---

## 8. Known gaps

1. Boxes added **after** bake stay plain boxes (nothing in the game does this today; a
   `rebake()` would be ten lines).
2. First-person viewmodels are excluded from the skin on purpose (`exclude: [head]`); they keep
   the old materials and do not snap.
3. The 128-segment cap: the player has 68, the saddled horse ~50. A creature over 128 boxes
   would have its tail-end boxes left as plain boxes with a warning-free truncation — worth an
   assert if anything ever approaches it.
4. Ragdolls are floppy on purpose (cone 80°/40°); hinges for knees would look more like anatomy
   and less like a marionette, at the cost of tuning 14 rig families.
5. `WorldBoot` runs without the tree GLBs present (warnings only); it is a creature check, not a
   world check.
