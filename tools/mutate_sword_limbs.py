#!/usr/bin/env python3
"""
mutate_sword_limbs.py -- the sword lops branches (2026-09-14).

    python3 tools/mutate_sword_limbs.py [repo-root]

Lemon: "can you make the sword capable of breaking off branches as stick to
any tree?" A sword swing whose sight-line crosses a branch -- on a standing
tree or a downed trunk -- takes the branch instead of nicking the trunk: the
limb's own HP for a standing limb (1-3 swings, same as the axe), one cut for
anything on a felled tree, sticks on the ground either way.
Each replace_once asserts a single match: a second run fails loudly.
"""
import os
import sys

root = sys.argv[1] if len(sys.argv) > 1 else "."


def read(path):
    return open(path, encoding="utf-8").read()


def write(path, s):
    open(path, "w", encoding="utf-8").write(s)


def replace_once(src, old, new, label=""):
    n = src.count(old)
    if n != 1:
        raise SystemExit("expected 1 match for %s, got %d" % (label or old[:40], n))
    return src.replace(old, new)


def insert_before_func(src, name, text):
    i = src.find("\nfunc " + name + "(")
    if i < 0:
        i = src.find("\nstatic func " + name + "(")
    if i < 0:
        raise SystemExit("no func %s" % name)
    return src[:i + 1] + text.rstrip("\n") + "\n\n\n" + src[i + 1:]


# =============================================================================
# TreeV2.gd -- which limb the sight-line crosses
P = os.path.join(root, "scripts/TreeV2.gd")
s = read(P)
s = insert_before_func(s, "chop_hit", '''## The first limb a sight-line runs through, within `reach` of `from` --
## for a blade that cuts what it is pointed at rather than what it is near.
## Returns [TreeBranch, world point] or [] when the ray crosses no limb.
## A limb's box is its mesh (leaves included), so a blade aimed into the
## foliage of a limb still finds the limb: generous on purpose.
func branch_on_ray(from: Vector3, dir: Vector3, reach: float) -> Array:
	var best: TreeBranch = null
	var best_t := INF
	var best_p := Vector3.INF
	for b in _branches:
		var tb := b as TreeBranch
		if not is_instance_valid(tb) or tb.gone or tb.mesh == null \\
				or not is_instance_valid(tb.mesh) or tb.mesh.mesh == null:
			continue
		var box: AABB = tb.mesh.global_transform * tb.mesh.mesh.get_aabb()
		var hit = box.intersects_ray(from, dir)
		if hit == null:
			continue
		var t: float = (hit as Vector3).distance_to(from)
		if t <= reach and t < best_t:
			best_t = t
			best = tb
			best_p = hit as Vector3
	return [best, best_p] if best != null else []
''')
write(P, s)
print("patched TreeV2.gd", len(s))

# =============================================================================
# FallenTrunk.gd -- lopping a branch off a downed tree
P = os.path.join(root, "scripts/FallenTrunk.gd")
s = read(P)
s = insert_before_func(s, "_stick_at", '''## The first branch a sight-line runs through on this downed tree, within
## `reach` of `from`. Returns [twig record, world point] or [].
func branch_on_ray(from: Vector3, dir: Vector3, reach: float) -> Array:
	var best: Dictionary = {}
	var best_t := INF
	var best_p := Vector3.INF
	for tw in _twigs:
		var mi := tw["mesh"] as MeshInstance3D
		if mi == null or not is_instance_valid(mi) or not mi.visible or mi.mesh == null:
			continue
		var box: AABB = mi.global_transform * mi.mesh.get_aabb()
		var hit = box.intersects_ray(from, dir)
		if hit == null:
			continue
		var t: float = (hit as Vector3).distance_to(from)
		if t <= reach and t < best_t:
			best_t = t
			best = tw
			best_p = hit as Vector3
	return [best, best_p] if not best.is_empty() else []


## Take one branch off a downed tree: it vanishes and what lands is sticks --
## one for a twig, two or three for a limb (the same yield TreeBranch gives
## a standing limb). Returns the number of sticks.
func lop_branch(tw: Dictionary, at: Vector3) -> int:
	var mi := tw["mesh"] as MeshInstance3D
	if mi == null or not is_instance_valid(mi) or not mi.visible:
		return 0
	mi.visible = false
	for L in _limbs.duplicate():
		if L["mesh"] == mi:
			var cs := L["shape"] as CollisionShape3D
			if is_instance_valid(cs):
				cs.queue_free()
			_limbs.erase(L)
	_twigs.erase(tw)
	var reach := float(tw.get("reach", 0.5))
	var n := 1 if reach < 1.0 else (2 if reach < 2.4 else 3)
	for _i in range(n):
		_stick_at(at)
	return n''')
write(P, s)
print("patched FallenTrunk.gd", len(s))

# =============================================================================
# Player.gd -- the sword takes the limb it is pointed at
P = os.path.join(root, "scripts/Player.gd")
s = read(P)
s = replace_once(s, '''	## A sword in a tree is a bad idea and it LOOKS like one: chips fly out of
	## the spot you struck, the trunk shivers, and not one bit of the felling
	## job gets done. Bring an axe (2). Elemental steel still marks the bark.
	if not landed:
		var wood_hit := _nearest_wood(forward, attack_range + 0.4)
		if wood_hit != null:
''', '''	## A sword in a tree is a bad idea and it LOOKS like one: chips fly out of
	## the spot you struck, the trunk shivers, and not one bit of the felling
	## job gets done. Bring an axe (2). Elemental steel still marks the bark.
	## ...but a BRANCH in the way of the blade comes off (Lemon 2026-09-14:
	## "make the sword capable of breaking off branches as sticks to any
	## tree"). Point at a limb, standing or downed, and the swing takes the
	## limb rather than nicking the trunk.
	if not landed and _sword_lop_branch(attack_range + 1.2, mat_id):
		cam_punch = maxf(cam_punch, 0.8)
	elif not landed:
		var wood_hit := _nearest_wood(forward, attack_range + 0.4)
		if wood_hit != null:
''', "sword block")

s = insert_before_func(s, "_do_melee_hit", '''func _sword_lop_branch(reach: float, mat_id := "") -> bool:
	## The first branch the sight-line runs through, on any tree in reach --
	## a standing TreeV2 limb (its own HP: one to three cuts, like the axe) or
	## anything on a downed trunk (one cut). Chips, the blade's own sound on
	## the wood, and sticks on the ground when it comes off.
	var from := _aim_origin()
	var dir := -camera.global_transform.basis.z
	var best_t := INF
	var best_owner: Node3D = null
	var best_hit: Variant = null
	var best_p := Vector3.INF
	var cull := (reach + 14.0) * (reach + 14.0)     ## a crown is wide; the trunk is not
	for g in ["trees", "fallen_trunks"]:
		for n in get_tree().get_nodes_in_group(g):
			var holder := n as Node3D
			if holder == null or not holder.has_method("branch_on_ray"):
				continue
			if holder.global_position.distance_squared_to(global_position) > cull:
				continue
			var r: Array = holder.call("branch_on_ray", from, dir, reach)
			if r.is_empty():
				continue
			var t: float = (r[1] as Vector3).distance_to(from)
			if t < best_t:
				best_t = t
				best_owner = holder
				best_hit = r[0]
				best_p = r[1]
	if best_owner == null:
		return false
	var species := ""
	if "species" in best_owner:
		species = String(best_owner.get("species"))
	_fx(HitFX.wood(best_p, _fx_dir(-dir), species, 0.6))
	if mat_id != "":
		_fx(HitFX.element(best_p, _fx_dir(-dir), Materials.blade_fx(mat_id), 0.5))
	WoodAudio.strike(self, best_p, "sword", 0.7, best_owner)
	var off := false
	if best_hit is TreeBranch:
		off = (best_hit as TreeBranch).take_hit(1)
	elif best_owner is FallenTrunk:
		off = (best_owner as FallenTrunk).lop_branch(best_hit as Dictionary, best_p) > 0
	if off:
		WoodAudio.limb(self, best_p)
		_add_log_msg("Limb down", Color(0.72, 0.76, 0.66))
	return true''')
write(P, s)
print("patched Player.gd", len(s))
