# Build Roadmap — The Withering

Build a *playable game* first, then the living world, then progression, then the
final art + customization pass. Each step should leave the game runnable.

Status keys: [x] done · [~] in progress · [ ] not started

## Step 1 — First-person movement [x]
- [x] FP camera + mouse look, WASD, sprint, jump
- [x] Stamina pool + regen

## Step 2 — Combat core [~]
- [x] Left-click attack loop (3-hit, finisher bonus)
- [x] Right-click block (light) / dodge (heavy)
- [x] Ctrl dash (light build)
- [x] Guard-break: strong attacks smash through a raised block (2s disable + knockback)
- [~] Hit feedback: camera shake in (guard break / heavy hits); hitstop + sound hooks still to do
- [~] Stamina-break on guard still to do; parry window DONE (block within 0.18s of
      impact = no damage/stamina, attacker staggers open, beats guard-breakers)

## Step 3 — First enemy [x]
- [x] Chase AI + melee attack
- [x] Fixed stat sheet (health/damage/speed)
- [x] Wither-to-dust death
- [x] Telegraphed attacks the player can block/dodge (every mob has a glowing windup)
- [x] Multiple enemy archetypes (skeleton, goblin, kobold — plus the boar)
- [x] Two specials per humanoid (smash/sweep, pounce/flurry, lunge/tail-spin)
- [x] Procedural attack animations (arm swings, crouches, spins; melee lands mid-swing)
- [x] Realistic 3-phase cuts (chamber → whip → follow-through) on the player's
      combo + draw slash and all sword mobs; damage lands at the visual impact.
      Per-mob throw power (boar shove 5 → ogre hurl 8.5); blocking = never thrown

## Step 4 — Weapons [~]
- [~] One weapon per type/weight (sword, axe, hammer, knife, bow, etc.) —
      BOW DONE: 1/2 weapon select, hold-to-draw/release-to-loose, arrow
      projectiles with drop, terrain-stuck arrows retrievable, ammo in inventory
- [ ] Base attack loop ("style") per weapon type/weight
- [ ] Menu to equip a style; equipped style drives the left-click loop

## Step 5 — Sword depth [~]
- [ ] Style points earned by use → upgrade styles
- [ ] Per-sword evolution bar (levels the individual weapon)
- [ ] Durability (slow drain, maintenance loop)
- [~] Material → element effects — FIRST PASS DONE (see docs/MATERIALS.md):
      all 10 materials in Materials.gd, matchup × element damage vs enemy
      family tags, aura glow on elemental blades, main-hand slot + click-to-
      wield, Armory dev menu on I, rare tier-weighted v1-slice mob drops
      (iron/steel/silver/meteoric). Element scaling awaits the evolution bar.
      SOURCING NOW LIVE: pickaxe (weapon 3) + mineable ore veins in the caves
      (silver seams anywhere, meteoric guards the deepest room); first ore of
      a new metal forges its sword on the spot, spares stack for smithing later
- [ ] Rarer swords carry unique styles; upgrading the sword adds new swings

## Step 6 — NPCs & passive mobs [~]
- [ ] A couple of NPC types
- [~] Passive wildlife — HORSES DONE (wild + saddled): wild herds graze far out
      and bolt on approach, never rideable; saddled horses near spawn are
      mountable (F) — camera-steered reins, Shift gallop, Space jump, sword-only
      saddle sweeps (left/right by where you look, alternating ahead).
      Hurt ANY horse once and it retaliates: wheels and KICKS you into a
      knockdown (fall + get-up, fully vulnerable, no i-frames — enemies keep
      swinging) and that horse never carries you again. Your own swings can
      never hit the horse you're riding; a horse dying under you still bucks
      you into the same knockdown. More wildlife later

## Step 7 — Nature & buildings [ ]
- [ ] Grass / trees (low-poly)
- [ ] Reusable building set (castle → townhouse, ~5 reused)

## Step 8 — World & survival basics [ ]
- [ ] A real explorable world chunk (plains/forest/mountain test region)
- [ ] Basic survival (health/healing; more later)

## Step 9 — Living world ("more than a game") [~]
- [~] Procedural caves + dungeons — caves DONE (seeded chamber networks, round
      natural swept tunnels that flare into domed caverns, crystal lighting, cave
      dwellers); dungeons next
- [ ] Shifting caves (regenerate, stronger shake inside, off-screen rebuild)
- [ ] Camps that grow → raid villages/cities
- [~] Random world events + titles — first pass: "The Hollow Depths / The Dusk
      Forest" fade in when entering/leaving the caves; Daybreak/Nightfall sky
      banners now ride the day/night clock (surface only)
- [x] Day/night cycle — DayNight.gd: full Skyrim-pace 20-min game day (72×),
      sun + moon on one wheel, keyframed sky/fog/ambient around the clock
      (17:30 = the original signature dusk), dark frost-blue nights where the
      torch really matters, caves ignore the sky entirely. Starts at 17:00.
      Danger cycles (bolder undead at night) still to come — is_night() is ready

## Step 10 — Leveling & progression [~]
- [x] XP + level-up to cap 99, 3 stat points per level, banked until spent.
      Curve retuned SLOW on request (~24 weak kills for level 2, ~5.2M XP total
      to 99). Orb XP re-trimmed AGAIN: every current mob drops GREEN essence
      (orb_tier 0, 2 XP/orb; yellow→purple saved for real elites, scaling
      slowly at 3/4/5), stronger kinds just drop MORE greens (3/5/7/9 orbs
      by xp_tier) — levels are earned
- [x] Five stats (CON/DEX/STR/WIS/CHA, base 5, cap 99) with diminishing-returns
      formulas driving HP/stamina pools + bar width, stamina costs/regen, move +
      attack speed, damage, damage taken, carry limit, XP gain, gold found
- [x] Progression trees ("grow what you use"): hidden achievement tiers that pay
      escalating points into their linked stat — Death's Door (near-death
      recoveries), Marathoner (distance), Untouchable (i-frame dodges),
      Combo Master (finishers), Perfect Guard (parries), Slayer (kills),
      Essence Drinker (XP orbs); Silver Tongue locked until NPCs.
      Endless: past the authored tiers, thresholds keep scaling per completion
- [x] Tab menu: Inventory | Stats | Progression — Cyberpunk-style stat sheet with
      hover tooltips (live before→after numbers) + achievement page with hidden tiers
- [ ] WIS gates sword tiers / sword arts (comes with steps 4–5)
- [ ] CHA grows through conversation (needs NPCs, step 6)
- [ ] Save/persistence so a level survives quitting (currently resets per run)
- [ ] Long-term scaling pass once higher-tier XP sources exist

## Step 11 — Customization & final art [ ]
- [ ] Skyrim-style character creator
- [ ] Realistic textures + actors replace placeholders

---

## Systems added along the way
- [x] Settings menu (Esc, saved to user://settings.cfg): "Ray-Traced Lighting"
      preset — SDFGI real-time GI + SSIL/SSAO/SSR + volumetric light shafts +
      glow, with flat ambient scaled back so bounce light leads (World.gd
      set_rt_lighting); shadow quality tiers; fullscreen/VSync/sensitivity/FOV.
      All live-applied. (Godot has no hardware RT — SDFGI is its ray-marched GI)
- [x] Ground pickups: coins/XP scatter and fall on death; walk over them and they fly to you
- [x] Dev mob-spawn menu (M) — spawns any mob ~10 ft ahead (confused until hit)
- [x] Inventory (I / Tab): item list, carry-weight limit (overweight = slowed, no sprint),
      armor slots (helmet/chest/arms/pants/shoes) + shield offhand slot
- [x] Offhand items: shield + torch owned from the start; Q cycles owned items only;
      equip raise/lower animation, shield block-raise, torch casts real flickering light
- [x] Grassy entrance hills over the cave mouths; branchier cave networks with loops
      and a guaranteed 3-way junction
- [x] Armory (dev) column on the I inventory page — grab any material sword;
      swords are inventory items on a "Main Hand" slot, click to wield
- [x] Bestiary (Tab page 4): all mobs listed, each row ??? until first kill;
      per-material weakness cells stay ??? until you land that metal on that
      creature (learn-by-doing "prove the matchup" discovery, with log toasts).
- [x] Material ARMOR SETS: all 10 metals as 5-piece kits (helmet/chestplate/
      bracers/greaves/boots) via the Armory's Armor button; each worn piece
      shaves 2/3/4/5% damage by tier (set: 10→25%, cap 40%); piece weight rides
      the metal (mithril kit light, adamant kit brutal); worn pieces TINT the
      visible body + viewmodel forearm. Helmets stats-only (no head mesh)
- [x] Drop & reclaim: Q over an inventory row tosses ONE of that item out in
      front of you (DroppedItem.gd — arcs, lands, lies there; NO magnet);
      look at it + E picks it back up ("[E] Pick up" prompt). Last-sword drop
      blocked (main hand never empty); equipment indices remap on removal
      Kills now counted centrally in Enemy._die → Player.on_mob_slain, so bow
      and pickaxe kills feed the Slayer tree too (they didn't before)
- [x] Mining: Iron Pickaxe in the starting pack (weapon 3), chop animation with
      impact-timed bite; OreVein.gd rocks (4 hits, seam flash + chips + shake)
      burst into ore pickups; Cave.gd seeds silver veins through rooms and
      meteoric in the deepest; first ore of a metal auto-forges that sword

---

## Notes for automated build runs
- Keep the game runnable after every change; prefer code-built nodes over fragile
  scene wiring where practical.
- Match the design doc (`docs/DESIGN.md`). When a decision is ambiguous, leave a
  `TODO(design):` comment rather than guessing a core direction.
- Update this file's checkboxes as work completes.
