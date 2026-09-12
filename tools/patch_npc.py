#!/usr/bin/env python3
"""Wire the NPC base into World.gd and Player.gd — idempotent, anchored, backed up.

    python3 tools/patch_npc.py            # patch scripts/World.gd + scripts/Player.gd
    python3 tools/patch_npc.py --check    # report what would change, touch nothing
    python3 tools/patch_npc.py --root /path/to/repo

Six hunks, each matched by a structural anchor rather than a line number, and
each skipped when its marker is already present:

  World.gd
    W1  `NPCDirector.boot(self)` right after the `_spawn_player()` call
        (in _ready on the old boot, begin_world() behind the main menu) (+1 / -0)
    W2  save_state: `<out>["npcs"] = NPCDirector.state_of(self)`
        before its final `return <out>`                                (+1 / -0)
    W3  apply_state: `NPCDirector.restore(self, <d>.get("npcs", {}))`
        as the first line of the body                                  (+1 / -0)
  Player.gd
    P1  _spawn_types: `["Villager", NPC],` as the first row            (+1 / -0)
    P2  _input KEY_E: a first branch handing E to NPCFocus.take_e;
        the branch that was first becomes `elif`                       (+2 / -1: the `if` -> `elif`)
    P3  _input KEY_F: an `elif` handing F to NPCFocus.take_f, placed
        after the pin-escape branch                                    (+2 / -0)
    P4  _physics_process: the guard poll gains `and not
        NPCFocus.claims_rmb(self)` — "raising a guard pulls the steel",
        so RMB on a person with the sword sheathed must be the focus,
        not the guard                                                  (+0 / -0: one line edited)

No binding is added: E and F are keys Player._input already claims, and
NPCFocus polls RMB the way the guard does. DevInputRegistry stays as it was.

Backups of both files go to <root>/../dark-fantasy-game-npc-backup-<stamp>/
(never a .bak beside the source).
"""
import argparse
import datetime
import os
import re
import shutil
import sys

W1_MARK = "NPCDirector.boot(self)"
W2_MARK = "NPCDirector.state_of(self)"
W3_MARK = "NPCDirector.restore(self"
P1_MARK = '["Villager", NPC]'
P2_MARK = "NPCFocus.take_e(self)"
P3_MARK = "NPCFocus.take_f(self)"
P4_MARK = "NPCFocus.claims_rmb(self)"
P4_ANCHOR = "blocking = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)"


def func_span(lines, name):
    """(start, end) line indexes of `func name(` at column 0; end is exclusive."""
    start = None
    for i, ln in enumerate(lines):
        if re.match(r"^(static\s+)?func\s+%s\s*\(" % re.escape(name), ln):
            start = i
            break
    if start is None:
        return None
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if re.match(r"^(static\s+)?func\s+\w+\s*\(|^class\s+\w+|^#{2,}", lines[j]) and not lines[j].startswith("\t"):
            end = j
            break
    return start, end


def patch_world(src):
    lines = src.split("\n")
    log = []

    # W1
    if W1_MARK in src:
        log.append("W1 already patched")
    else:
        # The player is spawned from _ready on the old boot and from
        # begin_world() behind the main menu on the new one: follow the call.
        hits = [i for i, ln in enumerate(lines) if ln.strip() == "_spawn_player()"]
        hit = None
        if len(hits) == 1:
            hit = hits[0]
        elif len(hits) > 1:
            for fname in ("begin_world", "_ready"):
                span = func_span(lines, fname)
                if span:
                    inside = [i for i in hits if span[0] < i < span[1]]
                    if inside:
                        hit = inside[0]
                        break
        if hit is None:
            raise SystemExit("W1: `_spawn_player()` call not found (%d candidates)" % len(hits))
        indent = lines[hit][: len(lines[hit]) - len(lines[hit].lstrip())]
        lines.insert(hit + 1, indent + "NPCDirector.boot(self)  ## the people (scripts/NPCDirector.gd, tools/patch_npc.py)")
        log.append("W1 boot after _spawn_player() (line %d)" % (hit + 2))

    # W2
    src2 = "\n".join(lines)
    if W2_MARK in src2:
        log.append("W2 already patched")
    else:
        span = func_span(lines, "save_state")
        if not span:
            raise SystemExit("W2: no save_state in World.gd")
        ret = None
        for i in range(span[1] - 1, span[0], -1):
            m = re.match(r"^\treturn (\w+)\s*$", lines[i])
            if m:
                ret = (i, m.group(1))
                break
        if ret is None:
            raise SystemExit("W2: save_state has no final `return <dict>`")
        lines.insert(ret[0], '\t%s["npcs"] = NPCDirector.state_of(self)  ## the people' % ret[1])
        log.append("W2 npcs into save_state before `return %s` (line %d)" % (ret[1], ret[0] + 1))

    # W3
    src3 = "\n".join(lines)
    if W3_MARK in src3:
        log.append("W3 already patched")
    else:
        span = func_span(lines, "apply_state")
        if not span:
            raise SystemExit("W3: no apply_state in World.gd")
        m = re.match(r"^func apply_state\((\w+)", lines[span[0]])
        param = m.group(1) if m else "d"
        # first non-comment body line
        at = span[0] + 1
        while at < span[1] and lines[at].strip().startswith("##"):
            at += 1
        lines.insert(at, '\tNPCDirector.restore(self, %s.get("npcs", {}))  ## the people' % param)
        log.append("W3 restore at the top of apply_state (line %d)" % (at + 1))

    return "\n".join(lines), log


def patch_player(src):
    lines = src.split("\n")
    log = []

    # P1
    if P1_MARK in src:
        log.append("P1 already patched")
    else:
        span = func_span(lines, "_spawn_types")
        if not span:
            raise SystemExit("P1: no _spawn_types in Player.gd")
        hit = None
        for i in range(span[0], span[1]):
            if '["Boar", Boar]' in lines[i]:
                hit = i
                break
        if hit is None:
            raise SystemExit("P1: `[\"Boar\", Boar]` not found in _spawn_types")
        indent = lines[hit][: len(lines[hit]) - len(lines[hit].lstrip())]
        lines.insert(hit, indent + '["Villager", NPC],  ## a person (scripts/NPC.gd)')
        log.append("P1 Villager row in _spawn_types (line %d)" % (hit + 1))

    # P2 / P3 live inside _input's match
    def key_line(token):
        span = func_span(lines, "_input")
        if not span:
            raise SystemExit("no _input in Player.gd")
        for i in range(span[0], span[1]):
            if re.match(r"^\t+%s:\s*(#.*)?$" % token, lines[i]):
                return i, span[1]
        raise SystemExit("`%s:` not found in Player._input" % token)

    src2 = "\n".join(lines)
    if P2_MARK in src2:
        log.append("P2 already patched")
    else:
        k, end = key_line("KEY_E")
        indent = lines[k][: len(lines[k]) - len(lines[k].lstrip())] + "\t"
        first_if = None
        for i in range(k + 1, min(k + 12, end)):
            if lines[i].startswith(indent + "if "):
                first_if = i
                break
            if re.match(r"^\t+KEY_\w+:", lines[i]):
                break
        if first_if is None:
            raise SystemExit("P2: KEY_E's first `if` not found within 12 lines")
        old = lines[first_if]
        lines[first_if] = indent + "elif " + old[len(indent) + 3:]
        lines.insert(first_if, indent + "\tpass  ## a person: greet / talk / continue the talk (scripts/NPCFocus.gd)")
        lines.insert(first_if, indent + 'if (menu_open == "" or menu_open == "talk") and kd_phase == "" and NPCFocus.take_e(self):')
        log.append("P2 KEY_E hands to NPCFocus.take_e; `%s` -> elif (line %d)" % (old.strip(), first_if + 3))

    src3 = "\n".join(lines)
    if P3_MARK in src3:
        log.append("P3 already patched")
    else:
        k, end = key_line("KEY_F")
        indent = lines[k][: len(lines[k]) - len(lines[k].lstrip())] + "\t"
        # after the pin-escape `if ...:` block: the first `elif` at this indent,
        # else the first `else`, else convert the first `if`
        target = None
        kind = None
        for i in range(k + 1, min(k + 16, end)):
            if re.match(r"^\t+KEY_\w+:", lines[i]):
                break
            if lines[i].startswith(indent + "elif "):
                target, kind = i, "elif"
                break
            if lines[i].startswith(indent + "else:"):
                target, kind = i, "else"
                break
        if target is None:
            for i in range(k + 1, min(k + 12, end)):
                if lines[i].startswith(indent + "if "):
                    target, kind = i, "if"
                    break
        if target is None:
            raise SystemExit("P3: KEY_F's branch structure not recognised")
        new_branch = indent + 'elif (menu_open == "" or menu_open == "talk") and NPCFocus.take_f(self):'
        if kind == "if":
            old = lines[target]
            lines[target] = indent + "elif " + old[len(indent) + 3:]
            lines.insert(target, indent + "\tpass  ## a person: antagonize (scripts/NPCFocus.gd)")
            lines.insert(target, new_branch.replace("elif ", "if ", 1))
            log.append("P3 KEY_F hands to NPCFocus.take_f; `%s` -> elif (line %d)" % (old.strip(), target + 3))
        else:
            lines.insert(target, indent + "\tpass  ## a person: antagonize (scripts/NPCFocus.gd)")
            lines.insert(target, new_branch)
            log.append("P3 KEY_F elif before `%s` (line %d)" % (lines[target + 2].strip(), target + 1))

    src4 = "\n".join(lines)
    if P4_MARK in src4:
        log.append("P4 already patched")
    else:
        hits = [i for i, ln in enumerate(lines) if P4_ANCHOR in ln]
        if len(hits) != 1:
            raise SystemExit("P4: expected exactly one `%s`, found %d" % (P4_ANCHOR, len(hits)))
        i = hits[0]
        lines[i] = lines[i].replace(P4_ANCHOR, P4_ANCHOR + " and not NPCFocus.claims_rmb(self)", 1)
        log.append("P4 guard poll yields RMB to a focus (line %d, edited in place)" % (i + 1))

    return "\n".join(lines), log


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--backup-dir", default=None)
    a = ap.parse_args()
    root = os.path.abspath(a.root)
    targets = {
        "scripts/World.gd": patch_world,
        "scripts/Player.gd": patch_player,
    }
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M")
    bdir = a.backup_dir or os.path.join(os.path.dirname(root), "dark-fantasy-game-npc-backup-%s" % stamp)
    changed = 0
    for rel, fn in targets.items():
        path = os.path.join(root, rel)
        if not os.path.exists(path):
            raise SystemExit("missing " + path)
        with open(path, "r", encoding="utf-8", newline="") as f:
            src = f.read()
        out, log = fn(src)
        for l in log:
            print("%-18s %s" % (rel + ":", l))
        if out == src:
            continue
        added = out.count("\n") - src.count("\n")
        print("%-18s %+d lines" % (rel + ":", added))
        if a.check:
            continue
        os.makedirs(bdir, exist_ok=True)
        shutil.copy2(path, os.path.join(bdir, os.path.basename(path)))
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(out)
        changed += 1
    if changed and not a.check:
        print("backups in", bdir)
    print("done: %d file(s) %s" % (changed, "would change" if a.check else "changed"))


if __name__ == "__main__":
    main()
