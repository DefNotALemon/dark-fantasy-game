#!/usr/bin/env python3
"""
Put the whole wildlife roster into the M spawn menu.

    python3 tools/patch_spawn_menu.py            # patch
    python3 tools/patch_spawn_menu.py --check    # report only
    python3 tools/patch_spawn_menu.py --revert   # restore the .bak

Re-runnable; guarded by a marker. Keeps scripts/Player.gd.bak_spawnmenu.

The menu was a single column of nine buttons. Nine plus sixty-five wild
species plus the legends is seventy-nine, which is more than twice the height
of the viewport, so this replaces _build_spawn_menu() with a framed scroller
of three-wide grids under group headings.

The wildlife rows are read out of CritterDex at runtime, not listed here — a
species added to the dex appears in this menu with no edit to Player.gd, which
is the same promise the rest of the system makes.
"""

import argparse
import pathlib
import re
import sys

MARK = "## --- wildlife menu ---"

NEW_MENU = '''func _build_spawn_menu() -> void:
	%(mark)s
	## The roster outgrew a single column the day the wildlife landed: nine
	## mobs, sixty-five wild species and the legends is seventy-nine buttons,
	## about twice the height of the viewport. Everything below the title now
	## lives in a fixed-size scroller, three buttons to a row, under headings.
	spawn_panel = PanelContainer.new()
	spawn_panel.visible = false
	hud_layer.add_child(spawn_panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	spawn_panel.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	margin.add_child(outer)

	var title := Label.new()
	title.text = "Spawn (~10 ft ahead)"
	outer.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(SPAWN_MENU_W, SPAWN_MENU_H)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)

	_menu_head(vb, "MOBS")
	var mob_grid := _menu_grid(vb)
	for entry: Array in _spawn_types():
		_menu_btn(mob_grid, String(entry[0])).pressed.connect(_spawn_mob.bind(entry[1]))

	## Wildlife, straight out of the dex.
	for group: Array in _critter_groups():
		_menu_head(vb, String(group[0]))
		var g := _menu_grid(vb)
		for row: Array in (group[1] as Array):
			_menu_btn(g, String(row[0])).pressed.connect(_spawn_critter.bind(String(row[1])))

	_menu_head(vb, "WORLD")
	var bc := _menu_btn(vb, "Tear open a CAVE (~30 m ahead)", 2)
	bc.pressed.connect(_spawn_cave)
	var bmet := _menu_btn(vb, "Call down a METEOR", 2)
	bmet.pressed.connect(_call_meteor)

	_menu_head(vb, "CAVE LAB — rival generators (~45 m ahead)")
	for entry: Array in [["New Cave 1 — Polished Worms", 1],
			["New Cave 2 — Halls & Passages", 2],
			["New Cave 3 — The Riverbed", 3],
			["New Cave 4 — The Cathedral", 4]]:
		_menu_btn(vb, String(entry[0]), 2).pressed.connect(_spawn_test_cave.bind(int(entry[1])))

	var hint := Label.new()
	hint.text = "M / Esc to close  •  scroll for wildlife"
	hint.modulate = Color(1, 1, 1, 0.55)
	outer.add_child(hint)


func _menu_head(parent: Node, text: String) -> void:
	parent.add_child(HSeparator.new())
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.modulate = Color(1, 1, 1, 0.7)
	parent.add_child(l)


func _menu_grid(parent: Node) -> GridContainer:
	var g := GridContainer.new()
	g.columns = SPAWN_MENU_COLS
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(g)
	return g


func _menu_btn(parent: Node, text: String, span := 1) -> Button:
	var b := Button.new()
	b.text = text
	## Long names ("Black-capped Chickadee") must not blow the grid out — clip
	## and put the full name in the tooltip instead of wrapping the row.
	b.clip_text = true
	b.tooltip_text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(SPAWN_BTN_W * span + (6.0 * (span - 1)), 0)
	b.add_theme_font_size_override("font_size", 13)
	parent.add_child(b)
	return b


func _critter_groups() -> Array:
	%(mark)s
	## Every wild thing, read out of CritterDex — so a species added to the dex
	## turns up in this menu with no edit here. Grouped by body plan, because
	## that is how you think when you want to go and look at something.
	var buckets := {
		"BIG GAME": ["CERVID", "URSID"],
		"PREDATORS": ["CANID", "FELID", "MUSTELID"],
		"CRITTERS": ["CHUNK", "RODENT_S"],
		"BIRDS": ["BIRD_GROUND", "BIRD_RAPTOR", "BIRD_PERCH", "BIRD_WATER"],
		"WATER & COLD BLOOD": ["HERP", "FISH"],
		"SWARMS & BUGS": ["SWARM"],
	}
	var out: Array = []
	for g: String in ["BIG GAME", "PREDATORS", "CRITTERS", "BIRDS",
			"WATER & COLD BLOOD", "SWARMS & BUGS"]:
		var rows: Array = []
		for k: String in CritterDex.keys():
			if CritterDex.flag(k, "legend", false):
				continue
			if (buckets[g] as Array).has(CritterDex.rig_of(k)):
				rows.append([String(CritterDex.get_profile(k).get("nm", k)), k])
		rows.sort_custom(func(a, b): return String(a[0]) < String(b[0]))
		if not rows.is_empty():
			out.append([g, rows])
	## Legends last, and clearly separated — spawning one by hand is a
	## different act from spawning a squirrel.
	var legends: Array = []
	for k: String in CritterDex.legends():
		legends.append([String(CritterDex.get_profile(k).get("nm", k)), k])
	legends.sort_custom(func(a, b): return String(a[0]) < String(b[0]))
	if not legends.is_empty():
		out.append(["LEGENDS", legends])
	return out


func _spawn_spot_ahead(dist: float) -> Vector3:
	## Ground under a point `dist` in front of you. Shared by the mob and the
	## wildlife spawners so they can never disagree about where "ahead" is.
	var fwd := -transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var pos := global_position + fwd * dist
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 3.0, pos + Vector3.DOWN * 30.0)
	q.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	if hit:
		return (hit.position as Vector3) + Vector3.UP * 0.2
	pos.y = global_position.y + 0.5
	return pos


func _spawn_critter(key: String) -> void:
	%(mark)s
	## Wildlife does NOT spawn confused. A disoriented goblin wandering in
	## circles is funny; a deer doing it just looks broken, and half the point
	## of spawning one is to watch it behave.
	var pos := _spawn_spot_ahead(3.0)
	var nm := String(CritterDex.get_profile(key).get("nm", key))
	var dir := get_tree().get_first_node_in_group("wildlife_director")

	if CritterDex.rig_of(key) == "SWARM":
		var sw := CritterSwarm.make(key, pos + Vector3.UP * 1.2)
		get_parent().add_child(sw)
		if dir != null and dir.has_method("adopt_swarm"):
			dir.call("adopt_swarm", sw)
		_add_log_msg("%%s — a cloud of them" %% nm, Color(0.72, 0.86, 0.70))
		return

	var c := Critter.make(key)
	get_parent().add_child(c)
	c.global_position = pos
	c.rotation.y = rotation.y + PI   ## facing you, so you see the front of it
	if dir != null and dir.has_method("adopt"):
		dir.call("adopt", c)
	var note := ""
	if CritterDex.flag(key, "legend", false):
		note = "  (legend)"
	elif CritterDex.flag(key, "water", false):
		note = "  (wants water)"
	elif CritterDex.flag(key, "glide", false):
		note = "  (flier)"
	_add_log_msg("%%s%%s" %% [nm, note], Color(0.80, 0.90, 0.75))


''' % {"mark": MARK}

CONSTS = """const SPAWN_MENU_W := 552.0   %s  the M menu's scroller frame
const SPAWN_MENU_H := 520.0
const SPAWN_MENU_COLS := 3
const SPAWN_BTN_W := 174.0
""" % MARK


def patch(root: pathlib.Path, check: bool) -> int:
    path = root / "scripts" / "Player.gd"
    if not path.exists():
        print("!! not found: %s" % path)
        return 1
    src = path.read_text()
    original = src

    if MARK in src:
        print("== already patched (marker present) — nothing to do")
        return 0

    problems = []

    # 1. constants, right after the movement speeds
    m = re.search(r"^const SPRINT_SPEED := 8\.0\n", src, re.MULTILINE)
    if m:
        src = src[: m.end()] + CONSTS + src[m.end():]
        print("   + menu constants")
    else:
        problems.append("SPRINT_SPEED anchor (constants)")

    # 2. replace _build_spawn_menu entirely, up to the next top-level func
    m = re.search(
        r"^func _build_spawn_menu\(\) -> void:\n.*?(?=^func _spawn_test_cave)",
        src,
        re.MULTILINE | re.DOTALL,
    )
    if m:
        src = src[: m.start()] + NEW_MENU + src[m.end():]
        print("   + _build_spawn_menu rebuilt (scroller + grids + wildlife)")
    else:
        problems.append("_build_spawn_menu block")

    for p in problems:
        print("   !! ANCHOR NOT FOUND: %s" % p)

    if check:
        print("== --check: nothing written")
        return 0 if not problems else 2
    if src == original:
        print("== no changes")
        return 0

    bak = path.with_suffix(".gd.bak_spawnmenu")
    if not bak.exists():
        bak.write_text(original)
        print("   kept original at %s" % bak.name)
    path.write_text(src)
    print("== patched %s" % path)
    return 0 if not problems else 2


def revert(root: pathlib.Path) -> int:
    path = root / "scripts" / "Player.gd"
    bak = path.with_suffix(".gd.bak_spawnmenu")
    if not bak.exists():
        print("!! no backup at %s" % bak.name)
        return 1
    path.write_text(bak.read_text())
    print("== reverted %s" % path.name)
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--revert", action="store_true")
    a = ap.parse_args()
    r = pathlib.Path(a.root).resolve()
    sys.exit(revert(r) if a.revert else patch(r, a.check))
