# Myrkfell — Optimization audit (2026-08-24)

Every number here was **measured** against the real repo scripts under headless Godot
4.4.1 (`tests/CostAudit.gd`, left in the repo so it can be re-run after any fix).
Nothing in this doc is a guess.

## The headline

**You were right.** The game builds every mob in the world during `World._ready`,
before the loading curtain lifts:

| Where | Bodies at boot | Nodes | Unique materials | Build time |
|---|---|---|---|---|
| Cave dwellers (`CaveRegion._spawn_dwellers`) | **71–132, mean ~101** | ~2,300 | ~1,530 | ~43 ms |
| Surface (5 boars + 2 saddled + 7 wild horses) | 14 | ~430 | ~316 | ~8 ms |
| Trees (`_build_forest`) | 420 | 420+ | shared shaders (good) | ~32 ms+GLB loads |
| **Total hostile/passive mobs** | **~115** | **~2,700** | **~1,850** | |

Per-body cost, measured: a Goblin is 21 nodes / 14 meshes / **14 unique
StandardMaterial3Ds**; a DarkKnight 25 / 18 / 18; a Horse 34 / 25 / 25. Every box in
`Enemy._box()` allocates its own material, so ~101 cave mobs = ~1,530 materials the
renderer must sort, none shared.

And they never sleep all the way: `Enemy._physics_process`'s far-away early-out still
runs **every physics frame for every mob** — it calls `_get_player()`
(`get_nodes_in_group`, a fresh Array allocation) and then `move_and_slide()` on a body
nobody can see. At ~101 mobs that is ~6,000 group lookups + 6,000 physics solves per
second spent on an empty cave. The wildlife system already proved the right pattern:
26 live critters, spawn ring 26–62 m, despawn at 96 m, and the woods still feel full.

## Ranked fixes

### 1. Stream the cave dwellers (the one you asked about) — biggest win
Turn `_spawn_dwellers` into a **lair ledger**: at world build, roll the same tables but
store *records* — `{pos, class, count, alive}` — instead of instantiating. A director
tick (underground only) instantiates a lair's pack when the player comes within ~45 m
of its pocket and dissolves it back to the record (with current health/dead count) past
~70 m. Deaths mark the record so cleared lairs stay cleared; save/load serializes
records, not bodies.
**Effect:** boot cost for hostiles drops from ~101 bodies / ~1,530 materials to **0**;
steady-state live hostiles ≈ 0 on the surface, ≈ 1–3 packs underground. The world plays
identically — the packs were always waiting in the dark; now the dark is honest about it.

### 2. Share enemy materials — second biggest, one function
`Enemy._box()`/`_box_in()`: replace `StandardMaterial3D.new()` with a static cache keyed
by `(color, metal)`. Mobs of a species already use identical palettes, so ~1,850 unique
materials collapse to a few dozen shared ones — fewer GPU state changes every frame,
cheaper spawns forever. ~10 lines. (Keep `body_mat` per-instance for the hit-flash tint;
everything else shares.)

### 3. Make sleep actually sleep
In the far-away branch: cache the player reference (refresh on a 1 s timer instead of a
group query per frame per mob), and skip `move_and_slide()` entirely when on-floor with
~zero velocity. Optionally tick the whole sleep check at 10 Hz round-robin. Turns the
sleeping-mob cost from ~6,000 solves/sec to ~0.

### 4. Put boars & horses on the wildlife contract
`_spawn_enemies`/`_spawn_horses` hand-place 14 bodies at boot. The WildlifeDirector
already streams 65 species with budgets, rings and save/load — register boar/horse
spawn intents with it (or mirror its ring logic) and the surface starts empty too,
filling as you walk. Saddled camp horses can stay hand-placed; they're 2 bodies and
they're *yours*.

### 5. Trees: cheap wins only (already mostly healthy)
420 trees load shared GLBs and shared shaders — fine. Two cheap adds when you feel like
it: `visibility_range_end` on tree meshes (distant-tree impostor/cutoff), and defer the
5 × 5 GLB `load()` set to a background thread so the curtain lifts sooner.

### 6. Grass v2 (done, this session)
LOD ladder + per-kind culls landed with the rewrite: ~210k grass triangles on screen
worst case with curved blades, vs ~116k flat ones before — more realism per triangle,
wider draw ring, and the far field costs 3 tris a tuft.

## What NOT to bother with

- `CaveField`/`CaveRegion` generation — already threaded, shallow-first, deep carved
  off-screen. Well built; leave it.
- Wildlife budget (26) — already the model everything else should copy.
- The audio layer — `_distant_tick` is exactly the cheap-world trick; extend it to
  hostiles if anything (distant goblin drums you'll never meet).

## Suggested order

2 → 3 → 1 → 4. The material cache and sleep fix are ~30 lines combined and de-risk
everything; the lair ledger is the real feature and lands cleanly on top; the wildlife
handoff is polish.

Say the word and I'll build the lair ledger + material cache next session, tests
included, same drill as wildlife.
