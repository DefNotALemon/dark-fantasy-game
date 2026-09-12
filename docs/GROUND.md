# Ground textures — scripts/GroundPaint.gd (2026-09-03)

The ground sheet in the game, and a brush for it. Lemon: *"those look amazing,
can you add that to the game with the dev mode being able to paint them?"*

## What is on the ground now

The overworld ground used to be one flat tint per vertex (`maine_color.png`)
dressed up by the shader's texel cells. It still is, underneath — but every dry
4 m bake cell now wears a **real, seamless 256 px texture** from the sheet:

```
                A      B      C      D      E      F      G      H      I      J      K
              lush   dry    patchy dirt   mud    forest barrens gravel sand   moss   snow
 1  BotW
 2  Arceus
 3  Tsushima
 4  Skyrim
 5  RDR2
 6  PSX
 7  Realistic-pixeled (house)          <- the default WORLD STYLE
 8  Minecraft
 9  Stardew
10  Valheim
11  The Withering (house)
```

A tile is named by its grid ref, `7-B`, and numbered `id = row * 11 + column`
(1..121). `tools/groundsheet.py` generates all of it — every tile is periodic
noise, so it repeats without a seam.

### Two layers decide what a cell wears

| | file | value per cell | who writes it |
|---|---|---|---|
| **base** | `assets/terrain/maine_ground.dat` | the bake's ground class as a sheet **column** 1..11, 0 = water | `tools/groundclass.py`, from `maine_color.png` |
| **paint** | `design/ground_paint.dat` | a **tile id** 1..121, 0 = nothing | the god editor's Ground tool |

and one number, the **world style** (`design/ground.json` → `row`):

```
worn = paint            if paint > 0
     = row * 11 + base  if row >= 0 and base > 0      (the whole map re-styles from one number)
     = the old tint     otherwise
```

Both maps are L8 images on the bake grid (1800 x 2700, row 0 = north, cell
`(i, j)` centred at `(x0 + 4i, z0 + 4j)`), stored as **PNG bytes under a `.dat`
name** so Godot never imports them — a lossy or re-formatted import would
corrupt the ids. `GroundPaint._png_bytes()` reads them with
`Image.load_png_from_buffer`. The atlas (`ground_atlas.dat`, 2816 x 2816) is
stored the same way and sliced into a `Texture2DArray` at boot (~150 ms).

**Export note:** like `*.r16`, these are not resources — `*.dat` must be in the
export include filter or the ground is bare in an exported build.

### The bake's classes → columns (`groundclass.py`)

forest, pine → **F** forest floor · meadow → **A** lush meadow · farm, Shelf gold
→ **B** dry grass · barrens → **G** · rock → **H** gravel · sand → **I** · snow →
**K** · seabed / lakes / rivers → 0. Patchy, dirt, mud and moss have no bake
class: they are paint-only, which is the point of the brush.

## The shader (`shaders/terrain_psx.gdshader`)

Per fragment: the four cell centres around the point are fetched
(`texelFetch` on paint, then base), each resolved to an id, and their tiles
blended **bilinearly** — so a painted edge is a 4 m gradient and a single cell
is a soft blob, never a hard square. Where the four ids agree (almost
everywhere) it is one array fetch. LOD is taken with `textureGrad` so the
divergent branches cannot pick a wrong mip at a tile edge.

The tile replaces the tint *before* the slope-rock / beach / snow overlays, so
cliffs still turn to rock over a painted meadow (`tile_rock` dials it). The
value-posterize and the 0.5 m texel-cell jitter are the tint's pixel language;
textured fragments skip the posterize and get a quarter of the jitter — the
sheet already carries its own palette per row.

Uniforms, all set by `GroundPaint._bind()`: `ground_tiles` (array),
`ground_base`, `ground_paint`, `ground_origin` (x0, z0), `ground_step`,
`ground_cells`, `ground_layers` (0 = feature off, the file's default),
`ground_row`, `tile_m` (metres per repeat, default 2.0).

## The brush (god mode → **Ground**)

- **Palette** — the 11 x 11 grid, rows numbered, columns lettered. Click a tile.
  Hover reads its name; the green line under the grid says what the brush holds
  and how many cells are painted.
- **World style** — a dropdown. Every *unpainted* dry cell re-dresses at once;
  "bake tint only" turns the base layer off (painted cells stay).
- **Texture scale** — metres of ground per repeat (0.5–12, default 2).
- **Brush** — Paint / Erase, radius 2–160 m. **Hold LEFT MOUSE and drag** to
  stroke; a dab lands every quarter-radius of travel, so holding still on one
  spot is one write. The ring on the ground is the brush (red = erase). The aim
  is the panel's usual: cursor in CURSOR mode, screen centre in LOOK mode
  (`F`). Over the panel the brush lifts.
- **Whole world** — *Fill every dry cell with this tile* and *Clear all paint*
  are two-click confirms (the button asks "Really?" first).
- The status line's `aim` readout shows the tile under the crosshair
  (`ground: 7-B Realistic-pixeled · Dry grass / Shelf`).

Saving: the paint file is written **2.5 s after the last stroke**, on the
panel's SAVE / Ctrl+S, when the editor closes, and on quit. Painting uploads the
paint texture at most every 80 ms (`UPLOAD_EVERY`), so a stroke never stalls
the frame.

`GroundPaint.inst.paint_disc(pos, radius_m, id)` / `fill_all(id)` /
`clear_all()` / `set_style_row(r)` / `set_tile_m(m)` are the whole API, so a
generator or a `game_eval` can paint too.

## Files

| | |
|---|---|
| `scripts/GroundPaint.gd` | the layer: atlas → array, the two maps, the brush, save/load. Names no other class; `Overworld._build_ground_paint()` hands it the shared ground material and the grid |
| `shaders/terrain_psx.gdshader` | the ground path described above |
| `scripts/GodEditor.gd` | the **Ground** tool: `_page_ground`, `_ground_click`, `_ground_dab`, the brush ring |
| `tools/groundsheet.py` | the generator: `out/ground_sheet.png` (the labelled contact sheet), `out/tiles/*.png`, `out/tiles.zip`. Assemble the 11 x 11 tiles into the atlas in row/column order and save the PNG bytes as `assets/terrain/ground_atlas.dat` |
| `tools/groundclass.py` | `maine_color.png` → `assets/terrain/maine_ground.dat`. Re-run after every `mainegen.py` bake |
| `tools/patch_ground.py` | the idempotent Player.gd wiring (the map over god mode, `map_eye`) |
| `tests/GroundPaintTests.gd` | 90 assertions, headless: ids, the brush geometry (a 10 m brush is 21 cells), erase, clamp, fill only dry cells, save/load round trip, the shipped base map's shape and legal values |
| `tests/GroundShaderCheck.gd` | compiles the shader on a live GL renderer with the textures bound and saves a frame — `xvfb-run -a godot --rendering-driver opengl3 --path . --script res://tests/GroundShaderCheck.gd` |

## Traps met on the way

- **Never let the id maps through the importer.** A `.png` under `res://` is
  imported; "Lossless" today can be "VRAM compressed" after one detect-3D pass,
  and either way `get_image()` hands back a re-formatted image. PNG bytes under
  `.dat`, read with `load_png_from_buffer`, is the only path that is byte-exact
  in the editor *and* in an export.
- `Image.set_pixel` on `FORMAT_L8` stores the colour's **value** (max channel),
  not `.r` — writing `Color(id/255, 0, 0)` is fine, writing a grey would be too,
  but a saturated blue would land as its blue channel. `get_pixel().r` reads it.
- A GDScript loop over the 4.9 M-cell map is a full second. `PackedByteArray.count(0)`
  is native and instant — the painted-cell count uses it. `fill_all` still
  loops (it has to write per cell) and is a user-triggered, once-in-a-while op.
- Sampling a `Texture2DArray` inside divergent `if`s is undefined for implicit
  LOD; `textureGrad` with derivatives taken *outside* the branch is not.
- Cells are **centred** on the grid, like `Overworld.sample_color` — the brush
  rounds, the shader floors the centre-relative coordinate. Mixing those two
  conventions shifts everything half a cell.
