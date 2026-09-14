#!/usr/bin/env python3
"""Wire the F4 Claude chat (scripts/ClaudeChat.gd) into Player.gd, the dev-key
registry and its suite, and the README. Idempotent: every edit checks for its
own marker first. Run from the repo root:

    python3 tools/patch_claude_chat.py
"""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
changed = []

def patch(path, edits):
    p = ROOT / path
    s = p.read_text()
    orig = s
    for marker, anchor, new, count in edits:
        if marker in s:
            continue
        assert s.count(anchor) == count, f"{path}: anchor x{s.count(anchor)} (want {count}): {anchor[:70]!r}"
        s = s.replace(anchor, new)
    if s != orig:
        p.write_text(s)
        changed.append(path)

# ---------------------------------------------------------------- Player.gd
patch("scripts/Player.gd", [
    # the field, next to the grass lab's
    ("var claude_chat: ClaudeChat",
     "var grass_lab: GrassLab = null   ## F3 -- the grass lab (scripts/GrassLab.gd)\n",
     "var grass_lab: GrassLab = null   ## F3 -- the grass lab (scripts/GrassLab.gd)\n"
     "var claude_chat: ClaudeChat = null   ## F4 -- Claude, riding along (scripts/ClaudeChat.gd)\n", 1),
    # built after the grass lab
    ("claude_chat = ClaudeChat.new()",
     "\tgrass_lab = GrassLab.new()\n\thud_layer.add_child(grass_lab)\n",
     "\tgrass_lab = GrassLab.new()\n\thud_layer.add_child(grass_lab)\n"
     "\t## Claude rides along too (scripts/ClaudeChat.gd) -- F4 opens the chat.\n"
     "\tclaude_chat = ClaudeChat.new()\n\thud_layer.add_child(claude_chat)\n\tclaude_chat.player = self\n", 1),
    # first refusal on keys while the card is up, right after the god editor's
    ("claude_chat.eat_input(event)",
     "\tif godmode != null and godmode.eat_input(event):\n\t\treturn\n",
     "\tif godmode != null and godmode.eat_input(event):\n\t\treturn\n"
     "\t## THE CLAUDE CARD (F4) owns the keyboard while it is up -- a typed M\n"
     "\t## must never open the map. Esc and F4 fall through to close/toggle it.\n"
     "\tif claude_chat != null and claude_chat.eat_input(event):\n\t\treturn\n", 1),
    # the key, after F3
    ("_toggle_menu(\"claude\")",
     "\t\t\tKEY_F3:\n\t\t\t\t## F3 IS THE GRASS LAB. Styles, colours, shapes and sliders for the meadow.\n\t\t\t\t_toggle_menu(\"grass\")\n",
     "\t\t\tKEY_F3:\n\t\t\t\t## F3 IS THE GRASS LAB. Styles, colours, shapes and sliders for the meadow.\n\t\t\t\t_toggle_menu(\"grass\")\n"
     "\t\t\tKEY_F4:\n\t\t\t\t## F4 IS CLAUDE. A live chat card over the game; the game keeps running.\n\t\t\t\t_toggle_menu(\"claude\")\n", 1),
    # the panel table
    ("claude_chat.visible = which == \"claude\"",
     "\tif grass_lab:\n\t\tgrass_lab.visible = which == \"grass\"\n",
     "\tif grass_lab:\n\t\tgrass_lab.visible = which == \"grass\"\n"
     "\tif claude_chat:\n\t\tclaude_chat.visible = which == \"claude\"\n", 1),
])

# ------------------------------------------------------- DevInputRegistry.gd
patch("tests/DevInputRegistry.gd", [
    ("\"tok\": \"KEY_F4\"",
     "\t\t{\"tok\": \"KEY_F3\", \"code\": KEY_F3, \"label\": \"F3\",\n"
     "\t\t\t\"what\": \"THE GRASS LAB -- styles, colours, shapes and sliders for the meadow\",\n"
     "\t\t\t\"live\": \"menu\", \"expect\": \"grass\", \"why\": \"\"},\n",
     "\t\t{\"tok\": \"KEY_F3\", \"code\": KEY_F3, \"label\": \"F3\",\n"
     "\t\t\t\"what\": \"THE GRASS LAB -- styles, colours, shapes and sliders for the meadow\",\n"
     "\t\t\t\"live\": \"menu\", \"expect\": \"grass\", \"why\": \"\"},\n"
     "\t\t{\"tok\": \"KEY_F4\", \"code\": KEY_F4, \"label\": \"F4\",\n"
     "\t\t\t\"what\": \"CLAUDE -- a live chat card over the game, with a note-taker that sends up the line\",\n"
     "\t\t\t\"live\": \"menu\", \"expect\": \"claude\", \"why\": \"\"},\n", 1),
])

# ---------------------------------------------------------- DevInputTests.gd
patch("tests/DevInputTests.gd", [
    ("twenty-six rows",
     "ok(b.size() == 25, \"twenty-five rows, one per match case in Player._input (got %d)\" % b.size())",
     "ok(b.size() == 26, \"twenty-six rows, one per match case in Player._input (got %d)\" % b.size())", 1),
    ("fifteen rows can be driven live",
     "ok(probeable == 14, \"fourteen rows can be driven live (%d)\" % probeable)",
     "ok(probeable == 15, \"fifteen rows can be driven live (%d)\" % probeable)", 1),
    ("eight keys toggle a menu open and shut",
     "ok(int(kinds.get(\"menu\", 0)) == 7, \"seven keys toggle a menu open and shut (%d)\" % kinds.get(\"menu\", 0))",
     "ok(int(kinds.get(\"menu\", 0)) == 8, \"eight keys toggle a menu open and shut (%d)\" % kinds.get(\"menu\", 0))", 1),
    ("\"claude, creative, god, grass",
     "same(sorted_join(menus.keys()), \"creative, god, grass, map, settings, sky, spawn, tab\",\n\t\t\t\"the eight menu names the prober will look for\")",
     "same(sorted_join(menus.keys()), \"claude, creative, god, grass, map, settings, sky, spawn, tab\",\n\t\t\t\"the nine menu names the prober will look for\")", 1),
])

# ---------------------------------------------------------------- README.md
patch("README.md", [
    ("| F4 |",
     "| Esc | Settings menu",
     "| F4 | **Claude (dev)**: a live chat card over the game — streamed replies with the game state riding along (where you are, the hour, the weather, health, FPS). Backend dropdown: Anthropic (key from `ANTHROPIC_API_KEY` or the card's KEY field → `user://claude.cfg`) or any OpenAI-compatible local server. A Haiku note-taker writes bugs/ideas/requests to `user://claude_notes/`, and **Send up the line** drops notes + transcript into `notes/claude-handoff/` for the Cowork session |\n| Esc | Settings menu", 1),
])

print("patched:", ", ".join(changed) if changed else "nothing (already applied)")
