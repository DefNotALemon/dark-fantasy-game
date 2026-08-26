"""Round four: lie the body down when you get knocked down.

In first person the eye dropped to half a metre but `body_rig` stayed bolt
upright, so the camera ended up INSIDE the standing body — you spent every
knockdown looking up between your own knees. Now the rig tips onto its back with
the camera and slides forward, so your legs stretch out ahead of you on the
ground where they belong.
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
        shutil.copyfile(p, p + ".bak5")
        open(p, "w", encoding="utf-8").write(src)


# the walking body-lean must not fight the knockdown pose
LEAN_OLD = '''	if body_rig:
		body_rig.rotation_degrees = body_rig.rotation_degrees.lerp(
			Vector3(clampf(rot.x, -8.0, 8.0) * 0.55, 0.0, clampf(rot.z, -6.0, 6.0) * 0.6), k)'''
LEAN_NEW = '''	## Not while you're on your back — _update_knockdown owns the rig then.
	if body_rig and kd_phase == "":
		body_rig.rotation_degrees = body_rig.rotation_degrees.lerp(
			Vector3(clampf(rot.x, -8.0, 8.0) * 0.55, 0.0, clampf(rot.z, -6.0, 6.0) * 0.6), k)'''

POSE_OLD = '''	camera.rotation_degrees.z = roll

	_frame_fx_and_regen(delta)'''

POSE_NEW = '''	## THE BODY GOES DOWN WITH THE CAMERA. It used to stay standing while the eye
	## dropped to half a metre, which put the lens inside your own torso — every
	## knockdown in first person was spent staring up between your knees.
	## Tipping the rig onto its back and sliding it forward puts your legs out
	## ahead of you on the ground, which is what you should see lying there.
	if body_rig:
		var lay := 0.0
		match kd_phase:
			"fall":
				lay = clampf(kd_t / KD_FALL, 0.0, 1.0)
			"down", "pinned":
				lay = 1.0
			"rise":
				lay = 1.0 - clampf(kd_t / KD_RISE, 0.0, 1.0)
		var le := lay * lay * (3.0 - 2.0 * lay)
		body_rig.rotation_degrees = Vector3(82.0 * le, body_rig.rotation_degrees.y, 0.0)
		body_rig.position = Vector3(0.0, 0.0, -0.95 * le)

	camera.rotation_degrees.z = roll

	_frame_fx_and_regen(delta)'''

RESET_OLD = '''			if u >= 1.0:
				kd_phase = ""
				kd_t = 0.0
				_update_head_offset()  ## hand the camera back to mouse-look'''
RESET_NEW = '''			if u >= 1.0:
				kd_phase = ""
				kd_t = 0.0
				if body_rig:
					body_rig.position = Vector3.ZERO   ## back on your feet
					body_rig.rotation_degrees.x = 0.0
				_update_head_offset()  ## hand the camera back to mouse-look'''

patch("scripts/Player.gd", [
    (LEAN_OLD, LEAN_NEW, "_update_knockdown owns the rig then"),
    (POSE_OLD, POSE_NEW, "THE BODY GOES DOWN WITH THE CAMERA"),
    (RESET_OLD, RESET_NEW, "back on your feet"),
])

print("done. .bak5 files left beside anything that changed.")
