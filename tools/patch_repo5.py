"""Round five: a meteor crater puts the trees standing on it over.

`CaveRegion.meteor_strike()` carves a 4.6 m sphere out of the ground and told
nothing about it. A tree standing on that spot kept standing — with its base
swallowed by the hole, which is why the trunk looked deleted from the ground.
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
        shutil.copyfile(p, p + ".bak6")
        open(p, "w", encoding="utf-8").write(src)


OLD = '''	if _player:
		var d := _player.global_position.distance_to(spot)
		_player.cam_shake = maxf(float(_player.cam_shake), clampf(0.62 - d * 0.004, 0.12, 0.62))'''

NEW = '''	## The crater takes the ground out from under whatever was standing on it.
	## Trees inside the blast go over, away from the impact, and leave a real
	## trunk on the ground — before this the hole simply swallowed the base and
	## the tree stood there with nothing underneath it.
	for t in get_tree().get_nodes_in_group("trees"):
		var tv := t as TreeV2
		if tv == null or tv.felled:
			continue
		if tv.global_position.distance_to(spot) <= METEOR_FELL_RADIUS:
			tv.blast_fell(spot)

	if _player:
		var d := _player.global_position.distance_to(spot)
		_player.cam_shake = maxf(float(_player.cam_shake), clampf(0.62 - d * 0.004, 0.12, 0.62))'''

CONST_OLD = "const TREE_MIN_GAP := 2.1       ## trunks must not grow through each other"
CONST_NEW = '''const TREE_MIN_GAP := 2.1       ## trunks must not grow through each other
## A meteor crater is 4.6 m across; anything rooted within this of the centre
## has lost the ground it stood on.
const METEOR_FELL_RADIUS := 7.5'''

patch("scripts/World.gd", [
    (CONST_OLD, CONST_NEW, "METEOR_FELL_RADIUS"),
    (OLD, NEW, "The crater takes the ground out from under"),
])
print("done. .bak6 files left beside anything that changed.")
