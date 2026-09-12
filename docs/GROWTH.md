# Growth patches — moss, fungi, vines, lichen (2026-09-03)

What creeps over a trunk, a boulder, or the brow of a cave mouth, and grows
there over game time. One reusable node (`GrowthPatch`), one catalogue
(`GrowthTypes`), one clock (`GrowthClock`), one shader (`growth.gdshader`).

## The two layers

| layer | what | how it is drawn |
|---|---|---|
| **base** (layer 0) | the film that hugs the surface — moss cushions/sheets, mycelium web, ivy leaves, lichen crust | flush cards a centimetre off the surface |
| **accent** (layer 1) | what stands proud once the base is established — bracket fungi, toadstools, hanging vine strands, beard lichen, sporophyte tufts | shelf / cross / hanging cards |

A patch is one **family** × one **base** × one **accent**. Families and their
variants live in `GrowthTypes.TYPES`; add a row there and it exists.

| family | bases | accents | speed | loves rain |
|---|---|---|---|---|
| moss | cushion, sheet, feather, peat | sporophytes, buttons, lichen_spots | 1.0 | ×1.2 |
| fungi | mycelium, rot, mould | brackets, toadstools, conks, teeth | 1.35 | ×1.6 |
| vine | ivy, tendrils, creeper | strands, curls, blooms | 0.75 | ×0.8 |
| lichen | crust_grey, crust_orange, crust_mint | beard, cups, shields | 0.45 | ×0.5 |

Both layers are slightly transparent (`opacity` per family, base ~0.8,
accent ~0.9) so the bark or stone reads through.

## How it grows

Every card carries a **birth** (0..1) by its distance from the patch's heart;
accents are born from 0.45 up. The patch has one `growth` float, an instance
uniform, and the shader fades and swells each card in as `growth` passes its
birth — so the patch spreads outward and the mushrooms arrive on top of the
moss. Nothing is rebuilt as it grows.

`GrowthClock` (World adds it) ticks every 1.5 s and advances every patch by
**game hours** elapsed — sleeping a week grows a week — times:

- **rain**: `1 + 2.0 × family.wet × (Weather.wetness + host.damp)` — wetness lags the
  rain, so moss keeps growing after a storm; a cave mouth has its own `damp`.
- **shade**: full sun halves it (× `family.shade`); north faces and undersides are shaded
  (`GrowthPatch.shade_for`, north = −Z as in bark.gdshader).
- **season**: autumn 0.65, winter 0.15.
- `GrowthClock.SPEED` — the dial. `DAYS_TO_FULL = 40` game days for moss, half shade, dry.

A loaded patch **catches up** on the game days the save slept through at a
nominal 0.3 wetness.

## Where it lands

The patch probes its host with rays and lays a card on every hit:

- **trees** — `TreeV2` rolls 0–3 patches from its own seed the frame after
  `_ready` (moss mostly; fungi on dead wood; lichen on birch; a vine on an
  ancient). Low on the trunk, on the shaded side. The probe is a throwaway
  trimesh of the **real trunk mesh** (bark relief included), not the cylinder
  collider, so the cards sit on the bark. Old trees start partly grown
  (`GROWTH_START` per stage); a sapling starts bare.
- **boulders** — `World._dress_rock`: moss on the north/under face, lichen on
  top. Probes the tilted mesh, not the axis-aligned box collider.
- **cave mouths** — `CaveRegion._dress_growth`: moss over the brow of the cap,
  lichen/moss/vine on its north flank, fungi shelving both throat walls just
  inside the gate. Probes the **world** (mask 1); the cap's trimesh colliders
  arrive deferred, so a patch that finds no stone waits and retries.

## Saving

- A `TreeV2` carries its patches in `save_dict()["growth"]` and `restore()`
  rebuilds them from the same seed on the same anchor — the same cards come
  back — then catches up. Hand-placed trees go through the same dict in
  `design/build_placements.json`, so their moss survives a new run.
- Boulders and cave mouths are rebuilt from the world seed and never
  serialised, so their patches carry a `host_key` (`rock:3:side`,
  `cave:0:brow`) and World keeps a `"growth"` ledger in the save; on load the
  live patch with that key is handed its saved growth.

## Adding one by hand

```gdscript
var g := GrowthPatch.make("fungi", "", "", randi())      # family, base ("" = roll), accent, seed
g.anchor_cylinder(0.8, ang, 0.5, 0.9, 3.0, 1.0)          # y, angle, span up, span round, reach, m²
# or: g.anchor_point(centre, facing, pitch_span, yaw_span, reach, inward, m²)
g.probe_meshes = [trunk_mesh_instance]                    # empty = probe the world
g.shade = GrowthPatch.shade_for(world_facing)
host.add_child(g)                                         # host-local frame; the patch sits at the host origin
```

`TreeV2.add_growth_patch("moss", seed)` does all of that for a tree — the hook
for a future Trees-tool chip in the god editor.

## Tests

- `tests/GrowthTests.gd` — 100 assertions, headless: catalogue, atlas tiles,
  probe-off-a-mesh, probe-the-world, cards hug the bark, determinism (the same
  dict lands vertex-identical cards), draw order, growth maths, clock, save /
  JSON / catch-up.
- `tests/GrowthTreeProbe.gd` — the real kit trees: 15 species×stage trees roll
  patches, 1,416 card pivots all on the taper, save → JSON → restore gives the
  same patches, not a re-roll.

## Traps

- `Mesh.surface_get_primitive_type` exists only on `ArrayMesh`; a `BoxMesh`
  host mesh has to be read through `surface_get_arrays` without it.
- The patch must be a direct child of its host at the identity transform:
  patch-local *is* host-local, and the probe faces are built in that frame by
  walking the parent chain — no global transforms, so it works the frame the
  host is added.
- Round atlas tiles fade to nothing before the tile edge, or the square card
  cut shows as a hard line through the moss.
- The wisp tile is painted rooted at the TOP; standing it up as a tuft (a
  sporophyte) means rooting it at v = 0, unlike the toadstool tiles.
