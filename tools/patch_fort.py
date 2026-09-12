#!/usr/bin/env python3
"""tools/patch_fort.py — wire Fort Knox into Overworld.gd and World.gd.

Marker-guarded and idempotent: every hunk is skipped if its marker is already
in the file, so a second pass adds nothing and leaves both files byte-identical.
That matters here because World.gd has now silently lost work twice to duelling
patchers (see docs/TREES_v3_PSX.md); the safe move is always to re-run this
against the LIVE file rather than to commit a copy edited from a stale read.

Markers stay on ONE line each — a marker string that gets line-wrapped in the
output never matches again, and the next pass duplicates the hunk.

    python3 tools/patch_fort.py [repo_root]
"""

import sys
import pathlib

ROOT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
SCRIPTS = ROOT / "scripts"

M_HOLE = "[fort] extra holes"
M_INHOLE = "[fort] punched rects"
M_COLL = "[fort] punched collider"
M_BUILD = "[fort] the granite work on the narrows"
M_READY = "_build_fort()"
M_TITLE = "_show_title(_place_title_for("

changed = []


def edit(path, fn):
    src = path.read_text()
    out = fn(src)
    if out is None or out == src:
        return False
    path.write_text(out)
    changed.append(path.name)
    return True


def need(src, marker, what):
    if marker in src:
        print(f"  = {what}: already there")
        return False
    return True


def once(src, anchor, addition, marker, what):
    """Insert `addition` after the first occurrence of `anchor`."""
    if not need(src, marker, what):
        return src
    i = src.find(anchor)
    if i < 0:
        raise SystemExit(f"!! anchor for {what} not found — refusing to guess")
    j = i + len(anchor)
    print(f"  + {what}")
    return src[:j] + addition + src[j:]


# ---------------------------------------------------------------- Overworld

OVERWORLD_HOLES = '''

## [fort] extra holes — rects punched out of the heightfield at runtime, on
## top of the spawn square. A hole removes the ground MESH and sinks the
## COLLIDER, so whatever registered one has to put its own floor back; that is
## what FortKnox's raft and apron are for. Each entry is {rect: Rect2, sink}.
static var _extra_holes: Array = []
static var _extra_bounds := Rect2()
static var _has_extra := false


## Cut `rect` (world XZ) out of the terrain, collider sunk to `sink`. Tiles
## already standing keep the ground they were built with, so this rebuilds
## them — at boot there are none yet and the rebuild costs nothing.
static func punch_hole(rect: Rect2, sink: float) -> void:
	for h in _extra_holes:
		if ((h as Dictionary)["rect"] as Rect2).is_equal_approx(rect):
			return
	_extra_holes.append({"rect": rect, "sink": sink})
	_extra_bounds = rect if not _has_extra else _extra_bounds.merge(rect)
	_has_extra = true
	if inst != null and inst._loaded:
		inst.rebuild_all()


## Forget every runtime hole. Only tests need this.
static func clear_holes() -> void:
	_extra_holes.clear()
	_extra_bounds = Rect2()
	_has_extra = false
'''

OVERWORLD_INHOLE_OLD = '''static func in_hole(pos: Vector3) -> bool:
	return absf(pos.x) < HOLE_HALF and absf(pos.z) < HOLE_HALF'''

OVERWORLD_INHOLE_NEW = '''static func in_hole(pos: Vector3) -> bool:
	if absf(pos.x) < HOLE_HALF and absf(pos.z) < HOLE_HALF:
		return true
	## [fort] punched rects — cheap out on the merged bounds first: this runs
	## once per quad of every tile, on the worker threads.
	if not _has_extra:
		return false
	var p := Vector2(pos.x, pos.z)
	if not _extra_bounds.has_point(p):
		return false
	for h in _extra_holes:
		if ((h as Dictionary)["rect"] as Rect2).has_point(p):
			return true
	return false'''

OVERWORLD_COLL_OLD = '''			if absf(sx) < inner:
				out[j * (quads + 1) + i] = HOLE_SINK
	return out'''

OVERWORLD_COLL_NEW = '''			if absf(sx) < inner:
				out[j * (quads + 1) + i] = HOLE_SINK
	## [fort] punched collider — same treatment for runtime holes, each with
	## its own sink. Boundary samples keep their real height (Rect2.grow(-0.01))
	## so the collider still meets the surrounding ground flush.
	if _has_extra:
		for j2 in range(quads + 1):
			var sz2 := oz + float(j2) * qs
			for i2 in range(quads + 1):
				var p := Vector2(ox + float(i2) * qs, sz2)
				if not _extra_bounds.has_point(p):
					continue
				for h in _extra_holes:
					var hd: Dictionary = h
					if ((hd["rect"] as Rect2).grow(-0.01)).has_point(p):
						out[j2 * (quads + 1) + i2] = float(hd["sink"])
						break
	return out'''


def patch_overworld(src):
    src = once(src, "static var inst: Overworld = null", OVERWORLD_HOLES,
               M_HOLE, "Overworld: hole registry")
    if need(src, M_INHOLE, "Overworld: in_hole consults them"):
        if OVERWORLD_INHOLE_OLD not in src:
            raise SystemExit("!! in_hole body not as expected — refusing to guess")
        src = src.replace(OVERWORLD_INHOLE_OLD, OVERWORLD_INHOLE_NEW, 1)
        print("  + Overworld: in_hole consults them")
    if need(src, M_COLL, "Overworld: collider sinks them"):
        if OVERWORLD_COLL_OLD not in src:
            raise SystemExit("!! _collision_heights tail not as expected — refusing to guess")
        src = src.replace(OVERWORLD_COLL_OLD, OVERWORLD_COLL_NEW, 1)
        print("  + Overworld: collider sinks them")
    return src


# -------------------------------------------------------------------- World

WORLD_CONSTS = '''

## [fort] the granite work on the narrows. One flag off and the fort, its
## punched hole and its map marker all stay out of the world.
const USE_FORT := true
const FORT_NAME := "Fort Knox"
'''

WORLD_FUNC = '''

## [fort] Stand Fort Knox up on the west bank of the Penobscot narrows, and
## register it as a place so the map dot and the on-screen title both come
## free — Overworld.places() hands back the live array, so appending to it is
## all a landmark needs to exist everywhere the towns do.
func _build_fort() -> void:
	if not USE_FORT or _terrain == null:
		return
	var f := FortKnox.raise_fort(self)
	if f == null:
		push_warning("World: Fort Knox needs loaded terrain — skipped.")
		return
	for p in _terrain.places():
		if String((p as Dictionary).get("name", "")) == FORT_NAME:
			return
	_terrain.places().append({
		"name": FORT_NAME,
		"pos": [FortKnox.SITE_X, FortKnox.SITE_Z],
		"y": f.pad_y,
		"rank": 1,
	})


## [fort] underground title — the depth title is right for a cave and wrong
## for a magazine, so the fort names its own inside.
func _place_title_for(below: bool) -> String:
	if USE_FORT and _player != null and FortKnox.contains(_player.global_position):
		if below:
			return "%s — the Undercroft" % FORT_NAME
		return FORT_NAME
	return "The Hollow Depths" if below else "The Dusk Forest"
'''

WORLD_TITLE_OLD = '_show_title("The Hollow Depths" if below else "The Dusk Forest")'
WORLD_TITLE_NEW = '_show_title(_place_title_for(below))'


def patch_world(src):
    src = once(src, "const TITLE_TIME := 3.0", WORLD_CONSTS,
               M_BUILD, "World: fort flags")
    if need(src, "\t_build_fort()", "World: _ready calls _build_fort"):
        anchor = "\t_build_camp()"
        if anchor not in src:
            raise SystemExit("!! _build_camp() call not found in _ready")
        src = src.replace(anchor, "\t_build_fort()  ## [fort]\n" + anchor, 1)
        print("  + World: _ready calls _build_fort")
    if need(src, "func _build_fort() -> void:", "World: _build_fort body"):
        anchor = "\nfunc _build_camp() -> void:"
        if anchor not in src:
            raise SystemExit("!! _build_camp definition not found")
        src = src.replace(anchor, WORLD_FUNC + anchor, 1)
        print("  + World: _build_fort body")
    if need(src, M_TITLE, "World: underground title"):
        if WORLD_TITLE_OLD not in src:
            print("  ! underground title line not found — left alone")
        else:
            src = src.replace(WORLD_TITLE_OLD, WORLD_TITLE_NEW + "  ## [fort]", 1)
            print("  + World: underground title")
    return src


def main():
    ow = SCRIPTS / "Overworld.gd"
    wd = SCRIPTS / "World.gd"
    for p in (ow, wd, SCRIPTS / "FortKnox.gd"):
        if not p.exists():
            raise SystemExit(f"!! missing {p}")
    print("Overworld.gd")
    edit(ow, patch_overworld)
    print("World.gd")
    edit(wd, patch_world)
    print()
    print("changed:", ", ".join(changed) if changed else "nothing (already patched)")


if __name__ == "__main__":
    main()
