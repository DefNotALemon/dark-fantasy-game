#!/usr/bin/env python3
"""Held items + the skull helm (2026-09-14).

Lemon: "can you make all the items holdable, as an item fairly large but still
in the players hand (every item). can you also make the bear skull equipable on
the head".

Every edit is an exact-anchor replacement that must match ONCE; a miss is a
hard error, never a silent skip. Run it again and it is a clean no-op.
"""
import os, sys

ROOT = os.environ.get("REPO", os.path.expanduser("~/mnt/dark-fantasy-game"))


def patch(path, edits):
    p = os.path.join(ROOT, path)
    src = open(p, encoding="utf-8").read()
    orig = src
    for anchor, new, guard in edits:
        if guard and guard in src:
            continue
        n = src.count(anchor)
        if n != 1:
            sys.exit("%s: anchor matched %d times:\n%s" % (path, n, anchor[:300]))
        src = src.replace(anchor, new)
    if src != orig:
        open(p, "w", encoding="utf-8").write(src)
        print("patched", path)
    else:
        print("no-op  ", path)


P = "scripts/Player.gd"
patch(P, [
    # ---- vars: the worn skull, the held thing ------------------------------
    (
        "var tp_helm: Node3D              ## worn helm, shown when the helmet slot is filled\n",
        "var tp_helm: Node3D              ## worn helm, shown when the helmet slot is filled\n"
        "var tp_skull: Node3D             ## a skull worn AS the helm (a bone in the helmet slot)\n",
        "var tp_skull: Node3D",
    ),
    (
        "var pick_vm: Node3D              ## pickaxe viewmodel (right hand + haft + head)\n",
        "var pick_vm: Node3D              ## pickaxe viewmodel (right hand + haft + head)\n"
        "\n"
        "## --- HELD ITEM: anything at all out of the pack, carried in the right fist.\n"
        "## (2026-09-14, Lemon: \"make all the items holdable, as an item fairly large\n"
        "## but still in the players hand (every item)\".) One unit leaves the grid\n"
        "## and rides the hand the way a pickaxe does -- sword to the hip, the thing's\n"
        "## own DroppedItem look centred in the fist and sized to read: never longer\n"
        "## than HELD_MAX_M, never smaller than HELD_MIN_M. Drawing steel, a tool or\n"
        "## the bow takes the hand back and the thing returns to the pack by itself.\n"
        "const HELD_REST_POS := Vector3(0.28, -0.29, -0.46)\n"
        "const HELD_REST_ROT := Vector3(18.0, -16.0, 4.0)\n"
        "const HELD_TURN := 60.0           ## degrees the thing turns toward the middle of the view, so\n"
        "                                  ## you see its length and its face, not its end\n"
        "const HELD_MAX_M := 0.46          ## longest side of a held thing, at most\n"
        "const HELD_MIN_M := 0.24          ## ...and at least: a coin is not invisible in a fist\n"
        "const HELD_GRIP := Vector3(0.0, 0.03, -0.10)      ## where the thing sits on the FP fist\n"
        "const HELD_GRIP_TP := Vector3(0.0, -0.05, -0.11)  ## and on the body's fist\n"
        "var held_item := {}               ## the ONE unit in the fist ({} = nothing); not in the grid\n"
        "var held_vm: Node3D               ## first person: hand, forearm and the thing\n"
        "var held_vm_look: Node3D\n"
        "var tp_held: Node3D               ## third person: the twin on tp_hand_r\n"
        "var inv_held_label: Button        ## the doll's \"In hand\" row\n",
        "var held_item := {}",
    ),
    # ---- build: the FP viewmodel and the TP twin root -----------------------
    (
        "\tpick_vm.visible = false\n"
        "\t_build_pick_mesh()\n",
        "\tpick_vm.visible = false\n"
        "\t_build_pick_mesh()\n"
        "\n"
        "\t## --- Held-item viewmodel: the right fist closed on whatever you pulled out. ---\n"
        "\theld_vm = Node3D.new()\n"
        "\thands_root.add_child(held_vm)\n"
        "\theld_vm.position = HELD_REST_POS\n"
        "\theld_vm.rotation_degrees = HELD_REST_ROT\n"
        "\theld_vm.visible = false\n"
        "\t_build_held_hand()\n",
        "\t_build_held_hand()\n",
    ),
    (
        "\ttp_sword = _make_sword(tp_hand_r, Vector3.ZERO, _sword_material_id())\n"
        "\ttp_sword.visible = false\n",
        "\ttp_sword = _make_sword(tp_hand_r, Vector3.ZERO, _sword_material_id())\n"
        "\ttp_sword.visible = false\n"
        "\t## The held thing's twin rides the same fist (filled by _build_held_visuals).\n"
        "\ttp_held = Node3D.new()\n"
        "\ttp_hand_r.add_child(tp_held)\n"
        "\ttp_held.visible = false\n",
        "\ttp_held = Node3D.new()\n",
    ),
    # ---- per frame ---------------------------------------------------------
    (
        "\t_update_pickaxe(delta)\n"
        "\t_update_axe(delta)\n"
        "\t_update_tp_gear(delta)\n"
        "\t_update_camera_arm(delta)\n",
        "\t_update_pickaxe(delta)\n"
        "\t_update_axe(delta)\n"
        "\t_update_held(delta)\n"
        "\t_update_tp_gear(delta)\n"
        "\t_update_camera_arm(delta)\n",
        "\t_update_held(delta)\n",
    ),
    (
        "\t\tpick_vm.visible = false\n"
        "\t\taxe_vm.visible = false\n",
        "\t\tpick_vm.visible = false\n"
        "\t\taxe_vm.visible = false\n"
        "\t\tif held_vm:\n"
        "\t\t\theld_vm.visible = false\n",
        "\t\tif held_vm:\n\t\t\theld_vm.visible = false\n",
    ),
    # ---- the body carries it ------------------------------------------------
    (
        "\t\telif (current_weapon == \"sword\" and sheath_t < 0.5) \\\n"
        "\t\t\t\tor current_weapon == \"pickaxe\" or current_weapon == \"axe\":\n"
        "\t\t\tr_pose = Vector3(-0.35 + s * 0.25, 0.0, 0.0)  ## armed carry, a ghost of stride\n",
        "\t\telif tp_held != null and tp_held.visible:\n"
        "\t\t\t## Carrying a thing: forearm up and forward so it rides in view,\n"
        "\t\t\t## the way the torch does on the other arm.\n"
        "\t\t\tr_pose = Vector3(0.62 + s * 0.20, 0.0, 0.08)\n"
        "\t\telif (current_weapon == \"sword\" and sheath_t < 0.5) \\\n"
        "\t\t\t\tor current_weapon == \"pickaxe\" or current_weapon == \"axe\":\n"
        "\t\t\tr_pose = Vector3(-0.35 + s * 0.25, 0.0, 0.0)  ## armed carry, a ghost of stride\n",
        "\t\telif tp_held != null and tp_held.visible:\n",
    ),
    # ---- the inventory: left click holds plain loot, right click holds anything
    (
        "\tif it.slot == \"\":\n"
        "\t\treturn  ## plain loot — nothing to equip. TODO(design): use/drop actions later\n",
        "\tif it.slot == \"\":\n"
        "\t\t_hold_from_pack(idx)  ## plain loot: it goes in your HAND\n"
        "\t\treturn\n",
        "\t\t_hold_from_pack(idx)  ## plain loot: it goes in your HAND\n",
    ),
    (
        "\t\tb.pressed.connect(_cell_clicked.bind(n))\n"
        "\t\tb.mouse_entered.connect(_set_hovered_item.bind(n))\n",
        "\t\tb.pressed.connect(_cell_clicked.bind(n))\n"
        "\t\tb.gui_input.connect(_cell_gui_input.bind(n))\n"
        "\t\tb.mouse_entered.connect(_set_hovered_item.bind(n))\n",
        "\t\tb.gui_input.connect(_cell_gui_input.bind(n))\n",
    ),
    (
        "\t\tleft.add_child(lbl)\n"
        "\t\tinv_slot_labels[slot] = lbl\n",
        "\t\tleft.add_child(lbl)\n"
        "\t\tinv_slot_labels[slot] = lbl\n"
        "\t## The HAND is a berth too: whatever you are holding, and a click puts it away.\n"
        "\tinv_held_label = Button.new()\n"
        "\tinv_held_label.custom_minimum_size = Vector2(214, 0)\n"
        "\tinv_held_label.alignment = HORIZONTAL_ALIGNMENT_LEFT\n"
        "\tinv_held_label.flat = true\n"
        "\tinv_held_label.focus_mode = Control.FOCUS_NONE\n"
        "\tinv_held_label.pressed.connect(_stow_held.bind(\"\"))\n"
        "\tleft.add_child(inv_held_label)\n",
        "\tinv_held_label = Button.new()\n",
    ),
    (
        "\thint.text = \"Click a pack item to EQUIP / use it (it moves into its slot — Terraria rules);\\nclick a worn slot on the doll to take it back off. B drops · Q wheels (hold Q = pick seat)\\n1 / 2 / 3 / 4 switch pages — Esc closes\"\n",
        "\thint.text = \"Click a pack item to EQUIP / use it (it moves into its slot — Terraria rules); plain loot goes in your HAND.\\nRight-click ANY item to hold it. Click a worn slot on the doll to take it back off. B drops · Q wheels (hold Q = pick seat)\\n1 / 2 / 3 / 4 switch pages — Esc closes\"\n",
        "Right-click ANY item to hold it.",
    ),
    (
        "\tfor slot in SLOT_ORDER:\n"
        "\t\tvar nm := _slot_name(slot)\n"
        "\t\t(inv_slot_labels[slot] as Button).text = \"%s:  %s\" % [SLOT_NAMES[slot], nm if nm != \"\" else \"—\"]\n",
        "\tfor slot in SLOT_ORDER:\n"
        "\t\tvar nm := _slot_name(slot)\n"
        "\t\t(inv_slot_labels[slot] as Button).text = \"%s:  %s\" % [SLOT_NAMES[slot], nm if nm != \"\" else \"—\"]\n"
        "\tif inv_held_label:\n"
        "\t\tvar hn := String(held_item.get(\"name\", \"\"))\n"
        "\t\tinv_held_label.text = \"In hand:  %s\" % (hn if hn != \"\" else \"—\")\n"
        "\t\tinv_held_label.tooltip_text = \"click to put it away\" if hn != \"\" else \"right-click a pack item to hold it\"\n",
        "\tif inv_held_label:\n",
    ),
    # ---- weight: a thing in the fist is carried in full ----------------------
    (
        "\tfor slot in SLOT_ORDER:\n"
        "\t\tvar e: Dictionary = _slot_item(slot)\n"
        "\t\tif not e.is_empty():\n"
        "\t\t\tw += float(e.get(\"weight\", 0.0)) * float(e.get(\"count\", 1)) * 0.5\n"
        "\treturn w\n",
        "\tfor slot in SLOT_ORDER:\n"
        "\t\tvar e: Dictionary = _slot_item(slot)\n"
        "\t\tif not e.is_empty():\n"
        "\t\t\tw += float(e.get(\"weight\", 0.0)) * float(e.get(\"count\", 1)) * 0.5\n"
        "\t## A thing in the fist is carried in full -- it is neither worn nor packed.\n"
        "\tif not held_item.is_empty():\n"
        "\t\tw += float(held_item.get(\"weight\", 0.0)) * float(held_item.get(\"count\", 1))\n"
        "\treturn w\n",
        "\t## A thing in the fist is carried in full",
    ),
    # ---- save / load --------------------------------------------------------
    (
        "\t\t\"inventory\": inventory.duplicate(true),\n"
        "\t\t\"equipment\": equipment.duplicate(true),\n"
        "\t\t\"carried_logs\": carried_logs.duplicate(true),\n",
        "\t\t\"inventory\": inventory.duplicate(true),\n"
        "\t\t\"equipment\": equipment.duplicate(true),\n"
        "\t\t\"held\": held_item.duplicate(true),\n"
        "\t\t\"carried_logs\": carried_logs.duplicate(true),\n",
        "\t\t\"held\": held_item.duplicate(true),\n",
    ),
    (
        "\t## The main hand is never empty — even a broken save wakes armed.\n"
        "\tif _slot_item(\"sword\").is_empty():\n"
        "\t\tequipment[\"sword\"] = {\"name\": \"Iron Sword\", \"weight\": Materials.sword_weight(\"iron\"),\n"
        "\t\t\t\"count\": 1, \"slot\": \"sword\", \"material\": \"iron\"}\n",
        "\t## The main hand is never empty — even a broken save wakes armed.\n"
        "\tif _slot_item(\"sword\").is_empty():\n"
        "\t\tequipment[\"sword\"] = {\"name\": \"Iron Sword\", \"weight\": Materials.sword_weight(\"iron\"),\n"
        "\t\t\t\"count\": 1, \"slot\": \"sword\", \"material\": \"iron\"}\n"
        "\t## And whatever was in the fist goes back in the fist.\n"
        "\tvar held_in: Variant = d.get(\"held\", {})\n"
        "\theld_item = (held_in as Dictionary).duplicate(true) if held_in is Dictionary else {}\n"
        "\tif not held_item.is_empty():\n"
        "\t\tcurrent_weapon = \"sword\"\n"
        "\t\tsheathed = true\n"
        "\t_build_held_visuals()\n",
        "\t## And whatever was in the fist goes back in the fist.\n",
    ),
    # ---- armour: a skull worn as the helm, and what a bone is worth --------
    (
        "\tvar h: Array = _slot_wear_color(\"helmet\", BODY_ARMOR_COL)\n"
        "\tvar has_helm := not _slot_item(\"helmet\").is_empty()\n"
        "\tif tp_helm:\n"
        "\t\ttp_helm.visible = has_helm\n",
        "\tvar h: Array = _slot_wear_color(\"helmet\", BODY_ARMOR_COL)\n"
        "\tvar helm_it: Dictionary = _slot_item(\"helmet\")\n"
        "\tvar has_helm := not helm_it.is_empty()\n"
        "\t## A BONE in the helmet slot is worn as itself -- the bear's skull over\n"
        "\t## your head like a hood, muzzle down over the brow -- not as the cap.\n"
        "\tvar skull_worn := has_helm and helm_it.has(\"bone\")\n"
        "\t_wear_skull(helm_it if skull_worn else {})\n"
        "\tif tp_helm:\n"
        "\t\ttp_helm.visible = has_helm and not skull_worn\n",
        "\tvar skull_worn := has_helm and helm_it.has(\"bone\")\n",
    ),
    (
        "\tvar protect := 0.0\n"
        "\tfor slot: String in Materials.ARMOR_SLOTS:\n"
        "\t\tvar m := _slot_metal(slot)\n"
        "\t\tif m != \"\":\n"
        "\t\t\tprotect += Materials.armor_piece_protect(m)\n"
        "\treturn 1.0 - minf(protect, 0.4)\n",
        "\tvar protect := 0.0\n"
        "\tfor slot: String in Materials.ARMOR_SLOTS:\n"
        "\t\tvar m := _slot_metal(slot)\n"
        "\t\tif m != \"\":\n"
        "\t\t\tprotect += Materials.armor_piece_protect(m)\n"
        "\t\telse:\n"
        "\t\t\t## no metal, but a thing can still say what it is worth: a bear\n"
        "\t\t\t## skull is a few per cent of bone between you and a claw\n"
        "\t\t\tprotect += clampf(float(_slot_item(slot).get(\"protect\", 0.0)), 0.0, 0.1)\n"
        "\treturn 1.0 - minf(protect, 0.4)\n",
        "\t\t\tprotect += clampf(float(_slot_item(slot).get(\"protect\", 0.0)), 0.0, 0.1)\n",
    ),
    # ---- B-drop: the whole dict goes with the thing ------------------------
    (
        '\tvar d := {"name": it.name, "weight": it.weight, "count": 1,\n'
        '\t\t"slot": String(it.get("slot", "")), "material": String(it.get("material", ""))}\n',
        '\t## The WHOLE dict goes with it -- a log keeps its rings and species, a\n'
        '\t## skull keeps being a skull -- not the five keys this used to cut it to.\n'
        '\tvar d := it.duplicate(true)\n'
        '\td["count"] = 1\n',
        "\t## The WHOLE dict goes with it",
    ),
    # ---- the functions ------------------------------------------------------
    (
        "## ============= Dropped items (Q to toss, look + E to reclaim) ==============\n",
        '''## ==================== Held items (anything, in the fist) ==================
## Lemon, 2026-09-14: "make all the items holdable, as an item fairly large but
## still in the players hand (every item)". So: the right hand is a BERTH. One
## unit of any grid stack can leave the pack and ride the fist -- shown by the
## thing's own DroppedItem look, centred and sized to read (HELD_MAX_M /
## HELD_MIN_M), first person on a hand-and-forearm viewmodel and third person
## on the body's own right fist. The sword rides the hip meanwhile. Steel, a
## tool or the bow needs that hand, so drawing any of them puts the thing back
## in the pack on its own (_update_held); nothing is ever dropped or lost.


func _holding() -> bool:
	return not held_item.is_empty()


func _hold_from_pack(idx: int) -> void:
	## Take ONE unit of a grid stack into the right fist. Holding the same
	## thing again puts it away; holding something else swaps (the old thing
	## goes back to the pack, forced -- a swap never vanishes what you own).
	if idx < 0 or idx >= inventory.size():
		return
	var it := inventory[idx]
	if _holding() and String(held_item.get("name", "")) == String(it.get("name", "")):
		_stow_held("")
		return
	if mount != null:
		_add_log_msg("Not from the saddle", Color(0.8, 0.8, 0.8))
		return
	_drop_carried_logs("you reached into your pack")
	var piece := it.duplicate(true)
	piece["count"] = 1
	it["count"] = int(it.get("count", 1)) - 1
	if int(it["count"]) <= 0:
		_remove_inventory_index(idx)
	if _holding():
		_give_item_dict(held_item, true)
	held_item = piece
	if current_weapon != "sword":
		_select_weapon("sword")   ## the tool goes away; the fist is wanted
	sheathed = true               ## and the blade rides the hip
	_build_held_visuals()
	_add_log_msg("Holding: %s" % String(piece.get("name", "")), Color(0.85, 0.9, 1.0))
	if menu_open == "tab" and tab_page == "inventory":
		_refresh_inventory_ui()


func _stow_held(why: String) -> void:
	## Back into the pack (forced: it came out of there, it fits back in).
	if not _holding():
		return
	var nm := String(held_item.get("name", ""))
	var piece := held_item
	held_item = {}
	_clear_held_visuals()
	if _give_item_dict(piece, true):
		_add_log_msg("Put away: %s%s" % [nm, (" -- " + why) if why != "" else ""], Color(0.8, 0.8, 0.8))
	else:
		## The one-of-a-kind caps can refuse (a second bedroll, a second
		## rucksack): then it goes down at your feet, never into nothing.
		var node := DroppedItem.make(piece.duplicate(true))
		get_parent().add_child(node)
		node.global_position = global_position + Vector3.UP * 0.4 - global_transform.basis.z * 0.5
		_add_log_msg("Set down: %s" % nm, Color(0.9, 0.9, 1.0))
	if menu_open == "tab" and tab_page == "inventory":
		_refresh_inventory_ui()


func _cell_gui_input(event: InputEvent, cell: int) -> void:
	## RIGHT CLICK on any pack cell holds the thing in it -- a sword, a
	## helmet, a potion, a skull -- whatever left click means for it.
	if event is InputEventMouseButton and event.pressed \\
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		if cell < inventory.size():
			_hold_from_pack(cell)
			get_viewport().set_input_as_handled()


func _build_held_hand() -> void:
	## The fist and forearm the thing rides in, first person -- the pickaxe's
	## own hand, so a held skull and a held pick are held by the same man.
	var skin := Color(0.62, 0.46, 0.36)
	var armor := Color(0.20, 0.22, 0.28)
	_box(held_vm, Vector3(0.10, 0.10, 0.13), skin, Vector3(0, 0, 0.02))                         ## hand
	_box(held_vm, Vector3(0.09, 0.09, 0.30), armor, Vector3(0, -0.05, 0.18), Vector3(8, 0, 0))  ## forearm


func _clear_held_visuals() -> void:
	## Out of the tree THIS frame, freed when the engine gets to it: a look
	## that is merely queued still counts as a child, and a rebuild in the
	## same frame (a load) would show two.
	if held_vm_look != null and is_instance_valid(held_vm_look):
		if held_vm_look.get_parent() != null:
			held_vm_look.get_parent().remove_child(held_vm_look)
		held_vm_look.queue_free()
	held_vm_look = null
	if tp_held != null and is_instance_valid(tp_held):
		for c in tp_held.get_children():
			tp_held.remove_child(c)
			c.queue_free()


func _build_held_visuals() -> void:
	_clear_held_visuals()
	if not _holding():
		return
	if held_vm != null:
		held_vm_look = _held_look(held_item)
		held_vm.add_child(held_vm_look)
		held_vm_look.position = HELD_GRIP
	if tp_held != null:
		var twin := _held_look(held_item)
		tp_held.add_child(twin)
		twin.position = HELD_GRIP_TP


func _held_look(item: Dictionary) -> Node3D:
	## The thing's own look -- DroppedItem draws every item in the game
	## already -- centred on the fist and sized to read: no longer than
	## HELD_MAX_M along its longest side, no smaller than HELD_MIN_M. Built
	## lying along +X (a bone, a log, a skull), it turns to point FORWARD
	## along -Z the way a blade does; a tall thing (a potion, the rucksack)
	## stays upright. The node is a DroppedItem with its life switched off:
	## no falling, no footing checks, and OUT of the loot group so the gaze
	## can never target the thing in your own hand.
	var wrap := Node3D.new()
	wrap.name = "HeldLook"
	var di := DroppedItem.make(item.duplicate(true))
	di.set_meta("held_look", true)
	var box := _look_aabb(di)
	var sz := box.size
	var longest := maxf(sz.x, maxf(sz.y, sz.z))
	var sc := 1.0
	if longest > HELD_MAX_M:
		sc = HELD_MAX_M / longest
	elif longest > 0.001 and longest < HELD_MIN_M:
		sc = HELD_MIN_M / longest
	di.scale = Vector3.ONE * sc
	di.position = -box.get_center() * sc
	## The long way points forward (+X -> -Z, like a blade) and then turns
	## HELD_TURN toward the middle of the view: held straight out, a skull
	## showed only the back of its head and a bone only its end.
	if sz.x >= sz.y and sz.x >= sz.z:
		wrap.rotation_degrees.y = 90.0 + HELD_TURN
	elif sz.z >= sz.y:
		wrap.rotation_degrees.y = HELD_TURN
	else:
		wrap.rotation_degrees.y = HELD_TURN * 0.5   ## a tall thing stays upright, turned a little
	wrap.add_child(di)
	## Its life is switched off AFTER it is ready, not before: READY is where
	## the engine turns physics processing on for any script that has a
	## _physics_process, and _ready is where DroppedItem joins the loot group.
	if di.is_inside_tree():
		_quiet_look(di)
	else:
		di.ready.connect(_quiet_look.bind(di), CONNECT_ONE_SHOT)
	return wrap


func _quiet_look(di: Node) -> void:
	if di == null or not is_instance_valid(di):
		return
	di.remove_from_group("dropped_items")
	di.set_physics_process(false)
	di.set_process(false)


func _look_aabb(n: Node3D) -> AABB:
	## Bounds of every mesh under `n`, in n's own space, off the tree.
	var out := AABB()
	var first := true
	var stack: Array = [[n, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var top: Array = stack.pop_back()
		var node: Node = top[0]
		var xf: Transform3D = top[1]
		for c in node.get_children():
			if not (c is Node3D):
				continue
			var cx: Transform3D = xf * (c as Node3D).transform
			var mi := c as MeshInstance3D
			if mi != null and mi.mesh != null:
				var a := mi.mesh.get_aabb()
				for k in 8:
					var corner := a.position + Vector3(
							a.size.x if (k & 1) != 0 else 0.0,
							a.size.y if (k & 2) != 0 else 0.0,
							a.size.z if (k & 4) != 0 else 0.0)
					var p := cx * corner
					if first:
						out = AABB(p, Vector3.ZERO)
						first = false
					else:
						out = out.expand(p)
			stack.append([c, cx])
	return out


func _update_held(delta: float) -> void:
	if held_vm == null:
		return
	## The fist is taken back by steel, a tool or the bow: the thing goes
	## home to the pack by itself. (Every "sheathed = false" in this file --
	## the hunch, a draw-slash, a guard, the saddle -- lands here.)
	if _holding() and (not sheathed or current_weapon != "sword"):
		_stow_held("the hand is needed")
	var show := _holding() and reach_phase == "" and sheath_t >= 0.5 and kd_phase == ""
	held_vm.visible = show and cam_mode != "tp"
	if tp_held != null:
		tp_held.visible = show and cam_mode == "tp"
	if not held_vm.visible:
		return
	## At rest: breathe with the shared gait, like the other held things.
	var bob := Vector3(
		sin(gait_phase + PI) * 0.015 * gait_amount,
		absf(sin(gait_phase + PI)) * 0.013 * gait_amount + sin(bob_t) * 0.0018,
		0.0)
	held_vm.position = held_vm.position.lerp(HELD_REST_POS + bob, delta * 10.0)
	held_vm.rotation_degrees = held_vm.rotation_degrees.lerp(
		HELD_REST_ROT + Vector3(0, 0, sin(gait_phase + PI) * 1.0 * gait_amount), delta * 10.0)


func _wear_skull(item: Dictionary) -> void:
	## A skull in the helmet slot is worn as a HOOD: the braincase scaled to
	## sit over the head, the muzzle forward and tipped down over the brow,
	## the sockets where the eyes would look out. Built from the same boxes
	## DroppedItem lays on the ground, so the skull you picked up is the
	## skull you are wearing. (Lemon, 2026-09-14: "make the bear skull
	## equipable on the head".)
	if tp_skull != null and is_instance_valid(tp_skull):
		tp_skull.queue_free()
	tp_skull = null
	if item.is_empty() or tp_head == null:
		return
	var w := float(item.get("bone_w", 0.30))
	var L := float(item.get("bone_len", 0.36))
	## DroppedItem._build_bone("skull"): braincase L*0.52 x w*0.72 x w*0.82
	## centred at (-L*0.20, w*0.36, 0), muzzle out along +X.
	## Big enough to go OVER the head both ways: wider than the skull of the
	## wearer and deeper than it, so the face is inside the braincase and the
	## muzzle stands proud of the brow like a visor.
	var sc := clampf(maxf(0.34 / maxf(w * 0.82, 0.05), 0.27 / maxf(L * 0.52, 0.05)), 0.6, 2.8)
	tp_skull = Node3D.new()
	tp_skull.name = "WornSkull"
	tp_head.add_child(tp_skull)
	tp_skull.rotation_degrees = Vector3(-14.0, 0.0, 0.0)   ## muzzle down over the brow
	var look := _held_look(item)     ## sized for a fist: undo that, size for a head
	var di: Node3D = look.get_child(0) as Node3D
	di.scale = Vector3.ONE * sc
	di.position = Vector3.ZERO
	look.rotation_degrees = Vector3(0.0, 90.0, 0.0)   ## +X -> -Z, forward
	tp_skull.add_child(look)
	## put the braincase centre over the head's centre, a touch up and back
	var bc := Vector3(-L * 0.20, w * 0.36, 0.0) * sc
	var bc_rot := Vector3(bc.z, bc.y, -bc.x)          ## after the 90-degree turn
	look.position = Vector3(0.0, 0.17, 0.02) - bc_rot
	tp_skull.visible = true


''' + "## ============= Dropped items (Q to toss, look + E to reclaim) ==============\n",
        "func _hold_from_pack(idx: int) -> void:",
    ),
])

# ---- the skull is a helmet; and a bone draws as a bone whatever its slot ----
patch("scripts/CarcassBody.gd", [
    (
        '''	var item := {
		"name": bone_item_name(kind, animal),
		"weight": bone_weight(kind, len_m),
		"count": 1,
		"slot": "",
		"keep": true,
		"bone": kind,
''',
        '''	## A SKULL IS A HELM (Lemon, 2026-09-14): it carries the helmet slot, so
	## a click in the pack wears it, and a few per cent of bone between you
	## and a claw. The other bones are plain loot.
	var item := {
		"name": bone_item_name(kind, animal),
		"weight": bone_weight(kind, len_m),
		"count": 1,
		"slot": "helmet" if kind == "skull" else "",
		"protect": 0.03 if kind == "skull" else 0.0,
		"keep": true,
		"bone": kind,
''',
        '"slot": "helmet" if kind == "skull" else "",',
    ),
])

patch("scripts/DroppedItem.gd", [
    (
        '''	var slot := String(item.get("slot", ""))
	var mat_id := String(item.get("material", ""))
	var nm := String(item.get("name", ""))
''',
        '''	var slot := String(item.get("slot", ""))
	var mat_id := String(item.get("material", ""))
	var nm := String(item.get("name", ""))
	## A bone is a bone whatever berth it fits: a skull wears the helmet slot
	## now, and must not come out of the pack as an iron cap.
	if item.has("bone"):
		_build_bone(String(item["bone"]))
		return
''',
        "\t## A bone is a bone whatever berth it fits",
    ),
])

print("done")
