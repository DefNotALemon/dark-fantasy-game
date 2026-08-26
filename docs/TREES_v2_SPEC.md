# Myrkfell / The Withering — Trees, Timber & Log Building (v2 build spec)

**Status:** replaces the tree work entirely. `scripts/ChopTree.gd` (cone canopies, notch-chop,
fell, split-into-logs) and `tools/treegen.py` (icosphere blob canopies) are both **superseded** —
keep them on disk until v2 reaches parity, then delete.

**Target repo:** `~/Documents/GitHub/dark-fantasy-game` (Godot 4.7, Forward+).
Existing systems to build on, not replace: `DayNight.gd` (game clock), `CarryLog.gd` (log physics +
carry), `Player.gd` (auto-sheathe when hands are full), `World.gd` (`_make_tree`, save/load).

**Rule for the implementer:** every number below is a *stated default*, not a guess to re-derive.
Change one only with a reason, and log the change. Build in the phase order at the end; stop at each
review gate and show a render or a clip before moving on.

---

## 1. Art direction

Medieval, hand-built, **cute-but-grounded — BotW's readability with The Withering's gloom**.
Not photoreal, not flat-shaded blobs either. Leaves read as *leaves* at 10 m: you can see shape and
gaps and sky through the canopy. Silhouette is the thing that sells it, so leaf-card outlines matter
more than leaf-card texel detail.

Palette continues `docs/DESIGN.md`: desaturated slate/indigo base, ember-orange and frost-blue
accents. Seasonal color is allowed to be the loudest thing on screen in autumn — that's the point.

---

## 2. Everything is data (this is the load-bearing decision)

Adding tree species #6 through #20 must cost **one resource file and zero code**. So:

**`TreeProfile`** (Resource, one per species) holds:
- trunk: height range per stage, base radius, taper curve, lean/wander, bark material
- branching: orders (1–3), children per order, branch angle range, phyllotaxis mode
  (`GOLDEN_ANGLE` for hardwoods / `WHORL` for conifers), apical dominance, droop, upsweep
- canopy: shape mask (`ROUND`, `VASE`, `COLUMNAR`, `CONICAL`, `TIERED`), density curve vs. stage
- `leaf: LeafProfile`
- gameplay: branch HP curve, log yield, stick yield, wood type tag

**`LeafProfile`** (Resource, one per leaf *shape*, reusable across species) holds:
- `atlas: Texture2D` — the leaf-card sheet
- `variants: int` — how many cells in the atlas (pick one per card at bake time)
- `card_size` min/max, `droop`, `cluster_size` (leaves per twig tip), `cross_quad: bool`
- four season color ramps: `spring`, `summer`, `autumn`, `winter`
- `deciduous: bool`, `marcescence: float` (share of dead leaves that cling through winter — oak)

Species are **authored as `.tres` files under `assets/trees/profiles/`** and registered in one
`TreeRegistry` autoload. `World.gd` asks the registry for a species by biome weight.

---

## 3. The five species (New England, phase 1)

| # | Species | Type | Leaf card | Canopy | Season behavior |
|---|---|---|---|---|---|
| 1 | **Sugar Maple** | deciduous | 5-lobe palmate, wide | `ROUND`, broad and dense | fresh green → deep green → **ember orange/scarlet** → bare |
| 2 | **Paper Birch** | deciduous | small ovate, toothed, many per card | `VASE`, airy, see-through | light green → green → **gold** → bare; white peeling bark year-round |
| 3 | **Northern Red Oak** | deciduous | deep-lobed, leathery | `ROUND` but gnarled and asymmetric | green → dark green → **russet/bronze** → ~25% leaves cling brown all winter (`marcescence = 0.25`) |
| 4 | **Eastern White Pine** | evergreen | needle fascicle, 5-needle sprays | `TIERED` — whorled branch decks, open trunk between | no color change; **snow load** on upper needle cards in winter; slight blue-green shift in cold |
| 5 | **Balsam Fir** | evergreen | short flat needle spray, dense | `CONICAL` spire, branches to the ground | no color change; heaviest snow accumulation; frost-blue tint in winter |

Yes — pine and fir carry winter. Two evergreens is deliberate: the world must not go bald in winter,
and conifer-vs-hardwood is the cheapest way to make a forest read as New England.

Bark is its **own texture per species** (not vertex color): oak fissured, birch peeling white,
maple plated, pine scaly, fir smooth-blistered. One shared bark shader, per-species albedo +
normal. Branch tubes UV-unwrap along their length so bark tiles without stretching at the taper.

---

## 4. Lifecycle — 5 stages, and it actually grows

`sapling → young → mature → ancient → withered`

Every profile parameter is a curve over stage, not five hand-built variants. Height, trunk radius,
branch order count, and **leaf density all scale together** — an ancient maple has roughly 6× the
leaf cards of a young one and a canopy that reads as solid from below.

| Stage | Height (maple) | Branch orders | Leaf cards (summer) | Choppable |
|---|---|---|---|---|
| sapling | 0.8–1.4 m | 0 | 12 | no (pull up by hand) |
| young | 3–4 m | 1 | 90 | yes, 1 log |
| mature | 7–9 m | 2 | 420 | yes, 3 logs |
| ancient | 10–13 m | 3 | 900 | yes, 5 logs |
| withered | 7–9 m | 2, bare + broken | 0–20 (ember leaves) | yes, 2 logs, brittle |

Growth ticks off `DayNight`'s day counter — see §9 for the seed → sapling → tree loop that feeds it.

### Scale classes — some trees are huge

Stage says *how old*, scale class says *how big it got*. `TreeProfile.scale_class` multiplies the
whole tree, and it is a separate axis so a forest can hold one monster without five new profiles.

| Class | Multiplier | Height (mature oak) | Where |
|---|---|---|---|
| `NORMAL` | 1.0 | 7–9 m | the ordinary forest |
| `ELDER` | 1.7 | 13–16 m | rare roll (~4%) in deep-woods scatter — the tree you notice |
| `GREAT` | 3.5–4.5 | 28–38 m | **hand-placed landmarks only**, never random |

`GREAT` trees are level design, not scatter: named, marked on the map, visible over the canopy from
a ridge, with their own approach and their own lighting. Rules that only apply to them:

- Order-1 limbs are thick enough to *stand on* — they get real collision, not capsules.
- Not fellable by a normal axe. Either they refuse the trunk outright (a story tree) or bucking takes
  a stated large number of passes and yields a pile of logs worth the trip.
- Canopy uses the L1 card set at L0 distance (bigger cards, same count) so the leaf budget doesn't
  explode at 4× the branch surface.
- Each one gets a hand-authored `.tres` under `assets/trees/great/`, not a registry roll.

Phase this after the normal-scale system works — but keep `scale_class` in the profile schema from
day one so nothing has to be refactored to add it.

---

## 5. Branch generation — realistic, addressable

Recursive, not random-scatter:

- Trunk spine with per-species wander + a root flare.
- Order-1 branches placed by **phyllotaxis** (137.5° golden angle for hardwoods; 4–6 branch whorls
  at fixed vertical intervals for conifers) — this alone is 80% of "looks like a real tree".
- **Apical dominance:** child length = parent length × `0.55–0.72`, and branches near the trunk top
  get more of the budget. Lower branches on mature+ trees are shed (bare scar stubs) because the
  canopy shaded them out.
- **Gravity + light:** each segment lerps toward `down * droop + up * light_seek`. Maple dips then
  curls up; fir sweeps down; pine goes flat-out horizontal.
- Order-3 twigs are what carry leaves. Nothing else does.

**Every order-1 branch is a named node** (`Branch_00`…`Branch_NN`) with its own capsule collider,
its own leaf MultiMesh, a base position, and a direction vector. Gameplay addresses branches by
name; the mesh generator must guarantee that mapping.

---

## 6. Leaves — textured cards, not geometry blobs

- **Leaf card** = one quad (or cross-quad for close LOD) with an alpha-clipped leaf-cluster texture
  from the species atlas. A single card holds a *small spray* of 3–7 leaves, not one leaf — that's
  how you get density cheap.
- Cards are placed only on order-3 twig tips, `cluster_size` per tip, orientation jittered ±25°,
  rotated to face outward from the canopy center, drooped by gravity.
- All cards for one tree go into **one `MultiMeshInstance3D` per tree** (per branch for the mature+
  trees so a branch's leaves can be culled/dropped independently). One draw call per canopy.
- Material: `alpha_scissor` (not blend — no sort cost, casts real shadows), cull disabled,
  `shadows_opaque` off so light filters through.
- **Wind:** vertex shader sway. Stiffness in `COLOR.r` (0 at trunk → 1 at leaf tip), per-card phase
  offset in `COLOR.g`. One global `wind_dir`/`wind_strength` uniform. Branches sway too, subtler.
- **LOD:** L0 cross-quads (<15 m) → L1 single quads, 50% count, 1.4× size (15–40 m) → L2 octahedral
  billboard imposter baked per species per season (40 m+). Godot `VisualInstance3D` LOD bias.

---

## 7. Seasons — one uniform, zero rebuilds

Add `season_phase: float (0..1)` to `DayNight.gd`, advanced by the day counter, exposed as a
**global shader parameter**. Both the leaf and bark shaders read it. Nothing regenerates a mesh.

The leaf shader does three things off that one float:

1. **Color** — sample the species' four-stop seasonal ramp. Autumn adds per-card hue jitter (a real
   maple is orange *and* red *and* still-green at once) driven by the card's instance ID.
2. **Defoliation** — as winter approaches, raise the alpha-clip threshold *per card* using a hashed
   per-instance value, so cards drop out gradually and in a scattered pattern rather than all at
   once. Costs nothing. `marcescence` holds back that share of cards at a brown winter color.
3. **Snow** — winter blends a white/frost albedo weighted by `dot(world_normal, UP)`, strongest on
   conifer needle cards and upward branch faces.

Falling-leaf ambience: in autumn, `World.gd` spawns a light GPUParticles3D leaf drift near the
player under deciduous canopies. Cheap, sells the season more than anything else.

**Seasonal length: 1 season = 24 game days**, so a year is 96 game days. One constant, one place.

Know what that buys, in real time, at `DAY_SECONDS = 1200`: **8 real hours per season, 32 real hours
per in-game year.** A season is a long stretch of a playthrough, not a passing weather mood — most
players will live inside one season for an entire session and remember the turn when it comes. That
is the right call for a survival game, and it has one consequence worth designing around: **autumn
has to be worth waiting for**, because a player may only see it once or twice. Lean into it — the
autumn colour ramp, the leaf drift, and the seed drop in §9 all land in the same window.

If playtesting says the wait is too long, decouple the two clocks (advance `season_phase` at 1.5×
the day counter) rather than shortening the day — the 20-minute day is already tuned.

---

## 8. Chopping — limbing, then bucking, then splitting

This replaces the current "notch the trunk and it falls" flow. New order of operations:

**a) Limbing (branches first).**
- Aiming at a branch and swinging: the axe animation **aligns its swing plane to that branch's
  direction vector** — you swing along the branch, outward and away from the camera (keeps the
  existing third-person rule that swings must read as going *away*).
- Branch HP scales with radius: `hp = ceil(radius / 0.03)`, so twigs go in one hit, a thick ancient
  limb takes 5–6.
- On break: that branch's leaf MultiMesh **detaches and falls** — convert to ~20 physical leaf cards
  (short-lived RigidBody or a scripted flutter, whichever profiles cheaper) plus a particle burst,
  the rest just despawn. The stripped branch becomes a **Stick** pickup (`RigidBody3D`, existing
  `Pickup.gd` contract). Big limbs yield 2–3 sticks.

**b) Felling + bucking (trunk second).**
- The trunk **refuses damage while any order-1 branch remains** — the axe bounces with a "clear the
  limbs first" cue. This is the core loop change; it makes big trees a project.
- With the tree bare, chopping the trunk notches and fells it as today (keep the good notch/wedge
  math from `ChopTree.gd`, it's the one part worth salvaging).
- A felled trunk on the ground is **bucked** into logs by chopping it: each hit at a spot cuts one
  log off, `log_length = 2.0 m`. Logs are `CarryLog` instances — existing carry + auto-sheathe rules
  already handle them.

**c) Splitting.**
- Axe on a grounded log → **2 half-logs (split billets)**.
- Axe on a billet → **4 planks**.
- Planks are the floor/wall material. Sticks are for tools, fire, and lashings.

---

## 9. Stumps, seeds and regrowth — the forest grows back

The world is not a finite pile of logs. Every tree you take can be replaced, by you or by the forest.

### Stumps

Felling leaves a stump — the notched wood above the cut, exactly as `ChopTree.gd` already builds it.
A stump is a small `StaticBody3D` that blocks movement and looks like evidence.

- **3 more axe hits destroys it.** It yields 2 firewood chunks and leaves a bare dirt scar.
- Stumps do not sprout. Clearing one is how you make ground plantable and how a felled clearing stops
  looking like a war zone.
- Stumps persist through save/load like the rest of the tree state.

### Seeds — one per species, and they look like themselves

Every species drops its own seed item. This is the detail that makes the forest legible: you learn to
read a species by what's on the ground under it.

| Species | Seed item | Reads as |
|---|---|---|
| Sugar maple | **Samara** | winged pair; *spins* as it falls — the helicopter |
| Paper birch | **Catkin** | soft dangling cluster that breaks into papery seedlets |
| Northern red oak | **Acorn** | cupped nut, the one everyone recognises |
| Eastern white pine | **Pine cone** | long, pendant, scaled |
| Balsam fir | **Fir cone** | short, upright, shatters instead of dropping whole |

Each seed is a `Pickup` with its own mesh, icon, and `species_id`. They are the *only* link between
one tree and the next, so the id must survive pickup, inventory, save/load, and planting.

### Drop rules

- Only **mature, ancient, and great** trees drop seeds. Young trees don't; withered ones are done.
- Drops happen in **autumn** — tied to `season_phase`, not to a timer. A mature tree drops
  `2–5` seeds across the season, an ancient `5–9`, a great tree `12–20`.
- Maple samaras spin down; cones fall straight and bounce. Cheap, and it sells the species.
- Seeds left on the ground live until the following **spring**, then resolve: **~15% germinate**
  into a sapling, the rest despawn. Germination is refused if the ground is occupied, sloped past the
  spawn limit, or within `2.5 m` of an existing trunk — that check is what stops a forest from
  choking itself into an unwalkable thicket over a long save.

### Planting

Hold a seed → ghost sapling preview → left click plants it. **Player planting always takes** — the
cost is the seed and the wait, and a coin-flip failure after a real-time wait is just punishment.
(The old design's 35%-fail-to-ash is deliberately dropped. Wild germination carries the randomness
instead, where it costs the player nothing.)

### Growth schedule

Game days per stage transition, at the 24-day season:

| Transition | Days | ≈ |
|---|---|---|
| sapling → young | 12 | half a season |
| young → mature | 48 | two seasons |
| mature → ancient | 192 | two years |
| ancient → withered | 384 | four years |

So a seed you plant is a real young tree by the next season and a harvestable mature tree within a
game year — visible progress inside one long playthrough — while ancient trees stay something the
world gave you, not something you farm. Growth only ticks for trees inside loaded chunks plus a
catch-up pass on load, so a save left alone doesn't rewrite the map.

---

## 10. Building — The Forest's log system, medieval and cute

Clone the placement grammar from *The Forest* / *Sons of the Forest*, then dress it BotW-warm:
chamfered log ends, visible notch joints, rope lashings at every crossing, slight hand-hewn wobble
so nothing is perfectly axis-aligned.

- **Hold a log → ghost preview** appears at the aim point, translucent green (valid) / red (blocked).
- **Right click cycles placement mode:**
  1. `LAID` — horizontal, stacks into wall courses, snaps end-to-end and course-on-course
  2. `PLANTED` — vertical post, sinks into ground, snaps to a ground grid
  3. `LEANED` — angled brace/rafter (phase 2)
- **Left click places.** Placed logs become `StaticBody3D` with the same mesh + bark material.
- **Snapping:** no world grid. Snap points live on placed logs — both ends, and the top saddle. Free
  placement when nothing is in snap range (0.6 m).
- **Planks → flooring:** planks place into a floor grid that snaps to the supporting logs beneath
  them; a plank with no support under it won't place.
- Structures save/load through the existing `SaveGame.gd` pattern — a flat array of
  `{type, transform, mode, wood_species}`. Wood species matters: birch flooring is pale, oak dark.
- **Buildings take no damage — ever.** Not from weather, not from enemies, not from decay. Once it's
  up it stays up, and the only thing that removes a placed piece is the player removing it. Do not
  build HP, durability, or repair for structures. That decision is closed; don't reopen it in a
  later phase "for realism".

---

## 11. Performance budget (hard targets)

| | Target |
|---|---|
| Draw calls per tree | 3 (trunk+branches, leaf multimesh, imposter) |
| Tris — mature, L0 | ≤ 8,000 incl. leaf cards |
| Tris — ancient, L0 | ≤ 10,000 hardwood / ≤ 13,000 fir |
| Tris — L2 imposter | 8 |
| Visible trees | 250+ at 60 fps on the MacBook |
| Leaf atlas | 1024², one per leaf shape, 8 spray cells + 8 single, BC7/ASTC |
| Season change cost | 0 mesh rebuilds, 0 allocations |

**These numbers were revised upward after building the thing.** The first draft of this spec said
4,500 tris for an ancient tree; that was written before anything existed. Measured from
`tools/treegen2.py`: mature 5.0k–9.7k, ancient 6.3k–12.8k. Hitting 4,500 is possible but only by
thinning the canopy until you can see straight through it, which loses the exact quality this whole
system is for. **The distance load belongs to the LODs, not to the close-up model.** A tree you are
standing under gets to be expensive; the other 249 are imposters.

Fir is the heaviest by a wide margin (needle sprigs need more cards to read as dense). If a budget
has to give, take it out of fir's card count first.

If a target is missed, cut leaf-card count before cutting leaf *shape* quality — density is
recoverable at distance, silhouette isn't.

---

## 12. Acceptance criteria

1. Five species render side by side, all five stages each, in one Blender preview render — and again
   in-engine in `World.tscn`.
2. Scrubbing `season_phase` 0→1 in the editor visibly runs spring → summer → autumn → bare/snow with
   no hitch and no mesh rebuild.
3. An ancient oak keeps ~25% of its leaves through winter; the fir wears snow; the maple goes bare.
4. Chopping a mature tree requires limbing all branches before the trunk accepts a hit; each broken
   branch drops its leaves visibly and yields sticks.
5. Felled trunk bucks into the stated log count; a log splits into billets, billets into planks.
6. A player can build a 3-course log wall, a post frame, and a plank floor, save, reload, and find
   it intact — and nothing in the world can damage it.
7. A felled tree's stump takes 3 hits to clear; the cleared scar accepts a planted seed.
8. Each species drops its own visibly distinct seed in autumn; a planted seed is a young tree 60 game
   days later; a save left running a full year shows wild germination without thicket choke.
9. 250 trees visible at 60 fps.

---

## 13. Build order — stop at every gate

- **Phase 0** — `TreeProfile`/`LeafProfile` resources + registry + one throwaway species. *Gate: schema review.*
- **Phase 1** — ~~branch generator~~ **done, see §16** (phyllotaxis, whorls, dominance, droop). *Gate: silhouette render — `previews/trees_silhouettes.png`.*
- **Phase 2** — ~~leaf atlases (§15)~~ ~~card placement (§16)~~ **done** + wind shader still to do. *Gate: `previews/trees_species_mature.png`.*
- **Phase 3** — ~~season uniform, ramps, defoliation, snow, marcescence~~ **shader written (§18)**, needs an in-engine scrub. *Gate: season scrub clip.*
- **Phase 4** — LODs + imposters + perf pass to the numbers in §11. *Gate: 250-tree fps capture.*
- **Phase 5** — ~~limbing / bucking / splitting~~ **written (§19)**, unrun. *Gate: chop-a-tree clip.*
- **Phase 6** — log building: ghost, modes, snapping, placement, save/load. *Gate: build-a-shack clip.*
- **Phase 7** — planks and flooring.
- **Phase 8** — stumps, the five seed items, drop / germinate / plant, growth ticks (§9). *Gate: plant a seed, skip 60 days, see a young tree.*
- **Phase 9** — `ELDER` roll and the first hand-placed `GREAT` tree (§4).

---

## 14. Decisions — all settled 2026-08-22

Nothing in this spec is waiting on an answer. Build it.

1. **Leaf atlases are generated, not painted.** `tools/leafgen.py` builds all five procedurally —
   see §15. Adding a sixth leaf shape is a new builder function, ~15 lines.
2. **Repo is `dark-fantasy-game`.** `myrkfell` is not on disk.
3. **Some trees are huge.** `scale_class`: `NORMAL` / `ELDER` / hand-placed `GREAT` (§4).
4. **A season is 24 game days** — 96-day year, 8 real hours per season (§7).
5. **The forest grows back.** Stumps clear in 3 more hits; every species drops its own seed; seeds
   germinate wild at ~15% or are planted by the player for a guaranteed take (§9).
6. **Buildings take no damage, ever.** No durability, no decay, no repair (§10).

---

## 15. `tools/leafgen.py` — the atlas generator (built, shipped)

Run: `python3 tools/leafgen.py --out assets/trees/leaves`
Deterministic (`--seed`, default 7717) — same seed, same bytes, so atlases are reproducible and
diff-clean. Needs only Pillow + numpy.

**Output per species** (maple, birch, oak, pine, fir), into `assets/trees/leaves/`:

- `<name>_leaf_atlas.png` — 1024², **grayscale luminance in RGB, silhouette in alpha**
- `<name>_leaf_normal.png` — tangent normal derived from leaf curvature + vein ridges

**Why grayscale:** the atlas is never coloured. The season shader multiplies luminance by the
species' seasonal ramp (§7), so one texture serves all four seasons — the ramps in `SEASON_RAMPS`
inside the script are the authored source of those colours and should be copied into each
`LeafProfile.tres`.

**Cell layout** (4 × 4 of 256 px):

| Cells | Contents | Used by |
|---|---|---|
| 0–7 | leaf **sprays** — 4–9 leaves fanned off an implied twig, gaps left for sky | canopy MultiMesh, L0/L1 |
| 8–15 | **single leaves** | close-detail cards, falling-leaf particles, UI icons |

Every leaf is auto-fitted inside its cell (`_fit()`): a leaf clipped by the atlas edge shows up
in-game as a straight razor cut across the canopy, so the generator shrinks rather than crops.

**Shape parameters worth knowing when tuning:** maple lobe sharpness (`** 0.58`), oak sinus depth
`0.66` / width `0.038` / forward rake `0.13`, birch serration `0.038 @ 26`, per-species `lscale`
in the `SPECIES` table (birch leaves are genuinely small — `0.86`), needle half-widths in
`needle_pine` / `needle_fir` (thin needles vanish in the downsample; below ~0.02 they go ghostly).

Previews land in `assets/trees/leaves/previews/`: `leaf_atlases.png` (sprays, summer tint),
`leaf_singles.png` (single leaves, autumn), `leaf_seasons.png` (one card through all four seasons —
this is the proof the one-uniform season plan works).

---

## 16. `tools/treegen2.py` — the tree generator (built, shipped)

Replaces `tools/treegen.py` (icosphere blob canopies). Five species × five stages, real recursive
branching, alpha-clipped leaf cards from the §15 atlases.

Run headless — no Blender app needed, `bpy` is a pip module:

```
pip install bpy                     # once, needs python 3.11
python3 tools/treegen2.py --out assets/trees --leaves assets/trees/leaves --glb
```

or inside Blender: `exec(open('tools/treegen2.py').read())`.

**The one function that matters for Godot: `build_skeleton(profile, stage, seed)`.** It is pure
Python — no `bpy` anywhere in it — and returns `(segments, twigs, height)`. Those are the same
numbers the Godot-side generator has to produce, so **port that function, not the mesh code**.
`SPECIES` at the top of the file is the `TreeProfile` schema from §2 in dict form; moving it to
`.tres` resources is Phase 0's job and should not change a single value.

What the skeleton does, in order: wandering trunk spine with a short root-flare section → order-1
branches placed by golden angle (hardwood) or by whorl rings that shorten toward the top (conifer,
which is what makes the cone) → recursive children at `dominance = 0.48–0.62` of the parent →
each segment bends by `-droop·(1-f) + light·(f-0.3)` so branches dip and then lift at the tip →
twigs recorded along the outer reaches of the last two orders.

**Two bugs worth not re-introducing:**

- Leaf cards only at branch *tips* gives pom-poms on bare sticks. Cards go along the outer 2
  segments of the last two orders.
- Wood must be welded (`remove_doubles`) **and** smooth-shaded, with leaf cards left flat. Flat-shaded
  piecewise tapers turn every segment join into a bamboo ring.

**Output:** `assets/trees/glb/<species>_<stage>_<name>.glb` (25 files, Y-up, origin at trunk base,
textures *not* embedded — the leaf atlas is one shared file, not 25 copies) and preview renders in
`assets/trees/previews/`.

**Still placeholder in here:** bark is flat per-species colour, because bark textures don't exist
yet (§3 wants five). Sapling stage is a stem with three leaf clusters — deliberately crude, it's
1.1 m tall. No wind, no LODs, no imposters yet.

---

## 17. `tools/barkgen.py` — bark (built, shipped)

Five seamless tiling bark sets, procedural, same pipeline as the leaves.
Lemon's call was **both** options: stylised albedo (plates readable at ten metres)
**and** a detailed normal doing the close-up work.

`python3 tools/barkgen.py --out assets/trees/bark` → per species:

| File | What it does |
|---|---|
| `<n>_bark_albedo.png` | stylised plates, with cavity shading baked in so they read before any light hits them |
| `<n>_bark_normal.png` | the fine relief |
| `<n>_bark_rough.png` | plate faces polish, crevices don't |
| `<n>_bark_height.png` | drives the parallax occlusion in the shader |

Species tells: oak deep vertical fissures, maple shaggy lifting plates, birch
chalk-white paper with dark horizontal lenticel dashes and peel curls, pine big
jigsaw plates, fir near-smooth grey with sparse resin blisters.

Trunk UVs are u = around the trunk, v = up it, so every noise field is
anisotropic — fissures are long in v and tight in u. Change that convention and
the bark stretches.

**Tuning that mattered:** the first pass came out as mush. What fixed it was
contrast + a baked cavity term (blur the height, subtract, darken the pits), not
more noise detail. `contrast` / `pivot` / `ao` per species in the `SPECIES` table.

---

## 18. Wind and season — `scripts/Wind.gd`, `shaders/foliage.gdshader`, `shaders/bark.gdshader`

Lemon's call: weather-driven gusts **and** the player shoving through foliage.

`Wind.gd` is one autoload-ish node added by `World.gd`. It publishes six global
shader parameters and nothing else in the game is allowed to invent its own
breeze:

| Global | Meaning |
|---|---|
| `wind_dir` | prevailing direction, wanders slowly, never snaps |
| `wind_strength` | breathing base + gusts that arrive and pass; `storm` lerps it toward 1 |
| `wind_time` | monotonic seconds |
| `season_phase` | 0..1 = one 96-day year |
| `player_pos` | where you are |
| `player_push` | 0 still → 1 sprinting; an axe swing spikes it |

Grass and cloth should read the same six when they get there. That is the point
of putting it here rather than in the tree code.

**`foliage.gdshader`** does the whole of §7 off `season_phase`: colour ramp
through four stops, per-card autumn hue jitter, **defoliation by raising the
alpha cut per card** (scattered, hashed — no mesh rebuild, no allocation), the
`marcescence` share that clings brown all winter, and snow on up-facing cards.
Sway uses a two-wave gust plus flutter, scaled by a stiffness term; the player's
proximity pushes cards aside.

**`bark.gdshader`** carries **parallax occlusion mapping** — Lemon asked for bark
that reads 3D up close, so the fissures actually occlude each other and slide
correctly as you move past, rather than being a flat picture with a normal map.
POM is the expensive part, so it fades between `pom_near` (3 m) and `pom_far`
(14 m); past that the normal map alone was already doing the job. A forest of
250 trees pays for parallax on the two or three you are standing next to.
Crevices also self-shadow by hit depth.

---

## 19. Chopping and pinning — the Phase 5 scripts

| File | Role |
|---|---|
| `scripts/TreeV2.gd` | the standing tree; loads the split GLB, wraps each `Branch_NN`, gates the trunk, fells |
| `scripts/TreeBranch.gd` | one limb: HP from thickness, leaf burst on break, drops sticks |
| `scripts/FallenTrunk.gd` | the physics trunk: crash, crush, **pin**, then bucking into logs |
| `scripts/TreeStump.gd` | 3 hits to clear, 2 firewood, leaves plantable ground |
| `scripts/PinWatcher.gd` | ticks the pin timer without touching Player's main loops |
| `tools/patch_repo.py` | the World.gd / Player.gd integration, re-runnable, leaves `.bak` files |

**Limbing gates felling.** The trunk refuses a bite while any limb stands.

**Not every branch is a limb.** A fir exports ~70 whorl branches; making a player
clear all seventy is punishment, not a loop. Only branches at or above
`MIN_LIMB_R` (0.055 m) gate the trunk, and only the **thickest 12**. Everything
thinner is scenery that comes down with the tree.

**Felling is physics.** The trunk topples about its base as a rigid body in the
direction you were standing, and it crushes what it lands on.

**Pinning** (Lemon's rule): under `PIN_ARMOR_TIER` armour, a trunk landing on you
pins you flat — a `"pinned"` knockdown phase with **no rise timer at all**. It
ends when the trunk rolls off (`PIN_SECONDS`, 7 s) or when something calls
`free_pinned()` — the co-op rescue hook. After **10 seconds** pinned, an
`[F] reload last save` prompt appears; F is the interact key everywhere else, and
you can't interact while pinned, so the overload is free.

### Known stubs

Two, both marked `TODO` in the source:

1. **`Player.armor_tier()` returns 0**, so a trunk always pins. There is no armour
   rating in the game yet — hook it to the worn chest piece's material tier and
   it is a one-line change.
2. **`Player.axe_swing_axis`** is set to the limb's axis on every chop but the axe
   animation does not read it yet. The data is there; rotating the swing arc onto
   it is an animation change I did not want to make blind inside a 6,000-line file.

`World.USE_TREES_V2 = false` reverts to the old cone trees if anything misbehaves.

---

## 20. What broke on first launch, and the tests that keep it fixed

Everything below was found by running the real engine, not by reading the code.
`tests/TreeTests.gd` now holds **174 assertions** covering all of it:

```
godot --headless --path . --script res://tests/TreeTests.gd
```

### The four real bugs

**1. Glitched leaves and magenta trees — the GLB materials were never replaced.**
The GLBs ship without textures on purpose (one shared atlas beats 25 embedded
copies), so their glTF materials are placeholders: flat grey, alpha-BLEND, and a
`KHR_materials_transmission` extension Godot cannot render. Nothing in the code
ever swapped them for the shaders — the shaders existed and were used by nothing.
*Fix:* `TreeV2.materials_for()` builds one `ShaderMaterial` pair per species
(cached and shared by every tree) and `_apply_materials()` overrides every
surface, matched by the glTF material NAME, not by surface index — a trunk with
no leaves has only one surface, so indices don't line up. The exporter also no
longer writes the transmission extension.

**2. No bark parallax — the wood had no UVs at all.**
Only the leaf cards got UVs; the trunk's were all zero, so the parallax march
smeared across a degenerate coordinate and produced whorls. *Fix:* bake tube UVs
in **metres** — u around the circumference, v along the limb — so texel density
is identical on a fat trunk and a thin twig. `tiling` is now "repeats per metre".

**3. Trees would not come down — limb HP was derived from the bounding box.**
A long thin branch has a big AABB, so nearly every limb came out at max HP: a
mature tree needed **~84 swings**. *Fix:* the exporter writes the true tube radius
into the object name (`Branch_03_r085` → 0.085 m) and `TreeBranch` parses it.
With `MAX_HP` 4 and 5 gating limbs, measured in-engine:

| | young | mature | ancient | withered |
|---|---|---|---|---|
| maple | 2 | 23 | 26 | 22 |
| birch | 2 | 19 | 25 | 16 |
| oak | 2 | 24 | 26 | 23 |
| pine | 2 | 19 | 26 | 18 |
| fir | 2 | 19 | 26 | 18 |

Young trees gate **zero** limbs — nothing on them is thick enough to be worth a
swing, so they go straight to the trunk. A sapling is one job; an ancient oak is
five limbs and then some.

**4. `Wind._declare` called an editor-only function.**
`RenderingServer.global_shader_parameter_get()` errors every call outside the
editor. *Fix:* just add the parameter — re-adding overwrites.

### Two things the render pass caught

- **Seasons were a permanent crossfade.** Straight lerping the four stops means
  "summer" exists for one instant of the year; the canopy read half-autumn in
  July. The ramp now **holds** each season and turns over the last 45%.
- **Bark colour balance.** In-engine, pine read peach and maple read pale grey.
  Both darkened; oak lightened slightly off near-black.

### What the pictures prove

`assets/trees/previews/godot_four_seasons.png` is one scene rendered four times
with nothing changed but `season_phase`: spring flush, deep summer, blazing
autumn, and a winter where the maples and birches are bare, **the oak still
carries its brown marcescent quarter**, and the conifers are frosted. That is
§7 working end to end.

### Still not verified in the real game

The tests run in an isolated lab project with stubbed `DroppedItem` / `CarryLog`.
Untested against the live game: the `Player.gd` chop path, the pin/knockdown
phase, save/load of tree state, and performance with 250 trees.

---

## 21. Round two — why they still would not come down

The first fix pass made trees *render*. It did not make them *fell*. Two more
bugs, both found by running the real project's scripts under Godot rather than
by reading them:

### Bug 5 — loading a save deleted the entire forest

`World.save_state()` only wrote nodes matching `if t is ChopTree`. `apply_state()`
cleared the whole `"trees"` group before restoring. So every `TreeV2` was
`queue_free()`d on load and **nothing came back** — the v2 forest was never
written in the first place. Silent, total, and it would have eaten a long save.

*Fix:* `save_state()` now writes `TreeV2` and `TreeStump` too; `apply_state()`
dispatches on the `"kind"` key and restores each type, falling through to
`ChopTree` for old saves with no `kind`. `TreeV2.from_dict()` +
`TreeStump.from_dict()` added. Part-chopped trees come back part-chopped: limbs
already taken stay gone, and trunk progress is preserved.

### Bug 6 — the limbs gating the trunk were nine metres over your head

Gating limbs were chosen by **thickness**, and the thickest limbs on a big tree
are high in the crown. The player swung at the trunk, an invisible branch
somewhere above lost a hit point, and nothing appeared to happen — for fifteen
swings. It read exactly like a broken axe.

*Fix, three parts:*

1. **Reach.** A limb only gates the trunk if its base is at or below
   `TreeBranch.REACH_HEIGHT` (4.5 m). You limb what you can reach; everything
   higher comes down with the tree.
2. **Lowest first, not thickest first.** A woodsman limbs from the bottom up,
   and the limb you just cut should be the one in front of your face.
3. **Say what the swing did.** `TreeV2.last_result` reports `limb` / `limb_off` /
   `trunk` / `felled` and `Player._chop_tree` puts it on the HUD every swing:
   "Limb down — 2 to go", "Limbed. Now the trunk.", and a one-time
   "Clear the limbs first" the first time you hit a blocked trunk.

`MAX_HP` is 3 and `MAX_LIMBS` is 4. Ancient trunks went 6 → 8 bites, because a
tall tree often has no reachable limbs at all.

### Measured, in the real project

| species | young | mature | ancient |
|---|---|---|---|
| maple | 2 | 12 | 11 |
| birch | 2 | 4 | 8 |
| oak | 2 | 16 | 14 |
| pine | 2 | 16 | 8 |
| fir | 2 | 16 | 20 |

**Not every species needs limbing, on purpose.** A slender birch is a pure trunk
job, and so is an ancient white pine — real white pines self-prune their lower
branches, so there is nothing down there to cut. A mature pine still has its low
whorls and is the harder tree. That asymmetry is forestry, not a bug, and the
suite asserts the shape of it rather than demanding limbs everywhere.

### Suite: 188 assertions, run against the real scripts

`tests/TreeTests.gd` now also locks down: every gating limb within reach, never
more than `MAX_LIMBS` of them, felling inside 22 swings, limbing mattering on at
least two species, and a part-chopped tree (and part-cleared stump) surviving a
save/load round trip.

---

## 22. Round three — the chop rules changed, and three things were broken

Lemon's call, and it replaces §8a outright: **limbs do not gate felling.** You cut
a wedge out of the trunk until it goes over. Limbing is still there and still
drops sticks, but only if you aim at a limb; it is never a requirement.

### The new chop loop

- Every swing at the trunk deepens a **notch** on the side you're standing on.
- The notch is carved into the trunk's own mesh — vertices pushed inward inside
  a wedge, deepest in the middle of the cut, tapering at the top, bottom and
  sides. It is rebuilt from pristine arrays each time, so depth never compounds.
- When the wedge passes the centre (`BREAK_AT`), the trunk goes over.
- Bites per stage: 1 / 3 / 5 / 7 / 4. The notch depth is the feedback.

### Bug 7 — the trunk was a stack of loose hoops

To carve a notch there has to be geometry to carve, so the generator now packs
rings every 12 cm through the chop zone. That exposed an old bug: **each segment
emitted its own pair of rings**, and the two rings meeting at a joint were built
from DIFFERENT segment directions, so they sat in different planes and the weld
pass could not merge them. At 1 m segments the overlap hid it. At 12 cm it opened
the trunk into floating bands with sky between them.

*Fix:* `_tube()` builds a whole limb as **one continuous tube** — one ring per
spine point, oriented by the average of the directions either side of it, then
bridged. Measured after: 348 verts, 336 polys, **24 boundary edges** (just the
two open ends) where before it was 672 boundary edges on 336 polys.

### Bug 8 — the fallen trunk froze standing up

`FallenTrunk._physics_process` froze the rigid body the instant it was slow —
which, on frame one before gravity had touched it, was immediately. It froze
bolt upright and never fell. It also spawned with its centre at ground level, so
half the log was underground.

*Fix:* a `MIN_FALL_TIME` before settling is even considered, spawn at
`base + half a trunk`, and a deferred impulse applied high on the trunk so it
hinges over like a real tree instead of spinning about its middle.

### Bug 9 — every leaf spray stood bolt upright

Leaf cards were built with their long axis on world +Z and only a random yaw, so
no matter which way a twig ran, its leaves pointed at the sky like grass.

*Fix:* the card's long axis is now the **twig's own direction** plus a per-species
gravity droop, and the base of the spray sits exactly at the twig tip (the atlas
cells are drawn stem-at-the-bottom, so `-v` is the attachment point). Droop per
species: pine 0.08 (needles sweep out), fir 0.24, oak 0.32, maple 0.36, birch 0.60
(it weeps).

### The forest had holes in it

140 trees over an 80 m disc is one tree every twelve metres — a savanna you can
see clean through. Now **420 trees grown in groves**: each new tree usually lands
2.6–6.5 m from the last one, sometimes starts a new stand elsewhere, and never
within 2.1 m of another trunk. Thickets and clearings instead of an even sprinkle.

### Also

Felled trunks and stumps now wear the species' real bark shader instead of a flat
colour, with tiling converted for their 0..1 cylinder UVs — a downed log is
exactly where you walk up close and the parallax earns its keep.

### Verified

237 assertions, run against the repo copy after patching, all green — including
"the first swing goes straight into the trunk", "that swing cut a notch", and
"no tree gates its trunk behind limbs". Rendered in-engine: the notch after four
swings, the trunk lying beside its stump, the closed tree line, and canopies with
the leaves coming out of the branches.

**Still not verified in the live game:** the Player chop path (the lab drives
`chop_hit` directly), the pin, and framerate with 420 trees — that count is well
past the 250 the budget in §11 was written for, so watch it.

---

## 23. Round four — the wound, the branches, and getting flattened by nothing

### Heartwood in the cut

Carving moved vertices but left bark on the cut face, so a notch looked like
dented bark. The carve now writes a per-vertex flag and the bark shader paints
**pale heartwood** inside the wound — no bark, no parallax (a saw face is flat),
and a rougher finish.

**The flag is INVERTED on purpose.** A mesh with no vertex-colour array reports
`COLOR = white`, so "1 = cut" painted *every branch in the forest* bright yellow
on the first try. White now means untouched bark and the carve writes values
below 1. If you ever add a mesh here, that convention is load-bearing.

### A felled tree keeps its branches

`_fell()` hands the whole model — carved trunk, bark, every limb — to the
`FallenTrunk` rigid body, and each limb over 1 m gets a small sphere collider.
The tree lands **resting on its own branches**, held off the dirt, instead of
lying flat like a telegraph pole. Limbs caught between the trunk and the ground
snap on impact and drop as sticks.

Tuning worth keeping: the first pass used fat props (up to 1.1 m) and the tree
stood there like a tripod at 20° off vertical. Props are now 0.10–0.38 m — enough
to hold it off the ground, not enough to hold it up.

### Bug 10 — felling knocked you down every single time

`_on_body_entered` swept a 2.2 m radius over every player and enemy and damaged
them all, so the crash flattened you wherever you were standing. It now hurts
**only the body it actually collided with**, and it only **pins** you if the trunk
is at least `PIN_ABOVE` (0.55 m) above you — landing alongside can knock you flat
at worst, it cannot hold you there.

### Bug 11 — every knockdown put your legs in your head

The eye dropped to half a metre but `body_rig` stayed standing, so in first
person the camera sat inside your own torso, looking up between your knees. The
rig now tips onto its back with the camera and slides forward, so your legs
stretch out ahead of you on the ground. The walking body-lean is gated on
`kd_phase == ""` so it can't fight the pose.

### Bug 12 — the leaves were a metre wide

"Only the pine looks right" was the clue. Every card was up to **1 m across**, so
a four-leaf spray read as a fern frond — and pine got away with it because long
needles at that scale are plausible. It is also why leaves looked like they were
floating: a card reached half a metre off its twig before the first leaf was
drawn.

Two fixes together: the atlas sprays now carry **9–17 small leaves** instead of
4–6 large ones (`lscale` roughly 0.42 where it was 1.0), and cards shrank to
0.15–0.36 m with more per twig, sitting with their base right on the wood.

---

## 24. Round five — dead trees, and craters that take trees with them

### The "trees with no leaves" were withered trees in living clothes

Every exported GLB has leaf geometry — checked, all 25. What was spawning bare
was the **withered stage**, which was 8% of trees, and it was wearing healthy
bark and *green* leaves. A dying tree read as a broken one.

So the answer to "trees spawning without leaves", "add dead textures", and "let
a tree die on a slim chance" is one system:

- **`TreeV2.dead`.** A snag: deadwood bark, bare branches, and a scatter of
  brown leaves that never fell (`dead_cling`, 9%). Dead wood is **brittle** —
  `BRITTLE` knocks 2 bites off the trunk.
- **Deadwood bark** (`tools/barkgen.py`, species id `dead`): silvered grey, deep
  vertical splits, patches peeled back to bare grain, almost no moss. **One
  shared set for all five species** — a dead trunk stops looking like an oak or
  a maple within a season, which is exactly why a snag reads as dead from across
  a clearing.
- **Who dies:** the withered stage is always dead, and any mature or ancient
  tree has a `SNAG_CHANCE` (2%) roll to be a standing dead tree at its own size.
  Withered spawns dropped from 8% to **4%**, so a bare tree is now a thing you
  notice rather than a thing you keep tripping over.

The stage-4 rule lives in `_ready()`, not in `make()` — a withered tree is dead
however it was built, including restored from a save.

### Bug 13 — a meteor crater left the tree hanging over the hole

`CaveRegion.meteor_strike()` carves a 4.6 m sphere out of the ground and told
nothing about it, so a tree standing on that spot kept standing with its base
swallowed — which is what "deleted the trunk from the ground" looked like.

`World._meteor_impact()` now fells every tree within `METEOR_FELL_RADIUS` (7.5 m)
via `TreeV2.blast_fell(from)`: it goes over **away from the impact** and leaves a
real trunk you can buck. It leaves **no stump** — the crater took that too, which
is why `_fell()` grew a `leave_stump` argument.

`blast_fell()` is deliberately general. Anything else that should put a tree
over — a giant, a landslide, a collapsing building — calls the same method.

### Verified

247 assertions green, including that a snag gets its own bark and leaf
materials, that the dead flag reaches the foliage shader, that dead wood is
brittle, and that a blasted tree leaves a trunk but no stump.
