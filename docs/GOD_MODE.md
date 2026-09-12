# God mode — the map editor (2026-09-02)

Press **F1** in game. You come **out of your body**, Minecraft-spectator style:
a free camera lifts off at exactly the view you had, and your character stays
standing where you left them. F1 again drops you back into their head, wherever
the camera has wandered to.

Everything stays live while you are out: the sun moves, the weather rolls, the
wildlife wanders. You are editing the running world, not a separate scene. But
nothing in it can see you — see **Nothing can touch you** below.

---

## Spectator

The camera has no body. Nothing to collide with, nothing to fall off.

| | |
|---|---|
| **F1** | out of your body / back into it |
| **WASD** | fly along the look |
| **Space / Ctrl** | up / down (world up, so looking at your feet still climbs) |
| **Shift** | ×3.2 boost |
| **scroll wheel up** | faster (×1.22 a click, up to ×24) |
| **scroll wheel down** | slower, back toward ×1.00 — which is the ordinary walk, and it snaps there |
| **F** | flip the mouse: **CURSOR** ⇄ **LOOK** |
| **hold right mouse** | look, in CURSOR mode |
| **Shift+B** | bring your body here |
| **M** | the map, OVER the editor — click to travel (camera and body both), M / Esc back to the editor |

The panel header reads `SPECTATOR ×1.00 · mouse CURSOR · body 412 m`, so you
always know how far you have drifted from the character you will snap back to.
Two buttons sit under it: **Return to body (F1)** and **Bring body here**, which
teleports the character to the ground under the camera.

### F — the mouse

Two modes, and F flips between them. The panel header says which one you are in.

- **CURSOR** (the default when the panel opens) — the pointer belongs to the
  panel. You click buttons, drag sliders, type notes. To look around, hold
  **right mouse** and drag.
- **LOOK** — the mouse is captured. Moving it turns your head exactly like
  ordinary play, and what you are aiming at is the middle of the screen. The
  panel is still on screen but you cannot click it until you press F again.

Flying and placing work in both. LOOK is for getting somewhere and dropping
things by eye; CURSOR is for driving the panel.

### Nothing can touch you

While the camera is out, the parked body is untouchable — belt **and** braces,
because one mechanism alone always misses something:

- **Physically**: its `collision_layer` goes to **0**. No sensor, ray, hitbox,
  swing or falling trunk can find it, because as far as the physics server is
  concerned there is nothing there.
- **By name**: `EditorMode.active` goes true, and `Enemy._get_player()` returns
  null. That is the single choke point every hunt, flee, charge and grudge in
  the game reads through — all nine mobs and all 73 wildlife species at once,
  because `Critter extends Enemy`. `CritterSwarm` finds you by group instead of
  through that, so the blackflies are gated separately.
- **The rest**: `take_damage`, `_start_knockdown` (every knockdown path funnels
  through it), `creature_grab`, `creature_press`, `pin_under` and the drowned's
  night-swim risk all refuse god mode outright.

The out-of-bounds net and the buried-in-rock net also stand down, so you can fly
off the map edge or straight through Katahdin.

### The body you go back to

The panel's **GOD** toggle decides what your *character* is when you return.
Off (the default): an ordinary mortal, and closing the editor is just resuming
play. On: they keep the invulnerability and gain Minecraft flight —
**double-tap Space** — and it survives closing the panel, so you can run and fly
around as the character with the editor shut.

Spectating is invulnerable either way; there is no body out there to hit.

Character flight parks the collision mask and restores it the instant it ends.

## Tools

**LEFT MOUSE always means "do the current tool where I'm aiming."** The aim ray
marches the heightfield analytically, so it lands on mid- and far-ring ground
that has no collider at all — you can point at a mountain five kilometres away.

### Select
Click a zone or a road to pick it up. Rename it, set its status
(idea → planned → building → done) and priority (low / normal / high / next),
resize a circle or a road width, read its notes, teleport to it, delete it.
With nothing selected the page lists everything in the plan.

### Zone
The areas: **city, town, village, hamlet, camp, docks, market · farm, orchard,
pasture, logging camp, quarry, mine, mill · forest, old growth, plains, meadow,
moor, marsh, beach, highland · keep, ruin, shrine, graveyard, dungeon, cave
mouth, boss arena, bandit camp · spawn, point of interest, keep clear, needs
work.**

- **Polygon** — click each corner, **Enter** closes it, **Backspace** takes one back.
- **Circle** — one click drops it; the radius slider is live and so is the ghost.

A zone draws as a coloured curtain with its name floating over the middle, drawn
without depth test so you can see the village boundary from the ridge above it.

### Path
Roads and trails: **king's road, road, cart track, trail, game trail, bridge,
ford, wall, palisade, fence line, canal.** Click along the route, **Enter**
finishes. The ribbon drapes onto the terrain at its real width, so you can see
the grade you just picked before you commit to it.

### Note
**This is the sectioning system.** Write a title and a body on the panel, pick a
tag (`todo` `idea` `question` `bug` `lore` `done`), then click the spot. The pin
stands there and files itself under whatever zone it lands in.

`design/WORLD_PLAN.md` is regenerated on every save, grouped by zone: open notes
first, then a section per zone with its coordinates, extent, area, nearest named
place and its notes as checkboxes. That is the file Claude reads next session.

### Trees
Five species (or `mixed`), five stages (or a random age). Brush radius 0 plants
one; anything above scatters a stand at the density slider, no two trunks closer
than 2 m. **Grow the tree I'm aiming at** ages it one stage.

A tree planted here is a real `TreeV2` — choppable, seasonal, and it survives a
new run.

### Build
**Pieces** (2 m grid): walls (plain, door, window, half, arch, corner post),
floors (plank, flagstone, stair, ramp), roofs (panel, gable, ridge, flat),
frame (post, beam, fence, gate, palisade, stone wall), props (well, fire pit,
crate, barrel, haystack, cart, market stall, signpost, bench, planter bed, dock,
cairn). Seven materials: timber, plaster, fieldstone, dark oak, thatch, slate,
cloth.

**Prefabs**: hut, cottage, longhouse, manor, barn, shed, ploughed field, animal
pen, watchtower, market row, well + square, dock, camp, shrine, ruined wall.

A prefab is **not** a special object — stamping a cottage places ~30 ordinary
pieces, and you can then delete its door and put a window there.

| | |
|---|---|
| **R / Shift+R** | rotate ±15° |
| **[ ]** | scale down / up |
| **PgUp / PgDn** | nudge height ±0.25 m |
| **H** | grid snap on/off |
| **P** | show/hide the plan overlay |
| **Ctrl+S** | save now |
| **Delete** | erase what I'm aiming at |

### Ground
**Paints the ground-sheet textures.** Pick a tile from the 11 x 11 palette
(rows are art styles, columns are ground types — `7-B` is the house style's dry
grass), hold LEFT MOUSE and drag across the terrain. Cells are the bake's own
4 m; edges blend. Erase puts a cell back to the **world style** — the dropdown
at the top of the page that re-dresses every unpainted cell in one row of the
sheet at once (default: 7, realistic-pixeled; "bake tint only" turns it off).
Radius 2–160 m; the ring on the ground is the brush (red = erase). Fill / Clear
the whole world are two-click confirms. Written to `design/ground_paint.dat` +
`design/ground.json` 2.5 s after you stop. Full notes: `docs/GROUND.md`.

### Erase
**Objects** removes a built piece or a tree you planted. **Plan marks** removes
the smallest zone under the cursor, and its notes with it.

---

## The map, from inside the editor

`M` used to close the editor (any other menu did), so "open the map in dev
mode" meant leaving dev mode. Now, while the panel is up, the map is an
**overlay**: `Player._toggle_menu("map")` sets `menu_open = "map"` and leaves
the editor visible and spectating underneath (`Player._map_over_god`). The
editor takes no input while the map is up (`GodEditor.map_over()`), the
spectator camera holds still (WASD is muted through `cam.typing`), and the
arrow on the map is the **camera**, not the parked body (`Player.map_eye()`).
Clicking travels **both**: `GodEditor.travel_to()` teleports the body (warming
the terrain first) and places the camera 14 m up and 22 m back, looking at the
spot, so F1 still returns you to your character where you are. `M`, `Esc`,
`F1` or travelling close just the map — `menu_open` goes back to `"god"` and
the cursor is yours again. `tools/patch_ground.py` is the Player.gd wiring.

## What it writes

| file | what |
|---|---|
| `design/world_plan.json` | the plan — zones, paths, notes. The truth. |
| `design/WORLD_PLAN.md` | the same thing as prose, grouped by zone. **Claude reads this.** |
| `design/build_placements.json` | the stuff — every piece and planted tree. |
| `design/ground_paint.dat` + `design/ground.json` | the ground — painted tile ids on the 4 m grid, and the world style. `docs/GROUND.md`. |

Written into `res://design/` when the game is run from the Godot editor (the only
way anyone is using god mode) and `user://design/` otherwise. `WorldPlan.dir()`
says which won.

Saves happen on every plan change, 2.5 s after a placement, when the panel
closes, and on Ctrl+S.

**None of this lives in a save game.** Built pieces and planted trees carry
`meta "built"`, `World.save_state` skips them, and `World.apply_state` calls
`get_tree().call_group("builder", "restore_all")` after a load. Start a new run
and the town is still there.

---

## Files

| | |
|---|---|
| `scripts/WorldPlan.gd` | the plan: records, geometry, persistence, the Markdown |
| `scripts/PlanViz.gd` | draws it — curtains, ribbons, pins, labels |
| `scripts/BuildKit.gd` | the catalog: 32 pieces, 15 prefabs, 7 materials, the cost table |
| `scripts/BuiltPiece.gd` | one placed piece; save / restore |
| `scripts/GodEditor.gd` | the panel, the tools, the aim, the ghost |
| `scripts/GroundPaint.gd` | the ground textures and the brush's data layer (`docs/GROUND.md`) |
| `scripts/EditorCam.gd` | the spectator eye — take-over, release, free flight |
| `scripts/EditorMode.gd` | one static flag, imported by Enemy and CritterSwarm |
| `tools/patch_god.py` | the re-runnable Player.gd / World.gd / Enemy.gd / CritterSwarm.gd wiring |
| `tests/GodEditorTests.gd` | 1,959 assertions — the data layer, no tree needed |
| `tests/GodEditorLive.gd` | 97 assertions — real nodes in a real tree, the F flip, the spectator camera, every prefab instantiated |

Run the suite:

```
godot --headless --path . --script res://tests/GodEditorTests.gd
godot --headless --path . --script res://tests/GodEditorLive.gd
```

It writes only into `user://plan_test/` — `WorldPlan._dir` is overridden before
anything runs, so a test can never scribble over `design/world_plan.json`.

---

## Fall damage is off

Per Lemon, 2026-09-02: gone. It is a real switch rather than deleted code —
**Settings → Fall Damage**, default **Off** — because the numbers were tuned
and a survival game may want them back one day.

Off means the whole thing: no health hit, no death by fall, and **no
hard-landing knockdown**. Leaving the knockdown in would read as "fall damage
is still on" even with the number at zero, so one early return in
`Player._apply_fall_damage` kills all three together. The camera dip and the
landing sound are not damage and stay.

God mode also refuses it independently, so it cannot come back to bite you
while you are flying around building.

Saved to the config as `game/fall_dmg`. Switches live, any time.

---

## The Stardew hook

`BuildKit.COST[piece]` already prices every piece in the item names the player's
inventory uses (`Plank`, `Log`, `Stone`, `Thatch`, `Stick`, `Cloth`). God mode
ignores it entirely.

A survival build system is this file's Build tab minus god mode, plus a pack
check and a spend: the catalog, the meshes, the ghost, the grid snapping and the
`{piece, pos, rot, mat}` record format all carry over unchanged. Zones are the
natural home for buildable land — a `farm` zone with status `done` is a plot,
and `WorldPlan.zone_at(x, z)` is most of a placement rule.

---

## Traps met on the way

- `StandardMaterial3D.specular` does not exist in Godot 4 (it is a 3.x remap and
  warns on every material). The property is `metallic_specular`.
- `global_position` on a node outside the tree returns zero and prints an error;
  `BuiltPiece.save_dict` falls back to `position`.
- A node's `_ready` has not necessarily run by the time the code that added it
  calls a method on it, so `PlanViz` builds its holder lazily rather than
  trusting the callback.
- **`tools/patch_god.py` must stay idempotent**, because two sessions now edit
  `Player.gd` and the only safe move is to re-run the patcher against the LIVE
  file and let the markers skip what is already there. Two ways that broke:
  a marker string that gets **line-wrapped** in the output never matches (keep
  markers on one line), and an unguarded `p += '''...'''` append duplicates its
  functions on the second pass. Both are fixed; there is a check for it —
  running the patcher twice must add zero hunks and leave all four files
  byte-identical.
- Mouse motion needed a second arbitration point. `Player._input` already hands
  keys and clicks to `GodEditor.eat_input()`, but motion arrives in
  `_unhandled_input`, so that now calls `GodEditor.take_motion()` first —
  without it, your character spins on the spot while you fly the camera.
- Setting a camera's rotation by accumulating `rotate()` calls drifts and rolls.
  `EditorCam` rebuilds its whole basis from yaw and pitch every look, so the
  horizon is level by construction (asserted).
- Headless has no window to capture a mouse into, so `Input.mouse_mode` keeps
  reporting `VISIBLE` however you set it — test the editor's own `mouse_look`
  state, not the engine's.
- Godot calls `_input` on deeper nodes first, but relying on that for
  arbitration is fragile. Instead `Player._input` hands every event to
  `GodEditor.eat_input()` first and honours its answer — one arbitration point,
  so the editor and the game can never both act on one click. Clicks over the
  panel are *consumed for the game* but never `set_input_as_handled`, so the GUI
  still receives them.
