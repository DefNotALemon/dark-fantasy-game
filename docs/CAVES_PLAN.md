# Caves 2.0 — Full Redo Plan (organic noise caves, realistic high-poly)

> Read this first when resuming cave work. Complete replacement of `Cave.gd`'s
> swept-tube/dome builder AND its room-grid planner. **No rooms, no graph**: caves are
> continuous noise-carved systems — winding tunnels that widen into caverns and pinch
> into fitable cracks entirely on their own, like real caves (Minecraft 1.18 noise
> caves, but flat-shaded realistic low poly). Meshed with chunked marching cubes.
> Last updated: 2026-07-14. Status: **CORE BUILT — CaveField.gd + CaveMesher.gd +
> CaveRegion.gd + RockDebris.gd live; old Cave.gd retired. Pickaxe digging works
> (bites carve + remesh, rocks fall, ceiling slabs hurt, dig-to-surface possible).
> NEXT: in-game walkthrough + noise tuning, then dressing/analysis passes below.**

## THE USER'S BRIEF (verbatim spirit — this is the contract)
Completely procedurally generated caves that are tunnels that realistically open into
wider gaps, sometimes with small narrow-but-fitable cracks leading into more caves.
Realistic like real-world caves but still fun. Inspiration: Minecraft realistic-mod
caves that are round and expand and shrink on their own. **Drop the room system** —
caves are bigger and smaller as they please.

## ARCHITECTURE — three noise fields, one rock
The underground is solid rock; density = rock minus the union of three carvers
(Minecraft 1.18's own recipe, tuned for on-foot melee):
1. **Worm tunnels ("spaghetti")** — ridged 3D noise near its zero-surface makes long
   winding tubes. Tube radius is modulated by a second low-frequency noise, so the
   same tunnel swells to 6–8 m and chokes to 1.5 m over its length — expansion and
   shrinkage come free, no authored rooms.
2. **Caverns ("cheese")** — very low-frequency 3D noise blobs. Where a tunnel grazes
   a blob, it "realistically opens into a wider gap" — that's the whole mechanism.
3. **Cracks ("noodles")** — a thin, high-frequency spaghetti variant: shoulder-width
   slots and crawl seams that connect otherwise separate systems. Guaranteed fitable
   (min clearance ≈ 0.9 m wide × 1.9 m tall along their spine — squeeze, not block).
Plus **domain warp** over everything (no straight lines survive) and a **depth ramp**:
carvers get more generous with depth, so systems grow grander the deeper you go.

## MAKING IT A GAME (fun guarantees on top of honest noise)
- **Mouths**: each region's entrance is a craggy grass-topped MOUND rising out of
  the flat forest floor with a dark walk-in archway bored through its face (built
  in the field itself: rock heaped above y=0 + a Chaikin-smoothed capsule tunnel,
  ≤30° floor, 1.9 m+ headroom — sim-verified). A lit crystal just inside makes it
  glow at night. Regions may interconnect through cracks — getting from cave A to
  cave B underground is allowed and cool.
- **Connectivity pass**: flood-fill the voxel grid from each mouth. Unreachable air
  pockets either get a crack carved to them (secret made findable) or stay sealed as
  pickaxe-breakable calcite pockets (mining opens *space*, not just veins).
- **Walkability**: gravity floor pass — where a cavity's floor slope is gentle, flatten
  toward walkable (sediment fill, like real cave silt); steep spots keep ledges. Player
  step-up (0.45) + jump must always beat the terrain along the flood-fill spine.
- **The deep prize**: deepest large cavern found by analysis = meteoric vein + heavy
  guard. Silver seams sprinkle mid-depth walls. Veins sit on real wall normals (field
  gradient).
- **Cavity classification drives everything else** (no rooms, so analysis replaces
  them): each air region gets tagged by local size — *crack / tunnel / gallery /
  cavern*. Spawn tables, decor, and titles key off tag + depth, e.g. big mid-depth
  cavern → goblin warren nest; huge deep cavern → orc/ogre ground; the single biggest
  → champion's court ("The Sunless Court" title, dark knight + retinue).

## LOOK (realistic low poly, ~10× current tris)
- Chunked **marching cubes** (~0.5–0.7 m voxels, 32³ chunks), flat normals, slight
  vertex jitter — hewn angular rock, no smooth blobs. SurfaceTool → ArrayMesh +
  trimesh collision, generated threaded at world build.
- **Strata banding** via vertex color by depth + warped noise: slate/indigo base rock,
  frost tint near the surface band, ember-warmed stone in the deeps.
- **Formation dressing sampled on the mesh**: stalactite forests where ceilings are
  low + wet, floor-to-ceiling columns, erosion scallops (the domain warp does these),
  breakdown boulder piles in caverns, crystals (frost-blue mid, ember deep) as the
  light anchors, glowworm ceiling specks over still water, black mirror pools in flat
  cavern floors, roots + daylight shafts within ~8 m of the surface.
- **Mood by depth** (not bands with borders — continuous ramps): daylight dies over
  the first 10 m, fog thickens, crystal pools of color get rarer, the deeps are
  torch-black. Location titles fade in off cavity tags ("The Hollow Depths" stays for
  the whole system; big finds get their own).

## TECH PLAN (game stays runnable at every step)
1. **`CaveField.gd`** — pure-math density: base rock, 3 carvers, domain warp, depth
   ramp, mouth worms, calc of min-clearance along crack spines. Seeded, no nodes.
2. **`CaveMesher.gd`** — chunked marching cubes + flat normals + jitter + strata
   vertex colors + trimesh collision, WorkerThreadPool at world build.
3. **`CaveAnalysis.gd`** — voxel flood fill from mouths; cavity tagging (crack/tunnel/
   gallery/cavern + depth); connectivity fixes; walkable-spine check; pick vein spots,
   spawn spots, prize cavern, title spots. Replaces the old layout planner.
4. **`Cave.gd` slims to an orchestrator** — keeps `mouth/dir/cave_seed` API so
   `World.gd` barely changes; hill/mouth dressing stays; tubes/domes/grid retire.
5. **Dressing pass** (formations, crystals, pools, glowworms, roots) on mesh samples.
6. **Rewire** veins/dwellers/titles to analysis output. Bestiary/loot untouched.
7. **Perf pass**: tri budget ~200–350k per region, chunk culling, measure first.

## REVIEW LOOP
Land field+mesher with bare rock first (walk it, feel the shapes) → tune noise until
the *caving* is fun (this is the make-or-break iteration — expect several rounds on
frequencies/radii) → then analysis + spawns/veins → then dressing, one family at a
time. Old caves stay in the scene until the new walk-through is approved.

## SHIFTING CAVES (step 9, don't build yet — but this is the foundation)
Re-seed the carvers beyond a stability bubble around the player, remesh chunks
off-screen: the labyrinth rearranges. Field+mesher+analysis are exactly the pieces
that make it cheap later.

## OPEN QUESTIONS — TODO(design)
- Water: visual mirror pools only for v1 (no swim), or shallow wading slow?
- Crack claustrophobia: camera pull-in / shoulder tuck while in a squeeze? (juicy,
  cheap: lerp FOV + viewmodel in when clearance < 1.2 m)
- Do cave-ins (pickaxe-triggered or scripted) drop real boulders? Later.
- Mob navigation in cracks: big mobs (ogre) simply can't fit — feature, not bug?
  (escape routes the ogre can't follow = fun) — needs a nav check so they don't hump
  the wall forever.
