#!/usr/bin/env python3
"""F3 -> the Grass Lab: four hunks into scripts/Player.gd and one row into
tests/DevInputRegistry.gd. Idempotent (each hunk is skipped when its marker is
present), anchored on exact unique text, --check to look before touching.

  Player.gd
    L1  `var grass_lab: GrassLab = null` after `var godmode: GodEditor = null`   (+1 / -0)
    L2  build it after the god editor: `grass_lab = GrassLab.new()` + add_child (+3 / -0)
    L3  `KEY_F3:` case after KEY_F2's, `_toggle_menu("grass")`                  (+3 / -0)
    L4  `_toggle_menu`: `if grass_lab: grass_lab.visible = which == "grass"`    (+2 / -0)
    L5  `_close_menu`: `if grass_lab: grass_lab.visible = false`                (+2 / -0)
  DevInputRegistry.gd
    R1  the KEY_F3 row after the KEY_F2 row, live kind "menu", expect "grass"  (+3 / -0)
"""
import argparse, os, sys

HUNKS = {
    "scripts/Player.gd": [
        ("L1 var", "var godmode: GodEditor = null\n",
         "var godmode: GodEditor = null\nvar grass_lab: GrassLab = null   ## F3 -- the grass lab (scripts/GrassLab.gd)\n",
         "var grass_lab: GrassLab"),
        ("L2 build", "\tgodmode = GodEditor.new()\n\thud_layer.add_child(godmode)\n",
         "\tgodmode = GodEditor.new()\n\thud_layer.add_child(godmode)\n"
         "\t## The grass lab builds itself too (scripts/GrassLab.gd) -- F3 opens it.\n"
         "\tgrass_lab = GrassLab.new()\n\thud_layer.add_child(grass_lab)\n",
         "grass_lab = GrassLab.new()"),
        ("L3 key", "\t\t\t\tif godmode != null and godmode.visible:\n\t\t\t\t\tgodmode.drop_in_here()\n",
         "\t\t\t\tif godmode != null and godmode.visible:\n\t\t\t\t\tgodmode.drop_in_here()\n"
         "\t\t\tKEY_F3:\n"
         "\t\t\t\t## F3 IS THE GRASS LAB. Styles, colours, shapes and sliders for the meadow.\n"
         "\t\t\t\t_toggle_menu(\"grass\")\n",
         "KEY_F3:"),
        ("L4 toggle", "\tif map_panel:\n\t\tmap_panel.visible = which == \"map\"\n\tif which == \"sky\" and sky_panel:\n",
         "\tif map_panel:\n\t\tmap_panel.visible = which == \"map\"\n"
         "\tif grass_lab:\n\t\tgrass_lab.visible = which == \"grass\"\n\tif which == \"sky\" and sky_panel:\n",
         "grass_lab.visible = which == \"grass\""),
        ("L5 close", "\tif map_panel:\n\t\tmap_panel.visible = false\n\tInput.mouse_mode = Input.MOUSE_MODE_CAPTURED\n",
         "\tif map_panel:\n\t\tmap_panel.visible = false\n"
         "\tif grass_lab:\n\t\tgrass_lab.visible = false\n\tInput.mouse_mode = Input.MOUSE_MODE_CAPTURED\n",
         "grass_lab.visible = false"),
    ],
    "tests/DevInputRegistry.gd": [
        ("R1 row",
         "\t\t{\"tok\": \"KEY_F2\", \"code\": KEY_F2, \"label\": \"F2\",\n"
         "\t\t\t\"what\": \"drop in -- the body comes to the spectator camera and you land in it\",\n"
         "\t\t\t\"live\": \"inert\", \"expect\": \"\",\n"
         "\t\t\t\"why\": \"guarded on the god panel being visible, so with it shut F2 must do nothing\"},\n",
         "\t\t{\"tok\": \"KEY_F2\", \"code\": KEY_F2, \"label\": \"F2\",\n"
         "\t\t\t\"what\": \"drop in -- the body comes to the spectator camera and you land in it\",\n"
         "\t\t\t\"live\": \"inert\", \"expect\": \"\",\n"
         "\t\t\t\"why\": \"guarded on the god panel being visible, so with it shut F2 must do nothing\"},\n"
         "\t\t{\"tok\": \"KEY_F3\", \"code\": KEY_F3, \"label\": \"F3\",\n"
         "\t\t\t\"what\": \"THE GRASS LAB -- styles, colours, shapes and sliders for the meadow\",\n"
         "\t\t\t\"live\": \"menu\", \"expect\": \"grass\", \"why\": \"\"},\n",
         "\"tok\": \"KEY_F3\""),
    ],
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    for rel, hunks in HUNKS.items():
        path = os.path.join(a.root, rel)
        src = open(path, encoding="utf-8", newline="").read()
        out = src
        for name, old, new, mark in hunks:
            if mark in out:
                print("  %-12s %-10s already there" % (rel.split("/")[-1], name))
                continue
            n = out.count(old)
            if n != 1:
                raise SystemExit("%s %s: anchor matches %d times" % (rel, name, n))
            out = out.replace(old, new, 1)
            print("  %-12s %-10s +%d / -0" % (rel.split("/")[-1], name, new.count("\n") - old.count("\n")))
        if out != src and not a.check:
            open(path, "w", encoding="utf-8", newline="").write(out)
            print("  %s written (%+d lines)" % (rel, out.count("\n") - src.count("\n")))


if __name__ == "__main__":
    main()
