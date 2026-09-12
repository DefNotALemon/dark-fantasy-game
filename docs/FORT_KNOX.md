# Fort Knox

The granite work on the west bank of the Penobscot narrows, across the water
from Bucksport. Begun in 1844 in our world and never finished; built here in
one pass at boot and left to the moss.

Files: `scripts/FortKnox.gd`, `tools/patch_fort.py`, `tests/FortTests.gd`.
Flag: `World.USE_FORT` — one `false` and the fort, its punched hole and its
map marker all stay out of the world.

---

## Where, and why there

World XZ **(2636, -1946)**, parade at ground + 2 m (about y = 20).

That spot was picked off the bake, not off a map. The Penobscot channel runs
north–south at x 2700–2810 and opens into the bay to the south-west; the west
bank rises from 12 m at the water's edge to 19 m about 120 m inland. The fort
sits on the shoulder of that rise, so the land approach is at grade and the
river front stands on a 4 m granite plinth over the bluff — which is what the
real one does. The Bucksport marker is 217 m north-east, across the water.

The whole punched rect (see below) was checked cell by cell against
`maine_water.r16`: **no water cell anywhere inside it**. The shoreline starts
at local x +64; the punch stops at +52.

Note the map is roughly 1:47 — 10.8 km of world for 510 km of Maine — so at
player scale the fort is a genuinely large landmark, about 90 m across the
angles, and the narrows in front of it are about 110 m wide.

---

## The three things that will bite you

### 1. The punched hole

The undercroft is **genuinely below the heightfield**, 7 m under the parade.
That only works because the fort cuts its own rect out of the terrain, mesh
and collider both — the same mechanism the spawn valley uses for
`CaveRegion`, generalised in this pass:

```gdscript
Overworld.punch_hole(rect: Rect2, sink: float)   # world XZ
Overworld.clear_holes()                          # tests only
```

`in_hole()` now consults a registry of runtime rects on top of the spawn
square, and `_collision_heights()` sinks each one to its own floor. Boundary
samples keep their real height (`Rect2.grow(-0.01)`) so the collider still
meets the surrounding ground flush.

**A hole takes the ground away and puts nothing back.** Whatever punches one
owes the world a floor. Here that is the raft and the apron. If you move the
fort and forget to move `PUNCH_X` / `PUNCH_Z`, you get a rectangular window
into nothing, 100 m wide, visible from the far bank.

The sink is `-22`, deliberately **above** `World._out_of_world`'s -60 m
trapdoor: someone who clips through the raft lands on the fort's own bottom
slab instead of being teleported back to spawn with no idea why.

### 2. One mesh per material

Every box, voussoir and stair tread goes into `_boxes` and is baked into a
single `ArrayMesh` per material at the end. The finished fort is **2,110 solid
boxes in 14 meshes** — about 28,700 triangles and 14 draw calls, not 2,110.
Per-block colour variation rides in the vertex colours, which is why one
shared `StandardMaterial3D` per id is enough. That is the trap the
optimisation audit found in `Enemy._box` (1,530 unique materials); do not
reintroduce it. **Never add a bare `MeshInstance3D` here — put it through
`_box`.**

Collision is separate and cheap: plain `BoxShape3D`s on one `StaticBody3D`.

### 3. The frame

Local **+X is east** (the river), **+Z is south**, **y = 0 is the parade**.
`CORNERS` runs clockwise. For a wall `a -> b`:

- `_outward(b - a)` is the field side, `_inward()` the parade side
- `_yaw_of(b - a)` yaws a box so its **local +Z runs along the wall** and its
  **local +X is the outward normal**

So a wall-aligned box is `Vector3(depth_through_wall, height, width_along_wall)`.
Getting that pair the wrong way round is the single easiest mistake in this
file: it turned every casemate pier into a 7 m slab lying *along* the face,
which walled the gun rooms off and blinded their ports. `FortTests` catches
both the normal flip and the axis swap.

---

## What is in it

| | |
|---|---|
| Main work | irregular pentagon, ~90 m across; five curtains 8 m over the parade, 2.6 m thick |
| River faces (1, 2) | 10 casemates, each a barrel vault behind a **real** opening in the curtain |
| Land faces (0, 3, 4) | rampart walk 4.4 m wide behind merlons, dry ditch outside |
| Gate | sally port through the west curtain, portcullis half down, timber bridge over the ditch |
| Spiral stairs | two, on the passage line at z ±28 — undercroft → parade → rampart, ~74 treads each |
| Undercroft | vaulted passage, two powder magazines, hot shot furnace and flue, postern out to the ditch |
| Water battery | on the bluff shoulder below the east front, guns looking down the narrows |
| Light | 11 shadowless sconces, distance-faded; the darkness itself is free (below) |

### Darkness for free

`World`'s fog/ambient blend rides **depth below the local heightfield**, not
an indoor flag. The undercroft is 7 m under it, so the existing cave gloom
applies with no new code at all — that is why the tunnels are dug rather than
built into a raised earthwork. The sconces only make it navigable.

The one thing that needed saying is the *name*: `World._place_title_for()`
gives the fort its own title, so standing in the magazine reads
"Fort Knox — the Undercroft" and not "The Hollow Depths".

### The map marker, for free

`Overworld.places()` hands back the live array, so `World._build_fort()`
appends one record:

```gdscript
{"name": "Fort Knox", "pos": [2636.0, -1946.0], "y": pad_y, "rank": 1}
```

That is all a landmark needs. `MapPanel._draw_places` gives it a dot and a
label, `place_name_at` gives it the on-screen title through the existing 0.6 s
tick, and click-to-travel already resolves it. No edit to `MapPanel.gd`.

---

## The raft and the apron

The two things that put ground back inside the hole.

**Raft** — the structural mass, local x -42..47, z -44..44. A slab lid (with
the stair wells and the flue left open), a run-merged fill that stops at each
undercroft room's vault crown, a skirt down past the lowest ground in the
footprint, and a bottom slab. The fill is merged into runs per row so a solid
quarter of the raft is a handful of boxes, not four hundred.

**Apron** — everything between the raft and the punch edge, rebuilt as 4 m
cells that follow the real terrain height, with the dry ditch cut into it by
dropping cells in the ditch band to `DITCH_FLOOR`. Rim cells run 5 m past the
punch edge so the seam with the live terrain is buried under stone. This is
also the only way the ditch can be a real excavation: you cannot dig a trench
into terrain that is still there.

The cells terrace the bluff a little. That reads as the cut the fort was set
into and matches the blocky language of everything else in the game, so it is
left alone on purpose.

---

## Tests

```
godot --headless --path . --script res://tests/FortTests.gd
```

**99 assertions, all green.** It runs with no renderer, no physics frame and
no terrain: `FortKnox.build_flat()` stands the fort on flat ground and
`keep_probe` retains every solid box so `solid_at()` / `clear_line()` can
answer "is this point inside stone?" analytically.

That is the point of the suite. A fort made of boxes is easy to get wrong in
ways a box count never catches, so **every opening is proved by walking a line
of samples through it** — the same thing the player's body will do, minus the
physics server. It found six real defects in this pass:

1. the raft was a hollow box with a lid — 60% of the parade stood over nothing
2. the magazine throats were sealed by the passage's own side walls
3. two gun ports near the salient looked into the neighbouring face
4. the stair wells were capped by the parade lid, so neither stair connected
5. three sconces were buried inside the oven and the newels
6. the casemate piers had their depth and width swapped (see "the frame")

`MIN_ASSERTIONS = 95` is the lost-section floor — the `await`-drops-the-rest
trap from `docs/WILDLIFE.md` applies here too.

Not covered headless, because they need the bake: the punched hole against
real tiles, the place record, and how it looks. Those are the live pass.

---

## Concurrency

`tools/patch_fort.py` is marker-guarded and **proven idempotent** — a second
run adds nothing and leaves `World.gd` and `Overworld.gd` byte-identical.
`World.gd` has now silently lost work twice to duelling patchers, so the safe
move is always to re-run this against the **live** file rather than commit a
copy edited from a stale read. It was: `World.gd` gained a main menu from
another session midway through this one, and re-running the patcher picked
that up cleanly.

Markers stay on one line each. A marker that gets line-wrapped in the output
never matches again, and the next pass duplicates its hunk.

---

## If you want to change it

- **Move it**: `SITE_X` / `SITE_Z`, and re-check `PUNCH_X` / `PUNCH_Z` against
  the water map. `FortTests._frame` asserts the punch contains the raft *and*
  the whole ditch.
- **Reshape it**: `CORNERS` (keep them clockwise), `RIVER_FACES`, `GATE_FACE`.
- **More or fewer guns**: `PORT_SPACING`, `FACE_INSET`.
- **Turn it off**: `World.USE_FORT = false`.

### Hooks left open

- Nothing lives in it. It joins group `"fort"`, not `trees`/`beds`/`psx_props`
  — `World.apply_state` sweeps those on load and would delete it. Adding
  garrison mobs means a spawn record, not geometry.
- No `GrowthPatch` yet. Moss and vines on the granite would suit it; the patch
  system wants `probe_meshes` and a `host_key` in `World`'s growth ledger, and
  the merged meshes make each patch large, so it needs a pass of its own.
- Save contract: none. The fort is world seed, identical every run, like
  `World`'s boulders. Give it state (a broken gate, a looted magazine) and it
  needs an entry in `World.save_state`.
