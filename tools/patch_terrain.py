#!/usr/bin/env python3
"""
Re-runnable wiring for the overworld: World.gd and Player.gd.

    python3 tools/patch_terrain.py [--repo .] [--dry]

Every hunk is guarded by a marker, so running this twice is a no-op and running
it after someone else's patcher only adds what is missing.

RULE (learned the hard way, twice): World.gd has silently lost work when two
patchers touched it. This script never rewrites a whole function -- it inserts
next to an anchor it can find, and refuses to run if an anchor is missing.
"""

import argparse, os, shutil, sys, time

MARK = "## [terrain]"

WORLD_FLAGS = '''
## --- the overworld --------------------------------------- ## [terrain] flags
## USE_TERRAIN false = the old walled valley, and nothing else changes.
const USE_TERRAIN := true
## The valley's fog is built for a 100 m box. Maine needs to see Katahdin from
## five kilometres away, so the surface fog thins hard when the terrain is on.
const TERRAIN_FOG := 0.0011
const TERRAIN_FAR := 9000.0        ## camera far plane, so the ranges render
## Loaded by PATH, never by class_name. A GDExtension can register a native
## class that shadows any script class_name without a parse-time warning --
## TerraBrush registers a non-instantiable `Terrain` and that is exactly what
## bit us. preload() resolves the file, so nothing can shadow it.
const OverworldScript := preload("res://scripts/Overworld.gd")
var _terrain: Node3D = null        ## the ground, or null when USE_TERRAIN is off
'''

WORLD_BUILD = '''

## [terrain] builder -----------------------------------------------------------
## Build the ground BEFORE _build_border and _spawn_player: the border net and
## the camera's far plane both ask the terrain how big the world is, and the
## player must have something to stand on before it is dropped.
func _build_terrain() -> void:
	if not USE_TERRAIN:
		return
	_terrain = OverworldScript.new()
	_terrain.name = "Terrain"
	add_child(_terrain)
	if not _terrain._loaded:
		## No bake on disk (or *.r16 missing from the export filter). Fall back
		## to the valley rather than dropping the player into nothing.
		push_warning("World: terrain data did not load -- staying in the valley.")
		_terrain.queue_free()
		_terrain = null
		return
	if _env != null:
		_env.fog_density = TERRAIN_FOG


## [terrain] True once the player has left the map entirely. With the terrain
## on this is the map rim; without it, the old +/-103 box.
func _out_of_world(p: Vector3) -> bool:
	if p.y < -60.0:
		return true
	if _terrain != null:
		return not _terrain.pos_in_bounds(p)
	return absf(p.x) > 103.5 or absf(p.z) > 103.5


## [terrain] Where a lost player is put back. The valley, always -- it is the
## one place in the world guaranteed to have ground at y = 0.
func _world_home() -> Vector3:
	return Vector3(0, 2, 0)
'''


# Straight text swaps applied before the marker hunks. Unlike a hunk these are
# self-idempotent -- once the old text is gone they simply never match -- so
# they can repair a file that an EARLIER version of this patcher wrote.
MIGRATIONS = {
    "World.gd": [
        ("var _terrain: Terrain = null       ## the ground, or null when USE_TERRAIN is off",
         "## Loaded by PATH, never by class_name. A GDExtension can register a native\n"
         "## class that shadows any script class_name without a parse-time warning --\n"
         "## TerraBrush registers a non-instantiable `Terrain` and that is exactly what\n"
         "## bit us. preload() resolves the file, so nothing can shadow it.\n"
         "const OverworldScript := preload(\"res://scripts/Overworld.gd\")\n"
         "var _terrain: Node3D = null        ## the ground, or null when USE_TERRAIN is off"),
        ("\t_terrain = Terrain.new()", "\t_terrain = OverworldScript.new()"),
    ],
}


def patch(path, hunks, dry):
    if not os.path.exists(path):
        sys.exit("missing %s" % path)
    src = open(path, encoding="utf-8").read()
    orig = src
    migrated = 0
    for old, new in MIGRATIONS.get(os.path.basename(path), []):
        if old in src:
            src = src.replace(old, new)
            migrated += 1
    applied, skipped = [], []
    for name, anchor, make in hunks:
        probe = "[terrain] " + name
        if probe in src:
            skipped.append(name)
            continue
        if anchor not in src:
            sys.exit("ANCHOR NOT FOUND in %s for hunk %r -- refusing to guess.\n"
                     "  looked for: %r" % (os.path.basename(path), name, anchor[:70]))
        if src.count(anchor) != 1:
            sys.exit("anchor for %r appears %d times in %s -- too ambiguous to patch."
                     % (name, src.count(anchor), os.path.basename(path)))
        src = src.replace(anchor, make(anchor), 1)
        applied.append(name)
    if src != orig and not dry:
        bak = path + ".bak_preterrain"
        if not os.path.exists(bak):
            shutil.copy2(path, bak)
        open(path, "w", encoding="utf-8").write(src)
    print("  %-12s applied %d  (%s)   already there %d%s" %
          (os.path.basename(path), len(applied), ", ".join(applied) or "-", len(skipped),
           "   MIGRATED %d" % migrated if migrated else ""))
    return src


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--dry", action="store_true")
    a = ap.parse_args()
    S = os.path.join(a.repo, "scripts")
    print("patch_terrain: %s%s" % (a.repo, "  (dry run)" if a.dry else ""))

    # ---------------------------------------------------------------- World.gd
    patch(os.path.join(S, "World.gd"), [
        ("flags",
         "const USE_TREES_V2 := true",
         lambda an: an + "\n" + WORLD_FLAGS),

        ("build call",
         "\t_build_environment()\n\t_pick_cave_sites()",
         lambda an: "\t_build_environment()\n\t_build_terrain()  ## [terrain] build call\n\t_pick_cave_sites()"),

        ("builder",
         "\nfunc _build_caves() -> void:",
         lambda an: WORLD_BUILD + an),

        ("border",
         "func _build_border() -> void:\n",
         lambda an: an + "\t## [terrain] border: the map rim replaces the walls when the\n"
                         "\t## overworld is on -- _out_of_world() is the net out there.\n"
                         "\tif _terrain != null:\n\t\treturn\n"),

        ("bounds net",
         "\tif _player.global_position.y < -40.0 \\\n"
         "\t\t\tor absf(_player.global_position.x) > 103.5 or absf(_player.global_position.z) > 103.5:\n"
         "\t\t_player.global_position = Vector3(0, 2, 0)",
         lambda an: "\tif _out_of_world(_player.global_position):  ## [terrain] bounds net\n"
                    "\t\t_player.global_position = _world_home()"),

        ("fog base",
         "\tvar want_fog := lerpf(BASE_FOG * weather_fog_scale, CAVE_FOG, depth_u)",
         lambda an: "\t## [terrain] fog base: the valley's fog is tuned for a 100 m box and\n"
                    "\t## would bury Katahdin. _process re-aims fog_density every frame, so\n"
                    "\t## the base has to change HERE, not once at build time.\n"
                    "\tvar _fog0: float = TERRAIN_FOG if _terrain != null else BASE_FOG\n"
                    "\tvar want_fog := lerpf(_fog0 * weather_fog_scale, CAVE_FOG, depth_u)"),

        ("streamed trees",
         "\t\tfor t in get_tree().get_nodes_in_group(group):",
         lambda an: an + "\n\t\t\t## [terrain] streamed trees: the ones the terrain scattered are\n"
                         "\t\t\t## regenerated on load, never serialised -- 4,000 of them would\n"
                         "\t\t\t## bloat every save and pin them to a tile that has moved on.\n"
                         "\t\t\tif (t as Node).has_meta(\"streamed\"):\n\t\t\t\tcontinue"),

        ("rebuild on load",
         "\tfor group in [\"trees\", \"tree_stumps\", \"carry_logs\", \"dropped_items\", \"beds\", \"psx_props\"]:\n"
         "\t\tfor n in get_tree().get_nodes_in_group(group):\n\t\t\t(n as Node).queue_free()",
         lambda an: an + "\n\t## [terrain] rebuild on load: the sweep above just deleted every\n"
                         "\t## streamed tree along with the saved ones. Put the forest back.\n"
                         "\tif _terrain != null:\n\t\t_terrain.rebuild_all()"),
    ], a.dry)

    # --------------------------------------------------------------- Player.gd
    patch(os.path.join(S, "Player.gd"), [
        ("far plane",
         "\tcamera.near = 0.02",
         lambda an: "\t## [terrain] far plane: Katahdin is five kilometres out; the default\n"
                    "\t## 4000 m far plane clips the ranges off the horizon.\n"
                    "\tcamera.far = 9000.0\n" + an),
    ], a.dry)

    print("done." if not a.dry else "dry run -- nothing written.")


if __name__ == "__main__":
    main()
