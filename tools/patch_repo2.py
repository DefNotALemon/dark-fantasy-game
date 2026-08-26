"""Trees v2 round 2: save/load round-trip, and chop feedback. Run from repo root.

Fixes two bugs found after the first launch:

  1. LOADING A SAVE DELETED THE ENTIRE FOREST. World.save_state() only wrote
     nodes that were `is ChopTree`, and apply_state() cleared the "trees" group
     before restoring — so every TreeV2 was queue_free()d and nothing came back.
  2. Chopping gave the player almost nothing to go on: a limb nine metres
     overhead lost HP invisibly and the only message appeared at three limbs
     left. It read as "the axe does nothing".
"""
import os
import shutil

ROOT = os.path.dirname(os.path.abspath(__file__))
if os.path.basename(ROOT) == "tools":
    ROOT = os.path.dirname(ROOT)


def patch(path, pairs):
    p = os.path.join(ROOT, path)
    src = open(p, encoding="utf-8").read()
    orig = src
    for old, new in pairs:
        if new.strip().splitlines()[0] in src:
            print("  = already patched:", path)
            continue
        if old not in src:
            print("  ! ANCHOR NOT FOUND in %s:\n    %s" % (path, old.splitlines()[0]))
            continue
        src = src.replace(old, new, 1)
        print("  + patched", path)
    if src != orig:
        shutil.copyfile(p, p + ".bak3")
        open(p, "w", encoding="utf-8").write(src)


# ------------------------------------------------- World.gd: save/load trees

SAVE_OLD = '''	var trees: Array = []
	for group in ["trees", "tree_stumps"]:
		for t in get_tree().get_nodes_in_group(group):
			if t is ChopTree:
				trees.append((t as ChopTree).save_dict())'''

SAVE_NEW = '''	var trees: Array = []
	for group in ["trees", "tree_stumps"]:
		for t in get_tree().get_nodes_in_group(group):
			## Every kind of tree that can stand in the world has to be written
			## here. Saving only ChopTree meant a v2 forest was silently dropped
			## on save and then wiped on load — the whole wood, gone.
			if t is TreeV2:
				trees.append((t as TreeV2).save_dict())
			elif t is TreeStump:
				trees.append((t as TreeStump).save_dict())
			elif t is ChopTree:
				trees.append((t as ChopTree).save_dict())'''

LOAD_OLD = '''	for td in d.get("trees", []):
		var t := ChopTree.from_dict(td as Dictionary)
		t.position = (td as Dictionary).get("pos", Vector3.ZERO)
		t.rotation.y = float((td as Dictionary).get("rot_y", 0.0))
		add_child(t)'''

LOAD_NEW = '''	for td in d.get("trees", []):
		var dd := td as Dictionary
		match str(dd.get("kind", "chop")):
			"tree_v2":
				var tv := TreeV2.from_dict(dd)
				add_child(tv)
				tv.restore(dd)          ## after _ready, so the limbs exist
			"stump":
				add_child(TreeStump.from_dict(dd))
			_:
				## old saves: cone trees, no "kind" key
				var t := ChopTree.from_dict(dd)
				t.position = dd.get("pos", Vector3.ZERO)
				t.rotation.y = float(dd.get("rot_y", 0.0))
				add_child(t)'''

patch("scripts/World.gd", [(SAVE_OLD, SAVE_NEW), (LOAD_OLD, LOAD_NEW)])


# ------------------------------------------------- Player.gd: chop feedback

FEEDBACK_OLD = '''		if t2.chop_hit(toward, aim):
			_add_log_msg("Timber!", Color(0.85, 0.75, 0.5))
		elif t2.trunk_blocked() and t2.branches_left() <= 3:
			_add_log_msg("%d limbs left" % t2.branches_left(), Color(0.62, 0.66, 0.58))
		return'''

FEEDBACK_NEW = '''		var was_blocked := t2.trunk_blocked()
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

HINT_VAR_OLD = '''var axe_swing_axis := Vector3.ZERO'''
HINT_VAR_NEW = '''var axe_swing_axis := Vector3.ZERO

## Show the "clear the limbs first" hint once, not on every swing.
var _limb_hinted := false'''

patch("scripts/Player.gd", [(FEEDBACK_OLD, FEEDBACK_NEW), (HINT_VAR_OLD, HINT_VAR_NEW)])

print("done. .bak3 files left beside anything that changed.")
