# The Withering (working title)

A gritty low-poly dark fantasy open-world survival RPG, built in **Godot 4.4**.
This repository is in early prototype — a playable vertical slice built bit by bit.

See `docs/DESIGN.md` for the full design and `docs/CONCEPT_ART_PROMPTS.md` for art prompts.

## How to run
1. Open Godot 4.4.
2. Import / open this folder as a project.
3. Press **F5** (Run Project). The main scene is `scenes/World.tscn`.

## Controls (prototype)
| Input | Action |
|---|---|
| WASD | Move |
| Mouse | Look |
| Shift | Sprint |
| Space | Jump |
| Left click | Sword: attack (flowing 1-2-3 combo) · Bow: hold to draw, release to loose · Pickaxe: chop (bites ore veins) |
| Right click | Sword: block · Bow: ease the string back down |
| 1 / 2 / 3 | Weapon: sword / bow / pickaxe (while no menu is open) |
| Ctrl | Dash |
| F | Mount / dismount a saddled horse (WASD ride — camera-steered, Shift gallop, Space jump; LMB = saddle sword sweeps, left/right by where you look) |
| Alt / Option | Sheathe / unsheathe sword |
| Q | Cycle offhand: shield → torch → empty (only items you own) |
| M | Mob spawn menu (spawns ~10 ft ahead, confused — won't attack until hit) |
| Tab | Menu: **1** Inventory · **2** Stats · **3** Progression · **4** Bestiary |
| I | Straight to the Inventory page |
| Esc | Settings menu (ray-traced lighting, shadows, display, input) — or closes the open menu |

(Heavy/light builds and dodge are coming later — dropped from this slice for now.)

## What's in this slice
- First-person movement with flowy momentum (eases into a stop), sprint, jump, stamina.
- A visible first-person body + a hand holding the sword (look down to see them).
- Three distinct, flowing swing animations chained as a 1-2-3 combo, with a stronger 3rd hit.
- Sheathe / unsheathe the sword on Alt (the blade moves to the hip when sheathed).
- HP and stamina bars (top-left), dash (Ctrl) with a stamina cost and brief i-frames.
- A small **forest world**: fog, dusk lighting, scattered low-poly trees and rocks.
- **Two procedural caves**: each mouth sits inside a **grassy hill** that rises
  from the forest floor and arcs over the opening — a little green hill with a
  hole in it. Sloped entry tunnels dive underground into seeded networks of
  6–9 chambers linked by real doorways, with frequent branches, loops, and at
  least one true **3-way junction** per cave — stalagmites, stalactites, rubble,
  and crystal light inside, with kobolds in the shallows and a skeleton deeper in.
  Going underground thickens the fog, kills the ambient light, and fades in a
  location title ("The Hollow Depths" / "The Dusk Forest").
- **No ghost hits**: attacks (theirs AND yours) need line of sight and a shared
  height band — mobs can no longer bite you through cave walls or floors, and
  they don't aggro through rock either.
- **Four mobs** with animated, glowing, telegraphed attacks you can dodge or block:
  - **Boars** — neutral until you get close, then wind up and **charge**.
  - **Skeletons** — slow undead swordsmen: guard-crushing overhead **smash**, or a
    quicker wide **sweep** (blockable).
  - **Goblins** — fast raiders: a crouching guard-breaking **pounce**, or a rapid
    three-hit club **flurry** at melee range.
  - **Kobolds** — weak but twitchy: a darting guard-breaking spear **lunge**, or a
    whirling **tail spin** up close.
  - Humanoids swing their weapon arm for every attack (raise, sweep, thrust, spin),
    and regular melee damage lands mid-swing so you have a beat to react.
- **Guard-break**: a strong attack landing on your raised block disables blocking
  for 2 seconds and knocks you back (with a camera rattle).
- **Ground loot**: coins/XP scatter and fall when a mob withers; if they land on
  a creature they glance off and keep falling. Walk over them and they fly up to you.
- **Leveling to 99**: XP orbs fill the blue bar; each level banks **3 stat points**.
  Five stats (CON / DEX / STR / WIS / CHA) with diminishing-returns formulas:
  CON grows the HP + stamina pools (the bars visibly widen) and speeds
  out-of-combat health regen, DEX cuts stamina
  costs and speeds regen/movement/swings, STR adds damage, flat damage
  reduction, and carry weight, WIS boosts XP gain (sword arts later), CHA boosts
  gold found (NPCs later).
- **A bow** (press 2): hold LMB to draw — damage and arrow speed ride the draw,
  DEX quickens it, STR powers it — release to loose. Real arrow projectiles with
  a shallow drop; arrows that miss stick into the world and can be walked over
  to retrieve. 20 arrows in your pack; the offhand lowers while the bow is out,
  and you can't block with your hands full. The sword now rests **point-up**
  in a ready carry, melting into each swing.
- **Perfect Guard (parry)**: raise your block in the last ~0.18s before a hit
  lands — no damage, no stamina, and the attacker staggers open for a counter.
  Timing beats even guard-breakers.
- **Progression trees** (hidden achievements): Death's Door, Marathoner,
  Untouchable, Combo Master, Perfect Guard, Slayer, Essence Drinker — each tier
  pays stat points straight into its linked stat ("grow what you use"), with
  escalating rewards and anti-farm rules. Tiers never run out — past the authored
  six, each completion scales the next threshold up (tree-specific growth).
  One tree stays ??? until NPCs exist.
- **Tab menu**: Inventory | Stats | Progression. The Stats page is a
  Cyberpunk-style sheet — hover an attribute for live before→after numbers,
  queue points with +/− and Confirm. The Progression page shows earned tiers,
  the next tier with a live progress bar, and hides the rest.
- **Inventory** (I, or Tab page 1): item list with a carry-weight limit
  (overweight = slowed, no sprint; STR raises the limit), five armor slots, and
  an offhand slot.
- **Offhand items**: you start owning a wooden shield and a torch. Cycle them with
  **Q** (or click in the inventory) — the item animates up into your left hand,
  sways as you move, and lowers away when swapped. The shield lifts to guard the
  view while you block; the **torch actually casts flickering light** (bring it
  into the caves).
- **Mob spawn menu** (M): spawn any mob ~10 feet in front of you.
- **Weapon materials** (docs/MATERIALS.md): every sword is made of one metal with
  real matchup damage vs creature families — silver shreds the undead and the
  cursed, steel dents armor but the curse drinks it, iron is honest vs beasts
  and raiders. Elemental metals (silver's Moonlight, meteoric's Ember...) wear a
  glowing aura and pay situational bonus damage. Click a sword in the Inventory
  to wield it (the blade rebuilds in your hand); the **Armory (dev)** column
  conjures any metal for testing, and mobs rarely drop material swords.
- **Mining**: press **3** for the pickaxe. **Silver veins** seam the cave rooms
  and a **meteoric vein** usually burns ember-orange in the deepest chamber —
  four bites crack one open into ore chunks that magnet to you. The first ore
  of a new metal is forged straight into that sword (the unlock moment); spares
  stack for the smithing loop to come. Swords skate uselessly off the rock.
- **Bestiary** (Tab, page 4): every creature is listed from the start but its
  page stays **???** until your first kill of one — then the name, families,
  stats, and kill count open up. Weaknesses are earned one metal at a time:
  land a material on a creature and that matchup is **proven** on its page
  (green = bites deep, red = resisted). Folklore you learn by doing, not reading.
- **A day/night cycle** (Skyrim pace): one full game day every **20 real
  minutes**. The sun and moon ride one wheel; the sky keyframes through dawn,
  noon, the game's signature dusk (17:30), and a dark frost-blue night where
  the torch earns its keep. **Daybreak / Nightfall** titles mark the turns;
  the caves ignore the sky completely.
- **Settings menu** (Esc): the headliner is **Ray-Traced Lighting** — Godot's
  SDFGI real-time global illumination preset (bounced sunlight, screen-space
  indirect light + AO + reflections, volumetric light shafts through the trees
  at dawn, and glow that makes elemental blades and cave crystals bloom).
  Heavy on the GPU, off by default. Plus shadow quality (Low/Med/High),
  fullscreen, VSync, mouse sensitivity, and FOV — all applied live and
  remembered between runs (`user://settings.cfg`).
- **Horses**, two kinds: **wild herds** graze the far tree line, spook when you
  press in, and never take a rider. **Saddled horses** near the spawn meadow
  are yours: **F** mounts — WASD reins steered by your look, **Shift** gallops
  (outruns anything), **Space** jumps, LMB throws flat **saddle sweeps** left
  or right of the neck. Hurt ANY horse even once and it answers: it wheels and
  **kicks you flat** — a real knockdown (fall, lie there, stagger up) with **no
  protection at any point** (enemies keep swinging; a perfect parry or dash
  i-frames are your only outs) — and that horse **never carries you again**.
  Your own swings can never hit the horse you're riding. If your horse dies
  under you, you go down with it.

Everything is placeholder primitives (capsules/boxes). Real art comes much later
(see build order, step 11).

## Project structure
- `scenes/World.tscn` — main scene (a thin shell; the world is built in code).
- `scripts/World.gd` — environment, ground (with cave holes), forest, caves, player,
  enemies + horses, underground ambience + location titles.
- `scripts/DayNight.gd` — the sky's clock: sun/moon wheel, keyframed sky/fog/ambient,
  Daybreak/Nightfall titles (20 real minutes per game day).
- `scripts/Horse.gd`, `SaddledHorse.gd` — passive wildlife: graze/flee AI, the kick +
  trust system, and the whole riding rig (reins, gallop, buck-off).
- `scripts/Cave.gd` — procedural cave generator (mouth, ramp, chambers, tunnels, decor).
- `scripts/Player.gd` — first-person controller + combat + HUD + Tab menu + spawn menu.
- `scripts/Stats.gd` — the character sheet: five stats, formulas, XP curve, progression trees.
- `scripts/Enemy.gd` — base mob AI: wander/chase, melee, telegraphed strong attack, wither death.
- `scripts/Boar.gd`, `Skeleton.gd`, `Goblin.gd`, `Kobold.gd` — the archetypes (stats + bodies).
- `scripts/Pickup.gd` — coins/XP that fall, rest on the ground, and magnet to you.
- `docs/` — design doc, concept art prompts, roadmap.
