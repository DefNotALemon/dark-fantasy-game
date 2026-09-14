#!/usr/bin/env python3
"""tests/CarcassTests.gd: the body is the animal's own skin, and bones are loot."""
import os, sys

ROOT = os.environ.get("REPO", os.path.expanduser("~/mnt/dark-fantasy-game"))
P = os.path.join(ROOT, "tests/CarcassTests.gd")
src = open(P, encoding="utf-8").read()
if "func _t_body_skin()" in src:
    print("no-op")
    sys.exit(0)

SECTION = r'''
# ----------------------------------------------------------------- body skin

func _t_body_skin() -> void:
	claim("body_skin", 31)
	## THE PICTURE IS THE ANIMAL'S OWN SKIN. Until 2026-09-14 a staged body
	## was four flat boxes and some spars -- "some cube that's stuck", when
	## Lemon found the butchery loop. It is the species' rig baked through
	## CreatureSkin now, lying on its side, and at the bones stage what is
	## left of it is loot. CarcassBody is reached by duck typing on purpose:
	## this file must parse on a machine whose class cache has not met it.
	var c := _bus(Carcasses.AUTUMN, Carcasses.SKY_CLEAR, 12.0)
	c.world_seed = 777
	root.add_child(c)
	var pl := FakePlayer.new()
	root.add_child(pl)
	c.player = pl
	pl.global_position = Vector3(12.0, 0.0, 0.0)
	var mass := Carcasses.mass_of("black_bear", 1.7)
	var rec := c.add("black_bear", "black bear", Vector3(3.0, 0.0, -2.0), mass)
	c._restage()
	ok(c.staged_ids().size() == 1, "a bear is a body at twelve metres")
	var body: Node3D = c._staged[int(rec["id"])]
	ok(body.is_in_group("carcass_bodies"), "in the carcass_bodies group")
	ok(body.has_method("dress") and body.has_method("sweep_taken"), "and it is a CarcassBody")
	var skin: CreatureSkin = body.get("skin")
	ok(skin != null and skin.bone_count() > 8,
			"wearing a real skeleton (%d bones)" % (skin.bone_count() if skin != null else 0))
	ok(skin != null and skin.segment_count() > 20,
			"and a real rounded skin, not four boxes (%d segments)"
			% (skin.segment_count() if skin != null else 0))
	ok(skin != null and skin.frozen and not skin.ragdoll, "held still: frozen, never simulating")
	ok(not bool(body.get("pose_from_death")), "a record with no ragdoll pose gets the fallback")
	ok(body.rotation == Vector3.ZERO, "the root never rotates -- the yaw lives in the pose")
	near_f(body.position.x, 3.0, 1e-6, "and it sits where the record says")
	## The fallback is ON ITS SIDE: the pelvis' up axis is nowhere near up...
	var pel: Transform3D = skin.bone_pose(1)
	ok(absf(pel.basis.y.y) < 0.6, "on its side (pelvis up.y = %.2f)" % pel.basis.y.y)
	## ...and on the ground: the lowest point of the skin rests on the terrain.
	var low := INF
	for bid in range(1, skin.bone_count()):
		var box: AABB = skin.bone_aabb(bid)
		var t: Transform3D = skin.bone_pose(bid)
		for k in 8:
			var corner := box.position + Vector3(
					box.size.x if (k & 1) != 0 else 0.0,
					box.size.y if (k & 2) != 0 else 0.0,
					box.size.z if (k & 4) != 0 else 0.0)
			low = minf(low, (t * corner).y)
	near_f(low, 0.01, 0.02, "the lowest point of it rests on the ground")
	ok((body.get("bones") as Dictionary).is_empty(), "no bones to pick up on a whole animal")
	ok(body.get_node_or_null("Slab") != null, "and the stained ground is under it")
	## THE STAGES ARE THE SKIN'S OWN MIRROR: colour and `visible` on the
	## proxies, which is what `_sync_segments` has always read.
	var trunk: MeshInstance3D = body.get("_trunk")
	var live_col: Color = (trunk.material_override as StandardMaterial3D).albedo_color
	rec["left"] = mass * 0.70    ## opened
	c._drive_bodies()
	ok(int(body.get_meta("stage")) == Carcasses.STAGE_OPENED, "the body follows the ledger to OPENED")
	var opened_col: Color = (trunk.material_override as StandardMaterial3D).albedo_color
	ok(opened_col != live_col and opened_col.r > live_col.r,
			"an opened trunk is bloodied (%s -> %s)" % [live_col, opened_col])
	ok(trunk.visible and skin.visible, "and still all there")
	rec["left"] = mass * 0.40    ## picked
	c._drive_bodies()
	ok(int(body.get_meta("stage")) == Carcasses.STAGE_PICKED, "then PICKED")
	ok(not trunk.visible, "the trunk is gone")
	var core: MeshInstance3D = body.get("_core")
	ok(core != null and core.visible, "a dark core shows in its place")
	var ribs: Array = body.get("_ribs")
	ok(ribs.size() >= 3 and (ribs[0] as MeshInstance3D).visible,
			"with %d rib plates over it" % ribs.size())
	ok((body.get("bones") as Dictionary).is_empty(), "and still nothing to pick up")
	## BONES ARE LOOT.
	rec["left"] = mass * 0.10    ## bones
	c._drive_bodies()
	ok(int(body.get_meta("stage")) == Carcasses.STAGE_BONES, "then BONES")
	ok(not skin.visible, "the skin is gone")
	var bones: Dictionary = body.get("bones")
	ok(bones.size() == 10, "a bear leaves ten bones: skull, ribs, two a leg (%d)" % bones.size())
	var names := {}
	var all_items := true
	for k in bones:
		var di := bones[k] as DroppedItem
		if di == null or not di.is_in_group("dropped_items") or not di.has_meta("carcass_bone"):
			all_items = false
			continue
		names[String(di.item.get("name", ""))] = true
	ok(all_items, "every one a DroppedItem in the loot group, marked as the carcass's")
	ok(names.has("Bear Skull") and names.has("Bear Ribs") and names.has("Bear Bone"),
			"named off the animal: %s" % [names.keys()])
	ok(bool((bones["skull"] as DroppedItem).item.get("keep", false)), "and a bone never expires")
	## TAKING ONE IS WRITTEN ON THE RECORD -- the picture's one word back to
	## the ledger. The player frees the node; nothing else ever does.
	(bones["skull"] as DroppedItem).free()
	c._drive_bodies()
	ok((rec.get("bones", {}) as Dictionary).has("skull"), "pick up the skull and the record knows")
	ok(not (rec.get("bones", {}) as Dictionary).has("ribs"), "and only the skull")
	pl.global_position = Vector3(1e5, 0.0, 1e5)
	c._restage()
	pl.global_position = Vector3(12.0, 0.0, 0.0)
	c._restage()
	var body2: Node3D = c._staged[int(rec["id"])]
	var n2 := (body2.get("bones") as Dictionary).size()
	ok(body2 != body and n2 == 9, "walk away and back and the skull is still gone (%d bones)" % n2)
	## and a save carries it
	var c2 := _bus(Carcasses.AUTUMN, Carcasses.SKY_CLEAR, 12.0)
	c2.from_dict(c.to_dict())
	ok(((c2.records[0] as Dictionary).get("bones", {}) as Dictionary).has("skull"),
			"the taken skull survives a save")
	c2.free()
	pl.free()
	c.free()


# ---------------------------------------------------------------------- pose

func _t_pose() -> void:
	claim("pose", 15)
	## THE POSE IS THE DEATH'S. A real kill hands its body to the ragdoll,
	## which settles and freezes; the bus reads the skeleton once, writes it
	## on the record, and the body it stages wears the same pose -- the
	## corpse is hidden in the same sweep, so nothing on screen changes.
	var c := _bus(Carcasses.AUTUMN, Carcasses.SKY_CLEAR, 12.0)
	root.add_child(c)
	var pl := FakePlayer.new()
	root.add_child(pl)
	c.player = pl
	pl.global_position = Vector3.ZERO
	## a dead bear: the fixture the harvest reads, wearing a real skin
	var dead := FakeDead.new()
	dead.species = "black_bear"
	dead.dying = true
	dead.add_to_group("enemies")
	root.add_child(dead)
	dead.global_position = Vector3(4.0, 0.0, 4.0)
	CritterRig.build(dead, "black_bear")
	var dskin := CreatureSkin.bake(dead, {"tile": "fur_long", "mass": 49.0})
	ok(dskin.bone_count() > 8, "the fixture wears a skeleton (%d bones)" % dskin.bone_count())
	ok(c.harvest() == 1, "it dies and is harvested")
	var rec := c.records[0] as Dictionary
	ok(c._pending.size() == 1, "and watched for its pose")
	ok(not rec.has("pose") or (rec["pose"] as PackedFloat32Array).is_empty(),
			"which is not written yet")
	c._restage()
	ok(c.staged_ids().is_empty(), "nothing is staged over a corpse that is still settling")
	## It settles: put it in a pose and freeze it, the way the ragdoll clock
	## does at the end of CORPSE_SETTLE.
	var tilt := Basis(Vector3.BACK, 1.2)
	var globals: Array = []
	for i in dskin.bone_count():
		var rest: Transform3D = dskin.rest_global(i)
		globals.append(Transform3D(tilt * rest.basis, tilt * rest.origin + Vector3(0.0, 0.3, 0.0)))
	dskin.pose_apply(globals)
	ok(dskin.frozen and not dskin.ragdoll, "the fixture is frozen")
	var before := dskin.pelvis_global().origin
	ok(before.distance_to(Vector3(4.0, 0.0, 4.0)) > 0.2, "with its pelvis off the spawn point (%.2f m)"
			% before.distance_to(Vector3(4.0, 0.0, 4.0)))
	c.harvest()    ## the next sweep reads it
	ok(c._pending.is_empty(), "the settled corpse is read and released")
	var pose: PackedFloat32Array = rec.get("pose", PackedFloat32Array())
	ok(pose.size() == dskin.bone_count() * 12, "twelve floats a bone on the record (%d)" % pose.size())
	near_f((rec["at"] as Vector3).x, before.x, 1e-4, "the record moved to where the pelvis lies")
	ok(c.staged_ids().size() == 1, "and the body is staged in the same sweep")
	ok(not dskin.visible, "the corpse is hidden the moment the body exists")
	var body: Node3D = c._staged[int(rec["id"])]
	ok(bool(body.get("pose_from_death")), "and the body wears the death's pose")
	var bskin: CreatureSkin = body.get("skin")
	var after: Vector3 = body.position + bskin.bone_pose(1).origin
	near_f(after.distance_to(before), 0.0, 1e-3, "pelvis for pelvis, where the corpse's was")
	## the same pose after a save
	var c2 := _bus(Carcasses.AUTUMN, Carcasses.SKY_CLEAR, 12.0)
	c2.from_dict(c.to_dict())
	ok(((c2.records[0] as Dictionary)["pose"] as PackedFloat32Array) == pose, "and it survives a save")
	dead.free()
	pl.free()
	c2.free()
	c.free()

'''

anchor = "\n# --------------------------------------------------------------- determinism\n"
assert src.count(anchor) == 1, src.count(anchor)
src = src.replace(anchor, SECTION + anchor)
run_anchor = "\t_t_bodies()\n\t_t_determinism()\n"
assert src.count(run_anchor) == 1
src = src.replace(run_anchor, "\t_t_bodies()\n\t_t_body_skin()\n\t_t_pose()\n\t_t_determinism()\n")
open(P, "w", encoding="utf-8").write(src)
print("patched", P)
