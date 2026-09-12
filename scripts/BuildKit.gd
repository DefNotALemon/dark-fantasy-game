class_name BuildKit
extends RefCounted

## ===========================================================================
## THE BUILD KIT — scripts/BuildKit.gd
##
## Every piece you can put in the world, and every prefab that is just a list
## of pieces. Medieval, cute, BotW-ish: timber frame over plaster, thatch,
## fieldstone. Boxes, because the rest of Myrkfell is boxes.
##
## TWO LAYERS, ON PURPOSE:
##
##   PIECES   `BuildKit.build(id, mat)` -> a StaticBody3D you can place.
##            Every piece is 2 m on the module grid, so anything snaps to
##            anything.
##
##   PREFABS  `BuildKit.prefab(id)` -> an Array of {piece, pos, rot, mat}.
##            A prefab is NOT a special object: stamping a cottage places
##            forty ordinary pieces, and you can then delete its door and put
##            a window there. Nothing about a stamped building is frozen.
##
## THE STARDEW HOOK: `BuildKit.COST[id]` is the material bill for a piece,
## in the same item names Player's inventory uses ("Plank", "Log", "Stone",
## "Thatch"). God mode ignores it. A survival build mode reads it, checks the
## pack, and spends. That is the only thing the two modes need to disagree
## about — the catalog, the meshes and the snapping are shared.
## ===========================================================================

const MODULE := 2.0           ## the grid: everything is a multiple of this
const WALL_H := 3.0
const WALL_T := 0.28
const FLOOR_T := 0.22

# ===========================================================================
#  Materials
# ===========================================================================

const MATS := {
	"wood":    {"label": "Timber",   "color": Color(0.44, 0.31, 0.19)},
	"plaster": {"label": "Plaster",  "color": Color(0.82, 0.78, 0.66)},
	"stone":   {"label": "Fieldstone", "color": Color(0.52, 0.52, 0.50)},
	"dark":    {"label": "Dark oak", "color": Color(0.26, 0.18, 0.12)},
	"thatch":  {"label": "Thatch",   "color": Color(0.70, 0.58, 0.30)},
	"slate":   {"label": "Slate",    "color": Color(0.32, 0.34, 0.38)},
	"cloth":   {"label": "Cloth",    "color": Color(0.74, 0.28, 0.24)},
}

static var _mat_cache := {}


static func mat(id: String, tint := 0.0) -> StandardMaterial3D:
	var key := "%s_%.2f" % [id, tint]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var base: Color = (MATS.get(id, MATS["wood"]) as Dictionary)["color"]
	if tint != 0.0:
		base = base.lightened(tint) if tint > 0.0 else base.darkened(-tint)
	var m := StandardMaterial3D.new()
	m.albedo_color = base
	m.roughness = 1.0
	m.metallic = 0.0
	m.metallic_specular = 0.05   ## Godot 4 name; `specular` is a 3.x remap and warns
	_mat_cache[key] = m
	return m


# ===========================================================================
#  The catalog
# ===========================================================================
## id -> {label, cat, mat (default), size (footprint in modules, for snapping)}

const PIECES := {
	## --- walls -------------------------------------------------------------
	"wall":        {"label": "Wall",           "cat": "Walls",  "mat": "plaster"},
	"wall_door":   {"label": "Wall + door",    "cat": "Walls",  "mat": "plaster"},
	"wall_window": {"label": "Wall + window",  "cat": "Walls",  "mat": "plaster"},
	"wall_half":   {"label": "Half wall",      "cat": "Walls",  "mat": "stone"},
	"wall_arch":   {"label": "Archway",        "cat": "Walls",  "mat": "stone"},
	"corner_post": {"label": "Corner post",    "cat": "Walls",  "mat": "dark"},

	## --- floors and roofs ---------------------------------------------------
	"floor":       {"label": "Floor",          "cat": "Floors", "mat": "wood"},
	"floor_stone": {"label": "Flagstones",     "cat": "Floors", "mat": "stone"},
	"stair":       {"label": "Stair",          "cat": "Floors", "mat": "wood"},
	"ramp":        {"label": "Ramp",           "cat": "Floors", "mat": "wood"},
	"roof":        {"label": "Roof panel",     "cat": "Roofs",  "mat": "thatch"},
	"roof_gable":  {"label": "Gable end",      "cat": "Roofs",  "mat": "plaster"},
	"roof_ridge":  {"label": "Ridge cap",      "cat": "Roofs",  "mat": "thatch"},
	"roof_flat":   {"label": "Flat roof",      "cat": "Roofs",  "mat": "wood"},

	## --- structure ----------------------------------------------------------
	"post":        {"label": "Post",           "cat": "Frame",  "mat": "dark"},
	"beam":        {"label": "Beam",           "cat": "Frame",  "mat": "dark"},
	"fence":       {"label": "Fence",          "cat": "Frame",  "mat": "wood"},
	"gate":        {"label": "Gate",           "cat": "Frame",  "mat": "wood"},
	"palisade":    {"label": "Palisade",       "cat": "Frame",  "mat": "dark"},
	"stone_wall":  {"label": "Stone wall",     "cat": "Frame",  "mat": "stone"},

	## --- props --------------------------------------------------------------
	"well":        {"label": "Well",           "cat": "Props",  "mat": "stone"},
	"firepit":     {"label": "Fire pit",       "cat": "Props",  "mat": "stone"},
	"crate":       {"label": "Crate",          "cat": "Props",  "mat": "wood"},
	"barrel":      {"label": "Barrel",         "cat": "Props",  "mat": "wood"},
	"haystack":    {"label": "Haystack",       "cat": "Props",  "mat": "thatch"},
	"cart":        {"label": "Cart",           "cat": "Props",  "mat": "wood"},
	"stall":       {"label": "Market stall",   "cat": "Props",  "mat": "cloth"},
	"signpost":    {"label": "Signpost",       "cat": "Props",  "mat": "wood"},
	"bench":       {"label": "Bench",          "cat": "Props",  "mat": "wood"},
	"planter":     {"label": "Planter bed",    "cat": "Props",  "mat": "wood"},
	"dock":        {"label": "Dock section",   "cat": "Props",  "mat": "wood"},
	"cairn":       {"label": "Cairn",          "cat": "Props",  "mat": "stone"},
}

## The Stardew hook. Item names match Player's inventory strings.
const COST := {
	"wall":        {"Plank": 4},
	"wall_door":   {"Plank": 6},
	"wall_window": {"Plank": 5},
	"wall_half":   {"Stone": 4},
	"wall_arch":   {"Stone": 8},
	"corner_post": {"Log": 1},
	"floor":       {"Plank": 3},
	"floor_stone": {"Stone": 4},
	"stair":       {"Plank": 4},
	"ramp":        {"Plank": 3},
	"roof":        {"Plank": 2, "Thatch": 4},
	"roof_gable":  {"Plank": 4},
	"roof_ridge":  {"Thatch": 3},
	"roof_flat":   {"Plank": 4},
	"post":        {"Log": 1},
	"beam":        {"Log": 1},
	"fence":       {"Stick": 4},
	"gate":        {"Plank": 3},
	"palisade":    {"Log": 2},
	"stone_wall":  {"Stone": 5},
	"well":        {"Stone": 12, "Plank": 4},
	"firepit":     {"Stone": 6},
	"crate":       {"Plank": 3},
	"barrel":      {"Plank": 4},
	"haystack":    {"Thatch": 6},
	"cart":        {"Plank": 8, "Log": 2},
	"stall":       {"Plank": 6, "Cloth": 3},
	"signpost":    {"Plank": 2},
	"bench":       {"Plank": 3},
	"planter":     {"Plank": 4},
	"dock":        {"Plank": 5, "Log": 2},
	"cairn":       {"Stone": 8},
}


static func categories() -> Array[String]:
	var out: Array[String] = []
	for id in PIECES:
		var c := str((PIECES[id] as Dictionary)["cat"])
		if not out.has(c):
			out.append(c)
	return out


static func pieces_in(cat: String) -> Array[String]:
	var out: Array[String] = []
	for id in PIECES:
		if str((PIECES[id] as Dictionary)["cat"]) == cat:
			out.append(id)
	return out


static func default_mat(piece: String) -> String:
	return str((PIECES.get(piece, {"mat": "wood"}) as Dictionary).get("mat", "wood"))


static func label_of(piece: String) -> String:
	return str((PIECES.get(piece, {"label": piece}) as Dictionary).get("label", piece))


# ===========================================================================
#  Building one piece
# ===========================================================================

static func build(piece: String, mat_id := "") -> StaticBody3D:
	var body := StaticBody3D.new()
	build_into(body, piece, mat_id)
	return body


static func build_into(body: StaticBody3D, piece: String, mat_id := "") -> StaticBody3D:
	## Fills an EXISTING body — BuiltPiece is its own StaticBody3D and a body
	## inside a body owns none of its parent's shapes.
	var m := mat_id if mat_id != "" else default_mat(piece)
	body.collision_layer = 1
	body.collision_mask = 0
	match piece:
		"wall":        _wall(body, m, "solid")
		"wall_door":   _wall(body, m, "door")
		"wall_window": _wall(body, m, "window")
		"wall_half":   _slab(body, m, Vector3(MODULE, 1.1, WALL_T), Vector3(0, 0.55, 0))
		"wall_arch":   _wall(body, m, "arch")
		"corner_post": _slab(body, m, Vector3(0.34, WALL_H, 0.34), Vector3(0, WALL_H * 0.5, 0))
		"floor":       _floor(body, m)
		"floor_stone": _floor(body, m)
		"stair":       _stair(body, m)
		"ramp":        _ramp(body, m)
		"roof":        _roof(body, m)
		"roof_gable":  _gable(body, m)
		"roof_ridge":  _slab(body, m, Vector3(MODULE, 0.28, 0.62), Vector3(0, 0.14, 0))
		"roof_flat":   _slab(body, m, Vector3(MODULE, 0.24, MODULE), Vector3(0, 0.12, 0))
		"post":        _slab(body, m, Vector3(0.26, WALL_H, 0.26), Vector3(0, WALL_H * 0.5, 0))
		"beam":        _slab(body, m, Vector3(MODULE, 0.26, 0.26), Vector3(0, 0.13, 0))
		"fence":       _fence(body, m)
		"gate":        _gate(body, m)
		"palisade":    _palisade(body, m)
		"stone_wall":  _stone_wall(body, m)
		"well":        _well(body, m)
		"firepit":     _firepit(body, m)
		"crate":       _slab(body, m, Vector3(0.8, 0.8, 0.8), Vector3(0, 0.4, 0), 0.08)
		"barrel":      _barrel(body, m)
		"haystack":    _haystack(body, m)
		"cart":        _cart(body, m)
		"stall":       _stall(body, m)
		"signpost":    _signpost(body, m)
		"bench":       _bench(body, m)
		"planter":     _planter(body, m)
		"dock":        _slab(body, m, Vector3(MODULE, 0.22, MODULE), Vector3(0, -0.11, 0))
		"cairn":       _cairn(body, m)
		_:            _slab(body, m, Vector3(1, 1, 1), Vector3(0, 0.5, 0))
	return body


## --- the one primitive everything is made of -------------------------------

static func _box(parent: Node, size: Vector3, pos: Vector3, mat_id: String,
		tint := 0.0, rot := Vector3.ZERO, collide := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat(mat_id, tint)
	parent.add_child(mi)
	if collide and parent is CollisionObject3D:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = pos
		cs.rotation = rot
		parent.add_child(cs)
	return mi


static func _slab(b: StaticBody3D, m: String, size: Vector3, pos: Vector3, tint := 0.0) -> void:
	_box(b, size, pos, m, tint)


## --- walls ------------------------------------------------------------------

static func _wall(b: StaticBody3D, m: String, style: String) -> void:
	var half := MODULE * 0.5
	match style:
		"solid":
			_box(b, Vector3(MODULE, WALL_H, WALL_T), Vector3(0, WALL_H * 0.5, 0), m)
		"door":
			## posts either side, lintel over
			_box(b, Vector3(0.55, WALL_H, WALL_T), Vector3(-half + 0.275, WALL_H * 0.5, 0), m)
			_box(b, Vector3(0.55, WALL_H, WALL_T), Vector3(half - 0.275, WALL_H * 0.5, 0), m)
			_box(b, Vector3(MODULE, 0.85, WALL_T), Vector3(0, WALL_H - 0.425, 0), m)
			## the door itself, set back a hair
			_box(b, Vector3(0.86, 2.05, 0.10), Vector3(0, 1.03, -0.06), "dark", 0.05, Vector3.ZERO, false)
		"window":
			_box(b, Vector3(MODULE, 1.05, WALL_T), Vector3(0, 0.525, 0), m)
			_box(b, Vector3(MODULE, 0.95, WALL_T), Vector3(0, WALL_H - 0.475, 0), m)
			_box(b, Vector3(0.45, 1.0, WALL_T), Vector3(-half + 0.225, 1.55, 0), m)
			_box(b, Vector3(0.45, 1.0, WALL_T), Vector3(half - 0.225, 1.55, 0), m)
			## shutters
			_box(b, Vector3(0.14, 1.0, 0.09), Vector3(-0.62, 1.55, -0.18), "dark", 0.0, Vector3.ZERO, false)
			_box(b, Vector3(0.14, 1.0, 0.09), Vector3(0.62, 1.55, -0.18), "dark", 0.0, Vector3.ZERO, false)
		"arch":
			_box(b, Vector3(0.5, WALL_H, WALL_T), Vector3(-half + 0.25, WALL_H * 0.5, 0), m)
			_box(b, Vector3(0.5, WALL_H, WALL_T), Vector3(half - 0.25, WALL_H * 0.5, 0), m)
			_box(b, Vector3(MODULE, 0.5, WALL_T), Vector3(0, WALL_H - 0.25, 0), m)
			_box(b, Vector3(1.3, 0.28, WALL_T + 0.02), Vector3(0, WALL_H - 0.62, 0), m, -0.1)
			return
	if style == "solid" or style == "window" or style == "door":
		## timber frame over the plaster: two uprights, a sill, a plate, a brace
		_box(b, Vector3(0.20, WALL_H, WALL_T + 0.10), Vector3(-half + 0.10, WALL_H * 0.5, 0),
			"dark", 0.0, Vector3.ZERO, false)
		_box(b, Vector3(0.20, WALL_H, WALL_T + 0.10), Vector3(half - 0.10, WALL_H * 0.5, 0),
			"dark", 0.0, Vector3.ZERO, false)
		_box(b, Vector3(MODULE, 0.22, WALL_T + 0.10), Vector3(0, WALL_H - 0.11, 0),
			"dark", 0.0, Vector3.ZERO, false)
		_box(b, Vector3(MODULE, 0.18, WALL_T + 0.10), Vector3(0, 0.09, 0),
			"dark", 0.0, Vector3.ZERO, false)
		if style == "solid":
			_box(b, Vector3(2.4, 0.16, WALL_T + 0.08), Vector3(0, WALL_H * 0.5, 0),
				"dark", 0.0, Vector3(0, 0, 0.92), false)


static func _floor(b: StaticBody3D, m: String) -> void:
	_box(b, Vector3(MODULE, FLOOR_T, MODULE), Vector3(0, -FLOOR_T * 0.5, 0), m)
	## plank seams
	for i in range(4):
		_box(b, Vector3(MODULE, 0.03, 0.05), Vector3(0, 0.005, -0.75 + i * 0.5),
			m, -0.18, Vector3.ZERO, false)


static func _stair(b: StaticBody3D, m: String) -> void:
	var steps := 6
	for i in range(steps):
		var h := WALL_H * float(i + 1) / float(steps)
		var d := MODULE / float(steps)
		_box(b, Vector3(MODULE, h, d), Vector3(0, h * 0.5, MODULE * 0.5 - d * (i + 0.5)), m,
			-0.02 * float(i % 2))


static func _ramp(b: StaticBody3D, m: String) -> void:
	var ang := atan2(WALL_H, MODULE * 2.0)
	var l := sqrt(WALL_H * WALL_H + (MODULE * 2.0) * (MODULE * 2.0))
	_box(b, Vector3(MODULE, 0.24, l), Vector3(0, WALL_H * 0.5, 0), m, 0.0, Vector3(-ang, 0, 0))


static func _roof(b: StaticBody3D, m: String) -> void:
	## one sloped panel; two of them back to back make a gable roof
	var ang := 0.62
	var l := MODULE * 1.35
	_box(b, Vector3(MODULE, 0.34, l), Vector3(0, sin(ang) * l * 0.5, -cos(ang) * l * 0.5),
		m, 0.0, Vector3(ang, 0, 0))
	_box(b, Vector3(MODULE, 0.10, l * 0.9), Vector3(0, sin(ang) * l * 0.5 + 0.2,
		-cos(ang) * l * 0.5), m, -0.15, Vector3(ang, 0, 0), false)


static func _gable(b: StaticBody3D, m: String) -> void:
	## a stepped triangle — five courses, because a box cannot be a triangle
	var courses := 5
	for i in range(courses):
		var f := float(i) / float(courses)
		var w := MODULE * (1.0 - f)
		_box(b, Vector3(w, 0.42, WALL_T), Vector3(0, 0.21 + i * 0.42, 0), m, -0.02 * i)


static func _fence(b: StaticBody3D, m: String) -> void:
	_box(b, Vector3(0.16, 1.25, 0.16), Vector3(-MODULE * 0.5 + 0.08, 0.62, 0), m)
	_box(b, Vector3(0.16, 1.25, 0.16), Vector3(MODULE * 0.5 - 0.08, 0.62, 0), m)
	_box(b, Vector3(MODULE, 0.12, 0.10), Vector3(0, 0.95, 0), m, -0.08)
	_box(b, Vector3(MODULE, 0.12, 0.10), Vector3(0, 0.55, 0), m, -0.08)


static func _gate(b: StaticBody3D, m: String) -> void:
	_box(b, Vector3(0.24, 2.3, 0.24), Vector3(-MODULE * 0.5 + 0.12, 1.15, 0), "dark")
	_box(b, Vector3(0.24, 2.3, 0.24), Vector3(MODULE * 0.5 - 0.12, 1.15, 0), "dark")
	_box(b, Vector3(MODULE, 0.22, 0.22), Vector3(0, 2.3, 0), "dark")
	for i in range(5):
		_box(b, Vector3(0.14, 1.5, 0.10), Vector3(-0.7 + i * 0.35, 0.75, 0), m)


static func _palisade(b: StaticBody3D, m: String) -> void:
	for i in range(5):
		var h := 3.1 + sin(float(i) * 2.1) * 0.18
		_box(b, Vector3(0.34, h, 0.34), Vector3(-0.8 + i * 0.4, h * 0.5, 0), m, -0.04 * (i % 3))
	_box(b, Vector3(MODULE, 0.16, 0.16), Vector3(0, 2.2, 0.22), "wood", 0.0, Vector3.ZERO, false)


static func _stone_wall(b: StaticBody3D, m: String) -> void:
	var rows := 4
	for r in range(rows):
		var n := 3 if r % 2 == 0 else 4
		for i in range(n):
			var w := MODULE / float(n)
			_box(b, Vector3(w * 0.95, 0.36, 0.55),
				Vector3(-MODULE * 0.5 + w * (i + 0.5), 0.18 + r * 0.36, 0), m,
				-0.10 + 0.05 * ((i + r) % 4))


static func _well(b: StaticBody3D, m: String) -> void:
	for i in range(8):
		var a := TAU * float(i) / 8.0
		_box(b, Vector3(0.55, 0.85, 0.36), Vector3(cos(a) * 0.85, 0.42, sin(a) * 0.85), m,
			-0.08 + 0.05 * (i % 3), Vector3(0, -a, 0))
	_box(b, Vector3(0.22, 2.0, 0.22), Vector3(-0.75, 1.4, 0), "wood")
	_box(b, Vector3(0.22, 2.0, 0.22), Vector3(0.75, 1.4, 0), "wood")
	_box(b, Vector3(2.1, 0.24, 1.5), Vector3(0, 2.5, 0), "thatch", 0.0, Vector3(0.25, 0, 0), false)
	_box(b, Vector3(2.1, 0.24, 1.5), Vector3(0, 2.5, 0), "thatch", -0.08, Vector3(-0.25, 0, 0), false)
	_box(b, Vector3(1.7, 0.14, 0.14), Vector3(0, 2.05, 0), "wood", 0.0, Vector3.ZERO, false)
	_box(b, Vector3(0.34, 0.36, 0.34), Vector3(0, 1.55, 0), "dark", 0.0, Vector3.ZERO, false)


static func _firepit(b: StaticBody3D, m: String) -> void:
	for i in range(9):
		var a := TAU * float(i) / 9.0
		_box(b, Vector3(0.36, 0.3, 0.3), Vector3(cos(a) * 0.8, 0.15, sin(a) * 0.8), m,
			-0.1 + 0.06 * (i % 3), Vector3(0, -a, 0))
	_box(b, Vector3(0.9, 0.12, 0.9), Vector3(0, 0.06, 0), "dark", 0.0, Vector3.ZERO, false)
	for i in range(4):
		_box(b, Vector3(0.14, 0.7, 0.14), Vector3(0, 0.35, 0), "wood", -0.1,
			Vector3(0.5, TAU * float(i) / 4.0, 0), false)


static func _barrel(b: StaticBody3D, m: String) -> void:
	_box(b, Vector3(0.62, 0.9, 0.62), Vector3(0, 0.45, 0), m)
	_box(b, Vector3(0.70, 0.10, 0.70), Vector3(0, 0.22, 0), "dark", 0.0, Vector3.ZERO, false)
	_box(b, Vector3(0.70, 0.10, 0.70), Vector3(0, 0.68, 0), "dark", 0.0, Vector3.ZERO, false)


static func _haystack(b: StaticBody3D, m: String) -> void:
	_box(b, Vector3(2.0, 1.1, 2.0), Vector3(0, 0.55, 0), m)
	_box(b, Vector3(1.5, 0.8, 1.5), Vector3(0, 1.45, 0), m, 0.05)
	_box(b, Vector3(0.9, 0.6, 0.9), Vector3(0, 2.1, 0), m, 0.10, Vector3.ZERO, false)
	_box(b, Vector3(0.12, 2.9, 0.12), Vector3(0, 1.45, 0), "wood", 0.0, Vector3.ZERO, false)


static func _cart(b: StaticBody3D, m: String) -> void:
	_box(b, Vector3(1.5, 0.30, 2.4), Vector3(0, 0.75, 0), m)
	_box(b, Vector3(1.5, 0.55, 0.14), Vector3(0, 1.02, -1.13), m, -0.05)
	_box(b, Vector3(1.5, 0.55, 0.14), Vector3(0, 1.02, 1.13), m, -0.05)
	_box(b, Vector3(0.14, 0.55, 2.4), Vector3(-0.68, 1.02, 0), m, -0.05)
	_box(b, Vector3(0.14, 0.55, 2.4), Vector3(0.68, 1.02, 0), m, -0.05)
	for s in [-1.0, 1.0]:
		_box(b, Vector3(0.16, 1.1, 1.1), Vector3(0.82 * s, 0.55, 0.3), "dark", 0.0,
			Vector3.ZERO, false)
	_box(b, Vector3(0.16, 0.16, 1.6), Vector3(0, 0.7, -1.9), "wood", 0.0,
		Vector3(0.22, 0, 0), false)


static func _stall(b: StaticBody3D, m: String) -> void:
	for x in [-1.0, 1.0]:
		for z in [-0.7, 0.7]:
			_box(b, Vector3(0.16, 2.3, 0.16), Vector3(x, 1.15, z), "wood")
	_box(b, Vector3(2.3, 0.16, 1.7), Vector3(0, 1.0, 0), "wood")
	_box(b, Vector3(2.6, 0.14, 1.05), Vector3(0, 2.45, -0.45), m, 0.0, Vector3(0.32, 0, 0), false)
	_box(b, Vector3(2.6, 0.14, 1.05), Vector3(0, 2.45, 0.45), m, -0.1, Vector3(-0.32, 0, 0), false)


static func _signpost(b: StaticBody3D, m: String) -> void:
	_box(b, Vector3(0.16, 2.4, 0.16), Vector3(0, 1.2, 0), m)
	_box(b, Vector3(1.1, 0.28, 0.08), Vector3(0.5, 2.0, 0), m, 0.12, Vector3.ZERO, false)
	_box(b, Vector3(0.9, 0.24, 0.08), Vector3(-0.4, 1.55, 0), m, 0.08, Vector3.ZERO, false)


static func _bench(b: StaticBody3D, m: String) -> void:
	_box(b, Vector3(1.8, 0.12, 0.45), Vector3(0, 0.48, 0), m)
	_box(b, Vector3(0.14, 0.48, 0.40), Vector3(-0.75, 0.24, 0), m, -0.08)
	_box(b, Vector3(0.14, 0.48, 0.40), Vector3(0.75, 0.24, 0), m, -0.08)


static func _planter(b: StaticBody3D, m: String) -> void:
	_box(b, Vector3(MODULE, 0.34, MODULE), Vector3(0, 0.17, 0), m, -0.05)
	_box(b, Vector3(MODULE - 0.3, 0.20, MODULE - 0.3), Vector3(0, 0.32, 0), "dark", -0.05,
		Vector3.ZERO, false)


static func _cairn(b: StaticBody3D, m: String) -> void:
	var y := 0.0
	for i in range(6):
		var s := 0.85 - i * 0.11
		_box(b, Vector3(s, 0.30, s * 0.85), Vector3(sin(i * 2.3) * 0.08, y + 0.15,
			cos(i * 1.7) * 0.08), m, -0.12 + 0.05 * (i % 3), Vector3(0, i * 0.7, 0))
		y += 0.28


# ===========================================================================
#  Prefabs — a building is a list of pieces, nothing more
# ===========================================================================

const PREFABS := {
	"hut":        {"label": "Hut",          "cat": "Homes"},
	"cottage":    {"label": "Cottage",      "cat": "Homes"},
	"longhouse":  {"label": "Longhouse",    "cat": "Homes"},
	"manor":      {"label": "Manor (2 up)", "cat": "Homes"},
	"barn":       {"label": "Barn",         "cat": "Farm"},
	"shed":       {"label": "Shed",         "cat": "Farm"},
	"field":      {"label": "Ploughed field","cat": "Farm"},
	"pen":        {"label": "Animal pen",   "cat": "Farm"},
	"tower":      {"label": "Watchtower",   "cat": "Town"},
	"market":     {"label": "Market row",   "cat": "Town"},
	"wellyard":   {"label": "Well + square","cat": "Town"},
	"dock":       {"label": "Dock",         "cat": "Town"},
	"campfire":   {"label": "Camp",         "cat": "Wild"},
	"shrine":     {"label": "Shrine",       "cat": "Wild"},
	"ruin":       {"label": "Ruined wall",  "cat": "Wild"},
}


static func prefab_categories() -> Array[String]:
	var out: Array[String] = []
	for id in PREFABS:
		var c := str((PREFABS[id] as Dictionary)["cat"])
		if not out.has(c):
			out.append(c)
	return out


static func prefabs_in(cat: String) -> Array[String]:
	var out: Array[String] = []
	for id in PREFABS:
		if str((PREFABS[id] as Dictionary)["cat"]) == cat:
			out.append(id)
	return out


static func prefab(id: String) -> Array:
	## -> [{piece, pos: Vector3, rot: float (radians, y), mat: String}]
	match id:
		"hut":       return _house(1, 1, 1, "thatch", "plaster")
		"cottage":   return _house(2, 2, 1, "thatch", "plaster")
		"longhouse": return _house(4, 2, 1, "thatch", "wood")
		"manor":     return _house(3, 3, 2, "slate", "plaster")
		"barn":      return _barn()
		"shed":      return _house(1, 2, 1, "thatch", "wood")
		"field":     return _field()
		"pen":       return _pen()
		"tower":     return _tower()
		"market":    return _market()
		"wellyard":  return _wellyard()
		"dock":      return _dock()
		"campfire":  return _camp()
		"shrine":    return _shrine()
		"ruin":      return _ruin()
	return []


static func _p(piece: String, pos: Vector3, rot := 0.0, m := "") -> Dictionary:
	return {"piece": piece, "pos": pos, "rot": rot,
		"mat": m if m != "" else default_mat(piece)}


static func _house(w: int, d: int, storeys: int, roof_mat: String, wall_mat: String) -> Array:
	## w x d MODULES. Origin is the centre of the footprint, on the ground.
	var out: Array = []
	var hw := float(w) * MODULE * 0.5
	var hd := float(d) * MODULE * 0.5
	for s in range(storeys):
		var y := float(s) * WALL_H
		## floor grid (the ground storey gets one too — a plank floor)
		for ix in range(w):
			for iz in range(d):
				out.append(_p("floor", Vector3(-hw + MODULE * (ix + 0.5), y + (0.0 if s == 0 else 0.0),
					-hd + MODULE * (iz + 0.5)), 0.0, "wood"))
		## the four walls
		for ix in range(w):
			var x := -hw + MODULE * (ix + 0.5)
			var north := "wall"
			var south := "wall"
			if s == 0 and ix == w / 2:
				south = "wall_door"
			elif ix % 2 == 1:
				north = "wall_window"
				south = "wall_window"
			out.append(_p(north, Vector3(x, y, -hd), 0.0, wall_mat))
			out.append(_p(south, Vector3(x, y, hd), PI, wall_mat))
		for iz in range(d):
			var z := -hd + MODULE * (iz + 0.5)
			var side := "wall_window" if iz % 2 == 0 else "wall"
			out.append(_p(side, Vector3(-hw, y, z), PI * 0.5, wall_mat))
			out.append(_p(side, Vector3(hw, y, z), -PI * 0.5, wall_mat))
		## corner posts
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				out.append(_p("corner_post", Vector3(hw * sx, y, hd * sz), 0.0, "dark"))
	## the roof: two slopes running the long way, gable ends, a ridge
	var top := float(storeys) * WALL_H
	for ix in range(w):
		var x := -hw + MODULE * (ix + 0.5)
		out.append(_p("roof", Vector3(x, top, -hd + 0.1), 0.0, roof_mat))
		out.append(_p("roof", Vector3(x, top, hd - 0.1), PI, roof_mat))
		out.append(_p("roof_ridge", Vector3(x, top + cos(0.62) * 0.0 + sin(0.62) * MODULE * 1.35,
			0.0), 0.0, roof_mat))
	for iz in range(d):
		var z := -hd + MODULE * (iz + 0.5)
		out.append(_p("roof_gable", Vector3(-hw, top, z), PI * 0.5, wall_mat))
		out.append(_p("roof_gable", Vector3(hw, top, z), -PI * 0.5, wall_mat))
	return out


static func _barn() -> Array:
	var out := _house(3, 3, 1, "thatch", "wood")
	out.append(_p("haystack", Vector3(4.4, 0, 1.2)))
	out.append(_p("cart", Vector3(-4.6, 0, -1.6), 0.4))
	out.append(_p("crate", Vector3(4.2, 0, -2.4)))
	out.append(_p("barrel", Vector3(3.4, 0, -2.9)))
	return out


static func _field() -> Array:
	var out: Array = []
	for ix in range(4):
		for iz in range(3):
			out.append(_p("planter", Vector3(-3.0 + ix * MODULE, 0, -2.0 + iz * MODULE)))
	for ix in range(5):
		out.append(_p("fence", Vector3(-4.0 + ix * MODULE, 0, -3.4)))
		out.append(_p("fence", Vector3(-4.0 + ix * MODULE, 0, 3.4)))
	for iz in range(4):
		out.append(_p("fence", Vector3(-5.0, 0, -3.0 + iz * MODULE), PI * 0.5))
		out.append(_p("fence", Vector3(5.0, 0, -3.0 + iz * MODULE), PI * 0.5))
	out.append(_p("signpost", Vector3(-5.2, 0, -3.6)))
	return out


static func _pen() -> Array:
	var out: Array = []
	for i in range(4):
		out.append(_p("fence", Vector3(-3.0 + i * MODULE, 0, -3.0)))
		out.append(_p("fence", Vector3(-3.0 + i * MODULE, 0, 3.0)))
		out.append(_p("fence", Vector3(-4.0, 0, -2.0 + i * MODULE), PI * 0.5))
		out.append(_p("fence", Vector3(4.0, 0, -2.0 + i * MODULE), PI * 0.5))
	out.append(_p("gate", Vector3(3.0, 0, -3.0)))
	out.append(_p("haystack", Vector3(-2.4, 0, 1.6)))
	return out


static func _tower() -> Array:
	var out := _house(1, 1, 3, "slate", "stone")
	## strip the thatch look: a flat top with a low parapet instead
	var keep: Array = []
	for p in out:
		var pd: Dictionary = p
		if str(pd["piece"]).begins_with("roof"):
			continue
		keep.append(pd)
	var top := 3.0 * WALL_H
	keep.append(_p("roof_flat", Vector3(0, top, 0), 0.0, "stone"))
	for s in [-1.0, 1.0]:
		keep.append(_p("wall_half", Vector3(0, top + 0.24, MODULE * 0.5 * s), 0.0, "stone"))
		keep.append(_p("wall_half", Vector3(MODULE * 0.5 * s, top + 0.24, 0), PI * 0.5, "stone"))
	return keep


static func _market() -> Array:
	var out: Array = []
	for i in range(4):
		out.append(_p("stall", Vector3(-6.0 + i * 4.0, 0, -3.0)))
		out.append(_p("stall", Vector3(-6.0 + i * 4.0, 0, 3.0), PI))
		out.append(_p("crate", Vector3(-5.0 + i * 4.0, 0, -1.6)))
		out.append(_p("barrel", Vector3(-4.4 + i * 4.0, 0, 1.6)))
	out.append(_p("signpost", Vector3(0, 0, 0)))
	return out


static func _wellyard() -> Array:
	var out: Array = []
	out.append(_p("well", Vector3.ZERO))
	for ix in range(-2, 3):
		for iz in range(-2, 3):
			if absi(ix) + absi(iz) <= 3 and not (ix == 0 and iz == 0):
				out.append(_p("floor_stone", Vector3(ix * MODULE, 0.02, iz * MODULE)))
	out.append(_p("bench", Vector3(-3.2, 0, 1.6), 0.3))
	out.append(_p("bench", Vector3(3.2, 0, -1.6), PI + 0.3))
	return out


static func _dock() -> Array:
	var out: Array = []
	for i in range(6):
		out.append(_p("dock", Vector3(0, 0, -5.0 + i * MODULE)))
		if i % 2 == 0:
			out.append(_p("post", Vector3(-1.1, -1.4, -5.0 + i * MODULE)))
			out.append(_p("post", Vector3(1.1, -1.4, -5.0 + i * MODULE)))
	out.append(_p("crate", Vector3(0.6, 0.11, 4.4)))
	out.append(_p("barrel", Vector3(-0.6, 0.11, 3.8)))
	return out


static func _camp() -> Array:
	return [
		_p("firepit", Vector3.ZERO),
		_p("bench", Vector3(0, 0, 2.0), PI),
		_p("bench", Vector3(0, 0, -2.0)),
		_p("crate", Vector3(2.2, 0, 1.2)),
		_p("signpost", Vector3(-2.6, 0, -1.4)),
	]


static func _shrine() -> Array:
	var out: Array = []
	out.append(_p("cairn", Vector3.ZERO))
	for i in range(4):
		var a := TAU * float(i) / 4.0 + PI * 0.25
		out.append(_p("post", Vector3(cos(a) * 2.2, 0, sin(a) * 2.2), 0.0, "dark"))
	for ix in range(-1, 2):
		for iz in range(-1, 2):
			out.append(_p("floor_stone", Vector3(ix * MODULE, 0.02, iz * MODULE)))
	return out


static func _ruin() -> Array:
	var out: Array = []
	out.append(_p("wall_arch", Vector3(0, 0, -2.0), 0.0, "stone"))
	out.append(_p("stone_wall", Vector3(-2.0, 0, -2.0), 0.0, "stone"))
	out.append(_p("stone_wall", Vector3(-3.0, 0, -1.0), PI * 0.5, "stone"))
	out.append(_p("stone_wall", Vector3(-3.0, 0, 1.0), PI * 0.5, "stone"))
	out.append(_p("wall_half", Vector3(2.0, 0, -2.0), 0.0, "stone"))
	out.append(_p("cairn", Vector3(1.4, 0, 1.6)))
	return out
