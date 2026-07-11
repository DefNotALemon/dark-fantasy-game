# Weapon Materials — List & Mechanics

> Design doc for roadmap Step 5 ("Material → element effects") + the DESIGN.md
> silver/steel matchup system. Last updated: 2026-07-09.
>
> STATUS: approved + first implementation pass DONE (2026-07-09):
> `scripts/Materials.gd` holds this table; all 10 material swords exist and are
> grabbable from the Armory (dev) column on the I inventory menu; matchup ×
> element multipliers apply to sword hits vs enemy `families` tags; elemental
> blades glow with an aura shell; ONLY the v1 slice drops from mobs (rare,
> tier-weighted). SECOND PASS (2026-07-09): sourcing + discovery are live —
> Iron Pickaxe (weapon 3) mines OreVein.gd rocks seeded through the caves
> (silver seams in ~half the rooms, meteoric usually in the deepest); the first
> ore of a new metal auto-forges its sword, spares stack for smithing later.
> The Tab-4 BESTIARY hides each creature's page until first kill and each
> material matchup until you land that metal on that creature ("prove it").
> Still pending: element scaling with evolution (needs step 5's evolution bar),
> durability/dulling, smithing, sharpening rocks.

## How the system works

Every weapon is made of **one material**. The material determines five things:

1. **Matchup multiplier** — damage scaled by the target's creature family.
   Proposed: **strong ×1.35 · neutral ×1.0 · weak ×0.8**. Shown in-game by hit
   feedback (bright crack vs dull thud), not menus — you learn it like silver-vs-werewolf folklore.
2. **Element (or none)** — commons have no element; rarer metals carry one, permanently.
   The element is a **constant aura on the blade** (flames, rime, arcs) whose intensity
   scales with **that individual sword's evolution level** — faint shimmer at evo 0,
   fully wreathed at max. Damage is **situational, not flat**: vs the right target it adds
   **+5% → +25% bonus damage** (scaling with evolution); vs resistant/wrong targets ~0.
   No casting ever — the weapon carries it.
3. **Weight modifier** — mithril-like is light (keeps a build non-heavy), adamant-like is
   the heaviest (pushes builds heavy). Feeds the existing carry-weight/build system.
4. **Durability profile** — how fast the edge dulls and durability drains per swing
   (iron dulls fast ×1.5 · steel ×1.0 · meteoric holds an edge ×0.5 · endgame metals
   are durable AND sharp).
5. **Value/rarity** — where it's found (biome gradient) and what drops it.

**Stacking:** sharpening rocks rub a temporary bonus onto the edge (+sharpness or
+vs-monster-type) that wears off over ~60 landed hits — it **stacks** with material
(silver + anti-undead rock = shredder). Crystals can add temporary elemental statuses
on top. **Blunt weapons** ignore edge material and care about **density/weight**
(strong vs skeletons, golems) — their "material" bonus reads from mass instead.

## Creature families (matchup targets)

| Family | Current mobs | Future |
|---|---|---|
| **Beasts** | Boar | Wargs, gnolls, spiders, rats |
| **Humanoids** | Kobold, Goblin, Orc, Ogre | Bandits, hobgoblins, trolls |
| **Undead** | Skeleton | Zombies, wraiths, wights, liches |
| **Cursed** | Dark Knight | Vampires, werewolves, specters |
| **Armored** | Dark Knight | Death knights, plated soldiers |
| **Constructs** | — | Golems |
| **Demons / Fae** | — | Demons, archfiends, fae |
| **Dragonkin** | — | Wyverns, dragons |

## The materials

| Material | Tier | Strong vs | Weak vs | Element | Element strong vs | Notes |
|---|---|---|---|---|---|---|
| **Bronze/Copper** | Common | Oozes, insects | Armored | — | — | Niche, early-game, cheap |
| **Iron** | Common | Beasts, humanoids | Constructs, undead | — | — | Dulls fast (×1.5) |
| **Steel** | Common | Beasts, humanoids, armored | Cursed, undead | — | — | The reliable baseline |
| **Silver** | Uncommon | Undead, cursed (vamps, weres, wraiths) | Armored | **Moonlight** — pale white-blue radiance | Undead, cursed (amplifies its own matchup) | The classic anti-monster metal; soft edge |
| **Cold Iron** | Uncommon | Demons, fae, cursed | Constructs | **Frost** — rime + drifting mist | Fiery, fast, regenerating foes; high evo adds a brief slow | Disrupts dark magic |
| **Meteoric / Star-iron** | Rare | Demons, dragonkin (partial) | — | **Ember** — flames licking the blade | Regenerating (trolls), cold/frost creatures | Rare drop; holds an edge (×0.5 dull) |
| **Mithril-like** | Rare | Broadly good | Nothing (but low brute force) | **Spark** — crackling arcs | Armored (conducts through plate), flying | Light (−25% weight) — stays non-heavy |
| **Adamant-like** | Rare | Golems, constructs, armored | Finesse play (it's slow) | **Quake** — shockwave thud on impact | Constructs, shields/guards (bonus guard-break) | Heaviest (+40%) — heavy builds |
| **Dragonbone / Dragonsteel** | End-game | Almost everything | — | **Dragonfire** — fierce roaring flame | Nearly all living things, incl. dragons | Forged from dragon drops |
| **Voidsteel / Soulforged** | End-game | Undead, demons, liches | — | **Soulfire** — violet-black cold flame | Undead, demons, liches | The "good at both" endgame metal |

Element color pairs land on the art direction's accent palette: **Ember orange**
(meteoric, dragonsteel) vs **Frost/Moonlight blue** (cold iron, silver, mithril's
white-blue arcs), with Soulfire violet as the endgame outlier.

## Armor sets (implemented 2026-07-09)

Every material also comes as a **5-piece armor set** — Helmet, Chestplate,
Bracers, Greaves, Boots (Armory → Armor button; no world sources yet). Worn
pieces each shave **2/3/4/5% damage by tier** (full set: common 10% →
end-game 25%, hard cap 40% total), applied before block math. Piece weight =
base × the metal's weight mult (a mithril kit is light, an adamant kit is a
walking wall — feeds the future heavy-build read). Worn armor **tints the
visible body** (chest→torso, bracers→arms + forearm, greaves→legs,
boots→feet); helmets are stats-only until the body gets a head. No armor
matchups/elements yet — defense stays simple until sword depth lands.

## Sourcing (matches DESIGN.md biome gradient)

- **Lowlands**: iron, steel, bronze/copper, some silver.
- **Regular caves**: mid-tier ores, occasional rare.
- **Mountains**: meteoric, mithril-like, adamant-like — harder mountain, better metal.
- **Snowy peaks**: dragonsteel + voidsteel precursors, guarded by dragons.
- **Drops**: ores/ingots are rare monster drops; dumb mobs hoard "shiny rocks",
  smart mobs smelt + forge (better-armed enemies).
- **Loot rules**: beasts drop ONLY XP — no coins, no swords. Undead drop no
  coins either (rotted purses), but may still drop their swords; zombies (fresh
  corpses, future) are the coin exception — tag them ["undead", "zombie"].

## v1 implementation slice (proposal)

Current roster only supports a few matchups, so start with **4 materials**:

1. **Iron** — starter sword's material (what you hold now).
2. **Steel** — the upgrade baseline; strong vs the humanoid pack (goblins/orcs/ogres).
3. **Silver** — the first *decision*: swaps in vs skeletons + dark knight, worse vs armor.
4. **Meteoric (Ember)** — the element showcase: flame aura scaling with evolution,
   proves out the visual + situational-damage pipeline.

Everything else waits for its target creatures (golems, trolls, dragons). Needs from
other steps first: per-weapon data (step 4 weapon menu) and the evolution bar (step 5)
for element scaling — matchup multipliers can ship before both.

## Open knobs (tune later, not blockers)

- Exact multipliers (×1.35/×0.8) and the element +5→25% curve.
- Whether weak-matchup should also feel worse to swing (slower?) or just deal less.
- Rock wear count (60 hits), slow-effect duration on high-evo Frost.
- Ore → ingot → forge loop details (smithing is its own future pass).
- **Multi-family mobs**: Dark Knight is armored (steel strong) *and* cursed (steel
  weak). Proposed rule: multipliers stack multiplicatively (×1.35 × ×0.8 ≈ ×1.08 —
  armor helps but the curse resists). Alternative: worst-case wins.
