# Game Modes — Peaceful / Normal / Hardcore

Shipped 2026-08-29. Core file: `scripts/GameMode.gd`. Suite:
`tests/GameModeTests.gd`. Settings row: **World** (Esc), first row.
Updated same day: the cave rule + surface amnesty (see below), and the
suite finally landed in the repo (it had only existed as a project doc).

## 1. What each mode is

### PEACEFUL

**Nothing picks the fight with you.** The bear still rears up, huffs, holds
its ground; the moose still stamps; the boar still turns and snorts. None of
them ever *commit* — unless you swing first, and then they are a real animal
again until the next time the switch is thrown.

**The caves stay caves — but ONLY the caves (2026-08-29).** What lives
underground still hunts you, because a cave that cannot hurt you is just a
room. A monster standing in daylight is off the clock: `may_engage` asks
`mob_in_cave()`, which duck-types through the `"cave_regions"` group to
`CaveRegion.contains_point()` (inside the field's footprint AND below the
surface skin, y < -2).

**THE SURFACE AMNESTY (2026-08-29).** The moment the switch lands,
`GameMode.settle()` pardons everything outside a cave ON THE SPOT — provoked
animals and surfaced monsters alike stand down instantly, grudges
(`provoked`) wiped. Only the caves keep their grudges. Hit something again
afterwards and it is a real animal again: the amnesty is the switch itself,
not a new rule of engagement.

| | Peaceful | Normal | Hardcore |
|---|---|---|---|
| pack size underground | half (never below 1) | as authored | as authored |
| notice radius, cave dwellers | ×0.55 | ×1.0 | ×1.0 |
| any blow from something alive | ×0.40 | ×1.0 | ×1.20 |
| wound regen rate | ×3.0 | ×1.0 | ×0.60 |
| regen delay after combat | ×0.35 (~1 s) | ×1.0 (3 s) | ×1.60 |
| blackfly bites | ×0.0 (still swarm) | ×1.0 | ×1.0 |

**Explicitly untouched, in every mode:** falls, fire, drowning, a felled
trunk landing on your back, the fog past the dead coast. Peaceful is a rule
about things with teeth, not about physics.

### NORMAL
The game as built. Every multiplier is `1.0`, every gate open.

### HARDCORE
Normal, meaner, and you get **one**. `Player._die` calls `SaveGame.seal()`
(tombstone at `user://save01.dead`); Load refuses that slot forever and Save
has nothing left to write. `Settings → New Run` breaks the seal and restores
the newborn snapshot captured at the end of `Player._ready`. The world is
not reset — a new life in an old land.

## 2. Architecture

`GameMode` is one static class — no node, no autoload, nothing ticks. Every
system asks it a question at the moment it matters, so the switch lands on
the very next swing. **The one hard rule:** GameMode never names `Enemy`,
`Critter`, `Player` or `CaveRegion` — they name *it*; naming back would make
the global class table cyclic. Everything is duck-typed (`"monster" in who`,
group `"cave_regions"` + `contains_point`), which also gives the
environmental carve-out for free: a fall reaches `take_damage` with no
attacker, and `is_creature(null)` is false.

### Hook list

| File | Hook |
|---|---|
| `Enemy.gd` | `monster`, `provoked`, wake gate `may_engage()` + `aggro_mult()`, `take_damage` sets provoked, `peace_settle()` |
| `Critter.gd` | all four routes to a charge gated; `peace_settle()` also aborts a contact special mid-move |
| `Player.gd` | `take_damage` / `horse_kick` × `creature_damage_mult`, regen mults, `_die`, Save/Load/New Run, World row |
| `CaveRegion.gd` | `_spawn_pack` × `pack_count()`; `contains_point()` answers `mob_in_cave` |
| `CritterSwarm.gd` | `swarm_damage_mult()` |
| `SaveGame.gd` | `seal` / `unseal` / `is_sealed` + Load refusal |

### Monster or animal
`monster = true` in exactly six `_init`s: Goblin, Kobold, Orc, Ogre,
Skeleton, DarkKnight. Everything else — boars, horses, all 73 dex entries —
is an animal.

### What counts as "you started it"
`Enemy.take_damage` sets `provoked` when the attacker is the player **or
when there is no attacker at all** (the sword, axe and pick all call bare —
a bare call is the player's signature). Creature-on-creature always passes
`self`, so infighting never provokes anything against you.

### Tuning
Nine constants at the top of `GameMode.gd` are the entire tuning surface.

## 3. Traps (kept from the build)

- The switch has to land on the fight you are already in — `settle()` walks
  the `enemies` group on every mode change.
- A bluffer has FOUR routes to a charge (two `_do_bluffer` escalations,
  `_spook`, FLEE→CHARGE) — all four are gated.
- Godot MCP: a running game makes every script write lie — stop the game
  first; the bare `error code 43` with `diagnostics_detail: "fallback"` is
  noise, only `log_capture` diagnostics are real.
