import sys, os
root = sys.argv[1] if len(sys.argv) > 1 else "."
P = os.path.join(root, "tests/WoodCutTests.gd")
s = open(P, encoding="utf-8").read()
def once(old, new):
    global s
    assert s.count(old) == 1, old[:60]
    s = s.replace(old, new)
once('''	_test_audio()
	_test_trunk()''', '''	_test_audio()
	_test_sword_limbs()
	_test_trunk()''')
once('''func _test_trunk() -> void:''', '''func _count_sticks() -> int:
	var n := 0
	for c in _world.get_children():
		var di := c as DroppedItem
		if di != null and String(di.item.get("name", "")) == "Stick":
			n += 1
	return n


func _test_sword_limbs() -> void:
	## the blade takes the limb its sight-line crosses -- standing or downed
	var t := TreeV2.new()
	t.species = "maple"
	t.stage = 2
	t.tree_seed = 99
	t.position = Vector3(60, 0, 0)
	_world.add_child(t)
	var tb: TreeBranch = null
	for b in t._branches:
		if (b as TreeBranch).mesh != null:
			tb = b
			break
	ok(tb != null, "a standing maple has limbs to lop")
	if tb != null:
		var box: AABB = tb.mesh.global_transform * tb.mesh.mesh.get_aabb()
		var target := box.get_center()
		var from := target + Vector3(3.0, -0.5, 0.0)
		var dir := (target - from).normalized()
		var r: Array = t.branch_on_ray(from, dir, 8.0)
		ok(not r.is_empty(), "branch_on_ray: a sight-line through a limb finds one")
		ok(r.is_empty() or (r[1] as Vector3).distance_to(from) <= 8.0, "...within reach")
		ok(t.branch_on_ray(from, -dir, 8.0).is_empty(), "branch_on_ray: pointed away, nothing")
		ok(t.branch_on_ray(from, dir, 0.5).is_empty(), "branch_on_ray: out of reach, nothing")
		if not r.is_empty():
			var limb := r[0] as TreeBranch
			var sticks0 := _count_sticks()
			var off := false
			var swings := 0
			while not off and swings < 5:
				off = limb.take_hit(1)
				swings += 1
			ok(off and swings <= 3, "one to three sword cuts take a standing limb (%d)" % swings)
			ok(limb.gone and _count_sticks() > sticks0, "and it is gone, with sticks on the ground (+%d)"
				% (_count_sticks() - sticks0))
			ok(t.branch_on_ray(from, dir, 8.0).is_empty() or (t.branch_on_ray(from, dir, 8.0)[0] as TreeBranch) != limb,
				"a lopped limb is never found again")
	## the same on the felled oak
	var vis := 0
	var pick: Dictionary = {}
	for tw in _trunk._twigs:
		if (tw["mesh"] as MeshInstance3D).visible:
			vis += 1
			if pick.is_empty():
				pick = tw
	ok(not pick.is_empty(), "the downed oak still carries branches")
	if not pick.is_empty():
		var mi := pick["mesh"] as MeshInstance3D
		var box2: AABB = mi.global_transform * mi.mesh.get_aabb()
		var target2 := box2.get_center()
		var from2 := target2 + Vector3(0.0, 2.5, 2.5)
		var dir2 := (target2 - from2).normalized()
		var r2: Array = _trunk.branch_on_ray(from2, dir2, 8.0)
		ok(not r2.is_empty(), "FallenTrunk.branch_on_ray finds a branch on the downed tree")
		if not r2.is_empty():
			var sticks1 := _count_sticks()
			var n := _trunk.lop_branch(r2[0] as Dictionary, r2[1] as Vector3)
			ok(n >= 1 and _count_sticks() == sticks1 + n, "lop_branch: %d stick(s) on the ground" % n)
			ok(not ((r2[0] as Dictionary)["mesh"] as MeshInstance3D).visible, "the branch is gone from the log")
			var vis2 := 0
			for tw in _trunk._twigs:
				if (tw["mesh"] as MeshInstance3D).visible:
					vis2 += 1
			ok(vis2 == vis - 1, "and out of the trunk's books (%d -> %d)" % [vis, vis2])
			ok(_trunk.lop_branch(r2[0] as Dictionary, r2[1] as Vector3) == 0, "lopping it twice gives nothing")
	t.queue_free()


func _test_trunk() -> void:''')
open(P, "w", encoding="utf-8").write(s)
print("patched tests", len(s))
