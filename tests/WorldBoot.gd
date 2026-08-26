extends SceneTree
## Boot the real World.tscn headless and check every creature — the player
## included — came up with a baked skin. Run:
##   godot --headless --path . --script res://tests/WorldBoot.gd

var _t := 0.0
var _world: Node = null
var _done := false


func _initialize() -> void:
	_world = (load("res://scenes/World.tscn") as PackedScene).instantiate()
	root.add_child(_world)


func _process(d: float) -> bool:
	_t += d
	if _t < 4.0 or _done:
		return false
	_done = true
	var pl := root.get_tree().get_first_node_in_group("player")
	print("player: %s" % pl)
	if pl != null and "body_skin" in pl and pl.body_skin != null:
		var s: CreatureSkin = pl.body_skin
		print("  player skin bones=%d segs=%d" % [s.bone_count(), s.segment_count()])
	var n := 0
	var skinned := 0
	var classes := {}
	for e in root.get_tree().get_nodes_in_group("enemies"):
		n += 1
		var s2 := CreatureSkin.of(e)
		if s2 != null and s2.bone_count() > 1:
			skinned += 1
		var cn := String(e.get_script().get_global_name()) if e.get_script() else "?"
		classes[cn] = int(classes.get(cn, 0)) + 1
	print("enemies=%d skinned=%d %s" % [n, skinned, classes])
	## knock one over and kill one, to be sure the real world path works
	var victims := root.get_tree().get_nodes_in_group("enemies")
	if victims.size() > 1:
		var a := victims[0] as Enemy
		var b := victims[1] as Enemy
		a.knockdown(Vector3(2, 0.5, 0), 1.0)
		b.take_damage(99999, null, false, null, pl)
		print("knocked=%s ragdoll=%s | dying=%s ragdoll=%s" % [a.knocked, a.skin.ragdoll, b.dying, b.skin.ragdoll])
	print("WORLD BOOT OK")
	quit()
	return true
