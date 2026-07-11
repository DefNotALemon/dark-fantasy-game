# Trees & Seed Lifecycle — Status + Resume Prompt

> Read this first when resuming tree/environment work. Last updated: 2026-07-08 (after full reset).

## RESET (2026-07-08)
The first full pass (20 GLBs, 4 species + complete Godot integration with TreeLife/Seed system) was **fully reverted at user's request** — scripts restored to placeholder cone trees, all tree assets/scripts deleted. Redoing species one at a time with user review between each.

## CURRENT STATE
- **Blender**: `trees_oak` collection has the take-2 oak line — 5 stages (sapling → young → mature → ancient → withered) spaced 9m along X. Saved to `assets/source/trees.blend`. Preview: `tools/previews/oak_line.png`. 72–832 tris.
- Take-2 oak improvements over v1: root flare, progressive trunk twist, dip-then-rise curling branches with twigs, forked ancient trunk + bare dead limb + frost lichen, withered claws upward with ember leaf quads, golden-angle branch spread.
- **Godot**: untouched — original procedural cone trees in World.gd. No GLB exports yet, no gameplay scripts.
- **Generator**: `tools/treegen.py` — oak-only right now (`build_oak_line()`, `preview(path)`). Same palette constants as before (slate/indigo, ember, frost).

## WORKFLOW (Blender MCP connector)
User's Blender (5.1.2) open + addon connected on port 9876. Iterate: edit `tools/treegen.py` → `importlib.reload(treegen); treegen.build_oak_line()` → `treegen.preview('<abs>/tools/previews/oak_line.png')` → view PNG. Preview rig (PreviewCam/Sun/Ground) + hidden default Cube/Light are render-only helpers.

## NEXT
1. **User reviews the oak line** → iterate on feedback until approved.
2. Then add species one at a time (pine → birch → willow expected), same review loop.
3. Only after models are approved: export GLBs (origin at base, Y-up) and redo Godot integration. Previous design to reuse: TreeLife stage-growth scenes; seed drops from mature/ancient; seeds eatable (H) or plantable (G); wild germination with ~35% fail-to-ash; scatter in World.gd. (All that code was deleted in the reset — rewrite when asked, don't assume it's wanted.)

## Design notes (approved earlier, unchanged)
Seed system: trees drop seeds → pick up and eat, or leave/plant to grow new trees with a fail chance (ash crumble). 5 life stages per species. Low poly, faceted, gritty-realism, moody-but-never-drab.
