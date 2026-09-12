extends Node3D

# =============================================================================
# MOVED -> scripts/Overworld.gd
#
# This file used to declare `class_name Terrain`. It cannot: the TerraBrush
# GDExtension in addons/ registers a NATIVE class called `Terrain` (Node3D,
# non-instantiable), and a native ClassDB name beats a script's class_name
# everywhere, with no parse-time warning. `Terrain.new()` returned null and
# World.gd fell over on the next line:
#
#     Class 'Terrain' isn't exposed.
#     Class type: 'Terrain' is not instantiable.
#     Invalid assignment of property 'name' ... on a base object of type 'Nil'.
#
# The overworld now lives in Overworld.gd as `class_name Overworld`, and
# World.gd loads it by PATH (preload) rather than by name, so no future addon
# can shadow it. tests/TerrainTests.gd asserts both.
#
# Safe to delete this file.
# =============================================================================
