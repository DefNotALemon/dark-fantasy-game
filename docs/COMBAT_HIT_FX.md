# Combat hit effects — spec & implementation

Status: shipped 2026-08-22 in `dark-fantasy-game`. Files: `scripts/HitFX.gd`
(new), `scripts/Player.gd`, `scripts/Arrow.gd`, `scripts/TreeV2.gd`.

## The rule

Nothing gets hit for free. Every blow that lands anywhere in the game routes
through one place, resolves an actual point of contact, works out *what* was
hit, and throws the right thing out of it.

## What comes out of what

| You hit | You get |
|---|---|
| Bare flesh (goblin, orc, ogre, kobold, boar) | Blood — a fast spray along the swing plus heavier gouts that fall out of the wound |
| Armour (`armored`/`construct` family, or `armored = true`) | Sparks: white-hot flecks in a wide fan, a few ricocheting back past your ear, and a one-beat light flash |
| The undead (`undead`, skeleton) | No blood left in them — pale bone shards and grave dust |
| Timber, with an axe or a sword | Chips and sawdust out of the **exact spot the edge went in**, tinted to the species, plus real tumbling splinters (`RockDebris`) |
| Anything, with elemental steel | The blade's own signature on top — see below |
| **You** | Same rules. Blood through the gaps, sparks off your plate, sparks alone when a shield or plate turns the blow completely |

Kind resolution lives in `HitFX.kind_of(node)` so the player, arrows and any
future damage source all agree.

## The blade's own effect

Fed straight from `Materials.blade_fx(material_id)` — no second table to keep
in sync:

- **meteoric / dragonsteel** — embers pushed into the wound, climbing back out, orange flash
- **voidsteel** — no sparks; slow purple squares that sink, violet flash
- **mithril / adamant** — no weather, just their own colour of light off the edge
- **iron, steel, bronze, silver, cold iron** — nothing. An honest metal doesn't do anything to the air and shouldn't pretend to.

The axe is plain iron, so it passes no material and gets no element burst. When
elemental steel is added to axes, pass the id to `_creature_impact` and it
works with no other change.

## Where the hit lands

`_impact_on(enemy, reach)` resolves the contact point in three falling steps:

1. Whatever the **crosshair ray** actually struck on that creature
2. A surface point on the line from your eye to its chest
3. A guess just off its chest, facing you

`_wood_strike_point(wood, reach)` does the same for timber, falling back to the
chopper's-side notch height when the ray misses (trunk colliders are often
narrower than the visible bark). The strike point is now also what gets passed
to `TreeV2.chop_hit` as the aim, so **the limb that comes off is the one under
the crosshair** rather than one 2.6 m down the sightline.

## The Blood setting

Settings → **Blood: Off / On**, saved to the config under `game/blood`,
defaults On. Off swaps the red for a colourless puff of impact dust — every hit
still lands and still reads. Sparks, bone dust, woodchips and elemental effects
are untouched by it. `HitFX.blood_enabled` is a static read at spawn time, so
the switch takes effect on the very next hit.

## Particle language

Same as the rest of the game: small **emissive cubes**, no textures. Every
burst is one-shot, fully explosive, world-space, and self-freeing — build it,
drop it in the world, forget it. Nothing ticks, nothing needs cleaning up.

## The axe swing bug

**The head was counter-rotating against its own sweep.** On the old forehand
the hand travelled right-to-left (`+0.18 → -0.20` on x) while the axe *head*
yawed left-to-right (`+58° → -56°`, which points the head `-0.66 → +0.91`).
Head and hand moved in opposite directions, so the edge trailed backwards
through the arc — which is exactly what "swinging backward" looks like. The
pitch also barely moved (8° → 16°), so the head never came *down* through the
cut, and damage landed at drive ≈ 0.98, the very end of the sweep rather than
the middle of it.

Rewritten as `AXE_KEYS`: three keyposes per side (chamber / impact / follow-
through) run through the same `_pose_keys` curve the sword uses. On the
forehand, yaw now runs −54 → −6 → +46 while the hand runs +0.20 → +0.02 →
−0.20 — **the same trip**. Pitch drops 40 → −12 → −30 so the head comes down
through the cut, and z drives to −0.30 at impact so the stroke travels *away*
from the camera. Backhand mirrors it. `AXE_HIT_AT` (0.52) now coincides with
the impact keypose, so damage lands mid-arc where the edge is actually passing
through.

Third person had the same problem: the cleave's drive ended at arm rotation
`x = −0.70`, which points the fist *behind* the body. Now ends at `+0.35` —
down and forward. Both axe strokes are mirrored cleaves so the body alternates
in step with the viewmodel, and the lens roll was mirrored to follow the arc.

### Verified

Headless Godot 4.7 check: all four scripts parse clean, the project boots with
no errors from this code, and a math harness confirms head-and-hand agreement
across both strokes, forward drive at impact, correct kind resolution over the
whole bestiary, and every effect flavour building without error.

## Also fixed along the way

`_do_axe_hit` only ever scanned the `trees` group, so downed trunks
(`fallen_trunks`) and stumps (`tree_stumps`) were unreachable — the branch in
`_chop_tree` that handles them was dead code. `_nearest_wood` now scans
`trees`, `choppable`, `fallen_trunks` and `tree_stumps`, so **bucking a felled
trunk into logs and clearing a stump both work**, per the trees-v2 spec.

## Notes / open ends

- A sword in a tree throws chips and shivers the trunk but does **no** felling
  progress, and nudges you toward the axe (rate-limited to once per 8 s).
- Arrows landing in timber throw a small chip burst; arrows in creatures use
  the same three-kind resolution at 0.75 power.
- No decals — blood doesn't stain the ground yet. If that's wanted, it wants a
  pooled decal system rather than more particles.
