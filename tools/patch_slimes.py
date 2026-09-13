#!/usr/bin/env python3
"""Wire the slimes (scripts/Slime.gd + Slime*.gd, Afflictions.gd,
SlimeDirector.gd) into the game. Idempotent: every edit is anchored on
text that exists exactly once and is skipped if its marker is already
there. Run from the repo root:

    python3 tools/patch_slimes.py

Touches: scripts/Player.gd (M menu SLIMES grid, bestiary rows + flavour,
status_speed_mult), scripts/HitFX.gd (goo splat for the "slime" family),
scripts/CaveRegion.gd (slime pockets in the galleries), scripts/World.gd
(the SlimeDirector after the Warbands). Player.gd / World.gd are edited by
other sessions too — this patcher only ever touches its own anchors.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
changed = []


def edit(path, anchor, replacement, marker, count=1):
    p = ROOT / path
    src = p.read_text()
    if marker in src:
        print(f"  = {path}: already has {marker!r}")
        return
    n = src.count(anchor)
    if n != count:
        sys.exit(f"!! {path}: anchor found {n}x (want {count}):\n{anchor}")
    src = src.replace(anchor, replacement)
    p.write_text(src)
    changed.append(path)
    print(f"  + {path}: {marker}")


# ---------------------------------------------------------------- Player.gd
# 1. the bestiary knows the nine colours (kills are keyed by display_name)
edit("scripts/Player.gd",
     '\t\t["Orc", Orc], ["Ogre", Ogre], ["Dark Knight", DarkKnight], ["Horse", Horse],\n\t]\n',
     '\t\t["Orc", Orc], ["Ogre", Ogre], ["Dark Knight", DarkKnight], ["Horse", Horse],\n'
     '\t] + _slime_types()\n',
     "] + _slime_types()")

# 2. the M menu gets its own SLIMES heading under MOBS
edit("scripts/Player.gd",
     '\t_menu_head(vb, "MOBS")\n'
     '\tvar mob_grid := _menu_grid(vb)\n'
     '\tfor entry: Array in _spawn_types():\n'
     '\t\t_menu_btn(mob_grid, String(entry[0])).pressed.connect(_spawn_mob.bind(entry[1]))\n',
     '\t_menu_head(vb, "MOBS")\n'
     '\tvar mob_grid := _menu_grid(vb)\n'
     '\tfor entry: Array in _spawn_types():\n'
     '\t\t_menu_btn(mob_grid, String(entry[0])).pressed.connect(_spawn_mob.bind(entry[1]))\n'
     '\n'
     '\t## The jellies (scripts/Slime.gd): nine colours, one row each.\n'
     '\t_menu_head(vb, "SLIMES")\n'
     '\tvar slime_grid := _menu_grid(vb)\n'
     '\tfor entry: Array in _slime_types():\n'
     '\t\t_menu_btn(slime_grid, String(entry[0])).pressed.connect(_spawn_mob.bind(entry[1]))\n',
     '_menu_head(vb, "SLIMES")')

# 3. the list itself, next to _spawn_types
edit("scripts/Player.gd",
     'func _build_spawn_menu() -> void:\n',
     'func _slime_types() -> Array:\n'
     '\t## The slimes, in Slime.ORDER (scripts/Slime.gd) — one class per colour\n'
     '\t## because the menu and the bestiary both spawn by `cls.new()`.\n'
     '\treturn [\n'
     '\t\t["Green Slime", SlimeGreen], ["Blue Slime", SlimeBlue], ["Ember Slime", SlimeRed],\n'
     '\t\t["Jolt Slime", SlimeYellow], ["Venom Slime", SlimePurple], ["Tar Slime", SlimeBlack],\n'
     '\t\t["Rime Slime", SlimeWhite], ["Gilt Slime", SlimeGold], ["Leech Slime", SlimePink],\n'
     '\t]\n'
     '\n'
     '\n'
     'func _build_spawn_menu() -> void:\n',
     "func _slime_types() -> Array:")

# 4. bestiary flavour falls back to the colour's own line
edit("scripts/Player.gd",
     '\t_detail_label(String(MOB_FLAVOR.get(nm, "")), 14, Color(1, 1, 1, 0.65))\n',
     '\t_detail_label(String(MOB_FLAVOR.get(nm, Slime.flavor_of(nm))), 14, Color(1, 1, 1, 0.65))\n',
     "Slime.flavor_of(nm)")

# 5. the slows: Afflictions.gd writes this, the walk speed reads it
edit("scripts/Player.gd",
     'var hitstun_timer := 0.0     ## thrown out of your action when hit (unblocked)\n',
     'var hitstun_timer := 0.0     ## thrown out of your action when hit (unblocked)\n'
     'var status_speed_mult := 1.0 ## Afflictions.gd: gummed / chilled — a slime left it on you\n',
     "var status_speed_mult")
edit("scripts/Player.gd",
     '\tif overweight:\n'
     '\t\tspeed *= 0.5  ## TODO(design): overburdened — flat 50% slowdown + no sprint for now\n',
     '\tif overweight:\n'
     '\t\tspeed *= 0.5  ## TODO(design): overburdened — flat 50% slowdown + no sprint for now\n'
     '\tspeed *= status_speed_mult   ## tar gum, rime chill (Afflictions.gd)\n',
     "speed *= status_speed_mult")

# ----------------------------------------------------------------- HitFX.gd
# a slime bleeds goo in its own colour, not blood
edit("scripts/HitFX.gd",
     '\tif "undead" in fams or "skeleton" in fams:\n'
     '\t\treturn "bone"\n'
     '\treturn "flesh"\n',
     '\tif "undead" in fams or "skeleton" in fams:\n'
     '\t\treturn "bone"\n'
     '\tif "slime" in fams:\n'
     '\t\t## goo, in the jelly\'s own colour — carried in the kind string so the\n'
     '\t\t## one-door for_creature() below can pour the right colour\n'
     '\t\tvar gc: Color = body.get("goo_color") if "goo_color" in body else Color(0.4, 0.9, 0.3)\n'
     '\t\treturn "slime:" + gc.to_html(false)\n'
     '\treturn "flesh"\n',
     '"slime:" + gc.to_html(false)')
edit("scripts/HitFX.gd",
     '\tmatch kind:\n'
     '\t\t"armour":\n'
     '\t\t\treturn armour(at, dir, power)\n'
     '\t\t"bone":\n'
     '\t\t\treturn bone(at, dir, power)\n'
     '\t\t_:\n'
     '\t\t\treturn flesh(at, dir, power)\n',
     '\tif kind.begins_with("slime"):\n'
     '\t\tvar col := Color(0.4, 0.9, 0.3)\n'
     '\t\tif kind.length() > 6:\n'
     '\t\t\tcol = Color.html(kind.substr(6))\n'
     '\t\treturn goo(at, dir, col, power)\n'
     '\tmatch kind:\n'
     '\t\t"armour":\n'
     '\t\t\treturn armour(at, dir, power)\n'
     '\t\t"bone":\n'
     '\t\t\treturn bone(at, dir, power)\n'
     '\t\t_:\n'
     '\t\t\treturn flesh(at, dir, power)\n',
     'return goo(at, dir, col, power)')
edit("scripts/HitFX.gd",
     '## ============================== Plumbing ==================================\n',
     'static func goo(at: Vector3, dir: Vector3, col: Color, power := 1.0) -> HitFX:\n'
     '\t## SLIME: a wet burst of jelly in the creature\'s own colour — fat slow\n'
     '\t## gobbets that fall and a fine faintly-lit spray that hangs a moment.\n'
     '\t## (scripts/Slime.gd uses it for landings and the death splat too.)\n'
     '\tvar fx := _root(at, 1.1)\n'
     '\tvar d := _safe(dir)\n'
     '\tvar dim := Color(col.r * 0.55, col.g * 0.55, col.b * 0.55, 1.0)\n'
     '\tfx.add_child(_cubes(int(10 * power), 0.075, 0.75, d, 55.0, 2.0, 4.5, 11.0,\n'
     '\t\t_ramp(col, dim, Color(dim.r, dim.g, dim.b, 0.0))))\n'
     '\tfx.add_child(_cubes(int(18 * power), 0.030, 0.55, d, 80.0, 3.0, 6.5, 7.0,\n'
     '\t\t_ramp(Color(col.r, col.g, col.b, 0.95), Color(col.r, col.g, col.b, 0.6), Color(col.r, col.g, col.b, 0.0)),\n'
     '\t\ttrue, col))\n'
     '\treturn fx\n'
     '\n'
     '\n'
     '## ============================== Plumbing ==================================\n',
     "static func goo(")

# ----------------------------------------------------------- CaveRegion.gd
# slime pockets: the shallow galleries get the green and the jolt, the
# middle gets the venom, the deeps get the ember and the tar
edit("scripts/CaveRegion.gd",
     '\t\tvar roll := _rng.randf()\n'
     '\t\tif c.y > -12.0:\n'
     '\t\t\tif roll < 0.6:\n'
     '\t\t\t\t_spawn_pack(c, Kobold, _rng.randi_range(6, 10))\n'
     '\t\t\telse:\n'
     '\t\t\t\t_spawn_pack(c, Goblin, _rng.randi_range(3, 6))\n'
     '\t\telif c.y > -21.0:\n'
     '\t\t\tif roll < 0.4:\n'
     '\t\t\t\t_spawn_pack(c, Goblin, _rng.randi_range(3, 6))\n'
     '\t\t\telif roll < 0.8:\n'
     '\t\t\t\t_spawn_pack(c, Skeleton, _rng.randi_range(4, 7))\n'
     '\t\t\telse:\n'
     '\t\t\t\t_spawn_pack(c, Ogre, _rng.randi_range(1, 2))\n'
     '\t\telse:\n'
     '\t\t\tif roll < 0.4:\n'
     '\t\t\t\t_spawn_pack(c, Skeleton, _rng.randi_range(4, 7))\n'
     '\t\t\telif roll < 0.75:\n'
     '\t\t\t\t_spawn_pack(c, Orc, _rng.randi_range(2, 4))\n'
     '\t\t\telse:\n'
     '\t\t\t\t_spawn_pack(c, Ogre, _rng.randi_range(1, 2))\n',
     '\t\tvar roll := _rng.randf()\n'
     '\t\tif c.y > -12.0:\n'
     '\t\t\tif roll < 0.45:\n'
     '\t\t\t\t_spawn_pack(c, Kobold, _rng.randi_range(6, 10))\n'
     '\t\t\telif roll < 0.72:\n'
     '\t\t\t\t_spawn_pack(c, Goblin, _rng.randi_range(3, 6))\n'
     '\t\t\telse:\n'
     '\t\t\t\t## [slimes] the shallow jellies: a green pocket, sometimes with\n'
     '\t\t\t\t## a jolt or two skittering among them\n'
     '\t\t\t\t_spawn_pack(c, SlimeGreen, _rng.randi_range(3, 5))\n'
     '\t\t\t\tif _rng.randf() < 0.5:\n'
     '\t\t\t\t\t_spawn_pack(c, SlimeYellow, _rng.randi_range(1, 2))\n'
     '\t\telif c.y > -21.0:\n'
     '\t\t\tif roll < 0.35:\n'
     '\t\t\t\t_spawn_pack(c, Goblin, _rng.randi_range(3, 6))\n'
     '\t\t\telif roll < 0.70:\n'
     '\t\t\t\t_spawn_pack(c, Skeleton, _rng.randi_range(4, 7))\n'
     '\t\t\telif roll < 0.85:\n'
     '\t\t\t\t_spawn_pack(c, Ogre, _rng.randi_range(1, 2))\n'
     '\t\t\telse:\n'
     '\t\t\t\t## [slimes] the venom creeps in the middle galleries\n'
     '\t\t\t\t_spawn_pack(c, SlimePurple, _rng.randi_range(2, 3))\n'
     '\t\telse:\n'
     '\t\t\tif roll < 0.35:\n'
     '\t\t\t\t_spawn_pack(c, Skeleton, _rng.randi_range(4, 7))\n'
     '\t\t\telif roll < 0.65:\n'
     '\t\t\t\t_spawn_pack(c, Orc, _rng.randi_range(2, 4))\n'
     '\t\t\telif roll < 0.85:\n'
     '\t\t\t\t_spawn_pack(c, Ogre, _rng.randi_range(1, 2))\n'
     '\t\t\telse:\n'
     '\t\t\t\t## [slimes] the deeps burn ember — and one tar sits in the dark\n'
     '\t\t\t\t_spawn_pack(c, SlimeRed, _rng.randi_range(2, 4))\n'
     '\t\t\t\tif _rng.randf() < 0.5:\n'
     '\t\t\t\t\t_spawn_pack(c, SlimeBlack, 1)\n',
     "_spawn_pack(c, SlimeGreen")

# ---------------------------------------------------------------- World.gd
edit("scripts/World.gd",
     'var _warbands: Warbands              ## [warbands] and who holds the ground it happens on\n',
     'var _warbands: Warbands              ## [warbands] and who holds the ground it happens on\n'
     'var _slimes: SlimeDirector           ## [slimes] the jellies on the surface (scripts/SlimeDirector.gd)\n',
     "var _slimes: SlimeDirector")
edit("scripts/World.gd",
     '\t_warbands = Warbands.new()\n'
     '\t_warbands.name = "Warbands"\n'
     '\tadd_child(_warbands)\n'
     '\t_warbands.bind_world(self)\n',
     '\t_warbands = Warbands.new()\n'
     '\t_warbands.name = "Warbands"\n'
     '\tadd_child(_warbands)\n'
     '\t_warbands.bind_world(self)\n'
     '\t## [slimes] the surface jellies, after the warbands: it reads the same\n'
     '\t## player and clock, and owns its own budget (SlimeDirector.USE_SLIMES).\n'
     '\t_slimes = SlimeDirector.new()\n'
     '\t_slimes.name = "SlimeDirector"\n'
     '\tadd_child(_slimes)\n'
     '\t_slimes.bind_world(self)\n',
     "_slimes = SlimeDirector.new()")
edit("scripts/World.gd",
     'func wildlife_census() -> Dictionary:\n',
     'func slimes() -> SlimeDirector:\n'
     '\t## [slimes] the surface jellies\' director (tests, the debug menu)\n'
     '\treturn _slimes\n'
     '\n'
     '\n'
     'func wildlife_census() -> Dictionary:\n',
     "func slimes() -> SlimeDirector:")

print("changed:", changed or "nothing")
