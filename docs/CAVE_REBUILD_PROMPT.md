# Cave Rebuild — Working Prompt (v2)

> A shared brief for a **complete, from-scratch rebuild of the cave system** in The Withering.
> We edit this together until it's right, *then* I build from it, step by step.
> **Status:** all previous cave upgrades were reverted to the 2026-07-10 baseline. This document
> is the plan for the next attempt — a clean start, not another patch.

---

## 1. The goal, in one line

Caves are assembled from a **kit of pre-verified, guaranteed-walkable pieces** that snap together
into varied **hub-and-spoke** layouts. A cave is *always* fully connected and walkable from the
entrance to the deepest room — **no invisible walls, no gaps, no pinch points, no ramp that dies
3/4 of the way in.** Tight tunnels open into big caverns. The entrance is a hole that **caves in
from above**, rocks tumbling down to settle nearly flush with the ground.

## 2. Locked decisions (already made — build to these)

- **Construction = modular kit.** Authored, individually-verified pieces joined at sockets. Not
  a fresh spline-lofted mesh per cave.
- **Feel = mix.** Tight, tense corridors that open into large domed caverns. Contrast and pacing.
- **Layout = hub-and-spoke, with variety.** Many kinds of hubs, many kinds of spokes, many kinds
  of intersections — the network should never feel like one room copy-pasted.
- **Entrance = a cave-in.** The ground opens, rocks fall from the rim and land almost flush,
  forming the step down into the entrance ramp; dust kicks up. (Full spec in §5.)
- **Keep the gameplay systems** (combat packs, mining veins, crystal/fog atmosphere, dweller
  spawns) — they hook onto the kit via markers (§7), they are not what we're rebuilding.

## 3. Why the old approach kept breaking (design these out — do NOT reintroduce)

Every one of these was a real, repeated bug. The kit must make each **structurally impossible**,
not "fixed with a tuned constant." If a piece is verified once, these can't come back.

1. **Lofted spline tubes fold into invisible walls.** Sweeping a tube along a Catmull-Rom curve
   means any bend tighter than the tube is wide folds the mesh through itself → an invisible wall.
   A winding *entry* put a ~48° kink at ~75% of the descent and froze the player 3/4 in.
   → *Kit fix:* corridors are straight or use **pre-authored, verified bends only**. No runtime
   curve lofting whose radius can go below the tube width.
2. **Doorways narrower than the tunnel.** A single skipped wall facet left a ~2.5m hole, but the
   tunnel was 3m — so the tube crammed through the opening and wedged the capsule at *every room*.
   → *Kit fix:* a doorway **is** a socket profile; the corridor that attaches has the *same*
   profile. Opening width can never disagree with corridor width.
3. **Tube end-flares ballooned at the doorway.** A cosmetic "flare into the room" widened the tube
   to ~4.2m exactly where it threaded the narrow opening — maximum jam.
   → *Kit fix:* no width changes at a seam. Ever. Pieces meet at a fixed profile.
4. **Descending ramp meets flat floor → a lip.** The sloped floor arriving into a flat room left a
   step that caught the capsule.
   → *Kit fix:* height changes live **only** inside dedicated ramp/stair pieces; every socket is
   flat, and two joined sockets share the exact floor height.
5. **Raised rims & rubble steps at the mouth wedge you.** A raised lip + steps at the entrance
   pinned the capsule at the threshold.
   → *Kit fix:* the entrance ramp's top socket is flush with the grass; rubble is cosmetic and
   never taller than the auto step-up.
6. **Wonky, tilted wall panels lean into the walk lane.** Randomly rotated wall segments intruded
   into doorways and formed wedges.
   → *Kit fix:* cosmetic wall relief is baked into a piece and verified once; it can never cross
   the walk lane because the piece was checked before it shipped.

## 4. Core mechanism: socket-based assembly (the reliability contract)

**A piece** is a self-contained chunk of cave — a room, a corridor, an intersection, the entrance.
Built/authored **once**, verified walkable **once**, reused forever. Each piece exposes **sockets**:
labelled connection points, each with a **grid position**, a **facing**, a **profile** (opening
shape+size, e.g. `CORR_3` = 3m-wide × 3.2m-tall arch, flat floor), and a **floor height**.

**The connection contract — the single rule that replaces all the fragile math:**
two pieces may join only when a socket on each has the **same profile**, **opposite facing**, and
the **same floor height**. Matching profiles ⇒ the opening equals the corridor. Equal floor heights
⇒ no lip. Fixed geometry ⇒ no fold, no balloon, no wedge. Walkability is guaranteed *by construction*.

**Assembly** grows a graph of pieces (detail in §6): place the entrance, then repeatedly attach a
compatible random piece to an open socket, rejecting placements that overlap an existing piece or
leave the world slab; force a path to the boss; add a couple of loops; cap every leftover socket.
Because every piece attaches *through* a socket, everything reachable is reachable on foot.

## 5. The entrance — "the earth caves in"

The signature moment, per the locked decision:

> a hole opens up into the ground, rocks fall from the top and create the step between the ground
> and the entrance ramp/tunnel, but the rocks land almost flush with the ground, with dust.

Sequence and guarantees:

1. **The ground opens.** A patch of the ground slab cracks and drops away, carving the hole (the
   world starts solid and opens up — no pre-existing pit).
2. **Rocks fall in.** Chunks tumble from the rim inward and down, tweening as they fall, with a
   **dust burst** (`GPUParticles3D`) as the hole forms and as rocks land.
3. **They settle near-flush.** Fallen rocks come to rest around the lip at **~ground level**,
   reading as the natural step from grass down onto the ramp — and never taller than the auto
   step-up height, so they're cosmetic, never a wedge. (This is the whole point of "almost flush.")
4. **Down the ramp.** Below the lip a dedicated **ramp piece** descends at a fixed, verified angle
   (~26°) to the first hub. Top socket flush with the grass; bottom socket flat, matching hub 0.
   Walk straight in and straight back out, always.

The entrance is just another kit piece obeying the socket contract, so it can't drift out of sync
with the rest. The cave-in effect is cosmetic dressing on top of the verified ramp underneath.

**Ties into step 9 (dynamic caves):** a cave-in is a natural trigger for one opening near the
player (quake shake still scales with distance), and the same effect can later fire when shifting
caves collapse and reopen.

## 6. The kit — pieces & the assembler

**Hubs (tunnels open into these — the big moments):** small round chamber · big domed cavern ·
pillared hall (columns break sightlines) · vertical chamber with ledges/ramps · chasm room (skirt
a pit / cross a bridge) · **boss arena** (deepest, largest).

**Spokes (connective tissue — tighter, tenser):** straight corridor · pre-authored gentle bend ·
descending ramp segment (the only place floor height changes) · narrow crawl (torch matters) ·
wide processional (approach to a hub).

**Intersections (where hub-and-spoke gets its variety):** L-bend · T-junction · 4-way crossroads ·
Y-fork · stair/landing (level change + a turn).

**Special:** entrance cave-in + ramp · dead-end alcove (loot / vein / crystal shrine) · wall plug
(caps an unused socket).

**The assembler (graph growth with guarantees):**
1. Place the **entrance**; its inner socket is the first open socket.
2. While the cave isn't big enough: pick an open socket, pick a compatible piece (weighted random,
   with rotation), and attach it. **Reject** if its bounding box overlaps a placed piece or leaves
   the ±slab bounds — try another piece/rotation, or cap the socket.
3. **Guarantee a path to a boss arena** (grow the main line first, then branch).
4. Add **1–2 loops** (join two nearby open sockets) so routes circle back instead of dead-ending.
5. Sprinkle **dead-end alcoves** for loot/veins.
6. **Cap every remaining open socket** with a wall plug — no holes to the void.
7. Smoke-test many seeds: assert no overlaps, no stranded pieces, entrance→boss reachable.

## 7. Gameplay hooks (attach to pieces, not to geometry)

Kept from today's game, rehung on **markers** baked into pieces:
- **Combat packs** — hubs carry pack-spawn markers; size/roster scales with depth (kobolds near
  the mouth → orcs/ogres deep → dark-knight champion in the boss arena).
- **Mining veins** — some alcoves/hubs carry vein markers (silver common, meteoric deep).
- **Crystal light & fog atmosphere** — light markers per piece; underground fog + location titles stay.

## 8. Non-negotiable invariants (the walkability contract)

1. Every piece is flat-floored, or a fixed safe-angle ramp/stair — **verified walkable alone.**
2. Pieces join **only** at matching sockets (same profile, opposite facing, equal floor height) ⇒
   seams are always full-width and level: no lip, no gap, no fold, no balloon.
3. Entrance top socket **flush with the grass**; ramp lands flat on hub 0's floor.
4. Entrance rubble is **cosmetic and ≤ step-up height** in the walk lane.
5. Every open socket is **capped** — no holes to the void.
6. A cave is connected **by construction**; still smoke-test seeds to confirm the assembler never
   overlaps or strands a piece, and entrance→boss is always reachable.
7. All surfaces use the **4 shared materials** so the future art pass swaps textures in one place.

## 9. Build order (how we tackle it together)

1. **Socket framework** — piece base + socket definition + match/attach/overlap logic. Prove two
   hard-coded pieces snap and are walkable.
2. **Entrance piece** — cave-in (hole carve + falling rocks + dust) + flush ramp into one hub.
   Walk in and out. *(Nail this first — it's the recurring pain.)*
3. **Core kit** — straight corridor, pre-authored bend, ramp, L/T/4-way, small chamber, big cavern.
   Enough to assemble a real cave.
4. **Assembler** — graph growth, overlap rejection, loops, boss-path guarantee, socket capping.
   Seed smoke-test.
5. **Variety pass** — pillared/vertical/chasm hubs, crawl/processional spokes, Y-fork/stairs, alcoves.
6. **Rehang gameplay** — pack/vein/crystal markers, fog + titles.
7. **Verify** — many-seed walkability sim + in-engine playtest; write the new invariants into CONTEXT.md.

## 10. Open decisions to settle (the "work on it together" part)

- **DECIDE A — first-playable piece set:** I'd ship step-3's set + entrance + boss arena first
  (feels complete), then the §6 variety pieces. Agree, or want a different starter set?
- **DECIDE B — cave size:** short delve (4–6 rooms) or sprawling complex (10–15)?
- **DECIDE C — grid vs free placement:** snap pieces to a coarse grid (simplest overlap checks,
  slightly blockier) or free-align at sockets (more organic, harder overlap math)? I lean grid.
- **DECIDE D — authoring style:** build pieces in **code** (matches "world built in code," no scene
  sprawl) or as **`.tscn` scenes** (easier to eyeball)? I lean code.
- **DECIDE E — how craggy:** how much cosmetic rock relief on walls/arches before it reads noisy?

---

*Next: scribble on this / tell me what to change, and lock the DECIDE points. When it reads right,
I start at Build-order step 1 (the socket framework) and we go piece by piece.*
