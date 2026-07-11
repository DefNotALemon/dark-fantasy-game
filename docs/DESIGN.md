# Dark Fantasy Open-World Survival RPG — Design Prompt

## Concept
A first-person, single-player dark fantasy open-world survival RPG. The world is grim, dangerous, and overrun with hostile races and creatures. Combat is melee-focused and skill-driven, character power is expressed through a D&D-style stat sheet, and progression comes from **leveling, weapon styles, and weapon evolution** — your gear grows with you.

There is **no spell-casting magic** in this game. Magic exists only as **artifacts, potions, and crystals**, and as **elemental effects tied to a weapon's material and level** (see Combat).

**Engine/platform:** Godot.

**Art direction:** 3D, **gritty-realism low-poly** — faceted low-poly geometry with realistic, weathered materials and dramatic lighting. **Dark fantasy with vibrant accent color** — grim, atmospheric base (fog, dusk, ash) lit by vivid pops: elemental blades, ember firelight, cold aurora skies. Think *Elden Ring*'s mood and *Ghost of Tsushima*'s color drama, rebuilt at a lower polygon count. Moody but never drab.

### Visual identity / key art
- **Composition language:** lone figure dwarfed by a hostile vista — jagged faceted peaks, a ruined castle, a distant dragon, drifting ash. A single glowing elemental weapon as the focal light source.
- **Withering motif:** drifting ash/dust particles throughout (enemies wither to dust on death — make it the world's signature texture).
- **Palette:** desaturated slate/indigo base, ember orange and frost blue as the recurring accent pair, snow-white highlights on peaks.
- **Placeholder title:** *The Withering* (working name — change freely).

Start small and vertical-slice first: one playable character, a small playable area, working combat, and one or two enemy types. Expand from there.

## Core Pillars
1. **Skill-based first-person melee** — timing, spacing, and reading the enemy matter more than stat-padding.
2. **Weapons that grow with you** — swords carry styles, evolve with use, and gain elemental power from their material.
3. **Build identity** — "heavy" vs. "non-heavy" builds play fundamentally differently.
4. **Tactile death** — enemies feel mortal; killing them is visually satisfying.
5. **Meaningful progression** — leveling and weapon mastery change *how* you fight, not just numbers.
6. **Expansive, living world** — a dense, reactive world full of enemies, materials, and factions that act with and against each other.

## Current Implementation Status (prototype)
What's actually built in the Godot prototype so far:

**Player & combat.** First-person movement with momentum, sprint, jump, dash (Ctrl, stamina + i-frames), and **auto step-up** over ledges up to ~1/4 the player's height. Visible first-person body (torso, legs, both hands) with a swinging-arm walk cycle; the sword sheathes/unsheathes on Alt (handle shows in a hip scabbard) and has a draw-from-sheath attack. Left-click runs a flowing 1-2-3 combo (resets after ~0.75s idle). **Blocking:** right-click guards — a **shield negates all damage**, a **bare-sword block halves it**; enemy *strong* attacks break the guard (2s disable) but a shield still eats the hit. Getting hit throws you out of your action; a **lunge from a boar/orc/ogre/skeleton flings you to the side** and the attacker barrels past. Respawn cancels all in-flight knockback/damage with brief i-frames.

**HUD & progression.** Bottom-center stamina/health/level bars (health red; bars fade when idle, never fully gone). Very slow out-of-combat healing after ~3s. Killing a creature drops **tier-colored XP orbs (green→purple) and gold coins** that burst out, float with the death shards, then fly to your waist; a fading top-right log shows gains and level-ups. Offhand (shield/torch) cycles with Q; there's a simple inventory and a mob-spawn test menu (M).

**Creatures.** A shared `Enemy` base (calm-wander → agitated, telegraphed strong attacks, flinch, caught-mid-attack retreat, white-flash → triangle-shatter death). Kinds, in ascending strength: **Kobold < Goblin < Skeleton < Orc/Ogre < Dark Knight**, plus the neutral **Boar**. The fodder (kobolds, goblins, boars) go down in a couple of hits; **skeletons and especially the new mobs (orcs, ogres, dark knights) soak several hits**. Smart kinds (everything but kobolds) **circle/orbit** the player at a steady radius, leaning into their movement, then dart in to strike — boars circle too, in a much bigger, more-rotated arc before charging. Orcs are fast, strong sword-wielders with varied attacks (a shoulder-**charge**, a lunging **thrust**, and a rapid **slash** combo); ogres are huge, hit hard, attack fairly briskly, and mix a lunging **bite**, a grab-and-**throw** (hurls you back over the shoulder), and the shared charge; dark knights get their own **shield-bash + dark-combo**. A **charge** shoves you to the side and the attacker barrels straight past. Boars roam the overworld only; **every other kind spawns in packs in the caves** (kobold 6-10, goblin 3-6, skeleton 4-7, deeper rooms hold orcs/ogres, and a champion room holds a dark knight leading orcs). Far-off idle mobs sleep to save CPU.

**World.** A forest overworld with procedural caves: torn-open, grass-covered block mounds around each mouth, a flat clear walk-in, and round "wonky-cylinder" chambers linked by tunnels, lit by glowing crystals, with an underground ambience shift and location titles.

*Not yet built (still design-only):* sword styles/material/elemental systems, D&D stat sheet & leveling math, smithing, shifting caves, camps/raids, biomes beyond the forest, character customization, real art (everything is placeholder low-poly primitives).

## Controls & Combat Mechanics

> **Design change:** The old Z/X/C in-combat stance-switch keys are **dropped.** Styles are now **set in the menu** ahead of time, and combat runs on a single **attack loop per equipped style**.

### Inputs
- **Left click** — attack. Performs the swings of your **currently equipped style** (a combo loop, not a single hit).
- **Right click** — context-dependent on build:
  - **Non-heavy builds** → block / guard.
  - **Heavy builds** → dodge (heavies trade blocking for a committed evasive move).
- **Ctrl** — dash. Available to **all non-heavy builds**. Heavy builds do not dash (their evasion is the right-click dodge instead).

### Sword styles (set in the menu)
- Every **sword type + weight has a base attack loop** (its default style) — e.g. a rapier loop feels fast and stabby, an oversized-sword loop slow and heavy.
- **Cooler / rarer swords carry their own unique styles.** Obtaining such a sword **unlocks its style**.
- The player **sets their active style in the menu**, not in real-time. The equipped style defines your left-click loop.
- **A style is only usable effectively if it fits your sword's material and your stats.** Equip a heavy brute style on a flimsy light blade, or without the Strength to swing it, and it performs poorly (sluggish, low damage, high stamina cost). Match the style to the right blade + build and it shines.

### Style progression (use it to grow it)
- **Style points** are earned by **using a style** in combat. Spend them to **upgrade that style**.
- **You add new swings/attacks to a style by upgrading the sword you got the style from** — the sword and its style level up together. A maxed signature sword unlocks the full combo set of its style.

### Sword evolution & durability
- **Evolution bar:** every individual sword has its **own evolution bar that fills the more you use it**. As it fills, the sword **levels up** — improving its stats and (with material) its elemental effect (see below).
- **Durability:** every sword has durability that **slowly ticks down with use**. It drains slowly, but it **still matters** — neglecting it means weaker hits and eventual breakage, so maintenance (repair/smithing/sharpening) is part of the loop.

### Build types
- **Heavy build** — defined by **carried weight, a heavy-class weapon, and a bigger/brute character**. High durability/power, slower; right-click = dodge, no dash.
- **Non-heavy build(s)** — more mobile; right-click = block, Ctrl = dash.
- Whether a character counts as "heavy" is driven by weight + weapon class + body type, so the player slides into a heavy or non-heavy feel based on how they equip and build, not a fixed class selection.

## Weapons
Swords are the centerpiece of combat, but the full melee/thrown roster matters. **Weapon type and weight determine its base attack loop, reach, speed, stamina cost, and whether a build reads as heavy.** Each weapon's feel should match its weight and use case (a rapier is fast and precise; an oversized sword is slow and devastating). For the vertical slice, include **one weapon of each type at a representative weight** so each use-case is playable.

### Swords (core focus)
- **Rapiers** — fast, precise, light.
- **Short swords** — quick, close-range.
- **Hand-and-a-half ("bastard") swords** — versatile, mid-weight.
- **Sword + small shield (buckler)** — one-handed sword paired with a small shield.
- **Longswords** — heavy swords.
- **Huge oversized swords** — slow, weighty, brute (heavy-build territory).

### Other melee weapons
- **Axes** — small axes (some **throwable**) and large axes.
- **Hammers** — small and large.
- **Scythes**.
- **Knives** — fast close-range (not thrown).
- **Staffs**.

### Ranged weapons
- **Shortbows** — fast, shorter range.
- **Longbows** — slower draw, longer range / more power.
- **Crossbows** — slow reload, high punch, easy to aim.

### Suggested additions (open for approval)
- **Spears / pikes** — reach, thrusting, good for keeping enemies at bay.
- **Halberds / glaives (polearms)** — heavy reach weapons; could read as heavy builds.
- **Maces / morningstars** — blunt, armor-breaking, pairs with the blunt-side sharpening-rock rule.
- **Flails** — hard to block, unpredictable arcs.
- **War picks** — armor-piercing, anti-heavy-armor niche.
- **Throwing axes** as a dedicated light thrown option (since axes already throw).

(Thrown weapons and bows need an aim/draw/throw input — to be defined.)

## On-Screen Titles & Notifications
The game uses **large title text in a medieval-style font**, fading in/out on screen, to announce key world events. These are atmospheric banners, not menu popups. Core triggers:
- **Entering a settlement** → *"Now Entering (Town Name)"* — displays the settlement's name as the player crosses into it.
- **A cave/dungeon shift occurs** → *"The World Has Shifted"* — paired with the earthquake shake.
- **A camp spawns overnight nearby** → *"Enemies Are Near"* — warns the player that a fresh hostile camp has appeared (the only time this fires; see Camps).

Keep the style consistent: same font, framing, and fade timing across all of these so they read as one cohesive "world event" system. (More event titles can be added later — e.g. region/biome names, boss arrivals.)

## Character Customization
- Deep, Skyrim-style character creation: race, sex/body, face sculpting, skin/hair, scars, and other appearance options.
- Since the game is first-person, ensure customization still reads in menus, inventory/paper-doll views, reflections, or cutscenes.

## Stats, Leveling & Character Sheet

### The stat sheet
Players **and** creatures share a **D&D-style stat sheet**. Each stat gives a **real, tangible advantage** (not just flavor):
- **Vitality (Constitution)** — max HP, survivability, resistance to status effects.
- **Dexterity** — dodging/evasion, attack speed, finesse-weapon accuracy.
- **Strength** — melee damage, heavy-weapon handling, carry weight (feeds heavy vs non-heavy).
- **Endurance/Stamina** — stamina pool for attacks, blocks, dashes, sprinting.
- **Perception** — accuracy/range (esp. bows), spotting traps, ambush awareness.
- **Will / Fortitude** — resistance to fear, curses, elemental/magical damage from artifacts and crystals.
- (Final stat list TBD — these are proposed; we can rename to taste.)

Derived stats (HP, stamina, evasion, carry weight, resistances) are computed from the core stats.

### Leveling system
- The player **levels up** by earning XP, and each level grants **points to assign into the D&D stat sheet** — so growth is player-directed and each point is a meaningful, felt upgrade.
- **Long-term / effectively endless leveling:** the game is meant to be **played for a long time**, so the player can **keep leveling and investing** well into late-game (no hard wall), with scaling costs/rewards to keep it meaningful.
- Stats gate and enhance other systems: build type (heavy/non-heavy via Strength/carry weight), weapon handling, and **whether a given sword style is usable effectively** (a style needs the stats to back it).

### Difficulty philosophy
The game **should not be easy** — but it should be **difficult *and* enjoyable** at the same time. Challenge comes from skill-based combat, smart enemies, and the living world, not from cheap or unfair spikes. Power growth (levels + skill trees + gear) should make the player **feel stronger over time** while the world keeps offering tougher threats to match.

## Progression Systems
Progression runs on **three intertwined layers**, so growth feels like both *you* getting stronger and *your gear* growing with you:

### 1. Character leveling (the D&D sheet)
- Earn XP → **level up** → assign points into the **D&D stat sheet** (Vitality, Dexterity, Strength, etc.).
- Long-term and effectively endless (see Stats, Leveling & Character Sheet).
- Your stats determine **which styles you can wield effectively** and your build type.

### 2. Sword styles (learned from swords, grown by use)
- Styles are **not bought from a tree** — they come from **swords**. Every sword type/weight has a base style; **rarer swords carry unique styles** that you unlock by acquiring them.
- The player **equips a style in the menu**; it's effective only if it **fits the sword's material and your stats**.
- **Style points** are earned by **using a style**, and spent to **upgrade that style**.
- **New swings/attacks are added to a style by upgrading the source sword** — sword and style level up together; a fully upgraded signature sword reveals its style's complete combo set.

### 3. Sword evolution & durability (per individual weapon)
- Each sword has its **own evolution bar** that fills with use, **leveling that specific weapon** (better stats, stronger material element).
- **Durability** slowly drains with use and must be maintained — still meaningful, never ignored.

### Optional Core/Body tree (TBD)
- A small shared tree may still exist for build-wide fundamentals not tied to a weapon — stamina, dash/dodge, blocking, carry weight, resistances, crystal/potion slots — fed by a slice of level-up points. (Keep or fold into stats — to confirm.)

### Difficulty & pacing
- Because three systems grow at once (you, your style, your specific sword), power should ramp smoothly without trivializing the world — tune XP, style points, and evolution rates together as the main balance levers.

### Build identity
- You can't max everything quickly, so investment forces choices — a finesse rapier duelist, a brute oversized-sword juggernaut, a frost-axe skirmisher, etc.
- Heavy vs non-heavy interacts here: Core-tree choices (carry weight, dodge vs block) reinforce which builds your weapon investments support.

## Enemies & Bestiary
The world should feel **expansive and alive** — densely populated with hostile races and creatures across a range of threat tiers, intelligence levels, and biomes. All creatures use the **same D&D stat-sheet system** as the player, and many participate in the living-world systems below (looting ore, smithing, traveling, fighting each other).

**Intelligence tiers** matter (they drive the ore/smithing behavior and combat AI):
- **Dumb** — beasts and lesser undead; hoard shiny ore, swing wildly.
- **Cunning** — goblins, kobolds; set ambushes, use crude gear, smelt ore.
- **Smart** — liches, warlords, dragons; forge gear, command others, use tactics.

### Fodder / common (numerous, low threat)
- **Skeletons** — common undead, easy to shatter (blunt-weak).
- **Kobolds** — small, numerous, cunning in groups.
- **Goblins** — common humanoid threat; can carry crude forged gear.
- **Giant rats / cave vermin** — swarming beasts.
- **Zombies / ghouls** — slow shambling undead.

### Mid-tier threats
- **Orcs** — strong humanoid raiders.
- **Hobgoblins** — disciplined goblinoid soldiers.
- **Bandits / cultists** — hostile humans.
- **Gnolls** — hyena-like pack hunters.
- **Harpies** — flying harassers.
- **Giant spiders** — webbing ambushers, often poisonous.
- **Wargs / dire wolves** — fast beasts, sometimes ridden by goblinoids.
- **Wraiths / specters** — incorporeal undead (resist non-magical/non-silver?).
- **Ogres** — big, dumb brutes.

### Elite / dangerous
- **Trolls** — regenerating brutes (fire/acid stop regen).
- **Wights / death knights** — armed, armored undead champions.
- **Minotaurs** — charging powerhouses.
- **Vampires** — fast, deadly (silver-weak).
- **Werewolves / lycanthropes** — silver-weak shapeshifters.
- **Golems** — stone/iron constructs (blunt-weak, edge-resistant).
- **Wyverns** — lesser flying dragon-kin.

### Apex / boss-tier (rare)
- **Liches** — rare undead overlords ("the occasional lich"); command lesser undead.
- **Dragons** — apex threats, varied by element; the smartest forge/hoard.
- **Demons / archfiends** — endgame horrors.
- **Giants** — towering brutes.

(This is a starting bestiary, not a cap — the world is meant to keep growing. Each entry should get a stat block, biome, loot table, and material weaknesses.)

### Death animation
- When an enemy dies it plays a **dying animation**, then **withers into dust** as it expires.

## Magic, Items & Crystals
- **No spells / no spellcasting.** The player never casts magic directly. All "magic" is delivered through items and earned effects.

### Magical artifacts
- Special equippable/usable items with powerful, often unique effects.

### Crystals — buffs & elemental statuses
Crystals grant **buffs and extra elemental statuses**, such as:
- **Poise / "keep going"** — let you take a hit mid-combo and continue the loop instead of being interrupted.
- **Damage reduction** — take less damage.
- **Elemental resistance** — withstand elemental damage.
- (And similar defensive/offensive status effects.)

### Potions — consumables
Potions can do a wide range of things, including:
- **Stat buffs**.
- **Healing**.
- **Movement speed**.
- **Adding knockback** to your hits.

### Elemental effects (material- and level-locked)
- A weapon's elemental effect is **exclusive to the material it's made of** — each material grants its own element (or none). The player doesn't cast it; the weapon carries it.
- **Visuals:** the element shows as an **effect wrapped around the sword** — flames licking the blade, frost rime and mist, crackling sparks, etc. It's a constant aura on the weapon, intensifying mid-swing.
- **Visual scaling:** the effect **grows with the weapon's evolution level** — a low-level blade shows a faint shimmer; a maxed one is fully wreathed in its element.
- **Damage:** the elemental effect deals **bonus damage situationally — based on the weapon's material *and* the creature being fought.** It's not flat extra damage; it's strongest against the right targets (e.g. fire vs. regenerating trolls, frost vs. fast/fiery enemies), tying directly into the material-matchup system. Against resistant or wrong-type foes it adds little.
- This makes material choice a **double decision**: the silver/steel matchup *and* which element you want, earned by investing use into that specific weapon. (Crystals can still add temporary elemental statuses on top — see Crystals.)

## Weapon Materials, Sharpening & Smithing

### Sharpening rocks
- Rocks the player **rubs onto the blade edge** (or the **blunt impact area** on weapons with no blade).
- Effects: make the weapon **sharper**, add **extra damage against certain monster types**, etc.
- **Default model:** the bonus **wears off as the edge dulls with use** (swing/hit count), so you re-apply rocks between fights. (Tweakable.)

### Material matchups (silver/steel mechanic)
A **material-vs-enemy** system in the spirit of silver vs. steel: a weapon's **material helps or hurts** depending on the enemy, so the player swaps weapons to match the threat. Starter material list (expandable):

| Material | Tier | Strong against | Weak / neutral against | Notes |
|---|---|---|---|---|
| **Iron** | Common | Beasts, humanoids | Constructs, most undead | Cheap, dulls fast |
| **Steel** | Common | Beasts, humanoids, armor | Cursed/undead | The reliable baseline |
| **Silver** | Uncommon | Vampires, werewolves, wraiths, undead | Heavily armored foes | The classic anti-monster metal |
| **Cold Iron** | Uncommon | Demons, fae, cursed creatures | Constructs | Disrupts dark magic |
| **Bronze/Copper alloy** | Common | Oozes, certain insects | Most armored foes | Niche, early-game |
| **Meteoric/Star-iron** | Rare | Demons, dragons (partial) | — | Rare drop, holds an edge |
| **Mithril-like (light alloy)** | Rare | Broadly good; great on fast weapons | Pure brute-force needs | Light = stays non-heavy |
| **Adamant-like (dense alloy)** | Rare | Golems, constructs, armor | Fast/finesse play (heavy) | Heaviest; crushes defenses |
| **Dragonbone/Dragonsteel** | End-game | Almost everything, incl. dragons | — | Forged from dragon drops |
| **Voidsteel/Soulforged** | End-game | Undead, demons, liches | — | The "good at both" rare endgame metal |

- Materials interact with **sharpening rocks** and **crystals** (e.g. a rock that adds "+ vs undead" stacks with silver).
- Blunt weapons care about **density/weight** more than edge material (good vs skeletons, golems).

### Fantastical ingots & blacksmithing
- **Blacksmithing**: forge weapons (esp. swords) from **fantastical ingots**.
- Ingot/blade qualities trade off:
  - **More durable** (lasts longer, resists wear).
  - **Sharper** (more damage / better edge).
  - **Rare end-game ingots** are good at **both**.

### Ores & ingots as drops (and monster behavior)
- **Ores and ingots** can be **monster drops**, but they are **rare**.
- Monster behavior around ore reinforces the world:
  - **Dumber monsters** pick up ores as a **"shiny rock"** off the ground, like a curious kid.
  - **Smarter monsters** pick up ores and may **smelt them into ingots** and even **forge swords** from them — so smarter enemies can be better-armed.

## World & Biomes
A **very large, changing open world** — a single landmass **surrounded by ocean**, fed by **rivers that flow down from the mountains**. The handcrafted overworld is stable, but it is punctuated by **procedurally generated content** that makes the map feel restless and never fully explored.

### Launch biomes
- **Plains** — open grassland, the connective tissue between regions.
- **Flower fields** — bright, calmer pockets within/near the plains.
- **Towns** — small settlements.
- **Cities** — larger settlements.
- **Cities with castles** — major hubs with fortifications.
- **Forests** — denser woodland.
- **Mountains** — rugged highlands; source of the rivers.
- **Snowy mountains** — frozen peaks.
- **Rivers** — run from the mountains down to the sea.
- **Ocean** — surrounds the entire land (border + future content).

*(More biomes to come later; the above is the launch set.)*

### Biome distribution — where creatures & materials come from
The world has a **difficulty gradient that climbs into the mountains and peaks in the snow.** Creatures and ores are seeded by region:

**Lowlands (plains, flower fields, forests, settlements):**
- Common/mid-tier creatures — skeletons, kobolds, goblins, orcs, beasts, bandits.
- Common ores — iron, steel, copper/bronze, some silver.
- Fewer caves; lighter dungeons.

**Regular cave dungeons (anywhere in the world):**
- Undead dungeons (procedural), plus the heavier horrors that surface from below — **demons** and **giants** turn up in regular cave dungeons.
- Mid-tier ores and the occasional rare find.

**Mountains:**
- **Far more caves** than the rest of the world, and **stronger dungeons** inside them.
- Signature creatures: **wyverns** (skies/cliffs), **golems** (stone/iron guardians), and **liches** ruling the stronger mountain dungeons.
- **Mythical / end-game ores** are found here — the harder the mountain, the better the metal (meteoric/star-iron, mithril/adamant-like, dragonbone precursors).

**Snowy mountains (hardest region):**
- **The rarest materials in the game** — the top-tier end-game ingots (dragonsteel, voidsteel/soulforged precursors).
- **Dragons** live here: their **internal flame keeps them warm**, so the frozen peaks are their domain. Apex encounters, apex rewards.

> Design intent: power and reward scale **upward and into the cold**. A player gears up in the lowlands, braves mountain caves for mythical ore, and only the strongest push into the snowy peaks for dragons and the rarest metals.

### Dynamic caves & dungeons (procedural)
- **Caves open up in the earth** over time — newly generated entrances appear in the world.
- **Earthquake feedback:** if the player is **near a cave as it opens, the screen shakes** like an earthquake (with rumble audio) to signal it.
- Cave contents are **procedurally generated** and varied:
  - **Undead dungeons** — procedurally generated dungeon layouts populated with undead creatures.
  - **Goblin caves** — lairs where goblins actually live (nests, hoards, crude forges).
  - (Room for more types later — beast dens, mineral caverns, etc.)
- Caves are a renewable source of exploration, loot, ore, and danger — reinforcing the "world keeps changing" feel.

### Shifting caves (the core "living cave" mechanic)
- **Every 1–2 in-game days, the cave/dungeon layouts shift and regenerate.** Passages, rooms, and exits change, so a cave you mapped yesterday is different today.
- **Stronger shake when you're inside.** A shift always produces the earthquake effect, but it's **much more intense if the player is inside a cave when it happens** — heavy screen shake and rumble to sell the world rearranging around you.
- **Stability rules during a shift:**
  - **Open caves:** a **decently large stability bubble** around the player stays the same (you're never crushed or teleported mid-step). It should be **pretty big** — enough room to feel safe — while **everything beyond it can be very different** afterward.
  - **Dungeons:** the **entire dungeon stays the same** once you're in it. Dungeons don't reshuffle around the player — only the open/cave portions do.
- **The shift itself happens off-screen.** Walls and rooms re-form out of the player's view (beyond the stability bubble), so the player never watches geometry pop in around them. The **exception:** if the player is **looking at a cave entrance** when a shift hits, that **entrance visibly caves in** in front of them — a dramatic, on-screen collapse that signals the world just rearranged.
- **Trapped? You're never permanently sealed in.** If a shift would leave the player boxed in, the cave **reopens an exit somewhere else** — but the player has to **explore and find the new way out**. Getting "lost" is the intended tension, not a dead end.
- This turns open caves into ever-changing labyrinths: re-entering one is a fresh run, and lingering too long means re-learning the route out — while dungeons remain a stable, fully explorable space.

## Living World
The world should feel **expansive and alive**, not a static enemy gallery:
- **Factions & rivalries** — goblinoids, undead, beasts, and humans have their own turf and can fight *each other*, not just the player.
- **Ecology & food chain** — predators hunt prey; smarter monsters dominate dumber ones; the player is one more actor in it.
- **Ore economy in the wild** — monsters wander, scavenge ore, hoard or smelt it, and arm themselves; clearing a smart warband can mean better loot.
- **Roaming & migration** — patrols, nomadic packs, and the "occasional" rare spawn (lich, dragon) that reshapes a region while present.
- **Biomes** — distinct regions with their own creatures, materials, and hazards, encouraging the player to travel and re-gear (see World & Biomes).
- **A shifting map** — procedurally generated caves and dungeons open over time, so even explored regions hold new danger.
- **Day/night & danger cycles** — undead and predators bolder at night; some enemies only appear under certain conditions.
- **Reactive world** — camps rebuild, hoards refill, territory shifts over time so the world keeps living after you pass through.

### Camps, escalation & raids
Humanoid creatures (goblins, orcs, bandits, gnolls, etc.) actively **build and grow in the world**, creating a standing threat the player is meant to manage:
- **When camps spawn.** A *new* camp only spawns **overnight, near the player** — and that spawn triggers the **"Enemies Are Near"** title (see On-Screen Titles). This is the only way a fresh camp appears around you.
- **Pre-existing camps in the world.** The player can also **stumble across camps** that already exist out in the world. These are **dormant** by default: they **won't grow or raid** unless the player **sleeps nearby or spends a lot of time near them** — proximity/time is what "wakes" a camp and starts its growth clock.
- **Camps grow when active.** Once active, **left unchecked a camp grows** — more tents, more defenders, more strength over time.
- **Smarter creatures recruit.** Intelligent leaders (goblin warlords, hobgoblin captains, etc.) **recruit other creatures** to join their camp/raid — pulling in beasts, lesser humanoids, and mercenary monsters to make the warband bigger and more dangerous.
- **Escalation to a raid.** A camp that grows large enough **launches a raid on the nearest village or city.** The bigger and better-recruited the camp, the stronger the raid.
- **If the raid succeeds (unlikely):** the attackers **take over the settlement**, and the player must **clear the entire city of their kind** to reclaim it — a much harder undertaking than stopping the camp early.
- **Player agency:** the intended loop is *scout → decide → strike*. Wipe a camp early for an easy job, or ignore it and risk a defended city later. This makes the world feel like it has its own momentum that the player chooses when to interrupt.

## Survival Layer
- Open-world survival systems (to be defined — e.g. health/healing, resources, hunger/exposure, day-night danger). Keep minimal at first.

## Build Order (locked)
**Philosophy:** build a *playable game* first, bit by bit. Only once the core plays well do we add the systems that make it "more than a game" (the living world), then progression, then the final art + customization pass.

1. First-person movement + camera, HP & stamina bars, and a dash system, in a small forest test world. *(In progress.)*
2. Combat core: left-click attack loop from an equipped style, right-click block/dodge by build, Ctrl dash, stamina.
3. One enemy (e.g. skeleton) with a fixed stat sheet, chase AI, dying animation + wither-to-dust.
4. Weapons: one per type/weight with base styles; menu style-equip.
5. Sword depth: style points, per-sword evolution bar, durability; material/element effects; rarer-sword unique styles + sword upgrades that add swings.
6. NPC types and passive mobs.
7. Nature (grass/trees) + reusable buildings (castle → townhouse set).
8. Expand enemy roster and a real explorable world chunk; basic survival.
9. **Living world** — procedural caves/dungeons, shifting caves, camps/raids, random world events. (The "more than a game" layer.)
10. **Leveling & progression** — XP, level-up, assign D&D stat points, long-term scaling so progression feels good.
11. **Character customization + final art pass** — realistic textures and actors swapped in for placeholders (no need for these until here).

## Before We Code — Please Clarify
A prioritized list to settle before the first coding loop. **Tier 1** items block the vertical slice; **Tier 2** can be decided as we build; **Tier 3** is later polish.

**Already decided:** Godot engine • low-poly-but-realistic, vibrant dark-fantasy art (Elden Ring × Ghost of Tsushima, lower poly) • no Z/X/C — styles set in menu, one loop per style • styles come from swords, grown by use + sword upgrades • per-sword evolution bar + slow durability • elements locked to weapon material + level • level-up assigns D&D stat points • character customization deferred (fixed playable character for now) • v1 must include a playable character, enemies, one weapon per type/weight, a couple NPC types, passive mobs, nature (grass/trees), and reusable buildings (castle → townhouse, ~5 reused well).

### Tier 1 — needed to start the vertical slice
1. **Assets: build or source?** Even low-poly needs models, rigs, and animations. Options:
   - **AI-generated assets — yes, viable.** AI tools can generate textures, concept art, skyboxes, and increasingly **3D meshes** (e.g. text/image-to-3D), which suits a stylized low-poly look well. **Caveats:** quality is uneven, **rigging and clean animation** (especially humanoid combat) still usually need manual work or mocap libraries, topology can be messy, and licensing/consistency must be checked. Best used **with** free/paid base packs rather than as the sole pipeline.
   - **Free/paid asset packs** — fastest path to a consistent look for v1.
   - **Hand-made** — full control, highest time cost.
   - *Recommended for v1:* asset packs for characters/animations + AI-generated for textures, props, and environment dressing, refined as we go.
2. **Attack/animation model.** Real swing animations with hitboxes (timing-based) vs. simpler hit detection to start.
3. **First sword + its base style.** Pick the one weapon/style for the slice (e.g. a mid-weight longsword with a 3-hit loop) and what its loop looks like.
4. **Stat list, locked.** Confirm the core stats (proposed: Vitality, Dexterity, Strength, Endurance, Perception, Will) and each one's effect.
5. **Leveling math, rough.** XP source (kills? exploration? both?) and points per level; plus rough style-point and evolution rates.
6. **Single-player only?** Confirming no multiplayer keeps scope sane.

### Tier 2 — decide during early development
7. **How styles "fit" a sword/stats** — exact rules for when an equipped style is effective vs. penalized (material match + stat thresholds).
8. **Bow/thrown input** — own button, or swap into the left-click slot?
9. **Element-per-material table** — which material grants which element, and the level scaling curve.
10. **Smithing access** — craft anywhere, at a home base, or only at world forges? Can the player smelt ore into ingots?
11. **Biome → ore + creature table** — finalize what spawns where (we have the gradient; needs exact lists).
12. **Cave/dungeon generation rules** — stability-bubble radius, shift frequency, dungeon size ranges.
13. **Camp/raid tuning** — growth speed, raid trigger threshold, how raids are warned/shown.
14. **Keep or fold the Core/Body tree** into stats?

### Tier 3 — later polish / content
15. **Character creator depth** — how Skyrim-deep when we return to it.
16. **Survival systems scope** — hunger/exposure/rest, or keep to health + healing at first.
17. **Save system & long-term progression** — how endless leveling stays meaningful (scaling, prestige, etc.).
18. **Story/quests** — narrative spine or pure sandbox at first?
19. **Full weapon roster timing** — which weapons beyond the first exist in v1 vs. later.
20. **Audio/music direction** — dark fantasy ambience, combat sound design.
