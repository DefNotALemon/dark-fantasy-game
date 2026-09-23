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
## v3 rebases every world-space position onto Lewiston-Auburn. Loading a v1/v2
## body into that coordinate frame would move the player, beds, drops,
## incidents and Chronicle places by different amounts, so those prototypes
## are refused rather than silently corrupting the world.
const VERSION := 3
const OLDEST_READABLE := 3
## HARDCORE's tombstone. Written beside the save, never inside it, so that a
## dead run is still a readable file — it just cannot be gone back to.
const SEAL_FILE := "save01.dead"
const SEAL_PATH := "user://save01.dead"


static func has_save() -> bool:
	return FileAccess.file_exists(PATH)


## ============================ The tombstone ================================
## HARDCORE's whole weight sits in these three functions. Dying in Hardcore
## does not delete your save — deleting it would be a mercy, because then
## nothing would be there to refuse you. It lays a marker BESIDE the file:
## the run is still on the disk, it simply cannot be gone back to. The mark
## outlives the process, so quitting and relaunching does not undo the death.


static func is_sealed() -> bool:
	return FileAccess.file_exists(SEAL_PATH)


static func seal(reason := "") -> void:
	var f := FileAccess.open(SEAL_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string("%s\n%s\n" % [Time.get_datetime_string_from_system(true), reason])
	f.close()


static func unseal() -> void:
	## The only two things that break a seal: Settings -> New Run, and writing
	## a fresh save over the slot (which is the same act by another name).
	var d := DirAccess.open("user://")
	if d != null and d.file_exists(SEAL_FILE):
		d.remove(SEAL_FILE)


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
	## Writing a new run over the slot lays the old one to rest — but Player
	## refuses to even call this while GameMode.run_lost, so you cannot use it
	## to unpick the death you just had.
	unseal()
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
	if is_sealed():
		## The whole of Hardcore, right here.
		return "That run is over. Hardcore does not take it back."
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
