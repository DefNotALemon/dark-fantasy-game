class_name SaveGame
extends RefCounted
## SAVE AND LOAD — one slot, written to `user://save01.dat`.
##
## What goes in the file is everything the world can't work out for itself.
## The forest, the caves, the day/night wheel: all of that is a seed and some
## noise, and the noise will redraw it identically forever. What the noise
## can't redraw is what YOU did to it — the trees you felled and how deep the
## axe got into the ones you didn't, the logs lying where they rolled, the
## loot you dropped, the grass you mowed and the cuttings on it, and the rock
## you dug out from under the world (CaveRegion keeps a 30 m sphere of that
## around wherever you were standing). Plus you: your body, your sheet, your
## pack, your shoulder.
##
## TODO(design): this is the manual slot for testing. The real game saves on
## SLEEP — the bedroll is the checkpoint, and the underground sphere is
## captured from the bed.

const PATH := "user://save01.dat"
const VERSION := 2          ## v2: equipment slots hold the ITEMS themselves
const OLDEST_READABLE := 1  ## v1 (index-based equipment) migrates on load


static func has_save() -> bool:
	return FileAccess.file_exists(PATH)


static func stamp() -> String:
	## When the slot was written, for the settings menu to show.
	if not has_save():
		return ""
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return ""
	var d: Variant = f.get_var()
	f.close()
	if d is Dictionary:
		return String((d as Dictionary).get("stamp", ""))
	return ""


static func save_game(player: Node) -> String:
	## Returns "" on success, or a short reason to show the player.
	var world := player.get_tree().get_first_node_in_group("world")
	if world == null or not world.has_method("save_state"):
		return "No world to save"
	var d := {
		"version": VERSION,
		"stamp": Time.get_datetime_string_from_system(true),
		"player": player.save_state(),
		"world": world.save_state(),
	}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return "Couldn't write the save file"
	f.store_var(d)
	f.close()
	return ""


static func load_game(player: Node) -> String:
	if not has_save():
		return "Nothing saved yet"
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return "Couldn't read the save file"
	var raw: Variant = f.get_var()
	f.close()
	if not (raw is Dictionary):
		return "That save file is unreadable"
	var d := raw as Dictionary
	var ver := int(d.get("version", 0))
	if ver < OLDEST_READABLE or ver > VERSION:
		return "That save is from another build"
	var world := player.get_tree().get_first_node_in_group("world")
	if world == null or not world.has_method("apply_state"):
		return "No world to load into"
	world.apply_state(d.get("world", {}) as Dictionary)
	player.apply_state(d.get("player", {}) as Dictionary)
	return ""
