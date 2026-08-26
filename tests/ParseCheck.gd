extends SceneTree
func _init() -> void:
	var bad := 0
	for p in ["res://scripts/Player.gd","res://scripts/Enemy.gd","res://scripts/Critter.gd","res://scripts/Horse.gd","res://scripts/Goblin.gd","res://scripts/Kobold.gd","res://scripts/Orc.gd","res://scripts/Ogre.gd","res://scripts/Skeleton.gd","res://scripts/DarkKnight.gd","res://scripts/Boar.gd","res://scripts/SaddledHorse.gd","res://scripts/CreatureSkin.gd","res://scripts/PsxTex.gd","res://scripts/World.gd"]:
		var sc = load(p)
		if sc == null or not (sc as GDScript).can_instantiate():
			print("BAD ", p)
			bad += 1
	print("parse check done, bad=%d" % bad)
	quit()
