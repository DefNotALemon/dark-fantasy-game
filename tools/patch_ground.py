#!/usr/bin/env python3
"""Ground textures + the map over god mode -- the Player.gd wiring.  (2026-09-03)

Two things Player.gd has to know that it did not:

  1. M while the god editor is up opens the map OVER the editor. It used to
     call godmode.closed() (menu "map" != "god"), which dropped you back into
     your body, saved the plan and then showed the map -- so "open the map in
     dev mode" meant "leave dev mode". Now menu_open becomes "map" while the
     editor stays visible and spectating; M / Esc / travelling close just the
     map and menu_open goes back to "god".
  2. map_eye(): the node the map's arrow follows -- the spectator camera while
     you are out of your body, the body otherwise.

Re-runnable: every hunk checks its marker first. Anchors are exact strings
lifted from the live file; the script refuses to run if one is missing or
ambiguous rather than guess.  Markers stay on ONE line (a wrapped marker never
matches on the second pass -- the patch_god.py lesson).

    python3 tools/patch_ground.py            (from the repo root)
"""
import sys, pathlib

SRC = pathlib.Path(__file__).resolve().parent.parent / "scripts"
changes = []


def patch(text, anchor, addition, marker, where="after", name=""):
    if marker in text:
        changes.append(f"  = {name}: already present")
        return text
    if text.count(anchor) != 1:
        raise SystemExit(f"ANCHOR {'MISSING' if anchor not in text else 'AMBIGUOUS'} for {name}:\n{anchor[:160]}")
    if where == "after":
        new = text.replace(anchor, anchor + addition)
    elif where == "before":
        new = text.replace(anchor, addition + anchor)
    else:
        new = text.replace(anchor, addition)
    changes.append(f"  + {name}")
    return new


p = (SRC / "Player.gd").read_text()

# --- A. _toggle_menu: the map over the editor -----------------------------------
p = patch(p, """func _toggle_menu(which: String) -> void:
	if menu_open == which:
		_close_menu()
		return
""", """	## MAP OVER GOD MODE (tools/patch_ground.py). While the editor is up the
	## map is an overlay, not a menu change: the editor stays visible and
	## spectating underneath, and closing the map hands the cursor back to it.
	if which == "map" and godmode != null and godmode.visible and map_panel:
		if menu_open == "map":
			_map_over_god(false)
		else:
			_map_over_god(true)
		return
	## F1 with the map over the editor: just drop the map. Re-running
	## godmode.opened() here would snap the spectator camera back to the body.
	if which == "god" and menu_open == "map" and godmode != null and godmode.visible:
		_map_over_god(false)
		return
""", "MAP OVER GOD MODE (tools/patch_ground.py)", name="_toggle_menu map-over-god")

# --- B. _close_menu: Esc with the map over the editor closes just the map -------
p = patch(p, """func _close_menu() -> void:
	menu_open = ""
""", """func _close_menu() -> void:
	if menu_open == "map" and godmode != null and godmode.visible:
		_map_over_god(false)     ## map-over-god: close the map, keep the editor
		return
	menu_open = ""
""", "map-over-god: close the map, keep the editor", where="replace", name="_close_menu map-over-god")

# --- C. the helpers, after _close_menu -------------------------------------------
p = patch(p, """	if map_panel:
		map_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
""", """

func _map_over_god(on: bool) -> void:
	## Show / hide the map on top of the god editor without touching the editor.
	## (tools/patch_ground.py -- map_over_god helper)
	if on:
		menu_open = "map"
		drawing = false
		bow_draw = 0.0
		map_panel.visible = true
		map_panel.opened()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if godmode.has_method("map_opened"):
			godmode.map_opened()
	else:
		menu_open = "god"
		map_panel.visible = false
		if godmode.has_method("map_closed"):
			godmode.map_closed()
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func map_eye() -> Node3D:
	## The node the M map's arrow marks: the spectator camera while god mode
	## has you out of your body, the body otherwise. (tools/patch_ground.py)
	if godmode != null and godmode.has_method("spectating") and godmode.spectating() \\
			and godmode.cam != null:
		return godmode.cam
	return self
""", "map_over_god helper", name="_map_over_god + map_eye")

(SRC / "Player.gd").write_text(p)
print("Player.gd:")
print("\n".join(changes))
