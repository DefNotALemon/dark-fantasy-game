# The map (M) — scripts/MapPanel.gd

Added 2026-09-02. `M` opens the whole state; `K` now opens the mob spawn menu
that used to live on `M`.

## What it draws

`assets/terrain/maine_preview.png` stretched into a 520 x 780 frame (the bake's
own 2:3, 7.2 x 10.8 km), with everything `maine_meta.json` knows laid over it:

| layer | drawn as | when |
|---|---|---|
| regions (18) | faint centred caption | zoom < 3 |
| places (50) | dot + name, dot and text sized by `rank` | rank >= 1 always; rank 0 from zoom 1.8 |
| peaks (17) | orange caret, `name  NNN m` | caret always; label from zoom 1.8 |
| lakes (30) | pale blue name | from zoom 1.8 |
| you | cyan arrow, rotated to your facing | always (edge dot when panned off) |

The readout under the frame follows the cursor: nearest place (or region),
world x/z, and either the ground height or the water depth.

## Controls

- **wheel** — zoom 1x..10x, anchored on the cursor
- **right-drag** — pan; the image can never be dragged off its own frame
- **left click** — FAST TRAVEL, **god mode only**. Out of god the click is
  refused with a line in the readout. `F1` turns god on.
- **M / Esc** — close
- **in god mode (F1)** — `M` opens the map OVER the editor and closes only the
  map; the arrow is the spectator camera; a click travels camera and body
  both (`GodEditor.travel_to`). Added 2026-09-03 — see `docs/GOD_MODE.md`,
  "The map, from inside the editor".

## Coordinates

The bake's row 0 is north, so the mapping is a straight linear scale with no
flip: `u = (wx - x0) / (nx * step)`, `v = (wz - z0) / (nz * step)`, and the view
point is `origin + uv * (view_size * zoom)`. `_to_view` / `_to_world` are exact
inverses; everything else (labels, the arrow, the click, the readout) goes
through them, so there is one place to get it wrong.

Because the scale is uniform, the arrow's screen angle is just
`atan2(forward.z, forward.x)` off the body's `-Z`.

## Travel

`_travel_to` refuses out of bounds, then puts you at `max(ground, water) + 2 m`
and calls `Player.god_teleport`, which warms the near ring FIRST (`Overworld.warm`)
so you land on a tile that exists instead of falling through one that has not
arrived. It then closes the map, because you want to be looking at the world.

## Wiring

`Player._build_hud` does `map_panel = MapPanelScript.new()` and sets
`map_panel.player = self`. It is loaded **by path**, not by `class_name`:
MapPanel is the one script that talks back to Player, and a name-level cycle
between the two is the kind of thing that becomes a parse error on a cold open.

One related change in `Player._input`: god mode's wheel speed-dial is now gated
on `menu_open == ""`, or it fights the map's zoom.

## Verified live (2026-09-02, Godot 4.7.2 on the MacBook)

Run the game, open the map, then `editor_manage(game_eval)`:

- world -> view -> world round trip over 3 zooms x 4 points (map corners
  included): worst error **0.00024 m**
- map corners land exactly on the frame corners at zoom 1
- zoom-about-cursor anchor drift **0.0005 m**
- pan clamp keeps the image covering the frame in both directions
- `centre_on` error **0 px**
- click without god: moved **0 m**, readout showed the refusal
- click with god: landed with **0 m** x/z error at ground + 2.0 m

And by hand in the running game: `M` opens it, `K` opens the spawn menu, the
wheel zooms and reveals the small-town / lake / peak labels, and a click on
Katahdin put the player on the snow line.
