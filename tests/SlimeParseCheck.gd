extends SceneTree
## Loads every script the slime pass touched and reports which fail to
## compile — the headless suite only parses what it references, so the
## patched Player.gd / World.gd / CaveRegion.gd need this separate pass.
##   godot --headless --path . --script res://tests/SlimeParseCheck.gd

const FILES := [
	"res://scripts/Slime.gd", "res://scripts/Afflictions.gd", "res://scripts/SlimeDirector.gd",
	"res://scripts/SlimeGreen.gd", "res://scripts/SlimeBlue.gd", "res://scripts/SlimeRed.gd",
	"res://scripts/SlimeYellow.gd", "res://scripts/SlimePurple.gd", "res://scripts/SlimeBlack.gd",
	"res://scripts/SlimeWhite.gd", "res://scripts/SlimeGold.gd", "res://scripts/SlimePink.gd",
	"res://scripts/HitFX.gd", "res://scripts/CaveRegion.gd", "res://scripts/World.gd",
	"res://scripts/Player.gd",
]


func _init() -> void:
	var bad := 0
	for f in FILES:
		var s = load(f)
		if s == null or not (s is GDScript):
			print("  FAIL load: ", f)
			bad += 1
			continue
		var err: int = (s as GDScript).reload(true)
		if err != OK or not (s as GDScript).can_instantiate():
			print("  FAIL compile (%d): %s" % [err, f])
			bad += 1
		else:
			print("  ok  ", f)
	print("PARSE: %d bad of %d" % [bad, FILES.size()])
	quit(0 if bad == 0 else 1)
