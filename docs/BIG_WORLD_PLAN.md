# BIG_WORLD_PLAN.md — the multi-kilometer world (with biomes)

> Decided 2026-07-22 with the user: target is a **multi-km overworld with real
> biomes** (lowlands → forest → mountains → snowy peaks, per DESIGN.md), and
> **dig-anywhere stays — but surface holes HEAL over time**. That one design
> call is load-bearing: healing digs are temporary state, so the overworld can
> be cheap streamed heightmap terrain (no per-tile carve persistence, bounded
> memory) while full voxel digging spawns in on demand wherever the pickaxe
> lands. The earth closing over its wounds is also just… The Withering.

**Read this with:** `CONTEXT.md` (current world = ONE 208×208 m CaveRegion,
its grass-skinned top IS the ground) · `docs/CAVES_PLAN.md` (the voxel
pipeline this plan reuses) · `docs/DESIGN.md` (biome gradient, ore economy).

---

## THE SHAPE

Three layers, cheapest possible per square meter:

1. **OVERWORLD — streamed heightmap tiles (the multi-km part).**
   Grid of tiles (~64 m) generated on worker threads in a ring around the
   player, unloaded behind. Per-tile deterministic seed. Heightfield +
   biome-colored surface mesh + trimesh collision + grass + tree/rock/POI
   scatter. A tile is CHEAP (65×65 height samples) — that's why the map can
   be kilometers where the voxel world could not.

2. **DIG PATCHES — lazy voxel islands (the dig-anywhere part).**
   Pickaxe bites overworld ground → spawn a small voxel patch (~19.2 m =
   24 cells square, deep enough for honest shafts) SEEDED FROM THE HEIGHTMAP
   so its surface matches the tile exactly; swap that footprint's collision
   to the patch and carve as today (`carve_bite` unchanged). **HEALING**: a
   slow clock refills carved cells toward the original field (sleep heals
   everything instantly — the world already shifts under you); a patch with
   no wounds left EVAPORATES back to plain tile. Healing = the garbage
   collector: no surface dig is ever saved. Depth guard: past ~10 m of
   overworld dirt the pick meets "unyielding earth" — unless the shaft has
   struck a real cave region below, in which case it BREAKS THROUGH.

3. **CAVE REGIONS — today's CaveRegion, placed as dungeons.**
   15–30 systems scattered across the map (seeded), each ≈ today's
   208×208×43 m field with mouths, zones, veins, dwellers, champion — the
   whole existing pipeline, deferred-deep-loaded on approach exactly as now.
   Digs INSIDE cave regions stay permanent-ish (permanence bubbles, sleep
   reshuffles) and are the only carve data the save system ever stores.

---

## PHASES (game runnable after every one — house rule)

**P0 — Parameterize the region.**
Kill every assumption that there is ONE region under everything: CaveField
origin/size become constructor args; World keeps a region REGISTRY; Player's
dig path asks "which diggable field owns this point?" (group lookup);
GrassSystem binds to its region, not the world. Zero visible change.

**P1 — Overworld tile streamer (skeleton).**
TileManager: seed → heightfield → mesh+collision on WorkerThreadPool,
activate ring (~5×5), free far tiles (hysteresis so walking a border doesn't
thrash). Flat-ish noise first, today's palette. The current region embeds in
it as "the first valley." Border walls move to the world rim. Out-of-bounds
rescue + meteor targeting + titles learn about tiles.

**P2 — Biome stack.**
Elevation + moisture noise (continent-scale frequencies) → biome id per
point → per-biome: surface palette, grass colors/density (GrassSystem
per-tile), tree set (the Blender pipeline's oak/pine/birch/willow by biome),
rock/boulder scatter, mob tables, fog/ambient tint. Mountains rise, peaks
snow. Biome names feed the location-title system ("The Frostfell Moors").

**P3 — Dig patches + healing.**
The lazy voxel patch above. Design calls to make in-build: heal RATE
(game-hours? days?), heal VISUAL (cells crumble back quietly vs. visible
regrowth — lean quiet + a log whisper "the earth has closed over"), whether
healing pauses while the player stands in the hole (it should), hardpan
depth, breakthrough-into-cave-region moment (a title, absolutely).

**P4 — Cave regions as placed dungeons.**
Placement pass (seeded, biome-aware: kobold warrens under forest, orc/ogre
deeps under mountains, the best metals under the peaks per MATERIALS).
Mouths dressed per biome. Meteor events pick loaded tiles and can leave a
CRATER PATCH (a dig patch variant that heals much slower — a scar).

**P5 — Persistence (small, at last).**
Save = player + stats/inventory + per-cave-region sparse carve deltas +
world seed + clock. Surface patches save NOTHING (they heal). This is
roadmap step 10's save system arriving through the world work.

**P6 — Streaming polish.**
Frame budgets (tiles/meshes per frame), priority by distance+heading,
memory caps, spawn/despawn budgets for mobs & horses per tile, a debug
overlay (tiles live, patches live, heal queue, ms per stream step).

---

## HONEST NUMBERS & LIMITS

- 4×4 km @ 64 m tiles = 62×62 grid; active ring 5×5 ≈ 25 tiles — trivial
  memory. Cave regions load at most 1–2 at once (they're far apart).
- Godot 32-bit floats are comfortable to ~8 km from origin; beyond that we'd
  add origin shifting or a double-precision build. 4 km needs neither.
- Seams: heightmap tiles knit trivially (shared edge samples). Patch↔tile
  seams hide because the patch surface is SEEDED from the same heightfield
  (± vertex jitter kept at zero on the boundary ring, the CaveRegion rim
  lesson). Cave-region tops keep their existing grass-skin treatment.
- The gameplay layer (combat, climbing AI, horses, loot physics, torch/TP
  body) is already world-agnostic — group lookups, no scene wiring. The
  couplings to touch are exactly: Player dig paths, World._process, grass
  binding, walls/rescue, meteors. All named above.

## WORKFLOW (how we build this together)

Claude can't run Godot in its workspace — so each increment lands as: Claude
builds a phase slice + updates docs → user playtests in-editor and reports
(what it looks like, frame feel, anything weird) → tune → next slice. Phases
are sliced so every hand-off is runnable and SEEABLE (P1's first visible
milestone: walk off today's map edge onto endless rolling placeholder hills).
