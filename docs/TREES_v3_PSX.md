# Myrkfell / The Withering — Trees v3: the PSX Nature & Biomes swap

**Status:** shipped 2026-08-26. Replaces the *art* of trees v2, keeps all of its *systems*.
`docs/TREES_v2_SPEC.md` is still the spec for how chopping, felling, bucking, seasons, snags and
save/load behave — this document only records what the models and materials became, and the handful
of places the code had to move to meet them.

**Everything is behind a flag.** Nothing was deleted.

| Flag | File | Off means |
|---|---|---|
| `TreeV2.USE_PSX` | `scripts/TreeV2.gd` | the procedural GLBs from `tools/treegen2.py` come back |
| `CaveRegion.USE_PSX_UNDERSTORY` | `scripts/CaveRegion.gd` | `Grass.gd`'s blades and the vertex-coloured ground come back |
| `World.USE_PSX_NATURE` | `scripts/World.gd` | grey-box boulders come back, no scattered deadfall |
| `World.USE_TREES_V2` | `scripts/World.gd` | the *old* cone trees (`ChopTree.gd`), as before |

`Grass.gd`, `treegen2.py`, `leafgen.py`, `barkgen.py`, `foliage.gdshader` and `bark.gdshader` are
all untouched on disk.

---

## 1. What the pack is, measured

38 meshes, three shared atlases, **six full recolours of every atlas**: Autumn, Dark, Redwood,
Snowy, Spring, Temperate. Every mesh carries exactly two materials — opaque wood and alpha-cut
foliage — which is the trunk/canopy split the engine already wanted.

Converted by `tools/psxgen.py` (kept in this session's notes; the outputs are checked in) into
`assets/psx_nature/glb/`, Y-up, origin at the trunk's foot, wood and foliage split into named
`Trunk` and `Foliage` children.

| Asset | Real height | Trunk r @1 m | Tris (standing) | Role |
|---|---|---|---|---|
| `SM_Tree_01 / _02` | 7.7 / 7.6 m | 0.34 / 0.32 | 176 / 174 | the hardwoods |
| `SM_BareTree_01 / _02` | 4.5 / 4.3 m | 0.34 / 0.32 | 148 / 136 | hardwood snags + withered |
| `SM_Pine_01…06` | 3.6–8.0 m | 0.06–0.17 | 121–197 | the conifers |
| `SM_BarePine_01 / _02` | 6.4 m | 0.16 / 0.14 | 133 / 115 | conifer snags |
| `SM_GiantPine_01 / _02` | 28.9 / 27.5 m | 1.01 / 0.79 | 276 | the `GREAT` trees |
| `SM_Shrub_01 / _02` | 2.9 / 2.0 m | — | 12 / 8 | bushes |
| `SM_Fern_01/02`, `SM_Plant_01…04` | 0.3–1.1 m | — | 20–40 | understory |
| `SM_FallenLog_Large / _Small` | 10.4 / 4.8 m long | — | 278 / 26 | deadfall |
| `SM_Stump_01 / _02`, `SM_Twig_01…04`, `SM_Rock_01…08` | 0.1–1.1 m | — | 16–48 | litter |

**The whole pack standing is 3,252 triangles.** A mature tree is 176. The procedural trees it
replaces measured 5.0k–12.8k each (v2 spec §11). That is roughly a **thirty-fold** cut in the
forest's triangle load, and it is why the tree budget in v2 §11 no longer binds anything.

### The dense chop trunk

The pack's trunks are four- to eight-sided tubes with **no rings at all through the chop band** —
`SM_Pine_01` goes straight from z=0.29 to z=1.71. There is nothing there to push inward, so the
notch would have had nothing to carve.

Subdividing at bake time would have made every standing tree pay for it. So each choppable tree
ships a **second GLB**, `<name>_chop.glb`, holding only a subdivided trunk (365–988 tris), and
`TreeV2._swap_dense_trunk()` swaps it in from `_cache_trunk()` — which was already lazy, and already
carried the comment explaining why. The shape is identical, so the swap is invisible; 420 standing
trees never load it.

### The radius profile

The exporter samples the trunk radius every 25 cm up to 3 m and writes it into
`assets/psx_nature/glb/manifest.json`. `PSXNature.radius_at()` reads it, bridging any gap from its
neighbours rather than returning zero — a zero there would let one swing eat straight through a
tree. The notch height is clamped to **0.45–1.45 m in model space**: above 1.45 the pack's trunks are
already opening into the crotch, and sampling there gave a three-metre sapling a trunk a third of a
metre thick.

---

## 2. Species after the swap

Species is no longer a leaf texture. The atlas carries colour now, and it carries it **for the whole
biome**. What species still is: shape, size, log yield, seed, growth rate, and how it reads on a
ridge. `PSXNature.TREE_MESH` maps it to models:

| Species | Live | Withered / snag | Sapling | Great |
|---|---|---|---|---|
| maple | `Tree_01` | `BareTree_01` | `Plant_02` | scaled `Tree_01` |
| birch | `Tree_02` | `BareTree_02` | `Plant_02` | scaled `Tree_02` |
| oak | `Tree_01`, `Tree_02` | `BareTree_01/02` | `Plant_02` | scaled |
| pine | `Pine_01, _02, _04` | `BarePine_01` | `Pine_05` | `GiantPine_01/02` |
| fir | `Pine_03, _05, _06` | `BarePine_02` | `Pine_06` | `GiantPine_01/02` |

`pick_tree()` takes the model whose **real** height is nearest the stage's target and scales it a
little, rather than blowing a four-metre tree up to twice its size; the second-nearest gets a 32%
look-in so a stand isn't one tree copied forty times. Measured scales now sit between ×0.4 and ×2.0.

**Snags got better, not worse.** A dead tree used to mean swapping in a grey deadwood bark set. Now
it wears an actual bare model — `BareTree` / `BarePine` — which is what the pack authored them for.

---

## 3. Seasons and biomes — one crossfade, no rebuilds

This is the part the pack simply hands over. Six painted atlases means the season system stops being
a colour ramp over a grayscale sheet and becomes a **crossfade between two hand-painted atlases**,
picked off the same global `season_phase` float `Wind.gd` already publishes.

A **region** binds four of the six:

| Region | spring | summer | autumn | winter |
|---|---|---|---|---|
| `temperate` | Spring | Temperate | Autumn | Snowy |
| `deepwood` | Dark | Dark | Dark | Snowy |
| `redwood` | Redwood | Redwood | Redwood | Snowy |
| `highland` | Spring | Temperate | Snowy | Snowy |
| `blight` | Dark | Dark | Autumn | Dark |

`TreeV2.region` is per-tree and saved, so a grove can be `deepwood` all year while the wood around it
turns. That is the whole biome system: one string.

The ramp **holds** each season and turns over the last 45% — straight-lerping the four stops means
"summer" exists for one instant of the year, which is the bug §20 of the v2 spec already caught once.

Materials are one shared `[wood, foliage]` pair per `(atlas group, region, alive/dead)`, cached in
`PSXNature._mats`. 420 trees are a handful of materials, not 420.

### Shaders

| File | Does |
|---|---|
| `shaders/psx_foliage.gdshader` | season crossfade, alpha cut (relaxed with distance so nearest+mipmap doesn't thin the canopy away), wind + player push from `Wind.gd`, snow on up-facing cards, snag cling, the `shed` uniform, instance tint via `COLOR` |
| `shaders/psx_wood.gdshader` | same crossfade, the heartwood wound, snow, no wind |
| `shaders/psx_leaffall.gdshader` | the falling burst, all motion in the vertex shader |
| `shaders/psx_ground.gdshader` | triplanar ForestFloor / Soil / RockGround over the cave mesh |

All four use the same **banded `light()`** — four flat diffuse tones, no specular — so wood, leaf and
floor sit in one picture, matching the "realistic pixeled" read the grass v2.3 work established.

**Two traps recorded here so they are not re-discovered:**

1. **`return` is illegal inside `light()`** in Godot. An early bail for a `flat_light == false`
   branch fails shader compilation with `Using 'return' in the 'light' processor function is
   incorrect`. The body has to be one branch.
2. **The cut flag in `psx_wood` is INVERTED, and that is load-bearing.** A mesh with no vertex
   colour array reports `COLOR = white`, so "1 = cut" paints every trunk in the forest bright
   heartwood. White means untouched bark; the carve writes values below 1. Same convention the v2
   bark shader used, same reason.

---

## 4. What the engine had to learn

`scripts/PSXNature.gd` is new and holds everything that knows an asset name: the manifest, the
species table, the region recipes, the shared materials, and mesh extraction for the scatter layers.
Nothing else in the codebase spells a filename.

`TreeV2` changes are contained:

- `_build_psx()` alongside `_build()`, picking off a **seeded** rng so a tree restored from a save
  re-rolls the *same* model. Get that wrong and every load reshuffles the forest.
- Surfaces matched by material **name** (`Foliage`), never by index.
- `trunk_radius()` (world) and `model_radius()` (mesh space) are now separate. They differ by the
  model's scale, and mixing them up is how a sapling ends up with a wedge wider than the tree.
- No `Branch_NN` nodes exist in the pack, so `branches_left()` is always 0 and every swing lands on
  the trunk — which is exactly the rule §22 of the v2 spec set. Limbing is gone rather than optional.
- Sticks now come off the crash instead of off limbing (`FallenTrunk.sticks`), and a one-piece trunk
  gets two small props along its length so it lands resting a hand's width off the dirt.

Bites to fell, measured in-engine: **young 2, mature 4–6, ancient 6–8**.

---

## 5. Shedding — Lemon's call

> *"the leaves won't stay on when they get knocked over"* → **they should come off, just properly.**

Two halves:

- The tree's own canopy thins **card by card** through a `shed` uniform on `psx_foliage`, hashed per
  card so it scatters. `FallenTrunk` ramps it over the fall (0.85/s). No mesh rebuild, no allocation
   — the same trick defoliation already used.
- `scripts/LeafBurst.gd` throws the difference: leaf quads **lifted out of that tree's own canopy
  mesh**, so they are the same leaves, with the same atlas UVs, in the same season. One `ArrayMesh`,
  one draw call; each card carries its centre and a seed in `CUSTOM0` and the vertex shader does all
  the falling, drifting and tumbling off a single float.

Cards shrink to **×0.30** about their own centre on the way out. At full size a pack canopy clump is
a metre and a half across and reads as a bedsheet — the same mistake §23 caught in the old canopy.
`custom_aabb` is forced large or the whole burst gets frustum-culled the moment it leaves the crown.

---

## 6. The floor — the procedural grass is retired

> *"fuck that ai grass (sry, but I didn't like it)"*

`scripts/Understory.gd` replaces `GrassSystem`. What it **keeps** from three rounds of grass tuning
is the siting: the same 16-cell chunk grid, the same five noise fields with the same seed arithmetic,
the same `floor_point` sampling, cliff rejection, clump cutoff and deterministic per-chunk rng. So
the ferns come up in the damp hollows exactly where the old ferns did.

What changes is what grows: the pack's plants, ferns and shrubs, plus twigs and pebbles — and no
blades at all. Per chunk: 520 plant attempts, 300 fern, 44 shrub, 90 twig, 18 pebble. A chunk uses at
most **two variants** of each layer, chosen off its own key, so neighbouring chunks bring different
ferns without one MultiMeshInstance per variant per chunk.

It keeps GrassSystem's whole public surface — group `"grass_system"`, `is_tall_at`, `cut_at`,
`rebuild_area`, `save_state`, `apply_state` — because Player, Enemy, CaveRegion and World all reach
for those by name. **Stealth is load-bearing:** `Enemy` aggro reads `grass_hidden` off the player and
something has to keep writing it. Cover is now rank patches of shrub and fern, but it is the same
`_tall` noise deciding where.

Only the leafy layers carry an instance tint. `psx_wood` reads `COLOR` as the axe-cut flag, so
tinting a rock would paint it fresh heartwood.

### And the ground under it

The world surface is the top skin of the map-wide `CaveRegion`, meshed by `CaveMesher` with flat
per-face vertex colours and **no UVs at all**. `psx_ground.gdshader` is therefore triplanar: it
projects ForestFloor / Soil / RockGround by world position, picks between them by flatness and depth,
and keeps the mesher's vertex colour as a **hue tint only** so the strata still cool to frost and
warm to ember down in the deeps. Winter swaps the forest floor for the Snowy sheet.

---

## 7. The wood's furniture

Small litter is instanced without collision — four thousand colliders for things you step over is a
bad trade. Anything you can trip over, climb, or chop is a `scripts/PSXProp.gd` `StaticBody3D` with a
convex hull off its own mesh: `World._build_props()` places 96 of them (fallen logs, old stumps, the
big boulders), and `_build_rocks()`'s 14 mineable boulders now wear real rock instead of grey boxes,
with their bodies, groups and `bites` meta untouched.

Fallen logs and stumps are **choppable** — a log lying in the wood is firewood somebody else already
felled. Large log 4 bites → 2 Wood + sticks; small log 2; stump 3.

`TreeStump` now wears `SM_Stump_01/02` scaled so its trunk matches the tree that stood there, with
the pale heartwood disc kept on top — the pack's stump is a weathered old one with bark right over
the cut, and that disc is the thing that says a person did this.

---

## 8. BUG 5 CAME BACK — and it ate the forest

`World.save_state()` was writing `if t is ChopTree` and nothing else, and `apply_state()` was
restoring every saved tree as a `ChopTree` after clearing the whole `"trees"` group. **Every `TreeV2`
in the world was `queue_free()`d on load and nothing came back.**

This is verbatim the bug §21 of the v2 spec documents finding and fixing. The fix was not in the
World.gd on disk — a later patcher (sky, wildlife or the spawn menu) restored a `.bak` over it.

Fixed again, and this time the suite asserts it: `save_state` writes `TreeV2`, `TreeStump` and
`ChopTree`, and `apply_state` dispatches on the `"kind"` key, falling through to `ChopTree` for old
saves that have no kind at all.

**Rule worth writing down: when two patchers touch `World.gd`, diff it against the last known-good
before committing.** This is the second time that file has silently lost work.

---

## 9. Numbers

| | v2 (procedural) | v3 (PSX) |
|---|---|---|
| Mature tree, L0 | 5,000–9,700 tris | **176** |
| Ancient tree, L0 | 6,300–12,800 tris | **176** (scaled) |
| Whole asset set standing | — | **3,252** |
| Dense chop trunk | n/a | 365–988, one tree at a time |
| Materials for 420 trees | 2 per species (10) | 2 per (atlas, region) — 6 for one region |
| Season change cost | 0 rebuilds | 0 rebuilds, +1 texture sample |
| Atlas VRAM, one region | 5 × 1024² grayscale | 12 × 1500² RGBA ≈ 100 MB |

The one place this costs more is texture memory: the pack's sheets are 1500² RGBA and a region needs
twelve of them resident (three atlas groups × four seasons). Regions load lazily, so a world that
only uses `temperate` pays for twelve. **If that ever needs to come down, downscale the sheets to
1024² rather than VRAM-compressing them** — block compression on pixel art is exactly the wrong
trade.

---

## 10. Verified, and not

`tests/PSXTreeTests.gd` — **642 assertions, green**, run against the real scripts under Godot 4.7:

```
godot --headless --path . --script res://tests/PSXTreeTests.gd
```

It covers: every asset in the manifest has a GLB; every choppable tree has a denser chop twin; the
whole pack is under 5k triangles standing; every species/stage picks a real asset inside its height
band at a sane scale; the radius profile never reads zero in the chop window; the same seed picks the
same tree twice; every region binds four atlases and the pairs are shared, not rebuilt; every surface
wears our ShaderMaterial and never a glTF placeholder; the first bite swaps in the dense trunk, cuts
a notch and exposes heartwood; every species and stage fells in ≤8 swings and leaves a trunk, a stump
and sticks; a canopy throws a burst with real atlas UVs and a snag throws nothing; dead trees wear
bare models and are brittle; great pines are the pack's giants; logs are firewood and boulders are
not; and a part-chopped tree survives a save/load as the same model, the same biome, with its notch.

`tools/psx_render.gd` renders the seven previews in `previews/` under a real GL context.

**Not verified in the live game:** the `Player.gd` chop path (the suite drives `chop_hit` directly),
the pin, framerate with 420 trees + the understory, and the understory against a real `CaveField`
(the suite has no voxel world). The first thing to watch on launch is `Understory` seed time — the
grass at this density seeded in ~4 s behind the loading curtain, and this places fewer instances of
heavier meshes.
