class_name EditorMode
extends RefCounted

## ===========================================================================
## THE ONE FLAG — scripts/EditorMode.gd
##
## True while the map editor's spectator camera is out and the player's body is
## parked. Everything in the world that HUNTS, FOLLOWS or TOUCHES the player
## reads this and finds nothing there.
##
## It lives in its own file, and names no other class, for the same reason
## GameMode is duck-typed: Enemy, Critter and CritterSwarm have to be able to
## import it, and anything it imported back would close a cycle.
##
## Set in exactly one place -- Player.set_editing() -- so the flag and the
## parked body can never disagree.
##
## Who reads it:
##   Enemy._get_player()      the choke point for all 9 mobs AND all 73
##                            wildlife species (Critter extends Enemy)
##   CritterSwarm._process()  the blackflies, which find you by group
##
## Everything else is covered physically instead: the parked body's
## collision_layer goes to 0, so no sensor, ray, hitbox or falling trunk can
## find it either.
## ===========================================================================

static var active := false
