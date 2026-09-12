extends Node
## Throwaway MCP parse probe (safe to delete). Naming the classes forces the
## editor to load and compile every script patched in the bear-moves /
## charge-past / peaceful-amnesty session; the typed signature checks below
## make an arity or name typo a COMPILE error here, not a runtime one there.


func _forces_load() -> void:
	print(Player, Enemy, Critter, Boar, GameMode, CritterAnim, CritterDex, CaveRegion)


func _sig_player(p: Player) -> void:
	if p == null:
		return
	var r := p.creature_grab(null, 1.0)
	p.grab_release(Vector3.ZERO)
	var ok := p.creature_press(null)
	p.creature_press_end(Vector3.ZERO)
	print(r, ok, p.grabbed_by, p.pressed_by, p.grab_t, p.press_t)


func _sig_enemy(e: Enemy) -> void:
	if e == null:
		return
	print(e._target_down(null))


func _sig_critter(c: Critter) -> void:
	if c == null:
		return
	print(c._pick_move(null, 1.0), c.grab_anchor(), c._move, c._grab_cd, c._press_cd)
	c._start_move("grab")
	c._move_tick(0.016, null)
	c._move_abort()
	c._finish_move()


func _sig_cave(cv: CaveRegion) -> void:
	if cv == null:
		return
	print(cv.contains_point(Vector3.ZERO))


func _sig_mode() -> void:
	print(GameMode.mob_in_cave(null),
		CritterAnim.duration("bear_grab"), CritterAnim.duration("bear_press"),
		CritterDex.flag("black_bear", "grab", false),
		CritterDex.flag("black_bear", "press", false))
