# CONTEXT.md — Read Me First (for every chat)

> **The Withering** — first-person dark fantasy open-world survival RPG in **Godot 4.4**.
> Skill-based melee, no spellcasting (magic = items/materials only), gear that grows with you,
> enemies wither to dust. Art: gritty-realism low-poly, slate/indigo base + ember/frost accents.
> Everything is placeholder primitives until step 11. Last updated: 2026-07-14.

**Doc map:** `docs/DESIGN.md` = full design bible · `docs/ROADMAP.md` = build order + live checkboxes (keep updated!) · `docs/MATERIALS.md` = metals/matchups · `docs/TREES_PLAN.md` = Blender tree pipeline · `docs/CAVES_PLAN.md` = Caves 2.0 redo (SDF + marching cubes) · `README.md` = controls + slice summary · this file = quick orientation.

**Rules of the road:** game must stay runnable after every change · world is built in code (scenes are thin shells — `World.tscn` is the only scene) · ambiguous design call → `TODO(design):` comment, don't guess · update ROADMAP checkboxes + README as work lands.

---

## ✅ COMPLETED SYSTEMS (what already works)

**Player core — `Player.gd` (2500 lines: controller + combat + HUD + all menus)**
- FP movement with momentum: WASD, sprint, jump, auto step-up, Ctrl dash (stamina + i-frames), **Space mantle-climb** (`_try_climb`/`_update_climb`: grabbable ledge ≤2.65 m beats jumping — rise-then-haul animation, hands plant, camera dips; works mid-air; 8 stamina; cancelled by knockdown). **Bump absorber** (`_eye_smooth` in `_apply_step_smooth`): small grounded body hops on lumpy voxel rock reach the eye as an eased glide — feet bump, view floats.
- Visible first-person body (torso/legs/hands), swinging-arm walk cycle, Alt sheathe/unsheathe to hip scabbard + draw-slash. Shield sheathes WITH the sword (stows across the back, `back_shield`); raising a block auto-draws.
- **The Hunch** (`_update_hunch`, settings toggle, default on): blade+shield auto-draw the instant any hostile turns AGITATED at you (edge-triggered so Alt can defy it; horses excluded — their agitation is flight), auto-sheathe after 6.7 quiet seconds (`HUNCH_SHEATHE_AFTER`).
- Stamina + health pools, very slow out-of-combat regen, respawn with i-frames.

**Combat — in `Player.gd`, telegraphs in `Enemy.gd`**
- LMB 1-2-3 combo (finisher bonus, ~0.75s reset) with realistic 3-phase cuts (chamber → whip → follow-through); damage lands at visual impact.
- RMB block: shield = full negate, bare sword = half. Enemy strong attacks guard-break (2s block disable + knockback + camera shake).
- **Parry**: block raised ≤0.18s before impact = no damage/stamina, attacker staggers, beats guard-breakers (`PARRY_WINDOW`).
- No ghost hits: attacks both ways need line-of-sight + shared height band.

**Weapons (1/2/3/4 select)**
- **1 Sword** — the combo loop above; material-driven (see below).
- **2 Bow** — hold-to-draw (damage/speed ride the draw, DEX quickens, STR powers), real arrow projectiles with drop (`Arrow.gd`), missed arrows stick in terrain and are retrievable, 20-arrow ammo in inventory.
- **3 Iron Pickaxe** — chop with impact-timed bite; mines ore veins AND digs cave rock (Caves 2.0). Swords can't mine.
- **4 War Axe** — heavy one-handed cleaver (`_try_axe_swing`/`_update_axe`/`_do_axe_hit`): ×1.35 base damage, slower, no combo ladder — two ALTERNATING authored swings (overhead chop / horizontal cleave), impact-timed damage, hits everything in the arc, LOS-checked. No material matchups yet (TODO: fold into metal system at step 4/5). Can't block with it; offhand shield/torch stay up.
- **Fall damage** (`_apply_fall_damage`, fires on touchdown in `_update_gait`): safe to ~6 m (11 m/s), then 6.5 dmg per m/s over; ≥17.5 m/s also folds you into the knockdown; lethal falls kill. Bypasses block/i-frames; mantling mid-air zeroes fall speed (the grab saves you).

**Enemies — `Enemy.gd` base (819 lines) + per-mob subclasses**
- Shared AI: calm-wander → agitated, circle/orbit then dart in, telegraphed glowing windups, flinch, caught-mid-attack retreat, white-flash triangle-shatter wither death, far-off mobs sleep (CPU).
- Roster (ascending): **Kobold** (lunge/tail-spin) < **Goblin** (pounce/flurry) < **Skeleton** (smash/sweep) < **Orc** (charge/thrust/slash) / **Ogre** (bite/throw/charge) < **DarkKnight** (shield-bash/dark-combo), plus neutral **Boar** (big-arc circling charge). Two specials per humanoid; per-mob throw power (boar 5 → ogre 8.5); blocking = never thrown.
- Boars roam the overworld; everything else spawns in cave packs (kobold 6-10, goblin 3-6, skeleton 4-7, orcs/ogres deeper, champion room = dark knight leading orcs).
- Central kill accounting: `Enemy._die → Player.on_mob_slain` (so bow/pickaxe kills count everywhere).

**Loot & pickups — `Pickup.gd`**
- Death bursts tier-colored XP orbs (green→purple, 2/5/8/11 XP) + gold coins; they scatter, fall, rest, magnet to you on walk-over. Loot rules: beasts = XP only; undead = no coins.

**Stats & leveling — `Stats.gd`**
- XP → level cap 99, 3 banked points/level, deliberately SLOW curve (~24 weak kills for lvl 2, ~5.2M total to 99).
- Five stats, base 5 cap 99, diminishing returns: **CON** HP+stamina pools (bars widen) + regen · **DEX** stamina costs/regen, move + swing speed · **STR** damage, damage reduction, carry weight · **WIS** XP gain (sword arts later) · **CHA** gold found (NPCs later).
- **Progression trees** ("grow what you use"): hidden achievement tiers paying points into their stat — Death's Door, Marathoner, Untouchable, Combo Master, Perfect Guard, Slayer, Essence Drinker (+ Silver Tongue locked until NPCs). Endless scaling past authored tiers; anti-farm rules.

**Settings menu — Esc (persisted to `user://settings.cfg`)**
- **Ray-Traced Lighting** toggle = Godot SDFGI preset (`World.set_rt_lighting`): real-time bounced GI + SSIL/SSAO/SSR + volumetric light shafts + glow; flat ambient ×0.55 when on. Godot has no hardware RT — SDFGI is the ray-marched equivalent. Off by default (GPU-heavy).
- Shadows Low/Med/High (atlas 2048/4096/8192 + soft filter), fullscreen, VSync, mouse sensitivity (0.3–2.5×), FOV (60–110), **The Hunch** on/off. All applied live via `Player._apply_settings`.

**Menus (Tab = 4 pages, I = straight to inventory, M = dev mob spawner) — all panels render 67% larger (`MENU_SCALE`, clamped to fit the window)**
- **1 Inventory**: item list, carry-weight limit (overweight = slow, no sprint), 5 armor slots, offhand slot, Main Hand slot (click a sword to wield — blade rebuilds in hand), **Armory (dev)** column conjures any metal.
- **2 Stats**: Cyberpunk-style sheet, hover = live before→after, queue +/− then Confirm.
- **3 Progression**: earned tiers + next-tier live progress bar, rest hidden.
- **4 Bestiary**: every mob ??? until first kill; material weaknesses ??? until you land that metal on that creature ("prove the matchup", green/red cells, log toasts).

**Offhand** — own shield + torch from start; Q cycles owned only: shield → torch → **shield+torch together** (shield straps to the forearm, torch shares the fist; `equipment["offhand2"]` companion slot) → empty. Raise/lower animations, shield lifts while blocking (strapped or not), torch casts real flickering light. Offhand lowers while bow is out (shield slung on back); sheathed = shield on back, torch stays lit.

**Materials — `Materials.gd` (all 10 metals live)**
- bronze/iron/steel (common, no element) · silver-Moonlight, cold_iron-Frost (uncommon) · meteoric-Ember, mithril-Spark, adamant-Quake (rare) · dragonsteel-Dragonfire, voidsteel-Soulfire (endgame).
- Matchup ×1.35/×1.0/×0.8 vs enemy `families` tags (beasts/humanoids/undead/cursed/armored/…); elements add situational +5→25% (scaling awaits evolution bar); elemental blades wear glowing auras. Rare tier-weighted mob drops (v1 slice: iron/steel/silver/meteoric only).

**Mining — `OreVein.gd`**
- 4 pickaxe bites (seam flash/chips/shake) burst veins into ore pickups; silver seams ~half the cave rooms, meteoric guards the deepest. **First ore of a new metal auto-forges that sword** (the unlock moment); spares stack for future smithing.

**World — `World.gd` + `CaveRegion.gd`/`CaveField.gd`/`CaveMesher.gd` + `DayNight.gd`**
- Forest overworld: fog, placeholder cone trees + rocks.
- **Day/night cycle** (`DayNight.gd`): Skyrim-pace — one game day per 20 real min (72×), starts 17:00. Sun + moon on one wheel, keyframed sky/fog/ambient (17:30 = the original signature dusk look), dark frost-blue nights (torch matters). Daybreak/Nightfall titles at 6:00/20:36 (surface only). `is_night()` ready for step 9 danger cycles. World._process lerps toward `surf_ambient`/`surf_fog`; caves override.
- **CAVES 2.0 (roomless, voxel)**: two 64×64×36 m `CaveRegion` blocks, each a `CaveField` density grid (0.8 m voxels, rock=+ air=−) carved by Minecraft-1.18-style noise carvers — **worm tunnels whose radius swells/pinches on its own, cheese caverns below −8, thin fitable cracks** — plus domain warp, a 2.2 m surface roof guard, rim columns forced air (slab overhangs the seam) and an unmineable bottom row. ~40% of systems roll **VAST** (`CaveField.vast`: fatter worms, far bigger/earlier caverns, wider cracks). **Regions are visually seamless with the overworld**: vertex jitter is zero on the open surface away from the entrance (flat grass = identical lighting to the slab; relief only at the entrance zone + underground) and the skin dips 7 cm under the slab's 1.2 m overhang at the rim (`dip` in `_gen_rows`) so the border never shares a plane (no z-fighting). `World.spawn_cave_at(mouth, dir)` tears open a NEW region at runtime (re-tiles the slab, quake + "The World Has Shifted" title) — wired to an M-menu dev button (`Player._spawn_cave`). **Entrance = a SUNKEN THROAT: an open grass-walled ramp cut descending from grade, diving under a low rock CAP (`MOUND_R/H` 5.2/2.5 at `MOUND_FWD`) — only the cap's top breaks the surface; the chain may only cut the surface within `MOUTH_OPEN_R` of the mouth (kills back-side holes).** **DEFERRED DEEP LOADING**: `field.generate(true)` builds only rows above `DEEP_Y=-8` at world build (deep rows = placeholder rock, dwellers/veins/crystals deferred); approaching the mouth triggers `start_deep_generation()` → threaded field rows → threaded chunk remesh → content spawns, all polled non-blocking in `CaveRegion._process` (`_deep_state` 0-3, digging restricted to shallow rows while threads run, player digs preserved via minf) — a Chaikin-smoothed capsule chain (≤30° floor, 1.9 m+ headroom, sim-verified) runs level through the mound then dives to −11.5 m where the noise caves take over; a lit crystal cluster just inside makes the mouth glow at night. `CaveMesher` skins it with chunked (16³) **naive surface nets** — flat normals, vertex jitter, strata vertex colors (grass top skin / slate / frost / ember by depth, sRGB→linear converted to match the slab exactly), trimesh collision per chunk (group `cave_rock`), **two-sided rock material** (sub-voxel walls pinch the net into twisted slivers whose culled backfaces read as see-through cracks — drawing both sides seals them) — all threaded via WorkerThreadPool at build. Content placed by `field.reachable_air()` BFS + `floor_point`: crystals (ember in the deeps), silver veins mid-band, meteoric at the deepest reachable floor, dweller packs by depth with a dark-knight champion at the bottom. **The pickaxe DIGS**: `carve_bite` scoops the field and remeshes dirty chunks — walls, ceilings, dig slowly all the way up to the surface; every bite bursts `RockDebris.gd` falling rocks, and biting a ceiling drops a big slab that deals 10 dmg to whoever stands under it. Old `Cave.gd` (swept tubes + chamber grid) retired but on disk. Underground = thicker fog, killed ambient, location titles ("The Hollow Depths"/"The Dusk Forest") unchanged.

**Horses & riding — `Horse.gd` + `SaddledHorse.gd` (step 6 first pass)**
- Two kinds, one bestiary page: **wild** herds (2×3-4, far tree line) graze/flee — skittish radius 8m, never rideable; **saddled** (2 near spawn) are calm and mountable with **F**.
- Riding: player capsule off, rides `saddle_world()`; camera-relative WASD reins (horse turns like an animal, 2.6 rad/s), Shift gallop 11.0 (player sprint ≈ 8), Space jump. Sword only; LMB = flat saddle sweeps via `MOUNTED_KEYS` — look >0.35 rad left/right picks the side, ahead alternates. No blocking/dash/finishers mounted.
- **Kick + trust**: any player damage to any horse sets `trust_broken` forever (it flees you, never carries you). Within 3.6m it retaliates — wheels rump-first and kicks (14 dmg, `Player.horse_kick`): parry or dash i-frames counter it, anything else = **knockdown** (`kd_phase` fall→down→rise, ~2.2s, camera drops+rolls, zero protection, inputs dead, enemies keep attacking). Your own swings can never hit your mount (excluded in `_do_melee_hit`); the buck-off (`thrown_from_mount`) still fires if a ridden horse is hurt some other way or dies under you. Central to it: `Player._start_knockdown` is reusable for future knockdown sources.

---

## 🔨 IN PROGRESS
- **Caves 2.0** — core is BUILT (see World section above + `docs/CAVES_PLAN.md`): field/mesher/region + digging + falling rocks + content placement, first pass, **needs an in-game walkthrough and noise tuning** (frequencies/radii = the make-or-break iteration). Then: dressing pass (stalactite forests, pools, glowworms, breakdown boulders), squeeze camera-tuck, cavity tagging for titles/archetype dressing, sealed-pocket secrets, perf pass.
- **Hit feedback** (step 2): camera shake done; hitstop + sound hooks TODO. Stamina-break on guard TODO.
- **Weapon styles** (step 4): bow done; base attack loop per weapon type/weight + menu style-equip NOT started.
- **Sword depth** (step 5): materials/matchups/sourcing done; style points, per-sword evolution bar, durability, unique styles on rare swords NOT started.
- **Trees** (Blender MCP pipeline, `tools/treegen.py` → `assets/source/trees.blend`): first full pass was **reverted**; take-2 oak line (5 life stages) awaits user review, then pine/birch/willow one at a time, then GLB export + TreeLife/seed gameplay rewrite. See `docs/TREES_PLAN.md` before touching trees.

## 🗺️ PLANNED (not started — roadmap order)
- **Step 6**: NPC types (unlocks CHA growth + Silver Tongue tree); more passive wildlife (horses are done).
- **Step 7**: grass/real trees, reusable building set (castle → townhouse).
- **Step 8**: real explorable world chunk (plains/forest/mountain), basic survival.
- **Step 9**: dungeons (caves done), **shifting caves** (regenerate on a timer, stability bubble, quake), camps that grow → raid settlements, more world-event titles, night danger cycles (day/night clock itself is DONE).
- **Step 10 leftovers**: WIS-gated sword tiers/arts, save/persistence (currently resets per run), long-term scaling pass.
- **Step 11**: Skyrim-style character creator, real art replacing primitives.
- **Later systems from DESIGN.md**: smithing/ingots, sharpening rocks, durability/dulling, crystals + potions + artifacts, thrown weapons + full weapon roster, factions/ecology/ore-economy living world, biome gradient (lowlands → mountains → snowy peaks = dragons + best metals), day/night danger.

---

## 🔁 HOW IT FITS TOGETHER (the playable loop)
Explore the forest → find a cave mouth → fight telegraphed pack combat (combo/block/parry/dodge, bow for pulls) → kills burst XP orbs + coins (`Pickup.gd` → `Stats.gd`) → level stats + progression trees pay out for *how* you play → bestiary entries + matchups unlock by doing → mine silver/meteoric veins with the pickaxe → first ore forges a new material sword → swap metals per enemy family (silver in the crypt-cave, steel vs the humanoid pack) → push deeper rooms → dark knight champion. Dev shortcuts while building: M spawns mobs, Armory grabs any sword.

Three progression layers by design: **you** (stats/levels) · **your style** (weapon loops — being built) · **your specific sword** (evolution/durability — next up). Difficulty philosophy: hard but fair; power should change *how* you fight, not just numbers.
