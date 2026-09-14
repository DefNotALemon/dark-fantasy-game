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
| Left click | Sword: attack (flowing 1-2-3 combo) · Bow: hold to draw, release to loose · Pickaxe: chop (bites ore veins, digs cave rock) · War axe: alternating chop/cleave |
| Right click | Sword: block · Bow: ease the string back down |
| 1 / 2 / 3 / 4 | Weapon: sword / bow / pickaxe / **war axe** (while no menu is open). The axe is a heavy one-handed cleaver — ~35% harder-hitting than the sword, slower, no combo: two alternating full SIDE swings (forehand right-to-left, backhand back across — a feller's strokes at trunk height). No material matchups yet — honest iron. **It also fells trees, properly**: every bite EATS a triangular wedge out of the trunk on the side you're standing (real geometry removed, pale heartwood laid open, deeper each swing), and when the wedge runs past the centre the trunk breaks *on that notch* — a stump stays rooted and everything above it goes over. When the crown hits dirt the canopy comes apart: every leaf breaks off and planes down to lie in the shape of the fallen crown, and the trunk splits into as many **logs** as the tree was metres tall |
| Ctrl | Dash — **or COMMIT**: press it during a sword swing (or swing during a dash) with an enemy in front of you and the step goes into the cut instead of your footwork. The blow lands at ×2.05 with ~a metre of extra reach, and costs 30 stamina *on top of* the swing, paid whether or not it connects. With nothing ahead, or nothing left in the tank, Ctrl is still just a dodge |
| V | Camera: first person → **third person** over the right shoulder. Short press in third person **swaps shoulders**; **hold 1.5s** to glide back into first person. Every switch is animated, walls pull the camera in, and your last choice is remembered between runs |
| C | **Stance cycle**: stand → crouch → **prone** → stand. Each step is slower, lower, and harder to spot — in tall grass calm enemies' wake radius is 60% upright, 35% crouched, **22% prone** (flat to the earth, chin over the grass line). Going prone settles slowly with a body-weight roll — that's the animation. Jumping or climbing stands you up |
| Space | Jump — or **climb**: if there's a grabbable ledge in front of you (up to ~2.6 m), Space mantles up onto it instead, with a pull-up animation. Works mid-air (grab a lip as you fall), costs a little stamina — spam it to scale cave walls or climb out of anywhere you're stuck (dig footholds with the pickaxe if the wall's too tall) |
| F | Interact: **sleep** at a bed (the bedroll by spawn) — sleeps to dawn, full heal, and **the underground SHIFTS**: every cave re-carves except the permanent entrance caves (24 m bubbles around each mouth, with a no-spawn barrier). Otherwise: mount / dismount a saddled horse (WASD ride — camera-steered, Shift gallop, Space jump; LMB = saddle sword sweeps; **ride INTO a steep rock face and the horse SCRAMBLES up it** — reins steer the line, ease off to let go) |
| Alt / Option | Sheathe / unsheathe sword — the shield stows on your back / draws with it. **The Hunch** (settings toggle, on by default): the blade auto-draws the instant something turns hostile and auto-sheathes after 6.7 quiet seconds |
| Q | **The ITEM WHEEL** (8 slots): hold Q and drag toward a slot, release to use it — swords wield, shield/torch take the arm, the bedroll unrolls, the potion goes down. In the Inventory: tap Q over an item to add it to the wheel, **hold Q** to choose exactly which slot it rides |
| E | Pick up the dropped item under your gaze — or **shoulder a log** from a felled tree (four is all a back will take; the load rides visibly on your shoulder and rolls off the moment you jump, climb, crouch, go prone, mount up, take a hit, or reach into your pack) — or **pack up a bedroll** (becomes a backpack item, 4 wt; click it in the Inventory to unroll it on the ground ahead — camp anywhere on the surface) |
| B | **Drop**: in the Inventory, sheds the hovered item at your feet |
| M | Mob spawn menu (spawns ~10 ft ahead, confused — won't attack until hit) — plus a dev button that **tears open a whole new cave mouth** ~30 m ahead (quake included), and the **CAVE LAB**: New Cave 1-4 raise four rival cave generators as walk-in rock massifs ~45 m ahead (Polished Worms / Halls & Passages / The Riverbed / The Cathedral — all diggable, all pixel-skinned like the real caves now, all with REAL cave spawns inside and dressed daylight entrances; one lab stands at a time) |
| G | **Creative menu (dev)**: every item in the game — sword / 5-pc armor set / raw ore for all 10 metals, plus shield, torch, pickaxe, arrows, bedroll, wood, and the junk loot |
| Tab | Menu: **1** Inventory · **2** Stats · **3** Progression · **4** Bestiary — the Inventory is **Terraria rules**: click a pack item to equip it (it MOVES into its slot), click a worn slot on the doll to take it off. The **Old Rucksack** is worn on its own **Back** slot and IS your grid: worn = 27 slots, bare back = 9. You start dressed, and saves put everything back exactly where you left it |
| I | Straight to the Inventory page |
| F4 | **Claude (dev)**: a live chat card over the game — streamed replies with the game state riding along (where you are, the hour, the weather, health, FPS). Backend dropdown: Anthropic (key from `ANTHROPIC_API_KEY` or the card's KEY field → `user://claude.cfg`) or any OpenAI-compatible local server. A Haiku note-taker writes bugs/ideas/requests to `user://claude_notes/`, and **Send up the line** drops notes + transcript into `notes/claude-handoff/` for the Cowork session |
| Esc | Settings menu (ray-traced lighting, shadows, display, input, the Hunch, **Main Hand** — mirror the whole kit for lefties — and **Save / Load**) — or closes the open menu. All menus render 67% larger |

(Heavy/light builds and dodge are coming later — dropped from this slice for now.)

## What's in this slice
- First-person movement with flowy momentum (eases into a stop), sprint, jump, stamina.
- A visible first-person body + a hand holding the sword (look down to see them).
- Three distinct, flowing swing animations chained as a 1-2-3 combo, with a stronger 3rd hit.
- You start with the blade **sheathed** — a drawn sword should mean something.
- Sheathe / unsheathe the sword on Alt (the blade moves to the hip, the shield to your
  back). **The Hunch**: sword + shield leap out on their own when anything turns hostile,
  and ride home after 6.7 calm seconds (toggle in settings). Raising a block also draws.
- HP and stamina bars (top-left), dash (Ctrl) with a stamina cost and brief i-frames.
- A small **forest world**: fog, dusk lighting, scattered low-poly trees and rocks.
- **Living grass**: short faceted tufts carpet the ENTIRE surface (Valheim-lush;
  paths come later) — gust waves roll the meadow, every blade sways, and the
  grass **bends away from you** as you wade through. It withers grey near cave
  mouths, and it's uprooted where you dig.
- **Tall hiding grass**: dense chest-high patches you can vanish into — stand
  (don't sprint) inside and calm enemies barely notice you ("~ hidden ~" shows
  while you're concealed). Sneak past packs, or line up the first arrow.
- **CAVES 2.0 — the CATHEDRAL underground** (docs/CAVES_PLAN.md): one map-wide
  voxel underground, now carved by the Cathedral generator that won the cave-lab
  bake-off. ~13 authored caverns — grand columned naves, mid halls, deep crypts —
  joined into one looping network of walkable capsule tunnels, every cavern
  floored with flat sediment terrain you can actually fight on, all roughed by
  noise so nothing reads man-made. Every sleep re-authors the whole network.
  The rock wears a NEW PIXEL SKIN: smooth walkable geometry, but colors are
  quantized into chunky ~1 m texels — deliberately "less real", like pixel art
  draped over stone. Crystals light the naves, silver seams run the middle
  depths, meteoric waits at the deepest reachable floor, and dweller packs get
  meaner the deeper you go — a dark knight holds the bottom.
- **The pickaxe DIGS**: bites carve real holes in cave rock — walls, floors,
  ceilings. Rocks physically fall from every bite (mining a ceiling drops a slab
  that HURTS — undercut at an angle). Dig a slow stubborn shaft all the way back
  up to the surface if you're lost, or down toward the glow of something better.
- **Digging PAYS, Minecraft-style**: every bite of bare rock has a depth-scaled
  chance to knock ore loose — bronze and iron near the surface, silver and cold
  iron in the middle dark, meteoric/mithril/adamant only in the true deeps. The
  endgame metals (dragonsteel, voidsteel) are **never** dug from the ground.
  First ore of a new metal still forges its sword on the spot.
- **Armor sets for every metal** (5 pieces: helmet/chest/bracers/greaves/boots)
  — and any full set in your pack gets a **one-click "Equip set" button** in the
  Inventory's Equipped column.
- Going underground thickens the fog, kills the ambient light, and fades in a
  location title ("The Hollow Depths" / "The Dusk Forest"). (The old grassy-hill
  chamber caves are retired — Cave.gd stays on disk / in git history.)
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
- **Offhand items**: you start owning a wooden shield and a torch. Cycle with
  **Q** (or click in the inventory) — shield → torch → **shield + torch together**
  (the shield straps to the forearm so the torch shares the fist) → empty. Items
  animate up into your left hand, sway as you move, and lower away when swapped.
  The shield lifts to guard the view while you block (strapped or not); the
  **torch actually casts flickering light** (bring it into the caves). Sheathing
  stows the shield across your back — the torch stays lit in your hand.
- **Darkness watch**: step into a cave (or into the night) and the torch comes
  out on its own, sharing the arm with your shield. While it's dark, sheathing
  only puts the SWORD away — shield and torch stay raised, and blocking works
  from behind the shield without drawing steel. Back in the light, your old
  loadout returns (unless you picked something yourself with Q in the dark).
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
