"""Round three: a forest with no holes in it, and chop messages that match the
new rules (limbs never gate felling). Run from the repo root."""
import os
import shutil

ROOT = os.path.dirname(os.path.abspath(__file__))
if os.path.basename(ROOT) == "tools":
    ROOT = os.path.dirname(ROOT)


def patch(path, pairs):
    """pairs: (old, new, sentinel). The sentinel must be a string that appears
    ONLY in the patched version — matching on new's first line was wrong, since
    that line often already exists, which silently skipped real edits."""
    p = os.path.join(ROOT, path)
    src = open(p, encoding="utf-8").read()
    orig = src
    for old, new, sentinel in pairs:
        if sentinel in src:
            print("  = already patched:", path)
            continue
        if old not in src:
            print("  ! ANCHOR NOT FOUND in %s:\n    %s" % (path, old.splitlines()[0]))
            continue
        src = src.replace(old, new, 1)
        print("  + patched", path)
    if src != orig:
        shutil.copyfile(p, p + ".bak4")
        open(p, "w", encoding="utf-8").write(src)


# ------------------------------------------------- World.gd: a real forest

COUNT_OLD = "const TREE_COUNT := 140"
COUNT_NEW = '''## 140 trees over an 80 m disc is one tree every twelve metres — a savanna with
## gaps you can see clean through. A wood wants roughly one every five or six,
## and it wants them in GROVES with clearings between, not evenly sprinkled.
const TREE_COUNT := 420
const GROVE_CHANCE := 0.76      ## odds the next tree joins the last one's grove
const GROVE_SPREAD := Vector2(2.6, 6.5)   ## how far from its neighbour it lands
const TREE_MIN_GAP := 2.1       ## trunks must not grow through each other'''

FOREST_OLD = '''func _build_forest() -> void:
	for i in range(TREE_COUNT):
		var pos := _random_ground_point()
		if pos == Vector3.INF:
			continue
		add_child(_make_tree(pos))'''

FOREST_NEW = '''func _build_forest() -> void:
	## Grow the wood in groves: most trees land near the previous one, some
	## start a new stand somewhere else. That leaves clearings and thickets
	## instead of an even sprinkle, and it closes the see-through gaps.
	var placed: Array[Vector3] = []
	var last := Vector3.INF
	for i in range(TREE_COUNT):
		var pos := Vector3.INF
		if last != Vector3.INF and _rng.randf() < GROVE_CHANCE:
			for _try in range(6):
				var a := _rng.randf() * TAU
				var r := _rng.randf_range(GROVE_SPREAD.x, GROVE_SPREAD.y)
				var cand := last + Vector3(cos(a) * r, 0.0, sin(a) * r)
				if cand.length() > WORLD_RADIUS or cand.length() < SPAWN_CLEAR:
					continue
				pos = cand
				break
		if pos == Vector3.INF:
			pos = _random_ground_point()
		if pos == Vector3.INF:
			continue
		var clash := false
		for q in placed:
			if q.distance_to(pos) < TREE_MIN_GAP:
				clash = true
				break
		if clash:
			continue
		placed.append(pos)
		last = pos
		add_child(_make_tree(pos))'''

patch("scripts/World.gd", [(COUNT_OLD, COUNT_NEW, "GROVE_CHANCE"),
                           (FOREST_OLD, FOREST_NEW, "Grow the wood in groves")])


# ------------------------------------------- Player.gd: messages that fit

MSG_OLD = '''		var was_blocked := t2.trunk_blocked()
		if t2.chop_hit(toward, aim):
			_add_log_msg("Timber!", Color(0.85, 0.75, 0.5))
			return
		## Tell the player what the swing DID, every single time. Without this
		## a limb overhead loses HP in silence and the axe reads as broken.
		match t2.last_result:
			"limb_off":
				var left := t2.branches_left()
				if left > 0:
					_add_log_msg("Limb down — %d to go" % left, Color(0.72, 0.76, 0.66))
				else:
					_add_log_msg("Limbed. Now the trunk.", Color(0.85, 0.78, 0.58))
			"limb":
				if was_blocked and not _limb_hinted:
					_limb_hinted = true
					_add_log_msg("Clear the limbs first", Color(0.68, 0.70, 0.74))
			"trunk":
				pass    ## the wedge and the shiver are the feedback here
		return'''

MSG_NEW = '''		if t2.chop_hit(toward, aim):
			_add_log_msg("Timber!", Color(0.85, 0.75, 0.5))
			return
		## Limbs no longer gate anything — the wedge in the trunk is the whole
		## job, and the growing notch IS the feedback. A limb only answers if
		## you aimed straight at one, and that's worth a word because it's a
		## choice, not a chore.
		if t2.last_result == "limb_off":
			_add_log_msg("Limb down", Color(0.72, 0.76, 0.66))
		return'''

AXIS_OLD = '''		if t2.trunk_blocked():
			## Line the swing up with the limb instead of hacking across it.
			var limb := t2.nearest_branch(global_position, aim)
			if limb != null:
				axe_swing_axis = limb.dir()
		else:
			axe_swing_axis = Vector3.ZERO'''

AXIS_NEW = '''		## Line a limb-swing up with the limb; a trunk swing keeps the normal arc.
		var limb := t2.nearest_branch(global_position, aim)
		axe_swing_axis = limb.dir() if limb != null else Vector3.ZERO'''

patch("scripts/Player.gd", [(AXIS_OLD, AXIS_NEW, "a trunk swing keeps the normal arc"),
                            (MSG_OLD, MSG_NEW, "the growing notch IS the feedback")])

print("done. .bak4 files left beside anything that changed.")
